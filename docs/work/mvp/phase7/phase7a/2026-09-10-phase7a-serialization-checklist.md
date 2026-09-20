# Phase 7a — Serialization: Checklist

**Written at execution time, 2026-09-20, from what was built** — not from the plan. A row whose task
did not do what the plan said is a row that says so, and the "Deviations from the plan" section
below is where each departure is stated with its reason. The design and the plan were written on
2026-09-10 against the *designs* of phases 4–6 (not their code), on a machine that then had only Ruby
3.4.10 and json 2.9.1 / 2.19.9, concurrently with 7b's and 7c's documents and before phase 6 was built.
Since then phases 4a–6c were built, reviewed and merged (#53–#80), every interpreter in the matrix was
installed, and the bundle resolves json **3.0.2** on every ABI. **This sub-phase was cut from `main` at
`c53638b`**, which holds every phase through 6b, and was built in parallel with 7b, 7c and 8a on the
same base — so nothing of theirs exists on this tree and nothing here describes any of it as landed. It
is the first phase in the roadmap to write into two gems, and the first to spend an adapter's `NFR-2`
third-party half; the three zero-dependency gates had never seen a gem carrying one. Where the plan's
text and the built tree disagree the tree wins and this document records it.

**Reconciled 2026-09-20.** Phase 7b's stack merged first (#81 → #82 → #83, `main` at `34f52e8`) and
7c's reconciled stack after it, so this phase's three branches were rebased onto the tree that holds
both by `git rebase --onto` with rerere disabled, every 7a commit preserved and none reordered. The
sentences below that count the tree describe **this phase's own base**, `c53638b`, and are left as
written; on the combined tree the figures are: 219 `lib/dexpace/` files beside `version.rb` (7b's
nine, 7c's fifteen and 7a's eleven over the 184 of phase 6), **nineteen** `private_constant`
test-mirror exceptions (the base's eighteen and 7c's `page/closing.rb`; 7a still adds none — every one
of its eleven `lib/` files has a `test/` mirror, re-checked by the mirror walk on the rebased tests
tip), seventeen checklists, seventeen as-built pages, the core manifest 1 257 → 1 330 (still exactly
this phase's 73 rows, the adapter's 2 → 15 unchanged), the entry file's `# Phase 7a:` block after 7c's
rather than directly after 6b's (its own comment still says "after 6b's block", which stays true with
7b's and 7c's between), and **eighteen** gates — 7b's `gates:serde_boundary`, which this phase's base
did not have and which scans `sse/**` and `page/**` alone, is green with `serde/` beside them. The
five converted registry pins were re-run with all three phase-7 layers in one process and in the bare
child; `composition_test.rb` was run by name. No 7a commit needed a repair and nothing was built by
the pass. The combined tree's counts are `CLAUDE.md`'s and the roadmap's reconciliation note's; this
document's are its base's.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization.md`. Task numbers are that plan's
(nineteen). Design: `docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization-design.md`, whose
Deviation Ledger numbers P7-1–P7-9 and whose as-built rows **P7-61–P7-72** are cited below (7b's and
7c's design ledgers knowingly share P7-1–P7-n; a phase-7 row is cited with its sub-phase letter, and
the manager fixed the as-built bands so the three lanes never collide: 7a from P7-61, 7b from P7-81,
7c from P7-101); the charter is `docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md`. Core
test files are under `gems/dexpace-core/test/`, adapter test files under `gems/dexpace-serde-json/test/`;
every `lib/` file has a `test/` mirror one for one (three core suites and five adapter suites carry no
`lib/` mirror and say so below), and each opens with the IDs it exercises.

## Requirement rows

Thirty own rows — `SERDE-1`–`SERDE-30` — plus the cross-reference rows for the non-`SERDE` IDs this
phase owns a share of or composes, taken from the design's interface table, its out-of-scope table and
the plan's Task 18. **Thirty ✅**, nothing ⏳, nothing 🚫, nothing N/A; nine rows carry a clause the
design said the checklist must state rather than tick (`SERDE-6`, `7`, `8`, `11`, `14`, `17`, `26`,
`27`, `29`) and nine are touched by a deviation row (`SERDE-4`, `9`, `13`, `15`, `19`, `20`, `24`,
`26`, `27`).

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `SERDE-1` | MUST | ✅ | 13, 14, 16 | One bundle, one reference: `Dexpace::Serde::JSON::Codec` answers all six seam methods and `.conforms?` accepts it; the encoder and decoder round-trip a model through one instance (`json/codec_test.rb` `EncodeProfilesTest`, "SERDE-1: the seam's six methods are all present"; `json/defaults_test.rb`, "SERDE-1: the encoder and decoder round-trip through one bundle") |
| `SERDE-2` | MUST | ✅ | 9, 14 | `Dexpace::Body.serialized(value, serde:)`, the ninth factory beside 3b's eight: a replayable `BytesBody` over `serde.dump_bytes(value)` whose media type is the serde's declared one — a `MediaType` passed through, a `String` parsed through phase 1's `MediaType.parse` (which refuses a value the header grammar cannot carry, naming it), a nil or empty one refused naming the codec's class with **no format-agnostic fallback**; the codec answers `MediaType.parse("application/json")`, one frozen constant. The header itself is the transport's to stamp when the caller set none (`TRANSPORT-10`, phase 8), asserted on the composed request (`http/body_serialized_test.rb`, all eight cases; `json/codec_test.rb`, "SEAM-19/SERDE-2"; `json/composition_test.rb` `WriteTest`; guard 27) |
| `SERDE-3` | MUST | ✅ | 14, 15, 17 | A codec closes nothing: `#dump_to` writes and answers the count without closing the sink, `#dump_into` touches only the target region, `#load` reads to EOF (a `BufferedSource` through `#read_utf8`, a raw `#read` IO through a dropped `BufferedSource.wrapping`) and never closes the source — asserted against `CloseCountingSink` / `CloseCountingSource` whose counts read **exactly 0**, under the default and under every accepted option, "even when the codec's own auto-close feature is enabled" (the requirement's tail) meaning every option this adapter accepts (`json/codec_test.rb`, "SERDE-3: dump_to …"; `json/codec_load_test.rb` `StreamTest`, two `SERDE-3` cases; `json/seam_conformance_test.rb`, both cases; guard 15) |
| `SERDE-4` | MUST | ✅ (P7-5) | 14, 17 | `#dump_into(value, buffer, offset:)` answers the byte count, honours the offset, raises **`::IndexError`** — distinct from `Dexpace::Serde::Error` and `cause: nil` even when called from inside a caller's rescue — on a negative or out-of-range offset and on a payload that does not fit, with an EXPLICIT fit check because `String#[]=` silently grows a String on an over-long payload (verified fact 12), and leaves the bytes before and after the region untouched. The target is a mutable `Encoding::BINARY` String only; a frozen, non-BINARY or non-String buffer and a non-Integer offset are `InvalidArgumentError`, and Ruby's `IO::Buffer` is refused (P7-5: it warns through `Warning.warn` on construction and its `#set_string` raises `ArgumentError` where `String#[]=` raises `IndexError`); the adapter's suite asserts over its own source that no Ruby `IO::Buffer` is constructed (`json/codec_test.rb` `EncodeProfilesTest`, the four `SERDE-4` cases and the two `P7-5` cases; `SerdeSeamAssertions#assert_buffer_profile`; guards 16–18) |
| `SERDE-5` | MUST | ✅ | 3, 14, 15 | Every decode takes an explicit witness: `Codec#load(source, witness)` has no witness-less overload (`ArgumentError` with one argument), runs `Dexpace::Serde.witness!` on the second, and the result is the REAL type with typed field access; a `#call`-shaped object is not a witness (`json/codec_load_test.rb` `StreamTest`, "SERDE-5: decode through an explicit witness yields the real type", "there is no witness-less overload"; `serde/witness_test.rb`, the lambda case; guard 14) |
| `SERDE-6` | MUST | ✅ (clause stated) | 5 | Parametric targets are expressible as combinators built BY VALUE from a concrete element witness — `List.of(Pet)`, `Map.of(String, Pet)`, `Nullable.of(Pet)`, nesting freely, decoding to real DTOs, over the scalar spellings `String` / `Integer` / `Float` / `BOOLEAN`. **The clause stated:** the requirement's second half — "a format-agnostic decoder that cannot resolve type arguments MUST fail loudly … rather than silently decoding into the raw type" — is unreachable, not implemented: there is no witness-less overload to fall into and a combinator cannot exist without a concrete element, so no decoder ever holds a partially-resolved carrier (design §10.14) (`serde/list_test.rb`, `map_test.rb`, `nullable_test.rb`, `scalars_test.rb`, all cases) |
| `SERDE-7` | MUST | ✅ (clause stated) | 3 | Its antecedent is conditional — "(where the host language offers one)" — and Ruby offers no reified generics; the port satisfies it anyway in the strongest form available: the ergonomic route `serde.load(source, Pet)` passes the class object itself, and that route IS the carrier, so there is no raw-class shortcut beside it to forget to route through (`serde/witness_test.rb`, "the ergonomic spelling and the carrier spelling are the same object") |
| `SERDE-8` | MUST | ✅ (clause stated) | 3, 5, 6 | The no-type-argument half is implemented: `List.of(nil)`, `List.of(Object.new)`, `List.of(::Symbol)`, `Map.of(String, nil)`, `Nullable.of(nil)` and `Tristate.of(Object.new)` all raise `InvalidArgumentError` at CONSTRUCTION with an actionable message naming the missing method and the class — earlier than the reference's binder-resolution failure. **The clause stated:** the "unresolved type variable" half is unreachable, and that is §10.14's strength rather than a gap — a combinator cannot be built without a concrete element witness (`serde/list_test.rb`, "SERDE-8"; `map_test.rb`; `nullable_test.rb`; `tristate_decode_test.rb`; `witness_test.rb`; guard 13) |
| `SERDE-9` | MUST | ✅ (P7-6) | 14, 15, 17 | The write path raises `Dexpace::Serde::SerializationError` — core's `Native` refusing a non-native value NAMING ITS CLASS before the generator sees it, and the generator's own `GeneratorError` (a `NaN`, a BINARY String holding invalid UTF-8) rescued as `::JSON::JSONError` and re-raised INSIDE the rescue so Ruby chains it as `#cause`; the read path raises `DeserializationError` chaining `ParserError` / `NestingError`; and no `::JSON` type escapes the SPI. P7-6 adds the port's own read-side guard: invalid UTF-8 in the drained text is a `DeserializationError` with no cause, before the parser. A duplicate key is one `DeserializationError` across json 2.19.9–3.0 because the codec fixes `allow_duplicate_key: false` (P7-65) — proven at the keyword level since review round 0, because json 3.0.2 refuses a duplicate key by default and the behavioural case alone could not tell the codec's option from the library's (`json/codec_test.rb` `FailureModelTest`, `ConstructionTest`'s duplicate-key case, `CoderKeywordsTest`; `json/codec_load_test.rb`, "SERDE-13/SERDE-9", "SERDE-9: a nesting-depth failure", both `P7-6` cases; `serde/native_test.rb`; guards 20, 30, 34, 34.5) |
| `SERDE-10` | MUST | ✅ | 14, 17 | `SerializationError` and `DeserializationError` are two subtypes under phase 2's `Dexpace::Serde::Error` root, neither a kind of the other, so a caller distinguishes direction while catching one base (`json/codec_test.rb` `FailureModelTest`, "SERDE-10: the write-path subtype is distinct"; `SerdeSeamAssertions#assert_failure_model`) |
| `SERDE-11` | SHOULD | ✅ (clause stated) | — | Satisfied by the language and needing no code (design §11.15): every serde error is a `::StandardError` descendant and Ruby has no checked exceptions; asserted as ancestry beside the malformed-input case (`json/codec_load_test.rb`, "SERDE-13/SERDE-9", `assert_kind_of(::StandardError, error)`) |
| `SERDE-12` | MUST | ✅ | 10, 15, 17 | A genuine stream I/O error propagates UNWRAPPED, structurally: `Codec#load` rescues `::JSON::JSONError` around the parse ALONE, whose ancestry is `[ParserError, JSONError, StandardError]` with `IOError` nowhere in it (verified fact 4), so a `Dexpace::StreamError` (an `::IOError`) from the source, a raw IO's own `IOError`, and the over-ceiling `StreamError` all pass through the codec and the handler's `ensure`-close untouched; a raising sink's `IOError` too (`json/codec_load_test.rb` `StreamTest`, three cases; `serde/decoding_handler_test.rb` `MatrixTest`, two cases; `SerdeSeamAssertions#assert_io_error_passthrough`; guard 21.5 red, guard 21 the recorded equivalent) |
| `SERDE-13` | MUST | ✅ (P7-6) | 2, 15 | A wire null into a non-null target fails NAMING THE TARGET TYPE, across every decode overload — which is one method: `Codec#load` builds `DecodeContext.root(target: witness)` and `#error!` renders the ROOT frame as `expected Pet (Hash) at /, got NilClass` (a nested frame keeps the plain form, and a same-named `#present!` target is not doubled); the context, not a nil screen in `#load`, because `Tristate.of` and `Nullable.of` legitimately take a top-level null (`serde/decode_context_test.rb` `RaiseSiteTest`, all seven cases; `json/codec_load_test.rb` `ShapeTest`, "SERDE-13" and "SERDE-20"; guards 11, 12) |
| `SERDE-14` | MUST | ✅ (clause stated) | 4 | The substantive half is real code, closed on EVERY path: `Present` validates in `#initialize` with `Model.required!("value", value)` (`SEAM-29`'s message), `.new` AND `.[]` are private so `Present[value: nil]` is a `NoMethodError` and the `send`-past-private hole meets the same check, and `Model#with` routes a derivation through `.build` so `T.present(1).with(value: nil)` raises on every supported Ruby — on 3.2.11 the guard that substitutes `Data#with` goes red where 4.0.6 stays green, which is why `test:gems` on the floor is the proof. **The clause stated:** the covariance clause is satisfied by the language (design §11.15) and has no code (`serde/tristate_test.rb`, the three `SERDE-14` cases; guards 1–3) |
| `SERDE-15` | MUST | ✅ (P7-9) | 7, 16 | In an object, Absent omits the key, Null emits a wire null and Present emits the encoded inner value — in core's `Native` walk, which drops a Hash entry whose walked value is `OMIT` (`ABSENT#dexpace_dump`) and re-walks a Present's inner value so a nested model's Absent is dropped too; through the real codec, `{"name":"x"}` / `{"name":"x","nick":null}` / `{"name":"x","nick":"n"}`; and over a seeded property sample of tri-state models that round-trip exactly (`serde/native_test.rb`, both `SERDE-15` cases; `json/defaults_test.rb`, "SERDE-19", "SERDE-15/SERDE-16: a seeded sample"; guard 4) |
| `SERDE-16` | MUST | ✅ | 6, 16 | `Tristate.of(w).dexpace_load_field(hash, key, ctx)`: a missing key is Absent, an explicit null is Null, a value is Present of the element's decode at the key's own path with the declared element type preserved (`Float` widened, a mis-shaped value refused naming `/pet/x`) — three lines over `Hash#key?` (`serde/tristate_decode_test.rb`, "SERDE-16/SERDE-17", "SERDE-16: the inner value's declared element type", "the field's shape failure names the field's own path"; `json/defaults_test.rb`, "SERDE-16/SERDE-17"; guard 7) |
| `SERDE-17` | MUST | ✅ (clause stated) | 6 | An omitted field is Absent and NEVER Null, asserted as both predicates. **The clause stated:** the field-default machinery the requirement describes ("the field's declared default must be Absent … before the decoder's null hook runs") is a key-oriented codec's problem Ruby does not have — `JSON.parse` yields an ordinary Hash and `key?` distinguishes the two directly (verified fact 6) — so the behaviour its conformance clause names is implemented and none of the machinery is emulated (`serde/tristate_decode_test.rb`, "SERDE-17: an omitted field is Absent and never Null"; guard 7) |
| `SERDE-18` | SHOULD | ✅ | 4 | `Tristate.absent`, `.null`, `.present(value)` (refusing nil), `.from_nullable(value)` (Present or Null, never Absent — a different name from `.of`, deliberately), the three exhaustive and mutually exclusive predicates, `#value_or_nil` and the three-way `#fold` (`serde/tristate_test.rb`, the five `SERDE-18` cases; guard 8) |
| `SERDE-19` | MUST | ✅ (P7-9) | 7, 16 | The DEFAULT configuration wires tri-state with nothing registered: `Codec.default.dump_string` of a model with an Absent field omits the key and with a Null field emits null, because the wiring is core's `Native` walk and structural rather than a per-model convention; an adapter building a serde around a caller-supplied codec instance never happens (P7-4), so the register-by-default and opt-out clauses have no subject (`json/defaults_test.rb`, "SERDE-19: the DEFAULT configuration wires tri-state"; `serde/tristate_test.rb`, "#dexpace_dump"; guard 32) |
| `SERDE-20` | SHOULD | ✅ (P7-9) | 6, 7, 16 | Where no enclosing object can omit a key, both Absent and Null emit a wire null rather than throwing: an Array element that walks to `OMIT` is `nil` with its position kept, a top-level `OMIT` is `nil`, and through the real codec `"null"` / `"[null,null,\"v\"]"`; the decode half — a top-level null is Null through `Tristate.of`'s protocol entry point and nil through `Nullable.of` (`serde/native_test.rb`, both `SERDE-20` cases; `json/defaults_test.rb`, "SERDE-20"; `serde/tristate_decode_test.rb`, "SERDE-20"; `json/codec_load_test.rb`, "SERDE-20"; guards 5, 6) |
| `SERDE-21` | MUST | ✅ | 2, 15 | The nine named cross-shape coercions are nine explicit fixtures on `DecodeContext`, never a loop — string→integer, string→float, string→boolean, empty-string→integer/float/boolean, float→integer (`1.5` and `1.0`), boolean→integer and integer→boolean (`1` and `0`), boolean→float, non-string-scalar→string — each a `DeserializationError`; and through the real codec, which coerces nothing so the witness sees the wire shape (`serde/decode_context_test.rb` `CoercionTest`, the eight `SERDE-21` cases; `json/codec_load_test.rb` `ShapeTest`, "SERDE-21"; `serde/scalars_test.rb`; guard 9) |
| `SERDE-22` | MUST | ✅ | 2, 15 | The strict policy still permits the representation-preserving conversions: `#float!(1)` widens to `1.0`, `#string!("")` binds, and every well-typed value binds unchanged — through the context, through `List.of(Float)` over `[1]`, and through the real codec (`serde/decode_context_test.rb` `CoercionTest`, the three `SERDE-22` cases; `serde/list_test.rb`; `json/codec_load_test.rb`, "SERDE-22"; guard 10) |
| `SERDE-23` | SHOULD | ✅ | 5, 15 | An unknown field is ignored rather than failing, as the witness protocol's default — a witness reads the keys it declares and never enumerates the object, and core ships no strictness flag; asserted on a DTO and through the real codec (`serde/list_test.rb` through `Pet`; `json/codec_load_test.rb` `ShapeTest`, "SERDE-23"; `json/composition_test.rb`, the `"extra":true` payload) |
| `SERDE-24` | SHOULD | ✅ (P7-8) | 8, 16 | ISO-8601 strings, never epoch numbers: core's `Instant` renders `#iso8601(6)` and parses through `Time.iso8601` (refusing the lax forms and a non-String, naming `Time (ISO-8601)` at the path), and the adapter's default `encoders:` table wires `::Time`, `::DateTime` and `::Date` to it. The round trip holds exactly over the stated domain — any `Time` whose `subsec` is an exact multiple of one microsecond, proven over whole seconds, an exact-microsecond `Time`, a UTC offset and a 64-sample seeded property test — and P7-8's truncation outside it is asserted, not prose: `Time.new(2026,9,10,12,0,0.123456,"+02:00")` renders `…00.123455+02:00` and does not round-trip (`serde/instant_test.rb`, all eleven cases; `json/defaults_test.rb`, the four `SERDE-24` / `P7-8` cases and the Date/DateTime case; guards 31, 31.5) |
| `SERDE-25` | SHOULD | ✅ | 13, 14 | `Dexpace::Serde::JSON.default` and `Codec.default` are factories answering a fresh, independent instance on every call, and the registry's factory is `.default` itself; the memoising mutation goes red (`json/codec_test.rb` `ConstructionTest`, "SERDE-25"; `json_test.rb`, "the module's two factories"; guard 28) |
| `SERDE-26` | MUST | ✅ (P7-4; clause stated) | 14 | Satisfied literally and not through §11.18's fallback: the constructor takes OPTIONS, never a caller's coder — so "built around a caller-supplied codec instance" never happens — and each instance owns a private `::JSON::Coder` built from its own options (json 2.19.9's per-instance, freezable engine), with no reader; two codecs share no engine, and one built with `max_nesting: 4` reads the same five-deep document differently from the default on both the decode and the encode side. **The clause stated:** the antecedent is false by construction (`json/codec_test.rb` `ConstructionTest`, the two `SERDE-26` cases; guard 29) |
| `SERDE-27` | MUST | ✅ (P7-1; clause stated) | 10 | `Dexpace::Serde::DecodingHandler.build(serde:, witness:)`, a `_ResponseHandler` supplied into 3b's `TypedResponse`: it hands `#load` the body's own `#source` and copies nothing; closes the response in one unguarded `ensure` on EVERY path (a valid body, a missing body, an empty body, a codec failure, a mid-stream I/O error, a failing `eof?` probe) with the count read as exactly 1 off `FakeResponseBody`'s raw counter; surfaces a nil body AND an empty one — screened with `BufferedSource#eof?`, a non-consuming probe — as a `DeserializationError` naming the target (or `an anonymous witness` for a `Class.new` one, which has no name to carry — P7-70, review round 1's R1-4); and rescues nothing, so the codec's chained failure and an unwrapped `StreamError` both pass through. **The clause stated:** "without first materializing the whole body" is NOT satisfied (P7-1): the JSON adapter drains to EOF under `Dexpace::IO.max_materialized_bytes` and a body above it raises `Dexpace::StreamError`, unwrapped — the documented limit `docs/sdk-documentation/serde.md` now states, closing the first owed half of the `docs/first-release.md` entry; the second half waits on phase 8. A `BytesBody`-backed response raises `StreamError` naming the class and `Body.buffer` is the readable spelling, asserted as a contract (`serde/decoding_handler_test.rb`, all fifteen cases — the empty-body case asserting BOTH halves of the message since review round 1, because the witness's own shape failure over a drained `""` names the target too; `json/composition_test.rb`, an empty 200 through the real codec; guards 22, 23, 23.5) |
| `SERDE-28` | MUST | ✅ | 11, 18 | `Dexpace::Serde::StatusAwareHandler.build(serde:, witness:, factory:)`: a 2xx delegates to a `DecodingHandler` (one implementation of `SERDE-27`); 400, 404, 500 and the **non-canonical 599** raise the factory's error — `ProtocolError.for` by default, one frozen lambda, `raise error, cause: nil` — over `Recovery.buffer_error_body`'s bounded copy, readable twice after the live response closed, with NO second close (the raw counter reads 1) and the error payload never reaching the witness; a 304 with `ETag` and `Location`, a malformed `ETag`, a multi-valued `Location`, a 100, a 301 and a 307 close the response (a close failure propagates) and raise a `DeserializationError` leading with the code and carrying the raw header values, parsed by nothing; a factory returning a non-Exception is refused. The composed path — `Operation` → `Pipeline.standard` → `TypedResponse` — asserts the 200, 404, factory and 304 branches end to end (`serde/status_aware_handler_test.rb`, all nineteen cases — a 304 through an anonymous witness reads `an anonymous witness`, never an empty name, since review round 1; `json/composition_test.rb`; guards 24–26, 36) |
| `SERDE-29` | SHOULD | ✅ (clause stated) | 14, 17 | A frozen codec is safe to share: eight threads × 200 rounds encoding and decoding distinct values through one instance, every thread joined, no corruption; and through the lift target. **The clause stated:** the cache clause has no subject — the witness is supplied per call and nothing is memoised by type, asserted as no `cache`/`memo` ivar on the codec, which is what a phase-9 `XCUT-12` audit will look for here (`json/codec_test.rb` `ConstructionTest`, both `SERDE-29` cases; `SerdeSeamAssertions#assert_shareable`) |
| `SERDE-30` | MAY | ✅ (taken) | 4, 7 | `ABSENT`, `NULL` and `OMIT` print as `"Absent"`, `"Null"` and `"Omit"` for both `#to_s` and `#inspect`, asserted as string equality; the three are frozen singletons of classes a caller cannot name (`serde/tristate_test.rb`, "SERDE-30"; `serde/native_test.rb`, "OMIT is a frozen sentinel") |

