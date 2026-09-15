# The byte-streaming layer

**As built by phase 3a, in `dexpace-core`, written against source on 2026-09-15.** This page says
what the streaming objects are and how they behave: one FIFO buffer, a buffered source and sink
with typed reads and non-consuming views, and a tee sink that mirrors a bounded tap. What each is
*required* to do is `docs/product-spec/05-i-o-contracts.md`; how the design maps it to Ruby is
`docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.1; the per-requirement proof is
`docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-checklist.md`. Signatures live in
`gems/dexpace-core/sig/dexpace/io/`, and this page does not restate them. Every example below was
run against the built code. There is no registry, no factory and no installation call here: the
provider seam the reference build had was retired (design §10.1), and the behavioural contract is
the whole deliverable.

## Read this first: `Dexpace::IO` shadows `::IO`

`Dexpace::IO` is the namespace for this layer, and inside `module Dexpace` a bare `IO` is that
module and not Ruby's. That is loud for a method call — `IO.pipe` raises `NoMethodError` — and
**silent for a type test**: `x.is_a?(IO)` is `false` for a real `::IO`, `IO === x` is `false`, and
a `case x when IO` falls through, with no error and no warning. Core never writes `is_a?(IO)`
(every stream it accepts is checked with `respond_to?`) and a RuboCop cop refuses the bare name
inside every gem's `lib/`.

**The same is true inside your own class if it includes `Dexpace`.** `include` puts `Dexpace`
ahead of `Object` in the class's ancestry, so a bare `IO` there resolves to `Dexpace::IO` too:

```ruby
class Uploader
  include Dexpace                 # for the short names -- and this is the cost

  def stream?(x) = x.is_a?(IO)    # silently false for a real ::IO
end
```

Write `::IO` in any class that includes `Dexpace`, or do not include it. A top-level
`include Dexpace` is unaffected, because `Object`'s own constants are searched first; `extend
Dexpace` and a class with no include are unaffected. The same holds for every flat `Dexpace::`
constant that shares a name with a core class — `Dexpace::Method` is the other one — and no gate
this repository owns can reach your file.

## Two read primitives, and why they are two

`IO-1`'s primitive is **`#read_into(dest, count:)`**: it appends up to `count` bytes to the tail
of a BINARY `dest` and returns how many — at least 1 when bytes remain, exactly 0 for a zero count
(never `-1`, even at end of stream), and `-1` when the source is exhausted before any byte. It is
deliberately not called `#read`, because `#read`, `#readpartial`, `#getbyte`, `#readbyte` and
`#each` carry **Ruby's** semantics and are what makes a `BufferedSource` a drop-in for `::IO`:
`IO.copy_stream` — which is what `Net::HTTP#body_stream=` uses — hands `#readpartial` one buffer
it reuses on every call and expects overwritten, so a tail-appending `#read` would corrupt every
streamed upload. Both are asserted against the same buffer in one test.

```ruby
source = Dexpace::IO::BufferedSource.of_bytes("héllo wörld")
buf = +"seed".b

source.read_into(buf, count: 3)   # => 3;    buf is "seedh\xC3\xA9" -- appended
source.read(4, buf)               # => "llo "; buf is "llo "       -- overwritten
source.readpartial(100)           # => "wörld".b
source.readpartial(1)             # raises Dexpace::EndOfStreamError, an ::EOFError
source.read(1)                    # => nil
source.read_into(+"".b, count: 1) # => -1
source.read_into(+"".b, count: 0) # => 0
```

`Dexpace::EndOfStreamError < ::EOFError` is load-bearing: `IO.copy_stream` terminates cleanly on
an `EOFError` subclass from a duck-typed `#readpartial` and propagates anything else. `#read` and
`#readpartial` hand `outbuf` back tagged `Encoding::BINARY` whatever tag it arrived with (`::IO`
and `StringIO` disagree with each other on this, and `StringIO` changed at Ruby 3.4).

## The typed reads

Every source responds to the whole vocabulary — `Dexpace::IO::TypedReads` supplies it over one
private hook, `#fill(min_bytes)`, which is also the whole of what a third-party source has to
implement (include the module and `Dexpace::Closeable`, define `#fill` and `#release`). Every
`String` that comes back is BINARY except the two explicit decodes.

```ruby
source = Dexpace::IO::BufferedSource.of_bytes("one\r\ntwo\ncafé".b)
source.read_line_utf8   # => "one"  -- "\n" and "\r\n" terminate and are consumed; a lone "\r" is content
source.read_line_utf8   # => "two"
source.read_utf8        # => "café", tagged UTF-8; #read_string(Encoding::ISO_8859_1) retags likewise
source.eof?             # => true
```

