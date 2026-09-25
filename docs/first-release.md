# First Release

Release-readiness register — and, since 2026-09-13, also the register of what v1 ships without and of
the post-release triggers, recorded here when the deferral register was retired: every postponed item
now lives either in the plan task that will do it or in this file. The find-list register was retired
the same day, on the same rule — a finding is routed to its owner when it is found, not registered —
and four of its items came here: two blockers before first publish (documenting the `include Dexpace`
constant shadow, and the `AuthDescriptor` carrier decision), `CFG-20`'s cancel-with-interrupt clause
under the unsatisfied MUSTs, and the `CTX-7`/`CTX-8` drain proof under the post-release triggers. Two
more left a second home here beside their primary owner: the Minitest 6 trigger, and the
`gates:bounded_map` blocker — which was filed red and expecting a phase-10 repair, and was closed on
2026-09-23 by phase 9's own green run against a cap `8c` had already shipped, with no repair owed. **Nothing has been published.** Since phase 0 landed
(2026-09-14) `gems/` holds the six gems, since phase 1 (2026-09-15) `dexpace-core` carries the HTTP domain
model, and since phase 2 (2026-09-15) the seam layer as well; there is still no tag, and no version beyond the
`0.0.0` every gem starts at.

## Gems, once they exist

Per `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` §2.1, the MVP is six gems, every one of
them at `0.0.0` until the first release:

| Gem | Published? |
|---|---|
| `dexpace-core` | no — 0.0.0 |
| `dexpace-transport-net_http` | no — 0.0.0 |
| `dexpace-serde-json` | no — 0.0.0 |
| `dexpace-transport-async_http` | no — 0.0.0 |
| `dexpace-async-thread` | no — 0.0.0 |
| `dexpace-conformance` | no — 0.0.0. **Phase 8 owns this gem's gemspec, its version and its first
  release** (the roadmap's phase-8 row; phase 9 adds the remaining suites and owns neither). This is the
  row that moves first: phase 8's phase-level pull request performs the **workspace's first gem release**,
  and the conformance gem's framework-agnostic assertion objects (phase 8a, Tasks 4–8 and 20; phase 9,
  Tasks 2–12a) are what it has to release |

