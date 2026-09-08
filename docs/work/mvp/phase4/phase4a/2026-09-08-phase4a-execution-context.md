# Phase 4a — Execution Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `dexpace-core`'s correlation model — three immutable context flavours forming a
one-way promotion chain, one call-unique key, one bounded process-wide store, and the nine-slot
instrumentation bundle roadmap obligation 1 fixes in core — satisfying all 20 `CTX-1`–`CTX-20`.

**Architecture:** One module (`Dexpace::Context`) three flat `Data` classes include for their
shared `#close`; one class (`Dexpace::ContextStore`) that *has* a `private_constant` bounded map
rather than *being* one, so `XCUT-14`'s and (later) `AUTH-19`'s implementations can share it; one
`private_constant` counter (`Dexpace::CallKey`) that mints `CTX-4`'s key; and one namespaced
instrumentation subsystem (`Dexpace::Instrumentation`) — a closed-set trace-id flavour, two
frozen no-op singletons, and the bundle that carries them. No pipeline, no recovery chain, no
transport, no socket: the whole test surface is value objects, one synchronised hash, and Ruby's
three execution carriers (thread, fiber, enumerator-fiber).

**Tech Stack:** Ruby 3.2–4.0 (development on 4.0.6), no runtime dependencies, Minitest, RBS +
Steep, RuboCop with phase 0's five custom cops and phase 2's sixth, plus a new seventh this phase
adds, SimpleCov, YARD.

**Spec:** `docs/work/mvp/phase4/phase4a/2026-09-08-phase4a-execution-context-design.md`, under the
charter `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md`. `docs/product-spec/07-execution-context-model.md`
is the normative chapter; `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md`
carries the canonical `CTX` text quoted below.

## Global Constraints

- **`dexpace-core` gains no dependency and no allowlist entry.** The gemspec keeps zero
  `add_dependency` lines (`SEAM-1`, `NFR-1`). This phase adds **no `require` of any kind beyond
  `require_relative`** — `::Thread::Mutex`, `::Hash`, `::Data`, `::Regexp`, `::Fiber` are core Ruby.
  `securerandom` is on phase 0's allowlist and this phase does **not** use it: `CTX-4`'s key is a
  rendered prefix plus a counter, never a UUID (design §5.4).
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`). No `# typed:` sigil
  anywhere (`notes/testing.md`'s conflict resolution — no Sorbet in this repository).
- **`downcase` is called with no arguments, everywhere** (`Dexpace/NoLocaleCaseFold`). This
  phase's two hex patterns (`W3C`'s 32-char trace id, the span-id pattern) are written
  lowercase-only and reject an uppercase input rather than folding it (`OBS-26`).
- **`Regexp.new(source, timeout: 1.0)` per pattern, never the process-global `Regexp.timeout`.**
  Four patterns in this phase: `TraceIdFlavour::NONE/W3C/DATADOG`'s three, plus `Bundle`'s
  span-id pattern.
- **Inside `module Dexpace`, anywhere, write `::Thread`, `::Queue`, `::Mutex`, `::SizedQueue`,
  `::ConditionVariable`, `::JSON` and `::IO`** — never the bare name (`Dexpace/QualifiedCoreConstant`,
  phase 2's sixth cop). This phase adds nothing to its `SHADOWED` list: no constant this phase
  defines shares a name with a Ruby core constant.
- **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden repository-wide**
  (`Dexpace/NoThreadInterrupt`). This phase starts no thread and interrupts none — the constraint
  has nothing to bite on here.
- **A `Thread::Mutex` is held across a flag flip and across nothing else.** Two mutexes exist in
  this phase — one inside `BoundedMap`, one inside `CallKey` — and neither is ever held across a
  drain of anything but its own hash, a close, or any suspension point. `BoundedMap` never yields
  to caller code.
- **A context is not a `Dexpace::Closeable`.** `#close` has no latch, no `#closed?`, no block form
  (verified fact 1 below; deviation P4-4, already filed by the design).
- **Every count and offset beyond the first positional subject is a keyword**, with one stated
  exception this phase itself creates: `NO_TRACER_FACTORY#tracer`'s two legacy positional
  parameters, kept positional for call-compatibility with `opentelemetry-api` (P4-8, resolved
  concretely below).
- **`private_class_method :new` plus a validating `.build`, on every `Data` this phase ships that
  is public API** — all five of them (three contexts, `Bundle`, `TraceIdFlavour`). Validation lives
  in `initialize` and is called again through `super` from `.build` via `new`. `Dexpace::BoundedMap`
  and `Dexpace::CallKey` are the two `private_constant` exceptions (P2-9, P4-3) and ship no `sig/`
  mirror, no YARD gate entry, no surface-manifest row.
- **Formatting:** double quotes, 2-space indent, 100 columns, `consistent_comma` trailing commas,
  leading-dot chains, `MethodLength: 25`, `ParameterLists: 4`, `BlockNesting: 3`. Every `lib/` and
  `test/` fence below was run through **RuboCop 1.90.0** against phase 0's `.rubocop.yml` as that
  plan writes it and reports **no offense** outside the set `OI-6` already records as firing
  repository-wide before this phase existed (`Layout/EmptyLineAfterMagicComment`,
  `Style/DataInheritance`, `Layout/EmptyLinesAfterModuleInclusion`, `Metrics/AbcSize`,
  `Metrics/ClassLength`, `Metrics/CyclomaticComplexity`, `Metrics/PerceivedComplexity`,
  `Naming/RescuedExceptionsVariableName`, `Naming/PredicateMethod`,
  `Minitest/MultipleAssertions`, `Minitest/EmptyLineBeforeAssertionMethods`).
- **`Metrics/ParameterLists: 4` and the keywords-everywhere rule are in direct tension, and this
  phase pays it with named inline disables rather than by pretending otherwise.** RuboCop counts
  keyword arguments by default (`CountKeywordArgs: true`), and `api-design/1d9e6e0b` makes every
  public parameter a keyword — so `Bundle.build`/`#initialize` (8), `ExchangeContext`'s pair (6)
  and `RequestContext`'s pair (5) all exceed the cap while carrying exactly the member set the
  design fixes. Each site carries `# rubocop:disable Metrics/ParameterLists` with the reason,
  which is phase 0's own convention for an inline directive; `NO_TRACER_FACTORY#tracer` (5) is
  disabled with `Lint/UnusedMethodArgument` for `P4-8`'s separate reason. Whether the repository
  should instead set `CountKeywordArgs: false` once is `OI-20`, filed by this plan and **not**
  decided here — a `.rubocop.yml` diff belongs to whoever closes `OI-6`.
- **Tests:** Minitest only, `FooTest < DexpaceTestCase`, `test "..." do` blocks, `test/` mirroring
  `lib/` one file per file, every test passing alone and in any order, the seed never overridden.
  Each test file's header comment names the requirement IDs it exercises. Every public constant
  gets three artifacts in the same task: the implementation, a YARD block, and an `.rbs` mirror.
  **No task writes only `sig/`.**
- **No commit step appears in any task.** The manager commits once per phase.
- **Never edit** `docs/product-spec/`, `docs/sdk-design-ruby/`, `docs/knowledge/harvested/`.

### Commands

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/<path>_test.rb   # one suite, red or green
(cd gems/dexpace-core && bundle exec rake test)                     # the gem's whole suite
bundle exec rake                                                    # all seventeen gates
bundle exec rake cops:test                                          # the custom cops' own suite
mise exec ruby@3.2.11 -- bundle exec rake test:gems                 # the floor, locally
bundle exec rake surface:regenerate                                 # deliberate; Task 9 only
```

### What was verified during planning, and how

Every `ruby` fence in this document was extracted to a scratch tree **outside this repository**
(`/tmp/phase4a-plan/`, never inside `gems/`, which does not exist yet and must not start existing
here) and run — not a prototype it was transcribed from. The tree was built on stand-ins for phase
0's `DexpaceTestCase` (with `#sample(count:, seed:)` and its `Warning.warn` override), phase 1's
`Dexpace::Model`, `Dexpace::Error` and `Dexpace::InvalidArgumentError`. The result, run under
`ruby -w` with `RUBYOPT=-W:deprecated`, identical across five seeds (1, 2, 3, 42, 12345) on
**3.2.11 and 3.4.10**:

```
67 runs, 327 assertions, 0 failures, 0 errors, 0 skips
```

and on **4.0.6**:

```
67 runs, 345 assertions, 0 failures, 0 errors, 0 skips
```

**The 18-assertion difference licenses nothing about the code under test — every run is 0 failures,
0 errors on all three.** It is a Minitest counting artifact: `Minitest::VERSION` is `5.25.1` on
3.2.11, `5.25.4` on 3.4.10, and `6.0.0` on 4.0.6 (Ruby 4.0.6's own bundled default gem) — checked
directly with `ruby -e 'require "minitest"; puts Minitest::VERSION'` on all three. Minitest 6.0.0
counts some assertions (inside `assert_raises`, `refute_respond_to` and similar composite
assertions) more granularly than 5.25.x; phase 3a recorded the same shape of gap (826 vs 830). No
task below states an assertion count as a pass/fail criterion for this reason — only run counts
and `0 failures, 0 errors`.

The seventh cop's own suite — 17 runs, 50 assertions, 0 failures — was run against **RuboCop
1.90.0** (phase 0's and phase 2's own pinned version) on 3.4.10 only, because that is the only
interpreter in this planning environment with the gem installed. **This licenses the cop's
behaviour, not its portability to another RuboCop version** — the reason it is safe regardless of
which interpreter runs the *host* Ruby process is design §5.4's and R1's own point: `TARGET_RUBY =
3.2` inside `CopCase` pins the **parse target**, and `RuboCop::ProcessedSource` does not depend on
the interpreter executing RuboCop itself, only on the RuboCop/parser gem version — exactly phase
2's Task 4 precedent ("run here on 3.4.10 because that is the only matrix row with the gem
installed, which is exactly the point").

Two independent facts were re-verified directly, matching the design's own record exactly, via
`mise exec ruby@<v> -- ruby -e '...'` on all three interpreters:

```
== ruby 3.2.11: frozen Data ivar write ==
FrozenError: can't modify frozen D: #<data D a=1>
== ruby 3.2.11: ObjectSpace::WeakKeyMap defined? ==
undefined
== ruby 3.4.10: frozen Data ivar write ==
FrozenError: can't modify frozen D: #<data D a=1>
== ruby 3.4.10: ObjectSpace::WeakKeyMap defined? ==
ObjectSpace::WeakKeyMap
== ruby 4.0.6: frozen Data ivar write ==
FrozenError: can't modify frozen D: #<data D a=1>
== ruby 4.0.6: ObjectSpace::WeakKeyMap defined? ==
ObjectSpace::WeakKeyMap
```

**This licenses P4-4** (a context cannot carry a `Closeable` latch, on any supported Ruby) **and
half of R1** (the constant genuinely does not exist at the floor, so the cop — not a runtime
check — is the only mechanism that can reach it on 3.2.11). It does not by itself license that
`RuboCop::ProcessedSource` parses the same source cleanly at `TargetRubyVersion 3.2` — that is a
parser fact, checked separately by the cop suite itself, which is why both checks are run rather
than one standing in for the other.

## This plan's open questions, resolved

The design (line 1292) left four for the plan to close, each with a recommendation. All four are
resolved below rather than deferred a second time, and two more the plan itself opened are
resolved beside them — the second of those, question 5, is the one place a design claim did not
survive contact with a shipped test, and it is filed as `OI-20` rather than restated.

**1. `#tracer`'s exact arity in `opentelemetry-api`.** The design's own recommendation —
`#tracer(name = nil, version = nil)` — **does not match the gem's current source and is not what
this plan ships.** Fetched and inspected directly: `gem fetch opentelemetry-api -v 1.11.0` (the
latest release as of 2026-09-08), unpacked, and read
`lib/opentelemetry/trace/tracer_provider.rb` — the no-op base class every real provider extends:

```ruby
# opentelemetry-api 1.11.0, lib/opentelemetry/trace/tracer_provider.rb
def tracer(deprecated_name = nil, deprecated_version = nil, name: nil, version: nil, attributes: nil)
  @tracer ||= Tracer.new
end
```

The gem moved to a mixed legacy-positional-plus-keyword shape, with keyword arguments taking
precedence over the positional ones on the same slot, to stay compatible with callers written
against the older two-positional-argument form while adding `attributes:`. **Per the design's own
rule — "if the real signature differs, the gem's wins" — `Dexpace::Instrumentation::NoTracerFactory#tracer`
mirrors this exactly**: two optional positional parameters plus three optional keyword parameters
(`name:`, `version:`, `attributes:`), all five ignored, always returning the shared `NO_TRACER`.
Task 6 ships this signature; P4-8, already filed by the design, is honoured by the resulting shape
without needing amendment — the design already anticipated the exact arity would come from the
gem, not from itself.

**2. Whether `Dexpace::BoundedMap` needs an RBS signature even though it ships none.** No —
confirmed on this plan's own scratch tree with `rbs -I sig validate` run against a full sig tree
that includes every public type this phase and phase 1/2 stand-ins define: it exits clean with
`BoundedMap` and `CallKey` absent from `sig/` entirely, because nothing in `sig/` ever names them
— `ContextStore`'s own `.rbs` types `#set`/`#put`/`#release` over `Context`, never over
`BoundedMap`. Task 3 (the first task touching `ContextStore`) states this as the moment the
question is closed. Per the design's own fallback, if a future `steep check` run (once the real
Steepfile exists) reports a diagnostic in a `core`-target file naming `BoundedMap`, the fix is to
the signature or the code — the target is never relaxed.

**3. Whether the `CTX-19` reachability test (1000 objects, three `GC.start`s) runs on every matrix
row.** Yes, on every row, per the design's own recommendation — measured cost: a few hundredths of a
second inside a whole-suite wall time of well under a tenth on every interpreter tested above,
i.e. noise. It is the only runtime test that would catch a weak map; the cop (Task 8) cannot see a
third-party store's implementation, so this is the one property test that has to run everywhere.

**4. Where `FakeContext` is required from.** An explicit `require_relative` in each suite that uses
it, never from `test_helper.rb` — phase 2's precedent, followed exactly. Two files need it:
`context_store_test.rb` (Task 3) and `context_test.rb` (Task 2), each with its own
`require_relative "../support/fake_context"`. Task 7 extends `context_store_test.rb` with the
`CTX-9` trap and needs no new require — same file. No other suite in this phase touches the fake.

**5. What the drain's discriminating measurement can actually be, as a shipped test.** Not one of
the design's four, and it has to be stated because the design names a measurement this plan then
could not make. The design's testing strategy and
`docs/knowledge/notes/execution-context.md` both say the two discriminating measurements are "the
maximum iterations in any one call" and "the maximum size ever observed", against the vacuous
`8000 − 64 = 7936` aggregate. **The first is shippable and Task 3 ships it**, as its observable
form: from a store already at `cap`, every further insert evicts **exactly one** occupant and the
size is never observed above `cap` — which is the drain body running at most once, and which
fails against a drain that evicts two per insert and against a `#put` path with no drain at all
(both measured). **The second is not shippable and was verified not to be.** `ContextStore#size`
takes the same mutex as the insert, so a split-lock `BoundedMap` — the one form where an
overshoot is genuinely reachable — was sampled by four concurrent `#size` readers across 64 000
inserts at `cap` 8 and **never reported above 8**, six runs, against six identical runs of the
shipped one-`synchronize` form. The design's `9`-at-`cap`-8 observation was taken from inside a
prototype's own hash, which no test written against this class's public surface can reach. The
one-`synchronize` discipline is therefore held by the source, the constant's comment and the
corpus note — not by a test — and that is filed as `OI-20` rather than papered over with a
sampler test that would pass against the defect it names.

**6. `while` versus a single `if`, which no test reaches at all.** Recorded next to the above so
nobody looks for the missing case: under one `synchronize` the two are behaviourally identical —
the design says so in as many words, and a `while` → `if` mutation leaves the whole suite green,
measured. The loop is written because `XCUT-14` makes it a MUST. Its enforcement is review, not
the suite.

## Task order and dependency chain

Nine tasks, in the order below. Each produces a file set that later tasks require by
`require_relative`; nothing is guessed forward, because Ruby resolves a constant reference at
**call time**, not at file-load time, and every promotion method's callee exists by the time any
test invokes it.

1. `Dexpace::ContextConflictError` — `CTX-8`'s named error, needed by Task 3.
2. `Dexpace::Context` (the shared module) + `FakeContext` (test support) — needed by Task 3.
3. `Dexpace::BoundedMap` (private) + `Dexpace::ContextStore` — `CTX-7`, `CTX-8`, `CTX-11`,
   `CTX-12`, `CTX-13`, `CTX-18`, `CTX-19`, and the `Fiber[]` boundary, all driven by `FakeContext`.
4. `Dexpace::Instrumentation::TraceIdFlavour` — needed by Task 7 (`Bundle`) and by Task 5's tests,
   which need `Bundle::NONE`. Moved ahead of the promotion chain because every chain test below
   needs an untraced bundle to build a context from.
5. `Dexpace::Instrumentation::NO_SPAN`, `NO_TRACER`, `NO_TRACER_FACTORY` — needed by Task 7.
6. `Dexpace::Instrumentation::Bundle` — needs Tasks 4 and 5.
7. `Dexpace::CallKey` (private) + the promotion chain: `DispatchContext`, `RequestContext`,
   `ExchangeContext` — `CTX-1`, `CTX-2`, `CTX-3`, `CTX-5`, `CTX-6`, `CTX-15`, `CTX-16`, `CTX-17`,
   plus `CTX-9`'s trap added to Task 3's `context_store_test.rb`. Needs Tasks 2, 3 and 6.
8. `Dexpace/NoWeakReferences`, the seventh cop, plus its `.rubocop.yml` wiring.
9. Wiring: `lib/dexpace.rb`'s final require order, the two regenerated artifacts (surface snapshot,
   RBS baseline), the checklist file, register updates, `CLAUDE.md`'s claims sentence.

