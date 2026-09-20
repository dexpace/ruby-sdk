# The synchronous transport: `dexpace-transport-net_http`

**As built by phase 8a, written against source on 2026-09-20.** This page says what the reference
synchronous transport gives an SDK author today: `Dexpace::Transport::NetHTTP`, a module with two
constructions and a fresh-per-call `Net::HTTP` behind each, the header policy the wire actually
carries, one total per-call budget across three native knobs, a response body that streams from the
socket until the caller drains or closes it, and the failure classification that keeps phase 6a's retry
layer honest. What each is *required* to do is `docs/product-spec/17-transport-adapter-conformance-contract.md`
(`TRANSPORT-1`–`TRANSPORT-30`, of which this adapter owns twenty-three; the other seven are the async
adapter's); how the design maps it to Ruby is `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.2 read with
entries 10 and 15 of `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`; the
per-requirement proof is `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-checklist.md`.
Signatures live in `gems/dexpace-transport-net_http/sig/`, and this page does not restate them. Every
example below was run, in the order printed and as one script, against the built code on 4.0.6
(net-http 0.9.1) and 3.2.11 (net-http 0.4.1) and printed the same on both, except for the ephemeral port a
`Host` line or an error message names, which is the run's own. The examples use `dexpace-conformance`'s
`WireServer` and `Scripts` as the server — a real `TCPServer` on `127.0.0.1` answering a scripted reply
and recording what it was sent — because a transport page's examples should touch a socket and nothing
outside the machine. Six names are the page's shorthand and nothing else is assumed: `NetHTTP` is
`Dexpace::Transport::NetHTTP`; `WireServer` and `Scripts` are `Dexpace::Conformance::WireServer` and
`Dexpace::Conformance::Scripts`, after `require "dexpace/conformance"`; `req(url, method: "GET",
headers: Dexpace::Headers::EMPTY, body: nil)` is `Dexpace::Request.build` over those four;
`headers(pairs)` is `Dexpace::Headers.builder` with each pair added; and `EMPTY` is
`Dexpace::RequestOptions::EMPTY`. `adapter` is the owning adapter the first block builds, never closed —
the one block that shows a close builds its own — and every block that talks to a socket starts its own
`server` and reads its port for `url`. A host that exports `HTTPS_PROXY` or `HTTP_PROXY` will see the
socket blocks route through that proxy, because that is what the configuration chain says (`CFG-24`,
the proxy block below); the gem's own suites blank those keys around every test for exactly that reason.
The borrowed-client blocks build a plain `Net::HTTP.new(host, port)`, whose own `:ENV` default reads the
environment through `URI#find_proxy` on `#start`: under an upper-case `HTTP_PROXY` with no lower-case
`http_proxy` that prints uri's "The environment variable HTTP_PROXY is discouraged" warning and, because
`find_proxy` exempts loopback, routes nowhere. The gem's suites pass an explicit nil proxy to every
fixture client they start for that reason, exactly as the adapter passes its own (the proxy block below).

**The gem's whole dependency budget is `dexpace-core` and `net-http >= 0.4`** (`NFR-2`): a default gem
on every supported Ruby, no upper bound, and the adapter is proven on 0.4.1 (Ruby 3.2 and 3.3), 0.6.0
(3.4) and 0.9.1 (4.0). Requiring the gem registers it with phase 2's registry under `:net_http`, so a
consumer that requires it and nothing else resolves an adapter without naming one (`SEAM-5`).

```ruby
require "dexpace/transport/net_http"

adapter = NetHTTP.build
adapter.owned?                                               # => true
Dexpace::Transport.conforms?(adapter)                        # => true
Dexpace::Transport.registered_keys                           # => [:net_http]
Dexpace::Transport.resolve.class                             # => Dexpace::Transport::NetHTTP::Adapter
NetHTTP.default.equal?(NetHTTP.default)                      # => false  (a fresh adapter every call)
NetHTTP::MANAGED_HEADERS
# => ["host", "content-length", "transfer-encoding", "connection", "keep-alive", "proxy-connection",
#     "te", "trailer", "upgrade", "expect"]
NetHTTP::DEFAULT_CONTENT_TYPE                                # => "application/octet-stream"
NetHTTP::TLS_SETTINGS                                        # => [:ca_file, :ca_path, :cert, :key, :verify_mode, :min_version]
[NetHTTP::DEFAULT_TIMEOUT_SECONDS, NetHTTP::MIN_TIMEOUT_SECONDS, NetHTTP::JOIN_DEADLINE_SECONDS]
# => [60.0, 0.001, 5.0]
```

## Two constructions, and ownership is decided at construction

`NetHTTP.build(timeout: nil, logger: Instrumentation::Logger::NULL, tls: nil)` is the SDK-managed
construction: **every call builds its own `Net::HTTP` from the request's URL** — `Net::HTTP` holds one
socket and one response state per instance, and one shared client under eight threads produced 26
responses matched to the wrong request when the design measured it — sets `max_retries = 0` and
`proxy_from_env = false` on it, applies this call's budget to its three timeout knobs, and closes the
connection when the response is closed. The cost, stated rather than hidden: one TCP (and over HTTPS one
TLS) handshake per request, no keep-alive and no pool on this construction
(`docs/first-release.md` § What v1 ships without says the same). `#close` latches, and an owning adapter
raises `Dexpace::ClosedError` on any later send (`SEAM-15`, `TRANSPORT-15`).

`NetHTTP.using(client, logger:)` is the borrowing construction: the caller's `Net::HTTP` is used
**verbatim** — no knob, no endpoint and no `use_ssl` is ever assigned on it, and the adapter neither
starts nor finishes it, so a client the caller started keeps its connection across calls (`XCUT-22`).
Three consequences follow and are the contract: the endpoint is the client's, and a request naming
another host, port or scheme is refused unsent; a per-call `RequestOptions#timeout` is refused rather than
applied to someone else's client; and calls are serialised, one exchange at a time from `#call` until its
response is closed, because one `Net::HTTP` cannot carry two. The client must already have
`max_retries == 0` — the adapter asserts it and never sets it, because `TRANSPORT-2` scopes the disable to
an SDK-managed transport and the knob is the caller's. A borrowing adapter's own `#close` latches and
leaves both the client and itself usable.

```ruby
client = Net::HTTP.new("127.0.0.1", 1)
NetHTTP.using(client)
# => Dexpace::InvalidArgumentError: a borrowed Net::HTTP must already have max_retries == 0
#    (TRANSPORT-2): the adapter may not set it on a client it does not own (XCUT-22)
client.max_retries = 0
NetHTTP.using(client).owned?                                 # => false
```

Against a keep-alive server the borrowed client's one connection serves two exchanges, and the adapter's
close touches nothing of the caller's:

```ruby
# Two responses on ONE connection: the fixture reads the first request, the script reads the second.
keep_alive = lambda do |conn, _head|
  Scripts.write_response(conn, body: "one")
  head = (+"").b
  head << conn.readpartial(4096) until head.include?("\r\n\r\n")
  Scripts.write_response(conn, body: "two")
end
server = WireServer.start(keep_alive)
url = "http://127.0.0.1:#{server.port}/"
client = Net::HTTP.new("127.0.0.1", server.port)
client.max_retries = 0
client.start
borrowed = NetHTTP.using(client)
2.times.map { borrowed.call(req(url), EMPTY, nil).body_string }   # => ["one", "two"]
[server.connections, client.started?]                        # => [1, true]
borrowed.close
[borrowed.closed?, client.started?]                          # => [true, true]
borrowed.call(req("http://127.0.0.1:1/"), EMPTY, nil)
# => Dexpace::InvalidArgumentError: a borrowed Net::HTTP is bound to 127.0.0.1:38955 (use_ssl=false)
#    and this request names 127.0.0.1:1 (use_ssl=false); the adapter may not re-point a client it does
#    not own (TRANSPORT-15, XCUT-22): use NetHTTP.build, or a client bound to this origin
owning = NetHTTP.build
owning.close
owning.call(req(url), EMPTY, nil)
# => Dexpace::ClosedError: this transport is closed
```

## A call, and what the wire carries

`Adapter#call(request, options, cancellation)` is phase 2's three-argument seam (`SEAM-11`); a nil
cancellation is the never-cancelled token. The wire request is the caller's `Dexpace::Headers` minus
`MANAGED_HEADERS`, plus `Host` and the framing header the transport derives, plus a `Content-Type`
derived by `TRANSPORT-10`'s precedence — and **nothing else**: `Net::HTTP` stamps `Accept`, `User-Agent`
and `Accept-Encoding` on every request it builds, and the adapter deletes all three, because `HTTP-6`
makes the four-member `Request` the whole truth about a request (P8-2).

```ruby
server = WireServer.start(Scripts.fixed("hello", headers: { "Content-Type" => "text/plain", "X-Trace" => "t1" }))
response = adapter.call(req("http://127.0.0.1:#{server.port}/pets?limit=2"), EMPTY, Dexpace::Cancellation.none)
response.status.code                                         # => 200
response.protocol.to_s                                       # => "http/1.1"
response.headers.entries                                     # => [["content-type", "text/plain"], ["x-trace", "t1"], ["content-length", "5"]]
response.body.content_length                                 # => 5
response.body_string                                         # => "hello"
server.requests.first.head                                   # => ["GET /pets?limit=2 HTTP/1.1\r\n", "Host: 127.0.0.1:35313\r\n", "\r\n"]
```

The header policy, on a `POST` carrying a bogus `Host`, `Content-Length` and `Connection` beside a
pass-through header (`TRANSPORT-11`, P8-13): the three managed names are dropped — each drop logged once
at `VERBOSE` under `Instrumentation::Events::TRANSPORT_HEADER_DROPPED` through the adapter's `logger:` —
`Host` and `Content-Length` are the transport's own, and the pass-through survives. The caller's explicit
`Content-Type` wins over the body's media type; with none, the body's is used; with neither, a
body-permitted method carries `application/octet-stream`, body or not (P8-4) — `Net::HTTP`'s own
fallback would be `application/x-www-form-urlencoded`, a claim a server acts on. A body-less `POST` goes
out with `Content-Length: 0` (`TRANSPORT-26`); an unknown-length body goes out chunked; every body is
streamed through phase 3a's `BufferedSource.over`, pulled from `#each` on demand and written exactly
once (`TRANSPORT-17`). `proxy-authorization` is deliberately **not** managed: this adapter stamps no
proxy credential of its own, so a caller's passes through.

```ruby
server = WireServer.start(Scripts.fixed("ok"))
url = "http://127.0.0.1:#{server.port}/"
json = Dexpace::MediaType.parse("application/json")
request = req(url, method: "POST",
              headers: headers("Host" => "bogus.example", "Content-Length" => "99", "Connection" => "keep-alive",
                               "X-Trace" => "t2", "Content-Type" => "text/plain"),
              body: Dexpace::Body.bytes("{}".b, media_type: json))
adapter.call(request, EMPTY, nil).close
server.requests[0].head
# => ["POST / HTTP/1.1\r\n", "X-Trace: t2\r\n", "Content-Type: text/plain\r\n", "Content-Length: 2\r\n",
#     "Host: 127.0.0.1:37825\r\n", "\r\n"]
adapter.call(req(url, method: "POST", body: Dexpace::Body.bytes("{}".b, media_type: json)), EMPTY, nil).close
server.requests[1].head.grep(/Content-Type/)                 # => ["Content-Type: application/json\r\n"]   (the body's, no explicit header)
adapter.call(req(url, method: "POST"), EMPTY, nil).close
server.requests[2].head.grep(/Content-/)                     # => ["Content-Type: application/octet-stream\r\n", "Content-Length: 0\r\n"]  (no body)
adapter.call(req(url, method: "POST", body: Dexpace::Body.chunked(%w[ab cd])), EMPTY, nil).close
server.requests[3].head.grep(/Transfer|Content-Length/)      # => ["Transfer-Encoding: chunked\r\n"]   (Body.chunked)
server.requests[3].body                                      # => "abcd"
```

**Every outbound header is re-validated immediately before dispatch** (`HTTP-17`, `HTTP-18`, `XCUT-18`):
`Dexpace::HeaderSyntax.validate_name!` and `.validate_outbound_value!` run over the request's headers
before anything is copied, so a duck-typed impostor that never met a `Headers::Builder` and carries a CRLF
in a header **name** — which `Net::HTTPGenericRequest#[]=` accepts and would write to the wire — is
refused with `Dexpace::InvalidArgumentError` and reaches no socket. This is the mitigation phase 1
postponed to the adapters for the constructor-privacy gap design §10.10 admits.

**`decode_content` is off, unconditionally** (P8-3): a `Content-Encoding: gzip` response is delivered
compressed, with `Content-Encoding` and the declared `Content-Length` intact, because that is the
response the server sent (`TRANSPORT-24`). The cost — no transparent decompression — is the caller's
to reverse with one `Accept-Encoding` header and a decode of their own.

## The response body streams, and the caller owns closing it

The response head is adapted on the caller's thread the moment it arrives; the body is a
`Dexpace::ResponseBody` over a `BufferedSource` over a **per-response producer thread** that drives
`Net::HTTP#request`'s block form and hands chunks across a `Thread::SizedQueue(1)` (P8-1, the design's
R1). So `#call` returns before the second chunk has been written, the body is read lazily through phase
3a's readers, and `Response#close` cascades — `ResponseBody#close` → `BufferedSource#close` →
the pump's close, which closes the queue, finishes the connection and joins the producer with a
**bounded** deadline (`JOIN_DEADLINE_SECONDS`), so the server observes the release promptly
(`TRANSPORT-19`, `TRANSPORT-25`, `SEAM-11`). One thread per in-flight response is the cost; a response
nobody closes and nobody drains strands one thread and one connection, which is what breaking
`SEAM-11`'s "the caller owns reading and closing it" costs.