**Supported Ruby is not uniform across this table, from phase 8 onward.**
`dexpace-transport-async_http` declares `required_ruby_version >= 3.3` where every other gem keeps the
repository floor of 3.2 (phase 8c's deviation `P8-36`, whose per-gem Ruby floor gate edit is 8c's plan,
Task 3): `async-http` 0.104.0 and its whole
dependency closure require 3.3, and the last release allowing 3.2 is eleven minor versions behind the one
phase 8c verified against (built and proven on 0.105.0, 2026-09-21, with the floor read from one
`VERSIONS` row — `ruby floor:dexpace-transport-async_http 3.3` — by the gemspec, the gates, the
`Gemfile` and the two rake tasks that load the gem, so the 3.2 row installs, tests and clean-bundles
five gems and is green; on the 3.3 row the bundle compiles `openssl` 4.0.2, because the
interpreter's own 3.2.4 is older than `io-stream` requires — and a *networked* resolve, the
clean-bundle gate's scratch install included, picks the newest `openssl` gem on the 3.4 and 4.0 rows
too, as it picked `net-http` 0.9.1 over the default for 8a (`P8-60`), so the second extension's
toolchain need is confined to 3.3 only for an install that resolves the interpreter's own). **A consumer on Ruby 3.2 composes `dexpace-core`,
`dexpace-transport-net_http`, `dexpace-serde-json`, `dexpace-async-thread` and `dexpace-conformance`, and
loses only the reactor transport** — which is `NFR-2`'s separability paying for itself, and it should be
stated in the release notes rather than discovered at `bundle install`.

**One gem's transitive closure contains a native extension.** `dexpace-transport-async_http` depends on
`io-event`, which compiles C (`ext/extconf.rb`). A platform with no toolchain and no precompiled
`io-event` cannot install that gem; the composition above is the answer for such a platform too.

## Blockers before first publish

- [ ] Repository scaffolding: `gems/`, root `Gemfile`, `Rakefile`, `Steepfile`,
      `rbs_collection.yaml`, `.rubocop.yml`, `VERSIONS` (§2.3)
- [ ] CI wired up and green on every gem
- [ ] The `dexpace-conformance` suite passing across the full supported Ruby range, 3.2 through 4.0.
      **Checkable for the first time after phase 8** (2026-09-12): phase 8a writes the suite this line
      names — the conformance gem's assertion protocol (its Tasks 4–8 and 20), the §9.3 `TCPServer`
      fixture and both thin drivers — and
      phase 8a and 8c each run it against a real adapter. **With one stated exception**: the 3.2 row runs
      the suite against `dexpace-transport-net_http` only, because `dexpace-transport-async_http` cannot
      be installed there (see the supported-Ruby note above, `P8-36`, and 8c's plan, Task 3). "Passing across 3.2
      through 4.0" therefore means: every gem on every row it can be installed on. **Status 2026-09-20**:
      the suite exists — twenty-eight assertions over twenty-two `TRANSPORT` IDs, `HTTP-17`/`HTTP-18` and
      `PAGE-36` — and 8a ran it against `dexpace-transport-net_http` on 3.2.11 (net-http 0.4.1 and 0.9.1),
      3.3.12, 3.4.10 and 4.0.6, every assertion green and `TRANSPORT-18` vacuous by measurement; the
      `async-http` half waits for 8c. **Status 2026-09-21**: 8c ran it against
      `dexpace-transport-async_http` on 3.3.12, 3.4.10 and 4.0.6 — thirty-four assertions now, phase
      8c's two groups appended — with every assertion green and four skips accounted for by name: the
      two assertions under `TRANSPORT-14` and the one under `TRANSPORT-27` waived by id (`P8-38`,
      `protocol-http1` refuses both heads out of the read) and `TRANSPORT-18` vacuous by measurement
      as on 8a's adapter; on the 3.2 row the async half is not installable and the sync half is what
      runs, as this line already says
- [x] **Before release, `docs/sdk-documentation/` must state what a green `dexpace-conformance` run does
      and does not prove, and the run's own report preamble must name the same omissions.** Filed
      2026-09-12 by phase 8a's design (`P8-9`). The wire fixture speaks plaintext only and exercises no
      connect timeout, so `TRANSPORT-4`'s open-timeout half and every TLS property are asserted in
      `dexpace-transport-net_http`'s own suite and **not** in the portable one; phase 8c's adapter
      additionally carries a named waiver listing `TRANSPORT-14`, whose malformed-inbound-header-**name**
      clause is unreachable on `async-http` (`P8-38`; the roadmap's phase-10 inbound list carries §12's
      `TRANSPORT-14` scoping). A third-party adapter author whose adapter
      passes is entitled to know that TLS verification, connect-timeout classification and any waived ID
      were not among the things it passed — which is the difference between a conformance suite and a
      badge. Cites `TRANSPORT-4`, `TRANSPORT-14`, `TRANSPORT-20`, `NFR-2`; the suite itself is phase
      8a's Tasks 4–8 and 20 and phase 9's Tasks 2–12a. **Status 2026-09-20**: `TransportSuite::PREAMBLE`
      names the two omissions in every report, and `docs/sdk-documentation/conformance.md` states them
      beside what a green run proves; the box ticks when 8c's waiver is stated beside them. **Ticked
      2026-09-21**: the preamble names a third omission, `TRANSPORT-8`, whose antecedent only an
      adapter's own suite can originate, and `conformance.md` states 8c's two waivers (`TRANSPORT-14`
      and `TRANSPORT-27`, both by id, both this adapter's alone) beside the three omissions. **Narrowed
      2026-09-25 by phase 10 (`R11`)**: the two waivers were re-measured -- `conformance_test.rb`'s "the two
      waived clauses are unreachable here: protocol-http1 refuses both heads out of the read" still passes
      on 3.3.12, 3.4.10 and 4.0.6, so both still state the truth -- and the page must add the largest
      thing a green run does not prove: `gems/dexpace-conformance/APPENDIX_B.md`'s rows dispositioned
      **by reference**, where the evidence is another gem's test file and the row proves the ID is claimed,
      never that the behaviour is asserted (`Aggregate::PREAMBLE` already prints it)
- [ ] **Before release, `docs/sdk-documentation/` must document the `include Dexpace` constant-shadow
      hazard.** Filed 2026-09-08 by phase 3a's design; recorded here 2026-09-13. Phase 1 measured
      `Dexpace::Method` shadowing `::Method` and concluded "**verified inert outside core**"; the observation
      is true and the conclusion is wider than it supports, because the measurement was taken at the top level.
      Verified 2026-09-08 on 3.2.11, 3.4.10 and 4.0.6, identically on all three: a **top-level**
      `include Dexpace` is inert, since `include` inserts `Dexpace` into `Object` and `Object`'s own constant
      table is searched first — but a consumer writing `class C; include Dexpace; def check(x) = x.is_a?(IO);`
      gets `Dexpace::IO`, because `include` puts `Dexpace` **ahead of** `Object` in `C.ancestors`
      (`[C, Dexpace, Object, Kernel, BasicObject]`). `C#check` then returns **`false` for a real `::IO`**, with
      no error and no warning; `IO === x` is false and a `case/when IO` falls through. `extend Dexpace` and a
      class with no include are unaffected; a `module M; include Dexpace` behaves like a class. It is about
      **every flat `Dexpace::` constant sharing a name with a core class** — `Dexpace::Method`, `Request`,
      `Response`, `Query`, `Status`, and `Dexpace::IO`, which phase 3a adds and which is the one callers most
      often type-test — and `include Dexpace` is an ordinary Ruby convenience phase 1 deliberately measured, so
      it is a use this port expects. Nothing mechanical can reach a consumer's file: phase 3a's extension of
      `Dexpace/QualifiedCoreConstant` covers `gems/*/lib/**/*.rb` and stops at the gem boundary by
      construction. Renaming is not on the table — design §3.1 and §10.2 name `Dexpace::IO::Buffer`, and `P1-1`
      keeps a namespace the design gave a subsystem. Phase 3a states the hazard in `Dexpace::IO`'s own YARD
      block and, since 2026-09-15, in `docs/sdk-documentation/io.md`'s opening section and the core README,
      where a consumer meets it, with the consumer case pinned in `gems/dexpace-core/test/dexpace/io_test.rb`;
      what is still owed before the tag is a release decision that has seen it
- [ ] **A decision on where a per-call or operation-level `AuthDescriptor` is carried.** `AUTH-4`–`AUTH-7`'s
      tier resolution takes a per-call, an operation and a client `AuthDescriptor` in that preference order,
      and `6c` ships the resolver as a correct, tested, stateless pure function. What no phase specifies — not
      1 through 5, and not `AUTH`'s own 38 IDs — is **where a per-call or operation-level descriptor is
      carried**: `docs/sdk-design-ruby/` names no field on `Request`, on `RequestOptions`, or on any
      `Operation` construct for it, and no `AUTH` requirement asks for one. `AUTH-1`–`AUTH-7` describe the
      descriptor and the resolver as data and a function, never a carrier. `6c` therefore ships the AUTH
      pillar step accepting an **already-resolved** stamper — `Step.build(stamper:)`, built 2026-09-18, takes
      one stamper and no `Scheme => credential` table — at construction time, treating the resolver as a
      standalone library object whose caller —
      presumably Operation-building code, outside `AUTH`'s scope entirely — invokes it and threads the result
      into the step. **Release-gated since 2026-09-13; this line owns the decision**, filed 2026-09-09 by
      phase 6c's design. No v1 phase builds that Operation-level wiring, so `AUTH-4`–`AUTH-7`'s resolver ships
      correct and exercised **only by its own unit tests**, never by an end-to-end call path. The event that
      would reopen it is **the first consumer that needs per-call or per-operation credentials — a worked
      example in `docs/sdk-documentation/`, a `dexpace-conformance` fixture, or a downstream SDK's `SEAM-26`
      operation projection carrying a descriptor**. Until that event: either the release notes state that the
      tier resolver has no carrier and only the client tier is reachable end to end, or a carrier is built
      before the tag
- [x] **`gates:bounded_map` green: `dexpace-transport-async_http`'s `Clients` is an uncapped
      per-origin client cache, which `XCUT-14` (MUST) forbids.** — **CLOSED 2026-09-23 by phase 9's
      `gates:bounded_map` run.** Found 2026-09-13 by phase 9's planning, and
      the **one true positive** of six `gates:bounded_map` reports over 222 filed Ruby fences at 184 distinct
      `gems/*/lib/**/*.rb` paths, measured identically on 3.2.11, 3.3.12, 3.4.10 and 4.0.6. The map is
      instance-lived and lives as long as the client, its key space is chosen by caller URLs and by a server's
      redirect `Location`, `#fetch` inserts with `||=` and nothing evicts — `#close` closes each client's pool
      and leaves the map populated. The repair is **phase 10's**, because `8c` owns the file and has already
      run by the time phase 9's audit does, and it sits on phase 10's inbound list (the roadmap's 2026-09-13
      status note) with the measured detail and the line numbers. The gate stays red until it lands, and
      `XCUT-14` being a MUST is why this is a blocker rather than a report line. **Amended 2026-09-13
      by the final pre-build review of phase 8c: `8c`'s plan Task 8 now bounds the map at planning
      time** — `Clients::MAX_ORIGINS`, drained back to the cap in a loop after each insert, with each
      evicted client's pool closed — so the map is expected to be bounded the moment `8c` lands and
      this blocker to close then, without a phase-10 repair. Phase 9's routing assumed `8c` had
      already run; it had not. This line stays open until a green `gates:bounded_map` run confirms it.
      **Status 2026-09-21**: 8c landed the bound — `Clients::MAX_ORIGINS` (32) over a key of
      (reactor, origin), drained back to the cap in a loop after every insert with closed reactors
      evicted first, every evicted client's pool retired and closed — proven by the three `XCUT-14`
      cases in `gems/dexpace-transport-async_http/test/dexpace/transport/async_http/clients_test.rb`;
      the gate itself does not exist yet, so the line stays open for phase 9's `gates:bounded_map` run
      and nothing else. **Closed 2026-09-23**: phase 9 built the gate and ran it. `gates:bounded_map`
      is **green over all 307 files in the six gems' `lib/` trees**, with six adjudicated exceptions,
      none of them this one. `clients.rb` is on the allowlist as a **verified false positive of the
      scan**, not as a silenced defect — the scan sees a Hash assigned to an instance variable and
      cannot see a cap, and the reason recorded beside the entry is the reading of the file: `#fetch`
      inserts with `||=` and calls `#drain` inside the SAME `@mutex.synchronize` as the insert, and
      `#drain` is a loop, `evicted << @by_key.delete(@by_key.keys.first) while @by_key.size >
      MAX_ORIGINS`, with closed reactors evicted first, which is `XCUT-14`'s drain clause exactly.
      The as-built ivar is `@by_key` and not `@by_origin`, which is why a check against the planning
      note's name would have missed it. `XCUT-14`'s checklist row is ✅ and no phase-10 repair is
      filed
- [ ] **Before release, `docs/sdk-documentation/` carries one worked end-to-end example** — a
      generated-style client over `dexpace-core` + `dexpace-transport-net_http` + `dexpace-serde-json`:
      operation descriptor, request assembly, pipeline with an AUTH step, decode, typed error, one
      paginated call. Filed 2026-09-13 by the roadmap-level generator-fitness review. This is the
      artifact **three standing decisions name as their reopening trigger** — the `AuthDescriptor`
      carrier line and the `HTTP-22`/`48`/`49`/`50` line above both read "a worked example in
      `docs/sdk-documentation/`" — so writing it forces both rather than leaving each waiting on an
      artifact nothing schedules. No phase produces it: the phase-7 and phase-8 segmentation designs
      each record `docs/sdk-documentation/architecture.md` as "**not** a phase deliverable. Recorded
      so the absence is a decision", and no `NFR` reaches user documentation, so phase 9 dispositions
      nothing here. The same pass discharges the three narrow obligations this file already carries
      against that tree: the conformance-run caveat, the `include Dexpace` constant shadow, and
      `Dexpace::IO::MAX_MATERIALIZED_BYTES`. Cites `SEAM-26`, `SEAM-27`, `SERDE-28`, `RECOV-15`,
      `PIPE-39`. **Narrowed 2026-09-25 by phase 10 (`R7`, `P10-7`): the example must also show the
      correlation chain** -- constructing a `Dexpace::DispatchContext`, promoting it with
      `#promote_to_request` and `#promote_to_exchange`, and where the operation name goes -- because no
      phase builds a call path that does it and this is the one place a generated client's author meets
      it (`CTX-16`, `CTX-14`, `SEAM-28`; the *Behavioural asymmetries* entry below)
- [ ] **The eighteen recorded corrections (fourteen until phase 10 completed the set on 2026-09-25) to `docs/sdk-design-ruby/` §3, §4, §5, §8, §9, §10, §11, §12 and to
      appendix C's `SSE-19` row applied — or the release notes stating which design sentences a reader
      should not trust.** Filed 2026-09-13 by phase 10's design. Every one is a place where the **rule**
      is right, the **mechanism sentence** is wrong about Ruby or about a library, and the phase that
      found it shipped the working code already. Numbered `C1`–`C13` by that design and enumerated here
      so no amendment recorded in `docs/deviations.md` ends the phase without a line in this blocker:
      §3.1's decode recipe (`C1`), §4's builder list dropping the
      multipart body `HTTP-3` names (`C2`), §3.1's and §10.12's attribution of `IO-6`'s ownership rule to the
      retired `SEAM-3` (`C3`), §8.1's `Event#tag` (`C4`), §3.2's block-scoped `read_body` (`C5`), `Net::HTTP`'s
      default-on retry against §3.2/§11.18/§12 (`C6`), §12's `TRANSPORT` row in both directions
      (`TRANSPORT-14` unreachable on `async-http`, `TRANSPORT-8` satisfiable there — `C7`), §8.3's absolute
      prohibition (`C8`), §9.3's "default gem" for a bundled Minitest (`C9`), §9.3's unstated report unit
      (`C10`), **§10.5's mitigation sentence attributing the socket-closing hook to "an adapter" where only
      the transport can perform it** (`C12`), **§12's `PAGE` row recording one vacuity fewer than
      `dexpace-conformance` will, `PAGE-15`'s wrapping clause and `7c P7-1`** (`C13`), and — the one
      against the **normative** specification — the two measured places where appendix C and a chapter
      diverge and neither says so: appendix C's `SSE-19` row drops the port sanction
      `docs/product-spec/13-…md:33` grants, and `docs/product-spec/15-…md:54`'s `OBS-29` sentence drops the
      "wiring … is a follow-up, so it is not yet runtime-enforced" clause appendix C's row carries (`C11`). The
      second cost five documents across four phases an open surface decision the requirement had already
      closed, which is why it is a pattern and not an erratum. **Why it is a blocker and not a report line:** these are the documents a
      consumer and a future porter read, thirteen of their sentences are false about the shipped code, and
      five of the trees they live in are frozen to every maintenance tool and reserved to a human acting
      deliberately — so no phase can close this, and leaving it unmentioned is the one outcome
      `docs/deviations.md`'s holding area exists to prevent. **The alternative form is real**: a release
      may ship with the sentences unamended if the notes say which they are; it may not ship with them
      unamended and unmentioned. The set, with each frozen sentence quoted, its replacement written out,
      its measurement and its verified code half, is `docs/deviations.md` § Deviations found outside a
      phase, completed by phase 10's plan, Task 17. **A fourteenth, filed 2026-09-16 by phase 4b's
      implementation (`C14`)**: §10 item 6's "`Dexpace::Error#suppressed` supplies the list" and §5.2's
      placing of the suppressed trail on `Dexpace::Error` itself. The rule is right — one core-owned trail,
      rendered wherever the error is displayed — and the mechanism sentence is wrong about where the method
      is defined and about what else can carry a trail: every primary `RECOV-12`, `close_quietly` and
      `Hooks.notify` hand the helper is a caller's exception, so the trail lives on `Dexpace::Suppressible`,
      which `Dexpace::Error` includes and `Dexpace.attach_suppressed` extends onto anything else (phase 4b's
      design, P4-12; the working code is `gems/dexpace-core/lib/dexpace/suppressible.rb`). Its replacement
      sentence is written out in 4b's design ledger and awaits the same human hand as the thirteen.
      **Completed 2026-09-25 by phase 10, which wrote the set out in `docs/deviations.md` § Deviations
      found outside a phase with every frozen sentence quoted, its replacement, its measurement and its
      code half verified in as-built source -- `C1`-`C14` plus four the as-built audit added:** `C15`,
      §10.18's list of platform-constant substitutions omitting 7b's `SSE::MAX_LINE_BYTES` and
      `MAX_EVENT_BYTES`; `C16`, §9's gate table carrying none of the seven gates phases 7b, 9 and 10 added
      (`gates:serde_boundary`, phase 9's addenda A4-A7, phase 10's A8-A11) or the probe's ninth check;
      `C17`, §11.8 naming the third surviving `XCUT-23` instance "executor" where it is the async transport
      seam (`Dexpace::AsyncTransport::REGISTRY`; there is no executor registry); and `C18`, §10.13 spelling
      the four encode profiles without the value they encode (`dump_to(value, sink)`, not `dump_to(sink)`);
      and `C19`, §4's and §10 item 10's "`send(:new, …)` reaches the generated constructor", where as built
      `send(:new)` runs the validating `#initialize` and the residual holes are `.allocate` and duck typing
      (phase 10's review round 0, R0-6).
      **The same human act owes one thing more, named here so it has an owner: the consolidation of every
      phase's as-built Deviation Ledger rows -- `P0-…` through `P9-42` and phase 10's `P10-1`-`P10-11` and
      `P10-21`-`P10-38` -- into design §10.** Each phase's status note ends "consolidation into design §10
      is a human's"; phase 10 is the last phase and the chapter is frozen to it. **The alternative form holds
      for this half too**: a release may ship with the ledgers unconsolidated if its notes list the phase
      ledgers a reader must consult beside §10
- [ ] An RBS sig-diff baseline established, so a later release can be checked against it for an
      accidental breaking change. **Phase 10 is the phase that can**: its plan, Task 5 is the last change
      to `sig/` in every gem, so Task 18 establishes the baseline over a tree nothing else will move —
      **both** baselines, the `sig/**/*.rbs` tree and the runtime surface snapshot, because `rbs`
      describes what someone wrote and not what `Data.define` generates. This line is design §9's
      release-tag mechanism, not `NFR-4` itself: appendix C's `NFR-4` is "a checked-in,
      machine-comparable snapshot" with the build failing on drift, which `gates:surface_snapshot` over
      the six manifests already is, so `NFR-4` is ✅ (phase 9's mark, kept by phase 10's `P10-35`) and
      what waits for a `v*` tag is `gates:sig_diff`, vacuous until one exists. (Corrected 2026-09-25 by
      phase 10's review round 2, R2-1: this sentence had read `NFR-4` as a diff against the previous
      release tag that stayed ⏳ until a tag.) **Still open after phase 10, with the reason (2026-09-25, `P10-36`):**
      `tools/sig_diff.rb` takes its baseline from `git describe --tags --match v*` and reads no committed
      baseline file, and phase 10 may not tag -- so the `sig/` baseline cannot be established inside this
      repository's design by any phase. Phase 10 did regenerate the six runtime surface manifests once,
      deliberately (two rows: `Dexpace::Protocol::HTTP_1_0` and `Dexpace::Status#standard?`), and put the
      SPDX header on every shipped `.rbs` -- the last change to `sig/` before a tag. The line closes with
      the first `v*` tag
- [ ] **The one-time public-surface choices the phases flagged, each decided before `NFR-4` locks it
      at the first `v*` tag.** Filed 2026-09-25 by phase 10, which is the last phase and cannot hand them
      forward. Adding a public name later widens (`api-design/1d9e6e0b`); removing or narrowing one after
      the tag is a break, so each is decided now or deliberately kept. The list, every row read off the
      tree on 2026-09-25: `BufferedSource.__dexpace_view` as a private class method reached by `send`
      (3a); `Dexpace::Body`'s identity `#==`/`#eql?`/`#hash` (3b); `ResponseBody.new` requiring `#peek`
      beside `#read_into` (3b); `Bundle#remote` beside `Bundle#remote?` and `ContextStore#put`/`#[]`
      with no caller in `lib/` (4a); `Recovery::Orchestrator#call`'s three required positionals (4b);
      `Pipeline::Stage#with`, a public row whose only behaviour is to raise (4c); `Instrumentation::Scope.build`,
      public and marked `@api private` (5c); **the body-replayability predicate's three spellings** --
      `Resilience::Resend.eligible?` and `.replayable_body?` public, `Auth::Step#replayable?` private
      (6a/6b/6c; the roadmap's 2026-09-18 bullet); the two transports' public `Adapter.owning`/`.borrowing`
      (8a, 8c); and **the default-port elision at the model boundary** -- `URL.parse!("https://h:443/y").to_s`
      is `"https://h/y"`, so a caller's explicit default port and a redirect's are both elided and
      `HTTP-46`'s textual comparison sees none (6b's P6-96; measured again 2026-09-25). None is a defect;
      each is a choice a release owner signs off. Cites `NFR-4`, `HTTP-46`, `RETRY-5`, `REDIR-6`, `AUTH-31`
- [ ] `SECURITY.md` contact confirmed reachable and monitored
- [ ] RubyGems ownership settled for every gem name above, and trusted publishing configured
      (OIDC-based, no long-lived API key committed anywhere)
- [ ] A decision on the four unbuilt convenience requirements in the HTTP domain model —
      `HTTP-48` (ETag), `HTTP-49` (HTTP range) and `HTTP-50` (the conditional-request aggregator),
      all SHOULD-level, plus `HTTP-22` (header-name interning, a MAY). Phase 1 built none of them.
      **The phase-6 target the deferral originally named was corrected on 2026-09-09: it does not
      fire.** Phase 6 carries a
      conditional header but constructs none — `REDIR-3`/`REDIR-4` preserve, `REDIR-5` strips,
      `AUTH-30` copies — so the four are still unbuilt after phase 6 and this decision is still owed.
      **Release-gated since 2026-09-13; this line owns the decision.** Phase 7's candidate
      does not fire either: the phase-7 segmentation design declined it, `7c` constructs no conditional
      header, `7a` copies the raw `ETag` string, and `SSE-38` forbids the SSE reader from setting a request
      header — so no v1 phase gives the four a caller. The event that would reopen it is **the first
      consumer that constructs a conditional request — a worked example in `docs/sdk-documentation/`, a
      `dexpace-conformance` fixture, or a downstream SDK's `SEAM-26` operation projection asking for one**.
      Until that event, it is a release decision and not a phase's: either the release notes state that
      `HTTP-22`, `HTTP-48`, `HTTP-49` and `HTTP-50` are unbuilt, or the four are built before the tag
- [x] **Phase 8's first transport adapter must wrap every stdlib I/O and timeout error it lets
      escape** — `Errno::ETIMEDOUT`, `SocketError`, `Timeout::Error` and their kin — in something
      answering `#retryable?` (`Dexpace::TransportError` or equivalent), defaulting to `true` per
      `XCUT-4` branch (b). **Ticked 2026-09-20**: `Dexpace::TransportError` landed with 8a's Task 2 in
      the shape below, and `dexpace-transport-net_http`'s `Failures.wrap` is a catch-all over every
      `StandardError` that is not already a `Dexpace::Error` — the twelve families the design names each
      proven wrapped with the original as `#cause`, on net-http 0.4.1, 0.6.0 and 0.9.1
      (`gems/dexpace-transport-net_http/test/dexpace/transport/net_http/failures_test.rb`). The
      `async-http` families are 8c's to prove against the same class. `RETRY-2`'s classification is a capability-only query (`XCUT-6`;
      `CFG-35`'s throwable half is phase 6a's Task 3, `Policy.throwable_retryable?`), so a bare
      unwrapped stdlib error classifies as **not retryable**, which is a silent
      retry-eligibility regression for exactly the class of failure `RETRY-4` calls "always
      retryable". It is invisible until an adapter exists to test it against, and reachable the
      first time a real socket times out. Recorded by phase 6a's design as deviation `P6-4`.
      **Closed in design 2026-09-12 by phase 8's planning; the box ticks when the class lands, which
      is phase 8a's Task 2.** The question this line asked — *will* phase 8 do it, with what, and who
      owns it — is now answered rather than open. `Dexpace::TransportError` is a **phase-level** task in
      `dexpace-core`, in a different gem from all three sub-phases, with one owner (8a's Task 2; 8c's
      Task 4 is a citation and a verification, and defines the class only in the out-of-order case, in
      the identical shape): `class TransportError < ::IOError; include Dexpace::Error; end`, `#retryable?`
      returning `true` unconditionally with no keyword that can override it, and a `#phase` reader
      (`:connect`/`:write`/`:read`/`:close`) **for diagnostics only, never branched on by `RETRY-2`'s
      capability query**. Phase 8 also supplies the exact list the wrap must cover, which is what makes
      the blocker real rather than theoretical: `Net::OpenTimeout`, `Net::ReadTimeout`,
      `Net::WriteTimeout` (all `< Timeout::Error < RuntimeError`), `SocketError` (`< StandardError`),
      `Errno::*` (`< SystemCallError`), `Async::TimeoutError` (`< StandardError`) and
      `Protocol::HTTP1::Error` (`< StandardError`) — **not one of which is an `::IOError` descendant**.
      It also closes phase 6a's deviation `P6-4`

## What v1 ships without

Recorded here on 2026-09-13, when the deferral register was retired: every postponed item now lives
either in the plan task that will do it or in this file. The items below were reconciled against the ten
phases planned so far, 0 through 9, before they landed here. **The release notes MUST state every item in
this section.** None is a blocker: each is a requirement below MUST level that v1 declines, a gem design
§2.2 places after v1, or — in exactly one entry — a pair of MUSTs the port cannot satisfy under its own
rules and says so. Every entry leads with its subject and requirement IDs, and a checklist row marked ⏳
for one of those IDs cites the entry here rather than a phase.

**One subsection is a fourth kind, added 2026-09-13**: *Behavioural asymmetries a consumer must know*
records a place where v1 **satisfies** its requirements and two paths still behave differently. Its
entries carry no ⏳ row, because nothing is declined or postponed; they are here because this is the
section the release notes are read out of, and a consumer who needs the fact would otherwise have to
find it in a design document.

### Unsatisfied MUSTs

- **Cancel-with-interrupt against a blocking worker — `ASYNC-3` and `PIPE-33`'s interrupt clause
  (MUST).** Design §10.5 records both as **unsatisfied** and `ASYNC-4` as **vacuous**, and the distinction
  is load-bearing: `ASYNC-4` was never part of this item — the deferral, from the day phase 2 filed it,
  cited `ASYNC-3` and `PIPE-33` only — and `8b` marks it N/A citing §10.5 directly, so it is not added to
  this entry. **Why the condition is unmeetable.** The pick-up condition was "an interruptible transport
  path", and
  design §8.3 forbids `Timeout.timeout`, `Thread#raise` and `Thread#kill` in every gem here, because an
  asynchronous interrupt can land on any bytecode instruction, including inside an `ensure` releasing a
  pooled connection; the check-after-resume rule and `Completer#on_cancel` mitigate but do not close the
  gap, since a transport blocked inside an uninterruptible C-extension read cannot be aborted early. No v1
  phase adopts such a path and none may, which is why the item is recorded as post-v1 rather than left
  waiting for a phase. **Where it is carried.** Phase 4c's checklist marks `PIPE-33` ⏳ citing this entry —
  `PIPE-33` is inside phase 4c's own ID range, and its row names the four clauses that **are** met so it is not
  read as a wholly unbuilt requirement; `8b`'s checklist marks `ASYNC-3` ⏳ and `PIPE-33`'s
  cross-reference row ⏳, both citing this entry, which is a re-assertion at the point the requirement's
  antecedent becomes real rather than a second decision (built 2026-09-21: both rows cite this entry as
  forecast, `ASYNC-4` is N/A on §10.5 alone, and the pool's own suite demonstrates the mitigation — a
  task cancelled while queued never reaches the transport, a send already running completes and its
  result is closed rather than delivered, and nothing is ever interrupted); phase 9's `ExecutorSuite` asserts `ASYNC-3` so that it
  **genuinely fails**
  and the thread driver waives it by ID (phase 9, Task 11 and Task 16 Step 4) — a waived failing assertion,
  never a green one; phase 10 audits the §10.5 ledger and may not re-open the trade (roadmap cross-cutting
  constraint 8). That `dexpace-transport-async_http` *can* abort an in-flight exchange through a parent
  task's cancellation does not close `ASYNC-3`, whose antecedent is a blocking task on a **worker thread**.
  **`CFG-20`'s cancel-with-interrupt clause is this same unmet clause under a second ID**, added here
  2026-09-13 (found 2026-09-09 by the phase-5 segmentation design). `CFG-20` is a SHOULD, three of its four
  clauses are met, and the fourth is the prohibition §10.5 already settles — so **the port gains no fourth
  unsatisfied MUST** and `CFG-20` does not join this entry's heading. What it gains is a citation that states
  the gap, which it did not have: design §10.5 names `ASYNC-3`, `ASYNC-4` and `PIPE-33` and stops; §12's `CFG`
  row says `CFG-20` is "reshaped as the pivot", which does not say a clause is unmet; and §10 item 4 lists
  `CFG-20` among the IDs it touches but argues the mechanism substitution rather than the gap — three
  citations available to a `CFG-20` checklist row and not one of them saying what is missing, which is exactly
  the ✅-or-⏳-with-an-unstated-clause the roadmap's one-row-per-ID convention exists to stop. Phase 5a's `R7`
  owns the row's form (⏳ against this entry with a note that the entry does not cite `CFG-20`, ✅-with-clauses
  naming the three that are met, or a partial marker of its own). The parallel worth reading beside it is
  §11.20's `RECOV-31`/`RETRY-38`, "the same feature under two IDs", and phase 4's treatment of it.

- **Streaming a response body through the deserializer without materializing it — `SERDE-27`'s
  no-materialization clause (MUST).** Added 2026-09-13 (found in the final review of phase 7a, decided
  by 7a's design on 2026-09-10 as `7a P7-1`). `SERDE-27` requires a response-decoding handler to
  "stream the response body directly through the deserializer into the target value (**without first
  materializing the whole body**)". **Why the clause is unmet.** Measured against **json 2.19.9**, the
  exact floor `dexpace-serde-json`'s gemspec declares — not merely against the 2.9.1 the interpreter
  ships — `JSON.parse` raises `TypeError` on a `StringIO`, `JSON::Parser` exposes only
  `#parse`/`#source`, and no singleton method is pull-shaped; the one IO-accepting entry point is
  `JSON.load`, which design §3.4 bans by lint rule for `create_additions`/CVE-2020-10663. The
  `#to_str` loophole works and buys nothing, because `#to_str` must return the whole `String`. The only
  remaining route is to write a JSON parser inside the gem whose entire purpose is to delegate to
  `json`, which would make the `>= 2.19.9` floor meaningless. **What ships instead.**
  `Dexpace::Serde::DecodingHandler` materialises nothing — it hands `#load` the `BufferedSource` — and
  the adapter then drains to EOF into one `String` under `Dexpace::IO::MAX_MATERIALIZED_BYTES`, 3a's
  64 MiB ceiling, checked incrementally. A body above it raises `Dexpace::StreamError`, an `::IOError`,
  which propagates unwrapped past the codec's `rescue ::JSON::JSONError` — correct under `SERDE-12`,
  and the observable behaviour a caller meets. **Why it is adapter-local and repairable.** The seam's
  `#load(source, witness)` **already takes the source**, so an adapter whose library has a pull parser
  satisfies the clause outright with no change to core, to the handlers or to the seam;
  `dexpace-serde-oj` (§ Post-v1 gems) is the named candidate and its entry records the same property
  from the other side. **Two things owed before release**, which is why this is an entry and not only a
  ledger row: the documented behaviour of a typed response handler on a body above
  `MAX_MATERIALIZED_BYTES` must be stated in `docs/sdk-documentation/`, so a caller streaming a large
  JSON response meets a documented limit rather than an `::IOError` — **done 2026-09-20**, when phase 7a
  was built: `docs/sdk-documentation/serde.md` states it under "`#load` materialises the whole text",
  and the codec's suite asserts the `StreamError` propagates unwrapped
  (`gems/dexpace-serde-json/test/dexpace/serde/json/codec_load_test.rb`, the `R1/P7-1` case); and phase
  8's adapters must each be checked for whether their library offers a pull parser that would satisfy
  the clause — phase 8's segmentation design already records that none of its three does, and this half
  stays open until phase 8 lands. **Where it is carried.** `7a`'s checklist marks `SERDE-27` with the
  clause named and cites this entry; the deviation row is `7a P7-1`, consolidated into design §10 and
  audited by `docs/deviations.md`; as built, the codec drains through 3a's `#read_utf8` and the ceiling
  it reads is the configured `Dexpace::IO.max_materialized_bytes`. Cites `SERDE-27`, `SEAM-21`, `IO-9`,
  `BODY-32`.

### SHOULD- and MAY-level requirements declined for v1

Each bullet: the IDs with their level, why v1 declines them, the trigger that would reopen the decision,
and the phase whose checklist carries the ⏳ row citing the entry here.

- **`SEAM-24`'s second sentence (SHOULD) — each adapter's caller-facing cancellation bridge over the
  host's own primitive.** The requirement's first sentence, propagating the diagnostic context across the
  thread handoff, *is* met: it is `ASYNC-8`'s, `dexpace-async-thread` implements it through `Fiber[]`, and
  `dexpace-transport-async_http` inherits it by construction. What v1 declines is the second sentence,
  because no v1 gem hands a caller a primitive to bridge — the thread pool hands out no `::Thread`,
  `#post` returns `nil`, and the only handle a caller holds is the pivot. Trigger: the post-v1
  `dexpace-async-async` gem, below, to which design §3.3 assigns the bridge. ⏳ row: phase 2, which owns
  `SEAM-24`; the narrowing is recorded by the phase-8 segmentation design and `8b`'s and `8c`'s. (The
  same deferral's other half, `SEAM-28`'s stable operation identifier, is not here: it is phase 5c's Task
  4, over the `RequestContext#operation_name` phase 4a's Task 7 built.)
- **`BODY-36` (MAY) — a read-only memory-mapped view of a file-backed body.** Ruby's
  standard library has no `mmap`; the only routes are a C extension or the `mmap` gem, both barred from
  `dexpace-core` by `SEAM-1`/`NFR-1`. Trigger: core's dependency budget changes — an event, and no phase in
  v1 can produce it. ⏳ row: phase 3b, which owns the ID. Its companion **`BODY-12` clause 2 (SHOULD)** —
  the transport dispatching a true zero-copy kernel path for a `Dexpace::FileBody` — is not a deferral but
  an **UNSCHEDULED** decision (2026-09-12, phase 8a's design, R5; **confirmed at execution 2026-09-20 on
  net-http 0.4.1, 0.6.0 and 0.9.1** — the kernel path is still unreachable without bypassing the library's
  own write path) and is stated here so the release notes carry it: `Net::HTTP` streams a body through
  `::IO.copy_stream` into a `Net::BufferedIO` whose `is_a?(::IO)` is false, so the kernel path is
  unreachable without rewriting the library's own write path. Clause 1 was discharged by phase 3b (`::IO.copy_stream` with the
  `(length, offset)` window) and is not owed.
- **`PIPE-36` (SHOULD), pillar-step stage locking.** Post-MVP per the design's own coverage
  index; nothing in v1 implements any part of it, and 4c's design names `#stage`'s precedence table (its
  R10) as where a lock would go. Trigger: none narrower than post-MVP has been named. ⏳ row: phase 4c.
- **`RECOV-31` (MAY), `RETRY-38` (SHOULD by tag, MAY by prose; the conflict is
  recorded at design §11.10), `RETRY-29` (MAY) and `RETRY-43` (MAY).** The per-attempt ordinal header is
  one feature seen from two requirement angles (`RECOV-31`/`RETRY-38`); the server-driven retry override
  and the fixed-delay mode are opt-in modes the MVP's retry engine does not need. Trigger: per-attempt
  observability being prioritised, at which point all four are revisited together. ⏳ rows: phase 6a, one
  per ID, `RECOV-31`'s beside `RETRY-38`'s.
- **`REDIR-27` (MAY), a configurable redirect-target header.** `Location` is the only header v1
  reads. Trigger: none named. ⏳ row: phase 6b.
- **`SSE-41` (MAY), a reactive adapter's error and lifecycle latitude.** Scoped to a reactive
  SSE adapter, and v1 ships only the pull-based SSE view. Trigger: a reactive SSE adapter being built. ⏳
  row: phase 7b.
- **`OBS-32` and `OBS-37` (SHOULD), OpenTelemetry metric conventions and the async body-capture
  skip.** Both presuppose infrastructure v1 does not ship: the metric conventions need an OTel adapter,
  and the body-capture skip needs the async-runtime bridge to have observability wired through it.
  Trigger: the post-v1 `dexpace-instrumentation-otel` gem together with the post-v1 async adapters,
  `dexpace-async-async` and `dexpace-async-concurrent_ruby`, all below.
  ⏳ rows: phase 5c (`OBS-32`) and phase 5b (`OBS-37`).
- **`TRANSPORT-28`'s zero-copy clause (SHOULD), per-adapter.** The two
  MVP transports do not need it to satisfy the transport contract; `8a`'s R5 finds `TRANSPORT-28`'s
  reachable half satisfiable on `Net::HTTP` and only its zero-copy clause outstanding — built and proven
  2026-09-20: a file body's `offset:` and `count:` window reaches the wire exactly and the body is
  replayable, on every supported row. Trigger: a transport adapter beyond the two the MVP ships. ⏳ row:
  phase 8a — `TRANSPORT-28`'s zero-copy clause. **`TRANSPORT-30` was in this entry and is no longer** *(narrowed 2026-09-13)*:
  `8a`'s `R17` found the deferral resting on a premise that was false in both directions — phase 5a
  ships `CFG-22`–`CFG-28`'s proxy resolver and routes proxy *use* to phase 8, and `Net::HTTP.new`'s
  `p_addr` defaults to `:ENV`, so the adapter was already proxying from the environment with a
  credential it had never resolved. `8a` implements the requirement instead (its plan Task 19b), which
  also gives that resolver its first consumer.
- **Connection reuse: `dexpace-transport-net_http` opens one TCP — and over HTTPS one TLS —
  connection per request** *(added 2026-09-13)*. Design §3.2 requires a per-call `Net::HTTP` and `8a`
  measured why: one shared client under eight threads produced 128 errors **and 26 responses matched
  to the wrong request**, which is `TRANSPORT-29`'s conformance clause failing. So v1 ships with no
  keep-alive and no connection pool on the reference synchronous transport, and every request pays a
  handshake. It is not a requirement gap — no `TRANSPORT` ID asks for pooling — but it is the first
  thing a user benchmarking against `faraday` will find, so it is stated here rather than left to be
  discovered. A pool is not reachable inside `NFR-2`'s budget (`connection_pool` would be a second
  third-party declaration and `gates:gemspec_audit` rejects it), and a hand-rolled one would have to
  answer every bounded-pool and deterministic-teardown rule the corpus routes to
  `dexpace-async-thread`, in a gem that is not that one. Trigger: a deliberately designed bounded pool
  with a checkout timeout, or `dexpace-transport-httpx`/`-excon` (§ Post-v1 gems), whose libraries
  pool natively. The corpus note is `docs/knowledge/notes/transport-adapter.md`'s `## Reference` entry
  beside `resource-management/4aca52f9`; `docs/sdk-documentation/` must state it before release.
- **Presence-gated auto-activation for instrumentation (design §3.6; cites `SEAM-5`, `SEAM-2`,
  `OBS-31`).** Phase 2 shipped the three seam registries and no auto-activation hook of any kind, with a
  test asserting the hook is absent; phase 5c read the deferral's condition — "an instrumentation seam
  exists to activate" — and found it **not met**, because `SEAM-2` enumerates five seams and
  instrumentation is not one, so the item is post-v1 and not UNSCHEDULED. Its first and only sanctioned
  user is the post-v1 `dexpace-instrumentation-otel` gem, below. **The restriction travels with this
  entry: no transport or
  codec adapter may ever use it** — for a transport or a codec, "whatever happens to be installed silently
  wins" is the auditability failure `SEAM-5`'s loud-failure branches exist to prevent, whereas for
  instrumentation the worst outcome of guessing wrong is a span that is or is not emitted. Trigger:
  that gem. No ⏳ row carries it — it names a mechanism, not a requirement of its own; phase 2's absence
  test is the artefact.
- **An `apiKey` credential carried in a query parameter or a cookie has no AUTH-step path —
  `AUTH-26` (MUST, satisfied as written), `AUTH-1`, `AUTH-8`, `AUTH-28`, `AUTH-29`.** Added 2026-09-13
  by phase 6c's final review. `AUTH-26` is explicit and header-only — "static key-credential stamping
  MUST write the key value into the credential's configured **header**" — and no `AUTH` requirement
  names a query or cookie carrier, so `6c` implements the requirement in full and the gap is in the
  specification's scope rather than in the port. It matters because OpenAPI's `apiKey` scheme admits
  `in: header | query | cookie`, and a generated SDK targeting a query-keyed API can still send the
  credential — it builds the query itself, at the operation layer — but in doing so it gets **none** of
  what the AUTH step exists for on that credential: no `AUTH-28` HTTPS guard before the value is
  attached, no `AUTH-29` cross-origin suppression (a query parameter survives a redirect re-issue on
  which `REDIR-7` would have stripped a header), and no `AUTH-8` redaction in diagnostics. That makes
  it a release decision with a security consequence rather than a missing convenience. No ⏳ row
  carries it, because no requirement is declined. The event that would reopen it is **the first
  consumer that needs one — a worked example in `docs/sdk-documentation/`, a `dexpace-conformance`
  fixture, or a downstream SDK's `SEAM-26` operation projection carrying a non-header `apiKey`**;
  widening `AUTH-26`'s carrier is a specification change and belongs to whoever makes it, not to a
  phase. Until then the release notes state that query- and cookie-carried API keys are outside the
  AUTH layer and what the consumer loses by placing one there

### Behavioural asymmetries a consumer must know

Not declined requirements and not gaps: places where v1 satisfies its requirements and the resulting
behaviour still differs between two paths a consumer may reasonably expect to match. **The release notes
MUST state every item here**, for the same reason the section above is stated.

- **The async standard pipeline follows no redirects — `PIPE-32`, `REDIR-25` (MUST).** Added
  2026-09-13 by the roadmap-level generator-fitness review. `Pipeline.standard` installs redirect, retry
  and instrumentation; `AsyncPipeline.standard` requires `redirect: :unsupported` as a **required**
  keyword and installs no step at `Stages::REDIRECT` — as built by phase 6b's Task 13a on 2026-09-19,
  the constructors phase 4c postponed, exactly in this shape. That is the requirement, not a shortfall —
  `PIPE-32` forbids pipeline-layer redirect following on the async path — and `PIPE-32`'s own last
  clause, "a port MUST document this asymmetry with the sync standard pipeline", is discharged in phase
  4c's design, in the YARD on `Dexpace::AsyncPipeline` and in `docs/sdk-documentation/redirect.md`. What
  that does not reach is a **consumer**: a generated client exposing a sync and an async method for one
  operation ships two behaviours on a 301/302, and the reader who needs to know types neither constant.
  So the release notes state it, and `docs/sdk-documentation/` states it beside the worked example the
  blocker above owes.

- **The HTTP-tracer vocabulary has no wired emitter for two of its three groups — `OBS-28`, `OBS-29`
  (MUST), `CTX-14`, `CTX-20`.** Added 2026-09-13 by phase 10's design, which closed this as a decision
  rather than carrying it as an open surface question. **This is conforming, and `OBS-29`'s own text is
  why:** its canonical row in appendix C ends "This is a documented emission contract;
  pipeline/transport wiring to emit it is a follow-up, so it is not yet runtime-enforced." Phase 5c
  ships the eleven-method vocabulary, the shared no-op and the ordering test; phase 6a emits the
  **per-attempt** group through `http_tracer_factory:` called with `cursor`. The
  **operation-lifecycle triple** and the **transport-milestone group** are emitted by nothing in v1,
  because the first would need a new step at `Stages::PRE_REDIRECT` — `Stages::LOGGING` is order 1100
  and would fire once per redirect hop, per retry attempt and per auth replay, contradicting the 1:1
  clause — and the second would need a widening of `RequestOptions`, a core type whose members are
  `(:timeout, :max_retries, :tags)`, since the transport seam is `#call(request, options, cancellation)`
  and `PIPE-11` forbids ambient carriage. Both were declined on the `Event#tag` precedent: `NFR-4` locks
  a public surface at the first tag, `OBS-28`'s "Every event method SHOULD default to a no-op" makes an
  unwired group conforming, and adding a keyword later widens while removing one breaks. **What a
  consumer needs to know**: an SDK author who installs an `HTTPTracer` sees the per-attempt events and
  not the operation-lifecycle or transport ones, and the contract those follow is documented rather than
  emitted. **The second thing the release notes must state** is that "per-operation tracer factory"
  names two objects and not one: `CTX-14`'s, on the correlation bundle, produces **span** tracers
  (`OBS-21`–`OBS-25`) and is legitimately shared — `OBS-25` requires a no-op factory that "MUST NOT
  allocate per call", so it returns the same object every time — while `OBS-29`'s produces
  **HTTP-tracers** and is legitimately per operation. Appendix C, design §8.1, phase 5c's Tasks 3–5 and
  phase 4a's `R3` all read them as one object; phase 10's plan, Task 16 states the distinction in both
  YARD blocks and in `docs/knowledge/notes/observability.md`.

- **The correlation chain is driven by the SDK author, not by the pipeline — `CTX-16` (SHOULD),
  `CTX-14`, `SEAM-28` (MAY).** Added 2026-09-13 by phase 10's design. **No phase in the roadmap builds
  a call path that creates or promotes an execution context**: verified by repository-wide grep over
  `docs/work/mvp/`, `DispatchContext`, `promote_to_request` and `promote_to_exchange` appear in no phase
  plan outside phase 4a's own documents; phase 5b's `Instrumentation::Step`, as built, probes nothing
  and names its span by the request's method token, because `Dexpace::Request`'s members are
  `(:method, :url, :headers, :body)` and no context is reachable from a step (5b's as-built row P5-99);
  and phase 6a's Task 8 seeds a `Cursor#bundle`, which carries no operation name. **This too is conforming**, and by `CTX-16`'s own modal clauses: the context carries
  the name, the name is carried forward unchanged across every promotion, and it influences neither the
  request nor the dispatch decision nor the store key. "It is exposed to the tracing seam to label the
  operation" is descriptive, not modal, and §11.11's rule for a SHOULD with embedded MUSTs applies —
  the port ships the feature, so it implements every embedded MUST. `SEAM-28`, the ID that would oblige
  a carrier, is a **MAY** and is deferred in §12. An `operation_name:` keyword on `Pipeline#call` was
  considered and declined on the same `NFR-4` grounds as the tracer wiring above; `api-design/1d9e6e0b`
  is what makes adding it later cheap. **What a consumer needs to know**: a generated client gets a
  correlation model it must construct and promote itself, and the worked end-to-end example the blocker
  above owes is where that is shown — phase 10's plan, Task 18 adds the correlation chain to that line's
  enumeration. **The recorded consequence**: `ContextStore`'s cap, `CTX-19`'s reachability and `CTX-9`'s
  eviction are exercised only by phase 4a's own tests in v1.

- **Port readings phase 10 left standing, each measured 2026-09-25 and each a behaviour a consumer can
  meet -- `HTTP-51`, `HTTP-12`, `SSE-11`, `IO-1`.** Added by phase 10, the last phase, which decided not
  to change them and has nowhere else to put them. *(a)* **A multipart part name or filename must be
  ASCII**: `MultipartBody`'s part-header sweep is the outbound header grammar, so `"résumé.pdf"` raises
  `InvalidArgumentError` at write time and the caller percent-encodes first (RFC 7578 §4.2's own advice;
  browsers send raw UTF-8). Widening the sweep to obs-text is additive and cannot break `NFR-4`; the
  trigger is the first consumer that needs a raw UTF-8 filename. *(b)* **`Query.parse` drops a trailing
  NUL** (`"a=b\0"` parses as `"a=b"`), phase 1's review R3-3 -- an HTTP-grammar reading, not a crash;
  trigger: a server whose query semantics depend on it. *(c)* **A zero-padded `retry:` field longer than
  ten digits is ignored** -- `00000000005` leaves the hint unset where `0000000005` sets 5 -- by the reader's ten-digit width bound (7b's
  review R1-2) -- `SSE-11`'s documented cap, read strictly. *(d)* **After a mid-stream failure,
  `BufferedSource.over`'s enumerator restarts `#each`** (7b's finding): a caller that rescues and reads on
  re-reads the body's first bytes. The SSE facade closes itself first and never meets it; latching
  exhaustion on a failure is the one-line alternative, recorded as the pick-up if a consumer reads past
  a failure. The release notes state all four.

### Post-v1 gems

Design §2.2 is the authority, and the roadmap's "Post-v1" paragraph already states the rule: these seven
are **entries here, not phases**. The line is not usefulness but what would be unproven without it —
a seam ships in the MVP with at least one adapter exercising the property the seam exists for, and a
second adapter over an already-proven property waits. Each entry names its trigger, as the MVP scope
design of 2026-09-05 stated it.

- **`dexpace-async-async`**, bridging the core async pivot to `Async::Task`. Trigger: a
  reactor-native async adapter is needed beyond the thread-pool-backed `dexpace-async-thread`, which is
  the adapter that proves the pivot. `SEAM-24`'s cancellation bridge (above) rides on it; the `XCUT-12`
  fiber-scheduler trigger that once did too was closed on 2026-09-25 by phase 10's fiber verification
  (under Post-release triggers, below).
- **`dexpace-async-concurrent_ruby`**, bridging the pivot to `Concurrent::Promises::Future`.
  Trigger: `concurrent-ruby` interop is needed beyond `dexpace-async-thread`.
- **`dexpace-transport-httpx`**, HTTP/2 without a reactor; a third transport over properties
  the MVP's two already prove. Trigger: HTTP/2 support is needed without adopting a reactor.
- **`dexpace-transport-excon`.** Trigger: `excon` interop is requested.
- **`dexpace-transport-typhoeus`.** Trigger: `typhoeus` interop is requested.
- **`dexpace-serde-oj`**, a faster codec over a seam `dexpace-serde-json` already proves with
  the reference wire codec. Phase 7a's design (2026-09-10) added a second motive beyond throughput, which
  `7a P7-1` makes visible (phase 7's three sub-phases knowingly share `P7-<n>` numbers until
  consolidation into design §10, so a phase-7 row is cited with its sub-phase letter): `oj` has a genuine streaming parser, so an `oj` adapter would satisfy `SERDE-27`'s
  "without first materializing the whole body" clause that `dexpace-serde-json` measurably cannot at its
  gemspec floor — a new property, not merely a faster codec (cites `SERDE-27`, `SEAM-21`, `IO-9`). That
  does not change the trigger, since throughput is still what a user will feel first, but it changes what
  the gem is worth. Trigger: JSON throughput is identified as a bottleneck the stdlib `json` gem cannot
  meet.
- **`dexpace-instrumentation-otel`.** The §8.1 instrumentation seam is duck-typed and already
  accepts an OpenTelemetry object with no adapter, so the gem is packaging convenience, not a new
  property. Trigger: a first-class OTel integration — helpers, defaults or bundled wiring — is worth
  shipping as its own gem. `OBS-32`/`OBS-37` and presence-gated auto-activation's only sanctioned user
  (both above) ride on it.

## Release path

Not yet defined. `NFR-16`'s signing requirement is enforced on the release path only once that
path exists (see `docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md`, NFR row); until
then there is no path to enforce it on.

Two items recorded here on 2026-09-13 because they belong to the release and to no phase:

- **Signed publication and the release half of `NFR-12` — `NFR-16`.** `NFR-16` asks for cryptographically
  signed artifacts with signing enforced on the release/CI path and gracefully optional locally; a signing
  step wired to a path that does not exist would be a gate over nothing, which is the failure mode phase 0
  was built to avoid. Phase 0 did build `gates:reproducible`, so `NFR-12`'s **build** half is satisfied;
  its **release** half — a published artifact byte-identical to a rebuild from its tag — waits with the
  rest of the path. Its condition is two blockers already listed above: RubyGems ownership settled and
  trusted publishing configured.
- **`PackagingSuite`'s `NFR-12` and `NFR-16` assertions against a published artifact.** Phase 9
  writes neither — no task in its plan writes an `NFR-12` or `NFR-16` assertion — so both are written at
  the first `v*` tag and the first `gem push`, alongside the signing step above. `NFR-15` is **not** in
  this entry: phase
  9's Task 9 asserts it against a locally built `.gem`, comparing the loaded `VERSION` to the resolved
  gemspec. `NFR-12`'s cross-toolchain half stays out of scope by phase 0's `P0-7`, which reads the
  requirement as byte-identity for one gem built twice on one interpreter.

### After the first publish

- **The fence executor for `.claude/skills/housekeeping/`.** The Node original's ninth
  housekeeping tool, `check-fences.mjs`, extracts every fenced TypeScript example that imports from the
  workspace and typechecks it against built declaration files; Ruby has no build step to hang that on, so
  the analogue is not a typechecker but an **executor** — extract every ```ruby fence that `require`s a
  `dexpace-*` gem, run it under `ruby -w` with that gem's `lib/` on `$LOAD_PATH` and a stubbed transport,
  and assert it exits 0 with no warnings. It needs published gems to point at (the SKILL.md note this
  entry was drawn from), so it waits for them; closable by no phase.

## Post-release triggers

Recorded here on 2026-09-13, when the deferral register was retired: every postponed item now lives
either in the plan task that will do it or in this file. Each entry names an **event** no v1 phase can
produce, recorded so a later reader does not mistake an unmet condition for a forgotten one. For each:
the trigger, then the one job to do when it fires.

- **A Steep target over a `test/` tree — a gem's `test/` tree becomes production-quality code worth
  checking** → add a Steep target
  over it. `8a` and phase 9 both place `dexpace-conformance`'s assertion objects and fixtures under `lib/`,
  where phase 0's per-gem target already checks them as production code, so the trigger is genuinely a
  `test/` tree and not the conformance gem.
- **`IO-38` on a Ruby without a GVL — a non-CRuby row enters the CI matrix** → run `gems/dexpace-core`'s
  `IO` suite unchanged
  and confirm the cross-thread close test (`IO-38`) still passes. On every CRuby row the GVL hides a
  missing lock, so the test proves the behaviour and not the `Thread::Mutex` mechanism design §3.1 fixes
  for JRuby and TruffleRuby. **The same row is what proves `ContextStore`'s drain, added here 2026-09-13**
  (found 2026-09-08 by phase 4a's plan review): `CTX-7`'s "registered, overwritten, and removed concurrently
  without external locking" and `CTX-8`'s "deterministically admit exactly one winner" both rest on
  `BoundedMap`'s one-`synchronize` insert-and-drain, and **no test holds it** — the discriminating
  measurement, "the maximum size ever observed", is unreachable from the public surface, because
  `ContextStore#size` delegates to `BoundedMap#size`, which takes the same `Thread::Mutex` as the insert, so a
  reader can never observe the transient `cap + 1`. Measured: a split-lock `BoundedMap`, acquiring the mutex
  separately for the insert and for the drain, sampled by four concurrent `#size` readers across 64 000
  inserts from 32 threads at `cap` 8, reported a maximum of **exactly 8 on six consecutive runs**, identical
  to six runs of the shipped one-`synchronize` form; the corpus note's own `9`-at-`cap`-8 observation was
  taken from **inside** the prototype's hash, which no test written against the public surface can reach.
  Phase 4a's plan ships the other discriminating measurement, "the maximum iterations in any one call", in its
  observable form. So narrowing that lock's scope is invisible to the suite on CRuby, exactly as a missing
  lock is for `IO-38`: when this trigger fires, add the `CTX-7`/`CTX-8` drain assertion beside it. The
  alternative repair — an internal probe seam on `BoundedMap` a test can read without the mutex — is a
  `private_constant`'s test surface phase 2 declined for `Dexpace::Hooks`, and would need the same argument
  made deliberately.
- **The require-allowlist regeneration guard — a new Ruby minor version enters the CI matrix** →
  re-derive the require-allowlist's name
  list on the new interpreter and diff it against the committed allowlist. This is `NFR-9`'s content that
  §10.19's retarget does not cover: the allowlist audit and the clean-bundle run check that today's list
  holds, not that it is still the right list.
- **Minitest 6 — no fence in the repository requires `minitest/mock`** → lift the root `Gemfile`'s `minitest`
  pin. Recorded 2026-09-13; found 2026-09-12 by phase 9's design. Phase 0's Task 2 pins `minitest` to
  `~> 5.25` — a **development** dependency, so the zero-runtime-dependency rule is untouched — because
  Minitest is a different major at the top of the supported range and the version there has removed
  `minitest/mock`. Measured on all three installed interpreters: `minitest 5.25.1` on **3.2.11**, `5.25.4` on
  **3.4.10** and **`6.0.0` on 4.0.6**, with
  `Gem::Specification.find_by_name("minitest").default_gem?` `false` on every one. On 5.25.x the gem ships
  `minitest/mock.rb`; **on 6.0.0 it does not** — `require "minitest/mock"` raises `LoadError` on 4.0.6, and
  that gem's `lib/` listing has neither `minitest/mock.rb` nor `minitest/unit.rb`, while `assertions.rb`,
  `test.rb`, `autorun.rb`, `spec.rb` and `benchmark.rb` all remain. Every assertion name this repository uses
  survives: 22 were checked, from `assert_equal` to `assert_in_delta`, and all 22 are still defined on
  `Minitest::Assertions` in 6.0.0. What disappears is `Minitest::Mock` and `Object#stub` — which **phase 8a's
  plan used twice** (`Dexpace::Conformance::TransportSuite.stub(:assertions, assertions)`, in its driver test
  and again in its `test/` fence) and which two corpus rules name (`testing/e27df4c7`, `testing/70473c9d`).
  *Narrowed 2026-09-20 at 8a's execution*: the built suites use **no** `.stub` anywhere — `TransportSuite.run`
  takes an `assertions:` keyword and the drivers' tests hand in a plain object answering `#assertions` — so
  the `stub` half of the pin's first reason is gone; the second reason below stands on its own.
  The pin keeps the same framework major and a working `stub` on every matrix row, at the cost of the 4.0 row
  not exercising the Minitest its interpreter ships; without it that row runs **red**, which would falsify the
  standing blocker above — the `dexpace-conformance` suite passing across 3.2 through 4.0 — and is exactly the
  trap §9.2's "run the real suite on each Ruby" argument exists for, since `TargetRubyVersion` catches syntax
  and not library availability. The job when this fires: drop the pin, and re-check that no fence requires
  `minitest/mock`.
  **Measurement corrected 2026-09-13 by phase 10's design, and the pin's reason widens with it.** Re-run on
  all four installed interpreters: `Gem::Specification.find_by_name("minitest").version` is **5.25.1** on
  3.2.11, **5.20.0** on 3.3.12, **6.0.6** on 3.4.10 and **6.0.0** on 4.0.6, with `default_gem?` `false` on
  every one — so the bundled-gem half of the record holds, and two of the three versions above it are now
  stale. What changed is not an interpreter: **6.0.6 is installed in the user gem directory on the 3.4 row**,
  beside the 5.25.4 that interpreter ships, and a bare `require "minitest"` resolves the newest rather than
  the shipped one. So the 3.4 row is affected too, and differently from the 4.0 row: `require "minitest/mock"`
  followed by `require "minitest/autorun"` there loads **both copies** and emits **13 `already initialized
  constant` warnings**, which `NFR-6`'s `Warning.warn`-raising gate turns into a failure — not a `LoadError`
  but a red row all the same. `require "minitest/mock"` still raises `LoadError` on 4.0.6 and `Object#stub`
  is still absent there. **The pin is therefore load-bearing for a second reason**: it is not only what keeps
  `Object#stub` available at the top of the range, it is what makes the 3.4 row deterministic at all, and the
  mechanism is newest-wins resolution outside Bundler rather than anything about the interpreter — which is
  also the sharpest available argument for `bundle exec`. The pin's owner does not change: phase 0's plan,
  Task 2. Phase 10's plan, Task 1 re-measures both facts at implementation time, because a fact that moved
  once in a day will move again, and its Task 18 carries the numbers here if they have.
  **Measurement corrected again 2026-09-25 by phase 10's execution, outside the bundle (`RUBYOPT` and
  `BUNDLE_*` cleared, the stock interpreters):** `Gem::Specification.find_all_by_name("minitest")` is
  5.27.0 and 5.25.1 on 3.2.11, 5.20.0 on 3.3.12, 6.0.6 and 5.25.4 on 3.4.10, 6.0.0 and 5.27.0 on 4.0.6 --
  a 5.x copy now sits beside the 6.x one on BOTH top rows, installed on this machine since the last
  measurement -- and **`require "minitest/mock"` now succeeds on all four** (it activates 5.27.0 / 5.20.0 /
  5.25.4 / 5.27.0, the newest copy that ships the file). So the 2026-09-13 sentence "still raises
  `LoadError` on 4.0.6" is no longer true on this machine, and it was never a fact about the
  interpreter: what a bare `require` resolves depends on what happens to be installed beside it. The
  pin's reason stands and is sharper for it -- the bundle, pinned `~> 5.25`, is the only resolution that
  is the same on every row. None of this is asserted in a committed test, deliberately: it is machine
  state, not interpreter behaviour.
