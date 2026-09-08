# Phase 4a — Execution Context

**Status:** Draft, for review. Written 2026-09-08, against
`docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md`, which is this sub-phase's charter.

## Purpose

Sub-phase 4a builds the correlation model one in-flight call carries from before its request exists to
after its response has arrived: three immutable context flavours forming a one-way promotion chain, one
call-unique key they share, one bounded process-wide store they register in, and the instrumentation
bundle every one of them holds. Twenty `CTX` IDs, one specification chapter, one gem.

**It is also the one place in phase 4 that signs a contract with a later phase.** Roadmap cross-phase
obligation 1 — "Phase 4 fixes the shape and ships the bundle in core; phase 5 implements the sentinels and
populates rather than replaces it. Phase 4 cannot defer the decision to phase 5, and phase 5 cannot
redefine it" — lands entirely here. Design §8.1 enumerates the bundle's nine members and their no-op
values and names none of them in Ruby. This document names them, and every name is `NFR-4`-locked at the
first release tag.

Four decisions reshape what a plan can write, and each was forced by a fact run on a real interpreter
rather than by taste.

- **A frozen `Data` cannot carry a close latch, so a context has none — and needs none.** `Dexpace::Closeable`
  flips `@dexpace_closed` under a mutex; a `Data` instance is frozen on construction and the write raises
  `FrozenError` on 3.2.11, 3.4.10 and 4.0.6. That is not an obstacle to route around: `CTX-9`'s eviction is
  conditional on **reference identity**, so the second close finds a different occupant or none and is
  already a no-op, which is exactly what `CTX-18` asks for. `#close` is idempotent through the store, not
  through a latch, and 4a writes no second latch (P4-4).
- **The call key participates in value equality, and the test that proves `CTX-9` exists only because
  `CTX-5` requires an escape hatch.** Two default-constructed contexts are never `==` (verified). To
  reproduce `CTX-9`'s trap at all you need two contexts that are `==` and not `equal?` — which is
  constructible only by pinning the same explicit key on both, the affordance `CTX-5`'s last clause
  mandates. The requirement and its own test are the same mechanism seen twice (R2).
- **The bounded store's drain loop is degenerate under this port's mutex, and the proof is structural — the
  obvious measurement proves nothing.** `CTX-12`'s stated rationale is convergence under concurrent insert
  bursts. The tempting evidence is a count: 8000 inserts from 16 threads against a cap of 64 leave exactly
  64 entries and run the drain body exactly 7936 times, on all three interpreters. That number is worthless.
  `7936 = 8000 − 64` is forced by conservation — every distinct key adds one entry, every drain iteration
  removes one — so *any* one-eviction-per-iteration drain produces it. Measured: a **split-lock** drain, where
  overshoot genuinely is reachable, and a **single `if` with no loop at all** both produce the identical
  8000 / 64 / 7936 on all three. What actually settles it is an argument: insert and drain sit in **one**
  `synchronize`, exactly one key is added per critical section, and the loop's invariant on entry is
  `size ≤ cap`, so `size ≤ cap + 1` at the top and the body can run at most once. The loop is written
  because `XCUT-14` makes it a MUST (`CTX-12` a SHOULD), not because it buys the convergence the rationale
  describes. A corpus note records it, with the discriminating measurement rather than the vacuous one (R4).
- **`ObjectSpace::WeakKeyMap` does not exist on the supported floor, and that does not weaken the gate.**
  `CTX-19`'s prohibition becomes a seventh custom cop, and its test table is a table of **source strings**:
  RuboCop parses, never evaluates, and `ObjectSpace::WeakKeyMap.new` parses cleanly on 3.2.11 where the
  constant is undefined — verified against the parser the suite actually runs, `RuboCop::ProcessedSource` at
  `TargetRubyVersion 3.2`, and not only against `RubyVM::AbstractSyntaxTree`. The accompanying behavioural
  test is a real discriminator rather than a tautology — a strong `Hash` returns 1000 of 1000 registered
  contexts after three `GC.start`s and an `ObjectSpace::WeakMap` returns 0, on all three — and it is a
  discriminator against `ObjectSpace::WeakMap` only: a `WeakKeyMap` passes it, which is why the cop and not
  the test is what forbids that spelling (R1).

4a ships no pipeline, no recovery chain, no transport and no socket. Its whole test surface is value
objects, one synchronised hash, and the three execution carriers Ruby offers.

## Governing documents

- `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md` — the charter. It fixes 4a's 20 IDs, the
  sixteen spec-forced boundaries and risks R1–R4. R5–R14 belong to 4b and 4c and are not touched here.
- `docs/product-spec/07-execution-context-model.md`, read in full, with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` for the canonical text of all
  twenty `CTX` IDs, and of `OBS-25`, `OBS-26`, `OBS-27`, `XCUT-11`, `XCUT-14`, `XCUT-15` and `AUTH-19`,
  which fix values 4a must carry or share.
- `docs/sdk-design-ruby/05-pipeline-architecture.md` §5.4 in full;
  `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.1 in full — the correlation bundle, the
  fiber-storage paragraph and the `opentelemetry-api` structural-subset rule;
  `docs/sdk-design-ruby/04-domain-model-construction.md` for the construction pattern;
  `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items 10, 11 and 18;
  `docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md` item 11
  (embedded MUSTs inside SHOULDs, which names `CTX-16` and `CTX-20` by ID); and §12's `CTX` row.
- `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` — the phase-4 row, cross-phase obligation 1, and
  the ✅ / 🚫 / ⏳ / N/A legend this sub-phase's checklist uses verbatim.
- `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates.md`,
  `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md`,
  `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` with
  `docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md`, and
  `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md` — what 4a stands on.
- `CLAUDE.md` and `docs/README.md`.

## Scope

### The 20 IDs, with dispositions

**Implemented — 20.** `CTX-1`–`CTX-20`, every one of them. Design §12's `CTX` row reads "*Deferred:* none",
and 4a defers nothing of its own scope.

Sixteen are MUST, three are SHOULD (`CTX-12`, `CTX-16`, `CTX-20`) and one is MAY (`CTX-13`).

- **`CTX-12` is implemented** — the post-insert drain loop, with the honest note above about what the mutex
  already guarantees.
- **`CTX-16` and `CTX-20` are the two SHOULDs design §11.11 flags as carrying embedded MUSTs** — "read as
  'the feature is optional, its behaviour is not' — where the port ships the feature it implements every
  embedded MUST". 4a ships both features, so `CTX-16`'s "MUST be carried forward unchanged" and "MUST be
  advisory only" and `CTX-20`'s "factory method MUST be safe to invoke concurrently" are all implemented and
  all tested. `CTX-20`'s embedded MUST is what forces 4a to name the factory method rather than ship an
  opaque object (R3).
- **`CTX-13`'s arbitrary-victim latitude is taken as-is**, which design §12 already records. 4a chooses
  oldest-registration-first and states the consequence rather than leaving it implicit (below).

**Also fixed by 4a without owning a new ID**, per the charter:

- the shape of `Dexpace::Instrumentation::Bundle` — §8.1, roadmap obligation 1 (R3);
- the bounded-map implementation `CTX-11` shares with `XCUT-14`'s general rule and `AUTH-19`'s per-nonce
  counter store (R4);
- the process-wide monotonic counter `CTX-4`'s key appends (R2).

### The canonical text the design turns on

Quoted from appendix C rather than paraphrased, because each fixes a decision below.

> **CTX-2** (MUST) — Each promotion MUST be additive and non-mutating: it produces a NEW context instance
> and never modifies the source. It carries forward, unchanged, the fields the source already has — the
> same InstrumentationContext reference and the same callKey (and, for the request->exchange promotion,
> additionally the same request and operationName) — and adds exactly the one new artifact for that stage
> … operationName is introduced at the request stage as an argument to the dispatch->request promotion; the
> dispatch context has no operationName field, so it is not 'carried forward' from the dispatch source.

> **CTX-4** (MUST) — Each call's store key MUST be unique per call and MUST NOT be derived from the trace
> identifier — or the trace+span pair — alone … The reference implementation derives the default key by
> appending a process-wide, monotonically increasing counter to a 'traceId:spanId' rendering (yielding
> 'traceId:spanId:n'); the exact format and the counter mechanism are a reference choice, and a port MAY key
> differently as long as the per-call-uniqueness invariant holds.

> **CTX-5** (MUST) — A context constructed directly (off-chain, not via promotion) without an explicit key
> MUST receive a fresh call-unique key using the same uniqueness guarantee as CTX-4. A consequence, given
> that the key participates in value-equality, is that two directly-constructed contexts with otherwise
> identical fields are NOT equal (their generated keys differ); callers who require value-equality MUST be
> able to pin an explicit shared key at construction.

> **CTX-8** (MUST) — The store MUST support unconditional overwrite ('set': install-or-replace, never
> throwing) used by promotion, and MUST support a reject-on-duplicate insert ('put': install only if
> absent, failing the loser). Concurrent inserts of the same key via the reject-on-duplicate path MUST
> deterministically admit exactly one winner and fail all others with an error whose message identifies the
> key. (Promotion uses only 'set'; 'put' is a separate strict-register affordance.)

> **CTX-9** (MUST) — Closing a context MUST evict the chain's store entry CONDITIONALLY ON REFERENCE
> IDENTITY: it removes the slot only when the currently registered occupant IS the closing context (same
> reference). It MUST NOT match by value equality. Removing a non-existent or already-replaced slot MUST be
> a well-defined no-op, not an error.

> **CTX-13** (MAY) — Eviction victim selection under cap pressure is arbitrary: the store provides NO
> ordering … and NO guarantee that any particular entry survives an insert that trips the cap — INCLUDING
> the entry that was just inserted … A port MAY choose a smarter (e.g. oldest-first) victim policy, but a
> port MUST NOT rely on any specific entry — the most-recently inserted included — surviving.

> **CTX-14** (MUST) — Each context MUST carry a correlation/instrumentation metadata bundle exposing at
> minimum: a trace id, a span id, trace flags, trace state, a trace-id encoding flavor, validity and
> remoteness flags, an active span, and a per-operation tracer factory. This bundle is what lets logs,
> metrics, and spans across the dispatch/request/exchange phases correlate into one logical trace.

> **CTX-15** (MUST) — A disabled-tracing / no-op instrumentation context MUST be available as the default
> and MUST expose reserved 'invalid' sentinel identifiers (an all-zero trace id, all-zero span id, zero
> trace flags, empty trace state) with isValid=false and isRemote=false, and a no-op span and no-op tracer
> factory. Because such a context shares constant identifiers across every untraced call, the call-key
> derivation (CTX-4) MUST remain correct (call-unique) even when every field of this bundle is identical
> across calls.

> **CTX-19** (MUST) — A registered context MUST keep its full Request+Response object graph reachable for as
> long as it stays in the store … reimplementations MUST NOT hold contexts by weak/soft references (that
> would let an in-flight context be collected mid-call) and MUST treat the bounded cap (CTX-11) — not
> garbage collection — as the leak backstop.

Two IDs outside `CTX` fix values 4a must carry, and are quoted because 4a is where they first become real:

> **OBS-26** (MUST) — … The reserved invalid sentinels MUST be: trace id of 32 hex zeros, span id of 16 hex
> zeros, trace flags '00', and empty trace-state; an all-zero trace/span id MUST be treated as
> invalid/no-trace.

> **OBS-27** (MUST) — Trace-id generation MUST support at least the W3C flavour (128-bit value rendered as
> 32 lowercase hex chars) and a Datadog flavour (64-bit unsigned integer rendered as a decimal string), plus
> a no-op flavour that always yields the invalid sentinel …

### Out of scope, explicitly

| Excluded | Owning phase |
|---|---|
| `RECOV-1`–`RECOV-34` — the recovery chain, its outcome type and its error primitives | 4b |
| `PIPE-1`–`PIPE-40` — the stage pipeline, the per-call cursor and the two bridges | 4c |
| `OBS-25`'s no-op tracer and span **protocols**, `OBS-26`'s sentinel definitions as tracing API, `OBS-27`'s trace-id **generation** | 5. 4a fixes the bundle's members, their names and the identity of the two no-op singletons; phase 5 populates and may not redefine (roadmap obligation 1, `DEF-37`) |
| `OBS-10`, `OBS-23`, `OBS-24`, `ASYNC-8`–`ASYNC-12` — the **diagnostic context** carried in `Fiber[:key]` | 5 and 8. This is not `CTX`; `docs/knowledge/notes/observability.md` draws the line and 4a asserts it in one test rather than restating it |
| `SEAM-28` — a stable operation identifier attached to the context chain | 5 (`DEF-1`). 4a supplies the chain half — `CTX-16`'s operation name is the carrier — and does not act on the rest |
| `CFG-15`–`CFG-21` — the clock, the **elapsed-time** monotonic counter, the interruptible sleep | 5 (`DEF-28`). `CTX-4`'s counter is a sequence counter and shares nothing with it but the adjective (`OI-15`) |
| A configuration source for the store's cap | 5 (`DEF-36`). 4a owns the constant and the `cap:` keyword that reaches it |
| `XCUT-14`'s audit of every bounded map, and `XCUT-11`'s audit of shared-instance state | 9. 4a builds the map `XCUT-14` audits |
| `AUTH-19`'s per-nonce counter store | 6. It reuses 4a's map and adds one operation to it (R4) |
| Any `Ractor` shareability claim for a context | none. `data-modeling/5bc538ba` already narrows it and a context transitively holds a body holding an `IO` |

**No segmentation design of its own.** 4a is one spec chapter, one gem, 20 IDs, under a segmentation design
that already exists at the `phase4/` level.

## Prerequisites, and the independence this sub-phase must state

**4a depends on 4b and 4c for nothing, and neither of them depends on 4a.** The charter's central structural
finding is that `CTX` is consumed by nothing in `RECOV` or `PIPE` — `CTX-<n>` is cited in no specification
chapter outside ch.07, and in no design section outside §5.4, §8.1, §11.11 and §12 bar one `CTX-9`
*comparison* in §5.2 that reads nothing from it. 4a leads for three convenience reasons and not because
anything waits on it. **This section states that independence rather than inheriting a chain by habit**,
which is what the charter requires of each sub-phase design.

### From phase 0 — seventeen blocking gates, unchanged and unlowered

`gates:require_allowlist` — core's `lib/**/*.rb` may `require` only `monitor`, `uri`, `stringio`,
`strscan`, `time`, `date`, `securerandom`, `digest`, `openssl`, `forwardable`, `set`, `singleton`. **4a adds
nothing to it and requires nothing at all.** `Data`, `Hash`, `String`, `Integer`, `Regexp` and
`::Thread::Mutex` are core Ruby. `securerandom` is allowlisted and 4a does **not** use it: `CTX-4`'s key is a
rendered prefix plus a counter, and design §5.4 rejects "a bare UUID, which would lose the debuggability the
prefix buys".

The allowlist is also half of R1's answer. `require "weakref"` inside `dexpace-core` is **already** rejected
by this gate, because `weakref` is not on the list — verified that `require "weakref"` succeeds on 3.2.11,
3.4.10 and 4.0.6 and that `weakref` appears in no `Gem::BUNDLED_GEMS::SINCE` table, so it is a live
temptation the gate happens to catch. What the gate cannot see is `ObjectSpace::WeakMap` and
`ObjectSpace::WeakKeyMap`, which need no `require` at all, and it does not cover adapter gems. That is the
cop's job.

`gates:surface_snapshot` and `gates:sig_diff` are regenerated once, deliberately, in the phase's last task.
Every public constant below is `NFR-4`-locked at the first release tag, which is why each is named on purpose
and carries a Deviation Ledger row where design §5.4 or §8.1 did not already name it. `Dexpace/SpdxHeader`
and `Dexpace/NoThreadInterrupt` bind every file; the latter has nothing to bite on here, because 4a starts no
thread and interrupts none.

### From phase 1

- **`Dexpace::Model`** — `Model.required!(name, value)` raising `Dexpace::InvalidArgumentError` with the one
  message form `"<name> is required"` (`SEAM-29`); `#with` overriding `Data#with` to route through the
  validating `.build`, because `Data#with` skips an `initialize` override on 3.2.11; `Model.own(collection)`
  = `Ractor.make_shareable(collection, copy: true)`; `Model.frozen_string(value)`. Every `Data` 4a defines
  includes it, so `#with` re-validates on every supported Ruby without 4a writing a line.
