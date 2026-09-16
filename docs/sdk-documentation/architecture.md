# Architecture

**As-built docs land here gem by gem, as they land in `gems/`.** Phase 0 built the six gem
skeletons and the gate set, phase 1 the HTTP domain model in `dexpace-core`, phase 2 the seam
layer in the same gem, phase 3a the byte-streaming layer beneath every body, phase 3b the body
layer on top of it, phase 4a the execution context one in-flight call carries, phase 4b the
recovery layer and the error trail, and phase 4c the stage pipeline; the adapters are still to
come, so this page is still a stub: it names the pages this tree will eventually hold and where
each one's content will come from, so the plan for the documentation exists before the
documentation does. Eight pages are real already, because their subjects are:
[`quality-gates.md`](./quality-gates.md), [`http.md`](./http.md), [`seams.md`](./seams.md),
[`io.md`](./io.md), [`body.md`](./body.md), [`execution-context.md`](./execution-context.md),
[`recovery.md`](./recovery.md) and [`pipelines.md`](./pipelines.md).
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

auth.md — tiers, credentials, schemes, challenges, and the redirect-safe re-issue rule. Derives
from `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md`.

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
