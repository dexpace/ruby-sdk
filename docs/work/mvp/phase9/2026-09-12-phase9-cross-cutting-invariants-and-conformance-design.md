# Phase 9 — Cross-Cutting Invariants and Conformance

**Status:** Draft, approved for planning.

## Purpose

Phase 9 is the first phase whose deliverable is an **answer rather than an artifact**. Nine phases
built something; this one says whether what they built is what the specification asked for, and
writes the saying-so down in a form a third party can re-run.

Two things make that concrete rather than rhetorical. **`NFR-1` through `NFR-17` have never been
dispositioned.** Phase 0 stood all seventeen gates up as machinery and closed
none — its design says the seventeen are "stood up here as machinery and dispositioned in phase 9,
which is the roadmap's own division", and that phase 9 "owns the checklist rows that say whether each
is satisfied"
(`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md:25,55`) — so every one
of the seventeen gets its first and only verdict here. And **`XCUT-1` through `XCUT-24` are almost
entirely already implemented**, scattered across phases 1, 2, 4, 5, 6, 7 and 8, by phases that each
said in as many words that the ID was phase 9's to disposition. **Thirty-three hand-forward rows in
thirteen phase documents** name this phase by name and hand it a subject.

So phase 9's scope is 41 requirement IDs and almost no new behaviour. What it ships is
**instrumentation**: the suites in `dexpace-conformance` that turn appendix B's 61 checklist items
into something that runs, the repository gates that turn four "audited repository-wide" promises into
source scans, and one aggregate report that names every waiver and every vacuity on every run.

**What phase 9 does not do is fix anything.** The roadmap's next row is phase 10, "Deviation
Reconciliation and Release Readiness — every gem (audit-led; ships code where the audit finds a
defect)". That is the phase with the repair budget. Phase 9 measures, reports, files and hands over,
and the boundary is stated in as many words below, including for the case a reader will ask about
first: what happens when the audit finds an unmet MUST.

## Governing documents

Five, in the roadmap's own order, all binding here:

- `docs/product-spec/19-cross-cutting-invariants-and-policies.md` — the normative source of
  `XCUT-1`–`XCUT-24`; `docs/product-spec/20-non-functional-requirements-and-quality-bar.md` — of
  `NFR-1`–`NFR-17`; and `docs/product-spec/appendix-b-conformance-test-checklist.md` — the 61-item
  conformance checklist across nine sections, which the roadmap's phase-9 row names as scope.
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` is the ID index.
- `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md` in full — its gate table (the `NFR`
  column of this phase's work), §9.1's API-surface lock and its honest limits, §9.2's three
  zero-dependency checks, and §9.3, whose closing **Appendix B** paragraph is the single most
  load-bearing paragraph in this phase's scope because it states, section by section, what this port
  exercises as written and what it restates. `docs/sdk-design-ruby/10-…md` item 19 (the `NFR-8`/
  `NFR-9` retarget) and §12's requirement-coverage index, whose `XCUT` and `NFR` rows and whose
  MUST-level summary are claims this phase audits rather than inherits.
- The Ruby styleguide, `styleguide/ruby/`, chapters `01-formatting-and-tooling.md`,
  `03-type-safety-and-nil-discipline.md`, `11-testing.md` and `12-module-organization.md`, queried
  through the corpus. Binding except where a note under `docs/knowledge/notes/` records otherwise —
  and this phase files three such notes, listed below.
- `CLAUDE.md` — the hard rule on what core may `require`, the requirement-ID conventions, the
  domain-model construction pattern and the constraints that will bite, all four of which are
  **audit subjects** here rather than merely context.
- `docs/README.md` — the ownership table, what is frozen to maintenance tooling, and the
  `docs/work/` naming rules.

Two documents are governing in a second sense, because this phase extends them rather than reading
them: `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md` (the seventeen
gates and their fifty-two failing fixtures) and
`docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md`
(`R7` and `R16`, which fix the assertion protocol, the five result statuses, the ID-keyed waivers,
the `WireServer` fixture and the twelve-clause suite contract). **Phase 9 adds suites to a protocol
it did not design and may not change.**

---

## The segmentation decision

**Phase 9 is not segmented.** One design, one plan, both at `docs/work/mvp/phase9/`.

The roadmap's rule reaches build phases only, and says so:

> A **build phase** — phases 1 through 8 — whose ID count clearly exceeds earlier phases', or that
> spans more than one ID-bearing spec chapter, or that ships more than one gem, gets a
> **segmentation design at the `phaseN/` level before any sub-phase design** … Phase 0 carries no
> requirement scope, so the rule does not reach it; **phases 9 and 10 are audit-led and segment only
> if their own design finds it necessary.**
> (`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:175-182`)

So the question is not whether the rule's three triggers fire but whether this design finds a cut
necessary. It does not, on four counts.

**The ID count is below the largest unsegmented phase.** 41 IDs, against phase 1's 42 checklist rows
and phase 2's 30, both of which ran with one design and one plan. Phase 9 is the second-smallest
pillar phase in the roadmap by ID count.

**Only one of the rule's three triggers even fires.** Phase 9 spans two ID-bearing chapters (§19 and
§20). It ships into **one** gem, `dexpace-conformance`, and owns neither that gem's gemspec nor its
version nor its release — phase 8 does, and `docs/first-release.md` records the row as phase 8's.
The trigger that forced phase 8's cut, "ships more than one gem", is absent here.

**The work volume is real but it is not separable.** The 33 hand-forward rows, appendix B's 61 items
and the 17 `NFR` dispositions are three views of one thing: a single aggregate report over a single
assertion protocol. A cut along §19/§20 would put `XCUT-11`'s nine subjects in one sub-phase and
`NFR-3`'s symbol enumeration in another while both read the same `sig/` tree and both land in the
same `Report`. A cut along "suites versus gates" would separate `XCUT-9`'s cycle-safety assertion
from `XCUT-9`'s repository-wide single-walk scan, which are two halves of one requirement.

**Every candidate cut needs a shared-contract sub-phase, and this project has already learned what
that costs.** The roadmap's phase-6 bullet records the correction: a shared-contract segment was
proposed, found already settled by phase 4c, and removed. Here the shared contract is 8a's twelve
clauses plus the five result statuses, and it is *already written* — in another phase. A sub-phase
whose only job is to restate an inherited contract is the failure the segmentation rule exists to
prevent, not an instance of it.

The one argument for segmenting, stated so it is not hidden: **auditing is a different activity from
building, and phase 9 does both** — it writes `InvariantSuite` and `PackagingSuite` as code, and it
reads nine phases' artifacts as an auditor. That is a real tension and the answer is a task ordering
inside one plan, not two documents: **the plan builds the instrument in tasks 1–14 and runs it in
tasks 15–17**, which is the ordering a single plan expresses naturally and two sub-phases would
express as a dependency edge.

---

## Prerequisite

**Phases 0 through 8, all of them, and this is the only phase in the roadmap for which that is
literally true.** Phase 9 has no sub-phase independence to claim and no convenience ordering to
state: every audit subject is an artifact some earlier phase committed to produce, and an audit of
an absent artifact is not an audit.

What that means concretely, and the discipline it forces, is the subject of `R3` below. The short
form: this document names every audit subject by **path and constant**, taken from the phase
document that promised it, and the plan's every audit task opens with an **existence probe** against
that name. A probe that fails does not stop the phase and does not improvise a replacement — it
routes the finding to its owner — phase 10's inbound list in the roadmap, where the repair belongs —
marks the checklist row with the discrepancy named, and hands the repair to phase 10.

The one dependency that runs the other way: **phase 10 reads phase 9's report**. Design §10's
nineteen entries are audited by `docs/deviations.md`, whose rows all read `design only — not yet
built` today; phase 9's per-ID verdicts are what lets phase 10 flip them. A verdict phase 9 gets
wrong is a verdict phase 10 acts on.

---

## Corpus reading, and what it settled

The phase-start pair was run before anything here was written.

`ruby scripts/knowledge.rb --section conflicts --brief` returns six styleguide-versus-design
conflicts and **all six print `[overridden by notes/…]`**; none is open. This phase inherits six
settled decisions and owns none of them — which matters more here than in a build phase, because
four of the six (`package-and-dependency-layout/41b154a3` the Ruby floor,
`package-and-dependency-layout/8c0687bf` the `gems/` monorepo, `type-system/93dc79aa` RBS over
Sorbet, `tooling-and-quality-gates/86d763f1` the rubocop baseline) are the premises of `NFR-2`,
`NFR-3`, `NFR-7` and `NFR-10`'s dispositions. An audit that re-opened one would be auditing against
the styleguide's contract rather than this port's.

`ruby scripts/knowledge.rb --origin note --brief` returns **43 entries across 20 topic files** at
`HEAD` — **47 across 21 after this phase's three notes**, which add **four entries**, because the new
`cross-cutting-invariants.md` carries two (the `XCUT-11` predicate and the AST-gates consequence);
notes and entries are different units and this sentence counts entries. And **51 across 21 from
2026-09-13**, when retiring the open-items register moved four more entries into `notes/` (the
`Fiber#storage=` setter, `Async::Cancel` not being a `StandardError`, `Async::Task#cancel`
superseding `#stop`, and `dexpace-transport-net_http`'s connection per request). (The first draft of
this paragraph said 40, which is `CLAUDE.md`'s count of *harvested topics* and not of note entries:
the charter's 43 was right
and the "correction" was a regression. Recorded because it is the shape of error this repository's
finding discipline exists to catch, and because an audit phase miscounting the corpus it audits
against is not a small thing.)

`ruby scripts/knowledge.rb --prefix-info XCUT`: 24 canonical IDs, **22 MUST and 2 SHOULD**, owning
chapter `docs/product-spec/19-cross-cutting-invariants-and-policies.md`, and **24 of 24 have a
substantive corpus entry, 0 roll-up only, 0 uncited**. `--prefix-info NFR`: 17 IDs, **13 SHOULD and
4 MUST**, owning chapter `…/20-non-functional-requirements-and-quality-bar.md`, and **17 of 17
substantive**. `--gaps XCUT,NFR`: `0 of 41 IDs in 2 prefixes have no substantive entry`.

### The spec-reading budget

**On the ID side: none.** Zero gaps across both prefixes, so every one of the 41 is answerable from
the corpus and appendix C, and this phase budgets no reading of `19-…md` or `20-…md` beyond the
verification pass every design does.

**On the appendix-B side: the whole of it, directly.** Appendix B is not ID-indexed in the way the
corpus is — it is the *source* of the roll-ups the corpus warns about, which is why
`CLAUDE.md` names the hazard and why a `--req` hit tagged `[appendix-B roll-up]` is not an answer.
Phase 9 is the phase most exposed to that hazard, because appendix B is literally its scope, and the
resolution is not to query it but to read it. **Read in full during this design: all 61 items across
`B.1`–`B.9`, counted section by section — 10, 6, 7, 8, 6, 5, 6, 6, 7.** The coverage map below is
built from that reading, one row per item.

One consequence worth stating because it looks like a discrepancy and is not: `--gaps XCUT` reports
zero roll-up-only IDs, and appendix B's `B.8` covers every `XCUT` ID. Both are true because the
corpus's `XCUT` knowledge comes from chapter 19's own prose and from
`docs/knowledge/harvested/cross-cutting-invariants.md`, not from appendix B. The roll-up hazard bites
prefixes whose *only* citation is a B item; `XCUT` and `NFR` are not among them.

### The audit groups, run in full

The `knowledge-lookup` skill's table names the groups; a group not written down cannot be repeated.
Seven were run, and this phase is the one where the styleguide-derived areas carrying no requirement
ID are themselves the subject.