- **`Dexpace::InvalidArgumentError < ::ArgumentError`** — every argument-validation failure in 4a raises it.
  `Dexpace::ArgumentError` is never defined.
- **`Dexpace::Error` is a module** (P1-2), included by 4a's one new error class.
- **`Dexpace::Request` and `Dexpace::Response`** — the two artefacts `CTX-2`'s promotions add.
- **Public constants are flat unless the design namespaced the subsystem** (P1-1). Design §8.1 names
  `Dexpace::Instrumentation::Bundle`, so the instrumentation subsystem keeps its namespace. Design §5.4 names
  no Ruby constant for the contexts or the store at all, so 4a names them and every name carries a ledger row.
- **No `.build` is a bare `new` wrapper.** Validation lives in each `Data` type's `initialize`.
- **`downcase` takes no argument** (`Dexpace/NoLocaleCaseFold`). 4a folds nothing; its two hex patterns —
  `W3C`'s 32-character trace id and `Bundle`'s 16-character span id — are written lowercase-only and reject
  an uppercase input rather than folding it, because `OBS-26` says "16 lowercase hex chars" and a fold would
  silently accept `0A` where the wire form is `0a`.
- **`Regexp.new(source, timeout:)` per pattern, never `Regexp.timeout`.** Phase 1 applies this even to a
  two-character hex pattern; 4a follows the same rule for **all four** of its patterns rather than arguing
  that an anchored character class cannot backtrack. The four are inventoried under `TraceIdFlavour` below.

### From phase 2

- **`Dexpace::Hooks` as a precedent, not as a collaborator.** `Hooks` is a `private_constant` with no `sig/`
  mirror, no YARD gate entry and no surface-manifest row (P2-15), called from three `core`-target files with
  both typing gates green. 4a's two `private_constant`s — `Dexpace::BoundedMap` and `Dexpace::CallKey` —
  follow it exactly.
- **`Dexpace::Cancellation`, the async pivot, the registries, `Dexpace::Closeable` and the two `SEAM-18`
  bridges are not used by 4a**, and `Dexpace.close_quietly` gains no new call site. A context's `#close`
  cannot raise (`CTX-18`), so there is nothing for `close_quietly` to swallow. **4a adds no fourth registry.**
- **The error-class shape** — `class X < ::StandardError; include Dexpace::Error; end`, as `SeamError`,
  `ClosedError` and `CancelledError` all are. `Dexpace::ContextConflictError` is the fourth.
- **`Dexpace::Closeable` is deliberately *not* included by a context**, and the reason is a verified fact
  rather than a preference — see P4-4.
- **The private-snapshot rule (P2-9)**: a `Data` that is public API follows phase 1's construction rule
  without exception; only a `private_constant` snapshot is exempt. Every `Data` 4a ships is public API, so
  every one gets `private_class_method :new` plus a validating `.build`.

### From phase 3

- **`Dexpace::Response#close` and the body tree.** 4a stores a `Response`, never reads one. `CTX-19` is the
  reason the store must hold it strongly: phase 3b's `ResponseBody` can pin a connection, which is exactly
  the graph ch.07 §7.4's rationale names.
- **The sixth cop as extended by 3a (P3-7)** — `Dexpace/QualifiedCoreConstant`, `SHADOWED` =
  `Thread Queue Mutex SizedQueue ConditionVariable JSON IO`, `WATCHED` = the one-segment `%w[Dexpace]`, with
  a definition-site guard, over `gems/*/lib/**/*.rb`. **4a adds nothing to `SHADOWED`**, and the standing
  rule 3a stated is why: a constant joins the list in the same change that creates the `Dexpace::` constant
  which shadows it, and no constant 4a defines shares a name with a Ruby core constant. That is not luck —
  it is the reason the three context flavours are `Dexpace::DispatchContext`, `Dexpace::RequestContext` and
  `Dexpace::ExchangeContext` rather than `Dexpace::Context::Request` and siblings (P4-1).
- **The `CopCase` harness** (phase 0, `.rubocop/test/cop_case.rb`) with `TARGET_RUBY = 3.2`, one row per
  case in `.rubocop/test/cops_test.rb`, `#assert_offense(cop_class, source, message_fragment)` and
  `#assert_no_offense`. The seventh cop's cases go into that same table.
- **Two open items land in 4a's window and neither is 4a's to fix.** `OI-8` and `OI-9` are phase-3 findings
  whose window closes when phase 3's plans execute; 4a neither widens nor closes them.

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run before anything here was written, and the counts below
are what it returned **before this phase filed its own two notes**; a reader re-running the first query
afterwards should expect 32 entries across 17 files, not 30 across 16.
`--origin note --brief` returns **30 entries across 16 note files**; `--section conflicts --brief` returns 18
note entries and 6 harvested ones, and **all six harvested conflicts print `[overridden by notes/…]`** —
`data-modeling/35fde90f`, `module-organization/bf6411ad`, `package-and-dependency-layout/41b154a3` and
`/8c0687bf`, `tooling-and-quality-gates/86d763f1`, `type-system/93dc79aa`. None is open, so 4a inherits no
unresolved conflict and owns no conflict decision of its own.

`--prefix-info CTX` reports 20 IDs, 16 MUST / 3 SHOULD / 1 MAY, owning chapter
`docs/product-spec/07-execution-context-model.md`, and **20 of 20 substantive with zero roll-up-only
entries**; `--gaps CTX` returns nothing. **The appendix-B roll-up hazard does not fire for this prefix at
all**, and 4a budgets no specification reading beyond ch.07, which was read in full anyway because it is
33 lines.

`--phase 2 --brief` and `--phase 3 --brief` were run. **Neither phase cites a single `CTX` ID** — phase 2's
70 distinct IDs and phase 3's 152 contain none — which is the charter's independence result arriving from
the other direction. Phase 1 cites none either.

**The `CTX-9` cross-filing is real and was met.** `--req CTX-9` returns `error-handling/1f635244` and
`error-handling/5a7d53ab`, both about `Dexpace.each_cause`, because design §5.2 likens the cause walk to
"the same trap **CTX-9** sets in §5.4" and the harvest read the comparison as a citation. They are 4b's
material. The charter recorded this as a known artefact; it is confirmed here and earns no note, because it
is a cross-filing rather than a wrong rule.

### The audit groups this phase ran

| Group | Query | Result |
|---|---|---|
| **Pipeline composition and execution context** | `--prefix CTX --section rules` then `--topic execution-context --section constraints,conclusions,reference` | 15 + 23 entries, the whole `execution-context` topic. Two entries earn notes (below); the rest are adopted and cited by key rather than restated |
| **Fiber scheduler, thread safety** | `--topic concurrency-and-async --section rules` and the same narrowed by `--grep 'mutex\|GVL\|thread-saf\|counter\|monotonic\|atomic\|fiber'` | 75 + 14 entries. `concurrency-and-async/f414b864` (the note) governs and is load-bearing three times: the store, the counter and the `put` race. `concurrency-and-async/0e11c51d`'s "shared counters must use `Concurrent::AtomicFixnum`" is already overridden by that note and needs no second |
| **Public API surface** | `--topic api-design,module-organization,documentation --section rules` | 51 entries. `api-design/1d9e6e0b` (keywords everywhere) shapes every signature and takes one stated exception (P4-8); `api-design/6ea28c9c` (never `nil` for absent) is answered by `CTX-18` requiring exactly that; `api-design/88e6bf12` (narrowest duck-typed parameter) is what makes the store testable; `module-organization/64e84d64` (full nesting form, never compact) is **the load-bearing rule R4 turns on** |
| **RBS / Steep typing** | `--topic type-system,data-modeling --section rules` | `type-system/545949a5` fixes the trace-id flavour as a frozen `Data` over a frozen table with a `parse`/`of` factory and never a `T::Enum`; `data-modeling/b74a2869` and `/ec0f41cb` put `CallKey` in a module rather than a class; `data-modeling/3e37c086` puts `ContextStore` in a class, because it owns state |
| **Minitest conventions** | `--topic testing,assertions --section rules` | 29 entries. `testing/7ecef8e8` and `/630ba094` name the one double 4a builds a **fake** and not a mock; `testing/4ef070df` (every test runs alone, in any order, fresh fixtures) is what forces the store's `cap:` keyword and forbids a suite that mutates one process-wide hash; `testing/62f8f4ec` shapes the `CTX-8` conflict test |
| **RuboCop and formatting** | `--topic tooling-and-quality-gates --section rules` | Clean. Phase 0's `CopCase` table shape and phase 2's/3a's precedent for adding to it govern R1 |
| **Styleguide-vs-design conflicts** | `--section conflicts --brief` | All six resolved; none open |

Two audit results earn **no note**, for the reasons 3a's own design fixed:

- **`resource-management/bf5560dc`** ("use block form … for every closable resource") does not reach a
  promotion chain, and the reason is specific rather than general: the object that must be closed is the
  **furthest-reached link**, which does not exist when the head is constructed. A block form on
  `DispatchContext` would close the head — a no-op by `CTX-10` — and leak the exchange context that
  actually occupies the slot. A rule that does not reach the case is a Deviation Ledger row (P4-5), not a
  note.
- **`api-design/c15b29ce`** ("every collection returned from a public method must be frozen") is *adopted*,
  not overruled: `Bundle#trace_state` is deep-frozen once at construction through `Model.own`, which is
  `HTTP-5`'s mechanism applied to a new type. An adopted rule needs no note.

### The two notes filed against the corpus by this phase

Written before the plan, because a resolution recorded only in a design document is re-litigated by whoever
reads the corpus next. `docs/knowledge/notes/execution-context.md` is a new file; `harvested/` is untouched.

- **`## Superseded`, superseding `execution-context/7459f067`** — the drain loop's *instruction* is adopted
  and its *rationale* does not apply to this port. The entry says the loop exists "so concurrent insert
  bursts converge to the bound instead of overshooting". With the insert and the drain inside one
  `Thread::Mutex` no concurrent insert can interleave between them, so the body runs at most once per insert
  and an overshoot is unreachable rather than rare — which is a proof from the shape of the critical section,
  not from a count. The note carries the proof **and** the count that fails to support it, because the count
  is what a later reader would reach for: 8000 inserts at cap 64 giving exactly 7936 iterations is
  `inserts − final size`, and a split-lock drain and a bare `if` both produce it. The convergence property is
  real for a striped or lock-free map and vacuous here. The note matters because the inverse inference is
  available and wrong: a reader who believes the loop *provides* convergence can conclude the mutex is what
  the loop replaces.
- **`## Superseded`, superseding `execution-context/c2eb344c`** — "one implementation" shared with
  `XCUT-14` and `AUTH-19` is achievable and is conditional on a rule the corpus already holds separately.
  Verified on all three: a `private_constant` on `Dexpace` **is** reachable by a bare, unqualified reference
  from any lexically nested `module Dexpace; module X` at any depth, **is not** reachable from the compact
  `module Dexpace::X` form, and **is not** reachable through a qualified `Dexpace::BoundedMap` even from
  inside `Dexpace`. So the sharing works only where `module-organization/64e84d64`'s full-nesting rule is
  followed, which the repository already requires for an unrelated reason. The note records the coupling so
  phase 6 and phase 9 meet it as a stated condition rather than as a `NameError`.

## The verified Ruby facts this phase is built on

Every claim was run on 3.2.11, 3.4.10 and 4.0.6 through `mise exec ruby@<v>` on 2026-09-08. The first six
changed a decision; the rest are recorded because a plan would otherwise assume them.