Cross-reference rows, the IDs this phase owns a share of or composes — each "composition asserted,
not satisfied here" where an earlier phase satisfies it:

| ID | Status | What 7a supplies, and where it is proven |
|---|---|---|
| `SEAM-19`, `SEAM-20`, `SEAM-21` | ✅ implemented against | Phase 2's six-method seam is implemented, not redesigned: `#media_type` a `MediaType`, the four encode profiles, `#load` reading to EOF and closing nothing; `interface _Codec` edited in place — `#media_type` to `(Dexpace::MediaType \| String)`, `#load` over `_Witness`, `#dump_to` to `Integer` — never a second interface (P7-61) (`json/codec_test.rb`; `json/codec_load_test.rb`; `sig/dexpace/serde.rbs`) |
| `SEAM-22` | ✅ surviving clause honoured | The witness protocol §10.14 substituted is built; the surviving clause — `#load` takes an explicit witness, no witness-less overload — holds on the real codec (`json/codec_load_test.rb`, "there is no witness-less overload"). The ID's row is phase 2's and does not move |
| `SEAM-23` | ✅ consumed | Both subtypes raised from the adapter under phase 2's class root; no second root (`json/codec_test.rb` `FailureModelTest`) |
| `SEAM-2` | ✅ mechanised | `Dexpace::Serde::JSON` appears in no core `lib/`, `sig/` or `test/` file outside a comment — a Ripper-based scan, because two core comments already name the adapter (P7-68) — and the seam supplies no media type; the adapter's registration is asserted only in the adapter's suite, and core's "starts empty on a bare require" pins now assert in a child process (`serde/no_concrete_codec_test.rb`; `seam_surface_test.rb`; `serde_test.rb`) |
| `SEAM-26`, `SEAM-27` | ✅ composition asserted | Phase 2 satisfies; Task 18 asserts the composition: `Operation.build(method:, template:, projections:)` → `#build_request` → `Pipeline.standard` over a recording lambda transport → `TypedResponse`, with `a/b` reaching the wire as one `a%2Fb` segment and a `PATCH` body carried as a `Dexpace::Body` (`json/composition_test.rb` `ReadTest`, `WriteTest`) |
| `HTTP-44`, `HTTP-45` | ✅ consumed | 3b's `TypedResponse` is supplied into, never replaced: the handler runs once across three `#value` calls, a memoised failure is re-raised as the SAME object with its cause, and no second memo, `@state` or lock exists in 7a (`serde/decoding_handler_test.rb` `ConstructionTest`; `serde/status_aware_handler_test.rb` `MappedTest`, "TypedResponse takes it") |
| `HTTP-41`, `HTTP-42`, `BODY-14`, `BODY-16` | ✅ consumed | `#source` is THE read handle (no `respond_to?` fallback; a `BytesBody` raises by design) and `Response#body_string` reads the buffered error copy twice (`serde/decoding_handler_test.rb`, the `BytesBody` case; `serde/status_aware_handler_test.rb`, "readable twice") |
| `BODY-30`, `HTTP-52`, `RECOV-16` | ✅ composition asserted | `Recovery.buffer_error_body` is the ONE buffering call site and closes the live body itself; the 4xx branch adds no second buffering and no second close, and the copy is readable repeatably after the walk (`serde/status_aware_handler_test.rb`, "adds no second close"; `json/composition_test.rb`, the 404 case) |
| `RECOV-15` | ✅ composition asserted | The `factory:` keyword is `ErrorMappingStep`'s spelling — one frozen lambda over `ProtocolError.for` as the default, `Registry.callable?` at arity 1 — and a generated SDK's factory decodes the buffered body into its own type through it (`json/composition_test.rb`, "the factory keyword lets a generated SDK decode the error body") |
| `IO-9`, `BODY-32` | ✅ consumed | `#load` drains through 3a's `#read_utf8`, guarded by `Dexpace::IO.max_materialized_bytes` (5a's per-call reader) — one ceiling, cited and never re-derived; the over-ceiling `StreamError` propagates unwrapped (`json/codec_load_test.rb`, "R1/P7-1") |
| `IO-6`, `BODY-8` | ✅ third rule beside them | A codec closes nothing (`SERDE-3`) — the third ownership rule, which phase 3 left to this layer (`message-bodies/a7afc6ee`) — sits beside 3a's wrapping-takes-ownership and 3b's closes-what-it-opened, and the handler's response close is the layer above both (`json/codec_load_test.rb`; `serde/decoding_handler_test.rb`, "the handler closes the response and hands the codec the body's own source, unclosed") |
| `HTTP-3`, `HTTP-4`, `SEAM-29` | ✅ | Every public `Data` follows the construction pattern: `DecodeContext`, `Present`, `List`, `Map`, `Nullable`, `DecodingHandler` and `StatusAwareHandler` have `.new` and `.[]` private, a validating `.build` over ALL members, validation in `#initialize`, `Model.required!`'s one message form, and `#with` through `.build` (P7-66; every suite's construction case) |
| `XCUT-12` | ✅ by construction | No mutex in the phase; the codec is frozen after construction and holds no per-type cache (the `SERDE-29` row) |
| `XCUT-15` | ✅ by construction | `DecodeContext#path` through `Model.own`, `Native` returning fresh collections and copying a mutable String, the combinators frozen `Data`s (`serde/decode_context_test.rb`, "#path is the model's own frozen copy"; `serde/native_test.rb`, "never aliases the caller's") |
| `TRANSPORT-10` | ✅ boundary stated | `Body.serialized` stamps no header; the media type is the body's and the transport writes it when the caller set none — asserted as the header's absence on the composed request (`json/composition_test.rb` `WriteTest`) |
| `NFR-1`, `NFR-2` | ✅ spent | `dexpace-serde-json` declares `dexpace-core` plus exactly one third-party gem, `json >= 2.19.9`, the one place that floor is stated; `gates:gemspec_audit` accepts it and refuses a second (guard 33a); core's gemspec still has zero `add_dependency` lines and core's five stdlib requires are unchanged (`json_test.rb`, "NFR-2", "REQUIRED_CORE") |
| `NFR-3` | ✅ | Eleven core mirrors, two adapter mirrors and phase 2's `serde.rbs` edited in place; `rbs:validate` and the strict `core` Steep target green with no relaxation; the `:serde_json` target alone downgrades `Ruby::UnknownConstant` to `:information` for the one `::JSON::Coder` reference rbs 4.2.0 does not declare (P7-62) |
| `NFR-4` | ✅ | Every addition is a widening; the manifests grew by exactly 86 rows — core 1 137 → 1 210, the adapter 2 → 15 — regenerated once and read row by row against the object model with no private constant among them; the RBS baseline diff is vacuous until the first tag |
| `NFR-11` | ✅ | No constant outside `Dexpace::` and the stdlib allowlist in any public signature: core's serde signatures name `::Time` alone, the adapter's name no `::JSON` type (the engine ivar is `untyped`); a `::JSON::State` return in a public signature is refused by `gates:rbs_surface` (guard 33d) and a `::JSON::Coder` ivar type by `rbs:validate` (guard 33c) |
| `NFR-13` | ✅ for `.rb`; the `.rbs` half is phase 10's | The thirty-four new `.rb` files — eleven under core's `lib/`, one under the adapter's, nineteen suites and three doubles — open with the two headers the `Dexpace/SpdxHeader` cop gates; the twelve new `.rbs` files carry no SPDX line, as no `.rbs` in the repository does (phase 10's `gates:spdx_rbs`), as 6a's and 6b's rows record |

