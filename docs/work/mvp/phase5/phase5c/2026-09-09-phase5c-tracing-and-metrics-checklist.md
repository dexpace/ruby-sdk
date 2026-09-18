# Phase 5c — Tracing and Metrics: Checklist

**Written at execution time, 2026-09-17, from what was built** — not from the plan. A row whose task
did not do what the plan said is a row that says so, and the "Deviations from the plan" section
below is where each departure is stated with its reason. The design and the plan were written on
2026-09-09 against phases 0–3's *plans* and phase 4's *designs*, on a machine that then had only Ruby
3.4.10; phases 1, 2, 3a, 3b, 4a, 4b and 4c were then built and merged to `main` (PRs #40–#62), and this
phase was cut from `main` at `993c439`, with all four interpreters installed. Where the plan's text and
the built tree disagree the tree wins and this document records it. **This is the 5c-first execution the
plan's Global Constraints anticipate**: phase 5b (issue #19) is not running, so 5c created
`diagnostics.rb` with its three constants for 5b to adopt (P5-71), and nothing else of 5b's — no
`Event`, no `Logger`, no `Keys`, no step — exists on this stack. Phase 5a (issue #18) is being built in
parallel off the same `main`; nothing of 5a's is on this base, 5c names no 5a constant and reads no
configuration value, and the sentences both lanes edit are written here for 5c only.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics.md`. Task numbers are that
plan's. Design: `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md`, whose
Deviation Ledger rows `P5-40`–`P5-50` and as-built rows `P5-71`–`P5-76` are cited below; the charter is
`docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md`. Every test file named here is under
`gems/dexpace-core/test/`, mirrors its `lib/` file one for one (three carry no `lib/` mirror and say so
below), and opens with the IDs it exercises.

## Requirement rows

Twelve own rows — `OBS-21`–`OBS-23` and `OBS-25`–`OBS-33` — plus thirteen cross-reference rows for the
non-`OBS` IDs, and the two 5b `OBS` IDs, this phase owns a share of, taken from the design's
interface-surface table the way 4b and 4c carried theirs: `CTX-14`, `CTX-15` and `CTX-20` (phase 4a's
slots, now populated), `SEAM-28` (the consumer), `XCUT-21` (`OBS-27`'s CSPRNG path), `OBS-10` and
`OBS-24` (the three constants shipped early), `OBS-34` (the structural half), `OBS-20` (the boundary 5c
honours from its side), `XCUT-11` and `XCUT-20` (phase 9's audits), `NFR-11` (the interfaces' home) and
`ASYNC-9`/`ASYNC-11` (the floor finding routed forward). **Eleven ✅** — `OBS-29` ✅ with its unwired
half named in the row, `OBS-30` ✅ by construction — **one ⏳** (`OBS-32`, post-v1), nothing 🚫,
nothing N/A. `OBS-24` and `OBS-34` are `5b`'s and appear only as cross-reference rows, so a reader who
arrives looking for either finds the answer here.

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `OBS-21` | MUST | ✅ | 3 | `NO_SPAN`'s private class gained exactly the seven protocol methods — `#recording?` false, `#set_attribute`, `#add_event`, `#record_error` returning `self` and dropping their data, `#status=` returning its argument with no reader, `#finish` `nil` on every call, `#context` `Bundle::NONE` by identity — every one working on the frozen receiver phase 4a published, so the object keeps its identity and the class is not `NFR-4`-locked (boundary 10). The recording branch is an implementer contract stated in the class's YARD and `_Span`'s RBS comment and asserted against `RecordingSpan` (P5-48): mutators keep what they are handed, and "call `end()` twice and assert no duplicate export" is one entry in `finished_at` after two `#finish` calls — unassertable against `NO_SPAN`, which exports nothing either way. `#status=` is reached through `public_send`, because the assignment form evaluates to its right-hand side whatever the method returns. Guards 1, 2, 3a and 3b below (`instrumentation/no_span_test.rb`) |
| `OBS-22` | MUST | ✅ | 5, 6 | `Tracing.activate(span)` returns a handle whose `#close` restores the previously-active span; `.with_span` is the block form over it with the restore in an `ensure`; `Scope` is a plain three-ivar class holding the previous span on the Ruby call stack and never a stack in fiber storage (R13, P5-46). Nesting is proven with two **distinct** `RecordingSpan`s by identity at every level — a one-span test passes under an implementation that restores nothing — the throw case asserts the **slot** after the `assert_raises`, and the bare handle is nested and closed by hand, which is the non-lexical form 5b's `AsyncStep` needs (P5-45). `#close` is idempotent by construction and `Scope` is not a `Dexpace::Closeable`. Guards 7, 8 and 13 (`instrumentation/tracing_test.rb`, `instrumentation/scope_test.rb`) |
| `OBS-23` | MUST | ✅ | 5, 6 | `Tracing.correlate(span, bundle)` pushes the bundle's trace id and span id under 5b's `Diagnostics::TRACE_ID` and `::SPAN_ID` — `Symbol`s, the one key spelling every carrier API accepts on every row (R11) — for the scope's lifetime, into `Fiber[]` and never `Thread.current[]` or `ContextStore` (boundary 14: a child thread, fiber and enumerator all see the pushed keys), and `Scope#close` restores each "to its prior value (or remove it if previously unset)" as one branchless assignment (R12, P5-49). For a non-recording span the push is skipped and activation delegates to `.activate`, asserted with a non-recording `RecordingSpan` and not `NO_SPAN` so the "still becomes current" half is a real assertion; for a bundle that is not `#valid?` it likewise delegates (`OBS-26`, the only state 5b's step can reach in phase 5). **The removal half is the floor's residual (P5-72)**: on 3.3+ the key is removed, on 3.2 it stays present with a `nil` value that `Fiber[]` and `OBS-10`'s null-skip both read as absent, and `FiberStorageFacts#assert_diagnostic_key_removed` asserts what each row can honour — never the pushed value. Guards 9, 10, 11 and 12 (`instrumentation/tracing_test.rb`, `instrumentation/scope_test.rb`, `instrumentation/diagnostics_test.rb`) |
| `OBS-25` | MUST | ✅ | 3, 4, 5, 6, 7, 8 | Every no-op is a frozen stateless singleton reached by a qualified constant and asserted by `assert_same`: `NO_TRACER#start_span` and `#in_span` hand back `NO_SPAN`; `NO_SCOPE` is the cached-singleton scope, returned on an **identity** test — the span being activated is already current and no key changes — and not on the recording flag, which would leave a recording span un-restored under a non-recording one (P5-47); `Bundle::NONE` is the no-op context whose identifiers are the invalid sentinels; `NULL` and `NO_TRACER_FACTORY` are the no-op HTTP tracer and factory. "MUST NOT allocate per call" is met by no method in the segment taking a `**` splat (P5-42, the cop `Dexpace/NoKeywordSplat` verified live below) and asserted as a two-loop `GC.stat` delta of exactly `0.0` per call over the whole span protocol, the tracer path, the untraced activation path, the eleven `NULL` callbacks and the two instruments, with only frozen constants, Symbols and Integers crossing the loop (`test/support/allocation_delta.rb`; 5b's R8). Guards 4, 5, 6, 7 and 19 |
| `OBS-26` | MUST | ✅ | 2 | Satisfied by **phase 4a** — the sentinels, the 16-lowercase-hex span-id rule and the derived `#valid?` are `Bundle`, `Bundle::INVALID_SPAN_ID` and `TraceIdFlavour`, untouched here (boundaries 10 and 11: `Bundle.members` is the same eight before and after, asserted). 5c adds `Bundle#sampled?`, the low bit of `trace_flags`, which 4a reserved for phase 5 and which reads `"01"`, `"03"` and `"ff"` sampled and `"00"`, `"02"` and `"fe"` not; and honours the all-zero rule in `Tracing.correlate`'s guard. Guard 14 (`instrumentation/bundle_test.rb`, `SampledTest`) |
| `OBS-27` | MUST | ✅ | 2 | `TraceIdFlavour#generate_trace_id(generator = ::SecureRandom)`: `W3C` draws `#hex(16)` — 32 lowercase hex by construction, nothing case-folded — `DATADOG` draws `#random_number(1 << 64)` rendered decimal, `NONE` returns the invalid sentinel by identity, every result frozen. A zero draw is **coerced** — `"0"*31 + "1"` and `1` — as a substitution rather than a redraw, driven through the injected generator seam because the branch is unreachable by sampling; a seeded `Random` is a deterministic generator through the same seam. The format half is a thousand draws each. Dispatch is `case name` (P5-50) and a flavour outside the three raises `InvalidArgumentError`. The randomness is `XCUT-21`'s CSPRNG path, kept separate from `CFG-32`'s (boundary 8); `securerandom` is already on the require allowlist (`gates:require_allowlist` green). No span-id generator ships (P5-44). Guards 15a–15e (`instrumentation/trace_id_flavour_test.rb`, `GenerationTest`) |
| `OBS-28` | SHOULD | ✅ | 8, 9 | `Dexpace::Instrumentation::HTTPTracer`, a module of exactly eleven no-op methods in the requirement's three groups with the arities phases 6 and 8 emit against pinned (host and port, byte counts, status and headers, next delay), and `NULL`, the frozen instance of a private class that includes it and adds nothing. "Implementers override only what they need" is a mechanism: a class including the module and overriding one method answers the other ten as no-ops. `CallableAdapter` is §8.1's bus shape, forwarding each callback as its name and a payload keyed by parameter name to one `#call(name, payload)` object, allocating a Hash per event by construction and refusing a non-callable at construction (P5-75). Guards 16 and 17 (`instrumentation/http_tracer_test.rb`, `instrumentation/callable_adapter_test.rb`) |
| `OBS-29` | MUST | ✅ **contract and ordering test only** | 4, 8, 10 | The eleven-method vocabulary, its no-op defaults and an ordering assertion over a conformant emitter fake ship in 5c: `RecordingHTTPTracer` includes the module and overrides all eleven, and `ordering_test.rb` drives a succeeding and a retry-exhausted operation through it by hand and asserts started first and once, succeeded or failed last and once and never both, and retries-exhausted **immediately** followed by operation-failed with the **same** error by `assert_same` — the clause a naive test omits. **Nothing in phase 5 emits any of it**: the per-attempt group has no emitter until phase 6's retry step and the transport-milestone group none until phase 8's adapters, which the requirement's own last sentence anticipates ("pipeline/transport wiring to emit it is a follow-up, so it is not yet runtime-enforced"). The wiring is postponed: the per-attempt half to phase 6a, Task 9 (`docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry.md`), the rest — the operation-lifecycle triple and the transport-reachable `HTTPTracer` — to phase 10's inbound list (R14). The 1:1 clause is read as binding stateful tracers only (P5-43) and asserted against `RecordingTracerFactory`, which mints a fresh tracer per call where `NO_TRACER_FACTORY` shares one. Guards 18a and 18b. *Cites:* `OBS-28`, `OBS-29`, `PIPE-24`, `PIPE-39`, §8.1 |
| `OBS-30` | MUST | ✅ **by construction** | 4, 6, 7, 8, 9 | Core wraps no tracer or meter call anywhere — no `rescue` in `tracing.rb`, `scope.rb`, `meter.rb`, `http_tracer.rb` or `callable_adapter.rb` — which is the whole of the runtime's obligation (boundary 2, `OBS-20`'s asymmetry). The must-not-throw half is a contract on implementers, stated in each class's YARD, and asserted the way the sentence does not sound: a `raise` inside `with_span`, `with_correlated_span`, `NO_TRACER#in_span` and a raising bus behind `CallableAdapter` all **propagate**, with every slot restored by the `ensure`. Concurrency safety is structural — frozen stateless singletons — and asserted as identity across sixteen threads for the factory, the meter's two instruments and `NULL`, the property rather than the absence of a race. Guard 13 |
| `OBS-31` | MUST | ✅ | 7 | `NO_METER#create_counter` and `#create_histogram` return one shared frozen instrument each, asserted meter-to-meter under **different** names (the same name would prove memoisation); the instruments' `#add` and `#record` return `nil`; the meter and both instruments are `private_constant` classes behind the public `NO_METER`, the asymmetry with `NO_SPAN` argued in the design; and core pulls no metrics runtime in — the gemspec still has zero `add_dependency` lines. The recording half is asserted on `RecordingMeter`, which deliberately mints a fresh instrument per call (P5-48). `interface _Meter`, `_Counter` and `_Histogram` are declared filled, here and only here, for 5b's step to type against. Guard 19 (`instrumentation/meter_test.rb`) |
| `OBS-32` | SHOULD | ⏳ | — | Post-v1 with `dexpace-instrumentation-otel`: `docs/first-release.md` § What v1 ships without › SHOULD- and MAY-level requirements declined for v1, the `OBS-32`/`OBS-37` entry, which names this row. No instrument name, unit or attribute set is fixed by 5c and `http.client.request.count` / `http.client.request.duration` appear nowhere in `lib/`; the two names are 5b's `Keys` constants (R11), and the units, descriptions and semantic-convention attribute sets stay declined because the conformance clause needs a recording meter core does not ship (P5-48). Task 12 filed nothing new |
| `OBS-33` | MUST | ✅ | 7 | The MUST-document half is discharged in the two places a duck-typed SPI's contract can bind — `_Counter#add`'s RBS comment and `NoCounter`'s YARD — and the "MUST NOT validate on the hot path" half by there being no check to write: `#add(-1)` and `#add(2.5)` are discarded like `#add(1)`. The histogram tolerates `Float::NAN`, `±Float::INFINITY`, `0` and `-1`, asserted as `assert_nil` on each return value and never `assert_nothing_raised` (`testing/26b866e1`); non-finite handling is a concrete adapter's (`instrumentation/meter_test.rb`) |
| `CTX-14`, `CTX-15` | MUST | ✅ populated | 3, 4, 5, 6 | Cross-reference, phase 4a's IDs: the `span` and `tracer_factory` slots and `Bundle::NONE`'s two no-op singletons now carry their protocols, with the five prohibitions honoured item by item — no second no-op span, tracer, tracer factory or meter anywhere in `lib/` (the smoke suite pins the thirteen constants under `Dexpace::Instrumentation`), neither published singleton replaced (`NO_SPAN`, `NO_TRACER` and `NO_TRACER_FACTORY` are `equal?` to `Bundle::NONE`'s and to a fresh `require`'s), no `Bundle` member renamed, removed or added, `#valid?` derived, `TraceIdFlavour` a `Data` with `.of` and `NONE`'s sentinel unchanged. `_Span` and `_Tracer` are widened **in place** in 4a's `sig/` files and the "empty on purpose" comments rewritten; no declaration moved (`instrumentation/bundle_test.rb`, `no_span_test.rb`, `no_tracer_test.rb`, `dexpace_test.rb`) |
| `CTX-20` | SHOULD | ✅ share | 4 | Cross-reference, phase 4a's ID: the factory's five-argument `#tracer` is untouched (P4-8, boundary 10) and its embedded MUST — safe to invoke concurrently — is re-asserted as sixteen threads receiving one object; the tracer it returns now answers `#start_span` and `#in_span` (`instrumentation/no_tracer_test.rb`) |
| `SEAM-28` | MAY | ✅ consumed | 4 | Cross-reference, the half of the MVP-scope `SEAM-24`/`SEAM-28` deferral phase 5 can meet: the **identifier** is phase 4a's `RequestContext#operation_name`, already carried and advisory; the **consumer** 5c supplies is `_TracerFactory#tracer(name, …)`, which takes it as `name` and which `RecordingTracer` keeps by identity. The requirement's own constraint holds structurally — nothing in `Dexpace::Instrumentation` can reach a `Request`, and the test's request object is untouched. `SEAM-28` exists only as an appendix-C row (the roadmap's gap paragraph, still unresolved) and was read out of appendix C; the `SEAM-24` half is post-v1 with `dexpace-async-async` (`docs/first-release.md` § What v1 ships without, the `SEAM-24` entry) (`instrumentation/no_tracer_test.rb`, `OperationTracerTest`) |
| `XCUT-21` | MUST | ✅ share | 2 | Cross-reference, phase 9's ID: `OBS-27`'s draw is `SecureRandom` — the CSPRNG path — and stays a separate code path from `CFG-32`'s non-cryptographic per-thread PRNG (boundary 8); 5c reaches for no 5a generator (`instrumentation/trace_id_flavour_test.rb`) |
| `OBS-10`, `OBS-24` | MUST | ✅ three constants, early | 1 | Cross-reference, 5b's IDs: `Diagnostics::TRACE_ID`, `::SPAN_ID` and `::DEFAULT_KEYS` ship in `diagnostics.rb` with the values 5b's design fixes, and nothing else of the module (P5-71); 5b's Task 6 extends the file. The measurement 5b need not re-derive stands and is now a standing test: `Fiber.current.storage` returns a fresh unfrozen `Symbol`-keyed `Hash` per read and `Symbol#name` is the same frozen `String` on every call (`instrumentation/diagnostics_test.rb`, `tracing_matrix_facts_test.rb`) |
| `OBS-34` | MUST | ✅ structural half | 11 | Cross-reference, 5b's ID, **not discharged here**: its conformance clause is 5b's step test at level `none`. What 5c owes is that `Tracing`, `Scope`, `NO_METER`, `HTTPTracer` and `NULL` have no parameter, ivar or argument through which a level could reach them, proven by a subprocess that loads the ten 5c files alone, runs tracing and metrics end to end, and asserts `Event`, `Logger`, `Keys`, `Events`, `HTTPLogging`, `Step` and `Configuration` are undefined — written against the **file list** and not the entry point, deliberately (guard 20) (`instrumentation/independence_test.rb`) |
| `OBS-20` | MUST | ✅ boundary | 6, 9 | Cross-reference, 5b's ID: "the runtime does NOT defensively wrap tracer or metrics calls" is 5c's side of boundary 2 — no `rescue` on any tracer or meter path, and a raise propagates with the slots restored (the `OBS-30` row). 5b may not stop wrapping and 5c did not start |
| `XCUT-11` | MUST | ✅ share | 3–9 | Cross-reference, phase 9's ID: eight frozen stateless singletons — `NO_SPAN`, `NO_TRACER`, `NO_TRACER_FACTORY`, `NO_SCOPE`, `NULL`, `NO_METER` and its two instruments — are the audited shared instances, with no lock and no state; per-call state lives on the call's own stack in `Scope`'s three ivars, and the one `Fiber[]` slot holds only an immutable span reference. Identity is asserted across sixteen threads for four of them |
| `XCUT-20` | MUST | ✅ scoped | 3–9 | Cross-reference, phase 9's ID: no method 5c writes can raise on any input it owns — `.current_span` never returns `nil`, `NULL` defines all eleven, `#finish` accepts a second call, the histogram takes NaN — and the guarantee is deliberately not extended to a foreign callback, which `OBS-20` forbids. Phase 9 audits that sentence |
| `NFR-11` | MUST | ✅ share | 3–9 | Cross-reference, phase 9's ID: seven interfaces have a named home — `_Span` and `_Tracer` widened in place, `_TracerFactory` unchanged, `_Scope`, `_Meter`, `_Counter` and `_Histogram` new — every name in them a `Dexpace::` constant or stdlib; `gates:rbs_surface` reports no foreign constant over the 110 mirrors, and `_HTTPTracer` is deliberately not declared |
| `ASYNC-9`, `ASYNC-11` | MUST | ⏳ finding routed | 1 | Cross-reference, phase 8b's IDs, touched by no code here: the floor finding — `Fiber[:k] = nil` retains a nil-valued key on 3.2 — reaches 8b's pooled-worker restore and 5b's union restore, both planned on the 3.4.10 fact. Routed as the roadmap's thirty-ninth inbound bullet and the corpus note (marker `sha:manual-phase5c-fiber-nil-and-string-key-floor`); neither plan is edited from 5c |

