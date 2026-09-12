# Phase 9 handoff — resume point after the narrow fix round

Written 2026-09-13 at the user's request, and **committed and pushed together with phase 9's working state before
the items below were resolved**. Phase 9 planning is not finished. Scope of this note is **phase 9 only**; phase 10
is untouched.

Read the whole note before acting. Every number was true when written; re-derive with the commands given.

---

## Where phase 9 stands

Branch `2-brainstorm-the-v1-roadmap-then-design-and-plan-each-phase-mvp`, tracking `origin`. Phase 9's documents,
register appends, corpus notes, roadmap and `CLAUDE.md` changes, and this note are in one commit on top of `041c54f`.

- `docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance-design.md` — 1,208 lines
- `docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance.md` — 4,670 lines, 17 tasks
- `docs/knowledge/notes/cross-cutting-invariants.md` (new), `notes/testing.md`, `notes/tooling-and-quality-gates.md`
- `docs/open-items.md`, `docs/deferred-items.md`, `docs/deviations.md`, the roadmap, `CLAUDE.md`

Scope: `XCUT-1`–`24`, `NFR-1`–`17`, appendix B's 61 items. **Not segmented** — confirmed by every reviewer.

Registers: phase 9 filed `OI-49`–`OI-56` and `DEF-43`–`DEF-47`. Next free ids when written: `OI` 57, `DEF` 48.

## How it got here

1. Opus planner wrote design and plan (452k tokens).
2. Two concurrent opus reviewers. Design: 10 blockers, all bookkeeping. Plan: 12 blockers; a 66-mutation battery
   caught 8 of 33 at the requirement level; 17 `git commit` steps in the plan.
3. Planner fixed everything in one round (687k tokens — retired).
4. Fresh opus re-reviewer, blockers only: 11 FIXED, 11 PARTIAL, 0 regressed, plus 5 new blockers — three of them
   the recurring root cause, call sites built from a predecessor's prose instead of its filed fence.
5. Fresh opus narrow-fix agent (494k tokens — retired). Reported every assigned item done on 3.2.11, 3.3.12, 3.4.10
   and 4.0.6, filed the residue below, and handed back the open items in the next section.

### What the narrow-fix round changed (its own report — self-graded, see "Verification status")

- **A1** Tasks 1 and 13 use phase 0's real `GateCase` plus `dexpace_test_case`; Task 14 uses `GateCase`. Prepend
  reason corrected: `Warning.singleton_class.ancestors` is `[FatalWarnings, #<Class:Warning>, Warning]`.
- **A2** Both adapter drivers call `Suite.run` and assert on the report; 8a's `MinitestDriver` (8a plan:2280–2322)
  is unchanged. The async-thread driver's call sites were rebuilt from 8b: `Pool.build(size:, …)` (8b
  plan:1315–1317); 8b files no `Thread.using`/`Thread.inline`, so `borrow:`, `functional:`, `events:` are `nil`.
- **A3** `CodecSuite` calls `dump_to` and `load(source, witness)` (phase 2 plan:4552–4564); the driver supplies the
  witness and a source factory, because 7a's `load` reads `source.read_utf8` (7a design:1322–1330).
- **A4** `XCUT-23` builds `Registry.new(seam:, installer:, conforms:)` (phase 2 plan:2864), `core: "~> M.N"`.
- **A5** `cause_walk` skips argument-carrying sends and adds `:FCALL`/`:BLOCK_PASS`; `seam_names` matches only
  `Serde::JSON`, `Transport::NetHTTP`, `Transport::AsyncHTTP`, `Async::Thread`.
- **B** `XCUT-21` replays construction with `cnonce_source:` stripped and requires `::SecureRandom` to perform the
  draw (interception gated on a thread-local flag); entropy judged by flipping each drawn byte (≥ 16 must change the
  cnonce).
- **C** `NFR-15`: a loaded module with no `VERSION` is `:failed`; Task 15 passes an explicit `constants:` map from
  `CLAUDE.md`'s gem table.
