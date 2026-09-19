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

- **The `Cursor` context-bundle widening (`R13`)** — assigned to `6a`. `6b`'s emission task (`R8`) takes its own
  `logger:`/`redactor:` constructor keywords regardless of whether the widening exists, so `6b` neither blocks
  on it nor builds it. See *Prerequisites* below for the concrete consequence if `6b` lands first.
- **The `Dexpace::Resilience` re-sendability namespace, and the one method in it that is *not* `6b`'s to
  call.** 3b's forward table names `Dexpace::Resilience::Resend.eligible?(request)` as phase 6's, and
  `RETRY-5`, `REDIR-6` and `AUTH-31` are its three cited call sites (`docs/sdk-design-ruby/05-pipeline-architecture.md`
  §5.2). **`6a`'s `R5` has since settled `eligible?` with a second clause `6b` must not inherit**: `request.body.nil?
  ? request.method.idempotent? : request.body.replayable?` (`docs/work/mvp/phase6/phase6a/2026-09-09-phase6a-retry-design.md`
  §`R5`), because `RETRY-7` makes a body-less **non-idempotent** request un-re-sendable. `REDIR-6` asks a
  strictly narrower question — "is the body present and not replayable?" — and says nothing about idempotency;
  method eligibility for a redirect is `REDIR-3`/`REDIR-4`'s configured allowed-method set and is decided
  elsewhere in this step. Calling `eligible?` here would reject a body-less `POST` 307 under a widened
  `allowed_methods:` that `REDIR-3`/`REDIR-4` explicitly permit. **So the two are different predicates and get
  different names.** `6b` writes `Dexpace::Resilience::Resend.replayable_body?(request)` —
  `request.body.nil? || request.body.replayable?` — plus `Dexpace::Resilience::NotReplayableError`, both under
  the `Dexpace::Resilience` namespace 3b already named and never under `Dexpace::Redirect`; `6a` writes
  `eligible?` in the same module. Neither sub-phase touches the other's method, neither no-ops on finding the
  file present (the file is shared; the methods are not), and `6c` discharges `AUTH-31` with a direct
  `request.body&.replayable?` and consumes neither (`docs/work/mvp/phase6/phase6c/2026-09-09-phase6c-authentication-design.md`).
  If `6a` lands first, `6b`'s Task 2 still runs: it adds its own method and the error class to the existing
  file.

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
  `#to_replayable`, `Response#close`, and the `Dexpace::Resilience` re-sendability namespace 3b
  forward-named (`6b` adds `.replayable_body?` to it; `.eligible?` is `6a`'s — see *Independence*).
  `docs/work/mvp/phase4/phase4b/2026-09-08-phase4b-recovery-primitives-design.md` for the error-class shape's
  precedent and `Dexpace.close_quietly`.
  `docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md` for
  `Dexpace::Instrumentation::Logger`/`Logger::NULL`, `Event`, `Keys`, `Events`, `Redactor`/`Redactor::DEFAULT`,
  `Severity` — the machinery `R8` reuses.
- `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-design.md` and `.../phase5b` as the worked
  precedent for this document's shape, depth and section naming.
- `docs/deviations.md` and `docs/first-release.md` (read, not
  edited — findings are described below, each with the owner that carries it); the two deferrals that reach this sub-phase — `REDIR-27`'s
  v1 decline (`docs/first-release.md` § What v1 ships without) and phase 4c's postponed `standard` constructors (Task 13a).
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
under *Findings, and who owns them now* so it is not lost twice.

**No note is filed by this document.** One candidate exists — `URI::Generic#userinfo = nil` being a silent
no-op for `REDIR-12` — and the charter already assigns it to `6b` "to file with the design that acts on it." It
is recorded in full under *Verified Ruby facts* below, with the exact note text a human should file, per the
instruction that note edits are described here, not made here.

## Scope: the 28 IDs, with dispositions

**28 IDs: 23 MUST, 4 SHOULD (`REDIR-10`, `REDIR-21`, `REDIR-23`, `REDIR-28`), 1 MAY (`REDIR-27`)**, matching the
charter's reconciliation against appendix C exactly.

| Disposition | IDs | Count |
|---|---|---|
| Implemented | `REDIR-1`–`REDIR-26`, `REDIR-28` | 27 |
| ⏳ declined for v1, no named trigger — the configurable target-header MAY (`docs/first-release.md` § What v1 ships without › SHOULD- and MAY-level, the `REDIR-27` entry) | `REDIR-27` | 1 |
| **Total** | | **28** |

Three rows carry a clause the checklist must state rather than tick, named by the charter and confirmed here:

- **`REDIR-11`** — clause (a) satisfied **structurally** (a `Location` value cannot reach cursor state at all;
  there is no code path from the wire to `#fork`'s `state:` argument); clause (b) is implemented by `6c`, not
  here — `6b`'s obligation is to write the marker `true` only on an actually-cross-origin hop and `false`
  (or omit it — see the object model below) otherwise, never the reverse; clause (c) is satisfied *a fortiori*,
  because nothing is ever added to the request, so nothing needs removing before dispatch.
- **`REDIR-25`** — satisfied by shipping no async redirect step at all. `Dexpace::AsyncPipeline` gains no
  `Redirect::AsyncStep`, and `Stages::REDIRECT` stays installable-but-unused on the async path exactly as 4c
  left it (`PIPE-28`). The substantive clause stays vacuous until the async standard pipeline phase 4c postponed exists
  (`AsyncPipeline.standard`, Task 13a), which is a phase-level task this sub-phase does not own as a sub-phase — see
  *Prerequisites*.
- **`REDIR-8`** — the triple is `[scheme.downcase, host.downcase, effective_port]`, compared against the
  **seed** request's URL, never the previous hop's, and never `URI#==`. Verified fact 3 below is why the
  `downcase` calls are not optional and why the port half is free.

**Four clauses inside otherwise unremarkable rows that a plan will implement narrower than the text**, named
here because each is the half of a requirement an implementation reads past:

- **`REDIR-3`/`REDIR-4` say "the ORIGINAL request method", not the current hop's.** The two are the same
  through any method-preserving chain, and differ after a `follow303` GET rebuild: `POST` → 303 → GET → 301
  continues under `GET`, which the default `{GET, HEAD}` set admits, while the seed method `POST` does not.
  `Step` therefore captures the seed method beside the seed origin triple and tests *that*, and the suite
  carries the `POST`→303→301 chain as its witness.
- **`REDIR-5` says "every `Content-*` request header (case-insensitively)"**, and its three examples are
  examples — `e.g.` in both appendix C and chapter 10. The 303 rebuild strips by **prefix**
  (`name.downcase.start_with?("content-")`), never by a fixed list, or `Content-MD5`, `Content-Language`,
  `Content-Range` and `Content-Disposition` survive a body that does not.
- **`REDIR-18` lists three triggers, and the third is "an unsupported/unknown scheme".** RFC 3986 resolution
  raises on neither an `ftp:` nor a `mailto:` target; `R7`'s `Location::SUPPORTED_SCHEMES` screen is what makes
  that clause implemented rather than assumed.
- **`REDIR-22a` is an ordering clause.** See *Testing strategy*: the prior response is closed **before** the
  next fork is issued, not after it returns.

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
| `lib/dexpace/resilience/resend.rb` | `Dexpace::Resilience::Resend.replayable_body?`, `::NotReplayableError` | public — the module is shared with `6a`'s `.eligible?`; the method is not, see *Independence* |

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

**`Dexpace::Resilience::Resend.replayable_body?`** — a module function, no state, `.replayable_body?(request)
-> bool` = "no body, or the body responds `#replayable?` truthfully," and
`Dexpace::Resilience::NotReplayableError < ::StandardError; include Dexpace::Error`, message form naming
replayability by name (`REDIR-6`'s "the reference raises an exception whose message names replayability").
**It is not `6a`'s `.eligible?`**, which folds in `RETRY-7`'s idempotency clause — see *Independence*.

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
      # REDIR-18's third trigger, "an unsupported/unknown scheme". RFC 3986 resolution does NOT
      # raise on one -- measured on 3.4.10: join("https://h/x", "mailto:a@b") returns a URI::MailTo
      # whose #host is nil, and join("https://h/x", "ftp://o/z") a perfectly valid URI::FTP -- so
      # the scheme is screened explicitly here rather than discovered downstream as a NoMethodError
      # on nil.host inside Origin.of or as a "cannot set user with opaque" out of #userinfo=.
      SUPPORTED_SCHEMES = ::Set["http", "https"].freeze

      # @param current_url [URI::Generic] the request URL of the current hop (always absolute).
      # @param header_value [String] the raw Location header value, absolute or relative.
      # @return [URI::Generic] NOT frozen and NOT yet userinfo-stripped -- Step strips (REDIR-12)
      #   and freezes once afterwards. Freezing here would make that strip raise FrozenError.
      # @raise [::URI::InvalidURIError] on a syntactically invalid reference, or on a resolved
      #   target whose scheme this client cannot dispatch (REDIR-18, both triggers, one rescue).
      def self.resolve(current_url, header_value)
        target = ::URI::RFC3986_PARSER.join(::Dexpace::URL.external_form(current_url), header_value)
        unless target.scheme && SUPPORTED_SCHEMES.include?(target.scheme.downcase)
          raise ::URI::InvalidURIError, "unsupported redirect scheme"
        end

        target
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
trigger. **What `.join` does *not* do is reject an unsupported scheme**, which is `REDIR-18`'s third listed
trigger ("syntactically invalid URI, illegal characters, **or an unsupported/unknown scheme**"), so the scheme
screen above is not belt-and-braces: without it a `Location: mailto:…` reaches `Origin.of` and raises
`NoMethodError` on a nil host, and a `Location: ftp://…` is dispatched to an HTTP transport. It raises the same
class as a malformed reference so one rescue covers both of `REDIR-18`'s shapes, and because `REDIR-18` forbids
throwing either way, the distinction has no observable consequence at the call site.
`REDIR-19`'s missing/empty `Location` is checked by `Step` before calling `Location.resolve` at all — an
absent or empty header never reaches the parser.

`Step`'s call site:

```ruby
# One call site, reached on BOTH decision routes -- the built-in one and a configured predicate's
# `true` (REDIR-20 overrides the FOLLOW decision, not REDIR-18's and REDIR-19's MUST-not-throw).
# The result is stripped (REDIR-12) and frozen here, once, and the same object is what the visited
# check (REDIR-16) and the follow-up builder both see -- see R9.
def resolve_target(current_request, response)
  location_value = response.headers["Location"]&.first
  return nil if location_value.nil? || location_value.empty?   # REDIR-19

  target = Dexpace::Redirect::Location.resolve(current_request.url, location_value)
  target.userinfo = ""                          # REDIR-12; "" clears, nil is a silent no-op
  target.freeze
rescue ::URI::InvalidURIError => e
  emit_location_malformed(location_value, e)    # REDIR-28's raw-string exception, R8
  nil                                            # REDIR-18: unfollowed, body left open (REDIR-22c)
end
```

A `nil` return from `resolve_target` is `Step`'s single "return the current response unfollowed" signal, and
it covers `REDIR-19`'s missing/empty header, `REDIR-18`'s malformed reference and `REDIR-18`'s unsupported
scheme alike. **It is evaluated before either decision route**, so a configured predicate that answers `true`
cannot drive the step into a follow-up it has no target for — `REDIR-20` overrides the built-in *follow
decision*, and `REDIR-18`/`REDIR-19` are MUSTs about not throwing that no predicate may waive.

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

**5b's public surface, quoted rather than assumed, because the first draft of this section invented one.**
`P5-17` fixes `Logger`'s public methods at `.build`, `#event`, `#enabled?`, `#context` and `#sink`
(`docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction.md`, Task "…`Logger` class,
`Logger::NULL` singleton") — there is **no** `#info`, `#warn`, `#info?` or `#warn?` on it, and `Event` is never
constructed by a caller: `Logger#event(severity)` makes the enabled decision **once** and returns either a live
`Event` or the shared frozen `Event::INERT`, and the event is finished with `#event(name)`, `#field(key, value)`,
`#cause(error)` and `#emit`. So every emitter below is one chain, the enablement guard is `#event`'s own return
value rather than a predicate call, and a test reads what was emitted off a `Dexpace::RecordingSink`'s
`#entries`, each carrying a `#payload` hash keyed by `Instrumentation::Keys`.

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
      HOP_FOLLOWED                = "http.redirect.hop".freeze
      LOOP_DETECTED               = "http.redirect.loop_detected".freeze
      # REDIR-15 has TWO observable outcomes and they are not the same event. The rejection is
      # already observable as a raised SchemeDowngradeError; the OPT-IN is observable only here,
      # and REDIR-15's "MUST surface it observably (e.g. a warning log)" binds on that branch.
      # Emitting the "rejected" name for a downgrade that was permitted would make the log say the
      # opposite of what happened.
      SCHEME_DOWNGRADE_REJECTED   = "http.redirect.scheme_downgrade_rejected".freeze
      SCHEME_DOWNGRADE_PERMITTED  = "http.redirect.scheme_downgrade_permitted".freeze
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
def emit_hop(from:, to:, status:, redirect_count:)
  # Logger#event makes the enabled decision once and hands back Event::INERT when the sink is not
  # listening; INERT's #field/#event/#cause are no-ops returning self and its #emit returns nil, so
  # there is no predicate to call and nothing to guard.
  @logger.event(Dexpace::Instrumentation::Severity::INFO)
         .event(Events::HOP_FOLLOWED)
         .field(Keys::FROM_URL, redacted_url(from))
         .field(Keys::TO_URL, redacted_url(to))
         .field(Keys::STATUS_CODE, status.code)
         .field(Keys::REDIRECT_COUNT, redirect_count)
         .emit
end

def emit_location_malformed(raw_value, error)
  @logger.event(Dexpace::Instrumentation::Severity::WARNING)
         .event(Events::LOCATION_MALFORMED)
         .field(Keys::LOCATION_RAW, raw_value)  # NOT passed through @redactor -- REDIR-28's exception
         .cause(error)
         .emit
end

def emit_scheme_downgrade_permitted(from, to)
  @logger.event(Dexpace::Instrumentation::Severity::WARNING)
         .event(Events::SCHEME_DOWNGRADE_PERMITTED)
         .field(Keys::FROM_URL, redacted_url(from))
         .field(Keys::TO_URL, redacted_url(to))
         .emit
end

# REDIR-28's "redaction failures MUST NOT crash logging" binds on ANY configured redactor, and
# `redactor:` is a constructor keyword, so a caller-supplied one is not guaranteed total the way
# Redactor::DEFAULT is. One rescue, one placeholder, one place.
def redacted_url(uri)
  @redactor.url(Dexpace::URL.external_form(uri))
rescue ::StandardError
  Dexpace::Instrumentation::Redactor::MALFORMED_URL
end
```

`redactor.url`'s own totality (`R11`'s design, `docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md`: "returns `MALFORMED_URL`... wraps its whole body in one `rescue StandardError`") is exactly `REDIR-28`'s
"redaction failures MUST NOT crash logging (a redaction error is swallowed to a placeholder)" — `6b` writes no
second `rescue` around `@redactor.url` because 5b's already degrades rather than raises.

**Defaults.** `logger: Dexpace::Instrumentation::Logger::NULL` (a caller who wires nothing gets `Event::INERT`
from every `#event` call and pays for nothing else, matching 5c's `NULL` `HTTPTracer` pattern; a caller who
wants records passes `Dexpace::Instrumentation::Logger.build(sink: …)`, which is 5b's only public constructor)
and `redactor: Dexpace::Instrumentation::Redactor::DEFAULT` (5b's real default redactor is stateless and safe to
hold even when `logger` is `NULL`, since nothing calls it in that case — defaulting it to a real instance rather
than a second null object costs nothing and means a caller who supplies only `logger:` gets real redaction with
no second keyword).

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
target   = resolve_target(current_request, response)           # REDIR-12, REDIR-18, REDIR-19; R7
return response if target.nil?                                 # unfollowed, open (REDIR-22c)

decision = @predicate ? @predicate.call(snapshot) : default_follow?(...)  # REDIR-20/REDIR-21
return response unless decision
return response if redirect_count >= @max_hops                 # REDIR-17's ceiling, OVER the answer
```

**The one exception this document names as a deliberate decision, not a spec violation, and flags for the
Deviation Ledger.** `REDIR-17`'s max-hops cap is enforced as a **hard ceiling applied *over* the follow
decision, never in place of it**: the snapshot is allocated and the configured predicate is consulted exactly as
`REDIR-21`'s NOTE requires, and only then — on a `true` answer — does the cap veto the follow. Ordering the two
the other way round, with `return response if redirect_count >= @max_hops` placed above the predicate call,
would allocate a snapshot and then discard it unread and would make `REDIR-21`'s "always … consults the
configured predicate" false at exactly the hop where a predicate most wants to be heard; that shape is
deliberately rejected here. `redirect_count` is part of what the snapshot hands the predicate — a predicate that
wants its own, different notion of "too many hops" can read it and decide not to follow on its own account — but
the step does not let a predicate override the cap upward, because `REDIR-17`'s
"the number of followed redirects MUST be capped by maxHops" is phrased with no carve-out for a predicate and
because an uncapped custom predicate would turn `REDIR-23`'s stack-safety guarantee (bounded memory per hop, an
iterative loop) into an unbounded one in wall-clock and connection terms even though it stays stack-safe. The
predicate genuinely does replace `REDIR-3`/`REDIR-4`'s allowed-method check, `REDIR-16`'s loop-URI check and
`REDIR-19`'s missing-Location check — every clause the specification frames as part of *whether this particular
hop should be followed* — because those are all read from the same snapshot the predicate receives and none of
them is independently safety-critical the way an unbounded loop is. `REDIR-15`'s downgrade rejection and
`REDIR-7`/`REDIR-8`/`REDIR-9`/`REDIR-11`/`REDIR-24`'s credential hygiene are **never** overridable by a
predicate either, for the same reason and because the specification itself frames them as unconditional
("`REDIR-7`... MUST be stripped before EVERY redirect re-issue"), never as part of "the decision." Neither are
`REDIR-18`'s and `REDIR-19`'s MUST-not-throw clauses: `resolve_target` (`R7`) runs before either decision route
and a `nil` from it returns the current response unfollowed whatever a predicate would have answered — which is
also what keeps a predicate-forced follow from reaching `Location.resolve` with a `nil` header value, where
`URI::RFC3986_PARSER.join` raises `ArgumentError` rather than the `URI::InvalidURIError` any rescue here expects.
Filed below as a candidate for the phase-6 Deviation Ledger, numbered at consolidation (`P6-<n>`, not assigned
here because `6a` and `6c` are being written concurrently and a specific number would risk colliding with
theirs).

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

## Findings, and who owns them now

Three, each named with the owner that carries it. **None is acted on by this document, and no file outside
`docs/work/mvp/phase6/phase6b/` is edited by it** — the frozen-tree rule and the "these edits are not `6b`'s to
make" instruction both apply.

**No finding to route — corrected in place instead, 2026-09-09.** **The charter's *Prerequisites* section
wrote `Dexpace::HTTP::URL.parse!` where the shipped constant is the flat `Dexpace::URL`.** Verified 2026-09-09
against every `module`/`class` declaration in
`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model.md`: `Dexpace::URL` is a direct child of
`Dexpace`, with no `Dexpace::HTTP` namespace anywhere in phase 1's shipped surface, per `P1-1`'s "flat unless
the design namespaced the subsystem" and §3's namespacing nothing. This sub-phase's own text cites
`Dexpace::URL` throughout and never repeated the slip. **Disposition:** the charter is same-day, uncommitted
work and no design decision rested on the wrong namespace, so all four occurrences were corrected in the
charter directly rather than routed to an owner — a finding is routed only when nobody is acting on it, and
this one was acted on. `6c`'s plan carried one instance in a code sample and was corrected with it.
Cites: `P1-1`, `HTTP-47`.

**Owner: `docs/knowledge/notes/url-and-query-encoding.md`.** **The `URI::Generic#userinfo = nil`
no-op note, filed in full under *Verified Ruby facts*, fact 1 above.** The charter names this as `6b`'s to file
"with the design that acts on it," which this document is; the exact text, key placement (a new `## Superseded`
or `## Reference` entry, since it does not override an *existing* harvested rule about `#userinfo=` — none
exists — it instead **adds** a fact the corpus does not yet carry, so `## Reference` is the more accurate
section per the skill's own guidance: "`## Reference` when the note only points somewhere") and manual `sha:`
marker are given above, ready to paste.

**Owner: `.claude/skills/knowledge-lookup/SKILL.md`'s audit-group table.** **The eleventh row the
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
`Dexpace::StreamError < ::IOError`. **The `Dexpace::Resilience` re-sendability namespace does not yet exist as a
shipped surface** — 3b's own forward table names it as phase 6's to write. This sub-phase's plan adds
`Resend.replayable_body?(request)` and `Resend::NotReplayableError` to it and adds nothing else; `Resend.eligible?`,
with `RETRY-7`'s idempotency clause, is `6a`'s and is never called from here, under the independence caveat given
at the top of this document.

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
to avoid. **The `Cursor` context-bundle widening (`R13`)** travels with whichever of the three sub-phases lands first; this
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
2. **`Pipeline.standard`, which phase 4c postponed to phase 6.** A phase-level task, executed by whichever of `6a`/`6b`
   lands second (under the recommended order, this plan's Task 13a) — see the charter. `6b` does not build it and states here, as the charter requires, that landing this sub-phase
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

**Reused from phase 4c, unmodified — under the names 4c actually ships, verified against its plan rather than
recalled.** They live in `gems/dexpace-core/test/support/probe_steps.rb` (not a `state_probe.rb`), they are
**top-level constants** in no namespace, and the write and read sides are two different classes:
`ForkingProbe.new(times:, state_per_drive:)` is R11's write side (it forks for every drive and writes each
drive's state map into its own stage slot) and `StateProbe.new(stage_to_read:)` is the read side, recording
`cursor.state(stage_to_read)` into `#reads` at every invocation. Neither declares `#stage` — 4c asserts
`refute_respond_to(…, :stage)` — so every install in this sub-phase's suite names the stage as an `append`
argument. `StateProbe` is what goes at `Stages::AUTH` in every test that needs to observe what
`Redirect::Step`'s fork actually wrote, which is how this sub-phase **extends 4c's R11 negative-assertion 4 from
a probe pair to a real step**: the assertion 4c wrote with a `ForkingProbe` writing and a `StateProbe` reading is
re-run here with the real `Redirect::Step` at `REDIRECT` and a `StateProbe` reader at `AUTH`, proving the
production step obeys the write-restriction contract it was built against, not only that the contract itself
holds for a probe.

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
- **`REDIR-22a`'s ordering is a separate assertion from its effect, and only the ordering one is load-bearing.**
  The requirement is "**before** issuing a follow-up request, the prior redirect response's body MUST be
  closed", and design §6.2 restates it in those words; 4c's own `ForkingProbe` — the `PIPE-40` fixture this
  sub-phase extends — closes the superseded intermediate and only then issues the next drive. Deferring the
  close to *after* the next fork returns passes every close-flag assertion above and is still wrong: it holds
  hop N's connection for the whole of hop N+1, which deadlocks any transport with a one-connection pool. So the
  suite asserts the **order** — the fake body's close is recorded against the transport's call count — and not
  merely that the close happened.

## Deviation Ledger

**One candidate, named here and numbered at consolidation.** `REDIR-17`'s max-hops cap is enforced as a hard
ceiling the step checks *before* consulting a configured predicate, rather than folding it into the "built-in
follow decision" `REDIR-20` says a predicate fully overrides. Argued in full under `R9` above. *Touches*
`REDIR-17`, `REDIR-20`, `REDIR-23`. Not numbered `P6-<n>` here because `6a` and `6c` are being written
concurrently under the same phase and a number assigned in isolation could collide; the consolidation step
(design §10) assigns the final number across all three sub-phases' ledgers at once.

**Nothing else in this sub-phase substitutes a mechanism the reference specifies.** The cross-origin marker
substitution is §10.15's, already argued and consolidated, and `6b` implements it rather than re-arguing it.

### As built, 2026-09-19

The one candidate above is now a row, and the order it names is corrected: the step is built as `R9`
says — the predicate is consulted, then the cap vetoes — and not as this ledger's own paragraph and the
roadmap's 6b note put it ("checked *before* a configured predicate is consulted"). This sub-phase was cut
from `main` at `e61864f`, which holds both 6a and 6c, so it landed **last**: Task 2 extended 6a's
`resend.rb` in place, Task 13a wrote the two `standard` constructors over 6a's `RetryStep` /
`AsyncRetryStep` and 5b's steps, and convergence point 1 — 6c's guarded end-to-end test — was un-guarded
here. The `Cursor` context-bundle widening (6a's Task 8) exists on this base and is consumed **not at
all**: a `Bundle` carries a span tracer factory and trace ids, not a logger, and the step's `logger:`
keyword is its own, as *Independence* committed to. Execution added the rows below, numbered from
**P6-91** as the manager fixed it — 6a's as-built rows are P6-51–P6-61 and 6c's P6-71–P6-87, and this
document numbered nothing before today; outside this document a 6a or 6c row is cited as "6a's P6-n" /
"6c's P6-n". The checklist's "Deviations from the plan" is the itemised list against the plan's text; the
rows here are the ones that touch public behaviour, the contract a later phase cites, or a statement
this document makes.

Seven statements above read differently against the source, and the difference is recorded here rather
than by rewriting the text it corrects:

- **The step is `Step.build`, `.new` private, frozen, and has no `redactor:` keyword.** The object
  model's `Step.new(...)` with seven keywords departs from every configured public class in the tree
  since 5b (`Instrumentation::Step.build`, 6a's `RetryStep.build`, 6c's `Auth::Step.build`), and `R8`'s
  "own `logger:`/`redactor:` keywords" re-introduces the two-policy drift 5b's review removed (P5-95:
  one redactor per logging path, the logger's). The private `Emitter` reads `logger.redactor`; a
  caller who wants a different policy builds the logger with it (P6-93).
- **`NotReplayableError` is flat under `Dexpace::`**, not `Dexpace::Resilience::NotReplayableError`:
  6a filed its one `Resilience` error, `RetryPredicateError`, flat under `error/` (6a's P6-56) and a
  namespace holding one flat and one nested error would be two conventions (P6-94).
- **`Location.resolve` also refuses a host-less target, and it strips and freezes.** `R7`'s screen is the
  scheme alone; measured on every row, `join` also hands back `http:foo` (host `nil`) and `http:///p`
  (host `""`), which `Origin.of` would have read as `nil.downcase` or dispatched host-less, so the screen
  is scheme AND host — `REDIR-18`'s "unresolvable". And the userinfo strip and the freeze live inside
  `Location.resolve` rather than at `Step`'s call site: one function turns a wire value into a
  dispatchable, credential-free, frozen target, and the conversion-and-log site in `Step` stays one
  `rescue` (P6-95).
- **The Set-of-URI rationale under `R9` is false.** `URI::Generic` defines `==`, `eql?` and `hash`, and
  `Set[a].include?(b)` is `true` for two parses of one string on every row (`matrix_facts_test.rb`).
  `visited_uris` stays a `Set<String>` of external forms — the wire-exact rendering is the right key
  regardless — but not for the reason this document gave; no YARD repeats it.
- **`REDIR-13` has a residue upstream of this layer.** `URI#to_s` elides an explicit scheme-default port
  and phase 1's `URL.parse!` re-parses a URI from its text (P5-91), so `Location: https://h:443/y`
  reaches the wire as `https://h/y`; every non-default port and every IPv6 literal survives, the origin
  is unchanged, and the elision is phase 1's (P6-96).
- **`REDIR-15`'s rejection is emitted, not only raised.** `R8` defined `SCHEME_DOWNGRADE_REJECTED` and the
  plan wired only the permitted branch; a constant nothing emits is an event a reader waits for in vain,
  and `REDIR-28`'s "scheme-downgrade event" has two outcomes. The refusal is recorded at WARNING before
  the response is closed and the error raised (P6-97).
- **The hop record's status key is 5b's.** `Keys::STATUS_CODE` is not shipped;
  `Instrumentation::Keys::HTTP_RESPONSE_STATUS_CODE` is one name for one thing across every record
  (P6-98).

Two things this document did not say and the build decided:

- **A raising predicate closes the current response.** `REDIR-22b` names the two build failures; a
  caller's predicate that raises is neither, and the requirement's own reason — nobody else will close
  a response the caller never receives — applies to it unchanged. The frame that closes before a raise
  covers the predicate call too (P6-99).
- **The two `standard` constructors' keyword set** (P6-100), below — the design's convergence point 2
  handed the task to "whichever lands second", and that is this sub-phase.

| # | Deviation | Touches | Why |
|---|---|---|---|
| P6-91 | `REDIR-17`'s cap is a hard ceiling applied **over** a configured predicate's answer: on a recognized 3xx the snapshot is allocated and the predicate consulted at every hop, the capped one included, and only then does the cap veto a `true` — never "before a configured predicate is consulted", as this ledger's paragraph above and the roadmap's 6b note put it | `REDIR-17`, `REDIR-20`, `REDIR-21`, `REDIR-23` | `R9`'s argument, as built: placing the cap above the predicate would make `REDIR-21`'s "always … consults the configured predicate" false at the one hop a predicate most wants to be heard; the predicate reads `redirect_count` off the snapshot and may stop earlier, and cannot lift the cap because `REDIR-17` is phrased with no carve-out and an uncapped predicate would make `REDIR-23`'s stack safety unbounded in connections (`step_test.rb` `PredicateTest`, "the cap vetoes a predicate that says FOLLOW"; guard 20) |
| P6-92 | New public names, `NFR-4`-locked from this phase (6a's P6-1/P6-2 precedent): `Dexpace::Redirect::Step` (`.build`, `#stage`, `#call`, `DEFAULT_ALLOWED_METHODS`, `DEFAULT_MAX_HOPS`), `Redirect::ConditionSnapshot` (`.build`, three readers, `#with`), `Redirect::Events` (five), `Redirect::Keys` (four), `Redirect::SchemeDowngradeError`, `Dexpace::NotReplayableError`, `Resilience::Resend.replayable_body?`, `Pipeline.standard`, `AsyncPipeline.standard` — twenty-eight manifest rows, 1 109 → 1 137, all widenings | `NFR-4`; the object model above; `PIPE-39` | Every one is named in the object model or in the rows below; `Origin`, `Location`, `Chain`, `Emitter` and `Reissue` are `private_constant`s with `sig/` mirrors and no manifest row |
| P6-93 | `Redirect::Step.build(allowed_methods: DEFAULT_ALLOWED_METHODS, follow303: false, max_hops: DEFAULT_MAX_HOPS, allow_scheme_downgrade: false, predicate: nil, logger: Logger::NULL)`, `.new` private, frozen, with **no `redactor:`** keyword: the records go through `logger.redactor` | `R8`; the object model's constructor; 5b's P5-34, P5-95 | One construction shape per phase since 5b, and one redaction policy per logging path — `R8`'s second keyword re-introduced the drift 5b's review removed; the "raising redactor" case is `Logger.build(sink:, redactor: raising)` and the emitter's own rescue degrades the field to the placeholder |
| P6-94 | `Dexpace::NotReplayableError` is flat under `Dexpace::`, in `lib/dexpace/error/not_replayable_error.rb`, not `Dexpace::Resilience::NotReplayableError` | `REDIR-6`; *Independence*; 6a's P6-56 | The one other `Resilience` error, `RetryPredicateError`, is flat; the smoke suite's layer table pins it beside `Redirect` |
| P6-95 | `Location.resolve` screens for an `http`/`https` scheme **and** a non-empty host, and answers the target userinfo-stripped and frozen; `Step#resolve` is one `rescue ::URI::InvalidURIError` that logs the raw value and answers nil | `REDIR-12`, `REDIR-18`; `R7` | `join` resolves `http:foo` and `http:///p` without raising (verified on every row); a host-less target is `REDIR-18`'s "unresolvable" and would otherwise raise `NoMethodError` inside `Origin` or be dispatched host-less; one function owns the wire-value-to-target transformation |
| P6-96 | `REDIR-13`'s "MUST preserve explicit ports" holds for every non-default port and every IPv6 literal, and an **explicit scheme-default port is elided** — `Location: https://h:443/y` reaches the wire as `https://h/y` | `REDIR-13`; phase 1's `URL.parse!`; 5b's P5-91 | `URI#to_s` drops a default port on every supported Ruby and `URL.parse!` re-parses a URI from its text, so the elision happens at phase 1's model boundary, upstream of this layer; the origin triple reads the parsed port and is unchanged; the suite never asserts that `:443` survives (`step_test.rb` `LocationTest`, "REDIR-13 residue") |
| P6-97 | `REDIR-15`'s refusal emits `Events::SCHEME_DOWNGRADE_REJECTED` at WARNING before the current response is closed and `SchemeDowngradeError` raised; the opt-in emits `SCHEME_DOWNGRADE_PERMITTED` | `REDIR-15`, `REDIR-28`; `R8` | `REDIR-28`'s "scheme-downgrade event" has two outcomes and two names, and a defined constant nothing emits is a trap under `OBS-39`'s "stable and predictable set" |
| P6-98 | The hop record's status field is `Instrumentation::Keys::HTTP_RESPONSE_STATUS_CODE`; `Redirect::Keys` has no `STATUS_CODE` and holds four keys, not five | `REDIR-28`, `OBS-39`; `R8`'s `Keys` listing | One name for one thing across every record core emits; the redirect response's status IS a response status code |
| P6-99 | A predicate that raises leaves the current response **closed** — the frame that closes before a raise (`REDIR-22b`) wraps the decision as well as the build | `REDIR-20`, `REDIR-22` | `REDIR-22b` names the two build failures; a raising predicate is a third raise out of the same loop with the same consequence — a response the caller never receives — and the requirement's reason applies unchanged (`step_test.rb` `PredicateTest`, "a predicate that raises") |
| P6-100 | `Pipeline.standard(over, redirect: nil, settings: RetrySettings.build, http_tracer_factory: nil, logger: Logger::NULL, level: HTTPLogging::DEFAULT, preview_bytes: nil)` and `AsyncPipeline.standard(over, redirect:, …the same…)`: `over` is a transport **or** a `Pipeline::Builder` already holding one; the async `redirect:` is required and admits `:unsupported` alone; a nil `http_tracer_factory:` leaves the retry family's own private default in place; no `builder:`, `retry:` or `instrumentation:` keyword | `PIPE-24`, `PIPE-32`, `PIPE-39`, `REDIR-25`; design §5.3; the charter's `R14` | `PIPE-24`'s "into EMPTY slots only … rejecting the whole call if any is occupied" is reachable through the constructor only if a builder can be handed in, and a positional that is ignored when `builder:` is given (the plan's shape) is a worse API than one positional discriminated by type; `retry` is a keyword Ruby cannot read back (`SyntaxError: Invalid retry`); the four shared keywords thread to the steps rather than taking built steps, so `logger:` reaches the redirect step too (`pipeline/standard_test.rb`; guards 43–51) |

**Review round 1, 2026-09-19.** Round 0 of the stack's review found no behaviour this document states
that the code fails to honour, and adds no row: its two should-fix findings were coverage gaps in the
suites behind two checklist rows. `PIPE-39`'s "`settings:` … reach the retry step" was inferred from a
call count the default schedule reproduces — the default settings retry a 503 too, after a real backoff
on `Clock::SYSTEM` — so the sync wiring case now reads the retry's one wait off the `FakeClock` the
settings carry and a second case drives `max_retries: 0`; and `REDIR-9`'s "or the 303 GET rebuild"
clause, which `Reissue.build` honours by stripping before it rebuilds (the *Object model*'s order),
had no test driving a cross-origin 303 with `Cookie` or `Proxy-Authorization`, and has one. Both are the
checklist's guards 51 and 52, red on 4.0.6 and 3.2.11, with no `lib/` line changed; the round's two nits
— the checklist's `NFR-13` count and the two over-long commit subjects — are the checklist's and the
stack's, not this document's.

**Review round 2, 2026-09-19.** Round 1 of the stack's review found no behaviour this document states
that the code fails to honour either, and adds no row: its one should-fix was a coverage gap behind
`REDIR-13`'s row. The MUST names "path, query, and fragment", and `Location.resolve` — one
`URI::RFC3986_PARSER.join`, no re-rendering — preserves all three, which the reviewer's own probe showed
reaching the transport byte for byte; but no test in the phase drove a fragment-carrying `Location`,
the `REDIR-14` case titled for a fragment-only reference carried none, and dropping the fragment from
the resolved target left every redirect suite green on 4.0.6 and 3.2.11. `LocationTest` now drives the
fragment-only reference, which resolves against the *current* hop and keeps that hop's path and query,
and a `REDIR-13` case sends a fragment, a percent-encoded fragment, an empty query and an empty
fragment; the four mutations behind them are the checklist's guards 53–56, red on both rows, and the
`REDIR-15` and `REDIR-18` cases moved to a `RefusedTargetTest` when the addition crossed
`Metrics/ClassLength`. No `lib/` line changed; the round's one nit — a class count in the checklist's
departure 32 — is the checklist's.

**Review round 3, 2026-09-19.** Round 2 of the stack's review found no behaviour this document
states that the code fails to honour either, and adds no row: its two should-fixes were coverage
gaps behind two MUST rows, each found by mutations that survived on 4.0.6 and 3.2.11 while the
reviewer's own probes showed the code right. `REDIR-3` says "there is deliberately NO automatic
POST→GET rewrite for 301/302", and `Reissue.build` honours it — `request.with(url:, headers:)` on
every non-303 hop, the method and the body untouched — but no test followed a 301 or a 302 on a
non-`GET`/`HEAD` method and asserted the re-issued method or body, so a rewrite on those two
statuses (the method, the body, or both) left every suite green; `ReissueTest` now follows a 301 and
a 302 on a `POST` and on a `PUT` and asserts the method token, the same body object and the
`Content-Type` on the transport's second call. `REDIR-5` says "case-insensitively", and
`Reissue.rebuild_as_get`'s prefix test is the `name.downcase.start_with?("content-")` the *Scope*
bullet spells — but every 303 case carried canonical casing, so dropping the fold survived; a case
whose `POST` carries `content-type`, `CONTENT-LENGTH` and `cOnTeNt-Language` now asserts each gone
from the rebuilt `GET`. The four mutations are the checklist's guards 57–60, red on both rows, and
the four earlier 303 cases moved unchanged to a `RebuildTest`, which the new one joins, when
`ReissueTest` reached `Metrics/ClassLength`. No `lib/` line changed; the round's one nit — a page
count in `docs/README.md` — is the index's.
