# seams-and-extensibility

## Rules
- A single seam implementation on the classpath is auto-discovered with no bootstrap call; zero or multiple discoverable candidates fail loudly (SEAM-5).
  <sub>spec · `docs/product-spec/01-product-overview.md:9-9` · high · sha:4f786c44354d</sub>
- The core library MUST NOT embed a concrete HTTP transport, byte-stream I/O implementation, or wire codec, and MUST depend at runtime on nothing beyond its language's standard library plus a compile-time-only logging facade (SEAM-1).
  <sub>spec · `docs/product-spec/02-architectural-principles.md:7-7` · high · sha:8014d2ec2c9d</sub>
- Each external concern that has a core-owned contract MUST be exposed as exactly one narrow interface — the enumerated seams are byte-stream provider, synchronous transport, asynchronous transport, wire codec, and operation-input-to-request projection — and the core MUST NOT reference any concrete implementation of a seam by name (SEAM-2).
  <sub>spec · `docs/product-spec/02-architectural-principles.md:8-8` · high · sha:8014d2ec2c9d</sub>
- Provider resolution MUST follow a fixed precedence — an explicitly installed provider always wins, otherwise the runtime auto-discovers providers on the classpath/plugin registry — throwing a descriptive error when zero providers are discoverable (with an install hint) and when more than one distinct provider is discoverable (listing all candidates), while exactly one discoverable provider is selected silently (SEAM-5).
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:34-34` · high · sha:0adae2d6a47f</sub>
- Explicit installation MUST be idempotent for the same instance and MUST reject installing a different provider when one is already installed, naming both (SEAM-6).
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:35-35` · high · sha:0adae2d6a47f</sub>
- A successful auto-resolution MUST be cached process-wide, while an unresolved state (zero or multiple candidates) MUST remain re-evaluable so a later-registered provider or explicit install can still take effect (SEAM-7).
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:36-36` · high · sha:0adae2d6a47f</sub>
- Resolution/install/swap state MUST be concurrency-safe: reads observe the latest install without blocking, writes are serialized so two concurrent installs cannot both pass the conflict check, and a concurrent first-access cannot run the discovery scan twice (SEAM-9).
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:37-37` · high · sha:0adae2d6a47f</sub>
- When an explicit install replaces a different provider that had already been auto-resolved and handed out, the runtime SHOULD emit a warning rather than fail, because objects may already exist against the previous provider (SEAM-8).
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:38-38` · high · sha:0adae2d6a47f</sub>
- The provider registry SHOULD tolerate one logical provider seen through more than one loader without misreporting it as multiple, de-duplicating by concrete implementation identity, and SHOULD recognize a thin delegating shim as its canonical target (SEAM-10).
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:39-39` · high · sha:0adae2d6a47f</sub>
- The provider registry SHOULD support lock-free reads of the active provider while serializing installs/swaps under a lock that does not pin/park carrier threads under lightweight-thread schedulers (IO-39).
  <sub>spec · `docs/product-spec/05-i-o-contracts.md:49-49` · high · sha:33e67b0b29cd</sub>
- A pluggable single-implementation seam (the I/O provider and any similar SPI) MUST resolve deterministically — an explicit install always wins, otherwise the implementation is auto-discovered from the environment, and zero or multiple candidates with no explicit selection MUST fail loudly with an actionable error rather than silently pick one or no-op. (XCUT-23)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:32` · high · sha:d6123be82c9e</sub>
- The zero-candidate discovery error names no concrete gem, saying only that a transport must be required or installed explicitly, so SEAM-2 holds even in the error path.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:409-412` · high · sha:bf7f85fc5f18</sub>
- The prior-state matrix that SEAM-6 and SEAM-8 describe compares equal? on the object occupying the resolved slot — never == and never the factory — because two calls of the same factory produce two non-equal? instances meant to be treated as different providers.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:423-426` · high · sha:bf7f85fc5f18</sub>
- Re-registering the equal? factory under the same key is a no-op, and registering a different factory under an occupied key raises naming both, so a double-require is quiet while two gems claiming one key are not.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:436-438` · high · sha:bf7f85fc5f18</sub>