| Audit group | Query | Result |
|---|---|---|
| *RuboCop and formatting* | `--topic tooling-and-quality-gates --section rules,constraints` (26 entries) | Clean for this phase's own code. Three rules already carry notes (`f37d7536`, `e00c3fc5` → `notes/tooling-and-quality-gates.md:10`; `86d763f1` → `:8`). `tooling-and-quality-gates/4ac4a7a4` ("pin Ruby to 4.0 or higher") is resolved by `package-and-dependency-layout/41b154a3`'s note. **`tooling-and-quality-gates/7338f962` is an audit subject, not a rule to follow**: it states RBS's blindness to `Data.define` readers, which phase 0 plan, Task 14's `Data`-reader snapshot decision measured and found the runtime snapshot does not compensate for |
| *Gem layout, zero-dependency core* | `--topic package-and-dependency-layout --section rules,constraints` and `--prefix SEAM --section rules` | Clean. `package-and-dependency-layout/c41c6c3d` (adapters exempt from core's require restriction) is the rule phase 0 plan, Task 9's per-gem denylist scope finds the *mechanism* does not implement per-gem, which phase 9 audits under `NFR-2` |
| *RBS / Steep typing* | `--topic type-system,data-modeling --section rules` | Clean; every Sorbet-conditional rule is resolved by `type-system/169c8f38` and `data-modeling/677b01de`. `NFR-3`'s disposition rests on those notes, not on the styleguide's own text |
| *Minitest conventions* | `--topic testing,assertions --section rules` (29 entries) | **Two rules found false against a real interpreter in the supported range.** `testing/e27df4c7` names `Minitest::Mock` and `testing/70473c9d` names `Time.stub`; **neither exists on Ruby 4.0.6**, where Minitest is 6.0.0 and ships no `minitest/mock.rb`. Measured on all three interpreters — see the verified facts below. One note filed, `## Superseded`, and one finding, routed to phase 0 plan, Task 2's `minitest` `~> 5.25` pin |
| *Public API surface* | `--topic api-design,documentation,module-organization,error-handling --section rules` | Clean. `documentation/80beb95e` is what the YARD gate mechanises and is `NFR-3`'s evidence; `api-design/46c8b5fc` is `NFR-4` verbatim and is why `NFR-4`'s disposition cannot be ✅ before a release tag exists |
| *Cross-cutting invariants* | `--topic cross-cutting-invariants --section rules,constraints,conclusions` (14 entries) | Clean, and three entries are **audit predicates this phase adopts verbatim rather than re-deriving**: `cross-cutting-invariants/89eb6533` (close idempotence is a latch under a `Thread::Mutex` held across the flip only), `/3cc24c73` (whoever flips the latch runs the release; a raising release still leaves it flipped) and `/8fa2c08d` (`XCUT-13`'s preserve-the-cancel-flag clause is satisfied by the flag never being touched, while non-blocking shutdown remains a real constraint). The last is the reason `XCUT-13`'s audit is two assertions and not three |
| *Error handling* | `--topic error-handling --section rules` | Clean. `error-handling/c0a986d2` is `XCUT-4` verbatim; five entries carry notes from phases 1 and 4, all adopted |

---

## The verified Ruby facts this phase is built on

Four facts below are load-bearing for a decision in this document. **Every one was run on 3.2.11,
3.4.10 and 4.0.6** — `mise exec ruby@<v> -- ruby …` — and the results are what is recorded, not what
was expected. Where a fact holds identically on all three that is stated; where it does not, the
divergence is the finding.

**Fact 1 — `RubyVM::AbstractSyntaxTree` is present on all three and the PARSER warns on nothing, but
a send is THREE node types and a Symbol literal is TWO.** `parse_file` returned a `SCOPE` node on
3.2.11, 3.4.10 and 4.0.6 alike, and with a recorder prepended above phase 0's `FatalWarnings`,
**zero warnings** were captured — parsing a file that carries none, which is a narrower fact than it
was first written as; `Fact 1b` corrects it. Two node facts were got wrong first, in three parts:

- **`a.cause` is `:CALL`, `a&.cause` is `:QCALL`, bare `cause` is `:VCALL`** — identical on all
  three. A scan naming only `:CALL` found two of three sends in one fixture and missed every
  safe-navigated one, which is a gate reporting clean over a live `XCUT-9` violation.
- **A Symbol literal is `:LIT` on 3.2.11 and `:SYM` on 3.4.10 and 4.0.6.** This is the reverse of
  the usual direction — the *newer* interpreters diverge — and it matters because the reflective-send
  scan (`send(:cause)`, `__send__`, `public_send`, `method(:cause)`) reads that node: naming only
  `:LIT` caught 6 of 7 realistic shapes on the floor and **2 of 7** on both newer rows. Recorded in
  `docs/knowledge/notes/cross-cutting-invariants.md`, because a repository whose gates are strictest on
  the interpreter they run on least is a general hazard and not this phase's alone.
- **`Hash` is `:CONST` and `::Hash` is `:COLON3`**, so a `Hash.new` check naming only the first
  missed `@h = ::Hash.new` on every interpreter.

`R4` chooses this mechanism for the repository-wide invariant scans, with those three corrections in
it. Measured catch rates after them **and after the 2026-09-13 corrections**, over the
re-verification review's wider mutation battery and identical on 3.2.11, 3.3.12, 3.4.10 and 4.0.6:
`cause_walk` 10 of 12 decidable shapes and clean on both argument-carrying builder shapes
(`send(variable)` undecidable); `bounded_map` 5 of 9 decidable shapes (two more undecidable);
`seam_names` 5 of 7 decidable shapes and clean on core's own `Async`, `Instrumentation` and `Serde`
error constants. (`drain_loop`, measured at 1 of 3 non-conforming shapes caught with one false
positive, is out of v1 on that measurement — see the addendum.) Every miss is dispositioned by the
plan's Task 13. Over every filed `lib/` fence of phases 0–8,
`cause_walk` and `seam_names` report zero; `bounded_map` reports six, adjudicated under A5 below.

**Fact 1b — the parser warns on nothing; the SCANNED FILE does, and it reaches `Warning.warn`.**
Fact 1's measurement was made against a file carrying no diagnostic, and the conclusion drawn from it
— that the scanner can never fire phase 0's warnings-fatal gate — is false. A file's `-w`
diagnostics are emitted at parse time and routed through `Warning.warn` exactly as at require time,
and `FatalWarnings` raises on the first one. 8a's filed `adapter.rb` is a live instance: the `rescue
::StandardError => e` inside `Adapter#dispatch` never reads `e` (8a plan:4858), and parsing that
fence emits `assigned but unused variable - e` on 3.2.11, 3.3.12, 3.4.10 and 4.0.6 — with the gate
suite's own `dexpace_test_case` loaded, `RuntimeError: warning treated as an error (NFR-6)` out of
`AstScan.receiver_calls`, measured on all four. **Which suppression, measured rather than assumed:**
`Warning[:deprecated] = false` does not reach it (the warning carries no category); `$VERBOSE =
false` silences the `-w` class but not the always-on parse warnings (`key :a is duplicated` still
raised on all four); `$VERBOSE = nil` silences both. So `AstScan.parse` is the sole parse entry
point, opening a `$VERBOSE = nil` window restored in `ensure` — the gate stays armed everywhere else
— and Task 1 measures the fact against a fixture that actually warns. The unused `e` in 8a's fence
is a lint finding for phase 10 to repair; phase 9 does not edit a committed fence to suit its own
scanner, and the fixture reproduces the shape rather than the gate working around it.

**Fact 2 — `prism` is absent on the 3.2 floor.** `require "prism"` raises `LoadError` on 3.2.11;
3.4.10 reports `Prism::VERSION` `1.9.0` and 4.0.6 reports `1.8.1`. *The inference, stated rather than
assumed:* phase 0 puts the gate suites in a job that runs on the pinned interpreter only, so a
Prism-based scan would in fact work. Fact 1 is preferred anyway because it needs no such argument and
no conditional require — a gate that runs on any matrix row without a second implementation is
cheaper to reason about than one that runs on one row for a reason a reader has to reconstruct. The
4.0.6 interpreter shipping an *older* prism than 3.4.10 is recorded as measured and nothing here
depends on it.

**Fact 3 — Minitest is not a default gem on any supported Ruby, and on 4.0.6 it is a different major
version that has removed `minitest/mock`.** `Gem::Specification.find_by_name("minitest").default_gem?`
is `false` on all three. The versions are **5.25.1 on 3.2.11, 5.25.4 on 3.4.10 and 6.0.0 on 4.0.6**.
On 5.25.x the gem ships `minitest/mock.rb`; **on 6.0.0 it does not** — `require "minitest/mock"`
raises `LoadError`, and the gem's `lib/` listing confirms both `minitest/mock.rb` and
`minitest/unit.rb` are gone while `assertions.rb`, `test.rb`, `autorun.rb`, `spec.rb` and
`benchmark.rb` remain. Every assertion name this repository uses — the 22 checked, from
`assert_equal` to `assert_in_delta` — is still defined on `Minitest::Assertions` in 6.0.0. The half
that disappears is `Minitest::Mock` and `Object#stub`. The first half of this confirms across the whole range
what phase 0 plan, Task 2's explicit `minitest` Gemfile line rests on, where that measurement covered
only 3.4.10; the second half is new, and it is what fixes that task's pin at `~> 5.25`.

**Fact 4 — a `Data.define` subclass's generated readers live on the superclass, and the instance is
frozen on construction, on all three.** `class Status < Data.define(:code); def ok? = …; end` gives
`Status.instance_methods(false) == [:ok?]` and `Status.superclass.instance_methods(false) ==
[:code]`, and `Status.new(code: 200).frozen?` is `true`, identically on 3.2.11, 3.4.10 and 4.0.6.
This re-confirms phase 0 plan, Task 14's `Data`-reader snapshot decision — which measured the same split — and it is the reason `XCUT-15`'s audit
asserts frozen-ness at the **instance** level and `NFR-4`'s disposition cannot claim the runtime
surface snapshot as a second gate over member accessors. `Ractor.make_shareable` was checked in the
same run and behaves as `CLAUDE.md` states: same object returned, outer and inner both frozen, on all
three.

---

## Scope

### The 41 requirement IDs

One checklist row per ID at execution time, per the roadmap's cross-cutting constraint 3. The
"expected disposition" column below is a **prediction made before any code exists** and is the thing
the checklist replaces with an observation; it is written here so the plan has something to be
falsified against, and `R3` states what happens when it is.

#### `XCUT-1`–`XCUT-24` (22 MUST, 2 SHOULD) — audited, not built

Every one is implemented by an earlier phase. The middle column names the artifact by the phase that
committed to produce it, and is the existence probe's target.

| ID | Level | Audit subject, as the owning phase named it | Where the assertion lives |
|---|---|---|---|
| `XCUT-1` | MUST | phase 2's `Dexpace::Cancellation` and `Dexpace::CancelledError`; 8a/8c's cancellation channel (suite contract clause 5) | `TransportSuite` (exists) + `InvariantSuite` |
| `XCUT-2` | MUST | 4b's classification, 6a's retry gate, 8a's `Failures` mapping | `TransportSuite` (exists) + `InvariantSuite` |
| `XCUT-3` | MUST | 5a's interruptible clock wait (§10.17's cancellable queue wait), 6a's inter-attempt delay | `InvariantSuite` |
| `XCUT-4` | MUST | phase 1's `Dexpace::Error` **module**, 4b's `Dexpace::ProtocolError`, 8a's phase-level `Dexpace::TransportError < ::IOError` | `InvariantSuite` |
| `XCUT-5` | MUST | 5a's `Dexpace::Retryability.retryable_status?`; 6a's baked `#retryable?` (its Task 6, the flag phase 4b postponed) | `InvariantSuite` |
| `XCUT-6` | MUST | 6a's `Policy.throwable_retryable?` — the capability query | `InvariantSuite` |
| `XCUT-7` | MUST | 6a's `RetrySettings#retryable_statuses` — the configurable set | `InvariantSuite` |
| `XCUT-8` | MUST | 4b's `ProtocolError.for` (raises) and `.for_or_nil` (returns `nil`) | `InvariantSuite` |
| `XCUT-9` | MUST | 4b's `Dexpace.each_cause`, **plus** the repository-wide check that nothing else walks `#cause` | `InvariantSuite` + `gates:cause_walk` |
| `XCUT-10` | MUST | 6a's retry-safety gate, applied uniformly to protocol and transport failures | `InvariantSuite` |
| `XCUT-11` | MUST | **nine** named shared instances across five phases — see the hand-forward table | `InvariantSuite` (predicate) + per-suite |
| `XCUT-12` | SHOULD | 6c's bearer/digest credential caches; 7a's cache-free `Codec` (the stated vacuity) | `InvariantSuite` + `CodecSuite` |
| `XCUT-13` | MUST | phase 2's `Dexpace::Closeable` latch; 7c's `Page` as its second consumer; 8b's `Pool#close` | `InvariantSuite` + every seam suite |
| `XCUT-14` | MUST | 4a's `Dexpace::BoundedMap` (`private_constant`) and `ContextStore`; 6c's nonce store as the second consumer | `InvariantSuite` + `gates:bounded_map` |
| `XCUT-15` | MUST | phase 1's whole domain model; 7a's `Tristate`/`DecodeContext`; 7b's `SSE::Event` | `InvariantSuite` |
| `XCUT-16` | MUST | 6c's HTTPS guard on the credential-attaching path | `InvariantSuite` |
| `XCUT-17` | MUST | 6b's four redirect-hygiene clauses, against the **seed** origin | `InvariantSuite` |
| `XCUT-18` | MUST | phase 1's `HeaderSyntax`, **plus** the wire-boundary re-validation in 8a and 8c (the mitigation phase 1 postponed to the adapters) | `InvariantSuite` + `TransportSuite` |
| `XCUT-19` | MUST | 5b's `RedactionPolicy::DEFAULT` and `HTTPLogging::DEFAULT`; 5a's `Proxy` masking and `UUID` | `InvariantSuite` |
| `XCUT-20` | MUST | 5b's `Instrumentation.contain`, `Redactor#url`'s sentinel, `Preview.render`; 5c's scoped claim | `InvariantSuite` |
| `XCUT-21` | MUST | 6c's Digest cnonce ≥ 128 bits from a CSPRNG | `InvariantSuite` |
| `XCUT-22` | MUST | phase 2's `Closeable#owned?`; the BYO path in 8a, 8b and 8c | `InvariantSuite` + every seam suite |
| `XCUT-23` | MUST | phase 2's `Dexpace::Registry` — explicit install > require-time discovery > loud failure | `InvariantSuite` |
| `XCUT-24` | SHOULD | 3b's preview wrappers and 4b's error-body snapshots, both byte-capped | `InvariantSuite` |

#### `NFR-1`–`NFR-17` (4 MUST, 13 SHOULD) — dispositioned here and nowhere else

The first column is the gate phase 0 built. The second is **what closing the requirement looks like
as an artifact**, which is the question this phase exists to answer and which `R2` argues.

| ID | Level | Phase 0's gate | Phase 9's disposition artifact | Expected mark |
|---|---|---|---|---|
| `NFR-1` | MUST | `gates:gemspec_audit`, `gates:require_allowlist`, `gates:clean_bundle` | `PackagingSuite` over each gem's **published** `Gem::Specification`, which is the subject `NFR-1`'s own conformance clause names | ✅ |
| `NFR-2` | SHOULD | `gates:gemspec_audit` | `PackagingSuite`, per adapter: core plus at most one. phase 0 plan, Task 9's per-gem denylist scope is named in the row, not fixed here | ✅ |
| `NFR-3` | SHOULD | `rbs:validate`, `steep`, the YARD gate | `PackagingSuite` enumerating each gem's exported constants and asserting each has a `sig/` mirror; no `private_constant` appears. **Phase 9's own code is inside this assertion's subject**, which is why `Check` is its own file and `Runner`'s helpers are `private_class_method` | ✅ |
| `NFR-4` | SHOULD | `gates:sig_diff`, `gates:surface_snapshot` | **No subject until a `v*` tag exists** (P0-8's pre-release branch). Phase 0 plan, Task 14's `Data`-reader snapshot decision narrows what the runtime snapshot contributes | ⏳ |
| `NFR-5` | SHOULD | SimpleCov `minimum_coverage 80` in `test:gems` | The gate's own aggregate number over the real tree, recorded | ✅ |
| `NFR-6` | SHOULD | `ruby -w` + `RUBYOPT=-W:deprecated`, `Warning.warn` raising | The gate's result, **with the hole phase 0 plan, Task 6's thread-count teardown assertion names**: thread death writes to `$stderr` and the override sees nothing | ✅, that hole cited |
| `NFR-7` | SHOULD | `rubocop --fail-level=convention` | The gate's result. **Phase 0 plan, Task 3's reviewed `.rubocop.yml` baseline says it is clean for no phase** under `.rubocop.yml` as phase 0 first wrote it | ⏳ pending that baseline |
| `NFR-8` | MUST | none — retargeted | **Vacuous by its own text** ("In ecosystems without such a build step this requirement does not apply"), §10.19, and §12 counts it among the eight vacuous MUSTs | N/A |
| `NFR-9` | SHOULD | none — retargeted with `NFR-8` | Vacuous with its antecedent. The retarget is dispositioned under `NFR-1`, not counted twice here | N/A |
| `NFR-10` | MUST | the 3.2/3.3/3.4/4.0 real-suite matrix; `gates:versions` | **Both kinds.** The matrix result (this build), plus a `PackagingSuite` assertion that each unit declares a floor and that a **higher** floor for an isolated capability is conforming, which `NFR-10` states outright. That is 8c plan, Task 3's per-gem Ruby floor gate edit: `dexpace-transport-async_http` at `>= 3.3` is conforming by the requirement and non-conforming by `gates:versions`, which asserts every gemspec equals the global floor | ⏳ pending that edit |
| `NFR-11` | SHOULD | `gates:rbs_surface` | **Both clauses, and the row names both.** Clause 1, no async-framework type in the core public surface: the gate plus `PackagingSuite`'s scan over each **shipped** `sig/` tree. Clause 2, "drive the same core call concurrently from multiple scheduler kinds and assert race-free results": `InvariantSuite`'s two `XCUT-11` assertions (plan Task 8) — sixteen threads on one shared instance, and the two-fibers-on-one-thread shape `8b` handed forward, which is the only one that sees a per-fiber mutex held across a suspension | ✅ |
| `NFR-12` | SHOULD | `gates:reproducible` | The gate's result, scoped by `P0-7` to one gem built twice on one interpreter | ✅, narrowly |
| `NFR-13` | SHOULD | `Dexpace/SpdxHeader`, a RuboCop cop | **Both kinds.** The cop's result, plus a `PackagingSuite` assertion that asserts the header is **present** on every shipped `sig/**/*.rbs` — the half a RuboCop cop cannot reach, since `.rbs` is not Ruby. It **fails** on the first-party tree today and goes green the day phase 10's repair lands; a body that vacuated unconditionally would check nothing for the porter `R2` puts this ID in the portable kind for. `NFR-13` is a SHOULD, so the failure records the gap and blocks no report | ⏳, phase 10's inbound list |
| `NFR-14` | SHOULD | `gates:versions` over the root `VERSIONS` | **Both kinds.** The gate's result, plus a `PackagingSuite` assertion that each unit's version equals its `VERSIONS` entry | ✅ |
| `NFR-15` | SHOULD | `Dexpace::VERSION` sourced from the gemspec | `PackagingSuite` reading the version at runtime from an installed gem and **comparing it to the resolved gemspec's version**, which is what the requirement names. A not-a-placeholder check alone passes at `0.0.0` — the version every gem here currently carries — and so would be green on a tree where `NFR-15` has never been satisfied | ✅ |
| `NFR-16` | SHOULD | none — no release path exists | Release-gated; `docs/first-release.md` § Release path, the signed-publication entry | ⏳ |
| `NFR-17` | MUST | the default `rake` task | **The meta-audit**: every gate in phase 0's seventeen is blocking, on every matrix row it is listed for. The `minitest` pin is the counterexample this phase found | ⏳ pending phase 0 plan, Task 2's `minitest` `~> 5.25` pin |

Seven plain ✅, two ✅-with-a-citation, two N/A and six ⏳ — seventeen — is the *prediction*, and the
⏳ marks divide two ways. **Four are pending a finding another task or phase owns**: `NFR-7` (phase 0
plan, Task 3's reviewed `.rubocop.yml` baseline), `NFR-10` (8c plan, Task 3's per-gem Ruby floor gate
edit), `NFR-13` (phase 10's inbound list, SPDX coverage for `sig/**/*.rbs`) and `NFR-17` (phase 0
plan, Task 2's `minitest` `~> 5.25` pin), the last two found by this design. **Two are pending a
release**, not a finding: `NFR-4` has no baseline until a `v*` tag exists, which is `P0-8`'s
pre-release branch, and `NFR-16` has no release path to enforce signing on, which is the
signed-publication entry in `docs/first-release.md` § Release path.
**None is pending a decision phase 9 gets to make**, which is the shape `R6` argues the
phase-9/phase-10 boundary into.

### Out of scope, explicitly

**No requirement outside `XCUT` and `NFR` is in phase 9's scope, and no earlier phase's row moves.**
Phase 9 cites `SEAM-12`, `SEAM-14`, `SEAM-15`, `SEAM-20`, `SEAM-21`, `SEAM-2`, `SERDE-3`, `SSE-37`,
`OBS-21`, `OBS-25`, `PAGE-36`, `TRANSPORT-1`–`30`, `ASYNC-1`–`22`, `PIPE-32`, `PIPE-33`, `PIPE-36`,
`PIPE-39` and `RECOV-31` as **evidence and as suite content**, because the hand-forward rows point at
them — but every one of those keeps its checklist row in the phase that owns it, and phase 9 carries
no row for any of them. That is the two-rows-one-obligation discipline phase 2 gave `SEAM-29` and
phase 3b gave `HTTP-46`, applied in the direction where the second row would be an audit rather than
an implementation, and it is the line that keeps this phase from silently re-scoping nine phases'
work into itself.

The gem's **gemspec, version and first release** are phase 8's and are out of scope here, per the
roadmap's phase-9 row ("owning neither its gemspec nor its release") and `docs/first-release.md`'s
`dexpace-conformance` row.

**Repairs are out of scope.** See `R6`.

**And so is anything a generator consumes.** Phase 9 ships **no runtime code a generated SDK
executes** — every line it writes lands in `dexpace-conformance`, in three repository gates or in
`test/` — so **nothing in this phase gates pointing an OpenAPI generator at the SDK or running a
generated client's smoke test**; that surface is complete when phase 8 lands. Phase 9 is a **release
gate**: what it blocks is publishing, which is why its outputs are checklist rows, a report and
`docs/first-release.md` lines rather than a gem a consumer adds.

---

## `R1` — what appendix B's 61 items owe this phase, section by section

**Decision: phase 9 writes suites for `B.8` and `B.9`; lifts the two artifacts earlier phases
explicitly named as lift targets for `B.3` and `B.4`; drives the already-written suites for `B.6` and
`B.7`; and dispositions `B.1`, `B.2` and `B.5` by reference to the owning phase's own suite, with a
committed coverage map as the artifact rather than a second copy of the tests.** `P9-1`.

The reason a decision is needed at all: **`B.1` through `B.7` cover subsystems whose IDs belong to
other phases.** 48 of the 61 items are in those seven sections. Re-implementing them in
`dexpace-conformance` would re-own seven phases' work; dropping them would abandon the roadmap's own
statement that appendix B is phase 9's scope. Neither is acceptable, so the question is which items
belong in a *portable* suite and which belong where they already are.

**The criterion is portability, and it comes from §9.3's own argument for the gem.** The conformance
gem exists because "a stubbing library needs a per-client shim, so the *same* assertions could not
run unchanged against `dexpace-transport-async_http` or a future `httpx` adapter — which is the whole
point of shipping `dexpace-conformance` as a gem from day one." An assertion earns a place in that
gem when **more than one implementation of one seam can be run against it**. An assertion over a
single core implementation does not become more true by being moved into another gem; it becomes a
test with one subject living in a package whose purpose is many subjects.

Applying that criterion:

| Section | Items | Owning phase | Phase 9's obligation |
|---|---|---|---|
| **B.1** Pagination | 10 | 7c | **By reference.** `Dexpace::Page::Paginator` and `AsyncPaginator` are core's single implementation; `PAGE-8` makes the engine stateless and shareable and there is no second engine to be portable across. Coverage map rows cite 7c's suite. The `B.1`/`B.2`/`B.5` entry in `docs/first-release.md` § Post-release triggers records what would change that |
| **B.2** SSE | 6 | 7b | **By reference**, same argument. One addition that is *not* by reference: `SSE-37`'s audit target is `gates:serde_boundary`'s `GUARDED` list plus "the repository-wide check that its `PENDING` list is empty", which 7b handed forward explicitly and which is a repository gate, not a suite assertion (`R4`) |
| **B.3** Serialization | 7 | 7a | **Lift, and the target is named.** 7a wrote `gems/dexpace-serde-json/test/support/serde_seam_assertions.rb` as "the named lift target for the conformance suite, written against the seam and never against `Dexpace::Serde::JSON` by name", and recorded the path in its checklist so "phase 9 inherits a target rather than a search". It becomes `Dexpace::Conformance::CodecSuite`, covering `SEAM-20`, `SERDE-3` and `SERDE-9` — the post-v1 `dexpace-serde-oj` is the second subject the lift is for. **Only those halves leave: the file is edited, never removed**, because `SEAM-21`, `SERDE-4`, `SERDE-12` and `SERDE-29` stay in it and `APPENDIX_B.md`'s `B.3` `by reference` rows name that path. **`SEAM-21` is NOT lifted**: it is the explicit-runtime-type-token rule, a property of the witness protocol (§10.14), and it stays in 7a's suite, recorded `scoped out` with that reason. `SERDE-4`'s offset matrix and `SERDE-12`'s I/O-error pass-through stay `by reference`, because 7a wrote them against a shape `CodecCase` does not carry. The reified-helper item is `restated per §9.3`. The `Tristate` and coercion items (`SERDE-14`–`SERDE-26`) stay with 7a — core's protocol, not the seam's |
| **B.4** Instrumentation | 8 | 5b, 5c | **Partial lift, already begun.** 8a placed `RecordingSpan` (5c's `OBS-21` obligation) and `Allocations` (5b's `R8`/`OBS-25` obligation) in `dexpace-conformance` already. §9.3 restates the allocation-freeness items as allocation-count assertions and keeps `OBS-1`'s shared-inert-event **identity** assertion exactly as written; both become `InvariantSuite`/`CoreSuite` assertions because they are the two `B.4` items §9.3 names by hand. The redaction items are `XCUT-19`'s subjects and are in `B.8` anyway. The rest: by reference to 5b/5c |
| **B.5** Configuration | 6 | 5a | **By reference.** The four-layer chain is one implementation; §9.3 restates one item (the `configure` tier as layer three) and that restatement is recorded in the coverage map, not re-litigated |
| **B.6** Transport | 5 | 8a, 8c | **Already written; phase 9 drives and aggregates.** `TransportSuite` exists with two drivers. Phase 9 adds no assertion and forks nothing (8a's `R16` forbids it) — it aggregates the two reports and audits the waivers, of which 8c's `TRANSPORT-14` is the one named |
| **B.7** Async runtime | 6 | 8b, 8c | **One new suite plus reference.** The harness half of `SEAM-25`'s lifecycle event (phase 2 postponed the event; 8b emits it) — "`dexpace-conformance` asserts 'close twice → executor shut once, one event'" — is unwritten after phase 8 and is phase 9's; it becomes `Dexpace::Conformance::ExecutorSuite`, covering `SEAM-12`, `SEAM-25` and `ASYNC-15`–`ASYNC-17` against a factory, with a **resource-free implementation supplied separately** for `ASYNC-17`, whose subject is by definition not a pool that owns a thread. **`SEAM-18` and `ASYNC-15`'s clause (c) are `scoped out` with reasons** — the first is the seam's shape rather than an implementation property and 8b asserts it; the second needs a pending interrupt, which §8.3 bans every primitive for. `ASYNC-3`'s and `ASYNC-4`'s dispositions are `R5`'s |
| **B.8** Cross-cutting | 6 | **phase 9** | **Written here** as `Dexpace::Conformance::InvariantSuite`. §9.3 restates one item — the seam-resolution item names require-time registration as the discovery substrate (`XCUT-23`) — and that restatement is honoured |
| **B.9** Non-functional | 7 | **phase 9** | **Written here** as `Dexpace::Conformance::PackagingSuite`. §9.3: "B.9 is exercised as §9's table, with NFR-8/NFR-9 inapplicable by their own text and replaced by §9.2" |

**The coverage map is the deliverable that makes "by reference" honest.** It is a committed file,
`gems/dexpace-conformance/APPENDIX_B.md`, with **one row per appendix-B item** — 61 rows — naming the
section, the item's requirement IDs, the suite or test file that covers it, and the status (`suite`,
`by reference`, `restated per §9.3`, `scoped out`, `waived`, `vacuous`). Without it, "by reference"
is a promise; with it, a reader can check every one of the 61 in one place, which is what a porter
running the checklist actually needs. `R7` states what keeps it current and what does not, and
The map's own preamble, written by the plan's Task 14, states the two checks over it that are
**not** achievable.

**The `by reference` residue is roughly 29 of 61, not 22, and the map is what makes it countable
rather than estimated.** `B.1`'s 10, `B.2`'s 6 and `B.5`'s 6 are the 22 `P9-1` covers outright;
`B.3`'s `Tristate` and coercion items and `B.4`'s items beyond the two §9.3 names by hand add roughly
seven more. Three statuses beyond `suite` and `by reference` carry the rest: `restated per §9.3` for
`B.3`'s reified-helper item (§9.3 restates `SERDE-7` as "the ergonomic decode helper routes through a
witness or combinator") and `B.5`'s four-layer-precedence item; and `scoped out` for `SEAM-21`,
`SEAM-18` and `ASYNC-15`'s clause (c), each with its reason in the row.

**One structural fact about appendix B that the map has to absorb, because §9.3's sentence assumes
otherwise.** §9.3 says "A failing **item** that the port has decided not to satisfy is reported as a
failure by the suite and suppressed … through a named waiver listing the requirement ID." But an
appendix-B item is not the suite's unit: `Assertion` carries `ids` (plural) and a `Result` carries
one status, while a single `- [ ]` item routinely rolls up a dozen IDs — `B.7`'s second item names
`ASYNC-3` *and* `ASYNC-4` in one bullet, and §9.3 itself requires those two to end with **different**
statuses, failing and vacuous. So the mapping is many-to-one and cannot be inverted: **the suite's
unit is one assertion per requirement ID; the appendix-B item is a view over them.** An item's status
in the map is the *worst* status among the assertions for its IDs, with every contributing status
listed. This is a decision, not a discovery, and it is recorded as `P9-8` so a later reader does not
try to make the two units line up.

---

## `R2` — what it means, mechanically, to disposition an `NFR`

**Decision: a disposition is a checklist row whose evidence is one of exactly four artifact kinds,
and the kind is chosen by who can re-run it — not by how the gate is implemented.** `P9-2`.

Phase 0's seventeen gates all answer a question. What they do not do is *record an answer*, and the
difference is the whole of this phase's `NFR` work. A gate that exits zero today tells you nothing
next month; a disposition is the durable statement, with the evidence named.

The four kinds:

1. **A portable conformance assertion** in `dexpace-conformance`, when the property is one a
   *third-party adapter author or porter* must also be able to check about their own unit. **Eight**
   are these — `NFR-1`, `NFR-2`, `NFR-3`, `NFR-10`, `NFR-11`, `NFR-13`, `NFR-14`, `NFR-15` — and
   they are the ones whose specification text is about **a unit** rather than about **this build**.
   They go into `PackagingSuite`.
2. **A recorded gate result** — the gate's own output over the real tree, captured in the checklist
   row with the number or the finding. `NFR-4`, `NFR-5`, `NFR-6`, `NFR-7`, `NFR-10`, `NFR-12`,
   `NFR-13`, `NFR-14`, `NFR-16` and `NFR-17` are these: each is a property of *this repository's
   build*. A portable assertion for `NFR-5` would be asserting that a stranger's gem has 80%
   coverage, which the requirement does not ask and the suite has no way to know.

**Three IDs appear in BOTH kinds, and that is not a double disposition — it is two audiences.**
`NFR-10`, `NFR-13` and `NFR-14` each carry a question about this repository's CI ("is the gate
enforcing it here?") and a distinct question about a unit ("can a porter check it against their own
reimplementation?"), and the second is the whole reason `dexpace-conformance` is a published gem
rather than a directory under `test/`. `NFR-10` in particular fits no single kind: its floor
declaration is a unit property the suite reads from a gemspec, while "run each unit's artifact on
its declared minimum runtime" is the CI matrix and travels nowhere. Each such ID gets **one**
checklist row naming both artifacts, never two rows.
3. **A recorded vacuity**, with the sentence that makes it vacuous quoted. `NFR-8` and `NFR-9`.
4. **A recorded absence of subject**, with the condition that would supply one. `NFR-4` (no `v*`
   tag) and `NFR-16` (no release path), both already carried by `P0-8` and `docs/first-release.md`
   § Release path.

**Why `PackagingSuite` reads published metadata and not the source gemspec, when phase 0's
`gates:gemspec_audit` already reads the source.** `NFR-1`'s own conformance clause says "the core
artifact's **published dependency metadata** lists zero runtime dependencies beyond the stdlib". A
source gemspec and a published one can differ — a gemspec that computes its dependencies, a build
that injects one, a `.gem` assembled from a different tree. Phase 0's gate is the pre-publication
check and is the right shape for CI; `PackagingSuite` reads `Gem::Specification.find_by_name(name)`,
which is what a consumer's process actually resolves, and is the right shape for the claim. **Two
checks, two subjects, both named** — and the second is the one a third party can run against a gem
they installed rather than a tree they cloned. Recorded as `P9-2`.

**What this phase deliberately does not do to a gate.** It does not lower `--fail-level`, does not
add an `Exclude:`, does not relax a metric cop, and does not switch a gate to report-only —
`NFR-17`'s whole content is that no gate is advisory, and a phase that relaxed one while
dispositioning that requirement would be falsifying its own evidence. Where a gate cannot pass today
(phase 0 plan, Task 3's reviewed `.rubocop.yml` baseline says RuboCop cannot, for any phase), the
disposition is ⏳ **with that finding's owner cited**, and
the repair is phase 10's.

---

## `R3` — how to audit a claim about code that does not exist

**Decision: every audit task is an existence probe followed by a property assertion, the probe's
target is a path-and-constant taken verbatim from the phase document that promised it, and a probe
that fails routes the finding to its owner rather than improvising.** `P9-3`.

This is the honest problem at the centre of the phase, and it deserves to be stated plainly rather
than managed. **Phase 9 is being planned on 2026-09-12, before a single line of `gems/` exists.**
Every subject in the `XCUT` table above is a promise in a design document. Three ways that promise
can fail to be kept, and each needs a different answer:

**The artifact arrives with a different name.** A constant renamed, a method moved, a
`private_constant` made public or the reverse. The probe fails, the audit task **corrects the name in
the checklist row and says it is correcting it**, and proceeds. Nothing to route — a rename that
preserves the property is not a finding, and this repository has already learned that silently
correcting a committed document is worse than correcting it loudly.

**The artifact arrives with a different shape, and the property still holds by another route.** The
audit task asserts the property against the shape that arrived, records the divergence in the
checklist row naming both shapes, and routes a finding to phase 10's inbound list **against the design document that
promised the other shape** — because a design document that describes something that was not built is a
document the next reader will trust wrongly. The requirement row itself can still be ✅.

**The artifact is absent.** The suite reports **`:vacuous`, carrying a mandatory reason string** —
`"<name> is absent; <phase> committed to it"` — and never `:failed`. Phase 9 is planned before any
code exists, so at execution time an artifact may legitimately not be built yet, and `:failed`
conflates *not built* with *built wrong*, which is precisely the distinction phase 10 acts on.
**Nothing passes by not being built**, and this is the clause that makes that true: the aggregate
report lists every **un-waived `:vacuous` on a MUST-level ID separately, and that list is a phase-9
report blocker** — the phase does not close with one outstanding — with each entry earning a
`docs/first-release.md` line. A SHOULD-level vacuity is recorded and does not block. The row is ⏳,
the finding goes to phase 10's inbound list, and the repair is phase 10's.

**The property does not hold.** The suite reports `:failed`, the row is ⏳ or 🚫 with the reason
named, the finding goes to phase 10's inbound list, and **the repair is phase 10's** (`R6`). If the ID is a MUST,
`docs/first-release.md` gains a blocker line, because an unmet MUST is a release question and not
only an audit finding.

**What makes this workable rather than a stack of conditionals** is that the promises are unusually
precise. Phase 4a named `Dexpace::BoundedMap` and `Dexpace::CallKey` as `private_constant`s reachable
by bare name from any full-nesting descendant, and said in `P4-3` that "phase 6's `AUTH-19` store and
phase 9's `XCUT-14` audit are both `dexpace-core` code, so the sharing works" — a probe target
precise enough to fail loudly. 8a named thirteen constants in `dexpace-conformance` with their roles.
7a named a file path. The plan's audit tasks quote these, and **the plan is written so that the probe
is the first line of every audit task**, not an assumption buried in one.

**One consequence for the plan's TDD shape, stated because it is not the usual one.** For the suites
phase 9 *writes* — `InvariantSuite`, `PackagingSuite`, `CodecSuite`, `ExecutorSuite`, the aggregate
report — TDD is ordinary: a failing test against a deliberately non-conforming double, then the
assertion, then green. `dexpace-conformance`'s own suite already drives a `FakeTransport` for exactly
this (8a), and phase 9 adds non-conforming doubles per suite: a codec that closes its sink, an
executor whose close is not idempotent, a "model" that aliases a caller's hash, a gemspec fixture
with two runtime dependencies. **The double is the unit under test, not the real gem** — which is
what makes the suite testable before the audit runs and is why a green suite proves the *instrument*
works and not that the SDK conforms. Those are different claims and the plan keeps them apart.

---

## `R4` — which checks are suite assertions and which are repository gates

**Decision: a check whose subject is a seam implementation's observable behaviour is a conformance
assertion; a check whose subject is this repository's source tree is a Rake gate. Four repository-wide
invariant scans are gates, built on `RubyVM::AbstractSyntaxTree`, and they are recorded as a Design §9
addendum.** `P9-4`.

Four hand-forward rows ask for something a behavioural assertion cannot express, because they are
statements about **the absence of a second implementation** rather than about what one implementation
does:

| Gate | What it scans | Handed forward by | IDs |
|---|---|---|---|
| `gates:cause_walk` | every `.rb` under `gems/*/lib/`, failing on a `#cause` send outside `Dexpace.each_cause`'s own file — **`:CALL`, `:QCALL` and `:VCALL`, plus `send`/`__send__`/`public_send`/`method` naming `:cause` as a literal**, plus `:FCALL` and `&:cause`, skipping an argument-carrying send (5b's `Event#cause(e)`); 10 of 12 decidable shapes, misses dispositioned by the plan's Task 13; `send(variable)` undecidable | 4b: "`Dexpace.each_cause` as the single walk, and the repository-wide check that nothing else walks `#cause`" | `XCUT-9` |
| `gates:bounded_map` | every `.rb` under `gems/*/lib/`, failing on a `Hash`-valued instance variable outside `BoundedMap`'s own file and a named allowlist — a literal, `Hash.new`, `::Hash.new` or a chained call on either; **4 of 6 shapes, and a Hash arriving from a method return or a parameter is an acknowledged blind spot**; 5 of 9 decidable shapes in the wider battery, misses dispositioned by the plan's Task 13. **Adjudicated 2026-09-13 against the filed fences: 6 hits in 5 files, 5 false positives allowlisted with their reason and 1 true positive, `Clients#@by_origin`'s missing cap, now on phase 10's inbound list** — the rule is unchanged, the allowlist is `InvariantGates::BOUNDED_MAP_ALLOWED` and has four entries, and a keyed-read narrowing was written, measured (6 → 3) and rejected for opening a cross-file blind spot | 4a: "the same map, as the single implementation the audit checks" | `XCUT-14` |
| `gates:serde_boundary` | 7b's existing gate — phase 9 adds the assertion that its `PENDING` list is **empty** | 7b: "the audit target … and the repository-wide check that its `PENDING` list is empty by the end of phase 7" | `SSE-37` (7b's row; evidence here) |
| `gates:seam_names` | core's `lib/` tree for a concrete seam implementation, matched by the **adapter-owned leaf namespace** anywhere in the path — `Serde::JSON`, `Transport::NetHTTP`, `Transport::AsyncHTTP`, `Async::Thread` — over constant paths **and** string literals, so `Serde::JSON`, `::Dexpace::Serde::JSON` and `const_get("Dexpace::Transport::NetHTTP")` all match. A fixed list of four fully qualified names caught **0 of 4** realistic shapes, and a seam-namespace suffix rule flagged 31 conforming references in 15 of core's filed files; the leaf rule catches 5 of 7 decidable shapes (misses dispositioned by the plan's Task 13) with zero hits on core's filed fences, and **does** need its list, which a later adapter gem extends | 7a: "the negative test over core's tree as the audit's existing evidence, rather than a repository-wide grep reconstructed at audit time" | `SEAM-2` (phase 2's row; evidence here) |

**Why these are gates and not assertions.** `dexpace-conformance` ships in `lib/` so a third party can
run it against *their* gem. A scan of `gems/*/lib/` is a scan of **this** repository and would be
meaningless in a consumer's process — there is no `gems/` there. Putting it in the conformance gem
would also require that gem to read the filesystem of a tree it does not own, which is the kind of
implicit coupling §9.3 shipped a separate gem to avoid.

**Why the AST and not a regex.** `grep '\.cause'` matches a comment, a string, an `# XCUT-9` citation
in a test header and the requirement ID itself. Verified fact 1 shows `RubyVM::AbstractSyntaxTree`
gives the method symbol on a send node — **`:CALL`, `:QCALL` and `:VCALL`, all three** — identically
on 3.2.11, 3.4.10 and 4.0.6. The parser warns on nothing itself; **verified fact 1b** is what governs
the suite, because phase 0's shared test case **overrides `Warning.warn` to raise** and a scanned
file's own `-w` diagnostics do reach it — so every parse goes through `AstScan.parse`'s `$VERBOSE`
window. The inference, stated: a three-interpreter-identical parser means the gate needs no
conditional require and no interpreter guard, cheaper than the Prism alternative verified fact 2 allows.

**Why they are an addendum rather than a silent addition.** Design §9's gate table is frozen. The
roadmap's cross-cutting constraint 6 fixed the procedure when phase 0 faced exactly this — "so phase
0 records it there as an addendum in its design doc" — and this design follows it: a
**Design §9 Addendum** section below, with a Deviation Ledger row per addendum for consolidation into
design §10.

---

## `R5` — the two dispositions a reader will check first, and what the report prints

**`ASYNC-3`.** §9.3 says its `B.7` item "is recorded as *failing* rather than vacuous, since
`dexpace-async-thread` supplies the blocking-task-on-a-worker antecedent the requirement conditions
on (§10.5)". 8a's mechanism makes it `:waived` — "`ASYNC-3`'s waiver is `8b`'s to pass; the mechanism
is `8a`'s to build". Those are two different statuses, and phase 9 is the phase that prints the
aggregate.

**Decision: the assertion is written so it genuinely fails, the first-party build waives it by
requirement ID, and the aggregate report prints `waived (would fail): ASYNC-3` — never
`passed`, never `vacuous`.** 8a's `Report#to_s` already "names every waived ID on every run, per
§9.3's 'the gap stays visible'", and §9.3's own sentence is satisfied by a failure that is suppressed
through a named waiver, which is precisely what it describes. The distinction phase 9 must not lose
is between `:waived` and `:vacuous`: a waived assertion *would have failed*, a vacuous one could not
have run. The report prints them in separate sections with separate counts, and `docs/first-release.md`'s
standing blocker — "a green conformance run's omissions must be written down before the gem is
published" — is what carries it to a reader who never runs the suite.

**`ASYNC-4`** is `:vacuous` and is on **no unsatisfied-MUST entry**, which is deliberate and which the
roadmap corrected in place on 2026-09-11: that entry (`docs/first-release.md` § What v1 ships without ›
Unsatisfied MUSTs) covers `ASYNC-3` and `PIPE-33`'s interrupt clause, and "`ASYNC-4` is deliberately
absent from it and should stay absent". Phase 9 does not add it.

**`NFR-8`.** §12 counts it among the eight MUSTs that hold vacuously. Phase 9 marks it **N/A**, not
✅ and not 🚫, and the retargeted checks (`gates:require_allowlist`, `gates:clean_bundle`) are
dispositioned under `NFR-1` where they do work rather than under `NFR-8` where they would be a
second count of the same gate. `NFR-9` follows its antecedent. `P9-5`.

---

## `R6` — the phase-9 / phase-10 boundary

**Decision, stated in as many words: phase 9 measures and reports; phase 10 repairs. Phase 9 ships
code only into `dexpace-conformance` and into the four new Rake gates, and it fixes a defect it finds
in no other gem, including a defect in an unmet MUST.** `P9-6`.

The roadmap's phase-10 row is "Deviation Reconciliation and Release Readiness — **every gem**
(audit-led; **ships code where the audit finds a defect**)", and its ordering rationale says phases 9
and 10 "audit what phases 0–8 built rather than building anything new, and phase 10's method,
re-deriving every ledger claim from as-built source, is why it **may ship code** even though its scope
is an audit." The permission to repair is phase 10's, named twice, and is not phase 9's.

**What phase 9 does when an audit fails**, in order and without discretion:

1. The suite reports the assertion `:failed` — or `:vacuous` with a reason, if the *artifact* is
   absent rather than wrong (`R3`). It is never restated to pass and never skipped. §9.3: "the gap
   stays visible rather than disappearing into a restated item." An un-waived MUST-level `:vacuous`
   is a **report blocker**, which is what stops the vacuity route from becoming a pass.
2. The checklist row for the ID is ⏳ or 🚫 with the reason and the failing assertion named.
3. The finding is **routed to its owner** with what was measured, on which interpreters, and what
   would resolve it: a numbered task in the owning phase's plan, or phase 10's inbound list in the
   roadmap when the repair belongs to a phase already planned. There is no register to append to.
4. **If the ID is a MUST**, `docs/first-release.md` gains a blocker line, because an unmet MUST is a
   release decision and `docs/first-release.md` is the register that holds those. The suite may carry
   a named waiver so the first-party build is not red forever, and the waiver's existence is itself
   printed on every run.
5. If the failure contradicts a claim in design §10 or §12, a dated entry goes to
   `docs/deviations.md`'s "Deviations found outside a phase" section — the holding area §10's frozen
   status requires — and **phase 10 folds it in**.

**The one exception, and its reason.** A defect **inside `dexpace-conformance` itself** that prevents
the suite from running is phase 9's to fix, because otherwise the phase has no instrument and the
audit does not happen. This is narrow: it covers the suites, the drivers, the fixture and the report,
and it does not extend to `dexpace-core` or to any adapter. A bug found in `WireServer` is fixed here;
a bug found in `Dexpace::BoundedMap` is filed here and fixed by phase 10.

**Why not let phase 9 fix the small ones.** Because "small" is the judgement that erodes the boundary,
and because a phase that both measures and repairs cannot report an unrepaired finding without it
looking like a choice. The audit's value is that its findings are not filtered by whether the auditor
felt like fixing them.

---

## `R7` — what keeps the coverage map honest, and what does not

**Decision: the map's 61 rows are generated from the suites where the suite is the evidence, and
hand-written where the evidence is another phase's test file — and the hand-written half is checked
by a test that does not check what a reader will assume it checks.** `P9-7`.

A generated map is trustworthy for the rows whose evidence is an `Assertion` in this gem: the
generator walks every suite's `.assertions`, reads each `Assertion#ids`, and emits the rows. That is
exact and cannot drift.

The "by reference" rows are the problem. Their evidence is a test file in another gem, and there is no
mechanism by which a test file announces which appendix-B item it covers. Two things phase 9 can
check, and one it cannot:

- **Can check:** the referenced file exists, and it contains the requirement IDs the row claims, in
  its header comment — which `CLAUDE.md`'s conventions already require ("A test file's header comment
  names the IDs it exercises"). A test asserts both, per row.
- **Can check:** every requirement ID appearing in any appendix-B item appears in at least one row of
  the map. That is 61 items' worth of IDs against the map's own rows, and it catches an item dropped
  from the map entirely.
- **Cannot check:** that the referenced test actually *asserts* the behaviour the item describes.
  Nothing mechanical can, short of re-implementing the assertion — which is what "by reference" exists
  to avoid.

That residue is real and is recorded rather than glossed: **a `by reference` row proves an ID is
claimed and a file exists, not that the behaviour is tested.** It is stated in the map's own preamble,
in the report's preamble, and it is why `docs/first-release.md`'s blocker about naming a green run's
omissions covers appendix B and not only the wire fixture's TLS gap.

---

## `R8` — the `XCUT-11` predicate, because nine rows point at it and none defines it

**Decision: a shared instance conforms to `XCUT-11` when it is frozen, or when every mutable instance
variable it holds is one of two named kinds — a `Thread::Mutex` and the state that mutex guards, or
`Dexpace::Closeable`'s `@closed` latch — and per-call state lives on a cursor, a walk, a scope or the
call's own stack.** `P9-9`.

`XCUT-11` is the heaviest single target in the hand-forward set: **nine rows across five phase
documents**, each naming different objects as "the audited shared instance". No phase defined what
"audited" means, and a naive predicate — *frozen and no instance variables* — would fail every
closeable component in the SDK, because `Closeable`'s latch is by construction mutable state on a
shared instance, and `cross-cutting-invariants/89eb6533` says so: close idempotence "is implemented as
a latch — a `@closed` boolean flipped under a `Thread::Mutex`". A predicate that condemned the one
mechanism the corpus prescribes would be measuring the wrong thing.

So the predicate has two halves, and both are assertable:

**Structural half** — over the class, using `instance_variables` on a built instance (verified fact 4
family: `instance_variables` returns `[:@lock]` on a frozen instance identically on all three
interpreters): either `frozen?`, or every ivar is in the allowlist the object declares. The allowlist
is not a constant in `dexpace-conformance` — it is **per-object, supplied by the suite's subject**,
because only the object knows which ivar is its mutex and which is the state under it. An object that
declares nothing and is not frozen fails.

**Behavioural half** — `XCUT-11`'s own conformance clause: "invoke one shared step instance from many
threads with distinct requests and assert no cross-talk." Sixteen threads, distinct requests,
assertions on the results rather than on timing. `8b`'s design already handed forward "the
**two-fibers-on-one-thread** test, which is the only shape that proves a per-fiber mutex is not held
across a suspension point", and phase 9 adopts that shape as the second behavioural assertion because
`Thread::Mutex` ownership being per-fiber is one of `CLAUDE.md`'s constraints-that-will-bite and a
thread-only test cannot see it.

The nine subjects, so the plan has a list rather than a search: 4a's `ContextStore`; 4c's
`Dexpace::Pipeline` and `AsyncPipeline` (with `Cursor` as the per-call state, and the audit target
being that nothing else is); 5a's `Configuration` and `Clock::SYSTEM`; 5b's `Redactor` and
`RedactionPolicy`; 5c's seven frozen stateless singletons (with `Scope` as the object that
deliberately holds per-call state on the call's own stack); 6a's `Policy` and `RetrySettings`; 7a's
`Codec`; 7c's `Paginator` and `AsyncPaginator` (with `Walk` as the per-call state); 8a's `Adapter`
(whose only mutable state is `Closeable`'s latch); and 8b's five concurrency assertions as existing
evidence.

---

## The 33 hand-forward obligations, each resolved

`grep -rn '\*\*Phase 9\*\*, on' docs/work/mvp/` returns **33 rows in 13 predecessor documents**.
(The charter said 31 rows in eleven documents; both numbers were wrong, and the eleven is how the
33 went wrong in the first draft of this table — **the two phase-6 files were missed**, which is
exactly the six rows that table dropped. The table below is rebuilt from the grep in the grep's own
order, and the four rows named in the second sweep are a **separate block** underneath, because the
prescribed grep does not return them.)

| # | Handed forward by | On | Resolution |
|---|---|---|---|
| 1 | 4a | `XCUT-14` | `gates:bounded_map` (`R4`) plus `InvariantSuite`'s two assertions — the cap clause and the deterministic drain-to-cap clause, which is the **only** line on that clause now `gates:drain_loop` is out of v1. Plan Tasks 7 and 13 |
| 2 | 4a | `XCUT-11` | `ContextStore` is subject 1 of nine (`R8`). Tasks 4, 8 |
| 3 | 4b | `XCUT-8` | `ProtocolError.for` / `.for_or_nil` — two forms, one assertion. Task 6 |
| 4 | 4b | `XCUT-9` | `gates:cause_walk` plus the cycle-safety assertion, **three-node and step-bounded**. Tasks 6, 13 |
| 5 | 5c | `XCUT-11` | Seven frozen singletons; `Scope` as deliberate per-call state. Tasks 4, 8 |
| 6 | 5c | `XCUT-20` | The **scoped** claim: satisfied for what 5c owns, not extended to a foreign callback (`OBS-20` forbids that). Task 7 |
| 7 | 6a | `XCUT-5`/`XCUT-6`/`XCUT-7` | Three distinct objects, audited as three: `Retryability.retryable_status?`, `Policy.throwable_retryable?`, `RetrySettings#retryable_statuses`. Task 6 |
| 8 | 6a | `XCUT-11` | `Policy` and `RetrySettings`. Tasks 4, 8 |
| 9 | 4c | `XCUT-11` | `Pipeline`/`AsyncPipeline`, with `Cursor` as the permitted per-call state. Tasks 4, 8 |
| 10 | 4c | the conformance pass | `PIPE-33` (an unsatisfied MUST, §10.5), `PIPE-36` (declined for v1, `docs/first-release.md` § What v1 ships without), `PIPE-39` (`Pipeline.standard`, phase 6b's Task 13a), `PIPE-32`'s vacuity. **Recorded in the aggregate report's preamble; no phase-9 checklist row** — those IDs are 4c's. Task 16 |
| 11 | 5b | `XCUT-19` | `RedactionPolicy::DEFAULT` and `HTTPLogging::DEFAULT` as clauses (a)/(b)/(c)/(e), **written in full**. Task 7 |
| 12 | 5b | `XCUT-20` | `Instrumentation.contain`, `Redactor#url`'s sentinel, `Preview.render` — three totality paths. Task 7 |
| 13 | 5b | `XCUT-11` | `Dexpace::Instrumentation::Redactor` and `RedactionPolicy` — **the filed name, not `Dexpace::Redactor`**. Tasks 4, 8 |
| 14 | 7b | `SSE-37` | `gates:serde_boundary`'s `PENDING` list asserted empty (`R4`, addendum A7). Task 13 |
| 15 | 7b | `XCUT-12`/`XCUT-15` | `SSE::Event`'s frozen `Data` satisfies `XCUT-15` by construction; phase 9's rows cite 7b's objects and 7b carries none. `XCUT-15` is Task 5, `XCUT-12` Task 8 |
| 16 | 6c | `XCUT-14`'s audit | `BoundedMap`'s second consumer, `DigestHandler`'s nonce store, per-handler rather than process-wide. Tasks 7, 13 |
| 17 | 6c | `NFR-11`'s RBS scan | **`Dexpace::Auth::BearerProvider`** — the one documented duck-type interface 6c names without enforcing via `include` — is named as the `PackagingSuite` `NFR-11` scan's subject: it must appear as an RBS `interface` and never as a foreign constant. Task 9 |
| 18 | 8b | `XCUT-11` | The five concurrency assertions, **and the two-fibers-on-one-thread shape adopted as `XCUT-11`'s second assertion** (`R8`). Task 8 |
| 19 | 8b | `XCUT-13` and `XCUT-22` | `Pool#close` bounded, non-blocking, latched; the BYO-executor survival assertion. `ExecutorSuite`. Task 11 |
| 20 | 8b | `SEAM-12` | `#post`-from-16-threads and `#post`-racing-`#close`. `ExecutorSuite`. Task 11 |
| 21 | 5a | `XCUT-11` | `Configuration`, `Clock::SYSTEM`. Tasks 4, 8 |
| 22 | 5a | `XCUT-19`/`XCUT-21` | `Dexpace::UUID` asserted as **not** the CSPRNG path, and `Proxy`'s masked rendering — the negative half matters as much as the positive, because `CFG-32` requires a non-cryptographic UUID. Task 7 |
| 23 | 7a | `SEAM-20`/`SEAM-21`/`SERDE-3` | The lift: `serde_seam_assertions.rb` → `CodecSuite`. **`SEAM-21` is not lifted** — it is the explicit-runtime-type-token rule, a property of the witness protocol (§10.14), and stays in 7a's suite; the close-the-target clause is `SEAM-20` plus `SERDE-3`. Task 10 |
| 24 | 7a | `XCUT-12` | `Codec` frozen and cache-free, **and the stated reason there is no per-type cache to audit** (`SERDE-29`) — recorded `:vacuous` with that reason, never `:passed`. Task 8 |
| 25 | 7a | `XCUT-15` | `Tristate`, `DecodeContext`, four combinators; `Native.of` returning fresh collections. Task 5 |
| 26 | 7a | `SEAM-2` | `gates:seam_names` over core's tree, **matching by path suffix** (`R4`). Task 13 |
| 27 | 7c | `XCUT-11` | `Paginator`/`AsyncPaginator`, `Walk` as per-call state. Tasks 4, 8 |
| 28 | 7c | `XCUT-13`/`XCUT-22` | `Page` as `Closeable`'s second consumer where the resource is a whole `Response`. Tasks 5, 11 |
| 29 | 7c | the conformance pass | `PAGE-35`'s vacuity (design §12's) **and `PAGE-15`'s wrapping clause (`P7-1`), which §12's `PAGE` row does not record** — the second goes to `docs/deviations.md`'s holding area for phase 10. Task 16 |
| 30 | 8a | the conformance assertion protocol | The protocol every later suite extends. Consumed and unchanged — with one addition stated rather than hidden: `Runner` is **new shared infrastructure** in a gem phase 8 owns (see the object-model section). Tasks 2–12 |
| 31 | 8a | `SEAM-12`, `SEAM-14`, `SEAM-15` | §9.3's three lifecycle assertions, already written and adapter-driven, so phase 2's ⏳ rows have an implementation to point at. Task 16 |
| 32 | 8a | `OBS-21` and `OBS-25` | `RecordingSpan` and `Allocations`, already in the gem. Phase 9 adds **no assertion**: `B.4`'s two §9.3-named items — the allocation-count restatement and `OBS-1`'s shared-inert-event identity — are recorded in `APPENDIX_B.md` `by reference` to 5b's and 5c's suites, which own those IDs. Task 14 |
| 33 | 8a | `XCUT-11` | `Adapter` as frozen-except-the-latch, with 8a's verified fact 9 as the measurement. Tasks 4, 8 |

**Four further obligations, found by the second sweep and not returned by the prescribed grep.** They
are listed separately because presenting them inside the table above is how the first draft came to
claim "no row is dropped and none is added" while having done both.

| Source | On | Resolution |
|---|---|---|
| 8a's plan (line 1044) | `Report#to_h` | 8a deferred the structured renderer as "`NFR-4`-locked surface with no caller until phase 9 aggregates". **Phase 9 is the caller**, so it ships `#to_h` with a `sig/` mirror. Task 3. (8a records this **once** in its plan; the second mention is its design's own open question 6, which is a different thing) |
| phase 1's postponement of the wire-boundary re-validation | `XCUT-18` | "phase 9's conformance suite is where the assertion that it happened belongs" — the wire-boundary re-validation assertion, driven through a forged `Dexpace::Request`. Task 7 |
| phase 2's postponement of `SEAM-25`'s lifecycle event | `SEAM-25` | The harness half, which 8b's design assigned to `8a` and 8a did not write. **Phase 9 writes it and records the correction as a correction.** Task 11 |
| phase 0's design (line 93) | the conformance assertion protocol | "phase 9 adds the remaining suites" — the second half of the pick-up condition. Tasks 2–12 |

## Design §9 Addendum — gates this phase adds to §9's table

Design §9's gate table is frozen and is not edited by this phase. The three gates below are additions
the table does not carry, recorded here as the roadmap's cross-cutting constraint 6 directs, each with
a Deviation Ledger row for consolidation into design §10.

| Addendum | What §9's table says | What phase 9 builds |
|---|---|---|
| **A4 — `gates:cause_walk`** | Nothing. §5.2 puts the cycle-safe walk in core; no row mechanises "only one walk" | An AST scan of `gems/*/lib/**/*.rb` failing on a `#cause` send outside `Dexpace.each_cause`'s own file, with a named allowlist carrying the requirement that justifies each entry. Covers `:CALL`, `:QCALL`, `:VCALL`, `:FCALL`, `&:cause` and the four reflective sends, and skips an argument-carrying send, which `Exception#cause` never is; 10 of 12 decidable shapes, misses dispositioned by the plan's Task 13; **`send(variable)` is undecidable and is written into the gate's own stated gap** (`XCUT-9`) |
| **A5 — `gates:bounded_map`** | Nothing. §5.4 states "one implementation"; no row checks it | One scan. It fails on a `Hash`-valued instance variable outside `Dexpace::BoundedMap` and a named allowlist — **4 of 6 realistic shapes, with a method return and a parameter acknowledged as blind spots**, and 5 of 9 decidable shapes in the wider battery; a third blind spot was measured in the same adjudication, a Hash held inside a value object rather than on the ivar (8c's `DropPolicy`). Its allowlist is **four entries, each carrying its reason**, and the one hit that is *not* allowlisted is the phase's finding: `async_http/clients.rb`'s uncapped per-origin client cache, which phase 10's inbound list carries as `Clients#@by_origin`'s missing cap. The drain-loop clause has **no scanner**: `InvariantSuite`'s deterministic behavioural assertion decides it (`XCUT-14`), and the shape check that would have sat beside it is out of v1 for the reason stated below the table |
| **A6 — `gates:seam_names`** | §9.2's require-allowlist covers `require`; nothing covers a **constant reference** | An AST scan of `dexpace-core`'s `lib/` for a concrete seam implementation, matched by the **adapter-owned leaf namespace** over both constant paths and string literals — 5 of 7 decidable shapes and zero hits on core's filed fences, where a fixed name list caught 0 of 4 and a seam-namespace suffix flagged 31 conforming references; misses dispositioned by the plan's Task 13 (`SEAM-2`). 7a already wrote the negative test; this is its repository-wide form |
| **A7 — `gates:serde_boundary`'s `PENDING` assertion** | Nothing; the gate is 7b's own addendum | The gate exists after phase 7; phase 9 adds the assertion that its `PENDING` list is empty, which is the clause 7b handed forward and could not assert while phase 7 was still running (`SSE-37`) |

All four run in the `gates` CI job alongside phase 0's interpreter-independent gates — **three newly
placed there**, and `gates:serde_boundary` already there because 7b wired it into the default task
(7b plan:1758), which phase 0's `ci_workflow_test.rb` (phase 0 plan:3610) already requires to appear
in a job — and all four are blocking — a non-blocking addition to a gate set while dispositioning `NFR-17` would be
self-falsifying. **Adding them means editing the root `Rakefile` and `.github/workflows/ci.yml`.**
`DEFAULT_GATES` is defined in the `Rakefile`, which `load`s `tasks/*.rake` **before** defining the
array and then freezes it (phase 0 plan, Task 1 Step 6), so a task defined only in
`tasks/gates.rake` is off `task default:` and therefore advisory — the one thing `NFR-17` forbids;
and phase 0's `ci_workflow_test.rb` is itself a blocking gate asserting that every entry in
`DEFAULT_GATES` appears in some CI job, so a phase that adds gates and leaves the workflow alone
reddens a phase-0 gate. The root `Rakefile` is therefore on this phase's file list, for that one
reason. Each gate's **stated gap** is part of the addendum rather than a footnote: a gate whose blind
spots are unwritten is a gate nobody can audit, and all three new ones are floors on their
invariant rather than proof of it.

**`gates:drain_loop` was the fourth addendum gate and is out of v1** *(decided 2026-09-13)*. `A5`'s
second scan asserted `XCUT-14`'s drain clause as *shape*; `InvariantSuite`'s `bounded_map_drains`
decides the same clause **behaviourally and deterministically** (a store pre-filled to cap + 5, then
one `set`: a drain loop ends at 8, a check-then-evict at 13, identically on all four interpreters),
while the gate measured **1 of 3 non-conforming shapes caught with one false positive**. A second
line weaker than the first is a cost, not evidence. The trigger that would bring it back is in
`docs/first-release.md` § Post-release triggers.

**`A5`'s six hits over the filed fences are adjudicated, not left as a number.** Re-measured
2026-09-13 over every Ruby fence in phases **0**–8 that names a `lib/` path — 222 fences at 184
distinct `gems/*/lib/**/*.rb` paths, 2 of which do not parse and neither of which holds a `Hash`
ivar — the two gate fences run **exactly as filed** report **6 `bounded_map` offences in 5 files**
while `cause_walk` and `seam_names` report **0**, identically on 3.2.11, 3.3.12, 3.4.10 and 4.0.6.
Five of the six are false positives and are now entries in `InvariantGates::BOUNDED_MAP_ALLOWED`,
each carrying its reason: `BoundedMap`'s own store, `Configuration::Builder`'s two accumulators, one
log `Event`'s field bag, and one `RecordingSpan` double's record. What they share is `XCUT-14`'s own
last clause — their primary cleanup mechanism is the owner being dropped after a single operation,
so a cap could never be the memory backstop — and that property is a **lifetime**, which is not
decidable from one file. The sixth is a true positive and stays red: `async_http/clients.rb`'s
uncapped per-origin client cache — phase 10's inbound list carries it as `Clients#@by_origin`'s
missing cap — which is what makes the other five credible rather than
convenient. **The gate's rule is unchanged.** The obvious generalising narrowing — report only an
ivar the file also reads by key — was written and measured, takes 6 offences to 3, fails to remove
the entry it was aimed at (`@fields.key?(Keys::EVENT)` is a keyed read with a constant key) and
opens a new statically decidable blind spot: a cache written in one file and looked up in another
through an `attr_reader`. Two proxies deep is worse than one honest allowlist line per file. The
corpus was reconstructed independently of the earlier round's, which is why its fence count differs
from the plan's Task 13 count of 199 of 202 while the hit set is identical.

---

## Module layout

Every file phase 9 creates or modifies. `sig/` mirrors `lib/` one file per file and ships inside the
gem; `test/` mirrors `lib/` and does not ship. One public constant per file
(`module-organization/1828a984`).

```
gems/dexpace-conformance/
  lib/dexpace/conformance.rb                  MODIFIED: a require_relative per new constant
  lib/dexpace/conformance/check.rb            Dexpace::Conformance::Check          the one primitive
  lib/dexpace/conformance/runner.rb           Dexpace::Conformance::Runner         the five statuses
  lib/dexpace/conformance/invariant_case.rb   Dexpace::Conformance::InvariantCase  incl. #probe!
  lib/dexpace/conformance/invariant_suite.rb  Dexpace::Conformance::InvariantSuite B.8
  lib/dexpace/conformance/packaging_case.rb   Dexpace::Conformance::PackagingCase
  lib/dexpace/conformance/packaging_suite.rb  Dexpace::Conformance::PackagingSuite B.9
  lib/dexpace/conformance/codec_case.rb       Dexpace::Conformance::CodecCase
  lib/dexpace/conformance/codec_suite.rb      Dexpace::Conformance::CodecSuite     B.3, lifted from 7a
  lib/dexpace/conformance/executor_case.rb    Dexpace::Conformance::ExecutorCase
  lib/dexpace/conformance/executor_suite.rb   Dexpace::Conformance::ExecutorSuite  B.7, SEAM-25's harness
  lib/dexpace/conformance/shared_instance.rb  Dexpace::Conformance::SharedInstance R8's predicate
  lib/dexpace/conformance/aggregate.rb        Dexpace::Conformance::Aggregate      the one report
  lib/dexpace/conformance/report.rb           MODIFIED: #results, #to_h, .merge, the two sections
  lib/dexpace/conformance/levels.rb           Dexpace::Conformance::Levels          Task 12a, generated
  sig/…                                       THIRTEEN mirrors, one per new public constant
  test/…                                      the gem's own suite: one non-conforming double per suite
  APPENDIX_B.md                               the 61-row coverage map

gems/dexpace-serde-json/
  test/dexpace/serde/json/conformance_test.rb   the CodecSuite driver: one test calling CodecSuite.run
  test/support/serde_seam_assertions.rb         MODIFIED: only the lifted halves leave (SEAM-20/
                                                SERDE-3, SERDE-9); SEAM-21, SERDE-4, SERDE-12 and
                                                SERDE-29 stay, and APPENDIX_B.md's B.3 rows name it
  test/dexpace/serde/json/seam_conformance_test.rb  MODIFIED: 7a's driver drops the two calls whose
                                                methods left and keeps the other three

gems/dexpace-async-thread/
  test/dexpace/async/thread/conformance_test.rb the ExecutorSuite driver, same shape

tasks/gates.rake                              MODIFIED: cause_walk, bounded_map, seam_names,
                                              serde_boundary's PENDING assertion
Rakefile                                      MODIFIED: the three names appended to DEFAULT_GATES,
                                              which is defined here and not in tasks/gates.rake --
                                              a gate outside it is off `task default:`, i.e.
                                              advisory, which NFR-17 forbids
.github/workflows/ci.yml                      MODIFIED: the three new gates placed in the `gates` job
tools/ast_scan.rb                             the shared RubyVM::AbstractSyntaxTree walker
tools/invariant_gates.rb                      the three offence lists, each with its stated gap
tools/requirement_levels.rb                   Task 12a's generator: reads appendix C, writes levels.rb
tools/appendix_b.rb                           the coverage map's generator and its two parsers
test/support/warning_capture.rb                a recorder PREPENDED above phase 0's FatalWarnings
test/gates/…                                  the gate tests
test/fixtures/gates/…                         five mutation fixtures, one deliberately failing
                                              input per gate plus a positive control
```

**Nothing is created outside the trees above.** That is `R6`'s boundary expressed as a file list:
**no `lib/` or `sig/` file outside `gems/dexpace-conformance/`, and no file in `gems/dexpace-core/`
at all.** If an audit finds a defect in one of those, the repair is phase 10's and the file list is
the mechanical reminder.

**Two entries in that list are widenings on the first draft, and each is load-bearing rather than
convenient.** `.github/workflows/ci.yml` is there because phase 0's `ci_workflow_test.rb` is a
**blocking** gate asserting that every entry in `DEFAULT_GATES` appears in some CI job — so a phase
that adds three gates and leaves the workflow alone reddens a phase-0 gate, which is not a boundary
worth keeping. And **each adapter gem's `test/` tree** is there because a suite nobody drives proves
nothing, and **8a set the precedent**: its driver is a file inside the adapter gem, at
`gems/dexpace-transport-net_http/test/dexpace/transport/net_http/conformance_test.rb`, holding one
`conformance(…)` call and nothing else. Phase 9 follows that **placement** for `dexpace-serde-json`
(`CodecSuite`) and `dexpace-async-thread` (`ExecutorSuite`), but each driver calls its suite's
`.run` and asserts on the report, because 8a's `MinitestDriver#conformance` builds a
`TransportCase` for every assertion and widening it would change an interface phase 8 owns. The boundary bounds *where phase 9 may
write*, not *whether it may repair another gem*, which it may not.

---

## The object model phase 9 ships

Each new suite follows 8a's protocol, and one addition to the gem is stated rather than implied.
`Assertion` stays `Data.define(:ids, :name, :body)` with `ids` a frozen array of requirement-ID
strings; `Result` stays `Data.define(:assertion, :status, :detail)` with the five statuses; waivers
stay keyed by requirement ID. 8a fixed `Assertion#body` as `^(untyped) -> void` precisely "because an
assertion's subject is whatever suite it belongs to and phase 9 adds suites for seams that are not
transports" — so each new suite supplies its own `*Case` subject and nothing in the *protocol*
changes.

**What does change: `Runner` is new shared infrastructure inside a gem phase 8 owns, and
`TransportSuite` is deliberately not moved onto it.** Four suites would otherwise carry four copies
of one status loop, which is §11.12's "four reference sync/async drifts" reappearing inside the
port's own suite. The cost of not moving `TransportSuite` is **two status-deciding paths in one
gem** — 8a's, inside `TransportSuite.run`, and `Runner`'s — and the reason is `R6`: phase 8 owns that
file, and a phase that refactors another phase's shipped code while claiming to only report is the
boundary failing quietly. The residue is real: a future change to the five statuses has to be made
twice. Recorded as `P9-10` rather than left as a consequence a reader has to notice.

| Constant | Subject its `.run` takes | Covers |
|---|---|---|
| `Check` | `.that(condition, message, expected:, actual:, ids:)` | The one assertion primitive, in its own file because phase 9's own code is inside the `NFR-3` assertion phase 9 ships |
| `Runner` | `.run(assertions, waive: [], around: nil) { subject }` | The five statuses, decided once. `.one` and `.invoke` are `private_class_method` |
| `InvariantSuite` | `.run(core: ::Dexpace, seam: nil, mutable: [], bounded_map: nil, bounded_map_store: nil, cnonce: nil, redirect_hops: nil, transport: nil, waive: [], around: nil)` — the loaded core, plus the driver's declarations and factories for the objects the suite cannot reach itself | `B.8`; 28 assertions across `XCUT-1`–`XCUT-24` (`XCUT-11`, `XCUT-13`, `XCUT-14` and `XCUT-18` carry two each — corrected in place 2026-09-13 from 27 and three: the plan's Task 7 gained `XCUT-18`'s forged-`Request` dispatch assertion behind a `transport:` factory — the wire-boundary re-validation's portable clause phase 1 named for this phase) |
| `PackagingSuite` | `.run(core: "dexpace-core", adapters: [], resolve:, constants: {}, waive: [], around: nil)` — gem **names**, resolved through `Gem::Specification.find_by_name` | `B.9`; `NFR-1`, `NFR-2`, `NFR-3`, `NFR-10`, `NFR-11`, `NFR-13`, `NFR-14`, `NFR-15` |
| `CodecSuite` | `.run(build:, witness:, source:, waive: [], around: nil)` — a codec factory, plus the driver's witness and source factory, because phase 2's contract is `load(source, witness)` with no witness-less overload | `B.3`'s seam half; `SEAM-20`, `SERDE-3`, `SERDE-9`. **`SEAM-21` is not lifted** — it is the type-token rule, a witness-protocol property, and stays in 7a's suite |
| `ExecutorSuite` | `.run(build:, borrow: nil, functional: nil, events: nil, waive: [], around: nil)` — the executor factory, the borrowing entry point, a **resource-free** implementation for `ASYNC-17`, and an event-recorder **factory** whose recorder is a **sink** — the adapter's `build:` lambda wires it into its own logger, because 8b's `Pool` exposes its shutdown only as `Events::INSTRUMENTATION_SHUTDOWN` through the injected logger and no filed executor has a shutdown counter | `B.7`'s lifecycle half; `SEAM-12`, `SEAM-25`, `ASYNC-15`–`ASYNC-17`, `XCUT-11`, `XCUT-13`, `XCUT-22`; `SEAM-25`'s harness half, which phase 2's postponement left to be written; and, added 2026-09-13 by the plan's Task 11, `ASYNC-3` — an assertion written so it genuinely fails on a worker-thread executor and is waived by ID by the first-party drivers, so the report prints `waived (would fail): ASYNC-3` rather than a green (the unsatisfied MUST, design §10.5). `SEAM-18` and `ASYNC-15`'s clause (c) are **scoped out with a reason** |
| `SharedInstance` | `.audit(object, mutable: [], ids: ["XCUT-11"])` — `mutable:` from the **driver**, never the audited object | `R8`'s structural half |
| `Aggregate` | `.run(Array[Report]) -> Report`, `.render(Report) -> String`, `.by_requirement_id(Array[suite], statuses: Report?)` | The one report; merges results, prints waived and vacuous separately, and builds the coverage map's generated half from each suite's **`.assertions`** rather than from a Report |

**Four things that follow from 8a's constraints and are not free choices.**

`PackagingSuite` needs no `require` at all: RubyGems is loaded before any user code, `Gem::Specification`
is available without one, and `Dir`/`File` are core. So the gem still declares `dexpace-core` and
nothing else, `gates:gemspec_audit` still passes, and phase 0 plan, Task 9's per-gem denylist question — which
bit `8a` over `socket` — does not arise for this phase's files.

`ExecutorSuite` must not name `Dexpace::Async::Thread`. `dexpace-conformance` declares `dexpace-core`
alone, so the executor is a factory the driver supplies, exactly as `TransportSuite` takes a transport
factory. The suite's own test drives a deliberately non-idempotent double.

`Aggregate` is where `Report#to_h` gets its first caller, which is what 8a deferred it for. The
structured form is `NFR-4`-locked surface, so it ships with a `sig/` mirror and lands in the same
change as the surface-manifest regeneration.

Neither new driver-facing constant requires a test framework. `MinitestDriver` and `RSpecDriver` stay
8a's, referenced at call time, and phase 9 adds no `require "minitest"` anywhere in `lib/` —
which is why the `minitest` pin touches this gem only indirectly: it is a finding about the *root
`Gemfile`*, owned by phase 0 plan, Task 2, rather than about `dexpace-conformance`.

---

## Testing strategy

**The instrument is what gets TDD; the audit is what gets run.** Those are two different activities in
one plan and conflating them is the failure mode `R3` names.

**For every suite phase 9 writes**, the test is a **non-conforming double** and the assertion must fail
against it before it passes against a conforming one. One double per suite, written first:

| Suite | The double that must make it fail | The conforming control |
|---|---|---|
| `InvariantSuite` | A `Headers` aliasing the caller's hash (`XCUT-15`); a `close` that is not latched, and one that blocks (`XCUT-13`, both clauses); a map with **no cap at all**, and a check-then-evict map, which fails the drain-to-cap assertion deterministically once its store is pre-filled past the cap (`XCUT-14`); a **three-node** cause cycle and a non-terminating walk (`XCUT-9`); a handler with no injectable `cnonce_source:` (`XCUT-21`); a step holding per-call state, and a latch-plus-mutex step that must **not** be condemned (`XCUT-11`) | The real core |
| `PackagingSuite` | A core with one runtime dependency (`NFR-1`) and an adapter with two (`NFR-2`); one whose loaded `VERSION` **disagrees with its gemspec**, including the `0.1.0`-against-`0.0.0` case a placeholder-only check would pass (`NFR-15`); an uninstalled gem and an unloaded constant, both of which must be `:vacuous` | The six real gems, read from built `.gem` files |
| `CodecSuite` | A codec that closes its sink (`SEAM-20`/`SERDE-3`); one letting `::JSON::ParserError` escape; one raising a Dexpace error **outside** `Dexpace::Serde::Error`; one raising a serde error with **no chained cause**; one that does not raise at all (`SERDE-9`, all its clauses) | `dexpace-serde-json` |
| `ExecutorSuite` | An executor whose `close` runs twice (`XCUT-13`); a holder that closes a borrowed executor (`XCUT-22`); one still accepting work after `close` (`ASYNC-16`); a "functional" implementation whose `close` does work (`ASYNC-17`); one emitting a second shutdown event (`SEAM-25`) | `dexpace-async-thread` |
| `SharedInstance` | An object with an undeclared mutable ivar; one with per-call state on the instance; and a latch-plus-mutex object with its state **declared by the driver**, which must pass | 4a's `ContextStore` |
| `Aggregate` | Two suites whose reports disagree on one ID's status | — |

**For every gate phase 9 adds**, phase 0's discipline applies unchanged: a gate that has never been
seen to fail is a configuration file. **Four gates, five fixtures**, each under
`test/fixtures/gates/` — that is the one spelling for fixtures; `test/gates/` holds the gate *tests* —
outside every gate's own scope. **A sixth fixture there belongs to the scanner rather than to a
gate** and is the last row: it exists so that verified fact 1b is measured rather than asserted, and
Task 1 writes it because Task 1 is where that fact is recorded.

| Gate | Fixture that must make it fail | Positive control |
|---|---|---|
| `gates:cause_walk` | Seven shapes in two files: `.cause`, `&.cause`, `send(:cause)`, `__send__`, `public_send`, `method(:cause)` and `send(variable)` — **six must be caught and the seventh is the stated gap** | A file citing `XCUT-9` in a comment and in a string and calling `Dexpace.each_cause` — which a `grep` would flag and the AST does not |
| `gates:bounded_map` | Six shapes in one file: `{}`, `Hash.new(0)`, `::Hash.new`, `{}.compare_by_identity` — **four must be caught** — plus `@e = build_map` and `@f = seed`, the two stated gaps | `@cap = 1024`, a non-Hash ivar, which must not be reported; and the same file under an allowlist entry carrying its reason. **Plus one integrity test over the adjudication itself**: every `BOUNDED_MAP_ALLOWED` key names a file that exists and every value is a non-empty reason, so a rename cannot silently re-open a hole |
| `gates:seam_names` | Four shapes in one file: `Dexpace::Serde::JSON`, `::Dexpace::Serde::JSON`, bare `Serde::JSON`, and `const_get("Dexpace::Transport::NetHTTP")` | `Dexpace::Registry` and `Dexpace::Serde::Error`, neither of which may be reported |
| `gates:serde_boundary` | A `PENDING` list with one entry | An empty `PENDING` |
| `AstScan.parse` (all three gates) | `warns_unused.rb` — one file whose own `-w` diagnostic (`assigned but unused variable - e`, 8a's filed shape at 8a plan:4858) raises under `FatalWarnings` when parsed. With a bare `parse_file`, the gate test **errors** on all four interpreters; that is the failing state the fixture exists to produce | The same file scanned through `AstScan.parse`, which must report it clean and must not raise — and every other fixture here, none of which warns |

**For the audit tasks**, there is no fixture and no TDD, and saying so is the point: an audit task's
output is a checklist row and, where it fails, a finding routed to its owner. What the plan *can* assert about an audit
task is that its **existence probe** runs and reports, which is one `assert` per named artifact and is
what turns "the design promised `Dexpace::BoundedMap`" into an observation.

**Three verifications that are not fixtures, run against real interpreters by the plan.** (1) The AST
walker on 3.2.11, 3.4.10 and 4.0.6 — **including the `:LIT`/`:SYM` divergence**, which the plan's Task
1 asserts per-interpreter, because verified fact 1 was measured during planning and a fact true in
planning and false at implementation time is what the note mechanism exists to catch. (2) The Minitest
version and `minitest/mock` availability on all three, because what the 4.0 row can run depends on which
`minitest` pin the root `Gemfile` carries — phase 0 plan, Task 2's `~> 5.25` — and the plan must
observe rather than assume it. (3) The
`PackagingSuite` against genuinely **built** `.gem` files rather than source gemspecs, because `P9-2`'s
whole argument is that those can differ.

**Those three were the interpreters installed during planning; 3.3.12 has since been installed, so
all four rows of the supported matrix (3.2 / 3.3 / 3.4 / 4.0 per `CLAUDE.md`) run locally.** There is
no `.ruby-version` file in this repository. Planning measurements were produced on 3.2.11, 3.4.10 and
4.0.6 and say so where they appear; the 2026-09-13 fix round re-ran the plan's fences on all four.

---

## Deviation Ledger

Each row is consolidated into design §10 and audited by `docs/deviations.md`.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P9-1 | Appendix B's `B.1`, `B.2` and `B.5` are dispositioned **by reference** to the owning phase's suite, not re-implemented in `dexpace-conformance` | design §9.3; appendix B | §9.3's argument for the gem is portability across implementations of one seam. Pagination, SSE and the configuration chain have one implementation each; a lifted assertion would be a second copy of a test with one subject, in a package whose purpose is many. `docs/first-release.md` § Post-release triggers (the `B.1`/`B.2`/`B.5` entry) records the condition that changes this |
| P9-2 | `NFR-1`/`NFR-2` are asserted **twice against two subjects**: phase 0's `gates:gemspec_audit` over source gemspecs, and `PackagingSuite` over published `Gem::Specification` metadata | `NFR-1`, `NFR-2`; design §9.2 | `NFR-1`'s conformance clause names "the core artifact's **published** dependency metadata". A source gemspec and a published one can differ, and only the second is what a consumer resolves. The first is the CI shape, the second is the claim's shape |
| P9-3 | Every audit task is an **existence probe plus a property assertion**, and a failed probe routes a finding to its owner rather than improvising a subject | `R3`; the whole `XCUT` table | Phase 9 is planned before any code exists. The alternative — writing audits against whatever arrives — makes the audit unfalsifiable, which is the failure this discipline exists to catch |
| P9-4 | Four repository-wide invariant checks are **Rake gates using `RubyVM::AbstractSyntaxTree`**, not conformance assertions | `XCUT-9`, `XCUT-14`, `SEAM-2`, `SSE-37`; design §9 table | A scan of `gems/*/lib/` is meaningless in a consumer's process. The AST rather than a regex because a regex matches comments, strings and requirement IDs; verified on all three interpreters; the parser itself is warning-free under `-w`, but a **scanned file's** own diagnostics reach `Warning.warn`, which phase 0's test case raises on — so `AstScan.parse` opens a `$VERBOSE = nil` window (verified fact 1b). Addenda A4–A7 |
| P9-5 | `NFR-8` and `NFR-9` are marked **N/A**, and §9.2's retargeted checks are dispositioned under `NFR-1` rather than counted again under `NFR-8` | `NFR-8`, `NFR-9`; §10.19; §12 | `NFR-8` exempts itself by its own text and §12 counts it among the eight vacuous MUSTs. Counting the require-allowlist and clean-bundle runs twice would make the gate set look larger than it is |
| P9-6 | Phase 9 **reports and does not repair**, including for an unmet MUST; the sole exception is a defect inside `dexpace-conformance` that prevents the suite from running | roadmap phase-9 and phase-10 rows | Phase 10's row carries the repair permission, twice. An auditor who repairs cannot report an unrepaired finding without it reading as a choice, and "small enough to just fix" is the judgement that erodes the boundary |
| P9-7 | The appendix-B coverage map's `by reference` rows prove **an ID is claimed and a file exists**, not that the behaviour is tested, and the map says so | `R7`; design §9.3 | Nothing mechanical can check that another gem's test asserts a described behaviour short of re-implementing it. Stating the limit in the map and in the report's preamble is the honest form; a map that implied more would be worse than none |
| P9-8 | **One `Result` per assertion; assertions are keyed by requirement ID, and an appendix-B item is a view over the assertions for its IDs, whose status is the worst among them** | design §9.3's "a failing item"; appendix B | `B.7`'s second item names `ASYNC-3` and `ASYNC-4`, which §9.3 itself requires to end failing and vacuous respectively. One `Result` carries one status, so item-granularity is unrepresentable. The wording matters beyond pedantry: "one assertion per ID" — the first draft's phrasing — **forbids** `XCUT-11`'s two clauses and `XCUT-13`'s two clauses from each having a check, which is exactly what `R8` and the design's own `XCUT-13` row require. Keying by ID while allowing several assertions per ID is what the worst-status mapping actually needs |
| P9-9 | `XCUT-11`'s audit predicate permits two named kinds of mutable state on a shared instance — a `Thread::Mutex` with the state it guards, and `Closeable`'s `@closed` latch — and **the driver declares them, never the audited object** | `XCUT-11`; `cross-cutting-invariants/89eb6533` | A *frozen and no ivars* predicate would condemn every closeable component in the SDK and the exact latch shape the corpus prescribes. Reading the declaration off the subject inverts the requirement in both directions — measured: a conforming latch-plus-mutex object **fails**, because no phase committed to such a method and `R6` forbids adding one, while the identical per-call-state bug **passes** by declaring its own ivar exempt. The driver is `dexpace-core`'s own suite and knows which ivar is which |
| P9-10 | `Runner` is **new shared infrastructure inside a gem phase 8 owns**, and `TransportSuite` is deliberately not moved onto it | design §9.3; the conformance assertion protocol; `R6` | Four suites would otherwise carry four copies of one status loop, which is §11.12's "four reference sync/async drifts" reappearing inside the port's own suite. Not moving `TransportSuite` leaves **two status-deciding paths in one gem**, and that is the price of `R6`: phase 8 owns that file, and a phase that refactors another phase's shipped code while claiming only to report is the boundary failing quietly. The residue is real — a future change to the five statuses must be made twice — and is stated rather than left to be noticed |

### As built, 2026-09-23

The ten rows above stand as decided; `R1`–`R8` were built as written, with `R3`'s vacuity blocker, `R5`'s
`waived (would fail)` rendering and `R8`'s disjunction all shipping in the shapes this document fixed.
This phase was cut from `main` at `582e33a`, which holds every phase through 8. Execution added the rows
below, numbered from **P9-21** as the brief fixes it; `P9-11`–`P9-20` are left free and nothing is
renumbered. The checklist's "Deviations from the plan" is the itemised list against the plan's text; the
rows here are the ones that touch public behaviour, the contract a later phase cites, or a statement this
document makes. `P9-34` and `P9-35` were added in **review round 1**, on 2026-09-24, and `P9-36`
through `P9-39` in **review round 2**, on the same day; each is marked as such in its own row, and
nothing earlier is rewritten except `P9-32`'s count, which was wrong as written and is corrected
twice for the same reason.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P9-21 | `SEAM-25`'s harness half is recorded as a **correction** to a committed record, not a restatement of one | `SEAM-25`; 8b's design | 8b's design said the harness half was 8a's and that 8b would hand it the shape; 8a wrote the protocol, the wire fixture and the transport suite and **no executor suite**. So the harness half was unwritten after phase 8. Phase 9 writes it and says so out loud, which is the discipline phase 4b failed when it corrected its charter while claiming to restate it |
| P9-22 | `CodecSuite`'s two assertions are **re-derived from the requirement text**, and `dexpace-serde-json`'s own files are left byte-identical | `SEAM-20`, `SERDE-3`, `SERDE-9`; plan Task 10 | The plan's lift would have moved `assert_closes_nothing`, whose body is the only evidence `SEAM-21` has in that suite, and `assert_failure_model`, which carries `SERDE-10` and the ENCODE half of `SERDE-9` too. A lift taking the portable halves would have dropped three properties on its way out. The relationship is `TransportSuite`'s to the net_http suite's instead: a portable assertion beside a gem-local one, both alive |
| P9-23 | None of the three first-party drivers uses 8a's `MinitestDriver`; each carries its own six-line generated-test loop | `R6`; 8a's `MinitestDriver` | `MinitestDriver#conformance` builds a `TransportCase` for every assertion, and widening it would change an interface phase 8 owns. The residue — two driver loops in one repository — is the price of `R6` and is stated in each driver's header rather than hidden |
| P9-24 | `test/support/gate_warning_capture.rb` deliberately does **not** require `dexpace_test_case`, and the scanner's warning property is proven by RECORDING rather than by arming the raiser | `NFR-6`; plan Task 1 | The plan said to require it so the two prepends land in order. Measured: `test/gates/` is the one suite whose base is `GateCase`, which does not install `FatalWarnings`, and arming it from a support file armed it for the whole `test:gates` process — where three deliberately-invalid gemspec fixtures and YARD's own load-time warnings had always reached `Warning.warn` harmlessly. Four pre-existing gate tests went red. What the file needs is the recorder, not the raiser |
| P9-25 | Two public-surface leaks were found by reading the regenerated manifest row by row and were **closed rather than accepted** | `NFR-4`; `R6` | `Aggregate#add_rows` was public (an `@api private` tag is not privacy), and `CodecSuite`'s two assertion factories were public where every other suite's are in a `private_constant` group. Both are this phase's own code, so both are fixed: every suite's public surface is now exactly `assertions`, `run` and `PREAMBLE`. `tools/surface.rb` walks `Module#constants(false)` and cannot see a `private_constant` module at all, which is why reading the manifest was the only way to find them |
| P9-26 | `invariant_suite/credentials.rbs` deliberately omits `include ::Random::Formatter`, and says so in the file | `NFR-11`; `gates:rbs_surface` | The `Recorder` double includes `Random::Formatter` so one `#bytes` override records every draw. `tools/rbs_surface.rb`'s `STDLIB_ALLOWED` does not carry `Random`, and widening a gate's allowlist to accommodate a test double is lowering the gate. The signature is incomplete by one line, the reason is in the file, and Steep is green over it |
| P9-27 | The three new gates' `DEXPACE_GATE_ROOT` route was **broken on arrival and is fixed**, with a fixture workspace and four tests | `R4`; the repository's every-gate-has-a-failing-fixture rule | The tasks handed the scanner paths made relative to the gate root, which `AstScan.parse` then opened relative to the process's CWD — the same directory only when the variable is unset. Under a fixture root every open raised `Errno::ENOENT`, so the three gates could never have been shown to REJECT anything. They now scan absolute paths under the root, join both allowlists to the same root, and make the message relative afterwards. A defect in this phase's own code, so `R6`'s report-don't-repair rule does not apply to it |
| P9-28 | `XCUT-3`'s assertion asserts that the waiter was **parked** when the cancel was issued, as a `Check` of its own | `XCUT-3` | Without the barrier the cancel could be issued before the waiter entered `Clock#sleep`, whose own entry check then raises — and a `Clock#sleep` that ignores the token entirely PASSED. Measured by mutation. The barrier is a bounded `Thread.pass` spin on `Thread#status`, never a sleep, and its result is checked rather than assumed, so a run that could not have discriminated reports `:failed` |
| P9-29 | `XCUT-12`'s assertion asserts that **every** racer was parked before the coalesced fetch is released | `XCUT-12` | Without the barrier the first thread finished alone and the other fifteen took the cached-token path without ever racing, so a stamper fetching per caller PASSED. Measured by mutation. Under a conforming stamper one racer parks in `#fetch` and fifteen park on the credential's lock; under a non-conforming one all sixteen park in `#fetch` — both are `"sleep"`, so the barrier is the same for either and decides nothing by itself |
| P9-30 | `tools/serde_boundary.rb`'s `pending` gains `list:`, **and** the task's abort branch gets a `RUBYOPT` prelude fixture | `SSE-37`; `R4` addendum A7 | The `list:` keyword lets a test drive a non-empty list through the FUNCTION. It does not reach the TASK: `PENDING` is a frozen constant and no gate root can make the task see a non-empty one, so a mutation deleting the abort left every test green. The fixture prepends one row onto `.pending` through `RUBYOPT`, which is this repository's deliberately-failing-fixture rule applied to the one gate clause with no other route in |
| P9-31 | `tools/requirement_levels.rb --check` takes an **optional path**, so both exits are proven | `R3`; `NFR-17` | With `TARGET` fixed the gate's own test could only ever assert exit 0, and a `--check` that always exited 0 passed it — measured by mutation. `--check <path>` compares the same render against a file the test writes to a temp dir, so the failing half needs no fixture tree and nothing under `gems/` is touched |
| P9-32 | The mutation set run here is **this phase's own**, re-derived from the design's testing strategy and the plan's per-task "non-conforming double" rule | the brief's minimum set | The reviewer's list was in this run's opening brief and did not survive the session's context compaction. **Forty-four** mutations were re-derived and all forty-four go red; a forty-fifth shape — conditioning `Registry#resolve`'s `return hand_out(resolved)` guard on anything else — turned its `loop do … end` into an unbounded spin, ran for six minutes and was **killed rather than counted**, which is the finding routed to phase 10's inbound list and not a guard. Review round 1 adds **seven** more (rows 46–52) and review round 2 **two** (rows 53–54), for fifty-three red in all (checklist, "Guards run red"). The two round-2 rows are shapes that SURVIVED round 1 — the brief's own minimum list named both — so the honest reading is that the set run at implementation was short by two, not that two more were found. The count exceeds the thirty-five the brief named as a minimum, but the SET is not the reviewer's, and a reviewer re-running the original should expect to find it covered rather than assume it |
| P9-33 | The plan's existence-probe list names `:Redactor` at the top level; the filed name is `Instrumentation::Redactor` | plan Task 16 Step 1; design `R8` row 13 | `Dexpace::Redactor` does not exist and never did — design `R8`'s own row 13 says "the filed name, not `Dexpace::Redactor`". The probe list was corrected at execution; every probe answers true, so no `R3` divergence was filed |
| P9-34 | **Every wait in the four new suites carries a bound**, and ASYNC-3's expired ENTRY wait is `:vacuous` rather than `:failed` | `ASYNC-3`, `SEAM-12`, `XCUT-11`; 8a's `await_closed_connection` | Review round 1. Three waits had none — `Shutdown#check_release`'s `transport.entered.pop` and the two `.each(&:join)` sites — and the first was demonstrated to HANG for ever against an executor that refuses the post (ASYNC-2's saturated queue, or a closed pool): nothing is ever pushed, the poster rescues the refusal, and the `ensure` that frees the gate and closes the pool is never reached. This gem exists to be run by third parties against THEIR executors, and 8a had already fixed the rule for it — `await_closed_connection` always carries a `timeout:`, so an adapter that never releases fails the assertion instead of hanging the run. The entry wait's expiry is `:vacuous` and not `:failed` because with no unit started there is no "blocking task on a worker thread", which is the antecedent `ASYNC-3`'s own sentence opens with; a MUST-level vacuity blocks the report regardless. The two join sites are Failures naming their clause, with the whole thread set sharing one budget so sixteen stuck threads cost one bound and not sixteen |
| P9-35 | `PackagingCase::DEFAULT_RESOLVE` rescues `::Gem::LoadError` **by name**, beside `::StandardError` | `NFR-1`, `NFR-2`, `NFR-10`, `NFR-14`, `NFR-15`; the suite's absent-antecedent contract | Review round 1, found by writing the test round 0 asked for: every case in `packaging_suite_test.rb` supplied its own `resolve:`, so the lambda a real driver gets had never run. RubyGems raises `Gem::MissingSpecError` for a name it cannot resolve and that descends from `Gem::LoadError < LoadError < ScriptError` — it is **not** a `StandardError`, so the shipped `rescue ::StandardError` let it past, and it escaped `Runner`'s own bare rescue too and aborted the whole run where the contract is one `:vacuous` result naming the absent unit. Measured on 4.0.6. A defect in this phase's own gem, so `R6`'s report-don't-repair rule does not reach it — the same standing `P9-27` has |
| P9-36 | Four of this document's own predictions were **overturned by observation**, and each is named here as a prediction that was WRONG | `NFR-7`, `NFR-10`, `NFR-17`, `XCUT-14`; plan Task 15 Step 3 | *A prediction is not an observation.* The disposition table above predicted six ⏳ and three of those predictions are simply wrong on the tree this phase was cut from: `NFR-7`'s was pending phase 0 plan Task 3's reviewed `.rubocop.yml` baseline, which landed — `rubocop` exits 0 on `main` at `582e33a`; `NFR-10`'s was pending 8c plan Task 3's per-gem Ruby floor gate edit, which landed — `VERSIONS` carries `ruby floor:dexpace-transport-async_http 3.3` and `gates:versions` is green; and `NFR-17`'s was pending phase 0 plan Task 2's `minitest ~> 5.25` pin, which landed, so the one finding this design raised against `NFR-17` is closed. The fourth correction is not a mark but a NARRATIVE: the whole `gates:bounded_map` story rested on `async_http`'s client cache being uncapped, and 8c shipped the cap its plan promised. `NFR-4`'s ⏳ is overturned as a mark only and narrowly — the row is ✅ because both gates run, while the `v*` baseline `gates:sig_diff` needs still does not exist — and `NFR-13`'s and `NFR-16`'s predictions HELD. All four corrections were MADE from measurement before Task 15's disposition run, so every mark it recorded is an observation; but only the `gates:bounded_map` one was written down AS a correction at the time, and review round 2 is what names the other three. Plan Task 15 Step 3 asks for the naming in as many words, and it is the naming and not the measurement that tells a later reader which of the two a ✅ is — which matters here because phase 10 reads the checklist first |
| P9-37 | `gates:bounded_map`'s allowlist is **re-adjudicated against as-built paths**, ships at six entries, and the integrity test gains the clause that would have caught the stale one | `XCUT-14`; plan Task 13 | The plan filed four keys. One — `gems/dexpace-core/lib/dexpace/configuration.rb` — silenced nothing, because 5a's two accumulators live in `configuration/builder.rb`; a key that silences nothing passes the plan's own "every key names a live file" test, which is exactly how a stale entry survives an adjudication. The scan reports six sites the gate must not fail on: `bounded_map.rb`, `instrumentation/event.rb` and `conformance/recording_span.rb` as filed, plus `configuration/builder.rb`, `auth/challenges.rb` (one parse's accumulator inside a `private_constant Parser`, reset at every `open_challenge` and dropped with the parse — `event.rb`'s lifetime argument) and `async_http/clients.rb` (`@by_key`, drained inside the insert's own `synchronize`). The rule is NOT narrowed and the keyed-read narrowing stays rejected: six is far short of the dozen open question 2 names as the point where the gate would be telling us the invariant is not held. The integrity test now asserts each key names a live file AND that the scan still reports a Hash ivar there |
| P9-38 | `InvariantSuite::Models::Borrowed` carries a **second, independent teardown route**, so `XCUT-22`'s "still usable" `Check` can fail | `XCUT-22` | Review round 2. `usable?` was `!@closed`, the exact negation of the `closed?` the FIRST `Check` already asserts, so no subject the suite can build separated the two: replacing the second `Check`'s condition with a literal `true` left the whole gem's suite green, while the code comment and the checklist row both claimed it caught a component that tore the resource down another way. `Borrowed#finish` is that other way — `Net::HTTP` spells its teardown exactly that, a pooled client spells it "retire", and an adapter tearing down a caller's SOCKET rather than the caller's client leaves `closed?` false — and `usable?` now reads both flags. `TearingSeam` drives it. The `ExecutorSuite` twin never had the problem: it posts work to the underlying executor after the holder's close, which is an observation of its own |
| P9-39 | `ExecutorCase#shutdowns`' event-NAME match is given a double that logs something **besides** its shutdown | `SEAM-25`, `XCUT-13`, `XCUT-22` | Review round 2. The count matches the payload's `Keys::EVENT` entry, but every double in `executor_suite_test.rb` emitted the shutdown payload and nothing else, so nothing separated "count the shutdown events" from "count the sink's writes" — and replacing the match with a bare `entries.count` left the file, the pool driver and the whole `rake test:gems` green, with four assertions reading that count. An executor that logged one unrelated line and emitted no shutdown would have passed `SEAM-25`; a conforming one that logged anything at all would have failed `XCUT-22`. `ChattyPool` emits one other event payload and one bare String message at construction, which nothing in the SPI forbids and which a real adapter's logger carries plenty of. No code changed — the code was right and only the guard was missing |

---

## Work phase 9 postponed, and who owns it now

Phase 9 postpones five things, each with a named owner, and inherits three. Every entry is
self-contained — what was postponed, why, the condition that would take it up, and where the obligation
lives now — because the reasoning survives here and nowhere else. (The heading avoids the literal words
the housekeeping probe's `registers` check reserves for an aggregate register.)

| Subject | What is postponed, and why | Condition, and where it lives now |
|---|---|---|
| **A regeneration guard over the require-allowlist itself** — the piece of `NFR-9`'s content the §10.19 retarget does not cover (`NFR-8`, `NFR-9`, `NFR-1`, `NFR-10`, `SEAM-1`) | Design §10.19 retargets `NFR-8`/`NFR-9` at the require-allowlist audit and the clean-bundle isolation run, and both check that **today's** allowlist holds; neither checks that the allowlist is still the right list. `NFR-9`'s content is a guard over shipped **keep-configuration** — "drop a shipped keep-rule … → the guard fails the ordinary build" — and the Ruby analogue is an interpreter where a name the allowlist permits has become a bundled gem. That is not hypothetical: `package-and-dependency-layout/70fbcaee` records the allowlist's basis moving once already, from the six names the corpus held to the 23 a real 4.0.6 interpreter reports, with `tsort` leaving the default set at 4.1 and `Gem::BUNDLED_GEMS::SINCE` undefined on the 3.2 floor. Phase 0 filtered against the whole `SINCE` table rather than the supported range, which is the right shape and is still a snapshot | Names the **event**, in the shape the `IO-38` and `BODY-36` triggers were given: **a new Ruby minor version entering the CI matrix**. No phase in v1 adds one — the matrix is fixed at 3.2 / 3.3 / 3.4 / 4.0. The work when it fires is one gate, not new code: re-derive the name list on the new interpreter and diff it against the committed allowlist. **Owner: `docs/first-release.md` § Post-release triggers, the require-allowlist entry** |
| **`PackagingSuite`'s `NFR-12` and `NFR-16` assertions against a released artifact** (`NFR-12`, `NFR-15`, `NFR-16`, `NFR-4`). `NFR-15`'s is **not** postponed: the plan's Task 9 ships it against a locally built `.gem`, comparing the loaded `VERSION` to the resolved gemspec, which is what the requirement names. The two postponed ones are **not shipped at all** — no phase-9 task writes an `NFR-12` or `NFR-16` assertion, and both are written at the pick-up. (As first recorded on 2026-09-12 this entry named all three and said phase 9 shipped them as `Vacuous` placeholders; no task does, so it was narrowed on 2026-09-13 rather than left to mislead whoever picks it up) | `NFR-16`'s signing is "enforced on the release/CI path" and there is no release path (`docs/first-release.md`'s "Release path: not yet defined"); `NFR-12`'s cross-toolchain half is explicitly out of scope by phase 0's `P0-7`, which reads `NFR-12` as byte-identity for one gem built twice on one interpreter | The first `v*` tag and the first `gem push`, alongside the signed-publication work phase 0 postponed to the release, whose own condition is "the RubyGems-ownership and trusted-publishing blockers in `docs/first-release.md` close". Release-gated; no phase owns it; the fence executor for `.claude/skills/housekeeping/` is the third item in the same family. **Owner: `docs/first-release.md` § Release path, the `NFR-12`/`NFR-16` entry** |
| **Lifting `B.1`, `B.2` and `B.5`'s assertions into `dexpace-conformance`** — the pagination (`B.1`, 10 items), SSE (`B.2`, 6 items) and configuration (`B.5`, 6 items) checklist items, which `P9-1` declines today and dispositions **by reference** (`PAGE-8`, `SSE-37`, `CFG-1`, `NFR-2`) | §9.3's argument for shipping `dexpace-conformance` as a gem is portability across *implementations of one seam*: "the *same* assertions could not run unchanged against `dexpace-transport-async_http` or a future `httpx` adapter — which is the whole point." Pagination, SSE and the configuration chain each have exactly one implementation, and `PAGE-8` makes the pagination engine stateless and shareable rather than pluggable. A lifted assertion over a single subject is not more true for having moved gems; it is a test with one subject living in a package whose purpose is many, and it costs a second file to keep in step. What phase 9 keeps from the lift is the part that carries information — the 61-row map (Task 14's `APPENDIX_B.md`), which says for every item where its evidence is | Names the **event**: a **second implementation** of the pagination engine, the SSE reader or the configuration chain exists. None is planned in v1 and none is on the post-v1 gem list — those are transports, async runtimes, a codec and an instrumentation adapter, not a second paginator — so this is a genuinely open-ended condition, recorded so a later reader does not read `P9-1` as an oversight. **Owner: `docs/first-release.md` § Post-release triggers, the `B.1`/`B.2`/`B.5` entry; Task 14's `APPENDIX_B.md` (`P9-1`) stands** |
| **`XCUT-12`'s single-flight assertion under a fiber scheduler rather than threads** (`XCUT-12`, `XCUT-11`, `AUTH-35`, `AUTH-36`, `ASYNC-9`). Phase 9 ships the **thread** form in `InvariantSuite` (Tasks 7–8) | `Thread::Mutex` ownership in Ruby is **per-fiber, not per-thread, and non-reentrant** (`CLAUDE.md`'s constraints that will bite; design §3.1/§3.7/§7.2), so a lock held across a suspension point deadlocks two fibers of one thread and a thread-only race cannot see it. `8b`'s design handed forward exactly this shape for `XCUT-11` — "the **two-fibers-on-one-thread** test" — and phase 9 adopts it there. For `XCUT-12` it needs a *credential* path running under a reactor, which means `dexpace-transport-async_http` driving `6c`'s bearer or digest cache: a composition no first-party suite assembles today, because `dexpace-conformance` declares `dexpace-core` and nothing else and so cannot open a reactor itself. The suite contract's clause 9 `around:` wrapper is the route — an async driver passes `->(&blk) { Sync { blk.call } }` — and supplying such a driver for a credential assertion is a piece of work, not a line | **Phase 10**, if its audit of `XCUT-12` finds the thread-only form insufficient — a judgement phase 10 is entitled to make and phase 9 is not, since phase 9 reports and phase 10 repairs (`P9-6`). Failing that, the condition is the post-v1 reactor-native `dexpace-async-async`, the first artifact that would make a second fiber-scheduler subject available. **Owner: phase 10's inbound list in the roadmap's 2026-09-13 status note; fallback `docs/first-release.md` § Post-release triggers, the `XCUT-12` entry** |
| **The MUST-level vacuity report blocker** (`NFR-17`) — the mechanism behind this design's rule that an un-waived `:vacuous` result on a MUST-level ID is a **phase-9 report blocker** and earns a `docs/first-release.md` line (`R3`; plan Task 15, step 4) | As first planned the rule was prose and nothing enforced it: `Report#passed?` is true when results are vacuous (8a's own report test asserts exactly that), and nothing in `dexpace-conformance` knows whether an ID is MUST or SHOULD, so no run could list MUST-level vacuities separately. Building it needs a requirement-level map derived from appendix C plus an aggregate section over it — machinery the 2026-09-13 fix round was not scoped to add, so it was postponed rather than dropped. **This is a manager decision and must not be lost**: `R3`'s absent-artifact `:vacuous` rule is safe only because this blocker exists, and without it an unbuilt MUST reads as a green run | Phase 9 execution, **before Task 15's disposition run** — that run's verdicts are not trustworthy without it. **Owner: the plan's Task 12a** (inserted 2026-09-13: `Levels::OF` derived from appendix C, `Report#blocking_vacuities`, and `accepted_vacuous:` with mandatory citations); Task 17 Step 3 marks it landed |

### What earlier phases postponed to phase 9, and what phase 9 decided

The roadmap's execution step 1 requires every phase to read everything earlier phases postponed and
disposition each item, not to scan for its own name. **All of it was read** on 2026-09-12. Two items were
already built before this phase (the version-skew guard's runtime half, phase 2; the body member's type
and `HTTP-46`, phase 3b) and one was already declined (moving core's fakes into `dexpace-conformance`,
phase 8a); phase 9 does not revisit a retired item. Every live item appears exactly once below. (The
first draft of this section enumerated the items wrongly — one counted twice, and `SEAM-25`'s harness
and the `IO-38` trigger omitted — which is how the harness reassignment came to be made silently.)

**Three items are taken up.**

- **The conformance assertion protocol** — phase 0 postponed it to "phase 8, which owns this gem's
  gemspec, its version and its first release; **phase 9 adds the remaining suites**." Phase 8a met the
  first half and wrote the protocol (its Tasks 4–8 and 20); phase 9 meets the second and adds `Check`,
  `Runner`, `SharedInstance`, `InvariantSuite`, `PackagingSuite`, `CodecSuite`, `ExecutorSuite` and
  `Aggregate`, plus `Report#to_h` (Tasks 2–12a).
- **The wire-boundary re-validation** — phase 1 postponed it to "phase 8 …; **phase 9's conformance suite
  is where the assertion that it happened belongs**." Phase 8 took the first clause (8a's Task 16, 8c's
  Task 9); phase 9 takes the second, as `InvariantSuite`'s `XCUT-18` assertion driven through a forged
  `Dexpace::Request` (Task 7).
- **`SEAM-25`'s lifecycle event, the harness half** — and **this one is a CORRECTION to a committed
  record, stated as a correction.** Phase 2 postponed the event; 8b's design said "The *harness* half of
  the condition — the assertion living in `dexpace-conformance` — is **`8a`'s**, and `8b` hands it the
  shape rather than writing it." 8a wrote the protocol, the `WireServer` fixture and the transport suite,
  and wrote **no executor suite**; 8b supplied the shape as promised and emits the event (its Tasks 6 and
  10). So the harness half is unwritten after phase 8 and phase 9 writes it as `ExecutorSuite` (Task 11),
  which means the earlier record is wrong about *which phase delivers it*. Phase 9 records the work with
  that correction named rather than presenting itself as meeting the condition as written — which is the
  discipline phase 4b failed when it corrected its charter while claiming to restate it.

**None is declined by phase 9.** The one item that invites it is **the Steep target over a `test/` tree**
(phase 0's), conditioned on "a gem's test support becomes production-quality code worth checking — phase
8's conformance helpers at the earliest". Phase 9 adds eight constants and a report, and every one goes in
**`lib/`** for 8a's reason (§9.3's argument is that a third-party author *runs* them), where phase 0
already gave that tree its own Steep target. Nothing phase 9 writes under `test/` is production-quality
code worth a seventh target. **The condition is not met, so the item is left where it is** —
`docs/first-release.md` § Post-release triggers, the Steep-over-`test/` entry — and this phase inherits
8a's reasoning rather than re-deriving it.

**The remaining items, each read and left untouched, grouped by why phase 9 cannot meet the condition.**

| Items | Why phase 9 does not meet the condition, and where each lives |
|---|---|
| `SEAM-24`'s cancellation bridge; `PIPE-36`; `RECOV-31`, `RETRY-29`, `RETRY-38`, `RETRY-43`; `REDIR-27`; `SSE-41`; `OBS-32`, `OBS-37`; presence-gated auto-activation | SHOULDs and MAYs declined for v1 — `docs/first-release.md` § What v1 ships without › SHOULD- and MAY-level requirements declined for v1. Phase 9 ships no domain code in any gem but the conformance one |
| `HTTP-22`, `HTTP-48`–`HTTP-50` | The standing decision line under `docs/first-release.md` § Blockers before first publish; the reopening event is the first consumer that constructs a conditional request, and phase 9 constructs none |
| `BODY-12` clause 2, `BODY-36` | Clause 2 is declined by phase 8a (its design's *Work phase 8a postponed*); `BODY-36`'s condition is core's dependency budget changing, which phase 9 does not do — `docs/first-release.md` § What v1 ships without, the `BODY-36`/`BODY-12` entry |
| `TRANSPORT-28`'s zero-copy clause, `TRANSPORT-30` | An adapter **beyond** the two MVP transports; phase 9 ships none — `docs/first-release.md` § What v1 ships without |
| The seven post-v1 gems | Out of the MVP's scope by construction — `docs/first-release.md` § What v1 ships without › Post-v1 gems; design §2.2 is the authority |
| `ASYNC-3` and `PIPE-33`'s interrupt clause — the unsatisfied MUSTs | "If an interruptible transport path is ever adopted" — §8.3 forbids one and phase 9 adopts nothing, so the condition is **not met** and phase 9 declines nothing. What phase 9 adds is the *disposition in the report*: `ASYNC-3` printed as `waived (would fail)` citing `docs/first-release.md` § What v1 ships without › Unsatisfied MUSTs and design §10.5, which `R5` settles; phase 10 audits the §10.5 ledger |
| The fence executor for `.claude/skills/housekeeping/`; signed publication and `NFR-12`'s release half | Release-gated — `docs/first-release.md` § Release path; phase 9 publishes nothing |
| The suppressed-exception trail (phase 4b, Task 1); `close_quietly`'s two routes (4b Task 2, 5b Task 14); the pivot's `deadline:` (5a Task 8); `Hooks.notify`'s dropped failures (4b Task 2); the body-logging caps (5a Task 13, 5b Tasks 14–15); the recovery-stack retry engine (6a Tasks 3, 4, 5, 7, 11); the context-store cap (5a Task 13); the no-op span and tracer protocols (5c Tasks 3–5); `ProtocolError#retryable?` (6a Task 6); `Pipeline.standard` (6b Task 13a); `CFG-35`'s throwable half (6a Task 3) | Built by the phase whose task is named — behavioural work phase 9 does not do |
| `IO-38` on a Ruby without a GVL | Names the **event** "a non-CRuby row is added to the CI matrix"; phase 9 adds no matrix row — `docs/first-release.md` § Post-release triggers |
| `OBS-19`'s header-drop policy | Phase 8's target, landed by 8c (Tasks 7, 9 and 15, `DropPolicy`) |
| `OBS-29`'s operation-lifecycle triple and transport-milestone group | The route is unreachable as stated — phase 10's inbound list carries it as the transport-reachable `HTTPTracer` — and phase 9 opens none: the emitter needs a `RequestOptions` widening, which is core surface and outside `R6`'s file list. Both residuals, `OBS-29`'s operation-lifecycle triple and the transport-reachable `HTTPTracer`, are on phase 10's inbound list |

## Findings, and who owns them now

**Five findings**, all measured rather than inferred, plus three more from an independent
re-verification review of this design's plan — a 66-mutation battery against the assertions and gates
that found the first draft green over defects it named. **None of them is registered.** Each is
**routed to its owner** below, and the owner line under each finding is where the work now lives; this
section stays as phase 9's own dated record of what it measured, which is the half a pointer cannot
carry.

**Minitest is 6.0.0 on Ruby 4.0.6 and ships no `minitest/mock`, so `Object#stub` and
`Minitest::Mock` do not exist on the top row of the CI matrix.** Measured on all three interpreters:
5.25.1 on 3.2.11, 5.25.4 on 3.4.10, 6.0.0 on 4.0.6; `require "minitest/mock"` raises `LoadError` on
4.0.6 and the gem's `lib/` listing has no such file. Every assertion name in use survives. Two
consequences are concrete rather than theoretical: phase 8a's plan uses
`Dexpace::Conformance::TransportSuite.stub(:assertions, …)` in two fences, which would `NoMethodError`
there; and two corpus rules — `testing/e27df4c7` ("Reserve true test doubles … `Minitest::Mock` …")
and `testing/70473c9d` (`Time.stub :now, fixed_time`) — name APIs absent on a supported Ruby. The
resolution belongs to the root `Gemfile` and to no test file: `minitest` must be pinned, and **which
pin** is the question. Pinning `~> 5.25` keeps `stub` everywhere and means the 4.0 row does not
exercise the Minitest its interpreter ships; leaving it unpinned makes the 4.0 row a different
framework major from the other three. A suite that cannot load makes the 4.0 row **red**, not
advisory, so this is not an `NFR-17` gap; its home is `docs/first-release.md`'s range blocker — "the
`dexpace-conformance` suite passing across the full supported Ruby range, 3.2 through 4.0" — which is
false on that row as phase 8a's fences are written. Cites `NFR-6`, `NFR-7`, `NFR-17`, `NFR-2`; the
conformance assertion protocol (8a's Tasks 4–8 and 20).
**Owner: phase 0 plan, Task 2** — the root `Gemfile` pins `minitest` to `~> 5.25`, a **development**
dependency, so the zero-runtime-dependency rule is untouched, and every matrix row including Ruby 4.0
then carries `minitest/mock` and the same framework major. 8a's two `Object#stub` fences therefore
stand. `docs/first-release.md` § Post-release triggers carries the lift: Minitest 6, once no fence
requires `minitest/mock`. The same Task 2 owns the neighbouring fact that Minitest is a **bundled**
gem and not a default one, so the `Gemfile` must name it at all.

**`NFR-13`'s SPDX gate is a RuboCop cop, so it cannot reach `sig/**/*.rbs`, which ships
inside every gem.** `Dexpace/SpdxHeader` is a custom RuboCop cop over Ruby source; `.rbs` is not Ruby
and no cop parses it. `NFR-13`'s conformance clause is "scan **all source files** for the required
header", and `CLAUDE.md` states that `sig/` "mirrors `lib/` one file per file and **ships inside each
gem**" — so the signatures are shipped source with no header and no gate. Phase 0's own `.rbs` fences
carry none. `.rbs` supports `#` comments, so the header is expressible; what is missing is a check.
What would resolve it: a small Rake gate over `sig/**/*.rbs` alongside the cop, or a deliberate
decision that `NFR-13` covers `lib/` only, stated where a reader will find it. Nothing is broken today
because nothing is implemented. Cites `NFR-13`, `NFR-3`, `NFR-17`.
**Owner: phase 10's inbound list in the roadmap** — SPDX coverage for `sig/**/*.rbs`. Phase 9 reports
and phase 10 repairs (`P9-6`): Task 15 dispositions `NFR-13` ⏳ with the gap named and
`PackagingSuite` asserts the header's **presence** over every shipped `sig/**/*.rbs`, so it reports
`:failed` on the first-party tree today and passes the day phase 10 fixes it — which is the direction
a gate should move under its own repair. An unconditional `:vacuous` was the first draft's shape and
checked nothing for anyone, including the porter this assertion is portable for.
`docs/knowledge/notes/tooling-and-quality-gates.md` carries the same finding against
`tooling-and-quality-gates/3085561e`.

**§9.3 fixes the requirement ID as the WAIVER's unit and leaves the REPORT's unit
unstated, and an appendix-B item cannot be it.** §9.3 already reads "suppressed in the port's own
build through a named waiver listing **the requirement ID**", so the waiver's unit is settled and
this finding does not claim otherwise. What is unstated is the unit the *report* prints a status for.
The sentence around it — "a failing **item** … is reported as a failure by the suite" — reads as
though the item were that unit, and it cannot be: `B.7`'s second item names `ASYNC-3` and `ASYNC-4`,
which §9.3 itself requires to end **failing** and **vacuous** respectively, and one `Result` carries
one status. `P9-8` resolves it for this port — one `Result` per assertion, assertions keyed by ID, an
item a view over them with the worst status winning — but a porter reading §9.3 alone will build the
wrong granularity, and the 61-row map is the only place the real mapping is written down. What would
resolve it: one clause naming the requirement ID as the report's unit too, folded in the next time §9
is deliberately amended. Cites `NFR-17`, `ASYNC-3`, `ASYNC-4`; the unsatisfied-MUST entry in
`docs/first-release.md` § What v1 ships without and the conformance assertion protocol.
**Owner: phase 10's inbound list in the roadmap** — §9.3's report unit, with an interim entry under
`docs/deviations.md` § Deviations found outside a phase. §9 is frozen, so the clause is not written
here; what phase 10 carries is the sentence, what is wrong with it, and `P9-8` as the correct
statement.

**A Symbol literal is a `:LIT` AST node on Ruby 3.2 and a `:SYM` node on 3.4 and 4.0, so a
source scan naming one is blind on the other rows.** Measured on 2026-09-12, parsing
`e.send(:cause)` on all three installed interpreters: the argument node is **`:LIT` on 3.2.11** and
**`:SYM` on 3.4.10 and 4.0.6**. Every other AST fact this phase depends on is identical across the
three — `:CALL`, `:QCALL`, `:VCALL`, `:IASGN`, `:HASH`, `:CONST`, `:COLON2`, `:COLON3`, `:WHILE`,
`:STR` — so this is the one node type that moves, and it moves at the boundary a repository whose
development happens on the newest Ruby is least likely to notice. The concrete instance is
`gates:cause_walk`, which reads that node to catch the four reflective sends: written against `:LIT`
alone it caught 6 of 7 shapes on 3.2.11 and **2 of 7** on the newer rows, and written against `:SYM`
alone it would invert that — either way the gate is strictest on one matrix row and blind on the
others, and `gates:*` runs in phase 0's single-interpreter `gates` job. `AstScan::SYMBOL_TYPES` names
both and the plan's Task 1 asserts the per-interpreter outcome, so this is not a defect in what phase
9 ships; it is the fact that made the first draft wrong, written down so the next source scan in this
repository does not rediscover it. Cites `XCUT-9`, `XCUT-14`, `SEAM-2`, `NFR-10`, `NFR-17`.
**Owner: `docs/knowledge/notes/cross-cutting-invariants.md`** — the AST-gates entry, item 3, which
names both node types and is where the next source scan in this repository will meet the fact. There
is no repair to schedule: what phase 9 ships already names both.

**The appendix-B coverage map's checks establish that a by-reference row is well-formed,
not that the behaviour it points at is tested.** *(Corrected 2026-09-13: the first draft dropped two
checks on numbers that are wrong.)* Measured against the real appendix B with the 19-prefix scanner:
the 61 items name **276 distinct requirement IDs, no ID repeated across items, at most 12 in one
item** (`B.2`'s item 11), 59 of 61 name ten or fewer, and **`B.5`'s six items name 5, 3, 8, 7, 7 and
8** — not "around twenty each", which was the stated reason for dropping the header check. So the
third check is not "every row names at least one ID": it is **per-row ID-set equality** against the
set parsed from that item's own text, which the ID column already claims to be. That is decidable, it
is strictly stronger, and it makes the distinct-ID coverage check hold **by construction**. Three
decidable checks survive — 61 rows, the per-section counts matching the specification, and per-row ID
equality plus an evidence path that exists — with the ID scanner restricted to the nineteen prefixes
because a bare `[A-Z]+-\d+` matches `ISO-8601`, which appears in `B.3`'s real text. What stays
unestablished is the ten-line-header check on the *referenced* file, whose header lives in a gem this
phase does not own — so a by-reference row proves an ID is claimed and a file exists, never that the
behaviour is tested (`P9-7`, unchanged), and a reader of a green run is entitled to know it.
Cites `NFR-17`; the conformance assertion protocol and the `B.1`/`B.2`/`B.5` trigger in
`docs/first-release.md` § Post-release triggers.
**Owner: phase 9 plan, Task 14** — the `APPENDIX_B.md` map preamble states, in the map's own voice,
what the three checks establish and what they leave unproven, and names the closing condition:
`docs/first-release.md` § Post-release triggers' `B.1`/`B.2`/`B.5` entry, whose event is a second
implementation. `Aggregate::PREAMBLE` (Task 12) says the same thing about a green suite run.

**Three further findings came out of the 2026-09-13 re-verification review of this design's plan**,
and each is routed into that plan rather than restated here.

- **`XCUT-9`'s residue** — a collect-then-yield walk hangs the suite (a bound would need an interrupt,
  which §8.3 bans), and a depth cap exactly equal to the cycle length passes, because a black-box test
  over one finite input cannot tell a counter from a visited set. **Owner: phase 9 plan, Task 6**,
  which decides how the suite reports a walk it cannot bound and whether several cycle lengths are
  driven, with Task 13's `gates:cause_walk` as the second line and the residue stated on the `XCUT-9`
  checklist row.
- **Phase 9's own suites break two rules the phase ships**: `module_function` makes every assertion
  factory public with no `sig/` mirror — 15 in `InvariantSuite`, 6 in `ExecutorSuite`, 4 in
  `PackagingSuite`, 2 in `CodecSuite` — and `CodecCase::CountingSink` is a second public class in one
  file, outside `module-organization/1828a984`'s private-struct exception, with
  `ExecutorCase::EventRecorder` the same shape. **Owner: phase 9 plan, Tasks 6–11** — the
  factory-visibility amendment in Task 6 binds all six tasks, and Tasks 10 and 11 carry the
  `private_constant` fix for their own case classes.
- **The four invariant gates' remaining statically decidable misses**, measured identically on 3.2.11,
  3.3.12, 3.4.10 and 4.0.6 and tabulated per gate. **Owner: phase 9 plan, Task 13**, which widens each
  gate for its misses or records them as accepted inside that gate's own stated gap, and states the
  result on the `XCUT-9`, `XCUT-14` and `SEAM-2` rows in Task 16.

The MUST-level vacuity blocker is the plan's Task 12a; its entry under *Work phase 9 postponed, and
who owns it now* carries the reasoning.

**One entry for `docs/deviations.md`'s "Deviations found outside a phase" holding area.** 7c handed
forward that **`PAGE-15`'s wrapping clause (`P7-1`) is not recorded in §12's `PAGE` row**, where
`PAGE-35`'s vacuity is. That is a §12 completeness gap about a deviation with no owning phase left to
record it, which is exactly what the holding area is for, and phase 10 folds it in.

**`docs/first-release.md`** gains no new blocker from this design. Its existing conformance lines —
the suite passing across 3.2 through 4.0, and the requirement that a green run's omissions be written
down before publication — are the two phase 9 discharges, and the `minitest` pin phase 0 plan, Task 2
now carries is what decides whether the first of them holds on the 4.0 row.

---

## The knowledge notes phase 9 files

Three notes in three files — **four entries**, because the new file carries two — written **before
the plan**, because a resolution recorded only in a design document is re-litigated by whoever reads
the corpus next. (Restated 2026-09-13 to name the unit: the plan's Task 17 Step 4 files these three
and no others, and the entry count is what the corpus query returns.)

- `docs/knowledge/notes/testing.md`, `## Superseded`, key `testing/e27df4c7` and `testing/70473c9d` —
  Minitest 6.0.0 on Ruby 4.0.6 ships no `minitest/mock`, so `Minitest::Mock` and `Object#stub` are
  unavailable on the top row of the supported range. Measured on 3.2.11, 3.4.10 and 4.0.6. This is
  `## Superseded` and not `## Conflicts` because it is not two documents disagreeing: it is one fact
  about a real interpreter, and following the harvested rule would write a test that cannot run.
- `docs/knowledge/notes/tooling-and-quality-gates.md`, `## Superseded`, key
  `tooling-and-quality-gates/3085561e` — the SPDX header "checked by a custom RuboCop cop" cannot
  reach `sig/**/*.rbs`, which ships inside every gem. The rule's *purpose* is adopted; its stated
  mechanism is incomplete for this repository's shipped surface.
- `docs/knowledge/notes/cross-cutting-invariants.md` — a new file — `## Reference`, **two entries in
  it**: the `XCUT-11` audit predicate `R8` fixes, and, as its own entry, the fact that the
  repository-wide invariant scans are Rake gates over `RubyVM::AbstractSyntaxTree`, verified present
  on 3.2.11, 3.4.10 and 4.0.6 — the parser warning-free, the scanned file's own diagnostics not,
  which is what `AstScan.parse` exists for — where `prism` is absent on the floor. `## Reference` rather than `## Superseded` because **nothing
  harvested is false**: `cross-cutting-invariants/89eb6533`'s latch rule stands unchanged, and what
  the note adds is the audit consequence the rule implies and does not state. The note says so in as
  many words, because backticking a key is what makes the CLI print `[overridden by notes/…]` beside
  that rule in every query result — and a correct rule should not read as overridden.

---

## Open questions for phase 9's own plan

Four, each with the answer this design expects and the reason it is the plan's to confirm rather than
this document's to fix. (Two questions from the first draft are **answered** and are gone from this
list: the appendix-B map's checks are settled by the plan's Task 14 and the preamble it writes, and `Report#to_h` is settled as stable API
with a `sig/` mirror, since 8a deferred it for phase 9's caller and `NFR-4`'s lock applies from the
first release.)

1. **Which `minitest` pin the root `Gemfile` carries** — phase 0 plan, Task 2 now carries it. Expected: pin `~> 5.25` for v1 and
   record the 4.0-row divergence, because a framework major changing under the suite mid-roadmap is a
   larger risk than not exercising the interpreter's own bundled copy. The plan observes the real
   `Gemfile` before deciding, and **the decision may not be phase 9's at all** — the root `Gemfile` is
   phase 0's artifact and `R6` makes the repair phase 10's.
2. **Whether `gates:bounded_map`'s allowlist can be kept short enough to be read.** **Answered
   2026-09-13, in the plan: yes — four entries.** The gate was run as filed over every Ruby fence in
   phases 0–8 naming a `lib/` path (222 fences, 184 distinct `gems/*/lib/**/*.rb` paths, 2 unparseable
   and neither holding a `Hash` ivar) and reported **6 offences in 5 files**, identically on 3.2.11,
   3.3.12, 3.4.10 and 4.0.6. Five are false positives and are allowlisted with their reason —
   `BoundedMap`'s own store, `Configuration::Builder`'s two accumulators, one log `Event`'s field bag
   and one `RecordingSpan` double's record — and what they share is `XCUT-14`'s own last clause: their
   primary cleanup mechanism is the owner being dropped after one operation, so a cap could never be
   the backstop. The sixth is a true positive and stays red — `Clients#@by_origin`'s missing cap, on phase 10's inbound list. The gate's decidable half is
   still narrow — 4 of 6 measured shapes, a Hash from a method return or a parameter acknowledged as a
   blind spot, and now a third: a Hash held inside a value object rather than on the ivar. Every entry
   carries a reason, as phase 0's require allowlist does; if the list grows past a dozen entries the
   gate is telling us the invariant is not actually held and that is a finding, not a maintenance
   chore.
3. **Whether `Dexpace::Async::Thread` exposes a resource-free implementation for `ASYNC-17`.**
   Expected: unclear, and the plan does not guess. If it does not, the driver passes
   `functional: nil` and `ASYNC-17` reports `:vacuous` with its reason — **phase 9 does not invent
   one inside the adapter**, which `R6` forbids.
4. **Whether the eleven shape-specified `XCUT` assertions and five `NFR` ones survive contact with
   the real artifacts.** Expected: mostly, and the honest prior is poor — **five of five assertions
   written in full in this phase's first draft contained a measured defect**, so a shaped assertion
   inherits no presumption of correctness. The plan writes each one under TDD against a
   deliberately non-conforming double, exactly as the fully-written ones were, and the phase's
   checklist records which were measured and which were reasoned.
