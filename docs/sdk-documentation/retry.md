# Retry

**As built by phase 6a, in `dexpace-core`, written against source on 2026-09-18.** This page says what
chapter 9 gives an SDK author today: one shared policy core — the classifier consult over two axes,
the backoff calculator, the pacing-header parser and the tuning constants — the re-sendability gate,
the one configuration object both stacks build from, and the two stacks themselves: the recovery-chain
retry that decorates a raw transport beneath phase 4b's orchestrator with a total-timeout budget, and
the stage-based pillar step at `Stages::RETRY` on both runtimes. What each is *required* to do is
`docs/product-spec/09-retry-and-resilience.md` (`RETRY-1`–`RETRY-45`) and appendix C's
`RECOV-17`–`RECOV-30` and `RECOV-34`; how the design maps it to Ruby is
`docs/sdk-design-ruby/06-retry-redirect-and-authentication.md` §6.1 and
`docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.3; the per-requirement proof is
`docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry-checklist.md`. Signatures live in
`gems/dexpace-core/sig/dexpace/resilience/`, and this page does not restate them. Every example below
was run against the built code on 4.0.6 and 3.2.11 and printed the same on both. The examples use three
test doubles from `gems/dexpace-core/test/support/` — `ScriptedTransport`, `ScriptedAsyncTransport` and
`FakeClock` — because the retry layer waits on a clock and re-sends through a transport, and neither is
something a page example should do for real; `R` is `Dexpace::Resilience` throughout, `req.(method)` a
GET or POST to `https://api.example/x` with no body, and `response(code, headers:)` a response over a
closable single-use body.

**Two stacks, one policy, no unification.** The specification's chapter opens by saying the two stacks
are "deliberately built on ONE status classifier, ONE backoff calculator, ONE pacing-header parser, and
ONE set of tuning constants so behavior cannot drift", and this port keeps both stacks and shares all
four: `RecoveryRetry`, `RetryStep` and `AsyncRetryStep` are three thin drivers over `Policy`, `Resend`
and `RetrySettings`, and a text scan in the suite refuses a delay literal anywhere but `Policy`. The
one asymmetry is `RETRY-27`/`RETRY-28`'s: the recovery stack enforces a total-timeout budget and the
stage stack must not, and the calculator takes no budget parameter at all — the budget is a separate
function only the recovery driver names, so the prohibition is a fact about which files call which
method (design §10, `P6-5`).

## The policy core: `Policy`

`Dexpace::Resilience::Policy` is a frozen-constant module with pure functions and no state, which is
`RETRY-42`'s "immutable and stateless" as a structure rather than a promise. Its constants are
`RETRY-12`'s defaults — 200 ms, ×2, 8 s, jitter 0.2, and a budget of three sends spelled in the stage
vocabulary as two retries — `XCUT-7`'s default configurable status set, `RETRY-21`'s fixed header
precedence, and the two ceilings `RETRY-18` and `RECOV-34` name.

```ruby
R = Dexpace::Resilience
R::Policy::DEFAULT_INITIAL_DELAY          # => 0.2
R::Policy::DEFAULT_MAX_RETRIES            # => 2
R::Policy::DEFAULT_RETRYABLE_STATUSES.to_a
# => [408, 429, 500, 502, 503, 504]
R::Policy::DEFAULT_PACING_HEADER_ORDER
# => ["Retry-After", "retry-after-ms", "x-ms-retry-after-ms", "X-RateLimit-Reset"]
```

**Two questions, two names, three objects.** Phase 5a's `Dexpace::Retryability.retryable_status?` is
`XCUT-5`'s single built-in classifier — 408, 429 and 500–599 less 501 and 505 — and it feeds exactly one
thing: the flag `ProtocolError` bakes at construction (below). `Policy.retry_eligible?(status, set:)` is
what the retry drivers consult instead, over `XCUT-7`'s *configurable* set, and it is
authoritative-contains: the set is consulted alone and never AND-ed with the baked flag, so a set that
narrows narrows and a set that widens widens (`RETRY-37`). The method has no baked-flag parameter, which
makes the intersection the requirement forbids a method that does not exist.

