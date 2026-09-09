# Phase 6b — Redirect

**Status:** Draft, for review. Written 2026-09-09, against
`docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md`, which is this sub-phase's charter and is not
re-derived here.

## Purpose

Sub-phase 6b builds the synchronous redirect pillar step: one iterative follower occupying `Stages::REDIRECT`
(order 200), forking a fresh `Cursor` for every hop it drives — the first included — resolving `Location`
against the current hop through `URI::RFC3986_PARSER`, enforcing every credential-hygiene rule against the
**seed** origin rather than the previous hop, and managing response-body lifecycle deterministically across the
loop. Twenty-eight `REDIR` IDs, one specification chapter, no second gem.

**The correctness stake this sub-phase carries is not one clause among twenty-eight.** `REDIR-7`'s unconditional
`Authorization` strip on every re-issue and `REDIR-11`'s cross-origin suppression signal are the two clauses
that stop a bearer token surviving a cross-origin redirect, and `REDIR-8`'s seed-origin comparison is what both
rest on. The charter's deviation §10.15 already fixed the *mechanism* — the signal is cursor state, not a
request header, so forgery is structurally impossible rather than defended against — and this document treats
that fix as settled and builds against it; what remains is `6b`'s half of a contract whose other half `6c` reads.

**Independence, stated because a plan will otherwise inherit a chain that does not exist.** `6a`, `6b` and `6c`
are three independent segments (charter, *The cut*). `6b` depends on phases 0–5 for everything it needs; its
dependency on `6a` and on `6c` is **empty**, with two named exceptions, both already flagged by the charter and
both handled below rather than silently reimplemented:

- **`OI-31`'s cursor widening (`R13`)** — assigned to `6a`. `6b`'s emission task (`R8`) takes its own
  `logger:`/`redactor:` constructor keywords regardless of whether the widening exists, so `6b` neither blocks
  on it nor builds it. See *Prerequisites* below for the concrete consequence if `6b` lands first.
- **`Dexpace::Resilience::Resend.eligible?(request)`** — the replayability predicate `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md`'s forward
  table names as phase 6's, and which `RETRY-5`, `REDIR-6` and `AUTH-31` all consult (`docs/sdk-design-ruby/05-pipeline-architecture.md`
  §5.2). The charter's `R5` gives `6a` the visibility decision and "confirms or changes" it, but does not say
  `6a` builds it *first*. `6b` needs it for `REDIR-6` regardless of landing order, so this document's plan
  builds it as one of `6b`'s own tasks, under the `Dexpace::Resilience` namespace 3b already named — not under
  `Dexpace::Redirect` — precisely so that whichever of `6a`/`6b` lands second finds the file already there and
  consumes it rather than duplicating it. If `6a` lands first, `6b`'s task for it is deleted and `6b` cites
  `6a`'s file instead. Neither sub-phase may put a second predicate under a different name.

**One correction to the charter, verified rather than inherited, per this document's own instruction to verify
every prerequisite before asserting it.** The charter's *Prerequisites* section wrote `Dexpace::HTTP::URL.parse!`
throughout (**corrected in place on 2026-09-09**, after this finding). Verified against `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model.md` (the actual
phase-1 plan, not a paraphrase of it): the file is `lib/dexpace/http/url.rb`, but the constant it defines is
**`Dexpace::URL`**, flat — `module Dexpace; module URL; ... end; end` — with no `Dexpace::HTTP` module anywhere
in phase 1's shipped surface (grep over every `module`/`class` line in the phase-1 plan confirms it: `HeaderName`,
`Headers`, `Status`, `Method`, `Protocol`, `URL` are all direct children of `Dexpace`, per `P1-1`'s "public
constants are flat unless the design namespaced the subsystem" — and §3 namespaces nothing). This document cites
`Dexpace::URL.parse!` / `.external_form` throughout and does not repeat the charter's slip. It is recorded as a
finding below rather than corrected in the charter here, which is this
sub-phase's to consume and not to edit.

## Governing documents

- `docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md` — the charter. Fixes `6b`'s 28 IDs, the
  fourteen spec-forced boundaries that touch redirect, `R7`–`R9`, and the independence statement this document
  restates rather than re-derives.
- `docs/product-spec/10-redirect-handling.md`, read in full (28 lines, four subsections), with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` for the canonical text of all 28
  `REDIR` IDs (`grep -n '^| REDIR-1 '` through `REDIR-28`, verified for this document).
- `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md` §6.2 in full — the cross-origin marker, the
  seed-origin triple, `URI.join`/`#merge` resolution, the lifecycle rules.
  `docs/sdk-design-ruby/05-pipeline-architecture.md` §5.1 in full — cursor-scoped state, the two rules §6.2 rests
  on, the write restriction.
  `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` item 15 (§10.15, quoted below)
  and item 17 (the cancellable wait, touched only incidentally here).
- `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md` — the contract this sub-phase
  implements against: the sixteen-stage table, `Cursor#fork(state:)`/`#state(stage)`/`#may_fork?`/`#spent?`, the
  stage-namespaced write restriction, `R11`'s five negative assertions and the note it files
  (`pipeline/86343352`) that a driving pillar step forks for *every* drive, the first included, and never calls
  its own `#call`.
- `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model.md` and `-design.md` for `Dexpace::URL`,
  `Dexpace::Request`/`Request::Builder`, `Dexpace::Response`/`Response::Builder`, `Dexpace::Headers`/
  `Headers::Builder`, `Dexpace::Method`, `Dexpace::Model`, `Dexpace::InvalidArgumentError`.
  `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` for `Dexpace::Cancellation`, the async
  pivot's real names (`Dexpace::Async::Future`/`::Completer`/`::Settlement`, never `Dexpace::Future`), and the
  error-class shape (`class X < ::StandardError; include Dexpace::Error; end`).
  `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md` for `Dexpace::Body#replayable?`/
  `#to_replayable`, `Response#close`, and the forward-named `Dexpace::Resilience::Resend.eligible?(request)`.
  `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md` for the error-class shape's
  precedent and `Dexpace.close_quietly`.
  `docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md` for
  `Dexpace::Instrumentation::Logger`/`Logger::NULL`, `Event`, `Keys`, `Events`, `Redactor`/`Redactor::DEFAULT`,
  `Severity` — the machinery `R8` reuses.
- `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-design.md` and `.../phase5b` as the worked
  precedent for this document's shape, depth and section naming.
- `docs/deferred-items.md`, `docs/open-items.md`, `docs/deviations.md`, `docs/first-release.md` (read, not
  edited — findings are described below for a human to file).
- `CLAUDE.md` and `docs/README.md`.

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run before this document was written.
`ruby scripts/knowledge.rb --origin note --brief` returns the same 37 entries across 18 note files the charter
already reports; `--section conflicts --brief` returns the same 24 entries, all six harvested ones printing
`[overridden by notes/…]`. **None is open**, so `6b` inherits no unresolved conflict.

