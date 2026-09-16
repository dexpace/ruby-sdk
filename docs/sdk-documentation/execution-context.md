# The execution context

**As built by phase 4a, in `dexpace-core`, written against source on 2026-09-16.** This page says
what one in-flight call carries from before its request exists to after its response has arrived:
three immutable context flavours forming a one-way promotion chain, one call-unique key they share,
one bounded process-wide store they register in, and the instrumentation bundle every one of them
holds. What each is *required* to do is `docs/product-spec/07-execution-context-model.md`; how the
design maps it to Ruby is `docs/sdk-design-ruby/05-pipeline-architecture.md` §5.4 and
`docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.1; the per-requirement proof is
`docs/work/mvp/phase4/phase4a/2026-09-08-phase4a-execution-context-checklist.md`. Signatures live in
`gems/dexpace-core/sig/dexpace/`, and this page does not restate them. Every example below was run
against the built code on 4.0.6 and 3.2.11 and printed the same on both.

**Nothing in v1 drives this chain for you.** No pipeline step, recovery step or transport
constructs or promotes a context (`docs/first-release.md` § What v1 ships without records why that
is conforming): a generated client builds the head, promotes it as its request and its response
come into being, and closes the last link. This page is written for that author.

## The bundle: `Dexpace::Instrumentation::Bundle`

Every context carries a **bundle** — the correlation metadata that lets logs, metrics and spans
across the three stages correlate into one trace (`CTX-14`). It is a frozen `Data` of eight members
— `trace_id`, `span_id`, `trace_flags`, `trace_state`, `flavour`, `remote`, `span`, `tracer_factory`
— and one derived predicate, `#valid?`, which is a function of the two identifiers rather than a
ninth member: `OBS-26` makes "an all-zero trace/span id MUST be treated as invalid" a MUST, so a
bundle cannot be told it is valid while carrying a sentinel. `#remote?` reads `remote` as a
predicate.

The untraced bundle is **`Bundle::NONE`**, one shared frozen object carrying `OBS-26`'s reserved
sentinels — 32 hex zeros, 16 hex zeros, flags `"00"`, an empty state — and the two no-op singletons:

```ruby
bundle = Dexpace::Instrumentation::Bundle::NONE
bundle.trace_id                                         # => "00000000000000000000000000000000"
bundle.span_id                                          # => "0000000000000000"
bundle.trace_flags                                      # => "00"
bundle.trace_state                                      # => []
bundle.flavour.name                                     # => :none
bundle.valid?                                           # => false
bundle.remote?                                          # => false
bundle.span.equal?(Dexpace::Instrumentation::NO_SPAN)   # => true
bundle.tracer_factory.tracer.equal?(Dexpace::Instrumentation::NO_TRACER)  # => true
bundle.frozen?                                          # => true
```

**`NONE` is available as the default and is never defaulted for you.** `bundle:` is a required
keyword on every context builder, and `trace_id:`, `span_id:` and `flavour:` are required on
`Bundle.build`, so "I forgot to pass a trace id" is a `missing keyword` and not a silently untraced
call — every untraced call's identifiers are identical (`CTX-15`), which is exactly why an accident
would be invisible downstream. A caller who wants the untraced value names `NONE`.

A real bundle is built through `Bundle.build` and validated member by member: the trace id must be
one its flavour renders, the span id 16 lowercase hex characters or the sentinel, the flags two
lowercase hex characters, the state a list of `[String, String]` pairs (a list, not a `Hash` —
W3C `tracestate` is ordered). Lowercase is enforced rather than folded: `0A` is rejected where the
wire form is `0a`. The state list is deep-copied and deep-frozen at construction, so the caller's
array is untouched and the bundle's cannot be reached through it.

```ruby
traced = Dexpace::Instrumentation::Bundle.build(
  trace_id: "4bf92f3577b34da6a3ce929d0e0e4736", span_id: "00f067aa0ba902b7",
  flavour: Dexpace::Instrumentation::TraceIdFlavour::W3C, trace_flags: "01",
  trace_state: [%w[vendor value]], remote: true,
)
traced.valid?                    # => true
traced.remote?                   # => true
traced.trace_state.frozen?       # => true

Dexpace::Instrumentation::Bundle.build(
  trace_id: "4BF92F3577B34DA6A3CE929D0E0E4736", span_id: "00f067aa0ba902b7",
  flavour: Dexpace::Instrumentation::TraceIdFlavour::W3C,
)                                # raises Dexpace::InvalidArgumentError,
                                 #   "trace_id does not match flavour :w3c"
```