```ruby
R::Policy.retry_eligible?(418, set: Set[418])   # => true   (outside the baked set, still retried)
R::Policy.retry_eligible?(503, set: Set[429])   # => false  (inside the baked set, still refused)
Dexpace::Retryability.retryable_status?(503)    # => true   (the baked classifier, unchanged)
```

The throwable branch is `RETRY-2`'s and `XCUT-6`'s: a capability query, `respond_to?(:retryable?) &&
retryable?`, walked over the error and its whole cause chain through phase 4b's `Dexpace.each_cause`,
whose identity-tracked visited set is what makes a cyclic chain terminate. Never a concrete-type match,
which is wrong in both directions: phase 3a's `StreamError` is an `IOError` and not a transport timeout,
and a real `Errno::ETIMEDOUT` is not an `IOError` at all. The residual is stated rather than hidden
(`P6-4`): a bare stdlib I/O or timeout error that escapes an adapter *unwrapped* answers no capability
and classifies not retryable, which is why phase 8's adapters must wrap what they let escape in
`Dexpace::TransportError`, whose flag answers `true` — `RETRY-4`'s row belongs to phase 8a.

```ruby
timeout = Class.new(::IOError) { def retryable? = true }   # the shape an adapter's wrapper has
R::Policy.throwable_retryable?(timeout.new("read timeout"))          # => true
R::Policy.throwable_retryable?(Dexpace::StreamError.new("short"))    # => false
R::Policy.throwable_retryable?(wrapped)   # a RuntimeError whose #cause is the timeout   # => true
```

`Policy.retryable?(error, retryable_statuses:)` is the one dispatch point every driver calls: a
cancellation first — `Policy.cancellation?` walks the cause chain for a `Dexpace::CancelledError`, and
one is never retryable whatever wraps it or what the wrapper answers (`RETRY-23`, `P6-60`) — then a
`ProtocolError` by its status against the configured set, anything else by the capability. A
`ProtocolError` deliberately does not answer `#retryable?`, so one buried in a cause chain can never
smuggle the baked set past the configured one (`P6-10`). The stage drivers consult the cancellation
guard before a caller's `should_retry:` too, so a predicate answering `true` never sees a cancellation.

```ruby
carrier = begin   # the adapter's retryable wrapper, raised from a rescue of the token's own raise
  begin; raise Dexpace::CancelledError, :token; rescue Dexpace::CancelledError; raise timeout, "read"; end
rescue timeout => error
  error
end
R::Policy.throwable_retryable?(carrier)                                             # => true
R::Policy.cancellation?(carrier)                                                    # => true
R::Policy.retryable?(carrier, retryable_statuses: R::Policy::DEFAULT_RETRYABLE_STATUSES)   # => false
```

**The calculator** is `RETRY-9`–`RETRY-11` and `RECOV-21` in one function: `initial × multiplier^(n−1)`
capped at the maximum, then symmetric jitter drawn uniformly from `[d(1 − j/2), d(1 + j/2)]` with
midpoint `d`, `j = 0` returning `d` exactly, a sub-nanosecond spread returning `d`, a negative sample
floored at zero; attempt 1 is the wait before the first retry and anything below 1 is refused.
Overflow is Ruby's own float arithmetic plus one guard: `2.0 ** 999` is `Infinity` and `[Infinity,
8.0].min` is `8.0`, so a huge attempt saturates — but `0.0 × Infinity` is `NaN` and `[NaN, 8.0].min`
*raises*, so a zero initial delay answers zero before the power is taken (found by the 2,000-attempt
trampoline test; `P6-53`).

```ruby
args = { initial_delay: 0.2, multiplier: 2.0, max_delay: 8.0, jitter: 0.0, random: Random }
(1..7).map { |n| R::Policy.backoff_delay(n, **args) }   # => [0.2, 0.4, 0.8, 1.6, 3.2, 6.4, 8.0]
R::Policy.backoff_delay(1_000, **args)                   # => 8.0
R::Policy.backoff_delay(1, **args, initial_delay: 0.0)   # => 0.0
R::Policy.backoff_delay(1, **args, initial_delay: 1.0, jitter: 0.5, random: Random.new(7))
  .between?(0.75, 1.25)                                  # => true
