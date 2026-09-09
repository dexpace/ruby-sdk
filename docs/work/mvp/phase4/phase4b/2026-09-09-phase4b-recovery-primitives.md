# Phase 4b — Recovery-Chain Primitives Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `dexpace-core`'s resilience layer — a closed two-variant outcome (`Dexpace::Outcome`),
two folds over frozen step lists (`RequestChain` and `ResponseChain`), one unified orchestrator
(`Orchestrator`) that lets no throwable past it, the three pure transforms (`IdempotencyKeyStep`,
`ClientIdentityStep`, `ErrorMappingStep`), the bounded error-body buffer (`Recovery.buffer_error_body`),
and the error primitives four register rows and five later phases have been waiting on
(`Suppressible`, `attach_suppressed`, `each_cause`, `OutcomeError`, `ProtocolError`) — satisfying
all 18 implemented `RECOV` IDs (`RECOV-1`–`RECOV-16`, `RECOV-32`, `RECOV-33`), carrying 15 ⏳ rows under
`DEF-35` to phase 6, and carrying 1 ⏳ row under `DEF-5` post-MVP.

**Architecture:** One closed sum type (`Dexpace::Outcome`) with exactly two variants (`Success` and
`Failure`) defined via `Data.define` + `Model` + validating `.build`; one pure transform contract
(`Dexpace::Recovery::Transform`) defining `#phase`, `#apply` and a default forwarding `#call(value)`;
three frozen transform steps; one `RequestChain` folding requests sequentially left-to-right; one
`ResponseChain` executing response steps on `Success` only and recovery steps on every outcome; one
private response-ownership helper (`Dexpace::Recovery::Ownership`) ensuring a response in hand is
closed exactly once on throw; one `Orchestrator` implementing the `Dexpace::Transport` duck type
over `#call(request, options, cancellation)` with a single `rescue Exception` region catching every
throwable, converting non-fatal exceptions to `Failure`, passing fatal exceptions and `OutcomeError`
unchanged, and unwrapping on dispatch with `cause: nil`; one trail module (`Dexpace::Suppressible`)
that `Dexpace::Error` includes and `Dexpace.attach_suppressed` `extend`s onto third-party exceptions;
and one cycle-safe `Dexpace.each_cause` enumerator using an identity-tracked visited set. No stage,
no cursor, no pipeline, no transport, no socket: the whole test surface is value objects, folds over
lambdas, and one in-memory fake transport.

**Tech Stack:** Ruby 3.2–4.0 (development on 4.0.6), zero runtime dependencies, Minitest, RBS +
Steep, RuboCop with seven custom cops, SimpleCov, YARD.

**Spec:** `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md`, under the
charter `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md`. `docs/product-spec/08-execution-pipelines.md`
§8.2 and §8.3 are the normative sections; `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md`
carries the canonical `RECOV`, `XCUT`, `BODY` and `PIPE` text quoted below.

## Global Constraints

- **`dexpace-core` gains no dependency and no allowlist entry.** The gemspec keeps zero
  `add_dependency` lines (`SEAM-1`, `NFR-1`). This phase adds **no `require` of any kind beyond
  `require_relative`** — `::Data`, `::Hash`, `::Array`, `::Exception`, `::Module`, `::Object` are core
  Ruby. `set` is on the allowlist and this phase does **not** use it: `XCUT-9`'s visited set
  resolves to `{}.compare_by_identity` to prevent structural `#eql?`/`#hash` truncation (design §5.2,
  verified fact 7).
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`). No `# typed:` sigil
  anywhere (`notes/testing.md`'s conflict resolution — no Sorbet in this repository).
- **`downcase` is called with no arguments, everywhere** (`Dexpace/NoLocaleCaseFold`).
- **Inside `module Dexpace`, anywhere, write `::Thread`, `::Queue`, `::Mutex`, `::SizedQueue`,
  `::ConditionVariable`, `::JSON` and `::IO`** — never the bare name (`Dexpace/QualifiedCoreConstant`).
  No constant this phase defines shares a name with a Ruby core constant.
- **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden repository-wide**
  (`Dexpace/NoThreadInterrupt`). This phase starts no thread, has no timer, and interrupts none.
- **No mutex is held in this phase, because 4b owns no mutable shared state.** Built chains hold
  frozen arrays of callables; an orchestrator holds three frozen references; per-call state lives in
  the value being transformed (`RECOV-14`). The suppressed trail relies on the single-writer
  discipline by construction at every call site (`RECOV-12`, `DEF-32`, `RETRY-34`).
- **`private_class_method :new` plus a validating `.build`**, on every `Data` this phase ships that
  is public API: `Dexpace::Outcome::Success` and `Dexpace::Outcome::Failure`. Validation lives in
  `initialize` and is invoked through `super` from `.build` via `new`. `Dexpace::Recovery::Ownership`
  is a `private_constant` and ships no `sig/` mirror, no YARD gate entry, and no surface snapshot row.
- **Formatting:** double quotes, 2-space indent, 100 columns, `consistent_comma` trailing commas,
  leading-dot chains, `MethodLength: 25`, `ParameterLists: 4`, `BlockNesting: 3`.
- **Tests:** Minitest only, `FooTest < DexpaceTestCase`, `test "..." do` blocks, `test/` mirroring
  `lib/` one file per file, every test passing alone and in any order, the seed never overridden.
  Each test file's header comment names the requirement IDs it exercises. Every public constant
  gets three artifacts in the same task: the implementation, a YARD block, and an `.rbs` mirror.
- **No commit step appears in any task.** The manager commits once per phase.
- **Never edit** `docs/product-spec/`, `docs/sdk-design-ruby/`, `docs/knowledge/harvested/`.

### Commands

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/<path>_test.rb   # one suite, red or green
(cd gems/dexpace-core && bundle exec rake test)                     # the gem's whole suite
bundle exec rake                                                    # all seventeen gates
bundle exec rake cops:test                                          # the custom cops' own suite
mise exec ruby@3.2.11 -- bundle exec rake test:gems                 # the floor, locally
bundle exec rake surface:regenerate                                 # deliberate; Task 15 only
```

### What was verified during planning, and how

**"Verified fact N" anywhere in this document means the design's numbering** — its fourteen-item
*The verified Ruby facts this phase is built on* — and this plan re-numbers none of them. The seven
that decide a line of code here are 1 (`#detailed_message` reaches the default printer,
`#full_message` does not), 2 (`rescue M` matches a module reached through a singleton class),
3 (`extend` and an ivar write both raise `FrozenError` on a frozen exception), 5 (a bare
`raise error` assigns the caller's `$!` as its `#cause`; `cause: nil` suppresses the assignment and
clears nothing), 6 and 7 (`Exception#==` is structural, `#eql?`/`#hash` are not, and only
`{}.compare_by_identity` survives both an `Array` and a caller-overridden `hash`/`eql?`),
9 (`NoMatchingPatternError` is inside `StandardError` while `LoadError` and `NotImplementedError`
are `ScriptError`s) and 14 (`Data`'s `deconstruct_keys` makes the `case/in` fold work under
`private_class_method :new`).

Every `ruby` fence below was extracted and syntax-checked with `ruby -c`, and the fold semantics of
`ResponseChain`/`Ownership`, the `Suppressible` trail, the `each_cause` walk and
`ClientIdentityStep#apply`'s header reconciliation were run against stand-ins on 3.4.10.
**The fences have not been executed against the real gem, because no gem exists** (`CLAUDE.md`:
zero gems under `gems/`), so every call into a phase-1, -2 or -3 constant here is written from that
phase's own committed plan and is checked at execution time by the task's own red step, not before
it. Three spellings are the ones that bite, and each is named where it is used: `Dexpace::Response`
is `Data.define(:request, :protocol, :status, :reason, :headers, :body)` and is built through
`Response.builder`; `Dexpace::Headers#[]` returns the name's **value list**, and `Headers.build`
takes `values:`/`casing:`; and `Dexpace::Body` is a **module**, so a fake body includes it.

## This plan's open questions, resolved

The design's closing section, *Open questions for 4b's own plan*, left five for this plan to close.
All five are resolved below, and each resolution is carried through the tasks rather than only
stated here:

1. **Whether `Dexpace::Recovery::Ownership` gets its own file or folds into `response_chain.rb`.**
   **Decision:** Its own file (`gems/dexpace-core/lib/dexpace/recovery/ownership.rb`), as a
   `private_constant :Ownership` under `Dexpace::Recovery`.
   **Reason:** Section 5.2's rule that "the asymmetry lives in one place" is a claim a reader
   must be able to verify by opening a single file. Isolating it keeps `ResponseChain` focused on
   the fold sequence, and provides a clean attachment point should phase 6's recovery-aware retry
   stack need the same helper.
2. **`ErrorMappingStep`'s default `factory:` spelling.**
   **Decision:** A private constant frozen lambda `DEFAULT_FACTORY = ->(response) { Dexpace::ProtocolError.for(response) }.freeze`
   in `lib/dexpace/recovery/error_mapping_step.rb`, referenced as the default parameter value `factory: DEFAULT_FACTORY`.
   **Reason:** Avoids allocating a new `Method` object on every `.build` invocation, provides a single
   frozen callable, and matches the RBS proc type `^(Dexpace::Response) -> ::Exception` cleanly without
   method-object typing workarounds.
3. **Whether `Dexpace.each_cause` stops at a raising `#cause` or propagates.**
   **Decision:** Stops at a raising `#cause` (treats it as the end of the cause chain) and returns normally.
   **Reason:** A classification walk (such as retryability or error inspection) must never be the thing
   that raises or crashes an application when inspecting an ill-behaved third-party exception. A fourth
   fixture class (`RaisingCauseError`) is added to `cyclic_errors.rb` to assert this behavior.
4. **Whether `DEF-32`'s fourth `Hooks.notify` test goes at one site or all three.**
   **Decision:** One site, in `test/dexpace/cancellation_test.rb` at `Cancellation::Source#cancel`.
   **Reason:** All three call sites invoke the same private helper `Dexpace::Hooks.notify`, and phase 2
   already proves each site delegates to `Hooks.notify`. Replicating the multi-raising handler test
   across all three would test `notify`'s internal trail attachment three times redundantly without
   exercising unique site logic.
5. **Whether `Dexpace::ProtocolError`'s message includes a body preview.**
   **Decision:** No body preview in the error message. The message format is `"HTTP #{status.code} #{status.canonical_name}"`
   (or `"HTTP #{status.code}"` if canonical name is absent).
   **Reason:** Redaction rules (`OBS-11`–`OBS-19`) are deferred to phase 5. Exception messages are
   frequently logged or exposed in stack traces. Error response bodies may contain sensitive credentials,
   tokens, or PII. Omitting the body preview prevents data leakage, while `#response` remains available
   for callers who explicitly inspect the buffered body.

## Task order and dependency chain

Fifteen tasks, in strict dependency order. Every file required by a task is guaranteed to exist
before that task is executed.

1. `Dexpace::Suppressible` (module, `attach_suppressed`, `suppressed`) + `Dexpace::Error` inclusion
   — foundational trail module needed by Tasks 2, 13, 14. Load-bearing require order: `suppressible`
   must precede `error`. Satisfies `DEF-24`, `RETRY-34`, `P4-12`, `P4-13`, `P4-14`, `P4-15`.
2. `DEF-32` (`Hooks.notify` trail update) and `DEF-27` (`close_quietly(onto:)`) — modifies phase-2
   infrastructure to utilize `Dexpace.attach_suppressed`. Needs Task 1.
3. `Dexpace.each_cause` + `CyclicErrorFixtures` test support — cycle-safe cause traversal (`XCUT-9`,
   `P4-16`). Needs Task 1.
4. `Dexpace::OutcomeError` — named internal error for exhaustiveness failures (`R6`, `P4-19`).
   Needs Task 1 (`Dexpace::Error`).
5. `Dexpace::ProtocolError` — status-to-typed-exception model carrying `#response` and `#status`
   (`XCUT-4`, `XCUT-8`, `RECOV-15`, `P4-20`, `DEF-38`). Needs Task 1.
6. `Dexpace::Outcome`, `Outcome::Success`, `Outcome::Failure` — closed sum type (`RECOV-1`,
   `P4-21`, `P4-24`). Needed by Tasks 11, 13, 14.
7. `Dexpace::Recovery` module and `Recovery.buffer_error_body` — bounded error-body buffering
   (`RECOV-16`, `BODY-30`). Needed by Task 11.
8. `Dexpace::Recovery::Transform` — pure transform contract (`R8`, `P4-24`, `P4-25`). Needed by
   Tasks 9, 10, 11.
9. `Dexpace::Recovery::IdempotencyKeyStep` — request transform step (`RECOV-32`). Needs Task 8.
10. `Dexpace::Recovery::ClientIdentityStep` — request transform step (`RECOV-33`). Needs Task 8.
11. `Dexpace::Recovery::ErrorMappingStep` — response transform step (`RECOV-15`, `RECOV-16`, `XCUT-8`,
    `PIPE-37`). Needs Tasks 5, 7, 8.
12. `Dexpace::Recovery::RequestChain` — left-to-right request fold (`RECOV-3`, `RECOV-14`, `P4-22`).
    Needed by Task 14.
13. `Dexpace::Recovery::Ownership` (private) + `Dexpace::Recovery::ResponseChain` + `FakeTransport`/`RecordingBody`
    test support — response-step and recovery-step fold with exact-once release semantics (`RECOV-4`–`RECOV-8`,
    `RECOV-12`–`RECOV-14`, `P4-18`, `P4-19`, `P4-22`). Needs Tasks 1, 4, 6.
14. `Dexpace::Recovery::Orchestrator` — transport wrapper and unwrap orchestrator (`RECOV-2`,
    `RECOV-10`, `RECOV-11`, `P4-17`, `P4-19`). Needs Tasks 12, 13.
15. Wiring, Surface Snapshot, RBS Baseline, Checklist, and Register Updates — require ordering,
    manifest regeneration, test matrix execution, checklist generation, register updates (`DEF-24`,
    `DEF-32`, `DEF-27`, `DEF-38`, `DEF-35`, `DEF-5`), and `CLAUDE.md` claims sentence.

---

## Task 1: `Dexpace::Suppressible` and `Dexpace::Error`

**Requirement IDs:** `DEF-24`, `RETRY-34` (the skip-self guard), `RECOV-12` (suppressed error attachment).
**Design:** "The trail cannot live on `Dexpace::Error`, because every primary it will ever be handed
is a caller's exception... So the trail is a **separate** module, `Dexpace::Suppressible`, that
`Dexpace::Error` includes and `Dexpace.attach_suppressed` `extend`s onto anything else — and it has to
be separate, because `rescue M` matches a module reached through a singleton class (verified), so
extending a third-party `IOError` with the rescue root would make `rescue Dexpace::Error` catch
errors the SDK never raised (P4-12, P4-13)."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/suppressible.rb`,
  `gems/dexpace-core/sig/dexpace/suppressible.rbs`
- Modify: `gems/dexpace-core/lib/dexpace/error.rb`,
  `gems/dexpace-core/sig/dexpace/error.rbs`,
  `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/suppressible_test.rb`

**Interfaces:**
- Consumes: `Dexpace::InvalidArgumentError`.
- Produces: `Dexpace::Suppressible`, `Dexpace.attach_suppressed(primary, secondary)`,
  `Dexpace.suppressed(error)`, `Dexpace::Error#suppressed`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# DEF-24, RETRY-34, RECOV-12.
