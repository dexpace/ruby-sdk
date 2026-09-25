# Phase 10 — Deviation Reconciliation and Release Readiness

**Status:** Draft, approved for planning.

## Purpose

Phase 9 asked whether what nine phases built is what the specification asked for. Phase 10 asks a
narrower and harder question: **is what the design documents *say* the port did what the port
actually did?** — and then repairs the difference. It is the only phase in the roadmap whose scope is
an audit and whose row grants it permission to ship code, and the roadmap grants that twice over:
"every gem (audit-led; **ships code where the audit finds a defect**)", and, in the ordering
rationale, "phase 10's method, re-deriving every ledger claim from as-built source, is why it **may
ship code** even though its scope is an audit".

Three things make that concrete.

**Design §10's nineteen entries have never been checked against code.** `docs/deviations.md` is the
as-built audit of that ledger and every one of its nineteen rows reads `design only — not yet built`.
Phase 10 is the phase that flips them, and the method is fixed by the roadmap: **re-derive every
claim from as-built source, never from another document.** A row that moves because a design document
said so is a row that has not been audited.

**Twenty-four bullets sit on phase 10's inbound list**, written into the roadmap on 2026-09-13 because
phase 10 had no design to carry them. Fourteen came from the retired open-items register, three
contributed a half no writable material could take, and the rest came from phase 9's own hand-offs
and from three review passes. Phase 10's planning read added eight more; the list's own preamble
provides for that, in as many words ("**Entries added after that restatement carry their own date**,
so the list grows as later review passes route audit-or-repair work here"). Every one of the
thirty-two is dispositioned below.

**And phase 10 is the last phase.** It has nowhere to hand anything. CLAUDE.md's four owners for a
finding reduce here to three: a numbered task in this plan, a fix made on the spot in writable
material, or an entry in `docs/first-release.md`. There is no later phase, and there is no register to
append to — both item-ID namespaces were retired on 2026-09-13 and neither is reused.

**What phase 10 is not.** It is not a second conformance pass. Phase 9 dispositioned all 41 `XCUT`
and `NFR` IDs and committed the instrument; phase 10 reads that instrument's output and repairs what
it reports. It does not re-run phase 9's judgement, and it does not re-open the one trade the roadmap
forbids it to: §10.5's split of `ASYNC-3`, `ASYNC-4` and `PIPE-33` is audited, not revisited
(roadmap cross-cutting constraint 8).

---

## Governing documents

Six, all binding here, and the first three in a stronger sense than in any earlier phase — phase 10's
deliverable is a verdict *about* them.

- **`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` in full** — the
  normative deviation ledger, nineteen entries plus a closing note, and the source of this phase's
  own 124 requirement IDs. **`docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md`**,
  twenty-one resolutions each of which is a claim about how a tension was settled, and
  **`docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md`**, whose per-prefix rows, its
  three kinds of entry (*not satisfied* / *vacuous* / *deferred*) and its MUST-level summary — "two
  are not satisfied … eight hold vacuously" — are the coverage claims phase 10 re-derives rather than
  inherits. All three are **frozen**: phase 10 may not edit them, which is the whole subject of `R5`.
- **`docs/deviations.md`** — the register phase 10 audits, nineteen rows plus a nine-entry holding
  area under *Deviations found outside a phase*, and **`docs/first-release.md`** — thirteen blockers,
  four subsections of what v1 ships without, a release path and seven post-release triggers. These
  two are the only registers left, and phase 10 is the last phase that writes to either before a tag.
- **`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`** — the phase-10 row, the ordering
  rationale that states this phase's method, cross-cutting constraint 8, and the inbound list at
  `:1790` onward, which is the entry this design read first and which the roadmap says so in as many
  words.
- **`docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance-design.md`** and
  **its plan** — `R6`'s boundary ("phase 9 measures and reports; phase 10 repairs"), `R3`'s
  absent-artifact rule, the five result statuses, `Report#blocking_vacuities`, `accepted_vacuous:`,
  the three repository gates with their allowlists and stated blind spots, and the 61-row
  `APPENDIX_B.md` coverage map. **Phase 10 consumes an instrument it did not build and may not
  redesign**, exactly as phase 9 consumed 8a's assertion protocol — with one exception argued in
  `R3`.
- **`CLAUDE.md`** — the hard rule on what core may `require`, the requirement-ID conventions, the
  domain-model construction pattern, the constraints that will bite, and the finding-routing rule,
  all five of which are audit subjects here and not merely context. Phase 10 also owns the `claims`
  sentences: the phase-directory count goes from ten to eleven with this filing.
- **`docs/README.md`** — the ownership table, what is frozen to maintenance tooling, and the
  `docs/work/` naming rules.

The Ruby styleguide is binding through the corpus, as in every phase, except where a note under
`docs/knowledge/notes/` records otherwise. Phase 10 files one note and adds no conflict.

---

## The segmentation decision

**Phase 10 is not segmented.** One design, one plan, both at `docs/work/mvp/phase10/`.

The roadmap's rule reaches build phases only:

> A **build phase** — phases 1 through 8 — whose ID count clearly exceeds earlier phases', or that
> spans more than one ID-bearing spec chapter, or that ships more than one gem, gets a
> **segmentation design at the `phaseN/` level before any sub-phase design** … Phase 0 carries no
> requirement scope, so the rule does not reach it; **phases 9 and 10 are audit-led and segment only
> if their own design finds it necessary.**
> (`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:175-182`)

So the question is whether this design finds a cut necessary. It does not, on four counts — and the
first of them is the one that looks like it cuts the other way, so it is stated first and answered
rather than buried.

**The ID count is the largest in the roadmap, and it is the wrong unit.** 124 own rows, against phase
6's 111-plus-15 and phase 1's 42. But **fifty-one of the 124 are one entry's ID family**: §10.1
retires the byte-stream provider seam and, in doing so, names `SEAM-3`–`SEAM-10`, all forty-two `IO`
IDs and `XCUT-23`, because the entry's argument is precisely that `IO-1`–`IO-29` and `IO-37`–`IO-42`
are implemented in full while only the pluggability apparatus is removed. Auditing that entry is one
read of one evidence tree against one claim, and it produces fifty-one checklist rows because
fifty-one IDs are named by the sentence being audited. **The unit of work here is the ledger entry,
not the ID**: 19 entries plus a closing note, plus 32 inbound bullets, is **52 units** — the same
order as phase 1's 42 unsegmented rows and phase 9's 41, and an order of magnitude below what 124
rows would suggest. Phase 9 made the same argument from the other direction when it counted 41 IDs
against 42; this one counts 52 units against 42.

**Only one of the rule's three triggers fires, and it fires maximally rather than meaningfully.**
Phase 10 spans **all nineteen** ID-bearing chapters, because design §10 does. It ships **no new gem**
— its repairs land in `dexpace-core`, `dexpace-transport-net_http`, `dexpace-transport-async_http`,
`dexpace-conformance` and the repository's own tooling, every one of which already exists by the time
phase 10 runs. The trigger that forced phase 8's cut, "ships more than one gem", is absent; the
trigger that forced phase 3's, "spans more than one ID-bearing spec chapter", is satisfied so
comprehensively that it cannot guide a cut — there is no chapter boundary that is not also inside a
single ledger entry.

**Every candidate cut splits a ledger entry.** A cut along prefix lines would put §10.1's `SEAM`
half in one sub-phase and its `IO` half in another while both audit one sentence. A cut along "core
versus adapters" would split §10.4, whose cancellation claim spans `SEAM-13`, `CFG-17`, `RETRY-23`,
`TRANSPORT-3` and `ASYNC-5` across three gems by construction, and §10.12, whose one ownership rule
is the I/O layer's and the body layer's and the serde seam's at once. A cut along "audit versus
repair" is the worst of the three: it would recreate, *inside* phase 10, the boundary phase 9's `R6`
drew between the two phases — and phase 10 exists because that boundary has to be crossed somewhere.
The reason `R6` works for phase 9 is that "the audit's value is that its findings are not filtered by
whether the auditor felt like fixing them"; that argument does not transfer to a phase whose row
grants the repair budget, and re-drawing the line here would leave the second half with no phase
after it.

**And the shared contract is already written, in two other phases.** Any segmentation would need a
sub-phase to fix the disposition vocabulary and the report-reading rules — and those are phase 8a's
five result statuses, phase 9's `Report`, `Levels::OF` and `accepted_vacuous:`, and `docs/deviations.md`'s
own row vocabulary. A sub-phase whose only job is to restate an inherited contract is the failure the
segmentation rule exists to prevent; the roadmap's phase-6 bullet records that exact correction being
made once already.

The one argument for segmenting, stated so it is not hidden: **phase 10 does three different kinds of
work** — it repairs code, it re-derives nineteen ledger claims, and it walks a release register — and
a plan that interleaves them would be hard to follow. The answer is a task ordering inside one plan,
which is what phase 9 did with its build/run split: **Tasks 1–3 build and read the instrument, Tasks
4–10 ship the repairs, Tasks 11–15 re-derive the ledger, Tasks 16–19 close the registers and the
phase.** That is a dependency chain a single plan expresses naturally and four sub-phases would
express as three edges.

---

## Prerequisite

**Phases 0 through 9, all of them, and phase 9 in a way no earlier prerequisite was.** Phase 9's
prerequisite was that its audit subjects exist; phase 10's is that its audit subjects exist **and have
already been audited once**. `R3` below states what phase 10 does with each of phase 9's five result
statuses, and the answer is different for each, so a phase-10 task that runs before phase 9's Task 16
has nothing to read.

Phase 10 states no convenience ordering and claims no sub-phase independence. It has one internal
ordering constraint: **Task 3 reads phase 9's aggregate report, and Tasks 4–10 consume Task 3's
intake.** Everything after Task 10 depends on the repairs having landed, because the ledger
re-derivation audits the tree *including* those repairs.

The one dependency that runs outward rather than inward: **nothing reads phase 10's output except the
release.** `docs/first-release.md`'s blocker list is the interface, and `R11` states what phase 10
puts on it.

---

## Corpus reading, and what it settled

The phase-start pair was run before anything here was written.

`ruby scripts/knowledge.rb --section conflicts --brief` returns **six** styleguide-versus-design
conflicts and **all six print `[overridden by notes/…]`** — `data-modeling/35fde90f`,
`module-organization/bf6411ad`, `package-and-dependency-layout/41b154a3`,
`package-and-dependency-layout/8c0687bf`, `tooling-and-quality-gates/86d763f1` and
`type-system/93dc79aa`. **None is open.** That matters more here than in a build phase for a reason
specific to this one: four of the six are the premises of the very claims phase 10 audits. §10.7's
narrowing of "standard library" rests on `package-and-dependency-layout/41b154a3`'s resolution of the
Ruby floor; §10.19's retarget of `NFR-8`/`NFR-9` rests on `tooling-and-quality-gates/86d763f1`'s
rubocop baseline. An audit that re-opened one would be auditing this port against the styleguide's
contract rather than against its own, which is the failure the query exists to catch.

`ruby scripts/knowledge.rb --origin note --brief` returns **51 entries across 21 topic files** at
`HEAD` — phase 9 predicted exactly that number for 2026-09-13 and it is what the corpus now returns.
**52 across 21 after this phase's one note**, which adds one entry to
`docs/knowledge/notes/observability.md`. (Notes, files and entries are three different units; this
sentence counts entries, which is what the query returns.)

Phase 10 read every one of the 51, because a note is by definition a place where a harvested rule was
found false, and phase 10's job is to find claims that are false. Two are load-bearing here and are
adopted rather than re-derived: `notes/io-and-byte-streams.md`'s override of
`io-and-byte-streams/fbcb4d19` is the corpus half of inbound bullet 11 (§3.1's decode recipe), and
`notes/message-bodies.md`'s mark on `message-bodies/8a1e7a7b` is the corpus half of bullet 13
(`IO-6` versus the retired `SEAM-3`). Phase 10 writes neither again; it carries them into the
amendment set of `R5`.

### The spec-reading budget

Phase 10's prefixes are **all nineteen**, so the gap query was run over all of them:
`ruby scripts/knowledge.rb --gaps SEAM,HTTP,IO,BODY,PIPE,RECOV,RETRY,REDIR,AUTH,PAGE,SSE,SERDE,OBS,CFG,TRANSPORT,ASYNC,XCUT,NFR`
reports **21 of 625 IDs in 18 prefixes with no substantive entry — 0 roll-up only, 21 uncited**:
`SEAM-22`, `SEAM-28`, `IO-32`–`IO-35` and `RECOV-17`–`RECOV-31`. (`CTX` was queried separately and is
20 of 20 substantive.)

**Five of the 124 own rows fall in that set** — `SEAM-22` (§10.14's witness protocol) and `IO-32`,
`IO-33`, `IO-34`, `IO-35` (§10.1's retired registry) — **plus `SEAM-28` among the cross-reference
rows.** For every one of the six the CLI reports "appendix C is their only normative statement — no
`docs/product-spec/` chapter states them", so **the budget is six appendix-C rows read verbatim and no
chapter reading at all.** They were read during this design and are quoted where they decide
something: `IO-32`/`IO-33` are the install-idempotence and explicit-install-wins clauses, `IO-34`/`IO-35`
the resolution cache and the replaced-provider warning — the four clauses §10.1's retirement removes
the *subject* of, which is why the entry's own sentence says "only the pluggability apparatus is
removed"; and `SEAM-22` is the generic-type-capture MUST §10.14 substitutes the witness protocol for.

The fifteen `RECOV` gaps are not phase 10's rows — §10.6 names `RECOV-12` and §10.18 names `RECOV-34`,
and both are substantive — so phase 10 inherits phase 6a's reading of them rather than repeating it.

**This is not the appendix-B situation phase 9 faced.** Appendix B is not in phase 10's scope: phase
9 committed the 61-row map and owns it, and phase 10's only business with it is one strengthening
`R3` argues for. So phase 10 budgets no appendix-B reading and is not exposed to the roll-up hazard
at all — every `--req` result this design rests on came back substantive.

### The audit groups, run in full

The `knowledge-lookup` skill's table names the groups; a group not written down cannot be repeated.
**Seven were run.** Phase 10 is the phase where the groups are read as *claims to check* rather than
as rules to follow, and two of the seven produced a finding.

| Audit group | Query | Result |
|---|---|---|
| *Styleguide-vs-design conflicts* | `--section conflicts --brief` | Six, all overridden. Four are premises of §10.7, §10.19, §10.3 and §10.14's arguments, listed above; phase 10 inherits and re-opens none |
| *Public API surface* | `--topic api-design,http-domain-model,documentation,module-organization,error-handling --section rules --brief` | Clean, and **one rule decides a phase-10 question**: `api-design/1d9e6e0b` is what makes a keyword-with-a-default an additive widening, which is the rule `R7` declines to use and `R8` does use. `api-design/46c8b5fc` is `NFR-4` verbatim and is why `R11` cannot mark `NFR-4` ✅ |
| *Gem layout, zero-dependency core* | `--topic package-and-dependency-layout --section rules,constraints --brief` and `--prefix SEAM --section rules --brief` | Clean. `package-and-dependency-layout/70fbcaee` (the Ruby 4.0 bundled-gem list, 23 entries re-verified against a real 4.0.6) is the note §10.7's audit rests on, and it is a note rather than a harvested rule because phase 0 found the harvested six wrong |
| *Encoding and binary strings* | `--prefix IO --section rules --brief` and `--topic io-and-byte-streams,serde --section rules --brief`, then `--grep 'encoding\|binary\|ASCII-8BIT\|force_encoding'` | **One rule already carries the phase-10 finding**: `io-and-byte-streams/fbcb4d19` prints `[overridden by notes/io-and-byte-streams.md]`, which is §3.1's decode recipe — inbound bullet 11. Adopted; not re-noted |
| *Resource lifecycle and stream ownership* | `--topic resource-management --section rules --brief` and `--chapter 13` | **One rule carries the other attribution finding**: `message-bodies/8a1e7a7b` is marked by `notes/message-bodies.md`, which is `IO-6` versus `SEAM-3` — inbound bullet 13. Adopted |
| *Observability, configuration and redaction* | `--topic observability,configuration,redaction-and-security --section rules --brief` and `--prefix CFG,OBS --section rules --brief` | **A finding.** No harvested or note entry records that `OBS-29`'s canonical text ends "pipeline/transport wiring to emit it is a follow-up, so it is not yet runtime-enforced", which is the sentence that closes the surface decision three phases treated as open (`R6`). Phase 10 files the one note this phase files, against `observability/…`'s HTTP-tracer entry |
| *Cross-cutting invariants* | `--topic cross-cutting-invariants --section rules,constraints,conclusions --brief` | Clean. `notes/cross-cutting-invariants.md`'s two entries — the `XCUT-11` predicate and the `:LIT`/`:SYM` AST divergence — are phase 9's and are adopted unchanged; the second is why Task 6's new gate names both node types from its first line |

---

## The verified Ruby facts this phase is built on

**Every fact below was run on all four installed interpreters — 3.2.11, 3.3.12, 3.4.10 and 4.0.6 —
which is the whole supported matrix.** Where a measurement is of a gem rather than of the
interpreter, the gem version is named and how it was obtained is stated. Nothing here is quoted from
an earlier phase without re-running it; two of the seven came back **different from the record**, and
both are findings.

**Fact 1 — the unused-rescue-binding warning is real on every row, phase 9's `$VERBOSE` window
suppresses it on every row, and the one fence that carried it has already been repaired.** Parsing a
`rescue ::StandardError => e` whose body never reads `e` with `RubyVM::AbstractSyntaxTree.parse_file`
under `-w` emits `warning: assigned but unused variable - e` on **3.2.11, 3.3.12, 3.4.10 and 4.0.6**,
identically; the same call inside a `$VERBOSE = nil` window restored in `ensure` — which is exactly
`AstScan.parse`'s shape — emits **nothing** on all four. The interpreter half of inbound bullet 7 is
therefore sound on every matrix row, and phase 9's mitigation stays.

**Corrected 2026-09-13, and the correction is the reason this fact reads differently from the bullet
that produced it.** Bullet 7 cites the shape at
`docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance.md:4858`, and
**that fence no longer carries the binding**: 8a's `Adapter#dispatch` reads `rescue ::StandardError`
with no `=> e` at that plan's **`:5177`** (the method at `:5168`), and the same plan records the repair
in its own correction list — "**`rescue ::StandardError => e` in `Adapter#dispatch` never read `e`** …
the binding is gone" (`:6337-6339`). `git log -S` names the commit: **152ec6a**, the pre-build review
of every MVP phase plan, which also corrected two further shapes for the same reason. Line 4858 today
is `body = res.body_string`. So the *repair* half of bullet 7 is **closed before phase 10 starts**, and
what survives is the generalisation — nothing asserts that `AstScan.parse` is the only caller of
`parse_file` — which is what Task 6 now ships alone. The fixture stays, as the artifact that proves the
gate's own `$VERBOSE` mechanism rather than as a defect waiting to be fixed.

This is worth stating plainly because it is the error class `R2` exists to catch, committed by this
design's own first draft: the shape was taken from the bullet that cited it instead of from the file it
names. Load-bearing for Task 1 and Task 6.

**Fact 2 — an SPDX header is expressible in RBS and parses on every row.** A `.rbs` file opening
with two `#` comment lines and a blank line before `module Dexpace` parses through
`RBS::Parser.parse_signature` on `rbs` **2.8.2** (3.2.11), **3.4.0** (3.3.12), **3.8.0** (3.4.10) and
**3.10.0** (4.0.6); the bare form parses identically, so adding the header changes nothing a
consumer's `steep check` sees. Two consequences for Task 5: the `NFR-13` repair is a header plus a
glob and not a format negotiation, and the `sig/` header is **SPDX only** — `# frozen_string_literal: true`
has no meaning in RBS, so the two-line `lib/` header becomes one line in `sig/`. Load-bearing for
Task 5.

**Fact 3 — `net-http`'s connect-phase `Timeout.timeout` is present on every row and its line number
is not stable.** The call is `net/http.rb:1601` on 3.2.11, `:1601` on 3.3.12, `:1657` on 3.4.10 and
`:1791` on 4.0.6, and on every row it is
`Timeout.timeout(@open_timeout, Net::OpenTimeout) { TCPSocket.open(…) }`. Inbound bullet 19 cites it
as `/usr/lib/ruby/3.4.0/net/http.rb:1657` — a machine-absolute path and a 3.4-specific line, neither
of which resolves on three of the four rows. **The finding survives and strengthens** (the primitive
is used on every supported Ruby, not just one); what must change is the citation, and the amendment
`R5` carries names the call and the method rather than a line. Load-bearing for Task 17's amendment C8.

**Fact 4 — the `async-http` dependency closure contains no `Timeout.timeout`, seven `Fiber#raise`
sites, one `Thread#raise` on the calling thread and one `Thread#kill`, and this answers the second half
of bullet 19 that nothing had measured.** Installed under `--install-dir` in the session scratchpad on 3.4.10, the closure resolves
to **17 gems**, including `async` 2.45.1, `async-http` 0.104.0, `io-event` 1.22.0, `protocol-http1`
0.41.0, `protocol-http2` 0.28.0 and `io-stream` 0.14.0 — the same versions phase 8c measured against.
A source scan of every `lib/` in the closure finds:

- **`Timeout.timeout`: zero calls.** The only occurrence is a documentation comment at
  `async/scheduler.rb:681`. So the sharpest form of bullet 19's hazard is absent on the async side.
- **`Fiber#raise`: seven sites** — `async/task.rb:365`, `async/scheduler.rb:324`, `:354`, `:378`,
  `:407`, `:666`, and `io-event/selector/select.rb:114`. The first is
  `Fiber.scheduler.raise(@fiber, Cancel, cause: cause)`, which is **how `Async::Task#cancel` delivers
  `Async::Cancel`** — the mechanism phase 8c's `TRANSPORT-8` measurement rests on. `Fiber#raise` is
  **not on §8.3's list**, and the omission is principled rather than accidental: a fiber raise resumes
  the fiber with an exception at a **scheduler checkpoint**, which is the precise property §8.3's
  rationale distinguishes from an interrupt landing on arbitrary bytecode, and which design §3.3 and
  §8.3 already rely on for the async path.
- **`Thread#raise`: one site**, `io-event/selector/select.rb:398`, and it is reported rather than
  omitted because §8.3 names that primitive by name and a reader auditing the ban will grep for it. It
  is benign for a reason about the **receiver**, not about reachability: the call is
  `Thread.current.raise(error)` — a raise on the *calling* thread, which is an ordinary synchronous
  `raise` and not the asynchronous cross-thread interrupt §8.3 prohibits, so nothing lands on another
  thread's arbitrary bytecode. Its own comment says what it is for ("For all other errors (e.g. thread
  interrupts), re-queue on the scheduler thread"), and it sits in `Selector::Select`, the pure-Ruby
  fallback selector rather than the `URing`/`EPoll` selectors `io-event` prefers on Linux.
- **`Thread#kill`: one site**, `io-event/selector.rb:59`, in the `ensure` of
  `Selector.process_wait`, killing a helper thread whose entire body is `Process::Status.wait(pid, flags)`.
  The adapter waits on no child process, so the path is unreachable from
  `dexpace-transport-async_http`, and the thread holds no SDK resource — which is the same shape of
  answer bullet 19 gives for `net-http`'s `TCPSocket.open`, reached independently.
- Incidentally corroborated: `async`, `async-http`, `io-event` and `protocol-http1` all declare
  `required_ruby_version >= 3.3`, which is 8c's `P8-36` and the `NFR-10` per-gem-floor finding,
  re-verified rather than quoted.

So the amendment §8.3 is owed is **larger and better evidenced** than "one clause scoping the
prohibition to code this repository writes": it is that clause plus the statement of what the
dependency closures actually do, which is the thing a reader auditing the ban will want and which no
document currently holds. Load-bearing for Task 17's amendment C8.

**Fact 5 — `rescue ArgumentError` catches an `ArgumentError` subclass on every row.** With
`class IAE < ::ArgumentError; end`, `raise IAE` is caught by `rescue ArgumentError` on all four, and
`ArgumentError.ancestors` begins `[ErrorHighlight::CoreExt, ArgumentError, StandardError, Exception]`
identically. So `7c`'s `Dexpace::InvalidArgumentError < ::ArgumentError` spelling really does put
`PAGE-14`'s **state** violation into the argument family, where a caller's `rescue ArgumentError`
around a page loop swallows it — which is bullet 24's claim, now measured rather than reasoned.
Load-bearing for Task 8.

**Fact 6 — the repository's chapter-attribution population, measured today, and a working check.**
Over every `*.md` under `docs/`: **38 lines name both a `docs/product-spec/` chapter and a canonical
requirement ID, and none of them is inside appendix C.** **Those numbers are convention-dependent and
are stated as such**, because a population is only defined once its patterns are: 38 is what the
check's own chapter-reference and ID patterns see, and it was taken **before this design and its plan
joined the population**. A wider regex — any `docs/product-spec/*.md` path on a line beside any
canonical ID, appendix-C-only lines dropped — reads **47 today, 36 of them outside phase 10's own two
files**. Neither number is the claim. The claim is the **ratio**: whatever the population, the
clause-scoped rule must fire with **0 false positives**, and Task 1 Step 4 re-measures all four numbers
and reads every fire rather than trusting these. A naive same-line rule — fire when a line
names a chapter and an ID the chapter does not carry — fires on **14 lines / 23 (chapter, ID) pairs,
of which 4 are true positives**; the other nineteen are correct prose, most of it sentences whose
whole subject is that the ID is *not* in that chapter. A **clause-scoped** rule — split at `;`,
associate each ID with the nearest preceding chapter reference, evaluate a negation vocabulary over a
two-line window, and exempt appendix C — fires **3 times, all 3 true positives, 0 false positives**,
with two stated blind spots: a clause continued onto the following line, and a backticked range
(`` `SEAM-11`–`SEAM-15` ``), which is what hides a fourth true positive. **This is the measurement
that decides bullet 3**: the roadmap asked for "a claim grammar ('read out of X', 'stated in X', an
`X §N` adjacency)", and a claim-verb grammar matches **0 of the 38** — the axis is clause scoping, not
verb detection. Load-bearing for Task 7.

**Fact 7 — Minitest resolution on this machine has moved since phase 9 measured it, and the new shape
is worse.** `Gem::Specification.find_by_name("minitest").version` is **5.25.1** on 3.2.11, **5.20.0**
on 3.3.12, **6.0.6** on 3.4.10 and **6.0.0** on 4.0.6, with `default_gem?` **`false`** on all four —
so the bundled-gem correction (bullet 21) is re-verified, and phase 9's per-row versions (5.25.1 /
5.25.4 / 6.0.0) are now two rows out of date. The 6.0.6 on 3.4.10 lives in the **user** gem directory
beside the 5.25.4 the interpreter ships, and a bare `require "minitest"` there resolves **6.0.6**, not
the shipped 5.25.4. Worse, `require "minitest/mock"` followed by `require "minitest/autorun"` on that
row loads **both copies** and emits **13 `already initialized constant` warnings** — which
`NFR-6`'s `Warning.warn`-raising gate turns into a failure. `require "minitest/mock"` still raises
`LoadError` on 4.0.6 and `Object#stub` is still absent there. **What this changes:** phase 0's
`~> 5.25` pin is not merely what keeps `stub` available on the 4.0 row; it is what makes the **3.4**
row deterministic at all, and the mechanism is newest-wins resolution in the user gem directory
rather than anything about the interpreter. That is a stronger argument for the pin and for
`bundle exec`, and it is a correction to the measurement `docs/first-release.md`'s Minitest trigger
records. Routed in *Findings*.

---

## Scope

### What the 124 own rows are, and why they are rows at all

**One checklist row per requirement ID named by design §10's nineteen entries, plus `RETRY-28` from
§10's closing note — 124 in all: 108 MUST, 15 SHOULD, 1 MAY.** The roadmap's phase-10 row states the
scope as "appendix C — every ID named by design §10's 19 entries", and this design takes that
literally: the set was extracted from the chapter mechanically, every range expanded, and every
member checked against appendix C. **All 124 resolve; none is a typo.** `RETRY-28` is named only by
the closing note — "the two retry stacks are **not** unified, so neither **RETRY-28**'s nor
`08-execution-pipelines.md`'s unification sanction is invoked" — which is a claim of the same kind as
the nineteen and is audited with them; it is called out separately so the count reads as 123 + 1
rather than as an unexplained 124.

The distribution, which is what the segmentation argument rests on:

| §10 entry | Subject | Own IDs | Task |
|---|---|---|---|
| §10.1 | The byte-stream provider seam is retired; its behavioural contract is not | **51** — SEAM 3–10; IO 1–42; XCUT-23 | 11 |
| §10.2 | The canonical body is a duck type, not a nominal interface | SEAM-3; BODY-1, BODY-35 | 12 |
| §10.3 | The async pivot is a core-owned future | SEAM-1, SEAM-16, SEAM-17; ASYNC-1, ASYNC-2; NFR-11 | 12 |
| §10.4 | Cancellation is cooperative; the orphaned-response close moves to the producer | SEAM-13, SEAM-30; XCUT-1–3; CFG-17, CFG-20, CFG-21; RETRY-23; TRANSPORT-3; ASYNC-5 | 12 |
| §10.5 | Two MUSTs are not satisfied and a third holds vacuously | ASYNC-3, ASYNC-4; PIPE-33 | 12 |
| §10.6 | Suppressed exceptions are a core-owned trail | RECOV-12; PAGE-13, PAGE-15; SSE-29, SSE-30, SSE-36; RETRY-34; XCUT-9 | 13 |
| §10.7 | "Standard library" narrowed to what is stable across the range | SEAM-1; NFR-1; AUTH-14; OBS-2 | 13 |
| §10.8 | Discovery's substrate is require-time self-registration | SEAM-5–9; XCUT-23 | 13 |
| §10.9 | `SEAM-10`'s multi-loader de-duplication is vacuous | SEAM-10 | 13 |
| §10.10 | Runtime encapsulation of models is partially unachievable | HTTP-2, HTTP-4, HTTP-7, HTTP-17, HTTP-18; SEAM-29; IO-28; BODY-37; XCUT-18 | 14 |
| §10.11 | Read-only collection exposure is computed once | HTTP-5; XCUT-15 | 14 |
| §10.12 | One stream-ownership rule for bodies | BODY-8; SEAM-3, SEAM-20, SEAM-21 | 14 |
| §10.13 | The serde seam ships four encode profiles | SEAM-20 | 14 |
| §10.14 | The serde witness is a class-object-and-combinator protocol | SEAM-22, SEAM-23; SERDE-5–8, SERDE-16, SERDE-17 | 14 |
| §10.15 | The cross-origin redirect marker lives on the per-hop cursor | REDIR-11; AUTH-29; PIPE-16 | 15 |
| §10.16 | The configuration chain keeps four tiers | CFG-1, CFG-3, CFG-4, CFG-24, CFG-26; OBS-35 | 15 |
| §10.17 | The interruptible sleep is a cancellable queue wait | CFG-15, CFG-17, CFG-18; RETRY-26; XCUT-3, XCUT-13 | 15 |
| §10.18 | Platform-constant substitutions where Ruby has no constant | IO-9; BODY-32; SSE-11; RECOV-34 | 15 |
| §10.19 | The dead-code-survival gate is retargeted | NFR-8, NFR-9 | 13 |
| closing note | Neither unification sanction is invoked; both seams and both bridges survive | RETRY-28 | 15 |

An ID named by more than one entry gets **one** row, in the earliest task that audits it, and the row
names every entry that names it — `SEAM-3` appears in §10.1, §10.2 and §10.12 and is audited in Task
11 with the other two entries' claims cross-referenced; `SEAM-5`–`SEAM-9` appear in §10.1 and §10.8
and are audited in Task 11, with Task 13 re-reading them for §10.8's own claim about what makes a
candidate discoverable. The per-task counts are **51 / 22 / 13 / 21 / 17**.

### The 64 cross-reference rows

**Every requirement ID an inbound bullet's own *Touches* line names, or a newly-found hand-forward
names, or one of phase 10's own repairs touches, that is not among the 124 — 64 rows: 44 MUST, 16 SHOULD,
4 MAY.** These follow the
two-rows-one-obligation discipline phase 2 gave `SEAM-29`, phase 3b gave `HTTP-46` and phase 9
declined to take for `TRANSPORT` and `ASYNC`: the owning phase keeps the ID, phase 10 carries a
**cross-reference** row recording what its repair did to that ID, and **no earlier phase's row moves.**

| Prefix | Cross-reference rows |
|---|---|
| SEAM | `SEAM-11`, `SEAM-15`, `SEAM-28` |
| HTTP | `HTTP-3`, `HTTP-24`, `HTTP-42`, `HTTP-43`, `HTTP-51` |
| BODY | `BODY-2`, `BODY-15`, `BODY-16` |
| CTX | `CTX-14`, `CTX-16`, `CTX-20` |
| PIPE | `PIPE-2`, `PIPE-11`, `PIPE-37` |
| RETRY | `RETRY-13` |
| AUTH | `AUTH-35` |
| PAGE | `PAGE-14` |
| SSE | `SSE-19`, `SSE-26`, `SSE-40` |
| SERDE | `SERDE-2` |
| OBS | `OBS-4`, `OBS-5`, `OBS-8`, `OBS-19`, `OBS-21`–`OBS-25`, `OBS-28`, `OBS-29`, `OBS-34` |
| CFG | `CFG-22`, `CFG-23`, `CFG-25`, `CFG-27`, `CFG-28` |
| TRANSPORT | `TRANSPORT-2`, `TRANSPORT-4`, `TRANSPORT-8`, `TRANSPORT-13`, `TRANSPORT-14`, `TRANSPORT-17`, `TRANSPORT-18`, `TRANSPORT-19`, `TRANSPORT-25`, `TRANSPORT-28`, `TRANSPORT-29`, `TRANSPORT-30` |
| ASYNC | `ASYNC-6` |
| XCUT | `XCUT-4`, `XCUT-11`, `XCUT-12`, `XCUT-14` |
| NFR | `NFR-2`, `NFR-3`, `NFR-4`, `NFR-6`, `NFR-13`, `NFR-17` |

**Total: 188 checklist rows** — 124 own, 64 cross-reference. Three of the 64 are there because a
phase-10 repair touches them rather than because an inbound bullet names them: `SEAM-15` (the attribution
`R10`'s check corrects), and `XCUT-11` and `AUTH-35` (the two requirements `R9`'s fiber assertion exercises
beside `XCUT-12` — `8b` handed the two-fibers-on-one-thread shape forward for the first, and the second is
the provider contract the assertion's own subject has to honour: `AUTH-35` (MUST) requires the bearer step
to reject a misbehaving provider result, a null or already-expired token to surface as an error, and a
throwing provider to propagate **and not be cached**, which is exactly what a single-flight fetch under a
reactor must still do). The checklist is written at execution
time, per the roadmap's execution step 6.

**Three IDs are named by phase 10's own text and deliberately get no row**, stated here so their absence
reads as a decision rather than an omission: `NFR-10` (cited by the Minitest finding), and `NFR-12` and
`NFR-16` (named in Task 18's heading). Phase 10 neither audits nor repairs any of the three — Task 18
only walks the `docs/first-release.md` lines that mention them, which is register work and not a
requirement verdict — and **phase 9 owns all three rows**. Adding a cross-reference row that records "no
repair, no audit" would be the two-rows-one-obligation discipline used for nothing. The counts therefore
stand at 124 / 64 / 188.

### Out of scope, explicitly

**Appendix B is phase 9's and stays phase 9's.** The 61-row `APPENDIX_B.md` map, its three checks and
its `by reference` residue belong to phase 9's Task 14. Phase 10 touches it in exactly one place, for
one reason argued in `R3`, and it adds no row and lifts no item.

**The `XCUT` and `NFR` dispositions are phase 9's and are not re-made.** Phase 10 reads phase 9's
seventeen `NFR` rows and twenty-four `XCUT` rows as **input**. Where a row is ⏳ pending a repair phase
10 ships, phase 10's own cross-reference row records that the repair landed and names phase 9's row;
it does not rewrite phase 9's checklist.

**§10.5's trade is not re-opened.** Cross-cutting constraint 8 says so and this design says so twice:
`ASYNC-3` and `PIPE-33`'s interrupt clause are audited as unsatisfied, `ASYNC-4` as vacuous, and
`CFG-20`'s cancel-with-interrupt clause as the same unmet clause under a second ID. Phase 10 adopts no
interruptible path; §8.3 forbids one.

**No new gem, and no new seam.** Phase 10 adds no `Dexpace::` namespace that is not already in
`CLAUDE.md`'s gem table, and the one public constant it adds — `Dexpace::SingleUseError` (`R8`) — goes
in `dexpace-core` beside the error hierarchy phases 1 and 2 built.

**Publication is not phase 10's.** `docs/first-release.md`'s release path is "not yet defined" and
phase 10 does not define it: it has no RubyGems ownership to settle and no trusted publishing to
configure, both of which are listed blockers whose subjects are outside this repository. **Every gem
stays at `0.0.0`** and nothing is tagged or pushed. What phase 10 owns of the release is stated in
`R11`, and it is the readiness rather than the act.

---

## `R1` — what "audit-led; ships code where the audit finds a defect" means mechanically

**Decision: an audit step and a repair step are different steps, with different exit conditions, and
a task never contains both for the same subject unless the audit found the defect in the same
task.** `P10-1`.

The roadmap's phrase invites a phase that drifts into rewriting whatever it dislikes. Three rules
keep it from doing that, and each is checkable.

**An audit step's product is a row, not a change.** It names the claim (a sentence in §10, §11, §12 or
`docs/deviations.md`, quoted), names the as-built evidence (a path, a constant, a line range in a
filed fence), and records one of four verdicts: **confirmed** (the claim is true of the code),
**confirmed-with-a-narrowing** (true, and narrower than the sentence says), **contradicted** (false),
or **unverifiable** (no artifact to check — `R3`'s absent case). An audit step that produces no row
has not run.

**A repair step's product is a change with a test that failed first.** Phase 10 ships code under
ordinary TDD: the failing test, confirmed failing, the change, confirmed passing. A repair with no
failing-first test is indistinguishable from a change of opinion, and this phase has more scope for
changes of opinion than any other.

**What closes a row.** For an own row: the verdict, plus — where the verdict is *contradicted* — either
a repair task number or an amendment in `R5`'s set. For a cross-reference row: the repair task number
plus the owning phase's row it cross-references. For a row the audit finds *unverifiable*: ⏳ with the
reason, and a `docs/first-release.md` entry if the ID is a MUST, because phase 10 has no later phase
to hand it to. **The one thing that never closes a row is a design document agreeing with itself.**

**Where phase 10 may write, as a file list**, which is `R6`'s discipline applied to the phase that
inherits it:

- `gems/dexpace-core/lib/`, `sig/`, `test/` — for `R8`'s error type and Task 10's wire form.
- `gems/dexpace-transport-async_http/` — `lib/`, `sig/`, `test/` — for Tasks 4 and 9.
- `gems/dexpace-transport-net_http/` — **`sig/` only**, for Task 5's header, and its `test/` tree for
  Task 10's `ResponseMapper` assertion. Task 6 no longer reaches its `lib/`: the binding it was going to
  drop is already gone (Fact 1).
- `gems/dexpace-conformance/` — for Task 3's two repairs only.
- every gem's `sig/**/*.rbs` — for Task 5's header.
- `tasks/gates.rake`, `tools/`, `test/`, the root `Rakefile`, `.github/workflows/ci.yml` — for the two
  new gates, and the `Rakefile` for the same reason phase 9 needed it: `DEFAULT_GATES` is defined
  there and frozen after `tasks/*.rake` load, so a gate added anywhere else is not blocking, which
  `NFR-17` forbids.
- `.claude/skills/housekeeping/` — for Task 7's claim check and its tests.
- `docs/deviations.md`, `docs/first-release.md`, `CLAUDE.md`, `docs/README.md`, the roadmap's status
  notes and inbound list, `docs/knowledge/notes/`, and every `docs/work/mvp/` document — for the
  register work and the corrections `R5` and *Findings* route.

**Where it may not**: `docs/product-spec/`, `docs/product-spec.md`, `docs/sdk-design-ruby/`,
`docs/sdk-design-ruby.md`, `docs/knowledge/harvested/`. Five trees, frozen, and `R5` is the whole
consequence.

**Addendum, 2026-09-25 — `R1`'s file list widened, by the maintainer's decision at execution.**
Four trees join the list above, each for a named reason and nothing wider: `docs/sdk-documentation/**`
and the root `README.md`, where a repair makes a page's prose stale; `gems/dexpace-transport-net_http/lib/**`
for **YARD comments only** — the `@decode_content` unknown-tag warning and the `ResponseMapper` sentence
that said an HTTP/1.0 response raises — and no code; `rbs_collection.yaml`'s header comment and nothing
else in that file; and `gems/dexpace-conformance/**` in full, because Task 5's repair invalidates
`packaging_suite_test.rb`'s pinned `NFR-13` `:failed` and the `PackagingCase` name-rule repair lives in its
`lib/`. `.rubocop.yml` and `scripts/` stay **out**: the process-tooling RuboCop exclusion becomes a
`docs/first-release.md` line instead. **Recorded honestly:** this addendum was written in the documentation
pass, after the code that relied on it was committed on the working branch, not before it as the decision
asked; every file it admits is named above and in the checklist's "Deviations from the plan".

---

## `R2` — the re-derivation method, stated so it can be failed

**Decision: every ledger claim is re-derived from the as-built artifact the claim is about, and the
audit step names that artifact by path and constant before it reads anything else. A claim whose
artifact cannot be named is *unverifiable*, never *confirmed*.** `P10-2`.

The roadmap states the method in half a sentence — "re-deriving every ledger claim from as-built
source, never from another document" — and half a sentence is not enough to fail an audit against.
Three specifics.

**The artifact is named from the phase document that promised it, and the audit reads the code.**
This is phase 9's `R3` discipline applied to a different subject: phase 9 probed for a constant's
existence, phase 10 probes for a *property* of the constant, and both start from the same place — the
phase document that committed to produce it. So an audit step's Interfaces block names, for each
claim, the promising document (path and line) and the shipped artifact (gem, file, constant). The
promising document is how the auditor knows where to look; it is **not** evidence, and a step that
cites it as evidence has failed.

**Three verdict hazards, each with a rule.**

*The claim is about an absence.* §10.1 says the pluggability apparatus "is removed"; §10.9 says
`SEAM-10`'s de-duplication "is vacuous". An absence cannot be confirmed by reading the file the thing
is absent from — it needs a **negative scan over the tree**, and the scan's own blind spots have to be
stated, which is exactly what phase 9's three gates do for `XCUT-9`, `XCUT-14` and `SEAM-2`. Phase 10
therefore mechanises the absence claims it can (`gates:ledger_audit`, Task 2) and states the residue
of the ones it cannot.

*The claim is about a mechanism that was substituted.* Thirteen of the nineteen entries are mechanism
substitutions, and the hazard is confirming the substitution while never checking that it delivers
what the original guaranteed. The rule: an audit of a substitution names **the requirement clause**
the substitution has to satisfy, quoted from appendix C, and checks the code against *that* — not
against the design's description of the substitution. §10.11 is the worked example: the claim is that
read-only exposure is computed once; the clause is `HTTP-5`'s "MUST reproduce this guarantee with
unmodifiable wrappers or per-call defensive copies"; the check is that a caller cannot mutate a
returned collection, not that `freeze` appears in the constructor.

*The claim is about a shape that arrived differently.* Phase 9's `R3` names this case and hands the
doc repair to phase 10. The rule here is the same as phase 9's for the requirement half and stricter
for the document half: assert against what arrived, record both shapes, and **the design document
that promised the other shape is a finding, routed in *Findings* or fixed if it is writable.** A
phase document is writable; §10 is not, and that asymmetry is `R5`.

**What the method produces, as one artifact.** `docs/deviations.md`'s nineteen rows, each moved from
`design only — not yet built` to a verdict, **each citing the as-built evidence** and none citing a
design document. That file is the deliverable the roadmap's phase-10 row is really about, and Task 2's
gate is what keeps it honest after phase 10 closes.

---

## `R3` — how phase 10 consumes phase 9's report, status by status

**Decision: phase 10 reads phase 9's report once, in Task 3, and converts it into a five-column
intake table whose every row names a phase-10 task, a `docs/first-release.md` entry, or a reason no
repair is needed. Nothing in Tasks 4–19 re-reads the report.** `P10-3`.

Phase 9's `Report` carries five statuses and two separate suppression mechanisms, and each means
something different to a repair phase. Getting one wrong produces either a repair of conforming code
or a green tree over a live defect.

| Phase-9 output | What it means | What phase 10 does |
|---|---|---|
| `:failed` | The property does not hold. `Failure` carries expected and actual | **Repair.** A numbered task, and — if any ID on the assertion is a MUST — a `docs/first-release.md` blocker that closes when the task lands. Phase 9's `P9-6` files the blocker; phase 10 closes it |
| `:vacuous`, artifact absent | `InvariantCase#probe!` raised: the constant a phase committed to is not there | **Investigate, then repair or report.** This is the status phase 9 created the distinction for — "`:error` says something went wrong in the suite, `:vacuous` with a reason says phase 1 committed to `Headers` and it is not there". If the artifact is renamed, correct the row and the promising document. If it is genuinely unbuilt, it is a `docs/first-release.md` entry, because phase 10 does not build another phase's feature |
| `:vacuous`, nothing to check | The requirement's antecedent is unreachable — `XCUT-12` over a cache-free `Codec`, `SERDE-29` | **No repair.** Record the reason on the cross-reference row. An un-accepted MUST-level one blocks phase 9's report, so by the time phase 10 reads it, it is either accepted with a citation or already a blocker |
| `:waived` | The assertion **would have failed** and the first-party build suppresses it by requirement ID | **Audit the waiver, never the assertion.** A waiver is a decision recorded elsewhere — §10.5 for `ASYNC-3`, `P8-38` for `TRANSPORT-14` — and phase 10's job is to check that decision is still the one the documents state, not to make the assertion pass. `R4` states what happens if it is not |
| `:error` | The harness reached for something the gem does not expose | **Never a finding against the audited gem.** Phase 9's plan warns that treating one as such is "a false finding phase 10 would act on". An `:error` is a `dexpace-conformance` defect and falls under phase 9's own exception; phase 10 fixes it in Task 3 because phase 9 has closed |
| `blocking_vacuities` non-empty | An un-waived, un-accepted MUST-level vacuity; the report is blocked | **The report is not trustworthy.** Task 3 stops and resolves these first — each is either an absent artifact (row 2 above) or a missing acceptance citation |
| a gate offence list | `gates:cause_walk`, `gates:bounded_map`, `gates:seam_names`, `gates:serde_boundary` | **Repair the offence, never the allowlist.** Phase 9 says it plainly: "The fix is not an allowlist entry." A new allowlist entry is a decision with an argument, and phase 9 priced it — "past a dozen entries the gate is reporting that the invariant is not held" |

**The one thing phase 10 changes in `dexpace-conformance`, and why it is not a redesign.** Phase 9's
own plan records two residues phase 8's ownership prevented it from closing, and phase 10 is the first
phase that owns every gem:

1. **`APPENDIX_B.md`'s check 2 is weaker than its own prose.** Phase 9's design settles on **per-row
   ID-set equality** against the set parsed from each appendix-B item's text — "that is decidable, it
   is strictly stronger, and it makes the distinct-ID coverage check hold **by construction**" — but the
   filed test asserts only that every row names at least one ID from the nineteen prefixes, and
   `AppendixB` exposes no per-item ID accessor to compare against. The map therefore claims a check it
   does not perform. Phase 10 adds the accessor and the equality assertion. This is a defect in an
   instrument phase 10 depends on, found by reading phase 9's plan against its own design, and it is
   the narrowest possible change: one accessor, one assertion, no new column and no new row.
2. **`TransportSuite` was deliberately left off `Runner`** (`P9-10`), leaving two status-deciding paths
   in one gem, so "a future change to the five statuses must be made twice." Phase 8's ownership was
   the only reason; it does not bind phase 10. Phase 10 folds `TransportSuite.run` onto `Runner`, with
   the five statuses asserted unchanged before and after.

Both are in Task 3, both under TDD, and neither touches the statuses, the waiver mechanism or the
report's shape. **Phase 10 adds no suite, no assertion and no gate to `dexpace-conformance`.**

---

## `R4` — what phase 10 does with a red row

**Decision: a red row is repaired, or it becomes a `docs/first-release.md` entry naming what is
unmet and why v1 ships anyway. There is no third option, and "no repair needed" is only available
with evidence, never with an argument.** `P10-4`.

Phase 9 had a later phase to hand a red row to. Phase 10 does not, and the discipline that replaces
`R6` is narrower rather than looser.

**Repair, when the defect is in code phase 10's file list reaches and the fix is bounded.** Bullet
6's uncapped map is the type case: a cap, a drain loop and a `close` on each evicted value, two tests,
one file.

**A `docs/first-release.md` entry, when the repair is a feature, a decision above phase 10's pay
grade, or an act outside the repository.** Three subsections take them and the choice is not free:

- **Blockers before first publish** — an unmet MUST, or a documentation artifact a consumer needs
  before the tag. Phase 10 adds one (`R5`'s amendment set) and closes or narrows others (`R11`).
- **What v1 ships without** — a requirement below MUST level v1 declines, or a MUST the port cannot
  satisfy under its own rules. Its three existing subsections plus *Behavioural asymmetries a consumer
  must know*, which is where `R6`'s and `R7`'s declines land. **The release notes MUST state every
  item in this section**, which is what makes it a real disposition rather than a place to put things.
- **Post-release triggers** — an event no v1 phase can produce. Phase 10 may add one and may **close**
  one: `R9` closes the `XCUT-12` trigger by doing the work, which is a disposition earlier phases
  could not reach.

**"No repair needed" needs evidence, and the evidence is named.** Bullet 6 is the worked example in
both directions. As filed it says the map is uncapped and `gates:bounded_map` stays red; amended the
same day, it says 8c's plan Task 8 now bounds the map at planning time, "so this entry is expected to
be moot when `8c` lands and phase 10 to find nothing to repair" — **and it stays on the list "until a
green `gates:bounded_map` run says so."** That is the shape: a green gate run, a passing assertion, or
a source read quoted in the row. A sentence in a plan saying the work is done is not evidence that it
was done, which is the whole reason phase 10's method is a re-derivation.

**And a waiver that no longer states the truth is a finding.** If `TRANSPORT-14`'s waiver is still
listed but 8c's measurement no longer holds — say `protocol-http1` has since changed — the repair is to
remove the waiver, not to keep it because it is committed. Task 3 re-measures the two waivers the
first-party build carries; that is two measurements, and they are the ones a reader of a green run is
entitled to have been made.

---

## `R5` — the frozen-chapter amendment set, and why phase 10 cannot apply it

**Decision: phase 10 writes the amendment set — each frozen sentence quoted, each replacement written
out, each with its measurement and its code half verified present in as-built source — into
`docs/deviations.md`, and files one `docs/first-release.md` blocker requiring a human to apply the set
before the tag. Phase 10 does not edit §3, §4, §8, §9, §10, §11, §12 or appendix C.** `P10-5`.

This is the largest single piece of phase 10's work and the one where the temptation to overstep is
strongest, so the constraint is stated first. `docs/README.md`'s "Frozen means frozen" and CLAUDE.md's
ownership table both make `docs/sdk-design-ruby/` and `docs/product-spec/` a human's, deliberately;
`docs/deviations.md` says each holding-area note "is folded into
`docs/sdk-design-ruby/10-…md` the next time §10 is deliberately amended by a human", and calls itself
"a holding area, not a permanent second ledger". **Phase 10 is not that human.** What it can do —
and what nothing else in the roadmap does — is make the amendment a **transcription** rather than a
re-derivation: thirteen numbered amendments, each stating the file, the sentence, the replacement and
the evidence, so applying the set is an editorial act and not a fresh investigation two years later.

The set, as Task 17 will write it. Every one already has an interim note or an inbound bullet; what
phase 10 adds is the replacement text and the verification that the code half landed.

| # | Chapter and sentence | The correction | Code half, verified in Task 17 step 1 |
|---|---|---|---|
| C1 | §3.1's decode recipe — `String#encode(invalid: :replace, undef: :replace)` applied to BINARY ingress | Retag to the declared charset first, then transcode with **both** encodings named | 3b's `Response#body_string`; `notes/io-and-byte-streams.md` overrides `io-and-byte-streams/fbcb4d19` |
| C2 | §4's builder sentence — six models plus `Configuration` | Name the **multipart body**, which `HTTP-3`'s canonical text lists and §4 drops | 3b's `MultipartBody#new_builder` and `::Builder`, its plan Task 7 |
| C3 | §3.1's ownership sentence and §10.12 — ownership-on-wrap attributed to **`SEAM-3`** | Cite **`IO-6`** rather than, or alongside, `SEAM-3`; appendix C is `IO-6`'s only normative statement | 3a reads `IO-6` out of appendix C and implements ownership-on-wrap; `notes/message-bodies.md` marks `message-bodies/8a1e7a7b` |
| C4 | §8.1's event surface — `#tag(key, value)` | Either name the requirement `#tag` serves and its precedence against `OBS-5`'s three sources, or the line goes | 5b ships four methods and not `#tag`, `P5-18` |
| C5 | §3.2's block-scoped `read_body` "satisfied literally" | Name a construction that works | 8a's per-response producer `Thread` over a `Thread::SizedQueue(1)`, `P8-1`; the fiber alternative disqualified by `FiberError: fiber called across threads` |
| C6 | §3.2, §11.18 and §12's `TRANSPORT` row + MUST-level count — `Net::HTTP` "retries nothing on its own" | `#max_retries` **defaults to 1**; stop recording `TRANSPORT-2` as vacuous for this adapter | 8a's `http.max_retries = 0` |
| C7 | §12's `TRANSPORT` row, two directions in one amendment | `TRANSPORT-14` joins the adapter-scoped list (unreachable on `async-http`); `TRANSPORT-8` is recorded **satisfied** on the async adapter and leaves the eight-vacuous-MUSTs count | 8c's `P8-38` and its named waiver; 8c's `Async::Cancel`/`Async::TimeoutError` class discrimination |
| C8 | §8.3's prohibition, stated as binding "every gem in this repository" | One clause scoping it to code this repository writes, **plus** the measured statement of what the two dependency closures do — `net-http`'s connect-phase `Timeout.timeout` (present on all four rows), and `async-http`'s closure: no `Timeout.timeout`, seven `Fiber#raise` sites at scheduler checkpoints, one `Thread#kill` on an unreachable helper thread (Fact 4) | None owed — the cop and the ban stand |
| C9 | §9.3 — Minitest "ships with the interpreter as a default gem" | Minitest is a **bundled** gem; the conclusion survives unchanged | phase 0's root `Gemfile` line and its `~> 5.25` pin |
| C10 | §9.3's waiver sentence — the **report's** unit left unstated | One clause naming the requirement ID as the unit of both the waiver and the report; `P9-8` is the correct statement | phase 9's `Report`, one `Result` per assertion, assertions keyed by ID |
| C11 | **Appendix C and the chapters diverge, in both directions, and neither says so.** Two measured instances: appendix C's `SSE-19` row drops the port sanction `docs/product-spec/13-…md:33` grants ("a port MAY add a configurable cap … documenting the divergence"), and `docs/product-spec/15-…md:54`'s `OBS-29` sentence drops the follow-up clause appendix C's row carries ("pipeline/transport wiring to emit it is a follow-up, so it is not yet runtime-enforced") while carrying a `*Conformance:*` clause appendix C drops | For each pair, **the two rows together are the only complete statement of the requirement**, and the amendment is that each row either carries the other's clause or says it is partial. **This is the only amendment against the normative specification**, so it is also a recommendation to the specification author, in §11's own idiom — and it is one amendment rather than two because the general defect, not either row, is what a reader needs told: `CLAUDE.md` calls appendix C "the fastest way to locate a requirement ID", and a checklist author who stops there gets a requirement that reads complete and is not | 7b ships `SSE-19`'s configurable cap (`P7-21` rests on the appendix-C half); 5c and 6a satisfy `OBS-29` as documented, and `R6` is the decision the missing clause had been blocking |
| C12 | **§10.5's mitigation sentence** — `Completer#on_cancel` lets "**an adapter**" shorten the abort by closing the socket under the read | Name the **transport**: of phase 8's three adapters only a transport owns a socket, so the sentence is true of two of the three and false of the third | 8b's pool posts an *opaque* block and `dexpace-async-thread` owns no socket; 8a's and 8c's `on_cancel` close sites. The existing 2026-09-12 note in the holding area, established by 8b's design |
| C13 | **§12's `PAGE` row** — its vacuity count is one lower than a conformance report's will be | Add one clause naming `PAGE-15`'s wrapping clause and citing `7c P7-1`, so a reader counting §12's vacuous entries against a report's vacuous section does not find them off by one in the `PAGE` prefix | 7c's `P7-1`; the existing 2026-09-12 completeness note in the holding area, established by phase 9's design |

**Two things this table is not.** It is not a second ledger — `docs/deviations.md`'s holding area
already exists for exactly this and already carries **eleven of the thirteen**; what phase 10 does is
write the two it does not carry, add the replacement text to all thirteen, and give the whole set one
closing condition. **That arithmetic was wrong in this design's first draft**, which said "nine of the
eleven" by counting the holding area's nine notes as if all nine were members of the set: seven of them
are (`C1`, `C3`–`C7`, `C10`), two are the 2026-09-12 attribution and completeness notes that the set had
simply left out, and two members — `C2` and `C9` — had no note at all. Naming them `C12` and `C13`
is what gives those two a closing condition, which a recorded correction with no line in the blocker
does not have. And it is not a
licence to amend: **C11 is against a frozen *normative* chapter**, which is a stronger constraint
still, and phase 10's disposition for it is a recommendation plus a release note, never an edit.

**The blocker phase 10 files.** `docs/first-release.md` § Blockers before first publish gains: *the
thirteen recorded corrections to `docs/sdk-design-ruby/` §3, §4, §8, §9, §10, §11, §12 and to appendix
C's `SSE-19` row applied, or the release notes stating which design sentences a reader should not
trust.* The alternative form matters — a release can ship with the sentences unamended if it says so,
and cannot ship with them unamended and unmentioned, which is the only outcome the holding area
exists to prevent.

---

## `R6` — `OBS-29`: the requirement's own last sentence closes the surface decision

**Decision: no new pipeline step, no `RequestOptions` widening, and no surface decision is owed.
`OBS-29`'s canonical text makes the wiring a documented follow-up, explicitly and in its own words, so
the port satisfies it with 5c's documented emission contract and 6a's per-attempt group. What phase 10
ships is the cross-reference that makes the two tracer factories two, and a
*Behavioural asymmetries* entry recording that no wired emitter exists in v1.** `P10-6`.

Inbound bullet 2 is the largest on the list and frames `OBS-29` as **one open surface decision** — "a
`PRE_REDIRECT`-adjacent step and/or a deliberate `RequestOptions` widening" — assembled from three
findings measured by phases 5b, 5c, 6a and 8a. Every one of the three findings is correct. The framing
is not, and the proof is one sentence of appendix C nobody quoted:

> **OBS-29** (MUST) … One tracer instance corresponds 1:1 to a single logical operation lifecycle
> (created by the factory per operation). **This is a documented emission contract; pipeline/transport
> wiring to emit it is a follow-up, so it is not yet runtime-enforced.**
> (`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md`, `OBS-29`)

The requirement conditions its own enforcement. `OBS-29` obliges the SDK to **document** the ordering
contract; it says in as many words that wiring the emission is a follow-up and is not runtime-enforced.
5c ships the eleven-method vocabulary, `NULL`, `CallableAdapter` and an ordering test; 6a emits the
per-attempt group through `http_tracer_factory:` called with `cursor` (`P6-7`). **That satisfies the
MUST as written**, and the two residual halves are not requirement gaps at all — they are the
follow-up the requirement names.

This is what `R2`'s method is for, and it is worth saying exactly what went wrong, because the shape
will recur and because the mechanism turned out to be sharper than "nobody re-read appendix C".
**Chapter 15 does not carry the follow-up clause either.**
`docs/product-spec/15-instrumentation-and-observability.md:54` ends at "One tracer instance corresponds
1:1 to a single logical operation" — no parenthetical, no follow-up clause — and it carries a
`*Conformance:*` clause ("drive a succeeding and a failing (retry-exhausted) operation through a
conformant emitter and assert the ordering and the exhausted→failed pairing") that **appendix C drops**.
So the divergence runs both ways in the same pair, and **the two rows together are the only complete
statement of `OBS-29`, with neither saying so.** Design §8.1 restates the chapter, the corpus's harvested
rule `observability/2da9e2f3` is derived from the chapter and is exact about its source, and five
documents across four phases reasoned from one or the other. Nobody was careless; the requirement is
split across two files and each half reads complete.

That is the same defect as appendix C's `SSE-19` row dropping the port sanction the chapter grants
(bullet 25, amendment C11), in the opposite direction — and **two instances make it a pattern**, which is
why C11 is written to cover both rather than as a one-row erratum. Phase 10 files its one knowledge note
here because the corpus could not have held the clause: a harvested entry cannot carry what its source
does not say.

**What is genuinely owed, and is not a surface decision.** The third finding stands entirely: *"per-operation
tracer factory" names two different objects, and the bundle's member is bound to the one that is
per-library.* The proof needs nothing outside this repository's normative text and phase 10 re-ran it:
`OBS-25` (MUST) requires "a no-op HTTP-tracer / tracer-factory" and that "Selecting a no-op path MUST
NOT allocate per call", so the no-op factory must return the same object every time — the opposite of
one instance per operation; and phase 4a's `P4-8` bound `Bundle#tracer_factory` to
`opentelemetry-api`'s `TracerProvider` shape, keyed by instrumentation-library name and version. **The
filed arity is the five-parameter one**, `def tracer(deprecated_name = nil, deprecated_version = nil,
name: nil, version: nil, attributes: nil)` (4a's plan `:188`, `:1418`, `sig/` at `:1455`) — 4a's design
rendered it `#tracer(name = nil, version = nil)` and its plan superseded that, which matters here
because Task 16 writes YARD on the method and a YARD block over the wrong arity is the defect this
phase exists to catch. So there are two factories: `CTX-14`'s, on the correlation
bundle, producing **span** tracers (`OBS-21`–`OBS-25`), legitimately shared and cached; and `OBS-29`'s,
producing **HTTP-tracers** (`OBS-28`'s eleven-method vocabulary), legitimately per operation. Appendix
C, design §8.1, 5c's Tasks 3–5 and 4a's `R3` all read them as one object, and 5c's `P5-43` reconciles
only the no-op case.

**Phase 10's repair is documentation and signature, not surface.** Task 16 states the distinction in
three places a reader will meet it — the YARD on `Bundle#tracer_factory`, the YARD on
`Instrumentation::HTTPTracer`, and a knowledge note under `docs/knowledge/notes/observability.md` —
and changes no public signature. There is no code to write because there is no object to add: both
factories already exist and both are already correct for their own requirement.

**What is declined, and where it is recorded.** A step at `Stages::PRE_REDIRECT` emitting the
operation-lifecycle triple, and a `RequestOptions` widening carrying an HTTP-tracer to the adapter.
Both are declined, for the reason 6a's `R15` and 8a's `P8-7` already gave and which the canonical text
now confirms: no requirement obliges either in v1, `OBS-28`'s "Every event method SHOULD default to a
no-op" makes an unwired group conforming, and `NFR-4` would lock a public keyword with no caller —
which is precisely the argument that kept `#tag` out of the event surface (amendment C4). The
consequence a consumer would meet goes to `docs/first-release.md` § What v1 ships without ›
*Behavioural asymmetries a consumer must know*: **the HTTP-tracer vocabulary's operation-lifecycle
triple and transport-milestone group have no wired emitter in v1**; the per-attempt group is emitted,
the rest is a contract an SDK author drives, and `OBS-29`'s own text is why that is conforming.

---

## `R7` — `CTX-16`: conforming without wiring, and where the gap belongs

**Decision: no `Cursor#operation_name` and no `operation_name:` keyword. `CTX-16`'s modal clauses are
satisfied by phase 4a without a call path, and the purpose-fit gap belongs to the worked end-to-end
example `docs/first-release.md` already blocks the release on.** `P10-7`.

Inbound bullet 23 measures something real: **no phase in the roadmap builds a call path that creates
or promotes an execution context.** Verified 2026-09-13 by repository-wide grep over
`docs/work/mvp/`, and phase 10 re-ran it: outside phase 4a's own documents, `DispatchContext`,
`promote_to_request` and `promote_to_exchange` appear in no phase plan at all. 5b's
`Instrumentation::Step` probes `request.respond_to?(:context)` and `Dexpace::Request`'s members are
`(:method, :url, :headers, :body)`, so it always takes its fallback. 6a's Task 8 seeds a `Cursor#bundle`
and a `Bundle` carries no operation name.

The bullet then says the decision is unowned: carry the name on the call path, or document driving the
chain as the SDK author's job. Read against appendix C, the first option is a widening no requirement
asks for:

> **CTX-16** (SHOULD) … When present it **MUST** be carried forward unchanged across every promotion.
> The operation name **MUST** be advisory only — it is exposed to the tracing seam to label the
> operation and **MUST NOT** influence the request, the dispatch decision, or the store key.

Three modal clauses, and phase 4a meets all three: the context carries the name, the name survives
every promotion unchanged, and it influences nothing. "It is exposed to the tracing seam to label the
operation" is **descriptive, not modal** — and §11.11's own rule for a SHOULD with embedded MUSTs
applies exactly: "where the port ships the feature it implements every embedded MUST". The port ships
the feature. `SEAM-28`, the ID that would oblige a carrier, is a **MAY** and is deferred in §12.

So the choice is between a `Pipeline#call` keyword with no caller in v1 and a documentation
obligation. Phase 10 takes the second, on the `#tag` precedent: adding a public keyword that nothing
drives `NFR-4`-locks a surface whose shape has never been validated against a real consumer, and
`api-design/1d9e6e0b` makes it cheap to add **later** precisely because adding widens. The
documentation obligation already has an artifact and a blocker:
`docs/first-release.md` requires "one worked end-to-end example" in `docs/sdk-documentation/` —
"operation descriptor, request assembly, pipeline with an AUTH step, decode, typed error, one
paginated call" — and that is the one place a reader learns what a generated client has to drive
itself. Phase 10 adds the correlation chain to that line's enumeration: the example must show
constructing a `DispatchContext`, promoting it, and where the operation name goes, so the chain is
documented at the only point a consumer meets it.

**Recorded consequence, so it is not read as an oversight.** `ContextStore`'s cap, `CTX-19`'s
reachability and `CTX-9`'s eviction are exercised only by phase 4a's tests in v1. That is stated on
phase 10's `CTX-16` cross-reference row and in the *Behavioural asymmetries* entry `R6` opens, which
covers the same ground from the tracing side.

---

## `R8` — the single-use latch gets one error family, in core

**Decision: `Dexpace::SingleUseError` in `dexpace-core`, raised by `7c`'s `Pages#each` on
re-iteration, with `Dexpace::SSE::StreamStateError` re-parented beneath it so 7b's public constant,
its YARD and its `sig/` survive unchanged.** `P10-8`.

Inbound bullet 24: `PAGE-14` and `SSE-26`/`SSE-40` guard the identical latch with two error families.
`7c` raises `Dexpace::InvalidArgumentError`, which is `< ::ArgumentError`
(`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md:313`); `7b` ships
`Dexpace::SSE::StreamStateError < ::StandardError`. Neither requirement names a type — `PAGE-14` says
only "re-iteration MUST fail rather than silently restart", `SSE-26` says "a second attempt MUST fail
loudly (e.g. an **illegal-state error**)".

Fact 5 measures what the divergence costs: a caller's `rescue ArgumentError` around a page loop
catches the re-iteration failure on every supported Ruby, and a caller cannot write one `rescue` for
both subsystems. The defect is not that two names exist; it is that one of them puts a **state**
violation in the **argument** family, where an unrelated clause swallows it.

Three spellings were considered.

*`7c` raises `Dexpace::SSE::StreamStateError`.* Rejected: pagination raising an `SSE::`-namespaced
error is a worse defect than the one it fixes.

*Rename `StreamStateError` to a core `Dexpace::StateError` and have both use it.* Rejected as a
**narrowing** in the `NFR-4` sense — a public constant disappears — and because "state error" is broad
enough to attract every future misuse, which `SEAM-29`'s one-type-one-message-form discipline argues
against.

*A new core type, with 7b's constant kept as a subclass.* Taken. `Dexpace::SingleUseError <
::StandardError`, `include Dexpace::Error`, sits beside `ClosedError` and `StreamError` in
`dexpace-core`; `Dexpace::SSE::StreamStateError < Dexpace::SingleUseError` keeps 7b's name, its
`sig/`, its YARD and every one of its tests, and `7c`'s `Pages#each` raises `SingleUseError`. Adding a
class between `StreamStateError` and `StandardError` is not a narrowing: every existing
`rescue StreamStateError` and `rescue StandardError` still catches. A caller gets one clause for both
subsystems, and `PAGE-14`'s failure leaves the argument family. The name is deliberately narrower than
"state error" because it names the one situation both requirements describe — a view whose iterator
was taken twice.

Cheap only before the tag, which is why it is phase 10's and not a post-release trigger: after
`NFR-4`'s baseline records two families, changing either is a break.

---

## `R9` — `XCUT-12`: the fiber form is reachable, so phase 10 ships it

**Decision: phase 10 judges the thread-only form insufficient and ships the fiber-scheduler
single-flight assertion, as a driver in `gems/dexpace-transport-async_http/test/`. The
`docs/first-release.md` post-release trigger closes.** `P10-9`.

Phase 9 postponed this and named phase 10 as the primary owner in as many words: "**Phase 10**, if its
audit of `XCUT-12` finds the thread-only form insufficient — a judgement phase 10 is entitled to make
and phase 9 is not."

**The judgement.** Insufficient, and the reason is one of CLAUDE.md's constraints that will bite:
`Thread::Mutex` ownership in Ruby is **per-fiber, not per-thread, and non-reentrant**, so a lock held
across a suspension point deadlocks two fibers of one thread — and a thread-only race cannot see it.
`XCUT-12`'s subject is a credential cache whose refresh is single-flight; a single-flight guard is
exactly a lock held across a fetch, which is exactly a suspension point under a reactor. The
thread-only assertion is therefore blind to the one failure mode the requirement's mechanism creates.
`8b` reached the same conclusion for `XCUT-11` and handed the shape forward; phase 9 adopted it there
and could not for `XCUT-12`.

**Why phase 9 could not and phase 10 can.** Phase 9's blocker was composition, not difficulty:
`dexpace-conformance` declares `dexpace-core` and nothing else, so it cannot open a reactor, and
phase 9's `R6` file list stopped at the conformance gem plus the gates. Neither constraint binds phase
10, and the route is already built — the suite contract's **clause 9 `around:` wrapper**, into which
an async driver passes `->(&blk) { Sync { blk.call } }`, and **8a's own precedent of a driver file
inside the adapter gem**. So the work is: one driver in `dexpace-transport-async_http`'s `test/` tree
that runs `InvariantSuite`'s `XCUT-12` assertions with that `around:`, driving `6c`'s bearer cache.
No new gem dependency, no change to `dexpace-conformance`, and `NFR-2`'s budget untouched — the driver
lives in a gem that already declares `async-http`.

**What closes.** `docs/first-release.md` § Post-release triggers' `XCUT-12` entry, whose own text says
"This trigger is what fires if phase 10 leaves that judgement open". Phase 10 does not leave it open,
so the entry is removed and its history recorded in the phase's status note rather than left armed
against an event that no longer means anything. `XCUT-12` is a SHOULD, so nothing was blocked by its
absence; what is gained is that the SHOULD is now asserted under the scheduler its mechanism is
hazardous on.

---

## `R10` — the claim check: what a naive rule measures, and what a clause-scoped one does

**Decision: phase 10 builds the check, clause-scoped with a negation vocabulary, and it gates — because
measured on the live tree it fires 3 times with 3 true positives and 0 false positives. Its two blind
spots are written into the check's own stated gap, in the shape phase 9 gave its three AST gates.**
`P10-10`.

Inbound bullet 3 asks for "a claim grammar ('read out of X', 'stated in X', an `X §N` adjacency), a
vocabulary for ranges and placeholders, and an appendix-C special case, tuned against those roughly
forty live candidates before it is allowed to gate anything." Phase 10 tuned it against the live
candidates, and the first thing the measurement says is that **the claim grammar is the wrong axis**.

Fact 6 has the numbers. **38 lines** under `docs/` name both a `docs/product-spec/` chapter and a
canonical ID; a claim-verb grammar matches **0 of the 38**, because the shape these claims actually
take is a governing-documents list — "`A.md` for `X`, `Y`; `B.md` for `Z`" — with no verb at all. What
makes a naive rule wrong is not that it misreads a verb; it is that it pairs **every** ID on a line
with **every** chapter on it. So the axis is **clause scoping**: split at `;`, associate each ID with
the nearest preceding chapter reference, and the 14-line / 23-pair naive fire set collapses to 3, all
three of them real.

**The three, which are the same bug class as the three gap pointers the register retirement
corrected.** `SEAM-13`'s only prose home is `docs/product-spec/02-architectural-principles.md`, and
`SEAM-15`, `SEAM-20`, `SEAM-22`, `SEAM-23` and `SEAM-28` appear in **no** prose chapter at all —
appendix C is their only normative statement, which phase 2 established on 2026-09-06, re-verified on
2026-09-07, and phase 10 re-verified today. Against that:

- `docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md:67`
  names `docs/product-spec/03-pluggable-seams-and-extension-model.md` "for `SEAM-11`–`SEAM-15`,
  `SEAM-22`, `SEAM-29`" — and that chapter carries **neither `SEAM-13` nor `SEAM-15` nor `SEAM-22`**.
  `SEAM-29` is fine; it is in both `02-` and `03-`.
- `docs/work/mvp/phase8/phase8c/2026-09-11-phase8c-asynchronous-transport-design.md:69-70` names the
  same chapter for `SEAM-11`, `SEAM-13`, `SEAM-14`, `SEAM-15`, `SEAM-16`, `SEAM-17`, `SEAM-24`,
  `SEAM-25`, `SEAM-30` — and it carries **neither `SEAM-13` nor `SEAM-15`**. The other seven check out.

Both are in phase documents, which phase 10 may write, so per CLAUDE.md they are **fixed, not filed** —
and the fixing is in this pass, not deferred to execution, because a governing-documents list that
sends an implementer to the wrong chapter is exactly what the check exists to stop.

**The check's two stated gaps, measured rather than guessed.** A clause continued onto the following
line is invisible — which is why 8c's `SEAM-15`, on line 70 with its chapter on line 69, is caught by
hand above and not by the check. And a **backticked range** (`` `SEAM-11`–`SEAM-15` ``) does not match
a range pattern written for unbackticked text, which is what hides 8a's `SEAM-13`. Task 7 closes the
second (a range vocabulary that tolerates the backticks, which raises the catch to 5 of the 5 known
true positives) and writes the first into the check's own gap, because closing it needs a
sentence-spanning parser and the check's precision does not justify one.

**Why it gates.** Phase 9's rule for a new check is the right one — a second line weaker than the
first is a maintenance cost carrying no evidence, and `gates:drain_loop` was dropped on it. This check
is not that: it is the only line on its invariant, and at 0 false positives over 38 live candidates it
costs nothing to leave blocking. It is a **probe check** rather than a Rake gate, because its subject
is `docs/`: it joins the probe's eight checks as a ninth, `claims`-adjacent and named for what it does.

---

## `R11` — release readiness: what phase 10 owns of `docs/first-release.md`

**Decision: phase 10 walks all thirteen blockers, the four *what v1 ships without* subsections, the
release path and the seven post-release triggers, and records for each one of four dispositions —
closed by this phase, narrowed by this phase, still open with the reason, or outside the repository.
It closes three, narrows two, adds one blocker and two *ships-without* entries, adds one trigger,
closes one trigger, corrects the measurement in a second, and defines no release process.** `P10-11`.

The roadmap's phase-10 row says "Release Readiness", and the temptation is to invent a release. Phase
10 does not: `docs/first-release.md`'s own § Release path reads "Not yet defined", its two recorded
items are conditioned on RubyGems ownership and trusted publishing — both outside this repository —
and `NFR-16`'s signing is "enforced on the release path only once that path exists". **Nothing is
published, no tag is cut, and every gem stays at `0.0.0`.** Phase 10's business is the readiness, and
the readiness is a walk with a verdict per line.

**What phase 10 closes.**

- *"An RBS sig-diff baseline established, so a later release can be checked against it."* Phase 10 is
  the last phase to touch `sig/` in every gem — Task 5's headers reach all of them — so it is the phase
  that can establish the baseline over a tree nothing else will change. It regenerates **both**
  baselines, because phase 9's own closing task proves one is not enough: the `sig/**/*.rbs` diff and
  the runtime surface manifest catch different things, and `Data.define`'s generated readers are
  invisible to the first.
- *`gates:bounded_map` green.* Task 4 either verifies 8c's cap landed or ships it. Either way the
  line closes on a green run, which is what its own amendment says it waits for.
- The `XCUT-12` post-release trigger, by `R9`.

**What phase 10 narrows.**

- The conformance-run caveat blocker — "`docs/sdk-documentation/` must state what a green
  `dexpace-conformance` run does and does not prove" — gains two items phase 10 measures rather than
  assumes: the waivers the first-party build actually carries after Task 3's re-measurement, and
  `APPENDIX_B.md`'s `by reference` residue, which is **the majority of the map's 61 rows** and is the
  largest single thing a green run does not prove.
- The worked-end-to-end-example blocker gains the correlation chain, per `R7`.

**What stays open, with the reason.** RubyGems ownership and trusted publishing (outside the
repository); `SECURITY.md`'s contact (a human act); the `include Dexpace` constant shadow, the
`AuthDescriptor` carrier and the `HTTP-22`/`48`/`49`/`50` decision (all three release decisions whose
reopening event is the worked example, which no phase produces); signed publication and
`PackagingSuite`'s `NFR-12`/`NFR-16` (release-gated); the scaffolding and CI lines (phase 0's, ticked
when phase 0 runs). Phase 10 re-states none of these as its own and invents no process for any.

**What phase 10 adds.** One blocker (`R5`'s amendment set) and two *what v1 ships without* entries,
both under *Behavioural asymmetries a consumer must know*: `R6`'s unwired HTTP-tracer groups and
`R7`'s undriven correlation chain. Both are places where v1 **satisfies** its requirements and a
consumer would still be surprised, which is exactly what that subsection was opened for.

**And one thing phase 10 refuses to do.** It does not mark `NFR-4` ✅. `api-design/46c8b5fc` is
`NFR-4` verbatim and the requirement's subject is a diff against the previous release tag; there is no
previous release tag. Phase 10 establishes the baseline and leaves the disposition ⏳, citing phase 9's
row and `P0-8`'s pre-release branch. Establishing a baseline is not satisfying a requirement about
comparing against one.

---

## The inbound list, all thirty-two bullets dispositioned

The roadmap's twenty-four, plus eight this design adds to the list dated 2026-09-13 under the list's
own growth rule. **Repair** means a numbered task ships code or a check; **amendment** means `R5`'s
set; **fixed now** means it was in writable material and this pass fixed it; **audit** means a row
with no change owed; **register** means a `docs/first-release.md` or `docs/deviations.md` entry.

| # | Bullet | Disposition | Task |
|---|---|---|---|
| 1 | The audit of the §10.5 ledger — `ASYNC-3`, `PIPE-33` unsatisfied, `ASYNC-4` vacuous, `CFG-20`'s clause the same gap under a second ID, the trade not re-opened | **audit** — §10.5 re-derived from 8b's and 8c's as-built cancellation paths and phase 9's `waived (would fail): ASYNC-3`; `docs/deviations.md` row 5 gets its verdict. The §10.5 attribution note (naming the **transport**, not "an adapter") is amendment-set adjacent and folded with C5 | 12, 17 |
| 2 | `OBS-29`'s surface decision — three findings and one decision | **decided, no surface** (`R6`). The canonical text's follow-up clause closes it; the two-factories cross-reference ships as YARD plus one knowledge note; the unwired groups become a *Behavioural asymmetries* entry | 16, 18 |
| 3 | The probe's "this ID is stated in chapter X" claim check, not built | **repair** (`R10`) — a ninth probe check, clause-scoped, gating; three true positives fixed | 7 |
| 4 | Whether the thread-only `XCUT-12` form suffices | **judged insufficient; repair** (`R9`) — the fiber driver ships in 8c's test tree; the post-release trigger closes | 9 |
| 5 | The repairs of every audit phase 9 reports `:failed` | **repair, routed** (`R3`) — Task 3's intake converts every `:failed`, blocking vacuity, waiver and gate offence into a task, a register entry or a no-repair row | 3 |
| 6 | `Clients#@by_origin` is an uncapped per-origin client cache — `XCUT-14` (MUST) | **verify, repair if red** — 8c's plan Task 8 bounds it at planning time; the row closes only on a green `gates:bounded_map`, per the bullet's own amendment | 4 |
| 7 | 8a's `Adapter#dispatch` unused rescue variable, and the general `parse_file` exposure | **first half already closed** by commit 152ec6a before phase 10 began — 8a's fence reads `rescue ::StandardError` at its plan `:5177` and that plan records the repair at `:6337-6339`; phase 10 ships no repair for it. **Second half is the repair**: `gates:sole_parse` asserts `AstScan.parse` is the only caller of `parse_file` in the repository, with the exemption scoped to that method's own body. Fact 1's interpreter measurement survives as the fixture that proves the `$VERBOSE` window | 6 |
| 8 | `NFR-13`'s SPDX gate cannot reach `sig/**/*.rbs` | **repair** — the header on every shipped `.rbs` plus `gates:spdx_rbs`; phase 9's presence assertion turns green (Fact 2) | 5 |
| 9 | The `PAGE-15`/`P7-1` and §10.5 attribution notes, plus the seven interim notes, to fold into design §10 | **amendment** (`R5`) — **eleven of the thirteen**: the seven interim notes are `C1`, `C3`–`C7` and `C10`, the §10.5 attribution note is **`C12`** and the `PAGE-15`/`P7-1` completeness note is **`C13`**. Phase 10 writes the two the holding area lacks (`C2`, `C9`) and files the blocker | 17 |
| 10 | Any `gates:bounded_map` that runs red | **repair; never an allowlist entry** — the same task as 6, with the adjudication rule stated | 4 |
| 11 | §3.1's decode recipe destroys every non-ASCII byte | **amendment C1** — code half 3b's, verified | 17 |
| 12 | §4's builder list drops the multipart body | **amendment C2** — code half 3b's Task 7, verified | 17 |
| 13 | §3.1's ownership sentence and §10.12 attribute `IO-6`'s rule to the retired `SEAM-3` | **amendment C3**, and `IO-6` is audited on its own row in Task 11 | 11, 17 |
| 14 | §8.1 names `Event#tag(key, value)` and no requirement does | **amendment C4** — and the precedent `R6` and `R7` both lean on | 17 |
| 15 | §3.2's block-scoped `read_body` cannot satisfy `SEAM-11`/`TRANSPORT-25` | **amendment C5** — code half 8a's `P8-1`, verified | 17 |
| 16 | `Net::HTTP` retries by default; §3.2, §11.18, §12 record that it does not | **amendment C6** — code half `http.max_retries = 0`, verified in as-built source | 17 |
| 17 | `TRANSPORT-14`'s malformed-name clause unreachable on `async-http` | **amendment C7** (first direction) — and Task 3 re-measures the waiver | 3, 17 |
| 18 | `TRANSPORT-8` is satisfiable on `async-http`; §12 counts it vacuous | **amendment C7** (second direction) | 17 |
| 19 | §8.3's prohibition is absolute; `net-http`'s connect phase uses `Timeout.timeout` | **amendment C8, widened** — Facts 3 and 4 add the per-row citation and the first measurement of `async-http`'s closure, which the bullet asks for and nothing had made | 17 |
| 20 | Phase 5a's exclusions table names `TRANSPORT-3`/`TRANSPORT-8` for proxy use and header-drop reporting | **fixed now** — the row names `TRANSPORT-30` and `TRANSPORT-13`, corrected in place and dated, in the shape 5b's was | — |
| 21 | §9.3 calls Minitest a default gem | **amendment C9**, and Fact 7 re-measures the versions the trigger records | 17, 18 |
| 22 | §9.3 leaves the report's unit unstated | **amendment C10** | 17 |
| 23 | `CTX-16`'s operation name never reaches the tracing seam | **decided, no surface** (`R7`) — conforming by the modal clauses; the gap joins the worked-example blocker and a *Behavioural asymmetries* entry | 16, 18 |
| 24 | `PAGE-14` and `SSE-26`/`SSE-40` guard one latch with two error families | **repair** (`R8`) — `Dexpace::SingleUseError` in core | 8 |
| **25** | **Appendix C's `SSE-19` row drops the port sanction `13-…md:33` carries** *(added 2026-09-13, phase 10's planning; handed forward by 7b)* | **amendment C11** — the only one against a normative chapter, so also a recommendation to the specification author | 17 |
| **26** | **Phase 2's four other declared-and-unwritten `sig/` files** *(added 2026-09-13; handed forward by 7a, which settled only `sig/dexpace/serde.rbs`'s `#media_type` clause)* | **repair** — Task 5 already reads every shipped `.rbs`; it also asserts none is empty of declarations and that every `interface _X` a phase document names is declared | 5 |
| **27** | **`Dexpace::Protocol.parse` has no `"http/1.0"` wire form, so a real `HTTP/1.0` response makes `ResponseMapper` raise** *(added 2026-09-13; handed forward by 8a, which calls it a phase-1 surface decision no sub-phase should take alone)* | **repair** — `Protocol::WIRE_FORMS` gains the alias; additive, so `NFR-4` permits it | 10 |
| **28** | **8a's forward-obligations row for `TRANSPORT-28`/`TRANSPORT-30` is half stale — `TRANSPORT-30` is implemented by 8a's own `R17`** *(added 2026-09-13)* | **fixed now** — the row names `TRANSPORT-28`'s zero-copy clause only, dated | — |
| **29** | **`APPENDIX_B.md`'s check 2 is weaker than its own prose** *(added 2026-09-13, found by reading phase 9's plan against phase 9's design)* | **repair** (`R3`) — the per-item ID accessor and the equality assertion | 3 |
| **30** | **`TransportSuite` is not on `Runner`, leaving two status-deciding paths in one gem (`P9-10`)** *(added 2026-09-13)* | **repair** (`R3`) — folded onto `Runner`, the five statuses asserted unchanged | 3 |
| **31** | **A design document that promised a shape the code did not take is phase 10's doc repair (phase 9's `R3`)** *(added 2026-09-13)* | **method, not a bullet** — `R2`'s third verdict hazard; each audit task routes its own | 11–15 |
| **32** | **The `minitest` pin's ownership: the root `Gemfile` is phase 0's artifact and `R6` makes the repair phase 10's (phase 9's open question 1)** *(added 2026-09-13)* | **audit plus a register correction** — Fact 7 re-measures; the pin stays phase 0's Task 2, and the `docs/first-release.md` trigger's per-row versions are corrected | 1, 18 |

**Counts.** Of the thirty-two: **12 become repairs** (bullets 3, 4, 5, 6, 7, 8, 10, 24, 26, 27, 29, 30
— twelve bullets, twelve task assignments, across **eight** tasks: 6 and 10 land in Task 4 together,
29 and 30 both in Task 3, and Task 3 also takes 5), **13
become amendments** in `R5`'s set (9, 11–19, 21, 22, 25 — thirteen bullets mapping to **thirteen**
numbered amendments, and the two counts coinciding is a coincidence: 17 and 18 share `C7`, while bullet 9
carries eleven of the thirteen on its own, including `C12` and `C13`), **2 are decided with no
surface** (2, 23), **3 are audit-only** (1, 31, 32), and **2 were fixed in this pass** (20, 28). The
arithmetic overlaps because several bullets carry more than one obligation; what has no overlap is
that **none of the thirty-two is carried forward unresolved.**

---

## The hand-forward obligations, each resolved

`grep -rn -i -e 'phase 10' -e 'phase-10' docs/work/` returns **280 hits in 30 documents** once phase
10's own two files are excluded — the number to quote, because including them the same command returns
539 in 33 and neither figure means anything about what earlier phases handed forward. (A first draft of
this sentence said 254, which reproduces under no convention; corrected 2026-09-13.) Most hits are the
generic finding-routing sentence every phase repeats, or a quotation of phase 10's roadmap row.
Stripped of those, **seventeen distinct subjects are handed forward by phases 0–8** and **fourteen by
phase 9**, counting a subject as one named obligation and splitting `R3`/`R6`'s routing policy into the
four distinct dispositions it actually directs here (`:failed`, a MUST-level un-accepted `:vacuous`, a
design document that promised a shape the code did not take, and a failure contradicting design §10 or
§12) — a stricter split that treats that policy as one subject gives eleven, which is why the rule is
stated rather than left to the reader. The two sets overlap heavily with the inbound list, which is the
point: the list was built from them.

**What the sweep added that the list did not have: four subjects from phases 0–8** — bullets 25, 26,
27 and 28 above — and **four more the sweep reached by way of phase 9, of which only two are phase 9's
own hand-forwards**: bullets **31** and **32** are, and bullets **29** and **30** are not. Those last two
are phase-10 findings *about* phase 9's documents rather than obligations phase 9 routed here — 29 came
from reading phase 9's plan against phase 9's design, and `P9-10` names phase 8 as the owner of
`TransportSuite` and phase 10 nowhere. The distinction is worth keeping because a hand-forward is a
decision someone made and a finding is one nobody did. Those eight are the reason
this design ran the sweep rather than trusting the list, and they are added to the list dated
2026-09-13.

**What the sweep confirmed the list already had, and the list states more fully:** the decode recipe
(3b, restated by 5b, the phase-7 charter, 7a, 7b, 7c, the phase-8 charter, 8a and 8c — nine documents
for one sentence), `Event#tag` (5b), `OBS-29`'s two halves (5b, 5c, the phase-6 charter, 6a, 7c, the
phase-8 charter, 8a, 8b, 8c), the two tracer factories (5c, the phase-6 charter, 6a, the phase-7
charter), the §10.5 ledger audit (the phase-8 charter, 8b), `Net::HTTP`'s default retry (the phase-8
charter, 8a, 8c), §3.2's `read_body` (the phase-8 charter, 8a), §8.3's dependency question (8a), phase
5a's substituted IDs (8a), `TRANSPORT-14` (8c), `TRANSPORT-8` (the phase-8 charter, 8c), `CTX-16`'s
unwired chain (4a), and the multipart builder (3b).

