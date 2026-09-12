# Phase 8a — Synchronous Transport and Conformance

**Status:** Draft, for review. Written 2026-09-11, against
`docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`, which is this sub-phase's charter.

**Path:** `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md`.
That is the path this document carries for the rest of its life and the one every citation of it should
use. Its plan is
`docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance.md`; the checklist
is written at execution time and is not this document's to draft.

## Purpose

Sub-phase 8a builds the **reference synchronous transport** and the **shared adapter conformance
harness**: `dexpace-transport-net_http`, which spends its `NFR-2` budget on `net-http` and opens the
first real socket in the repository; and `dexpace-conformance`, whose gemspec, version, first release
and first suite phase 8 owns. Twenty-three requirement IDs, all `TRANSPORT`: `TRANSPORT-1`–`6`, `10`,
`11`, `14`–`20`, `22`, `24`–`30`. Nineteen MUST and four SHOULD (`TRANSPORT-6`, `27`, `28`, `30`).

**It is the sub-phase the charter recommends first**, for four reasons the charter gives and this
document does not re-argue. **None of that makes `8a` a dependency of `8b` or `8c`**, and the
Prerequisites section states that independence in `8a`'s own words rather than inheriting a chain by
habit.

Eight decisions the charter named and declined to make are made here — `R1`–`R7` and `8a`'s half of
`R16`. Five of them turn on facts this document **measured**, and three of the five invert a premise the
charter had to reason around:

- **`R1` is decided as a per-response producer `Thread` over a `Thread::SizedQueue`, not a `Fiber`, and
  the reason is not abandonment.** The charter's candidate list leads with a fiber pump and treats the
  never-run `ensure` as the objection. Measured, there is a harder one: **`Fiber#resume` from a second
  thread raises `FiberError: fiber called across threads`**, so a fiber pump created on a worker inside
  `Transport.async_over(net_http, executor: pool)` — the charter's own convergence point 2 — cannot have
  its body read on the caller's thread. A `Thread::SizedQueue` can be popped from any thread. The fiber
  route is not merely leak-prone; it is broken for the composition phase 8 exists to prove. `P8-1`.
- **`TRANSPORT-27` is fully satisfiable and the charter's `R4` premise is wrong.** `R4` says half the
  requirement is unreachable because a non-numeric `Content-Length` raises
  `Net::HTTPHeaderSyntaxError` "out of `#request` itself, so the response never materialises". Measured
  under the block form this adapter uses anyway: **the response head is delivered in full** — status,
  reason and every header — and the raise happens later, when `read_body` calls `content_length()`.
  Deleting the unparseable header from the native response before reading makes `read_body` fall back to
  connection-close framing and the body reads. Status, headers, `nil` media type, `-1` length and a
  readable body: every clause of the SHOULD, met. No deviation row.
- **Under `ruby -w` — this repository's own gate — `Net::HTTP` emits a `Warning.warn` on any
  body-bearing request with no `Content-Type`, and phase 0's shared test case overrides `Warning.warn`
  to raise.** `Net::HTTPGenericRequest#supply_default_content_type` is
  `warn '...' , uplevel: 1 if $VERBOSE`, and `#set_body_internal` assigns `body = ''` to **every**
  body-permitted method with no body — so a body-less `POST` trips it too. The adapter therefore sets an
  explicit `Content-Type` on every body-permitted method, and `application/octet-stream` is what it sets
  when neither the caller nor the body supplies one. `P8-4`. This is not a style choice: without it the
  first `POST` in the suite fails the build.

## Governing documents

- `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md` — the charter. It fixes `8a`'s 23 IDs,
  the twenty spec-forced boundaries, the six rejected cuts, the four convergence points, the five
  phase-level tasks and risks `R1`–`R7` and `R16`.
- `docs/product-spec/17-transport-adapter-conformance-contract.md`, read in full (51 lines), together
  with `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md:559-588` for the
  canonical text and modal level of all 30 `TRANSPORT` IDs. Appendix C is a convenience here rather than
  a necessity — every one of the 30 appears in its own prose chapter — and the chapter's
  `*Conformance:*` clauses, which appendix C does not carry, are load-bearing in seven places named
  below.
- `docs/product-spec/03-pluggable-seams-and-extension-model.md` for `SEAM-11`–`SEAM-15`, `SEAM-22`,
  `SEAM-29`; `docs/product-spec/05-i-o-contracts.md` for `IO-40`;
  `docs/product-spec/19-cross-cutting-invariants-and-policies.md` for `XCUT-4`, `XCUT-13`, `XCUT-18`,
  `XCUT-22`; `docs/product-spec/20-non-functional-requirements-and-quality-bar.md` for `NFR-1`, `NFR-2`,
  `NFR-11`, `NFR-13`.
- `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.1 (`:52-150`, the encoding boundary and
  the body variants), **§3.2 in full (`:155-188`)** — read critically, because `OI-34` and `OI-35` each
  record one of its sentences as false about `Net::HTTP` — and §3.7 (`:452-518`, the close contract, the
  `@owned` construction-time distinction, `close_quietly`'s two disposal routes and `SEAM-15`'s
  documented mode).
- `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.3 (`:195-231`) — the clock, the
  cancellable wait, and the prohibition on `Timeout.timeout`, `Thread#raise` and `Thread#kill`.
- `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md` §9.3 (`:65-113`) in full — Minitest as the
  framework, `dexpace-conformance`'s framework-agnostic assertion objects, the `TCPServer` fixture
  rather than a stubbing library, the lifecycle assertions, and appendix B.6's per-adapter restatement
  with its named-waiver mechanism.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` §2.1 (`:16-25`), §2.3 (`:41-70`, the layout and
  the `Dexpace::VERSION` registration-time skew assertion) and §2.4 (`:71-105`).
- `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items **4** (`:23-29`),
  **7** (`:63-67`), **10** (`:77-81`, the wire-boundary re-validation that is `DEF-25`), **11**
  (`:82-86`) and **12** (`:87-91`, the stream-ownership rule).
- `docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md` item
  **18** (`:59-62`, `TRANSPORT-18` presuming a re-subscribable body producer) and item **21** (`:73-78`,
  the adapter-scoped-and-vacuous shape "several `TRANSPORT-` requirements share"); and §12's `TRANSPORT`
  row (`docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md:41`), which the charter's `OI-34`
  records as wrong about `TRANSPORT-2` and `TRANSPORT-18`.
- `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md` and its plan — the
  seventeen gates, the five custom cops (`:523`), the require allowlist with its **denylist** naming
  `net/http`, `socket` and `timeout` (`:459`), the adapter extension to the same audit (`:471-475`), the
  gemspec audit's `NFR-2` budget with its `two_third_party` fixture, the clean-bundle isolation run, the
  six Steep targets and the empty `rbs_collection.yaml` (`:570-585`), and both gem skeletons
  (`:254-260`).
- `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md` — `Dexpace::HeaderSyntax` as
  public API built for this phase (`:419-440`), `Request`, `Response`, `Headers`, `RequestOptions`,
  `MediaType`, `Status`, `Protocol`, `Dexpace::Model`, and the module-not-class error root that makes
  `Dexpace::TransportError < ::IOError` reachable at all.
- `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` and its plan
  (`docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md:3500-3590`, read as **code**) —
  `Dexpace::Transport`'s duck type and registry, `Dexpace::Closeable`, `Dexpace.close_quietly`,
  `Dexpace::Cancellation`, `Dexpace::ClosedError`, `Registry#register(key, factory, core:)`, and the
  `SEAM-15` rule phase 2 already narrowed.
- `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md` — `BufferedSource.wrapping`
  and `.over`, `TypedReads`' vocabulary, `MAX_MATERIALIZED_BYTES`, `Dexpace::StreamError < ::IOError` as
  a **sibling** of `Dexpace::TransportError`, `Dexpace::EndOfStreamError < ::EOFError`.
- `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md` — `Dexpace::Body`'s
  contract, `Dexpace::ResponseBody.new(source:, media_type:, content_length:)`, `Dexpace::FileBody`,
  `Response#close`/`#body_string`, and `P3-23`'s `#source`/`#close` rule.
- `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md` and
  `…/phase4c/2026-09-08-phase4c-stage-pipeline-design.md` — the error taxonomy's shape and `PIPE-26`.
- `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-design.md` (`Configuration::Keys`,
  `Dexpace::Clock`), `…/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md`
  (`Instrumentation::Logger`, `Severity`, `Instrumentation.contain`, and `R8`'s allocation-assertion
  rule), `…/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md` (`HTTPTracer`'s five transport
  methods and the `OBS-21`/`OBS-25` obligations it places on `dexpace-conformance`).
- `docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry-design.md` — `P6-4`'s stated blind spot and the
  wrap obligation it puts on this phase.