- **D** `XCUT-14` gains a behavioural `bounded_map_drains` assertion through a `bounded_map_store:` hook (8 vs 13);
  `gates:drain_loop` stays as a second line. The suite is now **27 assertions: 15 fully written, 12 by shape**, with
  `XCUT-11`, `XCUT-13` and `XCUT-14` carrying two each.
- **E** `InvariantCase#redirect_hop` and `InvariantSuite.run(redirect_hops:)` added; `XCUT-17` fully written.
- **F** Task 6 prints 3 tests; Task 14 has a real generator (61 rows, 11 generated, 50 `unmapped`, takes the map
  path); `walks_cause.rb` printed (5 offences of 6 sends); Tasks 4 and 10 print their wiring fences.
- **G** `XCUT-15` → Task 5; `DEF-44` narrowed to `NFR-12`/`NFR-16`; `OI-49` inference struck in design and
  `notes/testing.md`; four new CI gates (`serde_boundary` already exists from 7b plan:1758); 3.3.12 corrected.

Residue filed: `DEF-47` (MUST-level vacuity blocker unmechanised — pick up before Task 15's disposition run; a
manager decision), `OI-54` (`XCUT-9` collect-then-yield hang; depth cap 3 passes), `OI-55` (public factories and
`CountingSink` break rules phase 9 ships), `OI-56` (gates' remaining decidable misses, measured).

---

## Checks run by the main session, 2026-09-13, after the fix round

| Check | Result |
|---|---|
| `ruby .claude/skills/housekeeping/probe.rb` | `no drift found.` |
| `ruby -w .claude/skills/housekeeping/test/run.rb` | 97 runs, 248 assertions, 0 failures, 0 errors |
| `ruby -w scripts/test/knowledge_test.rb` | 80 runs, 309 assertions, 0 failures, 0 errors |
| `ruby scripts/verify_knowledge_structure.rb` | OK — 2166 harvested entries, 47 notes, every cited key live |
| `ruby scripts/knowledge_drift.rb` | 103 note citations resolve, 0 do not |
| `git diff` (staged and unstaged) over the five frozen trees | empty |
| Register pointers | `next id: OI-57` / `DEF-48` (as printed by the files); `OI-54`–`56`, `DEF-47` present |
| `grep GateTestCase` / `codec.dump(` / `git commit` in plan and design | 0 / 0 / 0 |
| `grep "Dexpace::Core"` in plan | 2 — both explanatory (plan:2367 comment, plan:4460 prose); not a defect |
| `grep "25 assertions"` in plan | 1 — plan:4151, a different test file (9 runs, 25 assertions); not a defect |

Re-run the same set before any later commit.

### Verification status — read this before trusting any number above the table

The fix agent ran the re-reviewer's harness **after adapting it** (`smut.rb`, `drivers_test.rb`, `assemble.rb`,
`runall.sh`, `mutate_gates.rb` — each change marked `ADAPTED` in its copy). That makes its harness results
self-graded. Its reported figures, identical on all four interpreters: `fp_scan` 0 `cause_walk` and 0 `seam_names`
offences over 199 filed fences; `xcut14_det` 8 vs 13; `smut` 21 of 24; `mutate_gates` `cause_walk` 10/12,
`bounded_map` 5/9, `seam_names` 5/7, `drain_loop` 1/3 with one false positive.

**By user decision (2026-09-13) the harnesses are disposable and independent measurement is deferred to the
user's end-of-planning review passes.** Both copies live on tmpfs and vanish on reboot:
`/tmp/claude-1000/-home-mohammad-Projects-dexpace-ruby-sdk/81b95ebb-d048-49f6-88cd-d8483741e815/scratchpad/`
(re-reviewer's originals) and `…/19d28a8f-c0a5-4e77-98eb-91ccc2b9d75e/scratchpad/phase9-fix/h/` (adapted copy).
Do not reconstruct them and do not dispatch a verifier because they are gone.

---

## Remaining work — phase 9 is not done until these are resolved

Each is either fixed by one **fresh** narrow agent or filed at the next free `OI` id with a target phase. Do not
resume any earlier agent. Recommended handling is given; the main session decides.

1. **`ExecutorSuite` reads a surface 8b's filed `Pool` does not have — and the plan tells the executor to file it as
   a finding against 8b.** `close_is_latched` and `borrowed_executor_survives` read `#shutdown_count` and expect
   `{name:}` event hashes; 8b's `Pool` has neither and emits its shutdown event through a logger sink (8b
   plan:1645–1651). The async-thread driver is red against the real `Pool`. plan:3413–3416 says: "record the
   `:error` as a finding, do not add the method (`R6`)". That instruction turns a suite defect into a false
   finding against conforming code, which phase 10 would act on. **Recommended: fix now** — rebuild the two
   assertions' observation from 8b's filed logger-sink fence, and strike the "record as a finding" sentence. This
   is the prose-not-fences root cause again.
