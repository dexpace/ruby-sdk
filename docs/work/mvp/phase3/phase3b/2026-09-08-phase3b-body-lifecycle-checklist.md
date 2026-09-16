# Phase 3b — Body Lifecycle: Checklist

**Written at execution time, 2026-09-16, from what was built** — not from the plan. A row whose task
did not do what the plan said is a row that says so, and the "Deviations from the plan" section
below is where each departure is stated with its reason. The plan and design were written on
2026-09-08 against phase 3a's *plan*; 3a was built and merged on 2026-09-15 with nineteen
departures of its own, and where the two disagree the built tree wins and this document records it.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle.md`. Task numbers are that
plan's. Design: `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md`, whose
Deviation Ledger rows `P3-n` are cited below; the charter is
`docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md`. Every test file named here is
under `gems/dexpace-core/test/`, mirrors its `lib/` file one for one, and opens with the IDs it
exercises.

## Requirement rows

Forty-nine own rows — `BODY-1`–`BODY-37`, `HTTP-36`–`HTTP-45`, `HTTP-51`, `HTTP-52` — plus the two
cross-reference rows the design names, `HTTP-46` and `HTTP-3`, whose IDs are phase 1's and whose
body-side clauses only this phase could discharge.

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `BODY-1` | MUST | ✅ | 1 | `Dexpace::Body#replayable?` defaults to `false`; every variant that answers `true` earns it — `BytesBody`, `BufferBody`, `FileBody`, `FormBody` unconditionally, `StreamBody` under `BODY-9`'s four conditions, `MultipartBody` as a conjunction — and `ChunkedBody` cannot be told to (P3-19). The property phase 6's three gates will read (`dexpace/http/body_test.rb`; each variant's suite) |
| `BODY-2` | MUST | ✅ | 7 | `MultipartBody#replayable?` is `parts.all?(&:replayable?)` and `#content_length` collapses to `-1` if any part's is unknown; both asserted with a mixed part list, and the disjunction and the missing collapse each run red in the battery (`dexpace/http/body/multipart_body_test.rb`, `FramingTest`) |
| `BODY-3` | MUST | ✅ | 1, 2 | `Dexpace::Body#to_replayable` returns `self` when already replayable and otherwise drains `#write_to` once into a `Dexpace::IO::Buffer`, returning a `BufferBody`; the write count is asserted at 1 and the original is left consumed by its own latch (`dexpace/http/body_test.rb`; `dexpace/http/body/buffer_body_test.rb`) |
| `BODY-4` | MUST | ✅ | 1 | The one `#replayable?` property the three paths consult, with the three declines documented at `Dexpace::Body`'s YARD and deliberately not unified — retry stops, auth returns the challenge unchanged and unclosed, redirect raises. **The three call sites are phase 6's**, in three places (6a, 6b, 6c), because the requirement says a port need not unify them; 3b builds no gate and no predicate |
| `BODY-5` | MUST | ✅ | — | Cross-reference: phase 1 shipped `Dexpace::Method#idempotent?`; the retry-only gate that reads it is phase 6a's. Nothing here to build, stated so the ID has a row in the chapter that owns it |
| `BODY-6` | MUST | ✅ | 1, 4, 5, 8 | `Dexpace::Body#claim_single_use!` raises `Dexpace::StreamError` naming `BODY-6` on a second write; used by `StreamBody`'s single-use path, `ChunkedBody` and `ResponseBody`, each with its own second-write test, and an owned stream body refuses before touching the closed stream (`dexpace/http/body/stream_body_test.rb`, `LatchTest` and `OwnershipTest`; `chunked_body_test.rb`, `LatchTest`; `response_body_test.rb`) |
| `BODY-7` | MUST | ✅ | 4, 5 | The latch is a `Thread::Mutex` held across the flag flip and nothing else; eight threads released together through a `Thread::Queue` on one single-use `StreamBody` and on one `ChunkedBody` — exactly one passes, seven see the same `Dexpace::StreamError`. A separate row and a separate proof from `BODY-6`, as the design asks (`stream_body_test.rb`, `LatchTest`; `chunked_body_test.rb`, `LatchTest`) |
| `BODY-8` | MUST | ✅ | 4, 5, 6, 8 | The body layer's rule, recorded rather than re-decided (design §10.12): a body closes exactly the sources it opened. `StreamBody` closes nothing by default and closes the stream as part of its one write — on a failed write too — only under `close: true`; `ChunkedBody` closes nothing and does not look for `#close`; `FileBody` closes the handle it opened per write; `ResponseBody` owns its source. `close: true` forces single-use, which is `BODY-8`'s own "the rewindable variant must keep it open to replay" (plan decision 6) (`stream_body_test.rb`, `OwnershipTest`; `chunked_body_test.rb`; `file_body_test.rb`, `HandlesTest`) |
| `BODY-9` | SHOULD | ✅ | 4 | Implemented, not vacuous (R9, P3-16). "Supports mark/reset" is seekability probed once at construction with `pos` then `seek(pos)` inside `rescue ::SystemCallError`, guarded by `respond_to?(:pos) && respond_to?(:seek)`; a **real** `IO.pipe` raises a **real** `Errno::ESPIPE` and stays fully readable, a `StringIO` and a `Tempfile` are no-ops. Replayable when rewindable **and** the length is known **and** at most `MAX_MATERIALIZED_BYTES` **and** ownership was not transferred; replay rewinds to `#origin`, never 0, asserted over a handle pre-positioned at byte 4. The race-safe rewind is a second flag under the same mutex: two writes made to **overlap** through a parking sink, the second refused naming `BODY-9`, the seek delta exactly 1 (`stream_body_test.rb`, the probe rows and `LatchTest`) |
| `BODY-10` | MUST | ✅ | 1, 4, 8 | `Dexpace::Body#copy_exactly(source, sink, count)`: exactly `count` bytes, `StreamError.short_transfer` naming delivered-of-total on a premature end, `StreamError.zero_read` for a zero-length read on a positive request without spinning (one call, asserted), a declared length of 0 as an empty write; driven from `StreamBody`, `BufferBody` and `ResponseBody` (`body_test.rb`, `CopyTest`; `stream_body_test.rb`, `CopyTest`) |
| `BODY-11` | MUST | ✅ | 6 | Six construction clauses, six tests — a missing path, a directory, the null device, a negative offset, an offset past the size, a count past the size — each a `Dexpace::InvalidArgumentError` naming the argument, plus a nil path with `SEAM-29`'s one message form; a fresh `::File` handle per write (eight threads draining one body share no cursor; the caller's own handle is undisturbed), closed on every exit, with `/proc/self/fd` counted across twenty failing writes (`file_body_test.rb`) |
| `BODY-12` | SHOULD | ✅ clause 1 / ⏳ clause 2 | 6 | Clause 1 is **implemented** (P3-17): `::IO.copy_stream(handle, sink, count, offset)`, whose window, return value and cursor behaviour were re-verified on 4.0.6 before Task 6. Clause 2 — the transport's zero-copy dispatch — stays ⏳ with `TRANSPORT-28`'s zero-copy clause: declined by phase 8a's design (R5), stated in `docs/first-release.md` § What v1 ships without, the `BODY-36`/`BODY-12` entry; this side ships `#path`, `#offset` and `#count` and deliberately **no `#to_path`**, asserted (`file_body_test.rb`, `WindowTest`) |
| `BODY-13` | MUST | ✅ | 1, 6 | One message form across both copy routines and the file transfer: `emit_exactly`'s sink short-write check and `FileBody#write_to`'s `copy_stream` return check both raise `StreamError.short_transfer(transferred:, expected:)`, 3a's helper; a file truncated after construction raises naming 4 of 10 rather than sending a short body (`bytes_body_test.rb`; `chunked_body_test.rb`; `file_body_test.rb`, `HandlesTest`) |
| `BODY-14` | MUST | ✅ | 8 | `ResponseBody#source` is the same handle every call (`assert_same`), the body is not replayable, and a second `#write_to` raises `BODY-6` rather than emitting nothing; `#to_replayable` is the explicit buffering wrapper. The handle is checked at construction as the `BufferedSource` vocabulary the class uses — `#read_into` **and** `#peek` — so a bare `_Source` is refused by name rather than failing on its first preview (review round 0, R0-5; deviation 21 below) (`response_body_test.rb`) |
| `BODY-15` | MUST | ✅ | 8 | `#close` is `Closeable`'s latch releasing the wrapped source — a `StringIO` under `BufferedSource.wrapping` is closed — idempotent, and assuming nothing about whether the body was read; a read on the source after close raises `Dexpace::ClosedError` (`response_body_test.rb`) |
| `BODY-16` | MUST | ✅ | 8 | `Response#body_string` and `#body_bytes` close the body in an `ensure`, asserted on the success path and with the source closed beforehand so the read raises `Dexpace::ClosedError` and the body is still closed. Both readers share one private `#read_through`, which closes the **handle `#source` returned** first, in its own `ensure`, and the body after it whatever the first close did — for a `ResponseBody` the same idempotent stream close, for a `BufferBody` or a fits-cap `ResponseLoggingBody` the fresh `#peek` view neither body's `#close` reaches, for the over-cap composite the `Tail`'s close and its prefix view. Twenty reads over each leave zero views registered, and a handle whose close raises still leaves the body closed (review round 0, R0-1; deviation 17 below) (`dexpace/http/response_test.rb`, `FinallyTest` and `SurfaceTest`) |
| `BODY-17` | MUST | ✅ | 10 | `RequestLoggingBody#write_to` builds a `Dexpace::IO::TeeSink` over the transport's sink and writes the delegate through it once: the primary receives every byte, the tap the exact bytes, the delegate's write count is 1, and the full payload reaches the primary under a cap of 2 (`request_logging_body_test.rb`) |
| `BODY-18` | MUST | ✅ | 10 | Satisfied by construction with a **fresh tee per write** — two writes of a replayable delegate leave exactly one payload in the snapshot and a different `@tee` object each time. This is why 3a shipped `TeeSink` without `#clear_tap` (3a's checklist, deviation 1); the plan's "3a's plan, Task 14 decides" is decided, and nothing here calls it (`request_logging_body_test.rb`, `AttemptsTest`) |
| `BODY-19` | MUST | ✅ | 10 | `tap_limit:` defaults to `::Float::INFINITY`, which `BODY-19`'s own text states for direct wrapper use, and is validated at construction with the tee's rule (P3-18); a cap of 4 stops the tap at 4 while the primary gets everything, a cap of 0 mirrors nothing (`request_logging_body_test.rb`) |
| `BODY-20` | SHOULD | ✅ | 10 | `@tee` is bound before the delegate runs and the tee mirrors before it forwards (`IO-27`): a delegate that fails after one chunk leaves that chunk in `#snapshot`, and a primary that raises mid-stream leaves the failing chunk captured. `FakeBody`'s `fail_after:` is the deterministic route (`request_logging_body_test.rb`, `AttemptsTest`) |
| `BODY-21` | MUST | ✅ | 10 | `#replayable?` is the delegate's verbatim; `#to_replayable` returns a `RequestLoggingBody` over the delegate's replayable form (a `BufferBody`) with the cap preserved, and `self` when the delegate is already replayable (`request_logging_body_test.rb`, `ReplayTest`) |
| `BODY-22` | MUST | ✅ | 11 | The drain runs at most once, lazily, on the first `#source`, `#snapshot` or `#error` — each trigger asserted through a drain-counting delegate; eight threads' first accesses drain once; two fibers of one thread interleave the drain without a `ThreadError`, which a mutex held across the drain raises (battery row 40 saw it). The `preview_bytes:` keyword is required (P3-18) (`response_logging_body_test.rb`; `SerializationTest`; `ConstructionTest`) |
| `BODY-23` | MUST | ✅ | 11, 13 | Fits-cap: the whole body captured, the delegate closed as part of the capture, every `#source` a fresh non-consuming `#peek` view succeeding independently; a body exactly the cap's size is a complete capture. The drain asks the delegate for `#source` **once** and holds that handle: over a `BufferBody` delegate — inside the wrapper's stated contract, and answering a fresh view per call (P3-23) — the fill's view is closed by the wrapper's own close, so the delegate's registry is empty afterwards and the copy still reads (review round 1, R1-1; deviation 22 below). Task 13 measured what one view per read costs (below) (`response_logging_body_test.rb`, and `DelegateHandleTest`) |
| `BODY-24` | MUST | ✅ | 11 | Over-cap: the prefix buffered, the delegate left open, `#source` a `BufferedSource.wrapping` over the private `Tail` replaying prefix, probe byte and live tail so the consumer gets the whole body, and a second `#source` raising `Dexpace::StreamError` naming `BODY-24`. The regime probe reads one byte past the cap and keeps it **outside** the capture, so the snapshot is exactly the cap (plan decision 9; battery row D9). The live tail is forwarded through **`#read_into`**, one fill, and not through the delegate source's `#read(count)`, which fills to the count or EOF: over a real `IO.pipe` with the writer held open, a `readpartial(1000)` on the tail returns the seven bytes that are there, joined with a five-second timeout — the composite is the consumer's real byte path, and a still-open connection is delivered as it arrives (review round 0, R0-3; deviation 19 below). That keeps the delegate's source contract at `_Source`'s single method, asserted with a `#read_into`-only recorder. The tail continues from the **one** handle the drain took, not from a fresh `#source`: over a `BufferBody` delegate, whose every `#source` starts at byte zero, three asks delivered `"012300123456789"` for a ten-byte body — through `Response#body_bytes` too — and one ask delivers it once; a fresh-view double sees `#source` asked exactly once in either regime and never on an undrained close (review round 1, R1-1; deviation 22 below) (`response_logging_body_test.rb`, `TailTest` and `DelegateHandleTest`; `response_test.rb`, `SurfaceTest`) |
| `BODY-25` | MUST | ✅ | 1, 11 | A zero read for a positive count is `StreamError.zero_read` naming `IO-17`, never EOF — in `copy_exactly`, in the drain's `fill_prefix` and on the over-cap tail's forward to the delegate — and the bytes read before it are retained; `FakeSource` is the only thing that produces it (`body_test.rb`, `CopyTest`; `response_logging_body_test.rb`, `FailureTest` and `TailTest`) |
| `BODY-26` | MUST | ✅ | 11 | A mid-drain failure keeps the bytes read and caches the error: `#source` re-raises the **same object** with its `#cause` and backtrace intact (`assert_same`), `#snapshot` returns the partial bytes without raising, `#error` returns it without a second drain and `nil` after a clean one; the failed drain leaves the delegate open for the wrapper's own close (`response_logging_body_test.rb`, `FailureTest`) |
| `BODY-27` | MUST | ✅ | 11 | One close-once guard, `Closeable`'s latch: the wrapper's own close, the capture path's best-effort close and the over-cap tail's close all reach it. Closing the tail closes the delegate once and marks the wrapper closed; wrapper-then-tail and tail-then-wrapper are each one close; a delegate whose close raises is still marked closed and the failure propagates once, from four threads too. The tail is `.wrapping`-owned and its `#close` calls the wrapper's, which is why `.over` was rejected (R10). `#release` closes the handle the drain took **ahead of** the delegate, the delegate's close in an `ensure`: a handle whose close raises still leaves the delegate closed, the failure propagates once, and after a full capture it is not a drain error either (review round 1, R1-1) (`response_logging_body_test.rb`, `CloseTest` and `DelegateHandleTest`) |
| `BODY-28` | MUST | ✅ | 11 | On the fits-cap path the delegate close is `Dexpace.close_quietly(self)` — its **first call site in the SDK** — so a raising close is not a drain error and the body is still served; the captured buffer survives the wrapper's close (`#snapshot` and `#source` still answer) and `#release` deliberately does not close it, pinned directly on both regimes; a view taken before the close reads after it. The opposite direction: the over-cap tail raises `Dexpace::ClosedError` after the wrapper's close (`IO-42`) (`response_logging_body_test.rb`, `CloseTest`) |
| `BODY-29` | SHOULD | ✅ | 11 | `#content_length` is the captured size only when the capture was complete — even when the delegate declared none — and the delegate's declared length for a prefix; it never triggers a drain, which is what lets the fiber proof terminate (`response_logging_body_test.rb`, `LengthTest`) |
| `BODY-30` | MUST | ✅ body half | 9 | `Dexpace::Body.buffer_bounded(body, cap:)` drains through `#source` into a `Dexpace::IO::Buffer`, stops asking at the cap, closes the original in an `ensure` — on a raising drain too — and returns a `BufferBody` readable independently and repeatably; the allocating test drains a 2 MiB body and asserts the bytes beyond 1 MiB were **not** pulled. The handle `#source` returned is closed in its own `ensure` before the original is — the view a `BufferBody` or a fits-cap wrapper hands out, deregistered; twenty copies over each leave zero views registered — guarded with `respond_to?` because `_Source` declares no `#close` (review round 0, R0-1; deviation 18 below). "A response with no body is returned unchanged" is phase 4's step, `Recovery.buffer_error_body` (4b) (`body_test.rb`, `BufferBoundedTest` and `BufferBoundedHandlesTest`) |
| `BODY-31` | MUST | ✅ | 9 | Cross-reference: the 4xx/5xx predicate is phase 1's `Status#error?`, the step that reads it is phase 4's; 3b's contribution is the negative guarantee — `buffer_bounded` takes a body and a cap and no status, and no executable line of `body.rb` mentions one — asserted mechanically (`body_test.rb`, `BufferBoundedTest`) |
| `BODY-32` | MUST | ✅ | 1, 8, 9 | `Dexpace::Body.clamp_cap`: a negative cap is `Dexpace::InvalidArgumentError`, a cap over `MAX_MATERIALIZED_BYTES` (and `::Float::INFINITY`) is silently clamped down, and `ResponseBody#preview` returns whatever exists up to the clamped cap — a 40-sample property over negative, zero, huge and ceiling+1 caps. "Silently clamp **down**" has no symptom on a ten-byte fixture, so it is proven by the **count the first read asks the stream for**: `buffer_bounded` over the `FakeSource`-backed double and `#preview` over a `#readpartial`-recording stream under `.wrapping` each ask for exactly the ceiling under caps of ceiling+1, ceiling×2 and `::Float::INFINITY`, and for 7 under a cap of 7. Deleting the clamp survived round 0's suite and fails one row in each of the two suites now; the `.max` spelling fails five in each (review round 0, R0-2). The capless half is 3a's `Buffer#snapshot` (`response_body_test.rb`, `PreviewTest`; `body_test.rb`, `BufferBoundedTest` and `BufferBoundedHandlesTest`) |
| `BODY-33` | SHOULD | ✅ | 8 | `ResponseBody#preview(cap:)` reads through a fresh `#peek` view closed in an `ensure`, does not advance the primary path, returns `""` when exhausted, and leaves no view registered after twenty calls; "null when there is no body" is the caller's `nil` check, phase 4's (`response_body_test.rb`, `PreviewTest`) |
| `BODY-34` | MUST | ✅ parameter half / ⏳ source and predicate | 10, 11 | The parameter shape lands: both wrappers take a cap, so one value can drive both. The shared **source** and the enablement **predicate** are phase 5's — 5a Task 13 (`docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration.md`) and 5b Tasks 14–15 (`docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction.md`); the predicate is met structurally today, asserted: nothing under `lib/` constructs either wrapper (`request_logging_body_test.rb`, `SurfaceTest`; `response_logging_body_test.rb`, `ConstructionTest`) |
| `BODY-35` | MUST | ✅ | 1, 5, 6, 7 | `-1`, never `nil`, as the module default; exact where known — `BytesBody` and `FormBody` from their encoded bytes, `FileBody` from the resolved window, `MultipartBody` from the framing routine — and `-1` carried through `StreamBody` and `ChunkedBody` when unknown; the form encoder is the `+`-for-space one beside the RFC 3986 encoder (Task 3) (`body_test.rb`; each variant's suite; `percent_encoding_test.rb`, `FormTest`) |
| `BODY-36` | MAY | ⏳ | — | No memory-mapped view: Ruby's standard library has no `mmap`, and both routes to one — a C extension or the `mmap` gem — are barred from core by `SEAM-1`/`NFR-1`. Owner: `docs/first-release.md` § What v1 ships without, the `BODY-36`/`BODY-12` entry; condition: core's dependency budget changes, which no phase in v1 can meet |
| `BODY-37` | MUST | ✅ | 10 | One mechanism with `IO-28`, not two: the wrapper exposes no `#buffer`, and the tee's own `#buffer` raises naming `IO-28`; design §10.10's honest position — `instance_variable_get` reaches anything — is restated and not exceeded (`request_logging_body_test.rb`, `SurfaceTest`) |
| `HTTP-36` | MUST | ✅ | 1 | `Dexpace::Body`: `#write_to(sink) -> Integer` the one hook, `#media_type` nullable, `#content_length` with the `-1` sentinel, `#replayable?`; an includer that defines no `#write_to` raises `NotImplementedError` naming it (`body_test.rb`) |
| `HTTP-37` | MUST | ✅ | 1, 2, 4, 5, 8 | The second-write guard (`BODY-6`/`BODY-7` above) and materialize-once (`BODY-3` above), on every single-use variant including `ResponseBody` (`stream_body_test.rb`; `chunked_body_test.rb`; `response_body_test.rb`; `body_test.rb`) |
| `HTTP-38` | MUST | ✅ | 1, 2, 3, 4, 5, 6, 7 | Eight factories over seven classes, in one place, each classifying by source — `.bytes`/`.string` replayable (`.string` encoding eagerly, plan decision 3), `.buffer` and `.file` replayable, `.stream` conditional under `BODY-9`, `.chunked` single-use, `.form` replayable and `x-www-form-urlencoded` with `+` for space, `.multipart` a conjunction; the factory table is asserted complete. The **serialized-object** clause has no subject until a codec exists and is phase 7a's, Task 9 (`Body.serialized`) (`body_test.rb`, `FactoriesTest`; `form_body_test.rb`; `percent_encoding_test.rb`, `FormTest`) |
| `HTTP-39` | MUST | ✅ | 1, 4 | `copy_exactly` writes exactly the declared count and raises on a premature end (`BODY-10` above); a `StreamBody` with a declared length shorter than the stream writes that many and no more (`body_test.rb`, `CopyTest`; `stream_body_test.rb`, `CopyTest`) |
| `HTTP-40` | MUST | ✅ | 6 | `FileBody`'s six fail-fast clauses, replayability, fresh handle per write and exact byte count — `count: nil` resolves to the rest of the file against the size captured at construction, so `#count` is always an `Integer` (`file_body_test.rb`) |
| `HTTP-41` | MUST | ✅ | 8 | `ResponseBody`: single-use with the same source every call, an explicit idempotent close releasing the transport stream whether or not the body was read, and both convenience readers closing the handle and then the body in an `ensure` (`BODY-14`, `BODY-15`, `BODY-16` above) (`response_body_test.rb`; `response_test.rb`, `FinallyTest` and `SurfaceTest`) |
| `HTTP-42` | MUST | ✅ | 8 | `Response#body_string`, the one decode boundary, in three steps: `Response.resolve_charset` reads `MediaType#charset` (`nil` for absent **or** unknown, so `Encoding.find` cannot raise) and falls back to UTF-8; 3a's `#read_string(encoding)` **retags**; `#encode(encoding, invalid: :replace, undef: :replace)` transcodes with the target **named**. Non-ASCII fixtures throughout; ISO-8859-1 honoured; mismatched bytes scrubbed; a 48-sample property with a hostile `Encoding.default_internal` on half the runs. Both mutations of the recipe were seen red (below). §3.1's own sentence is on phase 10's inbound list (`response_test.rb`, `DecodeTest` and `DecodeGlobalTest`) |
| `HTTP-43` | MUST | ✅ | 8 | `Response#close` is `body&.close` and nothing else — a `Data` instance is frozen and holds no latch, and the requirement delegates idempotence to the body's — asserted on a bodyless response, on a double close, and on a request-body variant in the slot, whose `#close` is the no-op default (`response_test.rb`, `CloseTest`) |
| `HTTP-44` | MUST | ✅ | 12 | `TypedResponse`: `#status`, `#headers`, `#protocol`, `#reason`, `#request` and `#response` forwarded without running the handler or touching the body; `#value` runs the handler at most once and memoises the outcome through an explicit state machine — a `nil` success and a `false` success each run it exactly once by count, a failure is re-raised as the same object with its `#cause` and backtrace; the `@value ||=` mutation fails six tests (`typed_response_test.rb`) |
| `HTTP-45` | MUST | ✅ | 12 | Eight threads' first accesses run the handler once and get one object, and one exception object when it raises; a fiber suspended mid-parse does not block a second fiber's raw accessor; a thread holding the parse mutex does not block a raw accessor, joined with a five-second timeout; a handler raising outside `StandardError` still settles the state so no later caller hangs. The P3-27 residue is stated at the method (`typed_response_test.rb`, `SerializationTest` and `SettlementTest`) |
| `HTTP-51` | SHOULD | ✅ | 7 | One framing routine, `#emit`, for the bytes and — with `count_only: true` (P3-29) — the length, proven as a 48-sample property (declared length equals bytes written) and after several writes of the memoised value; a `SecureRandom` boundary of 48 alphanumerics, a caller boundary validated against RFC 2046's 1–70 `bcharsnospace` at both ends and the specials; the one MUST as two mechanisms — `"` and `\` escaped, CR/LF **rejected** — with every assembled header line swept by phase 1's outbound grammar, so a part header value with a `\r` is refused too; a subtype validated as one bare token. **Stated limitation:** that grammar admits no byte at or above `0x80`, so a non-ASCII part name or filename must be percent-encoded by the caller (routed below) (`multipart_body_test.rb`) |
| `HTTP-52` | MUST | ✅ body half | 9 | `buffer_bounded` at `MAX_BUFFERED_ERROR_BODY_BYTES`, 1 MiB fixed by the requirement and taking no keyword, dropping bytes beyond the cap markerlessly, buffering inside the original's close scope, and exposing a `BufferBody` readable more than once; driven over a `ResponseBody`, a `ResponseLoggingBody` in both regimes and a `BufferBody` — the three bodies that can occupy `Response#body` — because the drain is `#source`-shaped (P3-23's write-side half). The error-mapping path that calls it is phase 4b's (`body_test.rb`, `BufferBoundedTest`; `response_test.rb`, `SurfaceTest`) |
| `HTTP-46` | MUST | ✅ | 1, 2, 5, 6, 7, 10, 14 | Cross-reference; the ID is phase 1's. The body half of by-value request equality now has a subject: `Dexpace::Body` defaults `#==`, `#eql?` and `#hash` together to **identity** (right for every variant holding a live stream), and `BytesBody`, `BufferBody`, `FileBody`, `FormBody`, `MultipartBody`, its `Part` and `RequestLoggingBody` override all three over the facts that fix their bytes — for `MultipartBody` the boundary, the **subtype** and the parts, since the subtype fixes the `Content-Type` on the wire; two bodies over the same parts and boundary as `form-data` and as `mixed` are different values and hash apart (review round 0, R0-4; deviation 20 below). Two requests over equal `BytesBody` values are equal and hash equal, a request works as a `Hash` key, and two over different stream bodies do not compare equal (`request_test.rb`; each variant's suite) |
| `HTTP-3` | MUST | ✅ | 7 | Cross-reference; the ID is phase 1's, whose builder-based list names "the multipart body", a subject phase 1 did not have. `MultipartBody#new_builder` returns a `MultipartBody::Builder` pre-filled with the parts, boundary and subtype, and the parts list is a `dup` so a builder mutation cannot reach the frozen body's list; a builder with nothing set builds an empty body. Design §4's omission of the subject is on phase 10's inbound list (`multipart_body_test.rb`) |

