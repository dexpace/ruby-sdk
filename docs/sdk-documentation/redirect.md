# Redirect

**As built by phase 6b, in `dexpace-core`, written against source on 2026-09-19.** This page says what
chapter 10 gives an SDK author today: one synchronous redirect pillar step at `Stages::REDIRECT`, the
read-only snapshot a caller's redirect predicate receives, the layer's event and key vocabulary, the two
errors a followed redirect can raise, the second predicate on phase 6a's re-sendability module, and — the
phase-level work phase 4c postponed — the two `standard` constructors, `Pipeline.standard` and
`AsyncPipeline.standard`. What each is *required* to do is `docs/product-spec/10-redirect-handling.md`
(`REDIR-1`–`REDIR-28`) and, for the constructors, appendix C's `PIPE-24`, `PIPE-32` and `PIPE-39`; how the
design maps it to Ruby is `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md` §6.2 and
`docs/sdk-design-ruby/05-pipeline-architecture.md` §5.3, read together with entry 15 of
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`; the per-requirement proof
is `docs/work/mvp/phase6/phase6b/2026-09-09-phase6b-redirect-checklist.md`. Signatures live in
`gems/dexpace-core/sig/dexpace/redirect/`, and this page does not restate them. Every example below was
run against the built code on 4.0.6 and 3.2.11 and printed the same on both (the one difference is
Ruby 3.4's `Hash#inspect` spelling, so the examples print arrays and strings). The examples use two test
doubles from `gems/dexpace-core/test/support/` — `ScriptedTransport`, whose script is one reply per call,
and `RecordingSink` — because a redirect step re-sends through a transport and logs through a sink, and
neither is something a page example should do for real; `R` is `Dexpace::Redirect` and `STAGES` is
`Dexpace::Pipeline::Stages` throughout, `req(url, method:, headers:, body:)` builds a request,
`response(status, location:)` a response over a closable body whose `#closes` counts, and
`follow(step, *replies, request:)` builds a pipeline with the step at `REDIRECT` over a scripted
transport, drives the request through it, and answers the response and the transport.

**Synchronous only, and the async pipeline says so at the call site.** There is no `Redirect::AsyncStep`
and no redirect following on the async runtime (`REDIR-25`, `PIPE-32`): `AsyncPipeline.standard` takes a
required `redirect: :unsupported` keyword and installs nothing at `REDIRECT`, so the asymmetry with
`Pipeline.standard` is spelled where a reader is looking rather than left as an absence. `REDIRECT`
stays installable on the async path by hand, because the two runtimes share one staging policy
(`PIPE-28`) and the constraint is the preset's, not the runtime's.

## The pillar step: `Step`

`Dexpace::Redirect::Step` is built through `.build`, with `.new` private and the result frozen, and
installed with `builder.append(step)` and no `stage:` because it declares `Stages::REDIRECT` — order 200,
the outermost pillar, so redirect wraps retry wraps auth per hop (`REDIR-24`, `PIPE-2`). Its keywords are
`allowed_methods:` (the methods a 301, 302, 307 or 308 is followed for, judged on the **original**
request's method, default `{GET, HEAD}` — `REDIR-3`, `REDIR-4`), `follow303:` (`REDIR-5`, default
`false`), `max_hops:` (`REDIR-17`, default 3; 0 disables following), `allow_scheme_downgrade:`
(`REDIR-15`, default `false`), `predicate:` (`REDIR-20`, default `nil`) and `logger:` (an
`Instrumentation::Logger`, `Logger::NULL` by default). The allowed set is copied and frozen at build,
so a caller mutating its own collection afterwards changes nothing (`REDIR-26`), and it is deliberately
not `Dexpace::Method::IDEMPOTENT`, whose five members govern retry re-sendability and would silently
widen redirect following to `OPTIONS`, `PUT` and `DELETE`.

