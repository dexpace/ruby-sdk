# transport-adapter — notes

Hand-written. `../harvested/transport-adapter.md` is what the documents say; this file is what the
implementation found, and it wins. Each entry names the harvested entry it answers by that entry's
stable key.

## Superseded
- **`Net::HTTP` has a built-in automatic retry, it is ON by default, and a cancellation delivered by
  closing the socket is swallowed by it.** Supersedes `transport-adapter/7e8e2c60` ("TRANSPORT-1 and
  TRANSPORT-2 … are vacuous for the net_http reference adapter because Net::HTTP follows no redirects
  and retries nothing on its own"), whose **redirect half is right** — verified,
  `(Net::HTTP.instance_methods + Net::HTTP.methods).grep(/redirect|follow/i)` is `[]` — and whose
  **retry half is false**. Verified on `net-http` 0.6.0 under Ruby 3.4.10:
  `Net::HTTP.new("x").max_retries` is **1**, and `#transport_request` retries when
  `count < max_retries && IDEMPOTENT_METHODS_.include?(req.method)` on `Net::ReadTimeout`, `IOError`,
  `EOFError`, `Errno::ECONNRESET`, `Errno::ECONNABORTED`, `Errno::EPIPE`, `Errno::ETIMEDOUT`,
  `OpenSSL::SSL::SSLError` and `Timeout::Error`, where `IDEMPOTENT_METHODS_` is
  `["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE"]` — PUT and DELETE included, and the retry
  re-runs `req.exec`, so it re-writes the body. **Measured end to end rather than read out of a rescue
  list**: against a server whose first connection hangs, with a second thread calling `conn.finish`
  250 ms in, the call **returned `200`** at the default `max_retries` and raised `IOError: stream
  closed in another thread` at `0`. So `TRANSPORT-2` is load-bearing, `TRANSPORT-17`'s single-use body
  could be written twice, and `TRANSPORT-3`'s cancellation is silently swallowed — three requirements
  fixed by one line, `http.max_retries = 0`. Two clauses of the same method bound the hazard without
  removing it: `rescue Net::OpenTimeout; raise` means a connect timeout is never retried, and
  `count = max_retries` inside the `reading_body` block means the window closes once the response head
  is read; neither helps the connect-and-head phase, which is where a cancel lands. Phase 10's inbound
  list carries the same finding against design §3.2, §11.18 and §12, which are frozen.
  <sub>review · `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md` · high · sha:manual-phase8a-net-http-retry</sub>
- **The block-scoped `read_body` construction buffers the whole body, and the coroutine that fixes it
  must be a `Thread` rather than a `Fiber` — because a fiber cannot be resumed from another thread.**
  Supersedes `transport-adapter/d16c7444` ("dexpace-transport-net_http issues the request inside
  Net::HTTP#request(req) { |res| ... } and exposes the response body as a BufferedSource over the
  block-scoped Net::HTTPResponse#read_body stream, satisfying SEAM-11's no-pre-buffering clause and
  TRANSPORT-25's lazy-read, cascading-close requirements"). Verified on `net-http` 0.6.0 under Ruby
  3.4.10 against a `TCPServer` that writes five body bytes, sleeps 400 ms and writes five more.
  `Net::HTTPResponse#reading_body` is `begin; yield; self.body; ensure; @socket = nil; end`, so the
  block form **buffers the whole body** unless the block itself reads, and a later `read_body` raises
  `IOError: Net::HTTPOK#read_body called twice`; `#request` with no block buffered too, returning after
  408 ms. Keeping the block open across the return of `#call` needs a coroutine, and **the fiber is
  disqualified by something other than the leak**: `Fiber#resume` from a second thread raises
  `FiberError: fiber called across threads`, so a fiber pump created on a `dexpace-async-thread` worker
  inside `Transport.async_over` cannot have its body read on the caller's thread, and `TRANSPORT-29`'s
  "confined to the returned response graph" would narrow to "confined to one thread". (An abandoned
  fiber's `ensure` also never runs, verified after three `GC.start`s; `Fiber#kill` does run it on
  3.4.10 and its availability on the 3.2 floor is unverified. Neither fact is what decides it.) What
  the SDK does instead, per phase 8a's `P8-1`: a per-response producer `Thread` over a
  `Thread::SizedQueue(1)`, drained through a `#readpartial`-shaped reader that
  `Dexpace::IO::BufferedSource.wrapping` owns; `#close` latches, closes the queue (waking a producer
  blocked on push), closes the connection (waking one blocked on a socket read with `IOError`, which
  requires `max_retries = 0` per this file's first entry) and joins with a **bounded** deadline.
  Measured: head at 4 ms against a 400 ms dribble, 4 MiB round-tripped byte-exactly in 95 ms, close
  mid-stream returning in 1 ms with the server observing the peer close, idempotent, no stranded
  thread. Phase 10's inbound list carries the same finding against design §3.2, which is frozen.
  <sub>review · `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md` · high · sha:manual-phase8a-response-pump</sub>

## Reference
- **A body-bearing `Net::HTTP` request with no `Content-Type` emits a `Warning.warn` under `-w`, and
  every body-permitted method has a body whether the caller gave one or not.** Beside
  `transport-adapter/0921e946`, which states `TRANSPORT-10`'s authority rule and says nothing about
  what the library does when nobody set a type. Verified on `net-http` 0.6.0 under Ruby 3.4.10:
  `Net::HTTPGenericRequest#supply_default_content_type` is
  `warn 'net/http: Content-Type did not set; using application/x-www-form-urlencoded', uplevel: 1 if
  $VERBOSE`, called by **both** `send_request_with_body` and `send_request_with_body_stream`; and
  `#set_body_internal` is `self.body = '' if @body.nil? && @body_stream.nil? && @body_data.nil? &&
  request_body_permitted?`, so a **body-less `POST`** takes the same path and reaches the wire with
  `Content-Length: 0` and a stamped `Content-Type`. With `Warning.warn` overridden to raise — which is
  exactly what phase 0's shared test case does — the call raised under `ruby -w` and did not without
  it. This repository's gate set fails the build on warnings, so the first `POST` in any suite is a red
  build unless the adapter sets the header. Phase 8a therefore sets an explicit `Content-Type` on every
  body-permitted method, defaulting to `application/octet-stream` (`P8-4`) — RFC 9110's own default for
  a payload of unknown type, and the one value that is not a claim about the bytes, where the library's
  `application/x-www-form-urlencoded` is a claim a server will act on. Suppressing the warning
  process-globally was rejected for the reason the port refuses `Regexp.timeout`: a library must not
  mutate a host global.
  <sub>review · `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md` · high · sha:manual-phase8a-content-type-warning</sub>
- **`net-http` 0.9.x, Ruby 4.0's, differs from the 0.4.x and 0.6.x the other supported Rubies ship in two
  places the adapter meets, and neither changes what the adapter does.** Beside `transport-adapter/0921e946`
  and this file's content-type entry above, whose measurements were taken on 0.6.0; verified on 2026-09-20 on
  0.4.1 (3.2.11 and 3.3.12), 0.6.0 (3.4.10) and 0.9.1 (4.0.6, where net-http is no longer a default gem).
  **One**: `Net::HTTPGenericRequest#supply_default_content_type` is gone from 0.9.1 — a body-bearing request
  with no `Content-Type` emits no warning under `-w` and reaches the wire with no `Content-Type` at all,
  while `#set_body_internal` still gives a body-less `POST` `body = ''` and `Content-Length: 0` on every
  version. So `P8-4`'s first reason (the warnings-fatal build) holds on three of the four rows and its
  second (a form type as a claim about the bytes) on the same three; `TRANSPORT-10`'s own rule holds on
  all four, and the adapter's stamp is identical on all four — which is why its `-w` `POST` test reads the
  wire's `Content-Type` line rather than only the absence of a warning. **Two**: `Net::HTTP#connect` is
  `Timeout.timeout(@open_timeout, Net::OpenTimeout) { TCPSocket.open(...) }` on 0.4.1 and 0.6.0 and
  `TCPSocket.open(..., open_timeout: @open_timeout)` on 0.9.1, and the first `Timeout.timeout` in a process
  starts Ruby's process-wide singleton timeout thread, which lives for the rest of the process. A suite
  that counts threads around every test — phase 0's `DexpaceTestCase` does — charges that thread to the
  first test that connects on a 3.2, 3.3 or 3.4 row and to no test on a 4.0 row; phase 8a parks it by
  opening one connection at test-helper load (`test/support/net_http_warmup.rb`), which is a test-support
  arrangement and not the SDK calling the primitive §8.3 bans. Two facts that did **not** move across the
  three versions and are worth stating because the design measured them once: `max_retries` defaults to 1
  with `PUT` and `DELETE` in the retried set, `#read_timeout=` reaches a live socket, `#[]=` on
  `Accept-Encoding` flips `decode_content` off and `#add_field` does not, a caller `Host` is honoured
  verbatim, `#to_hash` preserves bytes and multiplicity, and `send_request_with_body_stream` copies into a
  `Net::BufferedIO` on every one. The gemspec therefore pins `net-http >= 0.4` with no upper bound
  (phase 8a's `P8-60`), and `gems/dexpace-transport-net_http/test/dexpace/transport/net_http/matrix_facts_test.rb`
  prints the active version per row and asserts the two version-bound facts as the disjunction the adapter
  is correct under. Cites `TRANSPORT-10`, `TRANSPORT-26`, `TRANSPORT-2`, `NFR-2`, `NFR-6`.
  <sub>review · `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-checklist.md` · high · sha:manual-phase8a-net-http-0-9</sub>
- **`TRANSPORT-12`'s "stricter wire grammar" is per-protocol, not per-adapter, and on the looser protocol
  wire-boundary re-validation (phase 8a Task 16, phase 8c Task 9) is the only defence.** Annotates
  `transport-adapter/cb7901ef`. Verified 2026-09-11 on
  `protocol-http1` 0.41.0 and `protocol-http2` 0.28.0 under Ruby 3.4.10, against an in-process
  `async-http` server driven over both protocols. On HTTP/1.1, `Protocol::HTTP1::Connection#write_headers`
  checks `VALID_FIELD_NAME` (the RFC 7230 token set) and `VALID_FIELD_VALUE` (`[^\0\r\n]+`) and raises
  `Protocol::HTTP1::BadHeader`, rewrapped as `Protocol::HTTP::RefusedError` with the original as `#cause`
  — but only **after** the request line and `host:` are already on the socket, so
  `TRANSPORT-12`'s "the rest of the headers and the body MUST still be dispatched" is unreachable by
  rescuing and the drop must be a pre-dispatch predicate. On HTTP/2 the client validates **nothing**: a
  name `"Bad Name"` was transmitted (lowercased to `"bad name"`) and a value `"a\r\nEvil: 1"` was
  transmitted **verbatim**, both reaching the peer. So one adapter has `TRANSPORT-12`'s antecedent on one
  protocol and no validation at all on the other, and that wire-boundary re-validation is, on the
  HTTP/2 path, the only thing between a forged `Dexpace::Request` and an injected header — a stronger
  statement than design §10.10's "a correctness-of-shape gap, not a request-splitting gap". The port's
  answer is to apply the RFC 7230 token predicate before dispatch on **both** protocols, so one request
  produces one observable header set (`P8-40`).
  <sub>review · `docs/work/mvp/phase8/phase8c/2026-09-11-phase8c-asynchronous-transport-design.md` · high · sha:manual-phase8c-http2-no-validation</sub>
- **`dexpace-transport-net_http` opens a TCP — and, over HTTPS, a TLS — connection per request, which is
  what the design requires and what the corpus rule forbids.** Beside `resource-management/4aca52f9`
  ("Never open one connection per request; size connection or HTTP pools with a bounded, named constant
  instead"), which is a good rule for an application and is not the rule this gem follows. Design §3.2
  with `transport-adapter/52b448e8` requires the opposite for a measured reason: a **shared** `Net::HTTP`
  driven by eight threads produced 128 errors and **26 responses matched to the wrong request** (8a's
  verified fact 9) — `Net::HTTP` holds one socket and one response state per instance, so sharing one is
  not slow, it is wrong. The cost of the design is real and is not hidden: every request pays a
  handshake, which on an HTTPS endpoint is one round trip plus a TLS negotiation. **Why a pool is not the
  answer inside this gem.** `connection_pool` would be a second third-party declaration and
  `gates:gemspec_audit` rejects it — `NFR-2` budgets an adapter at `dexpace-core` plus at most one
  library, and `net-http` is that one. A hand-rolled pool would have to answer every bounded-pool and
  deterministic-teardown rule the corpus routes to `dexpace-async-thread`
  (`concurrency-and-async/6764e0b5`, `dc345cae`, `df658d73`, `3692970f`, `047644ea`, `dd8e6d2d`), in a gem
  that is not that one and whose `XCUT-11` surface would grow accordingly. What would resolve it: a later
  phase taking a hand-rolled bounded pool with a checkout timeout as a **deliberate, separately-designed**
  piece of work — not as a line added to the send path. Recorded here rather than left implicit because
  the first user to benchmark this SDK against `faraday` will find the handshake and should find it
  already written down. Cites `TRANSPORT-5`, `TRANSPORT-29`, `SEAM-12`, `NFR-2`, `XCUT-11`.
  <sub>review · `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md` · high · sha:manual-phase8a-connection-per-request</sub>