```

**The two budget helpers.** `Policy.effective_max_retries(override:, configured:, logger:)` is
`RETRY-41`: a present per-call `RequestOptions#max_retries` wins, else the configured value, a negative
configured value clamped to the default and the clamp logged as one WARNING
`http.instrumentation.config` diagnostic through 5b's facade, contained so a raising sink cannot fail
the resolution; zero means no retries. `Policy.budget_remaining(elapsed:, total_timeout:)` is
`RECOV-20`'s budget as the time *remaining* — `Float::INFINITY` for a zero budget, negative once spent —
and only `RecoveryRetry` calls it.

```ruby
R::Policy.effective_max_retries(override: 1, configured: 5)                     # => 1
R::Policy.effective_max_retries(override: nil, configured: -1, logger: logger)  # => 2
sink.payloads.first["event"]                              # => "http.instrumentation.config"
R::Policy.budget_remaining(elapsed: 6.0, total_timeout: 10.0)                   # => 4.0
R::Policy.budget_remaining(elapsed: 60.0, total_timeout: 0)                     # => Infinity
```

## The pacing parser: `Policy.pacing_delay`

`Policy.pacing_delay(headers, header_order:, now:, random:)` walks the header names in the order it is
given — the recovery stack's fixed precedence, or the stage stack's caller-configurable list — and
returns the first usable value in seconds, clamped to 365 days, or `nil` for no hint. The forms are
`RETRY-15`'s: `Retry-After` as delta-seconds (integer and fractional), then as an RFC 1123 HTTP-date
through phase 5a's `HTTPDate.parse` — the one parser, whose day group phase 6a widened from `(\d{2})` to
`(\d{1,2})` so a single-digit day parses, the weekday still required and still never validated (R1);
`retry-after-ms` and `x-ms-retry-after-ms` as integer milliseconds; `X-RateLimit-Reset` as Unix epoch
seconds whose delta is jittered *upward* to `[100%, 120%]` inside the parser (`RECOV-25`), so no second
jitter is ever applied on top. The parser is total (`RETRY-16`): a malformed, negative or out-of-range
value is `nil` and never zero, a past absolute time is `0.0` and never `nil` (`RETRY-17`), the numeric
form is screened by a strict anchored decimal grammar *before* any float parse so `30d`, `0x10`, `1e3`,
`5_0`, `NaN` and `Infinity` fall through (`RETRY-19`; `Integer("5_0", 10)` is 50, which is why the screen
is load-bearing), and a value one form cannot read does not stop the next form being tried (`RETRY-22`).
The grammars bound their digit runs at fifteen and a 64-byte ceiling sits in front of every form
(`P6-61`): fifteen digits is the largest run a Float carries exactly and 10^15 seconds is thirty million
years, so a longer run is out of range and `nil` before anything converts it — a 10 MB value costs the
parser microseconds and emits no warning, where an unbounded `String#to_f` cost seconds — and the
longest well-formed value, the 29-byte RFC 1123 date, sits well under the ceiling.

```ruby
order = R::Policy::DEFAULT_PACING_HEADER_ORDER
now = Time.utc(2026, 9, 18, 12, 0, 0)
pacing = ->(pairs) { R::Policy.pacing_delay(headers(pairs), header_order: order, now: now) }
pacing.("Retry-After" => "2.5")                                # => 2.5
pacing.("Retry-After" => "Fri, 18 Sep 2026 12:01:30 GMT")      # => 90.0
pacing.("Retry-After" => "Mon, 6 Sep 2026 12:00:00 GMT")       # => 0.0   (past; a wrong weekday, a one-digit day)
pacing.("retry-after-ms" => "1500")                            # => 1.5
pacing.("Retry-After" => "30d")                                # => nil
pacing.("Retry-After" => "garbage", "retry-after-ms" => "1000") # => 1.0
pacing.("Retry-After" => (400 * 86_400).to_s)                  # => 31536000.0   (365 days)
pacing.("Retry-After" => "9" * 15)                             # => 31536000.0   (clamped)
pacing.("Retry-After" => "9" * 16)                             # => nil          (out of range)
```