## What was built

Eleven new `lib/` files under `gems/dexpace-core/lib/dexpace/serde/`, in the entry file's dependency
order: `decode_context.rb`, `witness.rb` (reopening phase 2's `Dexpace::Serde` the way `closeable.rb`
defines `Dexpace.close_quietly`; `serde.rb`'s body is untouched), `native.rb` (`Native`, and the `OMIT`
sentinel over the private `Omit` class), `scalars.rb` (the private `Scalars` module with its `Scalar`
class and `TABLE`, and the public `BOOLEAN`), `tristate.rb` (`Tristate`, `ABSENT`, `NULL`, `Present`, the
private `Combinator` behind `.of`), `list.rb`, `map.rb`, `nullable.rb`, `instant.rb`,
`decoding_handler.rb` and `status_aware_handler.rb`. One core file widened in place, 3b's `http/body.rb`
(`Body.serialized`, plus two `require_relative`s), and one phase-2 `sig/` file edited in place,
`sig/dexpace/serde.rbs` (`interface _Codec`'s three clauses; P7-61). Every new file has a `sig/` mirror
— every nested `private_constant` declared there with the tree's "no visibility in RBS" comment —
and a `test/` mirror, with three core suites beside the mirrors that say so in their headers:
`serde/tristate_decode_test.rb` (the combinator's decode half), `http/body_serialized_test.rb` (7a's one
addition to 3b's module) and `serde/no_concrete_codec_test.rb` (the `SEAM-2` scan). No new core
`private_constant` FILE: the layer's private constants (`EMPTY_PATH`, `ROOT`, `Omit`, `NO_ENCODERS`,
`Scalars`, `Absent`, `Null`, `Combinator`, `EXPECTED`, `DEFAULT_FACTORY`) all live inside public files,
so `CLAUDE.md`'s eighteen test-mirror exceptions are unchanged. The entry file gains an eleven-line
`# Phase 7a:` block after 6b's. **In `gems/dexpace-serde-json`:** the gemspec's `json >= 2.19.9` line;
the entry file rewritten (`require "json"`, `require "dexpace"`, `MINIMUM_JSON_VERSION`, `REQUIRED_CORE`,
the top-level floor assertion raising `Dexpace::SeamError`, `.default`, `.build`, the registration under
`:json`); the new `lib/dexpace/serde/json/codec.rb` (`Codec` with its private `Options` module,
`DEFAULT_ENCODERS` and `MEDIA_TYPE`) with its `sig/` mirror and the entry file's `sig/` rewritten; the
smoke test `json_test.rb` reshaped to snapshot AFTER `require "dexpace"`, `json`, `time` and `date` and
extended with five cases; six new suites beside it — `json/codec_test.rb` (the codec's mirror; four nested
classes, the fourth review round 0's keyword pin),
`json/codec_load_test.rb` (two), `json/defaults_test.rb`, `json/seam_conformance_test.rb`,
`json/composition_test.rb` (two) and, since review round 1, `json/floor_test.rb`, which drives P7-7's
require-time floor assertion in a child process with the bundler environment stripped (R1-2) — and three
new `test/support/` files, `close_counting_source.rb`,
`close_counting_sink.rb` and `serde_seam_assertions.rb`, the last the file phase 9 lifts into
`dexpace-conformance`. The `Steepfile`'s `:serde_json` block gains its one relaxation and its comment;
`rbs_collection.yaml` is as `main` has it — its stale "json arrives with the codec in phase 7" sentence
is routed, not rewritten, because the file is a shared one outside this phase's bounds (review round
0, R0-1; Findings routed). **Five
existing core tests changed on the code branch as pins the registration invalidated**:
`seam_surface_test.rb`'s two seam-iterating pins ("starts empty on a bare require", "no seam's
zero-candidate error names a concrete gem") now run a child process that requires `dexpace` alone and
prints one row per seam — the `IO.popen([RbConfig.ruby, "-w", "-Ilib", "-e", PROGRAM], err: %i[child
out], chdir:)` shape of `instrumentation/independence_test.rb` — and `serde_test.rb`'s "starts empty"
pin the same way, while its two swap pins assert the swapped-in codec is no longer what resolves
(`refute_same` over a `resolved_after_swap` helper), because `Registry#swap` restores `resolved` and
never `factories`; 8a is making the identical conversion of the same two `seam_surface_test.rb` lines,
and the reconcile pass keeps one copy. The surface manifests were regenerated once, with all 86 rows
read against the object model. The dexpace_test.rb `LAYERS` table is untouched: 7a adds no flat
constant under `Dexpace`. **Review round 1 changed two `lib/` lines** (R1-4): `DecodingHandler#missing_body`
and `StatusAwareHandler#unhandled_message` derive the target's name through a private `#target_name`
that falls back to the literal `"an anonymous witness"` where `DecodeContext.root` gives an anonymous
class no target (P7-70), declared in both `sig/` mirrors; a named witness's messages are byte-for-byte
what they were.

## Matrix facts, re-run on every interpreter

The design's fifteen facts and the ones the build found were re-run on 2026-09-20 on **3.2.11, 3.3.12,
3.4.10 and 4.0.6**, against json **3.0.2** (the bundle's on every ABI, and installed in the 3.2.11 and
4.0.6 gem directories) and json **2.19.9** (the floor, pinned by `gem "json", "2.19.9"` in an unbundled
subprocess on 3.4.10). Uniform across the range and the two versions: `JSON.parse(StringIO)` raises
`TypeError` (fact 1); `JSON.generate(Object.new)` returns the inspect string and `strict: true` raises
(fact 3); `JSON::ParserError < JSONError < StandardError` with `IOError` nowhere in it (fact 4);
`JSON.parse` coerces nothing, `key?` distinguishes null from absent, `JSON.parse("null")` is `nil`
(fact 6); a `"\xff"` payload yields a UTF-8-tagged String whose `#valid_encoding?` is false (fact 7);
`JSON::Coder` exists, is freezable, and is **strict on its own account** — `Coder.new.dump(Object.new)`
and `.dump(Time.at(0))` raise `GeneratorError` with no `strict:` at all (fact 8, sharpened);
`Time#iso8601(6)` truncates `0.123456` to `…123455` and an integer-microsecond `Time` round-trips
(fact 9); `Time.iso8601` rejects the lax forms; `String#[]=` grows the target (fact 12); `Data#with`
skips an `initialize` override on 3.2.11 and runs it on 3.3+ (fact 14, the reason `Model#with` is
load-bearing); `Data.define`'s `.[]` stays public under `private_class_method :new` alone (fact 15).
**Version-sensitive, and the reason the option allowlist exists** (`docs/knowledge/notes/serde.md`):
`JSON::Coder.new`'s parameters are `[[:opt, :options], [:block, :as_json]]` on 2.19.9 and keywords with
a `**options` rest on 3.0.2; an unknown option is swallowed on 2.19.9 and refused with `ArgumentError`
on 3.0.2; `encoders:` is accepted on 2.19.9 and refused on 3.0.2; `Coder.new(nil)` works on 2.19.9 and
raises on 3.0.2; a duplicate key is last-wins on 2.9.1, a `warning:` on 2.19.9 under `-w` (which the
suite's fatal-warnings base turns into an error) and a `ParserError` on 3.0.2, while
`allow_duplicate_key: false` raises `ParserError` on both. **The interpreters' installed json**:
3.2.11 and 4.0.6 hold 3.0.2 beside their stock 2.6.3 / 2.18.0; 3.3.12 and 3.4.10 held only their stock
2.7.2 / 2.9.1 — neither with `JSON::Coder` — until `gates:clean_bundle` fetched 3.0.2 from rubygems.org
into each on this run (the Findings routed section). `BufferedSource#eof?` is a non-consuming probe,
true on an empty source and false otherwise, and `#read` with no length answers `""` at EOF, never nil.
The one thing that differs in a MESSAGE across the versions — `JSON.parse("")`'s text — is matched
nowhere.

## Guards run red

Every guard the brief lists was seen red, on 4.0.6 and on 3.2.11, and the bytes restored after each:
thirty-four single-edit mutations of `lib/` (the brief's thirty-two plus two the build added, 21.5 and
31.5), one at a time through a scratch harness that applies the edit, runs the owning suites under
`ruby -w`, captures the first failure and restores the file with `git checkout --`; plus the four gate
mutations of guard 33 on 4.0.6. On the first pass **thirty-one of thirty-four were caught on both rows;
guard 3 on 3.2.11 alone, as the brief predicted; and two were equivalent mutants, recorded with their
reasons rather than hidden** — 19, because `JSON::Coder` is strict on its own account, and 21, because
the parse rescue's scope is the parse alone. Guard 18's assertion is not vacuous: the seam assertion
calls `#dump_into` from inside a `rescue`, and dropping `cause: nil` turns it red. **Review round 0
(2026-09-20) ran forty-two of its own and found one more surviving on both rows** — the explicit
`allow_duplicate_key: false` default dropped from `Codec#initialize`, invisible on the bundle's json
3.0.2, where a duplicate key is a `ParserError` by default, and a warning-plus-last-wins only at the
2.19.9 floor, which no gate row runs — so the option is now pinned at the keyword level, in a child
process that records what `::JSON::Coder.new` receives (`codec_test.rb` `CoderKeywordsTest`), and the
battery is **thirty-five, thirty-three caught on both rows, guard 3 on 3.2.11 alone and guard 21 the
one equivalent mutant**: guard 34 is the round's, red on 4.0.6 with json 3.0.2 and on 3.4.10 with json
2.19.9 pinned unbundled, and guard 19, an equivalent mutant behaviourally, is red at the keyword level
through the same pin (34.5 below is the third thing the pin holds). **Review round 1 (2026-09-20) ran
fifty-nine of its own and found two more surviving on both rows**, each against a behaviour the design
states and this document claimed pinned: the `eof?` screen's raise reduced to a bare probe (23.5 below —
the empty-body case asserted only `/PetWitness/`, which the witness's own shape failure over the drained
`""` names too, so the case was green with the screen gone and the round found guard 23's third failure
to be the `eof?`-probe case, not it), and P7-7's require-time floor block deleted outright (35 below —
no gate row runs a json below the floor, so nothing saw it). Both are pinned on the tests branch, the
second in a child process with the bundler environment stripped; the round's one nit that reached
`lib/`, the anonymous-witness fallback, is guard 36. The battery is **thirty-eight, thirty-six caught
on both rows, guard 3 on 3.2.11 alone and guard 21 the one equivalent mutant**.

