# dexpace-core

Part of the [dexpace Ruby SDK](../../README.md): an HTTP-client toolkit, not an HTTP client.
This gem is the core: the domain model, the pipeline and every seam's contract.

**Status: `0.0.0`, unpublished; the HTTP domain model, the seam layer, the byte-streaming layer,
the body layer, the recovery layer and the stage pipeline are built.** `lib/` holds phase 1's wire model -- `Dexpace::Request`, `Response`, `Headers`,
`HeaderName`, `Status`, `Method`, `Protocol`, `MediaType`, `Query`, `RequestOptions`, the
`HeaderSyntax`, `PercentEncoding` and `URL` function modules, and the construction contract
`Dexpace::Model` / `Dexpace::Builder` under the error root `Dexpace::Error` -- phase 2's seam
layer: the provider registry `Dexpace::Registry`, the `Dexpace::Transport`,
`Dexpace::AsyncTransport` and `Dexpace::Serde` seams, the `Dexpace::Bridge` pair, the async pivot
`Dexpace::Async::Future` / `Completer`, `Dexpace::Cancellation`, `Dexpace::Closeable` and
`Dexpace::Operation` -- and phase 3a's byte-streaming layer under `Dexpace::IO`: the FIFO
`Buffer`, `BufferedSource` and `BufferedSink` with the `TypedReads` and `TypedWrites`
vocabularies, `TeeSink`, `MAX_MATERIALIZED_BYTES`, and the two failure types
`Dexpace::StreamError` and `Dexpace::EndOfStreamError` -- and phase 3b's body layer, flat under
`Dexpace::`: the contract `Dexpace::Body` with its eight factories and `.buffer_bounded`, the
variants `BytesBody`, `BufferBody`, `StreamBody`, `ChunkedBody`, `FormBody`, `FileBody` and
`MultipartBody`, the single-use `ResponseBody`, the wrappers `RequestLoggingBody` and
`ResponseLoggingBody`, `TypedResponse`, and `Response#close` / `#body_string` / `#body_bytes` --
and phase 4a's execution context: the three flavours `DispatchContext`, `RequestContext` and
`ExchangeContext` sharing the module `Dexpace::Context`, the bounded process-wide
`Dexpace::ContextStore`, `Dexpace::ContextConflictError`, and the instrumentation subsystem
`Dexpace::Instrumentation` with its `Bundle`, `TraceIdFlavour` and the three no-op singletons
-- and phase 4b's recovery layer: the closed outcome `Dexpace::Outcome::Success` / `Failure`, the
`Dexpace::Recovery` namespace with `RequestChain`, `ResponseChain`, `Orchestrator`, the `Transform`
contract and the three shipped steps, `Recovery.buffer_error_body`, the errors `Dexpace::ProtocolError`
and `OutcomeError`, and the three error primitives every later phase uses: the suppressed trail
`Dexpace::Suppressible` with `Dexpace.attach_suppressed` / `.suppressed`, and `Dexpace.each_cause`
-- and phase 4c's stage pipeline: `Dexpace::Pipeline` with its nested `Stages` (sixteen stage
constants, `ALL`, `PILLARS`, `.of`), `Stage`, `Step`, `Entry`, `Cursor`, `Builder` and
`TransformStep`, `Dexpace::AsyncPipeline` with `.map_response`, and `Dexpace::PipelineError`
-- and phase 5a's configuration layer: `Dexpace::Configuration` with its `Builder`, `Keys` and
`Sources`, the slot `Dexpace.configure` / `.configuration` / `.reset_config!`, `Dexpace::Clock`
with `SYSTEM` and `.deadline_in`, `Dexpace::Async.delay` and the `deadline:` keyword on the
future, `Dexpace::Proxy` with `Type`, `HostPattern` and `.resolve`, `Dexpace::HTTPDate`,
`Dexpace::UUID`, `Dexpace::Retryability` and `Dexpace::BuildInfo`, plus `ContextStore.default`
and `Dexpace::IO.max_materialized_bytes` reading the chain
-- and phase 5c's tracing and metrics layer, all under `Dexpace::Instrumentation`: the protocols
of `NO_SPAN`, `NO_TRACER` and `NO_TRACER_FACTORY` (given to the same three objects in place),
`Tracing` with `.current_span`, `.activate`, `.with_span`, `.correlate` and
`.with_correlated_span`, `Scope` and `NO_SCOPE`, `TraceIdFlavour#generate_trace_id` and
`Bundle#sampled?`, the vocabulary `HTTPTracer` with `NULL` and `CallableAdapter`, `NO_METER` over
the `_Meter` / `_Counter` / `_Histogram` interfaces, and phase 5b's three `Diagnostics` constants
shipped early. Nothing else yet: the pillar step families, the instrumentation step and every
adapter are later phases', nothing emits a trace or a metric, and no transport ships here, so
nothing talks to a socket. The as-built pages are `docs/sdk-documentation/http.md`,
`docs/sdk-documentation/seams.md`, `docs/sdk-documentation/io.md`, `docs/sdk-documentation/body.md`,
`docs/sdk-documentation/execution-context.md`, `docs/sdk-documentation/recovery.md`,
`docs/sdk-documentation/pipelines.md`, `docs/sdk-documentation/configuration.md` and
`docs/sdk-documentation/tracing-and-metrics.md`.

## Install

```ruby
# Gemfile
gem "dexpace-core"
```

## The smallest thing that works today

