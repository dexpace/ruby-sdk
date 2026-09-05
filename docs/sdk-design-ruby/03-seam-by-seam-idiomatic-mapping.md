## 3. Seam-by-Seam Idiomatic Mapping

### 3.1 The byte-stream provider seam → retired; its contract implemented in core

**What the reference requires and why.** **SEAM-3** demands a pluggable factory producing an empty buffer, buffered
readers over a raw stream and a byte array, buffered writers, and wrappers adding a buffered surface to a primitive
source or sink, with ownership transferring on wrap; **SEAM-4** requires the factory be concurrency-safe while the
returned instances need not be. The pluggability exists for one reason: the reference platform's adequate stream
library is third-party and **SEAM-1** bars core from depending on one.

**The porter's question.** Does Ruby ship, with the interpreter, a byte abstraction good enough to build a wire
protocol on — exact-count reads, charset decode, line reads honouring every terminator (**IO-14**), non-consuming
peek and slice views, a tee mirroring writes into a bounded tap — and is the full behavioural contract still
implementable over it?

**The Ruby answer.** Yes, so the *seam* retires while the *contract* stays. `IO`, `StringIO`, `IO.pipe` and `String`
(with `Encoding::BINARY`) are shipped and versioned with the interpreter; choosing them is choosing the platform,
not taking a dependency (P2). Core implements **IO-1**–**IO-42** in full, exactly once, with no factory, no
installation call and no discovery — which makes **SEAM-5**–**SEAM-10**, their mirrors **IO-30**–**IO-36** and
**IO-39**, and **XCUT-23** as applied to this seam moot. That is the largest simplification this port makes, and it is a
mechanical consequence of the byte-stream contract no longer needing to be kept out of a zero-dependency core.

Core ships one `Dexpace::IO::Buffer` (a FIFO of BINARY `String` chunks with a head offset, so draining is O(1)
amortised, satisfying **IO-7**–**IO-10**), one `BufferedSource`/`BufferedSink` pair providing the typed reads of
**IO-11**–**IO-16**, non-consuming views (**IO-19**–**IO-24**) implemented as cursors over core's own buffer rather
than re-reads of the underlying `IO` — repeatable views are a buffering concern, exactly as the reference frames
it, and a socket cannot be re-read regardless — and one `TeeSink` (**IO-25**–**IO-29**) that mirrors attempted
bytes into a bounded tap *before* forwarding, clears its staging buffer even on a failed primary write, and
forwards `flush`/`close`/`emit` to the primary only. The tee is hand-built rather than assembled from `IO.pipe` or
`IO.copy_stream`: duplicating a *readable* for two consumers is a different problem from mirroring a *sink's*
writes into a bounded tap while forwarding the payload untruncated. Four notes on the Ruby specifics:

- **IO-14**'s line semantics are hand-implemented, not delegated to `IO#gets`. `#gets` is governed by the global
  `$/`, and its universal-newline handling depends on how the underlying `IO` was opened — no basis for a
  requirement that fixes `\n` and `\r\n` as terminators, keeps a lone `\r` as content, and returns a final
  unterminated line as-is.
- The buffer is deliberately **not** built on the interpreter's own `IO::Buffer` (3.1+): that is a fixed-capacity
  native memory region built for zero-copy reactor backends, the right tool for a future high-throughput transport
  adapter and the wrong one for a growable FIFO.
- **IO-9**/**BODY-32**'s "host maximum single-array allocation" has no Ruby analogue — a `String` is bounded only by
  memory — so the port substitutes an explicit `MAX_MATERIALIZED_BYTES` constant (default 64 MiB, configurable) and
  fails loudly with a pointer at the streaming alternative rather than driving the process into the OOM killer. The
  64 MiB figure is chosen, not derived: it is an order of magnitude above any payload a client SDK should be
  materialising into one `String` and an order of magnitude below the heap a typical single-process Ruby web worker
  is given, so it separates "a caller who should have streamed" from "a caller doing something legitimate" without
  the constant itself needing to be right. Because the right value is deployment-specific, it is configurable
  through the same layered chain as every other limit (§8.2) rather than a frozen constant.
- **IO-38**'s cross-thread-visible close flag is written and read through a `Thread::Mutex` rather than relying on
  the GVL, so the guarantee survives JRuby and TruffleRuby. **IO-40**'s "no own timeout" is honoured: deadlines
  belong to the transport that owns the socket. **IO-16**'s native-stream bridge is satisfied by construction, since
  a `BufferedSource` already responds to `#read`, `#readpartial` and `#each`. **IO-28**/**BODY-37**'s "no direct
  backing-buffer handle" cannot be language-enforced (`instance_variable_get` reaches anything); core exposes no
  reader and raises from any method that would hand one out, and the honest position — a documented contract, not a
  guarantee — is the same hole recorded once in §4.

**The canonical body representation.** A body is any object responding to `#each`, yielding `String` chunks tagged
`Encoding::BINARY`. This is Rack's de facto streaming-body protocol, the closest thing Ruby has to a standard for
the concern (P14): a Rack body, an `Enumerator`, an array of chunks and core's own `BufferedSource` all satisfy it
with no glue. Core also adapts `#read`-shaped `IO`-likes at the edge because `Net::HTTP#body_stream=` wants one;
that is an interop convenience, not part of the portable contract. The alternative — `IO`-likes only — is a simpler
contract but loses the ability to hand an `Enumerator`-backed lazy generator (pagination, SSE, streaming multipart)
to a transport without a shim, which is the common case here.

