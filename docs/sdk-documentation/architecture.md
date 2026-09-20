# Architecture

**As-built docs land here gem by gem, as they land in `gems/`.** Phase 0 built the six gem
skeletons and the gate set, phase 1 the HTTP domain model in `dexpace-core`, phase 2 the seam
layer in the same gem, phase 3a the byte-streaming layer beneath every body, phase 3b the body
layer on top of it, phase 4a the execution context one in-flight call carries, phase 4b the
recovery layer and the error trail, phase 4c the stage pipeline, phase 5a the configuration
layer and the clock, phase 5c the tracing and metrics layer, phase 5b the logging facade and
redaction, phase 6a the retry layer — one policy core and its two stacks — phase 6c the
authentication layer, phase 6b the redirect layer with the two `standard` pipeline
constructors and phase 7b the server-sent-events layer with the serde-boundary gate; the adapters
are still to come, so this page is still a stub: it names the
pages this tree will eventually hold and where each one's content will come from, so the plan for
the documentation exists before the documentation does. Fifteen pages are real already, because
their subjects are: [`quality-gates.md`](./quality-gates.md), [`http.md`](./http.md),
[`seams.md`](./seams.md), [`io.md`](./io.md), [`body.md`](./body.md),
[`execution-context.md`](./execution-context.md), [`recovery.md`](./recovery.md),
[`pipelines.md`](./pipelines.md), [`configuration.md`](./configuration.md),
[`tracing-and-metrics.md`](./tracing-and-metrics.md),
[`logging-and-redaction.md`](./logging-and-redaction.md), [`retry.md`](./retry.md),
[`auth.md`](./auth.md), [`redirect.md`](./redirect.md) and [`sse.md`](./sse.md).
Once `dexpace-core` and the first adapters ship, this page becomes the same kind of front door the
sibling Node SDK's `docs/sdk-documentation/architecture.md` is — package by package, seam by seam
— and the entries below turn from plain text into real links, one at a time, as each page is
actually written against source.

## Planned pages

[http.md](./http.md) — the domain model: `Request`, `Response`, `Headers`, `Status`, `Query`, and
their kin, and how each is frozen at construction and reachable only through a builder or a
validating factory. Written against the model phase 1 shipped; derives from
`docs/sdk-design-ruby/04-domain-model-construction.md`.

[seams.md](./seams.md) — the interface layer everything else plugs into: what a transport, an
async transport and a codec are, how a provider is registered, installed and resolved, the
core-owned future and cancellation token, the close contract, and how an `Operation` becomes a
`Request`. Written against the layer phase 2 shipped; derives from
`docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md`.

[io.md](./io.md) — the byte-streaming layer every body stands on: the FIFO buffer, the buffered
source and sink with their typed reads and non-consuming views, the tee sink, the one ownership
rule, and the `Dexpace::IO` shadow a consumer that includes `Dexpace` has to know about. Written
against the layer phase 3a shipped; derives from
`docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.1.

[body.md](./body.md) — the body layer: the one contract every body includes and its eight
factories, the seven request-body variants and what each closes, the single-use response body,
the materialize-once guard and the bounded error copy, the two logging wrappers and their two
regimes, the one decode boundary on `Response`, and the lazy typed response. Written against the
layer phase 3b shipped; derives from `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md`
§3.1 and §7.3, read together with the body-seam deviations recorded in
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`.

[execution-context.md](./execution-context.md) — the correlation model one call carries: the
instrumentation bundle and its reserved sentinels, the three-flavour promotion chain, the
call-unique key and what its value equality costs, the bounded process-wide store and the
identity rule its close obeys. Written against the layer phase 4a shipped; derives from
`docs/sdk-design-ruby/05-pipeline-architecture.md` §5.4 and
`docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.1.


[recovery.md](./recovery.md) — the recovery layer: the closed two-variant outcome, the two folds
over frozen step lists and who closes the response, the orchestrator that lets no throwable past
it and its unchanged rethrow, the three shipped steps over one transform contract, the bounded
error copy's one call site, and the three error primitives the whole SDK uses from here on — the
suppressed-exception trail Ruby's single-parent `cause` cannot carry on its own, the cycle-safe
cause walk and the protocol error. Written against the layer phase 4b shipped; derives from
`docs/sdk-design-ruby/05-pipeline-architecture.md` §5.2 and §5.1's three shipped steps, read
together with the recovery-layer deviations recorded in
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`.