Fifty-one rows, forty-nine of them this phase's: 46 ✅ outright (two of them the cross-reference
rows), 4 ✅ in part with the remainder ⏳ and its owner named — `BODY-12` clause 2, `BODY-34`'s
source and predicate, and `BODY-30`'s and `HTTP-52`'s response-side clause, which is phase 4's step
— 1 ⏳ (`BODY-36`), 0 🚫, 0 N/A: 46 + 4 + 1 = 51, as the status cells have it (review round 1's
R1-2 corrected a "3 in part" that counted the two body-half rows as one). The design's "47
implemented, 2 postponed" is met with `BODY-12`'s first clause counted as implemented, as the design
itself splits it, and the other three partial rows counted with the implemented, as the design
counts them. Recounted from the table. `IO-42`'s asymmetry, `IO-28`
↔ `BODY-37`, `IO-40`'s clock and `IO-37`'s single-threaded contract are honoured as boundaries
rather than claimed as rows; `XCUT-15` and `XCUT-18` are left satisfiable and unclaimed.

## What was built

Twelve new `lib/` files under `gems/dexpace-core/lib/dexpace/http/` — exactly the design's Module
Layout: `body.rb` (`Dexpace::Body`, its eight factories, `MAX_BUFFERED_ERROR_BODY_BYTES`,
`.buffer_bounded`, the two private copy routines and the two latches), the ten variants under
`body/` (`bytes_body.rb`, `buffer_body.rb`, `stream_body.rb`, `chunked_body.rb`, `form_body.rb`,
`file_body.rb`, `multipart_body.rb` with its nested `Part` and `Builder`, `response_body.rb`,
`request_logging_body.rb`, `response_logging_body.rb` with its private `Tail`) and
`typed_response.rb` — each with a `sig/` mirror declaring every method, private ones and instance
variables included, for the strict `core` Steep target, and each with a `test/` mirror; plus two
fakes under `test/support/` (`fake_body.rb`, `fake_response_body.rb`), required explicitly by the
suites that use them. Three `lib/` files changed as the design said: `http/percent_encoding.rb`
(the form encoder beside the RFC 3986 one), `http/response.rb` (`#close`, `#body_string`,
`#body_bytes`, `.resolve_charset`, and after review round 0 the private `#read_through` both readers
share) and the entry file (twelve `require_relative`s as one block, after 3a's, in the plan's Task
14 Step 1 order — the build had moved `file_body` after `form_body`, both orders being
dependency-safe, and round 0's R0-6 put it back). Two `sig/` files changed as the design said, `request.rbs` and
`response.rbs`, narrowing `body` to `Dexpace::Body?` on the reader, `.build`, `.new` and
`#initialize` (P3-15). Three existing suites gained sections: `response_test.rb` (five nested
groups), `request_test.rb` (`HTTP-46`'s body half) and `percent_encoding_test.rb` (`FormTest`);
two phase-2 tests changed their pinned expectation (`seam_surface_test.rb`'s non-relative requires
now name `securerandom`; the smoke suite `dexpace_test.rb`'s constant list gains the body layer
and pre-requires `securerandom`). One repository-root tool is new, `tools/measure_view_retention.rb`
(Task 13). The gemspec is untouched — zero `add_dependency` lines — and `require "securerandom"`
in `multipart_body.rb` is the one `require` 3b adds, on phase 0's twelve-name allowlist.

The gates, all seventeen, on **4.0.6** (`bundle exec rake`, 2026-09-16, re-run after review rounds
0's and 1's repairs), on the tests tip: green, exit 0 — `cops:test` 100 runs / 326 assertions, `steep` no
type error over the strict `core` target, `test:gems` **1,153 runs / 6,076 assertions** across the
six gems, with **99.96% line coverage (2,977 / 2,978)** against the 80% floor — the one uncovered
line is the same one phases 2 and 3a recorded, the registry claim swap's race-only branch —
`test:gates` 129 runs, the nine `gates:*` tasks, `yard` 100.00% documented (369 methods, 0
undocumented), `bundler_audit` clean. On the code tip alone every one of the seventeen is green
too, `test:gems` at 784 runs, 0 failures, 0 errors and **84.21%** line coverage — above the floor,
because the phase-1 suites the code tip still carries reach most of the new layer through
`Response` and the smoke suite; the layering rule permits a red floor there and none was needed.
The same caveat about `rubocop` that phases 1, 2 and 3a recorded: run through `rake` from a
worktree nested under the parent checkout's `.claude/` it inspects 9 files; run as `bundle exec
rubocop --fail-level=convention --ignore-parent-exclusion` it inspected **227 files, no offenses**
at the tests tip (213 at the code tip), and that is the run these rows rest on. The twelve
body-layer suites are 323 runs on their own (48, 13, 10, 28, 18, 13, 30, 36, 28, 26, 54 and 19).

The matrix set (`test:gems gates:gemspec_audit gates:require_allowlist gates:clean_bundle
gates:single_instance`) is green on **3.2.11**, **3.3.12** and **3.4.10** at the tests tip, each with
its own lockfile resolved fresh — 1,153 runs / 6,076 assertions on each, 0 skips, 99.96% line
coverage — and on the code tip `test:gems` on 3.2.11 is 784 runs, 0 failures, 84.39%. The
interpreter-sensitive assertions are green on every row, and none skipped: the `StringIO` and
`Tempfile` seek shapes (`stream_body_test.rb`, "a StringIO is rewindable…", "a File is rewindable
and the probe leaves its cursor…", "replay rewinds to the construction position…"), the real
`IO.pipe` raising `Errno::ESPIPE` ("a pipe is not rewindable…", "a pipe stays fully readable after
the probe…"), the two-fiber proofs (`response_logging_body_test.rb`, "two fibers of one thread
interleave the drain…"; `typed_response_test.rb`, "a fiber suspended mid-parse…", "two fibers of
one thread reach the memo…"), the `/proc/self/fd` count (`file_body_test.rb`, "closes its handle
even when the sink raises partway"), the null-device rejection, the `Encoding.default_internal`
helper under `-w` (`response_test.rb`, `DecodeGlobalTest`, both tests) and the unknown-charset
fallback through `Encoding.find`.

The surface manifest `test/fixtures/surface/dexpace-core.txt` grew from 366 to 515 lines through
`bundle exec rake surface:regenerate`, once, in Task 14, and the 149 added lines were read one by
one against the plan's Task 14 Step 5 list: the fourteen constants (R6's twelve plus
`MultipartBody::Part` and `MultipartBody::Builder`), `Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES`,
`FormBody::MEDIA_TYPE`, `MultipartBody::BOUNDARY_CHARS`/`BOUNDARY_LENGTH`/`CRLF`/`DASHES`,
`Response#close`/`#body_string`/`#body_bytes` and `.resolve_charset`, `PercentEncoding#encode_form`
and `#encode_form_component` (instance rows, as phase 1's `#encode_component` is, because the module
is `extend self`), `ResponseBody.new` (the block-form override), and three rows the plan's list did
not have because they are this build's: `Dexpace::Body#==`, `#eql?` and `#hash` (deviation 3
below). No `private_constant` appears — `Body::BlockSink`, `Body::CountingSink`,
`ResponseLoggingBody::Tail`, `MultipartBody::GENERATED_BOUNDARY_CHARS` and
`PercentEncoding::FORM_UNRESERVED` are absent — and nothing was removed. `gates:sig_diff` still
prints "no release tag yet"; `gates:rbs_surface` is clean without widening its allowlist, because
no 3b signature names a stdlib constant 3a had not already admitted.

**Task 13's measurement, re-run on the merged tree rather than copied** (3.2.11 / 3.4.10 / 4.0.6,
`ruby -w -Igems/dexpace-core/lib tools/measure_view_retention.rb`, 2026-09-16):

