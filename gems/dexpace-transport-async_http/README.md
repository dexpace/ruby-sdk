# dexpace-transport-async_http

Part of the [dexpace Ruby SDK](../../README.md): an HTTP-client toolkit, not an HTTP client.
This gem is the asynchronous transport seam's reference adapter, over `async-http`.

**Status: `0.0.0`, unpublished; the adapter is built.** `lib/` holds phase 8c's
`Dexpace::Transport::AsyncHTTP`: the two constructions
`.build(timeout:, logger:, drop_policy:, connection_limit:, ssl_context:, configuration:)` over a
client map the adapter owns -- one `Async::HTTP::Client` per (reactor, origin), bounded at
`MAX_ORIGINS` -- and `.using(client, logger:, drop_policy:)` over a caller's own client, the
`Adapter` behind both with its owning-or-borrowing lifecycle, the header policy the wire carries
(`FRAMING_HEADERS`, the RFC 7230 token predicate applied on both protocols, and `DropPolicy`'s
once-per-name reporting), a per-call exchange task under the caller's own reactor task with one
total per-call budget, the queue-marshalled cancellation bridge that lets a token cancelled from any
thread reach the exchange, the lazy pull-shaped response body, the classifier that asks the
cancellation token first and wraps every other failure as a retryable `Dexpace::TransportError`,
the lenient inbound mapping, the default TLS context offering HTTP/2 by ALPN (`ALPN_PROTOCOLS`), and
the registration under `REGISTRY_KEY` (`:async_http`) that requiring the gem performs. Proven over
HTTP/1.1, plaintext prior-knowledge HTTP/2 and TLS HTTP/2 on Ruby 3.3, 3.4 and 4.0, and against the
shared conformance suite in `dexpace-conformance` as its second driver.

## Install

```ruby
# Gemfile
gem "dexpace-transport-async_http"
```

This gem requires **Ruby >= 3.3** -- narrower than the SDK's 3.2 floor, because `async-http`
and `async` require it (the SDK's `P8-36`). A consumer on 3.2 composes `dexpace-core` with
`dexpace-transport-net_http` and loses only the reactor transport.

## The smallest thing that works today

```ruby
require "dexpace/transport/async_http"

adapter = Dexpace::Transport::AsyncHTTP.build
request = Dexpace::Request.build(method: "GET", url: "http://127.0.0.1:8080/pets?limit=2",
                                 headers: Dexpace::Headers::EMPTY)
Sync do
  future = adapter.call(request, Dexpace::RequestOptions::EMPTY, nil)   # against a server on 8080
  response = future.value
  response.status.code  # => 200
  response.body_string  # => "[]" -- decoded through the one decode boundary, then closed
end
adapter.close           # => nil, reactor-free
```

The response body streams from the connection until it is drained or closed, on the fiber that
reads it; `Response#body_string` does both. `AsyncPipeline.standard(adapter, redirect: :unsupported)`
puts retry and authentication around it.

## What a reactor means here

**Every call needs a running reactor on the calling thread.** `Adapter#call` outside `Sync { }` or
`Async { }` does not raise: it returns an **already-failed** future carrying `Dexpace::SeamError`
whose message names the fix (`TRANSPORT-21`, `P8-39`). This gem creates no reactor of its own -- a
`Sync` inside the adapter would block the caller's thread and defeat the seam, and a reactor
thread the adapter owned would be a thread pool by another name, carrying the constructor's
diagnostic context rather than the caller's.

**A response does not outlive the reactor that produced it.** `Sync { }` returns only when the
reactor has no work left, and on its way out it drains the connection pool, which waits for every
busy connection -- and the connection behind an unread body is busy until that body is read or
closed. So read or close the response **inside** the block that made the call; a `Sync` that hands
a streaming response out to code after it never returns. `Response#body_string`, `#body_bytes` and
`#close` all release the connection.

**`Dexpace::AsyncTransport.sync_over(adapter)` still requires a reactor.** The bridge awaits the
future this adapter returns, and the exchange behind that future cannot run without a reactor, so
a caller with no reactor gets the same `SeamError` through the bridge as through `#call`.

**`Dexpace::Transport.async_over` accepts this adapter silently.** That bridge takes a synchronous
transport, and handing it an object whose `#call` already returns a future yields a future of a
future; the return-type check that would refuse it is phase 2's open finding in `dexpace-core`,
not this gem's to fix. Use the adapter as the `Dexpace::AsyncTransport` it is.

## ASYNC-7: what a cancellation interrupts

The SDK's design (§3.3) fixes the contrast between its two async adapters in one sentence: **"the
thread adapter lets an in-flight blocking read finish, the reactor-backed ones abort at the next
scheduler checkpoint."** This gem is the reactor-backed one. A cancellation -- the token's, the
future's, or one the runtime originates by cancelling a parent task -- reaches the exchange task as
`Async::Cancel` at its next scheduler checkpoint, which is where a blocked socket read is suspended,
and `ensure` blocks run there. That is the property `Thread#raise` lacks and the reason it is banned
in this SDK: the interrupt lands only where the task can be interrupted, never inside a connection's
release. The adapter's own suite measures it (a blocked read is abandoned well under the time the
response would have taken), so this sentence and the assertion cannot drift apart.