errors.md — the error tree, and which failure means what. The suppressed-exception trail is
already on [recovery.md](./recovery.md); this page collects the classes once the transport error
and the seam-specific errors have all landed. Derives from
`docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md`.

[pipelines.md](./pipelines.md) — the stage pipeline: the sixteen totally ordered stages and the
closed set they form, the step protocol and where a step's stage lives, the builder with its
pillar rules, surgical edits, all-or-nothing bulk paths and the two seeding constructors, the
forward-only cursor with its pillar-only fork and stage-scoped state, the sync runtime and its
async mirror as transports, the transform adapter, and why the bridges are phase 2's. The
standard-resilience constructors arrive with phase 6's pillar families. Written against the layer
phase 4c shipped; derives from `docs/sdk-design-ruby/05-pipeline-architecture.md` §5.1 and §5.3,
read together with the pipeline deviations recorded in
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`.

[configuration.md](./configuration.md) — the configuration layer and the clock: the four-tier
chain and the strict order that inverts Ruby's habit, the never-throw typed accessors, the
builder, the two seams and derivation, the process-wide slot, the seven declared keys and the two
earlier layers that read them, the injectable clock and its cancellable queue wait, the deadline
on the future and the scheduler-conditional delay, the proxy model with its closed type set, host
patterns and never-raising resolver, and the RFC 1123 date, UUID, retryability and build-info
utilities. Written against the layer phase 5a shipped; derives from
`docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.2 and §8.3, read together with
entries 16 and 17 of
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`.

[tracing-and-metrics.md](./tracing-and-metrics.md) — the tracing and metrics layer: the span,
tracer and tracer-factory protocols behind the three no-op singletons, the current-span carrier
and its scope handle with the identity test that returns the cached singleton, log correlation
over the two diagnostic-context keys and what the 3.2 floor makes of a removed key, trace-id
generation and the sampled bit, the eleven-method HTTP-tracer vocabulary with its ordering
contract and bus adapter, and the no-op meter with its shared instruments — and what nothing in
v1 emits yet. Written against the layer phase 5c shipped; derives from
`docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.1, read together with the
instrumentation deviations recorded in
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`.

[logging-and-redaction.md](./logging-and-redaction.md) — the logging facade and redaction: the
duck-typed sink and the closed severity set, the logger and the accumulating event with its
inert twin, the one rendering rule and the byte cap, the redactor and its default-deny policy,
the diagnostic-context fold and the snapshot bridge with what the 3.2 floor makes of it, the
containment primitive every emission runs inside, the body preview, the HTTP logging level and
its two configuration keys, the instrumentation step on both runtimes, and the four places
earlier layers now speak through it. Written against the layer phase 5b shipped; derives from
`docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.1 and
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`.

[retry.md](./retry.md) — the retry layer: the one policy core with its two-axis classifier
consult, backoff calculator, total pacing-header parser and tuning constants; the re-sendability
gate; the one configuration object both stacks build from and the key it reads; the stage-based
pillar step on both runtimes, with the iterative async trampoline and what a positive backoff does
without a scheduler; the recovery-chain retry that decorates a raw transport beneath the
orchestrator with its total-timeout budget; the per-attempt HTTP-tracer events every driver emits;
and the three wirings into earlier layers — the protocol error's baked flag, the cursor's
per-call bundle, and the date parser's single-digit day. Written against the layer phase 6a
shipped; derives from `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md` §6.1 and
`docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.3, read together with the
retry deviations recorded in the phase's own ledger.