`now:` is a parameter because the drivers pass their settings clock's `#now`, so a fake clock drives
the absolute forms deterministically; the default is `Time.now`.

## The re-sendability gate: `Resend.eligible?`

The second axis, single-sourced (`RETRY-5`–`RETRY-8`, `RECOV-18`): a body-less request is re-sendable
iff its method is idempotent — phase 1's `Method::IDEMPOTENT`, read through `#idempotent?` and re-listed
nowhere — and a body-bearing request iff its body says it is replayable (phase 3b's `Body#replayable?`,
`false` by default). So a bare non-idempotent POST is not re-sendable even though there is no payload to
resend, a PUT with a consumed stream is not either, and every driver consults this gate *first*, before
any condition is looked at and before any caller predicate is asked — a predicate may widen or narrow
the condition and may never authorise a re-send. Phase 6b adds `REDIR-6`'s body-only question to this
module beside `.eligible?`.

```ruby
R::Resend.eligible?(req.("GET"))                                          # => true
R::Resend.eligible?(req.("POST"))                                         # => false
R::Resend.eligible?(req.("POST", Dexpace::Body.bytes("{}".b)))            # => true
R::Resend.eligible?(req.("PUT", Dexpace::Body.stream(io, close: true)))   # => false
```

## The one configuration: `RetrySettings`

`RetrySettings.build` is a frozen `Data` over the shared defaults, validated clause by clause at
construction (`RECOV-34`, each refusal naming its member): durations non-negative, finite and within the
signed 64-bit nanosecond ceiling; `multiplier >= 1.0`; `jitter` in `[0.0, 1.0]`; `max_retries` a
non-negative Integer, zero disabling retries; `retryable_statuses` and `pacing_header_order` copied and
deep-frozen so the caller's collection stays theirs. `total_timeout` is carried for both stacks and read
by one (the recovery engine; `0` is unbounded). `#with` re-validates through `.build` on every Ruby,
because `Data#with` skips `initialize` on the 3.2 floor. `random:` defaults to the `::Random` *class*,
whose `.rand` is the process generator CRuby makes safe to share; a seeded `Random.new` is what a test
passes, and a caller who passes one shares a mutable generator across calls.

`max_retries` is the *stage* vocabulary — retries after the initial send — and the recovery stack's
attempts cap is always `max_retries + 1`, an identity and never a second number (`RETRY-14`, `P6-6`).
When no `max_retries:` is passed, `.build` reads 5a's `Configuration::Keys::MAX_RETRY_ATTEMPTS` off the
process-wide slot once — this class is that key's first reader — and falls back to
`Policy::DEFAULT_MAX_RETRIES`; an explicit argument always wins, and `#with` never re-hits the key. A
*negative* configured value meets `RETRY-41` at that one read: it is clamped to the default through the
same `Policy.effective_max_retries` the drivers resolve with, and the clamp is logged once, contained,
through `.build`'s `logger:` (`Instrumentation::Logger::NULL` by default, read at build and never held;
`P6-59`) — an explicit negative `max_retries:` is a caller's construction input and `RECOV-34` refuses it
instead.

```ruby
R::RetrySettings.build.max_retries                                        # => 2
R::RetrySettings.build.total_timeout                                      # => 0.0
R::RetrySettings.build.header_order.equal?(R::Policy::DEFAULT_PACING_HEADER_ORDER)   # => true
# with Dexpace.configure { |c| c.env_source = FakeConfigSource.new("MAX_RETRY_ATTEMPTS" => "4") }
R::RetrySettings.build.max_retries                                        # => 4
R::RetrySettings.build(max_retries: 1).max_retries                        # => 1
# with Dexpace.configure { |c| c.env_source = FakeConfigSource.new("MAX_RETRY_ATTEMPTS" => "-1") }
R::RetrySettings.build(logger: logger).max_retries                        # => 2   (clamped, logged)
sink.payloads.last["message"]      # => "max_retries -1 is negative and was clamped to 2 (RETRY-41)"
R::RetrySettings.build(max_retries: -1)
# raises Dexpace::InvalidArgumentError: max_retries must be a non-negative Integer (RECOV-34)
R::RetrySettings.build(jitter: 1.5)
# raises Dexpace::InvalidArgumentError: jitter must lie within [0.0, 1.0] (RECOV-34)
statuses = Set[500]; settings = R::RetrySettings.build(retryable_statuses: statuses); statuses << 599
settings.retryable_statuses.to_a                                          # => [500]
settings.with(clock: FakeClock.new).multiplier                            # => 2.0
```