## Constraints

## Conclusions
- The core stays small and dependency-free so a consumer's footprint is proportional to the features actually used, with each transport, codec, I/O backend, and async bridge shipped as a separately installable unit depending on the core plus at most one third-party library. (SEAM-1, NFR-1, NFR-2)
  <sub>spec · `docs/product-spec/02-architectural-principles.md:29-29` · high · sha:8014d2ec2c9d</sub>
- Ruby has no classpath to scan, so the port keeps all five SEAM-5 resolution branches and changes only the substrate: an adapter registers itself as a side effect of being required, for example Dexpace::Transport.register(:net_http, klass) called from lib/dexpace/transport/net_http.rb.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:406-409` · high · sha:bf7f85fc5f18</sub>
- "Discoverable" is defined as "the application has required this adapter, directly or through a Bundler group"; core ships an empty registry and never auto-requires an optional gem, which keeps SEAM-1 true.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:408-411` · high · sha:bf7f85fc5f18</sub>
- The registry maps a key to a factory (the adapter class or any #call-shaped builder) because require-time registration happens before the application has configured anything; resolution produces an instance, and the resolved slot holds exactly one, built from the winning factory the first time it is asked for and memoised thereafter.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:417-422` · high · sha:bf7f85fc5f18</sub>
- SEAM-10's de-duplication of one logical provider seen through multiple loaders is vacuous in Ruby, because there is no classloader, require de-duplicates by resolved path, and constants are process-global, so it is recorded rather than implemented as a no-op with a comment.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:440-442` · high · sha:bf7f85fc5f18</sub>
- Presence-gated auto-activation (activating an adapter because a library happens to be loaded) is allowed for instrumentation only, because for a transport or codec, silently letting whatever is installed win is an auditability failure that could reroute requests through a different HTTP library with different TLS and timeout defaults, while for instrumentation the worst outcome of guessing wrong is a span that is or is not emitted. (SEAM-5)
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:444-450` · high · sha:bf7f85fc5f18</sub>

## Reference
- The core depends on a small enumerated set of interfaces it never implements — a byte-stream provider, a synchronous transport, an asynchronous transport, a wire codec, and an operation-input projection (SEAM-2) — and each concrete implementation lives outside the core in its own module depending on the core plus at most one third-party library (NFR-2).
  <sub>spec · `docs/product-spec/01-product-overview.md:9-9` · high · sha:4f786c44354d</sub>
- The reference implementation resolves providers via a ServiceLoader over classpath service entries, using a registration shim because a JVM singleton object cannot be reflectively instantiated. (SEAM-10)
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:39-39` · high · sha:0adae2d6a47f</sub>
- I/O provider resolution (IO-31–IO-36) follows the same precedence, idempotence, caching, warning, and de-duplication rules as SEAM-5 through SEAM-10.
  <sub>spec · `docs/product-spec/05-i-o-contracts.md:47-47` · high · sha:33e67b0b29cd</sub>
- A provider/seam is a narrow abstraction (SPI) the core depends on but never implements, behind which a concrete capability such as I/O, transport, or serde plugs in.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:49` · high · sha:f0b3d2058626</sub>
- The provider registry is a Hash behind a Thread::Mutex for writes with an unsynchronised read of a single frozen reference for lookups, per SEAM-9, and resolution results are memoised until an install invalidates them, per SEAM-7.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:413-415` · high · sha:bf7f85fc5f18</sub>
- install(t) behaves as follows by prior resolved-slot state: an empty slot succeeds silently (SEAM-5); a slot already holding t (equal?) is a no-op (SEAM-6); a slot holding a different explicitly-installed object raises, naming the incumbent and the rejected object (SEAM-6); a slot holding a different auto-resolved but never-handed-out object replaces silently (SEAM-8); and a slot holding a different auto-resolved and already-handed-out object replaces and warns (SEAM-8).
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:428-434` · high · sha:bf7f85fc5f18</sub>
- dexpace-instrumentation-otel may install itself when OpenTelemetry is already defined; no other adapter may auto-activate on presence.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:449-451` · high · sha:bf7f85fc5f18</sub>

## Conflicts

## Superseded