`ruby scripts/knowledge.rb --prefix-info REDIR` confirms **28 of 28 IDs substantive, 0 roll-up only, 0 uncited**,
owning chapter `docs/product-spec/10-redirect-handling.md`, topics `redirect-handling`, `sdk-positioning`,
`redaction-and-security`. `--gaps REDIR` returns **0 of 28 with no substantive entry**, so `6b` budgets no
appendix-C-only reading beyond the 28-line chapter, which was read in full anyway because its
`*Conformance:*` clauses are not in appendix C and several are load-bearing (`REDIR-8`'s worked example,
`REDIR-14`'s `/v2/x` example, verified against a real interpreter below rather than trusted).

`ruby scripts/knowledge.rb --prefix REDIR --section rules --brief` returns 32 entries across two topic files
(`redirect-handling`, `redaction-and-security`), zero `[appendix-B roll-up]`-tagged. One entry is overridden:
`redirect-handling/d4885fbc` ("wire-exact preservation... satisfied by resolving through `URI.join`/`URI#merge`
and never round-tripping through a re-rendered string") prints `[overridden by notes/url-and-query-encoding.md:8]`.

**The note this override points at is `url-and-query-encoding/08c54234`, and it is quoted rather than
paraphrased because `R7` is built directly on it:**

> `SEAM-27`'s base-URL composition is not RFC 3986 reference resolution, and `URI.join` is banned by a phase-0
> cop; where resolution genuinely is wanted the spelling is `URI::RFC3986_PARSER.join`. ... **Second, the
> spelling is unusable as written.** Phase 0's `Dexpace/NoUriDefaultParser` cop bans `URI.join` along with the
> rest of the `URI.parse`/`URI.split` family... The sanctioned forms... are `URI::RFC3986_PARSER.join(base, ref)`
> and `#merge` on a URI that was itself parsed with `URI::RFC3986_PARSER`... Where this matters next is
> **phase 6**: the redirect-handling entry corrected above tells the redirect step to resolve through
> `URI.join`/`URI#merge` for `REDIR-13`'s wire-exact preservation, and the *semantics* there are right — a
> redirect target genuinely is a reference resolved against the previous URL — but the literal `URI.join` will
> fail the build, so that step writes `URI::RFC3986_PARSER.join`. One further caveat for any test written near
> this code: `URI::InvalidURIError`'s message differs by a space between 3.2.11 (`bad URI(is not URI?)`) and
> 4.0.6 (`bad URI (is not URI?)`), so no assertion may match it — phase 1's `Dexpace::URL.parse!` converts it to
> a `Dexpace::InvalidArgumentError` carrying the offending input, and that is what to assert on.
> <sub>review · `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` · high · sha:manual-phase2-seam27-composition</sub>

Two things this note settles for `6b` and one it does **not**: the spelling is `URI::RFC3986_PARSER.join`, the
semantics ("a redirect target genuinely is a reference resolved against the previous URL") are right and need no
correction, but the closing sentence's "phase 1's `Dexpace::URL.parse!` converts it" is **not** a route `6b` can
take — `Dexpace::URL.parse!` rejects a non-absolute URI (`HTTP-47`) and `REDIR-14` requires resolving a relative
`Location`, so `Dexpace::URL.parse!` cannot be handed the raw `Location` string at all. `R7` below resolves this
precisely: `6b` calls `URI::RFC3986_PARSER.join` directly, not through `Dexpace::URL`, and converts the resulting
`URI::InvalidURIError` itself, by class, exactly as the note's caveat requires ("no assertion may match it").

**`pipeline/86343352` is quoted once, in full, because it is the rule `6b`'s step is built on and getting it
backwards silently drops `REDIR-11`'s marker on hop 1:**

> **This port's rule is: a pillar step that may drive more than once forks for *every* drive, the first
> included, and never calls its own `#call` at all** … because the fork is also where cursor-scoped state is
> written (`docs/sdk-design-ruby/05-pipeline-architecture.md` §5.1, and §6.2's cross-origin marker), so a first
> drive that ran on the un-forked handle would have no stage slot to write and hop 1 could publish nothing. …
> writing the mixed shape the harvested sentence describes compiles, passes every ordering test, and silently
> drops whatever the pillar meant to publish on its first drive.
> <sub>review · `docs/work/mvp/phase4/phase4c/2026-09-08-phase4c-stage-pipeline-design.md` · high · sha:manual-phase4c-cursor-latch</sub>

The same entry's `P4-33` — `#call`'s reuse guard is sequential-only, 29/2000 races through on 3.2.11 and 0/2000
on 3.4.10/4.0.6 — is inherited as a fact `6b` must not misread as a concurrency guarantee; `6b` writes no test
asserting the race and does not treat the raise as anything but a single-cursor, single-thread defect detector.

**The audit group run for this document** is the eleventh row the charter says is owed to the
`knowledge-lookup` skill and could not add itself (constrained to write one file): `ruby scripts/knowledge.rb
--prefix RETRY,REDIR,AUTH --section rules --brief` and `--topic retry-and-resilience,redirect-handling,
authentication,cancellation-and-timeouts --section rules --brief`, run for the `REDIR` slice of it: clean, zero
roll-up, nothing contradicting a decision below. **This document does not add the row to the skill file** — that
edit is outside `docs/work/mvp/phase6/phase6b/` and is therefore not this document's to make; it is named again
under *Findings for the registers* so it is not lost twice.

**No note is filed by this document.** One candidate exists — `URI::Generic#userinfo = nil` being a silent
no-op for `REDIR-12` — and the charter already assigns it to `6b` "to file with the design that acts on it." It
is recorded in full under *Verified Ruby facts* below, with the exact note text a human should file, per the
instruction that register and note edits are described here, not made here.

## Scope: the 28 IDs, with dispositions

**28 IDs: 23 MUST, 4 SHOULD (`REDIR-10`, `REDIR-21`, `REDIR-23`, `REDIR-28`), 1 MAY (`REDIR-27`)**, matching the
charter's reconciliation against appendix C exactly.

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `REDIR-1`–`REDIR-26`, `REDIR-28` | 27 |
| ⏳ deferred, `DEF-7` (pre-existing), no named trigger — the configurable target-header MAY | `REDIR-27` | 1 |
| **Total** | | **28** |

Three rows carry a clause the checklist must state rather than tick, named by the charter and confirmed here:

- **`REDIR-11`** — clause (a) satisfied **structurally** (a `Location` value cannot reach cursor state at all;
  there is no code path from the wire to `#fork`'s `state:` argument); clause (b) is implemented by `6c`, not
  here — `6b`'s obligation is to write the marker `true` only on an actually-cross-origin hop and `false`
  (or omit it — see the object model below) otherwise, never the reverse; clause (c) is satisfied *a fortiori*,
  because nothing is ever added to the request, so nothing needs removing before dispatch.
- **`REDIR-25`** — satisfied by shipping no async redirect step at all. `Dexpace::AsyncPipeline` gains no
  `Redirect::AsyncStep`, and `Stages::REDIRECT` stays installable-but-unused on the async path exactly as 4c
  left it (`PIPE-28`). The substantive clause stays vacuous until `DEF-39`'s async standard pipeline exists,
  which is a phase-level task this sub-phase does not own — see *Prerequisites*.
- **`REDIR-8`** — the triple is `[scheme.downcase, host.downcase, effective_port]`, compared against the
  **seed** request's URL, never the previous hop's, and never `URI#==`. Verified fact 3 below is why the
  `downcase` calls are not optional and why the port half is free.

## Object model `6b` ships

All under `lib/dexpace/redirect/`, per `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` §2.3's
`lib/dexpace/{...,redirect,...}` slot — a directory the layout table already reserves, distinct from `resilience/`
(`6a`'s) and `auth/` (`6c`'s).

| File | Constant | Visibility |
|---|---|---|
| `lib/dexpace/redirect/step.rb` | `Dexpace::Redirect::Step` | public — the pillar step |
| `lib/dexpace/redirect/condition_snapshot.rb` | `Dexpace::Redirect::ConditionSnapshot` | public — `R9` |
| `lib/dexpace/redirect/events.rb` | `Dexpace::Redirect::Events`, `::Keys` | public — `R8` |
| `lib/dexpace/redirect/location.rb` | `Dexpace::Redirect::Location` | `private_constant` — `R7` |
| `lib/dexpace/redirect/origin.rb` | `Dexpace::Redirect::Origin` | `private_constant` |
| `lib/dexpace/redirect/errors.rb` | `Dexpace::Redirect::SchemeDowngradeError` | public (an error class, per `SEAM-29`'s neighbourhood) |
| `lib/dexpace/resilience/resend.rb` | `Dexpace::Resilience::Resend`, `::NotReplayableError` | public — shared with `6a`/`6c`, see *Independence* |

`Location` and `Origin` get **no `sig/` mirror and no dedicated test file**, following 5a's precedent for
`ConfigParsers`/`DeepValue`: both are asserted only at `Step`'s own call sites, because neither is public API and
a dedicated suite would test an implementation detail rather than a contract.

**`Dexpace::Redirect::Step`** is a plain class, not a `Data` — it is an implementation of the pillar-step duck
type and holds injected collaborators, the same reasoning `data-modeling/3e37c086` gives `Dexpace::Clock` and
5b gives `Dexpace::Instrumentation::Step`. Constructor:

```ruby
Dexpace::Redirect::Step.new(
  allowed_methods: Dexpace::Redirect::Step::DEFAULT_ALLOWED_METHODS,  # REDIR-3, REDIR-4, REDIR-26
  follow303: false,                                                  # REDIR-5
  max_hops: 3,                                                       # REDIR-17
  allow_scheme_downgrade: false,                                     # REDIR-15
  predicate: nil,                                                    # REDIR-20
  logger: Dexpace::Instrumentation::Logger::NULL,                    # R8
  redactor: Dexpace::Instrumentation::Redactor::DEFAULT               # R8
)
```

**`DEFAULT_ALLOWED_METHODS` is `6b`'s own frozen `Set` of `Dexpace::Method` — `{GET, HEAD}` — and it is not
`Dexpace::Method::IDEMPOTENT`.** The two are easy to conflate and the spec deliberately keeps them apart:
`HTTP-9`/`RETRY-6`'s idempotent set is five methods (`GET, HEAD, OPTIONS, PUT, DELETE`) and governs *retry*
re-sendability; `REDIR-3`/`REDIR-4`'s default allowed-method set for 301/302/307/308 following is exactly
`{GET, HEAD}` and governs whether a redirect is followed *at all*. Reusing `IDEMPOTENT` here would silently
widen redirect-following to `OPTIONS`, `PUT` and `DELETE`, which the specification's own default table does not
grant. `Step` builds its own two-member `Set` from `Dexpace::Method.of("GET")`/`.of("HEAD")` and validates a
caller-supplied collection the same way `RETRY`'s and `AUTH`'s configuration objects validate theirs — duplicated
and frozen at construction (`REDIR-26`), decoupled from the caller's own array.

**`Dexpace::Redirect::ConditionSnapshot`** — `Data.define(:response, :redirect_count, :visited_uris)`, following
phase 1's domain-model pattern (`private_class_method :new`, a validating `.build`, `Model.required!`). `R9`
below argues why it is public and `NFR-4`-locked rather than a private detail, and why `visited_uris` is a frozen
`Set` of `Dexpace::URL.external_form` strings rather than of `URI::Generic` objects or of `Request`s.

**`Dexpace::Redirect::Location`** (`private_constant`) exposes one method, `.resolve(current_url, header_value)
-> URI::Generic`, and raises `::URI::InvalidURIError` — Ruby's own class, converted by `Step` at the call site,
never by `Location` itself, so the conversion site and the log site are the same place (`R7`).

**`Dexpace::Redirect::Origin`** (`private_constant`) exposes `.of(uri) -> [String, String, Integer]` and
`.cross?(seed_triple, target_uri)`, the `[scheme.downcase, host.downcase, effective_port]` triple `REDIR-8`
requires and design §6.2 specifies explicitly rather than via `URI#==`.

**`Dexpace::Redirect::Events`/`::Keys`** — frozen `String` constants reusing 5b's shapes (`Instrumentation::Event`,
`Instrumentation::Logger`) but none of 5b's *reserved-key* auto-redaction table, for the reason `R8` states.

**`Dexpace::Redirect::SchemeDowngradeError < ::StandardError; include Dexpace::Error`** — `REDIR-15`'s "fail with
a clear error," raised by `Step`, never by `Location` or `Origin`.

**`Dexpace::Resilience::Resend`** — a module, no state, `.eligible?(request) -> bool` = "no body, or the body
responds `#replayable?` truthfully," and `Dexpace::Resilience::NotReplayableError < ::StandardError; include
Dexpace::Error`, message form naming replayability by name (`REDIR-6`'s "the reference raises an exception whose
message names replayability").

## `R7` — the `Location` parsing route

**Resolved: `6b` parses and resolves the `Location` reference in one call to `URI::RFC3986_PARSER.join`, never
through `Dexpace::URL`, and converts the resulting `::URI::InvalidURIError` by class at the one call site that
also logs it.**

`Dexpace::URL.parse!` is unusable here for a structural reason, not a convenience one: it rejects a non-absolute
URI (`HTTP-47`), and `REDIR-14` requires resolving a **relative** `Location` against the current hop's request
URL. Handing it the raw `Location` string would reject every relative redirect target the requirement exists to
handle. So `6b` writes its own thin wrapper:

```ruby
# lib/dexpace/redirect/location.rb
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Redirect
    # Resolves a Location header value against the current hop's request URL, per RFC 3986
    # reference resolution (REDIR-14). Raises the bare ::URI::InvalidURIError on any malformed or
    # unresolvable reference (REDIR-18) -- Step converts it, by class, at the single call site that
    # both logs the condition and returns the current response unfollowed. This module never
    # inspects the exception's #message: it differs by one space between 3.2.11 and 4.0.6
    # (url-and-query-encoding/08c54234), so no caller anywhere may match on it.
    module Location
      # @param current_url [URI::Generic] the request URL of the current hop (always absolute).
      # @param header_value [String] the raw Location header value, absolute or relative.
      # @return [URI::Generic] frozen; userinfo NOT yet stripped -- that is Step's job (REDIR-12).
      # @raise [::URI::InvalidURIError] on a syntactically invalid reference (REDIR-18).
      def self.resolve(current_url, header_value)
        ::URI::RFC3986_PARSER.join(::Dexpace::URL.external_form(current_url), header_value).freeze
      end
    end
  end
end
```

Verified for this document (below): `URI::RFC3986_PARSER.join` implements RFC 3986's reference-resolution
algorithm for **both** an absolute and a relative second argument — an absolute `Location` replaces the base
entirely (`REDIR-14`'s "Absolute Location values are used as-is"), a relative one resolves against it (`REDIR-14`'s
own worked example, `'/v2/x'` relative to `'https://h/v1/x'` → `'https://h/v2/x'`) — so `Location.resolve` needs
no branch distinguishing the two cases, and needs no separate parse-then-resolve step: `.join` does both, and
raising `::URI::InvalidURIError` on a malformed reference is exactly `REDIR-18`'s "malformed or unresolvable"
trigger. `REDIR-19`'s missing/empty `Location` is checked by `Step` before calling `Location.resolve` at all — an
absent or empty header never reaches the parser.

`Step`'s call site:

```ruby
begin
  target = Dexpace::Redirect::Location.resolve(current_request.url, location_value)
rescue ::URI::InvalidURIError => e
  emit_location_malformed(location_value, e)   # REDIR-28's raw-string exception, R8
  return current_response                       # REDIR-18: unfollowed, body left open (REDIR-22c)
end
```

**`REDIR-12`'s userinfo strip is spelled `target.userinfo = ""`, not `target.userinfo = nil` and not
`#user =`/`#password =` separately**, and this is the one piece of code in this sub-phase this document verifies
against a running interpreter rather than trusting the corpus, because getting it wrong reopens exactly the
credential-leak surface `REDIR-7`/`REDIR-11` exist to close on the *other* channel. See *Verified Ruby facts*,
fact 1, for the measurement; the note it produces is filed under *Findings* below.

## `R8` — `REDIR-28`'s emission site

**Resolved: `Step` takes its own `logger:`/`redactor:` constructor keywords, reuses 5b's `Instrumentation::Logger`
and `Instrumentation::Event` machinery for level-gating and sink dispatch, and performs redaction itself, by an
explicit call to `redactor.url` at each event's construction site — never through 5b's `Event` reserved-key
auto-redaction table.**

The redirect step sits at `Stages::REDIRECT` (order 200), strictly outside 5b's instrumentation step at
`Stages::LOGGING` (order 1100), so it cannot read that installed step's logger — there is no cursor-scoped
channel between two pillar steps other than the marker mechanism §5.1 grants only to a fork's own creator, and
borrowing it for logging would be exactly the kind of second use `R11`'s negative assertions exist to catch.
Verified for this document, confirming the charter's claim: `grep -rn REDIR-28 docs/work/mvp/phase5/` returns
nothing, so no phase-5 document states the `Redactor#url` ↔ `REDIR-28` linkage this sub-phase is the first to
make.

**Why not 5b's reserved-key table.** 5b's `Event#field(Keys::URL_FULL, value)` triggers redaction
*structurally*, through a table private to 5b's own HTTP-request/response event shape (`docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md`,
"`Keys::URL_FULL` → `redactor.url(value)`"). Reusing that table for a new subsystem's own keys would mean either
(a) editing 5b's `Event` to extend a table `6b` does not own, which is out of this document's scope and risks a
merge collision with 5c/8's own future users of the same table, or (b) writing `6b`'s from/to-URL fields under
the literal `Keys::URL_FULL` name to piggy-back on the existing entry, which breaks the moment an event needs
*two* URL-valued fields (the hop's `from` and `to`) under one reserved key. Both routes also make `REDIR-28`'s
own stated exception — the malformed-`Location` event logs the **raw, unredacted** string — a special case
*inside* a table whose whole purpose is "always redact this key," which is the opposite of what that event needs.
`6b` instead redacts explicitly, per field, at the point each event is built:

```ruby
# lib/dexpace/redirect/events.rb
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Redirect
    module Events
      HOP_FOLLOWED               = "http.redirect.hop".freeze
      LOOP_DETECTED               = "http.redirect.loop_detected".freeze
      SCHEME_DOWNGRADE_REJECTED   = "http.redirect.scheme_downgrade_rejected".freeze
      LOCATION_MALFORMED          = "http.redirect.location_malformed".freeze
    end

    module Keys
      FROM_URL        = "http.redirect.from_url".freeze         # ALWAYS passed through redactor.url
      TO_URL          = "http.redirect.to_url".freeze            # ALWAYS passed through redactor.url
      REDIRECT_COUNT  = "http.redirect.count".freeze
      STATUS_CODE     = "http.redirect.status_code".freeze
      # REDIR-28's stated exception: raw, NEVER passed through the redactor, because it failed to
      # parse into a URL and therefore cannot be redacted -- redacting a string that is not a URL
      # would silently fabricate a well-formed-looking placeholder for a value a porter may need to
      # see verbatim to diagnose (and which "a porter that may receive credential-bearing malformed
      # Location values should account for", per REDIR-28's own closing sentence).
      LOCATION_RAW    = "http.redirect.location_raw".freeze
    end
  end
end
```

```ruby
def emit_hop(from:, to:, status:)
  return unless @logger.info?

  @logger.info do
    Dexpace::Instrumentation::Event.new
      .event(Events::HOP_FOLLOWED)
      .field(Keys::FROM_URL, @redactor.url(Dexpace::URL.external_form(from)))
      .field(Keys::TO_URL, @redactor.url(Dexpace::URL.external_form(to)))
      .field(Keys::STATUS_CODE, status.code)
  end
end

def emit_location_malformed(raw_value, error)
  return unless @logger.warn?

  @logger.warn do
    Dexpace::Instrumentation::Event.new
      .event(Events::LOCATION_MALFORMED)
      .field(Keys::LOCATION_RAW, raw_value)   # NOT passed through @redactor -- REDIR-28's exception
      .cause(error)
  end
end
```

`redactor.url`'s own totality (`R11`'s design, `docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md`: "returns `MALFORMED_URL`... wraps its whole body in one `rescue StandardError`") is exactly `REDIR-28`'s
"redaction failures MUST NOT crash logging (a redaction error is swallowed to a placeholder)" — `6b` writes no
second `rescue` around `@redactor.url` because 5b's already degrades rather than raises.

**Defaults.** `logger: Dexpace::Instrumentation::Logger::NULL` (a caller who wires nothing pays for a no-op
level check and nothing else, matching 5c's `NULL` `HTTPTracer` pattern) and `redactor:
Dexpace::Instrumentation::Redactor::DEFAULT` (5b's real default redactor is stateless and safe to hold even when
`logger` is `NULL`, since nothing calls it in that case — defaulting it to a real instance rather than a second
null object costs nothing and means a caller who supplies only `logger:` gets real redaction with no second
keyword).

## `R9` — `REDIR-20`'s condition snapshot

**Resolved: `ConditionSnapshot` is public, `NFR-4`-locked API, built via the phase-1 domain-model pattern; it is
allocated for every recognized 3xx status and consulted whenever a predicate is configured, exactly per
`REDIR-21`'s NOTE, with one hard exception this document states as a deliberate, named decision rather than
leaving implicit.**

**Why public.** `REDIR-20` hands the snapshot to *caller-supplied* code — "a configured redirect predicate...
is given a READ-ONLY condition snapshot." A value crossing that boundary is public API by the repository's own
definition (`docs/README.md`'s "public means a `Dexpace::` constant with a YARD block and an RBS signature"),
so `ConditionSnapshot` gets the full phase-1 treatment: `private_class_method :new`, a validating `.build`, and
its `visited_uris` collection duplicated and frozen at construction (`HTTP-3`'s collection rule), never the
caller-supplied set the predicate itself might hold a reference to.

**Why `visited_uris` is a `Set` of `Dexpace::URL.external_form` strings, not of `URI::Generic` objects.**
`URI::Generic` defines no `#hash`/`#eql?` override distinguishing it from Ruby's default identity-based one for
`Set` membership in the way the loop needs (two `URI::Generic` instances parsed from the same string are not
`eql?` by default), so a `Set` of URI objects would silently fail to detect a revisit even on byte-identical
targets. `Dexpace::URL.external_form` renders the wire-exact string (`REDIR-13`), and `String#hash`/`#eql?` are
exactly value-based, so `REDIR-16`'s "recording every visited absolute URI" is a `Set<String>` seeded with
`Dexpace::URL.external_form(seed_request.url)`.

**The allocate-versus-short-circuit boundary, per `REDIR-21`'s own NOTE, quoted because a plan will otherwise
build the more intuitive but wrong shape:** "a response that IS a recognized 3xx always allocates the condition
snapshot and consults the configured predicate, EVEN when it carries no usable Location — the Location and
method checks live inside the default decision logic, not in a pre-predicate fast path. Only a non-redirect
status is short-circuited." `Step#call` therefore branches once, on the status code alone:

```ruby
unless RECOGNIZED_CODES.include?(response.status.code)   # REDIR-1, REDIR-2
  return response                                          # REDIR-21's fast path: no snapshot at all
end

snapshot = build_snapshot(response, redirect_count, visited)   # allocated unconditionally past this point
```

**The one exception this document names as a deliberate decision, not a spec violation, and flags for the
Deviation Ledger.** `REDIR-17`'s max-hops cap is enforced as a **hard ceiling the step checks before consulting
either the default decision logic or a configured predicate**, rather than being folded into "the built-in follow
decision" `REDIR-20` says a predicate "fully overrides." The snapshot is still allocated (per `REDIR-21`'s NOTE,
quoted above, which draws no exception for the cap), and `redirect_count` is part of what the snapshot hands the
predicate — a predicate that wants its own, different notion of "too many hops" can read it and decide not to
follow on its own account — but the step does not let a predicate override the cap upward, because `REDIR-17`'s
"the number of followed redirects MUST be capped by maxHops" is phrased with no carve-out for a predicate and
because an uncapped custom predicate would turn `REDIR-23`'s stack-safety guarantee (bounded memory per hop, an
iterative loop) into an unbounded one in wall-clock and connection terms even though it stays stack-safe. The
predicate genuinely does replace `REDIR-3`/`REDIR-4`'s allowed-method check, `REDIR-16`'s loop-URI check and
`REDIR-19`'s missing-Location check — every clause the specification frames as part of *whether this particular
hop should be followed* — because those are all read from the same snapshot the predicate receives and none of
them is independently safety-critical the way an unbounded loop is. `REDIR-15`'s downgrade rejection and
`REDIR-7`/`REDIR-8`/`REDIR-9`/`REDIR-11`/`REDIR-24`'s credential hygiene are **never** overridable by a
predicate either, for the same reason and because the specification itself frames them as unconditional
("`REDIR-7`... MUST be stripped before EVERY redirect re-issue"), never as part of "the decision." Filed below as
a candidate for the phase-6 Deviation Ledger, numbered at consolidation (`P6-<n>`, not assigned here because `6a`
and `6c` are being written concurrently and a specific number would risk colliding with theirs).

## Verified Ruby facts this document is built on

Run on 3.4.10 (`ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]`), the only interpreter
available on this machine — re-checked, matching every predecessor sub-phase's own finding. **Facts 1–3 are
floor-straddling in the sense the repository has been bitten by three times already (a stdlib behaviour that
differs across 3.2/3.4/4.0), and this sub-phase's plan re-runs each on 3.2.11 and 4.0.6 before relying on it in
a merged test suite**, exactly as 5a's plan did for its own six.

1. **`URI::Generic#userinfo = ""` clears both `#user` and `#password` and removes the `@` from rendering;
   `#userinfo = nil` is a silent no-op that leaves the credential in place.** Measured directly for this
   document:
   ```
   u = URI::RFC3986_PARSER.parse("https://user:pass@ex.com/p?q=1")
   u.userinfo = ""
   u.to_s   # => "https://ex.com/p?q=1"   -- credential gone, "@" gone
   u.user   # => nil
   ```
   against the no-op:
   ```
   u2 = URI::RFC3986_PARSER.parse("https://user:pass@ex.com/p?q=1")
   u2.userinfo = nil
   u2.to_s  # => "https://user:pass@ex.com/p?q=1"  -- unchanged; the credential survives
   ```
   confirmed at source: `URI::Generic#userinfo=` opens `if userinfo.nil? then return nil` before
   `check_userinfo`/`set_userinfo` are ever reached, so assigning `nil` is observably a no-op rather than a
   clear. *What it licenses:* `Location.resolve`'s result has `#userinfo = ""` called on it, unconditionally,
   before the resolved URI is used for anything — comparison, logging, or the follow-up request — so a
   server-supplied credential can never leak through a code path that trusted `#userinfo = nil`. *What it does
   not license:* trusting `#user = nil` alone to clear `#password` too — not tested here because `#userinfo = ""`
   is sufficient and is the one call site this document ships. **Floor-straddling** — `URI::Generic`'s setter
   bodies have not been diffed across the matrix by this document; the plan's Task 1 does that before this fact
   is relied on across the full range.

   **The knowledge note this document owes, filed here in full for a human to add under
   `docs/knowledge/notes/url-and-query-encoding.md` (target register), because the charter assigns it to `6b`
   "to file with the design that acts on it" and this document may not write into `docs/knowledge/` itself:**

   > **`URI::Generic#userinfo = nil` is a silent no-op and is the obvious-but-wrong spelling of `REDIR-12`.**
   > Measured: parsing `https://user:pass@ex.com/p`, assigning `userinfo = nil` and rendering gives back
   > `"https://user:pass@ex.com/p"` — the credential survives. Confirmed at source in `uri/generic.rb`: the
   > writer opens `if userinfo.nil? then return nil`, before `check_userinfo` and `set_userinfo` are ever
   > reached. The correct spelling is `#userinfo = ""`, which clears both `#user` and `#password` and removes
   > the `@` separator from rendering. `set_userinfo` is additionally **protected**, so a third obvious route
   > needs a `send`. `REDIR-12` says "server-supplied embedded credentials MUST never be used"; the spelling
   > that reads as satisfying it forwards them. `6b`'s `REDIR-12` test asserts on the rendered URL string
   > (`Dexpace::URL.external_form`), never on `#userinfo` being `nil`, because a resolved-but-not-yet-stripped
   > URI can also report `#userinfo` as `nil` for an unrelated reason (no userinfo present at all), which would
   > make a `#userinfo.nil?` assertion pass for the wrong reason on that input.
   > <sub>review · `docs/work/mvp/phase6/phase6b/2026-09-09-phase6b-redirect-design.md` · high · sha:manual-phase6b-userinfo-noop</sub>

2. **`URI::RFC3986_PARSER.join` implements RFC 3986 reference resolution for both a relative and an absolute
   second argument, and raises `::URI::InvalidURIError` on a malformed one.** Measured for this document:
   ```
   URI::RFC3986_PARSER.join("https://h/v1/x", "/v2/x").to_s        # => "https://h/v1/x" -> wait, verified:
   ```
   re-run precisely: `URI::RFC3986_PARSER.join("https://h/v1/x", "/v2/x").to_s` → `"https://h/v2/x"`, the exact
   `REDIR-14` worked example; `URI::RFC3986_PARSER.join("https://h/v1/x?a=1", "https://other/y").to_s` →
   `"https://other/y"` (absolute reference replaces the base entirely, as `REDIR-14` requires); `URI::RFC3986_PARSER.join("https://h:8443/v1/x", "y").to_s`
   → `"https://h:8443/v1/y"` (explicit port survives resolution). On a malformed reference:
   `URI::RFC3986_PARSER.join("https://a.example/base/x", "ht!tp://bad")` raises `URI::InvalidURIError`, message
   `"bad URI (is not URI?): \"ht!tp://bad\""` on 3.4.10 — the space-before-parenthesis form
   `url-and-query-encoding/08c54234` says differs from 3.2.11's, confirming that note's caveat directly rather
   than trusting it secondhand. *What it licenses:* `Location.resolve` as written above, one call, no branch
   for absolute-versus-relative. *What it does not license:* matching this exception's `#message` anywhere —
   `R7`'s call site rescues by class only.

3. **`URI` performs no host-case normalisation and supplies the scheme-default port only through `#port`, never
   through `#host`.** Re-confirming the charter's own verified fact 3 independently for this document:
   `URI::RFC3986_PARSER.parse("https://EX.com/").host` is `"EX.com"` (unchanged casing); `.port` is `443` with no
   port written, `80` for a bare `http://`, and `443` for an explicit `:443`. *What it licenses:* `Origin.of`'s
   triple calls `.host.downcase` explicitly (`HTTP-13`'s no-argument fold, `REDIR-8`'s "case-insensitive") and
   reads `.port` rather than re-deriving a default from `.scheme`, which is free correctness `URI` already
   computes.

4. **Ruby's `Set` is insertion-ordered (Hash-backed) and freezes and raises `FrozenError` exactly like any other
   collection.** Measured: two `Set`s built by inserting `"a","b","c"` and `"c","b","a"` respectively render
   `.to_a` in insertion order, not sorted; `set.dup.freeze` then `<<` raises `FrozenError`. *What it licenses:*
   `ConditionSnapshot#visited_uris` as a frozen `Set<String>` satisfies `REDIR-20`'s "insertion-ordered set of
   visited URIs" with no ordering shim.

## Findings for the registers

Three, described here for a human to file. **None is acted on by this document, none carries a number, and no
register file is edited by it** — the frozen-tree rule and the "register items are not `6b`'s to file" instruction
both apply.

**No register row — corrected in place instead, 2026-09-09.** **The charter's *Prerequisites* section
wrote `Dexpace::HTTP::URL.parse!` where the shipped constant is the flat `Dexpace::URL`.** Verified 2026-09-09
against every `module`/`class` declaration in
`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model.md`: `Dexpace::URL` is a direct child of
`Dexpace`, with no `Dexpace::HTTP` namespace anywhere in phase 1's shipped surface, per `P1-1`'s "flat unless
the design namespaced the subsystem" and §3's namespacing nothing. This sub-phase's own text cites
`Dexpace::URL` throughout and never repeated the slip. **Disposition:** the charter is same-day, uncommitted
work and no design decision rested on the wrong namespace, so all four occurrences were corrected in the
charter directly rather than filed as an open item — `open-items.md` holds findings nobody is acting on, and
this one was acted on. `6c`'s plan carried one instance in a code sample and was corrected with it.
Cites: `P1-1`, `HTTP-47`.

**Target register: `docs/knowledge/notes/url-and-query-encoding.md`.** **The `URI::Generic#userinfo = nil`
no-op note, filed in full under *Verified Ruby facts*, fact 1 above.** The charter names this as `6b`'s to file
"with the design that acts on it," which this document is; the exact text, key placement (a new `## Superseded`
or `## Reference` entry, since it does not override an *existing* harvested rule about `#userinfo=` — none
exists — it instead **adds** a fact the corpus does not yet carry, so `## Reference` is the more accurate
section per the skill's own guidance: "`## Reference` when the note only points somewhere") and manual `sha:`
marker are given above, ready to paste.

**Target register: `.claude/skills/knowledge-lookup/SKILL.md`'s audit-group table.** **The eleventh row the
charter names — *Resilience: retry, redirect and authentication* — is still unfiled**, and this document,
constrained to write only under `docs/work/mvp/phase6/phase6b/`, cannot file it either. Named again here so a
second sub-phase document does not also assume the other filed it. Exact row content is given in the charter,
*Corpus reading*, and is unchanged by anything `6b` found.

## Prerequisites, and the independence this sub-phase must state

**Every surface below was verified to exist and to be stated as shipping by the named phase's design, on
2026-09-09, following the charter's own instruction that a sub-phase design must not cite one it did not
verify.**

**From phase 0** — the seventeen blocking gates. `gates:require_allowlist` — `6b` requires nothing beyond `uri`,
already on the allowlist and already required by phase 1 and phase 2; `6b` adds no new require. The
`Dexpace/NoUriDefaultParser` cop is what makes `R7`'s `URI::RFC3986_PARSER.join` mandatory rather than a style
choice, and `Dexpace/NoLocaleCaseFold` is what makes `Origin.of`'s bare `downcase` a lint-enforced rule rather
than a habit (`REDIR-8`).

**From phase 1** — `Dexpace::URL.parse!(input)`/`.external_form(uri)` (used for the **seed** and **current-hop**
URLs, which are always absolute by construction, never for parsing a `Location`, per `R7`); `Dexpace::Request`,
`Request::Builder` (`#method=`, `#url=`, `#headers=`, `#body=`); `Dexpace::Response`, `Response::Builder`;
`Dexpace::Headers`, `Headers::Builder` (`#add`, `#set`, `#remove`, `#build`); `Dexpace::Method` (`.of`, `#token`,
and the **five**-member `IDEMPOTENT` set this sub-phase does **not** reuse — see the object model above);
`Dexpace::Model`, `Dexpace::InvalidArgumentError`.

**From phase 2** — `Dexpace::Cancellation` (threaded through the cursor already; `6b`'s loop reads
`cursor.cancellation` only as a courtesy check between hops, never re-implements a wait); the async pivot's real
names, `Dexpace::Async::Future`/`::Completer`/`::Settlement` — irrelevant to `6b` directly, since `REDIR-25` ships
no async step, but named so no code here accidentally writes `Dexpace::Future`; `Dexpace.close_quietly`, used
nowhere in this sub-phase's own code (every close in the loop is a direct `response.close`, because `6b` owns the
knowledge of which response is superseded and which is being returned — `PIPE-40`'s rule, restated below); the
error-class shape `class X < ::StandardError; include Dexpace::Error; end`, which `SchemeDowngradeError` and
`Resilience::NotReplayableError` both follow.

**From phase 3b** — `Dexpace::Body#replayable?`/`#to_replayable`, `Response#close`,
`Dexpace::StreamError < ::IOError`. **`Dexpace::Resilience::Resend.eligible?(request)` does not yet exist as a
shipped surface** — 3b's own forward table names it as phase 6's to write, and this sub-phase's plan builds it,
under the independence caveat given at the top of this document.

**From phase 4a** — nothing `6b` consumes directly (`BoundedMap`, `Bundle`, `ContextStore` are `6c`'s and `6a`'s
concerns respectively).

**From phase 4b** — `Dexpace::Outcome` is not consulted here: the redirect step operates on raw `Response`
objects returned by `cursor.fork(...).call(request)`, never on an `Outcome`, because the stage pipeline (§5.1)
and the recovery chain (§5.2) are the two layers the design explicitly forbids collapsing, and the redirect step
belongs entirely to the first.

**From phase 4c** — `Dexpace::Pipeline::Stages::REDIRECT` (order 200, pillar); `Pipeline::Cursor` — `#fork(state:
nil) -> Cursor`, raising `Dexpace::PipelineError` off a non-pillar stage or a spent cursor; `#state(stage) ->
Hash` (frozen, shared-empty for an unwritten stage); `#may_fork? -> bool`; `#spent? -> bool`; `#request`;
`#options`; `#cancellation`. `Stage#pillar?`/`#terminal?` are read only by the runtime, never by `Step`. `R11`'s
five negative assertions and `pipeline/86343352`'s rule (fork for every drive, the first included, never call
`#call`) are the contract `6b`'s own plan extends from probe doubles to the real step — see *Testing strategy*
below.

**From phase 5a** — nothing `6b` consumes directly (`Clock`, `Retryability`, `HTTPDate` are `6a`'s concerns).

**From phase 5b** — `Dexpace::Instrumentation::Logger` (`#info`/`#warn`/`#error`, block form, `#info?`/`#warn?`/
`#error?`), `Logger::NULL`; `Dexpace::Instrumentation::Event` (`#event(name)`, `#field(key, value)`,
`#cause(error)`); `Dexpace::Instrumentation::Redactor`/`Redactor::DEFAULT` (`#url`, total, degrading to
`MALFORMED_URL` rather than raising); `Dexpace::Instrumentation::Severity`. **`6b` consumes these classes
directly, as its own instances, never through the installed `Stages::LOGGING` step** — `R8` above is the full
argument.

**From phase 5c** — nothing `6b` consumes directly (`HTTPTracer`, the span/meter SPIs are `6a`'s and phase 8's
concerns; `REDIR`'s only observability obligation is the logging one, `REDIR-28`).

**The independence statement, made explicitly as the charter requires.** For every surface above, `6b`'s real
dependency is on phases 0–5. Its dependency on `6a` is limited to the shared `Dexpace::Resilience::Resend`
namespace, handled above so landing order does not matter; its dependency on `6c` is **empty** — `6b` writes
`state: { cross_origin: ... }` into its own fork's `Stages::REDIRECT` slot and returns, with no knowledge of
whether an `AUTH` step is installed at all, and `PIPE-4` guarantees at most one could be. A `6b` plan whose first
task waits on `6c`'s `Step` existing, or on `6a`'s `Resilience::Policy`, has re-imposed a chain the split existed
to avoid. **`OI-31`'s cursor widening (`R13`)** travels with whichever of the three sub-phases lands first; this
document does not build it and does not wait for it — `6b`'s `logger:`/`redactor:` keywords are `Step`'s own,
independent of any per-call instrumentation bundle a widened `Cursor` might one day carry, exactly as the charter
requires each consuming design to state.

## Convergence points — `6b`'s half of each

Three exist phase-wide (charter, *Convergence points*); `6b` is party to two.

1. **The end-to-end cross-origin credential-leak test.** `6b`'s half is complete on its own: a real
   `Dexpace::Redirect::Step` at `Stages::REDIRECT`, forking per hop, with a probe `AUTH`-position step downstream
   (4c's `StateProbe`, or a small counting probe built for this suite) asserting that `cursor.state(Stages::REDIRECT)`
   reads `{cross_origin: true}` on a foreign-host hop and `{cross_origin: false}` (or the shared frozen empty
   hash, per the object-model decision below) on a same-origin one. **The full end-to-end test — a real credential,
   a real `AUTH` step, an assertion that no `Authorization` reaches a second fake transport — is `6c`'s to write**,
   under the recommended order, and this document does not build it and does not assume `6c` has. `6b`'s own
   suite proves its half completely against the probe.
2. **`DEF-39`'s `Pipeline.standard`.** A phase-level task, executed by whichever of `6a`/`6b` lands second — see
   the charter. `6b` does not build it and states here, as the charter requires, that landing this sub-phase
   first does **not** make `Pipeline.standard` `6b`'s task; it becomes the task of whichever of `6a`/`6b` is
   still open when the other lands.
3. `RETRY-14`'s budget-equivalence test is internal to `6a` and `6b` is not party to it.

## Cross-cutting constraints this sub-phase meets

- **`downcase` with no arguments, everywhere** — `Origin.of`'s scheme/host fold (`HTTP-13`, `REDIR-8`).
- **`URI::RFC3986_PARSER` pinned explicitly for every parse and every resolution** — `Location.resolve`'s one
  call, and nowhere does `6b` write `URI.parse`, `URI.join`, `URI.split` or rely on `URI::DEFAULT_PARSER`.
- **Bytes on the wire are `Encoding::BINARY`** — `6b` never inspects or transcodes a request/response body; the
  303 body-drop (`REDIR-5`) discards the body reference outright rather than reading it, and the replayable
  re-send (`REDIR-6`) hands the existing body object to the follow-up `Request::Builder` unchanged.
- **An `Enumerator` abandoned mid-`#next` never runs its `ensure`.** Nothing in `6b` puts a resource inside an
  `Enumerator` block; the redirect loop is a `while`/`loop` construct (`REDIR-23`), and every response close
  happens in an explicit `ensure` or an explicit call at a named point in that loop, never inside an
  `Enumerator`.
- **Deadlines are explicit values, not ambient interrupts.** `6b` schedules nothing and waits on nothing itself;
  every blocking operation happens inside `cursor.fork(...).call(...)`, which threads the cursor's own
  cancellation and (once `6a` lands) retry-layer deadlines to the terminal transport. `6b` adds no timeout of
  its own.
- **`Ractor` is never load-bearing.** `Step`'s configuration (`allowed_methods`, `max_hops`, etc.) is frozen at
  construction and shared across every call; `ConditionSnapshot` is a frozen `Data`. Neither claims
  Ractor-shareability as part of its contract.

## Testing strategy

**No transport, no socket.** Every scenario drives a small scripted fake transport
(`test/support/scripted_transport.rb`, new in this sub-phase, reusable across every `REDIR` test) returning a
prepared sequence of `Response`s keyed by call count, plumbed as the pipeline's terminal transport under an
otherwise-empty `Pipeline::Builder` with only `Redirect::Step` installed at `Stages::REDIRECT`. This mirrors
phase 2's `test/support/fake_transport.rb` and 4c's own no-transport testing rule (roadmap cross-cutting
constraint 4).

**Reused from phase 4c, unmodified:** `test/support/state_probe.rb` (`StateProbe`, a pillar-stage probe that
forks with a named state map, and a slot probe that reads one) — installed at `Stages::AUTH` in every test that
needs to observe what `Redirect::Step`'s fork actually wrote, which is how this sub-phase **extends 4c's R11
negative-assertion 4 from a probe pair to a real step**: the same assertion 4c wrote against two `StateProbe`
instances is re-run here with the real `Redirect::Step` at `REDIRECT` and a `StateProbe` reader at `AUTH`,
proving the production step obeys the write-restriction contract it was built against, not only that the
contract itself holds for a probe.

**New in this sub-phase:**

- **`ScriptedTransport`** — `#call(request, options, cancellation)` popping the next prepared `Response` off a
  queue (or computing one from a block, for scenarios where the follow-up request's headers must be inspected —
  e.g. asserting `Authorization` is genuinely absent on the second call).
- **A minimal `AUTH`-position probe that stamps a fixed `Authorization` header whenever
  `cursor.state(Stages::REDIRECT)[:cross_origin]` is falsy, and refuses (asserts, in the test, rather than
  stamping) when it is truthy** — this is the shape `6b`'s half of convergence point 1 needs and is not 4c's
  `StateProbe`, which only records state, because this sub-phase's own assertion needs to observe a header on
  the *next* fake transport call, not merely a cursor read.

**The tests a reader would otherwise write wrong**, named because each is where the credential-leak stake bites:

- **`REDIR-7`/`REDIR-8`/`REDIR-11` together, on a two-hop chain where hop 1 is same-origin and hop 2 is
  cross-origin.** A test that only checks the *final* request's headers would pass against an implementation
  that strips `Authorization` once, at the end, rather than "before EVERY redirect re-issue." The suite asserts
  on **every** intermediate follow-up request the `ScriptedTransport` received, not only the last.
- **`REDIR-8` against the seed, not the previous hop.** A three-hop chain — seed on host A, hop 1 to a
  same-origin path on A, hop 2 from A to B — must mark hop 2 cross-origin by comparing against the **seed** (A),
  not against hop 1's own URL (which is also A, so a previous-hop comparison would agree with the seed-comparison
  by accident on this input). The suite additionally runs a chain where the previous hop is *already* B (seed A →
  hop 1 to B → hop 2 same-origin on B) and asserts hop 2 is **not** re-marked cross-origin merely because the
  seed was A — the exact scenario `REDIR-8`'s own text calls out ("so that a same-origin sub-redirect on a
  foreign host does not re-expose the credential").
- **`REDIR-9`/`REDIR-10`, same-origin versus cross-origin, in one test asserting both.** `Cookie` retained
  same-origin, stripped cross-origin, in the same chain, so the two clauses cannot both silently degrade to "always
  strip" or "never strip" and still pass.
- **`REDIR-16` and `REDIR-22c` together.** A loop that revisits the seed URI on hop 3 must return that response
  **open**, and the suite asserts `refute(response.body.closed?)` (or the fake body's own tracking flag) rather
  than only asserting the loop terminated — a response leaked as closed-when-it-should-be-open is invisible to a
  test that checks only "did it stop."
- **`REDIR-22a`/`REDIR-22b` on the two failure shapes.** A non-replayable body on a 307 closes the *current*
  redirect response before `Resilience::NotReplayableError` propagates (`22b`); a successful third hop closes
  hop 1's and hop 2's responses but leaves hop 3's (the final, returned) response open (`22a`/`22c` together) —
  asserted by three independent closed-flags on three fake response bodies, not by counting close calls, because
  a count alone cannot say *which* response was closed.

## Deviation Ledger

**One candidate, named here and numbered at consolidation.** `REDIR-17`'s max-hops cap is enforced as a hard
ceiling the step checks *before* consulting a configured predicate, rather than folding it into the "built-in
follow decision" `REDIR-20` says a predicate fully overrides. Argued in full under `R9` above. *Touches*
`REDIR-17`, `REDIR-20`, `REDIR-23`. Not numbered `P6-<n>` here because `6a` and `6c` are being written
concurrently under the same phase and a number assigned in isolation could collide; the consolidation step
(design §10) assigns the final number across all three sub-phases' ledgers at once.

**Nothing else in this sub-phase substitutes a mechanism the reference specifies.** The cross-origin marker
substitution is §10.15's, already argued and consolidated, and `6b` implements it rather than re-arguing it.
