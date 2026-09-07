# Phase 2 — Seam Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the seam layer in `dexpace-core` — the provider registry, both transport seams, the
async pivot, the cancellation token, the close/ownership contract, the wire-codec seam and its
failure hierarchy, and the operation-input projection — satisfying `SEAM-1`–`SEAM-30`.

**Architecture:** A seam is three artifacts and no fourth: a documented duck type, a `.conforms?`
predicate on the seam's own module, and an RBS interface in that seam's `sig/` file. Every piece of
shared mutable state is one frozen `Data` snapshot held in one instance variable, replaced wholesale
under a `Thread::Mutex` on the write path and read with no lock on the read path. One
`Dexpace::Registry` class implements `SEAM-5`–`SEAM-9`'s five branches once and is instantiated
three times, one per surviving seam.

**Tech Stack:** Ruby 3.2–4.0 (development on 4.0.6), no runtime dependencies, Minitest, RBS + Steep,
RuboCop with phase 0's five custom cops plus a sixth this phase adds, SimpleCov, YARD.

**Spec:** `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md`

## Global Constraints

Every task's requirements implicitly include this section. Values are copied verbatim from the
design and the governing documents.

- **`dexpace-core` gains no dependency and no allowlist entry.** The gemspec keeps zero
  `add_dependency` lines (`SEAM-1`, `NFR-1`). This phase adds **no `require`** of any kind beyond
  `require_relative`: `Thread`, `Thread::Mutex`, `Thread::Queue`, `Fiber`, `Data` and `Regexp` are
  core classes, and `uri` is already required by phase 1's `Dexpace::URL`. **`rubygems` is not on phase
  0's twelve-name allowlist and this phase does not put it there** — see Task 8.
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`;
  `docs/knowledge/notes/formatting-and-tooling.md`). No `# typed:` sigil anywhere.
- **Banned, and each is a blocking cop:** `Time.parse`/`Date.parse`/`DateTime.parse`;
  `URI::DEFAULT_PARSER` and the `URI.parse`/`URI.join`/`URI.split` family — **use
  `URI::RFC3986_PARSER` explicitly**, and in this phase reach `URI` only through phase 1's
  `Dexpace::URL`; any argument to `downcase`/`upcase`/`capitalize`/`swapcase` and `casecmp?`;
  `Timeout.timeout`, `Thread#raise`, `Thread#kill`.
- **Inside `lib/dexpace/async/**` and `lib/dexpace/serde/**`, write `::Thread`, `::Queue`,
  `::Mutex`, `::SizedQueue`, `::ConditionVariable` and `::JSON`** — never the bare name. Task 3
  ships the cop that enforces it. Verified on 3.2.11 and 4.0.6: a bare `Thread` inside
  `module Dexpace::Async` resolves to Ruby's `Thread` until `dexpace-async-thread` is required and
  to `Dexpace::Async::Thread` afterwards, and core's own suite never requires that gem.
- **A `Thread::Mutex` is held across a flag flip or a snapshot swap and across nothing else.** Never
  across a callback, a `warn`, a `#release`, a `#close` or any operation that may suspend. Verified
  on 3.2.11, 3.4.10 and 4.0.6: `Thread::Mutex` is non-reentrant (`ThreadError: deadlock; recursive
  locking`) and its ownership is per-fiber (`ThreadError: deadlock; lock already owned by another
  fiber belonging to the same thread`).
- **The pivot never carries a value through a queue.** Verified on all three interpreters:
  `Thread::Queue#pop` returns `nil` for a `timeout:` expiry, for a closed queue and for a pushed
  `nil` alike. The queue is a wake-up signal; the settled outcome lives in an instance variable.
- **Regexp timeouts are per-pattern**: `Regexp.new(source, timeout:)`, never `Regexp.timeout=`.
- **No `.build` is a bare `new` wrapper**, and this phase's boundary on that rule: a `Data` that is
  **public API** validates in its `initialize` — `Dexpace::Async::Settlement` and
  `Dexpace::Operation` both do — while a **`private_constant` snapshot** (`Registry::State`,
  `Registry::Claim`, `Cancellation::Source::State`) does not include `Dexpace::Model` and exposes
  no `.build` (deviation P2-9).
- **Two error classes, two levels deep, both including `Dexpace::Error`:** `Dexpace::SeamError` for
  a seam in a state the caller must fix (zero or ambiguous providers, version skew) and phase 1's
  `Dexpace::InvalidArgumentError` for a caller mistake in an argument (a conflicting install, a
  non-conforming provider, a malformed template). Never define `Dexpace::ArgumentError`.
- **Formatting:** double quotes, 2-space indent, **100 columns**, `consistent_comma` trailing
  commas, leading-dot chains, `MethodLength: 25` with `CountAsOne`, `ParameterLists: 4`,
  `BlockNesting: 3`.
- **Tests:** Minitest only, `FooTest < DexpaceTestCase`, `test "..." do` blocks, `test/` mirroring
  `lib/` one file per file, `assert_equal(expected, actual)` in that order, every test passing alone
  and in any order, the seed never overridden. Each test file's header comment names the requirement
  IDs it exercises.
- **Every public constant gets three artifacts in the same task**: the implementation, a YARD block
  that explains *why* and never restates a type (`documentation/42d8cbf4`), and an `.rbs` mirror at
  the same path under `sig/`.
- **No commit step appears in any task.** The manager commits once per phase.
- **Never edit** `docs/product-spec/`, `docs/sdk-design-ruby/`, `docs/knowledge/harvested/`.

### Commands

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/<path>_test.rb   # one suite, red or green
(cd gems/dexpace-core && bundle exec rake test)                     # the gem's whole suite
bundle exec rake                                                    # all seventeen gates
bundle exec rake cops:test                                          # the custom cops' own suite
mise exec ruby@3.2.11 -- bundle exec rake test:gems                 # the floor, locally
bundle exec rake surface:regenerate                                 # deliberate; Task 16 only
```

### What was verified during planning, and how to re-verify it

**Every `ruby` fence in this document was extracted and run**, not a prototype it was transcribed
from. The 45 `ruby` fences were written to the 42 files they name — Task 14's two fragments splice
into Task 13's `operation.rb`, and Task 12's two one-line error subclasses are prose here and were
written out; Task 3's cop is the one fence that is not part of the gem tree — on top of stand-ins for phase 0's `DexpaceTestCase` and phase 1's `Model`, `Builder`,
`Error`, `InvalidArgumentError`, `Method`, `URL`, `Query`, `Headers`, `RequestOptions`, `Request`
and `PercentEncoding`. The result, identical on **3.2.11, 3.4.10 and 4.0.6** and warning-free under
`ruby -w`:

```
179 runs, 567 assertions, 0 failures, 0 errors, 0 skips   # 575 assertions on 4.0.6
```

The run count is identical on all three, and identical across six random seeds. The assertion count
differs on 4.0.6 in four suites — `async/future_test.rb`, `error/cancelled_error_test.rb`,
`serde/error_test.rb` and `transport_test.rb` — because 3.2, 3.3 and 3.4 resolve Minitest 5.x
(5.25.1 on 3.2.11, 5.25.4 on 3.4.10) and 4.0 resolves 6.0.0, and the two count some
`assert_operator`/`refute_operator` and `refute_respond_to` calls differently. So three of the four
matrix rows see the lower assertion count and only the 4.0 row sees the higher one. No test is
skipped and none behaves differently; the same tests pass on all three.

**Every test that guards a concurrency fix was also run red, on all three interpreters.** A
regression test that passes under the bug it names is worse than no test, so each guard was reverted
in the built tree and re-run. Reverting, and the message each produces:

| Fix reverted | Guard | What it says |
|---|---|---|
| `#complete_resolution` releases the claim on a `rescue StandardError` path, not in `ensure` | `registry_test.rb` | "the registry wedged into a spin instead of re-evaluating" |
| `#swap`'s `ensure` restores the captured snapshot wholesale | `registry_test.rb` | "swap restored a closed gate and wedged the registry" |
| `#swap`'s `ensure` restores `factories` from the snapshot | `registry_test.rb` | "swap reverted a require-time registration, which no later require can redo. Expected: `[:key]`, Actual: `[]`" |
| `#resolve` does not record the claim's owner | `registry_test.rb`, three tests | "`[Dexpace::SeamError]` exception expected, not `<fatal>` … No live threads left. Deadlock?" |
| the factory or `.conforms?` call moves back under `@write` | `registry_test.rb`, two tests | `ThreadError: deadlock; recursive locking` |
| `Completer#await` does not detach what it armed | `cancellation_test.rb` | "the await armed a hook on a client-lifetime source and never detached it. Expected: 0, Actual: 1" |
| `#request_cancel` notifies before it settles | `async/completer_test.rb` | "cancellation must always publish an outcome" |
| `Hooks.notify` becomes a bare `each` in `Source#cancel` | `cancellation_test.rb` | "Expected: `[:first, :third]`, Actual: `[:first]`" |
| `Hooks.notify` becomes a bare `each` in `Completer#settle` | `async/completer_test.rb` | "Expected: `[:first, :third]`, Actual: `[:first]`" |
| `Cancellation.over`'s `is_a?(Source)` guard | `cancellation_test.rb` | "`Dexpace::InvalidArgumentError` expected but nothing was raised" |
| `deliver`'s delivery branch written as a method-level `else` | `transport/async_over_test.rb` | "the future never settled and `#value` would block" |
| `#on_cancel`'s per-registration guard becomes one token-level flag | `async_transport/sync_over_test.rb` | "a waiter never unblocked: SEAM-18's interruption clause is violated" |

Two of those fail as a **hang** rather than an assertion and are the ones to run under `timeout`:
the `SEAM-18` two-waiter test, and the re-entrant-resolve trio, whose reverted failure is Ruby's own
deadlock detector — a `fatal`, not a `SeamError` — because every thread in the process ends up
asleep on one gate.

**One thing that run was not.** It is not the seventeen gates: no RBS, Steep, SimpleCov or YARD is
installed here. Task 3's cop *was* executed — on RuboCop 1.90.0 through phase 0's verbatim
`CopCase` harness, 17 runs, 61 assertions, 0 failures — but not against the version `VERSIONS` will
pin, which is why Task 3 Step 5 is still a real check.

---

## File Structure

Grouped by responsibility. Every file below is created by exactly one task, and every `lib/` file
gets its `sig/` mirror and its `test/` mirror in that same task -- except `lib/dexpace/hooks.rb`,
which is a `private_constant` and therefore not public API by this repository's own definition. Paths are relative to
`gems/dexpace-core/` unless stated otherwise.

**The seam failure types (Task 1).** `lib/dexpace/error/seam_error.rb`,
`lib/dexpace/error/closed_error.rb`, `lib/dexpace/error/cancelled_error.rb`. First, because every
other task raises through them.

**Lifecycle (Task 2).** `lib/dexpace/closeable.rb` — `Dexpace::Closeable` and
`Dexpace.close_quietly`. Second, because the pivot's orphan close and every fake response need it.

**The sixth cop (Task 3).** `.rubocop/cops/dexpace/qualified_core_constant.rb` and cases added to
`.rubocop/test/cops_test.rb`, both at the repository root. Before any file under
`lib/dexpace/async/`, so that tree is written under the cop from its first line.

**Cancellation (Task 4).** `lib/dexpace/hooks.rb`, `lib/dexpace/cancellation.rb`,
`lib/dexpace/cancellation/source.rb`. `hooks.rb` is a `private_constant` and therefore the one
`lib/` file in this phase with no `sig/` mirror and no YARD gate entry.

**The async pivot (Tasks 5–6).** `lib/dexpace/async/settlement.rb`,
`lib/dexpace/async/completer.rb`, `lib/dexpace/async/future.rb`; then Task 6's two structural
proofs, which need `test/support/probe_scheduler.rb`.

**Discovery (Tasks 7–8).** `lib/dexpace/registry.rb`, split so that the five resolution branches and
the version-skew guard are separately reviewable.

**The transport seams (Tasks 9–11).** `lib/dexpace/transport.rb`, `lib/dexpace/async_transport.rb`,
and the `SEAM-18` bridges inside them; with `test/support/fake_transport.rb`,
`test/support/fake_async_transport.rb` and `test/support/warning_capture.rb`.

**The codec seam (Task 12).** `lib/dexpace/serde/error.rb`,
`lib/dexpace/serde/serialization_error.rb`, `lib/dexpace/serde/deserialization_error.rb`,
`lib/dexpace/serde.rb`, `test/support/fake_codec.rb`.

**The projection seam (Tasks 13–14).** `lib/dexpace/operation.rb`, split so the descriptor's
validation and `SEAM-27`'s composition are separately reviewable.

**Wiring and closing (Tasks 15–16).** `lib/dexpace.rb` and `sig/dexpace.rbs` (modified), then the
repository-root `test/fixtures/surface/dexpace-core.txt`, the checklist, and `CLAUDE.md`.

---

## Task 1: The seam failure types

**Requirement IDs:** `SEAM-15` (the documented post-close failure mode), and the error vocabulary
`SEAM-5`, `SEAM-6` and `SEAM-18` raise through. **Design:** "What a seam is in this port, stated
once" — *Seam-level failures*.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/error/seam_error.rb`,
  `gems/dexpace-core/lib/dexpace/error/closed_error.rb`,
  `gems/dexpace-core/lib/dexpace/error/cancelled_error.rb`, and the three `sig/` mirrors at
  `gems/dexpace-core/sig/dexpace/error/{seam_error,closed_error,cancelled_error}.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`, `gems/dexpace-core/sig/dexpace.rbs`
- Test: `gems/dexpace-core/test/dexpace/error/{seam_error,closed_error,cancelled_error}_test.rb`

**Interfaces:**
- Consumes: phase 1's `Dexpace::Error` (a module) and `Dexpace::InvalidArgumentError`.
- Produces: `Dexpace::SeamError < ::StandardError`, `Dexpace::ClosedError < ::StandardError`, and
  `Dexpace::CancelledError < ::StandardError` with `#reason`. All three include `Dexpace::Error`.
  Tasks 2, 4, 5, 7, 8, 9, 10, 11, 13 and 14 raise them.

- [ ] **Step 1: Write the failing tests**

`gems/dexpace-core/test/dexpace/error/cancelled_error_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# SEAM-18's interruption clause read as cooperative cancellation (design P2-4). The reason is a
# typed object rather than a message, because XCUT-2 requires timeout and cancellation to be told
# apart out-of-band; RETRY-23/RETRY-24 read the same field in phase 6.
class DexpaceCancelledErrorTest < DexpaceTestCase
  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::CancelledError
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::CancelledError, caught)
  end

  test "carries the cancellation reason as the object it was given" do
    reason = Object.new

    assert_same(reason, Dexpace::CancelledError.new(reason).reason)
  end

  test "reads without a reason" do
    assert_nil(Dexpace::CancelledError.new.reason)
    assert_equal("the operation was cancelled", Dexpace::CancelledError.new.message)
  end

  # XCUT-4 puts transport errors in Ruby's IOError family. A cancellation is not a transport
  # failure, so it deliberately stays outside it (design P2-4).
  test "is not in Ruby's IOError family" do
    refute_operator(Dexpace::CancelledError, :<, ::IOError)
  end
end
```

`gems/dexpace-core/test/dexpace/error/seam_error_test.rb` asserts the same `rescue Dexpace::Error`
catch, that `Dexpace::SeamError < ::StandardError`, and that it is **not** an `::ArgumentError` —
the distinction the design draws between a seam in a bad state and a bad argument.
`gems/dexpace-core/test/dexpace/error/closed_error_test.rb` asserts the catch and the superclass,
with a header comment naming `SEAM-15` as the MAY this port takes explicitly.

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/cancelled_error_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::CancelledError`.

- [ ] **Step 3: Write the three error files**

`lib/dexpace/error/seam_error.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # Raised when a seam is in a state the caller has to fix but did not pass in: no provider is
  # registered, more than one is (SEAM-5), or an adapter was built against an incompatible
  # dexpace-core (design §2.3's version-skew guard).
  #
  # Deliberately not an ArgumentError. `error-handling/5a185ba9` asks for a standard-library
  # exception where one exactly fits, and ArgumentError exactly fits a bad argument -- which is
  # what Dexpace::InvalidArgumentError is for, and is what a conflicting install raises. Nothing
  # was wrong with the argument here; the process is missing a provider.
  class SeamError < ::StandardError
    include Dexpace::Error
  end
end
```

`lib/dexpace/error/closed_error.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # Raised by a seam implementation when it is used after #close.
  #
  # SEAM-15 is a MAY -- "further send calls MAY have undefined behavior ... A port MAY choose a
  # mode but SHOULD document it" -- and this port chooses and documents one, because "undefined"
  # in Ruby means whatever NoMethodError the internals happen to produce.
  class ClosedError < ::StandardError
    include Dexpace::Error
  end
end
```

`lib/dexpace/error/cancelled_error.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # Raised when a cancelled operation is observed: Cancellation#check!, Future#value on a cancelled
  # future, and the blocking half of SEAM-18's bridge.
  #
  # The reason is carried as an object rather than folded into the message because XCUT-2 requires
  # a timeout and a cancellation to be told apart by ambient state, never by matching a string.
  # Phase 6's RETRY-23/RETRY-24 classification reads #reason, not #message.
  class CancelledError < ::StandardError
    include Dexpace::Error

    # @return [Object, nil] whatever the canceller supplied, untouched
    attr_reader :reason

    def initialize(reason = nil)
      @reason = reason
      super(reason.nil? ? "the operation was cancelled" : "the operation was cancelled: #{reason}")
    end
  end
end
```

- [ ] **Step 4: Write the three `sig/` mirrors**

`sig/dexpace/error/cancelled_error.rbs`:

```rbs
module Dexpace
  class CancelledError < ::StandardError
    include Dexpace::Error

    attr_reader reason: untyped

    def initialize: (?untyped reason) -> void
  end
end
```

`sig/dexpace/error/seam_error.rbs` and `sig/dexpace/error/closed_error.rbs` each declare the class,
its superclass and the `include`, with no members.

- [ ] **Step 5: Add the three `require_relative`s to `lib/dexpace.rb`**

Immediately after phase 1's `error/invalid_argument_error` line, in the order
`error/seam_error`, `error/closed_error`, `error/cancelled_error`.

- [ ] **Step 6: Run the tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/cancelled_error_test.rb`
Expected: PASS. Then the other two suites, then `bundle exec rake rbs:validate steep`.

---

## Task 2: `Dexpace::Closeable` and `Dexpace.close_quietly`

**Requirement IDs:** `SEAM-14`, `SEAM-25`; `XCUT-13` and `XCUT-22` are phase 9's to disposition and
are implemented here. **Design:** "`Dexpace::Closeable`, `Dexpace.close_quietly` and
`Dexpace::ClosedError`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/closeable.rb`,
  `gems/dexpace-core/sig/dexpace/closeable.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`, `gems/dexpace-core/sig/dexpace.rbs`
- Test: `gems/dexpace-core/test/dexpace/closeable_test.rb`

**Interfaces:**
- Consumes: `Dexpace::SeamError` (Task 1).
- Produces: `Dexpace::Closeable`, a module supplying `#initialize_closeable(owned: true)`,
  `#close`, `#closed?`, `#owned?` and a private `#release` the including class must define; and
  `Dexpace.close_quietly(resource)`. Tasks 5, 9 and 11 call `close_quietly`; every fake response in
  Tasks 5, 9, 10 and 11 includes `Closeable`.

- [ ] **Step 1: Write the failing test**

`gems/dexpace-core/test/dexpace/closeable_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"

# SEAM-14, SEAM-25, XCUT-13, XCUT-22. The latch is a boolean flipped under a Thread::Mutex held
# only across the flip: Ruby's Mutex is per-fiber-owned and non-reentrant (verified on 3.2.11,
# 3.4.10 and 4.0.6), so holding it across a #release that may suspend deadlocks two fibers of one
# thread.
class DexpaceCloseableTest < DexpaceTestCase
  class Spy
    include Dexpace::Closeable

    attr_reader :releases

    def initialize(owned: true)
      @releases = 0
      initialize_closeable(owned: owned)
    end

    private

    def release
      @releases += 1
    end
  end

  class Raising
    include Dexpace::Closeable

    def initialize
      initialize_closeable(owned: true)
    end

    private

    def release
      raise ::IOError, "the socket is already gone"
    end
  end

  class Forgetful
    include Dexpace::Closeable
  end

  test "close releases exactly once under contention" do
    spy = Spy.new

    16.times.map { ::Thread.new { spy.close } }.each(&:join)

    assert_equal(1, spy.releases)
    assert_predicate_by_respond_to(spy, :closed?)
  end

  test "a borrowed resource latches but is never released" do
    spy = Spy.new(owned: false)

    spy.close

    assert_equal(0, spy.releases)
    assert(spy.closed?, "XCUT-22: the SDK component is closed even though the resource is not")
  end

  test "a release that raises still leaves the latch flipped and propagates once" do
    raising = Raising.new

    assert_raises(::IOError) { raising.close }

    assert(raising.closed?)
    assert_nil(raising.close, "BODY-27: no second release is attempted")
  end

  test "an including class that never initialised the latch fails loudly" do
    error = assert_raises(Dexpace::SeamError) { Forgetful.new.close }

    assert_match(/initialize_closeable/, error.message)
  end

  test "close_quietly is null-safe and tolerates a resource with no close" do
    assert_nil(Dexpace.close_quietly(nil))
    assert_nil(Dexpace.close_quietly(Object.new))
  end

  test "close_quietly closes what it is given and swallows a close failure" do
    spy = Spy.new

    Dexpace.close_quietly(spy)

    assert_equal(1, spy.releases)
    # DEF-27: the rescued error is dropped until phase 4 supplies the suppressed trail and phase 5
    # the instrumentation diagnostic. Asserted rather than left as a comment, so the day a route
    # lands this test is what has to change.
    assert_nil(Dexpace.close_quietly(Raising.new))
  end

  # Minitest sends past `private`, verified on 5.25.1/3.2.11 and 6.0.0/4.0.6, so visibility is
  # asserted with respond_to? and never with assert_predicate (phase 1's finding).
  test "release is private and the latch queries are public" do
    spy = Spy.new

    refute_respond_to(spy, :release)
    assert_respond_to(spy, :close)
    assert_respond_to(spy, :closed?)
    assert_respond_to(spy, :owned?)
  end

  private

  def assert_predicate_by_respond_to(object, name)
    assert_respond_to(object, name)
    assert(object.public_send(name))
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/closeable_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Closeable`.

- [ ] **Step 3: Write `lib/dexpace/closeable.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "error/seam_error"

module Dexpace
  # The close contract, written down once because six requirements state it in six vocabularies --
  # SEAM-14, SEAM-25, HTTP-43, ASYNC-15..ASYNC-17, XCUT-13 and XCUT-22 -- and Ruby has no Closeable
  # interface and no try-with-resources to infer it from.
  #
  # Three properties, and each is here rather than in each implementation because each was
  # implemented differently at three sites in the reference build. (1) Close is idempotent, latched
  # rather than flag-checked: whoever flips the latch runs #release and everyone else returns.
  # (2) Ownership is a construction-time fact, not a close-time judgement -- a component takes a
  # resource through an entry point that either builds it or borrows it, and records which in a
  # frozen boolean. (3) Close never blocks on an interrupt-sensitive wait, which is free here
  # because this port delivers no interrupts (design §8.3).
  #
  # The latch mutex is created in #initialize_closeable rather than lazily, because a lazily
  # created mutex is itself the race it exists to prevent.
  module Closeable
    # Call from the including class's #initialize. `owned:` is SEAM-14's and XCUT-22's distinction:
    # false means the caller supplied the resource and the SDK must never release it.
    def initialize_closeable(owned: true)
      @dexpace_owned = owned ? true : false
      @dexpace_closed = false
      @dexpace_close_mutex = ::Thread::Mutex.new
      nil
    end

    def owned?
      ensure_closeable_initialized
      @dexpace_owned
    end

    def closed?
      ensure_closeable_initialized
      @dexpace_closed
    end

    # Idempotent and ownership-aware. The mutex is held across the flag flip and nothing else:
    # Ruby's Mutex is per-fiber-owned and non-reentrant, so holding it across a #release that may
    # suspend deadlocks two fibers of one thread. A #release that raises still leaves the latch
    # flipped, so no second release is attempted and the failure propagates exactly once.
    def close
      ensure_closeable_initialized
      first = @dexpace_close_mutex.synchronize do
        next false if @dexpace_closed

        @dexpace_closed = true
      end
      return nil unless first
      return nil unless @dexpace_owned

      release
      nil
    end

    private

    def release
      raise NotImplementedError,
            "#{self.class} includes Dexpace::Closeable and must define a private #release"
    end

    def ensure_closeable_initialized
      return if defined?(@dexpace_close_mutex) && @dexpace_close_mutex

      raise Dexpace::SeamError,
            "#{self.class} includes Dexpace::Closeable but never called #initialize_closeable"
    end
  end

  # The single sanctioned exit for a close on a cleanup or discard path: null-safe (CFG-21's last
  # clause), tolerant of an object with no #close, and never raising over a primary failure.
  #
  # Design §3.7 gives the rescued error two disposal routes and phase 2 has neither: the suppressed
  # trail is Dexpace::Error#suppressed, deferred to phase 4 (DEF-24), and the http.instrumentation.*
  # diagnostic is §8.1's facade, phase 5. Building either here would fix an interface a later phase
  # must be free to shape, so the error is dropped and DEF-27 names the two phases that supply the
  # routes. The two loud exceptions §3.7 names are honoured from the start and do not come through
  # here: an explicit #close by a caller propagates, and a #release raising during the latched close
  # above propagates once.
  #
  # @return [nil] always, so a caller cannot branch on a cleanup outcome
  def self.close_quietly(resource)
    return nil if resource.nil?
    return nil unless resource.respond_to?(:close)

    begin
      resource.close
    rescue ::StandardError
      nil # DEF-27
    end
    nil
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/closeable.rbs`**

```rbs
module Dexpace
  module Closeable
    def initialize_closeable: (?owned: bool) -> nil
    def owned?: () -> bool
    def closed?: () -> bool
    def close: () -> nil

    private

    def release: () -> void
    def ensure_closeable_initialized: () -> void
  end

  def self.close_quietly: (untyped resource) -> nil
end
```

- [ ] **Step 5: Add `require_relative "dexpace/closeable"` to `lib/dexpace.rb`**

