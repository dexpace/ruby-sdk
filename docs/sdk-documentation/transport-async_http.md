# The asynchronous transport: `dexpace-transport-async_http`

**As built by phase 8c, written against source on 2026-09-21.** This page says what the reference
asynchronous transport gives an SDK author today: `Dexpace::Transport::AsyncHTTP`, a module with two
constructions over `async-http`, the reactor every call needs and the failed future a call outside
one gets, a client map keyed by reactor and origin, the header policy the wire carries on HTTP/1.1
and HTTP/2 alike, one exchange task per call under one budget, a cancellation bridge that works from
any thread, a response body that streams on the fiber that reads it, and the failure classification
that keeps phase 6a's retry layer honest. What each is *required* to do is
`docs/product-spec/17-transport-adapter-conformance-contract.md` (`TRANSPORT-1`–`TRANSPORT-30`, of
which this adapter owns seven — `TRANSPORT-7`, `-8`, `-9`, `-12`, `-13`, `-21`, `-23` — and re-proves
8a's as the suite's second driver) with `ASYNC-6`, `ASYNC-21` and `ASYNC-22` from
`docs/product-spec/18-asynchronous-runtime-adapter-contract.md`; how the design maps it to Ruby is
`docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.3 read with entries 10 and 15 of
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`; the per-requirement
proof is `docs/work/mvp/phase8/phase8c/2026-09-11-phase8c-asynchronous-transport-checklist.md`.
Signatures live in `gems/dexpace-transport-async_http/sig/`, and this page does not restate them.
Every example below was run, in the order printed and as one script, against the built code on
4.0.6 and 3.3.12 (async-http 0.105.0, async 2.46.0 on both) and printed the same on both, except
for the ephemeral port a `Host` line names, which is the run's own. The examples use
`dexpace-conformance`'s `WireServer` and `Scripts` as the server — a real `TCPServer` on `127.0.0.1`
answering a scripted reply and recording what it was sent — because a transport page's examples
should touch a socket and nothing outside the machine. Eight names are the page's shorthand and
nothing else is assumed: `AsyncHTTP` is `Dexpace::Transport::AsyncHTTP`; `WireServer` and
`Scripts` are `Dexpace::Conformance::WireServer` and `Dexpace::Conformance::Scripts`, after
`require "dexpace/conformance"`; `req(url, method: "GET", headers: Dexpace::Headers::EMPTY,
body: nil)` is `Dexpace::Request.build` over those four; `headers(pairs)` is
`Dexpace::Headers.builder` with each pair added; `EMPTY` is `Dexpace::RequestOptions::EMPTY`;
`sink` is a recording sink — any object answering the facade's `#debug`/`#info`/`#warn`/`#error`
and their four predicates and keeping every `(severity, payload)` it is handed; and `drops` is the
pairs that sink recorded whose payload's `"event"` is `Events::TRANSPORT_HEADER_DROPPED`, in order.
`adapter` is the owning adapter the first block builds and the last block closes, and every block
that talks to a socket starts its own `server` and reads its port for `url`.

**The gem's whole dependency budget is `dexpace-core` and `async-http ~> 0.104`** (`NFR-2`), whose
closure brings `async`, `async-pool`, `protocol-http`, `protocol-http1`, `protocol-http2`, `io-event`
(a native extension) and `openssl`; the gem declares **Ruby >= 3.3**, narrower than the SDK's 3.2
floor, because that closure does (`P8-36`), so a consumer on 3.2 composes `dexpace-core` with
`dexpace-transport-net_http` and loses only this gem. Requiring the gem registers it with phase 2's
registry under `:async_http`, so a consumer that requires it and nothing else resolves an adapter
without naming one (`SEAM-5`).

```ruby
require "dexpace/transport/async_http"

adapter = AsyncHTTP.build
adapter.owned?                                               # => true
Dexpace::AsyncTransport.conforms?(adapter)                   # => true
Dexpace::AsyncTransport.registered_keys                      # => [:async_http]
Dexpace::AsyncTransport.resolve.class                        # => Dexpace::Transport::AsyncHTTP::Adapter
AsyncHTTP.default.equal?(AsyncHTTP.default)                  # => false  (a fresh adapter every call)
AsyncHTTP::FRAMING_HEADERS
# => ["host", "content-length", "transfer-encoding", "connection", "keep-alive", "proxy-connection",
#     "te", "trailer", "upgrade", "expect"]
AsyncHTTP::ALPN_PROTOCOLS                                    # => ["h2", "http/1.1"]
[AsyncHTTP::DEFAULT_TIMEOUT_SECONDS, AsyncHTTP::DEFAULT_CONNECTION_LIMIT, AsyncHTTP::MAX_ORIGINS]
# => [60.0, 8, 32]
AsyncHTTP::DropPolicy::MODES                                 # => [:every, :once_per_name, :quiet]
AsyncHTTP::REGISTRY_KEY                                      # => :async_http
```