| Live views on one captured buffer | Registered | Bytes retained | Close all |
|---|---|---|---|
| 1 | 1 | 0 | 0.0000 s |
| 100 | 100 | 0 | 0.0002 / 0.0002 / 0.0002 s |
| 1 000 | 1 000 | 0 | 0.0116 / 0.0142 / 0.0125 s |
| 10 000 | 10 000 | 0 | 1.1574 / 1.3232 / 1.3207 s |

Reverse-order close at 10 000: 0.6472 / 0.7103 / 0.7719 s. Per-view allocation: 8 objects on
3.2.11 and 4.0.6, 7 on 3.4.10. A thousand views read to the end and then closed cost 0.011–0.013 s
and retain nothing. Against the plan's decision-5 table (0.0045 s at 1 000, 0.46–0.52 s at 10 000,
9–10 objects per view): the shape is the same — zero bytes retained per unread view, deregistration
quadratic in the number of simultaneously-live unclosed views, reverse order roughly halving it —
the per-view allocation is one to two objects lower, and the close cost is about two and a half
times the plan's on this machine, which is machine variance over an `Array#delete` scan and not a
change in mechanism. **What changed and why:** the 3a finding the plan's "The findings" section
reports — `BufferedSource.wrapping` delivering one byte per read — is **closed** in 3a as built
(`TypedReads::READ_SEGMENT_BYTES` of 64 KiB, `#dexpace_fill_beyond(behind, want)` passing the
caller's count through, 3a's plan Task 10 amendment and review R0-1), so a view's read is one fill
of what is there rather than a byte at a time, and the retention measurement below the plan's
1 000-view knee is the same. The verdict stands as the plan wrote it: nothing in `BODY-22`–`BODY-29`
produces a thousand simultaneously-live unclosed views on one captured body, and the first caller
that does picks up the `Hash`-keyed registry as a numbered task in its own phase's plan, against 3a's
registry, which this phase did not touch.

