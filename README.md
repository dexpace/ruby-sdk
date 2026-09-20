<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/dexpace-wordmark-dark.svg">
    <img alt="dexpace" src="docs/assets/dexpace-wordmark-light.svg" width="320">
  </picture>
</p>

<h1 align="center">Dexpace Ruby SDK</h1>

The Ruby SDK for dexpace: **an HTTP-client toolkit, not an HTTP client.** It is for authors of
generated or hand-written service-client SDKs who need the correctness-sensitive plumbing —
idempotency-aware retry, redirects that never leak a bearer token cross-origin, RFC 7235/7616
authentication, pagination, SSE, three-state PATCH — solved exactly once, and it deliberately does
not compete with `faraday` or `httpx` on the easiest way to fetch a JSON endpoint.

## Status

**Phases 0, 1, 2, 3a, 3b, 4a, 4b, 4c, 5a, 5b, 5c, 6a, 6b, 6c, 7b, 7c, 7a and 8a are built.** Nothing is published. The repository holds six gems under
`gems/`, every one at `0.0.0`. `dexpace-core` carries the HTTP domain model — the frozen,
validated wire types every later phase stands on (`docs/sdk-documentation/http.md`) — the seam
layer: the provider registry, the transport and codec seams, the core-owned async pivot,
cancellation, the close contract and the operation projection (`docs/sdk-documentation/seams.md`)
— the byte-streaming layer every body stands on: the FIFO buffer, the buffered source and sink
with typed reads and non-consuming views, and the tee sink (`docs/sdk-documentation/io.md`) — and
the body layer: one body contract with eight factories over seven request-body variants, the
single-use response body, the materialize-once guard, the bounded error copy, the two logging
wrappers, the one decode boundary and the lazy typed response
(`docs/sdk-documentation/body.md`) — and the execution context: the three-flavour promotion chain,
the call-unique key, the bounded process-wide store and the instrumentation bundle every context
carries (`docs/sdk-documentation/execution-context.md`) — and the recovery layer: the closed two-variant outcome, the
two folds over frozen step lists, the orchestrator that lets no throwable past it, the three shipped
steps, and the error trail, the cycle-safe cause walk and the protocol error the whole SDK uses from
here on (`docs/sdk-documentation/recovery.md`) — and the stage pipeline: sixteen totally ordered
stages, a builder with pillar rules and surgical edits, a forward-only per-call cursor with a
pillar-only fork and stage-scoped state, a sync runtime and an async mirror that are both
transports, and the adapter that installs a recovery transform
(`docs/sdk-documentation/pipelines.md`) — and the configuration layer: the four-tier chain with its
never-throw typed accessors, builder and process-wide slot, the injectable clock with its
cancellable wait and the deadline the future gained, the proxy model and its never-raising
resolver, and the RFC 1123 date, UUID, retryability and build-info utilities
(`docs/sdk-documentation/configuration.md`) — and the tracing and metrics layer: the span, tracer
and tracer-factory protocols behind the three no-op singletons, the current-span carrier and its
scope handle, log correlation over the two diagnostic-context keys, trace-id generation and the
sampled bit, the HTTP-tracer vocabulary with its ordering contract, and the no-op meter
(`docs/sdk-documentation/tracing-and-metrics.md`) — and the logging facade and redaction: the
duck-typed sink and the closed severity set, the logger and the accumulating event with its inert
twin, the redactor and its default-deny policy, the diagnostic-context fold and snapshot bridge,
the containment every emission runs inside, the body preview, the HTTP logging level and its two
keys, and the instrumentation step on both runtimes — the one thing that starts a span and records
the two metrics per request (`docs/sdk-documentation/logging-and-redaction.md`) — and the retry
layer: one policy core with its two-axis classifier consult, backoff calculator, total
pacing-header parser and tuning constants, the re-sendability gate, the one configuration object
both stacks build from, the stage-based retry step on both runtimes with its iterative async
trampoline, and the recovery-chain retry beneath the orchestrator with its total-timeout budget —
the three drivers that emit the HTTP-tracer vocabulary's per-attempt group
(`docs/sdk-documentation/retry.md`) — and the authentication layer: the closed scheme set and the
pure three-tier resolver, the four credentials that redact in every rendering, the never-raising
RFC 7235 challenge parser, the Basic and Digest handlers with the chain that composes them, the
static key stamper, the bearer stamper on each runtime with its single-flight refresh, and the
AUTH pillar step on both runtimes with its HTTPS guard, its cursor-read cross-origin suppression
and its 401 replay (`docs/sdk-documentation/auth.md`) — and the redirect layer: the synchronous
redirect pillar step that forks per hop with the cross-origin marker as cursor state, strips
`Authorization` before every re-issue and judges cross-origin against the seed origin, the
read-only condition snapshot a predicate receives, the layer's event and key vocabulary, the
scheme-downgrade and not-replayable errors, the second re-sendability predicate, and the two
`standard` constructors phase 4c postponed — `Pipeline.standard` and `AsyncPipeline.standard` with
its required `redirect: :unsupported` (`docs/sdk-documentation/redirect.md`) — and the
server-sent-events layer: the WHATWG line machine over `BufferedSource#getbyte` with its two
documented, rejecting caps, the immutable five-field event, the field machine whose one persistent
state is the BOM flag, the resource-owning single-pass stream facade with its three factories and
its two consumption shapes, the typed adapter over a caller-supplied mapper with `SKIP` and `DONE`,
and the eighteenth gate, `gates:serde_boundary`, a parsed scan that keeps the layer and the
pagination layer free of any serialization dependency (`docs/sdk-documentation/sse.md`) — and the
pagination layer: the page value that owns one live response, the strategy contract with its three
built-in strategies over a caller-supplied extractor and never a codec, the byte-for-byte query
splice, the eager-closing item view and the single-use, look-ahead page view over one private walk,
the blocking engine, the non-blocking engine driven through `Future#on_settle` as a re-arm
trampoline, the fetcher front-end, and `URL.resolve` (`docs/sdk-documentation/pagination.md`) — and the
serialization layer: the witness protocol with its decode context, three container combinators, a named
boolean witness and an ISO-8601 witness, the three-state PATCH type with its decode combinator, the
native-form encode walk that makes tri-state PATCH structural, `Body.serialized`, and the two response
handlers phase 3b's `TypedResponse` was built to take (`docs/sdk-documentation/serde.md`).
`dexpace-serde-json` holds the JSON codec over one private `JSON::Coder` per instance, the
`json >= 2.19.9` floor in its gemspec and asserted at require time, and the seam registration under
`:json` — the first gem here with a third-party dependency, and the first the three zero-dependency
gates have run against with one; the operation-lifecycle and transport groups of the HTTP-tracer
vocabulary are emitted by nothing yet.
`dexpace-transport-net_http` carries the synchronous transport — the first thing here that talks
to a socket: two constructions over a fresh-per-call or a borrowed `Net::HTTP`, the header policy
the wire carries, a per-response producer thread behind every streamed body, one total budget
across three native knobs, a classifier that asks the cancellation token first and wraps every
other failure retryable, TLS settings and the proxy over the configuration chain
(`docs/sdk-documentation/transport-net_http.md`) — and `dexpace-conformance` carries the
conformance suite: the assertion protocol, the twenty-eight-assertion transport suite with its
vacuous and waived rows, the plaintext wire fixture, the Minitest and RSpec drivers and the two
observability doubles (`docs/sdk-documentation/conformance.md`). The other two are still
skeletons — a namespace, a `VERSION`, a gemspec, a signature mirror and a smoke suite:

