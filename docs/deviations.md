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

*(empty)*

A deviation discovered by a review or an audit, with no phase in flight to record it against and
no standing permission to edit §10 directly, lands here first: dated, with the IDs it touches and
what was found. It is folded into `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`
the next time §10 is deliberately amended by a human — this section is a holding area, not a
permanent second ledger. See `docs/README.md`'s "Frozen means frozen" for why routine work does
not edit §10 directly.
