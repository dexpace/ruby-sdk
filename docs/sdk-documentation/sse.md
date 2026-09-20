# Server-Sent Events

**As built by phase 7b, in `dexpace-core`, written against source on 2026-09-20.** This page says what
chapter 13 gives an SDK author today: the WHATWG line machine and the field state machine over it, the
immutable five-field event value, the resource-owning single-pass streaming facade with its three
factories, and the typed adapter over a caller-supplied mapper with its three outcomes. What each is
*required* to do is `docs/product-spec/13-server-sent-events-and-streaming.md` (`SSE-1`–`SSE-41`); how
the design maps it to Ruby is `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md` §7.2, read
together with §7.1's `Enumerator` rule and entries 6 and 18 of
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`; the per-requirement
proof is `docs/work/mvp/phase7/phase7b/2026-09-10-phase7b-server-sent-events-checklist.md`. Signatures
live in `gems/dexpace-core/sig/dexpace/sse.rbs` and `gems/dexpace-core/sig/dexpace/sse/`, and this page
does not restate them. Every example below was run against the built code on 4.0.6 and 3.2.11 and
printed the same on both (the one difference is the wording of Ruby's own `NoMethodError` for a private
`new`, which the first example shows in 4.0's spelling). The examples use three test doubles from
`gems/dexpace-core/test/support/` — `FakeResponseBody`, whose `#closes` counts and whose `close_error:`
raises, `ScriptedChunked`, whose script raises where an `Exception` sits, and `RecordingSink` — because
a stream owns a resource and reports through a logger, and neither is something a page example should
do for real; `SSE` is `Dexpace::SSE` throughout and `source(bytes)` is
`Dexpace::IO::BufferedSource.of_bytes(bytes.b)`.

**Nothing here talks to a socket, decodes JSON or reconnects.** `SSE-37` makes the layer
format-agnostic — no done-sentinel string, no error-envelope recognition, no serialization
dependency, and `gates:serde_boundary` scans every file of it to keep the third clause true — and
`SSE-38` leaves reconnection and last-event-id continuity to the caller: the layer surfaces each
event's own `id` and `retry` hint and acts on neither. The one extension point is the typed adapter's
mapper, whose vocabulary is `SKIP` and `DONE`.

## The limits and the two sentinels: `Dexpace::SSE`

The namespace holds three Integers and two frozen singletons. `MAX_LINE_BYTES` (1 MiB) and
`MAX_EVENT_BYTES` (8 MiB) are `SSE-19`'s two caps, taken as the port's documented divergence from a
reference that imposes no maximum: an over-long line, or an event block whose raw lines total more,
is **rejected** with `LimitExceededError` from the pull that crosses the bound, never truncated, and
both are settable per reader through the `max_line_bytes:` / `max_event_bytes:` keywords on every
constructor below — there is no configuration key, because the caller constructs the reader and is
the configuration source. `MAX_LINE_BYTES` is the bound phase 3a's line-cap finding asked for, at the
layer that knows what a line means; it is a different bound at a different layer from
`Dexpace::IO::MAX_MATERIALIZED_BYTES`, not a second ceiling under it, and phase 3a's
`#read_line_utf8` — which `IO-14` keeps unbounded and which no file in this repository now calls —
stays as it was ([io.md](./io.md)). `MAX_RETRY_MS` (2^31 − 1) is `SSE-11`'s cap on the `retry` field
and **not** the line cap; a larger value is ignored rather than wrapped, since Ruby's Integers cannot
overflow.

```ruby
SSE::MAX_LINE_BYTES                                  # => 1048576
SSE::MAX_EVENT_BYTES                                 # => 8388608
SSE::MAX_RETRY_MS                                    # => 2147483647
SSE::SKIP                                            # => Dexpace::SSE::SKIP
SSE::DONE.to_s                                       # => "Dexpace::SSE::DONE"
SSE::SKIP.equal?(SSE::DONE)                          # => false
SSE::Sentinel.new(name: :other)
# => NoMethodError: private method 'new' called for class Dexpace::SSE::Sentinel
```