1. **A frozen `Data` cannot carry a close latch.** A method on a `Data` subclass writing `@closed = true`
   raises `FrozenError: can't modify frozen D` on all three. `Dexpace::Closeable`'s whole mechanism is a flag
   flipped under a mutex, so it cannot be included into a context. This is what makes `#close` idempotent
   through the store instead (P4-4). An ivar set *before* `super` inside an `initialize` override does
   survive and the object is still frozen afterwards — recorded so a plan knows the hole exists and does not
   use it.
2. **`ObjectSpace::WeakKeyMap` is undefined on 3.2.11** and defined on 3.4.10 and 4.0.6;
   `ObjectSpace::WeakMap` exists on all three and needs no `require`. `require "weakref"` succeeds on all
   three and `weakref` is in no `Gem::BUNDLED_GEMS::SINCE` table (undefined on 3.2.11; 28 entries on 3.4.10;
   23 on 4.0.6). **And `RubyVM::AbstractSyntaxTree.parse("ObjectSpace::WeakKeyMap.new")` succeeds on 3.2.11**,
   where the constant does not exist. **The parser that matters is RuboCop's, not `RubyVM`'s**, so it was run
   too: `RuboCop::ProcessedSource.new(source, 3.2, path)` on RuboCop 1.90.0 — the version phase 2 and 3a both
   recorded, run here on 3.4.10 because that is the only matrix row with the gem installed, which is exactly
   the point: the parse target is pinned by `TARGET_RUBY` and does not follow the interpreter — accepts all
   fifteen rows of the table below with `valid_syntax?` true and no diagnostic, and
   yields the `const` nodes the cop matches on, including the bare `WeakMap` inside `module ObjectSpace` and
   the commented-out row, which correctly yields none. That is why a source-text cop's table runs unchanged
   on the floor (R1).
3. **A `WeakMap` and a `Hash` are distinguishable by a test that names neither.** 1000 objects registered
   and then dereferenced: after three `GC.start`s a strong `Hash` returns 1000 of 1000 and an
   `ObjectSpace::WeakMap` returns **0 of 1000**, on all three. `CTX-19`'s behavioural test is therefore a
   real discriminator and not a tautology (R1).
3a. **A `WeakKeyMap` is *not* distinguishable by that test, for a structural reason.** The same 1000-context
   run against `ObjectSpace::WeakKeyMap` returns 1000 of 1000 on 3.4.10 and 4.0.6: a `WeakKeyMap` holds its
   values strongly, and the stored context strongly holds the exact frozen `String` that is its key, so no
   entry is ever collectable. `CTX-19`'s reachability property therefore survives that substitution, and the
   substitution is still forbidden — by the cop alone (R1).
4. **A value-equality delete over the store evicts a structurally identical live sibling; an identity delete
   does not.** With two `Data` contexts carrying identical members, `h.delete_if { |_, v| v == other }`
   empties the hash while `h.delete(k) if h[k].equal?(other)` leaves it intact — and the identity delete
   *does* remove the slot when handed the actual occupant. All three. `CTX-9` reproduced, and the test 4a
   owes is three lines (R2).
5. **The drain loop's per-call iteration count is at most one, and the aggregate count does not show it.**
   8000 concurrent inserts, cap 64: final size exactly 64 and drain-body iterations exactly
   7936 = 8000 − 64, on all three — but the same three numbers came back from a split-lock drain that *can*
   overshoot and from a single `if` carrying no loop, so the aggregate is an arithmetic identity and not
   evidence. The measurement that discriminates is **the maximum iterations in one call** and **the maximum
   size ever observed**: under the one-`synchronize` insert-and-drain both are `1` and `cap` on all three,
   while splitting the two critical sections at cap 8 with 32 threads was observed at size `9`. See the
   corpus note above (R4).
6. **A `private_constant` on `Dexpace` is bare-name reachable from every full-nesting descendant and from
   nothing else.** `module Dexpace; module Store` and `module Dexpace; module Auth; module Digest` both
   resolve a bare `BoundedMap`; `module Dexpace::Compact` raises `NameError: uninitialized constant`; a
   qualified `Dexpace::BoundedMap` raises `NameError: private constant … referenced` **even from inside
   `Dexpace`**; and from outside it raises the same. The reachability is **per file, not per gem**: a
   separately-`require`d file that reopens `module Dexpace; module Conformance` resolves the bare name
   exactly as a file in the defining gem does, so "a different gem" is never the reason a private constant is
   out of reach — the *reference form* is. `Module#constants` excludes it, and so does
   `Module#constants(false)`, so it takes no surface-manifest row. All three (R4).
7. **`Data` value equality behaves exactly as `CTX-5` predicts.** Two contexts differing only in `call_key`
   are not `==`; two sharing a pinned key are `==`, `eql?` and hash-equal, and one finds the other as a
   `Hash` key. `#with` carries a member's **identity** forward, not a copy — `c.with(call_key: "x").bundle`
   is `equal?` to the original bundle — which is `CTX-2`'s "the same InstrumentationContext reference"
   implemented rather than asserted. All three.
8. **`Hash#[]=` on an existing key does not move it to the end.** `{a:,b:,c:}` with `a` reassigned still
   yields `[:a, :b, :c]`, and `#shift` returns the reassigned `a` first. All three. So an oldest-first drain
   evicts by **first registration**, and a promotion does not refresh its chain's position — legal under
   `CTX-13` and stated because a reader would assume otherwise.
9. **A mutex-guarded counter is exact under contention, and so is the unguarded one on CRuby.** 16 threads ×
   5000 increments produced 80 000 distinct strictly-increasing values with **and without** the mutex on all
   three interpreters. The unguarded form is not observed to lose an update on CRuby, which is precisely why
   an unguarded counter would ship and then fail on JRuby or TruffleRuby — the same argument design §1's safe
   publication rule and phase 3a's P3-6 both turn on. The mutex stays.
10. **Ruby `Integer` does not overflow**, so `CTX-4`'s "monotonically increasing counter" needs no wrap
    handling and no `RECOV-26`-style overflow-safe arithmetic. `2**64 + 1` increments to `2**64 + 2` and stays
    an `Integer` on all three.
11. **`.freeze` beats `String#-@` for a per-call-unique key**, by 1.5×–1.9× over 200 000 renderings — nine
    runs, three per interpreter, spread 1.52×–1.90× with 4.0.6 consistently the widest. The direction is
    stable and the magnitude is machine- and run-dependent, so the ratio is quoted as a range and is not a
    number a plan should assert. Interpolation always yields an unfrozen `String`, so one of the two is
    required; `-@` is the wrong one because it pays a lookup and an entry in a process-global dedup index
    whose only purpose is reuse, and a per-call-unique key by construction deduplicates against nothing.
12. **A frozen `String` is stored as a `Hash` key by identity; an unfrozen one is duplicated and frozen.**
    All three. So freezing the key at mint is not only correctness, it removes a per-registration `String`
    copy.
13. **`Fiber[:k]` is inherited by a child fiber, by a new `Thread` and by an `Enumerator`'s internal fiber;
    `Thread.current[:k]` is visible in none of the three; the inheritance is copy-on-write; and
    `Fiber.new(storage: nil)` opts out entirely.** Re-verified on all three, confirming
    `docs/knowledge/notes/observability.md`. `Fiber#storage=` still warns
    `Fiber#storage= is experimental and may be removed in the future!` on every call on every interpreter and
    `= nil` reads back `{}` on 3.2.11 and `nil` on the other two — `OI-13`, which 4a neither acts on nor is
    blocked by, because nothing in `CTX` touches fiber storage. **The half of `OI-13` that 4a does have to
    stand on is the complement**, and it was verified for that reason: `Fiber[:k] = v` and
    `Fiber.new(storage: …)` emit **no** warning on any of the three under `ruby -w` with
    `RUBYOPT=-W:deprecated`, and only `Fiber#storage=` does. 4a's `Fiber[]` boundary test writes
    `Fiber[:probe]` and runs under `DexpaceTestCase`, which fails a test on any warning the code under test
    raises, so this is the fact that keeps the test green — and it is the fact 4b, phase 5 and phase 8 lose
    the moment they reach for the save/install/restore side, which has no spelling that does not warn.
14. **A module included into a `Data` subclass sits ahead of `Data` in the ancestry** (`[F, Marker, Data]`),
    so `Dexpace::Context` can carry shared behaviour and still reach `Data`'s methods through `super`. The
    **two-level** shape 4a actually uses was run too, because that is the one the design rests on: with
    `Context` including `Model` and each flavour including `Context`, the ancestry is
    `[Flavour, Context, Model, …, Data]` and `Flavour.instance_method(:with).owner` is `Model` — so P1-4's
    `#with` override still beats `Data#with` through two hops, and `#with` on a flavour routes through that
    flavour's `.build` and preserves member identity. `private_class_method :new` plus a public `.build`
    works on a `Data` on all three, and an 8-member `Data` is unremarkable.
15. **A `Data` member holding a `Hash` or `Array` is *not* frozen by the instance's own freeze.** `freeze` is
    shallow, exactly as design §4 says, so `Bundle#trace_state` is deep-frozen by `Model.own` and not by
    `Data`.

## R1 — `CTX-19`'s weak-reference prohibition, resolved

**The decision: a seventh custom cop, `Dexpace/NoWeakReferences`.** Not an extension of an existing one, for
a reason each of the two candidates supplies on its own.

- **`Dexpace/QualifiedCoreConstant` is the wrong tool.** Its rule is *shadowing* and its message is "write
  `::Foo` here"; `CTX-19` is a *prohibition* and its fix is "do not write this at all". Phase 2 kept one
  `SHADOWED` list with one meaning on purpose ("two per-namespace lists would be a second rule to keep in
  step for no gain"), and putting a second, unrelated rule inside the same cop is the same mistake from the
  other side.
- **`Dexpace/NoThreadInterrupt` is the right *shape* and the wrong *name*.** It is a ban list with a stated
  hazard, which is exactly what this is — but the hazard is async interrupts and the cop is named after it.
  Renaming it would edit phase 0's gate table and `.rubocop.yml` for a rule phase 0 never claimed.

Phase 0's five cops and phase 2's sixth each mechanise exactly one named rule and are named after it. The
seventh follows, and `CTX-19` earns its own gate row because it is a MUST with its own conformance clause.

**What it forbids**, over `gems/*/lib/**/*.rb` — every gem, because an adapter is as capable of "helping the
collector" as core is:

1. A constant reference to `ObjectSpace::WeakMap` or `ObjectSpace::WeakKeyMap`, in any of the three written
   forms: `ObjectSpace::WeakMap`, `::ObjectSpace::WeakMap`, and a bare `WeakMap`/`WeakKeyMap` lexically
   inside `module ObjectSpace`.
2. A constant reference to `WeakRef`, bare or `::WeakRef`.
3. `require "weakref"` and `require("weakref")`.

The third is redundant inside `dexpace-core`, where `gates:require_allowlist` already rejects it, and is not
redundant anywhere else: the allowlist covers core's `lib/` alone. It is also the clause that produces a
message naming `CTX-19` instead of a generic allowlist failure, which is the difference between a rule
someone obeys and a rule someone understands.

The message names the requirement and the sanctioned alternative:
`"CTX-19 forbids holding a context by a weak reference; the bounded cap (CTX-11) is the leak backstop."`

**The test, and why the floor is not a problem.** Verified fact 2 is the whole answer: RuboCop parses source
text and never evaluates it, so a rejected-case row is the **string** `"ObjectSpace::WeakKeyMap.new\n"` and
no case in the table names a constant at runtime — nothing is version-conditional and nothing is skipped on
any matrix row. The claim was checked against the parser the suite actually uses and not only against
`RubyVM::AbstractSyntaxTree`: phase 0's `CopCase` builds `RuboCop::ProcessedSource.new(source, TARGET_RUBY,
path)` with `TARGET_RUBY = 3.2`, and on RuboCop 1.90.0 every row below reports `valid_syntax?` true with an
empty `diagnostics`, including the two that name `WeakKeyMap`. It also yields the `const` nodes the cop
matches on — `ObjectSpace::WeakKeyMap`, `::ObjectSpace::WeakKeyMap`, and a bare `WeakMap` under an
`ObjectSpace` node for the lexical row — while the commented-out row yields none, which is the accepted half
working for the right reason rather than by luck.

Rejected rows: `ObjectSpace::WeakMap.new`, `ObjectSpace::WeakKeyMap.new`, `::ObjectSpace::WeakKeyMap.new`,
a bare `WeakMap.new` inside `module ObjectSpace`, `WeakRef.new(ctx)`, `::WeakRef.new(ctx)`,
`require "weakref"`, and — the one that pins the cop to its purpose — `@map = ObjectSpace::WeakKeyMap.new`
inside `module Dexpace; class ContextStore`, which is the exact line the rule exists to stop.

Accepted rows, each producing **no** offense: `ObjectSpace.count_objects`, `ObjectSpace.each_object`,
`ObjectSpace::WeakMap` written inside a comment, a local variable named `weak_map`, a method named
`weak_ref`, a `Hash.new` inside `module Dexpace; class ContextStore`, and `require "set"`. The accepted half
is what proves the cop does not simply reject every occurrence of the substring — the failure phase 2's own
cop had before its namespace check existed.

**The accompanying behavioural test is not the cop, and it is not a tautology — but it catches exactly one of
the two weak maps, and the split is the point.** Verified fact 3: a strong `Hash` returns 1000 of 1000
registered contexts after three `GC.start`s and an `ObjectSpace::WeakMap` returns 0. So
`test_keeps_registered_contexts_reachable_when_the_caller_drops_every_reference` — register 1000 contexts
through the store, drop every local, `GC.start` three times, assert `store.size == 1000` and that a sampled
key still returns a context — **fails outright against `ObjectSpace::WeakMap`** and passes for the shipped
`Hash`. It names no `ObjectSpace` constant, so it runs identically on 3.2.11. The cap is set to 2048 for that
test so the store's own bound does not do the evicting.

**It does *not* fail against `ObjectSpace::WeakKeyMap`, and that is stated rather than assumed.** Verified
fact 3a: the same test returns 1000 of 1000 against a `WeakKeyMap` on 3.4.10 and 4.0.6, because a
`WeakKeyMap` holds its **values** strongly and each stored context strongly holds the very `call_key` object
that is its key — the entry can never become collectable. Two consequences, both wanted. The `CTX-19`
property survives a `WeakKeyMap` swap, so the test is not silently passing over a real defect: contexts
would still be reachable. And the swap is nonetheless forbidden, by the cop and only by the cop — which is
why `@map = ObjectSpace::WeakKeyMap.new` inside `module Dexpace; class ContextStore` is the rejected row the
cop's table pins itself to, and why the two halves are not redundant with each other.

**What the pair does and does not prove.** The cop forbids the three spellings, including the one no runtime
test can see; the test proves the property `CTX-19` is actually about. Neither reaches a *third-party* store
implementation, and nothing in this repository can — `CTX-19` says "reimplementations MUST NOT", and a
reimplementation is by definition outside these gates. That limit is stated in the cop's own comment and
in `ContextStore`'s YARD block rather than papered over.

## R2 — the call key, and what `CTX-5`/`CTX-6`'s inequality costs

**The key is a member of the context `Data`, and that is not a choice 4a makes** — `CTX-5` states it as a
premise ("given that the key participates in value-equality") and derives the inequality from it. What 4a
decides is the type, the counter's home, and how an explicit key is passed.

**The type is a frozen `String`.** `CTX-4`'s reference rendering is `'traceId:spanId:n'`, a string; the
whole reason design §5.4 prefers the prefix over "a bare UUID, which would lose the debuggability the prefix
buys" is a string property; and verified fact 12 says a frozen `String` is stored as a `Hash` key by identity
while an unfrozen one is copied and frozen on every registration. A frozen `Data` key would work and buys
nothing: the key is not a closed set, it has no parse-constructor invariant beyond non-emptiness, and
`type-system/545949a5`'s frozen-`Data`-over-a-frozen-table idiom is for closed domain sets, which this is
the opposite of.

**It is frozen with `#freeze` and never with `String#-@`.** Verified fact 11: `-@` costs roughly 1.5×–1.9×
more and adds an entry to a process-global dedup index whose only purpose is reuse, against a key that by
construction deduplicates against nothing. A per-call-unique identifier is the one case where interning is
strictly a cost.

