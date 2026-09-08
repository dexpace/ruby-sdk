# Phase 3a — I/O Contracts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the byte-streaming layer in `dexpace-core` — one FIFO buffer, one buffered
source/sink pair with typed reads and non-consuming views, and one tee sink that mirrors a bounded
tap without ever altering the wire body — satisfying the 34 implemented IDs of `IO-1`–`IO-42`.

**Architecture:** Two public modules supply the whole vocabulary over one private hook each —
`TypedReads` over `#fill(min_bytes)`, `TypedWrites` over `#deliver(string)` — and four classes
supply those hooks. Every buffered object is an `Array` of frozen BINARY chunks behind a moving head
offset, so draining is O(1) amortised and no view can see a chunk mutated behind its back. A view is
a `BufferedSource` in view mode holding a pin into its parent, not a new public type. The only
synchronised state in the whole sub-phase is `Dexpace::Closeable`'s close latch, read once per public
entry point.

**Tech Stack:** Ruby 3.2–4.0 (development on 4.0.6), no runtime dependencies, Minitest, RBS + Steep,
RuboCop with phase 0's five custom cops plus phase 2's sixth which this phase extends, SimpleCov,
YARD.

**Spec:** `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md`, under the charter
`docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md`.

## Global Constraints

Every task's requirements implicitly include this section. Values are copied verbatim from the design
and the governing documents.

- **`dexpace-core` gains no dependency and no allowlist entry.** The gemspec keeps zero
  `add_dependency` lines (`SEAM-1`, `NFR-1`). **This phase adds no `require` of any kind beyond
  `require_relative`**: `::IO`, `::String`, `::Encoding`, `::Thread::Mutex`, `::Enumerator` and
  `::Float` are core Ruby. `stringio` is already on phase 0's twelve-name allowlist and this phase
  uses it in `test/` only.
- **`IO-40` forbids a clock.** No method in 3a takes a timeout, a deadline or a `Cancellation`, and
  no task reaches for `DEF-28`'s `deadline:` keyword. The only blocking call in the sub-phase is the
  upstream's own `#readpartial`/`#read` inside `#fill`.
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`;
  `docs/knowledge/notes/formatting-and-tooling.md`). No `# typed:` sigil anywhere.
- **Banned, and each is a blocking cop:** `Time.parse`/`Date.parse`/`DateTime.parse`;
  `URI::DEFAULT_PARSER` and the `URI.parse`/`URI.join`/`URI.split` family; any argument to
  `downcase`/`upcase`/`capitalize`/`swapcase` and `casecmp?`; `Timeout.timeout`, `Thread#raise`,
  `Thread#kill`.
- **Inside `module Dexpace`, anywhere, write `::Thread`, `::Queue`, `::Mutex`, `::SizedQueue`,
  `::ConditionVariable`, `::JSON` and `::IO`** — never the bare name. Task 1 ships the cop that
  enforces it, and it is deliberately first so `lib/dexpace/io.rb` is written under it from its
  first line.
- **Core never writes `is_a?(IO)`.** Every caller-supplied stream is checked with `respond_to?`,
  which is `api-design/88e6bf12`'s "narrowest duck-typed interface it actually uses" and is the
  mitigation that matters — the cop cannot make a nominal type test correct, only stop one being
  written.
- **Bytes are always `Encoding::BINARY`.** Every chunk stored, and every `String` returned by
  `#read`, `#readpartial`, `#read_exactly`, `#snapshot` and `#each`, is BINARY. The ingress idiom is
  **keep the chunk when it is both frozen and already BINARY, `chunk.b` otherwise** —
  `force_encoding` appears nowhere on the ingress path, because it raises `FrozenError` on a frozen
  `String` even when the target encoding is already that string's own.
- **Every encoding test uses non-ASCII bytes.** Appending an ASCII-only UTF-8 `String` to a BINARY
  one leaves it BINARY while a non-ASCII one silently retags the result to UTF-8, so an ASCII-only
  fixture passes under exactly the bug.
- **A `Thread::Mutex` is held across a flag flip and across nothing else.** Never across a `#fill`,
  a read, a drain, a `#release` or a `#close`. Ruby's `Mutex` is non-reentrant and per-fiber-owned.
- **Two error vocabularies, and no third.** `Dexpace::InvalidArgumentError` (phase 1's) for a caller
  mistake in an argument; `Dexpace::EndOfStreamError` for end of stream; `Dexpace::StreamError` for a
  stream-contract violation; `Dexpace::ClosedError` (phase 2's) for use after close.
  **`Dexpace::IOError` and `Dexpace::EOFError` are never defined**, for phase 1's
  `Dexpace::ArgumentError` reason.
- **Every count and offset beyond the first positional subject is a keyword** (P3-9). The four
  host-native bridge methods are the stated exception and keep Ruby's positional signatures exactly:
  `#read(length = nil, outbuf = nil)`, `#readpartial(maxlen, outbuf = nil)`, `#getbyte`,
  `#write(*strings)`.
- **Formatting:** double quotes, 2-space indent, **100 columns**, `consistent_comma` trailing
  commas, leading-dot chains, `MethodLength: 25` with `CountAsOne`, `ParameterLists: 4`,
  `BlockNesting: 3`.
- **Tests:** Minitest only, `FooTest < DexpaceTestCase`, `test "..." do` blocks, `test/` mirroring
  `lib/` one file per file, `assert_equal(expected, actual)` in that order, every test passing alone
  and in any order, the seed never overridden. Each test file's header comment names the requirement
  IDs it exercises. **Visibility is asserted with `respond_to?`, never `assert_predicate`** — phase
  1's finding, that Minitest sends past `private` on the 3.2 floor.
- **Every public constant gets three artifacts in the same task**: the implementation, a YARD block
  that explains *why* and never restates a type, and an `.rbs` mirror at the same path under `sig/`.
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
bundle exec rake surface:regenerate                                 # deliberate; Task 15 only
```

### What was verified during planning, and how to re-verify it

**Every `ruby` fence in this document was extracted and run**, not a prototype it was transcribed
from. The gem tree was built on top of stand-ins for phase 0's `DexpaceTestCase` (with its
`#sample(count:, seed:)` and its `Warning.warn` override) and phase 1's `Dexpace::Error` and
`InvalidArgumentError`, plus phase 2's `SeamError`, `ClosedError` and the `Closeable` this phase
modifies. The result, identical on **3.2.11, 3.4.10 and 4.0.6** and warning-free under `ruby -w`
with `RUBYOPT=-W:deprecated`:

```
207 runs, 826 assertions, 0 failures, 0 errors, 0 skips   # 830 assertions on 4.0.6
```

The run count is identical on all three and identical across five random seeds (1, 7, 12345, 99991,
424242); stderr was empty on every row. The assertion count differs on 4.0.6 for phase 2's stated
reason — 3.2, 3.3 and 3.4 resolve Minitest 5.x and 4.0 resolves 6.0.0, and the two count some
`assert_operator`/`refute_operator` calls differently. Task 1's cop was run separately through phase
0's verbatim `CopCase` harness on **RuboCop 1.90.0**: `18 runs, 52 assertions, 0 failures`. The
signatures in `sig/` were checked with `rbs 4.2.0`: `rbs -I sig validate` exits 0.

**The guard that had to be run red was run red.** Task 2's change is a one-line behaviour change with
no signature change, so `gates:sig_diff` cannot see it and only one assertion distinguishes it from
phase 2's version. That assertion was run against phase 2's unsynchronised reader on all three
interpreters:

| Fix reverted | Guard | What it says |
|---|---|---|
| `Closeable#closed?` reads `@dexpace_closed` directly instead of inside `@dexpace_close_mutex.synchronize` | `closeable_test.rb`, "closed? acquires the close mutex" | `ThreadError expected but nothing was raised` — on 3.2.11, 3.4.10 and 4.0.6 alike |

**Tasks 5 through 9 build one file, and the ladder was run.** `typed_reads.rb` is assembled in five
steps; each stage was written out and run against the finished suite, so the sequence is a real TDD
ladder rather than an assertion that it is one:

| After task | `typed_reads_test.rb` |
|---|---|
| 5 | 65 runs, 36 assertions, **10 failures, 45 errors** |
| 6 | 65 runs, 63 assertions, **4 failures, 36 errors** |
| 7 | 65 runs, 122 assertions, **4 failures, 28 errors** |
| 8 | 65 runs, 141 assertions, **1 failure, 16 errors** |
| 9 | 65 runs, 233 assertions, **0 failures, 0 errors** |

The five fragments reconstruct the shipped file byte for byte, which was checked rather than assumed.

**One thing that run was not.** It is not the seventeen gates: no Steep, SimpleCov or YARD is
installed here, and the RuboCop and RBS versions above are not the ones `VERSIONS` will pin. Task 1
Step 5 and Task 15 Step 6 are therefore real checks, not formalities.

### The six verified Ruby facts, re-verified for this plan

Run on 3.2.11, 3.4.10 and 4.0.6 through `mise exec ruby@<v>` on 2026-09-08. Each names the task it
constrains.

| Fact | Result | Constrains |
|---|---|---|
| `IO.copy_stream` drives a duck-typed source through `readpartial(16384, buf)` with **one buffer object reused on every call**, and expects it overwritten; with no `#readpartial` it falls back to `read(16384, buf)` identically | `ids.uniq.size == 1`, payload intact, all three | Task 8. `#read`/`#readpartial` **overwrite**; `#read_into` **appends** |
| `IO.copy_stream` terminates cleanly on an `::EOFError` **subclass** raised by a duck-typed `#readpartial` | payload intact, all three | Task 3. Without `EndOfStreamError < ::EOFError` every phase-8 streaming upload fails |
| `force_encoding` on a frozen `String` raises `FrozenError` **even when the target encoding is already the string's own**; `String#b` always returns a new unfrozen object; `["chunk"].each` under `# frozen_string_literal: true` yields **frozen** strings | all three | Tasks 5 and 10, every ingress site |
| BINARY `<<` non-ASCII UTF-8 silently retags the result to **UTF-8**; BINARY `<<` ASCII-only stays BINARY | all three | every encoding test, and `#read_into`'s eager rejection of a non-BINARY `dest` |
| A `Thread::Mutex` held across a fiber suspension raises `ThreadError` for a second fiber of the same thread; nested `synchronize` in one fiber raises `ThreadError: deadlock; recursive locking` | all three | Tasks 2 and 10. One `synchronize` per public entry point, never nested, never held across a read |
| `StringIO#read(n, buf)`'s destination encoding changed at exactly Ruby 3.4 — **ASCII-8BIT on 3.2.11, UTF-8 on 3.4.10 and 4.0.6** — while `::IO#read` preserves the destination's tag on all three; both preserve a **BINARY** destination on all three | measured both ways | Tasks 8 and 10, and P3-13 |

Supporting facts, recorded because the plan would otherwise assume them: `readpartial` raises
`EOFError` where `read(n)` returns `nil`; `read()` with no count returns `""` at EOF; `read(0)` and
`readpartial(0)` return `""` even when exhausted; reading a closed `IO`/`StringIO` raises `IOError`;
an `Enumerator` `#each`-with-`break` runs its `ensure` while `#next`-then-abandon does not, after two
`GC.start`; `Encoding.find` raises `ArgumentError` for an unknown name; `byteslice` of a frozen
`String` returns an **unfrozen** one; `String#[]` with a `Range` is character-based; `IO#write`
returns the full count for a 1 MB blocking write.

### Decisions this plan makes, which the design left to it

The design's "Open questions for 3a's own plan" names three. All three are answered here, and six
further choices are recorded so they are not re-derived at a task boundary.

**1. The chunk-store compaction policy.** The store is an `Array` of chunks plus `@dexpace_head`, a
byte offset into `@dexpace_chunks.first`.

- **A fully consumed chunk is `shift`ed off the front, immediately, in `#advance_head`.** O(1).
- **A partially consumed head chunk is never `byteslice`d to compact it**; `@dexpace_head` moves
  instead. Compacting would copy the unconsumed tail a second time on every partial read, which is
  the invariant's whole point.
- **Every chunk in the store is a frozen BINARY `String`**, established once in `#store_append`.

That satisfies both invariants the design fixed:

- *No byte is copied more than once on the fill path.* `#store_append` keeps a chunk that is already
  frozen and BINARY with **no copy at all** — which is the ordinary Rack shape — and copies exactly
  once otherwise. The upstream's own return is deliberately **not** frozen in place: a duck-typed
  `#readpartial` that reuses one buffer would break if it were, so that path pays the one copy. The
  view fill path hands `#store_append` a window copy it has just made and therefore owns, so it
  freezes that copy at the call site rather than paying a second one.
- *The parent's own cursor is the retention floor, and no pin raises it.* `#advance_head` drops what
  the parent has itself consumed and keeps what it has not, with no reference to any live view — the
  design's rule exactly, and the reason the store needs no pin bookkeeping for retention. A view
  whose next byte the parent's cursor has already passed raises `Dexpace::ClosedError` rather than
  reading somewhere else (P3-5). `@dexpace_views` therefore serves `IO-22`/`IO-38`'s invalidation on
  close and nothing else (`OI-4`).

**2. `#each`'s chunk granularity: whatever the upstream returned.** `#store_take_chunk` hands back the
whole remaining head chunk, so `BufferedSource.over(body)` yields exactly the boundaries `body#each`
yielded — which is what `BODY-17`'s byte-exact mirroring needs to mean what it says, and it is
asserted in Task 10 rather than described. A `wrapping` source has no caller chunking to preserve and
yields whatever `#readpartial` returned. A caller that has already consumed part of the head chunk
gets the remainder as `#each`'s first chunk; that is honest and it is tested.

**3. The one allocating `IO-9` test runs on every matrix row.** It is in Task 12. Measured cost, once
per run per row, on the three interpreters:

| Ruby | elapsed | peak RSS |
|---|---|---|
| 3.2.11 | 0.0002 s | 19.1 MB |
| 3.4.10 | 0.0006 s | 15.7 MB |
| 4.0.6 | 0.0000 s | 16.7 MB |

Cheaper than the design budgeted for, because the buffer is built from a zero-filled `String` whose
pages Linux maps lazily and the guard reads `#bytesize` without touching them. `#bytesize` is
genuinely `MAX_MATERIALIZED_BYTES + 1` and `#snapshot` genuinely refuses, so the guard is exercised
for real. Skipping it on some rows would leave the ceiling's only size-based assertion untested
exactly where it might first break.

**4. `BufferedSink` stages and pushes in the same call.** `#deliver` appends to `@dexpace_staged` and
calls `#emit`, and `#emit` clears the staging buffer in an `ensure`. So the staging buffer exists —
it is what `IO-18`'s "staging buffer -> underlying stream" names — and it is empty between calls, so
a failed underlying write leaves nothing to prepend. **`#emit` never calls the underlying `#flush`
and `#flush` always does**, which is what makes `IO-18`'s distinction real here rather than notional,
and it needs no invented flush threshold that phase 5 would then have to configure.

**5. `IO-42`'s close check sits between `IO-3`'s validation and `IO-2`'s zero-count return.** The
design numbers the ordering inside `#read_into` as `IO-3`, then `IO-2`, then serve, and is silent on
where the close check goes. It goes second: `IO-42`'s MUST covers *every* read attempt including a
zero-count one, while `IO-2`'s clause is a statement about an **open** source's exhaustion and cannot
swallow it. `IO-3` stays first, because it must run "before any I/O occurs" and the close check is
not I/O.

**6. The cop must not flag its own phase.** `module Dexpace; module IO` is a `const` node named `IO`
with no namespace inside `module Dexpace`, so the cop as the design states it rejects
`lib/dexpace/io.rb` — the very file that creates the hazard. Task 1 adds a `#definition_name?` guard
that skips a `const` that is a `module`/`class` node's own identifier. Phase 2 never met this because
nothing declares `module Dexpace::Async::Thread`. **This is the single most likely way to ship Task 1
broken**, so the accepted table carries two rows for it.

**7. Task order, where the design called it convenience rather than dependency.** `BufferedSource`
(Task 10) comes **before** `TypedWrites` (Task 11), because it needs only `TypedReads` and it is what
makes the `IO.copy_stream` bridge story and the `IO-37`/`IO-38` tests reachable at the earliest point.
`Buffer` (Task 12) comes **after** `TypedWrites`, which it includes, and **before** `BufferedSink`
(Task 13) and `TeeSink` (Task 14), because `TeeSink`'s tap *is* a `Buffer` and `BufferedSink`'s
`IO-4` test reads best against a real one. `TypedWrites`' own `#write_from` is written against an
in-test `TypedReads` includer with a `#bytesize`, so Task 11 does not wait for Task 12.

**8. `BufferedSource.of_bytes` builds through the `#each` path, and `#initialize` takes four
keywords.** A byte array already *is* a canonical body representation (§10.2), so `.of_bytes` takes
its independent copy, freezes it, and hands it on as a one-chunk `#each`-shaped body rather than
seeding the store through a fifth construction keyword. Two things fall out. `#store_append` keeps an
already-frozen BINARY chunk without copying it again, so `.of_bytes` costs **one** copy rather than
two. And `#initialize` is left with four keywords — `upstream:`, `owns_upstream:`, `chunked:` and
`view:`, the last a private frozen `View` `Data` folding the three facts that make a source a view —
which is what phase 0's `Metrics/ParameterLists: 4` allows. The seven-keyword shape this replaced was
one cop finding, not a design decision; `owns_upstream:` stays an explicit factory-named argument
because `IO-6` and P3-11 make ownership a construction-time fact the factory names, and `View` is
`private_constant`, so neither the surface manifest nor the `sig` diff sees a new name.

**9. `TypedReads` and `TypedWrites` each carry their own `#validate_count!` and `#resolve_encoding`.**
Fifteen duplicated lines, deliberately: each module must stand alone, because a third-party sink that
supplies `#deliver` gets the whole write vocabulary by including one module and nothing else. Folding
them into a shared private module would add a ninth `lib/` file the design's layout does not have.

---

## File Structure

Grouped by responsibility. Every file below is created by exactly one task, and every `lib/` file
gets its `sig/` mirror and its `test/` mirror **in that same task** — phase 1's rule. Paths are
relative to `gems/dexpace-core/` unless stated otherwise.

**The gate (Task 1).** `.rubocop/cops/dexpace/qualified_core_constant.rb`, `.rubocop.yml` and
`.rubocop/test/cops_test.rb`, all at the repository root. First, so `lib/dexpace/io.rb` is written
under the rule from its first line — exactly as phase 2 put its cop before Task 4.

**The phase-2 change (Task 2).** `lib/dexpace/closeable.rb`, one line, and
`test/dexpace/closeable_test.rb`. A prerequisite of every close test that follows.

**The failure types (Task 3).** `lib/dexpace/error/stream_error.rb`,
`lib/dexpace/error/end_of_stream_error.rb`. Third, because every later task raises through them.

**The namespace and the ceiling (Task 4).** `lib/dexpace/io.rb` and `sig/dexpace/io.rbs`, the latter
also carrying the three RBS interfaces. Immediately after the cop, so the pairing is visible.

**The read vocabulary (Tasks 5–9).** `lib/dexpace/io/typed_reads.rb`, built in five steps — the
primitive, the typed reads with the ceiling, the line machine, the host-native bridge, the views —
against one in-test includer that supplies `#fill`. Split because it is the largest unit in the
sub-phase and a reviewer can reject the line machine while approving the primitive.

**The reader (Task 10).** `lib/dexpace/io/buffered_source.rb`, with `test/support/fake_chunked.rb`.

**The write vocabulary (Task 11).** `lib/dexpace/io/typed_writes.rb`, with
`test/support/fake_source.rb`.

**The FIFO (Task 12).** `lib/dexpace/io/buffer.rb`.

**The writer and the mirror (Tasks 13–14).** `lib/dexpace/io/buffered_sink.rb` with
`test/support/fake_sink.rb`, then `lib/dexpace/io/tee_sink.rb`.

**Wiring and closing (Task 15).** `lib/dexpace.rb` and `sig/dexpace.rbs` (verified rather than
modified, since each task adds its own `require_relative`), then the repository-root
`test/fixtures/surface/dexpace-core.txt`, the RBS baseline, and the checklist.

**Nine new `lib/` files — two error classes and seven under `Dexpace::IO` — with nine `sig/`
mirrors, nine `test/` mirrors, three test-support files, and two modified files that already exist.**

---
## Task 1: `Dexpace/QualifiedCoreConstant` gains `IO` and the one-segment watch

**Requirement IDs:** none directly; it mechanises deviation **P3-7** and protects every file inside
`module Dexpace` from a nominal type test that is silently false. **Design:** "R1 — the
`Dexpace::IO` shadowing gate".

**Files:**
- Modify: `.rubocop/cops/dexpace/qualified_core_constant.rb` (repository root)
- Modify: `.rubocop.yml` (the cop's `Include:`), `.rubocop/test/cops_test.rb`
- Test: `.rubocop/test/cops_test.rb`

**Interfaces:**
- Consumes: phase 0's `.rubocop/test/cop_case.rb` harness — `#assert_offense(cop_class, source,
  message_fragment)` and `#assert_no_offense(cop_class, source)` — and phase 2's cop, which already
  defines `SHADOWED`, `WATCHED`, `#on_const`, `#watched_namespace` and `#lexical_path`.
- Produces: a `RuboCop::Cop::Dexpace::QualifiedCoreConstant` that is blocking over
  `gems/*/lib/**/*.rb` from Task 4 onward.

**Why first.** The hazard this guards is created by Task 4. Landing the cop before it means
`lib/dexpace/io.rb` and everything after is written under the rule rather than retrofitted to it —
the same reason phase 2 put its cop before Task 4.

- [ ] **Step 1: Add the new cases to phase 0's data-driven suite**

Eight rejected sources and eight accepted ones, appended to the `REJECTED` and `ACCEPTED` tables
`.rubocop/test/cops_test.rb` already drives. They are shown here as a standalone class so this fence
runs on its own; in the repository the two arrays are appended to the existing tables and the
generated-method loop at the bottom already exists.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "cop_case"

# The rows phase 3a adds to phase 0's data-driven suite. In the repository these are appended to
# the existing REJECTED and ACCEPTED tables; here they stand alone so the addition can be run.
class QualifiedCoreConstantIOTest < CopCase
  D = RuboCop::Cop::Dexpace
  HEADER = "# frozen_string_literal: true\n# SPDX-License-Identifier: MIT\n\n"

  REJECTED = [
    # Phase 3a: Dexpace::IO is defined by core itself, so this is live from the first require.
    [D::QualifiedCoreConstant, "#{HEADER}module Dexpace\n  IO.pipe\nend\n", "`::IO`"],
    [D::QualifiedCoreConstant,
     "#{HEADER}module Dexpace\n  module IO\n    x.is_a?(IO)\n  end\nend\n", "`::IO`"],
    [D::QualifiedCoreConstant,
     "#{HEADER}module Dexpace\n  module Http\n    x.is_a?(IO)\n  end\nend\n", "`::IO`"],
    [D::QualifiedCoreConstant, "#{HEADER}module Dexpace::Async\n  IO.pipe\nend\n", "`::IO`"],
    # Phase 2's six, still rejected under the widened one-segment watch.
    [D::QualifiedCoreConstant, "#{HEADER}module Dexpace\n  module Async\n    Thread.new\n  end\n" \
                               "end\n", "`::Thread`"],
    [D::QualifiedCoreConstant, "#{HEADER}module Dexpace\n  module Serde\n    JSON.generate(x)\n" \
                               "  end\nend\n", "`::JSON`"],
    # The widening itself: a bare Mutex anywhere inside module Dexpace, not only in the two
    # namespaces phase 2 watched.
    [D::QualifiedCoreConstant, "#{HEADER}module Dexpace\n  Mutex.new\nend\n", "`::Mutex`"],
    [D::QualifiedCoreConstant, "#{HEADER}module Dexpace\n  module Http\n    Queue.new\n  end\n" \
                               "end\n", "`::Queue`"],
  ].freeze

  # The accepted half is what proves the cop does not simply reject every occurrence of the name --
  # which is exactly what phase 2's cop did before its namespace check existed.
  ACCEPTED = [
    [D::QualifiedCoreConstant, "#{HEADER}module Dexpace\n  ::IO.pipe\nend\n"],
    [D::QualifiedCoreConstant,
     "#{HEADER}module Dexpace\n  module IO\n    x.is_a?(::IO)\n  end\nend\n"],
    [D::QualifiedCoreConstant,
     "#{HEADER}module Dexpace\n  module Http\n    ::IO.pipe\n  end\nend\n"],
    [D::QualifiedCoreConstant, "#{HEADER}module Dexpace::Async\n  ::IO.pipe\nend\n"],
    # No enclosing module at all.
    [D::QualifiedCoreConstant, "#{HEADER}IO.pipe\n"],
    # An unrelated namespace: nothing named Elsewhere::IO exists.
    [D::QualifiedCoreConstant, "#{HEADER}module Elsewhere\n  IO.pipe\nend\n"],
    # File, StringIO and Tempfile are deliberately NOT in SHADOWED: no Dexpace:: constant of those
    # names exists, so a rule covering them would only flag correct code.
    [D::QualifiedCoreConstant, "#{HEADER}module Dexpace\n  File.read(path)\n  StringIO.new\n" \
                               "  Tempfile.create\nend\n"],
    # Written out in full.
    [D::QualifiedCoreConstant, "#{HEADER}module Dexpace\n  Dexpace::IO::Buffer.new\nend\n"],
    # THE definition site. `module Dexpace; module IO` declares the shadowing constant rather than
    # referring to Ruby's, so lib/dexpace/io.rb -- the file that creates the hazard -- is not
    # itself an offense. Without this row the cop rejects the phase that ships it.
    [D::QualifiedCoreConstant, "#{HEADER}module Dexpace\n  module IO\n    X = 1\n  end\nend\n"],
    [D::QualifiedCoreConstant, "#{HEADER}module Dexpace\n  module IO\n    class Buffer\n" \
                               "    end\n  end\nend\n"],
  ].freeze

  REJECTED.each_with_index do |(cop, source, fragment), index|
    test "rejected #{index}: #{source.lines.last.strip}" do
      assert_offense(cop, source, fragment)
    end
  end

  ACCEPTED.each_with_index do |(cop, source), index|
    test "accepted #{index}: #{source.lines[3].to_s.strip}" do
      assert_no_offense(cop, source)
    end
  end
end
```

**The accepted half is what proves the cop does not simply reject every occurrence of the name** —
which is exactly what phase 2's cop did before its namespace check existed. Two of those rows are
new and load-bearing: `module Dexpace; module IO` **declares** the shadowing constant rather than
referring to Ruby's, so without the `#definition_name?` guard in Step 3 the cop rejects Task 4, the
very file that creates the hazard.

- [ ] **Step 2: Run the cop suite to confirm it fails**

Run: `bundle exec rake cops:test`
Expected: FAIL — the four `IO` rejections produce no offense (`IO` is not yet in `SHADOWED`), the two
widened-watch rejections produce none (`Dexpace` alone is not yet watched), and the two definition-site
rows produce an offense they must not.

- [ ] **Step 3: Rewrite `.rubocop/cops/dexpace/qualified_core_constant.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # Inside `module Dexpace`, anywhere, a bare `Thread`, `Queue`, `Mutex`, `SizedQueue`,
      # `ConditionVariable`, `JSON` or `IO` is a silent time bomb: it resolves to Ruby's class
      # until the `Dexpace::` constant that shadows it is defined, and to that constant
      # afterwards.
      #
      # Phase 2 verified the adapter-gem half on 3.2.11 and 4.0.6: a bare `Thread` inside
      # `module Dexpace; module Async` is `Thread` before `dexpace-async-thread` is required and
      # `Dexpace::Async::Thread` after, and core's own suite never requires that gem.
      #
      # Phase 3a adds `IO`, and it is worse, because `Dexpace::IO` is defined by CORE. Verified on
      # 3.2.11, 3.4.10 and 4.0.6: inside `module Dexpace`, `x.is_a?(IO)` and `IO === x` are
      # silently `false` for a real `::IO`, and a `case/when IO` falls through -- while a bare
      # `IO.pipe` is a loud NoMethodError. The silent case is exactly the shape design §3.1 reaches
      # for, and `Response#body_string`, which phase 3b adds under lib/dexpace/http/, is the
      # counter-example that forbids scoping this rule to lib/dexpace/io/**.
      #
      # The standing rule, for every later phase: a constant joins SHADOWED in the same change
      # that creates the `Dexpace::` constant which shadows it -- never earlier, never later.
      # `File`, `StringIO` and `Tempfile` are deliberately absent: no `Dexpace::` constant of those
      # names exists, a bare `File` inside `module Dexpace` resolves to `::File` (verified), and a
      # rule guarding nothing only flags correct code.
      #
      # Scoped by `Include:` in .rubocop.yml to gems/*/lib/**/*.rb -- every gem, because an
      # adapter gem also writes inside `module Dexpace`. test/** is deliberately left out: a test
      # file's classes are top level, not inside `module Dexpace`, so the lexical check below
      # would find nothing there.
      #
      # The enclosing namespace is checked here rather than left to `Include:`. Phase 0's cop
      # harness runs a bare Commissioner over a fixed path with a Config carrying only
      # TargetRubyVersion, so no `Include:` ever applies to a cop under test -- a cop that relied
      # on path scoping would flag its own accepted case and the suite would say so.
      #
      # @example
      #   # bad -- inside module Dexpace
      #   IO.pipe
      #
      #   # good
      #   ::IO.pipe
      #
      #   # good -- a different namespace; nothing named Elsewhere::IO exists
      #   IO.pipe
      class QualifiedCoreConstant < RuboCop::Cop::Base
        MSG = "Write `::%<name>s` here: a bare `%<name>s` inside %<namespace>s resolves to the " \
              "shadowing `Dexpace::` constant instead of Ruby's."

        SHADOWED = %w[Thread Queue Mutex SizedQueue ConditionVariable JSON IO].freeze

        # One segment, which subsumes phase 2's two: the rule is now "inside `module Dexpace`,
        # anywhere". Phase 2 deliberately kept ONE SHADOWED list for both namespaces rather than
        # one list each, and widening the watch rather than adding a per-constant scope keeps that
        # decision intact. The cost is one `::` on every `::Thread::Mutex` core already writes in
        # that form.
        WATCHED = [%w[Dexpace]].freeze

        def on_const(node)
          return if node.namespace # already qualified: `A::IO` or `::IO`
          return if definition_name?(node)
          return unless SHADOWED.include?(node.short_name.to_s)

          namespace = watched_namespace(node)
          return if namespace.nil?

          add_offense(node, message: format(MSG, name: node.short_name, namespace: namespace))
        end

        private

        # `module Dexpace; module IO` DECLARES the shadowing constant; it does not refer to Ruby's.
        # Without this, the cop flags lib/dexpace/io.rb -- the very file that creates the hazard
        # the rule exists to guard. Phase 2 never met this because no file declares
        # `module Dexpace::Async::Thread`.
        def definition_name?(node)
          parent = node.parent
          return false if parent.nil?
          return false unless parent.module_type? || parent.class_type?

          parent.identifier.equal?(node)
        end

        # @return [String, nil] the watched namespace this node is lexically inside, or nil
        def watched_namespace(node)
          path = lexical_path(node)
          watched = WATCHED.find do |segments|
            path.each_cons(segments.length).any? { |window| window == segments }
          end
          watched&.join("::")
        end

        # Outermost-first, with a compact `module A::B` split into its segments, so that both
        # `module Dexpace; module IO` and `module Dexpace::IO` read the same.
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

Three changes from phase 2's version, and nothing else moves. `SHADOWED` gains exactly `IO` — not
`File`, `StringIO` or `Tempfile`, because no `Dexpace::` constant of those names exists and a rule
guarding nothing only flags correct code. `WATCHED` becomes the single one-segment path
`%w[Dexpace]`, which subsumes phase 2's two and keeps its deliberate choice of **one** `SHADOWED`
list for all namespaces rather than one list each. And `#definition_name?` is new.

- [ ] **Step 4: Widen the cop's `Include:` in `.rubocop.yml`**

```yaml
# Design §9 Addendum A1 (phase 2), widened by phase 3a's P3-7: a bare Thread/Queue/Mutex/JSON/IO
# inside module Dexpace resolves to the shadowing Dexpace:: constant. Every gem, because an adapter
# gem also writes inside module Dexpace. test/** is deliberately absent: a test file's classes are
# top level, so the cop's own lexical check would find nothing there.
Dexpace/QualifiedCoreConstant:
  Enabled: true
  Include:
    - "gems/*/lib/**/*.rb"
```

This **replaces** phase 2's two-path `Include:`; it does not add a third entry.

- [ ] **Step 5: Run the cop suite to confirm it passes**

Run: `bundle exec rake cops:test`
Expected: PASS, with each rejected source producing exactly one offense naming the constant and the
namespace, and each accepted source producing none. Verified through phase 0's verbatim `CopCase`
harness on RuboCop 1.90.0: **18 runs, 52 assertions, 0 failures**. `RuboCop::Cop::Base#on_const`,
`ConstNode#namespace`, `ConstNode#short_name`, `Node#each_ancestor`, `Node#parent`,
`ModuleNode`/`ClassNode#identifier` and `Node#module_type?`/`#class_type?` are long-stable
rubocop-ast API, but phase 0 pins whatever version `VERSIONS` names and that pin is not 1.90.0 by
construction. **If the installed RuboCop's AST API differs, fix the cop against that version — do not
weaken a case.**

- [ ] **Step 6: Run RuboCop over the repository**

Run: `bundle exec rubocop --fail-level=convention --only Dexpace/QualifiedCoreConstant`
Expected: clean. The widened `Include:` now reaches phase 1's and phase 2's `lib/` trees, which
already write `::Thread::Mutex` and `::Thread::Queue` in that form — if anything is reported there,
qualify it; that is the one-`::` cost P3-7 names. **Scoped to this cop deliberately**: an unscoped
run over the repository is not clean today and was not clean before this phase, for reasons that
belong to phase 0's cop configuration rather than to any one phase's code (`OI-6`, and Task 15
Step 5 states the measured list). Widening a watch must not be blocked on, or become the excuse for,
relaxing four metric cops for everyone.

---

## Task 2: `Dexpace::Closeable#closed?` reads the latch under the close mutex

**Requirement IDs:** `IO-38` — "the CLOSE state of a source/buffer MUST be observable across threads
to the slices derived from it, so that a close on one thread reliably invalidates a slice being read
on another (no torn or stale reads)". **Design:** "The one change 3a makes to a phase-2 constant";
deviation **P3-6**.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/closeable.rb` (one method body)
- Test: `gems/dexpace-core/test/dexpace/closeable_test.rb`
- **Not** modified: `gems/dexpace-core/sig/dexpace/closeable.rbs`. `#closed?` keeps its signature
  `() -> bool` and its public visibility and its arity, so this is a behaviour change with no
  signature change — which is exactly why `gates:sig_diff` cannot see it and why Step 1's assertion
  carries the weight.

**Interfaces:**
- Consumes: phase 2's `Dexpace::Closeable`, unchanged in every other respect.
- Produces: the same `#initialize_closeable(owned:)`, `#owned?`, `#closed?`, `#close` and private
  `#release`. Every task from 10 onward depends on `#closed?` acquiring the mutex.

**Do not** change `Closeable`'s ancestry, `#initialize_closeable`'s signature, `#owned?`, or
`#close`'s structure. `#close` already flips the latch under the mutex and holds it across the flip
only; `#owned?` reads a frozen value set at construction and stays unsynchronised.

- [ ] **Step 1: Add the three new tests to phase 2's suite**

Phase 2's tests are re-run **unchanged**; the last three in this file are what Task 2 adds.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"

# Phase 2's suite, plus the three assertions phase 3a's P3-6 adds for IO-38.
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

    def initialize = initialize_closeable(owned: true)

    private

    def release = raise("release failed")
  end

  # ---- phase 2's tests, re-run unchanged ------------------------------------------------------

  test "close is idempotent and release runs exactly once" do
    subject = Spy.new
    3.times { subject.close }

    assert_equal(1, subject.releases)
    assert(subject.closed?)
  end

  test "a Closeable closed from two threads releases once and both callers return" do
    subject = Spy.new
    returned = ::Thread::Queue.new

    threads = Array.new(2) { ::Thread.new { subject.close; returned.push(:returned) } }
    threads.each(&:join)

    assert_equal(1, subject.releases)
    assert_equal(2, returned.size)
  end

  test "a release that raises flips the latch, propagates once, and a second close is a no-op" do
    subject = Raising.new

    assert_raises(RuntimeError) { subject.close }
    assert(subject.closed?)
    assert_nil(subject.close)
  end

  test "an unowned Closeable never releases" do
    subject = Spy.new(owned: false)
    subject.close

    assert_equal(0, subject.releases)
    assert(subject.closed?)
    refute(subject.owned?)
  end

  test "an includer that never called initialize_closeable fails loudly" do
    unready = Class.new { include Dexpace::Closeable }.new

    assert_raises(Dexpace::SeamError) { unready.closed? }
  end

  test "an includer with no release hook fails loudly on close" do
    hookless = Class.new do
      include Dexpace::Closeable

      def initialize = initialize_closeable(owned: true)
    end.new

    assert_raises(::NotImplementedError) { hookless.close }
  end

  # Visibility, asserted with respond_to? rather than assert_predicate: Minitest sends past
  # `private` on the 3.2 floor (phase 1's finding).
  test "closed? and owned? are public with the arity phase 2 published" do
    subject = Spy.new

    assert_respond_to(subject, :closed?)
    assert_respond_to(subject, :owned?)
    assert_equal(0, subject.method(:closed?).arity)
    refute(subject.respond_to?(:release))
  end

  # ---- P3-6: the one change phase 3a makes ---------------------------------------------------

  # THE assertion that distinguishes the synchronised reader from phase 2's unsynchronised one on
  # CRuby, and the only one that does: it FAILS against phase 2's version, where #closed? never
  # touches the mutex. Verified on 3.2.11, 3.4.10 and 4.0.6 that a Thread::Mutex held across a
  # fiber suspension raises ThreadError for a second fiber of the same thread, so holding the
  # latch mutex from one fiber and reading #closed? from another proves the read acquires it.
  #
  # IO-38 is the requirement that forces this. Design §3.1 fixes the mechanism -- the flag is
  # "written and read through a Thread::Mutex rather than relying on the GVL, so the guarantee
  # survives JRuby and TruffleRuby" -- and DEF-33 records that no such interpreter is in the
  # matrix, which is precisely why this assertion carries the weight the behavioural IO-38 test
  # cannot.
  test "closed? acquires the close mutex" do
    subject = Spy.new
    latch = subject.instance_variable_get(:@dexpace_close_mutex)

    holder = ::Fiber.new { latch.synchronize { ::Fiber.yield } }
    holder.resume

    assert_raises(::ThreadError) { ::Fiber.new { subject.closed? }.resume }
  end

  # The counterpart: with the mutex free, #closed? is an ordinary read from any fiber.
  test "closed? reads normally when the mutex is free" do
    subject = Spy.new
    answers = []

    ::Fiber.new { answers << subject.closed? }.resume
    subject.close
    ::Fiber.new { answers << subject.closed? }.resume

    assert_equal([false, true], answers)
  end

  # The mutex is held across the flag flip and NOTHING else -- never across #release. A #release
  # that reads #closed? would deadlock on a non-reentrant Mutex if it were.
  test "the close mutex is not held across release" do
    reader = Class.new do
      include Dexpace::Closeable

      attr_reader :seen

      def initialize = initialize_closeable(owned: true)

      private

      def release = (@seen = closed?)
    end.new

    reader.close

    assert(reader.seen)
  end
end
```

The first of the three is the only assertion that distinguishes the synchronised reader from phase
2's on CRuby. Everything else about `IO-38` passes with or without the lock on every row of a CRuby
matrix, which is exactly what `DEF-33` records: the interpreter on which the mechanism is
load-bearing is not one this project runs.

- [ ] **Step 2: Run the suite to confirm the new test fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/closeable_test.rb`
Expected: FAIL — `ThreadError expected but nothing was raised`, on the "closed? acquires the close
mutex" test only. Verified on 3.2.11, 3.4.10 and 4.0.6.

- [ ] **Step 3: Change the one line in `lib/dexpace/closeable.rb`**

Replace `#closed?`'s body with:

```ruby
    # IO-38 (phase 3a, P3-6): the latch is read under the same Thread::Mutex that writes it, so a
    # close on one thread reliably invalidates a slice being read on another. Design
    # §3.1 fixes the mechanism -- "written and read through a Thread::Mutex rather than relying on
    # the GVL, so the guarantee survives JRuby and TruffleRuby" -- and phase 2's unsynchronised
    # read relied on exactly the GVL that sentence declines to rely on. Measured at ~40 ns per
    # call on 3.2.11, 3.4.10 and 4.0.6, paid once per public entry point and never per byte.
    # DEF-33 records that no GVL-free interpreter is in the matrix, so on every CI row this read
    # passes with or without the lock: the assertion that distinguishes them is the fiber-held
    # mutex test in closeable_test.rb.
    def closed?
      ensure_closeable_initialized
      @dexpace_close_mutex.synchronize { @dexpace_closed }
    end
```

- [ ] **Step 4: Run the suite to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/closeable_test.rb`
Expected: PASS, 10 tests.

- [ ] **Step 5: Re-run every phase-2 suite that reads `#closed?`, unchanged**

Run: `(cd gems/dexpace-core && bundle exec rake test)`
Expected: PASS, with no test file edited. The suites that touch it are `closeable_test.rb`, the
`#closed?` assertions across `transport/*_test.rb` and `async/completer_test.rb`, and the two
`SEAM-18` bridge suites, whose bridges are `Closeable` with `owned: false`. Record the run green in
the phase record — a behaviour change with no signature change is only as safe as the suite that was
already there.

---

## Task 3: `Dexpace::StreamError` and `Dexpace::EndOfStreamError`

**Requirement IDs:** the error vocabulary `IO-4`, `IO-9`, `IO-11`, `IO-12`, `IO-15`, `IO-16`,
`IO-17` and `IO-28` raise through, plus `BODY-13`'s one-helper rule, which 3a owns the I/O half of.
**Design:** "The error classes".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/error/stream_error.rb`,
  `gems/dexpace-core/lib/dexpace/error/end_of_stream_error.rb`, and the two `sig/` mirrors at
  `gems/dexpace-core/sig/dexpace/error/{stream_error,end_of_stream_error}.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/error/{stream_error,end_of_stream_error}_test.rb`

**Interfaces:**
- Consumes: phase 1's `Dexpace::Error` (a module).
- Produces: `Dexpace::StreamError < ::IOError` with `.short_transfer(transferred:, expected:)` and
  `.zero_read(requested:)`; `Dexpace::EndOfStreamError < ::EOFError`. Both include `Dexpace::Error`.
  Tasks 5–14 raise them, and phase 3b calls both class methods.

**Third, because every later task raises one of them**, and because `EndOfStreamError`'s ancestry
assertion is a one-line test that unblocks the whole bridge story.

- [ ] **Step 1: Write the failing tests**

`gems/dexpace-core/test/dexpace/error/end_of_stream_error_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "stringio"

# IO-11, IO-12, IO-15, IO-16.
class DexpaceEndOfStreamErrorTest < DexpaceTestCase
  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::EndOfStreamError, "eof"
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::EndOfStreamError, caught)
  end

  # THE ancestry assertion, and it is load-bearing rather than tidy. Verified on 3.2.11, 3.4.10 and
  # 4.0.6 that IO.copy_stream -- which is literally what Net::HTTP#send_request_with_body_stream
  # calls -- terminates CLEANLY on an ::EOFError SUBCLASS raised by a duck-typed #readpartial.
  # Outside that family copy_stream propagates and every streaming upload phase 8 performs fails,
  # and nothing else in 3a would catch it.
  test "inherits ::EOFError, which is what makes IO.copy_stream terminate rather than propagate" do
    assert_operator(Dexpace::EndOfStreamError, :<, ::EOFError)
  end

  # The proof, not the restatement: a duck-typed source that raises this class drives
  # IO.copy_stream to a clean finish with the payload intact.
  test "IO.copy_stream terminates on it and keeps the payload" do
    source = Class.new do
      def initialize = @remaining = 3

      def readpartial(_maxlen, outbuf = nil)
        raise Dexpace::EndOfStreamError, "done" if @remaining.zero?

        @remaining -= 1
        outbuf.nil? ? +"xy" : outbuf.replace(+"xy")
      end
    end.new
    destination = StringIO.new(+"".b)

    ::IO.copy_stream(source, destination)

    assert_equal("xyxyxy", destination.string)
  end

  # A ::StandardError, so `rescue => e` catches it; it is deliberately NOT in the IOError family,
  # because IO-24 requires end of stream to stay distinct from a state/contract failure.
  test "is not a Dexpace::StreamError, so EOF and a contract violation stay distinct" do
    refute_operator(Dexpace::EndOfStreamError, :<, Dexpace::StreamError)
  end
end
```

`gems/dexpace-core/test/dexpace/error/stream_error_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# IO-4, IO-9, IO-17, IO-28, and BODY-13's one-helper rule.
class DexpaceStreamErrorTest < DexpaceTestCase
  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::StreamError, "boom"
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::StreamError, caught)
  end

  # IO-4, IO-17 and IO-42 each literally say "an I/O error", and ::IOError is Ruby's root for that
  # family, so an existing `rescue IOError` site keeps matching.
  test "is in Ruby's IOError family" do
    assert_operator(Dexpace::StreamError, :<, ::IOError)
  end

  # NOT because of XCUT-4: XCUT-4 makes a transport error report itself as always-retryable, and a
  # stream-contract violation must not claim that. StreamError is a sibling of phase 8's
  # TransportError inside ::IOError, never a subclass, so this stays true when phase 8 lands.
  test "is not an EOF error, so a contract violation is never read as end of stream" do
    refute_operator(Dexpace::StreamError, :<, ::EOFError)
  end

  # BODY-13 requires the short-transfer message form of BODY-10/HTTP-39 and the zero-read form of
  # BODY-25 to come from ONE helper "so the message form cannot diverge". 3b calls these.
  test "short_transfer builds the one message form for a short transfer" do
    error = Dexpace::StreamError.short_transfer(transferred: 3, expected: 10)

    assert_instance_of(Dexpace::StreamError, error)
    assert_includes(error.message, "3")
    assert_includes(error.message, "10")
  end

  test "zero_read builds the one message form for IO-17's source-contract violation" do
    error = Dexpace::StreamError.zero_read(requested: 4096)

    assert_instance_of(Dexpace::StreamError, error)
    assert_includes(error.message, "4096")
    assert_includes(error.message, "IO-17")
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/end_of_stream_error_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::EndOfStreamError`. Then the same for
`stream_error_test.rb`.

- [ ] **Step 3: Write the two error files**

`lib/dexpace/error/stream_error.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # A stream-contract violation: a sink asked for more bytes than the source buffer holds (IO-4),
  # a source that returned 0 for a positive requested count (IO-17), an underlying sink that
  # accepted fewer bytes than it was handed, a materialisation over Dexpace::IO's ceiling (IO-9),
  # or a reach for a TeeSink's backing buffer (IO-28).
  #
  # It subclasses ::IOError because IO-4, IO-17 and IO-42 each literally say "an I/O error" and
  # ::IOError is Ruby's root for that family. Deliberately NOT because of XCUT-4: XCUT-4 requires
  # a *transport* error to report itself as always-retryable, and a stream-contract violation must
  # not make that claim. This is a sibling of phase 8's Dexpace::TransportError inside Ruby's I/O
  # family and never a subclass of it.
  #
  # Dexpace::IOError is never defined, for the Dexpace::ArgumentError reason phase 1 recorded: it
  # would shadow ::IOError for every file inside `module Dexpace`.
  class StreamError < ::IOError
    include Dexpace::Error

    # BODY-13 requires the short-transfer message form of BODY-10/HTTP-39 to come from ONE helper
    # "so the message form cannot diverge". 3a owns the I/O half; 3b calls this.
    def self.short_transfer(transferred:, expected:)
      new("transferred #{transferred} bytes but #{expected} were expected")
    end

    # IO-17's source-contract violation, and BODY-25's message form. One helper, same reason.
    def self.zero_read(requested:)
      new("a source returned 0 bytes for a requested count of #{requested}; " \
          "a read of 0 for a positive count is a source-contract violation (IO-17)")
    end
  end
