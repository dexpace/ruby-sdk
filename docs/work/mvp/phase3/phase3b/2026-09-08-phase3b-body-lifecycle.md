# Phase 3b — Body Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship everything a payload is between a caller and a socket — one shared body contract with
eight factories, seven request-body variants, one response body, the materialize-once guard, the
bounded error copy, two logging wrappers, the one decode boundary and the lazy typed-response
wrapper — satisfying the 47 implemented IDs of phase 3b's 49.

**Architecture:** One public module, `Dexpace::Body`, supplies the whole vocabulary over one hook
its includers define — `#write_to(sink) -> Integer` — exactly as 3a's `TypedReads` does over
`#fill`. `#each`, `#to_replayable`, the two copy routines and the consume-once latch are derived
there once, so eleven classes cannot drift. Every constant is **flat** under `Dexpace::` and filed
under `lib/dexpace/http/body/`, because a `Dexpace::Body::` namespace's natural member names are
`File`, `Buffer` and `Response` and that shadowing is silent for `is_a?` and `case/when`. The only
synchronised state in the sub-phase is four flag flips — `BODY-6`/`BODY-7`'s consume-once,
`BODY-9`'s rewind, `BODY-22`'s drain and `HTTP-45`'s parse — each under a `Thread::Mutex` held
across the flip and across nothing else.

**Tech Stack:** Ruby 3.2–4.0 (development on 4.0.6), no runtime dependencies, Minitest, RBS + Steep,
RuboCop with phase 0's five custom cops plus phase 2's sixth as 3a widened it, SimpleCov, YARD.

**Spec:** `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md`, under the
charter `docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md`, on top of
`docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts.md`.

## Global Constraints

Every task's requirements implicitly include this section. Values are copied verbatim from the
design and the governing documents.

- **`dexpace-core` gains no dependency and no allowlist entry.** The gemspec keeps zero
  `add_dependency` lines (`SEAM-1`, `NFR-1`). This phase adds exactly one `require` beyond
  `require_relative` — `require "securerandom"` in `multipart_body.rb`, for `HTTP-51`'s spec-valid
  random boundary — and `securerandom` is already on phase 0's twelve-name allowlist. `::File`,
  `::IO`, `::IO.copy_stream`, `::String`, `::Encoding`, `::Thread::Mutex` and
  `::Thread::ConditionVariable` are core Ruby and need none. `stringio` and `tempfile` are used in
  `test/` only.
- **`IO-40` forbids a clock.** No method in 3b takes a timeout, a deadline or a `Cancellation`, and
  no task reaches for `DEF-28`'s `deadline:` keyword. The only blocking calls are the delegate's own
  reads and the sink's own writes.
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`;
  `docs/knowledge/notes/formatting-and-tooling.md`). No `# typed:` sigil anywhere.
- **Banned, and each is a blocking cop:** `Time.parse`/`Date.parse`/`DateTime.parse`;
  `URI::DEFAULT_PARSER` and the `URI.parse`/`URI.join`/`URI.split` family; any argument to
  `downcase`/`upcase`/`capitalize`/`swapcase` and `casecmp?`; `Timeout.timeout`, `Thread#raise`,
  `Thread#kill`.
- **Inside `module Dexpace`, anywhere, write `::Thread`, `::Queue`, `::Mutex`, `::SizedQueue`,
  `::ConditionVariable`, `::JSON`, `::IO` and `::File`** — never the bare name. 3a's widened
  `Dexpace/QualifiedCoreConstant` enforces it, and 3b is the phase that consumes it at scale:
  `::IO.copy_stream`, `::IO::SEEK_SET` and `::File.open` all appear here.
- **3b creates no constant that shadows a core class**, so 3a's `SHADOWED` list is unchanged.
  `Dexpace::FileBody` and `Dexpace::BufferBody` shadow nothing, which is the whole reason the names
  are flat.
- **Core never writes `is_a?(IO)`.** Every caller-supplied stream, sink and `#each`-shaped object is
  checked with `respond_to?` — `api-design/88e6bf12`'s narrowest duck-typed interface.
- **Bytes are always `Encoding::BINARY`, except at the single decode boundary.** Every chunk a body
  yields, every `String` `#snapshot` and `#preview` return, and every byte written to a sink is
  BINARY. `Response#body_string` is the only place in this SDK that turns bytes into text.
- **`String#b` is the ingress retag, never `force_encoding`** — `io-and-byte-streams/a44b4de6` and
  `docs/knowledge/notes/io-and-byte-streams.md`: `force_encoding` raises `FrozenError` on a frozen
  `String` even when the target encoding is already its own, and a Rack-shaped body's `#each` yields
  frozen literals.
- **Every encoding test uses non-ASCII content.** Appending an ASCII-only UTF-8 `String` to a BINARY
  one leaves it BINARY while a non-ASCII one silently retags the result, so an ASCII-only fixture
  passes under exactly the bug.
- **A `Thread::Mutex` is held across a flag flip and across nothing else.** Never across a write, a
  drain, a parse or a `#release`. Ruby's `Mutex` is non-reentrant and per-fiber-owned.