**The counter lives in `Dexpace::CallKey`, a `private_constant` module of functions, and not on the store.**
`CTX-6` requires distinctness "across the whole process and across all three context flavors" — not across a
store — so a counter on a `ContextStore` instance would mint colliding keys the moment a second store
exists, which the `cap:` keyword makes routine in the suite. One module, one `Thread::Mutex`, one `Integer`,
incremented under the lock and read nowhere else. Verified fact 9 is why the mutex is not optional and
verified fact 10 is why there is no wrap handling.

`CallKey` is `private_constant` because `CTX-4` says outright that "the exact format and the counter
mechanism are a reference choice, and a port MAY key differently" — a generator nothing outside core needs to
name, and `NFR-4` locks every public name at the first release tag. The public surface is
`context.call_key`, a frozen `String`. `data-modeling/b74a2869` and `/ec0f41cb` put it in a module rather
than a class, because its whole interface is one function and it owns no lifecycle.

**`CallKey.mint(bundle)` renders `"#{bundle.trace_id}:#{bundle.span_id}:#{n}".freeze`.** With
`Bundle::NONE` — the shared singleton every untraced call carries — the prefix is constant across the entire
process, which is exactly the condition `CTX-15`'s last clause names, and the suffix is what keeps the key
unique anyway. That is the assertion `CTX-15` is tested by: mint two keys from the *same* `Bundle::NONE`
object and assert they differ.

**An explicit shared key is passed as `call_key:` at construction**, on all three flavours, defaulting to
`nil` and minting when absent. `CTX-5`'s escape hatch is therefore one keyword with a documented default
(`api-design/f1f31d53`) and no second constructor. Validation: when given, it must be a non-empty `String`
and is frozen through `Model.frozen_string`; when absent, `CallKey.mint` supplies one.

**The stated cost, in full, because a caller will meet it.** Two `DispatchContext`s built from the same
`Bundle::NONE` with no explicit key are **not** `==`, are not `eql?`, and do not collide as `Hash` keys —
verified fact 7. That is a documented consequence and not a defect, and 4a asserts both halves: the
inequality, and the equality that a pinned key restores. `#with` inherits it exactly — `Model#with` copies
every member it is not handed, `call_key` included, so `request_ctx.with(request: other)` keeps the key and
a derived context stays equal to a second derivation from the same source. **`#with` is not a promotion and
cannot be used as one**: it reaches only the members its own flavour declares, so `dispatch_ctx.with(request:
r)` raises `ArgumentError: unknown keyword: :request` (verified on all three, for `Data#with` and equally for
`Model#with` routing through `.build`). `#promote_to_request` is the only way to add a request, which is what
keeps `CTX-17`'s registration on the promotion path and off the copy path.

**The one thing the inequality buys, which is easy to miss.** `CTX-9`'s trap is only reproducible because of
it. To evict the wrong sibling you need two contexts that are `==` and not `equal?`; with a minted key that
pair cannot exist, so the test must pin the same explicit key on both — the affordance `CTX-5` requires. The
requirement's escape hatch and the requirement's own regression test are the same mechanism, and the test is
three lines because verified fact 4 already ran it.

## R3 — the `Bundle`'s members, their names, and the phase-5 handshake

`CTX-14` enumerates nine things the bundle must **expose**. §8.1 says core ships
`Dexpace::Instrumentation::Bundle` "as a frozen `Data` with all nine members" and names none of them in Ruby.
4a names them, and one of the nine is exposed without being stored.

### The eight members and the derived ninth

| `CTX-14`'s item | Ruby | Type | `Bundle::NONE`'s value |
|---|---|---|---|
| a trace id | `trace_id` | frozen `String` | 32 hex zeros (`OBS-26`) |
| a span id | `span_id` | frozen `String` | 16 hex zeros (`OBS-26`) |
| trace flags | `trace_flags` | frozen `String`, two lowercase hex chars | `"00"` (`OBS-26`) |
| trace state | `trace_state` | deep-frozen `Array` of frozen `[String, String]` pairs | `[]` (`OBS-26`) |
| a trace-id encoding flavor | `flavour` | `Dexpace::Instrumentation::TraceIdFlavour` | `TraceIdFlavour::NONE` |
| a remoteness flag | `remote` | `true`/`false`, read as `#remote?` | `false` (`CTX-15`) |
| a validity flag | **derived** `#valid?` | `true`/`false` | `false` (`CTX-15`) |
| an active span | `span` | duck type, RBS `_Span` | `Dexpace::Instrumentation::NO_SPAN` |
| a per-operation tracer factory | `tracer_factory` | duck type, RBS `_TracerFactory` | `Dexpace::Instrumentation::NO_TRACER_FACTORY` |

**Validity is derived, and that is P4-6.** `OBS-26` makes it a MUST that "an all-zero trace/span id MUST be
treated as invalid/no-trace", so validity is a *function* of the two identifiers and not an independent fact.
Storing it as a ninth member makes `Bundle.build(trace_id: <real>, span_id: <real>, valid: false)`
representable, and no requirement says what that would mean. `#valid?` is
`flavour.valid_trace_id?(trace_id) && span_id != INVALID_SPAN_ID`. `CTX-14`'s verb is "exposing", which
`#valid?` satisfies exactly; the deviation is from §8.1's word "members", not from the requirement.

**`trace_state` is a list, not a string.** `OBS-26` says "a vendor trace-state list" and W3C `tracestate` is
ordered with the most recent vendor first, so an `Array` of pairs preserves what a `Hash` would lose. It is
the shape `HTTP-28` already gave `Dexpace::Query`, and `Model.own` deep-freezes it once at construction —
verified fact 15 says `Data`'s own freeze would not.

**`trace_flags` stays the two-character wire form.** `OBS-26` fixes it as "a two-hex-char byte" with the
sentinel `'00'`, which is what W3C propagation needs on the wire. A `#sampled?` predicate is *not* shipped:
`CTX-14` does not ask for it, and adding a method later widens the surface, which `NFR-4` permits. **Phase 5
may add it.**

**The flavour governs the trace id only, and the span id is flavour-independent.** `CTX-14`'s own words are
"a trace-**id** encoding flavor", `OBS-27`'s scope is "trace-id generation", and `OBS-26` states the span-id
rule unqualified as "16 lowercase hex chars". So a Datadog-flavoured bundle carries a decimal trace id and a
hex span id. That reads oddly and it is what the two requirements say together; stating it here is what stops
a later reader "fixing" it.

### `TraceIdFlavour`

A frozen `Data` over a frozen table with an `.of` factory, per `type-system/545949a5`, and never a `T::Enum`
— which does not exist here anyway, because `sorbet-runtime` is a dependency `SEAM-1` forbids. Three
members, so the per-flavour behaviour is data rather than a `case`:

`TraceIdFlavour = Data.define(:name, :trace_id_pattern, :invalid_trace_id)`, with
`#valid_trace_id?(trace_id)` returning `trace_id != invalid_trace_id && trace_id_pattern.match?(trace_id)`
and `#renders?(trace_id)` returning `trace_id == invalid_trace_id || trace_id_pattern.match?(trace_id)`,
which is what `Bundle`'s own validation calls.

| Constant | `name` | pattern | `invalid_trace_id` |
|---|---|---|---|
| `TraceIdFlavour::NONE` | `:none` | `\A(?!)\z` — matches nothing, so only the sentinel `#renders?` | 32 hex zeros |
| `TraceIdFlavour::W3C` | `:w3c` | 32 lowercase hex | 32 hex zeros |
| `TraceIdFlavour::DATADOG` | `:datadog` | decimal digits of a 64-bit unsigned | `"0"` |

`TraceIdFlavour.of(name)` resolves a `Symbol` against the frozen table and raises
`Dexpace::InvalidArgumentError` on an unrecognised one — the `Protocol.parse` behaviour of `HTTP-33` and not
the deliberately total `Status.of` behaviour of `HTTP-10`, because a flavour is a closed set and a status
code is not.

**`NONE`'s `invalid_trace_id` is `OBS-26`'s 32 hex zeros and not `"0"`.** `OBS-26` fixes the reserved
sentinels as a single pair of values and `OBS-27` gives the no-op flavour "always yields the invalid
sentinel"; `Bundle::NONE` must carry exactly the pair `CTX-15` names. `DATADOG`'s `"0"` is a different
question — it is that flavour's own zero draw, the one `OBS-27` says "MUST be coerced to a non-zero value" —
and 4a records the split rather than collapsing it (P4-7).

**The pattern inventory is four, and every one is built with `Regexp.new(source, timeout: 1.0)`** —
per-pattern and never `Regexp.timeout`, following phase 1's precedent to the letter rather than arguing that
an anchored character class cannot backtrack. Three are the flavour table's `trace_id_pattern`s above. The
fourth is the span-id pattern `\A[0-9a-f]{16}\z`, held as a `private_constant` in `bundle.rb` — it needs no
public name, adds no `NFR-4` surface, and is flavour-independent for the reason "The flavour governs the
trace id only" above gives: `OBS-26` states the span-id rule unqualified while `OBS-27`'s flavours scope
only the trace id.

**What `Bundle.build` validates, stated once so the plan does not have to infer it.** `trace_id` must
`flavour.renders?` — the sentinel or a value the flavour's pattern accepts. `span_id` must match the span-id
pattern; `OBS-26` makes "16 lowercase hex chars" a MUST and nothing else in 4a would enforce it,
since `#valid?` only compares against `INVALID_SPAN_ID` and would return `true` for a malformed one.
`trace_flags` must be two lowercase hex characters. `trace_state` must be an `Array` of two-element
`String` pairs. Each failure raises `Dexpace::InvalidArgumentError` naming the field (`SEAM-29`).

### The two no-op singletons, and the exact line phase 5 may not cross

**Phase 4 fixes the members, their names, their duck-typed slots, and the identity of the two objects that
fill them. It does not fix the span or tracer protocols**, which are `OBS-21`–`OBS-25` and phase 5's.

- `Dexpace::Instrumentation::NO_SPAN` — one frozen instance of a `private_constant` class, responding to
  nothing beyond `Object`'s own surface. It exists so `Bundle::NONE.span` is a stable object a conformance
  test can assert by identity, which is what `OBS-25`'s "Selecting a no-op path MUST NOT allocate per call"
  requires of a test.
- `Dexpace::Instrumentation::NO_TRACER_FACTORY` — one frozen instance, and it is **not** empty, because
  `CTX-20`'s embedded MUST forbids that: "Its factory method MUST be safe to invoke concurrently from
  multiple threads." A factory with no factory method cannot satisfy a MUST about that method. It defines
  exactly one, `#tracer(name = nil, version = nil)`, returning one shared frozen `NO_TRACER`
  (`private_constant`). It holds no state, so concurrency safety is structural and the test asserts it by
  identity across threads rather than by argument.

`#tracer`'s **name and positional arity are the ecosystem's, not this repository's**, and that is P4-8.
§8.1 fixes core's tracing as "a structural subset of the `Tracer`/`Span` shape of `opentelemetry-api`" so
that "an application already running OpenTelemetry gets spans with no adapter code" — a property that is only
real if an application can pass `OpenTelemetry.tracer_provider` straight into `Bundle.build(tracer_factory:)`.
That requires this repository's factory duck type to be call-compatible with OTel's, which is positional.
`api-design/1d9e6e0b` asks for keywords on every public method and is deviated from here for the same class
of reason phase 3a's P3-9 carved out the host-native bridge: being call-compatible with a foreign object is
the method's entire purpose. **The exact arity is an open question for 4a's plan** — this document could not
install `opentelemetry-api` to read it — and the plan confirms it against the gem's own source before the
signature is locked.

### The handshake, stated so phase 5 can implement against it