After the three error files from Task 1.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/closeable_test.rb`
Expected: PASS, 7 tests. Then `bundle exec rake rbs:validate steep`.

---

## Task 3: `Dexpace/QualifiedCoreConstant` — the sixth custom cop

**Requirement IDs:** none directly; it mechanises the Design §9 Addendum A1 the design records, and
protects `SEAM-16`/`SEAM-17`'s implementation from a bug that cannot fail in the tree that contains
it. **Design:** "Design §9 Addendum — the sixth cop"; verified Ruby fact 2.

**Files:**
- Create: `.rubocop/cops/dexpace/qualified_core_constant.rb` (repository root)
- Modify: `.rubocop.yml` (the `require:` list and the new cop's `Include:`),
  `.rubocop/test/cops_test.rb` (phase 0's data-driven suite)
- Test: `.rubocop/test/cops_test.rb`

**Interfaces:**
- Consumes: phase 0's `.rubocop/test/cop_case.rb` harness, which parses a source string into a
  `RuboCop::ProcessedSource`, runs the cop through a `Commissioner` and asserts on the offense list.
- Produces: `RuboCop::Cop::Dexpace::QualifiedCoreConstant`, blocking from Task 4 onward.

- [ ] **Step 1: Add the cop's cases to phase 0's data-driven suite**

Seven rejected sources and six accepted ones, appended to the table `.rubocop/test/cops_test.rb`
already drives. Rejected, each as a one-file source with the standard header:
`Thread.new` inside `module Dexpace; module Async`; `Queue.new`, `Mutex.new`, `SizedQueue.new` and
`ConditionVariable.new` in the same place; `JSON.generate` inside `module Dexpace; module Serde`;
and `Thread.new` inside the compact form `module Dexpace::Async`, which must be flagged too — the
lexical path is the same however it is written.

Accepted, and each must produce **no** offense: `::Thread.new` and `::Queue.new` inside
`Dexpace::Async`; `::JSON.generate` inside `Dexpace::Serde`; a bare `Thread.new` inside
`module Dexpace; module Transport`; a bare `Thread.new` at the top level with no enclosing module
at all; and `Dexpace::Async::Thread.new` written out in full.

`SHADOWED` is deliberately one list for both watched namespaces rather than one list each, so a
bare `JSON` inside `Dexpace::Async` is flagged even though only `Dexpace::Serde` reopens `JSON`.
Two per-namespace lists would be a second rule to keep in step for no gain, and the false positive
costs one `::`.

**The accepted half is what proves the cop does not simply reject every occurrence of the six
names**, which is exactly what it did before the namespace check existed.

- [ ] **Step 2: Run the cop suite to confirm it fails**

Run: `bundle exec rake cops:test`
Expected: FAIL — `uninitialized constant RuboCop::Cop::Dexpace::QualifiedCoreConstant`.

- [ ] **Step 3: Write `.rubocop/cops/dexpace/qualified_core_constant.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # Inside `module Dexpace::Async` and `module Dexpace::Serde`, a bare `Thread`, `Queue`,
      # `Mutex`, `SizedQueue`, `ConditionVariable` or `JSON` is a silent time bomb: it resolves to
      # Ruby's class until the adapter gem that defines `Dexpace::Async::Thread` or
      # `Dexpace::Serde::JSON` is required, and to that module afterwards.
      #
      # Verified on Ruby 3.2.11 and 4.0.6: before the adapter loads, a bare `Thread` inside
      # `module Dexpace; module Async` is `Thread`; after, it is `Dexpace::Async::Thread`, and
      # `Thread.new` raises `NoMethodError: undefined method 'new' for module
      # Dexpace::Async::Thread`. dexpace-core's own suite never requires that gem, so this is a bug
      # that cannot fail in the tree that contains it -- which is what a cop is for.
      #
      # Scoped by `Include:` in .rubocop.yml to gems/dexpace-core/lib/dexpace/{async,serde}/**/*.rb.
      #
      # The enclosing namespace is checked here rather than left to `Include:` in .rubocop.yml.
      # Phase 0's cop harness runs a bare Commissioner over a fixed path with a Config carrying
      # only TargetRubyVersion, so no `Include:` ever applies to a cop under test -- a cop that
      # relied on path scoping would flag its own accepted case and the suite would say so.
      # `Include:` stays in .rubocop.yml anyway, because it is what keeps the cop off the other
      # five gems during a real run.
      #
      # @example
      #   # bad -- inside module Dexpace; module Async
      #   Queue.new
      #
      #   # good
      #   ::Queue.new
      #
      #   # good -- a different namespace; nothing reopens Dexpace::Transport::Thread
      #   Thread.new
      class QualifiedCoreConstant < RuboCop::Cop::Base
        MSG = "Write `::%<name>s` here: a bare `%<name>s` inside %<namespace>s rebinds to the " \
              "adapter gem's constant once that gem is required."

        SHADOWED = %w[Thread Queue Mutex SizedQueue ConditionVariable JSON].freeze

        WATCHED = [%w[Dexpace Async], %w[Dexpace Serde]].freeze

        def on_const(node)
          return if node.namespace # already qualified: `A::Thread` or `::Thread`
          return unless SHADOWED.include?(node.short_name.to_s)

          namespace = watched_namespace(node)
          return if namespace.nil?

          add_offense(node, message: format(MSG, name: node.short_name, namespace: namespace))
        end

        private

        # @return [String, nil] the watched namespace this node is lexically inside, or nil
        def watched_namespace(node)
          path = lexical_path(node)
          watched = WATCHED.find do |segments|
            path.each_cons(segments.length).any? { |window| window == segments }
          end
          watched&.join("::")
        end

        # Outermost-first, with a compact `module A::B` split into its segments, so that both
        # `module Dexpace; module Async` and `module Dexpace::Async` read the same.
        def lexical_path(node)
          node.each_ancestor(:module, :class)
              .map { |scope| scope.identifier.source }
              .reverse
              .flat_map { |name| name.split("::") }
        end
      end
    end
  end
end
```

- [ ] **Step 4: Register the cop in `.rubocop.yml`**

Add the file to the existing `require:` list alongside phase 0's five, then the cop's own entry with
the two-path `Include:` and a comment naming the design addendum:

```yaml
# Design §9 Addendum A1 (phase 2): a bare Thread/Queue/Mutex/JSON inside these two namespaces
# rebinds to the adapter gem's constant the moment that gem is required, and core's own suite
# never requires it.
Dexpace/QualifiedCoreConstant:
  Enabled: true
  Include:
    - "gems/dexpace-core/lib/dexpace/async/**/*.rb"
    - "gems/dexpace-core/lib/dexpace/serde/**/*.rb"
```

- [ ] **Step 5: Run the cop suite to confirm it passes**

Run: `bundle exec rake cops:test`
Expected: PASS, with the seven rejected sources each producing exactly one offense naming the
constant and the namespace, and the six accepted sources producing none. **If the installed
RuboCop's AST API differs, fix the cop against that version — do not weaken a case.** The
accepted half is what proves the cop does not reject everything.

**The cop has been run, but not against this project's own toolchain.** It was executed through
phase 0's verbatim `CopCase` harness on **RuboCop 1.90.0** during review — 17 runs, 61 assertions,
0 failures, including four cases beyond the thirteen above (a `class` nested inside
`Dexpace::Async`, `class << self` inside `Dexpace::Serde`, and the `::`-qualified counterparts of
both). `RuboCop::Cop::Base#on_const`, `ConstNode#namespace`, `ConstNode#short_name`,
`Node#each_ancestor` and `ClassNode`/`ModuleNode#identifier` are long-stable rubocop-ast API, but
phase 0 pins whatever version `VERSIONS` names and that pin is not 1.90.0 by construction — so this
step is a real check, not a formality.

- [ ] **Step 6: Run RuboCop over the repository**

Run: `bundle exec rubocop --fail-level=convention`
Expected: clean. The cop's `Include:` paths do not exist yet, which is correct: it becomes
load-bearing in Task 5.

---

## Task 4: `Dexpace::Cancellation` and `Cancellation::Source`

**Requirement IDs:** the third argument of both transport seams (`SEAM-11`, `SEAM-16`), `SEAM-13`'s
contract, `SEAM-18`'s interruption clause, `SEAM-30`'s trigger. **Design:** "`Dexpace::Cancellation`
and `Cancellation::Source`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/hooks.rb`,
  `gems/dexpace-core/lib/dexpace/cancellation.rb`,
  `gems/dexpace-core/lib/dexpace/cancellation/source.rb`, and the two `sig/` mirrors for the
  cancellation pair
- Modify: `gems/dexpace-core/lib/dexpace.rb`, `gems/dexpace-core/sig/dexpace.rbs`
- Test: `gems/dexpace-core/test/dexpace/cancellation_test.rb`,
  `gems/dexpace-core/test/dexpace/cancellation/source_test.rb`

**Interfaces:**
- Consumes: `Dexpace::CancelledError` (Task 1), `Dexpace::InvalidArgumentError` (phase 1).
- Produces: `Dexpace::Cancellation` — `.none`, `.source`, `.over(*sources)`, `.any(*tokens)`,
  `#cancelled?`, `#reason`, `#on_cancel { |reason| } -> Subscription`, `#check!`,
  `#merged_with(*others)`, a **protected** `#sources`, and the nested
  `Dexpace::Cancellation::Subscription` with `#detach`; and
  `Dexpace::Cancellation::Source` — `#token`, `#cancel(reason = nil) -> Boolean`, `#cancelled?`,
  `#reason`, `#cancelled_at`, `#on_cancel`, `#off_cancel(hook)`. `Cancellation.new` is private.
  Also `Dexpace::Hooks`, a **`private_constant`** module supplying `Hooks.notify(hooks, argument)`
  — the one notification loop `Cancellation::Source#cancel`, `Completer#settle` and
  `Completer#request_cancel` all run. Tasks 5, 9, 10 and 11 consume all of it.

- [ ] **Step 1: Write the failing tests**

`gems/dexpace-core/test/dexpace/cancellation_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"

# SEAM-11 and SEAM-16's third argument, SEAM-13's contract, SEAM-18's interruption clause and
# SEAM-30's trigger. The state lives on the Source and the token is a facade over one or more of
# them -- the same split as Completer/Future, and for the same reason: Ruby has no package-private
# visibility, so the alternative is a `send` through the boundary this pair exists to draw.
class DexpaceCancellationTest < DexpaceTestCase
  test "none is a shared token that can never be cancelled" do
    assert_same(Dexpace::Cancellation.none, Dexpace::Cancellation.none)
    refute(Dexpace::Cancellation.none.cancelled?)
    assert_nil(Dexpace::Cancellation.none.reason)
    assert_nil(Dexpace::Cancellation.none.check!)
  end

  test "a source cancels its token once and the first reason wins" do
    source = Dexpace::Cancellation.source
    seen = []
    source.token.on_cancel { |reason| seen << reason }

    refute(source.token.cancelled?)
    assert(source.cancel(:deadline))
    refute(source.cancel(:something_else), "cancel is idempotent; the first reason wins")

    assert(source.token.cancelled?)
    assert_equal(:deadline, source.token.reason)
    assert_equal([:deadline], seen)
  end

  test "on_cancel fires immediately when the token is already cancelled" do
    source = Dexpace::Cancellation.source
    source.cancel(:late)
    seen = []

    source.token.on_cancel { |reason| seen << reason }

    assert_equal([:late], seen)
  end

  test "check! raises CancelledError carrying the reason object" do
    source = Dexpace::Cancellation.source
    source.cancel(:stop)

    error = assert_raises(Dexpace::CancelledError) { source.token.check! }

    assert_equal(:stop, error.reason)
  end

  # The reason is latched at cancel time, not read off the first cancelled source in list order.
  # `second` is second in the list and first in time, and #reason must agree with what #on_cancel
  # was handed -- a composed token that disagrees with its own handler is worse than one with no
  # reason at all.
  test "any composes tokens and reports the reason of whichever cancelled first in time" do
    first = Dexpace::Cancellation.source
    second = Dexpace::Cancellation.source
    both = Dexpace::Cancellation.any(first.token, second.token)
    seen = []
    both.on_cancel { |reason| seen << reason }

    refute(both.cancelled?)
    second.cancel(:second)
    first.cancel(:first)

    assert(both.cancelled?)
    assert_equal(:second, both.reason)
    assert_equal([:second], seen)
    raised = assert_raises(Dexpace::CancelledError) { both.check! }
    assert_equal(:second, raised.reason)
  end

  # A shared "something already fired" flag would drop every registration after the first, which is
  # what makes a second waiter on one token block forever (SEAM-18).
  test "every registered block fires, not just the first" do
    source = Dexpace::Cancellation.source
    seen = []
    source.token.on_cancel { seen << :first }
    source.token.on_cancel { seen << :second }

    source.cancel(:go)

    assert_equal(%i[first second], seen)
  end

  test "a deliberate nil reason is still a cancellation" do
    source = Dexpace::Cancellation.source
    seen = []
    source.token.on_cancel { |reason| seen << reason }

    source.cancel

    assert(source.token.cancelled?)
    assert_nil(source.token.reason)
    assert_equal([nil], seen)
  end

  test "every token is frozen, none included, and none's on_cancel is inert" do
    assert(Dexpace::Cancellation.none.frozen?)
    assert(Dexpace::Cancellation.source.token.frozen?)
    assert(Dexpace::Cancellation.any(Dexpace::Cancellation.source.token).frozen?)

    Dexpace::Cancellation.none.on_cancel { flunk("a token with no sources can never fire") }
  end

  # The leak has two halves and either alone is enough to retain a response per request, so both
  # are asserted here against ONE long-lived source. (1) A token subscribes only when a caller
  # registers a callback, so composing costs nothing that outlives the token; subscribing at
  # construction to latch the winner retains one closure per composition. (2) A registration made
  # by Completer#await is detached when the await ends, so a bounded wait retains nothing on an
  # unbounded source; without the detach the closure reaches the Completer and therefore the
  # response it settled with. `.any(client_token, per_call_token)` plus `value(cancellation:)` is
  # exactly what `.any` is for and what phase 5's DEF-28 will do on every request.
  #
  # The second half awaits a future that is NOT yet settled, deliberately: Completer#await returns
  # before arming anything when the future has already settled, so a test that awaits a settled
  # future passes with the leak fully present.
  test "neither composing nor awaiting retains a callback on a long-lived source" do
    client = Dexpace::Cancellation.source

    200.times { Dexpace::Cancellation.any(client.token, Dexpace::Cancellation.source.token) }

    assert_equal(0, client.instance_variable_get(:@hooks).size,
                 "composition subscribed to a source at construction")

    completer = Dexpace::Async::Completer.new
    token = Dexpace::Cancellation.any(client.token, Dexpace::Cancellation.source.token)
    producer = ::Thread.new do
      sleep(0.02)
      completer.fulfil(Object.new)
    end

    completer.future.value(cancellation: token)
    producer.join

    assert_equal(0, client.instance_variable_get(:@hooks).size,
                 "the await armed a hook on a client-lifetime source and never detached it")
  end

  test "on_cancel returns a handle that detaches exactly its own registration" do
    source = Dexpace::Cancellation.source
    seen = []
    kept = source.token.on_cancel { seen << :kept }
    detached = source.token.on_cancel { seen << :detached }

    detached.detach
    assert_nil(detached.detach, "detach is idempotent and returns nil")
    source.cancel(:go)

    assert_equal([:kept], seen)
    assert_nil(kept.detach, "detaching after the source has cancelled is a no-op")
  end

  test "none's on_cancel still answers a handle, so a caller need not special-case it" do
    assert_nil(Dexpace::Cancellation.none.on_cancel { flunk("never fires") }.detach)
  end

  test "the winner is the source that cancelled first in time, across more than two" do
    first, second, third = Array.new(3) { Dexpace::Cancellation.source }
    token = Dexpace::Cancellation.any(first.token, second.token, third.token)
    seen = []
    token.on_cancel { |reason| seen << reason }

    third.cancel(:third)
    second.cancel(:second)
    first.cancel(:first)

    assert_equal(:third, token.reason)
    assert_equal([:third], seen)
  end

  test "sources is protected, so only another token composes on it" do
    refute_respond_to(Dexpace::Cancellation.source.token, :sources)
    assert_raises(::NoMethodError) { Dexpace::Cancellation.source.token.sources }
  end

  test "any of nothing, and any of none, is none" do
    assert_same(Dexpace::Cancellation.none, Dexpace::Cancellation.any)
    assert_same(Dexpace::Cancellation.none, Dexpace::Cancellation.any(Dexpace::Cancellation.none))
  end

  test "any refuses anything that is not a token, naming the class" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Cancellation.any(:nope) }

    assert_match(/Symbol/, error.message)
  end

  # .over is public so phase 5's deadline source can compose here, so it validates like the other
  # two composition entry points. Unguarded it builds a token that raises NoMethodError from inside
  # #cancelled? later, at a call site with no idea what went wrong.
  test "over refuses anything that is not a source, naming the class" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Cancellation.over(:nope) }

    assert_match(/Symbol/, error.message)
  end

  # A raising handler must not silence the ones registered after it. That is the same SEAM-18
  # failure as "a second waiter on one token blocks forever", reached from the write side: the
  # second waiter's handler is never called at all.
  test "one raising handler does not drop the handlers registered after it" do
    source = Dexpace::Cancellation.source
    seen = []
    source.token.on_cancel { seen << :first }
    source.token.on_cancel { raise ::IOError, "a handler blew up" }
    source.token.on_cancel { seen << :third }

    assert_raises(::IOError) { source.cancel(:go) }

    assert_equal(%i[first third], seen)
    assert(source.cancelled?, "the state was published before any handler ran")
    assert_equal(:go, source.reason)
  end

  test "on_cancel without a block is a caller mistake" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Cancellation.source.token.on_cancel }
  end

  test "new is private; .none, .source, .over and .any are the factories" do
    refute_respond_to(Dexpace::Cancellation, :new)
    assert_respond_to(Dexpace::Cancellation, :none)
    assert_respond_to(Dexpace::Cancellation, :source)
    assert_respond_to(Dexpace::Cancellation, :over)
    assert_respond_to(Dexpace::Cancellation, :any)
  end

  test "a source's on_cancel requires a block, exactly as its token's does" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Cancellation.source.on_cancel }
  end

  test "merged_with refuses anything that is not a token" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Cancellation.source.token.merged_with(:nope)
    end
  end
end
```

`gems/dexpace-core/test/dexpace/cancellation/source_test.rb` carries the write side: concurrent
`#cancel` from 16 threads elects exactly one winner (`SEAM-9`'s serialisation rule applied to the
same snapshot shape), `#cancelled?`/`#reason` on the source agree with the token's, and a hook
registered after cancellation fires immediately.

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/cancellation_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Cancellation`.

- [ ] **Step 3: Write `lib/dexpace/hooks.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # Running a list of caller-supplied callbacks, in one place, once.
  #
  # Three sites take the same shape -- Cancellation::Source#cancel, Async::Completer#settle and
  # Async::Completer#request_cancel -- and each publishes state under its mutex and then notifies
  # outside it. Written as a bare `hooks.each { |hook| hook.call(...) }` at each site, ONE raising
  # handler drops every later-registered handler and propagates out to whoever published the
  # state. That is the "a second waiter on one token blocks forever" SEAM-18 failure arriving from
  # the write side: the second waiter's handler is simply never called. Verified on 3.2.11, 3.4.10
  # and 4.0.6.
  #
  # So every hook runs, whatever an earlier one did, and the FIRST failure is re-raised once the
  # whole list has run. Re-raised rather than dropped, because phase 2 has neither disposal route
  # design §3.7 names -- Dexpace::Error#suppressed is phase 4's (DEF-24) and the
  # http.instrumentation.* diagnostic is phase 5's (§8.1) -- and a handler that raises into a void
  # is a bug nothing reports. Re-raising is safe here in a way it is not at the naive site: the
  # state is already published and every other handler has already run, so the raise can no longer
  # leave a token uncancelled or a future unsettled. The failures after the first are dropped until
  # #suppressed exists to carry them; DEF-32 records that and names the phase that closes it.
  #
  # Only StandardError is collected. A ScriptError, a NoMemoryError or a SignalException raised by
  # a handler is not a handler bug to be gathered up and re-raised later.
  module Hooks
    # @param hooks [Array<#call>] the list the caller already stole from under its own lock
    # @param argument [Object] the single argument every hook is called with
    # @return [nil]
    def self.notify(hooks, argument)
      failure = nil
      hooks.each do |hook|
        hook.call(argument)
      rescue ::StandardError => error
        failure ||= error
      end
      raise failure if failure

      nil
    end
  end

  # Not public API: it is a shape three internal call sites share, not a service core offers. A
  # private_constant is still reachable by the unqualified name from anywhere lexically inside
  # `module Dexpace`, which is where all three call sites are -- verified on 3.2.11, 3.4.10 and
  # 4.0.6 -- and unreachable as `Dexpace::Hooks` from outside.
  private_constant :Hooks
end
```

- [ ] **Step 4: Write `lib/dexpace/cancellation.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "error/cancelled_error"
require_relative "error/invalid_argument_error"

module Dexpace
  # A cancellation token: the third argument of both transport seams, the state SEAM-13 asks a
  # blocking transport to honour, and the trigger for SEAM-30's orphaned-response close.
  #
  # The reason is a typed object and never a message string, because XCUT-2 requires a timeout and
  # a cancellation to be told apart by ambient state "even when the runtime represents both with
  # the same exception type" -- which matters in Ruby, where Net::ReadTimeout is distinguishable
  # but Errno::* and IOError are not reliably. Phase 6 classifies on #reason's class.
  #
  # A token is a facade over a frozen list of Sources; the mutable state is theirs. That makes
  # .any a concatenation of source lists rather than a subscription graph, and makes .none a
  # singleton over the empty list that can never be cancelled and allocates nothing per call.
  #
  # What is deliberately absent: deadline-derived tokens and the clock behind them. Those are
  # CFG-15..CFG-21 and phase 5's (DEF-28); .any is the composition point they will use.
  class Cancellation
    private_class_method :new

    # The handle #on_cancel returns. #detach removes that one registration from every source the
    # token observes.
    #
    # A handle rather than `self`, because a registration that cannot be withdrawn is a leak with
    # a polite name: Completer#await registers one per wait on a token the caller may hold for the
    # life of a client, and the closure reaches the Completer and therefore the response it
    # settled with. #detach is idempotent, and a no-op on a source that has already cancelled and
    # cleared its list.
    class Subscription
      # Built by Cancellation#on_cancel and by nothing else.
      def initialize(sources, hook)
        @sources = sources
        @hook = hook
      end

      # @return [nil] always, so a caller cannot branch on a detach outcome
      def detach
        @sources.each { |source| source.off_cancel(@hook) }
        nil
      end
    end

    # @return [Cancellation] the shared, frozen token that is never cancelled
    def self.none = NONE

    # @return [Cancellation::Source] a fresh write side, with its token
    def self.source = Source.new

    # Builds a token over sources directly. Public because phase 5's deadline source composes here
    # and because #merged_with needs a class-level constructor that is not `new`.
    #
    # Public API validates its arguments. Without this guard `Cancellation.over(:nope)` builds a
    # token that raises NoMethodError from inside #cancelled? at some later point, while .any and
    # #merged_with -- the two other composition entry points -- both name the offending class at
    # the call that made the mistake.
    #
    # @raise [Dexpace::InvalidArgumentError] when handed anything but a Source
    def self.over(*sources)
      sources.each do |source|
        next if source.is_a?(Source)

        raise Dexpace::InvalidArgumentError,
              "Cancellation.over accepts Dexpace::Cancellation::Source objects, " \
              "got #{source.class}"
      end
      return NONE if sources.empty?

      new(sources)
    end

    # @raise [Dexpace::InvalidArgumentError] when handed anything but a token
    def self.any(*tokens)
      tokens.each do |token|
        next if token.is_a?(Cancellation)

        raise Dexpace::InvalidArgumentError,
              "Cancellation.any accepts Dexpace::Cancellation tokens, got #{token.class}"
      end
      return NONE if tokens.empty?

      tokens.first.merged_with(*tokens.drop(1))
    end

    # A token is a frozen list of sources and holds no state of its own: #cancelled? and #reason
    # are computed from the sources on every call.
    #
    # The winner is the cancelled source with the earliest #cancelled_at -- a monotonic nanosecond
    # stamp each Source takes when it cancels -- not the first in list order. Reading the reason
    # off the first cancelled source in list order would make #reason disagree with the reason
    # #on_cancel was just handed for the whole life of the token, which is the one thing a composed
    # token must not do.
    #
    # Ordering by that stamp rather than by a subscription is what lets a token subscribe to
    # NOTHING at construction. The alternative -- subscribe to every source and latch the winner --
    # is also correct and leaks: a token retains one closure on every source for as long as that
    # source lives, and composing a client-lifetime token with a per-call deadline token, which is
    # what .any is for and what phase 5's DEF-28 will do on every request, retained 201 closures on
    # one source over 200 compositions (measured on 3.2.11 and 4.0.6).
    #
    # What the stamp buys is convergence, not atomicity, and the residual is stated rather than
    # claimed away. A Source takes its stamp BEFORE it takes its own mutex, so a source with the
    # earlier stamp can publish its state after a handler has already fired on a later-stamped one,
    # and #reason then flips to the earlier one. Demonstrated deterministically on 3.2.11, 3.4.10
    # and 4.0.6 by holding one source's mutex across the other's #cancel, and observed in a
    # free-running race 2 times in 120,000 on 3.2.11. No stamp placement closes it: the two sources
    # hold two different mutexes and there is no order between them, so moving the read inside the
    # lock narrows the window without removing it. What holds unconditionally is what a caller may
    # rely on -- the token is cancelled, every reason it ever reports belongs to a source that
    # really was cancelled, and the value converges once every racing source has published.
    #
    # Ties are not the problem and are not treated as one: 0 same-nanosecond collisions in 100,000
    # stamps, with a 50 ns median gap between successive CLOCK_MONOTONIC reads at 1 ns resolution,
    # measured on all three interpreters. Two sources stamped inside one nanosecond tie-break on
    # list order.
    def initialize(sources)
      @sources = sources.freeze
      freeze
    end

    # Composition is an instance method so that #sources can stay protected: a class method has the
    # class as `self` and cannot call a protected instance method, which is what forces #sources
    # public if `.any` does the work itself.
    def merged_with(*others)
      others.each do |other|
        next if other.is_a?(Cancellation)

        raise Dexpace::InvalidArgumentError,
              "merged_with accepts Dexpace::Cancellation tokens, got #{other.class}"
      end
      combined = others.each_with_object(sources.dup) { |other, all| all.concat(other.sources) }
      Cancellation.over(*combined.uniq)
    end

    def cancelled? = @sources.any?(&:cancelled?)

    # The reason of the source that cancelled first in time. A deliberate `nil` reason is still a
    # cancellation, because #cancelled? is the question and this is not.
    def reason = winner&.reason

    # @raise [Dexpace::CancelledError] carrying #reason
    def check!
      raise Dexpace::CancelledError, reason if cancelled?

      nil
    end

    # Each registered block is invoked **exactly once**, whether the token observes one source or
    # several, and the guard is a flag private to that registration. A flag shared across the token
    # would silently drop every registration after the first, which is what makes a second waiter
    # on one token block forever -- a SEAM-18 violation no single-waiter test can see.
    #
    # The guard mutex is held across the flag flip and across nothing else; the block runs outside
    # it, so a handler that blocks cannot deadlock a second fiber of one thread. The handler is
    # handed #reason rather than the firing source's own, so a handler and a later #reason read
    # agree in every ordering the handler itself can observe; #initialize states the window across
    # which they can still disagree, and why no stamp placement closes it.
    #
    # Subscribing happens here and only here: a token nobody registers a callback on subscribes to
    # nothing, so composition costs nothing that outlives the token.
    #
    # @return [Dexpace::Cancellation::Subscription] the handle that detaches this registration.
    #   Returning a handle rather than `self` is what makes a bounded subscription possible at all.
    #   Composition subscribing to nothing is only half the leak: the other half is a registration
    #   that outlives what it was made for. `.any(client_token, per_call_token)` with
    #   `future.value(cancellation:)` -- what phase 5's DEF-28 does on every request -- retained one
    #   closure, and through it one response, per request on the client-lifetime source: measured
    #   200 of 200 on all three interpreters before #await detached. A caller registering for the
    #   life of the token ignores the value.
    def on_cancel(&block)
      raise Dexpace::InvalidArgumentError, "on_cancel requires a block" unless block
      return Subscription.new([].freeze, nil) if @sources.empty?

      fired = false
      guard = ::Thread::Mutex.new
      once = lambda do |_source_reason|
        run = guard.synchronize do
          next false if fired

          fired = true
        end
        block.call(reason) if run
      end
      @sources.each { |source| source.on_cancel(&once) }
      Subscription.new(@sources, once)
    end

    protected

    # Protected, not public: only another token composes on it, and that is #merged_with.
    attr_reader :sources

    private

    def winner = @sources.select(&:cancelled?).min_by(&:cancelled_at)

    NONE = new([].freeze)
    private_constant :NONE
  end
end
```

Note: `raise Dexpace::CancelledError, reason` passes `reason` to the class's one-argument
`#initialize`, which is what Task 1's signature is shaped for.

- [ ] **Step 5: Write `lib/dexpace/cancellation/source.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../cancellation"
require_relative "../hooks"

module Dexpace
  class Cancellation
    # The write side of a cancellation, handed only to whoever is entitled to cancel -- the Ruby
    # answer to a language with no way to hide a mutator. A consumer holding the token cannot
    # cancel someone else's operation.
    class Source
      State = ::Data.define(:cancelled, :reason, :cancelled_at)
      private_constant :State

      # A private_constant snapshot, so it does not include Dexpace::Model and has no .build:
      # phase 1's construction rule is about a public constructor, and this has none (design P2-9).
      #
      def initialize
        @mutex = ::Thread::Mutex.new
        @state = State.new(cancelled: false, reason: nil, cancelled_at: nil)
        @hooks = []
        @token = Cancellation.over(self)
      end

      # @return [Dexpace::Cancellation] the read side to hand to a transport
      attr_reader :token

      def cancelled? = @state.cancelled

      def reason = @state.reason

      # The monotonic nanosecond stamp taken when this source was cancelled, or nil. Public because
      # a composed token orders its sources by it to find the one that cancelled first in time,
      # which is what lets a token subscribe to nothing at construction.
      def cancelled_at = @state.cancelled_at

      # The state is published inside the lock and the hooks run outside it, so a handler that
      # raises can never leave the source uncancelled. The notification goes through Hooks.notify
      # rather than a bare `hooks.each`: one raising handler in a bare each drops every
      # later-registered handler, which is the "a second waiter on one token blocks forever"
      # SEAM-18 failure arriving from the write side -- verified on all three interpreters.
      #
      # @return [Boolean] true for the call that actually cancelled, false for every later one
      def cancel(reason = nil)
        at = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        hooks = @mutex.synchronize do
          next nil if @state.cancelled

          @state = State.new(cancelled: true, reason: reason, cancelled_at: at)
          taken = @hooks
          @hooks = []
          taken
        end
        return false if hooks.nil?

        Hooks.notify(hooks, reason)
        true
      end

      def on_cancel(&block)
        raise Dexpace::InvalidArgumentError, "on_cancel requires a block" unless block

        settled = @mutex.synchronize do
          next @state if @state.cancelled

          @hooks << block
          nil
        end
        block.call(settled.reason) if settled
        self
      end

      # Withdraws a hook a token registered, so a bounded wait retains nothing on an unbounded
      # source. Called by Cancellation::Subscription#detach and by nothing else. Idempotent, and a
      # no-op once #cancel has taken the list. Array#delete compares with ==, which for a Proc is
      # object identity, so one registration is removed and an identical-looking one is not.
      def off_cancel(hook)
        @mutex.synchronize { @hooks.delete(hook) }
        self
      end
    end
  end
end
```

