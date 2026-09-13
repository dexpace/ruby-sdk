# dexpace SDK — Ruby Port Design

**Status:** Design proposal. This document is not normative in the sense `product-spec.md` is — it mints no
requirement IDs — but every architectural decision below is justified against, or deliberately deviates from, a
specific requirement in that specification. Read `product-spec.md` first; this document assumes its vocabulary
(`SEAM-*`, `HTTP-*`, `IO-*`, `BODY-*`, `CTX-*`, `PIPE-*`, `RECOV-*`, `RETRY-*`, `REDIR-*`, `AUTH-*`, `PAGE-*`,
`SSE-*`, `SERDE-*`, `OBS-*`, `CFG-*`, `TRANSPORT-*`, `ASYNC-*`, `XCUT-*`, `NFR-*` — 645 requirements across 19
prefixes) and cites IDs inline rather than re-deriving them. Where an argument turns on exact wording, the
requirement is quoted verbatim.

**Scope.** This is a gem-and-seam-level architecture for a Ruby implementation of the same product: an HTTP-client
toolkit, not an HTTP client. It covers the monorepo and gem layout, the idiomatic Ruby mapping of each of the
spec's five seams and its async pivot, domain-model construction under `Data.define`, both pipeline layers,
resilience (retry/redirect/auth), pagination/SSE/serde, instrumentation and configuration, and the toolchain that
enforces mechanically the quality bar the reference build enforces mechanically. It does **not** contain Ruby
source, a gemspec, a `Rakefile`, a `Steepfile`, RuboCop configuration, RBS signatures, or CI YAML — those are
downstream of this document, produced when the port is actually undertaken. It does not specify a code-generation
layer; it specifies only the runtime primitives a generator would target (§3.5). It does not choose a wire
protocol beyond HTTP/1.1 for the reference transport, nor does it design the service-client surface a generator
would emit on top of it.

---

## Table of Contents

- [Porting Method](./sdk-design-ruby/00-porting-method.md)
- [1. Overview](./sdk-design-ruby/01-overview.md)
- [2. Gem and Workspace Layout](./sdk-design-ruby/02-gem-and-workspace-layout.md)
- [3. Seam-by-Seam Idiomatic Mapping](./sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md)
- [4. Domain Model Construction](./sdk-design-ruby/04-domain-model-construction.md)
- [5. Pipeline Architecture](./sdk-design-ruby/05-pipeline-architecture.md)
- [6. Retry, Redirect, and Authentication](./sdk-design-ruby/06-retry-redirect-and-authentication.md)
- [7. Pagination, SSE, and Serialization](./sdk-design-ruby/07-pagination-sse-and-serialization.md)
- [8. Instrumentation and Configuration](./sdk-design-ruby/08-instrumentation-and-configuration.md)
- [9. Toolchain and Quality Gates](./sdk-design-ruby/09-toolchain-and-quality-gates.md)
- [10. Deliberate Deviations from the Reference Contract](./sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md)
- [11. Appendix: Reference-Spec Ambiguities and How This Port Resolves Them](./sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md)
- [12. Appendix: Requirement Coverage Index](./sdk-design-ruby/12-appendix-requirement-coverage-index.md)