Renumbered from the "12 lib files in dependency order" reading of the design's module-layout table
because that table lists files by directory, not by buildable order — this plan's order is the one
that keeps every task's tests real from the first `- [ ] Step 1`.

---

## Task 1: `Dexpace::ContextConflictError`

**Requirement IDs:** `CTX-8`'s "an error whose message identifies the key." **Design:**
"`Dexpace::ContextConflictError` — `CTX-8`."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/error/context_conflict_error.rb`,
  `gems/dexpace-core/sig/dexpace/error/context_conflict_error.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/error/context_conflict_error_test.rb`

**Interfaces:**
- Consumes: phase 1's `Dexpace::Error` (a module included by every error class in this
  repository).
- Produces: `Dexpace::ContextConflictError < ::StandardError`, `#call_key`. Task 3's
  `ContextStore#put` raises it.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CTX-8.
class DexpaceContextConflictErrorTest < DexpaceTestCase
  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::ContextConflictError, "k1"
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::ContextConflictError, caught)
  end

  test "the message identifies the key, per CTX-8's own words" do
    error = Dexpace::ContextConflictError.new("call-key-42")

    assert_equal("call-key-42", error.call_key)
    assert_includes(error.message, "call-key-42")
  end

  test "is not Dexpace::InvalidArgumentError -- a lost race is not an invalid argument" do
    refute_operator(Dexpace::ContextConflictError, :<, Dexpace::InvalidArgumentError)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/context_conflict_error_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::ContextConflictError`.

- [ ] **Step 3: Write `lib/dexpace/error/context_conflict_error.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # CTX-8's reject-on-duplicate loser: a #put lost the race for a call key another registration
  # already occupies. Not Dexpace::InvalidArgumentError -- the caller passed nothing invalid, it
  # lost a race, and a caller that cannot tell those two apart cannot retry correctly.
  class ContextConflictError < ::StandardError
    include Dexpace::Error

    attr_reader :call_key

    def initialize(call_key)
      @call_key = call_key
      super("a context is already registered under call key #{call_key.inspect} (CTX-8)")
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/error/context_conflict_error.rbs`**

```rbs
module Dexpace
  class ContextConflictError < ::StandardError
    include Dexpace::Error

    attr_reader call_key: String

    def initialize: (String call_key) -> void
  end
end
```

- [ ] **Step 5: Add the require to `lib/dexpace.rb`**

Immediately after phase 2's `error/cancelled_error` line: `require_relative "dexpace/error/context_conflict_error"`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/context_conflict_error_test.rb`
Expected: PASS, 3 runs. Verified on this plan's scratch tree: 3 runs, 5 assertions on 3.2.11 and
3.4.10; 3 runs, 6 assertions on 4.0.6 (the Minitest-version artifact above).

---

## Task 2: `Dexpace::Context` and `FakeContext`

**Requirement IDs:** `CTX-9`, `CTX-10`, `CTX-18` (the shared `#close` mechanism); the duck-typed
store validation every flavour's `initialize` calls. **Design:** "`Dexpace::Context` — the module
the three flavours share"; "One double, and it is a fake."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/context.rb`, `gems/dexpace-core/sig/dexpace/context.rbs`,
  `gems/dexpace-core/test/support/fake_context.rb`
- Test: `gems/dexpace-core/test/dexpace/context_test.rb`

**Interfaces:**
- Consumes: phase 1's `Dexpace::Model` (`Model.required!`), `Dexpace::InvalidArgumentError`.
- Produces: `Dexpace::Context` (a module: `.validate!(bundle:, call_key:, store:)`, `#close`).
  `FakeContext` (test-support, `include Dexpace::Context`, `attr_reader :call_key, :store`).
  Tasks 3 and 7 include `Dexpace::Context` into every context type.

**`FakeContext`'s only dependency is a minimal double for `store`** — a plain object responding to
`#set`/`#release` — which this task's own test builds inline, since `Dexpace::ContextStore` does
not exist until Task 3.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "../support/fake_context"

# CTX-9, CTX-10, CTX-18: #close is `store.release(self)`, and every clause of all three is a
# property of the store, not of Context itself.
class DexpaceContextTest < DexpaceTestCase
  FakeStore = Struct.new(:released_with) do
    def set(context) = context

    def release(context)
      self.released_with = context
      true
    end
  end

  test "#close delegates to store.release(self)" do
    store = FakeStore.new
    ctx = FakeContext.new(call_key: "k", store: store)

    assert(ctx.close)
    assert_same(ctx, store.released_with)
  end

  test "validate! requires a non-nil bundle" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Context.validate!(bundle: nil, call_key: "k", store: FakeStore.new)
    end
  end

  test "validate! requires a non-nil, non-empty call_key" do
    store = FakeStore.new

    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Context.validate!(bundle: :b, call_key: nil, store: store)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Context.validate!(bundle: :b, call_key: "", store: store)
    end
  end

  test "validate! requires a store that responds to #set and #release" do
    bad_store = Object.new

    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Context.validate!(bundle: :b, call_key: "k", store: bad_store)
    end
  end

  test "validate! passes for a store responding to both" do
    assert_nil(Dexpace::Context.validate!(bundle: :b, call_key: "k", store: FakeStore.new))
  end
end
```

`gems/dexpace-core/test/support/fake_context.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../lib/dexpace/context"

# The one double CTX's store suite needs: every store rule (CTX-7 through CTX-13, CTX-18, CTX-19)
# is about a keyed occupant and nothing else. A real in-memory implementation of Dexpace::Context,
# not a recorder of calls -- a fake by testing/7ecef8e8's definition, named Fake* per
# testing/630ba094. Gets #close free from the module, which is what makes the CTX-9/CTX-10 cases
# readable.
class FakeContext
  include Dexpace::Context

  attr_reader :call_key, :store

  def initialize(call_key:, store:)
    @call_key = call_key
    @store = store
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/context_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Context`, raised from
`test/support/fake_context.rb`'s own `require_relative "../../lib/dexpace/context"`, which the
suite requires explicitly on its third line. Nothing requires the fake transitively: neither
`test_helper.rb` nor `dexpace.rb` names it, which is open question 4's resolution applied here.

- [ ] **Step 3: Write `lib/dexpace/context.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "model"

module Dexpace
  # The module DispatchContext, RequestContext and ExchangeContext all include (P4-1: not a
  # namespace containing them -- Dexpace::Context::Request would shadow phase 1's Dexpace::Request
  # for every file inside `module Dexpace; module Context`).
  #
  # CTX-1's terminality -- "the exchange stage is terminal, no method promoting back" -- is
  # enforced by ExchangeContext defining no #promote_* method, not by a guard clause here.
  # #inspect is deliberately NOT overridden here, and the consequence is stated rather than
  # discovered: `store` is a Data member, so Data's generated #inspect walks it into the map and
  # prints one level of every OTHER occupant, each with its own request and response. Ruby's
  # recursion guard only elides the second visit to the store itself, so at
  # MAX_TRACKED_CONTEXTS = 1024 any `p ctx`, any assert_equal failure message and any string
  # interpolating a context becomes a dump of every in-flight call. Phase 1 shipped no #inspect
  # override on Request or Response either, and a redaction-aware rendering is OBS-11-OBS-19's and
  # XCUT-19's, which are phase 5's. What 4a owes instead is that no assertion in its own suite
  # compares whole contexts where a member comparison would do.
  module Context
    include Dexpace::Model

    # The construction validation every flavour's #initialize calls before its own fields.
    def self.validate!(bundle:, call_key:, store:)
      Model.required!("bundle", bundle)
      Model.required!("call_key", call_key)
      raise InvalidArgumentError, "call_key must not be empty" if call_key.empty?
      return if store.respond_to?(:set) && store.respond_to?(:release)

      raise InvalidArgumentError, "store must respond to #set and #release"
    end

    # CTX-9 (identity-conditional eviction), CTX-10 (a promoted intermediate's close is a no-op)
    # and CTX-18 (double-close is a well-defined no-op) in one line: every clause of all three is a
    # property of ContextStore#release, which this delegates to without a latch (P4-4 -- a frozen
    # Data instance cannot carry one; verified on 3.2.11, 3.4.10 and 4.0.6 that a method on a
    # frozen Data subclass writing an ivar raises FrozenError).
    def close
      store.release(self)
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/context.rbs`**

```rbs
module Dexpace
  module Context
    include Dexpace::Model

    def self.validate!: (bundle: Instrumentation::Bundle, call_key: String, store: untyped) -> void

    def close: () -> bool
  end
end
```

- [ ] **Step 5: Add the require to `lib/dexpace.rb`**

After Task 1's line: `require_relative "dexpace/context"`.

- [ ] **Step 6: Run the tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/context_test.rb`
Expected: PASS, 5 runs. Verified: 5 runs, 7 assertions, identical on **all three** interpreters —
this file's `assert_raises` blocks happen to net no delta under Minitest 6.0.0, unlike several
other files in this phase, which is why this plan states a run count as the pass criterion and
never an assertion count on its own.

---

## Task 3: `Dexpace::BoundedMap` and `Dexpace::ContextStore`

**Requirement IDs:** `CTX-7`, `CTX-8`, `CTX-10`, `CTX-11`, `CTX-12`, `CTX-13`, `CTX-18`, `CTX-19`,
plus the `Fiber[]` boundary `docs/knowledge/notes/observability.md` draws. **Design:** "R4 —
`CTX-11`'s bounded map, resolved"; "`Dexpace::ContextStore`."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/bounded_map.rb`, `gems/dexpace-core/lib/dexpace/context_store.rb`,
  `gems/dexpace-core/sig/dexpace/context_store.rbs`
- Test: `gems/dexpace-core/test/dexpace/context_store_test.rb`

**Interfaces:**
- Consumes: Task 1's `ContextConflictError`, Task 2's `FakeContext`.
- Produces: `Dexpace::ContextStore` — `MAX_TRACKED_CONTEXTS = 1024`, `.default`,
  `.new(cap: MAX_TRACKED_CONTEXTS)`, `#set(context)`, `#put(context)`, `#[](call_key)`,
  `#release(context)`, `#size`. `Dexpace::BoundedMap` is `private_constant` and ships no `sig/`
  (open question 2, closed above). Task 7 constructs contexts with `store: ContextStore.default`
  as their own default.

**Every store here is a fresh `Dexpace::ContextStore.new(cap:)`, never `.default`** — this suite
passes alone and in any order and never touches the process-wide store.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "../support/fake_context"

