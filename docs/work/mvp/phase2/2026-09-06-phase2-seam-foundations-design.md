# Phase 2 — Seam Foundations

**Status:** Draft, approved for planning.

## Purpose

Phase 2 builds the interface layer the rest of the SDK plugs into: what a transport is, what a
codec is, what an async future is, what "resolve a provider" means when there is no classpath to
scan, what closing something means, and how an operation description becomes a `Dexpace::Request`.
Nothing here talks to a socket. Everything here is the shape a later phase — and, more to the
point, a third-party adapter author this project will never meet — has to fit.

It is the second phase that ships domain code and it makes four decisions the remaining eight
phases inherit whether or not they re-read this document: what the async pivot is and who owns it
(roadmap cross-phase obligation 5), what a registry does in each of the five branches `SEAM-5`
fixes, what close means and who is allowed to do it, and what a seam-level failure raises.

Three of those decisions were forced by facts verified on real interpreters during planning rather
than by taste, and each is stated in full below with the evidence.

- **`URI::RFC3986_PARSER.join` and `URI::Generic#merge` both produce `https://host/pets` for base
  `https://host/c?sig=1` and operation path `/pets`** — dropping the `/c` segment *and* the `sig`
  query that `SEAM-27`'s own conformance example requires to survive. RFC 3986 reference
  resolution is not `SEAM-27`'s composition rule, and design §3.5's "base-URL composition uses
  `URI.join`/`URI#merge`" cannot be followed here.
- **A bare `Thread` inside `module Dexpace::Async` resolves to Ruby's `Thread` until
  `dexpace-async-thread` is required, and to `Dexpace::Async::Thread` afterwards** — so core's own
  suite, which never loads that gem, is structurally blind to the bug. Phase 2 is the first phase
  that writes core code inside `Dexpace::Async`.
- **`Gem` is undefined under `ruby --disable-gems`**, so `DEF-21`'s registration-time version
  assertion cannot be built on `Gem::Requirement` without acquiring a dependency on RubyGems being
  loaded, which is not something a library may assume and which `rubygems` is not on phase 0's
  require allowlist to make safe.

Phase 2 ships no transport, no codec, no executor and no pipeline. Its tests need none of them:
every seam here is exercised against an in-memory fake that implements only that seam.

## Governing documents

Five, in the roadmap's order, all binding here:

- `docs/product-spec/03-pluggable-seams-and-extension-model.md` — this phase's normative chapter;
  `docs/product-spec/02-architectural-principles.md` for `SEAM-1`, `SEAM-2` and `SEAM-13`; and
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md`, which is the **only**
  normative statement of `SEAM-15`, `SEAM-20`, `SEAM-22`, `SEAM-23` and `SEAM-28` — see "What the
  gap IDs actually required" below.
- `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.1–§3.7 in full — the retired
  byte-stream seam, the sync transport duck type, the async pivot and its check-after-resume rule,
  the serde seam's four encode profiles, the operation projection, discovery-by-`require`, and the
  close/ownership rules; §2.4 for the zero-dependency invariant; §10 items 3, 8 and 9 for the
  pivot, the discovery substrate and `SEAM-10`'s vacuity; §11 items 3, 5, 6, 8 and 14 for the
  ambiguities this phase resolves; §12's `SEAM` row for the coverage index.
- The Ruby styleguide, `styleguide/ruby/`, queried through the corpus — chapters 3, 6, 9, 10, 11,
  12 and 14. Binding except where a note under `docs/knowledge/notes/` records otherwise, and this
  phase files four such notes.
- `CLAUDE.md` — the bundled-gem hard rule, the domain-model construction pattern, the constraints
  that will bite (all of which land here: `Thread::Mutex` per-fiber ownership, the interrupt ban,
  `URI::RFC3986_PARSER`, `Encoding::BINARY`, `Ractor` never load-bearing), the requirement-ID
  conventions and the public-API definition.
- `docs/README.md` — the ownership table and the `docs/work/` naming rules.

## Scope

### Requirement IDs in scope

**Thirty numbered IDs, `SEAM-1`–`SEAM-30`** — the roadmap's phase-2 row, which reads
`SEAM-1`–`SEAM-30` and nothing else. All thirty get a checklist row.

**`SEAM-29`'s row is a cross-reference, not a re-satisfaction.** Phase 1 honoured both of its MUSTs
ahead of this phase — `Dexpace::Model.required!` for the uniform `<name> is required` message and
`Dexpace::Builder` for the shared generic builder contract — on the roadmap's own instruction, and
`SEAM-29` is a row in **phase 1's** checklist. Dropping it here would leave an ID inside this
phase's stated range with no row in the phase that owns the range, which is precisely the failure
the one-row-per-ID convention exists to prevent, so the row stays and names phase 1's task.
Everything phase 2 builds depends on it: every seam-level failure raises through phase 1's error
root, and `Dexpace::Operation` builds its request through phase 1's `Request::Builder`.

Where the thirty land, in the design's own §3 order:

| IDs | Where | Disposition phase 2 expects |
|---|---|---|
| `SEAM-1`, `SEAM-2` | Standing: phase 0's three zero-dependency gates, plus this phase's registry error text and `.conforms?` predicates | ✅ |
| `SEAM-3`, `SEAM-4` | The byte-stream provider seam, retired (§10.1) | 🚫, named reason |
| `SEAM-5`–`SEAM-9` | `Dexpace::Registry` | ✅ |
| `SEAM-10` | Vacuous in Ruby (§10.9), replaced by the version-skew guard this phase builds | N/A + `DEF-21` picked up |
| `SEAM-11`, `SEAM-13` | `Dexpace::Transport` | ✅ |
| `SEAM-15` | `Dexpace::ClosedError` and the documented rule that an *owning* transport raises it | ✅ for the class and the rule; **no raise site**, because this phase ships no owning transport — phase 8's adapters are the first, and `dexpace-conformance` asserts it per adapter (`DEF-22`) |
| `SEAM-12` | The seam's shape, which forces no per-request state onto shared storage | ⏳ `DEF-22` — concurrency safety is a property of an implementation and this phase ships none |
| `SEAM-14` | `Dexpace::Closeable`, taken by both `SEAM-18` bridges | ✅ |
| `SEAM-25` | `Dexpace::Closeable`'s idempotent, ownership-aware release | ✅ for the release; the clause "and emits the lifecycle event" is `DEF-31`, phase 5 |
| `SEAM-16`, `SEAM-17`, `SEAM-30` | `Dexpace::Async::Future`, `Dexpace::Async::Completer`, `Dexpace::AsyncTransport` | ✅ |
| `SEAM-18` | `Dexpace::Bridge::AsyncOver` and `Dexpace::Bridge::SyncOver` | ✅ |
| `SEAM-19`–`SEAM-21`, `SEAM-23` | `Dexpace::Serde` and its failure hierarchy | ✅ |
| `SEAM-22` | Replaced by the witness protocol (§10.14); the seam-level half — `#load` takes an explicit witness and there is no witness-less overload — is fixed here | 🚫 mechanism, named reason |
| `SEAM-24` | Cross-thread diagnostic propagation | ⏳ `DEF-1`, rides on `DEF-11` |
| `SEAM-26`, `SEAM-27` | `Dexpace::Operation` | ✅ |
| `SEAM-28` | Stable operation identifier | ⏳ `DEF-1`, target phase 5 (given by this phase's sweep) |
| `SEAM-29` | Phase 1's `Dexpace::Model` and `Dexpace::Builder` | ✅ in phase 1 |

`XCUT-23` (deterministic single-implementation seam resolution) and `XCUT-13` (idempotent,
non-blocking close) are phase 9's to disposition, but both are *implemented* here, because they
restate `SEAM-5` and `SEAM-14`/`SEAM-25` in the cross-cutting chapter. Phase 2 does not claim them;
it leaves them satisfiable. `IO-39`'s lock-free registry reads are retired with the provider seam
(§12's `IO` row) and are phase 3's row, not this phase's — but the surviving registry implements
the property anyway, because three seams still need it.

### Out of scope, explicitly

| Excluded | Owning phase |
|---|---|
| `SEAM-29`'s implementation — the construction contract and the `<name> is required` message | 1 — depended on here, not re-satisfied |
| `HTTP-*`, including `HTTP-1`/`HTTP-2` | 1 |
| `IO-1`–`IO-42` — the byte-stream *contract* the retired seam used to hide | 3 |
| `CTX-*`, and the context chain `SEAM-28`'s operation identifier would attach to | 4 |
| `PIPE-33`'s pipeline-level sync↔async bridge, which reuses this phase's `SEAM-18` bridges rather than building a second pair | 4 |
| `RECOV-12`'s suppressed-exception trail, and therefore one of `close_quietly`'s two disposal routes | 4 — `DEF-24` |
| `CFG-15`–`CFG-21`'s clock, deadlines and interruptible delay, and therefore `#value(deadline:)` | 5 — `DEF-28` |
| `OBS`/§8.1's instrumentation facade, and therefore `close_quietly`'s other disposal route, `SEAM-25`'s lifecycle event, and any presence-gated auto-activation | 5 — `DEF-27`, `DEF-31`, `DEF-30` |
| `SERDE-*` — the witness protocol, `Tristate`, and every concrete codec behaviour | 7 |
| Every concrete adapter: `dexpace-transport-net_http`, `dexpace-transport-async_http`, `dexpace-async-thread`, and `dexpace-conformance`'s assertion objects | 8 — `DEF-22` |
| `ASYNC-3`, `ASYNC-4` and `PIPE-33`'s interrupt clause, the port's three known-unsatisfied MUSTs | 8 marks them, `DEF-18`; §10.5 |

**The three unsatisfied MUSTs are not re-opened here, and the connection is worth stating because
this phase is where it originates.** §10.5's gap is a consequence of the shape phase 2 fixes: the
pivot's cancellation is cooperative, because Ruby's only pre-emption primitives are `Thread#raise`
and `Thread#kill` and §8.3 forbids them. `Dexpace::Async::Future#cancel` therefore settles the
future promptly and asks the producer to notice at its next resume point; it cannot reach into a
worker blocked in a C-extension read. `ASYNC-3` and `PIPE-33`'s interrupt clause are that
limitation observed at a real adapter, which is phase 8. Phase 2's obligation is to make the
cooperative contract *stateable and testable* — the check-after-resume rule and
`Completer#on_cancel` — not to close the gap, and it does not claim to.

**No segmentation design.** The roadmap's segmentation rule reaches a build phase whose ID count
"clearly exceeds earlier phases'", or that spans more than one ID-bearing spec chapter, or that
ships more than one gem. Phase 2 is 30 IDs — fewer than phase 1's 42 checklist rows and fewer than
every later build phase — in one chapter, shipping one gem. The roadmap's own list of expected
sub-phases starts at phase 3 and does not name phase 2. One phase, one design, one plan; the
segmentation that phase 2 does need is between *tasks*, which the plan supplies.

## Prerequisite

**Phases 0 and 1, in full.** Phase 2 adds files into a tree that already has seventeen blocking
gates and a validated wire model. Specifically it relies on:

- **Phase 1's construction contract.** `Dexpace::Model` (`required!`, `own`, `frozen_string`, and
  the `#with` that re-validates on Ruby 3.2), `Dexpace::Builder`, `Dexpace::Error` as a **module**,
  and `Dexpace::InvalidArgumentError < ::ArgumentError`. Every error class phase 2 defines includes
  the module; every `Data` type phase 2 exposes publicly includes `Model`.
- **Phase 1's wire model**, consumed rather than extended: `Dexpace::Request` and
  `Request::Builder` (`Dexpace::Operation#build_request` returns one), `Dexpace::Response` (the
  transport seam's return type), `Dexpace::Headers` and `Headers::Builder`, `Dexpace::Query` and
  `Query::Builder` (`SEAM-27`'s RFC 3986 query rendering *is* `Query#encode`),
  `Dexpace::PercentEncoding.encode_component` (`SEAM-27`'s single-path-segment encoding *is* that
  function), `Dexpace::URL.parse!` (the base URL), `Dexpace::Method`, `Dexpace::RequestOptions`.
- **Phase 1's construction rule**, which binds every model phase 2 adds: no `.build` is a bare
  `new` wrapper; validation lives in the `Data` type's `initialize`; a validating constructor
  coerces through the member type's own factory.
- **The gates**, unchanged and unlowered — `rubocop` with phase 0's five custom cops, `rbs:validate`,
  `steep` with `core` strict, `test:gems` under `-w -W:deprecated` with the SimpleCov floor,
  `gates:require_allowlist`, `gates:rbs_surface`, `gates:surface_snapshot`, `gates:sig_diff`,
  `gates:gemspec_audit`, `gates:clean_bundle`, `gates:single_instance`.
- **The require allowlist**, unchanged: `monitor`, `uri`, `stringio`, `strscan`, `time`, `date`,
  `securerandom`, `digest`, `openssl`, `forwardable`, `set`, `singleton`. Phase 2 adds **no name to
  it** and uses exactly one entry, `uri` (already required by phase 1's `URL`). `Thread`,
  `Thread::Mutex` and `Thread::Queue` are core classes needing no `require`; `rubygems` is not on
  the list and phase 2 does not put it there — see P2-7.

**What phase 2 changes about the gates' denominator.** `gates:single_instance` carries a
`Dexpace::VERSION`-versus-gemspec assertion today and gains its runtime counterpart here: the
registration-time skew check `DEF-21` names. `gates:surface_snapshot` gains this phase's constants
in one reviewed regeneration, and `gates:rbs_surface` becomes genuinely load-bearing for the first
time — `NFR-11`'s whole point is that no third-party async type appears in a public signature, and
this is the phase that defines the async surface it would have appeared in.

## Corpus reading, and what it settled

The phase-start pair was run before anything here was written.
`ruby scripts/knowledge.rb --section conflicts --brief` returned nineteen entries across fourteen
topic files **before this phase's own four notes landed** (it reads 22 across 15 after them), of
which the six styleguide-versus-design conflicts **all print `[overridden by notes/…]`**; none is
open, and none of the six is re-litigated here.
`--origin note --brief` returned sixteen note entries across nine files, again before this phase's
four — twenty across eleven after them — the six conflicts plus
phase 0's five and phase 1's five — and nothing in that set contradicts this phase's plan. Two are
load-bearing here and are cited at their point of use: `module-organization/6e69ad04` (public
constants are flat; directories organise files) and `error-handling/d2eadac4` (`Dexpace::Error` is
a module, `Dexpace::ArgumentError` is never defined).

`ruby scripts/knowledge.rb --prefix-info SEAM` reports 30 canonical IDs, 23 MUST / 5 SHOULD / 2
MAY, owning chapter `docs/product-spec/03-pluggable-seams-and-extension-model.md`, and 28 of 30
substantive with **zero roll-ups**. `--gaps SEAM` names the two uncited: `SEAM-22` and `SEAM-28`.
No `--req` query run for this phase returned an `[appendix-B roll-up]` tag, so the three-step
roll-up path was not needed; the `--req` clusters run were `SEAM-3,SEAM-4`,
`SEAM-5..SEAM-10`, `SEAM-11..SEAM-15`, `SEAM-16,SEAM-17,SEAM-18,SEAM-30`, `SEAM-19..SEAM-23`,
`SEAM-24,SEAM-25` and `SEAM-26,SEAM-27,SEAM-28`. `--phase 0 --brief` shows phase 0's documents
already cite `SEAM-1`, `SEAM-2`, `SEAM-3`, `SEAM-22`, `SEAM-28` and `SEAM-30`; `--phase 1 --brief`
shows phase 1 citing `SEAM-1`, `SEAM-26`, `SEAM-27`, `SEAM-29` and `SEAM-30`.

### What the gap IDs actually required, and a correction to the roadmap

The roadmap's gap paragraph says to read `SEAM-22` and `SEAM-28` "out of
`docs/product-spec/03-pluggable-seams-and-extension-model.md`", and `--gaps SEAM` prints the same
pointer. **Neither ID appears in that chapter.** The chapter's prose carries 22 of the 30 SEAM
IDs; `SEAM-1`, `SEAM-2`, `SEAM-13` and `SEAM-29` are stated in
`docs/product-spec/02-architectural-principles.md`; and **`SEAM-15`, `SEAM-20`, `SEAM-22`,
`SEAM-23` and `SEAM-28` appear nowhere in the specification's prose at all** — appendix C is their
only normative statement. The CLI's pointer is derived mechanically from appendix C's subsystem
cell, so it names the subsystem's chapter rather than asserting the ID is in it; the roadmap
inherited the pointer and repeated it as an instruction. Filed as `OI-1`, because a phase told to
read a chapter that does not contain the requirement will either read the wrong thing or conclude
the specification is missing.

So this phase read appendix C rows 28 and 34 verbatim, and both roadmap expectations hold:

- **`SEAM-22` (MUST)** — "A full generic type capture used for deserialization MUST be created with
  a concrete type argument at the call site (on the JVM: an anonymous subclass). Construction MUST
  reject a capture whose argument is an unresolved type variable … The capture exposes both the
  full generic type and its erased raw class for a fast non-parametric path." Confirmed: the
  mechanism is a JVM reflection artefact, §10.14 replaces it with the witness protocol, and the
  witness is §7.3's, which is phase 7's. What phase 2 can and does fix is the clause that survives
  the substitution: **`#load` takes an explicit witness argument and there is no witness-less
  overload to fall into** (§3.4's own words). Nothing else about `SEAM-22` is buildable here.
- **`SEAM-28` (MAY)** — "The operation projection MAY carry a stable operation identifier for
  instrumentation/tracing; when present it is attached to the request's context chain but MUST NOT
  affect the assembled request's URL, headers, or body." Confirmed a MAY, and confirmed to depend
  on two things phase 2 does not have: the context chain (`CTX`, phase 4) and a consumer for the
  identifier (instrumentation, phase 5). Left deferred under `DEF-1`, with a target phase supplied
  by the sweep below.

The reading budget these two required was appendix C plus §7.3 and §10.14 — about a page. No other
phase-2 ID needed direct specification reading.

### The audit groups this phase ran

Five groups from the `knowledge-lookup` skill's table, each named with the query that produced it,
then its result. A group not in the table would have been added to the table before running, per
the roadmap's first Node-retrospective rule; none had to be.

| Audit group | Query | Result |
|---|---|---|
| *Public API surface* | `--topic api-design,http-domain-model,documentation,module-organization,error-handling --section rules` — 150 entries | One rule with no note, and it is this phase's: `module-organization/c84bf75e` ("requiring a file must have no load-time side effects — no network call, database query, **global registry mutation**, or `puts` at file scope"), which design §3.6 and §10.8 contradict head-on. Resolved by note. Adopted and load-bearing: `api-design/88e6bf12` (accept the narrowest duck type, return a concrete frozen value — which *is* the seam contract), `api-design/c15b29ce`, `documentation/80beb95e` and `/42d8cbf4`, `module-organization/1828a984` (one public constant per file). Already resolved and applied unchanged: `module-organization/6e69ad04`, `/2a4cc61d`, `error-handling/d2eadac4` |
| *Gem layout, zero-dependency core* | `--topic package-and-dependency-layout --section rules,constraints` (14) and `--prefix SEAM --section rules` (38) | Clean. `package-and-dependency-layout/fa303aa7` (zero `add_dependency` in core) and `/be92b361` (the logging sink is a duck type; core never requires `logger`) are adopted and are what shapes the executor duck type below. `porting-method/bf484e8e` (P14 — define a seam as a structural subset of the ecosystem's dominant shape) is the argument for `#call` and is cited at the transport seam |
| *RBS / Steep typing* | `--chapter 3 --section rules` and `--topic type-system,data-modeling --section rules` | One rule with no note, and it is this phase's: `data-modeling/a13e9ffe` ("define small, duck-typed interfaces as Sorbet abstract modules with `sig { abstract }` stubs, and have concrete implementations include them"). Resolved by note. Adopted verbatim and load-bearing: `data-modeling/5730bc9a` ("if the real intent of shared state is a process-global registry, use an explicit singleton module with documented mutability rather than a class variable") — which is exactly what `Dexpace::Transport`, `Dexpace::AsyncTransport` and `Dexpace::Serde` are; `data-modeling/3775e9d7` and `/fde152ef` (`extend self` or `class << self`, never `module_function`); `type-system/e4969b16` (`fetch` over `[]`) |
| *Fiber scheduler, thread safety* | `--prefix ASYNC --section rules` (25), `--topic concurrency-and-async --section rules` (75), `--chapter 9 --section rules` (38) | Four rules with no note, all one family: `concurrency-and-async/b44d400b`, `/abfb9ed9`, `/960d89ec` and `/0e11c51d` — prefer `concurrent-ruby`'s `Concurrent::Map`/`Concurrent::Array`/`Concurrent::AtomicFixnum` over hand-rolled `Mutex` synchronisation. Resolved by note. Adopted and load-bearing: `/c0fab747` (smallest critical section), `/ee54cb68` and `/f261a143` (never hold a lock across I/O), `/54d8bb89` and `/2c743901` (immutable `Data` at every concurrency boundary), `/b9d20c94` (never `Timeout.timeout`), `/611b9392` (check-after-resume). Routed onward to **phase 8**, with no phase-2 obligation because phase 2 ships no pool: `/6764e0b5`, `/dc345cae`, `/df658d73`, `/3692970f`, `/047644ea`, `/dd8e6d2d` — the bounded-pool and deterministic-teardown rules, which bind `dexpace-async-thread` |
| *Styleguide-vs-design conflicts* | `--section conflicts --brief` | Six, all `[overridden by notes/…]`. None open |

*Minitest conventions* was run as a sixth (`--chapter 11 --section rules`, 23 entries;
`--topic testing,assertions --section rules`, 29) and is clean: the only three rules without a
resolution — `assertions/df75bd2e`, `testing/de6fe7e3`, `testing/79254878` — already print
`[overridden by notes/…]`. Three shape the test plan rather than the code: `testing/f36a19cd`
(property-style tests mandatory for parsers and value objects with parse-constructor invariants,
which reaches `Dexpace::Operation`), `testing/62f8f4ec` (every error boundary gets a negative test
asserting class, message and no partial side effect) and `testing/4ef070df` (every test alone, in
any order, seed never overridden).

### Four notes filed against the corpus by this phase

Written before the plan, because a resolution recorded only in a design document is re-litigated by
whoever reads the corpus next.

- `docs/knowledge/notes/module-organization.md`, `## Conflicts` — **require-time seam
  self-registration is the discovery substrate, and it is the one load-time side effect this
  repository permits.** Resolves `module-organization/c84bf75e`.
- `docs/knowledge/notes/data-modeling.md`, `## Conflicts` — **a seam is a duck type plus a
  `.conforms?` predicate plus an RBS interface type, never a Sorbet abstract module.** Resolves
  `data-modeling/a13e9ffe`.
- `docs/knowledge/notes/concurrency-and-async.md` (new file), `## Conflicts` — **core's shared
  mutable state is a frozen snapshot swapped under a `Thread::Mutex`, because `concurrent-ruby` is
  a gem.** Resolves `concurrency-and-async/b44d400b`, `/abfb9ed9`, `/960d89ec` and `/0e11c51d`.
- `docs/knowledge/notes/url-and-query-encoding.md` (new file), `## Superseded` — **`SEAM-27`'s
  base-URL composition is not RFC 3986 reference resolution, and `URI.join` is banned by a phase-0
  cop; the sanctioned form where resolution *is* wanted is `URI::RFC3986_PARSER.join`.** Supersedes
  `url-and-query-encoding/ef5ecf25` and corrects `redirect-handling/d4885fbc`, which is phase 6's
  and would otherwise walk into the cop.

### The verified Ruby facts this phase is built on

Verified on 2026-09-06 against three installed interpreters — 3.2.11, 3.4.10 and 4.0.6 — the same
discipline phases 0 and 1 applied. Where a fact was checked on only two, the two are named.

1. **RFC 3986 reference resolution is not `SEAM-27`'s composition rule.** On 3.2.11 and 4.0.6
   alike, `URI::RFC3986_PARSER.join("https://host/c?sig=1", "/pets")` is `"https://host/pets"` and
   `URI::RFC3986_PARSER.parse("https://host/c?sig=1").merge("/pets")` is the same. `SEAM-27`'s own
   conformance step requires `host/c?sig=..` + `/pets` → `host/c/pets?sig=..&<opquery>`: both the
   base path segment and the base query must survive, and reference resolution discards both. The
   composition is therefore hand-built (§ "Operation" below), verified against six cases plus the
   fragment rejection on both interpreters. Reference resolution keeps its place where the design
   actually needs it — `REDIR-13`'s wire-exact re-resolution, phase 6 — and there the sanctioned
   spelling is `URI::RFC3986_PARSER.join`, which exists on every supported Ruby, because
   phase 0's `Dexpace/NoUriDefaultParser` cop bans `URI.join`. Also verified: `URI::Generic#merge`
   uses the **receiver's** parser (`URI::RFC3986_PARSER.parse(base).parser` is
   `URI::RFC3986_Parser` on 3.2.11 and on 4.0.6), so merging into a parser-pinned URI is safe; and
   `URI::InvalidURIError`'s message differs by a space between 3.2.11 (`bad URI(is not URI?)`) and
   4.0.6 (`bad URI (is not URI?)`), so no test may assert on it.
2. **A bare `Thread` inside `module Dexpace::Async` rebinds when the adapter gem loads.** Verified
   on 3.2.11 and 4.0.6: a method defined lexically inside `module Dexpace; module Async` returns
   Ruby's `Thread` for a bare `Thread` before `Dexpace::Async::Thread` is defined and
   `Dexpace::Async::Thread` afterwards, and `Thread.new` then fails with
   `NoMethodError: undefined method 'new' for module Dexpace::Async::Thread`. Core's own suite
   never requires `dexpace-async-thread`, so the failure is invisible to it. Phase 0 recorded the
   hazard for the adapter's own code; phase 2 is the first phase where **core** writes code inside
   that namespace. Two mitigations, both shipped: `::Thread`, `::Queue` and `::Mutex` everywhere
   under `Dexpace::Async`, enforced by a sixth custom cop (Design §9 Addendum A1), and a core test
   that defines a stand-in `Dexpace::Async::Thread` constant and re-exercises the pivot, which is
   the only way core's suite can catch it.
3. **`Gem` is undefined under `ruby --disable-gems`.** Verified on 3.2.11 and 4.0.6: `defined?(Gem)`
   and `defined?(Gem::Version)` are both `nil`. `DEF-21`'s registration-time assertion therefore
   compares `~> MAJOR.MINOR` by hand rather than through `Gem::Requirement`, and `rubygems` stays
   off the require allowlist. Cross-checked in the other direction: with RubyGems loaded,
   `Gem::Requirement.new("~> 0.1").satisfied_by?(Gem::Version.new("0.1.3"))` is `true` on both
   interpreters, which is what the phase's test compares the hand-rolled comparison against over a
   grid of versions.
4. **`Thread::Queue#pop` routes through a registered `Fiber.scheduler`.** Verified on 3.2.11,
   3.4.10 and 4.0.6 with a hand-written probe scheduler: a `Fiber.schedule`d consumer blocking on
   `Thread::Queue#pop` produces exactly `[[:block, "Thread::Queue"], [:unblock, "Thread::Queue"]]`
   on the scheduler, and the OS thread is never parked. Verified twice with two differently shaped
   probe schedulers, because the first shape is fragile for unrelated reasons. This is the fact
   design §3.3's scheduler-transparency claim rests on, and it is why the pivot's blocking wait is
   a queue wait and never a `Kernel#sleep` poll. One further 4.0-only observation: Ruby 4.0.6 warns
   `Scheduler should implement #fiber_interrupt` when a scheduler omits that method, and phase 0's
   `Warning.warn` override turns a warning into a test failure — so the phase's scheduler-probe
   test defines `#fiber_interrupt`, verified to silence it.
5. **`Thread::Queue#pop`'s `nil` is ambiguous three ways.** Verified on all three: `pop(timeout:)`
   exists on the 3.2 floor and returns `nil` on expiry; `pop` on a closed queue returns `nil`; and
   `pop` of a pushed `nil` returns `nil`. The pivot therefore never carries its value through the
   queue. The queue is a wake-up signal only; the settled outcome is written to an instance variable
   under the mutex and read back, which is also what makes a future that settles with `nil` (never
   reachable through the public API, but reachable through `Completer`) distinguishable from an
   unsettled one.
6. **`Thread::Mutex` is non-reentrant and its ownership is per-fiber.** Re-verified on all three:
   locking a held mutex from the same fiber raises `ThreadError: deadlock; recursive locking`, and
   from a second fiber of the same thread raises `ThreadError: deadlock; lock already owned by
   another fiber belonging to the same thread`. Every mutex in this phase is therefore held across
   a flag flip or a hash swap and across nothing else — never across a callback, a `warn`, a
   `#release`, or any operation that may suspend. (An aside, recorded because it is the blunter
   version of the same rule: the first probe scheduler written for fact 4, which suspends with
   `Fiber.yield` from inside its `#block` hook, aborted the interpreter on both 3.2.11 and 4.0.6
   when a `Thread::Mutex` was contended under it. The fault is the probe's, not Ruby's, and no
   design claim rests on it.)
7. **`Kernel#warn` routes through `Warning.warn`, and is silent when `$VERBOSE` is `nil`.** Verified
   on 3.2.11 and 4.0.6: a message passed to `Kernel#warn` reaches an overridden `Warning.warn`,
   while `$stderr.puts` does not; and with `$VERBOSE = nil` the call is suppressed before it gets
   there. `SEAM-8`'s warning is a SHOULD, so a channel the host can silence is the right one — but
   it means the phase's `SEAM-8` test must set `$VERBOSE` deliberately and must add the first entry
   to phase 0's zero-entry warning allowlist, with the comment phase 0 requires.
8. **A frozen `URI::Generic` `dup`s to an unfrozen copy whose `#path=`/`#query=` work**, verified on
   3.2.11 and 4.0.6, and mutating the frozen original raises `FrozenError`. That is what lets
   `Operation#build_request` compose against phase 1's frozen base URL without a re-parse of a
   re-rendered string.
9. **The registry shape resolves exactly once under contention.** A prototype of the design below —
   a frozen `Data` snapshot swapped under a `Thread::Mutex`, reads unsynchronised — resolved a
   single instance from 32 concurrent threads with exactly one factory invocation and one scan on
   3.2.11 and 4.0.6, and an unresolved registry re-scanned on every access and picked up a
   later registration.

## Module Layout

Every file phase 2 creates. `sig/` mirrors `lib/` one file per file and ships inside the gem;
`test/` mirrors `lib/` one file per file and does not ship. All paths under `gems/dexpace-core/`
unless stated otherwise.

```
lib/dexpace.rb                              MODIFIED: requires for the tree below
lib/dexpace/error/seam_error.rb             Dexpace::SeamError
lib/dexpace/error/closed_error.rb           Dexpace::ClosedError
lib/dexpace/error/cancelled_error.rb        Dexpace::CancelledError
lib/dexpace/closeable.rb                    Dexpace::Closeable   (+ Dexpace.close_quietly)
lib/dexpace/hooks.rb                        Dexpace::Hooks       (private_constant)
lib/dexpace/cancellation.rb                 Dexpace::Cancellation
lib/dexpace/cancellation/source.rb          Dexpace::Cancellation::Source
lib/dexpace/async/settlement.rb             Dexpace::Async::Settlement
lib/dexpace/async/completer.rb              Dexpace::Async::Completer
lib/dexpace/async/future.rb                 Dexpace::Async::Future
lib/dexpace/registry.rb                     Dexpace::Registry
lib/dexpace/bridge/async_over.rb            Dexpace::Bridge::AsyncOver
lib/dexpace/bridge/sync_over.rb             Dexpace::Bridge::SyncOver
lib/dexpace/transport.rb                    Dexpace::Transport
lib/dexpace/async_transport.rb              Dexpace::AsyncTransport
lib/dexpace/serde.rb                        Dexpace::Serde
lib/dexpace/serde/error.rb                  Dexpace::Serde::Error
lib/dexpace/serde/serialization_error.rb    Dexpace::Serde::SerializationError
lib/dexpace/serde/deserialization_error.rb  Dexpace::Serde::DeserializationError
lib/dexpace/operation.rb                    Dexpace::Operation

test/support/fake_transport.rb              the in-memory fake, required explicitly
test/support/fake_async_transport.rb
test/support/fake_codec.rb
```

Two files at the repository root, outside every gem:

```
.rubocop/cops/dexpace/qualified_core_constant.rb   the sixth custom cop (Design §9 Addendum A1)
.rubocop/test/cops_test.rb                          MODIFIED: the sixth cop's cases
```

Twenty new `lib/` files, nineteen `sig/` mirrors, nineteen `test/` mirrors, three test-support
files, one cop with its cases, and three already-existing files that gain content: `lib/dexpace.rb`,
`sig/dexpace.rbs` and the repository-root `test/fixtures/surface/dexpace-core.txt`.
`lib/dexpace/hooks.rb` is the one file with neither mirror: it is a `private_constant`, so it is not
public API by this repository's own definition -- no `sig/` signature, no YARD gate entry -- and a
test cannot name `Dexpace::Hooks` to exercise it directly. Its three call sites are where its
behaviour is asserted.

**The placement rule is phase 1's and is applied, not re-decided** (`module-organization/6e69ad04`,
deviation P1-1): a public constant the design names without a namespace is flat and its file sits
under a directory that organises rather than namespaces — `Dexpace::ClosedError` in
`lib/dexpace/error/closed_error.rb`, `Dexpace::Operation` in `lib/dexpace/operation.rb`,
`Dexpace::AsyncTransport` in `lib/dexpace/async_transport.rb`; a subsystem the design already names
with a namespace keeps it — `Dexpace::Async::Future`, `Dexpace::Serde::SerializationError`. Design
§3.3 names `Dexpace::Async::Future` and `Dexpace::Async::Completer`; §3.2 names
`Dexpace::Transport`; §3.4 names `Dexpace::Serde::SerializationError` and `DeserializationError`;
§3.5 names `Dexpace::Operation`; §3.7 names `Dexpace::Closeable`, `Dexpace.close_quietly` and
`Dexpace::ClosedError`; §3.3 names `Dexpace::Cancellation`. Every one of those names is taken from
the design rather than invented. **Constants the design's own §3 does not name**, and the reason for each: `Dexpace::Registry`
(P2-10), `Dexpace::AsyncTransport` (P2-1), `Dexpace::SeamError`, the `Dexpace::Bridge` namespace
holding both `SEAM-18` bridges (P2-13), `Dexpace::Cancellation::Subscription` (P2-14), and the
public methods P2-11 and P2-14 enumerate. `Dexpace::Hooks` is not among them: it is a
`private_constant` (P2-15) and therefore not public API by this repository's own definition. Every one of them
is `NFR-4`-locked at the first release tag, which is why each has a ledger row rather than a
comment.

`Dexpace.close_quietly` lives in `lib/dexpace/closeable.rb` beside the contract it serves. That
file therefore defines one public *constant* and one module function, which is what
`module-organization/1828a984` asks for; splitting a four-line helper into its own file to satisfy
a rule about constants would be the letter over the purpose.

---

## What a seam is in this port, stated once

Six of this phase's requirements say the same thing in six vocabularies, so the shape is written
down here and cited rather than repeated.

**A seam is three artifacts and no fourth.** (1) A **duck type** — a documented set of methods, with
no module to include and no class to inherit, so an object that already has the shape conforms
without an adapter (P14, `porting-method/bf484e8e`). (2) A **`.conforms?` predicate** on the seam's
own module, which is the runtime check a registry runs before it accepts a factory and which
`SEAM-2` is satisfied by, because core names the *shape* and never an implementation
(`transport-adapter/c3d2d69c`). (3) An **RBS interface type** in that seam's `sig/` file —
`interface _Transport` and the rest — which is what a consumer's own `steep check` sees at a
parameter. Assignability and runtime identity are different questions in Ruby and each artifact
answers one, exactly as phase 1 found for `SEAM-29`'s `Dexpace::Builder`.

**What a seam is not:** a Sorbet abstract module with `sig { abstract }` stubs, which is
`data-modeling/a13e9ffe`'s answer and needs `sorbet-runtime` in core's gemspec — the note above
resolves it; and not a nominal `include`-me module, which would make every existing Ruby object
that already has the shape need a wrapper and would put a `Dexpace::` constant into the *adapter's*
inheritance chain for no gain.

**Seam-level failures.** Two classes, two levels deep, both including `Dexpace::Error` so
`rescue Dexpace::Error` still catches everything (`error-handling/61ab4fb6`, `/d2eadac4`):

- **`Dexpace::SeamError < ::StandardError`** — a seam is in a state the caller must fix but did not
  pass in: zero providers registered, more than one with no explicit selection (`SEAM-5`), a
  version-skewed adapter (`DEF-21`).
- **`Dexpace::InvalidArgumentError`**, phase 1's — a caller mistake in an argument: installing a
  different provider over an installed one, registering a different factory under an occupied key
  (`SEAM-6`), a non-conforming object offered to a registry, a malformed operation template.
  `error-handling/5a185ba9` asks for a standard-library exception where one exactly fits, and
  `ArgumentError` exactly fits this and does not fit the first.

## `Dexpace::Registry` — discovery, install and conflict resolution

**Satisfies:** `SEAM-5`, `SEAM-6`, `SEAM-7`, `SEAM-8`, `SEAM-9`, `SEAM-10`, and `XCUT-23` for
phase 9. **Design:** §3.6 in full; §10.8; §2.3's version-skew guard. **Corpus:**
`seams-and-extensibility/4838ff28`, `/d740c615`, `/0ad49b6a`, `/f29f0752`, `/a049a720`, `/d781ca16`,
`/89cb68bc`, `/c8d621ef`, `/3db5e63f`; `data-modeling/5730bc9a`.

One class, instantiated once per seam and held in that seam's own module. Ruby has no classpath, so
§3.6 changes the substrate and keeps all five branches: **an adapter registers itself as a side
effect of being `require`d**, and "discoverable" means "the application has required this adapter".
Core ships an empty registry and never auto-requires an optional gem, which is what keeps `SEAM-1`
true, and the zero-candidate error names no gem, which is what keeps `SEAM-2` true in the error
path.

**The registry holds factories; the resolved slot holds one instance**, and conflating them is how a
port ends up comparing the wrong object (§3.6). `#register(key, factory, core:)` takes the adapter
class or any `#call`-shaped builder, because require-time registration happens before the
application has configured anything. `#resolve` builds the winning factory once and memoises the
instance. `#install(instance)` takes an instance.

**State is one frozen `Data` snapshot, swapped under a `Thread::Mutex`.** Five members —
`factories` (a frozen `Hash`), `resolved`, `handed_out`, `explicit` and `resolving` — so a reader
takes one unsynchronised read of a single reference and sees a consistent, fully-constructed, frozen
picture or the previous one, never a torn mixture. Writes serialise under the mutex, which is held
across the swap and across nothing else. That is `SEAM-9`'s three clauses implemented rather than
argued, and it is `IO-39`'s lock-free-read property surviving the seam that used to state it. The
alternative the styleguide prefers, `Concurrent::Map`, is a gem (note above).

**No factory call and no `.conforms?` call happens under that mutex**, and the `resolving` member
is what makes that possible. The obvious shape — build inside `synchronize` so the scan runs once —
deadlocks with `ThreadError: deadlock; recursive locking` the moment a factory resolves anything
from the same registry, because Ruby's `Thread::Mutex` is non-reentrant (verified), and it breaks
this design's own rule that a mutex is held across a snapshot swap and nothing else. Instead the
claim *is* a snapshot swap: the winner puts a `Thread::Queue` in `resolving` and builds outside the
lock, and every other caller blocks on that queue until the winner closes it. `SEAM-9`'s "a
concurrent first-access cannot run the discovery scan twice" survives with the scan unlocked, and
the wait is scheduler-transparent for the same reason the pivot's is. A resolution that raises
clears the slot and every waiter retries, which is `SEAM-7`'s re-evaluability rather than a
regression — and the slot is released in an `ensure`, not on a `rescue StandardError` path, because
a factory can raise a `LoadError` and a claim released only for `StandardError` leaves a closed
gate latched and every later `#resolve` spinning silently. An explicit `#install` that lands while
a build is in flight wins, and the built provider is discarded **and closed** through
`Dexpace.close_quietly`: a transport provider is the archetypal owner of a pool (`SEAM-14`), and
this phase already closes exactly this shape in `Completer#fulfil` (`SEAM-30`).

**The `resolving` slot therefore records the claiming fiber as well as the gate**, and a factory
that resolves the registry building it raises `Dexpace::SeamError` at that call. Without the owner,
that caller parks on the gate it took itself and never returns, and every later caller then parks
on the same gate: measured, one self-resolving thread plus four unrelated resolvers left five hung,
and a two-registry cycle hung too, on every supported Ruby. The build-under-`@write` shape this
replaced raised `ThreadError: deadlock; recursive locking` immediately from the offending call, and
that scenario is the stated motivation for replacing it — so a silent registry-wide wedge would be
a straight regression, not a trade. The owner is a `Fiber` rather than a `Thread` for the same
reason `Thread::Mutex`'s own ownership is per-fiber: two fibers of one thread can genuinely wait on
each other, while a factory that spawns a *thread* and resolves from it is not re-entrant at all.

`#resolve`'s branches, which are `SEAM-5` verbatim:

| Registered factories | Resolved slot | Behaviour |
|---|---|---|
| any | occupied | return the instance, no scan (`SEAM-7`) |
| zero | empty | raise `Dexpace::SeamError` naming the seam and telling the caller to require or install one — **naming no gem** (`SEAM-2`) |
| exactly one | empty | build, memoise, return, silently (`SEAM-5`) |
| two or more | empty | raise `Dexpace::SeamError` listing every registered key (`SEAM-5`) |

The failure branches memoise **nothing**, so a registry that failed re-scans on the next access and
a later `require` or `#install` takes effect — `SEAM-7`'s "an UNRESOLVED state MUST remain
re-evaluable", verified in the prototype.

`#install(instance)`'s prior-state table is §3.6's, implemented as a table rather than as prose
because `SEAM-6` and `SEAM-8` describe overlapping scenarios (§11.14). **The comparison is `equal?`
on the object in the resolved slot** — never `==` and never the factory (`seams-and-extensibility/c8d621ef`):

| Prior state of the resolved slot | `install(t)` | Requirement |
|---|---|---|
| empty | succeeds silently | `SEAM-5` |
| holds `t` (`equal?`) | no-op | `SEAM-6` |
| holds a different object, explicitly installed | raise `Dexpace::InvalidArgumentError` naming incumbent and rejected | `SEAM-6` |
| holds a different object, auto-resolved, never handed out | replace silently | `SEAM-8` — **vacuous in production**, see below |
| holds a different object, auto-resolved, already handed out | replace **and warn** | `SEAM-8` |

**The fourth row is `SEAM-8`'s negative clause holding vacuously, and saying so is the honest
reading.** `SEAM-8` warrants no warning "when the resolved provider was never actually returned",
and in this port `#resolve` hands out the provider in the same call that resolves it — so an
auto-resolved-but-never-handed-out slot is unreachable through the ordinary API. The branch is
implemented rather than collapsed for two reasons: collapsing it would warn on a state the
requirement explicitly says warrants no warning, the day a non-delivering resolution path is added;
and the unchecked swap seam `SEAM-6` sanctions does reach that state, which is where the test
exercises it. What the test may not claim — and does not — is that any production path reaches it.

`#register` carries the same rule one level down: re-registering the `equal?` factory under the same
key is a no-op, and a different factory under an occupied key raises naming both — so a double
`require` is quiet and two gems claiming one key are not.

**The warning is `Kernel#warn`, emitted outside the mutex.** Verified fact 7: it routes through
`Warning.warn`, which is interceptable, and it is silent when `$VERBOSE` is `nil`. `SEAM-8` is a
SHOULD asking for a warning rather than a failure, and a channel the host already knows how to
silence, redirect or turn into a log line is the right one for that; phase 5 may additionally emit
an `http.instrumentation.*` diagnostic when §8.1's facade exists. Emitting it outside the lock is
`concurrency-and-async/ee54cb68` applied — `warn` writes to a stream.

**`#swap(instance) { … }`** is the "separate unchecked/internal swap seam … for test-scoped
overrides" `SEAM-6` permits, taken explicitly and in the safest shape Ruby offers: block-scoped,
restoring the prior snapshot in an `ensure`, documented as test-scoped and performing no conflict
check. A bare setter would be the same capability with no restore.

**Two members are spliced from the live state rather than restored**, and the rule is the same for
both: the live value is the only correct one. `resolving`, because a resolution can be in flight
when the swap begins and can complete inside the block, and putting that snapshot's now-closed gate
back leaves every later `#resolve` popping a closed queue forever. `factories`, because an adapter
registers itself as a side effect of being `require`d and **Ruby will not re-run a `require`**: a
registration reverted by the `ensure` is gone for the rest of the process, silently — verified,
`swap(:fake) { register(:key, …) }` left `#registered_keys` empty. `resolved`, `explicit` and
`handed_out` *are* restored, because scoping an override to a block is what `#swap` is for and an
`#install` inside the block is part of that override.

### The version-skew guard (`DEF-21`, picked up here)

Design §2.3 pairs the `~> MAJOR.MINOR` gemspec constraint with a **registration-time assertion** on
`Dexpace::VERSION`, so a mismatched core/adapter pair fails at `require` time rather than at the
first seam call. Phase 0 built the static half (`gates:gemspec_audit` derives the expected
constraint from `VERSIONS`) and deferred the runtime half to this phase because it hangs on the
registration call phase 2 shapes. It is picked up here, as a **required** keyword:

`#register(key, factory, core:)`, where `core` is the same `~> MAJOR.MINOR` string the adapter's
gemspec declares. Required rather than optional, because an optional skew check is a skew check
nobody passes. The comparison is hand-rolled and accepts **only** the two-segment `~> M.N` form —
running MAJOR equal to `M`, running MINOR at least `N` — and raises `Dexpace::InvalidArgumentError`
on any other requirement string, so nobody writes `>= 1.2` and silently gets a different rule.
A mismatch raises `Dexpace::SeamError` naming the adapter key, the requirement and
`Dexpace::VERSION`.

Hand-rolled because of verified fact 3: `Gem` is undefined under `ruby --disable-gems`, and a
library may not assume RubyGems is loaded. The **test** cross-checks the hand-rolled comparison
against `Gem::Requirement#satisfied_by?` over a grid of versions, because under Bundler RubyGems is
always present in the test process — which is the honest way to get the reference semantics without
depending on them at runtime.

`SEAM-10` is the requirement this replaces. Its multi-loader de-duplication is **vacuous** in Ruby
(§10.9): there is no classloader, `require` de-duplicates by resolved feature path, and constants
are process-global, so one logical provider cannot be seen as two. The real Ruby risk is version
skew, and this is the guard for it. The checklist row is N/A-vacuous with the guard named, never
passing.

## `Dexpace::Transport` — the synchronous transport seam

**Satisfies:** `SEAM-11`, `SEAM-13`, `SEAM-15`, and `SEAM-2` for this seam; `SEAM-12`'s *shape*,
with the requirement itself ⏳ against `DEF-22`. **Design:** §3.2. **Corpus:** `transport-adapter/1e63c819`, `/da577942`, `/e25582ce`, `/938e4c9a`,
`/c3d2d69c`; `porting-method/bf484e8e`.

**A transport is any object responding to `#call(request, options, cancellation)` and returning a
`Dexpace::Response`.** `#call` is the convergence point of Ruby's own middleware ecosystems, so a
bare `lambda` is a valid transport and phase 4's `Dexpace::Pipeline` can stand in wherever a
transport is expected (`PIPE-26`) with no declaration.

`Dexpace::Transport` is a module with `extend self`-style singleton methods
(`data-modeling/3775e9d7`), no instance side, and no implementation:

- `.conforms?(object)` — `object` responds to `#call` and its callable accepts exactly three
  positional arguments. Verified across callable shapes on 3.2.11 and 4.0.6: `#parameters` reports
  `:req` for a lambda's and a method object's parameters and `:opt` for a non-lambda `proc`'s, so
  the predicate is "required count ≤ 3 and (a rest parameter is present or required + optional ≥
  3)" rather than an `#arity` equality, which would reject a `proc`. An object whose `#parameters`
  cannot be read falls back to `respond_to?(:call)` alone rather than refusing.
- `.register`, `.install`, `.resolve`, `.swap`, `.registered_keys` — thin delegations to this
  seam's own `Dexpace::Registry` instance. Delegation rather than inheritance, so the five branches
  are implemented once (`data-modeling/5730bc9a`).
- `.async_over(transport, executor:)` — `SEAM-18`, below.

**`SEAM-11`'s three clauses, each mapped.** *Single operation*: one `#call`, one `Response`; there
is no batch entry point to add later. *No pre-buffering*: the seam's contract says the returned
`Response`'s body is a lazily-read stream the caller owns and closes, and the fake transport
asserts that the body is not consumed by the call itself; the real proof is phase 8's, over a real
socket (`DEF-22`). *Options may be ignored*: `options` is always passed and is always a
`Dexpace::RequestOptions` — `RequestOptions::EMPTY` is the no-options call — so "a transport that
ignores options behaves identically" is structural: options are inert immutable data and ignoring
them is not reading them.

**`SEAM-12`** — concurrency-safety is a property of an implementation, and phase 2 ships none. What
phase 2 owns is that nothing in the *seam* forces per-request state onto shared storage: `#call`
takes everything it needs as arguments and returns everything it produces, so a conforming
transport can keep all per-request state in locals. The assertion belongs to
`dexpace-conformance` (`DEF-22`, phase 8) and the fake transport carries a concurrent-call test so
the seam's own harness is not the first place it is tried.

**`SEAM-13`** — a SHOULD about a blocking implementation, which phase 2 does not ship. Its contract
is fixed here and nowhere else: cancellation reaches a transport as the **third argument**, an
ordinary value, and the transport honours it by checking `#cancelled?` at every point it resumes
from a wait. Phase 8's adapters do the honouring; `dexpace-conformance` asserts it.

**`SEAM-15` is a MAY and this port takes it explicitly** (§3.7), in a narrower form than "a send
after close raises": **a transport that owns the resource it closed raises `Dexpace::ClosedError`
from a later send.** A wrapper that only *borrows* closes nothing and stays usable — which is what
both `SEAM-18` bridges do, and raising there would break `XCUT-22`'s "the caller owns its lifecycle
and may keep using it after the SDK component is closed". Phase 2 therefore ships the error class
and the documented rule and **no raise site**, because it ships no owning transport; phase 8's
adapters are the first owners and `dexpace-conformance` is where the raise is asserted. Documented
rather than left undefined, because "undefined" in Ruby means whatever `NoMethodError` the
internals happen to produce.

**One gap, admitted rather than papered over.** The synchronous and asynchronous transport seams
have the *same* structural shape — `#call(request, options, cancellation)` — and differ only in
return type, which no runtime predicate can check before the first call. `.conforms?` therefore
cannot tell an async transport registered in the sync registry from a sync one. The mitigation is
that they are two registries and an adapter names which seam it registers into, and that
`dexpace-conformance` asserts the return type per adapter. A `.conforms?` that claimed to
distinguish them would be a false proof, which is the same position §10.10 takes on `HTTP-2`.

## `Dexpace::AsyncTransport` — the asynchronous transport seam

**Satisfies:** `SEAM-16`, `SEAM-2` for this seam. **Design:** §3.3.

A second module of the same shape: `.conforms?`, the five registry delegations, and
`.sync_over(transport)` for `SEAM-18`. **An async transport is any object responding to
`#call(request, options, cancellation)` and returning a `Dexpace::Async::Future`.**

It is a **separate top-level constant and a separate registry**, which the design does not name
(P2-1). `SEAM-2` enumerates the synchronous and asynchronous transports as two distinct seams, so
one registry keyed by kind would merge two concerns the requirement separates. The name is not
`Dexpace::Transport::Async`, because that constant would sit beside `Dexpace::Transport::NetHTTP`
and `Dexpace::Transport::AsyncHTTP` — two adapter namespaces — and a seam beside its own
implementations is the confusion `SEAM-2` exists to prevent.

## The async pivot: `Dexpace::Async::Future` and `Dexpace::Async::Completer`

**Satisfies:** `SEAM-16`, `SEAM-17`, `SEAM-30`. **Design:** §3.3 in full; §10.3; §11.2.
**Corpus:** `transport-adapter/91d4b932`, `/bf372992`; `concurrency-and-async/611b9392`,
`/2db8f65c`, `/a50ffacb`.

**The pivot is core-owned, and this is the phase that owns it** — roadmap cross-phase obligation 5:
"the canonical dependency-free future is core's, decided in phase 2 (§10.3); phase 8's adapters
bridge to it and never replace it, which is also what keeps `NFR-11`'s RBS surface scan
satisfiable." Ruby's async ecosystem is fragmented across `Async::Task`,
`Concurrent::Promises::Future`, plain `Thread` plus `Thread::Queue` and EventMachine descendants,
none in the standard library and all with different cancellation semantics; adopting any one would
put a third-party type in core's public surface, which `SEAM-1` and `NFR-11` forbid.
`SEAM-17` is a SHOULD that names the pattern and not the type, and §11.2 already resolves the
apparent tension with `NFR-11` — its target is *third-party framework* types, and a core-owned
dependency-free pivot is not one.

**Two objects, because the read side and the write side are different capabilities.**

```
Dexpace::Async::Settlement = Data.define(:response, :error, :cancelled)
  # exactly one of response / error is non-nil; cancelled implies error

Dexpace::Async::Completer         # the write side, and where the state lives
  #future
  #fulfil(response)  #fail(error) # -> true, or false on a lost race
  #on_cancel { |reason| … }
  #settled?  #outcome             # -> Settlement or nil

Dexpace::Async::Future            # the read side: a facade over one Completer
  #settled?  #cancelled?
  #value(cancellation: nil)       # blocks the calling thread-or-fiber; raises the failure
  #wait(cancellation: nil)        # settles-or-returns; returns self; never raises the failure
  #on_settle { |settlement| … }   # invoked exactly once, on the settling thread-or-fiber
  #cancel(reason)                 # cooperative
```

**The state lives in the `Completer` and the `Future` is a facade over it**, rather than the state
living in the `Future` with the `Completer` reaching in. Ruby has no package-private visibility, so
the alternative is a cross-object `send`, which is a hole in exactly the boundary this pair exists
to draw. `Dexpace::Async::Settlement` is a public `Data` including `Dexpace::Model`, with its
cross-field rule — exactly one of `response`/`error`, and `cancelled` implying `error` — validated
in its `initialize` the way phase 1 validates every public model; it is what `#on_settle` yields and
what `Completer#outcome` returns.

The write side is handed only to the producer, so a consumer cannot settle someone else's future —
the Ruby answer to a language with no way to hide a completion method. `Completer.new` mints the
pair and `#future` memoises the one `Future` over it. `Future.new(completer)` stays public and
type-checks its argument rather than being made private: a second facade over the same completer is
harmless — every piece of state is on the completer, so two facades observe one future — and the
alternative, a private constructor the completer reaches through `send`, would put a `send` hole in
the boundary this pair exists to draw.

**`#value` blocks on a `Thread::Queue` pop and never spins or `Kernel#sleep`-polls**, which is what
makes the pivot scheduler-transparent: verified fact 4, a blocking queue pop under a registered
`Fiber.scheduler` routes through `block`/`unblock` and does not park the OS thread. A caller inside
`Async { }` therefore awaits the pivot without blocking the reactor, and a caller with no scheduler
blocks one thread, which is what they asked for.

**The queue is a wake-up signal, never the value channel** — verified fact 5: `pop` returns `nil`
for a timeout, for a closed queue and for a pushed `nil` alike, so a pivot that carried its value
through the queue could not tell "settled with nothing" from "not settled". The settled outcome is
written to an instance variable under the mutex, the queue is closed to wake every waiter, and each
waiter re-reads the variable. That is also how `SEAM-16`'s "MUST NOT complete successfully with a
null/absent value" is satisfied structurally: there is no settled-with-nothing state to reach,
because settling means writing one of exactly two things.

**The mutex is held across the settle flip and the callback-list steal, and across nothing else** —
verified fact 6. Callbacks run outside it, so an `#on_settle` handler that itself blocks cannot
deadlock a second fiber of the same thread. `#on_settle` on an already-settled future invokes the
block immediately, on the calling fiber, so a late registration is never lost.

**Cancellation is cooperative and there is exactly one rule.** `#cancel` cannot pre-empt a producer,
because Ruby's only pre-emption primitives are forbidden (§8.3). The rule, stated once here and
cited everywhere else, is design §3.3's **check-after-resume**: *after returning from any operation
that may have suspended — an I/O wait, a scheduler yield, a queue pop, a task await — and before
acting on the value it produced, the producer MUST re-check its cancellation state; if cancelled it
MUST close any response it holds and settle through the failure channel rather than delivering.*
`Completer#on_cancel` gives the producer a hook to abort promptly rather than only at the next
resume.

**`SEAM-30` is that rule's obligation, and phase 2 both states it and honours it.** Where core
itself produces a response the future will not hand to a caller — which happens in exactly one
place phase 2 ships, `SEAM-18`'s `async_over` bridge — the producer closes it through
`Dexpace.close_quietly`. `Completer#fulfil` on an already-settled future returns `false` **and
closes the response it was handed**, because a `fulfil` that loses the race is by definition
holding an orphan; that single line is what makes the requirement hold for every adapter that
routes through `Completer` rather than depending on each adapter remembering. `#cancel` after
settlement is a no-op on the value and does not close a delivered response, which is `SEAM-16`'s
last clause and `ASYNC-20`.

**`#value`'s blocking wait takes `cancellation:`, not `deadline:`** — a deliberate narrowing of
§3.3's written signature, recorded as P2-5 and deferred as `DEF-28`. `SEAM-18`'s interruption
clause is about cancellation; deadlines belong to `CFG-15`–`CFG-21` and phase 5's clock, and adding
a keyword later widens a signature rather than narrowing it, so `NFR-4`'s API lock is not
prejudiced.

## `Dexpace::Cancellation` and `Cancellation::Source`

**Satisfies:** the third argument of both transport seams (`SEAM-11`, `SEAM-16`), `SEAM-13`'s
contract, `SEAM-18`'s interruption clause, and `SEAM-30`'s trigger. **Design:** §3.3's
"Cancellation and deadlines, end to end"; §10.4.

The token exists in phase 2 because two seam signatures name it: a transport takes it as an
argument and a future's cancel state is read through it. A seam whose third argument has no type is
a seam phase 8 cannot be written against.

```
Dexpace::Cancellation
  .none                       # the shared, never-cancelled token
  .source                     # -> Cancellation::Source
  .any(*tokens)               # -> a token cancelled when any input is
  #cancelled?  #reason
  #on_cancel { |reason| … }   # invoked once; immediately if already cancelled
  #check!                     # raises Dexpace::CancelledError when cancelled

Dexpace::Cancellation::Source
  #token
  #cancel(reason)             # idempotent; the first reason wins
```

**The reason is a typed object, never a message string.** `XCUT-2` requires timeout and cancellation
to be told apart by ambient state rather than by matching a message, "even when the runtime
represents both with the same exception type" — which matters in Ruby, where `Net::ReadTimeout` is
distinguishable but `Errno::*` and `IOError` are not reliably. Inspecting `reason.class` is what
satisfies it. Phase 2 fixes the shape and defines no reason types beyond `Dexpace::CancelledError`
itself; `RETRY-23`/`RETRY-24`'s terminal-and-non-retryable classification is phase 6's and reads
the same field.

**The state lives on the `Source` and the token is a facade over one or more of them**, the same
split as `Completer`/`Future` and for the same reason — Ruby has no package-private visibility, so
the alternative is a `send` through the boundary. A `Source` holds one frozen `Data` snapshot
(`cancelled`, `reason`) swapped under a `Thread::Mutex`, with `#on_cancel` handlers run outside the
lock.

**A token is frozen, holds no state, and subscribes to nothing until a caller registers a
callback.** `#cancelled?` and `#reason` are computed from the sources on every call, and the winner
is the cancelled source with the earliest `#cancelled_at` — a monotonic nanosecond stamp each
`Source` takes when it cancels. Two alternatives were tried and rejected. Reading `#reason` off the
first cancelled source in *list* order is wrong, and this phase's own test caught it: a composed
token would report a different reason from the one its `#on_cancel` handler had just been handed,
for the whole life of the token, which is the single thing a composed token must not do.
Subscribing at construction to latch the winner is correct but leaks — a token retains one closure
on every source for as long as that source lives, and `.any` composing a client-lifetime token with
a per-call deadline token, which is exactly what `.any` is for and what phase 5's `DEF-28` will do
on every request, retained 201 closures on one source over 200 compositions, measured on 3.2.11 and
4.0.6. Ordering by the stamp gets the same answer with no subscription at all.

**What the stamp buys is convergence, not atomicity, and the residual is recorded rather than
claimed away.** A `Source` takes its stamp *before* it takes its own mutex, so a source with the
earlier stamp can publish its state after a handler has already fired on a later-stamped one, and
`#reason` then flips to the earlier one — a handler and a subsequent `#reason` read disagreeing.
Demonstrated deterministically on 3.2.11, 3.4.10 and 4.0.6 by holding one source's mutex across the
other's `#cancel`, and seen in a free-running race 2 times in 120,000 on 3.2.11. **No stamp
placement closes it**: the two sources hold two different mutexes and nothing orders them, so moving
the read inside the lock narrows the window without removing it, and a token-level latch is the
subscription-at-construction leak this design already rejected. What holds unconditionally, and is
what a caller may rely on: the token is cancelled, every reason it ever reports belongs to a source
that really was cancelled, and the value converges once every racing source has published. **Ties
are not the problem and are not treated as one** — 0 same-nanosecond collisions in 100,000 stamps,
a 50 ns median gap between successive `CLOCK_MONOTONIC` reads, 1 ns resolution, measured on all
three interpreters; two sources stamped inside one nanosecond tie-break on list order.

**`#on_cancel` guards per registration, not per token**, and it is the only method that
subscribes. Each registered block is invoked exactly once whether the token watches one source or
several, and the guard is a flag private to that registration; a single "something already fired"
flag on the token would silently drop every registration after the first, which is how a second
waiter on one token blocks forever — a `SEAM-18` violation no single-waiter test can see. The
handler is handed `#reason` rather than the firing source's own, so a handler and a later `#reason`
read agree in every ordering the handler itself can observe; the paragraph above states the window
they can still disagree across.

**`#on_cancel` returns an unsubscribe handle**, `Cancellation::Subscription`, whose `#detach`
withdraws that one registration from every source the token observes through
`Cancellation::Source#off_cancel`. Composition subscribing to nothing is only half of what keeps a
long-lived source from accumulating closures; the other half is that a registration made for a
bounded wait is withdrawn when that wait ends. `Completer#await` is the one caller in `lib/`, and it
detaches in an `ensure`. Without it, `.any(client_token, per_call_token)` with
`future.value(cancellation:)` — what phase 5's `DEF-28` does on every request — retains one closure,
and through it one response, per request on the client-lifetime source: measured 200 of 200, with
500 100 KB responses still reachable after `GC.start`, identically on all three interpreters.
Deviation P2-14.

**Every handler runs, whatever an earlier one did.** `Source#cancel` publishes its snapshot under
the mutex and then notifies through `Dexpace::Hooks.notify` rather than a bare
`hooks.each { |hook| hook.call(reason) }`: in a bare `each` one raising handler drops every
later-registered handler and propagates to the canceller, which is the "a second waiter on one
token blocks forever" `SEAM-18` failure arriving from the write side. `Hooks.notify` runs the whole
list, then re-raises the first failure — re-raising rather than dropping, because phase 2 has
neither of §3.7's two disposal routes (`DEF-24`'s suppressed trail, phase 4; §8.1's diagnostic,
phase 5) and a handler that raises into a void is a bug nothing reports. It is safe to re-raise
*there* in a way it is not at the naive site, because the state is already published and every other
handler has already run. The failures after the first are dropped until `#suppressed` exists to
carry them: `DEF-32`. Deviation P2-15.

`#sources` is **protected**, and composition therefore goes through `#merged_with(*others)`, an
instance method: a class method has the class as `self` and cannot call a protected instance
method, which is what would force `#sources` public if `.any` did the work itself. `.none` is a
**frozen** singleton over an empty list that allocates no mutex and no hook list, so the common
case allocates nothing and can never be cancelled. `Cancellation.new` is `private_class_method`;
`.none`, `.source`, `.over` and `.any` are the factories.

**What phase 2 does not build:** deadline-derived tokens, the interruptible delay, and the clock —
all `CFG-15`–`CFG-21`, phase 5 (`DEF-28`). `.any` composes tokens, which is what a per-call derived
token needs, and phase 5 supplies the deadline token it composes with.

## `Dexpace::Closeable`, `Dexpace.close_quietly` and `Dexpace::ClosedError`

**Satisfies:** `SEAM-14`, `SEAM-25`, `SEAM-15`, and `XCUT-13`/`XCUT-22` for phase 9.
**Design:** §3.7 in full. **Corpus:** `transport-adapter/7dc7f7b9`, `concurrency-and-async/65882a70`,
`cross-cutting-invariants/89eb6533`, `/f0dabb13`.

Six requirements say the same three things about closing in six vocabularies, and Ruby has no
`Closeable` interface and no `try-with-resources`, so it is written down once — here.

**The duck type.** Anything the SDK can release responds to `#close`. `Dexpace::Closeable` is a
module supplying the whole contract to any class that includes it and defines a private `#release`;
there is nothing to conform to, so a `Net::HTTP`, an `IO`, a `Tempfile` and a `Dexpace::Response`
all pass through the same helper.

**Idempotence is a latch, not a flag check.** A `@closed` boolean flipped under a `Thread::Mutex`,
with the mutex **held only across the flip** and released before `#release` runs — verified fact 6
is why: Ruby's `Mutex` is per-fiber-owned and non-reentrant, so holding it across a release that may
suspend deadlocks two fibers of one thread. Whoever flips the latch runs the release; everyone else
returns immediately. A release that raises still leaves the latch flipped, so no second release is
attempted (`BODY-27`), and the failure propagates once.

**Ownership is a construction-time fact, not a close-time judgement.** `XCUT-22`, `SEAM-14` and
`SEAM-25` all say the SDK closes exactly what the SDK created. In Ruby that is two differently named
entry points — one that *builds* a resource and one that *borrows* it — and a frozen `@owned`
boolean set at construction. `Dexpace::Closeable` supplies `#owned?` and a `#close` that runs
`#release` only when owned, so a component cannot make the decision differently at three sites.
Phase 2 ships no component that owns a real resource; what it ships is the contract and the test
that proves a borrowed resource survives its holder's close.

**Close never blocks on an interrupt-sensitive wait** (`XCUT-13`). This port has no interrupt to
preserve, so that half is satisfied by the flag never being touched; the non-blocking half is a real
constraint on phase 8's `dexpace-async-thread` and is stated here so it is not re-derived there.

**`Dexpace.close_quietly(resource)`** is the single sanctioned exit for a close on a cleanup or
discard path: it is null-safe (`CFG-21`'s last clause), it rescues `StandardError` from `#close`,
and it never raises over a primary failure. §3.7 gives the rescued error two disposal routes and
**phase 2 has neither** — the suppressed trail is `Dexpace::Error#suppressed`, deferred to phase 4
as `DEF-24`, and the `http.instrumentation.*` diagnostic is §8.1's facade, phase 5. Building either
here would fix an interface a later phase must be free to shape, which is the objection phase 0
raised against defining `Dexpace.register` early and it applies unchanged. So phase 2 ships the
helper with the rescue and the null-safety, **drops the rescued error**, says so in the YARD block
and in a test that asserts the current behaviour, and files `DEF-27` naming the two phases that
supply the routes. The two loud exceptions §3.7 names are honoured from the start: an explicit
`#close` by a caller propagates its failure, and a `#release` raising during the latched close
propagates once.

**`Dexpace::ClosedError`** is `SEAM-15`'s documented post-close failure mode, raised by any seam
implementation that chooses to detect the condition. Phase 2 defines the class and the rule; the
raising is per adapter.

## `Dexpace::Serde` — the wire-codec seam and its failure hierarchy

**Satisfies:** `SEAM-19`, `SEAM-20`, `SEAM-21`, `SEAM-22`'s surviving clause, `SEAM-23`, and
`SEAM-2` for this seam. **Design:** §3.4; §10.13; §10.14. **Corpus:** `serde/8a513091`, `/8547695f`,
`/8c9be85f`, `/da4f126d`, `/b4c876a3`, `/5821286d`.

A duck type of six methods and a `.conforms?` predicate over them:

```
#media_type                        # the media type this serializer produces (SEAM-19)
#dump_string(value)                # a fresh String                          (SEAM-20)
#dump_bytes(value)                 # a fresh Encoding::BINARY String         (SEAM-20)
#dump_to(value, sink)              # writes into a caller-owned #write sink; never closes it
#dump_into(value, buffer, offset:) # writes at an offset; IndexError on overflow
#load(source, witness)             # reads to EOF; never closes the source   (SEAM-21)
```

**All four allocation profiles ship and two of them are one Ruby type** (§10.13). A `String` tagged
`Encoding::BINARY` *is* Ruby's byte array; `#dump_bytes` differs from `#dump_string` only in the
encoding tag, which is the whole of the distinction `SEAM-20` draws — and both ship because the tag
is load-bearing at §3.1's encoding boundary and a caller wanting BINARY should not have to remember
`#b`. `#dump(value, sink)` is §3.4's shorthand for `#dump_to`; an adapter may define it and the
`Dexpace::Serde` YARD block says so, but it is deliberately **not** in the conformance contract —
requiring the alias would make the shorthand mandatory, which is the opposite of what a shorthand
is, so a codec implementing the four named profiles conforms without it.

**`SEAM-19`'s undefaulted media type is enforced at the seam, not at the codec.** `.conforms?`
requires `#media_type`; `Dexpace::Serde` supplies no default and has no fallback constant to fall
back to, so a codec that forgets it fails registration rather than silently stamping the wrong
`Content-Type`. That is the whole of what phase 2 can enforce; that the value is *correct* is phase
7's.

**`SEAM-21` and the surviving half of `SEAM-22`.** `#load` takes an explicit `witness` argument and
**there is no witness-less overload**, which is the clause of `SEAM-22` that survives §10.14's
substitution of the JVM's reflective type capture. The witness *protocol* — a class object and
combinator protocol rather than a reflective token — is §7.3's and phase 7's. `#load` reading to
EOF and not closing the caller's source is stated at the seam and asserted against the fake codec.

**`SEAM-23`'s failure hierarchy is a class root, and that inverts phase 1's P1-2 deliberately.**

```
Dexpace::Serde::Error < ::StandardError         # includes Dexpace::Error
Dexpace::Serde::SerializationError   < Dexpace::Serde::Error
Dexpace::Serde::DeserializationError < Dexpace::Serde::Error
```

Phase 1 made the SDK-wide root `Dexpace::Error` a **module**, because `XCUT-4` puts transport errors
in Ruby's `IOError` family and single inheritance makes a class root and that requirement mutually
exclusive. No such competing family exists here: `SEAM-20` and `SEAM-21` both say a genuine stream
I/O error **propagates unwrapped** rather than being reclassified as a serde failure, so a serde
error is never also an `IOError`. `SEAM-23` asks in so many words for "a stable, SDK-owned
hierarchy (a base serde failure with encode/decode subtypes)" that is "open for codegen/adapters to
add more specific subtypes", and a class root delivers that literally while including
`Dexpace::Error` keeps `rescue Dexpace::Error` catching it. Recorded as P2-2, because a later reader
finding a class root here and a module root there is entitled to know which rule applies where: the
**SDK root** is a module; a **seam-local root** with no competing Ruby family is a class.

Adapters raise these instead of leaking the backing library's exception type, and raise them from
inside the `rescue` so Ruby sets `#cause` automatically (`serde/5821286d`) — stated here, asserted
per adapter in phase 7 and phase 8.

**A naming hazard, flagged once.** Inside `module Dexpace::Serde`, a bare `Error` is
`Dexpace::Serde::Error` and a bare `JSON` would be `Dexpace::Serde::JSON` once `dexpace-serde-json`
is loaded — the same shape as verified fact 2. Core writes `Dexpace::Error` fully qualified
everywhere, and the sixth cop covers the stdlib half.

## `Dexpace::Operation` — the operation-input projection seam

**Satisfies:** `SEAM-26`, `SEAM-27`. **Deferred:** `SEAM-28` (`DEF-1`). **Design:** §3.5.
**Corpus:** `url-and-query-encoding/7f4ffc91`, `/2c8dc18b`, `/cd9d4974`, `/e655a621`, `/9ff11c34`.

A frozen `Data` descriptor plus one builder method, and the phase's only new public value type:

```ruby
Dexpace::Operation = Data.define(:method, :template, :projections)
Operation.build(method:, template:, projections: {})
operation.build_request(base_url:, inputs: {}) # -> Dexpace::Request
```

`projections` maps an input key to `[:path | :query | :header | :body, wire_name]`. Only `method`
and `template` are required and `projections` defaults to empty, so `SEAM-26`'s "a parameterless GET
overriding only method+path" is the default construction. It includes `Dexpace::Model`, has
`private_class_method :new` and validates in `initialize` — phase 1's construction rule applied,
with `method` coerced through `Dexpace::Method.of` so a `String` never survives as a member.

**Two placeholder checks, at two times, and the split is what makes `SEAM-27`'s "every placeholder
MUST have a supplied value" structural.** At construction, the set of `:path` projection wire names
must equal the set of `{name}` placeholders in the template — a placeholder with no projection can
never be filled, and a `:path` projection naming no placeholder can never be used, so both are
caller mistakes catchable before any request exists. At `#build_request`, every projected path input
must have a value in `inputs`; a missing one raises `Dexpace::InvalidArgumentError` naming the
placeholder. The template is scanned with a `Regexp.new(source, timeout:)` — per-pattern, never the
process-global `Regexp.timeout`, because a library must not impose a regexp budget on its host —
and an unterminated `{` is rejected at construction.

**Path values are encoded as single segments.** Each value goes through phase 1's
`Dexpace::PercentEncoding.encode_component`, whose unreserved set is exactly `A-Za-z0-9-._~`, so a
value containing `/` is encoded to `%2F` and cannot inject a segment. This is the seam's whole
security property and it is one call to a function phase 1 already verified byte for byte.

**The query is `Dexpace::Query#encode`**, phase 1's — `SEAM-27`'s "the query MUST be RFC-3986
rendered" is that method, and a repeated projection name emits one parameter per value because
`Query` is a pair list. Header projections go through `Headers::Builder` in its outbound direction,
so `HTTP-17`/`HTTP-18` validation happens here rather than at the transport. The body projection is
**carried, not encoded** (`SEAM-26`'s own words): it is passed to `Request::Builder#body` untouched,
and encoding it is the codec's job at a later stage.

### Base-URL composition, hand-built

This is verified fact 1 and it is the phase's largest departure from a design sentence. `SEAM-27`'s
four composition rules are implemented directly:

| Rule | Implementation |
|---|---|
| a trailing slash normalises to exactly one separator | the base path's trailing `/`s are stripped, the operation path's leading `/`s are stripped, and exactly one `/` is inserted |
| an empty operation path leaves the base untouched | the base path is used unchanged |
| an existing base query is preserved with the operation query appended after it, its dangling separator dropped | the base query's trailing `&`s are stripped, then `base&op`; either side being empty yields the other |
| a base carrying a fragment, or resolving to a malformed URL, is rejected with a context-bearing error | `Dexpace::URL.parse!` (phase 1) rejects the malformed and non-absolute case with the offending input in the message; a non-`nil` `#fragment` raises `Dexpace::InvalidArgumentError` naming the base |

Composition works on a `dup` of the frozen base URI and assigns `#path` and `#query`, never
re-parsing a re-rendered string — verified fact 8, and it is what keeps already-encoded octets
verbatim. `URI.join`, `URI::RFC3986_PARSER.join` and `URI::Generic#merge` are all wrong here for the
reason verified fact 1 gives, and the first of the three is additionally banned by phase 0's
`Dexpace/NoUriDefaultParser` cop.

`SEAM-27`'s own conformance example is the primary test:
`https://host/c?sig=abc` + `/pets` + `limit=1` → `https://host/c/pets?sig=abc&limit=1`, verified
identical on 3.2.11 and 4.0.6.

## `SEAM-18` — the two bridges

**Satisfies:** `SEAM-18`, and exercises `SEAM-30`. **Design:** §3.3; §5.3's `PIPE-33` note.
**Corpus:** `transport-adapter/4edbefc7`, `/85d9d8ed`; `concurrency-and-async/a1ec6ce4`, `/08a0e08d`.

**Both bridges live in `Dexpace::Bridge`, one per file**, rather than under the seam module that
exposes them (P2-13). `Dexpace::Transport::AsyncOver` would sit beside `Dexpace::Transport::NetHTTP`
and `::AsyncHTTP` — two adapter namespaces — and a reader meeting three constants there cannot tell
which core owns, which is exactly the confusion P2-1 keeps the async *seam* out of. Both include
`Dexpace::Closeable` with `owned: false`: each holds a caller-supplied transport, and `AsyncOver`
additionally a caller-supplied executor, and creates neither, so close latches and releases nothing
and never cascades to the wrapped transport (`SEAM-14`'s ownership clause, `XCUT-22`). Without this
the phase would ship two objects that call themselves transports and answer no `#close` at all,
which `SEAM-14` requires of "both transport seams".

**`Dexpace::Transport.async_over(transport, executor:)`** wraps a blocking transport as an async one.
The `executor:` keyword is **required and has no default** — `SEAM-18` says so in as many words, and
the reason is that a shared global pool would be starved by blocking work. The executor is a duck
type exposing `#post { … }` (`concurrency-and-async/08a0e08d`); core ships no implementation, which
is `SEAM-1` again, and phase 8's `dexpace-async-thread` supplies the first one. The bridge returns
the future **before** doing anything fallible and routes a synchronous raise from the executor to
`Completer#fail`, which is the normalisation `ASYNC-2` and `PIPE-30` require.

This is the one place in phase 2 where core itself can produce a response nobody will take delivery
of, so it is where `SEAM-30` is actually exercised rather than merely stated: the posted block
performs the blocking send, re-checks cancellation on return (check-after-resume), and on a lost
race hands the response to `Completer#fulfil`, which closes it through `Dexpace.close_quietly` and
returns `false`. A raise from `#post` **itself** — a shut-down pool, a rejected task — is routed to
`Completer#fail` alongside a raise from the wrapped transport, because `ASYNC-2` and `PIPE-30` ask
for one normalisation and a caller of an async seam should never have to `rescue` around `#call`.

**`Dexpace::AsyncTransport.sync_over(transport)`** wraps an async transport as a blocking one. Its
three clauses:

- **Unwrap the async-wrapper exception**, so the caller sees the original failure. In this port the
  pivot never wraps: `Completer#fail(error)` stores the error and `#value` re-raises *that object*,
  so there is no wrapper to unwrap and the clause holds structurally. The test asserts the identical
  object comes back out, not merely an equal message.
- **Honour interruption**: `#value(cancellation:)` waits on the token, and on cancellation it cancels
  the in-flight future and raises `Dexpace::CancelledError` carrying the reason. "Restore the
  interrupt flag" is vacuous here for exactly the reason `ASYNC-4` is vacuous (§10.5): a port that
  never delivers an interrupt cannot leave a stale one set. "Surface an interrupted-I/O error" is
  read as a typed cancellation error rather than an `IOError`, because `XCUT-4`'s I/O family is for
  *transport* failures and a cancellation is not one, and because `XCUT-2` requires the distinction
  to be readable out-of-band rather than from a message. Recorded as P2-4.
- **Per-call options are threaded, not dropped** — both bridges pass `options` through unchanged,
  and a test asserts the exact object arrives at the wrapped transport.

**Phase 4 reuses these rather than building a second pair.** §5.3's `PIPE-33` bridge is the same
capability at the pipeline layer, and a pipeline is a transport (`PIPE-26`), so the obligation is
recorded here: phase 4 wraps a `Dexpace::Pipeline` with `Transport.async_over` and does not
reimplement the executor contract, the orphan close or the normalisation.

## The byte-stream provider seam, and why nothing is here

**`SEAM-3` and `SEAM-4` are 🚫 — retired, not deferred.** §10.1 is the argument and it is not
re-made here: Ruby ships `IO`, `StringIO`, `IO.pipe` and `String` with `Encoding::BINARY` with the
interpreter, so choosing them is choosing the platform rather than taking a dependency, and the
pluggability apparatus exists for one reason — keeping a third-party stream library out of a
zero-dependency core — that does not apply. §11.3 records the assumption this rests on, because no
clause grants it: `SEAM-2` is read as constraining how a *retained* concern is exposed, not as
requiring a concern the runtime standardises to stay pluggable.

**The behavioural contract is not retired and is not phase 2's.** `IO-1`–`IO-29` and
`IO-37`–`IO-42` land in phase 3, in full, implemented directly on stdlib with no factory, no
installation call and no discovery. Phase 2's obligation is to say clearly that the two checklist
rows are a permanent simplification with a named reason, so that phase 9's conformance pass records
them as such rather than as gaps.

## `SEAM-1` and `SEAM-2` — the standing gates

Phase 0 built three mechanised checks for `SEAM-1` and put `json`, `net/http`, `net/protocol`,
`open-uri`, `socket` and `resolv` on the require **denylist** for `SEAM-2`. Phase 2 adds no
dependency, no allowlist entry and no denied require, so both rows are carried by the same three
gates running green over twenty more files. What phase 2 adds is the part a gate cannot see:

- **`SEAM-2`'s "the core MUST NOT reference any concrete implementation of a seam by name"** now has
  something to be true *of*. Three registries exist and every one of them starts empty; core never
  auto-requires an optional gem; and the zero-candidate error names the seam and the action
  ("require a transport adapter, or install one explicitly") and **no gem**. That last is the clause
  a test asserts by pattern, because it is the one an error message written later would quietly
  break.
- **Presence-gated auto-activation is not built.** §3.6 permits it for instrumentation only, and
  argues the asymmetry: for a transport or a codec, "whatever happens to be installed silently wins"
  is an auditability failure, while for instrumentation the worst outcome is a span that is or is
  not emitted. Phase 2 ships no instrumentation seam, so there is nothing to activate, and building
  the hook now would put a mechanism in the registry with no caller and one obvious wrong use.
  Filed as `DEF-30` so a later phase reading §3.6 does not conclude it was forgotten.

## The in-memory fake transport, and where it lives

Roadmap cross-cutting constraint 4: "phases 1 through 7 test against an in-memory fake transport
implementing only the `SEAM-11`/`SEAM-16` seams; phase 8 brings the first real socket." Phase 1
needed none — every type it shipped was a pure value. **Phase 2 is the first phase that needs one**,
so it decides where it lives.

**It lives in `gems/dexpace-core/test/support/`, and it is not public API.** Three fakes: a sync
transport, an async transport and a codec, each implementing only its seam, each configurable with
a canned response, a raise, a delay and a cancellation observation point. Required explicitly by
the suites that use them (`testing/180b5f41`), never from `test_helper.rb`, so no other gem's suite
loads them by accident.

The argument against publishing them, stated because the brief asks for it:

- **`NFR-11`'s scan is over `sig/`.** A fake in `test/` is invisible to it, which is the correct
  outcome — the scan exists to catch a third-party type in a *published* signature, and a test double
  has no business being in one either way.
- **`NFR-4`'s API lock would then protect it.** A public fake needs a YARD block, an RBS mirror and a
  row in `test/fixtures/surface/dexpace-core.txt`, after which changing its shape is a public API
  change diffed against a release tag. That is a real cost paid for a convenience, and it is paid
  forever.
- **`dexpace-conformance` is the gem chartered to publish test doubles** (§9.3), and it is phase 8's
  — `DEF-22`. Publishing a competing fake from core would give a third-party adapter author two
  answers to one question.
- **Phases 3 through 7 all ship `dexpace-core`**, so a core test-support file is reachable by every
  phase the roadmap's constraint names, with nothing published.

Filed as `DEF-29`: the move into `dexpace-conformance` happens when the first consumer outside
`dexpace-core` needs it, which is phase 8 at the earliest.

## Testing

`test/` mirrors `lib/` one file per file; each file's header comment names the requirement IDs it
exercises, and a non-obvious branch names the ID that forced it. Every suite subclasses
`DexpaceTestCase`, so a warning raised by code under test fails the test that triggered it.

**Per-ID placement.** Every in-scope ID is exercised in the test file mirroring the component that
owns it, and the checklist written at execution time names the plan task, not this document. Three
IDs are exercised in more than one file by nature: `SEAM-2` in `registry_test.rb` (the error names
no gem) and in `transport_test.rb`/`serde_test.rb` (the registries start empty); `SEAM-30` in
`async/completer_test.rb` (the lost-race close) and in `transport/async_over_test.rb` (the bridge's discard
path); `SEAM-14` in `closeable_test.rb` and in each fake's own suite.

**The concurrency tests, which are the ones a reader would otherwise write wrong.**

| Case | Asserted |
|---|---|
| 32 threads calling `#resolve` on an unresolved registry with one factory | exactly one factory invocation, exactly one scan, one `equal?` instance to every caller (`SEAM-9`) |
| a registry that raised on zero candidates, then a `register`, then `#resolve` | the second resolve succeeds — the failure memoised nothing (`SEAM-7`) |
| two threads calling `#install` with two different instances | exactly one wins and the loser raises; never both silently succeeding (`SEAM-9`) |
| a `Closeable` closed from two threads | `#release` runs exactly once; both callers return (`SEAM-14`) |
| a `Closeable` whose `#release` raises | the latch is still flipped, the failure propagates once, a second `#close` is a no-op |
| a `Future` settled from one thread while another blocks in `#value` | the value arrives; the waiter is not spinning — asserted by the settling thread sleeping first, so a spin would show as a busy loop rather than a block |
| `Completer#fulfil` on an already-settled future | returns `false` **and** closes the response it was handed exactly once (`SEAM-30`) |
| `#cancel` on an already-settled future | a no-op; the delivered response is **not** closed (`SEAM-16`, `ASYNC-20`) |
| `Cancellation::Source#cancel` called twice with two reasons | the first reason wins; `#on_cancel` handlers run exactly once |
| a factory that calls `#resolve` on the registry building it, and a two-registry cycle | `Dexpace::SeamError` at the offending call, and the registry re-evaluable for every other caller afterwards — never a park on the claim's own gate |
| a `Cancellation::Source` or a `Completer` with a raising hook among three | every hook still runs; the state is published before any of them does; the first failure is re-raised after the whole list (`SEAM-18`, `DEF-32`) |
| `Completer#on_cancel { raise }` then `Future#cancel` | the future is settled as cancelled and every waiter unblocks — a cancellation always publishes an outcome |
| 200 `future.value(cancellation: .any(client_token, per_call_token))` calls that block first | the client-lifetime source retains **zero** hooks afterwards; the future must not already be settled, or `#await` never arms and the test passes under the leak |
| a `register` performed inside a `#swap` block | survives the block's `ensure`; `resolved`/`explicit`/`handed_out` are restored and `factories`/`resolving` are not |

**The scheduler-transparency test**, which is the one that proves the pivot's central claim rather
than restating it: a probe `Fiber.scheduler` written in the test tree, a `Fiber.schedule`d consumer
blocking in `Future#value`, a producer settling from another scheduled fiber, and an assertion that
the scheduler's `#block`/`#unblock` hooks were called for a `Thread::Queue`. It implements
`#fiber_interrupt` because Ruby 4.0.6 warns without it and phase 0's override turns that warning
into a failure (verified fact 4). It runs on every row of the matrix, which is what makes it a
standing check rather than a one-off measurement.

**The constant-shadowing test**, which core's suite is otherwise structurally blind to: define
`Dexpace::Async::Thread` as a stand-in for the adapter gem's namespace, then re-run the pivot's core
assertions. Without qualification the pivot fails with `NoMethodError` on
`Dexpace::Async::Thread`; with `::Thread`, `::Queue` and `::Mutex` it passes. Paired with the sixth
cop's own cases in `.rubocop/test/cops_test.rb`, so the rule is enforced mechanically *and*
demonstrated behaviourally — the cop catches it on a file nobody ran, the test catches it on a file
nobody linted.

**The `SEAM-8` warning test** adds the first entry to phase 0's zero-entry warning allowlist, with
the comment phase 0 requires: the test sets `$VERBOSE` deliberately (verified fact 7 — `Kernel#warn`
is silent when it is `nil`), captures `Warning.warn`, and asserts the message names both the
incumbent and the replacement. A second case asserts **no** warning when the incumbent was never
handed out, which is the half `SEAM-8` is easiest to get wrong.

**The version-skew tests** are a grid: every combination of a declared `~> M.N` and a running
`MAJOR.MINOR.PATCH` over a small range, asserted against `Gem::Requirement#satisfied_by?` computed
in the test process. That is the reference semantics without a runtime dependency on them, and it
is what would catch a hand-rolled comparison that is right on the examples and wrong on `~> 0.0`
against `0.1.0`. A separate case asserts that a requirement string which is not the two-segment
`~> M.N` form is **refused**, not silently reinterpreted.

**The `SEAM-27` composition tests** are the specification's own conformance example plus the five
neighbouring cases verified during planning — trailing slash, empty operation path, no base path,
dangling `&`, both paths absolute — plus the fragment rejection, plus a path value containing `/`
asserted to arrive as `%2F` and not as two segments. That last is the seam's security property and
it gets its own test rather than riding on a composition assertion.

**Property tests, bounded** (`testing/f36a19cd`, and phase 0's `#sample(count:, seed:)`):
`Operation#build_request` over generated path values including `/`, `?`, `#`, a space and invalid
UTF-8, asserting the assembled URL always parses back with `URL.parse!` and always has the expected
number of path segments; and the version-comparison grid above.

**Negative tests at every error boundary** (`testing/62f8f4ec`): each raises the expected class,
carries a message naming the seam and the offending value, and leaves no partial side effect — a
registry is still usable after a rejected `register`, a `Completer` is still usable after a rejected
`fulfil`, an `Operation` is still usable after a rejected `build_request`.

**Visibility is asserted with `respond_to?`, never with `assert_predicate`** — phase 1's finding,
which bites here too: `Future#settled?` and `Cancellation#cancelled?` are public and
`Cancellation.new` and `Operation.new` are private, and Minitest sends past `private` on the 3.2
floor. (`Future.new` is deliberately **not** private — see the pivot section above.)

**One test asserts the fake transports themselves conform**, because a fake that has drifted from
the seam is a suite that proves nothing: `Dexpace::Transport.conforms?(FakeTransport.new)` and
`Dexpace::AsyncTransport.conforms?(FakeAsyncTransport.new)` and
`Dexpace::Serde.conforms?(FakeCodec.new)`.

## Design §3 Addendum — what this phase adds to the seam mapping

Design §3 is frozen and is not edited here. Two additions, each with a Deviation Ledger row for
consolidation into design §10.

| Addendum | What §3 says | What phase 2 builds |
|---|---|---|
| **A1 — `SEAM-27`'s base composition is not reference resolution** | §3.5: "Base-URL composition uses `URI.join`/`URI#merge` for RFC 3986 reference resolution and never re-parses a re-rendered string" | A hand-built composition implementing `SEAM-27`'s four rules directly. Verified: `URI::RFC3986_PARSER.join("https://host/c?sig=1", "/pets")` is `"https://host/pets"` on 3.2.11 and 4.0.6, dropping the base path segment and the base query that `SEAM-27`'s own conformance example requires to survive. §3.5's sentence remains correct where reference resolution is what is wanted — `REDIR-13`, phase 6 — and there the spelling is `URI::RFC3986_PARSER.join`, because `URI.join` is banned by phase 0's cop |
| **A2 — the async-transport seam is a second registry, and the executor is not a seam** | §3.6: "three seams still need a resolution story: transport (sync and async), serde, and the async executor" | Three registries — synchronous transport, asynchronous transport, serde — and **no executor registry**, because `SEAM-18` requires the executor to be caller-supplied "with no default" and an auto-resolved executor is that default. §11.8's "`XCUT-23` has three instances here" still holds, with a different membership |

## Design §9 Addendum — the sixth cop

Design §9's gate table is frozen and is not edited by this phase. One addition, recorded here as
phase 0 recorded its three, with a Deviation Ledger row.

| Addendum | What §9's table says | What phase 2 builds |
|---|---|---|
| **A1 — the qualified-core-constant cop** | Nothing. Phase 0 recorded the `Dexpace::Serde::JSON`/`Dexpace::Async::Thread` shadowing hazard in a YARD block and asserted the qualified form resolves; there is no gate | `Dexpace/QualifiedCoreConstant`, a blocking custom cop rejecting a bare `Thread`, `Queue`, `Mutex`, `SizedQueue`, `ConditionVariable` or `JSON` inside `lib/dexpace/async/**` and `lib/dexpace/serde/**` and requiring the `::`-qualified form. Verified: a bare `Thread` inside `module Dexpace::Async` resolves to Ruby's `Thread` until `dexpace-async-thread` is required and to `Dexpace::Async::Thread` afterwards, and core's own suite never requires that gem — so this is a bug that cannot fail in the tree that contains it. The cop ships with rejected and accepted cases in phase 0's data-driven suite |

## Deviation Ledger

Each row is consolidated into design §10 and audited by `docs/deviations.md`. Phase 2 does not edit
design §10; it is frozen.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P2-1 | The asynchronous transport seam gets its own top-level constant `Dexpace::AsyncTransport` and its own registry; there is **no executor registry** | design §3.6, §11.8; `SEAM-2`, `SEAM-18` | `SEAM-2` enumerates sync and async transport as two seams, so one registry keyed by kind merges two concerns the requirement separates. The name is not `Dexpace::Transport::Async` because that constant would sit beside the adapter namespaces `Dexpace::Transport::NetHTTP` and `::AsyncHTTP`. The executor is not a registry because `SEAM-18` requires it to be caller-supplied "with no default", and an auto-resolved executor is exactly that default; §11.8's count of three resolution instances survives with a different membership. Addendum §3-A2 |
| P2-2 | `Dexpace::Serde::Error` is a **class**, inverting phase 1's module root for a seam-local hierarchy | `SEAM-23`; design §3.4; P1-2 | `SEAM-23` asks for a hierarchy with encode/decode subtypes, open for adapters to extend. Phase 1's module root exists because `XCUT-4` puts transport errors in Ruby's `IOError` family; no competing family exists here, because `SEAM-20`/`SEAM-21` propagate genuine stream I/O errors unwrapped. The class includes `Dexpace::Error`, so `rescue Dexpace::Error` still catches it. The rule for every later phase: the SDK root is a module, a seam-local root with no competing family is a class |
| P2-3 | `SEAM-27`'s base-URL composition is hand-built and is **not** RFC 3986 reference resolution | design §3.5; `url-and-query-encoding/ef5ecf25` | Verified on 3.2.11 and 4.0.6: `URI::RFC3986_PARSER.join("https://host/c?sig=1", "/pets")` and `#merge` of the same both yield `https://host/pets`, dropping the base path segment and the base query that `SEAM-27`'s conformance step requires to survive. Reference resolution keeps its place at `REDIR-13`, phase 6, where the sanctioned spelling is `URI::RFC3986_PARSER.join` — `URI.join` is banned by phase 0's `Dexpace/NoUriDefaultParser`. Filed as a corpus note. Addendum §3-A1 |
| P2-4 | `SEAM-18`'s "restore the interrupt flag … surface an interrupted-I/O error" is read as cooperative cancellation raising `Dexpace::CancelledError` | `SEAM-18`; design §10.4, §10.5; `XCUT-2`, `XCUT-4` | Ruby's pre-emption primitives are forbidden (§8.3), so no interrupt is ever delivered and the flag clause is vacuous for the same reason `ASYNC-4` is. The error is typed rather than an `IOError` because `XCUT-4`'s I/O family is for transport failures and a cancellation is not one, and because `XCUT-2` requires the distinction to be readable out-of-band rather than from a message |
| P2-5 | The pivot's blocking wait takes `cancellation:` and not `deadline:` in this phase | design §3.3's `#value(deadline: nil)`; `CFG-15`–`CFG-21` | `SEAM-18`'s interruption clause is about cancellation; deadlines need phase 5's clock and interruptible-delay primitives, and building a deadline here would fix their shape a phase early. Adding the keyword later **widens** a signature, so `NFR-4`'s "disappears or narrows" lock is not prejudiced. `DEF-28` |
| P2-6 | `SEAM-8`'s warning is emitted through `Kernel#warn` | `SEAM-8`; design §8.1 | Verified: `Kernel#warn` routes through `Warning.warn`, so a host can intercept, redirect or silence it, and it is suppressed when `$VERBOSE` is `nil`. `SEAM-8` is a SHOULD asking for a warning rather than a failure, which is exactly what a suppressible advisory channel is for. §8.1's facade does not exist until phase 5 and may add an event then; it does not replace this |
| P2-7 | `DEF-21`'s version comparison is hand-rolled and accepts only `~> MAJOR.MINOR` | design §2.3; `NFR-14`; phase 0's require allowlist | Verified: `Gem` and `Gem::Version` are undefined under `ruby --disable-gems` on 3.2.11 and 4.0.6, and `rubygems` is not on the allowlist. Restricting the accepted form to the two-segment `~>` the design mandates means one rule with one meaning rather than a partial `Gem::Requirement` reimplementation; anything else is refused. The test cross-checks the comparison against `Gem::Requirement` over a grid, where RubyGems is present |
| P2-8 | A sixth custom cop, `Dexpace/QualifiedCoreConstant` | design §9's gate table; phase 0's P0-3 precedent | Verified: a bare `Thread` inside `module Dexpace::Async` silently rebinds to `Dexpace::Async::Thread` when the adapter gem is required, and core's own suite never requires it — a bug that cannot fail in the tree that contains it. Addendum §9-A1 |
| P2-9 | **Private** snapshot `Data` types — `Registry::State`, `Registry::Claim` and `Cancellation::Source::State`, all `private_constant` — do not include `Dexpace::Model` and expose no `.build` | phase 1's construction rule; `data-modeling/677b01de` | Phase 1's rule governs public models, and each of its three reasons is about a public constructor: `.build` is public API, `#with` routes derivation through it, and `send(:new, …)` reaches the constructor anyway. A `private_constant` snapshot has no public constructor, no caller derivation and no required-field contract, and including `Model` would put a `#with`→`.build` round trip on the registry's write path with no validation to run. They stay `Data` because `concurrency-and-async/2c743901` asks for immutable `Data` at every concurrency boundary, which is exactly what they are. The rule and its boundary: **a `Data` that is public API follows phase 1's construction rule without exception** — `Dexpace::Async::Settlement` and `Dexpace::Operation` both do — and only a `private_constant` snapshot is exempt |
| P2-10 | `Dexpace::Registry` is public API — YARD, RBS and a surface-manifest row — where the design names no such constant | design §3.6; `api-design/b0e18938` | `SEAM-5`–`SEAM-9`'s five branches are implemented once and delegated to by three seams; documenting them once on the class beats documenting them three times on the delegators, and a third-party seam author needs the same mechanism. The alternative — an internal helper — still appears in the runtime surface manifest, because that gate walks `Dexpace`'s constant tree, so "internal" would have bought a YARD exemption and nothing else |
| P2-11 | Six public methods and one public class method the design's §3 does not name: `Cancellation.over`, `Cancellation#merged_with`, `Completer#await`, `Completer#request_cancel`, `Completer#settled?`, `Completer#outcome`, `Registry.callable?`, `Cancellation::Source#cancelled_at` | design §3.3, §3.6; `NFR-4`; `api-design/b0e18938` | `NFR-4` locks every public signature at the first release tag, so a name that arrives by accident is locked by accident. Each survives for a stated reason: `.over` is the class-level constructor `#merged_with` and phase 5's deadline source both need; `#merged_with` exists so `#sources` can stay **protected**, which a class-method `.any` cannot do; `#await` and `#request_cancel` are what the `Future` facade delegates to, and Ruby offers no package-private visibility that would let the facade reach them otherwise — the alternative is a cross-object `send`, a hole in the boundary the pair exists to draw; `#settled?` and `#outcome` are the producer's legitimate "did I lose the race" query; `Registry.callable?` is the runtime half of the `#call` duck type both transport seams share, and lives on `Registry` because `Registry` is what validates a provider; `Source#cancelled_at` is what a composed token orders its sources by, and is what lets a token subscribe to nothing at construction. `Serde::CONTRACT`, `Operation::TARGETS`, `Registry::State`, `Registry::Claim` and `Cancellation::Source::State` are all `private_constant` for the same reason |
| P2-12 | The `SEAM-8` warning is observed in tests through a block-scoped `WarningCapture`, not through phase 0's warning allowlist | phase 0's `test/support/dexpace_test_case.rb`; `NFR-6` | The design said this phase would add the first entry to phase 0's zero-entry allowlist. An allowlist entry is a message pattern that stays permitted for the life of the suite, so every later warning matching it is swallowed too, and it presumes an allowlist API shaped the way the design guessed. `WarningCapture` prepends to `Warning`'s singleton class **after** phase 0's raising module, so it sits ahead in the ancestor chain, records only inside its own block, and delegates outside it — verified on 3.2.11, 3.4.10 and 4.0.6. Narrower, and it needs nothing of phase 0 but the ordering |
| P2-13 | Both `SEAM-18` bridges live in a `Dexpace::Bridge` namespace, one file each, rather than under the seam module that exposes them | design §3.3, §5.3; P2-1 | The design names neither constant. `Dexpace::Transport::AsyncOver` would sit beside the adapter namespaces `Dexpace::Transport::NetHTTP` and `::AsyncHTTP`, and a reader meeting three constants there cannot tell which one core owns — which is exactly the seat P2-1 keeps the async *seam* out of. Both bridges are also `Dexpace::Closeable` with `owned: false`, which is what makes `SEAM-14`'s "both transport seams MUST be closeable" true of the two transports this phase actually ships |
| P2-14 | `Cancellation#on_cancel` returns a `Cancellation::Subscription` handle rather than `self`, and `Cancellation::Source` gains a public `#off_cancel(hook)` | design §3.3; `SEAM-13`, `SEAM-18`; `NFR-4` | The design describes registration and says nothing about withdrawing one, which leaves `Completer#await` no way to detach the hook it arms on the caller's token. That hook reaches the `Completer` and through it the response the future settled with, so `.any(client_token, per_call_token)` with `future.value(cancellation:)` — what phase 5's `DEF-28` does on every request — retained one closure and one response per request on the client-lifetime source: measured 200 of 200, and 500 100 KB responses still reachable after `GC.start`, on 3.2.11, 3.4.10 and 4.0.6. Composing without subscribing fixes only the composition half of that leak. The cost is one public constant and one public method, both locked by `NFR-4` at the first release tag, which is why they are here and not in a comment |
| P2-15 | `Dexpace::Hooks`, a `private_constant` module supplying the one `notify(hooks, argument)` loop `Cancellation::Source#cancel`, `Completer#settle` and `Completer#request_cancel` all run | design §3.3, §3.7; `SEAM-18` | The design describes the notification three times and names no home for it, and a bare `hooks.each { |hook| hook.call(…) }` at each site drops every handler after a raising one and propagates to whoever published the state — the `SEAM-18` "a second waiter blocks forever" failure from the write side, verified on all three interpreters. One implementation runs the whole list and then re-raises the first failure; re-raising rather than dropping, because phase 2 has neither of §3.7's disposal routes (`DEF-24`, phase 4; §8.1, phase 5) and a handler raising into a void is a bug nothing reports. `DEF-32` carries the failures after the first. It is a `private_constant` and therefore not public API: no `sig/` mirror, no YARD gate entry, no surface-manifest row |

## Deferrals Filed by Phase 2

Filed against `docs/deferred-items.md`; each names a target phase or an explicit pick-up condition,
per the roadmap's execution step 7. (The heading avoids the literal words the housekeeping probe's
`registers` check reserves for the aggregate register, which is where these rows live.)

| ID | Deferral | Target / condition |
|---|---|---|
| `DEF-27` | `Dexpace.close_quietly`'s two error-disposal routes — the suppressed trail and the instrumentation diagnostic. Phase 2 ships the helper with the rescue and the null-safety and drops the rescued error, stated in the YARD block and asserted in a test | Phase 4 supplies the first route with `DEF-24`'s `#suppressed`; phase 5 supplies the second with §8.1's facade and closes the row |
| `DEF-28` | `#value(deadline:)` and `#wait(deadline:)` on the pivot, and the clock behind them | Phase 5, with `CFG-15`–`CFG-21`. Adding the keyword widens the signature, so it is not an `NFR-4` break |
| `DEF-29` | Moving the in-memory fake transport, async transport and codec out of `gems/dexpace-core/test/support/` and into `dexpace-conformance` | Condition: the first consumer outside `dexpace-core`. Phase 8 at the earliest, alongside `DEF-22`'s assertion objects |
| `DEF-30` | Presence-gated auto-activation, which §3.6 permits for instrumentation only | Condition: an instrumentation seam exists to activate — phase 5 at the earliest, and the first user is `dexpace-instrumentation-otel` (`DEF-17`), which is post-v1 |
| `DEF-32` | The handler failures `Dexpace::Hooks.notify` drops after re-raising the first. Every hook runs and the first failure is re-raised; the rest have nowhere to go, because §3.7's two disposal routes do not exist yet | Phase 4, with `DEF-24`'s `Dexpace::Error#suppressed` — the first carrier a second failure can attach to. Phase 5 may add a diagnostic per dropped failure once §8.1's facade exists; it does not replace the trail |
| `DEF-31` | `SEAM-25`'s lifecycle event — "only the first close shuts the owned executor **and emits the lifecycle event**". `Dexpace::Closeable` implements the idempotent, ownership-aware release; there is no event facade to emit through | Phase 5, with §8.1's instrumentation facade. The emitting adapter is phase 8's `dexpace-async-thread`, the first thing in this repository that owns an executor |

### Deferral-register sweep

The roadmap's execution step 1 requires every phase to read the whole register and disposition every
row, not to scan for its own name. All twenty-six rows were read.

**Phase 2 picks up one row, gives one row a target it did not have, and marks none UNSCHEDULED.**

- **`DEF-21` — picked up.** Its pick-up condition names phase 2 explicitly: "phase 2 (Seam
  Foundations), with the registration call it belongs to." Phase 2 defines that call, so the runtime
  half of the version-skew guard lands with it, as the required `core:` keyword on
  `Registry#register`. `Status` moves to `picked-up (2026-09-07, phase 2)` and the row stays, so
  every existing citation of `DEF-21` still resolves.
- **`DEF-1` — the `SEAM-28` half now targets phase 5; the `SEAM-24` half is untouched.** This is the
  only other row whose requirements are inside phase 2's ID range and whose code would live in the
  gem phase 2 ships. Phase 2 builds neither. `SEAM-28` is a MAY whose two halves both need machinery
  this phase does not have — the request's context chain (`CTX`, phase 4) and a consumer for the
  identifier (instrumentation, phase 5) — so **phase 5** is where it first has both, and that is the
  target the sweep supplies. **UNSCHEDULED would be wrong**: that status is for a row whose pick-up
  condition a phase *met* and declined to act on, and this row's condition ("no named trigger …
  picked up opportunistically") never fired, because the opportunity does not exist until the
  context chain does. `SEAM-24` keeps its existing condition — it ships with `dexpace-async-async`
  (`DEF-11`), which is post-v1 — and phase 2 notes only that it fixes the contract `SEAM-24`'s
  cancellation half will map: `Cancellation` in one direction and `Completer#on_cancel` in the
  other.
- **`DEF-22` — untouched, and it now carries a checklist row.** Several `SEAM` MUSTs are properties
  of an *implementation* rather than of a seam — `SEAM-12`'s concurrency safety, `SEAM-13`'s
  cancellation honouring, `SEAM-14`/`SEAM-25`'s real ownership over a resource the SDK created,
  `SEAM-30`'s orphan close in a real adapter. Phase 2 satisfies what a seam can satisfy and core's
  own implementations satisfy the rest — but **`SEAM-12` is marked ⏳ against this row rather than
  ✅**, because the phase ships no transport implementation at all and a requirement about
  implementations cannot be met by a shape. `SEAM-13`, `SEAM-14`, `SEAM-25` and `SEAM-30` stay ✅
  because each has something in this phase that actually implements it — the third argument and its
  token, `Dexpace::Closeable` and the two bridges that take it, and `Completer#fulfil`'s orphan
  close. No new deferral is filed, because filing one would duplicate `DEF-22`.
- **`DEF-18` — untouched.** `ASYNC-3`, `ASYNC-4` and `PIPE-33`'s interrupt clause are phase 8's to
  mark. Phase 2 is where the cooperative-cancellation shape that causes them is fixed, and it says
  so in "Out of scope" above rather than re-opening the trade.
- **`DEF-24`, `DEF-25`, `DEF-26` — untouched.** Phase 1's three. `DEF-24`'s suppressed trail is what
  `DEF-27` waits on and its target stays phase 4; `DEF-25`'s wire-boundary re-validation stays phase
  8; `DEF-26`'s body typing stays phase 3. Phase 2 does not narrow `Request#body`'s signature and so
  does not touch `DEF-26`.
- **`DEF-2` — untouched.** Phase 1 gave it phase 6 as a target and phase 2 ships no header helper.
- **`DEF-3`–`DEF-10` — untouched.** Requirement-level deferrals in `BODY`, `PIPE`, `RECOV`, `RETRY`,
  `REDIR`, `SSE`, `OBS` and `TRANSPORT`. None is reachable from a phase that ships only the seam
  layer.
- **`DEF-11`–`DEF-17` — untouched.** Post-v1 gems, out of the MVP by construction. `DEF-17`
  (`dexpace-instrumentation-otel`) is named by `DEF-30` as the first user of presence-gated
  activation, which adds a pointer rather than changing the row.
- **`DEF-19`, `DEF-20` — untouched.** Release-gated; nothing is published and every gem is still at
  `0.0.0`.
- **`DEF-23` — untouched, and the condition was checked rather than assumed.** A Steep target over a
  test tree is picked up "when a gem's test support becomes production-quality code worth checking".
  Phase 2 adds three fakes and a probe `Fiber.scheduler` to `gems/dexpace-core/test/support/`, which
  is the closest that condition has come to being met. It is still not met: the fakes exist to be
  registered and called, they have no invariants a type checker would catch, and `DEF-29` already
  says the moment they become production-quality is the moment they move into `dexpace-conformance`
  — which is where phase 0 put the condition's earliest trigger. Left untouched rather than marked
  UNSCHEDULED, because the condition was not met.