end
```

`lib/dexpace/error/end_of_stream_error.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # End of stream reached by a read form that cannot report it any other way: #read_exactly,
  # #readbyte, #readpartial, #skip (IO-11, IO-12, IO-15, IO-16).
  #
  # The superclass is load-bearing, not tidy. Verified on 3.2.11, 3.4.10 and 4.0.6 that
  # IO.copy_stream -- which is literally what Net::HTTP#send_request_with_body_stream calls, so it
  # is the code path every streamed upload takes -- terminates cleanly on an ::EOFError SUBCLASS
  # raised by a duck-typed #readpartial. Outside that family copy_stream propagates and every
  # upload phase 8 performs fails. Ruby's own readers raise ::EOFError for exactly this condition.
  class EndOfStreamError < ::EOFError
    include Dexpace::Error
  end
end
```

- [ ] **Step 4: Write the two `sig/` mirrors**

`sig/dexpace/error/stream_error.rbs`:

```rbs
module Dexpace
  class StreamError < ::IOError
    include Dexpace::Error

    def self.short_transfer: (transferred: Integer, expected: Integer) -> Dexpace::StreamError
    def self.zero_read: (requested: Integer) -> Dexpace::StreamError
  end
end
```

`sig/dexpace/error/end_of_stream_error.rbs`:

```rbs
module Dexpace
  class EndOfStreamError < ::EOFError
    include Dexpace::Error
  end
end
```

- [ ] **Step 5: Add the two `require_relative`s to `lib/dexpace.rb`**

Immediately after phase 2's `error/cancelled_error` line, in the order `error/stream_error`,
`error/end_of_stream_error`.

- [ ] **Step 6: Run the tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/end_of_stream_error_test.rb` and the same
for `stream_error_test.rb`.
Expected: PASS — 4 and 5 tests. Then `bundle exec rake rbs:validate steep`.

---

## Task 4: `Dexpace::IO`, the materialisation ceiling, and the three RBS interfaces

**Requirement IDs:** `IO-9`'s ceiling as a constant (design §10.18's substitution, §3.1's 64 MiB
default); deviation **P3-8**'s naming of `Dexpace::IO`, `_Source`, `_Sink` and `_Chunked`.
**Design:** "`Dexpace::IO` — the namespace and the ceiling"; "The RBS interfaces".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/io.rb`, `gems/dexpace-core/sig/dexpace/io.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/io_test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `Dexpace::IO` (a module) and `Dexpace::IO::MAX_MATERIALIZED_BYTES` (an `Integer`), plus
  the RBS interfaces `Dexpace::IO::_Source`, `_Sink` and `_Chunked`. Tasks 5–14 nest inside the
  module and read the constant directly.

**Immediately after the cop**, because this is the file that makes `Dexpace::IO` exist and therefore
the file that makes the cop bite.

- [ ] **Step 1: Write the failing test**

Note the third test: it pins the module's whole constant list, so a later phase that adds a class to
`Dexpace::IO` has to say so here as well as in the surface manifest.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"

# IO-9, and P3-8's naming of the constant.
class DexpaceIOTest < DexpaceTestCase
  test "MAX_MATERIALIZED_BYTES is design §3.1's 64 MiB, chosen and not derived" do
    assert_equal(64 * 1024 * 1024, Dexpace::IO::MAX_MATERIALIZED_BYTES)
  end

  # R5 is 3b's and phase 5 owns the configuration source. Nothing in 3a reads the ceiling from a
  # keyword, so this asserts the absence that DEF-28's precedent depends on: adding an optional
  # keyword later widens a signature, and NFR-4 is not prejudiced.
  test "no 3a operation takes a max_materialized_bytes keyword" do
    keywords = [Dexpace::IO::Buffer.instance_method(:snapshot),
                Dexpace::IO::TypedReads.instance_method(:read_exactly),
                Dexpace::IO::TypedReads.instance_method(:read_string),]
                .flat_map { |method| method.parameters.map(&:last) }

    refute_includes(keywords, :max_materialized_bytes)
  end

  test "Dexpace::IO is a module and holds the streaming classes" do
    assert_kind_of(::Module, Dexpace::IO)
    assert_equal(%i[Buffer BufferedSink BufferedSource MAX_MATERIALIZED_BYTES TeeSink TypedReads
                    TypedWrites].sort,
                 Dexpace::IO.constants.sort,)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::IO`.

- [ ] **Step 3: Write `lib/dexpace/io.rb`**

The YARD block carries `OI-3` — the finding that the shadowing is **not** inert inside a consumer's
own `class C; include Dexpace`, only inside a top-level include — because that is where a reader
meets it and no gate this repository owns can reach a consumer's file.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # The byte-streaming layer: one FIFO buffer, one buffered source/sink pair with typed reads and
  # non-consuming views, and one tee sink. Design §10.1 retired the provider seam that used to make
  # this pluggable, so the behavioural contract is the whole deliverable -- there is no registry,
  # no factory and no installation call here.
  #
  # HAZARD (OI-3), stated where a reader meets it. This constant shadows ::IO for every file
  # inside `module Dexpace` AND inside a consumer's own `class C; include Dexpace`, because
  # `include` inserts Dexpace ahead of Object in C.ancestors. `x.is_a?(IO)` is then silently false
  # for a real ::IO, with no error and no warning, and a `case/when IO` falls through. A top-level
  # `include Dexpace` is unaffected, because Object's own constant table is searched first. Core
  # never writes `is_a?(IO)`: every stream this layer accepts is checked with respond_to?, and
  # Dexpace/QualifiedCoreConstant makes a bare `IO` inside `module Dexpace` a RuboCop offense.
  # No gate this repository owns reaches a consumer's file.
  module IO
    # IO-9's ceiling. Design §10.18 substitutes it for a host maximum single-array allocation Ruby
    # does not have, and §3.1 fixes the default at 64 MiB -- "chosen, not derived". Every
    # operation that produces one contiguous String reads this constant directly; nothing takes it
    # as a keyword. Phase 5 owns the configuration source (R5, DEF-28's precedent): adding an
    # optional keyword later widens a signature rather than narrowing one, so NFR-4 is not
    # prejudiced.
    MAX_MATERIALIZED_BYTES = 64 * 1024 * 1024
  end
end
```

The file defines a module and one constant nested inside it, which is phase 2's reading of
`module-organization/1828a984` applied again (`Dexpace.close_quietly` beside `Dexpace::Closeable`):
splitting a single frozen `Integer` into its own file to satisfy a rule about constants would be the
letter over the purpose.

- [ ] **Step 4: Write `sig/dexpace/io.rbs`**

The three interfaces carry no runtime constant, so the surface snapshot cannot see them and the
`sig` diff is their only gate — which is why each is named deliberately and why `_Chunked` is not
called `_Body`.

```rbs
module Dexpace
  module IO
    MAX_MATERIALIZED_BYTES: Integer

    # IO-1's primitive, as a type. #write_all accepts anything satisfying it (IO-17).
    interface _Source
      def read_into: (String, count: Integer) -> Integer
    end

    # The primitive a destination satisfies, and what IO.copy_stream requires of one.
    interface _Sink
      def write: (*String) -> Integer
    end

    # Design §10.2's canonical body representation, AS A TYPE. Deliberately not named _Body: 3b's
    # body type is richer -- media type, content length, #replayable?, a single write-to-sink
    # operation -- and one name for two meanings across the sub-phase cut is the failure the cut
    # exists to prevent. 3b's interface can include this one.
    interface _Chunked
      def each: () { (String) -> void } -> void
    end
  end
end
```

- [ ] **Step 5: Add `require_relative "dexpace/io"` to `lib/dexpace.rb`**

After Task 3's two error files and after phase 2's `dexpace/closeable`.

- [ ] **Step 6: Run the test and RuboCop to confirm both pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io_test.rb`, then
`bundle exec rubocop --fail-level=convention gems/dexpace-core/lib/dexpace/io.rb`.
Expected: PASS, 3 tests; RuboCop clean — the `module Dexpace; module IO` declaration is the accepted
case Task 1 Step 1 added, so a failure here means Task 1's `#definition_name?` guard is missing.
Then `bundle exec rake rbs:validate steep`.

---
## Task 5: `TypedReads` — `#read_into`, the chunk store, and the view protocol

**Requirement IDs:** `IO-1`, `IO-2`, `IO-3`. **Design:** "R2 — the `Source#read(dest, count)`
primitive"; deviations **P3-1**, **P3-9**.

> **IO-1** (MUST) — `Source.read(dest, byteCount)` MUST append the bytes it reads to the TAIL of the
> caller-provided destination buffer (never overwrite existing content), and MUST return the number
> of bytes transferred: at least 1 when byteCount>0 and the source is not exhausted, exactly 0 when
> byteCount==0, -1 when the source is exhausted before any byte is read, and never more than
> byteCount.

> **IO-2** (MUST) — A read of byteCount==0 MUST return 0 and MUST NOT report end-of-stream (-1),
> even when the source is already exhausted.

> **IO-3** (MUST) — A negative byteCount passed to a size-taking read/write/copy operation MUST be
> rejected as an argument-validation (programming) error before any I/O occurs, rather than silently
> clamped. … a port MAY use whichever argument-error type is idiomatic, so long as it fails fast.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/io/typed_reads.rb`,
  `gems/dexpace-core/sig/dexpace/io/typed_reads.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/io/typed_reads_test.rb`

**Interfaces:**
- Consumes: Task 3's `Dexpace::StreamError` and `EndOfStreamError`, phase 1's
  `Dexpace::InvalidArgumentError`, phase 2's `Dexpace::ClosedError` and `Dexpace::Closeable`.
- Produces: `Dexpace::IO::TypedReads`, a **public** module supplying `#initialize_typed_reads` and
  `#read_into(dest, count:) -> Integer` over one private hook the includer defines,
  `#fill(min_bytes) -> Integer`. Also the protected view protocol — `#dexpace_consumed`,
  `#dexpace_ensure_buffered`, `#dexpace_window_copy`, `#dexpace_register_view`,
  `#dexpace_forget_view`, `#dexpace_invalidate`, `#dexpace_release_views`,
  `#dexpace_remaining_window` — which Tasks 9, 10 and 12 are the only callers of. Tasks 6–9 extend
  this file; Tasks 10 and 12 include it.

**Written against a trivial in-test includer.** `#read_into` needs `#fill` to exist but not
`BufferedSource`, and testing it against a fixed chunk list with no upstream at all is genuinely
simpler than standing `BufferedSource` up first.

**How this file is assembled.** `typed_reads.rb` is built across Tasks 5 to 9. Task 5 writes a
complete, loadable file with exactly two insertion points, and each later task splices into them:
public methods go **immediately before the `protected` keyword**, private helpers go **at the end of
the file's `private` section, before the closing `end`s**. Tasks 5–9's fragments concatenate to the
shipped file byte for byte, which was checked rather than assumed — **each fragment fence ends with
the blank line its successor needs**, so the concatenation satisfies `Layout/EmptyLineBetweenDefs`
and `Layout/EmptyLinesAroundAccessModifier` without an editing step nobody wrote down. Splice the
fences as they are; do not trim the trailing blank line.

**Why the module is public and not `private_constant` (P3-8), measured.** The runtime surface
snapshot walks each class's `public_instance_methods(false)`, which does **not** see a method
reaching a class through an included module. Running phase 0's walker over the finished tree both
ways: with `TypedReads` and `TypedWrites` public the manifest carries **37** public method names;
with `Dexpace::IO.private_constant :TypedReads, :TypedWrites` it carries **14**, and the two modules
vanish from it entirely. A private module would hide 23 of 3a's methods from the gate that exists to
see them.