## A reactor, and what a call needs from it

**Every call needs a running `Async` reactor on the calling thread**, and the adapter creates none
(`P8-39`): a `Sync { }` inside the adapter would block the caller's thread and defeat the seam, and a
reactor thread the adapter owned would be a thread pool by another name — `dexpace-async-thread`'s
job, and a long-lived fiber carrying the constructor's diagnostic context rather than the caller's
(`ASYNC-10`'s exact failure). `Adapter#call` outside a reactor does not raise. It returns an
**already-failed** future carrying `Dexpace::SeamError` whose message names the fix, which is what
`TRANSPORT-21` asks for in as many words: delivered through the returned future, never thrown
synchronously.

```ruby
future = adapter.call(req("http://127.0.0.1:1/"), EMPTY, nil)   # no Sync, no Async
future.settled?                                              # => true
future.value
# raises Dexpace::SeamError: Dexpace::Transport::AsyncHTTP requires a running Async reactor on the
#   calling thread; wrap the call in `Sync { }` or `Async { }`
Async::Task.current?                                         # => nil
```

Three consequences of the reactor being the caller's, and not the adapter's:

- **A response does not outlive the reactor that produced it.** `Sync { }` returns only when the
  reactor has no non-transient work left, and on its way out it stops the connection pool's own
  housekeeping task, whose release drains the pool — a wait on every busy connection, and the
  connection behind an unread body is busy until that body is read or closed. So read or close the
  response **inside** the block that made the call; a `Sync` that hands a streaming response out to
  code after it never returns. `Response#body_string`, `#body_bytes` and `#close` all release the
  connection. The 8c conformance driver met exactly this in `TRANSPORT-29`'s eight-thread assertion
  and materialises the body inside its per-thread reactor before handing the response out.
- **`Dexpace::AsyncTransport.sync_over(adapter)` still needs a reactor.** The bridge awaits the future
  this adapter returns, and the exchange behind it cannot run without a reactor, so a caller with no
  reactor gets the same `SeamError` through the bridge as through `#call`.
- **`Dexpace::Transport.async_over(adapter, executor:)` accepts this adapter silently** and yields a
  future of a future; the return-type check that would refuse it is phase 2's open finding in
  `dexpace-core`, not this gem's to fix. Use the adapter as the `Dexpace::AsyncTransport` it is.

## Two constructions, and a client map keyed by reactor and origin

`AsyncHTTP.build(timeout: nil, logger: Instrumentation::Logger::NULL, drop_policy: nil,
connection_limit: nil, ssl_context: nil, configuration: nil)` is the SDK-managed construction: the
adapter **owns** a map of `Async::HTTP::Client`s, one per **(reactor, origin)**, built on first use
and released by `#close`. The reactor is part of the key because an `async-http` client belongs to
the reactor whose tasks drive it and cannot be shared across reactors on different threads; keying
by `Fiber.scheduler` identity is what makes `ASYNC-22`'s "safe for concurrent calls from multiple
threads" true structurally — every thread running its own reactor gets its own client per origin,
and every fiber inside one reactor shares one multiplexed client. The map is bounded at
`MAX_ORIGINS` (32) and drained back to it after every insert, evicting clients whose reactor has
closed first and the oldest after that, with every evicted client's pool retired and closed rather
than dropped (`XCUT-14`). Each client is built with `retries: 0` — `async-http` would otherwise
re-send an idempotent request on a dropped connection, which is `TRANSPORT-2`'s prohibition and
`TRANSPORT-17`'s single-use body written twice — and with `limit:` from `connection_limit:`, the
configuration key `TRANSPORT_CONNECTION_LIMIT`, or `DEFAULT_CONNECTION_LIMIT` (8), the per-origin
connection bound on HTTP/1.1 (HTTP/2 multiplexes on one).

`AsyncHTTP.using(client, logger:, drop_policy:)` is the **borrowing** construction over a caller's
own `Async::HTTP::Client`, used verbatim: the adapter never sets a knob on it, refuses one whose
`retries` is not already zero rather than setting it (`TRANSPORT-2`, `XCUT-22`), and its `#close`
releases nothing of the caller's, so the client stays usable afterwards (`TRANSPORT-15`). A borrowed
client is bound to one endpoint, so every request through it names that origin; and it is bound to
the reactor it was built inside. `Adapter.new` is private behind the two factories. `#close` on
either construction is reactor-free — it retires every pooled connection and closes each pool
without waiting for a busy one (`P8-37`), which is what `XCUT-13`'s non-blocking shutdown asks — and
it is `Dexpace::Closeable`'s idempotent latch, the only state written after construction: nothing
per call lives on the adapter (`TRANSPORT-29`, `ASYNC-22`). The residual is the caller's: a
streaming response still open when the adapter closes has had its connection retired under it, so
the next read that reaches the native body (one the source's own buffer cannot serve) fails as a
`Dexpace::StreamError` — non-retryable, a body that failed after its head (`P3-3`), the body closed
— whose `#cause` and message are the library's own artefact of a retired connection
(`the response body failed mid-stream: NoMethodError: undefined method 'read' for nil`, measured on
4.0.6 and 3.3.12), not a description of the close; read or close the response before closing the
adapter.

## A call, and what the wire carries

`#call(request, options, cancellation)` returns a `Dexpace::Async::Future` **before the head has
arrived**: the request is mapped and re-validated on the caller's fiber, and the exchange runs in a
child task of the caller's current task. What reaches the wire is the four-member `Request` and
nothing else (`HTTP-6`): no `User-Agent`, no `Accept-Encoding`, no `Accept` — `async-http` stamps
none, so there is nothing to delete, unlike `Net::HTTP`. A body-less `GET` goes out with
`content-length: 0`, because `async-http` writes it and suppressing it would mean reaching under the
body layer; `TRANSPORT-26` does not forbid it and `HTTP-7` is about the model, not the wire.

```ruby
server = WireServer.start(Scripts.fixed("[]"))
Sync do
  future = adapter.call(req("http://127.0.0.1:#{server.port}/pets?limit=2",
                            headers: headers("Accept" => "application/json", "X-Trace" => "abc")),
                        EMPTY, nil)
  future.settled?                                            # => false  (returned before the head)
  response = future.value
  response.status.code                                       # => 200
  response.protocol.wire                                     # => "http/1.1"
  response.headers["content-type"]                           # => ["text/plain"]
  response.body.content_length                               # => 2
  response.body_string                                       # => "[]"
end
sent = server.requests.last
[sent.request_line, sent.path]                               # => ["GET /pets?limit=2 HTTP/1.1", "/pets?limit=2"]
[sent.header("accept"), sent.header("x-trace")]              # => ["application/json", "abc"]
sent.header("content-length")                                # => "0"
sent.header("host")                                          # => "127.0.0.1:33599"   (the fixture's port)
[sent.header("user-agent"), sent.header("accept-encoding")]  # => [nil, nil]
```

Before dispatch the header set meets three gates, in order, and every one is applied to the
`Request` the caller handed over — the wire-boundary re-validation phase 1 postponed to the adapters
(`HTTP-17`, `HTTP-18`, `XCUT-18`) runs first, on every name and value, so a forged request that met
no builder is refused as `Dexpace::InvalidArgumentError` through the future before anything is
mapped. Then the **framing set**: the ten folded names in `FRAMING_HEADERS` are never copied and are
logged at verbose, because on this adapter a caller's `Host` or `Content-Length` would be **appended
beside** the library's own rather than replace it (`TRANSPORT-11`). Then the **token predicate**: a
name the RFC 7230 token grammar refuses — `HTTP-17` admits seventeen bytes the grammar does not, `:`
among them — is dropped and reported through the adapter's `logger:` under
`Events::TRANSPORT_HEADER_DROPPED`, **on both protocols** (`TRANSPORT-12`, `P8-40`): `protocol-http1`
would refuse the whole request after the request line is already on the socket, and
`protocol-http2` would transmit the name unvalidated, so one predicate before dispatch is what makes
one request produce one header set whichever protocol ALPN chose. The drop's reporting is
`DropPolicy`'s: the default `ONCE_PER_NAME` warns the first time a folded name is dropped and is
quiet (verbose) afterwards, over a latch bounded at `MAX_TRACKED_NAMES` (64) distinct names, beyond
which every drop is quiet (`TRANSPORT-13`, the policy phase 5b postponed to phase 8 as `OBS-19`);
`EVERY` and `QUIET` are the other two modes, and `DropPolicy.build(mode:)` refuses anything else.

```ruby
server = WireServer.start(Scripts.fixed("ok"))
logged = AsyncHTTP.build(logger: Dexpace::Instrumentation::Logger.build(sink: sink))   # sink: any #debug/#info/#warn/#error object
Sync do
  h = headers("Host" => "bogus.example", "Content-Length" => "999", "X-Bad:Name" => "v", "X-Normal" => "n")
  logged.call(req("http://127.0.0.1:#{server.port}/", headers: h), EMPTY, nil).value.close
  logged.call(req("http://127.0.0.1:#{server.port}/", headers: headers("X-Bad:Name" => "again")), EMPTY, nil).value.close
end
sent = server.requests.first
sent.header("host")                                          # => "127.0.0.1:39165"   (the library's own, never bogus.example)
sent.header("content-length")                                # => "0"
[sent.header("x-bad:name"), sent.header("x-normal")]         # => [nil, "n"]
drops.map { |severity, payload| [severity, payload["header"], payload["reason"]] }   # the sink's header_dropped records
# => [[:debug, "Host", "transport framing header (TRANSPORT-11)"],
#     [:debug, "Content-Length", "transport framing header (TRANSPORT-11)"],
#     [:warn, "X-Bad:Name", "not an RFC 7230 token (TRANSPORT-12)"],
#     [:debug, "X-Bad:Name", "not an RFC 7230 token (TRANSPORT-12)"]]   (once per name, then quiet)
```

`Content-Type` follows `TRANSPORT-10`'s precedence and **invents nothing**: the caller's explicit
header wins, then the body's own media type, and a body with neither goes out with no
`Content-Type` — `async-http` stamps none, where `Net::HTTP`'s form-urlencoded default is what
`dexpace-transport-net_http` pre-empts with `application/octet-stream`. The length is the body's own
`#content_length` when it is known, and a streaming body of unknown length goes out chunked.

```ruby
server = WireServer.start(Scripts.sequenced("a", "b", "c"))
Sync do
  json = Dexpace::Body.string("{}", media_type: Dexpace::MediaType.parse("application/json"))
  adapter.call(req(url, method: "POST", body: json), EMPTY, nil).value.close
  adapter.call(req(url, method: "POST", body: json, headers: headers("Content-Type" => "text/plain")), EMPTY, nil).value.close
  adapter.call(req(url, method: "POST", body: Dexpace::Body.bytes("raw".b)), EMPTY, nil).value.close
end
server.requests.map { |r| r.header("content-type") }         # => ["application/json", "text/plain", nil]
server.requests.map { |r| r.header("content-length") }       # => ["2", "2", "3"]
```

## The response body streams, inside the reactor

The head is adapted the moment `Async::HTTP::Client#call` returns, on the exchange task; the body is
the adapter's own `ResponseBody` over the native `Protocol::HTTP::Body::Readable` — lazy,
pull-shaped, one native `#read` per chunk and nothing read ahead of demand (`ASYNC-21`'s property,
though the ID is not this port's), every chunk retagged `BINARY`, closed through the body's own
`Closeable` latch on exhaustion, on an explicit close and on a mid-stream failure alike, so the
native body is closed exactly once whichever path took it. Reading suspends the reading fiber at the
scheduler and never a thread, which is the whole reason for the gem; `Response#close` releases the
connection to the pool at once, so the server observes the release promptly (`TRANSPORT-19`,
`TRANSPORT-25`). On HTTP/2 an unread body's close is routed through `Dexpace.close_quietly` with the
adapter's `logger:`, because `async-http` writes the stream reset before it transitions the
stream's state, so a peer's end-of-stream landing during that write releases the pooled connection
twice inside the library (measured five of five through a response obtained in a child task and
closed unread by its parent); the connection is retired either way, and the library's raise is
reported through the logger rather than reaching `Response#close`.

```ruby
server = WireServer.start(Scripts.dribble("first-half", "second-half", 0.2))   # a 200 ms gap between the chunks
Sync do
  response = adapter.call(req("http://127.0.0.1:#{server.port}/stream"), EMPTY, nil).value   # the head, at once
  response.body.content_length                               # => -1   (chunked: unknown length)
  buffer = (+"").b
  response.body.source.read_into(buffer, count: 5)           # => 5
  buffer                                                     # => "first"
  response.body_bytes                                        # => "-halfsecond-half"   (the rest, then closed)
  response.body.closed?                                      # => true
end
server.await_closed_connection(timeout: 2)                   # => 1

server = WireServer.start(Scripts.large(1024 * 1024, hold: true))
Sync do
  response = adapter.call(req("http://127.0.0.1:#{server.port}/big"), EMPTY, nil).value
  response.body.source.read_into((+"").b, count: 16)
  response.close                                             # => nil, at once; the server sees the peer close
  response.close                                             # => nil   (idempotent)
end
server.await_closed_connection(timeout: 2)                   # => 1
```

A `204`, a `304` or a `HEAD`'s response has no body: `response.body` is `nil` and the native body,
if the library produced one, was closed by the mapper.

## One budget, one exchange task

The per-call budget is `RequestOptions#timeout`, then `.build(timeout:)`, then the configuration
key `REQUEST_TIMEOUT`, then `DEFAULT_TIMEOUT_SECONDS`; a bare number in `REQUEST_TIMEOUT` is
**milliseconds** (`CFG-7`), so thirty seconds is `30s` or `PT30S`. It is applied as one
`Async::Task#with_timeout` around the exchange — connect, write and the head — so two concurrent calls
with different budgets are each bounded by their own (`TRANSPORT-5`) and a near-zero budget is still a
bound and never "no timeout" (`TRANSPORT-6`). An expiry is `Async::TimeoutError`, a `StandardError`,
wrapped as a **retryable** `Dexpace::TransportError` with the original as `#cause` and the
cancellation token left exactly as it was found (`TRANSPORT-4`, `TRANSPORT-8`'s pair); the exchange
task and its watcher are gone from the reactor once the future has settled, so a long-lived reactor
accumulates nothing per failed call.

```ruby
server = WireServer.start(Scripts.hang_before_headers)
Sync do
  options = Dexpace::RequestOptions.builder.tap { |b| b.timeout = 0.2 }.build
  adapter.call(req("http://127.0.0.1:#{server.port}/slow"), options, nil).value
rescue Dexpace::TransportError => error
  [error.class, error.retryable?, error.phase]               # => [Dexpace::TransportError, true, :connect]
  error.cause.class                                          # => Async::TimeoutError
end                                                          # in well under a second
Dexpace::Configuration::Keys::REQUEST_TIMEOUT                # => "REQUEST_TIMEOUT"
Dexpace::Configuration::Keys::TRANSPORT_CONNECTION_LIMIT     # => "TRANSPORT_CONNECTION_LIMIT"
Dexpace::Configuration.build(overrides: { "REQUEST_TIMEOUT" => "250" }).duration("REQUEST_TIMEOUT")
# => 0.25   (a bare number is milliseconds)
```

## Cancellation: from any thread, delivered at a checkpoint

Three things cancel an exchange, and all three reach it: the caller's `Dexpace::Cancellation`
token, `Future#cancel` on the returned pivot (`ASYNC-6`'s two directions), and a cancellation the
runtime originates — a parent task cancelled, the reactor torn down — which arrives as
`Async::Cancel` inside the exchange task (`TRANSPORT-8`, satisfied on this adapter where the
specification records it vacuous). Every one of the first two is marshalled through a queue: the
token's hook settles the pivot cancelled and pushes its reason, and a transient **watcher** task
inside the reactor pops it and acts on the reactor's own thread — cancelling the exchange task while
it is in flight, or closing the delivered response afterwards, which is what wakes a consumer
blocked in a body read. The queue is the bridge because `Async::Task#cancel` cannot be called from
another OS thread (it raises there and cancels nothing), and the conformance suite cancels its token
from a `Thread.new` exactly as a host with a reactor per thread would. A cancel that arrives as the
exchange is finishing on its own is a no-op on the canceller's side: `Source#cancel` and
`Future#cancel` return normally whatever the exchange's state, because the adapter's hook is total
over the queue it pushes onto — the token still reads cancelled, and the future settles either the
cancellation or the response, never both. What surfaces is
`Dexpace::CancelledError` with the token's reason, the future reads `cancelled?`, it answers no
`retryable?` — a cancellation is terminal, and phase 6a's retry layer treats it so — and the
connection is released (`TRANSPORT-7`). A native response obtained after the pivot was cancelled is
closed, never delivered (`TRANSPORT-9`): the pivot itself closes what a settled completer is handed,
and the exchange checks the token again after every resume.

```ruby
server = WireServer.start(Scripts.hang_before_headers)
Sync do
  source = Dexpace::Cancellation.source
  future = adapter.call(req("http://127.0.0.1:#{server.port}/held"), EMPTY, source.token)
  Thread.new { source.cancel(:caller_gave_up) }.join         # from another OS thread
  begin
    future.value
  rescue Dexpace::CancelledError => error
    [error.class, error.reason]                              # => [Dexpace::CancelledError, :caller_gave_up]
  end
  future.cancelled?                                          # => true
  error.respond_to?(:retryable?)                             # => false
end
server.await_closed_connection(timeout: 2)                   # => 1
```

**`ASYNC-7`, this adapter's half of the contrast the design fixes** (§3.3): "the thread adapter
lets an in-flight blocking read finish, the reactor-backed ones abort at the next scheduler
checkpoint." The interrupt lands only where the exchange task is suspended — a socket read, a pool
wait — and `ensure` blocks run there, which is the property `Thread#raise` lacks and the reason it
is banned in this SDK. The adapter's own suite measures it: a blocked read is abandoned well under
the time the response would have taken to arrive.

## Failures: the token first, then a retryable wrap

Every failure with no response goes through one classifier, and the token is asked **first**: a
cancelled token turns any error into `Dexpace::CancelledError` — a bare `IOError` from a connection
the watcher retired and one of the SDK's own errors alike — because a cancel delivered by retiring
the connection and a peer reset arrive as the same `IOError` with the same message (`TRANSPORT-3`).
Then a `Dexpace::` error passes through unchanged, so a stream-contract violation or the
re-validation's `InvalidArgumentError` is never re-wrapped into something retryable. Everything
else — a refused connection, a resolution failure, a TLS failure, `protocol-http1`'s refusal of a
malformed head, a timeout — wraps as `Dexpace::TransportError` carrying the original as `#cause`,
retryable unconditionally (`TRANSPORT-4`, `TRANSPORT-20`), never a class list: of the families
`async-http` raises, not one is an `::IOError`. A failure while the request is being adapted — a
scheme the adapter cannot dispatch, a body that raises — is delivered through the future too, never
thrown past it (`TRANSPORT-21`); and a success always carries a `Dexpace::Response`, a `204` with no
body included (`TRANSPORT-23`), because the pivot settles with what the mapper built and nothing
else.

```ruby
Sync do
  adapter.call(req("http://127.0.0.1:1/"), EMPTY, nil).value                       # nothing listens on port 1
rescue Dexpace::TransportError => error
  [error.retryable?, error.phase]                            # => [true, :connect]
  error.cause.class                                          # => Errno::ECONNREFUSED
end
Sync { adapter.call(req("ftp://example.test/"), EMPTY, nil).value }
# raises Dexpace::InvalidArgumentError (the async transport dispatches http and https only)
headers("X-Inject" => "a\r\nEvil: 1")
# raises Dexpace::InvalidArgumentError (HTTP-18): the MODEL's own builder refuses the value, so a
#   request built through it never reaches the adapter with one. The adapter re-validates
#   regardless, for a request-shaped object that met no builder (design §10.10's admitted hole):
server = WireServer.start(Scripts.fixed("ok"))
forged = Object.new
forged.define_singleton_method(:method) { Dexpace::Method::GET }
forged.define_singleton_method(:url) { Dexpace::URL.parse!("http://127.0.0.1:#{server.port}/") }
forged.define_singleton_method(:headers) do
  Object.new.tap { |h| h.define_singleton_method(:each_entry) { |&b| b.call("X-Inject", "a\r\nEvil: 1") } }
end
forged.define_singleton_method(:body) { nil }
Sync { adapter.call(forged, EMPTY, nil).value }
# raises Dexpace::InvalidArgumentError (HTTP-18: the adapter's own re-validation, before anything is
#   mapped and before a byte reaches the socket)
server.requests                                              # => []
```

## Lenient inbound mapping, and the two clauses it waives

A vendor status inside `100`–`599` maps with its body readable (`TRANSPORT-24`); an HTTP/2 head maps
to the model's `http/2`. A header whose **value** carries a control byte is dropped alone and logged
at verbose while obs-text is preserved and a repeated `Set-Cookie` survives as two values
(`TRANSPORT-14`'s value clauses); a malformed `Content-Type` downgrades to no media type
(`TRANSPORT-27`'s media-type clause); an absent native length is the `-1` sentinel. Two clauses are
**not** satisfiable on this adapter and are named waivers in its conformance run rather than silent
gaps (`P8-38`): a malformed inbound header **name** and a non-numeric `Content-Length` both make
`protocol-http1` refuse the whole response out of the read, before a response object exists to
adapt, and the failure surfaces as a retryable `TransportError` carrying the library's own error.
`Net::HTTP` delivers both heads, so 8a's driver waives nothing.

```ruby
server = WireServer.start(Scripts.vendor_status(299, "custom"))
Sync do
  response = adapter.call(req("http://127.0.0.1:#{server.port}/"), EMPTY, nil).value
  [response.status.code, response.body_string]               # => [299, "custom"]
end

server = WireServer.start(Scripts.malformed_headers)          # a non-ASCII header NAME among the good ones
Sync do
  adapter.call(req("http://127.0.0.1:#{server.port}/"), EMPTY, nil).value
rescue Dexpace::TransportError => error
  [error.class, error.cause.class]                           # => [Dexpace::TransportError, Protocol::HTTP1::BadHeader]
end
```

## TLS and HTTP/2

An `https` origin under the owning construction gets the adapter's own `OpenSSL::SSL::SSLContext`:
`VERIFY_PEER` with the platform's default certificate store, and `alpn_protocols` set to
`ALPN_PROTOCOLS` (`h2`, then `http/1.1`), so HTTP/2 is negotiated wherever the peer offers it and
HTTP/1.1 otherwise. A caller's `ssl_context:` is used **verbatim** — never re-armed — so a context
without `alpn_protocols` negotiates HTTP/1.1, and one with a private store trusts what it says. Over
HTTP/2 one connection multiplexes every concurrent call to an origin (the adapter's suite drives
sixteen through one and counts one connection), which is the property a thread pool cannot have;
plaintext prior-knowledge HTTP/2 is not something an adapter can know from a URL, so it is reachable
only through `.using` over a caller's own client built for it. Both protocols are proven by the
adapter's suite against an in-process `async-http` server — HTTP/1.1, plaintext HTTP/2 and TLS HTTP/2
by real ALPN over a per-run self-signed certificate — including the wire-boundary re-validation over
HTTP/2, where nothing below the model validates and a CRLF value would otherwise reach the peer
verbatim. The portable suite's fixture speaks plaintext HTTP/1.1 only, so `TRANSPORT-4`'s
open-timeout half and every TLS property are this gem's own suite's, as its `PREAMBLE` says.

## Close

```ruby
adapter.close                                                # => nil, reactor-free, never waits on a busy connection
adapter.closed?                                              # => true
Sync do
  failed = adapter.call(req("http://127.0.0.1:1/"), EMPTY, nil)
  failed.settled?                                            # => true
  failed.value                                               # raises Dexpace::ClosedError (through the future, never synchronously)
end
```

An owning adapter fails every later call through the future with `Dexpace::ClosedError` and never
opens a connection; a borrowing adapter stays usable after its own close, because the client is the
caller's (`TRANSPORT-15`, `TRANSPORT-16`, `SEAM-15`).

## What is deliberately not here

No redirect following, no retry and no authentication live in this gem: those are phase 6's pillar
steps, and `AsyncPipeline.standard(adapter, redirect: :unsupported)` is how a caller gets retry and
authentication around this transport (`docs/sdk-documentation/pipelines.md`). No reactor of the
adapter's own, for the reasons above. No proxy: `async-http` has no proxy route the adapter could
carry the configuration chain into, so `TRANSPORT-30` stays the synchronous adapter's. No
transport-milestone tracing (`OBS-28`): the adapter takes a `logger:` and no tracer, because no
route exists from a three-argument seam to a per-operation `HTTPTracer` (8a's R6, `P8-7`, on phase
10's inbound list). No `Content-Type` default, no `User-Agent`, no auto-stamp of any kind. And no
Ruby 3.2: this gem alone declares 3.3, and the composition that keeps a 3.2 consumer whole is the
synchronous transport, `dexpace-transport-net_http`.