1. **Phase 5 populates through `Bundle.build` or `Bundle::NONE.with(...)`.** `Model#with` routes through the
   validating `.build` on every supported Ruby (P1-4), so a populated bundle is validated the same way a
   constructed one is. Phase 5 defines **no second bundle type** and no second constructor.
2. **Phase 5 may add methods to `Bundle` and to `TraceIdFlavour`** — `#sampled?`, and `OBS-27`'s trace-id
   *generation*, which naturally belongs on the flavour that defines the rendering. Adding a method widens
   the surface, which `NFR-4`'s "disappears or narrows" lock permits.
3. **Phase 5 may add methods to `NO_SPAN`'s and `NO_TRACER`'s classes** — those classes are
   `private_constant`, so they are not `NFR-4`-locked at all, and the *objects* phase 4 published by identity
   keep their identity. `OBS-25`'s "a no-op Tracer returning a shared no-op Span, a no-op Span whose
   current-scope is a cached singleton" is implemented by giving these two classes their methods, not by
   introducing a third pair. `DEF-37` records this so a phase-5 planner meets it in the register.
4. **Phase 5 may not** rename a member, remove one, change `#valid?` from derived to stored, change the
   sentinels, replace `TraceIdFlavour` with a `Symbol`, or hand `Bundle` a second `NONE`. Roadmap obligation
   1's second half is the whole of that list. **The question the list does not answer, answered here because
   it is the first one a phase-5 planner will ask: adding a `Data` *member* is redefinition and is not
   permitted**, even though it widens rather than narrows and `NFR-4` would allow it — a new member changes
   `Data`'s generated `==`, `hash` and `to_h`, and with them the `Bundle.build(**bundle.to_h) == bundle`
   round trip and every `Bundle::NONE` comparison already written. Clause 2's permission is for methods and
   only methods. Checked rather than assumed: `OBS-21`–`OBS-27` were read in full and **not one of the seven
   needs a field the eight members do not already carry** — `OBS-21`, `OBS-22` and `OBS-23` are span, scope
   and diagnostic-context requirements that touch no bundle field, `OBS-24` is the async snapshot, and
   `OBS-25`–`OBS-27` are the sentinels, the flavours and the no-op path this document already fixes. If a
   later requirement does need one, it is a new `P4`-numbered deviation and a roadmap amendment, not a
   phase-5 decision.
5. **`SEAM-28`'s operation identifier is not the bundle's.** It is `CTX-16`'s `operation_name` on the
   `RequestContext`, already shipped, and `DEF-1` names phase 5 as the phase that has both halves.

## R4 — `CTX-11`'s bounded map, resolved

**The decision: `Dexpace::BoundedMap`, a `private_constant` class on `Dexpace`.** Not a public constant, not
a module function.

**Why a class and not a module function.** §5.4 says the store shares "one implementation with `XCUT-14`'s
general bounded-map rule and with `AUTH-19`'s per-nonce counter store", and `XCUT-14`'s auditable unit is the
*map* — "every process/instance-lived map whose key space is influenced by callers or remote servers MUST be
bounded by a hard cap and MUST drain back under the cap after each insert using a loop". A module function
`drain!(hash, cap:)` would share three lines and leave each consumer to own the hash, the mutex and the
decision to call it, which is precisely the drift the shared implementation exists to prevent.
`data-modeling/3e37c086` puts state-owning behaviour in a class.

**Why `private_constant` and not public.** Verified fact 6 is the decisive one: a `private_constant` on
`Dexpace` **is** reachable by a bare unqualified reference from `module Dexpace; module Auth` and from
`module Dexpace; module Conformance` at any depth, so phase 6's `AUTH-19` store and phase 9's `XCUT-14` audit
can both use it. Verified: that holds for a file in **any** gem, because the reachability is lexical and a
gem boundary is not a lexical one — so neither consumer's gem membership is load-bearing, and neither is
constrained to `dexpace-core` by this decision. What *is* load-bearing is that both name the map from inside
a `module Dexpace; …` body. **No consumer outside this repository's own `Dexpace` namespace needs the map**,
so the risk the charter names — "a `private_constant` is invisible to a consumer's
`steep check`" — has no case to bite: `CTX-11`'s and `XCUT-14`'s conformance is about the *store's*
observable behaviour, asserted through `Dexpace::ContextStore`, not through the map. And `Module#constants`
excludes it (verified fact 6), so it takes no surface-manifest row, no `sig/` mirror and no YARD gate entry —
phase 2's `Dexpace::Hooks` precedent (P2-15) applied unchanged.

**The condition, which is the corpus note above.** The bare-name reachability holds only under
`module-organization/64e84d64`'s full nesting form; the compact `module Dexpace::Auth` raises `NameError`,
and so does a *qualified* `Dexpace::BoundedMap` written from inside `Dexpace`. Both are stated in the
constant's own comment, so phase 6 meets a documented condition rather than a puzzle.

**The contrast with `NO_SPAN`, which is decided the other way, and the reason it is *not* "a different
gem".** `NO_SPAN` and `NO_TRACER_FACTORY` are **public**, and the tempting reason is wrong: gem boundaries
have nothing to do with constant privacy. Verified on all three — a file in *any* gem that writes
`module Dexpace; module Conformance` in the full nesting form reaches a `private_constant` on `Dexpace` by a
bare name exactly as a core file does, because lexical scope is per **file**, not per gem. What actually
decides it is the *shape of the reference the assertion has to write*. `OBS-25`'s "MUST NOT allocate per
call" is a reference-identity claim, and the way a conformance suite makes it is
`assert_same Dexpace::Instrumentation::NO_SPAN, bundle.span` — a **qualified** reference, which verified
fact 6 shows raises `NameError: private constant … referenced` against a private constant *even from inside
`Dexpace`*. `BoundedMap` is only ever named from inside a `module Dexpace; …` body, where a bare name works;
`NO_SPAN` has to survive being named from an assertion line, where it does not. The two decisions differ
because the reference forms differ, not because the rule does and not because the gems do.

**The surface 4a ships on it, and the surface it does not.** YAGNI applies and a `private_constant` is not
`NFR-4`-locked, so 4a ships only what `CTX` needs: `#initialize(cap:)`, `#set(key, value)`,
`#put(key, value) -> bool`, `#[](key)`, `#delete_if_identical(key, object) -> bool` and `#size`. **Phase 6
adds `#update(key) { |old| new }` for `AUTH-19`'s counter increment** — an addition to *this* map, which is
what keeps "one implementation" true, and not a second map. The block that operation runs executes while the
map's mutex is held, so it must touch only in-memory state (`concurrency-and-async/f261a143`); that
constraint is written into the method's comment when phase 6 adds it, and is recorded here so phase 6 does
not discover it.

**`#delete_if_identical` is named for its mechanism and not for `CTX-9`**, because `AUTH-19` will never call
it and a general map should not carry a context-shaped name. It uses `equal?`, and the reason is in its
comment.

**The cap, and the loop.** `Dexpace::ContextStore::MAX_TRACKED_CONTEXTS = 1024`. `CTX-11` and `XCUT-14` name
no number; `AUTH-19` names 1024 as the default for a store of exactly this shape, and it is the only number
the specification gives for one. Using a second would make the "one implementation" claim visibly
two-valued (P4-9). `ContextStore.new(cap: MAX_TRACKED_CONTEXTS)` is how a test gets a cap of 3 and how phase
5 will later reach it from configuration (`DEF-36`).

The drain is `@h.shift while @h.size > @cap`, inside the same `synchronize` as the insert. It is written as a
loop because **`XCUT-14` makes it a MUST** — "MUST drain back under the cap after each insert using a loop
(not a single pre-insert check-then-evict)" — with `CTX-12` asking for the same thing as a SHOULD and
`CTX-11` requiring only the draining. What the loop actually does here is run at most once per insert, and
that is an argument rather than a measurement: one key is added per critical section and the loop's entry
invariant is `size ≤ cap`, so `size ≤ cap + 1` at the top. Verified fact 5 records both the discriminating
measurement and the vacuous one it replaces. The corpus note above is where that lands so a later reader does
not infer that the loop makes the mutex removable.