```ruby
server = WireServer.start(Scripts.dribble("first-half", "second-half", 0.2))   # a 200 ms gap between the chunks
response = adapter.call(req("http://127.0.0.1:#{server.port}/stream"), EMPTY, nil)   # returns in a few ms
response.body.content_length                                 # => -1   (chunked: unknown length)
buffer = (+"").b
response.body.source.read_into(buffer, count: 5)             # => 5
buffer                                                       # => "first"
response.body_bytes                                          # => "-halfsecond-half"   (the rest, then closed)
server.await_closed_connection(timeout: 2)                   # => 1

server = WireServer.start(Scripts.large(1024 * 1024, hold: true))
response = adapter.call(req("http://127.0.0.1:#{server.port}/big"), EMPTY, nil)
response.body.source.read_into((+"").b, count: 16)
response.close                                               # => nil, at once; the server sees the peer close
server.await_closed_connection(timeout: 2)                   # => 1
response.close                                               # => nil   (idempotent)
```

A `204`, a `304` or a `HEAD`'s response has no body and no producer thread; `response.body` is `nil`.

## One budget across three knobs

`RequestOptions#timeout` is a **total per-call budget** in seconds (P8-5, the design's R3), not a value
assigned to `open_timeout`, `write_timeout` and `read_timeout` each: the adapter computes a monotonic
deadline at `#call` entry through phase 5a's `Dexpace::Clock`, assigns the remaining budget to the three
knobs before the connection exists, and **reassigns `read_timeout` after every chunk** the producer
receives, so a trickling body of *n* chunks cannot take *n* times the budget. The tiers, highest first:
`options.timeout` on the call; `NetHTTP.build(timeout:)`; then `Configuration::Keys::REQUEST_TIMEOUT`
through `Configuration#duration` — whose grammar treats a bare number as **milliseconds** (`CFG-7`), so
`REQUEST_TIMEOUT=30` is thirty milliseconds and thirty seconds is `30s` or `PT30S` — and finally
`DEFAULT_TIMEOUT_SECONDS`, 60. A budget that is already spent raises before any socket is touched, as a
retryable failure with `phase: :connect`; a strictly positive one below `MIN_TIMEOUT_SECONDS` is clamped
up to it (`TRANSPORT-6`), never down to the zero `Net::HTTP` reads as "poll once".

```ruby
server = WireServer.start(Scripts.hang_before_headers)       # accepts, reads the request, never answers
url = "http://127.0.0.1:#{server.port}/"
options = Dexpace::RequestOptions.build(timeout: 0.2, max_retries: nil, tags: {})
begin
  NetHTTP.build(timeout: 30).call(req(url), options, nil)    # the call's 0.2 s wins over the transport's 30
rescue Dexpace::TransportError => error
  error.message                                              # => "Net::ReadTimeout with #<TCPSocket:(closed)>"
  [error.retryable?, error.phase, error.cause.class]         # => [true, :connect, Net::ReadTimeout]
  Dexpace::Resilience::Policy.throwable_retryable?(error)    # => true
end

client = Net::HTTP.new("127.0.0.1", server.port)
client.max_retries = 0
NetHTTP.using(client).call(req(url), options, nil)
# => Dexpace::InvalidArgumentError: a per-call timeout cannot apply to a borrowed Net::HTTP without
#    mutating it (TRANSPORT-5 against XCUT-22); use NetHTTP.build for a call that needs one

Dexpace.configure { |b| b.override(Dexpace::Configuration::Keys::REQUEST_TIMEOUT, "150ms") }
begin
  NetHTTP.build.call(req(url), EMPTY, nil)                   # the configured tier: 150 ms, in under a second
rescue Dexpace::TransportError => error
  error.cause.class                                          # => Net::ReadTimeout
end
Dexpace.reset_config!
```

## Failures: the token first, then a retryable wrap

Every failure that produced no response goes through one classifier (the design's `Failures`), in this
order (`TRANSPORT-3`, `TRANSPORT-4`, `TRANSPORT-20`): if the call's cancellation token is cancelled, the
failure is `Dexpace::CancelledError` carrying the token's reason, **whatever the exception was** — a
cancel delivered by closing the socket and a peer reset arrive as the same `IOError` with the same
message, so no class or message test could tell them apart; otherwise a `Dexpace::Error` of the SDK's own
passes through unchanged; otherwise the error is wrapped as a retryable `Dexpace::TransportError` with
the original as `#cause`, as a catch-all and never a list — `Net::OpenTimeout`, `ReadTimeout`,
`WriteTimeout`, `SocketError`, every `Errno::*`, `OpenSSL::SSL::SSLError`, `EOFError`, `IOError`,
`Net::HTTPBadResponse`, `Net::HTTPHeaderSyntaxError` and `Zlib::Error` are the families it meets, and
**not one of them but `EOFError` and `IOError` is an `::IOError`**, which is why an unwrapped one would
classify not-retryable through phase 6a's capability query (`RETRY-2`, `XCUT-4`, `P6-4`). The
cancellation token is subscribed for the whole life of the response, so a cancel under a blocked body
read closes the pump and the read raises the cancellation.

```ruby
flushed = Thread::Queue.new
server = WireServer.start(Scripts.hang_after_headers(on_headers_written: -> { flushed.push(true) }))
url = "http://127.0.0.1:#{server.port}/"
source = Dexpace::Cancellation.source
canceller = Thread.new { flushed.pop; source.cancel(:user_navigated_away) }   # once the head has gone out
begin
  adapter.call(req(url), EMPTY, source.token).body_bytes
rescue Dexpace::CancelledError => error
  error.message                                              # => "the operation was cancelled: user_navigated_away"
  error.reason                                               # => :user_navigated_away
end
canceller.join

closed = WireServer.start(Scripts.fixed("x"))
closed.close                                                 # the port is now one nothing listens on
begin
  adapter.call(req("http://127.0.0.1:#{closed.port}/"), EMPTY, nil)
rescue Dexpace::TransportError => error
  error.message                                              # => "Failed to open TCP connection to 127.0.0.1:35077 (Connection refused - connect(2) for \"127.0.0.1\" port 35077)"
  [error.phase, error.cause.class.ancestors.include?(SystemCallError)]   # => [:connect, true]
end
```

## Lenient inbound mapping

A status code maps totally (`Status.of` over the three-digit codes `Net::HTTP` parses — a 520 is a 520,
`TRANSPORT-24`); headers come from `Net::HTTPResponse#to_hash` and nothing else, so a multi-valued
`Set-Cookie` arrives as two values and bytes are preserved, and a header whose name or value the SDK's
inbound grammar refuses is **dropped, logged at VERBOSE by name, and never fails the response**
(`TRANSPORT-14`; obs-text is kept). A `Content-Length` that is not one run of at most fifteen digits —
`abc`, `-4`, two values, a sixteen-digit run — maps to the unknown-length sentinel `-1` with the raw
header still in `response.headers` (the grammar is a `Regexp.new` with its own timeout, as every pattern a
wire value reaches in this SDK is), and a
malformed `Content-Type` downgrades to a nil media type (`TRANSPORT-27`); the body reads either way,
because the adapter never lets `Net::HTTP` parse the length itself.

```ruby
server = WireServer.start(Scripts.malformed_content_length)  # Content-Length: abc, Content-Type: not a/;;media type
response = adapter.call(req("http://127.0.0.1:#{server.port}/"), EMPTY, nil)
response.headers["Content-Length"]                           # => ["abc"]
response.body.content_length                                 # => -1
response.body.media_type                                     # => nil
response.body_string                                         # => "hi"

server = WireServer.start(Scripts.vendor_status(520, "origin error"))
response = adapter.call(req("http://127.0.0.1:#{server.port}/"), EMPTY, nil)
[response.status.code, response.body_string]                 # => [520, "origin error"]
```

**Not lenient, and stated**: `Dexpace::Protocol` admits `HTTP/1.1` and `HTTP/2` only (`HTTP-33`), so a
server answering `HTTP/1.0` makes the adapter raise `Dexpace::InvalidArgumentError` after the head, with
the connection released first (`TRANSPORT-22`). Widening `Protocol::WIRE_FORMS` is a phase-1 surface
decision on phase 10's inbound list, not an adapter's to take. The status has the same shape: `Status`
is total over `100`–`599` (`HTTP-10`'s reading, phase 1's), while `Net::HTTP` parses any three digits
and delivers a `999` or a `600` as an `HTTPUnknownResponse` — such a head raises the same
`InvalidArgumentError` after the head with the connection released, `599` maps, and whether
`TRANSPORT-24`'s "any code" reaches `600`–`999` is the same kind of phase-1 question, on the same list.

## TLS and the proxy

`.build`'s `tls:` keyword (the design's R18) takes a `Hash` of plain values over exactly
`TLS_SETTINGS` — `ca_file` and `ca_path` as path Strings, `cert` an `OpenSSL::X509::Certificate` and
`key` an `OpenSSL::PKey` the caller built, `verify_mode` an Integer such as `OpenSSL::SSL::VERIFY_PEER`,
`min_version` a Symbol such as `:TLS1_2` — validated at construction and assigned to the per-call client
only when the URL is `https`. With no `tls:` nothing is assigned and OpenSSL's own defaults apply:
`VERIFY_PEER` with hostname verification. Passing `verify_mode: OpenSSL::SSL::VERIFY_NONE` is the caller
disabling verification deliberately; the adapter never weakens a default on its own, and an unknown key
raises, because a silently ignored `verify_mode:` is a security setting the caller believes they set.

```ruby
NetHTTP.build(tls: { verify_hostname: false })
# => Dexpace::InvalidArgumentError: tls: does not accept :verify_hostname; accepted keys are ca_file,
#    ca_path, cert, key, verify_mode, min_version
NetHTTP.build(tls: { ca_file: "/etc/ssl/corp.pem", min_version: :TLS1_2 }).owned?   # => true
```

The proxy is phase 5a's (`CFG-22`–`CFG-28`, `TRANSPORT-30`): each call resolves `Dexpace::Proxy.resolve`
over the configuration chain — `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY` — asks the resolved proxy's
`#bypass?` for this call's host, and hands the four values to `Net::HTTP.new` as its proxy positionals,
with `proxy_from_env = false` beside them: `Net::HTTP.new`'s own default is `:ENV`, which would have read
a lower-case `http_proxy` the SDK never resolved. A resolved proxy carrying a custom challenge handler, or
a SOCKS type — two things `Net::HTTP` cannot honour — is logged once at `WARNING` under
`NetHTTP::PROXY_LIMITATION_EVENT` naming the feature and the Basic fallback, and the call proceeds with
Basic from the proxy's username and password. Proxy credentials appear in no log record, and an origin
`401` draws no `Proxy-Authorization` out of the adapter, which stamps no header in answer to any status.

```ruby
proxy = WireServer.start(Scripts.fixed("via the proxy"))
Dexpace.configure { |b| b.override(Dexpace::Configuration::Keys::HTTP_PROXY, "http://127.0.0.1:#{proxy.port}") }
adapter.call(req("http://192.0.2.1/v1/pets?limit=2"), EMPTY, nil).body_string   # => "via the proxy"
proxy.requests.first.request_line                            # => "GET http://192.0.2.1/v1/pets?limit=2 HTTP/1.1"
Dexpace.reset_config!
```

## What is deliberately not here

No redirect following, no retry and no authentication live in this gem: those are phase 6's pillar
steps, and `Pipeline.standard(adapter)` is how a caller gets all three around this transport
(`docs/sdk-documentation/pipelines.md`). No connection pool and no keep-alive on the owning construction,
for the reason above. No transport-milestone tracing (`OBS-28`): the adapter takes a `logger:` and no
tracer, because no route exists from a three-argument seam to a per-operation `HTTPTracer` (the design's
R6, P8-7, on phase 10's inbound list). No zero-copy file upload: `Net::HTTP` writes a body stream into a
`Net::BufferedIO`, not an `::IO`, so `TRANSPORT-28`'s zero-copy clause is declined for v1 while its
replayability and byte-window clauses hold through phase 3b's `FileBody`. And nothing async: this is the
synchronous seam; `Transport.async_over(adapter, executor:)` over a real socket is phase 8b's, and the
HTTP/2-capable `dexpace-transport-async_http` is phase 8c's.
