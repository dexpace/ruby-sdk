# Phase 3a — I/O Contracts: Checklist

**Written at execution time, 2026-09-15, from what was built** — not from the plan. A row whose task
did not do what the plan said is a row that says so, and the "Deviations from the plan" section
below is where each departure is stated with its reason.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts.md`. Task numbers are that
plan's. Design: `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md`, whose
Deviation Ledger rows `P3-n` are cited below; the charter is
`docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md`. Every test file named here is
under `gems/dexpace-core/test/`, mirrors its `lib/` file one for one, and opens with the IDs it
exercises.

## Requirement rows

Forty-two: `IO-1`–`IO-42`.

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `IO-1` | MUST | ✅ | 5 | `Dexpace::IO::TypedReads#read_into(dest, count:)` — the primitive, deliberately not `#read` (P3-1): it appends to the tail of a BINARY `dest`, returns at least 1 when `count` is positive and the source is not exhausted, exactly 0 for a zero count, `-1` when exhausted before any byte, never more than `count`, and fills at most once before serving — through a view too, since review round 0: a `#peek` or `#slice` fills its parent until a byte past the view's own position has arrived and returns what came with it, never looping to `count` (R0-1; `ViewFills`, and `dexpace/io/buffered_source_test.rb`, `Views`, over a live `IO.pipe` with the writer still open; guard run red below). The count the caller asked for is the count the fill hook receives, so a wrapped stream is asked for `count` bytes and not for one, through a view as well (the plan's 2026-09-13 amendment; guards run red below). Asserted against `#read` on the same non-empty buffer in one test, so a later merge of the two turns red (`dexpace/io/typed_reads_test.rb`, the primitive rows and `Bridge`) |
| `IO-2` | MUST | ✅ | 5 | A zero count returns 0 and never `-1`, on an exhausted source too, and touches neither the buffer nor the fill hook. The check sits after `IO-42`'s close check, so a closed stream-backed source refuses a zero-count read as it refuses every other (plan decision 5) (`dexpace/io/typed_reads_test.rb`; `dexpace/io/buffered_source_test.rb`, `Close`) |
| `IO-3` | MUST | ✅ | 5, 6, 9, 11, 12 | A negative or non-`Integer` count, offset, length or maxlen is `Dexpace::InvalidArgumentError` naming the argument and the value, before any I/O and with no partial side effect — asserted for `#read_into`, `#read`, `#readpartial`, `#read_exactly`, `#skip`, `#read_string`, `#slice`, `#write_from` and `#copy_to`; `#read_into` also refuses a non-`String`, frozen or non-BINARY destination the same way (`dexpace/io/typed_reads_test.rb`, `Rejections`; `dexpace/io/typed_writes_test.rb`, `WriteFrom`; `dexpace/io/buffer_test.rb`, `CopyTo`) |
| `IO-4` | MUST | ✅ | 11, 13, 14 | `TypedWrites#write_from(buffer, count:)` removes exactly `count` bytes from the head of a `Dexpace::IO::Buffer` and pushes them; a buffer holding fewer raises `Dexpace::StreamError.short_transfer` naming both counts and consumes nothing; a zero count is a no-op; a non-`Buffer` is refused. Re-tested against a real `Buffer` into a `BufferedSink` over a `StringIO` and through a `TeeSink` (`dexpace/io/typed_writes_test.rb`, `WriteFrom`; `dexpace/io/buffered_sink_test.rb`; `dexpace/io/tee_sink_test.rb`, `Vocabulary`) |
| `IO-5` | MUST | ✅ | 11, 12, 13, 14 | `#flush` on every sink and `#close` on every source, sink, buffer and tee (`Dexpace::Closeable`). `BufferedSink#flush` pushes what is staged and calls the underlying `#flush` when there is one; `TeeSink#flush` forwards to the primary only (`dexpace/io/buffered_sink_test.rb`, `Staging`; `dexpace/io/tee_sink_test.rb`, `Lifecycle`) |
| `IO-6` | MUST | ✅ | 10, 13 | Read out of appendix C, its only normative home, and cited with design §10.12 — never `SEAM-3` (R3; `docs/knowledge/notes/message-bodies.md`). `BufferedSource.wrapping(io)` and `BufferedSink.wrapping(io)` take ownership: closing the wrapper closes the wrapped stream, `#owns_upstream?` reads it back, there is no borrowing variant (P3-12) and `.new` is private so ownership cannot be set through an unnamed argument (P3-11). `.of_bytes` and `Buffer.new` own no external resource; `.over` is the one stated exception and never closes what it wrapped. The bridge clause is asserted rather than inferred: `IO.copy_stream` through a wrapped pipe end, then `#close`, closes the pipe (`dexpace/io/buffered_source_test.rb`, the ownership rows and `Bridge`; `dexpace/io/buffered_sink_test.rb`) |
| `IO-7` | MUST | ✅ | 12 | `Dexpace::IO::Buffer` includes both vocabularies: bytes written through the sink surface read back through the source surface in order, `#bytesize` is what is currently held, and the mandatory property test writes N random BINARY chunks and reads them back, with a second property interleaving writes and reads (`dexpace/io/buffer_test.rb`) |
| `IO-8` | MUST | ✅ | 12, 14 | `Buffer#snapshot` is a fresh, independent, **unfrozen** BINARY copy from the cursor that neither consumes nor mutates the buffer; a later write does not reach it and mutating it does not reach the buffer (P3-10). `TeeSink#tap_snapshot` is the same over the tap (`dexpace/io/buffer_test.rb`, `Snapshot`; `dexpace/io/tee_sink_test.rb`) |
| `IO-9` | SHOULD | ✅ | 6, 12 | `Dexpace::IO::MAX_MATERIALIZED_BYTES`, 64 MiB, §10.18's substituted constant at §3.1's default, read directly and never from a keyword (asserted). One guard, `TypedReads#guard_materialization!`, at six sites (P3-4): `#read_exactly`, `#read_string`/`#read_utf8` with a count, the three count-less drains checked incrementally as the result grows (`#read` with no length, `#read_utf8`, `#read_string`), a length-bounded view's read through its known remaining window, and `Buffer#snapshot`. Every refusal is a `Dexpace::StreamError` naming the constant and the streaming alternatives (`#read_into`, `#each`, `#slice`, `Buffer#copy_to`) and allocates nothing; an over-ceiling slice constructs and refuses on the read (`IO-21`'s ordering); the one allocating test builds a buffer one byte over the ceiling and runs on every matrix row. `#read(length)`, `#readpartial(maxlen)` and `#read_line_utf8` are outside the guard on purpose, and P3-4 says why (`dexpace/io/typed_reads_test.rb`, `Ceiling`; `dexpace/io/buffer_test.rb`, `Snapshot`) |
| `IO-10` | MUST | ✅ | 12 | `Buffer#clear` discards every byte and the buffer accepts new writes afterwards; `Buffer#copy_to(other, offset: 0, count: nil)` copies a window measured from the cursor into another `Buffer` without consuming or mutating the source, defaults to "from offset through end", and refuses a negative offset or count, a window past the end and a non-`Buffer` target with `Dexpace::InvalidArgumentError` leaving both buffers untouched — never a ceiling error, because it materialises nothing (`dexpace/io/buffer_test.rb`, `CopyTo`) |
| `IO-11` | MUST | ✅ | 6, 8 | `#eof?` is true exactly when no bytes remain (and may fill once to find out); `#readbyte` returns 0..255 or raises `Dexpace::EndOfStreamError` and `#getbyte` returns 0..255 or `nil`; `#read` with no length drains everything and returns `""` when exhausted (`dexpace/io/typed_reads_test.rb`, `Typed`) |
| `IO-12` | MUST | ✅ | 6 | `#read_exactly(count)` returns exactly `count` BINARY bytes across chunk boundaries or raises `Dexpace::EndOfStreamError` consuming nothing; `#read_exactly(0)` is an empty BINARY `String`; `#read_utf8(count:)` and `#read_string(encoding, count:)` take a **byte** count and raise rather than return short (`dexpace/io/typed_reads_test.rb`, `Typed` and `Charsets`) |
| `IO-13` | MUST | ✅ | 6, 11 | Read side: `#read_utf8` and `#read_string(encoding)` retag the drained BINARY bytes with the named `Encoding` (or name), validate nothing — `#valid_encoding?` is the caller's question and `HTTP-42`'s replacement policy is 3b's — and refuse an unknown name before touching the stream. Write side: `#write_utf8(string, range: nil)` with a character range, and `#write_string(string, encoding:)`, which encodes into the named charset and refuses text it cannot represent. Every fixture is non-ASCII (`dexpace/io/typed_reads_test.rb`, `Charsets`; `dexpace/io/typed_writes_test.rb`, `Charsets`) |
| `IO-14` | MUST | ✅ | 7 | `#read_line_utf8`, hand-implemented over the chunk store and never `#gets`: `"\n"` and `"\r\n"` terminate and are consumed, a lone `"\r"` is content, a final unterminated line comes back as-is, `nil` when exhausted before any byte, a terminator split across two chunks is one terminator, the result is UTF-8-tagged. A 48-sample property over a pool including `"a\rb"`, `"é"` and `"hé\rllo"` mixes both terminators, an optional missing final one, and random chunk splits (`dexpace/io/typed_reads_test.rb`, `Lines`) |
| `IO-15` | MUST | ✅ | 6 | `#skip(count)` advances past exactly `count` bytes across chunk boundaries, raises `Dexpace::EndOfStreamError` consuming nothing when fewer remain, and `#skip(0)` is a no-op at and after EOF (`dexpace/io/typed_reads_test.rb`, `Typed`) |
| `IO-16` | SHOULD | ✅ | 8, 10, 11, 13 | The bridge is the source (R4): `#read(length = nil, outbuf = nil)`, `#readpartial(maxlen, outbuf = nil)`, `#getbyte`, `#readbyte` and `#each` carry Ruby's own semantics, end of stream the host-native way — `nil` from `#read`/`#getbyte`, `Dexpace::EndOfStreamError < ::EOFError` from `#readpartial`/`#readbyte` (P3-2) — and `outbuf` comes back BINARY whatever it arrived as (P3-13). Proved rather than restated: `IO.copy_stream` over a `BufferedSource.wrapping(pipe_end)` delivers the payload intact, terminates on the `EOFError` subclass, and closing the source afterwards closes the pipe; `#read(2, buf)` overwrites where `#read_into(buf, count: 2)` appends, in one test. Through a view the bridge keeps Ruby's semantics too, since review round 0: on a peek over a live `IO.pipe` with the writer open, `#readpartial(100)` returns the ten bytes that have arrived and `#each` yields them, as the root does, where before R0-1 both blocked to the count (`dexpace/io/buffered_source_test.rb`, `Views`; `dexpace/io/typed_reads_test.rb`, `ViewFills`). The writable half: `TypedWrites#write(*strings)` returns the byte count, and `IO.copy_stream` writes into a `BufferedSink.wrapping(io)` and into a `TeeSink` (`dexpace/io/typed_reads_test.rb`, `Bridge`; `dexpace/io/buffered_source_test.rb`, `Bridge`; `dexpace/error/end_of_stream_error_test.rb`; `dexpace/io/buffered_sink_test.rb`; `dexpace/io/tee_sink_test.rb`, `Vocabulary`) |
| `IO-17` | MUST | ✅ | 11, 13 | `TypedWrites#write_all(source)` pumps anything responding to `#read_into` through 64 KiB reads, terminates only on `-1`, returns the total, and raises `Dexpace::StreamError.zero_read` on a read of 0 for a positive count — unconditionally, because §10.1 retired the adapter and "adapter-native" has no subject here — without spinning; a source's own failure propagates unchanged. `FakeSource` scripts the violation no real stream produces. The symmetric write-side rule: an underlying `#write` that reports fewer bytes than it was handed is `Dexpace::StreamError.short_transfer` (`dexpace/io/typed_writes_test.rb`, `Pump`; `dexpace/io/buffered_sink_test.rb`, `Staging`) |
| `IO-18` | SHOULD | ✅ | 11, 12, 13, 14 | `#emit` pushes one level and never calls the underlying `#flush`; `#flush` does both. `BufferedSink` stages and pushes in the same `#deliver`, so the staging buffer is empty between calls (plan decision 4); `Buffer`'s two are the no-ops the requirement permits, returning `self`; `TeeSink`'s forward to the primary only (`dexpace/io/buffered_sink_test.rb`, `Staging`; `dexpace/io/buffer_test.rb`; `dexpace/io/tee_sink_test.rb`, `Lifecycle`) |
| `IO-19` | MUST | ✅ | 9, 10 | `#peek` returns a `BufferedSource` in view mode over the whole remaining source — an unbounded window, never "whatever happens to be buffered" — that drives the parent's fill without advancing the parent's cursor, one fill per read and returning what arrived, as on the root (review round 0, R0-1) (`dexpace/io/typed_reads_test.rb`, `Views`, `ViewFills`; `dexpace/io/buffer_test.rb`, `Close`; `dexpace/io/buffered_source_test.rb`, `Counts`, `Views`) |
| `IO-20` | MUST | ✅ | 9, 10 | `#slice(offset:, count:)` exposes at most `count` bytes starting `offset` ahead of the cursor, never advances the parent, and reading past the window behaves as end of window for every read form (`dexpace/io/typed_reads_test.rb`, `Views`) |
| `IO-21` | MUST | ✅ | 9, 10 | An offset past the end constructs successfully and surfaces on first read as empty/EOF; a negative or non-`Integer` offset or count is refused at construction (`dexpace/io/typed_reads_test.rb`, `Views` and `Ceiling`) |
| `IO-22` | MUST | ✅ | 5, 9, 10, 12 | Closing a view closes neither its parent nor the parent's cursor and releases its registration; closing the parent — a `BufferedSource` or a `Buffer` — invalidates every outstanding view so that every later read on one raises `Dexpace::ClosedError`, **transitively through a view's own views**, and the two parent-side entry points a view drives (`#dexpace_fill_beyond`, `#dexpace_window_copy`) check the parent's readability first, so a closed or invalidated intermediate serves nothing (deviation 3 below). P3-5's retention rule: a parent read past a live view's pin makes that view fail loudly naming "behind", never serving other bytes; a view that already pulled its window is unaffected (`dexpace/io/typed_reads_test.rb`, `ViewLifecycle`; `dexpace/io/buffer_test.rb`, `Close`) |
| `IO-23` | MUST | ✅ | 9, 10 | Two slices of one source have independent cursors and budgets; a slice of a slice composes offsets additively from the outer view's cursor and is capped at the outer window's remaining bytes, over a partially read outer view too, and a 48-sample property pins it over random offsets and budgets. Reading the outer view past the inner view's pin invalidates the inner one (P3-5 applied recursively) (`dexpace/io/typed_reads_test.rb`, `Views` and `ViewLifecycle`) |
| `IO-24` | MUST | ✅ | 9, 10 | Every read form on an explicitly closed view — thirteen of them, `#peek` and `#slice` included — raises `Dexpace::ClosedError`, a `StandardError` that is neither an `EOFError` nor a `StreamError` (P3-3) (`dexpace/io/typed_reads_test.rb`, `ViewLifecycle`; `dexpace/io/buffered_source_test.rb`, `Close`) |
| `IO-25` | MUST | ✅ | 14 | `Dexpace::IO::TeeSink.new(primary:)` mirrors every write into a `Buffer` tap and forwards the full payload to the primary, whose writes are byte-for-byte identical with or without a tap limit; a 48-sample property asserts tap and primary agree over random chunk sequences (`dexpace/io/tee_sink_test.rb`) |
| `IO-26` | MUST | ✅ | 14 | `tap_limit:` bounds the tap: it stops copying at the limit, a mid-write limit truncates exactly there, the full payload still reaches the primary, the default (`nil`, with `Float::INFINITY` accepted as the other spelling) is unbounded, a limit of 0 mirrors nothing and forwards everything, and a negative, non-`Integer` or finite-`Float` limit is refused at construction; a 32-sample property pins "exactly the first `limit` bytes" (`dexpace/io/tee_sink_test.rb`, the limit rows and `Vocabulary`) |
| `IO-27` | MUST | ✅ | 14 | The attempted bytes are mirrored before the primary is written, so a primary that raises mid-stream still leaves them in the tap; the staging buffer is cleared in an `ensure`, so a later write prepends nothing (`dexpace/io/tee_sink_test.rb`, `Failure`) |
| `IO-28` | MUST | ✅ | 14 | `TeeSink#buffer` is defined and raises `Dexpace::StreamError` naming `IO-28` and the typed write methods; no other route to the tap, the primary or the staging buffer is exposed, and the tap is reachable only through `#tap_snapshot`'s fresh copy. Design §10.10's honest position stands: `instance_variable_get` reaches anything and no fake proof is built (`dexpace/io/tee_sink_test.rb`, `Lifecycle`) |
| `IO-29` | MUST | ✅ | 14 | `#emit`, `#flush` and `#close` forward to the primary only, in that order when called in that order, tolerate a primary lacking any of the three, and leave the tap intact for snapshotting after close (`dexpace/io/tee_sink_test.rb`, `Lifecycle`) |
| `IO-30` | MUST | 🚫 | 10 | The provider seam's factory operations are retired with the seam (design §10.1; §12's `IO` row). **The one behavioural clause survives as a property of `.of_bytes`**: the source is an independent copy of the caller's `String`, so a later mutation of either reaches neither (`dexpace/io/buffered_source_test.rb`, the ownership rows) |
| `IO-31` | MUST | 🚫 | — | Provider resolution rules for a seam that does not exist (design §10.1). No fourth registry, no factory, no installation call, no discovery — asserted negatively by `Dexpace::IO.constants` being exactly the six streaming constants plus the ceiling (`dexpace/io_test.rb`) |
| `IO-32` | MUST | 🚫 | — | Install idempotence for the retired seam (design §10.1; one of the roadmap's five gap IDs, appendix-C only, read for nothing) |
| `IO-33` | MUST | 🚫 | — | Install-wins-after-discovery for the retired seam (design §10.1; appendix-C only) |
| `IO-34` | MUST | 🚫 | — | Discovery caching for the retired seam (design §10.1; appendix-C only) |
| `IO-35` | SHOULD | 🚫 | — | The late-replacement warning for the retired seam (design §10.1; appendix-C only) |
| `IO-36` | MUST | 🚫 | — | The provider's own conformance obligations for the retired seam (design §10.1) |
| `IO-37` | MUST | ✅ | 10 | No instance carries a lock over its read or write path; the only synchronised state is `Closeable`'s latch, read once per public entry point. The proof is the lock's absence: two fibers of one thread interleave `#read_exactly` calls on one `BufferedSource` whose upstream yields mid-read, and no `ThreadError` is raised — which a mutex held across a fill would raise (verified fact 7) (`dexpace/io/buffered_source_test.rb`, `Threads`) |
| `IO-38` | MUST | ✅ | 2, 10 | `Closeable#closed?` now reads the latch under the close mutex (P3-6), the one change to a phase-2 constant; the assertion that distinguishes it from phase 2's unsynchronised reader — a fiber holding the latch mutex across a `Fiber.yield`, a second fiber calling `#closed?`, `ThreadError` — was run red against phase 2's version first (guards below). Behaviourally: a `#read_exactly` blocked on a pipe on thread B fails with Ruby's own `IOError` when thread A closes the source, forwarded unchanged (`IO-40`), and every later read is `Dexpace::ClosedError`; a view being read on thread B raises `Dexpace::ClosedError` after thread A closes the parent — both sequenced through `Thread::Queue`s, never raced. On every CRuby row the GVL would hide a missing lock, which is the postponement the design records and `docs/first-release.md` § Post-release triggers owns (`dexpace/closeable_test.rb`; `dexpace/io/buffered_source_test.rb`, `Threads`) |
| `IO-39` | SHOULD | 🚫 | — | Lock-free reads of a provider registry that does not exist (design §10.1). The property survives in phase 2's `Dexpace::Registry`, as its checklist's `SEAM-9` row records |
| `IO-40` | MUST | ✅ | 10, 13, 14 | By construction: no method in 3a takes a timeout, a deadline or a `Cancellation`, and the only blocking call is the upstream's own `#readpartial`/`#read` inside `#fill`. The mirroring clause: `TeeSink` and `BufferedSink` clear their staging buffer in an `ensure`, never a `rescue`, so the primary's failure propagates once as the identical object — asserted with `assert_same` — and a blocked read's `IOError` reaches the caller unchanged (`dexpace/io/tee_sink_test.rb`, `Failure`; `dexpace/io/buffered_sink_test.rb`, `Staging`; `dexpace/io/buffered_source_test.rb`, `Threads`). The styleguide's per-call timeout rules are answered by `docs/knowledge/notes/resource-management.md` |
| `IO-41` | MUST | ✅ | 10, 12, 13, 14 | Close is idempotent on every source, buffer, sink and tee, the underlying resource is closed at most once — including when two threads close one source at once — and an upstream or primary with no `#close` is fine (`dexpace/io/buffered_source_test.rb`, `Close` and `Threads`; `dexpace/io/buffer_test.rb`, `Close`; `dexpace/io/buffered_sink_test.rb`, `Close`; `dexpace/io/tee_sink_test.rb`, `Lifecycle`) |
| `IO-42` | MUST | ✅ | 10, 12, 13, 14 | Both directions, two tests that fail in opposite ways. A stream-backed `BufferedSource` raises `Dexpace::ClosedError` from every read form after close (a zero-count `#read_into` included), a `BufferedSink` and a `TeeSink` from every write form, `#emit` and `#flush`; the error is a state error and never an `EOFError`. A `Buffer` stays readable and writable on its own surface after close — `#snapshot`, `#bytesize`, `#write`, `#emit`, `#flush`, `#read` — and its close still invalidates every view derived from it (`dexpace/io/buffered_source_test.rb`, `Close`; `dexpace/io/buffered_sink_test.rb`, `Close`; `dexpace/io/tee_sink_test.rb`, `Lifecycle`; `dexpace/io/buffer_test.rb`, `Close`) |

Forty-two rows: 34 ✅, 8 🚫 (`IO-30`–`IO-36`, `IO-39`, all citing design §10.1; `IO-30`'s
behavioural clause kept as a property), 0 ⏳, 0 N/A — 34 + 8 = 42, recounted from the table. The
three things the charter assigns 3a without a new ID are built: §10.2's canonical body
representation is `Dexpace::IO::_Chunked` in `sig/dexpace/io.rbs` and `TypedReads#each`, which makes
every source one; `BufferedSource.over` with its no-ownership exception; and
`Dexpace::IO::MAX_MATERIALIZED_BYTES`. `BODY-13`'s one-helper rule is honoured ahead of 3b by
`Dexpace::StreamError.short_transfer` and `.zero_read` (`dexpace/error/stream_error_test.rb`), and
`XCUT-15`/`XCUT-18` are left satisfiable and not claimed.

## What was built

Nine new `lib/` files under `gems/dexpace-core/lib/dexpace/` — exactly the design's Module Layout:
`error/stream_error.rb`, `error/end_of_stream_error.rb`, `io.rb`, and `io/typed_reads.rb`,
`io/buffered_source.rb`, `io/typed_writes.rb`, `io/buffer.rb`, `io/buffered_sink.rb`,
`io/tee_sink.rb` — each with a `sig/` mirror that declares every method, private ones and instance
variables included, because the strict `core` Steep target checks every file and never relaxes
(phase 2's deviation 1), and each with a `test/` mirror; plus three fakes under `test/support/`
(`fake_chunked.rb`, `fake_source.rb`, `fake_sink.rb`), required explicitly by the suites that use
them. Two existing files changed as the design said: `lib/dexpace/closeable.rb` (one method body,
P3-6) and `lib/dexpace.rb` (nine `require_relative`s as one block, in dependency order, after phase
2's). Three repository-root files changed: `.rubocop/cops/dexpace/qualified_core_constant.rb`
(`SHADOWED` gains `IO`, `WATCHED` becomes the one-segment `Dexpace`, and the definition-site guard),
`.rubocop.yml` (the cop's `Include:` is `gems/*/lib/**/*.rb`) and `.rubocop/test/cops_test.rb`
(eight rejected and ten accepted rows in a second nested class, and one phase-2 row moved from
accepted to rejected). Two further files the plan did not name: `tools/rbs_surface.rb`, whose
`NFR-11` allowlist gains `EOFError`, `IOError` and `Encoding` with a fixture and a pinning test
(deviation 6 below), and the core smoke suite `test/dexpace_test.rb`, whose constant list gains the
streaming layer. The gemspec is untouched — zero `add_dependency` lines — and **3a adds no
`require` of any kind beyond `require_relative`**.

The gates, all seventeen, on **4.0.6** (`bundle exec rake`, 2026-09-15), on the tests tip: green, exit
0 — `cops:test` 100 runs / 326 assertions, `steep` no type error over the strict `core` target,
`test:gems` 783 runs / 4,669 assertions across the six gems, 766 / 4,598 of them `dexpace-core`'s,
with **99.95% line coverage (2,222 / 2,223)** against the 80% floor — the one uncovered line is the
same one phase 2 recorded, the registry claim swap's race-only branch — `test:gates` 129 runs, the
nine `gates:*` tasks, `yard` 100.00% documented (261 methods, 0 undocumented), `bundler_audit`
clean. On the code tip alone `test:gems` is 530 runs, 0 failures, 0 errors and **77.91%** line
coverage, red on the SimpleCov floor and on nothing else, since the suites that raise it are the
tests tip's; every other gate is green there. The same caveat about `rubocop` that phases 1 and 2 recorded: run
through `rake` from a worktree nested under the parent checkout's `.claude/` it inspects 9 files;
run as `bundle exec rubocop --fail-level=convention --ignore-parent-exclusion` it inspected **200
files, no offenses**, and that is the run these rows rest on (already on phase 10's inbound list).
The plan's "the whole-repository RuboCop run is not clean" finding does not hold against the built
tree: phase 0 disabled `Layout/EmptyLineAfterMagicComment` in favour of `Dexpace/SpdxHeader` and
phases 1 and 2 met every metric cop with a reasoned inline directive or a smaller method, and 3a
did the same (two `Metrics/ModuleLength` directives on the vocabularies, one `Metrics/ClassLength`
on `BufferedSource`, and `store_take`/`store_peek`/`copy_to` reshaped under `Metrics/AbcSize`).

The matrix set (`test:gems gates:gemspec_audit gates:require_allowlist gates:clean_bundle
gates:single_instance`) is green on **3.2.11**, **3.3.12** and **3.4.10** at the tests tip, each
with its own lockfile resolved fresh — 783 runs / 4,669 assertions on each, 99.95% line coverage —
and on the code tip `test:gems` on 3.2.11 is 530 runs, 0 failures, 78.74%, the floor again the only
red. Every number in this section is the round-1 tip's, re-measured after review round 0's fixes
(the round-0 tip's were 774 / 4,630, 2,218 / 2,219, 262 methods, 78.00% and 78.83%). The five interpreter-sensitive assertions Task 15 Step 6 names are green on every row:
the `StringIO`-backed BINARY read (`buffered_source_test.rb`, `Bridge`, "a StringIO-backed source
returns BINARY on every interpreter in the matrix"), the frozen-chunk ingress retag (`Over`, "over
survives a body that yields frozen literals"), the `Enumerator` `ensure` asymmetry (`Over`, "closing
an unexhausted over source leaves the wrapped body's own ensure unrun"), the two-fiber `ThreadError`
(`Threads`, "two fibers of one thread interleave reads"), and `IO.copy_stream`'s buffer reuse and
`EOFError`-subclass termination (`Bridge`, "IO.copy_stream drives a wrapped source";
`end_of_stream_error_test.rb`, "IO.copy_stream terminates on it"). A sixth, found during the build:
the block form of `module_eval` resolves a constant in the block's own lexical scope on all three
interpreters, so the `Dexpace::IO` shadow is probed with string evals (`io_test.rb`).

The surface manifest `test/fixtures/surface/dexpace-core.txt` grew from 318 to 367 lines through
`bundle exec rake surface:regenerate`, once, after Task 14, and is 366 since review round 0; the 48
added lines were read one by one against the plan's Task 15 Step 3 list and are exactly it, with
two differences stated below: `Dexpace::IO::TeeSink#clear_tap` is absent (deviation 1) and
`Dexpace::IO::BufferedSource.__dexpace_view`, present at the round-0 tip, is absent since the view
constructor became a private class method (deviation 7). `Dexpace::IO::Buffer#` carries
four names and `TypedReads#` fifteen, which is P3-8's whole reason for keeping the two vocabularies
public. No `private_constant` appears: `BufferedSource::View`, `TypedReads::READ_SEGMENT_BYTES` and
`TypedWrites::WRITE_ALL_SEGMENT_BYTES` are absent, and the three RBS interfaces carry no runtime
constant. `gates:sig_diff` still prints "no release tag yet". `gates:rbs_surface` was watched go red
on the three core names and green once admitted.

## Guards run red

Every guard the plan asks to be run red was run red, on 4.0.6, and restored; the Task 2 guard was
also run red on 3.2.11 and 3.4.10. What each said:

| Fix reverted, or not yet applied | Guard | What it said |
|---|---|---|
| `Closeable#closed?` reads `@dexpace_closed` directly (phase 2's reader) | `closeable_test.rb`, "closed? acquires the close mutex" | `ThreadError expected but nothing was raised` — the one assertion that distinguishes P3-6 from phase 2's reader on CRuby, on 3.2.11, 3.4.10 and 4.0.6 alike |
| `IO` not yet in `SHADOWED`, `Dexpace` not yet watched | `cops_test.rb`, `QualifiedCoreConstantIOTest` | 6 failures: the four `IO` rejections and the two widened-watch rejections (`Mutex` under `Dexpace`, `Queue` under `Dexpace::Http`) produced no offense. The two definition-site rows cannot fail until `IO` is shadowed, so the plan's "8" is 6 |
| `#fill_once_if_empty` back to `ensure_buffered(1)` (the pre-amendment fence) | `buffered_source_test.rb`, `Counts`; `typed_reads_test.rb` | `Expected: 4096 Actual: 1`, `Expected: [65536, 65536] Actual: [1, 1]`, and three more on the vocabulary's own count-passing assertions — the check that makes the plan's Step 4a a step |
| `Dexpace::IO::BufferedSource` absent (after Task 9, before Task 10) | `typed_reads_test.rb` | `uninitialized constant Dexpace::IO::BufferedSource` on the 20 view-dependent tests and nothing else, as the plan's Step 5 predicts |

**The Tasks 5–9 ladder**, the finished `typed_reads_test.rb` (81 runs) run against each stage's
`lib/dexpace/io/typed_reads.rb` with the rest of the finished tree:

| After task | `typed_reads_test.rb` |
|---|---|
| 5 | 81 runs, 123 assertions, **12 failures, 57 errors** |
| 6 | 81 runs, 157 assertions, **4 failures, 47 errors** |
| 7 | 81 runs, 218 assertions, **4 failures, 38 errors** |
| 8 | 81 runs, 249 assertions, **1 failure, 20 errors** |
| 9 | 81 runs, 355 assertions, **1 failure, 0 errors** |
| 10 | 81 runs, 355 assertions, **0 failures, 0 errors** |

The stage-9 failure is the transitive-invalidation test that Task 10's protocol change closes
(deviation 3); the shape is the plan's ladder, with the plan's pre-amendment counts replaced by the
built tree's.

Review round 0 (2026-09-15) found that a view's fill asked its parent to buffer `behind + count`, so
`#read_into`, `#readpartial` and `#each` on a `#peek` or `#slice` blocked until the whole count had
arrived where the root returned at once (R0-1; deviation 18). The fix landed on the code branch and
nine tests on the tests branch; the five that distinguish the two shapes were run red against the
pre-fix `ensure_buffered(behind + want)` on 4.0.6 and green on 4.0.6 and 3.2.11 after it:

| Fix not yet applied | Guard | What it said |
|---|---|---|
| the parent-side view fill back to `ensure_buffered(behind + want)` | `typed_reads_test.rb`, `ViewFills` | four failures: `Expected: 10 Actual: 13` (`#read_into` on a peek took the second chunk too), `"0123456789abc"` for `#readpartial(100)`, `"abcd"` for `#each`'s first chunk, and `Expected: 1 Actual: 2` on the slice past the buffered bytes; the two `#read(n)`/`#read_exactly` rows stayed green, as Ruby's contract says they must |
| the same | `buffered_source_test.rb`, `Views`, "a view over a live pipe returns what has arrived, like the root" | `Expected #<IO:(closed)> to not be closed?` — the peek's `read_into(count: 100)` over ten bytes returned only after the two-second watchdog closed the writer |

## Audit groups run

The phase-start pair first, at implementation: `--origin note --brief` returns 52 note entries
across 21 files, the three this phase's design filed among them; `--section conflicts --brief`
returns the six harvested conflicts, every one `[overridden by notes/…]`, and 19 note-side entries.
`--prefix-info IO` reports 42 IDs, 38 substantive, 0 roll-ups, 4 uncited; `--gaps IO` names
`IO-32`–`IO-35` as appendix-C only, and this phase read nothing for them beyond the four 🚫 rows.
`--req` was run for each task's IDs before that task; none came back a roll-up. The six groups the
design ran at planning are recorded there; at implementation the three that bite were re-checked
against the built code rather than re-run in full:

| Group | Result at implementation |
|---|---|
| Encoding and binary strings | Clean against the built code: every chunk in every store is a frozen BINARY `String`, the one ingress retag is `#store_append` (keep a frozen BINARY chunk, `#b` everything else; `force_encoding` appears only on the caller's own fresh copy in `#read_string` and `#finish_line`), `#read_into` refuses a non-BINARY destination, `#read`/`#readpartial` pin `outbuf` BINARY (P3-13), and every encoding fixture is non-ASCII |
| Fiber scheduler, thread safety | Clean against the built code: the only mutex is `Closeable`'s, acquired once per public entry point through `#closed?` and never across a fill, a drain, a `#release` or a callback; a view driving its parent acquires the parent's latch once per fill, never per byte; `Timeout.timeout`, `Thread#raise` and `Thread#kill` appear nowhere and phase 0's cop stands guard |
| Public API surface | `module-organization/1828a984` (one public constant per file) holds for the nine files; `api-design/b0e18938` is why every name arriving beyond design §3's list is in P3-8 and why `#clear_tap` was dropped rather than shipped uncalled (deviation 1); `api-design/88e6bf12` is honoured by `respond_to?` at every caller-supplied stream and no `is_a?(IO)` anywhere (`io_test.rb` pins the shadow it guards against) |

The three notes the design filed stand as written; no fourth was needed. The corpus note the plan's
Task 10 amendment implies — that `fill(1)` was a throughput defect — is a plan-level finding already
closed by the amendment and earned no note.

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate; one
widens a gate's allowlist in the correct direction (item 6) and one moves a gate test's row from
accepted to rejected (item 2).

1. **`TeeSink#clear_tap` is dropped**, taking the first of the two resolutions Task 14's
   2026-09-13 amendment names. 3b satisfies `BODY-18` by building a fresh tee per write of the
   wrapped body, which `TeeSink` binding its primary at construction forces — a retry writes to a
   different sink — so the method had no caller anywhere in core while being NFR-4-locked surface,
   and phase 5a's P5-11 (no `unwrap` method ships when nothing calls it) is the precedent. The test
   row, the fragment, the `.rbs` line and the manifest line are gone together; `tee_sink_test.rb`
   pins the absence. The design's 3a→3b contract table and P3-8 list the method; the design's "As
   built" addendum records the drop, and 3b's design (its contract row 1) and plan (its Task 10,
   which already says "3a's plan, Task 14 decides whether it stays") read the decision from here.
2. **Phase 2's accepted cop row `module Dexpace; module Transport; Thread.new` is now a rejected
   row.** The plan says the one-segment watch "subsumes phase 2's two" and lists phase 2's six
   rejections as still rejected, but does not say that phase 2's accepted case 3 — a bare `Thread`
   in an unwatched namespace — becomes an offense under it. It does, by P3-7's own rule ("inside
   `module Dexpace`, anywhere"); the row moved from `ACCEPTED` to `REJECTED` with a comment, a
   tightening and not a narrowing. Phase 3a's own rows are a second nested class,
   `CopsTest::QualifiedCoreConstantIOTest`, for the 100-line cap (phase 2's deviation 3).
3. **View invalidation cascades, and the parent-side view entry points check readability.** The
   plan's `#dexpace_invalidate` set one flag on one view, so a slice of a slice survived its root's
   close: the inner view's own flag was untouched and its reads reached through the invalidated
   outer view into the root's store — or, for a `.of_bytes` root, pulled fresh bytes from the root's
   enumerator after the root had been closed. `IO-22`'s "every outstanding slice derived from it"
   reaches a slice of a slice, so `#dexpace_invalidate` now releases the view's own views, and
   `#dexpace_fill_beyond`/`#dexpace_window_copy` call `#ensure_readable` first, so a closed
   stream-backed parent or an invalidated intermediate serves nothing to any view. Found by a test
   the plan did not have ("closing the parent invalidates a slice of a slice, transitively"), run
   red before the change.
4. **The unbounded window is `nil`, not `Float::INFINITY`.** `#peek`'s window, `View#window`,
   `#dexpace_remaining_window` and `#build_view`'s arithmetic are `Integer?` throughout, with `nil`
   meaning "no known bound"; `TeeSink`'s `tap_limit:` default is likewise `nil`, with
   `Float::INFINITY` accepted as the other spelling and any finite `Float` refused. Strict Steep
   refused the plan's `Integer | Float` arithmetic at three sites, and an `Integer?` window is the
   honest type anyway: no view ever has a fractional or infinite budget. The public signatures are
   unchanged (`#peek` takes nothing; `TeeSink.new`'s keyword keeps its name).
5. **`sig/` declares every private method and instance variable**, and the plan's partial mirrors
   are completed accordingly (`TypedReads` gains `#take_from_head`, `Buffer` gains
   `#validate_window!`, `BufferedSink` gains `#write_through` and `#check_full_write`, `TeeSink`
   gains `#forward`, `#check_full_write` and `#validated_tap_limit`, `BufferedSource` gains
   `#window_budget` and `#pull_from_upstream`); `BufferedSource::View` and the two segment
   constants are declared with a comment saying the declaration exists for Steep. Phase 2's
   deviation 1 is the precedent. Three parameters the plan typed with an RBS interface are
   `untyped` — `BufferedSource.over(chunked)`, `TypedWrites#write_all(source)` and
   `TeeSink.new(primary:)` — because an RBS interface carries only its own methods and the runtime
   check on each is a `respond_to?` duck test; `_Chunked`, `_Source` and `_Sink` stay in
   `sig/dexpace/io.rbs` as the shapes a consumer's own `steep check` can type its objects against,
   and 3b's body interface can include `_Chunked` as the design intends.
6. **`tools/rbs_surface.rb`'s `NFR-11` allowlist gains `EOFError`, `IOError` and `Encoding`**, the
   same false positive phase 1 fixed for `Data`, `ArgumentError` and `StringScanner`: three core
   Ruby names the first I/O signatures needed. The fixture `test/fixtures/gates/rbs_surface/gems/
   fixture/sig/io_superclasses.rbs` and a pinning test in `test/gates/rbs_surface_test.rb` keep
   them admitted; the gate was watched red on all three before and green after.
7. **`BufferedSource.__dexpace_view` is a `private_class_method` with a `private def self.` RBS
   declaration, reached through `send`**, where the plan's Task 10 fence defined it as a public
   singleton method called by name and the design calls the view constructor "internal — no RBS
   signature, no YARD block". Strict Steep treats an undeclared `def self.` as a diagnostic that
   fails the gate, so the declaration exists, and `tools/sig_diff.rb` reads its `private` modifier
   and keeps it out of the `NFR-4` diff; `private_class_method` keeps it out of the surface
   manifest; its comment is not a YARD block under `.yardopts`'s `--no-private`; and the caller,
   `TypedReads#build_view`, outside the class, reaches it with `send` as phase 1's `Headers#==`
   reaches `#values` — the hole design §4's P8 records, used from inside core. At the round-0 tip it
   was public with a manifest row; review round 0's R0-3 made it private before the first tag locks
   the underscore name, and `buffered_source_test.rb`, `Views` pins the absence.
8. **Test files nest a class per behaviour group** for the 100-line cap (phase 2's deviation 4):
   `typed_reads_test.rb` (`Rejections`, `Typed`, `Charsets`, `Ceiling`, `Lines`, `Bridge`, `Each`,
   `Views`, `ViewFills`, `ViewLifecycle`, `Includer`), `buffered_source_test.rb` (`Bridge`, `Over`,
   `Close`, `Threads`, `Counts`, `Views`), `typed_writes_test.rb` (`WriteFrom`, `Pump`, `Charsets`,
   `Includer`),
   `buffer_test.rb` (`Snapshot`, `CopyTo`, `Close`), `buffered_sink_test.rb` (`Staging`, `Close`),
   `tee_sink_test.rb` (`Failure`, `Lifecycle`, `Vocabulary`), each over a shared factory module.
9. **`store_take` and `store_peek` are reshaped under `Metrics/AbcSize`**: `#take_from_head` is
   the one byteslice-and-advance step both `store_take` paths share, and `store_peek` walks with a
   running skip instead of a position and a start; `Buffer#copy_to`'s window check is
   `#validate_window!`. The plan predicted these two offenses and left them for phase 0's baseline;
   the baseline is clean, so they were fixed here.
10. **`fill` in `BufferedSource` is split** into `#pull_from_upstream` (the one `rescue ::EOFError`,
    around both `#readpartial` and `#read`) and `#fill_from_upstream`, and `#fill_from_parent`
    takes the view as an argument; `BufferedSink#push_one_level` and `TeeSink#deliver` write
    through a one-line `ensure`-wrapped method (`#write_through`, `#forward`) so Steep can see the
    result's type, with the short-write check in `#check_full_write` on each. Behaviour is the
    plan's.
11. **`require_relative` lines the plan's fences omit** — `error/seam_error` in both vocabularies,
    `error/stream_error`, `error/invalid_argument_error` and `error/closed_error` where each is
    raised — are present, so every file names what it raises; the require audit sees only
    `require_relative`.
12. **Run counts exceed the plan's.** The `IO` suites — `io_test.rb` and the six files under
    `test/dexpace/io/` — are 240 runs since review round 0 (231 before its nine; the 245 first
    written here was not this seven-file count) where the plan's built-tree run was 209 for the
    whole tree, because the nested classes carry extra cases the plan did not have
    (the readability checks, the count-passing guards on the vocabulary's own side, the pipe-end
    sink, the transitive invalidation, the consumer-side shadow probe); the plan's step-level
    expected counts ("PASS, 14 tests", "PASS, 3 tests") are therefore not matched and were not
    meant to be. Two of them could not have held as written: Task 4's `io_test.rb` pins the whole
    constant list, which is complete only after Task 14, and Task 5's negative-count test calls
    `#read_exactly`, which Task 6 adds.
13. **The plan's expectation for the segment guard's second assertion is `[65536, 65536]`, not
    `[65536]`**: `#each` asks the upstream once for the chunk and once more to find the end, and
    the plan's fake raises on the second ask after recording it. The fill-count assertion on the
    vocabulary side counts probes the same way.
14. **The `Dexpace::IO` shadow is probed with string evals.** The plan's io_test has no such test;
    the one written first used `Dexpace.module_eval { IO }`, which resolves `IO` in the block's own
    lexical scope — to `::IO` — on 3.2.11, 3.4.10 and 4.0.6 alike, and was caught by the floor run
    after Task 12 (the first run of that file on any row after Task 4). `module_eval("IO", __FILE__,
    __LINE__)` and a consumer class's `class_eval` state exactly the design's finding, both
    halves. Since review round 0 (R0-4) each probe evals a lambda, `->(x) { x.is_a?(IO) }`, in the
    receiver's scope and hands it the pipe end the test creates and closes in its `ensure`, where
    the first shape created an `IO.pipe` inside the eval'd string and never closed it.
15. **`Buffer#snapshot` reuses `TypedReads#guard_materialization!`** rather than a private
    `#ensure_snapshot_within_ceiling` of its own, so the six guarded sites share one message form.
16. **The entry file's nine `require_relative`s are one block appended after phase 2's**, in
    Task 15's dependency order, where Task 3 said "immediately after `error/cancelled_error`"
    (phase 2's deviation 15, again).
17. **`rbs:validate` was red between Tasks 5 and 10 and between Tasks 11 and 12 on the wip branch**,
    on the forward references to `Dexpace::IO::BufferedSource` and `Dexpace::IO::Buffer` that the
    plan's own signatures carry; the plan's per-task "then `rake rbs:validate steep`" cannot pass
    there. Steep was green at every task where `rbs:validate` was.
18. **A view's fill is one fill past its position, never a loop to the count** (review round 0,
    R0-1). The plan's Task 10 fence for `#fill_from_parent` called
    `parent.dexpace_ensure_buffered(behind + want)`, whose loop blocks until the whole count is
    buffered — the shape the same task's 2026-09-13 amendment forbids for the root ("must **not**
    become `ensure_buffered(count)`") and the design's R2 ("fills ONCE") and R4 ("keeps the bridge
    claim true of views") rule out. Measured: a peek over an `IO.pipe` holding ten bytes with the
    writer open hung on `read_into(count: 100)` and `readpartial(100)` where the root returned the
    ten at once. As built the parent-side entry point is `#dexpace_fill_beyond(behind, want)`,
    replacing `#dexpace_ensure_buffered`: fill until at least one byte past `behind` is buffered or
    the upstream is done, each fill asking the upstream for the rest of what the view wants, and
    the view takes what is there up to `want`. `#read(n)` and `#read_exactly(n)` on a view still
    fill to `n` through the view's own `#ensure_buffered` loop, which is Ruby's contract. The
    protected declaration in `sig/dexpace/io/typed_reads.rbs` follows; guard run red above.
19. **Two `.rbs` declarations are wrapped** (R0-5): `buffered_source.rbs`'s view constructor and
    `#initialize` lines were 127 and 105 columns against the plan's 100-column rule, which RuboCop
    does not read for `.rbs`; both now take the multi-line parameter shape phase 2's
    `registry.rbs` and `operation.rbs` use. `async_transport.rbs:17`, 105 columns since phase 2, is
    not this phase's and is left as it is.

## Findings routed

- **The plan's RuboCop-baseline finding does not reproduce** against the built tree (see "What was
  built"); nothing to route, and phase 0's plan, Task 3 gains no item from here.
- **3b's design (contract row 1) and P3-8 name `TeeSink#clear_tap`, which no longer exists** —
  recorded in the design's "As built" addendum (this phase may write it) and read by 3b's Task 10
  from there; 3b's own documents are not edited by this phase.
- **Phase 2's cop row flipped** (deviation 2) — in material this phase may write; fixed in place.
- **The RBS interfaces cannot type a duck-checked parameter** (deviation 5) — a Ruby fact about RBS,
  not a finding against any gate; recorded in the sig comments where a later phase meets it.
- **`rake rubocop` is vacuous in a worktree nested under the parent checkout's `.claude/`** —
  already on phase 10's inbound list from phase 1; the honest run is recorded above.
- **Review round 0's five findings** (2026-09-15) were each in material this phase may write and
  were fixed in place, on the branch that owns the file: R0-1 (a view blocked to the count; deviation
  18), R0-3 (the view constructor was public surface; deviation 7) and R0-5 (two `.rbs` lines over
  100 columns; deviation 19) on the code branch, R0-4 (the shadow probes leaked a pipe pair each;
  deviation 14) on the tests branch, and R0-2 on the docs branch: `docs/sdk-documentation/io.md`'s
  views example claimed the final `slice.read` raised `Dexpace::ClosedError` when the built code
  returned `""`, because the slice had already pulled its whole window and P3-5's "behind" failure
  needs a byte still unread; the example now leaves one, and was re-run on 4.0.6 and 3.2.11. Nothing
  was routed elsewhere.

## Postponed work

The one item the design postponed keeps its owner: exercising `IO-38` on a Ruby without a GVL is
`docs/first-release.md` § Post-release triggers, cited at `IO-38`'s row. The items earlier phases
postponed were re-read on 2026-09-15 and keep the owners the design's "Work Phase 3a Postpones"
section records — `close_quietly`'s two routes (phase 4b, Task 2; phase 5b, Task 14), the
`deadline:` keyword (phase 5a, Task 8), the fakes' move (declined by phase 8a; three more doubles
strengthen the case without meeting the condition), `Hooks.notify`'s dropped failures (phase 4b,
Task 2), `SEAM-25`'s lifecycle event (phase 8b, Tasks 6 and 10; phase 9, Task 11), the body
member's type and `HTTP-46` (3b, P3-15). The unbounded `#read_line_utf8` stays with phase 7b's plan,
Task 12; the `include Dexpace` shadow's documentation half is now written in
`docs/sdk-documentation/io.md` and its release-decision half stays under `docs/first-release.md`
§ Blockers before first publish; the `IO-6` appendix-C finding stays with the roadmap's gap
paragraph. The implementation postponed nothing further.
