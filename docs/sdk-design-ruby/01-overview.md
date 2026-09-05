## 1. Overview

The thesis — "an HTTP-client toolkit, not an HTTP client" — needs restating rather than repeating for Ruby, because
Ruby's default reflex is the opposite of the reference audience's. On the JVM, teams already compose a toolkit from
independently chosen parts because no single dominant client exists. In Ruby the gravity pulls the other way:
`faraday` (with its adapter-plus-middleware stack), `httpx`, `http.rb`, `rest-client`, `excon` and `typhoeus` are
complete, terminal HTTP clients, several of which already bundle retries, redirect following, instrumentation
hooks and JSON handling into one opinionated package. A Ruby engineer's default move when they need to call an
HTTP API is `gem install faraday` (or `Net::HTTP.get` for something small), not assembling a pipeline from parts.

This SDK does not compete with those gems on "easiest way to fetch a JSON endpoint." It targets a narrower
audience: **authors of generated or hand-written service-client SDKs** — an internal platform team publishing a
client for a company's own API surface, or an OpenAPI-codegen backend targeting Ruby — who need the
correctness-sensitive plumbing solved exactly once: idempotency-aware retry that never double-sends a one-shot
body (**RETRY-5**, **XCUT-10**), redirects that never leak a bearer token cross-origin (**REDIR-7**–**REDIR-13**,
**XCUT-17**), RFC 7235 challenge parsing and RFC 7616 Digest (**AUTH-12**–**AUTH-22**), cursor/page-number/Link-header
pagination (**PAGE-16**–**PAGE-24**), WHATWG SSE parsing (**SSE-1**–**SSE-19**), and PATCH's absent/null/present
three-state semantics (**SERDE-14**–**SERDE-20**) — so that no codegen backend re-solves any of it. The secondary
audience is application teams who want those guarantees while choosing their own transport (`Net::HTTP` today,
`async-http` when they adopt a reactor, `httpx` when they need HTTP/2) and their own codec, without inheriting
whichever choices this SDK's authors happened to prefer.

The value proposition survives unchanged: because the core carries no concrete transport, codec, byte-stream or
async-runtime dependency (**SEAM-1**, **NFR-1**), a consumer adopts it without inheriting a version conflict in a
`Gemfile.lock`, and swaps any one concern independently. The correctness-sensitive decisions — idempotent-method
classification (**HTTP-9**/**RETRY-6**), retryable-status classification (**RETRY-1**/**XCUT-5**/**XCUT-7**), body
replayability (**BODY-3**/**BODY-4**), header-injection defence (**HTTP-17**–**HTTP-19**/**XCUT-18**),
cancellation-versus-timeout classification (**XCUT-1**/**XCUT-2**) — are made once in `dexpace-core` so every
transport adapter behaves identically.

**Which of the reference's constraints hold in Ruby.** The reference's structural choices exist because of specific
JVM constraints; a faithful port must audit each one rather than inherit or discard the set wholesale.

- **Two genuinely different I/O execution models: HOLDS, and this is the pivotal finding.** Ruby has both a real
  blocking model (a thread parked in `read(2)` with `Net::HTTP`'s socket timeouts) and a real reactor model
  (`async`/`async-http` driving `Async::Task`s under a registered `Fiber.scheduler`). Under a scheduler, a blocking
  call built on plain `IO` is transparently non-blocking at the fiber level — but that transparency covers only
  pure-Ruby, scheduler-hookable I/O; C-extension transports (`typhoeus`/libcurl, some TLS paths) bypass the
  scheduler hooks entirely, and a reactor-native client exposes HTTP/2 stream multiplexing and a structured
  cancellation tree that no blocking call can express even when perfectly scheduled. Both the synchronous transport
  seam (**SEAM-11**) and the asynchronous transport seam with its pivot (**SEAM-16**, **SEAM-17**) therefore survive
  here (§3.2, §3.3). By P4's converse, a port must not collapse a split the host genuinely has.
- **Async-ecosystem fragmentation: HOLDS, more strongly than on the reference platform.** `async`'s `Async::Task`,
  `concurrent-ruby`'s `Concurrent::Promises::Future`, plain `Thread`+`Thread::Queue`, and EventMachine-descended
  deferrables are mutually incompatible primitives with different cancellation semantics, and none of them is in
  the standard library. **SEAM-17**'s "one canonical dependency-free pivot plus per-ecosystem adapter modules" is
  therefore not merely applicable, it is the only shape that keeps **SEAM-1** intact (§3.3).
- **No standard byte-stream type good enough to build a wire protocol on: DOES NOT HOLD.** `IO`, `StringIO`,
  `IO.pipe`, `Enumerator` and `IO::Buffer` ship with the interpreter, and Rack has given the ecosystem a de facto
  streaming-body protocol (`#each` yielding String chunks) that every web-facing Ruby library already speaks. The
  byte-stream *provider* seam retires; its behavioural contract does not (§3.1).
- **Generic erasure: DOES NOT HOLD — and neither does its inverse.** Ruby erases nothing (every object carries its
  class at runtime), but Ruby also *reifies* nothing about element types: an `Array` is never an `Array` of
  anything. **SERDE-5**–**SERDE-8** are consequently not vacuous; they need a different mechanism (§7.3).
- **A whole-program shrinker with a reflection blind spot: DOES NOT HOLD.** **NFR-8** says so itself: "In
  ecosystems without such a build step this requirement does not apply." The gate is retargeted rather than
  deleted, at the structurally equivalent Ruby risk (§9).
- **A global interpreter lock: NEW, and it cuts both ways.** On CRuby the GVL makes a lone instance-variable
  reference read or write atomic, which is what **XCUT-12**'s wait-free credential read needs and what the JVM
  needs `volatile` for — but that guarantee does not hold on JRuby or TruffleRuby, so the port relies on safe
  publication (write under a lock, read without) rather than on the GVL. The GVL also means "thread-safe" is
  cheaper to achieve and no cheaper to *reason about*: **XCUT-11**, **SEAM-12**, **TRANSPORT-29** and **ASYNC-22**
  still require per-call state to live on the call, not on the shared instance.
- **A cooperative fiber scheduler: NEW.** `Fiber.scheduler` (3.0+) is what makes the blocking contract
  scheduler-transparent, and what makes **RETRY-26**'s "MUST NOT pin an execution carrier" a live concern rather
  than a JVM-only one (§8.3).

A faithful port preserves the seams and their invariants; it does not preserve the reference's module count. This
port ends up with *more* seams surviving than a single-execution-model host would keep, and correspondingly fewer
gems than the reference's module map, because Ruby's gem granularity is coarser than a JVM multi-module build's.

---

