# Phase 8c — Asynchronous Transport

**Status:** Draft, for review. Written 2026-09-11, against
`docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`, which is this sub-phase's charter.

**Path:** `docs/work/mvp/phase8/phase8c/2026-09-11-phase8c-asynchronous-transport-design.md`. That is the
path this document carries for the rest of its life and the one every citation of it should use. Its plan
is `docs/work/mvp/phase8/phase8c/2026-09-11-phase8c-asynchronous-transport.md`; the checklist is written
at execution time and is not this document's to draft.

## Purpose

Sub-phase 8c ships **`dexpace-transport-async_http`** — §2.1's "reference *asynchronous* transport", the
one MVP gem whose reason for existing is to prove the properties a thread pool cannot: multiplexing, a
structured cancellation tree, and scheduler-native suspension. It fills
`gems/dexpace-transport-async_http/lib/`, spends that gem's `NFR-2` budget on `async-http`, adds the
second `rbs_collection.yaml` row, supplies the second driver for every assertable row of `8a`'s
conformance suite, and closes `DEF-41` and its own half of `DEF-25`.

**Ten requirement IDs**: `TRANSPORT-7`, `TRANSPORT-8`, `TRANSPORT-9`, `TRANSPORT-12`, `TRANSPORT-13`,
`TRANSPORT-21`, `TRANSPORT-23`, `ASYNC-6`, `ASYNC-21`, `ASYNC-22` — nine MUST and one SHOULD
(`TRANSPORT-13`), with `ASYNC-21` **N/A** by §11.21 and the charter's own row. Ten is small; the charter
argues at length why it is nonetheless its own segment, and this document does not re-argue it. What the
count does not see is the twenty-three second-adapter conformance rows, a fifteen-gem transitive closure
with a native extension, and an HTTP/2 path that no earlier document in this repository had exercised.

**The charter assigns 8c four risks — `R13`, `R14`, `R15` and (jointly with `8a`) `R16` — and this
document decides all four.** Three turn on facts measured here rather than inherited, and two of the
three invert something the charter had to reason around:

- **The HTTP/2 gap the charter could not close is closed.** The charter's closing paragraph records that
  "every async probe in this document ran HTTP/1.1 against a local `TCPServer`; the HTTP/2 path was not
  exercised", and makes `TRANSPORT-8`'s and `TRANSPORT-18`'s dispositions turn on it (`R14`). This
  document built an in-process HTTP/2 server from `async-http`'s own classes and drove it **twice** — over
  plaintext prior-knowledge h2, and over a self-signed TLS endpoint with real ALPN negotiation (verified
  facts 2 and 3). Everything below about HTTP/2 is measured, not inferred.
- **`TRANSPORT-12`'s antecedent is live on the HTTP/1.1 path and absent on the HTTP/2 path of the same
  adapter**, and the HTTP/2 half is worse than absent: `protocol-http2` performs **no outbound header
  validation at all**, so a name containing a space *and a value containing CRLF* both reach the wire
  verbatim (verified fact 4). `DEF-25`'s wire-boundary re-validation is therefore not a
  correctness-of-shape mitigation on this adapter's h2 path — it is the **only** thing between a forged
  model and an injected header.
- **`dexpace-transport-async_http` cannot declare the repository's Ruby 3.2 floor.** `async-http 0.95.0`
  and `async 2.38.0` both raised `required_ruby_version` to `>= 3.3`, and the installed 0.104.0 carries it
  (verified fact 1). Phase 0's `gates:versions` asserts that *every* gemspec's `required_ruby_version`
  equals `>= ` plus `VERSIONS`'s single `ruby floor` line. This is the sharpest finding in the sub-phase,
  it is mechanised on both sides, and it is settled under `R15` as deviation `P8-36` with `OI-38` filed
  against the gate that has to change.

---

## Governing documents

- `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md` — **the charter**, read in full and
  binding. It fixes 8c's ten IDs (`:747-767`), the twenty spec-forced boundaries (`:532-629`), the six
  rejected cuts, the four convergence points (`:840-878`), the phase-level tasks (`:882-923`), the
  fifteen verified Ruby facts (`:1057-1269`), the register sweep and risks `R13`–`R16` (`:1857-1897`).
- `docs/product-spec/17-transport-adapter-conformance-contract.md` (51 lines) and
  `docs/product-spec/18-asynchronous-runtime-adapter-contract.md` (46 lines), both read in full, with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md:559-610` for the canonical
  text and modal level of all ten IDs plus the twenty-three 8c re-asserts. The chapters' `*Conformance:*`
  clauses, which appendix C drops, are load-bearing in six places named below.
- `docs/product-spec/03-pluggable-seams-and-extension-model.md` — `SEAM-11`, `SEAM-13`, `SEAM-14`,
  `SEAM-15`, `SEAM-16`, `SEAM-17`, `SEAM-24`, `SEAM-25`, `SEAM-30`.
- `docs/product-spec/05-io-streaming-contracts.md` — `IO-40`, which keeps every deadline in this gem and
  out of `Dexpace::IO::BufferedSource`.
- `docs/product-spec/13-server-sent-events-and-streaming.md` — `SSE-39`'s pull-based delivery, the
  property this adapter's response body must feed, and `SSE-37`'s serde-independence, which 7b made a
  mechanised MUST and which 8c does not touch.
- `docs/product-spec/19-cross-cutting-invariants-and-policies.md` and `20-non-functional-requirements.md`
  — `XCUT-2`, `XCUT-4`, `XCUT-11`, `XCUT-13`, `XCUT-18`, `XCUT-22`, `NFR-1`, `NFR-2`, `NFR-3`, `NFR-4`,
  `NFR-11`, `NFR-13`.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` §2.1 (`:16-25`, "The reference *asynchronous*
  transport" and the sentence that says why it is MVP and not later), §2.3 (`:39-68`, the layout and the
  `~> MAJOR.MINOR` skew constraint) and §2.4 (`:71-105`, the zero-dependency rule, the bundled-gem hazard
  and the single-instance argument).