- [ ] **Step 6: Write the two `sig/` mirrors**

`sig/dexpace/cancellation.rbs`:

```rbs
module Dexpace
  class Cancellation
    def self.none: () -> Dexpace::Cancellation
    def self.source: () -> Dexpace::Cancellation::Source
    def self.over: (*Dexpace::Cancellation::Source) -> Dexpace::Cancellation
    def self.any: (*Dexpace::Cancellation) -> Dexpace::Cancellation

    def cancelled?: () -> bool
    def reason: () -> untyped
    def check!: () -> nil
    def on_cancel: () { (untyped) -> void } -> Dexpace::Cancellation::Subscription
    def merged_with: (*Dexpace::Cancellation) -> Dexpace::Cancellation

    class Subscription
      def initialize: (
        Array[Dexpace::Cancellation::Source] sources,
        (^(untyped) -> void)? hook,
      ) -> void
      def detach: () -> nil
    end
  end
end
```

`sig/dexpace/cancellation/source.rbs` declares `#token`, `#cancelled?`, `#reason`, `#cancelled_at`,
`#cancel: (?untyped) -> bool`, `#on_cancel` and `#off_cancel`. **`Dexpace::Hooks` gets no `sig/`
mirror and no YARD gate entry**, because it is a `private_constant` and this repository's definition
of public is a `Dexpace::` constant with a YARD block and an RBS signature.

- [ ] **Step 7: Add the three `require_relative`s to `lib/dexpace.rb`**

`dexpace/hooks`, then `dexpace/cancellation`, then `dexpace/cancellation/source`, after
`dexpace/closeable`.

- [ ] **Step 8: Run both suites to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/cancellation_test.rb` and the source
suite. Expected: PASS. Then `bundle exec rake rbs:validate steep rubocop`.

---

## Task 5: The async pivot — `Settlement`, `Completer`, `Future`

**Requirement IDs:** `SEAM-16`, `SEAM-17`, `SEAM-30`. **Design:** "The async pivot:
`Dexpace::Async::Future` and `Dexpace::Async::Completer`"; §10.3; §11.2; roadmap cross-phase
obligation 5.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/async/settlement.rb`,
  `gems/dexpace-core/lib/dexpace/async/completer.rb`,
  `gems/dexpace-core/lib/dexpace/async/future.rb`, and the three `sig/` mirrors
- Modify: `gems/dexpace-core/lib/dexpace.rb`, `gems/dexpace-core/sig/dexpace.rbs`
- Test: `gems/dexpace-core/test/dexpace/async/{settlement,completer,future}_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model` and `Dexpace::InvalidArgumentError` (phase 1), `Dexpace::Closeable`
  and `Dexpace.close_quietly` (Task 2), `Dexpace::CancelledError` (Task 1), `Dexpace::Cancellation`
  (Task 4).
- Produces: `Dexpace::Async::Settlement` — `.build(response:, error:, cancelled:)`, `.success`,
  `.failure`, `.cancellation`, `#response`, `#error`, `#cancelled`, `#success?`;
  `Dexpace::Async::Completer` — `#future`, `#fulfil(response) -> Boolean`, `#fail(error) ->
  Boolean`, `#request_cancel(reason) -> Boolean`, `#on_cancel`, `#on_settle`, `#settled?`,
  `#outcome`, `#await(cancellation)`; `Dexpace::Async::Future` — `.new(completer)`, `#settled?`,
  `#cancelled?`, `#wait(cancellation: nil)`, `#value(cancellation: nil)`, `#on_settle`,
  `#cancel(reason = nil)`. Tasks 6, 9, 10 and 11 consume all three.

- [ ] **Step 1: Write the failing tests**

`gems/dexpace-core/test/dexpace/async/completer_test.rb` — the write side, and where `SEAM-30` is
asserted:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# SEAM-16, SEAM-17, SEAM-30. The state lives on the Completer and the Future is a facade over it,
# because Ruby has no package-private visibility and the alternative is a cross-object `send`.
class DexpaceAsyncCompleterTest < DexpaceTestCase
  class FakeResponse
    include Dexpace::Closeable

    attr_reader :closes

    def initialize
      @closes = 0
      initialize_closeable(owned: true)
    end

    private

    def release
      @closes += 1
    end
  end

  def completer = Dexpace::Async::Completer.new

  test "a fulfilled future delivers the response and never closes it" do
    subject = completer
    response = FakeResponse.new

    assert(subject.fulfil(response))

    assert_same(response, subject.future.value)
    assert_equal(0, response.closes, "SEAM-16: a delivered response is the caller's to close")
  end

  test "a failed future re-raises the identical exception object" do
    subject = completer
    boom = ::IOError.new("connection reset")
    assert(subject.fail(boom))

    caught = assert_raises(::IOError) { subject.future.value }

    assert_same(boom, caught, "SEAM-18: there is no wrapper to unwrap")
  end

  test "fulfil that loses the race closes the orphan exactly once" do
    subject = completer
    assert(subject.fail(::IOError.new("already gone")))
    orphan = FakeResponse.new

    refute(subject.fulfil(orphan))

    assert_equal(1, orphan.closes, "SEAM-30: the caller-closes rule cannot apply to a value no " \
                                   "caller receives")
  end

  test "cancelling after settlement does not close the delivered response" do
    subject = completer
    response = FakeResponse.new
    subject.fulfil(response)

    subject.future.cancel(:too_late)

    assert_equal(0, response.closes, "SEAM-16's last clause, and ASYNC-20")
    refute(subject.future.cancelled?)
    assert_same(response, subject.future.value)
  end

  test "cancelling before settlement settles as cancelled and raises with the reason" do
    subject = completer

    subject.future.cancel(:stop)

    assert(subject.future.settled?)
    assert(subject.future.cancelled?)
    error = assert_raises(Dexpace::CancelledError) { subject.future.value }
    assert_equal(:stop, error.reason)
  end

  test "on_cancel gives the producer a hook to abort promptly" do
    subject = completer
    seen = []
    subject.on_cancel { |reason| seen << reason }

    subject.future.cancel(:abort)

    assert_equal([:abort], seen)
  end

  # The outcome is published BEFORE the cancel hooks run. Notify-then-settle leaves the future
  # permanently unsettled when one hook raises, so every #value on it blocks forever -- the same
  # failure Bridge::AsyncOver#deliver's rescue closes, reached through the public API alone. The
  # join timeout is the assertion: without it the suite hangs instead of failing.
  test "a raising cancel hook still leaves the future settled and every waiter unblocked" do
    subject = completer
    subject.on_cancel { raise ::IOError, "the producer's abort hook blew up" }

    assert_raises(::IOError) { subject.future.cancel(:stop) }

    assert(subject.settled?, "cancellation must always publish an outcome")
    assert(subject.future.cancelled?)
    waiter = ::Thread.new do
      subject.future.value
    rescue Dexpace::CancelledError => error
      error
    end
    assert(waiter.join(5), "the future never settled and #value would block forever")
    assert_equal(:stop, waiter.value.reason)
  end

  test "one raising settle callback does not drop the callbacks registered after it" do
    subject = completer
    seen = []
    subject.on_settle { seen << :first }
    subject.on_settle { raise ::IOError, "a settle callback blew up" }
    subject.on_settle { seen << :third }

    assert_raises(::IOError) { subject.fulfil(FakeResponse.new) }

    assert_equal(%i[first third], seen)
    assert(subject.settled?)
  end

  test "on_settle runs once whether registered before or after settlement" do
    subject = completer
    seen = []
    subject.future.on_settle { |settlement| seen << [:before, settlement.success?] }

    subject.fulfil(FakeResponse.new)
    subject.future.on_settle { |settlement| seen << [:after, settlement.success?] }

    assert_equal([[:before, true], [:after, true]], seen)
  end

  test "concurrent settles elect exactly one winner" do
    subject = completer
    wins = ::Queue.new

    16.times.map { |i| ::Thread.new { wins << i if subject.fail(::IOError.new(i.to_s)) } }
      .each(&:join)

    assert_equal(1, wins.size)
  end

  test "fail refuses anything that is not an exception" do
    assert_raises(Dexpace::InvalidArgumentError) { completer.fail(:not_an_exception) }
  end
end
```

`gems/dexpace-core/test/dexpace/async/future_test.rb` — the read side, and the two blocking
properties:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# SEAM-16, SEAM-18's interruption clause. #value blocks on a Thread::Queue pop rather than a spin
# or a Kernel#sleep poll, which is what makes the pivot scheduler-transparent (Task 6 proves it).
class DexpaceAsyncFutureTest < DexpaceTestCase
  test "value blocks until another thread settles, rather than spinning" do
    completer = Dexpace::Async::Completer.new
    response = Object.new
    producer = ::Thread.new do
      sleep(0.05)
      completer.fulfil(response)
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    assert_same(response, completer.future.value)

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_operator(elapsed, :>=, 0.04, "the waiter really blocked")
    producer.join
  end

  test "value honours a cancellation token and settles the future as cancelled" do
    completer = Dexpace::Async::Completer.new
    source = Dexpace::Cancellation.source
    canceller = ::Thread.new do
      sleep(0.02)
      source.cancel(:caller_gave_up)
    end

    error = assert_raises(Dexpace::CancelledError) do
      completer.future.value(cancellation: source.token)
    end

    assert_equal(:caller_gave_up, error.reason)
    assert(completer.future.cancelled?)
    canceller.join
  end

  test "wait returns self and never raises the failure" do
    completer = Dexpace::Async::Completer.new
    completer.fail(::IOError.new("boom"))

    future = completer.future

    assert_same(future, future.wait)
    assert(future.settled?)
  end

  test "a non-token cancellation is a caller mistake, not a NoMethodError from inside the pivot" do
    completer = Dexpace::Async::Completer.new

    error = assert_raises(Dexpace::InvalidArgumentError) do
      completer.future.value(cancellation: :not_a_token)
    end

    assert_match(/Dexpace::Cancellation/, error.message)
  end

  test "a future refuses to be built over anything but a completer" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Async::Future.new(Object.new) }

    assert_match(/Completer/, error.message)
  end

  test "settled? and cancelled? are public; the completer is not exposed" do
    future = Dexpace::Async::Completer.new.future

    assert_respond_to(future, :settled?)
    assert_respond_to(future, :cancelled?)
    refute_respond_to(future, :completer)
  end
end
```

`gems/dexpace-core/test/dexpace/async/settlement_test.rb` — the value type's cross-field rule and
the `#with` re-validation that only fails on the 3.2 floor without phase 1's shared `#with`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# SEAM-16: there is no "settled with nothing" state to reach, because settling means writing
# exactly one of a response or an error. That is enforced in initialize, not in a builder, per
# phase 1's construction rule.
class DexpaceAsyncSettlementTest < DexpaceTestCase
  test "exactly one of response or error, and cancelled implies error" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Async::Settlement.build }
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Async::Settlement.build(response: :r, error: ::IOError.new)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Async::Settlement.build(response: :r, cancelled: true)
    end
  end

  test "the three factories build the three shapes" do
    assert(Dexpace::Async::Settlement.success(:response).success?)
    refute(Dexpace::Async::Settlement.failure(::IOError.new).success?)
    cancelled = Dexpace::Async::Settlement.cancellation(Dexpace::CancelledError.new(:why))
    assert(cancelled.cancelled)
    refute(cancelled.success?)
  end

  # Data#with does not call an initialize override on Ruby 3.2 (verified 3.2.11 / 3.4.10 / 4.0.6),
  # so this passes on 3.4 and 4.0 without phase 1's shared #with and fails on the declared floor.
  test "with re-validates on every supported Ruby" do
    settled = Dexpace::Async::Settlement.success(:response)

    assert_raises(Dexpace::InvalidArgumentError) { settled.with(response: nil) }
  end

  test "new is private" do
    refute_respond_to(Dexpace::Async::Settlement, :new)
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/async/settlement_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Async`.

- [ ] **Step 3: Write `lib/dexpace/async/settlement.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Async
    # What a future settled as. Yielded to #on_settle and returned by Completer#outcome.
    #
    # The cross-field rule -- exactly one of response or error, and cancelled implying error -- is
    # SEAM-16's "MUST NOT complete successfully with a null/absent value" made structural: there is
    # no settled-with-nothing state to construct. It lives in #initialize rather than in a builder
    # because .build is public API, #with routes every derivation through it, and send(:new, ...)
    # reaches the constructor regardless (phase 1's construction rule).
    class Settlement < ::Data.define(:response, :error, :cancelled)
      include Dexpace::Model

      private_class_method :new

      def self.build(response: nil, error: nil, cancelled: false)
        new(response: response, error: error, cancelled: cancelled)
      end

      def self.success(response) = build(response: response)
      def self.failure(error) = build(error: error)
      def self.cancellation(error) = build(error: error, cancelled: true)

      def initialize(response:, error:, cancelled:)
        if response.nil? == error.nil?
          raise Dexpace::InvalidArgumentError,
                "a settlement carries exactly one of response or error"
        end
        if cancelled && error.nil?
          raise Dexpace::InvalidArgumentError, "a cancelled settlement carries an error"
        end

        super(response: response, error: error, cancelled: cancelled ? true : false)
      end

      def success? = error.nil?
    end
  end
end
```

- [ ] **Step 4: Write `lib/dexpace/async/completer.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "settlement"
require_relative "../closeable"
require_relative "../cancellation"
require_relative "../hooks"
require_relative "../error/cancelled_error"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Async
    # The write side of the canonical async pivot, and where the pivot's state lives.
    #
    # Design §10.3: the pivot is core-owned because Ruby's async ecosystem is fragmented across
    # Async::Task, Concurrent::Promises::Future, Thread plus Thread::Queue and EventMachine
    # descendants, none in the standard library and all with different cancellation semantics.
    # Adopting one would put a third-party type in core's public surface, which SEAM-1 and NFR-11
    # forbid. SEAM-17 is a SHOULD naming the pattern, not the type.
    #
    # A Completer is handed only to the producer, so a consumer cannot settle someone else's
    # future. Every constant reached from this namespace is written ::-qualified: once
    # dexpace-async-thread is required, a bare `Thread` here is Dexpace::Async::Thread, and core's
    # own suite never requires that gem (verified on 3.2.11 and 4.0.6).
    class Completer
      def initialize
        @mutex = ::Thread::Mutex.new
        @gate = ::Thread::Queue.new
        @outcome = nil
        @on_settle = []
        @on_cancel = []
      end

      # @return [Dexpace::Async::Future] the read side, memoised
      def future = @future ||= Future.new(self)

      def settled? = !@outcome.nil?

      # @return [Dexpace::Async::Settlement, nil]
      attr_reader :outcome

      # Deliver a response. Returns false when the race was already lost, and closes the response
      # it was handed on that path -- SEAM-30, implemented once here so it holds for every adapter
      # that settles through a Completer rather than depending on each one remembering.
      def fulfil(response)
        delivered = settle(Settlement.success(response))
        Dexpace.close_quietly(response) unless delivered
        delivered
      end

      def fail(error)
        unless error.is_a?(::Exception)
          raise Dexpace::InvalidArgumentError, "fail requires an exception, got #{error.class}"
        end

        settle(Settlement.failure(error))
      end

      # Cooperative: this cannot pre-empt a producer, because Ruby's only pre-emption primitives
      # are Thread#raise and Thread#kill and design §8.3 forbids them. The producer's obligation is
      # check-after-resume (design §3.3), and #on_cancel is how it can abort sooner.
      #
      # **The outcome is published before the hooks run.** Written the other way round -- notify,
      # then settle -- one raising hook aborts the method and the future is left permanently
      # unsettled, so every #value on it blocks forever. Reachable through the public API alone,
      # and reproduced on 3.2.11, 3.4.10 and 4.0.6: `completer.on_cancel { raise }` followed by
      # `completer.future.cancel(:stop)` left #settled? false. That is the same "the future never
      # settled and #value would block" failure Bridge::AsyncOver#deliver's rescue closes, arriving
      # from the other side, so it gets the same answer: a cancellation always publishes an
      # outcome. Hooks.notify then runs every hook and re-raises the first failure afterwards.
      def request_cancel(reason = nil)
        hooks = @mutex.synchronize do
          next nil if @outcome

          taken = @on_cancel
          @on_cancel = []
          taken
        end
        return false if hooks.nil?

        cancelled = settle(Settlement.cancellation(Dexpace::CancelledError.new(reason)))
        Hooks.notify(hooks, reason)
        cancelled
      end

      def on_cancel(&block)
        raise Dexpace::InvalidArgumentError, "on_cancel requires a block" unless block

        already = @mutex.synchronize do
          next true if @outcome

          @on_cancel << block
          false
        end
        block.call(@outcome.error.reason) if already && @outcome.cancelled
        self
      end

      def on_settle(&block)
        raise Dexpace::InvalidArgumentError, "on_settle requires a block" unless block

        settled = @mutex.synchronize do
          next @outcome if @outcome

          @on_settle << block
          nil
        end
        block.call(settled) if settled
        self
      end

      # Blocks the calling thread-or-fiber on a Thread::Queue pop, never a spin and never a
      # Kernel#sleep poll: under a registered Fiber.scheduler a blocking queue pop routes through
      # the scheduler's block/unblock hooks instead of parking the OS thread (verified on 3.2.11,
      # 3.4.10 and 4.0.6; Task 6 asserts it).
      def await(cancellation = nil)
        return self if settled?

        subscription = arm(cancellation)
        begin
          @gate.pop until settled?
        ensure
          subscription&.detach
        end
        self
      end

      private

      # The registration is detached in #await's `ensure`, whichever way the wait ends.
      #
      # It has to be. The hook lives on the caller's token, which a caller may hold for the life of
      # a client, and the closure reaches this Completer and through it the response the future
      # settled with. `.any(client_token, per_call_token)` with `future.value(cancellation:)` --
      # what phase 5's DEF-28 will do on every request -- retained one closure and one response per
      # request on the client-lifetime source: measured 200 of 200 on 3.2.11, 3.4.10 and 4.0.6, and
      # 500 100 KB responses still reachable after GC.start. Per-call tokens narrow the blast
      # radius and do not close it, because the whole point of .any is composing a per-call token
      # with a long-lived one.
      #
      # @return [Dexpace::Cancellation::Subscription, nil] nil when there was nothing to arm
      def arm(cancellation)
        return nil if cancellation.nil?

        unless cancellation.is_a?(Dexpace::Cancellation)
          raise Dexpace::InvalidArgumentError,
                "cancellation: takes a Dexpace::Cancellation, got #{cancellation.class}"
        end
        return nil if cancellation.equal?(Dexpace::Cancellation.none)

        cancellation.on_cancel { |reason| request_cancel(reason) }
      end

      # The queue is a wake-up signal and never the value channel: Thread::Queue#pop returns nil
      # for a timeout, for a closed queue and for a pushed nil alike (verified on all three
      # interpreters), so a pivot that carried its value through the queue could not tell
      # "settled with nothing" from "not settled".
      #
      # The mutex is held across the outcome write and the callback-list steal and across nothing
      # else. Callbacks run outside it, so an #on_settle handler that blocks cannot deadlock a
      # second fiber of the same thread, and they go through Hooks.notify so that one raising
      # handler cannot drop the rest of the list.
      def settle(settlement)
        callbacks = @mutex.synchronize do
          next nil if @outcome

          @outcome = settlement
          taken = @on_settle
          @on_settle = []
          @on_cancel = []
          taken
        end
        return false if callbacks.nil?

        @gate.close
        Hooks.notify(callbacks, settlement)
        true
      end
    end
  end
end
```

- [ ] **Step 5: Write `lib/dexpace/async/future.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "completer"

module Dexpace
  module Async
    # The read side of the canonical async pivot: a facade over one Completer, which is where every
    # piece of state lives.
    #
    # .new stays public and type-checks its argument rather than being made private. A second
    # facade over the same completer is harmless -- both observe one future -- and the alternative,
    # a private constructor the completer reaches through send, would put a send hole in exactly
    # the read/write boundary this pair exists to draw.
    class Future
      def initialize(completer)
        unless completer.is_a?(Completer)
          raise Dexpace::InvalidArgumentError,
                "a future is built over a Dexpace::Async::Completer, got #{completer.class}"
        end

        @completer = completer
      end

      def settled? = @completer.settled?

      def cancelled? = @completer.outcome&.cancelled ? true : false

      # Settles-or-returns; never raises the failure.
      def wait(cancellation: nil)
        @completer.await(cancellation)
        self
      end

      # Blocks, then delivers the response or raises the failure. `deadline:` is deliberately
      # absent: SEAM-18's interruption clause is about cancellation, and deadlines need phase 5's
      # clock and interruptible-delay primitives (CFG-15..CFG-21, DEF-28). Adding the keyword later
      # widens this signature rather than narrowing it, so NFR-4's API lock is not prejudiced.
      def value(cancellation: nil)
        wait(cancellation: cancellation)
        settlement = @completer.outcome
        raise settlement.error if settlement.error

        settlement.response
      end

      def on_settle(&block)
        @completer.on_settle(&block)
        self
      end

      def cancel(reason = nil)
        @completer.request_cancel(reason)
        self
      end
    end
  end
end
```

- [ ] **Step 6: Write the three `sig/` mirrors**

`sig/dexpace/async/future.rbs`:

```rbs
module Dexpace
  module Async
    class Future
      def initialize: (Dexpace::Async::Completer) -> void
      def settled?: () -> bool
      def cancelled?: () -> bool
      def wait: (?cancellation: Dexpace::Cancellation?) -> self
      def value: (?cancellation: Dexpace::Cancellation?) -> untyped
      def on_settle: () { (Dexpace::Async::Settlement) -> void } -> self
      def cancel: (?untyped reason) -> self
    end
  end
end
```

`sig/dexpace/async/settlement.rbs` and `.../completer.rbs` mirror their classes the same way.
`#response` is `untyped` for the same reason phase 1's `Request#body` is: the `Response` type is
phase 1's but a transport's response is what a *seam* returns, and narrowing it here would fix the
async seam's return type ahead of phase 8's first adapter.

- [ ] **Step 7: Add the three `require_relative`s to `lib/dexpace.rb`**

`dexpace/async/settlement`, `dexpace/async/completer`, `dexpace/async/future`, after the two
cancellation files. Order matters: `Completer#future` names `Future` at call time, but
`Future#initialize` names `Completer` at call time too, and `lib/dexpace.rb` must load both before
either is used.

- [ ] **Step 8: Run the three suites to confirm they pass**

Run each of `settlement_test.rb`, `completer_test.rb`, `future_test.rb`.
Expected: PASS. Then `bundle exec rake rubocop rbs:validate steep` — RuboCop is the step that
proves Task 3's cop is satisfied by the `::`-qualified constants in these three files.

- [ ] **Step 9: Run the floor**

Run: `mise exec ruby@3.2.11 -- bundle exec rake test:gems`
Expected: PASS. This is the run that would go red if phase 1's shared `#with` were dropped, because
`Data#with` does not call an `initialize` override on 3.2.

---

## Task 6: The pivot's two structural proofs

**Requirement IDs:** `SEAM-17` (the scheduler-transparency claim the pivot rests on); no new ID.
**Design:** "Testing" — *The scheduler-transparency test* and *The constant-shadowing test*;
verified Ruby facts 2 and 4.

**Files:**
- Create: `gems/dexpace-core/test/support/probe_scheduler.rb`
- Test: `gems/dexpace-core/test/dexpace/async/future_scheduler_test.rb`,
  `gems/dexpace-core/test/dexpace/async/future_shadowing_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Async::Completer` and `Dexpace::Async::Future` (Task 5).
- Produces: `ProbeScheduler`, a test-only `Fiber.scheduler` recording its `#block`/`#unblock` hooks.
  Nothing in `lib/` consumes it.

These are a separate task because a reviewer could accept Task 5's pivot and still reject the way
its two central claims are proved.

- [ ] **Step 1: Write `test/support/probe_scheduler.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A minimal Fiber scheduler that records which hooks a blocking operation routed through. It is a
# probe, not an implementation: #block runs other ready fibers in a nested loop rather than
# suspending the calling fiber, which is the shape that stays well-behaved when the blocker is a
# Thread::Mutex.
#
# #fiber_interrupt is defined because Ruby 4.0.6 warns "Scheduler should implement #fiber_interrupt"
# without it, and the shared test case turns a warning into a failure for the test that triggered
# it. Verified on 4.0.6 that defining it silences the warning.
class ProbeScheduler
  attr_reader :hooks

  def initialize
    @hooks = []
    @ready = []
    @unblocked = {}
  end

  def block(blocker, timeout = nil)
    @hooks << [:block, blocker.class.name]
    me = Fiber.current
    until @unblocked.delete(me)
      runnable = @ready.shift
      return false if runnable.nil?

      runnable.resume if runnable.alive?
    end
    true
  end

  def unblock(blocker, fiber)
    @hooks << [:unblock, blocker.class.name]
    @unblocked[fiber] = true
    @ready << fiber
  end

  def kernel_sleep(duration = nil) = nil
  def io_wait(io, events, timeout) = events
  def fiber_interrupt(fiber, exception) = nil

  def fiber(&block)
    created = Fiber.new(blocking: false, &block)
    @ready << created
    created
  end

  def close
    until @ready.empty?
      runnable = @ready.shift
      runnable.resume if runnable.alive?
    end
  end
end
```

- [ ] **Step 2: Write the two failing tests**

`gems/dexpace-core/test/dexpace/async/future_scheduler_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/probe_scheduler"

# SEAM-17. Design §3.3 claims the pivot is scheduler-transparent -- that a caller inside Async { }
# awaits it without blocking the reactor. That claim rests on one Ruby fact: a blocking
# Thread::Queue pop routes through a registered Fiber.scheduler's block/unblock hooks instead of
# parking the OS thread. This asserts the fact rather than restating the claim, and it runs on
# every row of the CI matrix, which is what makes it a standing check.
class DexpaceAsyncFutureSchedulerTest < DexpaceTestCase
  test "value blocks through the scheduler, not the thread" do
    scheduler = ProbeScheduler.new
    completer = Dexpace::Async::Completer.new
    delivered = []

    Fiber.set_scheduler(scheduler)
    begin
      Fiber.schedule { delivered << completer.future.value }
      Fiber.schedule { completer.fulfil(:response) }
    ensure
      Fiber.set_scheduler(nil)
    end

    assert_equal([:response], delivered)
    assert_includes(scheduler.hooks, [:block, "Thread::Queue"])
    assert_includes(scheduler.hooks, [:unblock, "Thread::Queue"])
  end
end
```

`gems/dexpace-core/test/dexpace/async/future_shadowing_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# Design §9 Addendum A1 and verified fact 2. dexpace-async-thread defines Dexpace::Async::Thread,
# after which a bare `Thread` written inside module Dexpace::Async resolves to that module rather
# than to Ruby's class -- and dexpace-core's own suite never requires that gem, so this is the only
# place core can catch it. Task 3's cop is the other half: the cop catches it on a file nobody ran,
# this catches it on a file nobody linted.
class DexpaceAsyncFutureShadowingTest < DexpaceTestCase
  test "the pivot still works once the adapter gem's namespace exists" do
    unless Dexpace::Async.const_defined?(:Thread, false)
      Dexpace::Async.const_set(:Thread, Module.new)
    end

    completer = Dexpace::Async::Completer.new
    response = Object.new
    producer = ::Thread.new { completer.fulfil(response) }

    assert_same(response, completer.future.value)

    producer.join
    assert_equal(Module, Dexpace::Async::Thread.class,
                 "the stand-in is still a bare Module, so the pivot did not reach Ruby's Thread " \
                 "by accident")
  end
end
```