class DexpaceSuppressibleTest < DexpaceTestCase
  test "empty suppressed trail returns frozen empty array" do
    err = ::StandardError.new("boom")
    assert_equal([], Dexpace.suppressed(err))
    assert_predicate(Dexpace.suppressed(err), :frozen?)
  end

  test "attach_suppressed extends primary with Dexpace::Suppressible without adding Dexpace::Error" do
    primary = ::IOError.new("primary failure")
    secondary = ::RuntimeError.new("cleanup failure")

    result = Dexpace.attach_suppressed(primary, secondary)

    assert_same(primary, result)
    assert_kind_of(Dexpace::Suppressible, primary)
    refute_kind_of(Dexpace::Error, primary)

    trail = primary.suppressed
    assert_equal([secondary], trail)
    assert_predicate(trail, :frozen?)
    assert_raises(FrozenError) { trail << ::StandardError.new }
  end

  test "rescue Dexpace::Suppressible catches extended third-party error" do
    primary = ::IOError.new("io err")
    secondary = ::RuntimeError.new("secondary")
    Dexpace.attach_suppressed(primary, secondary)

    caught = begin
      raise primary
    rescue Dexpace::Suppressible => e
      e
    end

    assert_same(primary, caught)
  end

  test "multiple attaches replace frozen trail in append order" do
    primary = ::StandardError.new("p")
    s1 = ::StandardError.new("s1")
    s2 = ::StandardError.new("s2")

    Dexpace.attach_suppressed(primary, s1)
    snapshot1 = primary.suppressed
    Dexpace.attach_suppressed(primary, s2)
    snapshot2 = primary.suppressed

    assert_equal([s1], snapshot1)
    assert_equal([s1, s2], snapshot2)
    assert_equal([s1, s2], Dexpace.suppressed(primary))
  end

  test "attach_suppressed skips attaching when primary equal? secondary" do
    primary = ::StandardError.new("loop")
    Dexpace.attach_suppressed(primary, primary)

    assert_equal([], Dexpace.suppressed(primary))
  end

  test "attach_suppressed swallows FrozenError when primary is frozen" do
    primary = ::StandardError.new("frozen").freeze
    secondary = ::StandardError.new("secondary")

    assert_same(primary, Dexpace.attach_suppressed(primary, secondary))
    assert_equal([], Dexpace.suppressed(primary))
  end

  # A frozen SDK error is already Suppressible by inclusion, so #suppressed is reachable on it and
  # the reader must not be the thing that raises: P4-13's no-op covers the WRITE, and a reader that
  # memoised into an ivar would turn every read of a frozen error's trail into a FrozenError.
  test "a frozen Dexpace::Error reads an empty trail and silently refuses the attach" do
    primary = Dexpace::ContextConflictError.new("k1").freeze
    assert_equal([], Dexpace.suppressed(primary))
    assert_same(primary, Dexpace.attach_suppressed(primary, ::IOError.new("cleanup")))
    assert_equal([], Dexpace.suppressed(primary))
  end

  test "attach_suppressed validates both arguments are Exceptions" do
    err = ::StandardError.new

    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace.attach_suppressed("not an error", err)
    end

    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace.attach_suppressed(err, :not_an_error)
    end
  end

  test "detailed_message renders primary message and formatted suppressed trail" do
    primary = ::StandardError.new("main failed")
    s1 = ::IOError.new("disk error")
    s2 = ::ArgumentError.new("invalid val")

    Dexpace.attach_suppressed(primary, s1)
    Dexpace.attach_suppressed(primary, s2)

    rendered = primary.detailed_message
    assert_includes(rendered, "main failed")
    assert_includes(rendered, "Suppressed exceptions (2):")
    assert_includes(rendered, "(1) IOError: disk error")
    assert_includes(rendered, "(2) ArgumentError: invalid val")
  end

  test "Dexpace::Error includes Dexpace::Suppressible" do
    assert_operator(Dexpace::Error, :<, Dexpace::Suppressible)

    # ContextConflictError is a Dexpace::Error
    err = Dexpace::ContextConflictError.new("k1")
    assert_kind_of(Dexpace::Suppressible, err)
    assert_equal([], err.suppressed)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/suppressible_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Suppressible`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/suppressible.rb` and modify `lib/dexpace/error.rb`**

Write `gems/dexpace-core/lib/dexpace/suppressible.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# This file requires nothing, and that is load-bearing rather than an omission. `error.rb`
# requires this file so `include Dexpace::Suppressible` resolves, and
# `error/invalid_argument_error.rb` requires `error.rb`. A `require_relative` back to the
# argument error from here closes that cycle: `error.rb` would re-enter as a no-op and run
# `include Dexpace::Suppressible` before this file's body has, raising NameError at load in
# every consumer at once. `lib/dexpace.rb` loads the whole tree, so
# `Dexpace::InvalidArgumentError` is defined long before `attach_suppressed` is first called.

module Dexpace
  # The suppressed exception trail. Defined on a separate module so that
  # Dexpace.attach_suppressed can extend a caller-supplied exception without
  # making it match rescue Dexpace::Error (P4-12, P4-13).
  module Suppressible
    # P4-14: the trail is a frozen array REPLACED on every attach, never one array frozen at
    # some later moment, so a handle taken earlier stays a stable snapshot. Reading never
    # writes an ivar: an SDK error can be frozen, and `#suppressed` is a reader that must not
    # raise FrozenError on one (verified fact 3 is about the writer, not this).
    def suppressed
      defined?(@dexpace_suppressed) ? @dexpace_suppressed : [].freeze
    end

    def detailed_message(**kwargs)
      msg = super(**kwargs)
      trail = suppressed
      return msg if trail.empty?

      lines = [msg, "Suppressed exceptions (#{trail.size}):"]
      trail.each_with_index do |err, idx|
        lines << "  (#{idx + 1}) #{err.class}: #{err.message}"
      end
      lines.join("\n")
    end
  end

  # Attaches secondary to primary's suppressed trail.
  # Skips self-attachment (RETRY-34).
  # Swallows FrozenError as a documented no-op (P4-13).
  def self.attach_suppressed(primary, secondary)
    unless primary.is_a?(::Exception)
      raise Dexpace::InvalidArgumentError, "primary must be an Exception"
    end
    unless secondary.is_a?(::Exception)
      raise Dexpace::InvalidArgumentError, "secondary must be an Exception"
    end

    return primary if primary.equal?(secondary) # RETRY-34's skip-self guard, by identity

    primary.extend(Dexpace::Suppressible) unless primary.is_a?(Dexpace::Suppressible)
    current = primary.suppressed
    primary.instance_variable_set(:@dexpace_suppressed, [*current, secondary].freeze)
    primary
  rescue ::FrozenError
    # P4-13: Deliberate swallow. A helper that raises while attaching a close error
    # would mask the primary, which RECOV-12 exists to prevent.
    primary
  end

  # Returns the frozen suppressed trail for error, or an empty frozen array if none.
  def self.suppressed(error)
    error.is_a?(Dexpace::Suppressible) ? error.suppressed : [].freeze
  end
end
```

Modify `gems/dexpace-core/lib/dexpace/error.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "suppressible"

module Dexpace
  # Root module for all exceptions raised by the dexpace SDK (P1-2).
  # Includes Dexpace::Suppressible so all SDK errors carry a suppressed trail (DEF-24).
  module Error
    include Dexpace::Suppressible
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/suppressible.rbs` and modify `sig/dexpace/error.rbs`**

Write `gems/dexpace-core/sig/dexpace/suppressible.rbs`:

```rbs
module Dexpace
  module Suppressible : ::Exception
    def suppressed: () -> Array[::Exception]
    def detailed_message: (**untyped) -> String
  end

  def self.attach_suppressed: [E < ::Exception] (E primary, ::Exception secondary) -> E
  def self.suppressed: (::Exception error) -> Array[::Exception]
end
```

The self-type is `::Exception` because `#detailed_message` calls `super`, and `**untyped` is
unnamed on purpose: Ruby passes `highlight:` and `order:` today and a signature that named them
would be wrong the day Ruby adds a third.

Modify `gems/dexpace-core/sig/dexpace/error.rbs` — `Dexpace::Error` gains the **same** self-type,
because a module including a self-typed module must satisfy that self-type. It is true of every
error in the SDK by phase 2's shape (`class X < ::StandardError; include Dexpace::Error; end`),
and `NFR-4` is not a concern: the lock diffs against a release tag that does not exist.

```rbs
module Dexpace
  module Error : ::Exception
    include Dexpace::Suppressible
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/suppressible"` to `gems/dexpace-core/lib/dexpace.rb`, on the line
**immediately above** phase 1's existing `require_relative "dexpace/error"`, which is itself above
`require_relative "dexpace/error/invalid_argument_error"`.
**Load-bearing require order:** `suppressible` must be required **before** `error`, because
`error.rb` writes `include Dexpace::Suppressible`; and `suppressible.rb` must require nothing,
because anything it required that reaches back to `error.rb` re-enters a load already in progress
and the `include` then runs against an undefined constant. Task 15 Step 1 restates the whole order.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/suppressible_test.rb`
Expected: PASS — 10 runs, 0 failures, 0 errors.

---

## Task 2: Phase-2 Error Trail Integration: `DEF-32` (`Hooks.notify`) and `DEF-27` (`close_quietly(onto:)`)

**Requirement IDs:** none of its own — this task is two **register pick-ups**, `DEF-32` and
`DEF-27`'s first disposal route, against phase-2 code. `RECOV-12` is the rule the trail exists for
and `SEAM-18` is what `Hooks.notify` was built against; neither is re-satisfied here.
**Design:** "`DEF-32`'s pick-up condition is exact: 'the change is confined to `Hooks.notify`:
attach each later failure to the first through `Dexpace.attach_suppressed`, then re-raise as now.'...
`Dexpace.close_quietly` gains one optional keyword, `onto:`, defaulting to `nil`. With `onto:` absent
the behaviour is byte-for-byte today's... With `onto:` supplied, the rescued error is attached to it
through `Dexpace.attach_suppressed` and `close_quietly` still returns `nil` and still does not raise.
`onto:` is validated at entry, before the close is attempted, and that placement is the decision."

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/hooks.rb`,
  `gems/dexpace-core/lib/dexpace/closeable.rb`,
  `gems/dexpace-core/test/dexpace/cancellation_test.rb`,
  `gems/dexpace-core/test/dexpace/closeable_test.rb`

**Interfaces:**
- Consumes: Task 1's `Dexpace.attach_suppressed`.
- Produces: Updated `Dexpace::Hooks.notify` carrying multiple failures on suppressed trail,
  and `Dexpace.close_quietly(resource, onto: nil)` disposing close failures onto a primary error.

- [ ] **Step 1: Write failing tests in `cancellation_test.rb` and `closeable_test.rb`**

In `gems/dexpace-core/test/dexpace/cancellation_test.rb`, add the fourth `Hooks.notify` test:

```ruby
  # DEF-32, P4-12, P4-13.
  test "multiple raising handlers attach later failures to first via Dexpace.attach_suppressed" do
    source = Dexpace::Cancellation::Source.new
    first_err = ::IOError.new("first handler failed")
    second_err = ::RuntimeError.new("second handler failed")

    source.token.on_cancel { raise first_err }
    source.token.on_cancel { "healthy handler ran" }
    source.token.on_cancel { raise second_err }

    caught = assert_raises(::IOError) do
      source.cancel
    end

    assert_same(first_err, caught)
    assert_kind_of(Dexpace::Suppressible, caught)
    refute_kind_of(Dexpace::Error, caught)
    suppressed = Dexpace.suppressed(caught)
    assert_equal(1, suppressed.size)
    assert_same(second_err, suppressed.first)
  end
```

In `gems/dexpace-core/test/dexpace/closeable_test.rb`, add tests for `close_quietly(onto:)`:

```ruby
  # DEF-27.
  test "close_quietly with onto: absent drops error and returns nil" do
    bad_resource = Object.new
    def bad_resource.close; raise ::StandardError, "boom"; end

    assert_nil(Dexpace.close_quietly(bad_resource))
  end

  test "close_quietly with onto: supplied attaches rescued error to onto: and returns nil" do
    bad_resource = Object.new
    def bad_resource.close; raise ::IOError, "close failed"; end

    primary = ::StandardError.new("primary failure")
    result = Dexpace.close_quietly(bad_resource, onto: primary)

    assert_nil(result)
    suppressed = Dexpace.suppressed(primary)
    assert_equal(1, suppressed.size)
    assert_equal("close failed", suppressed.first.message)
  end

  test "close_quietly validates onto: is an Exception before attempting close" do
    closed = false
    resource = Object.new
    resource.define_singleton_method(:close) { closed = true }

    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace.close_quietly(resource, onto: :not_an_exception)
    end
    refute(closed, "resource.close must not be called if onto: is invalid")
  end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/cancellation_test.rb`
Expected: FAIL — `assert_equal(1, suppressed.size)` fails because currently subsequent handler
failures are dropped.
Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/closeable_test.rb`
Expected: FAIL — `ArgumentError: unknown keyword: :onto`.

- [ ] **Step 3: Modify `lib/dexpace/hooks.rb` and `lib/dexpace/closeable.rb`**

In `gems/dexpace-core/lib/dexpace/hooks.rb`, add one `require_relative` and replace phase 2's
`Hooks.notify` — the rest of the file, including the `private_constant :Hooks` and its why-comment,
is untouched. `failure ||= error` becomes the attach, and `raise failure` gains `cause: nil`:

```ruby
require_relative "suppressible"
```

```ruby
    # DEF-32: every hook runs, and the failures AFTER the first are no longer dropped -- each is
    # attached to the first through Dexpace.attach_suppressed, which is the row's own wording.
    # The re-raise carries `cause: nil` because this site re-raises an error it has been CARRYING
    # since an earlier iteration rather than one it just rescued, and a bare `raise` would hand it
    # the caller's in-flight $! as a #cause (verified fact 5). "Re-raise as now" is honoured: the
    # object surfaced is the same object.
    def self.notify(hooks, argument)
      failure = nil
      hooks.each do |hook|
        hook.call(argument)
      rescue ::StandardError => error
        failure ? Dexpace.attach_suppressed(failure, error) : (failure = error)
      end
      raise failure, cause: nil if failure

      nil
    end
```

In `gems/dexpace-core/lib/dexpace/closeable.rb`, add two `require_relative`s and replace phase 2's
`Dexpace.close_quietly` **together with its YARD block** — the shipped comment says "the suppressed
trail is `Dexpace::Error#suppressed`, deferred to phase 4", which names the one carrier that cannot
work here, because the primary at this site is a caller's exception (P4-12). **`module Closeable`
itself is not touched** — no line of the latch, of `#closed?` or of the private `#release` changes:

```ruby
require_relative "suppressible"
require_relative "error/invalid_argument_error"
```

```ruby
  # DEF-27, first disposal route. With `onto:` absent -- every existing call site -- the behaviour
  # is byte-for-byte phase 2's: rescue StandardError, drop it, return nil. With `onto:` supplied
  # the rescued error lands on that error's suppressed trail, and close_quietly still returns nil
  # and still does not raise. §8.1's diagnostic is the SECOND route and is phase 5's; this method
  # gains a keyword and never a second helper, which is what keeps §3.7's "two ways and never a
  # third" true.
  #
  # `onto:` is validated at ENTRY, outside the rescue region, and that placement is the decision:
  # attach_suppressed raises InvalidArgumentError for a non-Exception, and validating inside the
  # rescue would replace the close failure this method was passed to carry with a caller-mistake
  # error -- the one thing §3.7 promises close_quietly never does. A nil `onto:` is the documented
  # no-attach default and is not a caller mistake.
  def self.close_quietly(resource, onto: nil)
    unless onto.nil? || onto.is_a?(::Exception)
      raise Dexpace::InvalidArgumentError, "onto must be an Exception"
    end
    return nil if resource.nil?
    return nil unless resource.respond_to?(:close)

    begin
      resource.close
    rescue ::StandardError => error
      Dexpace.attach_suppressed(onto, error) if onto # DEF-27
    end
    nil
  end
```

- [ ] **Step 4: Update `gems/dexpace-core/sig/dexpace/closeable.rbs`**

Update the signature for `Dexpace.close_quietly`:

```rbs
module Dexpace
  def self.close_quietly: (untyped resource, ?onto: ::Exception?) -> nil
end
```

- [ ] **Step 5: Run tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/cancellation_test.rb`
Expected: PASS — 0 failures, 0 errors.
Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/closeable_test.rb`
Expected: PASS — 0 failures, 0 errors.

---

## Task 3: Cycle-Safe Cause Walk: `Dexpace.each_cause` and Cyclic Error Test Fixtures

**Requirement IDs:** `XCUT-9`.
**Design:** "`XCUT-9` (MUST) — Any classification that walks an error's cause chain MUST be cycle-safe:
it MUST track visited causes by reference identity and terminate on a self-referential or cyclic chain
instead of looping forever... Core therefore has one `Dexpace.each_cause(error)` enumerator, and it
tracks the objects it has seen by **`equal?`** — not `==`... `Dexpace.each_cause` yields the error
itself first, then each cause (P4-16)... The walk treats a raise from `#cause` as the end of the chain
rather than propagating it (Open Question 3)."