2. **`notes/cross-cutting-invariants.md` is stale against the fixed design.** It still says the drain-loop clause is
   "not decidable" / "undecidable" because the "GVL serialises the interleaving", so it is "checked as shape" — the
   premise the fix round proved false (deterministic 8 vs 13). The fix agent also reports its `seam_names` rule
   still describes path-suffix matching. Corpus queries return this note. **Recommended: fix now**, keeping note
   format (bullet on one line at column 0; indented `<sub>` with backticked source path).
3. **`gates:bounded_map` flags 6 locations in filed conforming fences, unadjudicated.** It is a blocking gate, so if
   these are false positives Task 17's green gate set is unreachable — the same class as blocker A5. If true
   positives, they are legitimate phase-9 audit findings for phase 10. **Recommended: adjudicate each against the
   filed fence**; narrow the gate for false positives, record true positives as findings.
4. `smut`'s `XCUT-11` fiber-suspension non-conforming case reports `:error` where `:failed` is required.
   Recommended: fix with item 1 if cheap, else file.
5. Task 12 states 5 runs; 6 were measured. Recommended: correct the count.
6. `fp_scan` emitted an "assigned but unused variable" parse warning for one filed fence, which weakens the plan's
   claim that parsing emits no warning. Recommended: narrow the claim.

Then re-run the check table above and commit the fixes as a follow-up commit.

---

## Commit and push conventions

- Commit messages: normal prose, no attribution lines, end with `Refs #2`.
- **Never push, and never run any `gh` command, unless the user says so for that specific action.** The push of
  this note's commit was explicitly requested; that approval does not carry forward.
- Stage explicit paths; confirm `git status --short` shows nothing unexpected; re-run the probe after staging.

## After phase 9 is finished

- Update the auto-memory `ruby-sdk-roadmap-status.md`: final commit hashes, register pointers, residue ids.
- Do not start phase 10 unless the user asks.

---

## Facts and rules a resuming session must not rediscover

- **All four CI Ruby versions are installed locally**: 3.2.11, 3.3.12, 3.4.10, 4.0.6 (`mise ls ruby`). There is no
  `.ruby-version` and no project `mise.toml`; the global default is 3.4.
- **Prose-not-fences** is this phase's recurring root cause — nine blockers across three rounds counting item 1.
  Every brief must say: build stand-ins and call sites from the predecessor's filed code fence, and cite `file:line`.
- A fact can be true without licensing the conclusion drawn from it. Instance: the re-reviewer claimed
  `module-organization/1828a984` exists nowhere; `ruby scripts/knowledge.rb --key module-organization/1828a984`
  resolves it and seven committed phases cite it. Leave that citation alone.
- Settled, do not revisit: segmentation (none); absent artifact is `:vacuous` with a mandatory reason;
  `NFR-10`/`-13`/`-14` carry both a gate result and a portable assertion (two audiences); which `XCUT` assertions
  are fully written; `XCUT-14` asserted behaviourally.
- Main session manages; subagents do substantive work, opus for authoring and review. Subagents may not dispatch
  agents, may not change git state, and must not touch the frozen trees (`docs/knowledge/harvested/`,
  `docs/product-spec/`, `docs/product-spec.md`, `docs/sdk-design-ruby/`, `docs/sdk-design-ruby.md`) or any
  committed phase 0–8 document.
- Retire an agent once it runs long; a fix round goes to a fresh agent with a narrow brief.
- A design must not use the literal register heading names the probe's `registers` check reports; phases use
  `## Deferrals Filed by Phase N`.
