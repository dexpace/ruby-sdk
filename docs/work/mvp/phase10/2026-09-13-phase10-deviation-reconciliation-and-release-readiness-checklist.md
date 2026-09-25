# Phase 10 — Deviation Reconciliation and Release Readiness: Checklist

**Written at execution time, 2026-09-25, from what was built** — not from the plan. The design and the
plan were written on 2026-09-13 against the DESIGNS of phases 1–9, before phase 3 existed as code; every
earlier phase has since been built, reviewed and merged, and phase 9 audited them. Phase 10 was cut from
`main` at `b242de6`, which holds all of it and was green under all twenty-one gates before this phase
changed a line (measured, "Gate runs" below). Where the plan's text and the built tree disagree the tree
wins, and "Deviations from the plan" states each departure with its reason.

**Phase 10 is the last phase.** There is no later phase to route anything to: every finding this phase
does not repair is a dated `docs/first-release.md` line, and phase 10's inbound list on the roadmap is
**emptied by disposition** — every one of its sixty-five bullets carries a dated bracket naming what
happened to it, and the table below holds the same sixty-five. Nothing is published: every gem stays at
`0.0.0`, no tag is cut and no version is bumped.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase, task
number and path — that will do it, or the `docs/first-release.md` entry that owns it) · N/A not
applicable in this port.

Plan: `docs/work/mvp/phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness.md`, nineteen
tasks plus the "Task 10b" the maintainer added at execution (small repairs). Design:
`docs/work/mvp/phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness-design.md`, whose
Deviation Ledger carries `P10-1`–`P10-11` and whose As-built addendum, written with this checklist, adds
**`P10-21`–`P10-38`** (the band starts at `P10-21`; `P10-12`–`P10-20` are left free and nothing is
renumbered). The design's `R1` file list was widened by a dated addendum (see Deviations 1).

**Verdict vocabulary** (the design's `R1`): *confirmed*, *confirmed-with-a-narrowing* (true, and narrower
than the sentence — the narrowing is an amendment in `docs/deviations.md`'s set), *contradicted* (none
found), *unverifiable* (none). The per-entry verdict and its evidence is `docs/deviations.md`'s Status
column, which `gates:ledger_audit` checks: every verdict row cites a `gems/…` path that exists and names
only `Dexpace::` constants that are defined.

Test files are named with their gem: `core/…` is `gems/dexpace-core/test/dexpace/`, `gates/…` is
`test/gates/`, `conformance/…` is `gems/dexpace-conformance/test/dexpace/conformance/`, `async_http/…` is
`gems/dexpace-transport-async_http/test/dexpace/transport/async_http/`, `net_http/…` likewise, and
`housekeeping/…` is `.claude/skills/housekeeping/test/`.

---

## Requirement rows

**205 rows: 124 own, 64 cross-reference and 17 added cross-reference.** The 124 own rows are every ID
design §10's nineteen entries name plus `RETRY-28` from its closing note — extracted mechanically by
`LedgerAudit.ids_in` from the frozen chapter (123 distinct IDs, the same number `gates:ledger_audit`
asserts row by row) — **108 MUST, 15 SHOULD, 1 MAY**, each level read from appendix C. The 64 are the
design's cross-reference set (44 MUST, 16 SHOULD, 4 MAY). The 17 added are IDs a phase-10 repair changed
that neither set carried: `HTTP-10`, `HTTP-19`, `HTTP-33`, `HTTP-47`, `BODY-9`, `TRANSPORT-22`, `TRANSPORT-24`, `OBS-11`,
`CFG-13`, `NFR-7`, `NFR-15`, `REDIR-23`, `RETRY-42`, `RECOV-28`, `AUTH-34`, `AUTH-37` and `PIPE-39`. An ID
named by more than one §10 entry has one row naming every entry; the *Task* column is the audit task
(11–15) for an own row. The *Owner* column is the earlier phase whose checklist first carries the ID; no
earlier row moves, except the ten levels corrected in place (Deviations 10).

**Own rows by mark:** ✅ 107 · 🚫 11 (the retired provider apparatus: `SEAM-3`, `SEAM-4`, `IO-30`–`IO-36`,
`IO-39`; and `SEAM-22`'s mechanism, retired by §10.14, its surviving clause ✅ as phase 2 marks it) · N/A 4 (`SEAM-10`, `NFR-8`, `NFR-9`, `ASYNC-4`) · ⏳ 2 (`ASYNC-3`, `PIPE-33`, both
`docs/first-release.md` § Unsatisfied MUSTs) — `CFG-20` is counted ✅ with its fourth clause ⏳ on the same
entry. **By verdict:** every row's §10 entry is *confirmed* or *confirmed-with-a-narrowing*; nothing is
*contradicted* and nothing *unverifiable*.

### Own rows

