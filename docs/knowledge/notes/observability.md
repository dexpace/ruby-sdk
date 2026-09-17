# observability — notes

Hand-written. `../harvested/observability.md` is what the documents say; this file is what the
implementation found, and it wins. Each entry names the harvested entry it answers by that entry's
stable key.

## Superseded
- **Fiber storage is the diagnostic-context carrier across the whole supported range, its inheritance is copy-on-write, and it is not where `CTX`'s execution context lives.** Supersedes `observability/e0f1e864` ("Verified behaviour: `Fiber[:key]` is inherited by a child fiber, by a newly created `Thread`, and by an `Enumerator`'s internal fiber, while `Thread.current[:key]` — despite its name — is fiber-local and visible in none of them"), which carries **no version qualifier at all** and omits the half a phase most needs. Re-verified on 2026-09-08 against 3.2.11, 3.4.10 and 4.0.6, one case per claim: on all three, `Fiber[:k]` set in the main fiber is visible inside `Fiber.new { }`, inside `Thread.new { }` and inside an `Enumerator`'s internal fiber, while `Thread.current[:k]` is `nil` in all three of those places. Two properties the entry does not record and a design leans on: **inheritance is copy-on-write** — a write inside a child fiber does *not* escape to the parent, so a per-request context installed on a worker cannot leak back into the pool's own storage — and **`Fiber.new(storage: nil)` opts out entirely**, yielding an empty map. That last one is an *opt-out at fiber creation* and must not be mistaken for `ASYNC-11`'s clear: `ASYNC-11` is about **reinstating** an empty captured context into a target that already has one ("reinstating an empty context clears the target thread's context rather than raising an error"), which is a pooled worker's restore path, not a fresh fiber's. The write side of that path is `Fiber#storage=`, which is a separate and less comfortable fact — see this file's `## Reference` entry on that setter. `Fiber#storage` reads the whole map on all three. The version widening matters for the same reason it mattered for `../notes/pagination.md`'s `Enumerator` entry and design §3.5's `URI::DEFAULT_PARSER` pin: `Fiber[]` was introduced in 3.2, which is `required_ruby_version`'s floor, so an unqualified claim about it is exactly the shape that passes where you look and fails where you do not. It does not; the behaviour is uniform. **The boundary this note also draws, because two near neighbours have opposite designs.** Fiber storage carries the *diagnostic* context of `OBS-10`, `OBS-23`, `OBS-24` and `ASYNC-8`–`ASYNC-12` — phases 5 and 8. It is **not** where the *execution* context of `CTX-1`–`CTX-20` lives: `CTX-7` and `CTX-11` require a process-wide store that is thread-safe across distinct call keys and **bounded**, with `CTX-19` forbidding weak references and naming the cap as the only sanctioned leak backstop, so `docs/sdk-design-ruby/05-pipeline-architecture.md` §5.4 makes it a plain `Hash` behind a `Thread::Mutex` keyed by call key. Putting the context store in fiber storage would defeat the cap and the reachability requirement at once, and it is a natural mistake because `CLAUDE.md`'s constraints list files the fiber-storage fact under the heading of diagnostic context while the roadmap's phase-4 material is the only place a context store is discussed. Recorded per `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md`. `observability/9f7aa009` is unaffected and is adopted verbatim.
  <sub>review · `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md` · high · sha:manual-phase4-fiber-storage-range</sub>
