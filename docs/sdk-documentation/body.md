# The body layer

**As built by phase 3b, in `dexpace-core`, written against source on 2026-09-16.** This page says
what a body is between a caller and a socket: one shared contract, eight factories over seven
request-body variants, one response body, the materialize-once guard, the bounded error copy, the two
logging wrappers, the one decode boundary and the lazy typed-response wrapper. What each is
*required* to do is `docs/product-spec/06-request-and-response-body-lifecycle.md`; how the design
maps it to Ruby is `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.1 and §7.3; the
per-requirement proof is
`docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-checklist.md`. Signatures live in
`gems/dexpace-core/sig/dexpace/http/`, and this page does not restate them. Every example below was
run against the built code on 4.0.6 and 3.2.11 and printed the same on both. The byte-streaming
layer this sits on is [`io.md`](./io.md); read that page's first section before writing a class that
`include Dexpace`, because every constant here is flat under `Dexpace::` for the reason it gives.

## The contract: `Dexpace::Body`

Every body includes `Dexpace::Body` and implements one method, **`#write_to(sink) -> Integer`** —
`HTTP-36`'s single write-to-sink operation, where `sink` is anything responding to `#write`. The
module supplies the rest: `#media_type` (`nil` by default), `#content_length` (the `-1` sentinel by
default, never `nil`), `#replayable?` (`false` by default — `BODY-1` makes replay a property a body
earns), `#to_replayable` (`self` when already replayable, otherwise one drain into a buffer-backed
body), `#each` derived from `#write_to` so a body is also the `#each`-yielding-BINARY
representation every transport iterates, and `==`/`eql?`/`hash` defaulting to identity, which the
fixed-bytes variants override by value. Two more members are the read side a response body needs
and `Response` is written against: `#source`, whose default raises a named `Dexpace::StreamError`
because a request body has no read handle, and `#close`, whose default is a no-op because a body
owning no transport resource has nothing to release.

```ruby
body = Dexpace::Body.string("héllo")
body.class                # => Dexpace::BytesBody
body.replayable?          # => true
body.content_length       # => 6   -- bytes, not characters
body.media_type           # => nil
sink = Dexpace::IO::Buffer.new
body.write_to(sink)       # => 6
sink.snapshot             # => "h\xC3\xA9llo"
body.each.to_a            # => ["h\xC3\xA9llo"]
```

Bytes are always `Encoding::BINARY`: every chunk a body yields, every snapshot and preview, every
byte written to a sink. The one place bytes become text is `Response#body_string`, below.

## The eight factories and what each classifies

`HTTP-38` says factories classify replayability **by source**, so there is one place for them.

| Factory | Class | Replayable | Closes |
|---|---|---|---|
| `Body.bytes(string)`, `Body.string(text, encoding:)` | `BytesBody` | yes — an independent frozen copy | nothing |
| `Body.buffer(buffer)` | `BufferBody` | yes — reads through a fresh view every time | nothing (see below) |
| `Body.file(path, offset:, count:)` | `FileBody` | yes — a fresh handle per write | the handle it opened |
| `Body.stream(io, content_length:, close:)` | `StreamBody` | only when seekable, of known length, within the ceiling, and **not** owned | the stream, only with `close: true` |
| `Body.chunked(each_shaped)` | `ChunkedBody` | no, unconditionally | nothing |
| `Body.form(pairs)` | `FormBody` | yes | nothing |
| `Body.multipart(parts, boundary:, subtype:)` | `MultipartBody` | iff every part is | nothing of its own |

`Body.string` encodes **eagerly**, at construction, into the named charset (UTF-8 by default), so
`#content_length` is exact and a later mutation of the caller's `String` cannot reach the body. The
form body uses the `+`-for-space encoder that lives beside the RFC 3986 component encoder in
`Dexpace::PercentEncoding` and is never interchanged with it:

```ruby
form = Dexpace::Body.form([["q", "a b"], ["plus", "+"]])
form.media_type.render                              # => "application/x-www-form-urlencoded"
form.each.to_a                                      # => ["q=a+b&plus=%2B"]
Dexpace::PercentEncoding.encode_component("a b+")   # => "a%20b%2B"
```

`ChunkedBody` takes no `replayable:` keyword and never will: an `#each`-shaped object may or may
not re-yield identical bytes, `BODY-1` permits the property only when it is provable, and a keyword
would let a caller assert what the retry, redirect and challenge paths then believe. A caller with a
genuinely repeatable source uses `Body.bytes`, or pays one materialisation:

```ruby
chunked = Dexpace::Body.chunked(%w[hé llo])
chunked.replayable?         # => false
materialized = chunked.to_replayable
materialized.class          # => Dexpace::BufferBody
materialized.each.to_a      # => ["h\xC3\xA9llo"]
```

## Stream bodies, and what "mark/reset" means in Ruby

`BODY-9` makes a stream body of known length replayable when the stream "supports mark/reset".
Ruby has no mark/reset, and `respond_to?(:rewind)` is `true` for a pipe, a socket, a `StringIO` and
a `File` alike, so the probe is `pos` then `seek(pos)` at construction: a no-op on a seekable stream
at any position, and `Errno::ESPIPE` — a `SystemCallError`, not an `IOError` — on a pipe or socket.
The position it captures is the one replay returns to, **never byte 0**, so a body over a handle
already positioned mid-file cannot send bytes the caller never offered:

```ruby
io = StringIO.new(+"0123456789")
io.read(4)
stream = Dexpace::Body.stream(io, content_length: 6)
stream.rewindable?          # => true
stream.replayable?          # => true
stream.origin               # => 4
stream.each.to_a            # => ["456789"]
stream.each.to_a            # => ["456789"]   -- rewound to 4, not to 0

reader, writer = IO.pipe
writer.write("héllo")
writer.close
piped = Dexpace::Body.stream(reader, content_length: 6)
reader.respond_to?(:rewind) # => true         -- and it would raise
piped.rewindable?           # => false
piped.replayable?           # => false
piped.each.to_a             # => ["h\xC3\xA9llo"]
piped.each.to_a             # raises Dexpace::StreamError: ... single-use and its bytes have already been written (BODY-6)
```

Replayability needs all four: the probe said yes, the length is known (`-1` is single-use, `BODY-9`
says "of known length" literally), the length fits `Dexpace::IO::MAX_MATERIALIZED_BYTES`, and
**ownership was not transferred**. `close: true` makes the body close the stream as part of its one
write (`BODY-8`), and a body that closes its stream cannot rewind it for a second, so it is
single-use however seekable the stream — `#rewindable?` stays observable so you can tell the two
reasons apart:

```ruby
owned = Dexpace::Body.stream(StringIO.new(+"x"), content_length: 1, close: true)
[owned.rewindable?, owned.replayable?]   # => [true, false]
```

A stream body opened nothing, so by default it closes nothing. That is the body layer's ownership
rule (design §10.12): **a body closes exactly the sources it opened**, and transfer of close
ownership is opted into at the factory. It is deliberately not the I/O layer's rule, where wrapping
takes ownership (`IO-6`).

The consume-once latch is one `Thread::Mutex` held across a flag flip and nothing else: a second
write on a single-use body raises rather than emitting zero bytes, and under concurrent writes
exactly one passes and every loser sees the same error. A replayable stream body has a second flag
for `BODY-9`'s race-safe rewind — a write that overlaps another is refused, so two readers never
share one cursor. One residue is documented rather than closed: that guard is released in an
`ensure`, and an `Enumerator` abandoned mid-`#next` never runs one, so `stream_body.each.next`
followed by dropping the enumerator leaves the body refusing every later write. Nothing in Ruby
closes that, and refusing is strictly safer than two readers on one cursor.

## File bodies