# CTX-7, CTX-8, CTX-10, CTX-11, CTX-12, CTX-13, CTX-18, CTX-19, and the Fiber[] boundary
# docs/knowledge/notes/observability.md draws. CTX-9's trap is added in Task 7, once a Data
# context with real value equality exists -- FakeContext has none.
class DexpaceContextStoreTest < DexpaceTestCase
  test "CTX-7: 16 threads registering 1000 distinct keys each lose nothing" do
    store = Dexpace::ContextStore.new(cap: 20_000)

    threads = Array.new(16) do |t|
      Thread.new do
        1000.times { |i| store.set(FakeContext.new(call_key: "t#{t}-#{i}", store: store)) }
      end
    end
    threads.each(&:join)

    assert_equal(16_000, store.size)
  end

  test "CTX-8: 32 threads racing one #put admit exactly one winner" do
    store = Dexpace::ContextStore.new(cap: 64)
    gate = Thread::Queue.new
    outcomes = Thread::Queue.new

    32.times do
      Thread.new do
        gate.pop
        outcomes << begin
          store.put(FakeContext.new(call_key: "shared", store: store))
          :ok
        rescue Dexpace::ContextConflictError => error
          error
        end
      end
    end
    32.times { gate << true }
    results = Array.new(32) { outcomes.pop }

    winners = results.count { |r| r == :ok }
    losers = results.grep(Dexpace::ContextConflictError)

    assert_equal(1, winners)
    assert_equal(31, losers.size)
    losers.each { |error| assert_includes(error.message, "shared") }
  end

  test "CTX-10: releasing a promoted intermediate is a no-op; the successor keeps the slot" do
    store = Dexpace::ContextStore.new(cap: 8)
    intermediate = FakeContext.new(call_key: "k", store: store)
    successor = FakeContext.new(call_key: "k", store: store)
    store.set(intermediate)
    store.set(successor)

    refute(store.release(intermediate))
    assert_same(successor, store["k"])
  end

  test "CTX-13: cap pressure evicts the first-registered; re-setting a key does not refresh it" do
    store = Dexpace::ContextStore.new(cap: 3)
    a = FakeContext.new(call_key: "a", store: store)
    b = FakeContext.new(call_key: "b", store: store)
    c = FakeContext.new(call_key: "c", store: store)
    store.set(a)
    store.set(b)
    store.set(c)

    # Simulates a promotion overwriting "a"'s slot: Hash#[]= on an existing key does not move it.
    store.set(FakeContext.new(call_key: "a", store: store))
    store.set(FakeContext.new(call_key: "d", store: store))

    assert_equal(3, store.size)
    assert_nil(store["a"])
    assert_same(b, store["b"])
    assert_same(c, store["c"])
    refute_nil(store["d"])
  end

  test "CTX-13/CTX-18: nothing in the store's own behaviour depends on any entry surviving" do
    store = Dexpace::ContextStore.new(cap: 1)
    a = FakeContext.new(call_key: "a", store: store)
    store.set(a)
    store.set(FakeContext.new(call_key: "b", store: store))

    refute(store.release(a))
  end

  test "CTX-18: an unknown key resolves to nil and never raises" do
    store = Dexpace::ContextStore.new(cap: 8)

    assert_nil(store["nope"])
  end

  test "CTX-18: double-close and cleanup-path close are well-defined no-ops" do
    store = Dexpace::ContextStore.new(cap: 8)
    ctx = FakeContext.new(call_key: "x", store: store)

    refute(store.release(ctx))

    store.set(ctx)
    assert(store.release(ctx))
    refute(store.release(ctx))
  end

  test "CTX-11/CTX-12/XCUT-14: the cap bound holds under concurrent inserts, from 16 threads" do
    store = Dexpace::ContextStore.new(cap: 64)

    threads = Array.new(16) do
      Thread.new do
        prefix = ::Thread.current.object_id
        500.times { |i| store.set(FakeContext.new(call_key: "#{prefix}-#{i}", store: store)) }
      end
    end
    threads.each(&:join)

    assert_equal(64, store.size)
  end

  # A discriminator against ObjectSpace::WeakMap and NOT a tautology: the same run against a
  # WeakMap returns 0 of 1000 after three GC.starts on all three interpreters. It is equally NOT a
  # discriminator against ObjectSpace::WeakKeyMap, which passes it -- a WeakKeyMap holds its values
  # strongly and the stored context strongly holds the frozen String that is its key, so no entry
  # is ever collectable. That spelling is forbidden by Dexpace/NoWeakReferences (Task 8) and by
  # nothing here.
  test "CTX-19: 1000 registered contexts stay reachable after the caller drops every local" do
    store = Dexpace::ContextStore.new(cap: 2048)
    keys = Array.new(1000) { |i| "k#{i}" }
    keys.each { |key| store.set(FakeContext.new(call_key: key, store: store)) }

    3.times { GC.start }

    assert_equal(1000, store.size)
    refute_nil(store[keys.first])
  end

  test "the store is process-wide, not fiber-scoped -- the Fiber[] boundary" do
    store = Dexpace::ContextStore.new(cap: 8)
    ctx = FakeContext.new(call_key: "fiber-probe", store: store)
    store.set(ctx)

    Fiber[:probe] = :main_fiber
    # The setup guard: without this pair, the assertions below would prove nothing about the
    # store being process-wide rather than merely reflecting one shared execution context.
    assert_equal(:main_fiber, Fiber[:probe])
    assert_nil(::Thread.current[:probe])

    from_fiber = Fiber.new { store["fiber-probe"] }.resume
    from_thread = nil
    Thread.new { from_thread = store["fiber-probe"] }.join
    from_enumerator = Enumerator.new { |y| y << store["fiber-probe"] }.next

    assert_same(ctx, from_fiber)
    assert_same(ctx, from_thread)
    assert_same(ctx, from_enumerator)
  end

  # CTX-12/XCUT-14, and the assertion that is NOT the obvious one. The aggregate drain-iteration
  # count (inserts - final size) is an arithmetic identity that any one-eviction-per-iteration
  # drain reproduces, split-lock or no loop at all -- docs/knowledge/notes/execution-context.md
  # records the measurement and the trap. What discriminates single-threaded is this: from a store
  # already at cap, every further insert evicts EXACTLY ONE prior occupant and the size is never
  # observed above the cap, which is the drain body running at most once per insert.
  #
  # What this canNOT reach, stated so nobody reads more into it: `while` vs a single `if` is
  # behaviourally identical under the one-synchronize insert-and-drain (the loop is written because
  # XCUT-14 makes it a MUST), and the split-lock overshoot the note measures is invisible through
  # this class's public surface -- #size takes the same mutex. Verified: a split-lock BoundedMap
  # sampled by four concurrent #size readers across 64 000 inserts at cap 8 never reports above 8
  # on CRuby. OI-20.
  test "CTX-12/XCUT-14: from cap, each insert evicts exactly one, and size never exceeds cap" do
    store = Dexpace::ContextStore.new(cap: 8)
    seeds = Array.new(8) { |i| "seed-#{i}" }
    seeds.each { |key| store.set(FakeContext.new(call_key: key, store: store)) }

    sizes = []
    evictions = []
    keys = seeds.dup
    100.times do |i|
      before = keys.count { |key| store[key] }
      store.set(FakeContext.new(call_key: "fill-#{i}", store: store))
      sizes << store.size
      evictions << (before - keys.count { |key| store[key] })
      keys << "fill-#{i}"
    end

    assert_equal([8], sizes.uniq)
    assert_equal([1], evictions.uniq)
  end

  # XCUT-14 says "after each insert", and #put is an insert. Without this case the drain can be
  # deleted from the reject-on-duplicate path with the whole suite still green.
  test "CTX-8/CTX-11/XCUT-14: the reject-on-duplicate insert drains to the cap too" do
    store = Dexpace::ContextStore.new(cap: 3)

    6.times { |i| store.put(FakeContext.new(call_key: "p#{i}", store: store)) }

    assert_equal(3, store.size)
  end

  # P4-9's number, asserted rather than assumed: AUTH-19's stated default for a store of this
  # shape is the one number the specification supplies, and DEF-36 attaches a configuration
  # source to it without changing a signature.
  test "CTX-11: MAX_TRACKED_CONTEXTS is 1024 and is the cap a default-constructed store uses" do
    assert_equal(1024, Dexpace::ContextStore::MAX_TRACKED_CONTEXTS)

    store = Dexpace::ContextStore.new

    2000.times { |i| store.set(FakeContext.new(call_key: "d#{i}", store: store)) }

    assert_equal(Dexpace::ContextStore::MAX_TRACKED_CONTEXTS, store.size)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/context_store_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::ContextStore`.

- [ ] **Step 3: Write `lib/dexpace/bounded_map.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "model"

module Dexpace
  # The one bounded-keyed-map implementation XCUT-14's general rule, CTX-11's context store and
  # (phase 6) AUTH-19's per-nonce counter store all share. Not public API: CTX-4 says outright that
  # "the exact format and the counter mechanism are a reference choice", and NFR-4 locks every
  # public name at the first release tag, so a generator nothing outside core needs to name stays
  # unlocked. Reachable by a bare name from any `module Dexpace; module X` at any nesting depth,
  # and from nowhere else -- verified on 3.2.11, 3.4.10 and 4.0.6.
  #
  # Insert and drain sit in ONE Thread::Mutex#synchronize, so the drain body runs AT MOST ONCE per
  # insert: the loop's invariant on entry is size <= cap, so size <= cap + 1 at the top. It is
  # written as a loop because XCUT-14 makes that a MUST, not because more than one iteration is
  # reachable under this lock discipline -- see docs/knowledge/notes/execution-context.md.
  class BoundedMap
    def initialize(cap:)
      @cap = Model.required!("cap", cap)
      @h = {}
      @mutex = ::Thread::Mutex.new
    end

    # Unconditional overwrite. Never raises.
    def set(key, value)
      @mutex.synchronize do
        @h[key] = value
        @h.shift while @h.size > @cap
      end
      value
    end

    # Reject-on-duplicate insert. Returns whether THIS call installed the value; the caller decides
    # what a false return means. Never raises -- the conflict is a return value, not an exception,
    # so ContextStore can raise its own error naming the key AFTER this mutex is released.
    def put(key, value)
      @mutex.synchronize do
        next false if @h.key?(key)

        @h[key] = value
        @h.shift while @h.size > @cap
        true
      end
    end

    def [](key)
      @mutex.synchronize { @h[key] }
    end

    # Identity-conditional delete: removes the slot only when its current occupant is the object
    # handed in (`equal?`), never by value equality. Named for its mechanism, not for CTX-9 --
    # phase 6's AUTH-19 counter store never calls it, and a general map should not carry a
    # context-shaped name.
    def delete_if_identical(key, object)
      @mutex.synchronize do
        next false unless @h.key?(key) && @h[key].equal?(object)

        @h.delete(key)
        true
      end
    end

    def size
      @mutex.synchronize { @h.size }
    end
  end
  private_constant :BoundedMap
end
```

- [ ] **Step 4: Write `lib/dexpace/context_store.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "bounded_map"
require_relative "error/context_conflict_error"

module Dexpace
  # CTX-7 through CTX-13, CTX-18, CTX-19. HAS a BoundedMap rather than BEING one, so CTX-8's and
  # CTX-18's two-operation surface is what a caller sees.
  class ContextStore
    # AUTH-19's stated default for a bounded store of exactly this shape (P4-9). Neither CTX-11 nor
    # XCUT-14 names a number.
    MAX_TRACKED_CONTEXTS = 1024

    class << self
      # The one process-wide instance. Not a constant: a live store cannot be frozen at
      # assignment, which a mutable constant must be.
      def default
        @default ||= new
      end
    end

    def initialize(cap: MAX_TRACKED_CONTEXTS)
      @map = BoundedMap.new(cap: cap)
    end

    # CTX-8's unconditional overwrite. Never raises. Used by both promotions and by nothing else.
    def set(context)
      @map.set(context.call_key, context)
      context
    end

    # CTX-8's reject-on-duplicate insert. The conflict is detected under the map's mutex and the
    # error is raised after it is released.
    def put(context)
      return context if @map.put(context.call_key, context)

      raise ContextConflictError, context.call_key
    end

    # CTX-18's explicit absent result. nil is legitimate here: the requirement demands it and
    # forbids raising.
    def [](call_key)
      @map[call_key]
    end

    # CTX-9's identity-conditional eviction, CTX-10's intermediate no-op and CTX-18's unknown-key
    # no-op. Returns whether a slot was cleared.
    def release(context)
      @map.delete_if_identical(context.call_key, context)
    end

    def size
      @map.size
    end
  end
end
```

- [ ] **Step 5: Write `sig/dexpace/context_store.rbs`**

```rbs
module Dexpace
  class ContextStore
    MAX_TRACKED_CONTEXTS: Integer

    def self.default: () -> ContextStore

    def initialize: (?cap: Integer) -> void
    def set: (Context context) -> Context
    def put: (Context context) -> Context
    def []: (String call_key) -> Context?
    def release: (Context context) -> bool
    def size: () -> Integer
  end
end
```

- [ ] **Step 6: Add the requires to `lib/dexpace.rb`**

After Task 2's line, in order: `require_relative "dexpace/bounded_map"`, then
`require_relative "dexpace/context_store"`.

- [ ] **Step 7: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/context_store_test.rb`
Expected: PASS, 13 runs. Verified: 13 runs, 90 assertions, identical on **all three**
interpreters — this file's assertions are all plain (no `assert_raises`/`refute_respond_to`), so
the Minitest-version artifact above does not reach it. Re-run with `--seed` set to each of 1, 2, 3,
42, 12345: identical counts every time, because every thread count and cap in this file is a
literal, not a function of the seed.

- [ ] **Step 8: Run on the floor interpreter**

Run: `mise exec ruby@3.2.11 -- bundle exec ruby -w gems/dexpace-core/test/dexpace/context_store_test.rb`
Expected: PASS, 13 runs, 90 assertions. This is the run that proves `ObjectSpace::WeakMap` is not
silently substituted anywhere in this file's path — 3.2.11 does not even define `WeakKeyMap`, so a
`NameError` here (rather than a clean pass) would mean something in the require chain reaches for
it.

---

## Task 4: `Dexpace::Instrumentation::TraceIdFlavour`

**Requirement IDs:** `OBS-27`'s trace-id encoding flavours; `CTX-14`'s "a trace-id encoding
flavor" slot. **Design:** "`TraceIdFlavour`."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/trace_id_flavour.rb`,
  `gems/dexpace-core/sig/dexpace/instrumentation/trace_id_flavour.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/trace_id_flavour_test.rb`

**Interfaces:**
- Consumes: phase 1's `Dexpace::Model`.
- Produces: `Dexpace::Instrumentation::TraceIdFlavour` — `.build(name:, trace_id_pattern:,
  invalid_trace_id:)`, `.of(name)`, `#valid_trace_id?(trace_id)`, `#renders?(trace_id)`,
  `::NONE`, `::W3C`, `::DATADOG`. Task 6 (`Bundle`) requires all three constants.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# OBS-27's trace-id flavours.
class DexpaceInstrumentationTraceIdFlavourTest < DexpaceTestCase
  Flavour = Dexpace::Instrumentation::TraceIdFlavour

  FLAVOURS = [
    Flavour::NONE,
    Flavour::W3C,
    Flavour::DATADOG,
  ].freeze

  VALID_SAMPLES = {
    Flavour::W3C => ["a" * 32, "0123456789abcdef" * 2],
    Flavour::DATADOG => %w[1 42 18446744073709551615],
  }.freeze

  test ".of round-trips a recognised name" do
    FLAVOURS.each { |flavour| assert_same(flavour, Flavour.of(flavour.name)) }
  end

  test ".of raises Dexpace::InvalidArgumentError on an unrecognised name" do
    assert_raises(Dexpace::InvalidArgumentError) { Flavour.of(:bogus) }
  end

  test "NONE's sentinel is OBS-26's 32 hex zeros, not a flavour-specific zero draw" do
    assert_equal("0" * 32, Flavour::NONE.invalid_trace_id)
  end

  test "DATADOG's own zero draw is '0', distinct from OBS-26's sentinel" do
    assert_equal("0", Flavour::DATADOG.invalid_trace_id)
  end

  # testing/f36a19cd: a parse-constructor invariant gets a round-trip property test.
  # #renders?(x) == (#valid_trace_id?(x) || x == invalid_trace_id) for every generated x, and the
  # two predicates disagree at exactly one input: the flavour's own sentinel.
  test "renders? and valid_trace_id? agree everywhere except at the sentinel" do
    sample(count: 64, seed: 20_260_908) do |rng|
      flavour = FLAVOURS.sample(random: rng)
      candidates = [flavour.invalid_trace_id] + (VALID_SAMPLES[flavour] || [])
      candidate = candidates.sample(random: rng) || flavour.invalid_trace_id

      assert_equal(
        flavour.valid_trace_id?(candidate) || candidate == flavour.invalid_trace_id,
        flavour.renders?(candidate),
      )
    end
  end

  test "the sentinel is the one input where the two predicates disagree" do
    FLAVOURS.each do |flavour|
      assert(flavour.renders?(flavour.invalid_trace_id))
      refute(flavour.valid_trace_id?(flavour.invalid_trace_id))
    end
  end

  test "DATADOG accepts a 64-bit decimal rendering and nothing wider" do
    datadog = Flavour::DATADOG

    assert(datadog.valid_trace_id?("18446744073709551615"))
    refute(datadog.valid_trace_id?("184467440737095516150"))
    refute(datadog.valid_trace_id?("1a"))
    refute(datadog.valid_trace_id?(""))
  end

  test "W3C accepts exactly 32 lowercase hex characters" do
    assert(Flavour::W3C.valid_trace_id?("a" * 32))
    refute(Flavour::W3C.valid_trace_id?("A" * 32))
    refute(Flavour::W3C.valid_trace_id?("a" * 31))
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/trace_id_flavour_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Instrumentation`.

- [ ] **Step 3: Write `lib/dexpace/instrumentation/trace_id_flavour.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"