- [ ] **Step 1: Write the failing test**

The whole file's header and the in-test includer, plus the `IO-1`/`IO-2`/`IO-3` section. Tasks 6–9
append their own sections to this same file.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# IO-1, IO-2, IO-3, IO-9, IO-11..IO-16, IO-19..IO-24, and §10.2's #each.
#
# Written against a trivial in-test includer that supplies #fill from a fixed chunk list, so the
# read vocabulary is exercised with no upstream at all. BufferedSource's own suite covers the same
# vocabulary over a real stream.
class DexpaceTypedReadsTest < DexpaceTestCase
  # The Ruby shape of the reference's BufferedSource interface: supply #fill, get everything.
  class Scripted
    include Dexpace::IO::TypedReads
    include Dexpace::Closeable

    attr_reader :fills

    def initialize(*chunks)
      @pending = chunks
      @fills = 0
      initialize_closeable(owned: true)
      initialize_typed_reads
    end

    private

    def fill(_min_bytes)
      @fills += 1
      chunk = @pending.shift
      return 0 if chunk.nil?

      store_append(chunk)
    end

    # IO-22: an includer's #release invalidates every view derived from it. Buffer and
    # BufferedSource both do exactly this.
    def release
      dexpace_release_views
    end
  end

  def source(*chunks)
    Scripted.new(*chunks)
  end

  # ---- IO-1, IO-2, IO-3: the primitive -------------------------------------------------------

  # IO-1: "MUST append the bytes it reads to the TAIL of the caller-provided destination buffer
  # (never overwrite existing content)".
  test "read_into appends to the tail and never overwrites" do
    dest = +"seed".b

    transferred = source("abc").read_into(dest, count: 3)

    assert_equal(3, transferred)
    assert_equal("seedabc", dest)
  end

  # IO-1's four return values, and the -1 sentinel rather than Ruby's nil: IO-17's pump reads it,
  # and a foreign source implementing IO-1 literally would return it.
  test "read_into returns -1 when the source is exhausted before any byte" do
    assert_equal(-1, source.read_into(+"".b, count: 4))
  end

  test "read_into never returns more than count" do
    assert_equal(2, source("abcdef").read_into(+"".b, count: 2))
  end

  # IO-2: "A read of byteCount==0 MUST return 0 and MUST NOT report end-of-stream (-1), even when
  # the source is already exhausted." Ruby's own readers do not collapse this, but IO-2 is a
  # statement about 3a's surface.
  test "read_into returns 0 for a zero count on an exhausted source, never -1" do
    exhausted = source
    exhausted.read_into(+"".b, count: 1)

    assert_equal(0, exhausted.read_into(+"".b, count: 0))
  end

  test "read_into with a zero count touches neither the buffer nor the upstream" do
    subject = source("abc")

    assert_equal(0, subject.read_into(+"".b, count: 0))
    assert_equal(0, subject.fills)
  end

  # IO-3, rejected BEFORE any I/O and with no partial side effect.
  test "read_into rejects a negative count naming the argument, before any I/O" do
    subject = source("abc")

    error = assert_raises(Dexpace::InvalidArgumentError) { subject.read_into(+"".b, count: -1) }

    assert_includes(error.message, "count")
    assert_includes(error.message, "-1")
    assert_equal(0, subject.fills)
    assert_equal("abc", subject.read_exactly(3))
  end

  test "read_into rejects a non-Integer count" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      source("abc").read_into(+"".b, count: 2.5)
    end

    assert_includes(error.message, "count")
  end

  # A UTF-8 destination is rejected because appending a non-ASCII payload to a BINARY String
  # silently retags the RESULT to UTF-8 while an ASCII-only one does not, so the destination's
  # final tag would depend on the payload's content.
  test "read_into rejects a non-BINARY destination before any I/O" do
    subject = source("abc")

    error = assert_raises(Dexpace::InvalidArgumentError) { subject.read_into(+"", count: 3) }

    assert_includes(error.message, "ASCII-8BIT")
    assert_equal(0, subject.fills)
  end

  # A FrozenError from deep inside is a crash, not a rejection.
  test "read_into rejects a frozen destination before any I/O" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      source("abc").read_into("seed".b.freeze, count: 3)
    end

    assert_includes(error.message, "frozen")
  end

  test "read_into rejects a destination that is not a String" do
    assert_raises(Dexpace::InvalidArgumentError) { source("abc").read_into(:nope, count: 1) }
  end

  test "read_into fills at most once before serving, and serves from the buffer after that" do
    subject = source("ab", "cd")

    assert_equal(2, subject.read_into(+"".b, count: 4))
    assert_equal(1, subject.fills)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/typed_reads_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::IO::TypedReads`.

- [ ] **Step 3: Write `lib/dexpace/io/typed_reads.rb`**

Read the ordering inside `#read_into` before writing it: `IO-3`'s validation first because it must
run "before any I/O occurs"; then `IO-42`'s close check, because that MUST covers every read attempt
including a zero-count one; then `IO-2`'s zero return, before the buffer or the upstream is touched;
then serve from the buffer, filling at most once if it is empty.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../io"
require_relative "../error/end_of_stream_error"
require_relative "../error/stream_error"
require_relative "../error/invalid_argument_error"
require_relative "../error/closed_error"

module Dexpace
  module IO
    # The read vocabulary, supplied over one private hook the includer defines:
    # #fill(min_bytes) -> Integer, the number of bytes it appended to the store (0 at end of
    # stream). Dexpace::Closeable set the initialize_*-plus-one-hook precedent in phase 2 and this
    # follows it exactly; an includer must also include Dexpace::Closeable, which
    # #initialize_typed_reads asserts.
    #
    # Public, and not private_constant, for two reasons that are each sufficient (P3-8). The
    # runtime surface snapshot walks each class's public_instance_methods(false), which does NOT
    # see a method reaching a class through an included module, so a private module would hide
    # almost the whole of 3a from the gate that exists to see it. And a third-party source that
    # supplies #fill gets the entire read vocabulary by including this, which is the Ruby shape of
    # the reference's BufferedSource interface.
    #
    # #slice and #peek name Dexpace::IO::BufferedSource at call time rather than requiring it,
    # because buffered_source.rb requires this file. lib/dexpace.rb requires the whole tree, so
    # the constant is always resolvable by the time a caller can reach these methods.
    module TypedReads
      # Task 7's line machine reads these; they are here because a constant belongs at the top.
      NEWLINE = "\n".b.freeze
      CARRIAGE_RETURN = "\r".b.freeze

      private_constant :NEWLINE, :CARRIAGE_RETURN

      # Call from the including class's #initialize, after #initialize_closeable.
      def initialize_typed_reads
        unless is_a?(Dexpace::Closeable)
          raise Dexpace::SeamError,
                "#{self.class} includes Dexpace::IO::TypedReads and must also include " \
                "Dexpace::Closeable"
        end

        @dexpace_chunks = []
        @dexpace_head = 0
        @dexpace_buffered = 0
        @dexpace_consumed = 0
        @dexpace_views = []
        @dexpace_invalidated = false
        nil
      end

      # IO-1's primitive, and deliberately not called #read (P3-1). It APPENDS to the tail of
      # `dest`; #read and #readpartial overwrite, because IO.copy_stream hands them one buffer it
      # reuses across every call.
      #
      # Returns at least 1 when count is positive and the source is not exhausted, exactly 0 when
      # count is 0 (IO-2), -1 when exhausted before any byte, and never more than count.
      def read_into(dest, count:)
        ensure_typed_reads_initialized
        # IO-3 first, before any I/O and before the buffer is consulted.
        validate_destination!(dest)
        validate_count!(count, name: "count")
        # IO-42 next: a closed stream-backed source rejects every read attempt, count 0 included.
        # IO-2's clause is about an OPEN source's exhaustion, so it cannot swallow this.
        ensure_readable
        # IO-2: 0 for a zero count, never -1, without touching the buffer or the upstream.
        return 0 if count.zero?

        fill_once_if_empty
        return -1 if @dexpace_buffered.zero?

        taken = [count, @dexpace_buffered].min
        dest << store_take(taken)
        taken
      end

```

```ruby
      protected

      # The view protocol. Protected rather than public because a view drives its parent and
      # nothing else may: these are not NFR-4 surface.
      def dexpace_consumed
        @dexpace_consumed
      end

      def dexpace_ensure_buffered(target)
        ensure_buffered(target)
      end

      def dexpace_window_copy(offset, count)
        store_peek(offset, count)
      end

      def dexpace_register_view(view)
        @dexpace_views << view
        nil
      end

      def dexpace_forget_view(view)
        @dexpace_views.delete(view)
        nil
      end

      def dexpace_invalidate
        @dexpace_invalidated = true
        nil
      end

      # IO-22/IO-42: an includer's #release MUST call this, so a close on this object invalidates
      # every view derived from it and a later read on one of those views fails loudly rather than
      # returning stale or arbitrary bytes. Buffer and BufferedSource both do.
      def dexpace_release_views
        @dexpace_views.each { |view| view.dexpace_invalidate }
        @dexpace_views.clear
        nil
      end

      def dexpace_remaining_window
        ::Float::INFINITY
      end

```

```ruby
      private

      # IO-22/IO-38/IO-42. One Thread::Mutex acquisition per public entry point, through
      # Closeable#closed?, and it is never held across a fill, a read, a drain or a #release.
      def ensure_readable
        if @dexpace_invalidated
          raise Dexpace::ClosedError,
                "this #{self.class} was invalidated by a close on the source it was derived from"
        end
        return unless closed?
        return if reads_survive_close?

        raise Dexpace::ClosedError, "#{self.class} is closed"
      end

      # IO-42's in-memory exemption. Only Dexpace::IO::Buffer answers true.
      def reads_survive_close?
        false
      end

      def ensure_typed_reads_initialized
        return if defined?(@dexpace_chunks) && @dexpace_chunks

        raise Dexpace::SeamError,
              "#{self.class} includes Dexpace::IO::TypedReads but never called " \
              "#initialize_typed_reads"
      end

      def fill(_min_bytes)
        raise NotImplementedError,
              "#{self.class} includes Dexpace::IO::TypedReads and must define a private " \
              "#fill(min_bytes)"
      end

      def fill_once_if_empty
        ensure_buffered(1) if @dexpace_buffered.zero?
        @dexpace_buffered
      end

      def ensure_buffered(target)
        while @dexpace_buffered < target
          added = fill(target - @dexpace_buffered)
          break if added.nil? || added <= 0
        end
        @dexpace_buffered
      end

      # THE ingress retag, and the one place it happens. Verified facts 3 and 4: force_encoding on
      # a frozen String raises FrozenError even when the target encoding is already the string's
      # own, and a Rack-style body's #each yields frozen literals under this repository's own
      # frozen_string_literal pragma. String#b always returns a new, unfrozen copy. So: keep the
      # chunk when it is both frozen and already BINARY, and #b it otherwise. force_encoding
      # appears nowhere on this path.
      #
      # The compaction invariant this buys: every chunk in the store is a FROZEN BINARY String, so
      # a chunk is copied at most once on the way in -- and exactly zero times when the upstream
      # already yields frozen BINARY chunks, which is the ordinary Rack shape -- and no view can
      # ever see a chunk mutated behind its back. The upstream's own return is deliberately NOT
      # frozen in place: a duck-typed #readpartial that reuses one buffer would break if it were.
      def store_append(chunk)
        return 0 if chunk.nil? || chunk.empty?

        stored =
          if chunk.frozen? && chunk.encoding == ::Encoding::BINARY
            chunk
          else
            chunk.b.freeze
          end
        @dexpace_chunks << stored
        @dexpace_buffered += stored.bytesize
        stored.bytesize
      end

      # O(1) amortised: a fully consumed chunk is shifted off, a partially consumed head chunk is
      # left in place behind a moving @dexpace_head and is never bytesliced to compact it. The
      # byteslice that produces the caller's bytes is the only copy those bytes get.
      def store_take(count)
        return (+"").b if count.zero?

        head = @dexpace_chunks.first
        available = head.bytesize - @dexpace_head
        if count <= available
          out = head.byteslice(@dexpace_head, count)
          advance_head(count, available)
          @dexpace_buffered -= count
          @dexpace_consumed += count
          return out
        end

        out = (+"").b
        remaining = count
        while remaining.positive?
          head = @dexpace_chunks.first
          available = head.bytesize - @dexpace_head
          take = [remaining, available].min
          out << head.byteslice(@dexpace_head, take)
          advance_head(take, available)
          remaining -= take
        end
        @dexpace_buffered -= count
        @dexpace_consumed += count
        out
      end

      def store_drop(count)
        remaining = count
        while remaining.positive?
          head = @dexpace_chunks.first
          available = head.bytesize - @dexpace_head
          take = [remaining, available].min
          advance_head(take, available)
          remaining -= take
        end
        @dexpace_buffered -= count
        @dexpace_consumed += count
        nil
      end

      def advance_head(taken, available)
        if taken == available
          @dexpace_chunks.shift
          @dexpace_head = 0
        else
          @dexpace_head += taken
        end
        nil
      end

      # Non-consuming: copies a window `offset` bytes ahead of the cursor. This is how a view
      # reads its parent without advancing the parent.
      def store_peek(offset, count)
        out = (+"").b
        return out if count <= 0

        position = 0
        head_offset = @dexpace_head
        wanted = count
        @dexpace_chunks.each do |chunk|
          available = chunk.bytesize - head_offset
          if position + available > offset
            start = head_offset + (offset > position ? offset - position : 0)
            take = [chunk.bytesize - start, wanted].min
            out << chunk.byteslice(start, take)
            wanted -= take
            break if wanted.zero?
          end
          position += available
          head_offset = 0
        end
        out
      end

      def validate_count!(value, name:)
        unless value.is_a?(::Integer)
          raise Dexpace::InvalidArgumentError,
                "#{name} must be an Integer, got #{value.class}"
        end
        return unless value.negative?

        raise Dexpace::InvalidArgumentError, "#{name} must not be negative, got #{value}"
      end

      # IO-3's eager rejection. A non-BINARY destination is rejected because appending a
      # non-ASCII UTF-8 payload to a BINARY String silently retags the RESULT to UTF-8 while an
      # ASCII-only one does not -- so a UTF-8 dest would produce a buffer whose tag depends on the
      # payload's content. A frozen dest is rejected because a FrozenError from deep inside is a
      # crash, not a rejection.
      def validate_destination!(dest)
        unless dest.is_a?(::String)
          raise Dexpace::InvalidArgumentError, "dest must be a String, got #{dest.class}"
        end
        if dest.frozen?
          raise Dexpace::InvalidArgumentError, "dest must not be frozen: #read_into appends to it"
        end
        return if dest.encoding == ::Encoding::BINARY

        raise Dexpace::InvalidArgumentError,
              "dest must be tagged #{::Encoding::BINARY}, got #{dest.encoding}"
      end

      def raise_end_of_stream(operation)
        raise Dexpace::EndOfStreamError,
              "#{operation} reached the end of the stream with #{@dexpace_buffered} " \
              "bytes buffered"
      end

```

```ruby
    end
  end
end
```

Those four fences are one file, in that order: the header and `#read_into`, then the `protected`
block, then `private` and its helpers, then the closing `end`s. The `protected` block is the whole
view protocol and lands here rather than in Task 9 because `#materialization_hint` in Task 6 already
reads `#dexpace_remaining_window`; Tasks 9, 10 and 12 are its only other callers.
`@dexpace_invalidated` is likewise initialised and read here and set only by Task 9's views.

- [ ] **Step 4: Write `sig/dexpace/io/typed_reads.rbs`**

The mirror is written whole, for the finished module — Tasks 6–9 add no `sig/` work of their own,
which is what keeps "no task writes only `sig/`" true without leaving the signature behind the code.

```rbs
module Dexpace
  module IO
    module TypedReads
      def initialize_typed_reads: () -> nil
      def read_into: (String dest, count: Integer) -> Integer
      def read: (?Integer? length, ?String? outbuf) -> String?
      def readpartial: (Integer maxlen, ?String? outbuf) -> String
      def read_exactly: (Integer count) -> String
      def getbyte: () -> Integer?
      def readbyte: () -> Integer
      def read_utf8: (?count: Integer?) -> String
      def read_string: (Encoding | String encoding, ?count: Integer?) -> String
      def read_line_utf8: () -> String?
      def skip: (Integer count) -> nil
      def eof?: () -> bool
      def each: () { (String) -> void } -> nil
              | () -> Enumerator[String, nil]
      def peek: () -> Dexpace::IO::BufferedSource
      def slice: (offset: Integer, count: Integer) -> Dexpace::IO::BufferedSource

      private

      def fill: (Integer min_bytes) -> Integer
    end
  end
end
```

- [ ] **Step 5: Add `require_relative "dexpace/io/typed_reads"` to `lib/dexpace.rb`**

After `dexpace/io`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/typed_reads_test.rb`
Expected: PASS, 14 tests. Then `bundle exec rubocop --fail-level=convention` and
`bundle exec rake rbs:validate steep`.

---

## Task 6: `TypedReads` — the typed reads and the `IO-9` ceiling

**Requirement IDs:** `IO-9`, `IO-11`, `IO-12`, `IO-13`, `IO-15`. **Design:** "`Dexpace::IO::TypedReads`
— the read vocabulary"; deviation **P3-4**.

> **IO-9** (SHOULD) — Materializing an entire buffer as one contiguous byte array via snapshot()
> SHOULD refuse sizes that exceed the host's maximum single-array allocation, failing loudly with an
> actionable message that points callers at streaming alternatives (stream bridge / copyTo) rather
> than crashing with a low-level allocation error. Length-bounded slice reads apply the same guarded,
> message-bearing cap. …

> **IO-12** (MUST) — An exact-count read (readByteArray(n) / readUtf8(n)) MUST return exactly n
> bytes/characters or fail with an EOF error if fewer than n remain; it MUST NOT return a short
> result.

> **IO-15** (MUST) — skip(byteCount) MUST advance past exactly byteCount bytes, failing with an EOF
> error if fewer remain (skip(0) MUST be a no-op even at/after EOF).

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/io/typed_reads.rb`
- Test: `gems/dexpace-core/test/dexpace/io/typed_reads_test.rb`

**Interfaces:**
- Consumes: Task 5's store, `#ensure_readable`, `#validate_count!` and `#ensure_buffered`.
- Produces: `#read_exactly(count)`, `#getbyte`, `#readbyte`, `#read_utf8(count: nil)`,
  `#read_string(encoding, count: nil)`, `#skip(count)`, `#eof?`, and the private
  `#guard_materialization!`, `#materialization_hint`, `#drain_all`, `#store_take_chunk` and
  `#resolve_encoding` that Tasks 8, 9 and 12 also use.

**The ceiling is written HERE, with the methods that materialise** — not bolted on as a later "add
the cap" task. There are six guarded sites across the sub-phase (`#read_exactly`, `#read_string`,
`#read_utf8`, `#read` with no count, a length-bounded slice read, and `Buffer#snapshot`), and a cap
added afterwards misses one of them with no gate that would notice.

**The two materialising reads left outside the guard are outside it deliberately.** `#read(length)`
and `#readpartial(maxlen)` are `IO-9`'s own stated exemption — "plain (non-slice) exact-count
buffered reads instead inherit whatever bounds check the underlying stream library performs" — and
they are the bridge methods, which must behave as `::IO`'s do. `#read_line_utf8` (Task 7) is the
other, and it is the one the design records as `OI-5`: `IO-14` fixes no maximum line length, and the
caller that reads lines from a stream an attacker controls is phase 7's SSE machine, which `SSE-11`
obliges to carry its own cap. Neither is an oversight to be "tidied up" by a later task.

- [ ] **Step 1: Add the failing tests**

Append both sections to `typed_reads_test.rb`, after Task 5's.

```ruby
  # ---- IO-11..IO-13, IO-15: the typed reads --------------------------------------------------

  test "read_exactly returns exactly count bytes across a chunk boundary" do
    assert_equal("abcd", source("ab", "cd", "ef").read_exactly(4))
  end

  # IO-12: "MUST NOT return a short result". And it consumes nothing when it raises, so the source
  # is still usable -- the no-partial-side-effect rule.
  test "read_exactly raises at end of stream and consumes nothing" do
    subject = source("abc")

    assert_raises(Dexpace::EndOfStreamError) { subject.read_exactly(4) }
    assert_equal("abc", subject.read_exactly(3))
  end

  test "read_exactly(0) is an empty BINARY String" do
    result = source.read_exactly(0)

    assert_equal("", result)
    assert_equal(::Encoding::BINARY, result.encoding)
  end

  test "readbyte returns an unsigned 0..255 and raises at end of stream" do
    subject = source("\xFF".b)

    assert_equal(255, subject.readbyte)
    assert_raises(Dexpace::EndOfStreamError) { subject.readbyte }
  end

  test "getbyte returns nil at end of stream, which is Ruby's own spelling" do
    subject = source("A")

    assert_equal(65, subject.getbyte)
    assert_nil(subject.getbyte)
  end

  # IO-11: readByteArray() with no count returns all remaining bytes, and an empty result when
  # already exhausted.
  test "read with no length drains everything and returns an empty String at end of stream" do
    subject = source("ab", "cd")

    assert_equal("abcd", subject.read)
    assert_equal("", subject.read)
  end

  # IO-13, and the only decode in 3a is a retag: no replacement policy and no charset default,
  # because HTTP-42's single decode boundary is 3b's Response#body_string.
  test "read_utf8 retags the drained bytes as UTF-8, non-ASCII round trip" do
    result = source("héllo".b).read_utf8

    assert_equal(::Encoding::UTF_8, result.encoding)
    assert_equal("héllo", result)
  end

  # count is a BYTE count, not a character count -- P3-9's keyword, and the design's own word.
  test "read_utf8 takes a byte count, not a character count" do
    assert_equal(2, source("héllo".b).read_utf8(count: 2).bytesize)
  end

  test "read_string retags with the encoding the caller named" do
    result = source("caf\xE9".b).read_string(::Encoding::ISO_8859_1)

    assert_equal(::Encoding::ISO_8859_1, result.encoding)
    assert_equal("café", result.encode(::Encoding::UTF_8))
  end

  test "read_string accepts an encoding name and rejects an unknown one" do
    assert_equal(::Encoding::UTF_8, source("ab").read_string("UTF-8").encoding)
    error = assert_raises(Dexpace::InvalidArgumentError) { source("ab").read_string("no-such") }
    assert_includes(error.message, "no-such")
  end

  test "read_string with a count raises at end of stream rather than returning short" do
    assert_raises(Dexpace::EndOfStreamError) { source("ab").read_string("UTF-8", count: 5) }
  end

  # IO-15, including the explicit "skip(0) MUST be a no-op even at/after EOF".
  test "skip advances past exactly count bytes" do
    subject = source("abcdef")
    subject.skip(2)

    assert_equal("cdef", subject.read)
  end

  test "skip raises when fewer bytes remain, and skip(0) is a no-op at and after EOF" do
    subject = source("ab")

    assert_raises(Dexpace::EndOfStreamError) { subject.skip(5) }
    subject.read
    assert_nil(subject.skip(0))
  end

  test "eof? is false while bytes remain and true once they are gone" do
    subject = source("a")

    refute(subject.eof?)
    subject.read_exactly(1)
    assert(subject.eof?)
  end

  # Phase 1's finding: Minitest's assert_predicate sends past `private` on the 3.2 floor, so
  # visibility is asserted with respond_to?.
  test "eof? is public and the hooks are not" do
    subject = source("a")

    assert_respond_to(subject, :eof?)
    refute(subject.respond_to?(:fill))
    refute(subject.respond_to?(:store_append))
  end
```

```ruby
  # ---- IO-9: the ceiling ---------------------------------------------------------------------

  # The guard is checked against the requested or known count BEFORE anything is allocated, so
  # these refuse while allocating nothing at all.
  test "read_exactly refuses a count over the ceiling without allocating" do
    error = assert_raises(Dexpace::StreamError) do
      source("ab").read_exactly(Dexpace::IO::MAX_MATERIALIZED_BYTES + 1)
    end

    assert_includes(error.message, "MAX_MATERIALIZED_BYTES")
    assert_includes(error.message, "#read_into")
  end

  test "read_string and read_utf8 refuse a count over the ceiling" do
    over = Dexpace::IO::MAX_MATERIALIZED_BYTES + 1

    assert_raises(Dexpace::StreamError) { source("ab").read_string("UTF-8", count: over) }
    assert_raises(Dexpace::StreamError) { source("ab").read_utf8(count: over) }
  end

  # IO-21 makes over-range slice CONSTRUCTION lazy, so the ceiling fires on the read and never on
  # the construction (P3-4). This asserts exactly that ordering.
  test "an over-ceiling slice constructs successfully and refuses on the read" do
    subject = source("ab")
    view = subject.slice(offset: 0, count: Dexpace::IO::MAX_MATERIALIZED_BYTES + 1)

    assert_instance_of(Dexpace::IO::BufferedSource, view)
    assert_raises(Dexpace::StreamError) { view.read }
  end

  test "a slice inside the ceiling drains normally" do
    assert_equal("ab", source("ab").slice(offset: 0, count: 1024).read)
  end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/typed_reads_test.rb`
Expected: FAIL — `undefined method 'read_exactly'` and the rest, 27 more tests failing than passed
in Task 5.

- [ ] **Step 3: Add the public methods, immediately before `protected`**

```ruby
      # IO-12: exactly count bytes or an EOF error. Never a short result, and never a partial
      # consumption -- the bytes stay buffered when it raises.
      def read_exactly(count)
        ensure_typed_reads_initialized
        validate_count!(count, name: "count")
        ensure_readable
        guard_materialization!(count)
        return (+"").b if count.zero?

        ensure_buffered(count)
        raise_end_of_stream("read_exactly(#{count})") if @dexpace_buffered < count

        store_take(count)
      end

      # IO-11/IO-16: the next byte as an unsigned 0..255, or nil at end of stream.
      def getbyte
        ensure_typed_reads_initialized
        ensure_readable
        fill_once_if_empty
        return nil if @dexpace_buffered.zero?

        store_take(1).getbyte(0)
      end

      # IO-11's readByte(): the next byte, or an EOF error when none remain.
      def readbyte
        ensure_typed_reads_initialized
        ensure_readable
        fill_once_if_empty
        raise_end_of_stream("readbyte") if @dexpace_buffered.zero?

        store_take(1).getbyte(0)
      end

      # IO-12/IO-13. `count` is a BYTE count, not a character count. With none, drains.
      def read_utf8(count: nil)
        read_string(::Encoding::UTF_8, count: count)
      end

      # IO-13. Retags the bytes with the encoding the caller named and validates nothing:
      # #valid_encoding? is the caller's question and HTTP-42's replacement policy is 3b's, at the
      # one decode boundary design §3.1 permits.
      def read_string(encoding, count: nil)
        ensure_typed_reads_initialized
        target = resolve_encoding(encoding)
        ensure_readable
        bytes =
          if count.nil?
            drain_all
          else
            validate_count!(count, name: "count")
            guard_materialization!(count)
            ensure_buffered(count)
            raise_end_of_stream("read_string(#{count})") if @dexpace_buffered < count

            store_take(count)
          end
        bytes.force_encoding(target)
      end

      # IO-15: exactly count bytes, an EOF error if fewer remain, and skip(0) a no-op even at or
      # after EOF.
      def skip(count)
        ensure_typed_reads_initialized
        validate_count!(count, name: "count")
        ensure_readable
        return nil if count.zero?

        ensure_buffered(count)
        raise_end_of_stream("skip(#{count})") if @dexpace_buffered < count

        store_drop(count)
        nil
      end

      # IO-11's exhausted(). May block while the upstream decides.
      def eof?
        ensure_typed_reads_initialized
        ensure_readable
        fill_once_if_empty
        @dexpace_buffered.zero?
      end

```

- [ ] **Step 4: Add the private helpers, at the end of the `private` section**

```ruby
      # #each's granularity: the whole remaining head chunk, so the wrapped body's own chunking
      # survives .over.
      def store_take_chunk
        return nil if @dexpace_buffered.zero?

        head = @dexpace_chunks.first
        store_take(head.bytesize - @dexpace_head)
      end

      # IO-9 (P3-4). The ceiling is checked against the known count before anything is allocated,
      # and against the running total on a drain, so nothing over it is ever materialised.
      def drain_all
        guard_materialization!(materialization_hint)
        out = (+"").b
        loop do
          chunk = store_take_chunk
          if chunk.nil?
            break if ensure_buffered(1).zero?

            next
          end
          out << chunk
          guard_materialization!(out.bytesize)
        end
        out
      end

      # The known remaining byte count when there is one -- a length-bounded view -- and nil
      # otherwise. IO-9's "length-bounded slice reads apply the same guarded, message-bearing cap".
      def materialization_hint
        remaining = dexpace_remaining_window
        remaining.is_a?(::Integer) ? remaining : nil
      end

      def guard_materialization!(count)
        return if count.nil?
        return if count <= Dexpace::IO::MAX_MATERIALIZED_BYTES

        raise Dexpace::StreamError,
              "refusing to materialize #{count} bytes as one String: the limit is " \
              "#{Dexpace::IO::MAX_MATERIALIZED_BYTES} bytes " \
              "(Dexpace::IO::MAX_MATERIALIZED_BYTES). Stream it instead -- #read_into, #each, " \
              "#slice or Buffer#copy_to."
      end

      def resolve_encoding(encoding)
        return encoding if encoding.is_a?(::Encoding)

        ::Encoding.find(encoding.to_s)
      rescue ::ArgumentError => error
        raise Dexpace::InvalidArgumentError,
              "unknown encoding #{encoding.inspect}: #{error.message}"
      end

```

`#materialization_hint` is what makes `IO-9`'s "length-bounded slice reads apply the same guarded,
message-bearing cap" work without a second mechanism: a view with a finite window knows its own
remaining byte count, a root source does not, and a drain guards on its running total either way.