## Guards run red

Every guard the plan asks to be seen red was seen red, on 4.0.6, and restored. Fifty-five
single-edit mutations were run against the finished suites — the plan's fifty, the adversarial
review's two testable ones, and the regime-probe and two decode probes the brief names — each
applied to the built tree, the owning suite re-run, the file restored; **fifty-four were caught by
a test, and one was not**: the plan's `BODY-32` row is the `.max` spelling ("clamps up"), which
fails, but the *deletion* of the clamp clause — the edit that removes the MUST — survived the
whole suite on 4.0.6 and 3.2.11, and review round 0 found it (R0-2). Twelve more mutations were
run after that round's repair, one per line the repair made load-bearing, on 4.0.6 **and 3.2.11**,
and every one is caught; they are the second table below, and the rows that matter from the first
battery are the first. Eight more were run after review round 1's repair, one per line it made
load-bearing, again on both interpreters and again every one caught, with six of the earlier
mutants nearest the restructured drain and release re-run; they are the third table. Five mutations had to be re-spelled because their first form tripped `NFR-6`'s warning
gate at load — an unused variable or unreachable code — which is a mutation caught by a warning and
not evidence about a test, exactly as the plan found for four of its own; two of the twelve were
re-spelled the same way (a dropped `close` as a discarded `respond_to?` rather than a bare `nil`).

