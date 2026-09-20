# Phase 7b — Server-Sent Events: Checklist

**Written at execution time, 2026-09-20, from what was built** — not from the plan. A row whose task
did not do what the plan said is a row that says so, and the "Deviations from the plan" section
below is where each departure is stated with its reason. The design and the plan were written on
2026-09-10 against the *designs* of phases 4–6, on a machine that then had only Ruby 3.4.10,
concurrently with 7a's and 7c's documents and before any of the three was built. Since then phases
4a–6c were built, reviewed and merged, every interpreter in the matrix was installed, and a
cross-check agent read the plan against `main` at `c53638b` on 2026-09-20 and produced the as-built
list this build was dispatched with. **This phase was cut from `main` at `c53638b`**, which holds the
whole of phase 6 and none of 7a or 7c: the two sibling lanes were built concurrently in other
worktrees off the same base, so nothing here describes anything of theirs as landed, and the one
convergence point the charter names — spec-forced boundary 5's audit — is built here in full with
the pagination layer's globs on a printed `PENDING` list, the row's move to `GUARDED` being the
reconcile pass's after both lanes are on `main`. Where the plan's text and the built tree disagree
the tree wins and this document records it.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase7/phase7b/2026-09-10-phase7b-server-sent-events.md`. Task numbers are that
plan's (thirteen; the dispatch brief's "14 tasks" counts one the plan does not have). Design:
`docs/work/mvp/phase7/phase7b/2026-09-10-phase7b-server-sent-events-design.md`, whose Deviation
Ledger numbered `P7-20`–`P7-27` before execution and whose as-built rows **P7-81–P7-86** are cited
below (7a's rows are cited as "7a's P7-n", 7c's as "7c's P7-n"; the manager fixed the bands so the
three lanes never collide); the charter is
`docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md`. Every test file named here is under
`gems/dexpace-core/test/` unless it says `test/gates/`, mirrors its `lib/` file one for one (three
carry no `lib/` mirror and say so below), and opens with the IDs it exercises.

## Requirement rows

Forty-one own rows — `SSE-1`–`SSE-41` — plus the cross-reference rows for the non-`SSE` IDs this
phase owns a share of, taken from the design's interface table, the charter's spec-forced boundaries
and the as-built list the way 6a, 6b and 6c carried theirs. **Forty ✅, one ⏳** (`SSE-41`, declined
for v1), nothing 🚫, nothing N/A. Five rows state something other than "a test asserts it", as the
design's *Five rows the checklist must state rather than tick* requires: `SSE-19`, `SSE-18`,
`SSE-21`/`SSE-22`, `SSE-40` and `SSE-37`.

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `SSE-1` | MUST | ✅ | 7 | `Reader#next_event` loops `LineReader#next_line`; a blank line with any field seen builds one `Event`, and `reset_block` clears all five accumulators and the byte total on EVERY blank line, dispatching or not (since review round 0's R0-1: `dispatch`'s nil branch once returned before the reset, so a run of fieldless blocks accumulated into `SSE-19`'s event cap), so `data: 1\n\ndata: 2\n\n` is `[["1"], ["2"]]`, `id: 1\ndata: a\n\ndata: b\n\n` gives a second event with a nil id, event, comment and retry, and `data: a\n\n` + three `zz: 1\n\n` blocks + `data: b\n\n` under a 12-byte cap is `[["a"], ["b"]]` (`reader_test.rb` `DispatchTest`, the three `SSE-1` cases; `EventCapTest` "resets at every blank line"; guard 51) |
| `SSE-2` | MUST | ✅ | 3 | `LineReader` recognises LF, CR and CRLF natively over `#getbyte`, CRLF as one terminator, terminators stripped, a lone CR terminating by itself with the following byte held in a one-byte pushback (`a\rb\n` → `["a", "b"]`; `a\r\r\n` → `["a", ""]`; the same five lines under each terminator and under a mix are identical; a 200-sample seeded property test over generated line lists and terminator assignments round-trips, its one unexpressible assignment — an empty line terminated by LF directly after a CR-terminated one, which IS `\r\n` — excluded by construction). Built over `#getbyte` and NOT over 3a's `#read_line_utf8`, which keeps a lone CR as content (P7-20; `line_reader_test.rb` `GrammarTest`; guards 1–3) |
| `SSE-3` | MUST | ✅ | 5 | `Reader#apply_line` splits at the FIRST `0x3A` on the BINARY line: `data\n\n` and `data:\n\n` both give `[""]`, `data:a:b:c` keeps the later colons as value bytes, and `garbage\n\n` — an unrecognised name with no colon — dispatches nothing (`reader_test.rb` `FieldTest`, four `SSE-3` cases) |
| `SSE-4` | MUST | ✅ | 5 | A present-but-empty value is `""` and counts as a field seen: `event:\ndata:x\n\n` has `event == ""`, `id:\n\n` dispatches an event whose id is `""`; `Event#empty?` reads `event: ""` and `data: [""]` as not empty (`FieldTest`, two `SSE-4` cases; `event_test.rb`, "a present-but-empty field is not 'unset'") |
| `SSE-5` | MUST | ✅ | 5 | `Reader#value_after` strips exactly one `0x20`: `data: hello` → `hello`, `data:   hello` → `  hello`, a tab after the colon is content, and the comment text gets the same one strip (`FieldTest`, two `SSE-5` cases; guard 10) |
| `SSE-6` | MUST | ✅ | 5 | A line whose first BYTE is `0x3A` is a comment, latest-wins, one space stripped, and it counts as a field seen on its own: `:keep-alive\n\n` dispatches an event with `comment == "keep-alive"` and empty data (`FieldTest`, two `SSE-6` cases; `DispatchTest`, the comment-only block; guard 50) |
| `SSE-7` | MUST | ✅ | 5 | `Reader#apply_field` matches the four BINARY names `id`, `event`, `data`, `retry` EXACTLY: `garbage: zzz\nevent: kept\ndata: p\n\n` gives `kept` / `["p"]` with id and comment nil, `garbage: zzz\n\n` dispatches nothing, and — P7-24 — `DATA:`, `Event:`, `Id:` and `RETRY:` are unknown fields, as are ` data` and `data ` (`FieldTest`, the `SSE-7` and `SSE-7/P7-24` cases; guard 11, a `downcase`, which also keeps the phase free of the one fold site the charter's boundary 19 expected) |
| `SSE-8` | MUST | ✅ | 5 | `@data << decode(value)` in wire order, never joined: `data: line1\ndata: line2\n\n` is `["line1", "line2"]`; the join is `TypedStream#map`'s (`FieldTest`; `typed_stream_test.rb` `MapperTest`) |
| `SSE-9` | MUST | ✅ | 5, 7 | Two halves, two tasks. **Value half** (Task 5): `Reader#apply_id` tests `value.include?("\x00".b)` on the RAW bytes before the decode, so a NUL cannot be lost to a replacement character — `id: a\0b` leaves the id nil, `id: good\nid: a\0b` keeps `good`, `id: \xFF\0` is ignored, a valid id is verbatim and latest-wins (`FieldTest`, four `SSE-9` cases; guard 13). **Dispatch half** (Task 7): the NUL screen runs BEFORE `@seen` is set, so `id: a\0b\n\n` — a block whose only line is the NUL id — dispatches nothing, the one assertion that fails when the flag is set on the field name (`DispatchTest`, "a NUL id does not count as a field seen"; guard 12) |
| `SSE-10` | MUST | ✅ | 5 | `event` is stored raw, latest-wins, and is nil when no `event:` line was sent — never `"message"`; `Message` stays `Message` (`FieldTest`, two `SSE-10` cases; guard 14) |
| `SSE-11` | MUST | ✅ | 6 | `Reader#apply_retry`: an anchored `Regexp.new("\\A[0-9]+\\z", timeout: 1.0)` per pattern (never `Regexp.timeout`), a width check of at most `MAX_RETRY_MS`'s ten digits BEFORE `Integer(value, 10)`, and a value above `Dexpace::SSE::MAX_RETRY_MS = 2_147_483_647` ignored rather than wrapped; `5000`/`0`/`05` accepted, latest-wins, and twelve forms ignored — `bad`, `-100`, `+5`, empty, `0x10`, `1_0`, two leading spaces, `5a`, full-width `０５`, a trailing space, a trailing tab, `12abc` — six of which `Integer(s, exception: false)` accepts; an ignored retry does not count as a field seen; an over-cap value does not overwrite a valid one; a 4,096-digit run is ignored without being parsed. **This is NOT the line cap**: `SSE-11` is a MUST about the retry field's value, `SSE-19` a MAY about line length, two constants and two rows because the two were confused once (`reader_test.rb` `RetryTest`, seven cases; `sse_test.rb`; guards 15, 16) |
| `SSE-12` | MUST | ✅ | 5 | `Reader#consume_bom_once` runs on the FIRST `#next_event` — a reader built and never pulled touches its source zero times (`FakeChunked#yielded == 0`) — through one `#peek` view read for up to three bytes and closed in an `ensure` before the parent advances (open question 2, closed against 3a's shipped `#peek`: a view read three bytes deep and closed disturbs nothing, a two-byte source's view answers `[a, b, nil]`), and `#skip(3)` only after all three matched, since `#skip` on a shorter source raises. A BOM-prefixed stream loses the BOM and nothing else; `data: xyz` keeps `xyz` and `xyzdata: y` dispatches nothing (a three-byte skip would have made it `data: y`); `\xEF\xBBxdata: y` dispatches nothing; only ONE leading BOM is consumed; a BOM inside a value survives as U+FEFF and a BOM at the head of a later line makes that line an unknown field, never a consumed BOM; a stream shorter than three bytes is untouched (`reader_test.rb` `LookaheadTest`, seven `SSE-12` cases; `matrix_facts_test.rb`; guards 8, 9) |
| `SSE-13` | MUST | ✅ | 7 | `Reader#dispatch` answers an `Event` when `@seen` is true and nil otherwise: an id-only, a retry-only and a comment-only block each dispatch, `\n\n\n` dispatches nothing, and blank lines around two data blocks yield exactly two events (`DispatchTest`, three `SSE-13` cases; guard 17) |
| `SSE-14` | MUST | ✅ | 3, 7 | `LineReader#next_line` answers an unterminated final line as content (`a\ntail` → `["a", "tail"]`; `a\r` → `["a"]`); `Reader#next_event` dispatches a pending block once at EOF (`data: hello` → one event, then end; `data: a\n\ndata: b` → two) and signals end immediately for `""` and `"\n"` (`GrammarTest`, two `SSE-14` cases; `DispatchTest`, two; guard 4) |
| `SSE-15` | MUST | ✅ | 7 | The sentinel is `nil` (P7-22) and the end is a latch on the reader, `@ended`, checked before the source is touched: after the last event three further calls answer nil, and a source whose `#getbyte` resurrects bytes after its first nil is never read again (`DispatchTest`, two `SSE-15` cases; guard 18, whose sticky-end mutation is caught by the resurrecting duck the plan's cross-check asked for) |
| `SSE-16` | MUST | ✅ | 7 | The ONE item of state that survives a dispatch is `@bom_checked`: `retry: 500\ndata: a\n\ndata: b\n\n` gives `[500, nil]`, `id: 1 … / … / id: 3 …` gives `["1", nil, "3"]`, and the BOM flag DOES persist — a second block's leading BOM bytes are not consumed. The corpus entry saying the opposite (`sse-streaming/2dba42b0`, "current retry value, last event id") is superseded by `docs/knowledge/notes/sse-streaming.md` (`DispatchTest`, three `SSE-16` cases; guard 19) |
| `SSE-17` | MUST | ✅ | 3, 7 | Neither `LineReader` nor `Reader` answers `#close` or calls its source's: a real `BufferedSource` driven to completion is still open afterwards, in both suites (`ContractTest`; `DispatchTest`, "the reader never closes its source"; guard 20) |
| `SSE-18` | MUST | ✅ by omission | 7 | The MAY is taken: the reader holds no `Thread::Mutex` and its YARD states the single-threaded contract. There is no behavioural test, because no assertion distinguishes "documented single-threaded" from "accidentally single-threaded" (the design's *Five rows*); the one test pins the omission — no ivar of a `Reader` is a `Mutex` — so a lock is not added without a decision. The one lock in the subsystem is `Closeable`'s, on `Stream`, for `SSE-31` (`DispatchTest`, "the reader holds no lock") |
| `SSE-19` | MAY | ✅ taken | 2, 3, 7 | **The MAY the port takes, and the row that resolves phase 3a's line-cap finding.** Two documented bounds, both CHOSEN, both rejecting loudly and never truncating, both settable per reader (P7-21): `Dexpace::SSE::MAX_LINE_BYTES = 1024 * 1024` (`LineReader`, checked before each append — a line of exactly the cap passes, one byte more raises `LimitExceededError(kind: :line)`, at most one byte past the cap is ever pulled, bytes not characters) and `Dexpace::SSE::MAX_EVENT_BYTES = 8 * 1024 * 1024` (`Reader`, the raw bytes of every line of one block, comments and unknown fields included, reset at every blank line whether or not it dispatched — a block of exactly the cap passes, one byte more raises `kind: :event`, and three 5-byte fieldless blocks under a 12-byte cap raise nothing; the reset on a NON-dispatching blank line is review round 0's R0-1, guard 51). Both constants sit strictly below `Dexpace::IO::MAX_MATERIALIZED_BYTES`, asserted; the mutation battery at the real values names the constants and never the literals. **This is not `SSE-11`'s cap**, whose row is separate. The divergence is documented in the constants' YARD (naming `SSE-19`, the reference's absence of a maximum, `MAX_MATERIALIZED_BYTES` and the layer split), in `LimitExceededError`, in P7-21, in `docs/sdk-documentation/sse.md` and in the §10.18 amendment routed below; `documentation_test.rb` pins the sentences (`sse_test.rb`; `line_reader_test.rb` `CapTest`; `reader_test.rb` `EventCapTest`; `limit_exceeded_error_test.rb`; guards 5–7, 46–48) |
| `SSE-20` | MUST | ✅ | 4 | `Event` is `Data.define(:id, :event, :data, :comment, :retry)` including `Dexpace::Model`, `.new` and `.[]` private, `.build` the factory: the list is deep-copied and frozen once through `Model.own` (`original << "c"; original[0] << "!"` reaches nothing; the list and its elements are frozen; the same reference from every accessor), the scalar Strings are frozen copies, and `#with` is `Model#with` routing through `.build` — no bespoke `#with` — so a derivation re-validates on every row (`with(retry: -1)` raises on 3.2.11, where `Data#with` alone would skip `#initialize`) and shares nothing mutable: the caller's list is never the derived event's. **One thing the design's `SSE-20` sentence overstates**: `Model.own` hands an ALREADY deep-frozen list back as it is (`Ractor.make_shareable(copy: true)` copies only what is not yet shareable), so a derived event may share its parent's frozen list — indistinguishable from a copy, since nothing can mutate either (`event_test.rb`, five `SSE-20` cases; guards 21, 22) |
| `SSE-21` | SHOULD | ✅ | 4 | `Data`'s equality, `eql?` and hash over all five members, a stable `#inspect` naming the type, `#to_s` the same, `pp` the same (`event_test.rb`, two `SSE-21` cases) |
| `SSE-22` | SHOULD | ✅ | 4 | `Event#empty?` is `id.nil? && event.nil? && data.empty? && comment.nil? && self.retry.nil?` — true only when all five are UNSET; a comment-only event, a `retry: 0`, an `event: ""` and a `data: [""]` are all not empty (`event_test.rb`, three `SSE-22` cases; guard 23) |
| `SSE-23` | MUST | ✅ | 8, 9 | `Stream` includes `Closeable`; the ONE resource is `resource:` (the source by default, P7-25), released by a private `#release` exactly once across every path a close-counting `FakeResponseBody` is driven through: clean end (1), three explicit closes (1), an explicit close after the automatic release (1), a block-form `break` (1), an enumerator abandoned then closed (0 then 1), a mid-stream failure (1), a raising block (1), a `LimitExceededError` (1), a typed `DONE` (1), a typed mapper failure (1); an owned resource must answer `#close` at construction, a borrowed one need not; `TypedStream` owns nothing and delegates (`stream_test.rb` `LifecycleTest`, `FailureTest`; `typed_stream_test.rb` `ViewTest`; guards 24, 25) |
| `SSE-24` | MUST | ✅ | 8 | `Stream#advance` releases through `finish` — `Dexpace.close_quietly(self, logger:)` — on the reader's nil, so a full iteration without `#close` releases once, and the external form releases on the pull that finds the end (three events pulled: 0; the `StopIteration` pull: 1); a fully consumed typed view releases too (`LifecycleTest`, two `SSE-24` cases; `typed_stream_test.rb` `ViewTest`; guard 24) |
| `SSE-25` | MUST | ✅ | 8, 9 | The block form's `drive` has an `ensure close` in the stream's own scope, so a `break` after one event releases once, and so does an `Enumerable` method that stops early on `#events` — `first(2)` releases once and closes the stream; the enumerator form asserts BOTH halves of §7.1's rule — abandonment after one `#next` releases NOTHING, two `GC.start`s later, and the explicit `#close` that is the documented remedy releases once — with the enumerator dropped inside a helper so no reference survives into the assertions. The typed layer mirrors both: `TypedStream#drive_values` carries an `ensure` of its own (since review round 0's R0-2 — it had `Stream#drive`'s rescue and not its ensure, so `values.first(1)` left the resource at 0 closes where `events.first(1)` released), so `first(1)`, `take(2)`, `find` and an `each { break }` on `#values` each release once and a release failure there propagates as the raw form's does (`LifecycleTest`, three `SSE-25` cases; `typed_stream_test.rb` `ViewTest`, two `SSE-25` cases and the `SSE-30` one; guards 26, 52) |
| `SSE-26` | MUST | ✅ | 8, 9 | `Stream#take_view!` latches `@viewed` before either shape is built and raises `Dexpace::SSE::StreamStateError` on a second request in either shape, and the typed layer's two shapes compete for the SAME flag through `Stream#each` / `#events`: `typed.values` then `typed.values`, `typed.each`, `stream.events` and `stream.each` all refuse (`stream_test.rb` `ViewTest`; `typed_stream_test.rb` `ViewTest`; `stream_state_error_test.rb`; guard 27) |
| `SSE-27` | MUST | ✅ | 8 | Requesting a view after `#close` raises `StreamStateError` naming the closed state, in both shapes; `advance` reads `closed?` BEFORE every pull, so a close between pulls ends the enumerator with `StopIteration`, the resource closed once, and the torn-down source — a closed `BufferedSource`, whose read would raise `ClosedError`, a `StandardError` that would otherwise take the failure path — is never read; after a failure released the stream, a further pull is a clean end (`ViewTest`, three `SSE-27` cases; `FailureTest`, one; guard 28) |
| `SSE-28` | MUST | ✅ | 8 | `Closeable#close`'s latch: three explicit closes release once; an explicit close after the automatic release leaves the count at one, because the automatic path closes `self` and flips the same latch (never `@resource` directly); an explicit close whose release raised still leaves the latch flipped and a second close a no-op (`LifecycleTest`, two `SSE-28` cases; `FailureTest`, the explicit-close case; guard 25) |
| `SSE-29` | MUST | ✅ | 8 | `Stream#drive`'s one `rescue ::Exception` — 6a's and 6b's close-then-re-raise spelling — calls `Dexpace.close_quietly(self, onto: error)` BEFORE the bare `raise`: a `ScriptedChunked` failure after one event surfaces on the second pull with the resource closed once, in the enumerator form and the block form (the first event delivered at count 0); a release failure is on the error's suppressed trail (`["close failed"]`); the caller's own block raising takes the same path; a `LimitExceededError` does too. The frozen-primary caveat (P4-13) is stated in the YARD at the site (`FailureTest`, five `SSE-29` cases; `typed_stream_test.rb`, the raw-failure case; guard 29) |
| `SSE-30` | MUST | ✅ | 8, 9 | Two call sites into one close-once helper, never two closes (design §10 entry and the charter's boundary 12). **Automatic**: `finish` is `Dexpace.close_quietly(self, logger: @logger)` — a raising release on the clean end is swallowed, all three events delivered, and REPORTED out of band as one WARNING `http.instrumentation.close` with `IOError: close failed` as its cause through the stream's `logger:` (5b's second disposal route; `RecordingSink`), never the event payload or a data byte; the typed `DONE` path reports the same way (P7-83). **Explicit**: `#close` and a block-form `break` go through `Closeable#close` and a release failure propagates once (`FailureTest`, four `SSE-30` cases; `typed_stream_test.rb` `LifecycleTest`, two; guard 30) |
| `SSE-31` | MUST | ✅ | 8 | Both of the conformance clause's shapes, deterministic (`R6`). **Shape A**, close between pulls, clean end — the `SSE-27` row; the one that distinguishes an implementation on every row. **Shape B**: a thread parked in `stream.each` over `BufferedSource.wrapping(reader_end)` of an `IO.pipe`, sequenced through a `Thread::Queue` and a status poll (3a's `IO-38` shape, never a sleep), the wrapping source its OWN resource, `stream.close` from the test thread — the parked `#getbyte` raises Ruby's own `IOError` ("stream closed in another thread"), the source and the pipe's read end are closed, the stream is closed, and the thread is joined. **What the matrix cannot show**: the latch is phase 2's `Thread::Mutex`-guarded flag and the mechanism claim inherits `IO-38`'s deferral — on every CRuby row the test passes with or without the lock (`docs/first-release.md` § Post-release triggers, the `IO-38` entry) (`ThreadAndResponseTest`; `matrix_facts_test.rb` `ThreadTest`; guard 31, run under a timeout, hangs on `reader.value` as the design predicts) |
| `SSE-32` | MUST | ✅ | 8 | `Stream.open(response)` takes a `Dexpace::Response` and nothing else, raises `InvalidArgumentError` "the response has no body to stream" for a nil body, builds the reader over `response.body.source` and OWNS the response: over a real `Response` built by `RecoveryFixtures#build_response` over a real `ResponseBody`, a full iteration leaves `response.body.closed?` true, an explicit close closes it once and its source refuses a later read with `ClosedError`; the caps and the logger reach the reader through `.open` too (`ThreadAndResponseTest`, four `SSE-32` cases; `ConstructionTest`; guards 32, 33) |
| `SSE-33` | MUST | ✅ | 9 | `TypedStream#map` calls the mapper with `(event.event, event.data.join("\n"))`: `["line1", "line2"]` arrives as `"line1\nline2"`, an empty data line as an empty segment, a no-data event as `""`, an absent name as nil and a present-but-empty one as `""`; the decoded value is yielded bare, nil included; the mapper is the block or any callable of two positionals, else `InvalidArgumentError` (`typed_stream_test.rb` `MapperTest`, seven cases; guard 34) |
| `SSE-34` | MUST | ✅ | 2, 9 | `TypedStream#deliver` compares by IDENTITY against the two frozen `Sentinel` singletons `Dexpace::SSE::SKIP` and `::DONE` (P7-23; the type is `Sentinel`, not the design's `Signal` — P7-81): SKIP drops and advances, DONE closes the stream through the quiet route and ends the iteration in both shapes without yielding a sentinel model, events after DONE are never decoded, and a value that `==` SKIP but is not it is yielded (`OutcomeTest`, five `SSE-34` cases; `sentinel_test.rb`; `sse_test.rb`; guard 35) |
| `SSE-35` | MUST | ✅ | 9 | The mapper runs inside the pull: 0 calls before the first `#next`, 1 after, 2 after the second; draining two SKIPs to produce one element makes three calls and leaves the fourth event untouched (`OutcomeTest`, two `SSE-35` cases; guard 36) |
| `SSE-36` | MUST | ✅ | 9 | A mapper raising propagates at that pull — `ArgumentError: nope` on the second `#next`, the first value delivered at count 0 in the block form — with the resource closed once BEFORE it surfaces, and a release failure on its suppressed trail in both shapes: the block form through `Stream#drive`'s rescue, the enumerator form through `TypedStream#drive_values`' own (`LifecycleTest`, three `SSE-36` cases; guard 37) |
| `SSE-37` | MUST | ✅ gate + tests | 10, 11 | **Three prohibitions, one mechanised and two asserted.** *No serialization dependency*: `gates:serde_boundary` — `tools/serde_boundary.rb`, `test/gates/serde_boundary_test.rb`, twenty-one unit fixtures and two fixture workspaces under `test/fixtures/gates/serde_boundary/` — scans `lib/dexpace/sse.rb`, `lib/dexpace/sse/**/*.rb` and their `sig/` mirrors with a PARSED scan (prism for every `require`/`require_relative`/`autoload` spelling through `RequireScan` and every constant read or path; the RBS lexer for every type name), refuses `json`, `json/*` and any `serde` path segment, `Serde`, `Dexpace::Serde`, `JSON`, `::JSON`, `self::JSON` and `Dexpace::Serde::JSON::Codec`, a file it cannot parse and a feature that is not a literal, asserts every `GUARDED` glob matches at least one file, and prints its `PENDING` rows on every run; the eighteenth gate, wired into `DEFAULT_GATES`, `default_task_test.rb`'s `EXPECTED` and the once-per-run `gates` CI job (P7-84). *No done-sentinel and no error-envelope recognition*: `[DONE]`, `DONE`, `event: done`, `{"done":true}` and `end` are ordinary data values, `event: error` is an ordinary event handed to the mapper undecoded, no SSE class's own ancestry or constant table reaches `Serde` or `JSON`, and a code-line text scan of every SSE file finds no serde require or constant (`boundaries_test.rb`, six `SSE-37` cases; guards 38–40) |
| `SSE-38` | MUST | ✅ by omission, asserted | 10 | No method of `Stream`, `TypedStream`, `Reader` or `LineReader` — private ones included — matches `reconnect|request|transport|last_event_id`, and no SSE code line names `Last-Event-ID`, `Dexpace::Request`, `Transport` or `reconnect`; a second event's id is nil when only the first block carried one; the retry hint is surfaced (`[5, nil]`) and acted on by nothing; an exhausted stream stays closed and refuses a new view; no listener contract is offered — `Stream`'s own methods are exactly `each`, `events`, `typed`, `open`, `owning`, `borrowing` (`boundaries_test.rb`, five `SSE-38` cases) |
| `SSE-39` | MUST | ✅ | 8, 9 | Open question 3 closed as the design intended: 3a's `FakeChunked` yielding one event per chunk under `BufferedSource.over` is pulled ONCE for one `#next` and twice for two, in the raw and the typed view; a stream built and never pulled pulls nothing; the typed layer drains SKIPs with exactly as many raw pulls as one element needs (`stream_test.rb` `ViewTest`, two `SSE-39` cases; `typed_stream_test.rb` `OutcomeTest`, two; `matrix_facts_test.rb`; guard 41) |
| `SSE-40` | SHOULD | ✅ | 8 | `Stream#events` is `to_enum(:drive)` over the private drive routine, lazy until pulled, single-pass through the same `@viewed` latch as `#each`, propagating a mid-stream failure at the offending pull, and reusing the one `Reader` so the BOM flag persists — a second BOM in a later value survives as U+FEFF. **Cited by hand**: `sse-streaming/5f4803a0` and `/b94ce49e` are this row's corpus entries and are filed under `PAGE-14` alone (`docs/knowledge/notes/sse-streaming.md`'s Reference entry) (`ViewTest`, two `SSE-40` cases; `FailureTest`, one; guard 27) |
| `SSE-41` | MAY | ⏳ | — | A reactive adapter's error and lifecycle latitude, declined for v1: `docs/first-release.md` § What v1 ships without › SHOULD- and MAY-level, the `SSE-41` entry ("v1 ships only the pull-based SSE view. Trigger: a reactive SSE adapter being built. ⏳ row: phase 7b"). No code; `SSE-39`'s pull-based property is what such an adapter would inherit. No `ASYNC-21` row is carried, per design §11 item 21 |

Cross-reference rows, the IDs this phase owns a share of:

| ID | Status | What 7b supplies, and where it is proven |
|---|---|---|
| `IO-9`, `IO-14`, `BODY-32` (phase 3a's line-cap finding) | ✅ closed, with three corrections | The bound the finding asked for exists at the layer it named, as `Dexpace::SSE::MAX_LINE_BYTES` (the `SSE-19` row); the obliging requirement is `SSE-19` and not `SSE-11`; and the premise is false — 7b is not `#read_line_utf8`'s consumer, because `IO-14` and `SSE-2` disagree about a lone CR (P7-20), so `#read_line_utf8` ends v1 unbounded and with no in-repository caller. The code half of the closure is the YARD on both `MAX_LINE_BYTES` and `#read_line_utf8` (`typed_reads.rb`, corrected in this phase: `SSE-11` → `SSE-19`, and "the caller … is phase 7's SSE machine" → the truth) and `docs/sdk-documentation/io.md:188`; `documentation_test.rb` pins both. Nothing about `P3-4` itself changes |
| `IO-19`, `IO-15`, `IO-11` (`#peek`, `#skip`, `#getbyte`) | ✅ consumed | The four `BufferedSource` members the layer uses, and the only ones: `#getbyte` is the whole read path, `#peek`/`#skip` the BOM lookahead, the view's `#close` the fourth member of `_ByteSource` (P7-27 as amended, P7-82). `#read_line_utf8` is not consumed |
| `IO-6` | ✅ consumed | `Stream.owning` over `BufferedSource.wrapping(reader_end)` closes the pipe's read end through the source's own ownership — the `SSE-31` shape-B mechanism |
| `IO-40` | ✅ by omission | Neither reader nor facade imposes a timeout; a stream that never sends a byte blocks until the transport's deadline (`resource-management/d1f16cad`) |
| `HTTP-41`, `HTTP-43`, `BODY-14`, `BODY-16` | ✅ consumed | `Stream.open` reads `response.body.source` — the same handle every call — and closes the response, whose `#close` forwards to the body's latch; `Response#body` is typed `Dexpace::Body?` and the factory is written against it (the `SSE-32` row) |
| `HTTP-3`, `HTTP-4`, `SEAM-29` | ✅ | `Event` follows the construction pattern without exception: `.new` and `.[]` private, keyword `.build`, `Model.own` on the list, `Model.frozen_string` on the scalars, field-named `InvalidArgumentError`s, `#with` through `.build`; `Sentinel` is the closed-set exception in `Pipeline::Stage`'s shape (`event_test.rb`; `sentinel_test.rb`) |
| `RECOV-1` (boundary 10) | ✅ honoured | `Dexpace::Outcome` gains no member; `SSE-34`'s outcomes are two `Sentinel` singletons inside `Dexpace::SSE` and a bare value (P7-23) |
| `RECOV-12`, `SEAM-30`, `XCUT-9` (boundaries 11–13) | ✅ call sites only | Every quiet close is `Dexpace.close_quietly` (four sites: `Stream#finish`, `Stream#drive`'s rescue, `TypedStream#deliver`'s DONE, `TypedStream#drive_values`' rescue), every suppression is its `onto:`, and 7b walks no cause chain; no second trail, no second route |
| `SEAM-14`, `XCUT-22` | ✅ | Ownership is construction-time: `Stream.owning` vs `.borrowing`, `Closeable#owned?`; a borrowed resource's `#close` is never called and a borrowing stream still latches |
| `PIPE-26`, `PIPE-27` | ✅ N/A here | 7b installs no step, dispatches no request and holds no transport; the pipeline is not touched (`boundaries_test.rb`, the `SSE-38` absence) |
| `OBS-20`, `XCUT-20` | ✅ through 5b | The one emission — `close_quietly`'s `http.instrumentation.close` diagnostic — runs inside `Instrumentation.contain`; 7b adds no event name (`Instrumentation::Events` stays at nine) and no key |
| `XCUT-15`, `XCUT-12` | ✅ by construction | `Event` is frozen with a deep-frozen list; the one lock is `Closeable`'s, held across the flip only, and `Ractor` is load-bearing nowhere |
| `HTTP-13` (boundary 19) | ✅ vacuous | 7b calls `downcase` nowhere; `SSE-7` compares exactly (P7-24) and guard 11 keeps it so |
| `CFG-1`–`CFG-38` | ✅ untouched | No configuration key: `SSE-19`'s "configurable" is the two constructor keywords on every constructor (P7-21) |
| `SEAM-1`, `SEAM-2` | ✅ | No new require anywhere under `lib/dexpace/sse/` — not `strscan`, not `stringio` — and the require allowlist is unchanged; `gates:require_allowlist` and `gates:clean_bundle` green on every row |
| `NFR-3` | ✅ | Ten new `sig/` mirrors, the strict `core` target green with no relaxation; `_ByteSource` is a recursive four-method interface (P7-82); `source`/`resource` are `untyped` for `BufferedSource.wrapping`'s reason |
| `NFR-4` | ✅ | Every addition is a widening; the manifest grew by exactly 43 rows, 1 137 → 1 180, read row by row against the object model (P7-85); the RBS baseline diff is vacuous until the first tag |
| `NFR-11` | ✅ | No constant outside `Dexpace::` and the stdlib allowlist in any of the ten new signatures |
| `NFR-13` | ✅ for `.rb`; the `.rbs` half is phase 10's | The forty-six new `.rb` files — nine under `lib/`, one under `tools/`, one under `test/gates/`, twelve suites and three doubles under `gems/dexpace-core/test/`, and the twenty Ruby fixtures under `test/fixtures/gates/serde_boundary/` (seventeen under `files/`, three across the `workspace/` and `empty_glob/` roots; excluded from the cop, header carried anyway) — open with the two headers the `Dexpace/SpdxHeader` cop gates; the seventeen new `.rbs` files (nine `sig/` mirrors, eight fixtures) carry no SPDX line, as no `.rbs` in the repository does. Review round 0's R0-4 corrected the count words here: the first draft said twenty-nine, fourteen suites and twenty-one fixtures |
| `NFR-17` | ✅ | The eighteenth gate is blocking, in `DEFAULT_GATES` after `gates:require_allowlist`, in `gates:list`, in CI's once-per-run `gates` job, and driven red by `test/gates/serde_boundary_test.rb` against a fixture workspace |

## What was built

Nine new `lib/` files under `gems/dexpace-core/lib/dexpace/`: the namespace file `sse.rb` (the three
limits and the two sentinel constants, 3a's `io.rb` precedent) and eight under `sse/` —
`sentinel.rb`, `limit_exceeded_error.rb`, `stream_state_error.rb`, `line_reader.rb`, `event.rb`,
`reader.rb`, `stream.rb` and `typed_stream.rb` — every one public, every one mirrored in `sig/` and in
`test/`. Two earlier `lib/` files changed in place: `lib/dexpace.rb` gains a nine-line `# Phase 7b:`
block after 6b's and before the closing comment, and `io/typed_reads.rb`'s YARD on `#read_line_utf8`
loses the wrong requirement ID and the false premise (Task 12's code half; no code line changed).
The private constants — `LineReader::LF`/`CR`, the reader's `BOM`, `COLON`, `SPACE`, the four
BINARY field names, `DIGITS_ONLY`, `MAX_RETRY_DIGITS` and three byte constants, and
`LimitExceededError::KINDS` — are `private_constant`, so none reaches the manifest. One new gate:
`tools/serde_boundary.rb`, the `gates:serde_boundary` task appended at the END of `namespace :gates`
in `tasks/gates.rake`, its name in the root `Rakefile`'s `DEFAULT_GATES` after
`gates:require_allowlist`, in `test/gates/default_task_test.rb`'s `EXPECTED` and in
`.github/workflows/ci.yml`'s `gates` job, with `test/gates/serde_boundary_test.rb` and the fixtures
under `test/fixtures/gates/serde_boundary/` (`files/`, `workspace/`, `empty_glob/`). The smoke suite
gains `SSE_LAYER = %i[SSE]` and a `PhaseSevenLayers` case. Three new top-level test-support files,
one object per file: `ScriptedChunked` (a design-§10.2 body whose script raises where an `Exception`
sits — the mid-stream failure and a per-byte yield counter), `FakeByteSource` (the `_ByteSource` duck,
used in exactly two tests to keep P7-27's claim behavioural and in the two at-scale cap tests) and
`SSEFixtures` (`FIXTURE`, `byte_source`, `failing_source`, `counting_resource`, `gathered`,
`consume_one` and the one shared `stream_over(bytes = FIXTURE, resource: nil, **) -> [stream,
resource]`). The plan's `Dexpace::Test` namespace and its five doubles were never written: the tree's
own objects answer every assertion (Deviations 3 and 4). Twelve new suites — eleven under
`test/dexpace/sse/` plus `test/dexpace/sse_test.rb`: one per `lib/` file (nine, `stream_state_error_test.rb`
among them since review round 0's R0-3, which found it cited and not written), and three with no `lib/`
mirror that say so — `matrix_facts_test.rb` (the design's eight facts and the build's, a standing test
on every row), `boundaries_test.rb` (`SSE-37`/`SSE-38`'s absences) and `documentation_test.rb` (the
line-cap closure's prose). The surface manifest was regenerated once, 1 137 → 1 180, all 43 rows read
against the object model. Documentation: `docs/sdk-documentation/sse.md` (every example run on 4.0.6
and 3.2.11), `docs/knowledge/notes/sse-streaming.md` (two supersessions, three references), and the
`io.md`, `quality-gates.md`, `architecture.md`, README, `docs/README.md`, `CLAUDE.md` and roadmap
edits the docs PR carries; `docs/first-release.md` is untouched, its `SSE-41` entry true as written.

## Matrix facts, re-run on every interpreter

The design's eight facts and the ones the build found were run on 2026-09-20 on **3.2.11, 3.3.12,
3.4.10 and 4.0.6**, first as a scratch script per interpreter and then as
`test/dexpace/sse/matrix_facts_test.rb`, a standing test on every CI row (nineteen cases in three
nested classes). Every fact holds identically on every row except the one the suite pins against
`RUBY_VERSION`: `Data#with` skips an `#initialize` override on 3.2.11 and runs it on 3.3.12, 3.4.10
and 4.0.6 — the known floor difference `Dexpace::Model#with` exists for, and why `Event` includes
`Model`. Confirmed on every row: `Integer(s, exception: false)` accepts all six of `+5`, `-5`,
`0x10`, `1_0`, ` 5` and `5\n`; the anchored pattern rejects all nine adversarial inputs including the
full-width digits and matches a BINARY `5000`; `force_encoding` on a frozen String raises even to its
own encoding and `String#b` returns an unfrozen BINARY copy; `(+"".b) << "é"` retags to UTF-8; an
`Enumerator` abandoned mid-`#next` and a `def each` driven through `to_enum` both skip their
`ensure`, with `block_given?` true inside; a thread parked in `readpartial` or `getbyte` on an
`IO.pipe` read end that another thread closes raises `IOError` ("stream closed in another thread")
and closing the WRITE end gives `EOFError`; the same through `BufferedSource.wrapping` closes the pipe
too; the BOM is `[239, 187, 191]`; a `#peek` view read three bytes deep and closed disturbs the parent
by nothing and a two-byte source's view answers `[97, 98, nil]`; `#skip(3)` on a two-byte source
raises `EndOfStreamError`; a read on a closed `BufferedSource` raises `ClosedError`, a
`StandardError`; `FakeChunked` under `BufferedSource.over` is pulled once for a three-byte peek plus
nine `#getbyte`s and twice on the tenth; the two-step decode turns `a\xFFb` into `a�b` and keeps `é`,
and a same-encoding `#encode` with no options validates nothing (6c's trap); `Closeable`'s latch flips
before a raising `#release` and a borrowing close releases nothing; `pp` on a `Data` ignores an
`#inspect` override and honours `#pretty_print`. **One fact the cross-check stated is false on every
row**: after a mid-stream failure, `BufferedSource.over`'s next `#getbyte` does not answer nil — the
enumerator's dead fiber is replaced and `#each` restarts, so the pull re-delivers the stream's first
byte (Findings routed). The facade never meets it: `SSE-27`'s `closed?` check runs first.

## Guards run red

Every guard the dispatch brief's list asks to be seen red was seen red, on 4.0.6 and on 3.2.11, and
the bytes restored after each: forty-six single-edit mutations of `lib/` (the brief's forty-three,
three of which are not writable as a code edit and are recorded as such, plus six of this build's own)
through a harness that applies the edit, runs the owning suites under `ruby -w` with a 180-second
timeout per suite, captures the first failure and restores the file, and three more run by hand
against the gate and the type checker. On the first 4.0.6 pass three mutations crashed the suite at
load on an unused-variable or statement-not-reached warning (`FatalWarnings`, `NFR-6`'s rule) rather
than failing an assertion — guards 1, 3 and 29 — and were re-spelled to keep the code reachable; one
(guard 9, the BOM consumed at construction) hung the stream suite's shape-B test rather than failing
it, because a construction-time `#peek` read blocks on the pipe in the TEST thread before the reader
thread is started, and was killed after ten minutes — the reader suite catches it by assertion, and
the timeout is why the harness has one now; and one was written wrong twice — guard 22 as the plan
spelled it (a bespoke `#with` over `super`) reaches `Model#with` through `super` and is an equivalent
mutant, and the assertion the build first added against it (`refute_same(event.data, derived.data)`)
turned the UNMUTATED suite red, because `Model.own` hands an already deep-frozen list back as it is
(`Ractor.make_shareable` copies only what is not yet shareable) — so the guard is now "drop `include
Model`", the test asserts validation on derivation, and the mutant is caught on 3.2.11 and survives
on 4.0.6 as an equivalent mutant, where `Data#with` calls `#initialize` itself. **Forty-six of
forty-six caught on 3.2.11; forty-five of forty-six on 4.0.6**, the one survivor the equivalent
mutant just described; guard 44 is a deliberately inert control that must stay green on both rows,
and did. **Review round 0 (2026-09-20) ran forty-six of its own plus two controls, and the two
controls are what found the round's two defects** — each was the PROPOSED fix applied to the
unmutated tree, and each left its suite green, which is the suite saying it could not tell the fix
from the defect: `dispatch`'s nil branch returned before `reset_block`, so a run of fieldless blocks
accumulated into `SSE-19`'s event cap (no test wrote a blank-line-separated run of unknown-field,
NUL-id or rejected-retry blocks under a small cap); and `TypedStream#drive_values` had `Stream#drive`'s
rescue and not its ensure, so `values.first(1)` released nothing where `events.first(1)` released once
(no test called an early-stopping `Enumerable` method on either shape). Both were fixed on the code
branch and both controls became guards — **51 and 52, each red on both rows** against the pre-fix
`lib/` and green after it, so the battery is forty-eight, forty-eight caught on 3.2.11 and forty-seven
on 4.0.6, guard 22 still the one equivalent mutant.

| # | Mutation (the brief's numbering; 44–50 are this build's; 51–52 are review round 0's) | Red on 4.0.6 | Red on 3.2.11 |
|---|---|---|---|
| 1 | `SSE-2`: a lone CR is content (`return false unless byte == LF`, so the CR branch is unreachable) | `GrammarTest` "a lone CR terminates a line by itself" and nine more, `ContractTest` "a lone CR at the end of one pull" | 10 failures, `line_reader_test.rb` |
| 2 | `SSE-2`: CRLF as two terminators (never read the byte after a CR) | 7 failures — "CRLF is a single terminator" (`["one", "", "two"]`), the mixed cases, the property test | 7 failures |
| 3 | `SSE-2`: drop the pushback (`@pushback = nil if following`) | 7 failures — `a\rb\n` → `["a", ""]`, the property test | 7 failures |
| 4 | `SSE-14`: nil instead of the pending content at EOF | 4 failures in `line_reader_test.rb` ("a final line with no terminator", the duck test) and `reader_test.rb`'s "a partial block still present at EOF is dispatched" | 4 failures |
| 5 | `SSE-19`: `>` instead of `>=` before the append | "a line of exactly the cap passes and one byte more raises" (no raise at +1), "rejects before materialising", the at-scale +1 | 4 failures |
| 6 | `SSE-19`: `kind: :event` from the line cap | `error.kind` expected `:line` | 1 failure |
| 7 | `SSE-19`: `max_line_bytes:` defaulting to `MAX_EVENT_BYTES` | "the cap defaults to MAX_LINE_BYTES", the at-scale +1 passes | 2 failures |
| 8 | `SSE-12`: three bytes skipped unconditionally | 22 failures and 17 errors — `data: xyz` becomes the unknown field `a`; a short stream raises `EndOfStreamError` | 22 failures, 17 errors |
| 9 | `SSE-12`: the BOM consumed at construction | `LookaheadTest` "the BOM is consumed on the first pull, not at construction" (`yielded` 1, not 0); the stream suite's shape-B test HANGS (killed) | 1 failure |
| 10 | `SSE-3`/`SSE-5`: `lstrip` instead of one space | 4 failures — `"  hello"` expected, `" spaced"` comment | 4 failures |
| 11 | `SSE-7`: a `downcase` on the field name | "field names are compared CASE-SENSITIVELY" (`DATA: x` dispatches) | 1 failure |
| 12 | `SSE-9`: `@seen = true` before the NUL screen | `DispatchTest` "a NUL id does not count as a field seen" — the one test that catches it | 1 failure |
| 13 | `SSE-9`: a NUL id overwrites a prior valid id (`@id = nil`) | "a NUL id does not overwrite a valid id" (`good` expected) | 1 failure |
| 14 | `SSE-10`: `event` defaulted to `"message"` | "an absent event field is absent and is never defaulted" and one more | 2 failures |
| 15 | `SSE-11`: `Integer(value, exception: false)` instead of the pattern | `RetryTest`: `-100` reaches `Event.build` and raises `InvalidArgumentError` | 1 error |
| 16 | `SSE-11`: drop the `MAX_RETRY_MS` comparison | "a value above the documented cap is ignored", "an over-cap retry does not overwrite" | 2 failures |
| 17 | `SSE-13`: dispatch a block with no field seen | 27 failures — `\n\n\n` yields events, `garbage: zzz\n\n` dispatches | 27 failures |
| 18 | `SSE-15`: the end not latched (re-check the source) | "once end is reported, the source is never read again" — the resurrecting duck yields an event on the third call | 1 failure |
| 19 | `SSE-16`: `retry` carried across blocks (not reset) | "nothing but the BOM flag persists" (`500` expected nil), "every accumulator resets" | 2 failures |
| 20 | `SSE-17`: `@source.close` on the reader's nil | "the reader never closes its source, driven to completion" | 1 failure |
| 21 | `SSE-20`: `data.freeze` (shallow) instead of `Model.own` | `original[0] << "!"` reaches inside (`FrozenError` on the shared element, the mutate-the-original case) and "the elements are frozen" | 2 failures, 1 error |
| 22 | `SSE-20`: `Event` without `include Model`, so `#with` is `Data#with` | **survives — equivalent on 4.0.6**, where `Data#with` calls `#initialize` and so validates | "#with copies the data list" — `event.with(retry: -1)` raises nothing, because `Data#with` skips `#initialize` on the floor |
| 23 | `SSE-22`: `#empty?` ignoring `comment` | "a comment-only keep-alive reports non-empty", the five-way case | 2 failures |
| 24 | `SSE-23`/`SSE-24`: no release on the reader's nil | "iterating to completion releases once" (count 0), and the swallowed-failure cases raise `IOError` on the explicit close that now does the work | 2 errors |
| 25 | `SSE-24`/`SSE-28`: `@resource.close` directly on the automatic path | "an explicit close after an automatic release leaves the count at one" (2), the swallowed-failure case raises `IOError` | 3 failures, 2 errors |
| 26 | `SSE-25`: drop `drive`'s `ensure close` | "a partial consume through the block form releases on exit" (count 0), "a release failure on a block-form break propagates" | 2 failures |
| 27 | `SSE-26`/`SSE-40`: drop the `@viewed` latch | "obtaining an iterator twice fails loudly", "#each after #events also fails", and the typed suite's "single-pass across both shapes" | 2 failures per suite |
| 28 | `SSE-27`: no `closed?` check at the top of `#advance` | "a close observed between pulls ends iteration cleanly" (`ClosedError`, a `StandardError`, takes the failure path instead of `StopIteration`), "never reads the torn-down source", "after a failure … a further pull is a clean end" | 3 failures |
| 29 | `SSE-29`: no release before the error propagates (`close_quietly(nil, onto:)`) | "a mid-stream read failure releases before propagating" (count 0), "release failure … attached as suppressed" (empty trail) | 2 failures |
| 30 | `SSE-30`: the automatic path through `Closeable#close` (loud) | "a release failure on the automatic terminal path is swallowed" raises `IOError` and the delivered events are lost; the logger case | 2 errors |
| 31 | `SSE-31`: the shape-B stream owns a `FakeResponseBody` instead of the pipe source (a test-side edit, run by hand under `timeout 60`) | **HANGS** on `reader.value` — `timeout` exit 124 — the design's stated failure mode | exit 124 |
| 32 | `SSE-32`: `response.body` as the resource instead of `response` | **equivalent mutant under the real `Response`**, whose `#close` IS `body&.close`; recorded, not chased, as the brief says | equivalent |
| 33 | `SSE-32`: drop the nil-body raise | "opening over a bodyless response fails loudly" — `NoMethodError` (`source` on nil), not `InvalidArgumentError` | 1 failure |
| 34 | `SSE-33`: `data.join` with `""` | "the mapper receives the data lines joined with a single newline", the empty-segment case | 2 failures |
| 35 | `SSE-34`: `DONE` treated as `SKIP` (no close, no stop) | "DONE ends iteration cleanly, closes the stream" (count 0), "DONE through the block form", "events after a DONE sentinel are never decoded" | 3 failures |
| 36 | `SSE-35`: eager decoding in `#values` (`to_a` before the enumerator) | "decoding is lazy — one mapper call per pull" (calls 3 before the first pull), "draining Skips" (4 not 3), and the mapper-failure cases raise at `#values` | 3 failures, 2 errors |
| 37 | `SSE-36`: the mapper's error rescued and the loop retried | "a mapper that raises propagates at that pull" (nothing raised), "a release failure … attached as suppressed", the block-form case | 3 failures |
| 38 | `SSE-37`: `[DONE]` recognised in `Reader` | `boundaries_test.rb` "[DONE] is an ordinary data value" (`[["[DONE]"]]` alone) | 1 failure |
| 39 | `SSE-37` gate: `require "json"` in `reader.rb` (by hand) | `rake gates:serde_boundary` red — `reader.rb:9: require "json" -- a serialization dependency in a guarded file (SSE-37)` — and `rake gates:require_allowlist` red for the same `reader.rb:9` (`SEAM-2`); then `Dexpace::Serde`, `::JSON` and `require "json"` in a COMMENT only: the gate stays GREEN (`4 guarded globs clean`), which is what the parsed scan buys and what the plan's regex would have failed | run once, on the development Ruby (the gate is interpreter-independent) |
| 40 | `SSE-37` gate: a `GUARDED` glob typo (`sse/**/*.rbx`) | `rake gates:serde_boundary` red — `matches no file, so SSE-37's boundary would be checked against nothing` — and `test/gates/serde_boundary_test.rb` red (3 failures) | run once |
| 41 | `SSE-39`: a `@lookahead` prefetch in `#advance` | "pulling one event does not read ahead into the next" (`yielded` 2), and seven more — the prefetch also reads past the closed check | 7 failures, 4 errors |
| 42 | §7.1: the resource inside the enumerator's block or the drive routine — by reading, as the brief says | `@resource` appears at exactly two sites in `stream.rb`, `#initialize` (:120) and `#release` (:231); neither `drive`, `drive_values` nor either `to_enum` names it, and `initialize_closeable` runs in `#initialize` alone | — |
| 43 | RBS: `_ByteSource#peek` narrowed to `Dexpace::IO::BufferedSource` (by hand) | `steep check` GREEN and `gates:rbs_surface` GREEN — the `core` target checks `lib/` alone, where every source IS a `BufferedSource`, so no type gate sees the duck; the interface's structural claim is proven behaviourally by `FakeByteSource` in `line_reader_test.rb`'s and `reader_test.rb`'s P7-27 cases, and this row says so rather than claiming a red the tree cannot produce | — |
| 44 | control: an inert edit (`@retry = milliseconds if false` after the cap check) | GREEN, as it must be | GREEN |
| 45 | `SSE-26`/`SSE-27`: the two refusals in `take_view!` swapped (`closed?` twice) | "#each after #events also fails" (a second view is not refused) | 2 failures |
| 46 | `SSE-19`: `>=` instead of `>` on the event total | the exact-cap block raises (`EventCapTest`, the at-scale and the 32-byte cases) | 2 errors |
| 47 | `SSE-19`: `kind: :line` from the event cap | `error.kind` expected `:event` | 1 failure |
| 48 | `SSE-19`: the block byte total not reset at dispatch (`@block_bytes` never zeroed — an unset ivar) | 55 errors — `NoMethodError` on `nil` | 55 errors |
| 49 | `SSE-34`: `==` instead of `equal?` on `SKIP` | "the outcome comparison is identity — a value that == a sentinel is yielded" | 1 failure |
| 50 | `SSE-6`: a comment does not count as a field seen | "a retry-only block and a comment-only block both dispatch", and the comment-only event's `nil` | 1 failure, 2 errors |
| 51 | `SSE-1`/`SSE-19`: `dispatch` returns nil for a fieldless block BEFORE `reset_block` (the byte total carried across blank lines) — review round 0's R0-1 | `EventCapTest` "the event byte total resets at every blank line, dispatching or not": `LimitExceededError ... 12-byte limit ... kind=event` on `data: a\n\n` + three `zz: 1\n\n` blocks | 1 error |
| 52 | `SSE-25`: `TypedStream#drive_values` without its `ensure @stream.close` — review round 0's R0-2 | `ViewTest` "an Enumerable method that stops early on #values releases" (`Expected: 1 Actual: 0`) and "a release failure on a typed block-form break propagates" (nothing raised) | 2 failures |

## Audit groups run

The phase-start pair first, at implementation: `--origin note --brief` returned 56 note entries
across 22 files; `--section conflicts --brief` returned 19 entries with every harvested conflict
`[overridden by notes/…]` and none open. The thirteenth audit group's `SSE` slice — `--topic
sse-streaming --section rules,constraints,conclusions --brief` — returned 51 entries across one
topic file, **zero tagged `[appendix-B roll-up]`**, and `--prefix-info SSE` / `--gaps SSE` report 41
of 41 substantive and no gap; chapter 13 was read in full, its `*Conformance:*` clauses included,
which is where `SSE-31`'s two shapes, `SSE-17`'s instrumented source and `SSE-35`'s counted decoder
come from. `--req` was run per task. The five note entries the dispatch binds were read and applied:
`pipeline/86343352` (no pillar step here, so no fork — the rule's only site in 7b is the negative
`SSE-38` assertion), `pipeline/7ce4431d` (applied nowhere: the two re-raises in the phase are bare
`raise`s of the error just rescued, never a carried one), `error-handling/5322e965` (the trail is
`Suppressible`; 7b writes none), `execution-context/b58728da` (no `private_constant` of `Dexpace`
is reached; every private constant is the class's own) and `url-and-query-encoding/08c54234` (no
URI in the phase).

| Group | Result at implementation |
|---|---|
| Public API surface | `module-organization/1828a984` (one public constant per file) holds for every new file — `sse.rb` carries the module and its five value constants, `io.rb`'s precedent; `api-design/b0e18938` is why `Sentinel` has no public factory (the design's `Signal.build` dropped, P7-81), why `TypedStream.new` is private and reached from `Stream#typed` alone (`Logger` → `Event.send(:new)`'s precedent), why every byte constant is private, and why `Stream` exposes no `#logger`; every public name is in P7-27 as amended by P7-81/P7-82/P7-85 |
| RBS / Steep typing | Ten new mirrors, the strict target green; `_ByteSource` grew its fourth method (`close`) because the reader closes its peek view (P7-82); `LineReader#next_line`'s loop re-assigns through a fresh local (`following`) because Steep narrows `byte` after the nil check and refuses `Integer?` back into it; `Reader#bom_ahead?` returns the `begin` body's value so no local crosses the `ensure`; `MAX_RETRY_MS` is the literal `2_147_483_647` because `Integer#**` types as `Numeric` |
| Minitest conventions | Every suite subclasses `DexpaceTestCase`; the reader suite is five nested classes, the stream suite five, the typed suite four, the line-reader suite three and the matrix-facts suite three under `Metrics/ClassLength` (6c's and 6b's shape); every encoding assertion is non-ASCII; the seeded property test prints its seed on failure; two inline cop disables with reasons in `SSEFixtures` (`Lint/UnreachableLoop` on the one-event `break`, `Style/MapIntoArray` on the block-form collector), 5c's precedent |
| Fiber scheduler, thread safety | One lock in the phase, `Closeable`'s on `Stream`; `Reader` and `LineReader` hold none by contract; the one thread the suites start is joined (`DexpaceTestCase#teardown` counts); `Stream#events` and `TypedStream#values` are `Enumerator`s and inherit `Enumerator#next`'s own fiber rules — the typed BLOCK form is a plain loop over `Stream#each` and pays no fiber hop |
| Encoding and binary strings | Bytes are BINARY until a field value is extracted; the retag is `String#b` then `force_encoding` on the unfrozen copy, never on a frozen slice; `encode(UTF_8, UTF_8, invalid: :replace, undef: :replace)` names both encodings (P7-26); the caps count bytes |
| Resource lifecycle and stream ownership | `Closeable` included, never rebuilt; the resource on the object, never in the enumerator's block; no `block_given?` guard; `close_quietly` the one quiet route and `Closeable#close` the one loud one; `resource-management/1676974d` — GC is not a cleanup hook — is why the abandonment test asserts the ABSENCE of a release |
| Serialization, SSE and pagination | Every `SSE` rule in the group restates a clause implemented above; `sse-streaming/2dba42b0`, `/8c25db7d` and `/e98a0668` now print `[overridden by notes/sse-streaming.md]`; `/ebb489ba` (the require audit) is `gates:serde_boundary`; nothing of `SERDE` or `PAGE` is consumed |

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate. Items
1–24 are where the built tree overrode the plan's assumptions, in the order the dispatch's as-built
list gives them; 25–36 are this build's. The ones that touch public behaviour, the contract a later
phase cites, or a statement the design makes are also the as-built ledger rows P7-81–P7-86.

1. **No interpreter was installed and no `mise use -g` was run**: all four rows exist under
   `~/.local/share/mise/installs/ruby/`, one `bin` put first on `PATH` per command. The plan's
   `tools/verify_7b_facts.rb` was not written; the facts are `test/dexpace/sse/matrix_facts_test.rb`,
   a standing suite in the shape every phase since 5a used.
2. **The member stays `retry`, RBS accepts it, and no `retry_ms` fallback and no P7-28 row exist**;
   on the Ruby side `Event#initialize` cannot write `retry = …` (it parses as the `retry`
   statement, "statement not reached") or `super(retry: retry)` (a `SyntaxError`), so the four other
   members are re-assigned and forwarded by a bare `super`, and the retry hint is validated AFTER
   `super` through its own reader — allocation-free, where the shorthand hash and `binding` are not.
3. **No `Dexpace::Test` namespace and no five-class support file.** The doubles convention is
   top-level, one object per file, plus one shared `<Phase>Fixtures` module the suites `include`,
   required as `require_relative "../../support/<file>"`. `SSEFixtures` defines the `FIXTURE` the plan
   used and never defined, as `"data: a\n\ndata: b\n\ndata: c\n\n".b.freeze`.
4. **Four of the plan's five doubles are the tree's own objects.** `CountingResource` is
   `FakeResponseBody.new(nil, close_error:)` with `#closes`; `CountingBody` is 3a's `FakeChunked` with
   `#yielded` under `BufferedSource.over`; `FakeSSEResponse` is `RecoveryFixtures#build_response(200,
   body: response_body(…))`, a real `Response` over a real `ResponseBody`, the assertion being
   `response.body.closed?`; `PipeSource` is `BufferedSource.wrapping(reader_end)` over `IO.pipe` with
   3a's `IO-38` handshake; `ByteSource.new` is `BufferedSource.of_bytes`. One new double,
   `ScriptedChunked`, replaces both `ByteSource.failing_after` and `CountingBody`; `FakeByteSource` is
   the optional second, used in two duck tests and — because its `#getbyte` is three method calls where
   `BufferedSource`'s is a dozen and a String allocation — in the two at-scale cap tests (item 30).
5. **`_ByteSource` has four methods**: `getbyte`, `skip`, `peek` and `close`, the last because the
   reader closes its peek view in an `ensure` and the strict target would otherwise refuse (P7-82).
6. **`Stream.open` is typed and written against `Dexpace::Body?`**, `Response#body`'s real type;
   the design's "typed `Dexpace::ResponseBody?`" sentence is stale (3b's P3-15 narrowed to the
   contract, not to the class).
7. **`MAX_RETRY_MS` is the literal `2_147_483_647`**, the plan's `(2**31) - 1` being
   `Ruby::IncompatibleAssignment` under strict Steep; `LineReader#next_line`'s loop assigns the next
   byte to a fresh local before re-binding; nothing in the phase carries a `Metrics/CyclomaticComplexity`
   disable — `Reader#apply_line` hands the four-name dispatch to `apply_field`.
8. **The suites are split into nested classes** and the plan's fences were re-spelled where the cops
   objected: `%w[]` where an array is words, no `calls += 1; d` semicolons, `error` never `e`, a blank
   line before every assertion, the abandonment test's enumerator dropped inside a helper rather than
   `enum = nil`.
9. **The design's `Signal` is `Sentinel`** (P7-81): `::Signal` is a Ruby core module on every row,
   so a bare `Signal` inside `module Dexpace::SSE` would have been a third documented shadow beside
   `Method` and `IO`; the manager's decision (1), and `PhaseSevenLayers` asserts `Signal` still
   resolves to Ruby's for a class including `Dexpace::SSE`. No cop change.
10. **Every value constant inside a class is `private_constant`** — `LF`, `CR`, `BOM`, `COLON`,
    `SPACE`, the four field names, `DIGITS_ONLY`, `MAX_RETRY_DIGITS`, the three byte constants and
    `KINDS` — declared after the definitions in the defining file, so none reached the manifest; the
    43 rows are exactly the object model's.
11. **The automatic release closes `self`, never `@resource`**, and SSE-30's "reported out of band" is
    a real emission: the three factories take `logger: Instrumentation::Logger::NULL`, validated
    `is_a?(Instrumentation::Logger)` (6b's shape), passed to both `close_quietly` sites, and the
    swallowed failure lands on a `RecordingSink` as `http.instrumentation.close` (P7-83; the
    manager's decision (3)). `Instrumentation::Events` stays at nine.
12. **The decode is the plan's fence**, retag on an unfrozen `String#b` copy then `encode(UTF_8, UTF_8,
    invalid: :replace, undef: :replace)`, frozen; the same-encoding trap 6c found does not bite it
    because the options are what make it scrub, and `matrix_facts_test.rb` pins that.
13. **The gate lives where the tree keeps gates**: `tools/serde_boundary.rb` (`module SerdeBoundary;
    extend self; def violations(root)`), the task appended at the end of `namespace :gates`,
    `test/gates/serde_boundary_test.rb < GateCase` with `assert_gate_rejects`-style task runs, fixtures
    under `test/fixtures/gates/serde_boundary/`, `DEFAULT_GATES` after `gates:require_allowlist`,
    `EXPECTED` in `default_task_test.rb`, and the once-per-run `gates` CI job — NOT the matrix, whose
    set is pinned to the three zero-dependency checks plus `single_instance` and whose rationale a
    text scan does not meet. Eighteen replaces seventeen in `CLAUDE.md`, `README.md`,
    `docs/sdk-documentation/quality-gates.md` (row 9, the rest renumbered, "gates 7, 8, 10 and 14")
    and `default_task_test.rb`'s comment; the phase-0 records say seventeen and are not edited.
14. **The scan is parsed, not the plan's regexes.** `RequireScan.calls` for the require half, a prism
    walk over `ConstantReadNode`/`ConstantPathNode` (`full_name_parts`, with the dynamic-parent and
    missing-node errors rescued to the last segment) for the constant half, and the RBS lexer's
    `tUIDENT` tokens for the `sig/` half — so `sse.rb`'s YARD may say "names no Dexpace::Serde
    constant" and the design's "a whole JSON document" and stay green (guard 39's second half).
15. **7b built the gate alone, with `page/**` PENDING** (the manager's decision (2)): both the `lib/`
    and the `sig/` pagination globs are on the printed list, and their move to `GUARDED` is the
    reconcile pass's after both lanes are on `main`. 7c builds nothing for it.
    *Reconciled 2026-09-20:* the move happened — 7c's stack was rebased onto `main` `34f52e8` (this phase's docs tip) and its code branch carries the one `chore:` commit that guards `page.rb`, `page/**` and both `sig/` mirrors under "spec-forced boundary 5", leaving `PENDING` empty.
16. **`lib/dexpace.rb`'s `# Phase 7b:` block is appended after 6b's**, nine lines, nothing reordered;
    `sse.rb` requires `sse/sentinel` before assigning `SKIP`/`DONE`; the smoke suite's `LAYERS` gains
    `SSE_LAYER = %i[SSE]` and a `PhaseSevenLayers` class; the namespace file's mirror is
    `test/dexpace/sse_test.rb`; `sentinel_test.rb`, `limit_exceeded_error_test.rb` and
    `stream_state_error_test.rb` each exist — the third since review round 0 (R0-3), which found
    this sentence and the `SSE-26` row citing a file the tests branch did not hold. No
    `private_constant` FILE was added, so `CLAUDE.md`'s eighteen-file list is unchanged.
17. **Every constant and attribute carries YARD**; `Sentinel#pretty_print` was added so the
    "identifies itself in a log" claim holds under `pp` (6c's P6-72); YARD is at 100% (215
    constants, 82 attributes, 808 methods, 0 undocumented at the wip tip).
18. **Task 12's code half had its real target**: `typed_reads.rb:180`'s YARD (`SSE-11` → `SSE-19`,
    and the false premise replaced) and `docs/sdk-documentation/io.md:188`, both corrected in the same
    change as the cap; `documentation_test.rb` pins the method's YARD as well as `sse.rb`'s.
19. **Documents that already carried the routed items were cited, not re-edited**: the
    knowledge-lookup thirteenth row (live), the appendix-C `SSE-19` asymmetry (the roadmap's 2026-09-13
    inbound bullet, `docs/deviations.md`, `docs/first-release.md`'s `C11`), `SSE-41`'s ⏳ entry and the
    `IO-38` trigger. `docs/knowledge/notes/sse-streaming.md` did not exist and is filed (the manager's
    decision (4)); the roadmap's mention of a `resource-management.md` note draft has no draft behind
    it in the design and none is filed.
20. **Ledger numbering**: the design's rows stand as `P7-20`–`P7-27`; the as-built rows start at
    `P7-81`; `P7-28` is never used.
21. **Eight cops, not six**; none of the three ban cops has a site; `name.to_s.upcase` is unargumented.
22. **The cap decision is consistent with the tree**: plain constants plus per-reader keywords (3b's
    `MAX_BUFFERED_ERROR_BODY_BYTES` shape), no `Configuration::Keys` entry, and the layering assertion
    compares against `IO::MAX_MATERIALIZED_BYTES`, the default constant.
23. **After a mid-stream failure the source does NOT read as EOF** — the cross-check's claim 23 is
    false on every row (the enumerator restarts); no test asserts a second raise or a nil, and the
    facade's `closed?` check is what keeps it unreachable. The rescue spelling is 6a's and 6b's
    `rescue ::Exception` with the inline reason, in `Stream#drive` and `TypedStream#drive_values`, so
    an `Interrupt` inside the caller's block or the mapper releases the resource too; the plan's
    `StandardError` in `#advance` was not written — `advance` has no rescue at all, the one site being
    the drive routine both shapes share.
24. **The manager's four decisions were applied as given**: `Sentinel`; the gate in the `tools/` shape
    with `page/**` PENDING; `logger:` on the three factories with the emission through
    `close_quietly`; the corpus note filed on the docs branch.
25. **The plan's Task 9 ran green on its first run**: `stream.rb` and `typed_stream.rb` were written
    together because `Stream#typed` names `TypedStream` and `stream.rb` requires it, so the red run
    Task 9 expected was Task 8's `NameError`; Task 10's suite ran red twice on its own shape (an
    ancestry check that read `JSON::GeneratorMethods` off `Object` once another gem's suite had loaded
    the json gem in the same `test:gems` process, fixed by excluding `Object.ancestors`; a
    case-insensitive scan that matched the YARD's "last-event-id", fixed by scanning code lines) before
    green.
26. **`TypedStream` drives the two shapes differently, and neither reaches a private method of
    `Stream`.** The block form is `@stream.each { … }` — a plain loop, `Stream#drive`'s rescue and
    `ensure`, no fiber — and the external form is `to_enum(:drive_values, @stream.events)`, the raw
    enumerator taken eagerly at `#values` so the one view is latched then; DONE closes through
    `Dexpace.close_quietly(@stream, logger:)` with the logger handed over at construction, and the one
    `send` in the layer is `TypedStream.send(:new, …)` from `Stream#typed` (`Logger#event` →
    `Event.send(:new)`'s precedent). `deliver` answers `:done`/`:more`, not a boolean, under
    `Naming/PredicateMethod`.
27. **`Stream#each` and `TypedStream#each` take `&` and forward it** (`Naming/BlockForwarding`); with
    no block, `yield` raises Ruby's `LocalJumpError` at the first event — no `block_given?` guard is
    written, per the plan's ban.
28. **`Sentinel` has no `.build`**: the design's P7-27 listed `Signal.build`, but a public factory for
    a closed two-instance set is a name `NFR-4` would lock for nothing, so `.new` and `.[]` are private
    and `SKIP`/`DONE` are minted in `sse.rb` through `send(:new)` (buffered_source.rb's
    `__dexpace_view` precedent); `#with` refuses, in `Pipeline::Stage`'s shape (P7-81).
29. **The event cap counts every line of the block**, comments and unknown fields included, because the
    cap's subject is the block and a block padded with comment lines is the same surface; the check
    runs before the line is applied. Stated in `Reader#max_event_bytes`'s YARD.
30. **The two at-scale cap tests run over `FakeByteSource`**, not a `BufferedSource`: the machine
    costs ~0.9 µs per byte through `BufferedSource#getbyte` (a mutex acquisition and a one-byte
    String allocation per call, 3a's design) and ~0.3 µs through the duck, and the 8 MiB battery took
    14 s on 4.0.6 and 21 s on 3.2.11 over the real source — more than the whole core suite. The caps
    under test are the reader's, P7-27 makes the duck a conforming source, and the battery now costs
    ~3.5 s per row. The throughput itself is a finding, routed below.
31. **The `SSE-11` battery has twelve rejected forms**, the plan's nine plus a trailing space, a
    trailing tab and `12abc`, and the width check refuses a 4,096-digit run before `Integer()`.
32. **`SSE-12`'s tests discriminate a three-byte skip**: the plan's `data: \xEF\xBB` assertion compared
    raw bytes against a decoded value and could not; `xyzdata: y` and `\xEF\xBBxdata: y` — which a
    three-byte skip turns into the valid line `data: y` — can.
33. **The `SSE-15` sticky-end test uses a resurrecting duck** whose `#getbyte` yields bytes again after
    its first nil, as the cross-check's guard 18 asked, because a scripted chunked's finished
    enumerator would have kept a non-sticky reader green.
34. **`Stream.borrowing` takes `logger:` too** although it never releases: the typed DONE path on a
    borrowed stream still closes quietly through the same helper, and one constructor shape per phase
    is 5b's rule.
35. **`Stream.open` validates `is_a?(Response)`**: the sig says `Dexpace::Response` and the facade
    reads `#body` and calls `#close` on it, so a duck is refused by name rather than failing on `#body`.
36. **`Enumerable#first(n)` on `Stream#events` closes the stream**: `first` iterates internally and
    breaks, which is a block-form exit and runs `drive`'s `ensure close`; the released resource is the
    safe direction and `sse.md` says so. **And on `TypedStream#values` too, since review round 0's
    R0-2**: the external typed drive runs the raw enumerator, so an early exit through its block never
    reached the Stream's ensure, and `values.first(1)` stranded the resource (closes 0 against the
    raw form's 1) until `#close`; `drive_values` now carries the same `ensure`, a loud release on that
    exit and a no-op on the clean end, a `DONE` and both failure paths, whose latch has already
    flipped.
37. **Review round 0's fixes** (2026-09-20), one per branch: `Reader#dispatch` resets the block on
    its nil branch too and builds the `Event` through a private `build_event` (code; R0-1);
    `TypedStream#drive_values` gains its `ensure` (code; R0-2); `reader_test.rb` `EventCapTest`,
    `typed_stream_test.rb` `ViewTest` and `stream_test.rb` `LifecycleTest` gain the cases guards 51
    and 52 name, and `stream_state_error_test.rb` is written (tests; R0-1–R0-3); this document's
    count words, the design's As-built addendum and `sse.md`'s two `rescue`-less blocks are
    corrected (docs; R0-4, R0-5). No public name, signature or manifest row changed; `reader.rbs`
    gains one private line.

## Findings routed

- **The design's seven findings were verified at their owners.** (1) Task 12 built the code half —
  the YARD on `MAX_LINE_BYTES` and on `#read_line_utf8`, and `io.md` — and the prose half of the
  closure is the two sentences in the `SSE-19` cross-reference row above. (2) `P3-4`'s row in phase
  3a's design is that phase's record and is not edited; `docs/deviations.md` is phase 10's to flip,
  and the correction is stated in `typed_reads.rb`'s own YARD, which is where a reader of `P3-4` is
  sent. (3) Appendix C's `SSE-19` row: already the roadmap's 2026-09-13 inbound bullet
  (`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`, "Appendix C's `SSE-19` row drops the
  port sanction"), `docs/deviations.md`'s interim note and `docs/first-release.md`'s `C11` — cited,
  none edited. (4) and (5) The four attribution defects and the `SSE-16` supersession are filed as
  `docs/knowledge/notes/sse-streaming.md` (two `## Superseded` entries, three `## Reference`), and
  `ruby scripts/verify_knowledge_structure.rb` is OK afterwards. (6) The charter's two corrections are
  the charter's own record and are not edited by 7b. (7) The knowledge-lookup thirteenth row is live
  (`.claude/skills/knowledge-lookup/SKILL.md`, "Serialization, SSE and pagination").
- **New, routed to phase 10's inbound list** as audit work against already-planned phases, by date
  and content: (a) **`BufferedSource.over`'s enumerator restarts `#each` after a mid-stream failure**
  — `Enumerator#next` on a fiber that died by exception starts over, so a second read after a raise
  re-delivers the body's first bytes rather than nil or a second failure, on every row (phase 3a's
  residue; the SSE facade is shielded by `SSE-27`'s check, a bare `Reader` driven again after a raise
  is not); (b) **the per-byte read path costs ~0.9 µs per byte through `BufferedSource#getbyte`** — a
  `Closeable#closed?` mutex acquisition and a one-byte `String` allocation per byte — so an SSE stream
  parses at roughly 1 MiB/s on 4.0.6; the design fixes `#getbyte` as the primitive (P7-20) and the
  bulk path that would lift it (`read_into` into the line buffer, or a cheaper `TypedReads#getbyte`
  reading the head chunk in place) is a phase-10 performance item against 3a and 7b together, not a
  7b decision.
- **The §10.18 amendment**: both cap constants should join §10.18's list of platform-constant
  substitutions beside `SSE-11`'s, as the design recommends; `docs/sdk-design-ruby/` is frozen, so the
  consolidation of P7-20–P7-27 and P7-81–P7-86 into design §10 and the §10.18 text are a human's, as
  for every phase since 3a. `docs/deviations.md` is untouched, for phase 10 to flip.
- **The dispatch brief's task count**: the plan has thirteen tasks; the brief's "14 tasks" and
  "Task 14" name one it does not have. Recorded here so the checklist's task numbers are read against
  the plan.

## Postponed work

**`SSE-41` only**, declined for v1 (`docs/first-release.md`, cited above); no code, no trigger named
beyond the reactive adapter. **What earlier phases postponed here has landed**: phase 3a's line-cap
finding (Task 12, closed with its three corrections). **What this phase leaves to others, none of it
its own to defer**: the `page/**` rows' move from `PENDING` to `GUARDED` (the reconcile pass, after 7c
is on `main`); the enumerator-restart residue and the per-byte throughput (phase 10, cited above); the
`IO-38` mechanism claim `SSE-31` inherits (the non-CRuby CI row trigger). `ASYNC-21`'s backpressure
obligation is inherited by phase 8 from `SSE-39`'s pull path rather than rebuilt.