- [ ] **Step 5: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/typed_reads_test.rb`
Expected: PASS for every test in Tasks 5 and 6's sections; the sections Tasks 7–9 add are not
written yet.

---

## Task 7: `TypedReads` — `#read_line_utf8`, the line machine

**Requirement IDs:** `IO-14`. **Design:** the `#read_line_utf8` row of the read-vocabulary table,
which marks this read **unbounded on purpose** — the one materialising read
`MAX_MATERIALIZED_BYTES` does not guard (P3-4, `OI-5`). Do not add the guard here: the bound belongs
to the caller, and phase 7's SSE machine is the one `SSE-11` obliges to carry it.

> **IO-14** (MUST) — readUtf8Line() MUST read up to and consume the next line terminator and return
> the preceding bytes decoded as UTF-8, treating both '\n' and '\r\n' as terminators; it MUST
> return null when the source is exhausted before any byte is read; a final line with no terminator
> MUST be returned as-is; and a lone '\r' not followed by '\n' MUST be kept as part of the line's
> content.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/io/typed_reads.rb`
- Test: `gems/dexpace-core/test/dexpace/io/typed_reads_test.rb`

**Interfaces:**
- Consumes: Task 5's `#store_take`, `#store_drop`, `#ensure_buffered` and the `NEWLINE` /
  `CARRIAGE_RETURN` constants.
- Produces: `#read_line_utf8 -> String?`, and the private `#store_index_of` and `#finish_line`.

**Its own task because it is hand-written and has the most cases.** It is never `#gets`: `$/` is
global and universal-newline handling depends on how the `IO` was opened, and neither is a property
this layer may inherit. Phase 7's SSE line machine is a **different** machine over the same
primitive and is not built here (boundary to phase 7).

- [ ] **Step 1: Add the failing tests**

The property test's generator is the part to read carefully: **no pool entry ends with a carriage
return**, because `"x\r"` followed by a `"\n"` terminator is a `\r\n` terminator by `IO-14` and
would make the generator wrong rather than the machine.

```ruby
  # ---- IO-14: the line machine ---------------------------------------------------------------

  test "read_line_utf8 treats \\n as a terminator and does not return it" do
    subject = source("one\ntwo\n")

    assert_equal("one", subject.read_line_utf8)
    assert_equal("two", subject.read_line_utf8)
    assert_nil(subject.read_line_utf8)
  end

  test "read_line_utf8 treats \\r\\n as a terminator" do
    assert_equal("one", source("one\r\ntwo").read_line_utf8)
  end

  # IO-14: "a lone '\\r' not followed by '\\n' MUST be kept as part of the line's content".
  test "read_line_utf8 keeps a lone carriage return as content" do
    assert_equal("a\rb", source("a\rb\n").read_line_utf8)
  end

  test "read_line_utf8 returns a final unterminated line as-is" do
    subject = source("tail")

    assert_equal("tail", subject.read_line_utf8)
    assert_nil(subject.read_line_utf8)
  end

  test "read_line_utf8 returns nil when exhausted before any byte" do
    assert_nil(source.read_line_utf8)
  end

  test "read_line_utf8 returns an empty line for a bare terminator" do
    assert_equal("", source("\nx").read_line_utf8)
  end

  test "read_line_utf8 spans chunk boundaries and returns UTF-8" do
    subject = source("hél".b, "lo\nrest")

    line = subject.read_line_utf8
    assert_equal(::Encoding::UTF_8, line.encoding)
    assert_equal("héllo", line)
  end

  # A bounded property test (styleguide 11.7, phase 0's #sample). The generator mixes every
  # terminator IO-14 names, so the machine is exercised on inputs nobody wrote by hand.
  test "read_line_utf8 reconstructs any mix of terminators" do
    # No pool entry ends with a carriage return, because "x\r" + "\n" is a \r\n terminator by
    # IO-14 and would make the generator, not the machine, wrong.
    pool = ["", "a", "ab", "a\rb", "\rx", "x\ry"].freeze

    sample(count: 48) do |rng|
      lines = Array.new(rng.rand(1..5)) { pool.sample(random: rng) }
      terminators = Array.new(lines.length) { ["\n", "\r\n"].sample(random: rng) }
      text = lines.zip(terminators).map(&:join).join
      expected = lines.dup
      if rng.rand(2).zero?
        text = text[0...-terminators.last.length]
        expected.pop if expected.last.empty?
      end

      subject = source(text.b)
      read = []
      while (line = subject.read_line_utf8)
        read << line
      end

      assert_equal(expected, read)
    end
  end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/typed_reads_test.rb`
Expected: FAIL — `undefined method 'read_line_utf8'`, 8 tests.

- [ ] **Step 3: Add the public method, immediately before `protected`**

```ruby
      # IO-14. Hand-implemented over the byte store, never #gets: $/ is global and universal
      # newline handling depends on how the IO was opened. "\n" and "\r\n" terminate, a lone "\r"
      # is content, a final unterminated line comes back as-is, nil when exhausted before a byte.
      def read_line_utf8
        ensure_typed_reads_initialized
        ensure_readable
        scanned = 0
        loop do
          index = store_index_of(NEWLINE, scanned)
          return finish_line(store_take(index), terminated: true) unless index.nil?

          scanned = @dexpace_buffered
          break if ensure_buffered(scanned + 1) == scanned
        end
        return nil if @dexpace_buffered.zero?

        finish_line(store_take(@dexpace_buffered), terminated: false)
      end

```

- [ ] **Step 4: Add the private helpers, at the end of the `private` section**

```ruby
      def store_index_of(byte, from)
        position = 0
        head_offset = @dexpace_head
        @dexpace_chunks.each do |chunk|
          available = chunk.bytesize - head_offset
          if position + available > from
            start = head_offset + (from > position ? from - position : 0)
            found = chunk.index(byte, start)
            return position + (found - head_offset) unless found.nil?
          end
          position += available
          head_offset = 0
        end
        nil
      end

      def finish_line(bytes, terminated:)
        if terminated
          store_drop(1)
          bytes = bytes.byteslice(0, bytes.bytesize - 1) if bytes.end_with?(CARRIAGE_RETURN)
        end
        bytes.force_encoding(::Encoding::UTF_8)
      end

```

`#store_index_of` searches across chunk boundaries and respects a partially consumed head chunk,
which is what makes the line rule survive a slice window. The `\r` is stripped only when it
immediately precedes the `\n` the scan found, which is exactly `IO-14`'s "a lone '\r' not followed
by '\n' MUST be kept".

- [ ] **Step 5: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/typed_reads_test.rb`
Expected: PASS for Tasks 5–7's sections, the property test included at its default 48 samples and
seed.

---

## Task 8: `TypedReads` — the host-native bridge and `#each`

**Requirement IDs:** `IO-16`, and design §10.2's canonical body representation. **Design:** "R4 —
whether `IO-16`'s 'satisfied by construction' survives `IO-6`"; deviations **P3-2** and, new here,
**P3-13**.

> **IO-16** (SHOULD) — A BufferedSource SHOULD provide a read-only **host-native** byte-stream bridge
> whose single-byte read returns the next byte as an unsigned value 0..255 or -1 at end, and whose
> bulk read returns the count read or -1 at end; closing the bridge MUST close (or invalidate) the
> owning source. …

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/io/typed_reads.rb`
- Test: `gems/dexpace-core/test/dexpace/io/typed_reads_test.rb`

**Interfaces:**
- Consumes: Task 5's store and Task 6's `#drain_all` and `#store_take_chunk`.
- Produces: `#read(length = nil, outbuf = nil) -> String?`, `#readpartial(maxlen, outbuf = nil)`,
  `#each { |String| }`, and the private `#read_up_to`. Task 10's `IO.copy_stream` tests drive them;
  Task 10's `.over` depends on `#each`'s granularity.

**This is the task the whole sub-phase turns on.** `IO.copy_stream` — literally what
`Net::HTTP#send_request_with_body_stream` calls, so it is the code path every streamed upload takes
— hands `#readpartial` **one buffer object it reuses on every call** and expects it overwritten.
`IO-1`'s primitive appends. The two cannot be one method, which is P3-1, and this is where the other
half of that decision is written down in code.

- [ ] **Step 1: Add the failing tests**

The first test is the one to protect: it asserts both behaviours against the same non-empty BINARY
buffer in a single test, so a later "simplification" that merges `#read` and `#read_into` turns red.

```ruby
  # ---- IO-16: the host-native bridge ---------------------------------------------------------

  # THE assertion the whole sub-phase turns on. IO.copy_stream hands #readpartial ONE buffer that
  # it reuses on every call and expects overwritten; IO-1's primitive appends. Both are asserted
  # here against the same non-empty BINARY buffer in one test, so a later "simplification" that
  # merges them turns red.
  test "read overwrites outbuf while read_into appends to it" do
    buffer = +"seed".b

    source("abcd").read(2, buffer)
    assert_equal("ab", buffer)

    source("wxyz").read_into(buffer, count: 2)
    assert_equal("abwx", buffer)
  end

  test "readpartial overwrites outbuf too" do
    buffer = +"seed".b

    source("abcd").readpartial(2, buffer)

    assert_equal("ab", buffer)
  end

  # P3-2: the bridge signals end of stream the host-native way, because IO-16's own word is
  # "host-native" and -1 is the reference host's InputStream convention.
  test "read returns nil at end of stream for a positive length, and clears outbuf" do
    buffer = +"seed".b

    assert_nil(source.read(4, buffer))
    assert_equal("", buffer)
  end

  test "readpartial raises Dexpace::EndOfStreamError at end of stream" do
    assert_raises(Dexpace::EndOfStreamError) { source.readpartial(4) }
  end

  # P3-13. Ruby's own readers disagree with each other and across the supported floor: ::IO#read
  # PRESERVES the destination's tag on 3.2.11, 3.4.10 and 4.0.6, while StringIO#read changed at
  # exactly Ruby 3.4 -- ASCII-8BIT on 3.2.11, UTF-8 from 3.4.10. 3a pins BINARY instead, so the
  # answer is the same on every matrix row and behind every backing stream. IO.copy_stream does
  # not care, which is what keeps the bridge claim true.
  test "read and readpartial leave outbuf tagged BINARY whatever it arrived as" do
    utf8_buffer = +""
    source("héllo".b).read(2, utf8_buffer)
    assert_equal(::Encoding::BINARY, utf8_buffer.encoding)

    other = +""
    source("héllo".b).readpartial(2, other)
    assert_equal(::Encoding::BINARY, other.encoding)
  end

  test "read(0) is an empty String and readpartial(0) never raises" do
    assert_equal("", source.read(0))
    assert_equal("", source.readpartial(0))
  end

  # Ruby's own split, which is what makes the bridge a bridge: #read(n) keeps filling until it has
  # n bytes or the stream ends, while #readpartial returns what is already available.
  test "read fills up to length while readpartial returns what is available" do
    assert_equal("abcd", source("ab", "cd").read(4))
    assert_equal("ab", source("ab", "cd").readpartial(4))
  end

  # ---- §10.2: #each --------------------------------------------------------------------------

  # The granularity is whatever the upstream produced, because .over must preserve the wrapped
  # body's own chunking for BODY-17's byte-exact mirroring to mean what it says.
  test "each yields the upstream's own chunks, in order, tagged BINARY" do
    yielded = []

    source("ab", "cde", "f").each { |chunk| yielded << [chunk.dup, chunk.encoding] }

    assert_equal([["ab", ::Encoding::BINARY], ["cde", ::Encoding::BINARY],
                  ["f", ::Encoding::BINARY],], yielded,)
  end

  test "each without a block returns an Enumerator" do
    assert_kind_of(::Enumerator, source("ab").each)
    assert_equal(%w[ab cd], source("ab", "cd").each.to_a)
  end

  test "each resumes from the cursor when bytes were already consumed" do
    subject = source("abcd", "ef")
    subject.read_exactly(1)

    assert_equal(%w[bcd ef], subject.each.to_a)
  end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/typed_reads_test.rb`
Expected: FAIL — `undefined method 'read'` and `'readpartial'` and `'each'`, 9 tests.

- [ ] **Step 3: Add the public methods, immediately before `protected`**

```ruby
      # IO-16's host-native bulk read: Ruby's semantics exactly, so IO.copy_stream can drive it.
      # It OVERWRITES outbuf where #read_into appends, keeps filling until it has `length` bytes or
      # the stream ends, and returns nil at EOF for a positive length and "" at EOF with no length.
      # With no length it is also IO-11's count-less byte-array read.
      #
      # P3-13: outbuf comes back tagged Encoding::BINARY whatever it arrived as. ::IO#read
      # preserves the destination's tag on all three interpreters and StringIO#read changed at
      # exactly Ruby 3.4, so Ruby's own readers disagree with each other and across this port's
      # floor; pinning BINARY is what makes 3a's answer the same on every matrix row and behind
      # every backing stream. IO.copy_stream does not read the tag, which is what keeps the bridge
      # claim true.
      def read(length = nil, outbuf = nil)
        ensure_typed_reads_initialized
        validate_count!(length, name: "length") unless length.nil?
        ensure_readable
        data = length.nil? ? drain_all : read_up_to(length)
        if data.nil?
          outbuf&.replace((+"").b)
          return nil
        end
        return data if outbuf.nil?

        outbuf.replace(data)
      end

      # IO-16's host-native partial read. Overwrites outbuf; raises at EOF, and the class is a
      # ::EOFError subclass so IO.copy_stream terminates on it rather than propagating it.
      def readpartial(maxlen, outbuf = nil)
        ensure_typed_reads_initialized
        validate_count!(maxlen, name: "maxlen")
        ensure_readable
        data =
          if maxlen.zero?
            (+"").b
          else
            fill_once_if_empty
            raise_end_of_stream("readpartial(#{maxlen})") if @dexpace_buffered.zero?

            store_take([maxlen, @dexpace_buffered].min)
          end
        return data if outbuf.nil?

        outbuf.replace(data)
      end

      # Design §10.2: yields BINARY chunks until exhausted, so a source IS a canonical body
      # representation. The granularity is whatever the upstream produced -- .over must preserve
      # the wrapped body's own chunking for BODY-17's byte-exact mirroring to mean what it says.
      #
      # §7.1: the resource lives on the instance and #close is on the instance, so an Enumerator
      # abandoned mid-#next leaks nothing #close would not still release.
      def each
        return to_enum(:each) unless block_given?

        ensure_typed_reads_initialized
        ensure_readable
        loop do
          chunk = store_take_chunk
          if chunk.nil?
            break if ensure_buffered(1).zero?

            next
          end
          yield chunk
        end
        nil
      end

```

- [ ] **Step 4: Add the private helper, at the end of the `private` section**

```ruby
      def read_up_to(length)
        return (+"").b if length.zero?

        ensure_buffered(length)
        return nil if @dexpace_buffered.zero?

        store_take([length, @dexpace_buffered].min)
      end

```

- [ ] **Step 5: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/typed_reads_test.rb`
Expected: PASS for Tasks 5–8's sections.

- [ ] **Step 6: Record the deviation**

Add **P3-13** to the phase document's `## Deviation Ledger` — the numbering continues from the
design's P3-12 — and to `docs/deviations.md` when the phase lands:

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P3-13 | `#read` and `#readpartial` leave `outbuf` tagged `Encoding::BINARY` whatever tag it arrived with, where `::IO#read` preserves the destination's tag | `IO-16`; design §3.1's BINARY rule | The bridge's contract is "Ruby's semantics", and on this one point Ruby's own readers disagree with each other and across this port's floor: verified that `::IO#read(n, buf)` preserves a UTF-8 destination's tag on 3.2.11, 3.4.10 and 4.0.6, while `StringIO#read(n, buf)` gives ASCII-8BIT on 3.2.11 and UTF-8 from 3.4.10 — the same floor-straddling shape design §3.5 pins `URI::RFC3986_PARSER` against. Pinning BINARY makes 3a's answer identical on every matrix row and behind every backing stream, and §3.1's "core retags on ingress rather than trusting a declared charset" points the same way. `IO.copy_stream` does not read the destination's tag, so the bridge claim is unaffected — verified end to end in Task 10 |

---

## Task 9: `TypedReads` — `#peek` and `#slice`, the non-consuming views

**Requirement IDs:** `IO-19`, `IO-20`, `IO-21`, `IO-22`, `IO-23`, `IO-24`. **Design:** "The view
retention rule, which the specification does not state and 3a therefore does"; deviation **P3-5**.

> **IO-21** (MUST) — Slice offset overflow MUST be detected LAZILY: constructing a slice whose offset
> exceeds the source size MUST succeed, and the overflow MUST surface only on first read as an
> empty/EOF result … Negative offset or negative byteCount MUST be rejected eagerly at construction.

> **IO-22** (MUST) — Closing a slice MUST NOT close its parent source and MUST NOT advance the
> parent's cursor; conversely, closing the parent source MUST invalidate every outstanding slice
> derived from it so that subsequent reads on those slices fail loudly (a state/IO error), never
> returning stale or arbitrary bytes.

> **IO-23** (MUST) — Multiple slices (and peeks) of the same source MUST be mutually independent
> (each has its own cursor and byte budget), and a slice-of-a-slice MUST compose offsets additively
> and cap its window at the outer slice's remaining bytes.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/io/typed_reads.rb`
- Test: `gems/dexpace-core/test/dexpace/io/typed_reads_test.rb`

**Interfaces:**
- Consumes: Task 5's protected view protocol.
- Produces: `#peek -> BufferedSource` and `#slice(offset:, count:) -> BufferedSource`, and the
  private `#build_view`. Both name `Dexpace::IO::BufferedSource.__dexpace_view` at call time, so
  Task 10 must land before either can run — the tests in this task are written now and go green in
  Task 10.

**The hardest of the five, and the one with a rule the specification does not state.** A view pins
the parent's cursor at construction and reads a window relative to that pin, driving the parent's
`#fill` **without advancing the parent's cursor**. **The parent holds nothing back for it**: its
retention floor is its own cursor, and a view whose next byte that cursor has already passed raises
`Dexpace::ClosedError` (P3-5) rather than reading somewhere else, which is the only reading `IO-22`'s
"never returning stale or arbitrary bytes" allows. That rule is recursive, because a view is itself a
`BufferedSource`: reading an outer slice moves *its* cursor, so an inner slice taken from it before
that read is invalidated too, even though the underlying source has consumed nothing. Asserted, not
left to be discovered.

**`#peek` and `#slice` return a `BufferedSource`**, not a new public type — a view is a
`BufferedSource` constructed in view mode. That makes `IO-23`'s slice-of-a-slice free, keeps the
`IO-16` bridge claim true of views, and adds no `NFR-4`-locked constant.

- [ ] **Step 1: Add the failing tests**

```ruby
  # ---- IO-19..IO-24: the views ---------------------------------------------------------------

  # IO-19: "a non-consuming view over the whole remaining source such that reads from the peek view
  # do not advance the original source's cursor".
  test "peek does not advance the parent cursor" do
    subject = source("abcdef")

    assert_equal("abcdef", subject.peek.read)
    assert_equal("abcdef", subject.read)
  end

  test "peek is a BufferedSource, not a new public type" do
    assert_instance_of(Dexpace::IO::BufferedSource, source("ab").peek)
  end

  # IO-20.
  test "slice exposes at most count bytes starting offset bytes ahead of the cursor" do
    subject = source("abcdef")

    assert_equal("cd", subject.slice(offset: 2, count: 2).read)
    assert_equal("abcdef", subject.read)
  end

  test "reading past a slice window behaves as end of window" do
    subject = source("abcdef")
    view = subject.slice(offset: 0, count: 2)

    assert_equal("ab", view.read)
    assert_equal("", view.read)
    assert_raises(Dexpace::EndOfStreamError) { view.read_exactly(1) }
    assert_nil(view.read_line_utf8)
  end

  # IO-21: overflow is LAZY. Construction succeeds; the overflow surfaces on first read.
  test "a slice whose offset exceeds the source constructs successfully and is empty on read" do
    subject = source("abc")
    view = subject.slice(offset: 99, count: 5)

    assert_instance_of(Dexpace::IO::BufferedSource, view)
    assert_equal("", view.read)
    assert_nil(view.read_line_utf8)
    assert_raises(Dexpace::EndOfStreamError) { view.readbyte }
  end

  test "slice rejects a negative offset or count eagerly at construction" do
    subject = source("abc")

    assert_raises(Dexpace::InvalidArgumentError) { subject.slice(offset: -1, count: 1) }
    assert_raises(Dexpace::InvalidArgumentError) { subject.slice(offset: 0, count: -1) }
  end

  # IO-23: mutually independent cursors and budgets.
  test "two slices of one source are mutually independent" do
    subject = source("abcdef")
    first = subject.slice(offset: 0, count: 4)
    second = subject.slice(offset: 0, count: 4)

    assert_equal("ab", first.read(2))
    assert_equal("abcd", second.read)
    assert_equal("cd", first.read)
  end

  # IO-23: "a slice-of-a-slice MUST compose offsets additively and cap its window at the outer
  # slice's remaining bytes".
  test "a slice of a slice composes additively and is capped by the outer window" do
    subject = source("abcdefgh")
    outer = subject.slice(offset: 1, count: 4)

    assert_equal("cd", outer.slice(offset: 1, count: 2).read)
    assert_equal("cde", outer.slice(offset: 1, count: 99).read)
  end

  # P3-5 applied recursively, which it is because a view IS a BufferedSource: reading the OUTER
  # slice moves that slice's own cursor past the inner slice's pin, so the inner slice fails
  # loudly -- even though the underlying source has consumed nothing. Pinned rather than left to
  # be discovered, because IO-23's "mutually independent" is about slices of the SAME source and a
  # reader can take it further than it goes.
  test "reading an outer slice invalidates an inner slice taken from it" do
    subject = source("abcdefgh")
    outer = subject.slice(offset: 1, count: 4)
    inner = outer.slice(offset: 1, count: 2)

    assert_equal("bcde", outer.read)
    assert_raises(Dexpace::ClosedError) { inner.read }
  end

  test "slice composition holds over random offsets and budgets" do
    sample(count: 48) do |rng|
      text = ("a".."z").to_a.join
      outer_offset = rng.rand(0..6)
      outer_count = rng.rand(0..8)
      inner_offset = rng.rand(0..4)
      inner_count = rng.rand(0..8)

      outer = source(text.b).slice(offset: outer_offset, count: outer_count)
      window = text.byteslice(outer_offset, outer_count).to_s
      # Not #clamp: the window can be shorter than the inner offset, and clamp raises when its
      # own maximum is below its minimum. IO-23 caps at the outer slice's REMAINING bytes, which
      # is zero once the offset is past the end.
      available = [window.bytesize - inner_offset, 0].max
      expected = window.byteslice(inner_offset, [inner_count, available].min).to_s

      assert_equal(expected, outer.slice(offset: inner_offset, count: inner_count).read)
    end
  end

  # IO-22, first half.
  test "closing a slice closes neither the parent nor its cursor" do
    subject = source("abcdef")
    view = subject.slice(offset: 0, count: 2)
    view.read
    view.close

    refute(subject.closed?)
    assert_equal("abcdef", subject.read)
  end

  # IO-24: "Reading from a slice AFTER it has been explicitly closed MUST fail loudly (a state
  # error) for every read form, distinct from normal EOF."
  test "every read form on an explicitly closed slice raises ClosedError, not an EOF error" do
    view = source("abcdef").slice(offset: 0, count: 4)
    view.close

    assert_raises(Dexpace::ClosedError) { view.read }
    assert_raises(Dexpace::ClosedError) { view.read_exactly(1) }
    assert_raises(Dexpace::ClosedError) { view.readbyte }
    assert_raises(Dexpace::ClosedError) { view.getbyte }
    assert_raises(Dexpace::ClosedError) { view.readpartial(1) }
    assert_raises(Dexpace::ClosedError) { view.read_line_utf8 }
    assert_raises(Dexpace::ClosedError) { view.read_utf8 }
    assert_raises(Dexpace::ClosedError) { view.skip(1) }
    assert_raises(Dexpace::ClosedError) { view.eof? }
    assert_raises(Dexpace::ClosedError) { view.read_into(+"".b, count: 1) }
    assert_raises(Dexpace::ClosedError) { view.each { |_| nil } }
  end

  # IO-22, second half: "closing the parent source MUST invalidate every outstanding slice derived
  # from it so that subsequent reads on those slices fail loudly ... never returning stale or
  # arbitrary bytes".
  test "closing the parent invalidates every outstanding slice" do
    subject = source("abcdef")
    first = subject.slice(offset: 0, count: 2)
    second = subject.peek
    subject.close

    assert_raises(Dexpace::ClosedError) { first.read }
    assert_raises(Dexpace::ClosedError) { second.read }
  end

  # P3-5, which the specification does not state and 3a therefore does. IO-22's "never returning
  # stale or arbitrary bytes" is the only normative anchor and it points one way.
  test "a parent read past a live view's pin makes that view fail loudly, not return other bytes" do
    subject = source("abcdef")
    view = subject.slice(offset: 0, count: 4)
    subject.read_exactly(3)

    error = assert_raises(Dexpace::ClosedError) { view.read }

    assert_includes(error.message, "behind")
  end

  test "a view that has already pulled its window is unaffected by a later parent read" do
    subject = source("abcdef")
    view = subject.slice(offset: 0, count: 4)

    assert_equal("abcd", view.read)
    subject.read_exactly(5)
    assert_equal("", view.read)
  end
```

And the last section of the file, the includer contract, which belongs here because
`#ensure_typed_reads_initialized` and the `#fill` hook are now exercised through every public entry
point:

```ruby
  # ---- the includer contract -----------------------------------------------------------------

  test "an includer that never calls initialize_typed_reads fails loudly" do
    unready = Class.new do
      include Dexpace::IO::TypedReads
      include Dexpace::Closeable

      def initialize = initialize_closeable(owned: true)
    end.new

    assert_raises(Dexpace::SeamError) { unready.read }
  end

  test "an includer that supplies no fill hook fails loudly" do
    hookless = Class.new do
      include Dexpace::IO::TypedReads
      include Dexpace::Closeable

      def initialize
        initialize_closeable(owned: true)
        initialize_typed_reads
      end
    end.new

    assert_raises(::NotImplementedError) { hookless.read }
  end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/typed_reads_test.rb`
Expected: FAIL — `undefined method 'peek'`, 16 tests.

- [ ] **Step 3: Add the public methods, immediately before `protected`**

```ruby
      # IO-19: a non-consuming view over the whole remaining source.
      def peek
        ensure_typed_reads_initialized
        ensure_readable
        build_view(offset: 0, window: ::Float::INFINITY)
      end

      # IO-20/IO-21/IO-23. Negative offset or count is rejected eagerly; an offset past the end is
      # detected LAZILY, on the first read, as an empty/EOF result.
      def slice(offset:, count:)
        ensure_typed_reads_initialized
        validate_count!(offset, name: "offset")
        validate_count!(count, name: "count")
        ensure_readable
        build_view(offset: offset, window: count)
      end

```

- [ ] **Step 4: Add the private helper, at the end of the `private` section**

```ruby
      # IO-23: the child's offset composes additively (the pin is measured from this object's own
      # cursor) and its window is capped at this object's remaining window.
      def build_view(offset:, window:)
        headroom = dexpace_remaining_window - offset
        headroom = 0 if headroom.negative?
        view = Dexpace::IO::BufferedSource.__dexpace_view(
          parent: self, pin: @dexpace_consumed + offset, window: [window, headroom].min,
        )
        dexpace_register_view(view)
        view
      end
```

- [ ] **Step 5: Run the test and expect it to still fail, for one reason only**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/typed_reads_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::IO::BufferedSource`, on the view tests only.
**Everything else in this file must be green.** Task 10 supplies the constant; this is the one place
in the sub-phase where a task's own tests do not go green inside the task, and it is stated rather
than hidden because the alternative — standing `BufferedSource` up before the vocabulary it needs —
would invert the dependency the design fixed.

- [ ] **Step 6: Confirm the assembled file matches**

Run: `bundle exec rubocop --fail-level=convention gems/dexpace-core/lib/dexpace/io/typed_reads.rb`
Expected: the file's public methods in exactly this order — `initialize_typed_reads`, `read_into`,
`read_exactly`, `getbyte`, `readbyte`, `read_utf8`, `read_string`, `skip`, `eof?`,
`read_line_utf8`, `read`, `readpartial`, `each`, `peek`, `slice` — then `protected`, then `private`,
and **no layout, naming or style offense**: the five fragments each end with the blank line the next
one needs, so `Layout/EmptyLineBetweenDefs` and `Layout/EmptyLinesAroundAccessModifier` are satisfied
by the concatenation itself.

Three offenses are **expected here and are not this task's to fix**, all of them in the
already-repository-wide family `OI-6` records: `Metrics/ModuleLength` (this module is the whole read
vocabulary by design, and phase 0 configured `MethodLength`, `ParameterLists` and `BlockNesting` but
never `ModuleLength`), `Metrics/AbcSize` on `#store_take` and `#store_peek` (phase 1's `lib/` already
carries eight of these), and `Naming/RescuedExceptionsVariableName`, whose `e` this repository has
written as `error` since phase 1. **`Style/SymbolProc` on `@dexpace_views.each { |view|
view.dexpace_invalidate }` must not be autocorrected**: `#dexpace_invalidate` is `protected`, and
`&:dexpace_invalidate` sends it publicly — verified `NoMethodError: protected method
'dexpace_invalidate' called`. The block form is load-bearing, not a style lapse.

---
## Task 10: `Dexpace::IO::BufferedSource` — the reader

**Requirement IDs:** `IO-6`, `IO-16`, `IO-19`–`IO-24`, `IO-37`, `IO-38`, `IO-41`, `IO-42`; design
§10.2 and §7.1. **Design:** "R3 — `IO-6`, stated once, without `SEAM-3`"; "`Dexpace::IO::BufferedSource`
— the reader"; deviations **P3-3**, **P3-5**, **P3-11**, **P3-12**.