`#read_exactly(count)` returns exactly `count` bytes or raises `Dexpace::EndOfStreamError`
consuming nothing; `#skip(count)` advances exactly that far or raises the same way, and `#skip(0)`
is always a no-op. `#read_utf8(count:)` and `#read_string(encoding, count:)` take a **byte**
count. The decodes only retag: an invalid sequence comes back as-is with `#valid_encoding?`
false, because the one place a replacement policy applies is `Response#body_string`, which phase 3b
owns. Every count and offset is a keyword; the four `::IO`-compatible bridge methods keep Ruby's
positional signatures because call-compatibility with `::IO` is their entire purpose.

## Sources: three factories, one ownership rule

| Factory | Wraps | Owns it? |
|---|---|---|
| `BufferedSource.wrapping(io)` | anything responding to `#readpartial` or `#read` — a `StringIO`, an `IO.pipe` end, a `Tempfile`, your own object | **yes**: closing the source closes `io` |
| `BufferedSource.of_bytes(string)` | an independent copy of the `String` | no external resource |
| `BufferedSource.over(body)` | anything responding to `#each` yielding `String` chunks — a Rack body, an `Array`, an `Enumerator` | **no**: closing the source never closes the body |

`.wrapping` takes ownership because `IO-6` requires it and there is deliberately no borrowing
variant; `.new` is private so ownership cannot be set through an argument. With a block it
closes on any exit path and returns the block's value:

```ruby
io = StringIO.new("abc")
Dexpace::IO::BufferedSource.wrapping(io) { |source| source.read_exactly(2) }  # => "ab"
io.closed?                                                                      # => true
```

`.over` pulls on demand — no read-ahead accumulates — and preserves the body's own chunk boundaries
through `#each`, so a chunk of `""` means "no bytes this time" and never end of stream. What it
does not do is close the body: its callers are always downstream of something that already owns
the response, and if the body holds a resource, whoever created it closes it. A source closed
before exhaustion abandons the body's enumerator with its `ensure` unrun; that is Ruby's
`Enumerator` and nothing here papers over it. `#owns_upstream?` reads the ownership fact back;
`#view?` says whether a source is a view.

Chunks arriving from a body are stored as they are when frozen and already BINARY (the ordinary
Rack shape, no copy) and as `chunk.b` otherwise — never `force_encoding`, which raises on a frozen
`String`. Every source is itself a canonical body representation: it responds to `#each` yielding
BINARY chunks, so it can be handed to anything that consumes one.

## Views: `#peek` and `#slice`

A view is a `BufferedSource` over another source that reads without advancing its parent's
cursor. `#peek` covers the whole remaining source; `#slice(offset:, count:)` covers at most `count`
bytes starting `offset` ahead of the cursor. Both drive the parent's fill as needed, so a view can
read bytes the parent has not pulled from its upstream yet.

```ruby
source = Dexpace::IO::BufferedSource.of_bytes("abcdef")
source.peek.read                     # => "abcdef"
source.read_exactly(2)               # => "ab" -- the peek consumed nothing
slice = source.slice(offset: 1, count: 2)
slice.read                           # => "de"
source.read                          # => "cdef"
slice.read                           # raises Dexpace::ClosedError: the window is "behind" the cursor
```

The rules, all of them `IO-19`–`IO-24`'s except the last, which the specification leaves open and
this port fixes:

- Views are independent of each other; a slice of a slice composes offsets additively and is
  capped at the outer window's remaining bytes.
- An offset past the end constructs fine and reads as empty; a negative offset or count is refused
  at construction.
- Closing a view closes neither its parent nor the parent's cursor. Closing the parent invalidates
  every view derived from it, transitively, so every later read on one raises
  `Dexpace::ClosedError` — a state error, never an EOF.
- **The parent holds nothing back for a view.** Its retention floor is its own cursor: a view
  reading ahead of the parent retains what it reads ahead, and a view whose next byte the parent
  has already consumed fails loudly rather than serving bytes from somewhere else. Bytes a view
  has already read are behind it and the parent may pass them freely.

## The buffer

`Dexpace::IO::Buffer` is a FIFO that is simultaneously a source and a sink: bytes written through
`#write` read back in order through every typed read, and `#bytesize` is what is held now.

```ruby
buffer = Dexpace::IO::Buffer.new
buffer.write("ab", "cd")             # => 4
buffer.snapshot                      # => "abcd" -- a fresh, unfrozen, independent copy
buffer.read_exactly(1)               # => "a"
other = Dexpace::IO::Buffer.new
buffer.copy_to(other, offset: 1)     # copies "cd" from the cursor + 1 through the end; consumes nothing
buffer.close
buffer.write("x"); buffer.snapshot   # => "bcdx" -- an in-memory close frees nothing
```

The close asymmetry is `IO-42`'s and is deliberate in both directions: a `Buffer` stays readable
and writable on its own surface after `#close`, so a logging snapshot taken after the wrapper
closed still works, while its close still invalidates every view derived from it. A stream-backed
source or sink refuses every read, write, `#emit` and `#flush` after close with
`Dexpace::ClosedError`.