- `docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination-design.md:1320`, `:1436` — the
  `Dexpace::Page::_Executor` duck type (`8b`'s) and `PAGE-36`'s per-call-options conformance test
  (`8a`'s).
- `docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization-design.md` as the closest worked
  example of this document's form.
- `docs/deferred-items.md`, `docs/open-items.md`, `docs/deviations.md`, `docs/first-release.md`.
- `CLAUDE.md` and `docs/README.md`.

---

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run before anything here was written, and re-run for
this document rather than trusted from the charter's report.

`ruby scripts/knowledge.rb --origin note --brief` returns **38 entries across 19 note files**.
`ruby scripts/knowledge.rb --section conflicts --brief` returns **24 entries across 17 topic files, 18
of them notes and six harvested**, and **all six harvested ones print `[overridden by notes/…]`**
(`data-modeling/35fde90f`, `module-organization/bf6411ad`, `package-and-dependency-layout/41b154a3` and
`/8c0687bf`, `tooling-and-quality-gates/86d763f1`, `type-system/93dc79aa`). **None is open**, so `8a`
inherits no unresolved conflict and owns no conflict decision of its own. Narrowed to this sub-phase's
one prefix, `--section conflicts --prefix TRANSPORT --brief` returns **nothing at all**, which the
charter already reported for both phase-8 prefixes and which this document confirms.

**Corpus coverage: complete.** `--prefix-info TRANSPORT` reports **30 of 30 substantive, 0 roll-up only,
0 uncited**, owning chapter `docs/product-spec/17-transport-adapter-conformance-contract.md`, topics
`transport-adapter` and `cancellation-and-timeouts`. `--gaps TRANSPORT` closes with "0 of 30 IDs in 1
prefix have no substantive entry". **`8a`'s spec-reading budget is zero**, which the section below
states in the form the roadmap requires.

**The audit groups run, and what each found.** The charter drafted the skill's owed thirteenth row
(*Transport and async-runtime adapters*) and could not add it; `8a` ran that group and six others the
task named.

| Audit group | Query run | What it found for `8a` |
|---|---|---|
| *Transport and async-runtime adapters* (the charter's owed row) | `--prefix TRANSPORT --section rules` (30, one per ID, **zero roll-up-tagged**) and `--topic transport-adapter --role design` (8) | The eight design-role entries are the whole of what the corpus says about the Ruby mapping, and **two of them are the sentences `OI-34` and `OI-35` record as false**: `transport-adapter/7e8e2c60` (`TRANSPORT-1`/`TRANSPORT-2` vacuous for this adapter) and `transport-adapter/d16c7444` (the block-scoped `read_body` construction). The other six are adopted: `/e25582ce` and `/938e4c9a` (the duck type), `/52b448e8` (per-call `Net::HTTP`, never a shared client), `/deccd514` (`TRANSPORT-6`'s clamp implemented anyway), `/2985bb74` (the no-op close unless a client was supplied), `/c3d2d69c` (`SEAM-2`) |
| *Public API surface* | `--topic api-design,http-domain-model,documentation,module-organization,error-handling --section rules --brief` (150) | No rule with no note bites `8a`. Load-bearing and adopted: `api-design/88e6bf12` (accept the narrowest duck type, return a concrete frozen value — which is the seam contract), `module-organization/1828a984` (one public constant per file). Already resolved by note and applied unchanged: `module-organization/2a4cc61d` (explicit requires, no Zeitwerk), `/6e69ad04` (flat public constants), `/5c33e5ce` (require-time registration is the one permitted load-time side effect — which is how this adapter registers), `error-handling/d2eadac4` (the module error root) |
| *Gem layout, zero-dependency core* | `--topic package-and-dependency-layout --section rules,constraints --brief` (14) and `--prefix SEAM --section rules --brief` (38) | `package-and-dependency-layout/c41c6c3d` is the entry that licenses this sub-phase's two gemspecs: "adapter gems are exempt from `dexpace-core`'s require restriction — an adapter that wants `logger` declares it, fitting within `NFR-2`'s budget". `/92c1d6c8` fixes the registration-time skew assertion; `/d18d0e25` fixes the gem-name-to-constant mapping; `/72199b8b` makes explicit requires an adapter rule too |
| *RBS / Steep typing* | `--topic type-system,data-modeling --section rules --brief` (86) | `data-modeling/83610619` (`Model#with` routes through `.build`) and `/5bc538ba` are notes already applied; nothing new. The binding one for `8a` is the `NFR-11` scan, which is a gate rather than a corpus rule |
| *Minitest conventions* | `--topic testing,assertions --section rules --brief` (29) | `testing/4ef070df` (every test runs alone in any order) is what forces a **fresh wire server and fresh transports per assertion** in the conformance harness rather than one shared server. `testing/f8994c72` is the Sorbet-sigil note, already resolved. `assertions/e8c05720` is the note that says the production assertion primitive is the domain model's helper — which is why `Dexpace::Conformance::Failure` is **not** an `Assert` facade and not a `Dexpace::Error` |
| *Encoding and binary strings* | `--prefix IO --section rules --brief` (33) and `--topic io-and-byte-streams,serde --section rules --brief` (76), then `--grep 'encoding\|binary\|ASCII-8BIT\|force_encoding'` | `io-and-byte-streams/a44b4de6` (the note): appending an ASCII-only `String` to a BINARY one leaves it BINARY while a non-ASCII one retags it, **so every encoding assertion in `8a` uses non-ASCII content**. `/a005249e` (the note): `force_encoding` raises on a frozen `String`; `String#b` is the retag idiom. Measured consequence for this adapter, below: `String#replace` copies the source's encoding and `String#clear` + `<<` does not, which decides the pump reader's `outbuf` handling |
| *Fiber scheduler, thread safety* | `--topic concurrency-and-async --section rules --brief` (75) and `--chapter 9` | `concurrency-and-async/c0fab747` (smallest critical section) and `/ee54cb68` with `/f261a143` (never hold a lock across I/O) are what keep the close latch's mutex across the flag flip only. `/611b9392` (check-after-resume) binds the pump. The six bounded-pool rules the note routes to `8b` by name are **not** `8a`'s, and this document does not answer them |
| *Resource lifecycle and stream ownership* | `--topic resource-management --section rules --brief` (27) and `--chapter 13` | The group with the one live conflict for `8a`, below |

**One harvested rule in `8a`'s scope has no note and contradicts a shipped design decision**, and this
document resolves it rather than filing a second note:

> **`resource-management/4aca52f9`** — "Never open one connection per request; size connection or HTTP
> pools with a bounded, named constant instead, since an unbounded per-request connection count can
> exceed the upstream's hard connection ceiling and cause request failures."
> <sub>styleguide · `styleguide/ruby/13-resource-management.md:105-111` · high · sha:9abc7f90733b</sub>

Design §3.2 and `transport-adapter/52b448e8` require the opposite — **a per-call `Net::HTTP`, never a
shared client** — and verified fact 9 shows why the design is right on the merits and not merely
normative: a shared `Net::HTTP` driven by eight threads produced 128 errors **and 26 responses matched
to the wrong request**, which is exactly the failure `TRANSPORT-29`'s conformance clause exists to
catch. The styleguide rule's own stated hazard is an *unbounded* connection count; a synchronous
transport opens at most one connection per in-flight call and spawns no caller, so the count is bounded
by the caller's own concurrency and the named failure cannot arise from the SDK's side. The roadmap's
precedence rule settles it — a corpus rule carrying a requirement ID beats a general styleguide default,
and `TRANSPORT-5`/`TRANSPORT-29` carry two. The cost the rule is really about — a TCP (and TLS)
handshake per request — is real, is stated at the adapter, and is proposed as a register item below
rather than hidden. The three companion rules in the same chapter, `/62da4ea9` (pair a pool with a
checkout timeout), `/b3da5097` and `/fa79bab6` (bound a cache), have **no subject** in `8a`: there is no
pool and no cache. `/b7587eb7` ("track every spawned thread … and join it in a teardown path that is
guaranteed to run") and `/346deaec` ("release resources in `ensure`, never in `rescue`") are adopted and
are exactly what `R1`'s teardown is built from. `resource-management/d1f16cad` — the note that names
"phase 8's transports, which own the socket and set `open_timeout`/`read_timeout`/`write_timeout` per
call … with the values coming from phase 5's layered configuration chain as named settings rather than
literals" — is the direct instruction `R3` answers.

**The entries `8a` is built on, cited by key rather than restated**, except where the rule turns on the
sentence:

- **`transport-adapter/52b448e8`** — "Per-call options are threaded as an immutable
  `Dexpace::RequestOptions` value and applied to a per-call `Net::HTTP` instance's `open_timeout`,
  `read_timeout`, and `write_timeout`, never to a shared client object, satisfying `TRANSPORT-5`'s
  single-call scoping structurally rather than by discipline."
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:178-181` · high · sha:bf7f85fc5f18</sub>
- **`transport-adapter/deccd514`** — `TRANSPORT-6`'s clamp is implemented anyway for adapters over
  coarser APIs. Verified fact 8 shows the requirement's *antecedent* is not merely absent here but
  inverted.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:181-184` · high · sha:bf7f85fc5f18</sub>
- **`concurrency-and-async/611b9392`** — the check-after-resume rule. `8a`'s pump is a producer that
  suspends on a queue push and on a socket read, and every resume is a point at which it re-checks its
  own closed latch before acting on what it produced.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:239-244` · high · sha:bf7f85fc5f18</sub>
- **`resource-management/346deaec`** — "Release resources in `ensure`, never in `rescue`."
  <sub>styleguide · `styleguide/ruby/13-resource-management.md:81-81` · high · sha:9abc7f90733b</sub>
- **`resource-management/b7587eb7`** — "Track every spawned thread … and join it in a teardown path that
  is guaranteed to run, since a thread with no reference to join can never be recovered." `8a` spawns
  one thread per in-flight response and the object holding it is the one with `#close`.
  <sub>styleguide · `styleguide/ruby/13-resource-management.md:310-314` · high · sha:9abc7f90733b</sub>
- **`pipeline/f02559b9`** — `raise error, cause: nil` is the spelling for re-raising an error a component
  is *carrying* rather than one it just rescued. `8a`'s pump carries the producer's failure across a
  queue and re-raises it on the consumer's thread, which is exactly that shape.
  <sub>review · `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md` · high · sha:manual-phase4b-reraise-cause</sub>
- **`io-and-byte-streams/a005249e`** and **`/a44b4de6`** — the frozen-ingress retag rule and the
  ASCII-only-fixture trap. Both reach `8a`'s inbound chunk handling.
  <sub>review · `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md` · high · sha:manual-phase3a-frozen-ingress-retag</sub>

**One knowledge note is filed by this document's plan**, and its subject is verified facts 4 and 5:
`Net::HTTP` warns through `Warning.warn` on a body-bearing request with no `Content-Type`, and
`#set_body_internal` gives **every** body-permitted method a body, so the warning fires on a body-less
`POST` too — which under this repository's own warnings-fatal gate is a red build rather than a log
line. Drafted in *The knowledge note `8a` files* below; the plan's final task writes it.

## The spec-reading budget

**Zero, and stating that is the obligation.** The roadmap requires a phase whose IDs come back as gaps
to budget reading time in its design document and say so there
(`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:154-155`); `--gaps TRANSPORT` reports 0 of 30,
so the budget is zero and this sentence discharges the obligation.

**What that does not license.** `--gaps` measures *corpus* coverage, not *specification* coverage
(`OI-12` states the same asymmetry from the other side). Chapter 17 was read in full anyway, at 51
lines, and its `*Conformance:*` clauses — which appendix C does not carry — prescribe a test shape no
appendix-C row implies in seven places: `TRANSPORT-2`'s "a single-use body and a first-attempt
connection failure", `TRANSPORT-5`'s "two **concurrent** calls with different per-call timeouts",
`TRANSPORT-11`'s "a bogus Content-Length/Host plus a pass-through header", `TRANSPORT-14`'s "an obs-text
value is preserved; a control-byte header is dropped and the body still reads", `TRANSPORT-24`'s "a 520
with a body", `TRANSPORT-25`'s "stream a multi-megabyte response and assert byte-exact round-trip", and
`TRANSPORT-28`'s "a non-zero position and partial count; assert exactly that byte range reaches the
wire". Each is quoted where a decision below turns on it, and each is an assertion in
`dexpace-conformance` rather than a sentence in a checklist.

And **corpus coverage says nothing about whether a design sentence is true.** `transport-adapter/7e8e2c60`
and `/d16c7444` are two rules the corpus carries faithfully from a design chapter that is wrong about
the library. `--gaps` cannot see that and neither can `--req`; only running Ruby can, which is what the
Verified Ruby facts section is for.

---

## Scope: the 23 IDs

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `TRANSPORT-1`–`6`, `10`, `11`, `14`–`20`, `22`, `24`–`27`, `29` | 20 |
| Partially satisfied, one clause ⏳ | `TRANSPORT-28` (`DEF-10`) | 1 |
| ⏳ deferred whole | `TRANSPORT-30` (`DEF-10`) | 1 |
| Vacuous with a stated reason | `TRANSPORT-18` (once `max_retries = 0`) | 1 |
| **Total in budget** | | **23** |

Level split, derived mechanically from appendix C on 2026-09-11: **19 MUST, 4 SHOULD** (`TRANSPORT-6`,
`TRANSPORT-27`, `TRANSPORT-28`, `TRANSPORT-30`). No `MUST NOT` row appears. **No `DEF-<n>` moves an ID
into `8a` and none moves one out.**

**Two dispositions differ from the charter's table and both are narrowings in the requirement's
favour**, argued under `R4` and `R5`: `TRANSPORT-27` is **satisfied whole** where the charter expected
"half unreachable", and `TRANSPORT-28` is **partially satisfied** — its embedded MUST and its
byte-range clause met, its zero-copy clause ⏳ — where the charter carried the whole ID ⏳. A sub-phase
narrowing its own charter's ⏳ toward satisfaction is the direction the charter invites (`R5` asks `8a`
to "decide whether to implement the reachable half and mark `TRANSPORT-28` partially satisfied"); the
checklist rows carry both halves separately so neither disappears into a tick.

### Eleven rows carry a clause the checklist must state rather than tick

Each is on the authority of a measured fact, a requirement's own conditional antecedent, or a design
appendix — never on `8a`'s convenience.

- **`TRANSPORT-1` is satisfied by an absence, and the row says so.** `Net::HTTP` exposes no
  follow-redirects knob at all: `(Net::HTTP.instance_methods + Net::HTTP.methods).grep(/redirect|follow/i)`
  is `[]` (verified fact 1). The requirement's "the follow-redirects knob's default MUST be off" is
  therefore true of a knob that does not exist, and the conformance assertion — enqueue a 302 with a
  `Location`, assert the returned response is the raw 302 — is a real assertion with a real subject and
  passes. The row states the absence and names `8c`'s different route (not installing
  `Async::HTTP::Middleware::LocationRedirector`).
- **`TRANSPORT-2` is NOT vacuous, and the row must state the corrected reason.** `Net::HTTP#max_retries`
  defaults to **1** and `#transport_request` retries on eight exception families for six methods
  including PUT and DELETE (verified fact 2). Design §3.2, §11.18 and §12 each record the opposite;
  `OI-34` is the charter's row against those three sentences. `8a` writes `http.max_retries = 0` and the
  row cites `OI-34` rather than §12.
- **`TRANSPORT-3`'s discrimination is out-of-band and its *shape* is `8a`'s, not its policy.** The
  requirement forbids discriminating "by matching messages", and the mechanism is
  `Dexpace::Cancellation#reason`'s typed object (phase 2). The row states that a cancellation delivered
  by closing the socket surfaces from `Net::HTTP` as a bare `IOError` indistinguishable from a peer
  reset, so the adapter decides which it was by asking the **token**, never the exception — and that
  `max_retries = 0` is what stops the library swallowing it first (verified fact 3, where the default
  `max_retries` turned a cancelled call into a completed 200).
- **`TRANSPORT-6`'s antecedent is not merely absent but inverted, and the clamp ships anyway.** The
  requirement conditions on a native API that "treats zero as 'no timeout'". Measured (fact 8):
  `Net::HTTP` with `read_timeout = 0` raises `Net::ReadTimeout` immediately — zero is *poll-once* — and
  `nil` is no timeout. A truncation to zero here would produce an over-eager failure, not a hang. Floats
  down to `0.0005` are honoured and time out in 1 ms. The row states both and records that the clamp is
  implemented for the reason `transport-adapter/deccd514` gives (adapters over coarser APIs), not
  because this one needs it.
- **`TRANSPORT-11`'s drop set is larger than the requirement's minimum, and `Host` is the surprise.**
  `Net::HTTP` recomputes `Content-Length`, deletes a caller-set `Transfer-Encoding` on the body path,
  and **honours a caller-set `Host` verbatim** (verified fact 4) — so the one header the requirement
  names that the library will not manage for us is the one the requirement names first. The row states
  the full drop set, the three auto-stamps that are suppressed, and the two hop-by-hop headers dropped
  for a stated reason rather than because the requirement names them.
- **`TRANSPORT-14` is entirely `8a`'s work and its failure mode is phase 1's strictness.** `Net::HTTP`
  **preserves** a control byte in a value and a non-ASCII byte in a name (verified fact 6), and phase
  1's `Headers` re-runs `HTTP-17`/`HTTP-19` over every stored name and value at construction — so an
  unfiltered copy makes one malformed inbound header fail the whole response, which is precisely what
  `TRANSPORT-14` exists to prevent. The drop happens **before** the values reach
  `Dexpace::Headers::Builder`. The row states the ordering.
- **`TRANSPORT-15` and `TRANSPORT-16` split along `8a`'s two entry points and the row says which half is
  which.** The SDK-managed construction owns no long-lived native resource (a `Net::HTTP` per call), so
  its `#release` has nothing to release; the borrowing construction holds a caller's client it must
  never touch. `TRANSPORT-15`'s conformance clause has both halves and both are assertable — a borrowed
  client survives the transport's close and stays usable; an SDK-managed transport refuses a later send
  (`SEAM-15`). The row states that "releases only resources the transport itself created" is satisfied
  by there being none, not by a release nobody runs.
- **`TRANSPORT-17` is true because of one line, and the row names it.** `max_retries = 0` removes the
  only route by which `Net::HTTP` re-runs `req.exec` and therefore re-writes the body (verified fact 2).
  The requirement's second half — "MUST NOT itself trigger a second write" — is `8a`'s own discipline
  and is asserted separately, because it is a statement about the adapter and not about the library.
- **`TRANSPORT-18` is vacuous once `max_retries = 0`, and the row must give that reason and not
  §11.18's.** §11.18 says `Net::HTTP` "has no resend hook"; it has one and it is on by default. With
  `max_retries = 0` the antecedent — "the native body API drives writes through a re-subscribable
  producer" — is genuinely absent, because `IO.copy_stream(f, sock)` is driven exactly once per `#exec`
  and `#exec` runs once. The row states the corrected reason and cites `OI-34`. `8c` reports whether the
  antecedent is live on `async-http` (`R14`, the charter's); if it is, `8a`'s row gains a second sentence
  rather than a second row.
- **`TRANSPORT-28` is split, and the row carries both halves.** Its embedded MUST — "MUST treat a file
  body as replayable so it can be re-sent" — and its "honoring start position and byte count" clause are
  **satisfied with no transport-specific code**, because `Dexpace::FileBody#replayable?` is `true` and
  `#write_to` is `::IO.copy_stream(handle, sink, count, offset)` (3b), reached through
  `BufferedSource.over(body)`. The "zero-copy path where supported" clause is **⏳ `DEF-10`**, measured:
  `send_request_with_body_stream` writes to a `Net::BufferedIO`, whose `is_a?(::IO)` is **false**
  (verified fact 12), so the kernel path is unreachable without bypassing the library's own write path.
- **`TRANSPORT-30` is ⏳ `DEF-10` whole, and the row states which of its clauses are *already* true.**
  Its embedded MUSTs — proxy credentials never logged, never answered to an origin 401 — hold vacuously
  because `8a` configures no proxy at all and therefore never holds a credential: the adapter passes no
  `p_addr`/`p_user`/`p_pass` and sets `proxy_from_env = false` explicitly, so `Net::HTTP`'s own
  environment-derived proxy cannot activate behind the SDK's back. The row states that as the reason the
  MUSTs are safe while the SHOULD is deferred, rather than leaving a ⏳ over an embedded MUST.

### What `8a` additionally ships, without owning a new ID

- **`add_dependency "net-http", ">= 0.4"`** in `gems/dexpace-transport-net_http.gemspec` — `NFR-2`'s
  third-party half for that gem, and the only place that floor is stated (phase 0's `P0-9`). The plan
  lands this line **before** the first `require "net/http"` in that gem's `lib/`, because phase 0's
  adapter-extended require-allowlist audit permits "the single third-party gem that adapter's gemspec
  declares" and the reverse order is a red build, not a style preference.
- **`DEF-25`'s call site in this adapter** — `Dexpace::HeaderSyntax.validate_name!` and
  `.validate_outbound_value!` run again over every outbound header immediately before dispatch. Phase 1
  shipped the module as public API for exactly this.
- **`dexpace-conformance`'s whole content**: `DEF-22`'s `Failure`, the callable assertion protocol, the
  `Vacuous` and waiver mechanisms §9.3 and §12 between them require, §9.3's `TCPServer` fixture, the
  transport suite, and the two thin drivers.
- **`7c`'s `PAGE-36` per-call-options conformance test** — the same transport driven **twice in
  sequence** with different `RequestOptions`, both honoured. It is not `TRANSPORT-5`'s clause, which
  asks for two *concurrent* calls.
- **`5c`'s two conformance obligations** — `OBS-25`'s allocation assertion, written under `5b`'s `R8`
  rule, and the **recording span** `OBS-21`'s idempotence assertion needs.
- **`Dexpace::Configuration::Keys::REQUEST_TIMEOUT`** — one new frozen `String` constant in `dexpace-core`,
  added in the change that reads it, per 5a's own rule that "a key constant with no reader is
  `NFR-4`-locked surface nothing exercises". `R3`.
- **A named per-gem exception to phase 0's require denylist**, so `dexpace-conformance`'s `lib/` may
  `require "socket"`. `R7`.
- **The stated cross-reference for `TRANSPORT-12`'s and `TRANSPORT-13`'s sync halves**, both vacuous on
  this adapter (verified fact 5) and both `8c`'s rows.

### Canonical text quoted because a decision below turns on it

> **TRANSPORT-2** (MUST) — Where the native client has a built-in connection-failure/automatic retry
> feature, an SDK-managed transport MUST disable it. *Conformance: with a single-use body and a
> first-attempt connection failure, assert the native client does not silently re-send.*

> **TRANSPORT-5** (MUST) — A per-call timeout override MUST apply to that single call, overriding the
> configured default for that call only and leaving the shared native client untouched; a null override
> leaves the configured default in force. *Conformance: two concurrent calls with different per-call
> timeouts; assert each is bounded by its own value.*

> **TRANSPORT-10** (MUST) — The caller's explicit request Content-Type MUST remain authoritative and
> MUST NOT be overwritten by a body-derived media type. A body-derived Content-Type MUST be emitted only
> when the caller set none (matched case-insensitively).

> **TRANSPORT-11** (MUST) — Headers the native client computes from the body/connection (at minimum
> Content-Length, Host, Transfer-Encoding; plus any the native client rejects outright, e.g.
> Connection/Expect/Upgrade on java.net.http) MUST be dropped before dispatch. The transport SHOULD
> additionally log each drop at verbose. The exact drop set is transport-specific (OkHttp does not drop
> Connection).

> **TRANSPORT-14** (MUST) — Inbound response headers MUST be copied leniently enough that a single
> malformed header does not fail the whole response: a control byte in a value, or a control/non-ASCII
> byte in a name, MUST drop only that header (logged at verbose) while the body and remaining headers
> are still delivered. A transport SHOULD preserve a non-ASCII/obs-text byte in a value rather than
> stripping it.

> **TRANSPORT-25** (MUST) — The response body MUST be exposed as a lazily-read stream, not pre-buffered,
> and closing the SDK response MUST cascade to close the native body and release the connection. The
> caller owns closing the response. *Conformance: stream a multi-megabyte response and assert byte-exact
> round-trip; assert closing returns the connection.*

> **TRANSPORT-27** (SHOULD) — An unparseable or absent inbound Content-Type SHOULD be downgraded to "no
> media type" rather than failing the response; an absent/invalid Content-Length SHOULD map to the
> unknown-length sentinel (-1). *Conformance: a malformed Content-Type and non-numeric Content-Length
> still let the body read, with null media type and unknown length.*

> **SEAM-11** (MUST) — The synchronous transport seam MUST be a single-operation contract: given one
> request, produce one response. The response body MUST NOT be pre-buffered by the transport — the
> caller owns reading and closing it. The transport MAY additionally accept per-call options; a
> transport that ignores options MUST behave identically to the no-options call.

### Out of scope, explicitly

| Excluded | Owning phase |
|---|---|
| `SEAM-11`, `SEAM-12`, `SEAM-13` — the sync seam, concurrency safety, cooperative cancellation | 2, built as a duck-typed `#call(request, options, cancellation)`. `8a` supplies the first implementation and `dexpace-conformance` the assertion; the rows stay phase 2's |
| `SEAM-14`, `SEAM-15` — the close contract and the post-close send | 2, built. `8a` is the **first raise site** for `Dexpace::ClosedError` on a transport, under the rule phase 2 already documented |
| `SEAM-16`, `SEAM-17`, `SEAM-18`, `SEAM-25`, `SEAM-30` — the async seam, the pivot, the bridges, the orphan close | 2, built. `8a` ships no async transport, posts nothing, and owns no executor |
| `TRANSPORT-7`, `8`, `9`, `12`, `13`, `21`, `23` | `8c`. Five have an **async-only antecedent**; `TRANSPORT-12`/`13`'s antecedent is a native wire grammar stricter than the SDK model's, which `Net::HTTP` does not have (verified fact 5) |
| `ASYNC-1`–`ASYNC-22` | `8b` and `8c`. `8a` names no `ASYNC` ID and adds no `ASYNC` row |
| `HTTP-17`, `HTTP-18`, `XCUT-18` — the validators | 1, built as `Dexpace::HeaderSyntax`. `DEF-25` is the call site and is picked up here; the rows stay phase 1's |
| `HTTP-13` — case-insensitive folding | 1. Relevant because `Net::HTTP` normalises name case on the wire (verified fact 11) and the SDK model's folding is unaffected |
| `HTTP-36`–`HTTP-46`, `BODY-1`–`BODY-37` — the body model | 3b, built. `8a` consumes `Body#each`, `#content_length`, `#media_type`, `#replayable?`, `FileBody`'s window, and `ResponseBody`; it adds no body type |
| `IO-1`–`IO-42` | 3a, built. `IO-40` is the boundary that keeps deadlines out of them and puts them here |
| `PIPE-1`–`PIPE-40` | 4c. `8a` installs no step; `PIPE-26`'s "a pipeline is a transport" is why the seam is a duck type |
| `RETRY`, `REDIR`, `AUTH` | 6. `8a` disables the native equivalents and installs nothing |
| `OBS-19`, `OBS-28`, `OBS-29` | 5b/5c, with `DEF-41` `8c`'s and `DEF-42` still open. `R6` decides what `8a` wires |
| `SERDE`, `PAGE`, `SSE` | 7. `8a` consumes none of them; `PAGE-36`'s conformance test is a test, not a pagination feature |
| `NFR-1`–`NFR-17` | 0 built the machinery, 9 dispositions it. `8a` **spends** `dexpace-transport-net_http`'s `NFR-2` budget and asserts nothing about the gate |
| `Dexpace::TransportError` itself | The **phase-level task**. `8a` raises it and does not define it; whichever sub-phase lands first writes it in `dexpace-core` |

---

## Prerequisites, and the independence this sub-phase must state

**`8a` depends on `8b` and `8c` for nothing, and neither depends on `8a`.** The charter's finding —
every phase-8 boundary is a convenience — is stated here in `8a`'s own words rather than inherited,
because the charter requires exactly that of each sub-phase design:

- **`8a` → `8b` is absent.** `dexpace-transport-net_http` is a synchronous transport. It posts no work,
  owns no executor, takes no `executor:` keyword and never constructs a `Dexpace::Async::Future`.
  Nothing in `8a`'s `lib/` names `dexpace-async-thread`, and nothing in its suite loads it. The one
  place the two gems meet is `Transport.async_over(net_http, executor: pool)`, which is **phase 2's
  code**, is the charter's convergence point 2, and belongs to whichever of `8a` and `8b` lands second.
- **`8b` → `8a` is absent.** `8b`'s pool posts an opaque block; what the block does is the caller's
  business, and phase 2's `FakeTransport` is a sufficient driver for every `ASYNC` clause `8b` owns.
  Nothing in `8b` needs a socket, a wire fixture or a real adapter.
- **`8a` → `8c` is absent, and it is the edge a reader is most likely to invent.** `8c` consumes two
  artifacts this document **assigns to `8a`** — §9.3's `TCPServer` fixture and `DEF-22`'s assertion
  protocol — but neither is a *design* dependency: `8c`'s design can be written in full before `8a`
  lands, and `8c`'s obligation is to add a driver rather than to wait. `R16` states which side `8a` is
  on and what `8c` inherits.
- **`8c` → `8a` is absent.** `async-http` brings its own reactor, connection pool and HTTP/1.1 and
  HTTP/2 stacks. It needs no `Net::HTTP` and no `Dexpace::Transport::NetHTTP` constant, and `NFR-2`'s
  budget would not permit it to declare one.
- **The one genuinely shared object is in neither's gem.** `Dexpace::TransportError < ::IOError` lives
  in `dexpace-core` and is the charter's phase-level task 1. `8a` raises it; if `8a` lands first, `8a`
  writes it, and if `8c` lands first, `8c` does. Either way it is reviewed in the phase-level pull
  request, not in a sub-phase's.

**An `8a` plan whose first task waits on anything from `8b` or `8c` has re-imposed a chain that does not
exist.** The recommended order `8a → 8b → 8c` is the charter's convenience and this document does not
re-argue it; if the order changes, exactly two sentences in `8a`'s plan change — the one that says it
wrote the harness and the one that says it wrote `Dexpace::TransportError`.

Every surface below was verified against the named phase's design on 2026-09-11. Nothing is implemented
yet in this repository — these are design commitments, and `8a` inherits them as such.

### From phase 0 — the gates that bite, and the two skeletons

Both of `8a`'s gems already have a skeleton: a gemspec declaring `dexpace-core` **and nothing else**
(`P0-9`), an entry file defining the namespace and `VERSION`, a `sig/` mirror, a `test/` tree and a
named Steep target. Six gates bite, and two of them bite `8a` first in the whole roadmap.

- **`gates:gemspec_audit`** — `dexpace-transport-net_http` becomes the first gem in the repository with
  **two** runtime dependencies (`dexpace-core` plus one third-party), which is the case the audit's
  `two_third_party` negative fixture was written against but has never seen positively.
  `dexpace-conformance` stays at one, **by design and not by accident** (§2.1 says so).
- **`gates:require_allowlist`, extended to adapters** — every `require` must be allowlisted, or under
  `dexpace/`, or the single third-party gem that adapter's gemspec declares. `require "net/http"` is
  permitted for `dexpace-transport-net_http` under the third clause, even though `net/http` is on core's
  **denylist** by name. **`require "socket"` in `dexpace-conformance` is permitted by none of the three**
  and is `R7`'s amendment.
- **`gates:clean_bundle`** — the isolation run gains a second and third scratch workspace. For
  `dexpace-transport-net_http` the `Gemfile` must be `gem "dexpace-core", path:` **plus**
  `gem "dexpace-transport-net_http", path:`. **Phase 0's `clean_bundle_check` writes only the second
  line**, and because every adapter gemspec declares `dexpace-core`
  (`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates.md:1319`) and `dexpace-core` is
  never published, `bundle install` fails to resolve — measured 2026-09-12 on Bundler 4.0.20:
  `Because every version of dexpace-foo depends on dexpace-core ~> 0.0 and dexpace-core ~> 0.0 could not
  be found in rubygems repository … version solving has failed`, resolving cleanly the moment the core
  path line is added. That is a **latent phase-0 defect affecting all five adapter rows of
  `CLEAN_BUNDLE_ENTRIES`**, not only this sub-phase's two, and `8a`'s plan fixes it in `tasks/gates.rake`
  because `8a` is the first sub-phase that needs the gate to pass on a gem with a real runtime
  dependency.
  **The smoke path stays phase 0's `require <entry>; check VERSION` — corrected in place 2026-09-12,
  with the correction stated.** An earlier revision of this bullet said the smoke path should be "a real
  request against a `TCPServer` the script starts … the run that proves `net-http` is declared rather
  than merely present". **That rationale does not hold**, and no smoke path however constructed can
  recover it: `net-http` is a *default* gem, and Bundler does not gate a default gem's availability by
  Gemfile declaration. Measured 2026-09-12 on Bundler 4.0.20 / Ruby 3.4.10 — a scratch workspace whose
  only gem's `lib/` does `require "net/http"` with **no** `net-http` dependency declared anywhere
  installed and ran to completion under `bundle exec`, resolving `Net::HTTP`. `net-http` is also not
  scheduled to leave the default set anywhere in 3.2–4.0, so the 4.0 column cannot recover it either.
  **`gates:require_allowlist`'s text scan is the gate that actually proves declaration** — it permits
  `require "net/http"` for this gem *because* the gemspec declares it, independent of what the
  interpreter would load anyway — and the real socket round trip lives where it belongs, in the
  adapter's own suite and in `dexpace-conformance`.
- **`gates:rbs_surface`** (`NFR-11`) — the scan asserts no constant outside `Dexpace::` and the stdlib
  allowlist appears in any public signature. `Net::HTTP`, `Net::HTTPResponse` and `Net::HTTPGenericRequest`
  are the three names most likely to leak into an RBS file by convenience, and `8a`'s `sig/` names none
  of them.
- **`gates:surface_snapshot`** and **`gates:sig_diff`** — both gems gain real public surface for the
  first time; the plan's final task regenerates both artifacts.
- **The five custom cops** — `Dexpace/SpdxHeader` on every new file; `Dexpace/NoThreadInterrupt`, which
  bans `Timeout.timeout`, `Thread#raise`, `Thread#kill`, `Thread#terminate` and `Thread#exit` and which
  `R1`'s teardown is written to satisfy without a waiver; `Dexpace/NoUriDefaultParser`, which the
  request-to-endpoint conversion touches on every call; `Dexpace/NoLocaleCaseFold`, which the header
  fold touches; `Dexpace/NoTimeParse`, which `8a` never reaches.

`rbs_collection.yaml` has an **empty `gems:` list** and phase 0's own comment says "net-http and
async-http with the transports in phase 8, and each adds its own row here then". `8a` adds `net-http`'s;
`8c` adds `async-http`'s; the two are not one edit.

### From phase 1

`Dexpace::HeaderSyntax` — `.trim(name)`, `.valid_name?`, `.validate_name!` (returns the trimmed name),
`.valid_outbound_value?`, `.validate_outbound_value!(value, name:)`, `.valid_inbound_value?`,
`.validate_inbound_value!(value, name:)`, `.escape(name)` — public API "precisely because a phase-8
adapter is a different gem and must be able to reach it". `Dexpace::Request` (`:method, :url, :headers,
:body`), `Response` (`:request, :protocol, :status, :reason, :headers, :body`), `Headers` with its
builder, `RequestOptions` (`:timeout, :max_retries, :tags`) with `EMPTY`, `MediaType.parse`,
`Status.of`, `Protocol.parse`, `Method`, `Dexpace::Model` (`.required!`, `#with`, `.own`) and
`Dexpace::InvalidArgumentError < ::ArgumentError`. Two phase-1 facts `8a` leans on directly:
**`Headers` re-runs `HTTP-17`/`HTTP-18`/`HTTP-19` over every stored name and value at construction**,
which is what makes `TRANSPORT-14`'s pre-filter necessary; and **`Dexpace::Error` is a module**, which
is what makes `Dexpace::TransportError < ::IOError` possible at all.

### From phase 2

`Dexpace::Transport`'s duck type and `.conforms?(object)` (`Registry.callable?(object, arity: 3)`);
`Dexpace::Transport.register(key, factory, core:)` with its **required** skew keyword and
`Dexpace::SeamError` on mismatch (`DEF-21`, `P2-7`); `Dexpace::Transport.install` and `.swap` for tests;
`Dexpace::Closeable` with `#initialize_closeable(owned:)`, `#owned?`, `#closed?`, `#close` and the
private `#release`, the latch mutex held across the flip and nothing else; `Dexpace.close_quietly`,
null-safe and rescuing `StandardError`; `Dexpace::Cancellation` with `#cancelled?`, the typed `#reason`,
`.any` and `#on_cancel`; `Dexpace::ClosedError`; `Dexpace::SeamError`. And the `SEAM-15` rule phase 2
already narrowed, quoted because `8a` adopts it rather than re-deciding it:

> **a transport that owns the resource it closed raises `Dexpace::ClosedError` from a later send.** A
> wrapper that only borrows closes nothing and stays usable, which is why both `SEAM-18` bridges answer
> `#close`, release nothing and keep working; raising there would break `XCUT-22`'s "the caller owns its
> lifecycle and may keep using it after the SDK component is closed". Phase 2 ships no owning transport,
> so it ships the error class and the rule and no raise site — phase 8's adapters are the first owners,
> and `dexpace-conformance` is where the raise is asserted.
> <sub>`docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md:3526-3533`</sub>

The charter's spec-forced boundary 17 leaves "whether a transport that only *borrows* a caller-supplied
client also raises" open and assigns it to `8a`. **It is not open: phase 2 decided it, in code, in a
module comment, and `8a` adopts it unchanged.** The charter's reading of §3.7 as silent is right; phase
2 is the document that is not silent, and a sub-phase re-deciding a rule a predecessor shipped is the
drift the one-row-per-ID convention exists to prevent. The consequence for `8a` is the two-entry-point
shape in *The object model* below.

### From phase 3a and 3b

`Dexpace::IO::BufferedSource.wrapping(io)` — **takes ownership**, accepts anything responding to
`#readpartial` or `#read`, validated by `respond_to?` and never `is_a?` — and `.over(chunked)`, which
**owns nothing** and pulls from `#each` on demand. `TypedReads`' whole vocabulary, of which `8a` uses
`#readpartial`, `#read`, `#read_into` and `#each`. `Dexpace::IO::MAX_MATERIALIZED_BYTES`.
`Dexpace::StreamError < ::IOError` and `Dexpace::EndOfStreamError < ::EOFError`, the second of which is
load-bearing: `IO.copy_stream` terminates cleanly on an `EOFError` **subclass** raised by a duck-typed
`#readpartial`, and without it "every streaming upload phase 8 performs would fail"
(`io-and-byte-streams/6eb5155f`'s companion finding). `Dexpace::Body` with `#each`, `#media_type`,
`#content_length` (exact or `-1`), `#replayable?`, `#source` and `#close`;
`Dexpace::ResponseBody.new(source:, media_type: nil, content_length: -1)` and its block form;
`Dexpace::FileBody` with `#path`, `#offset`, `#count` and deliberately **not** `#to_path` (`P3-17`);
`Dexpace::Response#close`, `#body_string` and `#body_bytes`.

**Two open items `8a` inherits unresolved and must not paper over.** **`OI-9`** — `BufferedSource.wrapping`
returns one byte per read and yields one-byte chunks, "and it will reach every transport phase 8 writes,
since `BufferedSource.wrapping` is how a response body is built". It reaches `8a`'s response path
exactly as the row predicts, and it does **not** reach `8a`'s request path, which uses `.over`. `8a`
does not fix it — it is phase 3a's code in an unexecuted plan — and the plan's first task re-reads the
row to see whether the one-line fix has landed. **`OI-7`** — the decode recipe — reaches
`Response#body_string`, which is 3b's, not `8a`'s.

### From phase 4b and 4c

`Dexpace::ProtocolError`, `Dexpace.each_cause`, `Dexpace::Suppressible` and `attach_suppressed` — none
of which `8a` raises or attaches, because no `TRANSPORT` requirement describes a two-failure path that
core does not already own. `PIPE-26`/`PIPE-27` (a pipeline is a transport, and closing one does not
close the transport) is why the seam is a duck type and why `8a` may not assume its caller is a
pipeline. **`OI-18` is open and its repair is named as phase 8's or a phase-2 amendment's**; it is about
`Transport.async_over`, which `8a` neither calls nor changes.

### From phase 5a, 5b and 5c

`Dexpace::Clock` with `#monotonic` (`Process.clock_gettime(Process::CLOCK_MONOTONIC)`, `CFG-16`) and the
cancellable queue wait, behind the injectable seam so tests control it. `Dexpace.configuration`,
`Configuration#string`/`#integer`/`#boolean`/`#duration` — **those four and no `#float`**, verified
against 5a's shipped source (`…-phase5a-configuration.md:2771-2802`); `#duration` is the reader `R3`
uses — and `Configuration::Keys`, whose existing `HTTP_PROXY`, `HTTPS_PROXY`
and `NO_PROXY` entries are the precedent `R3` leans on. `Instrumentation::Logger.build(sink:, context:,
redactor:, diagnostic_keys:)` and `Logger::NULL`; `Severity::VERBOSE`/`WARNING`; `Logger#enabled?`;
`Event`/`Event::INERT` with `#field`, `#event`, `#cause` and `#emit`; `Instrumentation.contain(logger,
event:) { }` and `Events::INSTRUMENTATION_PREFIX`. `HTTPTracer`'s five transport methods with their
argument lists fixed by 5c — `#request_url_resolved(context, url)`, `#connection_acquired(context, host,
port)`, `#request_sent(context, byte_count)`, `#response_headers_received(context, status, headers)`,
`#response_received(context, byte_count)` — which `R6` decides what to do with.

### From phase 6a

The obligation, quoted because it is the sharpest hand-off in the register:

> **every transport adapter MUST wrap a bare stdlib I/O or timeout error it lets escape in something
> answering `#retryable?`** … the obligation phase 8 inherits is "wrap, and default to retryable," not
> "wrap, and get the classification right by hand".
> <sub>`P6-4`, `docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry-design.md:1330`</sub>

Verified fact 7 is the list that obligation has to cover, and none of the families in it is an
`::IOError`.

### From phase 7

`7a` leaves `DEF-22`'s callable-plus-`Failure` shape alone for this phase deliberately, and records
`gems/dexpace-serde-json/test/support/serde_seam_assertions.rb` as **phase 9's** lift target, not
phase 8's — so `8a` writes a transport suite and no serde suite. `7b` requires nothing of a transport
beyond `Response#body` answering `#source`, which is 3b's contract. `7c` hands forward `PAGE-36`'s
per-call-options test (`8a`'s) and `Dexpace::Page::_Executor` (`8b`'s), and fixes one division `8a`
honours rather than re-decides: "a response the transport never delivered because a cancel won the race
is **the transport's** to release" (`PAGE-33`).

---

## The verified Ruby facts this sub-phase is built on

**One interpreter, and this document says so before it says anything else.** As with every predecessor,
only **Ruby 3.4.10** (`ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]`) is installed
on the authoring machine, against **`net-http` 0.6.0**, which
`/usr/lib/ruby/gems/3.4.0/specifications/default/net-http-0.6.0.gemspec` confirms is a **default gem**
on this interpreter — the claim §2.1's dependency table makes. **The 3.2 and 4.0 columns have not been
run for anything below.** `8a`'s plan installs both and re-runs every fact before any implementation
task begins.

Everything below was measured against a scripted local `TCPServer` — the same fixture shape §9.3
prescribes and `8a` ships — written to
`<scratchpad>/p8a/fixture.rb`, with the probes in `pump.rb`, `teardown.rb`, `fiber.rb`, `wire.rb`,
`verbose.rb`, `inbound.rb`, `ae.rb`, `retry.rb`, `conc.rb`, `proto.rb`, `cl.rb`, `cl2.rb`, `to.rb`,
`bstream.rb` and `final.rb`. Nothing was installed into the project or into the user's gem directory.

1. **`Net::HTTP` exposes no follow-redirects knob at all.**
   `(Net::HTTP.instance_methods + Net::HTTP.methods).grep(/redirect|follow/i)` is `[]`. `TRANSPORT-1`'s
   "the follow-redirects knob's default MUST be off" is therefore true of a knob that does not exist,
   and the conformance assertion still has a real subject: a scripted `302` with a `Location` came back
   as a `Net::HTTPFound` with the raw status, not the redirected target.
   *Command:* `ruby -e 'require "net/http"; p (Net::HTTP.instance_methods + Net::HTTP.methods).grep(/redirect|follow/i)'`.

2. **`Net::HTTP` has a built-in automatic retry, it is ON by default, and the charter's `OI-34` is
   confirmed from the source.** `Net::HTTP.new("x").max_retries` is **`1`**.
   `Net::HTTP#transport_request` (`/usr/lib/ruby/3.4.0/net/http.rb:2401-2446`) rescues
   `Net::ReadTimeout`, `IOError`, `EOFError`, `Errno::ECONNRESET`, `Errno::ECONNABORTED`, `Errno::EPIPE`,
   `Errno::ETIMEDOUT`, `OpenSSL::SSL::SSLError` and `Timeout::Error`, and retries when
   `count < max_retries && IDEMPOTENT_METHODS_.include?(req.method)`, where `IDEMPOTENT_METHODS_` is
   `["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE"]` — **including PUT and DELETE, both of which
   carry bodies**. The retry re-runs `req.exec`, so it re-writes the body. Two clauses of the same method
   are worth recording because they bound the hazard rather than removing it: `rescue Net::OpenTimeout;
   raise` means a connect timeout is **never** retried, and `count = max_retries` inside the
   `reading_body` block ("Don't restart in the middle of a download") means the retry window closes once
   the response head has been read. Neither helps the connect-and-head phase, which is where a cancel
   lands.
   *Commands:* `ruby -e 'require "net/http"; p Net::HTTP.new("x").max_retries'`;
   `ruby -e 'require "net/http"; p Net::HTTP.const_get(:IDEMPOTENT_METHODS_)'`;
   `sed -n '2401,2446p' /usr/lib/ruby/3.4.0/net/http.rb`.

3. **With the default `max_retries`, a cancellation delivered by closing the socket is swallowed and the
   call completes successfully.** A scripted server whose first connection hangs for 5 s and whose
   second answers `200`; a second thread calls `conn.finish` 250 ms in. At **`max_retries = 1` (the
   default) the call returned `200`** — the library caught the `IOError`, opened a new connection and
   re-sent. At **`max_retries = 0` it raised `IOError: stream closed in another thread`**. This is
   `OI-34`'s third consequence measured end to end rather than read out of a rescue list, and it makes
   `max_retries = 0` a requirement of `TRANSPORT-3` independently of `TRANSPORT-2` and `TRANSPORT-17`.
   *Command:* `ruby retry.rb`.

4. **`Net::HTTP` auto-stamps three headers at construction and a fourth at write time, recomputes
   `Content-Length`, deletes `Transfer-Encoding`, and honours a caller-set `Host` verbatim.** A `POST`
   carrying `Content-Length: 9999`, `Host: bogus.example`, `X-Pass: kept`, `Transfer-Encoding: chunked`,
   `Connection: close` and a 3-byte body reached the wire as:
   `Accept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3`, `Accept: */*`, `User-Agent: Ruby`,
   `Content-Length: 3` (recomputed), **`Host: bogus.example` (honoured)**, `X-Pass: kept` (preserved),
   `Connection: close` (preserved), `Content-Type: application/x-www-form-urlencoded` (stamped) — and
   **no `Transfer-Encoding`**, which `send_request_with_body` deletes. The three construction-time
   stamps come from `Net::HTTPGenericRequest#initialize`'s `self['Accept'] ||= '*/*'`,
   `self['User-Agent'] ||= 'Ruby'` and the `accept-encoding` branch; `self['Host'] ||= host` is where a
   caller-set `Host` wins, because `||=` does not overwrite.
   *Command:* `ruby wire.rb`.

5. **`supply_default_content_type` warns through `Warning.warn` under `-w`, and `set_body_internal`
   gives every body-permitted method a body — so a body-less `POST` warns too.**
   `Net::HTTPGenericRequest#supply_default_content_type` (`generic_request.rb:263`) is
   `warn 'net/http: Content-Type did not set; using application/x-www-form-urlencoded', uplevel: 1 if $VERBOSE`,
   and `#set_body_internal` is `self.body = '' if @body.nil? && @body_stream.nil? && @body_data.nil? &&
   request_body_permitted?`. Measured with `Warning.warn` overridden to raise, exactly as phase 0's
   shared test case does: **under `ruby -w` a `POST` with a body and no Content-Type raised**; without
   `-w` it did not. Both `send_request_with_body` and `send_request_with_body_stream` call it, so
   neither dispatch route escapes. A body-less `POST` reached the wire with `Content-Length: 0` **and**
   the stamped `Content-Type`. Consequence: the adapter sets an explicit `Content-Type` on every
   body-permitted method, body or not (`P8-4`), and a body-less `GET` is untouched because
   `request_body_permitted?` is false.
   *Commands:* `ruby verbose.rb`, `ruby -w verbose.rb`; `sed -n '/def supply_default_content_type/,/end/p'
   /usr/lib/ruby/3.4.0/net/http/generic_request.rb`.

6. **`Net::HTTP` is lenient about inbound headers in exactly the places `TRANSPORT-14` requires a drop,
   and `#to_hash` is the only faithful mapping source.** A scripted `520` carrying `X-Obs: caf\xE9`,
   `X-Ctl: a\x01b`, `X-B\xE9d: y`, `Content-Type: not a/;;media type` and two `Set-Cookie` lines came
   back with every value tagged `ASCII-8BIT` and **every byte preserved** — the obs-text value
   (`TRANSPORT-14`'s SHOULD, satisfied by the library), the control byte and the non-ASCII name (both of
   which the adapter must drop). Three access APIs, three different answers:
   `#to_hash` is `{"set-cookie" => ["a=1", "b=2"], "x-multi" => ["one", "two"], …}` — lowercased names,
   **arrays preserved**; `#[]` joins with `", "`; `#each_capitalized` joins *and* re-cases, rendering
   `Set-Cookie: a=1, b=2`, which is not what the server sent. So inbound mapping reads `#to_hash` and
   nothing else. `#http_version` was `"1.0"` for an `HTTP/1.0` response and `#message` carried the
   reason phrase verbatim.
   *Commands:* `ruby inbound.rb`, `ruby hdrs.rb`.

7. **None of the errors a transport must classify is an `::IOError`, and DNS failure is not
   `SocketError` by name.** Ancestries measured: `Net::OpenTimeout`, `Net::ReadTimeout` and
   `Net::WriteTimeout` are each `[…, Timeout::Error, RuntimeError, StandardError, Exception]`;
   `Net::HTTPHeaderSyntaxError` and `Net::HTTPBadResponse` are `[…, StandardError, Exception]`;
   `SocketError` is `[SocketError, StandardError, Exception]`; **`Socket::ResolutionError` is
   `[Socket::ResolutionError, SocketError, StandardError, Exception]`** — a subclass, so rescuing
   `SocketError` covers DNS; `Errno::ECONNREFUSED`/`ECONNRESET`/`EPIPE` are `[…, SystemCallError,
   StandardError, Exception]`; `OpenSSL::SSL::SSLError` is `[…, OpenSSL::OpenSSLError, StandardError,
   Exception]`; `Zlib::DataError` is `[…, Zlib::Error, StandardError, Exception]`. The **one** exception
   is `EOFError`, whose ancestry is `[EOFError, IOError, StandardError, Exception]` — already inside the
   family `XCUT-4` branch (b) names, which is also why phase 3a's `Dexpace::EndOfStreamError` inherits
   it. Live confirmations against real sockets: a dead port raised `Errno::ECONNREFUSED` in 0 ms; an
   unroutable address with `open_timeout: 0.05` raised `Net::OpenTimeout` in 61 ms; an unresolvable host
   raised `Socket::ResolutionError` in 10 ms; a slow server with `read_timeout: 0.2` raised
   `Net::ReadTimeout` in 202 ms.
   *Commands:* `ruby final.rb`; `ruby -e 'require "net/http"; require "socket"; …'`.

8. **`Net::HTTP`'s timeouts are floating-point seconds, `0` means *poll once* and `nil` means *no
   timeout*, and a running connection's `read_timeout` can be retightened mid-stream.** `open_timeout`,
   `read_timeout` and `write_timeout` all accepted `0.0005` and read back unchanged; `read_timeout:
   0.0005` against a slow server raised `Net::ReadTimeout` after **1 ms**, so truncation-to-zero is not
   merely impossible here, it would be the *opposite* failure: measured, `read_timeout: 0` raised
   `Net::ReadTimeout` immediately, while `read_timeout: nil` blocked until the socket was closed from
   another thread. And `c.read_timeout = 0.3` assigned **inside** a `read_body` block propagated onto the
   live socket — `Net::HTTP#read_timeout=` does `@socket.read_timeout = sec if @socket` — and the next
   read raised `Net::ReadTimeout` 313 ms later. That last measurement is what makes `R3`'s total-budget
   deadline implementable rather than aspirational.
   *Commands:* `ruby ae.rb`, `ruby to.rb`, `ruby final.rb`.

9. **A shared `Net::HTTP` under concurrent calls does not merely raise — it returns the wrong response
   to the wrong request.** One started `Net::HTTP`, `max_retries = 0`, eight threads × twenty requests
   against a server that echoes the request path into the body: **128 exceptions
   (`{IOError => 109, Errno::ECONNRESET => 6, EOFError => 9, Net::HTTPBadResponse => 4}`) and 26
   responses whose body named a different request's path.** The same 160 requests through a per-call
   `Net::HTTP.start` produced **zero exceptions and zero mismatches**. `TRANSPORT-29`'s conformance
   clause is "fire many concurrent sync and async calls through one transport and assert each response
   matches its own request", and this is that assertion failing on the shared client and passing on the
   per-call one. It makes design §3.2's per-call construction a correctness requirement rather than a
   style preference, and it is the measurement that answers `resource-management/4aca52f9`.
   *Command:* `ruby conc.rb`.

10. **The response-body problem, measured three ways, and the decisive fact is not the one the charter
    leads with.** Against a `TCPServer` that writes five body bytes, sleeps 400 ms and writes five more:
    - **`#request` with no block returned after 408 ms** with `res.body == "aaaaabbbbb"` — the whole body
      buffered before `#request` returned, which is `SEAM-11`'s "MUST NOT pre-buffer the body" and
      `TRANSPORT-25` both violated.
    - **The block form is no better if the block does not read**: `Net::HTTPResponse#reading_body` is
      `begin; yield; self.body; ensure; @socket = nil; end`, so after the block `res.body` was already
      `"aaaaabbbbb"` and a later `res.read_body` raised `IOError: Net::HTTPOK#read_body called twice`.
    - **A `Fiber` holding the block open works and is unusable anyway.** `Fiber.yield(chunk)` inside
      `read_body` delivered chunk 1 at 1 ms and chunk 2 at 401 ms. But `f.resume` **from a second thread
      raised `FiberError: fiber called across threads`**, while the same `f.resume` on the creating
      thread continued normally — so a fiber pump created on a `dexpace-async-thread` worker inside
      `Transport.async_over` cannot have its body read on the caller's thread, which is the charter's
      convergence point 2. Separately and as the charter reports, an abandoned fiber's `ensure` did not
      run after three `GC.start`s, and `Fiber#kill` **does** run it on 3.4.10 (its availability on the
      3.2 floor is **unverified** and this document asserts nothing about it).
    - **A producer `Thread` over a `Thread::SizedQueue(1)` works and is poppable from any thread.** The
      response head arrived at 4 ms, chunk 1 at 4 ms, chunk 2 at 403 ms; chunks are `ASCII-8BIT` and
      unfrozen; the producer thread was dead immediately after the drain.
    *Commands:* `ruby pump.rb`, `ruby fiber.rb`.

11. **The producer thread's teardown needs two actions, not one, and both were measured.** With the
    producer blocked in a socket read after one chunk: **closing the queue alone did nothing** — the
    producer was still alive 300 ms later, because it was blocked on `readpartial` and not on `push`.
    **`conn.finish` from the consumer thread woke it immediately** with `IOError: stream closed in
    another thread`, and it unwound through its `ensure`. In the full prototype — latch, close the
    queue, finish the connection, `Thread#join(2)` — **`#close` returned in 1 ms**, the producer was
    already dead, the scripted server observed the peer close, and a second `#close` was a no-op. The
    same prototype round-tripped a **4 MiB** body byte-exactly in 95 ms and left no extra threads alive.
    Two smaller facts from the same runs that decide the reader's shape: `String#replace` copies the
    source's encoding (a UTF-8 target becomes BINARY) while `String#clear` followed by `<<` does not, so
    the reader's `outbuf` handling is `#replace` and never `#clear`; and `Net::HTTP` normalises
    header-name case on the wire (`x-lower-name` → `X-Lower-Name`, `ETag` → `Etag`), which is why no
    conformance assertion checks the wire bytes for a caller's exact spelling.
    *Commands:* `ruby teardown.rb`, `ruby proto.rb`, `ruby hdrs.rb`.

12. **A malformed `Content-Length` does not prevent the response from materialising, and deleting it
    lets the body read.** This is the charter's `R4` premise inverted. Under the block form: the head
    was delivered in full — `res.code == "200"`, `res.to_hash` carrying both the malformed
    `Content-Type: not a/;;media type` and `Content-Length: abc` — and only `res.content_length` and
    `res.read_body` raised `Net::HTTPHeaderSyntaxError: wrong Content-Length format`. With
    `res.delete("content-length")` called before the read, `read_body` fell through to connection-close
    framing and returned `"hi"`. Four cases measured: non-numeric → length `-1`, body reads; a
    **negative** `Content-Length: -4` → `Integer()` accepts it, so the parse must reject anything that
    is not `/\A[0-9]+\z/` or the sentinel collides; a good length → `2`, body reads; chunked with no
    length → `-1`, body reads. A malformed `Content-Type` passes through untouched, and the **adapter**
    downgrades it to `nil` — `MediaType.parse` raises on it rather than returning `nil`, so the rescue is
    `ResponseMapper`'s (see `R4` step 3). **`TRANSPORT-27` is satisfiable whole.**
    *Commands:* `ruby cl.rb`, `ruby cl2.rb`.

13. **`Accept-Encoding` and transparent decompression are one switch, and the adapter owns it.**
    `Net::HTTPGenericRequest#initialize` sets `@decode_content = true` and stamps the gzip
    `Accept-Encoding` **only** when no `accept-encoding` or `range` key is present in `initheader`; and
    `#[]=` carries `@decode_content = false if key.downcase == 'accept-encoding'`. Measured:
    `req["Accept-Encoding"] = "identity"` flipped `decode_content` to `false`, and a following
    `req.delete("accept-encoding")` **left it `false`** while removing the header — so a request can go
    out with the caller's exact header set and no transparent decompression. With `decode_content` left
    `true` a gzip response came back with the body **already decompressed**, `Content-Encoding`
    **removed** and `Content-Length` **rewritten** to the decoded length (11 for `"hello world"`), which
    is not the faithful mapping `TRANSPORT-24` and `TRANSPORT-27` describe. `Accept` and `User-Agent`
    are plain `delete`s; a request stripped of all three reached the wire as
    `["GET / HTTP/1.1", "Host: 127.0.0.1:46603"]`.
    *Commands:* `ruby ae.rb`, `ruby inbound.rb`.

14. **A duck-typed `#readpartial` source drives `body_stream=` correctly in both framings, and the write
    destination is not a real `::IO`.** A source answering only `#readpartial(maxlen, outbuf)` and
    raising an `EOFError` **subclass** at the end wrote `abcdef` under `content_length = 6` and
    `5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n` under `Transfer-Encoding: chunked` — both exactly as
    `Net::HTTPGenericRequest#send_request_with_body_stream` prescribes, which is
    `IO.copy_stream(f, sock)` on one path and `IO.copy_stream(f, Chunker.new(sock))` on the other, and
    which raises `ArgumentError` unless a `Content-Length` or `chunked?` is set. Instrumenting
    `IO.copy_stream` showed **`dst=Net::BufferedIO`, `is_IO=false`** — so the kernel `sendfile` path is
    unreachable, which is `TRANSPORT-28`'s zero-copy clause and `DEF-3`'s `BODY-12` clause 2, measured
    rather than inferred.
    *Commands:* `ruby bstream.rb`, `ruby final.rb`, `ruby cl.rb`.

15. **`Net::HTTP` releases the connection when adaptation raises inside the block, and it uses
    `Timeout.timeout` internally for the connect phase.** An exception raised inside
    `c.request(req) { |res| raise }` propagated, and `Net::HTTP.start`'s own `ensure` left `conn.started?`
    `false` with the scripted server observing the peer close — so `TRANSPORT-22`'s "close the native
    response before propagating" is satisfied by the library **for a failure inside the block**, and is
    `8a`'s own obligation for a failure *after* the head crosses the queue, which is where this adapter
    adapts. Separately, `/usr/lib/ruby/3.4.0/net/http.rb:1657` is
    `s = Timeout.timeout(@open_timeout, Net::OpenTimeout) { TCPSocket.open(...) }` — the primitive §8.3
    bans, used by the library the adapter depends on. It is outside the cop's scan (which reads this
    repository's `lib/`) and outside the hazard the ban is about (no SDK `ensure` holds a resource
    during connect), and it is recorded below as a proposed register item rather than silently accepted.
    *Commands:* `ruby final.rb`; `sed -n '1645,1665p' /usr/lib/ruby/3.4.0/net/http.rb`.

16. **`Net::HTTP`'s TLS defaults are `OpenSSL::SSL::SSLContext#set_params`' defaults, and the adapter
    must set nothing to get verification.** A fresh `Net::HTTP` with `use_ssl = true` reports
    `verify_mode` `nil`, `ca_file` `nil` and `min_version` `nil`; `Net::HTTP#connect` copies only
    **non-nil** ivars into `ssl_parameters` and then calls `@ssl_context.set_params(ssl_parameters)`,
    and `OpenSSL::SSL::SSLContext.new.set_params({})` yields **`verify_mode == 1` (`VERIFY_PEER`) and
    `verify_hostname == true`**. `OpenSSL::SSL::SSLContext::DEFAULT_PARAMS` on this build is
    `{verify_mode: 1, verify_hostname: true, options: 2147614800}`. So certificate and hostname
    verification are on by default, and an adapter that assigns nothing cannot weaken them.
    *Commands:* `ruby -e 'require "net/http"; require "openssl"; …'`;
    `sed -n '1620,1650p' /usr/lib/ruby/3.4.0/net/http.rb`.

17. **`minitest` is not a default gem on this interpreter, and `socket` is not a gem at all.**
    `Gem::Specification.find_by_name("minitest").default_gem?` is `false` and the resolved gem directory
    is under the user's own `~/.local/share/gem`, not the interpreter's; `Gem::BUNDLED_GEMS::SINCE` does
    not name it either, because the table lists only gems that *became* bundled at a known version.
    Design §9.3's "it ships with the interpreter as a default gem" is therefore imprecise — minitest is
    a **bundled** gem, available with the interpreter but requiring a `Gemfile` entry under Bundler —
    and the conclusion §9.3 draws from it survives unchanged. `socket`, by contrast, resolves to
    `/usr/lib/ruby/3.4.0/x86_64-linux/socket.so` with **no gemspec at all**: it is non-gemified stdlib,
    so it can never migrate to the bundled set. Both facts bear on `R7`.
    *Commands:* `ruby -e 'p Gem::Specification.find_by_name("minitest").default_gem?'`;
    `ruby -e 'require "socket"; p $LOADED_FEATURES.grep(/socket/).first'`;
    `ls /usr/lib/ruby/gems/3.4.0/specifications/default/`.

**Three things this document could not verify and does not assert.** (i) **Every fact above on 3.2.11
and 4.0.6** — the plan's first task installs both and re-runs all seventeen. (ii) **`Fiber#kill`'s
availability on Ruby 3.2**, which `R1` deliberately does not turn on. (iii) **Whether `rbs` ships
signatures for `net-http`** and therefore whether `8a`'s `rbs_collection.yaml` row or a `Steepfile`
`library "net-http"` line is the right spelling — `rbs` is not installed on this machine, and it is an
open question for the plan rather than a design decision.

---

## `R1` — how a `Net::HTTP` response body outlives `#call` without leaking a socket

**Decision: a per-response producer `Thread` over a `Thread::SizedQueue(1)`, drained through a
`#readpartial`-shaped reader that `Dexpace::IO::BufferedSource.wrapping` owns and closes. Not a
`Fiber`, not `Fiber#kill`, and not a buffering deviation.** `P8-1`.

The charter states the problem exactly and leaves the mechanism open:

> `#request` without a block buffers the entire body (`SEAM-11`'s "MUST NOT pre-buffer" and
> `TRANSPORT-25` both violated); the block form buffers too unless the block reads; a `Fiber` holding
> the block open delivers chunks lazily and correctly but **never runs its `ensure` when abandoned**,
> and `Fiber#kill`'s availability on the 3.2 floor is unverified.

### The decisive fact is not abandonment

The charter's objection to a fiber pump is that an abandoned fiber leaks the connection. That is true
(verified fact 10) and it is not the objection that settles it, because **every** candidate leaks a
connection when nobody closes the response — a thread pump leaks a thread *and* a connection — and
`TRANSPORT-25` and `SEAM-11` both say in as many words that "the caller owns closing the response". A
mechanism is not disqualified by failing to clean up after a caller who broke the contract; that is what
the contract is for.

What disqualifies the fiber is smaller and harder: **`Fiber#resume` from a thread other than the one
that created the fiber raises `FiberError: fiber called across threads`** (verified fact 10). Two of
this phase's own obligations cross that line.

- **`Transport.async_over(net_http_transport, executor: thread_pool)`** — the charter's convergence
  point 2, and "where `ASYNC-1`, `ASYNC-2`, `ASYNC-5`, `ASYNC-14`, `ASYNC-19` and `ASYNC-20` first meet
  a **real socket**". Phase 2's `Bridge::AsyncOver` posts `transport.call(…)` to the executor; the
  worker thread runs `#call` and therefore creates the fiber; the future delivers the `Dexpace::Response`
  to whatever thread is waiting on it. The first `response.body.source.read` on that thread raises
  `FiberError`, and it raises it from inside `Dexpace::IO::BufferedSource`, several frames from anything
  a reader would connect to a fiber.
- **`TRANSPORT-29`** — "all per-request state MUST be confined to local scope or the returned response
  graph". A fiber in the returned response graph is state that is confined to a *thread* as well, which
  is a restriction the requirement does not license and no other adapter has.

A `Thread::SizedQueue` has neither problem: it is popped from any thread by construction, and the
producer's own thread is an implementation detail of the response graph rather than a constraint on it.

### The mechanism, stated so it is checkable

`Dexpace::Transport::NetHTTP::ResponsePump` (a `private_constant`) owns three things — the producer
`Thread`, the `Thread::SizedQueue(1)`, and the `Net::HTTP` the producer started — and exposes exactly
the surface `BufferedSource.wrapping` needs plus `#close`.

1. **`#call` constructs the pump and blocks on one `pop`.** The producer opens the connection inside
   `Net::HTTP.start(host, port, …) { |c| … }`, sets `c.max_retries = 0`, and calls
   `c.request(native) { |res| queue.push([:head, res]); res.read_body { |chunk| queue.push([:chunk, chunk]) } }`.
   The first `pop` yields `[:head, res]` **or** `[:error, e]`; a failure before the head is re-raised on
   the caller's thread with `raise error, cause: nil` (`pipeline/f02559b9`), because the pump is
   *carrying* an error rather than rescuing one, and `$!` on the consumer's thread may be the caller's.
2. **The head is adapted on the caller's thread**, not the producer's, so every `Dexpace::` object in
   the returned graph is built where the caller can see the failure. If adaptation raises, `TRANSPORT-22`
   requires the native response to be closed before propagating: the pump is closed through
   `Dexpace.close_quietly` in an `ensure` and the adaptation error propagates alone. §3.7 names this
   call site.
3. **The body is a `Dexpace::ResponseBody` over `BufferedSource.wrapping(pump)`.** 3a's factory takes
   ownership and accepts anything answering `#readpartial` or `#read`; the pump answers `#readpartial`
   and `#close`. So `Response#close → ResponseBody#close → BufferedSource#close → pump#close` is the
   cascade `TRANSPORT-25` requires, and every link in it is a phase-2-or-3 contract this sub-phase
   neither writes nor widens.
4. **`ResponsePump#readpartial(maxlen, outbuf = nil)`** pops when its residue is empty, raises
   `Dexpace::EndOfStreamError` (`< ::EOFError`, 3a's) at end of stream, re-raises a carried producer
   failure, and writes into `outbuf` with **`String#replace`** so the destination carries BINARY rather
   than whatever encoding the caller's buffer had (verified fact 11). It is a `Dexpace::ClosedError`
   after close, per 3a's own use-after-close rule.
5. **`ResponsePump#close` is the latch plus two wakeups plus a bounded join**, in this order and for
   measured reasons (verified fact 11):
   - flip `@closed` under a `Thread::Mutex` **held across the flip and nothing else**
     (`concurrency-and-async/c0fab747`, `/ee54cb68`); everyone but the winner returns immediately;
   - `queue.close` — wakes a producer blocked on `push` with `ClosedQueueError`;
   - `connection.finish` — wakes a producer blocked in `readpartial` with `IOError: stream closed in
     another thread`, which is the mechanism §10.5 names ("`Completer#on_cancel` lets an adapter shorten
     that by closing the socket under the read") and which **only works because `max_retries = 0`**,
     since `IOError` is on the library's own retry rescue list (verified facts 2 and 3);
   - `thread.join(JOIN_DEADLINE_SECONDS)` — **bounded**, never unbounded, so `XCUT-13`'s and
     `TRANSPORT-16`'s "no unbounded await" holds. Measured, the join returned in 1 ms.
   Both wakeups are wrapped so a close cannot raise over a primary failure, and `#close` returns `nil`.
6. **The producer's own `ensure` closes the queue** (`resource-management/346deaec`: release in
   `ensure`, never in `rescue`), so a consumer blocked on `pop` when the producer dies for any reason
   gets `nil` and ends rather than hanging.
7. **Check-after-resume is honoured** (`concurrency-and-async/611b9392`): the producer re-reads the
   closed latch after every `push` returns and after `read_body` yields, and stops producing rather than
   delivering into a queue nobody will drain.

### What this costs, stated rather than hidden

**One thread per in-flight response**, alive from the moment the head is delivered until the body is
drained or the response is closed. A synchronous transport already has one caller thread per in-flight
call, so the steady-state cost is a doubling of thread count under concurrency, not an unbounded growth:
the pump count is bounded by the caller's own concurrency exactly as the connection count is
(`resource-management/4aca52f9`, answered above). A response nobody closes and nobody drains strands one
thread and one connection; that is the documented consequence of breaking
`SEAM-11`'s "the caller owns reading and closing it", it is recorded in the adapter's YARD, and
`resource-management/b7587eb7`'s "track every spawned thread … and join it in a teardown path that is
guaranteed to run" is satisfied by the thread being reachable from the object that owns `#close` rather
than by a registry the SDK sweeps.

**`TRANSPORT-19`'s observable behaviour, since `R1` decides it.** The requirement is about an abandoned
**streaming-body subscription** whose producer must be unblocked "so no writer thread or file handle is
stranded", with idempotent teardown. On this adapter the *outbound* subscription has no separate
producer at all — `IO.copy_stream(source, sock)` runs on the calling thread inside `#call` — so that
half has no antecedent, and the row says so. The *inbound* pump is a producer this port creates, and it
is where the rule is paid: closing an undrained response unblocks the producer in 1 ms and the teardown
is idempotent through the same latch. `TRANSPORT-19` is satisfied against the producer the port
actually has, and the row states which one.

### Three alternatives, considered and rejected

- **A `Fiber` pump, with `#close` resuming it with a stop sentinel.** This is better than the charter's
  framing suggests — a stop-sentinel resume runs the `ensure` deterministically with no `Fiber#kill` and
  no 3.2 question — and it still loses, on the cross-thread resume above. Named here rather than
  omitted, because a later reader who notices that abandonment is solvable will otherwise re-open a
  decision that turns on something else.
- **`Fiber#kill`.** Runs the `ensure` on 3.4.10 (verified), is absent from phase 0's
  `Dexpace/NoThreadInterrupt` list, and raises at the fiber's own suspension point rather than at an
  arbitrary instruction — so the charter is right that §8.3's rationale does not obviously reach it. It
  is rejected anyway and for a reason that is not the rationale: it does not address the cross-thread
  problem, and its availability on the 3.2 floor is unverified. Taking a primitive whose *presence* on
  the floor is unknown to solve a problem it does not solve is two risks for no gain.
- **Admitting that this adapter buffers.** Rejected because `SEAM-11`'s no-pre-buffering clause and
  `TRANSPORT-25` are both MUSTs with a mechanism available, and because the whole reason
  `dexpace-transport-net_http` ships in the MVP is that it has "streaming in both directions" (§2.1). A
  deviation is for a requirement with no available mechanism; this one has one, and it round-tripped
  4 MiB byte-exactly in 95 ms.

`P8-1` records the departure from design §3.2's prescribed construction; `OI-35` — the charter's — is
the row that records the chapter is wrong rather than merely silent, and `8a` does not file a second.

---

## `R2` — the outbound header policy, against a library that stamps four headers and honours one it should not

**Decision: the adapter builds the native request from an empty header set, deletes all three
construction-time stamps, copies exactly the caller's headers minus a named managed set, and sets
`Content-Type`, framing and `Accept-Encoding` itself. `decode_content` is turned off unconditionally.**
`P8-2`, `P8-3`, `P8-4`.

The dispatch path, in order, is the whole answer:

1. **Wire-boundary re-validation (`DEF-25`).** Every outbound name through
   `Dexpace::HeaderSyntax.validate_name!` and every outbound value through `.validate_outbound_value!`,
   **before anything is copied**. A violation raises `Dexpace::InvalidArgumentError` naming the header —
   it is not a drop, and charter boundary 11 forbids merging it with `TRANSPORT-12`'s per-header drop.
   This runs even though `Dexpace::Headers` validated at construction, because `HTTP-2`'s constructor
   privacy is bypassable (§10.10, `P8` there) and this is the mitigation §4 names. Measured relevance:
   `Net::HTTP#[]=` rejects a CR/LF *value* with `ArgumentError` but writes `Bad name: v` — an invalid
   HTTP/1.1 field name — straight to the wire (verified facts 4 and 5 of the charter, re-measured here),
   so the name half of the re-validation is the half with no native backstop.
2. **The managed drop set (`TRANSPORT-11`, `P8-13`).** A frozen, folded
   `Dexpace::Transport::NetHTTP::MANAGED_HEADERS` — public, because a conformance assertion and a caller
   debugging a vanished header both need it — holding
   **`host`, `content-length`, `transfer-encoding`, `connection`, `keep-alive`, `proxy-connection`,
   `te`, `trailer`, `upgrade`, `expect`**. **These ten names are a shared transport contract and are
   stated once in the charter** — `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`,
   *Shared transport contracts*, item 1 — because `8c`'s adapter drops the same ten under a differently
   named constant and a conformance assertion runs unchanged against both. `proxy-authorization` is in
   neither set, for the reason open question 3 below gives. The requirement's minimum is the first three; the rest are
   RFC 9110 §7.6.1 hop-by-hop headers, and the requirement's own text invites the extension ("plus any
   the native client rejects outright … The exact drop set is transport-specific"). Two of the seven
   additions carry their own reason rather than the general one: **`expect`**, because
   `Net::HTTP#continue_timeout` is `nil` by default and `wait_for_continue` therefore never runs, so a
   caller-set `Expect: 100-continue` against a server that waits would hang until the read deadline; and
   **`connection`**, because this adapter builds and closes a `Net::HTTP` per call and a caller-set
   `Connection` either agrees with what the adapter already does or contradicts it. Each drop is logged
   once at `Severity::VERBOSE` through the logger `R6` wires, which is `TRANSPORT-11`'s "SHOULD
   additionally log each drop at verbose" — **through the shared event name and field pair the charter's
   *Shared transport contracts* item 2 fixes**: `Dexpace::Instrumentation.contain(logger, event:
   Events::TRANSPORT_HEADER_DROPPED) { logger.event(Severity::VERBOSE).event(
   Events::TRANSPORT_HEADER_DROPPED).field("header", name).field("reason", …).emit }`. **Corrected in
   place 2026-09-12**: an earlier revision emitted a bare literal `"transport.header.dropped"` contained
   under `Events::INSTRUMENTATION_LOG` with a `Symbol` `:header` key and no reason field, which is a
   second spelling of a record `8c` emits under a core-owned constant, and one assertion cannot read a
   drop from both adapters if the two disagree about the event's name. `Events::TRANSPORT_HEADER_DROPPED
   = "http.transport.header_dropped"` is one new frozen `String` in `dexpace-core`, added by whichever
   sub-phase lands first and a no-op confirmation for the other.
   **`Host` is the one that needs saying out loud**: `Net::HTTPGenericRequest#initialize` does
   `self['Host'] ||= host`, so a caller-set `Host` that reached the native request would be *honoured*
   verbatim (verified fact 4) and the framing header the requirement names first would be the one the
   adapter failed to manage. Because the caller's `Host` is never copied, `||=` finds the slot empty and
   the library derives the correct value from the URL.
3. **The three auto-stamps.** `Accept`, `User-Agent` and `Accept-Encoding` are set by
   `Net::HTTPGenericRequest#initialize` and are **all three deleted** (verified fact 13: a stripped
   request reached the wire as `GET / HTTP/1.1` plus `Host` alone). The SDK sends the caller's header
   set, not a header set the caller never wrote. A caller who wants `User-Agent: Ruby` sets it; a caller
   who wants none gets none, which is the only behaviour compatible with `HTTP-6`'s wire model being the
   whole truth about a request. `P8-2`.
4. **`Accept-Encoding` and `decode_content` are one switch and it is set to off.** The order is
   load-bearing and measured (verified fact 13): assign `req["Accept-Encoding"] = value` — which flips
   `@decode_content` to `false` as a side effect of `#[]=` — and then `delete` it when the caller set
   none, which leaves the flag `false`. With `decode_content` left at its default the transport hands
   back a body that has been **silently decompressed**, with `Content-Encoding` removed and
   `Content-Length` rewritten to the decoded length. That is not the response the server sent, and
   `TRANSPORT-24`'s "surfaced faithfully" and `TRANSPORT-25`'s byte-exact round trip both describe the
   one that was. The cost — a caller who sets no `Accept-Encoding` now gets no compression — is real, is
   documented at the adapter, and is the caller's to reverse with one header. `P8-3`.
5. **`Content-Type` is always set on a body-permitted method** (`TRANSPORT-10`, and verified fact 5's
   warnings-fatal consequence). The precedence is exactly the requirement's: the caller's explicit
   header wins, matched **case-insensitively** through `Dexpace::HeaderName`'s fold and never through a
   locale-sensitive `downcase` (`Dexpace/NoLocaleCaseFold`); failing that the body's own
   `#media_type`; failing that `Dexpace::Transport::NetHTTP::DEFAULT_CONTENT_TYPE`, which is
   **`application/octet-stream`** — RFC 9110's own default for a payload of unknown type, and the one
   value that is not a claim about the bytes. Leaving the field to `supply_default_content_type` would
   put `application/x-www-form-urlencoded` on the wire, which is a *lie* a server will act on, and would
   fail this repository's build. `P8-4`.
6. **Framing is derived from the body and never copied.** `Content-Length` from
   `body.content_length` when it is non-negative; `Transfer-Encoding: chunked` when it is `-1`;
   neither when there is no body. `send_request_with_body_stream` raises `ArgumentError` unless one of
   the two is present (verified fact 14), so the branch is total by construction.
7. **The body is dispatched as `req.body_stream = Dexpace::IO::BufferedSource.over(body)`, never as
   `req.body =`.** One route for every body variant; `.over` owns nothing, pulls from `#each` on demand
   so no read-ahead accumulates, and is the factory `OI-9`'s throughput defect does **not** reach.
   `IO.copy_stream` drives it through `#readpartial` and terminates on `Dexpace::EndOfStreamError`
   because that class inherits `::EOFError` — 3a's decision, load-bearing here.
8. **A body-less request on a body-permitted method still needs the `Content-Type`**, because
   `#set_body_internal` assigns `body = ''` and routes through `send_request_with_body` (verified fact
   5). `TRANSPORT-26`'s "substitute a zero-length body with `Content-Length: 0`" is therefore satisfied
   by the library; the adapter's contribution is the header that stops the warning and the lie.

**What the caller sees, stated once**: the wire request is the caller's `Dexpace::Headers` minus
`MANAGED_HEADERS`, plus `Host` and the framing header derived by the transport, plus a `Content-Type`
derived by the precedence above. Nothing else. `TRANSPORT-11`'s conformance clause — "send a bogus
Content-Length/Host plus a pass-through header; assert the framing headers are recomputed and the
pass-through survives" — is an assertion over exactly that sentence.

---

## `R3` — what one `RequestOptions#timeout` means across three `Net::HTTP` knobs

**Decision: it is a total per-call budget, carried as a monotonic deadline and refreshed into all three
knobs — including mid-stream, which is measurable and measured.** `P8-5`.

`TRANSPORT-5` requires a per-call override to apply "to that single call, overriding the transport's
configured default for that call only", and its conformance clause is "two concurrent calls with
different per-call timeouts; assert **each is bounded by its own value**". "Bounded by its own value" is
a statement about the *call*, not about one syscall — and a per-operation reading makes the clause
false: with one value assigned to all three knobs, a call with `timeout: 5` can legitimately take
5 s connecting, 5 s writing and 5 s per read, without bound, which is exactly the failure
`resource-management/ed29d0f5` warns about from the other side ("a global timeout does not bound the
total blocking time of a batch of sequential calls"). The total-budget reading is the only one under
which the requirement's own assertion passes.

**The mechanism is §8.3's, literally.** Deadlines are explicit values propagated to
`open_timeout`/`read_timeout`/`write_timeout`; nothing is an ambient interrupt and
`Dexpace/NoThreadInterrupt` has nothing to bite.

- At `#call` entry the adapter computes `deadline = clock.monotonic + budget`, where `clock` is phase
  5a's injectable `Dexpace::Clock` (`CFG-15`, `CFG-16` — `Process.clock_gettime(Process::CLOCK_MONOTONIC)`,
  never `Time.now`).
- `open_timeout` and `write_timeout` are assigned `remaining` before the connection is started.
- `read_timeout` is assigned `remaining` before the request and **reassigned after every chunk the pump
  receives**. Verified fact 8: `Net::HTTP#read_timeout=` does `@socket.read_timeout = sec if @socket`,
  and a value assigned inside a `read_body` block took effect on the very next read. Without that
  refresh, a trickling body of *n* chunks would get *n* × the budget.
- **`remaining <= 0` raises before touching the socket**, as a `Dexpace::TransportError` wrapping the
  phase the budget expired in. A budget that has just expired must not be handed to `Net::HTTP` as `0`,
  because verified fact 8 shows `0` means *poll once* and would produce a confusing immediate
  `Net::ReadTimeout` from a different place.
- **`TRANSPORT-6`'s clamp**: a strictly positive `remaining` below
  `Dexpace::Transport::NetHTTP::MIN_TIMEOUT_SECONDS` is clamped **up** to it. The requirement's
  antecedent is doubly absent here — the knobs are floats down to `0.0005` and zero is not "no timeout"
  — and `transport-adapter/deccd514` requires the clamp be implemented anyway for adapters over coarser
  APIs. It is one `[remaining, MIN].max` and it carries the ID in a comment.

**Three tiers, and the configured one is a named setting rather than a literal.**
`resource-management/d1f16cad` is explicit that phase 8's transports take their configured defaults
"from phase 5's layered configuration chain as named settings rather than literals — which is
`2b9040ef` satisfied by a configuration key instead of a constant". So:

| Tier | Source | Wins over |
|---|---|---|
| per call | `options.timeout` (a `Float` of seconds, phase 1; `nil` means "use the default") | everything |
| per transport | `NetHTTP.build(timeout:)` | the configured default |
| configured | `Dexpace.configuration.duration(Configuration::Keys::REQUEST_TIMEOUT, default: DEFAULT_TIMEOUT_SECONDS)` | the constant |

**`#duration`, not `#float` — corrected in place 2026-09-12, with the correction stated.** An earlier
revision of this table wrote `Dexpace.configuration.float(…)`. **Phase 5a ships no `#float`**: its
`Configuration` defines exactly `#string`, `#raw_property`, `#integer`, `#boolean` and `#duration`
(`docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration.md:2771-2802`), and `#duration` is the
one that already returns `Float` **seconds** — through `ConfigParsers.parse_duration` (`:2087-2130`),
which returns the `default` unmodified when nothing is configured, which is exactly what this tier's
default path needs. The behavioural consequence, stated rather than hidden: `parse_duration`'s own
grammar (`CFG-7`, `P5-4`) treats a **bare number as milliseconds**, so `REQUEST_TIMEOUT=30` is thirty
*milliseconds* and a caller who wants thirty seconds writes `30s` or `PT30S`. That is
`Configuration::Keys`' existing convention for every duration-shaped setting in this repository and not
a precedent this sub-phase invents; it is documented in `Adapter`'s YARD. Found by this design's own
plan while writing Task 14, verified against 5a's shipped source rather than inferred.

**`Configuration::Keys::REQUEST_TIMEOUT` is one new frozen `String` in `dexpace-core`, and the precedent
is in the same constant.** `Keys` already holds `HTTP_PROXY`, `HTTPS_PROXY` and `NO_PROXY` — three names
no core file reads and only a transport will — so a transport-facing key there is the established shape,
not a new one; and `SEAM-2`'s "core never names a concrete implementation" is untouched, because
`"REQUEST_TIMEOUT"` names a setting and not an adapter. One key and not three (`CONNECT_`/`READ_`/`WRITE_`)
follows from the budget decision: there is one number to configure. It is added in the change that reads
it, per 5a's own rule that a key constant with no reader is `NFR-4`-locked surface nothing exercises, and
`8c` reads the same key rather than declaring a second spelling.

**On a borrowing transport a per-call override raises.** `TRANSPORT-5` says the override must apply
"leaving the shared native client untouched", and on a caller-supplied `Net::HTTP` there is no way to do
both — assigning the knob mutates the caller's object, which `XCUT-22` forbids. Silently ignoring it is
worse than refusing it: `SEAM-11` sanctions an options-ignoring transport, but a transport that honours
options on one construction and drops them on another is a silent wrong answer in the exact place
`PAGE-36` exists to prevent ("otherwise a caller's timeout/retry policy silently fails to govern pages
2..N"). So a non-`nil` `options.timeout` against a borrowing transport raises
`Dexpace::InvalidArgumentError` naming both the requirement and the fix. `P8-6`.

---

## `R4` — `TRANSPORT-27`'s unknown-length sentinel

**Decision: `TRANSPORT-27` is satisfied whole. The charter's premise that half of it is unreachable is
wrong, and the correction is measured.** No deviation row, and the ID is not ticked without the row
below saying how.

The charter's `R4` reads:

> Verified fact 12: a non-numeric `Content-Length` raises `Net::HTTPHeaderSyntaxError` out of `#request`
> itself, so there is no response to downgrade … `8a` decides between a deviation row naming the
> unreachable clause, a pre-parse that intercepts before `Net::HTTP` does … and a statement that the
> requirement is a SHOULD the adapter partly declines.

The measurement it rests on was taken **without a block**, and this adapter uses one for `R1`'s reasons
anyway. Under the block form (verified fact 12) the response head is delivered in full before anything
parses the length: `res.code`, `res.message` and `res.to_hash` — carrying both the malformed
`Content-Type: not a/;;media type` and the malformed `Content-Length: abc` — are all available inside the
block. `Net::HTTPHeaderSyntaxError` is raised later, by `Net::HTTPResponse#content_length`, which
`read_body_0` calls to choose its framing.

So the adapter never calls `res.content_length` and never lets `read_body` call it either:

1. **Map the length from the raw header.** `raw = res.to_hash["content-length"]&.first`; the SDK length
   is `raw` when it matches `/\A[0-9]+\z/`, and **`-1` otherwise** — absent, non-numeric, negative or
   multi-valued. The regexp rather than `Integer(raw, 10, exception: false)` is not fussiness: measured,
   `Integer("-4", 10, exception: false)` returns `-4`, which would collide with `BODY-35`'s and
   `TRANSPORT-27`'s unknown-length sentinel and report a negative length as a *known* one.
2. **Delete the header from the native response when the length is unknown**, before the pump reads the
   body. `Net::HTTPResponse` includes `Net::HTTPHeader`, so `res.delete("content-length")` is available;
   with it gone, `read_body_0` finds no length and no chunked encoding and falls through to
   connection-close framing. Measured over four cases: non-numeric → length `-1` and body reads;
   `-4` → `-1` and body reads; a good length → exact and body reads; chunked with no length → `-1` and
   body reads.
3. **The media type is downgraded by the adapter, because `MediaType.parse` *raises* — corrected in
   place 2026-09-12, with the correction stated.** An earlier revision of this section said phase 1's
   `MediaType.parse` "already downgrades" a malformed value to `nil`. **It does not.** Phase 1's shipped
   parser raises `Dexpace::InvalidArgumentError` whenever
   `slash.empty? || type.empty? || subtype.empty? || subtype.include?("/")`
   (`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model.md:2168-2183`), and this section's own
   example, `"not a/;;media type"`, hits exactly that branch: `split_parameters` cuts at the first `;`,
   the essence is `"not a/"`, and `partition("/")` yields `type = "not a"`, `subtype = ""`. It also
   raises on `nil`, through `Model.required!`. So `ResponseMapper` owns the downgrade:
   `raw = native.to_hash["content-type"]&.first`; `nil` when the header is absent; otherwise
   `MediaType.parse(raw)` inside a `rescue Dexpace::InvalidArgumentError; nil`. The malformed
   `Content-Type` still passes through `Net::HTTP` untouched (verified fact 12) and still reaches the
   caller verbatim in `Dexpace::Headers` — only the *interpretation* becomes `nil`. `TRANSPORT-27`'s
   "downgraded to 'no media type' rather than failing the response" is then satisfied by the adapter
   supplying the `nil` and the `Response::Builder` accepting it, because `body` and its media type are
   optional. Found by this design's own plan while writing Task 17, verified against phase 1's shipped
   source rather than inferred.

**The raw header still reaches the caller.** Deleting `content-length` from the *native* response happens
after `#to_hash` has been copied, so `Dexpace::Headers` carries the wire value the server sent and the
SDK's `-1` is the *interpretation*, not a rewrite. That is the same separation `TRANSPORT-24` draws for
status codes.

`TRANSPORT-27`'s conformance clause — "a malformed Content-Type and non-numeric Content-Length still let
the body read, with null media type and unknown length" — is one assertion in `dexpace-conformance` and
it passes. The row states the mechanism, because a reader who meets `res.content_length` in a stack trace
later will otherwise re-introduce it.

---

## `R5` — `TRANSPORT-28`'s reachable half, and what that does to `DEF-3`

**Decision: the reachable halves are implemented, cost no adapter code at all, and the row is
*partially satisfied* rather than ⏳ whole. `DEF-3`'s `BODY-12` clause 2 is marked UNSCHEDULED with phase
8a named.**

`TRANSPORT-28` is one SHOULD with an embedded MUST and three separable claims:

| Clause | Disposition | Why |
|---|---|---|
| "MUST treat a file body as replayable so it can be re-sent" | **satisfied** | `Dexpace::FileBody#replayable?` is `true` (3b) and `#write_to` opens a **fresh** handle per write, so a retry or a redirect re-sends identical bytes. The adapter asks `#replayable?` and never caches |
| "honoring start position and byte count" | **satisfied** | `FileBody#write_to(sink)` is `::IO.copy_stream(handle, sink, count, offset)` (3b, verified there on all three interpreters). Reached through `BufferedSource.over(body)` → `body.each` → `#write_to`, so the window is honoured by phase 3b's code and the adapter contributes nothing |
| "on a zero-copy path where supported" | **⏳ `DEF-10`** | Measured (verified fact 14): `send_request_with_body_stream` writes to a `Net::BufferedIO`, and instrumenting `IO.copy_stream` reports `is_IO=false` for the destination. The kernel `sendfile` path requires two real `::IO`s, so it is unreachable without bypassing the library's own write path — which would mean writing the request framing by hand and giving up `Chunker`, `wait_for_continue` and every future `net-http` fix |

**Marking the whole ID ⏳ would defer a met MUST**, which is the one outcome the checklist legend exists
to prevent. The charter's own `R5` invites the split ("decide whether to implement the reachable half and
mark `TRANSPORT-28` partially satisfied, or to carry the whole ID ⏳"), and this document takes the first
option with the measurement attached. The conformance assertion `TRANSPORT-28`'s clause prescribes —
"upload a file body with a non-zero position and partial count; assert exactly that byte range reaches
the wire" — is written and passes; the zero-copy clause has no assertion because it has no observable
behaviour to assert, which is itself the reason it is a SHOULD.

**`DEF-3`'s `BODY-12` clause 2**, whose own text says it "targets phase 8", has its condition met and its
action declined, on the measurement above. Per the roadmap's retirement rule that is **UNSCHEDULED with
the phase named**, not `picked-up` and not silently carried. `BODY-36`'s half is untouched — its condition
is core's dependency budget changing, which phase 8 does not do.

**`DEF-10` is not marked.** Its condition is "revisit when a transport adapter **beyond the two MVP
transports** ships", and phase 8 ships exactly those two. `TRANSPORT-30` stays ⏳ against it whole, and
`TRANSPORT-28`'s third clause stays ⏳ against it as a clause.

---

## `R6` — whether `DEF-42`'s transport-milestone group is wired

**Decision: the tracer is NOT wired and the row stays open; the *logger* is wired, through a constructor
keyword, and the two are different for a stated reason.** `P8-7`.

`OI-36` — the charter's — records that no route exists by which an adapter in another gem reaches a
**per-operation** `HTTPTracer` through an `NFR-4`-locked three-argument seam. That is right, and the
three routes it names each fail:

- **A constructor keyword** gives one tracer for the adapter's whole lifetime. `OBS-29` requires "One
  tracer instance corresponds 1:1 to a single logical **operation** lifecycle (created by the factory per
  operation)", and an adapter has no notion of an operation — it sees one request at a time and cannot
  tell page 2 of a paginator from an unrelated call. A factory keyword is no better: the adapter would
  have to invent the operation boundary, and inventing it per `#call` makes every retry attempt a new
  operation, which contradicts `OBS-29`'s ordering clauses directly.
- **Widening `RequestOptions`** is a core type and a phase-1 surface, and `NFR-4` locks it. A widening is
  permitted by the lock, but it would put an instrumentation object into the wire-adjacent options value
  that `HTTP-34`/`HTTP-35` define as timeout, retry budget and tags — and phase 5b's `P5-33` already
  states both member lists as settled.
- **A fourth route the charter does not name, and it is rejected too: carrying the tracer in `Fiber[]`.**
  5b and 5c already carry the *diagnostic context* there, so the machinery exists. It is rejected on
  three grounds, any one sufficient. A tracer is a live mutable object, and
  `observability/65191069` measured that a mutable object in a `Fiber[]` slot is **one shared object
  across every thread and child fiber** descended from the creating fiber — `XCUT-11`'s "any shared
  mutable state MUST be synchronized" with no synchronisation, and invisible in a single-threaded test.
  It would make the transport's behaviour depend on whether a pipeline step ran, which is the ambient
  carriage `PIPE-11` forbids for the execution context and which `SEAM-11`'s "a transport that ignores
  options MUST behave identically to the no-options call" is the spirit of. And it would publish a third
  core-owned `Fiber[]` key where 5b deliberately published two.

So `8a` emits none of `OBS-28`'s five transport milestones, **`DEF-42` stays open on this half as well as
on `OI-32`'s**, and `OBS-29`'s transport group is not marked emitted on the strength of a method nothing
calls. `8c` inherits the same answer and the same reason.

**The logger is a different object and it is wired.** `TRANSPORT-11` ("SHOULD additionally log each drop
at verbose") and `TRANSPORT-14` ("logged at verbose") are requirements `8a` owns and cannot discharge
without a sink, and unlike a tracer a `Dexpace::Instrumentation::Logger` carries **no per-operation
identity requirement** — `OBS-9`'s context map is per-logger and `OBS-1`'s enabled decision is per-call.
So `NetHTTP.build(logger:)` takes one, defaulting to `Logger::NULL` so no caller ever holds a `nil`
(5b's own reason for shipping the constant), and every emission goes through
`Dexpace::Instrumentation.contain(logger, event: …)` because `OBS-20`'s "every log-emission site" is not
scoped to phase 5's sites. The asymmetry is the finding: a logger is reachable by construction and a
per-operation tracer is not, and `OI-36` is about the second.

---

## `R7` — the `TCPServer` fixture and the assertion protocol

**Decision: both ship in `dexpace-conformance`'s `lib/`, the parameterisation is a factory rather than a
mixin, a result has five statuses and `vacuous` is one of them, and waivers are by requirement ID.**
`P8-8`, `P8-9`.

§9.3 fixes two things and leaves four open. What it fixes: the protocol — "each one a callable that
either returns cleanly or raises a `Dexpace::Conformance::Failure` carrying the expected and actual
values — with thin Minitest and RSpec drivers over them" — and the fixture's reason, socket behaviour a
stub cannot express plus "the *same* assertions could not run unchanged against
`dexpace-transport-async_http` or a future `httpx` adapter".

**`lib/`, not `test/`.** §9.3's whole argument is that a third-party adapter author runs these
assertions, which means they ship in the gem; phase 0 already gave that `lib/` its own Steep target. The
consequence is that **`DEF-23` stays unmet**: its condition is "a Steep target over a `test/` tree", and
nothing `8a` writes under `test/` is production-quality code worth checking. `8a` confirms the row rather
than picking it up.

**A factory, not a mixin.** The two shapes are a module included into the adapter author's own test
class, and a driver taking a callable that builds a transport. The factory wins on three counts, and the
third is the one that matters: a mixin ties the assertion set to one test class per adapter, so running
the same assertions against **two** adapters in one process — which is exactly what the first-party build
does once `8c` lands, and what phase 9 does across every seam — needs two classes and a naming
convention; a factory is a value and needs neither. A mixin also cannot express per-adapter *settings*
(a BYO client, a timeout), which `TRANSPORT-15`'s two-sided conformance clause requires. And a mixin
makes the framework the unit of composition, which is the coupling §9.3 shipped a separate gem to avoid.

```
report = Dexpace::Conformance::TransportSuite.run(
  build: ->(**settings) { Dexpace::Transport::NetHTTP.build(**settings) },
  waive: ["TRANSPORT-28"],                      # by requirement ID, never by test name
)
```

**Five statuses, because §12 distinguishes vacuous from passing and appendix B distinguishes waived from
absent.** An assertion returns cleanly (`:passed`), raises `Failure` (`:failed`), raises
`Dexpace::Conformance::Vacuous` carrying its reason (`:vacuous`), is suppressed by a named waiver
(`:waived`, and the report still names it), or raises anything else (`:error`, never silently a failure).
`:vacuous` is not a convenience: §12's MUST-level summary counts eight MUSTs that "hold vacuously", and a
suite that reported them as passing would be the mechanism by which that count stops being true. An
assertion raises `Vacuous` from **inside** — after it has established the antecedent is absent — rather
than being skipped by a list, so vacuity is a measurement and not a claim.

**Waivers are by requirement ID and the gap stays visible**, which is §9.3's own sentence: "A failing item
that the port has decided not to satisfy is reported as a failure by the suite and suppressed in the
port's own build through a named waiver listing the requirement ID, so the gap stays visible rather than
disappearing into a restated item." So `Assertion` carries its IDs as **data**, `Report#waived` lists
them, and the Minitest driver prints them on every run rather than only on failure. `ASYNC-3`'s waiver is
`8b`'s to pass; the mechanism is `8a`'s to build.

**`Dexpace::Conformance::Failure` is a `::StandardError` and deliberately does *not* include
`Dexpace::Error`.** Phase 1 made `Dexpace::Error` the module every SDK error includes so a caller can
`rescue Dexpace::Error` broadly; a conformance failure is a test result, not an SDK error, and including
it would make that rescue catch one. `P8-8` records the decision because §9.3 names the class and not its
ancestry.

**The fixture.** `Dexpace::Conformance::WireServer` binds a `TCPServer` on `127.0.0.1:0`, runs one accept
loop in a thread, and hands each connection to a **script** — a callable taking the socket and the
request head it already read. It records `#requests` (the head plus a declared body), `#connections` (so
`TRANSPORT-2`'s "assert the native client does not silently re-send" is a count and not an inference) and
`#closed_connections` (so `TRANSPORT-25`'s "assert closing returns the connection" is observable from the
server's side rather than from the client's), and **`#await_closed_connection`**, a blocking `Queue#pop`
the handler's `ensure` feeds — the one wait every "has the server seen it?" assertion uses, because a
`sleep`-poll over `#closed_connections` is load-sensitive and `testing/4ef070df` requires order
independence. `Scripts.hang_after_headers` takes an `on_headers_written:` callable for the mirror case:
a test that must fire a cancellation *while the call is blocked* pushes from there, on the server's own
thread, at the instant the client enters its first body read — never after a guessed delay. Named scripts cover what the chapter's conformance clauses
need: a fixed-length body, a chunked body, connection-close framing, a **dribbled** body with a delay
between chunks, a `302` with a `Location`, a vendor status with a body, malformed inbound headers, a
malformed `Content-Length`, a hang-after-headers, a first-connection-failure-then-success, and a
truncated body. **A fresh server and fresh transports per assertion**, because `testing/4ef070df` requires
every test to run alone in any order and a shared server makes `#connections` order-dependent.

**Two things the fixture deliberately does not do, and the suite says so rather than pretending.** It
speaks **plaintext only** — a self-signed TLS fixture is portable in principle and brittle in practice
across three interpreters and two OpenSSL majors, and the property that matters (verified fact 16: the
adapter assigns no `verify_mode`, so `set_params` supplies `VERIFY_PEER`) is asserted structurally in
`dexpace-transport-net_http`'s own suite. And it does not exercise a **connect** timeout, because there
is no portable way to make a local listener accept slowly; `TRANSPORT-4`'s read-timeout half and
`TRANSPORT-20`'s connection-refused half are scripted, and the open-timeout path is a unit test in the
adapter's suite against `Net::OpenTimeout` directly. Both omissions are recorded in the report's preamble
so a third-party adapter author is not misled about what a green run proves. `P8-9`.

---

## `R16` — who writes the conformance harness

**`8a` writes it.** The charter assigns §9.3's `TCPServer` fixture and `DEF-22`'s assertion protocol to
`8a`, `8a` is the recommended first sub-phase, and this document accepts both artifacts without
qualification. There is no branch here to leave open: if `8c` lands first it will find nothing to consume
and will have to write them, at which point `8a`'s design records that it consumed rather than wrote them
— one sentence, in one section, in a document that will by then be executing rather than being reviewed.

**What `8c` inherits, and what it must not do.** `8c` adds a **second driver** — one more
`TransportSuite.run(build:)` call with its own factory and its own waivers — and adds assertions only for
the seven IDs that are its own. It does not fork the suite, does not add a second `WireServer`, and does
not parameterise an existing assertion on "which adapter is this". The last is the failure the gem exists
to prevent: verified fact 11 records that `Net::HTTP` normalises header-name case on the wire while
`Protocol::HTTP::Headers` preserves it, so an assertion that checked the wire bytes for a caller's exact
spelling would pass on one adapter and fail on the other — which is precisely the kind of assertion
`dexpace-conformance` must not contain, and the kind that a per-adapter branch inside an assertion makes
easy to write.

### The suite contract — what `dexpace-conformance` assumes, and what it must never assume

**This is the single list, and it is `8a`'s to own.** It was five clauses when this document was written
and `8c`'s design carried a separate nine-clause list of requirements it placed on the same suite;
**merged here on 2026-09-12 into twelve, dropping nothing `8c` relies on.** `8c`'s design now cites this
section by name and path — *`R16` — who writes the conformance harness → The suite contract*, in
`docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md` —
and keeps only its own commentary. Where an `8c` clause was already implied by an `8a` assumption that is
said on the clause. **The goal the merge serves: `8c`'s transport passes the suite with no build-order
dependency beyond "`8a`'s gem exists".**

Clauses 1–5 are **properties of the transport under test**; 6–12 are **properties of the suite itself**,
which is the half `8c` supplied and which an `8a`-only reading would have left unstated.

1. It answers `#call(request, options, cancellation)` and returns a `Dexpace::Response`, **or a
   `Dexpace::Async::Future` of one** — `Dexpace::Transport.conforms?` and
   `Dexpace::AsyncTransport.conforms?` are the same arity-3 predicate, and clause 8 is how the suite
   stops caring which. *(Widened for `8c`; `8c`'s own clause 3 is the mechanism.)*
2. Its `Response#body`, when present, answers `#source` and `#close` (3b's `P3-23`), and `#source`
   returns a `Dexpace::IO::BufferedSource`. **Its `#content_length` is an `Integer` and is `-1` when
   unknown, never `nil`** (`BODY-35`, `TRANSPORT-27`) — `async-http` reports a native `nil` and maps it
   at the boundary, `Net::HTTP` parses it from the raw header; the suite asks the SDK model, never the
   native object. *(The `-1` half is new, and it is what stops an assertion written against one adapter's
   native shape from failing on the other's.)*
3. It answers `#close`, `#closed?` and `#owned?` (phase 2's `Dexpace::Closeable`).
4. It is built by a **callable factory, never a pre-built instance and never a constant**, taking keyword
   settings, of which the suite passes at most `timeout:`, `logger:` and — for `TRANSPORT-15`'s borrowed
   half — whatever the adapter's borrowing entry point is named, which the driver supplies as a second
   optional factory rather than assuming a name. *(`8c`'s clause 1. It asked additionally for a
   `base_url` positional; that is **not** needed and is deliberately not added: `TransportCase#request`
   already builds every request against the live fixture's own port, and an adapter that routes by
   `Request#url` — which `8c`'s does — needs nothing else. A factory that also wanted a base URL would
   force every adapter to accept one.)*
5. Every failure it raises, or fails its future with, that carried no HTTP response answers `#retryable?`
   (`XCUT-4` branch (b), the phase-level `Dexpace::TransportError`), and a **cancellation** surfaces as
   `Dexpace::CancelledError` — terminal and non-retryable — from whichever of the two channels clause 8
   is using. On the async path that means `Completer#request_cancel` and not `Completer#fail`, because
   only `#request_cancel` settles the `Settlement.cancellation` that `Future#cancelled?` reads as true
   and that `Future#value` re-raises as `CancelledError`. *(New, and it is the clause an async adapter
   satisfies by accident on the first call and not on the second.)*
6. **No assertion compares a header name against the wire's exact spelling.** Names are compared folded.
   `Net::HTTP` normalises case on the wire (`x-lower-name` → `X-Lower-Name`), `Protocol::HTTP::Headers`
   preserves it on HTTP/1.1 — and lowercases it on HTTP/2, which makes this an **intra**-adapter hazard
   as well as a cross-adapter one. *(`8c`'s clause 5, sharpened by its verified fact 2.)*
7. **No assertion expects `content-length` among a response's headers.** `protocol-http1` consumes it as
   framing and exposes it only as the body's length; `Net::HTTP` exposes both. The portable question is
   what `Dexpace::Response` says the length is, and clause 2 is where it is asked. *(`8c`'s clause 6.)*
8. **`send` is one primitive and the driver supplies it.** `TransportCase#settle(transport, request,
   options, cancellation) -> Dexpace::Response` — the sync driver implements it as
   `transport.call(…)`, the async driver as `transport.call(…).value(cancellation: …)`. Without it every
   §17 assertion is written twice and the two copies drift, which is §11.12's "four reference sync/async
   drifts" reappearing inside the port's own suite. *(`8c`'s clause 3, and the single most load-bearing
   thing `8c` needs that `8a`'s original five did not carry.)*
9. **Every assertion body is invoked by the driver, so the driver may wrap it.** `TransportSuite.run`
   takes an optional `around:` callable that receives each assertion's invocation as a block; the async
   driver passes `->(&blk) { Sync { blk.call } }`, because `8c`'s transport fails its future outside a
   reactor by design (`P8-39`). This is already `DEF-22`'s shape — "each one a callable that either
   returns cleanly or raises a `Dexpace::Conformance::Failure`" — made explicit: an assertion that
   reached out to a Minitest method body directly could not be wrapped. **A body streamed under a fiber
   scheduler is the case this exists for**: `TRANSPORT-25`'s multi-megabyte round trip and
   `TRANSPORT-19`'s abandoned-subscription clause both read a body, and on `8c` that read must happen
   inside the reactor the `around:` wrapper opened, on the same fiber the exchange was started on.
   *(`8c`'s clause 2.)*
10. **The fixture's accept loop runs on its own thread, never on the fiber under test.** `WireServer`
    already does this and it cannot be retrofitted cheaply: a `TCPServer#accept` on the fiber running an
    assertion deadlocks a reactor. *(`8c`'s clause 8 — already implied by `8a`'s `WireServer` shape, and
    stated here so it is a contract rather than an accident.)*
11. **The suite tolerates more than one fixture per run.** `TransportSuite.run` takes an optional
    `wire:` factory; `TransportCase#wire` calls it instead of starting a `WireServer` when one is given.
    A fixture must answer `#port` and the `#requests` / `#connections` / `#closed_connections` /
    `#await_closed_connection` counters `WireServer` publishes. `8c` drives the same protocol-independent
    assertions against `8a`'s HTTP/1.1 `TCPServer` fixture *and* its own in-process HTTP/2 fixture, which
    lives in `dexpace-transport-async_http`'s `test/support/` and never in `dexpace-conformance` —
    that gem declares `dexpace-core` and nothing else, and an HTTP/2 server needs `async-http`.
    *(`8c`'s clause 9.)*
12. **A per-adapter result is three-valued at minimum and never silently a pass.** The suite's five
    statuses (`:passed`, `:failed`, `:vacuous`, `:waived`, `:error`) cover `8c`'s asked-for
    pass / vacuous-with-reason / waived-with-requirement-id, and §9.3's named-waiver mechanism is the
    vehicle for a clause the port has decided not to satisfy. `8c` needs it for three shapes at once: one
    clause **unreachable on its adapter** (`TRANSPORT-14`'s malformed-inbound-**name** half), one clause
    **unreachable on `8c` and reachable on `8a`** (`TRANSPORT-27`'s invalid-`Content-Length` half — see
    the note below), and one **inverted pair** (`TRANSPORT-8` satisfied on `8c` and vacuous on `8a`;
    `TRANSPORT-12` live on `8c` and vacuous on `8a`). *(`8c`'s clause 4 — already implied by `8a`'s five
    statuses, and named here so `8c` need not re-derive which status carries which shape.)*

**Cancellation assertions use the `Dexpace::Cancellation` token and never a thread interrupt**
(`8c`'s clause 7) — already true of `8a`, forbidden repository-wide by `Dexpace/NoThreadInterrupt`, and
recorded here because it is a property of the *assertions* rather than of either adapter.

**One correction `8c` is owed in the other direction.** `8c`'s design reports that
`TRANSPORT-27`'s invalid-`Content-Length` clause is "unreachable on **both** adapters for the same
reason" and proposes one waiver covering both drivers. That is right about `async-http` and wrong about
`Net::HTTP`: verified fact 12 here measures the head arriving in full under the block form, and `R4`
implements the clause. **The waiver is `8c`'s driver's alone.**

Nothing in clauses 1–12 mentions `Net::HTTP`, a thread, a fiber or a reactor, and nothing in
`dexpace-conformance`'s `lib/` or `sig/` may name `async`, `Async::Task` or `Protocol::HTTP` — the
reactor wrapping in clause 9 lives in the driver `8c` supplies, inside `8c`'s own gem.

---

## Module layout

Every file `8a` creates or modifies. `sig/` mirrors `lib/` one file per file and **ships inside each
gem**; `test/` mirrors `lib/` and does not ship. `private_constant`s get neither, per phases 3, 4 and 7.
One public constant per file (`module-organization/1828a984`).

```
gems/dexpace-core/
  lib/dexpace/error/transport_error.rb        Dexpace::TransportError  — PHASE-LEVEL (below)
  lib/dexpace/configuration/keys.rb           MODIFIED: Keys::REQUEST_TIMEOUT
  lib/dexpace.rb                              MODIFIED: one require_relative
  sig/dexpace/error/transport_error.rbs       NEW  (phase-level)
  sig/dexpace/configuration/keys.rbs          MODIFIED

gems/dexpace-transport-net_http/
  dexpace-transport-net_http.gemspec          MODIFIED: add_dependency "net-http", ">= 0.4"
  lib/dexpace/transport/net_http.rb           MODIFIED: requires, .build, .using, .default,
                                              REGISTRY_KEY, and the require-time registration
  lib/dexpace/transport/net_http/adapter.rb            Dexpace::Transport::NetHTTP::Adapter
  lib/dexpace/transport/net_http/request_mapper.rb     private_constant RequestMapper
  lib/dexpace/transport/net_http/response_mapper.rb    private_constant ResponseMapper
  lib/dexpace/transport/net_http/response_pump.rb      private_constant ResponsePump
  lib/dexpace/transport/net_http/deadline.rb           private_constant Deadline
  lib/dexpace/transport/net_http/failures.rb           private_constant Failures
  sig/dexpace/transport/net_http.rbs          MODIFIED
  sig/dexpace/transport/net_http/adapter.rbs  NEW
  test/dexpace/transport/net_http/…           the adapter's own suite, plus the conformance driver

gems/dexpace-conformance/
  lib/dexpace/conformance.rb                  MODIFIED: requires, VERSION stays phase 0's
  lib/dexpace/conformance/failure.rb          Dexpace::Conformance::Failure
  lib/dexpace/conformance/vacuous.rb          Dexpace::Conformance::Vacuous
  lib/dexpace/conformance/assertion.rb        Dexpace::Conformance::Assertion
  lib/dexpace/conformance/result.rb           Dexpace::Conformance::Result
  lib/dexpace/conformance/report.rb           Dexpace::Conformance::Report
  lib/dexpace/conformance/wire_server.rb      Dexpace::Conformance::WireServer
  lib/dexpace/conformance/scripts.rb          Dexpace::Conformance::Scripts
  lib/dexpace/conformance/transport_case.rb   Dexpace::Conformance::TransportCase
  lib/dexpace/conformance/transport_suite.rb  Dexpace::Conformance::TransportSuite
  lib/dexpace/conformance/minitest_driver.rb  Dexpace::Conformance::MinitestDriver
  lib/dexpace/conformance/rspec_driver.rb     Dexpace::Conformance::RSpecDriver — NOT required by the entry file
  lib/dexpace/conformance/recording_span.rb   Dexpace::Conformance::RecordingSpan   (5c's OBS-21 obligation)
  lib/dexpace/conformance/allocations.rb      Dexpace::Conformance::Allocations     (5b's R8 / OBS-25 obligation)
  sig/…                                       thirteen mirrors
  test/…                                      the gem's own suite, driving a FakeTransport
```

**Two placement notes.** `MinitestDriver` and `RSpecDriver` are named that way and not `Minitest` and
`RSpec` for phase 5a's `P5-3` reason: inside `module Dexpace::Conformance`, a constant named `Minitest`
shadows `::Minitest` for every bare reference in the whole namespace — including the one in its own body
— and a name chosen so the shadow never exists is better than a cop policing one. And `RecordingSpan`
and `Allocations` live in `dexpace-conformance` rather than in `dexpace-core`'s `test/support/` because
5c and 5b each assigned them to "the conformance gem", and because a third-party adapter author asserting
`OBS-21` needs them to ship.

---

## The object model `8a` ships

### `dexpace-core` — one constant and one key (the phase-level task, and one line)

`Dexpace::TransportError` is the charter's **phase-level task 1**, and **`8a`'s Task 2 lands it** — the
charter fixed that on 2026-09-12, where it had read "whoever lands first writes it" and both `8a` and
`8c` then wrote it with two shapes. The shape below is the one the charter adopted, and it is a superset
of `8c`'s: `8c` constructs the class as `TransportError.new("…")` at every site in its `Errors.wrap`, so
the optional `phase:` keyword costs it nothing, and its three assertions (`< ::IOError`,
`include Dexpace::Error`, `#retryable?` always true) all hold here. `8c`'s Task 4 is a citation and a
verification, and writes the class itself only if `8c` executes first. `class TransportError < ::IOError;
include Dexpace::Error; end`, with `#retryable?` defaulting to `true` (`XCUT-4` branch (b): "A transport
error MUST report itself as always-retryable at the error level"), a `#phase` naming where the failure
occurred (`:connect`, `:write`, `:read`, `:close`) for diagnostics only, and Ruby's implicit `#cause`
carrying the stdlib error it wrapped. It is a **sibling** of `Dexpace::StreamError` inside `::IOError`
and never a subclass (`P3-3`), because a stream-contract violation must not claim to be always-retryable.
Verified fact 7 is why it cannot be skipped: none of `Net::OpenTimeout`, `Net::ReadTimeout`,
`Net::WriteTimeout`, `SocketError`, `Socket::ResolutionError`, `Errno::*`, `OpenSSL::SSL::SSLError`,
`Net::HTTPBadResponse` or `Net::HTTPHeaderSyntaxError` is an `::IOError`, so a bare one escaping the
adapter classifies **not-retryable** through `RETRY-2`'s capability query — `P6-4`'s stated blind spot,
arriving.

`Dexpace::Configuration::Keys::REQUEST_TIMEOUT = "REQUEST_TIMEOUT"` — `R3`.

### `dexpace-transport-net_http`

**`Dexpace::Transport::NetHTTP`** — a module, phase 0's namespace, gaining:

| Member | Role |
|---|---|
| `.build(timeout: nil, logger: Dexpace::Instrumentation::Logger::NULL) -> Adapter` | The **SDK-managed** construction. Builds a `Net::HTTP` per call. `owned?` is `true` |
| `.using(client, logger: …) -> Adapter` | The **borrowing** construction. Wraps a caller-built `Net::HTTP`. `owned?` is `false`. Raises `Dexpace::InvalidArgumentError` at construction unless `client.max_retries.zero?` (`P8-10`) |
| `.default -> Adapter` | `SEAM-5`'s zero-argument factory the registry calls; a **fresh** instance every call, never a memoized one |
| `REGISTRY_KEY = :net_http` | The key the require-time registration uses |
| `MANAGED_HEADERS` | The frozen, folded `TRANSPORT-11` drop set (`R2`) |
| `DEFAULT_CONTENT_TYPE` | `"application/octet-stream"` (`R2`, `P8-4`) |
| `DEFAULT_TIMEOUT_SECONDS`, `MIN_TIMEOUT_SECONDS`, `JOIN_DEADLINE_SECONDS` | The three tuning constants, named rather than embedded (`resource-management/2b9040ef`'s purpose) |
| `VERSION` | phase 0's, unchanged |

The file ends with
`Dexpace::Transport.register(REGISTRY_KEY, method(:default), core: "~> #{…}")` — the one load-time side
effect this repository permits (`module-organization/5c33e5ce`), with the **required** skew keyword that
raises `Dexpace::SeamError` on a `Dexpace::VERSION` mismatch (§2.3, `DEF-21`, `P2-7`).

**`Dexpace::Transport::NetHTTP::Adapter`** — the transport. `private_class_method :new`; includes
`Dexpace::Closeable`, calling `initialize_closeable(owned:)` with the construction-time fact; frozen
after construction except for `Closeable`'s latch, which is what `TRANSPORT-29`'s "effectively immutable
after construction" means in Ruby.

| Method | Behaviour | IDs |
|---|---|---|
| `#call(request, options, cancellation)` | The seam. Validates, maps, dispatches, adapts, returns a `Dexpace::Response`. Raises `Dexpace::ClosedError` when `closed?` **and** `owned?` | `SEAM-11`, `SEAM-13`, `SEAM-15`, `TRANSPORT-3`–`6`, `10`, `11`, `14`, `17`, `20`, `22`, `24`–`27`, `29` |
| `#close` | `Closeable`'s latch. `#release` is a **no-op** on the managed construction — there is no long-lived native resource — and is never reached on the borrowing one, because `Closeable#close` skips it when `owned?` is false | `TRANSPORT-15`, `TRANSPORT-16`, `SEAM-14`, `XCUT-13`, `XCUT-22` |
| `#closed?`, `#owned?` | `Closeable`'s two readers; `#owned?` is what makes `TRANSPORT-15` assertable from a test without `instance_variable_get`, exactly as 3a's `#owns_upstream?` is | `TRANSPORT-15` |

**`#close` latches on both constructions and only the managed one refuses a later send.** That is phase
2's documented `SEAM-15` mode adopted whole: an owning transport raises, a borrowing wrapper "closes
nothing and stays usable", and raising on the borrowing one "would break `XCUT-22`'s 'the caller owns its
lifecycle and may keep using it after the SDK component is closed'". `TRANSPORT-16`'s "call close several
times → no exception and stable state" is the latch; `TRANSPORT-15`'s two-sided clause is the pair.
**In-flight responses are not cancelled by the transport's close** — each `ResponsePump` is owned by the
`Dexpace::Response` that holds it, and `SEAM-25`'s "closing MUST NOT be required to cancel in-flight
requests" is the rule, applied to the seam that has no executor.

**`RequestMapper`** (`private_constant`) — `R2`'s eight steps, in order, as one module function returning
a `Net::HTTPGenericRequest`. It is the only place in the gem that touches `Dexpace::HeaderSyntax`, the
only place that names `MANAGED_HEADERS`, and the only place that constructs a native request.

**`ResponseMapper`** (`private_constant`) — takes the native head off the pump and returns a
`Dexpace::Response`: `Status.of(res.code.to_i)` (total over any integer, `TRANSPORT-24`),
`res.message` as `reason`, `Protocol.parse("HTTP/#{res.http_version}")`, headers from **`res.to_hash`**
and nothing else (verified fact 6), the `TRANSPORT-14` filter applied **before** the values reach
`Headers::Builder`, `R4`'s length parse, `MediaType.parse` wrapped in the
`rescue Dexpace::InvalidArgumentError; nil` that *is* the downgrade (`R4` step 3 — the parser raises,
it does not return `nil`), and a
`Dexpace::ResponseBody.new(source: BufferedSource.wrapping(pump), media_type:, content_length:)`. A
`204`, a `304` or a `HEAD` response — anything for which `res.class.body_permitted?` is `false`
(verified: `Net::HTTPNoContent`'s is `false`, `Net::HTTPOK`'s is `true`) —
gets `body: nil` and the pump is closed immediately, because a `ResponseBody` over a stream that will
never yield is a resource with no reader.

**`ResponsePump`** (`private_constant`) — `R1`. The producer thread, the `Thread::SizedQueue(1)`, the
`Net::HTTP`, and a `#readpartial`/`#read`/`#close` surface. It includes `Dexpace::Closeable` for the
latch and nothing else; its `#release` is `R1`'s three steps.

**`Deadline`** (`private_constant`) — `R3`. A frozen value over the clock and an absolute monotonic
instant, with `#remaining`, `#expired?` and `#clamped` — the last being `TRANSPORT-6`'s one-line clamp
with the ID in a comment.

**`Failures`** (`private_constant`) — one module function, `Failures.wrap(error, phase:, cancellation:)`,
and it is the whole of `TRANSPORT-3`, `TRANSPORT-4` and `TRANSPORT-20`. Its rules, in order:

1. **Ask the token first, never the exception.** If `cancellation.cancelled?`, the failure is a
   cancellation regardless of what the library raised, and it surfaces as the terminal, non-retryable
   interrupt-shaped error phase 2's `Dexpace::Cancellation#reason` carries. That is `TRANSPORT-3`'s
   "Discrimination MUST be out-of-band (the runtime's cancellation state), not by matching messages",
   and it is not a refinement: verified fact 3 shows a cancel and a peer reset arrive as the *same*
   `IOError` with the *same* message.
2. **Otherwise wrap into `Dexpace::TransportError`, retryable — as a catch-all, not as a lookup against
   an enumerated list.** The families this adapter actually meets are `Net::OpenTimeout`,
   `Net::ReadTimeout`, `Net::WriteTimeout`, `SocketError` (which covers `Socket::ResolutionError`),
   `Errno::*` via `SystemCallError`, `OpenSSL::SSL::SSLError`, `EOFError`, `IOError`,
   `Net::HTTPBadResponse`, `Net::HTTPHeaderSyntaxError` and `Zlib::Error` — and they are documented,
   not branched on. **An enumerated list has exactly one failure mode and it is the bad one**: a family
   nobody thought of escapes unwrapped and classifies **not-retryable** through `RETRY-2`'s capability
   query, which is precisely `P6-4`'s stated blind spot. `P6-4`'s obligation reads "wrap, and default
   to retryable, **not** wrap and get the classification right by hand", and a list is the hand.
   `TRANSPORT-4` is the row that makes the read-timeout case explicit — it is retryable and **must
   not** set the cancellation flag, which is structural here because `Failures` never writes to a
   token.
3. **Never wrap what is already ours.** `Dexpace::StreamError`, `Dexpace::EndOfStreamError`,
   `Dexpace::ClosedError`, `Dexpace::InvalidArgumentError` and anything including `Dexpace::Error`
   propagate unwrapped; double-wrapping a stream-contract violation into an always-retryable transport
   failure would make `RETRY-2` re-send on a caller's own bug.
4. **`Net::HTTPHeaderSyntaxError` is named in rule 2's documented set and is nearly unreachable**,
   because `R4` removes the one route that raises it. It is still named, because the library may raise
   it elsewhere and an unwrapped one would classify not-retryable — which is the same argument rule 2
   makes for being a catch-all rather than a list.

### `dexpace-conformance`

| Constant | Role |
|---|---|
| `Dexpace::Conformance::Failure < ::StandardError` | `DEF-22`'s failure, carrying `#expected`, `#actual` and `#requirement_ids`. **Not** a `Dexpace::Error` (`P8-8`) |
| `Dexpace::Conformance::Vacuous < ::StandardError` | Raised from inside an assertion that has established its antecedent is absent, carrying `#reason`. §12's distinction, made a result rather than a claim |
| `Dexpace::Conformance::Assertion` | `Data.define(:ids, :name, :body)`; `#call(subject)`. `ids` is a frozen array of requirement-ID strings, which is what makes a waiver by ID possible |
| `Dexpace::Conformance::Result` | `Data.define(:assertion, :status, :detail)`; status in `:passed`, `:failed`, `:vacuous`, `:waived`, `:error` |
| `Dexpace::Conformance::Report` | A frozen list of `Result`s with `#passed?`, `#failures`, `#vacuous`, `#waived`, `#errors`, `#to_s`. `#to_s` names every waived ID on every run, per §9.3's "the gap stays visible" |
| `Dexpace::Conformance::WireServer` | The `TCPServer` fixture. `.start(script) { |server| … }` and a non-block form with `#close`; `#port`, `#requests`, `#connections`, `#closed_connections`, and `#await_closed_connection(count = 1)` — a blocking `Queue#pop` fed from the connection handler's `ensure`, so a test that needs "the server has seen the close" waits on a condition instead of polling `#closed_connections` in a `sleep` loop (Global Constraints; `testing/4ef070df`) |
| `Dexpace::Conformance::Scripts` | The named scripts, module functions returning callables |
| `Dexpace::Conformance::TransportCase` | What an assertion receives: `#transport(**settings)`, `#borrowed_transport(client)`, `#wire`, `#request(path:, method:, headers:, body:)`, and a teardown the runner drives |
| `Dexpace::Conformance::TransportSuite` | `.assertions -> Array[Assertion]` (frozen, ordered) and `.run(build:, borrow: nil, waive: [])` |
| `Dexpace::Conformance::MinitestDriver` | `extend`-able; `conformance(suite, **options)` defines one test method per assertion |
| `Dexpace::Conformance::RSpecDriver` | The same over `::RSpec.describe`, referenced at call time and **never `require`d** |
| `Dexpace::Conformance::RecordingSpan` | 5c's `OBS-21` obligation: a span whose `#recording?` is true and which records attributes, errors and `#end` calls, so idempotence has a subject |
| `Dexpace::Conformance::Allocations` | 5b's `R8` obligation: `.delta(iterations:) { }` over `GC.stat(:total_allocated_objects)`, dividing by the iteration count rather than differencing two loops |

**Neither driver `require`s its framework**, and that is a gemspec decision rather than a style one.
`dexpace-conformance` declares `dexpace-core` and nothing else — §2.1 says so, and phase 0's
`gates:gemspec_audit` enforces it — so a `require "minitest"` in its `lib/` would be an undeclared
dependency on a **bundled** gem (verified fact 17), which is exactly the failure mode `CLAUDE.md`'s hard
rule is about, arriving in an adapter instead of in core. Each driver references `::Minitest` or
`::RSpec` inside a method body, resolved in the consumer's process where the framework is already
loaded, and `lib/dexpace/conformance.rb` requires the Minitest driver but **not** the RSpec one, so a
Minitest-only consumer never touches a file naming `::RSpec`.

**`Allocations` is written under 5b's `R8` rule and the rule is what the method signature encodes.**
What makes an allocation assertion caller-insensitive is passing **arguments that cannot allocate** —
not the file's `frozen_string_literal` comment, and not a two-loop delta, which isolates the caller's
per-iteration cost rather than hiding it. Measured on 3.4.10: `GC.stat(:total_allocated_objects)` around
an empty block reports **1** and around `{ nil }` reports **0**, so the harness's own overhead is
caller-shaped and an assertion that does not control its arguments measures the wrong thing. `.delta`
therefore takes the iteration count, runs a warm-up, and asserts the **per-iteration** delta is zero.

---

## The `sig/` shape

**Public means a YARD block *and* an RBS signature**, so every constant in the module layout above gets a
`sig/` mirror at the mirrored path, in the gem that ships it. Four things about the shape are decisions
rather than mechanics:

- **`NFR-11`'s scan is the gate that decides the adapter's whole surface, and `8a` is the first gem it
  can fire on.** No constant outside `Dexpace::` and the fixed stdlib allowlist may appear in any public
  signature. `Net::HTTP`, `Net::HTTPResponse` and `Net::HTTPGenericRequest` appear in **no** `sig/` file:
  `.build` takes keywords and `.using(client)` types its argument as `untyped` with a YARD block saying
  what it must be, exactly as 7a typed `#load`'s `source` as `untyped` rather than naming a class. The
  scan's five fixtures cover a return type, a superclass, an `include`, a type alias and a generic upper
  bound; the borrowing constructor's argument is the sixth position a name could occupy, and typing it
  `untyped` is what keeps the count at zero.
- **`dexpace-conformance` declares one RBS interface and it is the transport seam's**:
  `interface _Transport; def call: (Dexpace::Request, Dexpace::RequestOptions, Dexpace::Cancellation) -> Dexpace::Response; end`,
  in `sig/dexpace/conformance/transport_case.rbs`. `TransportCase#transport` returns it. That is the
  *only* place in the repository where the duck type phase 2 deliberately left structural acquires a
  named shape, and it is deliberate: the suite is the one consumer that must state what it assumes, and
  a `sig/`-only interface adds no runtime constant and no `.conforms?` competitor.
- **`Assertion#body` is `^(untyped) -> void`**, not a named interface, because an assertion's subject is
  whatever suite it belongs to and phase 9 adds suites for seams that are not transports.
- **The two drivers' `define_method`-generated tests are invisible to RBS and to the surface snapshot
  both**, which is correct — they are test methods in a consumer's class, not this gem's surface. What
  the snapshot does see is `MinitestDriver.conformance` and `RSpecDriver.conformance`, and the plan's
  final task regenerates **both** the RBS baseline and the runtime surface manifest, because
  `Data.define`'s generated readers on `Assertion` and `Result` are public API `rbs validate` cannot see.

`8a`'s public surface across both gems names exactly four stdlib types — `String`, `Integer`, `Float` and
`Symbol` — plus `Dexpace::` constants and `bool`. Nothing from `net/http`, nothing from `socket`,
nothing from `minitest`.

---

## The spec-forced boundaries, honoured

Each of the charter's twenty boundaries is honoured by name, not re-argued. The ones belonging wholly to
`8b` or `8c` are listed as not `8a`'s so a reader can see the whole set was read.

1. **The pipeline is the single authority on redirect and retry (boundary 1).** `http.max_retries = 0`
   on every managed client; a constructor-time refusal on a borrowing one (`P8-10`); and no
   follow-redirects knob to turn off (verified fact 1). The charter's "not vacuous for either MVP adapter
   on the retry half" is confirmed and is `OI-34`.
2. **The streaming contracts impose no timeout; the transport owns every deadline (boundary 2).**
   `IO-40`. `8a` pushes no deadline into `Dexpace::IO::BufferedSource` and sets none on the
   `ResponsePump`'s queue; every deadline is on the `Net::HTTP` instance (`R3`).
3. **Deadlines are explicit values, never ambient interrupts (boundary 3).** `8a` writes no
   `Timeout.timeout`, no `Thread#raise` and no `Thread#kill`; `Dexpace/NoThreadInterrupt` has nothing to
   bite and no waiver is requested. Verified fact 15 records that `net-http` itself uses
   `Timeout.timeout` for the connect phase, which is outside both the cop's scan and the hazard, and
   which is proposed as a register finding rather than accepted silently.
4. **§10.5's three MUSTs (boundary 4).** `8b`'s and `8c`'s. `8a` names no `ASYNC` ID and adds no ⏳ row
   against `DEF-18`.
5. **The pivot is core-owned (boundary 5).** `8a` ships no async transport and constructs no
   `Completer`. Stated because `Transport.async_over` will wrap this adapter and a reader may expect it
   to know.
6. **`NFR-11` is an RBS scan (boundary 6).** Above.
7. **`NFR-2`'s budget (boundary 7).** `dexpace-transport-net_http` declares `dexpace-core` plus
   `net-http`; `dexpace-conformance` declares `dexpace-core` and nothing else, **by design**, which is
   what forces both drivers' no-`require` shape.
8. **Every adapter's registration asserts `Dexpace::VERSION` (boundary 8).** The transport registers with
   the required `core:` keyword. `dexpace-conformance` registers into no seam — it is not an adapter —
   and therefore has no registration to assert, which is stated so its absence is a decision.
9. **Ownership is a construction-time fact (boundary 9).** Two differently named entry points, `.build`
   and `.using`, and a frozen `@owned` set at construction through `Closeable#initialize_closeable`.
   `TRANSPORT-15` and `XCUT-22` get one implementation.
10. **Idempotent close is a latch under a `Thread::Mutex` held only across the flip (boundary 10).** Two
    latches in `8a`, both phase 2's `Closeable`: the `Adapter`'s and the `ResponsePump`'s. Neither holds
    the mutex across the release, which for the pump is a queue close, a socket close and a join — every
    one of them a suspension point.
11. **Wire-boundary re-validation raises; `TRANSPORT-12`'s drop is a different rule (boundary 11).**
    `DEF-25`'s call site raises `Dexpace::InvalidArgumentError`; `MANAGED_HEADERS` drops. The two sets are
    disjoint by construction — a managed header is dropped whether or not it is valid, and an invalid
    header raises whether or not it is managed — and `8a` merges them nowhere.
12. **A pipeline is a transport and closing it is a no-op on the transport (boundary 12).** `8a` makes no
    assumption about its caller, reads nothing off a cursor, and installs no step.
13. **Conformance runs against a local `TCPServer`, never a stubbing library (boundary 13).** `R7`. `8a`
    adds no stubbing dependency to either gem, and the adapter's own suite uses the same fixture rather
    than a second one.
14. **`dexpace-conformance`'s assertions are framework-agnostic callables (boundary 14).** `R7`.
15. **Appendix B's phase-8 restatements are fixed by §9.3 (boundary 15).** B.6 is exercised per adapter,
    which is what `TransportSuite.run(build:)` makes mechanical, and the named-waiver mechanism is built
    here for `ASYNC-3`'s benefit even though `8a` waives nothing but `TRANSPORT-28`'s zero-copy clause.
16. **The seams are phase 2's (boundary 16).** `8a` adds no seam, no second registry and no competing
    root.
17. **`SEAM-15` is taken explicitly (boundary 17).** Settled by phase 2 in code; `8a` adopts it and
    supplies the first raise site. See *From phase 2*.
18. **Bytes on the wire are `Encoding::BINARY` in both directions (boundary 18).** Inbound: `read_body`
    chunks are `ASCII-8BIT` and unfrozen (verified fact 10) and the pump writes into `outbuf` with
    `String#replace`, which copies the source's encoding (verified fact 11). Outbound:
    `BufferedSource.over(body)` yields whatever 3b's bodies yield, which 3a retags. **Every encoding
    assertion in `8a` uses non-ASCII content** (`io-and-byte-streams/a44b4de6`).
19. **`URI::RFC3986_PARSER` is pinned (boundary 19).** The request-to-endpoint conversion reads
    `request.url`, which phase 1 already parsed with the pinned parser and stores as a frozen
    `URI::Generic`; `8a` reads `#scheme`, `#hostname`, `#port` and `#request_uri` off it and parses
    nothing itself — verified that `URI::RFC3986_PARSER.parse("http://example.com:8080/a/b?c=1")`
    yields a `URI::HTTP` whose `#request_uri` is `"/a/b?c=1"`, and that the `https` form defaults its
    `#port` to 443. `Dexpace/NoUriDefaultParser` has nothing to bite, and that is
    because phase 1 did the parse, not because `8a` avoided one.
20. **`OBS-19` rides on `TRANSPORT-13` (boundary 20).** `8c`'s, via `DEF-41`. `8a` drops headers under
    `TRANSPORT-11` and logs each at verbose, which is a *different* rule over a *different* set — the
    headers the transport manages, not the headers the native grammar rejects — and `8a` ships no
    three-mode policy object.

---

## Cross-cutting constraints that bite `8a` specifically

- **`Thread::Mutex` is per-fiber-owned and non-reentrant.** Two latches, both holding the mutex across
  the flag flip and nothing else (`concurrency-and-async/c0fab747`). The `ResponsePump`'s is the one that
  would deadlock if written the obvious way: its release closes a queue, closes a socket and joins a
  thread, and a lock held across any of the three would park two fibers of one thread under a
  `Fiber.scheduler`.
- **An abandoned `Enumerator` never runs its `ensure`.** §7.1's rule — the engine owns the resource in
  its own scope and exposes `#close` — is exactly what `R1` implements: the connection lives on the
  `ResponsePump`, not inside a block handed to a caller, and `8a` builds no `Enumerator` and yields no
  block that owns a socket.
- **`Fiber[:key]`, never `Thread.current[:key]`.** `8a` writes neither. The pump's producer thread
  inherits the caller's `Fiber[]` by construction (phase 4's `observability/698552b4`), which is why
  `8a` needs no diagnostic-context hop of its own — that is `8b`'s `ASYNC-8`–`ASYNC-12` work, and the
  fact that it is free here is worth stating so nobody builds a second one.
- **Bytes on the wire are BINARY**, and the `String#replace`-versus-`#clear` measurement is the concrete
  form of it in this gem.
- **`Regexp` timeouts are per-pattern.** `8a` compiles exactly one regexp over attacker-supplied bytes —
  `/\A[0-9]+\z/` against an inbound `Content-Length` (`R4`) — and it is anchored, character-class-only
  and linear, so it carries no `timeout:`. The reason is stated at the call site rather than left to a
  reader to re-derive, because the next regexp over an inbound header will not be.
- **`downcase` is called with no arguments.** Header folding goes through phase 1's `HeaderName`, which
  already folded at construction; `MANAGED_HEADERS` is stored pre-folded. `Dexpace/NoLocaleCaseFold`
  bites nowhere because `8a` folds nowhere.
- **`Ractor` is never load-bearing.** The `Adapter` is frozen and its members are frozen values, so it is
  incidentally shareable; the `ResponsePump` holds a `Thread` and is not, and nothing claims otherwise.
- **The bundled-gem rule does not reach the adapters — but it reaches the phase-level task.**
  `Dexpace::TransportError` lands in `dexpace-core` and may not `require` `socket`, `timeout` or
  `net/http` to name a class; it names none, because `::IOError` is a core class and every stdlib error
  it wraps arrives as an instance.
- **SPDX header and `# frozen_string_literal: true` on every file** (`NFR-13`). Worth naming because `8a`
  writes thirteen files into a gem whose content is assertions rather than domain code, and
  `Dexpace/SpdxHeader` does not care.

---

## Testing strategy

Seven groups. Three of them exist because a measured fact showed the obvious test would pass under the
bug.

1. **`RequestMapper` unit tests, against the `WireServer` and asserting the bytes on the wire.**
   `TRANSPORT-10`'s two cases as the requirement words them — "(a) body media type X with explicit
   Content-Type Y → Y on the wire; (b) same body with no explicit header → X on the wire" — plus the
   third case the requirement does not have and verified fact 5 forces: no explicit header and **no body
   media type** → `application/octet-stream`, and no warning. `TRANSPORT-11`'s clause verbatim — a bogus
   `Content-Length` and `Host` plus a pass-through header — with the assertion that the pass-through
   *survived* written as a separate test from the assertion that the framing headers were recomputed,
   because one passing while the other fails is the interesting outcome. The three auto-stamps asserted
   **absent**. `DEF-25`'s re-validation asserted by constructing a forged request through
   `Request.send(:new, …)` carrying a CRLF header name — the exact hole §10.10 admits — and asserting the
   adapter raises before any byte reaches the socket.
2. **`ResponseMapper` unit tests.** `TRANSPORT-24`'s clause with a `520` and a body, plus a `499`;
   `TRANSPORT-14`'s clause with an obs-text value preserved, a control-byte value dropped, a non-ASCII
   name dropped, and the body still reading in both drop cases; multi-valued `Set-Cookie` surviving as
   two values, which is the assertion that fails if anyone reaches for `#[]` or `#each_capitalized`
   (verified fact 6); `R4`'s four `Content-Length` cases; a malformed `Content-Type` becoming `nil`.
3. **`ResponsePump` tests, and this is the group `R1` is answerable to.** Lazy delivery against the
   dribble script, asserting the head arrives before the second chunk is written — with a **time
   assertion**, because a pump that buffered would pass every content assertion. `TRANSPORT-25`'s own
   clause: a multi-megabyte body round-tripped byte-exactly, and the connection observed closed **from
   the server's side** after `Response#close`. Close mid-stream with the producer blocked on a socket
   read, asserting the close returns promptly and the producer is dead. Close with the producer blocked
   on a queue push. Double close. Close before any read. A producer failure after the head, asserting it
   surfaces on the consumer's thread as a `Dexpace::TransportError` whose `#cause` is the stdlib error
   **and whose `#cause` was not acquired from the consumer's in-flight exception** — the `raise error,
   cause: nil` assertion `pipeline/f02559b9` describes, written with an unrelated exception deliberately
   in flight, which is the only way it can fail.
4. **`Failures` tests.** Each family in the wrap list mapped to `Dexpace::TransportError` with
   `#retryable?` true and the original as `#cause`; `TRANSPORT-4`'s clause — a short timeout against a
   slow server, asserting the retryable type **and a clear cancellation flag afterward**;
   `TRANSPORT-3`'s clause — a mid-call cancellation followed by a transport failure, asserting the
   interrupt type rather than the retryable one and the cancellation signal still observable; and the
   negative, that `Dexpace::StreamError` and `Dexpace::ClosedError` pass through unwrapped.
5. **Lifecycle tests.** `TRANSPORT-15`'s two sides: `.using(client)` closed, then the client used again
   successfully; `.build` closed, then a send raising `Dexpace::ClosedError`. `TRANSPORT-16`: close
   several times, stable state, and a pre-existing cancellation flag still set afterwards.
   `TRANSPORT-29`'s clause as a real concurrency proof — many concurrent calls through one transport with
   each response matched to its own request, which verified fact 9 shows is a test that **fails** against
   a shared client and is therefore worth writing.
6. **The conformance suite's own tests, in `gems/dexpace-conformance/test/`.** The suite is code and gets
   tested like code: an assertion that passes, one that raises `Failure`, one that raises `Vacuous`, one
   that raises something else, and a waived one, each landing in the right `Result` status; a `Report`
   whose `#to_s` names a waived ID; the `WireServer`'s counters; and — the test that matters — a
   **deliberately non-conforming** fake transport that fails a named assertion, proving the suite detects
   rather than merely runs. `DEF-29` is not picked up, so the fake is the gem's own and phase 2's stay
   where they are.
7. **`gems/dexpace-transport-net_http/test/` runs the conformance suite** through `MinitestDriver`, with
   one waiver (`TRANSPORT-28`'s zero-copy clause) and the three vacuity expectations (`TRANSPORT-18`, and
   the two cross-references to `TRANSPORT-12`/`TRANSPORT-13`) asserted as `:vacuous` rather than allowed
   to pass.

**Three tests that exist because a measured fact demands them:**

- **A body-bearing `POST` under `ruby -w` with `Warning.warn` overridden to raise**, asserting no
  warning. Verified fact 5: without the explicit `Content-Type` this is a red build, and the failure
  would otherwise appear in whichever suite happened to `POST` first.
- **A cancellation delivered under a blocked read, asserting the call raises rather than completing.**
  Verified fact 3: with `max_retries` left at its default the call returns `200`, so the naive assertion
  ("the error is a cancellation") is *skipped entirely* by the bug — the call never raises. The assertion
  has to be on the outcome, not on the exception class.
- **`PAGE-36`'s per-call-options test, in `dexpace-conformance`**: the same transport driven **twice in
  sequence** with different `RequestOptions`, each bounded by its own timeout. It is not `TRANSPORT-5`'s
  clause, and `7c`'s reason is why it is a separate test: "otherwise a caller's timeout/retry policy
  silently fails to govern pages 2..N", which a single-call test cannot see.

**No test allocates a multi-megabyte body more than once**, and the 4 MiB round trip is the one that
does; it ran in 95 ms in the prototype. **No test sleeps to synchronise** — every wait is a queue pop or
a bounded join with an assertion on the outcome, because `testing/4ef070df` requires order independence
and a sleep-based test is order-dependent on machine load.

---

## The interface surface later phases may cite

| Consumer | What it gets, and the obligation |
|---|---|
| **`8b`** | **Nothing, and that is the contract.** `dexpace-async-thread` needs no socket, no wire fixture and no real adapter; phase 2's `FakeTransport` drives every `ASYNC` clause it owns. If `8b` lands second it writes the composed `Transport.async_over(net_http, executor: pool)` test, which is the charter's convergence point 2 and belongs to whichever lands second |
| **`8c`**, on the harness | `Dexpace::Conformance::TransportSuite.run(build:, borrow:, waive:)`, `WireServer`, `Scripts`, `Assertion`/`Result`/`Report`, and both drivers. `8c` adds a **driver and seven assertions**, and forks nothing (`R16`). **The suite contract — twelve clauses, merged 2026-09-12 from `8a`'s original five and `8c`'s own nine** — is under `R16` → *The suite contract*, so `8c` can meet it without reading `8a`'s code, and `8c`'s design cites that section by path instead of carrying a second list |
| **`8c`**, on `Configuration::Keys::REQUEST_TIMEOUT` | The same key, read the same way. A second spelling would make one caller setting govern one transport |
| **`8c`**, on `TRANSPORT-18` | The row stays `8a`'s. `8c` **reports** whether the re-subscribable-producer antecedent is live on `async-http` (its own `R14`); if it is, `8a`'s row gains a sentence rather than `8c` gaining a row |
| **`8c`**, on `OI-36` | `R6`'s answer and its four rejected routes, so `8c` does not re-derive them. The tracer is unwired on both adapters for the same reason; the **logger** is a constructor keyword on both |
| **`8c`**, on `TRANSPORT-12`/`TRANSPORT-13` | `8a`'s two cross-reference rows, stating that both are vacuous on `Net::HTTP` — it rejects no model-valid name — so `8c`'s rows are the only ones and `DEF-41` is picked up there |
| **Phase 9**, on `DEF-22` | The assertion protocol as the shape every later suite extends: `Assertion` carrying its IDs as data, five `Result` statuses with `:vacuous` among them, and waivers by requirement ID. Phase 9 adds suites; it owns neither the gemspec nor the release |
| **Phase 9**, on `SEAM-12`, `SEAM-14`, `SEAM-15` | The three lifecycle assertions §9.3 names, already written and already driven by an adapter — so the phase-2 rows that are ⏳ "because this phase ships none" have an implementation to point at |
| **Phase 9**, on `OBS-21` and `OBS-25` | `RecordingSpan` and `Allocations`, with `5b`'s `R8` rule encoded in `.delta`'s signature |
| **Phase 9**, on `XCUT-11` | `Adapter` as a frozen, effectively-immutable shared instance whose only mutable state is `Closeable`'s latch, and the measurement (verified fact 9) that shows what the alternative costs |
| **Phase 10**, on `DEF-10` | `TRANSPORT-28`'s third clause and `TRANSPORT-30`, both ⏳ with their reasons measured rather than assumed |
| **A downstream adapter author** | `Dexpace::Conformance::TransportSuite` as the thing to run, and `R16`'s **suite contract** — twelve clauses, merged 2026-09-12 from `8a`'s five and `8c`'s nine — as the contract to meet. That is the whole reason the gem is published from day one (§9.3) |

---

## Deviation Ledger

**Numbering starts at `P8-1`, and the block `P8-1`–`P8-19` is reserved for `8a`.** **`P8-20`–`P8-35` is
reserved for `8b` and `P8-36`–`P8-50` for `8c` — corrected in place 2026-09-12, with the correction
stated.** This sentence read "`P8-20`–`P8-39` … and `P8-40` onward for `8c`", which is one of three
mutually inconsistent band statements the three concurrent designs each wrote. The charter now fixes the
allocation once, under its own *Deviation Ledger* (`8a` `P8-1`–`P8-19`, `8b` `P8-20`–`P8-35`, `8c`
`P8-36`–`P8-50`; used: `P8-1`–`P8-14`, `P8-20`–`P8-25`, `P8-36`–`P8-40`), and this document cites it
rather than restating a fourth version. Nothing was renumbered: `8a` uses `P8-1`–`P8-14`, which is inside
its band under every version of the sentence. The three sub-phase designs were written **concurrently**
in the same working tree, so a shared "next free number" would have had two documents taking the same
one; a ledger id is cited from source comments and tests and can never be renumbered. Reserving blocks is
phase 5's precedent (`P5-1`–`15`, `16`–`39`, `40`+) and the gap is the visible cost, preferred to a
collision. No `P8-<n>` exists anywhere in `docs/` today except as a placeholder in the charter's `R1`,
`OI-35` and Deviation Ledger prose, verified 2026-09-11. Each row is consolidated into design §10 and
audited by `docs/deviations.md`.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P8-1 | **The response body is streamed through a per-response producer `Thread` over a `Thread::SizedQueue(1)`**, not through design §3.2's block-scoped `Net::HTTPResponse#read_body` construction | `SEAM-11`, `TRANSPORT-25`, `TRANSPORT-19`; design §3.2 (`:167-171`); `transport-adapter/d16c7444`; `OI-35`; verified facts 10 and 11 | §3.2 says the block-scoped construction satisfies `SEAM-11` and `TRANSPORT-25` "**literally**". Measured, it satisfies neither: `Net::HTTPResponse#reading_body` ends with `self.body`, so the block form buffers the whole body unless the block reads, and a later `read_body` raises `IOError: … called twice`. Keeping the block open needs a coroutine. A `Fiber` works and is **rejected on a fact the charter does not name**: `Fiber#resume` from a second thread raises `FiberError: fiber called across threads`, which breaks `Transport.async_over(net_http, executor: pool)` — this phase's own convergence point 2 — and narrows `TRANSPORT-29`'s "confined to the returned response graph" to "confined to one thread". A `Thread::SizedQueue` is poppable from any thread. Measured: head at 4 ms against a 400 ms dribble, 4 MiB byte-exact, close mid-stream in 1 ms, no stranded thread |
| P8-2 | **`Accept`, `User-Agent` and `Accept-Encoding` — the three headers `Net::HTTPGenericRequest#initialize` stamps — are deleted, so the wire carries the caller's header set and nothing else** | `HTTP-6`, `TRANSPORT-10`, `TRANSPORT-11`; verified facts 4 and 13 | `HTTP-6` makes the four-member `Request` the whole truth about a request, and a transport that adds three headers the caller never wrote makes it false in a way no test of the model can see. The requirement's drop set is about headers the client *computes*; these are headers it *invents*, which is worse, and the requirement does not name them only because the reference client does not invent them. Measured, all three are plain `delete`s and a stripped request reaches the wire as `GET / HTTP/1.1` plus `Host` |
| P8-3 | **`decode_content` is turned off unconditionally**, so a `Content-Encoding` response is delivered compressed with its headers intact | `TRANSPORT-24`, `TRANSPORT-25`, `TRANSPORT-27`; verified fact 13 | Left at its default, `Net::HTTP` delivers a gzip response **already decompressed**, with `Content-Encoding` **removed** and `Content-Length` **rewritten** to the decoded length. That is not the response the server sent, and `TRANSPORT-24`'s "surfaced faithfully", `TRANSPORT-25`'s byte-exact round trip and `TRANSPORT-27`'s length mapping all describe the one that was. The SDK is a toolkit that maps; content-coding policy is the caller's, expressed as a header. The cost — no compression unless the caller asks — is documented at the adapter and is one header to reverse. The switch is `req["Accept-Encoding"] = v` followed by a conditional `delete`, which leaves the flag `false` either way |
| P8-4 | **A `Content-Type` is set on every body-permitted method, body or not**, defaulting to `Dexpace::Transport::NetHTTP::DEFAULT_CONTENT_TYPE` = `application/octet-stream` | `TRANSPORT-10`, `TRANSPORT-26`; `NFR-7`; phase 0's two warnings-fatal mechanisms; verified fact 5 | Two reasons, and either alone suffices. `Net::HTTPGenericRequest#supply_default_content_type` warns through `Warning.warn` under `$VERBOSE`, phase 0's shared test case overrides `Warning.warn` to **raise**, and `#set_body_internal` gives every body-permitted method a body — so a body-less `POST` would fail this repository's own build. And what it stamps is `application/x-www-form-urlencoded`, a claim about the payload that a server will act on; `application/octet-stream` is RFC 9110's own default for an unknown body and the one value that claims nothing. Two escapes were available and both are rejected: suppressing the warning process-globally, for the reason the port refuses `Regexp.timeout` — a library must not mutate a host global — and phase 0's `NFR-7` warning allowlist, whose starting state is **zero entries** and whose purpose is a warning the port cannot prevent, not one it can stop emitting by setting a header. The allowlist would not even work: phase 0's second mechanism appends `-w -W:deprecated` to `RUBYOPT` in a subprocess and scans stderr for `warning:`, which the `Warning.warn` override does not reach |
| P8-5 | **`RequestOptions#timeout` is a *total per-call budget*** carried as a monotonic deadline and refreshed into `open_timeout`, `write_timeout` and — after every chunk — `read_timeout`, rather than one value assigned to three per-operation knobs | `TRANSPORT-5`, `TRANSPORT-6`; `IO-40`; design §8.3; `resource-management/d1f16cad`, `/ed29d0f5`; verified fact 8 | `TRANSPORT-5`'s own conformance clause is "assert each is bounded by **its own value**", which is a statement about the call. Assigned per-operation, a call with `timeout: 5` is bounded by nothing: `read_timeout` is consulted per read, so a trickling body multiplies it by the chunk count — the exact failure `ed29d0f5` describes. The refresh is possible because `Net::HTTP#read_timeout=` does `@socket.read_timeout = sec if @socket`, measured to take effect on the next read from inside a `read_body` block. An expired budget raises before touching the socket, because `0` means *poll once* on this client and not *no timeout*. **The configured tier reads `Dexpace.configuration.duration(Keys::REQUEST_TIMEOUT, default: DEFAULT_TIMEOUT_SECONDS)`** — 5a ships no `#float` — so `CFG-7`'s bare-number-is-milliseconds grammar governs that tier and `REQUEST_TIMEOUT=30` is thirty *milliseconds*, documented in `Adapter`'s YARD (`R3`) |
| P8-6 | **A non-`nil` per-call `timeout` against a *borrowing* transport raises `Dexpace::InvalidArgumentError`** rather than being applied or ignored | `TRANSPORT-5`, `XCUT-22`, `SEAM-11`, `PAGE-36` | `TRANSPORT-5` requires the override to apply "leaving the shared native client untouched"; on a caller-supplied `Net::HTTP` those two clauses are contradictory, because the knobs are instance state. `SEAM-11` sanctions a transport that *ignores* options — but a transport that honours them on one construction and drops them on another is a silent wrong answer in exactly the place `PAGE-36` exists to prevent ("a caller's timeout/retry policy silently fails to govern pages 2..N"). Raising names the conflict and the fix; ignoring hides both |
| P8-7 | **No `OBS-28` transport milestone is emitted, and `DEF-42` stays open on this half**; the `Instrumentation::Logger`, by contrast, is wired through a constructor keyword | `OBS-28`, `OBS-29`, `TRANSPORT-11`, `TRANSPORT-14`; `DEF-42`, `OI-31`, `OI-32`, `OI-36`; `PIPE-11`; `NFR-4` | `OBS-29` requires one tracer per logical **operation**; the seam is three arguments, `NFR-4`-locked, and an adapter in another gem has no operation boundary to key on. A constructor keyword gives one tracer per adapter lifetime; widening `RequestOptions` is a phase-1 surface `P5-33` states as settled; and carrying it in `Fiber[]` puts a live mutable object into a slot `observability/65191069` measured to be **shared across every descended thread and fiber** — `XCUT-11` with no synchronisation — while making the transport's behaviour depend on whether a step ran. A logger has none of those problems: no per-operation identity requirement, no ambient carriage, and `Logger::NULL` as the value a caller with none holds. The asymmetry *is* `OI-36` |
| P8-8 | **`Dexpace::Conformance::Failure` is a `::StandardError` and does not include `Dexpace::Error`** | `DEF-22`; design §9.3; phase 1's `P1-2`; `error-handling/d2eadac4` | Phase 1 made `Dexpace::Error` a module every SDK error includes so a caller can `rescue Dexpace::Error` broadly. A conformance failure is a **test result**, not an SDK error; including it would make that rescue catch one, and an adapter author's `rescue Dexpace::Error` around a send would swallow the assertion that the send was wrong. §9.3 names the class and says nothing about its ancestry, which is why this is a decision rather than a reading |
| P8-9 | **The conformance wire fixture speaks plaintext only and exercises no connect timeout**, and the report says so | `TRANSPORT-4`, `TRANSPORT-20`; design §9.3; verified facts 7 and 16 | A self-signed TLS fixture is portable in principle and brittle across three interpreters and two OpenSSL majors; the property that matters — the adapter assigns no `verify_mode`, so `SSLContext#set_params` supplies `VERIFY_PEER` and `verify_hostname` — is a structural assertion in the adapter's own suite and needs no socket. A connect timeout has no portable local fixture at all (a listener that accepts slowly is not expressible), so `TRANSPORT-4`'s read half and `TRANSPORT-20`'s refused half are scripted and the open half is a unit test. Both omissions are printed in the report's preamble, because a third-party author who reads a green run as "fully conformant" is the failure this gem exists to prevent |
| P8-10 | **The borrowing construction *asserts* `client.max_retries.zero?` at construction rather than setting it** | `TRANSPORT-1`, `TRANSPORT-2`, `XCUT-22`; verified facts 2 and 3; `OI-34` | `TRANSPORT-2` scopes the disable to an "SDK-managed" transport, and `XCUT-22` forbids mutating a caller's client — so on a borrowed client the adapter may neither set the knob nor leave the hole. Refusing the construction closes it loudly, mutates nothing, and names the requirement in the message. The hole is not hypothetical: measured, a default `max_retries` turns a cancelled call into a completed `200` |
| P8-11 | Public **constants** design §3.2 and §9.3 do not name: `Dexpace::Transport::NetHTTP::Adapter`, `::MANAGED_HEADERS`, `::DEFAULT_CONTENT_TYPE`, `::DEFAULT_TIMEOUT_SECONDS`, `::MIN_TIMEOUT_SECONDS`, `::JOIN_DEADLINE_SECONDS`, `::REGISTRY_KEY`; `Dexpace::Conformance::Failure`, `::Vacuous`, `::Assertion`, `::Result`, `::Report`, `::WireServer`, `::Scripts`, `::TransportCase`, `::TransportSuite`, `::MinitestDriver`, `::RSpecDriver`, `::RecordingSpan`, `::Allocations`; `Dexpace::Configuration::Keys::REQUEST_TIMEOUT`; and the RBS interface `Dexpace::Conformance::_Transport` | `NFR-4`; `NFR-11`; `api-design/b0e18938`; `P1-1`, `P2-11`, `P3-14`, `P4-24`, `P5-1`, `P5-40`, `P6-1`, `P7-2` precedent | `NFR-4` locks a name before it locks a signature. §3.2 names exactly one Ruby identifier for this gem (`dexpace-transport-net_http` itself) and §9.3 names one (`Dexpace::Conformance::Failure`). Each name above is chosen for a stated reason in the object model. Two deserve naming here: **`MinitestDriver`/`RSpecDriver`** carry the suffix deliberately, because inside `module Dexpace::Conformance` a constant named `Minitest` shadows `::Minitest` for the whole namespace — 5a's `P5-3` reasoning applied to a second case; and **`Keys::REQUEST_TIMEOUT` is a `dexpace-core` constant added by an adapter sub-phase**, whose precedent is `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` in the same module, read by no core file |
| P8-12 | Public **methods** those chapters do not name: `NetHTTP.build`, `.using`, `.default`; `Adapter#call`, `#close`, `#closed?`, `#owned?`; `Failure#expected`, `#actual`, `#requirement_ids`; `Vacuous#reason`; `Assertion#ids`, `#name`, `#body`, `#call`; `Result#assertion`, `#status`, `#detail`; `Report#passed?`, `#failures`, `#vacuous`, `#waived`, `#errors`, `#to_s`; `WireServer.start`, `#port`, `#requests`, `#connections`, `#closed_connections`, `#await_closed_connection`, `#close`; `TransportCase#transport`, `#borrowed_transport`, `#wire`, `#request`; `TransportSuite.assertions`, `.run`; `MinitestDriver.conformance`, `RSpecDriver.conformance`; `RecordingSpan`'s recording surface; `Allocations.delta` | `NFR-4`; `api-design/b0e18938`; `P4-23`, `P5-2`, `P6-2`, `P7-3` precedent | `NFR-4` locks a signature, not only a name. Two deserve naming. **`.using` is a second construction entry point**, and it exists because §3.7 makes ownership a construction-time fact and phase 2's `SEAM-15` rule keys the post-close behaviour off it; a single `.build(client: nil)` would make ownership an argument value, which `P3-11` already rejected for `BufferedSource`. **`TransportSuite.run`'s `borrow:` keyword is optional**, so an adapter with no borrowing construction supplies nothing and `TRANSPORT-15`'s borrowed half records `:vacuous` rather than failing |
| P8-13 | **`MANAGED_HEADERS` extends `TRANSPORT-11`'s named minimum with seven hop-by-hop names** — `connection`, `keep-alive`, `proxy-connection`, `te`, `trailer`, `upgrade`, `expect` | `TRANSPORT-11`; RFC 9110 §7.6.1; verified fact 4 | The requirement itself says "plus any the native client rejects outright … The exact drop set is transport-specific (OkHttp does not drop Connection)", so an extension is inside the requirement rather than beside it. Six of the seven are hop-by-hop headers, which belong to the connection, and the connection is the transport's. Two carry their own reason: **`expect`**, because `continue_timeout` is `nil` by default so `wait_for_continue` never runs and `Expect: 100-continue` would hang against a server that waits; and **`connection`**, because this adapter builds and closes a client per call, so a caller-set value either agrees with what it already does or contradicts it |
| P8-14 | **Phase 0's require-allowlist denylist gains a per-gem scope**, so `dexpace-conformance`'s `lib/` may `require "socket"` | `SEAM-1`, `SEAM-2`, `NFR-2`; phase 0's `gates:require_allowlist` (`:455-475`); verified fact 17 | The denylist entry for `socket` carries its reason — "`SEAM-1`/`SEAM-2`: core embeds no concrete transport" — and that reason does not reach `dexpace-conformance`, which embeds no transport either: it embeds a **server**, which is the fixture §9.3 requires and which exists precisely so the suite depends on no transport. `socket` is **non-gemified stdlib** (a `.so` with no gemspec), so it can never migrate to the bundled set and the bundled-gem half of the rule has no subject. The amendment is a named per-gem exception with its reason attached, in the style phase 0 already uses for each denied name — not a removal |

**Three errata against this document, found by its own plan and corrected in place on 2026-09-12 rather
than numbered.** None is a deviation from the reference contract — each is a sentence this document got
wrong about a *predecessor's shipped code* or about Bundler, so correcting it changes what `8a` must do
and changes nothing about what the port claims, which is the same test `OI-34` and `OI-35` are filed
under. (1) **`Configuration#float` does not exist** — `R3`'s configured tier reads `#duration`, and
`CFG-7`'s bare-number-is-milliseconds grammar rides along; folded into `P8-5`'s row above. (2)
**`MediaType.parse` raises rather than returning `nil`** — `R4` step 3 now owns the downgrade through a
`rescue Dexpace::InvalidArgumentError`. (3) **No clean-bundle smoke path can prove `net-http` is
declared rather than merely present**, because Bundler does not gate a default gem by declaration —
*From phase 0* now says so, and names `gates:require_allowlist` as the gate that does prove it. A fourth
finding is not an erratum against this document at all but a **latent phase-0 defect** it surfaced:
`clean_bundle_check` writes a one-line `Gemfile` that cannot resolve any adapter's `dexpace-core` path
dependency, fixed by `8a`'s plan for all five adapter rows.

---

## Deferrals filed by phase 8a

**None new.** Every one of `8a`'s 23 IDs is implemented here, one with a clause ⏳ against an existing
row (`TRANSPORT-28`) and one ⏳ whole against the same row (`TRANSPORT-30`). No ID cluster moves out of
`8a`'s scope to a later phase.

### Deferral-register sweep

`8a`'s delta against the charter's whole-register sweep, which covered every row once and is not repeated
here. As with every predecessor, this document **states** each disposition and `8a`'s **plan performs**
the register edit.

- **`DEF-22` — picked up and closed by `8a`.** Its condition names this phase in as many words: "phase 8,
  which owns this gem's gemspec, its version and its first release; phase 9 adds the remaining suites."
  `8a` writes `Dexpace::Conformance::Failure`, the callable assertion protocol with its five result
  statuses and its ID-keyed waivers, the §9.3 `TCPServer` fixture, the transport suite, and both thin
  drivers (`R7`). `Status` moves to `picked-up (<date>, phase 8a)`. The row's `Cites:` line is currently
  `none` and should become `NFR-2`, `NFR-4`, `SEAM-12`, `SEAM-14`, `SEAM-15`, `TRANSPORT-1`–`30`,
  `OBS-21`, `OBS-25`, `PAGE-36`.
- **`DEF-25` — picked up by `8a` for this adapter's half.** Its condition: "phase 8 … **in each adapter's
  dispatch path**". `8a` calls `Dexpace::HeaderSyntax.validate_name!` and `.validate_outbound_value!` over
  every outbound header immediately before the native request is built, and the forged-request test
  proves the call site rather than asserting the module. The row's `Status` moves at the **phase-level
  PR**, once `8c`'s call site exists too; `8a`'s checklist carries its own row.
- **`DEF-29` — condition met, action declined; `8a` marks it UNSCHEDULED with phase 8a named.** Its
  condition — "the first consumer outside `dexpace-core`" — is met three times over in phase 8. Its
  *action* is the literal move named in its title, and `8a` declines it on the charter's argument, which
  this document confirms from inside the implementation: moving
  `gems/dexpace-core/test/support/`'s three fakes into `dexpace-conformance` would make `dexpace-core`'s
  own suite depend on a gem that depends on `dexpace-core` — a development-dependency cycle between the
  workspace's two most load-bearing gems — for no gain core's suite can see. Per the roadmap's retirement
  rule a met-but-declined condition is **UNSCHEDULED with the phase named**, not `picked-up`. The row's
  *purpose* is met by a different route and the UNSCHEDULED note says so: `dexpace-conformance` publishes
  its **own** doubles (`RecordingSpan`, `Allocations`, `WireServer`, and the non-conforming transport its
  own suite drives), which is what a third-party adapter author actually needs, and core keeps the three
  it already has.
- **`DEF-23` — untouched, and the condition was checked rather than assumed.** "When a gem's test support
  becomes production-quality code worth checking — phase 8's conformance helpers at the earliest."
  `8a` places the assertion objects and the `TCPServer` fixture in **`lib/`** (`R7`), where phase 0
  already gave `dexpace-conformance` its own Steep target, so they are checked as production code
  already. Nothing `8a` writes under `test/` is production-quality code worth a seventh target. The
  condition is still not met and the row stays `deferred`.
- **`DEF-3` — `BODY-12` clause 2 is dispositioned and `8a` marks it UNSCHEDULED with phase 8a named.**
  The row targets phase 8 explicitly. Verified fact 14: `send_request_with_body_stream` writes to a
  `Net::BufferedIO`, whose `is_a?(::IO)` is `false`, so the kernel path is unreachable without bypassing
  the library's write path — which would mean writing the request framing, the chunked encoder and the
  `100-continue` handshake by hand. Condition met, action declined, phase named. **`BODY-36`'s half is
  untouched.**
- **`DEF-10` — untouched.** Its condition is "revisit when a transport adapter **beyond the two MVP
  transports** ships"; phase 8 ships exactly those two, so it is **not** UNSCHEDULED. `TRANSPORT-30` is
  carried ⏳ whole against it and `TRANSPORT-28`'s zero-copy clause ⏳ as a clause (`R5`).
- **`DEF-41` — untouched by `8a`, and `8a` supplies the cross-reference the row's correction needs.**
  The row is `8c`'s: `TRANSPORT-12`'s and `TRANSPORT-13`'s antecedent is a native wire grammar stricter
  than the SDK model's, and `Net::HTTP` has none — it wrote `Bad name: v` to the wire rather than
  rejecting it. `8a`'s checklist carries both IDs as **stated cross-references** rather than silent
  absences, which is what the charter's amendment to the row (`TRANSPORT-12`, not `TRANSPORT-8`) needs on
  this side.
- **`DEF-42` — `8a`'s half is declined with a reason and the row stays open.** `R6`. The row's own text
  is "the transport-milestone group follows in phase 8 with the first adapter"; `8a` is that adapter and
  finds no route by which it can reach a per-operation `HTTPTracer`. The row does not close and does not
  become UNSCHEDULED — `OI-36` is the finding, and a route could exist after a deliberate `RequestOptions`
  widening, which is a phase-1 surface decision no sub-phase should take alone.
- **`DEF-31` — untouched by `8a`.** `SEAM-25`'s lifecycle event is `8b`'s; `8a` owns no executor and emits
  no `Events::INSTRUMENTATION_SHUTDOWN`. `8a`'s contribution is the harness in which `8b`'s "close twice
  → executor shut once, one event" assertion is written.
- **`DEF-18`, `DEF-30`–`DEF-40` — untouched.** `DEF-30` is worth one sentence because `8a` must not meet
  it by accident: presence-gated auto-activation is permitted "for instrumentation only" and "no transport
  or codec adapter may ever use it". `dexpace-transport-net_http` registers **explicitly** through phase
  2's `Registry#register` and activates on nothing; `dexpace-conformance` registers into no seam at all.
- **`DEF-2` — untouched, and the charter asked `8a` to check.** Its floated target is "the first consumer
  that constructs a conditional request … a `dexpace-conformance` fixture" is one of three candidates.
  `8a` builds that gem and the answer is **no**: the `WireServer` *answers* requests rather than making
  them, and the suite's own requests carry no `If-None-Match` or `If-Modified-Since` — `TRANSPORT-24`'s
  `304` script returns the status without the client having conditioned on anything, which is the
  correct shape for a transport assertion and would be the wrong shape for an `HTTP-48` one. The charter
  expected this and the check confirms it.
- **`DEF-1`, `DEF-4`–`DEF-9`, `DEF-11`–`DEF-17`, `DEF-19`–`DEF-21`, `DEF-24`, `DEF-26`–`DEF-28`,
  `DEF-32`–`DEF-38` — untouched**, all either closed by an earlier phase, targeted at `8b`/`8c`, or
  riding on a post-v1 gem. Two are worth naming because a reader will wonder: **`DEF-19`/`DEF-20`** are
  release-gated and phase 8 performs the workspace's first gem release, which `8a`'s gem is the subject
  of — neither is met by `8a` alone and neither is marked; and **`DEF-21`** is the version-skew guard
  whose first real adapter registration lands here.

---

## The findings proposed for the registers

**Five, described here for a human to file. None is acted on by this document and no register file is
edited by it.** Four target `docs/open-items.md` and **carry numbers as of 2026-09-12**; the fifth targets
`docs/first-release.md` and carries none, because it is a release blocker rather than an open item and
`OI-<n>` is not that register's namespace.

**The numbers, and why they are safe to write down now.** This section previously left them blank, on the
ground that the charter's `OI-34`–`OI-37` and `8c`'s `OI-38`–`OI-41` were unfiled and concurrent and a
number chosen from three documents at once is a collision waiting to be renumbered. That reasoning was
right while the three designs were being written independently and is now spent: all three sets are
written and none has moved, so the block after both is known. **`8a`'s four are `OI-42`–`OI-45`, and
`8b`'s three follow at `OI-46`–`OI-48`** — 8a before 8b, in sub-phase order, so the ordering rule is
statable rather than incidental. **A filer still checks before pasting**, with
`ruby .claude/skills/housekeeping/probe.rb --only citations`: the register's own stated `next id` is
`OI-34`, and fifteen numbers (`OI-34`–`OI-37` from the charter, `OI-38`–`OI-41` from `8c`,
`OI-42`–`OI-45` from here and `OI-46`–`OI-48` from `8b`) are cited across phase 8 with no row yet. The probe reports each as a dangling
citation until the rows are pasted; that is the expected state and not drift. **If any of the fifteen is
filed under a different number, every one after it shifts and the shift is mechanical** — nothing in
phase 8 cites an `OI-4x` from source code, only from these documents.

Each row below is written in `docs/open-items.md`'s own item format — `### OI-<n> — <title>`, then
`Opened` (the register's found-by field: a date and the phase that found it), `Status`, `Cites`, the
body, and a `**Resolution:**` line — so filing is a paste rather than a re-derivation.

**Target register: `docs/open-items.md`. Proposed id `OI-42`.**

> ### OI-42 — `net-http`'s connect phase uses `Timeout.timeout`, the primitive design §8.3 bans, and the cop that enforces the ban cannot see it
>
> - **Opened:** 2026-09-11, phase 8a design
> - **Status:** open
> - **Cites:** ASYNC-3, PIPE-33, XCUT-13, TRANSPORT-4, NFR-2, DEF-18

**`net-http`'s connect phase uses `Timeout.timeout`, the primitive design §8.3 bans, and the cop that
enforces the ban cannot see it.** `/usr/lib/ruby/3.4.0/net/http.rb:1657` is
`s = Timeout.timeout(@open_timeout, Net::OpenTimeout) { TCPSocket.open(conn_addr, conn_port, @local_host, @local_port) }`.
§8.3's prohibition is stated as binding "every gem in this repository" and phase 0 mechanises it as
`Dexpace/NoThreadInterrupt` over this repository's own `lib/`, so a library dependency using it is
outside both the words and the scan. The hazard §8.3 names — an asynchronous interrupt landing "inside an
`ensure` block that is releasing a pooled connection" — is **not** reachable through this particular use:
the interrupt can only land during `TCPSocket.open`, before any SDK object holds a socket, and the
library converts it into a typed `Net::OpenTimeout` rather than letting a bare `Timeout::Error` escape.
So the port's guarantee is narrower than §8.3's sentence and is still true of everything it claims. Worth
a row because the sentence is absolute, because a reader auditing the ban will grep `lib/` and find
nothing, and because the same question will be asked of `async-http`'s dependency closure in `8c`. What
would resolve it: §8.3 gaining one clause scoping the prohibition to code this repository writes, the
next time §8 is deliberately amended by a human. Nothing is broken today because nothing is implemented.
>
> **Resolution:** *(open)*

**Target register: `docs/open-items.md`. Proposed id `OI-43`.**

> ### OI-43 — design §9.3 calls Minitest a default gem; it is a bundled gem, and §2.4 is built on exactly that distinction
>
> - **Opened:** 2026-09-11, phase 8a design
> - **Status:** open
> - **Cites:** NFR-2, NFR-17, SEAM-1, DEF-22

**Design §9.3 calls Minitest a default gem; it is a bundled gem, and §2.4 is built on exactly that
distinction.** §9.3's argument for choosing Minitest over RSpec is that "**it ships with the interpreter
as a default gem**, so the same argument §2.4 makes about `base64` and `logger` applies to the test
framework". Verified on 3.4.10: `Gem::Specification.find_by_name("minitest").default_gem?` is `false`,
its gem directory is not the interpreter's, and `Gem::BUNDLED_GEMS::SINCE` does not name it either
(the table lists only gems that *became* bundled at a known version). Minitest is **bundled** — available
with the interpreter, and requiring an explicit `Gemfile`/gemspec entry under Bundler, which is the very
property §2.4 spends a page warning about. The **conclusion** survives unchanged and is the reason this
is a row rather than a correction to a decision: an adapter author can still run the suite with nothing
extra installed, and `dexpace-conformance` still declares nothing, because `8a`'s two drivers reference
`::Minitest` and `::RSpec` at call time and `require` neither. What it changes is one sentence in a frozen
chapter and one line in the root `Gemfile`, which must list `minitest` explicitly. Nothing is broken
today because nothing is implemented.
>
> **Resolution:** *(open)*

**Target register: `docs/open-items.md`. Proposed id `OI-44`.**

> ### OI-44 — the require-allowlist's denylist has no per-gem scope, so a denial written for core's reason reaches a gem the reason does not describe
>
> - **Opened:** 2026-09-11, phase 8a design
> - **Status:** open
> - **Cites:** SEAM-1, SEAM-2, NFR-1, NFR-2, DEF-22

**The require-allowlist's denylist has no per-gem scope, so a denial written for core's reason reaches a
gem the reason does not describe.** Phase 0's denylist denies `socket` with the reason "`SEAM-1`/`SEAM-2`:
core embeds no concrete transport", and phase 0's adapter extension permits only "allowlisted, or under
`dexpace/`, or the single third-party gem that adapter's gemspec declares" — so `dexpace-conformance`,
which declares no third-party gem, cannot `require "socket"` even though it embeds no transport and
`socket` is non-gemified stdlib that can never become a bundled gem. The immediate case is `8a`'s
(`P8-14` amends the gate with a named per-gem exception), and the shape is general: every denylist entry
carries a *reason*, the reasons are gem-scoped, and the mechanism is not. The same question will arise
for `dexpace-transport-async_http` and `openssl`, and for any future adapter that legitimately needs a
denied name. What would resolve it: the denylist growing a scope column, so an entry reads "denied to
core and to transport adapters" rather than "denied". Nothing is broken today because nothing is
implemented.
>
> **Resolution:** *(open)*

**Target register: `docs/open-items.md`. Proposed id `OI-45`.**

> ### OI-45 — `dexpace-transport-net_http` opens a TCP (and over HTTPS a TLS) connection per request, and the corpus rule that forbids that has no note
>
> - **Opened:** 2026-09-11, phase 8a design
> - **Status:** open
> - **Cites:** TRANSPORT-5, TRANSPORT-29, SEAM-12, NFR-2, XCUT-11

**`dexpace-transport-net_http` opens a TCP — and, over HTTPS, a TLS — connection per request, and the
corpus rule that forbids that has no note.** `resource-management/4aca52f9` says "Never open one
connection per request; size connection or HTTP pools with a bounded, named constant instead", and design
§3.2 with `transport-adapter/52b448e8` requires the opposite for measured reasons this document records
(verified fact 9: a shared `Net::HTTP` under eight threads produced 128 errors and **26 responses matched
to the wrong request**). The design is right and the cost is real: every request pays a handshake, which
on an HTTPS endpoint is one round trip plus a TLS negotiation. A keep-alive pool is not reachable inside
`NFR-2`'s budget — `connection_pool` would be a second third-party declaration and `gates:gemspec_audit`
rejects it — and a hand-rolled pool in the adapter would have to answer every bounded-pool and
deterministic-teardown rule the corpus routes to `dexpace-async-thread`, in a gem that is not that one.
What would resolve it: either a note recording the resolution this document argues, or a later phase
taking a hand-rolled bounded pool with a checkout timeout as a deliberate, separately-designed piece of
work. Recorded now because the first user to benchmark the SDK against `faraday` will find this and
should find it already written down. Nothing is broken today because nothing is implemented.
>
> **Resolution:** *(open)*

**Target register: `docs/first-release.md`. No `OI-<n>`, deliberately** — `docs/first-release.md` is the
release-readiness register and `OI-<n>` is `docs/open-items.md`'s namespace; a blocker filed with an open
item's number would resolve to a row in the wrong file. It is filed as a release blocker in that file's
own shape, by the phase-level PR rather than by this sub-phase.
**A green `dexpace-conformance` run proves less than its name suggests, and the gap must be written down
before anyone publishes the gem.** `P8-9`: the wire fixture speaks plaintext only and exercises no
connect timeout, so `TRANSPORT-4`'s open-timeout half and every TLS property are asserted in
`dexpace-transport-net_http`'s own suite and not in the portable one. The line to file: **before release,
`docs/sdk-documentation/` must state what a green conformance run does and does not prove, and the
report's preamble must name the same omissions** — because a third-party adapter author whose adapter
passes is entitled to know that TLS verification and connect-timeout classification were not among the
things it passed. Cites: `TRANSPORT-4`, `TRANSPORT-20`, `DEF-22`, `NFR-2`.

**Two amendments this document proposes to findings the charter has already written out.**

- **`OI-34` gains a measurement.** The charter's row argues from `transport_request`'s source that a
  cancellation delivered by closing the socket "would be swallowed and retried". Verified fact 3 measures
  it end to end: at the default `max_retries` the cancelled call **returned `200`**; at `0` it raised.
  The row's "Three consequences, none of them cosmetic" is stronger with the number in it, and the
  measurement belongs in the row rather than only in this design.
- **`OI-35`'s "Phase 8a's `R1` decides the construction" is now answerable**, and the row's Resolution
  should name `P8-1` and the reason that decided it — which is the cross-thread `FiberError`, not the
  abandoned `ensure` the row leads with. The row's diagnosis of the chapter is unchanged and correct.

**One row explicitly does not close.** `OI-9`'s one-byte-per-read defect in `BufferedSource.wrapping`
reaches `8a`'s response path exactly as the row predicts — it is the factory the `ResponsePump` is handed
to — and it is phase 3a's code to fix, in a plan that has not executed. `8a` does not fix it and does not
route around it; the plan's first task re-reads the row.

---

## Charter follow-through — owed, and applied 2026-09-12

**One cell in `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md` was wrong and is now
corrected in place there, with the correction stated** — the roadmap's own rule, applied to the document
that delegated the decision. The paragraph below is kept as the argument that produced the correction;
the charter's `8a` scope-table cell for `TRANSPORT-27` and its `R4` paragraph both now carry it, and its
"Dispositions other than ✅" paragraph carries the matching narrowing of `TRANSPORT-28` from ⏳-whole to
partially satisfied (`R5`).

The charter's `8a` scope table says of `TRANSPORT-27`: "**Half unreachable**: a non-numeric
`Content-Length` raises `Net::HTTPHeaderSyntaxError` out of `#request` (verified fact 12). **`R4`**", and
its `R4` offers `8a` a choice between a deviation row, an expensive pre-parse, and a partial decline.
Measured under the block form this adapter uses anyway (verified fact 12 here), the head is delivered in
full and the raise comes later, from `Net::HTTPResponse#content_length`; deleting the unparseable header
before the body read makes the body read. **`TRANSPORT-27` is satisfied whole, with no deviation and no
pre-parse.** The charter's fact 12 is not wrong about what it measured — it measured `#request` without a
block — and its conclusion does not survive the block form. The cell should read:

```
| `TRANSPORT-27` | SHOULD | Unknown media type and the `-1` length sentinel. **Satisfied whole** — `8a` measured that under the block form the head is delivered before `Net::HTTPResponse#content_length` raises, so the length is parsed from the raw header and the unparseable one deleted before the body read (`R4`, resolved) |
```

and `R4`'s own paragraph should carry the same correction with a pointer to this document. `8a` writes
one file and cannot make the edit; it is owed by whoever files this design, in the same change.

**Nothing else in the charter changes.** Its `TRANSPORT-28` cell says `8a` "dispositions it — see the
sweep and `R5`", which is what `R5` above does; the narrowing from ⏳-whole to partially-satisfied is the
disposition the cell invites rather than a correction to it.

---

## The knowledge notes `8a` files

Three, drafted here; the plan's final task writes them to `docs/knowledge/notes/transport-adapter.md`,
which does not exist yet and which this document creates. Two are `## Superseded` entries, because each
contradicts a harvested rule the corpus carries faithfully from a design chapter that is wrong about the
library — the two the charter named as `8a`'s. The third is `## Reference`, because it adds a guard no
harvested rule reaches rather than contradicting one.

```markdown
# transport-adapter — notes

Hand-written. `../harvested/transport-adapter.md` is what the documents say; this file is what the
implementation found, and it wins. Each entry names the harvested entry it answers by that entry's
stable key.

## Superseded
- **`Net::HTTP` has a built-in automatic retry, it is ON by default, and a cancellation delivered by
  closing the socket is swallowed by it.** Supersedes `transport-adapter/7e8e2c60` ("TRANSPORT-1 and
  TRANSPORT-2 … are vacuous for the net_http reference adapter because Net::HTTP follows no redirects
  and retries nothing on its own"), whose **redirect half is right** — verified,
  `(Net::HTTP.instance_methods + Net::HTTP.methods).grep(/redirect|follow/i)` is `[]` — and whose
  **retry half is false**. Verified on `net-http` 0.6.0 under Ruby 3.4.10:
  `Net::HTTP.new("x").max_retries` is **1**, and `#transport_request` retries when
  `count < max_retries && IDEMPOTENT_METHODS_.include?(req.method)` on `Net::ReadTimeout`, `IOError`,
  `EOFError`, `Errno::ECONNRESET`, `Errno::ECONNABORTED`, `Errno::EPIPE`, `Errno::ETIMEDOUT`,
  `OpenSSL::SSL::SSLError` and `Timeout::Error`, where `IDEMPOTENT_METHODS_` is
  `["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE"]` — PUT and DELETE included, and the retry
  re-runs `req.exec`, so it re-writes the body. **Measured end to end rather than read out of a rescue
  list**: against a server whose first connection hangs, with a second thread calling `conn.finish`
  250 ms in, the call **returned `200`** at the default `max_retries` and raised `IOError: stream
  closed in another thread` at `0`. So `TRANSPORT-2` is load-bearing, `TRANSPORT-17`'s single-use body
  could be written twice, and `TRANSPORT-3`'s cancellation is silently swallowed — three requirements
  fixed by one line, `http.max_retries = 0`. Two clauses of the same method bound the hazard without
  removing it: `rescue Net::OpenTimeout; raise` means a connect timeout is never retried, and
  `count = max_retries` inside the `reading_body` block means the window closes once the response head
  is read; neither helps the connect-and-head phase, which is where a cancel lands. `OI-34` records the
  same finding against design §3.2, §11.18 and §12, which are frozen.
  <sub>review · `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md` · high · sha:manual-phase8a-net-http-retry</sub>
- **The block-scoped `read_body` construction buffers the whole body, and the coroutine that fixes it
  must be a `Thread` rather than a `Fiber` — because a fiber cannot be resumed from another thread.**
  Supersedes `transport-adapter/d16c7444` ("dexpace-transport-net_http issues the request inside
  Net::HTTP#request(req) { |res| ... } and exposes the response body as a BufferedSource over the
  block-scoped Net::HTTPResponse#read_body stream, satisfying SEAM-11's no-pre-buffering clause and
  TRANSPORT-25's lazy-read, cascading-close requirements"). Verified on `net-http` 0.6.0 under Ruby
  3.4.10 against a `TCPServer` that writes five body bytes, sleeps 400 ms and writes five more.
  `Net::HTTPResponse#reading_body` is `begin; yield; self.body; ensure; @socket = nil; end`, so the
  block form **buffers the whole body** unless the block itself reads, and a later `read_body` raises
  `IOError: Net::HTTPOK#read_body called twice`; `#request` with no block buffered too, returning after
  408 ms. Keeping the block open across the return of `#call` needs a coroutine, and **the fiber is
  disqualified by something other than the leak**: `Fiber#resume` from a second thread raises
  `FiberError: fiber called across threads`, so a fiber pump created on a `dexpace-async-thread` worker
  inside `Transport.async_over` cannot have its body read on the caller's thread, and `TRANSPORT-29`'s
  "confined to the returned response graph" would narrow to "confined to one thread". (An abandoned
  fiber's `ensure` also never runs, verified after three `GC.start`s; `Fiber#kill` does run it on
  3.4.10 and its availability on the 3.2 floor is unverified. Neither fact is what decides it.) What
  the SDK does instead, per phase 8a's `P8-1`: a per-response producer `Thread` over a
  `Thread::SizedQueue(1)`, drained through a `#readpartial`-shaped reader that
  `Dexpace::IO::BufferedSource.wrapping` owns; `#close` latches, closes the queue (waking a producer
  blocked on push), closes the connection (waking one blocked on a socket read with `IOError`, which
  requires `max_retries = 0` per this file's first entry) and joins with a **bounded** deadline.
  Measured: head at 4 ms against a 400 ms dribble, 4 MiB round-tripped byte-exactly in 95 ms, close
  mid-stream returning in 1 ms with the server observing the peer close, idempotent, no stranded
  thread. `OI-35` records the same finding against design §3.2, which is frozen.
  <sub>review · `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md` · high · sha:manual-phase8a-response-pump</sub>

## Reference
- **A body-bearing `Net::HTTP` request with no `Content-Type` emits a `Warning.warn` under `-w`, and
  every body-permitted method has a body whether the caller gave one or not.** Beside
  `transport-adapter/0921e946`, which states `TRANSPORT-10`'s authority rule and says nothing about
  what the library does when nobody set a type. Verified on `net-http` 0.6.0 under Ruby 3.4.10:
  `Net::HTTPGenericRequest#supply_default_content_type` is
  `warn 'net/http: Content-Type did not set; using application/x-www-form-urlencoded', uplevel: 1 if
  $VERBOSE`, called by **both** `send_request_with_body` and `send_request_with_body_stream`; and
  `#set_body_internal` is `self.body = '' if @body.nil? && @body_stream.nil? && @body_data.nil? &&
  request_body_permitted?`, so a **body-less `POST`** takes the same path and reaches the wire with
  `Content-Length: 0` and a stamped `Content-Type`. With `Warning.warn` overridden to raise — which is
  exactly what phase 0's shared test case does — the call raised under `ruby -w` and did not without
  it. This repository's gate set fails the build on warnings, so the first `POST` in any suite is a red
  build unless the adapter sets the header. Phase 8a therefore sets an explicit `Content-Type` on every
  body-permitted method, defaulting to `application/octet-stream` (`P8-4`) — RFC 9110's own default for
  a payload of unknown type, and the one value that is not a claim about the bytes, where the library's
  `application/x-www-form-urlencoded` is a claim a server will act on. Suppressing the warning
  process-globally was rejected for the reason the port refuses `Regexp.timeout`: a library must not
  mutate a host global.
  <sub>review · `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md` · high · sha:manual-phase8a-content-type-warning</sub>
```

`ruby scripts/verify_knowledge_structure.rb` must pass after the write, and
`ruby scripts/knowledge.rb --key transport-adapter/7e8e2c60` and `--key transport-adapter/d16c7444` must
each print `[overridden by notes/transport-adapter.md:…]` — which is the test that the backticked keys
were copied correctly.

---

## Reference

Paths and identifiers a plan or a later phase will need, in one place.

| Thing | Where |
|---|---|
| This design | `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md` |
| Its plan | `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance.md` |
| Its checklist | `…-phase8a-synchronous-transport-and-conformance-checklist.md`, written at execution time |
| The charter | `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md` |
| Normative chapter | `docs/product-spec/17-transport-adapter-conformance-contract.md` (51 lines) |
| Canonical text | `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md:559-588` |
| The Ruby mapping, read critically | `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.2 (`:155-188`), §3.7 (`:452-518`) |
| The conformance argument | `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md` §9.3 (`:65-113`) |
| The two register rows this design's facts are about | `OI-34`, `OI-35` (proposed by the charter, not yet filed) |
| The four register rows this design proposes | `OI-42`–`OI-45`, plus one `docs/first-release.md` line with no `OI-<n>`. `8b`'s three follow at `OI-46`–`OI-48` |
| The deviation block | `P8-1`–`P8-19`, of which `P8-1`–`P8-14` are used. The charter fixes the phase-wide allocation (`8b` `P8-20`–`P8-35`, `8c` `P8-36`–`P8-50`) |
| The shared transport contracts `8a` and `8c` both implement | the charter's *Shared transport contracts* subsection — the ten-name drop set, `Events::TRANSPORT_HEADER_DROPPED`, `TRANSPORT-13`'s `8c`-only policy, and `Keys::REQUEST_TIMEOUT` |
| Corpus keys cited | `transport-adapter/7e8e2c60`, `/d16c7444`, `/52b448e8`, `/deccd514`, `/2985bb74`, `/e25582ce`, `/0921e946`; `cancellation-and-timeouts/b7cde725`, `/c8ff4730`, `/128ecb55`, `/40c2fd15`; `concurrency-and-async/611b9392`, `/c0fab747`, `/ee54cb68`, `/f261a143`; `resource-management/4aca52f9`, `/346deaec`, `/b7587eb7`, `/d1f16cad`; `io-and-byte-streams/a005249e`, `/a44b4de6`; `pipeline/f02559b9`; `module-organization/1828a984`, `/5c33e5ce`; `api-design/88e6bf12`; `testing/4ef070df`; `observability/65191069` |
| The audit-group row this sub-phase ran | *Transport and async-runtime adapters* — `--topic transport-adapter,cancellation-and-timeouts,concurrency-and-async --section rules --brief` and `--prefix TRANSPORT,ASYNC --section rules --brief`. **Still owed** to `.claude/skills/knowledge-lookup/SKILL.md`, together with phase 7's |
| Probe scripts, for re-running the facts | `<scratchpad>/p8a/{fixture,pump,teardown,fiber,wire,verbose,inbound,ae,retry,conc,proto,cl,cl2,to,bstream,hdrs,final}.rb` |

---

## Open questions for `8a`'s own plan

Six, each bounded, none reopening a decision above.

1. **The three-interpreter re-run of verified facts 1–17.** Only 3.4.10 is installed here. Task 1 of the
   plan installs 3.2.11 and 4.0.6 and re-runs every fact. **Three are conditional on the re-run and the
   plan says what changes if each fails.** `Net::HTTP#read_timeout=`'s live propagation onto an open
   socket (fact 8) is what `R3`'s mid-stream refresh rests on; if it does not hold on 3.2, the budget
   degrades to per-phase assignment with a stated narrowing rather than a redesign. The cross-thread
   `FiberError` (fact 10) is what `R1` rests on; if 3.2 permitted a cross-thread resume — it will not,
   but the claim is unverified there — `R1`'s conclusion is unchanged, because the thread pump is also
   the only mechanism that needs no `Fiber#kill`. And `Warning.warn`'s delivery of the Content-Type
   warning (fact 5) is what `P8-4` rests on; a Ruby on which it does not warn simply makes `P8-4`'s
   second reason (the `x-www-form-urlencoded` lie) the only one, which is sufficient on its own.
2. **Whether `net-http`'s RBS signatures reach Steep through `rbs_collection.yaml` or through a
   `Steepfile` `library "net-http"` line.** `rbs` is not installed on this machine and the two spellings
   are not interchangeable: a default gem's signatures ship with `rbs` itself, while
   `rbs_collection.yaml` resolves third-party gems from `gem_rbs_collection`. Phase 0's comment says each
   transport "adds its own row here", which presumes the second. *Recommendation:* try `library
   "net-http"` on the `dexpace-transport-net_http` Steep target first and add the collection row only if
   `rbs validate` needs it — but verify rather than assume, because an unresolvable signature makes the
   target's diagnostics meaningless rather than loud.
3. **The exact membership of `MANAGED_HEADERS`, on one name.** Nine of the ten are settled above.
   **Open:** whether `proxy-authorization` joins them. `TRANSPORT-30`'s embedded MUST is that proxy
   credentials "MUST NOT be answered to an origin-server (401) challenge", and `8a` configures no proxy —
   so a caller-set `Proxy-Authorization` is a header the SDK has no business managing and arguably
   should pass through like any other. *Recommendation:* **do not** manage it. Dropping it would silently
   break a caller who is proxying at a layer the SDK cannot see, and `TRANSPORT-30`'s MUST is about
   credentials *the SDK holds*, which it holds none of. The row states the reasoning either way.
4. **`WireServer`'s accept-loop shutdown, which is the fixture's own `XCUT-13`.** A `TCPServer#accept`
   blocked in a thread is woken by closing the server socket, which raises `IOError` or
   `Errno::EBADF` depending on timing. **Open:** whether `#close` closes the listener and joins with a
   bounded deadline (symmetric with `ResponsePump`) or uses a self-pipe. *Recommendation:* the bounded
   join, because it is the same shape the adapter uses and a fixture that teaches a different teardown
   idiom than the code it tests is a fixture a reader will copy wrongly.
5. **Whether `Allocations.delta`'s warm-up count is a constant or a keyword.** `GC.stat`'s own overhead is
   caller-shaped (measured: 1 allocation around an empty block, 0 around `{ nil }`), so a warm-up is
   required and its size is empirical. *Recommendation:* a named `private_constant` with the measurement
   in a comment, and the iteration count a required keyword — because `OBS-25`'s "MUST NOT allocate per
   call" is a per-iteration claim and a caller who forgets the count gets a number that means nothing.
6. **Whether the conformance report's preamble is a string or a structured value.** It must name the two
   omissions (`P8-9`) and every waived ID on every run. **Open:** whether `Report#to_s` is the only
   renderer or whether a `#to_h` ships beside it for a CI consumer. *Recommendation:* `#to_s` only in
   `8a`. A structured renderer is `NFR-4`-locked surface with no caller, which is `OI-8`'s exact shape,
   and phase 9 — which will have three suites to aggregate — is the phase with the caller.
