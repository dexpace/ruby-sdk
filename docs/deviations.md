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
| 1 | The byte-stream provider seam is retired; its behavioural contract is not | SEAM-3–SEAM-10, IO-1–IO-42, XCUT-23 | design only — not yet built |
| 2 | The canonical body is a duck type, not a nominal interface | SEAM-3, BODY-1, BODY-35 | design only — not yet built |
| 3 | The async pivot is a core-owned future rather than an ecosystem primitive | SEAM-1, SEAM-16, SEAM-17, ASYNC-1, ASYNC-2, NFR-11 | design only — not yet built |
| 4 | Cancellation is cooperative; the orphaned-response close moves to the producer | SEAM-13, SEAM-30, XCUT-1–XCUT-3, CFG-17, CFG-20, CFG-21, RETRY-23, TRANSPORT-3, ASYNC-5 | design only — not yet built |
| 5 | Two MUSTs are not satisfied, and a third holds vacuously | ASYNC-3, ASYNC-4, PIPE-33 | design only — not yet built |
| 6 | Suppressed exceptions are a core-owned trail, not a host facility | RECOV-12, PAGE-13, PAGE-15, SSE-29, SSE-30, SSE-36, RETRY-34, XCUT-9 | design only — not yet built |
| 7 | "Standard library" is narrowed to what is stable across the supported Ruby range | SEAM-1, NFR-1, AUTH-14, OBS-2 | design only — not yet built |
| 8 | Discovery's substrate is require-time self-registration, not classpath scanning | SEAM-5–SEAM-9, XCUT-23 | design only — not yet built |
| 9 | SEAM-10's multi-loader de-duplication is vacuous and is replaced by a version-skew guard | SEAM-10 | design only — not yet built |
| 10 | Runtime encapsulation of models is partially unachievable | HTTP-2/SEAM-29, HTTP-4, HTTP-7, HTTP-17, HTTP-18, IO-28/BODY-37, XCUT-18 | design only — not yet built |
| 11 | Read-only collection exposure is computed once, not wrapped per access | HTTP-5, XCUT-15 | design only — not yet built |
| 12 | One stream-ownership rule for bodies, resolving a reference inconsistency | BODY-8, SEAM-3, SEAM-20, SEAM-21 | design only — not yet built |
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

**What the *IDs touched* column lists, stated here because a reader has to know before they can use
it: every requirement ID the §10 entry names — not only the IDs the deviation narrows.** §10.1 is the
case that makes the difference visible: its argument is that `IO-1`–`IO-29` and `IO-37`–`IO-42` are
implemented in full while only the pluggability apparatus is removed, so all forty-two `IO` IDs are
named by the sentence and all forty-two belong in the row. **Widened 2026-09-13 by phase 10's
planning**: rows 1, 3, 10 and 12 listed only the narrowed subset, which made the column disagree with
the chapter by 34, 2, 3 and 1 IDs respectively. `gates:ledger_audit` (phase 10's plan, Task 2) asserts
this column **equals** the ID set extracted from its §10 entry's text, which is what makes phase 10's
count of 124 reproducible from the tree rather than a number in a document — and equality is only a
checkable rule once the column's meaning is written down, which is why it is written down here and
not only in the gate.

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
has no other home. **That count of eight-in-seven is the retirement's own batch and does not cover the two
notes phase 10's design added later the same day** — §8.3's scope clause, widened by the first measurement
of `async-http`'s dependency closure, and appendix C's `SSE-19` row, the first entry here against the
normative specification. Both are below, dated.

**What this section adds up to, because the arithmetic was wrong once and is worth stating: thirteen
amendments in eleven notes.** Phase 10's design numbers them `C1`–`C13` and its plan, Task 17 writes each
one's replacement text; the mapping is fixed here so neither document can drift from the other. Seven of
the eleven notes below the retirement paragraph carry `C1`, `C3`, `C4`, `C5`, `C6`, `C7` and `C10`; the two
dated 2026-09-13 carry `C8` and `C11`; and **the two notes above this paragraph, dated 2026-09-12, are
`C12` and `C13`** — the §10.5 "an adapter" attribution and §12's `PAGE` row. `C2` (§4's builder list
dropping the multipart body `HTTP-3` names) and `C9` (§9.3 calling a bundled Minitest a default gem) have
no note here yet and are Task 17's two remaining writes; they live meanwhile as bullets 12 and 21 of phase
10's inbound list. **Eleven notes carrying eleven of the thirteen** — the two missing are `C2` and `C9`,
and that is the whole of the gap; `C7`'s single note covers the two *directions* of §12's `TRANSPORT` row,
which is why the retirement paragraph above counts eight corrections in seven notes. The set's closing
condition is the
`docs/first-release.md` blocker phase 10 files, and that blocker's enumeration names all thirteen — an
amendment recorded here with no line in that blocker is exactly the outcome this section exists to prevent.

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