- `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.1 (`:5-60`, the BINARY boundary and the
  canonical `#each`-yielding body), §3.2 (`:155-188`, the sync seam — read to confirm 8c implements none
  of it), §3.3 (`:189-294`, the pivot, check-after-resume, cancellation and deadlines end to end, and at
  `:252-254` the post-v1 `dexpace-async-async` mapping that is **not** 8c's), §3.5 (the
  `URI::RFC3986_PARSER` pin) and §3.7 (`:452-518`, the close contract, the `@owned` distinction and
  `close_quietly`'s two disposal routes).
- `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.3 (`:195-231`) — the clock, the
  cancellable wait, the prohibition on `Timeout.timeout`/`Thread#raise`/`Thread#kill`, and the sentence
  that fixes what an async deadline is: "to the task's own timeout on the async path, where they interrupt
  only at a scheduler checkpoint".
- `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md` §9.2 (the three zero-dependency checks) and
  §9.3 (`:65-113`) — Minitest, `dexpace-conformance`'s framework-agnostic assertion objects, the
  `TCPServer` fixture, and B.6's "exercised per adapter, with **TRANSPORT-8** and **TRANSPORT-18** vacuous
  for `Net::HTTP` and mandatory for any adapter whose client has those paths", which is `R14`'s text.
- `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items **3** (`:18-22`,
  the core-owned pivot — 8c bridges to it and never replaces it), **4** (`:23-29`, cooperative
  cancellation and the producer-side orphan close), **5** (`:30-57`, the three MUSTs 8c may not re-open),
  **7** (`:63-67`), **10** (`:77-81`, `DEF-25`) and **12** (`:87-91`, stream ownership).
- `docs/sdk-design-ruby/11-…-spec-ambiguities-….md` items **2** (`:10-12`, `NFR-11` versus `SEAM-17`),
  **5** (`:20-22`, `SEAM-30`'s pre-emptible-future presumption), **8** (`:31-32`), **12** (`:42-44`, the
  four sync/async drifts), **18** (`:59-62`, `SERDE-26` and `TRANSPORT-18` as conditional obligations) and
  **21** (`:73-78`, `ASYNC-21`'s adapter-scoped MUST — 8c's `ASYNC-21` row and its whole reason).
- `docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md` — the `TRANSPORT` row (`:41`), the
  `ASYNC` row (`:42`) and the MUST-level summary (`:49-55`). `R14` changes what the `TRANSPORT` row should
  say about `TRANSPORT-8`; the charter's `OI-34` already records that the same row is wrong about
  `Net::HTTP`'s retry, and this document adds a second, independent correction to it.
- The predecessor designs 8c consumes rather than re-derives:
  `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md`,
  `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md`,
  `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md`,
  `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md`,
  `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md`,
  `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md`,
  `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md`,
  `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-design.md`,
  `docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md`,
  `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md`,
  `docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry-design.md`,
  `docs/work/mvp/phase7/phase7b/2026-09-10-phase7b-server-sent-events-design.md`.
- `docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization-design.md` as the closest worked example
  of this document's form, and the most recent sub-phase design to ship a gem.
- `docs/deferred-items.md` (`DEF-1`, `DEF-10`, `DEF-11`, `DEF-18`, `DEF-22`, `DEF-25`, `DEF-30`, `DEF-33`,
  `DEF-41`, `DEF-42`), `docs/open-items.md`, `docs/deviations.md`, `docs/first-release.md`.
- `CLAUDE.md` and `docs/README.md`.

**Not read, deliberately:** `docs/work/mvp/phase8/phase8a/` and `docs/work/mvp/phase8/phase8b/`. Both were
being written concurrently with this document and a half-written sibling is worse than none. Every fact
this document needs from either comes from the charter, which fixed them. `R16` is written so that
whichever of `8a` and `8c` lands first can accommodate the other.

---

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run before anything here was written, and re-run for
this document rather than trusted from the charter's report.

`ruby scripts/knowledge.rb --origin note --brief` returns **38 entries across 19 note files**.
`ruby scripts/knowledge.rb --section conflicts --brief` returns **24 entries across 17 topic files, 18 of
them notes and six harvested**, and **all six harvested ones print `[overridden by notes/…]`**
(`data-modeling/35fde90f`, `module-organization/bf6411ad`, `package-and-dependency-layout/41b154a3` and
`/8c0687bf`, `tooling-and-quality-gates/86d763f1`, `type-system/93dc79aa`). **None is open**, so 8c
inherits no unresolved conflict and owns no conflict decision of its own. Narrowed to this sub-phase's two
prefixes, `--section conflicts --prefix TRANSPORT,ASYNC --brief` returns the CLI's no-matching-entries
message: **no recorded styleguide-versus-design conflict touches a `TRANSPORT` or an `ASYNC` ID**, which
is the charter's result reproduced.

**`--req` on all ten IDs at once** — `--req TRANSPORT-7,TRANSPORT-8,TRANSPORT-9,TRANSPORT-12,
TRANSPORT-13,TRANSPORT-21,TRANSPORT-23,ASYNC-6,ASYNC-21,ASYNC-22` — returns entries across five topic
files, and the charter's roll-up warning holds exactly as predicted: the substantive answers all live in
`Rules`, and the `Reference` section is `[appendix-B roll-up]` noise at roughly the 44%/34% rates the
charter measured. **No query in writing this document was a bare `--req`**; every one carried
`--section rules,constraints,conclusions` or a `--key`.

**The audit groups run, and what each found.** The charter drafted the row the skill's table is owed and
this document ran it, plus seven of the twelve existing rows.

| Group | Query | What it returned, and what bound 8c |
|---|---|---|
| **Transport and async-runtime adapters** (the charter's owed row) | `--topic transport-adapter,cancellation-and-timeouts,concurrency-and-async --section rules --brief` | **125 entries across 3 topic files.** The widest group 8c ran and the one that reaches the styleguide-derived concurrency rules carrying no ID. Nothing in it is roll-up-tagged. |
| same, ID form | `--prefix TRANSPORT --section rules --brief` (**30 entries, 2 files**) and `--prefix ASYNC --section rules --brief` (**25 entries, 3 files**) | Complete and roll-up-free, confirming the charter: the roll-ups live entirely in `Reference`. `ASYNC`'s 25 exceed its 22 IDs because three design-role entries restate a requirement from the Ruby side. |
| *Public API surface* | `--topic api-design,http-domain-model,documentation,module-organization,error-handling --section rules --brief` | **150 entries across 5 topic files.** Nothing new for 8c beyond what phases 1, 2 and 7a already answered; the binding rules are the YARD-every-public-method gate and `error-handling`'s one-root rule, which `Dexpace::TransportError` (a phase-level task) already satisfies. |
| *Gem layout, zero-dependency core* | `--topic package-and-dependency-layout --section rules,constraints --brief` | **14 entries, 1 file.** The decisive one for `R15` is the single-instance argument (quoted under `R15`); the `NFR-2` budget rules are stated in terms of **declared** dependencies throughout, which is the reading `R15` takes. |
| *RBS / Steep typing* | `--chapter 3 --section rules --brief` (**23 entries**) and `--topic type-system,data-modeling --section rules --brief` (**86 entries across 2 files**) | Binding on the `sig/` shape below: non-nil return types unless the method models absence, and `type-system/e4969b16`'s `fetch` over `[]`. |
| *Minitest conventions* | `--chapter 11 --section rules --brief` (**23 entries**) and `--topic testing,assertions --section rules --brief` (**29 entries across 2 files**) | Two bind the testing strategy hard: the **30-second suite budget** (which is why every fixture in 8c is bounded and no test sleeps for more than 400 ms) and the **named-waiver rule** — "a conformance checklist item the port has decided not to satisfy is reported as a failure by the conformance suite and suppressed in the port's own build through a named waiver listing the requirement ID". 8c has two unreachable clauses that need exactly that treatment. |
| *Encoding and binary strings* | `--prefix IO --section rules --brief` (**33 entries across 3 files**) and `--topic io-and-byte-streams,serde --section rules --brief` (**76 entries across 2 files**) | `IO-40` is the boundary (below); `io-and-byte-streams/a44b4de6`'s frozen-ingress rule decides how 8c retags — and verified fact 6 says it does not have to, because `async-http` already hands back unfrozen BINARY. |
| *Fiber scheduler, thread safety* | `--topic concurrency-and-async --section rules --brief` (**75 entries, 1 file**) and `--chapter 9 --brief` (**51 entries**) | The single most useful line 8c found anywhere in the corpus is in chapter 9 and carries no ID: "**`Async` structured tasks drain automatically when the outer `Async do` block exits, making that cleanup free when using structured concurrency.**" That is the styleguide sanctioning the shape §3.7's close contract otherwise has to police by hand, and it is why 8c's exchange is a **child task of the caller's**, not an `Async { }`. |

**The entries 8c is built on, cited by key rather than restated**, except where the rule turns on the
sentence:

- **`concurrency-and-async/611b9392`** — check-after-resume, the one rule every async adapter owes. Quoted
  because 8c's whole cancellation design is an answer to its second half:
  > Every async adapter MUST honour check-after-resume: after returning from any operation that may have
  > suspended (an I/O wait, a scheduler yield, a queue pop, a task await), and before acting on the value
  > it produced, the producer MUST re-check its cancellation state; if cancelled, it MUST close any
  > response it holds and settle through the failure channel rather than delivering. (SEAM-30, ASYNC-5)

  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:239-244` · high · sha:bf7f85fc5f18</sub>
- **`cross-cutting-invariants/093b7681`** — ownership as a constructor-level distinction with a frozen
  `@owned` boolean and two differently named entry points. This is `TRANSPORT-15`/`SEAM-14`/`XCUT-22` and
  it is what gives 8c `.new` and `.over`.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:478-485` · high · sha:bf7f85fc5f18</sub>
- **`concurrency-and-async/f75816b6`** — the entry 8c must read and **not** act on: "dexpace-async-async
  later maps Async::Task#stop and #with_timeout onto the pivot's cancellation in both directions per
  ASYNC-6". That is `DEF-11`, post-v1, and `SEAM-24`'s second sentence. 8c satisfies `ASYNC-6` for the
  task **it creates itself** and bridges no caller-held task. It is also the entry verified fact 10
  corrects: `Async::Task#stop` is a deprecated alias in `async` 2.45.1.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:252-254` · high · sha:bf7f85fc5f18</sub>
- **`transport-adapter/cb7901ef`** — `TRANSPORT-12`'s drop, "on both sync and async paths".
  <sub>spec · `docs/product-spec/17-transport-adapter-conformance-contract.md:24-24` · high · sha:2d5843c58993</sub>
- **`cancellation-and-timeouts/58a6009b`** — `TRANSPORT-8`, and the clause `R14` turns on: "a transport
  with no internal-cancel path need not support it".
  <sub>spec · `docs/product-spec/17-transport-adapter-conformance-contract.md:17-17` · high · sha:2d5843c58993</sub>
- **`concurrency-and-async/f414b864`** — the `concurrent-ruby` substitution note. Its six routed
  bounded-pool rules bind **`8b`**, not 8c; what binds 8c from the same note is the pair it adopts
  verbatim — `/c0fab747` (protect only the smallest critical section) and `/ee54cb68` with `/f261a143`
  (never hold a lock across I/O), which govern 8c's one mutex, the per-origin client map.
  <sub>review · `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` · high · sha:manual-phase2-no-concurrent-ruby</sub>
- **`resource-management/d1f16cad`** — where the styleguide's per-call I/O timeout rules are paid:
  "**phase 8's transports, which own the socket** … with the values coming from phase 5's layered
  configuration chain as named settings rather than literals". 8c's deadline is `Async::Task#with_timeout`
  and its default comes from `Configuration`, not a literal.
  <sub>review · `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md` · high · sha:manual-phase3a-io40-no-timeouts</sub>
- **`pipeline/f02559b9`** — `raise error, cause: nil` for an error a component is *carrying* rather than
  one it just rescued. Every `Completer#fail` in 8c is that shape.
  <sub>review · `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md` · high · sha:manual-phase4b-reraise-cause</sub>
- **`io-and-byte-streams/a44b4de6`** — `String#b`, never `force_encoding`, on the ingress path, because a
  chunk may be frozen. Verified fact 6 says `async-http`'s chunks are unfrozen BINARY already, so 8c's
  ingress retag is a **no-op it must still be able to state**; the rule is what makes "no-op" a measured
  claim rather than an assumption.
  <sub>review · `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md` · high · sha:manual-phase3a-frozen-ingress-retag</sub>
- **`testing/9a56af9d`** — "B.6 is exercised per adapter, with two transport requirement items vacuous for
  Net::HTTP and mandatory for any adapter whose client has those code paths. (OBS-1, TRANSPORT-8,
  TRANSPORT-18)". This is `R14` stated by the corpus, and `R14` answers it with a measurement.
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:102-104` · high · sha:b9270d5d1ef8</sub>

**One knowledge note is filed by this document's plan** — drafted under *The knowledge note 8c files*. Its
subject is verified fact 4: `protocol-http2` transmits a CRLF-bearing header value verbatim while
`protocol-http1` refuses it, so the *same adapter* has and does not have an injection surface depending on
the negotiated protocol, and `DEF-25` is load-bearing rather than belt-and-braces on one of the two.

---

## The spec-reading budget

**Zero, and stating that is the obligation.** The roadmap requires a phase whose IDs come back as gaps to
budget reading time in its design document and say so there
(`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:154-155`).
`ruby scripts/knowledge.rb --gaps TRANSPORT,ASYNC` reports 0 of 52, so the budget is zero and this
sentence discharges the obligation.

**What that does not license**, restated for 8c specifically:

1. **`--gaps` measures corpus coverage, not specification coverage** (`OI-12` from the other side). Both
   chapters were read in full anyway, at 51 and 46 lines.
2. **The `*Conformance:*` clauses appendix C drops are load-bearing in six places here.** `TRANSPORT-7`'s
   "cancel an in-flight future and assert the native call is cancelled"; `TRANSPORT-8`'s "trigger a
   native-internal cancel and assert the terminal type; **a timeout on the same path still completes
   retryable**"; `TRANSPORT-9`'s "settle the future before the response finishes adapting"; `TRANSPORT-12`'s
   "send a model-valid non-token header name plus a normal header; assert send does not throw / the future
   completes normally, the bad header is absent, the normal header present"; `TRANSPORT-13`'s "under
   once-per-header assert the same name warns once then goes quiet, a different name warns once"; and
   `ASYNC-22`'s "fire many concurrent executeAsync calls on one client and assert each future resolves to
   its own correct Response **with no cross-talk**". A sub-phase reading only appendix C writes none of
   those six tests.
3. **Corpus coverage says nothing about whether a *design* sentence is true.** The charter's `OI-34` and
   `OI-35` are both design sentences that are wrong about `Net::HTTP`; this document adds a third and a
   fourth about `async-http` (`OI-39`, `OI-40`). Only running Ruby finds them, and only against the exact
   versions the gemspec will declare.

---

## Scope: the ten IDs

| Disposition | IDs | Count |
|---|---|---|
| Implemented and asserted | `TRANSPORT-7`, `TRANSPORT-9`, `TRANSPORT-12`, `TRANSPORT-13`, `TRANSPORT-21`, `TRANSPORT-23`, `ASYNC-6`, `ASYNC-22` | 8 |
| Implemented, and **a MUST §12 records as vacuous for the other adapter** | `TRANSPORT-8` (`R14`) | 1 |
| **N/A — adapter-scoped and vacuous** (§11.21) | `ASYNC-21` | 1 |
| **Total in budget** | | **10** |

Level split, derived from appendix C on 2026-09-11: **nine MUST, one SHOULD (`TRANSPORT-13`)**. No `MAY`
and no `MUST NOT`. **No `DEF-<n>` moves an ID into 8c and none moves one out.** `TRANSPORT-1`,
`TRANSPORT-2`, `TRANSPORT-11`, `TRANSPORT-14`, `TRANSPORT-18`, `TRANSPORT-24`–`TRANSPORT-27`,
`TRANSPORT-29` and the rest of §17 are **`8a`'s rows**, satisfied again here through a second driver of the
same assertion; the charter's assignment rule (`:635-643`) gives them no second row and this document
takes none.

### Nine rows carry a clause the checklist must state rather than tick

Each is on the authority of a requirement's own conditional antecedent, a design appendix, or a measured
fact — never on 8c's convenience.

- **`TRANSPORT-8` is satisfied here and §12 says it is vacuous.** Appendix C's antecedent is "Where the
  native client can surface a cancellation **originating inside it** while the SDK future is still live",
  and §12's `TRANSPORT` row lists `TRANSPORT-8` among "adapter-scoped and vacuous for `Net::HTTP`". On
  `async-http` the antecedent is live and measured (verified fact 8): a cancellation delivered from the
  caller's own structured-concurrency scope — a parent `Async::Task` being cancelled, or the reactor being
  torn down — reaches the in-flight exchange as `Async::Cancel` while the pivot is still live and nothing
  in the SDK asked for it. The row says **satisfied**, cites verified fact 8, and names `OI-41` as the §12
  correction it cannot make. `R14`.
- **`TRANSPORT-12` has a live antecedent on one protocol and none on the other, and 8c drops on both.**
  `protocol-http1` raises `Protocol::HTTP1::BadHeader` on `"Bad Name"`, which `HTTP-17` accepts;
  `protocol-http2` transmits it (verified facts 4 and 5). The row states that 8c applies the RFC 7230
  token predicate **before dispatch and independently of the negotiated protocol**, so one request
  produces one observable header set. Deviation `P8-40`.
- **`TRANSPORT-12`'s "the resulting native exception MUST NOT escape the send contract" cannot be met by
  rescuing.** Verified fact 5: `Protocol::HTTP1::Connection#write_request` writes the request line and the
  `host:` header **before** `write_headers` raises, so by the time the exception exists a partial request
  is already on the wire and "the rest of the headers and the body MUST still be dispatched" is
  unreachable on that connection. The row states pre-dispatch dropping as the *only* conforming
  implementation, not as a preference.
- **`TRANSPORT-13`'s dedup bound is a real number and the row states it.** "MUST be bounded so an attacker
  synthesising unbounded distinct names cannot grow it without limit." 8c fixes the bound at **64 distinct
  header names per adapter instance**, after which the policy degrades to its quiet mode rather than
  growing. The row names the constant and the degradation, because "bounded" with no number is not a
  testable clause.
- **`TRANSPORT-21`'s "Only truly fatal runtime errors may propagate synchronously" is one named set.** 8c
  lets exactly `Async::Cancel` (and therefore `Async::Stop`, which is the same class), `NoMemoryError`,
  `SystemExit`, `SignalException` and `Interrupt` propagate; everything else reaches `Completer#fail`. The
  row names the set rather than saying "fatal".
- **`TRANSPORT-23` is satisfied by phase 2's type, not by 8c's code.** `Dexpace::Async::Settlement`'s
  cross-field rule — exactly one of `response`/`error` — makes "completed successfully with nothing"
  unreachable. The row cites phase 2 and states that 8c writes no second guard.
- **`ASYNC-6` is the only ID quantified over adapters, and 8c owns the row for both directions.** The
  charter (`:641-643`) fixes this: `8b` carries a cross-reference row. 8c's row states both directions
  concretely — `cancellation.on_cancel { task.cancel(cause: reason) }` outward, and the task's own
  `Async::Cancel` inward to **`Completer#request_cancel(reason)`** — and names the test that proves each.
  (Corrected 2026-09-12: the inward call is `#request_cancel`, not `Completer#fail`. Only
  `#request_cancel` settles a `Settlement.cancellation`, which is the one outcome `Future#cancelled?`
  reads as true; `#fail` carrying a `CancelledError` instance settles a *failure* and leaves
  `#cancelled?` false. Phase 2's own `Bridge::AsyncOver#deliver` takes exactly this branch.)
- **`ASYNC-21` is N/A, and "N/A" is an argument.** §11.21: a MUST whose antecedent is an optional adapter,
  and no reactive adapter ships. The row states that the property it protects is implemented anyway, on
  7b's pull path (`SSE-39`) **and on 8c's response body**, which reads the native body exactly once per
  unit of consumer demand (verified fact 7). The row is N/A citing §11.21 and **no register entry**,
  because §12 holds it vacuous rather than deferred — the same distinction the charter draws for
  `ASYNC-4`.
- **`ASYNC-22` is satisfied structurally and asserted anyway.** All per-call state is the exchange task
  and its `Completer`; the adapter holds only the frozen client map. Verified fact 9 measures eight
  concurrent calls through one adapter with no cross-talk, which is the requirement's own conformance
  clause.

### What 8c additionally ships, without owning a new ID

- **`DEF-25`'s call site in this adapter** — `Dexpace::HeaderSyntax` re-run over every header name and
  outbound value immediately before dispatch. On the HTTP/2 path it is the **only** validation between the
  model and the wire (verified fact 4), which is a stronger statement than §10.10's and is recorded as
  such.
- **`DEF-41`/`OBS-19`'s three-mode drop-logging policy**, picked up here because 8c is the first adapter
  in the repository that drops rather than raises. Built from 5b's two `Severity` constants and its
  once-per-key latch, exactly as `DEF-41`'s own row predicts.
- **The second driver for every assertable row of `8a`'s conformance suite** — the charter's headline
  convergence point. `R16` states what 8c needs the suite to assume.
- **An in-process HTTP/2 conformance driver**, plaintext and TLS, which no other adapter in the MVP can
  supply and which `8a`'s `TCPServer` fixture cannot speak.
- **`ASYNC-7`'s README section for a reactor-backed adapter** — §3.3 fixes the content: "the
  reactor-backed ones abort at the next scheduler checkpoint". `8b` owns the ID; 8c writes its half.
- **The `rbs_collection.yaml` row for `async-http`** and the gem's named Steep target.
- **The registration call** — `Dexpace::AsyncTransport.register(key, factory, core: "~> MAJOR.MINOR")`,
  with the skew keyword required, never optional (boundary 8).

### Canonical text quoted because a decision below turns on it

> **TRANSPORT-8 (MUST).** Where the native client can surface a cancellation that originates inside it
> (e.g. an internal cancel-all or an interceptor-driven cancel) while the SDK future is still live, that
> cancellation MUST complete the future with a terminal, non-retryable cancellation-shaped exception, NOT
> the retryable transport-failure exception; a genuine timeout on the same path MUST still complete with
> the retryable type.

The decisive words are **"originates inside it"** and **"a genuine timeout on the same path"**. `R14` shows
both halves are live and both are discriminable by class, not by message — `Async::Cancel < Exception`
against `Async::TimeoutError < StandardError` (verified fact 10), which is `XCUT-2` satisfied by the
runtime rather than by the adapter.

> **TRANSPORT-12 (MUST).** A header that is valid at the SDK model layer but rejected by the native
> client's stricter wire grammar MUST be dropped for that header only; the resulting native exception MUST
> NOT escape the send contract. The rest of the headers and the body MUST still be dispatched, on both
> sync and async paths.

"The rest of the headers and the body MUST still be dispatched" is what verified fact 5 makes unreachable
after the fact, and is therefore the clause that forces the drop to be a **predicate**, not a `rescue`.

> **TRANSPORT-21 (MUST).** On the async path, a failure that occurs on the caller's thread before dispatch
> … MUST be delivered through the returned future (completed exceptionally), NOT thrown synchronously to
> the caller.

This is what makes 8c's answer to "called outside a reactor" a **failed future** rather than a raise — the
cleanest reading available, and one the requirement asks for in as many words.

> **ASYNC-21 (MUST).** An adapter exposing a streaming source (SSE) as a reactive stream MUST honor
> downstream backpressure by polling the source at most once per unit of demand (never eagerly) …

"An adapter exposing … as a reactive stream" is the antecedent §11.21 calls optional, and none ships.

### Out of scope, explicitly

| Excluded | Owner |
|---|---|
| `TRANSPORT-1`–`TRANSPORT-6`, `TRANSPORT-10`, `TRANSPORT-11`, `TRANSPORT-14`–`TRANSPORT-20`, `TRANSPORT-22`, `TRANSPORT-24`–`TRANSPORT-30` | **`8a`.** 8c satisfies each on its own adapter and adds a driver to `8a`'s assertion; it takes no second row. Where a clause is *unreachable* on this adapter, 8c reports it to `8a` (see *What 8c reports to `8a`*). |
| `ASYNC-1`–`ASYNC-5`, `ASYNC-7`–`ASYNC-20` | **`8b`.** 8c drives `Dexpace::Async::Future`/`Completer` and satisfies `ASYNC-1`, `ASYNC-2` and `ASYNC-5` by routing through them, but the rows are `8b`'s. |
| `Dexpace::TransportError < ::IOError` with `XCUT-4` branch (b)'s retryable flag | **The phase-level task, landed by `8a`'s Task 2** (the charter fixed that on 2026-09-12, where it had read "whoever lands first" and both plans then wrote it with two shapes). It lands in `dexpace-core`, which is none of the three sub-phases' gems. **8c requires it and does not define it**; its own Task 4 is a citation and a verification of the three properties 8c depends on — `< ::IOError`, `include Dexpace::Error`, `#retryable?` always `true` — and writes the class itself only if 8c executes before 8a, in which case it writes `8a`'s identical shape. `8a`'s shape is a superset of the one this document assumed: it adds an optional `phase:` keyword and a default message, and 8c constructs the class positionally (`TransportError.new("…")`) at every site in `Errors.wrap`, so it needs nothing `8a`'s lacks. 8c is one of its two consumers and states its wrap table against it below. |
| `dexpace-conformance`'s gemspec, the assertion protocol, the `TCPServer` fixture, the first release | **`8a`** and the phase. `R16`. |
| `dexpace-async-thread`'s pool | **`8b`.** `async-http` uses none (charter, *Why none of the three leads another*), and `NFR-2` would not permit a third declaration anyway. |
| `SEAM-24`'s second sentence — a caller-facing cancellation bridge over the host's own primitive | **`DEF-1`, riding on `DEF-11`** (`dexpace-async-async`), post-v1. 8c satisfies `ASYNC-6` for the `Async::Task` **it creates itself** and bridges no caller-held task. |
| `OBS-29`'s operation-lifecycle tracer triple, and `DEF-42`'s transport-milestone group | `OI-32` and `OI-36`. 8c's position under *`DEF-42`* below: no route exists, so 8c wires no emitter and says so. |
| `SSE-1`–`SSE-41`, `PAGE`, `SERDE` | **Phase 7**, built. 7b's own words: "A transport hands back a `Dexpace::Response`; `Dexpace::SSE::Stream.open(response)` is the whole integration." 8c adds no SSE code and ships one property SSE needs (`SSE-39`'s pull). |
| `BODY-12` clause 2 (`DEF-3`) and `TRANSPORT-28`/`TRANSPORT-30` (`DEF-10`) | **`8a`'s dispositions.** 8c reports that `protocol-http` ships `Protocol::HTTP::Body::File` with `#offset`, `#rewind` and `#rewindable?` (charter fact 15), so `TRANSPORT-28`'s reachable half is *more* reachable here — a report to `8a`'s `R5`, not a row. |

---

## Prerequisites, and the independence this sub-phase states in its own words

**8c depends on no other sub-phase of phase 8, and the charter says every boundary is a convenience.**
Stated positively, in 8c's own terms rather than by inheriting the charter's sentence:

- **8c needs nothing from `8b`.** `dexpace-async-thread` is a `SEAM-18` executor for wrapping a *blocking*
  transport. `async-http` is not blocking: it drives `Async::Task` under a `Fiber.scheduler`, and its
  cancellation primitive is `Async::Task#cancel` (verified facts 8 and 10). 8c's gemspec declares
  `dexpace-core` and `async-http` and could not declare `dexpace-async-thread` even if it wanted to, since
  `NFR-2`'s budget is core plus **one**. A 8c test that installs a `dexpace-async-thread` pool is testing
  `8b`'s gem, and this document writes none.
- **8c needs nothing from `8a` at design time, and two artifacts from it at execution time.** The
  `TCPServer` fixture and `DEF-22`'s assertion protocol are **assigned to `8a`** by the charter, and 8c is
  their consumer. If 8c runs first it writes them to the shape `R16` fixes, and `8a` records that it
  consumed rather than wrote them. Either way `R16` states what an asynchronous transport needs the suite
  to assume, written so whichever lands first can accommodate the other. **Nothing in this document waits
  on `8a`.**
- **8c does not need a real `Net::HTTP` adapter to exist.** Its whole test surface is its own gem, phase
  2's pivot, and an in-process `async-http` server it supplies itself. The one place the two adapters meet
  is the conformance suite, which is a convergence point and not a build-order edge.
- **What 8c would re-impose if it were careless**, named so a plan does not: a first task that waits on
  `8a`'s `Dexpace::Conformance::Failure`, or one that waits on `8b`'s pool to have an executor to post to.
  Neither is needed; 8c's first task is its gemspec.

**What 8c consumes from each predecessor phase.**

### From phase 0 — the gates this gem meets first
`gems/dexpace-transport-async_http/` already exists on paper: a gemspec declaring `dexpace-core` **and
nothing else** (deviation `P0-9` — "the third-party half of each budget arrives with the code that needs
it … `net-http` and `async-http` in phase 8"), an entry file
`lib/dexpace/transport/async_http.rb` defining `Dexpace::Transport::AsyncHTTP` and `VERSION`, a `sig/`
mirror, a `test/` tree and a named Steep target. `rbs_collection.yaml` has an **empty `gems:` list** and
phase 0's own comment anticipates "net-http and async-http with the transports in phase 8, and each adds
its own row here then". Seventeen gates are standing, and 8c is the first thing in the repository to meet
four of them in anger: **`gates:gemspec_audit`** (one third-party dependency, and the `two_third_party`
negative fixture is its proof), **`gates:require_allowlist`** (the scan covers the adapters too),
**`gates:clean_bundle`** (a scratch `Gemfile` holding only this gem), and — the one that breaks —
**`gates:versions`**, which asserts "every gemspec's `required_ruby_version` equals `>= ` plus the `ruby
floor` line". `R15` and `OI-38`.

### From phase 1
`Dexpace::HeaderSyntax`, "a module of pure functions, and **the public entry point every transport adapter
calls again immediately before dispatch** (phase 8, `DEF-25`) … public API in the full sense — YARD, RBS,
surface manifest — precisely because a phase-8 adapter is a different gem and must be able to reach it."
Also `Dexpace::Request` (`:method, :url, :headers, :body`), `Dexpace::Response`, `Dexpace::Headers`,
`Dexpace::Query`, `Dexpace::RequestOptions` (`:timeout, :max_retries, :tags`), `Dexpace::MediaType`,
`Dexpace::Status`, `Dexpace::Method`, and `Dexpace::Error` as a **module**, which is what makes
`Dexpace::TransportError < ::IOError` reachable at all.

### From phase 2 — every seam 8c registers into
`Dexpace::AsyncTransport` with `.conforms?` and the five registry delegations; **an async transport is any
object responding to `#call(request, options, cancellation)` and returning a `Dexpace::Async::Future`**.
`Dexpace::Async::Completer` (`#future`, `#fulfil`, `#fail`, `#on_cancel`, `#settled?`, `#outcome`) and
`Dexpace::Async::Future` (`#settled?`, `#cancelled?`, `#value(cancellation:)`, `#wait(cancellation:)`,
`#on_settle`, `#cancel(reason)`), with `Dexpace::Async::Settlement` carrying "exactly one of response /
error; cancelled implies error". `Dexpace::Cancellation` with `.none`, `.source`, `.any`, `#cancelled?`,
`#reason`, `#on_cancel`, `#check!`, and `Cancellation::Subscription#detach`. `Dexpace::Closeable`;
`Dexpace.close_quietly`; `Dexpace::Hooks.notify`; `Dexpace::Registry#register(key, factory, core:)` with
its **required** skew keyword; `Dexpace::ClosedError`; `Dexpace::SeamError`; `Dexpace::Bridge::AsyncOver`
and `SyncOver`. Three phase-2 facts 8c leans on directly: **`Completer#fulfil` on an already-settled
future returns `false` and closes the response it was handed** — which is `SEAM-30`/`ASYNC-5`/`TRANSPORT-9`
satisfied for every adapter that routes through `Completer` rather than by each adapter remembering;
**`#cancel` after settlement is a no-op on the value and does not close a delivered response**
(`ASYNC-20`); and **`Future#value` blocks on a `Thread::Queue` pop**, which under a registered
`Fiber.scheduler` routes through `block`/`unblock` and does not park the OS thread — so a caller awaiting
8c's future from inside the same reactor does not deadlock it.

### From phase 3a/3b — the byte layer the response body crosses
`Dexpace::IO::BufferedSource.over(body)` (taking no ownership) and `.wrapping(io)`;
`MAX_MATERIALIZED_BYTES`; `Dexpace::StreamError < ::IOError` as a **sibling** of `Dexpace::TransportError`
and never a subclass (`P3-3`); `Dexpace::EndOfStreamError < ::EOFError`; `Dexpace::Body` with `#source`
and a default no-op `#close`; `Body.buffer_bounded`; `Response#close`/`#body_string`/`#body_bytes`.
**Two open items 8c inherits unresolved:** `OI-9` (`BufferedSource.wrapping` delivers one byte per read,
"and it will reach every transport phase 8 writes") — 8c's response body is built with
`BufferedSource.over`, over an `#each`-yielding wrapper, **not** `.wrapping`, which is why `OI-9` does not
bite here and why that is a decision rather than luck; and `OI-7`, the decode recipe, which 8c does not
touch because it decodes nothing.

### From phase 4b/4c — the taxonomy and the runtime a transport sits under
`Dexpace::ProtocolError` flat beside where `Dexpace::TransportError` lands; `Dexpace.each_cause`;
`Dexpace::Suppressible` and `attach_suppressed`; `Stages`, `Cursor`, `Pipeline`/`AsyncPipeline`;
`PIPE-26`/`PIPE-27` — a pipeline is a transport and closing one never closes the transport it wraps, so 8c
may not assume its caller is a pipeline. **`OI-18` is open and named as phase 8's or a phase-2
amendment's**: `Transport.async_over` accepts an *async* transport silently and yields a future of a
future. 8c is the first real async transport and therefore the first object that can be fed to it by
mistake; 8c does not fix it (the repair is in `dexpace-core`) and its README says so.

### From phase 5a/5b/5c — configuration and observability, consumed and not re-decided
`Dexpace::Clock` and the cancellable queue wait; `Dexpace::Async.delay`, which **raises
`Dexpace::SeamError` with no `Fiber.scheduler`** (`P5-9`) — a precedent 8c follows exactly for its own
no-reactor case, except that `TRANSPORT-21` makes 8c's a failed future rather than a raise;
`Configuration` and `Configuration::Keys`; `Instrumentation::Severity` (`ERROR`, `WARNING`, `INFO`,
`VERBOSE`), `Instrumentation::Logger#event`, `Event`/`Event::INERT`, the duck-typed sink,
`Instrumentation.contain(logger, event:)` — **every log emission in 8c goes through it**, because
`OBS-20`'s "every log-emission site" is not scoped to phase 5's sites — the once-per-key latch, and
`Diagnostics.capture`/`.with`. Phase 5b's forward table names 8c's inheritance in one line: "`Severity`
and the once-per-key throttle, which is what `DEF-41` targets. Phase 8 writes the three-mode policy at the
call site that actually drops a header" (`…phase5b…-design.md:2110`) — **with the wrong requirement ID,
`TRANSPORT-8` for `TRANSPORT-12`**, which the charter already proposes correcting and 8c confirms from the
other side.

### From phase 6a — the classifier 8c must feed
`P6-4`'s stated obligation, quoted because it is the sharpest hand-off in the register: "**every transport
adapter MUST wrap a bare stdlib I/O or timeout error it lets escape in something answering
`#retryable?`** … the obligation phase 8 inherits is 'wrap, and default to retryable,' not 'wrap, and get
the classification right by hand'." 8c's wrap table below is that obligation discharged, and verified fact
11 is why it cannot be skipped: **not one** of the seven error families `async-http` raises is an
`::IOError`.

### From phase 7b — what an SSE stream needs of a transport
"A transport hands back a `Dexpace::Response`; `Dexpace::SSE::Stream.open(response)` is the whole
integration. `7b` requires nothing of a transport beyond `Response#body` answering `#source`, which is
3b's contract." 8c's response body answers `#source` with a `BufferedSource` over a one-chunk-per-demand
reader, so `SSE-39`'s "a blocking source read is the backpressure mechanism and no unbounded internal
event buffer accumulates" holds through the transport as well as through the parser. **7b explicitly
declined `ASYNC-21` and named it phase 8's**; 8c takes the row and records it N/A.

---

## Verified Ruby facts this sub-phase is built on

All verified on **2026-09-11** against **`ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM
[x86_64-linux]`**, the only interpreter available to this document, with
`GEM_HOME`/`GEM_PATH` pointing at a scratchpad directory holding **`async-http` 0.104.0**, **`async`
2.45.1**, **`async-pool` 0.12.0**, **`console` 1.37.0**, **`protocol-http` 0.71.0**, **`protocol-http1`
0.41.0**, **`protocol-http2` 0.28.0**, **`protocol-hpack` 1.5.1**, **`protocol-url` 0.19.0**,
**`io-event` 1.22.0**, **`io-endpoint` 0.18.0**, **`io-stream` 0.14.0**, **`fiber-annotation` 0.2.0**,
**`fiber-local` 1.1.0**, **`fiber-storage` 1.0.1**, plus `openssl` 4.0.2 and `json` 3.0.2. Nothing was
installed into the project or into the user's gem directory. **Where a fact needs the 3.2 floor or the 4.0
column to be load-bearing, that is said rather than assumed**; the plan runs the three-interpreter check
this document could not.

### 1. `async-http` requires Ruby >= 3.3, and so does `async`. The repository floor is 3.2 and a gate asserts it.

`Gem::Specification.find_by_name("async-http").required_ruby_version` is **`>= 3.3`**, and so is
`async`'s, `async-pool`'s, `console`'s, `io-endpoint`'s, `io-event`'s, `io-stream`'s, `protocol-http`'s,
`protocol-http1`'s, `protocol-http2`'s and `protocol-url`'s. Consulting rubygems.org's version index:
**`async-http 0.94.2` is the highest release whose `required_ruby_version` is `>= 3.2`; `0.95.0` raised it
to `>= 3.3`.** For `async` the boundary is **2.37.0 (`>= 3.2`) / 2.38.0 (`>= 3.3`), both released
2026-03-08**. Phase 0's `gates:versions` asserts "that every gemspec's `required_ruby_version` equals
`>= ` plus the `ruby floor` line" of the repo-root `VERSIONS` file, whose `ruby floor` is `3.2` and whose
`ruby matrix` is `3.2 3.3 3.4 4.0`
(`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md:291-303`). Two mechanised
constraints in direct contradiction. `R15`, deviation `P8-36`, `OI-38`.
*Commands:* `ruby scratchpad/p8c/deps.rb` under the scratchpad `GEM_HOME`;
`https://rubygems.org/api/v1/versions/async-http.json` and `/async.json`.

### 2. An HTTP/2 client and server can be built from `async-http`'s own classes over plaintext, in process, and they interoperate. **The charter's unverified gap is closed.**

`Async::HTTP::Endpoint.parse("http://127.0.0.1:0", protocol: Async::HTTP::Protocol::HTTP2)` binds; an
`Async::HTTP::Server` over it serves; an `Async::HTTP::Client` over the same protocol connects with
**prior knowledge** (no h2c upgrade, because `Async::HTTP::Protocol::HTTP::client` "Defaults to HTTP/1 for
plaintext connections" in its own doc comment — the server auto-detects the HTTP/2 preface, the client
does not offer it). Measured over both protocols against the same server and the same request:

| | HTTP/1.1 | HTTP/2 |
|---|---|---|
| `response.version` | `"HTTP/1.1"` | `"HTTP/2"` |
| response class | `Async::HTTP::Protocol::HTTP1::Response` | `Async::HTTP::Protocol::HTTP2::Response` |
| a response header named `x-Mixed-Case` | preserved as `"x-Mixed-Case"` | **lowercased to `"x-mixed-case"`** |
| body chunk | `"hello-HTTP/1.1"`, `ASCII-8BIT`, unfrozen | `"hello-HTTP/2"`, `ASCII-8BIT`, unfrozen |
| `body.length` | 14 | 12 |

The case row extends the charter's fact 14 from a **cross-adapter** hazard to an **intra-adapter** one:
`Protocol::HTTP::Headers#each` yields `key.to_s.downcase` (`protocol-http-0.71.0/lib/protocol/http/headers.rb:559`)
on the HTTP/2 path, which is RFC 9113 §8.2.1, and does not on the HTTP/1.1 path. A conformance assertion
that checks the wire for a caller's exact spelling passes over one protocol and fails over the other, on
one adapter. `R16`, and the suite contract's clause 6 (folded name comparison).
*Command:* `ruby scratchpad/p8c/h2.rb` under the scratchpad `GEM_HOME`.

### 3. HTTP/2 also negotiates over TLS by ALPN against a self-signed endpoint — and a caller-supplied `ssl_context` silently disables ALPN.

With a self-signed 2048-bit RSA certificate carrying `subjectAltName = DNS:localhost,IP:127.0.0.1`, a
server `ssl_context` with an `alpn_select_cb`, and a client `ssl_context` with `cert_store` and
`verify_mode = VERIFY_PEER`: **the first attempt negotiated HTTP/1.1 and the server's ALPN callback never
fired.** The reason is in `async-http`'s own source — `Endpoint#ssl_context` is
`@options[:ssl_context] || OpenSSL::SSL::SSLContext.new.tap { … context.alpn_protocols = alpn_protocols … }`
(`async-http-0.104.0/lib/async/http/endpoint.rb:198-207`), so **a caller-supplied context is used verbatim
and never has `alpn_protocols` set on it**. Adding `client_ctx.alpn_protocols = ["h2", "http/1.1"]`
produced `server ALPN offered: ["h2", "http/1.1"]` and `response.version == "HTTP/2"`. The same method
also shows `ssl_verify_mode` returning **`VERIFY_NONE` for any hostname matching
`/^(.*?\.)?localhost\.?$/`** when no context is supplied. Both facts drive the TLS decision below.
*Command:* `ruby scratchpad/p8c/tls.rb` under the scratchpad `GEM_HOME`.

### 4. `protocol-http2` performs **no outbound header validation at all**: a space in a name and a CRLF in a value both reach the wire.

Driving the in-process HTTP/2 client and server from fact 2 and reading what the server received:

| Caller-set header | What the HTTP/2 server received |
|---|---|
| `["x-inject", "a\r\nEvil: 1"]` | `[["x-inject", "a\r\nEvil: 1"]]` — **transmitted verbatim** |
| `["Bad Name", "v"]` | `[["bad name", "v"]]` — transmitted, lowercased |
| `["host", "bogus.example"]` | `[["host", "bogus.example"]]` — transmitted beside `:authority` |
| `["transfer-encoding", "chunked"]` | `[["transfer-encoding", "chunked"]]` — transmitted |
| `["content-length", "0"]` | `[]` — consumed by the framing layer |
| `["connection", "close"]` | `Protocol::HTTP2::StreamError: Stream closed!` with **no `#cause`** — the *server* rejected it per RFC 9113 §8.2.2 |

Three of those are protocol violations the library will happily emit. The first is the one that matters:
**on the HTTP/2 path, `DEF-25`'s wire-boundary re-validation is the only thing between a forged
`Dexpace::Request` and an injected header**, because nothing below the model validates. Design §10.10
describes the re-validation as making "the residual gap a correctness-of-shape gap, not a
request-splitting gap"; on this path it is literally the request-splitting defence. Knowledge note, and
`R13`/`R16`.
*Command:* `ruby scratchpad/p8c/h2hdr.rb` under the scratchpad `GEM_HOME`.

### 5. On HTTP/1.1 the same headers behave in three different, all-dangerous ways — and the `BadHeader` exception arrives **after** the request line is on the wire.

Captured as exact bytes with a raw `TCPServer` recording the request:

```
GET, caller sets nothing        "GET /p HTTP/1.1\r\nhost: 127.0.0.1:36133\r\ncontent-length: 0\r\n\r\n"
POST body, no framing headers   "POST /p HTTP/1.1\r\nhost: …\r\ncontent-length: 3\r\n\r\nabc"
POST body + content-length: 3   "POST /p HTTP/1.1\r\nhost: …\r\ncontent-length: 3\r\ncontent-length: 3\r\n\r\nabc"
POST body + host: bogus.example "POST /p HTTP/1.1\r\nhost: 127.0.0.1:36715\r\nhost: bogus.example\r\ncontent-length: 3\r\n\r\nabc"
POST body + transfer-encoding   "POST /p HTTP/1.1\r\nhost: …\r\ntransfer-encoding: chunked\r\ncontent-length: 3\r\n\r\nabc"
GET + "Bad Name"                "GET /p HTTP/1.1\r\nhost: 127.0.0.1:45229\r\n"          ← partial; then raised
GET + value "a\r\nEvil: 1"      "GET /p HTTP/1.1\r\nhost: 127.0.0.1:35547\r\n"          ← partial; then raised
GET + "X-MiXeD-CaSe"            "GET /p HTTP/1.1\r\nhost: …\r\nX-MiXeD-CaSe: v\r\ncontent-length: 0\r\n\r\n"
```

Four conclusions, each load-bearing:

1. **`async-http` auto-stamps exactly two headers — `host` and `content-length` — and nothing else.** No
   `user-agent`, no `accept`, no `accept-encoding`. That is the opposite of the charter's fact 4 for
   `Net::HTTP`, which stamps four and recomputes `Content-Length`.
2. **A caller-set framing header is not recomputed; it is *duplicated*.** `content-length: 3` twice;
   `host:` twice; `transfer-encoding: chunked` **beside** `content-length: 3`. Those are the canonical
   CL.CL and TE.CL request-smuggling shapes. `TRANSPORT-11`'s drop is therefore a **security** requirement
   on this adapter, not the hygiene requirement it is on an adapter that recomputes.
3. **`Protocol::HTTP1::Connection#write_request` writes `"#{method} #{target} #{version}\r\n"` and
   `"host: #{authority}\r\n"` *before* calling `write_headers`** (`protocol-http1-0.41.0/lib/protocol/http1/connection.rb:262-270`),
   and then `rescue`s **everything** and re-raises as `::Protocol::HTTP::RefusedError`. So a
   `BadHeader` on the fourth header arrives with a partial request already on the socket, and
   `TRANSPORT-12`'s "the rest of the headers and the body MUST still be dispatched" is unreachable on
   that connection. Ruby's implicit `cause` survives the rewrap — measured:
   `RefusedError#cause` is `#<Protocol::HTTP1::BadHeader: Invalid header name: "Bad Name">` — but the
   discriminator arrives too late to be useful.
4. **The poisoned connection is not reused.** After the refused request, three subsequent requests through
   the same client each reached the server intact and uncorrupted. `Client#call`'s `rescue
   ::Protocol::HTTP::RefusedError` releases the connection and the pool retires it. Good behaviour that
   8c must not rely on: the design drops pre-dispatch so the case never arises.

`Protocol::HTTP1::VALID_FIELD_NAME` is `/\A#{FIELD_NAME}\z/` over the RFC 7230 token set and
`VALID_FIELD_VALUE` is `/\A#{FIELD_VALUE}?\z/` over `[^\0\r\n]+` — strictly **wider** than `HTTP-18`'s
HTAB-plus-0x20–0x7E, so on HTTP/1.1 no *value* ever needs dropping and only *names* do.
*Commands:* `ruby scratchpad/p8c/wire1.rb`, `ruby scratchpad/p8c/poison.rb` under the scratchpad `GEM_HOME`.

### 6. The response body is lazy, pull-shaped, BINARY, unfrozen, and its close does not drain.

Against a `TCPServer` writing five body bytes, sleeping 400 ms and writing five more, with
`Content-Length: 10`:

- `client.get("/dribble")` **returned the response object at 1 ms**; `body.read` yielded `"aaaaa"` at 1 ms,
  `"bbbbb"` at 401 ms, and **`nil`** at end of stream.
- Chunks are `ASCII-8BIT` and **not frozen**, so `io-and-byte-streams/a44b4de6`'s `String#b` retag is a
  no-op here and `force_encoding`'s `FrozenError` trap cannot fire. 8c still routes through the same
  helper, so the property is asserted rather than assumed.
- The body's surface is `#read`, `#each`, `#close`, `#discard`, `#length`, `#stream?`, `#rewindable?`,
  `#buffered`, `#join`, `#rewind`, `#ready?`, `#empty?`, `#finish`, `#call`, `#to_io` — a pull contract
  that maps onto `Dexpace::Body#each` and `BufferedSource.over` with no pump, no fiber and no thread.
- **`response.close` on a 4 MiB unread body returned in 6 ms**, so close discards rather than drains —
  which is `TRANSPORT-16`'s "no unbounded await" satisfied at the *response* level. A separate 4 MiB read
  round-tripped **4 194 304 bytes exactly**, which is `TRANSPORT-25`'s own conformance clause.
- `Content-Length` does **not** appear in `response.headers.fields`; the length is `response.body.length`,
  and it is **`nil`** when the server sends none. **That `nil` is the *native* absence, not the SDK's
  sentinel**: `TRANSPORT-27`'s canonical text fixes the unknown-length sentinel as **`-1`** ("an
  absent/invalid Content-Length SHOULD map to the SDK's unknown-length sentinel (-1)"), and `BODY-35`
  fixes the same value on `Dexpace::Body#content_length`. The adapter maps `nil` → `-1` at the point it
  reads the native length, and no `nil` length ever crosses into the SDK model. (Corrected 2026-09-12;
  the earlier sentence read the native `nil` as the sentinel itself.)
- Abandoning an unread body and then issuing another request **opened no new connection** — the pool
  reclaimed it.

*Command:* `ruby scratchpad/p8c/lifetime.rb`, `ruby scratchpad/p8c/body.rb` under the scratchpad `GEM_HOME`.

### 7. A streaming request body is never materialised, and it is read exactly once per unit of demand.

A `Protocol::HTTP::Body::Readable` subclass whose `#read` returns `"hel"`, `"lo!"`, `nil` and whose
`#length` is `nil` and `#rewindable?` is `false` was sent as a POST body. The server received
`"3\r\nhel\r\n3\r\nlo!\r\n0\r\n\r\n"` — chunked transfer-encoding — and the body object recorded
**exactly three `#read` calls** for two chunks plus end-of-stream. `Protocol::HTTP::Body::Buffered.wrap`
of an `#each`-yielding object, by contrast, **materialises it** (`join == "ab"` for a two-chunk source),
so `Buffered.wrap` is the wrong bridge for a `Dexpace::Body` and a `Readable` subclass is the right one.
The same measurement is `SSE-39`'s and `ASYNC-21`'s backpressure property on the write side, and
fact 6's dribble timings are it on the read side.

`Protocol::HTTP::Request#retry!` returns **`false`** for `POST`, `PATCH` and `CONNECT` outright, and
otherwise delegates to `#rewind!`, which delegates to `body.rewind` — `false` for a non-rewindable body.
So a single-use body is never re-read even before `retries: 0` is considered. `TRANSPORT-17` and
`TRANSPORT-18` have two independent reasons to hold on this adapter.
*Command:* `ruby scratchpad/p8c/last.rb`, `ruby scratchpad/p8c/body.rb` under the scratchpad `GEM_HOME`.

### 8. Cancellation is real, it runs `ensure`, `rescue StandardError` is blind to it, and a **parent** task's cancellation reaches an in-flight exchange.

- `Async::Stop.equal?(Async::Cancel)` is **`true`**; `Async::Cancel.ancestors.take(3)` is
  `[Async::Cancel, Exception, Object]`. The charter's fact 9, reproduced.
- A task cancelled from outside ran `rescue Exception` and its `ensure`, **never** its
  `rescue StandardError`, and settled `status == :cancelled`.
- **Cancelling a task blocked in `response.body.read` aborted the read and ran the `ensure`** — the
  observed event sequence was `["got-response", "chunk1", "ensure-ran"]` with the 400 ms second chunk
  never arriving. That is `TRANSPORT-7` measured: "cancel an in-flight future and assert the native call
  is cancelled."
- Cancelling a task blocked in the pool's `acquire` likewise delivered `Async::Cancel` and the task
  completed.
- **Cancelling a *parent* task delivers `Async::Cancel` to its in-flight child**: the event sequence was
  `["outer-saw:Async::Cancel", "inner:Async::Cancel", "inner-ensure"]`. This is `TRANSPORT-8`'s antecedent
  — a cancellation the SDK did not initiate, arriving while the pivot is live, from the host runtime's own
  structured-concurrency scope. `R14`.
- `Async::Task#cancel(later = false, cause: $!)` accepts a **`cause:`**, and the cancelled task's
  `Async::Cancel#cause` **is the object passed**. That is the out-of-band channel `XCUT-2` and
  `TRANSPORT-3` want: a `Dexpace::Cancellation#reason` travels as the cause and is read back by class.
- `#stop` on an **already-finished** task is a no-op: `status` stayed `:completed` and `#wait` still
  returned the value. `ASYNC-20` and `TRANSPORT-9` are friendly here rather than hostile.
- A graceful HTTP/2 **GOAWAY** sent from the server mid-stream did **not** abort the in-flight stream; the
  client read it to completion. So GOAWAY is *not* `TRANSPORT-8`'s antecedent on this stack, and `R14`
  says so rather than assuming it.

*Commands:* `ruby scratchpad/p8c/cancel.rb`, `ruby scratchpad/p8c/goaway.rb`, `ruby scratchpad/p8c/final.rb`
under the scratchpad `GEM_HOME`.

### 9. `async-http` requires a reactor, the pool is unbounded by default, `Client#close` is an unbounded await, and concurrency is correct.

- **A full round trip outside any `Async`/`Sync` block raises `RuntimeError: No async task available!`**,
  from `Async::Task.current` (`async-2.45.1/lib/async/task.rb:438`). A *connect* to a dead port outside a
  reactor gets as far as `Errno::ECONNREFUSED`, which is why a shallow probe would conclude the opposite.
  `Fiber.scheduler` is `nil` and `Async::Task.current?` is `nil` outside. Inside `Sync { }` the same call
  works.
- **`Async::HTTP::Client.new(endpoint)` builds its pool with `limit: nil` — unbounded.** Eight concurrent
  requests against a slow endpoint opened **seven** new connections beside the one reused. All eight
  returned their own correct response with no cross-talk, which is `ASYNC-22`'s conformance clause; three
  serial requests opened **one** connection, which is keep-alive reuse.
- **`Async::HTTP::Client#close` blocked for 253 ms with one request in flight**, because it is
  `@pool.wait_until_free { Console.warn(self){"Waiting for #{@protocol} pool to drain: #{@pool}"} }`
  followed by `@pool.close`, and `wait_until_free` is `@condition.wait(@mutex) while busy?` — an
  **unbounded** await. It also writes a JSON `warn` line to the host's **stderr**, because `Console`'s
  default output is `Console::Output::Failure` at level `warn`. `XCUT-13` and `TRANSPORT-16` forbid the
  first; nothing in this SDK may do the second. Decision below; deviation `P8-37`.
- `Async::Pool::Controller`'s own `#close` is `drain` (retire every resource) then clear and stop the
  gardener — no wait. `Client` exposes `attr :pool`, so the non-blocking route is reachable.

*Command:* `ruby scratchpad/p8c/pool.rb`, `ruby scratchpad/p8c/env.rb`, `ruby scratchpad/p8c/lifetime.rb`
under the scratchpad `GEM_HOME`.

### 10. `Async::Task#stop` is a deprecated alias for `#cancel`, `with_timeout` raises a `StandardError`, and `Async { }` inside a reactor is not a child of the caller.

- `async-2.45.1/lib/async/node.rb` carries `# @deprecated Use {#cancel} instead.` immediately above
  `def stop(...) = cancel(...)`. Design §3.3 `:252-254` and the corpus entry
  `concurrency-and-async/f75816b6` both name `Async::Task#stop` as the primitive. **8c calls `#cancel`.**
  `OI-40`.
- `Async::Task#with_timeout(0.2) { client.get("/slowhdr") }` against a server that sleeps 2 s raised
  `Async::TimeoutError` after **200 ms**, with `ancestors.take(4) == [Async::TimeoutError, StandardError,
  Exception, Object]`, and the enclosing `ensure` ran. So one deadline value maps onto one
  `with_timeout`, it interrupts a blocked exchange, it is a `StandardError`, and it is therefore
  **distinguishable from a cancellation by class alone** — `TRANSPORT-4` and `TRANSPORT-8`'s "a genuine
  timeout on the same path MUST still complete retryable" satisfied by the runtime.
- **`Async { }` evaluated inside a running reactor reuses the scheduler but the new task's `#parent` is
  not the calling task** (`inner.wait.parent.equal?(outer_task)` was `false`); `Fiber.scheduler` inside is
  `Async::Reactor`. `Async::Task.current.async { }` is the child-making call. 8c uses the latter, so a
  caller's structured cancellation composes.
- **`Fiber[]` is inherited by a child `Async::Task` and copy-on-write protects the parent's slot**:
  with `Fiber[:trace_id] = "outer"` set, the child read `"outer"`, and a child writing
  `Fiber[:trace_id] = "inner"` left the parent reading `"outer"`. So diagnostic context crosses 8c's task
  boundary for free.

*Commands:* `ruby scratchpad/p8c/cancel.rb`, `ruby scratchpad/p8c/last.rb`, `ruby scratchpad/p8c/final.rb`
under the scratchpad `GEM_HOME`.

### 11. Not one error `async-http` raises is an `::IOError`, and inbound headers are lenient in two places and fatal in a third.

Ancestries measured on the live wire, not read from source:

| Provocation | Raised | Ancestry head |
|---|---|---|
| connect to a dead port | `Errno::ECONNREFUSED` | `SystemCallError, StandardError` |
| DNS failure | `Socket::ResolutionError` | `SocketError, StandardError` |
| TLS to a plaintext port | `OpenSSL::SSL::SSLError` | `OpenSSL::OpenSSLError, StandardError` |
| peer reset mid-body | `Protocol::HTTP::RemoteError` | `Protocol::HTTP::Error, StandardError` |
| header the wire grammar rejects | `Protocol::HTTP::RefusedError` | `Protocol::HTTP::Error, StandardError` |
| `connection:` on HTTP/2 | `Protocol::HTTP2::StreamError` | `Protocol::HTTP2::ProtocolError, Protocol::HTTP2::Error, Protocol::HTTP::Error, StandardError` |
| a deadline | `Async::TimeoutError` | `StandardError` |
| a cancellation | `Async::Cancel` | **`Exception`** |
| body write/read of a bad `Content-Length` | `Protocol::HTTP1::BadRequest` | `Protocol::HTTP1::Error, Protocol::HTTP::Error, StandardError` |

`XCUT-4` branch (b) requires the canonical transport failure to "belong to the runtime's I/O-error
family"; `EOFError` is the only one of the family above that is already an `::IOError`. This is the
phase-level `Dexpace::TransportError < ::IOError` task's whole justification, arriving from the async side
as well as the sync side.

Inbound headers, measured against a raw server:

- an obs-text byte in a **value** (`X-Obs: caf\xE9`) came back as `["X-Obs", "caf\xE9"]`, both
  `ASCII-8BIT` — `TRANSPORT-14`'s SHOULD satisfied by the library;
- a **control byte** in a value (`X-Ctl: a\x01b`) came back intact and must be dropped by the adapter
  before it reaches `Dexpace::Headers::Builder`, which `XCUT-18` makes reject it;
- **a non-ASCII byte in a header *name* (`X-B\xE9d: v`) raises `Protocol::HTTP1::BadHeader: Could not
  parse header` and fails the whole response.** `TRANSPORT-14` requires that case to "drop only that
  header … while the body and remaining headers are still delivered". **It is unreachable on this
  adapter.** `OI-39`, deviation `P8-38`, and a named waiver in the conformance run.

Status mapping is total: `520` and `499` both surfaced faithfully with readable bodies. A malformed
inbound `Content-Type` (`not a/;;media type`) passed through untouched, so `TRANSPORT-27`'s media-type
half is free; a malformed `Content-Length: abc` raised `Protocol::HTTP1::BadRequest: Invalid content
length: "abc"` out of the read, so `TRANSPORT-27`'s length half is **unreachable here for the same reason
the charter's fact 12 makes it unreachable on `Net::HTTP`** — a report to `8a`'s `R4`, not a row.
*Commands:* `ruby scratchpad/p8c/env.rb`, `ruby scratchpad/p8c/pool.rb`, `ruby scratchpad/p8c/lifetime.rb`,
`ruby scratchpad/p8c/final.rb` under the scratchpad `GEM_HOME`.

### 12. The dependency closure is 17 specs, one native extension, no `traces` and no `metrics`; and `require "async/http"` is warning-clean.

Walking `runtime_dependencies` transitively from `async-http 0.104.0` gives **17 specs including
`async-http` itself**: `async`, `async-pool`, `console`, `fiber-annotation`, `fiber-local`,
`fiber-storage`, `io-endpoint`, **`io-event` (native extension, `ext/extconf.rb`)**, `io-stream`, `json`,
`openssl`, `protocol-hpack`, `protocol-http`, `protocol-http1`, `protocol-http2`, `protocol-url`. `json`
and `openssl` are **default gems** in any normal bundle, so the third-party install count is **15**, which
reproduces the charter's fact 7. **`traces` and `metrics` are not in this closure** — earlier `async`
releases carried them and 2.45.1 does not, so any list written from memory is wrong. `async-http`'s
declared runtime dependencies are exactly `async >= 2.35.1`, `async-pool ~> 0.12`, `io-endpoint ~> 0.18`,
`io-stream ~> 0.14`, `protocol-http ~> 0.66`, `protocol-http1 ~> 0.41`, `protocol-http2 ~> 0.28`,
`protocol-url ~> 0.2`; its licence is MIT.

`RUBYOPT=-W:deprecated ruby -w -e 'require "async/http"'` printed **no warnings**, which matters because
phase 0's `test:gems` runs "warnings fatal". `Gem::BUNDLED_GEMS::SINCE` on 3.4.10 has **no entry** for
`openssl` or `uri`, and both are default gems, so the adapter may `require` them under the same rule core
lives by; the 4.0.6 re-check is owed by the plan.
*Commands:* `ruby scratchpad/p8c/deps.rb`; `RUBYOPT=-W:deprecated ruby -w -e 'require "async/http"'`;
`ruby -e 'p Gem::BUNDLED_GEMS::SINCE["openssl"]'`.

### 13. `Async::HTTP::Endpoint` accepts a `URI` object parsed by `URI::RFC3986_PARSER`, and neither `Internet` nor the client installs a redirector.

`Async::HTTP::Endpoint.parse` uses `URI.parse`, i.e. `URI::DEFAULT_PARSER`, which is
`URI::RFC3986_PARSER` on 3.4.10 and `URI::RFC2396_PARSER` below 3.4 — exactly the straddle §3.5 pins
against. But `Async::HTTP::Endpoint.new(url)` takes a `URI` object directly and only requires
`url.absolute?`: `Endpoint.new(URI::RFC3986_PARSER.parse("http://example.com:8080/a%20b?q=1"))` produced a
working endpoint with `scheme == "http"`, `authority == "example.com:8080"` and
`path == "/a%20b?q=1"`. **8c therefore never calls `Endpoint.parse`.**

`Async::HTTP::DEFAULT_RETRIES` is **3**, and `Async::HTTP::Client#call` retries on
`Protocol::HTTP::RefusedError` (resending even non-idempotent requests, since the server did not process
them) and on `Protocol::HTTP::RemoteError, SocketError, IOError, EOFError, Errno::ECONNRESET,
Errno::EPIPE` when `request.retry!`. `retries: 0` removes the loop entirely (`attempt` starts at 1, so
`attempt < 0` is never true). `Async::HTTP::Middleware::LocationRedirector` exists as the only file under
`lib/async/http/middleware/`, and **`Async::HTTP::Internet` does not install it** — its source contains no
reference to the constant. So `TRANSPORT-1` is satisfied by not wrapping and `TRANSPORT-2` by
`retries: 0`, and both are load-bearing rather than vacuous on this adapter.
*Commands:* `ruby scratchpad/p8c/env.rb`; `ruby -e 'require "async/http"; p Async::HTTP::DEFAULT_RETRIES'`.

### What this document could not verify, and does not assert

1. **Every fact above on Ruby 3.2.11, 3.3.x and 4.0.6.** Only 3.4.10 is installed. Ruby 3.2 is
   *structurally* out of reach for this gem (fact 1), which is `R15`'s whole subject; 3.3 and 4.0 are
   reachable and the plan runs them.
2. **Whether `gem_rbs_collection` carries signatures for `async-http` or any of its closure.** No network
   index for that was consulted, and the `rbs_collection.yaml` row's exact form depends on it. Named as an
   open question for the plan, with both branches specified.
3. **Whether `io-event` builds on every platform the CI matrix runs.** It compiles C; only x86_64-linux
   was exercised. `R15` records the consequence rather than a measurement.
4. **HTTP/2 flow-control and multiplexing under load.** Facts 2, 3 and 4 exercise the h2 path
   functionally — negotiation both ways, headers, bodies, stream errors — but not concurrent streams on
   one connection under window pressure. The plan's `ASYNC-22` test covers concurrency on HTTP/1.1;
   the h2 multiplexing test is named as a plan task, not claimed here.
5. **Whether a proxy is reachable at all through `Async::HTTP::Proxy`.** `TRANSPORT-30` is `8a`'s ⏳ row
   against `DEF-10` and 8c touched none of it.

---

## `R13` — where the orphan close lives, given that a cancelled task raises outside `StandardError`

**The charter's question.** `SEAM-30`, `ASYNC-5`, `TRANSPORT-9` and `TRANSPORT-22` all require a response
to be closed on a path where nobody will receive it, and `Async::Cancel < Exception` — with `Async::Stop`
a deprecated *alias* of that same class, not a subclass — means a `rescue` written the obvious way never
runs on a cancellation while it does run on `Async::TimeoutError`. `OI-37`.

**The decision, in four parts.**

**1. Every close of a resource 8c owns sits in an `ensure`, and 8c writes no `rescue StandardError` that a
close depends on.** The rule is stated once here and is a lint-able shape: *in the exchange task, the
native response is assigned to a local before anything can raise, and a single `ensure` closes it unless
`Completer#fulfil` returned `true`.* `Completer#fulfil` is what decides ownership — phase 2 made
`#fulfil` on an already-settled future "return `false` **and close the response it was handed**", so the
adapter's `ensure` only has to handle the case where `#fulfil` was never reached at all. Sketch, with
every branch named by the ID it discharges:

```ruby
native = nil
delivered = false
begin
  native = client.call(protocol_request)          # may raise, may be cancelled
  cancellation.check!                             # check-after-resume (concurrency-and-async/611b9392)
  response = ResponseMapper.call(native, ...)     # TRANSPORT-22: may raise with the socket live
  delivered = completer.fulfil(response)          # TRANSPORT-23, ASYNC-1; false on a lost race
rescue *WRAPPED => e                              # TRANSPORT-20, TRANSPORT-21, P6-4
  completer.fail(Errors.wrap(e))                  # pipeline/f02559b9: never a bare `raise`
ensure
  # TRANSPORT-9, TRANSPORT-22, ASYNC-5, SEAM-30, CFG-21 — and the only branch Async::Cancel reaches.
  Dexpace.close_quietly(native) unless delivered
end
```

The `ensure` runs on **every** exit: a normal return, a wrapped failure, an `Async::TimeoutError`, an
`Async::Cancel`, a `NoMemoryError`. That is the whole repair, and it is one line.

**2. `Dexpace.close_quietly` is still correct and 8c adds no second exit.** `OI-37` is careful about this
and 8c agrees: `close_quietly` rescues `StandardError` **from `#close`**, which is a different question
from what reaches the call site. `Protocol::HTTP::Body::Readable#close` raises `StandardError`s or
nothing; it does not raise `Async::Cancel` of its own. So the helper's rescue is unaffected, and a second
helper would give the SDK two answers to one question.

**3. `rescue Async::Cancel` and `rescue Async::Stop` name one class; 8c writes neither.** An adapter that
writes both has written one (`OI-37`). 8c writes *no* rescue of either: a cancellation propagates out of
the exchange task untouched, and the `ensure` closes the undelivered response and calls
`Completer#request_cancel(reason)`, which is what settles the pivot cancelled. Inspecting `$!` inside that
`ensure` is how the branch is taken — an inspection, never a rescue, so the exception still propagates and
the task still settles `:cancelled`. (Corrected 2026-09-12; the earlier sentence named
`Completer#on_cancel`, which registers a hook and settles nothing.) **`Async::Cancel` is on the `TRANSPORT-21` fatal list** — one of
exactly five things permitted to propagate — precisely so that nothing in 8c can convert a cancellation
into a transport failure by accident.

**4. Discrimination is out-of-band, twice over, and neither route matches a message.** `TRANSPORT-3`'s and
`TRANSPORT-8`'s requirement is that a cancellation be told from a timeout by runtime state, "not by
matching messages". 8c has two independent channels and uses both:

| Question | Channel | Verified |
|---|---|---|
| Was this a cancellation or a deadline? | `Async::Cancel < Exception` versus `Async::TimeoutError < StandardError` | fact 10 |
| Was this cancellation *ours* or the runtime's? | `Async::Cancel#cause` — `task.cancel(cause: token.reason)` puts the SDK's typed reason there; a cancellation from a parent scope carries something else | fact 8 |
| Independently of the exception: is the token cancelled? | `Dexpace::Cancellation#cancelled?` and `#reason.class` | phase 2 |

The second row is what makes `TRANSPORT-8` implementable rather than merely detectable, and it is the key
fact `R14` rests on.

**The test that a correct-looking wrong implementation passes, and the one it does not.** The charter names
it: "writes a test asserting the close ran on a **cancellation** specifically — not only on a timeout,
which is the test a correct-looking wrong implementation passes." 8c's suite carries both, deliberately
paired in one file so neither can be deleted without the other being noticed:

- **`test_orphan_closed_on_timeout`** — a slow server, `with_timeout` shorter than it, assert the native
  body's `#close` was called exactly once. **An implementation that puts the close in a
  `rescue StandardError` passes this.**
- **`test_orphan_closed_on_cancellation`** — the same server, the exchange task cancelled from outside,
  assert the same close happened exactly once. **The `rescue StandardError` implementation fails this**,
  because `Async::Cancel` is not a `StandardError`. Measured in fact 8: the `rescue StandardError` branch
  did not run and the `ensure` did.
- **`test_delivered_response_not_closed_by_late_cancel`** — the negative twin (`ASYNC-20`): fulfil, hand
  the response to a consumer, cancel the future, assert `#close` was **not** called. Fact 8's "stop on a
  finished task is a no-op" is what makes it pass.

Counting the close is done with a recording double over `Protocol::HTTP::Body::Readable`, not by watching
the socket, so the assertion is `close_count == 1` and not "the connection looked released".

---

## `R14` — `TRANSPORT-8`'s and `TRANSPORT-18`'s dispositions, both of which the charter could not verify

**The charter's question**, quoted so the answer is against the right text: "`TRANSPORT-8` needs a
cancellation 'originating inside' the client while the SDK future is live — candidates are `async-pool`
reaping a connection, an HTTP/2 GOAWAY, and `Protocol::HTTP::RefusedError`. `TRANSPORT-18` needs a
re-subscribable producer driving a native internal resend … **Every async probe in this document ran
HTTP/1.1 against a local `TCPServer`; the HTTP/2 path was not exercised.**"

**The HTTP/2 path is now exercised** (facts 2, 3 and 4): a plaintext prior-knowledge h2 client and server
in process, and a TLS endpoint with real ALPN negotiation. Every candidate is answered from a
measurement.

### `TRANSPORT-8` — **satisfied on this adapter**, and §12 records it vacuous

Three candidates, tested:

| Candidate | Result | Is it `TRANSPORT-8`'s antecedent? |
|---|---|---|
| An HTTP/2 **GOAWAY** arriving mid-stream | The in-flight stream **completed normally**; the client read all four body chunks (fact 8). | **No.** A graceful GOAWAY does not abort an open stream. |
| `Protocol::HTTP::RefusedError` | Raised when the server did not process the request; `Client#call` treats it as safe-to-resend. | **No.** It is a retryable transport failure, not a cancellation. It is `TRANSPORT-20`'s. |
| **A cancellation arriving from the host runtime's own structured-concurrency scope** — the caller's enclosing `Async::Task` being cancelled, or the reactor being torn down | `Async::Cancel` is delivered into the in-flight exchange while the pivot is still live; `ensure` runs; the task settles `:cancelled` (fact 8). | **Yes.** |

The third is not a contrived case. It is the ordinary shape of `async`: a consumer writes
`Async { … sdk.get(…) … }` inside a supervisor, the supervisor cancels its children on shutdown or on a
sibling's failure, and the adapter's exchange — a *child* of that task, by design — receives
`Async::Cancel` that no `Dexpace::Cancellation` produced. The requirement's own example is "an internal
cancel-all", and a reactor tearing down its task tree is exactly that.

**So `TRANSPORT-8` is satisfied here, and satisfying it is one branch:** when the exchange ends in
`Async::Cancel`, the pivot settles **cancelled** — `Dexpace::CancelledError`, terminal and
non-retryable — and when it ends in `Async::TimeoutError` the pivot settles with a **retryable**
`Dexpace::TransportError`. That is the requirement's two clauses, discriminated by class, and the
discrimination is free because `async` put the two exceptions in different halves of the exception tree
(fact 10).

**The consequence for §12, which 8c cannot fix.** `docs/sdk-design-ruby/12-…md:41` lists `TRANSPORT-8`
among the requirements "adapter-scoped and vacuous for `Net::HTTP`", and the MUST-level summary counts it
among "eight [that] hold vacuously". §9.3 is the more careful of the two — "**TRANSPORT-8** and
**TRANSPORT-18** vacuous for `Net::HTTP` and **mandatory for any adapter whose client has those paths**" —
and `async-http` has the path. §12 is frozen. **`OI-41`** records the correction, which is the same
species as the charter's `OI-34` and must be filed as one; the difference, and it is in the port's favour,
is that this correction *adds* a satisfied MUST rather than removing a vacuous one.

**What 8c does not claim.** `TRANSPORT-8` says "a transport with no internal-cancel path need not support
it". 8c has one and supports it. It does not claim that every way `async` can cancel a task has been
enumerated — only that at least one is live, which is all the antecedent needs, and that the
discrimination holds for any of them because it is by exception class.

### `TRANSPORT-18` — the antecedent is **removed by construction**, twice, and the row stays `8a`'s

`TRANSPORT-18`'s antecedent is "the native body API drives writes through a re-subscribable producer (so a
native internal resend — proxy-auth 407, protocol GOAWAY replay — re-reads the body)".
`Async::HTTP::Client#call` **is** exactly such a loop (fact 13): `begin … rescue
Protocol::HTTP::RefusedError … if attempt < @retries and request.rewind! then retry`. Two independent
things remove it:

1. **`retries: 0`.** `attempt` is incremented to 1 before the body of the `begin`, so `attempt < 0` is
   never true and the loop never re-subscribes. This is `TRANSPORT-2`'s obligation, and — exactly as the
   charter's fact 1 found for `Net::HTTP`'s `max_retries` — it is **not vacuous** on this adapter either:
   the default is 3, not 0.
2. **`Protocol::HTTP::Request#retry!` refuses anyway** (fact 7): `false` outright for `POST`, `PATCH` and
   `CONNECT`, and otherwise `body.rewind`, which a non-rewindable streaming body answers `false`. So even
   at `retries: 3` a single-use body is never re-read.

**8c *reports*; it takes no row.** The charter fixes this: "**`TRANSPORT-18`'s row stays `8a`'s** under
the one-row-per-ID convention: `8c` *reports* whether the antecedent is live on `async-http`, and `8a`
amends the row's stated reason if it is." The report to `8a`, in one sentence: *the antecedent is live on
`async-http` and is removed by `retries: 0` plus `Request#retry!`'s own refusal, which is the same shape
as `max_retries = 0` on `Net::HTTP`, so §11.18's "`Net::HTTP` has no resend hook" is right about
`Net::HTTP` and the general clause "both are near-vacuous for the MVP adapters" is wrong about this one.*

**What 8c reports to `8a`, collected** — five items, none of them a row:

| Report | Evidence | `8a` risk it lands on |
|---|---|---|
| `TRANSPORT-18`'s antecedent is live here and removed by `retries: 0` | fact 13 | — (the row's stated reason) |
| `TRANSPORT-27`'s invalid-`Content-Length` clause is unreachable **on this adapter** — `Protocol::HTTP1::BadRequest` is raised out of the read and no response object exists to downgrade. **Corrected 2026-09-12**: this row said "on **both** adapters, for the same reason", which `8a` measured to be false of `Net::HTTP` — under the block form `8a` uses, the head arrives in full and the raise comes later, from `Net::HTTPResponse#content_length`, so `8a` implements the clause. The waiver is 8c's driver's alone | fact 11; `8a` design's verified fact 12 | `R4` (resolved there as satisfied whole) |
| `TRANSPORT-28`'s reachable half is *more* reachable here — `protocol-http` ships `Protocol::HTTP::Body::File` with `#offset`, `#rewind` and `#rewindable?` | charter fact 15 | `R5` |
| `TRANSPORT-11`'s drop set is **security-critical** on this adapter, because a caller-set framing header is duplicated rather than recomputed | fact 5 | `R2` |
| `TRANSPORT-14`'s malformed-**name** clause is unreachable here; `8a`'s row should say the requirement is satisfied on `Net::HTTP` and waived on `async-http`, not satisfied outright | fact 11 | `OI-39`, `P8-38` |