`#snapshot`, `#read` with no count, `#read_utf8`, `#read_string`, `#read_exactly` and a bounded
view's read all refuse to build one `String` over `Dexpace::IO::MAX_MATERIALIZED_BYTES` (64 MiB,
a constant nothing takes as a keyword until phase 5 wires configuration) with a
`Dexpace::StreamError` naming the streaming alternatives, before allocating anything.
`#read(length)`, `#readpartial(maxlen)` and `#read_line_utf8` are outside the guard: the first two
take a length the calling code chose, and a line has no length until its terminator arrives, so
its bound belongs to the caller (phase 7's SSE machine carries its own).

## Sinks and the tee

`Dexpace::IO::TypedWrites` is the write vocabulary, over one private hook, `#deliver(string)`,
which always receives a frozen BINARY `String`: `#write(*strings)` (the `::IO`-compatible bridge,
returning the byte count), `#write_from(buffer, count:)` (exactly `count` bytes off the head of a
`Buffer`, or a `Dexpace::StreamError` and nothing consumed), `#write_all(source)` (pumps anything
responding to `#read_into` to exhaustion and returns the total; a read of 0 for a positive count
is a source-contract violation, never tolerated as EOF), `#write_utf8(string, range: nil)` (a
character range), `#write_string(string, encoding:)`, and `#emit`/`#flush`. `#emit` pushes one
level and never calls the underlying `#flush`; `#flush` does both.

`BufferedSink.wrapping(io)` owns `io` exactly as the source factory does and pushes every write
straight through, so a failed underlying write leaves nothing staged to prepend to the next; an
underlying `#write` that reports fewer bytes than it was handed is a contract violation.
`TeeSink.new(primary:, tap_limit: nil)` mirrors every write into a tap **before** forwarding the
full payload to the primary, stops mirroring at `tap_limit` bytes while still forwarding
everything, and forwards `#emit`, `#flush` and `#close` to the primary only, leaving the tap
readable through `#tap_snapshot` afterwards:

```ruby
out = StringIO.new(+"".b)
sink = Dexpace::IO::BufferedSink.wrapping(out)
tee = Dexpace::IO::TeeSink.new(primary: sink, tap_limit: 4)
tee.write_all(Dexpace::IO::BufferedSource.of_bytes("héllo"))
tee.close
out.string        # => "héllo".b  -- the wire body, untruncated; out is closed
tee.tap_snapshot  # => "h\xC3\xA9l".b -- the first four bytes
tee.buffer        # raises Dexpace::StreamError naming IO-28 and the typed write methods
```

A tee has no `#clear_tap`: it binds its primary at construction, so one tee cannot span two
attempts, and the request-logging wrapper phase 3b builds makes a fresh tee per write. A primary's
own failure propagates once, as the identical object; the tee's staging buffer is cleared in an
`ensure`, so nothing is swallowed or duplicated.

## Errors, and what is deliberately not one

| Class | Ancestry | When |
|---|---|---|
| `Dexpace::InvalidArgumentError` | `::ArgumentError` | a negative or non-`Integer` count, a bad window, a frozen or non-BINARY `#read_into` destination, an unknown charset — before any I/O |
| `Dexpace::EndOfStreamError` | `::EOFError` | `#read_exactly`, `#readbyte`, `#readpartial`, `#skip` at end of stream |
| `Dexpace::StreamError` | `::IOError` | a short `#write_from`, a zero read for a positive count, a short underlying write, a materialisation over the ceiling, `TeeSink#buffer` |
| `Dexpace::ClosedError` | `::StandardError` | any use of a stream-backed source, sink or tee after close, and any read of an invalidated or closed view |

`Dexpace::StreamError` is in Ruby's `IOError` family because the requirements say "an I/O error",
and it is a sibling of the transport error phase 8 adds, never a subclass: a stream-contract
violation must not claim to be retryable. `Dexpace::IOError` and `Dexpace::EOFError` are never
defined, for the same reason `Dexpace::ArgumentError` is not — they would shadow Ruby's inside
`module Dexpace`. `StreamError.short_transfer(transferred:, expected:)` and
`.zero_read(requested:)` are the one place the two message forms come from, so the body layer's
copies cannot diverge.

## Threads, fibers and clocks

Every streaming instance is a single-threaded contract: callers serialise access, and independent
views may be used from different threads. The one cross-thread guarantee is close: the close latch
is written and read under a `Thread::Mutex`, acquired once per public call and never held across a
fill, a read or a drain, so a close on one thread reliably invalidates a view being read on another
— and no lock is ever held across a suspension point, so two fibers of one thread may interleave
reads on one source. Nothing here owns a clock: no method takes a timeout, a deadline or a
cancellation token, and the only blocking call is the wrapped stream's own read, which the
transport that owns the socket bounds.