- **Lifting appendix `B.1`, `B.2` and `B.5` — a second implementation of the pagination engine, the SSE
  reader or the configuration chain exists** → lift their assertions into `dexpace-conformance`. Until
  then a lifted assertion over a single subject is a test with one subject living in a package whose
  purpose is many; phase 9's 61-row `APPENDIX_B.md` map, dispositioning the 22 items by reference
  (`P9-1`), stands and is phase 9's.
- **`gates:drain_loop`, the `XCUT-14` drain-shape scan — a non-conforming drain shape appears that the
  deterministic assertion cannot reach** → write the AST gate phase 9 planned and then dropped. Recorded
  2026-09-13; decided during phase 9's final review. `XCUT-14` (MUST) requires eviction "using a loop (not
  a single pre-insert check-then-evict)", and phase 9 ships that clause as a **behavioural** assertion —
  `InvariantSuite`'s `bounded_map_drains` (its plan, Task 7) pre-fills a store to cap + 5, performs one
  `set`, and observes a drain loop ending at 8 against a check-then-evict ending at 13, deterministically
  on 3.2.11, 3.3.12, 3.4.10 and 4.0.6. The shape gate that would have sat beside it measured **1 of 3
  non-conforming shapes caught, with one false positive** (a `loop do … break … end` drain) and misses a
  file whose `set` checks-then-evicts while `put` loops. A second line weaker than the first is a
  maintenance cost carrying no evidence, so it is out of v1 and phase 9 ships **three** repository gates
  rather than four. What fires this: a drain implementation whose non-conformance the cap-and-drain
  observation cannot see — a second eviction path, or an eviction reached only on a branch the
  behavioural test does not drive. Touches `XCUT-14`, `NFR-17`.