- **Fiber storage's copy-on-write protects the *slot*, not a mutable object held in it, and the two write APIs disagree about key types.** Narrows `observability/e0f1e864` a second time, and with it this file's first `## Superseded` entry, which added to that harvested rule the property that "**inheritance is copy-on-write** — a write inside a child fiber does *not* escape to the parent". That is true of a **rebinding** and false of a **mutation**, and the difference decides a design. Verified 2026-09-09 on `ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]`, the only interpreter installed on this machine, so this entry is **single-interpreter and must be re-run on 3.2.11 and 4.0.6** before anything rests on it — unlike the entry above it, which was run across all three. With `Fiber[:mutable] = []` set in the parent, a `<<` inside `Thread.new { }`, inside `Fiber.new { }` and inside an `Enumerator`'s internal fiber all landed in the parent's Array — contents `[:thread, :fiber, :enumerator]`, and `object_id` identical across the thread boundary — while `Fiber[:immutable] = :parent` rebound to `:child` in the same three children left the parent's slot at `:parent`. So a **span stack, a counter, or any mutable collection in a `Fiber[]` slot is one shared object across every thread and child fiber descended from the fiber that created it**, which is `XCUT-11`'s "any shared mutable state MUST be synchronized" with no synchronisation and is invisible in a single-threaded test; only an immutable value in the slot gets the isolation the copy-on-write phrase suggests. The second half is about the write side the entry above points at this file's `Fiber#storage=` reference entry for: **`Fiber.current.storage = {"trace.id" => "x"}` raises `TypeError: wrong argument type String (expected Symbol)`, while `Fiber["trace.id"] = "x"` succeeds and stores under `:"trace.id"`** — the per-key setter coerces a `String` key to a `Symbol`, the whole-map setter refuses one, and `Fiber.current.storage` hands every key back as a `Symbol` whichever setter wrote it. The consequence for `OBS-10`, `OBS-23`, `OBS-24` and `ASYNC-8`–`ASYNC-12`: the diagnostic-context key space is `Symbol`-shaped at the carrier's own API; a published key constant declared as a frozen `String` is not directly usable with `Fiber#storage=`, which is the whole-map call `ASYNC-9`'s pooled-worker restore may have no way to avoid; and a fold converting a storage key to an `OBS-39` field key must use `Symbol#name`, which returns the same frozen `String` on every call, never `Symbol#to_s`, which allocates a fresh unfrozen one per call (measured 1 against 1001 per 1000 calls). `:"trace.id".name` is **not** `equal?` to a `"trace.id"` frozen literal, so the two spellings are two objects and one constant has to be the single source. Recorded per `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md` (verified fact 2, the slot-versus-object split) and `docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md` (verified facts 1 and 10, the key-type split); filed once by the pass that reconciled those two designs, because each declined to write it rather than clobber the other's edit.
  <sub>review · `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md` · high · sha:manual-phase5-fiber-slot-and-key-type</sub>

