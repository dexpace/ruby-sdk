# The conformance suite: `dexpace-conformance`

**As built by phase 8a, written against source on 2026-09-20; the counts, the preamble and the two
groups phase 8c appended re-run against source on 2026-09-21.** This page says what the conformance gem
gives a transport-adapter author today: the assertion protocol phase 0 postponed — `Failure`, `Vacuous`,
`Assertion`, `Result` and `Report` — the thirty-four-assertion `TransportSuite` every adapter is proven
against, the `TransportCase` an assertion receives and the eleven-clause contract that keeps the suite
free of any adapter's name, the plaintext `WireServer` fixture and its fifteen `Scripts`, the two thin
drivers for Minitest and RSpec, and the two observability doubles phases 5b and 5c assigned here,
`RecordingSpan` and `Allocations`. What the suite is *required* to prove is
`docs/product-spec/17-transport-adapter-conformance-contract.md` and appendix B's `B.5`; how the design
maps it to Ruby is `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md` §9.3; the per-requirement
proof is `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-checklist.md`.
Signatures live in `gems/dexpace-conformance/sig/`, and this page does not restate them. Every example
below was run against the built code on 4.0.6 and 3.2.11 and printed the same on both (the one
difference is Ruby 3.4's `Hash#inspect` spelling, so the examples print arrays and strings), and the
ones whose printed values phase 8c's groups changed were re-run on 4.0.6 and 3.3.12. The
examples drive the suite against the reference adapter, `Dexpace::Transport::NetHTTP`, because a
conformance page's examples should run the real thing; `C` is `Dexpace::Conformance` and `NetHTTP` is
`Dexpace::Transport::NetHTTP` throughout.

**The gem declares `dexpace-core` and nothing else** (`NFR-2`), and that is load-bearing: neither
driver requires its framework — `skip` and `flunk` are sent to the test instance the consumer's class
already is, and `::RSpec` is resolved by name at call time — so Minitest, a bundled gem from Ruby 3.4
(`docs/knowledge/notes/tooling-and-quality-gates.md`), is never a runtime constraint on a consumer.
`socket` and `tempfile` are stdlib that stays stdlib, and the require allowlist admits `socket` to this
gem alone.

## What a green run proves, and what it does not

Read this before the numbers. The suite is **thirty-four assertions over thirty-two requirement IDs**:
twenty-eight `TRANSPORT` IDs, `HTTP-17` and `HTTP-18` with `XCUT-18` (the wire-boundary re-validation), and
`PAGE-36` (a closed transport is a `ClosedError`, never a hang). It is deliberately **not** all thirty
`TRANSPORT` IDs, and the two it does not carry — and the three things it cannot prove — are stated
rather than left to be discovered:

- **`TRANSPORT-8`** has no assertion: its antecedent is a cancellation the *native client* originates
  while the SDK future is live, which only an adapter's own suite can raise by naming its runtime — a
  parent `Async` task cancelled, for `dexpace-transport-async_http` — so it is that gem's row, proven
  in its own suite, and `PREAMBLE` names it as the third thing a green run does not prove.
- **`TRANSPORT-30`**, the proxy limitation, is the reference adapter's own and lives in
  `gems/dexpace-transport-net_http/test/`, because the fixture reads no configuration and is no proxy.
- **`TRANSPORT-4`'s connect-timeout half and TLS verification** are the two things `PREAMBLE` has
  named at the head of every report since 8a (P8-9): the fixture accepts every connection at once, so the
  open timeout is never exercised, and it has no certificate. An adapter that passes this suite has
  proven neither, and a third-party author who reads the report is told so.
- **`TRANSPORT-12` and `TRANSPORT-13`** resolve **vacuous by measurement** on an adapter whose native
  client accepts every model-valid header name — the bad name is sent and the wire is read, which is
  what `net-http` does — and are real on one whose wire grammar is stricter than the SDK model's, which
  is `async-http`'s (P8-55 is why they could not be a shared assertion declaring itself vacuous).
- **`TRANSPORT-14`'s malformed-inbound-name clause and `TRANSPORT-27`'s invalid-`Content-Length`
  clause** are **waived by id** in `dexpace-transport-async_http`'s driver and by nothing in
  `dexpace-transport-net_http`'s: `protocol-http1` refuses both heads out of the read before a response
  exists to adapt (P8-38), `Net::HTTP` delivers both. A waiver is reported on every run, and the two
  assertions under `TRANSPORT-14` are both skipped by the one id.

```ruby
require "dexpace/conformance"

C::TransportSuite.assertions.size                            # => 34
C::TransportSuite.assertions.flat_map(&:ids).uniq.size       # => 32
C::TransportSuite.assertions.flat_map(&:ids).grep(/TRANSPORT/).uniq.size   # => 28
C::TransportSuite.assertions.first(3).map(&:name)
# => ["the caller's explicit Content-Type wins over the body's",
#     "a body-derived Content-Type is used only when the caller set none",
#     "no explicit header and no body media type is never a form type"]
C::TransportSuite.assertions.last(6).map(&:ids)
# => [["TRANSPORT-7"], ["TRANSPORT-9"], ["TRANSPORT-21"], ["TRANSPORT-23"], ["TRANSPORT-12"], ["TRANSPORT-13"]]
puts C::TransportSuite::PREAMBLE
# dexpace-conformance transport suite: the wire fixture speaks plaintext only and exercises no
# connect timeout, so TLS verification and TRANSPORT-4's open-timeout classification are NOT among
# the things a green run proves (P8-9); assert both in the adapter's own suite. Nor is TRANSPORT-8:
# a cancellation the native client originates while the SDK future is live can only be raised by
# naming the adapter's own runtime, so that pair -- terminal on the cancellation, retryable on a
# timeout of the same path -- is the adapter's own suite's too.
```

The thirty-four are seven groups in the order a reader meets chapter 17: **outbound** (seven —
`TRANSPORT-10`'s `Content-Type` precedence, `TRANSPORT-26`'s body-less `POST`, `TRANSPORT-11`'s managed
headers, the two forged-header refusals), **inbound** (four — `TRANSPORT-24`'s vendor status,
`TRANSPORT-14`'s malformed header drop, `TRANSPORT-27`'s malformed `Content-Length`), **streaming** (three
— `TRANSPORT-25`'s large body, `TRANSPORT-19`'s prompt release, `TRANSPORT-28`'s file window),
**resilience** (eight — `TRANSPORT-1` through `-4`, `-17`, `-18`, `-20`, `-22`), **lifecycle** (six —
`TRANSPORT-5`'s budget, `TRANSPORT-6`'s clamp, `TRANSPORT-15`/`-16`'s close, `TRANSPORT-29`, `PAGE-36`),
and phase 8c's two — **asynchronous** (four — `TRANSPORT-7`'s mid-body cancel through the token with
the connection released, `TRANSPORT-9`'s response arriving after the cancel and never delivered,
`TRANSPORT-21`'s adaptation failure classified through the send primitive's failure channel,
`TRANSPORT-23`'s success always a `Dexpace::Response`) and **header drops** (two — `TRANSPORT-12`'s
model-valid non-token name dropped with the rest dispatched, `TRANSPORT-13`'s once-per-name, bounded
drop reporting read off the transport's own `logger:`). Every one of the six is written against the
suite contract's primitives — `kase.settle`, `kase.wire`, `kase.transport(logger:)` and
`Dexpace::Cancellation` — and names no reactor, no task and no native class, which is what lets 8a's
synchronous driver run them unchanged.

## Running it, and reading a report

`TransportSuite.run(build:, borrow:, waive:, around:, settle:, wire:, assertions:)` runs every assertion
in a **fresh** `TransportCase`, maps its raise onto one of `Result::STATUSES` — a `Vacuous` to
`:vacuous`, a `Failure` to `:failed`, anything else to `:error` and never silently a failure — tears the
case down in an `ensure` whatever happened, and answers a `Report`. `build:` is a keyword-taking factory
for the SDK-managed transport (the suite passes at most `timeout:` and `logger:`); `borrow:` takes the
fixture's **port** and answers a `BorrowedPair` of the borrowing transport and a "still usable?" probe,
or is nil for an adapter with no borrowing construction, whose `TRANSPORT-15` borrowed half is then
vacuous rather than failed.

```ruby
borrow = lambda do |port|
  client = Net::HTTP.new("127.0.0.1", port)
  client.max_retries = 0
  C::BorrowedPair.build(
    transport: NetHTTP.using(client),
    probe: -> { client.start { |c| c.request(Net::HTTP::Get.new("/")) }.code == "200" },
  )
end
report = C::TransportSuite.run(build: ->(**settings) { NetHTTP.build(**settings) }, borrow: borrow)
report.passed?                                               # => true
report.results.map(&:status).tally.to_a                      # => [[:passed, 31], [:vacuous, 3]]
report.vacuous.map { |r| r.assertion.ids }                   # => [["TRANSPORT-18"], ["TRANSPORT-12"], ["TRANSPORT-13"]]
puts report
# dexpace-conformance transport suite: the wire fixture speaks plaintext only and exercises no
# connect timeout, so TLS verification and TRANSPORT-4's open-timeout classification are NOT among
# the things a green run proves (P8-9); assert both in the adapter's own suite. Nor is TRANSPORT-8:
# a cancellation the native client originates while the SDK future is live can only be raised by
# naming the adapter's own runtime, so that pair -- terminal on the cancellation, retryable on a
# timeout of the same path -- is the adapter's own suite's too.
# 31 passed, 0 failed, 3 vacuous, 0 waived, 0 errored
#   vacuous: TRANSPORT-18: the native client opened one connection and pulled the single-use body
#   once across a dropped first attempt, so no re-subscribable producer is in play on this adapter
#   (TRANSPORT-18's antecedent is absent)
#   vacuous: TRANSPORT-12: the native client accepted the model-valid name X-Bad:Name and sent it, so
#   it rejects no header the SDK model admits (TRANSPORT-12's antecedent is absent)
#   vacuous: TRANSPORT-13: the native client accepted the model-valid names and sent them, so there
#   is no drop to log (TRANSPORT-13's antecedent is absent)
```

**Vacuous is a status, not a pass.** `TRANSPORT-18` says a native retry must not re-subscribe a
single-use body; the assertion drops the first connection and counts connections and body pulls, and
when it measures one of each — the only outcome `max_retries = 0` admits — the requirement's antecedent
is absent and the assertion says so rather than claiming a proof (P8-55). A `Report#passed?` is true with
vacuous rows and false with a failed or an errored one; the summary line prints all five counts on every
run, so a gap is never a silent zero. **A waiver is the same idea, declared**: `waive: ["TRANSPORT-28"]`
records that assertion `:waived` without running it, and the report names the id and the assertion on
every run — design §9.3's "the gap stays visible", for a port that has consciously not built something.

```ruby
waived = C::TransportSuite.run(build: ->(**s) { NetHTTP.build(**s) }, borrow: borrow, waive: ["TRANSPORT-28"])
waived.waived.map { |r| r.assertion.ids }                    # => [["TRANSPORT-28"]]
waived.to_s.lines.grep(/waived/)
# => ["30 passed, 0 failed, 3 vacuous, 1 waived, 0 errored\n",
#     "  waived: TRANSPORT-28 (a file body with a non-zero position and partial count sends exactly that range)\n"]
```

A failure names the requirement and carries what was expected and what was seen. Against a wrapper whose
`#close` is a no-op — a `TRANSPORT-15` violation by construction — the suite reports it and nothing else,
because every assertion runs in its own case and a failed one cannot poison the next:

```ruby
never_closes = Class.new do
  def initialize(inner) = @inner = inner
  def call(request, options, cancellation) = @inner.call(request, options, cancellation)
  def close = nil
  def closed? = false
  def owned? = true
end
report = C::TransportSuite.run(
  build: ->(**s) { never_closes.new(NetHTTP.build(**s)) },
  assertions: C::TransportSuite.assertions.select { |a| a.ids == ["TRANSPORT-15", "TRANSPORT-16"] },
)
report.passed?                                               # => false
report.failures.first.assertion.ids                          # => ["TRANSPORT-15", "TRANSPORT-16"]
report.failures.first.detail                                 # => "a send after close on an owning transport did not raise ClosedError"
```

## The two drivers

`MinitestDriver` is `extend`ed into a test class; `conformance(suite, build:, borrow:, waive:, settle:,
around:, wire:)` defines **one test method per assertion**, named `test_` plus the assertion's name with
every non-word run collapsed to an underscore, so a `-n` filter selects exactly the code path a full run
does — each generated test builds its own fresh case and runs its own assertion, never a replay of a
cached result. A `Vacuous` is a `skip` naming the reason, a `Failure` a `flunk` naming the ids, a waived
id a `skip` naming it, and anything else propagates as an error. Inherit the repository's own base class
where there is one: the first-party driver inherits `DexpaceTestCase`, whose teardown counts threads, so
a fixture thread an assertion leaked fails the test that leaked it. This is exactly the shape of
`gems/dexpace-transport-net_http/test/dexpace/transport/net_http/conformance_test.rb`, and a
third-party adapter's suite is the same file with its own two lambdas:

```ruby
class MyAdapterConformanceTest < Minitest::Test
  extend Dexpace::Conformance::MinitestDriver

  conformance(
    Dexpace::Conformance::TransportSuite,
    build: ->(**settings) { MyAdapter.build(**settings) },
    borrow: ->(port) { Dexpace::Conformance::BorrowedPair.build(transport: ..., probe: -> { ... }) },
    waive: [],
  )
end
# => 28 test methods; against NetHTTP: 27 pass, 1 skip ("vacuous: the native client opened one connection …")
```

`RSpecDriver` is the same in RSpec's vocabulary — one example group per assertion with one example each,
a waiver and a `Vacuous` as `skip`, a `Failure` as the example's failure — and it is **not** required by
`dexpace/conformance`: an RSpec-only consumer writes `require "dexpace/conformance/rspec_driver"` and
calls `Dexpace::Conformance::RSpecDriver.conformance(...)`, so a Minitest-only consumer never loads a
file that names the other framework. Neither driver names its framework in a signature (`NFR-11`).

The three keywords a synchronous adapter never passes are the **suite contract** for an asynchronous
one, and the reason the same thirty-four assertions run unchanged against 8c's adapter: `settle:`
(clause 8) is the one send primitive, `(transport, request, options, cancellation) -> Response`, which an
async driver replaces with "call, then await the future"; `around:` (clause 9) wraps each assertion's
whole invocation, which is where an async driver opens the reactor the body reads a streamed response
inside; and `wire:` (clause 11) is the fixture factory, whatever answers `_Wire` — `#port`, `#requests`,
`#connections`, `#closed_connections`, `#await_closed_connection`, `#close` — so an HTTP/2 server can
stand in for `WireServer` without this gem naming an async constant. `dexpace-transport-async_http`'s
driver is the second one built to it (`gems/dexpace-transport-async_http/test/dexpace/transport/async_http/conformance_test.rb`):
`settle:` awaits the future inside `around:`'s reactor — which runs the assertion as a child task and
bounds the parent's wait at thirty seconds, cancelling the child and flunking the row on expiry, so an
adapter that never releases what it holds fails the run instead of hanging it — and on a thread of
an assertion's own —
`TRANSPORT-5`'s pair and `TRANSPORT-29`'s eight — opens a reactor per settle and reads the body inside
it before handing the response out, because under `async-http` a response cannot outlive the reactor
that produced it (`docs/sdk-documentation/transport-async_http.md`). Its run is four skips — the three
waived assertions and `TRANSPORT-18` — and every other assertion green.

## The case an assertion receives

A `TransportCase` is what an assertion body is handed and the whole of what it may touch:
`#transport(timeout:, logger:)` builds a fresh SDK-managed transport through the driver's factory,
passing only the settings given; `#borrowed_transport` asks the borrow factory for a pair bound to the
live fixture's port; `#wire(script:)` starts the fixture on its first call and answers it thereafter;
`#request(path:, method:, headers:, body:)` builds a `Dexpace::Request` against the fixture's own port;
`#settle(transport, request, options, cancellation)` is the **one** way to send; and `#teardown` closes
every transport the case built and then the fixture, quietly, called by the runner in an `ensure` and
never by the assertion. What `#transport` returns is guarded: **it cannot be `#call`ed.** The default
`settle` *is* `transport.call`, so an assertion that called `#call` directly would pass every synchronous
run and fail only when an async driver replaced `settle:`; the guard makes that a red test today instead.

```ruby
body = lambda do |kase|
  kase.wire(script: C::Scripts.fixed("ok"))
  response = kase.settle(kase.transport, kase.request)
  unless response.status.code == 200
    raise C::Failure.new("not a 200", expected: 200, actual: response.status.code, requirement_ids: ["EXAMPLE-1"])
  end
  response.close
end
assertion = C::Assertion.build(ids: ["EXAMPLE-1"], name: "answers 200 on /", body: body)
kase = C::TransportCase.new(build: ->(**s) { NetHTTP.build(**s) })
assertion.call(kase)                                         # => nil   (no raise: passed)
kase.teardown                                                # => nil
kase.transport.call(:request, :options, :cancellation)
# => ArgumentError: a conformance assertion must send through kase.settle(transport, request, options, cancellation), never …
C::Result::STATUSES                                          # => [:passed, :failed, :vacuous, :waived, :error]
```

An `Assertion` is `ids`, `name` and a body; `Failure.new(message, expected:, actual:, requirement_ids:)`
is what a body raises when the adapter is wrong, `Vacuous.new(reason)` when the requirement's antecedent
turned out to be absent, and anything else is an error in the assertion or the fixture and is reported as
one. `Assertion.build` is how phase 9 will add its own suites beside this one, through the same runner
and the same drivers.

## The fixture: `WireServer` and `Scripts`

`WireServer.start(script)` is a real `TCPServer` on `127.0.0.1` and an ephemeral port, accepting on one
thread and handling each connection on another, recording every request it parses as a
`RecordedRequest` — `#head` (the raw lines, CRLF intact), `#request_line`, `#path`, `#header(name)` and
`#body` — and counting connections opened and closed. The script decides the reply: a callable taking
the accepted socket and the parsed head, and `Scripts` ships fifteen named ones — `fixed(body, status:,
headers:, hold:)`, `large(byte_count, hold:)`, `dribble(first, second, delay_seconds)` (chunked, with a
gap), `redirect(to)`, `vendor_status(code, body)`, `malformed_headers`, `malformed_content_length`,
`hang_before_headers` and `hang_after_headers` (each with a hook the assertion fires a cancel from),
`fail_first_connection_then_succeed(body)`, `truncated(declared_length:, actual_body:)`,
`sequenced(*bodies)` (one reply per request over a kept-alive connection), `echo_path`, and the
`write_response` and `large_body` helpers a custom script builds on. `hold: true` keeps the connection
open until the **peer** closes it, which is what makes "the server observed the release" observable:
`#await_closed_connection(count = 1, timeout:)` waits — bounded — for that many closes and answers the
count or nil, so a release assertion against an adapter that never releases fails instead of hanging
(P8-56). The fixture speaks plaintext HTTP/1.1 only, by design; it has no certificate and exercises no
connect timeout, which is `PREAMBLE`'s whole point.

```ruby
server = C::WireServer.start(C::Scripts.dribble("ab", "cd", 0.1))
server.port.positive?                                        # => true
client = Net::HTTP.new("127.0.0.1", server.port)
client.max_retries = 0
res = client.start { |c| c.request(Net::HTTP::Get.new("/x?y=1")) }
[res.code, res.body, res["Transfer-Encoding"]]               # => ["200", "abcd", "chunked"]
server.requests.first.request_line                           # => "GET /x?y=1 HTTP/1.1"
server.requests.first.header("host").start_with?("127.0.0.1:")   # => true
[server.connections, server.await_closed_connection(timeout: 2)] # => [1, 1]
server.close                                                 # => nil   (idempotent; joins its threads with a bound)
```

The fixture is also the reason `WireServer::JOIN_DEADLINE_SECONDS` exists: `#close` closes the listener
and every accepted socket and joins the handler threads with a bound, so a script blocked in a read the
peer never finishes cannot hang a suite's teardown.

## The two doubles

`RecordingSpan` is `OBS-21`'s test double over phase 5c's `_Span` protocol: a span that records what a
tracer would have received — `attributes`, `events` as `{name:, attributes:}` hashes, `errors`,
`status` and `finished_at` — and answers `recording?` false once finished. `Allocations.delta(iterations:)
{ … }` is `OBS-25`'s per-call allocation measurement — a warm-up, then a measured loop repeated until
two consecutive figures agree (at most `ATTEMPTS`) — answering a `Float` of allocations per iteration,
which is how "selecting a no-op path MUST NOT allocate per call" is
asserted as exactly `0.0` rather than "small". Both are here and not in core because a double is not
domain code, and both are what phase 9's observability suites will build on.

```ruby
span = C::RecordingSpan.new
span.set_attribute("http.request.method", "GET")
span.add_event("first_byte")
span.finish
span.attributes.to_a                                         # => [["http.request.method", "GET"]]
span.events.map { |e| e[:name] }                             # => ["first_byte"]
span.recording?                                              # => false

frozen = "constant".freeze
C::Allocations.delta(iterations: 1_000) { frozen.frozen? }   # => 0.0
C::Allocations.delta(iterations: 1_000) { String.new }       # => 1.0
```

## What is deliberately not here

No assertion names an adapter: the suite reaches every transport through the driver's two lambdas, and
`Net::HTTP` appears under `gems/dexpace-conformance/lib/` only in comments explaining a measurement. No
TLS, no proxy and no connect-timeout assertion, for the reasons the preamble states. No `RSpec` or
`Minitest` in a `require`, a gemspec or a signature. No `Timeout.timeout`, `Thread#raise` or
`Thread#kill`, in the fixture included: every wait is a bounded queue pop or a bounded join. And no suite
beyond the transport one yet: the remaining appendix-B suites, and the drivers' second consumer, are
phase 9's; this gem's gemspec, version and first release are phase 8's.