- ~~**`XCUT-12` under a fiber scheduler, the fallback — the post-v1 `dexpace-async-async` reactor-native
  adapter (above) ships**~~ — **CLOSED 2026-09-25 by phase 10**: the fiber-scheduler form is asserted in
  `gems/dexpace-transport-async_http/test/dexpace/transport/async_http/fiber_single_flight_test.rb`, eight
  fibers of one reactor on one thread against the real `Auth::BearerStamper` and `AsyncBearerStamper`,
  exactly one fetch, run red against a single-flight guard keyed by thread identity (phase 10's checklist,
  Guards run red 19). The judgement this entry waited on was made -- as a VERIFICATION rather than the
  repair the 2026-09-13 annotation below expected: the deadlock that annotation predicts does not happen
  (a fiber blocking on a `Thread::Mutex` another fiber holds parks on the scheduler), so the shipped code
  was already single-flight under a reactor, and what the fiber form catches that the thread form cannot
  is a guard keyed by thread identity (phase 10's `P10-21`). The entry is kept, struck, as the record:
  ~~→ run `XCUT-12`'s single-flight assertion under a fiber scheduler, driving
  `6c`'s bearer or digest cache through a reactor via the suite contract's clause 9 `around:` wrapper. The
  primary disposition is phase 10's, on whose inbound list it sits (the roadmap's 2026-09-13 status
  note): judge whether the thread-only form phase 9 ships (Tasks 7–8) suffices, a judgement phase 9 may
  not make (`P9-6`). This trigger is what fires if phase 10 leaves that judgement open, because the
  reactor adapter is the first artifact that makes a second fiber-scheduler subject available.
  **Annotated 2026-09-13 by phase 10's design, which does not leave it open: the thread-only form is
  judged insufficient and phase 10's plan, Task 9 ships the fiber form**, as a driver in
  `gems/dexpace-transport-async_http/test/` running `InvariantSuite`'s `XCUT-12` assertions through the
  suite contract's clause 9 `around:` wrapper (`->(&blk) { Sync { blk.call } }`) against `6c`'s bearer
  cache. The reason is one of `CLAUDE.md`'s constraints that will bite: `Thread::Mutex` ownership is
  per-fiber and non-reentrant, a single-flight guard is a lock held across a fetch, a fetch under a
  reactor is a suspension point, and a thread-only race cannot observe the deadlock that combination
  creates. Phase 9's blocker was composition and not difficulty — `dexpace-conformance` declares
  `dexpace-core` and nothing else, so it cannot open a reactor — and neither that nor `R6`'s file list
  binds a phase that owns every gem; the driver costs no dependency, because that gem already declares
  `async-http` and 8a's own precedent is a driver file inside the adapter gem. **This entry closes when
  Task 9 lands**, and phase 10's Task 18 removes it then rather than leaving a trigger armed against an
  event that no longer means anything. It stays here until the fiber run is recorded, because a decision
  in a plan is not evidence the work was done. Runs on **3.3.12, 3.4.10 and 4.0.6 only**: `async`,
  `async-http`, `io-event` and `protocol-http1` all declare `required_ruby_version >= 3.3`, re-verified
  2026-09-13, which is `P8-36` from the other side.~~

