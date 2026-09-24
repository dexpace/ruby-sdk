# Phase 9 — Cross-Cutting Invariants and Conformance: Checklist

**Written at execution time, 2026-09-23, from what was built** — not from the plan. A row whose task did
not do what the plan said is a row that says so, and "Deviations from the plan" below states each
departure with its reason. The design and the plan were written on 2026-09-12 (reviewed 2026-09-13)
against phases 0–8's documents; since then the whole of phases 7 and 8 was built and merged, and this
phase was cut from `main` at `582e33a`, which holds all of them. Where the plan's text and the built tree
disagree the tree wins and this document records it.

**Phase 9 reports; phase 10 repairs (design `R6`).** Nothing outside `gems/dexpace-conformance/`,
`tasks/`, `tools/`, `test/`, `.github/workflows/`, each adapter gem's `test/` tree and the root `Rakefile`
was changed — **plus exactly one ADDED file under `gems/dexpace-core/test/`**, the first-party
`InvariantSuite` driver, with no existing core file modified, renamed or deleted. That is the one place
`R6`'s file list bends and it is recorded rather than left to be discovered: deviation 14 below, `P9-40`,
and the design's As-built addendum, which names the two sentences that cannot both hold. No `lib/` or
`sig/` file outside `gems/dexpace-conformance/` was touched at all, in any gem, and
`git diff --name-status main..<the docs tip> -- gems/dexpace-core` is that one path, status `A`. Every
defect this phase found in another phase's code is routed with its evidence and left unrepaired —
"Findings routed" below — because a phase that repairs what it found destroys the evidence that it was
ever there.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase, task
number and path — that will do it, or the `docs/first-release.md` entry that owns it) · N/A not
applicable in this port.

Plan: `docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance.md`. Task numbers
are that plan's — seventeen numbered tasks plus Task 12a, eighteen headings. Design:
`docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance-design.md`, whose
Deviation Ledger carries `P9-1`–`P9-10` and whose As-built addendum, written with this checklist, adds
**`P9-21`–`P9-42`** (the band starts at `P9-21`; `P9-11`–`P9-20` are left free and nothing is renumbered).
Test files are named with their gem: `conformance/…` is
`gems/dexpace-conformance/test/dexpace/conformance/`, `core/…` is `gems/dexpace-core/test/dexpace/`,
`gates/…` is `test/gates/`, `serde_json/…` is `gems/dexpace-serde-json/test/dexpace/serde/json/` and
`async_thread/…` is `gems/dexpace-async-thread/test/dexpace/async/thread/`.

---

## Requirement rows

**Forty-one own rows** — `XCUT-1`–`24` and `NFR-1`–`17` — plus the cross-reference rows below for the IDs
this phase's suites exercise and do not own. **Thirty-six ✅, two N/A (`NFR-8`, `NFR-9`), one ⏳
(`NFR-16`), one ✅ with a stated partial (`NFR-12`) and one ✅ / ⏳ (`NFR-13`, whose assertion is built and
whose assertion FAILS against the tree)**; nothing 🚫.

**The aggregate run's verdict**, Task 16 Step 2, over all four suites with the real subjects and 8a's
adapter supplying `transport:`, on 2026-09-23 under Ruby 4.0.6:

```
43 passed, 1 failed, 0 vacuous, 1 waived, 0 errored
  waived (would fail): ASYNC-3 (cancelling a task blocked on a worker releases the worker within a bound)
  FAILED: NFR-13: shipped signature files carry no SPDX header
passed? false
```

That `false` is the instrument working, not the instrument broken: one SHOULD-level failure with a named
owner and one waived MUST that is declared to fail. Nothing is vacuous — every factory is supplied —
and `XCUT-18`'s call-site assertion, which is vacuous in core's own driver because core ships no
adapter, runs for real here.

**`PackagingSuite` was run a second time against what a consumer actually resolves**, which is what
design `P9-2` asks for and what a run inside `bundle exec` cannot give: the six gems were built with
`gem build`, installed into a scratch `GEM_HOME` outside the repository, and the suite run with every
`BUNDLE_*` and `RUBYOPT` key cleared. **7 passed, 1 failed, 0 vacuous, 0 waived** — `NFR-1`, `NFR-2`,
`NFR-3`, `NFR-10`, `NFR-11`, `NFR-14` and `NFR-15` against the PUBLISHED `Gem::Specification` and the
`sig/` trees inside the built `.gem` files, and the same `NFR-13` failure. That run is also the
evidence that every gem's `sig/` mirror SHIPS: the scan walked it inside the installed gem and not in
the repository.

**Prediction versus observation**, which the plan's Task 15 Step 3 asks for by name: *a prediction
is not an observation*, and where the two differ the row says which prediction was wrong. The design's
`NFR` disposition table, written on 2026-09-12, predicted **six ⏳**. **Three of those predictions were
wrong** and the rows below are ✅ on observation, each naming its own. **`NFR-7`**'s ⏳ was pending
phase 0 plan Task 3's reviewed `.rubocop.yml` baseline; whatever that baseline said when phase 0 wrote
it, the honest RuboCop run over the `.rubocop.yml` the repository carries exits 0 on `main` at
`582e33a`, before this phase changed anything. **`NFR-10`**'s was pending 8c plan Task 3's per-gem Ruby
floor gate edit; that edit landed — `VERSIONS` carries `ruby floor:dexpace-transport-async_http 3.3`
and `gates:versions` is green. **`NFR-17`**'s was pending phase 0 plan Task 2's `minitest ~> 5.25` pin,
the one non-blocking-gate finding the design itself had raised; that pin landed with its reason in
`VERSIONS`' own comment, so the meta-audit starts from green with nothing outstanding to report.
**`NFR-4`**'s ⏳ is overturned as a MARK only, and narrowly: both gates run and the row is ✅, but
`gates:sig_diff` still prints its own vacuity because the `v*` tag it needs does not exist, which is
what the design predicted. **`NFR-13`**'s and **`NFR-16`**'s predictions HELD — the SPDX assertion
fails as predicted, and there is still no release path.

A fourth correction observation forced is not an `NFR` mark at all but the narrative behind
`gates:bounded_map`'s one expected red, and it is deviation 4 below. Every one of the four was MADE
from measurement before Task 15's disposition run, so each mark is an observation and not a
transcription — but only the `gates:bounded_map` one was written down AS a correction at the time.
Naming the other three as overturned predictions is review round 2's repair (`P9-36`): a mark that
silently disagrees with the prediction it replaces leaves the next reader unable to tell which it is,
and phase 10 reads this document first.

Every `XCUT` row's evidence is the same three-part shape and is stated once here rather than repeated
forty-one times: **(a)** the assertion in `dexpace-conformance`, which names no first-party constant it
cannot reach through `InvariantCase`; **(b)** that assertion driven against a deliberately
non-conforming double in `conformance/invariant_suite_test.rb` (or `…_core_test.rb`), which is what
proves the assertion can fail at all; and **(c)** the same assertion driven against the real SDK by
`core/cross_cutting_invariants_test.rb`, the first-party driver. A row naming a mutation names one from
"Guards run red" below, run against the real subject through (c).

