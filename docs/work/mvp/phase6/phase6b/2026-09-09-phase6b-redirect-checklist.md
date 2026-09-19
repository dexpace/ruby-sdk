# Phase 6b — Redirect: Checklist

**Written at execution time, 2026-09-19, from what was built** — not from the plan. A row whose task
did not do what the plan said is a row that says so, and the "Deviations from the plan" section
below is where each departure is stated with its reason. The design and the plan were written on
2026-09-09 (reviewed 2026-09-13) against phases 0–3's *plans* and phases 4 and 5's *designs*, on a
machine that then had only Ruby 3.4.10, concurrently with 6a's and 6c's documents and before either
was built. Since then phases 4a–5c were built and merged, every interpreter in the matrix was
installed, and phases 6a (#72–#74) and 6c (#75–#77) were built in parallel, each approved by
independent review, and merged. **This phase was cut from `main` at `e61864f`**, which holds both,
so it is the lane that landed **last**, and three things the charter left to "whichever lands
second" are its: Task 2 extended 6a's `resilience/resend.rb` in place rather than creating it; Task
13a — `Pipeline.standard` and `AsyncPipeline.standard`, the constructors phase 4c postponed —
executed here over 6a's `RetryStep` / `AsyncRetryStep` and 5b's steps; and convergence point 1, the
end-to-end cross-origin credential-leak test 6c wrote guarded, was un-guarded here against the real
step. The `Cursor` context-bundle widening (6a's Task 8) exists on this base and was **consumed not at
all** — a `Bundle` carries a span tracer factory and trace ids, not a logger — so the step ships its
own `logger:` keyword, as the design's Independence section committed to. Where the plan's text and
the built tree disagree the tree wins and this document records it.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase6/phase6b/2026-09-09-phase6b-redirect.md`. Task numbers are that plan's
(fourteen plus 13a). Design: `docs/work/mvp/phase6/phase6b/2026-09-09-phase6b-redirect-design.md`,
whose Deviation Ledger numbered nothing before execution and whose as-built rows **P6-91–P6-100**
are cited below (6a's rows are cited as "6a's P6-n", 6c's as "6c's P6-n"; the manager fixed the
numbering so the three lanes never collide); the charter is
`docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md`. Every test file named here is under
`gems/dexpace-core/test/`, mirrors its `lib/` file one for one (three carry no `lib/` mirror and say
so below; five `private_constant`s carry no `test/` mirror and are asserted at their call sites), and
opens with the IDs it exercises.

## Requirement rows

Twenty-eight own rows — `REDIR-1`–`REDIR-28` — plus the phase-level rows (the two `standard`
constructors' `PIPE-39`, `PIPE-32` and `PIPE-24`, and convergence point 1) and the cross-reference rows
for the non-`REDIR` IDs this phase owns a share of, taken from the design's interface tables and the
charter's spec-forced boundaries the way 6a and 6c carried theirs. **Twenty-seven ✅, one ⏳**
(`REDIR-27`, declined for v1), nothing 🚫, nothing N/A; `REDIR-11`'s row states its three clauses and
`REDIR-25`'s row states that it is no longer vacuous.

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `REDIR-1` | MUST | ✅ | 9 | `Step::RECOGNIZED_CODES` (private) is exactly `{301, 302, 303, 307, 308}` and the loop's first line after the drive returns any other status as it is — 200, 204, 300, 304, 305, 400, 404, 500, 503 each pass through once, open, with no snapshot allocated and no predicate consulted (`step_test.rb` `DecisionTest`, "a non-3xx and a non-recognized 3xx pass through"; `PredicateTest`, "NEVER consulted for a non-recognized status"; guard 27) |
| `REDIR-2` | MUST | ✅ | 9 | 300, 304 and 305 are in the pass-through set above **with** a `Location` header present, so none is followed and 305 can never redirect to a server-chosen proxy (the same test, each of the three with `location: "https://a.example/y"`) |
| `REDIR-3` | MUST | ✅ | 8, 9, 12 | A 301 or 302 is followed iff the **original** request's method — `Chain#seed_method`, captured at the seed and never re-read off the current hop — is in the allowed set, default `Step::DEFAULT_ALLOWED_METHODS = {GET, HEAD}`, a fresh frozen `Set` of `Method`s and deliberately not `Method::IDEMPOTENT`: `OPTIONS`, `PUT`, `DELETE`, `POST` and `PATCH` are not followed by default, `GET` and `HEAD` are; and when followed the method and the body are preserved — no `POST` → `GET` rewrite. The seed-method rule's witness is `POST` → 303 → `GET` → 301, which stops at the 301 under the default set although the chain is now a `GET` (`step_test.rb` `ConstructionTest`, "the default is NOT Method::IDEMPOTENT"; `ReissueTest`, "the ORIGINAL method decides"; guards 31, 32) |
| `REDIR-4` | MUST | ✅ | 8, 12 | 307 and 308 take the same allowed-set decision and re-issue with the method and the **same body object** (`assert_same` on a replayable `FakeBody` through a `PUT` 308; a `POST` 307 under `allowed_methods: ["POST"]` is re-issued as a `POST`) (`step_test.rb` `ReissueTest`, "a replayable body is re-sent as the SAME object", "a body-LESS POST 307 is re-issued") |
| `REDIR-5` | MUST | ✅ | 8, 12 | `follow303: false` by default (a 303 over a `POST` returns as it is); opted in, `Reissue.rebuild_as_get` re-issues a `GET` with `body: nil` and every `Content-*` header removed **by prefix** under the no-argument fold — `Content-Type`, `Content-Length`, `Content-Language` and `Content-MD5` all gone, `Accept` kept — whatever the original method, and `Authorization` stripped with them (`REDIR-7`); a 303 over a NON-replayable body is followed, because it drops the body (`step_test.rb` `ReissueTest`, the four `REDIR-5` 303 cases; guards 33–35) |
| `REDIR-6` | MUST | ✅ | 2, 12 | Every method-preserving hop passes `Resilience::Resend.replayable_body?(request)` — `body.nil? \|\| body.replayable?`, phase 3b's own predicate, added beside 6a's `.eligible?` and **never** `.eligible?`, which folds in `RETRY-7` and would refuse a body-less `POST` 307 the allowed set admits — and a present non-replayable body raises `Dexpace::NotReplayableError`, whose message names replayability, with the redirect not attempted and the current response closed first (`REDIR-22b`); a body-less `POST` is re-issued; the predicate's source is scanned for `idempotent`/`method` and the two predicates part on exactly the bare `POST`. The three spellings of one predicate across 6a, 6b and 6c are on phase 10's inbound list (routed by 6c; cited below, not re-filed) (`resend_test.rb` `ReplayableBodyTest`; `error/not_replayable_error_test.rb`; `step_test.rb` `ReissueTest`; guards 36, 37) |
| `REDIR-7` | MUST | ✅ | 10 | `Reissue.strip` removes `Authorization` on **every** re-issue through `Headers::Builder#remove` — same-origin, cross-origin and the 303 rebuild alike — and the proof is on every intermediate request, never only the last: an AUTH-position `CredentialProbe` records, per drive, whether the request STILL carried the caller's `Authorization` when it arrived (`["Bearer caller-token", nil, nil]` over a seed → same-origin → cross-origin chain) and what the transport then saw (`["Bearer probe-token", "Bearer probe-token", nil]`: re-stamped by the probe on the same-origin hop, suppressed on the cross-origin one); with no AUTH step at all no re-issue carries the caller's header (`step_test.rb` `CredentialHygieneTest`, both `REDIR-7` cases; the convergence test below; guards 1, 2) |
| `REDIR-8` | MUST | ✅ | 3, 10 | `Origin.of(uri)` is `[scheme.downcase, host.downcase, port]` — the bare fold, `URI#port` supplying the scheme default (verified fact 3), `to_s` making the triple total over an opaque seed — and every comparison is against the **seed** request's triple (`Chain#seed`, computed once per operation), never the previous hop's. Both chains the design names: (i) A → A → B marks hop 2 cross-origin although the previous hop was A too; (ii) A → B → B keeps hop 2 cross-origin — `[false, true, true]` — and keeps the `Cookie` off the wire on hop 2, which a previous-hop comparison would put back. `A.EXAMPLE`, `:443` and `HTTPS://` are the seed's origin; `:8080` and `http://` are not (`step_test.rb` `CredentialHygieneTest`, the four `REDIR-8` cases; guards 4–6; guard 3 is the equivalent mutant, below) |
| `REDIR-9` | MUST | ✅ | 10, 12 | On a cross-origin hop `Cookie` and `Proxy-Authorization` are removed beside `Authorization`, on the method-preserving re-issue and the 303 rebuild alike (the strip runs before the rebuild), and **each clause has its own proof**: the method-preserving one in the same-then-cross chain, the 303 one over a `POST` carrying both headers under `follow303: true` — a 303 to a foreign origin rebuilds a `GET` carrying none of `Cookie`, `Proxy-Authorization`, `Authorization` or `Content-Type` and keeping `Accept`, while the same 303 to the seed's origin keeps the two origin-scoped headers and drops the other two (`REDIR-10` on the rebuild). Review round 0 found the rebuild clause unproven — a strip that kept the two headers on a cross-origin 303 survived the suite — and the case was added; a scheme change is a different origin, so the downgrade opt-in strips them too (`step_test.rb` `CredentialHygieneTest`, "Cookie and Proxy-Authorization are retained same-origin and stripped cross-origin, in one chain"; `ReissueTest`, "REDIR-9 / REDIR-10 on the 303 rebuild"; `LocationTest`, "the opt-in permits the downgrade"; guards 8, 52) |
| `REDIR-10` | SHOULD | ✅ | 10 | On a same-origin hop `Cookie` and `Proxy-Authorization` travel and only `Authorization` is stripped — asserted in the same chain as `REDIR-9`, so the two clauses cannot both degrade to "always strip" or "never strip" (the same test; guard 7) |
| `REDIR-11` | MUST | ✅ | 10, 14 | Three clauses. **(a) structurally**: the marker is `cursor.fork(state: { cross_origin: bool })` into the REDIRECT pillar's own slot, written on **every** drive — `false` on the seed's own and every same-origin hop, `true` on every cross-origin hop, never omitted (the plan's resolved question 3) — and a `Location` value has no code path to `#fork`'s `state:`; a forged `X-Dexpace-Cross-Origin` request header changes nothing, and nothing of the step's appears on the wire. **(b) 6c's**: "only SUPPRESS stamping, never CAUSE a credential to be sent" is the reader's clause — 6c's `AUTH-29` row and its `REDIR-11 (clause b)` cross-reference row. **(c) a fortiori**: nothing was added to the request, so nothing is removed before dispatch. 4c's R11 assertion 4 is extended to the real step — a `ForkingProbe` at RETRY writing `{cross_origin: true}` into its own slot is invisible under `Stages::REDIRECT` to a `StateProbe` at AUTH, which reads exactly what the production step wrote — and assertion 5 too: a second, independent chain on the same pipeline never sees the first's marker (`step_test.rb` `MarkerTest`, all four cases; guards 9–11) |
| `REDIR-12` | MUST | ✅ | 1, 4, 11 | `Location.resolve` clears the resolved target's userinfo with `userinfo = ""` — never `= nil`, the silent no-op verified fact 1 measures on every row and `docs/knowledge/notes/redirect-handling.md` records — after the scheme-and-host screen (the writer raises on an opaque URI) and before the freeze (a frozen URI raises); a user-only and a password-only userinfo are stripped too. Asserted on the **rendered URL the transport received**, never on `#userinfo` (`step_test.rb` `LocationTest`, two `REDIR-12` cases; `matrix_facts_test.rb`; guard 12) |
| `REDIR-13` | MUST | ✅ | 1, 4, 11 | One call to `URI::RFC3986_PARSER.join` and no re-rendering: `https://user:pass@h/a%2Fb?x=%26y%2Bz` reaches the wire as `https://h/a%2Fb?x=%26y%2Bz`, `https://[2001:db8::1]:8443/p%2Fq` byte for byte. **The residue, stated and not hidden**: an EXPLICIT scheme-default port is elided — `Location: https://a.example:443/y` reaches the wire as `https://a.example/y` — because `URI#to_s` drops it on every supported Ruby and phase 1's `URL.parse!` re-parses a URI from its text (5b's P5-91); the origin triple reads the parsed port and is unchanged, every non-default port survives, and the suite never asserts that `:443` survives (P6-96) (`step_test.rb` `LocationTest`, three `REDIR-13` cases; `matrix_facts_test.rb`; guard 13) |
| `REDIR-14` | MUST | ✅ | 1, 4, 11 | A relative `Location` resolves against the **current** hop — `/v1/x` → `/v2/a/b` → `c` → `/v3/x` sends `https://h/v2/a/c`, not `https://h/v1/c` — a query-only, a fragment-carrying and a network-path reference all resolve, and an absolute value is used as-is after the strip (`step_test.rb` `LocationTest`, two `REDIR-14` cases; `matrix_facts_test.rb`; guard 14) |
| `REDIR-15` | MUST | ✅ | 6, 11 | `Reissue.downgrade!` compares the two schemes with a bare `downcase` per hop: `https` → `http` emits `Events::SCHEME_DOWNGRADE_REJECTED` and raises `Redirect::SchemeDowngradeError` — a `Dexpace::Error` naming the two authorities and the opt-in, never a path or query — after the current response is closed (`REDIR-22b`); `http` → `https` → `http` fails on the second transition; `allow_scheme_downgrade: true` follows it and emits `SCHEME_DOWNGRADE_PERMITTED`, never the rejected name, and the credential stripping still applies (P6-97) (`scheme_downgrade_error_test.rb`; `step_test.rb` `LocationTest`, three `REDIR-15` cases; `EmissionTest`, "the rejected downgrade is emitted"; guards 15–17) |
| `REDIR-16` | MUST | ✅ | 9, 12 | `Chain#visited` is a `Set` of `URL.external_form` Strings seeded with the seed's URL and grown by one per followed hop; a target already in it returns the **current** response — the same object, `closes` 0 — without raising, a revisit of the seed and of an intermediate hop alike, and emits `LOOP_DETECTED` (`step_test.rb` `DecisionTest`, two `REDIR-16` cases; `EmissionTest`; guards 18, 19) |
| `REDIR-17` | MUST | ✅ | 8, 9 | `max_hops:` defaults to `DEFAULT_MAX_HOPS = 3`, must be a non-negative Integer, and `0` disables following entirely; on reaching the cap the last response is returned as it is, a 302 included, open. **The order as built** (P6-91): the cap is checked LAST, over the predicate's answer — the predicate is consulted at the capped hop too (`[0, 1]` seen with `max_hops: 1`) and its `true` is then vetoed; the design's ledger paragraph and the roadmap's 6b note say "before", and the As-built addendum corrects them (`step_test.rb` `ConstructionTest`; `DecisionTest`, two `REDIR-17` cases; `PredicateTest`, "the cap vetoes a predicate that says FOLLOW"; guards 20, 21) |
| `REDIR-18` | MUST | ✅ | 4, 9, 11, 13 | Never throws: `Step#resolve` is one `rescue ::URI::InvalidURIError` — BY CLASS, never by message, which differs between uri 0.13.3 and 1.x — that logs the RAW value and answers nil, the "return current" signal, and `Location.resolve` raises that one class for a malformed reference (`ht!tp://user:pass@bad`, a space, `<`, a non-ASCII byte, `:notaport`), for an unsupported scheme (`mailto:`, `ftp:`, `javascript:`, `data:`) and for a host-less target (`http:foo`, `http:///p`, `https://`) — the third the design did not name (P6-95). The current response is returned open, on both decision routes (`step_test.rb` `LocationTest`, two `REDIR-18` cases; `PredicateTest`, "unsupported scheme ... on BOTH decision routes"; `matrix_facts_test.rb`; guards 22, 23) |
| `REDIR-19` | MUST | ✅ | 9 | A missing or empty `Location` returns the response unfollowed and open before the parser is ever reached — `join(base, nil)` raises `ArgumentError`, not the class the rescue expects (verified fact) — and a predicate answering FOLLOW does not change that (`step_test.rb` `DecisionTest`, "no Location, or an empty one"; `PredicateTest`, "a predicate that says FOLLOW on a Location-less 3xx"; guard 24) |
| `REDIR-20` | MUST | ✅ | 5, 9 | `predicate:` — anything `Registry.callable?` accepts at arity 1 — fully overrides the built-in decision: it follows a `POST` 302 and a revisit the default would refuse, and refuses a `GET` 302 the default would follow. It receives `Redirect::ConditionSnapshot`, a frozen `Data` in the phase-1 shape (`.build(response:, redirect_count:, visited_uris:)`, `.new` private, `Model.required!` naming the member, `#with` through `.build` on every interpreter) whose `visited_uris` is copied through `Model.own` — deep, so a String the caller still holds cannot reach it — and frozen, so a predicate that mutates it meets `FrozenError` and the loop is unaffected; insertion order is kept (verified fact 4). Three things it cannot lift: `REDIR-18`/`REDIR-19` (nil target → unfollowed whatever it answered), the credential hygiene, and the cap (`condition_snapshot_test.rb`; `step_test.rb` `PredicateTest`; guard 25) |
| `REDIR-21` | SHOULD | ✅ | 9 | A non-recognized status returns before anything is allocated and never consults the predicate (a raising predicate proves it); a recognized 3xx ALWAYS allocates the snapshot and consults the predicate, even with no usable `Location` — nil, empty, `mailto:`, `ht!tp://bad` each consulted once (`step_test.rb` `PredicateTest`, three `REDIR-21` cases; guards 26, 27) |
| `REDIR-22` | MUST | ✅ | 11, 12 | **(a)** the superseded response is closed BEFORE the follow-up goes out — asserted as the **order**, not the count: the next hop's scripted reply is a callable that reads the prior response's `closes` at the moment the follow-up reaches the transport, and reads 1; three hops close hop 1 and hop 2 exactly once and leave the returned response at 0. **(b)** a downgrade rejection, a non-replayable body and a raising predicate (P6-99) each close the current response before the error propagates, inside one `closing_on_error` frame that rescues `::Exception` (6a's fence shape) and attaches a close failure to the error's suppressed trail rather than masking it. **(c)** every "return current" outcome — non-redirect, missing or malformed `Location`, loop, cap, a refusing predicate — hands the response back open (`step_test.rb` `LifecycleTest`, `DecisionTest`, `LocationTest`, `PredicateTest`; guards 16, 18, 28, 29) |
| `REDIR-23` | SHOULD | ✅ | 12 | `Step#call` is one `loop do … end` over a per-call `Chain`; 5,000 hops complete in seconds and the 5,001st drive sits at the first drive's `caller.size` (`step_test.rb` `LifecycleTest`, "a chain of 5,000 hops"; guard 30, a recursive follower, fails on the depth) |
| `REDIR-24` | MUST | ✅ | 10 | The step declares `Stages::REDIRECT` (order 200), the outermost pillar, so `PIPE-2`'s fixed order nests retry and auth inside every hop; the marker is written on every hop's fork and the AUTH-position probe records once per hop, the seed's own drive included (`step_test.rb` `ConstructionTest`; `MarkerTest`, "the marker is written on EVERY drive") |
| `REDIR-25` | MUST | ✅ | 13a | **No longer vacuous**: `AsyncPipeline.standard` exists and installs `AsyncRetryStep` at RETRY and `Instrumentation::AsyncStep` at LOGGING and **nothing at REDIRECT**; there is no `Redirect::AsyncStep`, no async spelling of `Location.resolve`, and `Stages::REDIRECT` stays installable by hand on the async path exactly as 4c left it (`PIPE-28`; spec-forced boundary 12) (`pipeline/standard_test.rb` `ShapeTest`; guard 45; 4c's `async_pipeline_test.rb` pin flipped on the code branch) |
| `REDIR-26` | MUST | ✅ | 8 | `Step.allowed_methods!` builds a fresh frozen `Set` of `Method`s from whatever collection the caller passes (Strings, Symbols or Methods); a later `<<` or `clear` on the caller's array changes nothing, proven **behaviourally** — the policy still follows a `GET` and still refuses a `POST` after the mutation — since the step exposes no reader (`step_test.rb` `ConstructionTest`, two `REDIR-26` cases; guard 38) |
| `REDIR-27` | MAY | ⏳ | — | The configurable target header, declined for v1: `docs/first-release.md` § What v1 ships without › SHOULD- and MAY-level, the `REDIR-27` entry ("`Location` is the only header v1 reads. Trigger: none named"). No code |
| `REDIR-28` | SHOULD | ✅ | 6, 13 | The private `Redirect::Emitter` emits `HOP_FOLLOWED` (INFO: from, to, the status under 5b's `HTTP_RESPONSE_STATUS_CODE`, the count), `LOOP_DETECTED`, `SCHEME_DOWNGRADE_REJECTED` / `_PERMITTED` and `LOCATION_MALFORMED` (WARNING) through the step's `logger:`, every one inside `Instrumentation.contain` so a raising sink cannot fail the redirect (`OBS-20`); every URL field through the **logger's** redactor — `Logger.build(redactor:)`, no `redactor:` on the step (P6-93) — with a raising redactor degrading the field to `[malformed url]` rather than dropping the record; and the malformed-`Location` record carrying the header value **raw** (`ht!tp://user:pass@bad` verbatim, `ftp://user:pw@h/z` verbatim) with the parser's error as the cause — the requirement's own exception, and the one place the redactor is not called. Across all four events over a chain of userinfo- and query-bearing URLs, no credential reaches any record (`events_test.rb`; `step_test.rb` `EmissionTest`, nine cases; guards 39–42) |

Phase-level rows — the work phase 4c postponed to "whichever of 6a/6b lands second", executed here as
Task 13a, and the convergence point the charter assigned the same way:

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `PIPE-39` | SHOULD | ✅ | 13a | The second convenience constructor, closing phase 4c's ⏳ row (which stays as its record): `Pipeline.standard(over, redirect: nil, settings:, http_tracer_factory:, logger:, level:, preview_bytes:)` installs `Redirect::Step` at REDIRECT, `Resilience::RetryStep` at RETRY and `Instrumentation::Step` at LOGGING, and nothing else, over `Builder#install_preset` — a source scan refuses any `append`/`prepend`/`insert_*`/`replace`/`reload` inside either constructor. `settings:` and `http_tracer_factory:` reach the retry step — **each on its own evidence**, because the default settings retry a 503 too: the retry's one wait is asserted on the `FakeClock` the settings carry, at their zero delay (`[0.0]`, where the default schedule would have slept ~0.2 s on `Clock::SYSTEM` and left that clock empty), `settings(max_retries: 0)` leaves a 503 unretried after one call, and the per-attempt tracer events are recorded; review round 0 found the settings half vacuous on the sync preset (the call count alone could not tell the two schedules apart) and both assertions were added — `logger:` reaches all three (the instrumentation step's request event once per attempt, the redirect step's hop record), `level:` and `preview_bytes:` the instrumentation step (BODY refused without a cap, accepted with one); the sync preset follows a redirect and retries a 503 in one call; a `redirect:` step handed in is installed as given. `AsyncPipeline.standard(over, redirect:, …)` installs `AsyncRetryStep` and `Instrumentation::AsyncStep` — the async one, never the sync `Step` — with the same keywords; a positive backoff with no `Fiber.scheduler` fails the future with `SeamError` (6a's P6-54), stated in the constructor's YARD, and no scheduler keyword exists because the step takes none (P6-100) (`pipeline/standard_test.rb`, thirteen cases; guards 46, 48–51) |
| `PIPE-32` | MUST | ✅ | 13a | `redirect:` on `AsyncPipeline.standard` is a **required** keyword (`ArgumentError: missing keyword: :redirect` without it) admitting `:unsupported` alone — `:follow`, `nil`, `true` and a `Redirect::Step` each refused with an `InvalidArgumentError` naming `PIPE-32` — and the preset installs nothing at REDIRECT; the asymmetry with the sync preset is spelled at the call site, in `AsyncPipeline`'s YARD and in `docs/sdk-documentation/redirect.md` and `pipelines.md` (`pipeline/standard_test.rb` `ShapeTest`; guards 43–45) |
| `PIPE-24` | MUST | ✅ consumed | 13a | Both constructors take a transport **or** a `Pipeline::Builder` as their one positional, so the empty-pillars rule is reachable through them: a builder whose RETRY is occupied rejects the whole preset with a `PipelineError` naming `PIPE-24` and its own entries untouched, on both runtimes, while a builder holding a PRE_REDIRECT step keeps it around the preset's three (`pipeline/standard_test.rb` `InstallationTest`; guard 47, a second installation path, fails on `PIPE-5`'s message where `PIPE-24`'s is expected) |
| Convergence point 1 | — | ✅ | 14 | `test/dexpace/auth/cross_origin_convergence_test.rb`, 6c's Task 15, in two layers: on the **code** branch `Redirect::Step.new` → `.build`, the one-line repair 6b's private constructor forced — and since `defined?(Dexpace::Redirect::Step)` is true the moment the code lands, the guard no longer skips and the test runs, and passes, on the code tip already; on the **tests** branch the now-dead guard line removed and the header rewritten to say who un-guarded it. Before the real step was installed the body was run against a scratch stub REDIRECT step that followed the `Location` but forked **without** the marker and failed on `Expected ["authorization"] to not include "authorization"` — the leak the test exists to catch — and it passes against the real step: a real `KeyStamper` on the real `Auth::Step`, the seed hop stamped, no `Authorization` reaching `https://evil.example.net/collect`. The one skip every `test:gems` run on `main` carried is gone (guards 1, 4, 10 and 11 each run it red) |

Cross-reference rows, the IDs this phase owns a share of:

| ID | Status | What 6b supplies, and where it is proven |
|---|---|---|
| `BODY-1` (`#replayable?`) | ✅ call site | `Resend.replayable_body?` calls phase 3b's predicate directly; `Body.bytes` answers yes and `Body.stream(…, close: true)` no through it, and the same object is re-sent (the `REDIR-4`, `REDIR-6` rows) |
| `PIPE-15`, `PIPE-16`, `PIPE-40` (P4-39) | ✅ | The step forks for EVERY drive, the first included, and never calls the handed cursor — a `SpyCursor` wrapper counts three forks and zero calls across three hops, one fork and zero calls on a plain 200 — re-sends through a fresh fork, closes each superseded intermediate before the next drive and never the one it hands back (`step_test.rb` `ForkingTest`, `LifecycleTest`) |
| `PIPE-11` | ✅ | Per-call state — the seed triple and method, the visited set, the count, the current request — is a private `Chain` allocated per `#call`, never an ivar on the frozen step |
| `HTTP-13` | ✅ | `Origin.of`'s scheme and host folds and `Reissue.rebuild_as_get`'s `Content-*` prefix test are the no-argument `downcase`, which the `Dexpace/NoLocaleCaseFold` cop makes a rule |
| `HTTP-3`, `HTTP-4`, `SEAM-29` | ✅ | `ConditionSnapshot` follows the construction pattern without exception: `.new` private, keyword `.build`, `Model.required!`'s one message form, the collection through `Model.own`, `#with` through `.build` (`condition_snapshot_test.rb`) |
| `HTTP-46`, `HTTP-47` | ✅ consumed | The seed and every current-hop URL are phase 1's absolute URIs; the `Location` is never handed to `URL.parse!`, which rejects the relative reference `REDIR-14` requires (`R7`); the follow-up goes through `Request#with`, so `URL.parse!` re-validates the resolved target at the model boundary |
| `RETRY-5`, `AUTH-31` | ✅ sibling predicates | 6a's `Resend.eligible?` (retry's, with `RETRY-7`) and 6c's private `Auth::Step#replayable?` are untouched; 6b's `.replayable_body?` is the third spelling, and the consolidation question is phase 10's (Findings routed) |
| `XCUT-19`, `OBS-13` | ✅ through 5b | Every URL a record carries goes through 5b's `Redactor#url` on the logger — userinfo `***:***@`, a non-allow-listed query value `***` — and no credential reaches any of the four events; the one raw field is the requirement's own exception (the `REDIR-28` row) |
| `OBS-20`, `XCUT-20` | ✅ | Every emission runs inside `Instrumentation.contain`; a sink raising on `info` does not fail the redirect (`step_test.rb` `EmissionTest`; guard 40) |
| `OBS-39` | ✅ | Five event names and four keys under one `http.redirect.` prefix, frozen, distinct, each a manifest row; 5b's `Events` pin (nine) is untouched — the redirect vocabulary is its own module, the design's `R8`, not 6c's precedent of widening 5b's (`events_test.rb`) |
| `PIPE-28` | ✅ | `Stages::REDIRECT` stays installable on the async path by hand; the preset, not the runtime, is what `PIPE-32` constrains (4c's `async_pipeline_test.rb`, the pin flipped from `refute_respond_to` to `assert_respond_to`) |
| `SEAM-1` | ✅ | No new require: `uri` is named by `location.rb` and `step.rb` and was allowlisted before phase 1; `Set` needs no require on any row and `Lint/RedundantRequireStatement` refuses one |
| `NFR-4` | ✅ | Every addition is a widening: no existing signature moved. The manifest grew by exactly 28 rows, 1 109 → 1 137, read row by row against the object model (P6-92); the RBS baseline diff is vacuous until the first tag |
| `NFR-11` | ✅ | No constant outside `Dexpace::` and the stdlib allowlist in any public signature; `URI::Generic` is on it |
| `NFR-13` | ✅ for `.rb`; the `.rbs` half is phase 10's | The nineteen new `.rb` files — ten under `lib/`, nine under `test/` (seven suites and two doubles; round 0 corrected the count from ten) — open with the two headers the `Dexpace/SpdxHeader` cop gates; the ten new `.rbs` files carry no SPDX line, as no `.rbs` in the repository does (phase 10's `gates:spdx_rbs`), as 6a's row records |

## What was built

Ten new `lib/` files: the flat `lib/dexpace/error/not_replayable_error.rb` (6a's P6-56 precedent for
the same namespace; P6-94) and nine under `lib/dexpace/redirect/` — `origin.rb` (private),
`location.rb` (private), `condition_snapshot.rb`, `events.rb` (`Events` and `Keys`, 5b's one-file
precedent), `scheme_downgrade_error.rb` (6c's precedent for a namespaced error under its own
directory), `chain.rb` (private), `emitter.rb` (private, 5b's `Emitter` shape), `reissue.rb` (private)
and `step.rb`, which also carries the `Dexpace::Redirect` module's YARD. No `lib/dexpace/redirect.rb`:
an empty namespace file has no precedent (recovery.rb, io.rb and proxy.rb all carry content;
`Instrumentation` and `Async` are defined by their nested files) and would cost a `sig/` and a `test/`
mirror for nothing. Three earlier files widened in place, each a designed widening: 6a's
`resilience/resend.rb` gains `.replayable_body?` beside `.eligible?` in the same `extend self` spelling
(the plan's "EXISTS" branch); 4c's `pipeline.rb` gains `.standard` and a private `.standard_redirect`,
and `async_pipeline.rb` gains `.standard`, both over `Builder#install_preset`, with 4c's three
"postponed to phase 6b" YARD sites (`pipeline.rb`, `builder.rb`, `async_pipeline.rb`) rewritten and
the `PIPE-32` paragraph on `AsyncPipeline` now stating the asymmetry as built; and `lib/dexpace.rb`
gains a ten-line `# Phase 6b:` block after 6c's, in dependency order. Every new file has a `sig/`
mirror — the five private ones with `hooks.rbs`'s comment, because the strict `core` Steep target
types every call site — and every public one a `test/` mirror; three suites carry no `lib/` mirror and
say so in their headers: `redirect/matrix_facts_test.rb` (Task 1's facts as a standing test, 5a's,
5b's, 5c's, 6a's and 6c's precedent), `pipeline/standard_test.rb` (the two constructors' own suite
over both files) and 6c's `auth/cross_origin_convergence_test.rb` (un-guarded). Two new top-level
test-support doubles, one class per file: `RedirectFixtures` (the requests, close-counting responses
and pipelines every redirect suite uses, over `FakeResponseBody` and 6a's `ScriptedTransport`) and
`CredentialProbe` (the AUTH-position probe that records, per drive, the URL, whether the request still
carried `Authorization` when it arrived and whether the REDIRECT slot said cross-origin, and stamps its
own token unless suppressed — 6b's half of convergence point 1, observed from where 6c's real step
reads it). No third scripted transport: 6a's `ScriptedTransport` was reused as it is, its callable
entry (called with request, options and cancellation) being exactly how `REDIR-22a`'s ORDER is
observed; 6c's `SequencedTransport` is what the un-guarded convergence test uses, and the pair's
reconciliation stays the manager's chore, cited below. Five existing tests changed: on the **code**
branch, as pins the code invalidated — the smoke suite's layer table (`REDIRECT_LAYER = %i[Redirect
NotReplayableError]`), 4c's `async_pipeline_test.rb` (`refute_respond_to` → `assert_respond_to` on
both `.standard`s) and 6c's `cross_origin_convergence_test.rb`'s constructor line (`.new` → `.build`,
which 6b's private constructor forced; its `defined?` guard stops skipping the moment the code lands,
so the test runs and passes on the code tip); on the **tests** branch — 6a's `resend_test.rb` (a nested
`ReplayableBodyTest` class, five cases), 6c's `cross_origin_convergence_test.rb` again (the dead guard
line removed, the header rewritten) and 6b's own `step_test.rb` (the `REDIR-8` (ii) Cookie assertion,
added after guard 3 stayed green). The surface manifest was regenerated once, 1 109 → 1 137, and all 28 rows read against
the object model: `AsyncPipeline.standard`, `NotReplayableError`, `Pipeline.standard`, `Redirect`,
`ConditionSnapshot` with its three readers and `.build`, `Events` (five), `Keys` (four),
`SchemeDowngradeError`, `Step` with `#call`, `#stage`, `.build`, `DEFAULT_ALLOWED_METHODS : Set` and
`DEFAULT_MAX_HOPS : Integer`, and `Resend#replayable_body?` (a `#` row because `extend self` is what
the cop set prescribes); nothing private, no `RECOGNIZED_CODES`, no configuration reader on the step.

## Matrix facts, re-run on every interpreter

The design's four facts and the ones the build found were run on 2026-09-19 on **3.2.11, 3.3.12, 3.4.10
and 4.0.6**, first as a scratch script per interpreter and then as `redirect/matrix_facts_test.rb`, a
standing test on every CI row (twelve cases, 58 assertions). Every fact holds identically on every row.
`userinfo = ""` clears user and password and `userinfo = nil` is a no-op (`user = nil` clears too; a
frozen URI raises `FrozenError` on the strip); `join` resolves a relative, a query-only, a
fragment-carrying and a network-path reference against the base and takes an absolute one as-is,
preserves `%2F`, `%2B`, a bracketed IPv6 host and `:8443` byte for byte, lowercases an upper-case
scheme and does not fold the host; `join(base, "")` answers the base and `join(base, nil)` raises
`ArgumentError`; `join` raises `URI::InvalidURIError` on `ht!tp://user:pass@bad`, a space, `<`, a
non-ASCII byte, `:notaport` and a tab, and raises on **nothing else** — `mailto:a@b` is a `URI::MailTo`
with a nil host whose `userinfo=` raises "cannot set user with opaque", `ftp://o/z` a `URI::FTP`,
`javascript:` and `data:` a `URI::Generic`, and `http:foo`, `http:///p` and `https://` an `http(s)`
URI with a nil or empty host — which is why `Location.resolve` screens both the scheme and the host
(P6-95). `URI#to_s` elides an explicit `:443` on every row (P5-91; P6-96). `Set` is insertion-ordered,
a frozen one raises, and `Set` needs no require. **The design's Set-of-URI rationale is false on every
row**: two parses of one string are `==`, `eql?`, hash alike and `Set[a].include?(b)` is true. **The
plan's malformed fixture `https://user:pass@ht!tp://bad` is a VALID URI** (host `ht!tp`, `!` a
sub-delim in reg-name) and would have been followed; the suite uses `ht!tp://user:pass@bad`. The one
thing that differs across the matrix is `URI::InvalidURIError`'s message — a uri-**gem** difference,
not an interpreter one: 3.3.12's default uri 0.13.3 prints `bad URI(is not URI?)` and "can not set user
with opaque", 3.4.10's 1.0.4 and the 1.1.1 on 3.2.11 and 4.0.6 print `bad URI (is not URI?)` and
"cannot set user with opaque" — and the bundle pins 1.1.1 on every row while `gates:clean_bundle` on the
3.3 row loads the default gem; nothing in this phase matches the message, and the note's floor caveat is
closed below.

## Guards run red

Every guard the brief asks to be seen red was seen red, on 4.0.6 and on 3.2.11, and the bytes restored
after each: fifty single-edit mutations of `lib/`, one at a time through a harness that applies the
edit, runs the owning suites under `ruby -w`, captures the first failure and restores the file. On the
first 4.0.6 pass forty-seven were caught; two crashed the suite on an unused-variable warning
(`FatalWarnings`) rather than an assertion and were re-spelled to keep the variable live (25, 46), which
is the guard firing under `NFR-6`'s rule; and **one stayed green because the suite had a gap, which was
closed** — the `REDIR-8` (ii) chain asserted `Authorization` and the marker but not the `Cookie`, so a
strip decision compared against the previous hop passed it; the case now asserts the `Cookie` off the
wire on hop 2 (guard 3 below). On the second pass **forty-nine of fifty are caught on 4.0.6 and
forty-nine of fifty on 3.2.11**, and the one that stays green on both is an **equivalent mutant**,
recorded with its reason rather than hidden. **Review round 0 (2026-09-19) ran forty-four of its own and
found two more surviving on both rows** — guard 48 had been run as one edit dropping `settings:` and
`http_tracer_factory:` together, and only the tracer half was firing; and no test drove a cross-origin
303 carrying `Cookie` or `Proxy-Authorization` — so the battery is **fifty-two, fifty-one caught on
4.0.6 and fifty-one on 3.2.11**, guard 3 the one equivalent mutant: guard 48 is now the tracer half
alone, and guards 51 and 52 are the round's two, each red on both rows after the tests-branch fix.

| # | Fix reverted | Guard | What it said (4.0.6; identical on 3.2.11 unless stated) |
|---|---|---|---|
| 1 | `REDIR-7`: `Authorization` not stripped on the re-issue | `CredentialHygieneTest`, `ReissueTest`, the convergence test | `Expected #<data Dexpace::Headers values={"authorization" => ["Bearer t"]} …> to not include "Authorization"` (5 failures) |
| 2 | `REDIR-7`: `Authorization` stripped on a cross-origin hop only | `CredentialHygieneTest` | the same `to not include "Authorization"` on the same-origin re-issue (3 failures) |
| 3 | `REDIR-8`: the STRIP decision compared against the previous hop (`Origin.of(chain.request.url)`) | — | **STAYED GREEN on both rows, and is equivalent**: the strip is cumulative — once a hop is cross-origin the `Cookie` and `Proxy-Authorization` are gone from the follow-up and never return, and a hop whose previous hop differs from the seed is exactly a hop after such a strip — so the seed-versus-previous distinction is observable only through the marker, which guard 4 catches; the suite gained the `Cookie` assertion on the A → B → B chain anyway, which pins the seed comparison against a re-adding implementation |
| 4 | `REDIR-8`: the MARKER compared against the previous hop | `MarkerTest`, `CredentialHygieneTest`, the convergence test | 41 errors and a failure — the previous-hop lookup breaks the seed's own drive; the convergence test fails on the leak |
| 5 | `REDIR-8`: the host compared case-sensitively | `CredentialHygieneTest` | `Expected: [false, false, false, false]` — `A.EXAMPLE` read as cross-origin |
| 6 | `REDIR-8`: the effective port dropped from the triple | `CredentialHygieneTest` | `Expected: [false, true, false, false]` — `:8080` read as same-origin |
| 7 | `REDIR-10`: `Cookie` stripped same-origin | `CredentialHygieneTest` | `Expected … to include "Cookie"` on the same-origin hop |
| 8 | `REDIR-9`: `Cookie` retained cross-origin | `CredentialHygieneTest` | `Expected … to not include "Cookie"` on the cross-origin hop (2 failures; 3 on 3.2.11, the (ii) chain's Cookie pin among them) |
| 9 | `REDIR-11`: the marker omitted on a same-origin hop | `MarkerTest` | `--- expected [{cross_origin: false}, …] +++ actual [{}, …]` (3 failures) |
| 10 | `REDIR-11`: no marker at all | `MarkerTest`, `CredentialHygieneTest`, the convergence test | 7 failures; the convergence test on `Expected ["authorization"] to not include "authorization"` |
| 11 | `REDIR-11`: the marker as an `X-Dexpace-Cross-Origin` request header | `MarkerTest`, the convergence test | `Expected: [false, true, false, false]` — the header is read by nothing (7 failures) |
| 12 | `REDIR-12`: `userinfo = nil` (the no-op) | `LocationTest`, `EmissionTest` | `--- expected "https://h/a%2Fb?x=%26y%2Bz" +++ actual "https://user:pass@h/a%2Fb?…"` (3 failures, 1 error) |
| 13 | `REDIR-13`: the `Location` decoded before resolution | `LocationTest` | `--- expected "https://h/a%2Fb?x=%26y%2Bz" +++ actual "https://h/a/b?x=&y+z"` (2 failures) |
| 14 | `REDIR-14`: a relative `Location` resolved against the seed | `LocationTest` | `--- expected [… "https://h/v2/a/c" …] +++ actual [… "https://h/c" …]` |
| 15 | `REDIR-15`: the downgrade followed by default | `LocationTest`, `EmissionTest` | `[Dexpace::Redirect::SchemeDowngradeError] exception expected, not …` (4 failures) |
| 16 | `REDIR-22b`: the closing frame dropped | `LocationTest`, `ReissueTest`, `PredicateTest`, `LifecycleTest` | `Expected: 1 Actual: 0` on `closes` (5 failures) |
| 17 | `REDIR-15`: `allow_scheme_downgrade: true` refused | `LocationTest`, `EmissionTest` | 4 failures, 3 errors — the opt-in raises |
| 18 | `REDIR-16`/`REDIR-22c`: a "return current" outcome closed | `DecisionTest`, `LocationTest`, `PredicateTest` | `Expected: 0 Actual: 1` on `closes` (5 failures) |
| 19 | `REDIR-16`: no loop detection | `DecisionTest`, `EmissionTest` | `ScriptedTransport: script exhausted` — the loop ran on (4 errors) |
| 20 | `REDIR-17`: the cap applied BEFORE the predicate | `PredicateTest` | `Expected: [0, 1] Actual: [0]` — the predicate not consulted at the capped hop |
| 21 | `REDIR-17`: the cap off by one (`>`) | `DecisionTest` | `Expected: 3 Actual: 4` transport calls (3.2.11 reports the count; 4.0.6's first line is the exhausted-script error) |
| 22 | `REDIR-18`: a malformed `Location` raises | `LocationTest`, `PredicateTest`, `EmissionTest` | `URI::InvalidURIError` out of the pipeline (7 errors) |
| 23 | `REDIR-18`: the scheme-and-host screen dropped | `LocationTest`, `EmissionTest` | `NoMethodError: undefined method 'downcase' for nil` out of `Origin.of` on `mailto:` (3 errors) |
| 24 | `REDIR-19`: the missing-`Location` guard dropped | `DecisionTest`, `PredicateTest` | `ArgumentError` out of `join(base, nil)` (3 errors) |
| 25 | `REDIR-20`: the snapshot aliases the caller's set | `condition_snapshot_test.rb` | `Expected Set["https://a.example/x"] (oid=…) to not be the same as Set[…] (oid=…)` (2 failures) |
| 26 | `REDIR-21`: the predicate skipped when the target is nil | `PredicateTest` | `Expected: [0, 0, 0, 0] Actual: []` |
| 27 | `REDIR-21`/`REDIR-1`: the fast path dropped | `DecisionTest`, `PredicateTest` | `RuntimeError: must not be called` — the predicate consulted on a 404 (2 errors) |
| 28 | `REDIR-22a`: the close deferred to the next iteration | `LifecycleTest` and 41 others | the deferred close reads 0 as the follow-up arrives; the step's ivar write breaks the frozen step (41 errors) |
| 29 | `REDIR-22a`: the superseded response never closed | `LifecycleTest` | `Expected: 1 Actual: 0` on hop 1's `closes` (2 failures) |
| 30 | `REDIR-23`: a recursive follower | `LifecycleTest` | `Expected: 28 Actual: 10028` — the 5,001st drive's `caller.size` |
| 31 | `REDIR-3`: `Method::IDEMPOTENT` as the default set | `ConstructionTest` | `Expected: 301` — `PUT`, `OPTIONS` and `DELETE` followed (1 failure, 1 error) |
| 32 | `REDIR-3`: the CURRENT hop's method judged, not the seed's | `ReissueTest` | `Expected: 301 Actual: 200` — the `POST` → 303 → `GET` → 301 chain followed on |
| 33 | `REDIR-5`: the `Content-*` headers kept on the 303 rebuild | `ReissueTest` | `Expected … to not include "Content-Type"` |
| 34 | `REDIR-5`: the 303 body and method kept | `ReissueTest` | `NoMethodError` — the rebuild reaches a helper that does not exist (3 errors) |
| 35 | `REDIR-5`: a 303 followed under the method set, ignoring `follow303` | `ReissueTest` | `Expected: 200 Actual: 303` and the default followed a 303 (2 failures, 1 error) |
| 36 | `REDIR-6`: `Resend.eligible?` called | `ReissueTest` | `Dexpace::NotReplayableError` on the body-less `POST` 307 the allowed set admits |
| 37 | `REDIR-6`: `replayable_body?` asking about the method | `resend_test.rb` | `Expected false to be truthy` on the bare `POST` (3 failures; the source scan among them on 3.2.11) |
| 38 | `REDIR-26`: the caller's collection aliased | `ConstructionTest`, `ReissueTest` | `Expected: 200 Actual: 301` after the caller's `clear` (4 failures, 1 error; on 3.2.11 the first line is `NotReplayableError expected but nothing was raised`) |
| 39 | `REDIR-28`: the redactor called on the malformed `Location` | `EmissionTest` | `Expected: "ftp://user:pw@h/z" Actual: "ftp://***:***@h/z"` (2 failures) |
| 40 | `OBS-20`: the containment dropped | `EmissionTest` | `RuntimeError: sink boom` out of the pipeline |
| 41 | `REDIR-28`: the hop URLs logged raw | `EmissionTest` | `--- expected "https://seed.example/x?sig=***" +++ actual "…?sig=SEED"` (3 failures) |
| 42 | `REDIR-28`: the emitter's redactor rescue dropped | `EmissionTest` | `RuntimeError: boom` — the record dropped with the redirect |
| 43 | `PIPE-32`: `redirect: nil` accepted | `standard_test.rb` | `Dexpace::InvalidArgumentError expected but nothing was raised` |
| 44 | `PIPE-32`: `redirect:` defaulted instead of required | `standard_test.rb` | `ArgumentError expected but nothing was raised` |
| 45 | `REDIR-25`: a redirect step on the async preset | `standard_test.rb` | `Expected: [:retry, :logging] Actual: [:redirect, :retry, :logging]` |
| 46 | `PIPE-39`: a preset installing nothing | `standard_test.rb` | `Expected: [:redirect, :retry, :logging] Actual: []` (7 failures, 1 error) |
| 47 | `PIPE-24`: a second installation path (`append`) | `standard_test.rb` | `Expected "pillar retry is already occupied … (PIPE-5)" to include "PIPE-24"` — the wrong gate fires and the builder is half-installed |
| 48 | `PIPE-39`: `http_tracer_factory:` not reaching `RetryStep` (first run with `settings:` dropped in the same edit; the tracer assertion is what fired) | `standard_test.rb` | `--- expected [:attempt_started, :attempt_failed, :attempt_started] +++ actual []` |
| 49 | `PIPE-39`: the sync `Instrumentation::Step` on the async preset | `standard_test.rb` | `Expected #<Dexpace::Instrumentation::Step …> to be an instance of Dexpace::Instrumentation::AsyncStep` |
| 50 | `PIPE-39`: `logger:` not reaching the instrumentation step | `standard_test.rb` | `Expected: 2 Actual: 0` request events |
| 51 | `PIPE-39`: `settings:` alone not reaching the sync `RetryStep` (both branches of the two-branch build) — round 0's first survivor | `standard_test.rb` `WiringTest` | `Expected: [0.0] Actual: []` on the settings' clock, and `ScriptedTransport: script exhausted after 1 calls` where `max_retries: 0` should have returned the 503 (1 failure, 1 error) |
| 52 | `REDIR-9`: `Cookie`/`Proxy-Authorization` kept on a CROSS-ORIGIN 303 rebuild (`strip(cross_origin: false)` for 303 alone) — round 0's second survivor | `ReissueTest` | `Expected #<data Dexpace::Headers values={"accept" => …, "cookie" => ["sid=1"], "proxy-authorization" => …}> to not include "Cookie"` |

Two guards the brief names have no mutation because nothing to mutate exists: no `Regexp` is compiled
anywhere in this phase (the scheme screen is an `Array#include?` over two literals, the `Content-*`
test a `start_with?`), so "a Regexp built without `timeout:`" cannot arise; and the convergence test's
red-for-the-right-reason run is the scratch-stub run recorded in its row, which guards 1, 4, 10 and 11
reproduce through the real step.

## Audit groups run

The phase-start pair first, at implementation: `--origin note --brief` returned 55 note entries across
22 files (6c's two new notes and 6a's among them); `--section conflicts --brief` returned 19 entries
with every harvested conflict `[overridden by notes/…]` and none open. The eleventh audit group's
`REDIR` slice, `--prefix REDIR --section rules --brief`, returned 32 entries across two topic files,
**zero tagged `[appendix-B roll-up]`**, covering 27 of the 28 (`REDIR-25` filed under Reference, read
with `--req`); chapter 10 was read in full, its `*Conformance:*` clauses included, and appendix C's
rows for `PIPE-24`, `PIPE-32` and `PIPE-39` verbatim. `--req` was run per task. The three note entries
the charter binds were read in full and are what three decisions rest on: `pipeline/86343352` (the
step forks for every drive, the first included — `ForkingTest`, and guard 10 is what a first drive on
the un-forked handle would lose), `url-and-query-encoding/08c54234` (`URI::RFC3986_PARSER.join` is the
spelling; the message is never matched) and `redirect-handling/b42d265d` — 6b's own note, filed with
the design, whose "floor-straddling and not yet closed" caveat Task 1 closes (Findings routed).
`pipeline/7ce4431d` applied nowhere: the one re-raise in the phase, `closing_on_error`'s, is a bare
`raise` of the error just rescued, never a carried one.

| Group | Result at implementation |
|---|---|
| Public API surface | `module-organization/1828a984` (one public constant per file) holds for every new file — `events.rb` carries `Events` and `Keys` on 5b's `keys.rb` precedent; `api-design/b0e18938` is why the step exposes no configuration reader (none of 5b's, 6a's or 6c's steps does), why `RECOGNIZED_CODES` is private and why the five helpers are `private_constant`s; every public name is in the design's object model or in P6-92/P6-100 |
| RBS / Steep typing | Ten new mirrors and three widened (`resend.rbs`, `pipeline.rbs`, `async_pipeline.rbs`), the strict target green with no relaxation; the predicate is `untyped` because a lambda is a valid value (`Registry.callable?` validates the arity), `AsyncPipeline.standard`'s `redirect:` is the literal type `:unsupported` so a consumer's own `steep check` catches a wrong symbol at the call site, every `URI::RFC3986_PARSER` site writes `#: untyped` as `url.rb` does, and one `#: untyped` on the async constructor's local keeps the refusal message's `#inspect` typeable past the literal's narrowing |
| Minitest conventions | Every suite subclasses `DexpaceTestCase`; the step suite is split into ten nested classes under `Metrics/ClassLength` (6c's shape) and the constructors' suite into two; a helper named `follow` rather than `run`; `assert_same` wherever identity is the claim (the returned response IS the current one, the re-sent body IS the caller's); no `Hash#inspect` asserted; every `URI::InvalidURIError` asserted by class |
| Fiber scheduler, thread safety | The step is frozen and holds no per-request state; the one mutable object per call is the private `Chain`, on the stack; no `Thread::Mutex` in the phase, no thread started, no wait; the async preset installs 6a's trampoline, which the phase does not touch |
| Resilience: retry, redirect and authentication | Every `REDIR` rule in the group restates a clause implemented above; `redirect-handling/d4885fbc`'s `URI.join`/`URI#merge` spelling prints `[overridden by notes/url-and-query-encoding.md:8]` and the build wrote `URI::RFC3986_PARSER.join`; the `RETRY`/`AUTH` rules that name `AUTH-31` and `AUTH-29` are 6a's and 6c's, and 6b neither consumes nor duplicates them beyond the marker's writer half |

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate. Items
1–16 are where the built tree overrode the plan's assumptions, in the order the brief's as-built list
gives them; 17–30 are this build's. The ones that touch public behaviour, the contract a later phase
cites, or a statement the design makes are also the as-built ledger rows P6-91–P6-100.

1. **The base is `main` at `e61864f`**, holding 6a and 6c; nothing here describes either as anything
   but landed. Task 2 ran its "EXISTS" branch: `.replayable_body?` added beside `.eligible?` in the same
   `extend self` spelling, the `sig/` mirror grown by one `def self?.` line, 6a's `resend_test.rb`
   extended with a nested class rather than the plan's second file.
2. **`NotReplayableError` is flat under `Dexpace::`**, in `error/not_replayable_error.rb`, on 6a's P6-56
   precedent for the same namespace, not `Dexpace::Resilience::NotReplayableError` and never inside
   `resend.rb` (P6-94). 6c's `AUTH-31` gate is its private `Step#replayable?`; the three spellings are
   phase 10's (Findings routed).
3. **Task 13a executed here, with 6a's and 5b's spellings as landed**: `RetryStep.build(settings:,
   http_tracer_factory:, logger:)` and `AsyncRetryStep.build(…)`, `Instrumentation::Step.build(logger:,
   level:, preview_bytes:)` with its two required keywords — the plan's bare `Step.build` raises — and
   `Instrumentation::AsyncStep.build` on the async preset, never the sync `Step` (guard 49); the retry
   keyword is `settings:`, never `retry:` (a bare `retry` in a method body is `SyntaxError: Invalid
   retry`); a nil `http_tracer_factory:` leaves 6a's private default in place through a two-branch
   build rather than a keyword splat the `NoKeywordSplat` cop refuses or a copied constant. 4c's
   `async_pipeline_test.rb` pins flipped on the code branch; the three "postponed" YARD sites
   rewritten; `.standard` added to both `.rbs`; `pipelines.md`'s two "does not exist yet" passages
   repaired.
4. **The convergence test is un-guarded in two layers** — `Step.new` → `Step.build` on the code
   branch, because the private constructor invalidated the existing test the moment its `defined?`
   guard turned true (the layering rule: a code-invalidated test's repair rides the code branch, so that
   tip is green); the dead guard line and the header on the tests branch — after the scratch-stub run
   recorded in its row. The plan's Task 14 Step 2 ("owned by 6c … NOT duplicated here") was stale on
   ownership; the charter's rule made it 6b's.
5. **The `Cursor` context-bundle widening was consumed not at all**: the step's `logger:` is its own,
   and `Cursor#bundle` is read by nothing in `redirect/`.
6. **The doubles as built were reused**: 6a's `ScriptedTransport` (its callable entry is the
   `REDIR-22a` ordering probe; no `log:` extension was needed), `FakeResponseBody` (`#closes`),
   `FakeBody`, `RecordingSink`, `FakeAsyncTransport`, `ScriptedAsyncTransport`, `FakeClock`,
   `RecordingHTTPTracer`, `ForkingProbe`, `StateProbe` and `SpyCursor`; the two new ones are top level,
   one class per file, in no namespace; no third scripted transport.
7. **5b as built**: `Logger.build(sink:, redactor:)`, `logger.event(severity).event(name).field(k, v)
   .cause(e).emit`, every emission inside `Instrumentation.contain` (the plan's four chains were bare;
   guard 40), `Logger#redactor` public and read by the emitter; the step takes no `redactor:` (P6-93);
   the "raising redactor" case is `Logger.build(sink:, redactor: raising)`. The redirect vocabulary is
   `Redirect::Events`/`Redirect::Keys` per the design's `R8`, not a widening of 5b's `Events` (6c's
   precedent for one diagnostic): five names and four keys are a subsystem's catalogue, 5b's nine-event
   pin stays untouched, and `Redirect::Keys::STATUS_CODE` is not shipped — the hop record's status is
   5b's `HTTP_RESPONSE_STATUS_CODE` (P6-98).
8. **Phase 1 as built**: `Headers#[]` returns the list (`.first` for a single read), `#include?` folds,
   `Request::Builder#header` appends so the strip is a `Headers::Builder#remove` and the re-issue goes
   through `Request#with(url:, headers:)` (and `with(method:, body: nil)` for the 303 rebuild),
   `Method::IDEMPOTENT` is an Array of Strings, `Model.required!` takes a String name, every
   `URI::RFC3986_PARSER` site writes `#: untyped`, `ConditionSnapshot` follows the construction pattern
   without exception, and the step is `.build` with `.new` private, frozen (P6-93);
   `Dexpace.close_quietly` takes the whole response.
9. **The Location facts, re-run on every row** (Matrix facts): the plan's malformed fixture is valid and
   was replaced; the design's Set-of-URI rationale is false and no YARD repeats it; the default-port
   residue is stated in the `REDIR-13` row and ledger row P6-96, not asserted away.
10. **The plan's broken fences were fixed in transcription**: Task 10's two `REDIR-8` tests became the
    two chains the design names, (i) A → A → B and (ii) A → B → B, with `install_with_probe` replaced by
    the fixtures' `follow(…, downstream:)`; Task 9's `REDIR-16` test asserts `closes` off a body every
    response carries; Task 13a's `response_with(status:, headers:)` became the fixtures' keyword shape;
    Task 12's "200 hops" title says 5,000; `private_constant` is declared in each defining file after its
    body, never in a namespace file. **The design's contradiction is settled**: the cap is applied over
    the predicate's answer (`R9`), and the ledger's "before" paragraph is corrected in the As-built
    addendum (P6-91).
11. **Files and mirrors**: `scheme_downgrade_error.rb` not `errors.rb`; `events.rb` holds `Events` and
    `Keys`; no empty `redirect.rb`; every new `lib/` file has a `sig/` mirror (`test/gates/
    gem_layout_test.rb` gates it one for one, private constants included — the plan's "no sig/ mirror
    for Origin/Location" would fail `test:gates`); `origin.rb`, `location.rb`, `chain.rb`, `emitter.rb`
    and `reissue.rb` join `CLAUDE.md`'s private-constant test-mirror exception list; the `# Phase 6b:`
    block sits after 6c's; the smoke suite's layer table gains `REDIRECT_LAYER`; the manifest
    regenerated once with `surface:regenerate`.
12. **RuboCop's answers**: `extend self` on `Origin`, `Location` and `Reissue`; `=> error`; every method
    under the length and complexity caps by splitting the step's re-issue rules into `Reissue`, its
    records into `Emitter` and its per-call locals into `Chain` (5b's `Emitter` precedent; the plan's
    seven-positional `drive` and five-positional `build_follow_up` never existed); the four-positional
    cap kept with keywords; `Metrics/ClassLength` recorded inline with its reason on `Step` alone (104
    lines: the six keywords' validation and the follower, its three concerns already split out — the
    recorded exception `.rubocop.yml` prescribes, 6a's and 6c's shape); the step suite split into ten
    nested classes and the constructors' into two; no `.freeze` on a plain literal; no `Regexp` in the
    phase; `Lint/RescueException` disabled inline on `closing_on_error` with 6a's reason.
13. **`docs/first-release.md`'s two entries were verified present and cited**: the `REDIR-27` ⏳ entry
    is cited and not rewritten; the `PIPE-32`/`REDIR-25` behavioural-asymmetries entry (lines 415–426)
    was future-tense about the constructors and now says they were built by Task 13a on 2026-09-19 in
    exactly that shape, and names `redirect.md` beside the two places it already named.
14. **Ledger numbering**: the design's one unnumbered candidate is P6-91; the as-built rows run to
    P6-100; every citation of a 6a or 6c row reads "6a's P6-n" / "6c's P6-n".
15. **All four interpreters were installed** and the facts run on each; nothing was installed.
16. **`CLAUDE.md`'s counts are re-derived from the tree on top of `main`**: 184 `lib/dexpace/` files
    beside `version.rb`, eighteen `private_constant` test-mirror exceptions, fourteen checklists, the
    whole of phase 6 built; the lib-file count was counted by hand because the probe does not read it.
17. **`Location.resolve` screens the host as well as the scheme, and strips and freezes** (P6-95).
18. **`Origin.of` is total over an opaque seed** (`to_s` on the scheme and host): a request over a
    hostless URI compares as cross-origin with everything, the direction that strips.
19. **The predicate is consulted BEFORE the target's nil-ness returns the response**, so `REDIR-21`'s
    "even with no usable Location" holds; the target is resolved first, so the malformed record is
    emitted before the predicate runs. The plan's own skeleton returned on a nil target before the
    predicate call and would have failed its own `REDIR-21` test.
20. **A raising predicate closes the current response** (P6-99); the closing frame rescues `::Exception`
    (6a's `fenced` shape, `Lint/RescueException` disabled inline with the reason) so the fatal family
    finds the response closed too.
21. **`REDIR-15`'s refusal is emitted before it is raised** (P6-97).
22. **`SchemeDowngradeError.new(from:, to:)` takes the two URIs as keywords** (6c's `HTTPSRequiredError`
    shape) and its message names the authorities — scheme, host, and the port when it is not the
    scheme's default — never a path or a query, and it exposes no readers.
23. **`NotReplayableError.new(context)`'s message** is `"<context> cannot be re-sent: the request body
    is present and not replayable (REDIR-6)"`.
24. **The step validates strictly**: `follow303:` and `allow_scheme_downgrade:` must be `true` or `false`,
    `max_hops:` a non-negative Integer, `predicate:` nil or callable at arity 1, `logger:` an
    `Instrumentation::Logger` (6a's check), `allowed_methods:` any collection `Method.of` accepts.
25. **The step exposes no configuration reader**: the plan's five `attr_reader`s and its
    `instance_variable_get` assertions are not built, on `api-design/b0e18938` and the three sibling
    steps' precedent; `REDIR-26` is proven behaviourally.
26. **`Chain#advance!` records the follow-up's URL**, not the resolved target's — the same external form
    (`URL.parse!` re-parses the target's text), and the visited set then holds exactly the URLs that
    were sent.
27. **The two `standard` constructors' shape** (P6-100): one positional, a transport or a builder; no
    `builder:`, `retry:` or `instrumentation:` keyword; `preview_bytes:` threaded because `level: BODY`
    requires it; `pipeline.rb` and `async_pipeline.rb` gain the `require_relative`s for the step
    families they name, and the file loads standalone and through the entry file.
28. **`REDIR-8` (ii) gained a `Cookie` assertion** after guard 3 stayed green (Guards run red).
29. **`Chain#advance!`'s YARD** was added after the wip tree's YARD gate reported it — the one
    undocumented method in the first full run.
30. **`Reissue.build` takes the opt-in flag and the emitter as keywords**, not the step, so the step
    exposes nothing for a private module's sake.
31. **Review round 0's two tests-branch additions** (2026-09-19): the sync wiring case in
    `pipeline/standard_test.rb` holds its `FakeClock` and asserts the retry's one wait on it, and a
    second case drives `settings(max_retries: 0)` — the `settings` fixture takes `**overrides` for it —
    so `settings:` reaching the sync `RetryStep` is proven and not inferred from a call count the
    default schedule reproduces (guard 51); and `ReissueTest` gains the cross-origin 303 rebuild case
    over an `ORIGIN_SCOPED_HEADERS` `POST`, so `REDIR-9`'s "or the 303 GET rebuild" clause has its own
    proof (guard 52). Neither the plan's Task 13a tests nor its Task 12 tests carried either.
32. **`pipeline/standard_test.rb` is three nested classes, not two**: the addition pushed `WiringTest`
    over `Metrics/ClassLength`, so the two `PIPE-24` cases and the `install_preset` source scan sit in
    an `InstallationTest` and `WiringTest` keeps the keyword-threading cases — a split, never an
    inline disable, the way `step_test.rb`'s header says its seven classes were split.

## Findings routed

- **The design's two findings were verified at their owners and not re-filed**: the
  `URI::Generic#userinfo = nil` note is `docs/knowledge/notes/redirect-handling.md`, key
  `redirect-handling/b42d265d`, sha `manual-phase6b-userinfo-noop`, filed with the design; the eleventh
  audit row is `.claude/skills/knowledge-lookup/SKILL.md`'s "Resilience: retry, redirect and
  authentication", live. The note's "floor-straddling and not yet closed" caveat is **closed by a new
  entry** in the same note file (never an in-place edit, which re-keys it): the measurement was re-run on
  3.2.11, 3.3.12, 3.4.10 and 4.0.6 on 2026-09-19 and holds identically on every row, and
  `redirect/matrix_facts_test.rb` is the standing test.
- **Already routed, cited and not re-filed**: the replayability predicate's three spellings (6a's
  `Resend.eligible?`, 6b's `Resend.replayable_body?`, 6c's private `Step#replayable?`) — phase 10's
  inbound list, routed by 6c on 2026-09-18, "referred to by date and content, never by ordinal"; the
  `ScriptedTransport`/`SequencedTransport` pair — the manager's reconciliation chore, named in 6c's
  checklist and roadmap note, still open, and the convergence test uses `SequencedTransport` while every
  6b suite uses `ScriptedTransport`.
- **New, routed to phase 10's inbound list** as audit work against an already-planned phase, by date and
  content: `REDIR-13`'s default-port residue — `URI#to_s` elides an explicit scheme-default port and
  phase 1's `URL.parse!` re-parses a URI from its text, so `Location: https://h:443/y` and a caller's own
  `Request.build(url: "https://h:443/y")` both reach the wire as `https://h/y` (5b's P5-91 found the
  same elision in the redactor and reassembled from the split components instead); phase 10's `NFR-4`
  and `HTTP-46` audit decides whether phase 1's model should preserve an explicit default port in its
  external form, which is a phase-1 decision and not this layer's (P6-96).
- **Design §6.2's `URI.join`/`URI#merge` spelling**: the corpus half is done
  (`url-and-query-encoding/08c54234` overrides `redirect-handling/d4885fbc`), the build wrote
  `URI::RFC3986_PARSER.join`, and **no `C15` is owed**: §6.2's sentence states the semantics — "resolving
  through `URI.join`/`URI#merge` and never round-tripping through a re-rendered string" — and the
  semantics are what was built; the literal spelling is a cop's concern the note already records, so no
  frozen sentence is contradicted in substance. Stated here so the decision is not re-made.
- **The design's ledger** gains an "As built" addendum (P6-91–P6-100); the consolidation of P6-91–P6-100
  into design §10, the correction of §6.2's spelling and any §5.3 wording are a human's, as for 3a, 3b,
  4a, 4b, 4c, 5a, 5b, 5c, 6a and 6c, because `docs/sdk-design-ruby/` is frozen. `docs/deviations.md` is
  untouched, for phase 10 to flip.
- **6c's Task 15 row** ("written, guarded; owned by 6b") and 4c's `PIPE-39` ⏳ and `PIPE-32` rows stay as
  their records; this document closes them.

## Postponed work

**`REDIR-27` only**, declined for v1 (`docs/first-release.md`, cited above); no code, no trigger named.
**What earlier phases postponed here has landed**: phase 4c's two `standard` constructors (`PIPE-39`,
Task 13a), and the charter's convergence point 1 (6c's guarded test, un-guarded). **What this phase
leaves to others, none of it its own to defer**: the three-spellings predicate and the default-port
residue (phase 10, cited above); the two scripted transports' reconciliation (the manager); the
wire-boundary re-validation of every re-issued header at the transport (phase 8a's Task 16, phase 8c's
Task 9, phase 9's Task 7 — the seed's and the follow-up's headers alike). The `Cursor` context-bundle
widening was neither built nor consumed here and no deferral is filed in its place. **Phase 6 is
complete**: 6a, 6c and 6b are built, and every phase-level task the charter named — the widening (6a),
the constructors (6b) and the convergence test (6c wrote, 6b closed) — has landed.