> **IO-6** (MUST) — When a provider wraps a caller-supplied underlying stream (readable stream ->
> buffered source, writable stream -> buffered sink), the returned wrapper MUST take ownership of
> that stream: closing the wrapper closes the underlying stream. The same holds for the stream
> bridges obtained from a buffered source/sink (closing the bridge closes the owning source/sink).
> Wrapping a plain byte array owns no external resource.

> **IO-37** (MUST) — All streaming instances … are single-threaded contracts: they are NOT required
> to be safe for concurrent use, and callers MUST serialize external access when sharing one across
> threads. Independent views (slices, peeks) MAY be used from different threads, but each individual
> view remains single-threaded.

> **IO-38** (MUST) — Even though individual instances are single-threaded, the CLOSE state of a
> source/buffer MUST be observable across threads to the slices derived from it, so that a close on
> one thread reliably invalidates a slice being read on another (no torn or stale reads).

> **IO-42** (MUST) — A buffered source/sink that wraps an external stream MUST reject
> read/write/flush/emit attempts made after close() with an I/O error, so use-after-close of a real
> resource fails loudly. …

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/io/buffered_source.rb`,
  `gems/dexpace-core/sig/dexpace/io/buffered_source.rbs`,
  `gems/dexpace-core/test/support/fake_chunked.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/io/buffered_source_test.rb`

**Interfaces:**
- Consumes: Tasks 5–9's `Dexpace::IO::TypedReads` (including its protected view protocol), Task 2's
  `Dexpace::Closeable`, Task 3's error classes.
- Produces: `Dexpace::IO::BufferedSource` with `.wrapping(io)` and its block form, `.of_bytes(string)`,
  `.over(chunked)`, `.__dexpace_view(parent:, pin:, window:)`, `#view?` and `#owns_upstream?`;
  `.new` is `private_class_method`. Tasks 11, 13 and 14 use it as a `_Source`; Task 9's view tests go
  green here.

**Ownership is two frozen construction-time facts.** `Closeable`'s `@owned` is always `true` — a
source always owns its own buffer — and a separate frozen `@dexpace_owns_upstream` decides whether
`#release` also closes the upstream. `.wrapping` owns; `.of_bytes` and `.over` own nothing. There is
**no borrowing variant of `.wrapping`**, because a wrapper that did not close what it wrapped is the
exact object `IO-6` prohibits (P3-12), and `.new` is private so ownership cannot be set through an
unnamed argument (P3-11).

**`.over` is the one stated exception, and it is design §3.1's rather than this plan's.** Closing a
`.over` source drains and discards its own buffer and never calls `#close` on what it wrapped,
because its callers are always downstream of something that already owns the response
(`message-bodies/f060d944`). This is what removes the one 3a→3b edge that would have run backwards.

**Cite `IO-6` and design §10.12, never `SEAM-3`.** Design §10.1 retires `SEAM-3` with the byte-stream
provider seam and phase 2 shipped it 🚫; the surviving normative home of ownership-on-wrap is `IO-6`,
which is `OI-2` and the subject of `docs/knowledge/notes/message-bodies.md`.

- [ ] **Step 1: Write `test/support/fake_chunked.rb`**

Required explicitly by the suites that use it, never from `test_helper.rb`
(`testing/180b5f41`). It exists because **no real stream can produce what the requirement is about**:
a `#each`-yielding-chunks body whose chunks are frozen literals is the ordinary Rack shape and the
exact input on which `force_encoding` raises.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Design §10.2's canonical body representation: an object responding to #each and nothing else, so
# it is exactly Dexpace::IO::_Chunked. Under this file's own frozen_string_literal pragma the
# chunks it yields from a literal array are FROZEN, which is the ordinary Rack shape and the exact
# input on which force_encoding raises (verified fact 3).
#
# `ensure_ran` records whether the #each body's ensure ran, which is §7.1's residue test, and the
# chunk list is scripted, so `FakeChunked.new("ab", "", "cd")` yields an EMPTY chunk between two
# non-empty ones -- the one input no StringIO and no IO.pipe can produce, and the one that tells
# "no bytes this time" apart from "no bytes ever".
class FakeChunked
  attr_reader :ensure_ran, :yielded

  def initialize(*chunks)
    @chunks = chunks
    @ensure_ran = false
    @yielded = 0
  end

  def each
    @chunks.each do |chunk|
      @yielded += 1
      yield chunk
    end
  ensure
    @ensure_ran = true
  end

  # The frozen non-ASCII literals every encoding test in 3a uses: an ASCII-only fixture would pass
  # under exactly the bug (verified fact 4).
  def self.frozen_utf8
    new("héllo ", "wörld")
  end
end
```

- [ ] **Step 2: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_chunked"
require "stringio"

# IO-6, IO-11..IO-24, IO-37, IO-38, IO-41, IO-42, and design §10.2.
#
# StringIO and IO.pipe stand in for a real stream and are not stubs: they give genuine EOF, genuine
# blocking and the genuine IOError a closed handle raises. IO.pipe in particular is what makes the
# IO-38 test real rather than simulated -- a reader really does block.
class DexpaceBufferedSourceTest < DexpaceTestCase
  def pipe
    reader, writer = ::IO.pipe
    yield reader, writer
  ensure
    reader.close unless reader.closed?
    writer.close unless writer.closed?
  end

  # ---- IO-6: ownership -----------------------------------------------------------------------

  # IO-6: "the returned wrapper MUST take ownership of that stream: closing the wrapper closes the
  # underlying stream." There is deliberately no borrowing variant (P3-12).
  test "wrapping takes ownership: closing the source closes the wrapped stream" do
    stream = StringIO.new("abc")
    source = Dexpace::IO::BufferedSource.wrapping(stream)

    assert(source.owns_upstream?)
    source.close
    assert(stream.closed?)
  end

  test "wrapping with a block closes on a normal exit and returns the block's value" do
    stream = StringIO.new("abc")

    result = Dexpace::IO::BufferedSource.wrapping(stream) { |source| source.read }

    assert_equal("abc", result)
    assert(stream.closed?)
  end

  test "wrapping with a block closes on an exception too" do
    stream = StringIO.new("abc")

    assert_raises(RuntimeError) do
      Dexpace::IO::BufferedSource.wrapping(stream) { raise "boom" }
    end
    assert(stream.closed?)
  end

  # IO-6's last sentence: "Wrapping a plain byte array owns no external resource."
  test "of_bytes owns nothing and takes an independent copy of the input" do
    original = +"abc"
    source = Dexpace::IO::BufferedSource.of_bytes(original)
    original << "def"

    refute(source.owns_upstream?)
    assert_equal("abc", source.read)
  end

  test "of_bytes result is not affected by, and does not affect, the caller's String" do
    original = +"abc"
    source = Dexpace::IO::BufferedSource.of_bytes(original)

    assert_equal("abc", source.read)
    assert_equal("abc", original)
  end

  # R3's one stated exception, and it is design §3.1's rather than this phase's: .over takes no
  # ownership, because its callers are always downstream of something that already owns the
  # response. This is what removes the one 3a->3b edge that would have run backwards.
  test "over owns nothing and never closes what it wrapped" do
    closed = false
    body = Object.new
    body.define_singleton_method(:each) { |&block| block.call("ab") }
    body.define_singleton_method(:close) { closed = true }

    source = Dexpace::IO::BufferedSource.over(body)
    source.read
    source.close

    refute(source.owns_upstream?)
    refute(closed)
  end

  # R1's real mitigation, asserted rather than argued: core never writes is_a?(IO), so every one
  # of these works. A nominal test would be silently false inside `module Dexpace` (OI-3).
  test "wrapping accepts a real IO, a StringIO and a bare readpartial-shaped object" do
    duck = Class.new do
      def initialize = @sent = false

      def readpartial(_maxlen, _outbuf = nil)
        raise ::EOFError if @sent

        @sent = true
        +"duck"
      end
    end.new

    pipe do |reader, writer|
      writer.write("pipe")
      writer.close
      assert_equal("pipe", Dexpace::IO::BufferedSource.wrapping(reader).read)
    end
    assert_equal("sio", Dexpace::IO::BufferedSource.wrapping(StringIO.new("sio")).read)
    assert_equal("duck", Dexpace::IO::BufferedSource.wrapping(duck).read)
  end

  test "wrapping rejects an object that reads no way at all" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::IO::BufferedSource.wrapping(Object.new)
    end

    assert_includes(error.message, "#readpartial")
  end

  # P3-11: ownership must not be settable through an unnamed argument, or a caller builds the
  # wrapper IO-6 forbids.
  test "new is private on the two wrapping classes and public on the two that own nothing" do
    assert_raises(::NoMethodError) { Dexpace::IO::BufferedSource.new }
    assert_raises(::NoMethodError) { Dexpace::IO::BufferedSink.new }
    assert_instance_of(Dexpace::IO::Buffer, Dexpace::IO::Buffer.new)
  end

  # ---- IO-16 and R4: the bridge, proved rather than restated ---------------------------------

  # THE bridge proof. This is the exact mechanism Net::HTTP#body_stream= uses:
  # Net::HTTP#send_request_with_body_stream is IO.copy_stream(f, sock). Not a mock of it.
  test "IO.copy_stream drives a wrapped source and the bytes arrive intact" do
    destination = StringIO.new(+"".b)

    pipe do |reader, writer|
      writer.write("héllo wörld" * 40)
      writer.close
      ::IO.copy_stream(Dexpace::IO::BufferedSource.wrapping(reader), destination)
    end

    assert_equal(("héllo wörld" * 40).b, destination.string)
  end

  # IO-6's second sentence -- "closing the bridge closes the owning source/sink" -- is trivially
  # true when the bridge IS the source, which is exactly why it gets an assertion: "trivially true"
  # is what a later refactor splitting the bridge into its own object would silently break.
  test "closing the source after IO.copy_stream closes the wrapped stream" do
    pipe do |reader, writer|
      writer.write("abc")
      writer.close
      source = Dexpace::IO::BufferedSource.wrapping(reader)
      ::IO.copy_stream(source, StringIO.new(+"".b))
      source.close

      assert(reader.closed?)
    end
  end

  # Verified fact 11: StringIO#read(n, buf)'s destination encoding changed at exactly Ruby 3.4
  # (ASCII-8BIT on 3.2.11, UTF-8 from 3.4.10) while IO#read preserves the destination's tag on all
  # three. This is a floor-straddler like URI::DEFAULT_PARSER, so it is pinned rather than assumed:
  # 3a never infers a tag from a destination or a source.
  test "a StringIO-backed source returns BINARY on every interpreter in the matrix" do
    source = Dexpace::IO::BufferedSource.wrapping(StringIO.new("héllo"))

    drained = source.read

    assert_equal(::Encoding::BINARY, drained.encoding)
    assert_equal("héllo".b, drained)
  end

  test "a pipe-backed source returns BINARY too" do
    pipe do |reader, writer|
      writer.write("héllo")
      writer.close

      assert_equal(::Encoding::BINARY,
                   Dexpace::IO::BufferedSource.wrapping(reader).read.encoding,)
    end
  end

  # ---- §10.2 and .over -----------------------------------------------------------------------

  # Verified fact 3: force_encoding on a frozen String raises FrozenError even when the target
  # encoding is already the string's own, and a Rack-style body's #each yields frozen literals.
  # String#b is the ingress idiom; force_encoding appears nowhere on this path.
  test "over survives a body that yields frozen literals, and stores them BINARY" do
    source = Dexpace::IO::BufferedSource.over(FakeChunked.frozen_utf8)

    drained = source.read

    assert_equal(::Encoding::BINARY, drained.encoding)
    assert_equal("héllo wörld".b, drained)
  end

  # Verified fact 4: appending a NON-ASCII UTF-8 String to a BINARY one silently retags the result
  # to UTF-8 while an ASCII-only one does not -- so an ASCII-only fixture would pass under exactly
  # the bug. Every encoding test in 3a therefore uses non-ASCII bytes.
  test "a non-ASCII chunk does not retag the buffer to UTF-8" do
    source = Dexpace::IO::BufferedSource.over(FakeChunked.new("é"))

    assert_equal(::Encoding::BINARY, source.read.encoding)
  end

  # .over preserves the wrapped body's own chunking, which is what BODY-17's byte-exact mirroring
  # needs. This is the plan's answer to the open question about #each's granularity.
  test "over preserves the wrapped body's chunk boundaries through each" do
    source = Dexpace::IO::BufferedSource.over(FakeChunked.new("ab", "cde", "f"))

    assert_equal(%w[ab cde f], source.each.to_a)
  end

  # IO-1's "at least 1 when byteCount>0 and the source is NOT exhausted". An empty chunk means
  # "no bytes this time", never "no bytes ever": Rack permits #each to yield "", and collapsing
  # the two truncates the body there -- silently, and with a well-formed short read that no
  # length check downstream would question. StopIteration is the only end-of-stream signal here.
  test "an empty chunk between two non-empty ones is not end of stream" do
    source = Dexpace::IO::BufferedSource.over(FakeChunked.new("ab", "", "cd"))

    assert_equal("abcd", source.read)
  end

  test "a leading empty chunk does not make the body look exhausted" do
    assert_equal("abc", Dexpace::IO::BufferedSource.over(FakeChunked.new("", "abc")).read)
  end

  test "an empty chunk truncates neither each nor read_exactly, and eof? stays false" do
    body = -> { FakeChunked.new("ab", "", "cd") }

    assert_equal(%w[ab cd], Dexpace::IO::BufferedSource.over(body.call).each.to_a)
    assert_equal("abcd", Dexpace::IO::BufferedSource.over(body.call).read_exactly(4))

    source = Dexpace::IO::BufferedSource.over(body.call)
    source.read_exactly(2)

    refute(source.eof?)
  end

  test "over pulls on demand, so no read-ahead accumulates" do
    body = FakeChunked.new("ab", "cd", "ef")
    source = Dexpace::IO::BufferedSource.over(body)

    source.read_exactly(1)

    assert_equal(1, body.yielded)
  end

  # §7.1's residue, asserted rather than papered over: a source closed before exhaustion abandons
  # the enumerator, and an abandoned Enumerator never runs its ensure (verified on 3.2.11, 3.4.10
  # and 4.0.6; #rewind does not run it either). Nothing core owns leaks, because .over owns
  # nothing -- the enumerator holds the caller's body, and the caller's body is owned by whoever
  # created it. .over's YARD block says so.
  test "closing an unexhausted over source leaves the wrapped body's own ensure unrun" do
    body = FakeChunked.new("ab", "cd", "ef")
    source = Dexpace::IO::BufferedSource.over(body)
    source.read_exactly(1)
    source.close

    refute(body.ensure_ran)
  end

  test "draining an over source to exhaustion does run the body's ensure" do
    body = FakeChunked.new("ab", "cd")
    Dexpace::IO::BufferedSource.over(body).read

    assert(body.ensure_ran)
  end

  test "a BufferedSource is itself a canonical body representation" do
    assert_respond_to(Dexpace::IO::BufferedSource.of_bytes("ab"), :each)
  end

  # ---- IO-41, IO-42: close ------------------------------------------------------------------

  # IO-41: "a second (or later) close() MUST NOT throw, and the underlying resource MUST be closed
  # at most once."
  test "close is idempotent and closes the underlying resource at most once" do
    closes = 0
    stream = Object.new
    stream.define_singleton_method(:read) { |_n| nil }
    stream.define_singleton_method(:close) { closes += 1 }

    source = Dexpace::IO::BufferedSource.wrapping(stream)
    source.close
    source.close
    source.close

    assert_equal(1, closes)
  end

  # IO-42: "A buffered source/sink that wraps an external stream MUST reject read/write/flush/emit
  # attempts made after close() with an I/O error." P3-3: that error is phase 2's
  # Dexpace::ClosedError, whose first raise site is here.
  test "a stream-backed source rejects every read form after close" do
    source = Dexpace::IO::BufferedSource.wrapping(StringIO.new("abcdef"))
    source.close

    assert_raises(Dexpace::ClosedError) { source.read }
    assert_raises(Dexpace::ClosedError) { source.read_exactly(1) }
    assert_raises(Dexpace::ClosedError) { source.readpartial(1) }
    assert_raises(Dexpace::ClosedError) { source.read_into(+"".b, count: 1) }
    assert_raises(Dexpace::ClosedError) { source.eof? }
    assert_raises(Dexpace::ClosedError) { source.peek }
  end

  # The two directions of IO-42's asymmetry get two tests that fail in OPPOSITE ways, because a
  # single "it raises after close" test would pass over either error. This is the stream-backed
  # half; buffer_test.rb carries the in-memory half.
  test "the post-close failure is a state error and never an end-of-stream error" do
    source = Dexpace::IO::BufferedSource.of_bytes("abc")
    source.close

    error = assert_raises(Dexpace::ClosedError) { source.read }

    refute_kind_of(::EOFError, error)
    refute_kind_of(Dexpace::StreamError, error)
  end

  test "closed? stays public with the same arity after P3-6" do
    source = Dexpace::IO::BufferedSource.of_bytes("abc")

    assert_respond_to(source, :closed?)
    assert_equal(0, source.method(:closed?).arity)
    refute(source.closed?)
    source.close
    assert(source.closed?)
  end

  # ---- IO-37, IO-38: the two threads on one flag ---------------------------------------------

  # IO-37: "All streaming instances ... are single-threaded contracts". The proof that no lock is
  # held across a read is the LOCK'S ABSENCE, and it is testable: verified on all three
  # interpreters that a Thread::Mutex held across a fiber suspension raises ThreadError for a
  # second fiber of the same thread. So this test fails loudly under exactly the bug it exists to
  # catch, and it is driven with Fiber.new/Fiber.yield rather than a scheduler.
  test "two fibers of one thread interleave reads on one source without a ThreadError" do
    gate = Class.new do
      def initialize = @chunks = %w[ab cd ef gh]

      def readpartial(_maxlen, _outbuf = nil)
        raise ::EOFError if @chunks.empty?

        ::Fiber.yield
        +@chunks.shift
      end
    end.new
    source = Dexpace::IO::BufferedSource.wrapping(gate)
    read = []

    first = ::Fiber.new { read << source.read_exactly(2) }
    second = ::Fiber.new { read << source.read_exactly(2) }
    first.resume
    second.resume
    first.resume
    second.resume

    assert_equal(%w[ab cd], read)
  end

  # IO-38: "the CLOSE state of a source/buffer MUST be observable across threads to the slices
  # derived from it, so that a close on one thread reliably invalidates a slice being read on
  # another (no torn or stale reads)."
  #
  # Sequenced through a Thread::Queue handshake, never raced: phase 2's cancellation-stamp work is
  # the precedent for how a free-running race produces a flake nobody can reproduce. DEF-33 records
  # that this passes with or without the lock on every CRuby row -- the assertion that
  # distinguishes mechanism from behaviour is the fiber-held-mutex test in closeable_test.rb.
  test "a close on one thread invalidates a read blocked on another" do
    pipe do |reader, writer|
      source = Dexpace::IO::BufferedSource.wrapping(reader)
      inside = ::Thread::Queue.new
      outcome = ::Thread::Queue.new

      blocked = ::Thread.new do
        inside.push(:reading)
        begin
          source.read_exactly(4)
          outcome.push(:returned)
        rescue ::StandardError => error
          outcome.push(error)
        end
      end

      assert_equal(:reading, inside.pop)
      Thread.pass until blocked.status == "sleep" || !blocked.status
      source.close
      writer.close

      result = outcome.pop
      blocked.join

      # The blocked read fails loudly and never returns stale bytes. What it raises is Ruby's own
      # ::IOError ("stream closed in another thread"), forwarded unchanged -- IO-40's "MUST NOT
      # swallow OR duplicate the wrapped stream's cancellation/interrupt handling" honoured by
      # doing nothing to it. Every read AFTER the close is 3a's own Dexpace::ClosedError.
      refute_equal(:returned, result)
      assert_instance_of(::IOError, result)
      assert_raises(Dexpace::ClosedError) { source.read }
    end
  end

  test "a close on one thread invalidates a view being read on another" do
    source = Dexpace::IO::BufferedSource.of_bytes("abcdef")
    view = source.slice(offset: 0, count: 4)
    ready = ::Thread::Queue.new
    go = ::Thread::Queue.new
    outcome = ::Thread::Queue.new

    reader = ::Thread.new do
      ready.push(:ready)
      go.pop
      begin
        outcome.push(view.read)
      rescue ::StandardError => error
        outcome.push(error)
      end
    end

    assert_equal(:ready, ready.pop)
    source.close
    go.push(:go)
    result = outcome.pop
    reader.join

    assert_instance_of(Dexpace::ClosedError, result)
  end

  # IO-41 across threads: #release runs exactly once and both callers return.
  test "close called from two threads releases once and both callers return" do
    releases = ::Thread::Queue.new
    stream = Object.new
    stream.define_singleton_method(:read) { |_n| nil }
    stream.define_singleton_method(:close) { releases.push(:closed) }
    source = Dexpace::IO::BufferedSource.wrapping(stream)

    threads = Array.new(2) { ::Thread.new { source.close } }
    threads.each(&:join)

    assert_equal(1, releases.size)
  end

  # ---- IO-7-shaped round trip over a real stream ---------------------------------------------

  test "random BINARY chunks read back byte-for-byte in order through a wrapped stream" do
    sample(count: 32) do |rng|
      chunks = Array.new(rng.rand(1..6)) { rng.bytes(rng.rand(0..64)) }
      source = Dexpace::IO::BufferedSource.wrapping(StringIO.new(chunks.join.b))

      assert_equal(chunks.join.b, source.read)
    end
  end
end
```

Two things in there are worth reading before running them. The `IO-37` test is driven with
`Fiber.new`/`Fiber.yield` **inside a read**, not with a scheduler, because a `Thread::Mutex` held
across a fiber suspension raises `ThreadError` for a second fiber of the same thread — so it fails
loudly under exactly the bug it exists to catch. The `IO-38` test is **sequenced through a
`Thread::Queue`, never raced**; phase 2's cancellation-stamp work is the precedent for how a
free-running race produces a flake nobody can reproduce.

- [ ] **Step 3: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/buffered_source_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::IO::BufferedSource`.

- [ ] **Step 4: Write `lib/dexpace/io/buffered_source.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "typed_reads"
require_relative "../closeable"

module Dexpace
  module IO
    # The reader: IO-6, IO-11..IO-24, IO-41, IO-42. Also, per design §10.2, a canonical body
    # representation, because it responds to #each yielding BINARY chunks.
    #
    # Ownership is two frozen construction-time facts, never a close-time judgement. Closeable's
    # @owned is always true -- a source always owns its own buffer -- and a separate frozen
    # @dexpace_owns_upstream decides whether #release also closes the upstream. The factory names
    # carry it: .wrapping owns (IO-6), .of_bytes and .over own nothing.
    class BufferedSource
      include Dexpace::IO::TypedReads
      include Dexpace::Closeable

      # The three facts that make a source a VIEW, folded into one value: the object it reads
      # through, the absolute position in that object's byte stream where its window starts, and
      # how wide that window is. One argument rather than three keeps #initialize inside
      # Metrics/ParameterLists' budget of four and makes "is this a view?" one nil check. A Data
      # instance is frozen on construction, which is exactly what a construction-time fact wants.
      # private_constant, so it is not NFR-4 surface and the runtime snapshot's constant walk,
      # which skips private constants, never sees it.
      View = ::Data.define(:parent, :pin, :window)

      private_constant :View

      private_class_method :new

      # IO-6: the returned wrapper TAKES OWNERSHIP -- closing it closes `io`. There is deliberately
      # no borrowing variant, because a wrapper that did not close what it wrapped is the exact
      # object IO-6 prohibits (P3-12).
      #
      # `io` is anything responding to #readpartial or #read. Checked with respond_to?, never
      # is_a?(IO): a nominal test would be silently false inside `module Dexpace` (OI-3), and the
      # duck test is what makes a StringIO, an IO.pipe end, a Tempfile and a caller's own
      # #readpartial-shaped object all work.
      #
      # With a block, closes on any exit path and returns the block's value
      # (`resource-management/bf5560dc`); without one the caller owns the close.
      def self.wrapping(io)
        unless io.respond_to?(:readpartial) || io.respond_to?(:read)
          raise Dexpace::InvalidArgumentError,
                "a wrapped stream must respond to #readpartial or #read, got #{io.class}"
        end

        source = new(upstream: io, owns_upstream: true)
        return source unless block_given?

        begin
          yield source
        ensure
          source.close
        end
      end

      # An INDEPENDENT copy of the input, so a later mutation of the caller's String does not
      # change the source and vice versa (IO-30's surviving behavioural clause, kept even though
      # the ID is a permanent simplification). Owns no external resource -- IO-6's last sentence.
      #
      # The copy is taken here, frozen, and handed on as a ONE-CHUNK #each-shaped body, because a
      # byte array already IS a canonical body representation (§10.2). That leaves one buffered
      # construction path instead of two to keep in step, and #store_append keeps an already-frozen
      # BINARY chunk without copying it a second time.
      def self.of_bytes(string)
        unless string.is_a?(::String)
          raise Dexpace::InvalidArgumentError, "of_bytes takes a String, got #{string.class}"
        end

        new(chunked: [string.b.freeze].freeze)
      end

      # Design §3.1's single inverse adapter over §10.2's duck type: any object responding to
      # #each and yielding String chunks. It pulls on demand so no read-ahead accumulates, and it
      # OWNS NOTHING -- closing the returned source never calls #close on what it wrapped, because
      # its callers are always downstream of something that already owns the response (R3,
      # `message-bodies/f060d944`).
      #
      # §7.1's residue, documented rather than papered over: a source closed before exhaustion
      # abandons the enumerator this drives, and an abandoned Enumerator never runs its ensure
      # (verified on 3.2.11, 3.4.10 and 4.0.6; #rewind does not run it either). A #each-shaped
      # object that holds a resource must expose #close and be closed by its owner, because .over
      # will not.
      def self.over(chunked)
        unless chunked.respond_to?(:each)
          raise Dexpace::InvalidArgumentError,
                "over takes an object responding to #each, got #{chunked.class}"
        end

        new(chunked: chunked)
      end

      # The view constructor #peek and #slice reach. Not public API: a view is a BufferedSource in
      # view mode, which makes IO-23's slice-of-a-slice free and adds no NFR-4-locked constant.
      def self.__dexpace_view(parent:, pin:, window:)
        new(view: View.new(parent: parent, pin: pin, window: window))
      end

      def initialize(upstream: nil, owns_upstream: false, chunked: nil, view: nil)
        @dexpace_upstream = upstream
        @dexpace_owns_upstream = owns_upstream
        @dexpace_enumerator = chunked&.to_enum(:each)
        @dexpace_view = view
        @dexpace_pulled = 0
        @dexpace_upstream_exhausted = upstream.nil? && chunked.nil? && view.nil?
        initialize_closeable(owned: true)
        initialize_typed_reads
        freeze_construction_facts
      end

      # IO-19/IO-20: true when this source is a non-consuming view over another.
      def view?
        !@dexpace_view.nil?
      end

      # IO-6: whether #close also closes the stream this source wraps.
      def owns_upstream?
        @dexpace_owns_upstream
      end

      protected

      def dexpace_remaining_window
        return ::Float::INFINITY unless view?

        remaining = @dexpace_view.window - dexpace_consumed
        remaining.negative? ? 0 : remaining
      end

      private

      # Both construction-time facts are frozen the moment they exist -- a boolean is, and a Data
      # instance is frozen on construction -- so this asserts rather than achieves. It is here
      # because the whole ownership and view story rests on neither ever changing after
      # #initialize returns, and an assertion is what a later reader can check.
      def freeze_construction_facts
        @dexpace_owns_upstream.freeze
        @dexpace_view.freeze
        nil
      end

      # The IO-1/IO-16 EOF sentinels are normalised HERE and nowhere else: readpartial's EOFError
      # and read's nil become one @dexpace_upstream_exhausted flag, which short-circuits every
      # later call. So the rescue runs at most once per stream rather than once per read, and the
      # hot path -- "the bytes are already buffered" -- never enters this method at all.
      def fill(min_bytes)
        return 0 if @dexpace_upstream_exhausted
        return fill_from_parent(min_bytes) if view?
        return fill_from_enumerator if @dexpace_enumerator

        fill_from_upstream(min_bytes)
      end

      def fill_from_upstream(min_bytes)
        want = [min_bytes, 1].max
        chunk =
          if @dexpace_upstream.respond_to?(:readpartial)
            begin
              @dexpace_upstream.readpartial(want)
            rescue ::EOFError
              @dexpace_upstream_exhausted = true
              nil
            end
          else
            @dexpace_upstream.read(want)
          end
        if chunk.nil? || chunk.empty?
          @dexpace_upstream_exhausted = true
          return 0
        end
        store_append(chunk)
      end

      # StopIteration is the ONLY end-of-stream signal on this path, so a fill that adds no bytes
      # is retried rather than latched. #each yielding "" is ordinary -- Rack permits it and
      # ["ab", "", "cd"].each is the shortest example -- and a zero-length chunk means "no bytes
      # this time", never "no bytes ever". Collapsing the two truncates a body at its first empty
      # chunk, silently and with a well-formed short read, and violates IO-1's "at least 1 when
      # byteCount>0 and the source is not exhausted".
      def fill_from_enumerator
        added = 0
        added = store_append(@dexpace_enumerator.next) while added.zero?
        added
      rescue ::StopIteration
        @dexpace_upstream_exhausted = true
        0
      end

      # P3-5, which the specification does not state and 3a therefore does. A view pins the
      # parent's cursor at construction and reads a window relative to that pin, driving the
      # parent's #fill without advancing the parent's cursor. If the parent consumes past the
      # window, the view's later reads fail loudly rather than returning bytes from somewhere
      # else -- IO-22's "never returning stale or arbitrary bytes" is the anchor.
      def fill_from_parent(min_bytes)
        budget = @dexpace_view.window - @dexpace_pulled
        return 0 if budget <= 0

        parent = @dexpace_view.parent
        behind = offset_into_parent(parent)
        want = min_bytes.clamp(1, budget)
        available = parent.dexpace_ensure_buffered(behind + want) - behind
        return 0 if available <= 0

        take = [available, want].min
        @dexpace_pulled += take
        # The window copy is fresh and this view owns it, so it is frozen here rather than inside
        # #store_append -- which keeps "at most one copy on the fill path" true on this path too.
        store_append(parent.dexpace_window_copy(behind, take).freeze)
      end

      # How far ahead of the parent's own cursor this view's next byte sits -- and P3-5's loud
      # failure when that number goes negative. The parent holds nothing back for a view, so a byte
      # its cursor has already passed cannot be served from anywhere, and IO-22 forbids serving it
      # from somewhere else.
      def offset_into_parent(parent)
        behind = @dexpace_view.pin + @dexpace_pulled - parent.dexpace_consumed
        return behind unless behind.negative?

        raise Dexpace::ClosedError,
              "this view's window starts #{-behind} bytes behind the source's cursor: the " \
              "source was read past the pin this view was taken at"
      end

      # IO-22/IO-41/IO-42. The latch has already flipped; this runs exactly once. Drop the buffer,
      # release this view's registration with its parent, invalidate every view derived from THIS
      # source, then close the upstream only if this source owns it.
      def release
        @dexpace_chunks.clear
        @dexpace_head = 0
        @dexpace_buffered = 0
        @dexpace_view.parent.dexpace_forget_view(self) if view?
        dexpace_release_views
        @dexpace_upstream.close if @dexpace_owns_upstream && @dexpace_upstream.respond_to?(:close)
        nil
      end
    end
  end