module Dexpace
  module Instrumentation
    # OBS-27's trace-id encoding flavours: a frozen Data over a frozen table with an .of factory,
    # never a case statement or a bare Symbol -- the per-flavour behaviour (a pattern and a
    # sentinel) is data, not code.
    class TraceIdFlavour < Data.define(:name, :trace_id_pattern, :invalid_trace_id)
      include Dexpace::Model
      private_class_method :new

      def self.build(name:, trace_id_pattern:, invalid_trace_id:)
        new(name: name, trace_id_pattern: trace_id_pattern, invalid_trace_id: invalid_trace_id)
      end

      def initialize(name:, trace_id_pattern:, invalid_trace_id:)
        Model.required!("name", name)
        Model.required!("trace_id_pattern", trace_id_pattern)
        Model.required!("invalid_trace_id", invalid_trace_id)

        super
      end

      def valid_trace_id?(trace_id)
        trace_id != invalid_trace_id && trace_id_pattern.match?(trace_id)
      end

      def renders?(trace_id)
        trace_id == invalid_trace_id || trace_id_pattern.match?(trace_id)
      end

      # OBS-26's reserved sentinel: 32 hex zeros. Matches nothing else -- only the sentinel
      # renders -- because a disabled-tracing bundle carries no trace id of its own.
      NONE = build(
        name: :none,
        trace_id_pattern: Regexp.new("\\A(?!)\\z", timeout: 1.0),
        invalid_trace_id: ("0" * 32).freeze,
      )

      # OBS-27's W3C flavour: 128-bit value rendered as 32 lowercase hex chars.
      W3C = build(
        name: :w3c,
        trace_id_pattern: Regexp.new("\\A[0-9a-f]{32}\\z", timeout: 1.0),
        invalid_trace_id: ("0" * 32).freeze,
      )

      # OBS-27's Datadog flavour: a 64-bit unsigned integer rendered as a decimal string. Its own
      # zero draw is "0", distinct from OBS-26's 32-hex-zero sentinel -- P4-7.
      DATADOG = build(
        name: :datadog,
        trace_id_pattern: Regexp.new("\\A[0-9]{1,20}\\z", timeout: 1.0),
        invalid_trace_id: "0",
      )

      ALL = [NONE, W3C, DATADOG].freeze

      def self.of(name)
        ALL.find { |flavour| flavour.name == name } ||
          raise(InvalidArgumentError, "unrecognised trace-id flavour: #{name.inspect}")
      end
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/instrumentation/trace_id_flavour.rbs`**

```rbs
module Dexpace
  module Instrumentation
    class TraceIdFlavour
      include Dexpace::Model

      attr_reader name: Symbol
      attr_reader trace_id_pattern: Regexp
      attr_reader invalid_trace_id: String

      NONE: TraceIdFlavour
      W3C: TraceIdFlavour
      DATADOG: TraceIdFlavour
      ALL: Array[TraceIdFlavour]

      def self.build: (name: Symbol, trace_id_pattern: Regexp, invalid_trace_id: String) -> TraceIdFlavour
      def self.of: (Symbol name) -> TraceIdFlavour

      def valid_trace_id?: (String trace_id) -> bool
      def renders?: (String trace_id) -> bool

      def ==: (untyped other) -> bool
      def eql?: (untyped other) -> bool
      def hash: () -> Integer
      def to_h: () -> Hash[Symbol, untyped]
      def with: (**untyped changes) -> TraceIdFlavour
    end
  end
end
```

- [ ] **Step 5: Add the require to `lib/dexpace.rb`**

After Task 3's lines: `require_relative "dexpace/instrumentation/trace_id_flavour"`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/trace_id_flavour_test.rb`
Expected: PASS, 8 runs. Verified: 8 runs, 83 assertions on 3.2.11 and 3.4.10, identical on 4.0.6.

---

## Task 5: `Dexpace::Instrumentation::NO_SPAN`, `NO_TRACER`, `NO_TRACER_FACTORY`

**Requirement IDs:** `CTX-14`'s "an active span" and "a per-operation tracer factory" slots;
`CTX-15`'s "a no-op span and no-op tracer factory"; `CTX-20`'s embedded MUST ("its factory method
MUST be safe to invoke concurrently"); `OBS-25`'s "MUST NOT allocate per call" (the shape this
phase gives it to make it assertable — the protocol itself is `DEF-37`, phase 5's). **Design:**
"The two no-op singletons, and the exact line phase 5 may not cross."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/no_span.rb`,
  `gems/dexpace-core/lib/dexpace/instrumentation/no_tracer.rb`,
  `gems/dexpace-core/sig/dexpace/instrumentation/no_span.rbs`,
  `gems/dexpace-core/sig/dexpace/instrumentation/no_tracer.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/no_span_test.rb`,
  `gems/dexpace-core/test/dexpace/instrumentation/no_tracer_test.rb`

**Interfaces:**
- Consumes: nothing beyond core Ruby.
- Produces: `Dexpace::Instrumentation::NO_SPAN` (one frozen instance of a `private_constant`
  class); `Dexpace::Instrumentation::NO_TRACER` (ditto) and `::NO_TRACER_FACTORY`
  (`#tracer(deprecated_name = nil, deprecated_version = nil, name: nil, version: nil, attributes:
  nil)` → `NO_TRACER`, always). Task 6 (`Bundle`) defaults `span:`/`tracer_factory:` to these two.
  RBS interfaces `_Span`, `_Tracer`, `_TracerFactory` — declared here, deliberately empty of
  members except `_TracerFactory#tracer`, per open question 1's resolution above.

- [ ] **Step 1: Write the failing tests**

`no_span_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CTX-15: a shared, frozen no-op span object.
class DexpaceInstrumentationNoSpanTest < DexpaceTestCase
  test "NO_SPAN is a single frozen instance" do
    assert_predicate(Dexpace::Instrumentation::NO_SPAN, :frozen?)
  end
end
```

`no_tracer_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CTX-20: the no-op tracer factory's method MUST be safe to invoke concurrently, and OBS-25's
# "MUST NOT allocate per call" is what the identity assertion below is for.
class DexpaceInstrumentationNoTracerTest < DexpaceTestCase
  # P4-8 and open question 1: the point of the mirrored signature is CALL COMPATIBILITY, and the
  # call shapes alone do not assert it. On Ruby 3.x a method that accepts no keyword parameters
  # receives `tracer(name: "n")` as a positional Hash, so every keyword call below passes just as
  # well against `def tracer(a = nil, b = nil)` -- the whole keyword half of the gem's signature
  # can be deleted with the call-shape assertions still green. The parameter list is the
  # discriminating assertion; the call shapes are the regression test for what callers write.
  test "the factory method mirrors opentelemetry-api 1.11.0's parameter list exactly" do
    assert_equal(
      [%i[opt deprecated_name], %i[opt deprecated_version],
       %i[key name], %i[key version], %i[key attributes],],
      Dexpace::Instrumentation::NO_TRACER_FACTORY.method(:tracer).parameters,
    )
  end

  test "the factory method accepts opentelemetry-api 1.11.0's own positional and keyword shape" do
    factory = Dexpace::Instrumentation::NO_TRACER_FACTORY

    assert_same(Dexpace::Instrumentation::NO_TRACER, factory.tracer)
    assert_same(Dexpace::Instrumentation::NO_TRACER, factory.tracer("name"))
    assert_same(Dexpace::Instrumentation::NO_TRACER, factory.tracer("name", "1.0"))
    assert_same(
      Dexpace::Instrumentation::NO_TRACER,
      factory.tracer(name: "name", version: "1.0", attributes: {}),
    )
    assert_same(Dexpace::Instrumentation::NO_TRACER, factory.tracer("name", name: "other"))
  end

  test "CTX-20: 16 threads calling #tracer concurrently all get the same object" do
    factory = Dexpace::Instrumentation::NO_TRACER_FACTORY
    results = Array.new(16)

    threads = Array.new(16) { |i| Thread.new { results[i] = factory.tracer } }
    threads.each(&:join)

    results.each { |tracer| assert_same(Dexpace::Instrumentation::NO_TRACER, tracer) }
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/no_span_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Instrumentation::NO_SPAN`. Then the same for
`no_tracer_test.rb`.

- [ ] **Step 3: Write `lib/dexpace/instrumentation/no_span.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # CTX-15's no-op span. Responds to nothing beyond Object's own surface: phase 4 fixes the
    # slot and the identity of the object filling it; OBS-21/OBS-25 fix the protocol, and that is
    # phase 5's (DEF-37). One frozen instance, so OBS-25's "MUST NOT allocate per call" is
    # assertable by reference identity.
    # rubocop:disable-next Lint/EmptyClass -- DEF-37: phase 5 adds the protocol.
    class NoSpan; end
    private_constant :NoSpan

    NO_SPAN = NoSpan.new.freeze
  end
end
```

- [ ] **Step 4: Write `lib/dexpace/instrumentation/no_tracer.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # CTX-20's no-op tracer, returned by NO_TRACER_FACTORY#tracer. One frozen instance.
    # rubocop:disable-next Lint/EmptyClass -- DEF-37: phase 5 adds the protocol.
    class NoTracer; end
    private_constant :NoTracer

    NO_TRACER = NoTracer.new.freeze

    # CTX-20's no-op tracer factory. Not empty: CTX-20's embedded MUST ("Its factory method MUST
    # be safe to invoke concurrently from multiple threads") forbids that -- a factory with no
    # factory method cannot satisfy a MUST about that method.
    #
    # #tracer's name and positional arity mirror opentelemetry-api's own
    # OpenTelemetry::Trace::TracerProvider#tracer (opentelemetry-api 1.11.0,
    # lib/opentelemetry/trace/tracer_provider.rb, fetched and read from rubygems.org 2026-09-08)
    # rather than this repository's own keywords-everywhere rule (api-design/1d9e6e0b), because
    # being call-compatible with a foreign TracerProvider is this method's entire purpose (P4-8):
    # an application already running OpenTelemetry must be able to pass
    # OpenTelemetry.tracer_provider straight into Bundle.build(tracer_factory:). The gem itself
    # keeps the two legacy positional parameters for callers written against its older
    # two-argument form while keyword arguments take precedence on the same slot; all five
    # arguments are ignored here, and concurrency safety is structural, since the factory holds no
    # state.
    class NoTracerFactory
      # rubocop:disable Lint/UnusedMethodArgument, Metrics/ParameterLists -- every argument is
      # part of the mirrored signature and is deliberately unused, and the count is the gem's,
      # not this repository's; see the class comment and P4-8.
      def tracer(deprecated_name = nil, deprecated_version = nil, name: nil, version: nil,
                 attributes: nil)
        NO_TRACER
      end
      # rubocop:enable Lint/UnusedMethodArgument, Metrics/ParameterLists
    end
    private_constant :NoTracerFactory

    NO_TRACER_FACTORY = NoTracerFactory.new.freeze
  end
end
```

- [ ] **Step 5: Write the two `sig/` mirrors**

`sig/dexpace/instrumentation/no_span.rbs`:

```rbs
module Dexpace
  module Instrumentation
    interface _Span
    end

    NO_SPAN: _Span
  end
end
```

`sig/dexpace/instrumentation/no_tracer.rbs`:

```rbs
module Dexpace
  module Instrumentation
    interface _Tracer
    end

    interface _TracerFactory
      def tracer: (?String? deprecated_name, ?String? deprecated_version, ?name: String?,
                   ?version: String?, ?attributes: Hash[String, untyped]?) -> _Tracer
    end

    NO_TRACER: _Tracer
    NO_TRACER_FACTORY: _TracerFactory
  end
end
```

`_Span` and `_Tracer` are declared **empty** on purpose: phase 4 fixes the slots, phase 5 fixes
the protocols (`DEF-37`). Declaring them as RBS interfaces rather than typing the two slots
`untyped` keeps `NFR-11` mechanical — no constant outside `Dexpace::` appears in any public
signature.

- [ ] **Step 6: Add the requires to `lib/dexpace.rb`**

After Task 4's line, in order: `require_relative "dexpace/instrumentation/no_span"`, then
`require_relative "dexpace/instrumentation/no_tracer"`.

- [ ] **Step 7: Run the tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/no_span_test.rb` and
`no_tracer_test.rb`. Expected: PASS, 1 run and 3 runs. Verified: `no_span_test.rb` 1 run, 1
assertion on 3.2.11/3.4.10, 2 on 4.0.6 (Minitest artifact); `no_tracer_test.rb` 3 runs, 22
assertions on all three (no composite assertions in this file, so no artifact).

---

## Task 6: `Dexpace::Instrumentation::Bundle`

**Requirement IDs:** `CTX-14`, `CTX-15`, `OBS-26`, `OBS-27`. **Design:** "R3 — the `Bundle`'s
members, their names, and the phase-5 handshake"; P4-6, P4-7 (both already filed).

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/bundle.rb`,
  `gems/dexpace-core/sig/dexpace/instrumentation/bundle.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/bundle_test.rb`

**Interfaces:**
- Consumes: Task 4's `TraceIdFlavour`, Task 5's `NO_SPAN`/`NO_TRACER_FACTORY`, phase 1's `Model`.
- Produces: `Dexpace::Instrumentation::Bundle` — eight members (`trace_id`, `span_id`,
  `trace_flags`, `trace_state`, `flavour`, `remote`, `span`, `tracer_factory`), `#valid?`
  (derived), `#remote?`, `::NONE`, `::INVALID_SPAN_ID`. Task 7 (every context flavour) requires
  `bundle:` and defaults nothing to `Bundle::NONE` automatically — the caller names it.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CTX-14, CTX-15, OBS-26, OBS-27, P4-6, P4-7.