**2026-09-13 — against design §8.3's prohibition, which is stated as absolute. Established by phase 10's
design.** The frozen sentence binds the ban on `Timeout.timeout`, `Thread#raise` and `Thread#kill` to
"every gem in this repository", and phase 0 mechanises it as `Dexpace/NoThreadInterrupt` over this
repository's own `lib/` — so a library **dependency** using the primitive is outside both the words and
the scan. What is actually true has two halves, both measured rather than reasoned. On the synchronous
side, `net/http`'s connect phase is
`Timeout.timeout(@open_timeout, Net::OpenTimeout) { TCPSocket.open(…) }` on **every** supported Ruby —
`net/http.rb:1601` on 3.2.11 and 3.3.12, `:1657` on 3.4.10, `:1791` on 4.0.6 — so the earlier record's
single absolute path and 3.4-specific line resolve on one row of four, and the correction must cite the
call rather than a line. The hazard §8.3 names is still unreachable through it: the interrupt can only
land during `TCPSocket.open`, before any SDK object holds a socket, and the library converts it into a
typed `Net::OpenTimeout`. On the asynchronous side — **the half nothing had measured**, and which the
earlier record asks for in as many words — the resolved `async-http` closure is 17 gems (`async` 2.45.1,
`async-http` 0.104.0, `io-event` 1.22.0, `protocol-http1` 0.41.0 and the rest), and a source scan of
every `lib/` in it finds **no `Timeout.timeout` call at all** (the one occurrence, `async/scheduler.rb:681`,
is a doc comment), **seven `Fiber#raise` sites** — `async/task.rb:365`, `async/scheduler.rb:324`, `:354`,
`:378`, `:407`, `:666`, and `io-event/selector/select.rb:114` — **one `Thread#raise`**,
`io-event/selector/select.rb:398`, and **one `Thread#kill`**,
`io-event/selector.rb:59`, in the `ensure` of `Selector.process_wait`, killing a helper thread whose
whole body is `Process::Status.wait`. **The `Thread#raise` is reported here rather than left out
because §8.3 names that primitive and a reader auditing the ban will grep for it**; it is benign, and
for a reason that is about the receiver rather than about reachability: the call is
`Thread.current.raise(error)`, a raise on the **calling** thread, which is an ordinary synchronous
`raise` and not the asynchronous cross-thread interrupt §8.3 prohibits — nothing lands on another
thread's arbitrary bytecode. Its comment says what it is for ("For all other errors (e.g. thread
interrupts), re-queue on the scheduler thread"), and it sits in `Selector::Select`, the pure-Ruby
fallback selector rather than the `URing`/`EPoll` selectors `io-event` prefers on Linux. `Fiber#raise`
is not on §8.3's list and the omission is
principled: a fiber raise resumes the fiber at a **scheduler checkpoint**, which is the property §8.3's
own rationale distinguishes from an interrupt landing on arbitrary bytecode and which §3.3 already
relies on for the async path — `async/task.rb:365` is precisely how `Async::Task#cancel` delivers the
`Async::Cancel` that phase 8c's `TRANSPORT-8` result rests on. The `Thread#kill` is unreachable from
`dexpace-transport-async_http`, which waits on no child process, and the thread holds no SDK resource.
So the clause owed is larger than "scope the prohibition to code this repository writes": it is that
clause **plus** the statement of what the two closures do, which is what a reader auditing the ban will
look for and what no document holds. **Code half: none owed** — the cop and the ban stand as written.
Touches `ASYNC-3`, `PIPE-33`, `XCUT-13`, `TRANSPORT-4`, `NFR-2`.