end
```

`#fill` is where the **two EOF sentinels are normalised, and where the rescue lives**.
`readpartial`'s `EOFError` and `read`'s `nil` both set one `@dexpace_upstream_exhausted` flag that
short-circuits every later call, so the rescue runs at most once per stream rather than once per
read — and the hot path, "the bytes are already buffered", never enters `#fill` at all. That is what
makes "without a rescue on the hot path" structural rather than clever.

**The three fill paths do not agree about a zero-byte result, and that asymmetry is the design's,
stated here so it is not tidied away.** On the `.over` path `StopIteration` is the **only**
end-of-stream signal: `#each` yielding `""` is ordinary — Rack permits it, `["ab", "", "cd"].each`
is the shortest example — so a fill that adds nothing is **retried**, and latching it instead
truncates the body at its first empty chunk, silently and with a well-formed short read that no
length check downstream would question. On the `wrapping` path a zero-length return **is**
exhaustion, because `::IO#read(n)`, `StringIO#read(n)`, `::IO#readpartial(n)` and
`StringIO#readpartial(n)` never return `""` for a positive `n` on 3.2.11, 3.4.10 or 4.0.6 — they
return `nil` or raise — so `""` is unreachable for every reader `Net::HTTP` or a test will hand it,
and retrying instead would spin on a caller's own object that returns `""` forever. On the view path
the parent's own fill has already been driven to exhaustion for the requested window before a zero
is returned. `FakeChunked` scripts the first case and `FakeSource` the third-party violation the
second one names.

- [ ] **Step 5: Write `sig/dexpace/io/buffered_source.rbs`**

```rbs
module Dexpace
  module IO
    class BufferedSource
      include Dexpace::IO::TypedReads
      include Dexpace::Closeable

      def self.wrapping: (untyped io) -> Dexpace::IO::BufferedSource
                       | [T] (untyped io) { (Dexpace::IO::BufferedSource) -> T } -> T
      def self.of_bytes: (String) -> Dexpace::IO::BufferedSource
      def self.over: (Dexpace::IO::_Chunked chunked) -> Dexpace::IO::BufferedSource

      def view?: () -> bool
      def owns_upstream?: () -> bool
    end
  end
end
```

`.wrapping`'s `io` is `untyped` on purpose: it accepts anything responding to `#readpartial` **or**
`#read`, and an RBS union of two structural interfaces would claim a narrowness the runtime check
does not have.

- [ ] **Step 6: Add `require_relative "dexpace/io/buffered_source"` to `lib/dexpace.rb`**

After `dexpace/io/typed_reads`.

- [ ] **Step 7: Run both suites to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/buffered_source_test.rb`, then
`bundle exec ruby -w gems/dexpace-core/test/dexpace/io/typed_reads_test.rb`.
Expected: PASS, 32 and 65 tests — **Task 9's view tests go green here**. Then
`(cd gems/dexpace-core && bundle exec rake test)` and
`mise exec ruby@3.2.11 -- bundle exec rake test:gems`, because the `StringIO`-backed BINARY
assertion and the `Enumerator` `ensure` asymmetry are both floor-straddlers.

---

## Task 11: `Dexpace::IO::TypedWrites` — the write vocabulary

**Requirement IDs:** `IO-4`, `IO-5`, `IO-13` (write side), `IO-16` (writable bridge), `IO-17`,
`IO-18`. **Design:** "`Dexpace::IO::TypedWrites` — the write vocabulary"; deviation **P3-9**.

> **IO-4** (MUST) — Sink.write(src, byteCount) MUST remove exactly byteCount bytes from the HEAD of
> the source buffer and push them downstream; if the source holds fewer than byteCount bytes this
> MUST fail with an I/O error rather than write a short/partial amount.

> **IO-17** (MUST) — writeAll(source) MUST pump the source to exhaustion into the sink and return the
> total number of bytes transferred; it MUST terminate only on a -1 (EOF) read. When pumping a
> foreign (non-adapter-native) source, a read that returns 0 for a non-zero requested count MUST be
> treated as a source contract violation and raised as an I/O error (not tolerated as EOF and not
> spun on forever).

> **IO-18** (SHOULD) — The sink surface SHOULD distinguish emit() from flush(): emit pushes buffered
> bytes one level toward their destination (a cheap hand-off, e.g. staging buffer -> underlying
> stream) without forcing a system-level flush, while flush forces bytes all the way out. On a pure
> in-memory buffer both MAY be no-ops that simply return self.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/io/typed_writes.rb`,
  `gems/dexpace-core/sig/dexpace/io/typed_writes.rbs`,
  `gems/dexpace-core/test/support/fake_source.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/io/typed_writes_test.rb`

**Interfaces:**
- Consumes: Task 3's `Dexpace::StreamError`, phase 2's `Dexpace::Closeable`, and Task 10's
  `BufferedSource` as a `_Source` in the tests.
- Produces: `Dexpace::IO::TypedWrites`, a **public** module supplying `#initialize_typed_writes`,
  `#write_from(buffer, count:)`, `#write(*strings) -> Integer`, `#write_all(source) -> Integer`,
  `#write_utf8(string, range: nil)`, `#write_string(string, encoding:)`, `#emit -> self` and
  `#flush -> self` over one private hook the includer defines, `#deliver(string) -> void`. Tasks 12,
  13 and 14 include it.

**`IO-17`'s zero-read check is unconditional.** The requirement scopes it to a non-adapter-native
source; design §10.1 retired the adapter, so "adapter-native" has no subject in this port, and a
correct source never returns 0 for a positive count anyway — so the check never fires for a native
one and needs no native/foreign predicate, no marker module and no `.conforms?`.

**`#write_from` is written against a `Buffer` it does not have yet.** It needs only `#bytesize` and
`#read_exactly` on its argument, both of which an in-test `TypedReads` includer supplies, so Task 11
does not wait for Task 12 — and Task 12 re-tests it against a real `Buffer`.

**The hook's contract, stated once: everything handed to `#deliver` is a frozen BINARY `String`.**
`#binary_of`, `#encode_to`, `#write_all` and `#write_from` each freeze what they produce, so a
`Buffer`'s `#store_append` keeps it with no second copy and a caller that reuses its own buffer
cannot reach what was already written.

- [ ] **Step 1: Write `test/support/fake_source.rb`**

It implements `#read_into` and nothing else, so it **is** `Dexpace::IO::_Source`. It exists because
no real Ruby stream returns 0 for a positive requested count, which is the whole of `IO-17`'s
source-contract violation.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# IO-17's source-contract violation has no natural stand-in: no real Ruby stream returns 0 for a
# positive requested count. This double implements #read_into and NOTHING else, so it is exactly
# Dexpace::IO::_Source and is also what proves #write_all accepts a foreign source.
#
# Each script entry is either a String to deliver, the Integer 0 (the violation), -1 (end of
# stream), or an exception instance to raise. It records what it was asked for, so a test can
# assert the pump terminated rather than spun.
class FakeSource
  attr_reader :calls

  def initialize(*script)
    @script = script
    @calls = []
  end

  def read_into(dest, count:)
    @calls << count
    outcome = @script.shift
    return -1 if outcome.nil? || outcome == -1
    raise outcome if outcome.is_a?(::Exception)
    return 0 if outcome == 0

    bytes = outcome.b
    dest << bytes
    bytes.bytesize
  end
end
```

- [ ] **Step 2: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_source"

# IO-4, IO-5, IO-13 (write side), IO-16 (writable bridge), IO-17, IO-18.
#
# Written against a trivial in-test includer whose #deliver appends to a String, so the write
# vocabulary is exercised with no destination at all.
class DexpaceTypedWritesTest < DexpaceTestCase
  class Collector
    include Dexpace::IO::TypedWrites
    include Dexpace::Closeable

    attr_reader :delivered

    def initialize
      @delivered = []
      initialize_closeable(owned: true)
      initialize_typed_writes
    end

    def written = @delivered.join.b

    private

    def deliver(string)
      @delivered << string.b
      nil
    end

    def release = nil
  end

  def sink = Collector.new

  # ---- IO-16: the writable bridge ------------------------------------------------------------

  # IO-16's writable half, and P3-9's stated exception: a positional splat exactly like ::IO#write,
  # because being call-compatible with ::IO is the bridge's entire purpose -- a keyword here would
  # make IO.copy_stream fail.
  test "write takes a splat of Strings and returns the byte count" do
    subject = sink

    assert_equal(5, subject.write("ab", "cde"))
    assert_equal("abcde", subject.written)
  end

  test "write returns the BYTE count, not the character count" do
    assert_equal("é".bytesize, sink.write("é"))
  end

  test "write stores BINARY even for a non-ASCII UTF-8 argument" do
    subject = sink
    subject.write("é")

    assert_equal(::Encoding::BINARY, subject.delivered.first.encoding)
  end

  test "write copies a caller-mutable String, so a reused buffer cannot corrupt what was written" do
    subject = sink
    buffer = +"ab".b
    subject.write(buffer)
    buffer.replace("zz")

    assert_equal("ab", subject.written)
  end

  test "write rejects a non-String argument" do
    assert_raises(Dexpace::InvalidArgumentError) { sink.write(42) }
  end

  # ---- IO-4: write_from ----------------------------------------------------------------------

  # IO-4: "MUST remove exactly byteCount bytes from the HEAD of the source buffer and push them
  # downstream".
  test "write_from removes exactly count bytes from the head of the buffer" do
    subject = sink
    buffer = Dexpace::IO::Buffer.new
    buffer.write("abcdef")

    subject.write_from(buffer, count: 3)

    assert_equal("abc", subject.written)
    assert_equal(3, buffer.bytesize)
    assert_equal("def", buffer.read)
  end

  # IO-4: "if the source holds fewer than byteCount bytes this MUST fail with an I/O error rather
  # than write a short/partial amount." And nothing is consumed, so the buffer is still usable.
  test "write_from fails with an I/O error rather than writing short, and consumes nothing" do
    subject = sink
    buffer = Dexpace::IO::Buffer.new
    buffer.write("ab")

    error = assert_raises(Dexpace::StreamError) { subject.write_from(buffer, count: 5) }

    assert_includes(error.message, "2")
    assert_includes(error.message, "5")
    assert_empty(subject.written)
    assert_equal("ab", buffer.read)
  end

  test "write_from rejects a negative count before touching the buffer" do
    buffer = Dexpace::IO::Buffer.new
    buffer.write("abc")

    assert_raises(Dexpace::InvalidArgumentError) { sink.write_from(buffer, count: -1) }
    assert_equal(3, buffer.bytesize)
  end

  test "write_from with a zero count is a no-op" do
    subject = sink
    buffer = Dexpace::IO::Buffer.new

    assert_nil(subject.write_from(buffer, count: 0))
    assert_empty(subject.written)
  end

  # ---- IO-17: the pump -----------------------------------------------------------------------

  # IO-17: "MUST pump the source to exhaustion into the sink and return the total number of bytes
  # transferred; it MUST terminate only on a -1 (EOF) read."
  test "write_all pumps to exhaustion and returns the total" do
    subject = sink
    source = FakeSource.new("ab", "cde", -1)

    assert_equal(5, subject.write_all(source))
    assert_equal("abcde", subject.written)
  end

  test "write_all terminates on -1 and does not keep asking" do
    source = FakeSource.new("ab", -1)
    sink.write_all(source)

    assert_equal(2, source.calls.length)
  end

  # IO-17: "a read that returns 0 for a non-zero requested count MUST be treated as a source
  # contract violation and raised as an I/O error (not tolerated as EOF and not spun on forever)."
  # No real Ruby stream produces this, which is why FakeSource exists.
  #
  # The check is UNCONDITIONAL rather than scoped to a "foreign" source: design §10.1 retired the
  # adapter, so "adapter-native" has no subject in this port, and a correct source never returns 0
  # for a positive count anyway.
  test "write_all raises on a zero read for a positive count and does not spin" do
    subject = sink
    source = FakeSource.new("ab", 0, "cd")

    error = assert_raises(Dexpace::StreamError) { subject.write_all(source) }

    assert_includes(error.message, "IO-17")
    assert_equal(2, source.calls.length)
  end

  test "write_all lets a source's own failure propagate unchanged" do
    boom = Class.new(::StandardError)

    assert_raises(boom) { sink.write_all(FakeSource.new("ab", boom.new("no"))) }
  end

  test "write_all rejects an object that is not a source" do
    error = assert_raises(Dexpace::InvalidArgumentError) { sink.write_all(Object.new) }

    assert_includes(error.message, "#read_into")
  end

  test "write_all drives a real BufferedSource end to end" do
    subject = sink

    assert_equal(6, subject.write_all(Dexpace::IO::BufferedSource.of_bytes("abcdef")))
    assert_equal("abcdef", subject.written)
  end

  # ---- IO-13: the write-side encodings --------------------------------------------------------

  test "write_utf8 writes the UTF-8 bytes of the string" do
    subject = sink
    subject.write_utf8("héllo")

    assert_equal("héllo".b, subject.written)
  end

  # P3-9: `range` is a CHARACTER range over the String -- the reference's substring form -- while
  # every count elsewhere in 3a is a byte count. The non-ASCII fixture is what tells them apart.
  test "write_utf8 range is a character range, not a byte range" do
    subject = sink
    subject.write_utf8("héllo", range: 0..1)

    assert_equal("hé".b, subject.written)
  end

  test "write_utf8 rejects a range outside the string" do
    assert_raises(Dexpace::InvalidArgumentError) { sink.write_utf8("ab", range: 9..12) }
  end

  test "write_string encodes into the charset the caller named" do
    subject = sink
    subject.write_string("café", encoding: ::Encoding::ISO_8859_1)

    assert_equal("caf\xE9".b, subject.written)
  end

  test "write_string rejects an unknown encoding name" do
    assert_raises(Dexpace::InvalidArgumentError) { sink.write_string("ab", encoding: "no-such") }
  end

  test "write_string rejects text the target charset cannot represent" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      sink.write_string("→", encoding: ::Encoding::ISO_8859_1)
    end

    assert_includes(error.message, "ISO-8859-1")
  end

  # ---- IO-5, IO-18 ---------------------------------------------------------------------------

  # IO-18: "On a pure in-memory buffer both MAY be no-ops that simply return self."
  test "emit and flush return self" do
    subject = sink

    assert_same(subject, subject.emit)
    assert_same(subject, subject.flush)
  end

  # ---- the includer contract -----------------------------------------------------------------

  test "an includer that never calls initialize_typed_writes fails loudly" do
    unready = Class.new do
      include Dexpace::IO::TypedWrites
      include Dexpace::Closeable

      def initialize = initialize_closeable(owned: true)
    end.new

    assert_raises(Dexpace::SeamError) { unready.write("ab") }
  end

  test "an includer that supplies no deliver hook fails loudly" do
    hookless = Class.new do
      include Dexpace::IO::TypedWrites
      include Dexpace::Closeable

      def initialize
        initialize_closeable(owned: true)
        initialize_typed_writes
      end
    end.new

    assert_raises(::NotImplementedError) { hookless.write("ab") }
  end

  test "the write hooks are private and the vocabulary is public" do
    subject = sink

    assert_respond_to(subject, :write_all)
    refute(subject.respond_to?(:deliver))
    refute(subject.respond_to?(:push_one_level))
  end
end
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/typed_writes_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::IO::TypedWrites`.

- [ ] **Step 4: Write `lib/dexpace/io/typed_writes.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../io"
require_relative "../error/stream_error"
require_relative "../error/invalid_argument_error"
require_relative "../error/closed_error"

module Dexpace
  module IO
    # The write vocabulary, symmetric to TypedReads and supplied over one private hook the
    # includer defines: #deliver(string) -> void, which pushes BINARY bytes one level toward the
    # includer's destination. An includer must also include Dexpace::Closeable.
    #
    # Public and not private_constant for TypedReads' two reasons (P3-8).
    #
    # It carries its own #validate_count! and #resolve_encoding rather than sharing TypedReads',
    # because each module must stand alone: a third-party sink that supplies #deliver gets the
    # whole write vocabulary by including this one and nothing else.
    module TypedWrites
      # The pump's read granularity. Private, so it is not NFR-4 surface and phase 5 is free to
      # make it a setting without widening a public signature.
      WRITE_ALL_SEGMENT_BYTES = 64 * 1024

      private_constant :WRITE_ALL_SEGMENT_BYTES

      def initialize_typed_writes
        unless is_a?(Dexpace::Closeable)
          raise Dexpace::SeamError,
                "#{self.class} includes Dexpace::IO::TypedWrites and must also include " \
                "Dexpace::Closeable"
        end

        @dexpace_writes_ready = true
        nil
      end

      # IO-4: removes exactly `count` bytes from the HEAD of `buffer` and pushes them downstream.
      # If the buffer holds fewer, this fails with an I/O error rather than writing a short amount
      # -- and it consumes nothing, so the buffer is still usable after the rejection.
      def write_from(buffer, count:)
        ensure_typed_writes_initialized
        validate_count!(count, name: "count")
        ensure_writable
        available = buffer.bytesize
        if available < count
          raise Dexpace::StreamError.short_transfer(transferred: available, expected: count)
        end
        return nil if count.zero?

        deliver(buffer.read_exactly(count).freeze)
        nil
      end

      # IO-16's host-native writable bridge: returns the byte count, which is what
      # IO.copy_stream requires of a destination. Positional splat, exactly like ::IO#write --
      # P3-9's stated exception, because a keyword here would make IO.copy_stream fail.
      def write(*strings)
        ensure_typed_writes_initialized
        ensure_writable
        total = 0
        strings.each do |string|
          bytes = binary_of(string)
          next if bytes.empty?

          deliver(bytes)
          total += bytes.bytesize
        end
        total
      end

      # IO-17: pumps `source` to exhaustion through IO-1's primitive and returns the total.
      # It terminates ONLY on a -1 read, and a read of 0 for a positive requested count is a
      # source-contract violation raised as an I/O error -- never tolerated as EOF, never spun on.
      #
      # The check is unconditional rather than scoped to a "foreign" source: design §10.1 retired
      # the adapter, so "adapter-native" has no subject in this port, and a correct source never
      # returns 0 for a positive count anyway.
      def write_all(source)
        ensure_typed_writes_initialized
        unless source.respond_to?(:read_into)
          raise Dexpace::InvalidArgumentError,
                "write_all takes a source responding to #read_into, got #{source.class}"
        end

        ensure_writable
        total = 0
        loop do
          chunk = (+"").b
          transferred = source.read_into(chunk, count: WRITE_ALL_SEGMENT_BYTES)
          break if transferred == -1

          if transferred.zero?
            raise Dexpace::StreamError.zero_read(requested: WRITE_ALL_SEGMENT_BYTES)
          end

          deliver(chunk.freeze)
          total += transferred
        end
        total
      end

      # IO-13. `range` is a CHARACTER range over the String, the reference's substring form.
      def write_utf8(string, range: nil)
        write_string(range.nil? ? string : sliced(string, range), encoding: ::Encoding::UTF_8)
      end

      # IO-13's symmetric explicit-charset write.
      def write_string(string, encoding:)
        ensure_typed_writes_initialized
        unless string.is_a?(::String)
          raise Dexpace::InvalidArgumentError, "string must be a String, got #{string.class}"
        end

        target = resolve_encoding(encoding)
        ensure_writable
        bytes = encode_to(string, target)
        deliver(bytes) unless bytes.empty?
        nil
      end

      # IO-5/IO-18. #emit is the cheap one-level hand-off -- staging buffer to underlying stream --
      # and does NOT force a system-level flush; #flush forces bytes all the way out. On a pure
      # in-memory buffer both are the no-ops IO-18 explicitly permits.
      def emit
        ensure_typed_writes_initialized
        ensure_writable
        push_one_level
        self
      end

      def flush
        ensure_typed_writes_initialized
        ensure_writable
        push_all
        self
      end

      private

      # IO-42, through Closeable#closed? -- one Thread::Mutex acquisition per public entry point.
      def ensure_writable
        return unless closed?
        return if writes_survive_close?

        raise Dexpace::ClosedError, "#{self.class} is closed"
      end

      # IO-42's in-memory exemption. Only Dexpace::IO::Buffer answers true.
      def writes_survive_close?
        false
      end

      def ensure_typed_writes_initialized
        return if defined?(@dexpace_writes_ready) && @dexpace_writes_ready

        raise Dexpace::SeamError,
              "#{self.class} includes Dexpace::IO::TypedWrites but never called " \
              "#initialize_typed_writes"
      end

      def deliver(_string)
        raise NotImplementedError,
              "#{self.class} includes Dexpace::IO::TypedWrites and must define a private " \
              "#deliver(string)"
      end

      def push_one_level
        nil
      end

      def push_all
        push_one_level
      end

      def sliced(string, range)
        unless string.is_a?(::String)
          raise Dexpace::InvalidArgumentError, "string must be a String, got #{string.class}"
        end

        part = string[range]
        if part.nil?
          raise Dexpace::InvalidArgumentError, "range #{range.inspect} is outside the string"
        end

        part
      end

      def encode_to(string, target)
        string.encode(target).b.freeze
      rescue ::EncodingError => error
        raise Dexpace::InvalidArgumentError,
              "cannot encode the given String as #{target}: #{error.message}"
      end

      def binary_of(string)
        unless string.is_a?(::String)
          raise Dexpace::InvalidArgumentError, "write takes Strings, got #{string.class}"
        end

        return string if string.frozen? && string.encoding == ::Encoding::BINARY

        # Frozen, so the store keeps it without a second copy and a caller that reuses its own
        # buffer cannot reach what was already written.
        string.b.freeze
      end

      def validate_count!(value, name:)
        unless value.is_a?(::Integer)
          raise Dexpace::InvalidArgumentError, "#{name} must be an Integer, got #{value.class}"
        end
        return unless value.negative?

        raise Dexpace::InvalidArgumentError, "#{name} must not be negative, got #{value}"
      end

      def resolve_encoding(encoding)
        return encoding if encoding.is_a?(::Encoding)

        ::Encoding.find(encoding.to_s)
      rescue ::ArgumentError => error
        raise Dexpace::InvalidArgumentError,
              "unknown encoding #{encoding.inspect}: #{error.message}"
      end
    end
  end
end
```

- [ ] **Step 5: Write `sig/dexpace/io/typed_writes.rbs`**

```rbs
module Dexpace
  module IO
    module TypedWrites
      def initialize_typed_writes: () -> nil
      def write_from: (Dexpace::IO::Buffer buffer, count: Integer) -> nil
      def write: (*String) -> Integer
      def write_all: (Dexpace::IO::_Source source) -> Integer
      def write_utf8: (String, ?range: Range[Integer]?) -> nil
      def write_string: (String, encoding: Encoding | String) -> nil
      def emit: () -> self
      def flush: () -> self

      private

      def deliver: (String) -> void
    end
  end
end
```

- [ ] **Step 6: Add `require_relative "dexpace/io/typed_writes"` to `lib/dexpace.rb`**

After `dexpace/io/buffered_source`.

- [ ] **Step 7: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/typed_writes_test.rb`
Expected: PASS, 25 tests. Then `bundle exec rubocop --fail-level=convention` and
`bundle exec rake rbs:validate steep`.

---
## Task 12: `Dexpace::IO::Buffer` — the FIFO

**Requirement IDs:** `IO-7`, `IO-8`, `IO-9`, `IO-10`, `IO-18`, `IO-41`, `IO-42`. **Design:**
"`Dexpace::IO::Buffer` — the FIFO"; deviations **P3-4**, **P3-10**, **P3-11**.

> **IO-7** (MUST) — A Buffer MUST behave as a FIFO byte queue that is simultaneously a source and a
> sink: bytes written through its sink surface MUST be read back through its source surface in the
> exact order written, and its size MUST reflect the number of bytes currently held.

> **IO-8** (MUST) — Buffer.snapshot() MUST return a fresh, independent byte-array copy of the
> buffer's current contents without consuming or otherwise mutating the buffer, such that later
> mutations of the buffer do not affect a previously returned snapshot and vice versa.

> **IO-10** (MUST) — Buffer.clear() MUST discard every byte (leaving size==0), and Buffer.copyTo(out,
> offset, byteCount) MUST copy the specified window into another buffer WITHOUT consuming or mutating
> the source buffer, defaulting to 'from offset through end' when byteCount is omitted, and rejecting
> out-of-range windows (negative offset/byteCount or offset+byteCount>size).

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/io/buffer.rb`, `gems/dexpace-core/sig/dexpace/io/buffer.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/io/buffer_test.rb`

**Interfaces:**
- Consumes: Tasks 5–9's `TypedReads` and Task 11's `TypedWrites`, plus phase 2's `Closeable`.
- Produces: `Dexpace::IO::Buffer` with a **public** `.new`, `#bytesize`, `#snapshot -> String`
  (unfrozen), `#clear` and `#copy_to(other, offset: 0, count: nil)`. Task 14's tap is one of these;
  Task 11's `#write_from` is re-tested against one; phase 3b's `BODY-3`/`HTTP-37` materialize-once
  depends on the whole surface.

**After `TypedWrites` because it includes it, and before `BufferedSink` because `TeeSink`'s tap is
one of these** and `IO-4`'s sink test reads best against a real buffer.

**It is deliberately not a `BufferedSource` subclass.** It would inherit `.wrapping`, `.of_bytes`
and `.over`, and `Buffer.wrapping(io)` is a nonsense factory that would appear in the surface
manifest. `.new` is public because a `Buffer` has exactly one construction meaning and needs no
factory to name it — phase 1's `private_class_method :new` plus a validating `.build` is a rule about
`Data` value types and does not reach a mutable, stateful object with no `.build` (P3-11).

- [ ] **Step 1: Write the failing test**