class DexpaceInstrumentationBundleTest < DexpaceTestCase
  Bundle = Dexpace::Instrumentation::Bundle
  W3C = Dexpace::Instrumentation::TraceIdFlavour::W3C

  test "CTX-15: Bundle::NONE carries OBS-26's reserved sentinels, isValid false, isRemote false" do
    bundle = Bundle::NONE

    assert_equal("0" * 32, bundle.trace_id)
    assert_equal("0" * 16, bundle.span_id)
    assert_equal("00", bundle.trace_flags)
    assert_equal([], bundle.trace_state)
    refute_predicate(bundle, :valid?)
    refute_predicate(bundle, :remote?)
    assert_same(Dexpace::Instrumentation::NO_SPAN, bundle.span)
    assert_same(Dexpace::Instrumentation::NO_TRACER_FACTORY, bundle.tracer_factory)
  end

  test "trace_id:, span_id: and flavour: are required -- there is no silent untraced default" do
    error = assert_raises(ArgumentError) do
      Bundle.build(span_id: "a" * 16, flavour: W3C)
    end

    # Both halves are load-bearing. Dexpace::InvalidArgumentError IS an ::ArgumentError (phase 1,
    # P1-3), so `assert_raises(ArgumentError)` alone passes just as well against a .build that
    # defaulted trace_id: to nil and let Model.required! reject it -- which is exactly the silent
    # untraced default this test exists to forbid. Ruby's own missing-keyword failure is the
    # assertion; the refute is what makes it discriminating.
    refute_kind_of(Dexpace::InvalidArgumentError, error)
    assert_includes(error.message, "missing keyword")
  end

  test "OBS-26: an all-zero span id makes a bundle invalid even when its trace id is real" do
    bundle = Bundle.build(
      trace_id: "a" * 32, span_id: Bundle::INVALID_SPAN_ID, flavour: W3C,
    )

    refute_predicate(bundle, :valid?)
  end

  test "OBS-26: span_id, trace_flags and trace_state are each validated on their own" do
    base = { trace_id: "a" * 32, span_id: "b" * 16, flavour: W3C }

    assert_raises(Dexpace::InvalidArgumentError) do
      Bundle.build(**base, span_id: "B" * 16)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Bundle.build(**base, trace_flags: "0")
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Bundle.build(**base, trace_flags: "ZZ")
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Bundle.build(**base, trace_state: [["vendor"]])
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Bundle.build(**base, trace_state: [%w[vendor value], :not_a_pair])
    end
  end

  test "CTX-7: a bundle is frozen on construction, Bundle::NONE included" do
    assert_predicate(Bundle::NONE, :frozen?)
    assert_predicate(
      Bundle.build(trace_id: "a" * 32, span_id: "b" * 16, flavour: W3C),
      :frozen?,
    )
  end

  test "an explicit nil trace_id gets SEAM-29's message, not a missing-keyword error" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Bundle.build(trace_id: nil, span_id: "a" * 16, flavour: W3C)
    end

    assert_equal("trace_id is required", error.message)
  end

  test "a valid W3C bundle reports valid? true" do
    bundle = Bundle.build(trace_id: "a" * 32, span_id: "b" * 16, flavour: W3C)

    assert_predicate(bundle, :valid?)
  end

  test "a malformed span_id is rejected even though valid? would not have caught it" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Bundle.build(trace_id: "a" * 32, span_id: "not-hex", flavour: W3C)
    end
  end

  test "a trace_id that does not match its flavour is rejected" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Bundle.build(trace_id: "42", span_id: "b" * 16, flavour: W3C)
    end
  end

  test "trace_state is deep-frozen through Model.own, independent of the caller's array" do
    source = [%w[vendor value]]
    bundle = Bundle.build(
      trace_id: "a" * 32, span_id: "b" * 16, flavour: W3C, trace_state: source,
    )
    source << %w[other value]

    assert_equal([%w[vendor value]], bundle.trace_state)
    assert_predicate(bundle.trace_state, :frozen?)
    assert_predicate(bundle.trace_state.first, :frozen?)
  end

  # testing/f36a19cd's round trip.
  test "Bundle.build(**bundle.to_h) == bundle for every generated bundle" do
    sample(count: 32, seed: 20_260_908) do |rng|
      trace_id = rng.rand < 0.5 ? "a" * 32 : W3C.invalid_trace_id
      bundle = Bundle.build(trace_id: trace_id, span_id: "b" * 16, flavour: W3C)

      assert_equal(bundle, Bundle.build(**bundle.to_h))
    end
  end

  test "#with preserves member identity for members it is not handed" do
    bundle = Bundle.build(trace_id: "a" * 32, span_id: "b" * 16, flavour: W3C)
    changed = bundle.with(remote: true)

    assert_same(bundle.span, changed.span)
    assert_same(bundle.tracer_factory, changed.tracer_factory)
    assert_predicate(changed, :remote?)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/bundle_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Instrumentation::Bundle`.

- [ ] **Step 3: Write `lib/dexpace/instrumentation/bundle.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "trace_id_flavour"
require_relative "no_span"
require_relative "no_tracer"

module Dexpace
  module Instrumentation
    # CTX-14's correlation/instrumentation bundle. Nine things CTX-14 says the bundle must EXPOSE;
    # eight are stored members and the ninth, validity, is derived (P4-6) -- OBS-26 makes "an
    # all-zero trace/span id MUST be treated as invalid" a MUST, so validity is a function of
    # trace_id and span_id and not an independently settable fact.
    class Bundle < Data.define(
      :trace_id, :span_id, :trace_flags, :trace_state, :flavour, :remote, :span, :tracer_factory,
    )
      include Dexpace::Model
      private_class_method :new

      # OBS-26's reserved span-id sentinel: 16 hex zeros. Flavour-independent -- OBS-26 states the
      # span-id rule unqualified while OBS-27's flavours scope only the trace id (P4-7).
      INVALID_SPAN_ID = ("0" * 16).freeze

      SPAN_ID_PATTERN = Regexp.new("\\A[0-9a-f]{16}\\z", timeout: 1.0)
      private_constant :SPAN_ID_PATTERN

      TRACE_FLAGS_PATTERN = Regexp.new("\\A[0-9a-f]{2}\\z", timeout: 1.0)
      private_constant :TRACE_FLAGS_PATTERN

      # trace_id:, span_id: and flavour: are required deliberately -- defaulting them would make
      # "I forgot to pass a trace id" produce a silently untraced bundle, invisible for exactly the
      # reason CTX-15 names. A caller who wants the untraced value names Bundle::NONE.
      # rubocop:disable Metrics/ParameterLists -- every parameter is a keyword
      # (api-design/1d9e6e0b) and the cop counts keywords; CTX-14 fixes the member set.
      def self.build(trace_id:, span_id:, flavour:, trace_flags: "00", trace_state: [],
                     remote: false, span: NO_SPAN, tracer_factory: NO_TRACER_FACTORY)
        new(
          trace_id: trace_id, span_id: span_id, trace_flags: trace_flags,
          trace_state: Model.own(trace_state), flavour: flavour, remote: remote,
          span: span, tracer_factory: tracer_factory,
        )
      end

      def initialize(trace_id:, span_id:, trace_flags:, trace_state:, flavour:, remote:, span:,
                     tracer_factory:)
        Model.required!("trace_id", trace_id)
        Model.required!("span_id", span_id)
        Model.required!("trace_flags", trace_flags)
        Model.required!("flavour", flavour)
        unless flavour.renders?(trace_id)
          raise InvalidArgumentError, "trace_id does not match flavour #{flavour.name.inspect}"
        end
        unless valid_span_id?(span_id)
          raise InvalidArgumentError, "span_id must be 16 lowercase hex chars (OBS-26)"
        end
        unless TRACE_FLAGS_PATTERN.match?(trace_flags)
          raise InvalidArgumentError, "trace_flags must be two lowercase hex chars"
        end
        unless trace_state.is_a?(::Array) && trace_state.all? { |pair| string_pair?(pair) }
          raise InvalidArgumentError, "trace_state must be an array of two-element string pairs"
        end

        super
      end
      # rubocop:enable Metrics/ParameterLists

      # Derived, not stored (P4-6): a function of trace_id and span_id, so
      # Bundle.build(trace_id: <real>, span_id: <real>, valid: false) is not representable.
      def valid?
        flavour.valid_trace_id?(trace_id) && span_id != INVALID_SPAN_ID
      end

      def remote? = remote

      # Hoisted out of #initialize so the validation reads as one line per member and the
      # constructor's branch count stays legible; private, so it takes no surface-manifest row.
      # OBS-26's sentinel is legal here and OBS-27 does not scope the span id, so the reserved
      # value and the 16-hex form are the two accepted shapes (P4-7).
      def valid_span_id?(value)
        value == INVALID_SPAN_ID || SPAN_ID_PATTERN.match?(value)
      end
      private :valid_span_id?

      def string_pair?(value)
        value.is_a?(::Array) && value.size == 2 && value.all?(String)
      end
      private :string_pair?

      # CTX-15's disabled-tracing default. The shared frozen singleton every untraced call
      # carries; CTX-4's call-key derivation stays call-unique across it because the counter, not
      # the bundle, supplies the uniqueness (CallKey.mint, Task 7).
      NONE = build(
        trace_id: TraceIdFlavour::NONE.invalid_trace_id,
        span_id: INVALID_SPAN_ID,
        flavour: TraceIdFlavour::NONE,
      )
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/instrumentation/bundle.rbs`**

```rbs
module Dexpace
  module Instrumentation
    class Bundle
      include Dexpace::Model

      INVALID_SPAN_ID: String

      attr_reader trace_id: String
      attr_reader span_id: String
      attr_reader trace_flags: String
      attr_reader trace_state: Array[[String, String]]
      attr_reader flavour: TraceIdFlavour
      attr_reader remote: bool
      attr_reader span: _Span
      attr_reader tracer_factory: _TracerFactory

      NONE: Bundle

      def self.build: (
        trace_id: String, span_id: String, flavour: TraceIdFlavour,
        ?trace_flags: String, ?trace_state: Array[[String, String]], ?remote: bool,
        ?span: _Span, ?tracer_factory: _TracerFactory,
      ) -> Bundle

      def valid?: () -> bool
      def remote?: () -> bool

      def ==: (untyped other) -> bool
      def eql?: (untyped other) -> bool
      def hash: () -> Integer
      def to_h: () -> Hash[Symbol, untyped]
      def with: (**untyped changes) -> Bundle
    end
  end
end
```

- [ ] **Step 5: Add the require to `lib/dexpace.rb`**

After Task 5's lines: `require_relative "dexpace/instrumentation/bundle"`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/bundle_test.rb`
Expected: PASS, 12 runs. Verified: 12 runs, 63 assertions on 3.2.11 and 3.4.10; 72 on 4.0.6
(Minitest artifact — every `assert_raises` block contributes one extra assertion under 6.0.0).

- [ ] **Step 7: Confirm `rbs validate` accepts the four `.rbs` files written so far**

Run: `rbs -I sig validate` from `gems/dexpace-core/`.
Expected: exits clean once phase 1's and phase 2's own `sig/` files are present (which they are,
by this point in the real repository). Verified on this plan's scratch tree — with stand-in
`.rbs` files for `Dexpace::Model`, `Dexpace::Error`, `Dexpace::InvalidArgumentError`,
`Dexpace::Request` and `Dexpace::Response` reproducing phase 1's shapes — that the full sig tree
this phase adds (`context.rbs`, `context_store.rbs`, `error/context_conflict_error.rbs`,
`instrumentation/trace_id_flavour.rbs`, `no_span.rbs`, `no_tracer.rbs`, `bundle.rbs`, plus Task 7's
three below) validates with **no output and exit 0** on `rbs` 3.8.0.

---

## Task 7: `Dexpace::CallKey` and the promotion chain

**Requirement IDs:** `CTX-1`, `CTX-2`, `CTX-3`, `CTX-4`, `CTX-5`, `CTX-6`, `CTX-9` (the trap,
added here), `CTX-15` (the non-trivial half), `CTX-16`, `CTX-17`. **Design:** "R2 — the call key";
`DispatchContext`/`RequestContext`/`ExchangeContext` sections.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/context/call_key.rb`,
  `gems/dexpace-core/lib/dexpace/context/dispatch_context.rb`,
  `gems/dexpace-core/lib/dexpace/context/request_context.rb`,
  `gems/dexpace-core/lib/dexpace/context/exchange_context.rb`,
  `gems/dexpace-core/sig/dexpace/context/{dispatch_context,request_context,exchange_context}.rbs`
- Modify: `gems/dexpace-core/test/dexpace/context_store_test.rb` (adds the `CTX-9` trap)
- Test: `gems/dexpace-core/test/dexpace/context/{dispatch_context,request_context,exchange_context}_test.rb`

**Interfaces:**
- Consumes: Task 2's `Dexpace::Context`, Task 3's `Dexpace::ContextStore`, Task 6's `Bundle`.
- Produces: `Dexpace::DispatchContext.build(bundle:, call_key: nil, store: ContextStore.default)`,
  `#promote_to_request(request:, operation_name: nil)`;
  `Dexpace::RequestContext.build(bundle:, request:, operation_name: nil, call_key: nil, store:
  ContextStore.default)`, `#promote_to_exchange(response:)`;
  `Dexpace::ExchangeContext.build(bundle:, request:, response:, operation_name: nil, call_key:
  nil, store: ContextStore.default)`, no promotion method. `Dexpace::CallKey` is `private_constant`.

- [ ] **Step 1: Write the failing tests**

`dispatch_context_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CTX-1 (the head of the chain), CTX-2, CTX-4, CTX-5, CTX-6, CTX-7, CTX-15, CTX-17.
class DexpaceDispatchContextTest < DexpaceTestCase
  # The untraced bundle every case in this file builds from (CTX-15).
  NONE = Dexpace::Instrumentation::Bundle::NONE

  test "CTX-5/CTX-6: two default-constructed contexts from the same bundle are NOT equal" do
    a = Dexpace::DispatchContext.build(bundle: NONE)
    b = Dexpace::DispatchContext.build(bundle: NONE)

    refute_equal(a, b)
    refute_operator(a, :eql?, b)
  end

  test "CTX-5: an explicit shared call_key restores value equality" do
    a = Dexpace::DispatchContext.build(bundle: NONE, call_key: "shared")
    b = Dexpace::DispatchContext.build(bundle: NONE, call_key: "shared")

    assert_equal(a, b)
    assert_operator(a, :eql?, b)
    assert_equal(a.hash, b.hash)
  end

  test "CTX-15: minting from the SAME Bundle::NONE object still yields distinct keys" do
    bundle = NONE
    a = Dexpace::DispatchContext.build(bundle: bundle)
    b = Dexpace::DispatchContext.build(bundle: bundle)

    assert_same(bundle, a.bundle)
    assert_same(bundle, b.bundle)
    refute_equal(a.call_key, b.call_key)
  end

  # One counter serves all three flavours: CTX-6 requires distinctness "across the whole
  # process and across all three context flavors", not across a store.
  test "CTX-6: three flavours built from one untraced bundle get three distinct keys" do
    bundle = NONE
    keys = [
      Dexpace::DispatchContext.build(bundle: bundle).call_key,
      Dexpace::RequestContext.build(bundle: bundle, request: :req).call_key,
      Dexpace::ExchangeContext.build(bundle: bundle, request: :req, response: :resp).call_key,
    ]

    assert_equal(3, keys.uniq.size)
  end

  test "CTX-17: constructing a dispatch context registers nothing" do
    store = Dexpace::ContextStore.new(cap: 8)
    ctx = Dexpace::DispatchContext.build(bundle: NONE, store: store)

    assert_equal(0, store.size)
    assert_nil(store[ctx.call_key])
  end

  test "CTX-17: a dispatch context never promoted closes as a harmless no-op" do
    store = Dexpace::ContextStore.new(cap: 8)
    ctx = Dexpace::DispatchContext.build(bundle: NONE, store: store)

    refute(ctx.close)
  end

  test "CTX-2: promotion is additive, non-mutating, and carries members forward by identity" do
    store = Dexpace::ContextStore.new(cap: 8)
    source = Dexpace::DispatchContext.build(bundle: NONE, store: store)
    request = :the_request

    promoted = source.promote_to_request(request: request)

    assert_same(source.bundle, promoted.bundle)
    assert_same(source.call_key, promoted.call_key)
    assert_same(request, promoted.request)
    refute_respond_to(source, :request)
  end

  test "CTX-17: the first promotion is the first store entry the chain ever has" do
    store = Dexpace::ContextStore.new(cap: 8)
    source = Dexpace::DispatchContext.build(bundle: NONE, store: store)

    assert_equal(0, store.size)
    promoted = source.promote_to_request(request: :req)

    assert_equal(1, store.size)
    assert_same(promoted, store[source.call_key])
  end

  # CTX-7's first clause -- "Contexts MUST be immutable and safe to share across threads without
  # external synchronization" -- which Data supplies and which nothing else in this suite asserts.
  test "CTX-7: every context flavour is frozen on construction" do
    bundle = NONE
    store = Dexpace::ContextStore.new(cap: 8)
    dispatch = Dexpace::DispatchContext.build(bundle: bundle, store: store)
    request = dispatch.promote_to_request(request: :req)

    assert_predicate(dispatch, :frozen?)
    assert_predicate(request, :frozen?)
    assert_predicate(request.promote_to_exchange(response: :resp), :frozen?)
  end

  # CTX-4's key is a frozen String on both paths: minted, and pinned by a caller. Verified fact 12
  # -- a frozen String is stored as a Hash key by identity, an unfrozen one is copied and frozen on
  # every registration -- so this is correctness and one fewer allocation per promotion.
  test "CTX-4: the call key is a frozen String whether it is minted or pinned" do
    bundle = NONE
    pinned = +"shared"

    assert_predicate(Dexpace::DispatchContext.build(bundle: bundle).call_key, :frozen?)

    ctx = Dexpace::DispatchContext.build(bundle: bundle, call_key: pinned)

    assert_predicate(ctx.call_key, :frozen?)
    refute_same(pinned, ctx.call_key)
  end

  test "there is no reverse promotion: DispatchContext has no #promote_to_dispatch" do
    refute_respond_to(
      Dexpace::DispatchContext.build(bundle: NONE), :promote_to_dispatch,
    )
  end
end
```