**The inverse adapter, and why there is exactly one.** Every consumer inside core that needs *typed reads* over a
body — SSE's line machine (§7.2), `Serde#load`'s source argument (§3.4), the error-body buffering of §5.1 —
needs the opposite direction: a `#each`-shaped body presented as a `BufferedSource`. Core supplies one entry point,
`Dexpace::IO::BufferedSource.over(body)`, which pulls chunks from the wrapped object's `#each` on demand and buffers
them into §3.1's FIFO, so pull semantics are preserved and no read-ahead accumulates. It is the single adapter
because three subsystems independently reaching for `IO.pipe` or an `Enumerator` shim is how the line-terminator
rules of **IO-14** and the BOM rule of **SSE-12** drift apart. It is the one place the §3.1 ownership rule is
stated as an exception to the paragraph below: **`.over` does not take ownership of the wrapped body** — closing the
returned source drains and discards its own buffer and never calls `#close` on the body — because its callers are
always downstream of something that already owns the response.

**Encoding, stated once.** Bytes read from or written to a socket are always `Encoding::BINARY` (verified the same
object as `ASCII_8BIT`); `String#b` is the idiom for "these bytes, untagged"; `force_encoding` is a *retag* used
only where the bytes are known to conform; and there is exactly one decode boundary, `Response#body_string`, which
applies the media type's charset via `String#encode(invalid: :replace, undef: :replace)` and falls back to UTF-8
when absent or unknown (**HTTP-42**). The port never trusts a transport's tagging — `Net::HTTP` returns bodies
tagged `ASCII-8BIT` regardless of the declared charset — and always retags to BINARY on ingress.

