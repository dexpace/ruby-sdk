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
row's number is a citation, the same as an item ID in `docs/first-release.md`, the one other register
left — the deferral register and the find-list were both retired on 2026-09-13.

## Deviations found outside a phase

**2026-09-12 — an attribution note against §10.5, i.e. against row 5 of the audit above. Proposed by phase
8b's design; it is not a `P8-<n>` deviation and is not routed to a phase plan or to
`docs/first-release.md`.** §10.5's mitigation sentence reads: "the check-after-resume rule (§3.3) aborts the
worker at its next resume point, and `Completer#on_cancel` lets **an adapter** shorten that by closing the
socket under the read." Phase 8 is the first phase with adapters, and it has three, of which **only one can
do what that sentence describes**. `dexpace-async-thread` owns no socket and cannot register such a hook —
its pool posts an *opaque* block and does not know what is inside it, which is also what lets the same
object serve `Dexpace::Page::_Executor` — so on the thread path the mitigation reduces to check-after-resume
alone, and the "shorten" half belongs entirely to the transport that owns the socket
(`dexpace-transport-net_http`, phase 8a). **The sentence is not wrong; it is unattributed**, and the cost of
leaving it so is concrete: a phase-9 audit reading the `ASYNC-3`/`PIPE-33` entry under
`docs/first-release.md` § What v1 ships without › Unsatisfied MUSTs will look for the hook in the gem whose
name appears two sentences earlier and will not find it. The addition owed is one clause naming the
**transport** rather than "an adapter". Recorded here as the as-built audit of item 5 until §10 is
deliberately amended by a human. Touches `ASYNC-3`, `ASYNC-6`, `PIPE-33`, `TRANSPORT-3`, and that
first-release entry.

