# serde

## Rules
- The wire-codec seam MUST bundle a serializer, a deserializer, and the media type its serializer produces, and that media type MUST NOT be defaulted at the seam level since each codec declares its own (SEAM-19).
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:24-24` · high · sha:0adae2d6a47f</sub>
- Deserialization MUST require an explicit runtime type token rather than an erased/inferred generic, so a language with type erasure recovers the intended type instead of silently producing a generic map/list, and parametric targets MUST be expressible through a full generic type capture (SEAM-21).
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:25-25` · high · sha:0adae2d6a47f</sub>
- A Serde MUST be a single bundle exposing exactly one encoder and one decoder for one wire format, so consumers acquire both through one reference. (SERDE-1)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:7-7` · high · sha:c6bc7789c3a9</sub>
- A Serde MUST declare the wire media type it produces, that media type MUST be used as the default Content-Type when a request body is created from a value plus a Serde, and it MUST NOT be defaulted to a format-agnostic constant at the SPI level. (SERDE-2)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:8-8` · high · sha:c6bc7789c3a9</sub>
- When encoding into or decoding from a caller-supplied stream, the serializer/deserializer MUST read/write the payload fully but MUST NOT close or take ownership of the caller's stream, and the encode-into-buffer profile likewise never assumes ownership of the target region. (SERDE-3)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:12-12` · high · sha:c6bc7789c3a9</sub>
- The encode-into-buffer serialization profile MUST return the number of bytes written, honor a start offset, throw a range/overflow error distinct from the serde exception type when the offset is out of range or the payload doesn't fit, and leave bytes before the offset untouched. (SERDE-4)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:13-13` · high · sha:c6bc7789c3a9</sub>
- Every decode operation MUST take an explicit runtime type witness for the target type, since a decoder relying on erased compile-time generics on an erasure-based runtime would silently yield an untyped map/list that detonates as a cast error on first field access. (SERDE-5)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:17-17` · high · sha:c6bc7789c3a9</sub>
- Parametric decode targets such as `List<Dto>` MUST be expressible through a full-generic type carrier preserving element types across erasure, and a format-agnostic decoder that cannot resolve type arguments MUST fail loudly for a genuinely parametric carrier rather than silently decoding into the raw type. (SERDE-6)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:18-18` · high · sha:c6bc7789c3a9</sub>
- An ergonomic reified/inline decode helper MUST capture the full generic type and route through the generic carrier rather than forwarding only the raw class. (SERDE-7)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:19-19` · high · sha:c6bc7789c3a9</sub>
- The generic type carrier MUST capture a concrete, fully-resolved type at construction and MUST reject construction with no type argument or an unresolved type variable, failing fast with an actionable message. (SERDE-8)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:20-20` · high · sha:c6bc7789c3a9</sub>
- Encode/decode failures MUST surface as the SDK's stable serde exception type or a subtype, with adapters catching the backing codec's processing failures, chaining the original as the cause, and never letting a backing-library exception type escape the SPI. (SERDE-9)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:24-24` · high · sha:c6bc7789c3a9</sub>
- Write-path serde failures MUST be a serialization-specific exception subtype and read-path failures a deserialization-specific subtype, both extending a common root, so callers can distinguish direction while catching one base type. (SERDE-10)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:25-25` · high · sha:c6bc7789c3a9</sub>
- Serde failures SHOULD be unchecked/runtime exceptions rather than checked/declared ones, so callers are not forced to wrap every round-trip. (SERDE-11)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:26-26` · high · sha:c6bc7789c3a9</sub>
- A genuine stream I/O error raised while reading/writing a caller-owned stream MUST propagate unwrapped as an I/O error and MUST NOT be re-wrapped as a serde exception, with only malformed-input/shape-mismatch/unencodable-value failures wrapped. (SERDE-12)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:27-27` · high · sha:c6bc7789c3a9</sub>
- Decoding a wire null literal into a non-null target type MUST fail with a deserialization exception naming the target type, across every decode overload, rather than returning a null that flows through and detonates later. (SERDE-13)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:28-28` · high · sha:c6bc7789c3a9</sub>
- The PATCH tri-state type MUST model exactly three states — Absent (key missing), Null (explicit null), and Present (carries a value) — making the illegal fourth state of Present-of-null unrepresentable by bounding Present to non-null values, and it SHOULD be covariant in its value type. (SERDE-14)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:32-32` · high · sha:c6bc7789c3a9</sub>
- When serializing a tri-state field within an object, Absent MUST omit the key entirely, Null MUST emit the key with a wire null, and Present MUST emit the key with the encoded inner value. (SERDE-15)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:33-33` · high · sha:c6bc7789c3a9</sub>
- When deserializing a tri-state field, a missing key MUST map to Absent, a present explicit-null MUST map to Null, and a present value MUST map to Present(value) with the inner value's declared element type preserved. (SERDE-16)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:34-34` · high · sha:c6bc7789c3a9</sub>
- The tri-state type SHOULD provide construction/consumption helpers — factories for absent, explicit-null, and present(non-null), a nullable-to-(present|null) mapper that can never yield Absent, a three-way fold, a value-or-null accessor, and is-absent/is-null/is-present predicates. (SERDE-18)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:36-36` · high · sha:c6bc7789c3a9</sub>
- The default codec configuration MUST wire the tri-state PATCH semantics, an adapter building a serde around a caller-supplied codec MUST register that wiring by default, and absent this wiring Absent and Null become indistinguishable on the wire. (SERDE-19)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:37-37` · high · sha:c6bc7789c3a9</sub>
- When a tri-state value is serialized with no enclosing object able to omit a key, such as a top-level value or an array element, the implementation SHOULD emit a wire null for both Absent and Null rather than throwing. (SERDE-20)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:38-38` · high · sha:c6bc7789c3a9</sub>
- The default decoder configuration MUST reject cross-shape scalar coercions such as string-to-integer, string-to-float, string-to-boolean, empty-string-to-integer/float/boolean, float-to-integer, boolean-to-integer, integer-to-boolean, boolean-to-float, and non-string-scalar-to-string, surfacing each as a deserialization failure. (SERDE-21)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:43-43` · high · sha:c6bc7789c3a9</sub>
- The strict-coercion decoder policy MUST still permit representation-preserving conversions, including numeric widening of an integer into a floating-point target, an empty string into a textual target, and any well-typed value binding to its matching target. (SERDE-22)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:44-44` · high · sha:c6bc7789c3a9</sub>
- The default decoder configuration SHOULD ignore unknown/unexpected fields rather than failing, so a server can add backward-compatible fields ahead of a client model update. (SERDE-23)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:45-45` · high · sha:c6bc7789c3a9</sub>
- When a serde is built around a caller-supplied codec instance, the SDK MUST NOT mutate the caller's instance during normal construction and MUST operate on a private copy of the codec engine, falling back to using the supplied instance directly only as documented, non-silent behavior if the codec cannot be copied. (SERDE-26)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:48-48` · high · sha:c6bc7789c3a9</sub>
- A configured serde SHOULD be safe to share across concurrent threads/tasks once configuration is complete, with any per-type sub-serializer caches using non-blocking, publication-safe updates rather than coarse locks. (SERDE-29)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:49-49` · high · sha:c6bc7789c3a9</sub>
- A response-decoding handler MUST stream the response body directly through the deserializer into the target value without first materializing the whole body, MUST consume and close the response on every path, MUST surface a missing body as a serde exception naming the target type, and MUST surface a codec/parse failure as a serde exception chaining the original while letting a genuine mid-stream I/O error propagate unwrapped. (SERDE-27)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:53-53` · high · sha:c6bc7789c3a9</sub>
- A status-aware response handler MUST decode the body only on a 2xx status, throw the mapped HTTP-error exception carrying a bounded buffered in-memory copy of the error body on 4xx/5xx, and on any other non-2xx status (1xx, or an unfollowed 3xx such as 304) close the response and raise a serde exception whose message leads with the status code and preserves conditional/redirect context. (SERDE-28, BODY-30)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:54-54` · high · sha:c6bc7789c3a9</sub>
- Neither #dump_to nor #dump_into closes the caller's target, and #dump_into raises an IndexError on overflow, as SEAM-20's last clause requires; this is asserted per adapter in dexpace-conformance rather than left to adapter discipline.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:313-317` · high · sha:bf7f85fc5f18</sub>
- #load(source, witness) reads to EOF and does not close the caller's source, per SEAM-21.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:318-319` · high · sha:bf7f85fc5f18</sub>
- The JSON adapter implements the seam's #dump and #load via JSON.generate and JSON.parse, never via JSON.dump or JSON.load, enforced by a lint rule rather than convention.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:334-338` · high · sha:bf7f85fc5f18</sub>
- #load on the serde seam always takes an explicit witness; there is no witness-less overload to fall into.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:338-339` · high · sha:bf7f85fc5f18</sub>
- A memoized TypedResponse failure is re-raised as the same exception object rather than re-derived, so that its #cause and its suppressed-exception trail survive every later access.
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:137-139` · high · sha:4bf713047534</sub>

## Constraints
- A tri-state field with no key on the wire MUST resolve to Absent, which in practice requires the field's declared default to be Absent because a missing key is short-circuited by the codec before the decoder's null hook runs. (SERDE-17)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:35-35` · high · sha:c6bc7789c3a9</sub>
- RBS and Steep act as a gate rather than a guarantee for witness type checking, since a host with a compiler can refuse an invalid call site outright while Ruby can only fail fast at run time.
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:124-126` · high · sha:4bf713047534</sub>

## Conclusions
- The default encoder configuration SHOULD emit date/time values as ISO-8601 strings rather than numeric epoch timestamps, and whichever form is chosen, encoding MUST round-trip to the same instant. (SERDE-24)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:46-46` · high · sha:c6bc7789c3a9</sub>
- A factory building the default codec configuration SHOULD return a fresh, independent instance on each call rather than a shared mutable singleton, because codec instances carry mutable caches that interact poorly with post-construction reconfiguration. (SERDE-25)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:47-47` · high · sha:c6bc7789c3a9</sub>
- Because Ruby neither erases generics nor reifies element types, requirements SERDE-5 through SERDE-8 are not vacuous in the Ruby port and need a different mechanism than on the reference platform.
  <sub>design · `docs/sdk-design-ruby/01-overview.md:52-54` · high · sha:a69e6feeaeb4</sub>
- Ruby collapses #dump_bytes and #dump_string to differ only in the encoding tag they produce, since a Ruby String tagged Encoding::BINARY is itself the byte array with no separate byte[] type, but both are shipped because the tag is load-bearing at the encoding boundary.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:309-313` · high · sha:bf7f85fc5f18</sub>
- The port ships the JSON codec as a separate gem, dexpace-serde-json, rather than embedding it in core even though json is a default gem and embedding would cost nothing in dependency terms, because SEAM-2 is about coupling and SEAM-19 is about not defaulting policy, and zero dependency cost is not zero coupling cost.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:324-327` · high · sha:bf7f85fc5f18</sub>
- A zero-add_dependency core cannot pin a minimum json version, and the 2026 advisories against the C generator's format-string handling make ">= 2.19.9" the floor a codec should declare, which is only expressible by placing the codec in its own gem that can declare that dependency.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:327-331` · high · sha:bf7f85fc5f18</sub>
- Keeping the JSON codec in a separate gem also keeps the door open for a future dexpace-serde-oj adapter without a second code path in core.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:331-333` · high · sha:bf7f85fc5f18</sub>
- The JSON adapter's default encoder configuration renders date and time values as ISO-8601 strings, never epoch numbers, and the corresponding witness parses that form back to the same instant, so SERDE-24's round-trip requirement holds by construction rather than by the caller matching independent conventions.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:341-344` · high · sha:bf7f85fc5f18</sub>
- Dexpace::Serde::JSON.default is a factory returning a fresh, independently configured adapter instance on every call rather than a shared one, so an application that reconfigures a codec it was handed cannot change the codec another part of the process is using, per SERDE-25.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:344-348` · high · sha:bf7f85fc5f18</sub>
- Ruby erases nothing about an object's class, so the reflective type-token trick used to recover a decoder's erased element type is unnecessary, but Ruby also reifies nothing about a container (an Array is never "an Array of anything"), so the underlying requirement to recover a target type is still not vacuous.
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:104-109` · high · sha:4bf713047534</sub>
- The witness pattern is stronger than a reflective type token in two ways (it fails at witness construction rather than deep inside a parse, and the "unresolved type variable" error state is unreachable because a combinator cannot be built without a concrete element witness), and weaker in one way (a host with a compiler refuses an invalid call site outright, whereas Ruby can only fail fast at run time). (SERDE-8)
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:119-126` · high · sha:4bf713047534</sub>
- TypedResponse memoization uses an explicit @state field with values :unstarted, :running, and :done rather than the idiomatic Ruby @value ||= load pattern, because a witness may legitimately decode to nil, and the ||= idiom would re-run the handler and re-read the already-consumed single-use body on every subsequent access.
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:134-137` · high · sha:4bf713047534</sub>
- TypedResponse serializes concurrent first accesses using a Thread::Mutex held only across the @state flip and never across the parse, because Ruby's Mutex is per-fiber-owned and non-reentrant, so holding it across the suspension point inside a parse would deadlock two fibers of one thread; a caller arriving mid-parse waits on a Thread::ConditionVariable over the same mutex, which the fiber scheduler hooks so it unmounts its fiber rather than pinning the thread. (HTTP-45, BODY-22)
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:141-149` · high · sha:4bf713047534</sub>
- The Tristate ABSENT and NULL sentinels override #to_s and #inspect to return "Absent" and "Null" because Ruby's default #inspect for a singleton object renders its object id, which would otherwise make log lines or test failures differ between runs and be unreadable. (SERDE-30)
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:153-156` · high · sha:4bf713047534</sub>
- Strict coercion policy for deserialization is satisfied because JSON.parse performs no coercion (so "5" never silently becomes 5), moving the strictness burden into the witness, where each field asserts its expected class and raises a DeserializationError naming the target type on mismatch. (SERDE-21, SERDE-22, SERDE-13, SERDE-26)
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:164-167` · high · sha:4bf713047534</sub>

## Reference
- Serde is the SDK's format-agnostic serialization seam defined by a small SPI bundling an encoder, decoder, and declared wire media type, with the core shipping only abstractions (Serde/Serializer/Deserializer, a generic type carrier, the three-state Tristate sum type for PATCH, and a stable exception hierarchy) while a concrete codec such as Jackson plugs in at the edge.
  <sub>spec · `docs/product-spec/14-serialization-serde.md:3-3` · high · sha:c6bc7789c3a9</sub>
- The absent and explicit-null tri-state sentinels MAY provide a stable, identity-free textual representation such as "Absent" or "Null" so logs and assertions do not leak an identity hash. (SERDE-30)
  <sub>spec · `docs/product-spec/14-serialization-serde.md:39-39` · high · sha:c6bc7789c3a9</sub>
- Serde is a bundle exposing one serializer, one deserializer, and the declared wire media type for one format, forming the SDK's format-agnostic serialization seam.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:61` · high · sha:f0b3d2058626</sub>
- Tristate is a three-valued sum type — Absent / Null / Present(value) — distinguishing a missing key from an explicit null from a present value at the serialization boundary, primarily for HTTP PATCH.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:67` · high · sha:f0b3d2058626</sub>
- A TypeRef / type witness is an explicit runtime carrier of a target type, either a raw class token or a full generic capture, passed into deserialization so a language with type erasure recovers the intended type.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:69` · high · sha:f0b3d2058626</sub>
- A serde bundle's own serializer output round-trips correctly through its own deserializer. (SERDE-1, SERDE-2)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:29` · high · sha:0451cc7f3bb4</sub>
- A serde bundle's declared media type becomes the default Content-Type, rather than the media type being defaulted at the SPI layer. (SERDE-1, SERDE-2)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:29` · high · sha:0451cc7f3bb4</sub>
- Serialization to a streaming or buffer target does not close that target. (SERDE-3, SERDE-4)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:30` · high · sha:0451cc7f3bb4</sub>
- Encoding into a buffer returns the encoded length, honors a supplied offset, and throws a non-serde range error on overflow. (SERDE-3, SERDE-4)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:30` · high · sha:0451cc7f3bb4</sub>
- Decoding requires an explicit type witness to be supplied. (SERDE-5, SERDE-6, SERDE-7, SERDE-8)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:31` · high · sha:0451cc7f3bb4</sub>
- A parametric type carrier preserves element types, and a decoder lacking a codec fails loudly on a parametric type reference while still decoding a plain-class carrier. (SERDE-5, SERDE-6, SERDE-7, SERDE-8)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:31` · high · sha:0451cc7f3bb4</sub>
- The reified/inline decode helper routes through the type carrier mechanism. (SERDE-5, SERDE-6, SERDE-7, SERDE-8)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:31` · high · sha:0451cc7f3bb4</sub>
- A type carrier rejects an unresolved type variable at construction time. (SERDE-5, SERDE-6, SERDE-7, SERDE-8)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:31` · high · sha:0451cc7f3bb4</sub>
- Serde failures surface as a stable serde exception type chaining the original cause, with no underlying library exception type escaping. (SERDE-9, SERDE-10, SERDE-11, SERDE-12, SERDE-13)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:32` · high · sha:0451cc7f3bb4</sub>
- The serde exception hierarchy has directional subtypes distinguishing write failures from read failures. (SERDE-9, SERDE-10, SERDE-11, SERDE-12, SERDE-13)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:32` · high · sha:0451cc7f3bb4</sub>
- Serde failures are unchecked exceptions. (SERDE-9, SERDE-10, SERDE-11, SERDE-12, SERDE-13)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:32` · high · sha:0451cc7f3bb4</sub>
- A genuine stream I/O error during serde propagates unwrapped rather than being wrapped as a serde exception. (SERDE-9, SERDE-10, SERDE-11, SERDE-12, SERDE-13)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:32` · high · sha:0451cc7f3bb4</sub>
- Decoding a wire null into a non-null target type fails, naming the target type, consistently across all decode overloads. (SERDE-9, SERDE-10, SERDE-11, SERDE-12, SERDE-13)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:32` · high · sha:0451cc7f3bb4</sub>
- The Tristate type has exactly three states, and Present(null) is unrepresentable. (SERDE-14, SERDE-15, SERDE-16, SERDE-17, SERDE-18, SERDE-19, SERDE-20, SERDE-30)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:33` · high · sha:0451cc7f3bb4</sub>
- Serializing Tristate emits nothing for Absent, emits null for Null, and emits the value for Present. (SERDE-14, SERDE-15, SERDE-16, SERDE-17, SERDE-18, SERDE-19, SERDE-20, SERDE-30)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:33` · high · sha:0451cc7f3bb4</sub>
- Decoding `{}`, `{"x":null}`, and `{"x":v}` round-trips correctly to Absent, Null, and Present(v) respectively for a Tristate field. (SERDE-14, SERDE-15, SERDE-16, SERDE-17, SERDE-18, SERDE-19, SERDE-20, SERDE-30)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:33` · high · sha:0451cc7f3bb4</sub>
- A missing key decodes to Absent for a Tristate field via a field default. (SERDE-14, SERDE-15, SERDE-16, SERDE-17, SERDE-18, SERDE-19, SERDE-20, SERDE-30)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:33` · high · sha:0451cc7f3bb4</sub>
- Tristate provides construction and consumption helper methods, and its ofNullable helper never yields Absent. (SERDE-14, SERDE-15, SERDE-16, SERDE-17, SERDE-18, SERDE-19, SERDE-20, SERDE-30)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:33` · high · sha:0451cc7f3bb4</sub>
- The default Tristate codec auto-registers its wiring. (SERDE-14, SERDE-15, SERDE-16, SERDE-17, SERDE-18, SERDE-19, SERDE-20, SERDE-30)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:33` · high · sha:0451cc7f3bb4</sub>
- Tristate degrades appropriately when used at the top level or as an array element. (SERDE-14, SERDE-15, SERDE-16, SERDE-17, SERDE-18, SERDE-19, SERDE-20, SERDE-30)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:33` · high · sha:0451cc7f3bb4</sub>
- Tristate's states render as stable sentinel strings. (SERDE-14, SERDE-15, SERDE-16, SERDE-17, SERDE-18, SERDE-19, SERDE-20, SERDE-30)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:33` · high · sha:0451cc7f3bb4</sub>
- Strict decoding rejects coercion across incompatible shapes. (SERDE-21, SERDE-22, SERDE-23, SERDE-24, SERDE-25, SERDE-26, SERDE-29)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:34` · high · sha:0451cc7f3bb4</sub>
- Strict decoding permits numeric widening and an empty string decoding to a string. (SERDE-21, SERDE-22, SERDE-23, SERDE-24, SERDE-25, SERDE-26, SERDE-29)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:34` · high · sha:0451cc7f3bb4</sub>
- Unknown fields in the wire payload are ignored during decode. (SERDE-21, SERDE-22, SERDE-23, SERDE-24, SERDE-25, SERDE-26, SERDE-29)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:34` · high · sha:0451cc7f3bb4</sub>
- ISO-8601 dates round-trip correctly through serde. (SERDE-21, SERDE-22, SERDE-23, SERDE-24, SERDE-25, SERDE-26, SERDE-29)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:34` · high · sha:0451cc7f3bb4</sub>
- Each serde factory call produces a fresh codec instance. (SERDE-21, SERDE-22, SERDE-23, SERDE-24, SERDE-25, SERDE-26, SERDE-29)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:34` · high · sha:0451cc7f3bb4</sub>
- A caller-supplied codec is not mutated by the serde layer. (SERDE-21, SERDE-22, SERDE-23, SERDE-24, SERDE-25, SERDE-26, SERDE-29)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:34` · high · sha:0451cc7f3bb4</sub>
- A serde codec is thread-safe once shared after its configuration phase. (SERDE-21, SERDE-22, SERDE-23, SERDE-24, SERDE-25, SERDE-26, SERDE-29)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:34` · high · sha:0451cc7f3bb4</sub>
- The streaming response handler closes its resource on every exit path, including a missing body, a missing codec, and an I/O error. (SERDE-27, SERDE-28)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:35` · high · sha:0451cc7f3bb4</sub>
- The status-aware response handler decodes only 2xx bodies, buffers a bounded preview of a 4xx/5xx error body, and raises a status-naming serde exception for other non-2xx statuses. (SERDE-27, SERDE-28)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:35` · high · sha:0451cc7f3bb4</sub>
- Ruby erases nothing, since every object carries its class at runtime, but Ruby also reifies nothing about element types, since an Array is never an Array of anything specific. (SERDE-5, SERDE-8)
  <sub>design · `docs/sdk-design-ruby/01-overview.md:52-54` · high · sha:a69e6feeaeb4</sub>
- The wire-codec seam is a duck type: an object responding to #media_type, #dump(value, sink), and #load(source, witness), plus three further encode entry points. (SEAM-2, SERDE-1, SERDE-2)
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:298-301` · high · sha:bf7f85fc5f18</sub>
- The serializer seam carries four dump methods — #dump_string(value), #dump_bytes(value), #dump_to(value, sink), and #dump_into(value, buffer, offset:) — with #dump as the shorthand for #dump_to.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:307-309` · high · sha:bf7f85fc5f18</sub>
- Encode and decode failures surface as the stable, SDK-owned Dexpace::Serde::SerializationError/DeserializationError pair, per SEAM-23, chaining the codec's own error rather than leaking the backing library's exception type, while a genuine stream I/O error propagates unwrapped.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:319-322` · high · sha:bf7f85fc5f18</sub>
- Ruby 3.4.10 ships json 2.9.1 (verified).
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:328-330` · high · sha:bf7f85fc5f18</sub>
- JSON.load accepts a proc and has historically enabled create_additions, the arbitrary-object instantiation hazard behind CVE-2020-10663, defaulted off only from json 2.7.0, giving it no place in a security-sensitive decode path.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:335-338` · high · sha:bf7f85fc5f18</sub>
- SERDE-23's tolerant decode of unknown fields is the witness's default: a witness reads only the keys it declares and ignores the rest, with strictness opt-in per witness.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:348-350` · high · sha:bf7f85fc5f18</sub>
- In the Ruby SDK, a witness is any object responding to .dexpace_load(parsed, ctx); a model class implements this as a class method returning an instance, and the inverse #dexpace_dump returns a structure of codec-native values.
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:111-113` · high · sha:4bf713047534</sub>
- Parametric serialization targets are covered by combinators that are themselves witnesses, supplied by core as Dexpace::Serde::List.of(Pet), Map.of(String, Pet), Nullable.of(Pet), and Tristate.of(String), each built by value from a concrete element witness. (SERDE-6)
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:114-117` · high · sha:4bf713047534</sub>
- Dexpace::TypedResponse is a lazy typed-response wrapper that forwards raw status, headers, protocol, reason, and request accessors straight to the underlying Response and touches the body only when the typed value is first accessed, memoizing the outcome so later accesses return the same value or re-throw the same failure without re-running the handler or re-reading the single-use body. (HTTP-44)
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:128-134` · high · sha:4bf713047534</sub>
- Tristate is implemented as three frozen singletons and one wrapper: Tristate::ABSENT, Tristate::NULL, and Tristate::Present = Data.define(:value), with Present.new(nil) rejected at construction so the illegal fourth state cannot be built through the public API. (SERDE-14, SERDE-20)
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:151-153` · high · sha:4bf713047534</sub>
- Because JSON.parse yields an ordinary Hash, hash.key?("x") distinguishes an absent key from a present null directly, making Ruby's Tristate decode side simpler than a key-oriented codec's; the witness decides per key with full knowledge of the enclosing model's shape. (SERDE-17, SERDE-16)
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:156-159` · high · sha:4bf713047534</sub>
- Tristate encoding is direct because #dexpace_dump builds the Hash and simply omits Absent keys before JSON.generate, requiring no per-key serializer hook. (SERDE-16, SERDE-15, SERDE-19, SERDE-20)
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:159-162` · high · sha:4bf713047534</sub>
- The serialization failure model is a Dexpace::Serde::Error root with SerializationError and DeserializationError subtypes; adapters catch the backing library's exceptions and re-raise inside the rescue block so Ruby sets #cause automatically, while a genuine stream IOError propagates unwrapped rather than being reclassified. (SERDE-9, SERDE-12, SEAM-20, SEAM-21)
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:170-174` · high · sha:4bf713047534</sub>

## Conflicts

## Superseded
