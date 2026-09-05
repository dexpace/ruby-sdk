# sdk-positioning

## Rules

## Constraints
- The core carries no concrete transport, codec, byte-stream, or async-runtime dependency, per SEAM-1 and NFR-1.
  <sub>design · `docs/sdk-design-ruby/01-overview.md:23-24` · high · sha:a69e6feeaeb4</sub>

## Conclusions
- The dexpace SDK is framed as "the machinery an HTTP client is made of," an HTTP-client toolkit rather than an HTTP client itself.
  <sub>spec · `docs/product-spec/01-product-overview.md:3-3` · high · sha:4f786c44354d</sub>
- Because the core carries no concrete transport, codec, or I/O dependency (SEAM-1), a consumer can adopt it without inheriting a transitive-dependency conflict and can swap any one concern independently.
  <sub>spec · `docs/product-spec/01-product-overview.md:7-7` · high · sha:4f786c44354d</sub>
- Correctness-sensitive decisions (idempotency classification, status ranges, body replayability, header-injection defenses, credential hygiene, cancellation semantics) are made once in the core so every transport behaves identically. (SEAM-1)
  <sub>spec · `docs/product-spec/01-product-overview.md:7-7` · high · sha:4f786c44354d</sub>
- A faithful port of the SDK must preserve the seams and their invariants rather than reimplement each concern per adapter. (SEAM-1)
  <sub>spec · `docs/product-spec/01-product-overview.md:7-7` · high · sha:4f786c44354d</sub>
- The SDK's thesis is "an HTTP-client toolkit, not an HTTP client," restated for Ruby because Ruby's ecosystem gravitates toward complete, terminal HTTP clients (faraday, httpx, http.rb, rest-client, excon, typhoeus) rather than assembling a pipeline from independently chosen parts as JVM teams do.
  <sub>design · `docs/sdk-design-ruby/01-overview.md:3-9` · high · sha:a69e6feeaeb4</sub>
- Idempotent-method classification, retryable-status classification, body replayability, header-injection defence, and cancellation-versus-timeout classification are decided once in dexpace-core so that every transport adapter behaves identically. (HTTP-9, RETRY-6, RETRY-1, XCUT-5, XCUT-7, BODY-3, BODY-4, HTTP-17, HTTP-19, XCUT-18, XCUT-1, XCUT-2)
  <sub>design · `docs/sdk-design-ruby/01-overview.md:25-29` · high · sha:a69e6feeaeb4</sub>
- A faithful port preserves the reference's seams and their invariants but not its module count, resulting in more seams surviving than a single-execution-model host would keep and fewer gems than the reference's module map, because Ruby's gem granularity is coarser than a JVM multi-module build's.
  <sub>design · `docs/sdk-design-ruby/01-overview.md:68-70` · high · sha:a69e6feeaeb4</sub>

## Reference
- The SDK core supplies immutable wire models, a staged request/response pipeline, and recovery-aware resilience primitives, but does not itself open sockets, encode JSON, or read bytes off a stream.
  <sub>spec · `docs/product-spec/01-product-overview.md:3-3` · high · sha:4f786c44354d</sub>
- Every capability that touches the outside world (network transport, byte-stream implementation, wire codec) plugs into the SDK behind a single-purpose interface.
  <sub>spec · `docs/product-spec/01-product-overview.md:3-3` · high · sha:4f786c44354d</sub>
- The asynchronous-runtime concern is handled through a canonical async pivot plus optional out-of-core adapter modules rather than a core interface.
  <sub>spec · `docs/product-spec/01-product-overview.md:3-3` · high · sha:4f786c44354d</sub>
- The first primary consumer audience is authors of generated or hand-written service clients who need correct, secure, observable HTTP plumbing without re-solving retry, redirect-credential-leak, and secret-logging problems per service.
  <sub>spec · `docs/product-spec/01-product-overview.md:5-5` · high · sha:4f786c44354d</sub>
- The second primary consumer audience is application teams who want to bring their own transport, JSON library, and async runtime and pay only for what they put on the classpath.
  <sub>spec · `docs/product-spec/01-product-overview.md:5-5` · high · sha:4f786c44354d</sub>
- The SDK's primary target audience is authors of generated or hand-written service-client SDKs, such as an internal platform team publishing a client for a company's own API surface or an OpenAPI-codegen backend targeting Ruby. (RETRY-5, XCUT-10, REDIR-7, REDIR-13, XCUT-17, AUTH-12, AUTH-22, PAGE-16, PAGE-24, SSE-1, SSE-19, SERDE-14, SERDE-20)
  <sub>design · `docs/sdk-design-ruby/01-overview.md:11-21` · high · sha:a69e6feeaeb4</sub>
- The correctness-sensitive plumbing the SDK solves once for its primary audience includes idempotency-aware retry that never double-sends a one-shot body, redirects that never leak a bearer token cross-origin, RFC 7235 challenge parsing and RFC 7616 Digest auth, cursor/page-number/Link-header pagination, WHATWG SSE parsing, and PATCH's absent/null/present three-state semantics. (RETRY-5, XCUT-10, REDIR-7, REDIR-13, XCUT-17, AUTH-12, AUTH-22, PAGE-16, PAGE-24, SSE-1, SSE-19, SERDE-14, SERDE-20)
  <sub>design · `docs/sdk-design-ruby/01-overview.md:11-21` · high · sha:a69e6feeaeb4</sub>
- The SDK's secondary audience is application teams who want the same correctness guarantees while choosing their own transport (Net::HTTP, async-http, or httpx) and their own codec, without inheriting the SDK authors' preferred choices.
  <sub>design · `docs/sdk-design-ruby/01-overview.md:19-21` · high · sha:a69e6feeaeb4</sub>

## Conflicts

## Superseded