**Phases 0, 1, 4b, 4c, 5a and 6b hand phase 10 nothing by name.** Phase 5a is *named in* a
hand-forward — 8a's correction of its exclusions table, bullet 20 — but makes none itself.

**One structural observation, because it is the shape of this whole phase.** Thirteen of the
seventeen phase-0-to-8 hand-forwards have the identical form: **the rule is right, the mechanism
sentence is wrong about Ruby or about a library, the phase that found it shipped working code, and
what is owed is one sentence the next time a human amends a frozen chapter.** Four have the opposite
form — a decision with **no** code half — and those four are `OBS-29`'s wiring, the two tracer
factories, `CTX-16`'s carrier and `Protocol.parse`'s missing wire form. Those four are where phase 10
may ship code, and `R6`, `R7` and bullet 27 are what it decided to do with each. That the ratio is 13
to 4 is the strongest single argument that phase 10's dominant deliverable is a **transcription**
(`R5`) and not a build.

---

## Design §9 Addendum — gates this phase adds to §9's table

Design §9's gate table is frozen and is not edited by this phase. The four checks below are additions
it does not carry, recorded here as the roadmap's cross-cutting constraint 6 directs, each with a
Deviation Ledger row for consolidation into design §10. **The labels continue the repository's own
addendum series** — phase 9 added `A4`–`A7` — so phase 10's are `A8`–`A11`. That is a different series
from `R5`'s amendment set, whose thirteen items are labelled **`C1`–`C13`**: an `A`-label is a gate this
phase builds, a `C`-label is a frozen sentence a human corrects. The two were `A1`–`A11` in a first
draft of this document and collided at `A8`, `A9` and `A10`; the rename is recorded because a reader who
meets "amendment A8" in one section and "addendum A8" in another has no way to tell them apart.