## What was built

Six new `lib/` files under `gems/dexpace-core/lib/dexpace/instrumentation/` — the design's five plus
`diagnostics.rb` (P5-71): `diagnostics.rb` (5b's three constants), `scope.rb` (`Scope`, `NO_SCOPE`, the
private `CURRENT_SPAN_KEY` and `NoScope`), `tracing.rb` (`Tracing`'s five functions), `meter.rb`
(`NO_METER` and the private `NoMeter`, `NoCounter`, `NoHistogram`, `NO_COUNTER`, `NO_HISTOGRAM`),
`http_tracer.rb` (`HTTPTracer`, `NULL` and the private `NullHTTPTracer`) and `callable_adapter.rb` —
each with a `sig/` mirror declaring every method, private constants included with the comment
`hooks.rbs` carries, and each with a `test/` mirror. Four `lib/` files widened **in place**: `no_span.rb`
(seven methods on `NoSpan`), `no_tracer.rb` (two on `NoTracer`; `NoTracerFactory` verbatim),
`trace_id_flavour.rb` (`#generate_trace_id`, two private constants, `require "securerandom"`) and
`bundle.rb` (`#sampled?`), with their four `sig/` mirrors widened — `_Span` and `_Tracer` filled where
4a declared them empty, `_TracerFactory` reproduced unchanged — and 4a's `no_span_test.rb` and
`no_tracer_test.rb` re-pinned from "responds to nothing beyond `Object`" to the exact protocol. The
entry file gains a six-line `# Phase 5c:` block in dependency order, `diagnostics` first; `sig/dexpace.rbs`
stays `module Dexpace; end`. Every file uses the full `module Dexpace; module Instrumentation` nesting
and never the compact form, every method works on a frozen receiver, and no method takes a `**` splat.

Three suites carry no `lib/` mirror and are named so: `ordering_test.rb` (`OBS-29`'s conformance
clause), `independence_test.rb` (R11's subprocess) and `tracing_matrix_facts_test.rb` (the standing
matrix facts). Six new files under `test/support/`: the four doubles the design names —
`recording_span.rb`, `recording_tracer.rb` (the factory and the tracer), `recording_meter.rb` (the
meter and its two instruments) and `recording_http_tracer.rb` — namespaced `Dexpace::Recording*`
(P5-73), plus two helpers, `allocation_delta.rb` and `fiber_storage_facts.rb`. The smoke suite
`dexpace_test.rb` gains the tracing-and-metrics `Layers` case pinning the thirteen public constants under
`Dexpace::Instrumentation` and the privacy of the rest; it and the two re-pinned 4a suites travel with the
code, because the code tip must keep them green. The surface manifest gains **42 rows, 730 to 772**, read
row by row against the object model before it was accepted: `Bundle#sampled?`, `CallableAdapter` and its
eleven, `Diagnostics` and its three, `HTTPTracer` and its eleven, `NO_METER`, `NO_SCOPE`, `NULL`, `Scope`
with `#close` and `.build`, `TraceIdFlavour#generate_trace_id` and `Tracing` with its five — no row for
any private constant, the three no-op classes still present only as the value type of their constant's
row. The gemspec is untouched — zero `add_dependency` lines — and `securerandom` is the one plain
`require` 5c adds, already on the allowlist. `docs/knowledge/notes/observability.md` gains one entry
(the floor facts), the roadmap one inbound bullet, `docs/first-release.md` nothing (both entries it
cites already read true), `docs/deviations.md` nothing (phase 10 flips it).

The gates, all seventeen, on **4.0.6** (`bundle exec rake`, 2026-09-17) at the tests tip and again at
the docs tip: green, exit 0 — `cops:test` 129 runs, `steep` no type error over the strict `core` target,
`test:gems` **1,640 runs / 20,939 assertions** across the six gems (87 runs more than the base: 86
across the thirteen new or widened instrumentation suites and one the smoke suite gained), with
**99.97% line coverage (4,271 / 4,272)** against the 80% floor — the one uncovered line is the same
registry-claim race branch every phase since 2 has recorded — `test:gates` 130 runs, the nine
`gates:*` tasks (`gates:require_allowlist` clean, 23 bundled gems known; `gates:surface_snapshot` six
manifests matching; `gates:rbs_surface` no foreign constant; `gates:clean_bundle` six gems in
isolation), `yard` 100.00% documented (547 methods, 0 undocumented), `bundler_audit` clean. The matrix
set is green at the tests tip on **3.2.11** (1,640 runs, 99.97% — 4,198 / 4,199, the same race branch),
**3.3.12** (1,640 runs, 99.97%) and **3.4.10** (1,640 runs, 99.97%), each after a fresh `Gemfile.lock`.
The **code tip** is green on all seventeen gates too, run one by one: its `test:gems` at 1,554 runs /
8,468 assertions and **97.86%** (4,181 / 4,272) on 4.0.6 and **98.49%** on 3.2.11 with the four matrix
gates — above the floor, so the one exception the layering rule allows was not needed. The honest
RuboCop run — `bundle exec rubocop --fail-level=convention --ignore-parent-exclusion` — inspected
**332 files, no offenses** at the tests and docs tips and 317 at the code tip; run through `rake` from
this worktree it inspects 10, the known vacuity on phase 10's inbound list.

One assertion was order-dependent and was found by the 3.4.10 matrix row rather than by any single
suite: the fact-6 case read `$LOADED_FEATURES` for `openssl` in the suite's own process, where
`test:gems`'s one process for six gems and `bundle exec`'s `RUBYOPT=-rbundler/setup` — whose setup
on 3.4.10 requires openssl itself, fifteen features — both put it there before `securerandom` ever
loaded. It now measures in a fresh subprocess with the bundler environment scrubbed, which is what the
fact claims (deviation 21 below).

## Matrix facts, re-run on every interpreter

The design ran its facts on 3.4.10 alone and flagged facts 2, 3, 4 and 6 for re-running on the floor and
the ceiling. All were re-run on 2026-09-17 on **3.2.11, 3.3.12, 3.4.10 and 4.0.6**, first as one script
per interpreter and then as `tracing_matrix_facts_test.rb`, which pins the two version boundaries found.

| Fact | 3.2.11 | 3.3.12 | 3.4.10 | 4.0.6 |
|---|---|---|---|---|
| `Fiber[:k] = v` warnings | 0 | 0 | 0 | 0 |
| `Fiber[:k] = nil` deletes the key | **no** — `storage` reads `{k: nil}` | yes | yes | yes |
| `Fiber#storage=` warnings per call | 1 | 1 | 1 | 1 |
| `Fiber#storage = {a: nil}` retains the key | yes | yes | yes | yes |
| `Fiber.current.storage = nil` reads back | `{}` | `nil` | `nil` | `nil` |
| `Fiber["k"] = v` / `Fiber["k"]` (String key) | `TypeError` | `TypeError` | interned to `:k` | interned to `:k` |
| `Fiber#storage = {"k" => v}` | `TypeError` | `TypeError` | `TypeError` | `TypeError` |
| `Symbol#name` identity-stable and frozen; `#to_s` not | yes | yes | yes | yes |
| `Fiber[]` inherited by child fiber, thread, enumerator; `Thread.current[]` by none | yes | yes | yes | yes |
| A child's rebinding stays in the child; a mutation reaches the parent | yes | yes | yes | yes |
| `Gem::BUNDLED_GEMS::SINCE` | undefined | 22 entries, `securerandom` nil | 28 entries, `securerandom` nil | 23 entries, `securerandom` nil |
| `require "securerandom"` loads `openssl` | no | no | no | no |
| `**splat` / named keyword, objects per 1000 calls | 1003 / 1 | 1004 / 1 | 1003 / 1 | 1003 / 1 |
| three-ivar object / three-member `Data`, per 1000 | 1002 / 2002 | 1002 / 2002 | 1002 / 2002 | 1003 / 3003 |
| a frozen singleton from sixteen threads | same object | same object | same object | same object |

Two facts fail on the floor and both are recorded rather than worked around: the `= nil` deletion is a
fact of 3.3 and later (P5-72; the plan's Task 1 fallback — "delete explicitly" — has nothing to delete
with on 3.2), and the String-key interning a fact of 3.4 and later, which touches nothing 5c built and
strengthens R11's `Symbol` decision. Both are the corpus note's new entry.

## Guards run red

Every guard the brief asks to be seen red was seen red, on 4.0.6, and the bytes restored after each; the
floor-sensitive ones — the six over `Fiber[]`, the two identity ones, the two allocation ones, the
sampled bit and the two coercions — were run on 3.2.11 as well and are caught there too, guard 11
through the floor branch of the removed-key assertion. Twenty-three single-edit mutations, one file at a
time, the owning suite re-run after each; **twenty-two caught, and the one that stays green is meant
to** (guard 20). Two mutations had to be re-spelled: a `{ name: name }` literal in void context is
eliminated by the VM's peephole optimiser and allocates nothing, so the two allocation guards build an
Array they then use.

| # | Fix reverted | Guard | What it said (4.0.6 unless stated) |
|---|---|---|---|
| 1 | `OBS-21`: `NO_SPAN#recording?` returning `true` | `no_span_test.rb` | `Expected #<NoSpan> to not be recording?` |
| 2 | `OBS-21`: `#set_attribute` returning `nil` instead of `self` | `no_span_test.rb` | `Expected nil to be the same as #<NoSpan>` |
| 3a | `OBS-21`: `RecordingSpan#finish` exporting on a second call (the latch removed) | `no_span_test.rb`, `RecordingBranchTest` | `--- expected [first] +++ actual [first, second]` |
| 3b | `OBS-21`: `NoSpan#finish` raising | `no_span_test.rb` | 2 errors: `RuntimeError: finished twice` |
| 4 | P5-42: `**attributes` on `NoSpan#add_event` | the honest RuboCop, and `no_span_test.rb` | `Dexpace/NoKeywordSplat: **attributes allocates a Hash on every call, even one passing no keyword, which OBS-25 forbids on a no-op path. Name each keyword (attributes: nil) instead.`; then `Expected [:req, :keyrest] to not include :keyrest` and `Expected \|0.0 - 1.0\| (1.0) to be <= 0.0` |
| 5 | `OBS-25`: one allocation on the no-op path (`NoTracer#start_span` builds an Array it uses) — **on 4.0.6 and 3.2.11** | `no_tracer_test.rb` | `the no-op tracer path allocates per call. Expected \|0.0 - 1.0\| (1.0) to be <= 0.0` |
| 6 | `OBS-25`: `NO_TRACER_FACTORY#tracer` returning a fresh object — **on 4.0.6 and 3.2.11** | `no_tracer_test.rb` | 4 failures: `Expected: 1 Actual: 16` on the sixteen threads, and the identity shapes |
| 7 | P5-47: `Tracing.activate` returning a fresh `Scope` for the current span — **on 4.0.6 and 3.2.11** | `tracing_test.rb`, `NoOpPathTest` | 3 failures: `the untraced activation path allocates per call. Expected \|0.0 - 3.0\|`, and `Expected #<Scope> to be the same as #<NoScope>` twice |
| 8 | `OBS-22`: `with_span` restoring outside an `ensure` | `tracing_test.rb` | `Expected #<RecordingSpan …> to be the same as …` on the slot after the raise |
| 9 | Boundary 14: `correlate` pushing under `Thread.current[]` — **on 4.0.6 and 3.2.11** | `tracing_test.rb`, `CorrelationTest` | 5 failures: `Expected: "2222222222222222" Actual: nil`, and the inheritance case |
| 10 | `OBS-23`: `correlate` not restoring a previously-set key (handle built without the priors) — **on 4.0.6 and 3.2.11** | `tracing_test.rb`, `CorrelationTest` | 4 failures: `Expected: "1111111111111111" Actual: "2222222222222222"` |
| 11 | `OBS-23`: `Scope#close` skipping a `nil` restore (the previously-unset key left present with the pushed value) — **on 4.0.6 and 3.2.11** | `tracing_test.rb`, `scope_test.rb` | 4.0.6: `:"span.id" should have been removed`; 3.2.11: `:"trace.id" should read back as nil on the 3.2 floor` — the floor branch catching it |
| 12 | `OBS-23`: `correlate` pushing for a non-recording span (the recording guard dropped) — **on 4.0.6 and 3.2.11** | `tracing_test.rb` | `:"trace.id" should be unset. Expected "4bf92f…" to be nil`, and P5-47's `non-recording, nothing owed` |
| 13 | `OBS-30`: a `rescue StandardError` added inside `with_span` | `tracing_test.rb` | `RuntimeError expected but nothing was raised` |
| 14 | `OBS-26`: `Bundle#sampled?` reading bit 2 — **on 4.0.6 and 3.2.11** | `bundle_test.rb`, `SampledTest` | `Expected #<data Bundle trace_flags="01" …> to be sampled?` |
| 15a | `OBS-27`: W3C producing uppercase | `trace_id_flavour_test.rb`, `GenerationTest` | `Expected /\A[0-9a-f]{32}\z/ to match "4BF9…"`, and the seeded-Random case |
| 15b | `OBS-27`: W3C returning the zero draw (coercion dropped) — **on 4.0.6 and 3.2.11** | `trace_id_flavour_test.rb` | `--- expected "000…01" +++ actual "000…00"` |
| 15c | `OBS-27`: DATADOG returning the zero draw (coercion dropped) — **on 4.0.6 and 3.2.11** | `trace_id_flavour_test.rb` | `--- expected "1" +++ actual "0"` |
| 15d | `OBS-27`: DATADOG's draw bound raised to `1 << 80`, so a draw can exceed `2**64 - 1` | `trace_id_flavour_test.rb` | `Expected /\A[0-9]{1,20}\z/ to match "…"` on a draw wider than twenty digits |
| 15e | `OBS-27`: NONE returning `"a" * 32` | `trace_id_flavour_test.rb` | `Expected "aaaa…" to be the same as "0000…"` |
| 16 | `OBS-28`: `HTTPTracer#operation_started` returning `:started` | `http_tracer_test.rb` | `Expected :started to be nil` |
| 17 | §8.1: `CallableAdapter#attempt_failed` forwarding `:attempt_started` | `callable_adapter_test.rb` | `--- expected +++ actual` on the eleven-tuple sequence |
| 18a | `OBS-29`: the ordering test driven with succeeded before started | `ordering_test.rb` | `Expected: :operation_started Actual: :operation_succeeded` |
| 18b | `OBS-29`: retries-exhausted followed by an attempt event and a different error | `ordering_test.rb` | `immediately followed. Expected: :operation_failed Actual: :attempt_failed` |
| 19 | `OBS-31`: `NoCounter#add` building an Array it uses — **on 4.0.6 and 3.2.11** | `meter_test.rb` | `the no-op metrics path allocates per call. Expected \|0.0 - 1.0\| (1.0) to be <= 0.0` |
| 20 | R11: Task 11's subprocess requiring `./lib/dexpace` instead of the ten files | `independence_test.rb` | **green, 1 run** — `Event` is still undefined because 5b is absent from this stack, which is exactly why the assertion is written against the **file list** and not the entry point: once 5b lands, the entry point defines `Event` and only the file-list form still discriminates |

## Audit groups run

The phase-start pair first, at implementation: `--origin note --brief` returned 52 note entries across
21 files before this phase's note and 53 after; `--section conflicts --brief` returned 25 entries, the six
harvested conflicts all `[overridden by notes/…]` and no open conflict. `--req` was run for each task's IDs
before that task; every phase-5 `OBS` ID returned its appendix-B roll-ups beside a substantive
`observability/…` rule, as the charter measured, and the three-step roll-up path was the normal reading
mode — appendix C's rows for `OBS-21`–`OBS-33` were read verbatim, and chapter 15's per-ID
`*Conformance:*` clauses with them. The corpus note `observability/80803133` (filed 2026-09-13, after the
design) corroborates R14 from the requirement's own last sentence and names phase 6a's emitter for the
per-attempt group. The nine groups the design ran at planning are recorded there; at implementation the
four it names for the plan were re-checked against the built code:

| Group | Result at implementation |
|---|---|
| Public API surface | `module-organization/1828a984` (one public constant per file) holds for all six files, `meter.rb`'s one public constant being `NO_METER`; `api-design/b0e18938` is why the instruments, the no-op classes and the slot key are private and every public name is in P5-40, P5-41 or P5-71–P5-76; `api-design/88e6bf12`'s narrowest duck type is every protocol as an RBS `interface`, with `_Span & Object` where identity is compared |
| RBS / Steep typing | Ten mirrors touched (six new, four widened), the strict target green; `def self?.` for `Tracing`'s five; `?{ }` on the private `NoTracer#in_span` only; `type-system/545949a5` still governs `TraceIdFlavour`, extended by a method and no member |
| Minitest conventions | Every suite subclasses `DexpaceTestCase`, every raise is asserted on the raised object and never with `assert_nothing_raised`, `assert_same` wherever identity is the claim, every `Fiber[]` slot restored in a `teardown` shared by the nested classes through a module, and four suites split into nested classes under `Metrics/ClassLength` |
| Fiber scheduler, thread safety | Clean against the built code: no mutex, no thread started in `lib/`, no wait, no `Timeout.timeout`, `Thread#raise` or `Thread#kill`; every singleton frozen and stateless; the one `Fiber[]` slot immutable-valued; `Thread.current[]` written nowhere |

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate. Items 1–9
are where the built tree overrode the plan's assumptions, in the order the brief's as-built list gives
them; the rest are this build's, and the ones that touch public behaviour are also ledger rows P5-71–P5-76.

1. **This was the 5c-first execution and `diagnostics.rb` did not exist**, so Task 1 created it with
   exactly the three constants, its `sig/` and `test/` mirrors, and its `require_relative` line in
   `lib/dexpace.rb` before `scope` and `tracing` — the line the plan's Task 12 says "is 5b's to add"
   (P5-71). Task 11's subprocess runs unchanged against the file list.
2. **The four phase-4a files were widened in place**, their `sig/` interfaces filled where 4a left them
   empty and the "empty on purpose" comments rewritten; no declaration moved, and 4a's `no_span_test.rb`
   and `no_tracer_test.rb` pins went from "responds to nothing beyond `Object`" to the exact protocol.
   The plan's Task 2 fence printed `TraceIdFlavour` with three members and no `max_value`; the built
   type has four, `renderable?` and the Datadog bound, all kept.
3. **Boundary 10's five prohibitions are asserted, not stated**: `Bundle.members` is the same eight, the
   three singletons `equal?` `Bundle::NONE`'s, `TraceIdFlavour::NONE`'s sentinel `"0" * 32`.
4. **The keyword-splat cop already exists** — `Dexpace/NoKeywordSplat`, phase 0's, scoped to
   `gems/*/lib/**/*.rb` — and was verified live with a scratch `**attributes` method under the honest
   RuboCop before any code was written; the design's finding is closed as built (below).
5. **Eight custom cops, and 5c adds none**; cop cases were not needed. RuboCop 1.91.0 with
   `NewCops: enable` makes `Style/OneClassPerFile` live, which the namespaced doubles satisfy.
6. **The doubles keep the plan's `Dexpace::Recording*` names** against the tree's top-level convention
   (P5-73), because 5b's plan consumes them by those names.
7. **The surface manifest is `test/fixtures/surface/dexpace-core.txt` at the repository root** and the
   walker holds `Data` readers; the 42-row diff was derived before the one `surface:regenerate` and read
   against it.
8. **No new `private_constant` file**: the six new no-op classes and the slot key live inside the six
   files, so `CLAUDE.md`'s six test-mirror exceptions stay six; `sig/` is 110 mirrors for 110 `lib/`
   files under `lib/dexpace/`.
9. **The full nesting form everywhere**, never `module Dexpace::Instrumentation`; verified by grep.
10. **`Fiber[:k] = nil` does not delete on 3.2.11**, so the plan's Task 1 fallback for a failing fact 4 —
    "a per-key `key?`-guarded restore that deletes explicitly" — could not be taken: the floor has no
    delete. The restore stays branchless and the floor's residual is P5-72; the two `key?` assertions
    the design prescribes are floor-aware through `FiberStorageFacts`.
11. **`Fiber["k"]` raises `TypeError` on 3.2.11 and 3.3.12**, narrowing the design's fact 3 and the
    corpus note `fd68a018`; a new corpus entry and the roadmap's thirty-ninth inbound bullet carry it.
12. **`Tracing` is `extend self`, not `module_function`**: the reviewed baseline's
    `Style/ModuleFunction: extend_self`. Its RBS is `def self?.` and types the span as `_Span & Object`.
13. **`#generate_trace_id`'s seam is `#hex` and `#random_number` only**, without the plan's
    `respond_to?(:hex)` fallback to `#bytes`; the coercion is a substitution (the plan's reading).
14. **Two support helpers beyond the four doubles**: `allocation_delta.rb` (one two-loop delta shared by
    five suites) and `fiber_storage_facts.rb` (the probes and the two floor-aware assertions).
15. **`Scope.build` public with `@api private`** (P5-74); `CallableAdapter` validates at construction
    and returns `nil` from every callback (P5-75); `NO_TRACER#in_span` returns `NO_SPAN` without a block
    (P5-76); `Bundle#sampled?` is `trace_flags.hex.allbits?(1)` (`Style/BitwisePredicate`).
16. **Task 11's subprocess spawns `RbConfig.ruby`, not `bundle exec`**: core needs no gem, so the
    subprocess runs identically on every matrix row; it also asserts the exact thirteen constants under
    `Dexpace::Instrumentation` and that `Configuration` is undefined.
17. **The plan's Task 1 fence defined its sample methods inside the test body**; they are class methods
    of a nested class, and its fact-5 `Data` measurement is 3003 per 1000 on 4.0.6 (2002 elsewhere), so
    the assertion is "at least two", not "two".
18. **Test file counts**: the plan's Task 2 test went into 4a's `trace_id_flavour_test.rb` as a
    `GenerationTest` nested class and `#sampled?` into `bundle_test.rb`'s `SampledTest`, keeping the
    one-file-per-`lib`-file mirror; `ordering_test.rb`, `independence_test.rb` and
    `tracing_matrix_facts_test.rb` are the three without a mirror.
19. **The plan's Task 1 said `mise exec ruby@3.2.11`**; the matrix rows were run by putting each
    interpreter's `bin` first on `PATH` with a fresh `Gemfile.lock` per interpreter, on 3.2.11, 3.3.12
    and 3.4.10, as `CLAUDE.md` prescribes.
20. **The three phase-5c documents were cut from `main`, not a sibling's tip**, and the counts (six
    `lib/` files, one hundred and nine under `lib/dexpace/`, nine checklists, 772 manifest rows) are
    derived on top of what `main` at `993c439` states; 5a's lane edits the same sentences and the
    manager's rebase-and-reprove pass reconciles them.
21. **The fact-6 openssl assertion measures in a scrubbed subprocess**, not in the suite's process
    as the plan's fence had it: in `test:gems`'s shared process on 3.4.10, and in any child that
    inherits `bundle exec`'s `RUBYOPT`, openssl is loaded by something other than `securerandom`, so
    the in-place read was order-dependent and the child without the scrub inherited bundler's own
    requires. Found by the tests tip's 3.4.10 matrix row; fixed in the tests commit, with the four
    rows re-run green.

## Findings routed

- **The keyword-splat cop, the design's first finding, is VERIFIED CLOSED as built**: phase 0 ships
  `Dexpace/NoKeywordSplat` over `gems/*/lib/**/*.rb`, and a scratch `def add_event(name, **attributes)`
  under `gems/dexpace-core/lib/` produced `Dexpace/NoKeywordSplat: **attributes allocates a Hash on every
  call, even one passing no keyword, which OBS-25 forbids on a no-op path. Name each keyword (attributes:
  nil) instead.` on the honest run (guard 4 repeats it). Nothing re-routed; P5-42 stands as the segment's
  own record.
- **The tracer-factory name collision, the design's second finding, stays on phase 10's inbound list**
  (the bullet "Per-operation tracer factory names two different objects"), verified present; the corpus
  note `observability/80803133` restates it. Nothing re-recorded.
- **The unreachable context bundle (phase 6a, Task 8), the charter's `OBS-24` arithmetic (corrected in
  the charter) and the `OBS-29` wiring (phase 6a Task 9 and the inbound list)** all sit with their owners,
  verified; `Tracing.correlate`'s `bundle.valid?` guard is the code half of the first.
