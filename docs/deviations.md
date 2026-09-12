# Deviations

The as-built audit of `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`
— the **normative deviation ledger** — checked against the code that actually ships, not against
the design document that promises it. Design §10 is frozen (see `docs/README.md`'s "Frozen means
frozen"); this file is where the routine, ongoing question "has entry N actually landed the way
§10 says it would?" gets answered and kept current.

**Nothing has been built yet.** Every row below is therefore `design only — not yet built`: the
argument in §10 is recorded, but there is no shipped code to audit it against. A row moves to
`as-built: confirmed` (or is flagged otherwise) once a gem implementing it exists and has been
checked against source, the same way `docs/deviations.md` is used in the sibling Node SDK.

## The audit

| # | Title | IDs touched | Status |
|---|---|---|---|
| 1 | The byte-stream provider seam is retired; its behavioural contract is not | SEAM-3–SEAM-10, IO-30–IO-36, IO-39, XCUT-23 | design only — not yet built |
| 2 | The canonical body is a duck type, not a nominal interface | SEAM-3, BODY-1, BODY-35 | design only — not yet built |
| 3 | The async pivot is a core-owned future rather than an ecosystem primitive | SEAM-16, SEAM-17, ASYNC-1, ASYNC-2 | design only — not yet built |
| 4 | Cancellation is cooperative; the orphaned-response close moves to the producer | SEAM-13, SEAM-30, XCUT-1–XCUT-3, CFG-17, CFG-20, CFG-21, RETRY-23, TRANSPORT-3, ASYNC-5 | design only — not yet built |
| 5 | Two MUSTs are not satisfied, and a third holds vacuously | ASYNC-3, ASYNC-4, PIPE-33 | design only — not yet built |
| 6 | Suppressed exceptions are a core-owned trail, not a host facility | RECOV-12, PAGE-13, PAGE-15, SSE-29, SSE-30, SSE-36, RETRY-34, XCUT-9 | design only — not yet built |
| 7 | "Standard library" is narrowed to what is stable across the supported Ruby range | SEAM-1, NFR-1, AUTH-14, OBS-2 | design only — not yet built |
| 8 | Discovery's substrate is require-time self-registration, not classpath scanning | SEAM-5–SEAM-9, XCUT-23 | design only — not yet built |
| 9 | SEAM-10's multi-loader de-duplication is vacuous and is replaced by a version-skew guard | SEAM-10 | design only — not yet built |
| 10 | Runtime encapsulation of models is partially unachievable | HTTP-2/SEAM-29, HTTP-4, HTTP-7, IO-28/BODY-37 | design only — not yet built |
| 11 | Read-only collection exposure is computed once, not wrapped per access | HTTP-5, XCUT-15 | design only — not yet built |
| 12 | One stream-ownership rule for bodies, resolving a reference inconsistency | BODY-8, SEAM-3, SEAM-21 | design only — not yet built |
| 13 | The serde seam ships four encode profiles, two of which are one Ruby type | SEAM-20 | design only — not yet built |
| 14 | The serde witness is a class-object-and-combinator protocol, not a reflective type token | SEAM-22, SEAM-23, SERDE-5–SERDE-8, SERDE-16, SERDE-17 | design only — not yet built |
| 15 | The cross-origin redirect marker lives on the per-hop cursor, not on the request | REDIR-11, AUTH-29, PIPE-16 | design only — not yet built |
| 16 | The configuration chain keeps four tiers with a substituted third source | CFG-1, CFG-3, CFG-4, CFG-24, CFG-26, OBS-35 | design only — not yet built |
| 17 | The interruptible sleep is a cancellable queue wait, not `Kernel#sleep` | CFG-15, CFG-17, CFG-18, RETRY-26, XCUT-3, XCUT-13 | design only — not yet built |
| 18 | Platform-constant substitutions where Ruby has no constant | IO-9, BODY-32, SSE-11, RECOV-34 | design only — not yet built |
| 19 | The dead-code-survival gate is retargeted, not deleted | NFR-8, NFR-9 | design only — not yet built |

Numbering follows §10's own list order and is not renumbered as entries are confirmed built; a
row's number is a citation, the same as an item ID in the other two registers.

## Deviations found outside a phase

**2026-09-12 — an attribution note against §10.5, i.e. against row 5 of the audit above. Proposed by
phase 8b's design; it is not a `P8-<n>` deviation and carries no `OI-<n>`.** §10.5's mitigation sentence
reads: "the check-after-resume rule (§3.3) aborts the worker at its next resume point, and
`Completer#on_cancel` lets **an adapter** shorten that by closing the socket under the read." Phase 8 is
the first phase with adapters, and it has three, of which **only one can do what that sentence describes**.
`dexpace-async-thread` owns no socket and cannot register such a hook — its pool posts an *opaque* block
and does not know what is inside it, which is also what lets the same object serve
`Dexpace::Page::_Executor` — so on the thread path the mitigation reduces to check-after-resume alone, and
the "shorten" half belongs entirely to the transport that owns the socket
(`dexpace-transport-net_http`, phase 8a). **The sentence is not wrong; it is unattributed**, and the cost
of leaving it so is concrete: a phase-9 audit reading `DEF-18` will look for the hook in the gem whose
name appears two sentences earlier and will not find it. The addition owed is one clause naming the
**transport** rather than "an adapter". Recorded here as the as-built audit of item 5 until §10 is
deliberately amended by a human. Touches `ASYNC-3`, `ASYNC-6`, `PIPE-33`, `TRANSPORT-3`, `DEF-18`.

**2026-09-12 — a completeness note against design §12's `PAGE` row. Proposed by phase 9's design; it is
not a `P9-<n>` deviation and carries no `OI-<n>`.** §12's three kinds of entry are *not satisfied*,
*vacuous* and *deferred*, and its `PAGE` row records exactly one: "PAGE-35 (SHOULD) is conditional on
offering a mutable paging-options object; the port offers an immutable value instead, so the clause is
vacuous rather than declined." **There is a second vacuity in the same prefix and the row does not carry
it.** Phase 7c's design found `PAGE-15`'s wrapping clause vacuous by a false antecedent and recorded it as
its own ledger row, `P7-1` — "the ID is implemented; the clause is vacuous by a false antecedent, and it
gets a ledger row rather than a fabricated wrapper type" — and handed the discrepancy forward to phase 9 in
as many words ("one vacuity to audit rather than tick — `PAGE-35`, design §12's — and one this sub-phase
adds, `PAGE-15`'s wrapping clause (`P7-1`), which §12's `PAGE` row does **not** currently record").

Why it lands here rather than in `open-items.md`: the finding is not that something is unmet but that a
**deviation has no home in the frozen ledger**, which is what this section exists for. The cost of leaving
it is specific and is §12's own stated purpose — "it is `dexpace-conformance` per item, not this table,
that establishes it" cuts the other way for a *vacuity*, because a vacuity is precisely the thing a suite
records and a table has to agree with. A reader counting §12's vacuous entries against a conformance
report's vacuous section will find them off by one in the `PAGE` prefix. The addition owed is one clause in
the `PAGE` row naming `PAGE-15`'s wrapping clause and citing `P7-1`. Recorded here as the as-built audit of
the `PAGE` coverage claim until §12 is deliberately amended by a human. Touches `PAGE-15`, `PAGE-35`,
`P7-1`.

A deviation discovered by a review or an audit, with no phase in flight to record it against and
no standing permission to edit §10 directly, lands here first: dated, with the IDs it touches and
what was found. It is folded into `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`
the next time §10 is deliberately amended by a human — this section is a holding area, not a
permanent second ledger. See `docs/README.md`'s "Frozen means frozen" for why routine work does
not edit §10 directly.
