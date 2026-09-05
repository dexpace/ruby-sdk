# cross-cutting-invariants

## Rules
- close()/shutdown() MUST be idempotent, latched so repeats are no-ops, and MUST NOT block on interrupt-sensitive waits, using non-blocking shutdown and preserving the ambient interrupt/cancel flag as-is. (XCUT-13)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:30` · high · sha:d6123be82c9e</sub>
- The SDK MUST close only resources it created; a caller-supplied (BYO) transport client, executor, or connection pool MUST NOT be closed by the SDK, and the caller retains ownership and may keep using it after the SDK component is closed. (XCUT-22)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:31` · high · sha:d6123be82c9e</sub>
- Every process/instance-lived map whose key space is influenced by callers or servers MUST be bounded by a hard cap and MUST drain back under the cap after each insert using a loop rather than a single pre-insert check-then-evict, so a concurrent insert burst converges to the bound. (XCUT-14)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:36` · high · sha:d6123be82c9e</sub>
- Public wire models (request, response, headers, media type, status, etc.) MUST be immutable after construction and safe to share across threads, expressing mutation as producing a new instance, and MUST NOT retain an alias to externally-mutable state that a post-construction mutation could use to alter the model. (XCUT-15)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:40` · high · sha:d6123be82c9e</sub>
- Diagnostic/preview reads of caller- or server-controlled payloads (error-body snapshots, request/response body log previews) MUST be byte-capped and SHOULD be non-consuming, never materializing an unbounded payload into memory and never disturbing the primary read path the consumer will use. (XCUT-24)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:53` · high · sha:d6123be82c9e</sub>
- Whoever flips the close latch runs the release, and everyone else returns immediately; a release that raises still leaves the latch flipped so no second release is attempted, per BODY-27, and the failure propagates once.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:471-473` · high · sha:bf7f85fc5f18</sub>
- Ownership of a resource (SDK-built versus caller-supplied) is a constructor-level distinction in Ruby, not a runtime check: every component that can take a resource takes it through two differently named entry points — one that builds it and one that borrows it — and records which it did in a frozen @owned boolean set at construction. (ASYNC-15)
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:478-485` · high · sha:bf7f85fc5f18</sub>
- An explicit #close by the caller propagates its failure (SSE-30) and a #release raising during the latched close propagates once (BODY-27); these are the two required-to-be-loud exceptions to close_quietly's otherwise quiet closing behaviour.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:508-516` · high · sha:bf7f85fc5f18</sub>

## Constraints

## Conclusions
- A reimplementation that violates any cross-cutting invariant is considered incorrect or unsafe even if each subsystem individually appears to work.
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:1-3` · high · sha:d6123be82c9e</sub>
- Unbounded caller/server-keyed maps are treated as a memory-exhaustion/DoS vector, which is the rationale for requiring a hard cap with drain-to-cap eviction. (XCUT-14)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:36` · high · sha:d6123be82c9e</sub>
- Ruby has no Closeable interface and no try-with-resources, so the close and ownership rules for SEAM-14, SEAM-25, HTTP-43, ASYNC-15 through ASYNC-17, XCUT-13, and XCUT-22 are written down once centrally rather than inferred from a type.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:454-457` · high · sha:bf7f85fc5f18</sub>
- Close idempotence is implemented as a latch — a @closed boolean flipped under a Thread::Mutex, held only across the flip and released before #release runs — rather than a flag check, using the same shape as the SSE facade and body wrappers' close-once guards, because Ruby's Mutex is per-fiber-owned and non-reentrant so holding it across a suspending release would deadlock two fibers of one thread. (XCUT-13, SEAM-14, SEAM-25, HTTP-43, HTTP-41, BODY-15)
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:464-471` · high · sha:bf7f85fc5f18</sub>
- Because this port has no interrupt-based cancellation, XCUT-13's clause to preserve the ambient cancel flag as-is during close is satisfied by the flag never being touched, while the non-blocking-shutdown requirement remains a real constraint enforced by mechanisms such as dexpace-async-thread's close signalling its queue and returning rather than joining workers under Kernel#sleep or an unbounded Thread#join.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:487-496` · high · sha:bf7f85fc5f18</sub>
- SEAM-15, a MAY requirement, is taken explicitly: a send after close raises Dexpace::ClosedError, documented rather than left undefined, because "undefined" in Ruby means whatever NoMethodError the internals happen to produce.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:496-499` · high · sha:bf7f85fc5f18</sub>

## Reference
- A BYO (bring-your-own) resource is a dependency such as a native HTTP client, executor, or connection pool that the caller constructs and hands to the SDK, and the caller owns its lifecycle since the SDK never closes it, in contrast to an SDK-managed resource that the SDK created and must release on close.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:11` · high · sha:f0b3d2058626</sub>
- A drain-to-cap bounded map is a concurrent map whose caller/server-influenced keys are capped, drained in a loop back under a hard bound after each insert, converging even under concurrent insert bursts, with an arbitrary eviction victim.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:29` · high · sha:f0b3d2058626</sub>
- Ownership-aware lifecycle is the close/dispose discipline where the SDK releases only resources it created and never a caller-supplied one, with close being idempotent.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:37` · high · sha:f0b3d2058626</sub>
- Anything the SDK can release responds to #close, and core ships one Dexpace::Closeable module supplying the whole contract to any class that includes it and defines a private #release.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:459-462` · high · sha:bf7f85fc5f18</sub>
- A Net::HTTP the transport built per call is closed by the transport, while a Net::HTTP the caller passed in is not; an executor dexpace-async-thread created is shut down on close while a caller-supplied one is not; an IO a file-backed body opened is closed after each write while an IO the caller handed to a body factory is not.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:481-484` · high · sha:bf7f85fc5f18</sub>
- Dexpace.close_quietly(resource) is the single sanctioned exit for cleanup-path close failures: it is null-safe, rescues StandardError from #close, and attaches the error to the primary exception's suppressed trail when a primary exception is in flight, or emits it as an http.instrumentation.* diagnostic when there is not; it never raises over a primary exception and never silently swallows. (CFG-21)
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:501-508` · high · sha:bf7f85fc5f18</sub>

## Conflicts

## Superseded