**Files:**
- Create: `gems/dexpace-core/test/support/cyclic_errors.rb`,
  `gems/dexpace-core/lib/dexpace/each_cause.rb`,
  `gems/dexpace-core/sig/dexpace/each_cause.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/each_cause_test.rb`

**Interfaces:**
- Consumes: `::Exception`.
- Produces: `Dexpace.each_cause(error) { |e| ... } -> nil` or `-> Enumerator`.

- [ ] **Step 1: Write test support fixtures and the failing test**

Write `gems/dexpace-core/test/support/cyclic_errors.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module CyclicErrorFixtures
  class SelfCause < ::StandardError
    def cause
      self
    end
  end

  class CyclicA < ::StandardError
    attr_accessor :other_cause
    def cause
      @other_cause
    end
  end

  class CyclicB < ::StandardError
    attr_accessor :other_cause
    def cause
      @other_cause
    end
  end

  # R7 fixture: never-raised errors with identical message and #cause override.
  # Overrides ==, eql?, and hash so identity tracking is proven against Set and Array.
  class StructurallyEqualError < ::StandardError
    attr_accessor :custom_cause

    def initialize(msg)
      super(msg)
      @custom_cause = nil
    end

    def cause
      @custom_cause
    end

    def ==(other)
      other.is_a?(StructurallyEqualError) && message == other.message
    end

    def eql?(other)
      self == other
    end

    def hash
      message.hash
    end
  end

  # Open Question 3 fixture: error whose #cause raises an error.
  class RaisingCauseError < ::StandardError
    def cause
      raise ::StandardError, "broken #cause method"
    end
  end
end
```

Write `gems/dexpace-core/test/dexpace/each_cause_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/cyclic_errors"
require "dexpace"

# XCUT-9.
class DexpaceEachCauseTest < DexpaceTestCase
  test "yields the error itself first, then its causes in order (P4-16)" do
    e1 = ::StandardError.new("root")
    e2 = begin
      raise e1
    rescue ::StandardError
      begin
        raise "middle"
      rescue ::StandardError
        raise "top"
      end
    end rescue $!

    walked = Dexpace.each_cause(e2).to_a
    assert_equal(3, walked.size)
    assert_equal("top", walked[0].message)
    assert_equal("middle", walked[1].message)
    assert_equal("root", walked[2].message)
  end

  test "terminates on a self-referential cause" do
    self_error = CyclicErrorFixtures::SelfCause.new("self")
    walked = Dexpace.each_cause(self_error).to_a

    assert_equal(1, walked.size)
    assert_same(self_error, walked.first)
  end

  test "terminates on a two-node cycle and yields each error once by identity" do
    ca = CyclicErrorFixtures::CyclicA.new("a")
    cb = CyclicErrorFixtures::CyclicB.new("b")
    ca.other_cause = cb
    cb.other_cause = ca

    walked = Dexpace.each_cause(ca).to_a
    assert_equal(2, walked.size)
    assert_same(ca, walked[0])
    assert_same(cb, walked[1])
  end

  test "tracks visited causes by reference identity and does not truncate structurally equal errors" do
    # Fixture uses never-raised StructurallyEqualError instances chained by #cause override.
    # An Array-backed or Set-backed walk truncates to 1; compare_by_identity yields 2.
    child = CyclicErrorFixtures::StructurallyEqualError.new("same message")
    parent = CyclicErrorFixtures::StructurallyEqualError.new("same message")
    parent.custom_cause = child

    assert_equal(parent, child, "fixtures must be == equal")
    assert(parent.eql?(child), "fixtures must be eql? equal, which is what defeats a Set")
    assert_equal(parent.hash, child.hash, "fixtures must have identical hash")
    refute_same(parent, child, "fixtures must be distinct objects")

    walked = Dexpace.each_cause(parent).to_a
    assert_equal(2, walked.size)
    assert_same(parent, walked[0])
    assert_same(child, walked[1])
  end

  test "stops at a raising #cause without propagating (Open Question 3)" do
    raising_err = CyclicErrorFixtures::RaisingCauseError.new("raising")
    walked = Dexpace.each_cause(raising_err).to_a

    assert_equal(1, walked.size)
    assert_same(raising_err, walked.first)
  end

  test "returns an Enumerator when called without a block" do
    err = ::StandardError.new("enum")
    enum = Dexpace.each_cause(err)

    assert_instance_of(Enumerator, enum)
    assert_equal([err], enum.to_a)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/each_cause_test.rb`
Expected: FAIL — `undefined method 'each_cause' for module Dexpace`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/each_cause.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # XCUT-9: Walks an error's cause chain cycle-safely, yielding the error itself first,
  # then each cause (P4-16). Tracks visited causes by reference identity through
  # compare_by_identity (verified fact 7).
  def self.each_cause(error, &block)
    return to_enum(:each_cause, error) unless block

    visited = {}.compare_by_identity
    curr = error
    while curr
      break if visited.key?(curr)

      visited[curr] = true
      yield curr
      curr = begin
        curr.cause
      rescue ::StandardError
        # Open Question 3: stop at raising #cause rather than propagating,
        # so a classification is never the thing that crashes.
        nil
      end
    end
    nil
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/each_cause.rbs`**

```rbs
module Dexpace
  def self.each_cause: (::Exception error) -> Enumerator[::Exception, void]
                      | (::Exception error) { (::Exception) -> void } -> void
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/each_cause"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/each_cause_test.rb`
Expected: PASS — 6 runs, 0 failures, 0 errors.

---

## Task 4: `Dexpace::OutcomeError`

**Requirement IDs:** `RECOV-2`, `RECOV-8`, `R6`.
**Design:** "The decision: `Dexpace::OutcomeError` is a `StandardError`, and the orchestrator re-raises
it by name in the same arm that already re-raises the fatal family... Keep it a `StandardError` and
name it in the re-raise arm. Chosen (R6, P4-19)."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/error/outcome_error.rb`,
  `gems/dexpace-core/sig/dexpace/error/outcome_error.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/error/outcome_error_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Error`.
- Produces: `Dexpace::OutcomeError < ::StandardError`, `#offending_class`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# R6, P4-19.
class DexpaceOutcomeErrorTest < DexpaceTestCase
  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::OutcomeError, String
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::OutcomeError, caught)
  end

  test "is a StandardError subclass" do
    assert_operator(Dexpace::OutcomeError, :<, ::StandardError)
  end

  test "carries offending_class and message identifies it" do
    err = Dexpace::OutcomeError.new(Integer)

    assert_equal(Integer, err.offending_class)
    assert_includes(err.message, "Integer")
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/outcome_error_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::OutcomeError`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/error/outcome_error.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # Raised when an unrecognised value is passed to an outcome fold (R6, P4-19).
  # Kept inside StandardError and re-raised by name in the orchestrator's fatal-family
  # arm so core defects are never converted to Failure outcomes.
  class OutcomeError < ::StandardError
    include Dexpace::Error

    attr_reader :offending_class

    def initialize(offending_class)
      @offending_class = offending_class
      super("unexpected outcome value of class #{offending_class} (R6, P4-19)")
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/error/outcome_error.rbs`**

```rbs
module Dexpace
  class OutcomeError < ::StandardError
    include Dexpace::Error
    attr_reader offending_class: Module
    def initialize: (Module offending_class) -> void
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/error/outcome_error"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/outcome_error_test.rb`
Expected: PASS — 3 runs, 0 failures, 0 errors.

---

## Task 5: `Dexpace::ProtocolError`

**Requirement IDs:** `XCUT-4` branch (a), `XCUT-8`, `RECOV-15`.
**Design:** "`Dexpace::ProtocolError` — `< ::StandardError`, `include Dexpace::Error`, carrying
`#response` and `#status`, with a message naming the status code and its canonical name... There is
no per-status subclass tree, and that is P4-20... `ProtocolError.for(response)` raises
`Dexpace::InvalidArgumentError` for a non-error status (`XCUT-8`)... `ProtocolError.for_or_nil(response)`
returns `nil` instead... No `#retryable?` (DEF-38)."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/error/protocol_error.rb`,
  `gems/dexpace-core/sig/dexpace/error/protocol_error.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/error/protocol_error_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Error`, `Dexpace::Response`, `Dexpace::Status`.
- Produces: `Dexpace::ProtocolError`, `ProtocolError.for(response)`,
  `ProtocolError.for_or_nil(response)`, `#response`, `#status`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# XCUT-4, XCUT-8, RECOV-15.
class DexpaceProtocolErrorTest < DexpaceTestCase
  # Dexpace::Response is Data.define(:request, :protocol, :status, :reason, :headers, :body) and
  # HTTP-4 requires all but reason and body, so every response in this phase's suites is built
  # through Response.builder -- which defaults headers to Headers::EMPTY -- on phase 3b's
  # precedent. `Response.build(status:, headers:, body:)` is not a signature that exists.
  def build_response(code)
    request = Dexpace::Request.builder
    request.url = "https://example.test/"
    builder = Dexpace::Response.builder
    builder.request = request.build
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = Dexpace::Status.of(code)
    builder.build
  end

  test "is a Dexpace::Error and StandardError" do
    resp = build_response(404)
    err = Dexpace::ProtocolError.new(resp)

    assert_kind_of(Dexpace::Error, err)
    assert_kind_of(::StandardError, err)
    assert_same(resp, err.response)
    assert_equal(Dexpace::Status.of(404), err.status)
  end

  test "message formats status code and canonical name without body preview (Open Question 5)" do
    err = Dexpace::ProtocolError.new(build_response(404))
    assert_equal("HTTP 404 Not Found", err.message)

    custom_err = Dexpace::ProtocolError.new(build_response(499))
    assert_equal("HTTP 499", custom_err.message)
  end

  test "ProtocolError.for returns error for 400..599 statuses" do
    err400 = Dexpace::ProtocolError.for(build_response(400))
    assert_equal(400, err400.status.code)

    err503 = Dexpace::ProtocolError.for(build_response(503))
    assert_equal(503, err503.status.code)
  end

  test "ProtocolError.for raises InvalidArgumentError for non-error status (XCUT-8)" do
    [200, 201, 301, 304].each do |code|
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::ProtocolError.for(build_response(code))
      end
    end
  end

  test "ProtocolError.for_or_nil returns nil for non-error status (XCUT-8 convenience form)" do
    assert_nil(Dexpace::ProtocolError.for_or_nil(build_response(200)))
    assert_nil(Dexpace::ProtocolError.for_or_nil(build_response(302)))

    err = Dexpace::ProtocolError.for_or_nil(build_response(500))
    assert_instance_of(Dexpace::ProtocolError, err)
    assert_equal(500, err.status.code)
  end

  test "ProtocolError does not define retryable? (DEF-38)" do
    err = Dexpace::ProtocolError.new(build_response(503))
    refute_respond_to(err, :retryable?)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/protocol_error_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::ProtocolError`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/error/protocol_error.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"
require_relative "invalid_argument_error"

module Dexpace
  # XCUT-4 branch (a): Protocol error carrying a fully-received response (status, headers, body).
  # P4-20: One class carrying #status, with no per-status subclass tree.
  class ProtocolError < ::StandardError
    include Dexpace::Error

    attr_reader :response, :status

    def initialize(response)
      @response = response
      @status = response.status
      canonical = status.canonical_name
      # Open Question 5: no body preview; message carries only status and canonical phrase
      msg = canonical ? "HTTP #{status.code} #{canonical}" : "HTTP #{status.code}"
      super(msg)
    end

    def self.for(response)
      unless response.status.error?
        raise Dexpace::InvalidArgumentError, "status #{response.status.code} is not an error status (XCUT-8)"
      end

      new(response)
    end

    def self.for_or_nil(response)
      return nil unless response.status.error?

      new(response)
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/error/protocol_error.rbs`**

```rbs
module Dexpace
  class ProtocolError < ::StandardError
    include Dexpace::Error
    attr_reader response: Dexpace::Response
    attr_reader status: Dexpace::Status
    def initialize: (Dexpace::Response response) -> void
    def self.for: (Dexpace::Response response) -> Dexpace::ProtocolError
    def self.for_or_nil: (Dexpace::Response response) -> Dexpace::ProtocolError?
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/error/protocol_error"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/protocol_error_test.rb`
Expected: PASS — 6 runs, 0 failures, 0 errors.

---

## Task 6: `Dexpace::Outcome`, `Outcome::Success`, and `Outcome::Failure`