## The stage-based step, sync: `RetryStep`

`RetryStep.build(settings:, http_tracer_factory:, delay_override:, should_retry:, logger:)` is the
pillar step at `Stages::RETRY` — order 500, between `REDIRECT` and `AUTH` — installed with
`builder.append(step)` and no `stage:` argument because it declares `#stage`. It **forks its cursor for
every drive, the first included, and never calls its own cursor's `#call`** (design §10, the
`pipeline/86343352` note): a fork is what gives a pillar's drive a stage slot, and `#call` and `#fork`
are disjoint on one cursor. It writes no cursor state of its own; the cross-origin marker is 6b's and
6c's. Each attempt re-sends the *same* frozen request through a fresh fork (`RETRY-44`).

One operation, in order: the tracer is made once from the factory, called with the cursor; the
effective retry count is resolved (`RETRY-41`); then per attempt — the cancellation token is checked at
the boundary (`RETRY-23`; a zero-length `Clock#sleep` returns before its own token check, so this is what
stands between a cancellation and a second send), `attempt_started` fires, the fork is driven, and a
success is returned. On a failure the decision runs — a cancellation is terminal before anything else
(`RETRY-23`, `P6-60`), then re-sendability, then the condition (the shared classifier, or the caller's
`should_retry:`), then the budget, in that order — and answers retry, exhausted or stop. On retry the
delay is resolved from the *still-open* response and `attempt_failed` fires with it, both inside one
fence that closes the response before a throwing computation or tracer propagates; then the failure
joins the trail, the response is closed, and the step waits on the settings clock's cancellable sleep
with the cursor's token (`RETRY-35`, `RETRY-26`). On stop or exhausted, a
response is returned as it is and a throwable is raised with the whole prior trail attached as
suppressed through `Dexpace.attach_suppressed` (`RETRY-34`), `retries_exhausted` firing first only when a
*retryable* failure met a spent budget — a failure that was never retryable is not an exhausted retry —
and that emission sits inside the same fence as the decision, so a tracer that raises there propagates
with the terminal error-status response closed first, while a tracer that does not leaves it open for
the caller, as the async pump's guarded block has always done on its terminal path.

The delay precedence is `RETRY-39`'s: the caller's `delay_override:` (called with `(attempt, response,
error)`, answering seconds or `nil` to decline), then the pacing headers on the response path only,
then backoff. A throwing or nonsensical override is non-fatal — one WARNING `http.instrumentation.hook`
diagnostic, and the precedence falls through — while a throwing `should_retry:` aborts the call as
`Dexpace::RetryPredicateError` with the raise as its `#cause`, the open response closed first
(`RETRY-40`). The fatal family (`NoMemoryError`, `SystemStackError`) is never rescued, classified,
reported or trail-attached: it propagates at the throw site, and the two close fences re-raise it
unchanged after closing the response (`RETRY-25`).

```ruby
clock = FakeClock.new
settings = R::RetrySettings.build(initial_delay: 0.1, jitter: 0.0, max_retries: 2, clock: clock)
tracer = Dexpace::RecordingHTTPTracer.new
step = R::RetryStep.build(settings: settings, http_tracer_factory: ->(_cursor) { tracer })
step.stage.equal?(Dexpace::Pipeline::Stages::RETRY)                       # => true

transport = ScriptedTransport.new([response(503, headers: { "Retry-After" => "3" }),
                                   response(503), response(200)])
pipeline = Dexpace::Pipeline::Builder.new(transport: transport).append(step).build
pipeline.call(req.("GET")).status.code                                    # => 200
transport.calls.size                                                      # => 3
clock.sleeps.map { _1[:duration] }                                        # => [3.0, 0.2]   (the hint, then backoff)
tracer.events.map(&:first)
# => [:attempt_started, :attempt_failed, :attempt_started, :attempt_failed, :attempt_started]
tracer.events[1][2].class                                                 # => Dexpace::ProtocolError
```

