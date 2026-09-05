# Phase 1 — Core HTTP Domain Model

**Status:** Draft, approved for planning.

## Purpose

Phase 1 builds the wire model every other prefix stands on: the frozen, transport-agnostic value
types that fix case-insensitivity, multi-value semantics, ordering, header-injection defence,
method/body legality and total status handling once, so no transport can behave differently. It is
the first phase that ships domain code, and it makes four decisions the remaining nine phases
inherit whether or not they re-read this document: what a core value type looks like, what its
public constant is called, what an error in this SDK is, and what "validated" means at a byte
level.

Two of those decisions were forced by facts verified on real interpreters during planning rather
than by taste. `Data#with` — the derivation path design §4 gives every value type that has no
builder — **does not call an `initialize` override on Ruby 3.2**, so every `HTTP-4`/`SEAM-29`
validation would be skipped on the declared floor while passing on the developer's 4.0. And
`String#strip`, the obvious way to implement `HTTP-17`'s "surrounding whitespace is trimmed before
validation", **also strips trailing NUL**, so `"a\0"` would trim to `"a"` and pass the very check
that exists to reject it. Both are stated in full below with the interpreter evidence.

Phase 1 ships no transport, no body, no seam and no pipeline. Its tests need none of them: every
type here is a pure value, and the phase's whole test surface is construction, derivation,
validation, encoding and equality.

## Governing documents

Five, in the roadmap's order, all binding here:

- `docs/product-spec/04-core-http-domain-model.md` — this phase's normative chapter, `HTTP-3`
  through `HTTP-35`, `HTTP-46`–`HTTP-50` and `HTTP-53`; and
  `docs/product-spec/02-architectural-principles.md` for `HTTP-1`/`HTTP-2`. Appendix C is the ID
  index.
- `docs/sdk-design-ruby/04-domain-model-construction.md` in full — the construction pattern, the
  builder/`#with` split, read-only collection exposure, the P8 encapsulation gap and the header,
  status, media-type, query and request-options mappings; and
  `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.5 for the strict component
  encoder and the `URI::RFC3986_PARSER` pin (`HTTP-29`, `HTTP-32`,
  `HTTP-47`); §2.3 for the layout; §10 items 10 and 11 and §11 item 6 for what this port admits it
  cannot close.
- The Ruby styleguide, `styleguide/ruby/`, queried through the corpus — chapters 3, 6, 8, 10, 11,
  12 and 14. Binding except where a note under `docs/knowledge/notes/` records otherwise, and this
  phase files four such notes, one of them carrying two entries.
- `CLAUDE.md` — the domain-model construction pattern, the constraints that will bite, the
  requirement-ID conventions and the public-API definition.
- `docs/README.md` — the ownership table and the `docs/work/` naming rules.

## Scope

### Requirement IDs in scope

**Thirty-nine numbered IDs**, the roadmap's phase-1 row: `HTTP-3`–`HTTP-35` (33),
`HTTP-46`–`HTTP-50` (5) and `HTTP-53` (1). All belong to
`docs/product-spec/04-core-http-domain-model.md`.

**Plus `HTTP-1` and `HTTP-2`, satisfied by construction, as two further checklist rows, and
`SEAM-29` as one more — 42 in total.** The brief for this phase placed `HTTP-1`/`HTTP-2` in phase 2
as "seam wiring"; that is wrong, and appendix C is what the scope follows. Its rows 37 and 38 give
both the subsystem **Core HTTP domain model**, phase 2's row is `SEAM-1`–`SEAM-30` and nothing
else, and the roadmap's own accounting reads "`HTTP-1`/`HTTP-2`, the ch.02 framing pair phase 1
satisfies by construction."
They are satisfied here by the construction pattern itself rather than by a component of their
own: `HTTP-1` by every type being a frozen `Data` whose collections are deep-frozen at
construction, `HTTP-2` by `private_class_method :new` plus a validating `.build` — with `HTTP-2`'s
residual gap admitted, not papered over (§10.10, and the Testing section below).

**`SEAM-29`'s construction contract is honoured here, ahead of phase 2**, per the roadmap's
phase-1 row, and it is a checklist row of its own — **42 rows in all**. It carries two MUSTs and
this phase implements both. The uniform-validation half — "a missing required field fails at
`build()` with a message of the form `<name> is required`" (`data-modeling/1d3d3827`) — is the one
shared helper this phase lands, which is also what `docs/knowledge/notes/assertions.md` names as
this repository's production assertion primitive. The second half — "a shared generic Builder
contract (`build()` producing the target type) MUST exist so generic composition helpers can accept
any builder" (spec ch.03 §3.8) — is `Dexpace::Builder`, below. No other `SEAM` ID is in scope.

`XCUT-15` and `XCUT-18` are phase 9's to disposition, but both are *implemented* here, because
they restate `HTTP-1` and `HTTP-17`/`HTTP-18` in the cross-cutting chapter. Phase 1 does not claim
them; it leaves them satisfiable.

### Out of scope, explicitly

| Excluded | Owning phase |
|---|---|
| `HTTP-36`–`HTTP-45`, `HTTP-51`, `HTTP-52` — body lifecycle, jointly numbered into spec ch.06 | 3 |
| `SEAM-1`–`SEAM-30` — the seam interfaces, including `SEAM-26`/`SEAM-27`'s operation projection, which is the rest of design §3.5 | 2 |
| `CFG-*` and the `Configuration` builder design §4 lists beside `Request` and `Response` | 5 |
| `RETRY-*`'s consumption of `HTTP-9`'s idempotency set, and `REDIR`/`AUTH` | 6 |
| The transport-side re-validation of header names and outbound values (`XCUT-18`) — phase 1 ships the validator functions, phase 8 calls them | 8 |
| `HTTP-22` (MAY, name interning) and `HTTP-48`–`HTTP-50` (SHOULD; ETag, HTTP range, conditional-request aggregator) | 6 — `DEF-2`, given that target by this phase's register sweep; see below |

**No segmentation design.** The roadmap's segmentation rule reaches a build phase whose ID count
"clearly exceeds earlier phases'", or that spans more than one ID-bearing spec chapter, or that
ships more than one gem. Phase 1 is 39 IDs in one chapter shipping one gem — fewer IDs than every
later build phase except phase 8's nominal count — and the roadmap's own list of expected
sub-phases starts at phase 3. One phase, one design, one plan.

## Prerequisite

**Phase 0, in full.** Phase 1 writes its first file into a workspace that already has seventeen
blocking gates, and is written under them from its first line. Specifically it relies on:

- **The `dexpace-core` skeleton** — its gemspec with zero `add_dependency` lines, `lib/dexpace.rb`,
  `lib/dexpace/version.rb`, the two `sig/` mirrors, its `Rakefile` and `test/test_helper.rb`. Every
  file phase 1 adds goes under that gem and nowhere else.
- **The test convention** — `test/support/dexpace_test_case.rb`, providing `DexpaceTestCase.test
  "..." do`, the `Warning.warn` override that makes a warning fail the test that triggered it, and
  `#sample(count:, seed:)` for the bounded property-style tests styleguide 11.7 makes mandatory
  for value objects with parse-constructor invariants. `gems/dexpace-core/test/test_helper.rb`
  puts the gem's `lib/` on `$LOAD_PATH` and requires that base.
- **The gates**, unchanged and unlowered: `rubocop` with the five custom cops
  (`Dexpace/SpdxHeader`, `Dexpace/NoTimeParse`, `Dexpace/NoUriDefaultParser`,
  `Dexpace/NoLocaleCaseFold`, `Dexpace/NoThreadInterrupt`), `rbs:validate`, `steep` with `core`
  strict, `test:gems` under `-w -W:deprecated` with the SimpleCov floor,
  `gates:require_allowlist`, `gates:rbs_surface`, `gates:surface_snapshot` against
  `test/fixtures/surface/dexpace-core.txt`, and `gates:sig_diff`.
- **The require allowlist** — core may `require` only `monitor`, `uri`, `stringio`, `strscan`,
  `time`, `date`, `securerandom`, `digest`, `openssl`, `forwardable`, `set`, `singleton`. Phase 1
  uses exactly one of them, `uri`, and adds nothing to the list.

Three of phase 0's four custom lint cops become load-bearing for the first time here rather than
in phase 0, because phase 0 shipped no code they could bite on: `Dexpace/NoUriDefaultParser` over
every URL parse, `Dexpace/NoLocaleCaseFold` over every header-name fold, and `Dexpace/SpdxHeader`
over roughly forty new files.