**Two ownership rules, deliberately different.** At the I/O layer, wrapping takes ownership: closing a
`BufferedSource` built over a caller's `IO` closes that `IO` (**SEAM-3**). At the body layer the rule is inverted
and uniform: **a body closes exactly the sources it opened itself** — a file-backed body opens and closes a fresh
handle per write (**BODY-11**), a body over a caller-supplied `IO` or `Enumerator` never closes it, and transfer is
opted into explicitly at the factory. Conflating the two is the trap **BODY-8** names ("A port MUST decide its
stream-ownership/close rule deliberately rather than assume every single-use body closes its input"); this resolves
the reference's own admitted per-variant inconsistency in one direction, and is recorded in §10.

**Body variants and the two logging wrappers.** The body contract is one duck type, but the BODY family draws five
distinctions inside it and adds two wrappers on top, each carrying an obligation the duck type alone does not
express. Naming them here keeps them from being rediscovered per call site.

- **Composite bodies.** A multipart or otherwise aggregate body reports `#replayable?` as the conjunction over its
  parts and collapses its declared length to unknown if any part's is unknown (**BODY-2**), so an aggregate can
  never claim a replayability its weakest part lacks. The form-urlencoded body is separate and always replayable,
  and uses §3.5's form encoder — `+` for space, never the RFC 3986 component encoder (**HTTP-38**, **BODY-35**).
- **File-backed bodies.** Replayable by opening a fresh `File` handle per write, which is what makes a concurrent
  or repeated send safe at the body level; validation is fail-fast at construction — the path exists and is a
  regular file, offset non-negative, count non-negative or the rest-of-file sentinel, and offset plus count within
  the size captured at construction (**BODY-11**). A short write raises naming transferred-of-total rather than
  completing silently, as do the exact-length copies of **BODY-10**/**HTTP-39**, which share one helper so the
  message form cannot diverge (**BODY-13**); a zero-length read for a positive request is a stream-contract
  violation, never an end-of-stream, and never a spin.
- **Materialize-once.** `#to_replayable` returns `self` when the body already is, and otherwise drains the body's
  write output exactly once into an in-memory buffer and returns a buffer-backed body, leaving the original
  consumed (**BODY-3**, **HTTP-37**). The single-use guard is race-safe: a second write raises rather than emitting
  zero bytes (**BODY-6**), and under concurrent writes at most one passes (**BODY-7**). The Ruby mechanism, and the
  reason it is stated in the design rather than left to the implementer, is §11.7's rule: **the `Thread::Mutex` is
  held only across the consumed-flag flip and never across the drain**, because Ruby's `Mutex` is per-fiber-owned
  and non-reentrant (both verified), so a lock held across the suspension point inside a drain deadlocks two fibers
  of one thread. The reference's atomic compare-and-set is a mechanism; race-safety is the requirement.
- **The replay gate.** Retry, redirect and the 401 challenge all consult the same `#replayable?` before re-sending
  a body-bearing request and decline differently — retry stops and surfaces the last outcome, auth returns the
  challenge response unchanged and unclosed, redirect raises (**BODY-4**) — which the port preserves rather than
  unifies, because **BODY-4** explicitly says a port need not unify the decline behaviour. A body-*less* request's
  retry eligibility is gated on method idempotency instead (**BODY-5**), and that gate is retry-only.
- **Response bodies are single-use handles.** The read handle is obtained once and returns the *same* underlying
  handle on every request, never a fresh replay (**BODY-14**); repeatable access requires the explicit buffering
  wrapper below. Close releases the transport resource, is idempotent, and does not assume the body was consumed
  (**BODY-15**, and see §3.7).

Two wrappers sit above the variants, and between them they are what the `TeeSink` above exists to serve.

- **The request-logging wrapper** mirrors the exact bytes of the wrapped body's single write into a bounded tap
  while forwarding the same bytes onward, consuming upstream exactly once (**BODY-17**). The tap is cleared at the
  start of every write so a snapshot reflects only the most recent attempt and a retry against a replayable
  delegate does not accumulate earlier attempts (**BODY-18**); it stops copying once the cap is reached while the
  full payload continues to the transport, so a multi-gigabyte upload mirrors only a preview (**BODY-19**). Mirroring
  happens *before* forwarding, which is why a primary-side failure still leaves the failing chunk captured
  (**BODY-20**) — the ordering `TeeSink` was built for. The wrapper exposes the delegate's replayability verbatim
  and its `#to_replayable` returns a wrapper around the delegate's replayable form with the cap preserved
  (**BODY-21**).
- **The response-logging wrapper** drains the delegate at most once, lazily, on first access — a read, a snapshot,
  or the cached-error query — buffering up to the cap, with concurrent first accesses serialised so the upstream is
  read exactly once (**BODY-22**). The Ruby latch is the same flag-flip-under-mutex shape as **BODY-7**'s, chosen
  for the same non-pinning reason the requirement's own JVM aside gives. Two regimes follow: within the cap the
  wrapper captures everything, closes the delegate, and serves every later read as a fresh non-consuming view —
  fully repeatable (**BODY-23**); over the cap it buffers only the prefix, leaves the delegate open, and serves the
  next read as a single-use stream that replays the prefix then continues from the live tail, with a second read
  failing (**BODY-24**). A zero-byte read for a positive count is an error, never an end-of-stream (**BODY-25**). A
  mid-drain failure retains the bytes already read and caches the error, so reads re-raise it, a snapshot returns
  the partial bytes without raising, and the error query never triggers a drain (**BODY-26**). Every close path —
  the wrapper's own and the tail stream's — routes through one close-once guard, and a delegate whose close raises
  is still marked closed (**BODY-27**); on the fits-cap path a close failure after a successful capture is
  best-effort and never reported as a drain error, and the captured buffer outlives the wrapper's close because it
  holds only memory (**BODY-28**). Reported content length is the captured size only when the capture was complete
  (**BODY-29**).

Both wrappers engage only when body-level logging is enabled and share one preview-size setting (**BODY-34**), and
neither is on the path when it is not. Error-to-exception mapping is a separate concern that applies only to error
statuses: a 304, or a 3xx no redirect step followed, is returned with its body intact rather than consumed
(**BODY-31**); the bounded error-body copy that mapping needs is specified once in §5.1.

### 3.2 The synchronous transport seam → kept, as a duck-typed single method

**SEAM-11** specifies a single-operation contract that "MUST NOT pre-buffer the body (caller owns read/close)" and
**SEAM-12** requires transports be safe for concurrent calls with all per-request state confined to locals or the
returned response graph. Both are pure intent — no JVM mechanism to translate — and both hold in Ruby unchanged.

The seam is a duck type, not a nominal module: **a transport is any object responding to
`#call(request, options, cancellation)` and returning a `Dexpace::Response`.** `#call` is the convergence point of
Ruby's own middleware ecosystems (Rack, Faraday adapters) and choosing it means a bare `lambda` is a valid
transport, a `Dexpace::Pipeline` can stand in wherever a transport is expected (**PIPE-26**), and no adapter has to
declare conformance it structurally already has (P14). Core ships a `Dexpace::Transport` module with a
`.conforms?` predicate and no implementation, satisfying **SEAM-2**'s "core never names a concrete implementation."

Streaming is preserved end to end: `dexpace-transport-net_http` issues the request inside
`Net::HTTP#request(req) { |res| ... }` and exposes the response body as a `BufferedSource` over the block-scoped
`Net::HTTPResponse#read_body` stream, so **SEAM-11**'s no-pre-buffering clause and **TRANSPORT-25**'s "lazily-read
stream, not pre-buffered ... closing the SDK response cascades to close the native body and release the connection"
are satisfied literally. The reference transport disables nothing for **TRANSPORT-1**/**TRANSPORT-2** because
`Net::HTTP` follows no redirects and retries nothing on its own — those two requirements are vacuous for this
adapter and load-bearing for a future Faraday-stack or `httpx` adapter, which is exactly the per-transport scoping
the specification's own §17 preamble anticipates ("Where a behavior exists in only one reference transport ... the
requirement is scoped accordingly").

Per-call options (**SEAM-11**, **TRANSPORT-5**, **ASYNC-19**) are threaded as an immutable
`Dexpace::RequestOptions` value and applied to a *per-call* `Net::HTTP` instance's `open_timeout`, `read_timeout`
and `write_timeout`, never to a shared client object — which satisfies **TRANSPORT-5**'s "applies to that single
call only, leaves the shared native client untouched" structurally rather than by discipline. **TRANSPORT-6**'s
clamp-don't-truncate rule applies: `Net::HTTP`'s timeouts are floating-point seconds, so a sub-millisecond positive
timeout is representable and no truncation-to-zero is possible, but the clamp is implemented anyway for adapters
over coarser APIs. An options-ignoring transport behaves identically with and without options, as **SEAM-11**
requires, because options are inert data. **SEAM-14**'s close contract on this seam is specified in §3.7 with the
rest of the port's lifecycle rules; `dexpace-transport-net_http` builds a `Net::HTTP` per call and therefore takes
the no-op close **SEAM-14** permits, unless the caller supplied a client, in which case closing it is forbidden.

### 3.3 The asynchronous transport seam and the canonical pivot

**What the reference requires and why.** **SEAM-16** requires the async transport's future to complete "with a
non-null response (caller owns close) or exceptionally, never a null success," and that cancelling an
already-succeeded future not close the delivered response. **SEAM-17** (a **SHOULD**) wants the async contract
expressed through one canonical dependency-free future pivot, with per-ecosystem facades as separate adapters
bridging to and from it, because that platform's async ecosystem is fragmented. **SEAM-30** and **ASYNC-5** require
the producer to close an orphaned response when the future is already settled; **ASYNC-1**/**ASYNC-2** restate
single-value completion and the failure channel; **ASYNC-6** requires bidirectional cancellation; **ASYNC-20**
requires that cancelling a future whose response was already delivered not close it.

**The porter's question.** Does Ruby have a dominant async primitive every framework already speaks — in which case
the pivot is that primitive and the bridges are unnecessary — or is it fragmented enough that **SEAM-17**'s
pivot-plus-adapters shape is the only one preserving **SEAM-1**? And what, precisely, is the pivot?

**The Ruby answer: a core-owned minimal future, with `Fiber.scheduler`-transparency as the named runner-up.**
Ruby's async ecosystem is fragmented across `Async::Task` (reactor-native, structured concurrency, cancellation
tree), `Concurrent::Promises::Future` (thread-pool-backed, composable, no structured cancellation), plain `Thread`
plus `Thread::Queue`, and EventMachine descendants — none in the standard library, all with different cancellation
semantics. Adopting any one as the pivot would put a third-party gem in core's public surface, which **SEAM-1** and
**NFR-1** forbid. Core therefore defines its own:

```
Dexpace::Async::Future
  #settled?   #cancelled?
  #value(deadline: nil)           # blocks the calling thread-or-fiber; raises the failure
  #wait(deadline: nil)            # settles-or-times-out; returns self; never raises the failure
  #on_settle { |outcome| ... }    # invoked exactly once, on the settling thread-or-fiber
  #cancel(reason)                 # cooperative; see the contract below
Dexpace::Async::Completer         # the write side: #fulfil(response), #fail(error), #on_cancel { ... }
```

The write side is a separate object handed only to the producer, so a consumer cannot settle someone else's future
— the Ruby answer to a language with no way to hide a completion method. `#value` blocks on a `Thread::Queue` pop
rather than a spin or a `Kernel#sleep` poll, which is what makes the pivot scheduler-transparent: Ruby's
synchronisation primitives are fiber-aware (verified: `Thread::Mutex` ownership is per-fiber, not per-thread —
locking a held mutex from a second fiber of the same thread raises `ThreadError` rather than succeeding), and under
a registered `Fiber.scheduler` a blocking queue pop routes through the scheduler's `block`/`unblock` hooks instead
of parking the OS thread. A caller inside `Async { }` therefore awaits the pivot without blocking the reactor, and
a caller with no scheduler blocks one thread — which is what they asked for.

**Clause-by-clause (P5).** `#value` and `#on_settle` deliver exactly one of a response or a failure and there is no
"settled with nothing" state to reach, satisfying **SEAM-16**'s "MUST NOT complete successfully with a null/absent
value" and **ASYNC-1** verbatim. **ASYNC-2** is satisfied because the adapter's entry point returns the future
before doing anything fallible and routes any synchronous raise to `Completer#fail` — the same normalisation
**PIPE-30** requires. **ASYNC-20** falls out of the ownership rule: `#cancel` after settlement is a no-op on the
value, and the caller owns closing a delivered response.

**The cooperative-cancellation contract, and its one rule.** `#cancel` cannot pre-empt a producer, because Ruby's
only pre-emption mechanisms are `Thread#raise` and `Thread#kill`, which this port forbids (§8.3). The contract every
adapter MUST honour is one rule, stated once and cited everywhere else: **check-after-resume — after returning from
any operation that may have suspended (an I/O wait, a scheduler yield, a queue pop, a task await), and before
acting on the value it produced, the producer MUST re-check its cancellation state; if cancelled, it MUST close any
response it holds and settle through the failure channel rather than delivering.** That rule implements
**SEAM-30** and **ASYNC-5** ("whoever loses the produce/terminate race performs the close") on a host with no
external pre-emption: it changes *how* the orphaned-response close happens, not *whether* (P6).
`Completer#on_cancel` gives the producer a hook to abort promptly — closing the socket, stopping a task — rather
than only at the next resume.

Two MVP gems settle the pivot from the two directions that matter. `dexpace-async-thread` drives it from a bounded
`Thread::SizedQueue` pool, giving the seam a zero-third-party implementation; `dexpace-transport-async_http` drives
it from an `Async::Task` under a reactor, which is what exercises the properties — multiplexing, structured
cancellation, scheduler-native suspension — that the pivot exists to expose and a thread pool cannot demonstrate
(§2.1). Later, `dexpace-async-async` maps `Async::Task#stop`/`#with_timeout` onto the pivot's cancellation in both
directions for callers whose own code is already reactor-based (**ASYNC-6**), and `dexpace-async-concurrent_ruby`
maps `Concurrent::Promises::Future`. **ASYNC-7**'s per-adapter documentation of whether cancellation aborts or lets
a blocking call finish is a required README section: the thread adapter lets an in-flight blocking read finish, the
reactor-backed ones abort at the next scheduler checkpoint. Every one of them owns a pool or a task group and
therefore carries the full **ASYNC-15**/**SEAM-25** close contract rather than **ASYNC-17**'s no-op default; §3.7
states it once.

**One consequence of check-after-resume that is easy to miss.** A producer that discovers cancellation *after* its
attempt has already produced a response is holding a closeable resource nobody will ever take delivery of. Closing
it is not optional tidiness: **CFG-21** requires that "when an interruptible-task future has already been cancelled
and the task nonetheless produced a result value that is a closeable resource, that result MUST be closed on the
discard path (best-effort, swallowing close failures) rather than leaked." The check-after-resume rule's close is
that discard path, it routes through §3.7's best-effort helper, and the helper is null-safe as the requirement's
last clause demands. The same helper serves **RETRY-32**'s late-arriving attempt response and **PAGE-27**'s drop
path, so there is one place where an unobserved close failure goes.

**Why not the two rejected alternatives.** *(b) "async is the sync contract run under a `Fiber.scheduler`"* is the
runner-up and is genuinely attractive — pure-Ruby I/O is already scheduler-transparent, so `Net::HTTP` under
`Async { }` is concurrent with no code change. It loses on two counts. It produces no *value*: there is no handle
to cancel, compose, attach a callback to, or hand to a paginator, so **ASYNC-1**, **ASYNC-6**, **ASYNC-20**,
**PAGE-25**–**PAGE-33** and **RETRY-30**–**RETRY-33** have nothing to attach to and **SEAM-16** becomes
unimplementable rather than satisfied differently. And it presumes every consumer runs under a scheduler, which
most will not for years, while foreclosing exactly the capabilities that justify an async seam — multiplexing and a
structured cancellation tree, which a blocking call cannot express however it is scheduled. Scheduler-transparency
is retained as a *property* of the synchronous seam (§3.2), which is where it belongs. *(c) block/callback-based*
inverts error handling, gives no single place to represent "exactly one success or one failure," and makes
**PAGE-31**'s and **RETRY-30**'s trampolines harder; callbacks are the mechanism *inside* `#on_settle`, not the
contract.

**Cancellation and deadlines, end to end.** Core defines `Dexpace::Cancellation`, a token carrying a typed
`#reason`, composable (`Cancellation.any(caller_token, deadline_token)`) and derivable per call, threaded through
the sync seam as an ordinary argument and through the async seam as the future's own state — one vehicle used by
the transport call, the inter-attempt wait and per-call timeouts alike. Because the reason is a typed object,
**XCUT-2**'s "timeout and cancellation told apart by ambient cancellation state, not by matching a message string,
even when the runtime represents both with the same exception type" is satisfied by inspecting `reason.class`,
which matters in Ruby where `Net::ReadTimeout` is distinguishable but `Errno::*` and `IOError` are not reliably.
**TRANSPORT-5**'s per-call scoping falls out free, since a derived token is inherently scoped to one call.
Deadlines propagate as explicit values: on the sync path into `open_timeout`/`read_timeout`/`write_timeout`, which
fail at a well-defined syscall boundary with a typed exception; on the async path into the task's own timeout or
`#value(deadline:)`, which interrupt only at scheduler checkpoints. §8.3 states the prohibition on
`Timeout.timeout` and `Thread#raise`, and why.

### 3.4 The wire-codec (serde) seam → kept separate, even though embedding is free

**SEAM-19** requires the codec seam to bundle a serializer, a deserializer and the media type its serializer
produces, and that the media type "is never defaulted at the seam level"; **SEAM-2** forbids core naming any
concrete implementation; **SERDE-1**/**SERDE-2** restate both. The seam is a duck type: an object responding to
`#media_type`, `#dump(value, sink)` and `#load(source, witness)`, plus the three further encode entry points the
next paragraph derives.

**All four allocation profiles ship, and one Ruby pair very nearly collapses.** **SEAM-20** requires the
serializer to "offer the common allocation profiles (produce a fresh string, produce a fresh byte array, stream
into a caller-owned output, encode into a caller-owned scratch buffer at an offset), and streaming/buffer variants
MUST NOT close the caller's target."
The seam therefore carries four methods, not one: `#dump_string(value)`, `#dump_bytes(value)`, `#dump_to(value,
sink)` and `#dump_into(value, buffer, offset:)`, with `#dump` above as the shorthand for `#dump_to`. Ruby collapses
exactly one pair and no more, and the collapse is real rather than convenient: **a Ruby `String` tagged
`Encoding::BINARY` *is* the byte array** — there is no separate `byte[]` type to produce, and `#dump_bytes` differs
from `#dump_string` only in the encoding tag the result carries, which is the whole of the distinction the
requirement draws. Both ship because the tag is load-bearing at the §3.1 encoding boundary and a caller that wants
BINARY should not have to remember `#b`. The two caller-owned variants are genuinely distinct and both ship:
`#dump_to` writes into any `#write`-shaped sink, and `#dump_into` writes into a caller-supplied
`String`/`IO::Buffer` at an offset, raising an `IndexError` on overflow as **SEAM-20**'s last clause requires.
**Neither closes the caller's target** — the port's general rule (§3.1: a wrapper closes only what it opened)
applied here, and asserted per adapter in `dexpace-conformance` rather than left to adapter discipline. The decode
side is the mirror: `#load(source, witness)` **reads to EOF and does not close the caller's source** (**SEAM-21**),
which is also why §3.1's `BufferedSource.over` takes no ownership. Encode and decode failures surface as the
stable, SDK-owned `Dexpace::Serde::SerializationError`/`DeserializationError` pair (**SEAM-23**) chaining the
codec's own error rather than leaking the backing library's exception type, while a genuine stream I/O error
propagates unwrapped — **SEAM-20**'s and **SEAM-21**'s failure clauses, implemented once in §7.3.

`json` is a default gem, so embedding the reference codec in core would cost nothing in dependency terms. The port
ships it separately anyway, as `dexpace-serde-json` — because **SEAM-2** is about coupling and **SEAM-19** is about
not defaulting policy, and zero dependency cost is not zero coupling cost (P3). Two Ruby-specific arguments make
the discipline pay for itself here rather than merely preserving symmetry. First, **a zero-`add_dependency` core
cannot pin a minimum `json` version**, and it needs to: `json` is versioned independently of the interpreter (Ruby
3.4.10 ships 2.9.1, verified) and the 2026 advisories against the C generator and its format-string handling make
`>= 2.19.9` the floor a codec should declare. Putting the codec in a gem that *can* declare
`add_dependency "json", ">= 2.19.9"` is the only way to state that floor at all. Second, it keeps the door open for
`dexpace-serde-oj` without a second code path in core.

Two naming hazards, flagged once. The seam's `#dump`/`#load` are the *seam's* method names (matching `Marshal` and
`Psych` convention); the JSON adapter implements them via `JSON.generate` and `JSON.parse`, **never** `JSON.dump`
or `JSON.load` — `JSON.load` accepts a proc, has historically enabled `create_additions` (the arbitrary-object
instantiation hazard behind CVE-2020-10663, defaulted off only from json 2.7.0), and has no place in a security-
sensitive decode path. This is enforced by a lint rule, not by convention. And `#load` on the seam always takes an
explicit witness (§7.3); there is no witness-less overload to fall into.

Two adapter defaults are fixed here rather than left to the JSON gem's own. The adapter's default encoder
configuration renders date and time values as ISO-8601 strings, never epoch numbers, and the corresponding witness
parses that form back to the same instant, so the round-trip **SERDE-24** requires holds by construction rather
than by the caller matching two independent conventions. And `Dexpace::Serde::JSON.default` is a *factory*: every
call returns a fresh, independently configured adapter instance rather than a shared one, so an application that
reconfigures the codec it was handed cannot change the codec another part of the process is using (**SERDE-25**).
Both are cheap here — `JSON` itself is stateless and the configuration is a frozen options hash (§7.3) — which is
precisely why there is no reason to skip them. **SERDE-23**'s tolerant decode of unknown fields is the witness's
default: a witness reads the keys it declares and ignores the rest, so backward-compatible server additions do not
break a deployed client, and strictness is opt-in per witness.

### 3.5 The operation-input projection seam

**SEAM-26** requires a per-operation declaration of method, path template with named placeholders, and typed
path/query/header/body projections, with the body carried rather than encoded; **SEAM-27** fixes path-parameter
percent-encoding as single segments (so a value cannot inject `/`), mandatory placeholder values, RFC 3986 query
rendering, and the base-URL composition rules (trailing-slash normalisation, empty-path no-op, base query preserved
with the operation query appended, base with a fragment or a malformed URL rejected with a context-bearing error).

The Ruby shape is a frozen `Dexpace::Operation` descriptor — method, template `String`, and a projection table
mapping input keys to `[:path | :query | :header | :body, name]` — plus one `Dexpace::Operation#build_request`
helper in core. No code generation is implied; the port specifies only the runtime primitive a generator would
target, matching the parent project's deferral of a codegen layer.

**The obvious-but-wrong tool, verified three ways (P13).** None of Ruby's three built-in escapers implements RFC 3986
*component* encoding, and each fails differently. Verified on 3.4.10 against the input `a b*~+/!()'`:

| Escaper | Output | Why it fails |
|---|---|---|
| `URI.encode_www_form_component` | `a+b*%7E%2B%2F%21%28%29%27` | space → `+` (not `%20`); `~` → `%7E` though **HTTP-32** requires `~` untouched; `*` left bare though **HTTP-29** requires `%2A` |
| `CGI.escape` | `a+b%2A~%2B%2F%21%28%29%27` | space → `+`; it is form encoding by design |
| `URI::RFC3986_PARSER.escape` | `a%20b*~+/!()'` | space and `~` correct, but it escapes only characters outside a broad *URI* set — `/`, `+`, `*` and the sub-delims survive, so a path parameter could inject a `/` and a query value could smuggle a `+` |

Core therefore hand-writes one strict component encoder whose unreserved set is exactly `A-Za-z0-9-._~` and which
percent-encodes everything else, used for path segments (**SEAM-27**), query rendering (**HTTP-29**) and single-
component encoding (**HTTP-32**), and one separate form encoder for `application/x-www-form-urlencoded` bodies
(**HTTP-38**/**BODY-35**), which is `+`-for-space and never claimed RFC 3986 compliance. The two are different
functions with different names and different tests; they are never interchanged.