| ID | Level | Status | Task | §10 entry | Owner | Verdict and as-built evidence |
|---|---|---|---|---|---|---|
| `SEAM-1` | MUST | ✅ | 12 | §10.3, §10.7 | 0 | confirmed (`docs/deviations.md` row 3); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `SEAM-3` | MUST | 🚫 | 11 | §10.1, §10.2, §10.12 | 2 | confirmed-with-a-narrowing (`docs/deviations.md` row 1); retired apparatus (§10.1); its ownership-on-wrap rule lives on as `IO-6`; also named by §10.2 (the duck type) and §10.12 (C3's misattribution) |
| `SEAM-4` | MUST | 🚫 | 11 | §10.1 | 2 | confirmed-with-a-narrowing (`docs/deviations.md` row 1); retired apparatus: provider resolution for a seam that does not exist |
| `SEAM-5` | MUST | ✅ | 11 | §10.1, §10.8 | 2 | confirmed-with-a-narrowing (`docs/deviations.md` row 1); the loud zero/many-candidate branches (`registry.rb`); §10.8's substrate; phase 10 added the termination argument at `#resolve` and `registry_test.rb`'s Termination pins |
| `SEAM-6` | MUST | ✅ | 11 | §10.1, §10.8 | 2 | confirmed-with-a-narrowing (`docs/deviations.md` row 1); phase 2's `Dexpace::Registry#install` (`gems/dexpace-core/lib/dexpace/registry.rb`): an `equal?` re-install is a silent no-op and a different instance over an explicit install raises `Dexpace::InvalidArgumentError` naming both; phase 2's row and its `registry_test.rb` cases stand. §10.1 names it only as part of the retired I/O seam's apparatus; the rule itself survives on the three registries that remain (§10.8) |
| `SEAM-7` | MUST | ✅ | 11 | §10.1, §10.8 | 2 | confirmed-with-a-narrowing (`docs/deviations.md` row 1); phase 2's `Dexpace::Registry#resolve` (`gems/dexpace-core/lib/dexpace/registry.rb`): a successful resolution memoised process-wide, a failed one memoising nothing; phase 2's row and its `registry_test.rb` cases stand. §10.1 names it only as part of the retired I/O seam's apparatus; the rule survives on the three registries that remain (§10.8) |
| `SEAM-8` | SHOULD | ✅ | 11 | §10.1, §10.8 | 2 | confirmed-with-a-narrowing (`docs/deviations.md` row 1); phase 2's `Dexpace::Registry` (`gems/dexpace-core/lib/dexpace/registry.rb`): replacing an already handed-out auto-resolved provider emits one `Kernel#warn`; phase 2's row and its `registry_test.rb` cases stand. §10.1 names it only as part of the retired I/O seam's apparatus; the rule survives on the three registries that remain (§10.8) |
| `SEAM-9` | MUST | ✅ | 11 | §10.1, §10.8 | 2 | confirmed-with-a-narrowing (`docs/deviations.md` row 1); phase 2's `Dexpace::Registry` (`gems/dexpace-core/lib/dexpace/registry.rb`): one frozen `Registry::State` snapshot swapped under a `::Thread::Mutex`, lock-free reads, one factory call across 32 concurrent first accesses; phase 2's row and its `registry_test.rb` cases stand. §10.1 names it only as part of the retired I/O seam's apparatus; the rule survives on the three registries that remain (§10.8) |
| `SEAM-10` | SHOULD | N/A | 11 | §10.1, §10.9 | 2 | confirmed-with-a-narrowing (`docs/deviations.md` row 1); vacuous (one constant namespace), replaced by the `core:` version-skew guard (§10.9). **Level corrected** in phase 2's checklist: appendix C says SHOULD |
| `SEAM-13` | SHOULD | ✅ | 12 | §10.4 | 2 | confirmed-with-a-narrowing (`docs/deviations.md` row 4); cooperative cancellation through `Dexpace::Cancellation`; §10.4 |
| `SEAM-16` | MUST | ✅ | 12 | §10.3 | 2 | confirmed (`docs/deviations.md` row 3); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `SEAM-17` | SHOULD | ✅ | 12 | §10.3 | 2 | confirmed (`docs/deviations.md` row 3); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `SEAM-20` | MUST | ✅ | 14 | §10.12, §10.13 | 2 | confirmed-with-a-narrowing (`docs/deviations.md` row 12); four profiles (§10.13) and closes-nothing (§10.12) |
| `SEAM-21` | MUST | ✅ | 14 | §10.12 | 2 | confirmed-with-a-narrowing (`docs/deviations.md` row 12); residue: 7a's evidence is a branch inside another assertion, declared in no ID-keyed map -- `docs/first-release.md` § Post-release triggers |
| `SEAM-22` | MUST | 🚫 mechanism (§10.14); surviving clause ✅ | 14 | §10.14 | 2 | confirmed (`docs/deviations.md` row 14); appendix-C only, read verbatim; the reflective type capture is retired and the witness is the substitution, so the mark is phase 2's own -- the surviving clause, an explicit witness with no witness-less `#load` overload, is phase 2's `serde_test.rb` case |
| `SEAM-23` | MUST | ✅ | 14 | §10.14 | 2 | confirmed (`docs/deviations.md` row 14); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `SEAM-29` | MUST | ✅ | 14 | §10.10 | 1 | confirmed-with-a-narrowing (`docs/deviations.md` row 10; amendment `C19`); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `SEAM-30` | MUST | ✅ | 12 | §10.4 | 2 | confirmed-with-a-narrowing (`docs/deviations.md` row 4); `Completer#fulfil`'s close of an undelivered response |
| `HTTP-2` | MUST | ✅ | 14 | §10.10 | 1 | confirmed-with-a-narrowing (`docs/deviations.md` row 10; amendment `C19`); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `HTTP-4` | MUST | ✅ | 14 | §10.10 | 1 | confirmed-with-a-narrowing (`docs/deviations.md` row 10; amendment `C19`); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `HTTP-5` | MUST | ✅ | 14 | §10.11 | 1 | confirmed (`docs/deviations.md` row 11); phase 10 repaired `Model.own`'s default-proc escape (Task 10b) |
| `HTTP-7` | MUST | ✅ | 14 | §10.10 | 1 | confirmed-with-a-narrowing (`docs/deviations.md` row 10; amendment `C19`); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `HTTP-17` | MUST | ✅ | 14 | §10.10 | 1 | confirmed-with-a-narrowing (`docs/deviations.md` row 10; amendment `C19`); re-validated at both wires; phase 10 made every `HeaderSyntax` predicate total over a non-String (Task 10b) |
| `HTTP-18` | MUST | ✅ | 14 | §10.10 | 1 | confirmed-with-a-narrowing (`docs/deviations.md` row 10; amendment `C19`); as `HTTP-17` |
| `IO-1` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); residue, not repaired: after a mid-stream failure `.over`'s enumerator restarts `#each` (7b's finding) -- `docs/first-release.md` § Post-release triggers |
| `IO-2` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-3` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-4` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-5` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-6` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); ownership-on-wrap, read from `IO-6`'s own text: `BufferedSource.wrapping(StringIO).close` closes the StringIO (measured 2026-09-25) |
| `IO-7` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-8` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-9` | SHOULD | ✅ | 11 | §10.1, §10.18 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); the materialisation ceiling, read per call; also §10.18. **Level corrected** in 5a's checklist: SHOULD |
| `IO-10` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-11` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); residue: the per-byte `#getbyte` cost (~0.9 µs/byte) -- `docs/first-release.md` § Post-release triggers |
| `IO-12` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-13` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-14` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-15` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-16` | SHOULD | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); the bridge half; C3 names it beside `IO-6` |
| `IO-17` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-18` | SHOULD | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-19` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-20` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-21` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-22` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-23` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-24` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-25` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-26` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-27` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-28` | MUST | ✅ | 11 | §10.1, §10.10 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); also §10.10's claim: a duck-typed stream passes the builder, and the wire boundary re-validates headers, not streams |
| `IO-29` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-30` | MUST | 🚫 | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); retired apparatus: the provider seam's factory operations are removed with the seam (§10.1); the one behavioural clause survives as a property of `Dexpace::IO::BufferedSource.of_bytes` -- the source is an independent copy -- as 3a's row records |
| `IO-31` | MUST | 🚫 | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); retired apparatus: provider resolution rules for a seam that does not exist (§10.1); asserted negatively by `Dexpace::IO.constants` holding no registry, factory or installation call (3a's `io_test.rb`), as 3a's row records |
| `IO-32` | MUST | 🚫 | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); appendix-C only; the install-idempotence clause whose subject is removed |
| `IO-33` | MUST | 🚫 | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); appendix-C only; explicit-install-wins, subject removed |
| `IO-34` | SHOULD | 🚫 | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); appendix-C only; the resolution cache, subject removed. **Level corrected** in 3a's checklist: SHOULD |
| `IO-35` | SHOULD | 🚫 | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); appendix-C only; the replaced-provider warning, subject removed |
| `IO-36` | MAY | 🚫 | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); the provider's own obligations, subject removed. **Level corrected** in 3a's checklist: MAY |
| `IO-37` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-38` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); tested on CRuby only; the GVL hides a missing lock -- the standing non-CRuby post-release trigger |
| `IO-39` | SHOULD | 🚫 | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); retired apparatus: lock-free reads of a provider registry that does not exist (§10.1); the property survives in phase 2's `Dexpace::Registry` (`SEAM-9`), as 3a's row records |
| `IO-40` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-41` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `IO-42` | MUST | ✅ | 11 | §10.1 | 3a | confirmed-with-a-narrowing (`docs/deviations.md` row 1); implemented in full by 3a under `gems/dexpace-core/lib/dexpace/io/` -- only the pluggability apparatus is removed; 3a's row stands |
| `BODY-1` | MUST | ✅ | 12 | §10.2 | 3b | confirmed (`docs/deviations.md` row 2); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `BODY-8` | MUST | ✅ | 14 | §10.12 | 3b | confirmed-with-a-narrowing (`docs/deviations.md` row 12); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `BODY-32` | MUST | ✅ | 15 | §10.18 | 3b | confirmed-with-a-narrowing (`docs/deviations.md` row 18); the ceiling BODY-32 shares with `IO-9` |
| `BODY-35` | MUST | ✅ | 12 | §10.2 | 3b | confirmed (`docs/deviations.md` row 2); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `BODY-37` | MUST | ✅ | 14 | §10.10 | 3b | confirmed-with-a-narrowing (`docs/deviations.md` row 10; amendment `C19`); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `PIPE-16` | MUST | ✅ | 15 | §10.15 | 4c | confirmed (`docs/deviations.md` row 15); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `PIPE-33` | MUST | ⏳ | 12 | §10.5 | 4c | confirmed as admitted, and not re-opened (roadmap cross-cutting constraint 8) (`docs/deviations.md` row 5); the interrupt clause not satisfied; the non-interrupting half met exactly -- `docs/first-release.md` § Unsatisfied MUSTs |
| `RECOV-12` | MUST | ✅ | 13 | §10.6 | 4b | confirmed-with-a-narrowing (`docs/deviations.md` row 6); the trail on `Suppressible`; C14 is the §10.6/§5.2 sentence correction |
| `RECOV-34` | MUST | ✅ | 15 | §10.18 | 4b | confirmed-with-a-narrowing (`docs/deviations.md` row 18); the ~292-year bound, refused above |
| `RETRY-23` | MUST | ✅ | 12 | §10.4 | 6a | confirmed-with-a-narrowing (`docs/deviations.md` row 4); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `RETRY-26` | MUST | ✅ | 15 | §10.17 | 6a | confirmed (`docs/deviations.md` row 17); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `RETRY-28` | MUST | ✅ | 15 | closing note | 6a | confirmed (`docs/deviations.md` the closing note); the closing note's own row: nothing unified, both sanctions un-invoked |
| `RETRY-34` | MUST | ✅ | 13 | §10.6 | 4b | confirmed-with-a-narrowing (`docs/deviations.md` row 6); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `REDIR-11` | MUST | ✅ | 15 | §10.15 | 4c | confirmed (`docs/deviations.md` row 15); the porter trap cannot occur: no header carries the marker |
| `AUTH-14` | MUST | ✅ | 13 | §10.7 | 6c | confirmed (`docs/deviations.md` row 7); `["u:p"].pack("m0")` (`auth/basic_handler.rb:45`), never `Base64` |
| `AUTH-29` | MUST | ✅ | 15 | §10.15 | 4c | confirmed (`docs/deviations.md` row 15); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `PAGE-13` | MUST | ✅ | 13 | §10.6 | 7c | confirmed-with-a-narrowing (`docs/deviations.md` row 6); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `PAGE-15` | MUST | ✅ | 13 | §10.6 | 7c | confirmed-with-a-narrowing (`docs/deviations.md` row 6); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `SSE-11` | MUST | ✅ | 15 | §10.18 | 7b | confirmed-with-a-narrowing (`docs/deviations.md` row 18); documented and public; C11's appendix-C `SSE-19` note stands beside it |
| `SSE-29` | MUST | ✅ | 13 | §10.6 | 7b | confirmed-with-a-narrowing (`docs/deviations.md` row 6); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `SSE-30` | MUST | ✅ | 13 | §10.6 | 7b | confirmed-with-a-narrowing (`docs/deviations.md` row 6); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `SSE-36` | MUST | ✅ | 13 | §10.6 | 7b | confirmed-with-a-narrowing (`docs/deviations.md` row 6); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `SERDE-5` | MUST | ✅ | 14 | §10.14 | 7a | confirmed (`docs/deviations.md` row 14); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `SERDE-6` | MUST | ✅ | 14 | §10.14 | 7a | confirmed (`docs/deviations.md` row 14); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `SERDE-7` | MUST | ✅ | 14 | §10.14 | 7a | confirmed (`docs/deviations.md` row 14); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `SERDE-8` | MUST | ✅ | 14 | §10.14 | 7a | confirmed (`docs/deviations.md` row 14); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `SERDE-16` | MUST | ✅ | 14 | §10.14 | 7a | confirmed (`docs/deviations.md` row 14); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `SERDE-17` | MUST | ✅ | 14 | §10.14 | 7a | confirmed (`docs/deviations.md` row 14); filed under Constraints in the corpus, not Rules |
| `OBS-2` | MUST | ✅ | 13 | §10.7 | 5b | confirmed (`docs/deviations.md` row 7); the duck-typed sink; no `require "logger"` anywhere in core's `lib/` |
| `OBS-35` | SHOULD | ✅ | 15 | §10.16 | 5b | confirmed (`docs/deviations.md` row 16); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `CFG-1` | MUST | ✅ | 15 | §10.16 | 5a | confirmed (`docs/deviations.md` row 16); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `CFG-3` | MUST | ✅ | 15 | §10.16 | 5a | confirmed (`docs/deviations.md` row 16); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `CFG-4` | MUST | ✅ | 15 | §10.16 | 5a | confirmed (`docs/deviations.md` row 16); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `CFG-15` | MUST | ✅ | 15 | §10.17 | 5a | confirmed (`docs/deviations.md` row 17); phase 10: NaN and Complex refused (Task 10b) |
| `CFG-17` | MUST | ✅ | 12 | §10.4, §10.17 | 5a | confirmed-with-a-narrowing (`docs/deviations.md` row 4); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `CFG-18` | SHOULD | ✅ | 15 | §10.17 | 5a | confirmed (`docs/deviations.md` row 17); phase 10: `Async.delay` refuses NaN and Complex (Task 10b) |
| `CFG-20` | SHOULD | ✅ (three clauses) / ⏳ (the interrupt clause) | 12 | §10.4 | 5a | confirmed-with-a-narrowing (`docs/deviations.md` row 4); three clauses met; the cancel-with-interrupt clause is §10.5's same unmet clause under a second ID -- `docs/first-release.md` § Unsatisfied MUSTs |
| `CFG-21` | MUST | ✅ | 12 | §10.4 | 5a | confirmed-with-a-narrowing (`docs/deviations.md` row 4); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `CFG-24` | MUST | ✅ | 15 | §10.16 | 5a | confirmed (`docs/deviations.md` row 16); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `CFG-26` | MUST | ✅ | 15 | §10.16 | 5a | confirmed (`docs/deviations.md` row 16); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `TRANSPORT-3` | MUST | ✅ | 12 | §10.4 | 8a | confirmed-with-a-narrowing (`docs/deviations.md` row 4); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `ASYNC-1` | MUST | ✅ | 12 | §10.3 | 8b | confirmed (`docs/deviations.md` row 3); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `ASYNC-2` | MUST | ✅ | 12 | §10.3 | 8b | confirmed (`docs/deviations.md` row 3); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `ASYNC-3` | MUST | ⏳ | 12 | §10.5 | 8b | confirmed as admitted, and not re-opened (roadmap cross-cutting constraint 8) (`docs/deviations.md` row 5); not satisfied, admitted: `ExecutorSuite` asserts it so it FAILS and the pool's driver waives it by ID, printed `waived (would fail): ASYNC-3` (`gems/dexpace-async-thread/test/dexpace/async/thread/conformance_test.rb`) -- `docs/first-release.md` § What v1 ships without › Unsatisfied MUSTs |
| `ASYNC-4` | MUST | N/A | 12 | §10.5 | 8b | confirmed as admitted, and not re-opened (roadmap cross-cutting constraint 8) (`docs/deviations.md` row 5); vacuous: a port that never delivers an interrupt cannot produce the poisoning hazard |
| `ASYNC-5` | MUST | ✅ | 12 | §10.4 | 8b | confirmed-with-a-narrowing (`docs/deviations.md` row 4); the producer-side orphan close, both transports |
| `XCUT-1` | MUST | ✅ | 12 | §10.4 | 9 | confirmed-with-a-narrowing (`docs/deviations.md` row 4); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `XCUT-2` | MUST | ✅ | 12 | §10.4 | 9 | confirmed-with-a-narrowing (`docs/deviations.md` row 4); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `XCUT-3` | MUST | ✅ | 12 | §10.4, §10.17 | 9 | confirmed-with-a-narrowing (`docs/deviations.md` row 4); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `XCUT-9` | MUST | ✅ | 13 | §10.6 | 4b | confirmed-with-a-narrowing (`docs/deviations.md` row 6); one walk, cycle-safe; residues stated, not repaired -- a collect-then-yield walk and a depth cap equal to the cycle length pass the black-box assertion (`docs/first-release.md` § Post-release triggers) |
| `XCUT-13` | MUST | ✅ | 15 | §10.17 | 9 | confirmed (`docs/deviations.md` row 17); the requirement stands as its owner's row records it; the entry's verdict and evidence are that row of `docs/deviations.md` |
| `XCUT-15` | MUST | ✅ | 14 | §10.11 | 9 | confirmed (`docs/deviations.md` row 11); as `HTTP-5` |
| `XCUT-18` | MUST | ✅ | 14 | §10.10 | 9 | confirmed-with-a-narrowing (`docs/deviations.md` row 10; amendment `C19`); the call-site assertion runs for real in the aggregate and is accepted-vacuous in core's own driver |
| `XCUT-23` | MUST | ✅ | 11 | §10.1, §10.8 | 9 | confirmed-with-a-narrowing (`docs/deviations.md` row 1); three surviving instances -- `Transport::REGISTRY`, `AsyncTransport::REGISTRY`, `Serde::REGISTRY` -- not "transport, serde, executor" as §11.8 says: there is no executor registry (8b's direct version assertion); re-read for §10.8 |
| `NFR-1` | MUST | ✅ | 13 | §10.7 | 0 | confirmed (`docs/deviations.md` row 7); phase 9's row ✅; the same claim's four mechanisms green |
| `NFR-8` | MUST | N/A | 13 | §10.19 | 0 | confirmed (`docs/deviations.md` row 19); N/A by its own text ("does not apply"). Phase 0's checklist marks it `🚫 retargeted`, phase 9's N/A; this checklist takes **N/A** as the convention for a retargeted vacuous requirement and records the departure from phase 0's mark (Deviations from the plan, 11) |
| `NFR-9` | SHOULD | N/A | 13 | §10.19 | 0 | confirmed (`docs/deviations.md` row 19); as `NFR-8`; its content that applies -- the allowlist still being the right list -- is the require-allowlist regeneration post-release trigger |
| `NFR-11` | SHOULD | ✅ | 12 | §10.3 | 0 | confirmed (`docs/deviations.md` row 3); a SHOULD (**level corrected** in 4c's, 5a's, 5b's and 5c's checklists, which said MUST) |

### Cross-reference rows

The 64 of the design plus the 17 added. Each names what phase 10 did and the owning phase whose row it
cross-references; the owning row is not re-marked. *Status* is the requirement's standing after phase 10,
with "unchanged" where phase 10 audited or documented and touched no code.

| ID | Level | Status | Task | Owner | What phase 10 did |
|---|---|---|---|---|---|
| `SEAM-11` | MUST | ✅ unchanged | 17 | 2 | amendment C5 (§3.2's `read_body` sentence); 8a's producer thread satisfies it |
| `SEAM-15` | MAY | ✅ unchanged | 7 | 2 | the `chapters` check's subject: appendix C is its only normative statement; the phase-8 segmentation design's misattribution fixed in place |
| `SEAM-28` | MAY | ⏳ unchanged (a MAY, deferred in §12) | 16 | 2 | `R7`: no carrier is built; the worked-example blocker gains the correlation chain |
| `HTTP-3` | MUST | ✅ unchanged | 17 | 1 | amendment C2 (§4's builder list omits the multipart body) |
| `HTTP-24` | MUST | ✅ unchanged | 10 | 1 | named by the plan for the `http/1.0` repair in error: `HTTP-24` is `MediaType`'s charset lookup and the repair is `HTTP-33`'s (see that row); also C1's |
| `HTTP-42` | MUST | ✅ unchanged | 17 | 3b | amendment C1 (§3.1's decode recipe) |
| `HTTP-43` | MUST | ✅ unchanged | 10 | 3b | named by the plan for the `http/1.0` repair in error: `HTTP-43` is `Response#close`; C5 touches it |
| `HTTP-51` | SHOULD | ✅ unchanged | 10b | 3b | MultipartBody's non-ASCII part names not widened -- `docs/first-release.md` port-readings entry (a) |
| `BODY-2` | MUST | ✅ unchanged | 17 | 3b | amendment C2 |
| `BODY-15` | MUST | ✅ unchanged | 17 | 3b | amendment C5 |
| `BODY-16` | MUST | ✅ unchanged | 17 | 3b | amendment C1 |
| `CTX-14` | MUST | ✅ unchanged | 16 | 4a | `Bundle#tracer_factory`'s YARD: CTX-14's span-tracer factory, not OBS-29's; pinned by `http_tracer_test.rb` |
| `CTX-16` | SHOULD | ✅ unchanged (4a's) | 16 | 4a | `R7`: conforming by the modal clauses; the correlation chain is the worked-example blocker's and a *Behavioural asymmetries* entry |
| `CTX-20` | SHOULD | ✅ unchanged | 16 | 4a | as `CTX-14` |
| `PIPE-2` | MUST | ✅ unchanged | 17 | 4c | amendment C6 (`Net::HTTP` retries by default; 8a sets `max_retries = 0`) |
| `PIPE-11` | MUST | ✅ unchanged | 16 | 4c | no ambient carrier added (`R6`, `R7`) |
| `PIPE-37` | MUST | ✅ unchanged | 16 | 4b | no `PRE_REDIRECT` step added (`R6`) |
| `RETRY-13` | MUST | ✅ unchanged | 17 | 6a | amendment C6 |
| `AUTH-35` | MUST | ✅ unchanged | 9, 10b | 6c | asserted under a reactor (`fiber_single_flight_test.rb`) and on the REFRESH path from a warm cache (`bearer_stamper_test.rb`, 6c's review R4-1) |
| `PAGE-14` | MUST | ✅ verified | 8 | 7c | `Page::PageStateError < ::StandardError` (`page/page_state_error.rb:17`), raised at `page/pages.rb:96`; `page_state_error_test.rb` refutes `ArgumentError`. `R8` not carried out (`P10-22`) |
| `SSE-19` | MAY | ✅ unchanged | 17 | 7b | amendment C11 (appendix C's row drops the chapter's port sanction) |
| `SSE-26` | MUST | ✅ verified | 8 | 7b | `SSE::StreamStateError` unchanged; one family per subsystem, neither in the argument family (`P10-22`) |
| `SSE-40` | SHOULD | ✅ verified | 8 | 7b | as `SSE-26` |
| `SERDE-2` | MUST | ✅ unchanged | 5 | 7a | `gates:spdx_rbs` finds no shipped `.rbs` empty of declarations (0 of 307); bullet 26 withdrawn by 7a |
| `OBS-4` | MUST | ✅ unchanged | 17 | 5b | amendment C4 (`Event#tag`) |
| `OBS-5` | MUST | ✅ unchanged | 17 | 5b | amendment C4; the Redactor's YARD now names where the three sources meet redaction |
| `OBS-8` | MUST | ✅ unchanged | 10b | 5b | `event_test.rb`'s race now asserts every racer parked before the gate opens (5b's review R3-3); also C4 |
| `OBS-19` | SHOULD | ✅ unchanged | 17 | 5b | amendment C7's header-drop scoping |
| `OBS-21` | MUST | ✅ unchanged | 16 | 5c | the span-tracer factory, distinguished from OBS-29's |
| `OBS-22` | MUST | ✅ unchanged | 16 | 5c | as `OBS-21` |
| `OBS-23` | MUST | ✅ unchanged | 16 | 5b | as `OBS-21` |
| `OBS-24` | MUST | ✅ repaired share | 10b | 5b | `AsyncStep` at BODY no longer counts the caller's continuation in the duration (5b's review R3-2), `async_step_test.rb` |
| `OBS-25` | MUST | ✅ unchanged | 16 | 5c | the no-op factory answers one tracer for every library (pinned) |
| `OBS-28` | SHOULD | ✅ unchanged | 16 | 5c | `HTTPTracer`'s YARD already states the contract |
| `OBS-29` | MUST | ✅ unchanged (5c's) | 16 | 5c | `R6`: documented contract, wiring a follow-up by its own text; the *Behavioural asymmetries* entry |
| `OBS-34` | MUST | ✅ unchanged | 16 | 5b | as `OBS-29` |
| `CFG-22` | MUST | ✅ repaired share | 10b | 5a | the proxy warning's credential belt unanchored: eight spellings of eight leaked on 4.0.6 and 3.2.11 before (5b's review R3-1); review round 0 (R0-4) found a password holding `/`, `?`, `#` or a second `@` still leaking its prefix past the unanchored belt, and the raw value is now scrubbed from the authority's start through the LAST `@` first -- fifteen spellings (the eight and seven more), none leaking, on 4.0.6 and 3.2.11; review round 1 (R1-1) added three whose password holds an `@` ahead of a reserved character, which only the through-the-LAST-`@` rule redacts -- eighteen |
| `CFG-23` | MUST | ✅ unchanged | 17 | 5a | bullet 20's proxy-ID substitution, corrected 2026-09-13 |
| `CFG-25` | MUST | ✅ unchanged | 17 | 5a | as `CFG-23` |
| `CFG-27` | MUST | ✅ unchanged | 17 | 5a | as `CFG-23` |
| `CFG-28` | MAY | ✅ unchanged | 17 | 5a | as `CFG-23` |
| `TRANSPORT-2` | MUST | ✅ unchanged | 17 | 8a | amendment C6 |
| `TRANSPORT-4` | MUST | ✅ unchanged | 17 | 8a | amendment C8; the conformance caveat blocker |
| `TRANSPORT-8` | MUST | ✅ unchanged | 17 | 8c | amendment C7 (second direction) |
| `TRANSPORT-13` | SHOULD | ✅ unchanged | 4 | 8c | `DropPolicy::MAX_TRACKED_NAMES`; beside the verified `Clients` cap |
| `TRANSPORT-14` | MUST | ✅ unchanged / waived on async_http | 3, 17 | 8a | the waiver re-measured green (`conformance_test.rb`'s "the two waived clauses are unreachable here"); amendment C7 |
| `TRANSPORT-17` | MUST | ✅ unchanged | 17 | 8a | amendment C6 |
| `TRANSPORT-18` | MUST | ✅ unchanged | 17 | 8a | amendment C6 |
| `TRANSPORT-19` | SHOULD | ✅ unchanged | 17 | 8a | amendment C5 |
| `TRANSPORT-25` | MUST | ✅ unchanged | 17 | 8a | amendment C5 |
| `TRANSPORT-28` | SHOULD | ⏳ unchanged (zero-copy clause) | 18 | 8a | `docs/first-release.md` § SHOULD- and MAY-level, unchanged |
| `TRANSPORT-29` | MUST | ✅ unchanged | 17 | 8a | amendment C5 |
| `TRANSPORT-30` | SHOULD | ✅ unchanged | 17 | 8a | bullet 28, fixed 2026-09-13 |
| `ASYNC-6` | MUST | ✅ unchanged | 9 | 8b | the fiber race runs inside the reactor the async transport uses |
| `XCUT-4` | MUST | ✅ unchanged | 17 | 9 | amendment C6 |
| `XCUT-11` | MUST | ✅ unchanged | 9 | 4c | fibers of one thread, asserted by thread identity in the fiber race |
| `XCUT-12` | SHOULD | ✅ (fiber form added) | 9 | 9 | `fiber_single_flight_test.rb`: one fetch for eight fibers against the real `BearerStamper` and `AsyncBearerStamper`; the trigger is closed |
| `XCUT-14` | MUST | ✅ verified | 4 | 9 | `AsyncHTTP::MAX_ORIGINS` 32, `Clients#drain`'s loop, eviction close, `#close` clear; `gates:bounded_map` green |
| `NFR-2` | SHOULD | ✅ unchanged | 17 | 0 | amendments C8 and C9 |
| `NFR-3` | SHOULD | ✅ unchanged | 5 | 0 | `gates:spdx_rbs` asserts every shipped signature declares something; `rbs validate` and `steep` green with the header |
| `NFR-4` | SHOULD | ✅ unchanged (phase 9's) | 18 | 0 | kept ✅: appendix C's `NFR-4` is a checked-in snapshot with drift failing the build, which `gates:surface_snapshot` is; the manifests regenerated once (two rows); `gates:sig_diff` stays vacuous without a tag (`P10-35`) |
| `NFR-6` | SHOULD | ✅ strengthened | 6 | 0 | `gates:sole_parse` asserts `AstScan.parse` is the one `RubyVM::AbstractSyntaxTree.parse_file` |
| `NFR-13` | SHOULD | ✅ (was ✅ / ⏳) | 5 | 0 | all 307 shipped `.rbs` carry the header; `gates:spdx_rbs` blocking; phase 9's `PackagingSuite` assertion now passes |
| `NFR-17` | MUST | ✅ strengthened | 2, 5, 6 | 0 | twenty-four blocking gates; `default_task_test.rb` and `ci_workflow_test.rb` assert the three new names |
| `HTTP-10` | MUST | ✅ repaired (MUST) | 10b | 1 | `Status` is total over every Integer (only a non-Integer is refused); the protocol range is `Status#standard?`. A first repair stopped at 0..999 and still threw on 1000 and -1, narrower than the MUST; review round 0 (R0-5) widened it |
| `HTTP-19` | MUST | ✅ repaired share | 10b | 1 | `HeaderSyntax`'s predicates, the lenient inbound one included, answer `false` for a non-String instead of raising `NoMethodError` (phase 1's review R3-4), `core/http/header_syntax_test.rb` "every predicate is total…" (repairs 6, Guards x3) |
| `HTTP-33` | MUST | ✅ repaired | 10 | 1 | `Protocol` gains `http/1.0` (WIRE_FORMS, ALIASES, `HTTP_1_0`); the negative case holds |
| `HTTP-47` | SHOULD | ✅ repaired (SHOULD) | 10b | 1 | `URL.parse!` refuses a host-less http-family URL and an unrenderable FTP typecode URI, and wraps every `URI::Error` |
| `BODY-9` | SHOULD | ✅ repaired share | 10b | 3b | `Body.stream` over an already-closed stream refuses it with `InvalidArgumentError` instead of letting a raw `IOError` escape (phase 3b's review R2-1), `core/http/body/stream_body_test.rb` "rejects an already-closed stream…" (repairs 7, Guards x4) |
| `TRANSPORT-22` | MUST | ✅ unchanged | 10 | 8a | the adaptation-failure tests now use an `HTTP/1.2` head |
| `TRANSPORT-24` | MUST | ✅ strengthened | 10b | 8a | a 600 or 999 head maps on both transports |
| `OBS-11` | MUST | ✅ repaired share | 10b | 5b | as `CFG-22` |
| `CFG-13` | SHOULD | ✅ repaired share | 10b | 5a | the property chain a repeated `Dexpace.configure` grew is flattened (5a's review R1-2), `config_test.rb` |
| `NFR-7` | SHOULD | ✅ repaired share | 10b | 0 | `rake rubocop` passes `--ignore-parent-exclusion` |
| `NFR-15` | SHOULD | ✅ repaired share | 10b | 0 | `PackagingCase`'s default name rule reaches all six gems |
| `REDIR-23` | SHOULD | ✅ unchanged | 10b | 6b | the wall-clock bound dropped; flatness is the proof |
| `RETRY-42` | MUST | ✅ unchanged | 10b | 6a | per-thread scripts; the interleaving dependence removed |
| `RECOV-28` | MUST | ✅ unchanged | 10b | 4b | as `RETRY-42` |
| `AUTH-34` | MUST | ✅ unchanged | 9 | 6c | single-flight under a reactor, asserted |
| `AUTH-37` | MUST | ✅ unchanged | 9 | 6c | the async stamper's coalescing under a reactor, asserted |
| `PIPE-39` | SHOULD | ✅ unchanged | 10b | 4c | the async preset's no-tracer-factory branch now asserted to thread `settings:` (6b's review R3-1) |

**Three IDs are named by phase 10's text and deliberately get no row** — `NFR-10`, `NFR-12`, `NFR-16` —
as the design's *64 cross-reference rows* section argues; phase 9 owns all three and phase 10 only walked
the `docs/first-release.md` lines that name them.

---

## What was built

- **Three blocking gates, twenty-four in all**, every body in `tools/` and every path joined to
  `gate_root` (`P9-27`'s lesson): `gates:ledger_audit` (`tools/ledger_audit.rb`: register row N's subject
  a word subsequence of §10 entry N's, its IDs EQUAL to the entry's, and a verdict row citing a real
  `gems/…` path and only defined `Dexpace::` constants — the rake task requires core and every adapter the
  interpreter's floor admits), `gates:spdx_rbs` (`tools/spdx_rbs.rb`: line 1 of every shipped `.rbs` is the
  SPDX header, and every shipped signature declares something) and `gates:sole_parse`
  (`tools/sole_parse.rb`: `AstScan.parse` is the one `RubyVM::AbstractSyntaxTree.parse_file` in `tools/`,
  `tasks/`, `test/gates/` and `.claude/skills/`, the exemption the owner METHOD, three test contrasts
  allowlisted with reasons). Each is in `DEFAULT_GATES` in the root `Rakefile` and in CI's `gates` job, and
  each is driven red through its rake task against a fixture workspace (`test/fixtures/gates/{ledger,
  spdx_rbs,sole_parse}/workspace`).
- **The probe's ninth check, `chapters`** (`.claude/skills/housekeeping/chapters.rb`), clause-scoped, with
  a backtick-tolerant range vocabulary, a negation vocabulary written as a `Regexp.union` of phrases, two
  stated gaps in `Chapters::GAPS`, and the two phase-8 pre-correction lines as committed regression
  fixtures. It found two live true positives, fixed in place.
- **The SPDX header on all 307 shipped `.rbs` files**, one line each; `rbs validate`, `steep`,
  `gates:rbs_surface` and `gates:sig_diff` unchanged by it, and phase 9's `PackagingSuite` `NFR-13`
  assertion now passes against the real tree.
- **`TransportSuite.run` on `Runner`**, the teardown supplied through the `around` wrapper so `Runner` is
  not widened.
- **The repairs in the table below**, every one test-first: Task 10's `Protocol` repair, Task 5's header, Task 3's fold and
  twenty of Task 10b's twenty-six items (its other six are the comment, YARD and document corrections listed
  after the table).
- **`docs/deviations.md`'s nineteen rows flipped**, each with as-built evidence, and **the amendment set
  written out as `C1`–`C19`**, with `docs/first-release.md`'s blocker naming all nineteen and the
  ledger-consolidation act beside them.
- **The fiber single-flight verification** (`async_http/fiber_single_flight_test.rb`) — a verification,
  not the repair `R9` planned (`P10-21`).

## Repairs, each with the test that is its audit

Every test below was run against the untouched `main` tree (the repair's own test files copied onto a
clean `git archive` of `b242de6`) before a line of `lib/` changed; the third column is what it printed
there. A pin whose test PASSED on `main` is a verification, and says so — its evidence is the mutation in
"Guards run red" that turns it red.

| # | Task | IDs | The failing test | What it printed on the untouched base |
|---|---|---|---|---|
| 1 | 10b | `OBS-11`, `CFG-22` | `core/instrumentation/downstream_wirings_test.rb` "R3-1, OBS-11, CFG-22: a credential after a slash reaches neither channel" | `Expected "[dexpace] proxy URL \"http:/user:secret@proxy.corp:3128\" has no explicit port; …" to not include "secret"` — 8 of 8 spellings leak, on 4.0.6 and 3.2.11 (a scratch probe over `Kernel#warn`) |
| 2 | 10 | `HTTP-33`, `TRANSPORT-24` | `core/http/protocol_test.rb` "parses HTTP/1.0 to its own canonical form…"; `net_http/response_mapper_test.rb` "an HTTP/1.0 head maps…" | `Dexpace::InvalidArgumentError: unrecognised protocol "HTTP/1.0"` (both) |
| 3 | 10b | `HTTP-10`, `TRANSPORT-24` | `core/http/status_test.rb` "maps every three-place code…", "standard? is the protocol's own range…"; `async_http/response_mapper_test.rb` "a vendor 999 status and an HTTP/1.0 head both map" | `InvalidArgumentError: code must be an integer status code between 100 and 599`; `NoMethodError: undefined method 'standard?'` |
| 4 | 10b | `HTTP-47` | `core/http/url_test.rb` "every malformed, unrenderable or host-less http URL fails with the SDK's error" | a failure: `mailto://host` raised `URI::InvalidComponentError`, `http:` parsed |
| 5 | 10b | `HTTP-5`, `XCUT-15` | `core/model_test.rb` "own takes a Hash with a default proc…", "own refuses a value it cannot make shareable…" | `TypeError: allocator undefined for Proc` |
| 6 | 10b | `HTTP-17`, `HTTP-18`, `HTTP-19` | `core/http/header_syntax_test.rb` "every predicate is total…" | `NoMethodError: undefined method 'b' for an instance of Integer` |
| 7 | 10b | `BODY-9`, `SEAM-29` | `core/http/body/stream_body_test.rb` "rejects an already-closed stream…" | a failure: a bare `IOError: closed stream` escaped |
| 8 | 10b | `CFG-15`, `CFG-17`, `CFG-18` | `core/clock_test.rb` "a NaN or a Complex duration is refused…"; `core/async/delay_test.rb` "a NaN or a Complex delay is refused…" | `Dexpace::InvalidArgumentError expected but nothing was raised` (NaN); `NoMethodError` (Complex) |
| 9 | 10b | `CFG-13` | `core/config_test.rb` "a lookup's depth does not grow with the number of configures" | `Expected: 22 / Actual: 222` |
| 10 | 10b | `OBS-24`, `OBS-34` | `core/instrumentation/async_step_test.rb` "at BODY the recorded duration excludes the caller's continuation" | `-[{amount: 250.0}] +[{amount: 5250.0}]` |
| 11 | 10b | `SEAM-1` | `gates/require_allowlist_test.rb` "refuses a dexpace/ path carrying a dot segment" | a failure: `dexpace/../json` and `dexpace/./../base64` accepted |
| 12 | 10b | `NFR-7` | `gates/rubocop_config_test.rb` "the gate ignores a parent checkout's exclusions…" | `Expected "task :rubocop do …" to include "--ignore-parent-exclusion"` |
| 13 | 10b | `NFR-15` | `conformance/packaging_suite_test.rb` "the default gem-name rule reaches all six…" | `Expected: "Dexpace" / Actual: "Dexpace::Core"` |
| 14 | 5 | `NFR-13`, `NFR-3` | `gates/spdx_rbs_test.rb` "every shipped signature in the six gems is clean"; `conformance/packaging_suite_test.rb` "NFR-13 against this repository's own shipped signatures passes" | 307 offences, 0 of them "declares nothing"; `Expected: :passed / Actual: :failed` |
| 15 | 2, 5, 6 | `NFR-17` | `gates/{ledger_audit,spdx_rbs,sole_parse}_test.rb`, `gates/default_task_test.rb` | `LoadError` (no tool file) and a twenty-one-gate count |
| 16 | 10b | `SEAM-5`, `XCUT-23` | `core/registry_test.rb` Termination (2 tests) | **passed** — a pin; phase 9's spin mutation turns it red |
| 17 | 10b | `AUTH-35` | `core/auth/bearer_stamper_test.rb` "every rejection holds on the REFRESH path too…" | **passed** — a pin for 6c's review R4-1; a validate-skipped-on-refresh mutant turns it red |
| 18 | 10b | `PIPE-39` | `core/pipeline/standard_test.rb` "settings: reaches the async retry step on the no-tracer-factory branch too" | **passed** — a pin for 6b's review R3-1 |
| 19 | 3 | `NFR-17` | `conformance/transport_suite_test.rb` "one run yields all five statuses in order…" | **passed** — the invariant of the fold, green before and after |
| 20 | 10b | `OBS-8` | `core/instrumentation/event_test.rb` "the terminal emit … happens once" gains a parking barrier | test quality (5b's review R3-3): without the barrier the "race" could be a sequential second call on 3.2 |
| 21 | 10b | `REDIR-23` | `core/redirect/step_test.rb` "a chain of 5,000 hops is followed iteratively" | test quality: the ten-second wall clock measured 10.6 s and 12.6 s under load (8a's record); the depth comparison is kept as the proof |
| 22 | 10b | `RETRY-42`, `RECOV-28` | `core/resilience/recovery_retry_test.rb` "eight concurrent calls … keep their budgets apart" | test quality: interleaving-dependent, red two runs in five under load on 3.2.11 (8a's review R1); now one script per thread |
| 23 | 10b | `IO-9`, `BODY-19`, `BODY-22`, `BODY-30`, `RECOV-16` | the four ceiling tests in `core/http/body_test.rb`, `core/http/body/response_body_test.rb`, `core/recovery_test.rb` | red under `MAX_MATERIALIZED_BYTES=4096` exported (4 failures), green after `test/support/pinned_ceiling.rb` |
| 24 | 10b | `CFG-11` | `core/configuration/builder_test.rb`'s seeded-builder case | red under `K=from-the-host` exported: `Expected "from-the-host" to be nil` |
| 25 | 16 | `CTX-14`, `OBS-25`, `OBS-29` | `core/instrumentation/http_tracer_test.rb` "the bundle's factory makes shared span tracers, never an HTTPTracer" | **passed** — a documentation repair; no test can go red for a YARD sentence, and this one pins the distinction it states |
| 26 | 9 | `XCUT-12`, `AUTH-34`, `AUTH-37` | `async_http/fiber_single_flight_test.rb` | **passed** — a verification (`P10-21`); the thread-identity guard mutant turns it red |
| 27 | review R0-4 | `OBS-11`, `CFG-22` | `core/instrumentation/downstream_wirings_test.rb` "R0-4, OBS-11, CFG-22: a password holding a reserved character leaks no prefix" | against repair 1's tree: `http:/user:pa/ss@h:1` warned `http:/user:pa/***:***@h:1` -- the username and the prefix before the reserved character, in `Kernel#warn` and the config sink, on 4.0.6 and 3.2.11 (the reviewer's measurement; the test's own red run is Guards 32) |
| 28 | review R0-5 | `HTTP-10`, `TRANSPORT-24` | `core/http/status_test.rb` "maps every Integer code …" and "construction is total over the Integer line"; `core/http/response_test.rb`'s two coercion cases | against the 0..999 tree: `InvalidArgumentError: code must be an integer status code between 0 and 999` for `-1`, `1000` and `2**70` |
| 29 | review R0-8 | — (process tooling) | `housekeeping/chapters_test.rb` "an appears-in attribution binds forward and fires when wrong", "a second appears-in run does not bind backward" | against the round-0 check: the wrong attribution is silent (`Expected: ["SEAM-15"] Actual: []`) |

Beside these, comment and YARD repairs that no test can observe: `Redactor`'s class YARD names where
redaction is applied (5b's review R3-4); `Cancellation::Source#off_cancel`'s comment no longer says
`Proc#==` is identity (measured false on all four rows; phase 2's review R3-3); `dexpace_test.rb`'s
"five public Resilience constants" is six (6a's review R2-1); `rbs_collection.yaml`'s header; the
`@decode_content` and `@owned`/`@dexpace_owns_upstream` YARD unknown-tag warnings; the `ResponseMapper`
YARD in both transports; `Bundle#tracer_factory`'s YARD (Task 16); and
`InvariantGates::BOUNDED_MAP_ALLOWED`'s `clients.rb` reason now citing its three tests.

## Inbound list, dispositioned

All sixty-five bullets of the roadmap's phase-10 inbound list, by position, date and content (the
first thirty-two are those of 2026-09-13; thirty-three were added after the design). Each bullet carries
the same disposition as a dated bracket in the roadmap. **18 repaired · 14 verified already fixed ·
32 moved to `docs/first-release.md` (thirteen of them the amendment set) · 1 withdrawn** — none carried
forward.

| # | Date | Bullet | Disposition | Evidence |
|---|---|---|---|---|
| 1 | 2026-09-13 | The audit of the §10.5 ledger | `docs/first-release.md` | §10.5 audited, not re-opened: `docs/deviations.md` row 5 carries the verdict with `ASYNC-3` waived-would-fail in the pool's driver; the gap stays `docs/first-release.md` § Unsatisfied MUSTs |
| 2 | 2026-09-13 | `OBS-29`'s surface decision, which is three findings and one decision. | `docs/first-release.md` | decided with no surface (`R6`): `OBS-29`'s own follow-up clause; `Bundle#tracer_factory`'s YARD now says it is CTX-14's span-tracer factory and not OBS-29's, pinned by `http_tracer_test.rb`; the unwired groups are a *Behavioural asymmetries* entry |
| 3 | 2026-09-13 | The probe's "this ID is stated in chapter X" claim check, which is not built. | repaired | built as the probe's ninth check, `chapters` (`.claude/skills/housekeeping/chapters.rb`, `test/chapters_test.rb`); two live true positives fixed in the phase-8 segmentation design |
| 4 | 2026-09-13 | The judgement whether the thread-only `XCUT-12` form phase 9 ships in Tasks 7–8 suffices | verified already fixed | judged and verified: the fiber form passes on the untouched tree (no deadlock), now asserted in `fiber_single_flight_test.rb`; the fallback trigger is closed |
| 5 | 2026-09-13 | The repairs of every audit phase 9 reports `:failed` | verified already fixed | the one `:failed` (`NFR-13`) is repaired by Task 5; `ASYNC-3`'s waiver stands per §10.5; no other `:failed` exists |
| 6 | 2026-09-13 | `dexpace-transport-async_http`'s `Clients#@by_origin` is an uncapped per-origin client cache, which   `XCUT-14` (MUST) forbids. | verified already fixed | already closed by phase 9 (green `gates:bounded_map`, 2026-09-23); the allowlist reason now cites `clients_test.rb`'s three `XCUT-14` cases |
| 7 | 2026-09-13 | 8a's `Adapter#dispatch` leaves its rescue variable unused — first half CLOSED 2026-09-13 — and every   repository tool that parses a filed s… | repaired | the general half built as `gates:sole_parse` (`tools/sole_parse.rb`, `test/gates/sole_parse_test.rb`) |
| 8 | 2026-09-13 | `NFR-13`'s SPDX gate is a RuboCop cop, so it cannot reach `sig/ | repaired | the SPDX header on all 307 shipped `.rbs` files plus `gates:spdx_rbs`; `packaging_suite_test.rb`'s `NFR-13` pin flipped to `:passed` |
| 9 | 2026-09-13 | The `PAGE-15`/`P7-1` and §10.5 attribution notes in `docs/deviations.md` | `docs/first-release.md` | written out as amendments `C12` and `C13` in `docs/deviations.md`; applying them is the frozen-chapter blocker's |
| 10 | 2026-09-13 | Any `gates:bounded_map` that runs red. | verified already fixed | every run green (`gates:bounded_map`, phase 10's tips) |
| 11 | 2026-09-13 | §3.1's decode recipe destroys every non-ASCII byte, and its target-less `#encode` follows a process   global. | `docs/first-release.md` | amendment `C1`, written out; the blocker |
| 12 | 2026-09-13 | §4's builder list drops the multipart body, which `HTTP-3` names. | `docs/first-release.md` | amendment `C2`, written out; the blocker |
| 13 | 2026-09-13 | §3.1's ownership sentence and §10.12 attribute `IO-6`'s rule to the retired `SEAM-3`. | `docs/first-release.md` | amendment `C3`, written out; `IO-6` audited on its own row (ownership-on-wrap measured) |
| 14 | 2026-09-13 | §8.1 names `Event#tag(key, value)` and no requirement in chapter 15 does. | `docs/first-release.md` | amendment `C4`, written out; the blocker |
| 15 | 2026-09-13 | §3.2's block-scoped `read_body` construction cannot satisfy the two requirements it says it satisfies   "literally". | `docs/first-release.md` | amendment `C5`, written out; the blocker |
| 16 | 2026-09-13 | `Net::HTTP` has a built-in automatic retry that is on by default, and §3.2, §11.18 and §12 all record that   it has none. | `docs/first-release.md` | amendment `C6`, written out; the blocker |
| 17 | 2026-09-13 | `TRANSPORT-14`'s malformed-inbound-header-*name* clause is unreachable on   `dexpace-transport-async_http`, and §12 records `TRANSPORT-14` a… | `docs/first-release.md` | amendment `C7` (first direction), written out; the waiver re-measured green by `conformance_test.rb` |
| 18 | 2026-09-13 | `TRANSPORT-8` is satisfiable on `dexpace-transport-async_http`, and §12 counts it among the eight MUSTs   that hold vacuously — the inverse … | `docs/first-release.md` | amendment `C7` (second direction), written out |
| 19 | 2026-09-13 | §8.3's prohibition is absolute and `net-http`'s connect phase uses `Timeout.timeout`, which the cop that   enforces the ban cannot see. | `docs/first-release.md` | amendment `C8`, written out with the per-row measurement (net-http 0.9.1 carries both the `Timeout.timeout` connect and `TCPSocket.open(open_timeout:)`) |
| 20 | 2026-09-13 | Phase 5a's exclusions table hands proxy use to phase 8 under two requirement IDs that are about   something else, and it is the second docum… | verified already fixed | fixed in place on 2026-09-13 by phase 10's planning; re-read 2026-09-25 |
| 21 | 2026-09-13 | §9.3 calls Minitest a default gem; it is a bundled gem, and §2.4 is built on exactly that   distinction. | `docs/first-release.md` | amendment `C9`, written out |
| 22 | 2026-09-13 | §9.3 fixes the requirement ID as the *waiver's* unit and leaves the *report's* unit unstated, and an   appendix-B item cannot be it. | `docs/first-release.md` | amendment `C10`, written out |
| 23 | 2026-09-13 | Nothing in the MVP constructs or promotes an execution context, so `CTX-16`'s operation name never   reaches the tracing seam it is defined … | `docs/first-release.md` | decided with no surface (`R7`); the correlation chain joins the worked-example blocker and the *Behavioural asymmetries* entry |
| 24 | 2026-09-13 | `PAGE-14` and `SSE-26`/`SSE-40` guard the identical single-use latch with two different error families,   and the divergence has to be settl… | verified already fixed | the premise is gone: 7c raises `Page::PageStateError < ::StandardError` (`page/page_state_error.rb:17`), refuted as an ArgumentError by `page_state_error_test.rb`; `R8` not carried out (`P10-22`) |
| 25 | 2026-09-13 | Appendix C's `SSE-19` row drops the port sanction the chapter carries, and `docs/product-spec/` is   frozen. | `docs/first-release.md` | amendment `C11`, written out; also a recommendation to the specification author |
| 26 | 2026-09-13 | Phase 2's three other declared-and-unwritten `sig/` files, which no gate can see. | withdrawn | withdrawn by 7a on 2026-09-20 (premise false on the tree); `gates:spdx_rbs`'s empty-declarations check finds 0 of 307 |
| 27 | 2026-09-13 | `Dexpace::Protocol.parse` has no alias for `"http/1.0"`, so a real `HTTP/1.0` response makes   `ResponseMapper` raise. | repaired | `Protocol` gains `http/1.0` in `WIRE_FORMS` and `ALIASES` and `Protocol::HTTP_1_0` (`HTTP-33`); both adapters map an HTTP/1.0 head |
| 28 | 2026-09-13 | 8a's forward-obligations row for the two declined `TRANSPORT` SHOULDs is half stale. | verified already fixed | fixed in place on 2026-09-13 by phase 10's planning |
| 29 | 2026-09-13 | `APPENDIX_B.md`'s check 2 is weaker than the prose that specifies it. | verified already fixed | already done by phase 9: `tools/appendix_b.rb` and `test/gates/appendix_b_test.rb`'s set-equality test |
| 30 | 2026-09-13 | `TransportSuite` is not on `Runner`, leaving two status-deciding paths in one gem. | repaired | `TransportSuite.run` delegates to `Runner.run` with the teardown supplied through `around:`; the five-status invariant test in `transport_suite_test.rb` |
| 31 | 2026-09-13 | A design document that promised a shape the code did not take is phase 10's doc repair. | verified already fixed | a method, applied: each audit row names its as-built evidence (`docs/deviations.md`), and every design found wrong is bracket-corrected in place |
| 32 | 2026-09-13 | The `minitest` pin's ownership. | `docs/first-release.md` | re-measured 2026-09-25; the Minitest trigger's numbers corrected in `docs/first-release.md`; the pin stays phase 0's |
| 33 | 2026-09-14 | The process tooling is outside the RuboCop baseline. | `docs/first-release.md` | `docs/first-release.md` § Post-release triggers, the residues line: `.rubocop.yml` and `scripts/` stayed outside phase 10's file list |
| 34 | 2026-09-14 | `rake rubocop` passes vacuously in a worktree nested under the parent checkout's `.claude/`. | repaired | `--ignore-parent-exclusion` on the gate's command, asserted by `rubocop_config_test.rb` |
| 35 | 2026-09-15 | Nine later-phase design documents cite a retired corpus key, `data-modeling/5bc538ba`, as narrowing the   wire model's Ractor-shareability c… | repaired | each of the eight designs carries a dated bracket naming the retired key and `P1-13` |
| 36 | 2026-09-15 | `Dexpace::URL.parse!` accepts a host-less `http:` and any absolute non-HTTP URI, so a `Request` can carry a   URL no transport can dispatch,… | repaired | `URL.parse!` refuses a host-less http-family URL and wraps every `URI::Error` (`HTTP-47`); which other schemes dispatch stays the transport's call |
| 37 | 2026-09-16 | `MultipartBody` refuses a non-ASCII part name or filename, because its part-header sweep is the outbound   header grammar. | `docs/first-release.md` | not taken: `docs/first-release.md` § Behavioural asymmetries, the port-readings entry (a) |
| 38 | 2026-09-16 | Phase 0's plan says the keyword-splat cop "carries no ordinal" and that phase 4a's cop is "the seventh";   every as-built document counts it… | repaired | phase 0's plan carries a dated bracket with the as-built count (eight) |
| 39 | 2026-09-17 | `Fiber[:k] = nil` retains the key with a `nil` value on Ruby 3.2, and `Fiber["k"]` raises `TypeError`   on 3.2 and 3.3 — two carrier facts t… | repaired | 5b's plan, 8b's plan and the phase-5 charter carry a dated bracket naming the floor facts |
| 40 | 2026-09-17 | Phase 5b's design states two verified facts that the as-built code no longer rests on: fact 6's   rebuild route (`u.userinfo = " | verified already fixed | already corrected in 5b's design As-built addendum; a dated bracket at the fact now points there |
| 41 | 2026-09-17 | The warnings-fatal gate runs every gem suite in one process, and Ruby 3.4+'s unused-block warning   is suppressed process-wide once any same… | `docs/first-release.md` | `docs/first-release.md` § Post-release triggers, the residues line (`-W:strict_unused_block`) |
| 42 | 2026-09-17 | Four phase-3b and phase-4b tests assert the default materialisation ceiling and read the live one,   so an exported `MAX_MATERIALIZED_BYTES`… | repaired | the four tests pin the default ceiling at the override tier (`test/support/pinned_ceiling.rb`); red under `MAX_MATERIALIZED_BYTES=4096` before, green after |
| 43 | 2026-09-18 | Phase 6a's design describes an async retry pump that recurses, and states the opposite. | verified already fixed | already corrected in 6a's design As-built addendum (`P6-54`); a dated bracket at the sketch now points there |
| 44 | 2026-09-18 | After phase 6 the body-replayability predicate has three spellings, two of them public and   `NFR-4`-locked. | `docs/first-release.md` | not unified: the one-time surface-choices blocker in `docs/first-release.md` names the three spellings |
| 45 | 2026-09-19 | An explicit scheme-default port is elided at phase 1's model boundary, and a redirect target   inherits it. | `docs/first-release.md` | recorded as a port reading: the one-time surface-choices blocker names the default-port elision (`HTTP-46`) |
| 46 | 2026-09-20 | After a mid-stream failure, `BufferedSource.over`'s enumerator restarts `#each` from its first   chunk, so a further read re-delivers the bo… | `docs/first-release.md` | `docs/first-release.md` § Behavioural asymmetries, port-readings entry (d) |
| 47 | 2026-09-20 | The per-byte read path through `BufferedSource#getbyte` costs about 0.9 µs a byte, so the SSE line   machine parses at roughly 1 MiB/s on 4.… | `docs/first-release.md` | `docs/first-release.md` § Post-release triggers, the residues line |
| 48 | 2026-09-20 | `gates:clean_bundle` installs into the interpreter's own gem directory, and the first adapter with a   third-party dependency makes that a n… | verified already fixed | closed by 8a's Task 23 on 2026-09-21 (its own bracket) |
| 49 | 2026-09-20 | `rbs_collection.yaml`'s header comment is stale: "json arrives with dexpace-serde-json's codec in   phase 7", and phase 7a added no row. | repaired | `rbs_collection.yaml`'s header rewritten to what the file holds |
| 50 | 2026-09-20 | `net-http`'s connect-phase `Timeout.timeout` has an observable: the first connection in a process   starts Ruby's process-wide `Timeout` thr… | `docs/first-release.md` | amendment `C8` carries the clause; the warm-up stays |
| 51 | 2026-09-20 | rbs 4.2.0 types `TCPServer#initialize` as `(?String host, Integer port)` — an optional positional   before a required one — and Steep 2.1.0 … | verified already fixed | the bundle's rbs is still 4.2.0 on every row, so the `untyped` local in `WireServer#initialize` stays; nothing to remove |
| 52 | 2026-09-20 | Phase 6b's `REDIR-23` proof carries a ten-second wall-clock bound over 5,000 hops, and the bound   fails under machine load while the stack-… | repaired | the ten-second bound is gone; the depth comparison is the proof (`step_test.rb`) |
| 53 | 2026-09-20 | Phase 6a's `RETRY-42` / `RECOV-28` eight-thread budget test is interleaving-dependent, and errors   under the whole-repository process on a … | repaired | each thread draws from its own script and the invariant is asserted per thread (`recovery_retry_test.rb`) |
| 54 | 2026-09-20 | `Dexpace::Status` guards `100`–`599` while `Net::HTTP` parses any three-digit code, so a `999` or a   `600` head raises `Dexpace::InvalidArg… | repaired | a MUST repair (`HTTP-10`): `Status` maps every Integer code and the protocol range is `Status#standard?` |
| 55 | 2026-09-21 | Two child-process idioms prove one property — `seam_surface_test.rb`'s private   `bare_require_report` and `test/support/bare_require.rb`'s … | `docs/first-release.md` | `docs/first-release.md` § Post-release triggers, the residues line |
| 56 | 2026-09-21 | Under the one-process `rake test:gems` the main fiber's storage carries 5c's no-op span   (`dexpace.current_span => Instrumentation::NO_SPAN… | `docs/first-release.md` | `docs/first-release.md` § Post-release triggers, the residues line |
| 57 | 2026-09-21 | Core's two duration guards, `Dexpace::Async.validate_delay` and `Dexpace::Clock::Guard.duration`,   admit a `NaN` and a `Complex`. | repaired | `Async.validate_delay` and `Clock::Guard.duration` refuse NaN and Complex (P8-77's shape), tested in `delay_test.rb` and `clock_test.rb` |
| 58 | 2026-09-21 | Two of phase 8c's design facts are stale on `async` 2.46.0, and `async-http`'s server lets a   peer's mid-head `EOFError` reach Console. | `docs/first-release.md` | read in 8c's As-built addendum; the Console report is an upstream matter -- the residues line |
| 59 | 2026-09-21 | The portable `TRANSPORT-7` row proves its delivered-body clause by chance against a streaming   adapter. | `docs/first-release.md` | `docs/first-release.md` § Post-release triggers, the residues line |
| 60 | 2026-09-23 | `Dexpace::Registry#resolve`'s discovery loop has no bound. | repaired | a termination argument at `Registry#resolve` and `registry_test.rb`'s Termination suite, which phase 9's spin mutation turns red |
| 61 | 2026-09-23 | `XCUT-12`'s fiber-scheduler form is unasserted, and the checklist row says so. | verified already fixed | verified as `XCUT-12`'s fiber form (`fiber_single_flight_test.rb`) |
| 62 | 2026-09-23 | `XCUT-9`'s cycle assertion has two stated residues, and `gates:cause_walk` proves neither absent. | `docs/first-release.md` | `docs/first-release.md` § Post-release triggers, the residues line |
| 63 | 2026-09-23 | 7a's `SEAM-21` evidence lives inside another assertion's body and is declared in no ID-keyed map. | `docs/first-release.md` | `docs/first-release.md` § Post-release triggers, the residues line |
| 64 | 2026-09-23 | `tools/surface.rb` cannot see a `private_constant` module, so a group that became public would be   invisible to `gates:surface_snapshot` un… | `docs/first-release.md` | `docs/first-release.md` § Post-release triggers, the residues line |
| 65 | 2026-09-23 | `Dexpace::Conformance::PackagingCase`'s default gem-name → constant-path rule covers none of this   port's exceptional four. | repaired | `PackagingCase`'s default rule covers all six gems (`-core` is the root, `http`/`json` are acronyms), tested in `packaging_suite_test.rb` |

## Leftover review items, dispositioned

The review nits and stated gaps the earlier phases' final reviews left open and routed nowhere — found in
the maintainer's per-phase leftover notes by the cross-check that opened this phase, not on the inbound
list. Each is re-measured on the tree before it is dispositioned.

| Source | Item | Still present on `main`? | Disposition |
|---|---|---|---|
| 5b R3-1 | the proxy warning's credential belt, anchored | yes, 8 of 8 spellings on 4.0.6 and 3.2.11 | **repaired** (repairs 1) |
| 5b R3-2 | `AsyncStep` at BODY counts the caller's continuation | yes (5250 ms against 250) | **repaired** (repairs 10) |
| 5b R3-3 | `OBS-8`'s race test probabilistic on 3.2 | yes | **repaired** (repairs 20) |
| 5b R3-4 | `Redactor`'s YARD omits its application point | yes | **repaired** (YARD) |
| 5a R1-2 | the property chain grows per configure | yes (depth 22 → 222) | **repaired** (repairs 9) |
| 5a R1-1 | `builder_test.rb` reads the host's `K` | yes | **repaired** (repairs 24) |
| 5c R0-1 | "thirteen cross-reference rows" against eleven rows / fourteen IDs | yes | **repaired**: a dated bracket in 5c's checklist |
| 5c R0-2 | `Fiber#storage=` in a fact-pin test | yes | not taken: judged no action by 5c; a fact pin, which warns by design |
| 5c | the probe's `claims` check does not read CLAUDE.md's spelled lib-file count | yes | not taken; counted by hand for this phase's CLAUDE.md edit -- `docs/first-release.md`'s post-release residues line, with its pick-up condition |
| 0 R3-2 | `require_allowlist.rb` accepts `dexpace/../json` | yes | **repaired** (repairs 11) |
| 0 R3-3 | CLAUDE.md's "32 inbound bullets" | yes | **repaired** in CLAUDE.md |
| 0 R3-4, R3-6, R3-7 | gate tests resolve `ruby`/`bundle` from PATH; a category assertion run once; a third-party sub-feature refused | yes | `docs/first-release.md` residues line |
| 1 R3-1 | `Model.own` leaks TypeError for a default-proc Hash | yes | **repaired** (repairs 5) |
| 1 R3-3 | `Query.parse` strips a trailing NUL | yes | `docs/first-release.md` port-readings entry (b) |
| 1 R3-4 | `HeaderSyntax` predicates raise on a non-String | yes | **repaired** (repairs 6) |
| 2 R3-1, R3-2 | `mailto://host` and `ftp…;type=x` leak URI errors | yes (`InvalidComponentError`; a `FrozenError` from `#to_s`) | **repaired** (repairs 4) |
| 2 R3-3 | the comment "Proc#== is identity" | yes, and false on all four rows (`a == a.dup` is true) | **repaired** (comment) |
| 3a | three `untyped` signature params; `TeeSink`'s Float `tap_limit` refusal; an ASCII-only tee test | yes | `docs/first-release.md` residues line |
| 3b R2-1 | `Body.stream(closed)` raises a raw IOError | yes | **repaired** (repairs 7) |
| 4a-8c | the one-time public-surface choices "decide before the first tag" | yes | **one `docs/first-release.md` blocker** enumerating them |
| 6a R2-1 | `dexpace_test.rb`'s "five" Resilience constants (six) | yes | **repaired** (comment) |
| 6a R2-2 | the async pump's close-before-schedule order unpinned | yes (an equivalent mutation) | `docs/first-release.md` residues line |
| 6b R3-1 | `AsyncPipeline.standard`'s `settings:` on the no-factory branch unasserted | yes | **repaired** (repairs 18) |
| 6c R4-1 | the sync stamper's refresh-path rejections unpinned | yes | **repaired** (repairs 17) |
| 7a R2-1 | `serde.md`'s fence lacks `require "stringio"` | yes | **repaired** in `docs/sdk-documentation/serde.md`, the fence run on 4.0.6 and 3.2.11 |
| 7a R2-2, R2-3 | a CLAUDE.md overstatement; a roadmap count | superseded by this phase's CLAUDE.md and roadmap edits | re-derived, not patched |
| 7b R1-2 | an 11+-digit zero-padded `retry:` is ignored | yes | `docs/first-release.md` port-readings entry (c) |
| 7b R1-1 | `sse.md`'s `#with` sentence and fence names | not re-measured | not taken -- `docs/first-release.md`'s post-release residues line, picked up at the next edit to `sse.md` |
| 7c R2-1 | a non-`Response` duck never closed after a parse | yes | `docs/first-release.md` residues line |
| 9 | the YARD unknown-tag warning `@decode_content` | yes | **repaired** (YARD), with 3a's `@owned` pair |

## Guards run red

Every mutation below was applied to the tree at the end of this phase, the owning test or gate run, the
first failure captured and the file restored — through one harness, on **4.0.6** unless the row says
otherwise. The list is the brief's thirty-one-item minimum where it applies (items 17 and 18 do not:
`R8` was not carried out) plus the repairs' own mutants.

| # | Mutation | Caught by (first failure) | IDs |
|---|---|---|---|
| 1 | Delete the header from one shipped `.rbs` (`dexpace-core/sig/dexpace/http/status.rbs`) | `gates:spdx_rbs`: "…/status.rbs: line 1 is not `# SPDX-License-Identifier: MIT` (NFR-13)"; `conformance/packaging_suite_test.rb` "NFR-13 against this repository's own shipped signatures passes": `Expected: :passed / Actual: :failed` | `NFR-13` |
| 2 | Put that header on line 3, two blank lines first | `gates:spdx_rbs` red on "line 1 is not …". **No asymmetry**: the brief expected `PackagingCase` to stay green (it reads two lines); measured, its `NFR-13` assertion goes red too (`Expected: :passed / Actual: :failed`) | `NFR-13` |
| 3 | `declarations.empty?` → the plan's `parse_signature(…).flatten.compact.empty?` | `gates/spdx_rbs_test.rb` "a signature with no declarations is an offence" (the Buffer survives the flatten, so the empty file is clean) | `NFR-3` |
| 4 | A direct `RubyVM::AbstractSyntaxTree.parse_file(path)` added to `tools/sole_parse.rb` itself | `gates:sole_parse`: "tools/sole_parse.rb:29: RubyVM::AbstractSyntaxTree.parse_file outside AstScan.parse (NFR-6)" | `NFR-6` |
| 5 | The same through `.send(:parse_file, path)`, and through `.public_send("parse_file", path)` | `gates:sole_parse`, the same message for each | `NFR-6` |
| 6 | Drop the `RubyVM::AbstractSyntaxTree` receiver scope | `gates/sole_parse_test.rb` "the repository has exactly one …": `tools/gemspec_audit.rb:78` and the other `Prism.parse_file` sites reported — the scope is load-bearing | `NFR-6` |
| 7 | Each new gate's rake task pointed at its fixture workspace (`DEXPACE_GATE_ROOT=test/fixtures/gates/{ledger,spdx_rbs,sole_parse}/workspace`) | exit 1 each: "row 1 ID set differs: chapter-only IO-6"; "…/probe.rbs: line 1 is not …"; "tools/x.rb:… parse_file outside AstScan.parse" — driven by `ledger_audit_test.rb`, `spdx_rbs_test.rb` and `sole_parse_test.rb` through `rake`, and re-run by hand at the code tip | `NFR-17` |
| 8 | `docs/deviations.md` row 8 loses `XCUT-23` | `gates:ledger_audit`: "row 8 ID set differs: chapter-only XCUT-23" | `NFR-17` |
| 9 | Rows 13 and 14 swapped | `gates:ledger_audit`: "row 13 subject drifted from entry 13", "row 14 subject drifted from entry 14", and both rows' ID sets | `NFR-17` |
| 10 | Row 2's verdict cites only `docs/sdk-design-ruby/10-…md` | `gates:ledger_audit`: "row 2 carries a verdict and no resolvable as-built evidence (P10-2)" | `NFR-17` |
| 11 | Row 7's verdict names `Dexpace::Completer` | `gates:ledger_audit`: "row 7 names Dexpace::Completer, which is not defined" — the task loaded the gems | `NFR-17` |
| 11a | Row 7 loses `OBS-2`; row 2 carries row 1's title; row 1 names `Dexpace::IO::Bufferz`; row 7 cites `basic_handlerz.rb` | `gates:ledger_audit`, each with its own line ("chapter-only OBS-2", "row 2 subject drifted", "not defined", "which does not exist") | `NFR-17` |
| 11b | `LedgerAudit#drift` stops reporting row-only IDs (a subset test, not equality) | **survived the first run** — no test gave a row a WIDER set. `ledger_audit_test.rb` gained "a row whose ID set is WIDER … equality, not a subset" over `register_extra_ids.md`; now red: `-["row 2 ID set differs: row-only BODY-9"]` | `NFR-17` |
| 11c | `LedgerAudit#evidence` never checks (`return []`) | `ledger_audit_test.rb`: the docs-only and the undefined-constant cases | `NFR-17` |
| 11d | `SpdxRbs` accepts the header anywhere in the first three lines | `spdx_rbs_test.rb` "a header that is present but not on line 1 is an offence" | `NFR-13` |
| 12 | `gates:ledger_audit` removed from `DEFAULT_GATES`; `gates:spdx_rbs` removed from `ci.yml` | `gates/default_task_test.rb`: "the default task's prerequisite count drifted. Expected: 24 Actual: 23"; `gates/ci_workflow_test.rb` red | `NFR-17` |
| 13 | `resolution.rb`'s belt back to the anchored `sub(/\A[^\/?#]*@/, …)` | `core/instrumentation/downstream_wirings_test.rb` "R3-1 …": `Expected "[dexpace] proxy URL \"http:/user:secret@proxy.corp:3128\" has no explicit port; …" to not include "secret"` — 4.0.6 and 3.2.11 | `OBS-11`, `CFG-22` |
| 14 | `"http/1.0"` dropped from `ALIASES` only; then from `WIRE_FORMS` only | `core/http/protocol_test.rb`: `InvalidArgumentError: unrecognised protocol "HTTP/1.0"`; the second fails at load: `Protocol#initialize: wire must be one of: http/1.1, http/2` from `HTTP_1_0 = build(…)` | `HTTP-33` |
| 15 | `"http/0.9" => "http/1.0"` added to `ALIASES` | `core/http/protocol_test.rb` "raises on an unrecognised identifier, naming it": `http/0.9. Dexpace::InvalidArgumentError expected but nothing was raised` | `HTTP-33` |
| 16 | `net_http`'s `ResponseMapper` over an `HTTP/1.0` head, the alias removed | `net_http/response_mapper_test.rb`: `InvalidArgumentError: unrecognised protocol "HTTP/1.0"` | `HTTP-33`, `TRANSPORT-24` |
| 17, 18 | (Task 8 mutants) | **not run**: `R8` was not carried out (`P10-22`), so there is no re-parenting to mutate | — |
| 19 | `BearerStamper#refresh!`'s `synchronize` replaced by a thread-identity guard (re-entry on the owning thread passes through) | `async_http/fiber_single_flight_test.rb`: "a refresh under one reactor was not single-flight. Expected: 1 Actual: 8" — 4.0.6 and 3.3.12 | `XCUT-12`, `AUTH-34` |
| 20 | The racers run as `::Thread.new` instead of `task.async` | the same file: `NoMethodError: undefined method 'wait' for an instance of Thread` before the one-thread assertion (`threads.uniq.size == 1`) is reached, and the base case's thread-count teardown (`Expected: 9 / Actual: 17`) — red, though not on the identity assertion the brief named | `XCUT-12` |
| 21 | `Model.own` without the default-proc strip | `core/model_test.rb`: `InvalidArgumentError: a model cannot own this collection: allocator undefined for Proc` | `HTTP-5`, `XCUT-15` |
| 22 | `Clock::Guard`'s NaN screen removed | `core/clock_test.rb` "CFG-15, CFG-17: a NaN or a Complex duration is refused …": `NaN. Dexpace::InvalidArgumentError expected but nothing was raised` | `CFG-15`, `CFG-17` |
| 23 | `Async.validate_delay`'s `real?` screen removed | `core/async/delay_test.rb`: `(1+1i). [Dexpace::InvalidArgumentError] exception expected, not Class: <NoMethodError>` | `CFG-18` |
| 24 | `Configuration::Builder#composed_source` back to nesting per configure | `core/config_test.rb` "CFG-13: a lookup's depth does not grow …": `Expected: 26 / Actual: 626` | `CFG-13` |
| 25 | `AsyncStep`'s end-time `on_settle` removed (the pre-repair attach order) | `core/instrumentation/async_step_test.rb` "at BODY the recorded duration excludes the caller's continuation": `-[{amount: 250.0}] +[{amount: 5250.0}]` | `OBS-24`, `OBS-34` |
| 26 | `reachable?` back to `start_with?("dexpace/")` | `gates/require_allowlist_test.rb` "refuses a dexpace/ path carrying a dot segment": `"" to include "dot_segments.rb:6"` | `SEAM-1` |
| 27 | `--ignore-parent-exclusion` removed from the rubocop task | `gates/rubocop_config_test.rb`: `Expected "task :rubocop do …" to include "--ignore-parent-exclusion"` | `NFR-7` |
| 28 | `REDIR-23`: the ten-second wall-clock bound re-added; then the step made recursive | the bound: **nothing red** (as intended: it was never the proof); the recursion: `core/redirect/step_test.rb` "a chain of 5,000 hops is followed iteratively": `Expected: 27 / Actual: 5027` | `REDIR-23` |
| 29 | The `chapters` check's range pattern disabled | `housekeeping/chapters_test.rb` "the phase8a pre-correction line fires on all three wrong ids" and one more | — (process tooling) |
| 30 | `Checks::Chapters` dropped from `Probe::ALL` | `housekeeping/probe_test.rb` "check names are the nine the documentation states" | — |
| 31 | `Bundle#tracer_factory`'s YARD | **no test can go red for a YARD sentence**; `http_tracer_test.rb` pins the distinction it states (repairs 25) | `CTX-14`, `OBS-29` |
| 32 | `ProxyResolution#scrub_userinfo` returns the raw value (review round 0's R0-4 repair disabled) | `core/instrumentation/downstream_wirings_test.rb` "R0-4 …": the first spelling's warning includes `pa/` -- red on 4.0.6 | `OBS-11`, `CFG-22` |
| 32a | `AUTHORITY_START` admits a bare `user:` as a scheme (`/+` → `/*`) | **survived, equivalent**: `user:***:***@…` is then reduced to `***:***@…` by the unanchored belt that runs after the redactor, so no channel ever carries the username; recorded, not a gap | `OBS-11` |
| 33 | `Status#initialize` back to the 0..999 range | `core/http/status_test.rb` "maps every Integer code …": `code must be an integer status code between 0 and 999` for `-1` | `HTTP-10` |
| 34 | The `chapters` check's forward binding removed (`run_target` always the preceding chapter) | `housekeeping/chapters_test.rb`: the phase-5 two-run shape fires `SEAM-13` against chapter 03, and the wrong `appears in` attribution goes silent | — (process tooling) |
| 35 | `'appears in'` restored to `Chapters::NEGATION` | `housekeeping/chapters_test.rb` "an appears-in attribution binds forward and fires when wrong": `Expected: ["SEAM-15"]` | — (process tooling) |
| 36 | `ProxyResolution#scrub_userinfo` scrubs through the FIRST `@` (`index` for `rindex`) | `core/instrumentation/downstream_wirings_test.rb` "R0-4 …": `http://user:se@c/ret@proxy.corp`'s warning keeps `c/` -- red on 4.0.6 and 3.2.11 (it survived round 0's spellings; review round 1, R1-1) | `OBS-11`, `CFG-22` |
| 37 | `"not appear in"`, `"does not appear"` and `"do not appear"` dropped from `Chapters::NEGATION` | `housekeeping/chapters_test.rb` "a negated appears-in is not an attribution": `SEAM-15` fires against chapter 03 -- red on 4.0.6 (review round 1, R1-4) | — (process tooling) |
| 38 | `'never appear'` and then `"n't appear"` dropped from `Chapters::NEGATION`, one at a time | `housekeeping/chapters_test.rb` "a negated appears-in is not an attribution": red on `never appears in`, then on `doesn't appear in` -- 4.0.6 (review round 2, R2-2) | — (process tooling) |
| x1 | `Status` guard back to `100..599` (as first cut; the guard is now a type check, R0-5) | `core/http/status_test.rb`: three errors, `code must be an integer status code between 0 and 999` raised from the mutated guard's own message path | `HTTP-10` |
| x2 | `URL.parse!` rescues `URI::InvalidURIError` only | `core/http/url_test.rb`: `mailto://host. [Dexpace::InvalidArgumentError] exception expected, not Class: <URI::InvalidComponentError>` | `HTTP-47` |
| x3 | `HeaderSyntax.valid_name?`'s String screen removed | `core/http/header_syntax_test.rb`: `NoMethodError: undefined method 'b' for an instance of Integer` | `HTTP-17` |
| x4 | `StreamBody#refuse_closed!` no longer reads `closed?` | `core/http/body/stream_body_test.rb` "rejects an already-closed stream …" | `BODY-9` |
| x5 | `Registry#resolve`'s installed-provider return made conditional on an empty factory map (phase 9's spin) | `core/registry_test.rb` Termination: "#resolve made no progress within 2.0s" | `SEAM-5` |
| x6 | `PackagingCase`'s default rule back to segment-for-segment | `conformance/packaging_suite_test.rb` "the default gem-name rule reaches all six …": `dexpace-core. Expected: "Dexpace" / Actual: "Dexpace::Core"` | `NFR-15` |
| x7 | `BearerStamper#refresh!` validates only on a cold cache | `core/auth/bearer_stamper_test.rb` "AUTH-35: every rejection holds on the REFRESH path too …": `[Auth::ProviderError] exception expected, not NoMethodError` | `AUTH-35` |
| x8 | `AsyncPipeline.standard` drops `settings:` on the no-tracer-factory branch | `core/pipeline/standard_test.rb` "settings: reaches the async retry step on the no-tracer-factory branch too": `SeamError: Async.delay needs a registered Fiber.scheduler …` (the default settings' positive delay) | `PIPE-39` |
| x9 | `TransportSuite`'s teardown lambda clears instead of tearing down | `conformance/transport_suite_test.rb` "one run yields all five statuses …": `Expected: 3 / Actual: 0` teardowns | `NFR-17` |

Every mutated file was restored by the harness's `ensure`, and `git status` was clean after each batch.

## Facts re-measured (Task 1)

Every fact the plan rests on was re-run on **3.2.11, 3.3.12, 3.4.10 and 4.0.6**, outside the bundle
where the fact is about the interpreter's own install, with `PATH` pointed at each interpreter.

| Fact | 3.2.11 | 3.3.12 | 3.4.10 | 4.0.6 |
|---|---|---|---|---|
| `rbs` installed with the interpreter | 4.1.3, 2.8.2 | 3.4.0 | 3.8.0 | 4.2.0, 3.10.0 |
| active `net-http`, outside the bundle | 0.9.1 (an installed gem above the default) | 0.4.1 | 0.6.0 | 0.9.1 |
| `Timeout.timeout(@open_timeout` present in `net/http.rb` (the connect phase) | yes (:1791) | yes (:1601) | yes (:1657) | yes (:1791) |
| `minitest` installed; version `require "minitest/mock"` loads | 5.27.0, 5.25.1; 5.27.0 | 5.20.0; 5.20.0 | 6.0.6, 5.25.4; 5.25.4 | 6.0.0, 5.27.0; 5.27.0 |
| `a = proc {}; a == a.dup` (the "`Proc#==` is identity" comment) | true | true | true | true |
| Two fibers of one reactor on one `Thread::Mutex` park rather than deadlock (async 2.46.0) | — (async-http needs 3.3) | park | not measured | park |

The `net-http` rows correct the plan's assumption that 0.9.1 dropped the `Timeout.timeout` connect path:
it did not: the `Timeout.timeout` line is still there at :1791, beside the `TCPSocket.open(open_timeout:)`
path 0.9.1 added — which is why `C8` narrows §8.3's sentence to code this repository writes. The
`minitest` row corrects `docs/first-release.md`'s 2026-09-13 trigger text (fact 7): `minitest/mock` loads
on every row because the bundle's 5.x is what activates, and the pin in the root `Gemfile` is right —
the trigger's measurement was rewritten, the pin was not.

## Intake from phase 9 (Task 3)

Phase 9's aggregate over its four suites was **43 passed, 1 failed, 0 vacuous, 1 waived, 0 errored**.
Every non-pass was dispositioned here:

- **`NFR-13` `:failed`** → **repaired** (repairs 14): the header on all 307 shipped `.rbs` files, the
  `packaging_suite_test.rb` pin flipped to `:passed`, and `gates:spdx_rbs` so it stays that way.
- **`ASYNC-3` waived (would fail)** → unchanged, by design: design §10.5's unsatisfied MUST; its line in
  `docs/first-release.md` § Unsatisfied MUSTs stands, and the second test that runs it unwaived and
  requires the failure still passes.
- **`XCUT-18`'s wire-boundary assertion** accepted as phase 9 left it — real against `net_http` as the
  aggregate's `transport:`, and vacuous only in the core driver that has no transport to aim at.
- **The async transport's two waivers** (`TRANSPORT-14`, `TRANSPORT-27`) were re-measured through
  `async_http/conformance_test.rb:173`, which runs each unwaived and requires the failure; both still
  fail unwaived, so both waivers stand.

## Audit groups run

The phase-start pair first: **71 notes** (`--origin note --brief`) and **6 conflicts**
(`--section conflicts --brief`), every one of the six printed `[overridden by notes/…]` — none open.
Then one group per audit task, each query from the knowledge-lookup skill's table, the entry count as
printed:

| Task | Group | Entries read |
|---|---|---|
| 11 | Encoding and binary strings, plus `--prefix SEAM,IO --section rules` (§10.1, §10.2, §10.12) | 71 |
| 12 | Gem layout, zero-dependency core; public API surface (§10.3, §10.4, §10.7, §10.8, §10.9) | 327 |
| 13 | Pipeline composition and execution context; resilience (§10.5, §10.6, §10.10, §10.11, §10.15) | 297 |
| 14 | Serialization, SSE and pagination (§10.13, §10.14, §10.16) | 192 |
| 15 | Observability, configuration and redaction; transport and async-runtime adapters; cross-cutting (§10.17, §10.18, §10.19, closing note) | 397 |

No rule in any group was found broken by the as-built tree that a note does not already record, so
**no note was added** to `docs/knowledge/notes/`; `ruby scripts/verify_knowledge_structure.rb` exits 0.

## Gate runs

Measured on the untouched base (`b242de6`, a `git archive` export so the phase's own edits could not
leak in) and on the finished tree, **4.0.6**. The three tips are proven separately, gate by gate, and
the report that hands the stack over carries those runs.

| Tree | Gate | Result |
|---|---|---|
| base | all twenty-one | green; `test:gems` 4206 runs, 74618 assertions, 0 failures, 0 errors, 9 skips, coverage 99.82%; `test:gates` 193 runs, 877 assertions |
| finished | all twenty-four | green; `test:gems` 4231 runs, 74843 assertions, 0 failures, 0 errors, 9 skips (the base's nine: no `skip` was added or removed), coverage 99.83%; `test:gates` 219 runs, 963 assertions; YARD 100.00% documented; `bundler_audit` no vulnerabilities |
| finished | `gates:ledger_audit` | "every register row matches its design section 10 entry, and every verdict cites resolvable as-built evidence." |
| finished | `gates:spdx_rbs` | "307 shipped signatures carry the header and declare something." |
| finished | `gates:sole_parse` | "AstScan.parse is the one parse_file; 3 deliberate test contrasts allowlisted with reasons." |
| finished | `ruby .claude/skills/housekeeping/probe.rb` | nine checks, exit 0 |

## Deviations from the plan

1. **`R1`'s file list was widened** by a dated addendum in the design (the maintainer's decision 4):
   `docs/sdk-documentation/**`, the root `README.md`, `gems/dexpace-transport-net_http/lib/**` (YARD
   only), `rbs_collection.yaml`'s header comment and `gems/dexpace-conformance/**` in full.
   `.rubocop.yml` and `scripts/` stayed out, and the RuboCop exclusion became a `docs/first-release.md`
   residue line. The addendum was written during execution rather than strictly before the first file
   outside the original list was touched; its content is what the decision said.
2. **Task 8 was not carried out** (`P10-22`); `PAGE-14`, `SSE-26` and `SSE-40` are verification rows.
3. **Task 9 is a verification** (`P10-21`): one fiber race test, and the thread-identity mutant is its
   discriminating red (Guards 19).
4. **Task 4 is a verification** (`P10-23`), and **Task 3 Step 4 was already phase 9's** (`P10-24`).
5. **`TransportSuite.run` folds onto `Runner` without widening it** (`P10-25`); two detail pins moved.
6. **The plan named `HTTP-24`/`HTTP-43` for the `Protocol` repair**; it is `HTTP-33` (`P10-28`).
7. **Three MUST/SHOULD repairs the plan did not carry**, all under the maintainer's decision 3:
   `Status.of` total over every Integer with `#standard?` (`HTTP-10`, `P10-27`), `URL.parse!`'s wrapping and host
   screen (`HTTP-47`, `P10-29`) and `Model.own`'s default proc (`HTTP-5`, `P10-30`). The runtime
   manifest gains exactly two rows, `Dexpace::Protocol::HTTP_1_0` and `Dexpace::Status#standard?`.
8. **Task 10b** (the maintainer's decision 7) took twenty-six items and stopped at the bound
   (`P10-34`).
9. **`NFR-8`, `NFR-9` and `SEAM-10` are N/A** here where phase 0 wrote `🚫 retargeted` (`P10-32`).
10. **Ten requirement levels were corrected in place** in earlier checklists, each with a dated bracket
    naming appendix C's level: `SEAM-10` (phase 2), `IO-34`, `IO-36` (3a), `RECOV-25` (4b), `NFR-11`
    (4c, 5a, 5b, 5c), `IO-9` (5a), `BODY-20` (5b). The rows' marks are unchanged.
11. **`NFR-4` stays ✅** (`P10-35`) and **the RBS baseline line stays open** (`P10-36`).
12. **The amendment set is `C1`–`C19`**, not `C1`–`C14`: `C14` was reconciled into
    `docs/deviations.md` (it was filed only in `docs/first-release.md`), and the as-built audit added
    `C15`–`C19` (`C19`, §4's and §10.10's `send(:new)` sentence, from the review's R0-6). The consolidation of every phase's as-built ledger rows into §10 is named inside the
    existing frozen-chapter amendment blocker with its alternative, not as a new blocker.
13. **`docs/deviations.md` rides the code branch** (`P10-33`).
14. **The probe's `chapters` check exempts phase 10's own documents** and writes its negation vocabulary
    as a union of phrases (`P10-31`).

## Findings routed

This is the last phase: a finding it does not repair has no phase to go to and becomes a dated
`docs/first-release.md` line.

| Finding | Owner |
|---|---|
| The thirteen-plus-six frozen-chapter amendments (`C1`–`C19`) and the ledger consolidation | `docs/first-release.md`, the frozen-chapter amendment blocker |
| The one-time public-surface choices phases 4–8 said to "decide before the first tag" | `docs/first-release.md`, a new blocker enumerating them |
| `Query.parse`'s trailing NUL; the default-port elision at the model boundary; 7b's zero-padded `retry:` | `docs/first-release.md`, *Behavioural asymmetries* → "Port readings" (a)–(d) |
| The process-tooling RuboCop exclusion; the per-byte `#getbyte` cost; the main fiber's leftover span; `.over`'s restart; the phase-0, phase-3a, 6a and 7c residues in the leftovers table above | `docs/first-release.md`, the post-release residues line |
| The continued-clause blind spot of the `chapters` check | `docs/first-release.md`'s existing trigger, re-measured |
| The RBS sig-diff baseline | `docs/first-release.md` § Release path, left open (`P10-36`) |
| A `ledger_audit` survivor found by the mutation battery (row-only IDs unasserted) | fixed in place: `register_extra_ids.md` and its test |

## Work phase 10 postponed

Three things, each owned by a `docs/first-release.md` entry and none by a phase: applying the nineteen
frozen-chapter amendments (a human's act; the trees are frozen to every tool), the `chapters` check's
continued-clause blind spot (a sentence-spanning parser is not justified at two fires), and an `NFR-4`
diff against a release tag that does not exist. The design's section "Work phase 10 postponed, and who
owns it now" carries each with its pick-up condition.

## Review round 0, repaired 2026-09-25

The maintainer's review of the three tips (code `e9ddaa9`, tests `2d59890`, docs `2f1451a`) returned one
blocking finding, eight to fix and three nits; every one is repaired on the branch that owns its file.

- **R0-1** (blocking): seven own rows carried a copied verdict false for their ID -- `SEAM-6`–`SEAM-9`
  now cite phase 2's `Dexpace::Registry`, and `IO-30`, `IO-31`, `IO-39` say *retired apparatus*, each
  from its owner's row. A mechanical pass over all 124 own rows against their owners' marks found no
  other contradiction beyond the deliberate departures each row states (`PIPE-33`, `RECOV-34`, `NFR-8`,
  `NFR-9`).
- **R0-2**: `docs/sdk-documentation/{transport-net_http,http,transport-async_http}.md` describe the
  as-built `Protocol` (`http/1.0` admitted) and `Status` (total, `#standard?`).
- **R0-3**, **R0-12**: `CLAUDE.md` names net_http's two YARD comments and two tests, and `C14`'s origin.
- **R0-4**: the proxy warning's residual prefix leak is repaired (repairs 27, Guards 32).
- **R0-5**: `Status` is total over every Integer (repairs 28, Guards 33); `P10-27` amended.
- **R0-6**: `docs/deviations.md` row 10 is *confirmed, narrower* and the set gains `C19` (`P10-37`).
- **R0-7**: 5c's probe-claims item and 7b's `sse.md` item are on `docs/first-release.md`'s residues
  line, each with its pick-up.
- **R0-8**: `"appears in"` binds forward rather than negating (repairs 29, Guards 34–35); `P10-31`
  amended. Live fires over `docs/` stay the two phase-8 lines the phase fixed, now zero.
- **R0-9**: `SEAM-22` carries phase 2's `🚫 mechanism; surviving clause ✅`; the tally is ✅ 107 · 🚫 11.
- **R0-10**, **R0-11**: the misplaced brackets moved to the end of the sentence or item citing the key,
  their repeated tail reworded; the struck `XCUT-12` trigger's old body struck too.

## Review round 1, repaired 2026-09-25

The review of the round-0 tips (code `0d830c2`, tests `cb69353`, docs `91f0d51`) returned no blocking
finding, three to fix and two nits; every one is repaired on the branch that owns its file.

- **R1-1**: the R0-4 proxy case gains three spellings whose password holds an `@` ahead of a reserved
  character, so the through-the-LAST-`@` rule is pinned: a first-`@` scrub now fails it on 4.0.6 and
  3.2.11 (Guards 36). The shipped code was already right; the gap was the test's.
- **R1-2**: `HTTP-19` and `BODY-9`, both carried by lib repairs 6 and 7, gain cross-reference rows; the
  added set is 17 and the total 205.
- **R1-3**: the one `rubocop:disable` phase 10 added (`tools/ledger_audit.rb`, `Metrics/ParameterLists`)
  carries its reason.
- **R1-4**: `Chapters::NEGATION` gains the negated verb (`not appear in`, `does not appear`, `do not
  appear`), so "`X` does not appear in <chapter>" is no longer read as an attribution (Guards 37).
- **R1-5**: `docs/first-release.md`'s `dexpace-async-async` entry no longer points at the closed
  `XCUT-12` trigger as live.

## Review round 2, repaired 2026-09-25

The review of the round-1 tips (code `b21031c`, tests `8ec8f16`, docs `795d30a`) returned no blocking
finding, one to fix and one nit; both are repaired on the branch that owns the file.

- **R2-1**: `docs/first-release.md`'s RBS-baseline entry still read `NFR-4` as a diff against the
  previous release tag that "stays ⏳ until a `v*` tag exists", against `P10-35` and this checklist's
  `NFR-4` ✅. The sentence now says the entry is design §9's release-tag mechanism, that `NFR-4` is ✅
  through `gates:surface_snapshot`, and that what waits for a tag is `gates:sig_diff`. It carries a
  dated correction note. The entry stays open for `P10-36`'s reason.
- **R2-2**: `Chapters::NEGATION` gains `never appear` and `n't appear`, so "`X` never appears in
  <chapter>" and "`X` doesn't appear in <chapter>" are no longer read as attributions. The negated-verb
  case drives both, plus `don't appear in` and `appears nowhere in` (Guards 38). The probe is clean at
  the documentation tip.

---

**Reconciled 2026-09-25.** Written on the working tree that the three stacked branches were cut from,
before the cut; the cut was proven exact (`git diff` between the documentation tip and the working
branch empty) and the working branch deleted. `main` is `b242de6` before and after; nothing is pushed,
and issue #34 stays open.
