# Tracing and metrics

**As built by phase 5c, in `dexpace-core`, written against source on 2026-09-17.** This page says what
the tracing and metrics half of chapter 15 gives an SDK author today: the span, tracer and
tracer-factory protocols behind the three no-op singletons phase 4a published, the current-span carrier
and the log-correlation scope over the diagnostic context, trace-id generation on the flavour, the
sampled bit, the HTTP-shaped tracer vocabulary with its ordering contract, and the metrics SPI with its
no-op meter. What each is *required* to do is `docs/product-spec/15-instrumentation-and-observability.md`
§15.5–§15.8; how the design maps it to Ruby is
`docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.1; the per-requirement proof is
`docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-checklist.md`. Signatures live in
`gems/dexpace-core/sig/dexpace/instrumentation/`, and this page does not restate them. Every example
below was run against the built code on 4.0.6 and 3.2.11 and printed the same on both, with three
differences each stated where it appears: the floor retains a nil-valued diagnostic key where 3.3 and
later remove it, a `Hash#inspect` on the floor spells `{:context=>:ctx}` where 4.0.6 spells
`{context: :ctx}`, and the allocation loop's fixed cost differs by three objects.

**Nothing in v1 traces a request for you.** No pipeline step exists yet — phase 5b's instrumentation
step is where a span is started and finished per request and where the two metrics are recorded — and
nothing emits the HTTP-tracer vocabulary: the per-attempt events wait for phase 6's retry step and the
transport milestones for phase 8's adapters, which `OBS-29`'s own text anticipates ("pipeline/transport
wiring to emit it is a follow-up"). What ships is the contract every one of those will honour and the
no-op implementations an untraced application runs on at zero cost. This page is written for the author
of an adapter or a step who will implement or drive that contract.

## The no-op span and tracer: `NO_SPAN`, `NO_TRACER`, `NO_TRACER_FACTORY`

Phase 4a published three frozen singletons with no methods and reserved their protocols for this
phase; phase 5c gave the private classes behind them their methods **in place**, so every object keeps
the identity phase 4a published and `Bundle::NONE` still carries the same two. A span answers `OBS-21`'s
seven methods: the recording flag, three mutators that are inert when it is false and return `self`
either way, a status writer with no reader, an idempotent `#finish`, and `#context`.

```ruby
span = Dexpace::Instrumentation::NO_SPAN
span.recording?                                                        # => false
span.set_attribute("http.request.method", "GET").equal?(span)          # => true
span.add_event("cache.hit", attributes: { "tier" => "l1" }.freeze).equal?(span)  # => true
span.record_error(RuntimeError.new("boom")).equal?(span)               # => true
span.finish                                                            # => nil
span.finish                                                            # => nil
span.context.equal?(Dexpace::Instrumentation::Bundle::NONE)            # => true
span.frozen?                                                           # => true
```

`finish`, not `end` — `end` is a legal method name, and the choice follows `opentelemetry-api`'s shape
as phase 4a's `#tracer` does; `record_error`, not `record_exception`, because `OBS-21`'s word is "error"
and the SDK's own vocabulary is `Dexpace::Error`. Every attributes parameter is one **named optional
keyword** and never a `**` splat: a splat allocates a `Hash` on every call including one that passes
nothing, and `OBS-25` makes the no-op path's zero allocation a MUST. The phase-0 cop
`Dexpace/NoKeywordSplat` refuses a splat in every gem's `lib/`.

A tracer starts a span or yields one, and the no-op tracer hands back `NO_SPAN` by identity; the
factory hands back `NO_TRACER` on every call, from any thread, whatever the instrumentation-library name
and version it is given (the five-argument mirror of `OpenTelemetry::Trace::TracerProvider#tracer`,
phase 4a's, unchanged).

```ruby
tracer = Dexpace::Instrumentation::NO_TRACER_FACTORY.tracer("GetUser")
tracer.equal?(Dexpace::Instrumentation::NO_TRACER)                         # => true
tracer.start_span("GetUser", kind: :client).equal?(Dexpace::Instrumentation::NO_SPAN)  # => true
tracer.in_span("GetUser") { |s| s.equal?(Dexpace::Instrumentation::NO_SPAN) }  # => true
```

`OBS-29` says one tracer instance corresponds 1:1 to one operation, created by its factory per
operation, and `OBS-25` says the no-op factory returns a shared tracer and allocates nothing. The two
are consistent only read as a rule about **state**: a tracer that accumulates anything per operation
must not be shared, and a stateless no-op has nothing to correspond. An implementer's factory returns a
fresh tracer per operation; the SDK's stays one object.

## The current span and the scope handle: `Tracing`, `Scope`, `NO_SCOPE`

`Dexpace::Instrumentation::Tracing` is a function module over one fiber-storage slot. `.current_span`
reads it and never returns `nil` — `NO_SPAN` when nothing is active. `.with_span(span) { }` makes a
span current for the block and restores the previous one in an `ensure`; `.activate(span)` is the
handle form `OBS-22` names — "return a scope handle that, when closed, restores the previously-active
span" — for a scope that outlives its frame, and the block form is written over it, so there is one
restore path. The handle is a plain three-ivar `Scope` holding the previous span on the Ruby call
stack, and deliberately not a `Data` and not a `Dexpace::Closeable`; nesting is the call stack.

```ruby
T = Dexpace::Instrumentation::Tracing
T.current_span.equal?(Dexpace::Instrumentation::NO_SPAN)          # => true

# A stand-in for an adapter's recording span: any object with the seven methods (three shown;
# the mutators would return self and #finish nil).
class DemoSpan
  attr_reader :name
  def initialize(name) = @name = name
  def recording? = true
  def context = Dexpace::Instrumentation::Bundle::NONE
end
outer = DemoSpan.new("outer")
inner = DemoSpan.new("inner")
T.with_span(outer) do
  T.current_span.name                                              # => "outer"
  T.with_span(inner) { T.current_span.name }                       # => "inner"
  T.current_span.name                                              # => "outer"
end
T.current_span.equal?(Dexpace::Instrumentation::NO_SPAN)          # => true

begin
  T.with_span(outer) { raise "boom" }
rescue RuntimeError => e
  e.message                                                        # => "boom"
end
T.current_span.equal?(Dexpace::Instrumentation::NO_SPAN)          # => true  (restored by the ensure)

scope = T.activate(outer)
scope.class.name                                                   # => "Dexpace::Instrumentation::Scope"
T.current_span.name                                                # => "outer"
scope.close                                                        # => nil
T.current_span.equal?(Dexpace::Instrumentation::NO_SPAN)          # => true
```

**The cached singleton.** `OBS-25` requires the no-op span's current-scope to be a cached singleton and
the no-op path to allocate nothing per call. `activate` returns `NO_SCOPE` — one frozen object whose
`#close` does nothing — exactly when nothing is owed on close, which is an **identity** test: the span
being activated is already the current one. In an untraced application the slot holds `NO_SPAN` and every
activation is of `NO_SPAN`, so every activation returns the singleton. The test is deliberately not the
recording flag: a non-recording span activated over a *recording* one still owes that restore, and a
singleton there would leave the recording span in place after the block, which is `OBS-22`'s exact
failure.

```ruby
T.activate(Dexpace::Instrumentation::NO_SPAN).equal?(Dexpace::Instrumentation::NO_SCOPE)  # => true
```

The carrier is `Fiber[]`, never `Thread.current[]`: a span activated before a thread, a child fiber or
an enumerator is created is the current span inside each of them, and a child's own activation rebinds
the child's slot only. The slot holds one immutable span reference — never a stack — because fiber
storage's copy-on-write protects the slot and not a mutable object held in it: a span stack there would
be one shared `Array` across every descendant thread and fiber.

## Log correlation: `correlate` and the two diagnostic keys

`OBS-23` adds the second half: activating a span *for log correlation* pushes the trace id and span id
onto the diagnostic context under `trace.id` and `span.id` for the scope's lifetime, restores each on
close, and skips the push for a non-recording span. The two key names are phase 5b's
`Dexpace::Instrumentation::Diagnostics::TRACE_ID` and `::SPAN_ID`, shipped early by this phase with
`DEFAULT_KEYS` (`OBS-10`'s "exactly {trace.id, span.id}") because `Tracing` reads them; phase 5b extends
that file with the fold and the snapshot bridge. They are `Symbol`s: `Fiber.current.storage` hands every
key back as a `Symbol`, `Fiber#storage=` refuses a `String` key on every supported Ruby, and on 3.2 and
3.3 the per-key `Fiber["k"]` refuses one too — a `Symbol` is the one spelling every carrier API accepts on
every row. The ids are taken from a `Bundle` passed in, so `Tracing` has no dependency on the execution
context.

```ruby
Dexpace::Instrumentation::Diagnostics::TRACE_ID      # => :"trace.id"
Dexpace::Instrumentation::Diagnostics::SPAN_ID       # => :"span.id"
Dexpace::Instrumentation::Diagnostics::DEFAULT_KEYS  # => [:"trace.id", :"span.id"]

bundle = Dexpace::Instrumentation::Bundle.build(
  trace_id: "4bf92f3577b34da6a3ce929d0e0e4736", span_id: "00f067aa0ba902b7",
  trace_flags: "01", flavour: Dexpace::Instrumentation::TraceIdFlavour::W3C,
)
bundle.valid?                                        # => true
bundle.sampled?                                      # => true

T.with_correlated_span(outer, bundle) do
  Fiber[Dexpace::Instrumentation::Diagnostics::TRACE_ID]   # => "4bf92f3577b34da6a3ce929d0e0e4736"
  Fiber[Dexpace::Instrumentation::Diagnostics::SPAN_ID]    # => "00f067aa0ba902b7"
  T.current_span.name                                      # => "outer"
end
Fiber[Dexpace::Instrumentation::Diagnostics::TRACE_ID]     # => nil
Fiber.current.storage.key?(:"trace.id")                    # => false on 3.3 and later; true on 3.2
```

**The last line is the one place the floor differs, and it is documented rather than papered over.**
The restore is one assignment per key — `Fiber[k] = previous` — with no branch on presence, because
`Fiber[:k] = nil` deletes the key on Ruby 3.3 and later, so "restore each key to its prior value (or
remove it if previously unset)" is the same statement in both branches. On the 3.2 floor that assignment
leaves the key present with a `nil` value, and 3.2 offers no other removal than `Fiber#storage=`, the
whole-map setter that warns on every call and that core never uses. The residual is invisible to every
reader in the SDK: `Fiber[k]` reads `nil` in both states, and the diagnostic-context fold (`OBS-10`,
phase 5b) must skip keys with null values, so a nil-valued key and an absent key fold identically. The
phase's ledger records it (P5-49 and P5-72), and its matrix-facts suite pins the 3.3.0 boundary.

Two guards keep a fake trace out of the logs. A **non-recording** span skips the push and delegates to
plain activation, in the requirement's own words. And a bundle that is **not `#valid?`** — `Bundle::NONE`
and its all-zero sentinels — likewise skips the push: `OBS-26` requires an all-zero id be treated as
no-trace, and a recording span paired with `Bundle::NONE` is the only state a step can reach until phase
6 makes a populated bundle reachable, so without the guard every log line of a tracing-enabled client
would carry a trace id of thirty-two zeros.

```ruby
T.with_correlated_span(outer, Dexpace::Instrumentation::Bundle::NONE) do
  Fiber[Dexpace::Instrumentation::Diagnostics::TRACE_ID]   # => nil   (no push: the bundle is invalid)
  T.current_span.name                                      # => "outer"  (still activated)
end
T.with_correlated_span(Dexpace::Instrumentation::NO_SPAN, bundle) do
  Fiber[Dexpace::Instrumentation::Diagnostics::TRACE_ID]   # => nil   (no push: the span is non-recording)
end
```

`correlate(span, bundle)` is the handle form of the same thing, returning `NO_SCOPE` when the span is
already current and both keys already hold the bundle's values, and a `Scope` restoring all three
otherwise. Nothing here rescues: `OBS-20` and `OBS-30` make a throwing tracer the caller's problem —
"the instrumentation runtime does not defensively catch these callbacks" — and both block forms restore
through `ensure` regardless of what the block did.

## Trace-id generation and the sampled bit: `TraceIdFlavour#generate_trace_id`, `Bundle#sampled?`

`OBS-27` asks for generation in at least the W3C and Datadog flavours plus a no-op flavour that always
yields the invalid sentinel, and that a zero draw be coerced to a non-zero value. Generation is a method
on phase 4a's flavour `Data`, one branch per flavour, over `SecureRandom` — the CSPRNG path, kept
separate from the non-cryptographic UUID path `CFG-32` asks phase 5a for. The randomness source is an
optional positional argument answering `#hex(bytes)` and `#random_number(max)`, `SecureRandom`'s own two
methods, so a seeded `Random` gives a deterministic id and a test can inject a generator that draws zero,
which no amount of sampling reaches.

```ruby
w3c = Dexpace::Instrumentation::TraceIdFlavour::W3C.generate_trace_id
w3c.size                                                            # => 32
w3c.match?(/\A[0-9a-f]{32}\z/)                                      # => true
Dexpace::Instrumentation::TraceIdFlavour::W3C.valid_trace_id?(w3c)  # => true
dd = Dexpace::Instrumentation::TraceIdFlavour::DATADOG.generate_trace_id
dd.match?(/\A[0-9]{1,20}\z/)                                        # => true
Dexpace::Instrumentation::TraceIdFlavour::NONE.generate_trace_id    # => "00000000000000000000000000000000"

flavour = Dexpace::Instrumentation::TraceIdFlavour::W3C
flavour.generate_trace_id(Random.new(42)) == flavour.generate_trace_id(Random.new(42))  # => true

# A generator that always draws zero: the coercion, which is a substitution and not a redraw.
class Zero
  def hex(_bytes) = "0" * 32
  def random_number(_max) = 0
end
Dexpace::Instrumentation::TraceIdFlavour::W3C.generate_trace_id(Zero.new)      # => "00000000000000000000000000000001"
Dexpace::Instrumentation::TraceIdFlavour::DATADOG.generate_trace_id(Zero.new)  # => "1"
```

Every result is frozen and valid under its flavour, so it goes straight into `Bundle.build`. No span-id
generator ships: `OBS-26` states the span-id rule as a *validity* rule the bundle already enforces, and
core creates no spans. `Bundle#sampled?` is the one method this phase adds to the bundle — the low bit
of the two-hex-char `trace_flags` byte, over the member phase 4a stored and without a ninth member:

```ruby
Dexpace::Instrumentation::Bundle::NONE.sampled?   # => false
bundle.with(trace_flags: "00").sampled?           # => false
```

## The metrics SPI: `NO_METER`

`OBS-31`'s meter manufactures a monotonic integer counter and a floating-point histogram, each taking
per-measurement attributes; the default meter is a no-op that discards every measurement and **returns
shared instrument singletons**, and core pulls no metrics runtime in. The instruments are private
classes behind the public `NO_METER`, because sharing is assertable meter-to-meter under two different
names without naming either instrument.

```ruby
meter = Dexpace::Instrumentation::NO_METER
counter = meter.create_counter("http.client.request.count", unit: "{request}")
histogram = meter.create_histogram("http.client.request.duration", unit: "ms")
counter.equal?(meter.create_counter("anything"))                       # => true
histogram.equal?(meter.create_histogram("else"))                       # => true
counter.add(1, attributes: { "http.request.method" => "GET" }.freeze)  # => nil
histogram.record(Float::NAN)                                           # => nil
histogram.record(12.5)                                                 # => nil
```

`OBS-33` binds the counter's documentation and the histogram's tolerance: only non-negative increments
are valid, a negative delta is the caller's undefined behaviour, and the core instrument does **not**
validate that on the hot path — there is no check, deliberately; the histogram takes any input, NaN and
either infinity included, and what a concrete adapter does with a non-finite value is the adapter's.
The two instrument names above are illustrative: phase 5c fixes no name, unit or attribute set
(`OBS-32`'s OpenTelemetry conventions are post-v1 with `dexpace-instrumentation-otel`), and the names
phase 5b's step records under are that phase's constants.

## The HTTP-tracer vocabulary: `HTTPTracer`, `NULL`, `CallableAdapter`

`OBS-28`'s vocabulary richer than start/end is a **module** of eleven no-op methods in three groups —
the operation lifecycle (`operation_started`, `operation_succeeded`, `operation_failed`), the
per-attempt events (`attempt_started`, `attempt_failed` with the next delay, `retries_exhausted`) and the
transport milestones (`request_url_resolved`, `connection_acquired` with host and port, `request_sent`
and `response_received` with byte counts, `response_headers_received` with status and headers). An
implementer includes it and overrides only what it needs; the rest stay no-ops rather than becoming
`NoMethodError`s in the caller's request path, which under `OBS-30`'s no-wrapping rule is what a missing
method would be. `NULL` is the frozen instance §8.1 names, the value an unconfigured slot holds.

```ruby
Dexpace::Instrumentation::NULL.operation_started(:ctx)   # => nil
Dexpace::Instrumentation::NULL.frozen?                   # => true

class LoggingTracer
  include Dexpace::Instrumentation::HTTPTracer
  def initialize(out) = @out = out
  def attempt_failed(_context, error, next_delay) = @out << "attempt failed: #{error.message}, next in #{next_delay}s"
end
out = []
t = LoggingTracer.new(out)
t.operation_started(:ctx)                                # => nil   (the inherited no-op)
t.attempt_failed(:ctx, RuntimeError.new("timeout"), 0.5)
out                                                      # => ["attempt failed: timeout, next in 0.5s"]
```

`OBS-29` fixes the ordering an emitter must honour — started once at the start; succeeded or failed
exactly once at the end and never both; attempt events as often as there are attempts;
`retries_exhausted`, when it fires, *immediately* followed by `operation_failed` carrying the *same*
error object — and `ordering_test.rb` drives a conformant recording emitter through a succeeding and a
retry-exhausted operation by hand and asserts every clause. That test is the regression the wiring must
keep green when phase 6a's retry step emits the per-attempt group and phase 8's adapters the milestones.

`CallableAdapter` is §8.1's pub/sub shape: it wraps one `#call(name, payload)` object and forwards each
of the eleven as its name and a `Hash` of the arguments under their parameter names. It allocates that
`Hash` per event by construction, which is why it is offered and not the default, and it refuses a bus
that cannot be called at construction rather than at the first event inside a request.

```ruby
events = []
adapter = Dexpace::Instrumentation::CallableAdapter.new(->(name, payload) { events << [name, payload] })
adapter.operation_started(:ctx)
adapter.connection_acquired(:ctx, "api.example.com", 443)
events   # => [[:operation_started, {context: :ctx}], [:connection_acquired, {context: :ctx, host: "api.example.com", port: 443}]]
Dexpace::Instrumentation::CallableAdapter.new(:not_callable)
# => Dexpace::InvalidArgumentError: callable must respond to #call(name, payload)
```

## What the no-op path costs: nothing per call

`OBS-25`'s clause is "Selecting a no-op path MUST NOT allocate per call", and it holds end to end for
the untraced application: a span from the no-op tracer, an activation of it, a mutator, a finish and a
counter increment, driven a thousand times, allocate a handful of objects in total — six on 4.0.6, nine
on 3.2.11, the loop's own fixed cost — and none per iteration. The precondition is on the caller, not the
callee: every argument that crosses the loop below is a frozen constant, a Symbol or an Integer, because
an inline `String` or `Hash` literal at the call site allocates whether or not the method it is passed to
does. The suite asserts the same as a two-loop delta of exactly `0.0` per call over every no-op object.

```ruby
FROZEN = { "k" => "v" }.freeze
GC.disable
before = GC.stat(:total_allocated_objects)
1000.times do
  s = Dexpace::Instrumentation::NO_TRACER.start_span("op", attributes: FROZEN)
  Dexpace::Instrumentation::Tracing.with_span(s) { s.set_attribute("k", 1) }
  s.finish
  Dexpace::Instrumentation::NO_METER.create_counter("c").add(1, attributes: FROZEN)
end
GC.stat(:total_allocated_objects) - before   # => 6 on 4.0.6, 9 on 3.2.11 -- for a thousand iterations
GC.enable
```

## What is deliberately not here

- **A recording span, tracer or meter.** Core owns no exporter and no metrics runtime; the recording
  clauses of `OBS-21`, `OBS-29`, `OBS-30` and `OBS-31` are obligations on an implementer, stated in each
  class's documentation and asserted in the suite against fakes under `gems/dexpace-core/test/support/`
  (`RecordingSpan`, `RecordingTracer` and its factory, `RecordingMeter`, `RecordingHTTPTracer`).
- **Any emitter of the HTTP-tracer vocabulary, and any step.** The instrumentation step is phase 5b's;
  the per-attempt emitter is phase 6a's retry step; the transport milestones are phase 8's; the
  operation-lifecycle triple is a surface decision on phase 10's inbound list.
- **A registry or auto-activation.** `SEAM-2` enumerates five core seams and instrumentation is not
  one; the tracer factory is a bundle member and the meter a step keyword, both with constant no-op
  defaults, and presence-gated activation stays post-v1 with `dexpace-instrumentation-otel`
  (`docs/first-release.md` § What v1 ships without).
- **A span-id generator, an instrument name, or a `**` splat anywhere.**