`SKIP` and `DONE` are the two instances of `Sentinel`, a `Data` whose constructors are private and
whose `#with` refuses, so the set is closed and every outcome comparison in the layer is `equal?`
against one of the two constants — a decoded model that happens to `==` a sentinel is still a value.
Both print as their constant's name under `to_s`, `inspect` and `pp`. The design named the type
`Signal`; it ships as `Sentinel` because a bare `Signal` inside `module Dexpace::SSE` would shadow
Ruby's `::Signal`, and `NFR-4` locks whichever name ships (the checklist's as-built row).

## The line machine: `LineReader`

`SSE::LineReader.new(source, max_line_bytes: SSE::MAX_LINE_BYTES)` reads `SSE-2`'s three terminators
natively over any source answering `#getbyte` — a `Dexpace::IO::BufferedSource`, or a duck — and hands
back each line's content as a fresh frozen BINARY `String` with the terminator stripped, `nil` once the
source is exhausted before any byte; a final line with no terminator is content (`SSE-14`). It is
built over `#getbyte` and **not** over phase 3a's `#read_line_utf8`, because the two grammars disagree
on the one clause that matters: `IO-14` keeps a lone `\r` as content and `SSE-2` makes it terminate a
line (P7-20). The machine's only state beyond the source is a one-byte pushback: after a CR it reads
one further byte to tell CR from CRLF, holding it for the next line when it is not LF — so a line
terminated by a lone CR cannot come back until one more byte arrives, a property of the grammar
WHATWG shares and one that reaches only a CR-terminating server. The cap is checked before each
append, so an over-long line is refused the moment it crosses the bound, with at most one byte past
the cap ever pulled.

```ruby
lines = SSE::LineReader.new(source("one\ntwo\r\nthree\rfour"))
lines.next_line                                      # => "one"
lines.next_line                                      # => "two"
lines.next_line                                      # => "three"
lines.next_line                                      # => "four"
lines.next_line                                      # => nil
lines.max_line_bytes == SSE::MAX_LINE_BYTES          # => true
SSE::LineReader.new(source("#{"x" * 65}\n"), max_line_bytes: 64).next_line
# => Dexpace::SSE::LimitExceededError: an SSE line exceeded its 64-byte limit and was rejected,
#    not truncated (SSE-19)
e.kind, e.limit                                      # => [:line, 64]
```

The line reader owns nothing and closes nothing (`SSE-17`); its source outlives it.

## The event value: `Event`

`SSE::Event` is `Data.define(:id, :event, :data, :comment, :retry)` including `Dexpace::Model`, built
through `Event.build(id: nil, event: nil, data: [], comment: nil, retry: nil)` with `.new` private
(the construction pattern of every core model). `data` is the ordered list of raw per-line values
exactly as the wire carried them, never joined (`SSE-8`); `event` is the raw field and `nil` when the
block sent none, never defaulted to `"message"` (`SSE-10`); `id` is the block's own and never a
carried last-event-id (`SSE-16`); `retry` is a non-negative millisecond count. A present-but-empty
field is `""` or `[""]`, distinct from an absent `nil` (`SSE-4`). The list is deep-copied and frozen
once at construction through `Model.own`, so neither the list the parser accumulated into nor a
caller's later mutation reaches inside (`SSE-20`), and `#with` routes through `.build` and copies it
again; equality, hash and the string form are over all five fields (`SSE-21`).

```ruby
event = SSE::Event.build(id: "7", event: "tick", data: %w[a b], retry: 5000)
event
# => #<data Dexpace::SSE::Event id="7", event="tick", data=["a", "b"], comment=nil, retry=5000>
event.data.frozen?                                   # => true
event.with(id: nil).id                               # => nil
SSE::Event.build.empty?                              # => true
SSE::Event.build(comment: "keep-alive").empty?       # => false
SSE::Event.build(event: "").empty?                   # => false
```

`#empty?` (`SSE-22`) is true only when all five fields are *unset*: a comment is content, and a
present-but-empty name or data line is not "unset".

## The field machine: `Reader`

