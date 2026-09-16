# Phase 4a — Execution Context: Checklist

**Written at execution time, 2026-09-16, from what was built** — not from the plan. A row whose task
did not do what the plan said is a row that says so, and the "Deviations from the plan" section
below is where each departure is stated with its reason. The plan and design were written on
2026-09-08 against phases 0–3's *plans*; phases 1, 2, 3a and 3b were then built and merged to
`main` (2026-09-14 to 2026-09-16), each with departures of its own, and where the two disagree
the built tree wins and this document records it.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase4/phase4a/2026-09-08-phase4a-execution-context.md`. Task numbers are that
plan's. Design: `docs/work/mvp/phase4/phase4a/2026-09-08-phase4a-execution-context-design.md`, whose
Deviation Ledger rows `P4-n` are cited below; the charter is
`docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md`. Every test file named here is
under `gems/dexpace-core/test/`, mirrors its `lib/` file one for one, and opens with the IDs it
exercises.

## Requirement rows

Twenty rows, `CTX-1`–`CTX-20` — the design's whole disposition table, every one implemented and
tested, none deferred, none not built, none N/A. Two IDs outside `CTX` fix values this phase is the
first to carry and are named in the rows that carry them: `OBS-26`'s reserved sentinels and
`OBS-27`'s trace-id flavours. Both keep their own rows in phase 5; nothing here claims them.

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `CTX-1` | MUST | ✅ | 2, 7 | Three flat `Data` classes sharing one included module (P4-1): `Dexpace::DispatchContext#promote_to_request` and `Dexpace::RequestContext#promote_to_exchange` are the only two promotion methods in core, and `Dexpace::ExchangeContext` defines no `#promote_*` at all — the terminality is the absence, asserted over `public_instance_methods` (`dexpace/context/exchange_context_test.rb`; the two `#promote_to_dispatch` refutations in `dispatch_context_test.rb` and `request_context_test.rb`) |
| `CTX-2` | MUST | ✅ | 7 | Each promotion builds a NEW instance through the successor's `.build` and never touches the source; the bundle, the call key and the store are carried forward **by identity** (`assert_same`, never `assert_equal` — the guard that rebuilds the bundle runs red below), the request and the operation name likewise on the second hop, and exactly one artefact is added; the operation name enters as an argument to the first promotion and is absent from the head (`refute_respond_to`) (`dispatch_context_test.rb`, `PromotionTest`; `request_context_test.rb`) |
| `CTX-3` | MUST | ✅ | 7 | One key per chain: a promotion carries `call_key` forward verbatim, so `store.size` stays 1 across both hops and the slot's occupant is the furthest link (`request_context_test.rb`, "CTX-3"); the guard that mints a fresh key on the second hop runs red below |
| `CTX-4` | MUST | ✅ | 7 | `Dexpace::CallKey.mint(bundle)` (a `private_constant`) renders `"#{trace_id}:#{span_id}:#{n}"` with a process-wide counter under one `::Thread::Mutex`, frozen with `#freeze`; the shape, the strictly increasing suffix, the frozen-on-both-paths property (minted and pinned, the caller's String never aliased) and 4000 concurrent mints without a collision are asserted (`dispatch_context_test.rb`; `ConstructionTest`) |
| `CTX-5` | MUST | ✅ | 7 | `.build(call_key: nil)` on all three flavours mints when absent and pins when given; two default-constructed contexts from one bundle are not `==`, not `eql?`, hash apart and occupy two `Hash` slots, and a shared explicit key restores all three (`dispatch_context_test.rb`; `request_context_test.rb`, `ConstructionTest`) |
| `CTX-6` | MUST | ✅ | 7 | One counter serves every flavour and every store: nine contexts built round-robin across the three flavours carry nine strictly increasing suffixes spanning exactly eight — the assertion a per-flavour counter fails where a mere distinctness check does not (the guard was seen to survive the weaker test and is caught by this one, below); two stores never share a minted key (`dispatch_context_test.rb`) |
| `CTX-7` | MUST | ✅ | 3, 7 | Every flavour and `Bundle` are frozen on construction (the immutability half); `Dexpace::ContextStore` over the `private_constant` `Dexpace::BoundedMap` — a `Hash` behind one `::Thread::Mutex` — takes 16 threads × 1000 distinct keys and loses nothing, and the whole store suite joins every thread it starts, which `DexpaceTestCase` asserts (`context_store_test.rb`, `ConcurrencyTest`; `dispatch_context_test.rb`, `PromotionTest`) |
| `CTX-8` | MUST | ✅ | 1, 3 | `#set` is install-or-replace and never raises; `#put` installs only if absent and raises `Dexpace::ContextConflictError`, the fourth error in phase 2's shape, carrying `#call_key` and a message naming the key; 32 threads released from one `::Thread::Queue` onto one key admit exactly one winner and 31 losers each asserting the key in both the member and the message, with the conflict detected under the map's mutex and raised after it (`error/context_conflict_error_test.rb`; `context_store_test.rb` and its `ConcurrencyTest`) |
| `CTX-9` | MUST | ✅ | 3, 7 | `ContextStore#release` → `BoundedMap#delete_if_identical`, which uses `equal?` and never `==`. THE trap, written the only way it can be: two `DispatchContext`s with the same pinned key are `==` and not `equal?`; releasing the sibling returns false and leaves the occupant, releasing the occupant clears it. The `==` substitution runs red below on 4.0.6 and 3.2.11 (`context_store_test.rb`, first case) |
| `CTX-10` | MUST | ✅ | 2, 3, 7 | Closing a promoted intermediate is a no-op observable as `false`, the successor keeps the slot — driven through the fake at the store and through a real chain (`context_store_test.rb`; `request_context_test.rb`, "CTX-10"; `context_test.rb`) |
| `CTX-11` | MUST | ✅ | 3 | `ContextStore::MAX_TRACKED_CONTEXTS = 1024` (P4-9), `ContextStore.new(cap:)` for a test or for phase 5a's configuration source, the cap validated as a positive Integer (a negative one would spin the drain forever on an empty hash); 2000 inserts into a default store leave 1024, and 16 threads × 500 into a cap of 64 leave 64 (`context_store_test.rb`, `BoundTest`) |
| `CTX-12` | SHOULD | ✅ | 3 | The post-insert drain loop, inside the same `synchronize` as the insert, on `#set` and on `#put` both; the discriminating single-threaded assertion — from a store at cap every further insert evicts exactly one and the size is never observed above cap — plus the note that the aggregate iteration count proves nothing. The two-per-insert and the deleted-drain guards run red below; the split-lock overshoot is unobservable through the public surface and stays with `docs/first-release.md`'s `IO-38` trigger (`context_store_test.rb`, `BoundTest`) |
| `CTX-13` | MAY | ✅ | 3, 7 | Oldest-first taken as-is, with its consequence asserted: at cap 3 a fourth key evicts the first-registered, and re-setting an existing key does not refresh its position (verified fact 8) — driven through `ContextStore#set` on the fake **and** through a real promotion, three chains at the request stage and one promoted to exchange before the fourth arrives, which is the case a release-then-set promotion fails (guard 19 below); nothing in the store's own behaviour depends on any entry surviving — `#release` on an evicted context is `false` and raises nothing, on the fake and on both links of the evicted real chain; the store exposes no iteration (`context_store_test.rb`, `BoundTest`) |
| `CTX-14` | MUST | ✅ | 4, 5, 6 | `Dexpace::Instrumentation::Bundle`, a frozen `Data` of exactly eight members — `trace_id`, `span_id`, `trace_flags`, `trace_state`, `flavour`, `remote`, `span`, `tracer_factory` — asserted as the member list in that order, with `#valid?` derived (P4-6) and `#remote?` beside the reader; `TraceIdFlavour` fills the flavour slot, `NO_SPAN` and `NO_TRACER_FACTORY` the two duck-typed ones (`instrumentation/bundle_test.rb`) |
| `CTX-15` | MUST | ✅ | 4, 5, 6, 7 | `Bundle::NONE`: `OBS-26`'s 32 hex zeros, 16 hex zeros, `"00"`, `[]`, `TraceIdFlavour::NONE`, `valid?` and `remote?` both false, `NO_SPAN` and `NO_TRACER_FACTORY` by identity, frozen, shared; the non-trivial half — two contexts minted from the **same** `NONE` object (`assert_same`) still get distinct keys, and the guard that derives the key from the bundle runs red (`bundle_test.rb`; `dispatch_context_test.rb`, "CTX-15") |
| `CTX-16` | SHOULD | ✅ | 7 | `RequestContext#operation_name` and `ExchangeContext#operation_name`: nil or a non-empty frozen String (an empty one is refused off-chain and at promotion), carried forward by identity, and asserted advisory **as a negative** — a named and an unnamed promotion from two heads with one pinned key share the key, the request object and the slot; the guard that folds the name into the key runs red (`request_context_test.rb`, `OperationNameTest`; `exchange_context_test.rb`) |
| `CTX-17` | MUST | ✅ | 7 | No `.build` touches the store: `store.size` is 0 after construction of every flavour, a never-promoted head closes as `false`, and the first promotion is the first entry the chain ever has; the guard that registers at construction runs red (`dispatch_context_test.rb`, `PromotionTest`; `request_context_test.rb` and `exchange_context_test.rb`, `ConstructionTest`) |
| `CTX-18` | MUST | ✅ | 2, 3, 7 | `ContextStore#[]` answers nil for an unknown key and raises nothing; `#release` on a never-registered, an evicted and an already-released context is `false`; `#close` twice on a registered exchange context evicts once; `Context#close` has no latch (P4-4) — a frozen `Data` cannot carry one — and is idempotent through the store (`context_store_test.rb`; `exchange_context_test.rb`; `context_test.rb`) |
| `CTX-19` | MUST | ✅ | 3, 7, 8 | The store is a strong `Hash`: 1000 registered contexts survive three `GC.start`s with every local dropped (a discriminator against `ObjectSpace::WeakMap` — the swap runs red below on 4.0.6 and 3.2.11 — and, stated, not against `WeakKeyMap`); a real `Request` and a real `Response` with a `ResponseBody` stay readable through the store after GC until `#close`; and `Dexpace/NoWeakReferences`, the eighth custom cop (P4-10), forbids the three spellings over every gem's `lib/`, with fourteen rejected and fifteen accepted sources in its own nested table and a gate test pinning its scope (`context_store_test.rb`, `ReachabilityTest`; `exchange_context_test.rb`; `.rubocop/test/cops_test.rb`, `NoWeakReferencesTest`; `test/gates/rubocop_config_test.rb`) |
| `CTX-20` | SHOULD | ✅ | 5 | `NO_TRACER_FACTORY#tracer` mirrors `opentelemetry-api` 1.11.0's `TracerProvider#tracer` parameter list exactly — `(deprecated_name = nil, deprecated_version = nil, name: nil, version: nil, attributes: nil)`, re-read from the gem at implementation (P4-8) — asserted as the parameter list and as the call shapes; 16 threads calling it get the same `NO_TRACER` (`assert_same`), which is the embedded MUST and `OBS-25`'s allocation clause in one; the per-call-allocation guard runs red (`instrumentation/no_tracer_test.rb`; `no_span_test.rb`) |

## What was built

Twelve new `lib/` files under `gems/dexpace-core/lib/dexpace/` — exactly the design's Module
Layout: `error/context_conflict_error.rb`, `context.rb` (the module the three flavours include,
carrying `#close` and the private `#validate_context!`), `bounded_map.rb` (`private_constant`),
`context_store.rb`, `instrumentation/trace_id_flavour.rb`, `instrumentation/no_span.rb`,
`instrumentation/no_tracer.rb` (two constants, two private classes), `instrumentation/bundle.rb`,
`context/call_key.rb` (`private_constant`), `context/dispatch_context.rb`,
`context/request_context.rb` and `context/exchange_context.rb` — **every one with a `sig/` mirror**,
the two private constants included (deviation 3 below), and ten with a `test/` mirror: the two
private constants have none, as `hooks.rb` has none, and their behaviour is asserted at their call
sites. One fake, `test/support/fake_context.rb`, required explicitly by exactly the two suites that
use it. One `lib/` file changed as the design said: the entry file gains the twelve
`require_relative`s as one block, in the plan's Task 9 order. The eighth custom cop,
`.rubocop/cops/dexpace/no_weak_references.rb`, with its cases in a nested class of
`.rubocop/test/cops_test.rb` and its `require:` line and scope in `.rubocop.yml`. Two files a gate
reads at run time gained content: the runtime surface manifest `test/fixtures/surface/dexpace-core.txt`
grew from 515 to 580 lines through `rake surface:regenerate`, run once, with every one of the 65
added rows read against the design's object model — the five value types' `Data` readers included,
which the shipped walker holds (finding 3 below) — and nothing removed; and the core smoke suite's
constant list gained the seven public constants beside the two private ones it asserts unreachable.
One gate suite gained a test: `test/gates/rubocop_config_test.rb` pins the new cop's `require:`
line, its enablement and its every-gem scope.

The public surface, all of it new and `NFR-4`-locked at the first tag (P4-2, P4-11): seven flat
constants — `Dexpace::Context`, `ContextConflictError`, `ContextStore` with `MAX_TRACKED_CONTEXTS`,
`DispatchContext`, `RequestContext`, `ExchangeContext` — and the namespaced instrumentation
subsystem `Dexpace::Instrumentation` with `Bundle` (`NONE`, `INVALID_SPAN_ID`), `TraceIdFlavour`
(`NONE`, `W3C`, `DATADOG`, `ALL`), `NO_SPAN`, `NO_TRACER` and `NO_TRACER_FACTORY`; the RBS
interfaces `_Span` and `_Tracer` (empty, on purpose), `_TracerFactory` (one method) and
`_ContextHost` (deviation 4); and the methods P4-11 lists, with one fewer than the plan wrote:
`Context.validate!` is not public (deviation 5).

The whole test surface is value objects, one synchronised hash and Ruby's three execution
carriers; no transport, no socket, no stream beyond the one `ResponseBody` the `CTX-19` end-to-end
case builds. Nothing was added to the require allowlist: the phase requires nothing but
`require_relative`, and `gates:require_allowlist` reports clean.

## Guards run red

Every guard the brief asks to be seen red was seen red, on 4.0.6, and restored; the two the brief
names for the floor were run on 3.2.11 as well. Eighteen single-edit mutations were run against
the finished suites — the thirteen the brief lists, plus five more for the clauses whose test the
design's testing strategy singles out (`CTX-3`, `CTX-16`, `CTX-17`, the all-zero trace id, and
the drain on `#put`). **Seventeen were caught on the first run and one was not**: the per-flavour
counter survived the plan's `CTX-6` case, which asserts only that three keys are distinct — a
counter per flavour yields three distinct keys too, whenever the shared counter has already moved
past the per-flavour one, and in a randomly ordered suite it always has. The case now asserts the
counter suffix increases strictly *across* flavours in build order, spanning exactly the number of
contexts built, and the mutation is caught (row 7). **Review round 0 found two more survivors**,
both in the store suite's reach and both closed in round 1 (rows 19 and 20): a `#promote_to_exchange`
that released its source before setting the successor — refreshing the chain's eviction position
and emptying the slot between two mutex acquisitions — passed every case, because the `CTX-13`
no-refresh claim was driven only through `ContextStore#set` on a `FakeContext`; and a memoised
`.default` (`@default ||= new`, the load-time line deleted) passed, because the identity case runs
after some `.build` in the same process has already called `.default`. The first now has a
real-chain case beside the fake-driven one; the second is asked of a fresh process. The same
round found the `Fiber[]` boundary test's setup guard covering one carrier where the design names
three; it now writes a fiber-storage and a fiber-local slot on the main fiber and asserts the pair
inside a child `Fiber`, a new `::Thread` and an `Enumerator`'s internal fiber, which is
`observability/016d9154`'s fact and not a mutation. One mutation had to be re-run by hand: the
guard script's `String#sub` collapsed the `\\A` in the timeout-dropped `Regexp.new` replacement
and the pattern stopped matching anything, which is a script artefact and not evidence; the
hand-applied edit fails exactly the per-pattern-timeout assertion and nothing else (row 12).