---

## `R15` — `NFR-2`'s budget against a fifteen-gem transitive closure with a native extension, and the Ruby floor

### The `NFR-2` verdict: **satisfied**, and it is not close

`dexpace-transport-async_http.gemspec` declares exactly two runtime dependencies:

```ruby
spec.add_dependency "dexpace-core", "~> #{VERSIONS.fetch("gem")[0, ...]}"   # ~> MAJOR.MINOR, §2.3
spec.add_dependency "async-http",   "~> 0.104"
```

One of them is `dexpace-core`. **One** is third-party. `NFR-2`'s words are "SHOULD be a separately
installable unit that **depends on the core plus at most one third-party library**", and phase 0's
`gates:gemspec_audit` counts declared `runtime_dependencies`. Both are satisfied literally.

**The argument for counting declarations and not the closure**, made rather than assumed, because the
charter asks for it and because the answer decides whether a deviation is owed:

1. **The requirement's subject is the *unit a consumer installs*, not the graph it pulls.** Its own
   rationale is "so a consumer composes only the units it uses and incurs no cost for unused ones" — a
   statement about *this* project's units. A consumer who does not want a reactor does not install this
   gem and pays nothing; that is the property `NFR-2` protects, and it holds exactly.
2. **The closure reading makes `NFR-2` unsatisfiable by any real Ruby HTTP library.** `httpx`, `excon`,
   `typhoeus` and `faraday` all carry closures; §2.2 names three of them as future adapters, so a reading
   that forbids this one forbids those, and §2.1's own table — which lists `async-http` as the single
   dependency of this gem — would be self-contradicting.