This test defines a constant that outlives it. It is in its own file, and it is the last word on
the subject: nothing else in the suite may assume `Dexpace::Async::Thread` is undefined. State that
in the file's header comment when writing it.

- [ ] **Step 3: Run them to confirm they fail**

Delete the `::` from one constant in `lib/dexpace/async/completer.rb` — `::Thread::Mutex` to
`Thread::Mutex` — run `future_shadowing_test.rb`, and confirm it fails with `NoMethodError` on
`Dexpace::Async::Thread`. Restore the `::`. **Do this deliberately: a test whose failure mode has
never been observed is a test nobody has seen work.**

- [ ] **Step 4: Run them to confirm they pass**

Run both suites, then `mise exec ruby@4.0.6 -- bundle exec ruby -w
gems/dexpace-core/test/dexpace/async/future_scheduler_test.rb`.
Expected: PASS with no `Scheduler should implement #fiber_interrupt` warning — which the shared
test case would otherwise turn into a failure.

---

## Task 7: `Dexpace::Registry` — the five resolution branches

**Requirement IDs:** `SEAM-5`, `SEAM-6`, `SEAM-7`, `SEAM-8`, `SEAM-9`; `SEAM-2` in the error path;
`XCUT-23` for phase 9. **Design:** "`Dexpace::Registry` — discovery, install and conflict
resolution"; §3.6; §10.8.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/registry.rb`,
  `gems/dexpace-core/sig/dexpace/registry.rbs`,
  `gems/dexpace-core/test/support/warning_capture.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`, `gems/dexpace-core/sig/dexpace.rbs`
- Test: `gems/dexpace-core/test/dexpace/registry_test.rb`

**Interfaces:**
- Consumes: `Dexpace::SeamError` (Task 1), `Dexpace::InvalidArgumentError` (phase 1).
- Produces: `Dexpace::Registry.new(seam:, installer:, conforms:)` with `#seam`,
  `#registered_keys`, `#register(key, factory, core:)`, `#install(provider)`, `#resolve`,
  `#swap(provider) { |provider| }`; and the class method
  `Dexpace::Registry.callable?(object, arity:)`. Tasks 8, 9, 10 and 12 consume all of it. Also
  `WarningCapture`, the test-only helper that records a `Kernel#warn` instead of letting the shared
  test case raise on it.

**Task 7 ships `#assert_core_version!` whole; Task 8 ships its proof.** The two are separate
tasks because a reviewer can accept the five resolution branches and still reject how a hand-rolled
version comparison is shown to be right, and because Task 8's proof is a grid against
`Gem::Requirement` rather than another unit test.

- [ ] **Step 1: Write `test/support/warning_capture.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Records a Kernel#warn instead of letting the shared test case raise on it.
#
# Phase 0's DexpaceTestCase prepends a module to Warning's singleton class that raises, so a
# warning fails the test that triggered it. SEAM-8 requires core to emit a warning, so exactly one
# test needs to observe one without failing. Prepending this module *after* phase 0's puts it ahead
# in the ancestor chain, so a recorded warning never reaches the raiser and an unrecorded one still
# does -- verified on 3.2.11, 3.4.10 and 4.0.6.
#
# This replaces the design's "adds the first entry to phase 0's warning allowlist": it is scoped to
# one block rather than to a message pattern for the life of the suite, and it needs no knowledge
# of phase 0's allowlist API.
module WarningCapture
  def self.recorded = @recorded ||= []

  def self.recording? = @recording

  # @return [Array<String>] the warnings emitted inside the block
  def self.record
    @recording = true
    recorded.clear
    yield
    recorded.dup
  ensure
    @recording = false
  end

  def warn(message, category: nil)
    return WarningCapture.recorded << message if WarningCapture.recording?

    super
  end
end

Warning.singleton_class.prepend(WarningCapture)
```

- [ ] **Step 2: Write the failing test**

`gems/dexpace-core/test/dexpace/registry_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/warning_capture"

# SEAM-5, SEAM-6, SEAM-7, SEAM-8, SEAM-9, SEAM-2, XCUT-23. Ruby has no classpath, so design §3.6
# changes the substrate -- an adapter registers itself as a side effect of being required -- and
# keeps all five precedence branches. State is one frozen Data snapshot swapped under a
# Thread::Mutex, so a reader takes one unsynchronised reference read and sees a consistent picture.
class DexpaceRegistryTest < DexpaceTestCase
  CORE = "~> 0.0"

  def registry(conforms: ->(_object) { true })
    Dexpace::Registry.new(
      seam: "transport",
      installer: "Dexpace::Transport.install",
      conforms: conforms,
    )
  end

  test "zero candidates raise a descriptive error naming no gem" do
    error = assert_raises(Dexpace::SeamError) { registry.resolve }

    assert_match(/no transport provider is registered/, error.message)
    assert_match(/Dexpace::Transport\.install/, error.message)
    refute_match(/net_http|async_http|net\/http|json|oj|excon|typhoeus/i, error.message,
                 "SEAM-2: core names no concrete implementation, not even in the error path")
  end

  test "exactly one candidate resolves silently and is memoised" do
    subject = registry
    built = 0
    subject.register(:fake, lambda {
      built += 1
      Object.new
    }, core: CORE)

    first = subject.resolve

    assert_same(first, subject.resolve, "SEAM-7: a successful resolution is cached process-wide")
    assert_equal(1, built)
  end

  test "two candidates raise an error listing every registered key" do
    subject = registry
    subject.register(:alpha, -> { :alpha }, core: CORE)
    subject.register(:beta, -> { :beta }, core: CORE)

    error = assert_raises(Dexpace::SeamError) { subject.resolve }

    assert_match(/:alpha/, error.message)
    assert_match(/:beta/, error.message)
  end

  test "a failed resolution memoises nothing and a later registration takes effect" do
    subject = registry
    assert_raises(Dexpace::SeamError) { subject.resolve }

    subject.register(:late, -> { :late }, core: CORE)

    assert_equal(:late, subject.resolve, "SEAM-7: an unresolved state stays re-evaluable")
  end

  test "re-registering the identical factory under one key is a no-op" do
    subject = registry
    factory = -> { :provider }
    subject.register(:key, factory, core: CORE)

    subject.register(:key, factory, core: CORE)

    assert_equal([:key], subject.registered_keys)
  end

  test "a different factory under an occupied key raises naming both" do
    subject = registry
    subject.register(:key, -> { :first }, core: CORE)

    error = assert_raises(Dexpace::InvalidArgumentError) do
      subject.register(:key, -> { :second }, core: CORE)
    end

    assert_match(/already registered/, error.message)
  end

  test "installing into an empty slot succeeds silently" do
    subject = registry
    provider = Object.new

    warnings = WarningCapture.record { subject.install(provider) }

    assert_empty(warnings)
    assert_same(provider, subject.resolve)
  end

  test "installing the identical instance twice is a no-op" do
    subject = registry
    provider = Object.new
    subject.install(provider)

    warnings = WarningCapture.record { subject.install(provider) }

    assert_empty(warnings)
    assert_same(provider, subject.resolve)
  end

  test "installing a different instance over an explicit install raises naming both" do
    subject = registry
    incumbent = Object.new
    subject.install(incumbent)

    error = assert_raises(Dexpace::InvalidArgumentError) { subject.install(Object.new) }

    assert_match(/already installed/, error.message)
  end

  # SEAM-8's negative clause -- "no warning is warranted ... when the resolved provider was never
  # actually returned" -- holds **vacuously in production** here, because #resolve hands out the
  # provider in the same call that resolves it, so an auto-resolved-but-never-handed-out slot is
  # unreachable through the ordinary API. The unchecked swap seam SEAM-6 sanctions is the only door
  # into that state, which is what this exercises: the branch exists, is correct, and would become
  # live the day a non-delivering resolution path is added. It does not prove that any production
  # path reaches it, and must not be read as proving that.
  test "replacing a swapped-in provider that was never handed out is silent" do
    subject = registry

    subject.swap(:auto) do
      warnings = WarningCapture.record { subject.install(Object.new) }

      assert_empty(warnings)
    end
  end

  test "replacing an auto-resolved provider that was already handed out warns" do
    subject = registry
    subject.register(:key, -> { :auto }, core: CORE)
    subject.resolve

    warnings = WarningCapture.record { subject.install(Object.new) }

    assert_equal(1, warnings.size)
    assert_match(/already been handed out/, warnings.first)
  end

  test "swap is scoped to its block and restores the previous state" do
    subject = registry
    subject.register(:key, -> { :real }, core: CORE)
    assert_equal(:real, subject.resolve)

    subject.swap(:fake) do |provider|
      assert_equal(:fake, provider)
      assert_equal(:fake, subject.resolve)
    end

    assert_equal(:real, subject.resolve)
  end

  test "swap without a block is a caller mistake" do
    assert_raises(Dexpace::InvalidArgumentError) { registry.swap(:fake) }
  end

  test "a concurrent first access runs the discovery scan exactly once" do
    subject = registry
    built = 0
    counter = ::Thread::Mutex.new
    subject.register(:key, lambda {
      counter.synchronize { built += 1 }
      Object.new
    }, core: CORE)
    results = ::Queue.new

    32.times.map { ::Thread.new { results << subject.resolve } }.each(&:join)

    resolved = []
    resolved << results.pop until results.empty?
    assert_equal(1, resolved.map(&:object_id).uniq.size, "SEAM-9: exactly-once resolution")
    assert_equal(1, built)
  end

  test "two concurrent installs cannot both pass the conflict check" do
    subject = registry
    accepted = ::Queue.new

    16.times.map do
      ::Thread.new do
        subject.install(Object.new)
        accepted << 1
      rescue Dexpace::InvalidArgumentError
        nil
      end
    end.each(&:join)

    assert_equal(1, accepted.size, "SEAM-9: writes are serialized")
  end

  test "a class factory is instantiated and a callable factory is called" do
    subject = registry
    klass = Class.new
    subject.register(:key, klass, core: CORE)

    assert_instance_of(klass, subject.resolve)
  end

  test "a factory whose product does not implement the seam fails loudly at resolve" do
    subject = registry(conforms: ->(object) { object.is_a?(Symbol) })
    subject.register(:key, -> { Object.new }, core: CORE)

    error = assert_raises(Dexpace::SeamError) { subject.resolve }

    assert_match(/does not implement the seam/, error.message)
  end

  test "install refuses a provider that does not implement the seam" do
    subject = registry(conforms: ->(object) { object.is_a?(Symbol) })

    assert_raises(Dexpace::InvalidArgumentError) { subject.install(Object.new) }
  end

  # Each of these takes the registry's OWN write mutex from inside the factory or the conformance
  # predicate, which is what makes them bite: under a "build inside @write.synchronize" shape every
  # one raises ThreadError: deadlock; recursive locking on every supported Ruby. A test whose
  # factory only calls #registered_keys would pass under that shape too, because #registered_keys
  # takes no lock -- and a regression test that passes under the bug is worse than no test.
  test "a factory that takes the registry's own write lock does not deadlock" do
    subject = registry
    installed = Object.new
    subject.register(:key, lambda {
      subject.install(installed) # #install takes @write
      Object.new
    }, core: CORE)

    assert_same(installed, subject.resolve,
                "an explicit install that lands mid-build wins, and the built provider is dropped")
  end

  test "the conformance predicate can take the write lock, so it is not called under it" do
    observed = []
    subject = nil
    subject = Dexpace::Registry.new(
      seam: "transport",
      installer: "Dexpace::Transport.install",
      conforms: lambda { |_provider|
        subject.swap(:probe) { observed << :ran } # #swap takes @write, twice
        true
      },
    )
    subject.register(:key, -> { Object.new }, core: CORE)

    subject.resolve

    assert_equal([:ran], observed)
  end

  test "a factory that resolves another registry does not deadlock" do
    inner = registry
    inner.register(:inner, -> { :inner_provider }, core: CORE)
    outer = registry
    outer.register(:outer, -> { inner.resolve }, core: CORE)

    assert_equal(:inner_provider, outer.resolve)
  end

  # The three re-entrancy cases, which the "resolves ANOTHER registry" test above does not reach.
  # A factory that resolves its OWN registry parks on the gate it took itself, and every later
  # caller then parks on the same gate: measured, one self-resolving thread plus four unrelated
  # resolvers left five hung on every supported Ruby. The shape this replaced raised
  # `ThreadError: deadlock; recursive locking` from the offending call, so a silent wedge would be
  # a straight regression.
  test "a factory that resolves its own registry raises rather than parking on its own gate" do
    subject = registry
    subject.register(:key, -> { subject.resolve }, core: CORE)

    error = assert_raises(Dexpace::SeamError) { subject.resolve }

    assert_match(/re-entrant transport resolution/, error.message)
  end

  test "a cycle of two registries raises rather than hanging both" do
    first = registry
    second = registry
    first.register(:first, -> { second.resolve }, core: CORE)
    second.register(:second, -> { first.resolve }, core: CORE)

    assert_raises(Dexpace::SeamError) { first.resolve }
  end

  # The claim is released in #complete_resolution's ensure on this path like any other, so the
  # registry is re-evaluable for everyone else. The join timeout is the assertion: without it the
  # suite hangs instead of failing.
  test "a re-entrant resolve leaves the registry re-evaluable for every other caller" do
    subject = registry
    reentrant = true
    subject.register(:key, lambda {
      next subject.resolve if reentrant

      :provider
    }, core: CORE)

    assert_raises(Dexpace::SeamError) { subject.resolve }
    reentrant = false

    later = ::Thread.new { subject.resolve }
    assert(later.join(5), "a re-entrant resolve wedged the whole registry")
    assert_equal(:provider, later.value)
  end

  # SEAM-7's "an UNRESOLVED state MUST remain re-evaluable", against the failure a rescue of
  # StandardError alone does not cover. A LoadError from an adapter factory that requires its own
  # dependency lazily is the realistic case; releasing the claim only on the StandardError path
  # leaves a closed gate latched and every later #resolve spinning at 100% CPU with no exception.
  # The join timeout is the assertion: without it the suite hangs instead of failing.
  test "a factory raising outside StandardError leaves the registry re-evaluable" do
    subject = registry
    first_attempt = true
    subject.register(:key, lambda {
      raise ::LoadError, "the adapter's own dependency is missing" if first_attempt

      :recovered
    }, core: CORE)

    assert_raises(::LoadError) { subject.resolve }
    first_attempt = false

    retried = ::Thread.new { subject.resolve }
    assert(retried.join(5), "the registry wedged into a spin instead of re-evaluating")
    assert_equal(:recovered, retried.value)
  end

  # #swap is the seam every adapter suite will reach for, and a resolution can complete inside its
  # block. Restoring the pre-block snapshot wholesale would put that resolution's now-closed gate
  # back and wedge every later #resolve the same way.
  test "swap does not restore a stale resolution claim" do
    subject = registry
    started = ::Queue.new
    release = ::Queue.new
    blocking = true
    subject.register(:key, lambda {
      if blocking
        blocking = false
        started << :in_factory
        release.pop
      end
      :provider
    }, core: CORE)

    resolver = ::Thread.new { subject.resolve }
    started.pop
    subject.swap(:fake) do
      release << :go
      resolver.join
    end

    later = ::Thread.new { subject.resolve }
    assert(later.join(5), "swap restored a closed gate and wedged the registry")
    assert_equal(:provider, later.value)
  end

  # An adapter registers itself as a side effect of being required, and Ruby will not re-run a
  # `require`, so a registration reverted by #swap's ensure is gone for the rest of the process.
  # `resolved`, `explicit` and `handed_out` ARE restored -- scoping an override is what swap is for
  # -- and `factories` is spliced from the live state for the same reason `resolving` is.
  test "swap does not revert a registration made inside its block" do
    subject = registry

    subject.swap(:fake) do
      subject.register(:key, -> { :real }, core: CORE)

      assert_equal(:fake, subject.resolve, "the override is still in force inside the block")
    end

    assert_equal([:key], subject.registered_keys,
                 "swap reverted a require-time registration, which no later require can redo")
    assert_equal(:real, subject.resolve)
  end

  test "callable? accepts every callable shape that can take three positional arguments" do
    assert(Dexpace::Registry.callable?(->(_a, _b, _c) {}, arity: 3))
    assert(Dexpace::Registry.callable?(proc { |_a, _b, _c| }, arity: 3))
    assert(Dexpace::Registry.callable?(->(*) {}, arity: 3))
    refute(Dexpace::Registry.callable?(->(_a) {}, arity: 3))
    refute(Dexpace::Registry.callable?(Object.new, arity: 3))
    refute(Dexpace::Registry.callable?(nil, arity: 3))
  end
end
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/registry_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Registry`.

- [ ] **Step 4: Write `lib/dexpace/registry.rb`**

Write the whole file, including the `#assert_core_version!` private method Task 8 tests; this task
implements it and Task 8 is the task that proves it against `Gem::Requirement`.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "error/seam_error"
require_relative "error/invalid_argument_error"
require_relative "version"

module Dexpace
  # Provider discovery, installation and conflict resolution, implemented once and instantiated
  # once per surviving seam.
  #
  # Ruby has no classpath to scan, so design §3.6 keeps all five of SEAM-5's precedence branches
  # and changes only the substrate: an adapter registers itself as a side effect of being
  # `require`d, and "discoverable" means "the application has required this adapter". Core ships an
  # empty registry and never auto-requires an optional gem, which is what keeps SEAM-1 true, and
  # the zero-candidate error names no gem, which is what keeps SEAM-2 true in the error path.
  #
  # The registry maps a key to a *factory* -- the adapter class, or any #call-shaped builder --
  # because require-time registration happens before the application has configured anything.
  # Resolution produces an *instance* and the resolved slot holds exactly one. SEAM-6's and
  # SEAM-8's prior-state table therefore compares `equal?` on the object in that slot: never ==,
  # and never the factory, because two calls of one factory produce two non-equal? instances the
  # requirement means to treat as different providers.
  #
  # State is one frozen Data snapshot in one instance variable, replaced wholesale under a
  # Thread::Mutex. A reader takes a single unsynchronised reference read and sees a consistent,
  # fully-constructed picture or the previous one, never a torn mixture -- which is SEAM-9's three
  # clauses implemented rather than argued, and IO-39's lock-free-read property surviving the seam
  # that used to state it. Concurrent::Map would be the styleguide's answer and is a gem
  # (docs/knowledge/notes/concurrency-and-async.md).
  class Registry
    # Design §2.3 mandates the two-segment pessimistic form and nothing else. Anything else is
    # refused rather than partially reimplemented.
    CORE_REQUIREMENT = Regexp.new("\\A~>\\s*(\\d+)\\.(\\d+)\\z", timeout: 1.0)
    private_constant :CORE_REQUIREMENT

    State = ::Data.define(:factories, :resolved, :handed_out, :explicit, :resolving)
    private_constant :State

    # The resolution claim: the gate every other caller waits on, and the fiber that took it.
    #
    # The owner is what turns a re-entrant #resolve from a silent registry-wide wedge into a loud
    # error at the offending call. It is a Fiber and not a Thread for the same reason
    # Thread::Mutex's own ownership is per-fiber: two fibers of one thread can genuinely wait on
    # each other, and a factory that spawns a thread and resolves from it is not re-entrant at all.
    Claim = ::Data.define(:gate, :owner)
    private_constant :Claim

    EMPTY = State.new(
      factories: {}.freeze, resolved: nil, handed_out: false, explicit: false, resolving: nil,
    ).freeze
    private_constant :EMPTY

    # Whether `object` can be called with `arity` positional arguments. Both transport seams are
    # duck types over #call and this is the runtime half of that contract; the RBS interface in
    # sig/ is the static half.
    #
    # Computed from #parameters rather than from #arity: a non-lambda Proc reports its parameters
    # as :opt where a lambda reports :req (verified on 3.2.11, 3.4.10 and 4.0.6), so an #arity
    # equality would reject `proc { |a, b, c| }`, which SEAM-11's "a bare send lambda works as a
    # transport" is meant to admit. An object whose #call comes from method_missing has no
    # introspectable parameters, and is admitted rather than refused.
    def self.callable?(object, arity:)
      return false unless object.respond_to?(:call)

      callable = object.is_a?(::Proc) || object.is_a?(::Method) ? object : object.method(:call)
      parameters = callable.parameters
      required = parameters.count { |(kind, _)| kind == :req }
      optional = parameters.count { |(kind, _)| kind == :opt }
      rest = parameters.any? { |(kind, _)| kind == :rest }
      required <= arity && (rest || required + optional >= arity)
    rescue ::NameError
      true
    end

    attr_reader :seam

    # @param seam [String] the seam's name, as it appears in every error message
    # @param installer [String] the fully qualified explicit-install entry point, for the hint
    # @param conforms [#call] the seam's own .conforms? predicate
    def initialize(seam:, installer:, conforms:)
      @seam = seam.to_s.freeze
      @installer = installer.to_s.freeze
      @conforms = conforms
      @write = ::Thread::Mutex.new
      @state = EMPTY
    end

    def registered_keys = @state.factories.keys

    # Re-registering the `equal?` factory under one key is a no-op, so a double require is quiet;
    # a different factory under an occupied key raises, so two gems claiming one key are not.
    def register(key, factory, core:)
      assert_core_version!(key, core)
      @write.synchronize do
        incumbent = @state.factories[key]
        next if incumbent.equal?(factory)

        if incumbent
          raise Dexpace::InvalidArgumentError,
                "#{@seam} key #{key.inspect} is already registered to #{incumbent.inspect}; " \
                "#{factory.inspect} was rejected"
        end

        @state = @state.with(factories: @state.factories.merge(key => factory).freeze)
      end
      self
    end

    # SEAM-5's "an explicitly installed provider always wins", with SEAM-6's conflict rule and
    # SEAM-8's warning. The warning is emitted outside the lock, because it writes to a stream.
    def install(provider)
      refuse(provider) unless @conforms.call(provider)
      replaced_after_handout = false
      @write.synchronize do
        state = @state
        next if state.resolved.equal?(provider)

        if state.resolved && state.explicit
          raise Dexpace::InvalidArgumentError,
                "a #{@seam} provider is already installed (#{state.resolved.inspect}); " \
                "#{provider.inspect} was rejected"
        end

        replaced_after_handout = !state.resolved.nil? && state.handed_out
        @state = state.with(resolved: provider, handed_out: false, explicit: true)
      end
      if replaced_after_handout
        # SEAM-8 is a SHOULD asking for a warning rather than a failure. Kernel#warn routes through
        # Warning.warn, so a host can intercept, redirect or silence it; verified suppressed when
        # $VERBOSE is nil, which is the right property for an advisory.
        warn("dexpace: a #{@seam} provider that had already been handed out was replaced by " \
             "#{provider.inspect}; objects built against the previous one may still be in use")
      end
      self
    end

    # Single-flight, with **no factory call and no #conforms? call under the lock**. The naive
    # shape -- build inside @write.synchronize -- deadlocks with `ThreadError: deadlock; recursive
    # locking` the moment a factory resolves anything from the same registry, because Ruby's Mutex
    # is non-reentrant, and it violates this file's own rule that a mutex is held across a snapshot
    # swap and nothing else.
    #
    # So the claim is a snapshot swap like any other: the winner puts a Thread::Queue in the
    # `resolving` slot and builds outside the lock, and every other caller blocks on that queue
    # until the winner closes it. That keeps SEAM-9's "a concurrent first-access cannot run the
    # discovery scan twice" while the scan itself runs unlocked, and it is scheduler-transparent
    # for the same reason the pivot's wait is: a blocking Thread::Queue pop routes through a
    # registered Fiber.scheduler rather than parking the OS thread. A resolution that raises clears
    # the slot and every waiter retries, which is SEAM-7's "an UNRESOLVED state MUST remain
    # re-evaluable".
    #
    # **A factory that resolves the registry it is being built by raises**, and the check is the
    # owner recorded in the claim. Without it that caller parks on the gate it took itself and
    # never returns, and every other caller then parks on the same gate: measured, one
    # self-resolving thread plus four unrelated resolvers left five hung, and a two-registry cycle
    # hung too. The shape this replaced -- build under @write -- raised `ThreadError: deadlock;
    # recursive locking` immediately from the offending call, and this comment already named that
    # scenario as the motivation for replacing it, so trading a loud error for a silent wedge would
    # be a straight regression. The claim is released by #complete_resolution's ensure on this path
    # exactly as on any other, so the registry stays re-evaluable for everyone else.
    def resolve
      resolved = @state.resolved
      return hand_out(resolved) if resolved

      loop do
        gate = nil
        reentrant = false
        claimed = @write.synchronize do
          state = @state
          next false if state.resolved

          if state.resolving
            reentrant = state.resolving.owner.equal?(::Fiber.current)
            gate = state.resolving.gate
            next false
          end

          gate = ::Thread::Queue.new
          @state = state.with(resolving: Claim.new(gate: gate, owner: ::Fiber.current))
          true
        end

        return complete_resolution(gate) if claimed

        raise_reentrant! if reentrant

        resolved = @state.resolved
        return hand_out(resolved) if resolved

        gate&.pop
      end
    end

    # SEAM-6's "separate unchecked/internal swap seam ... for test-scoped overrides", taken
    # explicitly and in the safest shape Ruby offers: block-scoped, restoring the prior snapshot in
    # an ensure, performing no conflict check. It records the override as auto-resolved rather than
    # explicitly installed, because a swap is not an install.
    def swap(provider)
      raise Dexpace::InvalidArgumentError, "swap requires a block" unless block_given?

      previous = @write.synchronize do
        was = @state
        @state = was.with(resolved: provider, handed_out: false, explicit: false)
        was
      end
      begin
        yield provider
      ensure
        # Two members are spliced from the LIVE state rather than restored from the captured
        # snapshot, and both for the same reason: the live value is the only correct one.
        #
        # `resolving`, because a resolution can be in flight when the swap begins and can complete
        # inside the block, and putting that snapshot's now-closed gate back would leave every
        # later #resolve popping a closed queue forever.
        #
        # `factories`, because a registration is a monotonic require-time fact and Ruby will not
        # re-run a `require`. An adapter registers itself as a side effect of being required
        # (design §3.6), so `require "some-adapter"` inside a swap block is a registration nothing
        # can redo: reverting it loses that adapter for the rest of the process, silently.
        # Verified: `swap(:fake) { register(:key, ...) }` left #registered_keys empty.
        #
        # `resolved`, `explicit` and `handed_out` ARE restored, because scoping an override to a
        # block is what #swap is for, and an #install inside the block is part of that override.
        @write.synchronize do
          live = @state
          @state = previous.with(resolving: live.resolving, factories: live.factories)
        end
      end
    end

    private

    def raise_reentrant!
      raise Dexpace::SeamError,
            "re-entrant #{@seam} resolution: a #{@seam} factory called #resolve on the registry " \
            "that is building it, directly or through a cycle of registries. The provider it " \
            "would return does not exist yet."
    end

    # Runs outside @write.
    #
    # The claim is released in `ensure` and not in a `rescue StandardError`. A factory can raise
    # something that is not a StandardError -- a LoadError from an adapter factory that requires
    # its own dependency lazily is the realistic case, and NotImplementedError, Interrupt and
    # NoMemoryError are the rest -- and a claim released only on the StandardError path leaves a
    # closed gate latched in the slot, after which every later #resolve pops a closed queue,
    # finds nothing resolved and loops: a silent spin at 100% CPU with no exception, which is
    # strictly worse than the deadlock this shape replaced. It also breaks SEAM-7's "an UNRESOLVED
    # state MUST remain re-evaluable", which is the contract this method exists to keep.
    #
    # An explicit #install that won the race while this was building keeps its provider and the
    # freshly built one is discarded -- and is closed, because a transport provider is the
    # archetypal owner of a pool (SEAM-14) and this phase already closes exactly this shape in
    # Completer#fulfil (SEAM-30). close_quietly is a no-op on a provider with no #close.
    def complete_resolution(gate)
      provider = build_sole_provider
      settled = @write.synchronize do
        @state = @state.with(resolved: provider, explicit: false) unless @state.resolved
        @state.resolved
      end
      Dexpace.close_quietly(provider) unless settled.equal?(provider)
      hand_out(settled)
    ensure
      @write.synchronize { @state = @state.with(resolving: nil) }
      gate.close
    end

    def hand_out(provider)
      @write.synchronize { @state = @state.with(handed_out: true) } unless @state.handed_out
      provider
    end

    def build_sole_provider
      keys = @state.factories.keys
      if keys.empty?
        raise Dexpace::SeamError,
              "no #{@seam} provider is registered. Require an adapter gem that registers one, " \
              "or install one explicitly with #{@installer}."
      end
      if keys.size > 1
        raise Dexpace::SeamError,
              "more than one #{@seam} provider is registered " \
              "(#{keys.map(&:inspect).join(", ")}). Install the one you want explicitly with " \
              "#{@installer}."
      end

      key = keys.first
      factory = @state.factories.fetch(key)
      provider = factory.respond_to?(:call) ? factory.call : factory.new
      unless @conforms.call(provider)
        raise Dexpace::SeamError,
              "the #{@seam} factory registered under #{key.inspect} produced a " \
              "#{provider.class}, which does not implement the seam"
      end

      provider
    end

    def refuse(provider)
      raise Dexpace::InvalidArgumentError,
            "a #{@seam} provider must implement the seam; #{provider.class} does not"
    end

    # DEF-21, picked up here: the runtime half of design §2.3's version-skew guard.
    #
    # Hand-rolled rather than built on Gem::Requirement, because `Gem` is undefined under
    # `ruby --disable-gems` (verified on 3.2.11 and 4.0.6) and a library may not assume RubyGems is
    # loaded; `rubygems` is also not on phase 0's require allowlist. Only the two-segment `~> M.N`
    # form design §2.3 mandates is accepted -- anything else is refused rather than partially
    # reinterpreted -- and Task 8's test cross-checks this comparison against
    # Gem::Requirement#satisfied_by? over a grid, where RubyGems is present.
    def assert_core_version!(key, requirement)
      match = CORE_REQUIREMENT.match(requirement.to_s)
      unless match
        raise Dexpace::InvalidArgumentError,
              "core: must be a two-segment pessimistic requirement such as \"~> 1.2\", " \
              "got #{requirement.inspect}"
      end

      wanted_major = match[1].to_i
      wanted_minor = match[2].to_i
      running = Dexpace::VERSION.split(".", 3)
      return if running[0].to_i == wanted_major && running[1].to_i >= wanted_minor

      raise Dexpace::SeamError,
            "#{@seam} adapter #{key.inspect} was built against dexpace-core #{requirement}, " \
            "but dexpace-core #{Dexpace::VERSION} is loaded"
    end
  end