- **`OBS-29`'s emission wiring is a documented follow-up and not a runtime obligation, and the clause
  that says so lives in appendix C's row and in no chapter — so the harvested rule, and every document
  derived from chapter 15, states the requirement short.** Corrects `observability/2da9e2f3`, which ends
  at "with one tracer instance corresponding 1:1 to a single logical operation" and is exact about its
  source: `docs/product-spec/15-instrumentation-and-observability.md:54` ends there too. **Appendix C's
  `OBS-29` row does not.** It continues "(created by the factory per operation). **This is a documented
  emission contract; pipeline/transport wiring to emit it is a follow-up, so it is not yet
  runtime-enforced.**" Re-read verbatim 2026-09-13 from
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md`. The divergence runs both
  ways in the same pair — the chapter carries a `*Conformance:*` clause ("drive a succeeding and a
  failing (retry-exhausted) operation through a conformant emitter and assert the ordering and the
  exhausted→failed pairing") that appendix C drops — so **the two rows together are the only complete
  statement of `OBS-29`, and neither says so.** That is the same shape as appendix C's `SSE-19` row
  dropping the port sanction `docs/product-spec/13-server-sent-events-and-streaming.md:33` grants, and
  two instances make it a pattern rather than an anecdote; both are recorded in `docs/deviations.md`
  § Deviations found outside a phase for a human to amend, since `docs/product-spec/` is frozen.
  **What the clause decides, and what it cost that it was missed.** `OBS-29` conditions its own
  enforcement: the SDK owes a *documented* ordering contract, and wiring an emitter is explicitly a
  follow-up. Phase 5c ships the eleven-method vocabulary, the shared no-op and an ordering test, and
  phase 6a emits the per-attempt group through `http_tracer_factory:` called with `cursor` — so the MUST
  is met, and the operation-lifecycle triple and transport-milestone group having no wired emitter in v1
  is conforming rather than a gap. Five documents across four phases (5b, 5c, 6a, 8a and the roadmap's
  phase-10 inbound list) reasoned from `docs/sdk-design-ruby/08-instrumentation-and-configuration.md`
  §8.1's restatement of the chapter, which cannot carry a clause the chapter does not have, and carried
  an "open surface decision" — a new step at `Stages::PRE_REDIRECT`, and/or a widening of
  `RequestOptions` — that the requirement had already closed. Nothing was built wrongly: every one of
  those phases declined the wiring, 6a under its `R15` and 8a as `P8-7`. What it cost is that the
  decision travelled as open through five documents and one register retirement, and that a phase with a
  repair budget could have spent it widening a public surface `NFR-4` would then lock with no caller —
  which is the `Event#tag` mistake (`P5-18`) in a second place. **The second thing this entry fixes,
  because the same paragraph is where it hides.** "Per-operation tracer factory" names **two** objects
  and the two are not interchangeable. `CTX-14` (MUST) puts a factory on the correlation bundle;
  `OBS-25` (MUST) requires "a no-op HTTP-tracer / tracer-factory" and that "Selecting a no-op path MUST
  NOT allocate per call", so a no-op factory returns the **same object every time** — the opposite of one
  instance per operation — and phase 4a's `P4-8` bound `Bundle#tracer_factory` to `opentelemetry-api`'s
  `TracerProvider` shape, `#tracer(name = nil, version = nil)`, keyed by instrumentation-library name and
  version. So the bundle's factory produces **span** tracers (`OBS-21`–`OBS-25`) and is legitimately
  shared or cached, while `OBS-29`'s produces **HTTP-tracers** (`OBS-28`'s eleven-method vocabulary) and
  is legitimately per operation. Appendix C, design §8.1, phase 5c's Tasks 3–5 and phase 4a's `R3` all
  read them as one object; phase 5c's `P5-43` reconciles the no-op case only and says nothing about a
  recording one. `observability/4044a5c7` is unaffected and adopted verbatim — the duck-typed listener it
  describes is the same vocabulary. This file's two other `## Superseded` entries
  (`sha:manual-phase4-fiber-storage-range` and `sha:manual-phase5-fiber-slot-and-key-type`) are about the
  diagnostic-context carrier and are untouched by this one; they are named by marker rather than by key
  because a backticked key must resolve to a harvested entry, and a note's own key is not one.
  <sub>review · `docs/work/mvp/phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness-design.md` · high · sha:manual-phase10-obs29-follow-up-clause</sub>