| Fix reverted | Guard | What it said |
|---|---|---|
| `HTTP-42`: the retag dropped, the target kept (`.read` for `.read_string(encoding)`) | `response_test.rb`, `DecodeTest` | **6 failures of 36**, then 9 of 39 once the P3-23 surface rows existed: `Expected: "héllo"`, the replacement characters in place of every non-ASCII byte |
| `HTTP-42`: the retag kept, the target dropped (`.encode(invalid: :replace, undef: :replace)`) | `response_test.rb`, `DecodeGlobalTest` | **exactly the two `default_internal` tests**: `Expected: #<Encoding:UTF-8> Actual: #<Encoding:ISO-8859-1>` and the property's `#<Encoding:US-ASCII>` — indistinguishable from the correct recipe on every other test, which is why the hostile-global tests exist |
| `BODY-9`: the probe becomes `respond_to?(:rewind)` | `stream_body_test.rb` | 3 failures, 1 error: the pipe reported rewindable, and its "replay" raised `Errno::ESPIPE` |
| `BODY-9`: replay rewinds to byte 0 | `stream_body_test.rb` | `Expected: "456789" Actual: "0123456789"` on the pre-positioned handle |
| `BODY-9`: the race-safe rewind guard dropped | `stream_body_test.rb`, `LatchTest` | `Dexpace::StreamError expected but nothing was raised` — the overlapping second write went through, and the seek delta was 2 |
| `BODY-8`: close ownership no longer forces single-use | `stream_body_test.rb` | 3 failures: an owned rewindable stream reported replayable, and the closed `StringIO` was then seeked |
| `BODY-6`/`BODY-7`: the consume-once latch dropped | `chunked_body_test.rb`, `LatchTest` | `Expected: 1 Actual: 8` passers under concurrent writes |
| `BODY-11`: the offset+count clause dropped | `file_body_test.rb` | `Dexpace::InvalidArgumentError expected but nothing was raised` |
| `BODY-12`: `#to_path` defined | `file_body_test.rb`, `WindowTest` | `Expected ... to not respond to :to_path` |
| `HTTP-51`: the length from a second routine | `multipart_body_test.rb` | 4 failures: the property found the drift on the first sample |
| `HTTP-51`: a CR/LF in a parameter value accepted | `multipart_body_test.rb`, `QuotingTest` | `Expected "part header ... carries a byte no header value may carry"` to include `"CR or LF"` — the whole-line sweep still refused it, by the other predicate |
| `HTTP-44`: the memo becomes `@value \|\|=` | `typed_response_test.rb` | **6 failures**: `Expected: 1 Actual: 3` handler calls for the `nil` success |
| `HTTP-45`: the raw accessors take the parse lock | `typed_response_test.rb`, `SerializationTest` | `Expected nil to not be nil`: the reader thread never finished inside its five seconds |
| `BODY-22`: the mutex held across the drain | `response_logging_body_test.rb`, `SerializationTest` | **1 error**, the fiber proof: `ThreadError: deadlock; lock already owned by another fiber belonging to the same thread` |
| `BODY-24`: the probe byte written into the capture | `response_logging_body_test.rb` | 2 failures: `Expected: "0123" Actual: "01234"` |
| `BODY-24`: a second tail read allowed | `response_logging_body_test.rb` | `Dexpace::StreamError expected but nothing was raised` |
| `BODY-28`: the wrapper's close also closes the captured buffer | `response_logging_body_test.rb`, `CloseTest` | `Expected #<Dexpace::IO::Buffer ... @dexpace_closed=true ...> to not be closed?` — the rule with no external symptom today, pinned directly |
| `BODY-27`: the tail's close bypasses the guard | `response_logging_body_test.rb`, `CloseTest` | `Expected: 1 Actual: 2` delegate closes when the tail and then the wrapper were closed |
| `BODY-30`: the original body not closed | `body_test.rb`, `BufferBoundedTest` | 6 failures across the three-body shape and the two doubles |
| `emit_exactly`'s ingress retag dropped (the review's R1) | `chunked_body_test.rb` | **missed on the first pass**, exactly as the review found: every sink in the suite retags on the way in. A raw `#write` recorder that keeps what it was handed as given was added, and the mutation then fails it: `Expected: [BINARY] Actual: [UTF-8]` |
| `FormBody` stores the caller's pairs (the review's R2) | `form_body_test.rb` | `Expected: [["a", "1"]] Actual: [["a", "19"], ["b", "2"]]` on the `#pairs` accessor |