`Bundle` follows the construction pattern every core model does (`new` is private, `.build`
validates, `#with` routes through `.build` on every supported Ruby), so
`Bundle::NONE.with(trace_id: real, span_id: real, flavour: W3C)` is validated exactly as a fresh
build is. That is how phase 5 will populate it; the contract phase 5 inherits — may add methods,
may not add, rename or remove a member, store validity, change the sentinels, replace the flavour
type with a `Symbol` or hand `Bundle` a second `NONE` — is the design's R3.

### The flavour: `TraceIdFlavour`

`OBS-27`'s trace-id encodings, as a closed set of frozen values with an `.of` factory:
`TraceIdFlavour::NONE`, `::W3C` (32 lowercase hex) and `::DATADOG` (a 64-bit unsigned integer as a
decimal string), in `::ALL`. Each carries the pattern a renderable trace id matches, the flavour's
own reserved sentinel, and for `DATADOG` the numeric bound a digit count cannot express. Two
predicates: `#valid_trace_id?` (renderable and not the sentinel) and `#renders?` (renderable or the
sentinel — what a bundle may carry). They disagree at exactly one input, the sentinel.

```ruby
Dexpace::Instrumentation::TraceIdFlavour.of(:datadog).max_value   # => 18446744073709551615
Dexpace::Instrumentation::TraceIdFlavour::W3C.valid_trace_id?("0" * 32)  # => false
Dexpace::Instrumentation::TraceIdFlavour::W3C.renders?("0" * 32)         # => true
```

**The flavour governs the trace id only.** `OBS-26` states the span-id rule unqualified and
`OBS-27`'s flavours scope only the trace id, so a Datadog bundle carries a decimal trace id and a
16-hex span id — odd to read, and what the two requirements say together. The span-id sentinel is
the one constant `Bundle::INVALID_SPAN_ID`; the trace-id sentinel is a property of the flavour,
because `DATADOG`'s own zero draw is `"0"` while `OBS-26`'s reserved value is 32 hex zeros.

### The two no-op singletons

`Dexpace::Instrumentation::NO_SPAN`, `NO_TRACER` and `NO_TRACER_FACTORY` are three frozen objects
whose classes are private. Phase 4 fixes the slots and the identity of the objects filling them;
phase 5c gives their classes the span and tracer protocols, and the objects keep their identity, so
`OBS-25`'s "selecting a no-op path MUST NOT allocate per call" is assertable with `equal?` and stays
true across that widening. Today `NO_SPAN` and `NO_TRACER` answer nothing beyond `Object`, and the
factory answers exactly one method, `#tracer`, whose parameter list is `opentelemetry-api` 1.11.0's
own `TracerProvider#tracer` so that an application already running OpenTelemetry can hand its
`tracer_provider` straight to `Bundle.build(tracer_factory:)`:

```ruby
factory = Dexpace::Instrumentation::NO_TRACER_FACTORY
factory.tracer("my-lib", "1.0").equal?(Dexpace::Instrumentation::NO_TRACER)                 # => true
factory.tracer(name: "my-lib", version: "1.0", attributes: {}).equal?(Dexpace::Instrumentation::NO_TRACER)  # => true
factory.method(:tracer).parameters
# => [[:opt, :deprecated_name], [:opt, :deprecated_version], [:key, :name], [:key, :version], [:key, :attributes]]
```

It is safe to call from any thread because it holds no state (`CTX-20`).

## The chain: `DispatchContext` → `RequestContext` → `ExchangeContext`

Three flat `Data` classes, each including `Dexpace::Context`, each frozen on construction. The
head, **`Dexpace::DispatchContext`**, exists before any request does and carries `bundle`,
`call_key` and `store`. **`#promote_to_request(request:, operation_name: nil)`** returns a
`RequestContext` that carries the same three members forward — the same objects, not copies — and
adds the request; the operation name enters here as an argument, because the head has no such
field. **`#promote_to_exchange(response:)`** on a `RequestContext` returns an `ExchangeContext`
carrying all five forward and adding the response. `ExchangeContext` has no promotion method at
all: the chain is one-way and the exchange stage is terminal (`CTX-1`), enforced by the absence of a
method rather than by a guard.

```ruby
request = Dexpace::Request.builder.tap { |b| b.url = "https://api.example.test/pets" }.build
response = Dexpace::Response.builder.tap do |b|
  b.request = request
  b.protocol = Dexpace::Protocol::HTTP_1_1
  b.status = 200
end.build

store = Dexpace::ContextStore.new(cap: 8)     # a private store for the example; see below
dispatch = Dexpace::DispatchContext.build(bundle: bundle, store: store)
dispatch.call_key       # => "00000000000000000000000000000000:0000000000000000:1"
store.size              # => 0    -- construction registers nothing (CTX-17)
dispatch.close          # => false -- a never-promoted head closes as a no-op

request_ctx = dispatch.promote_to_request(request: request, operation_name: "ListPets")
request_ctx.class                                   # => Dexpace::RequestContext
request_ctx.call_key.equal?(dispatch.call_key)      # => true
request_ctx.bundle.equal?(dispatch.bundle)          # => true
request_ctx.operation_name                          # => "ListPets"
store.size                                          # => 1    -- the first promotion is the first entry
store[dispatch.call_key].equal?(request_ctx)        # => true

exchange_ctx = request_ctx.promote_to_exchange(response: response)
exchange_ctx.class                                  # => Dexpace::ExchangeContext
store.size                                          # => 1    -- the same slot, overwritten (CTX-3)
store[dispatch.call_key].equal?(exchange_ctx)       # => true
exchange_ctx.respond_to?(:promote_to_request)       # => false
```