- **The per-key fiber-storage API is not uniform across the supported range: `Fiber[:k] = nil` deletes
  the key on Ruby 3.3 and later and RETAINS it with a `nil` value on 3.2, and `Fiber["k"]` interns a
  `String` key on 3.4 and later and raises `TypeError` on 3.2 and 3.3.** Narrows `observability/e0f1e864`
  a third time, on the write side, and is the re-run this file's second `## Superseded` entry
  (`sha:manual-phase5-fiber-slot-and-key-type`, single-interpreter on 3.4.10) asked for before anything
  rested on it. Measured 2026-09-17 by phase 5c's implementation on 3.2.11, 3.3.12, 3.4.10 and 4.0.6, one
  script per interpreter and then as a standing test
  (`gems/dexpace-core/test/dexpace/instrumentation/tracing_matrix_facts_test.rb`, which pins both
  boundaries against `RUBY_VERSION` so a patch release that moves either fails the matrix). **(1)** After
  `Fiber[:k] = "v"; Fiber[:k] = nil`, `Fiber.current.storage.key?(:k)` is `false` on 3.3.12, 3.4.10 and
  4.0.6 and **`true` on 3.2.11**, where `Fiber.current.storage` reads `{k: nil}`; `Fiber[:k]` reads `nil`
  on every row, a child fiber and a new thread inherit the nil-valued key on 3.2, and the floor offers no
  other removal -- its whole `Fiber` API is `[]`, `[]=`, `storage` and `storage=`, and the returned storage
  is a copy whose mutation changes nothing -- so the one way to remove a key on 3.2 is the warned whole-map
  setter this file's `## Reference` entry records. Phase 5c's design read "`Fiber[:k] = nil` deletes the
  key" as a fact of the range (its verified fact 4, the charter's fact 1); it is a fact of 3.3 and later.
  **(2)** `Fiber["dexpace.probe"] = 1` and the read `Fiber["dexpace.probe"]` both raise
  `TypeError: wrong argument type String (expected Symbol)` on 3.2.11 and 3.3.12 and intern to
  `:"dexpace.probe"` on 3.4.10 and 4.0.6, so the entry above's "the per-key setter coerces a `String` key
  to a `Symbol`" holds from 3.4 only; `Fiber#storage=` refuses a `String` key on every row, as it said.
  **What follows.** For `OBS-23`, phase 5c's per-key restore stays branchless -- "restore each key to its
  prior value (or remove it if previously unset)" is one assignment on 3.3+ and, on the floor, a
  present-and-`nil` key that `Fiber[]` reads identically and that `OBS-10`'s "Keys with null values MUST be
  skipped" folds identically, which is exactly the state its `P5-49` already argues about from the other
  direction; the as-built row `P5-72` records the floor half, and no core file calls the warned setter.
  For `OBS-24`'s union restore (5b's `P5-23`) and `ASYNC-9`/`ASYNC-11`'s pooled-worker restore (8b), the
  same holds: a per-key restore returns a 3.2 worker to a map of nil-valued keys rather than to an empty
  map, indistinguishable at every reader that skips nulls and visible only through `Fiber.current.storage`
  itself; both plans were written on the 3.4.10 fact and are audit work for phase 10 (the roadmap's inbound
  list, the thirty-ninth bullet). For the key TYPE, this settles `R11` harder than the reconciliation
  did: a `Symbol` is the one spelling every carrier API accepts on every row, and a frozen-`String` key
  constant would have raised on the floor at the first `Fiber[]=`, not merely at the whole-map setter.
  Read-side inheritance, copy-on-write per slot, the warned setter's per-call warning and the
  `storage = nil` divergence all re-measured as the entries above and below record.
  <sub>review · `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-checklist.md` · high · sha:manual-phase5c-fiber-nil-and-string-key-floor</sub>

## Reference
- **A pooled worker inherits the *pool creator's* fiber storage and sees nothing set afterwards, so a
  merge-shaped context install leaks assembly-time context into a caller's task.** Beside
  `observability/e0f1e864`, and specifically beside this file's second `## Superseded` entry over it
  (`sha:manual-phase5-fiber-slot-and-key-type`), which records that copy-on-write protects the slot and
  not the object in it; this is the other half of the same write-side story and it decides an
  implementation. Measured on Ruby
  3.4.10: `::Thread.new` inherits `Fiber[]` at the moment the thread is created, and a worker created
  before a key was set reads `nil` for it — so a pool's workers carry whatever the fiber that called
  `Pool.build` happened to hold, and nothing the caller does later reaches them. Phase 5b's
  `Diagnostics.with` merges on install (`snapshot.each { |k, v| Fiber[k] = v }`), which is exact for its
  own consumer and for `OBS-24`; on a pooled worker the merge leaves the inherited keys visible underneath
  the caller's snapshot, so a pool built under `Fiber[:tenant] = "assembly"` runs a caller's task with
  `tenant: "assembly"` on its log lines. That is `ASYNC-10`'s "a stale snapshot from when it was
  assembled", and it is invisible in any test that builds the carrier in the same context it submits from.
  `dexpace-async-thread` fixes it for itself with one line at worker start —
  `::Fiber.current.storage&.each_key { |k| ::Fiber[k] = nil }`, safe because `Fiber.current.storage`
  returns a fresh `Hash` — after which merge and replace agree and the union restore returns the worker to
  empty. **The rule generalises to any long-lived carrier this repository creates with `::Thread.new`**: a
  background exporter, a second executor adapter, or a caller's own worker wrapped in `Diagnostics.with`.
  Neither `Diagnostics.with` nor design §8.1 needs changing; what needed stating is that the carrier must
  start empty.
  <sub>review · `docs/work/mvp/phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter-design.md` · high · sha:manual-phase8b-pooled-worker-context-floor</sub>