3. **The corpus states the rule in declaration terms throughout.** The *Gem layout, zero-dependency core*
   group (14 entries) contains no rule about transitive closures, and the one that comes closest is about
   identity rather than count: "In Ruby, Bundler activates exactly one version of a gem per process,
   `require` de-duplicates by resolved feature path, and constants live in one process-global namespace".
4. **The absolute rule is core's, and it is untouched.** `dexpace-core.gemspec` still has zero
   `add_dependency` lines; the require-allowlist audit still scans core; the clean-bundle isolation run
   still proves core loads alone. `SEAM-1` and `NFR-1` are about *core*, and 8c changes nothing there.

**No deviation is owed for the closure.** Three consequences are, and each is an action rather than a
note:

- **A `docs/first-release.md` line for the native extension.** `io-event` compiles C (`ext/extconf.rb`).
  A consumer on a platform without a toolchain, or on a Ruby with no precompiled `io-event` gem, cannot
  install `dexpace-transport-async_http` — and **can** install `dexpace-core` plus
  `dexpace-transport-net_http`, which is `NFR-2`'s separability paying for itself. The release note says
  so in one sentence rather than leaving a failed `gem install` to say it.
- **`bundler-audit`'s surface grows by fifteen gems**, which is the first time in this repository that
  gate has had anything to check. That is a cost worth naming and not a reason to decline: an advisory
  against `protocol-http2` is exactly what the gate exists to surface, and the alternative — writing an
  HTTP/2 stack — is not on the table.
- **An `rbs_collection.yaml` row.** Open question for the plan (below), because whether
  `gem_rbs_collection` carries signatures for any of the closure was not verifiable here.

### The Ruby floor: **`required_ruby_version >= 3.3` for this gem alone**, deviation `P8-36`

**The collision, stated exactly.** `async-http 0.104.0` declares `required_ruby_version >= 3.3` and so
does every gem in its closure except `fiber-annotation`, `fiber-local`, `fiber-storage`, `json`,
`openssl` and `protocol-hpack` (fact 1). Phase 0's `gates:versions` asserts that **every** gemspec's
`required_ruby_version` equals `>= ` plus `VERSIONS`'s single `ruby floor` line, which is `3.2`, and the
CI matrix runs `3.2 3.3 3.4 4.0` with `test:gems`, `gates:gemspec_audit`, `gates:require_allowlist` and
`gates:clean_bundle` on **every** row.

**Three options were weighed.**

**(a) Declare `>= 3.2` and let Bundler resolve `async-http 0.94.2` on Ruby 3.2.** Bundler honours
`required_ruby_version` during resolution, so `add_dependency "async-http", ">= 0.94.2"` would install
0.94.2 with `async <= 2.37.0` on the 3.2 row and 0.104.0 on every other. **Rejected**, on one ground that
outranks the others: *a floor a gem declares must be a floor it is tested on*, and the only stack that
resolves on 3.2 is eleven minor releases behind the one this document measured, on an interpreter that is
not installed here. The adapter would be claiming support for an `async-http` whose HTTP/2 behaviour,
error ancestries, pool defaults and `Async::Task#cancel`-versus-`#stop` spelling this design has verified
for **none** of. Every one of the thirteen verified facts above would become "verified on the version
three of four CI rows use". That is the shape `NFR-10` exists to prevent, arriving from inside.

**(b) Declare `>= 3.2` and pin `"~> 0.104"` anyway.** The gemspec would advertise a floor the bundle
cannot satisfy: `bundle install` on Ruby 3.2 fails with an unresolvable dependency, and it fails at
install time in a consumer's project rather than in CI. **Rejected**: a declared floor that produces a
resolution error is worse than an honest narrower one, and `gates:versions` would pass while the gem was
broken — a gate reporting green over a real defect.

**(c) Declare `required_ruby_version >= 3.3` for this gem alone.** **Taken.** Four supports:

1. **`NFR-2`'s separability makes a per-adapter floor a supported outcome rather than a fracture.** The
   requirement's entire point is that "a consumer composes only the units it uses". A consumer on 3.2
   composes `dexpace-core` + `dexpace-transport-net_http` + `dexpace-serde-json` and loses the reactor
   transport — which is precisely the trade the gem split exists to make available.
2. **`dexpace-core`'s floor does not move**, and neither does any other gem's. `SEAM-1`, `NFR-1` and the
   bundled-gem rule are all about core and are untouched. What narrows is one optional adapter.
3. **The repository floor of 3.2 is a `VERSIONS` convention enforced by a phase-0 gate, not a requirement
   ID.** No `NFR` fixes a Ruby version. So this is a **process deviation from phase 0's gate**, cheap to
   state and cheap to mechanise, and not a spec deviation at all.
4. **The alternative pins the port to a stack its upstream has abandoned.** `async` and `async-http`
   raised their floors on the same day (2026-03-08 for `async`), which is an ecosystem-wide move rather
   than one maintainer's whim.

**What has to change, named so it is not discovered at execution time.** Three edits, none of them 8c's to
make alone, all recorded as `OI-38`:

- **`VERSIONS` gains a per-gem floor key**, in the shape phase 0 already uses for the other rows —
  `ruby floor dexpace-transport-async_http   3.3` beside the global `ruby floor   3.2`.
- **`gates:versions` reads it**: a gemspec's `required_ruby_version` equals `>= ` plus its own per-gem
  floor if one exists, else the global one. That is a three-line change to a phase-0 gate and it is the
  only gate change phase 8 asks for.
- **The CI matrix's 3.2 row excludes this gem** from the tasks that actually install or load it —
  `test:gems` and `gates:clean_bundle` — and from nothing else. (Corrected 2026-09-12: this bullet also
  named `gates:gemspec_audit` and `gates:require_allowlist`, which only `Gem::Specification.load` a
  gemspec and read text under `lib/`; both pass on 3.2 with this gem present and neither needs a skip.)
  The root `Gemfile` must skip it too, since phase 0's glob adds every `gems/*` directory
  unconditionally and Bundler checks `required_ruby_version` for a path gem at install time — without
  that edit the 3.2 row fails for the **whole workspace**, not only for this gem. `ci_workflow_test.rb`
  — which "reads `rake gates:list` and fails if any listed gate appears in no job" — must not read the
  exclusion as a missing job: it is per-**gem**, not per-gate, and lives inside the Ruby-side tasks
  rather than in the workflow YAML, so `.github/workflows/ci.yml` is not edited at all.

**What 8c will *not* do**: silently pass `gates:versions` by leaving `>= 3.2` in place, or quietly drop
the 3.2 row from the whole matrix. The first is (b); the second changes the port's floor for every gem to
suit one adapter, which is a decision no sub-phase may take.

---

## `R16` — who writes the conformance harness, and what an asynchronous transport needs it to assume

**8c is the consumer.** The charter **assigns** §9.3's `TCPServer` fixture and `DEF-22`'s assertion
protocol to `8a`, and this document accepts that assignment without qualification: *8c writes neither, and
8c's plan has no task that writes either.* If the sub-phases run out of order and 8c lands first, 8c
writes them to the shape below and `8a` records that it consumed rather than wrote them — the charter's
own rule, stated from the other side so both designs say which side they are on.

**What 8c additionally supplies and `8a` cannot**: an **HTTP/2 driver**. `8a`'s `TCPServer` fixture speaks
HTTP/1.1 bytes; nothing in `dexpace-transport-net_http` can speak HTTP/2 at all. 8c contributes a second
fixture — an in-process `async-http` server over both plaintext prior-knowledge h2 and a self-signed TLS
endpoint (facts 2 and 3) — and runs the protocol-independent assertions against it. That fixture lives in
`dexpace-transport-async_http`'s own `test/support/`, **not** in `dexpace-conformance`, because
`dexpace-conformance` declares `dexpace-core` and nothing else and an HTTP/2 server needs `async-http`.

### What 8c needs the suite to assume — cited, not restated