| # | Fix reverted | Guard | What it said (4.0.6 unless stated) |
|---|---|---|---|
| 1 | `CTX-9`: `BoundedMap#delete_if_identical` compares with `==` instead of `equal?` | `context_store_test.rb`, the trap | 1 failure of 18: `CTX-9: release evicts only the reference-identical occupant … Expected true to not be truthy` — the value-equal sibling evicted the live occupant. **Identical on 3.2.11** |
| 2 | `CTX-12`/`XCUT-14`: the drain evicts two per insert | `context_store_test.rb`, `BoundTest` | 4 failures: `from cap, each insert evicts exactly one … Expected: [8] Actual: [7, 8]` |
| 3 | `CTX-11`/`CTX-12`: the drain deleted | `context_store_test.rb`, `BoundTest` | 6 failures: `CTX-13: cap pressure evicts the first-registered … Expected: 3 Actual: 4`, and the cap-bound, `MAX_TRACKED_CONTEXTS` and `#put`-drains cases with it |
| 4 | `CTX-8`: `#put`'s absence check dropped, making it a plain overwrite | `context_store_test.rb`, `ConcurrencyTest` | 2 failures: `32 threads racing one #put admit exactly one winner … Expected: 1 Actual: 32` |
| 5 | `CTX-2`: `#promote_to_request` rebuilds the bundle through `#with` | `dispatch_context_test.rb`, `PromotionTest` | 1 failure: `promotion is additive, non-mutating, and carries members forward by identity … Expected #<data Bundle …> to be the same as #<data Bundle …>` — `assert_same` catches it; `assert_equal` would not, the two bundles being `==` |
| 6 | `CTX-15`/`CTX-4`: the counter clamped to 0, so the key is the bundle's rendering alone | `dispatch_context_test.rb` | 7 failures: `minting from the SAME Bundle::NONE object still yields distinct keys` and `three flavours … draw from one counter: Expected: 9 Actual: 1` among them |
| 7 | `CTX-6`: `ExchangeContext.build` mints from its own fixed counter | `dispatch_context_test.rb` | **0 failures against the plan's distinctness case** (the survivor); 1 failure against the strengthened case: `three flavours built from one untraced bundle draw from one counter: Expected: 9 Actual: 7` |
| 8 | `CTX-19`: `BoundedMap`'s hash swapped for `ObjectSpace::WeakMap` | `context_store_test.rb` | 3 failures, 6 errors: `CTX-19: 1000 registered contexts stay reachable after the caller drops every local: Expected: 1000 Actual: 0` — the discriminator the design promised — plus `CTX-7: … Expected: 16000 Actual: 9320`. **On 3.2.11**: 3 failures, 8 errors, the `CTX-19` case reading `Expected: 1000 Actual: 1` and the errors `NoMethodError: undefined method 'delete' for #<ObjectSpace::WeakMap>` — the floor's `WeakMap` has no `#delete`, so even the swap's shape differs across the range |
| 9 | `OBS-26`: `Bundle#valid?` ignores the span id | `instrumentation/bundle_test.rb` | 1 failure: `an all-zero span id makes a bundle invalid even when its trace id is real … Expected … to not be valid?` |
| 10 | `OBS-26`: `TraceIdFlavour#valid_trace_id?` ignores the sentinel | `trace_id_flavour_test.rb`; `bundle_test.rb` | 1 failure: `the sentinel is the one input where the two predicates disagree: Expected true to not be truthy`; and 2 in the bundle suite (`a DATADOG bundle …`, `NONE` reporting valid) |
| 11 | `OBS-26`: the span-id pattern matched against `value.downcase` | `bundle_test.rb`, `ValidationTest` | 1 failure: `span_id, trace_flags and trace_state are each validated on their own: Dexpace::InvalidArgumentError expected but nothing was raised` — `"B" * 16` accepted |
| 12 | The W3C pattern built without `timeout:` | `trace_id_flavour_test.rb`, `PerFlavourTest` | 1 failure (hand-applied): `every flavour is a frozen Data with its pattern built with a per-pattern timeout: w3c: no per-pattern timeout. Expected nil to not be nil` |
| 13 | `CTX-2`: `#promote_to_exchange` mutates `self` and registers it | `request_context_test.rb` | 4 errors: `FrozenError: can't modify frozen Dexpace::RequestContext` — the frozen `Data` refuses before any assertion runs |
| 14 | `OBS-25`/`CTX-20`: `#tracer` returns `NoTracer.new.freeze` per call | `instrumentation/no_tracer_test.rb` | 2 failures: `the factory method accepts … own positional and keyword shape … Expected #<NoTracer:0x…> to be the same as #<NoTracer:0x…>`, and the 16-thread case |
| 15 | `CTX-16`: the operation name folded into the successor's key | `request_context_test.rb`, `OperationNameTest` | 1 failure: `operation_name changes neither the call key, the request, nor the slot: Expected: "shared:GetUser" Actual: "shared"` |
| 16 | `CTX-17`: `DispatchContext.build` registers what it builds | `dispatch_context_test.rb`, `PromotionTest` | 4 failures: `constructing a dispatch context registers nothing: Expected: 0 Actual: 1`, the never-promoted close, and the first-promotion cases |
| 17 | `CTX-3`: `#promote_to_exchange` drops `call_key:` and mints afresh | `request_context_test.rb` | 3 failures: `request -> exchange carries every source member forward by identity: Expected "…:2" (oid=…) to be the same as "…:3"`, and the same-slot cases |
| 18 | `CTX-19`: the cop's `Include:` narrowed to `gems/dexpace-core/lib/**/*.rb` | `test/gates/rubocop_config_test.rb` | 1 failure of 7: `Dexpace/NoWeakReferences is required, enabled, and reaches every gem's lib/ [rubocop_config_test.rb:45]` with the expected/actual diff of the `Include` list |
| 19 | `CTX-13`/`CTX-10`: `#promote_to_exchange` calls `store.release(self)` before `store.set(ctx)` (review round 0's survivor; case added in round 1) | `context_store_test.rb`, `BoundTest`, the real-promotion case | 1 failure of 20: `CTX-13: a real promotion re-sets the slot without refreshing its eviction position … Expected: ["b", "c", "d"] Actual: ["a", "c", "d"]` — `a` survived and `b` was evicted. **Identical on 3.2.11** |
| 20 | `.default` memoised on first call — `def default = (@default ||= new)`, the load-time assignment deleted (review round 0's survivor; case added in round 1) | `context_store_test.rb`, `ReachabilityTest`, the fresh-process case | 1 failure of 20: `.default is assigned at file load: a fresh process holds it before any call … Expected: "true" Actual: "false"`. **Identical on 3.2.11** |

The cop's own table runs its 29 rows through phase 0's verbatim `CopCase` harness at
`TARGET_RUBY = 3.2` on RuboCop **1.91.0** (`VERSIONS` pins `~> 1.91`; the plan verified against
1.90.0), and every row of the two `ObjectSpace::WeakKeyMap` spellings parses and matches on the
host 4.0.6 exactly as the design says it must on a 3.2.11 host, since the parse target and not
the interpreter is what the harness pins.

## Audit groups run

The phase-start pair first, at implementation: `--origin note --brief` returns 52 note entries
across 21 files (the design counted 30 across 16 before it filed its own two; five phases have
filed notes since); `--section conflicts --brief` returns the six harvested conflicts, every one
`[overridden by notes/…]`, and 19 note-side entries. `--prefix-info CTX` reports 20 IDs, 16 MUST /
3 SHOULD / 1 MAY, 20 of 20 substantive, 0 roll-ups; `--gaps CTX` returns nothing. `--req` was run
once over all twenty IDs before Task 1 rather than per task — 47 entries across 5 topic files, 4
of them notes — and none came back a roll-up; the `CTX-9` cross-filing into `error-handling`
(`Dexpace.each_cause`, 4b's material) is the artefact the design recorded. The seven groups the
design ran at planning are recorded there; at implementation the three that bite were re-checked
against the built code:

| Group | Result at implementation |
|---|---|
| Pipeline composition and execution context | Clean against the built code: every rule in `execution-context` is either adopted verbatim or superseded by one of the design's two notes, which stand as written — the drain sits in one `synchronize` and yields to nothing, and `BoundedMap` is named by a bare name from `module Dexpace; class ContextStore` and nowhere else. `notes/observability.md`'s 2026-09-13 entry describes `P4-8` as `#tracer(name = nil, version = nil)`, the design's recommendation; the plan's resolution and the build carry the gem's five-parameter shape, and that entry's point — the bundle's factory produces span tracers and is legitimately shared — is unaffected. No note added |
| Fiber scheduler, thread safety | Clean against the built code: two mutexes, `BoundedMap`'s and `CallKey`'s, each held across a hash write or an increment and the drain of its own hash and nothing else, never across a callback; no code path acquires both; `Timeout.timeout`, `Thread#raise` and `Thread#kill` appear nowhere; every thread the suites start is joined, which `DexpaceTestCase`'s teardown enforces. The `Fiber[]` boundary test's setup guard covers the three carriers the design names — a fiber-storage slot and a fiber-local slot written on the main fiber, the pair read as `[:fiber_storage, nil]` inside a child `Fiber`, a new `::Thread` and an `Enumerator`'s internal fiber, `observability/016d9154`'s fact — before the store half; `Fiber[:probe] = v` there emits no warning on 3.2.11 or 4.0.6 under `-w -W:deprecated`, as verified fact 13 says |
| Public API surface | `module-organization/1828a984` (one public constant per file) holds for eleven of the twelve files; `no_tracer.rb`'s two is the stretch the design records. `api-design/b0e18938` is why `BoundedMap`, `CallKey`, `NoSpan`, `NoTracer`, `NoTracerFactory`, `SPAN_ID_PATTERN` and `TRACE_FLAGS_PATTERN` are private and why `Context.validate!` was made private too (deviation 5); `api-design/88e6bf12` is honoured by `respond_to?` at the store check and no `is_a?` on a store anywhere; `api-design/1d9e6e0b`'s one exception is P4-8's `#tracer` |

The two notes the design filed stand as written. No third was needed: nothing execution found was
a harvested rule stated wrong.

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate.
Items 1 through 4 are where phases 0–3b as built overrode the plan's assumptions; the rest are
this build's.

1. **`Dexpace/NoWeakReferences` is the eighth custom cop, not the seventh.** Seven exist on `main`:
   phase 0's five, phase 0's later `Dexpace/NoKeywordSplat`, and phase 2's
   `Dexpace/QualifiedCoreConstant`, which `CLAUDE.md`, `docs/sdk-documentation/quality-gates.md`,
   phase 2's checklist and `.rubocop/test/cops_test.rb`'s own head comment all call the seventh.
   The plan's Task 8 title and every "seventh" it writes are off by one, following phase 0's
   plan amendment of 2026-09-13, which says the keyword-splat cop "carries no ordinal" — a rule
   the as-built documentation does not follow. Every ordinal this phase writes says eighth; the
   discrepancy between phase 0's plan text and the as-built count is routed below.
2. **The `Metrics/ParameterLists` inline disables the plan's fences carry are not written.**
   Phase 0 as built already sets `CountKeywordArgs: false` in `.rubocop.yml`, citing this phase's
   seven measured methods — the plan's own finding, routed to phase 0's plan Task 3, was applied
   before this phase executed — so the directives would be redundant and
   `Lint/RedundantCopDisableDirective` would report each one. `NO_TRACER_FACTORY#tracer` keeps its
   `Lint/UnusedMethodArgument` directive, in RuboCop 1.91's `disable-next` form, because
   `Style/DirectiveScope` refuses a disable/enable pair around a single statement.
3. **`bounded_map.rb` and `context/call_key.rb` each have a `sig/` mirror.** The plan's open
   question 2 says phase 2 shipped `Dexpace::Hooks` with no `sig/` mirror; on `main`,
   `sig/dexpace/hooks.rbs` exists with a comment saying why — the strict `core` Steep target checks
   every file under `lib/` and needs the constant declared to type its call sites, and RBS has no
   visibility. The two mirrors carry that comment, `sig/` still mirrors `lib/` one file per file
   (77 of 77), and what the two constants do **not** get — a manifest row, a public YARD contract, a
   `test/` mirror — is exactly what `hooks.rb` does not get. The open question's conclusion, never
   relax the target, stands; the target reported no diagnostic at any task.
4. **`_ContextHost` is a fourth RBS interface.** `module Context` calls `store` and `call_key` in
   `#close`, and the strict target types a module's `self` by its self-type constraint; `Model`
   already does this with `_ModelInstance`. `_ContextHost` includes `_ModelInstance` and adds the
   two readers, so `Context : _ContextHost` types `#close` without an `untyped` receiver. It is a
   public name in `sig/` and is added to P4-2's list in the design's As-built addendum. `store` is
   `untyped` there and on every flavour, as the plan says, because the check is `respond_to?`.
5. **`Context.validate!` is the private instance method `#validate_context!`.** The plan's fence
   made it a public singleton method, which the real walker rendered as
   `Dexpace::Context.validate!` in the regenerated manifest — a locked public name the design never
   lists: its object model gives `Context` "one method", `#close`, and P4-11's method list omits it.
   Each flavour's `initialize` calls it bare before `super`, which is what an included module's
   private method is for; `context_test.rb` drives it through a `Data` includer shaped like the
   three flavours. One manifest row fewer than the plan's fence would have produced.
6. **`CallKey.mint` checks the bundle.** `DispatchContext.build(bundle: nil)` mints before it
   constructs, and the plan's fence raised `NoMethodError` off `nil.trace_id` there instead of
   `SEAM-29`'s `"bundle is required"`. The mint checks first; the flavour's `initialize` still
   checks too, for the pinned-key path.
7. **`BoundedMap.new(cap:)` requires a positive `Integer`.** The plan's fence accepted anything
   non-nil; a cap of 0 evicts the entry just inserted on every insert and a negative cap makes
   `@h.shift while @h.size > @cap` spin forever on an empty hash. Refused at construction with
   `Dexpace::InvalidArgumentError`; the absent case keeps `SEAM-29`'s message.
8. **`Bundle` ingests its three String members through `Model.frozen_string` and normalises
   `remote` to `true`/`false`**, in `initialize` rather than in `.build`, so `#with` (which routes
   through `.build`) and a direct `.build` are validated and owned identically; `trace_state` is
   owned through `Model.own` there for the same reason, where the plan owned it in `.build` only.
   `span:` and `tracer_factory:` are `Model.required!` too. `INVALID_SPAN_ID` is frozen explicitly:
   `"0" * 16` yields an unfrozen String even under the magic comment.
9. **`Bundle#initialize`'s checks are two private helpers, `#validate_identifiers!` and
   `#validate_wire_fields!`.** The plan's one-method form trips `Metrics/AbcSize` (21.21 of 17) and
   `Metrics/CyclomaticComplexity` (8 of 7) under the repository's defaults, which styleguide 01
   leaves unraised; the checks are unchanged.
10. **`TraceIdFlavour::DATADOG`'s bound is spelled `(1 << 64) - 1`.** rbs types `Integer#**` as
    `Numeric`, and strict Steep refuses a `Numeric` for the `Integer?` member; the suite asserts the
    value against `(2**64) - 1`. `invalid_trace_id` goes through `Model.frozen_string`, and
    `#renderable?` refuses a non-String before matching.
11. **`ContextStore.default` is `attr_reader :default` inside `class << self`**, which is what
    `Style/TrivialAccessors` asks of the plan's `def default = @default`; the eager assignment at
    the end of the class body is unchanged.
12. **The suites are one class per behaviour group.** Five of the plan's test files exceed
    `Metrics/ClassLength`'s 100 lines once every case is in them; each is split into nested
    `DexpaceTestCase` classes, the shape phase 3b used, with no case removed. The plan's `Struct`
    `FakeStore` is a plain class (`Naming/PredicateMethod` flags a `release` returning a literal
    `true`; the fake returns the context). Every thread a case starts is collected and joined
    before the case returns — the plan's `CTX-8` fence started 32 unjoined threads, which
    `DexpaceTestCase`'s teardown refuses.
13. **The run counts are the build's, not the plan's.** 4 / 8 / 20 / 14 / 3 / 5 / 20 / 20 / 13 /
    7 across the ten suites (114 in all) against the plan's 3 / 5 / 14 / 9 / 1 / 3 / 12 / 11 / 7 /
    3, because cases were added for the frozen-key both-ways property, the parameter list, the
    three private classes' unreachability, the strictly increasing counter, the cross-store
    counter, the concurrent mint, the real-`Response` reachability, the flavour and cap validation,
    and the member lists, and review round 1 added the store suite's real-promotion `CTX-13` case
    and the fresh-process `.default` case (guards 19 and 20); no plan case was dropped. The plan's
    `Fiber[]` boundary fence guarded the main fiber alone, the first build added a child `Fiber`,
    and review round 1 made the case guard the three carriers the design's testing strategy names,
    with a fiber-local slot set so "not visible" is asserted rather than vacuous. Minitest is 5.27.0 on every row under the
    bundle (`VERSIONS` pins `~> 5.25`), so the plan's "6.0.0 on 4.0.6" assertion-count artefact
    does not arise and the counts are identical across the four interpreters.
14. **`--req` ran once for all twenty IDs before Task 1** rather than once per task; every task's
    IDs were in that one result, and the audit-groups section records what it returned.
15. **The `CTX-19` end-to-end case builds its `Response` with a `ResponseBody`**, phase 3b's
    response-side body, not `Body.string` — a request body, which `Response#body_string` refuses
    by design (`HTTP-36`). The plan named no such case; it is this build's addition.
16. **The commit granularity is the stack's, not "once per phase".** The plan's "no commit step
    appears in any task; the manager commits once per phase" is the pre-2026-09-14 rule; the
    phase lands as the code → tests → docs stack the roadmap's step 5 now names (finding 5).

## Findings routed

- **The runtime surface snapshot DOES hold `Data`-generated readers — closed by phase 0 as
  built.** The plan's Task 9 Step 3 finding, routed to phase 0's plan Task 14, was derived on a
  stand-in walker: `tools/surface.rb#data_readers` on `main` walks the anonymous `Data.define`
  superclass and keeps every reader still public on the model, its own comment saying why, and
  the regenerated manifest holds every reader of the five value types (`DispatchContext#bundle`,
  `Bundle#trace_state`, `TraceIdFlavour#max_value` and the rest). P4-11's sentence — "the runtime
  surface snapshot is what holds them" — is true as written. Nothing to route.
- **The `Metrics/ParameterLists`-versus-keywords count — already applied by phase 0 as built.**
  Routed by the plan to phase 0's plan Task 3; `.rubocop.yml` on `main` sets
  `CountKeywordArgs: false` citing this phase's seven measured methods, and phase 0's checklist
  records it. Nothing to route; deviation 2 is the consequence.
- **The drain's second discriminating measurement — already on `docs/first-release.md`.** The
  `IO-38` post-release trigger row carries the `CTX-7`/`CTX-8` drain sentence, added 2026-09-13
  from the plan's review. Re-read against the build: `ContextStore#size` delegates to
  `BoundedMap#size` under the same mutex as the insert, the shipped measurement is the "at most
  one per insert" observable form (row `CTX-12`), and the row reads true; unchanged.
- **The cop ordinal.** Phase 0's plan amendment of 2026-09-13 says `Dexpace/NoKeywordSplat`
  "carries no ordinal" and that phase 4a's cop is "the seventh"; `CLAUDE.md`,
  `docs/sdk-documentation/quality-gates.md`, phase 2's checklist and `cops_test.rb` count it and
  call `Dexpace/QualifiedCoreConstant` the seventh. This phase follows the as-built count (eighth)
  and does not edit phase 0's record; the sentence in phase 0's plan is **routed to phase 10's
  inbound list** in the roadmap as documentation audit against an already-planned phase.
- **The roadmap's step 5 and five segmentation designs said a phase returns as one phase-level
  pull request.** Phases 1, 2, 3a and 3b each landed as their own code → tests → docs stack off
  `main`, and 4a and 4b run as two parallel stacks; the roadmap's step 5 and the phase 3, 4, 5, 6
  and 8 segmentation designs carry a dated in-place correction, in the shape of the 2026-09-14
  `mvp` → `main` correction already in step 5, keeping the old wording visible. The one deliberate
  edit this phase makes to an earlier phase's document, and it is in material the roadmap says is
  corrected in place. Phase 8's segmentation design leans on "the phase-level PR" as a mechanism in
  three further places (its `TransportError` definition "reviewed as one thing", a wait on it, and two
  `docs/first-release.md` changes "owed by the phase-level PR"); those are that phase's own
  operational sentences, left for phase 8's execution to restate against its three stacks, and named
  here so its implementer meets them as a known consequence rather than a discovery.
- **`notes/observability.md`'s 2026-09-13 entry states P4-8's arity as the design's two-positional
  recommendation.** The build carries the gem's five-parameter shape, as the plan resolved; the
  entry's argument does not depend on the arity and a note is never edited in place. Recorded here
  so a reader of that entry knows which shape shipped; phase 10's plan Task 16, which that entry
  names as the owner of the two-factories distinction, is where the wording is next touched.
- **The design's ledger** gains an "As built" addendum (in the design) for the eighth-cop numbering
  (P4-10), the two `sig/` mirrors (P4-3), `_ContextHost` (P4-2), the private validation (P4-11) and
  the confirmed `#tracer` arity (P4-8), with the one new row numbered **P4-40**, the next free
  number in the phase-4 ledger the three sub-phases share (4b's design filed P4-12–P4-25 and 4c's
  P4-26–P4-39 before this phase executed). The consolidation into design §10 and the §5.4 and
  §8.1 addenda are a human's, as they were for 3a and 3b, because `docs/sdk-design-ruby/` is
  frozen; `docs/deviations.md` is left as phase 2 left it for phase 10 to flip.

## Postponed work

The two items the design postponed keep their owners: the configuration source for
`ContextStore`'s cap is phase 5a, Task 13
(`docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration.md`), reached through the
`ContextStore.new(cap:)` keyword and `MAX_TRACKED_CONTEXTS` this phase ships with no signature to
change; and the no-op span and tracer protocols are phase 5c, Tasks 3, 4 and 5
(`docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics.md`), which give the three
private classes behind `NO_SPAN`, `NO_TRACER` and `NO_TRACER_FACTORY` their methods while the
objects keep the identity this phase published — the empty `_Span` and `_Tracer` interfaces are
that postponement stated in the type system. The items earlier phases postponed were re-read on
2026-09-16 and keep the owners the design's "Work Phase 4a Postpones" section records: `SEAM-28`'s
identifier (phase 5c, Task 4, over the `#operation_name` this phase carries), the suppressed trail
and `close_quietly`'s routes (4b), the pivot's `deadline:` (phase 5a, Task 8), the fakes' move to
`dexpace-conformance` (declined by 8a; `FakeContext` is one more double that would move), `IO-38`
on a GVL-free interpreter (`docs/first-release.md` § Post-release triggers, whose row now also
names this phase's drain) and the retry engine (6a). The implementation postponed nothing further.