`FileBody` validates six clauses at construction — the path exists, it is a regular file, the offset
is a non-negative `Integer`, the count is one or `nil` for the rest of the file, the offset is within
the size, and offset plus count is within the size captured then — each a `Dexpace::InvalidArgumentError`
naming the argument. Every write opens its own handle, transfers with `::IO.copy_stream(handle,
sink, count, offset)`, and closes the handle on every exit; a short transfer raises naming
transferred-of-total (`BODY-13`).

```ruby
fb = Dexpace::Body.file(path, offset: 3, count: 4)
[fb.count, fb.content_length]              # => [4, 4]
fb.each.to_a                               # => ["3456"]
fb.respond_to?(:to_path)                   # => false
Dexpace::Body.file(path, offset: 8, count: 5)
# raises Dexpace::InvalidArgumentError: offset 8 plus count 5 exceeds the 10-byte size captured at construction
```

`#to_path` is deliberately not defined. `::IO.copy_stream` checks `respond_to?(:to_path)` first,
and `copy_stream(body, socket)` with no length would then copy the **whole file**, silently ignoring
the window. `#path`, `#offset` and `#count` are public instead, which is what a transport dispatches
a kernel-level transfer on. And the one residue of design §7.1 that this layer originates: `BODY-11`
requires a fresh handle per write, so the handle cannot live on the object and `#close` cannot
release it; a consumer that drives `file_body.each.next` and abandons the enumerator leaks that
handle until the collector gets to it. A full drive to `StopIteration` and an `#each` with `break`
both run the `ensure`; only abandonment does not, and anything whose bytes come from a `FileBody`
— a multipart with a file part, a logging wrapper over one — inherits it.

## Multipart bodies

`MultipartBody` is `HTTP-51`'s composite: one framing routine writes the boundary, the part headers
and the part bodies, and `#content_length` runs the **same routine** against a counting sink, so
the declared length cannot drift from the bytes written. The counting run takes each part's own
declared length rather than writing the part, so asking for a header value never consumes a
single-use part or closes its stream; the length is computed lazily and memoised, which is why this
is the one body class that is not frozen. It is replayable iff every part is, and its length collapses
to `-1` if any part's is unknown (`BODY-2`).

```ruby
parts = [
  Dexpace::MultipartBody::Part.new(name: "note", body: Dexpace::Body.string("hi")),
  Dexpace::MultipartBody::Part.new(name: "file", filename: "a.txt",
                                   body: Dexpace::Body.bytes("AB", media_type: Dexpace::MediaType.parse("text/plain"))),
]
multipart = Dexpace::Body.multipart(parts, boundary: "XyZ")
multipart.media_type.render   # => "multipart/form-data; boundary=XyZ"
multipart.content_length      # => 169
multipart.each.to_a.join
# => "--XyZ\r\nContent-Disposition: form-data; name=\"note\"\r\n\r\nhi\r\n--XyZ\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nAB\r\n--XyZ--\r\n"
```

A generated boundary is 48 alphanumerics from `SecureRandom`; a caller-supplied one is validated
against RFC 2046's grammar (1–70 characters from `bcharsnospace`) and refused otherwise. `HTTP-51`'s
one MUST — a quote or a CR/LF in a parameter value must not break the framing — is two mechanisms:
a `"` or `\` in a name or filename is escaped inside the quoted-string, and a CR or LF is
**rejected**, because a quoted-string has no representation for it and an "escaped" CRLF is still a
CRLF on the wire. Every assembled part-header line is then swept by the outbound header grammar,
which admits HTAB and printable ASCII only — so a part name or filename carrying a byte at or above
`0x80` is refused, and a non-ASCII filename must be percent-encoded by the caller first (RFC 7578
§4.2).

```ruby
Dexpace::Body.multipart(parts, boundary: "has space")
# raises Dexpace::InvalidArgumentError: boundary "has space" violates RFC 2046's 1-70 bcharsnospace grammar (HTTP-51)
bad = Dexpace::Body.multipart([Dexpace::MultipartBody::Part.new(name: "a\r\nX: 1", body: Dexpace::Body.string("x"))])
bad.each.to_a
# raises Dexpace::InvalidArgumentError: a multipart parameter value must not contain CR or LF, got "a\r\nX: 1"
```

Two multipart bodies compare by value over the boundary, the subtype and the parts — the three facts
that fix what goes on the wire, `Content-Type` included. `HTTP-3` names the multipart body among the
builder-based models, so it carries `#new_builder` and a
`MultipartBody::Builder` whose pre-filled parts list is a copy, never the original's:

```ruby
derived = multipart.new_builder.tap { |b| b.subtype = "mixed" }.build
derived.media_type.render     # => "multipart/mixed; boundary=XyZ"
```

## The response side: `ResponseBody`, and the three methods on `Response`

A transport builds a `Dexpace::ResponseBody` over a `Dexpace::IO::BufferedSource.wrapping(io)`, so
closing the body closes the transport stream; the constructor checks for that reader's vocabulary
(`#read_into` and `#peek`) and refuses a bare `#read_into`-only source by name. `#source` is **the
same handle every call**, never a
fresh replay (`BODY-14`); `#close` is idempotent and makes no assumption the body was read
(`BODY-15`); `#preview(cap:)` reads through a fresh non-consuming view under `BODY-32`'s cap rules —
a negative cap is refused, a cap over the ceiling is silently clamped down, and whatever bytes exist
come back without requiring that exactly that many do. With a block, `ResponseBody.new` closes on
any exit path and returns the block's value.

`Dexpace::Response` gained three methods, all written against exactly two members of whatever the
body slot holds — `#source` and `#close` — which is why both are on the contract:

- **`#close`** forwards to the body and nothing else; idempotence lives in the body's latch, and a
  bodyless close is a no-op (`HTTP-43`).
- **`#body_string`** is the SDK's **one decode boundary** (`HTTP-42`), in three steps that are each
  load-bearing: resolve the charset from the media type (falling back to UTF-8 when none is declared
  or this Ruby does not know it), **retag** the BINARY bytes to that charset, then transcode with the
  target **named** — `encode(charset, invalid: :replace, undef: :replace)`. Skipping the retag
  mangles every non-ASCII byte, and a target-less `#encode` follows the host's
  `Encoding.default_internal`. The result is always `valid_encoding?`, and the body is closed in an
  `ensure` whether or not the read succeeded (`BODY-16`) — and so is the handle `#source` handed
  out, first: on a `BufferBody` or a fits-cap logging wrapper that handle is a fresh view of a buffer
  that outlives the call, and the reader is what deregisters it.
- **`#body_bytes`** decodes nothing, returns BINARY, and closes the same way.

```ruby
source = Dexpace::IO::BufferedSource.of_bytes("caf\xE9".b)
rb = Dexpace::ResponseBody.new(source: source,
                               media_type: Dexpace::MediaType.parse("text/plain; charset=iso-8859-1"))
rb.source.equal?(rb.source)   # => true
rb.preview(cap: 3)            # => "caf"
res = response_over(rb)       # a Dexpace::Response built through its builder
text = res.body_string        # => "caf\xE9"
text.encoding                 # => #<Encoding:ISO-8859-1>
rb.closed?                    # => true
res.close                     # => nil
```

Three bodies can occupy `Response#body`, and each answers `#source` in its own regime: a
`ResponseBody` with the same handle every time; a `ResponseLoggingBody` with the regime its drain
landed in; and a `BufferBody` — the bounded error copy — with a **fresh view per call**, because
`BODY-30` says "decode it, then snapshot it", and with a no-op `#close`, because `#body_string`'s
`ensure`-close must leave the copy readable. A request-body variant that ends up in the slot fails
by name with a `Dexpace::StreamError`, not a `NoMethodError`.

## The two logging wrappers