`SSE::Reader.new(source, max_line_bytes:, max_event_bytes:)` sits on a `LineReader` over any source
answering `#getbyte`, `#peek` and `#skip`, and `#next_event` answers the next `Event` or `nil` once the
source is exhausted with nothing pending — Ruby's stream-terminator sentinel, sticky because the end is
a latch on the reader (`SSE-15`, P7-22). Everything below the decode is a **byte** operation on the
BINARY line: the split at the first colon (`SSE-3`), the one-space strip (`SSE-5`), the comment test
on the first byte (`SSE-6`), the exact, **case-sensitive** match of the four field names (`SSE-7`,
P7-24 — `DATA:` is an unknown field), the NUL screen on an `id` before it can count as a field seen
(`SSE-9`), and the anchored digits-only screen on `retry`, which refuses everything `Integer()` would
have accepted — `+5`, `0x10`, `1_0`, `" 5"` — and ignores a value above `MAX_RETRY_MS` (`SSE-11`).
Each extracted value crosses the one decode boundary once, retag-then-transcode with both encodings
named and `invalid: :replace` (P7-26), so `text/event-stream`'s UTF-8 arrives as UTF-8 Strings and an
invalid byte becomes U+FFFD rather than a raise. A blank line dispatches the block when any field was
seen (`SSE-13`); end of stream dispatches a pending block once (`SSE-14`); the one item of state that
survives a dispatch is the "BOM already consumed" flag (`SSE-16`), and the BOM is consumed on the
**first pull**, through the source's non-consuming `#peek`, so a reader built and never pulled touches
its source zero times and a non-BOM prefix is left intact (`SSE-12`).

```ruby
wire = "\xEF\xBB\xBFid: 1\nevent: greeting\ndata: héllo\ndata: wörld\n\n:keep-alive\n\n" \
       "retry: 5000\n\nid: a\0b\ndata: x\n\ndata: tail"
reader = SSE::Reader.new(source(wire))
reader.next_event
# => #<data Dexpace::SSE::Event id="1", event="greeting", data=["héllo", "wörld"], comment=nil, retry=nil>
reader.next_event
# => #<data Dexpace::SSE::Event id=nil, event=nil, data=[], comment="keep-alive", retry=nil>
reader.next_event.retry                              # => 5000
reader.next_event.id                                 # => nil       (a NUL id is ignored entirely)
reader.next_event.data                               # => ["tail"]  (SSE-14: dispatched at EOF)
reader.next_event                                    # => nil
reader.next_event                                    # => nil
SSE::Reader.new(source("DATA: x\n\n")).next_event                     # => nil
SSE::Reader.new(source("retry: +5\ndata: x\n\n")).next_event.retry    # => nil
SSE::Reader.new(source("data: a\xFFb\n\n")).next_event.data           # => ["a�b"]
```

The reader owns nothing and closes nothing (`SSE-17`), and it is single-threaded by contract with no
lock of its own (`SSE-18`, the MAY taken): drive one reader from one thread at a time, and reach for the
facade when a `#close` must come from another.

## The facade: `Stream`

`SSE::Stream` includes phase 2's `Dexpace::Closeable` and is the one object in the layer that owns
anything: **exactly one** closeable resource, released **exactly once** across every termination path —
clean end, explicit `#close`, block-form exit, partial consume, mid-stream failure, and the typed
adapter's `DONE` (`SSE-23`). A stream reads from one thing and owns one thing, and they are two
parameters: `source` is what the reader pulls bytes from and `resource:` the one closeable the facade
releases, defaulting to the source itself (P7-25). Three factories, named against a trap —
`Dexpace::IO::BufferedSource.over` means *borrowing* and `.wrapping` means *owning*, so none of these
is `.over`: `Stream.owning(source, resource: source)` owns the resource, `Stream.borrowing(source,
resource: source)` flips its own latch on `#close` and releases nothing, and `Stream.open(response)`
reads `response.body.source` and owns the **response**, raising `Dexpace::InvalidArgumentError` when
the body is `nil` (`SSE-32`). Every factory takes `max_line_bytes:`, `max_event_bytes:` and a
`logger:` (an `Instrumentation::Logger`, `Logger::NULL` by default).

Two consumption shapes, both single-pass and both taking the same one view: `#each { |event| }` and
`#events -> Enumerator`. Requesting a second view in either shape, or any view after `#close`, raises
`StreamStateError` (`SSE-26`, `SSE-27`, `SSE-40`). The resource lives on the stream and never inside
the enumerator's block: an `Enumerator` abandoned mid-`#next` never runs its `ensure` (design §7.1),
so external iteration gets its release from the clean end or from `#close`, which is the documented
remedy for an abandoned enumerator, while the block form releases on every exit in the stream's own
scope. An `Enumerable` method that stops early — `first(n)`, `take`, `find` — leaves the block form's
`ensure` to close the stream, so the stream is finished after it.