- **New: the two floor facts** — routed as the roadmap's thirty-ninth inbound bullet (documentation half
  against 5b's `P5-23` sentence, 8b's `ASYNC-9`/`ASYNC-11` sentence and the charter's fact 1) and as a
  new entry in `docs/knowledge/notes/observability.md`, which 5b's and 8b's phase-start queries surface.
  Nothing else to route: `docs/first-release.md`'s two cited entries already read true and gain no line.
- **The design's ledger** gains an "As built" addendum (P5-71–P5-76); the consolidation of P5-40–P5-50 and
  P5-71–P5-76 into design §10 and the §8.1 addendum are a human's, as for 3a, 3b, 4a, 4b and 4c, because
  `docs/sdk-design-ruby/` is frozen. No frozen-chapter sentence is contradicted, so `docs/first-release.md`'s
  `C1`–`C14` paragraph gains no `C15`.

## Postponed work

The items the design dispositioned keep their owners, and the three the plan's Task 12 records have landed
or been read: **the no-op span and tracer protocols phase 4a postponed are complete** (Tasks 3, 4 and 5;
the five prohibitions honoured item by item, above); **`SEAM-28`'s consumer is supplied** (Task 4; the
identifier is 4a's `RequestContext#operation_name`, the consumer `_TracerFactory#tracer`'s `name`, read
out of appendix C because the ID exists only there); **presence-gated auto-activation's condition was read
and found NOT met** (R15: `SEAM-2` enumerates five seams and instrumentation is not one; 5c registers
nothing and adds no fourth registry, and phase 2's absence test stays green) — not met-and-declined, and
`docs/first-release.md`'s entry already records this reading. `OBS-32` stays post-v1 under the
`OBS-32`/`OBS-37` entry; the `OBS-29` wiring stays with phase 6a Task 9 and the inbound list; `SEAM-24`'s
half stays post-v1; `dexpace-conformance`'s restatement of the allocation and idempotence assertions is
phase 8a's (Tasks 4–8 and 20), which `test/support/allocation_delta.rb`'s comment is written for; the
fakes' move to that gem stays declined (six more doubles and helpers strengthen the case without meeting
it). The implementation postponed nothing further.