**(b) holds for every `XCUT` ASSERTION but two, and the two are named here rather than left to be
found.** The unit is the assertion and not the row, which is review round 3's correction: an ID appears
once however many assertions carry it, so a row can be covered on one assertion and bare on the other.
`XCUT-18` was exactly that, and the bare one could be neutralised whole with the whole of
`rake test:gems` green (deviation 16; `P9-42`). What makes the sentence checkable rather than asserted
is the sweep behind it: every assertion body in the four suites neutralised whole, one at a time, run
in review round 3 over all forty-five and leaving four green — `XCUT-3`'s, `XCUT-12`'s, `XCUT-18`'s
model layer and one private clause helper whose parent assertion is caught. Round 4 closed `XCUT-18`'s.
The two that remain, `XCUT-3`'s and `XCUT-12`'s, carry no committed non-conforming double: either would
need a subject that stays in the wait past the assertion's own half-second bound, which leaks a thread
`DexpaceTestCase`'s teardown counts, so their evidence is (a) + (c) + a hand-run SUBJECT mutation — 22
and 23 below. **Thirteen doubles were added in review round 3 and two more in round 4.** Until then
seven assertions had no (b) at all — `XCUT-1`, `XCUT-2`, `XCUT-6`, `XCUT-7`, `XCUT-10`, `XCUT-19` and
`XCUT-24` — and five of the seven could be neutralised WHOLE with `rake test:gems` green,
which is the difference between an assertion that holds and one that cannot report anything else
(deviation 15; `P9-41`).

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `XCUT-1` | MUST | ✅ | 8, 16 | "a cancellation is terminal and never retried": the token's `#check!` surfaces `Dexpace::CancelledError`, `Policy.throwable_retryable?` answers false for it, and `Policy.cancellation?` still recognises it when an adapter's own retryable error wraps it — the third clause is the one a check reading only the outermost error would miss. Two defective stand-in `Policy` cores — one reading only the outermost error, one calling a cancellation retryable. Mutations 12, 13 and 55 |
| `XCUT-2` | MUST | ✅ | 8, 16 | "a timeout is retryable and told apart from a cancellation by state": a `TransportError(phase: :read)` classifies retryable, the ambient flag stays clear, and a SUBTYPE of `CancelledError` is still recognised as a cancellation — the subtype clause is what makes "by the type, never by a message string" real. Two defective cores — one matching the cancellation type EXACTLY, so a subtype escapes, and one telling a timeout apart by its message. Mutation 56 |
| `XCUT-3` | MUST | ✅ | 8, 16 | "a pending inter-attempt wait is promptly cancellable": a thirty-second `Clock::SYSTEM#sleep` cancelled from another thread surfaces `CancelledError` inside half a second. The waiter must be **parked** when the cancel is issued, and that is asserted rather than assumed — without the barrier the cancel could beat the waiter into the wait and an implementation ignoring the token passed (`P9-28`). **No committed non-conforming double**, for the reason the evidence paragraph gives — a subject that stays in the wait leaks its thread — so the guard is mutation 22, run against the real `Clock` |
| `XCUT-4` | MUST | ✅ | 6, 16 | "the error taxonomy has two branches and a transport error is I/O-family": `ProtocolError` carries a status and `TransportError < ::IOError` does not, and `Dexpace::Error` is a MODULE both reach through `Module#===` |
| `XCUT-5` | MUST | ✅ | 6, 16 | "one shared status classifier decides the baked retryability flag": `Retryability.retryable_status?` is the one classifier and `ProtocolError#retryable_by_status?` reads it — never `#retryable?`, which is `XCUT-6`'s open capability (6a's `P6-10`) |
| `XCUT-6` | MUST | ✅ | 6, 16 | "a custom error's retryability capability is queried, not its type": `Policy.throwable_retryable?` probes `#retryable?` over every cause and never a class list, so a caller's own error type is honoured. Two defective cores — one reading only the outermost error, one matching a concrete TYPE. Mutation 57 |
| `XCUT-7` | MUST | ✅ | 6, 16 | "the configured retryable-status set is authoritative and can widen or narrow": a set admitting 404 admits it and one refusing 408 refuses it, and the default set is the six `RETRY-13` fixes. Two defective cores — a set ANDed with the baked classifier, which passes the narrowing half and fails the widening one, and a wrong default set. Mutation 58 |
| `XCUT-8` | MUST | ✅ | 6, 16 | "the status-to-exception factory refuses a non-error status": `ProtocolError.for` raises `InvalidArgumentError` on a 200, `.for_or_nil` answers nil, and the same factory still maps a 503 — both forms in one assertion |
| `XCUT-9` | MUST | ✅ | 6, 13, 16 | "the cause walk terminates on a cyclic chain, tracking by reference identity": a THREE-node cycle (two is indistinguishable from a depth-2 walk) driven through `Enumerator#next` under a step bound, so a non-terminating walk reports `:failed` rather than hanging. Beside it `gates:cause_walk`, the parsed scan that keeps the walk in one file. Mutation 24 |
| `XCUT-10` | MUST | ✅ | 6, 16 | "retry safety is decided from the request alone, uniformly": all four cases `XCUT-10` enumerates, plus the structural half — `Resend.eligible?`'s parameter list is exactly `[[:req, :request]]`, so there is no failure parameter to special-case on. Two defective cores — a gate that re-sends a bare POST, and one taking a failure parameter. Mutation 59 |
| `XCUT-11` | MUST | ✅ | 4, 8, 11, 16 | Two assertions plus a third in `ExecutorSuite`. Clause 1 is `SharedInstance.audit` over every shared instance the DRIVER declares (design `R8`, `P9-9`) and sixteen threads through one shared step with distinct requests; clause 2 is TWO FIBERS ON ONE THREAD, the only shape a lock held across a suspension point is visible in — Ruby's `Mutex` is per-fiber and non-reentrant — with the resulting `ThreadError` converted to a `Failure` so the status is `:failed` and not `:error`. The driver declares **every shared instance core publishes**, each with the ivars it is allowed to hold — twenty at this tip: eighteen frozen, which conform on `frozen?` alone whatever they hold (seven of them do hold state), and two unfrozen, `ContextStore.default` and `Pipeline.standard`, which declare exactly what they hold (`core/cross_cutting_invariants_test.rb`, "every shared instance core publishes"). The number is read off that factory rather than kept by hand here; design `R8`'s **nine** is a different list — the subjects it names across five phase documents — and both are right. Mutations 34, 35 and 44 |
| `XCUT-12` | SHOULD | ✅ | 8, 16 | "a credential cache's refresh is single-flight": sixteen threads race one `BearerStamper` over a parked provider and exactly one fetch happens. Every racer must be parked before the gate opens, asserted rather than assumed — without the barrier the first thread finished alone and a per-caller stamper passed (`P9-29`). Mutation 23. The FIBER-scheduler form is out: it needs a credential path under a reactor, which no first-party suite assembles — stated in the assertion and on phase 10's inbound list. **No committed non-conforming double**, for the same reason as `XCUT-3`: sixteen racers that never finish leak sixteen threads. The guard is mutation 23, run against the real `BearerStamper` |
| `XCUT-13` | MUST | ✅ | 5, 11, 16 | Two assertions plus `ExecutorSuite`'s: the latch is counted AT THE RESOURCE (`Closeable#close` answers nil on the winning and the losing call alike, so a return value proves nothing), and the close is bounded by elapsed monotonic time on BOTH calls — never by an interrupt, which §8.3 bans outright. Appendix C's third clause, "preserves the ambient interrupt/cancel flag as-is", is **scoped out with its reason** in `executor_suite/lifecycle.rb`'s own comment and asserted nowhere: §8.3 bans every primitive that could arrange a pending interrupt, so the clause holds by the flag never being touched and there is nothing observable to assert. Mutations 2 and 36 |
| `XCUT-14` | MUST | ✅ | 7, 13, 16 | Two assertions plus `gates:bounded_map`. The cap clause reads the size after EVERY insert across 320 of them, so an implementation that overshoots and trims is caught; the DRAIN clause fills the backing store to cap + 5 — the state a concurrent overshoot leaves, arranged without a thread — and performs one `#set`: a drain loop ends at the cap, a check-then-evict at cap + 5, on every interpreter. Mutations 6 and 7 |
| `XCUT-15` | MUST | ✅ | 5, 16 | "public wire models retain no external-mutable alias": the mutation is on the INNER array of the `values:` Hash, because a port that dup'd only the outer Hash passes a top-level check. Mutation 1 |
| `XCUT-16` | MUST | ✅ | 7, 16 | All three clauses: the plaintext refusal is `Auth::HTTPSRequiredError` BY CLASS, an HTTPS request really is stamped (so the refusal is about the scheme and not a broken path), and a marker-suppressed cross-origin re-issue proceeds over `http` carrying no credential. Mutations 19 and 20 |
| `XCUT-17` | MUST | ✅ | 7, 16 | All four clauses in one assertion, because a port can satisfy any three: `Authorization` stripped on a SAME-origin re-issue, all three origin-scoped headers on a cross-origin one, the `Location`'s userinfo gone, and an HTTPS→HTTP downgrade refused. Mutations 15–18 |
| `XCUT-18` | MUST | ✅ | 7, 16 | Two assertions. The model layer asserts the ASYMMETRY — HTAB refused in a name and admitted in a value — which a port applying one rule to both passes with a single case. The call-site assertion drives a forged request (built through `send(:new)`, or a duck if that fails) at a real adapter and OBSERVES wire activity through a listener it owns: one accepted connection is the failure. **Each assertion carries its own (b)**, which is the distinction review round 3 forced: the model layer's are a permissive validator and one applying the NAME rule to outbound values as well, added in review round 4 and proven by mutations 62 and 63 — until then this was the one assertion in the suite that could be neutralised whole with `rake test:gems` green (deviation 16), and the call site's are the two transports in `conformance/invariant_suite_core_test.rb`. Mutations 4 and 5 are the hand-run SUBJECT mutations of core's own `HeaderSyntax`, one per side of the asymmetry. **Vacuous in the core driver, real in the aggregate run**: core ships no adapter, so `transport:` is nil there and the vacuity is accepted with its citation; Task 16's run supplies `Dexpace::Transport::NetHTTP.build` and the assertion passes for real |
| `XCUT-19` | MUST | ✅ | 7, 16 | Clauses (a)–(d): userinfo, a query value and a fragment token all gone from one URL while host and path survive; the header allow-list is default-DENY; and a credential reveals nothing in `#to_s`, `#inspect` or — checked STRUCTURALLY, because `pp` is outside this gem's require allowlist — `#pretty_print`, whose owner must be the credential's own class (`pp.rb` never consults an `#inspect` override on a `Data`). Appendix C's clause (e), "full request/response BODY logging MUST be OFF by default", is asserted nowhere in `InvariantSuite` and is **5b's own**, proven there: `HTTPLogging::DEFAULT` is `NONE`, and `Instrumentation::Step` constructs the two phase-3b logging wrappers at `HTTPLogging::BODY` alone — 5b's checklist carries it as clause (e) of its own `XCUT-19` cross-reference row, over the `OBS-34` row's subject (`docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-checklist.md`). `invariant_suite/security.rb` says so in place. Two defective cores — a redactor forwarding the URL's userinfo, and a default-ALLOW header list. Mutations 9, 10 and 60 |
| `XCUT-20` | MUST | ✅ | 7, 16 | Scoped exactly as 5c handed it forward and no wider: `Instrumentation.contain` swallows and reports, `Redactor#url` substitutes its marker for a malformed input, `#header_value` always answers a String, and `Preview.render` survives undecodable bytes. NOT extended to a foreign tracer or meter callback, which `OBS-20` carves out — a `rescue` there is a guard this suite must not demand. Mutation 11 |
| `XCUT-21` | MUST | ✅ | 7, 16 | Two observations and no character count: the handler takes an injectable `cnonce_source:` (so its randomness can be audited at all), and bytes are DRAWN from the injected recorder and CARRIED into the rendering — each drawn byte flipped in turn, and at least sixteen must change the output. A character count would call a truncated 128-bit draw conforming. Mutation 21 |
| `XCUT-22` | MUST | ✅ | 5, 11, 16 | Both halves, on two INDEPENDENT routes: the caller-supplied resource is not closed AND it still works, because a component that tore it down another way would pass the first alone. That second route is `Borrowed#finish`, added in review round 2 — until then `usable?` was the negation of the `closed?` the first Check reads, so the second could not fail on its own (`P9-38`). `ExecutorSuite`'s twin asserts the same over a real pool behind `Transport.async_over`, and posts work to it, which is an independent observation of its own. Mutations 3, 40 and 54 |
| `XCUT-23` | MUST | ✅ | 8, 16 | Three ordered rules and the ORDERING is the content: zero candidates fail loudly, two candidates fail loudly, an explicit install beats a discovered one, and a single candidate is discovered. "Loud" is checked for its own reason — the message must name the explicit-install entry point. Mutations 21b and 25 |
| `XCUT-24` | SHOULD | ✅ | 7, 16 | Both subjects, because the halves live in different objects: 4b's error-body snapshot is the cap and 3b's logging tap is the non-consumption. A preview that capped but drained would pass the first alone. One defective core — a snapshot that multiplies its cap. Mutations 8 and 61 |
| `NFR-1` | MUST | ✅ | 9, 15 | Asserted TWICE against two subjects (`P9-2`): phase 0's `gates:gemspec_audit` over the source gemspec, and `PackagingSuite`'s "core declares zero runtime dependencies" over the resolved `Gem::Specification` a consumer actually gets. `gates:require_allowlist` and `gates:clean_bundle` are the same claim's other two mechanisms and all four are green on every matrix row |
| `NFR-2` | SHOULD | ✅ | 9, 15 | `PackagingSuite`'s "each adapter declares the core plus at most one library": `net_http` spends `net-http`, `async_http` spends `async-http`, `serde-json` spends `json`; `async-thread` and `conformance` spend none. Green against the built `.gem` files outside the bundle |
| `NFR-3` | SHOULD | ✅ | 9, 15 | `PackagingSuite`'s "every shipped implementation file has a signature beside it" — the `sig/` mirror as a property of the PACKAGED gem, not of the repository — beside `rbs validate` and `steep check` over six targets, both green with no relaxation added by this phase |
| `NFR-4` | SHOULD | ✅ | 15, 17 | `gates:sig_diff` (vacuous until the first `v*` tag, and it says so) and `gates:surface_snapshot` over the six manifests, regenerated deliberately once in Task 17 and reviewed row by row. This phase's rows are `dexpace-conformance`'s alone |
| `NFR-5` | SHOULD | ✅ | 15 | `rake test:gems` with SimpleCov `minimum_coverage 80`; measured at the tests tip |
| `NFR-6` | SHOULD | ✅ | 15 | `ruby -w` plus `RUBYOPT=-W:deprecated` with `DexpaceTestCase::FatalWarnings` raising, over one process holding all six gems' suites. This phase's `test/support/gate_warning_capture.rb` deliberately does NOT arm it, for the reason `P9-24` gives |
| `NFR-7` | SHOULD | ✅ | 15 | `rake rubocop` (findings fatal, no autocorrection) and `rake cops:test`. The honest command in a nested worktree is `bundle exec rubocop --fail-level=convention --ignore-parent-exclusion`, which is what was run: 776 files, no offences. **The design predicted ⏳**, pending phase 0 plan Task 3's reviewed `.rubocop.yml` baseline; that prediction was wrong — the baseline landed and the honest run is clean on `main` before this phase touched it |
| `NFR-8` | MUST | N/A | 15 | Ruby has no whole-program dead-code elimination, and the requirement exempts itself by its own text. §10.19 retargets it at the require-allowlist audit and the clean-bundle isolation run, both dispositioned under `NFR-1` rather than counted twice (`P9-5`) |
| `NFR-9` | SHOULD | N/A | 15 | The same: there is no shrinker keep-configuration to guard. The part of its CONTENT that does apply — a guard that the require-allowlist is still the RIGHT list on a new interpreter — is postponed with its trigger named (`docs/first-release.md` § Post-release triggers, the require-allowlist entry) |
| `NFR-10` | MUST | ✅ | 9, 15 | `PackagingSuite`'s "every unit declares a runtime floor, and a higher one stays isolated" — `dexpace-transport-async_http`'s 3.3 floor must not leak into the other five — beside `gates:versions`. **The design predicted ⏳**, pending 8c plan Task 3's per-gem Ruby floor gate edit; that prediction was wrong — the edit landed, `VERSIONS` carries the `floor:` row and `gates:versions` is green |
| `NFR-11` | SHOULD | ✅ | 9, 15 | `gates:rbs_surface` over `sig/**` plus `PackagingSuite`'s "the core's public signatures name no async-framework type", whose leak regex anchors on the START of a constant path so core's own `Dexpace::Async::Future` is not a match. Mutation 41 |
| `NFR-12` | SHOULD | ✅ (partial) | 15 | `gates:reproducible` — byte-identity for one gem built twice on one interpreter, which is phase 0's `P0-7` reading. The cross-toolchain half is explicitly out of scope and is release-gated (`docs/first-release.md` § Release path, the `NFR-12`/`NFR-16` entry) |
| `NFR-13` | SHOULD | ✅ / ⏳ | 9, 15, 16 | ✅ for the `lib/` half — the `Dexpace/SpdxHeader` cop over every Ruby file — and for the ASSERTION over the `sig/` half, which is what this phase owed. ⏳ for the `sig/` half's CONTENT: the assertion **fails, correctly**, and that failure is this phase's verdict rather than a defect in it. Measured on 2026-09-23: **307 of 307 shipped `.rbs` files carry no SPDX header, in all six gems.** A RuboCop cop parses Ruby and cannot reach `.rbs`, so nothing checked them. **Owner: phase 10's design addendum `A8` and inbound row 8, which already name this assertion and say "phase 9's presence assertion turns green"** — verified still owned on 2026-09-23, not re-recorded |
| `NFR-14` | SHOULD | ✅ | 9, 15 | `PackagingSuite`'s "every unit's version comes from one source of truth" against the resolved specs, beside `gates:versions` over the repository-root `VERSIONS` file |
| `NFR-15` | SHOULD | ✅ | 9, 15 | `PackagingSuite`'s "each unit reports its build version at runtime": the loaded `VERSION` constant compared against the resolved gemspec's, run against locally built `.gem` files outside the bundle |
| `NFR-16` | SHOULD | ⏳ | — | Artifact signing is "enforced on the release/CI path" and there is no release path. No phase-9 task writes an assertion for it and none is shipped as a placeholder. **Owner: `docs/first-release.md` § Release path, the `NFR-12`/`NFR-16` entry** |
| `NFR-17` | MUST | ✅ | 13, 15 | Every gate this phase adds is in `DEFAULT_GATES` in the root `Rakefile` — not in `tasks/gates.rake`, which the `Rakefile` `load`s before defining and freezing the array — so all **twenty-one** are in `task default:` and therefore blocking, and all three are in `ci.yml`'s `gates` job. `gates/default_task_test.rb` asserts the count and the membership, and phase 0's `ci_workflow_test.rb` asserts every `DEFAULT_GATES` entry appears in some CI job. **The design predicted ⏳**, pending phase 0 plan Task 2's `minitest ~> 5.25` pin — the one non-blocking-gate finding the design itself had raised; that prediction was wrong, because the pin landed, so the meta-audit found nothing outstanding to report |