Two things here are load-bearing. The mandatory property test (`testing/f36a19cd`, phase 0's
`#sample(count:, seed:)`) writes N random BINARY chunks through the sink surface and reads them back
through the source surface, which is `IO-7` stated as a property rather than as three examples. And
the last two tests are `IO-9`'s ceiling: the one that allocates runs on **every** matrix row —
measured at 0.0002 s / 19.1 MB on 3.2.11, 0.0006 s / 15.7 MB on 3.4.10 and 0.0000 s / 16.7 MB on
4.0.6, because the zero-filled pages are mapped lazily and the guard reads `#bytesize` without
touching them.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# IO-7, IO-8, IO-9, IO-10, IO-41, IO-42.
class DexpaceBufferTest < DexpaceTestCase
  def buffer(*strings)
    Dexpace::IO::Buffer.new.tap { |subject| subject.write(*strings) unless strings.empty? }
  end

  # ---- IO-7: the FIFO ------------------------------------------------------------------------

  # IO-7: "a FIFO byte queue that is simultaneously a source and a sink: bytes written through its
  # sink surface MUST be read back through its source surface in the exact order written, and its
  # size MUST reflect the number of bytes currently held."
  test "bytes written through the sink surface read back in order through the source surface" do
    subject = buffer("ab", "cd", "ef")

    assert_equal(6, subject.bytesize)
    assert_equal("abcdef", subject.read)
    assert_equal(0, subject.bytesize)
  end

  test "bytesize reflects what is currently held, not what was ever written" do
    subject = buffer("abcdef")
    subject.read_exactly(2)

    assert_equal(4, subject.bytesize)
  end

  test "it is simultaneously a source and a sink" do
    subject = buffer

    assert_kind_of(Dexpace::IO::TypedReads, subject)
    assert_kind_of(Dexpace::IO::TypedWrites, subject)
  end

  # The mandatory property test (styleguide 11.7): N random BINARY chunks written through the sink
  # surface and read back through the source surface, asserting FIFO order and byte equality.
  test "random chunks round trip through the sink and source surfaces in order" do
    sample(count: 64) do |rng|
      chunks = Array.new(rng.rand(1..8)) { rng.bytes(rng.rand(0..96)) }
      subject = buffer
      chunks.each { |chunk| subject.write(chunk) }

      assert_equal(chunks.join.b.bytesize, subject.bytesize)
      assert_equal(chunks.join.b, subject.read)
    end
  end

  test "interleaved writes and reads keep FIFO order" do
    sample(count: 48) do |rng|
      subject = buffer
      written = +"".b
      read = +"".b
      rng.rand(1..10).times do
        if rng.rand(2).zero?
          chunk = rng.bytes(rng.rand(0..32))
          written << chunk
          subject.write(chunk)
        else
          taken = subject.read(rng.rand(0..16))
          read << taken unless taken.nil?
        end
      end
      read << subject.read

      assert_equal(written, read)
    end
  end

  # ---- IO-8, IO-9: snapshot ------------------------------------------------------------------

  # IO-8: "a fresh, independent byte-array copy of the buffer's current contents without consuming
  # or otherwise mutating the buffer, such that later mutations of the buffer do not affect a
  # previously returned snapshot and vice versa."
  test "snapshot neither consumes nor mutates the buffer" do
    subject = buffer("abc")

    assert_equal("abc", subject.snapshot)
    assert_equal(3, subject.bytesize)
    assert_equal("abc", subject.read)
  end

  test "a later write does not reach a snapshot already handed out" do
    subject = buffer("abc")
    taken = subject.snapshot
    subject.write("def")

    assert_equal("abc", taken)
  end

  # P3-10: the snapshot comes back UNFROZEN, because IO-8's "and vice versa" presumes the caller
  # may mutate it. The styleguide's freeze-every-returned-collection rule names collections,
  # hashes and structs, and a String is none of the three.
  test "a snapshot is unfrozen and mutating it does not reach the buffer" do
    subject = buffer("abc")
    taken = subject.snapshot

    refute(taken.frozen?)
    taken << "zzz"
    assert_equal("abc", subject.snapshot)
  end

  test "a snapshot is BINARY even for non-ASCII content" do
    assert_equal(::Encoding::BINARY, buffer("héllo").snapshot.encoding)
  end

  test "a snapshot of an empty buffer is an empty BINARY String" do
    taken = buffer.snapshot

    assert_equal("", taken)
    assert_equal(::Encoding::BINARY, taken.encoding)
  end

  # ---- IO-10 ---------------------------------------------------------------------------------

  test "clear discards every byte" do
    subject = buffer("abcdef")
    subject.clear

    assert_equal(0, subject.bytesize)
    assert_equal("", subject.read)
  end

  # IO-10: "copyTo(out, offset, byteCount) MUST copy the specified window into another buffer
  # WITHOUT consuming or mutating the source buffer, defaulting to 'from offset through end'".
  test "copy_to copies a window without consuming or mutating the source" do
    source = buffer("abcdef")
    target = buffer

    source.copy_to(target, offset: 1, count: 3)

    assert_equal("bcd", target.read)
    assert_equal("abcdef", source.read)
  end

  test "copy_to defaults to from offset through end" do
    source = buffer("abcdef")
    target = buffer

    source.copy_to(target, offset: 2)

    assert_equal("cdef", target.read)
  end

  # IO-10: "rejecting out-of-range windows (negative offset/byteCount or offset+byteCount>size)".
  # P3-4: copy_to is NOT a ceiling case at all -- it materialises nothing contiguous of its own,
  # so an out-of-range window here is IO-10's argument error and never IO-9's StreamError.
  test "copy_to rejects an out-of-range window and leaves both buffers untouched" do
    source = buffer("abc")
    target = buffer

    assert_raises(Dexpace::InvalidArgumentError) { source.copy_to(target, offset: 0, count: 9) }
    assert_raises(Dexpace::InvalidArgumentError) { source.copy_to(target, offset: 9, count: 1) }
    assert_raises(Dexpace::InvalidArgumentError) { source.copy_to(target, offset: -1, count: 1) }
    assert_raises(Dexpace::InvalidArgumentError) { source.copy_to(target, offset: 0, count: -1) }
    assert_equal(0, target.bytesize)
    assert_equal("abc", source.read)
  end

  test "copy_to of an over-ceiling window is an argument error, never a ceiling error" do
    source = buffer("abc")

    error = assert_raises(Dexpace::InvalidArgumentError) do
      source.copy_to(buffer, offset: 0, count: Dexpace::IO::MAX_MATERIALIZED_BYTES + 1)
    end

    refute_kind_of(Dexpace::StreamError, error)
  end

  # ---- IO-18 ---------------------------------------------------------------------------------

  # IO-18's explicit MAY for a pure in-memory buffer.
  test "emit and flush are no-ops that return self" do
    subject = buffer("abc")

    assert_same(subject, subject.emit)
    assert_same(subject, subject.flush)
    assert_equal("abc", subject.read)
  end

  # ---- IO-41, IO-42 --------------------------------------------------------------------------

  test "close is idempotent" do
    subject = buffer("abc")

    subject.close
    subject.close

    assert(subject.closed?)
  end

  # IO-42: "A purely in-memory buffer is exempt on its OWN read/write surface (an in-memory close
  # frees nothing and may remain readable so snapshot-after-close logging still works)". This is
  # one of the two tests that fail in OPPOSITE directions; buffered_source_test.rb has the other,
  # and a single "it raises after close" test would pass over either error.
  test "a closed buffer stays readable and writable on its own surface" do
    subject = buffer("abc")
    subject.close

    assert_equal("abc", subject.snapshot)
    assert_equal(3, subject.bytesize)
    assert_equal(3, subject.write("def"))
    assert_equal("abcdef", subject.read)
  end

  # IO-42's other half, which the exemption does NOT cover: "its close() MUST still invalidate
  # every slice derived from it (see IO-22/IO-38)."
  test "closing a buffer still invalidates every view derived from it" do
    subject = buffer("abcdef")
    view = subject.slice(offset: 0, count: 3)
    peeked = subject.peek

    subject.close

    assert_raises(Dexpace::ClosedError) { view.read }
    assert_raises(Dexpace::ClosedError) { peeked.read }
  end

  test "a view over a buffer reads without consuming it" do
    subject = buffer("abcdef")

    assert_equal("abc", subject.slice(offset: 0, count: 3).read)
    assert_equal("abcdef", subject.read)
  end

  # ---- IO-9: the one allocating test ---------------------------------------------------------

  # The only test in 3a that allocates anything large: a Buffer built just over the ceiling, so
  # #snapshot's size guard is exercised for real. It costs one ~64 MiB String allocation, once per
  # run per matrix row, and it runs on EVERY row -- skipping it somewhere would leave the ceiling's
  # only size-based assertion untested exactly where it might first break.
  test "snapshot refuses a buffer over the ceiling and names the streaming alternatives" do
    subject = buffer
    over = Dexpace::IO::MAX_MATERIALIZED_BYTES + 1
    subject.write("\0".b * over)

    assert_equal(over, subject.bytesize)
    error = assert_raises(Dexpace::StreamError) { subject.snapshot }
    assert_includes(error.message, "MAX_MATERIALIZED_BYTES")
    assert_includes(error.message, "#each")
    assert_includes(error.message, "#copy_to")
  end

  test "snapshot of a buffer at the ceiling is not refused for its size" do
    subject = buffer

    # No allocation: the guard reads #bytesize, so an empty buffer proves the comparison is <=.
    assert_equal("", subject.snapshot)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/buffer_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::IO::Buffer`.

- [ ] **Step 3: Write `lib/dexpace/io/buffer.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "typed_reads"
require_relative "typed_writes"
require_relative "../closeable"

module Dexpace
  module IO
    # The FIFO: IO-7..IO-10, IO-41, IO-42. An Array of BINARY String chunks behind a head byte
    # offset, so draining is O(1) amortised (§3.1).
    #
    # It includes BOTH vocabularies, which is what makes it "simultaneously a source and a sink"
    # (IO-7). It is deliberately NOT a BufferedSource subclass: it would inherit .wrapping,
    # .of_bytes and .over, and Buffer.wrapping(io) is a nonsense factory that would appear in the
    # surface manifest.
    class Buffer
      include Dexpace::IO::TypedReads
      include Dexpace::IO::TypedWrites
      include Dexpace::Closeable

      def initialize
        initialize_closeable(owned: true)
        initialize_typed_reads
        initialize_typed_writes
      end

      # IO-7's size. Named for bytes because everything here is bytes and String#bytesize is the
      # precedent.
      def bytesize
        @dexpace_buffered
      end

      # IO-8: a fresh, independent, UNFROZEN BINARY copy that neither consumes nor mutates the
      # buffer. Unfrozen deliberately (P3-10) -- IO-8's "and vice versa" presumes the caller may
      # mutate it, and the styleguide's freeze-every-returned-collection rule names collections,
      # hashes and structs, which a String is none of.
      #
      # Guarded by MAX_MATERIALIZED_BYTES (IO-9): the size is known here, so an over-ceiling
      # snapshot refuses having allocated nothing.
      def snapshot
        ensure_snapshot_within_ceiling
        store_peek(0, @dexpace_buffered)
      end

      # IO-10.
      def clear
        @dexpace_chunks.clear
        @dexpace_head = 0
        @dexpace_consumed += @dexpace_buffered
        @dexpace_buffered = 0
        nil
      end

      # IO-10: copies a window into another Buffer WITHOUT consuming or mutating this one,
      # defaulting to "from offset through end", and rejecting an out-of-range window eagerly.
      # Not a ceiling case (P3-4): it materialises nothing contiguous of its own.
      def copy_to(other, offset: 0, count: nil)
        validate_count!(offset, name: "offset")
        validate_count!(count, name: "count") unless count.nil?
        span = count.nil? ? @dexpace_buffered - offset : count
        if offset > @dexpace_buffered || span.negative? || offset + span > @dexpace_buffered
          raise Dexpace::InvalidArgumentError,
                "window offset #{offset}, count #{count.inspect} is outside a buffer of " \
                "#{@dexpace_buffered} bytes"
        end
        other.write(store_peek(offset, span)) unless span.zero?
        nil
      end

      private

      # A Buffer has no upstream, so there is nothing to fill from. IO-7's source surface reads
      # exactly what its sink surface wrote.
      def fill(_min_bytes)
        0
      end

      # IO-7: bytes written through the sink surface land in the same store the source surface
      # reads, in the exact order written.
      def deliver(string)
        store_append(string)
        nil
      end

      # IO-42's in-memory exemption, in both directions. An in-memory close frees nothing, so
      # snapshot-after-close body logging still works.
      def reads_survive_close?
        true
      end

      def writes_survive_close?
        true
      end

      # IO-42's other half, which the exemption does NOT cover: close still invalidates every
      # view derived from this buffer (IO-22, IO-38).
      def release
        dexpace_release_views
      end

      def ensure_snapshot_within_ceiling
        return if @dexpace_buffered <= Dexpace::IO::MAX_MATERIALIZED_BYTES

        raise Dexpace::StreamError,
              "refusing to materialize #{@dexpace_buffered} bytes as one String: the limit is " \
              "#{Dexpace::IO::MAX_MATERIALIZED_BYTES} bytes " \
              "(Dexpace::IO::MAX_MATERIALIZED_BYTES). Stream it instead -- #read_into, #each, " \
              "#slice or Buffer#copy_to."
      end
    end
  end
end
```

`IO-42`'s asymmetry is here in both directions, and **neither may be simplified into the other**: the
in-memory read/write surface stays live after close, because an in-memory close frees nothing and
`BODY-28`'s "the captured buffer outlives the wrapper's close" depends on it; and the close still
invalidates every view derived from the buffer. `api-design/79b5d745` is why the asymmetry is
documented at the method rather than left looking like an oversight.

- [ ] **Step 4: Write `sig/dexpace/io/buffer.rbs`**

```rbs
module Dexpace
  module IO
    class Buffer
      include Dexpace::IO::TypedReads
      include Dexpace::IO::TypedWrites
      include Dexpace::Closeable

      def initialize: () -> void
      def bytesize: () -> Integer
      def snapshot: () -> String
      def clear: () -> nil
      def copy_to: (Dexpace::IO::Buffer other, ?offset: Integer, ?count: Integer?) -> nil
    end
  end
end
```

- [ ] **Step 5: Add `require_relative "dexpace/io/buffer"` to `lib/dexpace.rb`**

After `dexpace/io/typed_writes`.

- [ ] **Step 6: Run the tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/buffer_test.rb`, then
`bundle exec ruby -w gems/dexpace-core/test/dexpace/io/typed_writes_test.rb` — `#write_from` is now
exercised against a real `Buffer` in both files.
Expected: PASS, 22 and 25 tests. Then the whole gem suite on the floor:
`mise exec ruby@3.2.11 -- bundle exec rake test:gems`.

---

## Task 13: `Dexpace::IO::BufferedSink` — the writer

**Requirement IDs:** `IO-4`, `IO-5`, `IO-6`, `IO-16`, `IO-17`, `IO-18`, `IO-41`, `IO-42`. **Design:**
"`Dexpace::IO::BufferedSink` — the writer"; deviations **P3-11**, **P3-12**.

> **IO-5** (MUST) — Sink MUST expose flush() that pushes currently-buffered bytes toward their final
> destination, and both Source and Sink MUST be closeable.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/io/buffered_sink.rb`,
  `gems/dexpace-core/sig/dexpace/io/buffered_sink.rbs`, `gems/dexpace-core/test/support/fake_sink.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/io/buffered_sink_test.rb`

**Interfaces:**
- Consumes: Task 11's `TypedWrites`, Task 12's `Buffer` (in the `IO-4` test), Task 10's
  `BufferedSource` (in the `IO-17` test), phase 2's `Closeable`.
- Produces: `Dexpace::IO::BufferedSink` with `.wrapping(io)` and its block form; `.new` is
  `private_class_method`. Task 14's tests reuse `FakeSink`.

**The staging shape, decided by this plan (decision 4).** `#deliver` appends to `@dexpace_staged` and
calls `#emit`; `#emit` writes the staged bytes through and clears the buffer **in an `ensure`**, so a
failed underlying write leaves nothing to prepend. `#emit` never calls the underlying `#flush` and
`#flush` always does, which is what makes `IO-18`'s distinction real here rather than notional — and
it needs no flush threshold that phase 5 would then have to configure.

**The symmetric rule to `IO-17`'s.** An underlying `#write` that returns fewer bytes than it was
handed is a sink-contract violation and raises `Dexpace::StreamError` through the same
`.short_transfer` helper `BODY-13` requires.

- [ ] **Step 1: Write `test/support/fake_sink.rb`**

It implements `#write` and nothing else, so it **is** `Dexpace::IO::_Sink`. It is scriptable to
return a short count and to raise partway through, neither of which a real blocking Ruby stream will
do; and it records every `String` it received in order, which is how `IO-25`'s "the wire body MUST
never be reduced or altered by the tap" is asserted byte for byte in Task 14.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A destination that implements #write and NOTHING else, so it is exactly Dexpace::IO::_Sink.
# Scriptable to return a SHORT count (the underlying-sink contract violation) and to raise partway
# through, which is what IO-27's "clears its staging buffer even on a failed primary write" needs;
# and it records every String it received in order, which is how IO-25's "the wire body MUST never
# be reduced or altered by the tap" is asserted byte for byte.
class FakeSink
  attr_reader :writes

  def initialize(*script)
    @script = script
    @writes = []
  end

  def written
    @writes.join.b
  end

  def write(*strings)
    payload = strings.join.b
    outcome = @script.shift
    raise outcome if outcome.is_a?(::Exception)

    @writes << payload
    return outcome if outcome.is_a?(::Integer)

    payload.bytesize
  end
end
```

- [ ] **Step 2: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_sink"
require "stringio"

# IO-4, IO-5, IO-6, IO-16..IO-18, IO-41, IO-42.
class DexpaceBufferedSinkTest < DexpaceTestCase
  # ---- IO-6: ownership -----------------------------------------------------------------------

  test "wrapping takes ownership: closing the sink closes the wrapped stream" do
    stream = StringIO.new(+"".b)
    sink = Dexpace::IO::BufferedSink.wrapping(stream)
    sink.write("ab")
    sink.close

    assert(stream.closed?)
  end

  test "wrapping with a block closes on any exit path and returns the block's value" do
    stream = StringIO.new(+"".b)

    result = Dexpace::IO::BufferedSink.wrapping(stream) { |sink| sink.write("abc") }

    assert_equal(3, result)
    assert(stream.closed?)
  end

  test "wrapping with a block closes when the block raises" do
    stream = StringIO.new(+"".b)

    assert_raises(RuntimeError) { Dexpace::IO::BufferedSink.wrapping(stream) { raise "boom" } }
    assert(stream.closed?)
  end

  # R1's mitigation on the write side: respond_to?, never is_a?.
  test "wrapping accepts anything that responds to write" do
    assert_equal(2, Dexpace::IO::BufferedSink.wrapping(FakeSink.new).write("ab"))
  end

  test "wrapping rejects an object with no write" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::IO::BufferedSink.wrapping(Object.new)
    end

    assert_includes(error.message, "#write")
  end

  # ---- IO-16: the writable bridge ------------------------------------------------------------

  # IO-16's symmetric half: IO.copy_stream needs a destination whose #write returns the byte count.
  test "IO.copy_stream writes into a wrapped sink" do
    stream = StringIO.new(+"".b)
    sink = Dexpace::IO::BufferedSink.wrapping(stream)

    ::IO.copy_stream(StringIO.new("héllo wörld" * 40), sink)

    assert_equal(("héllo wörld" * 40).b, stream.string)
  end

  test "a non-ASCII write does not retag the underlying stream's buffer to UTF-8" do
    stream = StringIO.new(+"".b)
    Dexpace::IO::BufferedSink.wrapping(stream).write("é")

    assert_equal(::Encoding::BINARY, stream.string.encoding)
  end

  # ---- the short-underlying-write rule --------------------------------------------------------

  # IO-17's zero-read rule applied symmetrically on the write side: an underlying #write that
  # accepted fewer bytes than it was handed is a sink-contract violation. No real Ruby stream
  # produces this on a blocking write, which is why FakeSink is scriptable to.
  test "an underlying write that accepts fewer bytes than it was handed is an I/O error" do
    underlying = FakeSink.new(1)
    sink = Dexpace::IO::BufferedSink.wrapping(underlying)

    error = assert_raises(Dexpace::StreamError) { sink.write("abcd") }

    assert_includes(error.message, "1")
    assert_includes(error.message, "4")
  end

  test "a failed underlying write leaves no staged bytes to prepend to the next one" do
    underlying = FakeSink.new(::RuntimeError.new("boom"))
    sink = Dexpace::IO::BufferedSink.wrapping(underlying)

    assert_raises(::RuntimeError) { sink.write("abc") }
    sink.write("def")

    assert_equal("def", underlying.written)
  end

  # ---- IO-5, IO-18 ---------------------------------------------------------------------------

  # IO-18: emit pushes one level "without forcing a system-level flush", flush forces bytes all
  # the way out. The distinction is real here rather than notional: emit never calls the
  # underlying #flush and flush always does.
  test "emit does not call the underlying flush and flush does" do
    flushes = 0
    underlying = FakeSink.new
    underlying.define_singleton_method(:flush) { flushes += 1 }
    sink = Dexpace::IO::BufferedSink.wrapping(underlying)

    sink.write("ab")
    sink.emit
    assert_equal(0, flushes)

    sink.flush
    assert_equal(1, flushes)
  end

  test "emit and flush return self" do
    sink = Dexpace::IO::BufferedSink.wrapping(FakeSink.new)

    assert_same(sink, sink.emit)
    assert_same(sink, sink.flush)
  end

  # ---- IO-4, IO-17 over a real destination ---------------------------------------------------

  test "write_from moves bytes out of a Buffer and into the underlying stream" do
    stream = StringIO.new(+"".b)
    buffer = Dexpace::IO::Buffer.new
    buffer.write("abcdef")

    Dexpace::IO::BufferedSink.wrapping(stream).write_from(buffer, count: 4)

    assert_equal("abcd", stream.string)
    assert_equal("ef", buffer.read)
  end

  test "write_all pumps a BufferedSource into the underlying stream and returns the total" do
    stream = StringIO.new(+"".b)
    source = Dexpace::IO::BufferedSource.of_bytes("héllo wörld")

    total = Dexpace::IO::BufferedSink.wrapping(stream).write_all(source)

    assert_equal("héllo wörld".bytesize, total)
    assert_equal("héllo wörld".b, stream.string)
  end

  # ---- IO-41, IO-42 --------------------------------------------------------------------------

  test "close is idempotent and closes the underlying stream at most once" do
    closes = 0
    underlying = FakeSink.new
    underlying.define_singleton_method(:close) { closes += 1 }
    sink = Dexpace::IO::BufferedSink.wrapping(underlying)

    sink.close
    sink.close

    assert_equal(1, closes)
  end

  # IO-42: "MUST reject read/write/flush/emit attempts made after close() with an I/O error".
  test "a stream-backed sink rejects every write form after close" do
    sink = Dexpace::IO::BufferedSink.wrapping(FakeSink.new)
    sink.close

    assert_raises(Dexpace::ClosedError) { sink.write("ab") }
    assert_raises(Dexpace::ClosedError) { sink.write_utf8("ab") }
    assert_raises(Dexpace::ClosedError) { sink.write_string("ab", encoding: "UTF-8") }
    one_byte = Dexpace::IO::BufferedSource.of_bytes("a")
    assert_raises(Dexpace::ClosedError) { sink.write_all(one_byte) }
    assert_raises(Dexpace::ClosedError) { sink.write_from(Dexpace::IO::Buffer.new, count: 0) }
    assert_raises(Dexpace::ClosedError) { sink.emit }
    assert_raises(Dexpace::ClosedError) { sink.flush }
  end

  test "the post-close failure is a state error and never an end-of-stream error" do
    sink = Dexpace::IO::BufferedSink.wrapping(FakeSink.new)
    sink.close

    error = assert_raises(Dexpace::ClosedError) { sink.write("ab") }

    refute_kind_of(::EOFError, error)
  end

  test "close flushes what is staged before closing the underlying stream" do
    stream = StringIO.new(+"".b)
    sink = Dexpace::IO::BufferedSink.wrapping(stream)
    sink.write("abc")
    sink.close

    assert_equal("abc", stream.string)
  end

  # ---- the doubles conform to the seam --------------------------------------------------------

  # Phase 2's rule: a fake that has drifted from the seam is a suite that proves nothing. FakeSink
  # implements #write and nothing else, so it IS Dexpace::IO::_Sink.
  test "FakeSink is exactly the _Sink shape" do
    fake = FakeSink.new

    assert_respond_to(fake, :write)
    assert_equal(4, fake.write("abcd"))
    assert_equal("abcd", fake.written)
  end
end
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/buffered_sink_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::IO::BufferedSink`.

- [ ] **Step 4: Write `lib/dexpace/io/buffered_sink.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "typed_writes"
require_relative "../closeable"

module Dexpace
  module IO
    # The writer: IO-4, IO-5, IO-6, IO-16..IO-18, IO-41, IO-42.
    #
    # #deliver stages the bytes and pushes them one level immediately, so the staging buffer is
    # empty between calls and a failed underlying write cannot leave stale bytes to prepend. That
    # keeps IO-18's distinction real without inventing a flush threshold this port would then have
    # to configure: #emit pushes staged bytes toward the underlying stream and never calls the
    # underlying #flush, and #flush does both.
    class BufferedSink
      include Dexpace::IO::TypedWrites
      include Dexpace::Closeable

      private_class_method :new

      # IO-6: the returned wrapper TAKES OWNERSHIP -- closing it closes `io`. No borrowing variant
      # (P3-12). `io` is anything responding to #write; checked with respond_to?, never is_a?.
      def self.wrapping(io)
        unless io.respond_to?(:write)
          raise Dexpace::InvalidArgumentError,
                "a wrapped stream must respond to #write, got #{io.class}"
        end

        sink = new(io)
        return sink unless block_given?

        begin
          yield sink
        ensure
          sink.close
        end
      end

      def initialize(io)
        @dexpace_underlying = io
        @dexpace_staged = (+"").b
        initialize_closeable(owned: true)
        initialize_typed_writes
      end

      private

      def deliver(string)
        @dexpace_staged << string
        push_one_level
      end

      # The staging buffer is cleared in an ensure, so a failed underlying write leaves nothing
      # behind for the next one to prepend.
      def push_one_level
        return nil if @dexpace_staged.empty?

        payload = @dexpace_staged
        begin
          written = @dexpace_underlying.write(payload)
        ensure
          @dexpace_staged = (+"").b
        end
        # IO-17's rule, applied symmetrically on the write side: an underlying #write that
        # accepted fewer bytes than it was handed is a sink-contract violation.
        if written.is_a?(::Integer) && written < payload.bytesize
          raise Dexpace::StreamError.short_transfer(transferred: written,
                                                    expected: payload.bytesize,)
        end
        nil
      end

      def push_all
        push_one_level
        @dexpace_underlying.flush if @dexpace_underlying.respond_to?(:flush)
        nil
      end

      # IO-6/IO-41: flush what is staged, then close the underlying stream, exactly once.
      def release
        push_one_level
        @dexpace_underlying.close if @dexpace_underlying.respond_to?(:close)
        nil
      end
    end
  end
end
```

- [ ] **Step 5: Write `sig/dexpace/io/buffered_sink.rbs`**

```rbs
module Dexpace
  module IO
    class BufferedSink
      include Dexpace::IO::TypedWrites
      include Dexpace::Closeable

      def self.wrapping: (untyped io) -> Dexpace::IO::BufferedSink
                       | [T] (untyped io) { (Dexpace::IO::BufferedSink) -> T } -> T
    end
  end
end
```

- [ ] **Step 6: Add `require_relative "dexpace/io/buffered_sink"` to `lib/dexpace.rb`**

After `dexpace/io/buffer`.

- [ ] **Step 7: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/buffered_sink_test.rb`
Expected: PASS, 18 tests. Then `bundle exec rubocop --fail-level=convention` and
`bundle exec rake rbs:validate steep`.

---

## Task 14: `Dexpace::IO::TeeSink` — the mirror

**Requirement IDs:** `IO-25`, `IO-26`, `IO-27`, `IO-28`, `IO-29`, `IO-40`, `IO-41`, `IO-42`.
**Design:** "`Dexpace::IO::TeeSink` — the mirror"; deviations **P3-8**, **P3-11**.

> **IO-25** (MUST) — A TeeSink MUST mirror the bytes written through it into an in-memory tap buffer
> AND forward the full, untruncated payload to its primary sink; the bytes delivered to the primary
> (the wire body) MUST never be reduced or altered by the presence of the tap.

> **IO-26** (MUST) — A TeeSink MUST support a tap capacity limit that bounds how many bytes are
> mirrored into the tap; once the limit is reached, further writes MUST stop copying into the tap
> while still forwarding the FULL payload to the primary. The default limit MUST be effectively
> unbounded, and a limit of 0 MUST mirror nothing while still forwarding everything.

> **IO-27** (MUST) — A TeeSink MUST mirror the attempted bytes into the tap BEFORE forwarding them to
> the primary sink, so that if the primary write fails mid-stream the attempted bytes are still
> captured in the tap; and its staging buffer MUST be cleared even on a failed primary write so a
> later write does not prepend stale bytes.

> **IO-28** (MUST) — A TeeSink MUST NOT expose direct access to a backing buffer (attempting it MUST
> fail with a clear error directing callers to the typed write methods), because direct buffer writes
> would reach only the tap or only the primary and silently corrupt the wire body.

> **IO-29** (MUST) — A TeeSink's own flush(), close(), and emit() MUST forward to the PRIMARY sink
> only (not the tap), so lifecycle/flush semantics of the real destination are preserved and the
> in-memory tap is left intact for later snapshotting. …

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/io/tee_sink.rb`,
  `gems/dexpace-core/sig/dexpace/io/tee_sink.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/io/tee_sink_test.rb`

**Interfaces:**
- Consumes: Task 11's `TypedWrites`, Task 12's `Buffer` (the tap **is** one), Task 13's `FakeSink`,
  phase 2's `Closeable`.
- Produces: `Dexpace::IO::TeeSink` with a **public** `.new(primary:, tap_limit: ::Float::INFINITY)`,
  `#tap_snapshot`, `#tap_bytesize`, `#clear_tap` and a `#buffer` that exists only to raise. Phase
  3b's `BODY-17`–`BODY-21` and `BODY-37` consume exactly this surface.

**Last, and the only task where `IO-25`–`IO-29` all land together.** It is **not** a `BufferedSink`
subclass: `IO-29` makes its flush, close and emit forward to the primary only, so inheriting a sink's
lifecycle and then overriding three quarters of it would be inheritance used as a shortcut. Design
§3.1 already says the tee is hand-built rather than assembled from `IO.pipe` or `IO.copy_stream`.

**`#clear_tap` exists because `BODY-18` requires the tap cleared at the start of every write of the
wrapped body.** It is not a lifecycle method and `IO-29` does not reach it — which is why it is safe
for it to touch the tap when nothing else does.

**`IO-40` is honoured structurally, not by a clause.** The staging buffer is cleared in an `ensure`
and not a `rescue`, so nothing is swallowed and nothing is duplicated: the primary's own failure,
whatever it is, propagates exactly once. That is also `resource-management/346deaec`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_sink"