`request_context_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CTX-2 (request -> exchange half), CTX-16.
class DexpaceRequestContextTest < DexpaceTestCase
  # The untraced bundle every case in this file builds from (CTX-15).
  NONE = Dexpace::Instrumentation::Bundle::NONE

  test "CTX-2: request -> exchange carries every source member forward by identity" do
    store = Dexpace::ContextStore.new(cap: 8)
    request = :the_request
    source = Dexpace::RequestContext.build(
      bundle: NONE, request: request,
      operation_name: "GetUser", store: store,
    )
    response = :the_response

    promoted = source.promote_to_exchange(response: response)

    assert_same(source.bundle, promoted.bundle)
    assert_same(source.call_key, promoted.call_key)
    assert_same(source.request, promoted.request)
    assert_same(source.operation_name, promoted.operation_name)
    assert_same(response, promoted.response)
  end

  test "CTX-3: the promotion overwrites the same store slot" do
    store = Dexpace::ContextStore.new(cap: 8)
    dispatch = Dexpace::DispatchContext.build(bundle: NONE, store: store)
    request_ctx = dispatch.promote_to_request(request: :req)

    assert_equal(1, store.size)

    exchange_ctx = request_ctx.promote_to_exchange(response: :resp)

    assert_equal(1, store.size)
    assert_same(exchange_ctx, store[dispatch.call_key])
  end

  # CTX-16's advisory rule, asserted as a negative: the operation name influences none of the
  # three things it is forbidden from influencing.
  test "CTX-16: operation_name changes neither the call key, the request, nor the slot" do
    store = Dexpace::ContextStore.new(cap: 8)
    request = :shared_request
    dispatch_a = Dexpace::DispatchContext.build(
      bundle: NONE, call_key: "shared", store: store,
    )
    dispatch_b = Dexpace::DispatchContext.build(
      bundle: NONE, call_key: "shared", store: store,
    )

    named = dispatch_a.promote_to_request(request: request, operation_name: "GetUser")
    unnamed = dispatch_b.promote_to_request(request: request)

    assert_equal(named.call_key, unnamed.call_key)
    assert_same(named.request, unnamed.request)
    assert_same(unnamed, store["shared"])
  end

  test "CTX-16: operation_name is carried forward unchanged across promotion" do
    store = Dexpace::ContextStore.new(cap: 8)
    source = Dexpace::RequestContext.build(
      bundle: NONE, request: :req,
      operation_name: "GetUser", store: store,
    )

    promoted = source.promote_to_exchange(response: :resp)

    assert_same(source.operation_name, promoted.operation_name)
  end

  test "operation_name may be absent" do
    ctx = Dexpace::RequestContext.build(bundle: NONE, request: :req)

    assert_nil(ctx.operation_name)
  end

  # CTX-16 gives exactly two states -- "GetUser", or absent -- and "" is neither.
  test "an empty operation_name is rejected" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::RequestContext.build(
        bundle: NONE, request: :req, operation_name: "",
      )
    end
  end

  test "there is no reverse promotion: RequestContext has no #promote_to_dispatch" do
    refute_respond_to(
      Dexpace::RequestContext.build(bundle: NONE, request: :req),
      :promote_to_dispatch,
    )
  end
end
```

`exchange_context_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CTX-1: the exchange stage is terminal. Conformance: the exchange type exposes no method
# promoting back.
class DexpaceExchangeContextTest < DexpaceTestCase
  # The untraced bundle every case in this file builds from (CTX-15).
  NONE = Dexpace::Instrumentation::Bundle::NONE

  test "CTX-1: ExchangeContext defines no promotion method at all" do
    ctx = Dexpace::ExchangeContext.build(
      bundle: NONE, request: :req, response: :resp,
    )

    refute_respond_to(ctx, :promote_to_request)
    refute_respond_to(ctx, :promote_to_exchange)
    refute_respond_to(ctx, :promote_to_dispatch)
    assert_empty(Dexpace::ExchangeContext.public_instance_methods(false).grep(/\Apromote_to_/))
  end

  test "an empty operation_name is rejected" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::ExchangeContext.build(
        bundle: NONE, request: :req, response: :resp,
        operation_name: "",
      )
    end
  end

  test "CTX-18: #close on an exchange context evicts it when it is the current occupant" do
    store = Dexpace::ContextStore.new(cap: 8)
    dispatch = Dexpace::DispatchContext.build(bundle: NONE, store: store)
    exchange = dispatch.promote_to_request(request: :req).promote_to_exchange(response: :resp)

    assert(exchange.close)
    assert_nil(store[dispatch.call_key])

    refute(exchange.close)
  end
end
```

Add to the **top** of `context_store_test.rb` (Task 3's file), inside the class, the `CTX-9` trap
that needed a real `Data` context to be constructible:

```ruby
  # THE trap. Two contexts equal by value and distinct by identity are constructible only with a
  # pinned explicit call_key (CTX-5's escape hatch) -- FakeContext has no value equality at all
  # (plain Object#==), so this is the one case in the suite that needs a real Data context.
  test "CTX-9: release evicts only the reference-identical occupant, never a value-equal sibling" do
    store = Dexpace::ContextStore.new(cap: 8)
    bundle = Dexpace::Instrumentation::Bundle::NONE
    first = Dexpace::DispatchContext.build(bundle: bundle, call_key: "shared", store: store)
    second = Dexpace::DispatchContext.build(bundle: bundle, call_key: "shared", store: store)

    assert_equal(first, second)
    refute_same(first, second)

    store.set(first)

    refute(store.release(second))
    assert_same(first, store[first.call_key])

    assert(store.release(first))
    assert_nil(store[first.call_key])
  end
```

- [ ] **Step 2: Run them all to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/context/dispatch_context_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::DispatchContext`. Same shape for
`request_context_test.rb`, `exchange_context_test.rb`, and the added `CTX-9` test in
`context_store_test.rb` (which fails with `NoMethodError` or `uninitialized constant` depending on
where `DispatchContext` is referenced).

- [ ] **Step 3: Write `lib/dexpace/context/call_key.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # CTX-4's default key generator: a process-wide, monotonically increasing counter appended to a
  # 'traceId:spanId' rendering. Not public: CTX-4 says outright that "the exact format and the
  # counter mechanism are a reference choice, and a port MAY key differently". The public surface
  # is #call_key on a context, a frozen String.
  #
  # One Thread::Mutex, one Integer, incremented under the lock and read nowhere else -- a counter
  # on a ContextStore instance would mint colliding keys the moment a second store exists, and
  # CTX-6 requires distinctness "across the whole process and across all three context flavors",
  # not across a store. Ruby's Integer never overflows, so no wrap handling is needed.
  module CallKey
    @mutex = ::Thread::Mutex.new
    @counter = 0

    def self.mint(bundle)
      n = @mutex.synchronize { @counter += 1 }
      "#{bundle.trace_id}:#{bundle.span_id}:#{n}".freeze
    end
  end
  private_constant :CallKey
end
```

- [ ] **Step 4: Write the three context flavour files**

`lib/dexpace/context/dispatch_context.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../context"
require_relative "../context_store"
require_relative "call_key"
require_relative "request_context"

module Dexpace
  # CTX-1, CTX-2, CTX-5, CTX-17. The chain's head: before any request exists.
  class DispatchContext < Data.define(:bundle, :call_key, :store)
    include Dexpace::Context
    private_class_method :new

    # CTX-5's off-chain construction, with its explicit-key affordance and its minting default.
    # Construction registers nothing (CTX-17): the first store entry a chain ever has is installed
    # by the first promotion, below.
    def self.build(bundle:, call_key: nil, store: ContextStore.default)
      key = call_key.nil? ? CallKey.mint(bundle) : Model.frozen_string(call_key)
      new(bundle: bundle, call_key: key, store: store)
    end

    def initialize(bundle:, call_key:, store:)
      Dexpace::Context.validate!(bundle: bundle, call_key: call_key, store: store)

      super
    end

    # -> RequestContext. Carries forward the SAME bundle object, the SAME call_key and the SAME
    # store (CTX-2, CTX-3); introduces operation_name as an argument, exactly as CTX-2 requires;
    # registers the successor with store.set before returning it -- the first store entry the
    # chain ever has (CTX-17).
    def promote_to_request(request:, operation_name: nil)
      ctx = RequestContext.build(
        bundle: bundle, call_key: call_key, store: store,
        request: request, operation_name: operation_name,
      )
      store.set(ctx)
    end
  end
end
```

`lib/dexpace/context/request_context.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../context"
require_relative "../context_store"
require_relative "call_key"
require_relative "exchange_context"

module Dexpace
  # CTX-2, CTX-16. The chain's middle: an outgoing request has been assembled.
  class RequestContext < Data.define(:bundle, :call_key, :store, :request, :operation_name)
    include Dexpace::Context
    private_class_method :new

    # rubocop:disable Metrics/ParameterLists -- every parameter is a keyword (api-design/1d9e6e0b)
    # and the cop counts keywords; the member set is the design's, not a signature this phase chose.
    def self.build(bundle:, request:, operation_name: nil, call_key: nil,
                   store: ContextStore.default)
      key = call_key.nil? ? CallKey.mint(bundle) : Model.frozen_string(call_key)
      new(
        bundle: bundle, call_key: key, store: store, request: request,
        operation_name: operation_name.nil? ? nil : Model.frozen_string(operation_name),
      )
    end

    def initialize(bundle:, call_key:, store:, request:, operation_name:)
      Dexpace::Context.validate!(bundle: bundle, call_key: call_key, store: store)
      Model.required!("request", request)
      if !operation_name.nil? && operation_name.empty?
        raise InvalidArgumentError, "operation_name must not be empty"
      end

      super
    end
    # rubocop:enable Metrics/ParameterLists

    # -> ExchangeContext. Carries bundle, call_key, store, request and operation_name forward
    # unchanged (CTX-2's "additionally the same request and operationName"); adds the response;
    # calls store.set, which overwrites the same slot (CTX-3).
    def promote_to_exchange(response:)
      ctx = ExchangeContext.build(
        bundle: bundle, call_key: call_key, store: store,
        request: request, operation_name: operation_name, response: response,
      )
      store.set(ctx)
    end
  end
end
```

`lib/dexpace/context/exchange_context.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../context"
require_relative "../context_store"
require_relative "call_key"

module Dexpace
  # CTX-1, CTX-2. The chain's terminus: a response has arrived. No #promote_* method anywhere in
  # this class -- CTX-1's terminality is the absence.
  class ExchangeContext < Data.define(
    :bundle, :call_key, :store, :request, :operation_name, :response,
  )
    include Dexpace::Context
    private_class_method :new

    # rubocop:disable Metrics/ParameterLists -- every parameter is a keyword (api-design/1d9e6e0b)
    # and the cop counts keywords; the member set is the design's, not a signature this phase chose.
    def self.build(bundle:, request:, response:, operation_name: nil, call_key: nil,
                   store: ContextStore.default)
      key = call_key.nil? ? CallKey.mint(bundle) : Model.frozen_string(call_key)
      new(
        bundle: bundle, call_key: key, store: store, request: request,
        operation_name: operation_name.nil? ? nil : Model.frozen_string(operation_name),
        response: response,
      )
    end

    def initialize(bundle:, call_key:, store:, request:, operation_name:, response:)
      Dexpace::Context.validate!(bundle: bundle, call_key: call_key, store: store)
      Model.required!("request", request)
      Model.required!("response", response)
      if !operation_name.nil? && operation_name.empty?
        raise InvalidArgumentError, "operation_name must not be empty"
      end

      super
    end
    # rubocop:enable Metrics/ParameterLists
  end
end
```

Ruby resolves `RequestContext`/`ExchangeContext` at call time, not at file-load time, so
`dispatch_context.rb` and `request_context.rb` `require_relative`ing forward to files that in turn
`require_relative` back is not a cycle: each `require_relative` is a no-op the second time a file
is already loaded, and no constant is referenced until a test calls a `#promote_*` method, by
which point `lib/dexpace.rb`'s full require chain has already run.

- [ ] **Step 5: Write the three `sig/` mirrors**

`sig/dexpace/context/dispatch_context.rbs`:

```rbs
module Dexpace
  class DispatchContext
    include Context

    attr_reader bundle: Instrumentation::Bundle
    attr_reader call_key: String
    attr_reader store: untyped

    def self.build: (bundle: Instrumentation::Bundle, ?call_key: String?, ?store: untyped) -> DispatchContext

    def promote_to_request: (request: Dexpace::Request, ?operation_name: String?) -> RequestContext

    def ==: (untyped other) -> bool
    def eql?: (untyped other) -> bool
    def hash: () -> Integer
    def to_h: () -> Hash[Symbol, untyped]
    def with: (**untyped changes) -> DispatchContext
  end
end
```

`sig/dexpace/context/request_context.rbs`:

```rbs
module Dexpace
  class RequestContext
    include Context

    attr_reader bundle: Instrumentation::Bundle
    attr_reader call_key: String
    attr_reader store: untyped
    attr_reader request: Dexpace::Request
    attr_reader operation_name: String?

    def self.build: (
      bundle: Instrumentation::Bundle, request: Dexpace::Request,
      ?operation_name: String?, ?call_key: String?, ?store: untyped,
    ) -> RequestContext

    def promote_to_exchange: (response: Dexpace::Response) -> ExchangeContext

    def ==: (untyped other) -> bool
    def eql?: (untyped other) -> bool
    def hash: () -> Integer
    def to_h: () -> Hash[Symbol, untyped]
    def with: (**untyped changes) -> RequestContext
  end
end
```

`sig/dexpace/context/exchange_context.rbs`:

```rbs
module Dexpace
  class ExchangeContext
    include Context

    attr_reader bundle: Instrumentation::Bundle
    attr_reader call_key: String
    attr_reader store: untyped
    attr_reader request: Dexpace::Request
    attr_reader operation_name: String?
    attr_reader response: Dexpace::Response

    def self.build: (
      bundle: Instrumentation::Bundle, request: Dexpace::Request, response: Dexpace::Response,
      ?operation_name: String?, ?call_key: String?, ?store: untyped,
    ) -> ExchangeContext

    def ==: (untyped other) -> bool
    def eql?: (untyped other) -> bool
    def hash: () -> Integer
    def to_h: () -> Hash[Symbol, untyped]
    def with: (**untyped changes) -> ExchangeContext
  end
end
```

`store:`'s RBS type is `untyped` rather than `ContextStore` in all three: `Context.validate!`
accepts any object responding to `#set`/`#release` (the narrowest duck type, `api-design/88e6bf12`),
and `FakeContext` in Task 2/3's suite relies on that; typing it `ContextStore` in `sig/` would be
narrower than what the runtime actually accepts and would fail `steep check` against the suite's
own fakes once the fixture files are added to a Steep target.

- [ ] **Step 6: Add the requires to `lib/dexpace.rb`**

After Task 6's line, in order: `require_relative "dexpace/context/call_key"`, then
`require_relative "dexpace/context/exchange_context"`, then
`require_relative "dexpace/context/request_context"`, then
`require_relative "dexpace/context/dispatch_context"` — innermost first, matching the pattern each
file's own `require_relative`s already impose (a file requires what it names before it is named
by its own caller).