- **A second continued-clause true positive for the probe's chapter-attribution check — one appears that
  the check cannot see** → write the sentence-spanning form. Recorded 2026-09-13 by phase 10's design.
  The check is clause-scoped: it splits a line at `;`, pairs each requirement ID with the nearest
  preceding `docs/product-spec/` reference, expands a range whether or not its endpoints are backticked,
  and skips a clause whose two-line window carries a negation. Measured over every `*.md` under `docs/`:
  **38 lines name both a chapter and a canonical ID; a naive same-line rule fires on 14 lines / 23
  (chapter, ID) pairs with 4 true positives; the clause-scoped form fires 3 times with 3 true positives
  and 0 false positives.** Those four numbers are **convention-dependent** — they are what the check's
  own chapter-reference and ID patterns see — and they were taken before phase 10's two documents joined
  the population; a wider regex counting any `docs/product-spec/` path beside any canonical ID reads 47
  lines today, 36 of them outside phase 10's own two files. What must not move is the **0 false
  positives**, which is why the ratio and not the population is what this trigger is written against.
  Its one **unclosed** blind spot is a clause whose chapter reference sits on
  the preceding line — `phase8c-…-design.md:70`'s `SEAM-15` is the live instance, found by hand and not
  by the check — and closing it needs a sentence-spanning parser over Markdown, which 3 fires at 0 false
  positives does not justify. The gap is printed in the check's own output, so a reader is never told it
  saw something it did not. **What fires this**: a second such instance. One is an anecdote; two are a
  population. Touches the requirement-ID conventions, `NFR-17`. **Built and re-measured 2026-09-25 by
  phase 10** (`.claude/skills/housekeeping/chapters.rb`, the probe's ninth check): over the live tree
  the clause-scoped form fired twice, both true positives -- `SEAM-13` and `SEAM-15` inside a
  backticked range the phase-8 segmentation design attributed to chapter 03, fixed in place -- and zero
  false positives once the negation vocabulary was written as a union of phrases (an `/x` pattern had
  silently deleted the phrases' spaces). Review round 0 (R0-8) found `appears in` listed as a negation,
  which silenced the usual positive attribution; it is now a forward binding (the IDs before it pair with
  the chapter after it), and the live count is unchanged. The continued-clause blind spot is `Chapters::GAPS` and is
  asserted by `chapters_test.rb`; it still has one known instance, and this trigger still waits for a
  second.

- **Residues phase 10 measured and did not repair, each with the event that makes it worth doing**
  (added 2026-09-25; phase 10 is the last phase and none of these has a phase to go to). *The process
  tooling outside RuboCop* -- `scripts/**` and `.claude/**` are excluded in `.rubocop.yml` (P0-11,
  `NFR-7`'s one documented exception); phase 10's file list did not reach `.rubocop.yml` or `scripts/`
  → when either tree is next changed for its own reasons, run the autocorrect pass and delete the two
  `Exclude` lines. *The per-byte `#getbyte` cost* -- about 0.9 µs a byte through `BufferedSource#getbyte`,
  so the SSE line machine parses about 1 MiB/s (7b's baseline) → a consumer streaming SSE at that rate.
  *`Fiber[:"dexpace.current_span"]` left set on the main fiber across suites* under the one-process
  `rake test:gems` (8b) → the next suite that reads the main fiber's storage raw. *The portable
  `TRANSPORT-7` row's race* against a streaming adapter (8c's review R1-1) → the next change to
  `dexpace-conformance`'s transport suite. *`XCUT-9`'s two stated residues* (a collect-then-yield walk
  and a depth cap equal to the cycle length pass the black-box assertion; `gates:cause_walk` is the
  second line) → a second cause walk proposed anywhere. *7a's `SEAM-21` evidence living inside another
  assertion's body*, declared in no ID-keyed map → the next change to `dexpace-serde-json`'s suite.
  *`tools/surface.rb` blind to a `private_constant`* (it walks `Module#constants(false)`) → a private
  group module made public. *The 3.4+ unused-block warning `test:gems` cannot see* (suppressed
  process-wide once a same-named block-taking method is compiled; `-W:strict_unused_block` would reach
  it) → a new sink or callback method declared without `&`. *Two spellings of the bare-require child
  process* (`seam_surface_test.rb`'s helper and `test/support/bare_require.rb`) → the next bare-require
  pin written. *6a's async pump close-before-schedule order* unpinned (an equivalent mutation) → a change
  to `AsyncRetryStep`'s pump. *Phase 3a's three `untyped` signature parameters and `TeeSink`'s Float
  `tap_limit` refusal*, and 7c's non-`Response` duck never closed after a parse → the next change to
  those files. *The six gate tests that resolve `ruby`/`bundle` from PATH, the category assertion run
  once, the third-party sub-feature refusal* (phase 0's review R3-4/R3-6/R3-7) → the next gate added.
  *The probe's `claims` check does not read `CLAUDE.md`'s spelled-out `lib/` file counts* ("two hundred
  and twenty … files", 5c's leftover) -- phase 10 counted its own `CLAUDE.md` edit by hand → the next
  change to `.claude/skills/housekeeping/probe.rb`'s `claims` check, or the first time a spelled count
  drifts unnoticed. *`docs/sdk-documentation/sse.md`'s `#with` sentence and the fence names it leaves
  undefined* (7b's review R1-1), not re-measured by phase 10 → the next edit to that page, when the
  fences are run and the sentence checked against `Dexpace::SSE::Event#with`.
  *Phase 9's aggregate run is a hand run*: no committed test calls `Aggregate.run` over the four suites
  with real subjects, so the 43/1/0/1/0 verdict was not re-run as one report by phase 10 (each suite's
  driver ran in `rake test:gems`) → the first release's conformance run. *8c's two stale design facts and
  `async-http`'s server letting a peer's mid-head `EOFError` reach Console* → an upstream report.