The remaining thirty-four rows — `BODY-1`, `BODY-35`, `BODY-25`, `BODY-10`, `BODY-13` (both
routines), `BODY-32`'s `.max` spelling, `BODY-3`, `BODY-8`'s owned-stream close, `BODY-11`'s
regular-file, offset-past-size and handle-close clauses, `HTTP-51`'s quote escape and boundary
grammar, `BODY-2` both clauses, `BODY-14`, `BODY-15`, `BODY-6` on a response body, `BODY-33`,
`BODY-16` on both readers, `HTTP-43`, `HTTP-42`'s fallback, `BODY-18`, `BODY-20`, `BODY-21` both
clauses, `BODY-22`'s every-access drain, `BODY-24`'s over-cap close, `BODY-26`, `BODY-28`'s loud
close, `BODY-29`, `HTTP-44`'s unmemoised failure — each fail between one and seven tests of the
owning suite. The review's third, `BlockSink` dropping `#b` on a multi-string write, stays recorded
and untested as the plan says: nothing in core writes two `String`s to a sink in one call.

**Review round 0's repair, 2026-09-16** — one mutant per line the repair made load-bearing, run on
4.0.6 and again on 3.2.11 with the same results, and four of the first battery's mutants nearest
the restructured lines re-run against the new shape (`BODY-16`'s body close, `BODY-30`'s original
close, `BODY-27`'s tail-close guard, `BODY-24`'s probe byte: 5, 6, 2 and 3 failures, all still
caught):