- **Two error vocabularies, and no third. 3b defines no new error class.**
  `Dexpace::InvalidArgumentError` (phase 1's) for a caller mistake in an argument;
  `Dexpace::StreamError` (3a's) for a stream-contract violation — a second write, a short transfer,
  a short write, a zero read, a second tail read; `Dexpace::ClosedError` (phase 2's) for
  use-after-close; `Dexpace::EndOfStreamError` where a read form cannot report EOF another way.
- **`#content_length` is `-1`, never `nil`.** `BODY-35` fixes the sentinel in normative text and an
  ID-bearing rule beats the styleguide's nil-as-absence default; 3a took the same `-1` for `IO-1`.
- **Every count and offset beyond the first positional subject is a keyword** (3a's P3-9). The
  stated exceptions are the two private copy routines, whose third argument is the count they are
  named for.
- **Formatting:** double quotes, 2-space indent, **100 columns**, `consistent_comma` trailing
  commas, leading-dot chains, `MethodLength: 25` with `CountAsOne`, `ParameterLists: 4`,
  `BlockNesting: 3`.
- **Tests:** Minitest only, `FooTest < DexpaceTestCase`, `test "..." do` blocks, `test/` mirroring
  `lib/` one file per file, `assert_equal(expected, actual)` in that order, every test passing alone
  and in any order, the seed never overridden. Each test file's header comment names the requirement
  IDs it exercises. **Visibility is asserted with `respond_to?`, never `assert_predicate`** — phase
  1's finding, that Minitest sends past `private` on the 3.2 floor.
- **`ObjectSpace` is never used to prove cleanup.** Barred twice — `resource-management/1676974d`
  and design §7.1 — because an `ObjectSpace` sweep answers "has the collector got to it yet", which
  is exactly the question a deterministic-cleanup test must not ask. Where a descriptor count is the
  only honest proof, `/proc/self/fd` is counted and the test skips where `/proc` is absent.
- **Every public constant gets three artifacts in the same task**: the implementation, a YARD block
  that explains *why* and never restates a type, and an `.rbs` mirror at the same path under `sig/`.
  **No task writes only `sig/`.**
- **No commit step appears in any task.** The manager commits once per phase.
- **Never edit** `docs/product-spec/`, `docs/sdk-design-ruby/`, `docs/knowledge/harvested/`, or
  phase 3a's two documents.

### Commands

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/<path>_test.rb   # one suite, red or green
(cd gems/dexpace-core && bundle exec rake test)                     # the gem's whole suite
bundle exec rake                                                    # all seventeen gates
mise exec ruby@3.2.11 -- bundle exec rake test:gems                 # the floor, locally
bundle exec rake surface:regenerate                                 # deliberate; Task 14 only
```

### What was verified during planning, and how to re-verify it

**Every `ruby` and `rbs` fence in this document was extracted, written to the file it names and
run** — not a prototype it was transcribed from. The gem tree was built on top of the committed
phase-3a plan's own `lib/` fences (`typed_reads.rb` reassembled from its five task fragments,
`buffer.rb`, `buffered_source.rb`, `buffered_sink.rb`, `tee_sink.rb`, `typed_writes.rb`, `io.rb` and
the two error classes, all extracted verbatim), phase 2's `Closeable` with 3a's P3-6 one-line
change, phase 1's `Model`, `Error`, `InvalidArgumentError`, `PercentEncoding`, `Status`, `Method`
and `HeaderSyntax` fences, and stand-ins for the phase-1 types whose plan states them as prose
rather than as a fence (`MediaType`, `Protocol`, `Headers`, `URL`, `Request`, `Response`). 3a's own
`buffer_test.rb`, `tee_sink_test.rb` and `buffered_source_test.rb` were run against the assembled
tree first and pass — 22/225, 23/144 and 32/93 — so the substrate is 3a's and not an approximation
of it.

The result for **phase 3b's fourteen suites**, identical on **3.2.11, 3.4.10 and 4.0.6** and
warning-free under `ruby -w` with `RUBYOPT=-W:deprecated`:

```
275 runs, 791 assertions, 0 failures, 0 errors, 0 skips   # 927 assertions on 4.0.6
```

The run count is identical on all three and identical across every seed tried; **stderr was empty
on every row**. The assertion count differs on 4.0.6 for phase 2's stated reason — 3.2, 3.3 and 3.4
resolve Minitest 5.x and 4.0 resolves 6.0.0, and the two count some
`assert_operator`/`assert_predicate` calls differently; 3b's delta is larger than 3a's only because
3b's suites use more of them. `rbs -I sig validate` exits 0 on all three interpreters with
`rbs 3.8.0`.

Those numbers are the **post-review** ones. The plan's adversarial review rebuilt the tree from this
document's fences a second time, on the same 3a substrate — 3a's own `buffer_test.rb`,
`tee_sink_test.rb` and `buffered_source_test.rb` reproduce 22/225, 23/144 and 32/93 against it — and
found four defects the first run could not see, because the phase-1 stand-ins it used were more
permissive than phase 1's real `Request` and `Response`. They are listed under "The mutation
battery" below and are fixed in the tasks above.

**The mutation battery was run, and it is the reason to believe the suites.** Fifty single-edit
mutations, each reverting one requirement's mechanism, were applied one at a time to the finished
tree and the owning suite re-run. **All fifty were caught**; the table is in "The mutation battery"
below. Three were *not* caught on the first pass and each exposed a real weakness that is fixed in
the tests this plan ships — a race-safe-rewind test that raced instead of overlapping, an `IO-42`
test that could not see the buffer being closed, and an `HTTP-45` test that never made a raw
accessor contend for the lock.

**One thing that run was not.** It is not the seventeen gates: no Steep, SimpleCov, RuboCop or YARD
is installed here. Task 14's steps are therefore real checks, not formalities, and `OI-6` records
that RuboCop is clean for no phase under `.rubocop.yml` as phase 0 wrote it — 3b inherits that and
does not resolve it.

### The verified Ruby facts this plan is built on

Re-run on 3.2.11, 3.4.10 and 4.0.6 through `mise exec ruby@<v>` on 2026-09-08. Every one of the
design's ten facts reproduced **identically on all three**, and two more were found while planning.

| # | Fact | Constrains |
|---|---|---|
| 1 | `"café".b.encode(::Encoding::UTF_8, invalid: :replace, undef: :replace)` is `"caf"` + **two** U+FFFD. Retagging first yields `"café"`. `#encode` with **no target** converts to `Encoding.default_internal`: with it set to ISO-8859-1 the same call returns ISO-8859-1 with the accent destroyed, while the explicit-target form is unaffected | Task 8 |
| 2 | `respond_to?(:rewind)` is `true` for a pipe, a socket, a `StringIO` and a `File` alike. `origin = io.pos; io.seek(origin, ::IO::SEEK_SET)` raises `Errno::ESPIPE` on a pipe and is a genuine no-op on a seekable stream at any position. `Errno::ESPIPE` is a `SystemCallError` and **not** an `IOError` | Task 4 |
| 3 | An **ordinary** `#each` method leaks like an `Enumerator.new` block: `#next`-then-abandon leaves the `ensure` unrun after two `GC.start`; `#rewind` does not run it; `#each`-with-`break` **does**; a full external drive to `StopIteration` **does**; and `block_given?` is `true` under `to_enum(:each)` | Tasks 1, 6, 9 |
| 4 | `::IO.copy_stream(handle, duck_sink, 4, 3)` delivers `"3456"` as BINARY, returns `4`, and leaves the source `File`'s own cursor at `0`; with no offset the cursor advances to the end | Task 6 |
| 5 | A source responding to `#to_path` still honours `copy_stream`'s `(length, offset)`, but `copy_stream(obj, sink)` with **neither** copies the whole file | Task 6 |
| 6 | `raise cached_error` re-raises the same object with its `#cause` and its original backtrace intact, from a different frame and repeatedly | Tasks 11, 12 |
| 7 | `fz.b.frozen?` is `false`, `fz.b.equal?(fz)` is `false`, and `force_encoding` on a frozen `String` raises `FrozenError` even when the target encoding is already its own | Tasks 1, 5 |
| 8 | A `Thread::Mutex` held across a fiber suspension raises `ThreadError: deadlock; lock already owned by another fiber belonging to the same thread` for a second fiber of the same thread; nested `synchronize` raises `ThreadError: deadlock; recursive locking` | Tasks 4, 11, 12 |
| 9 | `Tempfile#close` leaves the path on disk and `#unlink` removes it | `test/` only |
| 10 | `byteslice` past the end returns `nil`, `byteslice(0, n)` past the end returns what exists, and `[Float::INFINITY, n].min` is an `Integer` | Tasks 8, 9 |
| **11** | **`Encoding.default_internal = x` emits `warning: setting Encoding.default_internal` under `ruby -w`, and `DexpaceTestCase`'s `Warning.warn` override turns it into a failure — both the set AND the restore.** A `$VERBOSE = nil` around the two assignments only, restored immediately, suppresses exactly those two and leaves `-w` live for everything else. Verified both ways on all three | Task 8 |
| **12** | **`Dexpace::IO::BufferedSource.wrapping(io)` delivers ONE BYTE per `#read_into` call and yields one-byte chunks from `#each`** — 200 000 chunks for 200 000 bytes, ~0.21 s where the `Buffer` and `.over` paths are unmeasurable. `#read(n)` is the only efficient path and it blocks for `n`. Uniform on all three | `OI-9`; no 3b test depends on the granularity |

Fact 11 is a plan-level finding the design could not have had: **the design's own mandated test — "run
half the decode property runs with `Encoding.default_internal = ::Encoding::ISO_8859_1` and restore
it in an `ensure`" — cannot be written that way**, because under `NFR-6` the assignment is a
failure. Task 8 ships the narrow helper that makes it writable and asserts, in a test of its own,
that `-w` is still live inside the block.

Fact 12 is a cross-phase finding against 3a, filed as **`OI-9`**. It is a throughput defect and not
a correctness one — every read is correct — and it is not 3b's to fix. No test in this plan asserts
a chunk granularity either way, so 3a's one-line fix lands without touching a line of 3b.

### Decisions this plan makes, which the design left to it

The design's "Open questions for 3b's own plan" names five. All five are answered here, and five
further choices are recorded so they are not re-derived at a task boundary.

**1. Task order.** The segmentation design's hard ordering is stated and obeyed: `BODY-1`–`BODY-16`,
`BODY-35`, `HTTP-36`–`HTTP-43` and `HTTP-51` land **before** `BODY-17`–`BODY-34`, `BODY-37`,
`HTTP-44`, `HTTP-45` and `HTTP-52`, because every wrapper wraps a body. Within the first group:
`Dexpace::Body` and `BytesBody` first, because every later test needs a body it can trust and a
`#write_to` to test against; `BufferBody` second, because `#to_replayable` returns one and it unlocks
the materialize-once test for every single-use variant; `StreamBody` third, because the consume-once
latch and the rewind probe both live there and the latch is then reused; `ChunkedBody` and `FormBody`
fourth; `FileBody` fifth, needing only `Dexpace::Body`; `MultipartBody` sixth, needing all of them
for its parts. The form encoder is its own task and is independent of everything, scheduled third so
`FormBody` has it.

**2. `MultipartBody#content_length` computes LAZILY and memoises.** `HTTP-51` fixes that the length
and the bytes come from one routine; it does not fix when. A multipart body over eight file parts
must not stat eight files to answer a header question that may never be asked. `-1` is truthy in
Ruby, so `@content_length ||= compute_content_length` memoises the unknown sentinel correctly too.
The consequence is that **`MultipartBody` is not frozen**, and Task 7 ships the test the
recommendation asked for: the memoised value still equals the bytes written, after several writes.
`IO-37` already says no body is thread-safe as a general contract, and two threads computing the
same pure value produce the same answer.

**3. `Body.string(text, media_type:, encoding: ::Encoding::UTF_8)` encodes EAGERLY, at
construction.** `#content_length` is then exact, and a caller's later mutation of the source `String`
cannot reach the body — 3a's `.of_bytes` independent-copy property, applied to text. It is one
`#encode` plus one `#b` at construction and nothing at write time. `Body.bytes` takes the same
independent frozen copy for the same reason, which is why both return a `BytesBody`.

**4. The chunk size `#write_to` uses when copying from a source is whatever the source's own read
returned.** `copy_exactly` asks `#read_into(dest, count: remaining)` for the whole remaining count
and writes exactly what came back, so the upstream's own boundaries survive to the sink and
`BODY-17`'s byte-exact mirroring sees them. `FileBody` delegates the question entirely to
`::IO.copy_stream`. **This layer invents no block size**, which is also why fact 12 is `OI-9`'s and
not this plan's to work around: when 3a's fill hint is fixed, 3b's chunking improves with it and no
3b test changes.

**5. `OI-4`'s measurement, run.** Task 13 is the measurement task the design asked for, and it is a
task rather than a note because the number is the deliverable. Measured on all three interpreters,
on the actual `BODY-23` drain:

| Live views on one captured buffer | Registered | `Array#delete` cost to close them all |
|---|---|---|
| 1 | 1 | 0.0000 s |
| 100 | 100 | 0.0001 s |
| 1 000 | 1 000 | 0.0045 s / 0.0046 s / 0.0051 s |
| 10 000 | 10 000 | 0.4556 s / 0.4830 s / 0.5210 s |

Exactly one view is registered per `BODY-23` read and it stays registered until the caller closes it;
a view holds **no bytes** until read (`@dexpace_buffered` is 0) and costs 9 allocated objects on
3.2.11 and 3.4.10, 10 on 4.0.6. Deregistration is quadratic in the number of live views — ten times
the views costs about a hundred times the close — and closing in reverse order (0.2373 s / 0.2684 s /
0.3216 s at 10 000) only halves it. **The verdict: `OI-4`'s bound stops being obvious above roughly
1 000 simultaneously-live, unclosed views on one captured body, and nothing in `BODY-22`–`BODY-29`
produces that shape** — a fits-cap capture is read once and occasionally a handful of times, and at
100 reads the cost is 0.1 ms. The plan changes nothing in 3a's view registry, which is what `OI-4`
asked; it records the number in `OI-4`'s resolution field.

**6. `close: true` forces single-use, and it is `BODY-8` stated literally rather than an extra
rule.** `BODY-8`'s own text says "the rewindable variant must keep it open to replay, and the
one-shot variant leaves the caller-supplied stream unclosed". A body that closes its stream as part
of its one write cannot rewind it for a second, so `StreamBody#replayable?` is the conjunction of
`BODY-9`'s three conditions **and** `!@close`. `#rewindable?` stays separately observable, so a test
can tell "the probe said no" apart from "ownership forbids it".

**7. `StreamBody` reads through a fresh `Dexpace::IO::BufferedSource.wrapping(@io)` per write, and
does not close it unless it owns the stream.** This is `IO-6` used exactly as written and **not** the
borrowing variant 3a declines to ship (P3-12): the wrapper's close still closes the stream; this body
simply does not call it. It keeps one reader in the SDK instead of two, and the wrapper itself owns
nothing but memory. A fresh wrapper per write is `FileBody`'s fresh-handle rule applied to the same
problem: a wrapper carried across writes would replay bytes it had already buffered.

**8. `Dexpace::Body` carries TWO private copy routines, one per direction, not one.**
`copy_exactly(source, sink, count)` is `HTTP-39`/`BODY-10`'s exact-length pump and `BODY-25`'s zero
read; `emit_exactly(sink, string)` is one already-materialised `String` to a `#write`-shaped sink,
with the ingress retag and the short-write check. Both raise through 3a's
`StreamError.short_transfer`, so `BODY-13`'s "one helper so the message form cannot diverge" holds
across the pair — which is what the requirement actually fixes. Folding them into one would mean
either allocating a `BufferedSource` per `BytesBody` write or duplicating the short-write check in
eight classes.

**9. `ResponseLoggingBody` tells `BODY-23` from `BODY-24` by reading ONE more byte, not by peeking.**
`BODY-23` is "end-of-stream reached before the cap" and `BODY-24` is "cap hit with bytes still
pending", and after taking exactly `preview_bytes` the wrapper cannot know which without asking. It
asks with `read_into(probe, count: 1)`: `-1` means fits-cap, and a byte means over-cap. The byte is
**kept outside the capture** — held aside and replayed by the composite between the prefix and the
tail — so no byte is lost and the snapshot is still exactly the cap the caller set. The
alternative, `#eof?`, would widen what a delegate's source must provide beyond
`Dexpace::IO::_Source`'s single `#read_into`, which is the contract `FakeSource` is built to be.

**10. `Body.buffer_bounded` drains through `#each` with a `break`, not through a bounded sink.**
`#each`-with-`break` runs the body's own `ensure`s on all three interpreters (fact 3), so a
`FileBody`'s handle still closes; and stopping the pull is what makes "the bytes beyond the cap are
not read" true rather than "read and discarded". The truncation is markerless — no ellipsis, no
sentinel — because `BODY-30` says "dropping bytes beyond the cap" and a marker would corrupt a
`Content-Length` a caller might still trust.

---

## File Structure

Grouped by responsibility. Every file below is created by exactly one task, and every `lib/` file
gets its `sig/` mirror and its `test/` mirror **in that same task** — phase 1's rule. Paths are
relative to `gems/dexpace-core/` unless stated otherwise.

**The contract and the simplest variant (Task 1).** `lib/dexpace/http/body.rb` — `Dexpace::Body`, its
eight factories, `MAX_BUFFERED_ERROR_BODY_BYTES`, the two private copy routines, the shared
consume-once latch and the two private sink shapes — and `lib/dexpace/http/body/bytes_body.rb`,
with `test/support/fake_body.rb`. First, because every later test needs a body it can trust, and
because `body_test.rb`'s own `#each` tests need a body whose chunk boundaries the test chose.

**The materialize-once product (Task 2).** `lib/dexpace/http/body/buffer_body.rb`.

**The form encoder (Task 3).** `lib/dexpace/http/percent_encoding.rb`, modified — two functions
beside the RFC 3986 pair, in one file, because `url-and-query-encoding/9ff11c34` asks for two
distinct functions and not two modules, and adjacency with the comment between them is the strongest
guard against interchanging them.

**The stream variants (Tasks 4–5).** `lib/dexpace/http/body/stream_body.rb`, then
`lib/dexpace/http/body/chunked_body.rb` and `lib/dexpace/http/body/form_body.rb`.

**The file variant (Task 6).** `lib/dexpace/http/body/file_body.rb`. Independent of Tasks 2–5.

**The composite (Task 7).** `lib/dexpace/http/body/multipart_body.rb`, with the nested `::Part`.

**The response side (Task 8).** `lib/dexpace/http/body/response_body.rb`, and
`lib/dexpace/http/response.rb` modified with `#close`, `#body_string` and `#body_bytes`.

**The bounded error copy (Task 9).** `lib/dexpace/http/body.rb` again — `.buffer_bounded` and its
two private helpers. It is a second task on one file because it needs Tasks 2 and 8 to exist and a
reviewer could reject it while approving Task 1.

**The wrappers (Tasks 10–11).** `lib/dexpace/http/body/request_logging_body.rb`, then
`lib/dexpace/http/body/response_logging_body.rb` with `test/support/fake_response_body.rb`.

**The lazy typed response (Task 12).** `lib/dexpace/http/typed_response.rb`, and the
`Dexpace::_ResponseHandler` interface in `sig/dexpace/http/body.rbs`.

**The measurement (Task 13).** No `lib/` file. It records a number in `OI-4`.

**Wiring and closing (Task 14).** `lib/dexpace.rb`, `sig/dexpace/http/{request,response}.rbs`, the
repository-root `test/fixtures/surface/dexpace-core.txt`, the RBS baseline, and the checklist.

**Twelve new `lib/` files with twelve `sig/` mirrors and fourteen `test/` mirrors, three modified
`lib/` files, two modified `sig/` files, two new test-support doubles.** `Dexpace::Body::Part` does
not exist: `MultipartBody::Part` is nested under its own class, which is phase 1's `Request::Builder`
shape and not a new namespace.

---
## Task 1: `Dexpace::Body` and `Dexpace::BytesBody`

**Requirement IDs:** `HTTP-36` (the whole contract), `HTTP-38`/`BODY-35`'s `.bytes` and `.string`,
`BODY-1`'s default, `BODY-35`'s `-1` sentinel, `HTTP-39`/`BODY-10` and `BODY-13`'s copy routines,
`BODY-25`'s zero read, `BODY-32`'s cap rules, `HTTP-46`'s by-value equality, §10.2's `#each`, and
deviations **P3-14**, **P3-20**, **P3-21**, **P3-22**.
**Design:** "`Dexpace::Body` — the contract, the factories, the constants"; R6.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/body.rb`,
  `gems/dexpace-core/lib/dexpace/http/body/bytes_body.rb`, and the two `sig/` mirrors at
  `gems/dexpace-core/sig/dexpace/http/body.rbs` and
  `gems/dexpace-core/sig/dexpace/http/body/bytes_body.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/support/fake_body.rb`,
  `gems/dexpace-core/test/dexpace/http/body_test.rb`,
  `gems/dexpace-core/test/dexpace/http/body/bytes_body_test.rb`

**Interfaces:**
- Consumes: 3a's `Dexpace::IO::Buffer`, `Dexpace::IO::MAX_MATERIALIZED_BYTES`,
  `Dexpace::StreamError.short_transfer(transferred:, expected:)` and `.zero_read(requested:)`,
  `Dexpace::IO::BufferedSource.of_bytes`; phase 1's `Dexpace::InvalidArgumentError`.
- Produces: `Dexpace::Body` — the module every later variant includes — with `#write_to(sink)`,
  `#media_type`, `#content_length`, `#replayable?`, `#to_replayable`, `#each`, the factories
  `.bytes` `.string` `.file` `.stream` `.chunked` `.form` `.multipart` `.buffer`, the private
  class method `clamp_cap(cap)`, and the private instance methods `counting_sink`,
  `copy_exactly(source, sink, count)`, `emit_exactly(sink, string)`, `initialize_single_use`,
  `claim_single_use!`, `claim_replay!`, `release_replay!`. Also `Dexpace::BytesBody`, and
  `FakeBody` — Tasks 2, 9, 10 and 11 all use it. Tasks 2–14 all depend on this task.

**First, because every later task needs a body it can trust and a `#write_to` to test against.**
The `#each`-from-`#write_to` derivation and the two copy routines are written once here and never
again — that is P3-21's whole content, and it is why `BODY-17`'s "the exact bytes the wrapped
body's single write produces" cannot mean two different things on the two paths.

- [ ] **Step 1: Write `test/support/fake_body.rb`**

It lands **here**, not with the wrapper that reads it most, because `body_test.rb` below requires
it and five of that file's own tests use it: `#each`'s derivation has to be asserted against a body
whose chunk boundaries the test chose. It is also the only deterministic route to `BODY-20`'s "the
snapshot returns the bytes mirrored up to the failure" in Task 10 — a real body either succeeds or
fails for a reason no test can place a byte boundary on.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A Dexpace::Body includer with a scriptable #write_to, and the only deterministic route to
# BODY-20's "the snapshot returns the bytes mirrored up to the failure": a real body either
# succeeds or fails for a reason the test cannot place a byte boundary on.
#
# `chunks` are yielded to the sink in order; `fail_after` is the number of chunks to write before
# raising `error`. It records the sink it was handed, which is how BODY-17's "consuming the
# upstream exactly once" is asserted.
class FakeBody
  include Dexpace::Body

  attr_reader :media_type, :content_length, :writes, :sinks

  OPTIONS = %i[media_type content_length replayable fail_after].freeze

  # **options rather than four keywords beside the splat, because Metrics/ParameterLists caps a
  # signature at four and a test double is not where that budget is spent. The unknown-key check
  # is what keeps a mistyped option a loud failure rather than a silently ignored one.
  def initialize(*chunks, **options)
    unknown = options.keys - OPTIONS
    raise ::ArgumentError, "unknown option(s): #{unknown.join(", ")}" unless unknown.empty?

    @chunks = chunks
    @media_type = options[:media_type]
    @content_length = options.fetch(:content_length, -1)
    @replayable = options.fetch(:replayable, false)
    @fail_after = options[:fail_after]
    @error = Dexpace::StreamError.new("scripted failure")
    @writes = 0
    @sinks = []
  end

  def replayable? = @replayable

  def write_to(sink)
    @writes += 1
    @sinks << sink
    written = 0
    @chunks.each_with_index do |chunk, index|
      raise @error if !@fail_after.nil? && index >= @fail_after

      written += sink.write(chunk.b)
    end
    written
  end
end
```

- [ ] **Step 2: Write the failing tests**

`gems/dexpace-core/test/dexpace/http/body_test.rb`. Tasks 2, 5 and 9 append their own sections to
this same file.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_body"
require_relative "../../support/fake_sink"
require_relative "../../support/fake_source"
require "stringio"

# HTTP-36, HTTP-38, HTTP-39, HTTP-52, BODY-1, BODY-10, BODY-13, BODY-25, BODY-30, BODY-32, BODY-35,
# and §10.2's #each.
class DexpaceBodyTest < DexpaceTestCase
  def bare
    Class.new { include Dexpace::Body }.new
  end

  def buffer_of(*strings)
    buffer = Dexpace::IO::Buffer.new
    strings.each { |string| buffer.write(string.b) }
    buffer
  end

  # ---- the defaults the contract carries (HTTP-36, BODY-1, BODY-35) ------------------------

  test "defaults replayable? to false, because BODY-1 makes replay a property a body earns" do
    refute_predicate(bare, :replayable?)
  end

  test "defaults content_length to the -1 sentinel and never to nil" do
    assert_equal(-1, bare.content_length)
  end

  test "defaults media_type to nil, which HTTP-36 makes nullable" do
    assert_nil(bare.media_type)
  end

  test "raises NotImplementedError when the includer never defined the one hook" do
    error = assert_raises(::NotImplementedError) { bare.write_to(Dexpace::IO::Buffer.new) }

    assert_includes(error.message, "#write_to(sink)")
  end

  # ---- #each derived from #write_to, once (§10.2, P3-21) ----------------------------------

  test "each yields exactly the chunks the single write produced" do
    body = FakeBody.new("hé", "llo")
    yielded = []

    body.each { |chunk| yielded << chunk }

    assert_equal(["hé".b, "llo".b], yielded)
  end

  test "each yields BINARY chunks even when the delegate wrote UTF-8 ones" do
    yielded = []

    FakeBody.new("héllo").each { |chunk| yielded << chunk.encoding }

    assert_equal([::Encoding::BINARY], yielded)
  end

  test "each with no block returns an Enumerator over the same bytes" do
    assert_equal(["hé".b, "llo".b], FakeBody.new("hé", "llo").each.to_a)
  end

  test "each and write_to produce identical bytes, which is what BODY-17 leans on" do
    sink = Dexpace::IO::Buffer.new
    FakeBody.new("hé", "llo").write_to(sink)
    yielded = +"".b
    FakeBody.new("hé", "llo").each { |chunk| yielded << chunk }

    assert_equal(sink.snapshot, yielded)
  end

  # ---- to_replayable (BODY-3/HTTP-37) ------------------------------------------------------

  test "to_replayable returns the same body unchanged when it is already replayable" do
    body = FakeBody.new("a", replayable: true)

    assert_same(body, body.to_replayable)
  end

  # ---- copy_exactly (HTTP-39/BODY-10, BODY-13, BODY-25) ------------------------------------

  test "copy_exactly writes precisely the declared count" do
    source = Dexpace::IO::BufferedSource.of_bytes("0123456789")
    sink = Dexpace::IO::Buffer.new

    assert_equal(4, bare.send(:copy_exactly, source, sink, 4))
    assert_equal("0123", sink.snapshot)
  end

  test "copy_exactly treats a declared length of zero as a legitimate empty write" do
    sink = FakeSink.new

    assert_equal(0, bare.send(:copy_exactly, FakeSource.new, sink, 0))
    assert_empty(sink.writes)
  end

  test "copy_exactly raises naming delivered-of-total when the source ends early" do
    source = Dexpace::IO::BufferedSource.of_bytes("012")
    error = assert_raises(Dexpace::StreamError) do
      bare.send(:copy_exactly, source, Dexpace::IO::Buffer.new, 10)
    end

    assert_includes(error.message, "3")
    assert_includes(error.message, "10")
  end

  test "copy_exactly treats a zero read for a positive count as a contract violation" do
    error = assert_raises(Dexpace::StreamError) do
      bare.send(:copy_exactly, FakeSource.new(0), Dexpace::IO::Buffer.new, 4)
    end

    assert_includes(error.message, "IO-17")
  end

  test "copy_exactly does not spin when the source keeps returning zero" do
    source = FakeSource.new(0, 0, 0)
    assert_raises(Dexpace::StreamError) do
      bare.send(:copy_exactly, source, Dexpace::IO::Buffer.new, 4)
    end

    assert_equal(1, source.calls.length)
  end

  test "copy_exactly detects a short write from the sink and names transferred-of-total" do
    source = Dexpace::IO::BufferedSource.of_bytes("0123456789")
    error = assert_raises(Dexpace::StreamError) do
      bare.send(:copy_exactly, source, FakeSink.new(2), 4)
    end

    assert_includes(error.message, "2")
    assert_includes(error.message, "4")
  end

  test "bytes and string both build a replayable BytesBody, which HTTP-38 classifies alike" do
    assert_instance_of(Dexpace::BytesBody, Dexpace::Body.bytes("a"))
    assert_instance_of(Dexpace::BytesBody, Dexpace::Body.string("a"))
  end

  test "string encodes eagerly, so a later mutation of the caller's String cannot reach the body" do
    text = +"héllo"
    body = Dexpace::Body.string(text)
    text << " more"

    assert_equal(6, body.content_length)
  end

  test "string rejects a non-String rather than calling to_s on it" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.string(42) }

    assert_includes(error.message, "Integer")
  end

end
```

`gems/dexpace-core/test/dexpace/http/body/bytes_body_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/fake_sink"

# HTTP-36, HTTP-38, HTTP-46, BODY-1, BODY-13, BODY-35.
class DexpaceBytesBodyTest < DexpaceTestCase
  test "is replayable, because HTTP-38 classifies a byte array and a string alike" do
    assert_predicate(Dexpace::BytesBody.new("a"), :replayable?)
  end

  test "reports the exact byte count, not the character count" do
    assert_equal(6, Dexpace::BytesBody.new("héllo").content_length)
  end

  test "writes the same bytes on every write" do
    body = Dexpace::BytesBody.new("héllo")
    first = Dexpace::IO::Buffer.new
    second = Dexpace::IO::Buffer.new

    body.write_to(first)
    body.write_to(second)

    assert_equal("héllo".b, first.snapshot)
    assert_equal(first.snapshot, second.snapshot)
  end

  test "keeps an independent copy, so a later mutation of the caller's String cannot reach it" do
    text = +"héllo"
    body = Dexpace::BytesBody.new(text)
    text << "!"

    assert_equal(6, body.content_length)
  end

  test "stores its bytes as BINARY whatever encoding the caller handed in" do
    sink = Dexpace::IO::Buffer.new
    Dexpace::BytesBody.new("héllo").write_to(sink)

    assert_equal(::Encoding::BINARY, sink.snapshot.encoding)
  end

  test "writes nothing and returns 0 for an empty body" do
    sink = FakeSink.new

    assert_equal(0, Dexpace::BytesBody.new("").write_to(sink))
    assert_empty(sink.writes)
  end

  test "detects a short write from the sink and names transferred-of-total" do
    error = assert_raises(Dexpace::StreamError) do
      Dexpace::BytesBody.new("héllo").write_to(FakeSink.new(2))
    end

    assert_includes(error.message, "2")
    assert_includes(error.message, "6")
  end

  test "rejects a non-String rather than coercing it" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::BytesBody.new(42) }

    assert_includes(error.message, "Integer")
  end

  # HTTP-46, and all three together: phase 1's Request#hash folds the body in, so a body with a
  # value #== and an identity #hash breaks the hash/eql? contract for every Request used as a key.
  test "compares by value over its bytes and its media type" do
    media = Dexpace::MediaType.parse("text/plain")

    assert_equal(Dexpace::BytesBody.new("a"), Dexpace::BytesBody.new("a"))
    refute_equal(Dexpace::BytesBody.new("a"), Dexpace::BytesBody.new("b"))
    refute_equal(Dexpace::BytesBody.new("a"), Dexpace::BytesBody.new("a", media_type: media))
  end

  test "hashes equal bodies equally, so a Request carrying one works as a Hash key" do
    assert_equal(Dexpace::BytesBody.new("a").hash, Dexpace::BytesBody.new("a").hash)
    assert(Dexpace::BytesBody.new("a").eql?(Dexpace::BytesBody.new("a")))
  end

  test "is frozen, so nothing can mutate it after construction" do
    assert_predicate(Dexpace::BytesBody.new("a"), :frozen?)
  end
end
```

- [ ] **Step 3: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/body_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Body`, raised out of `fake_body.rb`'s
`include Dexpace::Body`. Then the same for `bytes_body_test.rb`.

- [ ] **Step 4: Write `lib/dexpace/http/body.rb`**

Read the ordering inside `#each` before writing it: the block-shaped sink is a private constant so
no name enters the `NFR-4` surface, and `#each` is defined *once here* rather than per variant.
`copy_exactly` reads through `#read_into` and not through 3a's `TypedWrites#write_all(source)`,
which is P3-20: `#write_all` is a method on a **sink**, so using it would mean wrapping the
transport's `#write`-shaped destination in a `BufferedSink` — which `IO-6` then obliges to close
the socket, exactly what a body must never do.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../io"
require_relative "../io/buffer"
require_relative "../error/stream_error"
require_relative "../error/invalid_argument_error"

module Dexpace
  # The request/response body contract, the factory home, and the two copy routines every variant
  # shares (HTTP-36, HTTP-38, BODY-1, BODY-35).
  #
  # A module and not a base class: MultipartBody and ResponseLoggingBody each compose with
  # something else (Closeable, and later a codec's own mixin), and Ruby has single inheritance. A
  # module and not an RBS interface: an interface can be the type sig/ narrows Request#body and
  # Response#body to (DEF-26), but it cannot carry the default #replayable?, #content_length and
  # #each implementations, and restating those in eleven classes is the drift this exists to stop.
  #
  # Public, not private_constant, for TypedReads' reason (P3-8): the runtime surface snapshot walks
  # each class's public_instance_methods(false), which does not see a method reaching a class
  # through an included module, so a private module would hide most of phase 3b from the gate that
  # exists to see it.
  #
  # One hook: #write_to(sink) -> Integer. Everything else derives from it.
  #
  # BODY-4's three declines are NOT unified here. This module ships one #replayable? property; the
  # retry path stops and surfaces the last outcome, the auth path returns the original challenge
  # response unchanged and does NOT close it, and the redirect path raises. All three are phase 6's,
  # in three places, because BODY-4 says a port need not unify them.
  module Body
    # #each's destination: a sink shaped object that hands each write to a block. Private, so no
    # constant enters the NFR-4 surface.
    class BlockSink
      def initialize(&block)
        @block = block
      end

      def write(*strings)
        payload = strings.length == 1 ? strings.first : strings.join.b
        @block.call(payload)
        payload.bytesize
      end
    end

    # HTTP-51's declared-length half: the same framing routine run against this counts bytes
    # instead of writing them, so a declared length cannot drift from the bytes written.
    class CountingSink
      attr_reader :bytesize

      def initialize
        @bytesize = 0
      end

      def write(*strings)
        added = strings.sum(&:bytesize)
        @bytesize += added
        added
      end
    end

    private_constant :BlockSink, :CountingSink

    # ---- the contract ----------------------------------------------------------------------

    # HTTP-36's single write-to-sink operation, and the only byte-producing primitive a body has.
    # `sink` is anything responding to #write (Dexpace::IO::_Sink): a TeeSink, a BufferedSink, a
    # Buffer, a raw ::IO, the transport's own sink. Returns the byte count written.
    def write_to(_sink)
      raise ::NotImplementedError,
            "#{self.class} includes Dexpace::Body and must define #write_to(sink)"
    end

    # HTTP-36: nullable.
    def media_type
      nil
    end

    # HTTP-36/BODY-35: the exact count when known, and the -1 sentinel when not. Never nil --
    # BODY-35 fixes the sentinel in normative text and an ID-bearing rule beats the styleguide's
    # nil-as-absence default.
    def content_length
      -1
    end

    # BODY-1: false by default. True only where writing more than once yields byte-for-byte
    # identical output, which is a property a variant earns rather than one a caller may assert.
    def replayable?
      false
    end

    # The READ side of the contract, and the counterpart to #write_to (OI-10, P3-23).
    # Response#close, #body_string and #body_bytes are written against #source and #close, so a
    # body that can occupy Response#body and answers neither is a NoMethodError one layer up --
    # which is exactly what BODY-30/HTTP-52's BufferBody was.
    #
    # The default RAISES rather than being absent, and that is what makes the sig/ declaration true
    # of every Dexpace::Body: DEF-26 narrows Response#body to Dexpace::Body?, and
    # Response#body_string reads through this, so a declared-but-undefined member would make the
    # signature a lie. The
    # three bodies that can occupy Response#body -- ResponseBody, ResponseLoggingBody and
    # BufferBody -- override it with the handle they already hold; the seven request-body variants
    # raise from here, which is a named failure and not a NoMethodError.
    def source
      raise Dexpace::StreamError,
            "#{self.class} is a request body and exposes no readable source; #write_to is its " \
            "one byte-producing operation (HTTP-36)"
    end

    # HTTP-43 forwards a response's close to its body, and a body that owns no transport resource
    # has nothing to release. BODY-30 requires exactly that of the buffered error copy: the
    # ensure-close inside Response#body_string must leave a BufferBody "readable independently and
    # repeatably". Dexpace::ResponseBody and Dexpace::ResponseLoggingBody include
    # Dexpace::Closeable AFTER this module, so their latch wins where a close does release
    # something.
    def close
      nil
    end

    # BODY-3/HTTP-37: self when already replayable, otherwise drain once into memory and hand back
    # a replayable buffer-backed body, leaving the original consumed.
    def to_replayable
      return self if replayable?

      buffer = Dexpace::IO::Buffer.new
      write_to(buffer)
      Dexpace::BufferBody.new(buffer, media_type: media_type)
    end

    # Design §10.2: every body is also a canonical body representation, so a transport can iterate
    # it. Derived from #write_to once, here, so BODY-17's "the exact bytes the wrapped body's single
    # write produces" cannot mean two different things on the two paths (P3-21).
    #
    # §7.1's residue, widened by `docs/knowledge/notes/pagination.md`: an ordinary #each method
    # leaks exactly like an Enumerator.new block. A consumer that drives to_enum(:each) with #next
    # and abandons it does not run this method's ensures -- #rewind does not run them either, and
    # block_given? is true under that drive so no in-method guard helps. Bodies that hold a resource
    # therefore hold it on the object and expose #close; FileBody, which BODY-11 obliges to open a
    # fresh handle per write, cannot, and states the residue in its own YARD.
    def each
      return to_enum(:each) unless block_given?

      write_to(BlockSink.new { |chunk| yield chunk })
      nil
    end

    # ---- the factories (HTTP-38/BODY-35, one place) ----------------------------------------

    # Replayable: an independent frozen BINARY copy.
    def self.bytes(bytes, media_type: nil)
      Dexpace::BytesBody.new(bytes, media_type: media_type)
    end

    # Replayable. The String is encoded EAGERLY, at construction, so #content_length is exact and a
    # later mutation of the caller's String cannot change the body -- 3a's .of_bytes independent
    # copy property, applied to text.
    def self.string(text, media_type: nil, encoding: ::Encoding::UTF_8)
      unless text.is_a?(::String)
        raise Dexpace::InvalidArgumentError, "string takes a String, got #{text.class}"
      end

      Dexpace::BytesBody.new(text.encode(encoding).b, media_type: media_type)
    end

    def self.file(path, media_type: nil, offset: 0, count: nil)
      Dexpace::FileBody.new(path, media_type: media_type, offset: offset, count: count)
    end

    def self.stream(io, media_type: nil, content_length: -1, close: false)
      Dexpace::StreamBody.new(io, media_type: media_type, content_length: content_length,
                              close: close,)
    end

    def self.chunked(chunked, media_type: nil, content_length: -1)
      Dexpace::ChunkedBody.new(chunked, media_type: media_type, content_length: content_length)
    end

    def self.form(pairs)
      Dexpace::FormBody.new(pairs)
    end

    def self.multipart(parts, boundary: nil, subtype: "form-data")
      Dexpace::MultipartBody.new(parts, boundary: boundary, subtype: subtype)
    end

    def self.buffer(buffer, media_type: nil)
      Dexpace::BufferBody.new(buffer, media_type: media_type)
    end

    # ---- BODY-32's cap rules, shared by every capped operation --------------------------

    # BODY-32: reject a negative cap, silently clamp down to the ceiling, never up. Float::INFINITY
    # is accepted and clamps to the ceiling; [Float::INFINITY, Integer].min is an Integer.
    def self.clamp_cap(cap)
      if cap.equal?(::Float::INFINITY)
        return Dexpace::IO::MAX_MATERIALIZED_BYTES
      end
      unless cap.is_a?(::Integer)
        raise Dexpace::InvalidArgumentError,
              "cap must be an Integer or Float::INFINITY, got #{cap.class}"
      end
      if cap.negative?
        raise Dexpace::InvalidArgumentError, "cap must not be negative, got #{cap}"
      end

      [cap, Dexpace::IO::MAX_MATERIALIZED_BYTES].min
    end

    private_class_method :clamp_cap

    private

    # HTTP-51's counting half. Private, so the constant stays off the NFR-4 surface and the
    # runtime snapshot's constant walk never sees it.
    def counting_sink
      CountingSink.new
    end

    # HTTP-39/BODY-10, BODY-13 and BODY-25 in one routine: exactly `count` bytes from a
    # Dexpace::IO::_Source into `sink`, a premature end naming delivered-of-total, a zero-length
    # read for a positive request as a stream-contract violation rather than an EOF or a spin, and
    # a declared length of 0 as a legitimate empty write.
    #
    # It is this rather than 3a's TypedWrites#write_all(source) (P3-20): #write_all is a method on a
    # SINK, so using it would mean wrapping the transport's #write-shaped destination in a
    # BufferedSink -- which IO-6 then obliges to close the socket, exactly what a body must never do
    # (BODY-8, §10.12), and 3a ships no borrowing variant by design.
    #
    # The chunk size is whatever the source's own read returned: #read_into is asked for the
    # whole remaining count and delivers what it has, so BODY-17's byte-exact mirroring sees the
    # upstream's own boundaries rather than a size this layer invented.
    def copy_exactly(source, sink, count)
      transferred = 0
      while transferred < count
        wanted = count - transferred
        chunk = (+"").b
        taken = source.read_into(chunk, count: wanted)
        if taken.negative?
          raise Dexpace::StreamError.short_transfer(transferred: transferred, expected: count)
        end
        raise Dexpace::StreamError.zero_read(requested: wanted) if taken.zero?

        emit_exactly(sink, chunk)
        transferred += taken
      end
      transferred
    end

    # The other direction, and the second half of BODY-13's short-write detection: one String to a
    # #write-shaped sink, retagged to BINARY on the way (a body may yield a frozen non-BINARY chunk;
    # String#b is the retag because force_encoding raises FrozenError on a frozen String even when
    # the target encoding is already its own). Both routines raise through 3a's
    # StreamError.short_transfer, so BODY-13's one-message-form rule holds across the two.
    def emit_exactly(sink, string)
      payload = string.frozen? && string.encoding == ::Encoding::BINARY ? string : string.b
      return 0 if payload.empty?

      written = sink.write(payload)
      if written.is_a?(::Integer) && written < payload.bytesize
        raise Dexpace::StreamError.short_transfer(transferred: written, expected: payload.bytesize)
      end

      payload.bytesize
    end

    # BODY-6/BODY-7 and BODY-9's race-safe rewind use the same shape, and it is the only
    # synchronised state a request body has: a Thread::Mutex held across the flag flip and across
    # nothing else. Ruby's Mutex is non-reentrant and per-fiber-owned, so holding it across the
    # write deadlocks two fibers of one thread.
    def initialize_single_use
      @dexpace_body_mutex = ::Thread::Mutex.new
      @dexpace_consumed = false
      @dexpace_writing = false
      nil
    end

    # BODY-6: a second write raises rather than silently emitting zero bytes.
    # BODY-7: under concurrent writes exactly one passes and every loser sees the same failure.
    def claim_single_use!
      first = @dexpace_body_mutex.synchronize do
        next false if @dexpace_consumed

        @dexpace_consumed = true
      end
      return nil if first

      raise Dexpace::StreamError,
            "#{self.class} is single-use and its bytes have already been written (BODY-6)"
    end

    # BODY-9: "the rewind MUST be race-safe (at most one reset between any two writes)". A second
    # concurrent write observes the flag and raises rather than issuing a second seek underneath
    # the first write's read.
    def claim_replay!
      mine = @dexpace_body_mutex.synchronize do
        next false if @dexpace_writing

        @dexpace_writing = true
      end
      return nil if mine

      raise Dexpace::StreamError,
            "a write is already in progress on this #{self.class}; BODY-9 permits at most one " \
            "reset between any two writes"
    end

    def release_replay!
      @dexpace_body_mutex.synchronize { @dexpace_writing = false }
      nil
    end
  end
end
```

- [ ] **Step 5: Write `lib/dexpace/http/body/bytes_body.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"

module Dexpace
  # HTTP-38/BODY-35's replayable byte-array and string body, and the simplest thing that satisfies
  # HTTP-36. Flat, and in a subdirectory, per P1-1 and 3a's Dexpace::StreamError precedent: a
  # Dexpace::Body:: namespace would want the member names File, Buffer and Response, three constants
  # the body code uses constantly, and OI-3/P3-7 show that shadowing is silent for is_a? and
  # case/when.
  #
  # Body.string and Body.bytes both return one of these, because HTTP-38 classifies a string and a
  # byte array identically and two classes for one behaviour is one more than the requirement asks.
  class BytesBody
    include Dexpace::Body

    attr_reader :media_type

    # The copy is INDEPENDENT and frozen: a caller that mutates the String it handed in cannot
    # change the body's bytes or its declared length.
    def initialize(bytes, media_type: nil)
      unless bytes.is_a?(::String)
        raise Dexpace::InvalidArgumentError, "bytes must be a String, got #{bytes.class}"
      end

      @bytes = bytes.b.freeze
      @media_type = media_type
      freeze
    end

    def content_length
      @bytes.bytesize
    end

    def replayable?
      true
    end

    def write_to(sink)
      emit_exactly(sink, @bytes)
    end

    # HTTP-46: by value, over the facts that determine the bytes. All three together, never #==
    # alone -- phase 1's Request#hash folds the body in, and a body with a value #== and an identity
    # #hash breaks the hash/eql? contract for every Request used as a Hash key.
    def ==(other)
      other.is_a?(BytesBody) && other.content_length == content_length &&
        other.media_type == media_type && other.bytes == @bytes
    end
    alias eql? ==

    def hash
      [self.class, @bytes, @media_type].hash
    end

    protected

    attr_reader :bytes
  end
end
```

- [ ] **Step 6: Write the two `sig/` mirrors**

`sig/dexpace/http/body.rbs`. The `Dexpace::_ResponseHandler` interface at the top is Task 12's and
is written here because RBS wants one file per `lib/` file and this is where the module lives;
Task 12 adds no `sig/` file of its own beyond `typed_response.rbs`.

```rbs
module Dexpace
  interface _ResponseHandler
    def call: (Dexpace::Response) -> untyped
  end

  module Body
    MAX_BUFFERED_ERROR_BODY_BYTES: Integer

    def write_to: (Dexpace::IO::_Sink sink) -> Integer
    def source: () -> Dexpace::IO::_Source
    def close: () -> nil
    def media_type: () -> Dexpace::MediaType?
    def content_length: () -> Integer
    def replayable?: () -> bool
    def to_replayable: () -> Dexpace::Body
    def each: () { (String) -> void } -> nil
            | () -> Enumerator[String, nil]

    def self.bytes: (String, ?media_type: Dexpace::MediaType?) -> Dexpace::BytesBody
    def self.string: (String, ?media_type: Dexpace::MediaType?, ?encoding: Encoding)
                   -> Dexpace::BytesBody
    def self.file: (String, ?media_type: Dexpace::MediaType?, ?offset: Integer, ?count: Integer?)
                 -> Dexpace::FileBody
    def self.stream: (untyped, ?media_type: Dexpace::MediaType?, ?content_length: Integer,
                      ?close: bool) -> Dexpace::StreamBody
    def self.chunked: (Dexpace::IO::_Chunked, ?media_type: Dexpace::MediaType?,
                       ?content_length: Integer) -> Dexpace::ChunkedBody
    def self.form: (untyped) -> Dexpace::FormBody
    def self.multipart: (Array[Dexpace::MultipartBody::Part], ?boundary: String?, ?subtype: String)
                      -> Dexpace::MultipartBody
    def self.buffer: (Dexpace::IO::Buffer, ?media_type: Dexpace::MediaType?) -> Dexpace::BufferBody
    def self.buffer_bounded: (Dexpace::Body, ?cap: Integer | Float) -> Dexpace::BufferBody

    private

    def counting_sink: () -> untyped
    def copy_exactly: (Dexpace::IO::_Source source, Dexpace::IO::_Sink sink, Integer count)
                    -> Integer
    def emit_exactly: (Dexpace::IO::_Sink sink, String string) -> Integer
    def initialize_single_use: () -> nil
    def claim_single_use!: () -> nil
    def claim_replay!: () -> nil
    def release_replay!: () -> nil
  end
end
```

`sig/dexpace/http/body/bytes_body.rbs`:

```rbs
module Dexpace
  class BytesBody
    include Dexpace::Body

    attr_reader media_type: Dexpace::MediaType?

    def initialize: (String bytes, ?media_type: Dexpace::MediaType?) -> void
    def content_length: () -> Integer
    def replayable?: () -> bool
    def write_to: (Dexpace::IO::_Sink sink) -> Integer
    def ==: (untyped) -> bool
    def eql?: (untyped) -> bool
    def hash: () -> Integer

    private

    attr_reader bytes: String
  end
end
```

- [ ] **Step 7: Add the two `require_relative`s to `lib/dexpace.rb`**

Immediately after phase 1's `http/response` line, in the order `http/body`,
`http/body/bytes_body`.

- [ ] **Step 8: Run the tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/body_test.rb` and the same for
`bytes_body_test.rb`.
Expected: PASS — **18 tests** and **11 tests**. Then `bundle exec rake rbs:validate steep`.

---

## Task 2: `Dexpace::BufferBody` — materialize-once's product

**Requirement IDs:** `BODY-3`/`HTTP-37`'s materialize-once product, `BODY-30`/`HTTP-52`'s
replayable error copy, `HTTP-46`, and `IO-42`'s in-memory exemption as it reaches a body.
**Design:** "The seven request-body variants", `BufferBody` row; R10's first surface.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/body/buffer_body.rb` and
  `gems/dexpace-core/sig/dexpace/http/body/buffer_body.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`,
  `gems/dexpace-core/test/dexpace/http/body_test.rb` (append one section)
- Test: `gems/dexpace-core/test/dexpace/http/body/buffer_body_test.rb`

**Interfaces:**
- Consumes: Task 1's `Dexpace::Body` and its private `copy_exactly`; 3a's `Dexpace::IO::Buffer`,
  its `#peek`, `#snapshot`, `#bytesize` and its `#reads_survive_close?` exemption.
- Produces: `Dexpace::BufferBody.new(buffer, media_type: nil)` with `#content_length`,
  `#replayable?`, `#write_to`, `#media_type` and the protected `#snapshot_bytes`. Task 1's
  `#to_replayable` and Task 9's `.buffer_bounded` both return one.

**Second, because `#to_replayable` returns one of these and so does the bounded error copy.** It
is what unlocks the materialize-once test for every single-use variant that follows.

- [ ] **Step 1: Write the failing tests**

`gems/dexpace-core/test/dexpace/http/body/buffer_body_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# BODY-3, BODY-30, HTTP-37, HTTP-46, HTTP-52.
class DexpaceBufferBodyTest < DexpaceTestCase
  def buffer_of(*strings)
    buffer = Dexpace::IO::Buffer.new
    strings.each { |string| buffer.write(string.b) }
    buffer
  end

  test "is replayable and reports the buffer's byte count" do
    body = Dexpace::BufferBody.new(buffer_of("héllo"))

    assert_predicate(body, :replayable?)
    assert_equal(6, body.content_length)
  end

  # BODY-30's "readable independently and repeatably" is what makes this the materialize-once and
  # the error-copy product at once: the write goes through a fresh non-consuming peek view.
  test "never consumes its buffer, so every write produces the same bytes" do
    buffer = buffer_of("héllo")
    body = Dexpace::BufferBody.new(buffer)
    three = Array.new(3) do
      sink = Dexpace::IO::Buffer.new
      body.write_to(sink)
      sink.snapshot
    end

    assert_equal(["héllo".b] * 3, three)
    assert_equal(6, buffer.bytesize)
  end

  test "closes each peek view it takes, so a repeatedly written body does not grow the registry" do
    buffer = buffer_of("héllo")
    body = Dexpace::BufferBody.new(buffer)
    20.times { body.write_to(Dexpace::IO::Buffer.new) }

    assert_equal(0, buffer.instance_variable_get(:@dexpace_views).length)
  end

  test "closes its view even when the sink raises partway" do
    buffer = buffer_of("héllo")
    body = Dexpace::BufferBody.new(buffer)
    exploding = Class.new { def write(_string) = raise(Dexpace::StreamError, "boom") }.new

    assert_raises(Dexpace::StreamError) { body.write_to(exploding) }
    assert_equal(0, buffer.instance_variable_get(:@dexpace_views).length)
  end

  test "keeps reading after the buffer is closed, which is IO-42's in-memory exemption" do
    buffer = buffer_of("héllo")
    body = Dexpace::BufferBody.new(buffer)
    buffer.close
    sink = Dexpace::IO::Buffer.new
    body.write_to(sink)

    assert_equal("héllo".b, sink.snapshot)
  end

  test "rejects anything that is not a Dexpace::IO::Buffer" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::BufferBody.new("bytes") }

    assert_includes(error.message, "String")
  end

  test "compares by value over its snapshot and its media type" do
    assert_equal(Dexpace::BufferBody.new(buffer_of("a")), Dexpace::BufferBody.new(buffer_of("a")))
    refute_equal(Dexpace::BufferBody.new(buffer_of("a")), Dexpace::BufferBody.new(buffer_of("b")))
  end

  test "hashes over the length and media type, which equal bodies always share" do
    assert_equal(Dexpace::BufferBody.new(buffer_of("a")).hash,
                 Dexpace::BufferBody.new(buffer_of("a")).hash,)
  end
end
```

Append to `gems/dexpace-core/test/dexpace/http/body_test.rb`, immediately before the file's final
`end` — these two name `Dexpace::BufferBody` and could not be written in Task 1:

```ruby
  # ---- to_replayable's product (BODY-3/HTTP-37) --------------------------------------------

  test "to_replayable drains a single-use body once into a replayable BufferBody" do
    body = FakeBody.new("hé", "llo")

    materialized = body.to_replayable

    assert_instance_of(Dexpace::BufferBody, materialized)
    assert_predicate(materialized, :replayable?)
    assert_equal(1, body.writes)
  end

  test "to_replayable carries the media type across" do
    media = Dexpace::MediaType.parse("text/plain")

    assert_equal(media, FakeBody.new("a", media_type: media).to_replayable.media_type)
  end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/body/buffer_body_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::BufferBody`. `body_test.rb` fails the same way
on its two new tests and still passes its other 18.

- [ ] **Step 3: Write `lib/dexpace/http/body/buffer_body.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"

module Dexpace
  # The product of BODY-3/HTTP-37's materialize-once and of BODY-30/HTTP-52's bounded error copy: a
  # replayable body over a Dexpace::IO::Buffer that core owns.
  #
  # It NEVER consumes its buffer. #write_to writes through a fresh non-consuming #peek view closed
  # in an ensure, which is what makes BODY-30's "readable independently and repeatably" true rather
  # than true once, and what lets BODY-28's captured buffer keep answering after a close.
  class BufferBody
    include Dexpace::Body

    attr_reader :media_type

    def initialize(buffer, media_type: nil)
      unless buffer.is_a?(Dexpace::IO::Buffer)
        raise Dexpace::InvalidArgumentError,
              "buffer must be a Dexpace::IO::Buffer, got #{buffer.class}"
      end

      @buffer = buffer
      @media_type = media_type
      freeze
    end

    def content_length
      @buffer.bytesize
    end

    # A FRESH non-consuming view per call, which is the difference between this and BODY-14's
    # same-handle rule: BODY-14 governs the single-use response body, and BODY-30 requires this
    # copy to be "readable independently and repeatably". Response#body_string reads through here.
    # #close is Dexpace::Body's documented no-op -- there is no transport resource behind a buffer
    # core owns, and body_string's ensure-close must leave the copy readable (OI-10).
    def source
      @buffer.peek
    end

    def replayable?
      true
    end

    # Every view core takes, core closes: the view is closed in an ensure, which deregisters it
    # from the parent buffer so a repeatedly written body does not grow the parent's registry
    # (OI-4).
    def write_to(sink)
      view = @buffer.peek
      begin
        copy_exactly(view, sink, @buffer.bytesize)
      ensure
        view.close
      end
    end

    # HTTP-46. Bytes beyond Dexpace::IO::MAX_MATERIALIZED_BYTES are compared by identity rather than
    # by value, because #snapshot refuses to materialise them (IO-9) and an equality check must not
    # be the thing that raises. #hash is over the length and media type only, which is consistent:
    # equal bodies always hash equally.
    def ==(other)
      return true if equal?(other)
      return false unless other.is_a?(BufferBody)
      return false unless media_type == other.media_type && content_length == other.content_length
      return false if content_length > Dexpace::IO::MAX_MATERIALIZED_BYTES

      @buffer.snapshot == other.snapshot_bytes
    end
    alias eql? ==

    def hash
      [self.class, @media_type, content_length].hash
    end

    protected

    def snapshot_bytes
      @buffer.snapshot
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/http/body/buffer_body.rbs`**

```rbs
module Dexpace
  class BufferBody
    include Dexpace::Body

    attr_reader media_type: Dexpace::MediaType?

    def initialize: (Dexpace::IO::Buffer buffer, ?media_type: Dexpace::MediaType?) -> void
    def content_length: () -> Integer
    def source: () -> Dexpace::IO::BufferedSource
    def replayable?: () -> bool
    def write_to: (Dexpace::IO::_Sink sink) -> Integer
    def ==: (untyped) -> bool
    def eql?: (untyped) -> bool
    def hash: () -> Integer

    private

    def snapshot_bytes: () -> String
  end
end
```

- [ ] **Step 5: Add `require_relative "dexpace/http/body/buffer_body"` to `lib/dexpace.rb`**

- [ ] **Step 6: Run the tests to confirm they pass**

Expected: PASS — **8 tests** in `buffer_body_test.rb`, **20** in `body_test.rb`.

---

## Task 3: `PercentEncoding.encode_form` and `.encode_form_component`

**Requirement IDs:** `HTTP-38`/`BODY-35`'s "a form-urlencoded body MUST use
x-www-form-urlencoded encoding ('+' for space) distinct from RFC 3986 query encoding"; deviation
**P3-14**. **Design:** R6's third bullet under "Plus, and each named on purpose".

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/http/percent_encoding.rb`,
  `gems/dexpace-core/sig/dexpace/http/percent_encoding.rbs`
- Test: `gems/dexpace-core/test/dexpace/http/percent_encoding_test.rb` (append one section)

**Interfaces:**
- Consumes: phase 1's `Dexpace::PercentEncoding::ENCODED` byte table.
- Produces: `.encode_form(pairs) -> String` and `.encode_form_component(text) -> String`, over a
  `private_constant` `FORM_UNRESERVED` byte table. Task 5's `FormBody` is the only caller in core.

**Independent of every other task, and scheduled before Task 5 because `FormBody` needs it.** It
goes **beside** the RFC 3986 encoder in the same file, two functions and not two modules, because
`url-and-query-encoding/9ff11c34` asks for "two distinct functions with distinct tests that are
never interchanged" and the strongest guard against the mix-up is the two of them in one file with
the comment that says so between them. Phase 1 handed this deliverable here by name.

- [ ] **Step 1: Write the failing tests**

Appended to `gems/dexpace-core/test/dexpace/http/percent_encoding_test.rb`. Quoted here as a whole
file so the addition can be run on its own:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# HTTP-38/BODY-35's form encoder. These are appended to phase 1's own percent_encoding_test.rb;
# they are separated here only so the addition can be read on its own.
#
# `url-and-query-encoding`'s rule asks for two distinct functions with DISTINCT TESTS that are never
# interchanged. The distinctness is asserted mechanically below rather than described.
class DexpacePercentEncodingFormTest < DexpaceTestCase
  def form(text) = Dexpace::PercentEncoding.encode_form_component(text)
  def component(text) = Dexpace::PercentEncoding.encode_component(text)

  test "encodes a space as + where the RFC 3986 encoder writes %20" do
    assert_equal("+", form(" "))
    assert_equal("%20", component(" "))
  end

  test "encodes a literal + as %2B in BOTH, so a + in form output is always a space" do
    assert_equal("%2B", form("+"))
    assert_equal("%2B", component("+"))
  end

  test "passes * through where the RFC 3986 encoder escapes it" do
    assert_equal("*", form("*"))
    assert_equal("%2A", component("*"))
  end

  test "escapes ~ where the RFC 3986 encoder passes it through" do
    assert_equal("%7E", form("~"))
    assert_equal("~", component("~"))
  end

  test "passes ASCII alphanumerics and - . _ through unchanged" do
    assert_equal("aZ0-._", form("aZ0-._"))
  end

  test "reads bytes, so invalid UTF-8 encodes byte-exactly instead of raising" do
    assert_equal("%FF", form("\xFF".b))
  end

  test "encodes multi-byte characters one byte at a time" do
    assert_equal("%C3%A9", form("é"))
  end

  test "encode_form joins pairs with & and each name to its value with =" do
    assert_equal("a=1&b=2", Dexpace::PercentEncoding.encode_form([%w[a 1], %w[b 2]]))
  end

  test "encode_form encodes both halves of every pair" do
    assert_equal("a+b=c%2Fd", Dexpace::PercentEncoding.encode_form([["a b", "c/d"]]))
  end

  test "encode_form on no pairs is the empty String" do
    assert_equal("", Dexpace::PercentEncoding.encode_form([]))
  end

  # The mechanical version of "never interchanged": over random ASCII input the two functions agree
  # everywhere EXCEPT on the four characters they are defined to differ on, and they always differ
  # on a space.
  test "the two encoders differ only on space, ~ and *, and always differ on a space" do
    differing = (0..127).map(&:chr).reject { |c| form(c) == component(c) }

    assert_equal([" ", "*", "~"], differing.sort)
  end

  test "the two encoders never produce the same output for a String containing a space" do
    sample(count: 48, seed: 20_260_908) do |rng|
      text = Array.new(rng.rand(1..12)) { rng.rand(0x20..0x7E).chr }.join + " "

      refute_equal(form(text), component(text))
    end
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/percent_encoding_test.rb`
Expected: FAIL — `undefined method 'encode_form_component' for module Dexpace::PercentEncoding`.

- [ ] **Step 3: Add the two functions to `lib/dexpace/http/percent_encoding.rb`**

At the end of the module, after `.decode_component`, so the RFC 3986 pair and the form pair are
adjacent and the comment between them is unavoidable:

```ruby
    # ---- application/x-www-form-urlencoded (HTTP-38/BODY-35) -------------------------------

    # NOT RFC 3986, and never interchanged with the two functions above. `url-and-query-encoding`'s
    # rule asks for two distinct functions with distinct tests, not two modules: adjacency in one
    # file with this comment between them is the strongest guard against the mix-up there is.
    #
    # The passthrough set is the WHATWG urlencoded set -- ASCII alphanumeric plus "*", "-", "." and
    # "_" -- so the two functions differ on a space ("+" here, "%20" above), on "~" ("%7E" here,
    # "~" above) and on "*" ("*" here, "%2A" above). A literal "+" encodes to "%2B" in BOTH, which
    # is what makes a "+" in the output unambiguously a space and a "%2B" unambiguously a plus.
    FORM_UNRESERVED = ("A".."Z").to_a.concat(("a".."z").to_a, ("0".."9").to_a, %w[* - . _]).freeze
    private_constant :FORM_UNRESERVED

    def encode_form(pairs)
      pairs.map do |name, value|
        "#{encode_form_component(name)}=#{encode_form_component(value)}"
      end.join("&")
    end

    # Reads bytes, like encode_component, so a value carrying invalid UTF-8 encodes byte-exactly
    # rather than raising.
    def encode_form_component(text)
      text.b.each_byte.map { |byte| form_passthrough(byte) || ENCODED.fetch(byte) }.join
    end

    def form_passthrough(byte)
      return "+" if byte == 0x20

      character = byte.chr
      FORM_UNRESERVED.include?(character) ? character : nil
    end
    private_class_method :form_passthrough
```

- [ ] **Step 4: Add the two signatures to `sig/dexpace/http/percent_encoding.rbs`**

`FORM_UNRESERVED` is `private_constant` and therefore **not** in the signature and not in the
runtime surface manifest: it is the encoder's byte table, no caller outside this file reads it, and
every public constant is `NFR-4`-locked at the first release tag. `ENCODED`, phase 1's, stays
public because phase 1 made it so.

```rbs
module Dexpace
  module PercentEncoding
    def self.encode_form: (untyped pairs) -> String
    def self.encode_form_component: (String text) -> String
  end
end
```

- [ ] **Step 5: Run the tests to confirm they pass**

Expected: PASS — **12 tests**.

---

## Task 4: `Dexpace::StreamBody` — the rewind probe and the consume-once latch

**Requirement IDs:** `HTTP-38`/`BODY-35`'s one-shot source, `HTTP-37`, `BODY-6`, `BODY-7`,
`BODY-8`, `BODY-9`, `HTTP-39`/`BODY-10`; deviation **P3-16**.
**Design:** R9 in full; "The consume-once guard, once, for the two single-use variants";
"`BODY-8`, recorded rather than re-opened".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/body/stream_body.rb` and
  `gems/dexpace-core/sig/dexpace/http/body/stream_body.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/body/stream_body_test.rb`

**Interfaces:**
- Consumes: Task 1's `copy_exactly`, `emit_exactly`, `initialize_single_use`,
  `claim_single_use!`, `claim_replay!` and `release_replay!`; 3a's
  `Dexpace::IO::BufferedSource.wrapping` and `Dexpace::IO::MAX_MATERIALIZED_BYTES`.
- Produces: `Dexpace::StreamBody.new(io, media_type:, content_length:, close:)` with `#origin`,
  `#rewindable?`, `#owns_stream?`, `#replayable?` and `#write_to`. Task 5's `ChunkedBody` reuses
  the same latch through the module, not through this class.

**Third, because the consume-once latch and the rewind probe both live here**, and the latch is
then reused by `ChunkedBody` and `ResponseBody` through `Dexpace::Body`. Build it once, right.

`BODY-9` gets a Ruby subject and the SHOULD is implemented rather than declared vacuous.
`respond_to?(:rewind)` is `true` for a pipe, a socket, a `StringIO` and a `File` alike and
discriminates nothing; a trial `#rewind` discriminates and silently moves a caller's mid-file
cursor to byte 0. `origin = io.pos; io.seek(origin, ::IO::SEEK_SET)` does both jobs, and it
captures the position replay must return to at the same moment it proves it can.

- [ ] **Step 1: Write the failing test**

The negative case is a **real** `IO.pipe` raising a **real** `Errno::ESPIPE`, not a simulation —
that is what makes the probe test meaningful. The overlapping-write test parks the first write
inside the sink so the two writes genuinely overlap rather than merely being started together.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/fake_sink"
require "stringio"
require "tempfile"

# HTTP-37, HTTP-38, HTTP-39, BODY-1, BODY-6, BODY-7, BODY-8, BODY-9, BODY-10, BODY-35.
class DexpaceStreamBodyTest < DexpaceTestCase
  def drain(body)
    sink = Dexpace::IO::Buffer.new
    body.write_to(sink)
    sink.snapshot
  end

  # ---- BODY-9's antecedent, on real streams -------------------------------------------------

  # respond_to?(:rewind) is true for a pipe, a socket, a StringIO and a File alike, so the probe
  # cannot be that. A REAL IO.pipe raising a REAL Errno::ESPIPE is what makes this meaningful.
  test "a pipe is not rewindable, even though it answers respond_to?(:rewind)" do
    reader, writer = ::IO.pipe
    writer.write("héllo")
    writer.close
    body = Dexpace::Body.stream(reader, content_length: 6)

    assert(reader.respond_to?(:rewind))
    refute_predicate(body, :rewindable?)
    refute_predicate(body, :replayable?)
  ensure
    reader.close
  end

  test "a pipe stays fully readable after the probe, so the probe is non-destructive" do
    reader, writer = ::IO.pipe
    writer.write("héllo")
    writer.close
    body = Dexpace::Body.stream(reader, content_length: 6)

    assert_equal("héllo".b, drain(body))
  ensure
    reader.close
  end

  test "a StringIO is rewindable and a known short length makes it replayable" do
    body = Dexpace::Body.stream(StringIO.new(+"héllo"), content_length: 6)

    assert_predicate(body, :rewindable?)
    assert_predicate(body, :replayable?)
  end

  test "a File is rewindable and the probe leaves its cursor exactly where it was" do
    ::Tempfile.create("stream") do |file|
      file.write("0123456789")
      file.flush
      file.rewind
      file.read(4)
      body = Dexpace::Body.stream(file, content_length: 6)

      assert_equal(4, file.pos)
      assert_equal(4, body.origin)
    end
  end

  # THE finding the probe exists for: a body over a pre-positioned handle rewinds to where it
  # started, not to byte 0, so a replay cannot send bytes the caller never offered.
  test "replay rewinds to the construction position rather than to byte 0" do
    ::Tempfile.create("stream") do |file|
      file.write("0123456789")
      file.flush
      file.rewind
      file.read(4)
      body = Dexpace::Body.stream(file, content_length: 6)

      assert_equal("456789".b, drain(body))
      assert_equal("456789".b, drain(body))
    end
  end

  # ---- BODY-9's three conditions -----------------------------------------------------------

  test "an unknown length makes a rewindable stream single-use, per BODY-9's 'of known length'" do
    body = Dexpace::Body.stream(StringIO.new(+"héllo"))

    assert_predicate(body, :rewindable?)
    refute_predicate(body, :replayable?)
  end

  test "a length over MAX_MATERIALIZED_BYTES makes a rewindable stream single-use" do
    over = Dexpace::IO::MAX_MATERIALIZED_BYTES + 1
    body = Dexpace::Body.stream(StringIO.new(+"a"), content_length: over)

    refute_predicate(body, :replayable?)
  end

  # BODY-8's own sentence: "the rewindable variant must keep it open to replay". A body that closes
  # its stream as part of its one write cannot rewind it for a second.
  test "transferring close ownership forces single-use even on a rewindable stream" do
    body = Dexpace::Body.stream(StringIO.new(+"héllo"), content_length: 6, close: true)

    assert_predicate(body, :rewindable?)
    refute_predicate(body, :replayable?)
    assert_predicate(body, :owns_stream?)
  end

  # ---- BODY-8's ownership rule -------------------------------------------------------------

  test "closes nothing by default, because it opened nothing" do
    io = StringIO.new(+"héllo")
    drain(Dexpace::Body.stream(io, content_length: 6))

    refute_predicate(io, :closed?)
  end

  test "closes the stream as part of the single write when ownership was transferred" do
    io = StringIO.new(+"héllo")
    drain(Dexpace::Body.stream(io, content_length: 6, close: true))

    assert_predicate(io, :closed?)
  end

  test "closes an owned stream even when the write fails partway" do
    io = StringIO.new(+"héllo")
    body = Dexpace::Body.stream(io, content_length: 6, close: true)
    exploding = FakeSink.new(Dexpace::StreamError.new("the socket went away"))

    assert_raises(Dexpace::StreamError) { body.write_to(exploding) }
    assert_predicate(io, :closed?)
  end

  # ---- BODY-6 and BODY-7's consume-once guard ----------------------------------------------

  test "a second write on a single-use body raises rather than emitting zero bytes" do
    body = Dexpace::Body.stream(StringIO.new(+"héllo"))
    drain(body)
    error = assert_raises(Dexpace::StreamError) { drain(body) }

    assert_includes(error.message, "BODY-6")
  end

  # BODY-7 is a separate row from BODY-6 and a separate proof: not "a second write raises" but
  # "under concurrent writes at most one passes".
  test "under concurrent writes exactly one passes and every loser sees the consumed failure" do
    # An UNKNOWN length, so the body is single-use: a rewindable StringIO of known length would be
    # replayable and would take the other branch entirely.
    body = Dexpace::Body.stream(StringIO.new(+"0" * 512))
    start = ::Thread::Queue.new
    outcomes = ::Thread::Queue.new
    threads = Array.new(8) do
      ::Thread.new do
        start.pop
        outcomes << (drain(body) && :passed)
      rescue Dexpace::StreamError => error
        outcomes << error
      end
    end
    8.times { start << :go }
    threads.each(&:join)
    results = Array.new(8) { outcomes.pop }

    assert_equal(1, results.count(:passed))
    assert_equal(7, results.count { |r| r.is_a?(Dexpace::StreamError) })
  end

  # BODY-9's "at most one reset between any two writes", proved with the two writes made to
  # OVERLAP deterministically rather than raced and hoped for: the first write blocks inside the
  # sink until the second has been attempted, so a missing guard means two seeks and two readers
  # sharing one cursor -- which is exactly the corruption the clause exists to prevent.
  test "a write that overlaps another on a replayable body is refused, and seeks once" do
    io = CountingStringIO.new(+"0" * 512)
    body = Dexpace::Body.stream(io, content_length: 512)
    # The construction probe seeks once by design, so the count that matters is the delta.
    after_construction = io.seeks
    inside = ::Thread::Queue.new
    release = ::Thread::Queue.new
    first = ::Thread.new { body.write_to(BlockingSink.new(inside, release)) }
    inside.pop

    second = assert_raises(Dexpace::StreamError) { drain(body) }
    release << :go
    first.join

    assert_includes(second.message, "BODY-9")
    assert_equal(1, io.seeks - after_construction)
  end

  # §7.1's residue, and it is this class's own rather than FileBody's: BODY-9's rewind guard is
  # released in an `ensure`, and an abandoned enumerator never runs one, so the body stays claimed
  # for good. Stated as a fact rather than as a claim that it is prevented -- nothing in Ruby
  # closes it, and design §10.10's precedent is that an admitted hole beats a fake proof.
  test "abandoning a replayable body's enumerator leaves the rewind guard held for good" do
    body = Dexpace::Body.stream(StringIO.new(+"0123456789"), content_length: 10)
    enumerator = body.each
    enumerator.next

    error = assert_raises(Dexpace::StreamError) { drain(body) }

    assert_includes(error.message, "BODY-9")
  end

  test "draining that enumerator to exhaustion releases it, so only abandonment is affected" do
    body = Dexpace::Body.stream(StringIO.new(+"0123456789"), content_length: 10)
    body.each.to_a

    assert_equal("0123456789".b, drain(body))
  end

  # ---- HTTP-39/BODY-10's exact-length copy -------------------------------------------------

  test "a declared length shorter than the stream writes exactly that many bytes" do
    body = Dexpace::Body.stream(StringIO.new(+"0123456789"), content_length: 3)

    assert_equal("012".b, drain(body))
  end

  test "a declared length longer than the stream raises naming delivered-of-total" do
    body = Dexpace::Body.stream(StringIO.new(+"012"), content_length: 10)
    error = assert_raises(Dexpace::StreamError) { drain(body) }

    assert_includes(error.message, "3")
    assert_includes(error.message, "10")
  end

  test "a declared length of zero is a legitimate empty write" do
    sink = FakeSink.new

    assert_equal(0, Dexpace::Body.stream(StringIO.new(+"abc"), content_length: 0).write_to(sink))
    assert_empty(sink.writes)
  end

  test "an unknown length drains the stream to end of stream" do
    assert_equal("héllo".b, drain(Dexpace::Body.stream(StringIO.new(+"héllo"))))
  end

  # ---- construction and equality -----------------------------------------------------------

  test "rejects a stream that responds to neither readpartial nor read" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.stream(Object.new) }

    assert_includes(error.message, "#readpartial")
  end

  test "rejects a content_length below the -1 sentinel" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Body.stream(StringIO.new(+"a"), content_length: -2)
    end
  end

  test "leaves the body usable after a rejected construction argument" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Body.stream(StringIO.new(+"a"), content_length: -2)
    end

    assert_equal("a".b, drain(Dexpace::Body.stream(StringIO.new(+"a"))))
  end

  # HTTP-46: two different open streams are two different values, correctly.
  test "compares by identity, because two live streams are never interchangeable" do
    io = StringIO.new(+"a")
    first = Dexpace::Body.stream(io)
    second = Dexpace::Body.stream(io)

    assert_equal(first, first)
    refute_equal(first, second)
  end

  # A sink that parks inside its first write until it is released, which is what makes two writes
  # genuinely overlap instead of merely being started at about the same time.
  class BlockingSink
    def initialize(inside, release)
      @inside = inside
      @release = release
      @entered = false
    end

    def write(string)
      unless @entered
        @entered = true
        @inside << :inside
        @release.pop
      end
      string.bytesize
    end
  end

  # A StringIO that counts its seeks, which is the only way to assert BODY-9's "at most one reset".
  class CountingStringIO < StringIO
    attr_reader :seeks

    def initialize(*)
      super
      @seeks = 0
    end

    def seek(*)
      @seeks += 1
      super
    end
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/body/stream_body_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::StreamBody`.

- [ ] **Step 3: Write `lib/dexpace/http/body/stream_body.rb`**

Two things to read before writing it. The probe is guarded by `respond_to?(:pos)` **and**
`respond_to?(:seek)` before the `rescue ::SystemCallError`, because an object with `#read` and no
`#pos` would otherwise raise `NoMethodError` out of a probe whose whole job is to answer a
question. And `#pump` builds a **fresh** `BufferedSource.wrapping(@io)` per write and closes
nothing: that is `IO-6` used exactly as written and not the borrowing variant 3a declines to ship,
because the wrapper's close still closes the stream — this body simply does not call it unless
`close: true` transferred ownership.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"
require_relative "../../io/buffered_source"

module Dexpace
  # A body over a caller-supplied stream: HTTP-38/BODY-35's one-shot source, BODY-6..BODY-9.
  #
  # OWNERSHIP (BODY-8, design §10.12). A body closes exactly the sources it opened. This one opened
  # nothing, so it closes NOTHING unless the caller transferred ownership explicitly at the factory
  # with `close: true` -- at which point BODY-8's MUST applies and the single write drains and
  # closes, so skipping materialisation does not leak the stream.
  #
  # `close: true` also forces single-use, and that is BODY-8's own sentence rather than an extra
  # rule: "the rewindable variant must keep it open to replay". A body that closes its stream as
  # part of its one write cannot rewind it for a second.
  class StreamBody
    include Dexpace::Body

    attr_reader :media_type, :content_length

    def initialize(io, media_type: nil, content_length: -1, close: false)
      unless io.respond_to?(:readpartial) || io.respond_to?(:read)
        raise Dexpace::InvalidArgumentError,
              "a stream body's io must respond to #readpartial or #read, got #{io.class}"
      end
      unless content_length.is_a?(::Integer) && content_length >= -1
        raise Dexpace::InvalidArgumentError,
              "content_length must be an Integer of -1 or more, got #{content_length.inspect}"
      end

      @io = io
      @media_type = media_type
      @content_length = content_length
      @close = close ? true : false
      @origin, @rewindable = probe_rewindability(io)
      initialize_single_use
    end

    # BODY-9, all three conditions, plus BODY-8's ownership exclusion. The stream must be seekable
    # (probed once at construction), the length must be KNOWN -- BODY-9 says "of known length"
    # literally -- and it must fit the platform's maximum single-array bound, which design §10.18
    # substitutes as Dexpace::IO::MAX_MATERIALIZED_BYTES and IO-9 and BODY-32 share. Otherwise
    # single-use, which is BODY-9's own "otherwise it MUST be single-use".
    def replayable?
      @rewindable && !@close && @content_length != -1 &&
        @content_length <= Dexpace::IO::MAX_MATERIALIZED_BYTES
    end

    # The position the body starts at, captured by the same probe that proved it can return there.
    # Replay rewinds HERE and not to byte 0: a caller who hands over a File already positioned at
    # 4096 means the body starts at 4096, and a rewind to 0 would silently send bytes the caller
    # never offered.
    attr_reader :origin

    def rewindable?
      @rewindable
    end

    def owns_stream?
      @close
    end

    def write_to(sink)
      replayable? ? write_replayable(sink) : write_once(sink)
    end

    # HTTP-46: two different open streams are two different values, so equality is identity here --
    # correctly, because nothing about a live stream makes two of them interchangeable.
    def ==(other)
      equal?(other)
    end
    alias eql? ==

    def hash
      object_id.hash
    end

    private

    # BODY-9's "supports mark/reset", given a Ruby subject. respond_to?(:rewind) is true for a pipe,
    # a socket, a StringIO and a File alike, so it discriminates nothing; a trial #rewind
    # discriminates but silently moves a caller's mid-file cursor to 0. `pos` then `seek(pos)` does
    # both jobs: it raises Errno::ESPIPE on a pipe or a socket even at position 0 with nothing
    # consumed, and it is a genuine no-op on a seekable stream at any position. Errno::ESPIPE is a
    # SystemCallError and NOT an IOError, so a bare `rescue IOError` would not catch it.
    def probe_rewindability(io)
      return [0, false] unless io.respond_to?(:pos) && io.respond_to?(:seek)

      origin = io.pos
      io.seek(origin, ::IO::SEEK_SET)
      [origin, true]
    rescue ::SystemCallError
      [0, false]
    end

    def write_once(sink)
      claim_single_use!
      begin
        pump(sink)
      ensure
        @io.close if @close && @io.respond_to?(:close)
      end
    end

    # §7.1's residue, and it is this class's own rather than FileBody's (P3-28). release_replay!
    # runs in an `ensure`, and an ABANDONED enumerator never runs one: a consumer that drives
    # `stream_body.to_enum(:each)` with #next and drops it leaves @dexpace_writing set, and every
    # later write on this body raises BODY-9's "a write is already in progress" for good. Verified
    # on 3.2.11, 3.4.10 and 4.0.6, together with the two cases that are safe -- a full external
    # drive to StopIteration releases it, and #each with a break releases it. Nothing in Ruby
    # closes the abandonment case and this class does not pretend otherwise; a body that refuses
    # every later write is strictly safer than one that lets two readers share one cursor, which
    # is what BODY-9's clause exists to prevent. Design §10.10's precedent: an admitted hole beats
    # a fake proof.
    def write_replayable(sink)
      claim_replay!
      begin
        @io.seek(@origin, ::IO::SEEK_SET)
        pump(sink)
      ensure
        release_replay!
      end
    end

    # A FRESH Dexpace::IO::BufferedSource per write, for FileBody's reason: a source carried across
    # writes would replay bytes it had already buffered. It is never closed on the borrow path,
    # which is what leaves the caller's stream open -- and that is IO-6 used exactly as written
    # rather than the borrowing variant 3a declines to ship (P3-12): the wrapper's close still
    # closes the stream, this body just does not call it unless it owns the stream.
    def pump(sink)
      source = Dexpace::IO::BufferedSource.wrapping(@io)
      return copy_exactly(source, sink, @content_length) unless @content_length.negative?

      written = 0
      source.each { |chunk| written += emit_exactly(sink, chunk) }
      written
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/http/body/stream_body.rbs`**

```rbs
module Dexpace
  class StreamBody
    include Dexpace::Body

    attr_reader media_type: Dexpace::MediaType?
    attr_reader content_length: Integer
    attr_reader origin: Integer

    def initialize: (untyped io, ?media_type: Dexpace::MediaType?, ?content_length: Integer,
                     ?close: bool) -> void
    def replayable?: () -> bool
    def rewindable?: () -> bool
    def owns_stream?: () -> bool
    def write_to: (Dexpace::IO::_Sink sink) -> Integer
    def ==: (untyped) -> bool
    def eql?: (untyped) -> bool
    def hash: () -> Integer

    private

    def probe_rewindability: (untyped io) -> [ Integer, bool ]
    def write_once: (Dexpace::IO::_Sink sink) -> Integer
    def write_replayable: (Dexpace::IO::_Sink sink) -> Integer
    def pump: (Dexpace::IO::_Sink sink) -> Integer
  end
end
```

- [ ] **Step 5: Add `require_relative "dexpace/http/body/stream_body"` to `lib/dexpace.rb`**

- [ ] **Step 6: Run the test to confirm it passes**

Expected: PASS — **24 tests**.

---

## Task 5: `Dexpace::ChunkedBody` and `Dexpace::FormBody`

**Requirement IDs:** §10.2's canonical representation as a body, `BODY-6`, `BODY-7`, `BODY-8`,
`HTTP-38`/`BODY-35`'s form clause, `HTTP-46`; deviation **P3-19**.
**Design:** "`ChunkedBody` is single-use and takes no `replayable:` keyword"; the `FormBody` row.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/body/chunked_body.rb`,
  `gems/dexpace-core/lib/dexpace/http/body/form_body.rb`, and the two `sig/` mirrors
- Modify: `gems/dexpace-core/lib/dexpace.rb`,
  `gems/dexpace-core/test/dexpace/http/body_test.rb` (append one section)
- Test: `gems/dexpace-core/test/dexpace/http/body/chunked_body_test.rb`,
  `gems/dexpace-core/test/dexpace/http/body/form_body_test.rb`

**Interfaces:**
- Consumes: Task 1's `emit_exactly` and the shared latch; Task 3's
  `PercentEncoding.encode_form`; phase 1's `Dexpace::MediaType`; 3a's `Dexpace::IO::_Chunked`.
- Produces: `Dexpace::ChunkedBody.new(chunked, media_type:, content_length:)` and
  `Dexpace::FormBody.new(pairs)` with `FormBody::MEDIA_TYPE` and `#pairs`.

**Both are small, and they are one task because a reviewer would not reject one and approve the
other**: they are the two remaining always-classifiable factories, and together with Tasks 2 and 4
they complete `HTTP-38`'s table, which is why the factory-coverage test lands here.

`ChunkedBody` is **unconditionally single-use and takes no `replayable:` keyword** (P3-19).
`BODY-1` permits `#replayable?` to be `true` only when writing more than once *provably* yields
byte-for-byte identical output. An `#each`-shaped object may or may not, and a keyword would let a
caller **assert** the property — an assertion `BODY-4`'s three paths then believe. A caller with a
genuinely repeatable source uses `Body.bytes`, or calls `#to_replayable` and pays one
materialisation. "Add a keyword" is the obvious first request, which is why it is a ledger row
rather than a comment.

- [ ] **Step 1: Write the failing tests**

It reuses 3a's `FakeChunked`, required explicitly by the suite and never from the shared test
helper, because that double is the only thing that yields frozen non-BINARY literals **and** an
empty chunk between two non-empty ones — the one input no `StringIO` and no `IO.pipe` can produce.

`gems/dexpace-core/test/dexpace/http/body/chunked_body_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/fake_chunked"
require_relative "../../../support/fake_sink"

# HTTP-38, HTTP-46, BODY-1, BODY-4, BODY-6, BODY-7, BODY-8, BODY-35, and design §10.2.
class DexpaceChunkedBodyTest < DexpaceTestCase
  def drain(body)
    sink = Dexpace::IO::Buffer.new
    body.write_to(sink)
    sink.snapshot
  end

  test "writes exactly the chunks the wrapped object yields, in order" do
    assert_equal("héllo".b, drain(Dexpace::Body.chunked(FakeChunked.new("hé", "llo"))))
  end

  # FakeChunked yields FROZEN literals under its own file's frozen_string_literal pragma, which is
  # the ordinary Rack shape and the exact input on which force_encoding raises.
  test "retags a frozen non-BINARY chunk without raising FrozenError" do
    sink = Dexpace::IO::Buffer.new
    Dexpace::Body.chunked(FakeChunked.frozen_utf8).write_to(sink)

    assert_equal("héllo wörld".b, sink.snapshot)
    assert_equal(::Encoding::BINARY, sink.snapshot.encoding)
  end

  # The #each half of the same retag, and it needs a REAL body: FakeBody calls #b itself, so the
  # body_test.rb each-yields-BINARY test passes with Body#emit_exactly's retag removed. Here the
  # chunk reaching the block is whatever emit_exactly handed the sink.
  test "each yields BINARY chunks even when the wrapped object yields frozen UTF-8 ones" do
    encodings = []
    chunks = []

    Dexpace::Body.chunked(FakeChunked.frozen_utf8).each do |chunk|
      encodings << chunk.encoding
      chunks << chunk
    end

    assert_equal([::Encoding::BINARY], encodings.uniq)
    assert_equal("héllo wörld".b, chunks.join)
  end

  # An empty chunk between two non-empty ones means "no bytes this time", never "no bytes ever",
  # and no StringIO or IO.pipe can produce it.
  test "an empty chunk between two non-empty ones does not truncate the body" do
    assert_equal("abcd".b, drain(Dexpace::Body.chunked(FakeChunked.new("ab", "", "cd"))))
  end

  # P3-19, and it is a decision rather than an omission: BODY-1 permits replayable only when the
  # bytes are provably identical, and a keyword would let a caller ASSERT what BODY-4's three paths
  # then believe.
  test "is unconditionally single-use and Body.chunked takes no replayable keyword" do
    body = Dexpace::Body.chunked(["a"])

    refute_predicate(body, :replayable?)
    refute_includes(Dexpace::Body.method(:chunked).parameters.map(&:last), :replayable)
    refute_includes(Dexpace::ChunkedBody.instance_method(:initialize).parameters.map(&:last),
                    :replayable,)
  end

  test "a caller with a genuinely repeatable source pays one materialisation instead" do
    body = Dexpace::Body.chunked(["hé", "llo"])
    materialized = body.to_replayable

    assert_predicate(materialized, :replayable?)
    assert_equal("héllo".b, drain(materialized))
    assert_equal("héllo".b, drain(materialized))
  end

  test "a second write raises rather than emitting zero bytes" do
    body = Dexpace::Body.chunked(["a"])
    drain(body)
    error = assert_raises(Dexpace::StreamError) { drain(body) }

    assert_includes(error.message, "BODY-6")
  end

  test "under concurrent writes exactly one passes and every loser sees the same failure" do
    body = Dexpace::Body.chunked(Array.new(64) { "x" })
    start = ::Thread::Queue.new
    outcomes = ::Thread::Queue.new
    threads = Array.new(8) do
      ::Thread.new do
        start.pop
        drain(body)
        outcomes << :passed
      rescue Dexpace::StreamError => error
        outcomes << error.class
      end
    end
    8.times { start << :go }
    threads.each(&:join)
    results = Array.new(8) { outcomes.pop }

    assert_equal(1, results.count(:passed))
    assert_equal(7, results.count(Dexpace::StreamError))
  end

  # BODY-8: it opened nothing, so it closes nothing. An #each-shaped object holding a resource must
  # expose #close and be closed by its owner.
  test "closes nothing, and does not even look for a close method" do
    closeable = Class.new(FakeChunked) do
      attr_reader :closed

      def close = @closed = true
    end.new("a")
    drain(Dexpace::Body.chunked(closeable))

    assert_nil(closeable.closed)
  end

  test "declares an unknown length by default and carries a declared one through" do
    assert_equal(-1, Dexpace::Body.chunked(["a"]).content_length)
    assert_equal(9, Dexpace::Body.chunked(["a"], content_length: 9).content_length)
  end

  test "rejects an object that does not respond to each" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.chunked(Object.new) }

    assert_includes(error.message, "#each")
  end

  test "compares by identity, because two each-shaped objects are two values" do
    chunks = ["a"]

    refute_equal(Dexpace::Body.chunked(chunks), Dexpace::Body.chunked(chunks))
  end
end
```

`gems/dexpace-core/test/dexpace/http/body/form_body_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# HTTP-38, HTTP-46, BODY-1, BODY-35.
class DexpaceFormBodyTest < DexpaceTestCase
  def drain(body)
    sink = Dexpace::IO::Buffer.new
    body.write_to(sink)
    sink.snapshot
  end

  test "is always replayable, which HTTP-38 states outright" do
    assert_predicate(Dexpace::Body.form([%w[a b]]), :replayable?)
  end

  test "carries the x-www-form-urlencoded media type" do
    assert_equal("application/x-www-form-urlencoded",
                 Dexpace::Body.form([%w[a b]]).media_type.render,)
  end

  # The whole reason the form encoder is a different function with a different name: "+" for space,
  # never "%20". A body that used the RFC 3986 encoder would be wrong in a way no test of either
  # function alone would catch.
  test "encodes a space as + and never as %20" do
    assert_equal("a+b=c+d".b, drain(Dexpace::Body.form([["a b", "c d"]])))
  end

  test "encodes a literal + as %2B, so a + in the output is unambiguously a space" do
    assert_equal("a=%2B".b, drain(Dexpace::Body.form([["a", "+"]])))
  end

  test "joins pairs with & and separates each name from its value with =" do
    assert_equal("a=1&b=2".b, drain(Dexpace::Body.form([%w[a 1], %w[b 2]])))
  end

  test "accepts a Hash as well as an Array of pairs" do
    assert_equal("a=1&b=2".b, drain(Dexpace::Body.form({ "a" => "1", "b" => "2" })))
  end

  test "reports the exact encoded byte count, not the source character count" do
    assert_equal("a=%C3%A9".b.bytesize, Dexpace::Body.form([%w[a é]]).content_length)
  end

  test "writes the same bytes every time" do
    body = Dexpace::Body.form([["a b", "é"]])

    assert_equal(drain(body), drain(body))
  end

  # The bytes are encoded at construction, so a drain-only assertion passes even when the pairs
  # are aliased: #pairs is public and folds into #== and #hash, so the copy has to be asserted on
  # the accessor itself (HTTP-5, XCUT-15).
  test "takes an independent frozen copy of the pairs at construction" do
    pair = [+"a", +"1"]
    source = [pair]
    body = Dexpace::Body.form(source)
    source << %w[b 2]
    pair[1] << "9"

    assert_equal([%w[a 1]], body.pairs)
    assert_predicate(body.pairs, :frozen?)
    assert_equal("a=1".b, drain(body))
  end

  test "rejects something that cannot be mapped over" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.form(42) }

    assert_includes(error.message, "Integer")
  end

  test "compares by value over its pairs" do
    assert_equal(Dexpace::Body.form([%w[a 1]]), Dexpace::Body.form([%w[a 1]]))
    refute_equal(Dexpace::Body.form([%w[a 1]]), Dexpace::Body.form([%w[a 2]]))
    assert_equal(Dexpace::Body.form([%w[a 1]]).hash, Dexpace::Body.form([%w[a 1]]).hash)
  end
end
```

Append to `gems/dexpace-core/test/dexpace/http/body_test.rb`, immediately before the file's final
`end` — the last of the four constants it names lands in this task:

```ruby
  # ---- the factory table, complete (HTTP-38/BODY-35) ----------------------------------------

  test "the eight factories cover seven classes, with string and bytes sharing one" do
    buffer = buffer_of("a")

    assert_instance_of(Dexpace::BufferBody, Dexpace::Body.buffer(buffer))
    assert_instance_of(Dexpace::ChunkedBody, Dexpace::Body.chunked(["a"]))
    assert_instance_of(Dexpace::FormBody, Dexpace::Body.form([%w[a b]]))
    assert_instance_of(Dexpace::StreamBody, Dexpace::Body.stream(StringIO.new(+"a")))
  end
```

- [ ] **Step 2: Run them to confirm they fail**

Expected: FAIL — `uninitialized constant Dexpace::ChunkedBody`, then
`uninitialized constant Dexpace::FormBody`.

- [ ] **Step 3: Write `lib/dexpace/http/body/chunked_body.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"

module Dexpace
  # A body over design §10.2's canonical representation: any object responding to #each and yielding
  # String chunks -- a Rack body, an Enumerator, an Array of literals.
  #
  # UNCONDITIONALLY SINGLE-USE, and there is deliberately no `replayable:` keyword on this class or
  # on Body.chunked (P3-19). BODY-1 permits #replayable? to be true ONLY when writing more than once
  # provably yields byte-for-byte identical output. An #each-shaped object may or may not, and a
  # keyword would let a caller ASSERT the property -- an assertion the retry, redirect and 401 paths
  # then believe (BODY-4). A caller with a genuinely repeatable source uses Body.bytes, or calls
  # #to_replayable and pays one materialisation.
  #
  # It closes nothing (BODY-8): it opened nothing, and an #each-shaped object that holds a resource
  # must expose #close and be closed by its owner.
  class ChunkedBody
    include Dexpace::Body

    attr_reader :media_type, :content_length

    def initialize(chunked, media_type: nil, content_length: -1)
      unless chunked.respond_to?(:each)
        raise Dexpace::InvalidArgumentError,
              "a chunked body takes an object responding to #each, got #{chunked.class}"
      end
      unless content_length.is_a?(::Integer) && content_length >= -1
        raise Dexpace::InvalidArgumentError,
              "content_length must be an Integer of -1 or more, got #{content_length.inspect}"
      end

      @chunked = chunked
      @media_type = media_type
      @content_length = content_length
      initialize_single_use
    end

    def write_to(sink)
      claim_single_use!
      written = 0
      @chunked.each { |chunk| written += emit_exactly(sink, chunk) }
      written
    end

    # HTTP-46: identity, for StreamBody's reason. Two different #each-shaped objects are two
    # different values even when they happen to yield the same bytes once.
    def ==(other)
      equal?(other)
    end
    alias eql? ==

    def hash
      object_id.hash
    end
  end
end
```

- [ ] **Step 4: Write `lib/dexpace/http/body/form_body.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"
require_relative "../percent_encoding"
require_relative "../media_type"

module Dexpace
  # HTTP-38/BODY-35's form body: always replayable, application/x-www-form-urlencoded, and encoded
  # with the "+"-for-space encoder that lives beside the RFC 3986 one rather than with the RFC 3986
  # one. Phase 1 handed this deliverable here explicitly.
  class FormBody
    include Dexpace::Body

    MEDIA_TYPE = Dexpace::MediaType.parse("application/x-www-form-urlencoded")

    attr_reader :pairs

    # `pairs` is anything that iterates as [name, value] -- an Array of pairs or a Hash. It is
    # copied and frozen at construction, and the bytes are produced then too, so #content_length is
    # exact and a caller's later mutation cannot reach the body.
    def initialize(pairs)
      unless pairs.respond_to?(:map)
        raise Dexpace::InvalidArgumentError,
              "a form body takes pairs responding to #map, got #{pairs.class}"
      end

      @pairs = pairs.map do |name, value|
        [name.to_s.dup.freeze, value.to_s.dup.freeze].freeze
      end.freeze
      @bytes = Dexpace::PercentEncoding.encode_form(@pairs).b.freeze
      freeze
    end

    def media_type
      MEDIA_TYPE
    end

    def content_length
      @bytes.bytesize
    end

    def replayable?
      true
    end

    def write_to(sink)
      emit_exactly(sink, @bytes)
    end

    # HTTP-46: by value, over the pairs that determine the bytes.
    def ==(other)
      other.is_a?(FormBody) && other.pairs == @pairs
    end
    alias eql? ==

    def hash
      [self.class, @pairs].hash
    end
  end
end
```

- [ ] **Step 5: Write the two `sig/` mirrors**

`sig/dexpace/http/body/chunked_body.rbs`:

```rbs
module Dexpace
  class ChunkedBody
    include Dexpace::Body

    attr_reader media_type: Dexpace::MediaType?
    attr_reader content_length: Integer

    def initialize: (Dexpace::IO::_Chunked chunked, ?media_type: Dexpace::MediaType?,
                     ?content_length: Integer) -> void
    def write_to: (Dexpace::IO::_Sink sink) -> Integer
    def ==: (untyped) -> bool
    def eql?: (untyped) -> bool
    def hash: () -> Integer
  end
end
```

`sig/dexpace/http/body/form_body.rbs`:

```rbs
module Dexpace
  class FormBody
    include Dexpace::Body

    MEDIA_TYPE: Dexpace::MediaType

    attr_reader pairs: Array[[ String, String ]]

    def initialize: (untyped pairs) -> void
    def media_type: () -> Dexpace::MediaType
    def content_length: () -> Integer
    def replayable?: () -> bool
    def write_to: (Dexpace::IO::_Sink sink) -> Integer
    def ==: (untyped) -> bool
    def eql?: (untyped) -> bool
    def hash: () -> Integer
  end
end
```

- [ ] **Step 6: Add the two `require_relative`s to `lib/dexpace.rb`**

- [ ] **Step 7: Run the tests to confirm they pass**

Expected: PASS — **12** and **11 tests**, and **21** in `body_test.rb`.

---

## Task 6: `Dexpace::FileBody` — `::IO.copy_stream`, and no `#to_path`

**Requirement IDs:** `HTTP-40`/`BODY-11`'s six construction clauses and fresh handle per write,
`BODY-12` clause 1, `BODY-13`, `HTTP-46`; deviations **P3-17** and **P3-21**'s second half.
**Design:** "`FileBody` is the one that carries the most requirement per line"; §7.1 applied,
point 3.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/body/file_body.rb` and
  `gems/dexpace-core/sig/dexpace/http/body/file_body.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/body/file_body_test.rb`

**Interfaces:**
- Consumes: Task 1's `Dexpace::Body`; phase 1's `Dexpace::Model.required!` and
  `Dexpace::InvalidArgumentError`; 3a's `Dexpace::StreamError.short_transfer`.
- Produces: `Dexpace::FileBody.new(path, media_type:, offset:, count:)` with `#path`, `#offset`,
  `#count` and **no `#to_path`**. Phase 8's transport dispatches on those three.

**Independent of Tasks 2–5; it needs only Task 1.** `BODY-11` lists six construction clauses and
gets **one test per clause**, because a single "it validates" test passes with five of six checks
missing.

Two facts decide the implementation, both verified on 3.2.11, 3.4.10 and 4.0.6.
`::IO.copy_stream(handle, sink, count, offset)` accepts a duck-typed `#write` destination, honours
the window, leaves the handle's own cursor untouched when an offset is given, and returns the byte
count — which is `BODY-12` clause 1 and `BODY-13`'s short-write detection in one stdlib call. And
`::IO.copy_stream` checks `respond_to?(:to_path)` **first**, so `copy_stream(body, socket)` with no
length on a body defining `#to_path` copies the **whole file** and silently ignores the window.
`#to_path` is therefore deliberately not defined, and there is a test that says so.

- [ ] **Step 1: Write the failing test**

The `LeakyEach` double at the bottom is a `FileBody`-shaped object: a resource acquired and
released inside an ordinary `#each` method, which is exactly the shape `BODY-11`'s
fresh-handle-per-write requirement forces. The three residue tests assert the three **verified**
behaviours directly. There is no test claiming the leak is prevented, and no `ObjectSpace`.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/fake_sink"
require "tempfile"

# HTTP-40, HTTP-46, BODY-1, BODY-11, BODY-12, BODY-13, and §7.1's residue.
class DexpaceFileBodyTest < DexpaceTestCase
  def with_file(content = "0123456789")
    ::Tempfile.create("file_body") do |file|
      file.write(content)
      file.flush
      yield file
    end
  end

  def drain(body)
    sink = Dexpace::IO::Buffer.new
    body.write_to(sink)
    sink.snapshot
  end

  # ---- BODY-11's six construction clauses, one test each -----------------------------------
  # A single "it validates" test would pass with five of the six checks missing, which is why
  # BODY-11 gets six rows here and not one.

  test "rejects a path that does not exist" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Body.file("/nonexistent/dexpace/file")
    end

    assert_includes(error.message, "does not exist")
  end

  test "rejects a directory" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.file(Dir.tmpdir) }

    assert_includes(error.message, "not a regular file")
  end

  test "rejects a character device" do
    skip("no /dev/null on this platform") unless ::File.exist?("/dev/null")
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.file("/dev/null") }

    assert_includes(error.message, "not a regular file")
  end

  test "rejects a negative offset" do
    with_file do |file|
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Body.file(file.path, offset: -1)
      end

      assert_includes(error.message, "offset")
    end
  end

  test "rejects an offset past the size captured at construction" do
    with_file do |file|
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Body.file(file.path, offset: 11)
      end

      assert_includes(error.message, "past the end")
    end
  end

  test "rejects a count that runs past the size captured at construction" do
    with_file do |file|
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Body.file(file.path, offset: 8, count: 5)
      end

      assert_includes(error.message, "exceeds")
    end
  end

  test "rejects a negative count" do
    with_file do |file|
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.file(file.path, count: -2) }
    end
  end

  # ---- the window and the exact byte count -------------------------------------------------

  test "resolves a nil count to the rest of the file, so #count is always exact" do
    with_file { |file| assert_equal(10, Dexpace::Body.file(file.path).count) }
  end

  test "writes exactly the offset+count window and nothing outside it" do
    with_file do |file|
      assert_equal("3456".b, drain(Dexpace::Body.file(file.path, offset: 3, count: 4)))
    end
  end

  test "an empty window is a legitimate empty write" do
    with_file do |file|
      sink = FakeSink.new

      assert_equal(0, Dexpace::Body.file(file.path, count: 0).write_to(sink))
      assert_empty(sink.writes)
    end
  end

  test "delivers BINARY bytes" do
    with_file("héllo") do |file|
      assert_equal(::Encoding::BINARY, drain(Dexpace::Body.file(file.path)).encoding)
    end
  end

  # ---- BODY-11's fresh handle per write ----------------------------------------------------

  test "is replayable and writes identical bytes on every write" do
    with_file do |file|
      body = Dexpace::Body.file(file.path, offset: 3, count: 4)

      assert_predicate(body, :replayable?)
      assert_equal("3456".b, drain(body))
      assert_equal("3456".b, drain(body))
    end
  end

  test "opens a fresh handle per write, so concurrent writes do not share a cursor" do
    with_file("0123456789" * 64) do |file|
      body = Dexpace::Body.file(file.path)
      results = ::Thread::Queue.new
      threads = Array.new(8) { ::Thread.new { results << drain(body) } }
      threads.each(&:join)
      collected = Array.new(8) { results.pop }

      assert_equal([("0123456789" * 64).b], collected.uniq)
    end
  end

  test "does not disturb a caller's own open handle, because it opens its own" do
    with_file do |file|
      file.rewind
      file.read(4)
      drain(Dexpace::Body.file(file.path, offset: 0, count: 10))

      assert_equal(4, file.pos)
    end
  end

  # ---- BODY-12 clause 2: recognizable by type, and NOT by #to_path --------------------------

  # Verified on 3.2.11, 3.4.10 and 4.0.6: ::IO.copy_stream checks respond_to?(:to_path) first, and
  # copy_stream(body, sink) with no length then copies the WHOLE FILE. Defining #to_path would make
  # a transport doing the obvious thing silently upload every byte and ignore the window.
  test "does not define #to_path, which would make a transport ignore the window" do
    with_file do |file|
      body = Dexpace::Body.file(file.path, offset: 3, count: 4)

      refute(body.respond_to?(:to_path))
    end
  end

  test "exposes path, offset and count instead, which is what a transport dispatches on" do
    with_file do |file|
      body = Dexpace::Body.file(file.path, offset: 3, count: 4)

      assert(body.respond_to?(:path))
      assert(body.respond_to?(:offset))
      assert(body.respond_to?(:count))
      assert_equal([file.path, 3, 4], [body.path, body.offset, body.count])
    end
  end

  # ---- BODY-13's short write ---------------------------------------------------------------

  test "detects a short write and names transferred-of-total" do
    with_file do |file|
      body = Dexpace::Body.file(file.path, count: 10)
      error = assert_raises(Dexpace::StreamError) { body.write_to(FakeSink.new(3)) }

      assert_includes(error.message, "3")
      assert_includes(error.message, "10")
    end
  end

  # Counted through /proc rather than ObjectSpace, which design §7.1 and
  # `resource-management/1676974d` bar twice over: an ObjectSpace sweep answers "has the collector
  # got to it yet", which is precisely the question a deterministic-cleanup test must not ask.
  test "closes its handle even when the sink raises partway" do
    skip("descriptor counting needs /proc") unless ::File.directory?("/proc/self/fd")
    with_file do |file|
      body = Dexpace::Body.file(file.path)
      before = ::Dir.children("/proc/self/fd").length
      20.times do
        assert_raises(Dexpace::StreamError) do
          body.write_to(FakeSink.new(Dexpace::StreamError.new("boom")))
        end
      end

      assert_equal(before, ::Dir.children("/proc/self/fd").length)
    end
  end

  # ---- §7.1's residue: the three verified behaviours, asserted rather than described --------

  test "internal iteration with a break runs the ensure" do
    log = LeakyEach.new
    log.each { |chunk| break if chunk == "b" }

    assert_includes(log.events, :close)
  end

  test "a full external drive to StopIteration runs the ensure" do
    log = LeakyEach.new
    enumerator = log.to_enum(:each)
    begin
      loop { enumerator.next }
    rescue ::StopIteration
      nil
    end

    assert_includes(log.events, :close)
  end

  # The residue itself, stated as a fact rather than as a claim that it is prevented. There is no
  # ObjectSpace finalizer here on purpose: `resource-management/1676974d` and design §7.1 both bar
  # relying on the collector for deterministic cleanup.
  test "next-then-abandon does not run the ensure, and neither does rewind" do
    abandoned = LeakyEach.new
    enumerator = abandoned.to_enum(:each)
    enumerator.next
    enumerator = nil
    ::GC.start
    ::GC.start

    rewound = LeakyEach.new
    rewind_enumerator = rewound.to_enum(:each)
    rewind_enumerator.next
    rewind_enumerator.rewind

    refute_includes(abandoned.events, :close)
    refute_includes(rewound.events, :close)
  end

  # block_given? is TRUE inside #each when the method is reached through to_enum(:each), so a
  # `raise unless block_given?` guard forbids nothing. The defence is where the resource lives, and
  # for FileBody there is nowhere for it to live.
  test "block_given? is true under external iteration, so no in-method guard can help" do
    probe = LeakyEach.new
    probe.to_enum(:each).next

    assert(probe.saw_block)
  end

  test "FileBody's own documentation states the residue rather than claiming it is closed" do
    source = File.read(File.expand_path("../../../../lib/dexpace/http/body/file_body.rb", __dir__))

    assert_includes(source, "to_enum(:each)")
    assert_includes(source, "LEAKS")
  end

  # ---- equality -----------------------------------------------------------------------------

  test "compares by value over path, offset, count and media type" do
    with_file do |file|
      assert_equal(Dexpace::Body.file(file.path, offset: 1, count: 2),
                   Dexpace::Body.file(file.path, offset: 1, count: 2),)
      refute_equal(Dexpace::Body.file(file.path, offset: 1, count: 2),
                   Dexpace::Body.file(file.path, offset: 2, count: 2),)
      assert_equal(Dexpace::Body.file(file.path).hash, Dexpace::Body.file(file.path).hash)
    end
  end

  # A FileBody-shaped double: a resource acquired and released inside an ordinary #each method,
  # which is exactly the shape BODY-11's fresh-handle-per-write requirement forces.
  class LeakyEach
    attr_reader :events, :saw_block

    def initialize
      @events = []
      @saw_block = nil
    end

    def each
      @saw_block = block_given?
      @events << :open
      begin
        yield "a"
        yield "b"
        yield "c"
      ensure
        @events << :close
      end
    end
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Expected: FAIL — `uninitialized constant Dexpace::FileBody`.