- [ ] **Step 7: Run every test in this task to confirm they pass**

Run each of the three new files plus the modified `context_store_test.rb`:

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/context/dispatch_context_test.rb
bundle exec ruby -w gems/dexpace-core/test/dexpace/context/request_context_test.rb
bundle exec ruby -w gems/dexpace-core/test/dexpace/context/exchange_context_test.rb
bundle exec ruby -w gems/dexpace-core/test/dexpace/context_store_test.rb
```

Expected: PASS, 11 / 7 / 3 / 14 runs respectively. Verified on this plan's scratch tree: 11 runs,
26 assertions (3.2.11/3.4.10), 33 (4.0.6); 7 runs, 15 assertions (all three, no composite
assertions here beyond the one `assert_raises`, which nets to +0 on this file specifically —
verified directly, not assumed); 3 runs, 9 assertions (all three); 14 runs, 96 assertions (all
three — this file's own composite assertions are dwarfed by its many plain ones, so the
Minitest-version delta does not show at this file's scale... **this claim licenses nothing beyond
this specific 14-test file**; do not generalise it to other files, several of which do show the
delta, as Steps 6/7 above and Task 6's Step 6 record).

- [ ] **Step 8: Run the whole gem suite together, five seeds, three interpreters**

```bash
mise exec ruby@3.2.11 -- bundle exec rake test:gems
bundle exec rake test:gems   # 3.4.10, the development interpreter
mise exec ruby@4.0.6 -- bundle exec rake test:gems
```

Expected: PASS on every row. Verified directly on this plan's own scratch tree (all files from
Tasks 1–7 loaded together via a single runner, `ruby -w` with `RUBYOPT=-W:deprecated`, seeds 1, 2,
3, 42, 12345):

```
3.2.11: 67 runs, 327 assertions, 0 failures, 0 errors, 0 skips   (all five seeds identical)
3.4.10: 67 runs, 327 assertions, 0 failures, 0 errors, 0 skips   (all five seeds identical)
4.0.6:  67 runs, 345 assertions, 0 failures, 0 errors, 0 skips   (all five seeds identical)
```

The seed has no effect on any of these counts because every thread count, cap and sample count in
this phase's suite is a literal; `sample(seed:)`'s own two uses (`trace_id_flavour_test.rb`,
`bundle_test.rb`) pin their own seed (`20_260_908`) rather than inheriting Minitest's `--seed`, per
`testing/7ece0212`.

---

## Task 8: `Dexpace/NoWeakReferences`, the seventh cop

**Requirement IDs:** `CTX-19`'s prohibition, mechanised. **Design:** "R1 — `CTX-19`'s
weak-reference prohibition, resolved."

**Files:**
- Create: `.rubocop/cops/dexpace/no_weak_references.rb`
- Modify: `.rubocop/test/cops_test.rb`, `.rubocop.yml`
- Test: cases added to `.rubocop/test/cops_test.rb`'s existing `REJECTED`/`ACCEPTED` tables

**Interfaces:**
- Consumes: phase 0's `CopCase` harness (`.rubocop/test/cop_case.rb`, unmodified).
- Produces: `RuboCop::Cop::Dexpace::NoWeakReferences`, wired into `.rubocop.yml`'s `require:` list
  and given `Include: ["gems/*/lib/**/*.rb"]` — every gem, not core alone, because
  `gates:require_allowlist` covers only core's `lib/`.

- [ ] **Step 1: Write the failing cop cases**

Add to `.rubocop/test/cops_test.rb`'s `REJECTED` array (the existing five cops' rows are
unmodified):

```ruby
    # CTX-19: RuboCop parses and never evaluates, so ObjectSpace::WeakKeyMap is a valid row even
    # though the constant is undefined on the 3.2.11 floor -- verified against
    # RuboCop::ProcessedSource.new(source, 3.2, path) on RuboCop 1.90.0.
    [D::NoWeakReferences, "ObjectSpace::WeakMap.new\n", "CTX-19"],
    [D::NoWeakReferences, "ObjectSpace::WeakKeyMap.new\n", "CTX-19"],
    [D::NoWeakReferences, "::ObjectSpace::WeakKeyMap.new\n", "CTX-19"],
    [D::NoWeakReferences,
     "module ObjectSpace\n  class Foo\n    def initialize\n      @m = WeakMap.new\n    end\n  end\nend\n",
     "CTX-19"],
    [D::NoWeakReferences, "WeakRef.new(ctx)\n", "CTX-19"],
    [D::NoWeakReferences, "::WeakRef.new(ctx)\n", "CTX-19"],
    [D::NoWeakReferences, "require \"weakref\"\n", "CTX-19"],
    # The line the rule exists to stop.
    [D::NoWeakReferences,
     "module Dexpace\n  class ContextStore\n    def initialize\n      @map = ObjectSpace::WeakKeyMap.new\n    end\n  end\nend\n",
     "CTX-19"],
```

Add to the `ACCEPTED` array (a plain array of `[cop, source]` pairs elsewhere in the same file —
match the existing five cops' `ACCEPTED` shape):

```ruby
    [D::NoWeakReferences, "ObjectSpace.count_objects\n"],
    [D::NoWeakReferences, "ObjectSpace.each_object { |o| o }\n"],
    [D::NoWeakReferences, "# ObjectSpace::WeakMap is banned here\n"],
    [D::NoWeakReferences, "weak_map = {}\n"],
    [D::NoWeakReferences, "def weak_ref\nend\n"],
    [D::NoWeakReferences,
     "module Dexpace\n  class ContextStore\n    def initialize\n      @h = Hash.new\n    end\n  end\nend\n"],
    [D::NoWeakReferences, "require \"set\"\n"],
    # The scoping the bare-name matcher depends on: a bare WeakMap/WeakKeyMap outside
    # `module ObjectSpace` names something else and is not this cop's business.
    [D::NoWeakReferences, "module Dexpace\n  def self.build\n    WeakMap.new\n  end\nend\n"],
    [D::NoWeakReferences,
     "module Dexpace\n  module Store\n    def self.of\n      WeakKeyMap.of\n    end\n  end\nend\n"],
```

- [ ] **Step 2: Run the cop suite to confirm the new rows fail**

Run: `bundle exec rake cops:test`
Expected: FAIL — `uninitialized constant RuboCop::Cop::Dexpace::NoWeakReferences`.

- [ ] **Step 3: Write `.rubocop/cops/dexpace/no_weak_references.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # CTX-19: "reimplementations MUST NOT hold contexts by weak/soft references ... and MUST
      # treat the bounded cap (CTX-11), not garbage collection, as the leak backstop." A
      # source-text cop rather than a runtime check, because RuboCop parses and never evaluates:
      # this table's rejected rows include ObjectSpace::WeakKeyMap, which is UNDEFINED on the
      # 3.2.11 floor -- verified that RuboCop::ProcessedSource.new(source, 3.2, path) on RuboCop
      # 1.90.0 reports valid_syntax? true and yields the const nodes this cop matches on for every
      # row below.
      #
      # Scoped to gems/*/lib/**/*.rb in .rubocop.yml, not to dexpace-core alone: an adapter gem is
      # as capable of "helping the collector" as core is. `require "weakref"` is redundant inside
      # dexpace-core, where gates:require_allowlist already rejects it, and is not redundant
      # anywhere else -- the allowlist covers core's lib/ alone.
      class NoWeakReferences < Base
        MSG = "`%<offender>s` is forbidden: a context must not be held by a weak reference " \
              "(CTX-19); the bounded cap (CTX-11) is the leak backstop."

        RESTRICT_ON_SEND = %i[require].freeze
        WEAK_MAP_NAMES = %i[WeakMap WeakKeyMap].freeze

        # @!method object_space_weak_map?(node)
        def_node_matcher :object_space_weak_map?, <<~PATTERN
          (const (const {nil? cbase} :ObjectSpace) {:WeakMap :WeakKeyMap})
        PATTERN

        # @!method weak_ref_const?(node)
        def_node_matcher :weak_ref_const?, "(const {nil? cbase} :WeakRef)"

        # @!method weakref_require?(node)
        def_node_matcher :weakref_require?, <<~PATTERN
          (send nil? :require (str "weakref"))
        PATTERN

        def on_const(node)
          return unless object_space_weak_map?(node) || weak_ref_const?(node) ||
                        bare_weak_map_inside_object_space?(node)

          add_offense(node, message: format(MSG, offender: node.source))
        end

        def on_send(node)
          return unless weakref_require?(node)

          add_offense(node, message: format(MSG, offender: node.source))
        end

        private

        # `WeakMap`/`WeakKeyMap` written bare, lexically inside `module ObjectSpace`. RuboCop
        # parses and never evaluates, so this fires on the source text regardless of whether the
        # constant would resolve at runtime.
        def bare_weak_map_inside_object_space?(node)
          return false unless node.namespace.nil? && WEAK_MAP_NAMES.include?(node.short_name)

          node.each_ancestor(:module).any? do |mod|
            mod.identifier.const_type? && mod.identifier.short_name == :ObjectSpace
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Register the cop in `.rubocop.yml`**

Add the file to the existing `require:` list alongside phase 0's five and phase 2's sixth, then the
cop's own entry:

```yaml
# CTX-19: "reimplementations MUST NOT hold contexts by weak/soft references". Scoped to every
# gem's lib/, not core alone -- an adapter gem is as capable of this mistake as core is.
Dexpace/NoWeakReferences:
  Enabled: true
  Include:
    - "gems/*/lib/**/*.rb"
```

- [ ] **Step 5: Run the cop suite to confirm it passes**

Run: `bundle exec rake cops:test`
Expected: PASS, with the eight rejected sources each producing exactly one offense naming
`CTX-19` and the nine accepted sources producing none.

**Verified on this plan's own scratch tree, against RuboCop 1.90.0**, using phase 0's verbatim
`CopCase` harness (`RuboCop::ProcessedSource.new(source, 3.2, path)`, `RuboCop::Cop::Commissioner`):

```
17 runs, 50 assertions, 0 failures, 0 errors, 0 skips
```

on 3.4.10 — the only interpreter in this planning environment with RuboCop installed, which per
this plan's earlier note is exactly the row that matters, because `TARGET_RUBY = 3.2` inside
`CopCase` pins the parse target independent of which interpreter runs the RuboCop process itself.
**This run licenses the cop's behaviour against RuboCop 1.90.0 specifically; if the real repository's
`VERSIONS` file pins a different RuboCop release, re-run this suite against that version and fix
the cop against it rather than weakening a case** — phase 2's own stated rule for its sixth cop.

- [ ] **Step 6: Run RuboCop over the repository**

Run: `bundle exec rubocop --fail-level=convention`
Expected: `Dexpace/NoWeakReferences` reports 0 offenses over every `lib/` tree this phase adds.
Per `OI-6` (filed by phase 3a, still open), the whole-repository run is not expected to be clean
for reasons unrelated to this phase — this step's claim is scoped to this phase's own files, per
that item's own precedent.

---

## Task 9: Wiring, the two regenerated artifacts, and the phase record