| Fix reverted | Guard | What it said |
|---|---|---|
| `BODY-32`: the clamp **deleted** (`clamp_cap` returns `cap`) — the mutant that survived round 0 | `body_test.rb`, `BufferBoundedHandlesTest`; `response_body_test.rb`, `PreviewTest` | 1 failure in each: `Expected: 67108864 Actual: 67108865` — the count the first read asked for |
| `BODY-32`: clamps up (`.max`) | the same two | 5 failures in each |
| R0-1: the readers' handle close dropped from `#read_through` | `response_test.rb`, `SurfaceTest` | 4 failures: `Expected: 0 Actual: 1` registered view, on the `BufferBody` and on both wrapper regimes |
| R0-1: the two ensures flattened into one (`source.close; body.close`) | `response_test.rb`, `FinallyTest` | `Expected: 1 Actual: 0` body closes when the handle's close raised |
| R0-1: `copy_bounded`'s source close dropped | `body_test.rb`, `BufferBoundedHandlesTest` | 2 failures: `Expected: 0 Actual: 20` registered views |
| R0-1: `copy_bounded` closes the source unconditionally (no `respond_to?`) | `body_test.rb` | 1 failure, 4 errors: `NoMethodError: undefined method 'close' for an instance of FakeSource` |
| R0-3: the `Tail` forwards as `@source.read(count)` again | `response_logging_body_test.rb`, `TailTest` | 2 failures, 1 error: "the tail's partial read blocked with seven bytes available", the join's five seconds spent; the `#read_into`-only recorder's `NoMethodError` |
| R0-3: the `Tail` forwards as `@source.readpartial(count)` rescuing `EndOfStreamError` (the review's suggested spelling) | `response_logging_body_test.rb`, `TailTest` | 1 failure, 1 error: the `#read_into`-only recorder has no `#readpartial` — the spelling widens the delegate's source contract, which plan decision 9 keeps at `_Source` |
| `BODY-25` on the tail: a zero read returned as an empty chunk | `response_logging_body_test.rb`, `TailTest` | `Dexpace::StreamError expected but nothing was raised` |
| R0-4: the subtype dropped from `MultipartBody#==` | `multipart_body_test.rb`, `ConstructionTest` | `Expected ... @subtype="mixed" ... to not be equal to ... @subtype="form-data"` |
| R0-4: the subtype dropped from `MultipartBody#hash` | `multipart_body_test.rb`, `ConstructionTest` | the two hashes equal |
| R0-5: the `#peek` half of `ResponseBody`'s construction check dropped | `response_body_test.rb`, `ConstructionTest` | `Dexpace::InvalidArgumentError expected but nothing was raised` on a `FakeSource` |

**Review round 1's repair, 2026-09-16** — one mutant per line the one-handle rule made load-bearing
in `ResponseLoggingBody`, run on 4.0.6 and on 3.2.11 with identical counts, over
`response_logging_body_test.rb` and `response_test.rb` together (98 runs); then six of the earlier
mutants nearest the restructured lines re-run against the new shape (`BODY-28`'s buffer close 1
failure, `BODY-27`'s tail-close bypass 3, `BODY-24`'s probe byte in the capture 6, the fits-cap
best-effort close dropped 6, R0-3's `@source.read(count)` 2 failures + 1 error, `BODY-26`'s failure
not cached 1 + 5 — all still caught):

| Fix reverted | Guard | What it said |
|---|---|---|
| R1-1: the `Tail` built over a second `@delegate.source` | `response_logging_body_test.rb`, `DelegateHandleTest`; `response_test.rb`, `SurfaceTest` | 4 failures: `"012340123456789"` for the composite — the probe byte from the drain's handle, then a fresh view from byte zero — and the fresh-view double's `Expected: 1 Actual: 2` asks |
| R1-1: the regime probe asks `@delegate.source` again | the same | 4 failures: `"01230456789"` — the probe byte read from a second view's byte zero |
| R1-1: the fill and the probe on one handle, the tail on a second ask | the same | 5 failures: the same `"012340123456789"`, plus the fits-cap fill's view left registered (`Expected: 0 Actual: 1`), since the handle `#release` closes is now the tail's |
| R1-1: the handle close dropped from `#release` | `DelegateHandleTest`; `SurfaceTest` | 5 failures: `Expected: 0 Actual: 1` registered view in the `BufferBody`'s buffer, fits-cap and over-cap and through the reader, and the order log `Expected: [:handle, :delegate] Actual: [:delegate]` twice |
| R1-1: the close order swapped (delegate first, handle in the `ensure`) | `DelegateHandleTest` | 2 failures: `Expected: [:handle, :delegate] Actual: [:delegate, :handle]` |
| R1-1: the `ensure` dropped (two sequential closes) | `DelegateHandleTest` | 2 failures: `Expected: [:handle, :delegate] Actual: [:handle]` — the delegate never closed once the handle's close raised |
| R1-1: the handle's `respond_to?(:close)` guard dropped | `DelegateHandleTest`; `FailureTest` | 2 errors: `NoMethodError: undefined method 'close' for nil` on the undrained close, and for `FakeSource` on the failed-drain close |
| R1-1: the guard narrowed to the nil case (`unless upstream.nil?`) | `FailureTest` | 1 error: `NoMethodError ... for an instance of FakeSource` — a `_Source` declares no `#close` |

## Audit groups run

The phase-start pair first, at implementation: `--origin note --brief` returns 52 note entries
across 21 files; `--section conflicts --brief` returns the six harvested conflicts, every one
`[overridden by notes/…]`, and 19 note-side entries. `--prefix-info BODY` reports 37 IDs, 37
substantive, 0 roll-ups; `--gaps BODY,HTTP` returns nothing. `--req` was run for each task's IDs
before that task; none came back a roll-up. The eight groups the design ran at planning are recorded
there; at implementation the three that bite were re-checked against the built code:

| Group | Result at implementation |
|---|---|
| Encoding and binary strings | Clean against the built code: the ingress retag is `#emit_exactly`'s `String#b` and `BlockSink`'s, keeping a frozen BINARY chunk and copying everything else; no `force_encoding` on any body path; `Response#body_string` is the one decode site and names both encodings; every fixture is non-ASCII, and the raw-sink test added after the battery is what makes the body layer's own retag observable |
| Fiber scheduler, thread safety | Clean against the built code: four flag flips — `@dexpace_consumed`, `@dexpace_writing`, `ResponseLoggingBody`'s `@state`, `TypedResponse`'s `@state` — plus `Closeable`'s, each under a mutex held across the flip and nothing else, in `Closeable#close`'s if/else shape; `Timeout.timeout`, `Thread#raise` and `Thread#kill` appear nowhere; no method takes a deadline |
| Public API surface | `module-organization/1828a984` (one public constant per file) holds for the twelve files, with `MultipartBody::Part` and `::Builder` nested as `Request::Builder` is; `api-design/b0e18938` is why every name is in P3-14 or P3-22, and why `GENERATED_BOUNDARY_CHARS` and `FORM_UNRESERVED` are `private_constant`; `api-design/88e6bf12` is honoured by `respond_to?` at every caller-supplied stream, sink, `#each` object and handler, and no `is_a?(IO)` anywhere |

The two notes the design filed stand as written. No third was needed: the finding that
`BufferedSource.wrapping` delivered one byte per read is closed in 3a as built, and the corpus rule
it would have annotated (`io-and-byte-streams`' fill contract) is stated correctly by 3a's own note.

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate.
Items 1, 2 and 9 are where 3a as built overrode the plan's assumptions; 17 through 21 are review
round 0's and 22 is review round 1's; the rest are this build's.

1. **`Body.buffer_bounded` is driven over the three response-side bodies, and every double it
   drains answers `#source`.** The plan's Task 9 prose says so (P3-23's write-side half) but its
   test fence still drained `FakeBody` through `#write_to`. As built, `FakeBody` answers `#source`
   as one memoised `BufferedSource.of_bytes` over its chunks, the Task 9 suite runs over a
   `ResponseBody`, a `ResponseLoggingBody` in both regimes and a `BufferBody` plus two
   `#source`-answering doubles, and the oversized body pulls 64 KiB blocks through
   `BufferedSource.over` so "not read" is measurable.
2. **Task 13's tool reads `#source`, not `#read`**, the contract name P3-23 fixed after the plan's
   fence was written, and it does not `require "benchmark"`: `benchmark` left the default set at
   4.0 and is not in the `Gemfile`, so the clock is `Process.clock_gettime`.
3. **`Dexpace::Body` carries `HTTP-46`'s default — `#==`, `#eql?` and `#hash` as identity — and
   `StreamBody`, `ChunkedBody`, `ResponseBody` and `ResponseLoggingBody` drop their four copies.**
   Strict Steep refused `other.body == @body` on a value typed `Dexpace::Body` because a module type
   carries only the module's own methods; the honest fix is for the module to state the contract
   every includer meets, and identity is the right value comparison for every variant holding a
   live stream. Three manifest rows the plan's list did not have.
4. **Strict Steep reshaped eight private mechanisms without changing behaviour.** The four latches
   use `Closeable#close`'s if/else shape rather than `next`/`loop`-with-`break`; the same-class
   readers `#==` reaches (`BytesBody#bytes`, `BufferBody#snapshot_bytes`,
   `RequestLoggingBody#tap_limit`) are private and reached with `send`, as phase 1's `Headers#==`
   reaches `#values`, because RBS has no `protected`; nullable instance variables are read into a
   local before the branch; `::IO.copy_stream`'s destination is annotated `untyped` because rbs's
   `_Writer` takes `(*untyped)` and a `_Sink`'s `(*String)` fails on variance alone;
   `Response.resolve_charset` makes the UTF-8 fallback explicit because rbs declares
   `Encoding.find` nullable; and `ResponseBody.new` is a bare `super` — strict Steep refuses a `&nil`
   block-pass, and `#initialize` never yields, so the implicit forward is inert.
5. **`Body`'s RBS does not `include Dexpace::IO::_Chunked`.** `rbs validate` refuses a module that
   includes an interface and re-declares its method (`DuplicatedMethodDefinitionError` on every
   includer); every body satisfies `_Chunked` structurally and the sig says so in a comment.
6. **`TypedResponse#run_handler` rescues `::Exception` explicitly and re-raises** rather than
   settling in an `ensure` with `$!`, which `Style/SpecialGlobalVars` refuses and `English` would
   have added a require for; the behaviour is the plan's, and a test drives a `NotImplementedError`
   through it and joins a later caller with a timeout.
7. **A multipart subtype is validated as one bare token** through `MediaType.parse`, because
   `subtype: "form-data;x=1"` otherwise parsed as a subtype plus a smuggled parameter, with
   `#media_type` and `#subtype` disagreeing; found while writing the as-built page. The plan's
   finding that `subtype: "not a subtype"` leaks a stdlib exception does not reproduce: phase 1's
   `MediaType.parse` already refuses it with a `Dexpace::InvalidArgumentError`.
8. **A generated boundary draws from the alphanumeric subset** of `BOUNDARY_CHARS`, kept in the
   `private_constant` `GENERATED_BOUNDARY_CHARS`, so the `Content-Type` parameter stays a token
   that every peer parses; a caller-supplied boundary is still validated against the whole grammar,
   and the specials are asserted accepted.
9. **`RequestLoggingBody` validates its cap at construction** with the tee's rule and stores `nil`
   as `::Float::INFINITY`, so a caller's mistake is reported where it was made and two unbounded
   wrappers compare equal; 3a's `TeeSink.new` accepts `nil` and `Float::INFINITY` and refuses a
   finite `Float`, which the plan wrote against the earlier `Float::INFINITY`-only shape.
10. **Test files nest a class per behaviour group** for the 100-line cap (3a's deviation 8):
    `body_test.rb` (`CopyTest`, `FactoriesTest`, `BufferBoundedTest`), `stream_body_test.rb`
    (`OwnershipTest`, `LatchTest`, `CopyTest`, `ConstructionTest`), `chunked_body_test.rb`,
    `file_body_test.rb` (`WindowTest`, `HandlesTest`, `ResidueTest`, `EqualityTest`),
    `multipart_body_test.rb` (`FramingTest`, `BoundaryTest`, `QuotingTest`, `ConstructionTest`),
    `response_body_test.rb`, `request_logging_body_test.rb`, `response_logging_body_test.rb`
    (`FailureTest`, `CloseTest`, `LengthTest`, `SerializationTest`, `ConstructionTest`),
    `typed_response_test.rb` (`SerializationTest`, `SettlementTest`, `ConstructionTest`) and the
    five groups appended to `response_test.rb`, each over a shared factory module.
11. **Two phase-2 pins changed their expectation, and one smoke-suite snapshot its preamble.**
    `seam_surface_test.rb` pinned core's non-relative requires at `%w[strscan uri]`; it is
    `%w[securerandom strscan uri]` now, with the comment naming which phase added which. The smoke
    suite's top-level snapshot pre-requires `securerandom` beside `uri` and `strscan`, or the
    `::SecureRandom` constant is attributed to the entry file.
12. **Run counts exceed the plan's** — 323 runs across the twelve body suites (304 before review
    round 0's sixteen rows, 316 before round 1's seven) against the plan's 275 for the whole tree — because the nested groups
    carry cases the plan did not have: the
    contract's `#source`/`#close` defaults and identity default, `copy_exactly`'s chunk-boundary
    forwarding, `emit_exactly`'s retag and empty write, `Body.string`'s named charset,
    `BufferBody#source` and `#close`, an owned single-use body's second write, a `#read`-only stream
    with no `#pos`, a truncated file, an offset at exactly the size, the raw-sink retag, the
    `HTTP-51` specials and the quoted boundary, a filename with a CR, the length query's own
    framing rejection, the bare-token subtype, `ResponseBody#preview` after close, a failed drain
    leaving the delegate open, wrapper-then-tail close, a captured size with no declared length, a
    zero cap over an empty body, `TypedResponse#response`, the non-`StandardError` settlement, the
    three `Response` surface rows over the wrapper in both regimes, and the two rows the tests tip's
    coverage report asked for (a frozen BINARY chunk yielded uncopied; a non-Integer cap refused).
13. **The `HTTP-46` tests pass `headers: Dexpace::Headers::EMPTY`**, which `Request.build` requires
    and the plan's fence omitted; and `request_test.rb` requires `stringio` for the two-streams row.
14. **YARD blocks the plan's fences did not carry** were added to twenty-five public overrides the
    undocumented-method gate found bare, each saying why the override answers as it does.
15. **`MultipartBody` and `ResponseLoggingBody` carry a `Metrics/ClassLength` directive** with its
    reason, as 3a's `BufferedSource` does; `Body` carries `Metrics/ModuleLength`'s, as 3a's two
    vocabularies do. `Part#initialize`, `#emit` and `#part_headers` were split under
    `Metrics/AbcSize` (`#checked_body`, `#frozen_headers`, `#emit_part`, `#payload`, `#disposition`,
    `#sweep!`) rather than waived.
16. **`rbs:validate` was red between Tasks 1 and 12 on the wip branch**, on the forward references
    the plan's own signatures carry (`Body`'s factories name every variant) — 3a's deviation 17
    again — and `steep` was red at Task 12's end on the twenty diagnostics deviation 4 lists; both
    are green from the Steep commit onward, and every tip is proven green below.