- [ ] **Step 3: Write `lib/dexpace/http/body/file_body.rb`**

The YARD block is load-bearing rather than decorative: the residue test greps this file for
`to_enum(:each)` and `LEAKS`, because §10.10's precedent is that an admitted hole beats a fake
proof, and an admission nobody can find is not an admission.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"

module Dexpace
  # HTTP-40/BODY-11's file body: replayable, a FRESH ::File handle per write, and fail-fast
  # construction validating six clauses before any write is attempted.
  #
  # BODY-12's first clause is implemented here through ::IO.copy_stream(handle, sink, count,
  # offset), which is core Ruby (no require), accepts a duck-typed #write destination, honours the
  # (length, offset) window, leaves the handle's own cursor untouched when an offset is given, and
  # returns the byte count -- which is BODY-13's short-write detection for free. It is also the call
  # that becomes a real kernel sendfile/copy_file_range the moment both ends are real ::IOs, which
  # is what clause 2 is waiting for (DEF-3, DEF-10, phase 8).
  #
  # #to_path IS DELIBERATELY NOT DEFINED, and that is the whole of BODY-12's clause-2 answer from
  # this side. Verified on 3.2.11, 3.4.10 and 4.0.6: ::IO.copy_stream checks respond_to?(:to_path)
  # first, and copy_stream(body, sink) with NO length then copies the WHOLE FILE -- so a transport
  # doing the obvious thing would silently upload every byte of the file and ignore this body's
  # offset+count window. #path, #offset and #count are public instead, which is what "recognizable
  # by type so transports can dispatch a true zero-copy kernel path" actually needs.
  #
  # §7.1's residue, stated rather than closed. BODY-11 requires a fresh handle per write, so the
  # handle cannot live on the object and #close cannot release it. A consumer that drives
  # `file_body.to_enum(:each)` with #next and abandons it before exhaustion LEAKS that handle: the
  # ensure below does not run, #rewind does not run it, and GC.start is not a cleanup hook -- all
  # verified on 3.2.11, 3.4.10 and 4.0.6, and `docs/knowledge/notes/pagination.md` records that an
  # ordinary #each method leaks exactly like an Enumerator.new block. A FULL external drive to
  # StopIteration does run it, so BufferedSource.over(file_body) driven to exhaustion is safe, and
  # internal iteration with a break runs it too. Nothing in Ruby closes the abandonment case and
  # this class does not pretend otherwise; design §10.10's precedent is that an admitted hole beats
  # a fake proof, and `resource-management/1676974d` is why a finalizer is not the answer.
  class FileBody
    include Dexpace::Body

    attr_reader :path, :offset, :count, :media_type

    # BODY-11's six clauses, in this order, each raising Dexpace::InvalidArgumentError naming the
    # argument, and all of them before any I/O beyond one ::File.stat. `count: nil` is the
    # rest-of-file sentinel and resolves to size - offset at construction, so #count is always an
    # exact Integer -- HTTP-40's "MUST expose the exact byte count it will upload".
    def initialize(path, media_type: nil, offset: 0, count: nil)
      target = Dexpace::Model.required!("path", path).to_s
      validate_target!(target)
      validate_window!(offset, count)

      @path = target.dup.freeze
      @offset = offset
      @count = resolve_count(target, offset, count)
      @media_type = media_type
      freeze
    end

    def content_length
      @count
    end

    # BODY-11: replayable, because every write opens its own handle and reads its own window, so
    # concurrent and repeated sends are safe at the body level with no shared cursor to race on.
    def replayable?
      true
    end

    def write_to(sink)
      return 0 if @count.zero?

      handle = ::File.open(@path, "rb")
      begin
        transferred = ::IO.copy_stream(handle, sink, @count, @offset)
        if transferred < @count
          raise Dexpace::StreamError.short_transfer(transferred: transferred, expected: @count)
        end

        transferred
      ensure
        handle.close
      end
    end

    # HTTP-46: by value, over path, offset, count and media type -- the four facts that determine
    # the bytes.
    def ==(other)
      other.is_a?(FileBody) && other.path == @path && other.offset == @offset &&
        other.count == @count && other.media_type == @media_type
    end
    alias eql? ==

    def hash
      [self.class, @path, @offset, @count, @media_type].hash
    end

    private

    # BODY-11's first two clauses. Split out of #initialize for Metrics/MethodLength's 25, and
    # the split is by clause group rather than by line count.
    def validate_target!(target)
      unless ::File.exist?(target)
        raise Dexpace::InvalidArgumentError, "path #{target.inspect} does not exist"
      end
      return if ::File.file?(target)

      raise Dexpace::InvalidArgumentError, "path #{target.inspect} is not a regular file"
    end

    # BODY-11's offset and count shape clauses, before any I/O beyond the one ::File.stat below.
    def validate_window!(offset, count)
      unless offset.is_a?(::Integer) && !offset.negative?
        raise Dexpace::InvalidArgumentError,
              "offset must be a non-negative Integer, got #{offset.inspect}"
      end
      return if count.nil? || (count.is_a?(::Integer) && !count.negative?)

      raise Dexpace::InvalidArgumentError,
            "count must be a non-negative Integer or nil for the rest of the file, " \
            "got #{count.inspect}"
    end

    # BODY-11's last two clauses, and HTTP-40's "MUST expose the exact byte count it will upload":
    # `count: nil` is the rest-of-file sentinel and resolves against the size captured HERE, so
    # #count is always an exact Integer.
    def resolve_count(target, offset, count)
      size = ::File.stat(target).size
      if offset > size
        raise Dexpace::InvalidArgumentError,
              "offset #{offset} is past the end of a #{size}-byte file"
      end
      span = count.nil? ? size - offset : count
      return span if offset + span <= size

      raise Dexpace::InvalidArgumentError,
            "offset #{offset} plus count #{span} exceeds the #{size}-byte size captured at " \
            "construction"
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/http/body/file_body.rbs`**

```rbs
module Dexpace
  class FileBody
    include Dexpace::Body

    attr_reader path: String
    attr_reader offset: Integer
    attr_reader count: Integer
    attr_reader media_type: Dexpace::MediaType?

    def initialize: (String path, ?media_type: Dexpace::MediaType?, ?offset: Integer,
                     ?count: Integer?) -> void
    def content_length: () -> Integer
    def replayable?: () -> bool
    def write_to: (Dexpace::IO::_Sink sink) -> Integer
    def ==: (untyped) -> bool
    def eql?: (untyped) -> bool
    def hash: () -> Integer
  end