**What phase 1 changes about the gates' denominator.** `NFR-5`'s coverage floor was armed and
green over twelve entry and version files (phase 0's deviation P0-10). This phase is the first
where 80% is a number someone has to work for, and the first regeneration of
`test/fixtures/surface/dexpace-core.txt` since it was created two lines long.

## Corpus reading, and what it settled

The phase-start pair was run before anything here was written.
`ruby scripts/knowledge.rb --section conflicts --brief` returns the six styleguide-versus-design
conflicts and **all six print `[overridden by notes/…]`**; none is open. `--origin note --brief`
returns the same six plus phase 0's five, and nothing in either set contradicts this phase's plan.

`ruby scripts/knowledge.rb --gaps HTTP` reports **53 of 53 IDs substantive, zero roll-up-only,
zero uncited**. This phase therefore budgets **no direct specification reading beyond its own
chapter**, which it reads in full anyway because it is the chapter phase 1 exists to implement.
`--prefix-info HTTP` confirms the owning chapter and the 43/9/1 MUST/SHOULD/MAY split.
`--phase 0 --brief` shows phase 0's documents already cite `HTTP-13` — the locale-fold cop — and
nothing else in this prefix.

Four audit groups from the `knowledge-lookup` skill's table were run in full. Each is named with
the query that produced it, then its result.

**Public API surface** —
`--topic api-design,http-domain-model,documentation,module-organization,error-handling --section rules`.
Three rules routed to this phase are resolved here, all by note: `error-handling/51261878` (one
project-level base exception **class**), `error-handling/75571c73` (`Assert::InvariantViolation`
for programmer errors) and `module-organization/3ff5433e` (filename is the snake_case of the
constant path, resolved for the `http/` and `error/` trees). `api-design/3279c12e` was already
answered by `type-system/169c8f38`. Adopted unchanged and load-bearing here: `api-design/c15b29ce`
(freeze every returned collection), `api-design/e4fa3438` (`Data.define` for the value protocol,
overriding a generated method only with a why-comment — this phase does it three times, for
`HeaderName`, `Headers` and `Request`), `api-design/ea8f21e6` and `type-system/6b1e444e` (one
parse-constructor per type, named `parse`), `documentation/80beb95e` and `/42d8cbf4` (YARD every
public entity, never restate a signature).

**RBS / Steep typing** — `--chapter 3 --section rules` and
`--topic type-system,data-modeling --section rules`. One rule with no note, and it is this phase's:
`type-system/4a058b71` (closed domain sets modelled with `T::Enum`), routed here by phase 0's
design because phase 1 owns the domain model. Resolved by note. `type-system/e4969b16` (`fetch`
over `[]`) and `/b5166811` (`nil` as a last resort) are adopted; the one place `nil` is the
contract — `MediaType#charset` returning `nil` for absent or unknown — is `HTTP-24`'s own wording
and is documented at the accessor.

**Minitest conventions** — `--chapter 11 --section rules` and
`--topic testing,assertions --section rules`. Clean; `assertions/df75bd2e` is already overridden by
`docs/knowledge/notes/assertions.md`, whose "the helper lands in phase 1" is what this phase
delivers. Three rules shape the test plan rather than the code: `testing/f36a19cd` (property-based
round-trip tests **mandatory** for codecs, parsers and value objects with parse-constructor
invariants), `testing/62f8f4ec` (every error boundary gets a negative test asserting class, message
and no partial side effect — which is what caught the builder's orphan-casing entry) and
`testing/4ef070df` (every test alone, in any order, seed never overridden).

**Encoding and binary strings** — `--prefix IO --section rules` and
`--topic io-and-byte-streams,serde --section rules` narrowed with
`--grep 'encoding|binary|ASCII-8BIT|force_encoding'`. Clean, and two rules are directly
load-bearing: `io-and-byte-streams/ff0de47e` (wire bytes are always `Encoding::BINARY`) and
`/0a4773a6` (`String#b` is "these bytes, untagged"; `force_encoding` is a retag used only where the
bytes are known to conform). Phase 1 handles no socket, but it validates and encodes strings that
may carry any byte, which is where the verified findings below live.

### Four notes filed against the corpus by this phase

Written before the plan, because a resolution recorded only in a design document is re-litigated
by whoever reads the corpus next.

- `docs/knowledge/notes/module-organization.md`, `## Conflicts` — the public wire model's
  constants are flat (`Dexpace::Request`) while their files sit under `lib/dexpace/http/`.
  Resolves `module-organization/3ff5433e`.
- `docs/knowledge/notes/error-handling.md`, `## Conflicts` — `Dexpace::Error` is a **module**
  included by every core error class, not a base class, and there is no `Assert` facade. Resolves
  `error-handling/51261878` and `error-handling/75571c73`.
- `docs/knowledge/notes/type-system.md`, `## Conflicts` — closed domain sets are frozen `Data`
  value types with `parse`/`of` factories over a frozen table, because `T::Enum` is
  `sorbet-runtime` and this gem has no dependencies. Resolves `type-system/4a058b71`.
- `docs/knowledge/notes/data-modeling.md`, `## Superseded` — two entries: `Data#with` does not call
  an `initialize` override on Ruby 3.2 (supersedes `data-modeling/c4fe4732`, verified on 3.4.10
  only), and the wire model is Ractor-shareable *except* where a member is a `URI::Generic`
  (supersedes `data-modeling/996c0b12`).

### The verified Ruby facts this phase is built on

Re-verified on 2026-09-05 against three installed interpreters — 3.2.11, 3.4.10 and 4.0.6 — the
same discipline phase 0 applied to the bundled-gem list.

1. **`Data#with` does not call an `initialize` override on Ruby 3.2.** Given a `Data` subclass
   whose `initialize` raises on a `nil` member, `instance.with(member: nil)` returns
   `#<data … member=nil>` on **3.2.11** and raises on **3.4.10** and **4.0.6**. The override is
   simply not invoked on the floor. Design §4 makes `#with` the *only* derivation path for
   `MediaType`, `Status`, `Protocol`, `Method`, `HeaderName` and the conditional helpers, so the
   unpatched reading of that design ships unvalidated derivation on one supported Ruby and
   validated derivation on the rest — the same shape as the `URI::DEFAULT_PARSER` hazard §3.5
   describes, and no more acceptable. The fix is one `#with` override in the shared construction
   helper, which every `Data` type in every later phase gets by including one module.
2. **`String#strip` strips trailing NUL.** `"a\0".strip` is `"a"` on all three interpreters, so a
   header name `"a\0"` trimmed with `strip` before validation passes a check whose entire purpose
   is to reject NUL (`HTTP-17`). Trimming is SP and HTAB only.
3. **A character-oriented operation on an invalid-UTF-8 `String` raises rather than returning
   false.** `"h\xE9der".strip` raises `Encoding::CompatibilityError`, and matching the same
   string against a printable-ASCII regexp raises `ArgumentError: invalid byte sequence in
   UTF-8`. A validator that raises the wrong error class has not rejected the input; it has
   crashed. Every validation and encoding predicate in
   this phase reads bytes from `String#b`.
4. **`Ractor.make_shareable` deep-freezes in place and returns the same object**, and a `Data`
   holding a shallow-frozen `Hash` is *not* `Ractor.shareable?` while one holding a deep-frozen
   `Hash` is. Both halves verified on 3.2.11 and 4.0.6, confirming design §4's claim and its
   caveat. The safe form is `Ractor.make_shareable(collection, copy: true)`, verified on both
   interpreters to return a deep-frozen **copy** while leaving the source hash, its arrays and
   their strings unfrozen — which a plain `collection.dup` does not achieve, because `dup` is
   shallow and the nested arrays would still be the caller's.
5. **`Regexp.new(source, timeout:)` is available on 3.2.11** and `URI::RFC3986_PARSER` resolves on
   every supported Ruby, while `URI::DEFAULT_PARSER` is `URI::RFC2396_Parser` on 3.2.11 and
   `URI::RFC3986_Parser` on 3.4.10 — the split §3.5 pins against.

## Module Layout

Every file phase 1 creates, under `gems/dexpace-core/`. `sig/` mirrors `lib/` one file per file
and ships inside the gem; `test/` mirrors `lib/` one file per file and does not ship.

```
lib/dexpace.rb                              MODIFIED: explicit requires for the whole tree below
lib/dexpace/error.rb                        Dexpace::Error                (module)
lib/dexpace/error/invalid_argument_error.rb Dexpace::InvalidArgumentError
lib/dexpace/model.rb                        Dexpace::Model                (the construction helper)
lib/dexpace/builder.rb                      Dexpace::Builder              (SEAM-29's contract)
lib/dexpace/http/header_syntax.rb           Dexpace::HeaderSyntax
lib/dexpace/http/header_name.rb             Dexpace::HeaderName
lib/dexpace/http/headers.rb                 Dexpace::Headers
lib/dexpace/http/headers/builder.rb         Dexpace::Headers::Builder
lib/dexpace/http/status.rb                  Dexpace::Status
lib/dexpace/http/method.rb                  Dexpace::Method
lib/dexpace/http/protocol.rb                Dexpace::Protocol
lib/dexpace/http/media_type.rb              Dexpace::MediaType
lib/dexpace/http/percent_encoding.rb        Dexpace::PercentEncoding
lib/dexpace/http/query.rb                   Dexpace::Query
lib/dexpace/http/query/builder.rb           Dexpace::Query::Builder
lib/dexpace/http/url.rb                     Dexpace::URL
lib/dexpace/http/request_options.rb         Dexpace::RequestOptions
lib/dexpace/http/request_options/builder.rb Dexpace::RequestOptions::Builder
lib/dexpace/http/request.rb                 Dexpace::Request
lib/dexpace/http/request/builder.rb         Dexpace::Request::Builder
lib/dexpace/http/response.rb                Dexpace::Response
lib/dexpace/http/response/builder.rb        Dexpace::Response::Builder
```

Twenty-two new `lib/` files, twenty-two `sig/` mirrors, twenty-two `test/` mirrors, plus the three
already-existing files each gains content: `lib/dexpace.rb`, `sig/dexpace.rbs` and
`test/fixtures/surface/dexpace-core.txt` at the repository root.

**Public constants are flat; directories are file organisation, not namespace.** `Dexpace::Request`
is defined in `lib/dexpace/http/request.rb`, not `Dexpace::HTTP::Request`. Design §2.3 puts these
files under `lib/dexpace/http/`; design §3.2, §3.7 and §5 name the constants themselves
`Dexpace::Response` and `Dexpace::RequestOptions`, with no `HTTP::` segment, and later phases are
written against those names. Styleguide `module-organization/7d1041eb` asks for exactly this —
"re-export the public contract from the gem's top-level namespace (`Commerce::Order` rather than
`Commerce::Checkout::Order`)" — and this port satisfies it by *defining* the constant there rather
than by aliasing, because an alias would put two names for one class into both the RBS tree and
the `NFR-4` runtime surface manifest, which are diffed. The casualty is
`module-organization/3ff5433e`'s filename↔constant-path mapping, whose stated motivation is
Zeitwerk; Zeitwerk is off here (`module-organization/bf6411ad`), `lib/dexpace.rb` requires every
file explicitly, and nothing mechanical depends on the mapping. Recorded as note and as Deviation
Ledger row P1-1. **This fixes the naming convention for every later phase**: a subsystem whose
design names it with a namespace (`Dexpace::IO::Buffer`, `Dexpace::Serde::…`,
`Dexpace::Instrumentation::…`, `Dexpace::Outcome::Success`) keeps it; the wire model and the error
types are flat.

`Dexpace::Headers::Builder` *is* nested, and lives in its own file at the mirrored path, because a
builder belongs to its model and `module-organization/1828a984` allows one public constant per
file with no exception for a second one.

---

## Error root and the validation type (`error.rb`, `error/invalid_argument_error.rb`)

**Satisfies:** `HTTP-4`, `HTTP-47`, `SEAM-29`'s message form. **Design:** §5's error root; §4's
field-named validation. **Corpus:** `error-handling/51261878`, `/75571c73`, `/5a185ba9`,
`/ffdf6f4f`, `/f511eaba`, `/61ab4fb6`.

**`Dexpace::Error` is a module, included by every core error class.** Design §5 names it "core's
error root" and gives it a `#suppressed` array and an overridden `#full_message`; it does not say
whether it is a class, and the choice cannot be deferred past the phase that creates it.
`XCUT-4` (MUST) requires transport errors to "belong to the runtime's I/O-error family so existing
I/O catch sites keep matching", which in Ruby means `Dexpace::TransportError < ::IOError`; Ruby has
single inheritance, so a class root would make that requirement unsatisfiable in phase 8 without a
second, competing root. A module root satisfies both: `rescue Dexpace::Error` works because
`rescue` matches with `Module#===`, which is `is_a?`, and an included module answers it.

Phase 1's only concrete error is **`Dexpace::InvalidArgumentError < ::ArgumentError`, including
`Dexpace::Error`**. Subclassing Ruby's own is what `error-handling/5a185ba9` asks for ("prefer a
standard-library exception where one exactly fits") and what `/ffdf6f4f` describes ("`ArgumentError`
signals caller mistakes; raise it from validation helpers"), and it is literally what `HTTP-47`
asks for: "fail with an argument error carrying the offending input". **`Dexpace::ArgumentError`
is never defined**, in this phase or any later one: it would shadow `::ArgumentError` for every
file inside `module Dexpace`, so a bare `rescue ArgumentError` written anywhere in core would
silently stop catching Ruby's own — the same class of trap as `Dexpace::Serde::JSON` shadowing
`::JSON`, but silent rather than loud.

`Dexpace::Error` carries no behaviour in phase 1. Design §5's `#suppressed`, `#full_message` and
`Dexpace.attach_suppressed` arrive with the recovery chain that needs them, in phase 4 — deferred
as `DEF-24`, so the module's shape is fixed here and its content is not invented ahead of its
first caller. Recorded as Deviation Ledger rows P1-2 and P1-3 and as a one-line **Design §5
addendum** below, so phases 2, 4 and 8 inherit the shape rather than re-deciding it.

## The shared construction helper (`lib/dexpace/model.rb`)

**Satisfies:** `HTTP-1`, `HTTP-2`, `HTTP-3`, `HTTP-4`, `HTTP-5`, `SEAM-29`, `XCUT-15`.
**Design:** §4 in full. **Corpus:** `data-modeling/0b772c5f`, `/9218f17f`, `/817430c4`,
`/1d3d3827`, `notes/assertions.md`.

One module, `Dexpace::Model`, included by every value type in this gem and every later one. It is
small on purpose — four methods — and it is where the whole construction pattern is enforced once
instead of remembered twenty-two times:

- **`Model.required!(name, value)`** — the shared validation helper. Raises
  `Dexpace::InvalidArgumentError` with the message `"<name> is required"` and nothing else, which
  is the exact form `SEAM-29` fixes and the field-named failure `HTTP-4` requires. It is the
  production assertion primitive `docs/knowledge/notes/assertions.md` names; there is no second
  way to raise this class of failure.
- **`#with(**changes)`** — overrides `Data#with` and routes through the type's own `.build`, so
  derivation re-validates on **every** supported Ruby. Returns `self` when `changes` is empty.
  This is finding 1 above, closed in one place; a type that includes `Model` cannot forget it, and
  a later phase adding a `Data` type gets it by inclusion rather than by reading this document.
- **`Model.own(collection)`** — `Ractor.make_shareable(collection, copy: true)`, which deep-copies
  and then deep-freezes and returns the copy, leaving the caller's object and every object nested
  inside it untouched. The `copy: true` half is not optional and is the reason this is a named
  helper: `make_shareable` freezes **in place** (design §4's verified caveat), and a plain
  `collection.dup` is shallow, so `make_shareable(hash.dup)` would still freeze the caller's live
  value arrays. Verified on 3.2.11 and 4.0.6: with `copy: true` the source hash, its arrays and
  their strings are all still unfrozen afterwards and the returned copy is `Ractor.shareable?`.
  This one step is what satisfies `HTTP-5` with no per-access wrapper and makes every
  collection-holding model Ractor-shareable as a free side effect, with `Ractor` load-bearing for
  nothing. It stops at `Request` and `Response`, which hold a `URI::Generic` — see P1-9.
- **`Model.frozen_string(value)`** — `dup.freeze` for a caller-supplied `String` member, because a
  `String` a caller keeps a reference to is externally mutable state `XCUT-15` forbids a model
  from aliasing.

Value types get `private_class_method :new` plus a public validating `.build(**members)`; `.parse`
and `.of` are conveniences over `.build`. Builder-based models get the same `.build` on their
`Builder`. Neither hole in `HTTP-2` is closed and neither is hidden — see Testing.

**No `.build` is a bare `new` wrapper.** This is the phase's construction rule and it binds every
later phase's models too. Validation lives in the type's `initialize` override (or in `.build`
before `new`), never only in a `Builder`, for three reasons that are each independently sufficient:
`.build` is public API a fixture or a later phase can call directly; `#with` routes **every**
derivation back through `.build`, so a rule the builder alone enforced is a rule `#with` walks
around; and `send(:new, …)` reaches the generated constructor whatever anyone writes (`HTTP-2`'s
admitted gap, §10.10). The Builders carry exactly the rules that are about a field nobody set —
`HTTP-8`'s method defaulting is the only one in this phase — because a model that already has the
field cannot express them.

**A validating constructor coerces as well as checks.** Where a member has a type with a
`parse`/`of` factory, the model's `initialize` runs the value through it rather than trusting the
caller: `Request` coerces `method` through `Method.of` and `url` through `URL.parse!`, and
`Response` coerces `protocol` through `Protocol.parse` and `status` through `Status.of`. Otherwise
`Request.build(method: "GET", …)` would hold a `String` that behaves like a `Method` until the
first `#body_forbidden?` call — and `.build` is public API, so that is a caller a builder never
sees. Every one of those factories is idempotent on its own type, so a builder that already
constructed the value pays nothing. Members with no factory are type-checked instead (`headers`
must be a `Headers`, `request` a `Request`).

Applied per type, this is what each one validates at construction: `HeaderName` re-runs
`HTTP-17` and re-derives the fold; `Headers` re-runs `HTTP-17`/`HTTP-18`/`HTTP-19` over every
stored name and value; `Status` requires an `Integer` in 100–599 (`HTTP-10`); `Method` requires a
tchar token (`HTTP-9`); `Protocol` requires a canonical wire form (`HTTP-33`); `MediaType` requires
a folded, token-shaped, header-safe type/subtype and parameter set (`HTTP-23`, `HTTP-26`,
`HTTP-53`); `Query` requires a list of `[String, String]` pairs (`HTTP-28`); `RequestOptions`
re-runs `HTTP-35`'s two rejections; `Request` requires method, URL and headers and re-runs
`HTTP-7`'s body rule; `Response` requires request, protocol, status and headers (`HTTP-4`).
`URL`, `PercentEncoding` and `HeaderSyntax` are modules of functions with no constructor to
protect. The gap this closes is not hypothetical: `HeaderName.of("Accept").with(original:
"a\r\nb")` succeeds against a `.build` that only wraps `new`, and puts a CRLF on the wire.

## The shared builder contract (`lib/dexpace/builder.rb`)

**Satisfies:** `SEAM-29`'s second MUST. **Spec:** ch.03 §3.8 — "A shared generic Builder contract
(`build()` producing the target type) MUST exist so generic composition helpers can accept any
builder", with the conformance step "a builder is assignable where the generic Builder contract is
expected".

`SEAM-29` carries two MUSTs and the uniform `<name> is required` message is only the first. The
second asks for a contract, and in Ruby it has two halves because assignability and runtime
identity are different things: the RBS interface `Dexpace::_Builder[T]` is what a consumer's own
`steep check` sees at a helper's parameter, and the module `Dexpace::Builder` is what a helper can
ask at runtime. Every `Builder` class in this phase includes it — `Headers`, `Query`,
`RequestOptions`, `Request`, `Response` — and `Dexpace::Builder.build_all(builders)` is the generic
composition helper the requirement exists for, refusing an object that never opted in.

`#build` on the module itself raises `NotImplementedError`, which is a `ScriptError` and therefore
deliberately outside `StandardError`: a builder class that forgot to implement it is a programmer
error and must not be swallowed by an ordinary `rescue`.

Phase 1 lands this rather than phase 2 because the roadmap's phase-1 row says `SEAM-29`'s
construction contract is honoured here, and because a contract introduced after five builders exist
is a contract retrofitted onto five classes instead of shaping them.

## Header syntax (`lib/dexpace/http/header_syntax.rb`)

**Satisfies:** `HTTP-17`, `HTTP-18`, `HTTP-19`, `HTTP-20`, and `XCUT-18` for phase 9.
**Design:** §4's header section; §10.10's "the mitigation that matters".

A module of pure functions, and **the public entry point every transport adapter calls again
immediately before dispatch** (phase 8, `DEF-25`). It is public API in the full sense — YARD, RBS,
surface manifest — precisely because a phase-8 adapter is a different gem and must be able to
reach it.

- `.trim(name)` — removes leading and trailing **SP (0x20) and HTAB (0x09) only**, operating on
  `name.b`. Not `String#strip`: finding 2 above. Trimming CR or LF would let `"a\r\n"` become `"a"`
  and defeat `HTTP-17`; stripping NUL would do the same for `"a\0"`.
- `.valid_name?(name)` / `.validate_name!(name)` — after trimming, reject empty, and reject any
  byte below 0x21, equal to 0x7F, or ≥ 0x80. That single range covers `HTTP-17`'s C0 controls,
  DEL, non-ASCII, and — because SP and HTAB are below 0x21 — an interior space, which no header
  name may contain.
- `.validate_outbound_value!(value, name:)` — `HTTP-18`: accept HTAB plus 0x20–0x7E, reject
  everything else including every byte ≥ 0x80.
- `.validate_inbound_value!(value, name:)` — `HTTP-19`: accept HTAB and everything ≥ 0x20 except
  DEL, so obs-text passes and C0/DEL do not. Inbound *names* go through `.validate_name!`
  unchanged, which is what `HTTP-19` requires.
- `.escape(name)` — `HTTP-20`'s echo rule: renders a name's control bytes as `\xNN` escapes for an
  error message. **A rejected value never appears in a message at all**, in any form; the message
  names the header and the reason.

Every predicate reads `value.b.each_byte`. Finding 3 is why: a `String` carrying invalid UTF-8 is
exactly the input this module exists to reject, and a character-oriented implementation raises
`ArgumentError` from deep inside a regexp engine instead of returning `false`.

## HeaderName (`lib/dexpace/http/header_name.rb`)

**Satisfies:** `HTTP-21`, `HTTP-13`. **Deferred:** `HTTP-22` (`DEF-2`).

`Data.define(:original, :folded)` with `private_class_method :new`, a `.build(original:,
folded: nil)` whose `initialize` override trims, validates through `HeaderSyntax` and **re-derives**
the fold rather than trusting the one it was handed, and `HeaderName.of(string)` over it. Deriving
is what makes `#with(original: "CONTENT-TYPE")` fold correctly and `#with(original: "a\r\nb")`
raise. The fold uses **`downcase` and no arguments**
(`Dexpace/NoLocaleCaseFold` enforces the "no arguments" half repository-wide). Equality and hash
come from the members — and because `folded` is derived from `original`, two instances differing
only in casing are *not* equal by the generated comparison, so `#==`, `#eql?` and `#hash` are
overridden to compare `folded` alone, with a why-comment citing `HTTP-21` and
`api-design/e4fa3438`'s permission to override a generated protocol method deliberately.
`#to_s` returns the original casing for wire emission. Interoperation with the string-keyed API is
the `Headers` side's job: every `Headers` method accepts a `String` or a `HeaderName`.

## Headers (`lib/dexpace/http/headers.rb`, `lib/dexpace/http/headers/builder.rb`)

**Satisfies:** `HTTP-13`–`HTTP-21`, and `HTTP-3`/`HTTP-4`/`HTTP-5` for this model.
**Design:** §4 — "two parallel frozen hashes".

`Data.define(:values, :casing, :direction)`: `values` maps folded name → frozen `Array` of frozen
value strings; `casing` maps folded name → the original casing for emission (`HTTP-21`); and
`direction` is `:outbound` or `:inbound`. Both hashes are deep-frozen once at construction through
`Model.own`, and **both member readers are private** — the model's public surface is the accessors
below, not its internals. Ruby's insertion-ordered `Hash` gives `HTTP-16` at no cost.

**`direction` is a member, not a builder-only flag.** `HTTP-19`'s lenient inbound grammar is a
property of the collection, not of the object that happened to assemble it: if the builder alone
knew, `#new_builder` on a response's headers would hand back a strict builder that rejects the
obs-text the model it came from already holds. Carrying it means `Headers.inbound_builder` and
`#new_builder` agree, and a transport cannot accidentally get the strict path and drop a legitimate
Latin-1 `Content-Disposition`.

**`HTTP-5` has two tiers, and appendix C states them explicitly:** "Name-set and entry-set
accessors return a fresh per-call snapshot; per-name value-list accessors return the instance's own
list." So `#names` and `#entries` allocate and freeze a snapshot on every call, while `#[]` returns
the model's own frozen value list. Design §4's summary — "the same frozen reference is returned
from every accessor" — describes the second tier only, and where the two disagree the normative
text wins (Deviation Ledger P1-7). Both halves are asserted, so a later "optimisation" cannot
quietly collapse them into one behaviour.

Public surface: `.build(values:, casing:, direction: :outbound)`, `Headers.builder`,
`Headers.inbound_builder`, `Headers::EMPTY`, `#[](name)` → the model's own frozen `Array[String]`
or `nil`, `#include?(name)`, `#names` → a fresh frozen `Array[String]` in insertion order with
original casing, `#entries` → a fresh frozen array of frozen `[name, value]` pairs, `#each_entry`,
`#size`, `#empty?`, `#direction`, `#new_builder`.

**Equality is by folded name and value only.** `HTTP-13` requires the fold to govern "storage,
lookup, containment, mutation, removal, equality, and hashing", so two collections differing only
in the casing they will emit — or in the direction that validated them — are the same headers.
`Data` would generate equality over all three members and get that wrong, so `#==`/`#eql?`/`#hash`
are overridden over `values` alone, with the why-comment `api-design/e4fa3438` requires.

The two hashes are one collection seen twice, so the construction check is a **set equality** in
both directions: a value list with no casing entry cannot be emitted, and a casing entry with no
value list would make `#names` report a header that `#size` and `#[]` do not have.

`Headers::Builder` selects `HeaderSyntax.validate_outbound_value!` or `…inbound_value!` from its
`direction`, and **validates before it records**: recording the original casing first would leave an
orphan entry behind when the value is rejected, and `#names` would then report a header the model
does not carry. Builder methods: `#add(name, value)` (appends, `HTTP-14`), `#set(name, value)`
(replaces the whole list; **`nil` removes the header entirely**, `HTTP-15`), `#remove(name)`,
`#build`.

`#new_builder` `dup`s every value list rather than aliasing it and carries the direction (`HTTP-3`),
which is what makes the conformance sequence — derive, mutate the builder, build a second instance,
assert the first unchanged — pass rather than merely appear to.

## Status (`lib/dexpace/http/status.rb`)

**Satisfies:** `HTTP-10`, `HTTP-11`, `HTTP-12`. **Design:** §4's status paragraph.

`Data.define(:code)` — **one member, deliberately**. `HTTP-12` requires two `Status` values to be
equal iff their codes are equal with the name not participating, and a `Data.define(:code, :name)`
would generate equality over both members and violate it silently. The canonical name is looked up
from a frozen table instead: `Status.canonical_name(code)` returns the name or `nil`, which is
`HTTP-10`'s "separate lookup MUST let callers distinguish recognized codes".

`Status.of(code)` is total over any `Integer` and never raises for an unrecognised code
(`HTTP-10`); it raises `Dexpace::InvalidArgumentError` only for a non-`Integer` or a code outside
100–599, which is a caller mistake rather than a vendor code. Range classification is derived, not
stored: `#informational?`, `#success?`, `#redirect?`, `#client_error?`, `#server_error?` and
`#error?` (400–599), per `HTTP-11`. Named constants for the recognised codes — `Status::OK`,
`Status::NOT_FOUND` and the rest — come from the same frozen table, so `Status.of(200)` equals
`Status::OK` and both hash identically.

## Method (`lib/dexpace/http/method.rb`)

**Satisfies:** `HTTP-9`, and supplies `HTTP-7`'s classification.

`Data.define(:token)`. `Method.of(name)` upcases with `upcase` and no arguments and validates the
RFC 7230 token grammar, so an extension method is representable; each method's canonical wire token
equals its uppercase name by construction, which is `HTTP-9`'s second clause satisfied structurally
rather than by a table.

`Dexpace::Method` shadows `::Method` inside `module Dexpace` — the hazard phase 0 recorded for
`Dexpace::Serde::JSON` and `Dexpace::Async::Thread`, and the reason core writes `::Method` when it
means Ruby's. Verified inert outside core: a consumer's top-level `Method` still resolves to
Ruby's even after `include Dexpace`, because `Object`'s own constants win over an included
module's.

**`Method::IDEMPOTENT` is the single source `HTTP-9` demands** — the frozen set
`{GET, HEAD, OPTIONS, PUT, DELETE}` — exposed as `#idempotent?`. Phase 6's configurable retry
allow-list and its inherent replay-safety gate both derive from it and neither re-states it
(`retry-and-resilience/a742b808`). `Method::BODY_FORBIDDEN` is the second frozen set,
`{GET, HEAD, TRACE, CONNECT}`, exposed as `#body_forbidden?`; `HTTP-7` is enforced in
`Request::Builder#build` by asking the method, not by re-listing the four names there.

## Protocol (`lib/dexpace/http/protocol.rb`)

**Satisfies:** `HTTP-33`.

`Data.define(:wire)` over the canonical lower-case forms `http/1.1` and `http/2`, with
`Protocol.parse(text)` accepting those plus the aliases `HTTP/2` and `HTTP/2.0` case-insensitively
— `downcase` with no arguments, so "locale-invariant" is enforced by the cop rather than asserted —
and raising `Dexpace::InvalidArgumentError` naming the offending input for anything else.
`Protocol::HTTP_1_1` and `Protocol::HTTP_2` are the frozen instances.

## MediaType (`lib/dexpace/http/media_type.rb`)

**Satisfies:** `HTTP-23`, `HTTP-24`, `HTTP-25`, `HTTP-26`, `HTTP-27`, `HTTP-53`.
**Design:** §4's media-type paragraph — "Ruby ships nothing that does this".

`Data.define(:type, :subtype, :parameters)`, with `type` and `subtype` and every parameter **key**
lower-cased at construction and every parameter **value**'s case preserved (`HTTP-23`); equality
therefore falls out of the members, case-insensitive where the folding already happened and
case-sensitive on values.

A hand-written parser, because no stdlib function splits parameters respecting quoted strings:
`MediaType.parse(text)` splits on `;` outside quotes, splits each parameter on its **first** `=`
only, strips quotes and unescapes quoted-pairs (`HTTP-25`); rejects blank input, a missing or
empty type or subtype, more than one `/`, and a parameter with no `=` or an empty key or value
(`HTTP-53`); and rejects any C0-except-HTAB, DEL or non-ASCII byte anywhere **using
`HeaderSyntax`'s outbound-value predicate**, not a second copy of it, so `HTTP-26`'s "the same
predicate" is a shared function rather than a claim. `#render` emits a value bare when it is a
valid token and quoted-and-escaped otherwise, so `parse(render(x)) == x` — a property test, not an
example.

`#charset` resolves the `charset` parameter case-insensitively and returns `nil` when absent or
unrecognised, never raising (`HTTP-24`); the `nil` is documented at the accessor as
`type-system/b5166811` requires. `#matches?(other)` implements `HTTP-27`: a wildcard type is
permitted only with a wildcard subtype, a wildcard in either position matches any value, and
parameters are ignored.

Both regexps this file needs are built with `Regexp.new(source, timeout: …)` — per-pattern, never
the process-global `Regexp.timeout`, because a library must not impose a regexp budget on its host
(design §4, §6.3). Verified available on 3.2.11.

## PercentEncoding (`lib/dexpace/http/percent_encoding.rb`)

**Satisfies:** `HTTP-29`, `HTTP-31`, `HTTP-32`. **Design:** §3.5's component encoder, verified
three ways (P13).

Two functions and a hard rule that they are never confused with form encoding:

- **`.encode_component(text)`** — the strict RFC 3986 component encoder. The unreserved set is
  exactly `A-Za-z0-9-._~`; **every** other byte is percent-encoded uppercase. Verified against
  §3.5's own probe input: `a b*~+/!()'` → `a%20b%2A~%2B%2F%21%28%29%27`, which is space → `%20`,
  `*` → `%2A`, `+` → `%2B`, `/` → `%2F` and `~` untouched — `HTTP-29` and `HTTP-32` exactly, and
  what none of `URI.encode_www_form_component`, `CGI.escape` or `URI::RFC3986_PARSER.escape`
  produces.
- **`.decode_component(text)`** — lenient and total, per `HTTP-31`: a malformed escape falls back
  to the raw text rather than raising, and `+` decodes to `+` rather than to a space (`HTTP-32`).

Both read bytes. The encoder consumes `text.b`, so a value carrying invalid UTF-8 round-trips
byte-exactly instead of raising; the decoder accumulates into a BINARY buffer and retags the
result UTF-8 at the end, which is `io-and-byte-streams/0a4773a6`'s "`force_encoding` is a retag
used only where the bytes are known to conform" applied honestly — the bytes came from a
percent-decoding whose output is whatever the sender sent, so the retag is a label and every
comparison downstream is byte-wise.

**The form encoder that `HTTP-38`/`BODY-35` needs is not here and is not this.** It is `+`-for-space
and never claimed RFC 3986 compliant; it lands in phase 3 as a different function with a different
name and different tests (§3.5: "they are never interchanged").

## Query (`lib/dexpace/http/query.rb`, `lib/dexpace/http/query/builder.rb`)

**Satisfies:** `HTTP-28`–`HTTP-32`, and `HTTP-3`/`HTTP-5` for this model.

`Data.define(:pairs)` over a frozen `Array` of frozen `[name, value]` pairs — **a list, not a
`Hash`**, because `HTTP-28` needs multiple values per name with insertion order preserved *and* a
value-less parameter modelled as a single empty-string value distinct from an absent name, which a
`Hash` cannot express. Names are case-sensitive: no folding anywhere in this file.

`#encode` renders each pair through `PercentEncoding.encode_component`, emits a repeated name once
per value, omits the leading `?` and returns `""` when empty (`HTTP-29`). `Query.parse(text)`
inverts it leniently (`HTTP-31`): `nil` or blank → empty, a leading `?` tolerated, a segment with
no `=` or a trailing `=` → empty-string value, a stray `&` skipped, a malformed escape kept raw.
Equality is order-sensitive and, because the pairs list *is* the encoding's input, two instances
are equal exactly when they encode identically (`HTTP-30`).

`HTTP-5`'s two tiers apply here as they do to `Headers`: `#names` and `#entries` return a fresh
frozen snapshot per call, and the `pairs` member's generated reader is **private** so the entry set
has exactly one public accessor. `#[]` has no stored per-name list to hand back — the model is a
pair list — so it allocates one and freezes it, which satisfies the requirement's MUST by the
stricter route.

`Query::Builder#add(name, value)` maps a `nil` value to `""` (`HTTP-28`'s `?flag`), and `#build`
**drops any name whose value list is empty** so it cannot leave a phantom `contains`-true entry
invisible to `#encode` (`HTTP-30`).

## URL (`lib/dexpace/http/url.rb`)

**Satisfies:** `HTTP-46`, `HTTP-47`. **Design:** §3.5's parser pin.

A module of two functions, not a value type — the parsed URL is a `URI::Generic` and wrapping it
would add a type every later phase has to unwrap:

- **`.parse!(input)`** — parses with `URI::RFC3986_PARSER` explicitly, **never** `URI.parse` or
  `URI::DEFAULT_PARSER` (`Dexpace/NoUriDefaultParser` fails the build on either), rejects a
  non-absolute URI, and converts `URI::InvalidURIError` into a `Dexpace::InvalidArgumentError`
  whose message carries the offending input — `HTTP-47`'s "argument error carrying the offending
  input", with the input echoed because it is a URL the caller just supplied, not a header value
  `HTTP-20` protects.
- **`.external_form(uri)`** — the textual form `HTTP-46` compares by.

Requiring `"uri"` is phase 1's only `require` outside `require_relative`, and `uri` is on phase 0's
allowlist.

## RequestOptions (`lib/dexpace/http/request_options.rb`, `…/request_options/builder.rb`)

**Satisfies:** `HTTP-34`, `HTTP-35`, and `HTTP-3`/`HTTP-5` for this model.

`Data.define(:timeout, :max_retries, :tags)`, every field defaulting to the `nil` "use the default"
sentinel, `tags` a frozen `Hash` of `String` → `String` deep-frozen through `Model.own` (`HTTP-34`'s
"defensively copied at build"), and a canonical frozen `RequestOptions::EMPTY` so "override
nothing" allocates nothing per call. `timeout` is a `Float` of seconds — matching every Ruby socket
API, so no unit conversion sits between the model and the wire (design §4).

`HTTP-35`'s two rejections live in the **model's** `initialize`, not in the builder: a non-`nil`
timeout that is zero or negative and a negative `max_retries` are refused, while `0` for
`max_retries` is **accepted** and means "disable retries for this call". Putting them in the model
is the phase's construction rule — `.build` is public and `#with` routes through it, so
`options.with(timeout: -1)` must fail exactly where `builder.build` would. These are operational
knobs and are deliberately outside the wire model (`HTTP-6`), which is why they are a separate type
rather than members of `Request`.

## Request (`lib/dexpace/http/request.rb`, `lib/dexpace/http/request/builder.rb`)

**Satisfies:** `HTTP-3`–`HTTP-9`, `HTTP-46`, `HTTP-47`, and `HTTP-1`/`HTTP-2` by construction.

`Data.define(:method, :url, :headers, :body)` — exactly `HTTP-6`'s four members and nothing more.
`url` is the frozen `URI::Generic` that `URL.parse!` returned; `headers` is a `Headers`, never
`nil` and possibly empty; `body` is optional.

The cross-field validation design §4 keeps a real builder for lives in two places, and the split is
the phase's construction rule:

- **In the model**, so `.build`, `#with` and a forged `send(:new, …)` all meet it: `method`, `url`
  and `headers` are required (`HTTP-4`), and a body on a method whose classification forbids one is
  rejected by asking `Method#body_forbidden?` (`HTTP-7`). The spec's rationale for `HTTP-7` is that
  reference transports diverge — one throws, one silently drops the body — so rejecting once yields
  one portable behaviour; a GET that acquired a body through `#with` would reopen exactly that.
- **In the builder only**, because it is a rule about a field nobody set: no method and no body →
  GET; a body with no method → an error naming the **missing method**, never a default-then-reject
  (`HTTP-8`). `url` missing surfaces here too, through `URL.parse!`, so the message is
  `url is required` (`HTTP-4`, `HTTP-47`).

`#==` and `#hash` are overridden with a why-comment: `HTTP-46` requires URL comparison by **textual
external form** with no blocking work and no name resolution, and `Data`'s generated equality would
compare `URI::Generic` objects by their own normalising rules. Comparing `URL.external_form(url)`
plus method, headers and body by value is the requirement stated literally. Ruby's `URI` performs
no DNS, so the "no blocking work" half is structural — and the test asserts it rather than assuming
it.

**`body` is opaque in phase 1.** The `BODY` model is phase 3's; here the member is carried,
`HTTP-7`'s presence check is the only thing asked of it, and its RBS type is `untyped` with a YARD
note. Deferred as `DEF-26`, which is also where `HTTP-46`'s "body by value" becomes testable
against a real body type.

## Response (`lib/dexpace/http/response.rb`, `lib/dexpace/http/response/builder.rb`)

**Satisfies:** `HTTP-3`–`HTTP-6`, `HTTP-11`.

`Data.define(:request, :protocol, :status, :reason, :headers, :body)` — `HTTP-6`'s six members.
The model's `initialize` requires `request`, `protocol`, `status` and `headers` through
`Model.required!`, in the order the requirement lists them, so a missing one fails with
`status is required` and names the field (`HTTP-4`) whether it was reached through `.build`,
through `#with` or through the builder. `reason` and `body` are optional, and the builder defaults
`headers` to `Headers::EMPTY`.

`HTTP-11`'s "a response MUST expose these derived from its status" is six one-line delegations to
`Status`, not a second copy of the ranges.

`Response#close` and the body lifecycle (`HTTP-41`, `HTTP-43`) are phase 3's and are absent here
rather than stubbed.

## Entry point and the public surface (`lib/dexpace.rb`, `sig/**`, the surface manifest)

**Satisfies:** `NFR-3`, `NFR-4`, `NFR-11` — all dispositioned by phase 9, all mechanised by phase 0
and load-bearing here for the first time.

`lib/dexpace.rb` gains one `require_relative` per file above, in dependency order, and nothing else:
no autoloader (`SEAM-1`), no load-time side effect beyond defining constants. Every file gets an
RBS mirror in the same change — `sig/` is not a follow-up task, because a signature written later
is a signature written from the code instead of from the contract.

Two artifacts are regenerated deliberately, in the phase's last task and never to silence a
failure: `test/fixtures/surface/dexpace-core.txt` via `bundle exec rake surface:regenerate`, and
the RBS baseline `gates:sig_diff` compares (which still prints "no release tag yet" — phase 0's
P0-8 branch — because no `v*` tag exists). `gates:rbs_surface` passes unchanged: the only foreign
constant phase 1's signatures name is `URI::Generic`, and the allowlist matches on the first
segment, `URI`, which phase 0 already permits.

## Testing

`test/` mirrors `lib/` one file per file; each file's header comment names the requirement IDs it
exercises, and a non-obvious branch names the ID that forced it. Every suite subclasses
`DexpaceTestCase`, so a warning raised by code under test fails the test that triggered it.

**Per-ID placement.** Every one of the 39 in-scope IDs is exercised in the test file mirroring the
component that owns it, and the checklist written at execution time names the plan task, not this
document. Four IDs are exercised in more than one file by nature: `HTTP-3` and `HTTP-5` in all five
builder-based models' tests, `HTTP-4` in all of them plus `model_test.rb`, and `HTTP-17`/`HTTP-18`
in both `header_syntax_test.rb` (the predicate) and `headers_test.rb` (the model that calls it).

**The encoding tests**, which are the ones a reader would otherwise write wrong:

| Case | Asserted |
|---|---|
| `"a\0"` as a header name | rejected — the NUL survives trimming, because trimming is SP/HTAB only |
| `"a\r"`, `"a\r\nb"` as names and as values | rejected; the CR is never trimmed away first |
| `"h\xE9der"` (invalid UTF-8) as a name | rejected with `Dexpace::InvalidArgumentError`, **not** `ArgumentError: invalid byte sequence in UTF-8` from a regexp engine |
| `"  X-Trace  "` | accepted, stored as `X-Trace` (`HTTP-17`'s own conformance example) |
| `"v\xC3\xA5lue"` as an outbound value / as an inbound value | rejected / accepted (`HTTP-18` vs `HTTP-19`) |
| `"a\tb"` as a value | accepted, both directions |
| `a b*~+/!()'` through `encode_component` | `a%20b%2A~%2B%2F%21%28%29%27`, byte for byte |
| `%FF` through decode then encode | round-trips to `%FF` — the invalid-UTF-8 path through the codec |
| a rejected value's text | never appears in the exception message (`HTTP-20`); a rejected name's control bytes appear escaped |

**The immutability and aliasing tests `HTTP-3` and `HTTP-5` need**, one per builder-based model:
derive a builder with `#new_builder`, mutate it, build a second instance, assert the first is
unchanged; hold a reference to a value list obtained from an accessor, mutate the source builder,
assert the snapshot is unchanged; assert every returned collection is `frozen?` and that mutating
it raises `FrozenError`; pass a live `Hash` into `.build`, mutate the caller's copy afterwards, and
assert the model did not change (`XCUT-15`); and assert `Ractor.shareable?` on a built model, which
is the one-line proof that the deep freeze actually reached every nested collection — for every
model **except `Request` and `Response`**, where the assertion is inverted and carries its reason:
a `URI::Generic`'s `freeze` is shallow, so a request holding one is frozen and still not
shareable, and the only way to change that would deep-freeze `URI::RFC3986_PARSER` in place
(Deviation Ledger P1-9). `HTTP-5`'s two
tiers are asserted separately and in opposite directions — `refute_same` on two calls to `#names`
and `#entries`, `assert_same` on two calls to `#[]` — because a single "it is frozen" test would
pass over either behaviour.

**Three tests exist because `.build` is public.** `Headers.build` is given a CRLF name, a CRLF
value, and a stored name with no matching original casing; each must raise. They are not
redundant with the builder's own negative tests: they are the proof that the validation lives in
the model, where `#with` and `send(:new, …)` also have to meet it.

**Two tests cover the header direction** (`HTTP-19`): an inbound-built model's `#new_builder`
carries `:inbound` and still accepts obs-text, and an outbound one still refuses it. Without the
`direction` member both pass for the wrong reason.

**The `#with` test runs on every interpreter in the matrix.** One test per value type asserts that
`instance.with(member: <invalid>)` raises. On 3.4 and 4.0 it would pass even without the shared
override; on 3.2 it fails without it. CI's `test:gems` job already runs the real suite on
3.2/3.3/3.4/4.0, which is what makes this a standing check rather than a one-off measurement;
locally it is `mise exec ruby@3.2.11 -- bundle exec rake test:gems`.

**Property tests, bounded**, because `testing/f36a19cd` makes them mandatory for parsers, codecs
and value objects with parse-constructor invariants, and phase 0 shipped `#sample(count:, seed:)`
for exactly this: `MediaType.parse(render(x)) == x`; `Query.parse(q.encode) == q`;
`decode_component(encode_component(s)) == s` over generated byte strings including invalid UTF-8;
`Status.of(code)` total over 100–599; `HeaderName.of(s).folded` stable under re-folding.

**The `HTTP-2` negative proof, which is not faked.** Design §10.10 and §11.6 admit two holes.
**One is asserted**: a test proves `Request.send(:new, …)` reaches the generated constructor and
produces an instance that never met a builder, with a comment naming `HTTP-2`, §10.10 and the
mitigation — `HeaderSyntax` re-validation at the wire boundary, phase 8, `DEF-25` — so a later
reader cannot mistake the gap for an oversight or the mitigation for a closure. A test asserting
that path is blocked would be a lie that passes. **The other is stated, not tested**: that any
object responding to `#method`, `#url`, `#headers` and `#body` duck-types past the builder is a
property of Ruby, and an assertion that a four-reader `Struct` responds to four readers restates
the language rather than checking this SDK. It lives in the `Request` YARD block and in §10.10,
where a reader will actually meet it.

**Visibility is asserted with `respond_to?`, never with `assert_predicate`, because Minitest sends
past `private`.** Verified against Minitest 5.25.1 on Ruby 3.2.11 and 6.0.0 on 4.0.6:
`assert_predicate(obj, :flagged?)` calls `__send__` and passes on a **private** predicate on both,
and `refute_predicate` catches it on 6.0.0 only — so on the declared floor a predicate suite is
blind to visibility. That matters here because `Method#idempotent?` and `#body_forbidden?` are
asked by receiver from `Request`, one task later: a misplaced `private` would break that task
while `Method`'s own suite stayed green on 3.2.

**Every `Data` type gets a `#with` rejection test.** `.build` validates, so `#with` — which routes
through it — must reject what `.build` rejects: a CRLF `HeaderName`, a `nil` `Status` code, a
`Method` token with a space, an unknown `Protocol` wire form, an unfolded `MediaType` type, a
non-positive `RequestOptions` timeout, and a body added to a GET `Request`. These are the tests
that would have caught a `.build` that merely wrapped `new`, which is the failure this phase's
construction rule exists to prevent.

**The builder contract has its own suite** (`SEAM-29`): a generic helper accepts all five builders
and returns their five model classes, a builder that forgot `#build` raises `NotImplementedError`,
and an object that never included the module is refused. That list of five *is* the requirement's
conformance step.

**Error-boundary pairing** (`testing/62f8f4ec`): every validation rejection is tested for the
exception class, for a message that identifies the violating field or header, and for no partial
side effect — the builder is still usable after a rejected `#add`.

**Two tests exist for the error module's shape**, because it is what phases 2, 4 and 8 inherit:
`rescue Dexpace::Error` catches `Dexpace::InvalidArgumentError` through `Module#===`, and a bare
`rescue ArgumentError` written inside `module Dexpace` still catches Ruby's own — which is only
true because `Dexpace::ArgumentError` is never defined.

**The surface snapshot is regenerated once, deliberately**, in the last task, and the gate then
proves an unrecorded constant turns it red. Changing exports means regenerating both it and
`sig/`; the phase does that in one change, as `api-design/46c8b5fc` requires.

## Design §4 Addendum — what this phase adds to the design's construction pattern

Design §4 is frozen and is not edited here. Two additions, each with a Deviation Ledger row for
consolidation into design §10.

| Addendum | What §4 says | What phase 1 builds |
|---|---|---|
| **A1 — `#with` re-validates on every supported Ruby** | "`Data` also permits an `initialize` override that validates and then calls `super`" and "`MediaType`, `Status`, `Protocol`, `Method`, `HeaderName` and the conditional-request helpers are `Data` types with `parse`/`of` factories and `#with`" | `Dexpace::Model#with` overrides `Data#with` and routes through the type's validating `.build`. Verified: `Data#with` does not invoke an `initialize` override on 3.2.11, and does on 3.4.10 and 4.0.6, so the design's derivation path is unvalidated on the declared floor without this |
| **A2 — `HTTP-17`'s trim is SP and HTAB only** | §4 restates `HTTP-17` without naming a trim function | `HeaderSyntax.trim` removes SP (0x20) and HTAB (0x09) and nothing else. `String#strip` also removes NUL and other whitespace, so `"a\0"` and `"a\r"` would be laundered into acceptance by the very step that precedes the check that rejects them |

## Design §5 Addendum — the error root's shape

| Addendum | What §5 says | What phase 1 builds |
|---|---|---|
| **A3 — `Dexpace::Error` is a module** | "Core's error root `Dexpace::Error` therefore carries a `#suppressed` array … with `#full_message` overridden to render the trail" — without saying class or module | A module included by every core error class. `XCUT-4` requires transport errors to belong to Ruby's `IOError` family; single inheritance makes that impossible under a class root. `rescue Dexpace::Error` works via `Module#===`. Phases 2, 4 and 8 inherit this: `Dexpace::TransportError < ::IOError`, `Dexpace::PipelineError`, `Dexpace::ClosedError` and `Dexpace::Serde::Error` all include it |

## Deviation Ledger

Each row is consolidated into design §10 and audited by `docs/deviations.md`.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P1-1 | Public constants are **flat** (`Dexpace::Request`) while their files sit under `lib/dexpace/http/` | design §2.3 vs §3.2/§3.7/§5; `module-organization/3ff5433e` | §2.3 fixes the directory, §3/§5 fix the constant, and they disagree. The constant wins because later phases are written against it and `module-organization/7d1041eb` asks for the public contract at the top level. An alias would double every public name in both artifacts `NFR-4` diffs. The filename mapping's stated motivation is Zeitwerk, which is off |
| P1-2 | `Dexpace::Error` is a **module**, not a base exception class | design §5; `error-handling/51261878` | `XCUT-4` (MUST) puts transport errors in Ruby's `IOError` family. Single inheritance makes a class root and that requirement mutually exclusive; a module root satisfies both, and `rescue` matches modules |
| P1-3 | The validation error subclasses `::ArgumentError`; `Dexpace::ArgumentError` is never defined | `HTTP-47`; `error-handling/5a185ba9`, `/ffdf6f4f` | `HTTP-47` asks for "an argument error"; the styleguide prefers a stdlib exception where one exactly fits. The name is `InvalidArgumentError` because `Dexpace::ArgumentError` would shadow `::ArgumentError` for every file inside `module Dexpace`, silently narrowing every bare `rescue ArgumentError` in core |
| P1-4 | `#with` is overridden to route through the validating factory | design §4; `data-modeling/c4fe4732` | `Data#with` does not call an `initialize` override on Ruby 3.2 (verified against 3.2.11, 3.4.10, 4.0.6). Without the override, `HTTP-4`/`SEAM-29` validation is skipped on the declared floor and enforced everywhere else |
| P1-5 | `HTTP-17`'s "surrounding whitespace" is read as SP and HTAB only | `HTTP-17` | `String#strip` also strips NUL, so the obvious implementation accepts `"a\0"`. Trimming CR or LF would launder a header-splitting payload into a valid name |
| P1-7 | `HTTP-5` is implemented in **two tiers** — a fresh per-call snapshot for the name set and the entry set, the model's own frozen list per name — where design §4 says "the same frozen reference is returned from every accessor" | `HTTP-5`; design §4, §10.11 | Appendix C's own text splits them: "Name-set and entry-set accessors return a fresh per-call snapshot; per-name value-list accessors return the instance's own list." Design §4's sentence is a summary of the second tier, the specification is normative, and both halves are asserted so neither can be collapsed later |
| P1-8 | `Headers#==`/`#hash` compare folded names and values only; casing and direction take no part | `HTTP-13`; `api-design/e4fa3438` | `HTTP-13` puts equality and hashing under the fold. `Data` would generate equality over all three members, making `Accept` and `ACCEPT` unequal — the exact confusion the requirement exists to remove |
| P1-9 | `Request` and `Response` are frozen and deep-frozen in their collections but are **not** `Ractor.shareable?` | design §4; `data-modeling/996c0b12` | The design's "deep-freezing at construction makes the whole wire model Ractor-shareable" holds for every model whose members are strings and collections, and not for the two that hold a `URI::Generic`: verified on 3.2.11 and 4.0.6, a frozen URI is not shareable because `@host` and `@path` stay unfrozen, and `Ractor.make_shareable(uri)` reaches shareability only by deep-freezing `URI::RFC3986_PARSER` — a process-global object — in place, which is the one thing §4 says never to do. `Ractor` is load-bearing nowhere (§4, §9), so the claim is narrowed rather than the global frozen. Filed as a corpus note |
| P1-6 | `Request#==`/`#hash` override `Data`'s generated equality | `HTTP-46`; `api-design/e4fa3438` | `HTTP-46` requires comparison by textual external form; the generated equality would compare `URI::Generic` objects by `URI`'s own normalising rules, which is a different relation. The override carries the why-comment the styleguide requires |

## Deferrals Filed by Phase 1

Filed against `docs/deferred-items.md`; each names a target phase or an explicit pick-up condition,
per the roadmap's execution step 7. (The heading avoids the literal words the housekeeping probe's
`registers` check reserves for the aggregate register, which is where these rows live.)

| ID | Deferral | Target / condition |
|---|---|---|
| `DEF-24` | Design §5's suppressed-exception trail on the error root — `#suppressed`, the `#full_message` override and `Dexpace.attach_suppressed` with `RETRY-34`'s self-suppression guard | Phase 4, with the recovery chain (`RECOV-12`) that is its first caller |
| `DEF-25` | The wire-boundary re-validation of header names and outbound values inside every transport adapter — design §4's and §10.10's mitigation for the `HTTP-2` gap | Phase 8. Phase 1 ships `Dexpace::HeaderSyntax` as public API precisely so an adapter in another gem can call it |
| `DEF-26` | The `body` member's type and `HTTP-46`'s "body by value" equality half, both `untyped` in phase 1's RBS | Phase 3, when `BODY` lands |

### Deferral-register sweep

The roadmap's execution step 1 requires every phase to read the whole register and disposition
every row, not to scan for its own name. All twenty-three rows were read.

**Phase 1 picks up none, and gives one row a target phase it did not have.**

- **`DEF-2` — `HTTP-22`, `HTTP-48`, `HTTP-49`, `HTTP-50` — now targets phase 6.** This is the only
  row whose requirements are inside a phase-1 ID range and whose code would live in the gem phase 1
  ships, so it is the row the sweep exists for. Phase 1 does not build them: design §12 records all
  four as deferred, `HTTP-22` is a MAY whose observable contract (value equality by folded name) is
  already satisfied without interning, and `HTTP-48`–`HTTP-50` are SHOULD-level helpers over a
  header model that has no caller for them yet. **UNSCHEDULED would be the wrong mark**: that
  status is for a row whose pick-up condition a phase *met* and declined to act on, and this row's
  condition — "convenience helpers prioritized over minimal public surface" — never fired, because
  phase 1 deliberately kept the surface minimal. What the row lacked was a target, which is exactly
  what the roadmap's execution step 7 now requires of every deferral, so the sweep supplies one:
  **phase 6**, where `REDIR` and `AUTH` give the conditional-request helpers their first real
  caller (`If-Match`/`If-None-Match` on a re-issued request is `HTTP-50`'s aggregator, and an ETag
  is `HTTP-48`). The four unmet SHOULDs and the MAY are also recorded as a line in
  `docs/first-release.md`'s readiness list, so a release decision sees them without reading the
  deferral register.
- `DEF-1`, `DEF-3`–`DEF-10`, `DEF-18` — requirement-level deferrals in `SEAM`, `BODY`, `PIPE`,
  `RECOV`, `RETRY`, `REDIR`, `SSE`, `OBS`, `TRANSPORT` and `ASYNC`. None is reachable from a phase
  that ships only the HTTP domain model; left untouched.
- `DEF-11`–`DEF-17` — post-v1 gems, out of the MVP by construction.
- `DEF-19`, `DEF-20` — release-gated; nothing is published and every gem is still at `0.0.0`.
- `DEF-21` — phase 2's, hanging on require-time seam self-registration, which phase 1 does not add.
- `DEF-22` — phase 8's conformance assertion objects.
- `DEF-23` — a Steep target over a test tree; phase 1 adds twenty-two test files, none of which is
  production-quality helper code, so the condition is still unmet.