```ruby
step = R::RetryStep.build(settings: R::RetrySettings.build(initial_delay: 0.0, jitter: 0.0, max_retries: 1))
e1, e2 = timeout.new("one"), timeout.new("two")
Dexpace::Pipeline::Builder.new(transport: ScriptedTransport.new([e1, e2])).append(step).build
  .call(req.("GET"))
# raises e2 -- the LAST error, carrying the prior trail:
surfaced.equal?(e2)                                # => true
Dexpace.suppressed(surfaced).map(&:message)        # => ["one"]

pipeline.call(req.("POST")).status.code            # => 503   (a bare POST: one attempt, returned)
t3.calls.size                                      # => 1

R::RetryStep.build(should_retry: ->(*) { raise "boom" })  # ... on a 503:
# raises Dexpace::RetryPredicateError, whose #cause is #<RuntimeError: boom>

options = Dexpace::RequestOptions.build(timeout: nil, max_retries: 0, tags: {})
pipeline.call(req.("GET"), options).status.code    # => 503   (the per-call override: no retries)
```

The `http_tracer_factory:` is `OBS-29`'s per-operation HTTP-tracer source (R3, `P6-7`): called once per
`#call` with the cursor, which is also the `context` every callback receives, defaulting to a lambda
answering `Instrumentation::NULL`. It is deliberately *not* `Cursor#bundle`'s `tracer_factory`, which
produces span tracers — a different kind of object. A throwing tracer callback propagates and fails the
request: `OBS-30` puts that on the implementer, and core wraps no tracer callback (`OBS-20`'s
carve-out). The operation-lifecycle triple and the transport milestones are emitted by nothing in v1
(`docs/first-release.md`, the behavioural-asymmetries entry).

## The stage-based step, async: `AsyncRetryStep`

`AsyncRetryStep.build` takes the same keywords and shares the same decision and delay resolution (one
private helper module, so the two cannot drift) over 4c's async step contract: `#call` returns a
`Dexpace::Async::Future`, and every drive is a fork's future. **The loop is an iterative trampoline**
(`RETRY-30`): each `#call` allocates one private pump holding the per-call state; a downstream or delay
future that settles *inline* — which every scripted transport does, and which `Async.delay` does for a
zero-length delay — does not re-enter a nested attempt but flips a re-arm flag under the pump's mutex,
and the loop already running picks the next attempt up when the current one returns; only a future that
settles later, on another thread or a scheduler fiber, starts the loop again from its callback on a
fresh stack. The plan's recursive sketch overflowed at about 1,500 zero-length attempts on every
interpreter; the built pump is measured flat across 2,001 (`P6-54`).

**R2, as built.** A zero-length delay completes inline and re-arms the pump without a frame
(`RETRY-31`). A positive delay goes through 5a's `Async.delay`, which parks the fiber under a registered
`Fiber.scheduler` and blocks no thread — and with *no* scheduler raises `Dexpace::SeamError`
synchronously, which the pump's fence catches and turns into a failed future carrying the prior trail.
Nothing here installs, reads or shuts down a scheduler (`RETRY-45`), and the step never falls back to a
blocking sleep, which `RETRY-31` forbids. Every callback body is fenced (`RETRY-33`): a throwing
predicate, delay computation, tracer callback or factory, and a scheduler rejection, each close any open
response and complete the future exceptionally rather than leaving it hanging; the fatal family is
re-raised after the future is failed, and a fatal that *arrives* as a settlement — there is no rescue
arm on this path — is delivered unclassified and unretried (`RETRY-25`, `P6-55`). Once the returned
future is settled or cancelled, no further attempt launches, a pending delay is cancelled, and a response
arriving from an abandoned attempt is closed rather than leaked (`RETRY-32`); a cancelled token cancels
the pending delay and fails the future with the `CancelledError` (`RETRY-23`).