**`URI::DEFAULT_PARSER` is a version-dependent alias, and the port never references it.** Which parser it names
changed at exactly Ruby 3.4.0: on 3.4 it is `URI::RFC3986_Parser` (verified on 3.4.10), while on 3.2 and 3.3 — both
inside this port's supported range — it is `URI::RFC2396_Parser`, whose escaping and parsing rules differ. Code
written against `DEFAULT_PARSER` therefore silently changes behaviour across the CI matrix without changing a line,
which is the worst shape a portability bug can take: it passes on the developer's interpreter and fails on the
floor. **The rule is to pin `URI::RFC3986_PARSER` explicitly for every parse and every resolution and never to rely
on `DEFAULT_PARSER`**, enforced by the same lint rule that forbids `Time.parse` (§6.1). `URI::RFC3986_PARSER` has
been present since Ruby 3.0, so the pin costs nothing on the floor.

Base-URL composition uses `URI.join`/`URI#merge` for RFC 3986 reference resolution (verified:
`URI.join("https://h/base/", "../y?q=1#f")` yields `https://h/y?q=1#f`) and never re-parses a re-rendered string,
because round-tripping through `to_s` is where percent-encoding gets normalised away. Verified that `URI` preserves
already-encoded octets verbatim (`URI("https://h/a%2Fb?x=%26").to_s` round-trips unchanged), which is what
**REDIR-13** needs.

