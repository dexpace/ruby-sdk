# Phase 7a — Serialization

**Status:** Draft, for review. Written 2026-09-10, against
`docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md`, which is this sub-phase's charter.

**Path:** `docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization-design.md`. That is the path
this document carries for the rest of its life and the one every citation of it should use. Its plan
is `docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization.md`; the checklist is written at
execution time and is not this document's to draft.

## Purpose

Sub-phase 7a builds serialization in full: the **witness protocol** design §10.14 substituted for the
reference's reflective type token, its four combinators and its decode context; the **`Tristate`**
three-state PATCH type; the **native-form encode walk** that makes `SERDE-15`/`SERDE-19`/`SERDE-20`
structural rather than a per-model discipline; the **`SERDE-2` body factory**; the **two response
handlers** supplied into phase 3b's `Dexpace::TypedResponse`; and the **JSON codec** that fills
`gems/dexpace-serde-json/lib/` and declares the `json >= 2.19.9` floor. Thirty requirement IDs, all
`SERDE`, `SERDE-1`–`SERDE-30`: 22 MUST, 7 SHOULD, 1 MAY.

**It is the sub-phase the charter recommends first**, for four reasons the charter gives and this
document does not re-argue — it is the only sub-phase touching a second gem, it exercises three
phase-0 gates against a gem with a third-party dependency for the first time, it puts the one
cross-gem `sig/` arrangement in place before `7b`'s larger RBS surface arrives, and a scaffold defect
surfaced here still has two sub-phases' room to absorb it. **None of that makes `7a` a dependency of
`7b` or `7c`,** and the Prerequisites section states that independence in `7a`'s own words rather
than inheriting a chain by habit.

Four decisions the charter named and declined to make are made here — `R1`, `R2`, `R3` and `R12`.
Three of them turn on facts this document **measured** rather than inherited, and the sharpest of the
three inverts a premise the charter had to reason around:

- **`R1` is confirmed, and confirmed against the floor rather than against the interpreter's default
  gem.** The charter verified `JSON.parse(StringIO.new(…))` raising `TypeError` on **json 2.9.1**, the
  version Ruby 3.4.10 ships. This document installed **json 2.19.9** — the exact floor
  `dexpace-serde-json`'s gemspec will declare — and re-ran the check: `TypeError` again,
  `JSON::Parser.instance_methods(false)` is still `[:parse, :source]`, and nothing in the 2.19.9
  singleton-method list is pull-shaped. `SERDE-27`'s no-materialization clause is therefore
  **deviated, not satisfied**, and it is numbered `P7-1`.
- **json 2.19.9 has `JSON::Coder`, and json 2.9.1 does not.** Verified both ways. That is a real,
  per-instance, freezable, thread-safe codec engine — which means `SERDE-26`'s "MUST operate on a
  private copy of the codec engine" is satisfiable *literally* on the floored version, rather than
  through §11.18's near-vacuous reading and the requirement's own documented-fallback clause.
  `P7-4`, and it is stronger than the design's stated resolution in the direction the requirement
  wants.
- **`::JSON.generate` does not raise on an unserializable value; it silently stringifies it.**
  Measured on both 2.9.1 and 2.19.9: `JSON.generate(Object.new)` returns
  `"\"#<Object:0x…>\""`. `SERDE-9`/`SERDE-10` require an unserializable value to raise the
  serialization subtype. The adapter therefore passes `strict: true`, and core's native-form walk
  rejects a non-native value before the generator ever sees it — two layers, because the silent
  route is the default one.

## Governing documents