**Requirement IDs:** `RECOV-1`.
**Design:** "`RECOV-1` (MUST) — The response-side outcome MUST be a closed sum type with exactly two
variants... `Dexpace::Outcome::Success = Data.define(:response)` and `Dexpace::Outcome::Failure =
Data.define(:error)`... each including `Dexpace::Model` and `Dexpace::Outcome`, each with
`private_class_method :new` and a validating `.build(response:)` / `.build(error:)`...
Standard accessors (#success?, #failure?, #response_or_nil, #error_or_nil) and a fold (#fold) that
applies exactly one branch at most once per call (P4-21, P4-24)."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/outcome.rb`,
  `gems/dexpace-core/sig/dexpace/outcome.rbs`,
  `gems/dexpace-core/test/dexpace/outcome_test.rb`,
  `gems/dexpace-core/lib/dexpace/outcome/success.rb`,
  `gems/dexpace-core/sig/dexpace/outcome/success.rbs`,
  `gems/dexpace-core/test/dexpace/outcome/success_test.rb`,
  `gems/dexpace-core/lib/dexpace/outcome/failure.rb`,
  `gems/dexpace-core/sig/dexpace/outcome/failure.rbs`,
  `gems/dexpace-core/test/dexpace/outcome/failure_test.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`, `Dexpace::Response`, `::Exception`.
- Produces: `Dexpace::Outcome`, `Dexpace::Outcome::Success`, `Dexpace::Outcome::Failure`.

- [ ] **Step 1: Write the failing tests**

Write `gems/dexpace-core/test/dexpace/outcome/success_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# RECOV-1.
class DexpaceOutcomeSuccessTest < DexpaceTestCase
  # Response.builder, not Response.build: HTTP-4 requires :request and :protocol as well as
  # :status, and the builder is what defaults :headers to Headers::EMPTY (phase 3b's precedent).
  def build_response
    request = Dexpace::Request.builder
    request.url = "https://example.test/"
    builder = Dexpace::Response.builder
    builder.request = request.build
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = Dexpace::Status.of(200)
    builder.build
  end

  test "build constructs frozen Success carrying response" do
    resp = build_response
    outcome = Dexpace::Outcome::Success.build(response: resp)

    assert_kind_of(Dexpace::Outcome, outcome)
    assert_predicate(outcome, :frozen?)
    assert_same(resp, outcome.response)
    assert_predicate(outcome, :success?)
    refute_predicate(outcome, :failure?)
    assert_same(resp, outcome.response_or_nil)
    assert_nil(outcome.error_or_nil)
  end

  test "build validates response is required" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Outcome::Success.build(response: nil)
    end
  end

  test "fold applies on_success branch once and returns its result" do
    outcome = Dexpace::Outcome::Success.build(response: build_response)
    calls = []

    res = outcome.fold(
      on_success: ->(r) { calls << :success; :ok },
      on_failure: ->(e) { calls << :failure; :err },
    )

    assert_equal(:ok, res)
    assert_equal([:success], calls)
  end

  test "new constructor is private" do
    assert_raises(NoMethodError) do
      Dexpace::Outcome::Success.new(response: build_response)
    end
  end
end
```

Write `gems/dexpace-core/test/dexpace/outcome/failure_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# RECOV-1.
class DexpaceOutcomeFailureTest < DexpaceTestCase
  test "build constructs frozen Failure carrying error" do
    err = ::StandardError.new("failed")
    outcome = Dexpace::Outcome::Failure.build(error: err)

    assert_kind_of(Dexpace::Outcome, outcome)
    assert_predicate(outcome, :frozen?)
    assert_same(err, outcome.error)
    refute_predicate(outcome, :success?)
    assert_predicate(outcome, :failure?)
    assert_nil(outcome.response_or_nil)
    assert_same(err, outcome.error_or_nil)
  end

  test "build validates error is required and is an Exception" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Outcome::Failure.build(error: nil)
    end

    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Outcome::Failure.build(error: "not an exception")
    end
  end

  test "fold applies on_failure branch once and returns its result" do
    outcome = Dexpace::Outcome::Failure.build(error: ::StandardError.new)
    calls = []

    res = outcome.fold(
      on_success: ->(r) { calls << :success; :ok },
      on_failure: ->(e) { calls << :failure; :err },
    )

    assert_equal(:err, res)
    assert_equal([:failure], calls)
  end

  test "new constructor is private" do
    assert_raises(NoMethodError) do
      Dexpace::Outcome::Failure.new(error: ::StandardError.new)
    end
  end
end
```

Write `gems/dexpace-core/test/dexpace/outcome_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# RECOV-1.
class DexpaceOutcomeTest < DexpaceTestCase
  # Response.builder, not Response.build: HTTP-4 requires :request and :protocol as well as
  # :status, and the builder is what defaults :headers to Headers::EMPTY (phase 3b's precedent).
  def build_response
    request = Dexpace::Request.builder
    request.url = "https://example.test/"
    builder = Dexpace::Response.builder
    builder.request = request.build
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = Dexpace::Status.of(200)
    builder.build
  end

  # Verified fact 14: Data-generated #deconstruct_keys makes case/in work over the two variants
  # even with private_class_method :new. Each branch USES its binding -- an unused pattern binding
  # is an "assigned but unused variable" warning under -w, which DexpaceTestCase fails the test on.
  test "case/in pattern matching matches Success and Failure variants" do
    resp = build_response
    err = ::IOError.new("io")
    s = Dexpace::Outcome::Success.build(response: resp)
    f = Dexpace::Outcome::Failure.build(error: err)

    match_s = case s
    in Dexpace::Outcome::Success[response:]
      [:matched_success, response]
    in Dexpace::Outcome::Failure[error:]
      [:matched_failure, error]
    end
    assert_equal([:matched_success, resp], match_s)

    match_f = case f
    in Dexpace::Outcome::Success[response:]
      [:matched_success, response]
    in Dexpace::Outcome::Failure[error:]
      [:matched_failure, error]
    end
    assert_equal([:matched_failure, err], match_f)
  end

  test "property test: fold agrees with predicates across seeded sequence" do
    rng = Random.new(42) # seed pinned, per the design's testing strategy
    50.times do
      outcome = if rng.rand(2).zero?
        Dexpace::Outcome::Success.build(response: build_response)
      else
        Dexpace::Outcome::Failure.build(error: ::StandardError.new("rnd"))
      end

      branch = outcome.fold(on_success: ->(_) { :s }, on_failure: ->(_) { :f })

      if outcome.success?
        refute(outcome.failure?)
        assert_equal(:s, branch)
      else
        assert(outcome.failure?)
        assert_equal(:f, branch)
      end
    end
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/outcome_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Outcome`.

- [ ] **Step 3: Write `lib/dexpace/outcome.rb`, `outcome/success.rb`, and `outcome/failure.rb`**

Write `gems/dexpace-core/lib/dexpace/outcome.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # RECOV-1: Closed sum type with exactly two variants: Success and Failure.
  # Both variants include this module.
  module Outcome
  end
end
```

Write `gems/dexpace-core/lib/dexpace/outcome/success.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../outcome"

module Dexpace
  module Outcome
    # RECOV-1: Success variant carrying a Response.
    class Success < Data.define(:response)
      include Dexpace::Model
      include Dexpace::Outcome

      private_class_method :new

      def self.build(response:)
        Model.required!("response", response) # phase 1's signature is (name, value)
        new(response: response)
      end

      def success?
        true
      end

      def failure?
        false
      end

      # P4-21: RECOV-1 requires response-or-null, error-or-null accessors.
      def response_or_nil
        response
      end

      def error_or_nil
        nil
      end

      def fold(on_success:, on_failure:)
        on_success.call(response)
      end
    end
  end
end
```

Write `gems/dexpace-core/lib/dexpace/outcome/failure.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../outcome"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Outcome
    # RECOV-1: Failure variant carrying an Exception.
    class Failure < Data.define(:error)
      include Dexpace::Model
      include Dexpace::Outcome

      private_class_method :new

      def self.build(error:)
        Model.required!("error", error) # phase 1's signature is (name, value)
        unless error.is_a?(::Exception)
          raise Dexpace::InvalidArgumentError, "error must be an Exception"
        end

        new(error: error)
      end

      def success?
        false
      end

      def failure?
        true
      end

      # P4-21: RECOV-1 requires response-or-null, error-or-null accessors.
      def response_or_nil
        nil
      end

      def error_or_nil
        error
      end

      def fold(on_success:, on_failure:)
        on_failure.call(error)
      end
    end
  end
end
```

- [ ] **Step 4: Write RBS files**

Write `gems/dexpace-core/sig/dexpace/outcome.rbs`:

```rbs
module Dexpace
  module Outcome
    type t = Success | Failure
  end
end
```

Write `gems/dexpace-core/sig/dexpace/outcome/success.rbs`:

```rbs
module Dexpace
  module Outcome
    class Success
      include Dexpace::Model
      include Dexpace::Outcome
      attr_reader response: Dexpace::Response
      def self.build: (response: Dexpace::Response) -> Dexpace::Outcome::Success
      def success?: () -> true
      def failure?: () -> false
      def response_or_nil: () -> Dexpace::Response
      def error_or_nil: () -> nil
      def fold: [T] (on_success: ^(Dexpace::Response) -> T, on_failure: ^(::Exception) -> T) -> T
    end
  end
end
```

Write `gems/dexpace-core/sig/dexpace/outcome/failure.rbs`:

```rbs
module Dexpace
  module Outcome
    class Failure
      include Dexpace::Model
      include Dexpace::Outcome
      attr_reader error: ::Exception
      def self.build: (error: ::Exception) -> Dexpace::Outcome::Failure
      def success?: () -> false
      def failure?: () -> true
      def response_or_nil: () -> nil
      def error_or_nil: () -> ::Exception
      def fold: [T] (on_success: ^(Dexpace::Response) -> T, on_failure: ^(::Exception) -> T) -> T
    end
  end
end
```

- [ ] **Step 5: Add requires to `lib/dexpace.rb`**

Add to `gems/dexpace-core/lib/dexpace.rb`:
`require_relative "dexpace/outcome"`
`require_relative "dexpace/outcome/success"`
`require_relative "dexpace/outcome/failure"`

- [ ] **Step 6: Run tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/outcome_test.rb`
Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/outcome/success_test.rb`
Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/outcome/failure_test.rb`
Expected: PASS — all 3 test files passing, 0 failures, 0 errors.

---

## Task 7: `Dexpace::Recovery` and `Recovery.buffer_error_body`

**Requirement IDs:** `RECOV-16`, `BODY-30`. (`HTTP-52`'s bounded copy is phase 3b's and phase 1's —
the design's out-of-scope table says so in as many words; 4b ships only the step that calls it, and
this task claims no row for it.)
**Design:** "`Dexpace::Recovery.buffer_error_body(response) -> Response`... returns the response
unchanged when `status.error?` is false or the body is `nil`; otherwise calls
`Body.buffer_bounded(body, cap: Body::MAX_BUFFERED_ERROR_BODY_BYTES)` and returns
`response.with(body: buffered)`... Reads `Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES` and declares
no second constant (R9, Boundary 10)."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/recovery.rb`,
  `gems/dexpace-core/sig/dexpace/recovery.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/recovery_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Body.buffer_bounded`, `Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES`,
  `Dexpace::Response`.
- Produces: `Dexpace::Recovery.buffer_error_body(response)`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# RECOV-16, BODY-30. Status#error? is phase 1's and the bound is phase 3b's; this suite exercises
# only the step that reads both.
class DexpaceRecoveryTest < DexpaceTestCase
  # Response.builder, not Response.build (HTTP-4's six members); ResponseBody, not BufferBody,
  # because BufferBody wraps a Dexpace::IO::Buffer and rejects a String, and because a
  # single-use closable body is what the error path actually holds.
  def build_response(code, body = nil)
    request = Dexpace::Request.builder
    request.url = "https://example.test/"
    builder = Dexpace::Response.builder
    builder.request = request.build
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = Dexpace::Status.of(code)
    builder.body = body
    builder.build
  end

  def response_body(content)
    Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes(content))
  end

  test "buffer_error_body returns response unchanged by identity when status is not an error" do
    body = response_body("ok")
    resp = build_response(200, body)

    result = Dexpace::Recovery.buffer_error_body(resp)
    assert_same(resp, result)
    refute_predicate(body, :closed?)
  end

  test "buffer_error_body returns response unchanged by identity when body is nil" do
    resp = build_response(500, nil)

    result = Dexpace::Recovery.buffer_error_body(resp)
    assert_same(resp, result)
  end

  test "buffer_error_body buffers error body and original body is closed" do
    body = response_body("error payload")
    resp = build_response(500, body)

    result = Dexpace::Recovery.buffer_error_body(resp)

    refute_same(resp, result)
    assert_equal("error payload", result.body_string)
    assert_predicate(body, :closed?)
  end

  test "buffer_error_body truncates over-cap body to MAX_BUFFERED_ERROR_BODY_BYTES without marker" do
    # Boundary 10: the assertion names the constant rather than 1024 * 1024, so a second
    # constant would break this test rather than pass it.
    cap = Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES
    body = response_body("x" * (cap + 1))
    resp = build_response(503, body)

    result = Dexpace::Recovery.buffer_error_body(resp)
    buffered_bytes = result.body_bytes

    assert_equal(cap, buffered_bytes.bytesize)
    assert_equal("x" * cap, buffered_bytes)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/recovery_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Recovery`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/recovery.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "http/body"

module Dexpace
  # RECOV namespace holding recovery-chain machinery and error-body buffering.
  module Recovery
    # RECOV-16, BODY-30: Buffers error body into a bounded replayable in-memory copy
    # before mapping to a typed exception. Reads Body::MAX_BUFFERED_ERROR_BODY_BYTES
    # and declares no second constant (Boundary 10).
    def self.buffer_error_body(response)
      return response unless response.status.error?

      body = response.body
      return response if body.nil?

      buffered = Dexpace::Body.buffer_bounded(
        body,
        cap: Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES,
      )
      response.with(body: buffered)
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/recovery.rbs`**

```rbs
module Dexpace
  module Recovery
    def self.buffer_error_body: (Dexpace::Response response) -> Dexpace::Response
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/recovery"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/recovery_test.rb`
Expected: PASS — 4 runs, 0 failures, 0 errors.

---

## Task 8: `Dexpace::Recovery::Transform` Contract

**Requirement IDs:** R8 contract for `RECOV-32`, `RECOV-33`, `RECOV-15`, and 4c integration.
**Design:** "The shared thing is a pure transform, `#apply(value)`, and each layer reaches it
through one generic mechanism written once rather than once per step... `Transform#call(value)`
forwards to `#apply(value)`, so a `:request` transform is a `RequestChain` step and a `:response`
transform is a `ResponseChain` response step, each by the ordinary `#call` protocol of clause 3...
`#call` is the module's one default implementation (P4-24, P4-25)."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/recovery/transform.rb`,
  `gems/dexpace-core/sig/dexpace/recovery/transform.rbs`,
  `gems/dexpace-core/test/dexpace/recovery/transform_test.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`

**Interfaces:**
- Consumes: none.
- Produces: `Dexpace::Recovery::Transform` module with `#phase`, `#apply(value)`,
  and default `#call(value) = apply(value)`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# R8, P4-25.
class DexpaceRecoveryTransformTest < DexpaceTestCase
  class DummyTransform
    include Dexpace::Recovery::Transform

    def phase
      :request
    end

    def apply(value)
      "transformed: #{value}"
    end
  end

  test "dummy transform defines phase and apply" do
    t = DummyTransform.new
    assert_equal(:request, t.phase)
    assert_equal("transformed: input", t.apply("input"))
  end

  test "Transform#call forwards to #apply by default (P4-25)" do
    t = DummyTransform.new
    assert_equal("transformed: input", t.call("input"))
  end

  test "Transform un-implemented phase and apply raise NotImplementedError" do
    naked = Object.new
    naked.extend(Dexpace::Recovery::Transform)

    assert_raises(NotImplementedError) { naked.phase }
    assert_raises(NotImplementedError) { naked.apply("val") }
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/recovery/transform_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Recovery::Transform`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/recovery/transform.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Recovery
    # R8 contract: Pure transform interface implemented by IdempotencyKeyStep,
    # ClientIdentityStep, and ErrorMappingStep.
    # P4-25: Provides default implementation def call(value) = apply(value)
    # so a transform is directly usable as a chain step without an adapter.
    module Transform
      def phase
        raise ::NotImplementedError, "#{self.class}#phase must be implemented"
      end

      def apply(value)
        raise ::NotImplementedError, "#{self.class}#apply must be implemented"
      end

      def call(value)
        apply(value)
      end
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/recovery/transform.rbs`**

```rbs
module Dexpace
  module Recovery
    module Transform
      def phase: () -> Symbol
      def apply: [T] (T value) -> T
      def call: [T] (T value) -> T
    end

    interface _Transform
      def phase: () -> Symbol
      def apply: [T] (T value) -> T
      def call: [T] (T value) -> T
    end
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/recovery/transform"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/recovery/transform_test.rb`
Expected: PASS — 3 runs, 0 failures, 0 errors.

---

## Task 9: `Dexpace::Recovery::IdempotencyKeyStep`

**Requirement IDs:** `RECOV-32`.
**Design:** "`.build(header:, strategy:, methods: [Method::POST, Method::PUT, Method::PATCH], mode: :respect_existing)`.
`#phase` is `:request`... Adds the header only for a method in `methods`; every other method passes
through by identity... In `:respect_existing` (the default) a request already carrying the header is
returned by identity and `strategy` is not called at all... In `:overwrite` the strategy's result
replaces every existing value... The strategy is invoked at most once per applicable request."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/recovery/idempotency_key_step.rb`,
  `gems/dexpace-core/sig/dexpace/recovery/idempotency_key_step.rbs`,
  `gems/dexpace-core/test/dexpace/recovery/idempotency_key_step_test.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`

