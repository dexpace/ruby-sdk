# Phase 4c — Stage-Based Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `dexpace-core`'s stage-based pipeline subsystem — sixteen totally ordered stages,
the step and entry models, single-use forward-only cursors with pillar-only forks and per-stage
scoped state, unified sync and async builder with surgical edits, sync `Pipeline` and async
`AsyncPipeline` runtimes conforming to the transport SPI without allocation on empty pipelines, the
4b `TransformStep` adapter, and `AsyncPipeline.map_response` — satisfying 37 requirement IDs in full
(`PIPE-1`–`PIPE-32`, `PIPE-34`, `PIPE-35`, `PIPE-37`, `PIPE-38`, `PIPE-40`), the non-interrupting
half of `PIPE-33` (with the interrupt clause deferred under `DEF-18`), `PIPE-36` deferred under
`DEF-4`, and the step-less half of `PIPE-39` (with the standard-resilience constructors deferred under
`DEF-39`).

**Architecture:** One module of sixteen stages (`Dexpace::Pipeline::Stages`) built on immutable
`Stage` values; a step protocol (`Dexpace::Pipeline::Step`) and entry value (`Dexpace::Pipeline::Entry`);
a single cursor class (`Dexpace::Pipeline::Cursor`) with per-runtime private drivers
(`SyncDriver` and `AsyncDriver`); a shared composition engine (`Dexpace::Pipeline::Builder`)
providing ordered append/prepend, surgical edits (`insert_after`, `insert_before`, `replace`,
`remove`), all-or-nothing reload and preset installation, and flattening/nesting seeding; two
pipeline runtimes (`Dexpace::Pipeline` and `Dexpace::AsyncPipeline`) conforming to the transport SPI
without allocation on empty pipelines; a generic adapter (`Dexpace::Pipeline::TransformStep`)
wrapping phase 4b's `Transform` contract; and one unified error type (`Dexpace::PipelineError`).

**Tech Stack:** Ruby 3.2–4.0 (development on 4.0.6), no runtime dependencies, Minitest, RBS +
Steep, RuboCop with phase 0's five custom cops, phase 2's sixth, and phase 4a's seventh, SimpleCov,
YARD.

**Spec:** `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md`, under the
charter `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md`. `docs/product-spec/08-execution-pipelines.md`
§8.1 and §8.3 are the normative chapters; `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md`
carries the canonical `PIPE` text quoted below.

## Global Constraints