| Gem | Namespace | Runtime dependencies today |
|---|---|---|
| `dexpace-core` | `Dexpace` | none |
| `dexpace-transport-net_http` | `Dexpace::Transport::NetHTTP` | `dexpace-core`; `net-http >= 0.4` |
| `dexpace-transport-async_http` | `Dexpace::Transport::AsyncHTTP` | `dexpace-core` |
| `dexpace-serde-json` | `Dexpace::Serde::JSON` | `dexpace-core`; `json >= 2.19.9` |
| `dexpace-async-thread` | `Dexpace::Async::Thread` | `dexpace-core` |
| `dexpace-conformance` | `Dexpace::Conformance` | `dexpace-core` |

What phase 0 does ship is the gate set every later phase is written under: seventeen blocking
checks in one `bundle exec rake` — eighteen since phase 7b added `gates:serde_boundary` — each proven
by a deliberately failing input, and a CI matrix that runs the real suite on Ruby 3.2, 3.3, 3.4 and
4.0 (`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-checklist.md`).

## Working in the repository

```bash
bundle install          # Gemfile.lock is not committed; each Ruby resolves its own
bundle exec rake        # every gate, in order
bundle exec rake -T     # each gate is separately invocable
```

`CLAUDE.md` is the working summary — the hard rule on what `dexpace-core` may `require`, the
requirement-ID conventions, the constraints that will bite — and `docs/README.md` is the index
of everything under `docs/`: the normative specification, the port design, the harvested
knowledge corpus, the as-built documentation and the per-phase process records.

## License

MIT — see [`LICENSE`](./LICENSE). Every gem ships a byte-identical copy.