end
```

- [ ] **Step 5: Write `sig/dexpace/registry.rbs`**

```rbs
module Dexpace
  class Registry
    attr_reader seam: String

    def self.callable?: (untyped object, arity: Integer) -> bool

    def initialize: (seam: String, installer: String, conforms: ^(untyped) -> boolish) -> void
    def registered_keys: () -> Array[untyped]
    def register: (untyped key, untyped factory, core: String) -> self
    def install: (untyped provider) -> self
    def resolve: () -> untyped
    def swap: (untyped provider) { (untyped) -> void } -> void
  end
end
```

`untyped` on the provider is deliberate and is what `NFR-11` wants: a seam's provider is whatever
an adapter supplies, and naming a type here would either be `Object` or a constant outside
`Dexpace::`.

- [ ] **Step 6: Add `require_relative "dexpace/registry"` to `lib/dexpace.rb`**

After the async tree, before the three seam modules Tasks 9, 10 and 12 add.

- [ ] **Step 7: Run the suite to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/registry_test.rb`
Expected: PASS, 28 tests. Then `bundle exec rake rubocop rbs:validate steep`.

---

## Task 8: The version-skew guard (`DEF-21`)

**Requirement IDs:** `NFR-14`, and `SEAM-10`'s replacement — design §10.9 makes multi-loader
de-duplication vacuous in Ruby and names version skew as the real risk. **Design:** "The
version-skew guard (`DEF-21`, picked up here)"; verified Ruby fact 3.

**Files:**
- Test: `gems/dexpace-core/test/dexpace/registry_version_test.rb`
- Modify: `docs/deferred-items.md` is **not** touched here — the register rows were appended during
  planning. This task's deliverable is the proof.

**Interfaces:**
- Consumes: `Dexpace::Registry#register`'s `core:` keyword and its private `#assert_core_version!`
  (Task 7).
- Produces: nothing new in `lib/`. It is a separate task because a reviewer can accept Task 7's
  five branches and still reject how the comparison is proved.

- [ ] **Step 1: Write the failing test**

`gems/dexpace-core/test/dexpace/registry_version_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"

# DEF-21, picked up by phase 2: the runtime half of design §2.3's version-skew guard, which
# SEAM-10's vacuity (design §10.9) makes the real Ruby risk. The comparison is hand-rolled because
# Gem is undefined under `ruby --disable-gems` (verified on 3.2.11 and 4.0.6), so this suite is the
# only place Gem::Requirement appears -- in a test process where Bundler has already loaded it.
class DexpaceRegistryVersionTest < DexpaceTestCase
  def registry
    Dexpace::Registry.new(
      seam: "transport",
      installer: "Dexpace::Transport.install",
      conforms: ->(_object) { true },
    )
  end

  def accepts?(requirement)
    registry.register(:adapter, -> { :provider }, core: requirement)
    true
  rescue Dexpace::SeamError
    false
  end

  test "the hand-rolled comparison agrees with Gem::Requirement over a grid" do
    require "rubygems"
    running = Gem::Version.new(Dexpace::VERSION)

    sample(count: 24, seed: 20_260_907) do |random|
      requirement = "~> #{random.rand(0..2)}.#{random.rand(0..3)}"
      expected = Gem::Requirement.new(requirement).satisfied_by?(running)

      assert_equal(expected, accepts?(requirement),
                   "#{requirement.inspect} against dexpace-core #{Dexpace::VERSION}")
    end
  end

  test "the current core version satisfies its own major.minor" do
    major, minor, = Dexpace::VERSION.split(".", 3)

    assert(accepts?("~> #{major}.#{minor}"))
  end

  test "a minor ahead of the running core is skew and is loud" do
    major, minor, = Dexpace::VERSION.split(".", 3)

    error = assert_raises(Dexpace::SeamError) do
      registry.register(:adapter, -> { :p }, core: "~> #{major}.#{minor.to_i + 1}")
    end

    assert_match(/was built against dexpace-core/, error.message)
    assert_match(/#{Regexp.escape(Dexpace::VERSION)}/, error.message)
    assert_match(/:adapter/, error.message)
  end

  test "a different major is skew in both directions" do
    major, minor, = Dexpace::VERSION.split(".", 3)

    assert_raises(Dexpace::SeamError) do
      registry.register(:adapter, -> { :p }, core: "~> #{major.to_i + 1}.#{minor}")
    end
  end

  test "a requirement that is not the two-segment pessimistic form is refused, not reinterpreted" do
    [">= 0.1", "~> 0.1.2", "0.1", "~>0", "", "latest"].each do |requirement|
      error = assert_raises(Dexpace::InvalidArgumentError) do
        registry.register(:adapter, -> { :p }, core: requirement)
      end

      assert_match(/two-segment pessimistic requirement/, error.message, requirement.inspect)
    end
  end

  test "core: is required, so a skew check is never silently skipped" do
    assert_raises(::ArgumentError) { registry.register(:adapter, -> { :p }) }
  end
end
```

`#sample(count:, seed:)` is phase 0's bounded property-style helper; it yields a seeded `Random`
and prints the seed on failure.

- [ ] **Step 2: Run it, then prove it can fail**

**This task has no red phase, and calling it one would be a lie.** Task 7 ships
`#assert_core_version!` whole, so the suite is green the moment it is written; what this task
delivers is the evidence that the comparison is right, not the code. The proof is the break-it run:

```
bundle exec ruby -w gems/dexpace-core/test/dexpace/registry_version_test.rb   # green
```

Then change `running[1].to_i >= wanted_minor` to `==` in `lib/dexpace/registry.rb`, re-run, and
confirm the grid test goes red on a requirement such as `~> 0.0` against a `0.1.x` core. Change it
to `>` and confirm the "satisfies its own major.minor" test goes red. Restore both. A comparison
that has only ever been seen to agree has not been tested against disagreement.

- [ ] **Step 3: Verify the `--disable-gems` claim the design rests on**

```bash
mise exec ruby@3.2.11 -- ruby --disable-gems -e 'p defined?(Gem), defined?(Gem::Version)'
mise exec ruby@4.0.6  -- ruby --disable-gems -e 'p defined?(Gem), defined?(Gem::Version)'
```

Expected: `nil` and `nil` on both. This is the fact that makes the hand-rolled comparison
non-negotiable; re-run it rather than trusting the design's record of it.

- [ ] **Step 4: Confirm core still requires nothing new**

Run: `bundle exec rake gates:require_allowlist`
Expected: PASS, with `uri` still the only `require` in core outside `require_relative`. The
`require "rubygems"` above is in `test/`, which the audit does not scan and which `.gemspec` does
not ship.

---

## Task 9: `Dexpace::Transport` — the synchronous transport seam

**Requirement IDs:** `SEAM-11`, `SEAM-13`, `SEAM-15`, and `SEAM-2` for this seam; `SEAM-12`'s
*shape*, with the requirement itself ⏳ against `DEF-22` because the phase ships no transport
implementation for it to be a property of.
**Design:** "`Dexpace::Transport` — the synchronous transport seam"; §3.2; the "What a seam is in
this port" section.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/transport.rb`,
  `gems/dexpace-core/lib/dexpace/bridge/async_over.rb`,
  `gems/dexpace-core/sig/dexpace/transport.rbs`,
  `gems/dexpace-core/sig/dexpace/bridge/async_over.rbs`,
  `gems/dexpace-core/test/support/fake_transport.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`, `gems/dexpace-core/sig/dexpace.rbs`
- Test: `gems/dexpace-core/test/dexpace/transport_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Registry` (Task 7), `Dexpace::ClosedError` (Task 1), `Dexpace::Async::Completer`
  (Task 5), `Dexpace.close_quietly` (Task 2).
- Produces: `Dexpace::Transport` — `.conforms?(object)`, `.register(key, factory, core:)`,
  `.install(transport)`, `.resolve`, `.registered_keys`, `.swap(transport) { }`,
  `.async_over(transport, executor:)`; and `Dexpace::Bridge::AsyncOver`, whose instances respond
  to `#call(request, options, cancellation)`, return a `Dexpace::Async::Future` and are
  `Dexpace::Closeable`. Task 11 tests `.async_over`; Task 10 mirrors the module's shape.
  `FakeTransport` is consumed by Tasks 10 and 11.

**The bridge is `Dexpace::Bridge::AsyncOver`, not `Dexpace::Transport::AsyncOver`.** Deviation P2-1
argues that a seam constant must not sit beside the adapter namespaces `Dexpace::Transport::NetHTTP`
and `::AsyncHTTP`, and a bridge is no more entitled to that seat than a seam is; a reader meeting
`Dexpace::Transport::AsyncOver` beside two adapter modules cannot tell which of the three core
owns. `Dexpace::Bridge` holds both bridges, one per file, and is recorded as deviation P2-13.

`.async_over`'s implementation lands here because it belongs on this module; **its behaviour is
tested in Task 11**, alongside the other bridge, so the two halves of `SEAM-18` are reviewed
together.

- [ ] **Step 1: Write `test/support/fake_transport.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The in-memory fake the roadmap's cross-cutting constraint 4 requires of phases 1 through 7:
# implements only SEAM-11, holds no socket, and observes the cancellation token at the one point a
# real transport would.
#
# It lives in dexpace-core's test tree and is not public API. A published fake would need a YARD
# block, an RBS mirror and a row in the runtime surface manifest, after which changing its shape
# would be a public API change diffed against a release tag (NFR-4) -- a real cost paid forever for
# a convenience. dexpace-conformance is the gem chartered to publish adapter test doubles (§9.3)
# and it is phase 8's; DEF-29 records the move.
class FakeTransport
  # @return [Array<Array>] one [request, options, cancellation] triple per call
  attr_reader :calls

  def initialize(response: nil, raises: nil, before_return: nil)
    @response = response
    @raises = raises
    @before_return = before_return
    @calls = []
    @mutex = ::Thread::Mutex.new
  end

  def call(request, options, cancellation)
    @mutex.synchronize { @calls << [request, options, cancellation] }
    @before_return&.call
    raise @raises if @raises

    @response
  end
end

# A transport that ignores its options entirely, for SEAM-11's "a transport that ignores options
# MUST behave identically to the no-options call".
class OptionsIgnoringTransport
  def initialize(response) = @response = response

  def call(_request, _options, _cancellation) = @response
end

# The smallest thing that satisfies the executor duck type SEAM-18 requires the caller to supply:
# an object responding to #post. Running the block inline is what makes the bridge's behaviour
# deterministic in a test; phase 8's dexpace-async-thread supplies a real bounded pool.
class InlineExecutor
  def post(&block) = block.call
end
```

- [ ] **Step 2: Write the failing test**

`gems/dexpace-core/test/dexpace/transport_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/fake_transport"

# SEAM-11, SEAM-12, SEAM-13, SEAM-15, SEAM-2. A transport is any object responding to
# #call(request, options, cancellation) and returning a Dexpace::Response. #call is the convergence
# point of Ruby's own middleware ecosystems (porting-method/bf484e8e, P14), so a bare lambda is a
# valid transport and phase 4's Dexpace::Pipeline can stand in wherever one is expected (PIPE-26).
class DexpaceTransportTest < DexpaceTestCase
  CORE = "~> 0.0"

  test "conforms? accepts every callable shape that can take the seam's three arguments" do
    assert(Dexpace::Transport.conforms?(->(_request, _options, _cancellation) {}))
    assert(Dexpace::Transport.conforms?(proc { |_request, _options, _cancellation| }))
    assert(Dexpace::Transport.conforms?(->(*) {}))
    assert(Dexpace::Transport.conforms?(FakeTransport.new))
    assert(Dexpace::Transport.conforms?(OptionsIgnoringTransport.new(:response)))
  end

  test "conforms? refuses the wrong arity and anything that is not callable" do
    refute(Dexpace::Transport.conforms?(->(_request) {}))
    refute(Dexpace::Transport.conforms?(Object.new))
    refute(Dexpace::Transport.conforms?(nil))
  end

  test "the registry starts empty, so SEAM-1 holds on a bare require" do
    assert_empty(Dexpace::Transport.registered_keys)
  end

  test "install refuses an object that does not implement the seam" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Transport.install(Object.new) }

    assert_match(/must implement the seam/, error.message)
  end

  test "swap scopes an override to its block" do
    transport = ->(_request, _options, _cancellation) { :response }

    Dexpace::Transport.swap(transport) do
      assert_same(transport, Dexpace::Transport.resolve)
    end

    assert_raises(Dexpace::SeamError) { Dexpace::Transport.resolve }
  end

  test "register and resolve go through one registry, and the error names no gem" do
    error = assert_raises(Dexpace::SeamError) { Dexpace::Transport.resolve }

    assert_match(/no transport provider is registered/, error.message)
    refute_match(/net_http|async_http|net\/http/i, error.message, "SEAM-2")
  end

  test "an options-ignoring transport behaves identically with and without options" do
    transport = OptionsIgnoringTransport.new(:response)
    populated = Dexpace::RequestOptions.builder.tap do |builder|
      builder.timeout = 2.5
      builder.max_retries = 7
    end.build

    refute_equal(Dexpace::RequestOptions::EMPTY, populated, "the two calls really differ")

    assert_equal(
      transport.call(:request, Dexpace::RequestOptions::EMPTY, nil),
      transport.call(:request, populated, nil),
      "SEAM-11: options are inert immutable data, so ignoring them is not reading them",
    )
  end

  # SEAM-12 is a property of an implementation and phase 2 ships none; what the seam owes is that
  # nothing forces per-request state onto shared storage. The fake keeps every call in a local and
  # returns everything it produces, and this is the harness phase 8's adapters inherit.
  test "a conforming transport survives concurrent calls with no cross-talk" do
    transport = ->(request, _options, _cancellation) { request }
    results = ::Queue.new

    32.times.map { |i| ::Thread.new { results << transport.call(i, nil, nil) } }.each(&:join)

    seen = []
    seen << results.pop until results.empty?
    assert_equal((0...32).to_a, seen.sort)
  end

  test "async_over requires a caller-supplied executor and refuses anything without #post" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Transport.async_over(FakeTransport.new, executor: Object.new)
    end

    assert_match(/no default/, error.message, "SEAM-18: there is intentionally no default executor")
  end

  test "async_over refuses a non-conforming transport" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Transport.async_over(Object.new, executor: InlineExecutor.new)
    end
  end

  test "ClosedError is the documented post-close failure mode" do
    assert_operator(Dexpace::ClosedError, :<, ::StandardError)
    assert_operator(Dexpace::ClosedError, :<, Dexpace::Error)
  end
end
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/transport_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Transport`.

- [ ] **Step 4: Write `lib/dexpace/transport.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "registry"
require_relative "closeable"
require_relative "bridge/async_over"
require_relative "error/invalid_argument_error"

module Dexpace
  # The synchronous transport seam: a duck type, a .conforms? predicate, and an RBS interface in
  # sig/. There is no module to include and no class to inherit.
  #
  # A transport is any object responding to #call(request, options, cancellation) and returning a
  # Dexpace::Response. #call is the convergence point of Ruby's own middleware ecosystems (Rack,
  # Faraday adapters), so a bare lambda is a valid transport, phase 4's Dexpace::Pipeline can stand
  # in wherever a transport is expected (PIPE-26), and no adapter has to declare conformance it
  # structurally already has.
  #
  # SEAM-11's three clauses. *Single operation*: one #call, one response; there is no batch entry
  # point to add later. *No pre-buffering*: the returned response's body is a lazily-read stream the
  # caller owns and closes -- stated at the seam here, proved over a real socket in phase 8 and
  # asserted per adapter by dexpace-conformance (DEF-22). *Options may be ignored*: options are
  # always passed and are always an immutable Dexpace::RequestOptions, so "behaves identically" is
  # structural rather than a discipline.
  #
  # SEAM-13's cancellation reaches a transport as the third argument -- an ordinary value, never an
  # ambient interrupt -- and a transport honours it by re-checking #cancelled? at every point it
  # resumes from a wait.
  #
  # SEAM-15 is a MAY -- "a port MAY choose a [post-close failure] mode but SHOULD document it" --
  # and the documented mode is narrower than "a send after close raises": **a transport that owns
  # the resource it closed raises Dexpace::ClosedError from a later send.** A wrapper that only
  # borrows closes nothing and stays usable, which is why both SEAM-18 bridges answer #close,
  # release nothing and keep working; raising there would break XCUT-22's "the caller owns its
  # lifecycle and may keep using it after the SDK component is closed". Phase 2 ships no owning
  # transport, so it ships the error class and the rule and no raise site -- phase 8's adapters are
  # the first owners, and dexpace-conformance is where the raise is asserted.
  #
  # One gap, admitted rather than papered over: the synchronous and asynchronous seams have the
  # same structural shape and differ only in return type, so .conforms? cannot tell an async
  # transport registered here from a sync one. They are two registries and an adapter names which
  # it registers into; dexpace-conformance asserts the return type. A predicate claiming to
  # distinguish them would be a false proof, which is the position design §10.10 takes on HTTP-2.
  module Transport
    REGISTRY = Registry.new(
      seam: "transport",
      installer: "Dexpace::Transport.install",
      conforms: ->(object) { Dexpace::Transport.conforms?(object) },
    )
    private_constant :REGISTRY

    class << self
      def conforms?(object) = Dexpace::Registry.callable?(object, arity: 3)

      def register(key, factory, core:)
        REGISTRY.register(key, factory, core: core)
        self
      end

      def install(transport)
        REGISTRY.install(transport)
        self
      end

      def resolve = REGISTRY.resolve

      def registered_keys = REGISTRY.registered_keys

      def swap(transport, &block) = REGISTRY.swap(transport, &block)

      # SEAM-18's sync-to-async bridge. The executor is required and has no default, because a
      # shared global pool would be starved by blocking work -- the requirement says so in as many
      # words. It is a duck type exposing #post { ... }; core ships no implementation, which is
      # SEAM-1 again, and phase 8's dexpace-async-thread supplies the first one.
      def async_over(transport, executor:)
        unless conforms?(transport)
          raise Dexpace::InvalidArgumentError,
                "a transport responds to #call(request, options, cancellation); " \
                "#{transport.class} does not"
        end
        unless executor.respond_to?(:post)
          raise Dexpace::InvalidArgumentError,
                "async_over requires an executor responding to #post; there is intentionally " \
                "no default, because a shared global pool would be starved by blocking work"
        end

        Dexpace::Bridge::AsyncOver.new(transport, executor)
      end
    end
  end
end
```

- [ ] **Step 5: Write `lib/dexpace/bridge/async_over.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../async/completer"
require_relative "../closeable"

module Dexpace
  # The two sync<->async bridges SEAM-18 requires, each in its own file.
  #
  # Not under Dexpace::Transport: deviation P2-1 argues that a seam constant must not sit beside
  # the adapter namespaces Dexpace::Transport::NetHTTP and ::AsyncHTTP, and a bridge is no more
  # entitled to that seat than a seam is.
  module Bridge
    # A blocking transport presented as an asynchronous one. This is the one place phase 2 itself
    # can produce a response no caller will take delivery of, so it is where SEAM-30 is exercised
    # rather than merely stated.
    #
    # Closeable and **not owning**: it holds a caller-supplied transport and a caller-supplied
    # executor and creates neither, so close latches and releases nothing. That is SEAM-14's
    # ownership clause and XCUT-22's "a caller-supplied client or executor is NEVER closed by the
    # SDK", and it is why close does not cascade to the wrapped transport.
    class AsyncOver
      include Dexpace::Closeable

      def initialize(transport, executor)
        @transport = transport
        @executor = executor
        initialize_closeable(owned: false)
      end

      # The future is returned before anything fallible reaches the caller. A raise from
      # #post itself -- a shut-down pool, a rejected task -- is routed to the failure channel
      # exactly as a raise from the wrapped transport is, because ASYNC-2 and PIPE-30 require one
      # normalisation and a caller of an async seam should never have to rescue around #call.
      def call(request, options, cancellation)
        completer = Dexpace::Async::Completer.new
        begin
          @executor.post { deliver(completer, request, options, cancellation) }
        rescue ::StandardError => error
          completer.fail(error)
        end
        completer.future
      end

      private

      # Check-after-resume (design §3.3): the send may have suspended, so the cancellation state is
      # re-read before acting on the value it produced. If cancelled, the response is closed and
      # the future settles through the failure channel rather than delivering. Completer#fulfil
      # closes the orphan on a lost race too, so SEAM-30 holds even if this branch is missed.
      #
      # The whole body is inside the rescue, deliberately. Written with a method-level `else` the
      # delivery branch sits OUTSIDE the rescue's protection, so anything raised between the send
      # returning and the future settling -- reading #cancelled? off an argument that is not a
      # token is the cheapest example -- escapes the posted block, kills the worker under a real
      # threaded executor, and leaves the future permanently unsettled with every #value blocked
      # on it. Reproduced on 3.2.11, 3.4.10 and 4.0.6.
      def deliver(completer, request, options, cancellation)
        response = @transport.call(request, options, cancellation)
        if cancellation&.cancelled?
          Dexpace.close_quietly(response)
          completer.request_cancel(cancellation.reason)
        else
          completer.fulfil(response)
        end
      rescue ::StandardError => error
        completer.fail(error)
      end
    end
  end
end
```

`sig/dexpace/bridge/async_over.rbs` declares the class, its `include Dexpace::Closeable`, and
`#call` returning `Dexpace::Async::Future`.

- [ ] **Step 6: Write `sig/dexpace/transport.rbs`**

```rbs
module Dexpace
  interface _Transport
    def call: (untyped request, untyped options, Dexpace::Cancellation? cancellation) -> untyped
  end

  module Transport
    def self.conforms?: (untyped object) -> bool
    def self.register: (untyped key, untyped factory, core: String) -> singleton(Dexpace::Transport)
    def self.install: (untyped transport) -> singleton(Dexpace::Transport)
    def self.resolve: () -> untyped
    def self.registered_keys: () -> Array[untyped]
    def self.swap: (untyped transport) { (untyped) -> void } -> void
    def self.async_over: (untyped transport, executor: untyped) -> Dexpace::Bridge::AsyncOver
  end
end
```

`interface _Transport` is the static half of the seam — what a consumer's own `steep check` sees at
a parameter — and is the artifact `data-modeling/a13e9ffe`'s Sorbet abstract module is replaced by
(`docs/knowledge/notes/data-modeling.md`).

- [ ] **Step 7: Add the two `require_relative`s to `lib/dexpace.rb`**

`dexpace/bridge/async_over` then `dexpace/transport`, after `dexpace/registry`.

- [ ] **Step 8: Run the suite to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/transport_test.rb`
Expected: PASS. Then `bundle exec rake rubocop rbs:validate steep`.

Then confirm the file stands alone, which is what the `bridge/async_over` require above buys and
what `lib/dexpace.rb`'s ordering must not be the only thing supplying:

```bash
bundle exec ruby -w -Igems/dexpace-core/lib -e \
  'require "dexpace/transport"
   Dexpace::Transport.async_over(->(_r, _o, _c) {}, executor: Class.new { def post = nil }.new)'
```

Expected: no output. Without the require it is
`NameError: uninitialized constant Dexpace::Bridge`.

---

## Task 10: `Dexpace::AsyncTransport` — the asynchronous transport seam

**Requirement IDs:** `SEAM-16`, and `SEAM-2` for this seam. **Design:** "`Dexpace::AsyncTransport`
— the asynchronous transport seam"; deviation P2-1.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/async_transport.rb`,
  `gems/dexpace-core/lib/dexpace/bridge/sync_over.rb`,
  `gems/dexpace-core/sig/dexpace/async_transport.rbs`,
  `gems/dexpace-core/sig/dexpace/bridge/sync_over.rbs`,
  `gems/dexpace-core/test/support/fake_async_transport.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`, `gems/dexpace-core/sig/dexpace.rbs`
- Test: `gems/dexpace-core/test/dexpace/async_transport_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Registry` (Task 7), `Dexpace::Async::Future` and `Completer` (Task 5),
  `Dexpace::SeamError` (Task 1).
- Produces: `Dexpace::AsyncTransport` — the same five registry entry points and `.conforms?`, plus
  `.sync_over(transport)`; and `Dexpace::Bridge::SyncOver`, which is `Dexpace::Closeable` for the
  same reason `AsyncOver` is. `FakeAsyncTransport` is consumed by Task 11.

- [ ] **Step 1: Write `test/support/fake_async_transport.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The in-memory async fake: implements only SEAM-16, and settles its future synchronously unless a
# `settle_later` block is supplied, so a test can drive the completion race deliberately.
class FakeAsyncTransport
  attr_reader :calls, :completer

  def initialize(response: nil, raises: nil, settle_later: false)
    @response = response
    @raises = raises
    @settle_later = settle_later
    @calls = []
  end

  def call(request, options, cancellation)
    @calls << [request, options, cancellation]
    @completer = Dexpace::Async::Completer.new
    settle unless @settle_later
    @completer.future
  end

  def settle
    return @completer.fail(@raises) if @raises

    @completer.fulfil(@response)
  end
end
```

- [ ] **Step 2: Write the failing test**

`gems/dexpace-core/test/dexpace/async_transport_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/fake_async_transport"

# SEAM-16 and SEAM-2. A separate top-level constant and a separate registry from
# Dexpace::Transport, which the design does not name (deviation P2-1): SEAM-2 enumerates the
# synchronous and asynchronous transports as two distinct seams, so one registry keyed by kind
# would merge two concerns the requirement separates. The name is not Dexpace::Transport::Async,
# because that constant would sit beside the adapter namespaces Dexpace::Transport::NetHTTP and
# ::AsyncHTTP -- a seam beside its own implementations.
class DexpaceAsyncTransportTest < DexpaceTestCase
  test "conforms? has the same shape as the sync seam's, and that is an admitted gap" do
    assert(Dexpace::AsyncTransport.conforms?(FakeAsyncTransport.new))
    assert(Dexpace::AsyncTransport.conforms?(->(_r, _o, _c) {}))
    refute(Dexpace::AsyncTransport.conforms?(Object.new))
    # The two seams differ only in return type, which no predicate can check before the first
    # call. They are two registries, and an adapter names which it registers into.
    assert(Dexpace::Transport.conforms?(FakeAsyncTransport.new))
  end

  test "the registry starts empty and is not the sync seam's" do
    assert_empty(Dexpace::AsyncTransport.registered_keys)

    Dexpace::Transport.swap(->(_r, _o, _c) { :sync }) do
      assert_raises(Dexpace::SeamError) { Dexpace::AsyncTransport.resolve }
    end
  end

  test "the zero-candidate error names this seam and no gem" do
    error = assert_raises(Dexpace::SeamError) { Dexpace::AsyncTransport.resolve }

    assert_match(/no async transport provider is registered/, error.message)
    assert_match(/Dexpace::AsyncTransport\.install/, error.message)
    refute_match(/async_http|net_http/i, error.message, "SEAM-2")
  end

  test "a future that settles with a response is delivered, and the caller closes it" do
    response = Object.new
    transport = FakeAsyncTransport.new(response: response)

    future = transport.call(:request, nil, nil)

    assert_instance_of(Dexpace::Async::Future, future)
    assert_same(response, future.value, "SEAM-16: never a null success")
  end

  test "sync_over refuses a non-conforming transport" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::AsyncTransport.sync_over(Object.new) }
  end
end
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/async_transport_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::AsyncTransport`.

