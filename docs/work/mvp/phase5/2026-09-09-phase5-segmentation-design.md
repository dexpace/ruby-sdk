# Phase 5 — Segmentation Design

**Status:** Draft, for review. Written 2026-09-09, before any phase-5 sub-phase design exists.

**What this document is.** The segmentation design the roadmap's **Segmentation rule** requires of a build
phase that spans more than one ID-bearing spec chapter. It decides how many ways phase 5 is cut and in what
order, says for each boundary whether that order is a **dependency** or a **convenience**, assigns every
requirement ID to exactly one sub-phase, and names the boundaries that are spec-forced and therefore not open
to the sub-phase designs to revisit.

**What this document is not.** It is not a phase design, a plan or a checklist, and it names no numbered task
and writes no code. Where it names a decision as belonging to a sub-phase it stops there deliberately; a
segmentation design that settles the sub-phases' content is the same failure as a sub-phase plan that
re-imposes a chain the split existed to avoid, arriving from the other direction.

**The headline, stated once at the top because everything else depends on it.** Phase 5's stated scope is
`CFG-1`–`CFG-38` and `OBS-1`–`OBS-40`, 78 IDs, and the arithmetic is exactly right. **The cut is three ways,
not two** — `5a` configuration and the clock, `5b` the logging facade and redaction, `5c` tracing and metrics
— and **every boundary is a convenience**. The roadmap's expectation of two ways along the §15/§16 line is
adopted as one of the two boundaries and rejected as the whole cut; its stated reason for the *order* is
rejected outright. The roadmap says "the order is a real, if soft, dependency: `OBS-35`'s log-level resolution
wants `CFG`'s layered lookup … so 5a leads deliberately." `OBS-35` is a **SHOULD**, and the edge it names is
not the only one: `CFG-24` and `CFG-25` require proxy resolution to yield null "**with a warning**" and
`CFG-21`'s best-effort close is `DEF-27`'s second disposal route, both of which need §8.1's facade — so the
`CFG`↔`OBS` edges run **in both directions** and neither chapter leads the other. Phase 5 is the first phase
in the roadmap whose two chapters each supply the other, and that fact is what the cut is built on rather than
worked around.

Phase 5 adds **no fourth unsatisfied MUST**. It does meet a fourth clause of §8.3's prohibition — `CFG-20`'s
cancel-with-interrupt is `ASYNC-3`'s two-mode requirement under a second ID at SHOULD level — and no register
row currently cites `CFG-20`. That is filed as `OI-22`.

## Governing documents

- `docs/product-spec/16-configuration.md` and `docs/product-spec/15-instrumentation-and-observability.md` —
  normative, read in full for this document, together with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` for the canonical text of all 78
  IDs. Unlike phases 2, 3 and 4, appendix C is a convenience here and not a necessity: every one of the 78
  appears in its own prose chapter (verified below).
- `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` in full — §8.1 (the event object, the
  duck-typed sink, tracing, the correlation bundle, the diagnostic context, redaction), §8.2 (the four-tier
  chain, the typed accessors, the proxy model, dates, identifiers, deep equality) and §8.3 (the clock, the
  wait, the prohibition);
  `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items 4, 5, 16, 17 and 18;
  `docs/sdk-design-ruby/11-appendix-reference-spec-ambiguities-and-how-this-port-resolves-them.md` items 1, 4,
  11 and 15; and §12's `CFG` and `OBS` rows.
- `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` — the phase-5 row, the segmentation rule's phase-5
  bullet, the gap-ID paragraph, the five cross-phase obligations and the nine cross-cutting constraints.
- `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md` and the three phase-4 sub-phase designs —
  in particular each one's *interface surface later phases may cite* table, every one of which carries
  explicit phase-5 rows. `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` for the async
  pivot and `SEAM-28`; `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md` for the
  require allowlist and the denylist; `docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md` as the
  second worked example of this document's form.
- `docs/deferred-items.md`, `docs/open-items.md`, `docs/deviations.md`, `docs/first-release.md`.
- `CLAUDE.md` and `docs/README.md`.

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run first. `ruby scripts/knowledge.rb --origin note
--brief` returns **36 entries across 18 note files**; `--section conflicts --brief` returns **24 entries
across 17 topic files, 18 of them notes and six harvested** — the six harvested ones being the
styleguide-versus-design conflicts themselves, and each prints `[overridden by notes/…]` when resolved by key
(`data-modeling/35fde90f`, `module-organization/bf6411ad`, `package-and-dependency-layout/41b154a3` and
`/8c0687bf`, `tooling-and-quality-gates/86d763f1`, `type-system/93dc79aa`). **None is open**, so phase 5
inherits no unresolved conflict and owns no conflict decision of its own.

Five note entries bind this phase directly and are cited rather than restated:

- `observability/e0f1e864`'s superseding note in `docs/knowledge/notes/observability.md` — fiber storage is
  the diagnostic-context carrier across the whole supported range, its inheritance is **copy-on-write**, and
  it is **not** where `CTX`'s execution context lives. That note was filed by phase 4 for phase 5's benefit
  and is the boundary `5b` and `5c` work inside. It also names `OI-13` for the write side.
- `concurrency-and-async/f414b864` — core's shared mutable state is one frozen `Data` snapshot swapped under
  a `Thread::Mutex`, read without a lock; `Mutex` is per-fiber-owned and non-reentrant. This is exactly the
  shape §8.2 gives `Dexpace.configure`'s process-wide slot (`CFG-8`, `CFG-13`) and §8.1 gives `OBS-8`'s
  emit-once latch.
- `resource-management/d1f16cad` — the styleguide's per-call I/O timeout rules do not reach the streaming
  layer. They do not reach phase 5's clock either, and for a second reason: §8.3 forbids `Timeout.timeout`
  outright and `CFG-15`'s wait is a cancellable queue wait, not a timeout.
- `type-system/545949a5` — closed domain sets are frozen `Data` value types over a frozen table with a
  `parse`/`of` factory, never a `T::Enum`. `OBS-2`'s four severities and `OBS-34`'s three logging levels are
  both closed sets and both take that shape; `TraceIdFlavour` already does (phase 4a).
- `assertions/e8c05720` — the production assertion primitive is the domain model's own validation helper with
  the one message form `<name> is required`. `CFG-37`'s fail-fast argument guards and `OBS-3`'s empty-key
  rejection both route through it rather than inventing a second failure vocabulary.

**Corpus coverage.** `--prefix-info CFG` reports **38 of 38 substantive, 0 roll-up only, 0 uncited**;
`--prefix-info OBS` reports **40 of 40 substantive, 0 roll-up only, 0 uncited**. Phase 5 has the best corpus
coverage of any build phase so far.

**The appendix-B roll-up hazard fires here, and it fires on every single ID.** This is the exact inverse of
phase 4, whose segmentation design could report that "not one `--req` hit across the three prefixes is tagged
`[appendix-B roll-up]`". Verified 2026-09-09 by extracting the ID lists from every roll-up-tagged entry under
both prefixes: **all 38 `CFG` IDs and all 40 `OBS` IDs appear in at least one entry tagged
`[appendix-B roll-up]`**, 36 such entries under `configuration` and 40 under `observability`. That is appendix
B working as designed — `CFG` and `OBS` are two of the nine prefixes appendix B covers (§11.9) and its
checklist rolls eight IDs into one line — but it means **a sub-phase designer running `--req` on any phase-5
ID gets roll-up hits mixed with substantive ones on every query**, and the `knowledge-lookup` skill's
three-step roll-up path is not an occasional detour here but the normal reading mode. `--prefix-info`'s "0
roll-up only" is the reassurance that the substantive entry always exists beside them; it is not a licence to
read the roll-up as the answer.

**One audit group was run in full, and it was added to the skill's table before it was run**, per the
roadmap's first retrospective rule and phase 3a's and phase 4's precedent. The table carried no row for this
phase's subject matter, so a tenth was added — **Observability, configuration and redaction**:
`--topic observability,configuration,redaction-and-security --section rules --brief`, with
`--prefix CFG,OBS --section rules --brief` as the ID-bearing half. Running it produced **92 entries across
three topic files** and two results that shaped this document: the `redaction-and-security` topic carries
`XCUT-19`'s five clauses and `XCUT-21`'s CSPRNG rule **alongside** `OBS-11`–`OBS-19`, so the redaction surface
is one audit target spanning two prefixes and must not be split from the event object; and
`concurrency-and-async` — not `configuration` — is where `CFG-15`–`CFG-21` actually live in the corpus
(`configuration` carries only their appendix-B roll-up), which is why the group names both.

A second group, **Public API surface** extended with `performance`, was run as
`--topic api-design,performance,error-handling,module-organization,resource-management,concurrency-and-async
--section rules --brief` (201 entries) and narrowed by grep rather than read whole. It settled one thing this
document relies on: `api-design/1d9e6e0b`, `/a9943041` and `/634ccc4b` together make **adding an optional
keyword a non-breaking change and changing an existing default a MAJOR one**, which is the rule under which
`DEF-28`, `DEF-34` and `DEF-36` are all safe to pick up by widening a phase-2/3/4 signature. The remaining
eight rows of the table are audits of built code and belong to the sub-phases, which name and record the ones
they run.

`--phase 2`, `--phase 3` and `--phase 4` were run to see what the predecessors already cite. Phase 2 cites
`CFG-15`, `CFG-17`, `CFG-18`, `CFG-20`, `CFG-21` and `OBS-3` without owning them, all pointing here. Phase 3b
cites `CFG-1`–`CFG-4` and `OBS-35` and fixed the shape of two phase-5 consumers outright (`DEF-34`). Phase 4a
cites `OBS-21`, `OBS-25`, `OBS-26` and `OBS-27` and **fixed a contract phase 5 may not redefine** (`DEF-37`).

**No knowledge note is filed by this document.** Every verified fact below either overrides no harvested rule
or belongs to a sub-phase's own finding; the one candidate — that `Fiber[:k] = nil` deletes the key — widens
`observability/e0f1e864`'s already-superseding note rather than contradicting anything, and the note that
would carry it is `5b`'s to file with the design that acts on it. Recorded here so its absence is a decision.

---

## The cut

**Three ways. One boundary is the specification's own; the other is this document's judgement; both are
CONVENIENCES.**

| Sub-phase | Name | Spec sections | IDs | Order |
|---|---|---|---|---|
| **5a** | Configuration and the clock | `docs/product-spec/16-configuration.md`, all of it | 38 | first, **convenience** |
| **5b** | The logging facade and redaction | `15-instrumentation-and-observability.md` §15.1–§15.4, §15.9 | 27 | second, **convenience** |
| **5c** | Tracing and metrics | `15-instrumentation-and-observability.md` §15.5–§15.8 | 13 | third, **convenience** |

### Why the §15/§16 boundary is real and is still not a dependency

The roadmap's phase-5 bullet gives one edge and calls it "a real, if soft, dependency": `OBS-35`'s log-level
resolution wants `CFG`'s layered lookup. The edge is real. It is not a dependency, for three reasons stated
in increasing order of force.

1. **`OBS-35` is a SHOULD.** Its text is "A log-level value **SHOULD** be resolvable from layered
   configuration (explicit override -> environment variable -> normalized system property -> default)". A
   SHOULD whose feature the port ships implements every embedded MUST in it (§11.11), and `OBS-35`'s embedded
   MUST is "The SDK MUST NOT bake in a default config key name" — a *prohibition*, satisfiable with no
   configuration chain in sight.
2. **The edges run both ways.** `CFG-24`: proxy resolution "MUST NOT throw on any malformed input (proxies
   are optional; **invalid config yields null and a warning log**)". `CFG-25`: an out-of-range port "MUST
   cause resolution to yield null (**with a warning**)". A warning log is §8.1's facade, which is `5b`'s. And
   `DEF-27` reserves the closure of its own row for "phase 5 supplies the second [disposal route] with §8.1's
   facade", where the route is an `http.instrumentation.*` diagnostic emitted by `Dexpace.close_quietly` —
   whose null-safety clause is `CFG-21`, a `5a` requirement. So `5a` needs `5b` exactly as much as `5b` needs
   `5a`, and a document that records only one direction produces a chain that does not exist.
3. **The one decision that spans the boundary is already made and is not either segment's to re-open.**
   Design §10.16 is a single deviation — "The configuration chain keeps four tiers with a substituted third
   source" — and it *touches* `CFG-1`, `CFG-3`, `CFG-4`, `CFG-24`, `CFG-26` **and `OBS-35`**. Both segments
   implement one already-argued decision; neither derives it.

What remains true, and is the strongest thing that can be said for the order, is that a `5b` built before `5a`
would have to resolve `OBS-35`'s four tiers against a duck type it invented for the occasion — which is the
"fix an interface a later phase must be free to shape" objection phase 0 raised against defining
`Dexpace.register` early, phase 2 raised against `deadline:` (`DEF-28`) and phase 4 raised against
`RECOV-27`'s wait. That is a **convenience with teeth**, not a dependency, and it is stated in that form so a
`5b` plan does not treat `5a`'s absence as a blocker.