### 3.6 Discovery and the zero-dependency boundary, restated

After §3.1 retires the byte-stream provider, three seams still need a resolution story: transport (sync and async),
serde, and the async executor. **SEAM-5** fixes the precedence — explicit install always wins; else auto-discover;
zero discoverable candidates yields a descriptive install-hint error; more than one yields an error listing all
candidates; exactly one is selected silently — and **XCUT-23** restates it as a cross-cutting invariant. **SEAM-6**
makes explicit install idempotent for the same instance and a hard failure for a different one; **SEAM-7** caches a
successful auto-resolution process-wide while leaving an unresolved state re-evaluable; **SEAM-8** makes replacing
an already-handed-out auto-resolved provider a warning; **SEAM-9** requires reads to see the latest install without
blocking and writes to be serialised.

Ruby has no classpath to scan. The port keeps all five branches and changes only the *substrate*: **an adapter
registers itself as a side effect of being `require`d.** `Dexpace::Transport.register(:net_http, klass)` is called
from `lib/dexpace/transport/net_http.rb`, so "discoverable" means "the application has required this adapter,
directly or through a Bundler group." Core ships an empty registry and never auto-requires an optional gem, which
is what keeps **SEAM-1** true; the zero-candidate error names no concrete gem, saying only that a transport must be
required or installed explicitly, so **SEAM-2** holds in the error path too. With that substitution every branch is
satisfied verbatim: zero registered → loud failure with an install hint; exactly one → silent selection; two or
more registered with no explicit selection → loud failure listing the registered keys. The registry is a `Hash`
behind a `Thread::Mutex` for writes with an unsynchronised read of a single frozen reference for lookups
(**SEAM-9**), and resolution results are memoised until an install invalidates them (**SEAM-7**).