- [ ] **Step 4: Write `lib/dexpace/async_transport.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "registry"
require_relative "async/future"
require_relative "bridge/sync_over"
require_relative "error/seam_error"
require_relative "error/invalid_argument_error"

module Dexpace
  # The asynchronous transport seam: any object responding to
  # #call(request, options, cancellation) and returning a Dexpace::Async::Future.
  #
  # A second top-level constant and a second registry rather than a namespace under
  # Dexpace::Transport (deviation P2-1). SEAM-2 enumerates the two transports as two seams, and
  # Dexpace::Transport::Async would sit beside Dexpace::Transport::NetHTTP and ::AsyncHTTP -- two
  # adapter namespaces -- which is the confusion SEAM-2 exists to prevent.
  module AsyncTransport
    REGISTRY = Registry.new(
      seam: "async transport",
      installer: "Dexpace::AsyncTransport.install",
      conforms: ->(object) { Dexpace::AsyncTransport.conforms?(object) },
    )
    private_constant :REGISTRY

    class << self
      def conforms?(object) = Dexpace::Registry.callable?(object, arity: 3)

      def register(key, factory, core:)
        REGISTRY.register(key, factory, core: core)
        self
      end

      def install(transport)
        REGISTRY.install(transport)
        self
      end

      def resolve = REGISTRY.resolve

      def registered_keys = REGISTRY.registered_keys

      def swap(transport, &block) = REGISTRY.swap(transport, &block)

      # SEAM-18's async-to-sync bridge.
      def sync_over(transport)
        unless conforms?(transport)
          raise Dexpace::InvalidArgumentError,
                "an async transport responds to #call(request, options, cancellation) and " \
                "returns a Dexpace::Async::Future; #{transport.class} does not"
        end

        Dexpace::Bridge::SyncOver.new(transport)
      end
    end
  end
end
```

- [ ] **Step 5: Write `lib/dexpace/bridge/sync_over.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../async/future"
require_relative "../closeable"
require_relative "../error/seam_error"

module Dexpace
  module Bridge
    # An asynchronous transport presented as a blocking one.
    #
    # SEAM-18's three clauses. *Unwrap the async-wrapper exception*: this port never wraps --
    # Completer#fail stores the error and Future#value re-raises that object -- so the clause holds
    # structurally and the test asserts object identity rather than an equal message. *Honour
    # interruption*: the wait takes the cancellation token, and on cancellation it cancels the
    # in-flight future and raises Dexpace::CancelledError. "Restore the interrupt flag" is vacuous
    # for exactly the reason ASYNC-4 is (design §10.5): a port that never delivers an interrupt
    # cannot leave a stale one set. "Surface an interrupted-I/O error" is read as a typed
    # cancellation error rather than an IOError, because XCUT-4's I/O family is for transport
    # failures and a cancellation is not one (deviation P2-4). *Options are threaded*: they are
    # passed through unchanged, and a test asserts the exact object arrives.
    #
    # Closeable and not owning, for the same reason AsyncOver is: the wrapped transport is the
    # caller's (SEAM-14, XCUT-22).
    class SyncOver
      include Dexpace::Closeable

      def initialize(transport)
        @transport = transport
        initialize_closeable(owned: false)
      end

      def call(request, options, cancellation)
        future = @transport.call(request, options, cancellation)
        unless future.is_a?(Dexpace::Async::Future)
          raise Dexpace::SeamError,
                "an async transport must return a Dexpace::Async::Future, got #{future.class}"
        end

        future.value(cancellation: cancellation)
      end
    end
  end
end
```

- [ ] **Step 6: Write `sig/dexpace/async_transport.rbs` and `sig/dexpace/bridge/sync_over.rbs`**

`sig/dexpace/async_transport.rbs` mirrors Task 9's file, with `interface _AsyncTransport` whose
`#call` returns `Dexpace::Async::Future` and `.sync_over` returning `Dexpace::Bridge::SyncOver`.
`sig/dexpace/bridge/sync_over.rbs` declares the class, its `include Dexpace::Closeable`, and
`#call` returning `untyped`.

- [ ] **Step 7: Add the two `require_relative`s to `lib/dexpace.rb`**

`dexpace/bridge/sync_over` then `dexpace/async_transport`.

- [ ] **Step 8: Run the suite to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/async_transport_test.rb`
Expected: PASS. Then `bundle exec rake rubocop rbs:validate steep`, and the standalone-require
check Task 9 Step 8 runs, for this file:

```bash
bundle exec ruby -w -Igems/dexpace-core/lib -e \
  'require "dexpace/async_transport"; Dexpace::AsyncTransport.sync_over(->(_r, _o, _c) {})'
```

Expected: no output.

---

## Task 11: `SEAM-18` — the two bridges, and `SEAM-30` exercised

**Requirement IDs:** `SEAM-18`, and `SEAM-30` at a real call site. **Design:** "`SEAM-18` — the two
bridges"; §3.3's check-after-resume rule; deviation P2-4.

**Files:**
- Test: `gems/dexpace-core/test/dexpace/transport/async_over_test.rb`,
  `gems/dexpace-core/test/dexpace/async_transport/sync_over_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Transport.async_over` and `Dexpace::Bridge::AsyncOver` (Task 9),
  `Dexpace::AsyncTransport.sync_over` and `Dexpace::Bridge::SyncOver` (Task 10), `FakeTransport`,
  `OptionsIgnoringTransport`, `InlineExecutor` (Task 9), `FakeAsyncTransport` (Task 10),
  `Dexpace::Cancellation` (Task 4).
- Produces: nothing in `lib/`. A separate task because `SEAM-18` is a MUST whose proof is the
  deliverable, and a reviewer can accept both modules and reject the proof.

- [ ] **Step 1: Write the failing tests**

`gems/dexpace-core/test/dexpace/transport/async_over_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_transport"

# SEAM-18's sync-to-async half, and the one place in phase 2 where core itself can produce a
# response no caller will take delivery of -- which is where SEAM-30 is exercised rather than
# merely stated.
class DexpaceTransportAsyncOverTest < DexpaceTestCase
  class FakeResponse
    include Dexpace::Closeable

    attr_reader :closes

    def initialize
      @closes = 0
      initialize_closeable(owned: true)
    end

    private

    def release
      @closes += 1
    end
  end

  test "delivers the response and threads the exact options and token through" do
    response = FakeResponse.new
    sync = FakeTransport.new(response: response)
    async = Dexpace::Transport.async_over(sync, executor: InlineExecutor.new)
    options = Dexpace::RequestOptions::EMPTY
    token = Dexpace::Cancellation.none

    future = async.call(:request, options, token)

    assert_same(response, future.value)
    assert_same(options, sync.calls.first[1], "SEAM-18: per-call options are threaded, not dropped")
    assert_same(token, sync.calls.first[2])
    assert_equal(0, response.closes, "a delivered response is the caller's to close")
  end

  test "routes a synchronous raise from the wrapped transport to the failure channel" do
    boom = ::IOError.new("connection reset")
    async = Dexpace::Transport.async_over(
      FakeTransport.new(raises: boom), executor: InlineExecutor.new,
    )

    future = async.call(:request, nil, nil)

    caught = assert_raises(::IOError) { future.value }
    assert_same(boom, caught, "ASYNC-2 / PIPE-30: normalised to the failure channel, not wrapped")
  end

  test "closes the orphaned response when cancellation wins the completion race" do
    response = FakeResponse.new
    source = Dexpace::Cancellation.source
    sync = FakeTransport.new(response: response, before_return: -> { source.cancel(:gave_up) })
    async = Dexpace::Transport.async_over(sync, executor: InlineExecutor.new)

    future = async.call(:request, nil, source.token)

    assert_raises(Dexpace::CancelledError) { future.value }
    assert_equal(1, response.closes,
                 "SEAM-30: check-after-resume closes a response no caller receives")
  end

  test "the bridge's product conforms to the async seam" do
    async = Dexpace::Transport.async_over(FakeTransport.new, executor: InlineExecutor.new)

    assert(Dexpace::AsyncTransport.conforms?(async))
  end

  # ASYNC-2 and PIPE-30 want one normalisation: a caller of an async seam never has to rescue
  # around #call. A shut-down pool raising from #post is the same class of failure as the wrapped
  # transport raising, and goes to the same channel.
  test "a raise from the executor itself settles the future rather than escaping" do
    exploding = Class.new do
      def post(&_block) = raise(::IOError, "the pool is shut down")
    end.new
    async = Dexpace::Transport.async_over(FakeTransport.new(response: :ok), executor: exploding)

    future = async.call(:request, nil, nil)

    error = assert_raises(::IOError) { future.value }
    assert_equal("the pool is shut down", error.message)
  end

  # deliver's delivery branch must sit INSIDE its rescue. Written as a method-level `else` it does
  # not, so anything raised between the send returning and the future settling escapes the posted
  # block -- and under a real threaded executor that kills the worker and leaves the future
  # permanently unsettled. InlineExecutor masks it, because #call's own rescue catches what escapes;
  # this test supplies a threaded executor so it cannot.
  test "a raise after the send but before the settle still settles the future" do
    threaded = Class.new do
      def post(&block) = ::Thread.new(&block)
    end.new
    async = Dexpace::Transport.async_over(
      FakeTransport.new(response: :ok), executor: threaded,
    )

    # :not_a_token raises NoMethodError on #cancelled? inside deliver, before any settle.
    future = async.call(:request, nil, :not_a_token)

    settled = ::Thread.new { future.wait }
    assert(settled.join(5), "ASYNC-2/PIPE-30: the future never settled and #value would block")
    assert_raises(::NoMethodError) { future.value }
  end

  test "the bridge is closeable, owns nothing, and leaves the wrapped transport usable" do
    transport = FakeTransport.new(response: :ok)
    async = Dexpace::Transport.async_over(transport, executor: InlineExecutor.new)

    refute(async.owned?, "SEAM-14 / XCUT-22: the transport and the executor are the caller's")
    assert_nil(async.close)
    assert(async.closed?)
    assert_nil(async.close, "SEAM-14: close is idempotent")
    assert_equal(:ok, async.call(:request, nil, nil).value,
                 "close released nothing, because the bridge created nothing")
  end
end
```

`gems/dexpace-core/test/dexpace/async_transport/sync_over_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_async_transport"

# SEAM-18's async-to-sync half, clause by clause.
class DexpaceAsyncTransportSyncOverTest < DexpaceTestCase
  test "returns the delivered response" do
    response = Object.new
    sync = Dexpace::AsyncTransport.sync_over(FakeAsyncTransport.new(response: response))

    assert_same(response, sync.call(:request, nil, nil))
  end

  test "surfaces the original failure, not a wrapper" do
    boom = ::IOError.new("reset")
    sync = Dexpace::AsyncTransport.sync_over(FakeAsyncTransport.new(raises: boom))

    caught = assert_raises(::IOError) { sync.call(:request, nil, nil) }

    assert_same(boom, caught, "SEAM-18: the pivot never wraps, so there is nothing to unwrap")
  end

  test "honours cancellation by cancelling the in-flight future and raising" do
    transport = FakeAsyncTransport.new(response: :never, settle_later: true)
    sync = Dexpace::AsyncTransport.sync_over(transport)
    source = Dexpace::Cancellation.source
    canceller = ::Thread.new do
      sleep(0.02)
      source.cancel(:interrupted)
    end

    error = assert_raises(Dexpace::CancelledError) { sync.call(:request, nil, source.token) }

    assert_equal(:interrupted, error.reason)
    assert(transport.completer.future.cancelled?,
           "the in-flight future was cancelled, not orphaned")
    canceller.join
  end

  test "threads the exact options object through" do
    options = Dexpace::RequestOptions::EMPTY
    transport = FakeAsyncTransport.new(response: :ok)
    Dexpace::AsyncTransport.sync_over(transport).call(:request, options, nil)

    assert_same(options, transport.calls.first[1])
  end

  test "refuses an async transport that does not return a future" do
    sync = Dexpace::AsyncTransport.sync_over(->(_r, _o, _c) { :not_a_future })

    error = assert_raises(Dexpace::SeamError) { sync.call(:request, nil, nil) }

    assert_match(/must return a Dexpace::Async::Future/, error.message)
  end

  test "the bridge's product conforms to the sync seam" do
    sync = Dexpace::AsyncTransport.sync_over(->(_r, _o, _c) {})

    assert(Dexpace::Transport.conforms?(sync))
  end

  test "the bridge is closeable, owns nothing, and leaves the wrapped transport usable" do
    sync = Dexpace::AsyncTransport.sync_over(FakeAsyncTransport.new(response: :ok))

    refute(sync.owned?)
    assert_nil(sync.close)
    assert(sync.closed?)
    assert_nil(sync.close)
    assert_equal(:ok, sync.call(:request, nil, nil))
  end

  # Two blocking calls arming the SAME token is the shape this bridge creates whenever a caller
  # derives one token per operation and issues two requests under it. A cancellation guard that is
  # per-token rather than per-registration arms only the first waiter, and the second blocks
  # forever -- a SEAM-18 violation that no single-waiter test can see. The join timeout is the
  # assertion: without it the suite hangs instead of failing.
  test "two concurrent waits on one token both unblock when it is cancelled" do
    source = Dexpace::Cancellation.source
    bridges = Array.new(2) do
      Dexpace::AsyncTransport.sync_over(
        ->(_r, _o, _c) { Dexpace::Async::Completer.new.future },
      )
    end
    reasons = ::Queue.new

    threads = bridges.map do |bridge|
      ::Thread.new do
        bridge.call(:request, nil, source.token)
      rescue Dexpace::CancelledError => error
        reasons << error.reason
      end
    end
    sleep(0.05)
    source.cancel(:stop)

    threads.each do |thread|
      assert(thread.join(5), "a waiter never unblocked: SEAM-18's interruption clause is violated")
    end
    seen = []
    seen << reasons.pop until reasons.empty?
    assert_equal(%i[stop stop], seen)
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

If Tasks 9 and 10 landed, these pass immediately. **That is not good enough for a MUST.** Break each
clause deliberately and confirm the matching test goes red, then restore:

1. Drop `options` from `AsyncOver#deliver`'s `@transport.call` — the threading test must fail.
2. Replace `completer.fail(error)` with `completer.fail(RuntimeError.new(error.message))` — the
   identical-object test must fail.
3. Delete the `cancellation&.cancelled?` branch — the orphan-close test must fail, because
   `Completer#fulfil` wins the race and delivers rather than closing.
4. Change `future.value(cancellation: cancellation)` to `future.value` — the cancellation test must
   hang; kill it and confirm, then restore. **Run this one with a timeout**:
   `timeout 20 bundle exec ruby -w gems/dexpace-core/test/dexpace/async_transport/sync_over_test.rb`.
5. In `lib/dexpace/cancellation.rb`, replace `#on_cancel`'s per-registration list with a single
   token-level "already fired" flag — the shape a reader is most likely to reach for, because
   `.any` does need to fire once across several sources. The two-waiter test must then fail on its
   `thread.join(5)` assertion within about five seconds; verified failing on 3.2.11, 3.4.10 and
   4.0.6 during planning. Restore it. **This is the one break-it step that must not be skipped**:
   it is the only test in the phase whose failure mode is a hang rather than an assertion.
6. In `lib/dexpace/bridge/async_over.rb`, remove the `rescue ::StandardError => error` around
   `@executor.post` — the executor-raise test must fail with the `IOError` escaping `#call`
   instead of settling the future.

- [ ] **Step 3: Run them to confirm they pass**

Run both suites, then `mise exec ruby@3.2.11 -- bundle exec rake test:gems` and
`mise exec ruby@4.0.6 -- bundle exec rake test:gems`.

---

## Task 12: `Dexpace::Serde` — the wire-codec seam and its failure hierarchy

**Requirement IDs:** `SEAM-19`, `SEAM-20`, `SEAM-21`, `SEAM-22`'s surviving clause, `SEAM-23`, and
`SEAM-2` for this seam. **Design:** "`Dexpace::Serde` — the wire-codec seam and its failure
hierarchy"; §3.4; §10.13; §10.14; deviation P2-2.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/serde/error.rb`,
  `gems/dexpace-core/lib/dexpace/serde/serialization_error.rb`,
  `gems/dexpace-core/lib/dexpace/serde/deserialization_error.rb`,
  `gems/dexpace-core/lib/dexpace/serde.rb`, the four `sig/` mirrors, and
  `gems/dexpace-core/test/support/fake_codec.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`, `gems/dexpace-core/sig/dexpace.rbs`
- Test: `gems/dexpace-core/test/dexpace/serde_test.rb`,
  `gems/dexpace-core/test/dexpace/serde/error_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Registry` (Task 7), `Dexpace::Error` (phase 1).
- Produces: `Dexpace::Serde` — `.conforms?`, `.missing_methods`, and the five registry entry
  points; `Dexpace::Serde::Error < ::StandardError` including `Dexpace::Error`, with
  `SerializationError` and `DeserializationError` under it. Phase 7's `dexpace-serde-json`
  implements the duck type and raises the three classes.

- [ ] **Step 1: Write `test/support/fake_codec.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A codec that implements the seam and nothing beyond it. It is not a JSON codec and does not
# pretend to be: SEAM-19's point is that a codec declares its own media type, so the fake declares
# an obviously fake one and the test asserts the seam never defaults it.
class FakeCodec
  def media_type = "application/vnd.dexpace.fake"

  def dump_string(value) = value.to_s

  def dump_bytes(value) = value.to_s.b

  # SEAM-20: a streaming variant never closes the caller's target.
  def dump_to(value, sink) = sink.write(dump_string(value))

  def dump_into(value, buffer, offset:)
    encoded = dump_string(value)
    raise ::IndexError, "buffer too small" if offset + encoded.bytesize > buffer.bytesize

    buffer[offset, encoded.bytesize] = encoded
    encoded.bytesize
  end

  # SEAM-21: reads to EOF, never closes the caller's source, and requires an explicit witness --
  # there is no witness-less overload to fall into (SEAM-22's surviving clause).
  def load(source, witness) = witness.call(source.read)
end

# A codec missing one method, so the conformance predicate has something to reject.
class IncompleteCodec
  def media_type = "application/vnd.dexpace.incomplete"
  def dump_string(value) = value.to_s
  def dump_bytes(value) = value.to_s.b
  def dump_to(value, sink) = sink.write(dump_string(value))
  def load(source, witness) = witness.call(source.read)
end
```

- [ ] **Step 2: Write the failing tests**

`gems/dexpace-core/test/dexpace/serde_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/fake_codec"

# SEAM-19, SEAM-20, SEAM-21, SEAM-22's surviving clause, SEAM-2. The seam is a duck type of six
# methods: all four of SEAM-20's allocation profiles ship, and two of them are one Ruby type -- a
# String tagged Encoding::BINARY *is* Ruby's byte array, so #dump_bytes differs from #dump_string
# only in the encoding tag, which is the whole of the distinction the requirement draws (§10.13).
class DexpaceSerdeTest < DexpaceTestCase
  test "conforms? requires all six seam methods and names the missing ones" do
    assert(Dexpace::Serde.conforms?(FakeCodec.new))
    refute(Dexpace::Serde.conforms?(IncompleteCodec.new))
    refute(Dexpace::Serde.conforms?(Object.new))

    assert_equal(%i[dump_into], Dexpace::Serde.missing_methods(IncompleteCodec.new))
  end

  test "the media type is never defaulted at the seam level" do
    refute_respond_to(Dexpace::Serde, :media_type,
                      "SEAM-19: the seam supplies no default and has no fallback to fall back to")
    assert_equal("application/vnd.dexpace.fake", FakeCodec.new.media_type)
  end

  test "a codec that forgets media_type fails conformance rather than stamping the wrong type" do
    forgetful = Class.new(FakeCodec) do
      undef_method :media_type
    end.new

    refute(Dexpace::Serde.conforms?(forgetful))
    assert_equal(%i[media_type], Dexpace::Serde.missing_methods(forgetful))
  end

  test "the registry starts empty and its error names this seam and no gem" do
    assert_empty(Dexpace::Serde.registered_keys)

    error = assert_raises(Dexpace::SeamError) { Dexpace::Serde.resolve }

    assert_match(/no codec provider is registered/, error.message)
    refute_match(/json|oj/i, error.message, "SEAM-2")
  end

  test "install refuses a codec that does not implement the seam" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Serde.install(IncompleteCodec.new) }
  end

  test "swap scopes a codec override to its block" do
    codec = FakeCodec.new

    Dexpace::Serde.swap(codec) do
      assert_same(codec, Dexpace::Serde.resolve)
    end

    assert_raises(Dexpace::SeamError) { Dexpace::Serde.resolve }
  end

  # SEAM-20 and SEAM-21's never-close rule, asserted against the fake so the seam's own harness is
  # not the first place it is tried; dexpace-conformance asserts it per adapter (DEF-22).
  test "the streaming and buffer variants never close the caller's target" do
    codec = FakeCodec.new
    sink = StringIO.new(+"")

    codec.dump_to(:payload, sink)

    refute(sink.closed?, "SEAM-20: a streaming variant must not close the caller's sink")

    source = StringIO.new("payload")
    codec.load(source, ->(text) { text })

    refute(source.closed?, "SEAM-21: decode reads to EOF and does not close the caller's source")
  end

  test "dump_bytes and dump_string differ exactly in the encoding tag" do
    codec = FakeCodec.new

    assert_equal(Encoding::BINARY, codec.dump_bytes(:payload).encoding)
    assert_equal("payload", codec.dump_bytes(:payload).force_encoding(Encoding::UTF_8))
    assert_equal("payload", codec.dump_string(:payload))
  end

  test "dump_into raises IndexError on overflow" do
    assert_raises(::IndexError) do
      FakeCodec.new.dump_into(:a_long_payload, +"    ", offset: 0)
    end
  end

  # SEAM-22's mechanism -- a reflective generic type capture -- is replaced by the witness protocol
  # (§10.14, §7.3, phase 7). The clause that survives the substitution is fixed here: #load takes an
  # explicit witness and there is no witness-less overload.
  test "load requires an explicit witness" do
    assert_raises(::ArgumentError) { FakeCodec.new.load(StringIO.new("x")) }
  end
end
```

`gems/dexpace-core/test/dexpace/serde/error_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# SEAM-23. A class root here, inverting phase 1's module root for the SDK-wide Dexpace::Error, and
# the inversion is deliberate (deviation P2-2): phase 1's root is a module because XCUT-4 puts
# transport errors in Ruby's IOError family and single inheritance makes a class root and that
# requirement mutually exclusive. No competing family exists here, because SEAM-20 and SEAM-21 both
# say a genuine stream I/O error propagates unwrapped rather than being reclassified.
class DexpaceSerdeErrorTest < DexpaceTestCase
  test "the hierarchy is a class root with encode and decode subtypes" do
    assert_operator(Dexpace::Serde::SerializationError, :<, Dexpace::Serde::Error)
    assert_operator(Dexpace::Serde::DeserializationError, :<, Dexpace::Serde::Error)
    assert_operator(Dexpace::Serde::Error, :<, ::StandardError)
  end

  test "every one is caught by rescue Dexpace::Error" do
    [Dexpace::Serde::Error,
     Dexpace::Serde::SerializationError,
     Dexpace::Serde::DeserializationError].each do |klass|
      caught = begin
        raise klass, "boom"
      rescue Dexpace::Error => error
        error
      end

      assert_instance_of(klass, caught)
    end
  end

  test "a serde failure is not in Ruby's IOError family" do
    refute_operator(Dexpace::Serde::Error, :<, ::IOError,
                    "SEAM-20/SEAM-21: a genuine stream I/O error propagates unwrapped instead")
  end

  test "the base type is open for an adapter to subclass" do
    subtype = Class.new(Dexpace::Serde::DeserializationError)

    caught = begin
      raise subtype, "vendor-specific"
    rescue Dexpace::Serde::Error => error
      error
    end

    assert_instance_of(subtype, caught)
  end

  # Adapters raise these from inside a rescue so Ruby sets #cause automatically, rather than
  # leaking the backing library's exception type (serde/5821286d). Stated at the seam here,
  # asserted per adapter in phases 7 and 8.
  test "raising from inside a rescue chains the original as the cause" do
    original = ::RuntimeError.new("the backing library said no")

    caught = begin
      begin
        raise original
      rescue ::RuntimeError
        raise Dexpace::Serde::DeserializationError, "decode failed"
      end
    rescue Dexpace::Serde::Error => error
      error
    end

    assert_same(original, caught.cause)
  end
end
```

- [ ] **Step 3: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/serde_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Serde`.

- [ ] **Step 4: Write the three error files**

`lib/dexpace/serde/error.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  module Serde
    # The root of the seam's SDK-owned failure hierarchy (SEAM-23).
    #
    # A class, where phase 1 made the SDK-wide Dexpace::Error a module. The inversion is deliberate
    # and the rule for every later phase is: the SDK root is a module, a seam-local root with no
    # competing Ruby family is a class. Phase 1's root is a module because XCUT-4 requires transport
    # errors to belong to Ruby's IOError family and single inheritance makes a class root and that
    # requirement mutually exclusive. Nothing competes here: SEAM-20 and SEAM-21 both say a genuine
    # stream I/O error propagates unwrapped rather than being reclassified as a serde failure, so a
    # serde error is never also an IOError. SEAM-23 asks in so many words for "a stable, SDK-owned
    # hierarchy (a base serde failure with encode/decode subtypes)" that is "open for
    # codegen/adapters to add more specific subtypes", and a class root delivers that literally.
    #
    # Including Dexpace::Error keeps `rescue Dexpace::Error` catching it.
    class Error < ::StandardError
      include Dexpace::Error
    end
  end
end
```

`lib/dexpace/serde/serialization_error.rb` and `.../deserialization_error.rb` each
`require_relative "error"` and define a one-line subclass with a YARD block naming the encode or
decode half of `SEAM-20`/`SEAM-21` and the "chain the original as the cause" rule.

- [ ] **Step 5: Write `lib/dexpace/serde.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "registry"
require_relative "serde/error"
require_relative "serde/serialization_error"
require_relative "serde/deserialization_error"

module Dexpace
  # The wire-codec seam: a duck type of six methods, a .conforms? predicate and an RBS interface.
  #
  #   #media_type                        the media type this serializer produces (SEAM-19)
  #   #dump_string(value)                a fresh String                          (SEAM-20)
  #   #dump_bytes(value)                 a fresh Encoding::BINARY String         (SEAM-20)
  #   #dump_to(value, sink)              writes into a caller-owned #write sink; never closes it
  #   #dump_into(value, buffer, offset:) writes at an offset; IndexError on overflow
  #   #load(source, witness)             reads to EOF; never closes the source   (SEAM-21)
  #
  # All four of SEAM-20's allocation profiles ship and two of them are one Ruby type: a String
  # tagged Encoding::BINARY *is* Ruby's byte array, so #dump_bytes differs from #dump_string only
  # in the encoding tag -- which is the whole of the distinction the requirement draws (§10.13).
  # Both ship because the tag is load-bearing at §3.1's encoding boundary.
  #
  # #dump(value, sink) is design §3.4's shorthand for #dump_to and an adapter may define it, but it
  # is deliberately **not** in CONTRACT: a codec implementing the four named profiles conforms
  # without also defining an alias, and requiring the alias would make the shorthand mandatory,
  # which is the opposite of what a shorthand is.
  #
  # SEAM-19's undefaulted media type is enforced here rather than at the codec: .conforms? requires
  # #media_type and this module supplies no default and has no fallback constant, so a codec that
  # forgets it fails registration instead of silently stamping the wrong Content-Type. That the
  # value is *correct* is phase 7's.
  #
  # SEAM-22's reflective generic type capture is replaced by the witness protocol (§10.14, §7.3,
  # phase 7). The clause that survives the substitution is fixed here: #load takes an explicit
  # witness and there is no witness-less overload to fall into.
  module Serde
    CONTRACT = %i[media_type dump_string dump_bytes dump_to dump_into load].freeze
    private_constant :CONTRACT

    REGISTRY = Registry.new(
      seam: "codec",
      installer: "Dexpace::Serde.install",
      conforms: ->(object) { Dexpace::Serde.conforms?(object) },
    )
    private_constant :REGISTRY

    class << self
      def conforms?(object) = CONTRACT.all? { |name| object.respond_to?(name) }

      # @return [Array<Symbol>] the seam methods `object` does not answer, for an error message
      def missing_methods(object) = CONTRACT.reject { |name| object.respond_to?(name) }

      def register(key, factory, core:)
        REGISTRY.register(key, factory, core: core)
        self
      end

      def install(codec)
        REGISTRY.install(codec)
        self
      end

      def resolve = REGISTRY.resolve

      def registered_keys = REGISTRY.registered_keys

      def swap(codec, &block) = REGISTRY.swap(codec, &block)
    end
  end
