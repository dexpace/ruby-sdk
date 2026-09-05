# Architecture

**As-built docs land here gem by gem, as they land in `gems/`.** Nothing has been built yet, so
this page is a stub: it names the pages this tree will eventually hold and where each one's
content will come from, so the plan for the documentation exists before the documentation does.
Once `dexpace-core` and the first adapters ship, this page becomes the same kind of front door the
sibling Node SDK's `docs/sdk-documentation/architecture.md` is — package by package, seam by seam
— and the entries below turn from plain text into real links, one at a time, as each page is
actually written against source.

## Planned pages

http.md — the domain model: `Request`, `Response`, `Headers`, `Status`, `QueryParams`, and their
kin, and how each is frozen at construction and reachable only through a builder. Derives from
`docs/sdk-design-ruby/04-domain-model-construction.md`.

bodies.md — request bodies as duck-typed producers, response bodies as owned resources the caller
must close. Derives from `docs/sdk-design-ruby/04-domain-model-construction.md`, read together
with the body-seam deviations recorded in `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`.

errors.md — the error tree, and which failure means what, including the suppressed-exception trail
Ruby's single-parent `cause` cannot carry on its own. Derives from
`docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md`.

pipelines.md — stages, steps, the resilience pillars, and the two named seeding constructors that
build a standard pipeline. Derives from `docs/sdk-design-ruby/05-pipeline-architecture.md`.

auth.md — tiers, credentials, schemes, challenges, and the redirect-safe re-issue rule. Derives
from `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md`.

quality-gates.md — every blocking gate this SDK will run, what each protects, and how to run it
locally. Derives from `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md`.

write-a-transport.md — implementing the `Transport` seam, and proving an implementation against
`dexpace-conformance`. Derives from `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md`.

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