```ruby
step = R::Step.build
step.stage.name                                              # => :redirect
step.frozen?                                                 # => true
R::Step::DEFAULT_ALLOWED_METHODS.map(&:token)                # => ["GET", "HEAD"]
R::Step::DEFAULT_MAX_HOPS                                    # => 3
R::Step.build(max_hops: -1)
# => Dexpace::InvalidArgumentError: max_hops must be a non-negative Integer, got -1
```

The step is one iterative loop (`REDIR-23`: 5,000 hops sit at the first hop's stack depth) that forks a
fresh cursor for **every** drive, the first included, and never calls the cursor it was handed — the
fork is where the cross-origin marker is written, so a first drive on the un-forked handle would have no
slot to write (P4-39). Per hop: a response whose status is not 301, 302, 303, 307 or 308 is returned as
it is, open, before anything is allocated (`REDIR-1`, `REDIR-2`, `REDIR-21`'s fast path); otherwise the
`Location` is resolved against the **current** hop through `URI::RFC3986_PARSER.join`, screened,
userinfo-stripped and frozen (`REDIR-12`–`REDIR-14`, `REDIR-18`, `REDIR-19`), the snapshot is allocated
and the decision made, `REDIR-17`'s cap is applied over that answer, the follow-up is built inside a
frame that closes the current response before any raise propagates (`REDIR-22b`), the current response
is closed **before** the next fork goes out (`REDIR-22a`), the hop is recorded, and the loop goes round.

```ruby
res, transport = follow(step, response(302, location: "/y"),
                              response(301, location: "https://api.example/z"),
                              response(200))
res.status.code                                              # => 200
transport.calls.map { |(r, _, _)| r.url.to_s }               # => ["https://api.example/x",
                                                             #     "https://api.example/y",
                                                             #     "https://api.example/z"]
```

## Credential hygiene and the marker

Three rules, and the correctness stake of the whole chapter. `Authorization` is stripped before
**every** re-issue, same-origin and cross-origin alike, the 303 rebuild included — re-attaching a
credential for a known origin is the AUTH step's job (`REDIR-7`). `Cookie` and `Proxy-Authorization` are
stripped on a cross-origin hop and kept on a same-origin one (`REDIR-9`, `REDIR-10`). And "cross-origin"
is judged against the **seed** request's origin — `[scheme, host, effective port]`, the scheme and host
folded, the port the scheme default when omitted — and never against the previous hop, so a same-origin
sub-redirect on a foreign host cannot re-expose the credential (`REDIR-8`).

```ruby
seed = req("https://api.example/x", headers: { "Authorization" => "Bearer t", "Cookie" => "sid=1" })
_, transport = follow(step, response(302, location: "https://api.example/y"),   # same-origin
                            response(302, location: "https://cdn.example/z"),   # cross-origin
                            response(200), request: seed)
transport.calls.map { |(r, _, _)| r.headers.names.sort }     # => [["Authorization", "Cookie"],
                                                             #     ["Cookie"], []]
```

The signal the AUTH step reads to skip stamping on a cross-origin re-issue is **cursor state, never a
request header** (`REDIR-11`; design §10 entry 15): every drive forks with
`state: { cross_origin: true | false }` into the REDIRECT pillar's own slot — `false` on the seed's own
drive and every same-origin hop, `true` on every cross-origin hop, never omitted — and only that pillar's
fork can write the slot `cursor.state(Stages::REDIRECT)` reads. A server-supplied `Location` has no path
to cursor state, so forgery is structurally impossible rather than defended against; a forged
`X-Dexpace-Cross-Origin` request header changes nothing; and since nothing is added to the request,
nothing needs removing before dispatch. Phase 6c's `Auth::Step` reads exactly this key.

```ruby
reads = []
reader = ->(request, cursor) { reads << cursor.state(STAGES::REDIRECT)[:cross_origin]; cursor.call(request) }
follow(step, response(302, location: "https://api.example/y"),
             response(302, location: "https://cdn.example/z"),
             response(200), downstream: [[reader, STAGES::AUTH]])
reads                                                        # => [false, false, true]
```

The end-to-end proof — a real `KeyStamper` on the real `Auth::Step` behind the real redirect step, and
no `Authorization` reaching the foreign origin while the seed hop was stamped — is
`gems/dexpace-core/test/dexpace/auth/cross_origin_convergence_test.rb`, written guarded by phase 6c and
un-guarded by phase 6b.

## "Return current": loops, the cap, a missing or malformed `Location`

Every outcome that is not a follow hands the current response back **open**, for the caller to read and
close (`REDIR-22c`): a status outside the five; a `Location` that is missing or empty (`REDIR-19`); one
that is malformed, unresolvable, or names a scheme this client does not dispatch — `mailto:`, `ftp:`,
`javascript:`, an `http:` URL with no host — which is logged and never thrown (`REDIR-18`); a target
already visited, the seed's URL included (`REDIR-16`); a predicate or the built-in decision answering
no; and the cap (`REDIR-17`), on reaching which the last response is returned as it is, a 3xx included.

```ruby
res, transport = follow(step, response(302, location: "/y"), response(302, location: "/x"))
[res.status.code, transport.calls.size, res.body.closes]     # => [302, 2, 0]   the loop, open
res, transport = follow(R::Step.build(max_hops: 1),
                        response(302, location: "/1"), response(302, location: "/2"), response(200))
[res.status.code, transport.calls.size]                      # => [302, 2]      the cap
res, transport = follow(step, response(302))
[res.status.code, transport.calls.size]                      # => [302, 1]      no Location
res, transport = follow(step, response(302, location: "ht!tp://user:pass@bad"))
[res.status.code, transport.calls.size]                      # => [302, 1]      malformed
res, transport = follow(step, response(302, location: "mailto:a@b"))
[res.status.code, transport.calls.size]                      # => [302, 1]      unsupported scheme
```

The `Location` parsing route is `URI::RFC3986_PARSER.join`, directly — never `URI.join`, which a phase-0
cop refuses, and never `Dexpace::URL.parse!`, which rejects the relative reference `REDIR-14` requires
resolving. Resolution preserves an already-percent-encoded path, query and fragment, a bracketed IPv6
host and a non-default port byte for byte (`REDIR-13`). The userinfo strip is spelled `userinfo = ""`: assigning
`nil` is a silent no-op that forwards the server-supplied credential (`docs/knowledge/notes/redirect-handling.md`).
One residue, upstream of this layer: `URI#to_s` elides an **explicit** scheme-default port, and phase 1's
`URL.parse!` re-parses a URI from its text, so `Location: https://h:443/y` reaches the wire as
`https://h/y` — the origin is unchanged and every non-default port survives; the checklist's `REDIR-13`
row records it.

## Method, body and the 303 rebuild

A 301, 302, 307 or 308 is followed only when the **original** request's method is in the allowed set,
and then with the method and the body preserved — there is no `POST` → `GET` rewrite (`REDIR-3`,
`REDIR-4`). A 303 is not followed by default; opted in, it is re-issued as a `GET` with the body dropped
and every `Content-*` header removed by prefix, whatever the original method (`REDIR-5`). A
method-preserving hop re-sends the body, so a present body must be replayable — `Resend.replayable_body?`
below — or the operation fails with `Dexpace::NotReplayableError` and the redirect is not attempted
(`REDIR-6`); a 303 is exempt, having no body to re-send.

```ruby
post = req("https://api.example/x", method: "POST", body: Dexpace::Body.bytes("{}".b),
           headers: { "Content-Type" => "application/json" })
follow(step, response(303, location: "/y"), request: post).first.status.code   # => 303
_, transport = follow(R::Step.build(follow303: true),
                      response(303, location: "/y"), response(200), request: post)
rebuilt = transport.calls[1].first
[rebuilt.method.token, rebuilt.body, rebuilt.headers.names]  # => ["GET", nil, []]
follow(step, response(307, location: "/y"), request: post).first.status.code   # => 307
_, transport = follow(R::Step.build(allowed_methods: %w[GET HEAD POST]),
                      response(307, location: "/y"), response(200), request: post)
transport.calls[1].first.method.token                        # => "POST"

current = response(307, location: "/y")
streamed = req("https://api.example/x", method: "POST",
               body: Dexpace::Body.stream(StringIO.new("x"), close: true))
follow(R::Step.build(allowed_methods: %w[POST]), current, request: streamed)
# => Dexpace::NotReplayableError: redirect re-issue cannot be re-sent: the request body is
#    present and not replayable (REDIR-6)
current.body.closes                                          # => 1   closed before the raise
```

## The scheme downgrade

An `https` → `http` transition on any single hop is refused by default with
`Dexpace::Redirect::SchemeDowngradeError`, after the current response is closed (`REDIR-22b`) and after
the refusal is recorded; `allow_scheme_downgrade: true` permits it and the permission is recorded under
its own event name, so the log never says the opposite of what happened (`REDIR-15`). The check is per
hop — `http` → `https` → `http` fails on the second transition — and credential stripping applies
regardless: a scheme change is a different origin. The error's message names the two authorities and
the opt-in, and never a path or a query.

```ruby
current = response(302, location: "http://api.example/y")
follow(step, current)
# => Dexpace::Redirect::SchemeDowngradeError: redirect from https://api.example to
#    http://api.example would downgrade HTTPS to HTTP and is refused by default; opt in with
#    allow_scheme_downgrade: true (REDIR-15)
current.body.closes                                          # => 1
_, transport = follow(R::Step.build(allow_scheme_downgrade: true),
                      response(302, location: "http://api.example/y"), response(200))
transport.calls.map { |(r, _, _)| r.url.to_s }               # => ["https://api.example/x",
                                                             #     "http://api.example/y"]
```

## The predicate and its snapshot: `ConditionSnapshot`

A configured `predicate:` — anything callable with one argument — fully overrides the built-in follow
decision (`REDIR-20`): the allowed-method check, the 303 opt-in and the loop check are all its to
replace. It receives a `Dexpace::Redirect::ConditionSnapshot`, a frozen `Data` in the phase-1 shape —
`.build(response:, redirect_count:, visited_uris:)`, `.new` private, `#with` through `.build` — carrying
the current response (open), the count of redirects already followed and an insertion-ordered set of the
visited URIs' external forms, the current request's included, copied and frozen so the predicate cannot
reach the loop's live cycle-detection state. On a recognized 3xx the snapshot is always allocated and the
predicate always consulted, even when the response carries no usable `Location` (`REDIR-21`'s note); on
any other status neither happens. Three things a predicate cannot lift: a missing or malformed
`Location` still returns the current response unfollowed (`REDIR-18`, `REDIR-19` are MUSTs), the credential
hygiene still applies, and `REDIR-17`'s cap is a ceiling applied **over** the predicate's answer — the
predicate is consulted at the capped hop too, and its "follow" is then vetoed (R9; the checklist's
`P6-91`).

```ruby
seen = []
predicate = lambda do |snapshot|
  seen << [snapshot.redirect_count, snapshot.visited_uris.to_a, snapshot.response.status.code]
  snapshot.redirect_count < 1
end
res, transport = follow(R::Step.build(predicate: predicate),
                        response(302, location: "/1"), response(302, location: "/2"), response(200))
seen                                                         # => [[0, ["https://api.example/x"], 302],
                                                             #     [1, ["https://api.example/x", "https://api.example/1"], 302]]
[res.status.code, transport.calls.size]                      # => [302, 2]

snap = R::ConditionSnapshot.build(response: response(302), redirect_count: 0,
                                  visited_uris: ["https://api.example/x"])
snap.visited_uris.frozen?                                    # => true
snap.visited_uris << "https://evil.example/"                 # => FrozenError
```

## The records: `Events`, `Keys`

Each followed hop, each detected loop, each scheme-downgrade decision and each malformed `Location` is
one structured record through the step's `logger:` (`REDIR-28`), emitted inside
`Instrumentation.contain` so a raising sink cannot fail a redirect (`OBS-20`). The names are
`Dexpace::Redirect::Events` — `HOP_FOLLOWED` at INFO, `LOOP_DETECTED`, `SCHEME_DOWNGRADE_REJECTED`,
`SCHEME_DOWNGRADE_PERMITTED` and `LOCATION_MALFORMED` at WARNING — and the fields
`Dexpace::Redirect::Keys::FROM_URL`, `TO_URL`, `REDIRECT_COUNT` and `LOCATION_RAW`, with the status under
phase 5b's own `Instrumentation::Keys::HTTP_RESPONSE_STATUS_CODE`. Both URL fields go through the
**logger's** redactor — `Logger.build(redactor:)`, one policy per logging path; the step takes no
redactor of its own — and a redactor that raises degrades the field to the `[malformed url]` placeholder
rather than dropping the record. The one exception is `REDIR-28`'s own: the malformed-`Location` record
carries the header value **raw**, because it failed to parse and therefore cannot be redacted — a sink
receiving credential-bearing malformed values is the deployment's concern, and the requirement says so.

```ruby
sink = RecordingSink.new
logged = R::Step.build(logger: Dexpace::Instrumentation::Logger.build(sink: sink))
follow(logged, response(302, location: "https://user:pw@api.example/y?token=SECRET"), response(200),
       request: req("https://api.example/x?sig=S"))
payload = sink.payloads.first
payload["event"]                                             # => "http.redirect.hop"
payload[R::Keys::FROM_URL]                                   # => "https://api.example/x?sig=***"
payload[R::Keys::TO_URL]                                     # => "https://api.example/y?token=***"
payload["http.response.status_code"]                         # => 302
payload[R::Keys::REDIRECT_COUNT]                             # => 0

sink = RecordingSink.new
logged = R::Step.build(logger: Dexpace::Instrumentation::Logger.build(sink: sink))
follow(logged, response(302, location: "ht!tp://user:pass@bad"))
sink.payloads.first["event"]                                 # => "http.redirect.location_malformed"
sink.payloads.first[R::Keys::LOCATION_RAW]                   # => "ht!tp://user:pass@bad"
sink.payloads.first["cause"].start_with?("InvalidURIError")  # => true
```

The cause's text is the uri gem's own and differs by one space between uri 0.13 and uri 1.x, which is why
nothing in this layer matches it; the class is what a reader may rely on.

## The second re-sendability predicate: `Resend.replayable_body?`

Phase 6a's `Dexpace::Resilience::Resend` gains `.replayable_body?(request)` beside `.eligible?`, and
the two are not interchangeable. `.eligible?` is retry's gate and folds in `RETRY-7`'s idempotency
clause, so a body-less `POST` is *not* re-sendable there; `.replayable_body?` is `REDIR-6`'s question —
"is the body, if present, replayable?" — and says nothing about the method, because a redirect's method
eligibility is the allowed set's. Calling `.eligible?` at the redirect's site would refuse a body-less
`POST` 307 under an `allowed_methods:` that admits `POST`.

```ruby
bare_post = req("https://api.example/x", method: "POST")
Dexpace::Resilience::Resend.replayable_body?(bare_post)       # => true
Dexpace::Resilience::Resend.eligible?(bare_post)              # => false
```

## The standard pipelines: `Pipeline.standard`, `AsyncPipeline.standard`

The constructors phase 4c postponed until all three step families existed (`PIPE-39`), written over
`Builder#install_preset` and nothing else. `Pipeline.standard(over, ...)` installs a `Redirect::Step` at
`REDIRECT`, a `Resilience::RetryStep` at `RETRY` and an `Instrumentation::Step` at `LOGGING`;
`AsyncPipeline.standard(over, redirect: :unsupported, ...)` installs the async retry and instrumentation
steps and nothing at `REDIRECT`, and refuses every `redirect:` but `:unsupported`. `over` is a transport,
or a `Pipeline::Builder` already holding one and possibly other steps: the preset installs into **empty**
pillars only, and a builder whose target pillar is occupied rejects the whole call with nothing installed
(`PIPE-24`), while steps at other stages stay around the preset's. The keywords thread through:
`redirect:` (sync only — a `Redirect::Step` configured by the caller, or `nil` for one built over the
preset's logger), `settings:` and `http_tracer_factory:` to the retry step, `logger:` to all three,
`level:` and `preview_bytes:` to the instrumentation step. The async retry step waits through
`Dexpace::Async.delay`, so with no `Fiber.scheduler` a positive backoff fails the future with
`SeamError` and only zero-length delays retry (6a's P6-54); the constructor takes no scheduler keyword
because the step takes none.

```ruby
pipeline = Dexpace::Pipeline.standard(ScriptedTransport.new([]))
pipeline.entries.map { |e| e.stage.name }                    # => [:redirect, :retry, :logging]

settings = Dexpace::Resilience::RetrySettings.build(initial_delay: 0.0, jitter: 0.0, clock: FakeClock.new)
transport = ScriptedTransport.new([response(503), response(302, location: "/y"), response(200)])
pipeline = Dexpace::Pipeline.standard(transport, settings: settings)
pipeline.call(req("https://api.example/x")).status.code      # => 200   a retry, then a hop
transport.calls.map { |(r, _, _)| r.url.to_s }               # => ["https://api.example/x",
                                                             #     "https://api.example/x",
                                                             #     "https://api.example/y"]

Dexpace::AsyncPipeline.standard(ScriptedTransport.new([]))
# => ArgumentError: missing keyword: :redirect
Dexpace::AsyncPipeline.standard(ScriptedTransport.new([]), redirect: :follow)
# => Dexpace::InvalidArgumentError: AsyncPipeline.standard follows no redirects at the pipeline
#    layer (PIPE-32); pass redirect: :unsupported, got :follow
async = Dexpace::AsyncPipeline.standard(ScriptedTransport.new([]), redirect: :unsupported)
async.entries.map { |e| e.stage.name }                       # => [:retry, :logging]

builder = Dexpace::Pipeline.builder(transport: ScriptedTransport.new([]))
                           .append(Dexpace::Resilience::RetryStep.build)
Dexpace::Pipeline.standard(builder)
# => Dexpace::PipelineError: cannot install preset: pillar retry is already occupied by
#    Dexpace::Resilience::RetryStep (PIPE-24)
```

## What is deliberately not here

- **An async redirect step.** `REDIR-25` and `PIPE-32`: the async pipeline follows no redirects at the
  pipeline layer, and `AsyncPipeline.standard` says so with a required keyword.
- **A configurable target header.** `REDIR-27`'s MAY is declined for v1 (`docs/first-release.md`
  § What v1 ships without); `Location` is the only header read.
- **A `redactor:` keyword on the step.** The redactor is the logger's (`Logger.build(redactor:)`), one
  policy per logging path, as phase 5b's step and phase 6c's step have it.
- **A hop cap a predicate can lift.** `REDIR-17`'s "MUST be capped" is phrased with no carve-out, and an
  uncapped custom predicate would turn `REDIR-23`'s stack safety into an unbounded loop in connections
  and wall-clock; the predicate reads `redirect_count` off the snapshot and may stop earlier on its own
  account.
- **A `Resend` predicate that is both retry's and redirect's.** The two questions carry two names on one
  module; a third spelling, phase 6c's private `Auth::Step#replayable?`, is on phase 10's inbound list
  for consolidation.
- **Retrying the redirect target on a transport failure.** The retry pillar sits inside the redirect
  loop (`REDIRECT` 200, `RETRY` 500), so a failed hop is retried by the retry step, per hop, and the
  redirect step never re-drives a failed drive itself.