end
```

- [ ] **Step 5: Add `require_relative "dexpace/http/body/file_body"` to `lib/dexpace.rb`**

- [ ] **Step 6: Run the test to confirm it passes**

Expected: PASS — **24 tests**, one of which skips where `/proc/self/fd` is absent.

---

## Task 7: `Dexpace::MultipartBody` and `MultipartBody::Part`

**Requirement IDs:** `BODY-2`'s two conjunctions, `HTTP-51` in full, `HTTP-46`.
**Design:** "`MultipartBody` derives its length and its bytes from one routine".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/body/multipart_body.rb` and
  `gems/dexpace-core/sig/dexpace/http/body/multipart_body.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/body/multipart_body_test.rb`

**Interfaces:**
- Consumes: Tasks 1–6 — every variant can be a part; Task 1's `counting_sink` and
  `emit_exactly`; phase 1's `Dexpace::MediaType` and `Dexpace::HeaderSyntax`; `securerandom`.
- Produces: `Dexpace::MultipartBody.new(parts, boundary:, subtype:)` with `#parts`, `#boundary`,
  `.generate_boundary` and `BOUNDARY_CHARS`; `Dexpace::MultipartBody::Part.new(name:, body:,
  filename:, headers:)`.

**Sixth, because every part is one of Tasks 1–6's bodies.** Its property test is the
highest-value one in the sub-phase: over random part lists the **declared length equals the bytes
`#write_to` actually produced**, which is `HTTP-51`'s own reason for one shared framing routine,
stated as a property rather than as three examples.

`#content_length` runs the same `#emit` against a counting sink, **lazily and memoised** (plan
decision 2) — a multipart body over eight file parts must not stat eight files to answer a header
question that may never be asked — and there is a test that the memoised value still equals the
bytes written after several writes. `-1` is truthy in Ruby, so `||=` memoises the unknown sentinel
correctly. The class is therefore **not frozen**, which is stated here so nobody adds a `freeze`
that turns the memo into a `FrozenError`.

**The counting run takes `count_only: true`, and that keyword is the whole of `P3-29`.** Writing
the part bodies into the counting sink would make a **header question consume them**: a part that
is single-use but length-known — `Body.stream(io, content_length: 6, close: true)`,
`Body.chunked(chunks, content_length: 4)`, a pipe-backed stream with a declared length — is drained
by `#content_length`, its stream closed if ownership was transferred, and the write that was going
to send it then raises `BODY-6`. Every `FileBody` part would also be read off disk in full to
answer it. `count_only:` changes exactly one line: the payload count comes from the part's own
`#content_length` instead of from writing it. The **framing** bytes still come from the one
routine, which is the drift `HTTP-51` exists to prevent, and `BODY-2`'s `-1` sentinel already
covers the case where a part's length is not known.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "stringio"

# HTTP-46, HTTP-51, BODY-2.
class DexpaceMultipartBodyTest < DexpaceTestCase
  def part(name: "f", body: Dexpace::Body.bytes("héllo"), **rest)
    Dexpace::MultipartBody::Part.new(name: name, body: body, **rest)
  end

  def drain(body)
    sink = Dexpace::IO::Buffer.new
    body.write_to(sink)
    sink.snapshot
  end

  # ---- HTTP-51's one shared framing routine ------------------------------------------------

  # THE property this class exists for, stated as a property rather than as three examples: over
  # random part lists the declared length equals the bytes written, because both come from #emit.
  test "the declared length always equals the bytes actually written" do
    sample(count: 48, seed: 20_260_908) do |rng|
      parts = Array.new(rng.rand(1..5)) do |index|
        payload = "é" * rng.rand(0..40)
        filename = rng.rand(2).zero? ? nil : "f#{index}.txt"
        part(name: "p#{index}", body: Dexpace::Body.bytes(payload), filename: filename)
      end
      body = Dexpace::Body.multipart(parts)

      assert_equal(body.content_length, drain(body).bytesize)
    end
  end

  test "the memoised length still equals the bytes written after several writes" do
    body = Dexpace::Body.multipart([part, part(name: "g")])
    declared = body.content_length

    assert_equal(declared, drain(body).bytesize)
    assert_equal(declared, body.content_length)
    assert_equal(declared, drain(body).bytesize)
  end

  # The length query runs the framing routine, and running it against the PART BODIES would make
  # asking for a header value consume them: a part that is single-use but length-known is drained
  # -- and, with close: true, closed -- before the write that was going to send it.
  test "the length query does not consume a single-use part, nor close its stream" do
    io = StringIO.new(+"héllo")
    part = part(body: Dexpace::Body.stream(io, content_length: 6, close: true))
    body = Dexpace::Body.multipart([part], boundary: "XyZ")
    declared = body.content_length

    refute_predicate(io, :closed?)
    assert_equal(declared, drain(body).bytesize)
  end

  test "computes the length lazily, so building a body stats nothing" do
    body = Dexpace::Body.multipart([part])

    assert_nil(body.instance_variable_get(:@content_length))
    body.content_length

    refute_nil(body.instance_variable_get(:@content_length))
  end

  test "frames each part with the boundary, its headers, a blank line and a trailing CRLF" do
    body = Dexpace::Body.multipart([part(name: "f", body: Dexpace::Body.bytes("AB"))],
                                   boundary: "XyZ",)

    assert_equal(
      "--XyZ\r\nContent-Disposition: form-data; name=\"f\"\r\n\r\nAB\r\n--XyZ--\r\n".b,
      drain(body),
    )
  end

  test "closes the body with the boundary plus two dashes" do
    assert(drain(Dexpace::Body.multipart([part], boundary: "XyZ")).end_with?("--XyZ--\r\n".b))
  end

  test "emits a part's own media type as a Content-Type header" do
    media = Dexpace::MediaType.parse("text/plain; charset=utf-8")
    body = Dexpace::Body.multipart([part(body: Dexpace::Body.bytes("A", media_type: media))],
                                   boundary: "XyZ",)

    assert_includes(drain(body), "Content-Type: text/plain; charset=utf-8".b)
  end

  # ---- BODY-2's conjunctions ----------------------------------------------------------------

  test "is replayable if and only if every part is replayable" do
    replayable = Dexpace::Body.multipart([part, part(name: "g")])
    mixed = Dexpace::Body.multipart(
      [part, part(name: "g", body: Dexpace::Body.stream(StringIO.new(+"a")))],
    )

    assert_predicate(replayable, :replayable?)
    refute_predicate(mixed, :replayable?)
  end

  test "collapses its declared length to the -1 sentinel if any part's length is unknown" do
    mixed = Dexpace::Body.multipart(
      [part, part(name: "g", body: Dexpace::Body.stream(StringIO.new(+"a")))],
    )

    assert_equal(-1, mixed.content_length)
  end

  # ---- HTTP-51's boundary grammar ------------------------------------------------------------

  test "generates a boundary inside RFC 2046's 1-70 bcharsnospace grammar" do
    boundary = Dexpace::Body.multipart([part]).boundary

    assert_operator(boundary.length, :>=, 1)
    assert_operator(boundary.length, :<=, 70)
    assert(boundary.each_char.all? { |c| Dexpace::MultipartBody::BOUNDARY_CHARS.include?(c) })
  end

  test "generates a different boundary every time" do
    boundaries = Array.new(16) { Dexpace::Body.multipart([part]).boundary }

    assert_equal(16, boundaries.uniq.length)
  end

  test "rejects a caller boundary carrying a character outside the grammar" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Body.multipart([part], boundary: "has space")
    end

    assert_includes(error.message, "bcharsnospace")
  end

  test "rejects an empty boundary and one longer than 70 characters" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.multipart([part], boundary: "") }
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Body.multipart([part], boundary: "a" * 71)
    end
  end

  test "carries the boundary into the media type, so a header can name it" do
    body = Dexpace::Body.multipart([part], boundary: "XyZ")

    assert_equal("multipart/form-data; boundary=XyZ", body.media_type.render)
  end

  # ---- HTTP-51's one MUST: quoting and escaping ----------------------------------------------

  test "escapes a quote in a parameter value so it cannot close the quoted string early" do
    body = Dexpace::Body.multipart([part(name: 'a"b')], boundary: "XyZ")

    assert_includes(drain(body), 'name="a\\"b"'.b)
  end

  test "escapes a backslash in a parameter value" do
    body = Dexpace::Body.multipart([part(name: "a\\b")], boundary: "XyZ")

    assert_includes(drain(body), 'name="a\\\\b"'.b)
  end

  # A CR or an LF is REJECTED rather than escaped: RFC 7578's quoted-string has no representation
  # for them, and an escaped CRLF is still a CRLF on the wire.
  test "rejects a CR or an LF in a parameter value rather than escaping it" do
    crlf = Dexpace::Body.multipart([part(name: "a\r\nContent-Length: 0")], boundary: "XyZ")
    error = assert_raises(Dexpace::InvalidArgumentError) { drain(crlf) }

    assert_includes(error.message, "CR or LF")
  end

  test "rejects a part header value carrying a byte no header value may carry" do
    body = Dexpace::Body.multipart([part(headers: { "X-Note" => "a\rb" })], boundary: "XyZ")

    assert_raises(Dexpace::InvalidArgumentError) { drain(body) }
  end

  # ---- construction and equality --------------------------------------------------------------

  test "rejects anything that is not a Part" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Body.multipart([Dexpace::Body.bytes("a")])
    end

    assert_includes(error.message, "Part")
  end

  test "a Part requires a name and a Dexpace::Body" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::MultipartBody::Part.new(name: nil, body: Dexpace::Body.bytes("a"))
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::MultipartBody::Part.new(name: "f", body: "not a body")
    end
  end

  test "compares by value over its boundary and its parts" do
    first = Dexpace::Body.multipart([part], boundary: "XyZ")
    same = Dexpace::Body.multipart([part], boundary: "XyZ")
    other = Dexpace::Body.multipart([part], boundary: "AbC")

    assert_equal(first, same)
    refute_equal(first, other)
    assert_equal(first.hash, same.hash)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Expected: FAIL — `uninitialized constant Dexpace::MultipartBody`.

- [ ] **Step 3: Write `lib/dexpace/http/body/multipart_body.rb`**

`HTTP-51`'s one MUST inside a SHOULD is `#quote`: a backslash and a quote are escaped, and a CR or
an LF is **rejected** rather than escaped, because RFC 7578's quoted-string has no representation
for them and an escaped CRLF is still a CRLF on the wire. Every rendered header line then runs
through phase 1's `HeaderSyntax.valid_outbound_value?` rather than a second copy of it.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "securerandom"

require_relative "../body"
require_relative "../media_type"
require_relative "../header_syntax"

module Dexpace
  # HTTP-51 and BODY-2's composite body.
  #
  # ONE framing routine, #emit(sink), produces both the bytes and the declared length -- the length
  # runs it against a counting sink -- so HTTP-51's "the declared length can never drift from the
  # bytes written" is true by construction rather than by discipline. That is the highest-value
  # property test in this sub-phase.
  #
  # Not frozen, deliberately: #content_length memoises. Computing it eagerly would stat eight files
  # to answer a header question that may never be asked, and a body is not a Data value type
  # (design §4's construction pattern is for the wire model, and every body carries at least a
  # media type and a length, several an open stream, and two a consume-once latch).
  class MultipartBody
    include Dexpace::Body

    CRLF = "\r\n".b.freeze
    DASHES = "--".b.freeze

    # RFC 2046 bcharsnospace, which is the set a boundary may use with no trailing space.
    BOUNDARY_CHARS = (
      ("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a + %w[' ( ) + _ , - . / : = ?]
    ).freeze
    BOUNDARY_LENGTH = 48

    # One part: a name, an optional filename, a body, and any extra part headers.
    class Part
      attr_reader :name, :filename, :body, :headers

      def initialize(name:, body:, filename: nil, headers: {})
        @name = Dexpace::Model.required!("name", name).to_s.dup.freeze
        unless Dexpace::Model.required!("body", body).is_a?(Dexpace::Body)
          raise Dexpace::InvalidArgumentError, "a part's body must be a Dexpace::Body"
        end

        @filename = filename&.to_s&.dup&.freeze
        @headers = headers.to_h { |key, value| [key.to_s.dup.freeze, value.to_s.dup.freeze] }.freeze
        @body = body
        freeze
      end

      def replayable?
        @body.replayable?
      end

      def content_length
        @body.content_length
      end

      def ==(other)
        other.is_a?(Part) && other.name == @name && other.filename == @filename &&
          other.headers == @headers && other.body == @body
      end
      alias eql? ==

      def hash
        [self.class, @name, @filename, @headers, @body].hash
      end
    end

    attr_reader :parts, :boundary

    def initialize(parts, boundary: nil, subtype: "form-data")
      list = Dexpace::Model.required!("parts", parts).to_a
      unless list.all? { |part| part.is_a?(Part) }
        raise Dexpace::InvalidArgumentError,
              "every part must be a Dexpace::MultipartBody::Part"
      end

      @parts = list.freeze
      @boundary = boundary.nil? ? self.class.generate_boundary : validate_boundary!(boundary)
      @media_type = Dexpace::MediaType.parse("multipart/#{subtype}; boundary=#{@boundary}")
    end

    attr_reader :media_type

    # BODY-2: replayable if and only if EVERY constituent part is replayable.
    def replayable?
      @parts.all?(&:replayable?)
    end

    # BODY-2: the declared length collapses to the -1 sentinel if any part's length is unknown.
    # Otherwise it is the byte count the framing routine actually produces, computed lazily and
    # memoised. -1 is truthy in Ruby, so ||= memoises the sentinel correctly too.
    def content_length
      @content_length ||= compute_content_length
    end

    def write_to(sink)
      emit(sink)
    end

    # HTTP-51: 1..70 characters from bcharsnospace, generated with SecureRandom (already on phase
    # 0's require allowlist).
    def self.generate_boundary
      bytes = ::SecureRandom.bytes(BOUNDARY_LENGTH)
      bytes.each_byte.map { |byte| BOUNDARY_CHARS[byte % BOUNDARY_CHARS.length] }.join.freeze
    end

    def ==(other)
      other.is_a?(MultipartBody) && other.boundary == @boundary && other.parts == @parts
    end
    alias eql? ==

    def hash
      [self.class, @boundary, @parts].hash
    end

    private

    def compute_content_length
      return -1 if @parts.any? { |part| part.content_length.negative? }

      emit(counting_sink, count_only: true)
    end

    # THE one framing routine. #write_to and #content_length both run it; nothing else writes a
    # boundary or a part header, which is what HTTP-51's SHOULD is for.
    #
    # `count_only:` changes exactly one line, and it has to. Writing the part bodies to the
    # counting sink would mean a HEADER QUESTION consumes them: a part that is single-use but
    # length-known -- Body.stream(io, content_length: 6, close: true), Body.chunked(chunks,
    # content_length: 4), a pipe-backed stream with a declared length -- is drained (and, with
    # close: true, closed) by #content_length, and the write that follows raises BODY-6. Every
    # FileBody part would also be read off disk in full to answer it. The FRAMING bytes still
    # come from this one routine, which is the drift HTTP-51 exists to prevent; the payload count
    # is the part's own HTTP-36 declared length, and BODY-2's sentinel above is what covers the
    # case where it is not known.
    def emit(sink, count_only: false)
      written = 0
      @parts.each do |part|
        written += emit_exactly(sink, DASHES + @boundary.b + CRLF)
        written += emit_exactly(sink, part_headers(part))
        written += count_only ? part.content_length : part.body.write_to(sink)
        written += emit_exactly(sink, CRLF)
      end
      written + emit_exactly(sink, DASHES + @boundary.b + DASHES + CRLF)
    end

    def part_headers(part)
      lines = [+"Content-Disposition: form-data; name=#{quote(part.name)}"]
      lines[0] << "; filename=#{quote(part.filename)}" unless part.filename.nil?
      media = part.body.media_type
      lines << "Content-Type: #{media.render}" unless media.nil?
      part.headers.each { |key, value| lines << "#{key}: #{value}" }
      lines.each do |line|
        next if Dexpace::HeaderSyntax.valid_outbound_value?(line)

        raise Dexpace::InvalidArgumentError,
              "part header #{line.inspect} carries a byte no header value may carry (HTTP-51)"
      end
      (lines.join("\r\n") + "\r\n\r\n").b
    end

    # HTTP-51's one MUST inside a SHOULD: a CR, an LF or a quote in a parameter value must not be
    # able to break the framing. A backslash and a quote are escaped; a CR or an LF is REJECTED
    # rather than escaped, because RFC 7578 quoted-string has no representation for them and an
    # escaped CRLF would still be a CRLF on the wire.
    def quote(value)
      if value.include?("\r") || value.include?("\n")
        raise Dexpace::InvalidArgumentError,
              "a multipart parameter value must not contain CR or LF, got #{value.inspect}"
      end

      %("#{value.gsub(/[\\"]/) { |match| "\\#{match}" }}")
    end

    def validate_boundary!(boundary)
      text = boundary.to_s
      unless (1..70).cover?(text.length) && text.each_char.all? { |c| BOUNDARY_CHARS.include?(c) }
        raise Dexpace::InvalidArgumentError,
              "boundary #{text.inspect} violates RFC 2046's 1-70 bcharsnospace grammar (HTTP-51)"
      end

      text.dup.freeze
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/http/body/multipart_body.rbs`**

```rbs
module Dexpace
  class MultipartBody
    include Dexpace::Body

    CRLF: String
    DASHES: String
    BOUNDARY_CHARS: Array[String]
    BOUNDARY_LENGTH: Integer

    class Part
      attr_reader name: String
      attr_reader filename: String?
      attr_reader body: Dexpace::Body
      attr_reader headers: Hash[String, String]

      def initialize: (name: String, body: Dexpace::Body, ?filename: String?,
                       ?headers: Hash[String, String]) -> void
      def replayable?: () -> bool
      def content_length: () -> Integer
      def ==: (untyped) -> bool
      def eql?: (untyped) -> bool
      def hash: () -> Integer
    end

    attr_reader parts: Array[Dexpace::MultipartBody::Part]
    attr_reader boundary: String
    attr_reader media_type: Dexpace::MediaType

    def initialize: (Array[Dexpace::MultipartBody::Part] parts, ?boundary: String?,
                     ?subtype: String) -> void
    def replayable?: () -> bool
    def content_length: () -> Integer
    def write_to: (Dexpace::IO::_Sink sink) -> Integer
    def self.generate_boundary: () -> String
    def ==: (untyped) -> bool
    def eql?: (untyped) -> bool
    def hash: () -> Integer

    private

    def compute_content_length: () -> Integer
    def emit: (Dexpace::IO::_Sink sink) -> Integer
    def part_headers: (Dexpace::MultipartBody::Part part) -> String
    def quote: (String value) -> String
    def validate_boundary!: (untyped boundary) -> String
  end
end
```

- [ ] **Step 5: Add `require_relative "dexpace/http/body/multipart_body"` to `lib/dexpace.rb`**

- [ ] **Step 6: Run the test to confirm it passes**

Expected: PASS — **21 tests**.

- [ ] **Step 7: Run the require-allowlist audit**

Run: `bundle exec rake gates:require_allowlist`
Expected: clean. `securerandom` is phase 0's, already on the twelve-name list; this is the one
`require` phase 3b adds and it is the only task that can break the audit.

---

## Task 8: `Dexpace::ResponseBody`, and the one decode boundary

**Requirement IDs:** `HTTP-41`/`BODY-14`'s single-use handle, `BODY-15`'s idempotent close,
`BODY-16`'s finally-style readers, `HTTP-42`'s decode, `HTTP-43`'s response close, `BODY-32`'s cap
rules, `BODY-33`'s non-consuming preview, `HTTP-46`. **Design:** "`Dexpace::ResponseBody` — the
single-use handle"; "The three additions to phase-1 types"; "Encoding, stated once for 3b";
addendum **B1**; `OI-7`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/body/response_body.rb` and
  `gems/dexpace-core/sig/dexpace/http/body/response_body.rbs`
- Modify: `gems/dexpace-core/lib/dexpace/http/response.rb`,
  `gems/dexpace-core/sig/dexpace/http/response.rbs`, `gems/dexpace-core/lib/dexpace.rb`,
  `gems/dexpace-core/test/dexpace/http/response_test.rb` (append one section)