### Cross-reference rows

One per ID this phase's suites assert and another phase owns. Each names the owning phase's checklist
row, which is not re-marked here.

| ID | Owner | What this phase's suite adds |
|---|---|---|
| `SEAM-2` | phase 2 | `gates:seam_names`, the parsed scan asserting core names no adapter's leaf namespace — by leaf pair and not by a literal spelling, because a fixed list of fully qualified names caught none of four realistic shapes |
| `SEAM-12` | phase 2 | `ExecutorSuite`'s "a shared executor takes work from many threads", sixteen concurrent posts asserted on the collected set and never on timing |
| `SEAM-20` | phase 2 | `CodecSuite`'s "a codec never closes a target it was handed", with the bytes checked too so a codec that wrote nothing cannot pass by having closed nothing. Mutation 37 |
| `SEAM-25` | phase 2 (postponed to 8a, unwritten there) | `ExecutorSuite`'s "closing an owned executor emits exactly one shutdown event" — **the harness half, reassigned to phase 9 and stated as a correction to a committed record**, not a restatement of it (`P9-21`). The count is of shutdown EVENTS and not of sink writes, which review round 2 gave a double of its own (`P9-39`). Mutation 53 |
| `SERDE-3` | phase 7a | The same `CodecSuite` assertion, re-derived rather than lifted (`P9-22`) |
| `SERDE-9` | phase 7a | `CodecSuite`'s "a decode failure surfaces the SDK's serde type", all three clauses: it raises, the type is inside `Serde::Error`, and the original is chained — read through `Dexpace.each_cause` so `gates:cause_walk`'s allowlist stays at one entry. Mutation 38 |
| `SSE-37` | phase 7b | `gates:serde_boundary`'s `PENDING` list asserted EMPTY, the clause 7b handed forward and could not assert while phase 7 was running. The task's abort branch is now driven by a fixture (`P9-30`) |
| `ASYNC-3` | phase 8b | `ExecutorSuite`'s "cancelling a task blocked on a worker releases the worker within a bound", written so it genuinely FAILS and waived by ID, printed `waived (would fail): ASYNC-3`. The driver runs it UNWAIVED in a second test and requires the failure, so the waiver cannot outlive the limitation |
| `ASYNC-15` | phase 8b | The close-latch and borrowed-executor assertions, which carry it beside `XCUT-13` and `XCUT-22` |
| `ASYNC-16` | phase 8b | `ExecutorSuite`'s "close drains in-flight work and refuses new work", both halves |
| `ASYNC-17` | phase 8b | `ExecutorSuite`'s "a resource-free implementation inherits a no-op close", whose subject is `Transport.async_over` over an inline executor and deliberately NOT the pool — handing the pool there would assert the opposite requirement |