**Interfaces:**
- Consumes: `Dexpace::Recovery::Transform`, `Dexpace::Method`, `Dexpace::Request`, `Dexpace::Headers`.
- Produces: `Dexpace::Recovery::IdempotencyKeyStep`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# RECOV-32.
class DexpaceRecoveryIdempotencyKeyStepTest < DexpaceTestCase
  # HTTP-5's second tier: Headers#[] returns the name's own frozen VALUE LIST, not one string,
  # so every header assertion in this suite compares an Array.
  def build_request(method: Dexpace::Method::POST, headers: Dexpace::Headers::EMPTY)
    Dexpace::Request.build(
      method: method,
      url: "https://example.com/api",
      headers: headers,
      body: nil,
    )
  end

  def headers_with(name, *values)
    values.reduce(Dexpace::Headers.builder) { |b, value| b.add(name, value) }.build
  end

  test "phase is :request and step includes Transform" do
    step = Dexpace::Recovery::IdempotencyKeyStep.build(
      header: "Idempotency-Key",
      strategy: ->(_) { "k1" },
    )

    assert_kind_of(Dexpace::Recovery::Transform, step)
    assert_equal(:request, step.phase)
  end

  test "non-applicable method passes through by identity without calling strategy" do
    calls = 0
    step = Dexpace::Recovery::IdempotencyKeyStep.build(
      header: "Idempotency-Key",
      strategy: ->(_) { calls += 1; "k1" },
    )
    req = build_request(method: Dexpace::Method::GET)

    result = step.apply(req)

    assert_same(req, result)
    assert_equal(0, calls)
  end

  test "applicable method stamps header and invokes strategy at most once" do
    calls = 0
    step = Dexpace::Recovery::IdempotencyKeyStep.build(
      header: "Idempotency-Key",
      strategy: ->(_) { calls += 1; "unique-key" },
    )
    req = build_request(method: Dexpace::Method::POST)

    result = step.apply(req)

    refute_same(req, result)
    assert_equal(["unique-key"], result.headers["Idempotency-Key"])
    assert_equal(1, calls)
  end

  test "respect_existing mode does not invoke strategy if header already present" do
    calls = 0
    existing_headers = headers_with("Idempotency-Key", "existing-key")
    req = build_request(method: Dexpace::Method::POST, headers: existing_headers)

    step = Dexpace::Recovery::IdempotencyKeyStep.build(
      header: "Idempotency-Key",
      strategy: ->(_) { calls += 1; "fresh-key" },
      mode: :respect_existing,
    )

    result = step.apply(req)

    assert_same(req, result)
    assert_equal(["existing-key"], result.headers["Idempotency-Key"])
    assert_equal(0, calls)
  end

  test "overwrite mode invokes strategy and replaces existing header value" do
    calls = 0
    existing_headers = headers_with("Idempotency-Key", "existing-key", "second-key")
    req = build_request(method: Dexpace::Method::POST, headers: existing_headers)

    step = Dexpace::Recovery::IdempotencyKeyStep.build(
      header: "Idempotency-Key",
      strategy: ->(_) { calls += 1; "new-key" },
      mode: :overwrite,
    )

    result = step.apply(req)

    refute_same(req, result)
    # RECOV-32: in :overwrite the strategy result overwrites ANY existing value, so both go.
    assert_equal(["new-key"], result.headers["Idempotency-Key"])
    assert_equal(1, calls)
  end

  test "validates required parameters and mode" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Recovery::IdempotencyKeyStep.build(header: nil, strategy: ->(_) {})
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Recovery::IdempotencyKeyStep.build(header: "K", strategy: nil)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Recovery::IdempotencyKeyStep.build(header: "K", strategy: ->(_) {}, mode: :bad)
    end
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/recovery/idempotency_key_step_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Recovery::IdempotencyKeyStep`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/recovery/idempotency_key_step.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "transform"
require_relative "../http/method"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Recovery
    # RECOV-32: Idempotency-key request step.
    class IdempotencyKeyStep
      include Transform

      # RECOV-32's default method set. A private_constant, because P4-24 fixes the public
      # constants this phase adds and this is not one of them; a private constant is still
      # reachable by its unqualified name from inside the class, which is where the default
      # parameter is evaluated.
      DEFAULT_METHODS = [
        Dexpace::Method::POST,
        Dexpace::Method::PUT,
        Dexpace::Method::PATCH,
      ].freeze
      private_constant :DEFAULT_METHODS

      attr_reader :header, :strategy, :methods, :mode

      private_class_method :new

      def self.build(header:, strategy:, methods: DEFAULT_METHODS, mode: :respect_existing)
        raise Dexpace::InvalidArgumentError, "header is required" if header.nil? || header.empty?
        raise Dexpace::InvalidArgumentError, "strategy is required" if strategy.nil?
        unless mode == :respect_existing || mode == :overwrite
          raise Dexpace::InvalidArgumentError, "mode must be :respect_existing or :overwrite"
        end

        new(
          header: header,
          strategy: strategy,
          methods: methods.dup.freeze,
          mode: mode,
        )
      end

      def initialize(header:, strategy:, methods:, mode:)
        @header = header
        @strategy = strategy
        @methods = methods
        @mode = mode
      end

      def phase
        :request
      end

      def apply(request)
        return request unless @methods.include?(request.method)

        if @mode == :respect_existing && request.headers.include?(@header)
          return request
        end

        key = @strategy.call(request)
        builder = request.headers.new_builder
        if @mode == :overwrite
          builder.set(@header, key)
        else
          builder.add(@header, key)
        end
        request.with(headers: builder.build)
      end
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/recovery/idempotency_key_step.rbs`**

```rbs
module Dexpace
  module Recovery
    class IdempotencyKeyStep
      include Transform
      attr_reader header: String
      attr_reader strategy: ^(Dexpace::Request) -> String
      attr_reader methods: Array[Dexpace::Method]
      attr_reader mode: Symbol
      def self.build: (
        header: String,
        strategy: ^(Dexpace::Request) -> String,
        ?methods: Array[Dexpace::Method],
        ?mode: Symbol
      ) -> Dexpace::Recovery::IdempotencyKeyStep
      def phase: () -> :request
      def apply: (Dexpace::Request request) -> Dexpace::Request
    end
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/recovery/idempotency_key_step"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/recovery/idempotency_key_step_test.rb`
Expected: PASS — 6 runs, 0 failures, 0 errors.

---

## Task 10: `Dexpace::Recovery::ClientIdentityStep`

**Requirement IDs:** `RECOV-33`.
**Design:** "`.build(header:, tokens:, mode: :append)`. `#phase` is `:request`... Joins `tokens`
into one space-separated line... `:append` (default) appends the line after the first existing value,
preserving every other value; sets it as the sole value when the header is absent. `:replace`
overwrites all values... An empty token list, or one joining to a blank or whitespace-only line, makes
the step a no-op... In `:append` mode an empty first existing value is treated as absent."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/recovery/client_identity_step.rb`,
  `gems/dexpace-core/sig/dexpace/recovery/client_identity_step.rbs`,
  `gems/dexpace-core/test/dexpace/recovery/client_identity_step_test.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`

**Interfaces:**
- Consumes: `Dexpace::Recovery::Transform`, `Dexpace::Request`, `Dexpace::Headers`.
- Produces: `Dexpace::Recovery::ClientIdentityStep`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# RECOV-33.
class DexpaceRecoveryClientIdentityStepTest < DexpaceTestCase
  # HTTP-5's second tier: Headers#[] returns the name's own frozen VALUE LIST, which is what makes
  # RECOV-33's "preserving all other pre-existing values" clause assertable at all.
  def build_request(headers = Dexpace::Headers::EMPTY)
    Dexpace::Request.build(
      method: Dexpace::Method::GET,
      url: "https://example.com/api",
      headers: headers,
      body: nil,
    )
  end

  def headers_with(name, *values)
    values.reduce(Dexpace::Headers.builder) { |b, value| b.add(name, value) }.build
  end

  test "phase is :request and step includes Transform" do
    step = Dexpace::Recovery::ClientIdentityStep.build(
      header: "User-Agent",
      tokens: ["dexpace/1.0"],
    )

    assert_kind_of(Dexpace::Recovery::Transform, step)
    assert_equal(:request, step.phase)
  end

  test "sets header when initially absent" do
    step = Dexpace::Recovery::ClientIdentityStep.build(
      header: "User-Agent",
      tokens: ["sdk/1.0", "custom/2.0"],
      mode: :append,
    )
    req = build_request

    result = step.apply(req)
    assert_equal(["sdk/1.0 custom/2.0"], result.headers["User-Agent"])
  end

  test "append mode appends after first existing value with space separation" do
    headers = headers_with("User-Agent", "host-client/3.0")
    req = build_request(headers)

    step = Dexpace::Recovery::ClientIdentityStep.build(
      header: "User-Agent",
      tokens: ["sdk/1.0"],
      mode: :append,
    )

    result = step.apply(req)
    assert_equal(["host-client/3.0 sdk/1.0"], result.headers["User-Agent"])
  end

  # RECOV-33's parenthesis, and the half a single-valued fixture cannot catch: append touches the
  # FIRST value and preserves every other pre-existing one, so Headers::Builder#set alone -- which
  # replaces the whole list -- is the wrong mechanism.
  test "append mode preserves every pre-existing value after the first" do
    headers = headers_with("User-Agent", "host-client/3.0", "proxy/1.2", "edge/0.9")
    req = build_request(headers)

    step = Dexpace::Recovery::ClientIdentityStep.build(
      header: "User-Agent",
      tokens: ["sdk/1.0"],
      mode: :append,
    )

    result = step.apply(req)
    assert_equal(["host-client/3.0 sdk/1.0", "proxy/1.2", "edge/0.9"],
                 result.headers["User-Agent"],)
  end

  test "replace mode overwrites all existing values" do
    headers = headers_with("User-Agent", "old-client/1.0", "proxy/1.2")
    req = build_request(headers)

    step = Dexpace::Recovery::ClientIdentityStep.build(
      header: "User-Agent",
      tokens: ["sdk/2.0"],
      mode: :replace,
    )

    result = step.apply(req)
    assert_equal(["sdk/2.0"], result.headers["User-Agent"])
  end

  test "empty token list or whitespace-only line is a no-op returning request by identity" do
    req = build_request

    step1 = Dexpace::Recovery::ClientIdentityStep.build(header: "User-Agent", tokens: [])
    assert_same(req, step1.apply(req))

    step2 = Dexpace::Recovery::ClientIdentityStep.build(header: "User-Agent", tokens: ["  ", ""])
    assert_same(req, step2.apply(req))
  end

  test "append mode with empty first existing value emits no leading space" do
    headers = headers_with("User-Agent", "")
    req = build_request(headers)

    step = Dexpace::Recovery::ClientIdentityStep.build(
      header: "User-Agent",
      tokens: ["sdk/1.0"],
      mode: :append,
    )

    result = step.apply(req)
    assert_equal(["sdk/1.0"], result.headers["User-Agent"])
  end

  test "validates required parameters and mode" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Recovery::ClientIdentityStep.build(header: nil, tokens: ["t"])
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Recovery::ClientIdentityStep.build(header: "H", tokens: nil)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Recovery::ClientIdentityStep.build(header: "H", tokens: ["t"], mode: :unknown)
    end
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/recovery/client_identity_step_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Recovery::ClientIdentityStep`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/recovery/client_identity_step.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "transform"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Recovery
    # RECOV-33: Client-identity request step.
    class ClientIdentityStep
      include Transform

      attr_reader :header, :tokens, :mode

      private_class_method :new

      def self.build(header:, tokens:, mode: :append)
        raise Dexpace::InvalidArgumentError, "header is required" if header.nil? || header.empty?
        raise Dexpace::InvalidArgumentError, "tokens is required" if tokens.nil?
        unless mode == :append || mode == :replace
          raise Dexpace::InvalidArgumentError, "mode must be :append or :replace"
        end

        new(header: header, tokens: tokens.dup.freeze, mode: mode)
      end

      def initialize(header:, tokens:, mode:)
        @header = header
        @tokens = tokens
        @mode = mode
      end

      def phase
        :request
      end

      def apply(request)
        # RECOV-33: an empty token list, or one joining to a blank or whitespace-only line, is a
        # no-op and must not emit a blank header. The request comes back by identity.
        line = @tokens.join(" ").strip
        return request if line.empty?

        existing = request.headers[@header] # HTTP-5: the name's own value list, or nil
        builder = request.headers.new_builder
        if @mode == :replace || existing.nil?
          builder.set(@header, line)
        else
          # :append -- the line goes after the FIRST existing value and every OTHER pre-existing
          # value survives, which #set alone cannot do because it replaces the whole list. An
          # empty first value is treated as absent, so no leading space is emitted.
          first = existing.first
          builder.set(@header, first.strip.empty? ? line : "#{first} #{line}")
          existing.drop(1).each { |value| builder.add(@header, value) }
        end
        request.with(headers: builder.build)
      end
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/recovery/client_identity_step.rbs`**

```rbs
module Dexpace
  module Recovery
    class ClientIdentityStep
      include Transform
      attr_reader header: String
      attr_reader tokens: Array[String]
      attr_reader mode: Symbol
      def self.build: (
        header: String,
        tokens: Array[String],
        ?mode: Symbol
      ) -> Dexpace::Recovery::ClientIdentityStep
      def phase: () -> :request
      def apply: (Dexpace::Request request) -> Dexpace::Request
    end
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/recovery/client_identity_step"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/recovery/client_identity_step_test.rb`
Expected: PASS — 8 runs, 0 failures, 0 errors.

---

## Task 11: `Dexpace::Recovery::ErrorMappingStep`

**Requirement IDs:** `RECOV-15`, `RECOV-16`, `XCUT-8`, `PIPE-37`. (`BODY-31`'s
error-statuses-only predicate is phase 1's `Status#error?` and phase 3b's negative guarantee, both
built and both dispositioned there by the design's out-of-scope table; this task claims no row for
it and writes no second predicate.)
**Design:** "`.build(factory: Dexpace::ProtocolError.method(:for))`... `#phase` is `:response`...
Only 400..599 are errors (`Status#error?`). A 1xx, 2xx or 3xx response is returned by identity, body
not read, consumed or closed — `PIPE-37`'s parenthesised clause, asserted by `assert_same` plus an
assertion that `#source` was never called on the body... On an error status it calls
`Recovery.buffer_error_body` first (`RECOV-16`), then `factory` on the buffered response, then raises
the result... `factory:` defaults to core's ProtocolError.for via private frozen lambda (Open Question 2)."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/recovery/error_mapping_step.rb`,
  `gems/dexpace-core/sig/dexpace/recovery/error_mapping_step.rbs`,
  `gems/dexpace-core/test/dexpace/recovery/error_mapping_step_test.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`

**Interfaces:**
- Consumes: `Dexpace::Recovery::Transform`, `Dexpace::Recovery.buffer_error_body`,
  `Dexpace::ProtocolError`, `Dexpace::Response`, `Dexpace::Status`.
- Produces: `Dexpace::Recovery::ErrorMappingStep`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# RECOV-15, RECOV-16, XCUT-8, PIPE-37.
class DexpaceRecoveryErrorMappingStepTest < DexpaceTestCase
  # Dexpace::Body is a MODULE (phase 3b), so a fake body includes it -- and includes
  # Dexpace::Closeable after it, the order phase 3b uses everywhere a body is closable, so the
  # latch's #close wins over the module's no-op default.
  class SpyingBody
    include Dexpace::Body
    include Dexpace::Closeable

    attr_reader :source_called

    def initialize
      initialize_closeable
      @source_called = false
    end

    def source
      @source_called = true
      Dexpace::IO::BufferedSource.of_bytes("content")
    end

    private

    def release
      nil
    end
  end

  def build_response(code, body = nil)
    request = Dexpace::Request.builder
    request.url = "https://example.test/"
    builder = Dexpace::Response.builder
    builder.request = request.build
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = Dexpace::Status.of(code)
    builder.body = body
    builder.build
  end

  def response_body(content)
    Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes(content))
  end

  test "phase is :response and step includes Transform" do
    step = Dexpace::Recovery::ErrorMappingStep.build
    assert_kind_of(Dexpace::Recovery::Transform, step)
    assert_equal(:response, step.phase)
  end

  test "non-error response returned by identity and body not read, consumed or closed (PIPE-37)" do
    step = Dexpace::Recovery::ErrorMappingStep.build
    spy_body = SpyingBody.new
    resp = build_response(200, spy_body)

    result = step.apply(resp)

    assert_same(resp, result)
    refute(spy_body.source_called, "body#source must never be called on non-error response")
    refute_predicate(spy_body, :closed?)
  end

  test "error response buffers body and raises ProtocolError by default" do
    step = Dexpace::Recovery::ErrorMappingStep.build
    body = response_body("error payload")
    resp = build_response(404, body)

    raised = assert_raises(Dexpace::ProtocolError) do
      step.apply(resp)
    end

    assert_equal(404, raised.status.code)
    assert_equal("error payload", raised.response.body_string)
    assert_predicate(body, :closed?, "original body must be closed by buffering")
  end

  test "custom factory can map response to alternative exception" do
    custom_error_class = Class.new(StandardError)
    custom_factory = ->(r) { custom_error_class.new("status: #{r.status.code}") }

    step = Dexpace::Recovery::ErrorMappingStep.build(factory: custom_factory)
    resp = build_response(500, response_body("server error"))

    raised = assert_raises(custom_error_class) do
      step.apply(resp)
    end

    assert_equal("status: 500", raised.message)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/recovery/error_mapping_step_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Recovery::ErrorMappingStep`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/recovery/error_mapping_step.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "transform"
require_relative "../error/protocol_error"
require_relative "../recovery"

module Dexpace
  module Recovery
    # RECOV-15, RECOV-16, XCUT-8: Status-to-typed-exception response step.
    class ErrorMappingStep
      include Transform

      # Open Question 2: Frozen lambda default factory avoiding Method allocation.
      DEFAULT_FACTORY = ->(response) { Dexpace::ProtocolError.for(response) }.freeze
      private_constant :DEFAULT_FACTORY

      attr_reader :factory

      private_class_method :new

      def self.build(factory: DEFAULT_FACTORY)
        new(factory: factory)
      end

      def initialize(factory:)
        @factory = factory
      end

      def phase
        :response
      end

      def apply(response)
        # PIPE-37: Non-error status returned untouched (body not read, consumed or closed)
        return response unless response.status.error?

        # RECOV-16: Buffer error body before mapping
        buffered = Dexpace::Recovery.buffer_error_body(response)
        error = @factory.call(buffered)
        raise error
      end
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/recovery/error_mapping_step.rbs`**