A cancellation from another OS thread -- `Cancellation::Source#cancel` on a thread that is not the
reactor's -- is marshalled through a queue to a watcher task inside the reactor, because
`Async::Task#cancel` from a foreign thread is not supported by the runtime; the effect is the same
and it is prompt.

## Timeouts, headers and what the wire carries

- **The per-call budget** is `RequestOptions#timeout`, then `.build(timeout:)`, then the
  configuration key `REQUEST_TIMEOUT`, then `DEFAULT_TIMEOUT_SECONDS` (60). A bare number in
  `REQUEST_TIMEOUT` is **milliseconds** (`CFG-7`): thirty seconds is `30s` or `PT30S`. The budget
  is one `Async::Task#with_timeout` over the whole exchange, so it bounds the head; a body read
  after delivery is bounded by the caller's own reactor discipline.
- **Framing headers are never copied** from a request: the ten folded names in `FRAMING_HEADERS`
  (`host`, `content-length`, `transfer-encoding`, `connection`, `keep-alive`, `proxy-connection`,
  `te`, `trailer`, `upgrade`, `expect`) are dropped and logged at verbose, because `async-http`
  would append a caller's `Host` beside its own rather than replace it (`TRANSPORT-11`).
- **A header name the RFC 7230 token grammar refuses** (`HTTP-17` admits seventeen bytes the
  grammar does not, `:` among them) is dropped **on both protocols** before dispatch
  (`TRANSPORT-12`, `P8-40`) and reported through the adapter's `logger:` once per name, then
  quietly, over a bounded latch (`TRANSPORT-13`, `DropPolicy`). On HTTP/1.1 `protocol-http1` would
  refuse the whole request after the request line is on the wire; on HTTP/2 `protocol-http2` would
  transmit it unvalidated.
- **No `Content-Type` is invented.** The caller's explicit header wins, then the body's own media
  type; a body with neither goes out with no `Content-Type` -- `async-http` stamps none, unlike
  `Net::HTTP`, whose form-urlencoded default is what `dexpace-transport-net_http` pre-empts with
  `application/octet-stream`.
- **A body-less `GET` carries `content-length: 0`.** `async-http` writes it, and suppressing it
  would mean reaching under the body layer; `TRANSPORT-26` does not forbid it and `HTTP-7` is about
  the model, not the wire. Recorded rather than fixed.
- **HTTP/2** is negotiated by ALPN over TLS through the default context (`VERIFY_PEER`,
  `ALPN_PROTOCOLS`); a caller's `ssl_context:` is used verbatim, so a context without
  `alpn_protocols` negotiates HTTP/1.1. Plaintext prior-knowledge HTTP/2 is a property of a
  caller's own client, reachable through `.using`.
- **On Ruby 4.0**, the first use of `IO::Buffer` under a scheduler prints Ruby's once-per-process
  "IO::Buffer is experimental" warning to stderr. The adapter cannot suppress it for a host; a
  host that runs with warnings fatal should expect it once, as this gem's own suite does.

## Depends on

`dexpace-core`, and `async-http ~> 0.104` -- the one gem `NFR-2` budgets for this adapter, whose
closure brings `async`, `async-pool`, `protocol-http`, `protocol-http1`, `protocol-http2`,
`io-event` and `openssl`; on Ruby 3.3 that resolution compiles the `openssl` gem, because the
interpreter's own is older than `io-stream` requires.

## Where to read next

- `docs/sdk-documentation/transport-async_http.md` -- the as-built page: the reactor discipline,
  what the wire carries, what a cancellation interrupts, what a failure means, and what is
  deliberately not here.
- `docs/sdk-documentation/conformance.md` -- the suite this adapter is proven against, and the
  three things a green run does not prove.
- `docs/sdk-documentation/architecture.md` -- how the gems compose and which one to install.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` -- the gem layout and the
  zero-dependency invariant every gem here is built under.
