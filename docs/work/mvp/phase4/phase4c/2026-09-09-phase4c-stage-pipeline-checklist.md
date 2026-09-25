# Phase 4c — Stage-Based Pipeline: Checklist

**Written at execution time, 2026-09-16, from what was built** — not from the plan. A row whose task
did not do what the plan said is a row that says so, and the "Deviations from the plan" section
below is where each departure is stated with its reason. The design was written on 2026-09-08 and
the plan on 2026-09-09, against phases 0–3's *plans* and 4a's and 4b's *designs*; phases 1, 2, 3a
and 3b were then built and merged (PRs #40–#52), phase 4b was built and is open as #53 → #54 → #55,
and this phase was cut from 4b's docs tip (`15-phase-4b-recovery-primitives-docs` at `6099c66`)
because the one thing it consumes, `Dexpace::Recovery::Transform`, lives there. Where the plan's
text and the built tree disagree the tree wins and this document records it. Phase 4a was built in
parallel in another worktree off `main`: nothing of 4a's is on this base, 4c names no 4a constant
anywhere, and the plan's "phase 4a's seventh" cop is not here — the seventh on this base is phase
2's `Dexpace/QualifiedCoreConstant`, and 4c adds no cop.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase4/phase4c/2026-09-09-phase4c-stage-pipeline.md`. Task numbers are that
plan's. Design: `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md`, whose
Deviation Ledger rows `P4-26`–`P4-39` and as-built rows `P4-50`–`P4-59` are cited below; the
charter is `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md`. Every test file named
here is under `gems/dexpace-core/test/`, mirrors its `lib/` file one for one, and opens with the IDs
it exercises.

## Requirement rows

Forty own rows — `PIPE-1`–`PIPE-40` — plus the seven cross-reference rows for the non-`PIPE` IDs
this phase owns a share of, taken from the design's interface-surface table the way 3b carried
`HTTP-46` and `HTTP-3` and 4b carried its seven: `REDIR-11` and `AUTH-29` (the cursor-state
mechanism phase 6's cross-origin marker is built on), `XCUT-11` (the audited immutability of the
two runtimes), `NFR-11` (the two RBS interfaces' named home), `SEAM-18` (the bridges composed, not
rebuilt), and `TRANSPORT-1` and `TRANSPORT-2` (the premise phase 8 disables a native client's own
redirect and retry under). Thirty-seven ✅, one ✅ in part with its unmet clause ⏳ (`PIPE-33`,
§10.5), one ⏳ declined (`PIPE-36`), one ⏳ postponed in half (`PIPE-39`, phase 6b Task 13a),
nothing 🚫, nothing N/A.

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `PIPE-1` | MUST | ✅ | 2, 7, 8 | Cross-stage order derives from `Stages::ALL`'s position and from nothing else: `Builder#entries` is `Stages::ALL.filter_map { @buckets[stage] }.flatten(1)`, and there is no accumulated order to consult. The requirement's own conformance clause is run verbatim — fifteen `ProbeStep`s, one per installable stage, installed in a **shuffled** order under `Random.new(42)` with the order printed on failure, and the entry log equals the fifteen stages in order with the exit log its exact reverse (`dexpace/pipeline_test.rb`); a two-stage version asserts `PRE_REDIRECT` before `POST_SERDE` whatever was appended first (`pipeline/builder_test.rb`). The guard that flattens an insertion-order list instead fails the shuffled test with the install order in its message |
| `PIPE-2` | MUST | ✅ | 2, 8 | `Stages::ALL` is `PRE_REDIRECT, REDIRECT, POST_REDIRECT, PRE_RETRY, RETRY, POST_RETRY, PRE_AUTH, AUTH, POST_AUTH, PRE_LOGGING, LOGGING, POST_LOGGING, PRE_SERDE, SERDE, POST_SERDE, SEND`, asserted as a list of names (`pipeline/stages_test.rb`), and the requirement's own conformance clause is run: under a `ForkingProbe` at `REDIRECT` driving twice, a `PRE_REDIRECT` probe runs **once** and an `AUTH` probe **twice** — the assertion that fails if the outermost slot were inside the redirect loop (`dexpace/pipeline_test.rb`). `SERDE` is a reserved pillar with no shipped behaviour, as the requirement says. Every `Stage` the builder or an `Entry` holds is one of the sixteen constants **by identity**: a `dup`, `clone` or `Marshal` copy — `==` and not `equal?`, public on every `Data` — resolves through `Stages.of` at `Builder#resolve` and `Entry.build`, so the two identity comparisons the builder makes over stages hold whatever copy a caller handed in (review round 0, R0-2; deviation 25 below; P4-58) (`pipeline/builder_test.rb`, `InputTest`; `pipeline/entry_test.rb`) |
| `PIPE-3` | SHOULD | ✅ | 2 | Taken literally (P4-31): a pre and a post slot around each of the five pillars, `PRE_REDIRECT` doubling as PIPE-2's outermost slot, sixteen stages, order keys sparse by exactly 100 and asserted as `(1..16).map { _1 * 100 }`. The ALL-versus-`#order` assertion — ALL is a hand-written frozen Array and `#order` is a public member nothing at run time reads — is what catches a stage inserted at the wrong index or given an out-of-sequence key; the guard that swaps `PRE_AUTH` and `AUTH` in ALL fails it (`pipeline/stages_test.rb`) |
| `PIPE-4` | MUST | ✅ | 2, 7 | `Stage#pillar?` is true for exactly six stages, `PILLARS` is the five configurable ones in precedence order with `SEND` excluded, and `Builder` admits at most one step per pillar on every install path: `#append`, `#prepend`, the two surgical inserts, and — over the incoming set — `#reload` and `#install_preset` (`pipeline/stages_test.rb`, `pipeline/builder_test.rb`) |
| `PIPE-5` | MUST | ✅ | 7 | A distinct second step onto an occupied pillar raises `Dexpace::PipelineError` with the fixed form `pillar retry is already occupied by ProbeStep; cannot install ProbeStep (use #replace to substitute) (PIPE-5)` — both types named, the replace path pointed at — from `#append`, `#prepend` and `#insert_after`, and the bulk path raises its own form naming both types (`pillar retry would hold 2 distinct steps (ProbeStep, ProbeStep); a pillar admits at most one (PIPE-4, PIPE-5; rejected whole per PIPE-23 and PIPE-24)`). Distinctness is `#equal?`, never `==`: the fixture is two `ProbeStep`s over **one shared log**, `==` and not `equal?`, and the `==` guard fails that test with "nothing was raised" on 4.0.6 and 3.2.11 — and, since review round 0, fails the surgical-path test the same way, where a value-equal twin of a pillar's occupant collides through `#insert_after` too. A cross-stage `#replace` fails with PIPE-18's distinct message, never this one (`pipeline/builder_test.rb`) |
| `PIPE-6` | MUST | ✅ | 3, 7 | Re-installing the **same object** onto its pillar is a no-op with `entries` unchanged, on `#append`, on `#insert_after` / `#insert_before` beside itself — the path review round 0 found raising PIPE-5 with the same type named twice, repaired so the one predicate `#same_occupant_of?` answers for every install path (R0-1; deviation 24 below) — and on the bulk path where the same step twice collapses to one entry; `install_preset` treats a pillar the same object already occupies as not a collision. `ProbeStep` is a `Data` deliberately (verified fact 3), and `pipeline_doubles_test.rb` proves the fixture's own property: two probes over one shared log stay `==` across execution, two over separate logs stop being `==` the moment one runs (`pipeline/builder_test.rb`, `support/pipeline_doubles_test.rb`) |
| `PIPE-7` | MUST | ✅ | 7 | `#append` to the tail and `#prepend` to the head of a non-pillar bucket, `[c, a, b]` after two appends and a prepend; within-stage order survives `#reload` (`[b, a, c]` from a set given in another stage order) and every re-bucketing edit (`PIPE-22`'s row) (`pipeline/builder_test.rb`) |
| `PIPE-8` | MUST | ✅ | 2, 5, 7 | `Stages::SEND` is `pillar?`, `terminal?` and not `installable?`; `Entry.build` — the one place every install funnels through — raises `cannot install step at terminal stage SEND (PIPE-8)` for it, by `Stage` or by name, and flattening skips it because SEND has no bucket at all. The guard that drops the check in `Entry.build` fails two tests (`pipeline/stage_test.rb`, `pipeline/entry_test.rb`, `pipeline/builder_test.rb`) |
| `PIPE-9` | MUST | ✅ | 8, 10 | `Pipeline#call` returns `@transport.call(request, options, cancellation)` before anything else when the entry table is empty; `AsyncPipeline#call` reaches the driver's normalised `#dispatch` the same way. The request, options and token arrive by identity, and the trailing SHOULD is asserted as a **non-allocation**: under `GC.disable`, `ObjectSpace.each_object(Cursor).count` before and after one send through `.direct` is a delta of zero, counting the cursor class's instances so GC noise cannot flake it, CRuby-only and skipped elsewhere (phase 3a's `IO-38` postponement). The guard that removes the empty branch fails with `Expected: 0 Actual: 1` (`dexpace/pipeline_test.rb`, `dexpace/async_pipeline_test.rb`) |
| `PIPE-10` | MUST | ✅ | 6, 8 | The runtime holds a frozen entry table, a frozen step view and a write-once transport, exposes no writer (`public_instance_methods(false).grep(/=\z/)` empty on both runtimes), has no `#with` and a private `new`, and a builder mutated after `#build` does not reach it. Not `Object#freeze`d, because `PIPE-27`'s latch writes an ivar (plan open question 8). Each send allocates its own cursor: a one-step pipeline's `ObjectSpace` delta is at least one, and sixteen threads sending through one shared step are handed sixteen distinct cursors, collected by identity, with sixteen responses back (`dexpace/pipeline_test.rb`, `dexpace/async_pipeline_test.rb`) |
| `PIPE-11` | MUST | ✅ | 4, 6, 8 | The step protocol takes the cursor as its second argument and a step holds no per-call state; `Cursor`'s YARD states that per-call state is passed as an argument and never read from `Fiber[]` or `Thread.current[]`. The sixteen-thread test is the concurrency half (`pipeline/step_test.rb`, `dexpace/pipeline_test.rb`) |
| `PIPE-12` | MUST | ✅ | 4, 6 | `Step.conforms?` accepts a two-argument lambda, a proc (whose parameters report `:opt`), an object with a two-argument `#call`, a bound `Method`, a rest-parameter callable and one with a trailing optional; rejects zero-, one- and three-argument callables, a required keyword and a non-callable. A short-circuiting step at `PRE_AUTH` returns a synthetic response without calling the cursor, and neither the downstream step nor the transport runs (`pipeline/step_test.rb`, `pipeline/cursor_test.rb`) |
| `PIPE-13` | MUST | ✅ | 6 | `Cursor#call` advances to the entry at its position and invokes it with a cursor bound to that entry at the position after it; past the last entry the driver dispatches to the transport with the in-flight request, the options and the token by identity. Forward-only: a second sequential `#call` raises `cursor has already been invoked and cannot be reused (PIPE-15)` and `#spent?` is true, asserted on the raised object. The guard that removes the latch fails with "nothing was raised" on 4.0.6 and 3.2.11 (`pipeline/cursor_test.rb`) |
| `PIPE-14` | MUST | ✅ | 6 | `#call(request)` takes the request as its argument and the child cursor carries **that** object, so a substitution at `PRE_RETRY` reaches `RETRY`, `POST_AUTH` and the transport by identity with the original absent from every observation; the guard that passes the cursor's own `@request` to the driver instead fails with `Expected "original_request" to be the same as "substituted_request"` (`pipeline/cursor_test.rb`) |
| `PIPE-15` | MUST | ✅ | 3, 6 | `#fork` is the fork primitive and `ForkingProbe` is the pillar step that uses it — for **every** drive including the first, never calling its own `#call` (P4-39). Reuse is a defect the runtime raises on: a second `#call` raises, `#fork` on a spent cursor raises `cursor is spent and cannot be forked; #call and #fork are disjoint (PIPE-15)`, and a slot step's `#fork` raises `stage pre_auth is not a configurable pillar and cannot fork (PIPE-15)` with `#may_fork?` answering false first. The three guards — the latch removed, the spent check removed, the pillar gate opened — each fail exactly one test. Detection is **sequential-only** (P4-33), stated in `#call`'s and `#fork`'s YARD; no test asserts the race, by design (`pipeline/cursor_test.rb`) |
| `PIPE-16` | MUST | ✅ | 6 | A fork resumes from the parent's position, carries the parent's request, options and token by identity, and advances independently: under a twice-forking `REDIRECT` the `AUTH` probe is invoked once per drive with two distinct cursors, both spent afterwards. The guard that has `#fork` return `self` fails four tests; the guard that has the driver bind the child at `position + 2` fails three (`pipeline/cursor_test.rb`) |
| `PIPE-17` | MUST | ✅ | 6, 8 | The options object is `assert_same` at every step, at both forks and at the transport — never `assert_equal`, which the per-fork-`dup` guard passes and which the real assertion fails with two `to be the same as` messages; `RequestOptions::EMPTY` is the default and the same frozen object arrives through both bridges (`pipeline/cursor_test.rb`, `dexpace/pipeline_test.rb`) |
| `PIPE-18` | MUST | ✅ | 5, 7 | `#insert_after` and `#insert_before` place next to the **first** anchor instance in flattened order (`[before, a, after, b]` over two probes), require the step's effective stage to equal the anchor's, and reject a cross-stage move with `cannot insert Proc declaring stage post_auth relative to anchor at stage pre_auth (PIPE-18)`, installing nothing. `stage:` is required for a non-declaring step rather than inferred from the anchor, or the rejection would be unreachable for a lambda (R10). A surgical insert onto an occupied pillar collides like an append, and the occupant beside itself is a no-op like an append (`PIPE-6`, review round 0's R0-1). The anchor is a type, or — the plan's 2026-09-13 amendment — a `Symbol` or `String` matching `Entry#name`, which is how one of two lambdas (both of class `Proc`) is addressed; the guard that matches a name anchor by type fails two tests. An anchor that is none of those — `42`, `nil`, an `Object` — is refused up front with `Dexpace::InvalidArgumentError: anchor takes a Module, Symbol or String, got Integer`, on an empty builder too, where Ruby's `TypeError: class or module required` out of `#is_a?` used to surface only once an entry existed to compare against (review round 0, R0-4; deviation 26 below; P4-59) (`pipeline/builder_test.rb`, `SurgicalTest` and `InputTest`) |
| `PIPE-19` | MUST | ✅ | 7 | `#replace` swaps the first anchor instance 1:1 in its own stage (`[fresh, other]`), substitutes a pillar's one occupant without a collision, and rejects a cross-stage replacement with PIPE-18's distinct message — a distinct *message*, one class (P4-37) — and never PIPE-5's (`pipeline/builder_test.rb`) |
| `PIPE-20` | MUST | ✅ | 7 | `#remove(type)` deletes every instance of the type across every bucket with relative order preserved, and is a silent no-op returning `self` when absent; `#remove(name)` removes the one entry it names. `remove(Proc)` empties a pipeline of lambdas, which is the requirement's own semantics (`pipeline/builder_test.rb`) |
| `PIPE-21` | MUST | ✅ | 7 | An insert or replace whose anchor has no instance raises `anchor step of type String was not found in pipeline (PIPE-21)`, or `anchor step named :absent was not found in pipeline (PIPE-21)` on the name path, and changes nothing (`pipeline/builder_test.rb`) |
| `PIPE-22` | MUST | ✅ | 7 | One flatten function over the stage table, so there is nothing else the order could be: a builder taken through `append_all`, `append`, `insert_after`, `remove` and `replace` has entries `==` to a builder seeded from scratch with the resulting set (`pipeline/builder_test.rb`) |
| `PIPE-23` | MUST | ✅ | 7 | `#reload` validates the whole set — every element an `Entry`, then pillar exclusivity **over the incoming set** with the same step twice collapsing — before a single bucket is cleared, so a rejected reload leaves `#entries` `==` to the snapshot taken before it, with no rescue and no copy. Two rejection tests: a malformed entry, and the one the requirement's sentence is about, a distinct second step for a pillar over two value-equal `Data` probes. The commit-before-validate guard fails both, the `==` guard fails the second (`pipeline/builder_test.rb`) |
| `PIPE-24` | MUST | ✅ | 7 | `#install_preset` shares `#reload`'s validate half, then checks every target pillar is empty **before** committing, and rejects the whole call naming **every** occupant — `cannot install preset: pillar retry is already occupied by ProbeStep; pillar auth is already occupied by Proc (PIPE-24)` — with the snapshot unchanged and `REDIRECT` still empty; a preset colliding with itself on a pillar is rejected on the shared path; empty pillars are filled and the same occupant is not a collision. The mechanism ships with no standard step set (R14, P4-34) (`pipeline/builder_test.rb`) |
| `PIPE-25` | MUST | ✅ | 7, 8 | `#build` and `#build_async` flatten `Stages::ALL` once, skipping SEND, into a runtime whose `#steps` and `#entries` are frozen Arrays built at construction and returned as the **same object** every call (`assert_same`), never a lazy enumerator; `<<` on the view raises `FrozenError` (`dexpace/pipeline_test.rb`, `dexpace/async_pipeline_test.rb`) |
| `PIPE-26` | MUST | ✅ | 8, 10 | `Transport.conforms?(pipeline)` and `AsyncTransport.conforms?(async_pipeline)` are true without either class declaring anything — `#call(request, options = EMPTY, cancellation = none)` is the SPI's three positionals (verified fact 2) — the one- and three-argument call forms both work, a built pipeline nests as another builder's transport with the options object surviving by identity, and `Dexpace::Builder.build_all` accepts the builder (`dexpace/pipeline_test.rb`, `dexpace/async_pipeline_test.rb`) |
| `PIPE-27` | MUST | ✅ | 8, 10 | Both runtimes include `Closeable` with `owned: false` and define no `#release`: `#close` twice latches (`closed?` true, `owned?` false), the transport's own `closed?` is still false — the negative is the assertion — and a closed pipeline still sends, because it released nothing. The guard that makes the runtime owning with a cascading release fails the test (`dexpace/pipeline_test.rb`, `dexpace/async_pipeline_test.rb`) |
| `PIPE-28` | MUST | ✅ | 2, 7, 10 | One `Stages`, one `Builder`, one `Cursor`; the runtimes differ by one `private_constant` driver handed over as a constructor argument (P4-30). One step set built through `#build` and `#build_async` yields entry tables equal stage-for-stage and step-for-step **by identity** over the whole table; the guard that reverses the async table fails it, and `REDIRECT` stays installable on the async path because PIPE-32 constrains the preset, not the runtime (`dexpace/async_pipeline_test.rb`) |
| `PIPE-29` | MUST | ✅ | 6, 10 | The runtime's obligation is unconditional and PIPE-29's permission is about step authors: a step raising `RuntimeError` synchronously yields a failed future carrying the **identical** error, and `#call` did not raise (`dexpace/async_pipeline_test.rb`) |
| `PIPE-30` | MUST | ✅ | 6, 10 | `AsyncDriver#normalise` rescues `StandardError` only, around every step invocation and around the terminal dispatch — the empty-pipeline transport dispatch included, an `IOError` from it becoming a failed future — and the fatal family propagates through the **absent** arm: a `NotImplementedError` from a step and a `LoadError` from an empty pipeline's transport both escape `#call`, asserted by class. The `rescue ::Exception` guard fails both. A step's future is returned as itself, never re-wrapped, and a step or transport returning a non-`Future` fails the drive with `Dexpace::SeamError` (P4-52) (`dexpace/async_pipeline_test.rb`) |
| `PIPE-31` | MUST | ✅ | 10 | `AsyncPipeline.map_response(future) { ... }` (P4-38), written over phase 2's `Future#then` (P4-53): the handler sees the response open and it is closed after, once; a raising handler still closes it and fails the mapped future with the identical error (no unwrap, none needed); a second close is the caller's and tolerated; a source failure is forwarded as the identical object with no response to close and no handler run; cancelling the mapped future cancels the source with the reason arriving as the `on_cancel` block's argument; and it maps a real pipeline's future end to end. Two guards fail: the close moved out of the `ensure`, and a fresh completer wired through `on_settle` alone (`dexpace/async_pipeline_test.rb`) |
| `PIPE-32` | MUST | ✅ | 10 | The documentation clause is discharged in `AsyncPipeline`'s YARD — the async standard pipeline installs retry + instrumentation and takes an explicit `redirect: :unsupported`, the sync one installs the redirect step — and the substantive clause holds vacuously until those constructors land (phase 6b, Task 13a): neither runtime responds to `.standard`, asserted. `REDIRECT` is deliberately **not** made un-installable on the async path (`dexpace/async_pipeline_test.rb`) |
| `PIPE-33` | MUST | ✅ in part; clause 5 ⏳ | 8 | Four of five clauses met through phase 2's `Transport.async_over(pipeline, executor:)` and nothing of 4c's (P4-35): clause 1 by an absence — core ships no executor and no default, `executor:` is required; clause 2 asserted with `InlineExecutor#posts` — a five-step pipeline is **one** `#post`; clause 3 asserted with the options object arriving at the transport by identity through the bridge; clause 4 is `Future#cancel`, phase 2's. **Clause 5, interrupt-mode cancellation, is unmet**: design §10.5's unsatisfied MUST, `docs/first-release.md` § What v1 ships without › Unsatisfied MUSTs, whose entry says this row cites it; no test of it exists because there is no interrupt mode, and the trade is not re-argued. Phase 8b re-asserts the clause at the point the executor becomes real (`dexpace/pipeline_test.rb`) |
| `PIPE-34` | MUST | ✅ | 8 | Phase 2's `AsyncTransport.sync_over(async_pipeline)` over a built async pipeline: the response comes back, the options object arrives at the async transport by identity, and a cancelled token raises `Dexpace::CancelledError` carrying `:client_abort` with the in-flight future cancelled rather than blocking — the future kept in flight with `FakeAsyncTransport`'s `settle_later:` so the token can be observed. No wait, no deadline and no new signature ship in 4c (R13, P4-35) (`dexpace/pipeline_test.rb`) |
| `PIPE-35` | SHOULD | ✅ | 7, 8 | `Builder.flattening(pipeline)` reloads the runtime's entries (names included) over its transport; `Builder.nesting(pipeline)` makes the runtime the transport. Distinguished by behaviour: over one inner pipeline with a twice-forking `REDIRECT`, a new `PRE_RETRY` probe runs **twice** under FLATTEN and **once** under NEST; the swapped guard fails both assertions (`dexpace/pipeline_test.rb`) |
| `PIPE-36` | SHOULD | ⏳ | — | Pillar-step stage locking, declined post-MVP by the MVP-scope design: `docs/first-release.md` § What v1 ships without › SHOULD/MAY, whose entry names this row. Nothing here implements any part of it; R10's precedence table is where a lock would go, and verified fact 6 records why `Method#owner` cannot detect an inherited `#stage` |
| `PIPE-37` | MUST | ✅ | 9 | `Stages::PRE_REDIRECT` at order 100 is the outermost slot, and the clause is proven **through the pipeline** with 4b's real `ErrorMappingStep` under `TransformStep`: beneath a twice-forking `REDIRECT` the slot's transform runs exactly once, hands back the terminal 2xx by identity with `RecordingBody#source_count` and `#release_count` both 0 and the latch unflipped, while the superseded hop's body was released once (PIPE-40); a 503 raises `Dexpace::ProtocolError` out of the pipeline. Placement is documented on `TransformStep` and `PRE_REDIRECT`, not enforced. 4b's row proved the untouched pass at the step level; this is the same clause at the pipeline level (`pipeline/transform_step_test.rb`) |
| `PIPE-38` | MUST | ✅ | 7 | `append_all([s1, s2, s3])` yields `s1, s2, s3`; `prepend_all([s1, s2, s3])` yields `s3, s2, s1`, because each element is prepended individually; the asymmetry is in `#prepend_all`'s YARD as the requirement demands, and the guard that appends each element instead fails the test (`pipeline/builder_test.rb`) |
| `PIPE-39` | SHOULD | ⏳ in half | 8, 10 | The step-less shape ships: `Pipeline.direct(transport)` and `AsyncPipeline.direct(transport)`, plus `Builder#install_preset` (PIPE-24's mechanism) and `Builder.flattening` / `.nesting`. The standard-resilience constructors `Pipeline.standard` / `AsyncPipeline.standard` are postponed by the design to phase 6b, Task 13a (`docs/work/mvp/phase6/phase6b/2026-09-09-phase6b-redirect.md`, "Task 13a — phase-level"), the first phase in which all three families exist; its Task 14 closes this row. Asserted: neither runtime responds to `.standard` (`dexpace/pipeline_test.rb`, `dexpace/async_pipeline_test.rb`) |
| `PIPE-40` | MUST | ✅ | 3, 6 | The rule is the re-driving step's, and `ForkingProbe` is its conformance fixture: over a transport minting a closable response per drive, three drives close the first two before the next drive and hand back the third unclosed, `probe.closed_responses` naming exactly the two. The rule travels with `Cursor#fork`'s YARD, where a phase-6 author will meet it (`pipeline/cursor_test.rb`) |
| `REDIR-11` | MUST | ✅ mechanism | 6 | Cross-reference, phase 6b's ID: the mechanism its "no step downstream of AUTH can set the marker" rests on is built and asserted by name — cursor-scoped state keyed by `(stage, key)` (P4-28), written only through `#fork(state:)` into the forking pillar's own slot (P4-29), a `RETRY` pillar's fork carrying `cross_origin: false` visible under `Stages::RETRY` and never under `Stages::REDIRECT`, and a second fork from the same parent starting from the parent's slot so hop 2 never sees hop 1's write. The marker itself and its expiry are phase 6b's (`pipeline/cursor_test.rb`, `StateTest`) |
| `AUTH-29` | MUST | ✅ mechanism | 6 | Cross-reference, phase 6c's ID: `Cursor#state(Stages::REDIRECT)` is the read side — a frozen hash, one shared empty for an unwritten slot, a `FrozenError` on any write, a non-`Stage` refused — and there is no state-setting method on the cursor at all, pinned from the manifest's side. The auth step's reading of the marker is phase 6c's (`pipeline/cursor_test.rb`, `StateTest`) |
| `XCUT-11` | MUST | ✅ share | 8, 10 | Cross-reference, phase 9's ID: `Dexpace::Pipeline` and `AsyncPipeline` are audited shared-instance state with no lock — a frozen entry table, a frozen step view, a write-once transport, no writer, no `#with` — and the cursor is the only per-call state, allocated per send and never published. Sixteen concurrent sends share nothing (`dexpace/pipeline_test.rb`) |
| `NFR-11` | SHOULD | ✅ share | 4 | Cross-reference, phase 9's ID: the step protocol's static half has a named home, `_Step` and `_AsyncStep` in `sig/dexpace/pipeline/step.rbs`, every name in them a `Dexpace::` constant; `gates:rbs_surface` is green over the twelve new mirrors [level corrected 2026-09-25 by phase 10: appendix C gives `NFR-11` as SHOULD; this row said MUST] |
| `SEAM-18` | MUST | ✅ composed | 8 | Cross-reference, phase 2's ID: both bridges are used over a built pipeline and neither is reimplemented — 4c ships no executor duck type, no orphan close and no normalisation of its own at the bridge (charter boundary 15, P4-35). The design's finding that `Transport.async_over` accepted an async transport silently was found already repaired on this base by phase 2's Task 11: `Bridge::AsyncOver#deliver` raises `Dexpace::SeamError` when the wrapped transport delivers a `Future` (`dexpace/pipeline_test.rb`) |
| `TRANSPORT-1`, `TRANSPORT-2` | MUST | ✅ premise | 2 | Cross-reference, phase 8's IDs: the premise they presuppose — `PIPE` is the single authority on redirect and retry, at `Stages::REDIRECT` and `Stages::RETRY` — is what this phase makes true; disabling a native client's own is phase 8a's (`pipeline/stages_test.rb`) |

## What was built

Twelve new `lib/` files under `gems/dexpace-core/lib/dexpace/` — exactly the design's Module Layout:
`error/pipeline_error.rb`, `pipeline.rb` (`Dexpace::Pipeline`, `.builder`, `.direct`), and under
`pipeline/` `stage.rb`, `stages.rb`, `step.rb`, `entry.rb`, `cursor.rb`, `sync_driver.rb` and
`async_driver.rb` (the two `private_constant`s), `builder.rb` and `transform_step.rb`, then
`async_pipeline.rb` (`Dexpace::AsyncPipeline`, `.direct`, `.map_response`) — each with a `sig/`
mirror declaring every method, private ones and instance variables included, for the strict
`core` Steep target (**twelve** mirrors, the two drivers' among them with `hooks.rbs`'s comment,
P4-50), and every one but the two drivers with a `test/` mirror. Two files changed as the design
said: the entry file gains a twelve-line `# Phase 4c:` block in the plan's Task 11 order, with
`pipeline` first among the nested set, and the smoke suite `dexpace_test.rb` gains
`PIPELINE_LAYER` and the assertion that the drivers are private (it lives on the code branch, as
the brief fixes, because the code tip must keep it green). `sig/dexpace.rbs` is untouched
(P4-51). Four test-support files are new — `probe_step.rb`, `forking_probe.rb`, `state_probe.rb`
(one class per file, which `Style/OneClassPerFile` enforced rather than left to judgement) and
`pipeline_doubles_test.rb`, the doubles driven red first — and two of phase 2's are reused:
`fake_async_transport.rb` unchanged, and `inline_executor.rb` extended compatibly with a `#posts`
counter (P4-54). The surface manifest gains 79 rows, from 586 to 665, read row by row against the
object model before it was accepted: no row for either driver, no writer on `Cursor`, and one
spelling of each `Stage` flag because the raw `pillar`/`terminal` readers are private (P4-55). The
gemspec is untouched — zero `add_dependency` lines — and 4c adds no `require` of any kind beyond
`require_relative`: `seam_surface_test.rb`'s pinned list stays `securerandom strscan uri`.
`docs/knowledge/notes/` is untouched: the design's one note stands, and execution found the corpus
wrong about nothing further. `docs/deviations.md` is untouched, for phase 10 to flip.

The gates, all seventeen, on **4.0.6** (`bundle exec rake`, 2026-09-16, re-run after review round
0's repair), on the working branch before the cut and again at the tests tip: green, exit 0 —
`cops:test` 100 runs / 326 assertions, `steep` no type error over the strict `core` target,
`test:gems` **1,434 runs / 7,651 assertions** across the six gems (144 of them the eleven new
suites, one more the smoke suite gained), with **99.97% line coverage (3,817 / 3,818)** against the
80% floor — the one uncovered line is the same registry-claim race branch phases 2, 3a, 3b and 4b
recorded — `test:gates` 129 runs, the nine `gates:*` tasks (`gates:require_allowlist` clean, 23
bundled gems known; `gates:surface_snapshot` six manifests matching, the round-0 repair adding no
row; `gates:rbs_surface` no foreign constant), `yard` 100.00% documented (467 methods, 0
undocumented), `bundler_audit` clean. The matrix set is green on 3.2.11 (`test:gems` 1,434 runs,
99.97% line coverage there too — 3,771 / 3,772, the one line being the same race branch, which one
earlier run on the working tree happened to reach — and the four gates), 3.3.12 and 3.4.10, the
last two re-run after the round-0 repair on the docs tip's tree. The code tip is green on all
seventeen gates too, its `test:gems` at 1,290 runs and
**95.02%** on 4.0.6 (94.96% on 3.2.11), above the floor. The same caveat about `rubocop` that phases 1 through 4b recorded: run
through `rake` from a worktree nested under the parent checkout's `.claude/` it inspects 9 files;
run as `bundle exec rubocop --fail-level=convention --ignore-parent-exclusion` it inspected **287
files, no offenses** at the tests tip and 273 at the code tip, and every RuboCop claim here rests
on that run.

## Guards run red

Every guard the plan and the brief ask to be seen red was seen red, on 4.0.6, and restored
byte-for-byte after each; four were run on 3.2.11 as well — the `Stage#with` decision, because
`Data#with`'s floor behaviour is what it exists for, and the three identity-versus-`==` guards,
because value equality is the trap the floor could hide. Thirty-two single-edit mutations in all,
one file at a time, the owning suite re-run after each; **thirty-one were caught, and the one that
was not is a mutation that does not change behaviour** — a first attempt at "flatten by insertion
order" that sorted the buckets by their first entry's `object_id` and, the buckets being created in
`ALL`'s order, reproduced `ALL`'s order; the genuine mutation, an `@insertion` list appended on
every install and returned from `#entries`, is the one recorded below. Six more were run after
review round 0's repair (2026-09-16), one per line the repair made load-bearing, the three identity
ones on 3.2.11 as well as 4.0.6, and every one is caught; they are the second table. One of the six
had to be re-spelled: the surgical same-object `return` replaced by a bare `nil` tripped `NFR-6`'s
warning gate at load (`possibly useless use of nil in void context`), which is a mutation caught by
a warning and not evidence about a test, so the recorded form deletes the line.

| Fix reverted | Guard | What it said |
|---|---|---|
| `PIPE-6`: the pillar collision compared by `==` instead of `equal?` — **on 4.0.6 and 3.2.11** | `builder_test.rb` | `Dexpace::PipelineError expected but nothing was raised` on the shared-log `ProbeStep` pair |
| `PIPE-5`: the message dropping the new step's type | `builder_test.rb` | `Expected "pillar retry is already occupied by ProbeStep; cannot install a step (use #replace to substitute) (PIPE-5)" to include "... cannot install ProbeStep ..."` |
| `PIPE-8`: the SEND rejection removed from `Entry.build` | `entry_test.rb` | `Dexpace::PipelineError expected but nothing was raised`, and the `#with`-to-SEND test with it |
| `PIPE-1`: flattening by insertion order (`@insertion` returned from `#entries`) | `pipeline_test.rb`, `builder_test.rb` | the shuffled-probes test with `install order [:pre_logging, :post_logging, :pre_redirect, ...] under seed 42` in its message, and 12 builder failures |
| `PIPE-2`/`PIPE-3`: `PRE_AUTH` and `AUTH` swapped in `Stages::ALL` | `stages_test.rb` | the names-in-order test and the ALL-versus-`#order` test, both `--- expected / +++ actual` |
| `PIPE-35`: FLATTEN and NEST swapped | `pipeline_test.rb` | `FLATTEN: inside the redirect loop` (`Expected: 2 Actual: 1`), and the copies test |
| `PIPE-38`: `prepend_all` appending each element | `builder_test.rb` | `Expected: [s3, s2, s1] Actual: [s1, s2, s3]` |
| `PIPE-13`/`PIPE-15`: the cursor latch removed — **on 4.0.6 and 3.2.11** | `cursor_test.rb` | `Dexpace::PipelineError expected but nothing was raised` on the second sequential `#call` |
| `PIPE-15`/P4-39: `#fork` accepted on a spent cursor | `cursor_test.rb` | `Dexpace::PipelineError expected but nothing was raised` |
| `PIPE-15`/R10: `#fork` accepted on a slot stage (the pillar gate opened) | `cursor_test.rb` | R11 assertion 3: `Dexpace::PipelineError expected but nothing was raised` |
| `PIPE-16`: a fork sharing the parent's spent state (`#fork` returning `self`) | `cursor_test.rb` | `Expected {hop: 1} to be the same as {}`, and two `cursor is spent and cannot be forked` errors from the twice-forking probes |
| `PIPE-16`: the child cursor bound at `position + 2` (the tail skipped) | `cursor_test.rb` | `Expected: 3 Actual: 2` on the substitution's observers, and R11 assertion 4 |
| `PIPE-14`: the driver handed the cursor's own `@request` rather than the argument | `cursor_test.rb` | `Expected "original_request" to be the same as "substituted_request"` |
| `PIPE-17`: options `dup`ed per fork | `cursor_test.rb` | two `Expected #<Object> to be the same as #<Object>`, which `assert_equal` would have passed |
| R11/P4-28: state keyed by key alone (one flat slot every stage reads) | `cursor_test.rb` | R11 assertion 4: `--- expected / +++ actual`, AUTH seeing RETRY's `cross_origin: false` under `Stages::REDIRECT` |
| P4-29: a `state=` writer added to `Cursor` | `cursor_test.rb` | `no writer of any name may appear on Cursor. Expected [:state=] to be empty` |
| `PIPE-23`: `#reload` clearing the buckets before validating | `builder_test.rb` | `the existing collection is completely unchanged` on both rejection tests |
| `PIPE-24`: `#install_preset` committing before the occupancy check | `builder_test.rb` | `installing nothing` |
| `PIPE-23`/`PIPE-24`: the bulk collision compared by `==` — **on 4.0.6 and 3.2.11** | `builder_test.rb` | `Dexpace::PipelineError expected but nothing was raised`, twice |
| `PIPE-28`: `#build_async` deriving its table by a second path (reversed) | `async_pipeline_test.rb` | `Expected #<data Stage name=:post_serde ...> to be the same as ...`, and `Expected: [:redirect, :auth] Actual: [:auth, :redirect]` |
| `PIPE-18`/`PIPE-21`: a name anchor matched by type | `builder_test.rb` | the name-anchors-one-lambda test, and `Dexpace::PipelineError expected but nothing was raised` on the absent name |
| `PIPE-30`: a `ScriptError` converted to a failed future (`rescue ::Exception`) | `async_pipeline_test.rb` | `NotImplementedError expected but nothing was raised`; `LoadError expected but nothing was raised` |
| `PIPE-31`: `map_response` closing after the yield instead of in an `ensure` | `async_pipeline_test.rb` | `Expected #<CountingResponse @closes=0> to be closed?` |
| `PIPE-31`: `map_response` over a fresh completer wired through `on_settle` alone (no cancel propagation) | `async_pipeline_test.rb` | the cancellation test: the source `to be cancelled?`, and `RuntimeError: handler error` escaping the settling path |
| `PIPE-27`: the runtime owning its transport with a cascading release | `pipeline_test.rb` | `Expected #<Dexpace::Pipeline @dexpace_owned=true ...> to not be owned?` |
| `PIPE-9`: the empty branch removed (`.direct` allocating a cursor) | `pipeline_test.rb` | `an empty pipeline allocates no cursor (PIPE-9). Expected: 0 Actual: 1` |
| R8/`PIPE-37`: `TransformStep` calling `#call` instead of `#apply` | `transform_step_test.rb` | `RuntimeError: must never be called (verified fact 12)`, three errors |
| R8: `TransformStep` accepting a third phase | `transform_step_test.rb` | `Dexpace::InvalidArgumentError expected but nothing was raised` |
| R8: `TransformStep` reading `#phase` at call time | `transform_step_test.rb` | `#phase is read at build and never at call time. Expected: 1 Actual: 3` |
| `TransformStep` with the request/response branches swapped | `transform_step_test.rb` | `Expected: "handled_transformed_data" Actual: "transformed_handled_data"`, and its mirror |
| P4-32: `Stage#with` left as `Model#with` (the override removed) — **on 4.0.6 and 3.2.11** | `stage_test.rb` | `[Dexpace::InvalidArgumentError] exception expected, not Class: <NoMethodError> Message: <"undefined method 'build' for class Dexpace::Pipeline::Stage">`, identically on both |
| `PIPE-1`: the buckets sorted by their first entry's `object_id` | `pipeline_test.rb` | **green, 17 runs** — the buckets are created in `ALL`'s order, so the sort reproduced it; a no-op mutation, recorded so nobody counts it |

After review round 0's repair, one per line it made load-bearing:

| Fix reverted | Guard | What it said |
|---|---|---|
| `PIPE-6` (R0-1): the surgical same-object `return self` deleted from `#surgical` | `builder_test.rb`, `SurgicalTest` | 1 error: `Dexpace::PipelineError: pillar retry is already occupied by ProbeStep; cannot install ProbeStep (use #replace to substitute) (PIPE-5)` on the occupant beside itself |
| `PIPE-5`/`PIPE-6`: the shared `#same_occupant_of?` compared by `==` — **on 4.0.6 and 3.2.11** | `builder_test.rb` | 2 failures: `Dexpace::PipelineError expected but nothing was raised` on the surgical-path twin **and** on the `#append` twin, identically on both interpreters |
| P4-58 (R0-2): `Builder#resolve` taking a `Stage` as given — **on 4.0.6 and 3.2.11** | `builder_test.rb`, `InputTest` | 1 error: `Dexpace::PipelineError: step declares stage retry but was installed with stage retry (R10)` — the self-contradicting message the finding reported |
| P4-58 (R0-2): the `Stages.of(stage.name)` line deleted from `Entry.build` — **on 4.0.6 and 3.2.11** | `entry_test.rb` | 1 failure: `Expected #<data Dexpace::Pipeline::Stage name=:retry, ...> (oid=840) to be the same as #<data ... name=:retry, ...> (oid=848)` |
| P4-59 (R0-4): `validate_anchor!` dropped from `#remove` | `builder_test.rb`, `InputTest` | 1 failure: `Dexpace::InvalidArgumentError expected but nothing was raised` — `remove(42)` on an empty builder silently no-ops again |
| P4-59 (R0-4): `validate_anchor!` dropped from `#find_anchor` | `builder_test.rb`, `InputTest` | 1 failure: `[Dexpace::InvalidArgumentError] exception expected, not Class: <Dexpace::PipelineError>` — the empty builder reports PIPE-21's "not found" for an anchor that could never be found |

## Audit groups run

The phase-start pair first, at implementation: `--origin note --brief` returns 52 note entries
across 21 files (the design's one among them, `notes/pipeline.md`'s second entry);
`--section conflicts --brief` returns 25 entries, the six harvested conflicts all
`[overridden by notes/…]` and no open conflict. `--prefix-info PIPE` reports 40 IDs, 40
substantive, 0 roll-ups, 0 uncited; `--gaps PIPE` reports none. `--req` was run for each task's IDs
before that task; none came back a roll-up, and `PIPE-13`–`PIPE-16` and `PIPE-40`'s ten rule
entries were read in full before the cursor was written. The seven groups the design ran at
planning are recorded there; at implementation the five the design names for the plan were
re-checked against the built code:

| Group | Result at implementation |
|---|---|
| Public API surface | `module-organization/1828a984` (one public constant per file) holds for all twelve files; `api-design/b0e18938` is why every name is in P4-26, P4-27 or P4-50–P4-59, and why `Cursor::EMPTY_SLOT`, `::EMPTY_STATE`, `Stages::LOOKUP`, `TransformStep::PHASES` and the two drivers are private; `api-design/88e6bf12`'s narrowest duck type is honoured — `Step.conforms?` at every install, `respond_to?(:phase)`/`(:apply)` at the adapter, phase 2's predicate at both builds, no `is_a?(IO)` anywhere; `api-design/c15b29ce` holds for every returned collection, each frozen |
| RBS / Steep typing | Twelve mirrors, the strict target green; `Cursor#call` is `untyped` with `_Step`/`_AsyncStep` carrying the real types (plan open question 7); the RBS type aliases `anchor`, `stage_ref` and `name` live inside `class Builder` and validate on rbs 4.2 |
| Minitest conventions | Every suite subclasses `DexpaceTestCase`, every raise is asserted on the raised object and never with `assert_nothing_raised`, `assert_same` wherever identity is the claim, one behaviour per test, the `PIPE-1` seed pinned and printed, and five suites split into nested classes under `Metrics/ClassLength` |
| Fiber scheduler, thread safety | Clean against the built code: no mutex anywhere in the subsystem — the runtime is frozen data, the builder is single-threaded by construction and says so, the cursor is per-invocation and unshared with its latch's sequential-only detection stated in two YARD blocks (P4-33); `Timeout.timeout`, `Thread#raise` and `Thread#kill` appear nowhere; nothing waits |
| Resource lifecycle and stream ownership | Clean against the built code: the runtime closes nothing (PIPE-27); the one close site in the subsystem is `map_response`'s `ensure` through `close_quietly`; PIPE-40's close discipline is the re-driving step's and `ForkingProbe` is its worked example; `resource-management/bf5560dc`'s block form does not reach a runtime that hands its resource outward, the disposition 4b's P4-18 and 3a's P3-10 gave it |

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate.
Items 1–9 are where the built tree overrode the plan's assumptions, the brief's as-built list in
the order it gives them; 24 through 26 are review round 0's (2026-09-16), each fixed on the owning
branch with its guard run red above; the rest are this build's, and the ones that touch public
behaviour or a stated count are also ledger rows P4-50–P4-59.

1. **The 4b constructors take required keywords** and the phase-4b transforms are built with them:
   `IdempotencyKeyStep.build(header:, strategy:)`, `ClientIdentityStep.build(header:, tokens:)`,
   `ErrorMappingStep.build`. The plan's Task 9 fence built none of the three; the suite builds all
   three through `TransformStep` and drives the error-mapping one through a real pipeline over
   4b's `RecordingBody` and `RecoveryFixtures`.
2. **The surface manifest is `test/fixtures/surface/dexpace-core.txt` at the repository root**,
   not `gems/dexpace-core/test/fixtures/...` as the plan's Task 11 writes, and phase 0's walker
   holds the `Data`-generated readers; the diff was read row by row against the object model
   rather than against a list the plan does not carry.
3. **A `private_constant` gets a `sig/` mirror**: `pipeline/sync_driver.rbs` and
   `pipeline/async_driver.rbs` both exist with `hooks.rbs`'s comment, so the design's "ten `sig/`
   mirrors" is twelve (P4-50); neither driver has a manifest row, a YARD-gate entry or a `test/`
   mirror.
4. **Seven custom cops, not eight, and 4c adds none**; the plan's Tech Stack line names "phase
   4a's seventh", which is not on this base. `Dexpace/QualifiedCoreConstant` demanded nothing new.
5. **Inside `class Pipeline` a bare `Builder` is the pipeline builder** and phase 1's contract is
   reached as `Dexpace::Builder`, included exactly as `headers/builder.rb` does; the plan's builder
   included nothing.
6. **Phase 2's doubles are reused, not overwritten**: `FakeAsyncTransport.new(response:, raises:,
   settle_later:)` with three required positionals and `#completer`/`#settle`, so the plan's
   `defer: true` is `settle_later: true` and `calls.last[:options]` is `calls.last[1]`;
   `InlineExecutor` gains a `#posts` counter compatibly rather than a second `FakeExecutor` file
   (P4-54); `fake_transport.rb` is untouched. The plan's `probe_steps.rb` became three files,
   because `Style/OneClassPerFile` refuses two top-level classes in one file.
7. **`sig/dexpace.rbs` stays `module Dexpace; end`**; every constant declares in its own mirror
   (P4-51), so the plan's Task 11 Step 2 was not done as written.
8. **`DexpaceTestCase` is at `test/support/dexpace_test_case.rb`** and the suites use its
   `test "..."` form; `Model#with` routes through `.build` on the floor, which `entry_test.rb`'s
   `#with`-to-SEND case is written for.
9. **`Stage#with` refuses** (P4-56) — the as-built point 9 decision: `Data#with` is public on
   every `Data`, and through `Model#with` it would route to a `Stage.build` that does not exist
   (a `NoMethodError` from inside `Model`, measured on 4.0.6 and 3.2.11), so `Stage` overrides
   `#with` to raise `Dexpace::InvalidArgumentError` naming the closed set. The alternative — an
   identity check against `Stages::ALL` in `Entry.build` and `Builder` — was not taken, because
   it defends a hole rather than closing the route to it. (Review round 0 then found the *public*
   copy routes, `dup`, `clone` and `Marshal`, and those two places now *resolve* a `Stage` through
   `Stages.of` rather than check it — item 25 below — which is a different thing from refusing.)
10. **`Stage`'s raw `pillar` and `terminal` readers are private** (P4-55), so each flag has one
    public spelling, `#pillar?` and `#terminal?`; the plan's manifest would have carried both.
11. **The `Builder` has no `#transport` reader**; the plan's `attr_reader :transport` was a
    row P4-27 does not list and nothing reads, so it was not written.
12. **`Cursor#may_fork?` also answers false on a spent cursor**, not only on a slot stage, so
    "ask rather than rescue" is true of both raises `#fork` can make; `#state` refuses a
    non-`Stage` rather than reading it as an empty slot; `#fork` refuses a non-`Hash` `state:`;
    and the root cursor's `#fork` has its own message (`the root cursor is bound to no entry and
    cannot fork (PIPE-15)`) rather than the plan's `stage none` (P4-57).
13. **`AsyncDriver` returns a step's future as itself** and rescues `StandardError` only, with
    no `rescue ::Exception; raise` arm — the plan re-wrapped every step's future in a second
    `Completer` through `on_settle` and re-raised the fatal family with a bare `raise`. The
    absent arm is 4b's P4-47 shape; the identity return is what makes "no unwrapping needed"
    literally true and cancellation reach the producer directly. A non-`Future` return from a
    step or transport fails the drive with `Dexpace::SeamError` (P4-52), the mirror of
    `Bridge::SyncOver`'s check, which the plan's driver would have fulfilled the future with.
14. **`AsyncPipeline.map_response` is written over `Future#then`** (P4-53): the plan re-wired a
    completer, `on_cancel` and `on_settle` by hand; phase 2's combinator already forwards a
    failure by identity, a cancellation as a cancellation with its reason, and fails the derived
    future on a raising block, so the operator adds only the `ensure`d close. It also refuses a
    call without a block or over a non-`Future`.
15. **`AsyncPipeline`'s empty branch reaches `AsyncDriver#dispatch`**, one normalised region
    shared with the terminal hop of a non-empty drive, rather than the plan's private
    `dispatch_directly` with its own rescue: one rescue region in the async runtime, not two.
16. **`Builder#effective_stage` is one precedence table for installs and surgical edits**; the
    plan wrote `resolve_stage` and `resolve_surgical_stage` as two copies. The surgical inserts
    also check pillar exclusivity, which the plan's did not (PIPE-5 names "insert-after /
    insert-before" outright) — and, since review round 0, apply PIPE-6's same-object no-op on
    that path too (item 24) — and `#install_preset` treats a pillar the same object already
    occupies as not a collision (PIPE-6 on that path).
17. **`Stages` mints its sixteen through one private `mint` helper** carrying the subsystem's
    one `Stage.send(:new, ...)`, rather than sixteen `send`s in the constant table.
18. **Message forms**: `Stages.of`'s and the eleven `PipelineError` forms are the plan's
    verbatim; `Cursor#state`'s and `#fork`'s argument errors, `TransformStep.build`'s two, and
    `map_response`'s two are this build's, in SEAM-29's form.
19. **`Builder` carries a `# rubocop:disable Metrics/ClassLength` directive with its reason**,
    as `Registry`, `MultipartBody` and `BufferedSource` do: one deriver for both runtimes is the
    design (P4-30, PIPE-28), and the cap is not raised.
20. **Five suites are split into nested `DexpaceTestCase` classes** (`cursor_test.rb`,
    `builder_test.rb`, `pipeline_test.rb`, `async_pipeline_test.rb`, `transform_step_test.rb`),
    on phase 3b's and 4b's precedent, because `Metrics/ClassLength` caps a class at 100 lines;
    the smoke suite's `LAYERS` constant and a tightened pipeline test keep it under the cap.
21. **Two tests the plan did not name**: `stage_test.rb` proves the private constructor's five
    validations through the `send` hole (the one route to them), and `pipeline_test.rb` asserts
    `Dexpace::Builder.build_all` over the pipeline builder (SEAM-29's contract).
22. **The plan's Task 11 Step 6 named `mise exec ruby@3.2.11`**; the matrix rows were run by
    putting each interpreter's `bin` first on `PATH` with a fresh `Gemfile.lock` per interpreter,
    as `CLAUDE.md` prescribes, on 3.2.11, 3.3.12 and 3.4.10.
23. **The three phase-4c documents were cut from 4b's docs tip, not `main`**, and the checklist
    counts (twelve `lib/` files, ninety-one under `lib/dexpace/`, seven checklists) are derived
    on top of what 4b's base already states.

Items 24 through 26 are review round 0's (2026-09-16), each a gap the review found by experiment
against the built tree, fixed on the owning branch with its mutation run red above.

24. **`PIPE-6`'s same-object idempotence reaches the surgical inserts.** As first built,
    `#insert_after` and `#insert_before` of a pillar's own occupant beside itself raised PIPE-5
    naming the same type twice — `#surgical` called `refuse_collision!` with no same-object check,
    while `#install` and the two bulk paths had one. PIPE-5 lists insert-after and insert-before
    among the paths its distinct-step rule covers, so PIPE-6's "same" half reaches them too; the
    identity test is now one predicate, `#same_occupant_of?`, that `#install`, `#surgical` and
    `#same_occupant?` all call, and an exclusive insert of the occupant returns `self` after the
    cross-stage check has passed. A cross-stage insert of the occupant is still PIPE-18's refusal,
    and `#replace` of the occupant by itself still replaces (R0-1).
25. **Every `Stage` the subsystem holds is the constant by identity** (P4-58). `Data#dup`,
    `#clone` and a `Marshal` round-trip are public on every `Data` and each yields a `Stage` that
    is `==` its constant and not `equal?` to it — not a seventeenth stage, since name, order and
    flags are the constant's, but a second object; `Stages.of`, the bucket table and the cursor's
    state map all resolve it by value, so nothing misbehaved, but the builder's two identity
    comparisons over stages refused such a copy with a message naming the same stage on both sides
    (`step declares stage retry but was installed with stage retry (R10)`; a same-stage insert
    beside an `Entry` built over the copy as `cannot insert Proc declaring stage retry relative to
    anchor at stage retry (PIPE-18)`, on the reload path). `Builder#resolve` and `Entry.build` now
    canonicalise through `Stages.of(stage.name)` — P4-32's "only lookup" — at the two places a
    `Stage` enters, so the identity comparisons stay identity comparisons rather than becoming
    `==`. One consequence, stated: a `send`-forged `Stage` whose name is not one of the sixteen
    now fails at `Entry.build` with `unknown stage: :fake (PIPE-1)` rather than as a raw `KeyError`
    from the bucket table, and one whose name is a real stage's resolves to that constant; the P8
    hole is not closed by this and is not claimed to be. `entry.rb` gains one
    `require_relative "stages"` (R0-2).
26. **A mistyped anchor is refused in the SDK's own form** (P4-59). `#remove`, `#insert_after`,
    `#insert_before` and `#replace` handed an anchor that is neither a `Module` nor a `Symbol` or
    `String` to `entry.step.is_a?(anchor)`, which raises Ruby's `TypeError: class or module
    required` — and only once an entry existed to compare against, so `remove(42)` on an empty
    builder was a silent no-op. `validate_anchor!`, called once at the top of `#remove` and
    `#find_anchor`, raises `Dexpace::InvalidArgumentError: anchor takes a Module, Symbol or
    String, got Integer` before any comparison, in the `takes a ..., got ...` form of item 18 (R0-4).

## Findings routed

- **`Transport.async_over`'s missing return-type check, the design's second finding, is already
  repaired on this base** — `Bridge::AsyncOver#deliver` raises `Dexpace::SeamError` when the
  wrapped transport delivers a `Future`, with a comment naming phase 4c as the finding's origin.
  Verified, not re-recorded; nothing to route.
- **The type-keyed surgical edits, the design's first finding, are repaired here** by Task 5's
  `Entry#name` and Task 7's name anchors, as the plan's amendment says. Verified in
  `builder_test.rb`'s `NameAnchorTest`; nothing to route.
- **The `PIPE-39` constructor postponement stands as the design recorded it**: `Builder#install_preset`,
  `Pipeline.direct` / `AsyncPipeline.direct` and `Builder.flattening` / `.nesting` all ship; the
  standard constructors are phase 6b, Task 13a's, whose heading exists under that number.
- **The design's ledger** gains an "As built" addendum (P4-50–P4-59); the consolidation of
  P4-26–P4-39 and P4-50–P4-59 into design §10, and the §5.1 and §5.3 addenda (the `(stage, key)`
  state, the sixteen stages, the disjoint `#call`/`#fork`), are a human's, as they were for 3a, 3b
  and 4b, because `docs/sdk-design-ruby/` is frozen. No frozen-chapter sentence is contradicted
  by this build, so `docs/first-release.md`'s `C1`–`C14` paragraph gains no `C15`.
- **Nothing for phase 10's inbound list**: the gates were right about everything they reported,
  and `Style/OneClassPerFile` settled the plan's one-file-or-three question rather than fighting
  it.
- **Review round 0's five findings** (2026-09-16) all closed in this stack: the three on the
  builder are items 24–26 above, each on the owning branch with its test and its guard run red;
  the roadmap status note's fence count for `pipelines.md` was corrected from eleven to ten
  (R0-3); and the surface-manifest commit's body counted fourteen `Builder` instance methods
  where the manifest and the runtime hold thirteen (R0-5) — a commit message is not rewritten,
  so the fix commit's body carries the correct count. Nothing routed elsewhere.

## Postponed work

The one item the design postponed keeps its owner: the standard-resilience constructors
`Pipeline.standard` / `AsyncPipeline.standard`, with `PIPE-32`'s `redirect: :unsupported`
argument, are phase 6b, Task 13a (`docs/work/mvp/phase6/phase6b/2026-09-09-phase6b-redirect.md`),
written over `Builder#install_preset`, and its Task 14 closes the `PIPE-39` row. `PIPE-33`'s
interrupt clause stays with `docs/first-release.md` § What v1 ships without › Unsatisfied MUSTs
(design §10.5), re-asserted by phase 8b when the executor becomes real; `PIPE-36` stays declined
in the same file's SHOULD/MAY entry. The items earlier phases postponed and this phase read on
2026-09-16 keep their owners: the pivot's `deadline:` (phase 5a, Task 8 — 4c writes no wait, so
no second postponement is recorded, R13), the fakes' move to `dexpace-conformance` (declined by
8a; four more doubles strengthen the case without meeting it), `IO-38` on a GVL-free interpreter
(phase 3a; the two `ObjectSpace` deltas here are CRuby-only and skip elsewhere), the recovery-stack
retry engine (phase 6a, Tasks 3, 4, 5, 7 and 11 — 4c is one of its two substrates, `Stages::RETRY`
with `Cursor#fork`), `SEAM-24`/`SEAM-28` (phase 5c, Task 4), and the Cursor context-bundle
widening (phase 6a, Task 8). The implementation postponed nothing further.