---

## What was built

Four suites, one aggregate, three repository gates, one generated level map, one coverage map and three
first-party drivers.

- **`Runner`** — the one place the five statuses are decided, with the rescue order load-bearing
  (`Vacuous` and `Failure` are both `::StandardError` descendants, so the bare rescue is last) and a
  FRESH subject per assertion. `TransportSuite` is deliberately not moved onto it (`P9-10`).
- **`Report`** gains `.merge`, `#to_h`, `#blocking_vacuities`, `#accepted_vacuities`, `#unknown_ids`,
  `#would_fail` and the MUST-level vacuity blocker; `#passed?` is false while a blocking vacuity stands.
- **`Levels`** — 645 IDs generated from appendix C by `tools/requirement_levels.rb`, with a `--check`
  that both exits are now proven against (`P9-31`).
- **`SharedInstance.audit`** — `XCUT-11`'s structural predicate, R8's disjunction: frozen conforms on
  `frozen?` alone, unfrozen only when every ivar is one the DRIVER declared.
- **`InvariantSuite`** — 28 assertions over all 24 `XCUT` IDs in ten `private_constant` groups.
- **`PackagingSuite`** — 8 assertions over `NFR-1`, `2`, `3`, `10`, `11`, `13`, `14` and `15`.
- **`CodecSuite`** — 2 portable seam assertions, re-derived (`P9-22`).
- **`ExecutorSuite`** — 7 assertions in two groups, `ASYNC-3` among them and written to fail.
- **`Aggregate`** — one `Report` over every suite, with a `PREAMBLE` that prints what a green run does
  NOT prove on every render.
- **Three gates** — `gates:cause_walk`, `gates:bounded_map`, `gates:seam_names`, over
  `tools/ast_scan.rb`'s `RubyVM::AbstractSyntaxTree` walker. Twenty-one blocking gates in all.