- **`dexpace-core` gains no dependency and no allowlist entry.** The gemspec keeps zero
  `add_dependency` lines (`SEAM-1`, `NFR-1`). This phase adds **no `require` of any kind beyond
  `require_relative`** — `::Thread`, `::Array`, `::Hash`, `::Data`, `::ObjectSpace`, `::GC` are core Ruby.
  In particular, the LOGGING pillar is an architectural slot: core never `require`s `logger`, and the logging
  sink is a duck type (§8.1).
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`). No `# typed:` sigil
  anywhere (`notes/testing.md`'s conflict resolution — no Sorbet in this repository).
- **`downcase` is called with no arguments, everywhere** (`Dexpace/NoLocaleCaseFold`).
- **Inside `module Dexpace`, anywhere, write `::Thread`, `::Queue`, `::Mutex`, `::SizedQueue`,
  `::ConditionVariable`, `::JSON`, `::IO`, `::Array`, `::Hash`, `::Data`, `::StandardError`, `::Exception`** —
  never the bare name (`Dexpace/QualifiedCoreConstant`, phase 2's sixth cop). The design flags the two
  places that bite: `Dexpace::Pipeline::Entry#step` and `Dexpace::Pipeline::Cursor#request` each sit
  one line from `Dexpace::Request`. This phase adds nothing to the cop's `SHADOWED` list — no constant
  it defines shares a name with a Ruby core constant.
- **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden repository-wide**
  (`Dexpace/NoThreadInterrupt`). In 4c the constraint is met by an absence: **4c writes no wait, no sleep
  and no interrupt of any kind.** The only blocking call in reach is phase 2's `Future#value(cancellation:)`,
  and 4c does not call it either — a caller composing `AsyncTransport.sync_over` does.
- **Deadlines are explicit values, not ambient interrupts.** `DEF-28` keeps `deadline:` off the pivot until
  phase 5; 4c ships the narrower composition and fabricates no deadline (R13, P4-35).
- **`Thread::Mutex` ownership is per-fiber and non-reentrant.** 4c holds no mutex anywhere. The built
  runtime is immutable, so concurrent sends read frozen data with no lock (`PIPE-10`); the cursor is
  per-invocation and unshared (P4-33); the builder is single-threaded by construction and says so in its
  YARD, exactly as phase 1's builders do.
- **The cursor single-use latch is an unsynchronised instance variable**; its detection is sequential-only
  (P4-33). Verified fact 9 measures the race: 29 of 2000 runs on 3.2.11 and 0 of 2000 on 3.4.10/4.0.6.
  Handing one cursor to two threads is already a caller defect (`PIPE-15`); the design does not promise to
  catch every concurrent defect and ships no test asserting the race, because at 1.5 % the single-shot form
  flakes on the floor and the 2000-run form is green on one column and red on three.
- **`Fiber[:key]` is the diagnostic-context carrier and `PIPE` is not it.** Per-call state lives on the cursor
  and is passed as an argument, never read from ambient storage (`PIPE-11`). A step that spawns a fiber or
  thread must hand it the cursor explicitly; nothing is inherited.
- **Bytes on the wire are `Encoding::BINARY`.** 4c touches no wire bytes: a step receives a `Request` and
  returns a `Response`, and the body is phase 3's.
- **An `Enumerator` abandoned mid-`#next` never runs its `ensure`.** `#steps` and `#entries` are frozen `Array`s,
  the flatten is `flat_map`, and no resource is acquired inside any block 4c yields from.
- **Domain model construction pattern:** `Data.define` is the base for value types (`Stage`, `Entry`).
  `private_class_method :new` plus validating constructor / `.build` factory (`Stages.of`, `Entry.build`,
  `Cursor.build`, `TransformStep.build`). Collections are duplicated and frozen exactly once at construction.
- **Formatting:** double quotes, 2-space indent, 100 columns, `consistent_comma` trailing commas,
  leading-dot chains, `MethodLength: 25`, `ParameterLists: 4`, `BlockNesting: 3`.
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
bundle exec rake surface:regenerate                                 # deliberate; Task 11 only
```

## This plan's open questions, resolved

1. **The exact message forms for `Dexpace::PipelineError`'s nine conditions.**
   The design fixes what each must name and not the exact wording. This plan fixes the strings and
   asserts each one **at the site that raises it**, never against a hand-constructed error — a test
   that builds `PipelineError.new(msg)` and asserts `#message == msg` exercises `::StandardError`
   and nothing this phase writes. Task 1 pins the class shape; Tasks 5, 6 and 7 pin the forms:
   - `PIPE-5` pillar collision: `"pillar #{stage.name} is already occupied by #{existing_type}; cannot install #{new_type} (use #replace to substitute) (PIPE-5)"`
   - `PIPE-8` terminal SEND install: `"cannot install step at terminal stage SEND (PIPE-8)"`
   - `PIPE-15` cursor reused: `"cursor has already been invoked and cannot be reused (PIPE-15)"`
   - `PIPE-15` / R10 slot stage cannot fork: `"stage #{stage.name} is not a configurable pillar and cannot fork (PIPE-15)"`
   - `PIPE-15` / P4-39 spent cursor cannot fork: `"cursor is spent and cannot be forked; #call and #fork are disjoint (PIPE-15)"`
   - `PIPE-18` / `PIPE-19` cross-stage move: `"cannot insert #{step_type} declaring stage #{step_stage.name} relative to anchor at stage #{anchor_stage.name} (PIPE-18)"`
   - `PIPE-21` missing anchor: `"anchor step of type #{anchor_type} was not found in pipeline (PIPE-21)"`
   - `PIPE-23` reload validation failure: `"cannot reload pipeline entries: #{details} (PIPE-23)"`
   - `PIPE-24` preset collision: `"cannot install preset: pillar #{stage.name} is already occupied by #{occupant_type} (PIPE-24)"`, one clause per occupied pillar joined by `"; "`

   **Two more forms exist than P4-37 enumerates, and the gap is the design's own rather than this
   plan's invention.** P4-37 lists nine conditions; R10's precedence table rejects two further
   install-time cases with the same class, and neither is on that list — row 3 (a step declares
   `#stage` and a *different* `stage:` is given) and row 4 (a step declares nothing and no `stage:`
   is given). Both ship, under `Dexpace::PipelineError` and carrying no fields, so P4-37's *shape*
   claim is unaffected and no new deviation is filed; only its count reads low. They cite `R10`
   rather than a `PIPE` ID because no requirement forces either — R10's resolution does:
   - R10 row 3, declared/given disagreement: `"step declares stage #{declared.name} but was installed with stage #{given.name} (R10)"`
   - R10 row 4, no stage at all: `"step does not declare #stage and no stage: keyword was given; a step with no stage cannot be installed (R10)"`
2. **Whether `Stages::ALL` and `Stages::PILLARS` are `Ractor.make_shareable`d or merely frozen.**
   Merely frozen via `.freeze`. Constraint 8 and design §12 note that 4c makes no shareability claim
   for anything in the pipeline (a `Response` holds a body holding an `IO`, so no shareability claim is
   made for a cursor, runtime, or step). Calling `Ractor.make_shareable` would document a guarantee nothing
   in the specification demands. Shallow freeze of the owning `Array` and deep freezing of its immutable
   `Stage` elements suffices.
3. **The `ProbeStep` family's exact shape.**
   Separate types: `ProbeStep`, `ForkingProbe`, and `StateProbe`.
   - `ProbeStep` is a `Data.define(:tag, :log)` with `#call(request, cursor)` appending `[:enter, tag]`
     and `[:exit, tag]` around `cursor.call(request)`. As verified fact 3 shows, two `Data` instances
     with equal members are `==` and not `equal?`. To satisfy `PIPE-6`'s idempotence fixture, constructing
     two `ProbeStep` instances with identical `tag` and a **shared** mutable `log` array ensures they remain
     `==` across execution.
   - `ForkingProbe` is a dedicated class for testing `PIPE-15`, `PIPE-16`, `PIPE-40` and R11's *write*
     side: it forks `n` times, writes the per-drive state map it was given into its own stage slot,
     closes each superseded intermediate response before the next drive, and returns the final one
     unclosed. **It declares no `#stage`**, so the stage travels as the install-time argument (R10
     row 5) — a probe that hard-coded `REDIRECT` would be rejected by R10 row 3 the moment a test
     installed it at `RETRY`, which R11's assertion 4 does.
   - `StateProbe` is R11's *read* side: a slot probe that records `cursor.state(stage)` at every
     invocation. The pillar writer R11 also needs is `ForkingProbe` with `state_per_drive:`, not a
     second `StateProbe` mode — one forking implementation, used by both requirements.
   - None of the probe types acquires resources inside a yielded block.
4. **Whether `Builder` validates its transport with `Transport.conforms?` / `AsyncTransport.conforms?` at build time or only at first dispatch.**
   At `#build` and `#build_async` time (build time), through **phase 2's own predicates** rather than
   a local `respond_to?(:call)` — `Dexpace::Transport.conforms?` and `Dexpace::AsyncTransport.conforms?`
   both reduce to `Dexpace::Registry.callable?(object, arity: 3)`, so the arity check comes for free and
   there is one shape predicate in the repository rather than two. Validating at build fails fast,
   preventing a broken runtime from being handed back. The predicate cannot distinguish sync from async
   return types (verified facts 1 and 2), so it catches a non-callable and a wrong arity and nothing
   else; that is stated in `#build_async`'s YARD rather than pretended otherwise (P4-30's cost cell).
5. **How many of the fifteen `PIPE-1` probes one test file holds, and whether the shuffled-insertion case is one pinned-seed test or a fixed set of permutations.**
   All fifteen stages (all 16 stages in `Stages::ALL` minus terminal `SEND`). The shuffled-insertion test
   uses one pinned seed (`Random.new(42)`), logging the seed per `testing/7ece0212` if a failure occurs.
6. **Whether `#install_preset` and `#reload` share one public validation error or two.**
   They share one error class (`Dexpace::PipelineError`, per P4-37) with distinct, informative error message
   strings. Both share a validate-then-commit implementation so "all-or-nothing" semantics cannot drift.
7. **How `Cursor#call` and `#fork` are declared in RBS.**
   `untyped` on `Cursor#call` (and `Cursor#fork -> Cursor`), with `_Step` and `_AsyncStep` interfaces carrying
   the concrete return types (`Dexpace::Response` and `Dexpace::Async::Future` respectively).
   This follows the precedent phase 2 set for `Future#value`'s return type. A union type would force every
   step author to perform unnecessary type narrowing, while a generic `Cursor[R]` would introduce the repository's
   first generic class and complicate `#fork` without runtime backing.
   Concretely, and this is the text `NFR-4` locks — Task 6's `sig/dexpace/pipeline/cursor.rbs` writes
   `def call: (?Dexpace::Request request) -> untyped` and `def fork: (?state: Hash[untyped, untyped]?) -> Cursor`,
   and Task 4's `sig/dexpace/pipeline/step.rbs` writes the two interfaces that carry the real types.
   Widening `#call` from `untyped` to a union later is not an `NFR-4` break; narrowing it to
   `Dexpace::Response` would be, which is the asymmetry that makes `untyped` the reversible choice.

**Two more the plan opened, resolved here rather than met in the middle of a task.**

8. **`Dexpace::Pipeline` and `Dexpace::AsyncPipeline` are not `Object#freeze`d, and cannot be.**
   The design asks for both "frozen after construction" and `PIPE-27`'s close through
   `Dexpace::Closeable` with `owned: false`. Phase 2's `Closeable#close` writes `@dexpace_closed`
   under `@dexpace_close_mutex`, so `close` on a frozen runtime raises `FrozenError` and the
   `PIPE-27` test is the one that finds it. The two cannot both hold, and `PIPE-27` is the MUST:
   **the latch wins and `freeze` is dropped from both constructors.** What `PIPE-10`'s "immutable
   after construction (fixed ordered step collection + fixed transport reference)" actually requires
   is satisfied without it — `@entries` and `@steps` are frozen `Array`s built once and returned by
   the same reference every call, `@transport` is written once, and the class exposes no writer, no
   `#with` and no builder handle — and that is what Task 8 asserts instead of `pipeline.frozen?`.
   The one assertion in the design's R12 *Immutability* bullet that this drops is `pipeline.frozen?`
   itself; it is replaced by `assert_empty(Dexpace::Pipeline.public_instance_methods(false).grep(/=\z/))`
   and `assert_raises(FrozenError) { pipeline.steps << :extra }` alongside the two same-reference
   assertions, so nothing the bullet was protecting goes unasserted.
9. **How `Dexpace::AsyncPipeline` reaches `Dexpace::Pipeline::AsyncDriver`, which is a `private_constant`.**
   `private_constant` blocks the qualified reference from every scope whose cref does not include
   `Dexpace::Pipeline`, and `class AsyncPipeline` nests `[Dexpace::AsyncPipeline, Dexpace]` — so
   `Pipeline::AsyncDriver.new(self)` inside `AsyncPipeline#call` raises `NameError`. `const_get`
   would reach it and is the hole the design already names on `Cursor.build`'s `drive:` keyword; it
   is not used here, because there is a spelling with no hole in it. **`Builder` is itself nested
   inside `class Pipeline`, so both driver constants resolve there unqualified** — `#build` and
   `#build_async` therefore pass the driver class to the runtime's private constructor as
   `driver_class:`, and each runtime does `@driver_class.new(self)`. No public constant, no
   `const_get`, no second copy of the driver, and P4-30's "the runtimes differ by one private
   driver" becomes literally what the constructor argument says.

## Task order and dependency chain

1. **Task 1: `Dexpace::PipelineError`** — defines the single exception class for the pipeline subsystem and
   validates its nine message forms; needed by all later tasks when composition or contract rules are violated.
2. **Task 2: `Dexpace::Pipeline::Stage` and `Dexpace::Pipeline::Stages`** — defines the sixteen immutable stage
   constants, total ordering, and lookup; needed by `Entry`, `Cursor`, and `Builder`.
3. **Task 3: Pipeline Test Support Doubles** — defines `ProbeStep`, `ForkingProbe`, `StateProbe`, `FakeExecutor`,
   and `FakeAsyncTransport` under `test/support/`; needed by all subsequent task suites.
4. **Task 4: `Dexpace::Pipeline::Step` protocol and conformance predicate** — defines `Step.conforms?` and RBS
   interfaces `_Step` and `_AsyncStep`; needed by `Entry` and `Builder`.
5. **Task 5: `Dexpace::Pipeline::Entry` model** — defines the immutable `(stage, step)` pair; needed by `Cursor`,
   `Builder`, and both pipeline runtimes.
6. **Task 6: `Dexpace::Pipeline::Cursor` and Drivers** — defines the per-invocation cursor with single-use latch,
   `#call`, `#fork`, scoped state, and private `SyncDriver` and `AsyncDriver`; needed by `Pipeline` and `AsyncPipeline`.
7. **Task 7: `Dexpace::Pipeline::Builder`** — defines the mutable composition engine, append/prepend, surgical
   edits, reload, preset installation, and flattening/nesting seeding; needed by `Pipeline` and `AsyncPipeline`.
8. **Task 8: `Dexpace::Pipeline` Sync Runtime** — defines the sync execution engine, direct dispatch, zero-allocation
   empty pipeline, and the two phase-2 bridges end to end (`PIPE-33`/`PIPE-34`). It is what `Builder#build`
   *returns*, and it follows Task 7 rather than preceding it because Ruby resolves `Pipeline` inside
   `Builder#build` at call time: Task 7's own suite never calls `#build`, and every test that does is here.
9. **Task 9: `Dexpace::Pipeline::TransformStep`** — defines the generic adapter consuming phase 4b's `Transform`
   contract at `PRE_REDIRECT` (`PIPE-37`); completes the sync pipeline feature set.
10. **Task 10: `Dexpace::AsyncPipeline` Async Runtime and `map_response`** — defines the async execution engine,
    exception normalisation (`PIPE-29`/`PIPE-30`), and `AsyncPipeline.map_response` (`PIPE-31`); completes the
    async pipeline feature set.
11. **Task 11: Wiring, Runtime Surface Snapshot, RBS Baseline, the Checklist, and Documentation Upkeep** — fixes
    `lib/dexpace.rb`'s require order, updates `sig/dexpace.rbs`, regenerates the runtime surface snapshot,
    **verifies** the register rows the design already filed (`DEF-39`, `OI-17`, `OI-18` — none is re-filed),
    writes the phase checklist, runs the whole gate set and the floor, and runs the housekeeping probe.

**One ordering wrinkle, stated so nobody reads it as a defect.** Tasks 2 and 4–7 each open
`class Pipeline` to nest a constant inside it, and `lib/dexpace/pipeline.rb` itself does not exist
until Task 8 — so between Tasks 2 and 8 the constant `Dexpace::Pipeline` is created by whichever
nested file loads first. That is transient and harmless because every one of those files writes
`class Pipeline` and none writes `module Pipeline`; a mismatch would be a `TypeError` on the second
file. Task 11 Step 1 is where the final require order — `pipeline.rb` first among the nested set —
is put in place and asserted.

---

## Task 1: `Dexpace::PipelineError`

**Requirement IDs:** `PIPE-5`, `PIPE-8`, `PIPE-15`, `PIPE-18`, `PIPE-19`, `PIPE-21`, `PIPE-23`, `PIPE-24` —
the eight requirements whose rejection this one class carries, plus R10's two further rows. Every
one of them is *raised* in a later task; this task ships only the class and its shape.
**Design:** "`Dexpace::PipelineError` — `PIPE-5`, `PIPE-8`, `PIPE-15`, `PIPE-18`, `PIPE-19`, `PIPE-21`, `PIPE-23`, `PIPE-24`."
**Deviation:** P4-37 — one exception class for every composition-time and defect condition,
carrying no fields. The row enumerates nine; R10's precedence table adds two more (open question 1),
which changes the count and not the shape.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/error/pipeline_error.rb`,
  `gems/dexpace-core/sig/dexpace/error/pipeline_error.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/error/pipeline_error_test.rb`

**Interfaces:**
- Consumes: phase 1's `Dexpace::Error`.
- Produces: `Dexpace::PipelineError < ::StandardError`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# PIPE-5, PIPE-8, PIPE-15, PIPE-18, PIPE-19, PIPE-21, PIPE-23, PIPE-24.
class DexpacePipelineErrorTest < DexpaceTestCase
  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::PipelineError, "pipeline failure"
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::PipelineError, caught)
  end

  test "subclasses StandardError and includes Dexpace::Error" do
    assert_operator(Dexpace::PipelineError, :<, ::StandardError)
    assert_includes(Dexpace::PipelineError.ancestors, Dexpace::Error)
  end

  # P4-37: one class for every composition-time and defect condition, carrying NO fields, because
  # no caller branches on the reason and a carried field would be NFR-4-locked surface with no
  # reader. The contrast is deliberate: 4a's ContextConflictError carries #call_key because CTX-8's
  # caller lost a race and may retry.
  #
  # The eleven message forms themselves are asserted where they are raised, never here -- building
  # an error and asserting its #message tests ::StandardError. Entry.build (Task 5) raises PIPE-8's;
  # Cursor#call and #fork (Task 6) raise PIPE-15's three; Builder (Task 7) raises PIPE-5's,
  # PIPE-18's, PIPE-21's, PIPE-23's, PIPE-24's and R10's two.
  test "carries no fields of its own" do
    assert_empty(Dexpace::PipelineError.instance_methods(false))
    refute_respond_to(Dexpace::PipelineError.new("x"), :stage)
  end

  test "is not Dexpace::InvalidArgumentError -- a composition defect is not a bad argument" do
    refute_operator(Dexpace::PipelineError, :<, Dexpace::InvalidArgumentError)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/pipeline_error_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::PipelineError`.

- [ ] **Step 3: Write `lib/dexpace/error/pipeline_error.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # Raised on composition-time or contract violation in the pipeline subsystem (P4-37).
  # Conditions include pillar collisions, install at terminal SEND, cursor reuse,
  # invalid forks, cross-stage edits, missing anchor types, rejected reloads and presets.
  class PipelineError < ::StandardError
    include Dexpace::Error
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/error/pipeline_error.rbs`**

```rbs
module Dexpace
  class PipelineError < ::StandardError
    include Dexpace::Error
  end
end
```

- [ ] **Step 5: Add the require to `lib/dexpace.rb`**

Positioned in `lib/dexpace.rb` among the error requires:
`require_relative "dexpace/error/pipeline_error"`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/pipeline_error_test.rb`
Expected: PASS, 4 runs, 0 failures, 0 errors.

---

## Task 2: `Dexpace::Pipeline::Stage` and `Dexpace::Pipeline::Stages`

**Requirement IDs:** `PIPE-1`, `PIPE-2`, `PIPE-3`, `PIPE-4`, `PIPE-8`, `PIPE-25`, `PIPE-28`. `PIPE-36`
is **not** implemented here and no part of it is — `DEF-4` is unmet and post-MVP; R10's precedence
table is named as where a future lock would go, and verified fact 6 as why `Method#owner` cannot
detect an inherited `#stage`.
**Design:** "`Dexpace::Pipeline::Stage` — `PIPE-1`, `PIPE-2`, `PIPE-3`, `PIPE-4`, `PIPE-8`" and "`Dexpace::Pipeline::Stages` — `PIPE-1`, `PIPE-2`, `PIPE-3`, `PIPE-25`, `PIPE-28`."
**Deviations:** P4-31 (sixteen stages), P4-32 (`Stage` is `private_class_method :new` with no public factory; `Stages.of` is only lookup).

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/pipeline/stage.rb`,
  `gems/dexpace-core/lib/dexpace/pipeline/stages.rb`,
  `gems/dexpace-core/sig/dexpace/pipeline/stage.rbs`,
  `gems/dexpace-core/sig/dexpace/pipeline/stages.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/pipeline/stage_test.rb`,
  `gems/dexpace-core/test/dexpace/pipeline/stages_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`, `Dexpace::InvalidArgumentError`.
- Produces: `Dexpace::Pipeline::Stage`, `Dexpace::Pipeline::Stages` (16 stage constants, `ALL`, `PILLARS`, `.of`).

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# PIPE-1, PIPE-4, PIPE-8.
class DexpacePipelineStageTest < DexpaceTestCase
  # P4-32: the stage set is closed at sixteen *structurally*, not by policy. Data.define generates
  # BOTH .new and .[] -- privatising only .new leaves Stage[...] as a public field-wise constructor
  # and makes P4-32's "a caller cannot mint a sixteenth-and-a-half stage" false. Both are private,
  # verified on 3.2.11 and 3.4.10. The send hole phase 1's P8 names is untouched and is not closable.
  test "Stage has no public constructor: neither .new nor .[]" do
    assert_raises(NoMethodError) do
      Dexpace::Pipeline::Stage.new(name: :test, order: 100, pillar: false, terminal: false)
    end
    assert_raises(NoMethodError) do
      Dexpace::Pipeline::Stage[name: :test, order: 100, pillar: false, terminal: false]
    end
    refute_respond_to(Dexpace::Pipeline::Stage, :build)
  end

  test "Stage predicate methods reflect construction attributes" do
    stage = Dexpace::Pipeline::Stages::REDIRECT
    assert_equal(:redirect, stage.name)
    assert_equal(200, stage.order)
    assert_equal(true, stage.pillar?)
    assert_equal(false, stage.terminal?)
    assert_equal(true, stage.installable?)
  end

  test "terminal SEND stage is not installable" do
    send_stage = Dexpace::Pipeline::Stages::SEND
    assert_equal(:send, send_stage.name)
    assert_equal(1600, send_stage.order)
    assert_equal(true, send_stage.pillar?)
    assert_equal(true, send_stage.terminal?)
    assert_equal(false, send_stage.installable?)
  end

  test "sorting Stage instances directly raises ArgumentError per verified fact 10" do
    a = Dexpace::Pipeline::Stages::REDIRECT
    b = Dexpace::Pipeline::Stages::RETRY
    assert_raises(ArgumentError) do
      [b, a].sort
    end
  end
end
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# PIPE-1, PIPE-2, PIPE-3, PIPE-4, PIPE-8, PIPE-25, PIPE-28.
class DexpacePipelineStagesTest < DexpaceTestCase
  test "contains exactly sixteen stages" do
    assert_equal(16, Dexpace::Pipeline::Stages::ALL.size)
  end

  test "Stages::ALL is frozen" do
    assert_predicate(Dexpace::Pipeline::Stages::ALL, :frozen?)
  end

  test "Stages::ALL is in strictly ascending order by Stage#order" do
    all = Dexpace::Pipeline::Stages::ALL
    orders = all.map(&:order)

    assert_equal(orders, orders.uniq.sort)
    assert_equal(all, all.sort_by(&:order))
  end

  test "Stages::PILLARS contains the five configurable pillars in precedence order" do
    pillars = Dexpace::Pipeline::Stages::PILLARS
    expected = [
      Dexpace::Pipeline::Stages::REDIRECT,
      Dexpace::Pipeline::Stages::RETRY,
      Dexpace::Pipeline::Stages::AUTH,
      Dexpace::Pipeline::Stages::LOGGING,
      Dexpace::Pipeline::Stages::SERDE,
    ]

    assert_equal(expected, pillars)
    assert_predicate(pillars, :frozen?)
    refute_includes(pillars, Dexpace::Pipeline::Stages::SEND)
  end

  test "Stages.of resolves by symbol and string name" do
    assert_same(Dexpace::Pipeline::Stages::RETRY, Dexpace::Pipeline::Stages.of(:retry))
    assert_same(Dexpace::Pipeline::Stages::RETRY, Dexpace::Pipeline::Stages.of("retry"))
  end

  test "Stages.of raises Dexpace::InvalidArgumentError on unknown stage name" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Pipeline::Stages.of(:nonexistent)
    end

    assert_includes(error.message, "unknown stage: :nonexistent (PIPE-1)")
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline/stage_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Pipeline`.

- [ ] **Step 3: Write `lib/dexpace/pipeline/stage.rb` and `lib/dexpace/pipeline/stages.rb`**

`gems/dexpace-core/lib/dexpace/pipeline/stage.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Pipeline
    # An immutable stage in the total ordering (PIPE-1, PIPE-3).
    # Instances are closed and constructed only via Dexpace::Pipeline::Stages (P4-32).
    class Stage < ::Data.define(:name, :order, :pillar, :terminal)
      include Dexpace::Model

      # Data.define generates .[] alongside .new; both are private, because P4-32's closed-set
      # claim is structural and .[] alone would reopen it.
      private_class_method :new, :[]

      def initialize(name:, order:, pillar:, terminal:)
        unless name.is_a?(::Symbol)
          raise Dexpace::InvalidArgumentError, "name must be a Symbol (PIPE-1)"
        end
        unless order.is_a?(::Integer)
          raise Dexpace::InvalidArgumentError, "order must be an Integer (PIPE-1)"
        end
        unless pillar == true || pillar == false
          raise Dexpace::InvalidArgumentError, "pillar must be a boolean (PIPE-4)"
        end
        unless terminal == true || terminal == false
          raise Dexpace::InvalidArgumentError, "terminal must be a boolean (PIPE-8)"
        end
        if terminal && !pillar
          raise Dexpace::InvalidArgumentError, "terminal stage must also be a pillar (PIPE-4)"
        end

        super
      end

      def pillar?
        pillar
      end

      def terminal?
        terminal
      end

      def installable?
        !terminal
      end
    end
  end
end
```

`gems/dexpace-core/lib/dexpace/pipeline/stages.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "stage"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Pipeline
    # The canonical set of sixteen stages and their total ordering (PIPE-1, PIPE-2, PIPE-3, P4-31).
    module Stages
      PRE_REDIRECT  = Stage.send(:new, name: :pre_redirect,  order: 100,  pillar: false, terminal: false)
      REDIRECT      = Stage.send(:new, name: :redirect,      order: 200,  pillar: true,  terminal: false)
      POST_REDIRECT = Stage.send(:new, name: :post_redirect, order: 300,  pillar: false, terminal: false)
      PRE_RETRY     = Stage.send(:new, name: :pre_retry,     order: 400,  pillar: false, terminal: false)
      RETRY         = Stage.send(:new, name: :retry,         order: 500,  pillar: true,  terminal: false)
      POST_RETRY    = Stage.send(:new, name: :post_retry,    order: 600,  pillar: false, terminal: false)
      PRE_AUTH      = Stage.send(:new, name: :pre_auth,      order: 700,  pillar: false, terminal: false)
      AUTH          = Stage.send(:new, name: :auth,          order: 800,  pillar: true,  terminal: false)
      POST_AUTH     = Stage.send(:new, name: :post_auth,     order: 900,  pillar: false, terminal: false)
      PRE_LOGGING   = Stage.send(:new, name: :pre_logging,   order: 1000, pillar: false, terminal: false)
      LOGGING       = Stage.send(:new, name: :logging,       order: 1100, pillar: true,  terminal: false)
      POST_LOGGING  = Stage.send(:new, name: :post_logging,  order: 1200, pillar: false, terminal: false)
      PRE_SERDE     = Stage.send(:new, name: :pre_serde,     order: 1300, pillar: false, terminal: false)
      SERDE         = Stage.send(:new, name: :serde,         order: 1400, pillar: true,  terminal: false)
      POST_SERDE    = Stage.send(:new, name: :post_serde,    order: 1500, pillar: false, terminal: false)
      SEND          = Stage.send(:new, name: :send,          order: 1600, pillar: true,  terminal: true)

      ALL = [
        PRE_REDIRECT,
        REDIRECT,
        POST_REDIRECT,
        PRE_RETRY,
        RETRY,
        POST_RETRY,
        PRE_AUTH,
        AUTH,
        POST_AUTH,
        PRE_LOGGING,
        LOGGING,
        POST_LOGGING,
        PRE_SERDE,
        SERDE,
        POST_SERDE,
        SEND,
      ].freeze

      PILLARS = [
        REDIRECT,
        RETRY,
        AUTH,
        LOGGING,
        SERDE,
      ].freeze

      LOOKUP = ALL.each_with_object({}) do |stage, map|
        map[stage.name] = stage
        map[stage.name.to_s] = stage
      end.freeze
      private_constant :LOOKUP

      def self.of(name)
        LOOKUP.fetch(name) do
          raise Dexpace::InvalidArgumentError, "unknown stage: #{name.inspect} (PIPE-1)"
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/pipeline/stage.rbs` and `sig/dexpace/pipeline/stages.rbs`**

`gems/dexpace-core/sig/dexpace/pipeline/stage.rbs`:

```rbs
module Dexpace
  class Pipeline
    class Stage < ::Data
      include Dexpace::Model

      # .new and .[] are both private (P4-32) and are therefore absent here: RBS describes the
      # public surface NFR-4 locks, and Stages' sixteen constants are the whole population.
      attr_reader name: Symbol
      attr_reader order: Integer
      attr_reader pillar: bool
      attr_reader terminal: bool

      def pillar?: () -> bool
      def terminal?: () -> bool
      def installable?: () -> bool
    end
  end
end
```

`gems/dexpace-core/sig/dexpace/pipeline/stages.rbs`:

```rbs
module Dexpace
  class Pipeline
    module Stages
      PRE_REDIRECT: Stage
      REDIRECT: Stage
      POST_REDIRECT: Stage
      PRE_RETRY: Stage
      RETRY: Stage
      POST_RETRY: Stage
      PRE_AUTH: Stage
      AUTH: Stage
      POST_AUTH: Stage
      PRE_LOGGING: Stage
      LOGGING: Stage
      POST_LOGGING: Stage
      PRE_SERDE: Stage
      SERDE: Stage
      POST_SERDE: Stage
      SEND: Stage

      ALL: Array[Stage]
      PILLARS: Array[Stage]

      def self.of: (Symbol | String name) -> Stage
    end
  end
end
```

- [ ] **Step 5: Add requires to `lib/dexpace.rb`**

Add after pipeline root definition:
`require_relative "dexpace/pipeline/stage"`
`require_relative "dexpace/pipeline/stages"`

- [ ] **Step 6: Run tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline/stage_test.rb`
Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline/stages_test.rb`
Expected: PASS, 4 runs on stage_test, 6 runs on stages_test.

---

## Task 3: Pipeline Test Support Doubles

**Requirement IDs:** the fixtures for `PIPE-1`, `PIPE-2`, `PIPE-6`, `PIPE-15`, `PIPE-16`, `PIPE-33`,
`PIPE-34`, `PIPE-40` and R11. No requirement is *satisfied* by this task; every one is satisfied by
the suite that uses these doubles, and each is listed against its own task below.
**Design:** "The doubles, and why each exists."
**Verified Facts:** Fact 3 (ProbeStep equality over shared log), Fact 11 (ObjectSpace count under GC.disable).

**Files:**
- Create:
  - `gems/dexpace-core/test/support/probe_steps.rb`
  - `gems/dexpace-core/test/support/fake_executor.rb`
  - `gems/dexpace-core/test/support/fake_async_transport.rb`
- Test: `gems/dexpace-core/test/support/pipeline_doubles_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Pipeline::Stages`, `Dexpace::Async::Completer`, `Dexpace::Async::Future`.
- Produces: `ProbeStep`, `ForkingProbe`, `StateProbe`, `FakeExecutor`, `FakeAsyncTransport`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "probe_steps"
require_relative "fake_executor"
require_relative "fake_async_transport"

# Test doubles validation: verified fact 3, PIPE-6, PIPE-15, PIPE-33.
class PipelineDoublesTest < DexpaceTestCase
  test "ProbeStep instances with equal tags and shared log array are == and not equal?" do
    log = []
    first = ProbeStep.new(tag: :retry, log: log)
    second = ProbeStep.new(tag: :retry, log: log)

    assert_equal(first, second)
    refute_same(first, second)

    log << [:enter, :retry]
    assert_equal(first, second, "must remain == across shared log mutation (PIPE-6 fixture)")
  end

  test "ProbeStep instances with distinct tags are not ==" do
    log = []
    first = ProbeStep.new(tag: :auth, log: log)
    second = ProbeStep.new(tag: :retry, log: log)

    refute_equal(first, second)
  end

  # R10: no probe declares #stage, so every install in this phase's suite names the stage as an
  # argument -- row 5 of the precedence table. A declaring probe would be rejected by row 3 wherever
  # a test installs it somewhere other than the stage it hard-codes.
  test "no probe declares #stage" do
    refute_respond_to(ProbeStep.new(tag: :a, log: []), :stage)
    refute_respond_to(ForkingProbe.new, :stage)
    refute_respond_to(StateProbe.new(stage_to_read: Dexpace::Pipeline::Stages::REDIRECT), :stage)
  end

  test "FakeExecutor records post invocations" do
    executor = FakeExecutor.new
    assert_equal(0, executor.posts)

    run = false
    executor.post { run = true }

    assert_equal(1, executor.posts)
    assert_equal(true, run)
  end

  test "FakeAsyncTransport delivers a settled Future" do
    transport = FakeAsyncTransport.new(response: "ok")
    future = transport.call(nil)

    assert_instance_of(Dexpace::Async::Future, future)
    assert_equal("ok", future.value)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/support/pipeline_doubles_test.rb`
Expected: FAIL — `cannot load such file -- probe_steps`.

- [ ] **Step 3: Write test support files**

`gems/dexpace-core/test/support/probe_steps.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# ProbeStep is a Data value object; two instances with equal members are == and not equal?
# When constructed with a shared log Array, they remain == across mutations (verified fact 3, PIPE-6).
class ProbeStep < ::Data.define(:tag, :log)
  def call(request, cursor)
    log << [:enter, tag]
    begin
      cursor.call(request)
    ensure
      log << [:exit, tag]
    end
  end
end

# ForkingProbe is the conformance fixture for PIPE-15, PIPE-16, PIPE-40 and R11's write side. It
# forks for EVERY drive including the first and never calls its own #call (P4-39), closes each
# superseded intermediate response before the next drive and returns the last one unclosed
# (PIPE-40), and writes the drive's state map into its own stage slot (R11).
#
# #stage is NOT declared. A probe hard-coding REDIRECT would be rejected by R10 row 3 the moment a
# test installed it at RETRY, which R11's assertion 4 does; the stage travels as the install-time
# argument instead, which is R10's own answer for a step that declares nothing.
class ForkingProbe
  attr_reader :drives, :closed_responses

  def initialize(times: 2, state_per_drive: nil)
    @times = times
    @state_per_drive = state_per_drive || []
    @drives = 0
    @closed_responses = []
  end

  def call(request, cursor)
    last_response = nil

    @times.times do |i|
      # PIPE-40: the superseded intermediate is released before the next drive is issued, and the
      # one handed back is never closed -- close-responsibility passes outward.
      if last_response
        @closed_responses << last_response
        Dexpace.close_quietly(last_response)
      end

      @drives += 1
      last_response = cursor.fork(state: @state_per_drive[i]).call(request)
    end

    last_response
  end
end

# StateProbe is R11's read side: a slot probe recording cursor.state(stage) at every invocation.
# The write side is ForkingProbe with state_per_drive:, because only a pillar step may fork.
class StateProbe
  attr_reader :reads

  def initialize(stage_to_read:)
    @stage_to_read = stage_to_read
    @reads = []
  end

  def call(request, cursor)
    @reads << cursor.state(@stage_to_read)
    cursor.call(request)
  end
end
```

`gems/dexpace-core/test/support/fake_executor.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# FakeExecutor counts posts and executes blocks synchronously (PIPE-33).
class FakeExecutor
  attr_reader :posts

  def initialize
    @posts = 0
  end

  def post
    @posts += 1
    yield
  end
end
```

`gems/dexpace-core/test/support/fake_async_transport.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# FakeAsyncTransport returns an already-settled Future, or -- with defer: true -- a Completer the
# test settles itself. Both modes are deterministic and neither sleeps. The deferred mode is what
# PIPE-34's cancellation case needs: Future#await returns immediately on an already-settled future,
# so a token cancelled before the wait is never observed unless the future is still in flight.
class FakeAsyncTransport
  attr_reader :calls, :completers

  def initialize(response: nil, error: nil, defer: false)
    @response = response
    @error = error
    @defer = defer
    @calls = []
    @completers = []
  end

  def call(request, options = nil, cancellation = nil)
    @calls << { request:, options:, cancellation: }
    completer = Dexpace::Async::Completer.new
    @completers << completer

    unless @defer
      @error ? completer.fail(@error) : completer.fulfil(@response)
    end

    completer.future
  end
end
```

- [ ] **Step 4: Confirm no sig/ or lib/ entry needed**

Test doubles reside entirely under `test/support/` and do not ship in the gem; no RBS or `lib/dexpace.rb` entry.

- [ ] **Step 5: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/support/pipeline_doubles_test.rb`
Expected: PASS, 5 runs, 0 failures, 0 errors.

---

## Task 4: `Dexpace::Pipeline::Step` protocol and conformance predicate

**Requirement IDs:** `PIPE-11`, `PIPE-12`, `NFR-11`. `PIPE-12` is the step contract the predicate is
a predicate *of* — "each step MUST be bidirectional: it receives the inbound request, MAY call next
… MAY short-circuit"; `PIPE-11` is why a step carries no per-call state and takes the cursor as its
second argument; `NFR-11` is why the protocol has a named home in `sig/` at all.
**Design:** "`Dexpace::Pipeline::Step` — the step protocol" and "The RBS interfaces".
**Deviations:** P4-26 (public protocol module and RBS interfaces), P4-27 (`Step.conforms?`).
**Verified Facts:** Fact 1 (two-argument step predicate from `#parameters`).

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/pipeline/step.rb`,
  `gems/dexpace-core/sig/dexpace/pipeline/step.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/pipeline/step_test.rb`

**Interfaces:**
- Produces: `Dexpace::Pipeline::Step.conforms?(object) -> bool`, RBS interfaces `_Step` and `_AsyncStep`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# PIPE-11, PIPE-12, NFR-11.
class DexpacePipelineStepTest < DexpaceTestCase
  test "conforms? accepts 2-arg lambda" do
    step = ->(request, cursor) { cursor.call(request) }
    assert_equal(true, Dexpace::Pipeline::Step.conforms?(step))
  end

  test "conforms? accepts 2-arg Proc with optional parameters" do
    step = proc { |request, cursor| cursor.call(request) }
    assert_equal(true, Dexpace::Pipeline::Step.conforms?(step))
  end

  test "conforms? accepts object with 2-arg #call method" do
    klass = Class.new do
      def call(request, cursor)
        cursor.call(request)
      end
    end
    assert_equal(true, Dexpace::Pipeline::Step.conforms?(klass.new))
  end

  test "conforms? accepts rest-parameter callables" do
    step = ->(*args) { args }
    assert_equal(true, Dexpace::Pipeline::Step.conforms?(step))
  end

  test "conforms? rejects 0-arg, 1-arg, and 3-arg callables" do
    assert_equal(false, Dexpace::Pipeline::Step.conforms?(-> { 42 }))
    assert_equal(false, Dexpace::Pipeline::Step.conforms?(->(x) { x }))
    assert_equal(false, Dexpace::Pipeline::Step.conforms?(->(a, b, c) { [a, b, c] }))
  end

  test "conforms? rejects non-callable objects" do
    assert_equal(false, Dexpace::Pipeline::Step.conforms?(Object.new))
    assert_equal(false, Dexpace::Pipeline::Step.conforms?(nil))
    assert_equal(false, Dexpace::Pipeline::Step.conforms?("not callable"))
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline/step_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Pipeline::Step`.

- [ ] **Step 3: Write `lib/dexpace/pipeline/step.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../registry"

module Dexpace
  class Pipeline
    # The step protocol (PIPE-11, PIPE-12), mirroring Dexpace::Transport's shape one arity lower.
    #
    # A step is a duck type: `include Dexpace::Pipeline::Step` is neither required nor meaningful,
    # because design §5.1's requirement is that a lambda qualifies as a step and a module a lambda
    # cannot include cannot be the gate. The module exists so NFR-11's RBS scan has a named home for
    # the protocol and so the predicate lives once.
    #
    # No registry. Dexpace::Registry has three seam instances and this phase adds no fourth: a step
    # is something a caller builds and installs, not something the SDK discovers.
    module Step
      # Phase 2's predicate, one arity lower, reused rather than reimplemented -- "required <= 2 and
      # (a rest parameter is present or required + optional >= 2)", with the :opt handling that lets
      # a non-lambda `proc { |request, cursor| }` through, and phase 2's NameError fallback for an
      # object whose #parameters cannot be read.
      #
      # It cannot tell a sync step from an async one, because they differ only in return type --
      # phase 2's admitted gap arriving at a second seam, and why Builder has #build and #build_async
      # rather than one method with a flag (P4-30).
      def self.conforms?(object) = Dexpace::Registry.callable?(object, arity: 2)
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/pipeline/step.rbs`**

```rbs
module Dexpace
  class Pipeline
    module Step
      def self.conforms?: (untyped object) -> bool
    end

    interface _Step
      def call: (Dexpace::Request request, Dexpace::Pipeline::Cursor cursor) -> Dexpace::Response
    end

    interface _AsyncStep
      def call: (Dexpace::Request request, Dexpace::Pipeline::Cursor cursor) -> Dexpace::Async::Future
    end

    type step_callable = _Step | ^(Dexpace::Request, Dexpace::Pipeline::Cursor) -> Dexpace::Response
    type async_step_callable = _AsyncStep | ^(Dexpace::Request, Dexpace::Pipeline::Cursor) -> Dexpace::Async::Future
  end
end
```

- [ ] **Step 5: Add the require to `lib/dexpace.rb`**

Positioned after `stages.rb`: `require_relative "dexpace/pipeline/step"`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline/step_test.rb`
Expected: PASS, 6 runs, 0 failures, 0 errors.

---

## Task 5: `Dexpace::Pipeline::Entry` model

**Requirement IDs:** `PIPE-8` (the install at SEND is rejected here, in the one place every install
funnels through), `PIPE-22`, `PIPE-23`, `PIPE-25`, `PIPE-35` — the four that need a caller-visible
"this step, at this stage" pair.
**Design:** "`Dexpace::Pipeline::Entry` — `PIPE-22`, `PIPE-23`, `PIPE-25`, `PIPE-35`."
**Deviations:** P4-26 (public Entry constant), P4-27 (`Entry.build`).

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/pipeline/entry.rb`,
  `gems/dexpace-core/sig/dexpace/pipeline/entry.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/pipeline/entry_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`, `Dexpace::Pipeline::Stage`, `Dexpace::Pipeline::Step`, `Dexpace::PipelineError`.
- Produces: `Dexpace::Pipeline::Entry.build(stage:, step:) -> Entry`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# PIPE-8, PIPE-22, PIPE-23, PIPE-25, PIPE-35.
class DexpacePipelineEntryTest < DexpaceTestCase
  def setup
    @stage = Dexpace::Pipeline::Stages::RETRY
    @step = ->(req, cur) { cur.call(req) }
  end

  # Both generated constructors are private, so .build is the only path and its three checks cannot
  # be walked around by a caller who reaches for Data's .[] instead of .new.
  test "Entry.new and Entry.[] are both private" do
    assert_raises(NoMethodError) do
      Dexpace::Pipeline::Entry.new(stage: @stage, step: @step)
    end
    assert_raises(NoMethodError) do
      Dexpace::Pipeline::Entry[stage: @stage, step: @step]
    end
  end

  test "Entry.build succeeds with valid stage and conforming step" do
    entry = Dexpace::Pipeline::Entry.build(stage: @stage, step: @step)
    assert_same(@stage, entry.stage)
    assert_same(@step, entry.step)
    assert_predicate(entry, :frozen?)
  end

  test "Entry.build rejects terminal stage SEND with PipelineError" do
    send_stage = Dexpace::Pipeline::Stages::SEND
    error = assert_raises(Dexpace::PipelineError) do
      Dexpace::Pipeline::Entry.build(stage: send_stage, step: @step)
    end
    assert_includes(error.message, "cannot install step at terminal stage SEND (PIPE-8)")
  end

  test "Entry.build rejects non-stage with InvalidArgumentError" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Pipeline::Entry.build(stage: :not_a_stage, step: @step)
    end
    assert_includes(error.message, "stage must be a Dexpace::Pipeline::Stage (PIPE-1)")
  end

  test "Entry.build rejects non-conforming step with InvalidArgumentError" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Pipeline::Entry.build(stage: @stage, step: Object.new)
    end
    assert_includes(error.message, "step must conform to Dexpace::Pipeline::Step (PIPE-12)")
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline/entry_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Pipeline::Entry`.

- [ ] **Step 3: Write `lib/dexpace/pipeline/entry.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "stage"
require_relative "step"
require_relative "../error/pipeline_error"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Pipeline
    # An immutable association between a pipeline Stage and a conforming Step (PIPE-22, PIPE-25).
    class Entry < ::Data.define(:stage, :step)
      include Dexpace::Model

      # Data.define generates .[] alongside .new; both are private so .build is the only path in.
      private_class_method :new, :[]

      def self.build(stage:, step:)
        unless stage.is_a?(Stage)
          raise Dexpace::InvalidArgumentError, "stage must be a Dexpace::Pipeline::Stage (PIPE-1)"
        end
        unless stage.installable?
          raise Dexpace::PipelineError, "cannot install step at terminal stage SEND (PIPE-8)"
        end
        unless Step.conforms?(step)
          raise Dexpace::InvalidArgumentError, "step must conform to Dexpace::Pipeline::Step (PIPE-12)"
        end

        new(stage:, step:)
      end
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/pipeline/entry.rbs`**

```rbs
module Dexpace
  class Pipeline
    class Entry < ::Data
      include Dexpace::Model

      # .new and .[] are private; .build is the only public constructor.
      def self.build: (stage: Stage, step: untyped) -> Entry

      attr_reader stage: Stage
      attr_reader step: untyped
    end
  end
end
```

- [ ] **Step 5: Add the require to `lib/dexpace.rb`**

Positioned after `step.rb`: `require_relative "dexpace/pipeline/entry"`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline/entry_test.rb`
Expected: PASS, 5 runs, 0 failures, 0 errors.

---

## Task 6: `Dexpace::Pipeline::Cursor` and Drivers (`SyncDriver`, `AsyncDriver`)

**Requirement IDs:** `PIPE-10`, `PIPE-11`, `PIPE-12`, `PIPE-13`, `PIPE-14`, `PIPE-15`, `PIPE-16`, `PIPE-17`, `PIPE-40`.
**Design:** "`Dexpace::Pipeline::Cursor` — `PIPE-10`–`PIPE-17`, `PIPE-40`", R10, R11.
**Deviations:** P4-28 (scoped state is `(stage, key)`), P4-29 (no state-setting method), P4-30 (one Cursor class), P4-33 (unsynchronised single-use latch), P4-39 (`#call` and `#fork` disjoint on one cursor).
**Verified Facts:** Fact 4 (frozen Hash semantics), Fact 5 (`Data#with` identity preservation), Fact 7 (bare raise in async driver).

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/pipeline/cursor.rb`,
  `gems/dexpace-core/lib/dexpace/pipeline/sync_driver.rb`,
  `gems/dexpace-core/lib/dexpace/pipeline/async_driver.rb`,
  `gems/dexpace-core/sig/dexpace/pipeline/cursor.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/pipeline/cursor_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Pipeline::Entry`, `Dexpace::Pipeline::Stages`, `Dexpace::PipelineError`.
- Produces: `Dexpace::Pipeline::Cursor`, `SyncDriver` (private_constant), `AsyncDriver` (private_constant).

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../support/probe_steps"

# PIPE-10, PIPE-11, PIPE-12, PIPE-13, PIPE-14, PIPE-15, PIPE-16, PIPE-17, PIPE-40, R11.
class DexpacePipelineCursorTest < DexpaceTestCase
  # SyncDriver is a private_constant, so `Dexpace::Pipeline::SyncDriver` raises NameError from out
  # here; const_get is the documented way through and is the hole the design already names on
  # Cursor.build's drive: keyword. Reaching for it is what lets these tests drive a cursor with no
  # Pipeline runtime in the picture, which is the whole point of Task 6 preceding Task 8.
  SYNC_DRIVER = Dexpace::Pipeline.const_get(:SyncDriver)

  # The runtime surface a driver reads: a frozen entry table and a terminal transport, and nothing
  # else. Standing in for Dexpace::Pipeline here keeps Task 6 buildable before Task 8 exists.
  class DummySyncPipeline
    attr_reader :entries, :transport

    def initialize(entries, transport)
      @entries = entries.freeze
      @transport = transport
    end
  end

  # The narrowest stand-in for a Response that PIPE-40 needs: something with a close latch. Phase
  # 3's Body and Response are not involved -- no bytes cross this phase (design, Testing strategy).
  class FakeCloseable
    def initialize = @closed = false
    def close = @closed = true
    def closed? = @closed
  end

  def setup
    @request = "original_request"
    @options = Object.new.freeze
    @cancellation = Object.new.freeze
    @transport = ->(req, _opts, _canc) { "response_for_#{req}" }
  end

  def cursor_over(entries, transport = @transport)
    Dexpace::Pipeline::Cursor.build(
      drive: SYNC_DRIVER.new(DummySyncPipeline.new(entries, transport)),
      request: @request,
      options: @options,
      cancellation: @cancellation
    )
  end

  test "PIPE-12: short-circuiting step does not advance to downstream steps or transport" do
    transport_called = false
    downstream_called = false

    step1 = ->(_req, _cur) { "synthetic_response" }
    step2 = lambda do |req, cur|
      downstream_called = true
      cur.call(req)
    end

    e1 = Dexpace::Pipeline::Entry.build(stage: Dexpace::Pipeline::Stages::PRE_AUTH, step: step1)
    e2 = Dexpace::Pipeline::Entry.build(stage: Dexpace::Pipeline::Stages::AUTH, step: step2)

    wire = lambda do |_r, _o, _c|
      transport_called = true
      "wire"
    end
    res = cursor_over([e1, e2], wire).call(@request)

    assert_equal("synthetic_response", res)
    assert_equal(false, downstream_called)
    assert_equal(false, transport_called)
  end

  test "PIPE-13: forward-only cursor raises PipelineError on second call, spent? becomes true" do
    cursor = cursor_over([])

    assert_equal(false, cursor.spent?)
    cursor.call(@request)
    assert_equal(true, cursor.spent?)

    error = assert_raises(Dexpace::PipelineError) do
      cursor.call(@request)
    end
    assert_includes(error.message, "cursor has already been invoked and cannot be reused (PIPE-15)")
  end

  test "PIPE-13 / P4-39: fork after call on same cursor is rejected" do
    entry = Dexpace::Pipeline::Entry.build(
      stage: Dexpace::Pipeline::Stages::REDIRECT,
      step: lambda do |req, cur|
        cur.call(req)
        cur.fork
      end
    )

    error = assert_raises(Dexpace::PipelineError) do
      cursor_over([entry]).call(@request)
    end
    assert_includes(error.message, "cursor is spent and cannot be forked; #call and #fork are disjoint (PIPE-15)")
  end

  test "PIPE-14: request substitution sticks and propagates downstream" do
    seen_req = nil
    sub_req = "substituted_request"

    step1 = ->(_req, cur) { cur.call(sub_req) }
    step2 = lambda do |req, cur|
      seen_req = req
      cur.call(req)
    end

    e1 = Dexpace::Pipeline::Entry.build(stage: Dexpace::Pipeline::Stages::PRE_RETRY, step: step1)
    e2 = Dexpace::Pipeline::Entry.build(stage: Dexpace::Pipeline::Stages::RETRY, step: step2)

    res = cursor_over([e1, e2]).call(@request)

    assert_same(sub_req, seen_req)
    refute_same(@request, seen_req, "the original must not be retained anywhere on the drive")
    assert_equal("response_for_substituted_request", res)
  end

  test "PIPE-16 & PIPE-17: independent forks preserve options by identity across drives" do
    downstream_options = []
    downstream_spent = []
    downstream_cursors = []

    step1 = ForkingProbe.new(times: 2)
    step2 = lambda do |req, cur|
      downstream_options << cur.options
      downstream_cursors << cur
      response = cur.call(req)
      downstream_spent << cur.spent?
      response
    end

    e1 = Dexpace::Pipeline::Entry.build(stage: Dexpace::Pipeline::Stages::REDIRECT, step: step1)
    e2 = Dexpace::Pipeline::Entry.build(stage: Dexpace::Pipeline::Stages::AUTH, step: step2)

    cursor_over([e1, e2]).call(@request)

    # PIPE-16: the whole downstream tail re-runs from the fork's position, so AUTH is invoked once
    # per drive. A test that only asserted the response came back would pass against a cursor that
    # resumed PAST the tail on the second drive -- the exact defect PIPE-15 describes.
    assert_equal(2, downstream_options.size)
    assert_equal([true, true], downstream_spent)
    refute_same(downstream_cursors[0], downstream_cursors[1], "forks must advance independently")
    # PIPE-17: shared, not copied-and-diverged. assert_equal would pass against a per-fork rebuild.
    assert_same(@options, downstream_options[0])
    assert_same(@options, downstream_options[1])
  end

  test "PIPE-40: a re-driving step closes each superseded response and returns the last unclosed" do
    responses = []
    wire = lambda do |_r, _o, _c|
      response = FakeCloseable.new
      responses << response
      response
    end

    probe = ForkingProbe.new(times: 3)
    entry = Dexpace::Pipeline::Entry.build(stage: Dexpace::Pipeline::Stages::REDIRECT, step: probe)

    returned = cursor_over([entry], wire).call(@request)

    assert_equal(3, responses.size)
    assert_same(responses.last, returned)
    assert_equal([responses[0], responses[1]], probe.closed_responses)
    assert_predicate(responses[0], :closed?)
    assert_predicate(responses[1], :closed?)
    refute_predicate(returned, :closed?, "close-responsibility passes outward to the caller (PIPE-40)")
  end

  # R11 assertion 1. The negative is a statement about the SURFACE, not about a branch (P4-29):
  # "writable only by the pillar step that created the fork" is implemented as an unwritable object
  # plus a fork-time argument, so there is no check to bypass. The runtime surface manifest pins the
  # same fact from the other side (Task 11).
  test "R11: assertion 1 - cursor exposes no state-setting method at all" do
    methods = Dexpace::Pipeline::Cursor.public_instance_methods(false)

    assert_empty(methods.grep(/=\z/), "no writer of any name may appear on Cursor")
    assert_equal(
      %i[call cancellation fork may_fork? options request spent? state].sort,
      methods.sort
    )
  end

  test "R11: assertion 2 - state map returned is frozen" do
    cursor = cursor_over([])

    state_hash = cursor.state(Dexpace::Pipeline::Stages::REDIRECT)
    assert_predicate(state_hash, :frozen?)
    assert_raises(FrozenError) do
      state_hash[:cross_origin] = false
    end
  end

  test "R11: assertion 3 - non-pillar stage cannot fork" do
    step = ->(_req, cur) { cur.fork }
    entry = Dexpace::Pipeline::Entry.build(stage: Dexpace::Pipeline::Stages::PRE_AUTH, step: step)

    error = assert_raises(Dexpace::PipelineError) do
      cursor_over([entry]).call(@request)
    end
    assert_includes(error.message, "stage pre_auth is not a configurable pillar and cannot fork (PIPE-15)")
    refute(cursor_over([entry]).may_fork?, "a cursor at no owner index may not fork either")
  end

  # R11 assertion 4, and it is the assertion the (stage, key) namespacing exists for. Written
  # against Stages::REDIRECT and Stages::RETRY BY NAME because REDIR-11's cross-origin marker,
  # AUTH-29's reading of it and design section 10.15's "forgery becomes structurally impossible
  # rather than defended against" all rest on exactly this: a RETRY pillar step sits between
  # REDIRECT and AUTH in PIPE-2's order and may fork, so under a FLAT keyed map its fork could
  # carry a cross_origin AUTH cannot distinguish from REDIRECT's. Under a flat map this test fails.
  # A phase-6 author who changes the mechanism meets this comment.
  test "R11: assertion 4 - downstream pillar cannot alter upstream pillar slot" do
    auth_seen_redirect_state = nil
    auth_seen_retry_state = nil

    redirect_step = ForkingProbe.new(times: 1, state_per_drive: [{ cross_origin: true }])
    retry_step = ForkingProbe.new(times: 1, state_per_drive: [{ cross_origin: false, attempt: 1 }])
    auth_step = lambda do |req, cur|
      auth_seen_redirect_state = cur.state(Dexpace::Pipeline::Stages::REDIRECT)
      auth_seen_retry_state = cur.state(Dexpace::Pipeline::Stages::RETRY)
      cur.call(req)
    end

    e1 = Dexpace::Pipeline::Entry.build(stage: Dexpace::Pipeline::Stages::REDIRECT, step: redirect_step)
    e2 = Dexpace::Pipeline::Entry.build(stage: Dexpace::Pipeline::Stages::RETRY, step: retry_step)
    e3 = Dexpace::Pipeline::Entry.build(stage: Dexpace::Pipeline::Stages::AUTH, step: auth_step)

    cursor_over([e1, e2, e3]).call(@request)

    assert_equal({ cross_origin: true }, auth_seen_redirect_state)
    assert_equal({ cross_origin: false, attempt: 1 }, auth_seen_retry_state)
  end

  test "R11: assertion 5 - state writes do not reach back to parent or sibling forks" do
    step = Class.new do
      attr_reader :before_state, :parent_state, :sibling_state

      def call(req, cur)
        @before_state = cur.state(Dexpace::Pipeline::Stages::REDIRECT)
        cur.fork(state: { hop: 1 })
        @parent_state = cur.state(Dexpace::Pipeline::Stages::REDIRECT)
        second = cur.fork(state: { hop: 2 })
        @sibling_state = second.state(Dexpace::Pipeline::Stages::REDIRECT)
        second.call(req)
      end
    end.new

    entry = Dexpace::Pipeline::Entry.build(stage: Dexpace::Pipeline::Stages::REDIRECT, step: step)
    cursor_over([entry]).call(@request)

    # The same frozen object, not merely an equal one: a fork that mutated the parent's map in
    # place would still be assert_equal-clean here (verified fact 4's FrozenError is the other half).
    assert_same(step.before_state, step.parent_state)
    assert_empty(step.parent_state)
    # A second fork from the same parent inherits the parent's state, never the first fork's.
    assert_equal({ hop: 2 }, step.sibling_state)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline/cursor_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Pipeline::Cursor`.

- [ ] **Step 3: Write `lib/dexpace/pipeline/cursor.rb`, `sync_driver.rb`, and `async_driver.rb`**

`gems/dexpace-core/lib/dexpace/pipeline/cursor.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "stage"
require_relative "stages"
require_relative "../error/pipeline_error"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Pipeline
    # Per-invocation execution context threading state and position forward through pipeline entries (PIPE-10).
    # Holds an unsynchronised single-use latch whose detection is sequential-only (P4-33).
    class Cursor
      EMPTY_STAGE_STATE = {}.freeze
      EMPTY_STATE = {}.freeze
      private_constant :EMPTY_STAGE_STATE, :EMPTY_STATE

      attr_reader :request, :options, :cancellation

      private_class_method :new

      def self.build(drive:, request:, options:, cancellation:)
        new(drive:, owner_index: -1, position: 0, request:, options:, cancellation:, state: EMPTY_STATE)
      end

      def initialize(drive:, owner_index:, position:, request:, options:, cancellation:, state:)
        @drive = drive
        @owner_index = owner_index
        @position = position
        @request = request
        @options = options
        @cancellation = cancellation
        @state = state
        @spent = false
      end

      def spent?
        @spent
      end

      def may_fork?
        return false if @owner_index.negative?

        entry = @drive.entry_at(@owner_index)
        !entry.nil? && entry.stage.pillar? && !entry.stage.terminal?
      end

      def state(stage)
        @state.fetch(stage, EMPTY_STAGE_STATE)
      end

      # PIPE-12, PIPE-13. Advances to the next entry and invokes it; past the last entry the driver
      # dispatches to the terminal transport, threading the caller's options (PIPE-17). PIPE-14's
      # substitution sticks by construction: the child cursor carries the object passed here, and
      # the original is retained nowhere on the drive.
      #
      # Single-use. **The reuse guard is sequential-only** (P4-33): a second sequential call always
      # raises, a second CONCURRENT call sometimes does not -- eight threads through one
      # unsynchronised latch let more than one caller past on 29 of 2000 runs on 3.2.11 and 0 of
      # 2000 on 3.4.10 and 4.0.6. Handing one cursor to two threads is already the defect PIPE-15
      # names; do not read the raise as a concurrency guard.
      def call(new_request = @request)
        if @spent
          raise Dexpace::PipelineError, "cursor has already been invoked and cannot be reused (PIPE-15)"
        end

        @spent = true
        @drive.advance(
          position: @position,
          request: new_request,
          options: @options,
          cancellation: @cancellation,
          state: @state
        )
      end

      # PIPE-15, PIPE-16. A fresh cursor at the SAME position as the parent, carrying the current
      # in-flight request and the same frozen options object.
      #
      # Three rules a phase-6 pillar author has to know, and each is a raise rather than a comment:
      #
      # 1. Only a non-terminal pillar may fork (R10). The gate reads the RUNTIME's frozen entry
      #    table at the owner index, never the step's own #stage -- a forged step that answers
      #    Stages::REDIRECT while sitting in PRE_REDIRECT gets nothing, because nothing asks it.
      # 2. **#call and #fork are disjoint on one cursor (P4-39).** A step either drives once through
      #    #call and never forks, or forks for EVERY drive including the first and never calls
      #    #call. PIPE-15's own wording describes the reference's mixed shape -- drive 1 on the
      #    handle, drives 2..n on copies -- and this port does not use it: forking for drive 1 too
      #    is what makes hop 1 and hop n the same object and what gives a pillar's first drive a
      #    stage slot to write into. Forking earlier than PIPE-15 requires is strictly inside it.
      # 3. state: lands in the OWNER's own stage slot, chosen by the runtime from the entry table
      #    and never named by the caller (R11, P4-28). REDIR-11's marker expires for free: hop 2 is
      #    a fork of the same parent, not of hop 1's fork.
      #
      # The reuse guard #call carries is sequential-only; see #call.
      def fork(state: nil)
        if @spent
          raise Dexpace::PipelineError, "cursor is spent and cannot be forked; #call and #fork are disjoint (PIPE-15)"
        end
        unless state.nil? || state.is_a?(::Hash)
          raise Dexpace::InvalidArgumentError, "state: takes a Hash, got #{state.class}"
        end

        entry = @owner_index >= 0 ? @drive.entry_at(@owner_index) : nil
        stage = entry&.stage
        unless stage && stage.pillar? && !stage.terminal?
          stage_name = stage ? stage.name : :none
          raise Dexpace::PipelineError, "stage #{stage_name} is not a configurable pillar and cannot fork (PIPE-15)"
        end

        new_state = @state
        if state && !state.empty?
          current = @state.fetch(stage, EMPTY_STAGE_STATE)
          merged = current.merge(state).freeze
          new_state = @state.merge(stage => merged).freeze
        end

        Cursor.send(
          :new,
          drive: @drive,
          owner_index: @owner_index,
          position: @position,
          request: @request,
          options: @options,
          cancellation: @cancellation,
          state: new_state
        )
      end
    end
  end
end
```

`gems/dexpace-core/lib/dexpace/pipeline/sync_driver.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  class Pipeline
    # Private driver for synchronous step invocation and terminal dispatch (P4-30).
    class SyncDriver
      def initialize(pipeline)
        @pipeline = pipeline
      end

      def entry_at(index)
        @pipeline.entries[index]
      end

      def advance(position:, request:, options:, cancellation:, state:)
        entries = @pipeline.entries
        if position >= entries.size
          @pipeline.transport.call(request, options, cancellation)
        else
          entry = entries[position]
          child_cursor = Cursor.send(
            :new,
            drive: self,
            owner_index: position,
            position: position + 1,
            request: request,
            options: options,
            cancellation: cancellation,
            state: state
          )
          entry.step.call(request, child_cursor)
        end
      end
    end
    private_constant :SyncDriver
  end
end
```

`gems/dexpace-core/lib/dexpace/pipeline/async_driver.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  class Pipeline
    # Private driver for asynchronous step invocation and exception normalisation (P4-30, PIPE-29, PIPE-30).
    class AsyncDriver
      def initialize(pipeline)
        @pipeline = pipeline
      end

      def entry_at(index)
        @pipeline.entries[index]
      end

      def advance(position:, request:, options:, cancellation:, state:)
        entries = @pipeline.entries
        completer = Dexpace::Async::Completer.new

        if position >= entries.size
          begin
            future = @pipeline.transport.call(request, options, cancellation)
            future.on_settle { |s| s.success? ? completer.fulfil(s.response) : completer.fail(s.error) }
          rescue ::Exception => e
            raise unless e.is_a?(::StandardError)
            completer.fail(e)
          end
        else
          entry = entries[position]
          child_cursor = Cursor.send(
            :new,
            drive: self,
            owner_index: position,
            position: position + 1,
            request: request,
            options: options,
            cancellation: cancellation,
            state: state
          )

          begin
            result = entry.step.call(request, child_cursor)
            if result.is_a?(Dexpace::Async::Future)
              result.on_settle { |s| s.success? ? completer.fulfil(s.response) : completer.fail(s.error) }
            else
              completer.fulfil(result)
            end
          rescue ::Exception => e
            raise unless e.is_a?(::StandardError)
            completer.fail(e)
          end
        end

        completer.future
      end
    end
    private_constant :AsyncDriver
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/pipeline/cursor.rbs`**

```rbs
module Dexpace
  class Pipeline
    class Cursor
      # .new is private and takes owner_index:/position:/state: a caller cannot name; only .build
      # is public, and it produces the cursor bound to entry 0 (R10).
      def self.build: (drive: untyped, request: Dexpace::Request, options: Dexpace::RequestOptions, cancellation: Dexpace::Cancellation) -> Cursor

      attr_reader request: Dexpace::Request
      attr_reader options: Dexpace::RequestOptions
      attr_reader cancellation: Dexpace::Cancellation

      def spent?: () -> bool
      def may_fork?: () -> bool
      def state: (Stage stage) -> Hash[untyped, untyped]
      def call: (?Dexpace::Request request) -> untyped
      def fork: (?state: Hash[untyped, untyped]?) -> Cursor
    end
  end
end
```

- [ ] **Step 5: Add requires to `lib/dexpace.rb`**

Positioned after `entry.rb`:
`require_relative "dexpace/pipeline/cursor"`
`require_relative "dexpace/pipeline/sync_driver"`
`require_relative "dexpace/pipeline/async_driver"`

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline/cursor_test.rb`
Expected: PASS, 11 runs, 0 failures, 0 errors.

---

## Task 7: `Dexpace::Pipeline::Builder`

**Requirement IDs:** `PIPE-4`, `PIPE-5`, `PIPE-6`, `PIPE-7`, `PIPE-8`, `PIPE-18`, `PIPE-19`, `PIPE-20`,
`PIPE-21`, `PIPE-22`, `PIPE-23`, `PIPE-24`, `PIPE-28` (one deriver, not two), `PIPE-38`, and R10's
precedence table. `PIPE-25` and `PIPE-35` are *implemented* here — `#build`/`#build_async` and
`.flattening`/`.nesting` — and *asserted* in Task 8, which is where a built runtime exists to assert
them on. `DEF-39` is the deferral `#install_preset` is built under.
**Design:** "`Dexpace::Pipeline::Builder` — `PIPE-4`–`PIPE-8`, `PIPE-18`–`PIPE-25`, `PIPE-35`, `PIPE-38`", R10, R14.
**Deviations:** P4-27 (public builder methods), P4-30 (one Builder class for both runtimes), P4-34 (`PIPE-24` all-or-nothing preset mechanism with step set deferred under `DEF-39`).
**Open Items:** `OI-17` (surgical edits keyed by type; YARD documentation).

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/pipeline/builder.rb`,
  `gems/dexpace-core/sig/dexpace/pipeline/builder.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/pipeline/builder_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Pipeline::Stage`, `Dexpace::Pipeline::Stages`, `Dexpace::Pipeline::Step`, `Dexpace::Pipeline::Entry`, `Dexpace::PipelineError`.
- Produces: `Dexpace::Pipeline::Builder`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../support/probe_steps"

# PIPE-4, PIPE-5, PIPE-6, PIPE-7, PIPE-8, PIPE-18, PIPE-19, PIPE-20, PIPE-21, PIPE-22, PIPE-23,
# PIPE-24, PIPE-38, and R10's five-row precedence table. PIPE-25 and PIPE-35 are asserted through
# a built runtime and live in pipeline_test.rb (Task 8).
class DexpacePipelineBuilderTest < DexpaceTestCase
  def setup
    @transport = ->(req, opts, canc) { "ok" }
    @builder = Dexpace::Pipeline::Builder.new(transport: @transport)
  end

  test "PIPE-5 & PIPE-6: pillar exclusivity and idempotence over shared log" do
    log = []
    first = ProbeStep.new(tag: :retry, log: log)
    second = ProbeStep.new(tag: :retry, log: log)

    assert_equal(first, second, "must be value-equal")
    refute_same(first, second, "must be distinct objects")

    @builder.append(first, stage: Dexpace::Pipeline::Stages::RETRY)
    assert_equal(1, @builder.entries.size)

    # Idempotence: re-installing identical object is a no-op
    @builder.append(first, stage: Dexpace::Pipeline::Stages::RETRY)
    assert_equal(1, @builder.entries.size)

    # Collision: installing distinct object raises PipelineError naming both types
    error = assert_raises(Dexpace::PipelineError) do
      @builder.append(second, stage: Dexpace::Pipeline::Stages::RETRY)
    end
    assert_includes(error.message, "pillar retry is already occupied by ProbeStep; cannot install ProbeStep (use #replace to substitute) (PIPE-5)")
  end

  test "PIPE-8: cannot install step at terminal stage SEND" do
    step = ->(r, c) { c.call(r) }
    error = assert_raises(Dexpace::PipelineError) do
      @builder.append(step, stage: Dexpace::Pipeline::Stages::SEND)
    end
    assert_includes(error.message, "cannot install step at terminal stage SEND (PIPE-8)")
  end

  test "PIPE-18: insert_after / insert_before require matching stage and reject cross-stage" do
    step1 = ProbeStep.new(tag: :s1, log: [])
    step2 = ProbeStep.new(tag: :s2, log: [])

    @builder.append(step1, stage: Dexpace::Pipeline::Stages::PRE_AUTH)

    # Cross-stage rejection
    error = assert_raises(Dexpace::PipelineError) do
      @builder.insert_after(ProbeStep, step2, stage: Dexpace::Pipeline::Stages::AUTH)
    end
    assert_includes(error.message, "cannot insert ProbeStep declaring stage auth relative to anchor at stage pre_auth (PIPE-18)")

    # Matching stage succeeds
    @builder.insert_after(ProbeStep, step2, stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    assert_equal(2, @builder.entries.size)
    assert_same(step1, @builder.entries[0].step)
    assert_same(step2, @builder.entries[1].step)
  end

  test "PIPE-19: replace substitutes first matching anchor at same stage" do
    step1 = ProbeStep.new(tag: :old, log: [])
    step2 = ProbeStep.new(tag: :new, log: [])

    @builder.append(step1, stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    @builder.replace(ProbeStep, step2, stage: Dexpace::Pipeline::Stages::PRE_AUTH)

    assert_equal(1, @builder.entries.size)
    assert_same(step2, @builder.entries[0].step)
  end

  test "PIPE-20: remove deletes all matching instances and is no-op when absent" do
    step1 = ProbeStep.new(tag: :s1, log: [])
    step2 = ProbeStep.new(tag: :s2, log: [])

    @builder.append(step1, stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    @builder.append(step2, stage: Dexpace::Pipeline::Stages::POST_AUTH)

    @builder.remove(String) # absent, silent no-op
    assert_equal(2, @builder.entries.size)

    @builder.remove(ProbeStep)
    assert_equal(0, @builder.entries.size)
  end

  test "PIPE-21: insert or replace with missing anchor raises PipelineError" do
    step = ProbeStep.new(tag: :s1, log: [])

    error = assert_raises(Dexpace::PipelineError) do
      @builder.insert_after(String, step, stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    end
    assert_includes(error.message, "anchor step of type String was not found in pipeline (PIPE-21)")
  end

  test "PIPE-7: append adds to the tail and prepend to the head within a non-pillar stage" do
    a = ProbeStep.new(tag: :a, log: [])
    b = ProbeStep.new(tag: :b, log: [])
    c = ProbeStep.new(tag: :c, log: [])

    @builder.append(a, stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    @builder.append(b, stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    @builder.prepend(c, stage: Dexpace::Pipeline::Stages::PRE_AUTH)

    assert_equal([c, a, b], @builder.entries.map(&:step))
  end

  # PIPE-1's flattening is derived from the stage table, never from insertion order: a step in a
  # lower-ordered stage runs before one in a higher-ordered stage whatever order they were added in.
  test "PIPE-7 & PIPE-22: flattening derives from the stage table, not from insertion order" do
    late = ProbeStep.new(tag: :late, log: [])
    early = ProbeStep.new(tag: :early, log: [])

    @builder.append(late, stage: Dexpace::Pipeline::Stages::POST_SERDE)
    @builder.append(early, stage: Dexpace::Pipeline::Stages::PRE_REDIRECT)

    assert_equal([early, late], @builder.entries.map(&:step))
  end

  # R10's precedence table, all five rows. Rows 3 and 4 are the two rejections; a test that only
  # covered the accepting rows would pass against an implementation that silently resolved a
  # disagreement in either direction, which is what R10 exists to forbid.
  test "R10: the five-row precedence table for a step's stage assignment" do
    declaring = Class.new do
      def stage = Dexpace::Pipeline::Stages::RETRY
      def call(req, cur) = cur.call(req)
    end
    plain = ->(req, cur) { cur.call(req) }

    # Row 1: declares #stage, no argument -> the declared stage.
    b1 = Dexpace::Pipeline::Builder.new(transport: @transport)
    b1.append(declaring.new)
    assert_same(Dexpace::Pipeline::Stages::RETRY, b1.entries[0].stage)

    # Row 2: declares #stage, argument equal -> the declared stage.
    b2 = Dexpace::Pipeline::Builder.new(transport: @transport)
    b2.append(declaring.new, stage: Dexpace::Pipeline::Stages::RETRY)
    assert_same(Dexpace::Pipeline::Stages::RETRY, b2.entries[0].stage)

    # Row 3: declares #stage, argument DIFFERENT -> rejected, naming both.
    error = assert_raises(Dexpace::PipelineError) do
      Dexpace::Pipeline::Builder.new(transport: @transport)
                                .append(declaring.new, stage: Dexpace::Pipeline::Stages::AUTH)
    end
    assert_includes(error.message, "step declares stage retry but was installed with stage auth (R10)")

    # Row 4: declares nothing, no argument -> rejected. A lambda cannot respond to #stage
    # (verified fact 6), so this is the row every hand-written step meets first.
    error = assert_raises(Dexpace::PipelineError) do
      Dexpace::Pipeline::Builder.new(transport: @transport).append(plain)
    end
    assert_includes(error.message, "a step with no stage cannot be installed (R10)")

    # Row 5: declares nothing, argument given -> the argument.
    b5 = Dexpace::Pipeline::Builder.new(transport: @transport)
    b5.append(plain, stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    assert_same(Dexpace::Pipeline::Stages::PRE_AUTH, b5.entries[0].stage)
  end

  # R10 again, on the surgical side: stage: is required rather than inferred from the anchor,
  # because inferring it would make PIPE-18's own cross-stage rejection unreachable for a lambda.
  test "PIPE-18 / R10: a surgical edit never infers the anchor's stage for a non-declaring step" do
    @builder.append(ProbeStep.new(tag: :anchor, log: []), stage: Dexpace::Pipeline::Stages::PRE_AUTH)

    error = assert_raises(Dexpace::PipelineError) do
      @builder.insert_after(ProbeStep, ->(req, cur) { cur.call(req) })
    end
    assert_includes(error.message, "a step with no stage cannot be installed (R10)")
  end

  test "PIPE-22: determinism - an edited builder matches one built from scratch" do
    s1 = ProbeStep.new(tag: :s1, log: [])
    s2 = ProbeStep.new(tag: :s2, log: [])
    s3 = ProbeStep.new(tag: :s3, log: [])
    s4 = ProbeStep.new(tag: :s4, log: [])
    doomed = ->(req, cur) { cur.call(req) }
    pre_auth = Dexpace::Pipeline::Stages::PRE_AUTH

    # All three re-bucketing edits PIPE-22 names, then the same resulting step set from scratch.
    edited = Dexpace::Pipeline::Builder.new(transport: @transport)
    edited.append_all([s1, s2], stage: pre_auth)
    edited.append(doomed, stage: Dexpace::Pipeline::Stages::POST_AUTH)
    edited.insert_after(ProbeStep, s3, stage: pre_auth)
    edited.remove(Proc)
    edited.replace(ProbeStep, s4, stage: pre_auth)

    fresh = Dexpace::Pipeline::Builder.new(transport: @transport)
    fresh.append_all([s4, s3, s2], stage: pre_auth)

    # The flattened ENTRIES, not the response: the assertion is about ordering.
    assert_equal(fresh.entries, edited.entries)
  end

  test "PIPE-23: reload is all-or-nothing" do
    initial_entry = Dexpace::Pipeline::Entry.build(
      stage: Dexpace::Pipeline::Stages::PRE_AUTH,
      step: ProbeStep.new(tag: :orig, log: [])
    )
    @builder.append(initial_entry.step, stage: initial_entry.stage)
    snapshot = @builder.entries.dup

    invalid_entry = Object.new
    assert_raises(Dexpace::PipelineError) do
      @builder.reload([initial_entry, invalid_entry])
    end

    assert_equal(snapshot, @builder.entries, "builder entries must remain unchanged on rejected reload")
  end

  test "PIPE-24: install_preset is all-or-nothing" do
    existing = ProbeStep.new(tag: :existing, log: [])
    @builder.append(existing, stage: Dexpace::Pipeline::Stages::RETRY)
    snapshot = @builder.entries.dup

    preset_entries = [
      Dexpace::Pipeline::Entry.build(stage: Dexpace::Pipeline::Stages::REDIRECT, step: ProbeStep.new(tag: :p1, log: [])),
      Dexpace::Pipeline::Entry.build(stage: Dexpace::Pipeline::Stages::RETRY, step: ProbeStep.new(tag: :p2, log: [])),
    ]

    error = assert_raises(Dexpace::PipelineError) do
      @builder.install_preset(preset_entries)
    end
    assert_includes(error.message, "cannot install preset: pillar retry is already occupied by ProbeStep (PIPE-24)")
    assert_equal(snapshot, @builder.entries, "builder entries must remain unchanged on rejected preset")
  end

  test "PIPE-38: append_all preserves order; prepend_all reverses order" do
    s1 = ProbeStep.new(tag: :s1, log: [])
    s2 = ProbeStep.new(tag: :s2, log: [])
    s3 = ProbeStep.new(tag: :s3, log: [])

    b_append = Dexpace::Pipeline::Builder.new(transport: @transport)
    b_append.append_all([s1, s2, s3], stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    assert_equal([s1, s2, s3], b_append.entries.map(&:step))

    b_prepend = Dexpace::Pipeline::Builder.new(transport: @transport)
    b_prepend.prepend_all([s1, s2, s3], stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    assert_equal([s3, s2, s1], b_prepend.entries.map(&:step))
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline/builder_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Pipeline::Builder`.

- [ ] **Step 3: Write `lib/dexpace/pipeline/builder.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "stage"
require_relative "stages"
require_relative "step"
require_relative "entry"
require_relative "../transport"
require_relative "../async_transport"
require_relative "../error/pipeline_error"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Pipeline
    # Mutable composition builder for stage-based execution pipelines (PIPE-4, PIPE-7, PIPE-18).
    #
    # ONE builder serves both runtimes (P4-30). PIPE-28 forbids the two runtimes re-deriving
    # ordering independently, and sharing only Stages would still leave two builders duplicating
    # the surgical-edit semantics PIPE-28 also names; #build and #build_async over one bucket table
    # leave nothing to keep in sync.
    #
    # A builder is single-threaded by construction and holds no lock, exactly as phase 1's builders
    # do. The runtime it produces needs none either: it is immutable and concurrent sends read
    # frozen data (PIPE-10).
    class Builder
      attr_reader :transport

      def self.flattening(pipeline)
        builder = new(transport: pipeline.transport)
        pipeline.entries.each do |entry|
          builder.append(entry.step, stage: entry.stage)
        end
        builder
      end

      def self.nesting(pipeline)
        new(transport: pipeline)
      end

      def initialize(transport:)
        @transport = transport
        @buckets = Stages::ALL.each_with_object({}) do |stage, map|
          map[stage] = [] unless stage.terminal?
        end
      end

      def append(step, stage: nil)
        target_stage = resolve_stage(step, stage)
        check_pillar_exclusivity!(target_stage, step) do
          @buckets[target_stage] << Entry.build(stage: target_stage, step:)
        end
        self
      end

      def prepend(step, stage: nil)
        target_stage = resolve_stage(step, stage)
        check_pillar_exclusivity!(target_stage, step) do
          @buckets[target_stage].unshift(Entry.build(stage: target_stage, step:))
        end
        self
      end

      def append_all(steps, stage: nil)
        steps.each { |s| append(s, stage:) }
        self
      end

      # PIPE-38's asymmetry, and the requirement's own words are "a port MUST document this
      # asymmetry so callers get predictable ordering": prepend_all prepends each element
      # INDIVIDUALLY, so [a, b, c] ends up c, b, a within the stage, while append_all preserves the
      # batch's order. The reversal is a consequence of the definition rather than a special case,
      # and it is here in prose because a caller reading the signature alone would expect [a, b, c].
      def prepend_all(steps, stage: nil)
        steps.each { |s| prepend(s, stage:) }
        self
      end

      # PIPE-18. The anchor is the FIRST step in flattened order that is an instance of anchor_type.
      #
      # OI-17: the four surgical edits are keyed by step TYPE, and every lambda step has the class
      # Proc (verified fact 13) -- so in a pipeline holding two lambdas, insert_after(Proc, ...)
      # anchors on whichever flattens first and remove(Proc) deletes both. A step intended as an
      # anchor should be a named class. There is no repair inside this API; the finding is filed.
      def insert_after(anchor_type, step, stage: nil)
        anchor_entry, bucket = find_anchor(anchor_type)
        target_stage = resolve_surgical_stage(step, stage, anchor_entry.stage)

        idx = bucket.index(anchor_entry)
        bucket.insert(idx + 1, Entry.build(stage: target_stage, step:))
        self
      end

      def insert_before(anchor_type, step, stage: nil)
        anchor_entry, bucket = find_anchor(anchor_type)
        target_stage = resolve_surgical_stage(step, stage, anchor_entry.stage)

        idx = bucket.index(anchor_entry)
        bucket.insert(idx, Entry.build(stage: target_stage, step:))
        self
      end

      def replace(anchor_type, step, stage: nil)
        anchor_entry, bucket = find_anchor(anchor_type)
        target_stage = resolve_surgical_stage(step, stage, anchor_entry.stage)

        idx = bucket.index(anchor_entry)
        bucket[idx] = Entry.build(stage: target_stage, step:)
        self
      end

      def remove(anchor_type)
        @buckets.each_value do |bucket|
          bucket.reject! { |entry| entry.step.is_a?(anchor_type) }
        end
        self
      end

      def reload(entries)
        validated = validate_reload_entries(entries)
        @buckets.each_value(&:clear)
        validated.each do |entry|
          @buckets[entry.stage] << entry
        end
        self
      end

      # PIPE-24. Empty target pillars ONLY, validated up front, the WHOLE call rejected on any
      # collision, never an overlay. It shares validate-then-commit with #reload (PIPE-23) so
      # "all-or-nothing" is one code path and the two requirements cannot drift.
      #
      # R14/P4-34: this is the mechanism and there is no standard step SET behind it. The redirect
      # and retry families are phase 6's and the instrumentation step is phase 5's, so
      # Pipeline.standard defers under DEF-39 rather than shipping a constructor named for defaults
      # it cannot install. Phase 6 writes that constructor OVER this method.
      def install_preset(entries)
        validated = validate_reload_entries(entries)
        occupied = validated.filter_map do |entry|
          next unless entry.stage.pillar?

          existing = @buckets[entry.stage].first
          "pillar #{entry.stage.name} is already occupied by #{existing.step.class}" if existing
        end

        unless occupied.empty?
          raise Dexpace::PipelineError, "cannot install preset: #{occupied.join('; ')} (PIPE-24)"
        end

        validated.each do |entry|
          @buckets[entry.stage] << entry
        end
        self
      end

      def entries
        Stages::ALL.flat_map { |stage| @buckets[stage] || [] }.freeze
      end

      # PIPE-25. Flatten once into an immutable runtime. SyncDriver and AsyncDriver are
      # private_constants of Dexpace::Pipeline and resolve unqualified HERE, because Builder is
      # nested inside that class -- which is why the driver travels to the runtime as a constructor
      # argument rather than being named from Dexpace::AsyncPipeline, where it is unreachable
      # (plan open question 9).
      def build
        validate_transport!(Dexpace::Transport, "transport")
        Pipeline.send(:new, entries:, transport: @transport, driver_class: SyncDriver)
      end

      # The discriminator between a sync and an async pipeline is WHICH METHOD THE CALLER CALLED,
      # and that is documented rather than checked: Transport.conforms? and AsyncTransport.conforms?
      # are one predicate over #parameters, so neither can tell the two seams apart -- they differ
      # only in return type (P4-30's cost cell, phase 2's admitted gap at a second seam).
      def build_async
        validate_transport!(Dexpace::AsyncTransport, "async transport")
        AsyncPipeline.send(:new, entries:, transport: @transport, driver_class: AsyncDriver)
      end

      private

      def resolve_stage(step, explicit_stage)
        declared = step.respond_to?(:stage) ? step.stage : nil
        if declared
          declared_stage = declared.is_a?(Stage) ? declared : Stages.of(declared)
          if explicit_stage
            given_stage = explicit_stage.is_a?(Stage) ? explicit_stage : Stages.of(explicit_stage)
            if declared_stage != given_stage
              raise Dexpace::PipelineError, "step declares stage #{declared_stage.name} but was installed with stage #{given_stage.name} (R10)"
            end
          end
          check_not_terminal!(declared_stage)
          declared_stage
        elsif explicit_stage
          given_stage = explicit_stage.is_a?(Stage) ? explicit_stage : Stages.of(explicit_stage)
          check_not_terminal!(given_stage)
          given_stage
        else
          raise Dexpace::PipelineError,
                "step does not declare #stage and no stage: keyword was given; " \
                "a step with no stage cannot be installed (R10)"
        end
      end

      def resolve_surgical_stage(step, explicit_stage, anchor_stage)
        target_stage = if step.respond_to?(:stage) && step.stage
                         declared = step.stage.is_a?(Stage) ? step.stage : Stages.of(step.stage)
                         if declared != anchor_stage
                           raise Dexpace::PipelineError, "cannot insert #{step.class} declaring stage #{declared.name} relative to anchor at stage #{anchor_stage.name} (PIPE-18)"
                         end
                         declared
                       elsif explicit_stage
                         given = explicit_stage.is_a?(Stage) ? explicit_stage : Stages.of(explicit_stage)
                         if given != anchor_stage
                           raise Dexpace::PipelineError, "cannot insert #{step.class} declaring stage #{given.name} relative to anchor at stage #{anchor_stage.name} (PIPE-18)"
                         end
                         given
                       else
                         # stage: is REQUIRED on a surgical edit for a step that declares nothing,
                         # and is never inferred from the anchor. Inferring it would make PIPE-18's
                         # and PIPE-19's own cross-stage rejection unreachable for exactly the step
                         # shape design section 5.1 guarantees is legal -- a lambda.
                         raise Dexpace::PipelineError,
                               "step does not declare #stage and no stage: keyword was given; " \
                               "a step with no stage cannot be installed (R10)"
                       end
        check_not_terminal!(target_stage)
        target_stage
      end

      def check_not_terminal!(stage)
        if stage.terminal?
          raise Dexpace::PipelineError, "cannot install step at terminal stage SEND (PIPE-8)"
        end
      end

      def check_pillar_exclusivity!(stage, step)
        if stage.pillar? && !@buckets[stage].empty?
          existing = @buckets[stage].first
          if existing.step.equal?(step)
            return # Idempotent (PIPE-6)
          else
            raise Dexpace::PipelineError, "pillar #{stage.name} is already occupied by #{existing.step.class}; cannot install #{step.class} (use #replace to substitute) (PIPE-5)"
          end
        end
        yield
      end

      def find_anchor(anchor_type)
        Stages::ALL.each do |stage|
          next if stage.terminal?

          bucket = @buckets[stage]
          match = bucket.find { |entry| entry.step.is_a?(anchor_type) }
          return [match, bucket] if match
        end

        raise Dexpace::PipelineError, "anchor step of type #{anchor_type} was not found in pipeline (PIPE-21)"
      end

      def validate_reload_entries(entries)
        unless entries.is_a?(::Array)
          raise Dexpace::PipelineError, "cannot reload pipeline entries: entries must be an Array (PIPE-23)"
        end

        entries.map do |entry|
          unless entry.is_a?(Entry)
            raise Dexpace::PipelineError, "cannot reload pipeline entries: invalid entry #{entry.inspect} (PIPE-23)"
          end
          entry
        end
      end

      # Plan open question 4: phase 2's own predicate, not a local respond_to?(:call). Both seams
      # reduce to Dexpace::Registry.callable?(object, arity: 3), so the arity check comes for free
      # and there is one shape predicate in the repository rather than two.
      def validate_transport!(seam, label)
        return if seam.conforms?(@transport)

        raise Dexpace::InvalidArgumentError,
              "a #{label} responds to #call(request, options, cancellation); " \
              "#{@transport.class} does not"
      end
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/pipeline/builder.rbs`**

```rbs
module Dexpace
  class Pipeline
    class Builder
      def self.flattening: (Pipeline pipeline) -> Builder
      def self.nesting: (Pipeline pipeline) -> Builder

      attr_reader transport: untyped

      def initialize: (transport: untyped) -> void
      def append: (untyped step, ?stage: Stage | Symbol | nil) -> self
      def prepend: (untyped step, ?stage: Stage | Symbol | nil) -> self
      def append_all: (Array[untyped] steps, ?stage: Stage | Symbol | nil) -> self
      def prepend_all: (Array[untyped] steps, ?stage: Stage | Symbol | nil) -> self
      def insert_after: (singleton(Object) anchor_type, untyped step, ?stage: Stage | Symbol | nil) -> self
      def insert_before: (singleton(Object) anchor_type, untyped step, ?stage: Stage | Symbol | nil) -> self
      def replace: (singleton(Object) anchor_type, untyped step, ?stage: Stage | Symbol | nil) -> self
      def remove: (singleton(Object) anchor_type) -> self
      def reload: (Array[Entry] entries) -> self
      def install_preset: (Array[Entry] entries) -> self
      def entries: () -> Array[Entry]
      def build: () -> Pipeline
      def build_async: () -> AsyncPipeline
    end
  end
end
```

- [ ] **Step 5: Add the require to `lib/dexpace.rb`**

Positioned after drivers: `require_relative "dexpace/pipeline/builder"`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline/builder_test.rb`
Expected: PASS, 14 runs, 0 failures, 0 errors.

---

## Task 8: `Dexpace::Pipeline` Sync Runtime

**Requirement IDs:** `PIPE-1`, `PIPE-2`, `PIPE-9`, `PIPE-10`, `PIPE-11` (the concurrency clause),
`PIPE-25`, `PIPE-26`, `PIPE-27`, `PIPE-33` (clauses 1–4; clause 5 is `DEF-18`), `PIPE-34`, `PIPE-35`,
`PIPE-39` (the `direct` half).
**Design:** "`Dexpace::Pipeline` — `PIPE-9`, `PIPE-10`, `PIPE-25`, `PIPE-26`, `PIPE-27`, `PIPE-39`", R12, R13.
**Deviations:** P4-27 (public Pipeline methods), P4-35 (4c ships no bridge; reuses phase 2 bridges under `DEF-28`).
**Verified Facts:** Fact 2 (transport conformance of Pipeline), Fact 8 (frozen Array returns), Fact 11 (`ObjectSpace` count with `GC.disable`).

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/pipeline.rb`,
  `gems/dexpace-core/sig/dexpace/pipeline.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/pipeline_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Closeable`, `Dexpace::RequestOptions`, `Dexpace::Cancellation`.
- Produces: `Dexpace::Pipeline`, `.builder`, `.direct`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "support/probe_steps"
require_relative "support/fake_executor"
require_relative "support/fake_async_transport"

# PIPE-1, PIPE-2, PIPE-9, PIPE-10, PIPE-25, PIPE-26, PIPE-27, PIPE-33, PIPE-34, PIPE-35, PIPE-39.
class DexpacePipelineTest < DexpaceTestCase
  def setup
    @transport = ->(req, opts, canc) { "response_from_wire" }
    @request = "req"
  end

  # PIPE-1's conformance clause verbatim: one probe per stage, SEND excluded, installed in a
  # SHUFFLED order. Installing them in declaration order would pass against an implementation that
  # preserved insertion order and derived nothing from the stage table, which is the one thing
  # PIPE-1 forbids. The seed is pinned and named in the failure message (testing/7ece0212).
  PIPE_1_SEED = 42

  test "PIPE-1: fifteen probes installed in shuffled order execute in strict stage order" do
    log = []
    stages_15 = Dexpace::Pipeline::Stages::ALL.reject(&:terminal?)
    assert_equal(15, stages_15.size)

    rng = Random.new(PIPE_1_SEED)
    shuffled = stages_15.shuffle(random: rng)

    builder = Dexpace::Pipeline.builder(transport: @transport)
    shuffled.each { |st| builder.append(ProbeStep.new(tag: st.name, log:), stage: st) }
    builder.build.call(@request)

    expected = stages_15.map { |st| [:enter, st.name] } +
               stages_15.reverse.map { |st| [:exit, st.name] }

    assert_equal(expected, log, "install order was #{shuffled.map(&:name).inspect} under seed #{PIPE_1_SEED}")
  end

  # PIPE-2's conformance clause verbatim, and the assertion that would fail if PRE_REDIRECT were
  # ordered INSIDE the redirect loop. It is the same fact PIPE-37 and design section 6.2 both rest on.
  test "PIPE-2: PRE_REDIRECT probe runs once while AUTH probe runs twice under forking REDIRECT" do
    pre_redirect_runs = 0
    auth_runs = 0

    pre_step = lambda do |r, c|
      pre_redirect_runs += 1
      c.call(r)
    end
    auth_step = lambda do |r, c|
      auth_runs += 1
      c.call(r)
    end

    builder = Dexpace::Pipeline.builder(transport: @transport)
    builder.append(pre_step, stage: Dexpace::Pipeline::Stages::PRE_REDIRECT)
    builder.append(ForkingProbe.new(times: 2), stage: Dexpace::Pipeline::Stages::REDIRECT)
    builder.append(auth_step, stage: Dexpace::Pipeline::Stages::AUTH)
    builder.build.call(@request)

    assert_equal(1, pre_redirect_runs, "PRE_REDIRECT runs OUTSIDE the redirect loop (PIPE-2)")
    assert_equal(2, auth_runs, "AUTH runs once per fork (PIPE-2)")
  end

  test "PIPE-9: empty pipeline dispatches straight to the transport, threading the caller's arguments" do
    options = Object.new.freeze
    cancellation = Object.new.freeze
    recorded = nil
    mock_transport = lambda do |r, o, c|
      recorded = { r:, o:, c: }
      "wire_res"
    end

    res = Dexpace::Pipeline.direct(mock_transport).call(@request, options, cancellation)

    assert_equal("wire_res", res)
    assert_same(@request, recorded[:r])
    assert_same(options, recorded[:o])
    assert_same(cancellation, recorded[:c])
  end

  # R12, the two allocation deltas. PIPE-9's trailing SHOULD is testable as a NON-allocation rather
  # than only as a behaviour (verified fact 11), and the non-empty delta is the assertion that would
  # fail if someone "optimised" the empty branch into the general one and removed the cursor
  # everywhere. ObjectSpace counting is CRuby-specific; no v1 matrix row is non-CRuby (DEF-33).
  test "PIPE-9 & PIPE-10: empty pipeline allocates no cursor; a one-step pipeline allocates one" do
    empty_pipe = Dexpace::Pipeline.direct(@transport)

    stepped = Dexpace::Pipeline.builder(transport: @transport)
    stepped.append(ProbeStep.new(tag: :s1, log: []), stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    stepped_pipe = stepped.build

    GC.disable
    begin
      before_empty = ObjectSpace.each_object(Dexpace::Pipeline::Cursor).count
      empty_pipe.call(@request)
      after_empty = ObjectSpace.each_object(Dexpace::Pipeline::Cursor).count

      before_stepped = ObjectSpace.each_object(Dexpace::Pipeline::Cursor).count
      stepped_pipe.call(@request)
      after_stepped = ObjectSpace.each_object(Dexpace::Pipeline::Cursor).count
    ensure
      GC.enable
    end

    assert_equal(0, after_empty - before_empty, "empty pipeline must not allocate a cursor (PIPE-9, DEF-33)")
    assert_operator(after_stepped - before_stepped, :>=, 1, "a non-empty pipeline MUST allocate a cursor (PIPE-10)")
  end

  # PIPE-26: the runtime IS the transport SPI, with and without per-call options (verified fact 2).
  # Nothing on Pipeline declares this; it is true of the #call signature, which is why the
  # assertion is phase 2's own predicate rather than an is_a? check.
  test "PIPE-26: a built pipeline conforms to the transport seam and takes one or three arguments" do
    builder = Dexpace::Pipeline.builder(transport: @transport)
    builder.append(ProbeStep.new(tag: :s1, log: []), stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    pipeline = builder.build

    assert(Dexpace::Transport.conforms?(pipeline))
    assert_equal("response_from_wire", pipeline.call(@request))
    assert_equal(
      "response_from_wire",
      pipeline.call(@request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
    )
  end

  test "PIPE-10: non-empty pipeline allocates cursors and shares no mutable state across 16 threads" do
    builder = Dexpace::Pipeline.builder(transport: @transport)
    seen_cursors = {}
    seen_cursors.compare_by_identity
    mutex = Mutex.new

    step = lambda do |r, c|
      mutex.synchronize { seen_cursors[c] = true }
      c.call(r)
    end
    builder.append(step, stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    pipeline = builder.build

    threads = 16.times.map do
      Thread.new { pipeline.call(@request) }
    end
    threads.each(&:join)

    assert_equal(16, seen_cursors.size, "16 concurrent calls must allocate 16 distinct cursors (PIPE-10)")
  end

  # PIPE-25's read-only ordered view, and PIPE-10's "immutable after construction" alongside it.
  # A frozen Array built once and returned by the same reference every call -- design section 10.11's
  # computed-once rule, never a per-access dup, a wrapper, or a lazy Enumerator (an Enumerator
  # abandoned mid-#next never runs its ensure, and this is where it would be the idiomatic answer).
  #
  # `pipeline.frozen?` is deliberately NOT asserted: PIPE-27's close latch writes an ivar, so a
  # frozen runtime would raise FrozenError on #close (plan open question 8). The absence of any
  # writer is asserted instead, which is what that assertion was protecting.
  test "PIPE-25 & PIPE-10: steps and entries are frozen, computed once, and the runtime has no writer" do
    builder = Dexpace::Pipeline.builder(transport: @transport)
    builder.append(ProbeStep.new(tag: :s1, log: []), stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    pipeline = builder.build

    assert_predicate(pipeline.steps, :frozen?)
    assert_predicate(pipeline.entries, :frozen?)
    assert_same(pipeline.steps, pipeline.steps)
    assert_same(pipeline.entries, pipeline.entries)
    assert_raises(FrozenError) { pipeline.steps << :extra }
    assert_empty(Dexpace::Pipeline.public_instance_methods(false).grep(/=\z/))
  end

  test "PIPE-27: close latches, is idempotent, and never cascades to the terminal transport" do
    transport = Class.new do
      def initialize = @closed = false
      def call(_r, _o, _c) = "res"
      def close = @closed = true
      def closed? = @closed
    end.new

    pipeline = Dexpace::Pipeline.direct(transport)
    pipeline.close
    pipeline.close

    assert_predicate(pipeline, :closed?)
    refute_predicate(pipeline, :owned?)
    # The NEGATIVE is the assertion: a test that closed once and checked nothing would pass against
    # a cascading close.
    refute_predicate(transport, :closed?, "pipeline close must not cascade to transport (PIPE-27)")
  end

  test "PIPE-33: async_over posts the whole pipeline once as a single opaque unit" do
    builder = Dexpace::Pipeline.builder(transport: @transport)
    5.times { |i| builder.append(ProbeStep.new(tag: :"p#{i}", log: []), stage: Dexpace::Pipeline::Stages::PRE_AUTH) }
    pipeline = builder.build

    options = Dexpace::RequestOptions::EMPTY
    executor = FakeExecutor.new
    async_bridge = Dexpace::Transport.async_over(pipeline, executor:)
    future = async_bridge.call(@request, options, Dexpace::Cancellation.none)

    # Clause 2: the wrapped pipeline runs as ONE unit; its five steps never see the executor.
    assert_equal(1, executor.posts, "a five-step pipeline is one #post (PIPE-33)")
    assert_equal("response_from_wire", future.value)
    # Clause 1 is met by an absence: core ships no executor and this phase adds no default. Clause 5,
    # interrupt-mode cancellation, is the unsatisfied one -- DEF-18 and design section 10.5 -- and
    # there is no test of it because there is no interrupt mode to test.
  end

  test "PIPE-34: sync_over blocks on the async result and surfaces a cancelled token as CancelledError" do
    async_transport = FakeAsyncTransport.new(response: "async_wire_res")
    builder = Dexpace::Pipeline::Builder.new(transport: async_transport)
    builder.append(ProbeStep.new(tag: :p1, log: []), stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    async_pipeline = builder.build_async

    options = Dexpace::RequestOptions::EMPTY
    sync_bridge = Dexpace::AsyncTransport.sync_over(async_pipeline)

    assert_equal("async_wire_res", sync_bridge.call(@request, options, Dexpace::Cancellation.none))
    assert_same(options, async_transport.calls.last[:options], "per-call options survive the bridge (PIPE-34)")

    # A cancelled token raises rather than blocking. The future must still be IN FLIGHT for the
    # token to be observed at all -- Future#await returns immediately on a settled one -- which is
    # what the fake's defer: mode is for. There is no interrupt-mode case here because there is no
    # interrupt mode: DEF-18 and design section 10.5.
    deferred = FakeAsyncTransport.new(defer: true)
    deferred_pipeline = Dexpace::Pipeline::Builder.new(transport: deferred).build_async
    source = Dexpace::Cancellation::Source.new
    source.cancel(:client_abort)

    error = assert_raises(Dexpace::CancelledError) do
      Dexpace::AsyncTransport.sync_over(deferred_pipeline).call(@request, options, source.token)
    end
    assert_equal(:client_abort, error.reason)
  end

  test "PIPE-35: FLATTEN vs NEST behaviour distinction" do
    log_flatten = []
    log_nest = []

    # Base pipeline with REDIRECT forking twice
    base_b = Dexpace::Pipeline.builder(transport: @transport)
    base_b.append(ForkingProbe.new(times: 2), stage: Dexpace::Pipeline::Stages::REDIRECT)
    base_pipeline = base_b.build

    # Flattening: new probe at PRE_RETRY runs 2 times (inside redirect loop)
    flat_b = Dexpace::Pipeline::Builder.flattening(base_pipeline)
    flat_b.append(ProbeStep.new(tag: :probe, log: log_flatten), stage: Dexpace::Pipeline::Stages::PRE_RETRY)
    flat_pipeline = flat_b.build
    flat_pipeline.call(@request)
    enters_flatten = log_flatten.count { |entry| entry == [:enter, :probe] }
    assert_equal(2, enters_flatten, "under FLATTEN, step inside redirect loop runs twice (PIPE-35)")

    # Nesting: new probe at PRE_RETRY runs 1 time (outer to nested pipeline)
    nest_b = Dexpace::Pipeline::Builder.nesting(base_pipeline)
    nest_b.append(ProbeStep.new(tag: :probe, log: log_nest), stage: Dexpace::Pipeline::Stages::PRE_RETRY)
    nest_pipeline = nest_b.build
    nest_pipeline.call(@request)
    enters_nest = log_nest.count { |entry| entry == [:enter, :probe] }
    assert_equal(1, enters_nest, "under NEST, step outside nested pipeline runs once (PIPE-35)")
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline_test.rb`
Expected: FAIL — `undefined method 'builder' for class Dexpace::Pipeline`.

- [ ] **Step 3: Write `lib/dexpace/pipeline.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "closeable"
require_relative "request_options"
require_relative "cancellation"

module Dexpace
  # Synchronous stage-based execution pipeline. It IS a transport (PIPE-26): #call is exactly the
  # transport SPI's three positional parameters, with and without per-call options, so a built
  # pipeline stands in wherever a transport is expected -- backing a paginator (phase 7), nested as
  # another builder's transport (PIPE-35 NEST), or wrapped by a bridge.
  #
  # **PIPE-33 and PIPE-34 need nothing from this class** (R13, P4-35). Because a pipeline is a
  # transport, phase 2's Dexpace::Transport.async_over(pipeline, executor:) IS the sync-to-async
  # bridge and Dexpace::AsyncTransport.sync_over(async_pipeline) IS the async-to-sync one. This
  # phase ships no second bridge, no executor, and no wait of any kind; a reader looking here for a
  # PIPE-33 object will find none, and that is the answer rather than an omission.
  class Pipeline
    include Dexpace::Closeable

    attr_reader :entries, :steps, :transport

    private_class_method :new

    def self.builder(transport:)
      Builder.new(transport:)
    end

    # PIPE-39's first named shape: a step-less pipeline that forwards directly to a transport. The
    # second, Pipeline.standard, defers under DEF-39 -- the redirect and retry families are phase
    # 6's and the instrumentation step is phase 5's, and a constructor named for defaults it cannot
    # install is worse than its absence. Builder#install_preset is the mechanism it will be written
    # over.
    def self.direct(transport)
      Builder.new(transport:).build
    end

    # NOT Object#freeze'd, deliberately: PIPE-27's close latches, and Closeable#close writes
    # @dexpace_closed, so a frozen runtime would raise FrozenError on the first #close. PIPE-10's
    # "immutable after construction (fixed ordered step collection + fixed transport reference)" is
    # met by the two frozen Arrays, the write-once transport and the absence of any writer, which is
    # what the suite asserts instead (plan open question 8).
    def initialize(entries:, transport:, driver_class:)
      initialize_closeable(owned: false)
      @entries = entries.dup.freeze
      @steps = @entries.map(&:step).freeze
      @transport = transport
      @driver_class = driver_class
    end

    def call(request, options = RequestOptions::EMPTY, cancellation = Cancellation.none)
      # PIPE-9's MUST and its trailing SHOULD in one branch: an empty pipeline has no step to hand
      # a cursor to and therefore no per-call mutable state to share, so PIPE-10's guarantee holds
      # with no cursor allocated at all. There is no reading under which a NON-empty pipeline may
      # skip the cursor (R12).
      return @transport.call(request, options, cancellation) if @entries.empty?

      Cursor.build(
        drive: @driver_class.new(self),
        request:,
        options:,
        cancellation:
      ).call(request)
    end
  end
end
```

**`#close` is inherited whole and this class defines no `#release`** — phase 2's shape for both
bridges, unchanged. `initialize_closeable(owned: false)` is what makes `Closeable#close` flip the
latch and `return` before it would call `#release`, so `PIPE-27`'s "the pipeline never owns its
transport and MUST NOT close it" is a property of the ownership flag rather than of an override
someone could later delete. A `#release` here would be dead code that reads like a cascade point.

- [ ] **Step 4: Write `sig/dexpace/pipeline.rbs`**

```rbs
module Dexpace
  class Pipeline
    include Dexpace::Closeable

    def self.builder: (transport: untyped) -> Builder
    def self.direct: (untyped transport) -> Pipeline

    # .new and #initialize are absent deliberately: new is private and driver_class: is an argument
    # only Builder can supply, so neither is public surface NFR-4 locks.

    attr_reader entries: Array[Entry]
    attr_reader steps: Array[untyped]
    attr_reader transport: untyped

    def call: (Dexpace::Request request, ?Dexpace::RequestOptions options, ?Dexpace::Cancellation cancellation) -> Dexpace::Response
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Positioned first among the nested pipeline set: `require_relative "dexpace/pipeline"`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline_test.rb`
Expected: PASS, 11 runs, 0 failures, 0 errors.

---

## Task 9: `Dexpace::Pipeline::TransformStep` (4b Adapter)

**Requirement IDs:** `PIPE-37`, spec-forced boundaries 1 and 5.
**Design:** "The generic adapter — how 4c consumes 4b's `Transform` contract", `PIPE-37`.
**Deviations:** P4-26 (public constant `TransformStep`), P4-27 (`TransformStep.build`).
**Verified Facts:** Fact 12 (`TransformStep` calls `#apply` and never `#call`).

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/pipeline/transform_step.rb`,
  `gems/dexpace-core/sig/dexpace/pipeline/transform_step.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/pipeline/transform_step_test.rb`

**Interfaces:**
- Consumes: phase 4b's `Dexpace::Recovery::Transform` contract (`#phase`, `#apply`).
- Produces: `Dexpace::Pipeline::TransformStep`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../support/probe_steps"

# PIPE-37, boundary 1, boundary 5, verified fact 12.
class DexpacePipelineTransformStepTest < DexpaceTestCase
  class DummyTransform
    attr_reader :phase, :applied

    def initialize(phase)
      @phase = phase
      @applied = false
    end

    def apply(val)
      @applied = true
      "transformed_#{val}"
    end

    def call(_val)
      raise "must never be called (verified fact 12)"
    end
  end

  # PIPE-37's parenthesis is "body not read, consumed, or closed", so the double has to be able to
  # observe all three. #close is real because ForkingProbe releases each superseded intermediate
  # (PIPE-40) and a response with no #close would let that go unnoticed.
  class DummyTerminalResponse
    attr_reader :source_called

    def initialize
      @source_called = false
      @closed = false
    end

    def body = self

    def source
      @source_called = true
    end

    def close = @closed = true
    def closed? = @closed
  end

  test ".build validates that transform responds to #phase and #apply" do
    bad = Object.new
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Pipeline::TransformStep.build(bad)
    end
  end

  test ".build validates that #phase is :request or :response" do
    # R8 clause 2's "neither may add a third phase", made mechanical on this side. The specific
    # mistake it catches: a phase naming the recovery-STEP list -- a recovery step is
    # Outcome -> Outcome and is not a transform at all, and no Outcome ever crosses into PIPE.
    invalid_phase = Class.new do
      def phase = :recovery
      def apply(value) = value
    end.new

    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Pipeline::TransformStep.build(invalid_phase)
    end
  end

  test "calls #apply and never #call per verified fact 12" do
    req_tx = DummyTransform.new(:request)
    step = Dexpace::Pipeline::TransformStep.build(req_tx)
    cursor = Class.new { def call(r) = "handled_#{r}" }.new

    res = step.call("data", cursor)
    assert_equal(true, req_tx.applied)
    assert_equal("handled_transformed_data", res)
  end

  test "PIPE-37: installed at PRE_REDIRECT runs once with terminal response, body unread" do
    responses = []
    transport = lambda do |_r, _o, _c|
      response = DummyTerminalResponse.new
      responses << response
      response
    end

    transform = Class.new do
      attr_reader :runs

      def initialize = @runs = 0
      def phase = :response

      def apply(res)
        @runs += 1
        res
      end
    end.new

    tx_step = Dexpace::Pipeline::TransformStep.build(transform)
    builder = Dexpace::Pipeline.builder(transport:)
    builder.append(tx_step, stage: Dexpace::Pipeline::Stages::PRE_REDIRECT)
    builder.append(ForkingProbe.new(times: 2), stage: Dexpace::Pipeline::Stages::REDIRECT)

    pipeline = builder.build
    res = pipeline.call("req")

    # The REDIRECT probe drives twice, so two responses reach the wire and the PRE_REDIRECT slot
    # still sees exactly one -- the terminal one. Placement alone would not catch a wrapper that
    # re-invoked the outer slot per hop; this is the test that does.
    assert_equal(2, responses.size)
    assert_same(responses.last, res)
    assert_equal(1, transform.runs, "PRE_REDIRECT transform must run exactly once (PIPE-37)")
    refute(res.source_called, "on a non-error status the response is returned untouched (PIPE-37)")
    refute_predicate(res, :closed?, "the response handed back is not closed (PIPE-37, PIPE-40)")
  end

  test "TransformStep declares no #stage: one wrapper serves transforms whose placements differ" do
    step = Dexpace::Pipeline::TransformStep.build(DummyTransform.new(:request))

    refute_respond_to(step, :stage)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline/transform_step_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Pipeline::TransformStep`.

- [ ] **Step 3: Write `lib/dexpace/pipeline/transform_step.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "step"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Pipeline
    # Generic adapter wrapping phase 4b's Transform contract into the stage pipeline (R8, PIPE-37).
    # Resolves phase once at build time and invokes #apply rather than #call (verified fact 12).
    class TransformStep
      attr_reader :transform

      private_class_method :new

      # #phase is read ONCE, here, and the branch is chosen from the value read then -- the same
      # composition-time discipline #fork follows (R10), reached from the other direction. #call
      # never asks again, so a transform that changes its mind changes nothing.
      def self.build(transform)
        unless transform.respond_to?(:phase) && transform.respond_to?(:apply)
          raise Dexpace::InvalidArgumentError, "transform must respond to #phase and #apply"
        end

        phase = transform.phase
        unless phase == :request || phase == :response
          raise Dexpace::InvalidArgumentError,
                "transform #phase must return :request or :response, got #{phase.inspect}"
        end

        new(transform: transform, phase: phase)
      end

      def initialize(transform:, phase:)
        @transform = transform
        @phase = phase
      end

      # Calls #apply and NEVER #call. 4b's R8 clause 5 asks for exactly this, "so a future default
      # on #call cannot change what the pipeline does" -- Transform's module supplies
      # `def call(value) = apply(value)` as the recovery chain's step protocol, and this layer must
      # not ride on it.
      #
      # This class declares no #stage, deliberately. One wrapper serves three transforms whose
      # correct placements differ -- PIPE-37 requires the error-mapping transform at PRE_REDIRECT,
      # outside every fork, while an idempotency-key transform belongs at or before PRE_RETRY so a
      # re-attempt reuses the key -- and a #stage here would be a stage for the wrapper rather than
      # for what it wraps. The stage is named at install (R10). 4c cannot know which caller-supplied
      # transforms are terminal-response dependent, so PIPE-37's placement is documented on
      # Stages::PRE_REDIRECT and here, and is not enforced.
      def call(request, cursor)
        if @phase == :request
          cursor.call(@transform.apply(request))
        else
          @transform.apply(cursor.call(request))
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/pipeline/transform_step.rbs`**

```rbs
module Dexpace
  class Pipeline
    class TransformStep
      def self.build: (untyped transform) -> TransformStep

      attr_reader transform: untyped

      def call: (Dexpace::Request request, Dexpace::Pipeline::Cursor cursor) -> Dexpace::Response
    end
  end
end
```

- [ ] **Step 5: Add the require to `lib/dexpace.rb`**

Positioned after `builder.rb`: `require_relative "dexpace/pipeline/transform_step"`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline/transform_step_test.rb`
Expected: PASS, 5 runs, 0 failures, 0 errors.

---

## Task 10: `Dexpace::AsyncPipeline` Async Runtime and `map_response`

**Requirement IDs:** `PIPE-28`, `PIPE-29`, `PIPE-30`, `PIPE-31`, `PIPE-32`, `PIPE-39` (async direct).
**Design:** "`Dexpace::AsyncPipeline` — `PIPE-28`–`PIPE-32`", P4-36, P4-38.
**Deviations:** P4-26 (`AsyncPipeline` flat constant), P4-30 (shared Cursor and Builder), P4-36 (flat namespace), P4-38 (`AsyncPipeline.map_response` class method).
**Verified Facts:** Fact 2 (predicate accepting AsyncPipeline), Fact 7 (bare raise re-raising fatal exceptions).

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/async_pipeline.rb`,
  `gems/dexpace-core/sig/dexpace/async_pipeline.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/async_pipeline_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Pipeline::Stages`, `Dexpace::Pipeline::Cursor`, `Dexpace::Async::Completer`, `Dexpace::Async::Future`.
- Produces: `Dexpace::AsyncPipeline`, `.direct`, `.map_response`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "support/probe_steps"
require_relative "support/fake_async_transport"

# PIPE-28, PIPE-29, PIPE-30, PIPE-31, PIPE-32, PIPE-39.
class DexpaceAsyncPipelineTest < DexpaceTestCase
  def setup
    @transport = FakeAsyncTransport.new(response: "async_wire_res")
    @request = "req"
  end

  # PIPE-28's "MUST NOT each re-derive ordering independently", asserted stage-for-stage and
  # step-for-step BY IDENTITY over the whole table rather than on its first row -- one Stages, one
  # Builder, one flatten (P4-30).
  test "PIPE-28: #build and #build_async produce identical entry tables by identity" do
    builder = Dexpace::Pipeline::Builder.new(transport: @transport)
    builder.append(->(r, c) { c.call(r) }, stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    builder.append(ProbeStep.new(tag: :redirect, log: []), stage: Dexpace::Pipeline::Stages::REDIRECT)
    builder.append(ProbeStep.new(tag: :post, log: []), stage: Dexpace::Pipeline::Stages::POST_SERDE)

    sync_entries = builder.build.entries
    async_entries = builder.build_async.entries

    assert_equal(3, sync_entries.size)
    assert_equal(sync_entries.size, async_entries.size)
    sync_entries.zip(async_entries).each do |sync_entry, async_entry|
      assert_same(sync_entry.stage, async_entry.stage)
      assert_same(sync_entry.step, async_entry.step)
    end
  end

  test "PIPE-29 & PIPE-30: synchronous StandardError is normalised to failed Future; ScriptError raises" do
    sync_fail_step = ->(_r, _c) { raise "standard error in step" }
    builder = Dexpace::Pipeline::Builder.new(transport: @transport)
    builder.append(sync_fail_step, stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    pipeline = builder.build_async

    future = pipeline.call(@request)
    assert_instance_of(Dexpace::Async::Future, future)
    assert_raises(RuntimeError) do
      future.value
    end

    # ScriptError propagates synchronously
    fatal_step = ->(_r, _c) { raise NotImplementedError, "fatal error" }
    b_fatal = Dexpace::Pipeline::Builder.new(transport: @transport)
    b_fatal.append(fatal_step, stage: Dexpace::Pipeline::Stages::PRE_AUTH)
    fatal_pipeline = b_fatal.build_async

    assert_raises(NotImplementedError) do
      fatal_pipeline.call(@request)
    end
  end

  # A response with a real close latch, counting closes so PIPE-31's "idempotent double-close
  # tolerated" is asserted rather than assumed.
  class CountingResponse
    attr_reader :closes

    def initialize = @closes = 0
    def close = @closes += 1
    def closed? = @closes.positive?
  end

  test "PIPE-31: map_response applies the handler and then closes the response" do
    response = CountingResponse.new
    completer = Dexpace::Async::Completer.new
    mapped = Dexpace::AsyncPipeline.map_response(completer.future) { |res| [:mapped, res] }

    completer.fulfil(response)

    assert_equal([:mapped, response], mapped.value)
    assert_predicate(response, :closed?)
  end

  test "PIPE-31: a raising handler still closes the response and fails with the identical error" do
    response = CountingResponse.new
    expected = ::RuntimeError.new("handler error")
    completer = Dexpace::Async::Completer.new
    mapped = Dexpace::AsyncPipeline.map_response(completer.future) { raise expected }

    completer.fulfil(response)

    caught = assert_raises(::RuntimeError) { mapped.value }
    # The identical object, not merely an equal message: this port never wraps, so no unwrapping
    # step is needed and its absence is what this asserts.
    assert_same(expected, caught)
    assert_predicate(response, :closed?)
  end

  test "PIPE-31: closing again is a no-op the operator tolerates" do
    response = CountingResponse.new
    completer = Dexpace::Async::Completer.new
    mapped = Dexpace::AsyncPipeline.map_response(completer.future) { |res| res }

    completer.fulfil(response)
    mapped.value
    response.close

    assert_equal(2, response.closes, "the second close is the caller's and is tolerated")
  end

  test "PIPE-31: cancelling the mapped future cancels the source, carrying the reason" do
    seen_reason = nil
    source_completer = Dexpace::Async::Completer.new
    source_completer.on_cancel { |reason| seen_reason = reason }

    mapped = Dexpace::AsyncPipeline.map_response(source_completer.future) { |r| r }
    mapped.cancel(:client_abort)

    assert_predicate(source_completer.future, :cancelled?)
    assert_equal(:client_abort, seen_reason, "the reason arrives as the on_cancel block's argument")
  end

  test "PIPE-39: AsyncPipeline.direct creates step-less async pipeline" do
    pipeline = Dexpace::AsyncPipeline.direct(@transport)
    future = pipeline.call(@request)
    assert_equal("async_wire_res", future.value)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/async_pipeline_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::AsyncPipeline`.

- [ ] **Step 3: Write `lib/dexpace/async_pipeline.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "closeable"
require_relative "request_options"
require_relative "cancellation"
require_relative "async/completer"
require_relative "pipeline"
require_relative "pipeline/stages"
require_relative "pipeline/cursor"
require_relative "pipeline/builder"

module Dexpace
  # Asynchronous stage-based execution pipeline (PIPE-28, P4-36).
  #
  # It has no Stages of its own, no Builder of its own and no Cursor of its own: it references
  # Dexpace::Pipeline::Stages by that name and uses Dexpace::Pipeline::Cursor unchanged. PIPE-28's
  # "the two runtimes MUST NOT each re-derive ordering independently" is satisfied by there being
  # nothing to keep in sync -- what differs is one private driver, which arrives as a constructor
  # argument from Builder (P4-30).
  #
  # Flat, not Dexpace::Pipeline::Async (P4-36): Pipeline's namespace also holds Stages, Cursor and
  # Builder, three things this runtime SHARES rather than mirrors, and a variant-of reading is the
  # opposite of PIPE-28's. Phase 2 chose the same shape for Dexpace::AsyncTransport.
  #
  # **PIPE-32, and this paragraph IS the requirement's last clause discharged.** The async standard
  # pipeline MUST NOT follow HTTP redirects at the pipeline layer -- there is no async redirect
  # pillar step -- and "a port MUST document this asymmetry with the sync standard pipeline". The
  # asymmetry: Pipeline.standard will install redirect + retry + instrumentation, while
  # AsyncPipeline.standard installs retry + instrumentation only and takes an explicit
  # redirect: :unsupported argument so the absence is visible at the call site. Neither constructor
  # exists yet (DEF-39), so PIPE-32's substantive clause holds vacuously in phase 4 -- there is no
  # async standard pipeline to follow a redirect.
  #
  # What this phase deliberately does NOT do is make Stages::REDIRECT un-installable on the async
  # path. PIPE-28 requires the identical staging policy in both runtimes; a builder that rejected a
  # REDIRECT step for #build_async and accepted it for #build would be two staging policies.
  # PIPE-32 constrains the PRESET, not the runtime.
  class AsyncPipeline
    include Dexpace::Closeable

    attr_reader :entries, :steps, :transport

    private_class_method :new

    # PIPE-39's step-less shape, async form. AsyncPipeline.standard defers under DEF-39 with its
    # redirect: :unsupported argument; Builder#install_preset is the mechanism it will be written
    # over. PIPE-34's bridge is phase 2's AsyncTransport.sync_over(this), not a method here (R13).
    def self.direct(transport)
      Pipeline::Builder.new(transport:).build_async
    end

    # PIPE-31's terminal response-mapping operator (P4-38). A class method over a future rather than
    # a #call-with-handler overload, because PIPE-26 requires #call to stay exactly the transport
    # SPI's three positional parameters -- and because this way the four clauses are testable
    # against a bare Completer with no pipeline, transport or fake in sight.
    #
    # No unwrapping step appears, and that is not an omission: this port never wraps.
    # Completer#fail stores the error and Future#value re-raises THAT object, which is phase 2's
    # structural satisfaction of the same clause in sync_over.
    #
    # "Close any response that accompanies a failure" has exactly one reachable case here -- the
    # handler raising over a response the source delivered. Settlement.failure carries an error and
    # no response, so a source failure has no response to close; the requirement's wording invites
    # a second branch that cannot happen.
    def self.map_response(source)
      completer = Dexpace::Async::Completer.new
      # The block parameter is not decoration: Completer#request_cancel runs its hooks through
      # Hooks.notify(hooks, reason), so the reason arrives AS the block's argument. Written
      # `{ source.cancel(reason) }`, `reason` is an undefined local, the NameError is swallowed into
      # Hooks.notify's deferred-re-raise path, and the cancellation reaches the source having lost
      # its reason.
      completer.on_cancel { |reason| source.cancel(reason) }

      source.on_settle do |settlement|
        unless settlement.success?
          completer.fail(settlement.error)
          next
        end

        response = settlement.response
        begin
          completer.fulfil(yield(response))
        rescue ::Exception => e
          raise unless e.is_a?(::StandardError)

          completer.fail(e)
        ensure
          # On success: apply the handler and THEN close. On handler failure: close anyway. Both are
          # this one ensure, and phase 3's latch is what makes the idempotent double close PIPE-31
          # tolerates a property of the response rather than of this operator.
          Dexpace.close_quietly(response)
        end
      end

      completer.future
    end

    # Not Object#freeze'd, for the reason Dexpace::Pipeline is not: PIPE-27's latch writes an ivar.
    def initialize(entries:, transport:, driver_class:)
      initialize_closeable(owned: false)
      @entries = entries.dup.freeze
      @steps = @entries.map(&:step).freeze
      @transport = transport
      @driver_class = driver_class
    end

    def call(request, options = RequestOptions::EMPTY, cancellation = Cancellation.none)
      return dispatch_directly(request, options, cancellation) if @entries.empty?

      # Qualified: this class's cref is [Dexpace::AsyncPipeline, Dexpace], so a bare `Cursor` would
      # not resolve. There is exactly one Cursor class and both runtimes use it (P4-30).
      Pipeline::Cursor.build(
        drive: @driver_class.new(self),
        request:,
        options:,
        cancellation:
      ).call(request)
    end

    private

    # PIPE-9's empty branch on the async side, and PIPE-30 names it explicitly: the runtime must
    # normalise any synchronous exception thrown "by the empty-pipeline transport dispatch" too.
    def dispatch_directly(request, options, cancellation)
      completer = Dexpace::Async::Completer.new
      begin
        future = @transport.call(request, options, cancellation)
        future.on_settle do |settlement|
          if settlement.success?
            completer.fulfil(settlement.response)
          else
            completer.fail(settlement.error)
          end
        end
      rescue ::Exception => e
        # PIPE-30's fatal family, with a BARE raise: verified fact 7 confirms a bare re-raise
        # assigns no #cause and returns the identical object, so notes/pipeline.md's hazard --
        # `raise error` acquiring the caller's $! as a cause -- is not reachable here.
        raise unless e.is_a?(::StandardError)

        completer.fail(e)
      end
      completer.future
    end
  end
end
```

**`Cursor` and `RequestOptions` resolve here, and `AsyncDriver` does not** — which is what plan open
question 9 is about. `Dexpace::Pipeline::AsyncDriver` is a `private_constant`, and this class's cref
is `[Dexpace::AsyncPipeline, Dexpace]`, so naming it would raise `NameError`. `Builder` is nested
inside `class Pipeline` and can name it; `#build_async` therefore hands it over as `driver_class:`.
`Cursor` is reached through the plain qualified path because it is public.

- [ ] **Step 4: Write `sig/dexpace/async_pipeline.rbs`**

```rbs
module Dexpace
  class AsyncPipeline
    include Dexpace::Closeable

    def self.direct: (untyped transport) -> AsyncPipeline
    def self.map_response: [T] (Dexpace::Async::Future source) { (Dexpace::Response) -> T } -> Dexpace::Async::Future

    attr_reader entries: Array[Pipeline::Entry]
    attr_reader steps: Array[untyped]
    attr_reader transport: untyped

    def call: (Dexpace::Request request, ?Dexpace::RequestOptions options, ?Dexpace::Cancellation cancellation) -> Dexpace::Async::Future
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Positioned last in the pipeline set: `require_relative "dexpace/async_pipeline"`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/async_pipeline_test.rb`
Expected: PASS, 7 runs, 0 failures, 0 errors.

---

## Task 11: Wiring, the two regenerated artifacts, and the phase record

**Requirement IDs:** `NFR-3`, `NFR-4`, `NFR-11`, `NFR-13`, `NFR-14`.
**Design:** "Module layout", "Cross-cutting constraints", "Registers".

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Modify: `gems/dexpace-core/sig/dexpace.rbs`
- Regenerate: `gems/dexpace-core/test/fixtures/surface/dexpace-core.txt`
- Create: `docs/work/mvp/phase4/phase4c/<date>-phase4c-stage-pipeline-checklist.md`
- Verify (do **not** re-file): `docs/deferred-items.md`'s `DEF-39`, `docs/open-items.md`'s `OI-17`
  and `OI-18` — all three were filed by the design on 2026-09-08 and an ID is never reused
- Verify: `CLAUDE.md` claims sentence and housekeeping probe

- [ ] **Step 1: Verify the require order in `gems/dexpace-core/lib/dexpace.rb`**

Ensure the pipeline requires appear in exact dependency order:
```ruby
# Pipeline subsystem (Phase 4c)
require_relative "dexpace/error/pipeline_error"
require_relative "dexpace/pipeline"
require_relative "dexpace/pipeline/stage"
require_relative "dexpace/pipeline/stages"
require_relative "dexpace/pipeline/step"
require_relative "dexpace/pipeline/entry"
require_relative "dexpace/pipeline/cursor"
require_relative "dexpace/pipeline/sync_driver"
require_relative "dexpace/pipeline/async_driver"
require_relative "dexpace/pipeline/builder"
require_relative "dexpace/pipeline/transform_step"
require_relative "dexpace/async_pipeline"
```

- [ ] **Step 2: Update `gems/dexpace-core/sig/dexpace.rbs`**

Add module declarations mirroring the public types and constants:
`Dexpace::PipelineError`, `Dexpace::Pipeline`, `Dexpace::Pipeline::Stage`, `Dexpace::Pipeline::Stages`,
`Dexpace::Pipeline::Step`, `Dexpace::Pipeline::Entry`, `Dexpace::Pipeline::Cursor`,
`Dexpace::Pipeline::Builder`, `Dexpace::Pipeline::TransformStep`, and `Dexpace::AsyncPipeline`.

Run: `bundle exec rbs validate`
Run: `bundle exec steep check`
Expected: PASS on both.

- [ ] **Step 3: Regenerate the runtime surface manifest**

Run: `bundle exec rake surface:regenerate`
Confirm that `git diff test/fixtures/surface/dexpace-core.txt` adds only the public methods committed
by design §10 and deviations P4-26 and P4-27. In particular, verify that `Cursor` exposes no state-setting
writer method and that private drivers are not exposed.

- [ ] **Step 4: Verify the register rows this phase's design already filed**

**Nothing is appended here.** `DEF-39`, `OI-17` and `OI-18` were filed by
`2026-09-08-phase4c-stage-pipeline-design.md` and are live rows today — `docs/deferred-items.md`
carries `DEF-39` and reads `next id: DEF-40`; `docs/open-items.md` carries `OI-17` and `OI-18` and
reads `next id: OI-21`. Re-filing any of them would duplicate an ID that is already cited from this
plan, from the design and from `docs/knowledge/notes/pipeline.md`, and `CLAUDE.md`'s rule is that an
item ID is never renumbered and never reused.

What this step does is confirm each row still describes what shipped:

1. `DEF-39` — its "what is not deferred" clause names `Builder#install_preset`, `Pipeline.direct` /
   `AsyncPipeline.direct` and `Builder.flattening` / `.nesting`. All five ship (Tasks 7, 8, 10).
2. `OI-17` — its mitigation is documentation, and the YARD on `#insert_after` states it (Task 7).
3. `OI-18` — 4c neither introduces nor widens it; the repair it recommends is phase 2's to make.

Run: `ruby .claude/skills/housekeeping/probe.rb --only citations`
Expected: every `DEF-`/`OI-` citation in this plan resolves; no dangling item.

- [ ] **Step 5: Write the checklist**

`docs/work/mvp/phase4/phase4c/<date>-phase4c-stage-pipeline-checklist.md`, one row per requirement
ID in scope — all 40 `PIPE` — naming the numbered task that satisfies it, or the deferral
(`DEF-4`, `DEF-18`, `DEF-39`) or deviation that dispositions it. The self-review table below is the
source; the checklist is the artefact `CLAUDE.md` requires every sub-phase to ship beside its design
and plan, and a requirement in scope with no row is the failure this project is structured to
prevent.

- [ ] **Step 6: Run the whole gate set, then housekeeping**

Run: `bundle exec rake`
Expected: all seventeen gates green, including the require-allowlist audit (this phase adds no
entry), the clean-bundle isolation run, and `ruby -w` with warnings fatal.

Run: `mise exec ruby@3.2.11 -- bundle exec rake test:gems`
Expected: PASS. The floor is its own run because verified fact 9's latch race and `Data#with`'s
3.2 behaviour are both floor-only facts.

Run: `ruby .claude/skills/housekeeping/probe.rb`
Expected: exit code 0, "no drift found."

---

## Self-review against the design

### The 40 Requirement IDs Accounted For

| Requirement ID | Disposition | Owning Task / Register | Notes / Evidence |
|---|---|---|---|
| `PIPE-1` | ✅ Implemented | Task 2, Task 8 | Total stage ordering; 15 probes in shuffled order under pinned seed 42 in Task 8 |
| `PIPE-2` | ✅ Implemented | Task 2, Task 8 | Pillar precedence chain; PRE_REDIRECT runs once while AUTH runs twice under forking REDIRECT |
| `PIPE-3` | ✅ Implemented | Task 2 | 16 interleaved stages with sparse numbering by 100 |
| `PIPE-4` | ✅ Implemented | Task 2, Task 7 | `Stage#pillar?` plus `Builder`'s exclusivity check; at most one step per pillar stage |
| `PIPE-5` | ✅ Implemented | Task 7 | Collision compared by `#equal?`, never `==`; raises naming both types and pointing at `#replace` |
| `PIPE-6` | ✅ Implemented | Task 3, Task 7 | Re-installing the same object is a no-op; fixture is two `Data` probes over one **shared** `log` |
| `PIPE-7` | ✅ Implemented | Task 7 | `#append` to the tail, `#prepend` to the head, and flattening derived from the stage table |
| `PIPE-8` | ✅ Implemented | Task 2, Task 5, Task 7 | SEND is terminal, holds no user step, rejects installation, and flattening skips it |
| `PIPE-9` | ✅ Implemented | Task 8 | Direct dispatch threading the caller's arguments, plus a zero-cursor `ObjectSpace` delta (`DEF-33`) |
| `PIPE-10` | ✅ Implemented | Task 6, Task 8 | Per-call cursor, delta ≥ 1 on a one-step pipeline, 16 concurrent calls → 16 distinct cursors |
| `PIPE-11` | ✅ Implemented | Task 4, Task 6, Task 8 | The step protocol takes the cursor as its second argument; the 16-thread test is the concurrency half |
| `PIPE-12` | ✅ Implemented | Task 4, Task 6 | Bidirectional step contract; a short-circuiting step returns without advancing downstream |
| `PIPE-13` | ✅ Implemented | Task 6 | Forward-only advance; second invocation raises PipelineError; spent? becomes true |
| `PIPE-14` | ✅ Implemented | Task 6 | Request substitution sticks by identity across downstream steps and transport |
| `PIPE-15` | ✅ Implemented | Task 6 | Reuse guard raises (sequential-only, P4-33); fork gated to non-terminal pillars and rejected on a spent cursor (P4-39) |
| `PIPE-16` | ✅ Implemented | Task 6 | Forks resume from the parent's position; downstream invoked exactly twice, the two forks independent |
| `PIPE-17` | ✅ Implemented | Task 6 | Options shared by reference identity (assert_same) across forks |
| `PIPE-18` | ✅ Implemented | Task 7 | `insert_after`/`insert_before` on the first anchor instance; same stage required, `stage:` never inferred |
| `PIPE-19` | ✅ Implemented | Task 7 | `replace` 1:1 on the first anchor instance at the same stage; cross-stage rejected |
| `PIPE-20` | ✅ Implemented | Task 7 | remove deletes all instances; no-op when absent |
| `PIPE-21` | ✅ Implemented | Task 7 | A missing anchor raises identifying the type, rather than silently no-op'ing |
| `PIPE-22` | ✅ Implemented | Task 7 | `insert_after` + `remove` + `replace`, then the same step set from scratch: entries equal |
| `PIPE-23` | ✅ Implemented | Task 7 | Validate-then-commit; `builder.entries` captured before the rejected call and asserted unchanged |
| `PIPE-24` | ✅ Implemented | Task 7 | `install_preset` validates every target pillar empty up front, names each occupant, installs nothing on rejection (P4-34) |
| `PIPE-25` | ✅ Implemented | Task 7, Task 8 | `Builder#build` flattens `Stages::ALL` skipping SEND; `#steps`/`#entries` frozen and computed once |
| `PIPE-26` | ✅ Implemented | Task 8 | `Transport.conforms?(pipeline)` is true and both the one- and three-argument call forms work (verified fact 2) |
| `PIPE-27` | ✅ Implemented | Task 8 | Pipeline#close latches and never cascades to transport |
| `PIPE-28` | ✅ Implemented | Task 2, Task 7, Task 10 | One `Stages`, one `Builder`, one `Cursor`; the two entry tables compared row-for-row by identity |
| `PIPE-29` | ✅ Implemented | Task 6, Task 10 | The runtime's obligation is unconditional; `PIPE-29`'s permission is about what a step author may do |
| `PIPE-30` | ✅ Implemented | Task 6, Task 10 | `StandardError` → failed future; `ScriptError` propagates through a **bare** `raise` (verified fact 7) |
| `PIPE-31` | ✅ Implemented | Task 10 | Four tests: close on success, close on handler failure with the identical error, tolerated double close, cancel carrying its reason (P4-38) |
| `PIPE-32` | ✅ Implemented | Task 10 | The documentation clause is discharged in `AsyncPipeline`'s YARD; the substantive clause holds vacuously until `DEF-39` |
| `PIPE-33` | ⏳ Partially unsatisfied | Task 8 (`DEF-18`) | Clauses 1–4 met through `Transport.async_over` — one `#post` for a five-step pipeline; clause 5's interrupt mode is `DEF-18` and design §10.5 |
| `PIPE-34` | ✅ Implemented | Task 8 | `AsyncTransport.sync_over` over a built async pipeline: options by identity, and a cancelled token raising `CancelledError` rather than blocking (P4-35) |
| `PIPE-35` | ✅ Implemented | Task 7, Task 8 | FLATTEN runs the new probe **twice**, NEST **once** — the only assertion that distinguishes the two constructors |
| `PIPE-36` | ⏳ Deferred | `DEF-4` | Post-MVP, pre-existing; nothing here implements any part of it. R10's table is where a lock would go |
| `PIPE-37` | ✅ Implemented | Task 9 | Asserted **through** the pipeline under a twice-forking REDIRECT: one invocation, identity return, `#source` never called, response unclosed |
| `PIPE-38` | ✅ Implemented | Task 7 | `append_all` preserves order, `prepend_all` reverses it; the asymmetry is in `#prepend_all`'s YARD, as the requirement demands |
| `PIPE-39` | ⏳ Deferred in half | Task 8, Task 10 (`DEF-39`) | `Pipeline.direct` / `AsyncPipeline.direct` ship; `Pipeline.standard` / `AsyncPipeline.standard` defer to phase 6 over `#install_preset` |
| `PIPE-40` | ✅ Implemented | Task 3, Task 6 | `ForkingProbe` is the conformance fixture; three drives, the first two responses closed, the returned one not |

### Deviations P4-26 through P4-39 Mapped to Tasks

| Deviation | Summary | Owning Task(s) |
|---|---|---|
| P4-26 | Public constants neither §5.1 nor §5.3 names | Tasks 1, 2, 4, 5, 6, 7, 9, 10 |
| P4-27 | Public methods neither §5.1 nor §5.3 names | Tasks 2, 4, 5, 6, 7, 8, 9, 10 |
| P4-28 | Cursor-scoped state keyed by `(stage, key)` | Task 6 |
| P4-29 | Cursor has no state-setting method; write is argument to `#fork` | Task 6 |
| P4-30 | One `Cursor` and one `Builder` class serve both runtimes | Tasks 6, 7, 10 |
| P4-31 | Sixteen stages | Task 2 |
| P4-32 | `Stage` is `private_class_method :new` with no public factory | Task 2 |
| P4-33 | Cursor single-use latch is unsynchronised ivar; sequential-only detection | Task 6 |
| P4-34 | `PIPE-24` all-or-nothing preset mechanism with step set deferred under `DEF-39` | Task 7 |
| P4-35 | 4c ships no bridge; reuses phase 2 bridges | Task 8 |
| P4-36 | `AsyncPipeline` is flat constant | Task 10 |
| P4-37 | One `PipelineError`, carrying no fields (nine conditions in the row, eleven message forms once R10's table is counted) | Tasks 1, 5, 6, 7 |
| P4-38 | `PIPE-31` operator is `AsyncPipeline.map_response` class method | Task 10 |
| P4-39 | `#call` and `#fork` disjoint on one cursor; fork after call rejected | Task 6 |

### Design Section Review

- **Purpose & Scope:** all 40 `PIPE` IDs dispositioned above — 37 ✅, `PIPE-33` ⏳ (`DEF-18`, four of
  five clauses), `PIPE-36` ⏳ (`DEF-4`), `PIPE-39` ⏳ (`DEF-39`, one of two constructors).
- **Prerequisites & independence:** nothing here waits on 4a, and the only thing consumed from 4b is
  the `Transform` value type (Task 9). No allowlist entry, no `add_dependency`, no `require` beyond
  `require_relative`.
- **Verified Ruby facts:** facts 1 and 2 are Task 4's predicate and `PIPE-26`'s call forms; 3 is the
  `PIPE-6` fixture; 4 and 5 are R11's merge and `PIPE-17`'s `assert_same`; 6 is R10's `respond_to?`;
  7 is the async bare `raise`; 8 is `#steps`' single frozen reference; 10 is Task 2's `sort` raise;
  11 is R12's two deltas; 12 is Task 9's `#call`-raises double; 13 is `OI-17`. **Fact 9 informs no
  test by design** — 4c ships none asserting the latch race, at 1.5 % on the floor — and appears in
  the global constraints, `Cursor#call`'s YARD and `#fork`'s YARD instead.
- **R10:** `Builder#resolve_stage` and `#resolve_surgical_stage`; all five rows of the precedence
  table tested in Task 7, including row 4's "declares nothing and no argument is rejected" and the
  surgical rule that `stage:` is required rather than inferred from the anchor.
- **R11:** `(stage, key)` state, the only write an argument to `#fork`, landing in the owner's own
  slot from the frozen entry table. All five assertions in Task 6, the last two negatives included.
- **R12:** one `if` in `Pipeline#call`; all four assertions in Task 8, both `ObjectSpace` deltas under
  `GC.disable` with `DEF-33` named in the comment.
- **R13:** no bridge, no executor, no wait, no new signature. Tasks 8's `PIPE-33` and `PIPE-34` tests
  compose phase 2's two bridges over a real built pipeline and nothing else.
- **R14:** `#install_preset` ships as a general mechanism with no standard step set;
  `Pipeline.direct` / `AsyncPipeline.direct` ship; `DEF-39` carries the rest.
- **Generic adapter:** `TransformStep` reads `#phase` at build, calls `#apply` and never `#call`, and
  declares no `#stage` — all three asserted in Task 9.
- **Module layout:** twelve `lib/` files, ten `sig/` mirrors, ten `test/` mirrors and three
  test-support files, plus `test/support/pipeline_doubles_test.rb`, an eleventh test file the design's
  layout does not name — the doubles are load-bearing enough (verified fact 3's `==` relation, the
  `PIPE-40` close discipline) to be driven red first rather than trusted.
- **Testing strategy:** every case the design's *Testing strategy* enumerates has a home; the mapping
  is the disposition table above, task by task.
- **Deviation ledger:** all fourteen rows `P4-26`–`P4-39` assigned to tasks.
- **Deferrals & open items:** `DEF-39`, `OI-17` and `OI-18` were filed by the **design**; Task 11
  verifies them and files nothing new.

### What this plan does not carry, said plainly

- **`PIPE-36` is not implemented and no part of it is.** `DEF-4`'s condition — post-MVP, no narrower
  trigger — is unmet, and R10's precedence table is where a future lock would go. Verified fact 6
  records why `Method#owner` cannot detect an inherited `#stage`, so the deferral is not a
  convenience.
- **`PIPE-33`'s interrupt clause has no test, because there is no interrupt mode.** §10.5 settled the
  trade and nothing here re-opens it.
- **No test asserts the cursor's concurrent double-call.** P4-33 prices the decision; both shippable
  forms of that test are unshippable, and this plan does not ship a third.
- **No property tests.** `Stage` has no public constructor and `Entry`'s validation is two type
  checks, so `testing/f36a19cd`'s round-trip rule reaches neither — a disposition, not an omission.
- **The exact `sig/dexpace.rbs` and surface-manifest diffs are Task 11's output, not this plan's
  input.** They are regenerated, reviewed against P4-26 and P4-27, and committed; a plan that wrote
  them out in advance would be asserting what the tool will produce.