- Test: `gems/dexpace-core/test/dexpace/http/body/response_body_test.rb`

**Interfaces:**
- Consumes: Task 1's contract and both copy routines and `clamp_cap`; 3a's
  `Dexpace::IO::BufferedSource` with `#peek`, `#read`, `#read_string` and `#close`; phase 2's
  `Dexpace::Closeable`; phase 1's `Dexpace::MediaType#charset` and `Dexpace::Response`.
- Produces: `Dexpace::ResponseBody.new(source:, media_type:, content_length:)` with a block form,
  `#source`, `#close`, `#closed?`, `#preview(cap:)` and `#write_to`; and `Dexpace::Response#close`,
  `#body_string`, `#body_bytes` and `.resolve_charset`. Tasks 9, 11 and 12 all read these.

**Seventh, because it depends on 3a's `BufferedSource.wrapping` and on nothing else in 3b** — and
because the decode boundary lands with the object that owns the bytes.

**The decode boundary is the correctness-critical part of this task, and design §3.1's recipe for
it is wrong.** §3.1 says `#body_string` "applies the media type's charset via
`String#encode(invalid: :replace, undef: :replace)`". Applied to the BINARY bytes 3a delivers,
that call replaces **every** byte ≥ 0x80: `"café".b.encode(::Encoding::UTF_8, invalid: :replace,
undef: :replace)` is `"caf"` followed by two U+FFFD, on 3.2.11, 3.4.10 and 4.0.6 alike, because
from BINARY every high byte is undefined in the *source* encoding. And that call names no target,
so it converts to `Encoding.default_internal` — a process global the **host** sets. Three steps,
all load-bearing: resolve the charset from `MediaType#charset` (already `nil` for absent *or*
unknown, so `Encoding.find` cannot raise), **retag** through 3a's `#read_string`, then transcode
with **both** encodings named. `OI-7` and `docs/knowledge/notes/io-and-byte-streams.md` carry it.

- [ ] **Step 1: Write the failing tests**

`gems/dexpace-core/test/dexpace/http/body/response_body_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/fake_sink"
require "stringio"

# HTTP-41, HTTP-46, BODY-14, BODY-15, BODY-32, BODY-33.
class DexpaceResponseBodyTest < DexpaceTestCase
  def body(content = "héllo", **rest)
    Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes(content), **rest)
  end

  def over(io, **rest)
    Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.wrapping(io), **rest)
  end

  # ---- BODY-14: single-use, and the SAME handle every time ---------------------------------

  test "returns the same underlying handle every time, never a fresh replay" do
    subject = body

    assert_same(subject.source, subject.source)
  end

  test "is not replayable, because a response body's bytes are gone once consumed" do
    refute_predicate(body, :replayable?)
  end

  test "writes once and raises on a second write rather than emitting zero bytes" do
    subject = body
    sink = Dexpace::IO::Buffer.new
    subject.write_to(sink)
    error = assert_raises(Dexpace::StreamError) { subject.write_to(Dexpace::IO::Buffer.new) }

    assert_equal("héllo".b, sink.snapshot)
    assert_includes(error.message, "BODY-6")
  end

  test "to_replayable materialises it once into a repeatable BufferBody" do
    materialized = body.to_replayable
    first = Dexpace::IO::Buffer.new
    second = Dexpace::IO::Buffer.new
    materialized.write_to(first)
    materialized.write_to(second)

    assert_equal("héllo".b, first.snapshot)
    assert_equal("héllo".b, second.snapshot)
  end

  test "copies exactly the declared count when it has one" do
    subject = body("0123456789", content_length: 4)
    sink = Dexpace::IO::Buffer.new
    subject.write_to(sink)

    assert_equal("0123".b, sink.snapshot)
  end

  # ---- BODY-15: idempotent close that releases the transport resource ----------------------

  test "close releases the underlying source" do
    source = Dexpace::IO::BufferedSource.of_bytes("héllo")
    subject = Dexpace::ResponseBody.new(source: source)
    subject.close

    assert_predicate(source, :closed?)
    assert_predicate(subject, :closed?)
  end

  test "close is idempotent, and the second close releases nothing a second time" do
    io = StringIO.new(+"héllo")
    subject = over(io)
    subject.close
    subject.close

    assert_predicate(io, :closed?)
  end

  test "close makes no assumption that the body was read" do
    io = StringIO.new(+"héllo")
    over(io).close

    assert_predicate(io, :closed?)
  end

  test "the block form closes on a normal return and returns the block's value" do
    io = StringIO.new(+"héllo")
    source = Dexpace::IO::BufferedSource.wrapping(io)
    result = Dexpace::ResponseBody.new(source: source) { |b| b.content_length }

    assert_equal(-1, result)
    assert_predicate(io, :closed?)
  end

  test "the block form closes on any exit path, including a raise" do
    io = StringIO.new(+"héllo")
    source = Dexpace::IO::BufferedSource.wrapping(io)
    assert_raises(Dexpace::StreamError) do
      Dexpace::ResponseBody.new(source: source) { raise Dexpace::StreamError, "boom" }
    end

    assert_predicate(io, :closed?)
  end

  # ---- BODY-33 and BODY-32: the non-consuming capped preview -------------------------------

  test "preview reads from a fresh peek view and does not advance the primary read path" do
    subject = body("0123456789")

    assert_equal("0123".b, subject.preview(cap: 4))
    assert_equal("0123".b, subject.preview(cap: 4))
    sink = Dexpace::IO::Buffer.new
    subject.write_to(sink)

    assert_equal("0123456789".b, sink.snapshot)
  end

  test "preview returns an empty result when the source is exhausted" do
    subject = body("abc")
    subject.write_to(Dexpace::IO::Buffer.new)

    assert_equal("".b, subject.preview(cap: 8))
  end

  test "preview returns whatever bytes exist without requiring exactly the cap" do
    assert_equal("abc".b, body("abc").preview(cap: 64))
  end

  test "preview rejects a negative cap" do
    error = assert_raises(Dexpace::InvalidArgumentError) { body.preview(cap: -1) }

    assert_includes(error.message, "negative")
  end

  test "preview silently clamps a cap above the ceiling, never up" do
    over_ceiling = Dexpace::IO::MAX_MATERIALIZED_BYTES + 1

    assert_equal("abc".b, body("abc").preview(cap: over_ceiling))
    assert_equal("abc".b, body("abc").preview(cap: ::Float::INFINITY))
  end

  # BODY-32 as a property: negative raises, and every accepted cap returns at most
  # min(cap, ceiling, available) bytes.
  test "the clamp holds over negative, zero, huge and ceiling+1 caps" do
    ceiling = Dexpace::IO::MAX_MATERIALIZED_BYTES
    sample(count: 40, seed: 20_260_908) do |rng|
      cap = [-rng.rand(1..8), 0, rng.rand(0..12), ceiling + 1, ceiling * 2].sample(random: rng)
      subject = body("0123456789")
      if cap.negative?
        assert_raises(Dexpace::InvalidArgumentError) { subject.preview(cap: cap) }
      else
        assert_operator(subject.preview(cap: cap).bytesize, :<=, [cap, ceiling, 10].min)
      end
    end
  end

  test "preview closes every view it takes, so repeated previews do not grow the registry" do
    source = Dexpace::IO::BufferedSource.of_bytes("0123456789")
    subject = Dexpace::ResponseBody.new(source: source)
    20.times { subject.preview(cap: 4) }

    assert_equal(0, source.instance_variable_get(:@dexpace_views).length)
  end

  # ---- construction and equality -----------------------------------------------------------

  test "rejects a source that does not respond to read_into" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::ResponseBody.new(source: Object.new)
    end

    assert_includes(error.message, "#read_into")
  end

  test "compares by identity, because two live sources are two values" do
    subject = body

    assert_equal(subject, subject)
    refute_equal(subject, body)
  end
end
```

Appended to `gems/dexpace-core/test/dexpace/http/response_test.rb`, and quoted here as a whole
file so the addition can be run on its own. **`#with_default_internal` is not a convenience.** The
design mandates "half the decode property runs with `Encoding.default_internal =
`::Encoding::ISO_8859_1`", and that assignment emits `warning: setting Encoding.default_internal`
under `ruby -w`, which `DexpaceTestCase`'s `Warning.warn` override turns into a failure — both the
set **and** the restore, verified on all three interpreters. `$VERBOSE = nil` around the two
assignments and nothing else is the narrowest suppression that makes the mandated test writable,
and there is a test asserting `-w` is still live inside the block, so the suppression cannot
silently widen.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "stringio"

# HTTP-41, HTTP-42, HTTP-43, BODY-16. The three methods phase 3b adds to phase 1's Response.
#
# These are appended to phase 1's own response_test.rb rather than living in a file of their own;
# they are separated here only so the addition can be read on its own.
class DexpaceResponseBodyReaderTest < DexpaceTestCase
  # Sets Encoding.default_internal for the duration of the block and restores it, with the two
  # assignments -- and ONLY those -- made outside $VERBOSE.
  #
  # This helper exists because `Encoding.default_internal = x` emits `warning: setting
  # Encoding.default_internal` under `ruby -w`, and DexpaceTestCase's Warning.warn override turns
  # every warning into a failure (NFR-6). Verified on 3.2.11, 3.4.10 and 4.0.6: without the two
  # narrow suppressions BOTH the set and the restore raise, and with them `-w` stays live for
  # everything the block runs -- which is checked below rather than assumed.
  def with_default_internal(encoding)
    previous = ::Encoding.default_internal
    verbose = $VERBOSE
    begin
      $VERBOSE = nil
      ::Encoding.default_internal = encoding
      $VERBOSE = verbose
      yield
    ensure
      $VERBOSE = nil
      ::Encoding.default_internal = previous
      $VERBOSE = verbose
    end
  end

  def response(body)
    request = Dexpace::Request.builder
    request.url = "https://example.test/"
    builder = Dexpace::Response.builder
    builder.request = request.build
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = Dexpace::Status.of(200)
    builder.body = body
    builder.build
  end

  def response_body(bytes, media_type: nil)
    Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes(bytes),
                              media_type: media_type,)
  end

  def media(text) = Dexpace::MediaType.parse(text)

  # ---- HTTP-43: close ------------------------------------------------------------------------

  test "close forwards to the body" do
    body = response_body("héllo")
    response(body).close

    assert_predicate(body, :closed?)
  end

  test "a bodyless close is a no-op rather than a failure" do
    assert_nil(response(nil).close)
  end

  test "close is idempotent, with the idempotence living in the body's own latch" do
    body = response_body("héllo")
    subject = response(body)
    subject.close
    subject.close

    assert_predicate(body, :closed?)
  end

  # ---- HTTP-42: THE decode boundary ----------------------------------------------------------

  # Every encoding test here uses NON-ASCII content on purpose: an ASCII-only fixture passes under
  # exactly the bug these three steps prevent.
  test "decodes UTF-8 bytes declared UTF-8 without mangling them" do
    subject = response(response_body("héllo", media_type: media("text/plain; charset=utf-8")))

    assert_equal("héllo", subject.body_string)
  end

  # The retag is the step design §3.1's recipe omits. Without it, from BINARY every byte >= 0x80 is
  # undefined in the SOURCE encoding and #encode replaces it: "café".b.encode(UTF_8, ...) is "caf"
  # plus TWO replacement characters, on all three interpreters.
  test "does not replace every non-ASCII byte, which the retag-less recipe does" do
    decoded = response(
      response_body("café", media_type: media("text/plain; charset=utf-8")),
    ).body_string

    assert_equal("café", decoded)
    refute_includes(decoded, "�")
  end

  test "defaults to UTF-8 when no charset is declared" do
    subject = response(response_body("héllo", media_type: media("text/plain")))

    assert_equal(::Encoding::UTF_8, subject.body_string.encoding)
  end

  test "defaults to UTF-8 when there is no media type at all" do
    assert_equal("héllo", response(response_body("héllo")).body_string)
  end

  # MediaType#charset already returns nil for a charset this Ruby does not know, so Encoding.find
  # cannot raise here and HTTP-42's fallback needs no second validation.
  test "falls back to UTF-8 when the declared charset is unknown to this Ruby" do
    subject = response(
      response_body("héllo", media_type: media("text/plain; charset=x-not-a-charset")),
    )

    assert_equal("héllo", subject.body_string)
  end

  test "honours a declared ISO-8859-1 charset" do
    subject = response(
      response_body("caf\xE9".b, media_type: media("text/plain; charset=iso-8859-1")),
    )
    decoded = subject.body_string

    assert_equal(::Encoding::ISO_8859_1, decoded.encoding)
    assert_equal("café", decoded.encode(::Encoding::UTF_8))
  end

  test "scrubs rather than raises when the bytes do not match the declared charset" do
    subject = response(
      response_body("caf\xE9".b, media_type: media("text/plain; charset=utf-8")),
    )
    decoded = subject.body_string

    assert_predicate(decoded, :valid_encoding?)
    assert_includes(decoded, "�")
  end

  test "returns nil for a bodyless response" do
    assert_nil(response(nil).body_string)
    assert_nil(response(nil).body_bytes)
  end

  # THE test that stands between the correct recipe and a silent revert to §3.1's. A target-less
  # #encode converts to Encoding.default_internal, a process global the HOST sets -- so a decode
  # that omits its target returns whatever the host asked for and destroys the payload on the way.
  test "the decoded result does not depend on the host's Encoding.default_internal" do
    with_default_internal(::Encoding::ISO_8859_1) do
      subject = response(response_body("héllo", media_type: media("text/plain; charset=utf-8")))
      decoded = subject.body_string

      assert_equal(::Encoding::UTF_8, decoded.encoding)
      assert_equal("héllo", decoded)
    end
  end

  # Against the AMBIENT $VERBOSE, not against `true`: under `-w` that is true and the assertion is
  # the suppression check this test exists for, and running the file without `-w` then still
  # passes rather than failing for the wrong reason (Global Constraints: every test passes alone).
  test "the default_internal helper leaves the ambient $VERBOSE live inside the block" do
    ambient = $VERBOSE
    inside = :unset
    with_default_internal(::Encoding::ISO_8859_1) { inside = $VERBOSE }

    assert_equal(ambient, inside)
    assert_nil(::Encoding.default_internal)
  end

  # HTTP-42 as a property: over random bytes and a small charset set, with a hostile
  # default_internal for half the runs, the result is always valid_encoding? and always tagged
  # with the resolved charset.
  test "the decode holds over random bytes and charsets, with a hostile default_internal" do
    charsets = ["utf-8", "iso-8859-1", "us-ascii", nil]
    sample(count: 48, seed: 20_260_908) do |rng|
      bytes = Array.new(rng.rand(0..24)) { rng.rand(0x80..0xFF).chr }.join.b
      charset = charsets.sample(random: rng)
      type = charset.nil? ? media("text/plain") : media("text/plain; charset=#{charset}")
      expected = charset.nil? ? ::Encoding::UTF_8 : ::Encoding.find(charset)
      hostile = rng.rand(2).zero?

      check = lambda do
        decoded = response(response_body(bytes, media_type: type)).body_string

        assert_equal(expected, decoded.encoding)
        assert_predicate(decoded, :valid_encoding?)
      end
      hostile ? with_default_internal(::Encoding::ISO_8859_1, &check) : check.call
    end
  end

  # ---- OI-10: every body a Response can hold answers #source and #close ----------------------

  # Response#close/#body_string/#body_bytes are written against #source and #close, and the body
  # BODY-30/HTTP-52 puts in an error response is a BufferBody. A suite that only ever builds a
  # Response over a bare ResponseBody cannot see that, and phase 4 would be the first to.
  test "a Response carrying the bounded error copy decodes, snapshots and closes" do
    copy = Dexpace::Body.buffer_bounded(
      response_body("héllo", media_type: media("text/plain; charset=utf-8")), cap: 64,
    )
    subject = response(copy)

    assert_equal("héllo", subject.body_string)
    assert_equal("héllo".b, response(copy).body_bytes)
    assert_nil(response(copy).close)
  end

  test "a Response carrying a response-logging wrapper decodes, snapshots and closes" do
    delegate = response_body("héllo", media_type: media("text/plain; charset=utf-8"))
    wrapper = Dexpace::ResponseLoggingBody.new(delegate, preview_bytes: 64)

    assert_equal("héllo", response(wrapper).body_string)
    assert_predicate(wrapper, :closed?)
  end

  # The default is a RAISE and not an absent method, so a request-body variant that reaches
  # Response#body fails by name rather than with a NoMethodError, and the sig/ declaration stays
  # true of every Dexpace::Body (P3-23).
  test "a request-body variant in Response#body fails by name rather than with a NoMethodError" do
    subject = response(Dexpace::Body.bytes("héllo"))
    error = assert_raises(Dexpace::StreamError) { subject.body_bytes }

    assert_includes(error.message, "Dexpace::BytesBody")
  end

  # ---- HTTP-41/BODY-16: the finally-style close on both readers ------------------------------

  test "body_bytes returns BINARY and decodes nothing" do
    subject = response(response_body("héllo", media_type: media("text/plain; charset=utf-8")))
    bytes = subject.body_bytes

    assert_equal(::Encoding::BINARY, bytes.encoding)
    assert_equal("héllo".b, bytes)
  end

  test "body_string closes the body" do
    body = response_body("héllo")
    response(body).body_string

    assert_predicate(body, :closed?)
  end

  test "body_bytes closes the body" do
    body = response_body("héllo")
    response(body).body_bytes

    assert_predicate(body, :closed?)
  end

  test "body_string closes the body even when the read fails" do
    body = response_body("héllo")
    body.source.close
    subject = response(body)

    assert_raises(Dexpace::ClosedError) { subject.body_string }
    assert_predicate(body, :closed?)
  end

  test "body_bytes closes the body even when the read fails" do
    body = response_body("héllo")
    body.source.close
    subject = response(body)

    assert_raises(Dexpace::ClosedError) { subject.body_bytes }
    assert_predicate(body, :closed?)
  end

  test "body_bytes on an exhausted body returns an empty BINARY String rather than nil" do
    body = response_body("")
    bytes = response(body).body_bytes

    assert_equal("".b, bytes)
    assert_equal(::Encoding::BINARY, bytes.encoding)
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

Expected: FAIL — `uninitialized constant Dexpace::ResponseBody`, then
`undefined method 'body_string' for an instance of Dexpace::Response`.

- [ ] **Step 3: Write `lib/dexpace/http/body/response_body.rb`**

`.new` is overridden to add the block form because `resource-management/bf5560dc` asks for a block
form on every closable resource and this is phase 3b's only closable factory; `super(..., &nil)`
keeps the block from reaching `#initialize`.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"
require_relative "../../closeable"
require_relative "../../io/buffered_source"

module Dexpace
  # HTTP-41/BODY-14's single-use response body: a handle over the Dexpace::IO::BufferedSource the
  # transport built with .wrapping, so closing this closes the transport stream (IO-6).
  #
  # #source returns THE SAME underlying handle every time and never a fresh replay -- that is
  # BODY-14 literally, and repeatable access is what Dexpace::ResponseLoggingBody and
  # Dexpace::Body.buffer_bounded exist for.
  class ResponseBody
    include Dexpace::Body
    include Dexpace::Closeable

    attr_reader :source, :media_type, :content_length

    # `resource-management/bf5560dc`'s block form, and this is phase 3b's only closable factory:
    # with a block the body is closed on ANY exit path and the block's value is returned; without
    # one the caller owns the close.
    def self.new(source:, media_type: nil, content_length: -1)
      body = super(source: source, media_type: media_type, content_length: content_length, &nil)
      return body unless block_given?

      begin
        yield body
      ensure
        body.close
      end
    end

    def initialize(source:, media_type: nil, content_length: -1)
      unless source.respond_to?(:read_into)
        raise Dexpace::InvalidArgumentError,
              "a response body's source must respond to #read_into, got #{source.class}"
      end
      unless content_length.is_a?(::Integer) && content_length >= -1
        raise Dexpace::InvalidArgumentError,
              "content_length must be an Integer of -1 or more, got #{content_length.inspect}"
      end

      @source = source
      @media_type = media_type
      @content_length = content_length
      initialize_closeable(owned: true)
      initialize_single_use
    end

    # BODY-33's non-consuming preview, and BODY-32's cap rules on top of it: a negative cap is
    # rejected, the cap is SILENTLY clamped down to Dexpace::IO::MAX_MATERIALIZED_BYTES and never
    # up, and whatever bytes are available up to the clamped cap come back without requiring that
    # exactly that many exist. Reads through a FRESH #peek view closed in an ensure, so the primary
    # read path does not move; empty when the source is exhausted. ("Null when there is no body" is
    # the caller's nil check on response.body, which is phase 4's call site.)
    #
    # The ceiling is read from the constant and takes NO keyword: a `ceiling:` keyword would let one
    # stream carry two ceilings, which is exactly what design §10.18's single substituted constant
    # exists to prevent. What BODY-32 parameterises is the CAP, which is a different thing.
    def preview(cap:)
      limit = Dexpace::Body.send(:clamp_cap, cap)
      view = @source.peek
      begin
        view.read(limit) || (+"").b
      ensure
        view.close
      end
    end

    # BODY-14: a response body is a reader. It writes once, and a second write raises rather than
    # silently emitting nothing -- offering an already-read response body as a request body without
    # materialising it is the failure BODY-14 describes.
    def write_to(sink)
      claim_single_use!
      return copy_exactly(@source, sink, @content_length) unless @content_length.negative?

      written = 0
      @source.each { |chunk| written += emit_exactly(sink, chunk) }
      written
    end

    # HTTP-46: identity. Two different live sources are two different values.
    def ==(other)
      equal?(other)
    end
    alias eql? ==

    def hash
      object_id.hash
    end

    private

    # BODY-15: releases the underlying transport resource, idempotent through Closeable's latch,
    # and makes no assumption that the body was read -- a caller that skips the body entirely still
    # relies on this to release the connection.
    def release
      @source.close if @source.respond_to?(:close)
      nil
    end
  end
end
```

- [ ] **Step 4: Add the three methods to `lib/dexpace/http/response.rb`**

Immediately after phase 1's six classification predicates and before `class Builder`:

```ruby
    # HTTP-43: closeable, idempotent, forwarding to the body. A pure forward and nothing else --
    # a Data instance is frozen and cannot hold a latch, which would matter if HTTP-43 needed one.
    # It does not: its own appendix-C text says "(Idempotency is delegated to the body's
    # idempotent close per HTTP-41; a bodyless response close is a no-op.)" So idempotence lives
    # in ResponseBody's Closeable latch, which is where HTTP-41 puts it.
    def close
      body&.close
      nil
    end

    # HTTP-42, and the ONE decode boundary in this SDK. Three steps, and all three are
    # load-bearing (OI-7, `docs/knowledge/notes/io-and-byte-streams.md`).
    #
    # 1. Resolve the charset from the body's media type. MediaType#charset already returns nil
    #    for an ABSENT or an UNKNOWN-to-this-Ruby charset, so Encoding.find cannot raise and
    #    HTTP-42's UTF-8 fallback needs no second validation.
    # 2. RETAG the drained BINARY bytes to that encoding, which is 3a's #read_string. Skipping
    #    this mangles the payload: from BINARY every byte >= 0x80 is undefined in the SOURCE
    #    encoding, so "café".b.encode(UTF_8, invalid: :replace, undef: :replace) is "caf" plus
    #    TWO replacement characters, on 3.2.11, 3.4.10 and 4.0.6 alike.
    # 3. Transcode with BOTH encodings named. #encode with no target converts to
    #    Encoding.default_internal, a process global the host sets -- the same
    #    passes-where-you-look hazard design §3.5 pins URI::RFC3986_PARSER against.
    #
    # BODY-16: the body is closed in an ensure whether or not the read succeeded.
    def body_string
      return nil if body.nil?

      encoding = self.class.resolve_charset(body.media_type)
      begin
        body.source
            .read_string(encoding)
            .encode(encoding, invalid: :replace, undef: :replace)
      ensure
        body.close
      end
    end

    # HTTP-41/BODY-16's byte-array sibling. It decodes NOTHING and returns BINARY; the same
    # finally-style close applies.
    def body_bytes
      return nil if body.nil?

      begin
        body.source.read || (+"").b
      ensure
        body.close
      end
    end

    def self.resolve_charset(media_type)
      name = media_type&.charset
      name.nil? ? ::Encoding::UTF_8 : ::Encoding.find(name)
    end
```

- [ ] **Step 5: Write `sig/dexpace/http/body/response_body.rbs` and extend the Response mirror**

```rbs
module Dexpace
  class ResponseBody
    include Dexpace::Body
    include Dexpace::Closeable

    attr_reader source: Dexpace::IO::BufferedSource
    attr_reader media_type: Dexpace::MediaType?
    attr_reader content_length: Integer

    def self.new: (source: Dexpace::IO::BufferedSource, ?media_type: Dexpace::MediaType?,
                   ?content_length: Integer) -> Dexpace::ResponseBody
                | [T] (source: Dexpace::IO::BufferedSource, ?media_type: Dexpace::MediaType?,
                       ?content_length: Integer) { (Dexpace::ResponseBody) -> T } -> T

    def initialize: (source: Dexpace::IO::BufferedSource, ?media_type: Dexpace::MediaType?,
                     ?content_length: Integer) -> void
    def preview: (cap: Integer | Float) -> String
    def write_to: (Dexpace::IO::_Sink sink) -> Integer
    def ==: (untyped) -> bool
    def eql?: (untyped) -> bool
    def hash: () -> Integer

    private

    def release: () -> nil
  end
end
```

Merged into `sig/dexpace/http/response.rbs`, quoted standalone here so the addition can be
validated on its own:

```rbs
# The three methods phase 3b adds to phase 1's Response, and the DEF-26 narrowing of #body. In the
# repository these are merged into sig/dexpace/http/response.rbs; they stand alone here so the
# addition can be validated on its own.
module Dexpace
  class Response
    def close: () -> nil
    def body_string: () -> String?
    def body_bytes: () -> String?
    def self.resolve_charset: (Dexpace::MediaType? media_type) -> Encoding
  end
end
```

- [ ] **Step 6: Add `require_relative "dexpace/http/body/response_body"` to `lib/dexpace.rb`**

- [ ] **Step 7: Run the tests to confirm they pass**

Expected: PASS — **19** and **23 tests**.

- [ ] **Step 8: Run the decode boundary red, under the recipe the design states**

This is the one guard in the sub-phase that must be *seen* to fail, because the bug it catches
looks correct in review and passes over ASCII-only fixtures. Two mutations, both measured:

| Reverted to | Result |
|---|---|
| `.read.encode(encoding, invalid: :replace, undef: :replace)` — the retag dropped, target kept | **8 failures of 23** |
| `.read_string(encoding).encode(invalid: :replace, undef: :replace)` — retag kept, target dropped | **2 failures of 23**, and they are exactly the two `default_internal` tests |

§3.1's recipe **literally** — `.read.encode(invalid: :replace, undef: :replace)`, with no target at
all — is not in the table on purpose: it leaves the resolved `encoding` unused, so `ruby -w` warns
at load and `NFR-6` fails the file before an assertion runs, and a mutation caught by a warning is
not evidence about a test. Row one drops the retag and keeps the target, which is the half of §3.1's
recipe that mangles the payload and the half a reviewer would not catch by reading.

The second row is the point: the target-less form is indistinguishable from the correct one on
every test that does not set `Encoding.default_internal`, which is why the hostile-global tests
exist and why they are not optional.

---

## Task 9: `Body.buffer_bounded` and `MAX_BUFFERED_ERROR_BODY_BYTES`

**Requirement IDs:** `BODY-30`/`HTTP-52`'s bounded replayable copy; `BODY-31` as a
**cross-reference** to phase 1's `Status#error?`; `BODY-32`'s cap rules applied a second time.
**Design:** R8 in full; addendum **B2**.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/http/body.rb`,
  `gems/dexpace-core/sig/dexpace/http/body.rbs`,
  `gems/dexpace-core/test/dexpace/http/body_test.rb` (append one section)

**Interfaces:**
- Consumes: Task 1's `clamp_cap`, `#each` and the contract's `#close`; Task 2's
  `Dexpace::BufferBody`; Task 8's `Dexpace::ResponseBody#close`.
- Produces: `Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES` and
  `Dexpace::Body.buffer_bounded(body, cap:) -> Dexpace::BufferBody`. **Phase 4's**
  `Recovery.buffer_error_body(response)` is the only caller, and it reads this constant rather
  than declaring a second — `RETRY-36` shares the same bound.

**A second task on `body.rb` because it needs Tasks 2 and 8 to exist**, and because a reviewer
could reject the bounded copy while approving the contract. The constant moves one layer down from
design §5.1's `Recovery.buffer_error_body`, which is addendum B2: §5.1's guarantee — one constant,
one shared bound across every error-body-buffering path — holds exactly, and only the file it
lives in changes, because phase 3 ships bodies before phase 4 ships the chain.

**`buffer_bounded` is deliberately status-blind, and that is `BODY-31`'s whole treatment here.**
It never reads a status, which is what makes "mapping applies only to 4xx/5xx" impossible to get
wrong from inside the body layer: the only thing that can classify is phase 4's step, and the only
predicate it may use is phase 1's `Status#error?`. "A response with no body MUST be returned
unchanged" is a statement about a **response** and is phase 4's too. Two tests assert the negative
mechanically, because "we did not write a status check" stops being true one refactor later.

- [ ] **Step 1: Write the failing tests**

Appended to `gems/dexpace-core/test/dexpace/http/body_test.rb`, immediately before the file's
final `end`:

```ruby
  # ---- buffer_bounded (BODY-30/HTTP-52, BODY-32) -------------------------------------------

  test "buffer_bounded returns a replayable buffer-backed body readable more than once" do
    copy = Dexpace::Body.buffer_bounded(FakeBody.new("hé", "llo"), cap: 64)
    first = Dexpace::IO::Buffer.new
    second = Dexpace::IO::Buffer.new
    copy.write_to(first)
    copy.write_to(second)

    assert_predicate(copy, :replayable?)
    assert_equal("héllo".b, first.snapshot)
    assert_equal("héllo".b, second.snapshot)
  end

  test "buffer_bounded closes the original inside the drain's scope" do
    delegate = FakeResponseBodyDouble.new
    Dexpace::Body.buffer_bounded(delegate, cap: 64)

    assert_equal(1, delegate.closes)
  end

  test "buffer_bounded still closes the original when the drain raises" do
    delegate = FakeResponseBodyDouble.new(error: Dexpace::StreamError.new("boom"))
    assert_raises(Dexpace::StreamError) { Dexpace::Body.buffer_bounded(delegate, cap: 64) }

    assert_equal(1, delegate.closes)
  end

  test "buffer_bounded carries the original body's media type onto the copy" do
    media = Dexpace::MediaType.parse("application/problem+json")
    copy = Dexpace::Body.buffer_bounded(FakeBody.new("a", media_type: media), cap: 8)

    assert_equal(media, copy.media_type)
  end

  test "buffer_bounded truncates markerlessly at the cap" do
    copy = Dexpace::Body.buffer_bounded(FakeBody.new("0123456789"), cap: 4)
    sink = Dexpace::IO::Buffer.new
    copy.write_to(sink)

    assert_equal("0123", sink.snapshot)
  end

  test "buffer_bounded rejects a negative cap and clamps a huge one to the ceiling" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Body.buffer_bounded(FakeBody.new("a"), cap: -1)
    end
    copy = Dexpace::Body.buffer_bounded(FakeBody.new("a"), cap: ::Float::INFINITY)

    assert_equal(1, copy.content_length)
  end

  test "a zero cap buffers nothing and still closes the original" do
    delegate = FakeResponseBodyDouble.new
    copy = Dexpace::Body.buffer_bounded(delegate, cap: 0)

    assert_equal(0, copy.content_length)
    assert_equal(1, delegate.closes)
  end

  # BODY-30's default is fixed by the requirement's own text, so it takes no keyword anywhere.
  test "MAX_BUFFERED_ERROR_BODY_BYTES is 1 MiB and is the default cap" do
    assert_equal(1024 * 1024, Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES)
  end

  # THE allocating test, and it runs on every matrix row on purpose: it is the only place the
  # 1 MiB bound is exercised for real, and "the bytes beyond the cap are not read" is a claim about
  # a body larger than the cap that no smaller fixture can make.
  test "buffer_bounded over a body larger than the cap stops reading rather than discarding" do
    oversized = OversizedBody.new(2 * Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES)

    copy = Dexpace::Body.buffer_bounded(oversized)

    assert_equal(Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES, copy.content_length)
    assert_operator(oversized.yielded_bytes, :<, oversized.total)
  end

  # BODY-31 is a CROSS-REFERENCE row: the predicate is phase 1's Status#error? and the step that
  # reads it is phase 4's. The body layer's whole contribution is this negative guarantee, and it is
  # asserted mechanically rather than described, because "we did not write a status check" is
  # exactly the kind of claim that stops being true one refactor later.
  test "buffer_bounded takes a body and a cap, and no status of any kind" do
    names = Dexpace::Body.method(:buffer_bounded).parameters.map(&:last)

    assert_equal(%i[body cap], names)
  end

  test "no executable line of the body module mentions a status" do
    code = File.readlines(body_source).reject { |line| line.strip.start_with?("#") }

    refute_match(/\bstatus\b/, code.join)
  end

  def body_source
    File.expand_path("../../../lib/dexpace/http/body.rb", __dir__)
  end

  # A minimal response-body-shaped delegate: enough of the surface buffer_bounded uses, and a
  # close counter.
  class FakeResponseBodyDouble
    include Dexpace::Body

    attr_reader :closes

    def initialize(error: nil)
      @error = error
      @closes = 0
    end

    def write_to(sink)
      raise @error unless @error.nil?

      sink.write("body".b)
    end

    def close
      @closes += 1
      nil
    end
  end

  # Yields 64 KiB at a time and counts what it actually produced, so "not read" is measurable.
  class OversizedBody
    include Dexpace::Body

    CHUNK = 64 * 1024

    attr_reader :total, :yielded_bytes

    def initialize(total)
      @total = total
      @yielded_bytes = 0
    end

    def content_length = @total

    def write_to(sink)
      block = ("x" * CHUNK).b.freeze
      (@total / CHUNK).times do
        @yielded_bytes += sink.write(block)
      end
      @yielded_bytes
    end
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

Expected: FAIL — `undefined method 'buffer_bounded' for module Dexpace::Body`; `body_test.rb`'s
other 21 tests still pass.

- [ ] **Step 3: Add the constant and the two class methods to `lib/dexpace/http/body.rb`**

Immediately after `private_class_method :clamp_cap` and before the `private` keyword:

```ruby
    # BODY-30/HTTP-52 fix this number in their own text ("a fixed cap (1 MiB)"), so there is nothing
    # to configure and it takes no keyword. Distinct from Dexpace::IO::MAX_MATERIALIZED_BYTES, which
    # bounds one contiguous String, and from the body-logging preview size, which IS a parameter
    # (DEF-34). Collapsing any two of the three breaks a requirement.
    MAX_BUFFERED_ERROR_BODY_BYTES = 1024 * 1024

    # ---- BODY-30/HTTP-52's bounded replayable copy -----------------------------------------

    # Drains at most `cap` bytes of `body` into a Dexpace::IO::Buffer, STOPS reading rather than
    # reading and discarding, and returns a replayable buffer-backed body that is readable
    # independently and repeatably after the transport connection is released.
    #
    # DELIBERATELY STATUS-BLIND. It never reads a status, which is what makes BODY-31 ("mapping
    # applies only to 4xx/5xx") impossible to get wrong from inside the body layer: the only thing
    # that can classify is phase 4's recovery step, and the only predicate it may use is phase 1's
    # Dexpace::Status#error?. "A response with no body is returned unchanged" is a statement about a
    # RESPONSE and is phase 4's too.
    #
    # BODY-30's close clause: the drain runs inside the original body's close-guaranteeing scope, so
    # a buffer-allocation failure still releases the connection.
    def self.buffer_bounded(body, cap: MAX_BUFFERED_ERROR_BODY_BYTES)
      limit = clamp_cap(cap)
      buffer = Dexpace::IO::Buffer.new
      begin
        copy_bounded(body, buffer, limit)
      ensure
        body.close
      end
      Dexpace::BufferBody.new(buffer, media_type: body.media_type)
    end

    # Truncation is MARKERLESS -- no ellipsis, no sentinel -- and the bytes beyond the cap are not
    # pulled from the body at all. #each with a break runs the body's own ensures (verified on
    # 3.2.11, 3.4.10 and 4.0.6), which is why the original's handles still close.
    def self.copy_bounded(body, buffer, limit)
      return nil if limit.zero?

      taken = 0
      body.each do |chunk|
        headroom = limit - taken
        piece = chunk.bytesize <= headroom ? chunk : chunk.byteslice(0, headroom)
        buffer.write(piece)
        taken += piece.bytesize
        break if taken >= limit
      end
      nil
    end

    private_class_method :copy_bounded

