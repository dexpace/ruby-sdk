# Phase 7b — Server-Sent Events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `dexpace-core`'s Server-Sent Events subsystem in full — the WHATWG line and field state
machine (`Dexpace::SSE::LineReader`, `::Reader`), the immutable five-field event value
(`::Event`), the resource-owning single-pass streaming facade (`::Stream`) and the typed adapter
(`::TypedStream`) — satisfying `SSE-1`–`SSE-40` and carrying `SSE-41` as a ⏳ row under the
pre-existing `DEF-8`; resolving `OI-5` with the corrected requirement ID and a documented line cap;
and building the `SSE-37` require-and-constant audit that spec-forced boundary 5 extends over core's
pagination layer.

**Architecture:** A byte-level line machine over `Dexpace::IO::BufferedSource#getbyte` recognising LF,
CR and CRLF natively with a one-byte pushback — **not** over phase 3a's `#read_line_utf8`, whose
`IO-14` grammar keeps a lone `\r` as content where `SSE-2` requires it terminate a line (`P7-20`). A
stateless-per-block field machine above it whose only persistent state is the BOM flag (`SSE-16`). An
event value that is a `Data` including `Dexpace::Model`, so `SSE-20`'s defensive copy is `Model.own`
and its copy-with-changes clause is `Model#with` routing through `.build`. A facade that includes
phase 2's `Dexpace::Closeable` and therefore inherits idempotence, the mutex-guarded flag and
ownership-at-construction, with the resource living on the facade and **never inside an `Enumerator`
block or an owning `#each`**. A typed adapter that delegates `#close` to the facade rather than owning
a second resource, and whose three mapper outcomes are a bare decoded value plus two frozen
`Dexpace::SSE::Signal` singletons (`P7-23`).

**Tech Stack:** Ruby 3.2–4.0 (authored against 3.4.10), **zero new runtime dependencies and zero new
`require`s outside `dexpace/`** — the require allowlist does not grow, Minitest, RBS + Steep, RuboCop
with phase 0's six custom cops, SimpleCov, YARD.

**Spec:** `docs/work/mvp/phase7/phase7b/2026-09-10-phase7b-server-sent-events-design.md`, under the
charter `docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md`.
`docs/product-spec/13-server-sent-events-and-streaming.md` is the normative chapter for all 41 IDs;
`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` rows 410–450 carry the
canonical text and modal level of each.

---

## Global Constraints