Items 17 through 21 are review round 0's (2026-09-16), each a departure from a plan fence the
review found wanting, fixed on the owning branch with its mutation run red above.

17. **`Response#body_string` and `#body_bytes` close the handle `#source` returns, then the body.**
    The plan's fences closed only the body, which is the design's own rule 4 ("every view core
    takes, core closes") unmet on the two readers: a `BufferBody`'s and a fits-cap
    `ResponseLoggingBody`'s `#source` is a fresh `#peek` view that neither body's `#close` reaches,
    so every `body_string` left one view registered in a buffer that outlives the call (R0-1). The
    two readers now share a private `#read_through` — the handle closed in its own `ensure`, the
    body in the method's, so the second close runs whatever the first did — declared in `sig/` for
    the strict target.
18. **`Body.copy_bounded` closes the source it took**, in its own `ensure` before `buffer_bounded`'s
    closes the original, for the same reason and the same two bodies (R0-1). Guarded with
    `respond_to?(:close)` as the two `#release` methods are, because the read side's contract on a
    source is `Dexpace::IO::_Source`'s `#read_into` alone; the `FakeSource`-backed double in the
    suite answers no `#close` and is left alone.
19. **The over-cap `Tail` forwards the live delegate through `#read_into`, not `#read(count)`.**
    The plan's fence wrote `@source.read(count)`, which is `IO-16`'s bulk read and fills until the
    count or EOF, so on a still-open connection the composite delivered the rest of the body in
    `.wrapping`'s 64 KiB segments or at end of stream where the delegate alone returns what has
    arrived (R0-3). `#read_into` fills once, is what a partial read is, and is the one member the
    regime probe already asked of the delegate's source (plan decision 9), so the delegate's source
    contract stays `_Source`'s single method — the review's suggested `#readpartial` would have
    widened it, and the `#read_into`-only recorder in `TailTest` is what refuses that spelling. The
    forwarding sits in a private `#read_tail` beside `#take_pending` under `Metrics/AbcSize`, and a
    zero return raises `BODY-25`'s violation through 3a's helper.
20. **`MultipartBody#==` and `#hash` fold the subtype in.** The plan's fence compared the boundary
    and the parts, so two bodies framing the same parts as `multipart/form-data` and as
    `multipart/mixed` were equal under `HTTP-46` while their media types differed (R0-4).
21. **`ResponseBody`'s construction check asks for `#read_into` and `#peek`.** The plan's fence
    checked `#read_into` alone, which admitted a bare `_Source` the class then sent `#peek`,
    `#each`, `#read` and `#read_string` — a `NoMethodError` on the first preview or read through
    `Response` (R0-5). `#peek` is the narrowest member only a `BufferedSource`-shaped reader
    answers, and the message names both; a view of a `BufferedSource` still constructs.
22. **`ResponseLoggingBody` asks its delegate for `#source` once per wrapper, and closes that
    handle.** The plan's fence (Task 11, Step 4) took `@delegate.source` in `fill_prefix`, again for
    the regime probe and a third time for the `Tail`, and its `CountingDelegate` memoises its
    source, so the plan's own suite could not see the three asks. That is correct over
    `ResponseBody`, whose `#source` is `BODY-14`'s same handle every call, and wrong over
    `BufferBody`, inside the wrapper's stated delegate contract and answering a fresh `#peek` view
    per call by P3-23's own decision: the over-cap composite replayed the prefix twice and then the
    whole body — `"012300123456789"` for ten bytes, through `Response#body_bytes` too — and the
    fits-cap fill's view was never closed, against §7.1's rule 4 (review round 1, R1-1). The drain
    now asks once and holds the handle in `@upstream`; `fill_prefix`, `capture_complete?` and the
    `Tail` read from it, and `#release` closes it ahead of the delegate with the delegate's close in
    an `ensure`, so `BODY-15`'s transport release is attempted whatever the handle's close did. One
    `respond_to?(:close)` guard covers the two handles that cannot be closed — a `_Source` with no
    `#close`, and the `nil` before any drain has asked — and the RBS mirror declares the ivar and the
    two narrowed private signatures. Nothing on the public surface moved: the manifest is the same
    515 lines.

## Findings routed

- **Non-ASCII part names and filenames are refused by `MultipartBody`.** The design's whole-line
  sweep uses phase 1's outbound header grammar, which admits HTAB and printable ASCII only, so a
  `Part` named `"résumé"` or a filename `"résumé.pdf"` raises `Dexpace::InvalidArgumentError` at
  write time and the caller must percent-encode first (RFC 7578 §4.2's own recommendation; browsers
  send raw UTF-8). A safe default and a stated limitation, kept as the design decided; whether the
  part-header sweep should admit obs-text, a widening that cannot break `NFR-4`, is **routed to phase
  10's inbound list** in the roadmap as audit work against this phase's decision.
- **The decode-recipe sentence in design §3.1** was already on phase 10's inbound list, filed at
  planning; the code half is Task 8 and the corpus half is `docs/knowledge/notes/io-and-byte-streams.md`.
  Nothing further to route.
- **`Body.string("caf\xE9".b)` leaks `Encoding::UndefinedConversionError`** — already routed to
  phase 1's plan, Task 1 (the argument-boundary re-wrap rule) by the plan; stays there. The
  multipart half of that finding does not reproduce (deviation 7).
- **`TeeSink#clear_tap`** — decided by 3a (dropped); nothing to route, and this phase never calls it.
- **The one-byte-per-read finding against 3a** — closed in 3a as built (its plan's Task 10
  amendment and review R0-1); Task 13's measurement above records what changed. Nothing to route.
- **Design §4's builder list omitting the multipart body** — already on phase 10's inbound list;
  `HTTP-3`'s cross-reference row above is the code half.
- **The RuboCop-baseline finding** the plan inherits from phase 0 does not reproduce (3a found the
  same): the honest run is clean.
- **The design's ledger** gains an "As built" addendum (below, in the design) for deviations 3, 7,
  8 and 9, which touch public behaviour; the consolidation of P3-14–P3-29 into design §10 is a
  human's, as it was for 3a, because `docs/sdk-design-ruby/` is frozen.

## Postponed work

The one item the design postponed keeps its owner: the body-logging caps' configured source and
the enablement predicate are phase 5a, Task 13 and phase 5b, Tasks 14–15, cited at `BODY-34`'s row.
The two dispositions the plan's Task 14 Step 7 asks to be checked against the code hold as the
design recorded them: `BODY-12`'s first clause is discharged by Task 6 (`::IO.copy_stream`, the
window, `#path`/`#offset`/`#count`, no `#to_path`) and clause 2 stays with `TRANSPORT-28` under
`docs/first-release.md` § What v1 ships without; the body-member narrowing phase 1 postponed to
phase 3 is picked up by Task 14 (`sig/` at `Dexpace::Body?`, `HTTP-46`'s body half tested). The
items earlier phases postponed were re-read on 2026-09-16 and keep the owners the design's "Work
Phase 3b Postpones" section records: `close_quietly`'s two disposal routes (phase 4b, Task 2; phase
5b, Task 14 — `BODY-28` is now its first call site and the case is strengthened, not met), the
pivot's `deadline:` keyword (phase 5a, Task 8), the fakes' move to `dexpace-conformance` (declined
by phase 8a; `FakeBody` and `FakeResponseBody` are two more doubles that would move), `IO-38` on a
GVL-free interpreter (`docs/first-release.md` § Post-release triggers), and a Steep target over a
test tree (event-gated there too; the two fakes are scriptable methods with no invariant a type
checker would catch). The implementation postponed nothing further.