```ruby
step = R::AsyncRetryStep.build(settings: R::RetrySettings.build(initial_delay: 0.0, jitter: 0.0, max_retries: 2))
transport = ScriptedAsyncTransport.new([response(503), response(503), response(200)])
future = Dexpace::Pipeline::Builder.new(transport: transport).append(step).build_async.call(req.("GET"))
Fiber.scheduler                                    # => nil
future.settled?                                    # => true    (zero-length delays complete inline)
future.value.status.code                           # => 200

step = R::AsyncRetryStep.build(settings: R::RetrySettings.build(initial_delay: 0.01, jitter: 0.0))
# ... over [response(503), response(200)], with no scheduler registered:
future.value                                       # raises Dexpace::SeamError -- not a hang, not a blocking wait
```

## The recovery-chain retry: `RecoveryRetry`

`RecoveryRetry.build(transport:, settings:, http_tracer_factory:, logger:)` is the first stack: a
`Dexpace::Transport` by the duck type that decorates a raw transport and is installed as
`Recovery::Orchestrator`'s own `transport:` argument, *not* as a `Recovery::ResponseChain` recovery step
(`P6-3`). Two facts force the position: a recovery step's `#apply(outcome)` carries no request to
re-send, and `RECOV-19` describes an engine that dispatches its own re-sends and re-classifies each one
— which only a transport decorator can do while keeping `RequestChain`'s stamping (the idempotency key,
the client identity) applied once per exchange rather than once per attempt. Sitting below the
orchestrator's rescue region, a transport that *raises* reaches this engine as an exception and is
retried when it answers the capability (`RECOV-17`; `P6-8`) — the connection-reset case the chain
alone would never have retried.

Each attempt's error-status response is buffered through phase 4b's `Recovery.buffer_error_body`,
which is what releases the connection before the wait (`RECOV-16`, `RETRY-35`), and paired with
`ProtocolError.for(buffered)` purely to decide whether to keep going; the *buffered* response is what
every later line sees — the pacing parse, the pass-through, and whatever `ErrorMappingStep` factory the
caller configured, which runs exactly once, on the terminal response. Two terminal shapes (`P6-9`): a
response whose failure was never retryable — a status outside the configured set, a request that was not
re-sendable — is *returned*, "passes through as Success" for the outer chain to map (`RECOV-19`); a
throwable, and a retryable status that met a spent attempt cap or a spent total-timeout, is *raised*
with the prior trail attached (`RECOV-20`, `RETRY-34`), `retries_exhausted` firing immediately before
when the budget is what stopped it.

The budget is both bounds (`RECOV-20`, `RETRY-27`): a maximum-attempts cap counting the initial send as
attempt 1 (`max_retries + 1`), and a total-timeout applied as the time remaining through
`Policy.budget_remaining` — a delay that would push the elapsed time past the budget is suppressed and
the last failure surfaced, so no wait can overshoot; zero is unbounded. Elapsed time is the settings
clock's monotonic reading, never `Time.now`. The pacing precedence on this stack is the fixed one, and a
hint replaces the backoff for that decision while still being clamped by the remaining budget
(`RECOV-22`). The wait is `Clock#sleep` with the caller's token, the token is checked at every attempt
boundary, and the attempt count, start instant and trail are locals of one `#call` (`RECOV-28`).

```ruby
clock = FakeClock.new
settings = R::RetrySettings.build(initial_delay: 0.4, max_delay: 0.4, jitter: 0.0,
                                  max_retries: 10, total_timeout: 1.0, clock: clock)
transport = ScriptedTransport.new(Array.new(11) { response(503) })
engine = R::RecoveryRetry.build(transport: transport, settings: settings)
Dexpace::Transport.conforms?(engine)               # => true
engine.call(req.("GET"), Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
# raises Dexpace::ProtocolError: HTTP 503 Service Unavailable -- the budget:
transport.calls.size                               # => 3     (1.0 -> sleep 0.4 -> 0.6 -> sleep 0.4 -> 0.2 < 0.4)
clock.sleeps.map { _1[:duration] }                 # => [0.4, 0.4]
Dexpace.suppressed(error).map { _1.status.code }   # => [503, 503]

R::RecoveryRetry.build(transport: ScriptedTransport.new([response(404)]))
  .call(req.("GET"), Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
  .then { |r| [r.status.code, r.body.class] }      # => [404, Dexpace::BufferBody]   (RECOV-19: returned, buffered)

orchestrator = Dexpace::Recovery::Orchestrator.build(
  transport: R::RecoveryRetry.build(transport: ScriptedTransport.new([response(503), response(200)]),
                                    settings: R::RetrySettings.build(initial_delay: 0.0, jitter: 0.0, clock: FakeClock.new)),
  request_chain: Dexpace::Recovery::RequestChain.build,
  response_chain: Dexpace::Recovery::ResponseChain.build(
    response_steps: [Dexpace::Recovery::ErrorMappingStep.build],
  ),
)
orchestrator.call(req.("GET"), Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none).status.code  # => 200
```