```

- [ ] **Step 4: Add the constant and `.buffer_bounded` to `sig/dexpace/http/body.rbs`**

Both are already in the signature Task 1 wrote; confirm the two lines are present rather than
adding them twice:

```rbs
    MAX_BUFFERED_ERROR_BODY_BYTES: Integer
    def self.buffer_bounded: (Dexpace::Body, ?cap: Integer | Float) -> Dexpace::BufferBody
```

- [ ] **Step 5: Run the tests to confirm they pass**

Expected: PASS — **32 tests** in `body_test.rb`. One of them allocates: `buffer_bounded` over a
2 MiB body, once per run per matrix row, and it is the only place the 1 MiB bound is exercised for
real. It is **not** dropped: "the bytes beyond the cap are not read" is a claim about a body
larger than the cap that no smaller fixture can make. The body it drains yields 64 KiB blocks
directly and never touches a `BufferedSource`, so it costs about 32 block writes and not 2 million
reads.

---

## Task 10: `Dexpace::RequestLoggingBody` and `FakeBody`

**Requirement IDs:** `BODY-17`, `BODY-18`, `BODY-19`, `BODY-20`, `BODY-21`, `BODY-37`, and
`BODY-34`'s parameter half; deviations **P3-18** and **P3-14**. **Design:** "The two logging
wrappers", first half; R5.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/body/request_logging_body.rb`,
  `gems/dexpace-core/sig/dexpace/http/body/request_logging_body.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/body/request_logging_body_test.rb`

**Interfaces:**
- Consumes: Task 1's `Dexpace::Body` and its `FakeBody`; 3a's
  `Dexpace::IO::TeeSink.new(primary:, tap_limit:)`, `#tap_snapshot`, `#tap_bytesize` and its
  raising `#buffer`; 3a's `FakeSink`.
- Produces: `Dexpace::RequestLoggingBody.new(delegate, tap_limit: ::Float::INFINITY)` with
  `#snapshot`, `#tap_bytesize`, `#delegate` and `#to_replayable`. **Phase 5's instrumentation
  layer constructs these.**

**Ninth, because it needs a body to delegate to and 3a's tee.** `FakeBody` is Task 1's — five of
`body_test.rb`'s own tests need it, so it cannot wait until here — and this is where its
`fail_after:` earns its place: it is the only deterministic route to `BODY-20`'s "the snapshot
returns the bytes mirrored up to the failure", since a real body either succeeds or fails at a byte
boundary a test cannot place.

**`BODY-18` is satisfied by construction, not by clearing.** A **fresh** `TeeSink` per write cannot
accumulate an earlier attempt's bytes, which is strictly stronger than clearing one — it also drops
the previous attempt's memory. That is why 3a's `TeeSink#clear_tap` has **no caller in core**, and
this plan deliberately writes none: `OI-8` names the window in which 3a's plan may drop the method
before either plan executes, and this task is the confirmation `OI-8` asks for.

**The wrapper calls neither `#close`, `#flush` nor `#emit` on the tee.** `IO-29` forwards all
three to the **primary**, and the primary is the transport's sink, which a body does not own
(`BODY-8`, §10.12). A recording sink measures that rather than describing it.

**The `tap_limit:` default is `::Float::INFINITY` and it is deliberately asymmetric with Task 11's
required `preview_bytes:`** (P3-18). `BODY-19` states this default in its own text — "The unbounded
default cap exists for direct wrapper use; the instrumentation layer always supplies a finite cap"
— and `BODY-22` names none. A reviewer who tidies the two into one breaks one requirement or the
other.

- [ ] **Step 1: Write the failing test**

`gems/dexpace-core/test/dexpace/http/body/request_logging_body_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/fake_body"
require_relative "../../../support/fake_sink"

# BODY-17, BODY-18, BODY-19, BODY-20, BODY-21, BODY-34, BODY-37.
class DexpaceRequestLoggingBodyTest < DexpaceTestCase
  def wrapper(delegate = FakeBody.new("hé", "llo"), **rest)
    Dexpace::RequestLoggingBody.new(delegate, **rest)
  end

  # ---- BODY-17: mirror while forwarding, consuming the upstream once ------------------------

  test "forwards every byte to the primary sink" do
    sink = FakeSink.new
    wrapper.write_to(sink)

    assert_equal("héllo".b, sink.written)
  end

  test "mirrors the exact bytes the delegate's single write produced" do
    subject = wrapper
    subject.write_to(FakeSink.new)

    assert_equal("héllo".b, subject.snapshot)
  end

  test "consumes the upstream exactly once, never twice" do
    delegate = FakeBody.new("hé", "llo")
    wrapper(delegate).write_to(FakeSink.new)

    assert_equal(1, delegate.writes)
  end

  test "the full untruncated payload reaches the primary whatever the tap cap is" do
    sink = FakeSink.new
    subject = wrapper(FakeBody.new("hé", "llo"), tap_limit: 2)
    subject.write_to(sink)

    assert_equal("héllo".b, sink.written)
    assert_equal("hé".b[0, 2], subject.snapshot)
  end

  # ---- BODY-19: the bounded tap, and its unbounded default ---------------------------------

  # BODY-19 states this default in its own text, and it is DELIBERATELY asymmetric with
  # ResponseLoggingBody's required preview_bytes: (P3-18). Unifying the two breaks a requirement.
  test "defaults its tap cap to unbounded, which BODY-19 states outright" do
    parameters = Dexpace::RequestLoggingBody.instance_method(:initialize).parameters

    assert_includes(parameters, [:key, :tap_limit])
    assert_equal("héllo".b, wrapper.tap { |w| w.write_to(FakeSink.new) }.snapshot)
  end

  test "stops copying into the tap once the cap is reached" do
    subject = wrapper(FakeBody.new("0123456789"), tap_limit: 4)
    subject.write_to(FakeSink.new)

    assert_equal(4, subject.tap_bytesize)
    assert_equal("0123".b, subject.snapshot)
  end

  test "a tap cap of zero mirrors nothing and still forwards everything" do
    sink = FakeSink.new
    subject = wrapper(FakeBody.new("héllo"), tap_limit: 0)
    subject.write_to(sink)

    assert_equal("héllo".b, sink.written)
    assert_equal("".b, subject.snapshot)
  end

  # ---- BODY-18: satisfied by construction, with a FRESH tee per write ------------------------

  # A fresh tee per write cannot accumulate an earlier attempt's bytes, which is strictly stronger
  # than clearing one -- it also drops the previous attempt's memory. It is why 3a's
  # TeeSink#clear_tap has no caller in core (OI-8).
  test "a retry against a replayable delegate does not accumulate the earlier attempt's bytes" do
    subject = wrapper(FakeBody.new("héllo", replayable: true))
    subject.write_to(FakeSink.new)
    subject.write_to(FakeSink.new)

    assert_equal("héllo".b, subject.snapshot)
  end

  test "builds a different tee for every write, so no state survives an attempt" do
    subject = wrapper(FakeBody.new("héllo", replayable: true))
    subject.write_to(FakeSink.new)
    first = subject.instance_variable_get(:@tee)
    subject.write_to(FakeSink.new)

    refute_same(first, subject.instance_variable_get(:@tee))
  end

  test "never calls close, flush or emit on the tee, because IO-29 forwards all three" do
    primary = RecordingSink.new
    wrapper.write_to(primary)

    assert_equal(0, primary.closes)
    assert_equal(0, primary.flushes)
    assert_equal(0, primary.emits)
  end

  # ---- BODY-20: the partial mirror -----------------------------------------------------------

  # FakeBody is the only deterministic route here: a real body either succeeds or fails at a byte
  # boundary the test cannot place.
  test "a write that fails partway still leaves the mirrored bytes in the snapshot" do
    subject = wrapper(FakeBody.new("hé", "llo", fail_after: 1))

    assert_raises(Dexpace::StreamError) { subject.write_to(FakeSink.new) }
    assert_equal("hé".b, subject.snapshot)
  end

  # IO-27's ordering is what makes this true: the tee mirrors BEFORE it forwards, so a
  # PRIMARY-side failure still leaves the failing chunk captured.
  test "a primary-side failure still leaves the failing chunk captured" do
    subject = wrapper(FakeBody.new("hé", "llo"))
    exploding = FakeSink.new("hé".bytesize, Dexpace::StreamError.new("the socket went away"))

    assert_raises(Dexpace::StreamError) { subject.write_to(exploding) }
    assert_equal("héllo".b, subject.snapshot)
  end

  test "the snapshot before any write is an empty BINARY String" do
    assert_equal("".b, wrapper.snapshot)
    assert_equal(::Encoding::BINARY, wrapper.snapshot.encoding)
  end

  # ---- BODY-21: replayability verbatim, and a wrapper around the replayable form -------------

  test "exposes the delegate's replayability verbatim" do
    refute_predicate(wrapper(FakeBody.new("a", replayable: false)), :replayable?)
    assert_predicate(wrapper(FakeBody.new("a", replayable: true)), :replayable?)
  end

  test "materialize-once returns a wrapper around the delegate's replayable form" do
    subject = wrapper(FakeBody.new("héllo"), tap_limit: 4)
    materialized = subject.to_replayable

    assert_instance_of(Dexpace::RequestLoggingBody, materialized)
    assert_predicate(materialized, :replayable?)
  end

  test "materialize-once preserves the tap cap, so a retry loop keeps capturing" do
    materialized = wrapper(FakeBody.new("0123456789"), tap_limit: 4).to_replayable
    materialized.write_to(FakeSink.new)

    assert_equal("0123".b, materialized.snapshot)
  end

  test "materialize-once returns self when the delegate is already replayable" do
    subject = wrapper(FakeBody.new("a", replayable: true))

    assert_same(subject, subject.to_replayable)
  end

  test "delegates the media type and the declared length" do
    media = Dexpace::MediaType.parse("text/plain")
    subject = wrapper(FakeBody.new("a", media_type: media, content_length: 1))

    assert_equal(media, subject.media_type)
    assert_equal(1, subject.content_length)
  end

  # ---- BODY-37: no writable-buffer handle ----------------------------------------------------

  # ONE mechanism, not two: the wrapper exposes no buffer accessor and TeeSink#buffer already
  # raises with the actionable message. Design §10.10 records the honest position -- the prohibition
  # cannot be language-enforced, instance_variable_get reaches anything -- and this claims no more.
  test "exposes no buffer handle of its own" do
    refute(wrapper.respond_to?(:buffer))
  end

  test "the tee's own buffer accessor fails loudly with an actionable message" do
    subject = wrapper
    subject.write_to(FakeSink.new)
    error = assert_raises(Dexpace::StreamError) { subject.instance_variable_get(:@tee).buffer }

    assert_includes(error.message, "IO-28")
  end

  # ---- construction and BODY-34's structural half --------------------------------------------

  test "rejects a delegate that cannot produce bytes" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::RequestLoggingBody.new(42) }

    assert_includes(error.message, "#write_to")
  end

  # BODY-34's enablement clause is satisfied STRUCTURALLY in phase 3b: nothing in core constructs a
  # logging wrapper, so the wrappers are off the path unless something builds one. Phase 5's
  # instrumentation layer is the thing that will (DEF-34).
  test "nothing in the core library constructs a logging wrapper" do
    root = File.expand_path("../../../../lib", __dir__)
    sources = Dir.glob("#{root}/**/*.rb").grep_v(/request_logging_body\.rb\z/)
    constructions = sources.select do |path|
      File.read(path).include?("RequestLoggingBody.new")
    end

    assert_empty(constructions)
  end

  test "compares by value over its delegate and its cap" do
    delegate = FakeBody.new("a")

    assert_equal(wrapper(delegate, tap_limit: 4), wrapper(delegate, tap_limit: 4))
    refute_equal(wrapper(delegate, tap_limit: 4), wrapper(delegate, tap_limit: 8))
  end

  # A #write sink that also answers #close, #flush and #emit, so "IO-29 forwards all three to the
  # primary and the wrapper therefore calls none of them" is measurable rather than described.
  class RecordingSink
    attr_reader :closes, :flushes, :emits, :written

    def initialize
      @closes = 0
      @flushes = 0
      @emits = 0
      @written = +"".b
    end

    def write(*strings)
      payload = strings.join.b
      @written << payload
      payload.bytesize
    end

    def close = @closes += 1
    def flush = @flushes += 1
    def emit = @emits += 1
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Expected: FAIL — `uninitialized constant Dexpace::RequestLoggingBody`.

- [ ] **Step 3: Write `lib/dexpace/http/body/request_logging_body.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"
require_relative "../../io/tee_sink"

module Dexpace
  # BODY-17..BODY-21 and BODY-37: the tee-on-write capture wrapper.
  #
  # Nothing in core constructs one of these. That is how BODY-34's enablement clause ("body
  # logging MUST be engaged only when body-level logging is enabled") is satisfied in phase 3b --
  # STRUCTURALLY, not by a flag: the wrapper is off the path unless something builds it, and the
  # only thing that will is phase 5's instrumentation layer (DEF-34).
  class RequestLoggingBody
    include Dexpace::Body

    # BODY-19 states this default in its own text: "The unbounded default cap exists for direct
    # wrapper use; the instrumentation layer always supplies a finite cap." 3a's TeeSink already
    # implements exactly that and this passes the value through.
    #
    # DELIBERATELY ASYMMETRIC with ResponseLoggingBody, which REQUIRES its cap (P3-18). Unifying the
    # two defaults breaks one requirement or the other.
    def initialize(delegate, tap_limit: ::Float::INFINITY)
      unless delegate.respond_to?(:write_to)
        raise Dexpace::InvalidArgumentError,
              "a request-logging wrapper takes a body responding to #write_to, " \
              "got #{delegate.class}"
      end

      @delegate = delegate
      @tap_limit = tap_limit
      @tee = nil
    end

    attr_reader :delegate

    def media_type
      @delegate.media_type
    end

    def content_length
      @delegate.content_length
    end

    # BODY-21: the delegate's replayability, VERBATIM.
    def replayable?
      @delegate.replayable?
    end

    # BODY-21: a wrapper around the delegate's replayable form, with the tap cap preserved, so a
    # retry loop keeps capturing bytes for every attempt. BODY-3's "return the same body unchanged
    # when already replayable" wins when it applies, which is the same object either requirement
    # would name.
    def to_replayable
      return self if replayable?

      self.class.new(@delegate.to_replayable, tap_limit: @tap_limit)
    end

    # BODY-17: the tee mirrors the exact bytes the delegate's single write produces while forwarding
    # those same bytes to `sink`, consuming the upstream exactly once, and the FULL untruncated
    # payload reaches `sink` whatever the cap (IO-25/IO-26).
    #
    # A FRESH tee per write, which is BODY-18 satisfied by construction and strictly stronger than
    # clearing one: it also drops the previous attempt's memory. It is why 3a's TeeSink#clear_tap
    # has no caller in core (OI-8).
    #
    # The wrapper never calls #close, #flush or #emit on the tee: IO-29 forwards all three to the
    # PRIMARY, and the primary is the transport's sink, which a body does not own (BODY-8, §10.12).
    def write_to(sink)
      tee = Dexpace::IO::TeeSink.new(primary: sink, tap_limit: @tap_limit)
      @tee = tee
      @delegate.write_to(tee)
    end

    # BODY-20: a write that failed partway still returns the bytes mirrored up to the failure,
    # because @tee is bound before the delegate runs and IO-27 makes the tee mirror BEFORE it
    # forwards. Empty BINARY before the first write.
    def snapshot
      @tee.nil? ? (+"").b : @tee.tap_snapshot
    end

    def tap_bytesize
      @tee.nil? ? 0 : @tee.tap_bytesize
    end

    # HTTP-46, and BODY-37's shape: a wrapper is equal to a wrapper over an equal delegate with the
    # same cap. The wrapper exposes no buffer handle of its own -- BODY-37 is IO-28 restated at this
    # layer and is ONE mechanism, not two; TeeSink#buffer already raises with the actionable
    # message, and design §10.10 records the honest position that the prohibition cannot be
    # language-enforced.
    def ==(other)
      other.is_a?(RequestLoggingBody) && other.delegate == @delegate &&
        other.tap_limit == @tap_limit
    end
    alias eql? ==

    def hash
      [self.class, @delegate, @tap_limit].hash
    end

    protected

    attr_reader :tap_limit
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/http/body/request_logging_body.rbs`**

```rbs
module Dexpace
  class RequestLoggingBody
    include Dexpace::Body

    attr_reader delegate: Dexpace::Body

    def initialize: (Dexpace::Body delegate, ?tap_limit: Integer | Float) -> void
    def media_type: () -> Dexpace::MediaType?
    def content_length: () -> Integer
    def replayable?: () -> bool
    def to_replayable: () -> Dexpace::Body
    def write_to: (Dexpace::IO::_Sink sink) -> Integer
    def snapshot: () -> String
    def tap_bytesize: () -> Integer
    def ==: (untyped) -> bool
    def eql?: (untyped) -> bool
    def hash: () -> Integer

    private

    attr_reader tap_limit: Integer | Float
  end
end
```

- [ ] **Step 5: Add the require to `lib/dexpace.rb`**

- [ ] **Step 6: Run the test to confirm it passes**

Expected: PASS — **23 tests**.

---

## Task 11: `Dexpace::ResponseLoggingBody` and `FakeResponseBody`

**Requirement IDs:** `BODY-22`–`BODY-29`, `BODY-34`'s parameter half, `IO-42` in both directions;
deviation **P3-18**. **Design:** "The two logging wrappers", second half; R10 in full.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/body/response_logging_body.rb`,
  `gems/dexpace-core/sig/dexpace/http/body/response_logging_body.rbs`,
  `gems/dexpace-core/test/support/fake_response_body.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/body/response_logging_body_test.rb`

**Interfaces:**
- Consumes: Task 8's `Dexpace::ResponseBody#source`; Task 2's `Dexpace::IO::Buffer` usage; 3a's
  `#peek`, `BufferedSource.wrapping`, `StreamError.zero_read`; phase 2's `Dexpace::Closeable` and
  **`Dexpace.close_quietly` — this is its first call site in the SDK**; 3a's `FakeSource`.
- Produces: `Dexpace::ResponseLoggingBody.new(delegate, preview_bytes:)` with `#source` —
  `Dexpace::Body`'s contract name for `BODY-23`/`BODY-24`'s regime accessor, `P3-23` — plus
  `#snapshot`, `#error`, `#content_length`, `#close` and `#closed?`; and `FakeResponseBody`.

**The largest single task in the sub-phase, and its two regimes are two halves of one object
rather than two tasks** — the close-once guard spans them, and splitting would put `BODY-27` in
neither half.

**`IO-42` governs surfaces, not objects, and this wrapper holds three with three different
answers.** The captured `Dexpace::IO::Buffer` is **exempt** and keeps answering after any close,
because it wraps no external stream — that is `BODY-28`, and 3a already expresses it as
`Buffer#reads_survive_close?`. The over-cap composite is **not exempt**: it holds the live
delegate, so a read after close raises `Dexpace::ClosedError`. And views derived from the buffer
are invalidated by the **buffer's** close, never by the wrapper's — which is why `#release` closes
the delegate and deliberately does **not** close the buffer. Three surfaces, three tests, and the
first two **fail in opposite directions**, because one "it still works after close" test would
pass over either error.

**The composite is `BufferedSource.wrapping` of a small private `#read`-shaped tail object**, and
that is `BODY-27`'s second close path made real. `BODY-27` names **two** paths — "the wrapper's own
close **and the one-shot tail stream's close** MUST route through a single shared close-once guard"
— and `.over` owns nothing, so the tail's `#close` would be a public, callable method that released
no transport resource: a clause naming two paths cannot be satisfied by making one of them inert.
The harm is concrete, because `BODY-24` hands the tail to a consumer **as the rest of the body**,
and closing what you were handed is the idiomatic release. `.wrapping` **owns** the tail (`IO-6`),
so `source.close → Tail#close → the wrapper's own Closeable latch`: one guard, both paths, either
order, and a delegate whose close raises is still marked closed. The wrapper's `#release` closes
the **delegate** and not the tail, so there is no cycle.

**Fits-cap and over-cap are told apart by reading one more byte** (plan decision 9). After taking
exactly `preview_bytes` the wrapper cannot know which regime it is in without asking; it asks with
`read_into(probe, count: 1)`. `#eof?` would have widened what a delegate's source must provide
beyond `Dexpace::IO::_Source`'s single `#read_into`. The byte is **kept and not captured**: it is
held aside and replayed by the composite between the prefix and the still-live tail, so nothing is
lost and the capture is still exactly `preview_bytes`. Writing it into the buffer instead would
make every over-cap snapshot `cap + 1` bytes long — and a cap of 0 capture one byte of a payload
the caller asked not to capture — which is `BODY-22`'s "buffering up to a configurable byte cap"
and `BODY-24`'s "MUST buffer only the prefix" both exceeded by one.

- [ ] **Step 1: Write `test/support/fake_response_body.rb`**

A delegate whose `#close` **raises**, which `BODY-27` and `BODY-28` both require and which no
`StringIO` will do. It is deliberately not a `Dexpace::ResponseBody`: the wrapper's contract on its
delegate is `#source`, `#content_length`, `#media_type` and `#close`, and this is exactly that.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A response-body delegate whose #close RAISES, which BODY-27 ("if the delegate's close throws it
# MUST still be marked closed") and BODY-28 ("a close failure after a successful full capture MUST
# NOT be reported as a drain error") both require and which no StringIO will do.
#
# It is deliberately NOT a Dexpace::ResponseBody: the wrapper's contract on its delegate is #source,
# #content_length, #media_type and #close, and this is exactly that and nothing more.
class FakeResponseBody
  attr_reader :source, :media_type, :content_length, :closes

  def initialize(source, media_type: nil, content_length: -1, close_error: nil)
    @source = source
    @media_type = media_type
    @content_length = content_length
    @close_error = close_error
    @closes = 0
  end

  def close
    @closes += 1
    raise @close_error unless @close_error.nil?

    nil
  end
end
```

- [ ] **Step 2: Write the failing test**

The interleaved-fibers test is the one a reader would otherwise write wrong, and it is written to
**terminate**. Fiber A suspends *inside* the drain with the state flipped to `:running` and the
mutex not held; fiber B then calls `#content_length`, which takes the same mutex briefly and
returns. Under a mutex held across the drain, B raises `ThreadError: deadlock; lock already owned
by another fiber belonging to the same thread` — measured, not assumed — so the test fails loudly
under exactly the bug it exists to catch. A fiber that *waited* would block the thread and hang,
which is why no test does that.

`gems/dexpace-core/test/dexpace/http/body/response_logging_body_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/fake_response_body"
require_relative "../../../support/fake_source"
require "stringio"

# BODY-22, BODY-23, BODY-24, BODY-25, BODY-26, BODY-27, BODY-28, BODY-29, BODY-34, IO-42.
class DexpaceResponseLoggingBodyTest < DexpaceTestCase
  def response_body(content = "héllo", **rest)
    Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes(content), **rest)
  end

  def wrapper(delegate = response_body, preview_bytes: 64)
    Dexpace::ResponseLoggingBody.new(delegate, preview_bytes: preview_bytes)
  end

  def read_all(source)
    out = +"".b
    source.each { |chunk| out << chunk }
    out
  end

  # ---- BODY-22: drain at most once, lazily, on first access --------------------------------

  test "does not touch the delegate until a first access" do
    delegate = response_body
    wrapper(delegate)

    assert_equal("héllo".b, read_all(delegate.source))
  end

  test "drains exactly once however many accessors are called" do
    delegate = CountingDelegate.new("héllo")
    subject = wrapper(delegate)
    subject.snapshot
    subject.source
    subject.error
    subject.snapshot

    assert_equal(1, delegate.drains)
  end

  test "a source, a snapshot and an error query each trigger the first drain" do
    %i[source snapshot error].each do |accessor|
      delegate = CountingDelegate.new("héllo")
      wrapper(delegate).public_send(accessor)

      assert_equal(1, delegate.drains, "#{accessor} did not trigger the drain")
    end
  end

  # ---- BODY-23: the fits-cap regime --------------------------------------------------------

  test "captures the whole body when it fits within the cap" do
    assert_equal("héllo".b, wrapper.snapshot)
  end

  test "closes the delegate as part of a successful full capture" do
    delegate = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("héllo"))
    wrapper(delegate).snapshot

    assert_equal(1, delegate.closes)
  end

  test "serves every read as a fresh non-consuming view, each succeeding independently" do
    subject = wrapper
    three = Array.new(3) { read_all(subject.source) }

    assert_equal(["héllo".b] * 3, three)
  end

  test "a body exactly the size of the cap is treated as fully captured" do
    subject = wrapper(response_body("abcdef"), preview_bytes: 6)

    assert_equal("abcdef".b, subject.snapshot)
    assert_equal(6, subject.content_length)
  end

  # ---- BODY-24: the over-cap regime --------------------------------------------------------

  test "buffers only the prefix and leaves the delegate open when the body exceeds the cap" do
    delegate = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("0123456789"))
    subject = wrapper(delegate, preview_bytes: 4)
    subject.snapshot

    assert_equal(0, delegate.closes)
    refute_predicate(subject, :closed?)
  end

  test "serves the next read as the prefix followed by the still-live tail, complete" do
    subject = wrapper(response_body("0123456789"), preview_bytes: 4)

    assert_equal("0123456789".b, read_all(subject.source))
  end

  test "a second read in the over-cap regime fails, because the tail is single-consumer" do
    subject = wrapper(response_body("0123456789"), preview_bytes: 4)
    subject.source
    error = assert_raises(Dexpace::StreamError) { subject.source }

    assert_includes(error.message, "BODY-24")
  end

  # ---- BODY-25: a zero read for a positive count ---------------------------------------------

  # No real Ruby stream returns 0 for a positive requested count, which is why FakeSource exists.
  test "a delegate read returning zero for a positive count is a contract violation, not EOF" do
    delegate = FakeResponseBody.new(FakeSource.new("ab", 0))
    subject = wrapper(delegate, preview_bytes: 64)

    assert_instance_of(Dexpace::StreamError, subject.error)
    assert_includes(subject.error.message, "IO-17")
  end

  test "the bytes read before a zero read are retained rather than discarded" do
    delegate = FakeResponseBody.new(FakeSource.new("ab", 0))

    assert_equal("ab".b, wrapper(delegate).snapshot)
  end

  # ---- BODY-26: a mid-drain failure, three behaviours over one cached value -------------------

  test "a read after a mid-drain failure re-raises the cached error on every call" do
    subject = wrapper(FakeResponseBody.new(FakeSource.new("ab", Dexpace::StreamError.new("boom"))))
    first = assert_raises(Dexpace::StreamError) { subject.source }
    second = assert_raises(Dexpace::StreamError) { subject.source }

    assert_same(first, second)
  end

  # A bare `raise` re-raises the SAME object with its #cause and its original backtrace intact,
  # verified on 3.2.11, 3.4.10 and 4.0.6 -- so no #exception dance and no backtrace juggling.
  test "the re-raised error keeps its cause and its original backtrace" do
    cause = ::RuntimeError.new("root cause")
    failure = begin
      begin
        raise cause
      rescue ::RuntimeError
        raise Dexpace::StreamError, "the drain failed"
      end
    rescue Dexpace::StreamError => error
      error
    end
    subject = wrapper(FakeResponseBody.new(FakeSource.new("ab", failure)))
    raised = assert_raises(Dexpace::StreamError) { subject.source }

    assert_same(failure, raised)
    assert_same(cause, raised.cause)
    assert_equal(failure.backtrace, raised.backtrace)
  end

  test "snapshot returns the partial bytes without raising after a mid-drain failure" do
    subject = wrapper(FakeResponseBody.new(FakeSource.new("ab", Dexpace::StreamError.new("boom"))))

    assert_equal("ab".b, subject.snapshot)
  end

  test "the error accessor surfaces the cached error without raising and without a second drain" do
    delegate = FakeResponseBody.new(FakeSource.new("ab", Dexpace::StreamError.new("boom")))
    subject = wrapper(delegate)

    assert_instance_of(Dexpace::StreamError, subject.error)
    assert_same(subject.error, subject.error)
  end

  test "the error accessor is nil after a clean drain" do
    assert_nil(wrapper.error)
  end

  # ---- BODY-27: one close-once guard --------------------------------------------------------

  test "closes the delegate at most once across every close path" do
    delegate = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("0123456789"))
    subject = wrapper(delegate, preview_bytes: 4)
    subject.source
    subject.close
    subject.close

    assert_equal(1, delegate.closes)
  end

  # BODY-27 names TWO close paths, and this is the second one. BODY-24 hands the tail to a
  # consumer as the rest of the body, so closing what you were handed is the idiomatic release; it
  # has to reach the same guard the wrapper's own close reaches, or BODY-15's release is lost one
  # layer up.
  test "closing the tail the consumer was handed closes the delegate, exactly once" do
    delegate = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("0123456789"))
    subject = wrapper(delegate, preview_bytes: 4)
    tail = subject.source
    tail.close

    assert_equal(1, delegate.closes)
    assert_predicate(subject, :closed?)

    tail.close
    subject.close

    assert_equal(1, delegate.closes)
  end

  test "a delegate whose close raises is still marked closed, and the failure propagates once" do
    delegate = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("0123456789"),
                                    close_error: ::IOError.new("already closed"),)
    subject = wrapper(delegate, preview_bytes: 4)

    assert_raises(::IOError) { subject.close }
    assert_predicate(subject, :closed?)
    assert_nil(subject.close)
    assert_equal(1, delegate.closes)
  end

  test "close from two threads closes the delegate once even when its close raises" do
    delegate = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("0123456789"),
                                    close_error: ::IOError.new("already closed"),)
    subject = wrapper(delegate, preview_bytes: 4)
    start = ::Thread::Queue.new
    outcomes = ::Thread::Queue.new
    threads = Array.new(4) do
      ::Thread.new do
        start.pop
        subject.close
        outcomes << :quiet
      rescue ::IOError
        outcomes << :raised
      end
    end
    4.times { start << :go }
    threads.each(&:join)
    results = Array.new(4) { outcomes.pop }

    assert_equal(1, results.count(:raised))
    assert_equal(1, delegate.closes)
    assert_predicate(subject, :closed?)
  end

  # ---- BODY-28 and IO-42, in the two directions that fail in opposite ways -------------------

  test "a close failure after a successful full capture is not reported as a drain error" do
    delegate = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("héllo"),
                                    close_error: ::IOError.new("already closed"),)
    subject = wrapper(delegate)

    assert_equal("héllo".b, subject.snapshot)
    assert_nil(subject.error)
  end

  test "a close failure after a successful capture does not stop the body being served" do
    delegate = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("héllo"),
                                    close_error: ::IOError.new("already closed"),)

    assert_equal("héllo".b, read_all(wrapper(delegate).source))
  end

  # IO-42's in-memory exemption. This test and the next fail in OPPOSITE directions, which is why
  # they are two tests: one "it still works after close" test would pass over either error.
  test "the captured buffer keeps answering after the wrapper's close" do
    subject = wrapper
    subject.snapshot
    subject.close

    assert_equal("héllo".b, subject.snapshot)
    assert_equal("héllo".b, read_all(subject.source))
  end

  # The rule with no external symptom TODAY and a severe one after one refactor, so it is pinned
  # directly: #release closes the delegate and deliberately does NOT close the captured buffer.
  # Closing it would invalidate every outstanding BODY-23 view for no gain and would put BODY-28's
  # post-mortem snapshot one reordering away from breaking.
  test "the wrapper's close closes the delegate and deliberately not the captured buffer" do
    fits = wrapper
    fits.snapshot
    fits.close

    over = wrapper(response_body("0123456789"), preview_bytes: 4)
    over.snapshot
    over.close

    refute_predicate(fits.instance_variable_get(:@buffer), :closed?)
    refute_predicate(over.instance_variable_get(:@buffer), :closed?)
  end

  # IO-42's third surface: views derived from the captured buffer are invalidated by the BUFFER's
  # close, never by the wrapper's. That is why #release closes the delegate and deliberately does
  # NOT close the buffer -- closing it would invalidate every outstanding BODY-23 view for no gain.
  test "a view taken from the captured buffer before the close still reads after it" do
    subject = wrapper
    view = subject.source
    subject.close

    assert_equal("héllo".b, read_all(view))
  end

  test "the over-cap tail raises ClosedError after the wrapper's close" do
    subject = wrapper(response_body("0123456789"), preview_bytes: 4)
    tail = subject.source
    subject.close

    assert_raises(Dexpace::ClosedError) { read_all(tail) }
  end

  # ---- BODY-29: the reported length ----------------------------------------------------------

  test "reports the captured size when the body was fully captured" do
    assert_equal(6, wrapper(response_body("héllo", content_length: 6)).tap(&:snapshot)
                      .content_length,)
  end

  test "reports the delegate's declared length when the capture is only a prefix" do
    subject = wrapper(response_body("0123456789", content_length: 10), preview_bytes: 4)
    subject.snapshot

    assert_equal(10, subject.content_length)
  end

  test "reports the delegate's declared length before any drain, and triggers none" do
    delegate = CountingDelegate.new("héllo", content_length: 6)
    subject = wrapper(delegate)

    assert_equal(6, subject.content_length)
    assert_equal(0, delegate.drains)
  end

  # ---- BODY-22's serialization ----------------------------------------------------------------

  test "concurrent first accesses drain the upstream exactly once" do
    delegate = CountingDelegate.new("0" * 512)
    subject = wrapper(delegate, preview_bytes: 512)
    start = ::Thread::Queue.new
    threads = Array.new(8) do
      ::Thread.new do
        start.pop
        subject.snapshot
      end
    end
    8.times { start << :go }
    threads.each(&:join)

    assert_equal(1, delegate.drains)
    assert_equal(512, subject.snapshot.bytesize)
  end

  # THE fiber proof, and it terminates. Fiber A suspends INSIDE the drain with the state flipped to
  # :running and the mutex NOT held; fiber B then calls #content_length, which takes the same mutex
  # briefly and returns. Under a mutex held across the drain, B raises "ThreadError: deadlock; lock
  # already owned by another fiber belonging to the same thread" -- verified -- so this fails loudly
  # under exactly the bug it exists to catch rather than restating the previous test.
  test "two fibers of one thread interleave the drain without a ThreadError" do
    delegate = FakeResponseBody.new(SuspendingSource.new("0123456789"), content_length: 10)
    subject = wrapper(delegate, preview_bytes: 64)
    drainer = ::Fiber.new { subject.snapshot }
    drainer.resume

    observed = ::Fiber.new { subject.content_length }.resume
    drainer.resume

    assert_equal(10, observed)
    assert_equal("0123456789".b, subject.snapshot)
  end

  # ---- construction and BODY-34's structural half ----------------------------------------------

  # BODY-22 names no default and an unbounded one would mean the over-cap regime never fires, so the
  # keyword is REQUIRED -- deliberately asymmetric with RequestLoggingBody (P3-18). Adding a default
  # in phase 5 widens the signature and cannot break NFR-4.
  test "requires its preview cap, because BODY-22 names no default" do
    assert_raises(::ArgumentError) { Dexpace::ResponseLoggingBody.new(response_body) }
    assert_includes(Dexpace::ResponseLoggingBody.instance_method(:initialize).parameters,
                    [:keyreq, :preview_bytes],)
  end

  test "rejects a negative cap and a delegate with no source" do
    assert_raises(Dexpace::InvalidArgumentError) { wrapper(response_body, preview_bytes: -1) }
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::ResponseLoggingBody.new(Object.new, preview_bytes: 4)
    end
  end

  test "a cap of zero captures nothing and serves the whole body from the tail" do
    subject = wrapper(response_body("héllo"), preview_bytes: 0)

    assert_equal("".b, subject.snapshot)
    assert_equal("héllo".b, read_all(subject.source))
  end

  # The regime probe reads one byte past the cap to tell BODY-23 from BODY-24. That byte is kept,
  # because the composite owes the consumer every byte -- but it is kept OUTSIDE the capture, or
  # BODY-22's "up to a configurable byte cap" is exceeded by one on every over-cap body.
  test "the over-cap capture is exactly the cap, and the probe byte is still served" do
    subject = wrapper(response_body("0123456789"), preview_bytes: 4)

    assert_equal("0123".b, subject.snapshot)
    assert_equal("0123456789".b, read_all(subject.source))
  end

  test "is a reader, so offering it as a request body fails loudly" do
    error = assert_raises(Dexpace::StreamError) { wrapper.write_to(Dexpace::IO::Buffer.new) }

    assert_includes(error.message, "#source")
  end

  test "nothing in the core library constructs a response-logging wrapper" do
    root = File.expand_path("../../../../lib", __dir__)
    constructions = Dir.glob("#{root}/**/*.rb").grep_v(/response_logging_body\.rb\z/).select do |p|
      File.read(p).include?("ResponseLoggingBody.new")
    end

    assert_empty(constructions)
  end

  # A delegate that counts how many times its source was drained, which is the only way to assert
  # "at most once" rather than "the answer looks right".
  class CountingDelegate
    attr_reader :drains, :media_type, :content_length

    def initialize(content, media_type: nil, content_length: -1)
      @content = content.b
      @media_type = media_type
      @content_length = content_length
      @drains = 0
      @source = nil
    end

    def source
      @drains += 1 if @source.nil?
      @source ||= Dexpace::IO::BufferedSource.of_bytes(@content)
    end

    def close = nil
  end

  # A source that suspends its fiber in the middle of the drain, which is what puts fiber A inside
  # the drain while fiber B runs.
  class SuspendingSource
    def initialize(content)
      @remaining = content.b
      @suspended = false
    end

    def read_into(dest, count:)
      return -1 if @remaining.empty?

      unless @suspended
        @suspended = true
        ::Fiber.yield
      end
      taken = [count, @remaining.bytesize].min
      dest << @remaining.byteslice(0, taken)
      @remaining = @remaining.byteslice(taken, @remaining.bytesize - taken)
      taken
    end
  end
end
```