**2026-09-12 — a completeness note against design §12's `PAGE` row. Proposed by phase 9's design; it is not
a `P9-<n>` deviation and is not routed to a phase plan or to `docs/first-release.md`.** §12's three kinds of
entry are *not satisfied*, *vacuous* and *deferred*, and its `PAGE` row records exactly one: "PAGE-35
(SHOULD) is conditional on offering a mutable paging-options object; the port offers an immutable value
instead, so the clause is vacuous rather than declined." **There is a second vacuity in the same prefix and
the row does not carry it.** Phase 7c's design found `PAGE-15`'s wrapping clause vacuous by a false
antecedent and recorded it as its own ledger row, `7c P7-1` — "the ID is implemented; the clause is vacuous by
a false antecedent, and it gets a ledger row rather than a fabricated wrapper type" — and handed the
discrepancy forward to phase 9 in as many words ("one vacuity to audit rather than tick — `PAGE-35`, design
§12's — and one this sub-phase adds, `PAGE-15`'s wrapping clause (`P7-1`), which §12's `PAGE` row does
**not** currently record"). **The sub-phase letter is load-bearing in every citation here:** phase 7's
three sub-phases knowingly number their ledgers from `P7-1` each — the roadmap records the collision as
deliberate and resolves it at consolidation into design §10
(`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md:1507`) — so an unqualified `P7-1` resolves to
two different deviations, `7c`'s vacuity here and `7a`'s unsatisfied `SERDE-27` clause under
`docs/first-release.md` § What v1 ships without › Unsatisfied MUSTs.

Why it lands here rather than with a phase's plan task or in `docs/first-release.md`: the finding is not
that something is unmet but that a **deviation has no home in the frozen ledger**, which is what this
section exists for. The cost of leaving it is specific and is §12's own stated purpose — "it is
`dexpace-conformance` per item, not this table, that establishes it" cuts the other way for a *vacuity*,
because a vacuity is precisely the thing a suite records and a table has to agree with. A reader counting
§12's vacuous entries against a conformance report's vacuous section will find them off by one in the `PAGE`
prefix. The addition owed is one clause in the `PAGE` row naming `PAGE-15`'s wrapping clause and citing
`7c P7-1`. Recorded here as the as-built audit of the `PAGE` coverage claim until §12 is deliberately amended
by a human. Touches `PAGE-15`, `PAGE-35`, `7c P7-1`.

**Eight corrections added 2026-09-13, in seven notes, when the find-list register was retired** — the two
against §12's `TRANSPORT` row share one note. Each records that a
sentence in a frozen chapter is wrong about something the port has since measured; each was established by the
phase named, which shipped the code half already; and each is folded into
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` — or into the chapter it is
against — by phase 10, whose inbound list in `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` carries
every one of them in full, with the measurements. They land here rather than with a plan task or in
`docs/first-release.md` for the reason this section exists: in each of them the requirement itself is
satisfied and the code half is already decided, and what is owed is a correction to a frozen chapter, which
has no other home.

**2026-09-08 — against design §3.1's decode recipe. Established by phase 3b's design.** The frozen sentence
fixes one decode boundary as `Response#body_string`, "which applies the media type's charset via
`String#encode(invalid: :replace, undef: :replace)` and falls back to UTF-8 when absent or unknown". The rule
is right; the mechanism is wrong twice. Because the same paragraph requires every response body to be retagged
`Encoding::BINARY` on ingress, `undef: :replace` destroys every byte at or above `0x80` —
`"café".b.encode(::Encoding::UTF_8, invalid: :replace, undef: :replace)` returns `"caf"` plus two U+FFFD — and
the target-less `#encode` converts to whatever `Encoding.default_internal` the host has set. What is actually
true: the boundary is **retag to the declared charset, then transcode with both encodings named**. Phase 3b
ships exactly that and `docs/knowledge/notes/io-and-byte-streams.md` overrides the harvested rule. Not a
deviation from the reference contract — `HTTP-42` is satisfied exactly. Touches `HTTP-42`, `HTTP-24`, `IO-13`,
`BODY-16`.

**2026-09-08 — against design §3.1's ownership sentence and §10.12. Established by the phase-3 segmentation
design.** The frozen sentences attribute ownership-on-wrap to **`SEAM-3`** — §3.1's "closing a
`BufferedSource` built over a caller's `IO` closes that `IO` (**SEAM-3**)", with §10 item 12 leaning on the
same rule — and `SEAM-3` is the ID §10 item 1 retires, shipped by phase 2 as 🚫. What is actually true: the
live ID is **`IO-6`**, a MUST, and appendix C is its only normative statement, since ch.05 §5.1 runs
`IO-1`–`IO-5` and `IO-18` and only the bridge half survives there under `IO-16`, a SHOULD. The addition owed
is one citation of `IO-6` rather than, or alongside, `SEAM-3`. Phase 3a reads `IO-6` out of appendix C and
implements ownership-on-wrap; the corpus repeats the wrong attribution at `message-bodies/8a1e7a7b`, which a
note under `docs/knowledge/notes/message-bodies.md` marks. Touches `IO-6`, `IO-16`, `SEAM-3`, `BODY-8`.

**2026-09-09 — against design §8.1's event surface. Established by phase 5b's design.** The frozen code block
fixes `#field(key, value)`, `#tag(key, value)`, `#event(name)`, `#cause(error)` and `#emit`. What is actually
true: four are traceable to a requirement (`OBS-3`, `OBS-4`, `OBS-39`, `OBS-8`) and **`#tag` is not** — no
`OBS` requirement names a tag other than `OBS-4`'s single reserved `event` tag, which the same block gives to
`#event(name)`, and `OBS-5`'s precedence rule enumerates exactly three contributing sources, so a fourth keyed
channel would have no precedence and no collision rule. Phase 5b ships the four and not `#tag`, deviation
`P5-18`; because adding a method widens, not shipping it costs nothing before the first release, while
shipping it would `NFR-4`-lock a public method with no requirement and no caller. Touches `OBS-4`, `OBS-5`,
`OBS-8`, `NFR-4`.

**2026-09-11 — against design §3.2, §11.18 and §12's `TRANSPORT` row on `Net::HTTP`'s retry. Established by
the phase-8 segmentation design.** The frozen sentences say `Net::HTTP` "retries nothing on its own", "has no
resend hook", and that `TRANSPORT-2` is adapter-scoped and vacuous, counted among §12's eight vacuous MUSTs.
What is actually true, measured on `net-http` 0.6.0 under Ruby 3.4.10: `#max_retries` **defaults to 1** and
`#transport_request` retries idempotent methods — `["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE"]` — on
nine error classes including `IOError`, re-running `req.exec` and so re-writing the body. Phase 8a's design
measured the sharpest consequence end to end: with a second thread closing the connection 250 ms into a hung
first connection, the call **returned `200`** at the default and raised `IOError` at `0` — the library
swallowing and retrying a caller's cancellation. Phase 8a writes `http.max_retries = 0`; until §12 is amended
the row and its MUST-level count are wrong. Touches `TRANSPORT-2`, `TRANSPORT-3`, `TRANSPORT-17`,
`TRANSPORT-18`, `RETRY-13`, `PIPE-2`, `XCUT-4`.

**2026-09-11 — against design §3.2's `read_body` sentence. Established by the phase-8 segmentation design and
decided by phase 8a's `R1`.** The frozen sentence says the adapter issues the request inside
`Net::HTTP#request(req) { |res| ... }` and exposes the body over the block-scoped `read_body` stream, so
`SEAM-11`'s no-pre-buffering clause and `TRANSPORT-25`'s lazily-read stream are satisfied "literally". What is
actually true, measured on `net-http` 0.6.0 under Ruby 3.4.10 against a server that writes, sleeps 400 ms and
writes again: the block form with a non-reading block returns with the body **already buffered**, because
`Net::HTTPResponse#reading_body` ends with `self.body` and nils `@socket` in its `ensure`, and a later
`res.read_body` raises `IOError: Net::HTTPOK#read_body called twice` — a fully buffered body and a dead
socket, both clauses violated by the design's own recipe. Phase 8a ships a per-response producer `Thread` over
a `Thread::SizedQueue(1)` instead, deviation `P8-1`; the fiber alternative is disqualified by
`FiberError: fiber called across threads`. Touches `SEAM-11`, `TRANSPORT-25`, `TRANSPORT-19`, `TRANSPORT-29`,
`IO-41`, `BODY-15`, `HTTP-43`.

**2026-09-11 — against design §12's `TRANSPORT` row on `TRANSPORT-14` and `TRANSPORT-8`. Established by phase
8c's design.** Two corrections in one row, in opposite directions. §12 records `TRANSPORT-14` as satisfied
without qualification; what is actually true, measured against `protocol-http1` 0.41.0 under Ruby 3.4.10, is
that a control/non-ASCII byte in a header **name** raises `Protocol::HTTP1::BadHeader` out of the read, so no
response object exists and the adapter has nothing to drop — unreachable on `async-http` and satisfiable on
`Net::HTTP`, which preserves such a name as a key. And §12 lists `TRANSPORT-8` as "adapter-scoped and vacuous
for `Net::HTTP`" and counts it among the eight vacuous MUSTs; what is actually true, measured against `async`
2.45.1 and `async-http` 0.104.0, is that cancelling a parent `Async::Task` delivers `Async::Cancel` into an
in-flight child exchange — `TRANSPORT-8`'s antecedent exactly — with the terminal/retryable discrimination
free by class, since `Async::Cancel < Exception` and `Async::TimeoutError < StandardError`. §9.3 is already
careful about `TRANSPORT-8`'s scoping and says nothing about `TRANSPORT-14`'s. Phase 8c records `P8-38` and
carries a named conformance waiver listing `TRANSPORT-14`, and implements and asserts the `TRANSPORT-8`
discrimination. Touches `TRANSPORT-8`, `TRANSPORT-14`, `TRANSPORT-3`, `TRANSPORT-4`, `XCUT-2`, `XCUT-18`,
`HTTP-17`, `ASYNC-6`, `NFR-8`.

**2026-09-12 — against design §9.3's waiver sentence. Established by phase 9's design.** The frozen sentence
reads: "A failing **item** that the port has decided not to satisfy is reported as a failure by the suite and
suppressed in the port's own build through a named waiver listing **the requirement ID**." The waiver half is
settled and is not disputed. What is actually true is that the **report's** unit is left unstated and cannot
be the item: phase 8a's protocol makes `Assertion` carry a list of requirement IDs and `Result` carry one
status, while an appendix-B item is one bullet naming up to a dozen IDs — and §9.3 itself creates the
decisive case, requiring `B.7`'s second item to be vacuous for `ASYNC-4` and failing for `ASYNC-3` at once.
Phase 9 resolves it for this port as `P9-8` — one assertion per requirement ID, an appendix-B item a
many-to-one view whose status is the worst among its assertions — and commits the 61-row map that is the only
place the real mapping is written down. The clause owed names the requirement ID as the unit of both the
waiver and the report. Touches `NFR-17`, `ASYNC-3`, `ASYNC-4`.

A deviation discovered by a review or an audit, with no phase in flight to record it against and
no standing permission to edit §10 directly, lands here first: dated, with the IDs it touches and
what was found. It is folded into `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`
the next time §10 is deliberately amended by a human — this section is a holding area, not a
permanent second ledger. See `docs/README.md`'s "Frozen means frozen" for why routine work does
not edit §10 directly.