```rbs
module Dexpace
  module Recovery
    class ErrorMappingStep
      include Transform
      attr_reader factory: ^(Dexpace::Response) -> ::Exception
      def self.build: (
        ?factory: ^(Dexpace::Response) -> ::Exception
      ) -> Dexpace::Recovery::ErrorMappingStep
      def phase: () -> :response
      def apply: (Dexpace::Response response) -> Dexpace::Response
    end
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/recovery/error_mapping_step"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/recovery/error_mapping_step_test.rb`
Expected: PASS — 4 runs, 0 failures, 0 errors.

---

## Task 12: `Dexpace::Recovery::RequestChain`

**Requirement IDs:** `RECOV-3`, `RECOV-14`.
**Design:** "`RequestChain` — `RECOV-3`, `RECOV-14`. A class (`data-modeling/3e37c086`: it owns state).
`.build(steps: [])`, `#apply(request) -> Request`, `#steps -> Array` (frozen)... Left-to-right fold;
the output of step N is the input of step N+1. `Array#reduce`, never `Enumerator#next`... An empty
chain returns the input unchanged, by identity... A throwing step aborts the remainder and propagates...
The list is copied and frozen at construction (`RECOV-14`, P4-22)."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/recovery/request_chain.rb`,
  `gems/dexpace-core/sig/dexpace/recovery/request_chain.rbs`,
  `gems/dexpace-core/test/dexpace/recovery/request_chain_test.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`

**Interfaces:**
- Consumes: `Dexpace::Request`.
- Produces: `Dexpace::Recovery::RequestChain`, `#apply(request)`, `#steps`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# RECOV-3, RECOV-14.
class DexpaceRecoveryRequestChainTest < DexpaceTestCase
  def build_request(url = "https://example.com/api")
    Dexpace::Request.build(
      method: Dexpace::Method::GET,
      url: url,
      headers: Dexpace::Headers::EMPTY,
      body: nil,
    )
  end

  test "empty chain returns input request unchanged by identity" do
    chain = Dexpace::Recovery::RequestChain.build
    req = build_request

    assert_same(req, chain.apply(req))
    assert_equal([], chain.steps)
    assert_predicate(chain.steps, :frozen?)
  end

  test "applies steps in sequential left-to-right fold (output of N is input of N+1)" do
    # Request#url is the frozen URI::Generic that URL.parse! returned, not a String, so the
    # assertion goes through #to_s -- comparing a String to a URI silently fails.
    step1 = ->(r) { r.with(url: "#{r.url}/step1") }
    step2 = ->(r) { r.with(url: "#{r.url}/step2") }
    chain = Dexpace::Recovery::RequestChain.build(steps: [step1, step2])
    req = build_request

    result = chain.apply(req)
    assert_equal("https://example.com/api/step1/step2", result.url.to_s)
  end

  test "throwing step aborts remaining steps and propagates to caller (RECOV-3)" do
    step1_ran = false
    step2_ran = false
    step3_ran = false

    step1 = ->(r) { step1_ran = true; r }
    step2 = ->(_) { step2_ran = true; raise ::IOError, "step 2 broke" }
    step3 = ->(r) { step3_ran = true; r }

    chain = Dexpace::Recovery::RequestChain.build(steps: [step1, step2, step3])

    err = assert_raises(::IOError) do
      chain.apply(build_request)
    end

    assert_equal("step 2 broke", err.message)
    assert(step1_ran, "step 1 must run")
    assert(step2_ran, "step 2 must run")
    refute(step3_ran, "step 3 must not run after step 2 throws")
  end

  test "defensively copies and freezes step list at construction (RECOV-14, P4-22)" do
    caller_array = [->(r) { r }]
    chain = Dexpace::Recovery::RequestChain.build(steps: caller_array)

    caller_array << ->(r) { r.with(url: "https://mutated.com") }

    assert_equal(1, chain.steps.size)
    assert_predicate(chain.steps, :frozen?)
    assert_raises(FrozenError) { chain.steps << ->(r) { r } }
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/recovery/request_chain_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Recovery::RequestChain`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/recovery/request_chain.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Recovery
    # RECOV-3, RECOV-14: Sequential left-to-right fold over request steps.
    class RequestChain
      attr_reader :steps

      private_class_method :new

      def self.build(steps: [])
        # P4-22: dup and freeze step list rather than routing through Model.own
        new(steps: steps.dup.freeze)
      end

      def initialize(steps:)
        @steps = steps
      end

      def apply(request)
        # RECOV-3: Left-to-right fold. If a step throws, propagates and aborts remainder.
        @steps.reduce(request) do |req, step|
          step.call(req)
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/recovery/request_chain.rbs`**

```rbs
module Dexpace
  module Recovery
    class RequestChain
      attr_reader steps: Array[^(Dexpace::Request) -> Dexpace::Request]
      def self.build: (
        ?steps: Array[^(Dexpace::Request) -> Dexpace::Request]
      ) -> Dexpace::Recovery::RequestChain
      def apply: (Dexpace::Request request) -> Dexpace::Request
    end
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/recovery/request_chain"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/recovery/request_chain_test.rb`
Expected: PASS — 4 runs, 0 failures, 0 errors.

---

## Task 13: `Dexpace::Recovery::Ownership` (private) and `Dexpace::Recovery::ResponseChain`

**Requirement IDs:** `RECOV-4`, `RECOV-5`, `RECOV-6`, `RECOV-7`, `RECOV-8`, `RECOV-9`,
`RECOV-12`, `RECOV-13`, `RECOV-14`.
**Design:** "`ResponseChain` — `.build(response_steps: [], recovery_steps: [])`, `#apply(outcome) -> Outcome`...
Fold order is all response steps first, then all recovery steps, in declared order within each
group (`RECOV-6`)... Response steps run only on a Success (`RECOV-4`); on a Failure the entire
response phase is skipped... Recovery steps run on every outcome, always, including a failure a
response step just produced by throwing (`RECOV-5`)... A throwing response step's error becomes a
Failure fed to the recovery steps (`RECOV-7`), and a throwing recovery step's error is wrapped into
a Failure fed to the next recovery step (`RECOV-8`)... `#apply` does not raise for any Outcome input
within StandardError, with three stated exceptions: the fatal family, `OutcomeError`, and
`InvalidArgumentError` on non-Outcome argument (`P4-19`)... `Ownership.close_on_throw` closes
in-hand response on throw path attaching close error as suppressed (`RECOV-12`) and leaves release
count 0 on deliberate return (`RECOV-13`)."

**Files:**
- Create: `gems/dexpace-core/test/support/fake_transport.rb`,
  `gems/dexpace-core/lib/dexpace/recovery/ownership.rb`,
  `gems/dexpace-core/lib/dexpace/recovery/response_chain.rb`,
  `gems/dexpace-core/sig/dexpace/recovery/response_chain.rbs`,
  `gems/dexpace-core/test/dexpace/recovery/response_chain_test.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`

**Interfaces:**
- Consumes: `Dexpace::Outcome`, `Dexpace::Outcome::Success`, `Dexpace::Outcome::Failure`,
  `Dexpace::OutcomeError`, `Dexpace.attach_suppressed`.
- Produces: `Dexpace::Recovery::ResponseChain`, `Dexpace::Recovery::Ownership` (private).

- [ ] **Step 1: Write test doubles in `test/support/fake_transport.rb` and the failing test**

Write `gems/dexpace-core/test/support/fake_transport.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"

class FakeTransport
  attr_reader :calls

  def initialize(response: nil, error: nil)
    @response = response
    @error = error
    @calls = []
  end

  def call(request, options = nil, cancellation = nil)
    @calls << { request: request, options: options, cancellation: cancellation }
    raise @error if @error

    @response
  end
end

# Dexpace::Body is a MODULE (phase 3b), so this includes it rather than subclassing it, and
# includes Dexpace::Closeable AFTER it -- the order phase 3b uses everywhere a body is closable,
# so the latch's #close wins over the module's no-op default.
#
# It counts #release and NOT #close on purpose: two assertions in this phase are release COUNTS
# rather than release facts (RECOV-12's "exactly once" and RECOV-13's "zero"), and RECOV-12's path
# calls #close twice -- buffer_bounded's ensure, then the chain's own close -- so a fake counting
# #close would assert 2 where the requirement says once, and would pass against a chain that had
# dropped Closeable's latch.
class RecordingBody
  include Dexpace::Body
  include Dexpace::Closeable

  attr_reader :release_count, :source_count

  def initialize(content = "body")
    initialize_closeable
    @content = content
    @release_count = 0
    @source_count = 0
  end

  def source
    @source_count += 1
    Dexpace::IO::BufferedSource.of_bytes(@content)
  end

  private

  def release
    @release_count += 1
  end
end
```

Write `gems/dexpace-core/test/dexpace/recovery/response_chain_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_transport"
require "dexpace"

# RECOV-4, RECOV-5, RECOV-6, RECOV-7, RECOV-8, RECOV-9, RECOV-12, RECOV-13, RECOV-14.
class DexpaceRecoveryResponseChainTest < DexpaceTestCase
  def build_response(code = 200, body = nil)
    request = Dexpace::Request.builder
    request.url = "https://example.test/"
    builder = Dexpace::Response.builder
    builder.request = request.build
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = Dexpace::Status.of(code)
    builder.body = body
    builder.build
  end

  test "fold order runs all response steps first, then all recovery steps (RECOV-6)" do
    log = []
    r1 = ->(resp) { log << :r1; resp }
    r2 = ->(resp) { log << :r2; resp }
    c1 = ->(out)  { log << :c1; out }
    c2 = ->(out)  { log << :c2; out }

    chain = Dexpace::Recovery::ResponseChain.build(
      response_steps: [r1, r2],
      recovery_steps: [c1, c2],
    )
    initial = Dexpace::Outcome::Success.build(response: build_response)

    result = chain.apply(initial)

    assert_predicate(result, :success?)
    assert_equal(%i[r1 r2 c1 c2], log)
  end

  test "response steps skipped entirely on Failure outcome (RECOV-4)" do
    r_ran = false
    c_ran = false

    chain = Dexpace::Recovery::ResponseChain.build(
      response_steps: [->(resp) { r_ran = true; resp }],
      recovery_steps: [->(out) { c_ran = true; out }],
    )
    initial = Dexpace::Outcome::Failure.build(error: ::IOError.new("transport fail"))

    result = chain.apply(initial)

    assert_predicate(result, :failure?)
    refute(r_ran, "response steps must be skipped on Failure")
    assert(c_ran, "recovery steps must run on Failure")
  end

  test "throwing response step converted to Failure fed to recovery steps (RECOV-5, RECOV-7)" do
    observed_in_recovery = nil

    chain = Dexpace::Recovery::ResponseChain.build(
      response_steps: [->(_) { raise ::StandardError, "response step threw" }],
      recovery_steps: [->(out) { observed_in_recovery = out; out }],
    )
    initial = Dexpace::Outcome::Success.build(response: build_response)

    result = chain.apply(initial)

    assert_predicate(result, :failure?)
    assert_equal("response step threw", result.error.message)
    assert_same(result, observed_in_recovery)
  end

  test "throwing recovery step wrapped into Failure fed to NEXT recovery step (RECOV-8)" do
    observed_in_next = nil

    chain = Dexpace::Recovery::ResponseChain.build(
      response_steps: [],
      recovery_steps: [
        ->(_) { raise ::StandardError, "recovery step 1 threw" },
        ->(out) { observed_in_next = out; out },
      ],
    )
    initial = Dexpace::Outcome::Success.build(response: build_response)

    result = chain.apply(initial)

    assert_predicate(result, :failure?)
    assert_equal("recovery step 1 threw", result.error.message)
    assert_same(result, observed_in_next)
  end

  test "response closed exactly once on throw with Success in hand (RECOV-12)" do
    body = RecordingBody.new
    resp = build_response(200, body)
    initial = Dexpace::Outcome::Success.build(response: resp)

    chain = Dexpace::Recovery::ResponseChain.build(
      response_steps: [->(_) { raise ::StandardError, "crash" }],
      recovery_steps: [],
    )

    result = chain.apply(initial)

    assert_predicate(result, :failure?)
    assert_equal(1, body.release_count, "response must be released exactly once (RECOV-12)")
  end

  test "close error attached as suppressed on throw path without masking primary (RECOV-12)" do
    body = Object.new
    def body.close; raise ::IOError, "close failure"; end

    resp = build_response(200, body)
    initial = Dexpace::Outcome::Success.build(response: resp)

    primary_err = ::StandardError.new("primary crash")
    chain = Dexpace::Recovery::ResponseChain.build(
      response_steps: [->(_) { raise primary_err }],
      recovery_steps: [],
    )

    result = chain.apply(initial)

    assert_predicate(result, :failure?)
    assert_same(primary_err, result.error)
    suppressed = Dexpace.suppressed(result.error)
    assert_equal(1, suppressed.size)
    assert_equal("close failure", suppressed.first.message)
  end

  test "a Failure in hand closes nothing on the throw path (RECOV-12)" do
    body = RecordingBody.new
    resp = build_response(200, body)

    chain = Dexpace::Recovery::ResponseChain.build(
      response_steps: [],
      recovery_steps: [
        # The chain is holding a Failure, not this response, so there is nothing to release --
        # RECOV-12's third clause, and the one a suite that only drives the Success path misses.
        ->(_) { raise ::StandardError, "recovery step threw with a Failure in hand" },
      ],
    )
    initial = Dexpace::Outcome::Failure.build(error: ::IOError.new("transport fail"))

    result = chain.apply(initial)

    assert_predicate(result, :failure?)
    assert_equal(0, body.release_count, "a Failure in hand carries no response to close")
    refute_predicate(resp.body, :closed?)
  end

  test "deliberately returning different outcome leaves original release count 0 (RECOV-13)" do
    body = RecordingBody.new
    resp = build_response(200, body)
    initial = Dexpace::Outcome::Success.build(response: resp)

    # Recovery step deliberately returns substitute Success
    replacement_resp = build_response(200, RecordingBody.new)
    chain = Dexpace::Recovery::ResponseChain.build(
      response_steps: [],
      recovery_steps: [
        ->(_) { Dexpace::Outcome::Success.build(response: replacement_resp) },
      ],
    )

    result = chain.apply(initial)

    assert_same(replacement_resp, result.response)
    assert_equal(0, body.release_count, "pipeline must NOT auto-close discarded response (RECOV-13)")
  end

  test "defensively copies and freezes both step lists at construction (RECOV-14, P4-22)" do
    r_list = [->(r) { r }]
    c_list = [->(o) { o }]
    chain = Dexpace::Recovery::ResponseChain.build(response_steps: r_list, recovery_steps: c_list)

    r_list << ->(r) { r }
    c_list << ->(o) { o }

    assert_equal(1, chain.response_steps.size)
    assert_equal(1, chain.recovery_steps.size)
    assert_predicate(chain.response_steps, :frozen?)
    assert_predicate(chain.recovery_steps, :frozen?)
  end

  test "apply validates outcome is a Dexpace::Outcome (P4-19)" do
    chain = Dexpace::Recovery::ResponseChain.build
    assert_raises(Dexpace::InvalidArgumentError) do
      chain.apply("not an outcome")
    end
  end

  test "re-raises Dexpace::OutcomeError when step returns non-Outcome (R6, P4-19)" do
    chain = Dexpace::Recovery::ResponseChain.build(
      recovery_steps: [->(_) { "not an outcome" }],
    )
    initial = Dexpace::Outcome::Success.build(response: build_response)

    assert_raises(Dexpace::OutcomeError) do
      chain.apply(initial)
    end
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/recovery/response_chain_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Recovery::ResponseChain`.

- [ ] **Step 3: Write `lib/dexpace/recovery/ownership.rb` and `lib/dexpace/recovery/response_chain.rb`**