## Three wirings into earlier layers

**`ProtocolError#retryable_by_status?`** — `XCUT-5`'s baked flag, phase 4b's postponement, computed once
at construction from 5a's `Retryability` and never per subclass (`RETRY-3`). Deliberately not named
`#retryable?`, the open capability: a `ProtocolError` answering that query would let the baked set
override the configured one whenever the error is wrapped (`P6-10`).

```ruby
Dexpace::ProtocolError.for(response(503)).retryable_by_status?          # => true
Dexpace::ProtocolError.for(response(501)).retryable_by_status?          # => false
Dexpace::ProtocolError.for(response(503)).respond_to?(:retryable?)      # => false
```

**`Cursor#bundle`** — the context-bundle widening (Task 8), the one export 6b and 6c consume if it
exists: `Pipeline#call` and `AsyncPipeline#call` gain an optional `bundle:` keyword, `Bundle::NONE` by
default, that seeds a read-only per-call `Cursor#bundle` carried across every `#fork` exactly as
`#options` is. 5b's instrumentation step now honours the reconciled precedence's first clause for its
tracer factory — the cursor's bundle when it is not `NONE`, else the step's keyword — and correlates over
the same bundle, so a valid seeded bundle pushes its trace and span ids onto the diagnostic context
(`OBS-23`). The meter has no bundle source (`CTX-14`'s bundle carries none) and keeps the keyword.

```ruby
bundle = Dexpace::Instrumentation::Bundle.build(trace_id: "a" * 32, span_id: "b" * 16,
                                                flavour: Dexpace::Instrumentation::TraceIdFlavour::W3C)
seen = []
probe = ->(request, cursor) { seen << cursor.bundle; cursor.call(request) }
pipeline = Dexpace::Pipeline::Builder.new(transport: ->(*) { response(200) })
                                     .append(probe, stage: Dexpace::Pipeline::Stages::PRE_RETRY).build
pipeline.call(req.("GET"))
pipeline.call(req.("GET"), bundle: bundle)
seen[0].equal?(Dexpace::Instrumentation::Bundle::NONE)   # => true
seen[1].equal?(bundle)                                   # => true
```

**`HTTPDate.parse`'s single-digit day** — R1's widening of 5a's one RFC 1123 parser, so `RETRY-15`'s
tolerance list is met by the parser `Retry-After` already reads through; nothing else about the grammar
moved.

```ruby
Dexpace::HTTPDate.parse("Sun, 6 Nov 1994 08:49:37 GMT")   # => 1994-11-06 08:49:37 UTC
```

## What is deliberately not here

`Pipeline.standard` and `AsyncPipeline.standard` — the constructors phase 4c postponed — are phase 6b's
to build over `Builder#install_preset`; this phase ships the two step families they will install and
neither constructor. The operation-lifecycle triple and the transport milestones of the HTTP-tracer
vocabulary are emitted by nothing in v1, and a tracer sees the per-attempt group only. `RETRY-29`'s
server-driven override header, `RETRY-38`/`RECOV-31`'s attempt-ordinal header and `RETRY-43`'s
fixed-delay mode are declined for v1 (`docs/first-release.md`). `RETRY-4`'s unconditional flag on a
no-response transport failure lives on the wrapper type phase 8's adapters raise, not here — and until
an adapter wraps what it lets escape, a bare stdlib timeout classifies not retryable (`P6-4`). The async
step takes no scheduler keyword and installs none; a positive backoff under no scheduler fails the
future rather than blocking a thread.