Nothing in core constructs either; phase 5's instrumentation layer will, which is how `BODY-34`'s
"only when body-level logging is enabled" holds today. Their cap defaults are deliberately
asymmetric: the request side defaults to unbounded, which `BODY-19` states in its own text for direct
wrapper use, and the response side **requires** its cap, because `BODY-22` names none and an
unbounded one would buffer a multi-gigabyte response in the wrapper whose job is to bound it.

**`RequestLoggingBody.new(delegate, tap_limit:)`** builds a **fresh** `Dexpace::IO::TeeSink` per
write, so the tap reflects only the most recent attempt (`BODY-18` by construction), the full payload
reaches the primary whatever the cap, and the tee mirrors before it forwards so a primary-side
failure still leaves the failing chunk in `#snapshot`. It exposes the delegate's replayability
verbatim and its `#to_replayable` wraps the delegate's replayable form with the cap preserved. It
exposes no buffer handle (`BODY-37`), and never calls `#close`, `#flush` or `#emit` on the tee,
because those forward to a primary the body does not own.

```ruby
logged = Dexpace::RequestLoggingBody.new(Dexpace::Body.string("héllo wörld"), tap_limit: 4)
sink = Dexpace::IO::Buffer.new
logged.write_to(sink)   # => 13
sink.snapshot           # => "h\xC3\xA9llo w\xC3\xB6rld"   -- the whole payload
logged.snapshot         # => "h\xC3\xA9l"                   -- the first four bytes
logged.replayable?      # => true
```

**`ResponseLoggingBody.new(delegate, preview_bytes:)`** drains the delegate at most once, lazily,
on the first `#source`, `#snapshot` or `#error`, with concurrent first accesses serialised so the
upstream is read exactly once — the mutex is held across a state flip and never across the drain,
so two fibers of one thread interleave it. Two regimes follow, told apart by reading one byte past
the cap:

- **Fits the cap** (`BODY-23`): everything is captured, the delegate is closed best-effort — a
  close failure after a full capture is not a drain error and does not stop the body being served
  (`BODY-28`) — and every `#source` is a fresh non-consuming view, fully repeatable. The captured
  buffer survives the wrapper's own close, so post-mortem `#snapshot` still works.
- **Exceeds the cap** (`BODY-24`): only the prefix is captured, the delegate stays open, and
  `#source` is a **single-use** composite that replays the prefix, then the probe byte, then the live
  tail; a second `#source` raises. The tail forwards each read to the delegate's `#read_into` — one
  fill — so a still-open connection is delivered as bytes arrive, never held for a count. Closing
  that tail and closing the wrapper reach **one** close-once guard, so the delegate is closed at most
  once whichever the consumer does and in either order.

```ruby
delegate = Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes("0123456789"),
                                     content_length: 10)
wrapper = Dexpace::ResponseLoggingBody.new(delegate, preview_bytes: 4)
wrapper.snapshot          # => "0123"    -- exactly the cap; the probe byte is not captured
wrapper.closed?           # => false     -- over-cap: the delegate stays open
wrapper.content_length    # => 10        -- the delegate's declared length, not the capture's
tail = wrapper.source
tail.read                 # => "0123456789"
wrapper.source            # raises Dexpace::StreamError: the over-cap tail ... is single-consumer ... (BODY-24)
tail.close
delegate.closed?          # => true

fits = Dexpace::ResponseLoggingBody.new(
  Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes("héllo")), preview_bytes: 64,
)
fits.snapshot                              # => "h\xC3\xA9llo"
fits.closed?                               # => true   -- fits-cap: closed as part of the capture
[fits.source.read, fits.source.read]       # => ["h\xC3\xA9llo", "h\xC3\xA9llo"]
fits.close
fits.snapshot                              # => "h\xC3\xA9llo"   -- the buffer holds only memory
```

A mid-drain failure keeps the bytes read before it and caches the error: `#source` re-raises the
same object every call, `#snapshot` returns the partial bytes without raising, and `#error` returns
the cached error (or `nil`) without a second drain (`BODY-26`). A delegate read returning zero bytes
for a positive count is a stream-contract violation, never end of stream (`BODY-25`).