### Why the boundary inside §15 exists, and why it is this document's judgement rather than the spec's

The specification does not forbid one segment covering the whole of chapter 15, and this document does not
pretend it does. Phase 4 could quote a MUST NOT for its `4b`/`4c` line; phase 5 cannot, and saying so plainly
is what stops the argument being read as stronger than it is. Four things support the line anyway.

1. **The chapter's own introduction states that its two halves have opposite failure-containment rules, and
   makes honouring the asymmetry a port obligation.**
   > "The overriding intent: observability is always safe (never leaks secrets), always cheap when disabled
   > (no hot-path allocation), and never breaks the caller. **That last guarantee is asymmetric:**
   > log-emission failures are caught and swallowed, whereas tracing and metrics calls are NOT defensively
   > wrapped — their safety rests on the SPI contract that those callbacks never throw (**OBS-30**). A port
   > MUST either honour that contract or add its own guards."

   `OBS-20` restates it as a MUST that names both halves and forbids treating them alike: every log-emission
   site "MUST catch any exception and re-surface it as a best-effort `http.instrumentation.*` diagnostic",
   while "The runtime does NOT defensively wrap tracer (span start, scope activation, end) or metrics
   (counter/histogram) calls". That forces the **behaviour** apart, not the segments — but a single document
   whose job is to keep two error policies apart while describing them as one deliverable is the shape phase
   4 declined for `4b`/`4c`, arriving here without a prohibition to lean on.
2. **The two halves are disjoint object graphs.** `5b` is the `Event`/`Logger` facade (`OBS-1`–`OBS-9`,
   `OBS-39`, `OBS-40`), the redactor (`OBS-11`–`OBS-19`, `XCUT-19`), the diagnostic-context fold (`OBS-10`,
   `OBS-24`), failure containment (`OBS-20`) and the HTTP logging policy (`OBS-34`–`OBS-38`). `5c` is the
   `Span`/`Scope`/`Tracer` shape (`OBS-21`–`OBS-27`), the HTTP-tracer vocabulary (`OBS-28`–`OBS-30`) and the
   `Meter` (`OBS-31`–`OBS-33`). They share **two String constants** — the diagnostic-context keys `trace.id`
   and `span.id`, which `OBS-23` writes and `OBS-10` folds — and nothing else. That is a shared contract, not
   a boundary, and it is named as risk **R11** with both owners.
3. **`5c` carries a contract phase 4 fixed and phase 5 may not redefine.** `DEF-37` and roadmap cross-phase
   obligation 1 give it a five-clause handshake with phase 4a over `Dexpace::Instrumentation::Bundle`,
   `NO_SPAN`, `NO_TRACER_FACTORY` and `TraceIdFlavour`. Phase 4 made `4a` a segment for the mirror-image
   reason ("carries the phase's one irreversible external handshake"). A contract that is a whole document's
   subject is harder to breach than one that is section 9 of a forty-ID document.
4. **Redaction must stay welded to the event object, and a 27-ID segment makes that visible.** Design §8.1:
   "Redaction (**OBS-11**–**OBS-19**) runs on the way into `#field`, **not at the sink**, so no sink
   implementation can bypass it." That is the phase's security-critical structural claim; `XCUT-19`'s five
   clauses are the audit target; and both live entirely inside `5b`.

Against the line: 13 IDs is smaller than any sub-phase the roadmap's expectations contain (`4a`'s 20 was the
previous minimum), and a phase returns to `mvp` as **one phase-level pull request** (roadmap execution step
5), so a third sub-phase is a third document set and not a third merge. Both are real costs, accepted, and
the second is the reason a *fourth* segment is rejected below.

### Where the line inside §15 falls, and why the tempting 20/20 split is wrong

The numerically pleasing cut is `OBS-1`–`OBS-20` against `OBS-21`–`OBS-40`, twenty each. It is wrong.
`OBS-34`–`OBS-40` are **logging** requirements — the chapter files them under §15.9 "Log level, body preview,
and event vocabulary", and design §8.1 lists `OBS-39` (the stable event names and keys) and `OBS-40` (the
throttled collision diagnostic) explicitly among "the eight clauses **the event object** then carries".
Putting them in the tracing segment would separate `OBS-39`'s `url.full` from the redactor that makes it
redacted, which is the one line §8.1 calls "the single most consequential in this subsection". So the line is
**§15.1–§15.4 plus §15.9 against §15.5–§15.8**, giving 27 and 13.

`OBS-23` goes to `5c` and not to `5b`, although its effect lands in the diagnostic context `5b` folds. Its
verb decides it: "**Activating a span** for log correlation MUST push the trace id and span id onto the
thread-local diagnostic context". It is a span-activation requirement whose non-recording branch "MUST skip
the push and delegate to plain current-span activation" — a statement about `OBS-21`'s recording flag, which
is `5c`'s. `OBS-24` goes to `5b`: it is the context snapshot itself, with no span in it.

### The order that is recommended, and why it is only a recommendation

`5a → 5b → 5c`. Three reasons, none of them a dependency:

1. **`5a` is what the most downstream work waits on.** Four register rows name it — `DEF-28` (the pivot's
   `deadline:` and the clock behind it), `DEF-34` (the body-logging caps' configuration source, jointly with
   `5b`), `DEF-36` (the context store's cap) — and the whole of phase 6 waits on two of its objects:
   `CFG-15`'s cancellable wait is the one `DEF-35`'s `RECOV-27` was moved to phase 6 to reach, and `CFG-12`'s
   well-known key for the retry-attempt cap is where `RETRY-12`'s defaults come from. Landing it first gives
   phase 6 the longest lead, which is the reasoning phase 4 gave `4a`.
2. **`5b` is where four register rows close or half-close**, and one of them is a behaviour change to code an
   earlier phase shipped: `DEF-27`'s second disposal route closes that row, `DEF-31`'s lifecycle event gets
   its shape, `DEF-32`'s optional per-failure diagnostic becomes available, and `DEF-34` is picked up with
   `5a`. Landing it before `5c` means the instrumentation step exists for `5c` to populate rather than to
   invent.
3. **`5c` is the smallest segment and every one of its inputs is already shipped** — phase 4a's `Bundle`,
   `TraceIdFlavour`, `NO_SPAN` and `NO_TRACER_FACTORY`, and `Fiber[]` itself. It is put last because it is the
   segment that would gain least from moving, not because anything blocks it. A `5c` built first would be
   correct and would leave `OBS-34`'s step with two empty slots for `5b` to fill instead of the other way
   round.

**Because the order is a convenience, each sub-phase's design must say so in its own Prerequisite section
rather than inheriting a chain by habit** — the treatment the roadmap prescribes for phase 7 and phase 4
applied here for the same reason. A `5b` plan whose first task waits on `5a`'s `Configuration` object has
re-imposed a chain that does not exist; so has a `5c` plan that waits on `5b`'s `Logger`.

### Three other cuts were considered, and rejected

**Rejected cut A — two ways, the roadmap's expectation: `5a` configuration, `5b` everything in chapter 15.**
Rejected on the four grounds under *Why the boundary inside §15 exists*, and on one more that is arithmetic
rather than judgement: a 38/40 split makes phase 5 the only phase in the roadmap with two segments both at or
above 38 IDs and no line inside either. Phase 3b's 49 was explicitly flagged as "the price of not splitting a
lifecycle" — one object graph that could not be cut. Forty IDs over five disjoint object graphs is not that
case.

**Rejected cut B — three ways with the third line inside `CFG`: the layered chain against the utilities.**
This is the most tempting alternative, because appendix C names the prefix's subsystem "**Configuration and
utilities**" and chapter 16 splits §16.1–§16.4 from §16.5–§16.6 itself. Rejected on design §10.16. The proxy
model is not a utility that happens to live near the chain: §8.2 says the proxy resolution "keeps its
preferred first layer too … preserving **CFG-24**'s precedence shape with a Ruby-native source. That is **one
deviation applied twice, not two deviations**." Splitting `CFG-22`–`CFG-28` from `CFG-1`–`CFG-4` would put one
deviation in two documents and invite the second to re-derive it. With the proxy staying, the residual
"utilities" segment is `CFG-29`–`CFG-36` — eight IDs, four of them free-standing helpers with no consumer
anywhere in phase 5. Eight IDs is the "four IDs, rejected without a paragraph" shape, and a segment whose
whole content has no caller in its own phase is a `utilities.rb` with a document attached.

**Rejected cut C — four ways: `5a`, `5b`, `5c` and a fourth for the HTTP instrumentation step.** The step
`OBS-34` describes is genuinely the one object all three segments feed: it reads the log level (`5a`'s chain,
`5b`'s parse), emits `OBS-39`'s events through `5b`'s facade, and starts a span and records two instruments
through `5c`'s SPIs — "Span lifecycle AND metric recording run on every request independent of the log level"
is `OBS-34`'s own sentence. A fourth segment for it would be strictly linear, so it buys no independence, and
it is a fourth document set and not a fourth merge. Rejected, and the step is instead assigned to **`5b`**
with `5c` populating its two duck-typed slots — the shape phase 4a used for the `Bundle` and phase 4 used for
its three shipped steps (its R8). That assignment is fixed below as a charter decision, not a spec-forced
boundary, and its open questions are risk **R11**.

---

## Spec-forced boundaries — not open to `5a`, `5b` or `5c`

Each is a MUST, a design deviation already argued, or a roadmap obligation already fixed, that settles
something a sub-phase design might otherwise believe it is free to decide.

1. **The bundled-gem rule, and `logger` in particular.** `CLAUDE.md`'s hard rule and design §2.4. §8.1 states
   the consequence for this phase in one sentence:
   > "Beneath the event object, **the output sink is a duck type, and core never `require`s `logger`** —
   > §2.4's reason: `logger` becomes a bundled gem in Ruby 4.0 (verified), so requiring it from a
   > zero-dependency core creates an undeclared dependency on a supported interpreter."

   Re-verified 2026-09-09: `Gem::BUNDLED_GEMS::SINCE["logger"]` is `"4.0.0"`. `5b` defines the sink as
   anything responding to `#debug`/`#info`/`#warn`/`#error` plus the `#debug?`-style predicates, ships a
   frozen `NullLogger` as the default, and writes no `require "logger"` anywhere in `lib/`. This is the one
   constraint in the phase that a mechanised gate already catches by name rather than generically: phase 0's
   denylist carries `logger` explicitly so the failure message says *when* it left the default set.
2. **`OBS-1`'s shared inert event is an object with an asserted identity, not a cheap code path.**
   > "The facade MUST decide enabled/disabled once, at event-creation time, and **return a shared inert event
   > for the disabled case**." Conformance: "assert the returned event is the shared singleton
   > (reference-identical across calls)."

   §8.1 argues at length that a `Logger`-shaped sink is the wrong *shape* for this family and that seven
   further MUSTs "are stated *about that object* and have nowhere to live on a `sink.info { }` call". `5b`
   ships `Dexpace::Instrumentation::Event` and `Event::INERT`; it may not substitute a block-form sink call
   for either.
3. **`OBS-20`'s asymmetry, quoted because it is the boundary between `5b` and `5c`'s error policies.**
   > "Emitting structured log events around a request MUST NOT be able to fail the request: every
   > log-emission site … MUST catch any exception and re-surface it as a best-effort
   > `http.instrumentation.*` diagnostic, and a secondary failure while emitting that diagnostic MUST be
   > swallowed. **The runtime does NOT defensively wrap tracer … or metrics … calls**; their non-failure
   > guarantee rests instead on the SPI contract that those callbacks never throw (OBS-30), so a throwing
   > tracer or meter WILL propagate and can fail the request."

   Neither segment may make the other's rule uniform. `5c` may not wrap; `5b` may not stop wrapping.
4. **`XCUT-19` is default-deny in five clauses and `OBS-11`'s userinfo redaction can never be allow-listed.**
   `XCUT-19(a)` and `OBS-11` both say "always"/"unconditionally and independent of any allow-list", and
   `XCUT-19(e)` makes full body logging OFF by default, which `OBS-34`'s "defaulting to none (logging off
   unless explicitly opted in)" restates. `5b` may not add an allow-list entry that reaches userinfo and may
   not default any level above `none`.
5. **Redaction runs at `#field`, not at the sink** (§8.1), so `OBS-39`'s `url.full` "MUST always be the
   redacted URL" is structural rather than defended. `5b` may not offer a sink-level redaction hook, because
   a sink that could bypass redaction is the whole failure this placement prevents.
6. **`CFG-1`'s ordering is preserved even where it inverts Ruby convention**, per §10.16 and §8.2:
   > "this port uses *call-site override > `ENV` > `configure` defaults > caller default*, because
   > **CFG-1** is normative and a conformance test written against it would observe the difference."

   `5a` implements four tiers with `Dexpace.configure`'s process-wide defaults as the substituted third
   source. It may not drop to three tiers and may not fabricate a second `ENV` read under another name (P11).
   `CFG-3`'s normalised-key accessor and `CFG-4`'s raw exact-name accessor stay distinct.
7. **`CFG-15`'s wait is a cancellable queue wait and not `Kernel#sleep`** — §10.17, §8.3:
   `Clock#sleep(duration, cancellation:)` is a bounded wait on a per-call `Thread::Queue` the cancellation
   token pushes to on cancel. `5a` may not implement it as a sleep, and may not reach for `Timeout.timeout`,
   `Thread#raise` or `Thread#kill`, which the phase-0 cop `Dexpace/NoThreadInterrupt` blocks anyway.
8. **`CFG-32`'s non-cryptographic UUID and `XCUT-21`'s CSPRNG stay two code paths**, §8.2:
   > "even though Ruby's `SecureRandom` lacks the blocking-entropy problem that motivated the split: keeping
   > them separate costs nothing and preserves the ability to substitute either independently."

   `CFG-32`'s own text is explicit — "It MUST use a non-blocking randomness source (per-thread PRNG), and
   callers MUST treat the output as NON-cryptographic" — so `5a` may not implement it as
   `SecureRandom.uuid`, however tempting. The mechanism is `R3`; the two-path rule is not open.
9. **`CFG-34`'s boxed-versus-primitive clause is recorded inapplicable, and only that clause.** §11.15: the
   rest of `CFG-33`/`CFG-34` is implemented. `5a` may not extend the inapplicability to the NaN and signed-zero
   halves, which verified fact 5 below shows are the two that actually require work.
10. **Phase 4a's five-clause handshake over the instrumentation bundle, quoted from `DEF-37` because roadmap
    obligation 1 puts it out of phase 5's reach.** Phase 5 populates through `Bundle.build` or
    `Bundle::NONE.with(...)`; may add methods to `Bundle`, `TraceIdFlavour`, and the `private_constant`
    classes behind `NO_SPAN` and `NO_TRACER`; and may **not** introduce a second no-op span or tracer, replace
    either published singleton, rename or remove a `Bundle` member, add a member, change `Bundle#valid?` from
    derived to stored, replace `TraceIdFlavour` with a bare `Symbol`, or give `Bundle` a second `NONE`.
    Phase 4a's deviations `P4-6`, `P4-7` and `P4-8` are the three shape decisions `5c` inherits. `5c` fixes
    the span and tracer *protocols* (`OBS-21`–`OBS-25`), which phase 4 deliberately did not.
11. **`OBS-26`'s reserved sentinels are already values in core and are not re-chosen.** Trace id of 32 hex
    zeros, span id of 16 hex zeros, trace flags `"00"`, empty trace state. `5c` implements `OBS-27`'s
    generation over `TraceIdFlavour::W3C` and `::DATADOG` and may not alter `::NONE`'s sentinel, which
    `Bundle::NONE` carries and `CTX-15` names.
12. **`OBS-25`'s no-allocation clause is asserted by reference identity from a qualified constant**, which is
    why `NO_SPAN` and `NO_TRACER_FACTORY` are public where phase 4a's other new internals are
    `private_constant` (`execution-context/c2eb344c`'s superseding note). `5c` may not make either private,
    and the `dexpace-conformance` suite that asserts it is phase 8's.
13. **The three unsatisfied MUSTs are settled and phase 5 does not re-open them.** §10.5 splits `ASYNC-3`,
    `ASYNC-4` and `PIPE-33`; `DEF-18` carries them. `CFG-20` is the same prohibition meeting a fourth ID and
    is treated below, not re-argued.
14. **`Fiber[:key]` is the diagnostic-context carrier and `CTX`'s store is not it** — design §8.1,
    `docs/knowledge/notes/observability.md`. `5b` and `5c` may not put the diagnostic context in
    `Thread.current[]`, which is fiber-local and invisible to a child fiber, a new `Thread` and an
    `Enumerator`'s internal fiber; and may not put it in `Dexpace::ContextStore`, whose cap and reachability
    requirements it would defeat.
15. **Charter decision, not spec-forced, recorded here so `5c` meets it as a fixed input rather than an open
    question: the HTTP instrumentation step is `5b`'s object and `5c` populates two slots in it.** `OBS-34` is
    a `5b` ID (§15.9), `OBS-20`'s wrapping rule is the step's dominant correctness constraint and is `5b`'s,
    and `Stages::LOGGING` is the pillar phase 4c handed phase 5 for it. `5c` supplies the tracer factory and
    the meter through the slots and ships **no second step**. Open questions are `R11`.

---

## Scope: every ID, assigned to exactly one sub-phase

**78 requirement IDs.** Level split, derived mechanically from appendix C on 2026-09-09: **61 MUST, 16
SHOULD, 1 MAY.**

### Reconciliation against the roadmap's arithmetic

**The roadmap's phase-5 arithmetic is correct and nothing is missing or double-counted.** Verified
mechanically against appendix C on 2026-09-09: `CFG` is 38 contiguous rows `CFG-1`..`CFG-38` with no
duplicate, `OBS` is 40 contiguous rows `OBS-1`..`OBS-40`, and the file holds exactly 645 requirement rows.
38 + 40 = 78, which is the roadmap's phase-5 cell. `5a`'s 38 plus `5b`'s 27 plus `5c`'s 13 is 78, each ID in
exactly one sub-phase.

Per-prefix levels: `CFG` 29 MUST / 8 SHOULD (`CFG-12`, `CFG-13`, `CFG-14`, `CFG-18`, `CFG-19`, `CFG-20`,
`CFG-35`, `CFG-36`) / 1 MAY (`CFG-28`); `OBS` 32 MUST / 8 SHOULD (`OBS-7`, `OBS-19`, `OBS-28`, `OBS-32`,
`OBS-35`, `OBS-37`, `OBS-38`, `OBS-40`) / 0 MAY.

### `5a` — Configuration and the clock (38 IDs, all `CFG`)

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `CFG-1`–`CFG-19`, `CFG-21`–`CFG-33`, `CFG-36`–`CFG-38` | 35 |
| Partially satisfied — `CFG-20`'s cancel-with-interrupt clause is `ASYNC-3`'s under a second ID and is unsatisfiable under §8.3 (§10.4, §10.5, `DEF-18`, `OI-22`); its other three clauses are met | `CFG-20` (SHOULD) | 1 |
| Partially satisfied — the NaN and signed-zero halves implemented; the boxed-versus-primitive clause recorded **inapplicable** per §11.15 | `CFG-34` | 1 |
| Partially satisfied, **pending `R1`** — the expected answer is that the status half lands here as `XCUT-5`'s single shared classifier while the throwable half waits on `XCUT-6`'s capability (phase 6) and `Dexpace::TransportError` (phase 8); `5a` may instead defer the whole ID beside `DEF-38`, and files the row if it does | `CFG-35` (SHOULD) | 1 |

**Nothing in `CFG` is deferred outright**, which design §12's `CFG` row confirms: "*Deferred:* none." `5a`
additionally ships, without owning a new ID: the configuration source `DEF-34` and `DEF-36` are waiting for;
the `deadline:` keyword on `Future#value`/`#wait` and the monotonic clock behind it (`DEF-28`); and `CFG-14`'s
well-known key constants, which `RETRY-12` and `OBS-35` both reference by name without either owning them.

`CFG-16` is `OI-15`'s **elapsed-time** counter and shares nothing with `CTX-4`'s **call-sequence** counter but
the adjective. `5a` writes the full phrase, never "the monotonic counter" unqualified.

### `5b` — The logging facade and redaction (27 IDs)

The segment's ID set is exactly `OBS-1`–`OBS-20` together with `OBS-34`–`OBS-40`: 20 + 7 = **27**.

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `OBS-1`–`OBS-18`, `OBS-20`, `OBS-34`, `OBS-35`, `OBS-36`, `OBS-38`, `OBS-39`, `OBS-40` | 25 |
| Partially satisfied — the verbosity policy and its once-per-name throttle ship; the emission site is vacuous for `Net::HTTP`, which raises rather than drops (§12's `OBS` row), and binds any phase-8 adapter that does drop | `OBS-19` (SHOULD) | 1 |
| ⏳ deferred, `DEF-9` (pre-existing), post-v1 with the async adapters | `OBS-37` (SHOULD) | 1 |

`XCUT-19` and `XCUT-20` are phase 9's IDs and get no row here; `5b` satisfies both by construction —
`OBS-11`–`OBS-18` are `XCUT-19`(a)–(c) and `OBS-15`/`OBS-20` are `XCUT-20` — and phase 9 audits the claim.

`5b` additionally ships, without owning a new ID: `Dexpace.close_quietly`'s second disposal route, closing
`DEF-27`; `SEAM-25`'s lifecycle event shape, half-supplying `DEF-31`; the optional per-dropped-failure
diagnostic in `Hooks.notify` (`DEF-32`); the configuration wiring for phase 3b's `RequestLoggingBody` and
`ResponseLoggingBody` and phase 3a's `MAX_MATERIALIZED_BYTES` (`DEF-34`, jointly with `5a`); and the HTTP
instrumentation step at `Stages::LOGGING` with two slots `5c` fills.

### `5c` — Tracing and metrics (13 IDs)

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `OBS-21`–`OBS-31`, `OBS-33` | 12 |
| ⏳ deferred, `DEF-9` (pre-existing), post-v1 with `dexpace-instrumentation-otel` (`DEF-17`) | `OBS-32` (SHOULD) | 1 |

`5c` additionally ships, without owning a new ID: the span and tracer protocols behind phase 4a's three
singletons, closing `DEF-37`; `SEAM-28`'s stable operation identifier as a consumer of phase 4a's
`RequestContext#operation_name`, closing `DEF-1`'s second half; and the widened RBS interfaces `_Span`,
`_Tracer` and `_TracerFactory`, which phase 4a declared empty on purpose.

`OBS-28` (SHOULD) and `OBS-29` (MUST) are a parent-SHOULD/child-MUST pair of the kind §11.11 resolves as "the
feature is optional, its behaviour is not": `5c` ships `OBS-28`'s vocabulary and therefore implements
`OBS-29`'s ordering contract in full. `OBS-29`'s own text
records that "pipeline/transport wiring to emit it is a follow-up, so it is not yet runtime-enforced" —
`R14`.

---

## Exclusions — IDs a reader would expect here, and the phase that owns each

| Excluded | Owning phase |
|---|---|
| `CTX-14`, `CTX-15`, `CTX-20` — the correlation bundle's shape, its `NONE` singleton, the no-op tracer factory | 4, built. Roadmap obligation 1: phase 4 fixed the shape and phase 5 populates and may not redefine. Phase 5 owns `OBS-25`/`OBS-26`/`OBS-27`, the requirements those members are *values of* |
| `CTX-4`, `CTX-6` — the process-wide monotonic **call-sequence** counter | 4, built. `CFG-16`'s is an **elapsed-time** counter; `OI-15` records that one phrase named both |
| `CTX-7`, `CTX-11`, `CTX-19` — the bounded context store | 4, built. Phase 5 supplies only the configuration source for its cap (`DEF-36`) |
| `ASYNC-8`–`ASYNC-12` — capture, install and restore of the diagnostic context across a thread hop | 8. Phase 5 owns the carrier (`OBS-10`, `OBS-23`, `OBS-24`); `dexpace-async-thread` owns the adapter-side save/install/restore, and `OI-13`'s warned setter is what it will meet |
| `ASYNC-3`, `ASYNC-4`, `PIPE-33`'s interrupt clause | 8 marks all three (`DEF-18`, §10.5). Phase 5 meets the same prohibition at `CFG-20` and dispositions it here rather than adding a fourth |
| `RETRY-1`, `RETRY-13`, `RETRY-26`, `RETRY-28`, `XCUT-6`, `XCUT-7` — the retry engine, the shared backoff calculator, the configurable retryable-status set | 6. Phase 5 ships the wait `RETRY-26` needs (`CFG-15`) and, under `R1`, `XCUT-5`'s single built-in status classifier (`CFG-35`) — which is not `XCUT-7`'s configurable set and must not be conflated with it |
| `RECOV-17`–`RECOV-30`, `RECOV-34` — the recovery-stack retry engine | 6 (`DEF-35`). `RECOV-27`'s cancellable inter-attempt wait was moved there *because* it is `CFG-15`'s object, which phase 5 now builds |
| `XCUT-5`'s baked retryability flag on `Dexpace::ProtocolError` | 6 (`DEF-38`). Phase 4b shipped the class; phase 6 adds `#retryable?`. `R1` decides whether it computes from a `5a` classifier or a phase-6 one, and `OI-21` records that `DEF-38` did not account for `CFG-35` |
| `XCUT-9` — the cycle-safe cause walk `CFG-19` and `CFG-35` both need | 4b, built as `Dexpace.each_cause`, tracking by reference identity. Phase 5 uses it and writes no second walk |
| `XCUT-11` — shared-instance safety for redactors and factories | 9 dispositions. Phase 5 builds redactors and factories that are the audit's subject |
| `XCUT-13` — idempotent, non-blocking close | 2, built as `Dexpace::Closeable`. `CFG-21`'s null-safe best-effort close is `Dexpace.close_quietly`, phase 2's, and phase 5 adds only its second disposal route |
| `XCUT-14` — the general bounded-map rule | 9 dispositions; 4a built the implementation |
| `XCUT-19`, `XCUT-20`, `XCUT-21` — default-deny redaction, observability totality, the CSPRNG rule | 9 dispositions. Phase 5 satisfies all three by construction: `OBS-11`–`OBS-18` are `XCUT-19`(a)–(c), `OBS-15`/`OBS-20` are `XCUT-20`, and `CFG-32`'s deliberate separation from `SecureRandom` is what keeps `XCUT-21` a distinct path |
| `SEAM-24` — cross-thread diagnostic propagation beyond fiber-local storage | Post-v1 with `dexpace-async-async` (`DEF-1`, `DEF-11`) |
| `SEAM-5`'s auto-activation for instrumentation | Post-v1 (`DEF-30`, `DEF-17`). Instrumentation is **not** one of `SEAM-2`'s five seams, so phase 5 adds no fourth registry — see the sweep |
| `BODY-19`, `BODY-22`, `BODY-32`, `BODY-34`, `IO-9` — the logging body wrappers and the materialisation ceiling | 3a and 3b, built. Phase 5 supplies only their configuration source and enablement gate (`DEF-34`) |
| `AUTH-19`'s per-nonce counter store, `AUTH-20`'s cryptographic nonces | 6. Both consume phase-4a's bounded map and `XCUT-21`'s CSPRNG path; neither is phase 5's |
| `TRANSPORT-3`, `TRANSPORT-8` — proxy use and header-drop reporting on a real adapter | 8. Phase 5 ships `CFG-22`–`CFG-28`'s proxy *model* and `OBS-19`'s *policy*; nothing in core opens a socket |
| `NFR-5`'s coverage floor, `NFR-7`'s warning-free build | 0, stood up; 9 dispositions. `OI-13`'s per-call warning is where `NFR-7` bites a phase-5 decision (`R12`) |

---

## Gap IDs: what `--gaps CFG,OBS` reports, and how the roadmap's claim held

The roadmap says, of the 22 gap IDs it enumerates: "Every other prefix has full corpus coverage." `CFG` and
`OBS` are among the others, and **the claim holds exactly**. `ruby scripts/knowledge.rb --gaps CFG,OBS`, run
2026-09-09, reports the following — the trailing summary line elided, the rest verbatim, so re-running it and
diffing this block is not mistaken for drift:

```
CFG — Configuration and utilities
  38 canonical IDs: 38 substantive, 0 roll-up only, 0 uncited

OBS — Instrumentation and observability
  40 canonical IDs: 40 substantive, 0 roll-up only, 0 uncited
```

**No sub-phase budgets any specification reading beyond its own chapters, and both chapters are short.**
Chapter 15 is 73 lines and chapter 16 is 62; both were read in full for this document, together with the
canonical appendix-C text of all 78 IDs, which is where the conformance notes' extra detail does *not* live —
the chapters carry a `*Conformance: …*` clause per ID that appendix C does not, and those clauses were read
as well. Thirty-five `CFG` and forty `OBS` conformance notes exist and several are load-bearing: `OBS-1`'s
"assert the returned event is the shared singleton (reference-identical across calls)" is what makes the
singleton's *identity* rather than its cheapness the tested property, and `CFG-26`'s "`a\|b|c` → `[a|b, c]`;
`a\,b,c` → `[a,b, c]`" is the only statement anywhere of what the escape rule produces.

**The pointer pathology that produced `OI-1`, `OI-2` and `OI-12` does not recur here, and that was checked
rather than assumed.** Verified mechanically 2026-09-09: every one of `CFG-1`–`CFG-38` appears in
`docs/product-spec/16-configuration.md` and every one of `OBS-1`–`OBS-40` appears in
`docs/product-spec/15-instrumentation-and-observability.md`, and no phase-5 ID exists only as an appendix-C
row. `--gaps`'s "read these out of …" line is not printed for either prefix, so there is no unfollowable
instruction to file. This is worth stating positively: at three occurrences the pattern looked like a property
of appendix C's relationship to the prose chapters, and the fourth prefix pair checked shows it is not
universal.

**What replaces it is the roll-up hazard**, recorded under *Corpus reading* above: all 78 IDs return at least
one `[appendix-B roll-up]`-tagged hit on `--req`, where phase 4's three prefixes returned none. The sub-phase
designs run the skill's three-step roll-up path as a matter of course, not as an exception.

---

## Prerequisites, and the decisions phase 5 inherits

**From phase 0** — seventeen blocking gates, unchanged and unlowered. Four bite here.

- `gates:require_allowlist`. Core's `lib/**/*.rb` may `require` only `monitor`, `uri`, `stringio`, `strscan`,
  `time`, `date`, `securerandom`, `digest`, `openssl`, `forwardable`, `set`, `singleton`. **Phase 5 is
  expected to add nothing**, and the one candidate is `rbconfig` for `CFG-36`'s host-runtime identity —
  verified fact 7 shows it is avoidable. `logger` is on the **denylist by name**, so a `require "logger"` in
  core fails with a message naming the release it left the default set in rather than a generic "not
  allowlisted". `timeout` is likewise denylisted, which is the mechanised half of boundary 7.
- `Dexpace/NoThreadInterrupt` (a phase-0 cop). In phase 5 this is not background: it is why `CFG-15`'s wait is
  a queue wait and why `CFG-20`'s interrupt mode cannot be built.
- `Dexpace/NoTimeParse`, which bans `Time.parse`, `Date.parse` and `DateTime.parse` and points at
  `Time.httpdate`. Verified fact 3 shows `Time.httpdate` alone does not satisfy `CFG-30`, so `5a` meets this
  cop as a live constraint rather than a formality (`R2`).
- `gates:surface_snapshot` and `gates:sig_diff` regenerate for every new public constant. Phase 5 ships more
  new public constants than any phase since 1 — the whole `Dexpace::Instrumentation::` and configuration
  surfaces — and §8.1 requires `OBS-39`'s event names and field keys to be "frozen constants **covered by
  §9.1's surface snapshot**, because a 'stable' vocabulary that nothing asserts drifts on the first refactor."

**From phase 1** — `Dexpace::Model` with the `#with` override that routes through the validating `.build`;
`Dexpace::Builder`; `Dexpace::Error` as a **module**; `Dexpace::InvalidArgumentError < ::ArgumentError`;
`Status`, `Method`, `Headers`, `Request`, `Response`, `MediaType`. Four rules bind every file phase 5 writes:

- **Public wire-model constants are flat (P1-1) — but a subsystem the design already names with a namespace
  keeps it.** §8.1 names `Dexpace::Instrumentation::Event`, `Event::INERT` and `Dexpace::Instrumentation::Bundle`;
  phase 4a already shipped `Dexpace::Instrumentation::NO_SPAN`, `NO_TRACER_FACTORY` and `TraceIdFlavour`. Those
  keep their namespace. Everything else is a naming decision each sub-phase records as a Deviation Ledger row.
- **No `.build` is a bare `new` wrapper.** Validation lives in each `Data` type's `initialize`.
- **`Dexpace::ArgumentError` is never defined**, in this or any later phase. `CFG-37`'s and `OBS-3`'s fail-fast
  guards raise `Dexpace::InvalidArgumentError`.
- **`downcase` takes no argument**, everywhere in core — which `OBS-12`'s "decoded, compared
  case-insensitively" parameter-name match and `CFG-6`'s case-insensitive `true`/`false` both depend on.

**From phase 2** — the seam layer, and three of its objects are phase 5's direct subjects:

- `Dexpace::Cancellation`, `Cancellation::Source` with `#on_cancel` returning a `Subscription`, and
  `Cancellation.any` / `Cancellation.over`. `DEF-28` names `Cancellation.any` as "the composition point a
  deadline-derived token plugs into, and `Cancellation.over` is public for exactly that." `CFG-17`'s
  re-assertion clause is met **structurally** by this token: the "interrupt/cancellation status" a downstream
  handler observes is the token's own cancelled state, which was already set before the wait woke.
- `Dexpace::Async::Future` and `Async::Completer`, currently `#value(cancellation:)` and `#wait(cancellation:)`
  with **no `deadline:`** (deviation P2-5, `DEF-28`). `5a` adds the keyword, which widens.
- `Dexpace.close_quietly` with its null-safety (`CFG-21`'s last clause) and its `rescue StandardError` that
  currently **drops** the rescued error, plus `Dexpace::Hooks.notify` (`private_constant`). Phase 4b gave
  `close_quietly` its `onto:` keyword and the suppressed-trail route; `5b` supplies the diagnostic route and
  closes `DEF-27`.
- `Dexpace::Registry` and three seam registries, with **no auto-activation hook of any kind** and a test
  asserting its absence (`DEF-30`). Phase 4 added no fourth registry and neither does phase 5.
- `Dexpace::Closeable` with its latch and ownership rule — `SEAM-25`'s whole sentence except the lifecycle
  event (`DEF-31`).
- Six custom cops, including `Dexpace/QualifiedCoreConstant` (P2-8, extended by phase 3a as P3-7). Phase 5
  defines no constant that shadows a core class, but `5b`'s sink duck type is deliberately *named after* one
  it must not become.

**From phase 3** — `Dexpace::Body` as the contract; `Dexpace::BufferBody`, `ResponseBody`; **the two logging
wrappers `DEF-34` is about**: `Dexpace::RequestLoggingBody` takes `tap_limit:` defaulting to
`::Float::INFINITY`, `Dexpace::ResponseLoggingBody` takes a **required** `preview_bytes:`, and nothing in core
constructs either — which is how `BODY-34`'s "engaged only when body-level logging is enabled" is satisfied
structurally today and what `5b` changes. `Dexpace::IO::MAX_MATERIALIZED_BYTES` is a frozen constant with no
keyword, and §3.1 asks for it to become "configurable through the same layered chain as every other limit
(§8.2)". `Response#body_string` and `#body_bytes` are what `OBS-38`'s charset-aware preview builds on.

**From phase 4, and this is the largest and most constrained inheritance:**

- **4a, obligatorily** — `Dexpace::Instrumentation::Bundle` with its eight stored members and derived
  `#valid?`, `Bundle::NONE`, `Bundle::INVALID_SPAN_ID`, `TraceIdFlavour` with `NONE`/`W3C`/`DATADOG` and
  `.of`, `NO_SPAN`, `NO_TRACER_FACTORY` and its one method `#tracer(name = nil, version = nil)`, and the empty
  RBS interfaces `_Span`, `_Tracer`, `_TracerFactory`. **The shape is fixed and `5c` populates it.** The
  five-clause handshake in phase 4a's R3 is the contract; `DEF-37` is its register row; boundary 10 above
  restates the prohibitions.
- **4a** — `RequestContext#operation_name` and `ExchangeContext#operation_name`, "already carried and already
  advisory", which is `DEF-1`'s first half for `SEAM-28`.
- **4a** — `ContextStore.new(cap:)` and `ContextStore::MAX_TRACKED_CONTEXTS = 1024`, the attachment point
  `DEF-36` names. Picking it up is one wiring and **no signature change**.
- **4b** — `Dexpace::Error#suppressed`, `Dexpace.attach_suppressed`, the trail rendered through
  `#detailed_message` (not `#full_message`), `Dexpace.each_cause` tracking by reference identity, and
  `Dexpace::ProtocolError` **without** `#retryable?`. `Dexpace.each_cause` is what `CFG-19`'s unwrap loop and
  `CFG-35`'s cause-chain walk both use; neither writes a second walk. 4b's interface table binds `5b`
  twice: on `DEF-27`, "Phase 5 adds the `http.instrumentation.*` diagnostic for the `onto:`-absent case and
  **closes the row**; it does not replace the trail and does not remove the keyword"; and on `DEF-32`, "Phase
  5 may emit a diagnostic per attached failure; it does not replace the trail."
- **4c** — `Stages::LOGGING` as the pillar for the instrumentation step, with `Stages::PRE_LOGGING` and
  `POST_LOGGING` as its slots. 4c's interface table is explicit about the shape: "The step declares `#stage`
  and is installed with no `stage:` argument. It is a pillar, so it **may** fork. **It should not**: a step
  that drives the chain exactly once drives it through `#call`, and `#call` and `#fork` are disjoint on one
  cursor — a step either calls once and never forks, or forks for every drive and never calls." `5b` builds
  the step against that sentence and does not rediscover it. On `DEF-28`, 4c says "Nothing new. 4c calls no
  blocking wait; when `deadline:` lands on `Future#value`, `AsyncTransport.sync_over` gains it and **no
  pipeline signature changes**" — so `5a`'s pick-up touches no phase-4 code.
- **4c** — `Builder#install_preset(entries)`, the all-or-nothing mechanism `DEF-39` reserves for phase 6's
  `Pipeline.standard`. `PIPE-24`/`PIPE-39` name an instrumentation step among the defaults; **phase 5 does not
  write either constructor** — `DEF-39` targets phase 6 as "the first phase in which all three families
  exist", and phase 5 supplies one of the three.

**Two open items land in phase 5's window and neither is phase 5's to close.** `OI-13` (`Fiber#storage=` warns
on every call at the default warning level and `= nil` reads back differently on the 3.2 floor) is met head-on
by `OBS-24` and is risk `R12`. `OI-15` ("the monotonic counter" names two unrelated objects) is met by
`CFG-16`; `5a` writes **elapsed-time counter** in full and never the bare phrase, which is the mitigation
`OI-15` itself names.

---

## Cross-cutting constraints that bite phase 5 specifically

1. **The bundled-gem rule, and it bites harder here than in any phase before it.** `logger` becomes a bundled
   gem in Ruby 4.0 (`Gem::BUNDLED_GEMS::SINCE["logger"] == "4.0.0"`, re-verified), and §8.1 makes the sink a
   duck type for exactly that reason. This is the one phase where the idiomatic Ruby answer to the chapter's
   headline requirement — "use `Logger`" — is the forbidden one, and the failure would be silent on the
   development interpreter and loud only on the 4.0 matrix row under Bundler. The mitigations are three and
   all already exist: the denylist names `logger` explicitly, the clean-bundle isolation run is what makes the
   4.0 column load-bearing, and §8.1's duck type is *the stdlib `Logger` surface as a structural subset*, so
   a consumer's `Logger`, a Rails logger or `SemanticLogger` drops in with zero adapter code. `5b` must not
   write `require "logger"` even in a test-support file inside `gems/dexpace-core`, because the require scan
   resolves relative targets and reads text.
2. **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden in every gem**, argued in §8.3 and
   enforced by `Dexpace/NoThreadInterrupt`. In phase 5 this is the direct and only cause of `CFG-20`'s
   unsatisfiable clause, and it is what makes `CFG-15`'s wait a queue wait. It is **not** what makes `CFG-17`
   hard: `CFG-17`'s re-assertion clause is met by the cancellation token phase 2 built.
3. **Deadlines are explicit values, not ambient interrupts.** `5a` adds `deadline:` to `Future#value` and
   `#wait` and derives a cancellation token from it through `Cancellation.any`; it does not add a timeout, and
   the deadline propagates to `open_timeout`/`read_timeout`/`write_timeout` only in phase 8.
4. **`OBS-11`–`OBS-19`'s redaction is the phase's security surface, and it is default-deny in four places at
   once.** Userinfo is unconditional and can never be allow-listed (`OBS-11`, `XCUT-19`(a)); the query
   allow-list defaults to exactly `{api-version}` (`OBS-12`); the header-name allow-list "MUST contain only
   diagnostic, non-credential headers" (`OBS-18`, `XCUT-19`(c)); body logging is off by default (`OBS-34`,
   `XCUT-19`(e)). `OBS-15` makes the whole thing total — a parse failure returns `[malformed url]` and never
   raises — and `XCUT-20` generalises that to every observability path. The failure mode is not a crash; it
   is a token in a log aggregator, and no test that only exercises the happy path finds it. Phase 4b already
   deferred one decision to this constraint: `Dexpace::ProtocolError`'s message names the status and does not
   include a body preview, "because a message is what lands in a log by default, and an error body is the one
   payload most likely to carry a token or a customer identifier. **Confirm with phase 5's planner rather than
   reversing it here.**" `5b` confirms it.
5. **`Fiber[:key]` versus `Thread.current[:key]`, and the read/write asymmetry.** The read side is uniform
   across the supported range and copy-on-write (phase 4's verified fact 7, `docs/knowledge/notes/observability.md`).
   The write side splits: `Fiber[:k] = v` is warning-free (verified fact 1) and is all `OBS-23` needs;
   `Fiber#storage=` warns per call at the default warning level against a gate set that fails on warnings, and
   is what `OBS-24`'s whole-map snapshot reaches for (`OI-13`, risk `R12`).
6. **`Thread::Mutex` is per-fiber-owned and non-reentrant.** `CFG-8`/`CFG-13`'s process-wide configuration
   slot is one frozen reference swapped under a mutex with readers taking no lock, and `OBS-8`'s emit-once
   guard is "a `@emitted` boolean flipped under a `Thread::Mutex` **with the mutex released before the sink
   call**, so an emit that blocks on I/O does not hold a lock across a suspension point" (§8.1). Neither holds
   a lock across a callback, a render or a sink write.
7. **Regexp timeouts are per-pattern.** `CFG-23`'s glob-to-pattern conversion, `OBS-12`'s query tokenizer,
   `OBS-27`'s trace-id validation and `CFG-30`'s date grammar are all `Regexp.new(source, timeout:)` and never
   `Regexp.timeout`. `CFG-23` additionally says patterns "SHOULD be compiled once at construction, not per
   lookup", so the compiled pattern is a member of the frozen proxy model.
8. **`Ractor` is never load-bearing.** `Configuration` holds two callable seams (`CFG-11`), so no shareability
   claim is made for it despite it being a frozen `Data`; `data-modeling/5bc538ba` already narrows the general
   claim for the same reason.
9. **An `Enumerator` abandoned mid-`#next` never runs its `ensure`.** `OBS-22`'s scope handle and `OBS-24`'s
   snapshot bridge are both `begin/ensure` around a block, never an enumerator, and no resource is acquired
   inside any block phase 5 yields from.

---

## `CFG-20`: the fourth clause of §8.3's prohibition, and why it is not a fourth unsatisfied MUST

§10.5 names three: `ASYNC-3`, `ASYNC-4` and `PIPE-33`'s interrupt clause. `CFG-20` is a fourth ID describing
the same mechanism, and it is inside phase 5's range, so a reader who meets it needs the relationship stated
precisely rather than inferring that phase 5 has widened the port's gap.

**`CFG-20` and `ASYNC-3` are the same requirement at two levels.** `CFG-20` (SHOULD): "running a task on an
executor such that cancelling with the 'interrupt' flag interrupts the worker thread currently running the
task, while cancelling without it cancels without interrupting. A task still queued (not yet started) or
already finished MUST NOT be interrupted, and the worker's interrupt/cancel state MUST be cleared before it
returns to its pool … Rejected submission (saturated/shut-down executor) MUST be delivered through the
returned future, never thrown synchronously." `ASYNC-3` (MUST) is the first sentence verbatim in different
words; `ASYNC-4` (MUST) is the pool-clearing sentence. `CFG-20` is `ASYNC-3` + `ASYNC-4` + one clause of its
own, tagged SHOULD.

**Three of its four clauses are met.** The non-interrupting cancel is `Future#cancel`, phase 2's. The
queued-or-finished clause holds because no interrupt is ever delivered. The rejected-submission clause is
phase 2's `Completer#fail` routing, which the phase-2 plan's own review fixed and tested — a raise escaping
the posted block leaving the future permanently unsettled was one of the four defects that review reproduced.

**The fourth is unsatisfiable and is not phase 5's to re-open.** Interrupt-mode cancellation is the mechanism
§8.3 forbids repository-wide. §10.5's residual-gap statement applies unchanged: a transport blocked inside an
uninterruptible C-extension read cannot be aborted early, so the worker occupies its pool slot until the read
returns; the future completes as cancelled promptly, `Completer#on_cancel` lets an adapter shorten the wait by
closing the socket under the read, and the consequence is bounded worker occupancy rather than a correctness
failure. `docs/deviations.md` row 4 — "Cancellation is cooperative; the orphaned-response close moves to the
producer" — already lists `CFG-17`, `CFG-20` and `CFG-21` among the IDs it touches, and §10.4 is where the
mechanism substitution is argued.

**Phase 5 adds no fourth unsatisfied MUST, and the arithmetic is why:** `CFG-20` is a **SHOULD**, so its unmet
clause is an unmet SHOULD clause, not a fourth entry beside `ASYNC-3`, `ASYNC-4` and `PIPE-33`. §12's `CFG`
row already dispositions it — "`CFG-20` (SHOULD, interruptible-task future) **reshaped as the pivot** (§3.3)
with `CFG-21`'s discard-path close honoured".

**What is missing is a register row, and that is the finding.** §10.5 lists three IDs and `CFG-20` is not one;
`DEF-18` cites `ASYNC-3` and `PIPE-33` and not `CFG-20`; §12's word is "reshaped", which does not say a clause
is unmet; and `docs/first-release.md` carries no line for it. So `5a`'s checklist row for `CFG-20` has three
things to cite and none of them states the gap. Filed as **`OI-22`**. This is the same
two-IDs-one-feature shape §11.20 records for `RECOV-31`/`RETRY-38`, and the phase-4 segmentation design's
treatment of it — carry the row, cite the ledger, do not conflate the counts — is the treatment `5a` applies.

---

## Verified Ruby facts that shaped this cut

**Interpreter availability, stated before the facts because it limits every one of them.** Phases 3 and 4 ran
their facts on 3.2.11, 3.4.10 and 4.0.6 via `mise exec ruby@<v>`. **On this machine only 3.4.10 is
installed** — `mise ls` lists `bun`, `go`, `node` and `opencode` and no Ruby, and no interpreter exists under
`~/.local/share/mise/installs`, `~/.rbenv`, `~/.rvm` or `/opt/rubies`. Every fact below was run on
**`ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]`** and on nothing else. Where a fact is
of the floor-straddling kind this repository has been bitten by three times — `URI::DEFAULT_PARSER` at 3.4.0,
`StringIO#read(n, buf)`'s encoding at 3.4, `Data#with`'s `initialize` on 3.2 — it is flagged, and **the
sub-phase design that acts on it re-runs it on 3.2.11 and 4.0.6 before relying on it**. Nothing here is
claimed across a range that was not run.

1. **`Fiber[:k] = v` emits no warning; `Fiber#storage=` warns on every call.** Two `Fiber[]=` writes and one
   read-back produce zero warnings; two `Fiber#storage=` calls produce two, category `:experimental`, text
   `Fiber#storage= is experimental and may be removed in the future!`. **And `Fiber[:k] = nil` deletes the
   key** — `Fiber.current.storage.key?(:k)` is `false` afterwards, not `true` with a `nil` value. *What it
   licenses:* `OBS-23`'s whole contract — "push the trace id and span id … for the scope's lifetime, and MUST
   restore each key to its prior value (**or remove it if previously unset**) on close" — is expressible with
   `Fiber[]=` alone, per key, with no warning and no gate problem. *What it does not license:* any claim about
   `OBS-24`. `OBS-24`'s "immutable snapshot … reinstall … restore that thread's prior context" is a whole-map
   operation and the obvious spelling is `Fiber#storage=`, which is `OI-13`'s warned setter and which reads
   back differently on the 3.2 floor. Verified here that `Fiber#storage = {a: nil, b: 1}` **does** retain the
   `nil`, so a nil-valued diagnostic key is reachable through the map setter and unreachable through the
   per-key one — which decides whether `OBS-10`'s "Keys with null values MUST be skipped" is a live clause or
   a vacuous one, and that is `5b`'s to state (`R12`).
2. **`Time.httpdate` formats `CFG-29` exactly and rejects three of `CFG-30`'s four zone tokens.**
   `Time.utc(1994,11,6,8,49,37).httpdate` is `"Sun, 06 Nov 1994 08:49:37 GMT"`, zero-padded, which is
   `CFG-29`'s stated example verbatim. Parsing: `Time.httpdate` **accepts** a wrong weekday
   (`"Mon, 06 Nov 1994 …"` parses, satisfying `CFG-30`'s informational-weekday clause), **accepts** a
   lower-case month (`"06 nov 1994"`), **rejects** the empty string and **rejects** a missing comma after the
   weekday (satisfying both of `CFG-31`'s strictness clauses) — and **rejects `UTC`, `+0000` and `+00:00`**
   with `ArgumentError: not RFC 2616 compliant date`, all three of which `CFG-30` requires be accepted and
   normalised to the zero offset. `Time.rfc2822` accepts `GMT` and `UTC` but not `+00:00`. *What it licenses:*
   `CFG-30` cannot be `Time.httpdate` and cannot be `Time.parse` either, which the phase-0 cop
   `Dexpace/NoTimeParse` bans by name while pointing at `Time.httpdate` as the sanctioned form. `5a` writes a
   normalise-then-delegate step or an explicit grammar; the choice is `R2`. *What it does not license:*
   abandoning `Time.httpdate` — it is exactly right for `CFG-29` and for three of `CFG-30`'s four tolerances.
   `Date._httpdate` returns a component hash including `zone` and `offset` and is a third route.
3. **`URI::RFC3986_PARSER` preserves a present-but-empty query and never mistakes a fragment `?` for a query
   delimiter.** `P.parse("https://h/x?")` gives `query == ""` and `#to_s` gives `"https://h/x?"`; setting
   `query = nil` gives `"https://h/x"`. `P.parse("https://h/x#a?b=c")` gives `query == nil` and
   `fragment == "a?b=c"`. `P.parse("/cb?code=SECRET")` succeeds with `scheme == nil`. `P.parse("not a url at
   all")` raises `URI::InvalidURIError`. `u.userinfo = "***:***"` renders `"https://***:***@h/x"`. *What it
   licenses:* `OBS-14`'s three clauses — do not alter scheme/host/port/path, preserve a trailing `?`, do not
   insert a spurious separator for a fragment `?` — are satisfied by the pinned parser with one discipline:
   an emptied query is assigned `""` and never `nil`. And `OBS-16`'s branch is `scheme.nil?` and **not** a
   rescue, because a relative URL parses cleanly. *What it does not license:* `OBS-15`'s totality. The parser
   raises on some inputs and succeeds on others, so the `[malformed url]` sentinel still needs a `rescue`, and
   `5b` must decide what happens to an input that parses but rebuilds wrong (`R9`).
4. **`Date._iso8601` parses no ISO-8601 duration at all.** `Date._iso8601("PT5S")`, `("P1D")`, `("PT-5S")` and
   `("P1DT2H3M4S")` all return `{}`. *What it licenses:* `CFG-7`'s ISO-8601 branch is hand-written, alongside
   its `<number><unit>` shorthand and its bare-number-as-milliseconds branch, and `5a` budgets for a grammar
   rather than a delegation. *What it does not license:* any claim about `date`'s other parsers, which are
   fine and which `CFG-30` may still use.
5. **Ruby's float equality is wrong for `CFG-34` in both directions, and `eql?` does not rescue it.** Two
   distinct `NaN` objects: `a == b` is `false`, `[a] == [b]` is `false`, `[a].eql?([b])` is `false` —
   `CFG-34` requires NaN **equal** to NaN. Signed zeros: `[0.0] == [-0.0]` is `true` and
   `[0.0].eql?([-0.0])` is `true`, and `0.0.hash == (-0.0).hash` — `CFG-34` requires them **unequal** with
   hashing that matches. (The trap that makes this easy to get wrong: `[n] == [n]` with the *same* NaN object
   is `true`, because `Array#==` short-circuits on identity, so a test written with one NaN passes under a
   broken implementation.) `1.0/x` discriminates the zeros. *What it licenses:* `CFG-33`/`CFG-34`'s deep
   equality is a hand-written recursive comparison with its own hash, delegating to neither `==` nor `eql?`
   for floats, and `5a` budgets for that rather than for a thin wrapper. *What it does not license:*
   revisiting §11.15 — the boxed-versus-primitive clause stays inapplicable, and it is a different clause from
   these two.
6. **The inert-event chain allocates nothing, and the repository's mandatory `frozen_string_literal` comment
   is what makes the test say so.** A frozen singleton whose builder methods return `self` and whose `#emit`
   is a no-op, driven 1000 times with `GC` disabled, allocates **1** object — the measurement floor.
   Driven with a bare `"x"` String literal as an argument it allocates **1001**, one per call; add
   `# frozen_string_literal: true` at the top of the same file and it is **1** again. *What it licenses:*
   `OBS-1`'s "MUST allocate nothing" is testable by `GC.stat(:total_allocated_objects)` exactly as §8.1
   promises, and the honest limit §8.1 states — "allocates nothing beyond the arguments the caller had already
   computed" — is measurable rather than an excuse. *What it does not license:* writing that test carelessly.
   A conformance file without the magic comment measures the caller and fails against a correct
   implementation, which matters because `dexpace-conformance` is a different gem written in a later phase
   (`R8`).
7. **`RbConfig` is undefined under `ruby --disable-gems`.** `defined?(RbConfig)` is `"constant"` normally and
   `nil` under `--disable-gems`, where the constant reference raises `NameError`; `require "rbconfig"` then
   works, and `rbconfig` is not in `Gem::BUNDLED_GEMS::SINCE` (28 entries, `logger` at `"4.0.0"`).
   `RUBY_PLATFORM`, `RUBY_ENGINE`, `RUBY_VERSION` and `RUBY_DESCRIPTION` need no require. *What it licenses:*
   `CFG-36`'s "host runtime identity (runtime version, vendor, OS name)" can be derived with **no new
   allowlist entry**, so phase 5 grows the require allowlist by nothing. *What it does not license:* the claim
   that `RbConfig` is unusable — it is requirable and legitimately allowlistable, at the cost of a reviewed
   one-line diff. This is phase 2's `Gem`-under-`--disable-gems` finding arriving at a second subsystem
   (`R5`).
8. **`Thread::Queue#pop(timeout:)` returns `nil` after the interval.** A 0.05 s timeout returns `nil` in
   0.050 s; `Process.clock_getres(Process::CLOCK_MONOTONIC)` is 1 ns. *What it licenses:* §8.3's
   `Clock#sleep(duration, cancellation:)` as a bounded queue wait, and `CFG-17`'s "SHOULD preserve
   sub-millisecond precision where the platform allows". Phase 4 verified the same call on the 3.2 floor for
   `RECOV-27`, which is the version half this run does not cover. *What it does not license:* `CFG-18`'s
   "WITHOUT blocking a thread", which holds only under a registered `Fiber.scheduler` (`R6`).
9. **`Class#name` is `nil` for an anonymous class, and `BasicObject#to_s` raises a `NoMethodError` that
   `rescue StandardError` catches.** `Class.new(StandardError).name` is `nil`; `Deep::Nest::Boom.name` is
   `"Deep::Nest::Boom"`, whose last `::` segment is `OBS-6`'s `SimpleClassName`. *What it licenses:* §8.1's
   "the rendering path rescues `StandardError` per value and substitutes `[unrenderable <ClassName>]`" catches
   the `BasicObject` case it names. *What it does not license:* rendering an exception by
   `e.class.name.split("::").last` without a nil guard — an anonymous error class, which
   `Class.new(StandardError)` produces and which appears in test suites and in metaprogrammed adapters, makes
   `OBS-6`'s own totality clause fail on the totality path.
10. **A `\A…\z` glob translation with `Regexp::IGNORECASE` satisfies `CFG-23`'s four rules and fails on an
    embedded newline.** `*` → `.*`, `?` → `.`, everything else `Regexp.escape`d, anchored `\A…\z`, case
    folded: `*.example.com` matches `A.Example.COM`, `a?c` matches `abc` and not `abbc`, `a.b` does not match
    `axb`. But `*` does not match `"a\nb"`, because `.` excludes `\n` without `/m`. *What it licenses:*
    `CFG-23`'s "escape all regex metacharacters, require a FULL-string match, and match case-insensitively"
    with `\A`/`\z` and never `^`/`$`. *What it does not license:* ignoring the newline case — a host name
    cannot contain one in practice, but `CFG-23`'s words are "match any run of characters", and `5a` either
    adds `/m` or records why it did not.

---

## Deferrals filed by phase 5

**None, and that is deliberate.** A segmentation design decides a cut; it does not decide the interfaces whose
absence a deferral records. Phase 4 filed one only because `DEF-35` was a **scope disposition** — an entire ID
cluster moving to another phase — and leaving it unrecorded would have obliged a sub-phase to re-derive a
sixteen-ID argument and possibly reach a different answer. Phase 5 has one candidate of that shape,
`CFG-35`'s classifier, and the answer it reaches is **"phase 5 builds it"** rather than "phase 5 defers it",
so there is nothing to defer. The argument is `R1` and the finding against `DEF-38`'s reasoning is `OI-21`.

**Three rows are expected of the sub-phases** and are named in the risks so their absence later is visible:
`5a`'s disposition of `CFG-35`'s throwable half, which needs `XCUT-6`'s capability (phase 6) and
`Dexpace::TransportError` (phase 8) (`R1`); `5a`'s treatment of `CFG-18`'s non-blocking clause under no
registered scheduler (`R6`); and `5c`'s disposition of `OBS-29`'s lifecycle **wiring**, which the requirement
itself calls a follow-up (`R14`).

### Deferral-register sweep

The roadmap's execution step 1 requires the phase to read the **whole** register and disposition every row.
All thirty-nine were read. As with phases 3 and 4, this document **states** each disposition and the sub-phase
**performs** the register edit.

**Phase 5 picks up four rows, closes a fifth that has been open since phase 2, half-supplies two, and files
none.**

- **`DEF-1`'s `SEAM-28` half — picked up, by `5c`.** Its pick-up condition names phase 5 explicitly and says
  why: "Both halves of the MAY need machinery phase 2 does not have — the request's context chain (`CTX`,
  phase 4) … and a consumer for the identifier (instrumentation, phase 5) … and **phase 5 is the first phase
  that has both**." Phase 4a supplied the chain half as `RequestContext#operation_name`, "already carried and
  already advisory". `5c` supplies the consumer: `CTX-20`'s per-operation tracer factory takes a name, and
  `OBS-29` requires "One tracer instance corresponds 1:1 to a single logical operation lifecycle (created by
  the factory per operation)" — the operation identifier is what names it. `SEAM-28`'s own constraint travels
  with the pick-up: "when present it is attached to the request's context chain but **MUST NOT affect the
  assembled request's URL, headers, or body**." The row's `SEAM-24` half is untouched and stays with
  `DEF-11`. If `5c` declines, the row becomes **UNSCHEDULED** with phase 5 named, because this is a condition
  phase 5 genuinely meets.
- **`DEF-27` — picked up and CLOSED, by `5b`.** The row fixes two disposal routes for `close_quietly`'s
  rescued error and reserves closure: "phase 4 supplies the first route with `DEF-24`'s `#suppressed` and
  `Dexpace.attach_suppressed`; **phase 5 supplies the second with §8.1's facade and closes this row**."
  Phase 4b supplied the first and added the `onto:` keyword. `5b` emits the `http.instrumentation.*`
  diagnostic for the `onto:`-absent case, does not replace the trail, does not remove the keyword, and moves
  `Status` to `picked-up`. The test phase 2 wrote asserting the error is dropped is what has to change, and
  4b's interface table already says so.
- **`DEF-28` — picked up, by `5a`.** Its condition names phase 5 "with `CFG-15`–`CFG-21`'s clock and
  interruptible-delay primitives" and names the composition point: "`Dexpace::Cancellation.any` is the
  composition point a deadline-derived token plugs into, and `Cancellation.over` is public for exactly that."
  `5a` adds `deadline:` to `Future#value` and `#wait`. `NFR-4` is not prejudiced — adding a keyword **widens**
  and the lock fails only when a signature "disappears or narrows" — and 4c confirms no pipeline signature
  changes.
- **`DEF-34` — picked up, by `5a` and `5b` jointly.** Its condition names "phase 5, when `CFG-1`–`CFG-4`'s
  layered chain and `OBS-35`'s body-level-logging setting exist" and states the work as "three wirings and no
  new mechanism": read the shared preview size from the chain into both wrappers, gate their construction on
  the enablement setting, and give `MAX_MATERIALIZED_BYTES` a configured source. The chain is `5a`'s and the
  setting is `5b`'s, so the row is edited by whichever lands second and both designs cite it. Every one of the
  three is a **widening** of a narrower signature, so `NFR-4` permits all three.
- **`DEF-36` — picked up, by `5a`.** Its condition names "phase 5, with `CFG-1`–`CFG-4`'s layered chain. The
  attachment point already exists and the work is one wiring: read the cap from the chain when constructing
  the process-wide store. **No signature changes.**" `ContextStore.new(cap:)` is already keyword-shaped with a
  documented default of `MAX_TRACKED_CONTEXTS = 1024`.
- **`DEF-37` — picked up and closed, by `5c`.** Its condition names "phase 5, with `OBS-25`". `5c` gives the
  three `private_constant` classes their methods and widens `_Span` and `_Tracer`; the three published objects
  keep the identity phase 4 gave them, which is what makes `OBS-25`'s allocation clause assertable by
  reference identity. The five prohibitions in the row's "What phase 5 may not do" are restated as spec-forced
  boundary 10 above.
- **`DEF-31` — half supplied, row stays open, and phase 5 must not close it.** Its condition names phase 5
  "with §8.1's facade — that is where the event can be emitted", and then names phase 8: "The first thing in
  this repository that actually **owns** an executor is phase 8's `dexpace-async-thread`, so phase 8 is where
  the emission gets a real subject and where `dexpace-conformance` asserts 'close twice → executor shut once,
  one event'." `5b` supplies the event's shape and its place in `OBS-28`'s vocabulary and adds a dated line to
  the row's `Status`; the row does **not** move to `picked-up`.
- **`DEF-32` — optional half available, row stays as phase 4b left it.** Its text reserves the trail for phase
  4 and adds: "Phase 5 **may** additionally emit an `http.instrumentation.*` diagnostic per dropped failure
  once §8.1's facade exists (`DEF-27` waits on the same two routes); **it does not replace the trail**." `5b`
  decides whether to take the option; either way the trail phase 4b built stays.
- **`DEF-30` — untouched, and the one row whose condition needs an argument rather than a lookup.** Its
  condition is "an instrumentation seam exists to activate — phase 5 (Configuration and Observability) at the
  earliest — and its first and only sanctioned user is `dexpace-instrumentation-otel` (see `DEF-17`), which is
  post-v1." **The recommendation is that phase 5 does not meet it**, and the reason is `SEAM-2`'s own
  enumeration: "The enumerated core interface seams are: byte-stream provider, synchronous transport,
  asynchronous transport, wire codec (serde), and operation-input->request projection." **Instrumentation is
  not among them.** Phase 5 ships a tracer, a meter and a logger as duck types with no-op defaults installed
  through configuration, not as a registered seam with `SEAM-5` discovery, and phase 4 already recorded that
  phase 4 "adds no fourth registry". A row whose condition names an object the phase does not build is not
  UNSCHEDULED. **`5c` records this reading explicitly**; if `5c` does ship a registry the reading reverses and
  the row becomes UNSCHEDULED with phase 5 named (`R15`).
- **`DEF-9` — untouched, and cited by two ⏳ rows.** `OBS-32` (OTel metric conventions) is `5c`'s ⏳ row and
  `OBS-37` (async body-capture skip) is `5b`'s. The condition — the OTel adapter (`DEF-17`) and the async
  adapters (`DEF-11`, `DEF-12`) — is post-v1 and phase 5 cannot meet it. Not UNSCHEDULED.
- **`DEF-38` — untouched, and the one row phase 5's scope reaches into without being able to edit.** It
  targets phase 6 and its content — `#retryable?` on `Dexpace::ProtocolError` — stays there. What phase 5
  changes is the *source*: under `R1`, `CFG-35`'s classifier is `XCUT-5`'s "SINGLE shared status classifier"
  and phase 6 computes the flag from it rather than building one. Filed as `OI-21` because the row is
  committed and its argument has a hole this document cannot close by editing.
- **`DEF-18` — untouched, and cited by `5a`'s `CFG-20` row.** Phase 5 neither meets nor re-opens it. See
  *`CFG-20`* above and `OI-22`.
- **`DEF-35` — untouched, and phase 5 is what unblocks it.** Its forcing argument was that `RECOV-27`'s
  conforming wait "is the object `CFG-15` defines, which is phase 5's". `5a` builds that object; the fifteen
  IDs stay in phase 6.
- **`DEF-3` — untouched.** `BODY-12` clause 1 discharged by phase 3b; clause 2 targets phase 8 with `DEF-10`;
  `BODY-36`'s condition is core's dependency budget changing, which phase 5 explicitly does not do (verified
  fact 7).
- **`DEF-2`, `DEF-4`, `DEF-5`, `DEF-6`, `DEF-7`, `DEF-8` — untouched.** `HTTP`, `PIPE`, `RECOV`, `RETRY`,
  `REDIR` and `SSE`; other prefixes, later phases or post-MVP.
- **`DEF-10` — untouched.** Per-adapter, phase 8 at the earliest.
- **`DEF-11`–`DEF-17` — untouched.** Post-v1 gems, out of the MVP by construction. `DEF-17` is what `DEF-9`
  and `DEF-30` both ride on.
- **`DEF-19`, `DEF-20` — untouched.** Release-gated; nothing is published.
- **`DEF-21` — already picked up** by phase 2. **`DEF-26` — already picked up** by phase 3b.
- **`DEF-22`, `DEF-23` — untouched.** Phase 8's conformance assertion objects; a Steep target over a test tree
  whose condition ("production-quality test support") phase 5's fakes do not meet. `DEF-22` is worth reading
  beside `R8`: `OBS-1`'s allocation assertion is one of the assertions that gem will hold, and it has a
  file-level precondition.
- **`DEF-24`, `DEF-25` — untouched.** Already picked up by phase 4b; wire-boundary re-validation is phase 8's.
- **`DEF-29` — untouched.** `5a`, `5b` and `5c` will add test doubles — a fake clock, a fake env source, a
  recording sink, a recording tracer and meter — under `gems/dexpace-core/test/support/`, following the
  precedent of phases 2, 3 and 4. `CFG-11` makes the env and property seams injectable **by requirement**, so
  a hermetic test never touches real `ENV`, and `CFG-15` does the same for the clock. The condition — a
  consumer outside `dexpace-core` — is not met.
- **`DEF-33` — untouched.** A non-CRuby matrix row; no phase in v1 plans one.
- **`DEF-39` — untouched.** `PIPE-24`/`PIPE-39`'s standard-resilience constructors target phase 6 as "the
  first phase in which all three families exist". Phase 5 supplies one of the three (the instrumentation
  step); it does not write either constructor and does not install a preset.

### The findings filed against `docs/open-items.md`

Three, proposed here for a human to file. None is acted on by this document.

**`OI-21` — `CFG-35` and `XCUT-5` define the same status classifier, and `DEF-38` assigns it to phase 6
without accounting for `CFG-35` being a phase-5 ID.** `XCUT-5` (MUST): the baked retryability flag "MUST be
computed ONCE at construction from a **SINGLE shared status classifier** … That classifier MUST treat 408,
429, and all 5xx EXCEPT 501 and 505 as retryable." `CFG-35` (SHOULD): "A shared retryability classifier SHOULD
exist and treat these HTTP status codes as retryable: 408, 429, and all 5xx EXCEPT 501 and 505 … Where the
classifier is implemented, this exact status-code set is a hard contract so exception construction and the
retry policy agree." Same set, same object, two IDs in two phases. `DEF-38`, filed by phase 4b and committed,
says "that classifier is `RETRY-1`'s, the same object `XCUT-6`'s open-capability path and `XCUT-7`'s
configurable retryable-status set are defined against, **all three of them phase 6's**" — which is correct
about `XCUT-6` and `XCUT-7` and does not mention `CFG-35`, whose home is phase 5 and whose text is where the
built-in set is stated at requirement level. Nothing is wrong in either document; the failure is that one
object is named by two requirements in two phases and no cross-reference exists at either end. It is the
`OI-15` shape — a sentence that reads correctly and resolves to the wrong phase — and, like `OI-15`, it is
filed rather than fixed because the register row is committed and adversarially reviewed. `XCUT-5`'s own
closing NOTE is the thing a reader must not lose: the baked flag is **not** what the retry step consults, so
the built-in classifier (`CFG-35`/`XCUT-5`) and the configurable set (`XCUT-7`) are legitimately two objects
and only the first is in question here. `R1` is where phase 5 decides.

**`OI-22` — `CFG-20`'s cancel-with-interrupt clause is `ASYNC-3`'s under a second ID, is unsatisfiable under
§8.3, and no register row cites `CFG-20`.** §10.5 names `ASYNC-3`, `ASYNC-4` and `PIPE-33` and stops; `DEF-18`
cites `ASYNC-3` and `PIPE-33`; §12's `CFG` row says `CFG-20` is "reshaped as the pivot", which does not say a
clause is unmet; §10 item 4 lists `CFG-20` among the IDs it touches but argues the mechanism substitution
rather than the gap; and `docs/first-release.md` carries no line. So a phase-5 checklist row for `CFG-20` has
three citations available and none of them states what is missing. The disposition is not in doubt — it is a
SHOULD, three of its four clauses are met, and the fourth is the same prohibition §10.5 already settles, so
**the port gains no fourth unsatisfied MUST** — but the roadmap's one-row-per-ID convention exists to stop a
✅ or a ⏳ with an unstated missing clause, which is exactly what phase 2 recorded for `SEAM-25` when it filed
`DEF-31`. Filed so the row `5a` writes has something true to cite. The parallel worth reading beside it is
§11.20's `RECOV-31`/`RETRY-38` — "the same feature under two IDs" — and the phase-4 treatment of it.

**`OI-23` — the probe's `citations` check cannot see a backticked register ID, which is the form this
repository writes 92% of them in.** `Citations#check_file` in `.claude/skills/housekeeping/probe.rb` scans
`Prose.unfenced(...)`, and `unfenced` blanks inline code spans as well as fenced and indented blocks, "so a
link or a citation ID that appears only as an EXAMPLE, inside code, is not read as an actual link or
citation." That reasoning is sound for a link and wrong for a register ID here, because `CLAUDE.md`'s own
requirement-ID convention backticks every ID and every document follows it. Measured across the tracked
`docs/`, `scripts/` and `.claude/` trees on 2026-09-09, excluding the two register files and the skill's own
test fixtures: **996 backticked `OI-`/`DEF-` mentions against 83 bare ones**, so the check inspects about one
citation in thirteen. Reproduced directly: a scratch file under `docs/work/` naming two undefined open-item
IDs, one wrapped in backticks and one bare, produces exactly one finding — the bare one. **The immediate
consequence is this document.** It cites `OI-21`, `OI-22` and this row before any of them exists, in the repository's normal
backticked form, and the check that exists to catch precisely that returns "no drift found"; the only finding
the probe reports against this change is `CLAUDE.md`'s phase-directory count. So a human filing the two rows
above has no mechanical reminder that they are still unfiled, which is the failure mode the check was built
for. This is the `OI-14` and `OI-16` family — a mechanism that reports clean over a set it never looked at —
and it is filed rather than fixed because the fix is a judgement about the check (blank inline code for links
but not for register IDs? scan `asserted` rather than `unfenced`? both, with the example case handled by an
explicit ignore marker?) and belongs with whoever owns the skill.

---

## Risks and open questions the sub-phase designs must resolve

Each is named with the sub-phase that owns it. **None is decided here.** Risk numbering restarts per phase in
this repository — phase 3's segmentation design ran R1–R10 and phase 4's ran R1–R14, and each phase's
sub-phase designs carry their own phase's numbers — so phase 5's are `R1`–`R15` and collide with neither.

**R1 — `5a`: whether `CFG-35`'s shared retryability classifier lands here, and what happens to its throwable
half.** `OI-21` states the collision. Three answers are available. **(a) Build it here.** `CFG-35` is phase
5's ID; its status set is fixed verbatim by `XCUT-5`; `XCUT-5`'s word SINGLE is then satisfied by one object
with one home, and `DEF-38`'s phase-6 work becomes "compute from the classifier phase 5 built" rather than
"build one". **(b) Defer it to phase 6** beside `DEF-38`, on `DEF-38`'s own argument that a classifier built
early gives two homes — an argument that had force against phase 4, which owned no requirement defining one,
and has less against phase 5, which does. **(c) Build the status half here and defer the throwable half**,
which needs `XCUT-6`'s retryability capability (phase 6) and `Dexpace::TransportError < ::IOError` (phase 8);
`Dexpace.each_cause` and `Dexpace::StreamError < ::IOError` already exist, so a walk over `::IOError` is
within reach today but would classify a set that is about to grow. `5a` picks one, states which, and — if it
is (b) or (c) — files the deferral this document deliberately does not.

**R2 — `5a`: `CFG-30`'s four zone tokens, against a banned `Time.parse` and a `Time.httpdate` that rejects
three of them.** Verified fact 2. Three routes: normalise the zone token to `GMT` and delegate to
`Time.httpdate`, which keeps the weekday and month tolerances free but means the strictness clauses of
`CFG-31` are inherited from a method the input no longer reaches unmodified; parse with an explicit anchored
`Regexp` and `Time.utc`, which puts `CFG-31`'s two failure cases under direct control at the cost of writing
the grammar; or read components with `Date._httpdate` and assemble. `5a` decides, and states how
`CFG-31`'s "blank/empty input MUST fail" survives whichever normalisation runs first.

**R3 — `5a`: `CFG-32`'s "non-blocking randomness source (per-thread PRNG)" on a Ruby where `Random::DEFAULT`
no longer exists.** Verified: `defined?(Random::DEFAULT)` is `nil` on 3.4.10. `Random.rand` works from
multiple threads but is one process-global generator, not a per-thread one. The candidates are a `Random`
instance per fiber in `Fiber[]` (which inherits copy-on-write into a child fiber, so two fibers would share a
seed — a correctness question, not a style one), a `Random` per thread, one `Random` behind a mutex, or
`Random.new` per call. `SecureRandom.uuid` is excluded by boundary 8 and by `CFG-32`'s own words. `5a` states
which, and states what "usable concurrently from multiple threads **without shared mutable state**" costs in
each.

**R4 — `5a`: where `CFG-33`/`CFG-34`'s deep equality lives, and what "distinct array kinds" means in a
language with one `Array`.** Verified fact 5 makes the implementation a hand-written recursive comparison with
its own hash. `5a` decides whether it is public API (and therefore `NFR-4`-locked and YARD-documented) or a
`private_constant` — noting `execution-context/c2eb344c`'s superseding note, which records that a
`private_constant` on `Dexpace` is reachable by a bare reference from any file inside `module Dexpace; …` and
**not** through a qualified reference or from the compact `module Dexpace::X` form — and it decides what
`CFG-34`'s "An object array and a primitive array with the same numeric values MUST NOT be considered equal"
means here, given §11.15 records only the boxed-versus-primitive half as inapplicable.

**R5 — `5a`: `CFG-36`'s host-runtime identity, and whether the require allowlist grows.** Verified fact 7:
`RbConfig` is undefined under `--disable-gems`, `RUBY_PLATFORM` is always defined, and `rbconfig` is
allowlistable at the cost of a reviewed diff. `CFG-36` wants "runtime version, vendor, OS name", each falling
back to a non-blank `unknown`, and requires every identity token to be non-blank "so joined identity strings
are never malformed". `5a` decides the source for each of the three and, if it reaches for `rbconfig`, carries
the allowlist diff and its motivating requirement — which would be the first growth of that list since phase
0 and should not happen by accident.

**R6 — `5a`: `CFG-18`'s "WITHOUT blocking a thread" holds only under a registered `Fiber.scheduler`.** §8.3's
own argument is conditional: "under a registered `Fiber.scheduler` the queue pop routes through the
scheduler's `block`/`unblock` hooks and unmounts the fiber, so no carrier is pinned; **with no scheduler it
blocks only the calling thread**, never a shared pool thread, which is the hazard the requirement targets."
`CFG-18` is a SHOULD asking for a *future* completing after a duration on a *provided scheduler*, which is a
different shape from `CFG-15`'s blocking sleep. `5a` decides whether `CFG-18` ships as a scheduler-conditional
implementation with the condition documented, as a deviation row of its own, or as a deferral naming phase 8 —
and it must not ship something that claims not to block a thread while blocking one.

**R7 — `5a`: which citation `CFG-20`'s checklist row carries.** `OI-22` states the gap: §10.4 argues the
substitution without stating the unmet clause, §10.5 lists three IDs not including this one, and `DEF-18`
cites two. `5a` decides whether the row is ⏳ against `DEF-18` with a note that the row does not cite
`CFG-20`, or ✅-with-clauses naming the three that are met, or a partial marker of its own — and whichever it
chooses, the row must name the unmet clause rather than inheriting §12's word "reshaped".

**R8 — `5b`: what `OBS-1`'s allocation test measures, and where its file-level precondition lives.** Verified
fact 6: the inert chain allocates zero, and a bare String literal in the test loop allocates one per call
unless the file carries `# frozen_string_literal: true`. Every file in this repository carries it by rule, so
the in-gem test is safe — but `OBS-1`'s conformance clause is one `dexpace-conformance` will restate (phase 8,
`DEF-22`), in a different gem, and a conformance file that loses the magic comment fails a correct
implementation. `5b` decides whether the assertion is written to be insensitive to the caller's allocations
(measure the delta of two loops, or pass only frozen constants) or whether the precondition is stated in a
comment the later gem will copy. It also decides how the *identity* half — "assert the returned event is the
shared singleton (reference-identical across calls)" — is asserted, which is `assert_same` on a qualified
constant and therefore, per `execution-context/c2eb344c`, forces `Event::INERT` to be public.

**R9 — `5b`: `OBS-15`'s totality against a parser that raises on some inputs and succeeds on others.**
Verified fact 3. `URI::RFC3986_PARSER` raises `URI::InvalidURIError` on garbage, parses a relative URL cleanly
with `scheme == nil`, and round-trips a present-but-empty query only if the query is set to `""` and not
`nil`. `OBS-15` requires "on any parse **or rebuild** failure it MUST return a fixed sentinel". `5b` decides
what counts as a rebuild failure, whether the redactor rescues `StandardError` or only `URI::Error`, and how
`OBS-16`'s three-way branch (parseable absolute → full redaction; relative or unparseable → keep the path,
drop the rest, append `?***` if there was a query **or** a fragment; neither → verbatim) is expressed given
that "relative" and "unparseable" reach it by two different routes.

**R10 — `5b`: `OBS-19`'s disposition, given §12 calls it vacuous for `Net::HTTP`.** Design §12's `OBS` row:
"`OBS-19` (SHOULD) is vacuous for `Net::HTTP`, which raises on an unencodable header rather than dropping it,
and binds any adapter that drops." `5b` decides between shipping the three-mode verbosity policy with its
once-per-header-name default and its throttle — which shares its latched-flag mechanism with `OBS-40`'s
once-per-logger diagnostic, so it is nearly free — and recording the requirement vacuous with a
cross-reference row for phase 8. It must not ship a policy with no caller and no test that exercises it,
which is the `OI-8` shape (`TeeSink#clear_tap`, `NFR-4`-locked public API with no core caller).

**R11 — `5b` and `5c` jointly: the instrumentation step's two slots, and who declares `trace.id` and
`span.id`.** This is the one contract that crosses the `5b`/`5c` line and it is a contract, not an ordering.
Boundary 15 fixes the ownership: the step is `5b`'s, installed at `Stages::LOGGING`, and `5c` fills the tracer
and meter slots. What is not fixed: whether the slots are constructor keywords defaulted to phase 4a's
`NO_TRACER_FACTORY` and `5c`'s no-op meter, or a configuration read; how `OBS-34`'s "Span lifecycle AND metric
recording run on every request **independent of the log level**" is expressed so that a level of `none`
provably still starts a span (its conformance clause requires the test); and which segment declares the two
diagnostic-context key names that `OBS-23` writes and `OBS-10` folds by default. **Neither may ship a second
step, a second key-name constant, or a second no-op meter**, and whichever design lands second cites the first
rather than restating it.

**R12 — `5c` and `5b`: `OBS-24`'s whole-map snapshot against `OI-13`'s warned setter.** Verified fact 1 splits
the problem cleanly: `OBS-23`'s per-key push and restore need only `Fiber[]=`, which warns nothing; `OBS-24`'s
"immutable snapshot … reinstall … restore that thread's prior context afterward (including on exception)" is
the whole-map operation `OI-13` records, and `Fiber#storage=` warns on every call at the default warning level
against a gate set that fails the build on warnings, and behaves differently on the 3.2 floor for `= nil`.
Three routes: implement the restore per key over the union of the captured and prior key sets, which stays
inside `Fiber[]=` and never touches the warned setter — and which also decides whether `OBS-10`'s "Keys with
null values MUST be skipped" is a live clause, since `Fiber[:k] = nil` deletes rather than stores; wrap the
setter in a scoped `Warning.warn` filter, which is not process-global and is therefore permissible where
`Warning[:experimental] = false` is not; or take an `NFR-7` waiver carrying its reason. `5b` owns `OBS-24`
and `5c` owns `OBS-23`, so the decision is stated once and cited by the other. **The floor and ceiling
behaviour must be re-run before this is decided** — this document ran only 3.4.10.

**R13 — `5c`: `OBS-22`'s scope handle against `OBS-25`'s cached-singleton clause.** `OBS-22` requires
activation to "return a scope handle that, when closed, **restores the previously-active span**", and to
restore even when the guarded code throws. `OBS-25` requires "a no-op Span whose current-scope is a **cached
singleton**" and that "Selecting a no-op path MUST NOT allocate per call". A handle that restores a previous
span carries per-activation state and therefore cannot be a singleton on the recording path; the no-op path
can be, because there is nothing to restore. `5c` states the split, and states where the previously-active
span is stored — a `Fiber[]` slot, a stack in fiber storage, or a closure — knowing that `OBS-23` makes the
same close restore two diagnostic-context keys "to their prior value (or remove it if previously unset)" and
that the two restores must be one `ensure`.

**R14 — `5c`: whether `OBS-29`'s lifecycle wiring ships here or with the pillar steps.** `OBS-29` ends: "This
is a documented emission contract; **pipeline/transport wiring to emit it is a follow-up, so it is not yet
runtime-enforced.**" §8.1 says the ordering "is asserted by an ordering test". The per-attempt half of
`OBS-28`'s vocabulary — attempt started, attempt failed with next delay, retries exhausted — has no emitter
until phase 6's retry step exists, and the transport milestones have none until phase 8. `5c` decides whether
it ships the vocabulary plus an ordering test driven by a fake emitter (the reading this document expects, and
the one §8.1 describes), or files a deferral for the wiring with phase 6 and phase 8 named. It must not mark
`OBS-29` ✅ on the strength of a contract nothing emits without saying so in the row.

**R15 — `5c`: whether `DEF-30`'s condition is met.** The sweep above recommends **no**, on `SEAM-2`'s
enumeration: instrumentation is not one of the five core interface seams, phase 5 adds no fourth registry, and
the row's only sanctioned user is post-v1. `5c` states that reading in its own design — or, if it does ship a
registry for the tracer, meter or sink, reverses it and marks the row **UNSCHEDULED** with phase 5 named. A
row whose condition a phase met and declined without saying so is the failure the whole-register sweep exists
to prevent, and this is the only row in phase 5's window where the answer is an argument rather than a
lookup.

---

## Deviation Ledger

**Empty.** This document decides no deviation from the reference contract. Every mechanism substitution phase
5 relies on is already catalogued in
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` — items 4 (cooperative
cancellation, which is where `CFG-17`, `CFG-20` and `CFG-21` sit), 5 (the unsatisfied MUSTs, which `CFG-20`
does not join), 7 ("standard library" narrowed to what is stable, which is `logger`'s row and `OBS-2`'s), 16
(the four-tier chain with a substituted third source) and 17 (the interruptible sleep as a cancellable queue
wait) — and is cited above rather than re-argued. The sub-phase designs will have ledgers of their own; a
deviation decided by any of them is numbered `P5-<n>` and consolidated into design §10.

**One correction to the roadmap, stated here because the roadmap requires a corrected cell to be corrected in
place with the correction stated.** The segmentation rule's phase-5 bullet reads: "**Phase 5 (78 IDs),
expected 5a configuration, 5b instrumentation and observability.** The cut follows the §15/§16 line and the
order is a real, if soft, dependency: `OBS-35`'s log-level resolution wants `CFG`'s layered lookup, which
design §10.16 records alongside the configuration chain, so 5a leads deliberately. 5b is where
`CTX-14`/`CTX-15`'s instrumentation bundle gets its `OBS-25`/`OBS-26` sentinels populated."

Three things in it are corrected and one is confirmed.

- **The cut is three ways, not two.** The §15/§16 line is adopted as one of two boundaries; the second falls
  inside chapter 15 at the §15.4/§15.5 line, giving `5a` 38, `5b` 27 and `5c` 13. The letters `5a` and `5b`
  keep the roadmap's meanings for configuration and for the logging half; `5c` is new.
- **The order is a CONVENIENCE, not a dependency, soft or otherwise.** `OBS-35` is a SHOULD, and the
  `CFG`↔`OBS` edges run both ways: `CFG-24` and `CFG-25` require a **warning log** on invalid proxy
  configuration and `CFG-21`'s best-effort close is `DEF-27`'s second disposal route, both of which need
  §8.1's facade. §10.16 is one already-argued deviation that both segments implement and neither derives.
  `5a` still leads, with three convenience reasons stated above.
- **The sentinels are populated in `5c`, not in `5b`.** `OBS-25`, `OBS-26` and `OBS-27` are tracing
  requirements and travel with `OBS-21`–`OBS-24` and the metrics SPI. `DEF-37` is `5c`'s row and phase 4a's
  five-clause handshake is `5c`'s contract.
- **Confirmed unchanged:** the phase-5 row's ID ranges and the count. `CFG-1`–`CFG-38` and `OBS-1`–`OBS-40`
  sum to 78, verified mechanically against appendix C, and no requirement ID moves to another phase.

**Two consequences outside this document's own scope to fix, recorded so they are not discovered later.**

- **`CLAUDE.md`'s phase-directory claims sentence goes stale the moment this document is filed.** It currently
  reads "There are five phase directories under `docs/work/*/`" and enumerates `phase0/` through `phase4/`.
  Filing this document creates `docs/work/mvp/phase5/` and makes it six. The probe's `claims` check reads that
  numeral, so this one **is** mechanically caught — unlike the roadmap's own former "`mvp/` is the only
  delivery and it is empty" — and it is corrected by hand in the change that files this document, together
  with the phase-5 entry in the enumeration.
- **The `knowledge-lookup` skill's audit-group table gained a tenth row**, *Observability, configuration and
  redaction*, added before the group was run per the roadmap's first retrospective rule and phases 3a's and
  4's precedent. That is an edit to `.claude/skills/knowledge-lookup/SKILL.md` and not to a frozen tree.