**Construction registers nothing; promotion registers the successor.** `.build` on any flavour —
`DispatchContext.build(bundle:, call_key: nil, store:)`, `RequestContext.build(bundle:, request:,
operation_name: nil, call_key: nil, store:)`, `ExchangeContext.build(bundle:, request:, response:,
operation_name: nil, call_key: nil, store:)` — touches no store, so an off-chain context is a value
and nothing else. The two `#promote_*` methods are the only callers of `ContextStore#set` in core.

`#with` is not a promotion and cannot be used as one: it reaches only the members its own flavour
declares (`dispatch.with(request: r)` raises `ArgumentError: unknown keyword`), so the promotion
methods are the only way to add an artefact, which is what keeps registration on the promotion
path.

### The operation name

`RequestContext#operation_name` and `ExchangeContext#operation_name` carry a schema-defined
operation id — `"ListPets"` — or `nil`; an empty string is refused, and so is anything that is not a
`String` (a Symbol spelling of the same id included), with `Dexpace::InvalidArgumentError`
`operation_name must be a String`. It is carried forward unchanged
and is **advisory only**: it influences neither the request, nor any dispatch decision, nor the
store key (`CTX-16`). It is the chain half of `SEAM-28`'s postponed operation identifier; the
tracing seam that will read it is phase 5c's.

### Closing

`#close` on any link is `store.release(self)`: the slot is cleared **only when its current
occupant is this very object** — reference identity, never value equality — and the return value
says whether it was. So closing the exchange context evicts it; closing the request context it was
promoted from is a no-op, because the slot now holds the successor; closing twice is a no-op; and a
context has no closed latch to carry, because a frozen `Data` cannot hold one and the store already
answers the question.

```ruby
request_ctx.close                                   # => false -- promoted intermediate, no-op (CTX-10)
store[dispatch.call_key].equal?(exchange_ctx)       # => true
exchange_ctx.close                                  # => true  -- the occupant, evicted
store[dispatch.call_key]                            # => nil
exchange_ctx.close                                  # => false -- already gone, still a no-op (CTX-18)
```

**Close the furthest link you reached.** There is no block form on the head for that reason: a
block around `DispatchContext.build` would close the head — a no-op — and leak the exchange context
that actually occupies the slot. The bounded cap below is the backstop for a chain nobody closes,
and it is the *only* backstop: nothing here is held weakly (`CTX-19`).

## The key, and what equality costs

Every context carries a **call key**, a frozen `String` unique per call across the whole process
and all three flavours (`CTX-4`, `CTX-6`). Absent an explicit one, it is minted as
`"traceId:spanId:n"` from the bundle's two identifiers and a process-wide counter — the counter is
what keeps it unique when every untraced call shares `NONE`'s identical identifiers. The key
participates in value equality, and that has a consequence worth reading twice:

```ruby
a = Dexpace::DispatchContext.build(bundle: bundle, store: store)
b = Dexpace::DispatchContext.build(bundle: bundle, store: store)
a == b                          # => false -- two default-constructed contexts are never equal (CTX-5)
a.call_key == b.call_key        # => false
```

Two contexts built from the same bundle with otherwise identical fields are **not** equal, because
their minted keys differ. A caller who needs value equality pins a shared key with `call_key:` at
construction — the one escape hatch, and the one way to make two contexts that are `==` and not
`equal?`, which is exactly the pair the identity rule of `#close` is about:

```ruby
c = Dexpace::DispatchContext.build(bundle: bundle, store: store, call_key: "shared")
d = Dexpace::DispatchContext.build(bundle: bundle, store: store, call_key: "shared")
c == d                          # => true
c.equal?(d)                     # => false
store.set(c)
store.release(d)                # => false -- a value-equal sibling does not evict the occupant (CTX-9)
store["shared"].equal?(c)       # => true
store.release(c)                # => true
```

A pinned key must be a non-empty `String` — a Symbol or an Integer is refused with
`Dexpace::InvalidArgumentError` `call_key must be a String` rather than keying a slot no `String`
lookup finds — and is frozen without aliasing the caller's `String`; it restores equality only
between contexts built against the same store object, since `store` is a member too.