## The bounded error copy

`Dexpace::Body.buffer_bounded(body, cap: Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES)` drains at
most `cap` bytes of a body — through its `#source`, so it works on all three bodies that can occupy
`Response#body` — into a buffer, closes the original in an `ensure` so a failure to allocate still
releases the connection, and returns a `BufferBody` readable independently and repeatably. The loop
stops asking rather than reading and discarding, and the truncation is markerless. The 1 MiB cap is
fixed by `BODY-30`/`HTTP-52` and takes no configuration. The operation is deliberately
**status-blind**: turning an error response into an exception, and asking `Status#error?` first, is
phase 4's recovery step.

```ruby
big = Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes("x" * 3_000_000))
copy = Dexpace::Body.buffer_bounded(big)
copy.class                                   # => Dexpace::BufferBody
copy.content_length                          # => 1048576
big.closed?                                  # => true
[copy.source.read.bytesize, copy.source.read.bytesize]   # => [1048576, 1048576]
```

## The lazy typed response

`Dexpace::TypedResponse.new(response:, handler:)` exposes `#status`, `#headers`, `#protocol`,
`#reason`, `#request` and `#response` without touching the body or taking any lock, and `#value`
runs the handler at most once on first access and memoises the outcome — a `nil` or `false`
success, or a raised failure re-raised as the same object with its cause and backtrace intact
(`HTTP-44`). Concurrent first accesses are serialised with a mutex held across a state flip only,
never across the parse (`HTTP-45`); a handler that raises outside `StandardError` still settles the
state and is re-raised unchanged, so no later caller hangs. The handler is any object responding to
`#call(response)` — the RBS interface `Dexpace::_ResponseHandler` — and it takes the whole response
because the thing that reads the body, chooses a codec and parses must be status-aware; phase 7
supplies that handler into this class rather than replacing it.

```ruby
typed = Dexpace::TypedResponse.new(response: res, handler: ->(r) { r.status.code })
typed.status                    # => #<data Dexpace::Status code=200>
typed.value                     # => 200
calls = 0
lazy = Dexpace::TypedResponse.new(response: res, handler: ->(_r) { calls += 1; nil })
[lazy.value, lazy.value, calls] # => [nil, nil, 1]
```

One residue, recorded rather than papered over: `Thread::Mutex` and `Thread::ConditionVariable`
defer to an *installed* fiber scheduler, and none is installed by default, so a second fiber of the
same thread arriving mid-parse parks the carrier thread in `#wait` until the parsing fiber is resumed.
Two threads are unaffected, and so is a second fiber arriving after the parse has settled; the
response-logging drain has the identical shape.

## Errors, and what is deliberately not one

The body layer defines **no new error class**. A caller mistake in an argument is
`Dexpace::InvalidArgumentError`; a stream-contract violation — a second write on a single-use body,
a short transfer, a short write, a zero-length read for a positive count, a second read of the
over-cap tail, a request body asked for its `#source` — is `Dexpace::StreamError`; use of a real
stream after its close is `Dexpace::ClosedError`. One argument mistake still leaves core as a stdlib
exception and is on phase 1's plan to re-wrap: `Body.string("caf\xE9".b)` raises
`Encoding::UndefinedConversionError` out of `String#encode`, because the bytes cannot be read as
UTF-8 to encode them.

## Threads, fibers and clocks

No body is thread-safe as a general contract (`IO-37`). The only synchronised state in the layer is
four flag flips — the consume-once latch, the replay guard, the drain latch and the parse latch —
plus `Closeable`'s, each under a mutex held across the flip and nothing else. No method takes a
timeout, a deadline or a cancellation token (`IO-40`): the only blocking calls are the delegate's
own reads and the sink's own writes. `Ractor` is never load-bearing, and the collector is never a
cleanup hook — which is why the two `Enumerator` residues above are stated instead of closed.