**The victim policy and its stated consequence.** `Hash#shift` removes the oldest **first registration** —
and verified fact 8 says `Hash#[]=` on an existing key does not move it, so a chain's slot does not refresh
when a promotion overwrites it. Oldest-first is what `CTX-13` explicitly permits ("A port MAY choose a
smarter (e.g. oldest-first) victim policy"), and the non-refresh is legal for the same reason. What
`CTX-13` forbids is *relying* on any entry surviving, and 4a obeys it structurally: **nothing in core reads a
context back out of the store**. Promotion writes and returns; `#close` conditionally removes and tolerates
absence. `#[]` exists for `CTX-18` and for the suite, and core calls it nowhere.

## Module layout

Every file 4a creates, under `gems/dexpace-core/`, except the two at the repository root. `sig/` mirrors
`lib/` one file per file and ships inside the gem; `test/` mirrors `lib/` one file per file and does not
ship.

```
lib/dexpace.rb                                   MODIFIED: explicit requires for the tree below
lib/dexpace/error/context_conflict_error.rb      Dexpace::ContextConflictError
lib/dexpace/bounded_map.rb                       Dexpace::BoundedMap                    (private_constant)
lib/dexpace/context.rb                           Dexpace::Context                       (module)
lib/dexpace/context/call_key.rb                  Dexpace::CallKey                       (private_constant)
lib/dexpace/context/dispatch_context.rb          Dexpace::DispatchContext
lib/dexpace/context/request_context.rb           Dexpace::RequestContext
lib/dexpace/context/exchange_context.rb          Dexpace::ExchangeContext
lib/dexpace/context_store.rb                     Dexpace::ContextStore
lib/dexpace/instrumentation/trace_id_flavour.rb  Dexpace::Instrumentation::TraceIdFlavour
lib/dexpace/instrumentation/no_span.rb           Dexpace::Instrumentation::NO_SPAN
lib/dexpace/instrumentation/no_tracer.rb         Dexpace::Instrumentation::NO_TRACER_FACTORY, ::NO_TRACER
lib/dexpace/instrumentation/bundle.rb            Dexpace::Instrumentation::Bundle

test/support/fake_context.rb                     the one double, required explicitly
```

```
.rubocop/cops/dexpace/no_weak_references.rb      the seventh custom cop
.rubocop/test/cops_test.rb                       MODIFIED: the seventh cop's cases
.rubocop.yml                                     MODIFIED: the require: list and the cop's Include:
```

Twelve new `lib/` files, **ten** `sig/` mirrors and **ten** `test/` mirrors — `bounded_map.rb` and
`context/call_key.rb` are `private_constant`s and get neither, per P2-15, and their behaviour is asserted at
their call sites, which is the treatment phase 2 gave `Dexpace::Hooks` — one test-support file, one cop with
its cases, and three already-existing files that gain content: `lib/dexpace.rb`, `sig/dexpace.rbs` and the
repository-root `test/fixtures/surface/dexpace-core.txt`.

**The placement rule is phase 1's and is applied, not re-decided** (P1-1, `module-organization/6e69ad04`): a
public constant the design names without a namespace is flat and its file sits under a directory that
organises rather than namespaces — `Dexpace::ContextConflictError` in `lib/dexpace/error/`, the three
contexts in `lib/dexpace/context/`, `Dexpace::ContextStore` at `lib/dexpace/context_store.rb` exactly as
phase 2 put `Dexpace::AsyncTransport` at `lib/dexpace/async_transport.rb`. A subsystem the design already
names with a namespace keeps it — `Dexpace::Instrumentation::Bundle` is §8.1's own name, so the whole
instrumentation subsystem is namespaced.

`lib/dexpace/instrumentation/no_tracer.rb` defines two constants — plus the two `private_constant` classes
behind them — because the second, `NO_TRACER`, is what the first returns and is named in no other file. That
is **not literally** `module-organization/1828a984`'s sanctioned exception, which is "a class-level private
struct or `Data.define` used nowhere but that file"; it is the same reasoning one step out, and it is
recorded as a stretch rather than as a citation so a reader who checks the rule does not find it saying
something else. Splitting the pair across two files would put a `private_constant` in one file and its only
reference in another, which the full-nesting reachability of verified fact 6 permits and which buys nothing.

## The object model 4a ships

Every public constant, its surface, and the IDs forcing that shape.

### `Dexpace::Context` — the module the three flavours share

Design §5.4 requires "three distinct `Data` classes **sharing a module**", so that `CTX-1`'s "the exchange
stage is terminal — no method promoting back" is enforced by the absence of a method rather than by a guard
clause. 4a reads "sharing a module" as **a module the three include**, not a namespace containing them, for
the reason P4-1 records: `Dexpace::Context::Request` would shadow `Dexpace::Request` for every file inside
`module Dexpace; module Context`, which is the exact hazard `Dexpace/QualifiedCoreConstant` exists for and
which that cop cannot express a fix for (its message is "write `::Foo`", and `::Request` is not what a
reader should write). It is also the shape phase 1 already used twice — `Dexpace::Error` and
`Dexpace::Model` are modules included by flat classes.

`Dexpace::Context` includes `Dexpace::Model`, so every flavour gets `Model.required!`, `Model.own`,
`Model.frozen_string` and the validating `#with` by inclusion. Verified fact 14 confirms a module included
into a `Data` subclass sits ahead of `Data` in the ancestry.

It carries one method:

- **`#close`** — `store.release(self)`. `CTX-9`, `CTX-10` and `CTX-18` in one line, because every clause of
  all three is a property of `ContextStore#release`: identity-conditional removal, a no-op for a promoted
  intermediate whose slot now holds its successor, and a no-op for an unknown or already-removed key.
  Idempotent without a latch (P4-4).

`ctx.is_a?(Dexpace::Context)` is true for all three flavours, which is what the store's RBS types against and
what the test double includes.

### The `store` member, and the one `Data`-generated method it makes expensive

Every flavour carries `store` as a `Data` member so `#close` needs no argument and no ambient lookup, and
`CTX-9`'s identity eviction has an unambiguous target. `Data` generates `==`, `eql?`, `hash`, `to_h` and
`inspect` over every member, and for `store` the first four are harmless: `ContextStore` defines neither
`==` nor `hash`, so both fall through to identity, which is what two contexts sharing one process-wide store
want. Equality also means a pinned `call_key` restores value-equality only between contexts built against
the **same** store object — true by default, since `.build` defaults `store: ContextStore.default`, and true
in the suite, where each case passes one `ContextStore.new(cap:)` to both sides.

**`#inspect` is the exception, and it is stated rather than discovered.** Verified on all three: `#inspect`
on a registered context walks `store` into the map and prints one level of *every other* occupant, each with
its own request and response, and Ruby's recursion guard only replaces the second visit to the store itself
with `...` — a cap-8 store of five-member contexts holding two short strings each already renders 1 125
characters on 3.2.11 and 1 141 on the other two from a single `ctx.inspect`. At
`MAX_TRACKED_CONTEXTS = 1024` and real `Request`/`Response` graphs, any `p ctx`, any `assert_equal` failure
message and any message that interpolates a context becomes a dump of every in-flight call. 4a does **not** override `#inspect`: phase 1 shipped no `#inspect` override on `Request` or `Response`
either, and a redaction-aware rendering is `OBS-11`–`OBS-19`'s and `XCUT-19`'s, which are phase 5's. What 4a
owes is that no assertion in its own suite compares whole contexts where a member comparison would do — the
`CTX-2` cases already use `assert_same` on the carried-forward members for a different reason — and a YARD
note on `Dexpace::Context` saying why, so phase 5 meets a stated consequence when it writes the redactor
rather than reading it out of a 40 KB test failure.

### `Dexpace::DispatchContext` — `CTX-1`, `CTX-2`, `CTX-5`, `CTX-17`

`Data.define(:bundle, :call_key, :store)`, `private_class_method :new`, plus:

- **`.build(bundle:, call_key: nil, store: ContextStore.default)`** — `CTX-5`'s off-chain construction with
  its explicit-key affordance and its minting default. **Construction registers nothing** (`CTX-17`).
- **`#promote_to_request(request:, operation_name: nil)` → `RequestContext`** — builds the successor
  carrying the **same** `bundle` object, the **same** `call_key` and the **same** `store` (`CTX-2`,
  `CTX-3`), adds the one artefact, introduces the operation name as an argument exactly as `CTX-2` says, and
  **registers the successor** with `store.set` before returning it. That call is the first store entry a
  chain ever has (`CTX-17`).
- No reverse promotion exists anywhere in the model (`CTX-1`).

### `Dexpace::RequestContext` — `CTX-2`, `CTX-16`

`Data.define(:bundle, :call_key, :store, :request, :operation_name)`, `private_class_method :new`, plus:

- **`.build(bundle:, request:, operation_name: nil, call_key: nil, store: ContextStore.default)`** —
  off-chain construction, registering nothing.
- **`#promote_to_exchange(response:)` → `ExchangeContext`** — carries `bundle`, `call_key`, `store`,
  `request` and `operation_name` forward unchanged (`CTX-2`'s "additionally the same request and
  operationName"), adds the response, and calls `store.set`, which overwrites the same slot (`CTX-3`).

`operation_name` is `nil` or a non-empty frozen `String`. An empty `String` is rejected with
`Dexpace::InvalidArgumentError`, because `CTX-16` gives exactly two states — "a schema-defined operation id
such as 'GetUser', or absent" — and `""` is neither. It is **advisory only**: it reaches no request, no
dispatch decision and, decisively, **not the store key**, which `CallKey.mint` derives from the bundle and
the counter alone. That is asserted rather than argued (below).

### `Dexpace::ExchangeContext` — `CTX-1`, `CTX-2`

`Data.define(:bundle, :call_key, :store, :request, :operation_name, :response)`,
`private_class_method :new`, `.build(...)`, and **no promotion method at all**. `CTX-1`'s terminality is the
absence, which is the property design §5.4 chose three classes to get.

### `Dexpace::ContextStore` — `CTX-7`, `CTX-8`, `CTX-9`, `CTX-10`, `CTX-11`, `CTX-12`, `CTX-13`, `CTX-18`, `CTX-19`

A class, because it owns state (`data-modeling/3e37c086`). It **has** a `BoundedMap` rather than **being**
one, so `CTX-8`'s and `CTX-18`'s two-operation surface is what a caller sees and the map's general operations
are not part of it.

| Member | Requirement |
|---|---|
| `MAX_TRACKED_CONTEXTS = 1024` | `CTX-11`, and `AUTH-19`'s stated default for the same shape (P4-9) |
| `.default` | the one process-wide instance, assigned at file load into a class-level ivar. **Not** a constant: `data-modeling/6accaff9` requires a mutable constant to be frozen at assignment, and a live store cannot be |
| `.new(cap: MAX_TRACKED_CONTEXTS)` | what gives every test a fresh, small store (`testing/4ef070df`) and what phase 5's configuration will reach (`DEF-36`) |
| `#set(context) -> context` | `CTX-8`'s unconditional overwrite. Never raises. Used by both promotions and by nothing else |
| `#put(context) -> context` | `CTX-8`'s reject-on-duplicate insert. Raises `Dexpace::ContextConflictError` naming the key. **The conflict is detected under the map's mutex and the error is raised after it is released**, per `concurrency-and-async/f261a143` |
| `#[](call_key) -> Context?` | `CTX-18`'s explicit absent result. `nil` is legitimate here because the requirement demands it and forbids raising, which is the documented case `api-design/6ea28c9c` reserves |
| `#release(context) -> bool` | `CTX-9`'s identity-conditional eviction, `CTX-10`'s intermediate no-op and `CTX-18`'s unknown-key no-op. Returns whether a slot was cleared, which is how `CTX-10` is observable |
| `#size -> Integer` | how `CTX-11`'s bound is asserted |

`#set` and `#put` take a **context**, not a key/value pair, and read `#call_key` off it. That is the narrowest
duck type the operation actually uses (`api-design/88e6bf12`), it makes `CTX-3`'s "all three flavors register
under the identical store slot" unforgeable at the call site, and it is what lets the suite drive every store
rule with a two-field fake instead of a `Bundle`, a `Request` and a `Response`.

**Contexts are validated at construction to respond to `#set` and `#release`** — the two methods a context
calls on its store — rather than to be a `Dexpace::ContextStore`. Narrowest duck type again, and it is what
keeps the fake cheap.

### `Dexpace::ContextConflictError` — `CTX-8`

`< ::StandardError`, `include Dexpace::Error`, matching phase 2's three. It carries `#call_key` and its
message names the key, which is `CTX-8`'s own words ("an error whose message identifies the key") and what
`testing/62f8f4ec` requires a negative test to assert. It is not `Dexpace::InvalidArgumentError`: the caller
passed nothing invalid, it lost a race, and a caller that cannot tell those apart cannot retry correctly.

### `Dexpace::Instrumentation::Bundle`, `::TraceIdFlavour`, `::NO_SPAN`, `::NO_TRACER_FACTORY`

R3 above, in full. `Bundle` is a `Data` including `Dexpace::Model`, `private_class_method :new`, with
`.build` requiring `trace_id:`, `span_id:` and `flavour:` and defaulting `trace_flags: "00"`,
`trace_state: []`, `remote: false`, `span: NO_SPAN`, `tracer_factory: NO_TRACER_FACTORY`.

**The three required keywords are required deliberately.** Defaulting them would make "I forgot to pass a
trace id" produce a silently untraced bundle, which is invisible for exactly the reason `CTX-15` names — every
untraced call's identifiers are identical, so nothing downstream can tell an accident from a policy. A caller
who wants the untraced value names `Bundle::NONE` and gets the shared object `OBS-25` requires.

**The same choice is made one level up, and `CTX-15`'s word "default" is why it needs saying.** `bundle:` is
**required** on `DispatchContext.build`, `RequestContext.build` and `ExchangeContext.build`; no context
builder defaults it to `Bundle::NONE`. `CTX-15` requires the no-op bundle to "be available as the default",
which `Bundle::NONE` satisfies — it exists, it is the shared frozen singleton §8.1 names, and it is what an
untraced call carries. What `CTX-15` does not require is that a context *silently acquire* it, and
defaulting `bundle:` would reintroduce exactly the invisibility the paragraph above rejects, one caller
further out: an untraced chain and a chain whose tracing was dropped by accident would be indistinguishable
at the construction site as well as downstream. Naming `Bundle::NONE` costs one argument and makes the
untraced case a decision.

`Bundle::INVALID_SPAN_ID = "0" * 16` is public and frozen; the trace-id sentinel lives on the flavour,
because it is the one of the two that varies.

### The RBS interfaces

`interface _Span end` and `interface _Tracer end` are declared **empty** — phase 4 fixes the slots, phase 5
fixes the protocols, and an empty interface says that in the type system rather than in a comment.
`interface _TracerFactory` declares `#tracer` alone. Declaring them as interfaces rather than typing the two
members `untyped` keeps `NFR-11` mechanical: no constant outside `Dexpace::` appears in any public signature.
They are 4a's constants for `NFR-4` purposes and carry a ledger row.

## The spec-forced boundaries, honoured

Six of the charter's sixteen bind 4a; each is honoured by a named mechanism rather than by intent.

1. **`CTX-9`'s identity eviction** — "the one place a Ruby port is actively likely to go wrong" (§5.4).
   `ContextStore#release` calls `BoundedMap#delete_if_identical`, which uses `equal?`. Verified fact 4 is the
   test, and R2 explains why the test is constructible at all.
2. **`CTX-17`'s registration-at-promotion** — no `.build` on any flavour touches the store. The two
   `#promote_*` methods are the only callers of `#set` in core.
3. **`CTX-19`'s prohibition on weak references** — R1's cop plus R1's reachability test. 4a decides the
   lint's shape; it does not decide whether the prohibition holds.
4. **`CTX-14`/`CTX-15`'s bundle shape is fixed in phase 4 and only in phase 4** — R3, with the five-clause
   handshake and `DEF-37`. The boundary's own words are "Nine members, a frozen `NONE` singleton, `OBS-26`'s
   reserved sentinels as its values, `CTX-20`'s no-op tracer factory", and **4a departs from the first of the
   four**: nine things are exposed, eight are stored, and validity is derived. That is `P4-6`, which names
   this boundary as well as design §8.1. The other three are honoured verbatim.
5. **`CTX-13`'s arbitrary-victim latitude taken as-is** — oldest-registration-first, with the non-refresh
   consequence stated and with nothing in core reading a context back out of the store.
6. **Phase 1's construction rule** — `private_class_method :new`, a validating `.build`, validation in
   `initialize`, `#with` routed through `.build`, and no `.build` that is a bare `new` wrapper. Every `Data`
   4a ships is public API, so P2-9's `private_constant` exemption does not apply to any of them.

## Cross-cutting constraints that bite 4a specifically

1. **`Fiber[:key]` is the diagnostic-context carrier and `CTX`'s store is not it.** Verified fact 13
   re-confirms the inheritance asymmetry; `docs/knowledge/notes/observability.md` draws the line. `CTX-7`
   and `CTX-11` require a process-wide store that is thread-safe across distinct keys **and bounded**, and
   `CTX-19` requires reachability — putting it in fiber storage would defeat the cap and the reachability
   requirement at once, and would make a context invisible to the thread that has to close it. 4a asserts
   the boundary in one test rather than restating it in prose.
2. **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden**, enforced by phase 0's
   `Dexpace/NoThreadInterrupt`. 4a starts no thread and interrupts none; the constraint has nothing to bite
   on here, and it is named so that nobody reaches for an interrupt to bound a drain.
3. **Deadlines are explicit values, never ambient interrupts.** 4a has no deadline, no clock and no wait.
   `CTX-4`'s counter is a **sequence** counter and shares nothing with `CFG-16`'s elapsed-time monotonic
   counter but the adjective — `OI-15` records that collision, because the charter's own exclusions table
   assigns "the monotonic counter" to phase 5 and a 4a reader could take that to mean this one.
4. **`Thread::Mutex` is per-fiber-owned and non-reentrant** (`concurrency-and-async/f414b864`). Two mutexes
   exist in 4a — one inside `BoundedMap`, one inside `CallKey` — and neither is ever held across a callback,
   a drain of anything but its own hash, a close, or any suspension point. `BoundedMap` never yields to
   caller code in 4a; when phase 6 adds `#update`, the block it runs is documented as in-memory-only for
   this reason. No 4a code path acquires both mutexes, so no lock order exists to get wrong.
5. **An `Enumerator` abandoned mid-`#next` never runs its `ensure`** (`pagination/b2a85752`). 4a yields no
   block that holds a resource and returns no enumerator. `ContextStore` exposes no iteration at all: `#size`
   is the only aggregate read, which is what `CTX-13`'s "MUST NOT rely on any specific entry surviving" wants
   anyway.
6. **The bundled-gem rule.** 4a requires nothing; see the phase-0 prerequisites.
7. **`Ractor` is never load-bearing.** Every `Data` here is frozen and `Bundle`'s collections are deep-frozen
   by `Model.own`, so a `Bundle` is shareable as a free side effect. **No shareability claim is made for a
   context**, because it holds a `Response` holding a body holding an `IO`, and holds a live `ContextStore`
   besides — `data-modeling/5bc538ba` and P1-9 already narrow the claim and 4a narrows it no further.
8. **`XCUT-15`'s no-alias rule** reaches `Bundle#trace_state`, which is the only caller-supplied mutable
   collection 4a ingests. `Model.own` — `Ractor.make_shareable(collection, copy: true)` — deep-copies then
   deep-freezes, leaving the caller's array untouched, which is what verified fact 15 says `Data`'s own
   freeze would not do.

## Testing strategy

`test/` mirrors `lib/` one file per file; each file's header comment names the requirement IDs it exercises
and a non-obvious branch names the ID that forced it. Every suite subclasses `DexpaceTestCase`, so a warning
raised by code under test fails the test that triggered it.

**No transport, no socket, no stream.** Roadmap cross-cutting constraint 4 puts phases 1 through 7 on an
in-memory fake transport; 4a touches no transport at all, so the constraint is satisfied trivially and phase
2's `SEAM-11`/`SEAM-16` fakes are not required. Nothing in 4a performs I/O, which is what makes every
concurrency test here deterministic.

**One double, and it is a fake.** `gems/dexpace-core/test/support/fake_context.rb` defines `FakeContext`:
`include Dexpace::Context`, an `attr_reader :call_key` and `:store`, and nothing else. It exists because
every store rule — `CTX-7` through `CTX-13`, `CTX-18`, `CTX-19` — is about a keyed occupant and about
nothing else, and driving them through a real chain would mean building a `Bundle`, a `Request` and a
`Response` per case and would couple the store's suite to three other types' constructors. It gets `#close`
free from the module, which is what makes the `CTX-9`/`CTX-10` cases readable. It is named `Fake*` and not
`Mock*` per `testing/630ba094`, and it is a fake by `testing/7ecef8e8`'s definition: a real in-memory
implementation of an owned interface, not a recorder of calls. `DEF-29`'s condition — a consumer outside
`dexpace-core` — stays unmet; this strengthens the row without meeting it.

The promotion rules — `CTX-1`–`CTX-3`, `CTX-16`, `CTX-17` — are tested against **real** contexts with a
`ContextStore.new(cap: …)` passed explicitly, never `ContextStore.default`. No test in 4a touches the
process-wide store, which is what makes `testing/4ef070df`'s "every test must run alone, in any order" true
of this suite rather than aspirational.

**The tests a reader would otherwise write wrong.**

- **`CTX-9`'s eviction, three lines and one trap.** Build two contexts with the **same pinned `call_key`** so
  they are `==` and not `equal?` — the only way the pair exists, per R2. `set` the first, `release` the
  second, assert the slot is untouched and `#release` returned `false`; then `release` the first and assert
  it is gone. A test that used two default-constructed contexts would pass against a `==`-based
  implementation, because their keys differ and the value comparison would never fire.
- **`CTX-5`/`CTX-6`'s inequality, both halves.** Two `DispatchContext.build(bundle: Bundle::NONE)` are not
  `==`; two with the same `call_key:` are `==`, `eql?` and hash-equal. And — the assertion `CTX-6` is
  actually about — a `DispatchContext`, a `RequestContext` and an `ExchangeContext` all built from
  `Bundle::NONE` with no explicit key get three distinct keys, because one counter serves all three flavours.
- **`CTX-15`'s non-trivial half.** Mint two keys from the **same** `Bundle::NONE` object — asserted
  `equal?`, not merely `==` — and assert the keys differ. This is the test that would fail if the key were
  ever derived from the bundle.
- **`CTX-2`'s carried-forward identity.** Assert `promoted.bundle.equal?(source.bundle)` and
  `promoted.call_key.equal?(source.call_key)` — **`assert_same`, never `assert_equal`**. `CTX-2` says "the
  same InstrumentationContext reference", and value equality would pass against an implementation that
  rebuilt the bundle. Assert the source is unchanged in the same test, which is the requirement's own
  conformance step.
- **`CTX-16`'s advisory rule, asserted as a negative.** Build two `RequestContext`s from the same
  `DispatchContext` — one promoted with an operation name and one without — and assert the two keys are
  identical, the two requests are the same object, and the store slot is the same. A positive test that the
  name is carried forward proves nothing about the three things `CTX-16` forbids it from influencing.
- **`CTX-8`'s race.** 32 threads released from one `::Thread::Queue` barrier onto one key: exactly one
  winner, 31 `Dexpace::ContextConflictError`s, and every message contains the key. Verified fact-shaped —
  the prototype produced 1/31 on all three interpreters — so this is a test of the shipped code and not a
  hope. `testing/80c44c7f` requires the raised object to be asserted on, not rescued and ignored.
- **`CTX-7`'s concurrency.** 16 threads × 1000 distinct keys into a store with a cap above 16 000: final
  size exactly 16 000. The prototype's number on all three.
- **`CTX-11`/`CTX-12`/`XCUT-14`'s bound, and the assertion that is not the obvious one.** 16 threads ×
  500 inserts, cap 64: final size exactly 64 — the concurrency half. The drain half is **not** an assertion
  on the aggregate iteration count, which is `inserts − final size` for any correct drain and would pass
  against a split-lock implementation and against no loop at all (verified fact 5). It is a single-threaded
  assertion that **no one call runs the drain body twice** and that the map is never observed above `cap`,
  which is what the corpus note claims and what would change if the mutex's scope ever narrowed.
- **`CTX-13`'s two obligations, one of them negative.** Assert the documented policy — with cap 3, inserting
  a fourth distinct key evicts the **first-registered**, and a promotion on an existing key does **not**
  refresh its position (verified fact 8). And assert that nothing in the store's own behaviour depends on an
  entry surviving: `#release` on an evicted context returns `false` and raises nothing, which is `CTX-18`'s
  clause and `CTX-13`'s constraint meeting.
- **`CTX-19`'s reachability**, R1 above: 1000 registered contexts, every local reference dropped, three
  `GC.start`s, `store.size == 1000` and a sampled key still resolving. A discriminator against
  `ObjectSpace::WeakMap` and not a tautology (verified fact 3), and **not** a discriminator against
  `ObjectSpace::WeakKeyMap`, which passes it (verified fact 3a) — the cop is what covers that spelling, and
  the test's comment says so rather than implying a reach it does not have.
- **The `Fiber[]` boundary, asserted once.** A context registered on the main fiber is found by
  `store[key]` from inside a child `Fiber`, from inside a new `::Thread`, and from inside an `Enumerator`'s
  internal fiber. The same test asserts, as its setup guard, that `Fiber[:probe]` **is** visible in all three
  and `Thread.current[:probe]` is **not** — which is what establishes that the three really are distinct
  execution contexts and that the store's visibility is not an artefact of them being the same one. Without
  that guard the store half proves nothing; with it, it proves the store is process-wide and not
  fiber-scoped, which is the line `docs/knowledge/notes/observability.md` draws.
- **`CTX-20`'s concurrency.** `NO_TRACER_FACTORY.tracer` called from 16 threads returns the same object 16
  times (`assert_same`), which is `OBS-25`'s allocation clause and `CTX-20`'s thread-safety clause in one
  assertion, and is true because the factory holds no state.
- **`CTX-18`'s double close.** `ctx.close` twice on a registered context, `ctx.close` on a never-promoted
  dispatch context (`CTX-17`'s "harmless no-op"), and `ctx.close` on a promoted intermediate (`CTX-10`) —
  three cases, none raising, each asserting the store's state afterwards. `testing/26b866e1` forbids
  `assert_nothing_raised`, so each asserts the resulting state instead.

**Property tests.** `testing/f36a19cd` makes round-trip property tests mandatory for "any value object with
parse-constructor invariants", which reaches `TraceIdFlavour.of` and `Bundle.build`: a bounded, seeded
generator over the three flavours and over valid and invalid identifier renderings, asserting that `.of`
round-trips its `name`, that `#renders?(x) == (#valid_trace_id?(x) || x == invalid_trace_id)` for every
generated `x`, and that `Bundle.build(**bundle.to_h) == bundle` for every generated bundle. **The second is
written that way because the two predicates always disagree at exactly one input and agree everywhere
else** — read off the two definitions above, `#renders?` is `true` at the flavour's own sentinel where
`#valid_trace_id?` is `false`, which is the whole reason both exist. "They never disagree about the
sentinel" would be the one property that is false by construction, and a generator asserting it would fail
on its first draw. Iteration counts are fixed and the seed
is pinned and logged (`testing/7ece0212`, `/7b383289`).

**The cop suite** gains the seventh cop's rows in phase 0's existing table, run through `bundle exec rake
cops:test`. Per phase 2's precedent, the cop is executed against phase 0's verbatim `CopCase` harness during
the phase and the version it was run on is stated, because `VERSIONS` pins a RuboCop the design cannot know.

## The interface surface 4b and 4c may cite

**The load-bearing statement here is a negative one, and it is the charter's central finding.** Nothing in
`RECOV` or `PIPE` consumes anything in `CTX`: outside ch.07 and appendix C the token `CTX-<n>` appears in no
specification chapter, and in no design section outside §5.4, §8.1, §11.11 and §12 bar one `CTX-9`
*comparison* in §5.2 that reads nothing from it. **4b and 4c are not obliged to consume any of this**, and a
4b or 4c plan whose first task waits on a 4a artefact has re-imposed a chain that does not exist.

What 4a nonetheless ships as a stable contract, so that a later phase cites rather than re-derives:

| Consumer | What it gets, and when |
|---|---|
| **4b**, optionally | `Dexpace::ContextConflictError` as the fourth member of the phase-2 error shape, if 4b wants a precedent for a conflict-class error. Nothing else. `RECOV-11`'s "current context" is phase 2's `Dexpace::Cancellation`, not this |
| **4c**, optionally | `Dexpace::BoundedMap` — if `PIPE`'s per-call cursor ever needs a bounded keyed map, it uses this one and declares no second. `PIPE-11`'s cursor-scoped state is not a `CTX` artefact and 4c owns its shape |
| **Phase 5**, obligatorily | `Dexpace::Instrumentation::Bundle` with its eight members, `Bundle::NONE`, `Bundle::INVALID_SPAN_ID`, `TraceIdFlavour` with its three constants and `.of`, `NO_SPAN`, `NO_TRACER_FACTORY` and `#tracer`, and the RBS interfaces `_Span`, `_Tracer`, `_TracerFactory`. The five-clause handshake in R3 is the contract; `DEF-37` is its register row |
| **Phase 5**, obligatorily | `RequestContext#operation_name` and `ExchangeContext#operation_name` — `DEF-1`'s first half for `SEAM-28`, already carried and already advisory |
| **Phase 5**, on `DEF-36` | `ContextStore.new(cap:)` and `ContextStore::MAX_TRACKED_CONTEXTS`, which is where a configuration source attaches |
| **Phase 6**, on `AUTH-19` | `Dexpace::BoundedMap`, reached by a bare unqualified name from `module Dexpace; module …` in the full nesting form, with `#update` added to it rather than a second map written |
| **Phase 9**, on `XCUT-14` | The same map, as the single implementation the audit checks; and `ContextStore` as the one `CTX-11` instance of it |
| **Phase 9**, on `XCUT-11` | `ContextStore` as the audited shared-instance state: one `Thread::Mutex`, no per-call state on the instance |

## Deviation Ledger

Each row is consolidated into design §10 and audited by `docs/deviations.md`. Numbering starts at `P4-1`;
the phase-4 segmentation design left the ledger empty.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P4-1 | The three context flavours are flat — `Dexpace::DispatchContext`, `Dexpace::RequestContext`, `Dexpace::ExchangeContext` — and "sharing a module" (§5.4) is read as **a module they include**, `Dexpace::Context`, not a namespace containing them | design §5.4; P1-1; phase 3a's P3-7 | `Dexpace::Context::Request` would shadow phase 1's `Dexpace::Request` for every file inside `module Dexpace; module Context`, and `Dexpace::Context::Request#request` returns a `Dexpace::Request` — the two are one line apart. That is exactly the hazard `Dexpace/QualifiedCoreConstant` exists for, and the cop cannot express the fix: its message is "write `::Foo`", and `::Request` is wrong. The alternative — adding `Request` and `Response` to `SHADOWED` under the now repository-wide `WATCHED` — would flag every legitimate bare `Request` in core. The included-module reading is also what phase 1 already did twice, with `Dexpace::Error` and `Dexpace::Model` |
| P4-2 | Public constants design §5.4 does not name: `Dexpace::Context`, `Dexpace::DispatchContext`, `Dexpace::RequestContext`, `Dexpace::ExchangeContext`, `Dexpace::ContextStore`, `Dexpace::ContextStore::MAX_TRACKED_CONTEXTS`, `Dexpace::ContextConflictError`, `Dexpace::Instrumentation`, `Dexpace::Instrumentation::TraceIdFlavour` with `NONE`/`W3C`/`DATADOG`, `Dexpace::Instrumentation::NO_SPAN`, `Dexpace::Instrumentation::NO_TRACER_FACTORY`, `Dexpace::Instrumentation::Bundle::INVALID_SPAN_ID`, and the RBS interfaces `_Span`, `_Tracer`, `_TracerFactory` | `NFR-4`; `api-design/b0e18938`; phase 2's P2-11 and phase 3a's P3-8 precedent | `NFR-4` locks every public signature at the first release tag, so a name that arrives by accident is locked by accident. §5.4 describes the model and names no Ruby constant for any of it; §8.1 names only `Dexpace::Instrumentation::Bundle` and `Bundle::NONE`. Each name above is chosen on purpose and its reason is in this document's object-model section |
| P4-3 | `Dexpace::BoundedMap` and `Dexpace::CallKey` are `private_constant`, with no `sig/` mirror, no YARD gate entry and no surface-manifest row | design §5.4's "one implementation"; `CTX-4`; P2-15 | Verified: a `private_constant` on `Dexpace` is bare-name reachable from every full-nesting descendant and from nothing else, and `Module#constants` excludes it. Phase 6's `AUTH-19` store and phase 9's `XCUT-14` audit are both `dexpace-core` code, so the sharing works; no consumer outside this repository's namespace needs either, and `CTX-4` says outright that the key format and the counter mechanism "are a reference choice". The condition — `module-organization/64e84d64`'s full nesting form, never the compact one — is in the constants' own comments and in a corpus note |
| P4-4 | A context is **not** a `Dexpace::Closeable`; it has `#close` and no latch, no `#closed?` and no block form | phase 2's `Closeable`; `CTX-9`, `CTX-10`, `CTX-18`; `resource-management/bf5560dc` | Verified on all three: a method on a frozen `Data` writing an ivar raises `FrozenError`, so `Closeable`'s latch cannot be included into a context. It is not needed: `CTX-9`'s eviction is conditional on reference identity, so a second close finds a different occupant or none and is already the well-defined no-op `CTX-18` requires. The block form is separately wrong here rather than merely absent — the object that must be closed is the **furthest-reached link**, which does not exist when the head is constructed, so a block on `DispatchContext.build` would close the head (a `CTX-10` no-op) and leak the exchange context that actually holds the slot |
| P4-5 | The styleguide's block-form resource rule is recorded as not reaching this subsystem rather than as a conflict | `resource-management/bf5560dc`; phase 3a's P3-10 precedent | A rule that does not reach a case is a ledger row, not a corpus note; a note records what an implementation found a rule to get *wrong*. The reason is P4-4's second half and it is specific to a promotion chain, not general to value objects |
| P4-6 | `Bundle` stores **eight** members and exposes `CTX-14`'s ninth, validity, as a derived `#valid?` | `CTX-14`, `OBS-26`; design §8.1's "all nine members"; **the charter's spec-forced boundary 14 and its `R3`, both of which say "nine members"** | `OBS-26` makes it a MUST that an all-zero trace/span id is treated as invalid, so validity is a function of two members already present. Storing it makes `Bundle.build(trace_id: <real>, span_id: <real>, valid: false)` representable and no requirement says what it would mean. `CTX-14`'s verb is "exposing", which the predicate satisfies, and §8.1's own enumeration already writes the item as the predicate `valid? == false` alongside `remote? == false` — so the deviation is from the word "members" in three documents, not from the requirement any of them is restating. Named against the charter as well as the design because boundary 14 is on the list the charter declares "not open to `4a`, `4b` or `4c`", and a departure from a closed list has to be visible in the ledger rather than only in a section heading. Roadmap obligation 1, which is what boundary 14 is enforcing, fixes that phase 4 ships the shape and phase 5 may not redefine it, and states no count. `#remote?` is a predicate over the stored `remote` for symmetry of reading |
| P4-7 | The reserved invalid **trace id** is a property of `TraceIdFlavour` and not a single constant; the invalid **span id** is a single constant | `OBS-26`, `OBS-27`; `CTX-15` | The two requirements are only consistent if the sentinel varies with the flavour: `OBS-26` fixes it as 32 hex zeros while `OBS-27`'s Datadog flavour renders a trace id as a decimal string, in which 32 hex zeros is not expressible and `"0"` is the zero draw `OBS-27` forbids generating. `TraceIdFlavour::NONE`'s sentinel is `OBS-26`'s exact value, so `Bundle::NONE` carries the pair `CTX-15` names verbatim. The span id needs no such split: `OBS-26` states its rule unqualified and `OBS-27`'s scope is trace ids |
| P4-8 | `NO_TRACER_FACTORY#tracer(name = nil, version = nil)` is **positional**, against the keywords-everywhere rule | `CTX-20`; design §8.1; `api-design/1d9e6e0b`; phase 3a's P3-9 precedent | §8.1 fixes core's tracing as a structural subset of `opentelemetry-api`'s shape so "an application already running OpenTelemetry gets spans with no adapter code" — which is only true if `OpenTelemetry.tracer_provider` can be passed straight into `Bundle.build(tracer_factory:)`, and that requires call compatibility with a foreign object's positional signature. The same exception phase 3a made for the host-native `IO` bridge, for the same reason: being call-compatible is the method's entire purpose. The exact arity is confirmed against the gem in 4a's plan |
| P4-9 | `ContextStore::MAX_TRACKED_CONTEXTS = 1024`, a number no `CTX` requirement gives | `CTX-11`, `XCUT-14`, `AUTH-19`; design §10.18's substituted-constant precedent | Neither `CTX-11` nor `XCUT-14` names a cap. `AUTH-19` names 1024 as the default for a bounded store of exactly this shape, and it is the only number the specification supplies for one; §5.4 requires the two to share one implementation, and giving one shared implementation two different default bounds would make the claim visibly two-valued. The value is a keyword with a documented default, not a hard-coded literal, so `DEF-36` can attach a configuration source without changing a signature |
| P4-10 | A seventh custom cop, `Dexpace/NoWeakReferences` | `CTX-19`; design §5.4's "forbidden by lint"; phase 0's P0-3 and phase 2's P2-8 precedent | §5.4 makes `CTX-19` a lint rule and does not say which. Extending `Dexpace/QualifiedCoreConstant` would put a prohibition inside a shadowing cop whose message ("write `::Foo`") is the wrong fix; extending `Dexpace/NoThreadInterrupt` would put an unrelated hazard behind a name that states a different one. Every cop in this repository mechanises one named rule and is named after it. It scopes to `gems/*/lib/**/*.rb` because `gates:require_allowlist` covers core alone and an adapter can hold a context too |
| P4-11 | Public **methods** neither design §5.4 nor §8.1 names: `Context#close`; `DispatchContext#promote_to_request` and `RequestContext#promote_to_exchange`; `ContextStore.default`, `#set`, `#put`, `#[]`, `#release` and `#size`; `ContextConflictError#call_key`; `Bundle#valid?` and `#remote?`; `TraceIdFlavour.of`, `#valid_trace_id?` and `#renders?`; and `NO_TRACER_FACTORY#tracer` | `NFR-4`; `api-design/b0e18938`; phase 2's P2-11 and phase 3a's P3-8, both of which cover methods as well as constants | `NFR-4` locks a public *signature*, not only a public name, and §5.4 describes the whole promotion chain and the store without naming a single Ruby method — so every verb above is 4a's invention and is locked at the first release tag. `P4-2` covers the constants; this row is its other half, filed separately because the precedents it stands on filed both. Each name is chosen for a stated reason in the object-model section, and two deserve naming here because they are the ones a later reader will question. **`#put` and `#[]` have no caller anywhere in core** — `CTX-8` requires the reject-on-duplicate insert as "a separate strict-register affordance" and `CTX-18` requires the explicit absent lookup, so both are surface a requirement forces and only the suite exercises; deleting them later would be an `NFR-4` break for a method core never used, which is exactly the kind of accident this row exists to make deliberate. **`#promote_to_request`/`#promote_to_exchange` name the target stage rather than the source**, so `CTX-1`'s one-way chain reads off the call site. The `Data`-generated readers on all five value types — the three contexts, `Bundle` and `TraceIdFlavour` — are public API too and are invisible to `rbs validate`; the runtime surface snapshot is what holds them, which is the pairing `CLAUDE.md` requires and the phase's last task regenerates |

## Deferrals Filed by Phase 4a

Filed against `docs/deferred-items.md`; each row names an explicit target or pick-up condition, per the
roadmap's execution step 7. (The heading avoids the literal words the housekeeping probe's `registers` check
reserves for the aggregate register, which is where the rows live.)

| ID | Deferral | Target / condition |
|---|---|---|
| `DEF-36` | A configuration source for `Dexpace::ContextStore`'s cap. 4a ships `MAX_TRACKED_CONTEXTS = 1024`, the `cap:` keyword that reaches it, and one process-wide store built with the default; what it does not ship is any way for an application to change the process-wide store's bound, because the configuration chain does not exist. `CTX-11` requires a bound and names no number, so a fixed 1024 is conforming; an application running many thousands of concurrent calls would nonetheless want to raise it | Phase 5, with `CFG-1`–`CFG-38`. The attachment point already exists — `ContextStore.new(cap:)` — so this widens nothing and breaks no signature. The same shape as `DEF-34`, which defers the configuration source for phase 3b's body-logging caps |
| `DEF-37` | The no-op span and tracer protocols behind `Dexpace::Instrumentation::NO_SPAN`, `NO_TRACER` and `NO_TRACER_FACTORY`. 4a ships three frozen singletons and exactly one method — `#tracer(name = nil, version = nil)`, which `CTX-20`'s embedded MUST forces — because `OBS-21`–`OBS-25` are phase 5's. `NO_SPAN` responds to nothing beyond `Object`'s surface, and the RBS interfaces `_Span` and `_Tracer` are declared empty on purpose | Phase 5, with `OBS-25`. The classes behind all three singletons are `private_constant` and therefore not `NFR-4`-locked, so phase 5 adds methods to them and the objects keep the identity phase 4 published. Phase 5 may **not** introduce a second no-op span or tracer, replace either singleton, or give `Bundle` a second `NONE` — roadmap obligation 1 |

### Deferral-register sweep

The roadmap's execution step 1 requires the phase to read the **whole** register and disposition every row.
All thirty-five were read; the charter's own sweep covered the phase-4-wide dispositions and is not repeated,
so what follows is the 4a-specific delta.

- **`DEF-1` — untouched, and 4a supplies the half it names.** "`SEAM-28` targets phase 5 … the request's
  context chain (`CTX`, phase 4) for 'attached to the request's context chain' … and phase 5 is the first
  phase that has both." 4a ships `RequestContext#operation_name` and `ExchangeContext#operation_name`, which
  is the chain half. The row is not edited: its condition names phase 5 and 4a cannot meet it.
- **`DEF-24`, `DEF-27`, `DEF-32`, `DEF-5` — 4b's, not 4a's.** The charter assigns all four to 4b and 4b
  performs the register edits. 4a touches none of them: it raises no error that carries a suppressed trail,
  and `close_quietly` gains no call site here.
- **`DEF-28` — untouched, and named as a constraint.** 4a has no clock, no deadline and no wait. Recorded
  because its text names "the monotonic counter", which is not `CTX-4`'s (`OI-15`).
- **`DEF-29` — untouched.** `FakeContext` lands under `gems/dexpace-core/test/support/`, following phase 2's
  and phase 3's precedent. The condition — a consumer outside `dexpace-core` — is not met.
- **`DEF-30`, `DEF-31`, `DEF-34` — untouched.** All three target phase 5's instrumentation facade and
  configuration chain. `DEF-36` is filed beside `DEF-34` and for the same reason.
- **`DEF-33` — untouched, and worth one sentence.** Its condition is a non-CRuby matrix row, and 4a is a
  second phase whose concurrency guarantees rest on a `Thread::Mutex` that the GVL would hide the absence of
  (verified fact 9). The row is not widened; it is noted that its value has grown.
- **`DEF-35` — untouched.** Filed by the charter; `RECOV`, phase 6.
- **`DEF-2`, `DEF-3`, `DEF-4`, `DEF-6`–`DEF-23`, `DEF-25`, `DEF-26` — untouched.** Other prefixes, other
  phases, or already picked up. None names phase 4 or a condition 4a can meet.

### The findings filed against `docs/open-items.md`

**`OI-15` — "the monotonic counter" names two unrelated objects in two committed documents, and the
phase-4 segmentation design's exclusions table assigns the phrase to phase 5.** `CTX-4` requires "a
process-wide, monotonically increasing counter" appended to the key rendering — an integer sequence, phase
4's, with no notion of time. `CFG-16` requires "a monotonic elapsed-time counter" on the time seam — phase
5's, deferred by `DEF-28`. The charter's exclusions table reads "`CFG-15`–`CFG-21` — the clock, the
monotonic counter, the interruptible sleep, `future.value(deadline:)` — 5 (`DEF-28`)", and a 4a reader who
takes that row at face value concludes the counter `CTX-4` needs is not theirs to build. It is. Filed rather
than fixed because the charter is committed and reviewed and a finding against a committed phase is a
register row, not an edit. It is the same family as `OI-14`: a cross-reference that reads correctly and
resolves to the wrong thing, with nothing mechanically checking it — and here the collision is a *word*
rather than a path, which is the one variant of the four `OI-14`'s proposed link-and-citation check would
not catch.

**`OI-16` — the corpus CLI prints `[overridden by notes/…]` for every key a note backticks, including the
rules the note explicitly adopts.** Filed by this document's own review, because this phase's note is one of
the two that trip it. `Corpus#link_overrides` has a single relation and derives it from a bare backticked
key anywhere in a note's text, so `docs/knowledge/notes/execution-context.md`'s citation of
`api-design/b0e18938` and `module-organization/64e84d64` — both rules the note *rests on* — now marks them
overridden in every query result that returns them, and the same is already true of
`concurrency-and-async/c0fab747`, `/ee54cb68` and `/f261a143` under a committed note whose own sentence says
it does not weaken them. 77 of 2 166 harvested entries carry the marker today; the other notes' markers were
spot-checked and are genuine multi-key supersedes. The citations are not removed here: the fix is a tool or
convention change, and stripping one note's citations would break the citation rule for that note alone
while the committed note kept doing it.

## Open questions for 4a's own plan

Four, each bounded, none reopening a decision above.

1. **`#tracer`'s exact arity in `opentelemetry-api`.** P4-8 fixes the method name and the positional shape
   from §8.1's structural-subset rule; this document could not install the gem to read the signature.
   Recommendation: `#tracer(name = nil, version = nil)`, confirmed against the gem's own source before the
   signature is locked, and both arguments ignored by the no-op. If the real signature differs, **the gem's
   wins** — the whole point of the positional form is call compatibility, so matching it is the requirement
   and not a preference.
2. **Whether `Dexpace::BoundedMap` needs an RBS signature for Steep's sake even though it ships none.**
   Phase 2 shipped `Dexpace::Hooks` as a `private_constant` with no `sig/` mirror and reported
   `rake rbs:validate steep` green with three call sites in `core`-target files, so the pattern is
   established. Recommendation: follow it exactly and confirm on the first task that touches
   `ContextStore`; if Steep does report a diagnostic in a `core`-target file, fix the signature or the code
   and **never relax the target**, which is phase 2's own standing instruction.
3. **Whether the `CTX-19` reachability test runs on every matrix row.** It allocates 1000 small objects and
   calls `GC.start` three times. Recommendation: yes, on every row — it is the only test that would catch a
   weak map, the cop cannot catch a third-party one, and the cost is milliseconds. The plan states the cost
   either way.
4. **Where `FakeContext` is required from.** Phase 2's precedent is an explicit `require_relative` in each
   suite that uses it and never from `test_helper.rb`. Recommendation: follow it; the store suite and the
   `CTX-9`/`CTX-10`/`CTX-13` cases are the only users, and a context suite that accidentally tested the fake
   instead of a real chain would be a silent hole in `CTX-1`–`CTX-3`.