**What the registry holds, and which identity the prior-state table compares.** The two are deliberately different
objects and conflating them is how a port ends up comparing the wrong thing. **The registry maps a key to a
*factory*** — the adapter class, or any `#call`-shaped builder — because `require`-time registration happens before
the application has configured anything and a factory is the only thing an adapter can supply at that point.
**Resolution produces an *instance*, and the resolved slot holds exactly one**, built from the winning factory the
first time it is asked for and memoised thereafter. `Dexpace::Transport.install(t)` takes an instance, not a key.
The prior-state matrix **SEAM-6**/**SEAM-8** describe therefore compares **`equal?` on the object occupying the
resolved slot** — never `==`, for §5.1's reason, and never the factory, because two calls of the same factory
produce two non-`equal?` instances that the requirement means to treat as different providers. Written as the
explicit table it is implemented as, rather than as prose, because the two rules are easy to conflate:

| Prior state of the resolved slot | `install(t)` behaviour | Requirement |
|---|---|---|
| empty | install succeeds silently | **SEAM-5** |
| holds `t` (`equal?`) | no-op | **SEAM-6** |
| holds a different object, explicitly installed | raise, naming incumbent and rejected | **SEAM-6** |
| holds a different object, auto-resolved but never handed out | replace silently | **SEAM-8** |
| holds a different object, auto-resolved and already handed out | replace and warn | **SEAM-8** |

Registration itself carries the same rule one level down: re-registering the `equal?` factory under the same key is
a no-op, and a different factory under an occupied key raises naming both, so a double-`require` is quiet and two
gems claiming one key are not.

**SEAM-10**'s de-duplication of one logical provider seen through multiple loaders is vacuous in Ruby, for the
reason given in §2.4 — there is no classloader, `require` de-duplicates by resolved path, and constants are
process-global — and is recorded as such in §10 rather than implemented as a no-op with a comment.

**Presence-gated auto-activation** (activating an adapter because a library happens to be loaded) is allowed for
**instrumentation only**. The asymmetry is deliberate and worth arguing: for a transport or a codec, "whatever
happens to be installed silently wins" is an auditability failure — a `Gemfile` change could silently reroute every
request through a different HTTP library with different TLS defaults and different timeout semantics, which is
precisely the outcome **SEAM-5**'s loud-failure branches exist to prevent. For instrumentation the worst outcome of
guessing wrong is a span that is or is not emitted; nothing about the request changes. So
`dexpace-instrumentation-otel` may install itself when `OpenTelemetry` is already defined, and no other adapter may.

### 3.7 Lifecycle and ownership

Six requirements — **SEAM-14**, **SEAM-25**, **HTTP-43**, **ASYNC-15**–**ASYNC-17**, **XCUT-13** and **XCUT-22** —
say the same three things about closing, in six different vocabularies. Ruby has no `Closeable`
interface and no `try-with-resources`, so the rule has to be written down once rather than inferred from a type,
and this is where it is written.

**The duck type.** Anything the SDK can release responds to `#close`, and core ships one `Dexpace::Closeable`
module supplying the whole contract to any class that includes it and defines a private `#release`. There is no
nominal interface to conform to; a caller's own object closes correctly if it responds to `#close`, which is what
lets a `Net::HTTP`, an `IO`, a `Tempfile` and a `Dexpace::Response` all pass through the same helper.

**Idempotence is a latch, not a flag check.** **XCUT-13** requires close to be "idempotent (latched so repeat calls
are no-ops)", **SEAM-14** requires it of both transport seams, **SEAM-25** of any async adapter owning a pool, and
**HTTP-43** of `Response` — "Response MUST be closeable and its close MUST be idempotent and forward to the body" —
which in turn delegates to the body's idempotent close (**HTTP-41**, **BODY-15**). All four use the same mechanism:
a `@closed` boolean flipped under a `Thread::Mutex`, with the mutex held *only across the flip* and released before
`#release` runs — the identical shape §7.2 uses for the SSE facade and §3.1's body wrappers use for their
close-once guards, and for the identical reason (Ruby's `Mutex` is per-fiber-owned and non-reentrant, so holding it
across a release that may suspend deadlocks two fibers of one thread). Whoever flips the latch runs the release;
everyone else returns immediately. A release that raises still leaves the latch flipped, so no second release is
attempted (**BODY-27**), and the failure propagates once.

**Ownership: the SDK closes exactly what the SDK created.** **XCUT-22** states it plainly — "A caller-supplied
(bring-your-own) transport client, executor, or connection pool MUST NOT be closed/shut down by the SDK; the caller
owns its lifecycle and may keep using it after the SDK component is closed" — and **SEAM-14**, **SEAM-25** and
**ASYNC-15** each restate it for their seam. In Ruby this is a constructor-level distinction, not a runtime check:
every component that can take a resource takes it through two differently named entry points, one that *builds* the
resource and one that *borrows* it, and records which it did in a frozen `@owned` boolean set at construction.
Concretely: a `Net::HTTP` the transport built per call is closed by the transport; a `Net::HTTP` the caller passed
in is not. An executor `dexpace-async-thread` created is shut down on close; a caller-supplied one is not, even
when the adapter is the only thing using it. An `IO` a file-backed body opened is closed after each write; an `IO`
the caller handed to a body factory is not (§3.1). Making ownership a construction-time fact rather than a
close-time judgement is what keeps this from being re-decided, differently, at each of those three sites.

**Close never blocks on an interrupt-sensitive wait.** **XCUT-13**'s second clause — close "MUST NOT block on
interrupt-sensitive waits — it uses non-blocking shutdown semantics and preserves the ambient interrupt/cancel flag
as-is" — is the one clause that interacts with §8.3's prohibition, and the interaction is favourable rather than
awkward. A port that had interrupt-based cancellation would need to be careful that a blocking shutdown step does
not swallow or reset an ambient interrupt; this port has no interrupt to preserve, so "preserves the ambient
cancel flag as-is" is satisfied by the flag never being touched. What remains is the non-blocking part, and it is a
real constraint: `dexpace-async-thread`'s close signals its queue and returns, it does not join workers under a
`Kernel#sleep` or an unbounded `Thread#join`. **ASYNC-16**'s graceful shutdown — stop accepting work, let in-flight
tasks finish — is a **SHOULD** and is what the adapter does by default, with the wait itself performed through
§8.3's cancellable queue wait and a bounded deadline, so a caller who closes inside a cancelled scope is not
parked. **SEAM-15** is a **MAY** and the port takes it explicitly: **a send after close raises
`Dexpace::ClosedError`**, documented rather than left undefined, because "undefined" in Ruby means whatever
`NoMethodError` the internals happen to produce.

**Unobserved failures on cleanup paths.** Cleanup runs in `ensure` blocks and on discard paths where there is often
no caller left to raise to, and a close failure must never replace the failure that caused the cleanup. One helper,
`Dexpace.close_quietly(resource)`, is the single sanctioned exit: it is null-safe (**CFG-21**'s last clause), it
rescues `StandardError` from `#close`, and it disposes of that error in exactly one of two ways and never a third
— **attached to the primary exception's suppressed trail (§5.2) when there is a primary exception in flight, and
emitted as an `http.instrumentation.*` diagnostic through §8.1's facade when there is not.** It never raises over a
primary exception, and it never silently swallows: a swallowed close failure is a leaked connection nobody can
diagnose. The two exceptions to *quiet* closing are both required to be loud and are both stated where they live:
an **explicit** `#close` by the caller propagates its failure (**SSE-30**, §7.2), and a `#release` raising during
the latched close above propagates once (**BODY-27**, §3.1). Everything else — the orphaned-response close of
**SEAM-30**/**ASYNC-5**, the discard close of **CFG-21**, the adaptation-failure close of **TRANSPORT-22** ("if
adapting a live native response ... throws, the transport MUST close the native response before the throwable
propagates ... both the sync and async response paths"), the superseded-response closes of **PIPE-40** and
**REDIR-22**, the pre-wait release of **RETRY-35**, the drop paths of **PAGE-12** and **PAGE-27** — goes through
`close_quietly`.

---

