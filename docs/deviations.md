# Deviations

The as-built audit of `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`
— the **normative deviation ledger** — checked against the code that actually ships, not against
the design document that promises it. Design §10 is frozen (see `docs/README.md`'s "Frozen means
frozen"); this file is where the routine, ongoing question "has entry N actually landed the way
§10 says it would?" gets answered and kept current.

**Audited 2026-09-25 by phase 10, against the tree at the end of phase 10.** Every row was
re-derived from as-built source, never from another document: each Status cell names the gem path and
the constant that is its evidence, and `gates:ledger_audit` (phase 10's plan, Task 2) fails the build if
a row's IDs stop equalling its entry's, if two rows drift out of their entry's position, or if a verdict
cites no `gems/…` path that exists or names a `Dexpace::` constant that is not defined. The verdicts are
phase 10's design `R1`'s four: *confirmed*, *confirmed, narrower* (true, and narrower than the sentence --
each names the amendment below that carries the narrowing), *contradicted* (none) and *unverifiable*
(none). The closing note's claim -- nothing unified, both retry stacks, both transport seams and both
bridges survive -- is confirmed too (`gems/dexpace-core/lib/dexpace/resilience/`, `Dexpace::Bridge::SyncOver`
and `AsyncOver`), and is phase 10's checklist row `RETRY-28`.

## The audit

| # | Title | IDs touched | Status |
|---|---|---|---|
| 1 | The byte-stream provider seam is retired; its behavioural contract is not | SEAM-3–SEAM-10, IO-1–IO-42, XCUT-23 | as-built: confirmed, narrower -- the apparatus is absent (`gems/dexpace-core/lib/dexpace/io.rb` defines `Dexpace::IO::Buffer`, `BufferedSource`, `BufferedSink`, `TeeSink` and no registration entry point; the only registries are `Dexpace::Transport::REGISTRY`, `Dexpace::AsyncTransport::REGISTRY` and `Dexpace::Serde::REGISTRY`) and the contract is 3a's `gems/dexpace-core/lib/dexpace/io/`; narrower where XCUT-23's third surviving instance is the async transport seam, not an executor (C17) |
| 2 | The canonical body is a duck type, not a nominal interface | SEAM-3, BODY-1, BODY-35 | as-built: confirmed -- `Dexpace::IO::BufferedSource.over` (`gems/dexpace-core/lib/dexpace/io/buffered_source.rb:91`) takes no ownership, measured: closing the source leaves the upstream open, where `.wrapping` (`:48`) closes it; every body yields BINARY chunks from `#each` (`gems/dexpace-core/lib/dexpace/http/body.rb`) |
| 3 | The async pivot is a core-owned future rather than an ecosystem primitive | SEAM-1, SEAM-16, SEAM-17, ASYNC-1, ASYNC-2, NFR-11 | as-built: confirmed -- the pivot is `Dexpace::Async::Future`, `Dexpace::Async::Completer` and `Dexpace::Async::Settlement` (`gems/dexpace-core/lib/dexpace/async/future.rb`), core-owned; `gates:rbs_surface` finds no foreign async type in any shipped signature |
| 4 | Cancellation is cooperative; the orphaned-response close moves to the producer | SEAM-13, SEAM-30, XCUT-1–XCUT-3, CFG-17, CFG-20, CFG-21, RETRY-23, TRANSPORT-3, ASYNC-5 | as-built: confirmed, narrower -- `Dexpace::Async::Completer#fulfil` closes an undelivered result (`gems/dexpace-core/lib/dexpace/async/completer.rb:96`); the socket-closing hooks are the transports' (`gems/dexpace-transport-net_http/lib/dexpace/transport/net_http/response_pump.rb:120`, `gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/exchange.rb:134`) and the pool owns no socket, so the mitigation names a transport, not an adapter (C12) |
| 5 | Two MUSTs are not satisfied, and a third holds vacuously | ASYNC-3, ASYNC-4, PIPE-33 | as-built: confirmed as admitted, not re-opened -- `ASYNC-3` waived by ID as would-fail in `gems/dexpace-async-thread/test/dexpace/async/thread/conformance_test.rb`, `PIPE-33`'s interrupt clause unmet, `ASYNC-4` vacuous; the gap is `docs/first-release.md` § Unsatisfied MUSTs |
| 6 | Suppressed exceptions are a core-owned trail, not a host facility | RECOV-12, PAGE-13, PAGE-15, SSE-29, SSE-30, SSE-36, RETRY-34, XCUT-9 | as-built: confirmed, narrower -- the trail is `Dexpace::Suppressible` (`gems/dexpace-core/lib/dexpace/suppressible.rb:46`), included by `Dexpace::Error` and extended onto any exception by `Dexpace.attach_suppressed`, not a method of `Dexpace::Error` itself (C14); one cycle-safe walk, `Dexpace.each_cause` over `compare_by_identity` (`gems/dexpace-core/lib/dexpace/each_cause.rb:48`), kept alone by `gates:cause_walk` |
| 7 | "Standard library" is narrowed to what is stable across the supported Ruby range | SEAM-1, NFR-1, AUTH-14, OBS-2 | as-built: confirmed -- `gems/dexpace-core/dexpace-core.gemspec` declares no dependency; Basic is `pack("m0")` (`gems/dexpace-core/lib/dexpace/auth/basic_handler.rb:45`); no `require "logger"` in core; `gates:require_allowlist` and `gates:clean_bundle` green on every row |
| 8 | Discovery's substrate is require-time self-registration, not classpath scanning | SEAM-5–SEAM-9, XCUT-23 | as-built: confirmed, narrower -- adapters self-register at require time (`gems/dexpace-transport-net_http/lib/dexpace/transport/net_http.rb`) into `Dexpace::Registry`'s five branches (`gems/dexpace-core/lib/dexpace/registry.rb`); the permitted instrumentation auto-activation exists nowhere (`gems/dexpace-core/test/dexpace/seam_surface_test.rb`), so the restriction holds by absence |
| 9 | SEAM-10's multi-loader de-duplication is vacuous and is replaced by a version-skew guard | SEAM-10 | as-built: confirmed -- vacuous with a replacement: `Dexpace::Registry#register(key, factory, core:)` (`gems/dexpace-core/lib/dexpace/registry.rb:123`) is the version-skew guard; `gates:single_instance` green |
| 10 | Runtime encapsulation of models is partially unachievable | HTTP-2/SEAM-29, HTTP-4, HTTP-7, HTTP-17, HTTP-18, IO-28/BODY-37, XCUT-18 | as-built: confirmed as admitted -- `Dexpace::Request.send(:new, ...)` reaches the generated constructor (measured); both transports re-validate header names and outbound values at the wire (`gems/dexpace-transport-net_http/lib/dexpace/transport/net_http/request_mapper.rb:58`, `gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/request_mapper.rb:50`) |
| 11 | Read-only collection exposure is computed once, not wrapped per access | HTTP-5, XCUT-15 | as-built: confirmed -- `Dexpace::Model.own` (`gems/dexpace-core/lib/dexpace/model.rb`) deep-freezes a copy it owns; a returned header value list refuses mutation (measured); phase 10 repaired its default-proc escape |
| 12 | One stream-ownership rule for bodies, resolving a reference inconsistency | BODY-8, SEAM-3, SEAM-20, SEAM-21 | as-built: confirmed, narrower -- a body closes only what it opened (`gems/dexpace-core/lib/dexpace/http/body/stream_body.rb`), ownership-on-wrap is `Dexpace::IO::BufferedSource.wrapping`'s, a codec closes nothing (`gems/dexpace-serde-json/lib/dexpace/serde/json/codec.rb`); §10.12 attributes the I/O rule to SEAM-3 where the live ID is IO-6 (C3) |
| 13 | The serde seam ships four encode profiles, two of which are one Ruby type | SEAM-20 | as-built: confirmed, narrower -- all four profiles ship (`gems/dexpace-serde-json/lib/dexpace/serde/json/codec.rb:145`), `dump_string` tagged UTF-8 and `dump_bytes` ASCII-8BIT (measured); each takes the value first, which §10.13 does not spell (C18) |
| 14 | The serde witness is a class-object-and-combinator protocol, not a reflective type token | SEAM-22, SEAM-23, SERDE-5–SERDE-8, SERDE-16, SERDE-17 | as-built: confirmed -- `Dexpace::Serde.witness!` over `Dexpace::Serde::WITNESS_METHOD` (`gems/dexpace-core/lib/dexpace/serde/witness.rb:17`); the hierarchy is `Dexpace::Serde::Error` with `Dexpace::Serde::SerializationError` and `Dexpace::Serde::DeserializationError` under it; no compile-time refusal, as admitted |
| 15 | The cross-origin redirect marker lives on the per-hop cursor, not on the request | REDIR-11, AUTH-29, PIPE-16 | as-built: confirmed -- `cursor.fork(state: { cross_origin: ... })` on every drive (`gems/dexpace-core/lib/dexpace/redirect/step.rb:166`), read only through `cursor.state` (`gems/dexpace-core/lib/dexpace/auth/step.rb:118`); `Dexpace::Pipeline::Cursor` has no state setter |
| 16 | The configuration chain keeps four tiers with a substituted third source | CFG-1, CFG-3, CFG-4, CFG-24, CFG-26, OBS-35 | as-built: confirmed -- `Dexpace::Configuration#string` (`gems/dexpace-core/lib/dexpace/configuration.rb:115`) reads override, environment, property, default; the property tier is `Dexpace.configure` (`gems/dexpace-core/lib/dexpace/config.rb:43`); `Dexpace::Proxy.resolve` reads the same chain; phase 10 bounded the chain a repeated configure grew |
| 17 | The interruptible sleep is a cancellable queue wait, not `Kernel#sleep` | CFG-15, CFG-17, CFG-18, RETRY-26, XCUT-3, XCUT-13 | as-built: confirmed -- `Dexpace::Clock#sleep` is a per-call queue pop woken by the token (`gems/dexpace-core/lib/dexpace/clock.rb:113`); phase 10 refused NaN and Complex in its guard and in `Dexpace::Async.delay` |
| 18 | Platform-constant substitutions where Ruby has no constant | IO-9, BODY-32, SSE-11, RECOV-34 | as-built: confirmed, narrower -- `Dexpace::IO::MAX_MATERIALIZED_BYTES` (`gems/dexpace-core/lib/dexpace/io.rb:27`), `Dexpace::SSE::MAX_RETRY_MS` (`gems/dexpace-core/lib/dexpace/sse.rb:58`), `Dexpace::Resilience::Policy::MAX_DURATION_NANOSECONDS` (`gems/dexpace-core/lib/dexpace/resilience/policy.rb:77`); 7b added `Dexpace::SSE::MAX_LINE_BYTES` and `Dexpace::SSE::MAX_EVENT_BYTES`, which the entry does not list (C15) |
| 19 | The dead-code-survival gate is retargeted, not deleted | NFR-8, NFR-9 | as-built: confirmed -- vacuous by its own text; retargeted at the require-allowlist audit and the clean-bundle run (`gems/dexpace-core/dexpace-core.gemspec`, `tasks/gates.rake`), both green on every row |

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
amendments in eleven notes** (as of 2026-09-13; phase 10's table above completes the set at eighteen). Phase 10's design numbers them `C1`–`C13` and its plan, Task 17 writes each
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

**The amendment set, written out -- phase 10, 2026-09-25. This is the section's closing condition.**
Phase 10 (its plan, Task 17) verified every code half below in as-built source before writing a
replacement, so applying each amendment is editorial: quote the sentence, paste the replacement. The set
is **`C1`-`C18`**: the thirteen of phase 10's design, `C14` (filed by phase 4b in `docs/first-release.md`
and missing here until now), and four the as-built audit added (`C15`-`C18`). The notes below this table
stand as each amendment's measured record; `C2`, `C9` and `C14`-`C18` had none and are written in the
table alone. Its closing condition is the `docs/first-release.md` blocker "The fourteen recorded
corrections ... applied", which now enumerates all eighteen and names the one further human act this set
cannot transcribe -- **the consolidation of every phase's as-built Deviation Ledger rows into §10** --
and whose alternative form is that the release notes name the sentences, and the ledgers, a reader
should not trust. After that blocker is answered this section is a record, not a holding area.

| # | File and sentence | Replacement | Code half, verified 2026-09-25 |
|---|---|---|---|
| C1 | §3.1 (`03-…md:78`): "applies the media type's charset via `String#encode(invalid: :replace, undef: :replace)`" | "retags the BINARY bytes to the media type's charset -- UTF-8 when it is absent or unknown -- and then transcodes with both encodings named, `#encode(target, invalid: :replace, undef: :replace)`" | `Dexpace::Response#body_string` (`gems/dexpace-core/lib/dexpace/http/response.rb`): `MediaType#charset`, `#read_string(encoding)`, then a named-target `#encode` |
| C2 | §4 (`04-…md:21`): "`Request`, `Response`, `Headers`, `Query`, `RequestOptions` and `Configuration` get real mutable `Builder` classes" | add "and the multipart body (`MultipartBody#new_builder`, `MultipartBody::Builder`), which **HTTP-3** names" | `Dexpace::MultipartBody::Builder` (`gems/dexpace-core/lib/dexpace/http/body/multipart_body.rb`) and its non-aliasing test |
| C3 | §3.1 (`03-…md:83`): "closes that `IO` (**SEAM-3**)"; §10.12 leans on the same attribution | cite **IO-6** (appendix C its only statement) beside or instead of SEAM-3 | `Dexpace::IO::BufferedSource.wrapping` closes the IO, measured |
| C4 | §8.1's code block (`08-…md:31`): "`#tag(key, value)`" | delete the method, or name the requirement it serves and its precedence against **OBS-5**'s three sources | `Dexpace::Instrumentation::Event` ships `#field`, `#event`, `#cause`, `#emit` and no `#tag` (5b's P5-18) |
| C5 | §3.2 (`03-…md:167-172`): the block-scoped `read_body` "satisfied literally" | "a per-response producer `Thread` over a `Thread::SizedQueue(1)`, drained through a `#readpartial`-shaped reader, keeps the body lazy and closable (**SEAM-11**, **TRANSPORT-25**); the block form buffers the body and kills the socket, measured" | `gems/dexpace-transport-net_http/lib/dexpace/transport/net_http/response_pump.rb` (8a's P8-1) |
| C6 | §3.2 (`03-…md:172-173`), §11.18 and §12's `TRANSPORT` row: `Net::HTTP` "retries nothing on its own", "has no resend hook", TRANSPORT-2 vacuous | "`Net::HTTP#max_retries` defaults to 1 and re-sends idempotent requests; the adapter sets it to 0, so TRANSPORT-2 is satisfied by construction and leaves §12's vacuous count" | `http.max_retries = 0` in `gems/dexpace-transport-net_http/lib/dexpace/transport/net_http/adapter.rb` |
| C7 | §12's `TRANSPORT` row, both directions | add TRANSPORT-14 to the adapter-scoped list (unreachable on `async-http`); record TRANSPORT-8 as satisfied on the async adapter and drop it from the vacuous count | the named waiver `WAIVED = %w[TRANSPORT-14 TRANSPORT-27]` and the "unreachable here" measurement in `gems/dexpace-transport-async_http/test/dexpace/transport/async_http/conformance_test.rb`; 8c's `Async::Cancel`/`Async::TimeoutError` discrimination |
| C8 | §8.3 (`08-…md:216`): "forbidden in every gem in this repository" | "forbidden in code this repository writes, which `Dexpace/NoThreadInterrupt` enforces over every gem's `lib/`. A dependency may use them: `net-http`'s connect phase is `Timeout.timeout(@open_timeout, Net::OpenTimeout)` on every supported Ruby (0.9.1 also carries `TCPSocket.open(open_timeout:)`), the first such call starts a process-wide thread a host that counts threads sees once, and the `async-http` closure has no `Timeout.timeout`, seven `Fiber#raise` sites at scheduler checkpoints, one `Thread.current.raise` and one `Thread#kill` on an unreachable helper" | none owed; the cop stands |
| C9 | §9.3 (`09-…md:71`): "it ships with the interpreter as a default gem" | "it ships with the interpreter as a **bundled** gem, needing an explicit bundle entry under Bundler -- `VERSIONS` carries it, pinned `~> 5.25` -- and the same argument follows" | `VERSIONS`' `tool minitest ~> 5.25` row and its reason beside it (`VERSIONS:22-28`), read by the root `Gemfile` |
| C10 | §9.3 (`09-…md:111`): the waiver "listing the requirement ID", the report's unit unstated | add "and the report's unit is the same requirement ID: one assertion per ID, an appendix-B item a many-to-one view whose status is the worst of its assertions" | `Dexpace::Conformance::Report`, one `Result` per assertion, and `gems/dexpace-conformance/APPENDIX_B.md` |
| C11 | appendix C's `SSE-19` and `OBS-29` rows, against their chapters | each row either carries the other's clause or says it is partial -- a recommendation to the specification author, in §11's idiom | 7b's configurable line cap (`Dexpace::SSE::MAX_LINE_BYTES`); 5c's documented `OBS-29` contract and 6a's emitted per-attempt group |
| C12 | §10.5 (`10-…md:52`): "`Completer#on_cancel` lets an adapter shorten that" | "lets a **transport** shorten that by closing its socket under the read; the thread-pool adapter owns no socket" | the transports' hooks at `net_http/response_pump.rb:120` and `async_http/exchange.rb:134` |
| C13 | §12's `PAGE` row (`12-…md:36`) | add "`PAGE-15`'s wrapping clause is vacuous by a false antecedent (`7c P7-1`)" beside PAGE-35 | 7c's `P7-1` |
| C14 | §10 item 6 (`10-…md:60`): "`Dexpace::Error#suppressed` supplies the list"; §5.2's placement | "`Dexpace::Suppressible` supplies the list -- `Dexpace::Error` includes it and `Dexpace.attach_suppressed` extends it onto any other exception" | `gems/dexpace-core/lib/dexpace/suppressible.rb` (4b's P4-12) |
| C15 | §10 item 18 (`10-…md:119-124`): the named substitutions | add "`SSE::MAX_LINE_BYTES` (1 MiB) and `SSE::MAX_EVENT_BYTES` (8 MiB), SSE-19's two rejecting caps, distinct from SSE-11's `MAX_RETRY_MS`" | `gems/dexpace-core/lib/dexpace/sse.rb:38`, `:48` (7b's P7-21) |
| C16 | §9's gate table (`09-…md:7-24`) | add the seven gates later phases built -- `gates:serde_boundary` (7b), `gates:cause_walk`, `gates:bounded_map`, `gates:seam_names` (phase 9, A4-A7), `gates:ledger_audit`, `gates:spdx_rbs`, `gates:sole_parse` (phase 10, A8, A9, A11) -- and the probe's `chapters` check (A10); the NFR-13 row gains "and `gates:spdx_rbs` over every shipped `.rbs`" | `DEFAULT_GATES` in the root `Rakefile`, twenty-four names |
| C17 | §11.8 (`11-…md:32`): XCUT-23's three instances "(transport, serde, executor)" | "(transport, async transport, serde)" -- there is no executor registry | `Dexpace::AsyncTransport::REGISTRY` (`gems/dexpace-core/lib/dexpace/async_transport.rb:22`) |
| C18 | §10 item 13 (`10-…md:93`): "`#dump_to(sink)` and `#dump_into(buffer, offset:)`" | "`#dump_to(value, sink)` and `#dump_into(value, buffer, offset: 0)`" (and `#dump_string(value)`, `#dump_bytes(value)`) | `gems/dexpace-serde-json/lib/dexpace/serde/json/codec.rb:145-200` |

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