```ruby
require "dexpace"

builder = Dexpace::Request.builder
builder.url = "https://api.example.test/widgets"
request = builder.header("Accept", "application/json").build

request.method                  # => Dexpace::Method::GET, defaulted because there is no body
request.headers["accept"]       # => ["application/json"], looked up case-insensitively
request.with(body: "x")         # raises Dexpace::InvalidArgumentError: a GET carries no body
```

Every type is frozen at construction, validated in its constructor, and derived through
`#with` or `#new_builder` rather than mutated; a caller mistake raises
`Dexpace::InvalidArgumentError`, which is also an `ArgumentError`.

A transport is any object responding to `#call(request, options, cancellation)`, so the seam
layer works end to end with a lambda standing in for the adapter phase 8 ships:

```ruby
operation = Dexpace::Operation.build(
  method: "GET", template: "/pets/{id}", projections: { id: [:path, "id"], limit: [:query, "limit"] },
)
request = operation.build_request(base_url: "https://api.example.test/v1", inputs: { id: "a/b", limit: 1 })
request.url.to_s               # => "https://api.example.test/v1/pets/a%2Fb?limit=1"

Dexpace::Transport.swap(->(req, _options, _cancellation) { req.url.to_s }) do
  Dexpace::Transport.resolve.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
end
Dexpace::Transport.resolve     # raises Dexpace::SeamError: no transport provider is registered
```

Bytes stream through `Dexpace::IO`: a buffered source over any `#readpartial`-shaped stream owns
it, reads through Ruby's own `#read`/`#readpartial` (so `IO.copy_stream` can drive it) or the
tail-appending primitive `#read_into`, and hands out non-consuming views; a tee mirrors a bounded
tap while the wire body goes through untouched:

```ruby
require "stringio"

Dexpace::IO::BufferedSource.wrapping(StringIO.new("one\ntwo")) do |source|
  source.peek.read_line_utf8   # => "one", and the source's cursor has not moved
  source.read_exactly(4)       # => "one\n".b -- every byte that comes back is BINARY
  source.read_utf8             # => "two"
end                            # closes the StringIO: wrapping takes ownership

tee = Dexpace::IO::TeeSink.new(primary: Dexpace::IO::Buffer.new, tap_limit: 3)
tee.write("héllo")             # => 6, the byte count; the tap keeps "h\xC3\xA9", the primary all of it
```

A body is a `Dexpace::Body`: one write-to-sink operation, a media type, a length with `-1` for
unknown, and a replayability every factory classifies by source. A response body is single-use
and owns its transport stream; `Response#body_string` is the one place bytes become text:

```ruby
body = Dexpace::Body.form([["q", "a b"]])
body.replayable?               # => true
body.each.to_a                 # => ["q=a+b"], the form encoder, never the RFC 3986 one

source = Dexpace::IO::BufferedSource.of_bytes("caf\xE9".b)
media = Dexpace::MediaType.parse("text/plain; charset=iso-8859-1")
res = Dexpace::ResponseBody.new(source: source, media_type: media)
res.preview(cap: 3)            # => "caf", through a fresh view; the primary path has not moved
response.body_string           # => "caf\xE9" tagged ISO-8859-1, and the body is closed
```

One thing to know before writing `include Dexpace` in a class of your own: `Dexpace::IO` shadows
`::IO` there, so `x.is_a?(IO)` is silently false for a real `IO`. Write `::IO`
(`docs/sdk-documentation/io.md` says why).

## Depends on

Nothing. `dexpace-core.gemspec` has no `add_dependency` line, and `rake gates:gemspec_audit` asserts
it stays that way (`SEAM-1`, `NFR-1`).

## Where to read next

- `docs/sdk-documentation/http.md` -- the domain model as built: what each type guarantees.
- `docs/sdk-documentation/seams.md` -- the seam layer as built: what a transport, a codec and a
  future are, and how a provider is resolved.
- `docs/sdk-documentation/io.md` -- the byte-streaming layer as built: the two read primitives,
  the ownership rule, views, the buffer, the tee, and the `Dexpace::IO` shadow.
- `docs/sdk-documentation/body.md` -- the body layer as built: the contract and its factories,
  what each body closes, the two logging regimes, the decode boundary, and the typed response.
- `docs/sdk-documentation/execution-context.md` -- the execution context as built: the bundle
  and its sentinels, the promotion chain, the call key and what its equality costs, the bounded
  store and the identity rule of `#close`.
- `docs/sdk-documentation/recovery.md` -- the recovery layer as built: the outcome, the two chains
  and who closes the response, the orchestrator and its unwrap, the three shipped steps, the error
  trail and the cause walk.
- `docs/sdk-documentation/pipelines.md` -- the stage pipeline as built: the sixteen stages, the
  builder's pillar rules and surgical edits, the cursor's fork and stage-scoped state, the two
  runtimes, the transform adapter, and why the bridges are phase 2's.
- `docs/sdk-documentation/configuration.md` -- the configuration layer as built: the four-tier
  chain and its order, the typed accessors, the builder and the slot, the keys and the two layers
  that read them, the clock and the deadline, the proxy and its resolver, and the utilities.
- `docs/sdk-documentation/tracing-and-metrics.md` -- the tracing and metrics layer as built: the
  no-op protocols, the current span and its scope handle, log correlation and the floor's
  residual, trace-id generation, the HTTP-tracer vocabulary and its ordering contract, the no-op
  meter, and what the no-op path costs.
- `docs/sdk-documentation/architecture.md` -- how the gems compose and which one to install.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` -- the gem layout and the
  zero-dependency invariant every gem here is built under.