| # | Fix reverted | Guard | What it said (4.0.6; identical on 3.2.11 unless stated) |
|---|---|---|---|
| 1 | `SERDE-14`: `Model.required!` dropped from `Present#initialize` | `tristate_test.rb` | `Dexpace::InvalidArgumentError expected but nothing was raised` (3 failures) |
| 2 | `SERDE-14`: `.[]` left public, validation in `.build` alone | `tristate_test.rb` | `Expected Dexpace::Serde::Tristate::Present to not respond to []` |
| 3 | `SERDE-14`: `Data#with` bound in place of `Model#with` | `tristate_test.rb` | **3.2.11: RED** — `Dexpace::InvalidArgumentError expected but nothing was raised` on "#with cannot derive a Present holding nil"; **4.0.6: GREEN**, because `Data#with` runs the `initialize` override there. Interpreter-sensitive as predicted, and why `test:gems` on the floor is the proof |
| 4 | `SERDE-15`: the Hash branch stores `nil` instead of dropping an `OMIT` | `native_test.rb`, `defaults_test.rb` | `--- expected {"name" => "x"} +++ actual {"name" => "x", "nick" => nil}` (6 failures) |
| 5 | `SERDE-20`: the Array branch drops an `OMIT` element | `native_test.rb` | `Expected: [nil, nil, "v"] Actual: ["v"]` (3 failures) |
| 6 | `SERDE-20`: `OMIT` returned at the top level | `native_test.rb` | `Expected Omit to be nil` |
| 7 | `SERDE-16`/`17`: `#dexpace_load_field` tests `nil?` instead of `key?` | `tristate_decode_test.rb`, `defaults_test.rb` | `Expected Absent to be null?` — the explicit null read as Absent (3 failures) |
| 8 | `SERDE-18`: `from_nullable(nil)` answers `ABSENT` | `tristate_test.rb` | `Expected Absent to be null?` |
| 9 | `SERDE-21`: `#integer!` accepts a numeric String | `decode_context_test.rb` | `Dexpace::Serde::DeserializationError expected but nothing was raised` on "string to integer is rejected" |
| 10 | `SERDE-22`: `#float!` rejects an Integer | `decode_context_test.rb`, `list_test.rb` | `DeserializationError: expected Float at /0, got Integer` (2 errors) |
| 11 | `SERDE-13`: `#error!` renders the plain form at the root | `decode_context_test.rb`, `codec_load_test.rb` | `--- expected "expected Pet (Hash) at /, got NilClass" +++ actual "expected Hash at /, got NilClass"` (2 failures) |
| 12 | `SERDE-13`: `Codec#load` builds `DecodeContext.root` with no target | `codec_load_test.rb` | the same diff on "a wire null into a non-null target names the target type", `decode_context_test.rb` green — the two layers are separately pinned |
| 13 | `SERDE-8`: `List.of` skips `Scalars.resolve` | `list_test.rb` | `NoMethodError: undefined method 'dexpace_load' for class String` (1 failure, 3 errors) |
| 14 | `SERDE-5`/`8`: `witness?` also accepts `#call` | `witness_test.rb`, `decoding_handler_test.rb` | `Expected true to not be truthy` on the lambda case; the non-witness-at-construction case (2 failures) |
| 15 | `SERDE-3`: `Codec#load` closes the source | `codec_load_test.rb`, `seam_conformance_test.rb` | `SERDE-3: #load closed the caller's source. Expected: 0 Actual: 1` (4 failures) |
| 16 | `SERDE-4`: the explicit fit check dropped | `codec_test.rb`, `seam_conformance_test.rb` | `IndexError expected but nothing was raised` — the String silently grew (4 failures) |
| 17 | `SERDE-4`: `SerializationError` raised for an overflow | `codec_test.rb`, `seam_conformance_test.rb` | `[IndexError] exception expected, not Class: <Dexpace::Serde::SerializationError>` (4 failures) |
| 18 | `SERDE-4`: `cause: nil` dropped | `codec_test.rb`, `seam_conformance_test.rb` | `Expected #<RuntimeError: in flight> to be nil` — the in-flight error chained (3 failures) |
| 19 | `SERDE-9`/`10`: `strict: true` dropped from the Coder | `codec_test.rb` | **Behaviourally equivalent on both rows**: `JSON::Coder` is strict on its own account on 2.19.9 and 3.0.2 (`Coder.new.dump(Object.new)` raises `GeneratorError` with no option), so `strict: true` is documentation of intent; `Native` is the observable layer and is pinned by the class-naming assertion. Kept, and the YARD says so. **Red since review round 0 through the keyword pin**: `CoderKeywordsTest` — `+++ actual ["allow_duplicate_key=false", "allow_duplicate_key=true", …]`, `strict=true` gone from every line |
| 20 | `SERDE-9`: `dump_string` re-raises with `cause: nil` | `codec_test.rb`, `seam_conformance_test.rb` | `Expected nil to be a kind of JSON::JSONError, not NilClass` (2 failures) |
| 21 | `SERDE-12`: the parse rescue widened to `StandardError` | `codec_load_test.rb`, `seam_conformance_test.rb` | **STAYED GREEN on both rows, and is equivalent**: `parse(text)` wraps `@coder.load(text)` alone, and the I/O error arises in `drain(source)` outside it, so widening that rescue cannot reach the stream — the scope, not only the class, is what keeps `SERDE-12` structural |
| 21.5 | `SERDE-12`: a `StandardError` rescue around the drain, re-raising as `DeserializationError` | `codec_load_test.rb`, `seam_conformance_test.rb` | `[Dexpace::StreamError] exception expected, not Class: <Dexpace::Serde::DeserializationError>` (6 failures; `[IOError]` on 3.2.11's first line) |
| 22 | `SERDE-27`: the `ensure response.close` dropped | `decoding_handler_test.rb`, `status_aware_handler_test.rb` | `Expected: 1 Actual: 0` on `body.closes` (8 failures) |
| 23 | `SERDE-27`: the nil-body and `eof?` screens dropped | `decoding_handler_test.rb`, `status_aware_handler_test.rb` | `[Dexpace::Serde::DeserializationError] exception expected, not Class: <NoMethodError>` on the bodyless case and on the anonymous-witness 204; `[Dexpace::StreamError] exception expected, not Class: <NoMethodError>` on the `eof?`-probe case, whose double has no `#read`; `Expected /no body/ to match "expected … PetWitness (Hash) at /, got String"` on the empty-body case; the status-aware 204 beside them (4 + 1 failures). **As first recorded the third failure was attributed to the empty-body case; review round 1 found that case GREEN under this guard** — the failure was the `eof?`-probe case — and its `/no body/` assertion is the round's repair (23.5) |
| 23.5 | `SERDE-27`: the `eof?` probe kept and its raise dropped (`raise missing_body if source.eof?` → `source.eof?`; review round 1's 23c) | `decoding_handler_test.rb`, `composition_test.rb` | `Expected /no body/ to match "expected DexpaceSerdeDecodingHandlerTest::PetWitness (Hash) at /, got String"` on the empty-body case, and `Expected /no body to decode into DexpaceSerdeJSONCompositionTest::Pet:/ to match "malformed JSON: unexpected end of input at line 1 column 1"` on the composed empty 200 through the real codec (2 failures). **Survived every suite on both rows before review round 1** |
| 24 | `SERDE-28`: the 4xx branch delegates to the decoder | `status_aware_handler_test.rb` | `Dexpace::ProtocolError expected but nothing was raised` (9 failures) |
| 25 | `SERDE-28`: a second `response.close` in the 4xx branch | `status_aware_handler_test.rb` | `Expected: 1 Actual: 2` on `body.closes` — visible only because `FakeResponseBody` counts raw closes (2 failures) |
| 26 | `SERDE-28`: the third-branch message does not lead with the code | `status_aware_handler_test.rb`, `composition_test.rb` | `Expected /\A304\b/ to match "Not Modified 304: not decoded into …"` (3 failures) |
| 27 | `SERDE-2`: `application/octet-stream` as the fallback | `body_serialized_test.rb` | `Dexpace::InvalidArgumentError expected but nothing was raised` on "no format-agnostic default" |
| 28 | `SERDE-25`: `.default` memoised | `codec_test.rb`, `json_test.rb` | `Expected #<Codec …> to not be the same as #<Codec …>` |
| 29 | `SERDE-26`: the Coder hoisted to one class-level shared instance | `codec_test.rb` | `Dexpace::Serde::SerializationError expected but nothing was raised` on the `max_nesting: 4` encode case, and `DeserializationError: malformed JSON: nesting of 5 is too deep` on the default's decode (3 failures, 2 errors). A first spelling of this mutation crashed the suite on an unused-variable warning under `NFR-6` and was re-spelled to keep the variable live, as 6b's guards 25 and 46 were |
| 30 | `P7-6`: the `valid_encoding?` guard dropped | `codec_load_test.rb` | `Dexpace::Serde::DeserializationError expected but nothing was raised` — a UTF-8-tagged invalid String came back |
| 31 | `SERDE-24`: `#iso8601` with no digits | `instant_test.rb`, `defaults_test.rb` | `Expected: 2025-09-10 12:00:00.123456 UTC Actual: 2025-09-10 12:00:00 UTC` — the microsecond round trips (10 failures) |
| 31.5 | `SERDE-24`: `time.to_i.to_s` (an epoch number) | `instant_test.rb`, `defaults_test.rb` | `DeserializationError: expected Dexpace::Serde::Instant (Time (ISO-8601)) at /, got String` (6 failures, 6 errors) |
| 32 | `SERDE-19`: `ABSENT#dexpace_dump` answers `nil` | `defaults_test.rb`, `native_test.rb`, `tristate_test.rb` | `--- expected {"name":"x"} +++ actual {"name":"x","nick":null}` and `Expected nil (oid=4) to be the same as Omit` (7 failures) |
| 33a | a second `add_dependency "rake"` in the adapter gemspec | `gates:gemspec_audit` | `dexpace-serde-json declares json, rake; NFR-2 allows core plus at most one third-party library.` (a gem outside the bundle, `oj`, is refused earlier still, by Bundler's own resolution) |
| 33b | `require "json"` in `serde/instant.rb` | `gates:require_allowlist` | `instant.rb:5: require "json" -- SEAM-2: the wire codec is a seam. It lives in dexpace-serde-json, and the >= 2.19.9 floor lives in that gemspec and nowhere else` |
| 33c | `@coder: ::JSON::Coder` in the adapter's `codec.rbs` | `rbs:validate` | `codec.rbs:20:16...20:29: Could not find ::JSON::Coder (RBS::NoTypeFoundError)` |
| 33d | `-> ::JSON::State` on a public method in `codec.rbs` | `gates:rbs_surface` | `codec.rbs: public signature references JSON::State, which is outside Dexpace:: and the stdlib allowlist` |
| 34 | `P7-65`: the explicit `allow_duplicate_key: false` default dropped from `Codec#initialize` (review round 0's X7) | `codec_test.rb` `CoderKeywordsTest` | `--- expected ["allow_duplicate_key=false strict=true", …] +++ actual ["strict=true", "allow_duplicate_key=true strict=true", "max_nesting=4 strict=true", …]` on 4.0.6 with json 3.0.2 and on 3.4.10 with json 2.19.9 pinned unbundled — where `ConstructionTest`'s behavioural duplicate-key case goes red too, through `NFR-6`'s fatal `warning: detected duplicate key "a" in JSON object`, the only row it ever could: on 3.0.2 that case stays green under the mutant, because the library refuses a duplicate key by default |
| 34.5 | `P7-65`: `encoders:` forwarded to the Coder (`table.compact` in place of `table.except(:encoders).compact`) | `codec_test.rb` `CoderKeywordsTest`, `ConstructionTest` | the third recorded line reads `allow_duplicate_key=false encoders={Time => #<Proc…>} max_nesting=4 strict=true`; on 3.0.2 the library refuses the keyword first (`ArgumentError: unknown keyword: encoders`) and the "encoders: replaces the default table" case errors beside it, while on 2.19.9 only the keyword pin sees it |
| 35 | `P7-7`: the require-time floor block deleted from `json.rb` (review round 1's N1) | `floor_test.rb` | `Expected /\ASEAM_ERROR json=2\.18\.0 / to match "LOADED json=2.18.0 keys=[:json]"` — the interpreter's stock json loads and registers, the silently-unpatched case the deviation exists for (`2.6.3` on 3.2.11, where the same line goes red). **Survived every suite and every gate on every row before review round 1**: no gate row runs a json below the floor, so the child pins the interpreter's default json by exact version with `gem` and requires the entry file with `RUBYOPT`, `RUBYLIB` and the `BUNDLE_*`/`BUNDLER_*` keys cleared |
| 36 | `P7-70`: the `"an anonymous witness"` fallback dropped from either handler's `#target_name` (review round 1's R1-4) | `decoding_handler_test.rb`, `status_aware_handler_test.rb` | `Expected /no body to decode into an anonymous witness:/ to match "no body to decode into : the response carried none (SERDE-27)"` and `Expected /\A304 Not Modified: not decoded into an anonymous witness,/ to match "304 Not Modified: not decoded into , only a 2xx body is (SERDE-28)"` (1 failure each) |

## Audit groups run

The phase-start pair first, at implementation: `--origin note --brief` returned 56 note entries across
22 files; `--section conflicts --brief` returned 25 entries with every one of the six harvested
conflicts `[overridden by notes/…]` and none open. The thirteenth audit group's `SERDE` slice —
`--prefix SERDE --section rules,constraints,conclusions` — returned 36 entries across two topic
files, **zero tagged `[appendix-B roll-up]`**, covering all 30 IDs (the four a `--section rules`
reading misses, `SERDE-17`, `24`, `25` and `30`, are filed under Constraints and Conclusions — the
design's narrowness finding, now a one-cell edit of the skill's row); chapter 14 was read in full, its
`*Conformance:*` clauses included. The five note entries the brief binds were read in full:
`pipeline/86343352` and `pipeline/7ce4431d` (the carried re-raise is `raise error, cause: nil` — the
`StatusAwareHandler`'s factory-built error and `#dump_into`'s `IndexError`, and nowhere else, because
the two codec re-raises are of the error just rescued, inside the rescue, so the chain is wanted),
`error-handling/5322e965` (no suppressed trail is attached in 7a: no `SERDE` requirement describes a
two-failure path, and a close raising in the handler's `ensure` propagates over the primary),
`execution-context/b58728da` (no `private_constant` of `Dexpace` is reached from a compact `module`
form; `Scalars` is a `private_constant` of `Serde`, named bare from full-nesting bodies) and
`url-and-query-encoding/08c54234` (7a parses no URL).

| Group | Result at implementation |
|---|---|
| Public API surface | `module-organization/1828a984` (one public constant per file) holds: `native.rb` carries `Native` and `OMIT` on 5b's `keys.rb` two-constants precedent with the `Omit` class private, `scalars.rb` carries `BOOLEAN` with `Scalars` private, `tristate.rb` the module with its three members and the private `Combinator`, `codec.rb` the class with its private `Options`; `api-design/b0e18938` is why `Scalars`, `Combinator`, `Omit`, `Absent`, `Null`, the codec's `Options` and every default table are private and why the codec has no `coder` / `options` reader; every public name is in the design's object model or in P7-2/P7-3 |
| RBS / Steep typing | Twelve new mirrors and three edited in place (`serde.rbs`, `http/body.rbs`, the adapter's `json.rbs`); the strict `core` target green with no relaxation and two `#: Type` annotations on empty-collection locals (the tree's idiom); the `:serde_json` target's one relaxation named and commented; `_Witness` an interface inside `Dexpace::Serde` on the `_Source`/`_Sink`/`_Span` convention, `_Codec` left at `Dexpace::_Codec` where phase 2 put it |
| Minitest conventions | Every suite subclasses `DexpaceTestCase`; the six suites over 100 code lines are split into nested classes over a shared `Fixtures` module (6c's shape); `assert_same` wherever identity is the claim (the memoised failure, the shared root context, the body's own source handle); no `Hash#inspect` asserted; every parser error asserted by class, never by message; the seeded `sample` helper for both property tests; every thread joined |
| Encoding and binary strings | Every encoding assertion carries non-ASCII content (`é`, `héllo wörld`, `Ré`); `#dump_bytes` is `.b` of a UTF-8 String, `#dump_into`'s target must be BINARY, `#read_utf8` retags and `P7-6` validates; the ingress retag is never `force_encoding` on a frozen chunk |
| Serialization, SSE and pagination | Every `SERDE` rule in the group restates a clause implemented above; `serde/b5e5efc8` (the strictness burden on the witness) and `serde/5fe8e3ed` (`key?`) are what `DecodeContext` and `Tristate::Combinator` are built on; `serde/5e420c20`'s `JSON.load` ban is honoured (`::JSON::Coder#load` is `::JSON.parse`'s configured form, and the YARD says so at the call site); no `SSE` or `PAGE` rule is consumed |

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate. Items
1–22 are where the built tree overrode the plan's assumptions, in the order the brief's as-built list
gives them; 23–31 are this build's. The ones that touch public behaviour, the contract a later phase
cites, or a statement the design makes are also the as-built ledger rows P7-61–P7-72.

1. **`interface _Codec` was never empty and lives at `Dexpace::_Codec`.** Task 12's fence would have
   written a second interface at `Dexpace::Serde::_Codec`; the existing one was edited in place with
   the three clauses (P7-61), `_Witness` was put inside `Dexpace::Serde` on the namespace-local
   convention, and `sig/dexpace.rbs` — a two-line stub — was not touched. The design's headline finding
   is withdrawn in its As-built addendum with the evidence (all four phase-2 files carry bodies since
   c881f92), and the roadmap's phase-10 bullet carries a dated bracketed correction.
2. **Five core pins invalidated by the require-time registration**, converted on the code branch as
   the manager decided: two subprocess assertions in `seam_surface_test.rb`, one in `serde_test.rb`,
   and two swap pins asserting the override is gone (P7-63).
3. **`Response.build(status:, body:)` does not exist and `TypedResponse.new` refuses a non-Response**,
   so the plan's `CountingResponse` double was never written: every handler test builds a real
   `Response` through `RecoveryFixtures#build_response` over 3b's `FakeResponseBody`, whose raw
   `#closes` counter is what makes guard 25's second close visible (P7-64). `Body.buffer` takes a
   `Dexpace::IO::Buffer`, `Headers#[]` answers the value list, and the 304 headers are built through
   `headers_with(...).new_builder.add(...)`.
4. **`FakeCodec` hands its witness BINARY bytes**, so the two upcase witnesses retag before folding, and
   the "empty body" screen never reaches `nil.upcase` (`#read` answers `""` at EOF).
5. **The json facts moved**: 3.0.2 everywhere in the bundle, `Coder.new` keywords-only with an unknown
   key refused, `encoders:` refused, a duplicate key a `ParserError`. Hence the option allowlist, the
   keyword-only construction, `allow_duplicate_key: false` fixed, and `encoders:` never forwarded
   (P7-65); the design's open question 4 premise is true at the floor and false at 3.0, and the codec's
   YARD says so.
6. **The empty body is detected with `BufferedSource#eof?`**, never `#content_length` (which is `-1` for
   every unknown-length body) and never a parser message; the plan's "convert a codec-side end-of-input
   `ParserError`" clause was not written (P7-67).
7. **RuboCop refused the fences as written**: `Codec.build` and `JSON.build` take one positional Hash
   (`Model#with`'s idiom) rather than a `**` splat; every rescue variable is `error`; `Native`,
   `Instant` and `Scalars` use `extend self`; `Native.of` is a scalar/collection/encoded trio of private
   helpers; `dump_into`'s validation is a private `buffer!`; the codec's option validation is a private
   `Options` module (`Metrics/ClassLength`); six suites are split into nested classes; and every test
   line is under 100 columns.
8. **Steep on `::JSON::Coder`**: json 3.0.2 ships no `sig/`, so the manager's first route was closed and
   the second taken — the `:serde_json` target alone downgrades `Ruby::UnknownConstant` to
   `:information`, commented, with the ivar typed `untyped` (P7-62); `rbs_collection.yaml` needed no
   row and is as `main` has it — the feat commit had corrected its stale comment, and review round 0
   (R0-1) had the hunk dropped as a rewrite of a shared file outside this phase's bounds; the
   correction is routed (Findings routed).
9. **The gemspec line landed before the first `require "json"`**, and every one of
   `gates:gemspec_audit`, `gates:require_allowlist` and `gates:clean_bundle` passed on every row;
   `clean_bundle` fetched json 3.0.2 into 3.3.12's and 3.4.10's gem directories (Findings routed).
10. **The `SEAM-2` scan reads code, not comments, through Ripper**, because `serde.rb` and
    `http/method.rb` already name the adapter in a comment and the plan's raw `include?` would have
    failed on `main`; the test excludes itself by `File.expand_path(__FILE__)` (P7-68).
11. **Every `Data` has a public `.build` over ALL its members, `private_class_method :new, :[]` and
    validation in `#initialize`** (P7-66): `DecodeContext.build(path:, target:)` is public and `#at`
    routes through it; `StatusAwareHandler`'s members are `(serde, witness, factory)` with the
    `DecodingHandler` derived in `#initialize`; `Present#initialize` carries `Model.required!` so `.[]`
    and `send(:new, …)` meet the same check.
12. **Every nested `private_constant` is declared in its `.rbs`** with the tree's comment, and the test
    mirrors are one per `lib/` file (`list_test.rb`, `map_test.rb`, `nullable_test.rb`,
    `scalars_test.rb`, never one `combinators_test.rb`), with `tristate_decode_test.rb` and
    `body_serialized_test.rb` as extras beside the mirrors.
13. **`blank?` does not exist**; `Body.serialized` writes the nil/empty test out, and its `serde:` is
    also checked for `#dump_bytes` and `#media_type` so a non-codec is refused by name.
14. **The default factory is a frozen lambda**, `ErrorMappingStep`'s shape, never
    `ProtocolError.method(:for)`; the three-branch dispatch reads `Response#success?` / `#error?`.
15. **The composition slice runs `Pipeline.standard` over a three-positional lambda**, since core's
    `FakeTransport` is out of another gem's test tree (styleguide 12.6) and the plan's
    `require_relative "../../../support/fake_transport"` resolves to nothing; the recording transport
    is a small class whose `#to_proc` is the lambda (P7-69).
16. **The docs edited for 7a only**, on top of what `main` says: `CLAUDE.md`'s built-phase sentence, the
    layer paragraph, 184 → 195, fifteen checklists, the adapter's `lib/` sentence, five "Constraints"
    lines; `docs/README.md`'s fifteen pages; root `README.md`'s gem table and skeleton sentence;
    `architecture.md`'s `serde.md` entry with the `write-a-serde.md` placeholder left in place.
17. **The register entries the design already filed were verified and not re-filed**:
    `docs/first-release.md`'s `7a P7-1` entry (its first owed half now closed by `serde.md`), the
    `dexpace-serde-oj` second motive, the generated-style worked-example blocker; the knowledge-lookup
    row's Query column gained `constraints,conclusions`; `docs/knowledge/notes/serde.md` is new with the
    drafted UTF-8 entry and a second entry on the `Coder` option drift.
18. **The `# Phase 7a:` block is at the END of `lib/dexpace.rb`**, after 6b's, in dependency order;
    `witness.rb` reopens `Dexpace::Serde` and `serde.rb`'s body is untouched; the `LAYERS` table is
    untouched.
19. **`strict: true` is not observable past `Native`** — and, sharper than the brief's point 19,
    `JSON::Coder` is strict on its own account, so guard 19 is an equivalent mutant behaviourally on
    every row; kept as documentation of intent, with a Native-bypassing pin that drives the private
    engine directly, and — since review round 0 — pinned at the keyword level with
    `allow_duplicate_key: false` by `CoderKeywordsTest` (guards 19, 34, 34.5).
    `raise ::IndexError, …, cause: nil` is asserted from inside a `rescue` (guard 18 red).
20. **Ledger numbering** from P7-61 (P7-61–P7-72); no design row renumbered; 7b's and 7c's rows never
    cited.
21. **Nothing installed**: all four interpreters were present; the facts were re-run on all four and
    json 2.19.9 was reached by pinning it in an unbundled subprocess on 3.4.10 from the cross-check's
    scratch gem home.
22. **The manager's four decisions were followed as written**: route (2) for Steep; the child-process
    pins on the code branch; the roadmap bullet's bracketed correction; `clean_bundle`'s fetch recorded
    once and routed, and `clean_bundle_check` not edited.
23. **`DecodeContext.root` names an anonymous class as nothing** — `Module#name` is nil for
    `Class.new`, so the root falls back to the shared no-target instance rather than rendering
    `#<Class:0x…>` into every message (P7-70). Since review round 1 (R1-4) the two handler messages
    that interpolate that target — `DecodingHandler#missing_body` and
    `StatusAwareHandler#unhandled_message` — fall back to the literal `"an anonymous witness"` through a
    private `#target_name`, so a 204 or a 304 through an anonymous witness no longer reads
    "decode into : the response"; the context's own rule is unchanged.
24. **`#pointer` is RFC 6901 exact (`""` at the root) and `#error!` renders the root frame as `/`** for
    readability, the design's own message form; a same-named `#present!` target at the root is not
    doubled.
25. **`Native`'s Hash keys are String or Symbol, coerced to String, and anything else raises** — an
    Integer key is refused rather than stringified, the loud direction the walk exists for; a Symbol
    VALUE is not native and raises, and the design's rule 7 is followed rather than softened (P7-71).
26. **`Native`'s encoder lookup is exact class first, then the first `is_a?` match in table order**, so
    `DateTime` finds its own entry before `Date`'s and a caller's `Numeric` entry catches a `Rational`.
27. **`Codec#load` accepts a raw IO answering `#read`** beside a `BufferedSource`, by wrapping it in a
    dropped `BufferedSource.wrapping` — the same read, the same ceiling, the caller's IO left open —
    because phase 2's own seam test passes a `StringIO` and `SERDE-3`'s subject is "a caller-supplied
    stream" (P7-72).
28. **`Codec#dump_to` answers `bytes.bytesize` rather than the sink's return value**, so the count is
    the codec's and a sink answering something else cannot mis-report it; a sink without `#write` is
    refused by name.
29. **The 304 message form is `<code> <canonical name>: not decoded into <target>, only a 2xx body is
    (SERDE-28); etag: …; location: …`**, the raw values joined with `", "` per header the way a
    header line reads.
30. **`Body.serialized`'s test suite is `http/body_serialized_test.rb`**, beside 3b's `body_test.rb`,
    never inside it.
31. **The smoke test's "defines nothing outside Dexpace" pins `Codec MINIMUM_JSON_VERSION
    REQUIRED_CORE VERSION`** as the module's four constants and `:JSON` as the one sibling added, with
    the snapshots taken after `require "dexpace"`, `json`, `time` and `date`.

## Findings routed

- **The design's four findings were verified at their owners and not re-filed**, with one withdrawn:
  the `_Codec` finding rests on a false premise — all four phase-2 `sig/` files have carried bodies
  since c881f92 — and is withdrawn in the design's As-built addendum, with the roadmap's phase-10
  bullet corrected in place by a dated bracketed sentence (the manager's decision 3); the
  `SERDE`-audit-group narrowness is a one-cell edit of `.claude/skills/knowledge-lookup/SKILL.md`'s
  thirteenth row, applied; the `SERDE-27` release entry in `docs/first-release.md` is cited by the
  `SERDE-27` row, and its first owed half — the documented ceiling behaviour — is closed by
  `docs/sdk-documentation/serde.md`, the entry updated to say so and to leave the phase-8 half open;
  `dexpace-serde-oj`'s second motive is already on its post-v1 entry.
- **New, routed to phase 10's inbound list** as audit-or-repair work against the phase-0 gate, by date
  and content: `gates:clean_bundle` installs into the running interpreter's gem directory and, on the
  first adapter with a third-party dependency, fetched json 3.0.2 from rubygems.org into 3.3.12's and
  3.4.10's on this run; the repair is a `BUNDLE_PATH` under the scratch directory. Phase 8a's Task 23
  owns `clean_bundle_check` this wave and may close it there.
- **New, routed to phase 10's inbound list by date and content, after review round 0 (R0-1)**:
  `rbs_collection.yaml`'s header comment says "json arrives with dexpace-serde-json's codec in phase 7",
  and 7a added no row — `json`'s signatures are rbs's own stdlib set, resolved already, and json 3.0.2
  ships no `sig/` — so the sentence is stale on the tree and stays stale, because the file is a shared
  one outside 7a's bounds that phase 8a's first row rewrites; whichever lane adds the first row closes
  it, and the roadmap's bullet says so.
- **New corpus note**, `docs/knowledge/notes/serde.md`, two `## Reference` entries: the UTF-8 validation
  the design drafted, and the json 2.19.9 → 3.0 `JSON::Coder` option drift the build measured, both
  with the keys they rest on cited in support (`[cited by]`, never overriding).
- **The design's ledger** gains an "As built" addendum (P7-61–P7-72); the consolidation of P7-1–P7-9
  and P7-61–P7-72 into design §10 is a human's, as for every phase since 3a, because
  `docs/sdk-design-ruby/` is frozen. `docs/deviations.md` is untouched, for phase 10 to flip.
- **8a's identical conversion of `seam_surface_test.rb:17` and `:22`** is the manager's reconcile chore:
  both stacks are green alone, and one copy is kept at merge.

## Postponed work

**None of 7a's own.** All thirty IDs are implemented; design §12's `SERDE` row ("*Deferred:* none") is
unchanged. **What earlier phases postponed here has landed**: phase 3b's `TypedResponse` has its two
handlers and the ninth body factory; phase 2's `_Codec` clauses are settled; phase 3's third ownership
rule (`message-bodies/a7afc6ee`) is implemented whole. **What this phase leaves to others, none of it its
own to defer**: `SERDE-27`'s no-materialization clause (`7a P7-1`, the `docs/first-release.md` entry,
whose remaining half is phase 8's pull-parser check); the phase-9 lift of
`gems/dexpace-serde-json/test/support/serde_seam_assertions.rb` into `dexpace-conformance`; the
`clean_bundle` install location (phase 10, or 8a's Task 23); the wire-boundary re-validation of the
`Content-Type` `Body.serialized` implies (phase 8a's Task 16, phase 8c's Task 9). 7b and 7c are
independent of this sub-phase and of each other, and neither consumed anything here.