- **`dexpace-core` gains no dependency and the require allowlist does not grow.** `7b` requires nothing
  outside `dexpace/`. An SSE parser is a place `strscan` and `stringio` get reached for reflexively;
  neither is needed once the line machine reads bytes from a `BufferedSource`, and neither is added.
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`, `Dexpace/SpdxHeader`).
- **Inside `module Dexpace`, every core constant is `::`-qualified**: `::String`, `::Encoding`,
  `::Integer`, `::Regexp`, `::StandardError`, `::Data`, `::IOError`. `Dexpace::SSE::Signal` shadows
  nothing Ruby-owned; `Dexpace/QualifiedCoreConstant` is scoped to `lib/dexpace/async/**` and
  `lib/dexpace/serde/**` and has no site here, but the qualification convention applies anyway.
- **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are strictly forbidden**
  (`Dexpace/NoThreadInterrupt`). There is no interrupt anywhere in this subsystem: `SSE-31`'s
  cross-thread close tears the resource down and lets the blocked read fail.
- **`Thread::Mutex` is per-fiber-owned and non-reentrant.** The **one** lock in this plan is phase 2's,
  inside `Dexpace::Closeable`, held across the flag flip only. No task below creates a second mutex.
  `SSE-18` leaves the parser deliberately unsynchronised.
- **`downcase` is never called** (`Dexpace/NoLocaleCaseFold`). `SSE-7`'s field-name comparison is
  case-sensitive (`P7-24`), which is the one place a fold would otherwise appear.
- **`Regexp.new(source, timeout: 1.0)` per pattern, never `Regexp.timeout`.** One pattern in the whole
  subsystem: `SSE-11`'s anchored digit screen, Task 6.
- **Bytes stay `Encoding::BINARY` until a field value is extracted**, and the decode is
  retag-then-transcode with both encodings named (`P7-26`). `String#b` is the retag idiom;
  `force_encoding` raises `FrozenError` on a frozen chunk even when the target is the string's own
  encoding. **Every encoding assertion uses non-ASCII content** — an ASCII-only fixture passes under
  exactly the bug.
- **Domain model construction pattern:** `Data.define`, `private_class_method :new`, `.build` with
  `Model.required!`, defensive collection copies with `Model.own`, shallow `freeze`.
- **`Dexpace::Closeable` is included, never re-implemented**, and `#initialize_closeable(owned:)` is
  called from every including class's constructor — phase 2's own guard raises with a message naming
  the method if it is not.
- **`Dexpace.close_quietly(resource, onto:)` is the only quiet-close route** and
  `Dexpace.attach_suppressed` the only suppression route. `7b` writes neither. **The frozen-primary
  caveat is stated in the YARD at both `SSE-29` and `SSE-36` sites**: `attach_suppressed` silently
  no-ops on a frozen primary (`P4-13`).
- **No resource lives inside an `Enumerator` block or inside an owning `#each`**, and **no
  `block_given?` guard is written anywhere** — it is measurably `true` inside `#each` reached through
  `to_enum(:each)` and `#next`, so it forbids nothing.
- **Formatting:** double quotes, 2-space indentation, 100 columns, `consistent_comma` trailing commas.
- **Every new `lib/` file opens with the `require_relative`s for the core files it names** — phase 2's
  precedent, unchanged.
- **Deviation numbering is `P7-20`–`P7-39`**, a band reserved for `7b` because `7a` and `7c` were
  written concurrently and could not coordinate. See the design's Deviation Ledger.

### Commands

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/<name>_test.rb   # one suite, red or green
(cd gems/dexpace-core && bundle exec rake test)                        # the gem's whole suite
bundle exec rake                                                       # all gates, plus the new one
bundle exec rake gates:serde_boundary                                  # SSE-37, Task 11
bundle exec rubocop                                                    # linting and the six cops
bundle exec steep check                                                # Steep typing gate
bundle exec rbs validate                                               # RBS validation gate
bundle exec rake surface:regenerate                                    # deliberate; the final task only
```

### What was verified during planning

**One interpreter, and this plan says so before it says anything else.** As with phases 3, 4, 5 and 6,
only Ruby 3.4.10 was available to the authoring machine (`ruby 3.4.10 (2026-06-30 revision 2b0b7728dc)
+PRISM [x86_64-linux]`). **The 3.2 and 4.0 columns have not been run for anything in this plan.**
Task 1 installs both and re-runs every fact on all three before any implementation task begins.

Measured on 3.4.10 while writing the design:

1. **`Integer(s, exception: false)` accepts six inputs `SSE-11` requires be ignored**: `"+5"`→5,
   `"-5"`→-5, `"0x10"`→16, `"1_0"`→10, `" 5"`→5, `"5\n"`→5. `"12abc".to_i` → 12. An anchored
   `Regexp.new("\\A[0-9]+\\z", timeout: 1.0)` rejects all eight adversarial inputs measured, including
   the full-width `"０５"`. **Task 6's screen is the pattern, not `Integer`.**
2. **`force_encoding` raises `FrozenError` on a frozen `String` even when the target encoding is the
   string's own**; `String#b` on a frozen string returns a fresh unfrozen BINARY copy.
3. **`(+"".b) << "é"` produces a UTF-8 string**; `(+"".b) << "x"` stays BINARY; `(+"".b) << "é".b`
   stays BINARY. Every encoding fixture in this plan is non-ASCII.
4. **`Data.define(:retry)` builds and `event.retry` parses.** `E.members` is the five symbols,
   `e.public_send(:retry)` works, `e.with(retry: 10)` works. **`rbs validate`'s acceptance of
   `def retry: () -> Integer?` is NOT verified** — Task 1 checks it, with `retry_ms` as the named
   fallback.
5. **`Data#with` copies the struct and shares its members**, so `SSE-20`'s second clause needs
   `Dexpace::Model#with` routing through `.build` and would be silently broken by a bespoke `#with`.
   A `Data` instance is frozen at construction and returns the same frozen reference from every
   accessor call.
6. **An `Enumerator` abandoned mid-`#next` never runs its `ensure`, after two `GC.start` calls; an
   ordinary `def each` with an `ensure` driven through `to_enum(:each)`/`#next` and abandoned never runs
   it either; and `block_given?` is `true` inside `#each` reached that way.**
7. **A thread parked in `r.readpartial(16)` on the read end of an `IO.pipe` whose read end is closed
   from another thread raises `IOError`.** Closing the **writer** end instead raises `EOFError`. Both
   halves of `SSE-31`'s conformance clause are therefore writable and deterministic on CRuby.
8. **The UTF-8 BOM is `[239, 187, 191]`**, and `String.new(capacity: n, encoding:
   ::Encoding::BINARY)` produces a BINARY buffer.

The following were confirmed by reading the shipped source rather than re-deriving them from prose:

- **`#read_line_utf8` keeps a lone `\r` as content** — phase 3a's own test asserts
  `assert_equal("a\rb", source("a\rb\n").read_line_utf8)`
  (`docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts.md:2201-2202`). This is why Task 3
  builds a line machine instead of calling it.
- **`Dexpace::Outcome::Success.build: (response: Dexpace::Response) -> …`**
  (`docs/work/mvp/phase4/phase4b/2026-09-09-phase4b-recovery-primitives.md:1527`). This is why Task 2
  defines SSE-owned sentinels instead of reusing `Outcome` (`P7-23`).
- **`Dexpace::Closeable` supplies `#initialize_closeable(owned: true)`, `#close`, `#closed?`,
  `#owned?` and requires a private `#release`**
  (`docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md:379-380`), with the latch mutex created
  in `#initialize_closeable` rather than lazily.
- **`Dexpace::ResponseBody#source` returns the same underlying handle every time, never a fresh
  replay** (`docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md:828-840`), and
  `Response#body` is typed `Dexpace::ResponseBody?` after `DEF-26`'s narrowing. Task 8's `SSE-32`
  convenience is written against exactly those two facts.
- **`Model.own(collection)` is `Ractor.make_shareable(collection, copy: true)`**, a deep-frozen copy
  (`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md:347`).

## This plan's open questions, resolved

The design's four open questions are resolved below with a concrete decision each; each names the task
that carries the check.

1. **`Event`'s fifth member is named `retry`**, matching the wire field. Task 1 Step 4 runs `rbs
   validate` on a scratch signature containing `def retry: () -> Integer?` on all three interpreters.
   **If any rejects it**, the member becomes `retry_ms` throughout, Task 4 says so at the step it
   changes, and a `P7-28` ledger row records that one `Event` member name differs from its wire field
   name. No other task changes.
2. **`SSE-12`'s BOM lookahead closes its `#peek` view immediately, inside an `ensure`, before the parent
   has advanced.** 3a's view-retention rule bites only when the parent's cursor passes what a live view
   still needs; a view closed before any parent read cannot meet it. Task 1 Step 5 confirms this against
   3a's shipped `#peek` rather than its prose.
3. **`SSE-39`'s read-count assertion attaches to the body's `#each` yields**, not to the
   `BufferedSource`'s internal reads: a `BufferedSource` pulls a chunk when its buffer empties, so a 1:1
   assertion against internal reads measures the buffer. Task 2 builds `CountingBody`, which yields one
   event's bytes per chunk and counts its yields; Task 8's assertion is `assert_equal(1,
   body.yield_count)` after one pull. The fallback, if 3a's buffering makes even that indirect, is a
   source double implementing `#getbyte` directly, and Task 2 builds that double anyway for Task 3.
4. **Task 11 begins by checking whether `tools/serde_boundary.rb` already exists**, because `7c` may
   have landed first. If it does, the task collapses to moving two `sse/**` rows into `GUARDED` and
   writes no fixtures; if it does not, the task builds the tool, the rake task and six fixtures. The
   step says so at the step, not in a preamble.

---

## Task order and dependency chain

Thirteen tasks, in exact buildable dependency order. Nothing in this list waits on `7a` or `7c` —
`SSE-37` positively forbids the first dependency and nothing in chapters 12 or 14 creates the second.

1. **Matrix fact verification and test support doubles** — installs `ruby@3.2.11` and `ruby@4.0.6`,
   re-runs the eight facts on all three, resolves open question 1, and produces the four doubles this
   plan needs.
2. `Dexpace::SSE`, the three constants, `Signal`/`SKIP`/`DONE`, `LimitExceededError`
   (`SSE-19` in part, `SSE-34` in part) — standalone.
3. `Dexpace::SSE::LineReader` (`SSE-2`, `SSE-14`'s line half, `SSE-19`'s line cap) — needs Task 2's
   constants and Task 1's source double.
4. `Dexpace::SSE::Event` (`SSE-20`, `SSE-21`, `SSE-22`) — needs phase 1's `Dexpace::Model` only;
   independent of Task 3.
5. `Dexpace::SSE::Reader` — the field machine and the BOM (`SSE-3`–`SSE-10`, `SSE-12`) — needs Tasks 3
   and 4.
6. `Dexpace::SSE::Reader` — `SSE-11`'s digit screen and magnitude cap — needs Task 5.
7. `Dexpace::SSE::Reader` — dispatch, end-of-stream, statefulness, ownership and the event cap
   (`SSE-1`, `SSE-13`–`SSE-19`) — needs Tasks 5 and 6.
8. `Dexpace::SSE::Stream` — the facade (`SSE-23`–`SSE-32`, `SSE-39`, `SSE-40`) — needs Task 7, phase 2's
   `Closeable`, phase 3b's `ResponseBody`, phase 4b's `close_quietly`/`attach_suppressed`.
9. `Dexpace::SSE::TypedStream` (`SSE-33`–`SSE-36`) — needs Tasks 2 and 8.
10. The `SSE-37`/`SSE-38` prohibition tests — needs Tasks 7, 8 and 9 to exist to assert against.
11. `gates:serde_boundary` — `SSE-37`'s mechanism, extended over `lib/dexpace/page/**` (spec-forced
    boundary 5) — needs Task 8's files to exist so the at-least-one-match assertion has something to
    match.
12. `OI-5`'s closure evidence — the YARD sentences that make the 3a-ceiling relationship visible from
    the code, and the four register-amendment texts drafted for a human.
13. Final wiring: the nine `require_relative` lines, the surface snapshot regeneration, the RBS
    baseline diff, and the checklist note. **The checklist itself is written at execution time per
    `CLAUDE.md` and is not a task this plan performs.**

---

## Task 1: Matrix Fact Verification and Test Support Doubles

**Requirement IDs:** none directly; this task is the plan's own evidence-gathering step, per the
precedent phases 3, 4, 5 and 6 all set.
**Design:** "The verified Ruby facts this phase is built on"; "Open questions for `7b`'s own plan".

**Files:**
- Create: `gems/dexpace-core/test/support/sse_doubles.rb`
- Create: `tools/verify_7b_facts.rb` (run by hand on each interpreter; never in CI)

**Needs:** phase 3a's `Dexpace::IO::BufferedSource`; phase 3b's `Dexpace::Body`.
**Produces:** `ByteSource`, `CountingBody`, `CountingResource`, `PipeSource` — the four doubles.

- [ ] **Step 1: Install the two missing interpreters and re-run the eight facts on all three**

```bash
mise use -g ruby@3.2.11 && ruby tools/verify_7b_facts.rb
mise use -g ruby@3.4.10 && ruby tools/verify_7b_facts.rb
mise use -g ruby@4.0.6  && ruby tools/verify_7b_facts.rb
```

`tools/verify_7b_facts.rb` prints one line per fact and exits non-zero on any disagreement. Facts 1–8
from "What was verified during planning" above, verbatim. **Record the three outputs in the task's
notes**; a fact that differs on any row is a design change, not a plan detail, and stops the task.

- [ ] **Step 2: Resolve open question 1 — does RBS accept a method named `retry`?**

```bash
mkdir -p /tmp/7b_rbs && cat > /tmp/7b_rbs/probe.rbs <<'RBS'
module Probe
  class E
    attr_reader retry: Integer?
    def self.build: (?retry: Integer?) -> Probe::E
  end
end
RBS
bundle exec rbs -I /tmp/7b_rbs validate
```

Expected: clean on all three interpreters. **If any rejects it**, the member is `retry_ms` throughout
Tasks 4, 5, 6, 7 and 9, and a `P7-28` ledger row is added in Task 13.

- [ ] **Step 3: Resolve open question 2 — `#peek`'s view, closed before any parent read**

A scratch script over 3a's shipped `BufferedSource`: build a source over a five-byte body, take
`#peek`, read three bytes from the view, close the view, then read all five bytes from the parent and
assert they are all there. Confirms `SSE-12`'s lookahead is genuinely non-consuming and that closing
the view early disturbs nothing.

- [ ] **Step 4: Write the four doubles**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Test doubles for phase 7b. Four objects, each existing because a real one cannot be scripted:
#
#   ByteSource       - a BufferedSource-shaped double over a fixed BINARY String, whose #getbyte,
#                      #peek and #skip are the only members 7b's line machine uses, and which counts
#                      #getbyte calls. It is deliberately NOT a Dexpace::IO::BufferedSource: 7b's
#                      contract on its source is exactly those three methods, and this is that and
#                      nothing more (phase 3b's FakeResponseBody set the precedent).
#   CountingBody     - a Dexpace::Body yielding one caller-supplied chunk per #each yield and
#                      counting the yields. SSE-39's no-read-ahead assertion attaches here.
#   CountingResource - a #close-counting closeable. SSE-23's five termination paths assert against it.
#   PipeSource       - a ByteSource-shaped double over the read end of an IO.pipe, so a read can be
#                      parked and torn down from another thread. SSE-31's hard half needs it.

module Dexpace
  module Test
    class ByteSource
      attr_reader :getbyte_count

      def initialize(bytes, chunk_at: nil)
        @bytes = bytes.b.freeze
        @pos = 0
        @getbyte_count = 0
        @chunk_at = chunk_at   # if set, #getbyte returns nil once past it until #release_chunk
      end

      def getbyte
        @getbyte_count += 1
        return nil if @pos >= @bytes.bytesize

        byte = @bytes.getbyte(@pos)
        @pos += 1
        byte
      end

      def peek = self.class.new(@bytes.byteslice(@pos..) || "".b)
      def skip(count) = @pos += count
      def close = @closed = true
      def closed? = !!@closed
    end
  end
end
```

`CountingBody`, `CountingResource` and `PipeSource` follow in the same file, each with the same
why-comment shape.

- [ ] **Step 5: Confirm the doubles load and the fact script is green on all three**

Run: `bundle exec ruby -w -Igems/dexpace-core/test -e 'require "support/sse_doubles"'`
Expected: PASS, no warnings.

---

## Task 2: `Dexpace::SSE`, the constants, the two sentinels and the limit error

**Requirement IDs:** `SSE-19` (the two constants and the error), `SSE-34` (the two sentinels),
`SSE-11` (`MAX_RETRY_MS`).
**Design:** "`R4` — the constants, and why these numbers"; "`R5`"; "Module layout".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/sse.rb`
- Create: `gems/dexpace-core/lib/dexpace/sse/signal.rb`
- Create: `gems/dexpace-core/lib/dexpace/sse/limit_exceeded_error.rb`
- Create: the three matching `sig/` mirrors
- Test: `gems/dexpace-core/test/dexpace/sse/sse_test.rb`

**Needs:** phase 1's `Dexpace::Model`; phase 1's `Dexpace::Error` module.
**Produces:** `Dexpace::SSE::MAX_LINE_BYTES`, `::MAX_EVENT_BYTES`, `::MAX_RETRY_MS`, `::SKIP`,
`::DONE`, `::Signal`, `::LimitExceededError`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# SSE-19 (the two documented caps and the loud rejection they raise), SSE-11 (the retry magnitude
# cap), SSE-34 (the two mapper-outcome sentinels).

require_relative "../../test_helper"
require "dexpace"

class DexpaceSSETest < DexpaceTestCase
  test "SSE-19: MAX_LINE_BYTES is 1 MiB and MAX_EVENT_BYTES is 8 MiB, both chosen and documented" do
    assert_equal(1 * 1024 * 1024, Dexpace::SSE::MAX_LINE_BYTES)
    assert_equal(8 * 1024 * 1024, Dexpace::SSE::MAX_EVENT_BYTES)
  end

  test "SSE-19: the line cap is strictly below phase 3a's materialisation ceiling" do
    # OI-5: this is a different bound at a different layer, never a second ceiling on the same
    # operation. The relationship is asserted rather than described so a later change to either
    # constant that inverted it would fail here.
    assert_operator(Dexpace::SSE::MAX_LINE_BYTES, :<, Dexpace::IO::MAX_MATERIALIZED_BYTES)
    assert_operator(Dexpace::SSE::MAX_EVENT_BYTES, :<, Dexpace::IO::MAX_MATERIALIZED_BYTES)
    assert_operator(Dexpace::SSE::MAX_LINE_BYTES, :<, Dexpace::SSE::MAX_EVENT_BYTES)
  end

  test "SSE-11: MAX_RETRY_MS is 2**31 - 1, design section 10.18's substituted constant" do
    assert_equal((2**31) - 1, Dexpace::SSE::MAX_RETRY_MS)
  end

  test "SSE-34: SKIP and DONE are two distinct frozen singletons" do
    refute_equal(Dexpace::SSE::SKIP, Dexpace::SSE::DONE)
    assert(Dexpace::SSE::SKIP.frozen?)
    assert(Dexpace::SSE::DONE.frozen?)
    assert_same(Dexpace::SSE::SKIP, Dexpace::SSE::SKIP)
  end

  test "SSE-34: a sentinel reaching a log identifies itself" do
    assert_equal("Dexpace::SSE::SKIP", Dexpace::SSE::SKIP.to_s)
    assert_equal("Dexpace::SSE::DONE", Dexpace::SSE::DONE.inspect)
  end

  test "SSE-34: Signal cannot be constructed by a caller, so the sentinel set is closed" do
    assert_raises(NoMethodError) { Dexpace::SSE::Signal.new(name: :other) }
  end

  test "SSE-19: LimitExceededError names which bound was crossed and its value" do
    error = Dexpace::SSE::LimitExceededError.new(kind: :line, limit: Dexpace::SSE::MAX_LINE_BYTES)
    assert_equal(:line, error.kind)
    assert_equal(Dexpace::SSE::MAX_LINE_BYTES, error.limit)
    assert_kind_of(Dexpace::Error, error)
    assert_kind_of(::StandardError, error)
    assert_match(/line/, error.message)
    assert_match(/1048576/, error.message)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/sse_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::SSE`, 7 tests.

- [ ] **Step 3: Write `lib/dexpace/sse/signal.rb` and `lib/dexpace/sse/limit_exceeded_error.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module SSE
    # SSE-34: one of the two mapper-outcome sentinels. The set is closed by construction —
    # `private_class_method :new` plus two module-level instances — so an outcome comparison is an
    # identity test and a decoded model that happens to == a sentinel cannot be mistaken for one.
    #
    # Dexpace::Outcome::Success and ::Failure are deliberately NOT reused: Success's single member is
    # `response: Dexpace::Response` (phase 4b), and Skip and Done are both *successful* outcomes that
    # differ in what the iterator does next, so Outcome's success/failure surface answers a question
    # this adapter is not asking. See P7-23.
    class Signal < ::Data.define(:name)
      private_class_method :new

      def self.build(name:) = allocate_frozen(name)
      def to_s = "Dexpace::SSE::#{name.to_s.upcase}"
      def inspect = to_s

      private_class_method def self.allocate_frozen(name) = send(:new, name: name).freeze
    end
  end
end
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module SSE
    # SSE-19: raised when a line or an accumulated event block crosses its documented bound.
    #
    # The port takes SSE-19's MAY and REJECTS rather than truncates: a truncated data line reaches
    # the caller's mapper as a parse failure at a place the caller cannot relate to the cause, and
    # design section 10.18's own sanction is "fails or ignores loudly". `kind` is :line or :event and
    # `limit` is the constant that was crossed, so a caller raising the cap knows which one to raise.
    class LimitExceededError < ::StandardError
      include Dexpace::Error

      attr_reader :kind, :limit

      def initialize(kind:, limit:)
        @kind = kind
        @limit = limit
        super("SSE #{kind} exceeded its #{limit}-byte limit")
      end
    end
  end
end
```

- [ ] **Step 4: Write `lib/dexpace/sse.rb` with the three constants and the two sentinels**

Each constant carries a YARD block stating the number, that it is **chosen rather than derived**, that
it is `SSE-19`'s (or `SSE-11`'s) documented divergence from a reference that imposes no maximum, and —
on `MAX_LINE_BYTES` — **that this is the bound `OI-5` names**. Task 12 checks that sentence exists.

- [ ] **Step 5: Write the `sig/` mirrors, add the requires, run to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/sse_test.rb`
Expected: PASS, 7 runs, 0 failures, 0 errors.

---

## Task 3: `Dexpace::SSE::LineReader` — the three terminators and the line cap

**Requirement IDs:** `SSE-2`, `SSE-14` (the unterminated-final-line half), `SSE-19` (the line cap).
**Design:** "`Dexpace::SSE::LineReader`"; "`R4` — the second correction"; `P7-20`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/sse/line_reader.rb`
- Create: `gems/dexpace-core/sig/dexpace/sse/line_reader.rbs`
- Test: `gems/dexpace-core/test/dexpace/sse/line_reader_test.rb`

**Needs:** Task 1's `ByteSource`; Task 2's `MAX_LINE_BYTES` and `LimitExceededError`.
**Produces:** `LineReader.new(source, max_line_bytes:)`, `#next_line -> String?`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# SSE-2 (LF, CR and CRLF all recognised, CRLF as a single terminator, terminators stripped, a lone CR
# terminating alone), SSE-14 (a final line with no terminator returned as content), SSE-19 (the line
# cap, rejecting loudly).
#
# P7-20: these tests are the whole reason this class exists rather than a call to phase 3a's
# #read_line_utf8. IO-14 requires a lone \r be KEPT AS CONTENT and SSE-2 requires it TERMINATE — the
# "lone CR" test below is exactly the assertion phase 3a's own suite makes in the opposite direction
# (docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts.md:2201).

require_relative "../../test_helper"
require "dexpace"
require "support/sse_doubles"

class DexpaceSSELineReaderTest < DexpaceTestCase
  def lines(bytes, **kwargs)
    reader = Dexpace::SSE::LineReader.new(Dexpace::Test::ByteSource.new(bytes), **kwargs)
    out = []
    while (line = reader.next_line)
      out << line
    end
    out
  end

  test "SSE-2: LF terminates and is stripped" do
    assert_equal(["one", "two"], lines("one\ntwo\n"))
  end

  test "SSE-2: CRLF is a single terminator, not two" do
    assert_equal(["one", "two"], lines("one\r\ntwo\r\n"))
  end

  test "SSE-2: a lone CR terminates a line by itself" do
    assert_equal(["a", "b"], lines("a\rb\r"))
  end

  test "SSE-2: a CR followed by a non-LF byte terminates and that byte starts the next line" do
    assert_equal(["a", "b"], lines("a\rb\n"))
  end

  test "SSE-2: mixed terminators produce the same line list" do
    assert_equal(["a", "b", "c"], lines("a\nb\r\nc\r"))
  end

  test "SSE-2: a bare terminator yields an empty line, which is the dispatch boundary" do
    assert_equal(["a", "", "b"], lines("a\n\nb\n"))
    assert_equal(["a", "", "b"], lines("a\r\n\r\nb\r\n"))
    assert_equal(["a", "", "b"], lines("a\r\rb\r"))
  end

  test "SSE-14: a final line with no terminator comes back as content" do
    assert_equal(["a", "tail"], lines("a\ntail"))
  end

  test "SSE-2/SSE-14: a stream ending in a lone CR terminates that line" do
    assert_equal(["a"], lines("a\r"))
  end

  test "returns nil when exhausted before any byte, and stays nil" do
    reader = Dexpace::SSE::LineReader.new(Dexpace::Test::ByteSource.new(""))
    assert_nil(reader.next_line)
    assert_nil(reader.next_line)
  end

  test "lines are BINARY, and a non-ASCII line stays BINARY" do
    # An ASCII-only fixture passes under exactly the bug io-and-byte-streams/a44b4de6 names, so this
    # assertion uses non-ASCII content deliberately.
    line = lines("café\n").first
    assert_equal(::Encoding::BINARY, line.encoding)
    assert_equal("café".b, line)
  end

  test "SSE-19: a line of exactly the cap passes and one byte more raises" do
    cap = 64
    assert_equal(["x" * cap], lines("#{"x" * cap}\n", max_line_bytes: cap))

    error = assert_raises(Dexpace::SSE::LimitExceededError) do
      lines("#{"x" * (cap + 1)}\n", max_line_bytes: cap)
    end
    assert_equal(:line, error.kind)
    assert_equal(cap, error.limit)
  end

  test "SSE-19: the cap defaults to MAX_LINE_BYTES" do
    reader = Dexpace::SSE::LineReader.new(Dexpace::Test::ByteSource.new(""))
    assert_equal(Dexpace::SSE::MAX_LINE_BYTES, reader.max_line_bytes)
  end

  test "SSE-19: the cap rejects before materialising, not after" do
    # A source that would supply far more than the cap must be stopped at the cap, so the read count
    # is bounded by it. This is what distinguishes a guard from an after-the-fact length check.
    source = Dexpace::Test::ByteSource.new("x" * 10_000)
    reader = Dexpace::SSE::LineReader.new(source, max_line_bytes: 64)
    assert_raises(Dexpace::SSE::LimitExceededError) { reader.next_line }
    assert_operator(source.getbyte_count, :<=, 66)
  end

  test "SSE-17: the line reader never closes its source" do
    source = Dexpace::Test::ByteSource.new("a\n")
    Dexpace::SSE::LineReader.new(source).next_line
    refute(source.closed?)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/line_reader_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::SSE::LineReader`, 14 tests.

- [ ] **Step 3: Write `lib/dexpace/sse/line_reader.rb`**

The machine, in one method:

```ruby
LF = 0x0A
CR = 0x0D

def next_line
  buffer = @buffer.clear
  byte = take_byte
  return nil if byte.nil?

  while byte
    case byte
    when LF then return finish(buffer)
    when CR
      following = @source.getbyte
      @pushback = following unless following.nil? || following == LF
      return finish(buffer)
    else
      raise Dexpace::SSE::LimitExceededError.new(kind: :line, limit: @max_line_bytes) if
        buffer.bytesize >= @max_line_bytes

      buffer << byte
    end
    byte = take_byte
  end

  finish(buffer)   # SSE-14: a final line with no terminator is content
end
```

with `#take_byte` draining the one-byte pushback first and `#finish` returning a frozen `dup` of the
BINARY buffer. `@buffer` is a `::String.new(capacity: 4096, encoding: ::Encoding::BINARY)` reused
across lines, which keeps the machine allocation-flat on a long stream.

The YARD block states the inherent property: **a line terminated by a lone CR cannot be dispatched
until one further byte arrives**, because nothing distinguishes CR from the first half of CRLF without
it. That is the grammar's, WHATWG has it too, and it affects only a CR-terminating server.

- [ ] **Step 4: Write the `sig/` mirror, add the require, run to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/line_reader_test.rb`
Expected: PASS, 14 runs, 0 failures, 0 errors.

- [ ] **Step 5: Add the terminator property test**

Over a seeded generator of line contents and a generated assignment of terminators from
`["\n", "\r\n", "\r"]`, the parsed line list equals the generated one. **Seed pinned and logged**
(`testing/7ece0212`). This is `SSE-2`'s exhaustiveness claim in executable form and it is where a
lone-CR-at-a-chunk-boundary bug in the pushback surfaces.

---

## Task 4: `Dexpace::SSE::Event` — the immutable five-field value

**Requirement IDs:** `SSE-20`, `SSE-21`, `SSE-22`.
**Design:** "`Dexpace::SSE::Event`"; verified fact 5.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/sse/event.rb`
- Create: `gems/dexpace-core/sig/dexpace/sse/event.rbs`
- Test: `gems/dexpace-core/test/dexpace/sse/event_test.rb`

**Needs:** phase 1's `Dexpace::Model` (`Model.own`, the `.build`-routing `#with`).
**Produces:** `Event.build(id:, event:, data:, comment:, retry:)`, the five readers, `#empty?`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# SSE-20 (immutable, defensively-copied read-only data list, copied again on copy-with-changes),
# SSE-21 (structural equality and hash over all five fields, a stable string form), SSE-22 (the
# is-empty predicate, true only when all five are unset).

require_relative "../../test_helper"
require "dexpace"

class DexpaceSSEEventTest < DexpaceTestCase
  test "SSE-20: mutating the list the event was built from cannot reach inside it" do
    original = ["a", "b"]
    event = Dexpace::SSE::Event.build(data: original)
    original << "c"
    original[0] << "!"
    assert_equal(["a", "b"], event.data)
  end

  test "SSE-20: the data list and its elements are frozen" do
    event = Dexpace::SSE::Event.build(data: ["a"])
    assert(event.data.frozen?)
    assert(event.data.first.frozen?)
    assert_raises(::FrozenError) { event.data << "b" }
  end

  test "SSE-20: #with copies the data list rather than sharing it" do
    # verified fact 5: raw Data#with copies the struct and SHARES its members. Dexpace::Model#with
    # routes through .build, so the list is re-owned. This test fails if a bespoke #with is ever
    # written over the module's.
    source = ["a"]
    event = Dexpace::SSE::Event.build(data: source)
    derived = event.with(id: "1")
    refute_same(source, derived.data)
    assert_equal(["a"], derived.data)
  end

  test "SSE-20: the same frozen reference comes back from every accessor call" do
    event = Dexpace::SSE::Event.build(data: ["a"])
    assert_same(event.data, event.data)
  end

  test "SSE-21: equality and hash are over all five fields" do
    a = Dexpace::SSE::Event.build(id: "1", event: "e", data: ["d"], comment: "c", retry: 5)
    b = Dexpace::SSE::Event.build(id: "1", event: "e", data: ["d"], comment: "c", retry: 5)
    assert_equal(a, b)
    assert_equal(a.hash, b.hash)
    refute_equal(a, b.with(retry: 6))
    refute_equal(a, b.with(comment: "other"))
  end

  test "SSE-21: the string form is stable and names the type" do
    event = Dexpace::SSE::Event.build(data: ["d"])
    assert_match(/Dexpace::SSE::Event/, event.inspect)
    assert_equal(event.inspect, Dexpace::SSE::Event.build(data: ["d"]).inspect)
  end

  test "SSE-22: #empty? is true only when all five fields are unset" do
    assert(Dexpace::SSE::Event.build.empty?)
    refute(Dexpace::SSE::Event.build(id: "1").empty?)
    refute(Dexpace::SSE::Event.build(retry: 0).empty?)
  end

  test "SSE-22/SSE-6: a comment-only keep-alive reports non-empty, because a comment is content" do
    refute(Dexpace::SSE::Event.build(comment: "keep-alive").empty?)
  end

  test "SSE-22/SSE-4: a present-but-empty field is not 'unset'" do
    # SSE-4 makes present-but-empty distinct from absent, so neither of these is empty.
    refute(Dexpace::SSE::Event.build(event: "").empty?)
    refute(Dexpace::SSE::Event.build(data: [""]).empty?)
  end

  test "an event is frozen at construction and cannot be built through .new" do
    assert(Dexpace::SSE::Event.build.frozen?)
    assert_raises(NoMethodError) { Dexpace::SSE::Event.new(id: nil) }
  end

  test "SSE-20: non-ASCII data survives construction with its encoding intact" do
    event = Dexpace::SSE::Event.build(data: ["café"])
    assert_equal("café", event.data.first)
    assert_equal(::Encoding::UTF_8, event.data.first.encoding)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/event_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::SSE::Event`, 11 tests.

- [ ] **Step 3: Write `lib/dexpace/sse/event.rb`**

`Data.define(:id, :event, :data, :comment, :retry)` including `Dexpace::Model`, with
`private_class_method :new` and a `.build` whose only work is `Model.own(data)` —
`Ractor.make_shareable(collection, copy: true)`, a deep-frozen copy, which is what makes both the
list and its elements frozen and what makes the mutate-the-original test pass on both construction
and derivation. `#empty?` is the five-way `nil`/`empty?` test.

**If Task 1 Step 2 rejected the RBS spelling**, the member is `retry_ms` here and in Tasks 5, 6, 7 and
9, and the test names change with it.

- [ ] **Step 4: Write the `sig/` mirror, add the require, run to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/event_test.rb`
Expected: PASS, 11 runs, 0 failures, 0 errors.

---

## Task 5: `Dexpace::SSE::Reader` — the field machine and the BOM

**Requirement IDs:** `SSE-3`, `SSE-4`, `SSE-5`, `SSE-6`, `SSE-7`, `SSE-8`, `SSE-9`, `SSE-10`, `SSE-12`.
**Design:** "`Dexpace::SSE::Reader`"; "Encoding, stated once for `7b`"; `P7-24`, `P7-26`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/sse/reader.rb`
- Create: `gems/dexpace-core/sig/dexpace/sse/reader.rbs`
- Test: `gems/dexpace-core/test/dexpace/sse/reader_test.rb`

**Needs:** Tasks 3 and 4.
**Produces:** `Reader.new(source, max_line_bytes:, max_event_bytes:)`, `#next_event -> Event?` (the
field half; dispatch and end-of-stream arrive in Task 7).

- [ ] **Step 1: Write the failing test — the grammar battery, from the chapter's own clauses**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# SSE-3 (split at the first colon), SSE-4 (present-but-empty is not absent), SSE-5 (strip exactly one
# leading space), SSE-6 (comments, latest-wins, counting as a field seen), SSE-7 (only four field
# names interpreted, CASE-SENSITIVELY - P7-24), SSE-8 (data lines accumulate in wire order, unjoined),
# SSE-9 (a NUL in an id ignores the field entirely), SSE-10 (event is raw, latest-wins, never
# defaulted to "message"), SSE-12 (a single leading BOM through non-consuming lookahead).
#
# Every fixture string below is taken verbatim from the conformance clause of the requirement its
# test names, in docs/product-spec/13-server-sent-events-and-streaming.md.

require_relative "../../test_helper"
require "dexpace"
require "support/sse_doubles"

class DexpaceSSEReaderTest < DexpaceTestCase
  def first_event(bytes)
    Dexpace::SSE::Reader.new(Dexpace::Test::ByteSource.new(bytes)).next_event
  end

  test "SSE-3: a colon-less line is a field name with an empty value" do
    assert_equal([""], first_event("data\n\n").data)
  end

  test "SSE-3: a trailing colon yields an empty value" do
    assert_equal([""], first_event("data:\n\n").data)
  end

  test "SSE-3: an unrecognized field with no colon dispatches no event" do
    assert_nil(first_event("garbage\n\n"))
  end

  test "SSE-4: a present empty event name is present, not absent" do
    assert_equal("", first_event("event:\ndata:x\n\n").event)
  end

  test "SSE-5: exactly one leading space is stripped and further spaces are preserved" do
    assert_equal(["hello"], first_event("data: hello\n\n").data)
    assert_equal(["  hello"], first_event("data:   hello\n\n").data)
  end

  test "SSE-6: a comment line is captured and counts as a field seen on its own" do
    event = first_event(":keep-alive\n\n")
    assert_equal("keep-alive", event.comment)
    assert_empty(event.data)
  end

  test "SSE-6: comments are latest-wins within a block" do
    assert_equal("second", first_event(":first\n:second\ndata:x\n\n").comment)
  end

  test "SSE-7: an unknown field sets no state and causes no dispatch on its own" do
    event = first_event("garbage: zzz\nevent: kept\ndata: p\n\n")
    assert_equal("kept", event.event)
    assert_equal(["p"], event.data)
    assert_nil(event.id)
    assert_nil(event.comment)
  end

  test "SSE-7/P7-24: field names are compared CASE-SENSITIVELY, so DATA: is an unknown field" do
    # WHATWG compares field names exactly and SSE-7 names four lowercase tokens, requiring every
    # other name be silently discarded. A downcase here would make DATA: an interpreted data field.
    # This is the charter's spec-forced boundary 19 having no site in 7b.
    assert_nil(first_event("DATA: x\n\n"))
    assert_nil(first_event("Event: x\n\n"))
  end

  test "SSE-8: consecutive data fields accumulate in wire order, unjoined" do
    assert_equal(["line1", "line2"], first_event("data: line1\ndata: line2\n\n").data)
  end

  test "SSE-9: an id containing a NUL is ignored entirely" do
    assert_nil(first_event("id: a\0b\ndata:x\n\n").id)
  end

  test "SSE-9: a NUL id does not overwrite a valid id already seen in the same block" do
    assert_equal("good", first_event("id: good\nid: a\0b\ndata:x\n\n").id)
  end

  test "SSE-9: a valid id is stored verbatim, latest-wins" do
    assert_equal("second", first_event("id: first\nid: second\ndata:x\n\n").id)
  end

  test "SSE-10: an absent event field is absent and is never defaulted to 'message'" do
    assert_nil(first_event("data:x\n\n").event)
  end

  test "SSE-12: a single leading BOM is consumed and excluded from the first event's fields" do
    assert_equal(["x"], first_event("\xEF\xBB\xBFdata: x\n\n").data)
  end

  test "SSE-12: a BOM later in the stream survives as ordinary data" do
    assert_equal(["a\u{FEFF}b"], first_event("data: a\u{FEFF}b\n\n").data)
  end

  test "SSE-12: a non-BOM prefix is left intact - the lookahead is non-consuming" do
    # A reader that consumed three bytes unconditionally would pass every BOM-prefixed fixture and
    # corrupt every stream without one.
    assert_equal(["xyz"], first_event("data: xyz\n\n").data)
    assert_equal(["\xEF\xBB"], first_event("data: \xEF\xBB\n\n").data)
  end

  test "SSE-12: a stream shorter than three bytes does not confuse the lookahead" do
    assert_nil(first_event("\n"))
  end

  test "P7-26: field values are UTF-8, decoded once with both encodings named" do
    value = first_event("data: café\n\n").data.first
    assert_equal(::Encoding::UTF_8, value.encoding)
    assert_equal("café", value)
  end

  test "P7-26: an invalid UTF-8 byte is replaced rather than raising" do
    value = first_event("data: a\xFFb\n\n").data.first
    assert_equal(::Encoding::UTF_8, value.encoding)
    assert(value.valid_encoding?)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/reader_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::SSE::Reader`, 20 tests.

- [ ] **Step 3: Write the field machine**

`#consume_bom_once` runs on the first `#next_event` only, through `@source.peek` read for up to three
bytes with the view closed in an `ensure`, and `@source.skip(3)` only on an exact `[0xEF, 0xBB, 0xBF]`
match. `#apply_line(line)` does the byte-level work — `0x3A` first byte is a comment, split at the
first `0x3A`, strip one `0x20` — then dispatches on the **exact** BINARY field name against four
frozen BINARY constants. Decoding is `#decode(bytes)`:

```ruby
def decode(bytes)
  bytes.b.force_encoding(::Encoding::UTF_8)
       .encode(::Encoding::UTF_8, ::Encoding::UTF_8, invalid: :replace, undef: :replace)
end
```

`String#b` first because `force_encoding` raises `FrozenError` on a frozen string even when the target
is its own encoding; both encodings named on `#encode` because `undef: :replace` with no target
follows `Encoding.default_internal`, a process global the host sets.

`SSE-9`'s NUL check runs on the **BINARY** value, before decoding, so a NUL cannot be lost to a
replacement character first.

- [ ] **Step 4: Write the `sig/` mirror, add the require, run to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/reader_test.rb`
Expected: PASS, 20 runs, 0 failures, 0 errors.

---

## Task 6: `SSE-11` — the retry screen and the magnitude cap

**Requirement IDs:** `SSE-11`.
**Design:** verified fact 1; "`R4`", which states at length that this is **not** the line cap.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/sse/reader.rb`
- Test: `gems/dexpace-core/test/dexpace/sse/reader_test.rb` (appended)

**Needs:** Task 5.
**Produces:** `Reader`'s `retry` handling.

- [ ] **Step 1: Write the failing test**

```ruby
# appended to reader_test.rb
#
# SSE-11: the retry field's value screen and magnitude cap. This is a SEPARATE cap from SSE-19's
# line cap and a separate checklist row; OI-5 conflated the two once already and the two tests sit
# apart deliberately.

test "SSE-11: a digits-only value is accepted as a non-negative millisecond duration" do
  assert_equal(5000, first_event("retry: 5000\n\n").retry)
  assert_equal(0, first_event("retry: 0\n\n").retry)
  assert_equal(5, first_event("retry: 05\n\n").retry)
end

test "SSE-11: retry is latest-wins within a block" do
  assert_equal(2, first_event("retry: 1\nretry: 2\n\n").retry)
end

test "SSE-11: every non-digits-only form leaves retry unset" do
  # verified fact 1: Integer(s, exception: false) ACCEPTS six of these. This battery is the reason
  # the screen is an anchored pattern and not Integer() or #to_i.
  ["retry: bad", "retry: -100", "retry: +5", "retry:", "retry: 0x10", "retry: 1_0",
   "retry:  5", "retry: 5a", "retry: ０５"].each do |line|
    assert_nil(first_event("#{line}\ndata:x\n\n").retry, "expected #{line.inspect} to be ignored")
  end
end

test "SSE-11: an ignored retry does not mark the block dispatchable on its own account" do
  assert_nil(first_event("retry: bad\n\n"))
end

test "SSE-11: a value above the documented cap is ignored rather than wrapped" do
  assert_nil(first_event("retry: #{Dexpace::SSE::MAX_RETRY_MS + 1}\n\n"))
  assert_equal(Dexpace::SSE::MAX_RETRY_MS, first_event("retry: #{Dexpace::SSE::MAX_RETRY_MS}\n\n").retry)
end

test "SSE-11: an over-cap retry does not overwrite a valid one already seen in the block" do
  assert_equal(7, first_event("retry: 7\nretry: #{Dexpace::SSE::MAX_RETRY_MS + 1}\ndata:x\n\n").retry)
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/reader_test.rb`
Expected: 6 new failures — the reader does not yet interpret `retry`.

- [ ] **Step 3: Implement the screen**

```ruby
# SSE-11: "accepted only if it consists solely of ASCII digits 0-9". Integer(s, exception: false)
# accepts "+5", "-5", "0x10", "1_0", " 5" and "5\n" (measured on 3.4.10) and String#to_i accepts
# "12abc" - every one of which this requirement says to ignore. An anchored pattern is the only
# screen that is right, and it carries its own per-pattern timeout because a library must not set
# the process-global Regexp.timeout (CLAUDE.md, design section 4).
DIGITS_ONLY = ::Regexp.new("\\A[0-9]+\\z", timeout: 1.0).freeze
```

with the accepted value compared against `Dexpace::SSE::MAX_RETRY_MS` and ignored above it. The
magnitude cap's YARD names design §10.18 and states in one clause that **this is not the line cap**.

- [ ] **Step 4: Run to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/reader_test.rb`
Expected: PASS, 26 runs, 0 failures, 0 errors.

---

## Task 7: `Dexpace::SSE::Reader` — dispatch, end-of-stream, statefulness, ownership, the event cap

**Requirement IDs:** `SSE-1`, `SSE-13`, `SSE-14`, `SSE-15`, `SSE-16`, `SSE-17`, `SSE-18`, `SSE-19` (the
event cap).
**Design:** "`Dexpace::SSE::Reader`"; the "five rows the checklist must state rather than tick" entry
for `SSE-18`; `P7-22`.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/sse/reader.rb`
- Test: `gems/dexpace-core/test/dexpace/sse/reader_test.rb` (appended)

**Needs:** Tasks 5 and 6.
**Produces:** `#next_event`'s dispatch, sticky end and event cap.

- [ ] **Step 1: Write the failing test**

```ruby
# appended to reader_test.rb
#
# SSE-1 (a blank line collapses accumulated fields into exactly one event and resets accumulators),
# SSE-13 (permissive dispatch; a no-field block is skipped), SSE-14 (EOF dispatches a pending block),
# SSE-15 (a sticky end-of-stream sentinel), SSE-16 (only the BOM flag persists), SSE-17 (the reader
# owns nothing), SSE-18 (documented single-threaded; no lock), SSE-19 (the event cap).

def events(bytes, **kwargs)
  reader = Dexpace::SSE::Reader.new(Dexpace::Test::ByteSource.new(bytes), **kwargs)
  out = []
  while (event = reader.next_event)
    out << event
  end
  out
end

test "SSE-1: a blank line is the dispatch boundary and resets the accumulators" do
  assert_equal([["1"], ["2"]], events("data: 1\n\ndata: 2\n\n").map(&:data))
end

test "SSE-1/SSE-16: the second event's id is absent when only the first block carried one" do
  parsed = events("id: 1\ndata: a\n\ndata: b\n\n")
  assert_equal("1", parsed.first.id)
  assert_nil(parsed.last.id)
end

test "SSE-13: an id-only block dispatches" do
  assert_equal(["42"], events("id: 42\n\n").map(&:id))
end

test "SSE-13: a retry-only block and a comment-only block both dispatch" do
  assert_equal(1, events("retry: 5\n\n").size)
  assert_equal(1, events(":c\n\n").size)
end

test "SSE-13: a block in which no field was set is skipped" do
  assert_empty(events("\n\n\n"))
end

test "SSE-14: a partial block still present at EOF is dispatched" do
  parsed = events("data: hello")
  assert_equal(1, parsed.size)
  assert_equal(["hello"], parsed.first.data)
end

test "SSE-14: an empty stream signals end immediately with no event" do
  assert_empty(events(""))
end

test "SSE-15: the end sentinel is sticky" do
  reader = Dexpace::SSE::Reader.new(Dexpace::Test::ByteSource.new("data: a\n\n"))
  refute_nil(reader.next_event)
  assert_nil(reader.next_event)
  assert_nil(reader.next_event)
  assert_nil(reader.next_event)
end

test "SSE-16: nothing but the BOM flag persists across calls - no carried retry value" do
  # sse-streaming/2dba42b0 and design section 7.2 both say the current retry value and the last event
  # id are per-stream state. SSE-16 says "only the BOM already consumed flag persists" and SSE-38
  # says the last-event-id MUST NOT be persisted. These two tests assert the requirements.
  parsed = events("retry: 500\ndata: a\n\ndata: b\n\n")
  assert_equal(500, parsed.first.retry)
  assert_nil(parsed.last.retry)
end

test "SSE-16/SSE-38: no last-event-id is carried forward" do
  parsed = events("id: 1\ndata: a\n\ndata: b\n\nid: 3\ndata: c\n\n")
  assert_equal(["1", nil, "3"], parsed.map(&:id))
end

test "SSE-17: the reader never closes its source, driven to completion" do
  source = Dexpace::Test::ByteSource.new("data: a\n\ndata: b\n\n")
  reader = Dexpace::SSE::Reader.new(source)
  reader.next_event while reader.next_event
  refute(source.closed?)
end

test "SSE-19: an event block whose accumulated bytes cross the cap raises" do
  cap = 32
  assert_equal(1, events("data: #{"x" * 20}\n\n", max_event_bytes: cap).size)

  error = assert_raises(Dexpace::SSE::LimitExceededError) do
    events("data: #{"x" * 20}\ndata: #{"y" * 20}\n\n", max_event_bytes: cap)
  end
  assert_equal(:event, error.kind)
  assert_equal(cap, error.limit)
end

test "SSE-19: the event byte total resets at each dispatch" do
  cap = 32
  parsed = events("data: #{"x" * 20}\n\ndata: #{"y" * 20}\n\n", max_event_bytes: cap)
  assert_equal(2, parsed.size)
end

test "SSE-19: both caps default to their constants" do
  reader = Dexpace::SSE::Reader.new(Dexpace::Test::ByteSource.new(""))
  assert_equal(Dexpace::SSE::MAX_LINE_BYTES, reader.max_line_bytes)
  assert_equal(Dexpace::SSE::MAX_EVENT_BYTES, reader.max_event_bytes)
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/reader_test.rb`
Expected: 14 new failures.

- [ ] **Step 3: Implement dispatch and the sticky end**

`#next_event` loops `@lines.next_line`; a blank line with `@seen` true builds an `Event` and resets the
five accumulators; `nil` from the line reader dispatches a pending block once (`SSE-14`) and then
latches `@ended` so every later call returns `nil` (`SSE-15`). The accumulated byte total is checked
against `@max_event_bytes` on every field append and reset at dispatch.

**`SSE-18` is satisfied by omission**: no lock is added. The class's YARD block states the
single-threaded contract explicitly, and **there is no test**, because no assertion distinguishes
"documented single-threaded" from "accidentally single-threaded". The checklist row says the same.

- [ ] **Step 4: Write the `sig/` update, run to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/reader_test.rb`
Expected: PASS, 40 runs, 0 failures, 0 errors.

- [ ] **Step 5: Add the mutation battery on the two caps at their real values**

A line of exactly `MAX_LINE_BYTES` passes and `+1` raises; an event block of exactly
`MAX_EVENT_BYTES` passes and `+1` raises. **The assertions name the constants, never the literals**,
so a second constant would break the test rather than pass it. This is 3b's and 4b's precedent for the
same shape, and it is the one place `7b` allocates at scale — roughly 1 MiB and 8 MiB per run per
matrix row, stated so it is a decision rather than an accident.

---

## Task 8: `Dexpace::SSE::Stream` — the resource-owning facade

**Requirement IDs:** `SSE-23`, `SSE-24`, `SSE-25`, `SSE-26`, `SSE-27`, `SSE-28`, `SSE-29`, `SSE-30`,
`SSE-31`, `SSE-32`, `SSE-39`, `SSE-40`.
**Design:** "`Dexpace::SSE::Stream`"; "`R6`"; "§7.1's `Enumerator` rule applied"; `P7-25`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/sse/stream.rb`
- Create: `gems/dexpace-core/lib/dexpace/sse/stream_state_error.rb`
- Create: `gems/dexpace-core/sig/dexpace/sse/stream.rbs` and `…/stream_state_error.rbs`
- Test: `gems/dexpace-core/test/dexpace/sse/stream_test.rb`

**Needs:** Task 7; phase 2's `Dexpace::Closeable` and `Dexpace::InvalidArgumentError`; phase 3b's
`Dexpace::ResponseBody`; phase 4b's `Dexpace.close_quietly` and `Dexpace.attach_suppressed`; Task 1's
`CountingResource`, `CountingBody` and `PipeSource`.
**Produces:** `Stream.open(response)`, `.owning(source)`, `.borrowing(source)`, `#each`, `#events`,
`#close`, `#closed?`; and `Dexpace::SSE::StreamStateError`, `SSE-26`/`SSE-27`'s loud failure.

- [ ] **Step 1: Write the failing test — the lifecycle battery**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# SSE-23 (exactly one closeable resource, closed exactly once across every termination path), SSE-24
# (clean end releases), SSE-25 (partial consume must not strand), SSE-26 (single-pass), SSE-27
# (post-close iteration fails; an in-flight iterator ends cleanly), SSE-28 (idempotent close), SSE-29
# (mid-stream failure releases before propagating, with the release failure suppressed), SSE-30 (the
# swallow-versus-propagate split), SSE-31 (cross-thread close, both shapes), SSE-32 (the response
# convenience), SSE-39 (no eager read-ahead), SSE-40 (the lazy single-pass view).

require_relative "../../test_helper"
require "dexpace"
require "support/sse_doubles"

class DexpaceSSEStreamTest < DexpaceTestCase
  FIXTURE = "data: a\n\ndata: b\n\ndata: c\n\n"

  def stream_over(bytes = FIXTURE, resource: nil)
    resource ||= Dexpace::Test::CountingResource.new
    [Dexpace::SSE::Stream.owning(Dexpace::Test::ByteSource.new(bytes), resource: resource), resource]
  end

  test "SSE-23/SSE-24: iterating to completion without close releases the resource exactly once" do
    stream, resource = stream_over
    stream.each { |_event| nil }
    assert_equal(1, resource.close_count)
  end

  test "SSE-23/SSE-28: three explicit closes release once" do
    stream, resource = stream_over
    3.times { stream.close }
    assert_equal(1, resource.close_count)
  end

  test "SSE-28: an explicit close after an automatic release leaves the count at one" do
    stream, resource = stream_over
    stream.each { |_event| nil }
    stream.close
    assert_equal(1, resource.close_count)
  end

  test "SSE-25: a partial consume through the block form releases on exit" do
    stream, resource = stream_over
    stream.each { |_event| break }
    assert_equal(1, resource.close_count)
  end

  test "SSE-25: a partial consume through the enumerator releases on explicit close" do
    # verified fact 6: an Enumerator abandoned mid-#next never runs its ensure and GC is not a
    # cleanup hook. This test asserts BOTH halves - the absence of a release after abandonment and
    # its presence after the documented remedy - because asserting only the second would hide the
    # rule the design is built on.
    stream, resource = stream_over
    enum = stream.events
    enum.next
    enum = nil
    GC.start
    GC.start
    assert_equal(0, resource.close_count)
    stream.close
    assert_equal(1, resource.close_count)
  end

  test "SSE-26: obtaining an iterator twice fails loudly" do
    stream, = stream_over
    stream.events
    assert_raises(Dexpace::SSE::StreamStateError) { stream.events }
  end

  test "SSE-26/SSE-40: #each after #events also fails - one view, either shape" do
    stream, = stream_over
    stream.events
    assert_raises(Dexpace::SSE::StreamStateError) { stream.each { |_e| nil } }
  end

  test "SSE-27: requesting an iterator after close fails loudly" do
    stream, = stream_over
    stream.close
    assert_raises(Dexpace::SSE::StreamStateError) { stream.events }
  end

  test "SSE-27/SSE-31: a close observed between pulls ends iteration cleanly" do
    stream, resource = stream_over
    enum = stream.events
    assert_equal(["a"], enum.next.data)
    stream.close
    assert_raises(StopIteration) { enum.next }
    assert_equal(1, resource.close_count)
  end

  test "SSE-29: a mid-stream read failure releases before propagating" do
    resource = Dexpace::Test::CountingResource.new
    source = Dexpace::Test::ByteSource.failing_after("data: a\n\n", Dexpace::StreamError.new("boom"))
    stream = Dexpace::SSE::Stream.owning(source, resource: resource)
    enum = stream.events
    assert_equal(["a"], enum.next.data)
    assert_raises(Dexpace::StreamError) { enum.next }
    assert_equal(1, resource.close_count)
  end

  test "SSE-29: a release failure during a mid-stream failure is attached as suppressed" do
    resource = Dexpace::Test::CountingResource.new(raise_on_close: ::IOError.new("close failed"))
    source = Dexpace::Test::ByteSource.failing_after("", Dexpace::StreamError.new("boom"))
    stream = Dexpace::SSE::Stream.owning(source, resource: resource)
    error = assert_raises(Dexpace::StreamError) { stream.each { |_e| nil } }
    assert_equal(["close failed"], Dexpace.suppressed(error).map(&:message))
  end

  test "SSE-30: a release failure on the automatic terminal path is swallowed" do
    resource = Dexpace::Test::CountingResource.new(raise_on_close: ::IOError.new("close failed"))
    stream = Dexpace::SSE::Stream.owning(Dexpace::Test::ByteSource.new(FIXTURE), resource: resource)
    delivered = []
    stream.each { |event| delivered << event.data.first }
    assert_equal(%w[a b c], delivered)
  end

  test "SSE-30: a release failure during an EXPLICIT close propagates" do
    resource = Dexpace::Test::CountingResource.new(raise_on_close: ::IOError.new("close failed"))
    stream = Dexpace::SSE::Stream.owning(Dexpace::Test::ByteSource.new(FIXTURE), resource: resource)
    assert_raises(::IOError) { stream.close }
  end

  test "SSE-31: a close that tears down an in-flight blocked read surfaces as an I/O error" do
    # verified fact 7: closing the read end of an IO.pipe from another thread while a thread is
    # parked in readpartial raises IOError in the parked thread. Sequenced through a Queue so it is
    # deterministic rather than timing-dependent, which is phase 3a's IO-38 precedent.
    source = Dexpace::Test::PipeSource.new
    resource = Dexpace::Test::CountingResource.new
    stream = Dexpace::SSE::Stream.owning(source, resource: resource)
    parked = ::Thread::Queue.new
    reader = ::Thread.new do
      parked << :ready
      stream.each { |_e| nil }
    rescue ::StandardError => e
      e
    end
    parked.pop
    source.wait_until_blocked
    stream.close
    assert_kind_of(::IOError, reader.value)
    assert_equal(1, resource.close_count)
  end

  test "SSE-32: opening over a response binds the stream's lifecycle to the response" do
    response = fake_response_with_sse_body(FIXTURE)
    Dexpace::SSE::Stream.open(response).each { |_e| nil }
    assert(response.closed?)
  end

  test "SSE-32: opening over a bodyless response fails loudly" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::SSE::Stream.open(fake_response(body: nil))
    end
  end

  test "P7-25: a borrowed source is never closed by the stream" do
    resource = Dexpace::Test::CountingResource.new
    stream = Dexpace::SSE::Stream.borrowing(Dexpace::Test::ByteSource.new(FIXTURE), resource: resource)
    stream.each { |_e| nil }
    stream.close
    assert_equal(0, resource.close_count)
    assert(stream.closed?)
  end

  test "SSE-39: pulling one event does not read ahead into the next" do
    body = Dexpace::Test::CountingBody.new(["data: a\n\n", "data: b\n\n"])
    stream = Dexpace::SSE::Stream.owning(Dexpace::IO::BufferedSource.over(body), resource: body)
    enum = stream.events
    assert_equal(["a"], enum.next.data)
    assert_equal(1, body.yield_count)
  end

  test "SSE-40: the view is lazy and propagates a read failure at the offending pull" do
    source = Dexpace::Test::ByteSource.failing_after("data: a\n\n", Dexpace::StreamError.new("boom"))
    stream = Dexpace::SSE::Stream.owning(source, resource: Dexpace::Test::CountingResource.new)
    enum = stream.events
    assert_equal(["a"], enum.next.data)
    assert_raises(Dexpace::StreamError) { enum.next }
  end

  test "SSE-40: the view reuses one reader instance, so the BOM is consumed once" do
    stream, = stream_over("\xEF\xBB\xBFdata: a\n\ndata: \xEF\xBB\xBFb\n\n")
    parsed = stream.events.to_a
    assert_equal(["a"], parsed.first.data)
    assert_equal(["\u{FEFF}b"], parsed.last.data)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/stream_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::SSE::Stream`, 21 tests.

- [ ] **Step 3: Write `lib/dexpace/sse/stream.rb`**

`include Dexpace::Closeable`; `#initialize_closeable(owned:)` in every constructor path; a private
`#release` calling `@resource.close`. The three factories are `P7-25`'s three names, and **none is
called `.over`**, because `Dexpace::IO::BufferedSource.over` means *borrowing* and a same-named method
with the opposite polarity one namespace away is the kind of name that is wrong in the one way review
does not catch. `Stream.open(response)` raises `Dexpace::InvalidArgumentError` when `response.body` is
`nil` and builds a `Reader` over `response.body.source`.

The drive routine is the whole lifecycle:

```ruby
private def advance
  return nil if closed?          # SSE-27: an in-flight iterator observes the closed state

  event = @reader.next_event
  if event.nil?
    Dexpace.close_quietly(self, onto: nil)   # SSE-24 + SSE-30's swallowing half
    return nil
  end
  event
rescue ::StandardError => error
  Dexpace.close_quietly(self, onto: error)   # SSE-29: release BEFORE the error propagates
  raise
end
```

`#each` with a block drives `#advance` in the `Stream`'s own scope with an `ensure` that closes;
`#events` returns `to_enum(:drive)` over a private `#drive` that holds no resource. **The resource
lives on the `Stream` and never inside either.** `@viewed` is latched before either is built
(`SSE-26`, `SSE-40`). **No `block_given?` guard is written** — verified fact 6.

`SSE-30`'s asymmetry is two call sites into one latch: `Dexpace.close_quietly(self, …)` for the
automatic path and `Closeable#close` for the explicit one, both flipping the same `@closed` flag, so
`SSE-28`'s "even after an automatic release" clause holds by construction rather than by a second flag.

`Dexpace::SSE::StreamStateError < ::StandardError`, `include Dexpace::Error`, is `SSE-26`/`SSE-27`'s
loud failure and lands in `lib/dexpace/sse/stream_state_error.rb` beside `LimitExceededError`.

The YARD on the `SSE-29` path states the **frozen-primary caveat**: `Dexpace.attach_suppressed`
silently no-ops on a frozen primary (`P4-13`), so the release failure is attached for every error the
SDK or a caller normally raises and silently is not for a frozen one.

- [ ] **Step 4: Write the `sig/` mirror, add the requires, run to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/stream_test.rb`
Expected: PASS, 21 runs, 0 failures, 0 errors.

---

## Task 9: `Dexpace::SSE::TypedStream` — the mapper adapter

**Requirement IDs:** `SSE-33`, `SSE-34`, `SSE-35`, `SSE-36`.
**Design:** "`Dexpace::SSE::TypedStream`"; "`R5`"; `P7-23`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/sse/typed_stream.rb`
- Create: `gems/dexpace-core/sig/dexpace/sse/typed_stream.rbs`
- Modify: `gems/dexpace-core/lib/dexpace/sse/stream.rb` (adds `#typed`)
- Test: `gems/dexpace-core/test/dexpace/sse/typed_stream_test.rb`

**Needs:** Tasks 2 and 8.
**Produces:** `Stream#typed(&mapper)`, `TypedStream#each`, `#values`, `#close`, `#closed?`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# SSE-33 (the mapper receives the raw event name and the data lines joined by a single \n, and the
# decoded value is yielded), SSE-34 (the three outcomes), SSE-35 (lazy, per-element decoding), SSE-36
# (a throwing mapper propagates at the pull but releases the resource first).

require_relative "../../test_helper"
require "dexpace"
require "support/sse_doubles"

class DexpaceSSETypedStreamTest < DexpaceTestCase
  test "SSE-33: the mapper receives the data lines joined with a single newline" do
    seen = []
    stream_over("data: line1\ndata: line2\n\n").typed { |name, data| seen << [name, data] }.each { }
    assert_equal([[nil, "line1\nline2"]], seen)
  end

  test "SSE-33: a no-data event gives the mapper the empty string, not nil" do
    seen = []
    stream_over("event: ping\n\n").typed { |name, data| seen << [name, data] }.each { }
    assert_equal([["ping", ""]], seen)
  end

  test "SSE-33: the mapper's decoded value is what the consumer receives" do
    values = stream_over("data: 1\n\ndata: 2\n\n").typed { |_n, d| d.to_i * 10 }.to_a
    assert_equal([10, 20], values)
  end

  test "SSE-33: a mapper returning nil yields nil - nil is a value, not a sentinel" do
    assert_equal([nil], stream_over("data: x\n\n").typed { |_n, _d| nil }.to_a)
  end

  test "SSE-34: SKIP drops the event and advances, never surfacing it" do
    typed = stream_over("data: a\n\ndata: skipme\n\ndata: c\n\n").typed do |_n, d|
      d == "skipme" ? Dexpace::SSE::SKIP : d
    end
    assert_equal(%w[a c], typed.to_a)
  end

  test "SSE-34: DONE ends iteration cleanly, closes the stream, and yields no model for the sentinel" do
    resource = Dexpace::Test::CountingResource.new
    stream, = stream_over("data: a\n\ndata: bye\n\ndata: never\n\n", resource: resource)
    typed = stream.typed { |_n, d| d == "bye" ? Dexpace::SSE::DONE : d }
    assert_equal(%w[a], typed.to_a)
    assert_equal(1, resource.close_count)
  end

  test "SSE-34: events after a DONE sentinel are never decoded" do
    decoded = []
    stream_over("data: a\n\ndata: bye\n\ndata: never\n\n").typed do |_n, d|
      decoded << d
      d == "bye" ? Dexpace::SSE::DONE : d
    end.to_a
    assert_equal(%w[a bye], decoded)
  end

  test "SSE-35: decoding is lazy - one mapper call per pull" do
    calls = 0
    typed = stream_over("data: a\n\ndata: b\n\ndata: c\n\n").typed { |_n, d| calls += 1; d }
    enum = typed.each
    enum.next
    assert_equal(1, calls)
    enum.next
    assert_equal(2, calls)
  end

  test "SSE-35/SSE-39: draining Skips pulls only as many raw events as one element needs" do
    calls = 0
    typed = stream_over("data: s\n\ndata: s\n\ndata: v\n\ndata: v2\n\n").typed do |_n, d|
      calls += 1
      d == "s" ? Dexpace::SSE::SKIP : d
    end
    assert_equal("v", typed.each.next)
    assert_equal(3, calls)   # two skips drained, one value produced; v2 not touched
  end

  test "SSE-36: a mapper that raises propagates at that pull and releases the resource first" do
    resource = Dexpace::Test::CountingResource.new
    stream, = stream_over("data: a\n\ndata: boom\n\n", resource: resource)
    typed = stream.typed { |_n, d| d == "boom" ? raise(::ArgumentError, "nope") : d }
    enum = typed.each
    assert_equal("a", enum.next)
    assert_raises(::ArgumentError) { enum.next }
    assert_equal(1, resource.close_count)
  end

  test "SSE-36: a release failure during a mapper failure is attached as suppressed" do
    resource = Dexpace::Test::CountingResource.new(raise_on_close: ::IOError.new("close failed"))
    stream, = stream_over("data: boom\n\n", resource: resource)
    typed = stream.typed { |_n, _d| raise(::ArgumentError, "nope") }
    error = assert_raises(::ArgumentError) { typed.to_a }
    assert_equal(["close failed"], Dexpace.suppressed(error).map(&:message))
  end

  test "SSE-23: the typed view is not a second closeable - close delegates to the stream" do
    resource = Dexpace::Test::CountingResource.new
    stream, = stream_over("data: a\n\n", resource: resource)
    typed = stream.typed { |_n, d| d }
    typed.close
    typed.close
    assert(stream.closed?)
    assert_equal(1, resource.close_count)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/typed_stream_test.rb`
Expected: fails with `NoMethodError: undefined method 'typed'`, 13 tests.

- [ ] **Step 3: Write `lib/dexpace/sse/typed_stream.rb`**

The join is `event.data.join("\n")`, done **here** and never in the parser, because `SSE-8` requires the
parser keep the raw per-line list. The outcome dispatch is identity, not equality:

```ruby
outcome = @mapper.call(event.event, event.data.join("\n"))
next   if outcome.equal?(Dexpace::SSE::SKIP)     # SSE-34
break  if done!(outcome)                         # SSE-34: close, yield nothing for the sentinel
yielder << outcome                               # SSE-33: the decoded value itself
```

`#close`/`#closed?` delegate to the `Stream`; `TypedStream` includes no `Closeable` and holds no
resource, so `SSE-23`'s exactly-one claim survives the typed layer.

- [ ] **Step 4: Write the `sig/` mirror, add the require, run to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/typed_stream_test.rb`
Expected: PASS, 13 runs, 0 failures, 0 errors.

---

## Task 10: `SSE-37` and `SSE-38`'s prohibitions, asserted by test

**Requirement IDs:** `SSE-37` (the two unscannable prohibitions), `SSE-38`.
**Design:** "`R11` — what the gate does not cover, and what does".

**Files:**
- Create: `gems/dexpace-core/test/dexpace/sse/boundaries_test.rb`

**Needs:** Tasks 7, 8 and 9.
**Produces:** the four negative assertions design §7.2 asks for by name.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# SSE-37 (no built-in done-sentinel, no error-envelope recognition - the two halves the require audit
# cannot scan for, since a sentinel is a string literal and no scanner tells "[DONE]" from any other
# string), SSE-38 (no auto-reconnect, no persisted last-event-id, no reconnect header).
#
# Design section 7.2: these are "satisfied by omission AND asserted by test, since the temptation to
# add them is real". That is why this file exists rather than a comment.

require_relative "../../test_helper"
require "dexpace"
require "support/sse_doubles"

class DexpaceSSEBoundariesTest < DexpaceTestCase
  test "SSE-37: [DONE] is an ordinary data value and does not terminate the stream" do
    events = stream_over("data: [DONE]\n\ndata: after\n\n").events.to_a
    assert_equal([["[DONE]"], ["after"]], events.map(&:data))
  end

  test "SSE-37: an event named 'error' is an ordinary event and raises nothing" do
    events = stream_over("event: error\ndata: {\"message\":\"x\"}\n\n").events.to_a
    assert_equal(1, events.size)
    assert_equal("error", events.first.event)
  end

  test "SSE-37: no core SSE file names a serde constant" do
    # The mechanical half is gates:serde_boundary (Task 11). This is the runtime companion: the SSE
    # namespace defines nothing whose ancestry or constant table reaches Dexpace::Serde.
    Dexpace::SSE.constants.each do |name|
      value = Dexpace::SSE.const_get(name)
      next unless value.is_a?(::Module)

      refute_match(/Serde|JSON/, value.ancestors.map(&:to_s).join(","))
    end
  end

  test "SSE-38: the subsystem constructs no request and holds no transport" do
    # A reconnect would need one of the two. Neither exists, and this asserts the absence rather than
    # describing it.
    refute(Dexpace::SSE::Stream.instance_methods.any? { |m| m.to_s.match?(/reconnect|request/) })
    refute(Dexpace::SSE::Reader.instance_methods.any? { |m| m.to_s.match?(/reconnect|request/) })
  end

  test "SSE-38/SSE-16: a second event's id is absent, so no last-event-id is persisted" do
    events = stream_over("id: 1\ndata: a\n\ndata: b\n\n").events.to_a
    assert_nil(events.last.id)
  end

  test "SSE-38: an exhausted stream stays exhausted and does not reopen" do
    stream = stream_over("data: a\n\n")
    assert_equal(1, stream.events.to_a.size)
    assert(stream.closed?)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails, then passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/boundaries_test.rb`
Expected: all six pass on the first run if Tasks 7–9 are correct. **If any passes for the wrong reason
— a `refute_match` over an empty collection, say — the assertion is strengthened rather than accepted.**
This is the one task in the plan whose tests are expected green immediately, and the step exists to
make that expectation explicit rather than to skip the red phase.

---

## Task 11: `gates:serde_boundary` — `SSE-37`'s mechanism, extended over `lib/dexpace/page/**`

**Requirement IDs:** `SSE-37`. Spec-forced boundary 5 (charter) for the pagination extension.
**Design:** "`R11`".

**Files (if `7b` lands first):**
- Create: `tools/serde_boundary.rb`
- Modify: `tasks/gates.rake`
- Create: `test/tools/serde_boundary_test.rb` and six fixtures under `test/fixtures/serde_boundary/`

**Files (if `7c` landed first):**
- Modify: `tools/serde_boundary.rb` — **one line**

**Needs:** Task 8's files, so the at-least-one-match assertion has something to match.
**Produces:** `bundle exec rake gates:serde_boundary`, wired into the default task.

- [ ] **Step 1: Check whether the tool already exists**

```bash
ls tools/serde_boundary.rb 2>/dev/null && echo EXISTS || echo ABSENT
```

**If EXISTS** — `7c` landed first. Skip to Step 6. Do not write a second tool, a second rake task or a
second fixture set.

- [ ] **Step 2: Write the failing gate test**

Six fixtures, each a file under a scratch guarded path:

| Fixture | Must |
|---|---|
| `requires_json.rb` — `require "json"` | fail, naming `SSE-37` |
| `requires_serde.rb` — `require_relative "../serde/json"` | fail, naming `SSE-37` |
| `names_serde.rb` — a bare `Dexpace::Serde` reference | fail, naming `SSE-37` |
| `names_qualified_json.rb` — `::JSON.parse` | fail — this is the spelling `Dexpace/QualifiedCoreConstant` pushes an author toward, so it is the one a naive scan misses |
| `clean.rb` — neither | pass (the positive control) |
| a `GUARDED` glob matching **zero** files | fail, naming the glob — the assertion that stops a typo from reporting clean forever |

- [ ] **Step 3: Run test to confirm it fails**

Run: `bundle exec ruby -w test/tools/serde_boundary_test.rb`
Expected: fails with `LoadError` / `NameError` on `tools/serde_boundary.rb`, 6 tests.

- [ ] **Step 4: Write `tools/serde_boundary.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# SSE-37: "Core parsing and streaming MUST remain format- and API-agnostic: they MUST hold no
# built-in done-sentinel, no error-envelope recognition, and NO SERIALIZATION DEPENDENCY."
# Design section 7.2 mechanises this as a require audit rather than leaving it to review.
#
# It is a text scan and not a runtime trace, for the same reason phase 0's require audit is one:
# lib/dexpace.rb requires the whole tree explicitly and there is no autoloader to interrogate.
#
# The PENDING list is spec-forced boundary 5 of the phase-7 segmentation design: section 12's
# pagination serde-agnosticism carries NO requirement ID, so the SSE-37 mechanism is extended one
# path wider. Whichever of 7b and 7c lands first writes this tool; the other moves one row.

module SerdeBoundary
  GUARDED = [
    ["gems/dexpace-core/lib/dexpace/sse.rb",      "SSE-37"],
    ["gems/dexpace-core/lib/dexpace/sse/**/*.rb", "SSE-37"],
  ].freeze

  PENDING = [
    ["gems/dexpace-core/lib/dexpace/page/**/*.rb",
     "phase-7 segmentation design, spec-forced boundary 5 (7c moves this into GUARDED)"],
  ].freeze

  FORBIDDEN_REQUIRE = /^\s*require(?:_relative)?\s+["'][^"']*(?:serde|json)/
  FORBIDDEN_CONST   = /(?<![A-Za-z_:])(?:::)?(?:Dexpace::Serde|Serde|JSON)\b/
end
```

The runner asserts, for every `GUARDED` row, that the glob matches **at least one file** — without it,
a glob with a typo scans nothing and reports clean forever, which is the precise way a boundary gate
stops being a gate — then scans each matched file for both patterns and reports every hit with the
requirement ID from the row. It prints each `PENDING` row and its reason on every run, so the row is a
standing reminder rather than a hole.

- [ ] **Step 5: Add `gates:serde_boundary` to `tasks/gates.rake` and wire it into the default task**

Beside phase 0's three zero-dependency gates, blocking, on every matrix row.

- [ ] **Step 6: Move the `sse/**` rows into `GUARDED` (the `7c`-landed-first path)**

If Step 1 said EXISTS, the whole task is: add or move the two `sse/**` rows into `GUARDED`, run the
gate, and confirm it is green. No second tool, no second rake task, no fixtures.

- [ ] **Step 7: Run the gate and the whole suite**

Run: `bundle exec rake gates:serde_boundary && bundle exec rake`
Expected: PASS. The gate's output names the one `PENDING` row (or none, if `7c` has already moved it).

---

## Task 12: `OI-5`'s closure evidence and the register-amendment texts

**Requirement IDs:** none new. `SSE-19`, `SSE-11`, `SSE-2`, `IO-14`, `IO-9` are cited by the texts.
**Design:** "`R4`"; "The findings proposed for the registers".

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/sse.rb` (the YARD sentences)
- Test: `gems/dexpace-core/test/dexpace/sse/documentation_test.rb`
- **No new document.** The four register-amendment texts already live, verbatim and ready to paste, in
  the design's *The findings proposed for the registers* section. This task builds the **code** half of
  `OI-5`'s closure and hands the prose half to a human; writing a second copy of those texts into a
  third file is how a correction ends up applied in one place and stale in another.

**Needs:** Tasks 2 and 3.
**Produces:** the documented divergence `SSE-19` charges for taking its option.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# SSE-19 charges taking its MAY with "documenting the divergence", and OI-5's third obligation is
# that the relationship between phase 3a's ceiling and 7b's cap be "visible from the code and not
# only from a register". A doc-comment test is unusual; it is written because both obligations are
# discharged by prose and prose is exactly what silently disappears in a later refactor.

require_relative "../../test_helper"

class DexpaceSSEDocumentationTest < DexpaceTestCase
  SOURCE = ::File.read(::File.expand_path("../../../lib/dexpace/sse.rb", __dir__))

  test "SSE-19: MAX_LINE_BYTES's YARD names the requirement and the divergence" do
    assert_match(/SSE-19/, SOURCE)
    assert_match(/documented divergence|documenting the divergence/, SOURCE)
  end

  test "OI-5: MAX_LINE_BYTES's YARD names OI-5 and phase 3a's ceiling" do
    assert_match(/OI-5/, SOURCE)
    assert_match(/MAX_MATERIALIZED_BYTES/, SOURCE)
  end

  test "the two caps are documented as chosen rather than derived" do
    assert_match(/chosen, not derived|chosen rather than derived/, SOURCE)
  end

  test "SSE-11's cap is documented as NOT the line cap" do
    assert_match(/not the line cap/i, SOURCE)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails, write the YARD, run to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/sse/documentation_test.rb`
Expected: fails, then PASS, 4 runs.

- [ ] **Step 3: Hand the four register-amendment texts to a human**

**This plan edits no register.** The four texts are already drafted, verbatim and ready to paste, in the
design's *The findings proposed for the registers* section: the `OI-5` amendment (three corrections,
including the false-premise one), the `P3-4` amendment, the appendix-C `SSE-19` finding, the
corpus-navigation finding, the `sse-streaming` note draft, the segmentation-design correction and the
`knowledge-lookup` thirteenth row. The task's deliverable is a note in the handover naming that
section, not an edit.

---

## Task 13: Final wiring, the two regenerated artifacts, and the handover

**Requirement IDs:** `NFR-3`, `NFR-4`, `NFR-11`, `NFR-13` — all phase 0's machinery, exercised.
**Design:** "Module layout"; `P7-27`.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Modify: the committed runtime surface manifest
- Modify: `Steepfile` if a new target relaxation is needed (it should not be)

- [ ] **Step 1: Add the nine `require_relative` lines to `lib/dexpace.rb`**

In dependency order: `sse`, `sse/signal`, `sse/limit_exceeded_error`, `sse/stream_state_error`,
`sse/line_reader`, `sse/event`, `sse/reader`, `sse/stream`, `sse/typed_stream`. Explicit requires, no
autoloader — which is also what keeps `gates:require_allowlist` a text scan.

- [ ] **Step 2: Run the whole gate set**

```bash
bundle exec rake
```

Expected: PASS on every gate, including the new `gates:serde_boundary`, `gates:require_allowlist` (the
allowlist has not grown), `gates:gemspec_audit` (core's runtime dependencies are still empty) and
`gates:clean_bundle` on all four Ruby rows.

- [ ] **Step 3: Regenerate BOTH artifacts, deliberately**

```bash
bundle exec rake surface:regenerate
bundle exec rbs validate && bundle exec steep check
```

**Both, because each catches what the other cannot see.** `Event`'s five `Data`-generated readers,
`Signal`'s two singleton constants and `Stream`'s `Closeable`-supplied `#close`/`#closed?`/`#owned?`
are invisible to `rbs validate` — a method reaching a class through an included module does not appear
in `public_instance_methods(false)` either, which is why phase 3a made `TypedReads` public and why the
manifest must be read after regeneration rather than assumed. `P7-27` lists every name the regeneration
is expected to add; **a name in the diff that is not in `P7-27`'s list is an unintentional export and
stops the task.**

- [ ] **Step 4: Confirm `NFR-11`'s scan is still clean**

No constant outside `Dexpace::` and the fixed stdlib allowlist appears in any `sig/dexpace/sse/*.rbs`.
`7b`'s signatures name `Dexpace::` types, `::String`, `::Integer`, `::Symbol` and `::StandardError`
only.

- [ ] **Step 5: Write the handover note**

Naming: the four register-amendment texts (design, *The findings proposed for the registers*); the
`sse-streaming` note draft for `docs/knowledge/notes/`; the `knowledge-lookup` thirteenth row; the
`P7-20`–`P7-27` ledger rows for consolidation into design §10, with the §10.18 amendment recommendation
for both cap constants; and the deviation-numbering band, so the human filing `7a`, `7b` and `7c`
together can renumber safely in one change if they prefer contiguous numbers.

**The checklist is written at execution time**, per `CLAUDE.md`, and is not a task this plan performs.
It maps one row per requirement ID onto a task number above: `SSE-1`→7, `SSE-2`→3, `SSE-3`–`SSE-10`→5,
`SSE-11`→6, `SSE-12`→5, `SSE-13`–`SSE-18`→7, `SSE-19`→2/3/7 (three rows' worth of evidence in one row,
naming all three), `SSE-20`–`SSE-22`→4, `SSE-23`–`SSE-32`→8, `SSE-33`–`SSE-36`→9, `SSE-37`→10 and 11,
`SSE-38`→10, `SSE-39`→8, `SSE-40`→8, and `SSE-41`→ ⏳ `DEF-8`, no task.

---

## Self-review against the design

Run before handover; each line is a question the design answers and the plan must not have drifted from.

- [ ] Does any task call `#read_line_utf8`? **It must not** (`P7-20`).
- [ ] Does any task create a `Thread::Mutex`? **It must not** — the one lock is `Closeable`'s.
- [ ] Does any task call `downcase`? **It must not** (`P7-24`).
- [ ] Does any task add a `require` outside `dexpace/`? **It must not.**
- [ ] Does any resource live inside an `Enumerator` block or an owning `#each`? **It must not.**
- [ ] Is there a `block_given?` guard anywhere? **There must not be.**
- [ ] Does any encoding assertion use ASCII-only content? **It must not** — such a test passes under
      exactly the bug.
- [ ] Does any cap assertion name a literal rather than the constant? **It must not.**
- [ ] Does `SSE-11`'s row cite `SSE-19`, or the reverse? **Neither** — they are two caps and two rows.
- [ ] Did any task edit a register, a spec file, a design file or the corpus? **None may.**