**The suite contract is one list and `8a` owns it.** This section carried nine clauses of its own when
this document was written, beside five `8a`'s design carried; **merged on 2026-09-12 into one twelve-clause
list, dropping nothing 8c relies on.** It lives in
`docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md`, section
**`R16` — who writes the conformance harness → *The suite contract***, and this document cites it there
rather than carrying a second copy that can drift from it. `8a`'s plan Task 6 builds the three mechanisms
the merge added — `settle:`, `around:` and `wire:` on `TransportSuite.run` / `TransportCase` — which is
what makes "8c's transport passes the suite with no build-order dependency beyond `8a`'s gem exists" a
mechanical claim rather than an aspiration.

**Where the merge moved something, with the reason, so a reader of this document's earlier nine is not
left guessing:**

- **Clause 4's `base_url` positional is not in the merged list, deliberately.** This document asked for
  `->(base_url, **options) { adapter }`; `TransportCase#request` already builds every request against the
  live fixture's own port, and an adapter that routes by `Request#url` — which 8c's does — needs nothing
  else. A factory that also took a base URL would force every adapter to accept one. What 8c actually
  needed and got is the **factory** half: never a pre-built instance and never a constant.
- **Two of the nine were already implied by an `8a` assumption** and are stated in the merged list rather
  than added to it: the fixture's accept loop on its own thread (`8a`'s `WireServer` already runs one
  accept loop in a thread, and a `TCPServer#accept` on the fiber under test deadlocks a reactor), and the
  three-valued per-adapter result (`8a`'s five statuses — `:passed`, `:failed`, `:vacuous`, `:waived`,
  `:error` — already cover pass / vacuous-with-reason / waived-with-id).
- **Two clauses were added that neither document had.** A response body's `#content_length` is an
  `Integer` and is `-1` when unknown, never `nil` (`BODY-35`, `TRANSPORT-27`) — 8c maps its native `nil`
  at the boundary and the suite asks the SDK model, never the native object; and a **cancellation**
  surfaces from the send primitive as `Dexpace::CancelledError`, which on the async path means
  `Completer#request_cancel` and not `Completer#fail`, because only `#request_cancel` settles the
  `Settlement.cancellation` that `Future#cancelled?` reads as true.
- **One thing this document had wrong in the other direction.** It reported `TRANSPORT-27`'s
  invalid-`Content-Length` clause as "unreachable on **both** adapters" and proposed one waiver covering
  both drivers. That is right about `async-http` (fact 11: `Protocol::HTTP1::BadRequest` out of the read,
  no response object to downgrade) and **wrong about `Net::HTTP`**: `8a` measured its own adapter directly
  and found the head delivered in full under the block form, and implements the clause. **The waiver is
  8c's driver's alone**, and this document's *Deferrals*, `R14` report table and testing strategy are
  corrected to say so.

**8c-specific commentary the merged list does not carry**, because it is about this adapter rather than
about the suite:

- **8c supplies a second fixture `8a` cannot.** `8a`'s `TCPServer` fixture speaks HTTP/1.1 bytes and
  nothing in `dexpace-transport-net_http` can speak HTTP/2 at all. 8c contributes an in-process
  `async-http` server over both plaintext prior-knowledge h2 and a self-signed TLS endpoint (facts 2 and
  3) and runs the protocol-independent assertions against it through the merged clause 11's `wire:`
  factory. **It stays in `dexpace-transport-async_http`'s own `test/support/`**, never in
  `dexpace-conformance`, which declares `dexpace-core` and nothing else.
- **The header-name folding clause is an *intra*-adapter hazard here, not only a cross-adapter one.**
  The charter's fact 14 made it cross-adapter; this document's fact 2 measures HTTP/1.1 preserving
  `X-MiXeD-CaSe` and HTTP/2 lowercasing it, on the same adapter in the same run
  (`Protocol::HTTP::Headers#each` yields `key.to_s.downcase` on the h2 path, RFC 9113 §8.2.1). That is
  why the merged clause is written as "names are compared folded" rather than "the two adapters spell
  names differently".
- **The reactor wrapper is 8c's, not the suite's.** No `async`, `Async::Task` or `Protocol::HTTP` type
  may appear anywhere in `dexpace-conformance`'s `lib/` or `sig/` — that gem declares `dexpace-core` and
  nothing else, by design and not by accident (boundary 7) — so the `Sync { … }` that the merged clause 9
  permits lives in the **driver** 8c supplies, inside 8c's own gem.

---

## The dispatch path, in order

One method, `Dexpace::Transport::AsyncHTTP::Adapter#call(request, options, cancellation)`, returning a
`Dexpace::Async::Future`. Every step names the ID it discharges. **Nothing between step 1 and step 18 may
raise to the caller** except the five fatals of step 2 — that is `TRANSPORT-21`.

**1. Mint the pivot and return it.** `completer = Dexpace::Async::Completer.new` and the method's *last*
statement is `completer.future`; every step below happens inside a task or inside a `begin/rescue` that
routes to `completer.fail`. This is `TRANSPORT-21`, `ASYNC-2` and `PIPE-30`'s normalisation, and it is the
same shape phase 2 fixed: "the adapter's entry point returns the future before doing anything fallible".

**2. Post-close guard, and the fatal set.** If the adapter is closed, settle with `Dexpace::ClosedError`
— **through the future**, not by raising, because `SEAM-15`'s "a send after close raises" is about the
*sync* seam's exception and `TRANSPORT-21` governs this one (boundary 17; 8c's reading is recorded as a
row rather than a deviation because the two requirements are about different channels of the same
outcome). The only things permitted to propagate synchronously out of `#call` are `Async::Cancel`
(= `Async::Stop`), `NoMemoryError`, `SystemExit`, `SignalException` and `Interrupt`.

**3. Reactor check.** `Async::Task.current?` — if `nil`, settle with `Dexpace::SeamError` carrying the
message *"Dexpace::Transport::AsyncHTTP requires a running Async reactor; wrap the call in `Sync { }` or
`Async { }`"*, and return. Verified fact 9 is why: a full round trip outside a reactor raises
`RuntimeError: No async task available!` from deep inside `async`, which is neither a `Dexpace::` error
nor a useful message. **8c does not create a reactor**: doing so means either blocking the caller's thread
(`Sync`), which defeats the seam, or owning a background reactor thread, which is a thread pool by another
name — `8b`'s territory, a second `ASYNC-15` close contract, and a long-lived fiber whose `Fiber[]` is the
*constructor's* context rather than the caller's, which is `ASYNC-10`'s exact failure. Deviation `P8-39`;
the precedent is phase 5a's `Dexpace::Async.delay`, which "raises `Dexpace::SeamError` when
`Fiber.scheduler` is `nil`" (`P5-9`), differing only in the channel `TRANSPORT-21` fixes.

**4. Wire-boundary re-validation — `DEF-25`.** `Dexpace::HeaderSyntax` is re-run over **every** header name
(`HTTP-17`) and **every** outbound value (`HTTP-18`, `XCUT-18`) before anything is adapted. A violation
**raises**, and the raise is caught and routed to `completer.fail`. This is not belt-and-braces on the
HTTP/2 path: verified fact 4 shows `protocol-http2` transmitting `"a\r\nEvil: 1"` as a header value
verbatim, so on that path this step is the sole defence against header injection. Boundary 11 keeps it
disjoint from step 6: **re-validation raises; `TRANSPORT-12`'s drop is silent, and the two sets do not
overlap** — `HTTP-18` permits only HTAB plus 0x20–0x7E, which is strictly inside
`Protocol::HTTP1::VALID_FIELD_VALUE`'s `[^\0\r\n]+`, so no value ever reaches step 6.

**5. Framing-header drop — `TRANSPORT-11`.** **The drop set is a shared transport contract and is stated
once in the charter** — `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`, *Shared transport
contracts*, item 1 — because `8a`'s adapter drops **the same ten folded names** under its own constant
(`NFR-2` forbids either gem depending on the other, so the membership is what is shared, not the name) and
a conformance assertion reads the list on both. **`trailer` was missing from this table and is added,
2026-09-12**: neither adapter supports caller-supplied trailers, so a caller-set `Trailer` announces
fields that will never be sent, which is a false statement about a framing the transport chose. The set is
larger than the requirement's minimum on both adapters, and verified fact 5 is why the extension is
*more* load-bearing here — each entry is a smuggling vector rather than a tidiness issue, because
`async-http` **appends** a caller-set framing header where `Net::HTTP` recomputes it:

| Dropped | Why, measured |
|---|---|
| `host` | `write_request` writes `host: #{authority}` unconditionally; a caller-set one is **appended**, producing two `Host` headers (fact 5). |
| `content-length` | The body layer writes its own; a caller-set one is **appended**, producing CL.CL (fact 5). |
| `transfer-encoding` | Passed through beside a computed `content-length`, producing TE.CL (fact 5). |
| `connection`, `keep-alive`, `proxy-connection`, `upgrade`, `te` | RFC 9113 §8.2.2's connection-specific set. On HTTP/2 a caller-set `connection` made the peer kill the stream with `Protocol::HTTP2::StreamError` (fact 4); on HTTP/1.1 it is the framing layer's to decide. |
| `trailer` | Added 2026-09-12 to match `8a`'s set. This adapter accepts no caller-supplied trailers, so a caller-set `Trailer` announces fields that will never be sent. |
| `expect` | `100-continue` changes the write handshake under the body layer and is the transport's to negotiate. |

**`proxy-authorization` is in neither adapter's set**, per the same shared contract: `8a` configures no
proxy and holds no credential, so a caller-set value belongs to a proxying layer the SDK cannot see, and
`TRANSPORT-30`'s embedded MUST is about credentials *the SDK holds*.

Each drop is logged at `Severity::VERBOSE` through `Instrumentation.contain`, which is `TRANSPORT-11`'s
"SHOULD additionally log each drop at verbose" — **through the one event name and field pair the charter's
*Shared transport contracts* item 2 fixes**, `Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED =
"http.transport.header_dropped"` with `String` `"header"` and `"reason"` keys, so one assertion reads a
drop record from either adapter. The constant is one new frozen `String` in `dexpace-core`, added by
whichever sub-phase lands first and a no-op confirmation for the other. Matching is **case-insensitive on
the folded name** (`HTTP-13`, `downcase` with no arguments).

**6. Wire-grammar drop — `TRANSPORT-12`, `TRANSPORT-13`.** Every surviving name is tested against the RFC
7230 token grammar; a name that fails is **dropped, that header only**, and the drop is reported through
the `TRANSPORT-13` policy. The predicate is applied **on both protocols**, even though HTTP/2 would
transmit the name (fact 4) — deviation `P8-40`, argued below. It is applied **before dispatch**, not by
rescuing `Protocol::HTTP::RefusedError`, because verified fact 5 shows the exception arrives after the
request line and `host:` are already on the socket, making "the rest of the headers and the body MUST
still be dispatched" unreachable on that connection.

**7. Content-Type authority — `TRANSPORT-10`.** The caller's explicit `content-type` wins, matched
case-insensitively; a body-derived media type is emitted **only** when the caller set none. Unlike
`Net::HTTP`, `async-http` stamps no default (fact 5), so there is no library default to defeat — the whole
of `TRANSPORT-10` on this adapter is the adapter's own code, and the "(b) same body with no explicit
header → X on the wire" half is the one that needs a test.

**8. Body-less requests — `TRANSPORT-26`.** A body-less `POST`/`PUT`/`PATCH` dispatches with an empty body
and `Content-Length: 0` — which `async-http` already writes (fact 5) — and a body-forbidden method gets no
body attached. One measured wrinkle, recorded rather than fixed: **`async-http` writes
`content-length: 0` on a body-less GET too.** `TRANSPORT-26` does not forbid it, `HTTP-7` is about the
model rather than the wire, and suppressing it would mean reaching under the body layer. Documented in the
gem's README and named in the checklist row's clause.

**9. Endpoint construction.** `Dexpace::Request#url` is parsed with **`URI::RFC3986_PARSER` explicitly**
(§3.5, enforced by `Dexpace/NoUriDefaultParser`) and the resulting `URI` object is handed to
`Async::HTTP::Endpoint.new(uri, **options)`. **`Async::HTTP::Endpoint.parse` is never called**, because it
routes through `URI.parse` and therefore `URI::DEFAULT_PARSER`, which *is* what changed at exactly 3.4.0.
Verified fact 13 shows `Endpoint.new` accepts an RFC3986-parsed `URI::HTTP` and yields the right scheme,
authority and path.

**10. Client acquisition.** One `Async::HTTP::Client` per **origin** (scheme, host, port), memoised in a
`Hash` guarded by a `Thread::Mutex` held across the fetch-or-insert **and nothing else** —
`concurrency-and-async/c0fab747` and `/ee54cb68`. `Client.new` opens no socket (its pool's constructor
block runs on `acquire`), so the critical section contains no I/O and no suspension point, which is what
makes a non-reentrant, per-fiber-owned `Mutex` safe here. Construction arguments, every one a decision:

| Argument | Value | Why |
|---|---|---|
| `retries:` | **`0`** | `TRANSPORT-2`, `TRANSPORT-17`, `TRANSPORT-18`. The default is 3 (fact 13) and the SDK pipeline is the single retry authority (boundary 1). Asserted, not assumed. |
| `limit:` | from `Configuration`, default **`8` per origin** | The pool is **unbounded by default** (fact 9): eight concurrent calls opened seven connections. An SDK that hands a caller an unbounded file-descriptor budget has made a decision on the caller's behalf. The number is chosen, not derived — it is the shape §3.1 uses for `MAX_MATERIALIZED_BYTES`, and because the right value is deployment-specific it comes from phase 5a's layered chain as a named setting (`resource-management/d1f16cad`, `/2b9040ef`). |
| `protocol:` | the endpoint's own, or an explicit override | `Async::HTTP::Protocol::HTTPS` for `https://` (ALPN, h2 preferred), `HTTP1` for `http://` unless the caller asks for prior-knowledge h2. Fact 2: the plaintext client "Defaults to HTTP/1" and does **not** attempt h2c. |
| `ssl_context:` | always the adapter's own | See *TLS defaults* below. |
| middleware | **none** | `TRANSPORT-1`: `Async::HTTP::Middleware::LocationRedirector` exists and `Internet` does not install it (fact 13); 8c does not wrap, and the checklist row says "satisfied by not installing", which is an obligation rather than an absence. |