end
```

- [ ] **Step 6: Write the four `sig/` mirrors**

`sig/dexpace/serde.rbs` carries `interface _Codec` with the six methods and the module's class
methods; the three error files each declare their class and superclass.

- [ ] **Step 7: Add the four `require_relative`s to `lib/dexpace.rb`**

`dexpace/serde/error`, `dexpace/serde/serialization_error`,
`dexpace/serde/deserialization_error`, then `dexpace/serde`.

- [ ] **Step 8: Run both suites to confirm they pass**

Run both, then `bundle exec rake rubocop rbs:validate steep`. RuboCop is where Task 3's cop checks
that nothing under `lib/dexpace/serde/` writes a bare `JSON`.

---

## Task 13: `Dexpace::Operation` — the descriptor and its validation

**Requirement IDs:** `SEAM-26`. **Deferred:** `SEAM-28` (`DEF-1`, target phase 5). **Design:**
"`Dexpace::Operation` — the operation-input projection seam"; §3.5.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/operation.rb`,
  `gems/dexpace-core/sig/dexpace/operation.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`, `gems/dexpace-core/sig/dexpace.rbs`
- Test: `gems/dexpace-core/test/dexpace/operation_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`, `Dexpace::Method`, `Dexpace::InvalidArgumentError` (phase 1).
- Produces: `Dexpace::Operation` — `.build(method:, template:, projections: {})`,
  `.placeholders_in(text)`, `#method`, `#template`, `#projections`, `#placeholders`, and `#with`
  from `Dexpace::Model`. `new` is private. Task 14 adds `#build_request`.

Task 14 adds the request assembly. Splitting them is deliberate: the descriptor's validation is
`SEAM-26`'s and the composition is `SEAM-27`'s, and the composition is the phase's largest
departure from a design sentence.

- [ ] **Step 1: Write the failing test**

`gems/dexpace-core/test/dexpace/operation_test.rb` — the descriptor half:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"

# SEAM-26. A frozen Data descriptor: an HTTP method, a path template with named placeholders, and
# typed projections of inputs onto path / query / header / body. Only method and template are
# required and the four projections default to empty, so "a parameterless GET overriding only
# method+path" is the default construction.
#
# Two placeholder checks at two times, which is what makes SEAM-27's "every placeholder MUST have a
# supplied value" structural rather than a runtime hope: at construction the set of :path
# projection names must equal the set of {name} placeholders, and at #build_request every projected
# path input must have a value.
class DexpaceOperationTest < DexpaceTestCase
  test "a parameterless operation needs only a method and a template" do
    operation = Dexpace::Operation.build(method: "GET", template: "/pets")

    assert_equal(Dexpace::Method.of("GET"), operation.method)
    assert_equal("/pets", operation.template)
    assert_empty(operation.projections)
    assert_empty(operation.placeholders)
  end

  test "the method is coerced through Method.of, so a String never survives as a member" do
    operation = Dexpace::Operation.build(method: "post", template: "/pets")

    assert_instance_of(Dexpace::Method, operation.method)
    assert_equal("POST", operation.method.to_s)
  end

  test "a missing required field fails with SEAM-29's message form" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(method: "GET", template: nil)
    end

    assert_equal("template is required", error.message)

    method_error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(method: nil, template: "/pets")
    end

    assert_equal("method is required", method_error.message)
  end

  test "an empty template is legal, because SEAM-27 says an empty path leaves the base untouched" do
    operation = Dexpace::Operation.build(method: "GET", template: "")

    assert_equal("", operation.template)
  end

  test "every template placeholder must have a path projection" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(method: "GET", template: "/pets/{id}")
    end

    assert_match(/"id"/, error.message)
    assert_match(/no path projection/, error.message)
  end

  test "a path projection naming no placeholder is refused" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(
        method: "GET", template: "/pets", projections: { id: [:path, "id"] },
      )
    end

    assert_match(/name no template placeholder/, error.message)
  end

  test "an unbalanced brace and an empty placeholder are refused" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(method: "GET", template: "/pets/{id")
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(method: "GET", template: "/pets/}")
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(method: "GET", template: "/pets/{}")
    end
  end

  test "a projection targeting something other than the four parts is refused, naming them" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(
        method: "GET", template: "/pets", projections: { biscuit: [:cookie, "c"] },
      )
    end

    assert_match(/:path/, error.message)
    assert_match(/:cookie/, error.message)
  end

  test "a projection with no wire name is refused" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(
        method: "GET", template: "/pets", projections: { tag: [:query, ""] },
      )
    end
  end

  test "at most one body projection" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(
        method: "POST", template: "/pets", projections: { a: [:body, "a"], b: [:body, "b"] },
      )
    end
  end

  test "projections must be a Hash, and the error names what was passed" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(method: "GET", template: "/pets", projections: [[:query, "q"]])
    end

    assert_match(/Array/, error.message)
  end

  test "the descriptor is frozen and its projections are deep-frozen" do
    operation = Dexpace::Operation.build(
      method: "GET", template: "/pets", projections: { tag: [:query, "tag"] },
    )

    assert_predicate_frozen(operation)
    assert_predicate_frozen(operation.projections)
    assert_raises(::FrozenError) { operation.projections[:other] = [:query, "other"] }
  end

  test "a caller's projections hash is copied, not aliased" do
    projections = { tag: [:query, "tag"] }
    operation = Dexpace::Operation.build(method: "GET", template: "/pets", projections: projections)

    projections[:sneaky] = [:query, "sneaky"]

    assert_equal(%i[tag], operation.projections.keys,
                 "XCUT-15: the model holds no alias to externally mutable state")
  end

  # Data#with does not call an initialize override on Ruby 3.2 (verified 3.2.11 / 3.4.10 / 4.0.6),
  # so without phase 1's shared #with this passes on 3.4 and 4.0 and skips validation on the floor.
  test "with re-validates on every supported Ruby" do
    operation = Dexpace::Operation.build(method: "GET", template: "/pets")

    assert_raises(Dexpace::InvalidArgumentError) { operation.with(template: "/pets/{id}") }
  end

  test "new is private; .build is the construction path" do
    refute_respond_to(Dexpace::Operation, :new)
    assert_respond_to(Dexpace::Operation, :build)
  end

  private

  def assert_predicate_frozen(object)
    assert(object.frozen?, "#{object.class} must be frozen at construction")
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/operation_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Operation`.

- [ ] **Step 3: Write `lib/dexpace/operation.rb` — the descriptor half**

Write the whole file now; Task 14's tests exercise the `#build_request` half of it.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "model"
require_relative "http/method"
require_relative "http/url"
require_relative "http/query"
require_relative "http/headers"
require_relative "http/request"
require_relative "http/percent_encoding"
require_relative "error/invalid_argument_error"

module Dexpace
  # The operation-input projection seam: a frozen descriptor plus one builder method.
  #
  # SEAM-26 requires a per-operation declaration of an HTTP method, a path template with named
  # placeholders, and typed projections of inputs onto path / query / header / body, "so operation
  # arguments flow through typed projections rather than URL string surgery". No code generation is
  # implied; this is the runtime primitive a generator would target.
  #
  # `projections` maps an input key to [:path | :query | :header | :body, wire_name]. Only method
  # and template are required and projections default to empty, so a parameterless GET is the
  # default construction.
  #
  # SEAM-28's stable operation identifier is a MAY and is deferred (DEF-1, target phase 5): both of
  # its halves need machinery phase 2 does not have -- the request's context chain (CTX, phase 4)
  # and a consumer for the identifier (instrumentation, phase 5).
  class Operation < ::Data.define(:method, :template, :projections)
    include Dexpace::Model

    TARGETS = %i[path query header body].freeze
    private_constant :TARGETS

    # Per-pattern timeouts, never the process-global Regexp.timeout: a library must not impose a
    # regexp budget on its host.
    PLACEHOLDER = Regexp.new("\\{([^{}]*)\\}", timeout: 1.0)
    private_constant :PLACEHOLDER

    BRACE = Regexp.new("[{}]", timeout: 1.0)
    private_constant :BRACE

    private_class_method :new

    def self.build(method:, template:, projections: {})
      new(method: method, template: template, projections: projections)
    end

    # @return [Array<String>] the placeholder names in `text`, in order
    def self.placeholders_in(text) = text.to_s.scan(PLACEHOLDER).flatten

    # Validation lives here rather than in a builder, because .build is public API, #with routes
    # every derivation through it, and send(:new, ...) reaches the constructor regardless. A
    # validating constructor also coerces: `method` goes through Dexpace::Method.of so a String
    # never survives as a member.
    def initialize(method:, template:, projections:)
      resolved = Dexpace::Method.of(Dexpace::Model.required!("method", method))
      text = Dexpace::Model.required!("template", template).to_s
      table = validated_projections(Dexpace::Model.required!("projections", projections))
      validate_template!(text, table)
      super(
        method: resolved,
        template: text.dup.freeze,
        projections: Dexpace::Model.own(table),
      )
    end

    def placeholders = self.class.placeholders_in(template)

    private

    def validated_projections(projections)
      unless projections.is_a?(::Hash)
        raise Dexpace::InvalidArgumentError,
              "projections must be a Hash of input key => [target, wire name], " \
              "got #{projections.class}"
      end

      bodies = 0
      table = {}
      projections.each do |key, projection|
        target, name = projection
        unless TARGETS.include?(target)
          raise Dexpace::InvalidArgumentError,
                "projection #{key.inspect} targets #{target.inspect}; expected one of " \
                "#{TARGETS.map(&:inspect).join(", ")}"
        end
        if name.nil? || name.to_s.empty?
          raise Dexpace::InvalidArgumentError, "projection #{key.inspect} has no wire name"
        end

        bodies += 1 if target == :body
        table[key] = [target, name.to_s.dup.freeze].freeze
      end
      if bodies > 1
        raise Dexpace::InvalidArgumentError, "an operation carries at most one body projection"
      end

      table
    end

    # Two halves of SEAM-27's "every placeholder MUST have a supplied value", checked at
    # construction: a placeholder with no projection can never be filled, and a :path projection
    # naming no placeholder can never be used. Both are caller mistakes catchable before any
    # request exists, which is strictly stronger than catching them at assembly time.
    #
    # An empty template is legal -- SEAM-27's "an empty path leaves the base untouched".
    def validate_template!(text, table)
      if BRACE.match?(text.gsub(PLACEHOLDER, ""))
        raise Dexpace::InvalidArgumentError, "template has an unbalanced brace: #{text}"
      end

      declared = self.class.placeholders_in(text)
      if declared.any?(&:empty?)
        raise Dexpace::InvalidArgumentError, "template has an empty placeholder: #{text}"
      end

      projected = table.each_value.select { |(target, _)| target == :path }.map(&:last)
      missing = declared - projected
      unless missing.empty?
        raise Dexpace::InvalidArgumentError,
              "template placeholder(s) #{missing.map(&:inspect).join(", ")} have no path projection"
      end

      extra = projected - declared
      return if extra.empty?

      raise Dexpace::InvalidArgumentError,
            "path projection(s) #{extra.map(&:inspect).join(", ")} name no template placeholder"
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/operation.rbs`**

```rbs
module Dexpace
  class Operation
    attr_reader method: Dexpace::Method
    attr_reader template: String
    attr_reader projections: Hash[untyped, [Symbol, String]]

    def self.build: (
      method: Dexpace::Method | String,
      template: String,
      ?projections: Hash[untyped, [Symbol, String]],
    ) -> Dexpace::Operation
    def self.placeholders_in: (String) -> Array[String]

    def placeholders: () -> Array[String]
    def build_request: (
      base_url: String | URI::Generic,
      ?inputs: Hash[untyped, untyped],
    ) -> Dexpace::Request
  end
end
```

- [ ] **Step 5: Add `require_relative "dexpace/operation"` to `lib/dexpace.rb`**

Last of the phase's requires, after `dexpace/serde`.

- [ ] **Step 6: Run the suite to confirm the descriptor tests pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/operation_test.rb`
Expected: PASS. Task 14's suite is still missing, which is correct.

---

## Task 14: `Operation#build_request` — projections and `SEAM-27` composition

**Requirement IDs:** `SEAM-27`, and `SEAM-26`'s "the body is carried, not encoded". **Design:**
"Base-URL composition, hand-built"; Design §3 Addendum A1; deviation P2-3; verified Ruby facts 1
and 8.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/operation.rb` (add `#build_request` and its four private
  helpers)
- Test: `gems/dexpace-core/test/dexpace/operation_build_request_test.rb`

**Interfaces:**
- Consumes: `Dexpace::URL.parse!` and `.external_form`, `Dexpace::PercentEncoding.encode_component`,
  `Dexpace::Query.builder`, `Dexpace::Headers.builder`, `Dexpace::Request.builder` — all phase 1's.
- Produces: `Operation#build_request(base_url:, inputs: {}) -> Dexpace::Request`.

- [ ] **Step 1: Write the failing test**

`gems/dexpace-core/test/dexpace/operation_build_request_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"

# SEAM-27, and SEAM-26's "the body is carried, not encoded, by this seam".
#
# The composition is hand-built and is NOT RFC 3986 reference resolution. Verified on 3.2.11 and
# 4.0.6: URI::RFC3986_PARSER.join("https://host/c?sig=1", "/pets") is "https://host/pets" and
# #merge of the same is identical -- both discard the /c base segment and the sig query that
# SEAM-27's own conformance step requires to survive. Design §3.5's "base-URL composition uses
# URI.join/URI#merge" is superseded here (deviation P2-3,
# docs/knowledge/notes/url-and-query-encoding.md); reference resolution keeps its place at REDIR-13
# in phase 6, where the spelling is URI::RFC3986_PARSER.join because URI.join is cop-banned.
class DexpaceOperationBuildRequestTest < DexpaceTestCase
  def operation(template: "/pets", projections: {}, method: "GET")
    Dexpace::Operation.build(method: method, template: template, projections: projections)
  end

  def url_for(subject, base) = subject.build_request(base_url: base).url.to_s

  test "the specification's own conformance example" do
    subject = operation(projections: { limit: [:query, "limit"] })

    request = subject.build_request(base_url: "https://host/c?sig=abc", inputs: { limit: 1 })

    assert_equal("https://host/c/pets?sig=abc&limit=1", request.url.to_s)
  end

  test "a trailing slash normalises to exactly one separator" do
    assert_equal("https://host/c/pets", url_for(operation, "https://host/c/"))
    assert_equal("https://host/c/pets", url_for(operation, "https://host/c"))
    assert_equal("https://host/pets", url_for(operation, "https://host"))
    assert_equal(
      "https://host/c/pets",
      operation(template: "pets").build_request(base_url: "https://host/c///").url.to_s,
    )
  end

  test "an empty operation path leaves the base untouched" do
    subject = operation(template: "", projections: { limit: [:query, "limit"] })

    request = subject.build_request(base_url: "https://host/c", inputs: { limit: 1 })

    assert_equal("https://host/c?limit=1", request.url.to_s)
  end

  test "an existing base query is preserved with the operation query appended after it" do
    subject = operation(projections: { limit: [:query, "limit"] })

    request = subject.build_request(base_url: "https://host/c?sig=abc", inputs: { limit: 2 })

    assert_equal("https://host/c/pets?sig=abc&limit=2", request.url.to_s)
  end

  test "a dangling base separator is dropped" do
    subject = operation(projections: { limit: [:query, "limit"] })

    request = subject.build_request(base_url: "https://host/c?sig=abc&&", inputs: { limit: 2 })

    assert_equal("https://host/c/pets?sig=abc&limit=2", request.url.to_s)
  end

  test "a base with no query and an operation with none yields no query at all" do
    assert_equal("https://host/pets", operation.build_request(base_url: "https://host").url.to_s)
  end

  # The seam's whole security property, and it gets its own test rather than riding on a
  # composition assertion.
  test "a path value containing a slash is encoded, not split into segments" do
    subject = operation(template: "/pets/{id}", projections: { id: [:path, "id"] })

    request = subject.build_request(base_url: "https://host", inputs: { id: "a/b" })

    assert_equal("https://host/pets/a%2Fb", request.url.to_s)
    assert_equal(3, request.url.path.split("/").length, "one segment, not two")
  end

  test "a path value's reserved characters are all percent-encoded" do
    subject = operation(template: "/pets/{id}", projections: { id: [:path, "id"] })

    request = subject.build_request(base_url: "https://host", inputs: { id: "a b?c#d&e" })

    assert_equal("https://host/pets/a%20b%3Fc%23d%26e", request.url.to_s)
  end

  test "a missing placeholder value is loud and names the input key and the placeholder" do
    subject = operation(template: "/pets/{id}", projections: { id: [:path, "id"] })

    error = assert_raises(Dexpace::InvalidArgumentError) do
      subject.build_request(base_url: "https://host")
    end

    assert_match(/:id/, error.message)
    assert_match(/"id"/, error.message)
  end

  # A supplied nil is missing, not empty: SEAM-27 makes a placeholder with no value an error, and
  # an `inputs.key?` check alone would render "https://host/pets/" -- well-formed, wrong, silent.
  test "a nil path input is missing, not an empty segment" do
    subject = operation(template: "/pets/{id}", projections: { id: [:path, "id"] })

    error = assert_raises(Dexpace::InvalidArgumentError) do
      subject.build_request(base_url: "https://host", inputs: { id: nil })
    end

    assert_match(/:id/, error.message)
  end

  test "false is a path value, not a missing one" do
    subject = operation(template: "/pets/{id}", projections: { id: [:path, "id"] })

    request = subject.build_request(base_url: "https://host", inputs: { id: false })

    assert_equal("https://host/pets/false", request.url.to_s)
  end

  test "a base carrying a fragment is rejected with a context-bearing error" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      operation.build_request(base_url: "https://host/c#section")
    end

    assert_match(/fragment/, error.message)
    assert_match(%r{https://host/c\#section}, error.message)
  end

  test "a malformed or relative base is rejected through phase 1's URL.parse!" do
    assert_raises(Dexpace::InvalidArgumentError) { operation.build_request(base_url: "/c") }
    assert_raises(Dexpace::InvalidArgumentError) { operation.build_request(base_url: "ht tp://x") }
  end

  test "a repeated query projection emits one parameter per value" do
    subject = operation(projections: { tag: [:query, "tag"] })

    request = subject.build_request(base_url: "https://host", inputs: { tag: %w[a b] })

    assert_equal("https://host/pets?tag=a&tag=b", request.url.to_s)
  end

  test "an absent optional query input contributes nothing" do
    subject = operation(projections: { tag: [:query, "tag"] })

    assert_equal("https://host/pets", subject.build_request(base_url: "https://host").url.to_s)
  end

  test "header projections go through the outbound header builder" do
    subject = operation(projections: { trace: [:header, "X-Trace"] })

    request = subject.build_request(base_url: "https://host", inputs: { trace: "abc" })

    assert_equal(["abc"], request.headers["X-Trace"])
  end

  test "a header projection carrying a CRLF is rejected by phase 1's validation, here" do
    subject = operation(projections: { trace: [:header, "X-Trace"] })

    assert_raises(Dexpace::InvalidArgumentError) do
      subject.build_request(base_url: "https://host", inputs: { trace: "a\r\nInjected: yes" })
    end
  end

  test "the body is carried, not encoded" do
    subject = operation(method: "POST", projections: { payload: [:body, "body"] })
    payload = Object.new

    request = subject.build_request(base_url: "https://host", inputs: { payload: payload })

    assert_same(payload, request.body, "SEAM-26: encoding it is the codec's job at a later stage")
  end

  test "the assembled request meets phase 1's cross-field rules" do
    subject = operation(method: "GET", projections: { payload: [:body, "body"] })

    assert_raises(Dexpace::InvalidArgumentError) do
      subject.build_request(base_url: "https://host", inputs: { payload: "x" })
    end
  end

  test "already-encoded octets in the base survive the composition verbatim" do
    request = operation.build_request(base_url: "https://host/a%2Fb?x=%26")

    assert_equal("https://host/a%2Fb/pets?x=%26", request.url.to_s)
  end

  test "the composed URL re-parses to itself" do
    request = operation.build_request(base_url: "https://host/c")

    assert_equal(request.url.to_s, Dexpace::URL.parse!(request.url.to_s).to_s)
  end

  test "the composed URL is frozen and the base is untouched" do
    base = Dexpace::URL.parse!("https://host/c")

    request = operation.build_request(base_url: base)

    assert(request.url.frozen?)
    assert_equal("https://host/c", base.to_s)
  end

  # testing/f36a19cd makes a property-style test mandatory for a value object with a
  # parse-constructor invariant. Phase 0's #sample(count:, seed:) is the bounded helper.
  test "any path value produces a URL that re-parses with the expected segment count" do
    subject = operation(template: "/pets/{id}", projections: { id: [:path, "id"] })
    alphabet = ["a", "/", "?", "#", "&", " ", "%", "\xC3\xA5".b, "\xFF".b].freeze

    sample(count: 40, seed: 20_260_907) do |random|
      value = Array.new(random.rand(1..6)) { alphabet.sample(random: random) }.join
      url = subject.build_request(base_url: "https://host/c", inputs: { id: value }).url

      assert_equal(url.to_s, Dexpace::URL.parse!(url.to_s).to_s, "value #{value.inspect}")
      assert_equal(["", "c", "pets", nil].compact.length + 1 - 1, url.path.split("/").length - 1,
                   "value #{value.inspect} produced #{url.path.inspect}")
    end
  end
end
```

The last assertion's arithmetic is deliberately written out rather than a literal: the base
contributes `/c`, the template contributes `/pets/{id}`, and a correctly encoded value adds exactly
one segment however many slashes it contains. If it reads awkwardly at implementation time, replace
it with `assert_equal(3, url.path.split("/").length - 1)` and keep the failure message.

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/operation_build_request_test.rb`
Expected: FAIL — `undefined method 'build_request'`.

- [ ] **Step 3: Add `#build_request` and its helpers to `lib/dexpace/operation.rb`**

Insert `#build_request` after `#placeholders`, and the four helpers with the other private methods.

```ruby
    # Assembles a Dexpace::Request against a base URL.
    #
    # @param base_url [String, URI::Generic] parsed through phase 1's Dexpace::URL.parse!, which
    #   pins URI::RFC3986_PARSER and rejects a non-absolute or malformed URL with the offending
    #   input in the message (HTTP-47)
    # @param inputs [Hash] operation arguments, keyed as the projection table is
    # @raise [Dexpace::InvalidArgumentError] a base carrying a fragment, or a projected path input
    #   with no value
    def build_request(base_url:, inputs: {})
      base = Dexpace::URL.parse!(base_url)
      if base.fragment
        raise Dexpace::InvalidArgumentError,
              "a base URL must not carry a fragment: #{Dexpace::URL.external_form(base)}"
      end

      builder = Dexpace::Request.builder
      builder.method = method
      builder.url = compose(base, render_path(inputs), render_query(inputs))
      builder.headers = render_headers(inputs)
      builder.body = body_input(inputs)
      builder.build
    end
```

```ruby
    # Each value goes through phase 1's strict RFC 3986 component encoder, whose unreserved set is
    # exactly A-Za-z0-9-._~, so a value containing "/" becomes "%2F" and cannot inject a segment.
    # That is SEAM-27's whole security property, and it is one call to a function phase 1 already
    # verified byte for byte.
    def render_path(inputs)
      encoded = {}
      projections.each do |key, (target, name)|
        next unless target == :path

        value = inputs[key]
        # `nil` is missing, not empty. SEAM-27 makes a placeholder with no supplied value an
        # error, and `inputs.key?` alone would let { id: nil } render "/pets/" -- a URL that is
        # well-formed, wrong, and silent. `false` is a value and survives.
        if value.nil?
          raise Dexpace::InvalidArgumentError,
                "operation input #{key.inspect} is required for path placeholder #{name.inspect}"
        end

        encoded[name] = Dexpace::PercentEncoding.encode_component(value.to_s)
      end
      template.gsub(PLACEHOLDER) { encoded.fetch(::Regexp.last_match(1)) }
    end

    # SEAM-27's "the query MUST be RFC-3986 rendered" is phase 1's Query#encode, and a repeated
    # projection emits one parameter per value because Query is a pair list, not a Hash.
    def render_query(inputs)
      builder = Dexpace::Query.builder
      projections.each do |key, (target, name)|
        next unless target == :query
        next unless inputs.key?(key)

        Array(inputs.fetch(key)).each { |value| builder.add(name, value) }
      end
      builder.build.encode
    end

    # The outbound direction, so HTTP-17/HTTP-18 validation happens here rather than at the
    # transport -- a header value carrying a CRLF is rejected while the request is being assembled.
    def render_headers(inputs)
      builder = Dexpace::Headers.builder
      projections.each do |key, (target, name)|
        next unless target == :header
        next unless inputs.key?(key)

        builder.add(name, inputs.fetch(key).to_s)
      end
      builder.build
    end

    def body_input(inputs)
      key, = projections.find { |_, (target, _)| target == :body }
      key.nil? ? nil : inputs[key]
    end

    # SEAM-27's four composition rules, implemented directly. This is a concatenation, not RFC 3986
    # reference resolution: verified on 3.2.11 and 4.0.6 that
    # URI::RFC3986_PARSER.join("https://host/c?sig=1", "/pets") is "https://host/pets", discarding
    # both the base path segment and the base query the requirement keeps -- which would silently
    # drop a signed-URL base's prefix and its SAS query, the exact case SEAM-27's rationale names.
    #
    # Works on a dup of the frozen base and assigns #path and #query rather than re-parsing a
    # re-rendered string, which is what keeps already-encoded octets verbatim (verified: a frozen
    # URI::Generic dups to an unfrozen copy whose writers work, and the original still raises
    # FrozenError).
    def compose(base, path, query)
      composed = base.dup
      composed.path = compose_path(base.path.to_s, path)
      composed.query = compose_query(base.query.to_s, query)
      composed.freeze
    end

    def compose_path(base_path, operation_path)
      return base_path if operation_path.empty?

      "#{base_path.sub(%r{/+\z}, "")}/#{operation_path.sub(%r{\A/+}, "")}"
    end

    def compose_query(base_query, operation_query)
      base = base_query.sub(/&+\z/, "")
      return (operation_query.empty? ? nil : operation_query) if base.empty?
      return base if operation_query.empty?

      "#{base}&#{operation_query}"
    end
```

- [ ] **Step 4: Run it to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/operation_build_request_test.rb`
Expected: PASS.

- [ ] **Step 5: Re-verify the finding the whole task rests on**

```bash
mise exec ruby@3.2.11 -- ruby -ruri \
  -e 'puts URI::RFC3986_PARSER.join("https://host/c?sig=1", "/pets")'
mise exec ruby@4.0.6 -- ruby -ruri \
  -e 'puts URI::RFC3986_PARSER.join("https://host/c?sig=1", "/pets")'
```

Expected: `https://host/pets` on both. If a future Ruby changes this, the design's deviation P2-3
and `docs/knowledge/notes/url-and-query-encoding.md` are what have to change, not this code —
`SEAM-27`'s rules are the requirement either way.

- [ ] **Step 6: Confirm the cop-banned spelling never entered the tree**

Run: `grep -rn 'URI\.join\|URI\.parse\|DEFAULT_PARSER' gems/dexpace-core/lib`
Expected: no matches. Then `bundle exec rake rubocop`.