- [ ] **Step 3: Run it to confirm it fails**

Expected: FAIL — `uninitialized constant Dexpace::ResponseLoggingBody`.

- [ ] **Step 4: Write `lib/dexpace/http/body/response_logging_body.rb`**

`Dexpace.close_quietly(self)` on the fits-cap path is `BODY-28`'s "best-effort" **and**
`BODY-27`'s close-once guard at once: it routes through this wrapper's own `#close`, so the latch
flips before `#release` runs and a delegate whose close raises is still marked closed, while the
failure is dropped rather than reported as a drain error. `DEF-27`'s condition is still unmet, so
the rescued error is still dropped; the row is strengthened, not met.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"
require_relative "../../closeable"
require_relative "../../io/buffer"
require_relative "../../io/buffered_source"

module Dexpace
  # BODY-22..BODY-29: the drain-once response capture wrapper, in two regimes behind one close-once
  # guard.
  #
  # IO-42 governs SURFACES, not objects, and this holds three of them with three different answers
  # (R10). The captured Dexpace::IO::Buffer is EXEMPT and keeps answering after any close, because
  # it wraps no external stream (BODY-28, and 3a expresses it as Buffer#reads_survive_close?). The
  # over-cap composite is NOT exempt: it holds the live delegate, so a read after close raises
  # Dexpace::ClosedError (BODY-24). And views derived from the buffer are invalidated by the
  # BUFFER's close, never by the wrapper's -- which is why #release closes the DELEGATE and
  # deliberately does not close the buffer.
  class ResponseLoggingBody
    include Dexpace::Body
    include Dexpace::Closeable

    # BODY-22 says "buffering up to a configurable byte cap" and names NO default, and an unbounded
    # default would mean BODY-24's over-cap regime never fires and a multi-gigabyte response is
    # fully buffered by the wrapper whose whole purpose is to bound it. Required, therefore --
    # deliberately asymmetric with RequestLoggingBody (P3-18). Adding a default in phase 5 widens
    # the signature and cannot break NFR-4 (DEF-28's precedent, DEF-34).
    def initialize(delegate, preview_bytes:)
      unless delegate.respond_to?(:source)
        raise Dexpace::InvalidArgumentError,
              "a response-logging wrapper takes a body responding to #source, " \
              "got #{delegate.class}"
      end
      unless preview_bytes.is_a?(::Integer) && !preview_bytes.negative?
        raise Dexpace::InvalidArgumentError,
              "preview_bytes must be a non-negative Integer, got #{preview_bytes.inspect}"
      end

      @delegate = delegate
      @preview_bytes = preview_bytes
      @buffer = Dexpace::IO::Buffer.new
      @pending = nil
      @state = :unstarted
      @error = nil
      @complete = false
      @tail_taken = false
      @mutex = ::Thread::Mutex.new
      @condition = ::Thread::ConditionVariable.new
      initialize_closeable(owned: true)
    end

    attr_reader :delegate, :preview_bytes

    # BODY-23/BODY-24's read surface, under Dexpace::Body's contract name (P3-23): it triggers the
    # drain on first access and then serves the regime the drain landed in, and it is what
    # Response#body_string and #body_bytes read through when a wrapper occupies Response#body.
    def source
      ensure_drained
      raise @error unless @error.nil?
      return @buffer.peek if @complete

      claim_tail!
      Dexpace::IO::BufferedSource.wrapping(Tail.new(self, @buffer, @pending, @delegate.source))
    end


    # BODY-26: the partial bytes, without raising, whatever happened during the drain. BINARY --
    # Response#body_string is the SDK's only decode boundary and this is not it.
    def snapshot
      ensure_drained
      @buffer.snapshot
    end

    # BODY-26's exception-query accessor: the cached error, or nil. It triggers the FIRST drain
    # (BODY-22 lists the exception query among the first-access triggers) and never a second one.
    def error
      ensure_drained
      @error
    end

    # BODY-29: the captured size ONLY when the capture was complete, otherwise the delegate's
    # declared length -- the true length, since the capture is a bounded prefix. It never triggers a
    # drain, which is also what makes the interleaved-fibers proof below terminate.
    def content_length
      captured = @mutex.synchronize { @complete ? @buffer.bytesize : nil }
      captured.nil? ? @delegate.content_length : captured
    end

    def media_type
      @delegate.media_type
    end

    # A response-logging wrapper is a reader, not a request body. Offering it as one would have to
    # choose between truncating at the cap and re-consuming the tail, and both are wrong.
    def write_to(_sink)
      raise Dexpace::StreamError,
            "#{self.class} is a response capture wrapper and produces no request body; use " \
            "#source"
    end

    def ==(other)
      equal?(other)
    end
    alias eql? ==

    def hash
      object_id.hash
    end

    private

    # BODY-24's composite: the captured prefix from a FRESH non-consuming #peek view, then the
    # regime probe's byte, then the still-live tail, so the consumer receives the complete body.
    #
    # It is #read(count)-shaped and handed to BufferedSource.WRAPPING, not .over, and that is
    # BODY-27's second close path made real. BODY-27 names two paths -- "the wrapper's own close
    # AND the one-shot tail stream's close MUST route through a single shared close-once guard" --
    # and .over owns nothing, so the tail's #close would be a public, callable method that
    # released no transport resource. BODY-24 hands this stream to a consumer AS THE REST OF THE
    # BODY; closing what you were handed is the idiomatic release, and under .over that close
    # would lose BODY-15's guarantee one layer up. .wrapping owns this object (IO-6), so
    # source.close -> Tail#close -> the wrapper's own Closeable latch: one guard, both paths,
    # either order, and a delegate whose close raises is still marked closed.
    #
    # The wrapper's #release closes the DELEGATE and not this object, so there is no cycle.
    class Tail
      def initialize(wrapper, buffer, pending, source)
        @wrapper = wrapper
        @view = buffer.peek
        @pending = pending
        @source = source
      end

      # BufferedSource.wrapping drives #read(count) and reads nil as end of stream; it never
      # receives "" from here, because "" latches exhaustion on that path (3a's fill_from_upstream)
      # and an empty prefix must not end the composite before the tail has been read.
      def read(count)
        if @wrapper.closed?
          raise Dexpace::ClosedError,
                "the over-cap tail of a #{@wrapper.class} cannot be read after the wrapper is " \
                "closed: it replays a captured prefix and then continues from the delegate, and " \
                "the delegate is gone (BODY-24, IO-42)"
        end

        prefix = @view.read(count)
        return prefix unless prefix.nil? || prefix.empty?
        return take_pending unless @pending.nil? || @pending.empty?

        @source.read(count)
      end

      # BODY-27's second path, and the reason this is .wrapping's upstream rather than .over's
      # body: it routes to the wrapper's own close-once guard, so a consumer that closes the
      # stream it was handed releases the connection exactly as one that closes the wrapper does,
      # and the two together are still one close.
      def close
        @view.close
        @wrapper.close
      end

      private

      def take_pending
        taken = @pending
        @pending = nil
        taken
      end
    end

    private_constant :Tail

    # BODY-24: "A second read in this regime MUST fail (the tail is single-consumer)."
    def claim_tail!
      taken = @mutex.synchronize do
        next true if @tail_taken

        @tail_taken = true
        false
      end
      return nil unless taken

      raise Dexpace::StreamError,
            "the over-cap tail of a #{self.class} is single-consumer and has already been taken " \
            "(BODY-24)"
    end

    # BODY-22: at most once, lazily, with concurrent first accesses serialized so the upstream is
    # read exactly once. The Thread::Mutex is held across the STATE FLIP and across nothing else --
    # never across the drain. Ruby's Mutex is per-fiber-owned and non-reentrant, so a mutex held
    # across the drain raises ThreadError for a second fiber of the same thread; that is what makes
    # the interleaved-fibers test a proof rather than a restatement.
    def ensure_drained
      mine = @mutex.synchronize do
        loop do
          case @state
          when :unstarted then @state = :running
                               break true
          when :running then @condition.wait(@mutex)
          else break false
          end
        end
      end
      return nil unless mine

      begin
        drain
      ensure
        @mutex.synchronize do
          @state = :done
          @condition.broadcast
        end
      end
      nil
    end

    def drain
      taken = fill_prefix
      @complete = probe_complete(taken)
      # BODY-28: on the fits-cap path the delegate close is BEST EFFORT. Dexpace.close_quietly's
      # first call site in this SDK (DEF-27's condition is still unmet, so the rescued error is
      # still dropped). It routes through this wrapper's own #close, so BODY-27's close-once guard
      # still owns the only close path, and a delegate whose close raises is still marked closed.
      Dexpace.close_quietly(self) if @complete
      nil
    rescue ::StandardError => error
      # BODY-26: retain the bytes read before the failure and cache the error.
      @error = error
      nil
    end

    def fill_prefix
      source = @delegate.source
      taken = 0
      while taken < @preview_bytes
        wanted = @preview_bytes - taken
        chunk = (+"").b
        got = source.read_into(chunk, count: wanted)
        break if got.negative?
        # BODY-25: zero bytes for a POSITIVE requested count is a stream-contract violation, never
        # end of stream. 3a's helper, so the message form cannot diverge from BODY-10's.
        raise Dexpace::StreamError.zero_read(requested: wanted) if got.zero?

        @buffer.write(chunk)
        taken += got
      end
      taken
    end

    # BODY-23 is "end-of-stream reached before the cap" and BODY-24 is "cap hit with bytes still
    # pending", so the two are told apart by ONE more byte. Reading it rather than peeking keeps the
    # delegate's source contract to #read_into alone, and the byte is kept: it joins the captured
    # prefix, so the composite still replays every byte the consumer is owed.
    def probe_complete(taken)
      return true if taken < @preview_bytes

      probe = (+"").b
      got = @delegate.source.read_into(probe, count: 1)
      return true if got.negative?

      # The byte is KEPT but it is NOT part of the capture. BODY-22 caps what the wrapper
      # buffers, so writing it into @buffer would make every over-cap snapshot cap+1 bytes long
      # -- and a cap of 0 capture one byte of a payload the caller asked not to capture. It is
      # replayed by the composite between the captured prefix and the still-live tail instead,
      # so the consumer still receives every byte the delegate had.
      @pending = probe
      false
    end

    # BODY-27: ONE close-once guard, Closeable's latch, shared by the wrapper's own close and by the
    # capture path's best-effort close. It closes the DELEGATE and deliberately NOT the captured
    # buffer: the buffer holds only memory, closing it would invalidate every outstanding BODY-23
    # view for no gain, and BODY-28 requires it to survive this close.
    def release
      @delegate.close if @delegate.respond_to?(:close)
      nil
    end
  end
end
```

- [ ] **Step 5: Write `sig/dexpace/http/body/response_logging_body.rbs`**

```rbs
module Dexpace
  class ResponseLoggingBody
    include Dexpace::Body
    include Dexpace::Closeable

    attr_reader delegate: untyped
    attr_reader preview_bytes: Integer

    def initialize: (untyped delegate, preview_bytes: Integer) -> void
    def source: () -> Dexpace::IO::BufferedSource
    def snapshot: () -> String
    def error: () -> StandardError?
    def content_length: () -> Integer
    def media_type: () -> Dexpace::MediaType?
    def write_to: (Dexpace::IO::_Sink sink) -> bot
    def ==: (untyped) -> bool
    def eql?: (untyped) -> bool
    def hash: () -> Integer

    private

    def claim_tail!: () -> nil
    def ensure_drained: () -> nil
    def drain: () -> nil
    def fill_prefix: () -> Integer
    def probe_complete: (Integer taken) -> bool
    def release: () -> nil
  end
end
```

- [ ] **Step 6: Add the require to `lib/dexpace.rb`**

- [ ] **Step 7: Run the test to confirm it passes**

Expected: PASS — **38 tests**.

---

## Task 12: `Dexpace::TypedResponse` and `Dexpace::_ResponseHandler`

**Requirement IDs:** `HTTP-44`'s memo, `HTTP-45`'s serialization; deviation **P3-14**.
**Design:** R7 in full; §7.3.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/typed_response.rb` and
  `gems/dexpace-core/sig/dexpace/http/typed_response.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/typed_response_test.rb`

**Interfaces:**
- Consumes: phase 1's `Dexpace::Response`; Task 8's `Dexpace::ResponseBody` for the
  does-not-consume assertions; the `Dexpace::_ResponseHandler` interface Task 1 wrote into
  `sig/dexpace/http/body.rbs`.
- Produces: `Dexpace::TypedResponse.new(response:, handler:)` with `#response`, `#status`,
  `#headers`, `#protocol`, `#reason`, `#request` and `#value`. **Phase 7 supplies a status-aware
  handler INTO this rather than replacing it.**

**Genuinely independent — it depends only on phase 1's `Response` — so it floats, and it is placed
after Task 8 so the "does not consume the body" assertions have a real body to be about.**

**The handler is any object responding to `#call(response)`, and it takes the whole response.**
Not the `SEAM-22` witness: a witness responds to `.dexpace_load(parsed, ctx)` and takes an
**already-parsed** value, so something must read the body, choose a codec and parse before it
runs — and `serde/4b78c08d` requires that something to be **status-aware**. `#call(body)` or
`#call(bytes)` would be narrower and would force phase 7 to *replace* this class. A lambda is the
test double, which is why no support class is needed. Phase 3b builds no witness, no codec and no
status-aware handler.

**The memo is an explicit state machine and never `@value ||=`.** A handler that legitimately
decodes to `nil` would be re-run on every access under `||=`, and the second run would read a
single-use body that is already gone. The test asserts that by **counting invocations**, not by
comparing a `nil` to a `nil`. A memoised failure is re-raised with a bare `raise`, which returns
the same object with its `#cause` and its original backtrace intact — verified on all three.

- [ ] **Step 1: Write the failing test**

`gems/dexpace-core/test/dexpace/http/typed_response_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# HTTP-44, HTTP-45.
class DexpaceTypedResponseTest < DexpaceTestCase
  # The handler contract is #call(response) and nothing more, so the failure a handler raises
  # is the handler's own class. Phase 3b defines no serde error and names none.
  class HandlerFailure < ::StandardError; end

  def response(body: nil, status: 200)
    request = Dexpace::Request.builder
    request.url = "https://example.test/"
    builder = Dexpace::Response.builder
    builder.request = request.build
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = Dexpace::Status.of(status)
    builder.reason = "Fine"
    builder.body = body
    builder.build
  end

  def response_body(content = "héllo")
    Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes(content))
  end

  def typed(handler, **rest)
    Dexpace::TypedResponse.new(response: response(**rest), handler: handler)
  end

  # ---- HTTP-44: the raw accessors, without consuming the body -------------------------------

  test "exposes status, headers, protocol, reason and request without running the handler" do
    calls = 0
    subject = typed(->(_response) { calls += 1 })

    assert_equal(Dexpace::Status.of(200), subject.status)
    assert_equal(Dexpace::Headers::EMPTY, subject.headers)
    assert_equal(Dexpace::Protocol::HTTP_1_1, subject.protocol)
    assert_equal("Fine", subject.reason)
    assert_equal("https://example.test/", subject.request.url.to_s)
    assert_equal(0, calls)
  end

  test "the raw accessors do not consume the body" do
    body = response_body
    subject = Dexpace::TypedResponse.new(response: response(body: body), handler: ->(_r) { nil })
    subject.status
    subject.headers
    sink = Dexpace::IO::Buffer.new
    body.write_to(sink)

    assert_equal("héllo".b, sink.snapshot)
  end

  # ---- HTTP-44: the memo -------------------------------------------------------------------

  test "runs the handler at most once and returns the same value on every access" do
    calls = 0
    subject = typed(lambda { |_response|
      calls += 1
      Object.new
    })
    first = subject.value

    assert_same(first, subject.value)
    assert_same(first, subject.value)
    assert_equal(1, calls)
  end

  # THE `@value ||=` bug: a handler that legitimately decodes to nil would be re-run on every
  # access, and the second run would read a single-use body that is already gone. Asserted by
  # COUNTING invocations rather than by comparing a nil to a nil.
  test "memoises a nil success, so a handler that decodes to nil still runs exactly once" do
    calls = 0
    subject = typed(lambda { |_response|
      calls += 1
      nil
    })

    assert_nil(subject.value)
    assert_nil(subject.value)
    assert_nil(subject.value)
    assert_equal(1, calls)
  end

  test "memoises a false success too" do
    calls = 0
    subject = typed(lambda { |_response|
      calls += 1
      false
    })

    assert_equal(false, subject.value)
    assert_equal(false, subject.value)
    assert_equal(1, calls)
  end

  test "memoises a raised failure and re-raises the same object every time" do
    calls = 0
    subject = typed(lambda { |_response|
      calls += 1
      raise HandlerFailure, "bad json"
    })
    first = assert_raises(HandlerFailure) { subject.value }
    second = assert_raises(HandlerFailure) { subject.value }

    assert_same(first, second)
    assert_equal(1, calls)
  end

  # A bare `raise` re-raises the SAME object with its #cause and original backtrace intact,
  # verified on 3.2.11, 3.4.10 and 4.0.6.
  test "the re-raised failure keeps its cause and its original backtrace" do
    subject = typed(lambda { |_response|
      begin
        raise ::RuntimeError, "root cause"
      rescue ::RuntimeError
        raise HandlerFailure, "decode failed"
      end
    })
    first = assert_raises(HandlerFailure) { subject.value }
    second = assert_raises(HandlerFailure) { subject.value }

    assert_equal("root cause", second.cause.message)
    assert_equal(first.backtrace, second.backtrace)
  end

  test "does not consume the body itself, leaving that to the handler" do
    body = response_body
    subject = Dexpace::TypedResponse.new(response: response(body: body), handler: ->(_r) { :ok })
    subject.value
    sink = Dexpace::IO::Buffer.new
    body.write_to(sink)

    assert_equal("héllo".b, sink.snapshot)
  end

  test "hands the whole response to the handler, which is what makes it status-aware" do
    seen = nil
    typed(->(r) { seen = r }, status: 503).value

    assert_equal(Dexpace::Status.of(503), seen.status)
  end

  # ---- HTTP-45: serialization ----------------------------------------------------------------

  test "concurrent first accesses run the handler exactly once and all get the same object" do
    calls = ::Thread::Mutex.new
    count = 0
    value = Object.new
    subject = typed(lambda { |_response|
      calls.synchronize { count += 1 }
      sleep(0.01)
      value
    })
    start = ::Thread::Queue.new
    results = ::Thread::Queue.new
    threads = Array.new(8) do
      ::Thread.new do
        start.pop
        results << subject.value
      end
    end
    8.times { start << :go }
    threads.each(&:join)
    collected = Array.new(8) { results.pop }

    assert_equal(1, count)
    assert_equal([value], collected.uniq)
  end

  test "concurrent first accesses to a failing handler all raise the same object" do
    count = ::Thread::Mutex.new
    calls = 0
    subject = typed(lambda { |_response|
      count.synchronize { calls += 1 }
      sleep(0.01)
      raise HandlerFailure, "bad json"
    })
    start = ::Thread::Queue.new
    results = ::Thread::Queue.new
    threads = Array.new(8) do
      ::Thread.new do
        start.pop
        subject.value
      rescue HandlerFailure => error
        results << error
      end
    end
    8.times { start << :go }
    threads.each(&:join)
    collected = Array.new(8) { results.pop }

    assert_equal(1, calls)
    assert_equal(1, collected.uniq.length)
  end

  # A fiber suspended INSIDE the parse must not block a second fiber reading a raw accessor. That
  # is HTTP-44's "without consuming the body" made mechanical: under an implementation that took
  # the lock in the raw accessors, the second fiber would raise "ThreadError: deadlock; lock already
  # owned by another fiber belonging to the same thread".
  test "a fiber suspended mid-parse does not block another fiber reading a raw accessor" do
    subject = typed(lambda { |_response|
      ::Fiber.yield
      :parsed
    })
    parser = ::Fiber.new { subject.value }
    parser.resume

    observed = ::Fiber.new { [subject.status, subject.reason] }.resume
    parser.resume

    assert_equal([Dexpace::Status.of(200), "Fine"], observed)
    assert_equal(:parsed, subject.value)
  end

  # HTTP-44's "WITHOUT consuming the body" made mechanical on the lock rather than on the body: a
  # raw accessor that took the parse lock would block for the whole parse. Joined with a timeout,
  # because the failure mode of that bug is a hang and a hang is worse than a failure in CI.
  test "the raw accessors answer while another thread holds the parse lock" do
    subject = typed(->(_response) { :parsed })
    held = ::Thread::Queue.new
    release = ::Thread::Queue.new
    holder = ::Thread.new do
      subject.instance_variable_get(:@mutex).synchronize do
        held << :held
        release.pop
      end
    end
    held.pop
    reader = ::Thread.new { [subject.status, subject.reason, subject.headers] }
    finished = reader.join(5)
    release << :go
    holder.join
    reader.join

    refute_nil(finished, "a raw accessor blocked on the parse lock")
    assert_equal([Dexpace::Status.of(200), "Fine", Dexpace::Headers::EMPTY], reader.value)
  end

  test "two fibers of one thread reach the memo without a recursive-lock ThreadError" do
    calls = 0
    subject = typed(lambda { |_response|
      calls += 1
      :parsed
    })
    first = ::Fiber.new { subject.value }.resume
    second = ::Fiber.new { subject.value }.resume

    assert_equal(:parsed, first)
    assert_equal(:parsed, second)
    assert_equal(1, calls)
  end

  # ---- construction --------------------------------------------------------------------------

  # A lambda IS the handler contract, which is why the test double is one line and needs no support
  # class. Phase 7 supplies a status-aware handler INTO this rather than replacing it.
  test "accepts any object responding to call, and a lambda is one" do
    callable = Class.new { def call(_response) = :ok }.new

    assert_equal(:ok, typed(callable).value)
    assert_equal(:ok, typed(->(_r) { :ok }).value)
  end

  test "rejects a handler that does not respond to call" do
    error = assert_raises(Dexpace::InvalidArgumentError) { typed(Object.new) }

    assert_includes(error.message, "#call(response)")
  end

  test "rejects anything that is not a Dexpace::Response" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::TypedResponse.new(response: :not_a_response, handler: ->(_r) { :ok })
    end

    assert_includes(error.message, "Dexpace::Response")
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Expected: FAIL — `uninitialized constant Dexpace::TypedResponse`.

- [ ] **Step 3: Write `lib/dexpace/http/typed_response.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "response"
require_relative "../error/invalid_argument_error"

module Dexpace
  # HTTP-44 and HTTP-45's lazy typed-response wrapper. Design §7.3 names it flat.
  #
  # The handler is ANY object responding to #call(response) -- Dexpace::_ResponseHandler in sig/, a
  # lambda in a test. Not the SEAM-22 witness: a witness responds to .dexpace_load(parsed, ctx) and
  # takes an ALREADY-PARSED value, so something must read the body, choose a codec and parse before
  # it runs, and `serde/4b78c08d` requires that something to be STATUS-AWARE. So the handler needs
  # the whole response, and the witness sits inside it -- which is what lets phase 7 supply a
  # handler INTO this rather than replace it. Phase 3b builds no witness, no codec and no
  # status-aware handler.
  class TypedResponse
    def initialize(response:, handler:)
      unless response.is_a?(Dexpace::Response)
        raise Dexpace::InvalidArgumentError,
              "response must be a Dexpace::Response, got #{response.class}"
      end
      unless handler.respond_to?(:call)
        raise Dexpace::InvalidArgumentError,
              "handler must respond to #call(response), got #{handler.class}"
      end

      @response = response
      @handler = handler
      @state = :unstarted
      @value = nil
      @error = nil
      @mutex = ::Thread::Mutex.new
      @condition = ::Thread::ConditionVariable.new
    end

    attr_reader :response

    # HTTP-44's raw accessors: status, headers, protocol, reason and request WITHOUT consuming the
    # body. They take no lock, which is not an optimisation -- a lock here would block a caller
    # reading a status while another fiber of the same thread sits inside the parse.
    def status = @response.status
    def headers = @response.headers
    def protocol = @response.protocol
    def reason = @response.reason
    def request = @response.request

    # HTTP-44: parse at most once on first access and memoise the OUTCOME. The state machine is
    # explicit -- :unstarted, :running, :done, :failed -- and never inferred from @value being
    # nil, because `@value ||= handler.call(response)` re-runs the handler for one that legitimately
    # decodes to nil, and the second run reads a single-use body that is already gone. Both a nil
    # success and a raised failure are memoised.
    #
    # A memoised failure is re-raised with a bare `raise`, which returns THE SAME OBJECT with its
    # #cause and its original backtrace intact (verified on 3.2.11, 3.4.10 and 4.0.6) -- no
    # #exception dance and no backtrace juggling.
    #
    # HTTP-45: the mutex is held across the state flip and across NOTHING else, never across the
    # parse, with a caller arriving mid-parse waiting on a Thread::ConditionVariable over the same
    # mutex. Ruby's Mutex and ConditionVariable both defer to an INSTALLED Fiber scheduler, which
    # is HTTP-45's "does not pin the carrier thread" in Ruby's vocabulary -- and the qualifier is
    # load-bearing (P3-27). With no scheduler installed, which is the default, a second FIBER of
    # the same thread arriving mid-parse blocks the carrier thread inside #wait; if the parsing
    # fiber is never resumed the process aborts with "No live threads left. Deadlock?". Verified on
    # 3.2.11, 3.4.10 and 4.0.6. Two threads are unaffected, and so is a second fiber arriving after
    # the parse has settled -- both are tested. It is the same shape as the three unsatisfied MUSTs
    # design §10.5 splits, and it is recorded rather than papered over.
    def value
      run_handler if claim_parse
      settled = @mutex.synchronize { [@state, @value, @error] }
      raise settled[2] if settled[0] == :failed

      settled[1]
    end

    private

    def claim_parse
      @mutex.synchronize do
        loop do
          case @state
          when :unstarted then @state = :running
                               break true
          when :running then @condition.wait(@mutex)
          else break false
          end
        end
      end
    end

    def run_handler
      settle(:done, @handler.call(@response), nil)
    rescue ::StandardError => error
      settle(:failed, nil, error)
    ensure
      # A handler that raises OUTSIDE StandardError -- NoMemoryError, a SignalException, a
      # ScriptError out of a broken handler -- unwinds past the rescue above. Without this the
      # state stays :running and every other caller waits on the condition variable for the life
      # of the process, which is the one failure mode worse than a raised error. Task 11's
      # #ensure_drained flips its state in an ensure for the same reason. #settle is a no-op once
      # the state has moved, so the happy path pays one uncontended lock.
      settle(:failed, nil, $!)
    end

    def settle(state, value, error)
      @mutex.synchronize do
        next if @state != :running

        @value = value
        @error = error
        @state = state
        @condition.broadcast
      end
      nil
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/http/typed_response.rbs`**

The `Dexpace::_ResponseHandler` interface it names was written in Task 1's signature file for the
body module; confirm it is there rather than declaring it twice.

`gems/dexpace-core/sig/dexpace/http/typed_response.rbs`:

```rbs
module Dexpace
  class TypedResponse
    attr_reader response: Dexpace::Response

    def initialize: (response: Dexpace::Response, handler: Dexpace::_ResponseHandler) -> void
    def status: () -> Dexpace::Status
    def headers: () -> Dexpace::Headers
    def protocol: () -> Dexpace::Protocol
    def reason: () -> String?
    def request: () -> Dexpace::Request
    def value: () -> untyped

    private

    def claim_parse: () -> bool
    def run_handler: () -> nil
  end
end
```

- [ ] **Step 5: Add `require_relative "dexpace/http/typed_response"` to `lib/dexpace.rb`**

- [ ] **Step 6: Run the test to confirm it passes**

Expected: PASS — **17 tests**.

---

## Task 13: `OI-4`'s measurement on the `BODY-23` drain

**Requirement IDs:** none directly. It discharges the measurement `OI-4` asks for and records the
number in that item's Resolution field. **Design:** "Open questions for 3b's own plan", item 2;
§7.1 applied, point 4.

**Files:**
- Create: `tools/measure_view_retention.rb` (repository root, not inside a gem)
- Modify: `docs/open-items.md` — `OI-4`'s **Resolution** field only

**Interfaces:**
- Consumes: Task 11's `Dexpace::ResponseLoggingBody`; Task 8's `Dexpace::ResponseBody`.
- Produces: nothing in `lib/`, `sig/` or `test/`. **It changes nothing in phase 3a's view
  registry**, which is exactly what `OI-4` asks: "the right first move is a measurement, on phase
  3b's actual drain, not a redesign here".

**Why it is a task and not a note: the number is the deliverable.** `OI-4` was filed by 3a against
this drain by name — "the first place that bound stops being obvious is phase 3b, whose
`BODY-22`–`BODY-29` response-logging drain takes a view **per attempt on a retried request**" —
and an open item resolved by an opinion is not resolved.

It lives in `tools/` and **not** in `test/`, deliberately: a timing measurement inside a suite
becomes a test that fails on a loaded CI machine, and phase 0's gate set has no place for one.

- [ ] **Step 1: Write `tools/measure_view_retention.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# OI-4's measurement, not a test: it prints numbers and asserts nothing, because OI-4 asks for a
# measurement on phase 3b's actual BODY-23 drain rather than a redesign of phase 3a's view registry.
# Run it by hand, record the table in OI-4's Resolution field, and delete nothing from 3a.
#
#   bundle exec ruby -Igems/dexpace-core/lib tools/measure_view_retention.rb
#
# It lives in tools/ and not in test/, so it never runs in CI and never becomes a timing-sensitive
# test that fails on a loaded machine.

require "benchmark"
require "dexpace"

def wrapper(bytes)
  delegate = Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes(bytes))
  Dexpace::ResponseLoggingBody.new(delegate, preview_bytes: 64 * 1024)
end

def registry(wrapper)
  wrapper.instance_variable_get(:@buffer).instance_variable_get(:@dexpace_views)
end

puts "reads  registered  bytes_retained  read_s   close_all_s"
[1, 10, 100, 1_000, 10_000].each do |reads|
  subject = wrapper("x" * 4096)
  subject.snapshot
  views = nil
  taking = Benchmark.realtime { views = Array.new(reads) { subject.read } }
  registered = registry(subject).length
  retained = views.sum { |view| view.instance_variable_get(:@dexpace_buffered) }
  closing = Benchmark.realtime { views.each(&:close) }
  puts format("%6d %10d %15d %8.4f %12.4f", reads, registered, retained, taking, closing)
end

puts
puts "closing in REVERSE order (Array#delete scans from the front):"
[1_000, 10_000].each do |reads|
  subject = wrapper("x" * 4096)
  subject.snapshot
  views = Array.new(reads) { subject.read }
  elapsed = Benchmark.realtime { views.reverse_each(&:close) }
  puts format("%6d reverse close: %.4f s", reads, elapsed)
end

puts
subject = wrapper("x" * 4096)
subject.snapshot
before = GC.stat(:total_allocated_objects)
2_000.times { subject.read }
after = GC.stat(:total_allocated_objects)
puts format("2000 reads allocated %d objects (%.1f per view)", after - before,
            (after - before) / 2000.0,)
```

- [ ] **Step 2: Run it on all three interpreters**

```bash
for v in 3.2.11 3.4.10 4.0.6; do
  mise exec ruby@$v -- ruby -w -Igems/dexpace-core/lib tools/measure_view_retention.rb
done
```

Measured 2026-09-08 on 3.2.11 / 3.4.10 / 4.0.6:

| Live views on one captured buffer | Registered | Bytes retained | Close all |
|---|---|---|---|
| 1 | 1 | 0 | 0.0000 s |
| 10 | 10 | 0 | 0.0000 s |
| 100 | 100 | 0 | 0.0001 s |
| 1 000 | 1 000 | 0 | 0.0045 / 0.0046 / 0.0051 s |
| 10 000 | 10 000 | 0 | 0.4556 / 0.4830 / 0.5210 s |

Reverse-order close at 10 000: 0.2373 / 0.2684 / 0.3216 s. Per-view allocation: **9 objects** on
3.2.11 and 3.4.10, **10** on 4.0.6.

- [ ] **Step 3: Write the finding into `OI-4`'s Resolution field**

The three sentences the item needs, and no more — `OI-4` stays **open** as a documented, measured,
accepted cost rather than being closed by a phase that did not change the mechanism:

> **Measured (2026-09-08, phase 3b plan, `tools/measure_view_retention.rb`).** Exactly one view is
> registered per `BODY-23` read and stays registered until the caller closes it; a view holds zero
> bytes until it is read and costs 9 allocated objects (10 on 4.0.6). Deregistration is quadratic
> in the number of live views — 1 000 views close in 0.005 s and 10 000 in 0.46–0.52 s, with
> reverse order roughly halving it — so the `Array` costs nothing up to about **1 000
> simultaneously-live, unclosed views on one buffer** and becomes measurable above it. Nothing in
> `BODY-22`–`BODY-29` produces that shape: a fits-cap capture is read once and occasionally a
> handful of times, and phase 6's retry loop builds a **new** wrapper per attempt rather than
> taking another view on the old one. The `Hash`-keyed-by-`object_id` alternative stays available
> and unneeded; the item stays open against the first caller that exceeds the bound.

- [ ] **Step 4: Confirm nothing under `docs/knowledge/harvested/` or phase 3a changed**

Run: `ruby scripts/verify_knowledge_structure.rb` and `git status --short`
Expected: exit 0, and the only changed files are `tools/measure_view_retention.rb` and
`docs/open-items.md`.

---

## Task 14: Wiring, `DEF-26`'s narrowing, the two regenerated artifacts, and the checklist

**Requirement IDs:** `HTTP-46` as a **cross-reference** row — the ID is phase 1's, and the body half
of its by-value equality was untestable there because no body type existed; `NFR-3`, `NFR-4`,
`NFR-11`; `DEF-26`, **picked up**. Deviations **P3-14**, **P3-15**, **P3-22**.
**Design:** "The three additions to phase-1 types", third row; R6's constant table.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace.rb`, `gems/dexpace-core/sig/dexpace/http/request.rbs`,
  `gems/dexpace-core/sig/dexpace/http/response.rbs`,
  `gems/dexpace-core/test/dexpace/http/request_test.rb` (append two tests),
  repository-root `test/fixtures/surface/dexpace-core.txt`