## The store: `Dexpace::ContextStore`

One process-wide registry of in-flight chains, keyed by call key, safe to use from any thread
without external locking (`CTX-7`). **`ContextStore.default`** is the one process-wide instance,
built at load with the cap **`ContextStore::MAX_TRACKED_CONTEXTS`** (1024, the one number the
specification supplies for a store of this shape); every context builder defaults `store:` to it.
`ContextStore.new(cap:)` builds a private one — what a test uses, and where phase 5's
configuration will attach a configured cap without changing a signature.

Two ways in, both taking a context and reading `#call_key` off it (`CTX-8`): **`#set`** is
install-or-replace and never raises — what promotion uses — and **`#put`** installs only if the slot
is empty and otherwise raises `Dexpace::ContextConflictError`, whose `#call_key` and message name
the key. Under a race, exactly one `#put` wins. Two ways out: **`#[](call_key)`** answers the
occupant or `nil` for an unknown or evicted key, never raising (`CTX-18`), and **`#release(context)`**
is the identity-conditional eviction `#close` delegates to. **`#size`** is the only aggregate read;
there is no iteration, deliberately.

```ruby
store.put(c)
store.put(d)                    # raises Dexpace::ContextConflictError
                                #   e.call_key  # => "shared"
                                #   e.message   # => "a context is already registered under call key \"shared\" (CTX-8)"
store.set(d).equal?(d)          # => true -- install-or-replace
```

**The cap is a hard bound and the leak backstop.** After every insert the store drains back to its
cap by evicting the oldest registration first (`CTX-11`, `CTX-12`); re-setting a key through
promotion does not refresh its position. `CTX-13` grants the store latitude over which entry goes,
and forbids relying on any particular one surviving — including the one just inserted — which core
obeys structurally: nothing in core reads a context back out. A chain nobody closes therefore
costs at most the cap's worth of entries, and never a collection mid-call: the map is a strong
`Hash`, and a custom cop, `Dexpace/NoWeakReferences`, refuses `ObjectSpace::WeakMap`,
`ObjectSpace::WeakKeyMap` and `WeakRef` in every gem's `lib/` (`CTX-19`).

```ruby
small = Dexpace::ContextStore.new(cap: 2)
first = Dexpace::DispatchContext.build(bundle: bundle, store: small).promote_to_request(request: request)
Dexpace::DispatchContext.build(bundle: bundle, store: small).promote_to_request(request: request)
Dexpace::DispatchContext.build(bundle: bundle, store: small).promote_to_request(request: request)
small.size                      # => 2
small[first.call_key]           # => nil   -- the oldest registration went
first.close                     # => false -- and closing it is still a well-defined no-op
Dexpace::ContextStore::MAX_TRACKED_CONTEXTS                                  # => 1024
Dexpace::ContextStore.default.equal?(Dexpace::ContextStore.default)          # => true
```

**The store is process-wide, not fiber-scoped.** `Fiber[:key]` is the SDK's diagnostic-context
carrier (`CLAUDE.md`, "Constraints that will bite"); the execution context is not stored there and
must not be: a context registered on one thread is found by `store[key]` from a child fiber, a new
thread and an enumerator's internal fiber alike, because a bounded, reachable, closeable registry is
the opposite design from an inherited per-fiber map.

## What to know before writing against it

- **Every context is frozen** and every member it holds is the object it was given; a `Response`
  reachable through a registered `ExchangeContext` stays reachable — body and connection included —
  until the chain is closed or the cap evicts it. Close what you promote.
- **`#inspect` on a registered context walks the store.** `store` is a member, so `Data`'s
  generated `#inspect` prints one level of every other occupant; at 1024 entries with real
  request/response graphs, `p ctx` and a failing `assert_equal` on whole contexts are dumps of every
  in-flight call. Compare members, not contexts; a redaction-aware rendering is phase 5's.
- **`Dexpace::Context` is a module the three flavours include, not a namespace**, so `Request` and
  `Response` inside `module Dexpace` keep meaning phase 1's types; the flavours are flat under
  `Dexpace::` and the instrumentation subsystem keeps its own namespace.
- **`Dexpace::BoundedMap` and `Dexpace::CallKey` are private.** The map is the one bounded-keyed-map
  implementation later phases share (`AUTH-19`'s nonce counters, `XCUT-14`'s audit), reachable by a
  bare name from inside a `module Dexpace; …` body only; the key format is a reference choice a
  port may change. Neither is part of the locked API.
- **What this page does not show, because it is not built:** a pipeline that promotes the chain,
  a tracer or span that does anything, a configured cap. The first two are phases 4c, 5c and 6a's;
  the third is phase 5a's.