**2026-09-13 — against `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md`'s
`SSE-19` row, which is the first entry here against the *normative* specification. Established by phase
10's design; handed forward by phase 7b.** `docs/product-spec/13-server-sent-events-and-streaming.md:33`
ends `SSE-19` with a port sanction — "a port MAY add a configurable cap and reject/truncate oversized
lines, **documenting the divergence**" — and appendix C's row for the same ID ends at "a growable byte
accumulator expands by doubling" and carries no sanction. `CLAUDE.md` calls appendix C "the fastest way
to locate a requirement ID", and a checklist author working from the index alone would read 7b's
configurable cap as unsanctioned. The asymmetry runs both ways in the same pair: appendix C says "no
maximum line **or event** size" where the chapter says only "lines/values", and `P7-21` turns on the
appendix-C half — so **the two rows together are the only complete statement of `SSE-19`, and nothing
says so.** Why it lands here rather than with a plan task: the requirement is satisfied — 7b ships the
cap and documents it — and what is owed is a correction to a frozen chapter, which has no other home.
Because the chapter is normative rather than a design document, the correction is also a recommendation
to the specification author, in the idiom §11 already uses for the four it makes. **Code half: already
shipped** — 7b's configurable line cap, ledger row `P7-21`.

**There is a second instance, in the other direction, and it did measurable damage — so what is owed is one
correction about the pattern rather than two errata about two rows.** Appendix C's `OBS-29` row ends
"(created by the factory per operation). **This is a documented emission contract; pipeline/transport wiring
to emit it is a follow-up, so it is not yet runtime-enforced.**";
`docs/product-spec/15-instrumentation-and-observability.md:54` carries **neither** the parenthetical nor the
clause, and carries a `*Conformance:*` clause appendix C drops. Design §8.1 restates the chapter, the
corpus's harvested rule for `OBS-29` is derived from the chapter and is exact about its source, and **five
documents across four phases** — phases 5b, 5c, 6a, 8a and this repository's phase-10 inbound list — reasoned
from the short form and carried an "open surface decision" (a new pipeline step at `Stages::PRE_REDIRECT`,
and/or a widening of `RequestOptions`) that the requirement had already closed. Nothing was built wrongly:
every one of those phases declined the wiring, 6a under its `R15` and 8a as `P8-7`. What it cost is that the
decision travelled as open through five documents and one register retirement, and that a phase holding a
repair budget could have spent it widening a public surface `NFR-4` would then lock with no caller — the
`Event#tag` mistake (`P5-18`) in a second place. **Code half: already shipped** — 5c's eleven-method
vocabulary, shared no-op and ordering test, and 6a's per-attempt group through `http_tracer_factory:` called
with `cursor` (`P6-7`); the operation-lifecycle triple and the transport-milestone group having no wired
emitter in v1 is conforming by the clause above, and is recorded in `docs/first-release.md` § What v1 ships
without › Behavioural asymmetries a consumer must know. The corpus half is
`docs/knowledge/notes/observability.md`, which **Corrects** the harvested rule — and does not report a
harvesting error, because a harvested entry cannot carry what its source does not say.

Touches `SSE-19`, `SSE-11`, `SSE-12`, `OBS-29`, `OBS-28`, `OBS-25`, `CTX-14`, `CTX-20`, `NFR-4`.

A deviation discovered by a review or an audit, with no phase in flight to record it against and
no standing permission to edit §10 directly, lands here first: dated, with the IDs it touches and
what was found. It is folded into `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`
the next time §10 is deliberately amended by a human — this section is a holding area, not a
permanent second ledger. See `docs/README.md`'s "Frozen means frozen" for why routine work does
not edit §10 directly.