- **`APPENDIX_B.md`** — the 61-row coverage map, generated and hand-annotated.
- **Three drivers** — `core/cross_cutting_invariants_test.rb` (the ONE file this phase adds under
  `gems/dexpace-core/`, and the one place `R6`'s file list bends; `P9-40`),
  `serde_json/conformance_test.rb`, `async_thread/conformance_test.rb`.

---

## Guards run red

The reviewer's mutation list could not be recovered verbatim after this session's context was compacted
(`P9-32`), so the set below was re-derived from the design's testing strategy and the plan's own
"non-conforming double first" rule. **It was NOT one mutation per assertion, and saying so was this
document's own error**: review round 2 measured that `XCUT-2`, `XCUT-6`, `XCUT-7` and `XCUT-10` had no
row in this table at all and `XCUT-1` only subject rows, and review round 3's seven (rows 55–61) are
what close that. **Sixty-two mutations, every one red** — forty-four at implementation, seven in
**review round 1** (rows 46–52), two in **review round 2** (rows 53–54), seven in **review round 3**
(rows 55–61) and two in **review round 4** (rows 62–63) — run one at a time through a harness that
applies the edit, runs the owning suite, captures the first failure and restores the file, on
**4.0.6** (row 52 on **3.2.11**, the row whose parser the fact differs on). The table below numbers
sixty-three slots because two are placeholders for a mutation that was re-cut rather than a mutation of
their own. Rows 53 and 54 are the two shapes that SURVIVED review round 1; rows 55–61 and row 62
neutralise one of this phase's OWN assertions whole rather than mutating a subject — the only shape
that proves a committed double can report `:failed` — and row 63 removes a single `Check` from one, so
`XCUT-18`'s name/value asymmetry has a control of its own. All eleven are recorded as what
they were, a gap in this phase's own guards and not a gap in the code those guards watch.

Six shapes were re-cut: one spun forever and was killed rather than counted (a finding in its own
right, routed below), and five went green; **two of those five were not bad mutations but real
non-discrimination in this phase's own assertions**, and both were repaired before the mutation was
re-run — `XCUT-3`'s cancel could beat the waiter into the wait, and `XCUT-12`'s sixteen racers could
finish one at a time. Those two repairs are `P9-28` and `P9-29`, and they are the reason the mutation
pass is worth its cost.

| # | Mutation | Caught by (first failure) | Rows |
|---|---|---|---|
| 1 | `Headers#initialize` aliases the caller's Hash instead of `Model.own` | `XCUT-15: a model changed when a collection passed into it was mutated` | `XCUT-15` |
| 2 | `Closeable#close` runs `#release` on every call | `XCUT-13: close ran its release more than once (expected 1, got 2)` | `XCUT-13` |
| 3 | `Closeable#close` releases regardless of `owned:` | `XCUT-22: the SDK closed a resource it did not create` | `XCUT-22` |
| 4 | `HeaderSyntax.validate_name!` admits HTAB | `XCUT-18: a header NAME containing HTAB was accepted` | `XCUT-18` |
| 5 | `HeaderSyntax.validate_outbound_value!` refuses HTAB | `XCUT-18: an outbound VALUE containing HTAB was rejected` | `XCUT-18` |
| 6 | `BoundedMap#set` evicts once instead of draining | `XCUT-14: one insert into an over-cap map evicted once instead of draining back to the cap` | `XCUT-14` |
| 7 | `BoundedMap#set` has no cap at all | `XCUT-14: an insert burst pushed the map past its cap` | `XCUT-14` |
| 8 | `Body.buffer_bounded` multiplies its cap | `XCUT-24: an error-body snapshot materialised an unbounded payload` | `XCUT-24` |
| 9 | `Redactor`'s authority builder forwards the userinfo | `XCUT-19: "pw" survived URL redaction` | `XCUT-19` |
| 10 | `Redactor#header_name?` is default-ALLOW | `XCUT-19: the header allow-list is not default-deny` | `XCUT-19` |
| 11 | `Instrumentation.contain` re-raises after reporting | `RuntimeError: a sink exploded` (an `:error`, which is the point: it reached the caller) | `XCUT-20` |
| 12 | `Policy.cancellation?` stops walking the cause chain | `XCUT-1: a cancellation wrapped in a retryable transport error was not recognised` | `XCUT-1` |
| 13 | `Policy.throwable_retryable?` answers true for a cancellation | `XCUT-1: a cancellation classified retryable` | `XCUT-1` |
| 14 | *(superseded — see 22)* | | |
| 15 | `Reissue.strip` moves the `Authorization` removal behind the cross-origin test | `XCUT-17: Authorization survived a SAME-ORIGIN re-issue (clause a)` | `XCUT-17` |
| 16 | `Reissue.strip` drops the `Cookie` removal | `XCUT-17: cookie survived a CROSS-ORIGIN re-issue (clause b)` | `XCUT-17` |
| 17 | `Location` clears the userinfo with `= nil`, the documented silent no-op | `XCUT-17: userinfo in the Location survived the re-issue (clause c)` | `XCUT-17` |
| 18 | `Reissue.downgrade!` never raises | `XCUT-17: an HTTPS-to-HTTP downgrade was followed without opt-in (clause d)` | `XCUT-17` |
| 19 | `Auth::Step#enforce_https!` raises nothing | `XCUT-16: a credential was stamped over a plaintext transport` | `XCUT-16` |
| 20 | `Auth::Step` drops the cross-origin suppression | `XCUT-16: a credential-FREE cross-origin re-issue was refused by the HTTPS guard` | `XCUT-16` |
| 21 | `DigestHandler` draws from `::SecureRandom` instead of the injected source | `XCUT-21: the handler drew no bytes from the injected source` | `XCUT-21` |
| 21b | `Registry#install` becomes a no-op | `XCUT-23: an auto-discovered implementation beat an explicit install` | `XCUT-23` |
| 22 | `Clock#sleep` never subscribes the token | `XCUT-3: a pending inter-attempt wait was not released by a cancellation` | `XCUT-3` |
| 23 | `BearerStamper#refresh!` fetches outside the lock | `XCUT-12: a token refresh was not single-flight: every concurrent caller fetched` | `XCUT-12` |
| 24 | `Dexpace.each_cause` drops its visited test | `XCUT-9: the cause walk did not terminate after visiting the cycle once` | `XCUT-9` |
| 25 | `Registry#sole_key` picks the first of several candidates | `XCUT-23: two registered candidates with no explicit install did not fail loudly` | `XCUT-23` |
| 26 | *(the zero-candidate branch is the same method; covered by 25 and 21b)* | | |
| 27 | `Runner#one` rescues `StandardError` before `Vacuous` | `Expected: :vacuous / Actual: :error` | `NFR-17` |
| 28 | `Runner#waived?` matches the assertion NAME | `the preamble, the acceptances and the would-fail declarations reach the Report` | `NFR-17` |
| 29 | `Report#passed?` drops the blocking-vacuity term | `an acceptance naming one of two MUST ids still blocks, because accepted? is all?` | `NFR-17` |
| 30 | `Report#accepted?` becomes `any?` | the same | `NFR-17` |
| 31 | `Report#validate_citation!` admits a blank citation | `ArgumentError expected but nothing was raised` | `NFR-17` |
| 32 | `Report#unknown_ids` always answers empty | `Expected: ["XCUT-99"]` | `NFR-17` |
| 33 | `Levels.must?` counts an unknown ID as a MUST | `an unknown id never blocks` | `NFR-17` |
| 34 | `SharedInstance.audit` drops the frozen half of the disjunction | `a frozen instance holding state conforms on frozen? alone` (raised a `Failure`) | `XCUT-11` |
| 35 | `SharedInstance.audit` reads the declaration off the audited object | `a subject declaring its own per-call state as exempt is not believed` | `XCUT-11` |
| 36 | `Closeable#close` unlatched, seen through the pool's shutdown event | `XCUT-13, ASYNC-15: close shut the executor more than once` | `XCUT-13`, `ASYNC-15` |
| 37 | `Codec#dump_to` closes the sink it was handed | `SEAM-20, SERDE-3: the codec closed a caller-supplied sink` | `SEAM-20`, `SERDE-3` |
| 38 | `Codec#load` lets a bare `NoMethodError` escape | `SERDE-9: a failure outside the SDK's serde hierarchy escaped the seam` | `SERDE-9` |
| 39 | `Runner.run` builds one subject and shares it across the run | `the subject block is called once per assertion / Expected: 2, Actual: 1` | `NFR-17` |
| 40 | `Bridge::AsyncOver` owns and closes its executor | `XCUT-22, ASYNC-15: the SDK shut down an executor it borrowed` | `XCUT-22`, `ASYNC-15` |
| 41 | `PackagingSuite::Surface::LEAK` matches nothing | `a signature naming an async-framework type fails NFR-11 / Expected: :failed` | `NFR-11` |
| 42 | `Aggregate.by_requirement_id` defaults a missing result to `:passed` | `by_requirement_id reads each suite's DECLARED assertions, not a report's results` | `NFR-17` |
| 43 | one row deleted from `APPENDIX_B.md` | `every row's ID column equals the set parsed from that item's own text` | `NFR-17` |
| 44 | `Sharing` skips the driver's declared shared instances | `a shared instance the driver declares is audited too` | `XCUT-11` |
| 45 | `AstScan.parse` leaves `$VERBOSE` armed | `AstScan.parse's $VERBOSE window did not hold` | `XCUT-9`, `XCUT-14`, `SEAM-2` |
| 46 | `Shutdown#check_release`'s expired entry pop raises nothing | `[Vacuous] exception expected, not Failure: a worker blocked in an uninterruptible call was not released after cancel` | `ASYNC-3` |
| 47 | `check_posters_returned` keeps its bounded join and drops its `Check` | `Expected /did not return/ to match "work posted from many threads was lost or duplicated"` | `SEAM-12`, `XCUT-11` |
| 48 | `check_all_returned` keeps its bounded join and drops its `Check` | `Expected /did not return on every thread/ to match "a shared step crossed one call's request into another's"` | `XCUT-11` |
| 49 | `Dependencies#single_version_source` stops raising its vacuity | `with no single source named, NFR-14 is vacuous rather than a pass / Expected: :vacuous, Actual: :passed` | `NFR-14` |
| 50 | `PackagingCase::DEFAULT_RESOLVE` drops `::Gem::LoadError` | `Gem::MissingSpecError: Could not find 'dexpace-no-such-gem-…'` — 1 error, not 8 vacuities | `NFR-1`, `NFR-2`, `NFR-10`, `NFR-14`, `NFR-15` |
| 51 | `RequirementLevels::ROW` loses its nineteen-prefix restriction | `{"HTTP-7"…, "RFC-7235" => :must, "ISO-8601" => :should, …}` against a synthetic table | `NFR-17` |
| 52 | the duplicated-key capture is taken INSIDE the `$VERBOSE` window | `a duplicated key warns whatever $VERBOSE is` (3.2.11) | `XCUT-9`, `XCUT-14`, `SEAM-2` |
| 53 | `ExecutorCase#shutdowns` counts every recorder payload instead of matching `Keys::EVENT` | `XCUT-13 => :failed, XCUT-22 => :failed, SEAM-25 => :failed` against the chatty-but-conforming pool | `SEAM-25`, `XCUT-13`, `XCUT-22` |
| 54 | `Models#only_closes_what_it_created`'s second `Check` takes a literal `true` | `a holder that tears a borrowed resource down without closing it fails XCUT-22 / Expected: [:failed], Actual: [:passed]` | `XCUT-22` |
| 55 | `Concurrency#cancellation_is_terminal` neutralised WHOLE — `return nil if subject` as the body's first line, so no local is orphaned and the `-w` hook cannot mask the result | both new `XCUT-1` doubles: `a cancellation classifier that reads only the outermost error fails XCUT-1` and `a classifier that calls a cancellation retryable fails XCUT-1`, `Expected: [:failed]` | `XCUT-1` |
| 56 | `Concurrency#timeout_is_retryable_and_distinct` neutralised whole | both new `XCUT-2` doubles: the EXACT-type match and the message-matching classifier, `Expected: [:failed]` | `XCUT-2` |
| 57 | `Taxonomy#open_capability_query` neutralised whole | both new `XCUT-6` doubles: the outermost-only query and the concrete-type match, `Expected: [:failed]` | `XCUT-6` |
| 58 | `Taxonomy#configurable_status_set_is_authoritative` neutralised whole | both new `XCUT-7` doubles: the ANDed set and the wrong default, `Expected: [:failed]` | `XCUT-7` |
| 59 | `Classification#retry_safety_is_uniform` neutralised whole | both new `XCUT-10` doubles: the re-sent bare POST and the failure parameter, `Expected: [:failed]` | `XCUT-10` |
| 60 | `Security#redaction_is_default_deny` neutralised whole | both new `XCUT-19` doubles: the userinfo-forwarding redactor and the default-ALLOW header list, `Expected: [:failed]` | `XCUT-19` |
| 61 | `Memory#capped_non_consuming_preview` neutralised whole | the new `XCUT-24` double: a snapshot that multiplies its cap, `Expected: [:failed]` | `XCUT-24` |
| 62 | `HeaderSyntax#header_syntax_validation` neutralised whole — `XCUT-18`'s MODEL layer, the fourth survivor of round 3's sweep and the one no document named | both new model-layer doubles: `a validator that refuses nothing fails XCUT-18's model-layer assertion` and `an outbound-value rule identical to the NAME rule fails XCUT-18's HTAB clause`, `Expected: [:failed, :vacuous]` | `XCUT-18` |
| 63 | `HeaderSyntax#check_values` drops its HTAB-ACCEPTED clause, leaving the outbound-value rule a subset of the name rule | the symmetric double ALONE: `an outbound-value rule identical to the NAME rule fails XCUT-18's HTAB clause`. The permissive double still fails on the NAME clauses, which is why the asymmetry needs a second one | `XCUT-18` |

One more shape was cut and then **killed rather than counted**: conditioning `Registry#resolve`'s
`return hand_out(resolved)` guard on anything else turns its `loop do … end` into an unbounded spin with
no progress, and it ran for six minutes before it was stopped. That is not a guard going red; it is the
finding routed below, and the two mutations that replaced it — 21b and 25 — are what prove `XCUT-23`.

A second shape is recorded the same way, and for the same reason. Restoring `Shutdown#check_release`'s
entry pop to the unbounded `transport.entered.pop` review round 0 found there — row 46's mutation taken
one step further — leaves the refusing-executor test with nothing to return to: the run was still
parked when `timeout 90` killed it, and the same removal at the two join sites is caught instead, by
Ruby's own deadlock detector, as `fatal: No live threads left. Deadlock?`. That asymmetry is why rows
47 and 48 drop the `Check` and keep the bounded join: a mutation the interpreter aborts proves the join
runs, not that an expired one is reported. The hang itself is the defect `P9-34` fixes, demonstrated; it
is not a guard going red and it is not counted among the sixty-two.

Beside the mutations, the three new gates are each driven against a deliberately failing **fixture
workspace** through `DEXPACE_GATE_ROOT` (`test/fixtures/gates/invariants/workspace/`), and
`gates:serde_boundary`'s abort branch against a `RUBYOPT` prelude fixture. Those four routes did not
exist when the mutation pass began and the first of them found a real defect — `P9-27`.

---

## Audit groups run

The phase-start pair first, at implementation on 2026-09-23: `--origin note --brief` and
`--section conflicts --brief`, the latter returning every one of the six harvested conflicts
`[overridden by notes/…]` and none open. `--req` was run per task against the IDs each task names.

**This phase's own audit group did not exist and was added to the table** in
`.claude/skills/knowledge-lookup/SKILL.md`, because an audit whose group is not written down cannot be
repeated: **Cross-cutting invariants and the quality bar** —
`--topic cross-cutting-invariants,tooling-and-quality-gates,resource-management --section rules --brief`
and `--prefix XCUT,NFR --section rules --brief`. Run on 2026-09-23: **41 entries across 12 topic files**,
and `--gaps XCUT,NFR` answers **0 of 41** — every one of this phase's IDs has a substantive corpus entry,
none roll-up only, so nothing here had to be read out of the specification instead.

| Group | Result at implementation |
|---|---|
| Cross-cutting invariants and the quality bar | The new row above. Two of its entries are this phase's own, filed at design time — `cross-cutting-invariants/89eb6533`'s audit consequence and the AST-gates entry — and both were re-read in full before the code they describe was written; one of the two is CORRECTED by execution, in a new entry rather than an edit (`gates:drain_loop` was not built) |
| Public API surface | Every new group module is a `private_constant`, so `tools/surface.rb`'s `Module#constants(false)` walk does not see it — 8a's `TransportSuite` precedent. Each suite's public surface is exactly `assertions`, `run` and `PREAMBLE`; two leaks found by reading the regenerated manifest row by row were closed rather than accepted (`P9-25`) |
| Gem layout, zero-dependency core | `dexpace-conformance` still declares `dexpace-core` alone; the new files add no require outside the allowlist; `gates:clean_bundle` green on every row |
| RBS / Steep typing | Every new `lib/` file has a `sig/` mirror, the `private_constant`s carrying `hooks.rbs`'s comment; both targets green with no relaxation added. One signature is deliberately INCOMPLETE and says so: `invariant_suite/credentials.rbs` omits `include ::Random::Formatter`, because `tools/rbs_surface.rb`'s `STDLIB_ALLOWED` does not carry `Random` and widening a gate's allowlist for a test double is lowering the gate (`P9-26`) |
| Minitest conventions | Every suite subclasses `DexpaceTestCase` or `GateCase`; no `.stub`; mutable fixtures built fresh per test. No `sleep` anywhere in the suites' own logic or in any assertion — every wait there is a queue pop with a timeout, a bounded join or a bounded `Thread.pass` spin on `Thread#status`. **One deliberate `Kernel.sleep` exists, in a non-conforming DOUBLE**: `invariant_suite_test.rb`'s `BlockingCloseSeam#close` sleeps `0.6` on its first close, past `XCUT-13`'s half-second bound, because a double whose whole job is to block past a bound has no other way to do it — and without it that clause would pass against every subject the suite can build |
| Fiber scheduler, thread safety | The two-fibers-on-one-thread assertion is the shape 8b handed forward; the barriers added in `P9-28` and `P9-29` use `Thread#status` and never a sleep |
| Observability, configuration and redaction | `XCUT-19`'s and `XCUT-20`'s assertions are scoped to what 5b and 5c own and are not widened to a foreign callback |

---

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate. The
corresponding ledger rows are `P9-21`–`P9-42` in the design's As-built addendum.

1. **`dexpace-serde-json`'s and `dexpace-core`'s existing files are byte-identical** — the plan's Task 10
   removes `assert_closes_nothing`'s and `assert_failure_model`'s portable halves from 7a's
   `serde_seam_assertions.rb` and drops two calls from its driver. Nothing was removed: the two
   `CodecSuite` assertions are RE-DERIVED from the requirement text, so `SEAM-21`'s type-token clause and
   the encode half of `SERDE-9` — both of which live inside the bodies a lift would have moved — stay
   alive in 7a's suite. `P9-22`.
2. **`MinitestDriver` is not used by any of the three drivers.** 8a wrote it around `TransportCase` and
   `R6` keeps phase 9 out of phase 8's file. Each driver carries its own six-line loop instead; the
   residue — two driver loops in one repository — is stated rather than hidden. `P9-23`.
3. **`test/support/gate_warning_capture.rb` deliberately does not require `dexpace_test_case`.** The plan
   said to, so the two prepends land in order. Measured: `test/gates/` runs on `GateCase`, which does not
   install `FatalWarnings`, and arming it from a support file armed it for the whole `test:gates` process
   — where three deliberately-invalid gemspec fixtures and YARD's own load-time warnings had always
   reached `Warning.warn` harmlessly. Four pre-existing gate tests went red. The file ships the RECORDER
   and not the raiser, and the scanner's warning property is proven by recording. `P9-24`.
4. **The bounded-map allowlist was re-adjudicated against as-built paths, and the plan's one expected
   true positive is a false positive.** The plan's Task 16 Step 3 expects `gates:bounded_map` to report
   `async_http/clients.rb`'s `@by_origin` as an uncapped cache. The as-built name is `@by_key` and it IS
   capped: `Clients#fetch` calls `#drain` inside the same `@mutex.synchronize` as the insert, and `#drain`
   is a loop — `evicted << @by_key.delete(@by_key.keys.first) while @by_key.size > MAX_ORIGINS`, closed
   reactors first — which is `XCUT-14`'s drain clause exactly. Verified by reading the file on
   2026-09-23. So the gate is GREEN, `XCUT-14`'s row is ✅ rather than ⏳, no phase-10 inbound bullet is
   filed for it and no `docs/first-release.md` blocker is opened — and the standing blocker that waited
   on this verification is ticked rather than a new one filed. The allowlist that remains after the
   re-adjudication is six entries, each with its written reason in `tools/invariant_gates.rb`, and the
   integrity test asserts that every entry names a live file the scan still reports at that site — the
   clause whose absence let the stale `configuration.rb` key survive a whole adjudication. `P9-37`.
5. **Two assertions this phase wrote did not discriminate, and both were repaired.** `XCUT-3`'s cancel
   could be issued before the waiter entered the wait, and `XCUT-12`'s racers could finish serially. Both
   now assert a parking barrier as a `Check` of its own, so a run that could not have discriminated
   reports `:failed` and never `:passed`. Found by the mutation pass. `P9-28`, `P9-29`.
6. **The three new gates' `DEXPACE_GATE_ROOT` route was broken and is fixed.** The tasks handed the
   scanner paths made relative to the gate root, which it then opened relative to the process's CWD — the
   same directory only when the variable is unset. Under a fixture root every open raised `Errno::ENOENT`,
   so the three gates could never have been shown to reject anything. They now scan absolute paths under
   the root, join both allowlists to the same root, and make the message relative afterwards; a fixture
   workspace and four tests keep it fixed. This is a defect in this phase's own code and is therefore
   fixed rather than routed. `P9-27`.
7. **`gates:serde_boundary`'s abort branch and `--check`'s failing exit had no test.** `PENDING` is a
   frozen constant with no root or environment that can make the task see a non-empty one, and
   `RequirementLevels::TARGET` is fixed — so a mutation deleting the abort, and one making `--check`
   always exit 0, both left every test green. A `RUBYOPT` prelude fixture drives the first; an optional
   path argument on `--check` drives the second. `P9-30`, `P9-31`.
8. **The reviewer's mutation list is not quoted here.** It was in this run's opening brief and did not
   survive the session's context compaction. The forty-four mutations run at implementation were
   re-derived from the design's testing strategy and the plan's per-task "non-conforming double" rule;
   the count exceeds the
   thirty-five the brief named as a minimum, but the SET is this phase's and not the reviewer's, and a
   reviewer re-running the original list should expect to find it covered rather than assume it. `P9-32`.
9. **`SEAM-25`'s harness half is recorded as a correction to a committed record.** 8b's design said the
   harness half was 8a's; 8a wrote no executor suite. Phase 9 writes it, and says so out loud rather than
   restating the earlier record as though it had been right. `P9-21`.

### Review round 1, 2026-09-24

Two further departures, both repairs to **this phase's own gem** — `R6` bars phase 9 from repairing what
it AUDITS, and `dexpace-conformance`'s new code is what it wrote, the same standing `P9-27` has.

10. **Three waits in the new suites carried no bound, and one of them hung.** `Shutdown#check_release`
    opened with an unbounded `transport.entered.pop`; against an executor that REFUSES the post —
    `ASYNC-2`'s saturated queue, or a closed pool — nothing is ever pushed, the poster rescues the
    refusal, and the run never returns, with the `ensure` that frees the gate and closes the pool never
    reached. Demonstrated, not argued: with the bound removed the refusing-executor test was still
    parked when `timeout 90` killed it, and the reviewer's own probe — the same assertion on a thread
    joined at eight seconds — reported `:HUNG` where it now answers
    `[:vacuous, "the executor did not start the posted unit within 1.0s …"]`. The two `.each(&:join)`
    sites — `concurrent_post` and
    `drive_threads` — had the same shape against a subject whose submission or whose shared call never
    returns. All three now carry a bound, 8a's own rule for this gem
    (`await_closed_connection`'s `timeout:`), and the expired entry wait is `:vacuous` with its reason
    rather than `:failed`, because with no unit started there is no blocking worker to cancel.
    Rows 46–48. `P9-34`.
11. **`PackagingCase::DEFAULT_RESOLVE` never caught the error it exists to catch**, and writing the test
    review round 0 asked for is what found it: every case in `packaging_suite_test.rb` supplied its own
    `resolve:`, so the SHIPPED lambda had never run. `Gem::MissingSpecError` descends from
    `Gem::LoadError < LoadError < ScriptError` and is **not** a `StandardError`, so `rescue
    ::StandardError` let it past — and past `Runner`'s bare rescue too, aborting the whole run where the
    contract is one `:vacuous` naming the absent unit. Row 50. `P9-35`.

### Review round 2, 2026-09-24

Two further departures, both repairs to guards this phase wrote, found by re-running two shapes from
the brief's own minimum mutation list that review round 1 measured as SURVIVING.

12. **`XCUT-22`'s second clause could not fail.** `InvariantSuite::Models#only_closes_what_it_created`
    makes two `Check`s against one `Borrowed` double: it was not closed, and it still works. `usable?`
    was `!@closed` — the exact negation of the `closed?` the first `Check` already reads — so no subject
    the suite can build separated them, and replacing the second `Check`'s condition with a literal
    `true` left the whole gem's suite green. The comment above it and this checklist's own `XCUT-22` row
    both claimed the opposite. `Borrowed` now carries the other route the requirement implies: `#finish`
    is the adapter-side teardown reached without going through `#close` — `Net::HTTP` spells it exactly
    that — and `usable?` reads both flags. `TearingSeam` drives it. Row 54. `P9-38`.
13. **`SEAM-25` was "one sink write" as tested, not "one shutdown EVENT".** `ExecutorCase#shutdowns`
    matches the payload's `Keys::EVENT` entry, and every double in `executor_suite_test.rb` emitted the
    shutdown payload and nothing else, so replacing that match with a bare `entries.count` left the
    file, the pool driver and the whole `rake test:gems` green — while four assertions read that count.
    `ChattyPool` logs one other event payload and one bare String message at construction, which is
    conforming and which nothing in the SPI forbids; the mutation now reddens `XCUT-13`, `XCUT-22` and
    `SEAM-25` together. No code changed: the code was right and only the guard was missing. Row 53.
    `P9-39`.

### Review round 3, 2026-09-24

Two departures, one of them a document repair and the other the same class of defect rounds 1 and 2
found: a guard this phase wrote that could not go red.

14. **`R6`'s one sanctioned exception was recorded nowhere, and two sentences could not both hold.**
    The driver for `InvariantSuite` is `gems/dexpace-core/test/dexpace/cross_cutting_invariants_test.rb`
    — one ADDED file, no existing core file modified, renamed or deleted — and that is what design
    `P9-9` means by "the driver is `dexpace-core`'s own suite and knows which ivar is which". The
    design's Module layout says the opposite in as many words ("no file in `gems/dexpace-core/` at
    all"), and this checklist's and the roadmap's boundary sentences enumerated the trees phase 9
    changed without naming it. All three now name the file and the narrow bend it is, and `P9-40`
    records the contradiction by pointing at both sentences. Nothing in the tree changed: the boundary
    was always one added test file, and a reader could only learn that by running
    `git diff --name-status`. `P9-40`.
15. **Seven `XCUT` assertions had no committed non-conforming double, and five could be neutralised
    WHOLE with the suite green.** `XCUT-1`, `XCUT-2`, `XCUT-6`, `XCUT-7`, `XCUT-10`, `XCUT-19` and
    `XCUT-24`: nothing in the repository drove a subject that made any clause of the first five fail,
    so each reported `:passed` because it could not report anything else, and the evidence paragraph
    above and the Guards preamble both claimed otherwise. `invariant_suite_core_test.rb`'s own header
    made it worse by naming `XCUT-6`, `XCUT-7` and `XCUT-10` among the IDs it drove. Thirteen defective
    stand-in cores now drive all seven, in the shape that file already used — a patched `Resilience`
    whose `const_missing` falls through, so one test changes one subject. Measured: neutralising each
    of the seven assertions whole and warning-free reddens exactly the new tests for it, thirteen
    across the seven (rows 55–61). No first-party code changed: the assertions were right and only the
    negative controls were missing. `P9-41`.

### Review round 4, 2026-09-24

One departure, and it is the same class narrowed by one row: a guard this phase wrote that could not go
red, found by counting assertions where this document counted rows.

16. **`XCUT-18`'s model-layer assertion had no committed non-conforming double, and no document named
    it.** Review round 3's sweep neutralised all forty-five assertion bodies in the four suites one at a
    time; four survived, and three were accounted for — `XCUT-3`'s and `XCUT-12`'s, which this checklist
    names, and a private clause helper whose parent assertion is caught. The fourth,
    `HeaderSyntax#header_syntax_validation`, could be neutralised whole with the whole of
    `rake test:gems` green: both of its committed tests pin the model assertion `:passed` and drive the
    call-site one. The evidence paragraph above could not see it, because it counted **rows** and
    `XCUT-18` carries two assertions — the row was covered on one of them. Two defective stand-in cores
    now drive it: a permissive validator that refuses nothing, and one that applies the NAME rule to
    outbound values as well, so the asymmetry that IS the requirement has a control of its own rather
    than resting on the real subject. Measured: neutralising the assertion whole reddens both (row 62),
    and deleting the HTAB-accepted `Check` alone reddens the second (row 63). No first-party code
    changed. `P9-42`.

---

## Findings routed

Nothing below is repaired here. Each is routed to its owner with its evidence, per design `R6`.

| Finding | Evidence | Routed to |
|---|---|---|
| **307 of 307 shipped `.rbs` files carry no SPDX header**, in all six gems — `NFR-13`'s conformance clause is "scan ALL source files" and `sig/` ships inside every gem | The aggregate run's one failure, 2026-09-23; `grep -rl "SPDX-License-Identifier" gems --include='*.rbs'` answers 0 of 307 | **Already owned**: phase 10's design addendum `A8` (`gates:spdx_rbs`) and its inbound row 8, which name this very assertion. Verified still owned on 2026-09-23 and NOT re-recorded |
| `PackagingCase`'s default gem-name → constant-path rule cannot produce `Dexpace` for `dexpace-core` or an acronym-cased leaf (`NetHTTP`, `AsyncHTTP`, `JSON`), so four of six gems need the `constants:` override a driver supplies. A driver that omits it gets a `:vacuous` with an actionable message, never a wrong answer | The aggregate run's first pass reported `Dexpace::Core is not loaded` | phase 10's inbound list (dated 2026-09-23) — a defaulting rule that covers the port's own six is a repair, not a report |
| `Registry#resolve`'s discovery loop spins forever when `@state.resolved` is set but a candidate remains registrable — reachable only by a code change, but the loop has no bound at all | Found while cutting a mutation: `return hand_out(resolved) if resolved && @state.factories.empty?` turned `#resolve` into an unbounded `loop do` with no progress. The shipped code is correct; the LOOP's lack of a bound is the finding | phase 10's inbound list (dated 2026-09-23) |
| `XCUT-12`'s fiber-scheduler form is unasserted: the requirement's "wait-free hot-path read" and single-flight clauses are proven for threads only, because a credential path under a reactor is a composition no first-party suite assembles | `invariant_suite/resolution.rb`'s own comment; the assertion names the thread form explicitly | phase 10's inbound list (dated 2026-09-23) |
| `XCUT-9`'s stated residue: a collect-then-yield cause walk never returns a step to count, and a depth cap of exactly three passes the cycle assertion. `gates:cause_walk` is the second line and proves neither absent | `invariant_suite/classification.rb`'s comment, written before the assertion | phase 10's inbound list (dated 2026-09-23) |
| 7a's `SEAM-21` evidence lives inside `assert_closes_nothing`'s body and has no assertion of its own; the re-derivation left it there deliberately, but it is undeclared in any ID-keyed map | `P9-22`; `APPENDIX_B.md`'s `B.3` rows | phase 10's inbound list (dated 2026-09-23) |
| `tools/surface.rb` cannot see a `private_constant` module, so a group module that became public would be invisible to `gates:surface_snapshot` until its methods leaked | Found by reading the regenerated manifest row by row (`P9-25`): two real leaks were present and were closed | phase 10's inbound list (dated 2026-09-23) |

---

## Postponed work

Everything the design postponed is VERIFIED still owned rather than re-recorded, per the phase workflow.
The five entries in the design's "Work phase 9 postponed, and who owns it now" table stand as written;
their owners — `docs/first-release.md` § Post-release triggers and § Release path — were re-read on
2026-09-23 and each names the entry it was given.

`NFR-16` is the one requirement row this phase leaves ⏳, and its owner is the `NFR-12`/`NFR-16` entry
under § Release path. `NFR-8` and `NFR-9` are N/A with their reasons above and are not deferred: there is
nothing to pick up.