| Addendum | What §9's table says | What phase 10 builds |
|---|---|---|
| **A8 — `gates:spdx_rbs`** | Nothing. `NFR-13` is mechanised as `Dexpace/SpdxHeader`, a RuboCop cop, and a cop parses Ruby | A Rake gate over `sig/**/*.rbs` in every gem, asserting `# SPDX-License-Identifier:` on line 1 — one line, not the two `lib/` carries, because `# frozen_string_literal: true` has no meaning in RBS (Fact 2). Blocking, in `DEFAULT_GATES` and the `gates` CI job. It also asserts **no shipped `.rbs` is empty of declarations**, which is bullet 26's residue and has no other home (`NFR-13`, `NFR-3`) |
| **A9 — `gates:sole_parse`** | Nothing. `tools/ast_scan.rb` carries "nothing else in this file may call `parse_file` directly" as a **comment**, and no gate asserts it | An AST scan of `tools/**/*.rb`, `tasks/**/*.rake`, `test/gates/**/*.rb` and `.claude/skills/**/*.rb` failing on any `parse_file` send outside `AstScan.parse`'s own method body. Named node types from the first line, both `:LIT` and `:SYM`, per `notes/cross-cutting-invariants.md`. Its stated gap is the same one phase 9 wrote down: `send(variable)` is statically undecidable (`NFR-6`, `NFR-17`) |
| **A10 — the probe's ninth check, `chapters`** | Nothing — the probe is not in §9's table at all, and `links` catches only an unresolvable chapter path | The clause-scoped chapter-attribution check of `R10`: 3 fires, 3 true positives, 0 false positives over 38 live candidates, with a backtick-tolerant range vocabulary and two stated blind spots. A probe check rather than a Rake gate because its subject is `docs/`; blocking in the sense the probe is, which is that exit 1 means drift |
| **A11 — `gates:ledger_audit`** | Nothing. §10's nineteen entries are audited by `docs/deviations.md`, and no row checks that the register still describes the chapter | Three decidable assertions over `docs/deviations.md`: row *n* carries §10 entry *n*'s subject as a word subsequence; row *n*'s expanded ID set **equals** the ID set extracted from entry *n*'s text — the check that makes this phase's count of 124 reproducible instead of a number in a document; and a row carrying a verdict cites at least one `gems/…` path that exists and no `Dexpace::` constant that is undefined. **A row citing only `docs/…` fails**, which is `P10-2` made mechanical. Blocking, in `DEFAULT_GATES` and the `gates` CI job (`NFR-17`) |