Write `gems/dexpace-core/lib/dexpace/recovery/ownership.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../outcome"
require_relative "../outcome/success"
require_relative "../outcome/failure"
require_relative "../error/outcome_error"
require_relative "../suppressible"

module Dexpace
  module Recovery
    # RECOV-12, RECOV-13: the ONE place the ownership asymmetry lives. It closes the in-hand
    # response on a raise and never on a normal return, which is why it is named for the throw
    # path -- RECOV-13's half is the ABSENCE of a close on the other one.
    # Private constant owned by Recovery (Open Question 1).
    module Ownership
      def self.close_on_throw(outcome)
        yield
      rescue Dexpace::OutcomeError
        # R6, P4-19: Core exhaustiveness defect is re-raised and never converted to Failure.
        raise
      rescue ::Exception => error
        # RETRY-25: the fatal family is surfaced unchanged, with no trail attached.
        raise unless error.is_a?(::StandardError)

        if outcome.is_a?(Dexpace::Outcome::Success)
          # RECOV-12: close the in-hand response before wrapping, and write the close as a
          # NARROW rescue inside this region rather than as a bare close -- verified fact 10: an
          # exception escaping here would replace the primary and leave it reachable only through
          # #cause, which is the masking RECOV-12 forbids in its own sentence. A Failure in hand
          # carries no response, so this branch is skipped and nothing is released.
          begin
            outcome.response.close
          rescue ::StandardError => close_error
            Dexpace.attach_suppressed(error, close_error)
          end
        end

        Dexpace::Outcome::Failure.build(error: error)
      end
    end
    private_constant :Ownership
  end
end
```

Write `gems/dexpace-core/lib/dexpace/recovery/response_chain.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "ownership"
require_relative "../outcome"
require_relative "../outcome/success"
require_relative "../outcome/failure"
require_relative "../error/outcome_error"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Recovery
    # RECOV-4..8, RECOV-12..14: Response recovery chain.
    #
    # RECOV-9: a recovery step SHOULD NOT throw; it SHOULD surface its error explicitly by
    # returning Dexpace::Outcome::Failure.build(error:). Throwing is tolerated -- RECOV-8 wraps
    # the throwable into a Failure and feeds it to the NEXT recovery step, and #apply still does
    # not raise -- but it cedes control of the wrapped error to this chain's defensive catch, and
    # a step that returns a Failure keeps it.
    class ResponseChain
      attr_reader :response_steps, :recovery_steps

      private_class_method :new

      def self.build(response_steps: [], recovery_steps: [])
        new(
          response_steps: response_steps.dup.freeze,
          recovery_steps: recovery_steps.dup.freeze,
        )
      end

      def initialize(response_steps:, recovery_steps:)
        @response_steps = response_steps
        @recovery_steps = recovery_steps
      end

      def apply(outcome)
        unless outcome.is_a?(Dexpace::Outcome)
          raise Dexpace::InvalidArgumentError, "outcome must be a Dexpace::Outcome (P4-19)"
        end

        curr = outcome

        # RECOV-4: Response steps run only on Success
        if curr.is_a?(Dexpace::Outcome::Success)
          @response_steps.each do |step|
            curr = Ownership.close_on_throw(curr) do
              resp = step.call(curr.response)
              Dexpace::Outcome::Success.build(response: resp)
            end
            break if curr.failure?
          end
        end

        # RECOV-5: recovery steps run on every outcome, always -- including a failure a response
        # step just produced by throwing.
        #
        # The case/in with a raising `else` is R6's, and this is one of exactly two places it
        # belongs: the value arrived from a CALLER-supplied step and its type is unproven
        # (verified fact 14; the other is the orchestrator's RECOV-10 unwrap). Dexpace::OutcomeError
        # is a StandardError and Ownership re-raises it by name rather than converting it, because
        # NoMatchingPatternError is inside StandardError and the conforming-looking route would
        # demote a core defect to an outcome a later recovery step may swallow (P4-19).
        @recovery_steps.each do |step|
          curr = Ownership.close_on_throw(curr) do
            returned = step.call(curr)
            case returned
            in Dexpace::Outcome::Success => success then success
            in Dexpace::Outcome::Failure => failure then failure
            else raise Dexpace::OutcomeError, returned.class
            end
          end
        end

        curr
      end
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/recovery/response_chain.rbs`**

```rbs
module Dexpace
  module Recovery
    class ResponseChain
      attr_reader response_steps: Array[^(Dexpace::Response) -> Dexpace::Response]
      attr_reader recovery_steps: Array[^(Dexpace::Outcome::t) -> Dexpace::Outcome::t]
      def self.build: (
        ?response_steps: Array[^(Dexpace::Response) -> Dexpace::Response],
        ?recovery_steps: Array[^(Dexpace::Outcome::t) -> Dexpace::Outcome::t]
      ) -> Dexpace::Recovery::ResponseChain
      def apply: (Dexpace::Outcome::t outcome) -> Dexpace::Outcome::t
    end
  end
end
```

- [ ] **Step 5: Add requires to `lib/dexpace.rb`**

Add to `gems/dexpace-core/lib/dexpace.rb`:
`require_relative "dexpace/recovery/ownership"`
`require_relative "dexpace/recovery/response_chain"`

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/recovery/response_chain_test.rb`
Expected: PASS — 11 runs, 0 failures, 0 errors.

---

## Task 14: `Dexpace::Recovery::Orchestrator`

**Requirement IDs:** `RECOV-2`, `RECOV-10`, `RECOV-11`, `RETRY-25`.
**Design:** "`.build(transport:, request_chain:, response_chain:)`, `#call(request, options, cancellation)`.
It is itself a `Dexpace::Transport` by duck type... `RECOV-2`: the request chain, the transport invocation
and the response chain all run inside one `rescue Exception` region with R6's three arms. A before-request
throw does not skip after-error handling... `RECOV-10`: unwrap by `case/in` fold: on Success return
response; on Failure `raise error, cause: nil` (verified fact 5)... `RECOV-11`: nothing to do, asserted
rather than implemented (P4-17); token still answers `cancelled?` afterwards."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/recovery/orchestrator.rb`,
  `gems/dexpace-core/sig/dexpace/recovery/orchestrator.rbs`,
  `gems/dexpace-core/test/dexpace/recovery/orchestrator_test.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`

**Interfaces:**
- Consumes: `Dexpace::Recovery::RequestChain`, `Dexpace::Recovery::ResponseChain`,
  `Dexpace::Transport` duck type, `Dexpace::Outcome::Success`, `Dexpace::Outcome::Failure`,
  `Dexpace::OutcomeError`.
- Produces: `Dexpace::Recovery::Orchestrator`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_transport"
require "dexpace"

# RECOV-2, RECOV-10, RECOV-11, RETRY-25.
class DexpaceRecoveryOrchestratorTest < DexpaceTestCase
  def build_request
    Dexpace::Request.build(
      method: Dexpace::Method::GET,
      url: "https://example.com/api",
      headers: Dexpace::Headers::EMPTY,
      body: nil,
    )
  end

  # Response.builder, not Response.build: HTTP-4 requires :request and :protocol as well as
  # :status, and the builder is what defaults :headers to Headers::EMPTY (phase 3b's precedent).
  def build_response
    request = Dexpace::Request.builder
    request.url = "https://example.test/"
    builder = Dexpace::Response.builder
    builder.request = request.build
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = Dexpace::Status.of(200)
    builder.build
  end

  test "successful send passes through request chain, transport, and response chain" do
    resp = build_response
    transport = FakeTransport.new(response: resp)
    req_chain = Dexpace::Recovery::RequestChain.build
    resp_chain = Dexpace::Recovery::ResponseChain.build

    orchestrator = Dexpace::Recovery::Orchestrator.build(
      transport: transport,
      request_chain: req_chain,
      response_chain: resp_chain,
    )

    result = orchestrator.call(build_request)
    assert_same(resp, result)
    assert_equal(1, transport.calls.size)
  end

  test "defining invariant: before-request throw does not skip after-error recovery hooks (RECOV-2)" do
    throwing_req_step = ->(_) { raise ::IOError, "pre-request explosion" }
    req_chain = Dexpace::Recovery::RequestChain.build(steps: [throwing_req_step])

    observed_error = nil
    recovering_step = ->(outcome) { observed_error = outcome.error; outcome }
    resp_chain = Dexpace::Recovery::ResponseChain.build(recovery_steps: [recovering_step])

    transport = FakeTransport.new(response: build_response)

    orchestrator = Dexpace::Recovery::Orchestrator.build(
      transport: transport,
      request_chain: req_chain,
      response_chain: resp_chain,
    )

    err = assert_raises(::IOError) do
      orchestrator.call(build_request)
    end

    assert_equal("pre-request explosion", err.message)
    assert_equal("pre-request explosion", observed_error.message)
    assert_equal(0, transport.calls.size, "transport must not be called if request step threw")
  end

  test "transport throw is caught, converted to Failure, and rethrown by identity (RECOV-2, RECOV-10)" do
    transport_err = ::StandardError.new("connection dropped")
    transport = FakeTransport.new(error: transport_err)

    orchestrator = Dexpace::Recovery::Orchestrator.build(
      transport: transport,
      request_chain: Dexpace::Recovery::RequestChain.build,
      response_chain: Dexpace::Recovery::ResponseChain.build,
    )

    caught = assert_raises(::StandardError) { orchestrator.call(build_request) }

    # assert_same, never assert_equal: Exception#== is STRUCTURAL (verified fact 6), so
    # assert_equal would pass against an implementation that substituted an equal error, which is
    # exactly what RECOV-10's "no wrapping, no substitution" forbids.
    assert_same(transport_err, caught, "error must be rethrown UNCHANGED by identity (RECOV-10)")
  end

  test "unwrap attaches no cause while an unrelated exception is in flight (RECOV-10)" do
    # The Failure MUST carry an error this test CONSTRUCTED and never raised -- RECOV-10's own
    # named case, "a recovery step constructing the error and returning a Failure". An error a
    # fixture RAISED inside the rescue below already acquired the unrelated exception as its
    # #cause at its own `raise`, and `cause: nil` suppresses the assignment without clearing a
    # pre-existing cause (verified fact 5), so assert_nil would fail against a CORRECT
    # implementation. Driving it from a transport raise is the shape that trap is set for.
    constructed = ::StandardError.new("constructed by a recovery step, never raised")
    resp_chain = Dexpace::Recovery::ResponseChain.build(
      recovery_steps: [->(_) { Dexpace::Outcome::Failure.build(error: constructed) }],
    )
    orchestrator = Dexpace::Recovery::Orchestrator.build(
      transport: FakeTransport.new(response: build_response),
      request_chain: Dexpace::Recovery::RequestChain.build,
      response_chain: resp_chain,
    )

    # The caller's own rescue is what makes $! non-nil at the unwrap; a bare `raise error` there
    # would hand this unrelated exception to the surfaced error as its #cause.
    surfaced = begin
      raise "unrelated caller in-flight exception"
    rescue ::StandardError
      begin
        orchestrator.call(build_request)
      rescue ::StandardError => caught
        caught
      end
    end

    assert_same(constructed, surfaced)
    assert_nil(surfaced.cause, "unwrap must pass cause: nil so the caller's $! is not assigned")
  end

  test "cancellation signal remains asserted after failure conversion and unwrap (RECOV-11, P4-17)" do
    source = Dexpace::Cancellation::Source.new
    token = source.token
    source.cancel("cancelled explicitly")

    cancel_err = Dexpace::CancelledError.new("wait cancelled")
    transport = FakeTransport.new(error: cancel_err)

    orchestrator = Dexpace::Recovery::Orchestrator.build(
      transport: transport,
      request_chain: Dexpace::Recovery::RequestChain.build,
      response_chain: Dexpace::Recovery::ResponseChain.build,
    )

    caught = assert_raises(Dexpace::CancelledError) do
      orchestrator.call(build_request, nil, token)
    end

    assert_same(cancel_err, caught)
    assert_predicate(token, :cancelled?, "token must remain cancelled after unwrap (RECOV-11)")
    assert_equal("cancelled explicitly", token.reason)
  end

  test "fatal family (LoadError) escapes recovery chain unconverted (R6, RETRY-25)" do
    req_step = ->(_) { raise ::LoadError, "cannot load such file" }
    recovery_hook_ran = false
    resp_chain = Dexpace::Recovery::ResponseChain.build(
      recovery_steps: [->(out) { recovery_hook_ran = true; out }],
    )

    orchestrator = Dexpace::Recovery::Orchestrator.build(
      transport: FakeTransport.new(response: build_response),
      request_chain: Dexpace::Recovery::RequestChain.build(steps: [req_step]),
      response_chain: resp_chain,
    )

    assert_raises(::LoadError) do
      orchestrator.call(build_request)
    end
    refute(recovery_hook_ran, "recovery hooks must not observe fatal ScriptErrors")
  end

  test "OutcomeError escapes orchestrator unconverted (R6, P4-19)" do
    resp_chain = Dexpace::Recovery::ResponseChain.build(
      recovery_steps: [->(_) { raise Dexpace::OutcomeError, String }],
    )

    orchestrator = Dexpace::Recovery::Orchestrator.build(
      transport: FakeTransport.new(response: build_response),
      request_chain: Dexpace::Recovery::RequestChain.build,
      response_chain: resp_chain,
    )

    assert_raises(Dexpace::OutcomeError) do
      orchestrator.call(build_request)
    end
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/recovery/orchestrator_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Recovery::Orchestrator`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/recovery/orchestrator.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../outcome"
require_relative "../outcome/success"
require_relative "../outcome/failure"
require_relative "../error/outcome_error"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Recovery
    # RECOV-2, RECOV-10, RECOV-11: Unified orchestrator.
    # Implements Dexpace::Transport duck type over #call(request, options, cancellation).
    #
    # The defining invariant has ONE blind spot and it is documented rather than discovered:
    # RECOV-2's conversion boundary is StandardError, and LoadError and NotImplementedError are
    # ScriptErrors (verified fact 9), so a caller-supplied step that lazily `require`s something
    # absent -- or an adapter author's `raise NotImplementedError` -- escapes the recovery chain
    # entirely and no recovery hook observes it. Core requires nothing lazily, so no core step can
    # do this. The remedy for a step author who wants a lazy dependency observed by the chain is to
    # load at construction rather than at #call, or to rescue its own LoadError and raise a
    # StandardError. Task 14's LoadError test asserts the escape for the case that will happen.
    class Orchestrator
      attr_reader :transport, :request_chain, :response_chain

      private_class_method :new

      def self.build(transport:, request_chain:, response_chain:)
        raise Dexpace::InvalidArgumentError, "transport is required" if transport.nil?
        raise Dexpace::InvalidArgumentError, "request_chain is required" if request_chain.nil?
        raise Dexpace::InvalidArgumentError, "response_chain is required" if response_chain.nil?

        new(
          transport: transport,
          request_chain: request_chain,
          response_chain: response_chain,
        )
      end

      def initialize(transport:, request_chain:, response_chain:)
        @transport = transport
        @request_chain = request_chain
        @response_chain = response_chain
      end

      def call(request, options = nil, cancellation = nil)
        outcome = begin
          # RECOV-2: Before-request phase and transport invocation inside one rescue region
          req = @request_chain.apply(request)
          resp = @transport.call(req, options, cancellation)
          Dexpace::Outcome::Success.build(response: resp)
        rescue Dexpace::OutcomeError
          # R6, P4-19: Defect in code re-raised by name
          raise
        rescue ::StandardError => error
          # RECOV-2: Convert to Failure and thread through response chain
          Dexpace::Outcome::Failure.build(error: error)
        rescue ::Exception
          # RETRY-25: Fatal family surfaced unchanged
          raise
        end

        final_outcome = @response_chain.apply(outcome)

        # RECOV-10: Unwrap final outcome
        case final_outcome
        in Dexpace::Outcome::Success => s
          s.response
        in Dexpace::Outcome::Failure => f
          # verified fact 5: cause: nil suppresses implicit assignment of caller's $!
          raise f.error, cause: nil
        else
          raise Dexpace::OutcomeError, final_outcome.class
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/recovery/orchestrator.rbs`**