```ruby
body = FakeResponseBody.new(nil)
stream = SSE::Stream.owning(source("data: a\n\ndata: b\n\ndata: c\n\n"), resource: body)
stream.owned?                                        # => true
stream.events.first(2).map(&:data)                   # => [["a"], ["b"]]
body.closes                                          # => 1   (first(2) stopped early: released)
stream.close; body.closes                            # => 1   (SSE-28: idempotent)
stream.events
# => Dexpace::SSE::StreamStateError: this stream is closed; no iterator can be requested (SSE-27)

body2 = FakeResponseBody.new(nil)
stream2 = SSE::Stream.owning(source("data: a\n\ndata: b\n\n"), resource: body2)
got = []
stream2.each { |ev| got << ev.data.first }
[got, body2.closes, stream2.closed?]                 # => [["a", "b"], 1, true]
```

`SSE-30`'s asymmetry is two call sites into one close-once helper, never two closes. The automatic
terminal paths — the clean end and a typed `DONE` — release through `Dexpace.close_quietly(self,
logger:)`: a release failure there is swallowed and reported out of band as one
`http.instrumentation.close` WARNING through the stream's `logger:` (nothing under the default
`Logger::NULL`), so the events already delivered are never discarded by a close that failed after
them. An explicit `#close`, and a `break` out of the block form, go through `Closeable#close`, whose
release failure propagates once. A mid-stream failure — the source's, a `LimitExceededError`, or an
error raised by the caller's own block — releases **before** it propagates, with a release failure
attached to it as suppressed through `Dexpace.attach_suppressed` (`SSE-29`; a frozen primary is the
documented no-op, P4-13). `#close` is safe from another thread (`SSE-31`): the latch's mutex is held
across the flip only, the drive routine reads `closed?` before every pull so a close between pulls ends
the iteration cleanly, and a close during a blocked read tears the resource down under the reader,
surfacing as the source's own `IOError`.

```ruby
failing = Dexpace::IO::BufferedSource.over(ScriptedChunked.new("data: a\n\n", Dexpace::StreamError.new("boom")))
body3 = FakeResponseBody.new(nil, close_error: IOError.new("close failed"))
enum = SSE::Stream.owning(failing, resource: body3).events
enum.next.data                                       # => ["a"]
enum.next
# => Dexpace::StreamError: boom
Dexpace.suppressed(e).map(&:message)                 # => ["close failed"]
body3.closes                                         # => 1

sink = RecordingSink.new
logger = Dexpace::Instrumentation::Logger.build(sink: sink)
body4 = FakeResponseBody.new(nil, close_error: IOError.new("close failed"))
stream4 = SSE::Stream.owning(source("data: a\n\n"), resource: body4, logger: logger)
stream4.events.map { |e| e.data.first }              # => ["a"]   (delivered, the failure swallowed)
sink.payloads.first["event"]                         # => "http.instrumentation.close"
sink.payloads.first["cause"]                         # => "IOError: close failed"

borrowed = FakeResponseBody.new(nil)
stream5 = SSE::Stream.borrowing(source("data: a\n\n"), resource: borrowed)
stream5.each { |_e| nil }
[stream5.closed?, borrowed.closes]                   # => [true, 0]
```

Over a real `Dexpace::Response` — here one built through `Response.builder` over a
`Dexpace::ResponseBody` — `Stream.open` binds the stream's lifecycle to the response: closing the
stream closes the response, which forwards to its body's own latch (`HTTP-43`).

```ruby
stream6 = SSE::Stream.open(response)
stream6.events.map(&:data)                           # => [["a"], ["b"]]
response.body.closed?                                # => true
SSE::Stream.open(bodyless_response)
# => Dexpace::InvalidArgumentError: the response has no body to stream (SSE-32)
```

Delivery is pull-based with no read-ahead (`SSE-39`): the parser advances the source only when the
consumer asks for the next event, a body yielding one event per chunk is pulled once per pull, and a
blocking source read is the backpressure. The layer imposes no timeout of its own (`IO-40`); a stream
that never sends a byte blocks until the transport's own deadline fires.

## The typed adapter: `TypedStream`