**Requirement IDs:** `NFR-4`'s surface lock and `NFR-3`'s signature gate over everything Tasks
1–8 added. **Design:** "Module layout"; "The 20 IDs, with dispositions."

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace.rb` (verify the final require order),
  `test/fixtures/surface/dexpace-core.txt` (repository root), the `sig/**/*.rbs` baseline the API
  lock diffs against, `CLAUDE.md` (claims sentences, if what they must say has changed)
- Create: `docs/work/mvp/phase4/phase4a/2026-09-08-phase4a-execution-context-checklist.md`
  (**written at execution time, per this task — its content is not authored in this plan**)

**Interfaces:**
- Consumes: every task above.
- Produces: a green `bundle exec rake` on all four matrix rows, and the checklist mapping all 20
  `CTX` IDs to a task.

- [ ] **Step 1: Verify `lib/dexpace.rb`'s require order**

Each task added its own lines; this step confirms the result rather than writing it. The full
sequence this phase adds, after phase 2's last line:

```ruby
require_relative "dexpace/error/context_conflict_error" # Task 1
require_relative "dexpace/context" # Task 2
require_relative "dexpace/bounded_map" # Task 3
require_relative "dexpace/context_store" # Task 3
require_relative "dexpace/instrumentation/trace_id_flavour" # Task 4
require_relative "dexpace/instrumentation/no_span" # Task 5
require_relative "dexpace/instrumentation/no_tracer" # Task 5
require_relative "dexpace/instrumentation/bundle" # Task 6
require_relative "dexpace/context/call_key" # Task 7
require_relative "dexpace/context/exchange_context" # Task 7
require_relative "dexpace/context/request_context" # Task 7
require_relative "dexpace/context/dispatch_context" # Task 7
```

`sig/dexpace.rbs` is unchanged: every constant this phase adds has its own file under `sig/`.

- [ ] **Step 2: Run the require-allowlist and gemspec audits**

Run: `bundle exec rake gates:require_allowlist gates:gemspec_audit gates:clean_bundle`
Expected: PASS, unchanged. This phase adds **no `require` of any kind beyond `require_relative`**
— `::Thread::Mutex`, `::Hash`, `::Data`, `::Regexp`, `::Fiber` are core Ruby, and nothing in this
phase touches `securerandom`, `weakref`, or any other allowlisted-or-not name.

- [ ] **Step 3: Regenerate the runtime surface snapshot**

Run: `bundle exec rake surface:regenerate`
Expected: `test/fixtures/surface/dexpace-core.txt` gains exactly these rows, and no others. **This
is not derived by reading the walker's source and reasoning about it — it was produced by loading
this phase's actual classes into a live interpreter and calling phase 0's own walker method,
`mod.public_instance_methods(false)`, exactly as `tools/surface.rb` (phase 0, Task 14) does**:

```
Dexpace::Context
Dexpace::Context# close
Dexpace::ContextConflictError
Dexpace::ContextConflictError# call_key
Dexpace::ContextStore
Dexpace::ContextStore# [] put release set size
Dexpace::ContextStore::MAX_TRACKED_CONTEXTS : Integer
Dexpace::DispatchContext
Dexpace::DispatchContext# promote_to_request
Dexpace::ExchangeContext
Dexpace::Instrumentation
Dexpace::Instrumentation::Bundle
Dexpace::Instrumentation::Bundle# remote? valid?
Dexpace::Instrumentation::Bundle::INVALID_SPAN_ID : String
Dexpace::Instrumentation::Bundle::NONE : Dexpace::Instrumentation::Bundle
Dexpace::Instrumentation::NO_SPAN : Dexpace::Instrumentation::NoSpan
Dexpace::Instrumentation::NO_TRACER : Dexpace::Instrumentation::NoTracer
Dexpace::Instrumentation::NO_TRACER_FACTORY : Dexpace::Instrumentation::NoTracerFactory
Dexpace::Instrumentation::TraceIdFlavour
Dexpace::Instrumentation::TraceIdFlavour# renders? valid_trace_id?
Dexpace::Instrumentation::TraceIdFlavour::ALL : Array
Dexpace::Instrumentation::TraceIdFlavour::DATADOG : Dexpace::Instrumentation::TraceIdFlavour
Dexpace::Instrumentation::TraceIdFlavour::NONE : Dexpace::Instrumentation::TraceIdFlavour
Dexpace::Instrumentation::TraceIdFlavour::W3C : Dexpace::Instrumentation::TraceIdFlavour
Dexpace::RequestContext
Dexpace::RequestContext# promote_to_exchange
```

(`Bundle::NONE`, `TraceIdFlavour::NONE`/`W3C`/`DATADOG`/`ALL` also appear in the real repository's
diff even though they hold no new class — the walker's `else` branch renders every
non-`Module` constant, typed by its value's class, and these are the ones this phase adds.)

**This table corrects an assumption `P4-11` states as settled, and that correction is filed as
`OI-19` below rather than silently written around.** `P4-11` (design, already committed) says: "The
`Data`-generated readers on all five value types … are public API too and are invisible to `rbs
validate`; the runtime surface snapshot is what holds them." **Verified directly against phase 0's
own walker method, on all three interpreters: it does not.** `mod.public_instance_methods(false)`
returns only methods defined **directly** on `mod` itself, and for `class DispatchContext <
Data.define(:bundle, :call_key, :store)`, the readers `bundle`, `call_key` and `store` are defined
on the **anonymous class `Data.define` returns**, which is `DispatchContext.superclass` — not on
`DispatchContext` itself:

```
Dexpace::DispatchContext.instance_methods(false)             # => [:promote_to_request]
Dexpace::DispatchContext.superclass.instance_methods(false)  # => [:bundle, :call_key, :store]
```

on 3.2.11, 3.4.10 and 4.0.6 alike. (Contrast: `Foo = Data.define(:a, :b) do; def extra; end; end`
— assigning the `Data.define` return **directly** to a constant, with a block, rather than
subclassing it — gives `Foo.instance_methods(false) == [:a, :b, :extra]` and `Foo.superclass ==
Data`, on all three. The difference is the subclassing idiom itself, not a Ruby-version fact.) This
repository's entire `Data`-based value-type convention, from phase 1 forward (`class Status <
Data.define(:code)`, and every one after it, including this phase's five), uses the subclassing
form — so **no `Data`-generated reader for any type in this codebase has ever appeared in a
regenerated runtime surface snapshot**, contrary to `P4-11`'s and `CLAUDE.md`'s stated rationale
for why the snapshot exists alongside the RBS diff ("Each catches what the other cannot see").
This phase's own snapshot above is the first case where that gap is visible end to end: not one of
`DispatchContext`'s, `RequestContext`'s, `ExchangeContext`'s, `Bundle`'s or `TraceIdFlavour`'s
`Data`-generated readers appears in it, and `#==`/`#eql?`/`#hash`/`#to_h` — the methods `Data`
itself defines — are absent from every one of those types' rows for the same underlying reason,
one level further up the ancestry. `#with` is the one apparent exception and is not one: it
appears exactly once in the whole manifest, as phase 1's `Dexpace::Model# with`, because `Model`
overrides `Data#with` (P1-4) and `Model` is itself a `Dexpace::` module the walker descends into
— so what the snapshot holds is `Model`'s definition, not any flavour's inherited copy.

`Dexpace::BoundedMap` and `Dexpace::CallKey` appear in **no** row: `private_constant` excludes
them from `Module#constants`, which is what the walker enumerates from (verified fact 6 in the
design). `NoSpan`, `NoTracer` and `NoTracerFactory` also do not get their own class rows — they
are `private_constant` too, and only the module-level constants that hold their frozen instances
(`NO_SPAN`, `NO_TRACER`, `NO_TRACER_FACTORY`) appear. `ExchangeContext` gets **no** `#` row at
all: it defines no method of its own beyond what `Data` and `Context` supply, neither of which
`public_instance_methods(false)` on `ExchangeContext` itself can see — which is, incidentally, a
second and independent rendering of `CTX-1`'s terminality: the type that ends the chain is the one
with no owned methods.

**`OI-19`, filed here.** *Title:* the runtime surface snapshot does not hold a `Data`-generated
reader for any type built with this repository's `class X < Data.define(...)` subclassing
convention, contrary to `P4-11`'s and `CLAUDE.md`'s stated rationale ("the RBS diff is paired with
a runtime surface snapshot … Each catches what the other cannot see"). *Why filed rather than
fixed:* `tools/surface.rb` is phase 0's file (Task 14), already committed and reviewed, and every
`Data`-based type since phase 1 is affected identically — this is not 4a's gap to fix, and fixing
it by walking `mod.superclass.instance_methods(false)` as well would change what a `sig_diff`-style
manifest asserts for **every** gem, which is a phase-0-owned decision. *What it means for `NFR-4` in
the meantime:* a `Data`-generated reader can be renamed or removed without the runtime snapshot
noticing (the RBS diff still catches it, since every reader is written out explicitly in `sig/`
per phase 1's own stated reason for doing so) — so `NFR-4`'s "each catches what the other cannot
see" is true for `sig_diff` against RBS omissions, but the runtime snapshot's contribution for a
`Data`-generated reader specifically is nothing, not a backstop. **This plan does not act on it
beyond filing it and stating the corrected expectation above** — acting on it (changing the walker)
is outside a sub-phase's remit over a phase-0-owned tool.

- [ ] **Step 4: Regenerate the RBS baseline and run the API lock**

Run: `bundle exec rake rbs:validate steep gates:sig_diff gates:rbs_surface`
Expected: PASS. `gates:rbs_surface` asserts that no constant outside `Dexpace::` and a fixed
stdlib allowlist appears in any public signature (`NFR-11`) — this phase's whole public surface
names only `String`, `Integer`, `Symbol`, `Regexp`, `Array`, `Hash`, `bool` and `untyped`, plus the
two empty interfaces `_Span`/`_Tracer` and the one-method `_TracerFactory`, none of which name an
external constant.

- [ ] **Step 5: Re-run the cop suite and RuboCop over the finished tree**

Run: `bundle exec rake cops:test` then `bundle exec rubocop --fail-level=convention`
Expected: `cops:test` PASS — one generated Minitest method per table row across all seven cops.
This phase contributes 17 of them (8 rejected, 9 accepted; 50 assertions), verified against
RuboCop 1.90.0; the total is whatever the live table holds once phase 0's and phase 2's rows are
counted with them, and is deliberately not asserted here. Also expected:
`Dexpace/NoWeakReferences` reporting 0 offenses over the finished tree. The whole-repository
RuboCop run inherits `OI-6`'s already-open caveat and is not re-litigated here.

- [ ] **Step 6: Run every gate on every matrix row**

Run: `bundle exec rake`, then `mise exec ruby@3.2.11 -- bundle exec rake test:gems` and the same
for 3.3 and 4.0. Expected: PASS. Three facts in this phase give a different answer on a single
interpreter and must be seen green on **every** row: `ObjectSpace::WeakKeyMap`'s absence on
3.2.11 (Task 3's Step 8 and Task 8's cop suite), the frozen-`Data`-ivar `FrozenError` (implicit in
every `.build` call on every row, since `initialize` runs on all three), and the Minitest
assertion-count artifact on 4.0.6 (every task above) — none of which is a failure, all of which
are stated rather than silently absorbed.

- [ ] **Step 7: Write the checklist**

`docs/work/mvp/phase4/phase4a/2026-09-08-phase4a-execution-context-checklist.md`, one row per
requirement ID, using the roadmap's ✅ / 🚫 / ⏳ / N/A legend verbatim. All twenty `CTX-1`–`CTX-20`
get a row, all ✅ — the design's own "Implemented — 20" disposition table names none as deferred,
and Tasks 1–8 above cover every one of them: `CTX-1`–`CTX-3`, `CTX-5`, `CTX-6`, `CTX-15`–`CTX-17`
(Task 7); `CTX-4` (Task 7's `CallKey`); `CTX-7`, `CTX-8`, `CTX-10`–`CTX-13`, `CTX-18` (Task 3, with
`CTX-9` completed in Task 7); `CTX-14` (Tasks 4–6); `CTX-19` (Tasks 3 and 8); `CTX-20` (Task 5).
This step is where the row-by-row table is actually written — not here, per this plan's own
"not a checklist" scope.

- [ ] **Step 8: Record what the phase decided, in the right place**

- **Deviations.** The design filed `P4-1` through `P4-11`; this plan adds none — open question 1's
  resolution (the richer five-parameter `#tracer` signature) is the concrete instance `P4-8`
  already anticipated ("The exact arity is confirmed against the gem in 4a's plan"), not a new
  departure from it.
- **Deferrals.** `DEF-36` and `DEF-37` were filed by the design; this plan files no new row. The
  register was read in full at the design stage and its sweep is not repeated here.
- **Open items.** `OI-13`, `OI-15`, `OI-16` were filed by the design and stay open; none is this
  plan's to close. This plan files **two** new items. `OI-20` (`docs/open-items.md`, and open
  question 5 above): the design's second discriminating drain measurement — "the maximum size ever
  observed" — is not reachable through `ContextStore`'s public surface, verified against a
  split-lock `BoundedMap` sampled by four concurrent `#size` readers across 64 000 inserts, so the
  one-`synchronize` insert-and-drain is held by review rather than by the suite; the same item
  carries the `Metrics/ParameterLists` / `CountKeywordArgs` tension the Global Constraints name,
  because both are things this phase measured and neither is a sub-phase's to settle. And `OI-19`
  (Step 3 above and `docs/open-items.md`): the runtime surface snapshot does not hold a `Data`-generated reader for
  any type using this repository's `class X < Data.define(...)` convention, contrary to `P4-11`'s
  and `CLAUDE.md`'s stated rationale for pairing it with the RBS diff — discovered while deriving
  this task's own expected snapshot content against phase 0's real walker rather than by
  inspection. It is filed, not fixed, because `tools/surface.rb` is phase 0's and every `Data`-based
  type in every gem is affected identically.
- **Release blockers.** None. Nothing is published and every gem stays at `0.0.0`.

- [ ] **Step 9: Update `CLAUDE.md`'s claims sentences if what they must say has changed**

Run: `ruby .claude/skills/housekeeping/probe.rb --only claims`

**No count changes and the probe stays green** — `phase4/` and `phase4a/` are already committed
directories and `CLAUDE.md` already reads "There are five phase directories under
`docs/work/*/`", naming `phase0` through `phase4`. What this plan's filing stales is a **clause**
the probe cannot see, because it carries no numeral: the same sentence ends "three sub-phase
directories — `phase4/phase4a/`, `phase4/phase4b/` and `phase4/phase4c/` — each holding that
sub-phase's design **with its plan still to be written**". Once this document lands, `phase4a/`
holds a design *and* a plan. The correction is to that clause and to nothing else; the probe's
`claims` check will not report it, which is exactly why it is named here. Per `CLAUDE.md`'s own
"never rewrite prose to satisfy a check" rule, the judgement about the wording belongs to whoever
lands the change — what this step fixes is that a previous draft of it pointed at a sentence that
had already been corrected.

---

## Self-review against the design

**Spec coverage.** All 20 `CTX` IDs have a task, and each is named in the header comment of at
least one test file that exercises it — including `CTX-4`, whose two clauses are asserted in
`dispatch_context_test.rb` (the key is call-unique across the same `Bundle::NONE`, and it is a
frozen `String` on both the minted and the pinned path) rather than only implied by `CallKey`'s
existence, and `CTX-7`, whose first clause — "Contexts MUST be immutable" — is asserted on all
three flavours and on `Bundle` rather than left to `Data`: `CTX-1` (Tasks 2, 7),
`CTX-2`/`CTX-3` (Task 7), `CTX-4` (Task 7), `CTX-5`/`CTX-6` (Task 7),
`CTX-7` (Tasks 3 and 7 — the store's concurrency half and the contexts' immutability half),
`CTX-8` (Task 3), `CTX-9` (Tasks 2, 3, 7),
`CTX-10` (Tasks 2, 3), `CTX-11`/`CTX-12`/`CTX-13` (Task 3), `CTX-14` (Tasks 4–6), `CTX-15` (Tasks
6, 7), `CTX-16` (Task 7), `CTX-17` (Task 7), `CTX-18` (Tasks 2, 3, 7), `CTX-19` (Tasks 3, 8),
`CTX-20` (Task 5). The design's "also fixed by 4a without owning a new ID" trio — the `Bundle`
shape (Task 6), the shared bounded map (Task 3), the process-wide counter (Task 7) — are covered.
The design's four open questions are resolved above, before Task 1, not deferred into a task, and
two the plan opened for itself are resolved beside them.

**Boundaries.** No task builds a pipeline stage, a recovery-chain outcome, a transport or a
socket. No task gives `Bundle` a tenth member, a stored `valid` field, or a second `NONE`. No task
adds `#sampled?` to `Bundle` or a `deadline:`/clock/cancellation anywhere — `DEF-28`/`DEF-36`
stay phase 5's. No task builds `OBS-21`–`OBS-25`'s span/tracer protocols beyond the one method
`CTX-20` forces — `DEF-37` stays phase 5's. No task touches `Fiber[:key]` as a write target — only
as a read-side boundary test (Task 3). No fourth registry, no `close_quietly` call site (a
context's `#close` cannot raise, per `CTX-18`), no `Dexpace::Closeable` inclusion anywhere.

**Type consistency.** `bundle:`, `call_key:`, `store:`, `request:`, `operation_name:`,
`response:` are the same keyword names in every `.build` across Tasks 6 and 7.
`#promote_to_request`/`#promote_to_exchange` are the only two promotion method names, used
identically in Task 7's implementation and its own tests. `Context.validate!(bundle:, call_key:,
store:)` is defined once in Task 2 and called with the identical keyword set from all three
flavours' `initialize` in Task 7. `CallKey.mint(bundle)` is called identically from all three
`.build` methods. `ContextStore#set`/`#put`/`#release` all take one `context` argument and read
`#call_key` off it, never a separate key parameter, in both Task 3's implementation and Task 7's
callers.

**Placeholder scan.** No "TBD", no "add appropriate error handling," no "similar to Task N"
standing in for code — every task's implementation is the complete, tested file.