[auth.md](./auth.md) — the authentication layer: the closed scheme set, the descriptor and the
pure three-tier resolver, the four credential types and the three renderings each redacts, the
never-raising RFC 7235 challenge parser, the Basic and Digest handlers with the chain that
composes them and the hook that puts Digest in front of the step, the static key stamper, the
bearer stamper on each runtime with its single-flight refresh and the async three-zone rule, and
the AUTH pillar step on both runtimes — its HTTPS guard, its cursor-read cross-origin suppression,
the 401 re-challenge replay and the bearer 401 branch — and the end-to-end cross-origin test phase
6b un-guarded. Written against the layer phase 6c shipped; derives from
`docs/sdk-design-ruby/06-retry-redirect-and-authentication.md` §6.3, read together with entries 7
and 15 of `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`.

[redirect.md](./redirect.md) — the redirect layer: the synchronous pillar step and its six options,
the credential hygiene — `Authorization` stripped before every re-issue, `Cookie` and
`Proxy-Authorization` on a cross-origin hop, cross-origin judged against the seed origin — and the
cross-origin marker as cursor state, the "return current" outcomes for a loop, the cap, a missing
or malformed `Location`, the 303 rebuild and the replayable-body gate, the scheme downgrade and
its opt-in, the read-only snapshot a predicate receives, the redacted records and the one raw
exception, the second re-sendability predicate beside retry's, and — the phase-level work phase 4c
postponed — `Pipeline.standard` and `AsyncPipeline.standard` with its required
`redirect: :unsupported`. Written against the layer phase 6b shipped; derives from
`docs/sdk-design-ruby/06-retry-redirect-and-authentication.md` §6.2 and
`docs/sdk-design-ruby/05-pipeline-architecture.md` §5.3, read together with entry 15 of
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`.

[sse.md](./sse.md) — the server-sent-events layer: the two documented caps and the retry cap beside
them, the two mapper-outcome sentinels, the WHATWG line machine over `#getbyte` and why it is not
phase 3a's `#read_line_utf8`, the immutable five-field event, the field machine and the one item of
state it keeps, the resource-owning single-pass facade with its three factories, its two consumption
shapes and its termination paths, the quiet-versus-loud release split and the out-of-band report,
the cross-thread close, the response convenience, the typed adapter's three outcomes and its
laziness, and what is deliberately not there — no sentinel string, no error envelope, no
serialization dependency (kept so by `gates:serde_boundary`), no reconnection. Written against the
layer phase 7b shipped; derives from `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md`
§7.2 and §7.1, read together with entries 6 and 18 of
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`.

[quality-gates.md](./quality-gates.md) — every blocking gate this SDK runs, what each protects,
and how to run it locally. Written against the build phase 0 shipped; derives from
`docs/sdk-design-ruby/09-toolchain-and-quality-gates.md`.

write-a-transport.md — implementing the `Transport` seam, and proving an implementation against
`dexpace-conformance`. Derives from `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md`;
the seam's contract itself is already on [seams.md](./seams.md).

write-a-serde.md — implementing the `Serde` seam: the serializer/deserializer pair, the
`Tristate` PATCH convention, and the four encode profiles. Derives from
`docs/sdk-design-ruby/07-pagination-sse-and-serialization.md`.

write-a-paging-strategy.md — implementing a pagination strategy over a response and a template
request. Derives from `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md`.

write-a-response-handler.md — turning a `Response` into a caller's own model, including the
memoizing-wrapper pattern for a body read more than once. Derives from
`docs/sdk-design-ruby/04-domain-model-construction.md`.

## What this tree will not be

The API reference: once gems exist, every exported symbol's signature lives in `sig/*.rbs` and its
meaning in YARD-generated docs, both gated in CI (`docs/sdk-design-ruby/09-toolchain-and-quality-gates.md`).
A third hand-written copy of either would drift.

The specification: `docs/product-spec/` is normative; `docs/sdk-design-ruby/` is the binding
design and the only place a `HTTP-N`, `SEAM-N`, `RETRY-N` reading is settled. This tree explains
how the resulting packages compose, not what they are required to do.