```rbs
module Dexpace
  module Recovery
    class Orchestrator
      attr_reader transport: untyped
      attr_reader request_chain: Dexpace::Recovery::RequestChain
      attr_reader response_chain: Dexpace::Recovery::ResponseChain
      def self.build: (
        transport: untyped,
        request_chain: Dexpace::Recovery::RequestChain,
        response_chain: Dexpace::Recovery::ResponseChain
      ) -> Dexpace::Recovery::Orchestrator
      def call: (Dexpace::Request request, ?untyped options, ?Dexpace::Cancellation::Token? cancellation) -> Dexpace::Response
    end
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/recovery/orchestrator"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/recovery/orchestrator_test.rb`
Expected: PASS — 7 runs, 0 failures, 0 errors.

---

## Task 15: Final Wiring, Surface Snapshot, RBS Baseline, Checklist, and Register Updates

**Requirement IDs:** `NFR-1`, `NFR-3`, `NFR-4`, `NFR-11`, `NFR-13`, `NFR-14`.
**Design:** "The final wiring task — `lib/dexpace.rb`'s require order, the regenerated runtime
surface snapshot and RBS baseline, the register moves the design commits to (`DEF-24` and `DEF-32`
to `picked-up`, `DEF-27` gaining a dated `Status` line and not moving, the new `DEF-38` row), and the
`CLAUDE.md` claims sentence."

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace.rb`,
  `gems/dexpace-core/sig/dexpace.rbs`,
  `test/fixtures/surface/dexpace-core.txt`,
  `docs/deferred-items.md`,
  `CLAUDE.md`
- Create: `docs/work/mvp/phase4/phase4b/2026-09-09-phase4b-recovery-primitives-checklist.md`

- [ ] **Step 1: Check `lib/dexpace.rb` require order**

Ensure `gems/dexpace-core/lib/dexpace.rb` includes explicit `require_relative` directives for every
new file in the tree in buildable dependency order.
**Crucial ordering invariant:** `dexpace/suppressible` must be required **before** `dexpace/error`.

The lines below are 4b's own; they interleave with phases 0-3's existing ones rather than replacing
them. `dexpace/error` is phase 1's line, listed only to fix what must sit above it, and
`dexpace/error/invalid_argument_error` — also phase 1's — keeps its existing position below it.

```ruby
# 4b's contribution to lib/dexpace.rb, in dependency order:
require_relative "dexpace/suppressible"   # NEW, and it must precede the next line
require_relative "dexpace/error"          # phase 1's, unmoved: it includes Dexpace::Suppressible
require_relative "dexpace/each_cause"
require_relative "dexpace/error/outcome_error"
require_relative "dexpace/error/protocol_error"
require_relative "dexpace/outcome"
require_relative "dexpace/outcome/success"
require_relative "dexpace/outcome/failure"
require_relative "dexpace/recovery"
require_relative "dexpace/recovery/transform"
require_relative "dexpace/recovery/idempotency_key_step"
require_relative "dexpace/recovery/client_identity_step"
require_relative "dexpace/recovery/error_mapping_step"
require_relative "dexpace/recovery/request_chain"
require_relative "dexpace/recovery/ownership"
require_relative "dexpace/recovery/response_chain"
require_relative "dexpace/recovery/orchestrator"
```

- [ ] **Step 2: Run require-allowlist audit**

Run: `bundle exec rake gates:require_allowlist`
Expected: PASS — 0 unallowlisted requires. Phase 4b adds no dependencies and no external requires.

- [ ] **Step 3: Regenerate runtime surface snapshot**

Run: `bundle exec rake surface:regenerate`
Expected: `test/fixtures/surface/dexpace-core.txt` gains exactly these rows, derived from
`mod.public_instance_methods(false)`:

```
Dexpace::Outcome
Dexpace::Outcome::Failure
Dexpace::Outcome::Failure# error error_or_nil failure? fold response_or_nil success?
Dexpace::Outcome::Success
Dexpace::Outcome::Success# error_or_nil failure? fold response response_or_nil success?
Dexpace::OutcomeError
Dexpace::OutcomeError# offending_class
Dexpace::ProtocolError
Dexpace::ProtocolError# response status
Dexpace::Recovery
Dexpace::Recovery::ClientIdentityStep
Dexpace::Recovery::ClientIdentityStep# apply call header mode phase tokens
Dexpace::Recovery::ErrorMappingStep
Dexpace::Recovery::ErrorMappingStep# apply call factory phase
Dexpace::Recovery::IdempotencyKeyStep
Dexpace::Recovery::IdempotencyKeyStep# apply call header methods mode phase strategy
Dexpace::Recovery::Orchestrator
Dexpace::Recovery::Orchestrator# call request_chain response_chain transport
Dexpace::Recovery::RequestChain
Dexpace::Recovery::RequestChain# apply steps
Dexpace::Recovery::ResponseChain
Dexpace::Recovery::ResponseChain# apply recovery_steps response_steps
Dexpace::Recovery::Transform
Dexpace::Recovery::Transform# apply call phase
Dexpace::Suppressible
Dexpace::Suppressible# detailed_message suppressed
```

`Dexpace::Recovery::Ownership` does not appear because it is a `private_constant` excluded from
`Module#constants`.

- [ ] **Step 4: Regenerate RBS baseline and run API lock**

Run: `bundle exec rake rbs:validate steep gates:sig_diff gates:rbs_surface`
Expected: PASS — `gates:rbs_surface` confirms no constants outside `Dexpace::` and stdlib allowlist
appear in public signatures (`NFR-11`).

- [ ] **Step 5: Run cop suite and RuboCop**

Run: `bundle exec rake cops:test`
Run: `bundle exec rubocop --fail-level=convention`
Expected: PASS — 0 offenses on newly written files.

- [ ] **Step 6: Run full test matrix**

Run: `bundle exec rake`
Run: `mise exec ruby@3.2.11 -- bundle exec rake test:gems`
Run: `mise exec ruby@3.3.7 -- bundle exec rake test:gems`
Run: `mise exec ruby@3.4.10 -- bundle exec rake test:gems`
Run: `mise exec ruby@4.0.6 -- bundle exec rake test:gems`
Expected: PASS on all four interpreters, 0 failures, 0 errors.

- [ ] **Step 7: Write the checklist**

Create `docs/work/mvp/phase4/phase4b/2026-09-09-phase4b-recovery-primitives-checklist.md`.
Account for all 34 `RECOV` requirements:
- 18 Implemented rows (✅): `RECOV-1`–`RECOV-16`, `RECOV-32`, `RECOV-33`
  - `RECOV-1` -> Task 6
  - `RECOV-2` -> Task 14
  - `RECOV-3` -> Task 12
  - `RECOV-4` -> Task 13
  - `RECOV-5` -> Task 13
  - `RECOV-6` -> Task 13
  - `RECOV-7` -> Task 13
  - `RECOV-8` -> Task 13
  - `RECOV-9` -> Task 13 (a SHOULD about *step authors*: 4b ships no recovery step, so the row is
    satisfied by the chain tolerating a throwing one (`RECOV-8`) and by `ResponseChain`'s YARD
    naming `Outcome::Failure.build` as the way to honour the preference)
  - `RECOV-10` -> Task 14
  - `RECOV-11` -> Task 14
  - `RECOV-12` -> Task 13
  - `RECOV-13` -> Task 13
  - `RECOV-14` -> Tasks 12, 13
  - `RECOV-15` -> Task 11
  - `RECOV-16` -> Tasks 7, 11
  - `RECOV-32` -> Task 9
  - `RECOV-33` -> Task 10
- 15 Deferred rows under `DEF-35` (⏳): `RECOV-17`–`RECOV-30`, `RECOV-34` (target phase 6)
- 1 Deferred row under `DEF-5` (⏳): `RECOV-31` (post-MVP)

- [ ] **Step 8: Record what the phase decided, in the right place**

`docs/deferred-items.md` is append-only in its rows and its item format is
`### DEF-<n> — <title>` with bullet fields; a picked-up row is **never moved or deleted**, its
`Status` line changes and the row stays where it is, so a `DEF-<n>` citation written while the work
was deferred still resolves. There is no `picked-up` section to move anything into.

- **Deferrals.**
  - `DEF-24`: `- **Status:** picked-up (2026-09-09, phase 4b)`, naming `Dexpace::Suppressible`,
    `Dexpace.attach_suppressed` and the `#detailed_message` rendering. Its `Why` names
    `Dexpace::Error#suppressed` as the carrier and `#full_message` as the override; both are
    corrected to `Dexpace::Suppressible` and `#detailed_message` in the same edit (P4-12, R5).
  - `DEF-32`: `- **Status:** picked-up (2026-09-09, phase 4b)`, naming the fourth test,
    `"multiple raising handlers attach later failures to first via Dexpace.attach_suppressed"` in
    `test/dexpace/cancellation_test.rb`, and correcting its `Dexpace::Error#suppressed` clause to
    `Dexpace::Suppressible` — the primary at that site is a bare `::IOError` (P4-12).
  - `DEF-27`: a dated `Status` line recording the **first** disposal route only —
    `Dexpace.close_quietly(resource, onto:)` — and stating that the row stays **deferred** for
    phase 5's second route, §8.1's diagnostic. It does **not** become `picked-up`. Its `Why`'s
    `Dexpace::Error#suppressed` clause is corrected in the same edit.
  - `DEF-38`: **already filed**, by this sub-phase's design on 2026-09-08, and the register's
    `next id` is `DEF-40`. This plan files **no** new deferral and must not append a second
    `DEF-38`; the step is to confirm the existing row still reads true of what Task 5 shipped —
    the class with `#response`, `#status`, `.for` and `.for_or_nil`, and no `#retryable?`.
- **Deviations.** The design filed `P4-12` through `P4-25` and this plan adds none; the plan's five
  open-question answers are decisions the design asked it to make, not new departures. Consolidating
  them into design §10 is **not this task's edit** — `docs/sdk-design-ruby/` is frozen to this plan
  by its own Global Constraints and the consolidation is the manager's, following the phase. What
  this step does is record the as-built state of the fourteen rows in `docs/deviations.md`.
- **Open items.** None filed. The two findings against committed phase-2 documents that the design
  names go to the manager, and are not `OI-` rows: each is a sentence a named change rewrites.
- **Release blockers.** None. Nothing is published and every gem stays at `0.0.0`.

- [ ] **Step 9: Update `CLAUDE.md` claims sentence**

Update the claims sentence in `CLAUDE.md`:
"three sub-phase directories — `phase4/phase4a/`, `phase4/phase4b/` and `phase4/phase4c/`; `phase4a/`
and `phase4b/` each hold a design and a plan, `phase4c/` a design with the plan still to be written."

Run: `ruby .claude/skills/housekeeping/probe.rb --only claims`
Expected: PASS.

---

## Self-review against the design

**Spec coverage.** All 34 `RECOV` requirement IDs are accounted for in this plan:
- 18 implemented in named tasks:
  `RECOV-1` (Task 6), `RECOV-2` (Task 14), `RECOV-3` (Task 12), `RECOV-4` (Task 13),
  `RECOV-5` (Task 13), `RECOV-6` (Task 13), `RECOV-7` (Task 13), `RECOV-8` (Task 13),
  `RECOV-9` (Task 13), `RECOV-10` (Task 14), `RECOV-11` (Task 14), `RECOV-12` (Task 13),
  `RECOV-13` (Task 13), `RECOV-14` (Tasks 12, 13), `RECOV-15` (Task 11), `RECOV-16` (Tasks 7, 11),
  `RECOV-32` (Task 9), `RECOV-33` (Task 10).
- 15 deferred under `DEF-35` to phase 6: `RECOV-17` through `RECOV-30`, and `RECOV-34`.
- 1 deferred under `DEF-5` post-MVP: `RECOV-31`.
- Non-`RECOV` requirement IDs 4b owns a share of: `XCUT-4` branch (a) (Task 5), `XCUT-8` (Task 5),
  `XCUT-9` (Task 3), `BODY-30` (Task 7), `PIPE-37`'s honourability (Task 11), `RETRY-34`'s skip-self
  guard (Task 1), `RETRY-25`'s fatal-family passthrough as `RECOV-2`'s rule (Task 14). `HTTP-52` and
  `BODY-31` are **not** claimed: the design's out-of-scope table assigns both to phases 3b and 1,
  and 4b ships only the step that calls them.
- Register pick-ups (deferral IDs, not requirement IDs): `DEF-24` (Task 1), `DEF-32` (Task 2), and
  `DEF-27`'s first disposal route only (Task 2, row stays open).

**Deviation ledger coverage.** Every deviation row `P4-12` through `P4-25` lands in a named task:
- `P4-12` (separate `Suppressible` module) -> Task 1
- `P4-13` (`attach_suppressed` `extend`s primary, swallows `FrozenError`) -> Task 1
- `P4-14` (`#suppressed` frozen array replaced on attach) -> Task 1
- `P4-15` (public `Dexpace.suppressed` and `Suppressible` constant) -> Task 1
- `P4-16` (`each_cause` yields error itself first) -> Task 3
- `P4-17` (`RECOV-11` structural without token mutation) -> Task 14
- `P4-18` (block-form resource rule does not reach chain) -> Task 13
- `P4-19` (`OutcomeError` StandardError re-raised by name; totality 3 exceptions) -> Tasks 4, 13, 14
- `P4-20` (`ProtocolError` single class with `#status`, no subclass tree) -> Task 5
- `P4-21` (`Outcome#response_or_nil` and `#error_or_nil` return `nil` for absent) -> Task 6
- `P4-22` (chains `dup` and `freeze` step lists rather than `Model.own`) -> Tasks 12, 13
- `P4-23` (public methods neither design §5.1 nor §5.2 names) -> Tasks 1, 3, 5, 6, 7, 8, 12, 13, 14
- `P4-24` (public constants neither design §5.1 nor §5.2 names) -> Tasks 6, 8, 9, 10, 11, 12, 13, 14
- `P4-25` (`Transform` default `#call(value) = apply(value)`) -> Task 8

**Spec-forced boundaries honoured.**
- **Boundary 1 (§8.3 two-layer prohibition):** No stage, cursor, pillar, or `PIPE` constant is named
  in any implementation file. Transforms are pure functions of one argument (`#apply(value)`).
- **Boundary 6 (`RECOV-1` closed two-variant outcome, `RECOV-6` fold order):** `Outcome::Success` and
  `Outcome::Failure` are the only two variants; response steps run first on `Success` only, followed
  by recovery steps on every outcome.
- **Boundary 7 (`RECOV-8` totality):** `#apply` never raises under `StandardError` step behavior;
  the only escaping errors are fatal `ScriptError`/`SignalException`, internal `OutcomeError`, and
  caller-bug `InvalidArgumentError` at the boundary.
- **Boundary 8 (`RECOV-12`/`RECOV-13` ownership asymmetry):** Concentrated in `Ownership.close_on_throw`;
  response closed exactly once on throw paths with close errors attached as suppressed; zero release
  calls on deliberate outcome returns.
- **Boundary 9 (`RECOV-14` uniform defensive copy):** Both `RequestChain` and `ResponseChain` copy
  and freeze their step lists at construction.
- **Boundary 10 (`RECOV-16` single bound):** `Recovery.buffer_error_body` reads
  `Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES`; no second constant is declared.
- **Boundary 5 (`PIPE-37` placement rule):** `ErrorMappingStep#apply` returns non-error responses
  untouched by identity (`assert_same`), without reading or closing the body.

**Open questions.** All five open questions from the design are resolved in the front matter before
Task 1 and enforced across the tasks.

**Type consistency.**
- `RequestChain#steps` is `Array[^(Dexpace::Request) -> Dexpace::Request]`.
- `ResponseChain#response_steps` is `Array[^(Dexpace::Response) -> Dexpace::Response]`.
- `ResponseChain#recovery_steps` is `Array[^(Dexpace::Outcome::t) -> Dexpace::Outcome::t]`.
- `Transform` declares `#phase` returning `:request` or `:response`, and `#apply(value)`.
- `DEFAULT_FACTORY` is a frozen lambda calling `ProtocolError.for`.

**Placeholder scan.** Every fence is complete, syntactically valid Ruby or RBS. No "TBD", no
"etc.", and no "similar to Task N" sketches appear. Task 2 is the one task whose fences are
**fragments rather than whole files** — it modifies two committed phase-2 files — and they are
written as the exact `require_relative` lines and the exact method bodies that replace phase 2's,
with the surrounding file stated as untouched, rather than as a whole file with an elision in it.