- `docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md` — the charter. It fixes `7a`'s 30
  IDs, the twenty-four spec-forced boundaries, the five rejected cuts, the one convergence point
  (which is `7b`'s and `7c`'s, not `7a`'s) and risks `R1`, `R2`, `R3` and `R12`.
- `docs/product-spec/14-serialization-serde.md`, read in full (57 lines), together with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` for the canonical text
  and modal level of all 30 IDs. Every one of the 30 appears in its own prose chapter, so appendix C
  is a convenience here rather than a necessity — and the chapter's `*Conformance:*` clauses, which
  appendix C does not carry, are load-bearing in five places named below.
- `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.4 in full
  (`03-seam-by-seam-idiomatic-mapping.md:295-350`) — the six-method codec duck type, the four
  allocation profiles and the pair that nearly collapses, why the codec is a separate gem, the two
  naming hazards, the two adapter defaults; and §3.1's encoding boundary, which `#load` crosses.
- `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md` §7.3 in full
  (`07-pagination-sse-and-serialization.md:99-174`) — the witness, the combinators, the P9 argument,
  where the witness is cashed in, `Tristate`, and the three closing notes.
- `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items **12**
  (`:87-91`, the stream-ownership rule whose third clause is the codec's), **13** (`:92-96`, four
  encode profiles, two of which are one Ruby type) and **14** (`:97-102`, the witness as a
  class-object-and-combinator protocol). Both 13 and 14 already govern `7a`; it inherits them rather
  than re-deciding them.
- `docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md`
  items **15** (`:51-53`, clauses with no Ruby manifestation — `SERDE-11` and `SERDE-14`'s covariance)
  and **18** (`:59-62`, `SERDE-26` presuming a mutable codec engine); and §12's `SERDE` row
  (`docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md:38`), which reads
  "*Deferred:* none".
- `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md` and its plan
  `…-quality-gates.md` — the seventeen gates, the require allowlist with `json` on its **denylist**
  by name (`:459`), the adapter extension to the same audit (`:471-475`), the gemspec audit's
  `NFR-2` budget, the clean-bundle isolation run, the five custom cops (`:523`), and
  `gems/dexpace-serde-json`'s skeleton (`:254-260`; plan `:1374-1398`, `:2628-2630`).
- `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md` — `Dexpace::Model`
  (`.required!`, `#with`, `.own`, `.frozen_string`), `Dexpace::MediaType`,
  `Dexpace::InvalidArgumentError < ::ArgumentError`, `Dexpace::Status#error?`, `Dexpace::Error` as a
  **module**.
- `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` (`:942-1005`) and its plan's
  Task 12 (`docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md:4270-4610`) — the six-method
  `Dexpace::Serde` duck type read as **code**, its `CONTRACT`, `.conforms?`, `.missing_methods` and
  the five registry entry points, `FakeCodec`, and the
  `Error`/`SerializationError`/`DeserializationError` hierarchy with its class root (`P2-2`). Also
  `Dexpace/QualifiedCoreConstant` (`:1295`).
- `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md` —
  `Dexpace::IO::BufferedSource`'s read vocabulary, **`#read_utf8`/`#read_string(encoding)` retagging
  and applying no replacement policy** (`:657-658`, `:939`), `Dexpace::IO::MAX_MATERIALIZED_BYTES`
  and `P3-4`'s widening (`:1109`), `Dexpace::StreamError < ::IOError`, and the
  frozen/non-BINARY-destination rejection precedent (`:826`).
- `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md` — `Dexpace::Body`'s
  contract row for `#source` and `#close` (`:706-764`), the eight factories, `Body.buffer_bounded`
  and `MAX_BUFFERED_ERROR_BODY_BYTES`, `Response#close`/`#body_string`/`#body_bytes`, and **`R7` in
  full** (`:514-558`) — `Dexpace::TypedResponse.new(response:, handler:)` over
  `Dexpace::_ResponseHandler`, and the sentence that fixes `7a`'s shape: "`#call(body)` or
  `#call(bytes)` would be narrower and would force phase 7 to **replace** `TypedResponse` rather than
  supply a handler into it" (`:535`).
- `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md` —
  `Dexpace::ProtocolError` with `.for`/`.for_or_nil` (`:1110-1134`),
  `Dexpace::Recovery.buffer_error_body` (`:1136-1150`), `ErrorMappingStep`'s `factory:` keyword
  (`:1186-1200`), `Dexpace.attach_suppressed`/`.suppressed`/`.each_cause`, `Dexpace.close_quietly`,
  and the forward table's phase-7 rows (`:1528-1529`).
- `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md` — read only to confirm
  that `7a` installs no step and touches nothing of 4c's.
- `docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry-design.md` and
  `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-design.md` as the two closest worked
  examples of this document's form.
- `docs/deferred-items.md` (`DEF-16`, `DEF-22`, `DEF-26`, `DEF-29`), `docs/open-items.md` (`OI-7`,
  `OI-10`, `OI-12`), `docs/deviations.md`, `docs/first-release.md`.
- `CLAUDE.md` and `docs/README.md`.

---

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run before anything here was written, and re-run
for this document rather than trusted from the charter's report.

`ruby scripts/knowledge.rb --origin note --brief` returns **38 entries across 19 note files**.
`ruby scripts/knowledge.rb --section conflicts --brief` returns **24 entries across 17 topic files,
18 of them notes and six harvested**, and **all six harvested ones print `[overridden by notes/…]`**
(`data-modeling/35fde90f`, `module-organization/bf6411ad`, `package-and-dependency-layout/41b154a3`
and `/8c0687bf`, `tooling-and-quality-gates/86d763f1`, `type-system/93dc79aa`). **None is open**, so
`7a` inherits no unresolved conflict and owns no conflict decision of its own.

Narrowed to this sub-phase's one prefix, `--origin note --prefix SERDE --brief` returns **one** entry
and `--section conflicts --prefix SERDE --brief` returns the same one — `message-bodies/a7afc6ee`,
which is the note that hands `7a` its work by naming what phase 3 declined to touch:

> A third ownership rule exists and belongs to neither layer — `SEAM-20`/`SEAM-21`/`SERDE-3`
> (`serde/cfbe4e9a`), where **a codec closes nothing** — and phase 3 neither implements nor weakens
> it.

<sub>review · `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md` · high · sha:manual-phase3a-io6-ownership-home</sub>

`serde/cfbe4e9a` prints `[overridden by notes/message-bodies.md:8]` for the **citation half only**;
its content — `SERDE-3` itself — stands unchanged and is `7a`'s to implement whole.

**Corpus coverage: complete.** `ruby scripts/knowledge.rb --prefix-info SERDE` reports **30 of 30
IDs substantive, 0 roll-up only, 0 uncited**, owning chapter
`docs/product-spec/14-serialization-serde.md`, topics `serde`, `sdk-positioning` and
`message-bodies`. `ruby scripts/knowledge.rb --gaps SERDE` closes with "0 of 30 IDs in 1 prefix have
no substantive entry". **`7a`'s spec-reading budget is zero**, which the section below states in the
form the roadmap requires.

**The audit group was run, and the charter's thirteenth row is what named it.** The
`knowledge-lookup` skill's audit-group table is owed a row the charter drafted and could not add —
*Serialization, SSE and pagination*, `--topic serde,sse-streaming,pagination --section rules --brief`
and `--prefix SERDE,SSE,PAGE --section rules --brief`. Narrowed to this sub-phase, `7a` ran
`--prefix SERDE --section rules` (26 entries, one topic file, **zero roll-up-tagged**),
`--prefix SERDE --section constraints,conclusions` (10 entries across two topic files) and
`--topic serde --role design` (33 entries). Those three cover all 30 IDs with no gap: `SERDE-17` is
in *Constraints* only (`serde/18a5757b`) and `SERDE-24`, `SERDE-25` and `SERDE-30` are in
*Conclusions* only (`serde/fccbd8a5`, `/d3bef411`, `/9c037363`), so a `--section rules` audit alone
would have missed four of the thirty. That is the same species of navigation hazard the charter
recorded for `sse-streaming/5f4803a0` and `pagination/b2a85752`, arriving from a different
direction, and it is proposed as a register finding below.

**The charter's roll-up warning holds for `SERDE` and matters here.** `--prefix SERDE --brief`
returns 79 entries of which **30** are `[appendix-B roll-up]`, and `--req SERDE-17` returns eight
roll-up entries beside the two that answer it. Every query above therefore carried
`--section`; a bare `--req` was used nowhere in writing this document.

**The entries `7a` is built on, cited by key rather than restated**, except where the rule turns on
the sentence:

- **`serde/b5e5efc8`** — the strictness argument this whole sub-phase's decode side rests on.
  "`JSON.parse` performs no coercion, so `"5"` never silently becomes `5`; the strictness burden
  moves into the witness, where each field asserts its expected class and raises a
  `DeserializationError` naming the target type on mismatch — which is also how `SERDE-13` is
  enforced." (`SERDE-21`, `SERDE-22`, `SERDE-13`, `SERDE-26`.)
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:164-167` · high · sha:4bf713047534</sub>
- **`serde/5fe8e3ed`** — why `SERDE-17`'s asymmetry does not bite. "Because `JSON.parse` yields an
  ordinary `Hash`, `hash.key?("x")` distinguishes an absent key from a present null directly, making
  Ruby's `Tristate` decode side simpler than a key-oriented codec's; the witness decides per key with
  full knowledge of the enclosing model's shape." (`SERDE-17`, `SERDE-16`.)
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:156-159` · high · sha:4bf713047534</sub>
- **`serde/ffc92673`** — `SERDE-8`'s unreachable state, and why that is a strength rather than a gap.
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:119-126` · high · sha:4bf713047534</sub>
- **`serde/d15ade64`**, **`serde/9672c682`**, **`serde/66ebd950`** — the three reasons the codec is a
  separate gem, of which the second is `7a`'s one gemspec line and the third is a constraint on how
  `7a` writes the adapter (one code path, all policy at the seam) rather than a task.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:324-333` · high · sha:bf7f85fc5f18</sub>
- **`serde/5e420c20`** — why `JSON.load` is banned by lint rule and not by convention. "`JSON.load`
  accepts a proc and has historically enabled `create_additions`, the arbitrary-object instantiation
  hazard behind CVE-2020-10663, defaulted off only from json 2.7.0, giving it no place in a
  security-sensitive decode path." This is the entry `R1` collides with: `JSON.load` is the **only**
  IO-accepting entry point json has.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:335-338` · high · sha:bf7f85fc5f18</sub>
- **`serde/e9047c51`** and **`serde/97665a9a`** — `TypedResponse`'s `@state` memo and its
  flip-only mutex. Both are **3b's, shipped**; `7a` writes no second memo and no second lock, and
  cites these so that fact is visible from this document rather than only from 3b's.
  <sub>design · `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md:134-149` · high · sha:4bf713047534</sub>
- **`io-and-byte-streams/6eb5155f`** — the single decode boundary is retag then transcode, both
  encodings named, because bytes from the wire are `Encoding::BINARY` and `String#encode` with
  `undef: :replace` and no explicit target destroys every byte at or above `0x80` and follows
  `Encoding.default_internal`. `OI-7`. `7a`'s `#load` crosses this boundary, and verified fact 7
  below is what it adds to the recipe.
  <sub>review · `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md` · high · sha:manual-phase3b-decode-retag-then-transcode</sub>
- **`data-modeling/83610619`** — `Dexpace::Model#with` routes through the type's own validating
  `.build`, because `Data#with` does not call an `initialize` override on Ruby 3.2 and does on 3.4
  and 4.0. `Tristate::Present` includes `Dexpace::Model` and therefore cannot be `#with`-ed into
  holding `nil` on any supported Ruby — which is `SERDE-14`'s unrepresentable fourth state closed on
  the derivation path as well as the construction path.
  <sub>review · `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md` · high · sha:manual-phase1-data-with</sub>

**One knowledge note is filed by this document's plan**, and its subject is verified fact 7 below:
`#read_utf8` and `#read_string(encoding)` **retag without validating**, and `::JSON.parse` accepts
invalid UTF-8 without raising, so the two compose into a silent corruption path that no phase-3 test
covers because phase 3a's own contract is "retag, no replacement policy". The note is written under
`docs/knowledge/notes/serde.md` as a `## Reference` entry naming `serde/b5e5efc8`, because it does
not supersede that rule — it adds the guard the rule's "each field asserts its expected class" cannot
reach, since a `String` that is invalid UTF-8 is still a `String`. Drafted in *The knowledge note
`7a` files* below; the plan's final task writes it.

## The spec-reading budget

**Zero, and stating that is the obligation.** The roadmap requires a phase whose IDs come back as
gaps to budget reading time in its design document and say so there
(`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:154-155`); `--gaps SERDE` reports 0 of 30,
so the budget is zero and this sentence discharges the obligation.

**What that does not license**, restated from the charter because it applies to `7a` specifically:
`--gaps` measures *corpus* coverage, not *specification* coverage (`OI-12` states the same asymmetry
from the other side). Chapter 14 was read in full anyway, at 57 lines, and the `*Conformance:*`
clauses appendix C does not carry are load-bearing in five places — `SERDE-3`'s close-counting
tracker "even when the codec's own auto-close feature is enabled", `SERDE-4`'s four-part buffer
assertion, `SERDE-9`'s "its cause is the library's exception", `SERDE-27`'s five-case matrix, and
`SERDE-28`'s "a **non-canonical** 599". Each is quoted where a decision below turns on it.

---

## Scope: the 30 IDs

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `SERDE-1`–`SERDE-30` | 30 |
| ⏳ deferred | none — design §12's `SERDE` row reads "*Deferred:* none" | 0 |
| **Total in budget** | | **30** |

Level split, derived mechanically from appendix C on 2026-09-10 and matching the charter's: **22
MUST, 7 SHOULD (`SERDE-11`, `SERDE-18`, `SERDE-20`, `SERDE-23`, `SERDE-24`, `SERDE-25`, `SERDE-29`),
1 MAY (`SERDE-30`)**. No `MUST NOT` row appears. **No `DEF-<n>` moves an ID into `7a` and none moves
one out.**

### Nine rows carry a clause the checklist must state rather than tick

Each is on the authority of a design appendix, a measured fact, or a requirement's own conditional
antecedent — never on `7a`'s convenience.

- **`SERDE-11` is satisfied by the language and needs no code.** Design §11.15
  (`11-appendix-…md:51-53`): "**SERDE-11**'s unchecked exceptions and **SERDE-14**'s covariance are
  satisfied by the language and need no code." Ruby has no checked exceptions; every
  `Dexpace::Serde::Error` is a `::StandardError` descendant and appears in no declared signature.
  The row states the vacuity with §11.15 as its authority.
- **`SERDE-14` splits, and the row says which half is which.** The covariance clause is §11.15's
  vacuity above. The *substantive* half — Present bounded to non-null so the illegal fourth state is
  unrepresentable — is **real code**, closed on both the construction path (`Present.build` rejects
  `nil`) and the derivation path (`Dexpace::Model#with` routes through `.build`,
  `data-modeling/83610619`). A row marking the whole ID vacuous would be wrong.
- **`SERDE-6`'s second half is unreachable, not implemented.** "A format-agnostic decoder that cannot
  resolve type arguments MUST fail loudly (serde exception) for a genuinely parametric carrier rather
  than silently decoding into the raw type." There is no such decoder in this port: `#load` takes a
  witness by value, a combinator is built from a concrete element witness, and there is no
  witness-less overload to fall into (phase 2's `SEAM-22` surviving clause, `serde/4eeb87ad`). The
  row states the unreachability and cites §10.14; it does not emulate a failure with no input.
- **`SERDE-7`'s antecedent is conditional and the port satisfies the requirement anyway.** Its own
  text scopes it "(where the host language offers one)". Ruby offers no reified generics — but the
  port's ergonomic route is `serde.load(source, Pet)`, passing the class object itself, and **that
  route *is* the generic carrier** rather than a raw-class shortcut beside it. There is no "forward
  only the raw class" path to forget to route through, because the two paths are the same path. The
  row states that, and it is the strongest form of the requirement available on this host.
- **`SERDE-8`'s unresolved-type-variable rejection is unreachable, and that is a strength argued in
  §10.14.** A combinator cannot be constructed without a concrete element witness, so there is no
  partially-resolved carrier to reject (`serde/ffc92673`). `Dexpace::Serde.witness!(w)` fails at
  witness *construction* — earlier than the reference's binder-resolution failure. The
  no-type-argument half **is** implemented: `List.of(nil)` and `List.of(Object.new)` both raise.
- **`SERDE-17` is vacuous by measurement, and the measurement is the row's content.** Verified fact
  6: `JSON.parse(%q({"x":null})).key?("x")` is `true` and `JSON.parse("{}").key?("x")` is `false`.
  The reference's "the field's declared default must be Absent and the decoder's empty-value fallback
  must yield Absent" describes a key-oriented codec's problem Ruby does not have (`serde/5fe8e3ed`).
  `7a` implements the behaviour the requirement's conformance clause names — decode an object
  omitting the field, assert Absent and not Null — and emulates none of the machinery.
- **`SERDE-26`'s antecedent is false by construction and the requirement is satisfied more strongly
  than §11.18's fallback route.** See `P7-4`. The adapter's public constructor takes options, never a
  `::JSON::Coder`, so "built around a caller-supplied codec instance" never happens; and each
  instance owns a private `::JSON::Coder` built from its own frozen options `Hash`, so no engine is
  shared and no reconfiguration of one reaches another. §11.18's documented-fallback clause is **not
  invoked**, which is a change from what design §7.3 predicted and is why it carries a ledger row.
- **`SERDE-27`'s no-materialization clause is deviated, not satisfied.** `P7-1`, argued in full under
  `R1`. The row cites `P7-1`, names what the handler *does* satisfy (it hands `#load` the source and
  copies nothing) and names the observable behaviour above `MAX_MATERIALIZED_BYTES`.
- **`SERDE-29`'s cache clause has no subject in this port.** "Any per-type sub-serializer caches
  SHOULD use non-blocking, publication-safe updates rather than coarse locks." There is **no per-type
  cache at all**: a witness is supplied by value at every `#load` call, so nothing is memoized by
  type. The sharing half of the requirement is real and implemented — a `Codec` is frozen after
  construction and its `::JSON::Coder` is thread-safe (verified fact 9) — and the row states the
  cache clause's vacuity with `XCUT-12` named as its shape, because a phase-9 audit reading
  `XCUT-12` will look for a cache here and must find the reason there is none.

### What `7a` additionally ships, without owning a new ID

- **`add_dependency "json", ">= 2.19.9"`** in `gems/dexpace-serde-json/dexpace-serde-json.gemspec` —
  `NFR-2`'s third-party half for that gem, and **the only place in the repository that floor may be
  stated** (`CLAUDE.md`'s hard rule; design §3.4; `serde/d15ade64`). The plan lands this line
  **before** the first `require "json"` in that gem's `lib/`, because phase 0's adapter-extended
  require-allowlist audit permits "the single third-party gem that adapter's gemspec declares"
  (`…phase0…-design.md:471-475`) and the reverse order is a red build, not a style preference.
- **A require-time floor assertion** in `gems/dexpace-serde-json/lib/dexpace/serde/json.rb` —
  `P7-7`. `bundler-audit` enforces the floor for a *bundled* consumer over time; it does not run in a
  consumer's process, and an unbundled `require "dexpace/serde/json"` on Ruby 3.4.10 activates the
  interpreter's default `json` **2.9.1**, which lacks `JSON::Coder` entirely (verified fact 8).
- **`Dexpace::Body.serialized(value, serde:)`** — `SERDE-2`'s "that media type MUST be used as the
  default Content-Type when a request body is created from a value plus a Serde", which phase 3b
  deliberately did not build: its eight factories are `.bytes`, `.string`, `.file`, `.stream`,
  `.chunked`, `.form`, `.multipart` and `.buffer`, and it "builds no witness, no codec and no
  status-aware handler" (`…phase3b…-design.md:557`). Adding a ninth factory **widens**, which
  `NFR-4`'s "disappears or narrows" lock permits.
- **The `_Codec` RBS interface's body**, which phase 2 declared it would write and left unwritten
  (`docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md:4613-4614` says the file "carries
  `interface _Codec` with the six methods" and gives no types). `7a` is the first code that has to
  agree with it, and `#media_type`'s return type is the one that matters — see `R3`'s
  `Body.serialized` paragraph and the register finding below.

### Canonical text quoted because a decision below turns on it

> **SERDE-3** (MUST) — When encoding into, or decoding from, a caller-supplied stream, the
> serializer/deserializer MUST read/write the payload fully (to EOF on the read side) but MUST NOT
> close or take ownership of the caller's stream. The encode-into-buffer profile likewise touches
> only the target region and never assumes ownership. *Conformance: wrap a caller stream in a
> close-counting tracker; serialize/deserialize through it; assert bytes transferred and close count
> 0, **even when the codec's own auto-close feature is enabled**.*

> **SERDE-4** (MUST) — The encode-into-buffer profile MUST return the number of bytes written, MUST
> honor a start offset, and MUST throw a range/overflow error (**distinct from the serde exception
> type and not chaining one**) when the offset is out of range or the payload does not fit. Bytes
> before the offset MUST be left untouched.

> **SERDE-12** (MUST) — A genuine stream I/O error raised while reading/writing a caller-owned stream
> MUST propagate unwrapped as an I/O error and MUST NOT be re-wrapped as a serde exception. Only
> malformed-input / shape-mismatch / unencodable-value failures are wrapped.

> **SERDE-19** (MUST) — The default codec configuration MUST wire the tri-state PATCH semantics. An
> adapter building a serde around a caller-supplied codec MUST register that wiring by default and
> MAY allow opting out only for a caller that already installed equivalent wiring. Absent this
> wiring, Absent and Null become indistinguishable on the wire.

> **SERDE-27** (MUST) — A response-decoding handler MUST stream the response body directly through
> the deserializer into the target value (**without first materializing the whole body**), MUST
> consume and close the response on every path, MUST surface a missing body (e.g. 204) as a serde
> exception naming the target type, and MUST surface a codec/parse failure as a serde exception
> chaining the original while letting a genuine mid-stream I/O error propagate unwrapped.

> **SERDE-28** (MUST) — A status-aware handler MUST decode the body only on a 2xx status. On 4xx/5xx
> it MUST throw the mapped HTTP-error exception carrying a bounded, buffered in-memory copy of the
> error body (so the error body is readable after the live response closes) instead of decoding the
> error payload as the success type. On any other non-2xx status (1xx, or an unfollowed 3xx such as
> 304) it MUST close the response and raise a serde exception whose message leads with the status
> code and preserves conditional/redirect context (ETag / Location).

### Out of scope, explicitly

| Excluded | Owning phase |
|---|---|
| `SEAM-19`–`SEAM-21`, `SEAM-23` — the codec seam's six methods, `.conforms?`/`.missing_methods`, the five registry entry points, and the `Error`/`SerializationError`/`DeserializationError` hierarchy | 2, built. `7a` implements against them, adds no seventh seam method, removes none, and adds no second error root |
| `SEAM-22` — the reflective generic type capture | 2, marked 🚫 with the reason attached; the surviving clause (`#load` takes an explicit witness, no witness-less overload) is phase 2's Task 12. The **witness protocol** §10.14 substitutes is `7a`'s work, but the ID's row is phase 2's and does not move |
| `SEAM-26`, `SEAM-27` — the operation-input projection seam | 2. `SERDE-2`'s Content-Type default is `7a`'s and is a **body-factory** concern, not an operation-projection one |
| `HTTP-44`, `HTTP-45` — the lazy typed-response wrapper, its `@state` memo and its mutex | 3b, built as `Dexpace::TypedResponse` over `Dexpace::_ResponseHandler`. `7a` supplies two handlers **into** it and writes no second memo, no second `@state` machine and no second lock |
| `HTTP-41`, `HTTP-42`, `BODY-14`, `BODY-16` — the response body, `#source`, the charset decode, the close-in-`ensure` readers | 3b, built. `OI-10`'s resolution put `#source` and a default no-op `#close` on `Dexpace::Body` |
| `BODY-30`, `HTTP-52` — the bounded buffered error-body copy | 3b (`Body.buffer_bounded`, `MAX_BUFFERED_ERROR_BODY_BYTES`) and 4b (`Recovery.buffer_error_body`, the **one** buffering call site). `SERDE-28`'s "bounded, buffered in-memory copy" consumes them and adds no second |
| `IO-9`, `BODY-32` — `MAX_MATERIALIZED_BYTES` | 3a, one ceiling, cited and never re-derived. `7a`'s `#load` drain is guarded by it and lowers nothing |
| `IO-6`, `BODY-8` — the two ownership rules | 3a and 3b. The **third** rule — a codec closes nothing — is `7a`'s and phase 3 declined to touch it (`message-bodies/a7afc6ee`) |
| `RECOV-1`–`RECOV-16`, `XCUT-9` — `Outcome`, the chains, `ProtocolError`, `Recovery.buffer_error_body`, `Dexpace.each_cause` | 4b, built. `7a` calls three of them and builds none |
| `PIPE-1`–`PIPE-40` | 4c, built. `7a` installs no step and writes no second installation path |
| `CFG-1`–`CFG-38`, `OBS-1`–`OBS-40` | 5. **No `SERDE` requirement names a configuration key, an instrumentation event, a log level or a clock**, and `7a` adds none |
| `CFG-29`–`CFG-31` — RFC 1123 date formatting and parsing (`Dexpace::HTTPDate`) | 5a. `SERDE-24` is ISO-8601 and a **different grammar**; `7a` does not consume `HTTPDate` and `HTTPDate` does not consume `Instant` |
| `SSE-1`–`SSE-41` | `7b`. `SSE-37` forbids core's SSE layer from holding a serialization dependency, and `7a` reaches into `lib/dexpace/sse/**` not at all |
| `PAGE-1`–`PAGE-36` | `7c`. §12's engine is serde-agnostic; `7a` ships no pagination-flavoured witness and `dexpace-serde-json` receives no pagination code |
| `TRANSPORT-18` — the re-subscribable body producer | 8, and near-vacuous for `Net::HTTP` (§11.18, the same item that names `SERDE-26`) |
| `HTTP-48` — the ETag helper | Still deferred (`DEF-2`). `SERDE-28`'s "preserves conditional/redirect context (e.g. ETag / Location)" is satisfied by **copying the raw header value**, never by parsing it — the charter's own argument, honoured here |
| `XCUT-12`, `XCUT-15` | 9 dispositions. `7a` satisfies each by construction: `XCUT-12` through `SERDE-29`'s absent cache and frozen codec, `XCUT-15` through `Data`-frozen values and `Model.own`'d collections |
| `NFR-1`–`NFR-4`, `NFR-11` | 0 built the machinery, 9 dispositions it. `7a` **spends** `dexpace-serde-json`'s `NFR-2` budget and asserts nothing about the gate |
| `dexpace-conformance` | 8 owns the gem, 9 adds the suites. `7a` writes its assertions in `gems/dexpace-serde-json/test/` — charter boundary 8 |

---

## Prerequisites, and the independence this sub-phase must state

**`7a` depends on `7b` and `7c` for nothing, and neither depends on `7a`.** The charter's finding —
every phase-7 boundary is a convenience — is stated here in `7a`'s own words rather than inherited,
because the roadmap's phase-7 bullet requires exactly that of each sub-phase design:

- **`7a` → `7b` is forbidden, not merely absent.** `SSE-37` is a MUST that core parsing and streaming
  hold **no serialization dependency**, mechanised by §9.2's require audit (`sse-streaming/ebb489ba`).
  Nothing `7a` builds may be reached from `lib/dexpace/sse/**`, and `7a` neither exports anything for
  `7b` nor asks anything of it. `SSE-33`–`SSE-36`'s typed adapter takes a **caller-supplied mapper**
  and receives `(event-name, joined-data)`; it never meets a witness.
- **`7a` → `7c` is absent.** §12's chapter intro fixes the pagination engine as serde-agnostic, and
  `PAGE-5` fixes a strategy as reading the response itself. A `7c` strategy may accept an object
  conforming to **phase 2's** `Dexpace::Serde` duck type — the seam is phase 2's, shipped; the codec
  is `7a`'s — and that distinction is the whole of why the edge is absent.
- **`7b` → `7a` and `7c` → `7a` are absent.** Nothing in
  `docs/product-spec/14-serialization-serde.md` mentions an event stream or a page; `SERDE-27`'s
  handler reads a `Dexpace::Response` and nothing about it is page-shaped or event-shaped.
- **`7a` owns no side of the charter's one convergence point.** The `SSE-37` require-and-constant
  audit, extended over the pagination layer (charter boundary 5, `R11`), is written by whichever of
  `7b` and `7c` lands first. **`7a` writes no part of it and adds no path to it**, which is stated
  here so neither sibling design assumes `7a` did.

**A `7a` plan whose first task waits on anything from `7b` or `7c` has re-imposed a chain that does
not exist.** The recommended order `7a → 7b → 7c` is the charter's convenience and this document does
not re-argue it; if the order changes, nothing in `7a`'s plan needs to.

Every surface below was verified against the named phase's design on 2026-09-10. Nothing is
implemented yet in this repository — these are design commitments, and `7a` inherits them as such.

### From phase 0 — the seventeen blocking gates

Six bite here, and one of them bites `7a` first in the whole roadmap.

- **`gates:require_allowlist`, with `json` on the *denylist* by name**, reason attached: "`SEAM-2`:
  the wire codec is a seam. The codec lives in `dexpace-serde-json` and the `>= 2.19.9` floor lives
  in that gemspec and nowhere else" (`…phase0…-design.md:459`). Core's allowlist is `monitor`, `uri`,
  `stringio`, `strscan`, `time`, `date`, `securerandom`, `digest`, `openssl`, `forwardable`, `set`,
  `singleton`. **`7a`'s core files require nothing outside it** — `time` for `Dexpace::Serde::Instant`
  is already on it and is a default gem that stays a default gem across 3.2–4.0 (`Time#iso8601` is
  `time`'s, not `Time`'s built-in).
- **The adapter extension to the same audit** (`:471-475`): every `require` in an adapter must be
  allowlisted, or under `dexpace/`, or **the single third-party gem that adapter's gemspec declares**.
  This is what makes `7a`'s gemspec-line-before-first-require ordering a build constraint rather than
  a preference.
- **`gates:gemspec_audit`**, enforcing `NFR-2`'s core-plus-at-most-one budget with a
  `two_third_party` negative fixture. **`7a` is the first sub-phase in the roadmap to spend an
  adapter's third-party half**, and this gate has never seen a gem with a third-party dependency in
  it. Retiring that risk first is the charter's own reason for recommending `7a` first.
- **The clean-bundle isolation run**, on every Ruby in the matrix. It currently targets core;
  `7a`'s plan runs the same shape by hand against `dexpace-serde-json` (a scratch `Gemfile` holding
  only that gem by path) so the `>= 2.19.9` resolution is proven rather than assumed — and this is
  the run that distinguishes 2.19.9 from the interpreter's default 2.9.1.
- **`ruby -w` with warnings fatal**, mechanised two ways: `Warning.warn` overridden in the shared
  test case **to raise**, plus a stderr scan for `warning:` in a subprocess with `-w -W:deprecated`
  appended to `RUBYOPT` (`…phase0…-design.md:542-556`). Verified fact 5 is why this bites `7a`: Ruby's
  `IO::Buffer` emits an experimental warning through `Warning.warn` on first construction, so a test
  that constructs one **fails the build**. `P7-5`.
- **The six custom cops** — `Dexpace/SpdxHeader`, `NoTimeParse`, `NoUriDefaultParser`,
  `NoLocaleCaseFold`, `NoThreadInterrupt` (`:523`) and phase 2's `Dexpace/QualifiedCoreConstant`
  (`…phase2…-design.md:1295`). The sixth "rejects a bare `Thread`, `Queue`, `Mutex`, `SizedQueue`,
  `ConditionVariable` or `JSON` inside `lib/dexpace/async/**` and `lib/dexpace/serde/**` and requires
  the `::`-qualified form". **`Dexpace::Serde::JSON` is the exact constant that cop exists for, and
  `7a` is the first code it bites.**
- **The gem skeleton itself**: `gems/dexpace-serde-json` at `0.0.0` with a real gemspec declaring
  `dexpace-core` **and nothing else**, `lib/dexpace/serde/json.rb` (carrying phase 0's shadowing
  caution in a comment), `lib/dexpace/serde/json/version.rb` defining
  `Dexpace::Serde::JSON::VERSION`, `sig/`, `test/`, a shadowing-regression test asserting
  `::JSON.name == "JSON"` and `Dexpace::Serde::JSON.name == "Dexpace::Serde::JSON"`, and a Steep
  target with **two signature roots** (`check "gems/dexpace-serde-json/lib"`, `signature
  "gems/dexpace-serde-json/sig", "gems/dexpace-core/sig"`).

### From phase 1

`Dexpace::Model` — `Model.required!(name, value)` raising `Dexpace::InvalidArgumentError` with the
message `"<name> is required"` (`SEAM-29`), `#with` overriding `Data#with` and routing through the
type's own `.build`, `Model.own(collection)` = `Ractor.make_shareable(collection, copy: true)`, and
`Model.frozen_string(value)`. `Dexpace::MediaType` — `Data.define(:type, :subtype, :parameters)`,
`.parse(text)`, `#render`, `#charset` returning `nil` for absent or unknown, `#matches?`.
`Dexpace::Status#error?` (400..599, `HTTP-11`) and `#code`. `Dexpace::InvalidArgumentError <
::ArgumentError`, including `Dexpace::Error`. `Dexpace::Error` is a **module**.

### From phase 2

`Dexpace::Serde` — the six-method codec duck type, read as code rather than as prose:

```
CONTRACT = %i[media_type dump_string dump_bytes dump_to dump_into load].freeze   # private_constant
.conforms?(object)        # CONTRACT.all? { |name| object.respond_to?(name) }
.missing_methods(object)  # CONTRACT.reject { … }
.register(key, factory, core:) / .install(codec) / .resolve / .registered_keys / .swap(codec, &block)
```

`#dump(value, sink)` is §3.4's shorthand for `#dump_to`; an adapter may define it and it is
**deliberately not in `CONTRACT`**. `Dexpace::Serde::Error < ::StandardError` including
`Dexpace::Error`, with `SerializationError` and `DeserializationError` under it — a **class** root,
inverting phase 1's module root deliberately (`P2-2`), and **not** in Ruby's `IOError` family, which
phase 2 asserts by test. `FakeCodec` and `IncompleteCodec` in
`gems/dexpace-core/test/support/fake_codec.rb`. `Dexpace::SeamError`. `Dexpace::Closeable`.
`Dexpace::Hooks` is a `private_constant` with no `sig/` mirror — `7a` cannot cite it as an interface
surface.

**Phase 2 left `interface _Codec`'s body unwritten.** Its plan says `sig/dexpace/serde.rbs` "carries
`interface _Codec` with the six methods and the module's class methods" and gives no types
(`…phase2…:4613-4614`). `7a` writes them, and `#media_type`'s return type is the one that has a
consequence — see `R3`.

### From phase 3a

`Dexpace::IO::BufferedSource` with `#read_into`, `#read`, `#readpartial`, `#getbyte`, `#each`,
`#peek`, `#slice`, `#read_exactly`, `#read_string(encoding, count: nil)`, **`#read_utf8(count:
nil)`** and `#read_line_utf8`. `.wrapping(io)` **takes ownership**; `.of_bytes(string)` copies;
`.over(body)` **takes none**. `Dexpace::IO::Buffer` — core's own FIFO, not Ruby's `IO::Buffer`, and
it addresses no offset. `Dexpace::IO::BufferedSink`, `#write(*strings) -> Integer`.
`Dexpace::IO::MAX_MATERIALIZED_BYTES` (64 MiB) with `P3-4`'s widening: it guards **every** operation
producing one contiguous `String`, including `#read_utf8` and `#read_string`, checked *incrementally
as the result grows*. `Dexpace::StreamError < ::IOError` and `Dexpace::EndOfStreamError < ::EOFError`,
both including `Dexpace::Error`. `Dexpace::ClosedError`.

**The one contract clause `7a` acts on and 3a states plainly:** "`#read_utf8` and
`#read_string(encoding)` **retag**; they apply no replacement policy — that is `HTTP-42`'s, at 3b's
single decode boundary" (`…phase3a…-design.md:658`, `:939`). Verified fact 7 is what follows from it.

3a's precedent for a hostile destination is also inherited rather than re-decided: a "frozen or
non-BINARY destination" raises `Dexpace::InvalidArgumentError`, not a stream error
(`…phase3a…-design.md:826`, `IO-3`/`IO-21`). `#dump_into` follows it exactly.

### From phase 3b

`Dexpace::Body` — the module, with `#write_to(sink) -> Integer` the one required hook and defaults
for `#media_type` (`nil`), `#content_length` (`-1` when unknown, **never `nil`**), `#replayable?`
(`false`), `#to_replayable`, `#each`, **`#source`** (default **raises** `Dexpace::StreamError` naming
the class) and **`#close`** (default **no-op**). The include order is `include Dexpace::Body` then
`include Dexpace::Closeable` wherever a body owns something (`OI-10`, `P3-23`). Eight factories.
`Body.buffer_bounded(body, cap:)` and `Body::MAX_BUFFERED_ERROR_BODY_BYTES` (1 MiB, **3b's**
constant). `Dexpace::ResponseBody` — `#source` returns **the same underlying handle every call**,
`#close` releases the transport resource through `Closeable`'s latch. `Dexpace::BufferBody` —
`#source` returns a **fresh `#peek` view per call**, `#close` is the module's no-op, so `BODY-30`'s
"decode it, then snapshot it" both work after the live response is gone. `Response#close`,
`#body_string`, `#body_bytes`. `sig/` narrows `Request#body` and `Response#body` to
`Dexpace::Body?` (`DEF-26`, picked up).

**`Dexpace::TypedResponse.new(response:, handler:)`** over **`Dexpace::_ResponseHandler` — `def
call: (Dexpace::Response) -> untyped`** — validated by `respond_to?(:call)` and never by a nominal
test, with `HTTP-44`'s four-state `@state` memo (`:unstarted`, `:running`, `:done`, `:failed`), a
memoized failure re-raised as **the same object**, and `HTTP-45`'s `Thread::Mutex` held **only**
across the flip. Its five raw forwards — `#status`, `#headers`, `#protocol`, `#reason`, `#request` —
touch neither `#value` nor the body. **3b builds no witness, no codec and no status-aware handler**
and says so. `7a` supplies two handlers into this and replaces nothing.

### From phase 4b

`Dexpace::ProtocolError < ::StandardError`, including `Dexpace::Error`, carrying `#response` and
`#status`, **one class with no per-status subclass tree** (`P4-20`); `ProtocolError.for(response)`
raising `Dexpace::InvalidArgumentError` for a non-error status and `.for_or_nil(response)` returning
`nil` (`XCUT-8`'s two forms). `Dexpace::Recovery.buffer_error_body(response) -> Response` — returns
the response unchanged when `status.error?` is false **or the body is `nil`**, otherwise calls
`Body.buffer_bounded(body, cap: Body::MAX_BUFFERED_ERROR_BODY_BYTES)`, and is the **one** buffering
call site (4b's forward table: "phase 6 adds no second"; the same holds for phase 7).
`Dexpace::Recovery::ErrorMappingStep.build(factory: Dexpace::ProtocolError.method(:for))` — the
precedent `7a`'s `StatusAwareHandler` copies for its own `factory:` keyword.
`Dexpace::Suppressible`, `Dexpace.attach_suppressed` (with the self-suppression skip and the stated
**frozen-primary** no-op), `Dexpace.suppressed`, `Dexpace.each_cause` (cycle-safe by reference
identity, **block form**), `Dexpace.close_quietly(resource, onto:)`, `Dexpace::Outcome` with
`Success`/`Failure`. The re-raise spelling for an error core is **carrying** is
`raise error, cause: nil` (`pipeline/f02559b9`).

### From phase 4c

**Nothing.** `7a` installs no pipeline step, forks no cursor, and touches no 4c file. `PIPE-26`'s "a
built pipeline is a transport" is `7c`'s row, not `7a`'s.

### From phase 5

**Nothing is required by any of the 30 IDs**, and that is worth stating rather than leaving implicit:
no `SERDE` requirement names a configuration key, an instrumentation event, a log level or a clock.
One adjacency exists and is not a dependency — `SERDE-24`'s ISO-8601 grammar is **not**
`Dexpace::HTTPDate`'s RFC 1123 grammar, and `7a` does not consume `HTTPDate`.

### From phase 6

**Nothing, in either direction.** Phase 6 cites no phase-7 ID and phase 7 cites none of phase 6's,
verified by the charter and re-checked here.

---

## The verified Ruby facts this sub-phase is built on

**One interpreter, and this document says so before it says anything else.** As with phases 3, 4, 5
and 6, only **Ruby 3.4.10** (`ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]`) is
installed on the authoring machine. **The 3.2 and 4.0 columns have not been run for anything below.**
`7a`'s plan installs both and re-runs every fact before any implementation task begins.

Unlike every predecessor, this sub-phase also has a **second** axis to pin: the `json` version. Two
were exercised — the interpreter's default gem **2.9.1**, and **2.19.9**, the exact floor the gemspec
will declare, installed into a scratch `GEM_HOME` for this document. Where a fact differs between
them, both are given.

1. **`JSON.parse` cannot be handed a stream, on either version.**
   `JSON.parse(StringIO.new(%q({"a":1})))` raises `TypeError: no implicit conversion of StringIO into
   String` on 2.9.1 **and on 2.19.9**. `JSON.load` accepts an IO and returns `{"a" => 1}` on both, and
   `JSON.load` is the method design §3.4 bans by lint rule (`serde/5e420c20`). This is `R1`, and
   confirming it against the floor rather than the default gem is what the charter could not do.
2. **json 2.19.9 offers nothing pull-shaped.** `JSON.singleton_methods` on 2.19.9 is
   `[:[], :_dump_default_options, :_load_default_options, :_unsafe_load_default_options, :create_id,
   :create_id=, :deprecation_warning, :dump, :dump_default_options, …, :generate, :generator,
   :load, :load_default_options, :load_file, :load_file!, :parse, :parse!, :parser, :pretty_generate,
   :restore, :state, :unparse, :unsafe_load, …]` — no `parse_stream`, no incremental entry point.
   `JSON::Parser.instance_methods(false)` is `[:parse, :source]` on both versions, and
   `JSON::Ext.constants` is `[:Generator, :Parser, :ParserConfig]`. The one loophole is
   **`#to_str`**: `JSON.parse(obj)` succeeds when `obj` responds to `#to_str`, and fails for an object
   answering only `#read` — but `#to_str` returns the whole `String`, so it materialises exactly as
   much as `#read` would. There is no route that does not.
3. **`::JSON.generate` silently stringifies an unserializable value, on both versions.**
   `JSON.generate(Object.new)` returns `"\"#<Object:0x…>\""`. **`strict: true` makes it raise**
   `JSON::GeneratorError: Object not allowed in JSON`, and `JSON::Coder.new(strict: true).dump` does
   the same. `SERDE-9`/`SERDE-10` require an unserializable value to raise the serialization subtype,
   so the silent default is a requirement violation waiting to happen and the adapter passes
   `strict: true`. Two further generator failures are already loud on both versions and need no
   option: `JSON.generate(Float::NAN)` raises `JSON::GeneratorError: NaN not allowed in JSON`, and
   generating a BINARY `String` holding `\xff` raises `JSON::GeneratorError: "\xFF" from ASCII-8BIT
   to UTF-8`.
4. **`JSON::ParserError` is `JSON::JSONError` is `StandardError`, and is nowhere near `IOError`.**
   Ancestors on both versions: `[JSON::ParserError, JSON::JSONError, StandardError, Exception]`;
   `JSON::GeneratorError` sits beside it; `JSON::NestingError < JSON::ParserError`.
   `IOError.ancestors.include?(JSON::JSONError)` is `false`. So `SERDE-12` is satisfied
   **structurally** by `rescue ::JSON::JSONError`: a `Dexpace::StreamError`, which is an `::IOError`,
   cannot be caught by it. `7a` writes no `rescue StandardError` in the codec path, and the row states
   the ancestry as the reason rather than the discipline.
5. **Ruby's `IO::Buffer` emits an experimental warning through `Warning.warn`, at every warning
   level.** `ruby -e 'IO::Buffer.new(4)'` prints `warning: IO::Buffer is experimental and both the
   Ruby and C interface may change in the future!` with no `-w`, with `-w`, and under
   `RUBYOPT=-W:deprecated`; overriding `Warning.warn` to raise catches it, with `category:
   :experimental`. Phase 0's shared test case **overrides `Warning.warn` to raise**, so a test that
   constructs one fails the build. Separately, `IO::Buffer#set_string` raises `ArgumentError`
   ("Specified offset+length is bigger than the buffer size!") where `String#[]=` raises
   `IndexError`, so supporting both would give `SERDE-4`'s range error two classes. `P7-5`.
6. **`JSON.parse` performs no coercion, and a `Hash` distinguishes an absent key from a present null
   directly.** `JSON.parse(%q({"n":"5"}))["n"]` is `"5"`, never `5` — `SERDE-21` satisfied by the
   codec doing nothing. `JSON.parse(%q({"x":null})).key?("x")` is `true` with value `nil`;
   `JSON.parse("{}").key?("x")` is `false` — `SERDE-16` and `SERDE-17` without the field-default
   machinery `SERDE-17` describes (`serde/5fe8e3ed`). And `JSON.parse("null")` returns `nil` rather
   than raising, on both versions, which is what makes `SERDE-20`'s top-level decode implementable.
7. **`::JSON.parse` accepts invalid UTF-8 and returns a UTF-8-tagged `String` that is not valid
   UTF-8.** `JSON.parse(%Q({"a":"\xff"}).b)["a"]` returns a `String` whose `#encoding` is
   `UTF-8`, whose `#bytes` is `[255]`, and whose **`#valid_encoding?` is `false`**. It also accepts a
   BINARY-tagged input holding well-formed UTF-8 and returns correctly-tagged UTF-8 (`"é"`). Combined
   with phase 3a's contract that `#read_utf8` **retags without validating**, the two compose into a
   silent corruption path: a caller receives a `String` that claims UTF-8 and is not one. Note also
   that a *transcode* is the wrong tool here — `"\xc3\xa9".b.encode(::Encoding::UTF_8,
   ::Encoding::BINARY)` raises `Encoding::UndefinedConversionError` for the perfectly valid two-byte
   `é`, because BINARY has no character semantics to convert *from*. The correct recipe for "these
   bytes are UTF-8" is **retag, then validate**, and `P7-6` is where `7a` adds the validation
   `io-and-byte-streams/6eb5155f`'s recipe does not reach.
8. **`JSON::Coder` exists on 2.19.9 and does not exist on 2.9.1.** `JSON.constants.include?(:Coder)`
   is `false` under the interpreter's default gem and `true` under the floor.
   `JSON::Coder.instance_method(:initialize).parameters` is `[[:opt, :options], [:block, :as_json]]`;
   its instance methods are `[:dump, :generate, :load, :load_file, :parse]`. It is **freezable**
   (`c.freeze.dump({"a"=>1})` works) and **thread-safe** — eight threads × 500 dumps each produced
   exactly the eight expected distinct results. That is a real per-instance codec engine, which is
   what `P7-4` and `P7-7` both turn on.
9. **`Time#iso8601(n)` truncates rather than rounds, so the round trip `SERDE-24` requires holds only
   over a stated precision domain.** Three measurements:
   - `Time.utc(2026,9,10,12,0,0).iso8601` is `"2026-09-10T12:00:00Z"` and `Time.iso8601` of that is
     `==` **and `eql?`** the original. Whole seconds round-trip exactly.
   - `Time.new(2026,9,10,12,0,0, "+02:00").iso8601` is `"2026-09-10T12:00:00+02:00"` and reads back
     with `utc_offset` 7200. The offset survives.
   - **`Time.new(2026,9,10,12,0,0.123456, "+02:00").iso8601(6)` is
     `"2026-09-10T12:00:00.123455+02:00"` — one microsecond low — and the round trip is `false`.**
     The `Float` second is stored as the exact rational `8895942329546431/72057594037927936`
     (≈ `0.12345599999…`) and `#iso8601` truncates. `Time.at(Rational(…) + Rational(1,3))` fails the
     same way at `iso8601(9)`. A `Time` built with exact microseconds — `Time.at(0, 123456, :usec)`,
     `subsec` = `1929/15625` — **does** round-trip at `iso8601(6)`.

   `P7-8` is where the domain is stated. `Time.iso8601` also rejects a lax form: `"2026-09-10"` and
   `"2026-09-10 12:00:00"` both raise `ArgumentError`, and so does `"not a time"` and `""`, which is
   the strictness `SERDE-13`/`SERDE-21` want on the decode side.
10. **`Time.iso8601` and `Time#iso8601` are `time`'s, and `Dexpace/NoTimeParse` does not ban them.**
    The cop bans `Time.parse`, `Date.parse` and `DateTime.parse` (phase 0's table). `time` is on
    core's require allowlist and is legitimately `require`d by the adapter.
11. **`raise Klass, "msg", cause: nil` produces an exception with `#cause` `nil` even inside a
    `rescue`.** Verified: raised from within `rescue RuntimeError`, `e.cause` is `nil`; without
    `cause: nil` it is the in-flight `RuntimeError`. That is `SERDE-4`'s "not chaining one" made
    structural rather than dependent on where `#dump_into` happens to be called from, and it is
    `pipeline/f02559b9`'s spelling reused.
12. **`String#[]= ` with an in-range offset and an over-long payload silently GROWS the string.**
    `buf = ("\0"*4).b; buf[2,3] = "abcd".b` leaves a **six**-byte string. An out-of-range offset
    raises `IndexError` ("index 9 out of string", "index -9 out of string"); a frozen target raises
    `FrozenError`. So `SERDE-4`'s "the payload does not fit" case is **not** caught by the primitive
    and `#dump_into` must check the fit explicitly before writing — which is exactly what phase 2's
    `FakeCodec` already does and what `7a`'s real codec must not drop.
13. **A frozen singleton with `#to_s`/`#inspect` overridden is `Ractor.shareable?`.** Verified for
    the `Tristate::ABSENT`/`::NULL` shape: `to_s` and `inspect` both return `"Absent"`, the object is
    frozen, and `Ractor.shareable?` is `true`. `SERDE-30` costs two lines and Ractor-shareability is
    a free side effect that no claim rests on.
14. **`Data.define`-generated instances are frozen and compare by value.** `Pres.new(value: 1) ==
    Pres.new(value: 1)` is `true` and `#frozen?` is `true`, so `Tristate::Present`'s equality falls
    out of the member with nothing written.
15. **`respond_to?` sees a class method.** `class W; def self.dexpace_load(parsed, ctx); end; end;
    W.respond_to?(:dexpace_load)` is `true`, and `Object.new.respond_to?(:dexpace_load)` is `false`.
    That is what makes "a witness is any object responding to `.dexpace_load`" cover both a model
    **class** and a combinator **instance** with one predicate.

Two facts from the charter are inherited rather than re-measured because nothing here turns on them
differently: `Data#with` copies the struct and shares its members (charter fact 3, already discharged
by `data-modeling/83610619`), and the UTF-8 BOM is `[239, 187, 191]` (charter fact 7, `7b`'s).

---

## `R1` — `SERDE-27`'s "without first materializing the whole body"

**Decision: the clause is NOT satisfied, and the gap is numbered `P7-1` rather than argued away.**

The charter left `7a` the choice between two readings and required it to state which it took:

> `7a` decides whether that is `SERDE-27` satisfied (the requirement's object being the handler's
> behaviour) or a deviation to argue (the requirement's *purpose* being bounded memory), states
> which, and if it is a deviation numbers it `P7-<n>` and names the obligation it puts on
> `dexpace-serde-oj` and on any future adapter whose library does have a pull parser.

**The handler-behaviour reading is available and is rejected, for a stated reason.** It is true that
`SERDE-27`'s subject is "a response-decoding handler", and true that `Dexpace::Serde::DecodingHandler`
materialises nothing: it reads `response.body.source`, hands that `BufferedSource` straight to
`serde.load(source, witness)`, and never allocates a `String` of its own. On that reading the clause
is satisfied and the memory cost is the *adapter's*, which the requirement does not name.

It is rejected because **the requirement's parenthesis is a memory guarantee, not an architectural
one**, and reading it as architectural would make it unfalsifiable: any handler that delegates
satisfies it, including one delegating to a codec that reads the body twice. The clause exists to
bound peak memory on a large response, and on stdlib `json` — at the floor, verified fact 1 — that
bound is not available at any price short of writing a JSON parser, which is the one thing an adapter
whose entire purpose is to delegate to `json` must not do. Design §3.4 puts the codec in its own gem
precisely so the `>= 2.19.9` floor can be stated; re-implementing the parser inside it would make the
floor meaningless.

**What the port actually does, stated so it is checkable:**

1. `DecodingHandler#call(response)` reads `response.body` and, when it is non-`nil`, calls
   `serde.load(response.body.source, witness)`. No `String` is built in the handler, `#body_string` is
   never called, and the response is closed in an `ensure` on every path.
2. `Dexpace::Serde::JSON::Codec#load(source, witness)` drains `source` to EOF with
   `source.read_utf8` — **guarded incrementally by `Dexpace::IO::MAX_MATERIALIZED_BYTES`**, 3a's
   64 MiB ceiling under `P3-4`'s widening — validates the result (`P7-6`), parses it with
   `::JSON.parse`, and calls `witness.dexpace_load(parsed, ctx)`.
3. **The observable behaviour above the ceiling**, which the charter requires this document to state:
   a response body exceeding 64 MiB raises **`Dexpace::StreamError`**, 3a's, which is an `::IOError`
   and therefore **not** caught by the codec's `rescue ::JSON::JSONError` (verified fact 4). It
   propagates unwrapped past the codec, past the handler's `ensure`-close, and reaches the caller as a
   stream error — which is `SERDE-12` satisfied structurally on exactly the path where a reader would
   most expect a serde error. A caller wanting a larger body must stream it themselves through
   `Response#body.source` rather than through a typed handler; that is documented at the handler, not
   discovered.
4. **`7a` neither lowers 3a's ceiling nor introduces a second materialisation constant**, per charter
   boundary 16.

**The obligation this puts on future adapters, named as the charter requires.** The seam's shape is
what keeps the deviation adapter-local and repairable: `#load(source, witness)` **already takes the
source**, so an adapter whose library has a pull parser satisfies `SERDE-27`'s parenthesis outright
with **no change to core, to the handler, or to the seam** — it simply does not drain. Two named
targets inherit the obligation:

- **`dexpace-serde-oj` (`DEF-16`)** — `oj` has a genuine streaming API. The row's pick-up condition
  ("when JSON throughput is identified as a bottleneck the stdlib `json` gem cannot meet") is
  unchanged by this, but `7a` adds a second reason the row exists, and a finding below proposes
  saying so in the register rather than leaving it to be rediscovered.
- **Any adapter phase 8 or later ships whose library has a pull parser.** The obligation is recorded
  in `docs/first-release.md` as a finding below, because it is the kind of gap that is invisible until
  someone streams a 200 MB response through a typed handler and meets a `Dexpace::StreamError`.

**Two alternatives were considered and rejected.**

- **Route `#load` through `JSON.load`, which does accept an IO.** Rejected outright: design §3.4 bans
  it by lint rule, `serde/5e420c20` gives the reason (`create_additions`, CVE-2020-10663, defaulted
  off only from json 2.7.0), and phase 2's `Dexpace/QualifiedCoreConstant` plus phase 0's cop set
  would both have to be weakened to allow it. A memory bound bought with an arbitrary-object
  instantiation hazard is not a bound worth having.
- **Hand `::JSON.parse` a `#to_str`-answering lazy proxy over the source.** Verified fact 2 shows
  this *works* — `JSON.parse` calls `#to_str` on a non-`String` — and it buys nothing, because
  `#to_str` must return the whole `String`. It would produce a deviation that looks satisfied. Named
  and rejected so a later reader who discovers the `#to_str` loophole does not mistake it for the fix.

`P7-1` records all of this.

---

## `R2` — the witness protocol's public surface, and what `ctx` is

The charter's `R2` has two halves. Both are settled here.

### What `ctx` is

**`ctx` is `Dexpace::Serde::DecodeContext`, a new core type this sub-phase defines, and it is
emphatically not phase 4a's `Dexpace::Context`.**

The problem, stated exactly: design §7.3 writes "**A witness is any object responding to
`.dexpace_load(parsed, ctx)`**" (`07-pagination-sse-and-serialization.md:112`) and the token `ctx`
occurs **nowhere else in the design tree for this purpose** — a repository-wide grep finds it in
§5.1's `delete_if` example and in §8.1's instrumentation-listener signatures, both unrelated. Nothing
defines it. A `7a` that shipped `.dexpace_load(parsed, ctx)` without deciding what `ctx` is would fix
a public signature (`NFR-4` locks it the moment it ships) around an undefined argument.

**Phase 4a's `Dexpace::Context` is the wrong answer, and ruling it out is half the decision.** 4a
ships `Dexpace::Context` as a module included by three flavours — `DispatchContext`,
`RequestContext`, `ExchangeContext` — carrying the execution-scoped store, and `ctx.is_a?(Dexpace::Context)`
is true for all three (`…phase4a…-design.md:882-905`). Passing one to a witness would be wrong three
ways: a decode happens with no pipeline (`serde.load(StringIO.new(json), Pet)` is a legitimate call
and there is no execution context to hand it); it would couple the codec seam to the pipeline layer,
which `SEAM-2` and `NFR-11` both push against; and it would make every hand-written witness's
signature name a type it has no use for.

**What `ctx` is for, derived from the requirements rather than invented.** Three `SERDE` MUSTs put a
job on the decode side that a bare `parsed` value cannot do alone:

- `SERDE-13` — "fail with a deserialization exception **naming the target type**".
- `SERDE-21` — nine named cross-shape coercions "MUST surface as a deserialization failure".
- `SERDE-22` — the strict policy "MUST still permit representation-preserving conversions",
  specifically integer→float widening and empty-string→string.

Design §7.3 assigns all three to the witness: "the strictness burden moves into the witness, where
each field asserts its expected class and raises a `DeserializationError` naming the target type on
mismatch" (`serde/b5e5efc8`). **That is a per-field discipline unless something makes it a shared
helper**, and this repository already knows what happens when a uniform failure has no single
implementation — `SEAM-29` exists because of it, and phase 1's `Model.required!` is the answer it
took. `DecodeContext` is `Model.required!` for the decode side.

```
Dexpace::Serde::DecodeContext          # Data.define(:path), include Dexpace::Model
  .root                                -> DecodeContext         # frozen, path []
  #path                                -> Array[String|Integer] # frozen, JSON-Pointer-ish segments
  #at(segment)                         -> DecodeContext         # a child with one segment appended
  #object!(value, key: nil)            -> Hash                  # SERDE-21
  #array!(value, key: nil)             -> Array
  #string!(value, key: nil)            -> String                # rejects 5, true, nil
  #integer!(value, key: nil)           -> Integer               # rejects "5", 1.5, true
  #float!(value, key: nil)             -> Float                 # SERDE-22: WIDENS an Integer
  #boolean!(value, key: nil)           -> bool                  # rejects "true", 1
  #present!(value, target, key: nil)   -> untyped               # SERDE-13: rejects nil, names target
  #error!(expected:, actual:, key: nil) -> void                 # raises; the ONE raise site
```

Every `!` method raises `Dexpace::Serde::DeserializationError` through `#error!`, with one message
form — `"expected <target> at <path>, got <actual class>"` — which is the `SEAM-29` shape applied to a
second family of failures. `key:` is a convenience that appends one segment for the message only, so
`ctx.string!(h["name"], key: "name")` reads naturally without a separate `#at` call; `#at` is what a
combinator uses to descend.

A worked witness, which is also the shape the YARD block shows:

```ruby
class Pet
  def self.dexpace_load(parsed, ctx)
    h = ctx.object!(parsed)
    new(id:   ctx.integer!(h["id"],  key: "id"),
        name: ctx.string!(h["name"], key: "name"),
        tags: Dexpace::Serde::List.of(String).dexpace_load(h["tags"], ctx.at("tags")))
  end

  def dexpace_dump = { "id" => @id, "name" => @name, "tags" => @tags }
end
```

**`SERDE-23`'s tolerant decode falls out of this and is not a separate mechanism**: the witness reads
the keys it declares and never enumerates `h`, so an unknown field is ignored with nothing written
(`serde/0610f93a`). Strictness is opt-in per witness — a witness that wants it calls
`ctx.error!` on `h.keys - DECLARED` itself, and core ships no flag for it, because a flag would have
to live somewhere and `SERDE-23` is a SHOULD the port takes as the default.

**Encoding takes no context, and the asymmetry is the design's own argument turned into a
signature.** §7.3: "Ruby erases nothing — every object carries its class" (so encode needs no
witness) "but Ruby also *reifies* nothing about a container" (so decode does). Phase 2's shipped
`CONTRACT` says the same thing mechanically: **only `#load` takes a witness**; all four `#dump_*`
methods take a value alone. So `#dexpace_dump` stays §7.3's zero-argument instance method and there
is no `DumpContext`. Anyone tempted to add one later should read this paragraph first.

### The witness protocol's public surface, and how much of it `NFR-4` locks

**Everything below is public API the moment it ships** — a `Dexpace::` constant with a YARD block and
an RBS signature — and `NFR-4` locks each name and signature against the previous release tag. There
is no release tag: every gem is at `0.0.0` and nothing is published, so the lock is free to establish
now and expensive to change later, which is the whole reason `R2` is a design decision rather than an
implementation detail. `api-design/b0e18938`'s minimal-surface rule is applied by asking of each
member "would a hand-written witness or a generated SDK call this?", and anything that fails is a
`private_constant`.

```
Dexpace::Serde.witness!(w)             -> w        # raises Dexpace::InvalidArgumentError otherwise
Dexpace::Serde.witness?(w)             -> bool     # the predicate half, for a builder that branches
Dexpace::Serde::WITNESS_METHOD         = :dexpace_load     # frozen Symbol, the one name
Dexpace::Serde::DUMP_METHOD            = :dexpace_dump

Dexpace::Serde::DecodeContext          # above
Dexpace::Serde::List.of(element)       -> a witness for Array[element]
Dexpace::Serde::Map.of(key, value)     -> a witness for Hash[key, value]
Dexpace::Serde::Nullable.of(element)   -> a witness accepting nil
Dexpace::Serde::Tristate.of(element)   -> a witness for the three-state field
Dexpace::Serde::Instant                -> the ISO-8601 Time witness (SERDE-24's decode half)
Dexpace::Serde::Native.of(value, encoders:) -> Hash|Array|String|Integer|Float|bool|nil
Dexpace::Serde::OMIT                   # the frozen sentinel Native drops from a Hash
```

**Four decisions inside that list, each with its reason:**

1. **`.witness!` raises and `.witness?` predicates, and both ship.** `SERDE-8` requires the carrier to
   "fail fast with an actionable message", which is `.witness!`; a generated SDK validating a
   configuration table wants the non-raising form, and `api-design/6ea28c9c`'s precedent (4b shipped
   both `.for` and `.for_or_nil` for exactly this reason) says two forms is the right answer when the
   requirement names one. The validation is `w.respond_to?(:dexpace_load)` — `respond_to?`, never a
   nominal test, matching every seam in this repository and verified to see a class method
   (fact 15).
2. **The combinator set is OPEN, and core ships four.** A witness is any object answering
   `.dexpace_load`, so a caller writes their own combinator — a `Set` witness, a
   discriminated-union witness — with no registration, no subclassing and no core change. `SERDE-6`
   requires parametric targets to be *expressible*, not enumerated, and an open set expresses more
   than a closed one for less code. **Core ships exactly the four §7.3 names** and adds no fifth; the
   YARD block on `Dexpace::Serde` says the set is open and shows the two-line shape of a hand-written
   combinator, so the extension route is documented rather than merely permitted.
3. **`WITNESS_METHOD`/`DUMP_METHOD` are public frozen `Symbol`s.** They cost two lines and they are
   what a code generator emitting witnesses needs in order to not hard-code a string that this
   repository could rename. They are also what `Native`'s walk and `.witness?` both read, so there is
   exactly one place the name `:dexpace_load` is written.
4. **`Native` and `OMIT` are public.** They are the mechanism `SERDE-15`/`SERDE-19`/`SERDE-20` are
   satisfied by (`P7-9`), a second codec adapter must call them to inherit that satisfaction
   (`serde/66ebd950`'s "no second code path in core"), and a witness whose `#dexpace_dump` wants to
   emit an omitted key returns `OMIT`. A `private_constant` `Native` would make
   `dexpace-serde-oj` re-implement tri-state encoding, which is exactly the outcome the seam exists
   to prevent.

**What is deliberately NOT public:** the two singleton classes behind `Tristate::ABSENT` and
`Tristate::NULL` (`private_constant`, following 4a's and phase 2's treatment of an implementation
class a caller can observe but should not name); `JSON::Codec`'s `::JSON::Coder` instance and its
options `Hash` (`NFR-11` — no `::JSON` constant appears in the adapter's public `sig/`); and every
`#dexpace_load` implementation detail on the four combinators beyond the protocol method itself.

---

## `R3` — where the two response handlers live and what they are called

**Decision: two flat classes under `Dexpace::Serde`, both `Dexpace::_ResponseHandler`s, and
`StatusAwareHandler` calls `Dexpace::Recovery.buffer_error_body` legitimately.**

```
Dexpace::Serde::DecodingHandler.build(serde:, witness:)                    # SERDE-27
Dexpace::Serde::StatusAwareHandler.build(serde:, witness:, factory: …)     # SERDE-28
```

Both answer `#call(response) -> untyped`, which is 3b's `_ResponseHandler` exactly, so
`Dexpace::TypedResponse.new(response: r, handler: Dexpace::Serde::DecodingHandler.build(…))` is the
whole of the wiring and `TypedResponse` is **supplied into, never replaced** (charter boundary 7;
`…phase3b…-design.md:535`).

**Placement follows `P1-1` unchanged.** `Dexpace::Serde` is a namespace the design itself wrote, so
these live inside it; everything else stays flat. The names say what each does rather than what it
is (`api-design`'s rule), and neither carries the word "Response" twice.

### `DecodingHandler` — `SERDE-27`'s five clauses, one at a time

```ruby
def call(response)
  body = response.body
  raise missing_body_error if body.nil?

  @serde.load(body.source, @witness)
rescue ::Dexpace::Serde::Error
  raise                                    # already ours; do not re-wrap (SERDE-9's "or a subtype")
ensure
  response.close                           # every path, SERDE-27 clause 2
end
```

- **"stream the response body directly through the deserializer"** — the handler passes
  `body.source`, a `Dexpace::IO::BufferedSource`, and copies nothing. Clause satisfied.
- **"(without first materializing the whole body)"** — `P7-1`. Not satisfied by this adapter; the
  handler's own behaviour is the strongest half of it available.
- **"MUST consume and close the response on every path"** — an `ensure`, unguarded, because
  `#close` is on `Dexpace::Body`'s contract with a no-op default (`P3-23`) and `Response#close` is
  `body&.close` (`HTTP-43`). **This does not conflict with `SERDE-3`.** `SERDE-3` binds the *codec*
  and the object is the *caller's stream*: `#load` does not close the `BufferedSource` it was handed.
  The *handler* is a different object at a different layer and its subject is the **response**, which
  it owns for the duration of the call. Two rules, two subjects, and stating that here is the point
  of the paragraph — a reader who conflates them will delete one of the two behaviours.
- **"MUST surface a missing body (e.g. 204) as a serde exception naming the target type"** — a `nil`
  body **and** a zero-byte body both raise `Dexpace::Serde::DeserializationError` with the target
  named, because a caller cannot distinguish them and `::JSON.parse("")`'s own `ParserError` names
  nothing useful. Stated in the YARD; the requirement's example is 204 and its subject is "a missing
  body", which an empty one is.
- **"MUST surface a codec/parse failure as a serde exception chaining the original"** — the codec
  does this, not the handler, by re-raising **inside** the `rescue` so Ruby sets `#cause`
  automatically (`serde/5821286d`). The handler's own `rescue Dexpace::Serde::Error; raise` exists
  only to make the pass-through deliberate rather than accidental.
- **"while letting a genuine mid-stream I/O error propagate unwrapped"** — verified fact 4: the
  codec's `rescue ::JSON::JSONError` cannot catch a `Dexpace::StreamError`, because that is an
  `::IOError`. Structural, not disciplinary.

### `StatusAwareHandler` — `SERDE-28`'s three branches

```
2xx                              -> @decoding.call(response)          # delegates; ONE decode path
400..599                         -> raise @factory.call(Dexpace::Recovery.buffer_error_body(response))
anything else (1xx, 3xx, 304)    -> response.close; raise DeserializationError, "<code> …"
```

- **The 2xx branch delegates to a `DecodingHandler`** rather than re-implementing it, so `SERDE-27`'s
  five clauses have exactly one implementation and `SERDE-28`'s "decode the body only on a 2xx
  status" is a branch rather than a second decoder.
- **The 4xx/5xx branch uses phase 4b's objects and adds none.** `Recovery.buffer_error_body` is the
  **one** buffering call site (4b's forward table), and it already returns the response unchanged
  when the body is `nil`, so the branch needs no `nil` check of its own. `factory:` defaults to
  `Dexpace::ProtocolError.method(:for)` — the exact spelling and default `ErrorMappingStep` uses
  (`…phase4b…-design.md:1186`) — so a generated SDK substitutes its typed errors here with the same
  keyword it already knows from the recovery chain, and `SERDE-28`'s "the **mapped** HTTP-error
  exception" is `RECOV-15`'s object rather than a second one. `ProtocolError.for` is right rather
  than `.for_or_nil` because this branch has already established `status.error?`.
- **`Recovery.buffer_error_body`'s `ensure` releases the original response**, so the 4xx/5xx branch
  needs no separate close and must not add one — a second close would be a double close of an object
  4b's `Body.buffer_bounded` already released. Stated because "close on every path" invites one.
- **The third branch is where `SERDE-28` is easiest to get half-right.** Its message "leads with the
  status code and preserves conditional/redirect context (ETag / Location)", so the handler copies
  the **raw** `ETag` and `Location` header values into the message and parses neither — the charter's
  own `DEF-2` argument, honoured: running a malformed server `ETag` through `HTTP-48`'s validating
  helper inside an error path would turn a diagnostic into a second failure. The chapter's
  conformance clause also names "**a non-canonical 599**", which is a 5xx and therefore the *second*
  branch — it is called out here because a reader skimming "non-canonical" will file it under the
  third. Both get their own test.

### `Dexpace::Body.serialized(value, serde:)` — `SERDE-2`

Returns a `Dexpace::BytesBody` (3b's, unchanged) whose bytes are `serde.dump_bytes(value)` and whose
media type is the serde's. `BytesBody` is `#replayable?` `true` and knows its exact
`#content_length`, both for free, which is what makes a serialized body retryable without
`#to_replayable` doing anything (`BODY-1`, `HTTP-38`).

**One coercion, and it exposes an unfixed seam type.** `Dexpace::Body#media_type` returns
`Dexpace::MediaType?`; phase 2's `FakeCodec#media_type` returns the `String`
`"application/vnd.dexpace.fake"`; and phase 2 never wrote `interface _Codec`'s body, so nothing fixes
which the seam produces. `7a` settles it in the direction that costs a caller least and a reader
nothing:

- **The `_Codec` interface declares `def media_type: () -> (Dexpace::MediaType | String)`**, and
  `Dexpace::Serde::JSON::Codec#media_type` returns a **`Dexpace::MediaType`**
  (`MediaType.parse("application/json")`, memoized frozen at construction).
- **`Body.serialized` accepts either**, coercing a `String` through `MediaType.parse` and passing a
  `MediaType` through. A `nil` or blank media type raises `Dexpace::InvalidArgumentError` naming the
  codec's class, because `SERDE-2`'s "MUST NOT be defaulted to a format-agnostic constant at the SPI
  level" means there is no fallback to fall back to — phase 2 enforced that at `.conforms?`, and this
  is the same rule at the one call site that consumes the value.
- The unfixed-return-type finding is proposed for `docs/open-items.md` below rather than fixed by
  editing phase 2's document.

---

## `R12` — the `dexpace-serde-json` suite's shape, given that phase 9 owns the reusable form

**Decision: adapter-local Minitest tests over two new doubles, with the *assertions* factored into
one plain module phase 9 can lift, and the target named in `7a`'s checklist.**

Charter boundary 8 keeps phase 7 out of `dexpace-conformance` — phase 8 owns that gem's gemspec,
version and first release, and phase 9 adds the remaining suites. So §3.4's "asserted per adapter in
`dexpace-conformance` rather than left to adapter discipline" and phase 2's "asserted per adapter in
phase 7 and phase 8" are satisfied **in phase 9**, and `7a` writes its assertions in
`gems/dexpace-serde-json/test/`.

What `7a` writes, and the line between the two halves:

| Artifact | Where | Why there |
|---|---|---|
| `CloseCountingSource` / `CloseCountingSink` | `gems/dexpace-serde-json/test/support/` | `SERDE-3`'s conformance clause names a "close-counting tracker" in as many words. They are **new** — phase 2's `FakeCodec` is a codec, not a stream tracker — so `DEF-29`'s "the first consumer outside `dexpace-core`" condition is genuinely not met by reusing anything |
| `SerdeSeamAssertions` — a plain module of assertion **methods** over a `codec` the includer supplies | `gems/dexpace-serde-json/test/support/` | The lift target. Phase 9 moves this file and re-points its `Dexpace::Conformance::Failure` raises; the *content* — `SERDE-3`'s close count, `SERDE-4`'s four-part offset matrix, `SERDE-9`'s type-escape assertions, `SERDE-12`'s I/O-error pass-through — is written once and against the seam, never against `Dexpace::Serde::JSON` by name |
| Everything else — witness protocol, `Tristate`, `Native`, both handlers, `Body.serialized` | `gems/dexpace-core/test/` | Core code, core tests |

**`SerdeSeamAssertions` is a Minitest-flavoured module and does not pre-empt `DEF-22`.** Design §9.3
fixes the conformance gem's shape as "a callable that returns cleanly or raises a
`Dexpace::Conformance::Failure` carrying the expected and actual values, with thin Minitest and RSpec
drivers over it", and building that here would fix an interface before the gem that serves it exists
— which is `DEF-22`'s own argument. `7a` writes ordinary `assert_*` calls and leaves the callable
shape to phase 8; what it buys phase 9 is that the **assertions themselves** are in one file with one
name, rather than spread across a suite and reconstructed from prose. The checklist names the file so
phase 9 inherits a target rather than a search.

**Core's serde tests use `FakeCodec` and never the JSON adapter.** This is a hard constraint, not a
preference: the charter's cross-cutting constraint states "`Dexpace::Serde::JSON` appears in no core
file, in no core `sig/` file (`NFR-11`) and in **no core test**". `DecodingHandler`'s and
`StatusAwareHandler`'s suites therefore drive `FakeCodec` (phase 2's, in
`gems/dexpace-core/test/support/`) with a lambda witness, and a core test that `require`d
`dexpace/serde/json` would also fail phase 0's clean-bundle run, because core's bundle does not
contain that gem. The plan's Task 1 adds the negative assertion — a grep-shaped test over core's
`test/` tree — so the constraint is mechanised rather than remembered.

---

## Module layout

Every file `7a` creates or modifies. `sig/` mirrors `lib/` one file per file and **ships inside each
gem**; `test/` mirrors `lib/` and does not ship. `private_constant`s get neither, per phases 3 and 4.

```
gems/dexpace-core/
  lib/dexpace/serde/decode_context.rb        Dexpace::Serde::DecodeContext
  lib/dexpace/serde/witness.rb               Dexpace::Serde.witness!/.witness?, WITNESS_METHOD, DUMP_METHOD
  lib/dexpace/serde/native.rb                Dexpace::Serde::Native, Dexpace::Serde::OMIT
  lib/dexpace/serde/tristate.rb              Dexpace::Serde::Tristate (+ ABSENT, NULL, Present)
  lib/dexpace/serde/list.rb                  Dexpace::Serde::List
  lib/dexpace/serde/map.rb                   Dexpace::Serde::Map
  lib/dexpace/serde/nullable.rb              Dexpace::Serde::Nullable
  lib/dexpace/serde/instant.rb               Dexpace::Serde::Instant
  lib/dexpace/serde/decoding_handler.rb      Dexpace::Serde::DecodingHandler
  lib/dexpace/serde/status_aware_handler.rb  Dexpace::Serde::StatusAwareHandler
  lib/dexpace/http/body.rb                   MODIFIED: Body.serialized(value, serde:)
  lib/dexpace.rb                             MODIFIED: ten require_relative lines
  sig/dexpace/serde.rbs                      MODIFIED: interface _Codec's body (phase 2 left it empty)
  sig/…                                      ten mirrors + the Body and dexpace.rbs edits

gems/dexpace-serde-json/
  dexpace-serde-json.gemspec                 MODIFIED: add_dependency "json", ">= 2.19.9"
  lib/dexpace/serde/json.rb                  MODIFIED: the floor assertion, the requires, .default, .build
  lib/dexpace/serde/json/codec.rb            Dexpace::Serde::JSON::Codec
  sig/dexpace/serde/json.rbs                 MODIFIED
  sig/dexpace/serde/json/codec.rbs           NEW
  test/support/close_counting_source.rb      the SERDE-3 tracker (source side)
  test/support/close_counting_sink.rb        the SERDE-3 tracker (sink side)
  test/support/serde_seam_assertions.rb      the phase-9 lift target
  test/dexpace/serde/json/codec_test.rb      the adapter's own suite
```

Ten new `lib/` files in core (nine public constants plus the two module functions on `Dexpace::Serde`
itself), one new `lib/` file in the gem, two modified core `lib/` files, one modified gem entry file,
one gemspec line, and three new test-support files. Design §3.4 and §7.3 between them name six of the
constants above — `Dexpace::Serde::JSON`, `List`, `Map`, `Nullable`, `Tristate` (with `ABSENT`,
`NULL`, `Present`) and `Dexpace::TypedResponse` (3b's) — so every other name carries a ledger row
(`P7-2`).

**Two placement notes.** `Body.serialized` goes on `Dexpace::Body` beside the other eight factories
rather than into a `Dexpace::Serde` module function, because `HTTP-38` puts body classification in one
place and a ninth factory beside eight is where a reader will look. And `Instant` is **core's**, not
the adapter's, because a witness is codec-agnostic by construction and putting it in the adapter would
make `dexpace-serde-oj` write a second one — while the *default wiring* of it as the encoder for
`::Time` stays the adapter's, which is precisely what design §3.4's sentence says ("the **adapter's**
default encoder configuration renders date and time values as ISO-8601 strings").

---

## The object model `7a` ships

### `Dexpace::Serde::DecodeContext`

Specified under `R2`. `Data.define(:path)`, `include Dexpace::Model`, `private_class_method :new`,
`.root` returning a frozen singleton with an empty frozen path, `#at(segment)` returning a new
context. Every `!` method funnels into `#error!`, which is the **one** raise site for a decode shape
failure — `SEAM-29`'s discipline applied to a second family, and the thing that makes `SERDE-13`'s
"across every decode overload" a property of one method rather than of every witness anyone writes.

`#float!` is the one method with a permission rather than a prohibition: `SERDE-22` requires integer
→ float widening, so `ctx.float!(1)` returns `1.0` while `ctx.integer!(1.5)` raises. Both directions
get their own test, because a strict-coercion implementation that also rejects the widening has
broken a MUST while looking more correct.

### `Dexpace::Serde::Tristate` — `SERDE-14`–`SERDE-20`, `SERDE-30`

A **module** carrying the six instance methods, included by all three values — exactly `Outcome`'s
shape (4b) and `Context`'s (4a), so `v.is_a?(Dexpace::Serde::Tristate)` is one type test and the RBS
union has a name.

```
Tristate::ABSENT           # frozen instance of a private_constant singleton class
Tristate::NULL             # ditto
Tristate::Present = Data.define(:value)     # include Dexpace::Model; .build rejects nil

# module functions (SERDE-18)
Tristate.absent / .null / .present(value) / .from_nullable(value) / .of(element_witness)
# instance methods (SERDE-18, SERDE-30)
#absent? / #null? / #present? / #value_or_nil / #fold(on_absent:, on_null:, on_present:) / #dexpace_dump
```

- **`SERDE-14`'s unrepresentable fourth state is closed on both paths.** `Present.build(nil)` raises
  `Dexpace::InvalidArgumentError` with `SEAM-29`'s message form, and `Dexpace::Model#with` routes a
  derivation through the same `.build` on **every** supported Ruby (`data-modeling/83610619`), so
  `Tristate.present(1).with(value: nil)` raises too. The `#with` half is the one a reader will not
  think to test; it has its own test.
- **`.of(element_witness)` and `.from_nullable(value)` are two different things with two different
  names**, deliberately: the first is the decode-side combinator `§7.3` names, the second is
  `SERDE-18`'s "nullable-to-(present|null) mapper that can never yield Absent". One `.of` doing both
  would be the API-design mistake `SERDE-18`'s own conformance clause exists to catch ("assert the
  nullable mapper yields Present for non-null and Null for null").
- **`SERDE-30` is taken.** Both sentinels override `#to_s` and `#inspect` to return `"Absent"` and
  `"Null"`, for §7.3's stated reason — Ruby's default `#inspect` renders an object id, so a log line
  or a test failure would otherwise differ between runs. Verified fact 13 confirms the frozen
  singleton stays `Ractor.shareable?`, which is a free side effect and no part of any claim.
- **`#dexpace_dump` returns `OMIT` for ABSENT, `nil` for NULL, and the inner value's dump for
  Present**, which is where `SERDE-15` and `SERDE-20` meet `Native` below.
- **Decoding is the combinator's**, and it is three lines because of verified fact 6:
  `Tristate.of(w).dexpace_load` is called by the enclosing witness with the enclosing `Hash` and the
  key, so it can ask `h.key?(k)` — `SERDE-16` and `SERDE-17` with no field-default machinery. The
  combinator therefore has a **two-argument** entry point for the in-object case
  (`#dexpace_load_field(hash, key, ctx)`) beside the protocol's `#dexpace_load(parsed, ctx)` for the
  top-level case, and the second is `SERDE-20`'s "deserialize a top-level null → Null".

### `Dexpace::Serde::List`, `Map`, `Nullable` — `SERDE-6`

Each is a frozen `Data` built by value from a concrete element witness, and each *is* a witness.
`List.of(Pet)`, `Map.of(String, Pet)`, `Nullable.of(Pet)`. Construction runs
`Dexpace::Serde.witness!` on every element argument, so `List.of(nil)` and `List.of(Object.new)` both
raise at **construction** with an actionable message — `SERDE-8`'s "reject construction with no type
argument", implemented; the "unresolved type variable" half is unreachable and stated rather than
emulated (`serde/ffc92673`).

A `String`/`Integer`/`Float`-shaped element is accepted as a witness by a small set of **built-in
scalar witnesses** rather than by special-casing the class objects: `Dexpace::Serde::List.of(String)`
resolves `String` through a frozen lookup table to a scalar witness that calls `ctx.string!`. That
keeps `.of`'s argument uniformly "a witness" while letting the ergonomic spelling §7.3 uses
(`Tristate.of(String)`, `Map.of(String, Pet)`) work verbatim. The table is a `private_constant`; it
covers `String`, `Integer`, `Float`, and the two boolean singletons' shape, and a class not in it
must answer `.dexpace_load` like anything else.

`Map.of` decodes keys through the key witness, which for JSON is always `String` — but the witness is
required rather than assumed, so a codec whose keys are not strings inherits the combinator unchanged.

### `Dexpace::Serde::Native` and `Dexpace::Serde::OMIT` — `SERDE-15`, `SERDE-19`, `SERDE-20` (`P7-9`)

`Native.of(value, encoders: {})` walks a value and returns codec-native Ruby: `Hash`, `Array`,
`String`, `Integer`, `Float`, `true`, `false`, `nil`. Its rules, in order:

1. `nil`, `true`, `false`, `Integer`, `Float`, `String` pass through. A `String` is
   `Model.frozen_string`-shaped on the way out only if it was mutable; nothing is retagged.
2. Anything answering `DUMP_METHOD` is replaced by `value.dexpace_dump` and re-walked. That is the
   model case, the `Tristate` case and the hand-written-witness case, all one branch.
3. `Hash` — every value walked; **an entry whose walked value is `OMIT` is dropped** (`SERDE-15`).
   Keys are coerced to `String` and a non-`String`-able key raises `SerializationError`.
4. `Array` — every element walked; **an element that walks to `OMIT` becomes `nil`** (`SERDE-20`'s
   array-element degradation).
5. At the **top level**, a value that walks to `OMIT` becomes `nil` (`SERDE-20`'s top-level
   degradation, "emit a wire null for both Absent and Null rather than throwing").
6. A class present in `encoders:` is replaced by `encoders[klass].call(value)` and re-walked. This is
   the only hook, and it is what carries the adapter's ISO-8601 default without core naming `::Time`
   as a policy.
7. Anything else raises `Dexpace::Serde::SerializationError` **naming the class** — the loud failure
   verified fact 3 shows `::JSON.generate` will not give.

**Why this lives in core rather than in each model's `#dexpace_dump`, which is what §7.3 describes.**
`SERDE-19` is a MUST that "the default codec configuration MUST wire the tri-state PATCH semantics"
and that "absent this wiring, Absent and Null become indistinguishable on the wire". §7.3's route —
the model omits its own Absent keys before `JSON.generate` — makes that wiring a **convention every
hand-written model must remember**, and the failure mode of forgetting it is silent and is exactly
the one the requirement names. Putting the omission in the walk makes it structural, which is the
word §7.3 itself uses for what `SERDE-19` needs ("`SERDE-19`'s default wiring is structural rather
than registered"). A model may still omit the key itself and nothing breaks; the walk simply has
nothing to drop. `P7-9` records the difference.

### `Dexpace::Serde::Instant` — `SERDE-24`'s decode half (`P7-8`)

A frozen singleton witness. `.dexpace_load(parsed, ctx)` calls `ctx.string!(parsed)` then
`::Time.iso8601`, converting `::ArgumentError` into `DeserializationError` naming `Time`;
`#dexpace_dump(time)` is the encoder side and is what the adapter installs in `encoders:`.

**Its documented precision domain is `P7-8`, and it is the one place `SERDE-24`'s "MUST round-trip to
the same instant" needs a caveat.** Verified fact 9: `Time#iso8601(n)` **truncates**, so a `Time`
whose `subsec` is not exactly representable in `n` decimal digits does not round-trip — including the
extremely ordinary `Time.new(…, 0.123456, …)`, whose stored rational is `0.12345599999…` and which
comes back one microsecond low. The port's position:

- **The encoder emits `#iso8601(6)`** — microseconds — because that is the resolution the overwhelming
  majority of HTTP APIs use and because a `Time` built from integer microseconds
  (`Time.at(sec, usec, :usec)`, `Time.utc(…)`) round-trips **exactly** at that width, verified.
- **The round-trip guarantee is stated as holding for any `Time` whose `subsec` is an exact multiple
  of one microsecond**, which is every `Time` this SDK itself constructs and every `Time` `Instant`
  decodes. It is stated in the YARD block, not left to be discovered.
- **Outside that domain the encoding truncates and the round trip is lossy**, and the YARD says so
  with the measured example. `7a` does **not** round instead of truncating: `Time#iso8601` is `time`'s
  and re-implementing its formatter to round would be a second date formatter beside 5a's
  `Dexpace::HTTPDate`, which is the outcome charter boundary 20 and `CLAUDE.md`'s "one ceiling, cited
  and never re-derived" habit both push against.

### `Dexpace::Serde::DecodingHandler` and `::StatusAwareHandler`

Specified under `R3`. Both are `Data.define`d, frozen, `private_class_method :new`, `.build` with
`Model.required!` on `serde:` and `witness:`, and `Dexpace::Serde.witness!` on the witness so a bad
one fails at handler construction rather than at first body access — which matters because
`TypedResponse` is lazy and a construction-time failure is the only one a caller sees before the wire.

### `Dexpace::Serde::JSON::Codec` — the six seam methods

`.build(**options)` and `.default` (`SERDE-25`: a **factory**, a fresh instance every call).
Frozen after construction, holding a frozen options `Hash` and a private `::JSON::Coder` built from
it. Every reference to Ruby's JSON is `::JSON`, per phase 0's shadowing caution and phase 2's
`Dexpace/QualifiedCoreConstant`.

| Method | Behaviour | IDs |
|---|---|---|
| `#media_type` | A memoized frozen `Dexpace::MediaType` for `application/json` | `SERDE-1`, `SERDE-2`, `SEAM-19` |
| `#dump_string(value)` | `@coder.dump(Native.of(value, encoders: @encoders))` — a UTF-8 `String` | `SERDE-4` (n/a), `SEAM-20` |
| `#dump_bytes(value)` | `#dump_string(value).b` — the same bytes, BINARY-tagged | `SEAM-20`, §10.13 |
| `#dump_to(value, sink)` | `sink.write(#dump_bytes(value))`; **never closes the sink** | `SERDE-3` |
| `#dump_into(value, buffer, offset:)` | Below | `SERDE-4` |
| `#load(source, witness)` | Below | `SERDE-3`, `SERDE-5`, `SERDE-12`, `SERDE-27` |

**`#dump_into`, stated in full because it is the profile with the most ways to be quietly wrong:**

```ruby
def dump_into(value, buffer, offset: 0)
  unless buffer.is_a?(::String) && !buffer.frozen? && buffer.encoding == ::Encoding::BINARY
    raise Dexpace::InvalidArgumentError, "buffer must be a mutable BINARY String"
  end

  encoded = dump_bytes(value)                       # may raise SerializationError; that is correct
  size    = encoded.bytesize
  if offset.negative? || offset > buffer.bytesize || offset + size > buffer.bytesize
    raise ::IndexError, "…", cause: nil             # SERDE-4: distinct, and NOT chaining (fact 11)
  end

  buffer[offset, size] = encoded
  size
end
```

Four measured decisions in nine lines. The **explicit fit check** is mandatory because verified fact
12 shows `String#[]=` silently *grows* the target on an over-long payload rather than raising — the
one behaviour `SERDE-4` exists to forbid. **`cause: nil`** is `pipeline/f02559b9`'s spelling and makes
"not chaining one" a property of the raise rather than of where the method happens to be called from
(verified fact 11). The **frozen/non-BINARY rejection** is `Dexpace::InvalidArgumentError` and not
`IndexError`, because a wrong *kind* of argument is not a wrong *range* and 3a already set that
precedent (`IO-3`/`IO-21`). And the payload is encoded **before** the fit check because the length is
not knowable otherwise — which means a generator failure surfaces as `SerializationError` and an
overflow as `IndexError`, in that order, and `SERDE-4`'s conformance clause is satisfied by two
tests rather than one.

**`#load`, stated in full because `R1` and `P7-6` both live in it:**

```ruby
def load(source, witness)
  Dexpace::Serde.witness!(witness)
  text = source.read_utf8                     # drains to EOF (SERDE-3); IO-9 guards incrementally
  unless text.valid_encoding?
    raise Dexpace::Serde::DeserializationError, "response body is not valid UTF-8"
  end

  parsed = @coder.load(text)
  witness.dexpace_load(parsed, Dexpace::Serde::DecodeContext.root)
rescue ::JSON::JSONError => e
  raise Dexpace::Serde::DeserializationError, "…"   # inside the rescue: Ruby sets #cause (SERDE-9)
end
# NOTE: no #close anywhere. SERDE-3, and phase 3's message-bodies/a7afc6ee names this rule as 7a's.
```

- **`source.read_utf8` and not `read_string(MediaType#charset)`.** RFC 8259 §8.1 fixes JSON text as
  UTF-8 for interchange, so the adapter reads UTF-8 unconditionally and does not consult the
  response's declared charset. That also keeps `#load`'s signature honest: it takes a source, not a
  response, and has no `MediaType` to consult.
- **The `valid_encoding?` guard is `P7-6`**, and verified fact 7 is why: `#read_utf8` retags without
  validating (3a's stated contract) and `::JSON.parse` accepts invalid UTF-8 without raising, so
  without this line a caller receives a `String` that claims UTF-8 and is not one, several frames
  from the cause. It costs one scan of an already-materialised `String` and it is stated in the YARD
  as the port's own guard rather than the codec's.
- **`rescue ::JSON::JSONError`, never `rescue StandardError`.** Verified fact 4: a
  `Dexpace::StreamError` is an `::IOError` and cannot be caught by it, so `SERDE-12` is satisfied
  structurally. A `rescue StandardError` would catch it and break the MUST, which is why the narrow
  rescue is a design decision and not a style one.
- **No `#close`.** `SERDE-3`, `SEAM-21`, design §10.12, `message-bodies/a7afc6ee`, and the adapter's
  suite asserts it against `CloseCountingSource` — including the requirement's own tail, "even when
  the codec's own auto-close feature is enabled", which for `json` means the assertion holds with
  every option the adapter accepts.

**`Dexpace::Serde::JSON` — the module's own surface:**

```ruby
module Dexpace
  module Serde
    module JSON
      MINIMUM_JSON_VERSION = "2.19.9"                                  # P7-7

      def self.default = Codec.build                                  # SERDE-25: fresh every call
      def self.build(**options) = Codec.build(**options)
    end
  end
end
```

plus, at require time, the floor assertion and the seam registration:

```ruby
if ::Gem::Version.new(::JSON::VERSION) < ::Gem::Version.new(MINIMUM_JSON_VERSION)
  raise Dexpace::SeamError, "dexpace-serde-json requires json >= #{MINIMUM_JSON_VERSION} …"
end
Dexpace::Serde.register(:json, -> { default }, core: Dexpace::VERSION)
```

The `core:` argument is design §2.4's registration-time version-skew assertion, spent here for the
first time by an adapter with a third-party dependency. `Gem::Version` needs no `require` (verified).

---

## The `sig/` shape

**Public means a YARD block *and* an RBS signature**, so every constant in the module layout above
gets a `sig/` mirror at the mirrored path, in the gem that ships it. Three things about the shape are
decisions rather than mechanics:

- **The witness is an RBS `interface`, not a class.** `interface _Witness; def dexpace_load:
  (untyped parsed, Dexpace::Serde::DecodeContext ctx) -> untyped; end` in
  `gems/dexpace-core/sig/dexpace/serde/witness.rbs`. An interface is what a structural duck type is,
  it is what 3b did for `_ResponseHandler`, and it means a caller's own model class type-checks
  against `List.of` without inheriting anything. `parsed` and the return are `untyped` because a
  witness's target type is the caller's; RBS and Steep are a **gate rather than a guarantee** here
  and the port claims no more (`serde/2f431a07`, §7.3's honest third point).
- **`interface _Codec`'s body is written here**, filling in what phase 2 declared and left empty. Its
  `#media_type` returns `(Dexpace::MediaType | String)` per `R3`; `#load` takes `(untyped source,
  _Witness witness) -> untyped`, where `source` is `untyped` rather than
  `Dexpace::IO::BufferedSource` because `SERDE-3`'s subject is "a caller-supplied stream" and
  phase 2's own test passes a `StringIO`.
- **`NFR-11` is satisfied per gem, and the adapter's half is the one to watch.** No constant outside
  `Dexpace::` and the fixed stdlib allowlist may appear in a public signature. Core's serde `sig/`
  names `::Time` (in `Instant`) and nothing else foreign; **the adapter's `sig/` names no `::JSON`
  constant at all**, because `Codec.build` takes a plain options `Hash` and the `::JSON::Coder` is a
  private instance variable with no reader. That is a deliberate narrowing of the adapter's surface
  and it is what keeps `NFR-11`'s scan clean in the one gem where it would otherwise fire.

The plan's final task regenerates **both** the RBS baseline and the runtime surface snapshot, because
`Data.define`'s generated readers on `Tristate::Present`, `DecodeContext` and the three combinators
are public API invisible to `rbs validate`, and the two gates each catch what the other cannot.

---

## The spec-forced boundaries, honoured

Each of the charter's twenty-four boundaries that reaches `7a` is honoured by name, not re-argued.
The ones belonging wholly to `7b` or `7c` are listed as not `7a`'s so a reader can see the whole set
was read.

1. **Core's SSE layer holds no serialization dependency (boundary 1).** `7b`'s. `7a` writes nothing
   under `lib/dexpace/sse/**`, exports nothing for it, and adds no path to the `SSE-37` audit.
2. **The witness is a class-object-and-combinator protocol, never a reflective type token
   (boundary 2).** §10.14 and §7.3. `7a` builds the protocol §10.14 substituted and does not re-open
   the substitution; `SEAM-8`'s unresolved-type-variable rejection is recorded as unreachable rather
   than emulated.
3. **All four encode profiles ship and the seam's six methods are phase 2's (boundary 3).** `7a`
   implements the six, adds no seventh to the seam and removes none; `#dump` stays a documented
   shorthand outside `CONTRACT`.
4. **The pagination strategy reads the response itself (boundary 4).** `7c`'s. `dexpace-serde-json`
   receives no pagination code and `7a` ships no page-shaped witness.
5. **The `SSE-37` audit extended over the pagination layer (boundary 5).** `7b`'s or `7c`'s,
   whichever lands first. **`7a` writes no part of it**, stated here so neither sibling assumes
   otherwise.
6. **A codec closes nothing (boundary 6).** `SEAM-20`, `SEAM-21`, `SERDE-3`, `serde/cfbe4e9a`,
   `message-bodies/a7afc6ee`. `#dump_to` does not close the sink, `#dump_into` does not own the
   buffer, `#load` does not close the source, and the adapter's suite asserts each against a
   close-counting tracker — including `SERDE-3`'s "even when the codec's own auto-close feature is
   enabled" tail.
7. **`Dexpace::TypedResponse` is supplied into, never replaced (boundary 7).** Both handlers answer
   `#call(response)`. `7a` writes no second memo, no second `@state` machine and no second lock.
8. **`dexpace-conformance` is not written into by phase 7 (boundary 8).** `R12`. `7a` records the
   phase-9 lift target in its checklist.
9. **A pipeline is a transport (boundary 9).** `7c`'s. `7a` touches no 4c file.
10. **`Dexpace::Outcome` gains its third variant in the SSE namespace (boundary 10).** `7b`'s. `7a`
    adds no member to `Outcome`, `Success` or `Failure` and consumes none.
11. **The suppressed trail is `Dexpace.attach_suppressed`/`.suppressed` (boundary 11).** Named for
    `PAGE-13`, `PAGE-15`, `SSE-29`, `SSE-36` — none of them `7a`'s. **`7a` attaches no suppressed
    exception**, because no `SERDE` requirement describes a two-failure path: `SERDE-27`'s `ensure`
    close is the only place a second failure could arise, and a `#close` raising there propagates
    over the primary rather than attaching to it, which is `HTTP-43`'s and `BODY-15`'s behaviour and
    not `7a`'s to change. Stated because a reader will look for the trail here.
12. **`SSE-30`'s swallow-versus-propagate split (boundary 12).** `7b`'s. `7a` calls
    `Dexpace.close_quietly` nowhere — `SERDE-27`'s "close on every path" is a loud close, not a quiet
    one, and using the quiet helper would swallow a close failure the caller is entitled to see.
13. **Every cause walk goes through `Dexpace.each_cause` (boundary 13).** `7a` walks no `#cause`
    chain at all: `SERDE-9`'s chaining is Ruby's own implicit `#cause` from raising inside a `rescue`,
    and nothing in `7a` classifies by cause.
14. **Resource acquisition and release never live inside an `Enumerator` block (boundary 14).** `7a`
    builds no `Enumerator` and acquires no resource inside a block it hands out. Named because the
    charter calls it the constraint phase 7 exists downstream of.
15. **The line-reading primitive is phase 3a's (boundary 15).** `7b`'s. `7a` reads no lines.
16. **`MAX_MATERIALIZED_BYTES` is one ceiling, cited and never re-derived (boundary 16).** `#load`'s
    drain is guarded by it, `7a` introduces no second materialisation constant and lowers 3a's not at
    all — see `R1` clause 4.
17. **Bytes on the wire are BINARY; the decode boundary is retag-then-transcode with both encodings
    named (boundary 17).** `#load` retags through 3a's `#read_utf8` and adds the validation step
    verified fact 7 shows the recipe needs (`P7-6`). **Every encoding assertion in `7a` uses non-ASCII
    content**, for the reason `io-and-byte-streams/a44b4de6` gives: appending an ASCII-only `String`
    to a BINARY one leaves it BINARY, so an ASCII-only fixture passes under exactly the bug.
18. **`URI::RFC3986_PARSER` is pinned (boundary 18).** `7a` parses no URL.
19. **`downcase` is called with no arguments (boundary 19).** One site: `SERDE-2`'s media-type
    comparison, which goes through phase 1's `MediaType` — already folded at construction — so `7a`
    writes no fold of its own and the cop has nothing to bite.
20. **`Time.parse`, `Date.parse` and `DateTime.parse` are banned (boundary 20).** `SERDE-24` uses
    `Time.iso8601`/`Time#iso8601` from `time`, which is on the allowlist and is not what the cop bans
    (verified fact 10). **`7a` does not reach for `Dexpace::HTTPDate`**, which is RFC 1123 and a
    different grammar.
21. **`JSON.load` and `JSON.unsafe_load` have no place in a decode path, and inside `module
    Dexpace::Serde` a bare `JSON` is the adapter (boundary 21).** `7a` is the first code
    `Dexpace/QualifiedCoreConstant` bites. Every reference is `::JSON`; `#load` uses
    `::JSON::Coder#load`, which is `::JSON.parse`'s configured form and **not** `::JSON.load` — the
    two share four letters and nothing else, and the plan's task says so at the call site so a later
    reader does not "fix" it. Core's own `lib/dexpace/serde/**` files reference `JSON` in no form at
    all.
22. **Regexp timeouts are per-pattern (boundary 22).** `7a` compiles no regexp. `Time.iso8601`'s own
    grammar is `time`'s and `7a` does not reimplement it.
23. **`Ractor` is never load-bearing (boundary 23).** `Tristate`'s sentinels and `Present`, the four
    combinators and `DecodeContext` are frozen `Data`/singletons and are Ractor-shareable as a free
    side effect (verified fact 13); nothing in `7a` claims or tests it.
24. **Phases 1 through 7 test against an in-memory fake transport (boundary 24).** `7a` needs no
    transport at all — its handlers take a `Response`, which the suite constructs directly — so the
    constraint is met by having no subject.

---

## Cross-cutting constraints that bite `7a` specifically

- **`Thread::Mutex` is per-fiber-owned and non-reentrant.** `7a` holds **no mutex at all**. The one
  place a lock is required in this subsystem is `HTTP-45`'s `TypedResponse` flip, which is **3b's,
  shipped, and held across the flip only** (`serde/97665a9a`); a handler `7a` supplies into it runs
  *outside* that lock by construction, which is the whole reason 3b wrote it that way. A handler that
  took its own lock would nest one inside a parse and reintroduce exactly the deadlock 3b avoided.
- **Bytes on the wire are `Encoding::BINARY`.** `#dump_bytes` is `#dump_string(value).b` and
  `#dump_into`'s target must be BINARY, both because the tag is load-bearing at §3.1's boundary and
  because a UTF-8-tagged buffer would make byte offsets and character offsets disagree in
  `String#[]=`. Every encoding test uses non-ASCII content.
- **An `Enumerator` abandoned mid-`#next` never runs its `ensure`.** `7a` builds none, and the
  handlers' close is an `ensure` in an ordinary method, not in a block handed to a caller.
- **Deadlines are explicit values, not ambient interrupts.** `7a` imposes no timeout: `IO-40` forbids
  the I/O layer from owning one and `7a` sits above it. A large body is bounded by
  `MAX_MATERIALIZED_BYTES`, which is a **size** bound, not a time bound, and `7a` states that
  distinction at the handler rather than letting a reader assume a slow trickle is caught.
- **`SEAM-2`: core names no concrete implementation.** It bites hardest here because this is the
  sub-phase with a concrete implementation in it. `Dexpace::Serde::JSON` appears in no core `lib/`
  file, in no core `sig/` file (`NFR-11`) and in **no core test** — mechanised by `7a`'s own negative
  test over core's `test/` tree, per `R12`.
- **`Ractor` is never load-bearing** and **the bundled-gem rule** — core's new files require nothing
  outside phase 0's allowlist, and `time` (the one they need, for `Instant`) is on it.

---

## Testing strategy

Six natural groups. Two of them exist because a measured fact showed the obvious test would pass
under the bug.

1. **`DecodeContext` unit tests** — one test per `!` method's accept case and per its reject case,
   with `SERDE-21`'s nine named coercions as **nine explicit fixtures** rather than a loop, because
   the requirement names them individually and a loop that drops one is invisible; plus `SERDE-22`'s
   two permissions (integer→float widening, empty-string→string) as their own tests, since a strict
   implementation that also rejects those has broken a MUST while looking more correct. `#error!`'s
   message form is asserted once, as `SEAM-29`'s is.
2. **Witness protocol and combinator tests** — `.witness!`/`.witness?` against a class, a combinator
   instance, a lambda-shaped object and `Object.new`; `List.of(nil)` and `List.of(Object.new)` raising
   at construction (`SERDE-8`); a `List.of(Pet)` decoding an array into real `Pet`s and a field access
   returning a typed value (`SERDE-5`'s own conformance clause); `Map.of`, `Nullable.of`; and
   `SERDE-23`'s tolerant decode — a document with an extra field decodes successfully.
3. **`Tristate` tests** — the three states' `SERDE-15`/`SERDE-16` round trip (`{}` → Absent,
   `{"x":null}` → Null, `{"x":v}` → Present, and back), `SERDE-17`'s absent-not-null assertion,
   `SERDE-14`'s `Present.build(nil)` **and** `Tristate.present(1).with(value: nil)` both raising,
   `SERDE-18`'s nullable mapper never yielding Absent, `SERDE-20`'s top-level and array-element
   degradation, and `SERDE-30`'s two sentinel strings asserted as **string equality**, not as
   `refute_match(/0x/)`.
4. **`Native` tests** — the seven walk rules, each with a fixture; the `OMIT` drop in a `Hash`, its
   `nil` in an `Array` and its `nil` at top level as three separate tests; and the unserializable-value
   case asserting `SerializationError` **naming the class**, which is the assertion verified fact 3
   says `::JSON.generate` alone would fail.
5. **Handler tests, against `FakeCodec` and never the JSON adapter** — `SERDE-27`'s five-case
   conformance matrix written as five tests (valid body → typed value plus **one** close; bodyless →
   serde exception naming the target; malformed → serde exception with a non-`nil` `#cause`;
   mid-stream I/O error → propagates **unwrapped**; the response closes in every case, asserted by a
   close-counting `Response` double); and `SERDE-28`'s branches, including the **599** case in the
   4xx/5xx branch and the 304 case in the third, with the third asserting the message leads with the
   code and carries the raw `ETag` and `Location` values. A `TypedResponse` integration test asserts
   the handler runs **once** across three `#value` calls and that a failure is re-raised as the
   **same object** — 3b's guarantee, asserted here because `7a` is its first real consumer.
6. **Adapter tests in `gems/dexpace-serde-json/test/`, through `SerdeSeamAssertions`** —
   `SERDE-3`'s close count of **0** for `#dump_to`, `#dump_into` and `#load`; `SERDE-4`'s four-part
   matrix (return equals standalone length; `[N, N+len)` matches; `[0,N)` unchanged; a one-byte-short
   buffer raises a range error that is **not** the serde type and whose `#cause` is `nil`);
   `SERDE-9`'s "the thrown type is the SDK serde type, not the library's, **and its cause is the
   library's exception**"; `SERDE-10`'s direction split; `SERDE-12`'s injected I/O error propagating
   unwrapped **and** its malformed-content counterpart being wrapped; `SERDE-19`'s "build from a bare
   codec with default settings" round trip; `SERDE-21`/`SERDE-22`'s policy through the real codec;
   `SERDE-24`'s round trip **within the stated precision domain** plus an explicit test asserting the
   documented truncation outside it, so `P7-8`'s caveat is executable rather than prose;
   `SERDE-25`'s two calls returning distinct instances; and `SERDE-29`'s concurrent-workers test
   (`refute_same` on the two `.default` results, then many threads encoding and decoding distinct
   values through one frozen codec).

**Two negative tests that exist because a measured fact demands them:**

- **No core file, `sig/` file or test names `Dexpace::Serde::JSON`.** A grep-shaped test over
  `gems/dexpace-core/`, because `SEAM-2` is invisible to every other gate inside one gem.
- **`gems/dexpace-serde-json`'s suite constructs no Ruby `IO::Buffer`.** Verified fact 5: it would
  raise through phase 0's `Warning.warn` override. `P7-5` makes the exclusion a contract; the test
  makes it a gate.

**One property test**, because `testing/f36a19cd` makes round-trip property tests mandatory for a
value object with parse-constructor invariants and `Tristate` has one: over a seeded generator of
Absent/Null/Present values embedded in a model, `load(dump(v)) == v` for every case, with the seed
pinned and logged (`testing/7ece0212`). The `SERDE-24` round trip gets the same treatment over
integer-microsecond `Time`s.

**No test allocates 64 MiB.** `MAX_MATERIALIZED_BYTES`'s behaviour is 3a's and already tested there;
`7a`'s `#load` asserts only that a `Dexpace::StreamError` raised by a stubbed source propagates
unwrapped through the codec's `rescue`, which is the property `R1` clause 3 states and needs no real
allocation to prove.

---

## The interface surface later phases may cite

Stated as a contract, so a later phase cites rather than re-derives.

| Consumer | What it gets, and the obligation |
|---|---|
| **`7b`** | **Nothing, and that is the contract.** `SSE-37` forbids it. `7b`'s design should state that it consumes no `7a` constant and requires no `dexpace/serde` file, which is what the audit will check |
| **`7c`** | **Phase 2's `Dexpace::Serde` duck type, never `7a`'s codec.** A strategy may accept an object answering the six seam methods; it may not name `Dexpace::Serde::JSON`, and it need not name any `7a` constant either. If a `7c` strategy wants a typed extraction it takes a caller-supplied `#call(response)`, not a witness |
| **Phase 8**, on `SERDE-27` (`P7-1`) | The obligation to satisfy the no-materialization clause when its library can: `#load(source, witness)` **already takes the source**, so an adapter with a pull parser satisfies it with no change to core, to the handlers or to the seam. Named in `docs/first-release.md` by the finding below |
| **Phase 8**, on `_Codec` | `interface _Codec`'s written body, including `#media_type`'s `(Dexpace::MediaType | String)` return. A second codec adapter implements six methods and inherits `Native`, `Tristate` and `DecodeContext` unchanged — `serde/66ebd950`'s "no second code path in core", made concrete |
| **Phase 8**, on `TRANSPORT-18` | Nothing from `7a`. `SERDE-26` and `TRANSPORT-18` share §11.18's shape; `P7-4` closes `SERDE-26`'s half literally and says nothing about the transport's |
| **Phase 9**, on `SEAM-20`/`SEAM-21`/`SERDE-3` | `gems/dexpace-serde-json/test/support/serde_seam_assertions.rb` — the named lift target for the conformance suite, written against the seam and never against `Dexpace::Serde::JSON` by name. `7a`'s checklist names the file |
| **Phase 9**, on `XCUT-12` | `Dexpace::Serde::JSON::Codec` as a frozen, cache-free shared instance, and the stated reason there is no per-type cache to audit (`SERDE-29`) |
| **Phase 9**, on `XCUT-15` | `Tristate`, `DecodeContext` and the four combinators as `Data`-frozen values; `Native.of` returning fresh collections, never aliasing a caller's |
| **Phase 9**, on `SEAM-2` | The negative test over core's tree as the audit's existing evidence, rather than a repository-wide grep reconstructed at audit time |
| **A downstream SDK author** | `Dexpace::Serde::WITNESS_METHOD` and `DUMP_METHOD` as the two names a code generator emits against, and the open-combinator rule as the extension route |

---

## Deviation Ledger

Numbering starts at `P7-1`; **no `P7-<n>` exists anywhere in `docs/`, verified 2026-09-10.** Each row
is consolidated into design §10 and audited by `docs/deviations.md`.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P7-1 | **`SERDE-27`'s "without first materializing the whole body" is NOT satisfied.** The handler materialises nothing and hands `#load` the `BufferedSource`; the JSON adapter then drains to EOF into one `String` under `Dexpace::IO::MAX_MATERIALIZED_BYTES`. A body above the ceiling raises `Dexpace::StreamError`, unwrapped | `SERDE-27`; design §3.4's `JSON.load` ban; `serde/5e420c20`; verified facts 1, 2 and 4 | Verified against **json 2.19.9**, the gemspec floor, not only against the interpreter's 2.9.1: `JSON.parse` raises `TypeError` on a `StringIO`, `JSON::Parser` exposes only `#parse`/`#source`, and no singleton method is pull-shaped. `JSON.load` is the sole IO-accepting entry point and is banned by lint rule for CVE-2020-10663's `create_additions` hazard. The `#to_str` loophole works and buys nothing, because `#to_str` returns the whole `String`. The only remaining route is to write a JSON parser inside the gem whose purpose is to delegate to `json`, which would make the `>= 2.19.9` floor meaningless. The seam's shape keeps the deviation adapter-local: an adapter with a pull parser satisfies the clause with **no change to core, to the handlers or to the seam** |
| P7-2 | Public **constants** neither design §3.4 nor §7.3 names: `Dexpace::Serde::DecodeContext`, `::Native`, `::OMIT`, `::Instant`, `::DecodingHandler`, `::StatusAwareHandler`, `::WITNESS_METHOD`, `::DUMP_METHOD`; `Dexpace::Serde::JSON::Codec` and `::MINIMUM_JSON_VERSION` | `NFR-4`; `NFR-11`; `api-design/b0e18938`; `P1-1`, `P2-11`, `P3-14`, `P4-24`, `P5-1`, `P6-1` precedent | `NFR-4` locks a name before it locks a signature. §7.3 names `Dexpace::Serde.witness!`, four combinators and `Tristate`'s three members; §3.4 names `Dexpace::Serde::JSON.default`. Everything above is chosen here for a stated reason in the object model, and placement follows `P1-1` unchanged — `Dexpace::Serde` is a namespace the design itself wrote, so these nest inside it and nothing else does |
| P7-3 | Public **methods** neither design §3.4 nor §7.3 names: `Dexpace::Serde.witness?`; `DecodeContext.root`, `#path`, `#at`, `#object!`, `#array!`, `#string!`, `#integer!`, `#float!`, `#boolean!`, `#present!`, `#error!`; `Tristate.absent`, `.null`, `.present`, `.from_nullable`, and the six instance methods; `Native.of`; `List`/`Map`/`Nullable`/`Tristate`'s `#dexpace_load` and `Tristate.of`'s `#dexpace_load_field`; `Instant.dexpace_load`/`#dexpace_dump`; both handlers' `.build` and `#call`; `Codec.build`, `.default` and the six seam methods; `Dexpace::Body.serialized` | `NFR-4`; `api-design/b0e18938`; `P4-23`, `P5-2`, `P6-2` precedent | `NFR-4` locks a signature, not only a name. Two deserve naming here. **`#dexpace_load_field(hash, key, ctx)` is a second entry point on one combinator** — `Tristate.of`'s — and exists because verified fact 6 makes the in-object case answerable only with the enclosing `Hash` in hand; the top-level `#dexpace_load` is `SERDE-20`'s and cannot see a key. **`Body.serialized` widens phase 3b's factory set from eight to nine**, which `NFR-4`'s "disappears or narrows" lock permits and `api-design/1d9e6e0b` covers |
| P7-4 | **`SERDE-26` is satisfied by a per-instance private `::JSON::Coder`, and the adapter accepts no caller-supplied engine** — where design §7.3 predicts "close to vacuous for a stateless `JSON` module … satisfied by holding configuration in a frozen options hash … the requirement's own fallback clause covers this" | `SERDE-26`; design §7.3; §11.18; verified fact 8 | §7.3 and §11.18 were written against **json 2.9.1**, which has no `JSON::Coder`. The floor the gemspec declares — **2.19.9** — does, and it is a real per-instance engine: freezable, thread-safe across 8 × 500 concurrent dumps, `[:dump, :generate, :load, :load_file, :parse]`. So the port does not need the fallback clause and does not invoke it. Two properties follow that the frozen-options-hash route does not give: no engine is ever shared between two serdes, and there is no caller instance to mutate because `Codec.build` takes options rather than a coder — which makes `SERDE-26`'s antecedent false by construction *and* its purpose satisfied literally, rather than either alone |
| P7-5 | **`#dump_into`'s target is a mutable `Encoding::BINARY` `String` only.** Ruby's `IO::Buffer` is rejected with `Dexpace::InvalidArgumentError`, where design §3.4 writes "a caller-supplied `String`/`IO::Buffer`" | `SEAM-20`; `SERDE-4`; design §3.4; phase 0's warnings-fatal gate; verified fact 5 | Measured: `IO::Buffer.new` emits an experimental warning through `Warning.warn` at **every** warning level, and phase 0's shared test case overrides `Warning.warn` **to raise** — so a test that constructs one fails the build, and a requirement whose conformance clause cannot be tested is not satisfied. Second reason: `IO::Buffer#set_string` raises `ArgumentError` where `String#[]=` raises `IndexError`, so supporting both would give `SERDE-4`'s "range/overflow error" two classes and a caller two rescues. Third: `Dexpace::IO::Buffer` — the name a reader will reach for — is a **FIFO with no offset addressing**, so it is not the missing third option either. A BINARY `String` *is* Ruby's byte array (§10.13's own argument), so nothing about `SEAM-20`'s buffer profile is lost |
| P7-6 | **`#load` validates that the drained text is valid UTF-8 before parsing**, raising `DeserializationError` — a guard neither the requirement nor the design names | `SERDE-9`, `SERDE-13`; `io-and-byte-streams/6eb5155f`; `OI-7`; verified fact 7 | Two silences compose into one: phase 3a's `#read_utf8` **retags without validating** (its own stated contract — "no replacement policy — that is `HTTP-42`'s"), and `::JSON.parse` accepts invalid UTF-8 and returns a UTF-8-tagged `String` whose `#valid_encoding?` is `false`. Without the guard a caller receives a `String` that claims an encoding it does not have, several frames from the cause, with no error anywhere. A *transcode* is the wrong repair — `"\xc3\xa9".b.encode(UTF_8, BINARY)` raises on a perfectly valid `é` — so retag-then-**validate** is the recipe, and `7a` adds the second step rather than changing 3a's primitive, because `7b`'s SSE machine reads the same primitive and may legitimately want bytes that are not valid UTF-8 |
| P7-7 | **`dexpace-serde-json` asserts `json >= 2.19.9` at require time**, raising `Dexpace::SeamError`, where `CLAUDE.md` and design §3.4 name `bundler-audit` as what enforces the floor | `NFR-2`; design §3.4; `serde/d15ade64`; verified fact 8 | `bundler-audit` runs in **this** repository's CI, not in a consumer's process, and it audits a `Gemfile.lock` — so it never sees an unbundled `require "dexpace/serde/json"`, which on Ruby 3.4.10 activates the interpreter's default `json` **2.9.1**. That version has no `JSON::Coder` at all, so the failure without the assertion is a `NameError` deep inside a codec rather than a message naming the floor — and, worse, the 2026 advisories the floor exists for would be silently unpatched. One `Gem::Version` comparison, no `require` needed |
| P7-8 | **`SERDE-24`'s round-trip guarantee is stated as holding for a `Time` whose `subsec` is an exact multiple of one microsecond**, and the encoder truncates outside that domain | `SERDE-24`; design §3.4's "the round-trip **SERDE-24** requires holds by construction"; verified fact 9 | Measured: `Time#iso8601(n)` **truncates**, so `Time.new(2026,9,10,12,0,0.123456,"+02:00").iso8601(6)` is `…00.123455+02:00` — one microsecond low — and the round trip fails. The `Float` second is stored as `8895942329546431/72057594037927936` ≈ `0.12345599999…`, and a `subsec` with no finite decimal expansion (`Rational(1,3)`) fails at any width. Integer-microsecond times round-trip **exactly** at `iso8601(6)`, which is every `Time` this SDK constructs and every `Time` `Instant` decodes. The port states the domain in the YARD with the measured example and asserts both halves in tests, rather than claiming "by construction" for a guarantee that measurably has an edge. Rounding instead of truncating would mean a second date formatter beside 5a's `HTTPDate` |
| P7-9 | **The tri-state omission is core's `Native` walk, not each model's `#dexpace_dump`**, where design §7.3 writes "`#dexpace_dump` builds the `Hash` and simply omits Absent keys before `JSON.generate`" | `SERDE-15`, `SERDE-19`, `SERDE-20`; design §7.3 | §7.3's route makes `SERDE-19`'s MUST a convention every hand-written model must remember, and the requirement names the exact failure of forgetting it: "absent this wiring, Absent and Null become indistinguishable on the wire" — silent, on the wire, in a PATCH. Moving the drop into the walk makes the wiring **structural**, which is the word §7.3 itself uses for what `SERDE-19` needs, and puts `SERDE-20`'s three degradations (top-level, array element, in-object) in one place instead of in every model. A model that omits its own Absent keys still works; the walk simply has nothing to drop. It also means `dexpace-serde-oj` inherits tri-state encoding by calling `Native.of`, which is `serde/66ebd950`'s "no second code path in core" |

---

## Deferrals filed by phase 7a

**None.** Every one of `7a`'s 30 IDs is implemented here, three of them with a deviation row and six
with a stated clause. No ID cluster moves out of `7a`'s scope to a later phase, and design §12's
`SERDE` row — "*Deferred:* none" — is unchanged by this document.

### Deferral-register sweep

`7a`'s delta against the charter's whole-register sweep, which covered every row once and is not
repeated here. As with phases 3, 4, 5 and 6, this document **states** each disposition and `7a`'s
**plan performs** the register edit.

- **`DEF-16` — untouched, and `7a` adds a second reason the row exists.** `dexpace-serde-oj` waits
  for "when JSON throughput is identified as a bottleneck the stdlib `json` gem cannot meet". `7a`
  ships the first codec against which such a measurement could be taken, and `P7-1` adds a
  *correctness* motive beside the throughput one: `oj` has a genuine streaming API, so an `oj`
  adapter would satisfy `SERDE-27`'s no-materialization clause outright. The condition is not met and
  the status does not change; a finding below proposes recording the second motive so it is not
  rediscovered.
- **`DEF-22` — untouched, and `7a` is careful not to pre-empt it.** `dexpace-conformance`'s
  framework-agnostic assertion objects are phase 8's. `7a` writes ordinary Minitest assertions in one
  named module and leaves the callable-plus-`Failure` shape alone — `R12`.
- **`DEF-29` — untouched, and its condition is still not met.** "The first consumer outside
  `dexpace-core`. Phase 8 at the earliest." `7a`'s adapter suite needs a **close-counting stream
  tracker**, which is not one of the three fakes the row covers (`FakeTransport`, `FakeAsyncTransport`,
  `FakeCodec`), so it writes its own in that gem's `test/support/` and consumes none of core's. The
  same disposition phase 3a gave.
- **`DEF-26` — closed in 3b, and named because `7a` is what it was closed *for*.** The `sig/`
  narrowing of `Request#body`/`Response#body` to `Dexpace::Body?` is the type `Body.serialized`
  returns into and the type `DecodingHandler` reads. No action.
- **`DEF-2` — untouched, and `7a` is the near-miss the charter identified.** `SERDE-28` is the first
  requirement anywhere in the specification naming an entity-tag in an executable clause, and it is
  satisfied by **copying the raw header value**, not by `HTTP-48`'s validating helper. `7a` confirms
  the charter's reading from inside the implementation: running a malformed server `ETag` through a
  validating parser inside an error path would turn a diagnostic into a second failure. The row's
  status does not change.
- **`DEF-1`, `DEF-3`–`DEF-15`, `DEF-17`–`DEF-21`, `DEF-23`–`DEF-28`, `DEF-30`–`DEF-43` — untouched**,
  all either closed by an earlier phase, targeted at `7b`/`7c`/phase 8, or riding on a post-v1 gem.
  Two are worth naming because a reader will wonder: **`DEF-8`** (`SSE-41`) is `7b`'s ⏳ row and
  appears nowhere in `7a`'s budget; and **`DEF-25`** (wire-boundary re-validation of header names and
  outbound values) is phase 8's, and `SERDE-2`'s stamped `Content-Type` is among the values it will
  re-validate — which is stated here so phase 8 has a named source for that value.

---

## Relationship to phase-level tasks, and to `7b`/`7c`

The charter records **no phase-level task owned by no sub-phase**: phase 7 installs nothing into the
pipeline, ships no preset, emits no instrumentation event required by any of its 107 IDs and widens no
phase-4 type. `7a` confirms that from inside its own scope — it installs no step, emits no event and
widens no phase-4 type.

Two items the charter records as **owed outside its own scope** are named again here so they are not
lost between three sub-phase designs, and **neither is `7a`'s to perform**:

- The `knowledge-lookup` skill's **thirteenth audit-group row** (*Serialization, SSE and pagination*),
  whose exact content the charter drafted. Whoever files the charter adds it. `7a` ran the group's
  `SERDE` half and reports above what a `--section rules`-only reading would have missed.
- **`CLAUDE.md`'s phase-directory claims sentence**, which goes from seven to eight the moment
  `docs/work/mvp/phase7/` exists. Mechanically caught by the probe's `claims` check.

`7a` claims neither, and it claims no part of the charter's one convergence point (`R11`, the
`SSE-37` audit extended over pagination) — that is `7b`'s or `7c`'s, whichever lands first, and this
document says so twice on purpose.

---

## The findings proposed for the registers

Four, described here for a human to file. **None is acted on by this document, none carries a number,
and no register file is edited by it.**

**Target register: `docs/open-items.md`.**
**Phase 2 declared `interface _Codec` and never wrote its body, and `#media_type`'s return type is
the clause with a consequence.** `docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md:4613-4614`
says `sig/dexpace/serde.rbs` "carries `interface _Codec` with the six methods and the module's class
methods" and gives no types; phase 2's `FakeCodec#media_type` returns the `String`
`"application/vnd.dexpace.fake"`; and `Dexpace::Body#media_type` returns `Dexpace::MediaType?`. So
`SERDE-2`'s "that media type MUST be used as the default Content-Type when a request body is created
from a value plus a Serde" crosses a type boundary nothing declares. `7a` settles it — the interface
declares `(Dexpace::MediaType | String)`, the JSON codec returns a `MediaType`, and `Body.serialized`
coerces a `String` through `MediaType.parse` and raises `Dexpace::InvalidArgumentError` naming the
codec's class for a `nil` or blank one — but the *finding* is that a declared-and-unwritten `sig/`
interface is invisible to every gate: `rbs validate` passes over an empty interface and `NFR-4`'s
diff has nothing to diff. Worth a row because phase 2 declared four other `sig/` files in the same
sentence and a reader should know whether the same happened to them. Cites: `SEAM-19`, `SERDE-1`,
`SERDE-2`, `NFR-3`, `NFR-4`.

**Target register: `docs/open-items.md`.**
**A `--section rules` audit of `SERDE` misses four of its thirty IDs, which is the charter's
navigation hazard from a third direction.** `--prefix SERDE --section rules` returns 26 entries;
`SERDE-17` lives only in *Constraints* (`serde/18a5757b`) and `SERDE-24`, `SERDE-25` and `SERDE-30`
live only in *Conclusions* (`serde/fccbd8a5`, `/d3bef411`, `/9c037363`). The
`knowledge-lookup` skill's audit-group table names `--section rules` for every group, and its audit
loop's step 2 says "Read the group. One query, `--section rules`, from the table above" — so an
auditor following the documented loop over `SERDE` reports clean over 26 of 30 rules. This is the
same species as `sse-streaming/5f4803a0` (an SSE rule filed under `PAGE-14`) and `pagination/b2a85752`
(a rule with no ID at all), and the charter proposed a row for those two; this one argues the fix is
different, because the entries are correctly filed and it is the *group query* that is too narrow.
The proposed amendment is to the audit-group table's `Query` column — `--section rules,constraints,conclusions`
for the ID-bearing groups — rather than to any corpus entry. Cites: `SERDE-17`, `SERDE-24`,
`SERDE-25`, `SERDE-30`.

**Target register: `docs/first-release.md`.**
**`SERDE-27`'s no-materialization clause is unsatisfied for every adapter the MVP ships, and the
failure is a `Dexpace::StreamError` a caller will meet at 64 MiB.** `P7-1`. The line to file: **before
release, the documented behaviour of a typed response handler on a body above
`Dexpace::IO::MAX_MATERIALIZED_BYTES` must be stated in `docs/sdk-documentation/`, and phase 8's
adapters must be checked for whether any of their libraries offers a pull parser that would satisfy
the clause** — because the seam already takes the source, so the repair is per adapter and costs core
nothing, and because a caller streaming a large JSON response through `Dexpace::TypedResponse` today
meets an `::IOError` rather than a documented limit. `dexpace-serde-oj` (`DEF-16`) is the named
candidate. Cites: `SERDE-27`, `IO-9`, `BODY-32`, `SEAM-21`, `DEF-16`.

**Target register: `docs/deferred-items.md`, as an amendment to `DEF-16`'s `Why` and `Cites`.**
**`dexpace-serde-oj` has a second reason to exist beyond throughput, and `7a` is what makes it
visible.** The row's current reason is "`oj` would be a faster codec over an already-proven seam, not
a new property"; `P7-1` shows that is now half the picture — `oj` has a genuine streaming parser, so
an `oj` adapter would satisfy `SERDE-27`'s "without first materializing the whole body" clause that
`dexpace-serde-json` measurably cannot, at the gemspec floor. That **is** a new property, and it does
not change the pick-up condition (throughput is still the trigger a user will feel first) but it does
change what the row is worth. Cites: `SERDE-27`, `SEAM-21`, `IO-9`.

**One existing row explicitly does not close.** `OI-7`'s subject is a sentence in the frozen §3.1 and
`7a` consumes the corrected retag-then-transcode recipe without touching the mechanism — it adds a
validation step above it (`P7-6`) rather than amending it. The item resolves when §3 is next
deliberately amended by a human, as the row itself says.

---

## The knowledge note `7a` files

Drafted here; the plan's final task writes it to `docs/knowledge/notes/serde.md`. It is a
`## Reference` entry rather than a `## Superseded` one, because it does not contradict
`serde/b5e5efc8` — it adds the guard that rule cannot reach.

```markdown
## Reference
- **A decoded JSON `String` can be UTF-8-tagged and invalid, and neither layer that produces it
  raises.** Beside `serde/b5e5efc8`, which puts the strictness burden on the witness: a witness
  asserting `String` cannot catch this, because an invalid-UTF-8 `String` *is* a `String`. Measured
  on Ruby 3.4.10 against json 2.9.1 and 2.19.9: `JSON.parse(%Q({"a":"\xff"}).b)["a"]` returns a
  `String` whose `#encoding` is UTF-8, whose `#bytes` is `[255]` and whose `#valid_encoding?` is
  `false`. Phase 3a's `#read_utf8` and `#read_string(encoding)` retag and apply no replacement
  policy, by their own stated contract, so nothing between the wire and the witness validates.
  Phase 7a's `Dexpace::Serde::JSON::Codec#load` therefore calls `#valid_encoding?` on the drained
  text and raises `Dexpace::Serde::DeserializationError` before parsing (`P7-6`). A *transcode* is
  the wrong repair: `"\xc3\xa9".b.encode(::Encoding::UTF_8, ::Encoding::BINARY)` raises
  `Encoding::UndefinedConversionError` for a valid two-byte `é`, because BINARY has no character
  semantics to convert from — so `io-and-byte-streams/6eb5155f`'s recipe is retag, then **validate**,
  and the transcode step applies only when a declared charset is not UTF-8.
  <sub>review · `docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization-design.md` · high · sha:manual-phase7a-utf8-validation</sub>
```

---

## Open questions for `7a`'s own plan

Five, each bounded, none reopening a decision above.

1. **The exact scalar-witness table's membership.** `List.of(String)` resolves `String` through a
   frozen `private_constant` lookup to a scalar witness, so §7.3's ergonomic spellings work verbatim.
   `String`, `Integer` and `Float` are certain. **Open:** whether `TrueClass`/`FalseClass` get an
   entry (there is no `Boolean` class in Ruby to key on, so the spelling would have to be a symbol or
   a core-supplied `Dexpace::Serde::BOOLEAN` constant), and whether `Time` resolves to `Instant`.
   *Recommendation:* ship `Dexpace::Serde::BOOLEAN` as a named witness rather than key on two
   classes, and **do not** map `::Time` in core — the ISO-8601 wiring is the adapter's per §3.4, and a
   core mapping would make it the default for every codec.
2. **Whether `DecodeContext#path` renders as JSON Pointer (`/pets/3/name`) or as a dotted path
   (`$.pets[3].name`) in `#error!`'s message.** Both are readable; only one should exist.
   *Recommendation:* JSON Pointer (RFC 6901), because it is a standard with an unambiguous escaping
   rule for a key containing `/`, and because a dotted path needs a bespoke quoting rule the first
   time a key contains a `.`.
3. **The `SERDE-27` "empty body" boundary's exact test.** `body.nil?` is certain. **Open:** whether a
   present body whose source is immediately at EOF is detected by a zero-length `#read_utf8` result in
   the codec (which would raise `DeserializationError` from `::JSON.parse("")`, chaining a
   `JSON::ParserError` whose message names nothing useful) or by an explicit check in the handler
   before delegating. *Recommendation:* the handler checks, because `SERDE-27` requires the exception
   to **name the target type** and only the handler knows it; the codec's message would satisfy
   "a serde exception" and fail "naming the target type".
4. **Whether `Codec.build`'s options `Hash` is validated against a known key set or passed to
   `::JSON::Coder` opaquely.** *Recommendation:* validated against a frozen allowlist, raising
   `Dexpace::InvalidArgumentError` for an unknown key — because `::JSON::Coder.new` accepts unknown
   options silently, and an adapter that forwards a typo produces a codec configured differently from
   what the caller wrote with no signal. The allowlist's exact membership is the plan's to fix
   against the floored gem, since 2.19.9's option set is what matters and not 2.9.1's.
5. **The three-interpreter re-run of verified facts 1–15, and specifically fact 8.** `JSON::Coder`'s
   presence is a property of the **gem**, not the interpreter, so the gemspec floor should make it
   uniform across 3.2, 3.3, 3.4 and 4.0 — but that has not been run, and Ruby 4.0's own default
   `json` version is unknown to this document. Task 1 of the plan installs all three interpreters,
   resolves `dexpace-serde-json`'s bundle on each, and re-runs every fact; **`P7-4` and `P7-7` are
   both conditional on fact 8 holding on all three**, and the plan says what changes if it does not
   (the frozen-options-hash route design §7.3 predicted becomes the fallback, and `P7-4` is withdrawn
   in favour of §11.18's reading).