- **`Fiber#storage=` is the only whole-map write side `ASYNC-9`/`ASYNC-11` can use, it warns on every
  call on every supported Ruby, and it does not behave the same on the floor — so prefer per-key
  writes.** Beside `observability/e0f1e864` and this file's two `## Superseded` entries over it; it is
  the write-side fact the first of those points here for. Design §8.1 fixes the adapter's shape as
  "saves the worker's prior storage, installs the captured snapshot for the work's duration and
  restores it in an `ensure` (**ASYNC-9**)", with an absent context "capturing as empty and reinstating
  as a clear rather than a raise (**ASYNC-11**)". `Fiber[]=` writes one key; saving and restoring a
  *whole* map needs `Fiber#storage=`, and `Fiber.new(storage:)` cannot serve, because a pooled worker's
  fiber already exists when the task arrives. Two facts about that setter, verified 2026-09-08 on
  3.2.11, 3.4.10 and 4.0.6 via `mise exec ruby@<v>`. **(1) It warns on every call, on all three, and at
  the default warning level.** `Fiber#storage= is experimental and may be removed in the future!` is
  emitted **per call**, not once per process (two calls, two warnings, verified), and it appears with
  plain `ruby` as well as `ruby -w` — it is not gated behind verbose mode. This repository's gate set
  runs the real suite under `ruby -w` with **warnings failing the build**
  (`docs/sdk-design-ruby/09-toolchain-and-quality-gates.md` §9.2), so a per-task save/restore emits one
  warning per task and fails that gate. The warning's category is `:experimental`, so
  `Warning[:experimental] = false` silences it — but that is a **process-global** flag, and a library
  setting one on its host is the same imposition the port already refuses for `Regexp.timeout`
  (`CLAUDE.md`, design §4/§6.3), so it is not a fix an adapter may reach for unasked. The remaining
  routes are a scoped `Warning.warn` filter around the call or an `NFR-7` waiver carrying its reason;
  which one is right is the deciding phase's call, and neither is free. **(2)
  `Fiber.current.storage = nil` is not uniform across the range.** On 3.2.11 it leaves
  `Fiber.current.storage` as `{}`; on 3.4.10 and 4.0.6 it leaves it as `nil`. `= {}` yields `{}` on all
  three. So the obvious spelling of `ASYNC-11`'s "reinstating an empty context clears the target" reads
  back differently on the floor than on the rest of the matrix, which is exactly the shape of bug an
  unqualified version claim hides. **What follows for a phase that acts on this** — 5 for `OBS-10`,
  `OBS-23` and `OBS-24`, 8 for `ASYNC-8`–`ASYNC-12`: write per key (`Fiber[k] = v`), which warns
  nowhere and coerces a `String` key as this file's second `## Superseded` entry records, and reach for
  the whole-map setter only with one of the two routes above written down beside it. What is **not**
  claimed: that fiber storage is the wrong carrier. Read-side inheritance is uniform and copy-on-write
  across the whole range, re-verified in the same session and recorded in the entries above. Only the
  write side is in question. `CTX`'s execution-context store touches fiber storage nowhere and is
  untouched by this.
  <sub>review · `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md` · high · sha:manual-phase4-fiber-storage-setter</sub>