**11. The exchange task.** `Async::Task.current.async { … }` — a **child of the caller's task**, not
`Async { }`. Fact 10 measured the difference: `Async { }` inside a reactor produces a task whose `#parent`
is not the caller. The child relationship is what makes three things work at once: a caller's structured
cancellation reaches the exchange (`TRANSPORT-8`, fact 8), `Fiber[]` is inherited so diagnostic context
crosses for free (fact 10, and `SEAM-24`'s first sentence below), and the styleguide's own observation
applies — "`Async` structured tasks drain automatically when the outer `Async do` block exits, making that
cleanup free when using structured concurrency."

**12. The deadline.** One value — `RequestOptions#timeout`, or `Configuration`'s default — becomes
`task.with_timeout(seconds) { … }`. **The configured tier reads
`Dexpace::Configuration::Keys::REQUEST_TIMEOUT`, the same key `8a` declares**, through
`Dexpace.configuration.duration(…)`; 5a ships no `#float`, and `#duration`'s grammar treats a bare number
as **milliseconds** (`CFG-7`), which both adapters document at the adapter. That is the charter's *Shared
transport contracts* item 4, and it is why this document says "`8c` reads the same key rather than
declaring a second spelling" — one caller setting must govern both transports. `8c`'s
`Keys::TRANSPORT_CONNECTION_LIMIT` is genuinely `8c`-only: `Net::HTTP` is constructed per call and has no
pool to bound. It is an **explicit value propagated to the task's own timeout**, per
§8.3, and it interrupts only at a scheduler checkpoint. `Timeout.timeout`, `Thread#raise` and
`Thread#kill` appear nowhere. Verified fact 10: `with_timeout(0.2)` over a 2 s server aborted at 200 ms
with `Async::TimeoutError`, a `StandardError`, and ran the enclosing `ensure`. `TRANSPORT-5`'s per-call
scoping is structural — the timeout is on the per-call task, never on the shared client — and
`TRANSPORT-6`'s clamp is implemented anyway: `with_timeout` takes float seconds, so truncation to zero is
unreachable, and the clamp exists for adapters over coarser APIs (§3.2's own reasoning for `Net::HTTP`,
applied here for symmetry so the conformance assertion is not adapter-specific).

**13. The cancellation bridge — `ASYNC-6`, `TRANSPORT-7`.** Both directions, wired once:

- **Token → task.** `subscription = cancellation.on_cancel { |reason| task.cancel(cause: reason) }`, with
  `subscription.detach` in the `ensure` so a long-lived token does not retain a finished exchange (phase
  2's own leak argument for `Cancellation::Subscription`). `#cancel`, not the deprecated `#stop`
  (fact 10). Passing `cause:` is what carries `Dexpace::Cancellation#reason` into `Async::Cancel#cause`,
  measured in fact 8, and it is the out-of-band discriminator `XCUT-2` and `TRANSPORT-3` require.
- **Pivot → task.** `completer.on_cancel { |reason| task.cancel(cause: reason) }` — the same call, so
  cancelling the future reaches the in-flight exchange. Fact 8 measured the effect: a task cancelled while
  blocked in `body.read` or in the pool's `acquire` aborts and runs its `ensure`.
- **Task → pivot.** The exchange task ending in `Async::Cancel` settles the pivot **cancelled** with
  `Dexpace::CancelledError` — terminal, non-retryable (`TRANSPORT-3`, `TRANSPORT-8`), never the retryable
  transport failure.

`ASYNC-6`'s conformance clause is "per adapter, cancel via the native primitive and assert the future
observes cancellation; cancel the future and assert the native primitive terminates" — two tests, both
listed below, and 8c is the only MVP gem that can pass the second in the interrupting sense.

**14. Check-after-resume.** After the exchange returns and **before** acting on the response,
`cancellation.check!`. This is `concurrency-and-async/611b9392`, quoted in full above, and it is what makes
`SEAM-30`/`ASYNC-5` hold on a host with no external pre-emption.

**15. Response adaptation, and the `ensure`.** `TRANSPORT-24`'s total status mapping (facts: 520 and 499
both surface faithfully with readable bodies), `TRANSPORT-14`'s lenient inbound header copy, and
`TRANSPORT-27`'s media-type downgrade. If adaptation raises with the socket live, `TRANSPORT-22` requires
the native response closed before propagating — which is the `ensure` of `R13`'s sketch, on both the
success and the failure path, through `Dexpace.close_quietly` (§3.7 names this call site explicitly).

Inbound header handling, from fact 11:

| Inbound | Action | ID |
|---|---|---|
| obs-text / non-ASCII in a **value** | **preserved**, BINARY | `TRANSPORT-14`'s SHOULD, satisfied by the library |
| control byte in a **value** | **dropped, that header only**, logged verbose | `TRANSPORT-14`, and required because `XCUT-18` makes `Dexpace::Headers::Builder` reject it — a header that reached the builder would fail the whole response |
| control / non-ASCII in a **name** | **unreachable**: `protocol-http1` raises `BadHeader` out of the read and the response never materialises | `TRANSPORT-14` waived here; `OI-39`, `P8-38` |

**16. The response body — `TRANSPORT-25`, `SEAM-11`, `IO-40`, `SSE-39`.** `ResponseBody` is a
`Dexpace::Body` whose `#each` calls the native `Protocol::HTTP::Body::Readable#read` **once per yield**
and stops at `nil`, and whose `#close` closes the native body and returns the connection to the pool.
Four properties, each measured:

- **Lazy.** The response object arrives at 1 ms and the second chunk at 401 ms (fact 6). `SEAM-11`'s "MUST
  NOT pre-buffer the body" and `TRANSPORT-25`'s lazily-read stream are satisfied **natively** — no pump,
  no fiber, no thread, and none of the `R1` problem `8a` has to solve.
- **BINARY.** Chunks are `ASCII-8BIT` and unfrozen, so `io-and-byte-streams/a44b4de6`'s `String#b` retag
  is a no-op — routed through the same helper anyway, so the property is asserted.
- **One read per unit of demand.** That is `SSE-39`'s backpressure mechanism surviving the transport, and
  it is why 7b's `Dexpace::SSE::Stream.open(response)` needs nothing of 8c beyond `Response#body`
  answering `#source`.
- **Close does not drain and does not block.** A 4 MiB unread body closed in 6 ms (fact 6), so
  `TRANSPORT-16`'s "no unbounded await" holds at the response level as well as the adapter level.

The `Dexpace::IO::BufferedSource` is built with **`.over(body)`**, which takes no ownership, and never
with `.wrapping(io)` — which is what keeps `OI-9`'s one-byte-per-read defect out of this adapter. §7.1's
rule is honoured by construction: the resource lives on the object with `#close`, never inside an
`Enumerator` block.

**17. Error wrapping.** Everything reaching `completer.fail` is a `Dexpace::` error. `P6-4`'s obligation is
"wrap, and default to retryable":

| Native | Wrapped as | ID |
|---|---|---|
| `Async::TimeoutError` | `Dexpace::TransportError`, **retryable**, cancellation flag **clear** | `TRANSPORT-4`, `TRANSPORT-8`'s second clause |
| `Errno::*` (`SystemCallError`) | `Dexpace::TransportError`, retryable | `TRANSPORT-20` |
| `SocketError`, `Socket::ResolutionError` | idem | `TRANSPORT-20` |
| `OpenSSL::SSL::SSLError` | idem | `TRANSPORT-20` |
| `EOFError` | idem — already an `::IOError`, wrapped anyway so `#retryable?` answers | `TRANSPORT-20`, `XCUT-4` |
| `Protocol::HTTP::Error` and everything under it — `RefusedError`, `RemoteError`, `Protocol::HTTP1::*`, `Protocol::HTTP2::*` | idem | `TRANSPORT-20` |
| `Dexpace::` errors already (`HeaderSyntax`'s, `StreamError`) | **passed through unwrapped** | `P3-3`: `StreamError` is a sibling of `TransportError`, never a subclass |
| **`Async::Cancel` (= `Async::Stop`)** | **not rescued, not wrapped** — propagates; the `ensure` closes and the pivot settles cancelled with `Dexpace::CancelledError` | `TRANSPORT-3`, `TRANSPORT-8`, `R13` |

Every wrap carries the original as `#cause`, and every `Completer#fail` of an error the adapter is
*carrying* rather than one it just rescued uses `raise error, cause: nil` (`pipeline/f02559b9`), so a
caller's in-flight exception is never silently adopted as a cause.

**18. Settle.** `completer.fulfil(response)`. `TRANSPORT-23` and `SEAM-16`'s "MUST NOT complete
successfully with a null/absent value" are satisfied by `Dexpace::Async::Settlement`'s own cross-field
rule — exactly one of `response`/`error` — so there is no settled-with-nothing state to reach and 8c
writes no guard for it.

### TLS defaults

**8c always supplies its own `OpenSSL::SSL::SSLContext`**, and never lets `async-http` build one. Two
measured reasons (fact 3):

1. **`Async::HTTP::Endpoint#ssl_verify_mode` returns `VERIFY_NONE` for any hostname matching
   `/^(.*?\.)?localhost\.?$/`.** That is a defensible convenience in a web framework and a silent TLS
   downgrade in an SDK. 8c sets `verify_mode: OpenSSL::SSL::VERIFY_PEER` and the default certificate
   store, unconditionally, for every host.
2. **A caller-supplied context is used verbatim and never has `alpn_protocols` set on it**, so HTTP/2 over
   TLS is unreachable unless the adapter sets ALPN itself. 8c sets `alpn_protocols = ["h2", "http/1.1"]`,
   which is what produced `response.version == "HTTP/2"` in fact 3.

Both are overridable through `Configuration` for the caller who genuinely needs a private CA or a pinned
cipher list, and the override is a whole `SSLContext` rather than a per-knob keyword, so the SDK never
becomes a partial re-export of OpenSSL's configuration surface. `require "openssl"` is permitted here:
`openssl` is a default gem with no `Gem::BUNDLED_GEMS::SINCE` entry (fact 12), which is the same rule core
lives by — the 4.0.6 re-check is owed by the plan.

### `SEAM-24`'s first sentence, and what stays deferred

`SEAM-24` (SHOULD): "Async-runtime adapter modules that hand work to another thread SHOULD propagate the
ambient logging/diagnostic context … across the thread handoff."

**8c satisfies the first sentence by construction and needs no code.** The adapter hands work to no
*thread*: it creates a child `Async::Task`, which is a fiber of the caller's own thread, and **`Fiber[]` is
inherited by a child task with copy-on-write** (fact 10) — the child read the parent's `trace_id`, and a
child writing its own left the parent's slot unchanged. So the diagnostic context crosses 8c's boundary
for free, and none of `ASYNC-9`'s save/install/restore machinery has an antecedent here: there is no
reused or pooled carrier whose prior context could be clobbered. **8c calls neither `Diagnostics.with` nor
`Fiber#storage=`**, which means `OI-13`'s warned setter — the hazard that dominates `8b`'s `R8` — does not
reach this gem at all. The checklist states this as a property the suite asserts (a `Fiber[]` slot set
before `#call` is visible to a log emitted inside the exchange), not as an absence.

**What stays deferred is `SEAM-24`'s second sentence**, and it is narrower than it looks: "**Each
adapter's cancellation bridge** SHOULD map cancellation in both directions per that ecosystem's idiom
(e.g. cancelling a downstream subscription/future cancels the pivot future, and vice versa)." That is a
**caller-facing** bridge over the host's own primitive — a caller who already holds an `Async::Task` and
wants cancelling *it* to cancel the pivot. Design §3.3 `:252-254` assigns it to `dexpace-async-async`
(`concurrency-and-async/f75816b6`), which is `DEF-11`, post-v1. **8c satisfies `ASYNC-6` for the
`Async::Task` it creates itself and bridges no caller-held task**, so it does not meet the second
sentence. The charter already proposes the `DEF-1` amendment that says this; 8c confirms it from the
adapter's side and adds nothing.

### The sync half of `TRANSPORT-12`, and why 8c ships no second transport

`TRANSPORT-12` says "on both sync and async paths". 8c ships **one** implementation and reaches the sync
path through **phase 2's `Dexpace::AsyncTransport.sync_over(async_transport)`**, which wraps an async
transport as a blocking one. One code path, two paths satisfied, and no possibility of the two drifting —
which is §11.12's own resolution ("each through a single shared implementation so the paths cannot drift
again") applied here. The one caveat, stated because it is measurable: **`sync_over` on this adapter still
requires a reactor**, because the exchange it awaits cannot run without one; a caller with no reactor gets
the step-3 `Dexpace::SeamError` through the bridge. The README says so beside the `ASYNC-7` section.

---

## Module layout

```
gems/dexpace-transport-async_http/
  dexpace-transport-async_http.gemspec
  lib/dexpace/transport/async_http.rb                    Dexpace::Transport::AsyncHTTP — explicit requires,
                                                         VERSION, the registration call, the skew assertion
  lib/dexpace/transport/async_http/version.rb            ::VERSION
  lib/dexpace/transport/async_http/adapter.rb            ::Adapter — the #call seam, steps 1-3 and 11-18
  lib/dexpace/transport/async_http/request_mapper.rb     ::RequestMapper — steps 4-9 (DEF-25, TRANSPORT-10/11/12/26)
  lib/dexpace/transport/async_http/request_body.rb       ::RequestBody — Protocol::HTTP::Body::Readable over a Dexpace::Body
  lib/dexpace/transport/async_http/response_mapper.rb    ::ResponseMapper — step 15 (TRANSPORT-14/24/27)
  lib/dexpace/transport/async_http/response_body.rb      ::ResponseBody — Dexpace::Body over the native body (step 16)
  lib/dexpace/transport/async_http/clients.rb            ::Clients — the per-origin map, @owned, #close (step 10)
  lib/dexpace/transport/async_http/endpoints.rb          ::Endpoints — URI::RFC3986_PARSER -> Async::HTTP::Endpoint, TLS
  lib/dexpace/transport/async_http/errors.rb             ::Errors.wrap — step 17's table
  lib/dexpace/transport/async_http/drop_policy.rb        ::DropPolicy — TRANSPORT-13's three modes, DEF-41
  sig/dexpace/transport/async_http.rbs                   one .rbs per .rb, shipped inside the gem
  sig/dexpace/transport/async_http/*.rbs
  test/test_helper.rb
  test/support/http2_server.rb                           the in-process h2 fixture (plaintext + TLS), R16
  test/support/recording_body.rb                         the close-counting double, R13
  test/dexpace/transport/async_http/*_test.rb            one per lib file
  test/dexpace/transport/async_http/conformance_test.rb  the dexpace-conformance driver, R16
```

**Explicit `require`s, no autoloader** (§2.3, `module-organization/2a4cc61d`'s resolved conflict). The
entry file requires `dexpace`, then `async/http`, then its own tree in dependency order, then registers.
That also makes `gates:require_allowlist` a text scan for this gem as it is for core.

**The require set, stated exactly**, because the audit reads it: `dexpace`, `async/http`, and — only
where a file needs them before anything else has loaded them — `uri` and `openssl`, which are default
gems with no bundled-since entry (fact 12). **Nothing else.** In particular there is **no
`require "protocol/http/body/readable"`, no `require "protocol/http/request"`, no `require "async"` on
its own, no `require "console"` and no `require "protocol/http1"`** — every one of those belongs to a
transitive gem the gemspec does not declare, and phase 0's `RequireAllowlist.third_party_for` permits an
adapter exactly the dependency names its own gemspec declares (`["async-http", "async/http"]` here), so a
bare `require "protocol/http/..."` fails `gates:require_allowlist` outright. Where 8c needs a class from a
transitive gem it reaches it through `async-http`'s own surface, which is the gem it declared: measured on
2026-09-12, `require "async/http"` alone already defines `Protocol::HTTP::Body::Readable` and
`Protocol::HTTP::Request` (`defined?` reports `"constant"` for both), so no second `require` is needed for
either. (Corrected 2026-09-12; the earlier list named the two `protocol/http/...` files, contradicting this
paragraph's own next sentence and the gate.)

**The registration call and the skew assertion** (§2.4, boundary 8):

```ruby
Dexpace::AsyncTransport.register(
  :async_http,
  ->(**options) { Dexpace::Transport::AsyncHTTP::Adapter.new(**options) },
  core: "~> #{Dexpace::Transport::AsyncHTTP::CORE_REQUIREMENT}"   # required keyword; raises Dexpace::SeamError on skew
)
```

`DEF-30`'s restriction is honoured and named: presence-gated auto-activation is "for **instrumentation
only** … No transport or codec adapter may ever use it." 8c registers **explicitly**, at `require` time,
and never because `Async::HTTP` happens to be defined.

---

## The object model 8c ships

### `Dexpace::Transport::AsyncHTTP::Adapter`

The seam implementation. **Two entry points, the ownership distinction made at construction**
(`cross-cutting-invariants/093b7681`, `XCUT-22`, `SEAM-14`, `TRANSPORT-15`):

```
.new(configuration: nil, ssl_context: nil, connection_limit: nil, drop_policy: nil) -> Adapter   # builds and owns its clients
.over(client)                                                                       -> Adapter   # borrows a caller-supplied native client
#call(request, options, cancellation)                                               -> Dexpace::Async::Future
#close                                                                              -> nil
#closed?                                                                            -> bool
```

`@owned` is a frozen boolean set at construction and never re-decided. `.new` builds a `Clients` map and
closes it; `.over(client)` wraps a single caller-supplied client and **never** closes it, so "the caller
may keep using it after the transport is closed" (`TRANSPORT-15`) holds by construction. The adapter is
otherwise **effectively immutable after construction** (`TRANSPORT-29`, `ASYNC-22`): the only mutable
state is the `Clients` map's `Hash` and the close latch, both under their own mutex, and every per-call
value lives on the exchange task and its `Completer`.

`#close` is `Dexpace::Closeable`'s latch — a `@closed` boolean flipped under a `Thread::Mutex` **held only
across the flip** — and its `#release` closes the `Clients` map if `@owned`. It is idempotent
(`TRANSPORT-16`, `XCUT-13`) and it does not block.

### `Dexpace::Transport::AsyncHTTP::Clients`

The per-origin client map, and the object deviation `P8-37` lives on.

```
#fetch(origin)  -> an object responding to #call(protocol_request) and #close
#close          -> nil
```

`#fetch` is memoise-or-create under one `Thread::Mutex` whose critical section is **the `Hash` read and
the `Hash` insert and nothing else**: the client is built *outside* the lock and inserted under it, so a
lost race discards an unused client (`Client.new` opens no socket — fact 9's pool inspection — so a
discarded one costs nothing). Building outside the lock is not belt-and-braces: the endpoint's
`OpenSSL::SSL::SSLContext#set_params` touches the default certificate store, which is filesystem I/O and
therefore a scheduler suspension point under a fiber scheduler, and `concurrency-and-async/ee54cb68` with
`/f261a143` forbid holding a lock across I/O. (Corrected 2026-09-12; the earlier sentence claimed the
critical section contained no I/O while building the client inside it.) **`#close` calls
`client.pool.close`, not `client.close`**, and that is `P8-37`: verified fact 9 measured
`Async::HTTP::Client#close` blocking 253 ms on `@pool.wait_until_free` with one request in flight, which
is the **unbounded await** `XCUT-13` and `TRANSPORT-16` forbid in as many words, *and* emitting a JSON
`Console.warn` line to the host's **stderr**, which nothing in this SDK may do. `Async::Pool::Controller#close`
is `drain` — retire every resource — then clear and stop the gardener, with no wait, and `Client` exposes
`attr :pool`, so the conforming route is public API. §3.7's rule for the sibling gem is the same sentence:
"close signals its queue and returns, it does not join workers under a `Kernel#sleep` or an unbounded
`Thread#join`."

A connection still in flight when `#close` runs is retired rather than waited on; the exchange holding it
sees its socket close and surfaces a wrapped, retryable `Dexpace::TransportError` — which is what a caller
who closed a transport mid-flight asked for, and is `ASYNC-16`'s graceful-shutdown SHOULD declined
deliberately at the *transport* level (it binds an adapter that owns an **executor**; this one owns a
connection pool, and `TRANSPORT-16`'s MUST is the governing clause).

### `Dexpace::Transport::AsyncHTTP::ResponseBody`

A `Dexpace::Body` over `Protocol::HTTP::Body::Readable`.

```
#each { |chunk| … }   # one native #read per yield; BINARY; stops at nil
#source               -> Dexpace::IO::BufferedSource          (built with .over, never .wrapping — OI-9)
#content_length       -> Integer                              (native #length, with nil mapped to -1 —
                                                               TRANSPORT-27's and BODY-35's sentinel, never nil)
#close                -> nil                                  (idempotent; closes the native body, releases the connection)
```

It is **not** an `Enumerator` and it never acquires a resource inside a block (§7.1): the native body is
held on the object, and `#close` is the release. An abandoned `#each` leaks nothing that `#close` cannot
reclaim, and `Dexpace::Response#close` forwards to it (`HTTP-43`).

### `Dexpace::Transport::AsyncHTTP::RequestBody`

A `Protocol::HTTP::Body::Readable` subclass over a `Dexpace::Body`, so an outbound body is **never
materialised** (fact 7 measured exactly one `#read` per chunk plus one for end-of-stream, and chunked
framing on the wire). `#length` reports the body's own when it has one and `nil` otherwise;
`#rewindable?` is `false` for a single-use body, which is the second of `TRANSPORT-17`'s two independent
guarantees. `Protocol::HTTP::Body::Buffered.wrap` is **not** used for this: it materialises an
`#each`-yielding object (fact 7), which would violate `SEAM-11`'s streaming intent on the write side.

### `Dexpace::Transport::AsyncHTTP::DropPolicy` — `TRANSPORT-13`, `OBS-19`, `DEF-41`

A frozen `Data` over phase 5b's two ingredients, which is exactly what `DEF-41`'s row predicts ("Phase 8
writes a small `Data` over both").

```
DropPolicy::EVERY        # every drop at Severity::WARNING
DropPolicy::ONCE_PER_NAME  # the default: first per folded name at WARNING, the rest at VERBOSE
DropPolicy::QUIET        # all at Severity::VERBOSE
#report(logger, name, reason) -> nil
```

- **Case-insensitive**, keyed on the folded name (`downcase` with no arguments — `HTTP-13`, and the lint
  rule that forbids a locale symbol).
- **Bounded at 64 distinct names per adapter instance**, after which the policy degrades to `QUIET` rather
  than growing — the requirement's "MUST be bounded so an attacker synthesising unbounded distinct names
  cannot grow it without limit", with a number, because "bounded" without one is not testable. **The
  policy and its bound are `8c`-only, and that is the correct asymmetry** (the charter's *Shared transport
  contracts*, item 3): `TRANSPORT-13`'s antecedent is a native wire grammar stricter than the SDK model's,
  `Net::HTTP` has none — it writes `Bad name: v` to the wire rather than rejecting it — so the ID is
  vacuous on `8a` and `8a` ships no policy object. A `TRANSPORT-11` **framing** drop never goes through
  the policy on either adapter and is always verbose: three modes over a set the caller controls would let
  an attacker suppress a `WARNING` by exhausting the per-name bound.
- Every emission goes through `Instrumentation.contain(logger, event: …)`, because `OBS-20`'s "every
  log-emission site" is not scoped to phase 5's sites.
- The conformance clause it must pass, verbatim from §17.3: "under once-per-header assert the same name
  warns once then goes quiet, a different name warns once."

### `Dexpace::Transport::AsyncHTTP::Errors`

`Errors.wrap(error) -> Dexpace::TransportError` — step 17's table as data, not a `case` chain, so the
mapping is inspectable and testable as a table. It never sees `Async::Cancel`, by construction.

---

## The `sig/` shape

`sig/` mirrors `lib/` one file per file and **ships inside the gem**, so a consumer's `steep check` sees
it (`NFR-3`). `rbs validate` and `steep check` gate it; the gem gets its own **named Steep target**
(phase 0 created it), strict on the public surface and lenient on internals, never a blanket ignore.

**`NFR-11` is the constraint that shapes every signature here, and it is mechanised.** `gates:rbs_surface`
asserts that no constant outside `Dexpace::` and a fixed stdlib allowlist appears in any public signature
under `sig/`. The charter says it "binds `8c` hardest: `Protocol::HTTP::Response` and `Async::Task` are the
two constants most likely to leak into an RBS file by convenience." Three concrete consequences:

1. **`Adapter#call` returns `Dexpace::Async::Future`** and takes `Dexpace::Request`,
   `Dexpace::RequestOptions?` and `Dexpace::Cancellation`. No foreign constant appears, because none
   crosses the seam.
2. **`.over(client)` declares its argument as a gem-local interface, not as `Async::HTTP::Client`.** The
   adapter's own `sig/` declares
   `interface _Client; def call: (untyped) -> untyped; def close: () -> void; def pool: () -> untyped; end`
   under `Dexpace::Transport::AsyncHTTP`, and `.over` takes a `_Client`. That mentions no foreign constant,
   passes the scan, and is honest: the seam this gem borrows across really is a duck type. The YARD block
   names `Async::HTTP::Client` in prose, which is where the reader needs it and which the scan does not
   read.
3. **`ResponseBody`'s native handle is `untyped` in the signature and named in YARD.** Same reason. It is
   private state and never appears in a public return type.

**The runtime surface snapshot is regenerated with the RBS**, because they see different things: `Data`'s
generated readers, `define_method` and the require-time `register` call are invisible to RBS
(`gates:surface_snapshot`). Changing 8c's exports means regenerating both, and the plan's last task does.

**`gates:sig_diff`** has nothing to diff for this gem — there is no previous release tag — and phase 0
already handles the no-tag case. It becomes live the moment phase 8 performs the workspace's first
release.

**Open, and named as a plan question:** whether `gem_rbs_collection` carries signatures for `async-http`
or any of its closure. If it does, `rbs_collection.yaml` gains a normal `- name: async-http` row. If it
does not, the row is an explicit no-signatures entry and every foreign constant is `untyped` inside the
gem's own Steep target — which costs 8c nothing, because clauses 1–3 above mean no foreign constant
appears in a *public* signature either way.

---

## Spec-forced boundaries, honoured

The charter fixes twenty (`:532-629`). Fourteen reach 8c; here is where each is met, and none is
re-decided.

| # | Boundary | Where 8c meets it |
|---|---|---|
| 1 | The pipeline is the single redirect and retry authority | `retries: 0` and no `LocationRedirector`, both asserted (step 10, fact 13). **Not vacuous on this adapter** — the defaults are 3 and opt-in-but-absent respectively. |
| 2 | The streaming contracts impose no timeout; the transport owns every deadline | `IO-40`. The deadline is `task.with_timeout` (step 12); `ResponseBody` and `BufferedSource` carry none. |
| 3 | Deadlines are explicit values, never ambient interrupts | Step 12. No `Timeout.timeout`, no `Thread#raise`, no `Thread#kill` — and `Fiber#kill` is not used either, because 8c has no abandoned-fiber problem (`R1` is `8a`'s). |
| 4 | §10.5's three MUSTs are settled and split exactly that way | 8c re-opens none. `ASYNC-3`'s antecedent is a blocking task on a worker thread; 8c has no worker thread, so the gap does not widen here — and 8c does **not** claim to close it, because the ID is `8b`'s row. |
| 5 | The pivot is core-owned; adapters bridge and never replace | `Dexpace::Async::Completer`/`Future` are settled, never subclassed, never replaced. No `Async::Task` in any public signature. |
| 6 | `NFR-11` is an RBS scan over `sig/` | The `sig/` section above, three clauses. |
| 7 | `NFR-2` is core plus at most one third-party library | `R15`. Two declared dependencies, one third-party. |
| 8 | Every adapter's registration asserts `Dexpace::VERSION` | The registration call above; `core:` is a required keyword and 8c does not pass it optionally. |
| 9 | Ownership is a construction-time fact | `.new` versus `.over`, frozen `@owned`. |
| 10 | Idempotent close is a latch under a mutex held only across the flip | `Dexpace::Closeable`; `#release` runs outside the lock. |
| 11 | Wire-boundary re-validation **raises**; `TRANSPORT-12`'s drop is a different rule over a **disjoint** set | Steps 4 and 6, and the disjointness is proved rather than asserted: `HTTP-18` permits HTAB plus 0x20–0x7E, strictly inside `VALID_FIELD_VALUE`'s `[^\0\r\n]+`, so no value survives step 4 to reach step 6 (fact 5). |
| 12 | A pipeline is a transport and closing it is a no-op on the transport | 8c assumes nothing about its caller and never closes one. |
| 16 | The seams are phase 2's and phase 8 registers into them | 8c adds no seam, no second registry and no competing root. |
| 18 | Bytes on the wire are BINARY in both directions | Facts 2 and 6; `RequestBody` yields BINARY, `ResponseBody` retags through `String#b`. |
| 19 | `URI::RFC3986_PARSER` is pinned for every parse and resolution | Step 9; `Endpoint.parse` is never called (fact 13). |
| 20 | `OBS-19` rides on `TRANSPORT-13` | `DropPolicy`; `DEF-41` picked up here. |

Boundaries 13, 14, 15 and 17 are `8a`'s and the phase's; 8c consumes them. Boundary 17's open half —
"whether a transport that only *borrows* a caller-supplied client also raises" — is `8a`'s to decide, and
8c states its own answer for its own gem in step 2 (it raises through the future either way, because
`@owned` governs what `#close` *releases*, not what `#call` *refuses*) and will follow `8a` if `8a`
decides otherwise.

---

## Cross-cutting constraints that bite 8c specifically

- **The forbidden three.** `Timeout.timeout`, `Thread#raise`, `Thread#kill`. 8c is the one gem in the
  repository where the sanctioned alternative is *better* than the forbidden mechanism rather than merely
  acceptable: `Async::Task#cancel` runs `ensure` blocks at a scheduler checkpoint (fact 8), which is the
  precise property §8.3 says `Thread#raise` lacks. 8c's `ASYNC-7` README section says so.
- **`Thread::Mutex` is per-fiber and non-reentrant.** It binds exactly two objects here: the close latch
  (held across the flag flip only) and the `Clients` map (held across a `Hash` fetch-or-insert containing
  no suspension point). A mutex held across `client.call` would deadlock two fibers of one thread, and
  8c holds none.
- **An abandoned `Enumerator` never runs its `ensure`.** `ResponseBody` is not an `Enumerator` and
  acquires nothing inside a block; the native body lives on the object and `#close` releases it (§7.1).
- **`Fiber[:key]`, never `Thread.current[:key]`.** Fact 10: a child `Async::Task` inherits `Fiber[]` with
  copy-on-write. This is the whole of `SEAM-24`'s first sentence for this gem, and 8c writes no context
  code.
- **Bytes on the wire are BINARY.** Facts 2 and 6 measured `ASCII-8BIT`, unfrozen, on both protocols.
- **`URI::RFC3986_PARSER` pinned.** Fact 13, step 9. This is the constraint most likely to be violated by
  convenience, because `Async::HTTP::Endpoint.parse` is the documented entry point and it is wrong here.
- **The bundled-gem rule does not bind an adapter — but the require set still matters.** 8c declares
  `async-http`, requires `async/http` and two `protocol/http` files reachable through it, and requires
  `uri` and `openssl`, both default gems with no bundled-since entry (fact 12). It requires **no**
  transitive gem by name.
- **Regexp timeouts are per-pattern.** 8c writes one regexp over attacker-influenced bytes — the RFC 7230
  token predicate in step 6 — and constructs it with `Regexp.new(source, timeout:)`, never
  `Regexp.timeout`. (The pattern is a simple character class with no backtracking, so the timeout is
  belt-and-braces; the rule is repository-wide and 8c does not carve an exception.)
- **`Ractor` is never load-bearing**, and is not reachable here at all: a reactor is thread-bound.
- **SPDX header and `# frozen_string_literal: true` on every file** (`NFR-13`), checked by a custom cop.
- **`ruby -w` with warnings fatal.** Fact 12: `require "async/http"` under `-w` with
  `RUBYOPT=-W:deprecated` is silent, so the dependency does not fail the gate on load. The plan re-checks
  on 3.3 and 4.0.
- **`Console` writes JSON to stderr at `warn` by default.** 8c must never let a library warning reach the
  host's stderr on the SDK's behalf: that is what `P8-37` avoids for the one call site that does it, and
  the plan's suite asserts a clean stderr across a full adapter lifecycle. 8c does **not** set
  `Console.logger.level` — mutating a process-global logger is the same class of imposition the port
  refuses for `Regexp.timeout`.

---

## Testing strategy

**Minitest, `ruby -w`, SimpleCov's 80% floor, and the whole suite well under 30 seconds**
(`testing`'s own bound). No test sleeps longer than 400 ms and there are four that long.

### The fixtures

1. **`8a`'s `TCPServer` wire fixture**, consumed for every protocol-independent §17 assertion. 8c writes
   it only if it lands first (`R16`).
2. **A raw `TCPServer` inside this gem**, for the three things a conformance fixture should not encode:
   the exact outbound bytes (fact 5's capture), a mid-body peer reset, and a dribbling body with a
   measurable inter-chunk gap.
3. **`test/support/http2_server.rb`** — an in-process `async-http` server, in two configurations:
   plaintext with `protocol: Async::HTTP::Protocol::HTTP2` (prior knowledge), and TLS with a
   self-signed certificate generated per run and real ALPN. Facts 2 and 3 are its proof of concept.
   **It stays in this gem** and never in `dexpace-conformance`, which declares `dexpace-core` and nothing
   else.
4. **A recording double over `Protocol::HTTP::Body::Readable`**, counting `#close`, for `R13`'s three
   tests. Counting the close beats watching the socket, because "the connection looked released" is not
   an assertion.

**No stubbing library anywhere** (§9.3): the requirements are about socket-level behaviour a stub cannot
express, and a per-client shim would make the same assertions unrunnable against a second adapter.

### Deterministic cancellation without sleeps

Three techniques, so no cancellation test races:

1. **The server holds the response.** A fixture endpoint that accepts, sends headers, then blocks on a
   `Thread::Queue` the test controls. The test cancels while the exchange is provably blocked, then
   releases the queue. No sleep is needed to "get into" the blocking state, because the *server* decides
   when the client leaves it.
2. **A `Dexpace::Cancellation::Source` the test owns.** `source.cancel(reason)` at the exact point, and
   `Future#wait(cancellation:)` to observe the settlement. Never `Thread#raise`, which the cop forbids.
3. **Ordering assertions, not timing assertions.** The `R13` tests assert `close_count == 1` and the
   event *sequence*, not elapsed milliseconds. The one place a duration is asserted is `with_timeout`'s,
   and it is asserted as "less than the server's 2 s hold", a two-order-of-magnitude margin.

`Async::Task#status` (`:cancelled` / `:completed`) is the third observation channel and is what makes a
cancellation test assert the *native* side of `ASYNC-6`, not only the pivot's.

### The tests each own ID needs, named

| ID | Test |
|---|---|
| `TRANSPORT-7` | Cancel the pivot mid-body; assert the native exchange aborted (`task.status == :cancelled`), the `ensure` ran, and the connection was released. Fact 8 is the pilot. |
| `TRANSPORT-8` | Cancel the **parent** task while the pivot is live; assert the pivot settles with a terminal, non-retryable `Dexpace::CancelledError`. Paired with: a `with_timeout` expiry on the same path settles with a **retryable** `Dexpace::TransportError`. Two assertions, one file, because the pair is the requirement. |
| `TRANSPORT-9` | Settle the future (cancel it) in the window after the native response exists and before delivery; assert the native body's `#close` ran **exactly once**. Driven through `Completer#fulfil`'s own lost-race close plus the `ensure`. |
| `TRANSPORT-12` | Send `["Bad Name", "v"]` plus `["x-normal", "n"]`; assert the future completes normally, the bad header is absent from the wire, the normal header present, and the body dispatched — **over HTTP/1.1 and over HTTP/2**, because only the pair proves `P8-40`. |
| `TRANSPORT-13` | Under `ONCE_PER_NAME`, drop `X-Bad Name` twice and `Y-Bad Name` once; assert WARNING, VERBOSE, WARNING. Plus: 65 distinct bad names, assert the latch stopped growing and degraded to quiet. Plus: `x-bad name` and `X-Bad Name` share one latch entry (case-insensitivity). |
| `TRANSPORT-21` | Three pre-dispatch failures — a header `HeaderSyntax` rejects, a URL the endpoint cannot build, and no reactor — each asserted to come back as an **already-failed future**, never a synchronous raise. |
| `TRANSPORT-23` | Across success and failure, assert `Settlement` never carries a nil response on the success branch. Structural, and asserted anyway. |
| `ASYNC-6` | Direction one: `source.cancel(reason)` on the token; assert the task terminated and `Async::Cancel#cause` is the reason. Direction two: `future.cancel(reason)`; assert the same. The conformance clause names both. |
| `ASYNC-21` | No test — N/A. The **property** is tested as `SSE-39`'s: instrument `ResponseBody`'s native handle and assert **one** `#read` per `#each` yield, with nothing read ahead. |
| `ASYNC-22` | Sixteen concurrent `#call`s through one adapter against a fixture that echoes a per-request nonce; assert every future resolved to *its own* response with no cross-talk. Fact 9 ran eight; the suite runs sixteen because the requirement's word is "many". |

### The second-driver conformance run

8c adds itself as a driver of every assertable §17 row `8a` writes, through `R16`'s `settle` primitive and
a `Sync { }` wrapper. Two **named waivers** (§9.3's mechanism, listing the requirement ID so the gap stays
visible):

- **`TRANSPORT-14`** — the malformed-inbound-**name** clause, unreachable (fact 11, `P8-38`, `OI-39`).
  The obs-text and control-byte-in-a-value halves pass normally.
- **`TRANSPORT-27`** — the invalid-`Content-Length` clause, unreachable **on this adapter only**
  (`Protocol::HTTP1::BadRequest` out of the read, fact 11). **Corrected 2026-09-12**: this bullet said it
  was "unreachable on `8a`'s adapter too" and proposed "one waiver covering both drivers". `8a` measured
  `Net::HTTP` directly under the block form it uses and found the head delivered in full, and implements
  the clause (`8a`'s `R4`, resolved as satisfied whole). **The waiver names this driver and not `8a`'s.**

### The three zero-dependency checks, from this gem's side

- **`gates:gemspec_audit`** — `runtime_dependencies` is exactly `["dexpace-core", "async-http"]`.
- **`gates:require_allowlist`** — the require set above, scanned as text.
- **`gates:clean_bundle`** — a scratch `Gemfile` holding only
  `gem "dexpace-transport-async_http", path: …`, then `bundle exec ruby -e` requiring the gem and driving
  one exchange against an in-process fixture, **on 3.3, 3.4 and 4.0 and not on 3.2** (`R15`). The gems it
  may activate are `dexpace-core`, `async-http` and `async-http`'s own closure — and **nothing else**; an
  activation of `concurrent-ruby`, `logger` or a second HTTP library is the failure the run exists to
  catch.

### CI matrix

`3.3`, `3.4` and `4.0` for this gem; **`3.2` excluded**, per `R15` and `P8-36`. The exclusion is per-gem,
not per-gate: the 3.2 row still runs `dexpace-core`, `dexpace-transport-net_http`, `dexpace-serde-json`,
`dexpace-async-thread` and `dexpace-conformance` with every gate. `ci_workflow_test.rb` — which "reads
`rake gates:list` and fails if any listed gate appears in no job" — must see every gate in some job, which
it does.

---

## The interface surface later phases may cite

Phase 9 (conformance and cross-cutting audit) and phase 10 (the ledger audit) may cite these and nothing
else from this gem. Everything not listed is internal, whatever its Ruby visibility.

| Constant | Role |
|---|---|
| `Dexpace::Transport::AsyncHTTP` | The gem's namespace, `VERSION`, and the require-time registration |
| `Dexpace::Transport::AsyncHTTP::Adapter` | The `SEAM-16` implementation: `.new`, `.over`, `#call`, `#close`, `#closed?` |
| `Dexpace::Transport::AsyncHTTP::DropPolicy` | `TRANSPORT-13`'s three modes and `#report`; the object `DEF-41` closes on |
| `Dexpace::Transport::AsyncHTTP::_Client` | The RBS interface `.over` borrows across, declared so no foreign constant enters a public signature |

**Not public, and named so nobody cites them:** `Clients`, `Endpoints`, `Errors`, `RequestMapper`,
`RequestBody`, `ResponseMapper`, `ResponseBody`. They have no YARD block and no entry in the surface
manifest, which is this repository's definition of internal.

**What phase 9 will want and should take from here:** the two named waivers, the `TRANSPORT-8` inversion
(`OI-41`), and the HTTP/2 fixture, which is the only thing in the MVP that can drive an `XCUT` audit over
a second protocol.

---

## Deviation Ledger

Each row is consolidated into design §10 and audited by `docs/deviations.md`.

**Numbering starts at `P8-36`, and the gap is deliberate.** The three sub-phases of phase 8 were designed
**concurrently**, so a shared "next free number" would have had two documents taking the same one, and a
ledger id is cited from source comments and tests and can never be renumbered. **`P8-1`–`P8-19` are
reserved for `8a` and `P8-20`–`P8-35` for `8b` — corrected in place 2026-09-12, with the correction
stated.** This sentence read "`P8-1`–`P8-20` … `P8-21`–`P8-35`", which is one of three mutually
inconsistent band statements the three concurrent designs each wrote; the charter now fixes the
allocation once, under its own *Deviation Ledger*, and this document cites it rather than restating a
fourth version. **`P8-36`–`P8-50` for `8c` is unchanged**, of which `P8-36`–`P8-40` are used and
`P8-41`–`P8-50` stay unallocated (`P8-41` was proposed by this document's plan and retired unfiled on
2026-09-12; nothing cites it and no id is reused). Nothing was renumbered in any sub-phase. This is
phase 5's recorded arrangement applied to a three-way concurrent split.

### `P8-36` — `dexpace-transport-async_http` declares `required_ruby_version >= 3.3`, narrower than the repository floor of 3.2

*Touches* `NFR-2`, `NFR-10`, and phase 0's `gates:versions` (a process gate, not a requirement ID).
*Judged.* `async-http 0.95.0` and `async 2.38.0` raised their floors to `>= 3.3` and the installed 0.104.0
carries it (verified fact 1); the highest 3.2-compatible pair is `async-http 0.94.2` with `async 2.37.0`,
eleven and eight minor releases behind, and not installed here. A floor a gem declares must be a floor it
is tested on, and the alternative readings either advertise an unresolvable bundle or claim support for a
stack none of this document's thirteen verified facts covers. `NFR-2`'s own separability is what makes the
narrowing supported rather than a fracture: a consumer on 3.2 composes core plus
`dexpace-transport-net_http` and loses only the reactor transport. *Consequence:* `VERSIONS` gains a
per-gem floor key, `gates:versions` reads it, and the 3.2 CI row excludes this gem. *Not* a change to
`dexpace-core`'s floor or to any other gem's. `R15`, `OI-38`.

### `P8-37` — the adapter's `#close` releases the connection pool directly rather than calling `Async::HTTP::Client#close`

*Touches* `TRANSPORT-16`, `XCUT-13`, `SEAM-14`, `OBS-20`. *Judged, and the requirement compels it.*
Verified fact 9: `Async::HTTP::Client#close` is `@pool.wait_until_free { Console.warn … }` then
`@pool.close`, and `wait_until_free` is `@condition.wait(@mutex) while busy?` — measured blocking for
253 ms with one request in flight. `XCUT-13` requires close to use "non-blocking shutdown semantics (no
unbounded await)" and `TRANSPORT-16` restates it; the library's own close cannot satisfy either. It also
writes a JSON `warn` line to the host's **stderr** through `Console`'s default output, which no part of
this SDK may do. `Async::Pool::Controller#close` is `drain` then clear with no wait, and `Client` exposes
`attr :pool`, so the conforming route is public API rather than a `send`. *Residual:* a connection in
flight at close is retired rather than waited for, and its exchange surfaces a wrapped retryable failure —
which is what closing a transport mid-flight means. §3.7 states the same rule for `dexpace-async-thread`.

### `P8-38` — `TRANSPORT-14`'s malformed-inbound-**name** clause is not satisfiable on this adapter

*Touches* `TRANSPORT-14`. *Admitted rather than argued away* (P8). The requirement: "a control byte in a
value, **or a control/non-ASCII byte in a name**, MUST drop only that header (logged at verbose) while the
body and remaining headers are still delivered." Verified fact 11: a response header
`X-B\xE9d: v` makes `protocol-http1` raise `Protocol::HTTP1::BadHeader: Could not parse header` out of the
**read**, so the response never materialises and the adapter has nothing to drop from. The other two
clauses — obs-text in a value preserved, control byte in a value dropped — are satisfied. *Why not fixed:*
the only route is to parse the response head off the socket before `protocol-http1` does, which means
reimplementing the HTTP/1.1 response parser inside the adapter, and `NFR-2`'s whole point is that the
adapter is thin over one library. *Mitigation:* none available; the gap is a **single malformed inbound
header name fails the whole response**, which is bounded (the response, not the connection, and not other
requests) and is reported by the conformance suite as a **named waiver listing `TRANSPORT-14`**, so it
stays visible. `OI-39`.

### `P8-39` — the async transport is usable only from inside a reactor, and says so through a failed future

*Touches* `SEAM-16`, `TRANSPORT-21`, `ASYNC-2`. *Judged.* Verified fact 9: a full round trip outside
`Async`/`Sync` raises `RuntimeError: No async task available!` from inside `async`. 8c does not create a
reactor — `Sync { }` would block the caller's thread and defeat the seam; an owned reactor thread is a
thread pool by another name (`8b`'s gem, a second `ASYNC-15` contract, and a long-lived fiber carrying the
*constructor's* `Fiber[]`, which is `ASYNC-10`'s exact failure). Instead `#call` with no
`Async::Task.current?` returns an **already-failed** future carrying `Dexpace::SeamError` with a message
naming the fix, which is what `TRANSPORT-21` asks for in as many words ("MUST be delivered through the
returned future … NOT thrown synchronously"). The precedent is phase 5a's `Dexpace::Async.delay`, which
raises `Dexpace::SeamError` with no `Fiber.scheduler` (`P5-9`); the channel differs because the
requirement differs. *Documented* in the gem's README beside the `ASYNC-7` section, and in the
`sync_over` caveat.

### `P8-40` — a header the HTTP/1.1 wire grammar rejects is dropped on **both** protocols

*Touches* `TRANSPORT-12`. *Judged.* Verified facts 4 and 5: `protocol-http1` refuses `"Bad Name"` and
`protocol-http2` transmits it (lowercased, unvalidated). A drop predicate scoped to the negotiated
protocol would make one `Dexpace::Request` produce two different observable header sets depending on an
ALPN result the caller never saw — and `TRANSPORT-12`'s own phrasing, "on both sync and async paths", is
about *one* rule holding across a path split, which is the same concern one protocol version further
down. So 8c applies the RFC 7230 token predicate before dispatch, unconditionally. *Cost:* a caller who
wants a non-token header name delivered over HTTP/2 — which RFC 9113 §8.2.1 forbids anyway — cannot.
*Benefit:* one request, one header set, and a conformance assertion that does not have to know which
protocol won.

### Corrections made to this document on 2026-09-12, none of them a deviation

The plan's verification pass found five sentences in this document that measure differently, and each is
corrected in place above with its reason rather than carried as a ledger row — the same line this
document's own next paragraph draws. **`P8-36`–`P8-40` remain the whole of 8c's ledger.**

1. **`TRANSPORT-27`'s unknown-length sentinel is `-1`, not `nil`** (appendix C's own text; `BODY-35`).
   The object-model block and verified fact 6 both said `nil`; the adapter maps the native `nil` to `-1`
   and exposes `#content_length`, the name every other `Dexpace::Body` uses.
2. **The require set may not name `protocol/http/body/readable` or `protocol/http/request`.** Phase 0's
   require-allowlist gate scans **every** gem's `lib/`, not only core's, and permits an adapter only the
   dependency names its own gemspec declares; both constants arrive with `require "async/http"` anyway.
3. **`ASYNC-6`'s inward direction is `Completer#request_cancel`, not `Completer#fail`** — only the former
   settles the outcome `Future#cancelled?` reads as true.
4. **`Clients#fetch` builds its client outside the mutex.** The endpoint's SSL context load is filesystem
   I/O, which a lock may not be held across.
5. **`R15`'s exclusion list was two tasks too long, and one task short.** Only `test:gems` and
   `gates:clean_bundle` install or load this gem on the 3.2 row; the root `Gemfile` — which `R15` did not
   name — is the one that breaks the whole workspace if it is missed.

**The plan's proposed `P8-41` is retired rather than filed.** It would have recorded correction 2 as a
deviation; a ledger row is a deliberate difference from the **reference contract**, and declining to write
two `require` lines a phase-0 gate rejects is neither a difference from the contract nor deliberate — it is
this document being wrong about its own gate, now fixed above. No `docs/deviations.md` row was ever
written for `P8-41`, so no id is reused; `P8-41`–`P8-50` stay unallocated inside 8c's band.

**What 8c found that is not a deviation, and is filed as such.** Verified facts 1, 4, 9 and 11 each change
what this sub-phase must *do* and none changes what the port *claims*. `retries: 0` is `TRANSPORT-2`
satisfied, not deviated from; the HTTP/2 validation gap is a library fact that makes `DEF-25` load-bearing
rather than a decision about a requirement; the unbounded pool default is a knob the adapter sets. Only
`P8-38` narrows a MUST, and it narrows it by an amount the requirement's own per-transport scoping
anticipates.

---

## Deferrals and the register sweep

**8c files no new deferral.** The register's `next id` is `DEF-43` and 8c does not take it: every
postponement 8c would want is already carried by a row.

The roadmap's execution step 1 requires a phase to disposition the whole register, and the **charter did
that for phase 8** (`:1273-1412`, all forty-two rows). 8c does not repeat it; it states only where its own
work changes a disposition the charter recorded, which is four rows.

- **`DEF-25` — picked up, 8c's half.** The condition names "each adapter's dispatch path"; step 4 is that
  call site. 8c's checklist carries its own row and the `Status` moves at the phase-level PR once both
  adapters' call sites exist. **What 8c adds to the charter's account**: on the HTTP/2 path this is not a
  mitigation for a forged model, it is the **only** validation between the model and the wire (fact 4),
  which strengthens the row rather than changing its disposition.
- **`DEF-41` — picked up and closed by 8c.** The condition — "phase 8, at the first adapter that drops a
  caller-set header rather than raising on it" — is met (fact 5), and `DropPolicy` is the object. The
  charter's proposed amendment stands in full and 8c confirms both halves of it from the adapter's side:
  the requirement the row should name is **`TRANSPORT-12`** with **`TRANSPORT-13`** the logging twin, not
  `TRANSPORT-8`; and phase 5b's forward table (`…phase5b…-design.md:2110`) repeats the same wrong ID and
  is corrected in the same change. 8c adds one fact the amendment should carry: **the antecedent is live
  on the HTTP/1.1 path and absent on the HTTP/2 path of this same adapter**, and 8c drops on both anyway
  (`P8-40`), so the row's "the first adapter that drops" is true of the gem and not of every exchange it
  performs.
- **`DEF-42` — not picked up by 8c, and the reason is `OI-36`.** The charter makes 8c's emitter call sites
  conditional on `R6` ("once `R6` settles the route"), and `R6` is `8a`'s. `OI-36` records that **no route
  exists** by which an adapter in another gem reaches a per-operation `HTTPTracer` through an
  `NFR-4`-locked three-argument seam. 8c does not invent one: a constructor keyword gives one tracer per
  adapter lifetime, which is not what `OBS-29`'s 1:1 clause describes, and widening `RequestOptions` is a
  phase-1 core surface and a real `NFR-4` widening. **8c wires no emitter and says so**, which is the
  answer the charter says it expects and the same answer `OI-32` already records for the
  operation-lifecycle triple. If `8a` settles `R6` the other way, 8c's plan gains one task and this
  paragraph is what it amends.
- **`DEF-1` — untouched; the charter's amendment stands and 8c confirms the adapter half.** 8c satisfies
  `SEAM-24`'s **first** sentence by construction (`Fiber[]` inheritance across a child task, fact 10) and
  `ASYNC-6` for the `Async::Task` it creates itself. It bridges no caller-held task, so it does **not**
  meet the second sentence, which design §3.3 `:252-254` assigns to `dexpace-async-async` (`DEF-11`,
  post-v1). The row stays **deferred** and is not UNSCHEDULED.

**Four more rows 8c checked and left alone**, stated because a reader will ask:

- **`DEF-10`** — `TRANSPORT-28`/`TRANSPORT-30` are `8a`'s ⏳ rows and its condition ("a transport adapter
  beyond the two MVP transports") is not met. 8c reports that `Protocol::HTTP::Body::File` makes
  `TRANSPORT-28`'s reachable half *more* reachable here (charter fact 15) — a report to `8a`'s `R5`, not a
  row and not a pick-up.
- **`DEF-11`** — `dexpace-async-async`. 8c is the gem most likely to be mistaken for it and is not it:
  `dexpace-transport-async_http` **implements** the SPI over a reactor; `dexpace-async-async` would
  **bridge** a caller's own `Async::Task` to the pivot. The charter says the same thing from the
  segmentation side; 8c says it here so the register row is not read as met.
- **`DEF-18`** — `ASYNC-3` and `PIPE-33`'s interrupt clause. 8c adds no unsatisfied MUST and re-opens
  nothing; both rows are `8b`'s. Worth one sentence because it is counter-intuitive: 8c is the one adapter
  in the MVP that *can* abort an in-flight blocking operation (fact 8), and that does **not** close
  `ASYNC-3`, whose antecedent is "a blocking task on a worker thread" and whose row belongs to the gem
  that has one.
- **`DEF-30`** — presence-gated auto-activation is instrumentation-only and "no transport or codec adapter
  may ever use it". 8c registers explicitly at require time and never because `Async::HTTP` is defined.
  Named because "activate because `async-http` happens to be loaded" is exactly the convenience a reader
  of this gem would reach for.

---

## The findings proposed for the registers

**Four, described here for a human to file. None is acted on by this document, and no register file is
edited by it.** The register's `next id` is `OI-34`; **the charter already proposes `OI-34` through
`OI-37` and has not been filed**, so 8c's numbers run from **`OI-38`** and the two documents' proposals
are contiguous rather than colliding. If the charter's four are filed with different numbers, these four
shift with them and the shift is mechanical.

**Target register: `docs/open-items.md`. Proposed id `OI-38`.**

> ### OI-38 — `dexpace-transport-async_http` cannot declare the repository-wide Ruby 3.2 floor, and a phase-0 gate asserts that it must
>
> - **Opened:** 2026-09-11, phase 8c design
> - **Status:** open
> - **Cites:** NFR-2, NFR-10, NFR-14, DEF-11, P0-9, P8-36
>
> Phase 0 fixed `VERSIONS` with a single `ruby floor` line of `3.2` and a `ruby matrix` of
> `3.2 3.3 3.4 4.0`, and `rake gates:versions` asserts "that every gemspec's `required_ruby_version` equals
> `>= ` plus the `ruby floor` line"
> (`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md:291-303`). Verified on
> 2026-09-11 against the installed stack: **`async-http` 0.104.0 declares `required_ruby_version >= 3.3`**,
> and so do `async` 2.45.1, `async-pool` 0.12.0, `console` 1.37.0, `io-endpoint` 0.18.0, `io-event` 1.22.0,
> `io-stream` 0.14.0, `protocol-http` 0.71.0, `protocol-http1` 0.41.0, `protocol-http2` 0.28.0 and
> `protocol-url` 0.19.0. From rubygems.org's version index: `async-http 0.94.2` is the last release
> allowing `>= 3.2` and `0.95.0` raised it; for `async` the boundary is `2.37.0` / `2.38.0`, both released
> 2026-03-08. So the two mechanised constraints contradict each other: the gate requires `>= 3.2` and the
> only dependency that satisfies `>= 3.2` is eleven minor releases behind the one the phase-8c design
> verified every one of its facts against. Phase 8c takes the narrowing as deviation `P8-36` and
> `dexpace-core`'s floor does not move. What this row records is the **machinery that has to change and
> that no sub-phase owns**: (a) `VERSIONS` gains a per-gem floor key
> (`ruby floor dexpace-transport-async_http  3.3`) beside the global one; (b) `gates:versions` reads a
> per-gem floor when one exists and the global floor otherwise — a change to a phase-0 gate; (c) the root
> `Gemfile`'s `gems/*` glob skips a gem this interpreter's version cannot satisfy, without which
> `bundle install` on the 3.2 row fails for the whole workspace; (d) the 3.2 row excludes this one gem
> from `test:gems` and `gates:clean_bundle` — the two tasks that install or load it; `gates:gemspec_audit`
> and `gates:require_allowlist` only read text and need no exclusion. The exclusion is per-gem and not
> per-gate, and it lives in the Ruby-side tasks rather than in the workflow YAML, so
> `ci_workflow_test.rb`'s "every listed gate appears in some job" still holds and `ci.yml` is unedited. It also earns a line in
> `docs/first-release.md`: the gem a consumer on Ruby 3.2 cannot install, and the composition that still
> works for them. Nothing is broken today because nothing is implemented.
>
> **Resolution:** *(open)*

**Target register: `docs/open-items.md`. Proposed id `OI-39`.**

> ### OI-39 — `TRANSPORT-14`'s malformed-inbound-header-**name** clause is unreachable on `dexpace-transport-async_http`, and §12 records `TRANSPORT-14` as satisfied without qualification
>
> - **Opened:** 2026-09-11, phase 8c design
> - **Status:** open
> - **Cites:** TRANSPORT-14, XCUT-18, HTTP-17, NFR-8, P8-38
>
> `TRANSPORT-14` (MUST): "Inbound response headers MUST be copied leniently enough that a single malformed
> header does not fail the whole response: a control byte in a value, **or a control/non-ASCII byte in a
> name**, MUST drop only that header (logged at verbose) while the body and remaining headers are still
> delivered." Verified on 2026-09-11 against `protocol-http1` 0.41.0 under Ruby 3.4.10, driving a raw
> `TCPServer` that emits `X-B\xE9d: v`: the client raises
> `Protocol::HTTP1::BadHeader: Could not parse header: "X-B\xE9d: v"` out of the **read**, so no response
> object exists and the adapter has nothing to drop from. The other two clauses hold: an obs-text byte in a
> value came back as `["X-Obs", "caf\xE9"]` (both `ASCII-8BIT`) and a control byte in a value came back
> intact for the adapter to drop. The charter's fact 6 measured `Net::HTTP` doing the opposite — it
> *preserves* a non-ASCII name as a key — so the requirement is satisfiable on one MVP adapter and not on
> the other, which is the per-transport scoping §17's own preamble anticipates and which neither §12 nor
> §9.3 records for this ID (§9.3 scopes only `TRANSPORT-8` and `TRANSPORT-18` that way). Phase 8c records
> it as deviation `P8-38` and the conformance run carries a **named waiver listing `TRANSPORT-14`**, per
> §9.3's mechanism, so the gap is reported rather than restated. The only route to satisfying it would be
> to parse the response head off the socket before `protocol-http1` does, i.e. to reimplement the HTTP/1.1
> response parser inside an adapter whose whole design is to be thin over one library. What would resolve
> it: §12's `TRANSPORT` row gains `TRANSPORT-14` to its adapter-scoped list the next time §12 is
> deliberately amended by a human, and `docs/deviations.md` carries the interim note. Nothing is broken
> today because nothing is implemented.
>
> **Resolution:** *(open)*

**Target register: `docs/open-items.md`. Proposed id `OI-40`.**

> ### OI-40 — design §3.3 and the corpus name `Async::Task#stop`, which `async` 2.45.1 deprecates in favour of `#cancel`
>
> - **Opened:** 2026-09-11, phase 8c design
> - **Status:** open
> - **Cites:** ASYNC-6, SEAM-24, DEF-1, DEF-11, TRANSPORT-7
>
> `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:252-254` reads: "`dexpace-async-async` maps
> `Async::Task#stop`/`#with_timeout` onto the pivot's cancellation in both directions for callers whose own
> code is already reactor-based (**ASYNC-6**)", and the corpus carries it verbatim as
> `concurrency-and-async/f75816b6`. The phase-8 segmentation design cites `Async::Task#stop` as "the
> primitive" in its fact 8 and in `R13`. Verified on `async` 2.45.1 under Ruby 3.4.10:
> `lib/async/node.rb` carries `# Backward compatibility alias for {#cancel}. # @deprecated Use {#cancel}
> instead.` immediately above `def stop(...) = cancel(...)`, and `Async::Task.instance_method(:stop).owner`
> is `Async::Node`. The current primitive is **`Async::Task#cancel(later = false, cause: $!)`**, and its
> `cause:` keyword is materially better for this port than `#stop` was: a `Dexpace::Cancellation#reason`
> passed as `cause:` is readable back off the raised `Async::Cancel` as `#cause`, which is the out-of-band
> discrimination `XCUT-2` and `TRANSPORT-3` require and which `#stop` gives no channel for. This is the
> same species as the charter's `OI-34` and `OI-35` — a frozen design chapter that is wrong about a
> library — and it is smaller than either: the *mapping* §3.3 describes is right, only the method name has
> moved. Phase 8c calls `#cancel` everywhere. What would resolve it: `dexpace-async-async` (`DEF-11`,
> post-v1) is written against `#cancel`; §3.3's sentence is corrected the next time §3 is deliberately
> amended by a human; the corpus entry re-keys on the next harvest, at which point any note citing
> `concurrency-and-async/f75816b6` needs revisiting. Nothing is broken today because nothing is
> implemented.
>
> **Resolution:** *(open)*

**Target register: `docs/open-items.md`. Proposed id `OI-41`.**

> ### OI-41 — `TRANSPORT-8` is satisfiable on `dexpace-transport-async_http`, and §12 counts it among the eight MUSTs that hold vacuously
>
> - **Opened:** 2026-09-11, phase 8c design
> - **Status:** open
> - **Cites:** TRANSPORT-8, TRANSPORT-3, TRANSPORT-4, XCUT-2, ASYNC-6, NFR-8
>
> `docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md:41` lists "TRANSPORT-1, TRANSPORT-2,
> TRANSPORT-8 and TRANSPORT-18 … adapter-scoped and vacuous for `Net::HTTP`", and the MUST-level summary
> at `:49-55` counts `TRANSPORT-8` among "eight [that] hold vacuously". §9.3 is more careful —
> "**TRANSPORT-8** and **TRANSPORT-18** vacuous for `Net::HTTP` and **mandatory for any adapter whose
> client has those paths**" — and the corpus carries that as `testing/9a56af9d`. Verified on 2026-09-11
> against `async` 2.45.1 and `async-http` 0.104.0 under Ruby 3.4.10: cancelling a **parent** `Async::Task`
> delivers `Async::Cancel` into an in-flight child exchange while the SDK future is still live — measured
> event sequence `["outer-saw:Async::Cancel", "inner:Async::Cancel", "inner-ensure"]` — which is exactly
> `TRANSPORT-8`'s antecedent, "a cancellation that originates inside it (e.g. an internal cancel-all)". It
> is not a contrived case: it is the ordinary shape of a consumer whose supervisor cancels its children on
> shutdown. The requirement's second clause is free here, because `async` puts the two exceptions in
> different halves of the tree: `Async::Cancel < Exception` and `Async::TimeoutError < StandardError`, so
> the terminal-versus-retryable discrimination is by class and never by message (`XCUT-2`). Two candidates
> were tested and **rejected** as the antecedent: a graceful HTTP/2 GOAWAY mid-stream did not abort the
> open stream (the client read it to completion), and `Protocol::HTTP::RefusedError` is a retryable
> transport failure rather than a cancellation. So the port gains a **satisfied** MUST where §12 records a
> vacuous one — the inverse direction from `OI-34`, and equally a defect in a frozen chapter. What would
> resolve it: phase 8c implements and asserts the discrimination and its checklist row states it;
> §12's `TRANSPORT` row and the MUST-level count are corrected the next time §12 is deliberately amended
> by a human, and `docs/deviations.md` carries the interim note. Nothing is broken today because nothing is
> implemented.
>
> **Resolution:** *(open)*

**Target register: `docs/deferred-items.md`, as an addition to the charter's proposed `DEF-41`
amendment.** The charter already proposes correcting the row's requirement ID from `TRANSPORT-8` to
`TRANSPORT-12`/`TRANSPORT-13` and correcting the same wrong ID in phase 5b's forward table
(`docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md:2110`). 8c confirms the
correction from the adapter's side and asks for **one sentence more** in the same edit: *the condition is
met by `dexpace-transport-async_http`'s **HTTP/1.1** path specifically — `protocol-http1` rejects a header
name `HTTP-17` accepts while `protocol-http2` transmits it unvalidated — and the adapter drops on both
protocols anyway, so "the first adapter that drops" is true of the gem rather than of every exchange it
performs.* Without that sentence a reader of the closed row will conclude that any `async-http`-based
adapter must drop, which is true, and that the wire forces it, which is only half true.

**Target register: `docs/first-release.md`.** Two lines, both owed by the phase-level PR rather than by
this sub-phase:

- **A supported-Ruby line.** `dexpace-transport-async_http` requires Ruby **>= 3.3**, narrower than every
  other gem in the workspace (`P8-36`, `OI-38`). A consumer on Ruby 3.2 composes `dexpace-core`,
  `dexpace-transport-net_http`, `dexpace-serde-json`, `dexpace-async-thread` and `dexpace-conformance`, and
  loses only the reactor transport — which is `NFR-2`'s separability paying for itself and should be
  stated as such rather than discovered at `bundle install`.
- **A native-extension line.** The gem's transitive closure contains `io-event`, which compiles C
  (`ext/extconf.rb`). A platform with no toolchain and no precompiled `io-event` cannot install this gem.
  The same sentence covers it.

**What `ruby .claude/skills/housekeeping/probe.rb` reports until these are filed, so the next runner does
not read it as drift.** Re-run on 2026-09-12 with all seven phase-8 documents in place, the probe reports
**18 findings across two checks**, every one of them a consequence of those documents existing and none
fixable from inside this one. (**Corrected in place**: this paragraph said "ten findings", counting only
the charter's four ids and this document's four, before `8a` and `8b` numbered seven more.)

- **`claims` (1)** — `CLAUDE.md:381`: states "eight phase directories" but the repository has 9. That is
  the **charter's** to clear, not 8c's; the charter writes the three `CLAUDE.md` edits out verbatim.
- **`citations` (17)** — **fifteen `OI-<n>` numbers cited across phase 8 with no row in
  `docs/open-items.md`**, two of them (`OI-38` and `OI-41`) cited twice, which is where 15 becomes 17
  lines: `OI-34`–`OI-37` by the charter, `OI-38`–`OI-41` here, `OI-42`–`OI-45` by `8a` and
  `OI-46`–`OI-48` by `8b`, in sub-phase order. The register's `next id` is `OI-34`, so the fifteen run
  contiguously from it, and every document writes its own rows out in the register's own format for
  pasting. Phase 7's findings deliberately carried no numbers and produced no such finding; phase 8 files
  numbered rows so the follow-through is a paste rather than a re-derivation, which is the trade the
  charter states and 8c follows for consistency rather than re-deciding.

`links`, `inbox`, `root`, `readmes`, `registers` and `guard` are clean. **Once the fifteen rows are
pasted and `CLAUDE.md`'s numeral is corrected, the probe is clean.**


**Two rows explicitly do not close.** `OI-9`'s one-byte-per-read defect in `BufferedSource.wrapping` is
phase 3a's code to fix; 8c avoids it by using `.over` and says so rather than closing it. `OI-18`'s
`Transport.async_over` accepting an async transport silently is phase 2's or a phase-8 amendment's; 8c is
the first object that can be fed to it by mistake and does not fix it — the repair is in `dexpace-core`
and belongs with `OI-18`'s owner.

---

## The knowledge note 8c files

One note, written by the plan's final task, under `docs/knowledge/notes/transport-adapter.md`, section
`## Reference`, naming the harvested rule it annotates rather than supersedes.

Its subject is verified fact 4. `transport-adapter/cb7901ef` is `TRANSPORT-12`'s harvested text — "A
header valid at the SDK model layer but rejected by the native client's stricter wire grammar must be
dropped for that header only … on both sync and async paths" — and the rule is **correct and silent about
the case that bites**: it presumes the native client *has* a stricter grammar. On `async-http` one
protocol does and the other does not, and the one that does not transmits a CRLF-bearing header value
verbatim. The note is `## Reference` rather than `## Superseded` because nothing in the harvested rule is
false; what it adds is the observation that a *protocol* boundary inside one adapter is a second axis the
rule does not name, and that `DEF-25`'s re-validation changes role across it — from the
correctness-of-shape mitigation design §10.10 describes to the sole request-splitting defence.

Draft, in the shape the skill fixes. **The fenced block below is the note file's own content, heading
included**; its `## Reference` is a heading of `docs/knowledge/notes/transport-adapter.md`, not a second
Reference section of this document. The `knowledge-lookup` skill fixes that section name, so the line is
copied verbatim and never renamed; this document's own section was renamed instead (below), so the two no
longer read as a duplicated heading.

```markdown
## Reference
- **`TRANSPORT-12`'s "stricter wire grammar" is per-protocol, not per-adapter, and on the looser protocol
  `DEF-25` is the only defence.** Annotates `transport-adapter/cb7901ef`. Verified 2026-09-11 on
  `protocol-http1` 0.41.0 and `protocol-http2` 0.28.0 under Ruby 3.4.10, against an in-process
  `async-http` server driven over both protocols. On HTTP/1.1, `Protocol::HTTP1::Connection#write_headers`
  checks `VALID_FIELD_NAME` (the RFC 7230 token set) and `VALID_FIELD_VALUE` (`[^\0\r\n]+`) and raises
  `Protocol::HTTP1::BadHeader`, rewrapped as `Protocol::HTTP::RefusedError` with the original as `#cause`
  — but only **after** the request line and `host:` are already on the socket, so
  `TRANSPORT-12`'s "the rest of the headers and the body MUST still be dispatched" is unreachable by
  rescuing and the drop must be a pre-dispatch predicate. On HTTP/2 the client validates **nothing**: a
  name `"Bad Name"` was transmitted (lowercased to `"bad name"`) and a value `"a\r\nEvil: 1"` was
  transmitted **verbatim**, both reaching the peer. So one adapter has `TRANSPORT-12`'s antecedent on one
  protocol and no validation at all on the other, and `DEF-25`'s wire-boundary re-validation is, on the
  HTTP/2 path, the only thing between a forged `Dexpace::Request` and an injected header — a stronger
  statement than design §10.10's "a correctness-of-shape gap, not a request-splitting gap". The port's
  answer is to apply the RFC 7230 token predicate before dispatch on **both** protocols, so one request
  produces one observable header set (`P8-40`).
  <sub>review · `docs/work/mvp/phase8/phase8c/2026-09-11-phase8c-asynchronous-transport-design.md` · high · sha:manual-phase8c-http2-no-validation</sub>
```

`ruby scripts/verify_knowledge_structure.rb` must pass after it lands, and `harvested/` is not edited.

---

## Reference — versions, library sources and probe scripts

Facts and citations a plan or a later reader will want without re-deriving them. **This is this document's
only `## Reference`-shaped section**; the one above it is inside a fenced block and belongs to the
knowledge note 8c files. (Renamed 2026-09-12 so a heading scan over this file reports no duplicate.)

**Versions this design was verified against.** Ruby 3.4.10; `async-http` 0.104.0, `async` 2.45.1,
`async-pool` 0.12.0, `console` 1.37.0, `protocol-http` 0.71.0, `protocol-http1` 0.41.0, `protocol-http2`
0.28.0, `protocol-hpack` 1.5.1, `protocol-url` 0.19.0, `io-event` 1.22.0, `io-endpoint` 0.18.0,
`io-stream` 0.14.0, `fiber-annotation` 0.2.0, `fiber-local` 1.1.0, `fiber-storage` 1.0.1, plus `openssl`
4.0.2 and `json` 3.0.2 (both default gems in a normal bundle).

**The two routes to HTTP/2**, because a plan will need both and neither is the documented default:

```ruby
# (a) plaintext, prior knowledge — no h2c upgrade exists in async-http's client
endpoint = Async::HTTP::Endpoint.new(uri, protocol: Async::HTTP::Protocol::HTTP2)

# (b) TLS with ALPN — note that a caller-supplied ssl_context NEVER gets alpn_protocols set for it
ctx = OpenSSL::SSL::SSLContext.new
ctx.alpn_protocols = ["h2", "http/1.1"]        # without this line, HTTP/1.1 is negotiated
ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER    # without this, localhost silently gets VERIFY_NONE
endpoint = Async::HTTP::Endpoint.new(uri, ssl_context: ctx)
```

**The four library sources this design reads as normative for its own decisions**, with the exact lines:

| What | Where |
|---|---|
| `write_request` writes the request line and `host:` before `write_headers`, and rewraps everything as `RefusedError` | `protocol-http1-0.41.0/lib/protocol/http1/connection.rb:262-270` |
| `VALID_FIELD_NAME` / `VALID_FIELD_VALUE` | `protocol-http1-0.41.0/lib/protocol/http1/connection.rb:45-46` |
| `Client#call`'s retry loop, `DEFAULT_RETRIES = 3`, and `Client#close`'s `wait_until_free` | `async-http-0.104.0/lib/async/http/client.rb:19,92-145` |
| `Endpoint#ssl_context` — a caller-supplied context bypasses ALPN; `ssl_verify_mode` is `VERIFY_NONE` for localhost | `async-http-0.104.0/lib/async/http/endpoint.rb:185-207` |
| `Async::Task#stop` is a deprecated alias for `#cancel`; `#cancel(later = false, cause: $!)` | `async-2.45.1/lib/async/node.rb`, `async-2.45.1/lib/async/task.rb` |
| `Async::Task.current` raises `RuntimeError, "No async task available!"` | `async-2.45.1/lib/async/task.rb:438` |
| `Protocol::HTTP::Headers#each` yields `key.to_s.downcase` (the HTTP/2 lowercasing) | `protocol-http-0.71.0/lib/protocol/http/headers.rb:559` |
| `Pool::Controller#wait_until_free` is `@condition.wait(@mutex) while busy?`; `#close` is `drain` then clear | `async-pool-0.12.0/lib/async/pool/controller.rb:139-147,198-213` |

**The probe scripts**, in the scratchpad, each re-runnable under the scratchpad `GEM_HOME`:
`deps.rb` (closure and floors), `h2.rb` (HTTP/1.1 versus HTTP/2 in process), `tls.rb` (TLS + ALPN),
`hdr.rb`/`hdr2.rb`/`h2hdr.rb` (header mapping per protocol), `wire1.rb` (exact outbound bytes),
`poison.rb` (the partial-request case and connection reuse), `lifetime.rb` (body laziness, status
mapping, outside-reactor), `pool.rb` (pool bounds, concurrency, inbound headers, `Client#close`),
`body.rb` (large-body close, streaming upload, `rewind!`/`retry!`), `cancel.rb` (cancellation, timeouts,
error ancestries, `Fiber[]`), `goaway.rb` (parent-task cancel, GOAWAY), `final.rb` (mid-body abort, stop
edge cases), `env.rb` (reactor requirement, retries, middleware, error taxonomy), `last.rb` (streaming
upload, `with_timeout`, `cancel(cause:)`).

---

## Open questions for 8c's own plan

Eight, each with the decision already narrowed to two or three branches so the plan settles rather than
re-opens.

1. **Does `gem_rbs_collection` carry signatures for `async-http` or any of its closure?** Not verifiable
   here. If yes, `rbs_collection.yaml` gains a normal `- name: async-http` row and Steep types the
   adapter's internals. If no, the row is an explicit no-signatures entry and every foreign constant is
   `untyped` inside this gem's target. **Either way the public surface is unaffected**, because the
   `sig/` section's three clauses keep every foreign constant out of it. The plan's first task checks and
   writes the row it finds.
2. **What exactly does `VERSIONS` gain, and who edits `gates:versions`?** `R15` fixes the shape
   (`ruby floor dexpace-transport-async_http  3.3`) and `OI-38` records that the gate is phase-0
   machinery. The plan decides whether 8c's own PR carries the three-line gate change or whether it is a
   phase-level task beside `Dexpace::TransportError`. **This document's recommendation: phase-level**, on
   the same reasoning the charter gives for `TransportError` — it lands in a file none of the three
   sub-phases owns.
3. **Is `connection_limit`'s default 8, and is its `Configuration::Keys` name new or shared?** The value
   is chosen, not derived, and the plan may move it after measuring. The key name is the real question:
   whether phase 5a's chain already carries a connection-limit key that `8a` will also want, in which case
   it is shared, or whether it is `Keys::TRANSPORT_CONNECTION_LIMIT` and 8c adds it. 8c must not add a
   second key for a concept `8a` names differently.
4. **Does `DropPolicy` live in this gem or in `dexpace-core`?** `DEF-41` says "Phase 8 writes a small
   `Data` over both [5b ingredients], at the one call site that actually drops a header", which reads as
   the adapter. But `TRANSPORT-13` binds *any* adapter that drops, and a second adapter would want the
   same object. **This document's recommendation: this gem**, because `OI-8`'s shape — public,
   `NFR-4`-locked API with no caller — is exactly what a core-resident policy with one external caller
   would be, and moving it to core later widens rather than narrows. The plan states the decision either
   way, and `DEF-41`'s closing note records it.
5. **HTTP/2 multiplexing under window pressure.** Facts 2, 3 and 4 exercise the h2 path functionally but
   not many concurrent streams on one connection under flow control. The plan adds an `ASYNC-22` variant
   over HTTP/2 with N concurrent streams on a single connection, and decides N.
6. **Does the HTTP/2 fixture generate its certificate per run or per suite?** Per run is simpler and costs
   an RSA keygen (~100 ms at 2048 bits, measured incidentally in fact 3); per suite needs a cached
   artefact and a `.gitignore` entry. **Recommendation: per run**, inside the 30-second budget.
7. **Where does the `ASYNC-7` README section live, and does it duplicate `8a`'s?** §3.3 fixes the
   *content* of the contrast — "the thread adapter lets an in-flight blocking read finish, the
   reactor-backed ones abort at the next scheduler checkpoint" — and the charter makes the *assertion*
   that the two differ a conformance row `8c` adds. The plan decides whether that row compares two
   README strings (brittle) or two measured behaviours (right, and what fact 8 already demonstrates for
   this half).
8. **Do the thirteen verified facts hold on 3.3 and 4.0?** 3.2 is out of scope by `R15`. The plan's first
   task re-runs the whole probe set on both, and any divergence becomes a note under
   `docs/knowledge/notes/` rather than an edit to this document — the same discipline
   `observability/65191069`'s single-interpreter caveat exists to enforce.