- Create: `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-checklist.md`
- Modify: `docs/deferred-items.md` — `DEF-3` amended, `DEF-26` marked picked up

**Interfaces:**
- Consumes: every constant Tasks 1–12 produced.
- Produces: a `dexpace-core` whose `lib/dexpace.rb` requires the whole tree explicitly, a `sig/` in
  which `Request#body` and `Response#body` are `Dexpace::Body?`, a regenerated runtime surface
  manifest, and the phase's checklist.

**Last, and it regenerates the two artifacts exactly once, deliberately.** 3b adds more public
constants than any phase so far, which is why R6 names every one on purpose and P3-14 gives them a
ledger row: a name arriving by accident is `NFR-4`-locked by accident at the first release tag.

- [ ] **Step 1: Verify `lib/dexpace.rb`'s require order**

Each task added its own line; this step checks the whole block reads in dependency order and that
nothing is missing. The twelve lines phase 3b adds, after phase 1's `http/response` and 3a's
`io/tee_sink`:

```ruby
require_relative "dexpace/http/body"
require_relative "dexpace/http/body/bytes_body"
require_relative "dexpace/http/body/buffer_body"
require_relative "dexpace/http/body/file_body"
require_relative "dexpace/http/body/stream_body"
require_relative "dexpace/http/body/chunked_body"
require_relative "dexpace/http/body/form_body"
require_relative "dexpace/http/body/multipart_body"
require_relative "dexpace/http/body/response_body"
require_relative "dexpace/http/body/request_logging_body"
require_relative "dexpace/http/body/response_logging_body"
require_relative "dexpace/http/typed_response"
```

`lib/dexpace.rb` issues explicit `require`s for the whole tree rather than using an autoloader,
because every autoloader worth using is a gem — which is also what makes the require audit a text
scan rather than a runtime trace.

- [ ] **Step 2: Run the require-allowlist and gemspec audits**

Run: `bundle exec rake gates:require_allowlist gates:gemspec_audit`
Expected: clean. Phase 3b adds exactly one `require` — `securerandom` in `multipart_body.rb`, on
phase 0's twelve-name list — and zero `add_dependency` lines.

- [ ] **Step 3: Narrow `Request#body` and `Response#body` in `sig/` — `DEF-26`, picked up**

`DEF-26`'s pick-up condition named phase 3 explicitly, and 3b is where a body type exists to narrow
to. In `sig/dexpace/http/request.rbs` and `sig/dexpace/http/response.rbs`:

```rbs
    attr_reader body: Dexpace::Body?
```

The type is the **production contract** — `HTTP-36`'s "a thing with a single write-to-sink
operation, a media type, a length and a replayability property" — and **not** §10.2's `#each` duck
type, which is what a body *yields*. 3a named its interface `_Chunked` and not `_Body` for exactly
this reason (P3-15). RBS reads a module used as a type as "an instance of a class that includes it",
so every variant type-checks and Steep sees all eleven.

**No coercion is added at `Request::Builder`.** `#body=` continues to accept and store whatever it
is given; it does not turn a `String` into a `BytesBody`. Coercion would put a second
replayability-classification site next to `HTTP-38`'s one. `DEF-23` records that no Steep target
covers a test tree, so phase 1's suites are unaffected by the narrowing.

- [ ] **Step 4: Append `HTTP-46`'s body-half tests to `test/dexpace/http/request_test.rb`**

The ID stays phase 1's. Its design overrides `#==`/`#hash` on `Request` to compare
"`URL.external_form(url)` plus method, headers and body by value", and the body half was untestable
there. Dropping the row would leave a requirement whose obligation this phase discharges with no row
in the phase that discharges it — the same treatment phase 2 gave `SEAM-29`.

```ruby
  # HTTP-46's body half, untestable in phase 1 because no body type existed. Phase 3b supplies the
  # type; the ID stays phase 1's and this is its cross-reference row.
  test "compares its body by value, so two requests over equal bodies are equal" do
    first = Dexpace::Request.build(method: Dexpace::Method::POST, url: "https://example.test/",
                                   body: Dexpace::Body.bytes("héllo"),)
    same = Dexpace::Request.build(method: Dexpace::Method::POST, url: "https://example.test/",
                                  body: Dexpace::Body.bytes("héllo"),)
    other = Dexpace::Request.build(method: Dexpace::Method::POST, url: "https://example.test/",
                                   body: Dexpace::Body.bytes("wörld"),)

    assert_equal(first, same)
    assert_equal(first.hash, same.hash)
    refute_equal(first, other)
  end

  test "a request carrying a body works as a Hash key, which needs eql? and hash together" do
    key = Dexpace::Request.build(method: Dexpace::Method::POST, url: "https://example.test/",
                                 body: Dexpace::Body.bytes("héllo"),)
    twin = Dexpace::Request.build(method: Dexpace::Method::POST, url: "https://example.test/",
                                  body: Dexpace::Body.bytes("héllo"),)

    assert_equal(:found, { key => :found }[twin])
  end
```

- [ ] **Step 5: Regenerate the runtime surface snapshot**

Run: `bundle exec rake surface:regenerate` then `git diff test/fixtures/surface/dexpace-core.txt`
Expected: **additions only**. **Thirteen** constant rows — the design's R6 table counts twelve
because it folds `MultipartBody::Part` into `MultipartBody`, and the walk sees a nested constant as
its own row: `Dexpace::Body`, `BytesBody`, `BufferBody`, `FileBody`, `StreamBody`, `ChunkedBody`,
`FormBody`, `MultipartBody`, `MultipartBody::Part`, `ResponseBody`, `RequestLoggingBody`,
`ResponseLoggingBody`, `TypedResponse` — plus `Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES`,
`FormBody::MEDIA_TYPE`, `MultipartBody::BOUNDARY_CHARS`/`BOUNDARY_LENGTH`/`CRLF`/`DASHES`, and
three methods on `Response`. `PercentEncoding::FORM_UNRESERVED` is **not** among them: it is
`private_constant` (Task 3), so the walk never sees it and it is not `NFR-4`-locked.
**Nothing may disappear.**

`Dexpace::Body::BlockSink`, `CountingSink`, `ResponseLoggingBody::Tail`,
`PercentEncoding::FORM_UNRESERVED` and 3a's `BufferedSource::View` are `private_constant` and the
walk does not see them, which is the point of making them private. `Dexpace::Body` itself is **not** `private_constant`, for `TypedReads`' reason
(P3-8): the walk uses `public_instance_methods(false)`, which cannot see a method reaching a class
through an included module, so a private module would hide most of phase 3b from the gate that
exists to see it.

- [ ] **Step 6: Regenerate the RBS baseline and run the API lock**

Run: `bundle exec rake rbs:validate steep sig:diff`
Expected: `rbs -I sig validate` exits 0; the diff is additions only. `NFR-11`'s scan must stay clean:
no constant outside `Dexpace::` and the fixed stdlib allowlist appears in any public signature —
`Dexpace::_ResponseHandler` names `Dexpace::Response` and nothing of phase 7's, which is R7's
whole point.

The lock diffs against the previous release tag and **there is none**: every gem is at `0.0.0` and
nothing is published (`docs/first-release.md`). `DEF-26`'s narrowing is therefore free now and would
not be later, which is exactly why the row targeted phase 3.

- [ ] **Step 7: Verify the two register rows the design already amended still describe the code**

**This step edits nothing unless the code disagrees with the register.** Phase 3b's design already
performed both amendments in `docs/deferred-items.md`, and this step is the check that the shipped
code matches what they now claim — a register row amended by a design and falsified by the
implementation is worse than one never touched.

- **`DEF-3`** reads "BODY-12, clause 1 — met and discharged by phase 3b", naming
  `::IO.copy_stream(handle, sink, count, offset)`, the four verified properties, `#path`/`#offset`/
  `#count`, the deliberate absence of `#to_path`, clause 2 targeting phase 8 with `DEF-10`, and
  `BODY-36`'s condition as "core's dependency budget changes". Confirm Task 6 shipped exactly that;
  its status line reads `deferred (BODY-12 clause 1 discharged 2026-09-08, phase 3b)`.
- **`DEF-26`** reads `picked-up (2026-09-08, phase 3b)`, citing the `sig/` narrowing to
  `Dexpace::Body?` and `HTTP-46`'s by-value body comparison against real body types. Confirm Steps 3
  and 4 shipped exactly that.

`DEF-34` was filed by the design and needs no change. `DEF-27`, `DEF-28`, `DEF-29` and `DEF-33` are
strengthened rather than met and their text stands: `BODY-28` is `close_quietly`'s first call site
and neither disposal route exists yet; `FakeBody` and `FakeResponseBody` are two more doubles that
would move into `dexpace-conformance` when a consumer outside `dexpace-core` appears, which is phase
8 at the earliest.

- [ ] **Step 8: Write the checklist**

`docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-checklist.md`, **one row per
requirement ID**, naming for each the numbered task above that satisfies it, or recording it as a
deferral or a deviation. **50 rows: the 49 IDs the segmentation design fixes, plus `HTTP-46`'s
cross-reference row.** The mapping, so the checklist is a transcription and not a re-derivation:

| ID | Task | Note |
|---|---|---|
| `BODY-1` | 1 | the default, and the property phase 6's three gates read |
| `BODY-2` | 7 | both conjunctions |
| `BODY-3` | 1, completed by 2 | the operation is Task 1's, its product is Task 2's |
| `BODY-4` | 1 | the one `#replayable?` property and the three documented declines; **the three call sites are phase 6's**, in three places, because `BODY-4` says a port need not unify them |
| `BODY-5` | — | cross-reference: phase 1 shipped `Method#idempotent?`; the retry gate that reads it is phase 6's |
| `BODY-6` | 4 | shared with Task 5's `ChunkedBody` and Task 8's `ResponseBody` through the module |
| `BODY-7` | 4 | a separate row and a separate proof from `BODY-6` |
| `BODY-8` | 4 | and Task 5's "closes nothing" test; §10.12 re-decided nothing |
| `BODY-9` | 4 | P3-16 |
| `BODY-10` | 1 | `copy_exactly` |
| `BODY-11` | 6 | six clauses, six tests |
| `BODY-12` | 6 (clause 1) | clause 2 ⏳ `DEF-3`/`DEF-10`, phase 8; P3-17 |
| `BODY-13` | 1 and 6 | one message form across both copy routines |
| `BODY-14` | 8 | |
| `BODY-15` | 8 | |
| `BODY-16` | 8 | both readers, both `ensure`d |
| `BODY-17` | 10 | |
| `BODY-18` | 10 | satisfied by construction; `OI-8` |
| `BODY-19` | 10 | P3-18 |
| `BODY-20` | 10 | `FakeBody` |
| `BODY-21` | 10 | |
| `BODY-22` | 11 | |
| `BODY-23` | 11 | and Task 13's measurement |
| `BODY-24` | 11 | |
| `BODY-25` | 1 and 11 | `FakeSource` |
| `BODY-26` | 11 | three behaviours, three tests |
| `BODY-27` | 11 | `FakeResponseBody` |
| `BODY-28` | 11 | `close_quietly`'s first call site; `DEF-27` strengthened |
| `BODY-29` | 11 | |
| `BODY-30` | 9 | body half; the step and the no-body clause are phase 4's |
| `BODY-31` | 9 | cross-reference: the predicate is phase 1's `Status#error?`, the step is phase 4's; 3b's contribution is the status-blind guarantee and its two tests |
| `BODY-32` | 1 and 8 | `clamp_cap`, and `#preview(cap:)` |
| `BODY-33` | 8 | the "null when there is no body" clause is the caller's `nil` check, phase 4's |
| `BODY-34` | 10 and 11 | parameter half only; the shared source and the enablement predicate are `DEF-34`, phase 5 |
| `BODY-35` | 1 | |
| `BODY-36` | — | ⏳ `DEF-3`; condition: core's dependency budget changes |
| `BODY-37` | 10 | one mechanism with `IO-28`, not two |
| `HTTP-36` | 1 | |
| `HTTP-37` | 1, 2, 4 | materialize-once in 1/2, the second-write guard in 4 |
| `HTTP-38` | 1, 2, 4, 5, 6 | the factory table completes in Task 5 |
| `HTTP-39` | 1 | |
| `HTTP-40` | 6 | |
| `HTTP-41` | 8 | |
| `HTTP-42` | 8 | `OI-7`; the one decode boundary |
| `HTTP-43` | 8 | a pure forward; idempotence lives in `ResponseBody`'s latch |
| `HTTP-44` | 12 | |
| `HTTP-45` | 12 | |
| `HTTP-46` | 14 | cross-reference: the ID is phase 1's; 3b supplies the type and the test |
| `HTTP-51` | 7 | |
| `HTTP-52` | 9 | body half |

- [ ] **Step 9: Run every gate on every matrix row**

```bash
bundle exec rake
mise exec ruby@3.2.11 -- bundle exec rake
mise exec ruby@3.3 -- bundle exec rake
mise exec ruby@3.4.10 -- bundle exec rake
mise exec ruby@4.0.6 -- bundle exec rake
```

Expected: green. **`OI-6` is the honest caveat**: RuboCop's own report is clean for no phase under
`.rubocop.yml` as phase 0 wrote it, so the RuboCop row here is unfalsifiable until whoever lands
phase 0 resolves it. 3b inherits that and adds to it rather than pretending otherwise. The
clean-bundle isolation run is the row that matters most for this phase, because `securerandom` is
the one `require` 3b adds and Ruby 4.0's column is what proves it is still a default gem there.

---
## The mutation battery

Fifty single-edit mutations, each reverting one requirement's mechanism, applied one at a time to
the finished tree with the owning suite re-run on 3.4.10. **All fifty were caught.** Every mutation
is a plausible edit, not a syntax error: four were rewritten during the battery because their first
form tripped `NFR-6`'s warning gate at load time rather than the assertion they were aimed at, and a
mutation caught by a warning is not evidence about a test.

| # | Reverted mechanism | Guard |
|---|---|---|
| 1 | BODY-1 default replayable? becomes true | **caught** — 1 failure |
| 2 | BODY-35 the -1 sentinel becomes nil | **caught** — 1 failure |
| 3 | BODY-25 a zero read is treated as end of stream | **caught** — 2 failures |
| 4 | BODY-10 a short transfer completes silently | **caught** — 1 failure |
| 5 | BODY-13 the sink short-write check is dropped | **caught** — 1 failure |
| 6 | BODY-32 the cap clamps UP instead of down | **caught** — 2 failures |
| 7 | BODY-30 the original body is not closed | **caught** — 3 failures |
| 8 | BODY-3 to_replayable returns self for a single-use body | **caught** — 1 failure |
| 9 | BODY-9 the probe becomes respond_to?(:rewind) | **caught** — 3 failures, 1 errors |
| 10 | BODY-9 replay rewinds to byte 0 instead of the origin | **caught** — 1 failure |
| 11 | BODY-9 the race-safe rewind guard is dropped | **caught** — 1 failure |
| 12 | BODY-8 an owned stream is not closed | **caught** — 2 failures |
| 13 | BODY-8 close ownership no longer forces single-use | **caught** — 3 failures |
| 14 | BODY-6/BODY-7 the consume-once latch is dropped | **caught** — 2 failures |
| 15 | BODY-11 the regular-file clause is dropped | **caught** — 2 failures |
| 16 | BODY-11 the offset+count clause is dropped | **caught** — 1 failure |
| 17 | BODY-11 the offset-past-size clause is dropped | **caught** — 1 failure |
| 18 | BODY-12 #to_path is defined | **caught** — 1 failure |
| 19 | BODY-13 the file short-write check is dropped | **caught** — 1 failure |
| 20 | BODY-11 the file handle is not closed | **caught** — 1 failure |
| 21 | HTTP-51 the length comes from a second routine | **caught** — 2 failures |
| 22 | HTTP-51 a quote in a parameter value is not escaped | **caught** — 2 failures |
| 23 | HTTP-51 a CR/LF in a parameter value is accepted | **caught** — 1 failure |
| 24 | HTTP-51 the boundary grammar is not checked | **caught** — 2 failures |
| 25 | BODY-2 replayability becomes a disjunction | **caught** — 1 failure |
| 26 | BODY-2 an unknown part length does not collapse the total | **caught** — 1 failure |
| 27 | BODY-14 #source returns a fresh handle each time | **caught** — 1 failure |
| 28 | BODY-15 close does not release the source | **caught** — 5 failures |
| 29 | BODY-33 preview consumes the primary read path | **caught** — 1 failure |
| 30 | BODY-6 a response body may be written twice | **caught** — 1 failure |
| 31 | BODY-16 body_string does not close the body | **caught** — 2 failures |
| 32 | BODY-16 body_bytes does not close the body | **caught** — 2 failures |
| 33 | HTTP-43 close does not forward to the body | **caught** — 2 failures |
| 34 | HTTP-42 the charset falls back to BINARY instead of UTF-8 | **caught** — 4 failures |
| 35 | BODY-18 one tee is reused across writes | **caught** — 2 failures |
| 36 | BODY-20 the tee is bound only after a successful write | **caught** — 2 failures |
| 37 | BODY-21 materialize-once drops the tap cap | **caught** — 1 failure |
| 38 | BODY-21 replayability is hard-coded instead of delegated | **caught** — 1 failure |
| 39 | BODY-22 the drain runs on every access | **caught** — 2 errors |
| 40 | BODY-22 the mutex is held across the drain | **caught** — 1 error |
| 41 | BODY-24 a second tail read is allowed | **caught** — 1 failure |
| 42 | BODY-24 the over-cap path also closes the delegate | **caught** — 1 failures, 2 errors |
| 43 | BODY-26 the drain error is not cached | **caught** — 1 failures, 4 errors |
| 44 | BODY-28 the capture close is loud instead of best effort | **caught** — 1 failures, 1 errors |
| 45 | BODY-28 the wrapper's close also closes the captured buffer | **caught** — 1 failure |
| 46 | BODY-29 the captured size is reported even for a prefix | **caught** — 3 failures |
| 47 | BODY-27 the close-once guard is bypassed | **caught** — 2 failures |
| 48 | HTTP-44 the memo becomes @value ||= | **caught** — 6 failures |
| 49 | HTTP-44 a failure is not memoised | **caught** — 2 failures, 1 error |
| 50 | HTTP-45 the raw accessors take the parse lock | **caught** — 1 failure |

**Three were missed on the first pass, and each exposed a real weakness in a test this plan now
ships differently.** They are recorded because the fix is the interesting part:

| Missed | Why the test did not see it | What the plan ships instead |
|---|---|---|
| `BODY-9`'s race-safe rewind guard dropped | The test raced four threads and asserted `seeks <= passers + 1`, which is satisfied when *all* of them pass and *all* of them seek | The two writes are made to **overlap deterministically**: the first parks inside a `BlockingSink` until the second has been attempted, so the second must be refused and the seek delta must be exactly 1 |
| `#release` also closing the captured buffer | `Buffer#reads_survive_close?` is `true`, so closing it is invisible to every read; and on the fits-cap path `close_quietly(self)` has already run before any view exists, so no outstanding view is invalidated either | The rule is pinned **directly** — after a full lifecycle on both regimes, `@buffer` is asserted **not** closed — because it is a rule with no external symptom today and a severe one after one reordering |
| `HTTP-45`'s raw accessors taking the parse lock | The fiber test suspended fiber A inside `@handler.call`, which is outside the mutex, so fiber B never contended for anything | Another **thread** holds the parse mutex while a reader thread calls `#status`/`#reason`/`#headers`, joined with a 5-second timeout — because the failure mode of that bug is a hang, and a hang is worse than a failure in CI |

Four mutations are recorded as **equivalent and therefore not in the table**, because pretending a
test catches something it cannot is worse than saying so: reordering the two `private_class_method`
symbols, renaming a private helper, changing `@dexpace_body_mutex` to another name, and moving
`freeze` to the end of a `BytesBody` constructor that has nothing left to mutate.

### The adversarial review's own battery, and what it found

The review did not trust the table above. It rebuilt the tree from this document's fences, ran a
**thirty-three-mutation** battery of its own against the finished suites, and probed the six
mechanisms the review brief names. Thirty of the thirty-three were caught. **Three were missed, and
two of those were tests passing under exactly the bug they exist to catch**; all three are fixed in
the tasks above, and the fixed tests were re-run red against the pre-fix fence first.

| Missed | Why the test could not see it | What the tasks now ship |
|---|---|---|
| `Body#emit_exactly` drops the `String#b` ingress retag | The only "`#each` yields BINARY" test used `FakeBody`, which calls `#b` itself, and every sink in the suite retags on the way in — so no assertion in the sub-phase depended on the retag | Task 5's `ChunkedBody` suite yields `FakeChunked.frozen_utf8` through `#each` and asserts the block's chunks are BINARY: the chunk reaching the block is whatever `emit_exactly` handed the sink |
| `FormBody` stores the caller's pairs instead of a copy | `@bytes` is encoded at construction, so a drain-only assertion is unchanged by the aliasing; the test named "takes an independent frozen copy" passed with `@pairs = pairs` | Task 5's test asserts `#pairs` itself — it is public and folds into `#==` and `#hash` — after mutating both the caller's array and one of its Strings |
| `Body::BlockSink` drops `#b` on the joined multi-string write | Nothing in core writes two Strings to a sink in one call, so the branch is unreachable from any body this phase ships | Recorded, not tested. A test for an unreachable branch is a test that cannot fail for the right reason; the branch is one line and the retag beside it is now covered |

Four further findings came from the probes rather than the battery, and each is a task change with
a red-first reproduction: the two suites that build a `Response` did so with a `Request` carrying no
method and a builder carrying no protocol, which phase 1's own `initialize` rejects (Tasks 8 and 12
— 19 errors of 20 and 15 of 17 against the real contract); `TypedResponse` left `@state` at
`:running` for good when a handler raised outside `StandardError`, blocking every other caller on
the condition variable for the life of the process (Task 12, `P3-27`'s neighbour); `MultipartBody`'s
length query consumed and closed single-use parts (Task 7, `P3-29`); and the `BODY-23`/`BODY-24`
regime probe wrote its extra byte into the capture, making every over-cap snapshot `cap + 1` bytes
(Task 11).

---

## The finding filed against `docs/open-items.md`

**`OI-9` — `Dexpace::IO::BufferedSource.wrapping(io)` delivers one byte per read, so every
`wrapping`-backed transfer is one syscall per byte.** Verified on 3.2.11, 3.4.10 and 4.0.6 while
planning this phase. `#read_into(dest, count: N)` returns **1** for any positive `N` when the buffer
is empty, and `#each` yields **one-byte chunks**: 200 000 chunks and 200 001 `readpartial(1)` calls
for 200 000 bytes, at ~0.21 s where the `Buffer` and `.over` paths are unmeasurable (0.000 s). The
cause is one line: `#read_into` fills through `#fill_once_if_empty`, which is hard-coded to
`ensure_buffered(1)` — that is, `fill(1)` — rather than `fill(count)`; `#store_take_chunk`'s empty
refill inside `#each` and `#drain_all` has the identical shape. `fill(count)` fills **once** and
returns whatever came back, which is non-blocking and satisfies `IO-1`'s "at least 1 when byteCount
is positive and the source is not exhausted" exactly as `fill(1)` does.

It is a **throughput** defect and not a correctness one — every read returns correct bytes in the
correct order, which is why 3a's own suite is green and stays green. It reaches phase 3b's
`StreamBody` upload pump, `ResponseBody`'s readers, `Response#body_string` and the
`ResponseLoggingBody` drain, and it will reach every transport phase 8 writes, since
`BufferedSource.wrapping` is how a response body is built.

Why it is recorded rather than fixed here: it is phase 3a's code, phase 3a's plan is committed and
adversarially reviewed, and this plan must not edit it — the same order-of-work argument `OI-8`
makes. **The window is the same one `OI-8` names**: neither plan has been executed, no gem exists,
every gem is at `0.0.0`, so the fix is one line in an unexecuted plan and no signature changes at
all. **No test in phase 3b asserts a chunk granularity in either direction** — deliberately, and
plan decision 4 says so — so 3a's fix lands without touching a line of 3b.

**`OI-11` — a caller mistake in an argument can still leave core through a stdlib exception class.**
`Dexpace::Body.string("caf\xE9".b)` raises `Encoding::UndefinedConversionError`, and
`Dexpace::Body.multipart(parts, subtype: "not a subtype")` raises out of `MediaType.parse`, where the
Global Constraints promise `Dexpace::InvalidArgumentError` for "a caller mistake in an argument".
Filed rather than fixed here: the fix is a `rescue` at each site, the two sites are not the only
ones (phase 1's coercions have the same shape), and a rule about which stdlib exceptions core
re-wraps is a cross-phase decision this sub-phase should not make alone. Recorded by phase 3b's
plan review.

`OI-1` through `OI-8` remain open and unchanged. `OI-4` gains the measurement Task 13 produces, in
its Resolution field, and stays open. `OI-7` is this phase's design's and is discharged in code by
Task 8 without being closed as an item, because what would resolve it is one sentence in a frozen
design chapter. `OI-10` is the design review's and is **resolved** by the contract widening
`P3-23` records, which Tasks 1, 2, 8, 9 and 11 implement.

## Deferrals Filed by Phase 3b

**None new.** `DEF-34` was filed by the design and its text needs no change: phase 3b ships the
parameter shape on both wrappers, one number that can drive both, and the structural half of
`BODY-34`'s enablement clause, and what it cannot ship is the thing that decides the value and the
thing that decides "enabled". Task 14 Step 7 **amends `DEF-3`** and marks **`DEF-26` picked up**;
neither is a new deferral.

## Deviation Ledger

The design's rows **P3-14** through **P3-21** stand unchanged and are not restated here, and
**P3-23** — `#source`/`#close` on the contract, `OI-10`'s resolution — is the design review's and is
carried there. This plan adds **P3-22**, and its own adversarial review added **P3-27**, **P3-28**
and **P3-29**; the provenance is kept visible because a row's owner is who answers for it.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P3-22 | The per-variant accessors design §3 does not name and P3-14's constant list does not enumerate: `StreamBody#origin`, `#rewindable?` and `#owns_stream?`; `RequestLoggingBody#delegate`, `#snapshot` and `#tap_bytesize`; `ResponseLoggingBody#snapshot`, `#error`, `#delegate` and `#preview_bytes`; `FormBody#pairs` and `FormBody::MEDIA_TYPE`; `MultipartBody#parts`, `#boundary`, `.generate_boundary`, `BOUNDARY_CHARS` and `BOUNDARY_LENGTH`; `ResponseBody#preview`; `Response.resolve_charset`. **`#source` is not here** — it is a contract member under **P3-23**, and `ResponseLoggingBody#read` is gone, renamed to it | `NFR-4`; P3-14's and 3a's P3-8 precedent | Each is `NFR-4`-locked at the first release tag exactly as a constant is, and P3-14 covers the twelve **constants** rather than every method on them. Each is here because a test needs it to be observable rather than because a caller asked: `#rewindable?` is what lets a test tell "the probe said no" apart from "`BODY-8` ownership forbids replay", which is the distinction P3-16 and plan decision 6 turn on; `#tap_bytesize` is what makes `BODY-19`'s cap measurable without reaching for the tee; `#error` is `BODY-26`'s third behaviour and has no other home. The ones that are **not** here are as deliberate: `FileBody` exposes no `#to_path` (P3-17), `RequestLoggingBody` exposes no buffer handle (`BODY-37`), and `Dexpace::Body` exposes no `ceiling:` keyword anywhere (boundary 8) |
| P3-27 | `HTTP-45`'s "MUST NOT pin/park the underlying OS carrier thread for the duration of the parse" holds for threads and for a fiber arriving after the parse has settled, and **not** for a second fiber of the same thread arriving mid-parse with no Fiber scheduler installed | `HTTP-45`; design §10.5's precedent | `Thread::Mutex` and `Thread::ConditionVariable` defer to an *installed* Fiber scheduler, and the default is that none is installed. Verified on 3.2.11, 3.4.10 and 4.0.6: with fiber A suspended inside `@handler.call`, fiber B's `#value` blocks the carrier thread inside `#wait`, and if A is never resumed the process aborts with `No live threads left. Deadlock?`. Ruby offers no scheduler-independent primitive that serializes without parking, so this is the same shape as the three unsatisfied MUSTs §10.5 splits — recorded, not papered over. `Dexpace::ResponseLoggingBody#ensure_drained` has the identical shape and the identical residue. Task 12's YARD states it at the method; Task 11's test comment already did |
| P3-28 | `StreamBody`'s `BODY-9` rewind guard is released in an `ensure`, so a replayable body whose `#each` enumerator is abandoned mid-stream stays claimed and refuses **every** later write | `BODY-9`; §7.1, and design §10.10's precedent | The residue `docs/knowledge/notes/pagination.md` widened to an ordinary `#each` method reaches this class as well as `FileBody`, and the design records only `FileBody`'s. There is no in-method defence — `block_given?` is true under `to_enum(:each)` — and no `#close` to release the flag, because the flag guards a write and not a resource. Verified on all three that a full external drive to `StopIteration` and `#each`-with-`break` both release it, so only abandonment is affected. A body that refuses every later write is strictly safer than two readers sharing one cursor, which is what `BODY-9`'s clause exists to prevent; Task 4 asserts the residue as a fact rather than claiming it is closed |
| P3-29 | `MultipartBody`'s counting run takes `count_only: true`: the framing bytes come from the one shared routine and the **payload count** comes from each part's own `#content_length` rather than from writing the part | `HTTP-51` | `HTTP-51` fixes that the declared length and the bytes come from one routine so the two cannot drift; it does not say a length query may consume the body. Writing the parts into the counting sink does: verified on all three that `#content_length` over a `Body.stream(io, content_length: 6, close: true)` part drains **and closes** it, that the write which follows then raises `BODY-6`, and that the same happens for a `Body.chunked(chunks, content_length: 4)` part and a pipe-backed stream with a declared length — and that every `FileBody` part is read off disk in full to answer a header question. The drift `HTTP-51` names is the framing, and the framing still comes from `#emit`; a part whose `#content_length` disagrees with the bytes it writes is violating `HTTP-36`, and `BODY-2`'s `-1` sentinel already covers a part whose length is unknown |

---
## Self-review against the design

**Spec coverage.** Every one of the design's 49 IDs has a task, and the mapping is Task 14 Step 8's
table rather than a claim here. The design's ten spec-forced boundaries: `IO-40` (1) is Global
Constraints and no method in any task takes a deadline; `IO-37`/`IO-38` (2) is four flag flips and no
more, one each in Tasks 4, 11 and 12 plus `Closeable`'s; `IO-42`'s asymmetry (3) is Task 11's three
surfaces and its two opposite-direction tests; `IO-28` ↔ `BODY-37` (4) is Task 10 and it claims no
more than §10.10 does; `IO-6` with `BODY-8` (5) is Task 4 and plan decision 7, and the codec's third
rule is untouched; `BODY-4`'s three declines (6) are documented at `#replayable?` and built by nobody
here; `HTTP-42`'s single boundary (7) is Task 8 and every other reader returns BINARY; the ceiling
(8) is read from 3a's constant in Tasks 1, 4 and 8 and no keyword is added anywhere; the retired
provider seam (9) gets no registry; and `Dexpace::IO::` (10) is why every `::IO`, `::File` and
`::IO::SEEK_SET` in Tasks 4, 6 and 7 is written qualified.

R5's three caps are three numbers in three places and no task collapses two. R6's twelve constants
are all present and flat. R7's handler is `#call(response)` and no witness exists. R8's line is
Task 9's argument type. R9 is Task 4. R10 is Task 11.

**The five open questions are answered** in "Decisions this plan makes", items 1 to 5, each with the
choice stated and — for the two the design asked to be tested — the test named: Task 7's memoised
length equals the bytes written, and Task 13's measurement is a task rather than a paragraph.

**Boundaries, checked one at a time.** No task writes `Dexpace::Recovery.buffer_error_body`, a status
check in the body layer, or "a response with no body is returned unchanged" — phase 4. No task adds a
`ceiling:` keyword, a default preview size, or an "enabled?" predicate — phase 5, `DEF-34`. No task
writes `Resilience::Resend.eligible?` or any retry, redirect or auth gate — phase 6. No task writes a
witness, a codec or a status-aware handler, and nothing here generalises 3b's ownership rule over
`SEAM-20`/`SEAM-21`/`SERDE-3` — phase 7. No task implements zero-copy dispatch — phase 8, `DEF-10`.

**What must ship complete because a later phase depends on it, and does.** `#replayable?` on every
variant, for phase 6's three gates. `Body.buffer_bounded` plus the constant, for phase 4's step and
`RETRY-36`'s shared bound. A `_Chunked`-compatible `#each` on every body, for phase 8's transports —
derived once in Task 1, so it exists on all eleven. `Dexpace::Body` as the `sig/` type, for `NFR-11`
and every later signature. `Dexpace::_ResponseHandler`, for phase 7 to supply into. The
`TeeSink`-based capture surface, for phase 5 to construct.

**Type consistency.** `#write_to(sink) -> Integer` is the one hook and every variant implements it
with that arity; `#source` and `#close` are the read-side pair the contract adds (`P3-23`, `OI-10`),
`#source` raising by default so the `sig/` declaration is true of every `Dexpace::Body` and the
three bodies that can occupy `Response#body` overriding it. `copy_exactly(source, sink, count)` and `emit_exactly(sink, string)` keep their
names and argument order in all six callers. `clamp_cap(cap)` is called by `Body.buffer_bounded` and
by `ResponseBody#preview` and returns an `Integer` in both. `#snapshot` means "the captured bytes,
BINARY, without raising" on both wrappers. `#delegate` is the wrapped body on both. `#source` means the same thing
on all three response-side bodies and is the contract's own name — the same object every time on
`ResponseBody` (`BODY-14`), a fresh non-consuming view per call on `BufferBody` (`BODY-30`), and
`BODY-23`/`BODY-24`'s regime accessor on `ResponseLoggingBody`. All three return a
`Dexpace::IO::BufferedSource` and not bytes, and each YARD says so in its first line.

**`BODY-27`, settled.** The clause names two close paths and the composite is
`BufferedSource.wrapping` over a `#read`-shaped tail whose `#close` routes to the wrapper's own
`Closeable` latch — one guard, both paths, either order. `.over`, which owns nothing, would have
made the tail's `#close` a callable method that released no transport resource, and `BODY-24` hands
that tail to a consumer as the rest of the body. Task 11's suite asserts it directly: closing the
tail closes the delegate exactly once, and a later close of either is still one close.

**Placeholder scan.** No task contains "TBD", "similar to Task N", "add appropriate validation" or a
test described rather than written. Every `ruby` and `rbs` fence in this document was extracted,
written to the file it names, and run.