---

## Task 15: Entry-point wiring, the signature tree and YARD

**Requirement IDs:** `NFR-3`, `NFR-11` as machinery; `SEAM-1`'s explicit-require rule; `SEAM-2`'s
"core references no concrete implementation". **Design:** "Module Layout"; "`SEAM-1` and `SEAM-2` —
the standing gates".

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace.rb`, `gems/dexpace-core/sig/dexpace.rbs`
- Test: `gems/dexpace-core/test/dexpace_test.rb` (extend), and a new
  `gems/dexpace-core/test/dexpace/seam_surface_test.rb`

**Interfaces:**
- Consumes: every constant from Tasks 1–14.
- Produces: a `require "dexpace"` that loads the seam layer, and a signature tree `rbs validate` and
  `steep check` both accept.

- [ ] **Step 1: Extend the smoke suite and add the seam-surface suite**

Add to `test/dexpace_test.rb`: requiring `"dexpace"` alone makes `Dexpace::Transport`,
`Dexpace::AsyncTransport`, `Dexpace::Serde`, `Dexpace::Operation`, `Dexpace::Registry`,
`Dexpace::Cancellation`, `Dexpace::Async::Future` and `Dexpace::Closeable` resolve.

`gems/dexpace-core/test/dexpace/seam_surface_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/fake_transport"

# SEAM-1 and SEAM-2 as properties of the assembled tree rather than of any one file. The three
# mechanised gates phase 0 built cover the dependency half; this covers the part a gate cannot see.
class DexpaceSeamSurfaceTest < DexpaceTestCase
  test "every seam registry starts empty on a bare require" do
    assert_empty(Dexpace::Transport.registered_keys)
    assert_empty(Dexpace::AsyncTransport.registered_keys)
    assert_empty(Dexpace::Serde.registered_keys)
  end

  test "no seam's zero-candidate error names a concrete gem" do
    [Dexpace::Transport, Dexpace::AsyncTransport, Dexpace::Serde].each do |seam|
      error = assert_raises(Dexpace::SeamError) { seam.resolve }

      refute_match(/net_http|async_http|net\/http|async-http|\bjson\b|\boj\b|httpx|excon|typhoeus/i,
                   error.message,
                   "SEAM-2: #{seam} names a concrete implementation in its error path")
    end
  end

  test "core defines no auto-activation hook, deliberately" do
    # Design §3.6 permits presence-gated auto-activation for instrumentation only, and phase 2
    # ships no instrumentation seam, so there is nothing to activate. DEF-30 records it, so a later
    # phase reading §3.6 does not conclude it was forgotten.
    refute_respond_to(Dexpace::Transport, :install_if_present)
    refute_respond_to(Dexpace::Serde, :install_if_present)
  end

  test "core requires nothing outside its own tree" do
    requires = Dir.glob(File.expand_path("../../lib/**/*.rb", __dir__))
                  .flat_map { |path| File.readlines(path) }
                  .grep(/^\s*require\s+["']/)
                  .map { |line| line[/["']([^"']+)["']/, 1] }
                  .uniq

    assert_equal(["uri"], requires,
                 "SEAM-1: the only non-relative require in core is phase 1's, and it is on the " \
                 "allowlist. gates:require_allowlist is the blocking version of this.")
  end

  test "the seam modules expose no instance side to be included by accident" do
    [Dexpace::Transport, Dexpace::AsyncTransport, Dexpace::Serde].each do |seam|
      assert_empty(seam.instance_methods(false), "#{seam} is a singleton module, not a mixin")
    end
  end

  test "both SEAM-18 bridges live under Dexpace::Bridge, not beside an adapter namespace" do
    async = Dexpace::Transport.async_over(->(_r, _o, _c) {}, executor: InlineExecutor.new)
    sync = Dexpace::AsyncTransport.sync_over(->(_r, _o, _c) {})

    assert_instance_of(Dexpace::Bridge::AsyncOver, async)
    assert_instance_of(Dexpace::Bridge::SyncOver, sync)
    refute(Dexpace::Transport.const_defined?(:AsyncOver, false), "deviation P2-1 and P2-13")
    refute(Dexpace::AsyncTransport.const_defined?(:SyncOver, false))
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/seam_surface_test.rb`
Expected: FAIL on the first constant that `lib/dexpace.rb` does not yet require.

- [ ] **Step 3: Order the requires in `lib/dexpace.rb`**

Appended after phase 1's block, in dependency order — not alphabetical:

```
error/seam_error, error/closed_error, error/cancelled_error,
closeable,
hooks,
cancellation, cancellation/source,
async/settlement, async/completer, async/future,
registry,
bridge/async_over, bridge/sync_over,
transport, async_transport,
serde/error, serde/serialization_error, serde/deserialization_error, serde,
operation
```

`hooks` precedes both, because `cancellation/source` and `async/completer` both name `Hooks` and it
is a `private_constant` resolved by lexical lookup at call time.
`cancellation` precedes `cancellation/source` because the source file reopens the class.
The two `bridge/` files precede `transport` and `async_transport`, because each module's
`.async_over`/`.sync_over` names a `Dexpace::Bridge::` constant.
`async/settlement` precedes `async/completer` because `Completer#settle` names it at call time and
`lib/dexpace.rb` must have loaded it before any caller. `registry` precedes the three seam modules
because each names `Registry` in its module body.

- [ ] **Step 4: Check the whole gem loads in isolation**

```bash
bundle exec ruby -w -Igems/dexpace-core/lib -e \
  'require "dexpace"; p Dexpace::Transport.registered_keys, Dexpace::Cancellation.none.cancelled?'
```

Expected: `[]` and `false`, with no warning on stderr.

- [ ] **Step 5: Write `sig/dexpace.rbs`'s additions and run the typing gates**

Run: `bundle exec rake rbs:validate steep`
Expected: both green. If `steep check` reports a diagnostic in a `core`-target file, fix the
signature or the code — **never relax the target**; `core` is the one Steep target that never
relaxes.

- [ ] **Step 6: Run the documentation gate**

Run: `bundle exec rake yard`
Expected: zero undocumented public objects. Every public class and method carries a YARD block that
explains why the rule exists and never restates a type.

- [ ] **Step 7: Run the whole gem suite**

Run: `(cd gems/dexpace-core && bundle exec rake test)`
Expected: PASS, every suite from Tasks 1–14.

---

## Task 16: Gates, the surface snapshot, the checklist and `CLAUDE.md`

**Files:**
- Create: `docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations-checklist.md`
- Modify: `test/fixtures/surface/dexpace-core.txt`, `CLAUDE.md`
- Test: the full gate set, plus the housekeeping probe

**Interfaces:**
- Consumes: everything Tasks 1–15 built.
- Produces: the phase record. Nothing consumes it in code.

- [ ] **Step 1: Run every gate, in one command**

Run: `bundle exec rake`
Expected: all seventeen green, plus `cops:test` covering the sixth cop. Read
`gates:require_allowlist` closely — it must still report `uri` as core's only `require`, unchanged
from phase 1. `gates:gemspec_audit` must still find `runtime_dependencies` empty for
`dexpace-core`.

- [ ] **Step 2: Run the suite on the floor and the ceiling**

```bash
mise exec ruby@3.2.11 -- bundle exec rake test:gems
mise exec ruby@4.0.6  -- bundle exec rake
```

Expected: green on both. The 3.2 run is the one that would fail if phase 1's shared `#with` were
dropped, because `Data#with` does not call an `initialize` override there — `Settlement` and
`Operation` both depend on it. The 4.0 run is where the scheduler probe's missing `#fiber_interrupt`
would have turned into a test failure.

- [ ] **Step 3: Regenerate the runtime surface manifest, deliberately**

```bash
bundle exec rake surface:regenerate
git diff test/fixtures/surface/dexpace-core.txt
bundle exec rake gates:surface_snapshot gates:rbs_surface gates:sig_diff
```

Expected: the manifest grows by this phase's public surface; the three gates then pass, with
`gates:sig_diff` still printing `no release tag yet — the first v* tag becomes the baseline`.
**Read the diff before accepting it.** Four things to check specifically: no `REGISTRY` constant
appears (all three are `private_constant`) and no `Dexpace::Hooks` (same reason);
`Dexpace::Cancellation::Subscription` **does** appear, because it is public API — it is what
`#on_cancel` returns; `Registry::State`, `Registry::Claim`,
`Cancellation::Source::State` and `Operation::PLACEHOLDER` appear only if the generator walks
private constants, which is a fact about phase 0's generator and not a defect either way — record
which it did in the checklist; and no constant appears that no task above created, which would be
a leak. Regeneration is a reviewed act, never a way to silence a failure (`api-design/46c8b5fc`).

- [ ] **Step 4: Confirm `gates:rbs_surface` is genuinely load-bearing now**

Run: `bundle exec rake gates:rbs_surface`
Expected: PASS. This is the first phase where it could have failed: `NFR-11`'s whole point is that
no third-party async type appears in a public signature, and this is the phase that defines the
async surface one would have appeared in. Confirm by adding `Async::Task` to a `sig/` file
temporarily, watching the gate go red, and removing it.

- [ ] **Step 5: Write the checklist**

Create `docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations-checklist.md` from what was actually
built, not from this plan. **Thirty rows**, `SEAM-1` through `SEAM-30`, each naming the numbered
task above that satisfies it. Legend, verbatim from the roadmap: ✅ implemented and tested · 🚫 not
built (permanent simplification, named reason) · ⏳ deferred (`DEF-<n>` with its pick-up condition)
· N/A not applicable in this port. The rows that are not ✅:

| ID | Mark | Row must say |
|---|---|---|
| `SEAM-3`, `SEAM-4` | 🚫 | The byte-stream provider seam is retired (§10.1); the behavioural contract `IO-1`–`IO-42` is phase 3's and is not retired with it |
| `SEAM-10` | N/A | Vacuous in Ruby (§10.9) — one process-global constant namespace, no classloader; replaced by the version-skew guard Task 8 proves |
| `SEAM-22` | 🚫 | The reflective generic type capture is replaced by the witness protocol (§10.14, phase 7); the surviving clause — `#load` takes an explicit witness, no witness-less overload — is Task 12 |
| `SEAM-12` | ⏳ | `DEF-22`. The seam's shape carries no per-request state — `#call` takes everything it needs and returns everything it produces — but concurrency safety is a property of an *implementation* and this phase ships none. `dexpace-conformance` asserts it per adapter; Task 9's concurrent-call test exercises the harness, not a transport |
| `SEAM-24` | ⏳ | `DEF-1`, riding on `DEF-11` (`dexpace-async-async`, post-v1). Task 4 and Task 5 fix the cancellation contract its bidirectional mapping will map |
| `SEAM-15` | ✅ with a named gap | The MAY is taken and documented: `Dexpace::ClosedError` (Task 1), and the rule that **an owning transport raises it from a later send** while a borrowing wrapper closes nothing and stays usable (Task 9's module comment; `XCUT-22`). What ships is the class and the rule and **no raise site** — `Dexpace::ClosedError` has no reference anywhere in `lib/` outside its own file, and the only tests assert its ancestry — because phase 2 ships no transport that owns a resource. Phase 8's adapters are the first owners and are where the raise lands; `dexpace-conformance` is where it is asserted per adapter (`DEF-22`). The row names the gap rather than letting a bare ✅ imply a raise nothing performs |
| `SEAM-25` | ✅ with a named gap | The idempotent, ownership-aware release is `Dexpace::Closeable` (Task 2) and both bridges take it (Tasks 9, 10). The clause "only the first close shuts the owned executor **and emits the lifecycle event**" has no event to emit until §8.1's instrumentation facade exists: `DEF-31`, phase 5. The row names it rather than claiming it |
| `SEAM-28` | ⏳ | `DEF-1`, target **phase 5**, given by this phase's register sweep |
| `SEAM-29` | ✅ in phase 1 | A cross-reference row: phase 1's `Dexpace::Model.required!` and `Dexpace::Builder`. Not re-satisfied here |

Add the audit-group section the roadmap requires: the six groups this phase ran (*Public API
surface*; *Gem layout, zero-dependency core*; *RBS / Steep typing*; *Fiber scheduler, thread
safety*; *Styleguide-vs-design conflicts*; *Minitest conventions*), the result of each, and the four
notes filed. Record `OI-1` under whatever the checklist's findings heading is — never as an
aggregate register section, which the probe's `registers` check reports.

- [ ] **Step 6: Verify the register rows, and add any the implementation found**

```bash
grep -n '^### DEF-2[7-9]\|^### DEF-3[0-2]\|^### OI-1' docs/deferred-items.md docs/open-items.md
grep -n 'picked-up' docs/deferred-items.md
```

Expected: `DEF-27` through `DEF-32` and `OI-1`, appended during planning, and `DEF-21` reading
`picked-up (2026-09-07, phase 2)`. Anything the implementation defers beyond those is appended as
`DEF-33` onward with the deferring phase, the reason, the pick-up condition and the IDs it cites,
and the `next id:` line at the foot of each register is updated.

- [ ] **Step 7: Append the roadmap status note**

Append one dated entry to `## Phase Status Notes` in
`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`, recording what was **built** — the
planning entry is already there. Never rewrite an earlier one.

- [ ] **Step 8: Update `CLAUDE.md`**

Four edits, and no others:

1. The **"Nothing is implemented yet"** paragraph — `dexpace-core` now carries the HTTP domain model
   and the seam layer.
2. The **"Constraints that will bite"** section — add the two rules this phase fixed for every later
   phase: inside `Dexpace::Async` and `Dexpace::Serde` write `::Thread`/`::Queue`/`::Mutex`/`::JSON`
   because a bare name rebinds when the adapter gem loads (a sixth cop enforces it); and `SEAM-27`'s
   base-URL composition is a concatenation, while RFC 3986 reference resolution is
   `URI::RFC3986_PARSER.join` and is `REDIR-13`'s. One line each, pointing at the phase-2 design.
3. The **command block** — add `bundle exec rake cops:test` if phase 0 did not already list it.
4. The **counts the `claims` check reads** — the gem count and the harvested-topic count are
   unchanged; the phase-directory sentence already says three and must now describe a `phase2/`
   holding a design, a plan **and a checklist**.

- [ ] **Step 9: Run the probe and fix what it reports**

Run: `ruby .claude/skills/housekeeping/probe.rb`
Expected: exit 0, `no drift found.` A `claims` finding means a numeral in a sentence is wrong — fix
the sentence, never the check.

- [ ] **Step 10: Run the four repository gate commands**

```bash
ruby .claude/skills/housekeeping/probe.rb
ruby -w .claude/skills/housekeeping/test/run.rb
ruby -w scripts/test/knowledge_test.rb
ruby scripts/verify_knowledge_structure.rb
```

Expected: all four exit 0.

- [ ] **Step 11: Hand over**

Do not commit. Report to the manager: the twenty new `lib/` files with their `sig/` and `test/`
mirrors (`lib/dexpace/hooks.rb` has neither, and is a `private_constant`), the sixth cop and its cases, the seventeen gates green on 3.2 and 4.0, the surface-manifest
diff, the `DEF-` rows and `OI-1`, the checklist's thirty rows with every 🚫, ⏳ and N/A named, and
the `CLAUDE.md` diff.

---

## Self-Review

**Spec coverage.** Every `## <Component>` section of the design maps to at least one task:

| Design section | Task |
|---|---|
| What a seam is in this port, stated once (the three artifacts; the two failure classes) | 1, 9, 10, 12 |
| `Dexpace::Registry` — discovery, install and conflict resolution | 7 |
| The version-skew guard (`DEF-21`) | 7 (code), 8 (proof) |
| `Dexpace::Transport` — the synchronous transport seam | 9 |
| `Dexpace::AsyncTransport` — the asynchronous transport seam | 10 |
| The async pivot: `Future` and `Completer` | 5, and 6 for its two structural proofs |
| `Dexpace::Cancellation` and `Cancellation::Source` | 4 |
| `Dexpace::Closeable`, `Dexpace.close_quietly` and `Dexpace::ClosedError` | 1, 2 |
| `Dexpace::Serde` — the wire-codec seam and its failure hierarchy | 12 |
| `Dexpace::Operation` — the operation-input projection seam | 13 |
| Base-URL composition, hand-built | 14 |
| `SEAM-18` — the two bridges | 9 and 10 create `Dexpace::Bridge::AsyncOver` and `::SyncOver`, 11 proves both |
| The byte-stream provider seam, and why nothing is here | 16 (the two 🚫 checklist rows) |
| `SEAM-1` and `SEAM-2` — the standing gates | 15, 16 |
| The in-memory fake transport, and where it lives | 9, 10, 12 |
| Testing (the concurrency table, the scheduler test, the shadowing test, the `SEAM-8` warning test, the version grid, the `SEAM-27` cases, the property tests) | 2, 4, 5, 6, 7, 8, 9, 11, 14 |
| Design §3 Addendum A1 (`SEAM-27` composition) and A2 (three registries, no executor registry) | 14; 9, 10, 15 |
| Design §9 Addendum A1 (the sixth cop) | 3 |
| Deviation Ledger, deferrals, register sweep | filed during planning; audited in 16 |

**Requirement coverage.** All 30 in-scope IDs: `SEAM-1`/`SEAM-2` (15, 16), `SEAM-3`/`SEAM-4` (🚫,
16), `SEAM-5`–`SEAM-9` (7), `SEAM-10` (N/A + 8), `SEAM-11`–`SEAM-13` (9), `SEAM-14`/`SEAM-25` (2),
`SEAM-15` (1, 9 — ✅ with a named gap: the class and the rule ship, the raise site is phase 8's),
`SEAM-16`/`SEAM-17` (5, 6, 10), `SEAM-18` (9, 10, 11), `SEAM-19`–`SEAM-21` (12),
`SEAM-22` (🚫 mechanism; surviving clause 12), `SEAM-23` (12), `SEAM-24` (⏳ `DEF-1`),
`SEAM-26` (13), `SEAM-27` (14), `SEAM-28` (⏳ `DEF-1`, phase 5), `SEAM-29` (phase 1), `SEAM-30`
(5, 11).

**Placeholder scan.** No "TBD", no "implement later", no "add appropriate error handling", no
"similar to Task N". Four places describe a file's shape in prose rather than in full code, and each
names the exact members and behaviour: Task 1's two smaller error suites, Task 10's `sig/` mirror
(identical in shape to Task 9's, which is given in full), Task 12's two one-line error subclasses,
and Task 15's `sig/dexpace.rbs` additions. Repeating forty lines of near-identical RBS would bury
the two lines that differ.

**Type consistency.**

- `Dexpace::Registry.new(seam:, installer:, conforms:)` is defined in Task 7 and called with
  exactly those three keywords in Tasks 9, 10 and 12.
- `Dexpace::Registry.callable?(object, arity:)` is defined in Task 7 and called as
  `callable?(object, arity: 3)` by `Transport.conforms?` (9) and `AsyncTransport.conforms?` (10).
- `#register(key, factory, core:)` carries the `core:` keyword in Task 7's signature, Task 8's
  proof, and every call in Tasks 7, 9, 10 and 12's tests.
- `Dexpace::Async::Completer#fulfil`/`#fail`/`#request_cancel` all return a Boolean, and Task 11's
  bridge tests depend on `#fulfil` returning `false` on a lost race.
- `Dexpace::Async::Future.new(completer)` takes a `Completer` and is called only from
  `Completer#future` (Task 5) and from Task 5's negative test.
- `Dexpace::Cancellation.over(*sources)` is defined in Task 4, validates every argument
  `is_a?(Source)`, and is called by `Source#initialize` and by `#merged_with` in the same task;
  `#sources` is **protected**, and `.any` reaches it only through `#merged_with`, which is an
  instance method and therefore may.
  `Cancellation::Source#cancelled_at` is public because the token's `#winner` orders by it.
- `Dexpace::Cancellation#on_cancel` returns a `Cancellation::Subscription`, not `self`, and it is
  the only subscribing method. `Subscription#detach` calls `Cancellation::Source#off_cancel`, which
  exists for it alone. `Completer#await` is the only caller in `lib/` that detaches, and it does so
  in an `ensure`.
- `Dexpace::Hooks.notify(hooks, argument)` is defined in Task 4 and called from exactly three
  places: `Cancellation::Source#cancel` (Task 4), `Completer#settle` and `Completer#request_cancel`
  (Task 5). It is a `private_constant`, reached by the unqualified name from inside
  `module Dexpace`, so it has no `sig/` mirror and no YARD gate entry.
- `Dexpace::Registry#complete_resolution` releases the `resolving` claim in an `ensure`, so every
  exit path — including a `LoadError` or any other non-`StandardError` from a factory, and including
  the re-entrancy `SeamError` — leaves the registry re-evaluable. The `resolving` slot holds a
  `Registry::Claim` (the gate plus the claiming `Fiber`), not a bare `Thread::Queue`. `#swap`
  restores the pre-block snapshot with the **live** `resolving` and `factories` values spliced in,
  never the captured ones.
- `Dexpace.close_quietly(resource)` is defined in Task 2 and called in Task 5 (`Completer#fulfil`)
  and Task 9 (`Bridge::AsyncOver#deliver`).
- `Dexpace::Closeable#initialize_closeable(owned: false)` is called by both bridges (Tasks 9, 10),
  so both answer `#close`, `#closed?` and `#owned?` — which is what `SEAM-14` requires of "both
  transport seams" and what neither bridge did before this revision.
- `Dexpace::Closeable#initialize_closeable(owned:)` is defined in Task 2 and called by every fake
  response in Tasks 5, 9 and 11.
- `Operation#build_request(base_url:, inputs:)` is declared in Task 13's RBS and implemented in
  Task 14 with those exact keywords.
- Phase 1's surface is consumed by name and not extended: `Dexpace::Model.required!`,
  `Model.own`, `Method.of`, `URL.parse!`, `URL.external_form`,
  `PercentEncoding.encode_component`, `Query.builder`/`#add`/`#build`/`#encode`,
  `Headers.builder`/`#add`/`#build`, `Headers::EMPTY`, `Request.builder` with `#method=`,
  `#url=`, `#headers=`, `#body=`, `#build`, and `RequestOptions::EMPTY`.
- `WarningCapture.record { }` is defined in Task 7 and used only there.
- `FakeTransport`, `OptionsIgnoringTransport` and `InlineExecutor` are defined in Task 9 and used in
  Tasks 9 and 11; `FakeAsyncTransport` in Task 10, used in Tasks 10 and 11; `FakeCodec` and
  `IncompleteCodec` in Task 12; `ProbeScheduler` in Task 6.

**Three places this plan diverges from the committed design, stated here because a reader of the
design will not otherwise find them.**

- **`WarningCapture` replaces the design's "adds the first entry to phase 0's zero-entry warning
  allowlist".** The design's mechanism is a message pattern that stays allowlisted for the life of
  the suite, so every later warning matching it is also swallowed, and it needs phase 0's allowlist
  API to be shaped the way the design guessed. `WarningCapture` is block-scoped, records rather than
  permits, delegates to phase 0's raising override outside the block, and needs no knowledge of that
  API — verified on 3.2.11, 3.4.10 and 4.0.6 that prepending it after phase 0's module puts it ahead
  in the ancestor chain. Recorded as deviation **P2-12**.
- **`Dexpace::Bridge::AsyncOver` and `::SyncOver` are two files under a namespace the design's
  Module Layout did not list.** The design named neither constant; putting them under
  `Dexpace::Transport` and `Dexpace::AsyncTransport` would have seated `Transport::AsyncOver`
  beside the adapter namespaces `Transport::NetHTTP` and `::AsyncHTTP`, which is precisely what
  deviation P2-1 argues a core constant must not do. Recorded as deviation **P2-13**, with both
  files added to the design's Module Layout.
- **`Cancellation#on_cancel` returns an unsubscribe handle, and there is a `Dexpace::Hooks` the
  design's Module Layout did not list.** The design says `#on_cancel { |reason| }` and says nothing
  about withdrawing a registration, which left `Completer#await` with no way to detach what it
  armed; and it describes the notification loop three times without naming the one place it lives.
  Recorded as deviations **P2-14** and **P2-15**, with `lib/dexpace/hooks.rb` added to the design's
  Module Layout.

**Rough edges, stated rather than hidden.**

- `Cancellation#on_cancel` returns a handle where the design implies `self`. The alternative was a
  registration nothing can withdraw, which is what `Completer#await` needs to withdraw: measured 200
  retained closures — and through them 200 responses — on a client-lifetime source over 200 requests
  before the detach existed. Recorded as deviation **P2-14**. What it costs is one more public
  constant and one more public method on `Source`; both are in P2-14's row, so `NFR-4` locks them
  deliberately rather than by accident.
- `Transport.conforms?` and `AsyncTransport.conforms?` are the same predicate, because the two seams
  are structurally identical and differ only in return type. Two registries and
  `dexpace-conformance` are the mitigation; a predicate claiming to distinguish them would be a
  false proof.
- `Registry#resolve` reads `@state` without a lock. That is deliberate and is `SEAM-9`'s
  "reads observe the latest install without blocking": the state is one frozen `Data` in one
  instance variable, so a reader sees a fully-constructed snapshot or the previous one. On CRuby the
  GVL makes the reference read atomic; the property the design leans on is that no partially
  constructed state is ever published, which holds regardless of implementation.
- `Registry#resolve`'s single-flight claim means a waiter can be woken by a resolution that
  **failed**, and then claims and retries the scan itself. That is `SEAM-7`'s "an UNRESOLVED state
  MUST remain re-evaluable" and is what a caller wants — each caller gets its own error — but it
  does mean N concurrent callers of a registry with two candidates raise N times rather than once.
  Nothing is built, so nothing leaks.
- If an explicit `#install` lands while a resolution is in flight, the install wins and the freshly
  built provider is discarded — and closed through `Dexpace.close_quietly`, which is a no-op on a
  provider with no `#close`. It *is* `SEAM-30`'s shape: a value produced that no caller will
  receive. `SEAM-14` makes a transport closeable and a transport provider is the archetypal owner
  of a connection pool, so dropping it unclosed would leak exactly what `SEAM-30` exists to
  prevent, and this phase already closes the same shape in `Completer#fulfil`.
- **`Cancellation#reason` is eventually consistent with what `#on_cancel` was handed, and cannot be
  made otherwise.** A `Source` takes its monotonic stamp before it takes its own mutex, so a source
  with the earlier stamp can publish after a handler has already fired on a later-stamped one, and
  `#reason` then flips to the earlier one. Demonstrated deterministically on 3.2.11, 3.4.10 and
  4.0.6 by holding one source's mutex across the other's `#cancel`; seen in a free-running race 2
  times in 120,000 on 3.2.11 and not at all in 400,000 on 3.4.10 or 4.0.6. **No stamp placement
  closes it** — the two sources hold two different mutexes and nothing orders them — so it is stated
  rather than claimed away, at `Cancellation#initialize` and here. What holds unconditionally: the
  token is cancelled, every reason it reports belongs to a source that really was cancelled, and the
  value converges once every racing source has published. Ties are *not* the problem and are not
  treated as one: 0 same-nanosecond collisions in 100,000 stamps, 50 ns median gap between
  successive `CLOCK_MONOTONIC` reads, 1 ns resolution, on all three interpreters.
- `Hooks.notify` re-raises the **first** handler failure and drops the rest. Dropping is wrong and
  temporary: `DEF-32` names phase 4's `Dexpace::Error#suppressed` (`DEF-24`) as where they go.
  Re-raising rather than dropping everything is the choice made here because phase 2 has no
  diagnostic channel at all, and a handler that raises into a void is a bug nothing reports.
- `SEAM-8`'s "auto-resolved but never handed out" branch is implemented and, in production,
  unreachable: `#resolve` hands out the provider in the same call that resolves it. It is reachable
  only through the unchecked swap seam `SEAM-6` sanctions, which is how the test reaches it. The
  branch is kept rather than collapsed because collapsing it would warn on a state `SEAM-8`
  explicitly says warrants no warning, the day a non-delivering resolution path is added.
- The `SEAM-8` warning goes to `Kernel#warn` and is therefore silent when `$VERBOSE` is `nil`
  (verified). `SEAM-8` is a SHOULD asking for a warning rather than a failure, so a channel the host
  can silence is the right one — but a consumer running `-W0` will not see it, and that is stated at
  the method rather than discovered.
- `Operation#build_request` renders headers through the outbound builder, so a header projection
  carrying a CRLF fails at assembly rather than at dispatch. That is stricter than `SEAM-26`
  requires and is the right side to err on; phase 8's transports re-validate anyway (`DEF-25`).