`stream.typed { |event_name, data| ... }` — or `stream.typed(mapper)` with any callable of two
positionals — answers a `TypedStream`, which is not a second `Closeable`: it delegates `#close` and
`#closed?` to the stream and owns nothing, so `SSE-23`'s exactly-one claim survives it. The mapper is
called per pulled event with the raw `event` field (`nil` when absent) and the data lines joined with
a single `"\n"` (`""` when there were none) — the one join in the layer, deferred here from the parser
(`SSE-33`) — and its answer is one of three outcomes (`SSE-34`): `SSE::SKIP` drops the event and
advances, `SSE::DONE` ends the iteration cleanly and closes the stream through the quiet route without
yielding a model for the sentinel event, and anything else — `nil` included — is the decoded value,
yielded bare (P7-23). Decoding is lazy and per element (`SSE-35`): the mapper runs inside the pull, and
the adapter pulls only as many raw events as one element needs to drain `SKIP`s. A mapper that raises
propagates at that pull, with the resource released first and a release failure on its suppressed
trail (`SSE-36`). The two shapes mirror the stream's, `#each { |value| }` and `#values ->
Enumerator`, both taking the stream's one view, and `TypedStream` does not include `Enumerable` — one
view per stream is the single-pass discipline, and `Enumerable` would hand a caller thirty methods that
each silently take it.

```ruby
wire2 = "data: 1\n\n:ping\n\ndata: 2\n\ndata: [DONE]\n\ndata: 3\n\n"
body7 = FakeResponseBody.new(nil)
typed = SSE::Stream.owning(source(wire2), resource: body7).typed do |name, data|
  next SSE::SKIP if data.empty?          # the keep-alive
  next SSE::DONE if data == "[DONE]"     # THIS API's sentinel, known to this mapper alone

  [name, Integer(data)]
end
typed.values.to_a                                    # => [[nil, 1], [nil, 2]]
[body7.closes, typed.closed?]                        # => [1, true]   ("3" was never decoded)

body8 = FakeResponseBody.new(nil)
enum8 = SSE::Stream.owning(source("data: a\n\ndata: b\n\n"), resource: body8)
             .typed { |_n, d| raise ArgumentError, "bad #{d}" if d == "b"; d }.values
enum8.next                                           # => "a"
enum8.next
# => ArgumentError: bad b
body8.closes                                         # => 1
```

The `[DONE]` above is the mapper's convention and not the SDK's: to the reader it is an ordinary data
value, and a stream whose data line is `[DONE]` yields an ordinary `Event` and carries on (`SSE-37`).

## What is deliberately not here

- **No done-sentinel, no error-envelope recognition, no serialization dependency** (`SSE-37`). An event
  named `error` is an ordinary event; `[DONE]` is an ordinary data value; nothing under
  `lib/dexpace/sse/` requires `json` or names `Dexpace::Serde`, and `gates:serde_boundary` — a parsed
  scan over every require, constant read and RBS type name under the guarded paths — is what keeps it
  so. Whatever convention a generated SDK follows lives in its mapper.
- **No reconnection and no last-event-id continuity** (`SSE-38`, `SSE-16`). The layer surfaces each
  event's own `id` and `retry` and constructs no request, sets no `Last-Event-ID` header and reopens
  nothing; the second event's `id` is `nil` when only the first block carried one.
- **No reactive adapter** (`SSE-41`, a MAY declined for v1 by `docs/first-release.md`). `SSE-39`'s
  pull-based, no-read-ahead property is implemented on the pull path, so an adapter that arrives later
  inherits the backpressure rather than rebuilding it.
- **No strict-WHATWG mode.** The chapter's deliberate deviations — comment exposure, permissive
  dispatch, EOF partial-dispatch — are replicated, as design §11 item 17 settles.
- **No timeout, no lock in the parser, no second quiet-close route, no second suppressed trail.**
  `IO-40` keeps deadlines with the transport; `SSE-18` leaves the reader single-threaded; `SSE-30`'s
  quiet route is `Dexpace.close_quietly` and `SSE-29`'s trail is `Dexpace.attach_suppressed`, both
  phase 4b's.
- **No configuration key** for either cap. `SSE-19`'s "configurable" is the two constructor keywords,
  and phase 5's chain is untouched.
- **No `Stream.over`.** The name means the opposite one namespace away, and the facade's three
  factories say which way ownership goes.