# IO-25, IO-26, IO-27, IO-28, IO-29, IO-40.
class DexpaceTeeSinkTest < DexpaceTestCase
  def tee(primary = FakeSink.new, **options)
    Dexpace::IO::TeeSink.new(primary: primary, **options)
  end

  # ---- IO-25 ---------------------------------------------------------------------------------

  # IO-25: "MUST mirror the bytes written through it into an in-memory tap buffer AND forward the
  # full, untruncated payload to its primary sink; the bytes delivered to the primary (the wire
  # body) MUST never be reduced or altered by the presence of the tap."
  test "the wire body reaches the primary byte for byte and the tap mirrors it" do
    primary = FakeSink.new
    sink = tee(primary)

    sink.write("héllo ", "wörld")

    assert_equal("héllo wörld".b, primary.written)
    assert_equal("héllo wörld".b, sink.tap_snapshot)
  end

  test "the primary sees the same writes with or without a tap limit" do
    unlimited = FakeSink.new
    limited = FakeSink.new
    tee(unlimited).write("abcdef")
    tee(limited, tap_limit: 2).write("abcdef")

    assert_equal(limited.writes, unlimited.writes)
  end

  test "tap_snapshot is a fresh independent copy, like Buffer#snapshot" do
    sink = tee
    sink.write("abc")
    taken = sink.tap_snapshot
    sink.write("def")

    assert_equal("abc", taken)
    assert_equal("abcdef", sink.tap_snapshot)
  end

  test "tap_bytesize reports what the tap currently holds" do
    sink = tee
    sink.write("abcd")

    assert_equal(4, sink.tap_bytesize)
  end

  # ---- IO-26 ---------------------------------------------------------------------------------

  # IO-26: "once the limit is reached, further writes MUST stop copying into the tap while still
  # forwarding the FULL payload to the primary."
  test "the tap stops at its limit while the full payload still reaches the primary" do
    primary = FakeSink.new
    sink = tee(primary, tap_limit: 4)

    sink.write("abcdef")
    sink.write("ghij")

    assert_equal("abcd", sink.tap_snapshot)
    assert_equal("abcdefghij", primary.written)
  end

  # IO-26: "The default limit MUST be effectively unbounded".
  test "the default limit is effectively unbounded" do
    sink = tee
    sink.write("x" * 100_000)

    assert_equal(100_000, sink.tap_bytesize)
    assert_includes(Dexpace::IO::TeeSink.instance_method(:initialize).parameters,
                    %i[key tap_limit],)
  end

  # IO-26: "a limit of 0 MUST mirror nothing while still forwarding everything."
  test "a limit of zero mirrors nothing and forwards everything" do
    primary = FakeSink.new
    sink = tee(primary, tap_limit: 0)

    sink.write("abcdef")

    assert_equal(0, sink.tap_bytesize)
    assert_equal("abcdef", primary.written)
  end

  test "a mid-write limit truncates the tap exactly at the limit" do
    sink = tee(FakeSink.new, tap_limit: 3)
    sink.write("abcdef")

    assert_equal("abc", sink.tap_snapshot)
  end

  test "a negative or non-numeric tap limit is rejected at construction" do
    assert_raises(Dexpace::InvalidArgumentError) { tee(FakeSink.new, tap_limit: -1) }
    assert_raises(Dexpace::InvalidArgumentError) { tee(FakeSink.new, tap_limit: "lots") }
  end

  test "a primary with no write is rejected at construction" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::IO::TeeSink.new(primary: Object.new) }
  end

  # ---- IO-27 ---------------------------------------------------------------------------------

  # IO-27: "MUST mirror the attempted bytes into the tap BEFORE forwarding them to the primary
  # sink, so that if the primary write fails mid-stream the attempted bytes are still captured in
  # the tap". Only a scriptable FakeSink can raise partway through.
  test "a failed primary write still leaves the attempted bytes in the tap" do
    primary = FakeSink.new(nil, ::RuntimeError.new("boom"))
    sink = tee(primary)

    sink.write("abc")
    assert_raises(::RuntimeError) { sink.write("def") }

    assert_equal("abcdef", sink.tap_snapshot)
  end

  # IO-27: "its staging buffer MUST be cleared even on a failed primary write so a later write
  # does not prepend stale bytes." An ensure and not a rescue, so nothing is swallowed -- which is
  # also how IO-40's "MUST NOT swallow OR duplicate the wrapped stream's cancellation/interrupt
  # handling" is honoured structurally.
  test "the staging buffer is cleared even on a failed primary write" do
    primary = FakeSink.new(::RuntimeError.new("boom"))
    sink = tee(primary)

    assert_raises(::RuntimeError) { sink.write("abc") }
    sink.write("def")

    assert_equal("def", primary.written)
  end

  test "a short primary write is a sink-contract violation" do
    error = assert_raises(Dexpace::StreamError) { tee(FakeSink.new(1)).write("abcd") }

    assert_includes(error.message, "4")
  end

  # ---- IO-28 ---------------------------------------------------------------------------------

  # IO-28: "MUST NOT expose direct access to a backing buffer (attempting it MUST fail with a
  # clear error directing callers to the typed write methods)". Defined rather than absent so the
  # failure is that message and not a NoMethodError. Design §10.10 records the honest position:
  # the prohibition cannot be language-enforced and 3a builds no fake proof that it can.
  test "buffer is defined and raises with a message naming the typed write methods" do
    sink = tee

    assert_respond_to(sink, :buffer)
    error = assert_raises(Dexpace::StreamError) { sink.buffer }
    assert_includes(error.message, "IO-28")
    assert_includes(error.message, "#write_all")
  end

  test "no other route to the backing store is exposed" do
    sink = tee

    refute(sink.respond_to?(:primary))
    refute(sink.respond_to?(:staged))
    refute(sink.respond_to?(:tap_buffer))
  end

  # ---- IO-29 ---------------------------------------------------------------------------------

  # IO-29: "A TeeSink's own flush(), close(), and emit() MUST forward to the PRIMARY sink only (not
  # the tap), so lifecycle/flush semantics of the real destination are preserved and the in-memory
  # tap is left intact for later snapshotting."
  test "flush, emit and close forward to the primary only and leave the tap intact" do
    events = []
    primary = FakeSink.new
    primary.define_singleton_method(:flush) { events << :flush }
    primary.define_singleton_method(:emit) { events << :emit }
    primary.define_singleton_method(:close) { events << :close }
    sink = tee(primary)
    sink.write("abc")

    sink.emit
    sink.flush
    sink.close

    assert_equal(%i[emit flush close], events)
    assert_equal("abc", sink.tap_snapshot)
  end

  test "flush and emit return self" do
    sink = tee

    assert_same(sink, sink.emit)
    assert_same(sink, sink.flush)
  end

  # BODY-18's per-attempt reset. It is not a lifecycle method, so IO-29 does not reach it.
  test "clear_tap empties the tap without touching the primary" do
    primary = FakeSink.new
    sink = tee(primary)
    sink.write("abc")

    sink.clear_tap

    assert_equal(0, sink.tap_bytesize)
    assert_equal("abc", primary.written)
  end

  test "the tap survives close, so a snapshot can still be taken afterwards" do
    sink = tee
    sink.write("abc")
    sink.close

    assert_equal("abc", sink.tap_snapshot)
  end

  # ---- IO-41, IO-42 --------------------------------------------------------------------------

  test "close is idempotent and closes the primary at most once" do
    closes = 0
    primary = FakeSink.new
    primary.define_singleton_method(:close) { closes += 1 }
    sink = tee(primary)

    sink.close
    sink.close

    assert_equal(1, closes)
  end

  test "a closed tee rejects every write form" do
    sink = tee
    sink.close

    assert_raises(Dexpace::ClosedError) { sink.write("ab") }
    assert_raises(Dexpace::ClosedError) { sink.write_utf8("ab") }
    one_byte = Dexpace::IO::BufferedSource.of_bytes("a")
    assert_raises(Dexpace::ClosedError) { sink.write_all(one_byte) }
    assert_raises(Dexpace::ClosedError) { sink.emit }
    assert_raises(Dexpace::ClosedError) { sink.flush }
  end

  # ---- the whole write vocabulary reaches both sides -------------------------------------------

  test "write_all, write_from and write_utf8 all mirror and forward" do
    primary = FakeSink.new
    sink = tee(primary)
    buffer = Dexpace::IO::Buffer.new
    buffer.write("cd")

    sink.write_utf8("é")
    sink.write_from(buffer, count: 2)
    sink.write_all(Dexpace::IO::BufferedSource.of_bytes("ef"))

    assert_equal("écdef".b, primary.written)
    assert_equal("écdef".b, sink.tap_snapshot)
  end

  test "the tap and the primary agree byte for byte over random chunk sequences" do
    sample(count: 48) do |rng|
      primary = FakeSink.new
      sink = tee(primary)
      chunks = Array.new(rng.rand(1..6)) { rng.bytes(rng.rand(0..48)) }
      chunks.each { |chunk| sink.write(chunk) }

      assert_equal(chunks.join.b, primary.written)
      assert_equal(chunks.join.b, sink.tap_snapshot)
    end
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/tee_sink_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::IO::TeeSink`.

- [ ] **Step 3: Write `lib/dexpace/io/tee_sink.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "typed_writes"
require_relative "buffer"
require_relative "../closeable"

module Dexpace
  module IO
    # The mirror: IO-25..IO-29, IO-40.
    #
    # Its own class rather than a BufferedSink subclass. IO-29 makes its flush, close and emit
    # forward to the primary only, so inheriting a sink's lifecycle and then overriding three
    # quarters of it would be inheritance used as a shortcut. Design §3.1 already says the tee is
    # hand-built rather than assembled from IO.pipe or IO.copy_stream.
    class TeeSink
      include Dexpace::IO::TypedWrites
      include Dexpace::Closeable

      # IO-26: the default limit MUST be effectively unbounded, and a limit of 0 mirrors nothing
      # while still forwarding everything.
      def initialize(primary:, tap_limit: ::Float::INFINITY)
        unless primary.respond_to?(:write)
          raise Dexpace::InvalidArgumentError,
                "primary must respond to #write, got #{primary.class}"
        end
        unless tap_limit.is_a?(::Numeric) && !tap_limit.negative?
          raise Dexpace::InvalidArgumentError,
                "tap_limit must be a non-negative number, got #{tap_limit.inspect}"
        end

        @dexpace_primary = primary
        @dexpace_tap_limit = tap_limit
        @dexpace_tap = Dexpace::IO::Buffer.new
        @dexpace_staged = (+"").b
        initialize_closeable(owned: true)
        initialize_typed_writes
      end

      # IO-8 over the tap: a fresh, independent copy. The tap is readable only through this.
      def tap_snapshot
        @dexpace_tap.snapshot
      end

      def tap_bytesize
        @dexpace_tap.bytesize
      end

      # BODY-18's per-attempt reset. Not a lifecycle method, so IO-29 does not reach it.
      def clear_tap
        @dexpace_tap.clear
        nil
      end

      # IO-28. Defined rather than absent, so the failure is this message and not a NoMethodError.
      # Design §10.10 records the honest position: the prohibition cannot be language-enforced --
      # instance_variable_get reaches anything -- and 3a does not build a fake proof that it can.
      def buffer
        raise Dexpace::StreamError,
              "a TeeSink exposes no backing buffer: a direct buffer write would reach only the " \
              "tap or only the primary and silently corrupt the wire body (IO-28). Use the typed " \
              "write methods -- #write, #write_from, #write_all, #write_utf8, #write_string."
      end

      private

      # IO-27: the attempted bytes are mirrored into the tap BEFORE they are forwarded, so a
      # primary write that fails mid-stream still leaves them captured; and the staging buffer is
      # cleared in an ensure -- not a rescue, so nothing is swallowed, which is also how IO-40's
      # "MUST NOT swallow OR duplicate the wrapped stream's cancellation/interrupt handling" is
      # honoured structurally.
      def deliver(string)
        @dexpace_staged << string
        mirror(@dexpace_staged)
        payload = @dexpace_staged
        begin
          written = @dexpace_primary.write(payload)
        ensure
          @dexpace_staged = (+"").b
        end
        if written.is_a?(::Integer) && written < payload.bytesize
          raise Dexpace::StreamError.short_transfer(transferred: written,
                                                    expected: payload.bytesize,)
        end
        nil
      end

      # IO-25/IO-26: once the limit is reached the tap stops copying while the FULL untruncated
      # payload still goes to the primary.
      def mirror(payload)
        headroom = @dexpace_tap_limit - @dexpace_tap.bytesize
        return nil if headroom <= 0

        take = headroom < payload.bytesize ? headroom.to_i : payload.bytesize
        @dexpace_tap.write(payload.byteslice(0, take))
        nil
      end

      # IO-29: forward to the PRIMARY only, leaving the tap intact for later snapshotting.
      def push_one_level
        @dexpace_primary.emit if @dexpace_primary.respond_to?(:emit)
        nil
      end

      def push_all
        @dexpace_primary.flush if @dexpace_primary.respond_to?(:flush)
        nil
      end

      def release
        @dexpace_primary.close if @dexpace_primary.respond_to?(:close)
        nil
      end
    end
  end
end
```

`#buffer` is **defined rather than absent**, so the failure is that message and not a
`NoMethodError`. Design §10.10 already records the honest position and this task does not improve on
it: the prohibition cannot be language-enforced, `instance_variable_get` reaches anything, and 3a
builds no fake proof that it cannot.

- [ ] **Step 4: Write `sig/dexpace/io/tee_sink.rbs`**

```rbs
module Dexpace
  module IO
    class TeeSink
      include Dexpace::IO::TypedWrites
      include Dexpace::Closeable

      def initialize: (primary: Dexpace::IO::_Sink, ?tap_limit: Numeric) -> void
      def tap_snapshot: () -> String
      def tap_bytesize: () -> Integer
      def clear_tap: () -> nil
      def buffer: () -> bot
    end
  end
end
```

`#buffer`'s return type is `bot` — RBS's bottom type — because the method never returns.

- [ ] **Step 5: Add `require_relative "dexpace/io/tee_sink"` to `lib/dexpace.rb`**

After `dexpace/io/buffered_sink`. This is the last of the eight.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io/tee_sink_test.rb`
Expected: PASS, 23 tests. Then `bundle exec rubocop --fail-level=convention` and
`bundle exec rake rbs:validate steep`.

---
## Task 15: Wiring, the two regenerated artifacts, and the phase record

**Requirement IDs:** `NFR-4`'s surface lock and `NFR-3`'s signature gate over everything Tasks 3–14
added, plus the eight 🚫 rows the checklist has to carry — `IO-30`–`IO-36` and `IO-39`. **Design:**
"Prerequisites — From phase 0"; "The 42 IDs, with dispositions".

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace.rb` (verify, not extend), `test/fixtures/surface/dexpace-core.txt`
  (repository root), the `sig/**/*.rbs` baseline the API lock diffs against
- Create: `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-checklist.md`
- Modify: `CLAUDE.md` (the gem/phase claim sentences, if what they must say has changed)

**Interfaces:**
- Consumes: every task above.
- Produces: a green `bundle exec rake` on all four matrix rows, and the checklist that maps all 42
  `IO` IDs to a task, a deferral or a deviation.

**Deliberate, and last.** The two artifacts are regenerated **once**, on purpose, and **never to
silence a failure**.

- [ ] **Step 1: Verify `lib/dexpace.rb`'s require order**

Each task added its own line; this step confirms the result rather than writing it. The nine lines
this phase adds, in dependency order, after phase 2's `error/cancelled_error` and `dexpace/closeable`:

```ruby
require_relative "dexpace/error/stream_error"        # Task 3
require_relative "dexpace/error/end_of_stream_error" # Task 3
require_relative "dexpace/io"                        # Task 4
require_relative "dexpace/io/typed_reads"            # Task 5
require_relative "dexpace/io/buffered_source"        # Task 10
require_relative "dexpace/io/typed_writes"           # Task 11
require_relative "dexpace/io/buffer"                 # Task 12
require_relative "dexpace/io/buffered_sink"          # Task 13
require_relative "dexpace/io/tee_sink"               # Task 14
```

`lib/dexpace.rb` issues explicit `require`s for the whole tree rather than using an autoloader,
because every autoloader worth using is a gem — which also makes the require audit a text scan.
**`sig/dexpace.rbs` is unchanged**: every constant this phase adds has its own file under `sig/`.

- [ ] **Step 2: Run the require-allowlist and gemspec audits**

Run: `bundle exec rake gates:require_allowlist gates:gemspec_audit gates:clean_bundle`
Expected: PASS, unchanged. **This phase adds no `require` of any kind beyond `require_relative`** —
`::IO`, `::String`, `::Encoding`, `::Thread::Mutex`, `::Enumerator` and `::Float` are core Ruby, and
`stringio` is `test/`-only and already allowlisted. Re-verified on 3.2.11, 3.4.10 and 4.0.6 that
neither `stringio` nor `tempfile` appears in any `Gem::BUNDLED_GEMS::SINCE` table inside the
supported range, so neither is at risk of the bundled-gem trap.

- [ ] **Step 3: Regenerate the runtime surface snapshot**

Run: `bundle exec rake surface:regenerate`
Expected: `test/fixtures/surface/dexpace-core.txt` gains exactly these rows, and no others. Verified
by running phase 0's walker over the finished tree:

```
Dexpace
Dexpace::Closeable
Dexpace::Closeable# close closed? initialize_closeable owned?
Dexpace::ClosedError
Dexpace::EndOfStreamError
Dexpace::Error
Dexpace::IO
Dexpace::IO::Buffer
Dexpace::IO::Buffer# bytesize clear copy_to snapshot
Dexpace::IO::BufferedSink
Dexpace::IO::BufferedSource
Dexpace::IO::BufferedSource# owns_upstream? view?
Dexpace::IO::MAX_MATERIALIZED_BYTES : Integer
Dexpace::IO::TeeSink
Dexpace::IO::TeeSink# buffer clear_tap tap_bytesize tap_snapshot
Dexpace::IO::TypedReads
Dexpace::IO::TypedReads# each eof? getbyte initialize_typed_reads peek read read_exactly read_into read_line_utf8 read_string read_utf8 readbyte readpartial skip slice
Dexpace::IO::TypedWrites
Dexpace::IO::TypedWrites# emit flush initialize_typed_writes write write_all write_from write_string write_utf8
Dexpace::InvalidArgumentError
Dexpace::SeamError
Dexpace::StreamError
Dexpace::VERSION : String
```

Read the shape before accepting it: `Dexpace::IO::Buffer#` carries **four** method names, not
twenty-seven, because `public_instance_methods(false)` does not see a method reaching a class through
an included module — the module rows are where the other twenty-three live. That is P3-8's whole
reason for keeping `TypedReads` and `TypedWrites` public, and it is why **changing exports means
regenerating both artifacts**: the RBS diff and this snapshot each catch what the other cannot see.

- [ ] **Step 4: Regenerate the RBS baseline and run the API lock**

Run: `bundle exec rake rbs:validate steep gates:sig_diff gates:rbs_surface`
Expected: PASS. `gates:rbs_surface` asserts that no constant outside `Dexpace::` and a fixed stdlib
allowlist appears in any public signature (`NFR-11`); 3a's whole public surface names only `String`,
`Integer`, `Encoding`, `Numeric`, `Range` and `Enumerator`. **Task 2's change is invisible to
`gates:sig_diff` by construction** — `#closed?` keeps `() -> bool` — which is why that task carries
its own mechanism assertion.

- [ ] **Step 5: Re-run the cop suite and RuboCop over the finished tree**

Run: `bundle exec rake cops:test` then `bundle exec rubocop --fail-level=convention`
Expected: `cops:test` PASS, and `Dexpace/QualifiedCoreConstant` reporting **0 offenses** over the
finished `lib/` tree — verified over all nine new files plus phase 1's and phase 2's, which the
widened `Include:` now reaches. That is the claim this phase can make on its own.

**The whole-repository RuboCop run is not clean, and it was not clean before this phase either.**
Measured on RuboCop 1.90.0 with phase 0's `.rubocop.yml` exactly as written: phase 1's and phase 2's
`lib/` fences already report `Layout/EmptyLineAfterMagicComment` (32×, the two-line SPDX header phase
0 itself mandates), `Naming/RescuedExceptionsVariableName` (4×, `error` rather than `e`),
`Metrics/AbcSize` (8×), `Metrics/ClassLength`, `Style/SymbolProc` and others; 3a adds
`Metrics/ModuleLength` on the two vocabulary modules and `Metrics/AbcSize` on two store helpers to
the same list. **The gap is in the configuration, not in any one phase's code**, and closing it is a
reviewed `.rubocop.yml` diff that has to name the cop, the reason and the phases affected — the same
shape phase 0 fixed for the require allowlist. It is recorded as **`OI-6`** and it is deliberately
not closed here: 3a widened this cop's `Include:` and must not also be the phase that relaxes four
metric cops for everyone. Task 1 Step 6's expectation is the same one, narrowed to the cop 3a owns.

- [ ] **Step 6: Run every gate on every matrix row**

Run: `bundle exec rake`, then `mise exec ruby@3.2.11 -- bundle exec rake test:gems` and the same for
3.3 and 3.4.
Expected: PASS. Five assertions in this phase give a different answer on a single interpreter and
must be seen green on **every** row: the `StringIO`-backed BINARY read (the 3.4 encoding change
straddles the floor), the frozen-chunk ingress retag, the `Enumerator` `ensure` asymmetry, the
two-fiber `ThreadError`, and `IO.copy_stream`'s buffer reuse and `EOFError`-subclass termination.

- [ ] **Step 7: Write the checklist**

`docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-checklist.md`, one row per requirement
ID, using the roadmap's ✅ / 🚫 / ⏳ / N/A legend verbatim. Every one of `IO-1`–`IO-42` gets a row.

| Rows | Disposition |
|---|---|
| `IO-1`, `IO-2`, `IO-3` | ✅ Task 5 |
| `IO-4` | ✅ Task 11, re-tested Task 13 |
| `IO-5` | ✅ Tasks 11, 13 |
| `IO-6` | ✅ Tasks 10, 13 |
| `IO-7`, `IO-8`, `IO-10` | ✅ Task 12 |
| `IO-9` | ✅ Tasks 6 and 12 — six guarded sites, and the one allocating test |
| `IO-11`, `IO-12`, `IO-13`, `IO-15` | ✅ Task 6 |
| `IO-14` | ✅ Task 7 |
| `IO-16` | ✅ Tasks 8, 10, 13 |
| `IO-17` | ✅ Task 11 |
| `IO-18` | ✅ Tasks 11, 12, 13 |
| `IO-19`–`IO-24` | ✅ Task 9, green in Task 10; `IO-22`'s invalidation also Task 12 |
| `IO-25`–`IO-29` | ✅ Task 14 |
| `IO-30`, `IO-31`, `IO-32`, `IO-33`, `IO-34`, `IO-35`, `IO-36`, `IO-39` | 🚫 permanent simplification, `docs/sdk-design-ruby/10-…md` item 1 and §12's `IO` row. **`IO-30`'s behavioural clause survives as a property of `.of_bytes`** (Task 10) even though the ID is 🚫, because it is a behaviour and not apparatus |
| `IO-37`, `IO-38` | ✅ Tasks 2 and 10, with `DEF-33` cited at `IO-38` |
| `IO-40` | ✅ by construction — no method in 3a takes a timeout, a deadline or a `Cancellation`; Task 14 carries the mirroring clause |
| `IO-41` | ✅ Tasks 10, 12, 13, 14 |
| `IO-42` | ✅ Tasks 10, 12, 13, 14 — both directions, two tests that fail in opposite ways |

- [ ] **Step 8: Record what the phase decided, in the right place**

- **Deviations.** The design filed P3-1 through P3-12; Task 8 adds **P3-13**. All thirteen go in the
  phase document's `## Deviation Ledger`, are consolidated into design §10, and are audited by
  `docs/deviations.md`.
- **Deferrals.** `DEF-33` was filed by the design and is cited at `IO-38`'s row. **This plan files
  none.** The register was read in full and no row is picked up: `DEF-26` and `DEF-3` are 3b's and
  phase 8's, `DEF-27` gains no `close_quietly` caller here (every close in 3a is either a caller's
  explicit `#close`, which propagates, or a `#release`, which propagates once — §3.7's two loud
  exceptions), `DEF-28` is named as a constraint rather than a deferral, `DEF-29`'s condition stays
  unmet while its row is strengthened by three more doubles, and `DEF-32` has no notifier here.
- **Open items.** This plan files **`OI-4`** and **`OI-6`** (below). `OI-2`, `OI-3` and `OI-5` stay
  open and none is 3a's to close.
- **Release blockers.** None. Nothing is published and every gem stays at `0.0.0`.

- [ ] **Step 9: Update `CLAUDE.md`'s claims sentences if what they must say has changed**

Run: `ruby .claude/skills/housekeeping/probe.rb --only claims`
The gem-count sentence changes when phase 0 lands, not here; the phase-directory sentence changes
when this plan is filed. **Never rewrite prose to satisfy a check** — the probe says what is wrong and
where, and the judgement about what the sentence should say is yours.

---

## The two findings filed against `docs/open-items.md`

**`OI-4` — a source retains every view derived from it until it is closed, and `Array#delete` makes
the deregistration O(n).** `TypedReads` keeps `@dexpace_views` so that a close can invalidate every
outstanding view (`IO-22`, `IO-38`, `IO-42`). A view removes itself on its own `#close`, through
`#dexpace_forget_view`, but a caller that takes many views and closes none — which nothing forbids —
grows that array for the parent's lifetime, and each later close is a linear scan. It is bounded in
this SDK by construction: every `#peek` caller here is a bounded preview and the parent is a response
body whose lifetime is one request. It is recorded because phase 3b builds `BODY-22`–`BODY-29`'s
response-logging drain on `#peek` and `#slice` **per attempt on a retried request**, which is the
first place the bound stops being obvious. What would resolve it: nothing mechanical is warranted yet
— a weak reference table would trade a real, measurable cost for a hypothetical one, and the
`ObjectSpace`-based alternative is barred by `resource-management/1676974d` and design §7.1's rule
that the GC is not a cleanup hook. What a later phase should do first is measure, on 3b's actual
drain.

**`OI-6` — RuboCop's own report is not clean for any phase under `.rubocop.yml` as phase 0 wrote
it.** Measured on RuboCop 1.90.0 against phase 0's config exactly as that plan writes it: phase 1's
and phase 2's `lib/` fences already report 32 `Layout/EmptyLineAfterMagicComment` offenses — on the
two-line SPDX header **phase 0 itself mandates** — plus `Metrics/AbcSize` ×8,
`Naming/RescuedExceptionsVariableName` ×4 (this repository has written `=> error` since phase 1)
and a dozen others, and 3a adds `Metrics/ModuleLength` on its two vocabulary modules. `NFR-7` makes
findings fatal, so a gate that cannot pass is one whose `--fail-level` gets lowered by whoever first
runs `bundle exec rake`, and every plan's "Expected: clean" step is unfalsifiable until it does
pass. One finding inside it is **not** a configuration gap: `Style/SymbolProc` on
`@dexpace_views.each { |view| view.dexpace_invalidate }` must not be autocorrected, because
`#dexpace_invalidate` is `protected` and `&:dexpace_invalidate` sends it publicly. Resolving it is
one reviewed `.rubocop.yml` diff naming each cop and its reason, against the RuboCop version
`VERSIONS` pins — and it belongs to phase 0's owner, not to the phase that widened one cop's
`Include:`.

`OI-2`, `OI-3` and `OI-5` remain open and unchanged; none is 3a's to close.

---

## Deviation Ledger

The design filed P3-1 through P3-12 and they are not restated here. This plan adds one.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P3-13 | `#read` and `#readpartial` leave `outbuf` tagged `Encoding::BINARY` whatever tag it arrived with, where `::IO#read` preserves the destination's tag | `IO-16`; design §3.1's "bytes on the wire are always `Encoding::BINARY`" and its ingress-retag rule; verified fact 6 | The bridge's stated contract is "Ruby's semantics", and on this one point Ruby's own readers disagree with each other and across this port's floor: verified on 3.2.11, 3.4.10 and 4.0.6 that `::IO#read(n, buf)` preserves a UTF-8 destination's tag on all three, while `StringIO#read(n, buf)` gives ASCII-8BIT on 3.2.11 and UTF-8 from 3.4.10 — the same floor-straddling shape design §3.5 pins `URI::RFC3986_PARSER` against. Both preserve a BINARY destination on all three, so pinning BINARY is the one answer that is identical on every matrix row and behind every backing stream, and it is what §3.1's "core retags on ingress rather than trusting a declared charset" asks for. `IO.copy_stream` never reads the destination's tag, so R4's bridge claim is unaffected — asserted end to end in Task 10, not argued |

---

## Self-review against the design

**Spec coverage.** All 42 `IO` IDs have a task or a 🚫 row in Task 15's checklist table; the design's
"Also fixed by 3a without owning a new ID" trio — §10.2's canonical body representation,
`BufferedSource.over` with its no-ownership exception, and `MAX_MATERIALIZED_BYTES` — are Tasks 8/10,
10 and 4 respectively. The design's four risks are answered: R1 by Task 1 and Task 4's YARD block,
R2 by Task 5, R3 by Task 10, R4 by Tasks 8 and 10. Its three open questions are answered above. The
3a→3b contract table is shipped complete: `TeeSink`'s seven methods plus `#clear_tap` and the raising
`#buffer` (Task 14), `Buffer.new` with the whole read and write surface (Tasks 11–12),
`#read_exactly` and `#write_all` with `IO-17`'s rule and both `StreamError` helpers (Tasks 3, 6, 11),
`#peek`/`#slice` and `Buffer`'s post-close readability (Tasks 9, 12), `MAX_MATERIALIZED_BYTES` (Task
4), `BufferedSource.wrapping` with ownership (Task 10), `#read_string`/`#read_utf8` (Task 6),
`IO-6`'s half stated once (Task 10), and `_Chunked` with `BufferedSource#each` (Tasks 4, 8).

**Boundaries.** No task builds a body variant, `#replayable?`, a media type or a content length; no
second decode site is added and `#read_string`/`#read_utf8` retag without a replacement policy;
`Request#body` and `Response#body` are not narrowed in `sig/` (`DEF-26` stays 3b's); nothing adds
`#body_string` or `#close` to `Dexpace::Response`; no logging wrapper is built. No recovery-chain
step, error-to-exception mapping or new `close_quietly` caller. No configuration, clock, deadline,
`deadline:` keyword, `max_materialized_bytes:` keyword or instrumentation event. No SSE line machine
over `IO-14`, no `SSE-12` BOM rule, no pagination engine, and the codec's close-nothing rule is
neither implemented nor weakened. No transport, socket, `body_stream=` adaptation or wire-boundary
re-validation — `IO.copy_stream` appears only as a test driver. `XCUT-15` and `XCUT-18` are left
satisfiable and not claimed. **No fourth registry, no factory, no installation call, no discovery.**

**Type consistency.** `#read_into(dest, count:)`, `#slice(offset:, count:)`, `#write_from(buffer,
count:)` and `#copy_to(other, offset:, count:)` carry the same keyword names everywhere they appear;
`#fill(min_bytes)` and `#deliver(string)` are the two hook names and neither is spelled another way;
`.short_transfer(transferred:, expected:)` and `.zero_read(requested:)` are called from Tasks 11, 13
and 14 with exactly the keywords Task 3 defines; `#dexpace_release_views` is defined in Task 5 and
called from Tasks 10 and 12 under that name.