**And one thing phase 10 deliberately does not add.** No new `dexpace-conformance` suite and no new
assertion. Phase 9's four suites and three gates are the instrument, and a phase that both reads an
instrument and extends it cannot say which of the two its verdict came from.

---

## Module layout

Phase 10 adds **one** new public `Dexpace::` constant — `Dexpace::SingleUseError` (`R8`) — widens the
contents of one that exists (`Protocol::WIRE_FORMS`), and adds **four** repository tools: three Rake gate
bodies under `tools/` and the probe's ninth check under `.claude/skills/housekeeping/`. Task 4 may add
`Clients::MAX_ORIGINS`, which is an adapter-internal constant and not part of the public surface
`NFR-4` locks. Everything else it touches already exists. (A first draft of this line said "three public
constants and two tools", which contradicted *Out of scope*'s own count of one.)

```
gems/dexpace-core/
  lib/dexpace/single_use_error.rb        Dexpace::SingleUseError        R8, PAGE-14 / SSE-26
  sig/dexpace/single_use_error.rbs
  lib/dexpace/protocol.rb   (modified)   Protocol::WIRE_FORMS gains "http/1.0"   bullet 27
  sig/dexpace/protocol.rbs  (modified)
  lib/dexpace.rb            (modified)   the require_relative for the new file

gems/dexpace-core/lib/dexpace/page/pages.rb        (modified)  raises SingleUseError
gems/dexpace-core/lib/dexpace/sse/stream_state_error.rb (modified)  < Dexpace::SingleUseError
gems/dexpace-core/lib/dexpace/instrumentation/*.rb (YARD only)      R6's two-factories cross-reference

gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/clients.rb (verify) bullets 6, 10
gems/dexpace-transport-async_http/test/dexpace/transport/async_http/xcut12_fiber_test.rb  R9

gems/dexpace-conformance/lib/dexpace/conformance/transport_suite.rb (modified)  bullet 30
gems/dexpace-conformance/test/appendix_b_map_test.rb                (modified)  bullet 29
gems/dexpace-conformance/lib/dexpace/conformance/appendix_b.rb      (modified)  the per-item ID accessor

every gem's sig/**/*.rbs                (modified)  the SPDX line

tools/ast_scan.rb           (modified)  its header comment's stale 8a citation only  Task 6 Step 5
tools/ledger_audit.rb                   the gate body for gates:ledger_audit  R2, addendum A11
tools/spdx_rbs.rb                       the gate body for gates:spdx_rbs      addendum A8
tools/sole_parse.rb                     the gate body for gates:sole_parse    addendum A9
tasks/gates.rake            (modified)  the three new gate tasks
Rakefile                    (modified)  the three names appended to DEFAULT_GATES
.github/workflows/ci.yml    (modified)  the three names in the gates job
test/gates/phase10_ruby_facts_test.rb   Task 1's re-verification of the seven facts, all four rows
test/gates/ledger_audit_test.rb, test/gates/spdx_rbs_test.rb, test/gates/sole_parse_test.rb
test/fixtures/gates/…                   one failing fixture per gate, plus a positive control

.claude/skills/housekeeping/chapters.rb  the ninth probe check
.claude/skills/housekeeping/probe.rb     (modified)  registers it
.claude/skills/housekeeping/test/chapters_test.rb
```

**Three notes on placement.** `Dexpace::SingleUseError` is a flat `Dexpace::` constant and therefore
falls under the `include Dexpace` constant-shadow hazard `docs/first-release.md` already blocks on —
but `SingleUseError` shadows no core class, so it adds nothing to that blocker; the check is worth
stating because the blocker's own text is about "every flat `Dexpace::` constant sharing a name with a
core class". The two gate bodies go in `tools/` beside phase 9's, not in `tasks/gates.rake`, for
phase 9's reason: a `.rake` file is `load`ed before `DEFAULT_GATES` exists. And the probe check is its
own file, `chapters.rb`, because `guard.rb`'s tested-guard precedent is one concern per file and the
check has four tunable vocabularies that want their own tests.

---

## Testing strategy

**Every repair is TDD, and the failing test is the audit.** This is the one place phase 10 differs
from a build phase: the test that must fail first is not a specification of new behaviour, it is the
**assertion of the claim the audit found false**. So Task 8's failing test is that `rescue ArgumentError`
around a second `Pages#each` catches — which it does today, measured — and Task 5's is that a shipped
`.rbs` has no SPDX line. A repair whose test could not have been written before the audit is a repair
that was not audited into existence.

**Each of the three new Rake gates ships a deliberately failing fixture and a positive control**, which
is what phase 0 required of its seventeen and phase 9 of its three. `gates:ledger_audit` ships three
fixtures rather than two, because its ID-set-equality assertion and its evidence assertion fail for
different reasons and a single fixture would prove only one of them. The probe check ships four: a true
positive, a correct-prose negation, a continued clause (the stated blind spot, asserted to *not* fire
and to be documented), and a backticked range (asserted to fire).

**Every Ruby fact is re-verified at implementation time on all four interpreters**, via
`mise exec ruby@<v> -- ruby`, and Task 1 is that re-verification. Facts 3, 4 and 7 are the ones most
likely to have moved: two are about a third-party gem's source and one is about the machine's gem
state, and Fact 7 has **already** moved once between phase 9's measurement and this one.

**The audit tasks' tests are `gates:ledger_audit`.** An audit produces a row, and a row is prose; what
makes it checkable is Task 2's gate, which asserts that each of `docs/deviations.md`'s nineteen rows
has the number and title of §10's entry at that position, that its ID list equals the IDs that entry
names, and that every evidence path and constant a confirmed row cites resolves. That is the same
per-row equality check `R3` adds to `APPENDIX_B.md`, applied to the register phase 10 owns — and it is
what stops the register drifting after phase 10 closes, which is the failure mode a register audited
once always has.

**`assert_predicate` is not used**, per every phase plan's Global Constraints: it sends past `private`
on the 3.2 floor. Every test runs alone in any order; mutable fixtures are built fresh.

---

## Deviation Ledger

Each row is consolidated into design §10 and audited by `docs/deviations.md`.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P10-1 | An audit step and a repair step are separate steps with separate exit conditions, and "no repair needed" requires evidence rather than an argument | `R1`; the roadmap's phase-10 row | The row grants a repair budget to an audit phase. Without the split, the phase's findings are filtered by whether the auditor felt like fixing them — which is the failure phase 9's `R6` avoided by having a later phase, and phase 10 has none |
| P10-2 | Every ledger claim is re-derived from the as-built artifact; the promising phase document tells the auditor where to look and is never evidence | `R2`; design §10, §11, §12; `docs/deviations.md` | The roadmap states the method in half a sentence. A row that moves because a design document says so has not been audited, and nineteen such rows would be a register that is true and useless at once |
| P10-3 | Phase 9's report is read **once**, in Task 3, and converted into an intake table; nothing later re-reads it | `R3`; phase 9's `Report`, the five statuses | Five statuses, two suppression mechanisms and four gate offence lists read differently by a repair phase than by an audit phase. Reading them twice is how two tasks reach opposite conclusions about one row |
| P10-4 | Phase 10 changes exactly two things in `dexpace-conformance` — `APPENDIX_B.md`'s check 2 and `TransportSuite` onto `Runner` — and adds no suite, assertion or gate there | `R3`; `P9-7`, `P9-10`; `NFR-17` | Both are residues phase 8's ownership caused and phase 10 is the first phase that owns every gem. Adding anything else would make phase 10's verdicts inseparable from its own instrument |
| P10-5 | The frozen-chapter corrections ship as a written **amendment set** in `docs/deviations.md` plus one release blocker, never as an edit to §3, §4, §8, §9, §10, §11, §12 or appendix C | `R5`; `docs/README.md`'s "Frozen means frozen" | Phase 10 is not the human those chapters are reserved for. What it can do is make the amendment a transcription — sentence, replacement, evidence, verified code half — so applying it is editorial rather than a fresh investigation |
| P10-6 | `OBS-29` needs no wiring: its canonical text makes the emission wiring a follow-up and "not yet runtime-enforced". The `PRE_REDIRECT` step and the `RequestOptions` widening are declined | `R6`; `OBS-29`, `OBS-28`, `CTX-14`, `CTX-20`, `OBS-25`, `NFR-4` | Five documents across four phases reasoned from design §8.1's restatement, which drops the clause. The requirement conditions its own enforcement, so the port satisfies it and the unwired groups are a consumer-facing asymmetry rather than a gap |
| P10-7 | `CTX-16` is satisfied without a call path; the purpose-fit gap joins the worked-example blocker instead of widening `Pipeline#call` | `R7`; `CTX-16`, `SEAM-28`, `PIPE-11`, `NFR-4` | All three of `CTX-16`'s modal clauses are met by phase 4a and "exposed to the tracing seam" is descriptive. A keyword with no caller `NFR-4`-locks an unvalidated surface — the `#tag` precedent, and `api-design/1d9e6e0b` makes adding it later cheap |
| P10-8 | One core error family for the single-use latch: `Dexpace::SingleUseError`, with `SSE::StreamStateError` re-parented beneath it | `R8`; `PAGE-14`, `SSE-26`, `SSE-40`, `SEAM-29`, `NFR-4` | `7c`'s `InvalidArgumentError < ::ArgumentError` puts a state violation in the argument family, where `rescue ArgumentError` swallows it on every supported Ruby. Re-parenting keeps 7b's constant, so nothing narrows |
| P10-9 | `XCUT-12`'s thread-only form is judged insufficient and the fiber form ships as a driver in `dexpace-transport-async_http`'s `test/` tree | `R9`; `XCUT-12`, `XCUT-11`, `AUTH-35`, `ASYNC-9`, `NFR-2` | `Thread::Mutex` is per-fiber, so a thread-only race cannot see a lock held across a suspension — the one failure mode a single-flight guard creates. Phase 9's blocker was composition, not difficulty, and it does not bind a phase that owns every gem |
| P10-10 | The chapter-attribution check is clause-scoped, not verb-scoped, and it gates | `R10`; the requirement-ID conventions; `NFR-17` | A claim-verb grammar matches 0 of 38 live candidates; clause scoping takes the naive 23-pair fire set to 3 fires with 0 false positives. Two blind spots are written into the check's own gap, as phase 9 did for its three |
| P10-11 | Phase 10 defines no release process and marks `NFR-4` ⏳ while establishing its baseline | `R11`; `NFR-4`, `NFR-16`, `NFR-12`; `docs/first-release.md` | The release path's conditions are outside this repository. Establishing a baseline is not satisfying a requirement about diffing against one, and marking it ✅ would be the kind of claim this phase exists to catch |

### As built, 2026-09-25

The rows above stand and nothing is renumbered. What execution changed takes the band from **`P10-21`**;
`P10-12`–`P10-20` are left free as a visible gap, the convention 4a/4b/4c and 5a/5b/5c used. Every row is
re-derived from the tree, and each names the evidence.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P10-21 | **`R9` is carried out as a verification, not a repair.** The deadlock premise is false: two fibers of one reactor blocking on one `Thread::Mutex` do not deadlock -- the second parks on the scheduler (measured on 3.3.12 and 4.0.6, async 2.46.0), and the real `Auth::BearerStamper` under `Sync` with eight fibers makes exactly one fetch. The fiber race ships as `gems/dexpace-transport-async_http/test/dexpace/transport/async_http/fiber_single_flight_test.rb` against the real `BearerStamper` and `AsyncBearerStamper`, discriminating a thread-identity single-flight guard (Guards run red, 19) | `XCUT-12`, `XCUT-11`, `AUTH-34`, `AUTH-35`, `AUTH-37`; `R9` | `R9` justified the driver by a hazard the tree disproves; a repair whose failing test passes on `main` is a verification (`P10-1`). What a thread-only race truly cannot see is a guard keyed by thread identity, and that is what the fiber race catches. Not through `InvariantSuite`'s `around:`: its `XCUT-12` assertion races sixteen THREADS it builds itself, so wrapping the run in `Sync` runs threads inside a reactor and proves nothing new |
| P10-22 | **`R8` is not carried out.** 7c already raises `Dexpace::Page::PageStateError < ::StandardError` (`page/page_state_error.rb:17`, raised at `page/pages.rb:96` and `page/walk.rb:94`), and `page_state_error_test.rb` refutes `ArgumentError` -- `R8`'s defect is absent. A shared supertype no requirement asks for is not a repair, and `SSE::StreamStateError` is also `SSE-27`'s closed-stream refusal, so `SingleUseError` would misname one of its two raise sites. `PAGE-14`, `SSE-26` and `SSE-40` are verification rows | `PAGE-14`, `SSE-26`, `SSE-40`; `R8`, `P10-8` | `P10-1` |
| P10-23 | Task 4 is a verification: `Transport::AsyncHTTP::MAX_ORIGINS` (32), `Clients#drain`'s loop under the insert's mutex, the eviction close and `#close`'s clear all shipped with 8c, pinned by `clients_test.rb`'s three `XCUT-14` cases; `gates:bounded_map` green. The allowlist reason for `clients.rb` now cites those three tests as its mechanism | `XCUT-14`, `TRANSPORT-13` | No defect; phase 9 closed the blocker on 2026-09-23 |
| P10-24 | Task 3 Step 4 was already done by phase 9 in files the plan does not name: `tools/appendix_b.rb` and `test/gates/appendix_b_test.rb`, whose "every row's ID column equals the set parsed from that item's own text" is set equality. No accessor, no fixture | `NFR-17`; bullet 29 | Verification row |
| P10-25 | `TransportSuite.run` folds onto `Runner` **without widening `Runner`**: the fresh `TransportCase` is built inside the invocation and the `around` handed to `Runner` tears it down in an `ensure` after the driver's own wrapper returns. One observable change: a `:failed` detail now carries `Runner`'s `(expected …, got …)` suffix; the two pins that spelled the old form moved with the change | `NFR-17`; `P9-10` | Five statuses decided in one place; phase 9's `R3` interface untouched |
| P10-26 | The three new gates join every path to `gate_root` (P9-27's lesson from the first line); `gates:ledger_audit` requires core and every adapter whose Ruby floor the interpreter meets before resolving a constant; `gates:spdx_rbs` reads the declarations as the third element of `RBS::Parser.parse_signature` (`.flatten.compact.empty?` is never true on rbs 4.2.0); `gates:sole_parse` is scoped to a `RubyVM::AbstractSyntaxTree` receiver (Prism's `parse_file` routes no diagnostic through `Warning.warn`) with three reasoned test-contrast entries in `SoleParse::ALLOWED`, each asserted still to report | `NFR-3`, `NFR-6`, `NFR-13`, `NFR-17`; addenda A8, A9, A11 | The plan's fences were CWD-relative, called three private or absent `AstScan` helpers, and would have reported six offences on a clean tree |
| P10-27 | **`HTTP-10` repaired, a MUST.** `Dexpace::Status` maps every code a status line can carry, 0..999, and the protocol's 100-599 range moved to `Status#standard?`. Phase 1 recorded the old guard as "the port's reading" in its plan and checklist and in no ledger row, so by the maintainer's rule it was a defect: a 600 or LinkedIn's 999 made both transports raise where `TRANSPORT-24` says to surface it. Two phase-1 pins and two phase-8 adaptation-failure tests changed with it (the latter now use an `HTTP/1.2` head) | `HTTP-10`, `HTTP-11`, `TRANSPORT-24`, `TRANSPORT-22` | Additive: `NFR-4` permits the widening; the manifest gains `Dexpace::Status#standard?` |
| P10-28 | `Protocol` gains `http/1.0` in BOTH `WIRE_FORMS` and `ALIASES`, and the constant `Protocol::HTTP_1_0`, under `HTTP-33` -- not `HTTP-24`/`HTTP-43`, which the plan named and which are `MediaType`'s charset lookup and `Response#close` | `HTTP-33`; bullet 27 | The manifest gains one row |
| P10-29 | `URL.parse!` refuses (i) an http-family URL with no host, (ii) a URI whose own `#to_s` mutates it -- `URI::FTP` with `;type=` -- and wraps (iii) every `URI::Error`, not only `InvalidURIError`, as `InvalidArgumentError` naming the input. Non-http schemes are still admitted: which schemes dispatch stays a transport's call (phase 1's reading) | `HTTP-47` | The rationale clause -- fail at construction rather than later -- was unmet for three shapes |
| P10-30 | `Model.own` drops a caller's Hash default proc from the model's copy and turns any other un-shareable value into `InvalidArgumentError` | `HTTP-5`, `XCUT-15` | A default proc is behaviour, not data; `Ractor.make_shareable(copy: true)` raised a raw TypeError |
| P10-31 | The `chapters` probe check exempts phase 10's own design, plan and checklist (they quote the pre-correction attributions on purpose) and spells its negation vocabulary as a `Regexp.union` of phrases, never an `/x` pattern -- under `/x` the phrases' spaces vanish, which the first live run showed as sixty false fires. Measured on the live tree: two fires, both true positives, in `phase8/2026-09-11-phase8-segmentation-design.md:60` (`SEAM-13` and `SEAM-15` inside a range attributed to chapter 03), fixed in place with a dated bracket | `SEAM-13`, `SEAM-15`; `R10`, addendum A10 | The design measured the population before phase 10's documents joined it |
| P10-32 | A retargeted vacuous requirement is marked **N/A** (`NFR-8`, `NFR-9`, `SEAM-10`), phase 9's convention; phase 0's checklist's `🚫 retargeted` stands as its own record and the departure is stated here | `NFR-8`, `NFR-9` | Two conventions for one disposition was a reader's trap |
| P10-33 | `docs/deviations.md` rides the **code** branch: `gates:ledger_audit` reads it at run time, and a gate's input lives where the gate runs | `NFR-17` | The layering rule |
| P10-34 | "Task 10b", the small-repairs task the maintainer added, took twenty-six items -- twenty test-first repairs (the checklist's repairs-table rows marked `10b`) and six comment, YARD or document corrections no test can observe -- and stopped there, at the decision's bound; every other inbound bullet or leftover it could have taken is a dated `docs/first-release.md` line | Scope | The decision's own bound (~25 items, one `lib/` file each) |
| P10-35 | `NFR-4` stays **✅**, phase 9's mark. `P10-11` and Task 18 Step 6 read the requirement as "a diff against the previous release tag"; appendix C's `NFR-4` is "captured in a checked-in, machine-comparable snapshot, and the build SHOULD fail on any drift", which `gates:surface_snapshot` over the six manifests does. The release-tag diff is design §9's mechanism, and its vacuity is stated in the row | `NFR-4`; `P10-11` superseded | Following `P10-11` would have overturned a correct row |
| P10-36 | The "RBS sig-diff baseline" line in `docs/first-release.md` stays **open**: `tools/sig_diff.rb` takes its baseline from `git describe --tags --match v*`, there is no committed baseline file, and this phase may not tag. The runtime manifests were regenerated once, deliberately | `NFR-4`; `R11` | Establishing a baseline without a tag is not possible in this repository's design |

---

## Work phase 10 postponed, and who owns it now

Phase 10 postpones **three** things. It is the last phase, so every one of the three names a
`docs/first-release.md` entry and none names a phase. The heading is phase 9's verbatim, and the shape
is the one CLAUDE.md sanctions: each row routes an obligation to its owner rather than registering it
here.

| Subject | What is postponed, and why | Where the obligation lives now |
|---|---|---|
| **Applying the thirteen amendments to §3, §4, §8, §9, §10, §11, §12 and appendix C's `SSE-19` row** (`R5`; every ID those sentences touch) | Five trees are frozen to every maintenance tool and reserved to a human acting deliberately, and phase 10 is a phase. Writing the set is the most phase 10 can do, and it is more than any earlier phase could: each amendment now carries the sentence, the replacement, the measurement and the verified code half, so applying it is editorial | **`docs/first-release.md` § Blockers before first publish**, the amendment-set line phase 10 files, whose alternative form is that the release notes name which design sentences a reader should not trust. Its content is `docs/deviations.md` § Deviations found outside a phase, completed to eleven |
| **The chapter-attribution check's continued-clause blind spot** (`R10`) | A clause whose chapter reference is on the preceding line is invisible to a line-oriented scanner, and 8c's `SEAM-15` is the live instance — caught by hand, not by the check. Closing it needs a sentence-spanning parser over Markdown, and at 3 fires with 0 false positives the check's precision does not justify one. The gap is written into the check's own output, so a reader is never told the check saw something it did not | **The check's stated gap**, and `docs/first-release.md` § Post-release triggers: **a second continued-clause true positive appears** → write the sentence-spanning form. One instance is an anecdote; two are a population |
| **An `NFR-4` diff, as opposed to an `NFR-4` baseline** (`NFR-4`, `NFR-16`, `NFR-12`) | `NFR-4`'s subject is a diff against the previous release tag and there is no tag. Phase 10 establishes both baselines — the `sig/**/*.rbs` tree and the runtime surface manifest — over a tree nothing else will change, and leaves the disposition ⏳ | **`docs/first-release.md` § Release path**, beside the signed-publication and `PackagingSuite` items, whose condition is the first `v*` tag and the first `gem push`. Phase 9's `NFR-4` row stands ⏳ and phase 10's cross-reference row cites it |

### What earlier phases postponed to phase 10, and what phase 10 decided

The roadmap's execution step 1 requires every phase to read everything earlier phases postponed and
disposition each item. **All of it was read**, across the ten phases and both registers. Two items
named phase 10 as an owner and both are taken up; the rest fall into groups phase 10 cannot meet, and
each group's reason is the same reason phase 9 gave, re-checked rather than quoted.

**Two items are taken up.**

- **`XCUT-12` under a fiber scheduler** — the deferral register's one item handed to phase 10, and
  phase 9's own postponement, both naming "phase 10, if its audit finds the thread-only form
  insufficient". `R9` finds it insufficient and ships the driver. The fallback trigger closes.
- **The repairs of every `:failed` audit, and the two `dexpace-conformance` residues** — phase 9's
  `R6` hands the first and `P9-7`/`P9-10` leave the second two. `R3` takes all three.

**None is declined with its condition met.** The item that invites it is the `minitest` pin (bullet
32): phase 9 wondered whether the decision is phase 10's, since the root `Gemfile` is phase 0's
artifact and `R6` makes the repair phase 10's. Fact 7 measured it and the answer is that **the pin is
right and its owner does not change** — phase 0's Task 2 carries it, and what phase 10 owes is the
corrected measurement in `docs/first-release.md`'s trigger, not a different pin. The condition for a
phase-10 repair — the pin proving wrong — is not met.

**The remaining items, each read and left where it is.**

| Items | Why phase 10 does not meet the condition, and where each lives |
|---|---|
| `SEAM-24`'s cancellation bridge; `PIPE-36`; `RECOV-31`, `RETRY-29`, `RETRY-38`, `RETRY-43`; `REDIR-27`; `SSE-41`; `OBS-32`, `OBS-37`; presence-gated auto-activation; `HTTP-22`, `HTTP-48`–`HTTP-50`; `BODY-12` clause 2, `BODY-36`; `TRANSPORT-28`'s zero-copy clause | SHOULDs and MAYs v1 declines, each with a reason measured by the phase that declined it. Phase 10's repair budget is for defects its audit finds, not for features earlier phases chose not to build — shipping one would be the drift `P10-1` exists to stop. `docs/first-release.md` § What v1 ships without, and the `HTTP-22`/`48`/`49`/`50` line under § Blockers |
| The seven post-v1 gems | Out of the MVP's scope by construction; design §2.2 is the authority. `docs/first-release.md` § What v1 ships without › Post-v1 gems |
| `ASYNC-3` and `PIPE-33`'s interrupt clause | "If an interruptible transport path is ever adopted" — §8.3 forbids one and phase 10 adopts nothing. Phase 10 **audits** the ledger entry (Task 12) and may not re-open the trade (cross-cutting constraint 8). `docs/first-release.md` § What v1 ships without › Unsatisfied MUSTs |
| `SERDE-27`'s no-materialization clause | Measured unmeetable at `json`'s declared floor by 7a; the named candidate is the post-v1 `dexpace-serde-oj`. Phase 10 ships no codec. Same section |
| Signed publication, `NFR-12`'s release half, `PackagingSuite`'s `NFR-12`/`NFR-16`, the housekeeping fence executor | Release-gated on conditions outside this repository — RubyGems ownership, trusted publishing, published gems to point at. `docs/first-release.md` § Release path and § After the first publish |
| A Steep target over a `test/` tree | The condition is a `test/` tree becoming production-quality code. Phase 10 adds one driver file and two gate bodies; the gate bodies go in `tools/`, which phase 9 established, and the driver is one `conformance(…)`-shaped call. Condition not met. § Post-release triggers |
| `IO-38` and the `CTX-7`/`CTX-8` drain proof on a Ruby without a GVL | Names the event "a non-CRuby row enters the CI matrix"; phase 10 adds no matrix row. § Post-release triggers |
| The require-allowlist regeneration guard | Names the event "a new Ruby minor version enters the CI matrix"; the matrix is fixed at 3.2 / 3.3 / 3.4 / 4.0. § Post-release triggers |
| Lifting appendix `B.1`, `B.2`, `B.5` | Names the event "a second implementation of the pagination engine, the SSE reader or the configuration chain exists". Phase 10 ships none, and `P9-1` stands. § Post-release triggers |
| `gates:drain_loop` | Names the event "a non-conforming drain shape appears that the deterministic assertion cannot reach". Phase 10's Task 4 either finds one or does not; if it does not, the trigger stays armed as written. § Post-release triggers |
| Minitest 6 | Names the event "no fence in the repository requires `minitest/mock`". Phase 10 adds no fence requiring it and removes none of 8a's two. § Post-release triggers, with Fact 7's corrected measurement |

---

## Findings, and who owns them now

**Seven findings, every one measured rather than inferred. None is registered.** Each is routed to its
owner below, and the owner line is where the work lives; this section is phase 10's dated record of
what it measured, which is the half a pointer cannot carry.

**Minitest resolution on this machine has moved since phase 9 measured it, and the 3.4 row is now
affected in a different way from the 4.0 row.** Measured 2026-09-13 on all four interpreters:
`Gem::Specification.find_by_name("minitest").version` is **5.25.1** on 3.2.11, **5.20.0** on 3.3.12,
**6.0.6** on 3.4.10 and **6.0.0** on 4.0.6, with `default_gem?` `false` on every one. Phase 9 recorded
5.25.1 / 5.25.4 / 6.0.0 for three of those rows on 2026-09-12, and two have changed — not because an
interpreter changed but because **6.0.6 is installed in the user gem directory on the 3.4 row**, beside
the 5.25.4 that interpreter ships, and a bare `require "minitest"` resolves the newest. The
consequence is sharper than a version number: `require "minitest/mock"` followed by
`require "minitest/autorun"` on that row loads **both copies** and emits **13
`already initialized constant` warnings**, which `NFR-6`'s `Warning.warn`-raising gate turns into a
failure. So phase 0's `~> 5.25` pin is not only what keeps `Object#stub` available on the 4.0 row; it
is what makes the 3.4 row deterministic at all, and the mechanism is newest-wins resolution outside
Bundler. `require "minitest/mock"` still raises `LoadError` on 4.0.6. Cites `NFR-6`, `NFR-17`,
`NFR-10`, `NFR-2`.
**Owner: `docs/first-release.md` § Post-release triggers, the Minitest 6 entry** — its per-interpreter
versions are corrected and the duplicate-load mechanism added, dated, by Task 18. The pin stays **phase
0's plan, Task 2**; nothing about it changes. And phase 10's Task 1 re-measures both, because a fact
that moved once in a day will move again.

**`docs/product-spec/03-pluggable-seams-and-extension-model.md` is named as the source of `SEAM-13`,
`SEAM-15` and `SEAM-22` by two phase-8 governing-documents lists, and it carries none of the three.**
Re-verified 2026-09-13: `SEAM-13`'s only prose home is `docs/product-spec/02-architectural-principles.md`,
and `SEAM-15`, `SEAM-20`, `SEAM-22`, `SEAM-23` and `SEAM-28` appear in no prose chapter — appendix C is
their only normative statement, which is what phase 2 established on 2026-09-06 and what the register
retirement's three "unfollowable gap pointers" were. The two lists are
`docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance-design.md:67`
(wrong about `SEAM-13`, `SEAM-15`, `SEAM-22`; right about the other four) and
`docs/work/mvp/phase8/phase8c/2026-09-11-phase8c-asynchronous-transport-design.md:69-70` (wrong about
`SEAM-13` and `SEAM-15`; right about the other seven). An implementer following either list reads the
wrong chapter and finds nothing. Cites `SEAM-13`, `SEAM-15`, `SEAM-22`, `SEAM-29`.
**Owner: nobody — fixed in this pass.** Both lists now name appendix C for the appendix-C-only IDs and
`02-architectural-principles.md` for `SEAM-13`, with the correction stated and dated. They are phase
documents, which CLAUDE.md's routing rule makes writable material, and "if the thing it reports is in
material you may write, it is not a finding at all: fix it." Task 7's check is what keeps the class
closed.

**A claim-verb grammar for the chapter-attribution check matches 0 of the 38 live candidates; the
axis is clause scoping.** Measured 2026-09-13 over every `*.md` under `docs/`. The roadmap's job
description for bullet 3 asks for a grammar of "read out of X", "stated in X", an `X §N` adjacency —
and no live candidate has a verb at all, because the shape the claims take is a bare
governing-documents list. A naive same-line rule fires on 14 lines / 23 pairs with 4 true positives;
clause scoping plus a negation vocabulary over a two-line window fires 3 times with 3 true positives
and 0 false positives. Cites the requirement-ID conventions, `NFR-17`.
**Owner: phase 10's plan, Task 7**, which builds the clause-scoped form, its four fixtures and its two
stated gaps. The finding is recorded here because the roadmap's stated job description is wrong about
the mechanism and a later reader would otherwise build the verb grammar and measure it as useless.

**`OBS-29`'s enforcement clause is in appendix C's row and in no chapter, so every document derived
from chapter 15 states the requirement short — and the divergence runs both ways in the same pair.**
Appendix C's `OBS-29` row ends "(created by the factory per operation). This is a documented emission
contract; pipeline/transport wiring to emit it is a follow-up, so it is not yet runtime-enforced."
`docs/product-spec/15-instrumentation-and-observability.md:54` ends at "One tracer instance corresponds
1:1 to a single logical operation" — **neither the parenthetical nor the follow-up clause** — and carries
a `*Conformance:*` clause appendix C drops. So each row reads complete and neither is. Design §8.1
restates the chapter; the harvested rule `observability/2da9e2f3` is derived from the chapter and is
exact about its source; 5b, 5c, 6a, 8a and the roadmap's inbound bullet all reasoned from one or the
other and carried an "open surface decision" the requirement had already closed. Nothing was built
wrongly — every one of those phases declined the wiring, 6a under its `R15` and 8a as `P8-7` — but the
decision travelled as open through five documents and one register retirement, and a phase with a repair
budget could have spent it widening a public surface `NFR-4` would then lock with no caller. **This is
the second measured instance of the index-versus-chapter divergence**, the first being appendix C's
`SSE-19` row dropping the port sanction the chapter grants, and two instances is what makes C11 an
amendment about the pattern rather than an erratum about one row. Cites `OBS-29`, `OBS-28`, `OBS-25`,
`CTX-14`, `CTX-20`, `SSE-19`, `NFR-4`.
**Owner: `docs/knowledge/notes/observability.md`** — the one note phase 10 files, filed at planning time
rather than at execution, because a resolution recorded only in a design document is re-litigated by
whoever reads the corpus next; plus phase 10's plan, Task 16, which states the two-factories distinction
in the two YARD blocks a phase-5 implementer copies from, and Task 17's amendment C11 for the pattern.
The corpus could not have held the clause — a harvested entry cannot carry what its source does not say
— which is why the note **Corrects** `observability/2da9e2f3` rather than reporting the harvester. This
is the shape of error `R2`'s method exists to catch and the strongest single piece of evidence for it:
the claim was re-derived from appendix C and the answer changed.

**`APPENDIX_B.md`'s check 2 is weaker than the prose that specifies it.** Phase 9's design settles on
per-row ID-set equality against each appendix-B item's own text and argues it makes the distinct-ID
coverage check hold by construction; the filed test asserts only that each row names at least one ID
from the nineteen prefixes, and `AppendixB` exposes no per-item ID accessor to compare against. The
map therefore documents a check it does not perform, in an artifact whose whole purpose is to be the
one place the real mapping is written down. Cites `NFR-17`.
**Owner: phase 10's plan, Task 3**, which adds the accessor and the equality assertion. It is phase
10's rather than phase 9's because phase 9 has closed by the time phase 10 reads its plan, and it is a
defect in an instrument phase 10's verdicts depend on — which is the one category `R3` permits phase
10 to touch inside `dexpace-conformance`.

**The `async-http` dependency closure uses `Fiber#raise` in seven places, `Thread#raise` in one and
`Thread#kill` in one, and `Fiber#raise` is not on §8.3's list.** Measured 2026-09-13 by source scan of the resolved closure —
17 gems, installed under `--install-dir` in the session scratchpad, `async` 2.45.1 / `async-http`
0.104.0 / `io-event` 1.22.0 / `protocol-http1` 0.41.0, the versions 8c measured against. No
`Timeout.timeout` call anywhere (the one occurrence is a doc comment). `Fiber#raise` at
`async/task.rb:365` is how `Async::Task#cancel` delivers `Async::Cancel` — the mechanism 8c's
`TRANSPORT-8` result rests on — and six more sites sit in `async/scheduler.rb` and `io-event`. The
omission from §8.3's list is principled: a fiber raise resumes at a **scheduler checkpoint**, which is
the property §8.3's rationale distinguishes and §3.3 already relies on. The single `Thread#raise` is `io-event/selector/select.rb:398`, and it is
`Thread.current.raise(error)` — a raise on the calling thread, which is an ordinary synchronous `raise`
rather than the asynchronous cross-thread interrupt §8.3 prohibits, in the pure-Ruby fallback selector;
it is reported because §8.3 names the primitive and a reader auditing the ban will grep for it. The
single `Thread#kill` is
`io-event/selector.rb:59`, in `Selector.process_wait`'s `ensure`, killing a helper thread whose body
is `Process::Status.wait`; the adapter waits on no child process. Cites `ASYNC-3`, `PIPE-33`,
`XCUT-13`, `TRANSPORT-4`, `NFR-2`.
**Owner: phase 10's plan, Task 17, amendment C8** — which the measurement widens from "one clause
scoping the prohibition to code this repository writes" to that clause plus the statement of what both
closures do. Bullet 19 asked for this measurement in as many words ("the same question is owed of
`async-http`'s dependency closure") and nothing had made it.

**`net-http`'s connect-phase `Timeout.timeout` is on every supported Ruby and the inbound bullet's
citation resolves on one.** The call is `net/http.rb:1601` on 3.2.11 and 3.3.12, `:1657` on 3.4.10 and
`:1791` on 4.0.6, and on every row it is
`Timeout.timeout(@open_timeout, Net::OpenTimeout) { TCPSocket.open(…) }`. Bullet 19 cites
`/usr/lib/ruby/3.4.0/net/http.rb:1657` — a machine-absolute path and a version-specific line. The
finding strengthens; the citation does not survive. Cites the same IDs.
**Owner: phase 10's plan, Task 17, amendment C8**, which cites the call and the method rather than a
line, and the roadmap's inbound list, where bullet 19 gains the dated per-row measurement — because a
citation that resolves on one laptop is the failure the styleguide-path rule already names in
CLAUDE.md.

**One entry for `docs/deviations.md`'s holding area that is not one of the thirteen.** None. Phase 10
completes the holding area rather than adding to it: the seven notes of the retirement batch (`C1`,
`C3`–`C7`, `C10`), the two dated 2026-09-12 that the set had left out and this pass numbers `C12` and
`C13`, and the two phase 10 added — `C11` and the entry carrying Fact 4's closure measurement into `C8`
— make **eleven notes carrying eleven of the thirteen**, with `C2` and `C9` Task 17's two remaining
writes. Everything else phase 10
finds is either a repair or a fix in writable material. **That is the intended end state** — the
holding area was described as "a holding area, not a permanent second ledger", and phase 10 is the
phase that hands it over complete.

**`docs/first-release.md`'s new lines, in one place so they can be counted.** One blocker (`R5`'s
amendment set); two *Behavioural asymmetries* entries (`R6`'s unwired HTTP-tracer groups, `R7`'s
undriven correlation chain); one post-release trigger (the continued-clause blind spot); two narrowed
blockers (the conformance-run caveat, the worked example); three closed lines (the RBS baseline,
`gates:bounded_map`, and the `XCUT-12` trigger); one corrected trigger (Minitest 6's measurement).

---

## The knowledge notes phase 10 files

**One note, one entry, in an existing file — filed with this design and not at execution time**, because
a resolution recorded only in a design document is re-litigated by whoever reads the corpus next. Phase
9 set the precedent and its status note records it ("Three corpus notes were filed before the plan was
written"); phase 10's plan, Task 19 Step 4 **confirms** the entry and re-runs the verifiers rather than
filing it.

`docs/knowledge/notes/observability.md` gains one entry under `## Superseded`, role `review`, with a
manual `sha:` marker, recording that **`OBS-29`'s emission wiring is a documented follow-up and not a
runtime obligation, and that the clause saying so lives in appendix C's row and in no chapter.** It
**Corrects** `observability/2da9e2f3`, the harvested Rules entry, which ends at "one tracer instance
corresponding 1:1 to a single logical operation" and is exact about its source —
`docs/product-spec/15-instrumentation-and-observability.md:54` ends there too. So the note does not
report a harvesting error: **a harvested entry cannot carry what its source does not say**, and that is
the point the entry makes. `observability/2da9e2f3` therefore prints
`[overridden by notes/observability.md]`, which is verified rather than assumed —
`ruby scripts/knowledge.rb --key observability/2da9e2f3` shows the tag.

Two citation details that were measured rather than guessed. `observability/4044a5c7` — the duck-typed
listener entry — is named with a leaning verb ("unaffected and adopted verbatim"), so it prints
`[cited by notes/…]`: marking a correct, load-bearing rule as overruled is the expensive direction to
get wrong. And this file's **two existing `## Superseded` entries** are named by their `sha:` markers
rather than by their keys, because `verify_knowledge_structure.rb` rejects a backticked key that no
**harvested** entry carries, and a note's own key is not one. A first draft cited them as keys and the
gate failed with two violations naming both; that is recorded here because it is the kind of thing a
later note-writer will otherwise rediscover.

**Why only one.** A note earns its place by overriding a harvested rule that an implementation found
false. Phase 10's other six findings are not that: two are corrections to documents phase 10 fixed in
this pass, three are measurements of third-party source or machine state that no harvested rule
asserts, and one is a defect in a phase plan. Filing a note for a finding with no harvested rule
behind it would make `notes/` the register CLAUDE.md says it is not.

Phase 10 adds **no conflict entry**: the six cross-role conflicts are all overridden and phase 10
opens none. After the note landed, `ruby scripts/verify_knowledge_structure.rb` reports
**52 note entries, all review-role, every cited key live**, and `ruby scripts/knowledge_drift.rb`
reports **111 note citations resolving, 0 not**. `docs/knowledge/harvested/` is not touched.

---

## The four decisions the maintainer confirmed

**All four were put to the maintainer with the call, the alternative and the cost of overturning, and
all four were confirmed on 2026-09-13.** They are recorded here as decided rather than open, and each
keeps its alternative written out — the alternative is now the rejected branch, not a live option, and
it is kept because a decision whose alternative has been deleted cannot be revisited on evidence.
Nothing else in this document is open.

1. **`R6`: the `PRE_REDIRECT` operation-lifecycle step is declined. Confirmed.** `OBS-29`'s own last
   sentence makes the wiring a follow-up and not runtime-enforced, so the MUST is met by 5c's documented
   contract and 6a's per-attempt group, and adding a step would `NFR-4`-lock a surface with no caller.
   *Rejected alternative:* ship the step anyway, on the ground that a documented contract nothing emits
   is a contract no test exercises end to end, and `Stages::PRE_REDIRECT` is a site phase 4c already
   argues runs exactly once. This was the one decision that would have materially changed what v1's
   instrumentation does, which is why it was flagged; taking the alternative would have added one task
   and one `sig/` change inside `dexpace-core` and removed one *Behavioural asymmetries* entry.
2. **`R7`: documentation rather than an `operation_name:` keyword. Confirmed.** `CTX-16`'s three modal
   clauses are met without a carrier, `SEAM-28` is a deferred MAY, and the `#tag` precedent says a
   keyword with no caller is the expensive direction. *Rejected alternative:* add `operation_name:` to
   `Pipeline#call` and `AsyncPipeline#call` beside 6a's `bundle:`, on the ground that `ContextStore`'s cap
   and `CTX-19`'s reachability are otherwise exercised only by tests and that a generated client will
   want it on day one; it would have added one task and touched two `sig/` files.
3. **`R5`: the amendment set is a `docs/first-release.md` blocker, not a *ships-without* entry.
   Confirmed**, with the explicit alternative form kept inside the blocker itself — the release notes
   naming which design sentences a reader should not trust. Thirteen wrong sentences in the documents a
   consumer reads is a release decision, and making it a blocker forces the decision rather than
   recording it. *Rejected alternative:* a *what v1 ships without* entry, on the ground that no
   requirement is unmet and the holding area already carries the corrections; it would have moved one
   line between two sections and changed no task.
4. **`R9`: phase 10 ships the `XCUT-12` fiber driver rather than leaving the trigger armed. Confirmed.**
   The route exists (clause 9's `around:`, 8a's in-gem driver precedent), the composition blocker was
   phase 9's and not phase 10's, and a SHOULD asserted only under the scheduler its mechanism is safe on
   is an assertion that cannot fail. *Rejected alternative:* leave the post-release trigger armed for
   `dexpace-async-async`, on the ground that a driver in one adapter's `test/` tree proves the property
   for that adapter rather than portably; it would have removed one task and restored one trigger. The
   trigger stays in `docs/first-release.md` until Task 9's fiber run is recorded, because a decision in a
   plan is not evidence the work was done; Task 18 removes it then.
