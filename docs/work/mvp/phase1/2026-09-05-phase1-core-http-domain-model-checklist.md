# Phase 1 — Core HTTP Domain Model: Checklist

**Written at execution time, 2026-09-15, from what was built** — not from the plan. A row whose
task did not do what the plan said is a row that says so, and the "Deviations from the plan"
section below is where each departure is stated with its reason.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model.md`. Task numbers are that
plan's. Design: `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md`, whose
Deviation Ledger rows `P1-n` are cited below. Every test file named here is under
`gems/dexpace-core/test/`, mirrors its `lib/` file one for one, and opens with the IDs it
exercises.

## Requirement rows

Forty-two: `HTTP-1`–`HTTP-35`, `HTTP-46`–`HTTP-50`, `HTTP-53` and `SEAM-29`.

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `HTTP-1` | MUST | ✅ by construction | 2, 4–15 | Every model is `class X < Data.define(...)` including `Dexpace::Model`: frozen on construction, collections deep-frozen once through `Model.own`, `#with` the only derivation. `Ractor.shareable?` is asserted on every collection-holding model — `Headers`, `MediaType`, `Query`, `RequestOptions`, **and** `Request`/`Response` with a `nil` body (see `P1-9` as built, below; the opaque body is carried as given) — as the one-line proof the freeze reached every level (`dexpace/model_test.rb`, each model's suite) |
| `HTTP-2` | MUST | ✅ by construction, gap stated | 2, 14 | `private_class_method :new` plus a validating `.build` on every model. The residual gap is asserted, not hidden: `dexpace/http/request_test.rb` proves `Request.send(:new, …)` reaches the constructor and that `Request.new` does not, and names the mitigation — wire-boundary re-validation, phase 8a Task 16 / 8c Task 9 / phase 9 Task 7 (design §10.10). Because validation lives in `initialize`, a forged instance is still a *valid* one; the gap is bypassing the builder's cross-field defaulting, not validation |
| `HTTP-3` | MUST | ✅ / ⏳ / vacuous — split three ways | 5, 11, 13, 14, 15 | ✅ for the five models phase 1 builds: `Headers#new_builder` dups every value list and carries the direction, `Query#new_builder` dups every pair, `RequestOptions#new_builder` dups the tags, `Request#new_builder` and `Response#new_builder` carry frozen members; each suite derives, mutates the builder, builds a second instance and asserts the first unchanged. Value types with no builder derive through `Model#with`, which routes through `.build`. ⏳ for **the multipart body**: phase 1 ships no body, so `newBuilder()`-style derivation for it is `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle.md` Task 7's. **`RequestConditions` is vacuous**: the type is `HTTP-50`'s and `HTTP-50` is ⏳ under `docs/first-release.md`, so there is no instance for the clause to bind to |
| `HTTP-4` | MUST | ✅ | 1, 2, 5, 11, 13, 14, 15 | `Model.required!(name, value)` raises `Dexpace::InvalidArgumentError` with the one message form `<name> is required`; every model's `initialize` calls it for each required member — `Request` for method, url and headers, `Response` for request, protocol, status and headers in `HTTP-4`'s own order — so the field is named whether the model was reached through `.build`, `#with` or a builder (`dexpace/model_test.rb`; the "names a missing member" cases in `request_test.rb`, `response_test.rb`, `headers_test.rb`, `query_test.rb`, `request_options_test.rb`) |
| `HTTP-5` | MUST | ✅, two tiers | 2, 5, 11, 13 | Collections are `Model.own`ed — `Ractor.make_shareable(x, copy: true)` — once at construction. Appendix C's two tiers are implemented and asserted in opposite directions: `Headers#names`/`#entries` and `Query#names`/`#entries` are a fresh frozen snapshot per call (`refute_same` on two calls), `Headers#[]` is the instance's own frozen list (`assert_same`), and `Query#[]` allocates and freezes because a pair list has no stored per-name list. Mutating any returned collection raises `FrozenError`; a snapshot taken before a builder mutation is unchanged after it (`P1-7`) |
| `HTTP-6` | MUST | ✅ | 14, 15 | `Request` is exactly `Data.define(:method, :url, :headers, :body)`; `Response` exactly `(:request, :protocol, :status, :reason, :headers, :body)`; `to_h.keys` is asserted in both suites; `headers` is a `Headers`, never nil, `Headers::EMPTY` / `Headers::EMPTY_INBOUND` by default; operational knobs live in `RequestOptions` |
| `HTTP-7` | MUST | ✅ | 7, 14 | `Method#body_forbidden?` over the frozen set `{GET, HEAD, TRACE, CONNECT}`; `Request#initialize` rejects a non-nil body on such a method, and `Request::Builder#build` rejects it first with the same message. Proven for all four tokens, and for derivation: `get_request.with(body: "payload")` raises (`request/builder_test.rb`, `request_test.rb`) |
| `HTTP-8` | SHOULD | ✅ | 14 | `Request::Builder#build`: no method and no body → `Method::GET`; a body with no method → `method is required`, checked before `HTTP-7` so the missing method is what is reported (`request/builder_test.rb`) |
| `HTTP-9` | MUST | ✅, cites `P1-10` | 7 | `Method::IDEMPOTENT = %w[GET HEAD OPTIONS PUT DELETE]` is the single source and `#idempotent?` reads it; the canonical wire token equals the uppercase name structurally, since `Method.of` upcases (no argument) and validates the RFC 7230 token grammar through `HeaderSyntax.token?`. The set and predicate are **public**, which the requirement's parenthetical says they should not be — `P1-10`, because phase 6a/6b read them by receiver from sibling files (`method_test.rb`) |
| `HTTP-10` | MUST | ✅ | 6 | `Status.of(code)` is total over 100–599 — a 256-sample property test — and never raises for an unrecognised code; `Status.canonical_name(code)` and `#canonical_name` are the separate lookup and answer `nil` for a vendor code (499, 520, 526, 530, 599 asserted). A non-Integer or an out-of-range Integer is a caller mistake and raises (`status_test.rb`) |
| `HTTP-11` | MUST | ✅ | 6, 15 | Six range predicates on `Status`, derived from the code; `Response` exposes the same six as one-line delegations (`status_test.rb`, `response_test.rb`) |
| `HTTP-12` | MUST | ✅ | 6 | `Status` has one member, `code`; equality and hash are `Data`'s over it, so `Status.of(200) == Status::OK` and both hash identically, with the name a lookup rather than a member (`status_test.rb`) |
| `HTTP-13` | MUST | ✅ | 3, 4, 5 | `HeaderName#folded` is `downcase` with no argument (`Dexpace/NoLocaleCaseFold` rejects the argument form repository-wide); `Headers` keys `values` and `casing` by the fold for storage, lookup, containment, mutation, removal, equality and hashing; `Headers#==`/`#hash` are over the folded values only (`P1-8`). The fold never meets a non-ASCII byte because `HTTP-17` rejected it first (`header_name_test.rb`, `headers_test.rb`) |
| `HTTP-14` | MUST | ✅ | 5 | `Headers::Builder#add` appends, `#set` replaces the whole list; per-name insertion order is the array's (`headers/builder_test.rb`) |
| `HTTP-15` | MUST | ✅ | 5 | `Headers::Builder#set(name, nil)` removes the header entirely — no value list, no casing entry (`headers/builder_test.rb`) |
| `HTTP-16` | SHOULD | ✅ | 5 | Ruby's insertion-ordered `Hash`; `#names` and `#entries` come back in insertion order with original casing, and the first casing added is the one emitted (`headers_test.rb`, `headers/builder_test.rb`) |
| `HTTP-17` | MUST | ✅ | 3, 4, 5 | `HeaderSyntax.trim` removes SP and HTAB only, on bytes (`P1-5`: `String#strip` strips NUL); `valid_name?` rejects empty, every byte below 0x21, DEL and every byte ≥ 0x80 by reading `name.b.each_byte`, so `"a\0"`, `"a\r"`, `"a\r\nb"`, `"  "`, an interior space and invalid UTF-8 are all rejected with the SDK's error, never the regexp engine's; `"  X-Trace  "` is accepted as `X-Trace`. `HeaderName#initialize` and `Headers#initialize` run it again on every stored name, so `.build` and `#with` meet it too (`header_syntax_test.rb`, `header_name_test.rb`, `headers_test.rb`) |
| `HTTP-18` | MUST | ✅ | 3, 5 | `HeaderSyntax.valid_outbound_value?`: HTAB plus 0x20–0x7E, read as bytes; `"v\xC3\xA5lue"` rejected, `"a\tb"` accepted. `Headers::Builder` and `Headers#initialize` apply it for `:outbound`. A 128-sample property test proves the outbound grammar is strictly narrower than the inbound one (`header_syntax_test.rb`, `headers_test.rb`) |
| `HTTP-19` | MUST | ✅ | 3, 5, 15 | `HeaderSyntax.valid_inbound_value?` admits obs-text and refuses C0-except-HTAB and DEL; inbound names go through `validate_name!` unchanged. `direction` is a **member** of `Headers`, so `#new_builder` on an inbound model is inbound and `Headers::EMPTY_INBOUND` is `Response::Builder`'s default — asserted both ways, an inbound model deriving a lenient builder and an outbound one still refusing obs-text (`headers_test.rb`, `response_test.rb`) |
| `HTTP-20` | MUST | ✅ | 3, 5 | A rejected value never appears in a message in any form (`"secret\r\ntoken"` under `Authorization`: the message names the header and not `secret`); a rejected name is echoed with its control bytes escaped as `\xNN` through `HeaderSyntax.escape`, which itself reads bytes (`header_syntax_test.rb`, `headers/builder_test.rb`) |
| `HTTP-21` | MUST | ✅ | 4, 5 | `HeaderName` compares and hashes by `#folded`, keeps `#original` for emission, interoperates with the string-keyed API (`HeaderName.of` accepts a `String` or a `HeaderName`; every `Headers` method accepts either), and enforces `HTTP-17`. The fold is a derived attribute set before `super`, not a second member (`P1-11`) (`header_name_test.rb`) |
| `HTTP-22` | MAY | ⏳ | — | Not built; the observable contract — value equality by folded name — holds without interning. Owned by `docs/first-release.md` § Blockers before first publish, the `HTTP-22`/`48`/`49`/`50` decision line |
| `HTTP-23` | MUST | ✅ | 9 | `MediaType.parse` lower-cases type, subtype and every parameter key and preserves each value's case; `initialize` re-checks that every component is already folded, so `#with(type: "TEXT")` raises. Equality falls out of the members: case-insensitive where folded, case-sensitive on values (`media_type_test.rb`) |
| `HTTP-24` | MUST | ✅ | 9 | `MediaType#charset` looks `charset` up under the folded key, folds the value, and returns it only when this Ruby's `Encoding.name_list` (minus the four process-relative pseudo-aliases) knows it; `nil` otherwise, never a raise; the `nil` is documented at the accessor (`media_type_test.rb`) |
| `HTTP-25` | MUST | ✅ | 9 | A `StringScanner` parser over the byte-validated input: parameters split on `;` outside a quoted-string, each on its **first** `=`, quotes stripped and quoted-pairs unescaped; `#render` emits a value bare when it is a token and quoted-and-escaped otherwise. `parse(render(x)) == x` is a 64-sample property over an alphabet including `;`, `=`, `"` and `\` (`media_type_test.rb`) |
| `HTTP-26` | MUST | ✅ | 3, 9 | `MediaType.parse` runs `HeaderSyntax.valid_outbound_value?` — the same predicate, not a copy — on the raw input before any character-oriented work, and `initialize` runs it on every parameter value; CR, DEL, non-ASCII and invalid UTF-8 are rejected with the SDK's error (`media_type_test.rb`) |
| `HTTP-27` | SHOULD | ✅ | 9 | `#matches?`: `*/*` matches everything, `type/*` any subtype of the type, parameters ignored; `*/json` is rejected at construction (`media_type_test.rb`) |
| `HTTP-28` | MUST | ✅ | 11 | `Query` is a list of `[name, value]` pairs: case-sensitive names, insertion order across names, multiple values per name, and `Query::Builder#add(name, nil)` stores `""` — one empty-string value, distinct from an absent name (`query_test.rb`, `query/builder_test.rb`) |
| `HTTP-29` | MUST | ✅ | 10, 11 | `Query#encode` renders every name and value through `PercentEncoding.encode_component`, one occurrence per value, in insertion order, no leading `?`, `""` when empty (`query_test.rb`) |
| `HTTP-30` | MUST | ✅ | 11 | `Query#==`/`#hash` compare the encodings, which is the requirement stated literally (`P1-12`); order-sensitive, and `parse(q.encode) == q` is a 64-sample property. An empty value list cannot reach the model: `Query::Builder#set(name, [])` removes the name (`query_test.rb`, `query/builder_test.rb`) |
| `HTTP-31` | MUST | ✅ | 10, 11 | `Query.parse`: `nil` or blank → `Query::EMPTY`, a leading `?` tolerated, a segment with no `=` or a trailing `=` → `""`, a stray `&` skipped, a malformed escape kept raw; `PercentEncoding.decode_component` is lenient and total. Both read bytes, so a query carrying invalid UTF-8 parses and re-encodes byte-exactly (`query_test.rb`, `percent_encoding_test.rb`) |
| `HTTP-32` | SHOULD | ✅ | 10 | `PercentEncoding.encode_component`: unreserved set exactly `A-Za-z0-9-._~`, everything else uppercase-escaped — `a b*~+/!()'` → `a%20b%2A~%2B%2F%21%28%29%27` byte for byte; `decode_component("a+b")` is `"a+b"`; `%FF` round-trips (`percent_encoding_test.rb`) |
| `HTTP-33` | MUST | ✅ | 8 | `Protocol` over the canonical forms `http/1.1` and `http/2`; `Protocol.parse` accepts those and the aliases `HTTP/2` and `HTTP/2.0` case-insensitively (`downcase`, no argument, after a byte check) and raises naming an unrecognised identifier; `.build` accepts only a canonical form, so `#with` cannot admit an alias (`protocol_test.rb`) |
| `HTTP-34` | MUST | ✅ | 13 | `RequestOptions` — `timeout` (a `Float` of seconds), `max_retries`, `tags` — every field `nil`/empty by default, `RequestOptions::EMPTY` one shared frozen instance, `tags` `Model.own`ed at build and a map of `String` to `String` (`request_options_test.rb`) |
| `HTTP-35` | MUST | ✅ | 13 | In the model's `initialize`, so `.build` and `#with` meet it: a non-nil timeout that is zero or negative raises, a negative `max_retries` raises, `0` is accepted and means "disable retries for this call" (`request_options_test.rb`) |
| `HTTP-46` | MUST | ✅ (URL and method/headers), ⏳ (body by value) | 12, 14 | `Request#==`/`#hash` compare `URL.external_form(url)` — a textual key; Ruby's `URI` resolves nothing, and the test compares two textually different URLs naming one host without touching the network — plus method, headers and body by `==` (`P1-6`). The body half is opaque here and was built by phase 3b (`P3-15`, `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle.md`) (`url_test.rb`, `request_test.rb`) |
| `HTTP-47` | SHOULD | ✅ | 12, 14 | `URL.parse!` pins `::URI::RFC3986_PARSER`, refuses a non-absolute URI naming it, and converts `URI::InvalidURIError` into a `Dexpace::InvalidArgumentError` carrying the offending input with the original as `cause`; `Request::Builder#build` and `Request#initialize` both route the URL through it, so `"::bad"` is named from either (`url_test.rb`, `request/builder_test.rb`) |
| `HTTP-48` | SHOULD | ⏳ | — | Not built; `docs/first-release.md` § Blockers before first publish, the `HTTP-22`/`48`/`49`/`50` decision line — no v1 phase constructs a conditional request |
| `HTTP-49` | SHOULD | ⏳ | — | As `HTTP-48` |
| `HTTP-50` | SHOULD | ⏳ | — | As `HTTP-48`; this is also why `HTTP-3`'s `RequestConditions` clause is vacuous |
| `HTTP-53` | MUST | ✅ | 9 | `MediaType.parse` rejects blank input, a missing or empty type or subtype, more than one `/`, a parameter with no `=`, an empty key or an empty value, an unterminated quoted-string and text after a closed one; the rejected list is enumerated in `media_type_test.rb` |
| `SEAM-29` | MUST | ✅, both halves | 1, 2, 5, 11, 13, 14, 15 | The uniform message: `Model.required!` is the one helper, one error class, one form (`model_test.rb`). The generic contract: `Dexpace::Builder`, included by all five builders, with `Dexpace::_Builder[T]` as the RBS interface and `Builder.build_all` as the composition helper; `dexpace/builder_test.rb` passes all five builders through it — the requirement's conformance step — and proves an incomplete builder raises `NotImplementedError` and a non-builder is refused |

Forty-two rows: 36 ✅ (three of them by construction or split — `HTTP-1`, `HTTP-2`, `HTTP-3`; two carrying a
deferred half — `HTTP-3`, `HTTP-46`), 4 ⏳ (`HTTP-22`, `HTTP-48`, `HTTP-49`, `HTTP-50`), 0 🚫, 0 N/A.
`XCUT-15` and `XCUT-18` are implemented here — `Model.own`/`Model.frozen_string` and `HeaderSyntax` — and
are phase 9's to disposition; neither is a row.

## What was built

Twenty-two new `lib/` files under `gems/dexpace-core/lib/dexpace/`, each with its `sig/` mirror and its
`test/` mirror, plus the entry file, its signature and the smoke suite extended — the layout the design's
Module Layout section names, file for file. `require "uri"` and `require "strscan"` are the only two
`require`s outside `require_relative` (the plan expected `uri` alone; `strscan` is the media-type parser's,
and both are on the require allowlist). The gemspec still has zero `add_dependency` lines.

The gates, all seventeen, on **4.0.6** (`bundle exec rake`, 2026-09-15): green, exit 0 — `cops:test` 65 runs,
`steep` no type error over the strict `core` target, `test:gems` 252 runs / 1853 assertions with **100.00% line
coverage (768/768)** against the 80% floor, `test:gates` 128 runs / 523 assertions, the nine `gates:*` tasks,
`yard` 100.00% documented (15 modules, 16 classes, 60 constants, 8 attributes, 122 methods), `bundler_audit`
clean. **One caveat about `rubocop`, stated in full under "Findings routed"**: run through `rake` from this
worktree it inspected 8 files, because RuboCop inherits `AllCops/Exclude` from the topmost `.rubocop.yml` on
the path and the parent checkout's excludes `.claude/**/*`, under which this worktree sits; run as
`bundle exec rubocop --fail-level=convention --ignore-parent-exclusion` it inspected **126 files, no
offenses**, and that is the run these rows rest on.

The matrix set — `test:gems gates:gemspec_audit gates:require_allowlist gates:clean_bundle
gates:single_instance` — green on **3.2.11**, and `test:gems` green on **3.3.12** and **3.4.10** as well,
each with its own lockfile resolved fresh. The 3.2.11 run is the one that proves `Dexpace::Model#with`: with
the override removed (`Dexpace::Model.send(:remove_method, :with)` after load) `model_test.rb` fails one case on
3.2.11 — `Sample.build(code: 1).with(code: nil)` returns a model with a nil code — and passes on 4.0.6, which is
the design's finding 1 reproduced against the built code.

The surface manifest `test/fixtures/surface/dexpace-core.txt` grew from two lines to 221 through
`bundle exec rake surface:regenerate`, once, after the last task; the diff was read line by line and holds
exactly the constants and methods the twenty-two files define — `Headers::EMPTY_INBOUND` beside
`Headers::EMPTY`, `Method::IDEMPOTENT` (`P1-10`), and no private reader (deviation 10 below). `gates:sig_diff`
still prints "no release tag yet".

## Audit groups run

The phase-start pair first: `--section conflicts --brief` returns the six harvested conflicts, every one
`[overridden by notes/…]`; `--origin note --brief` returns those six and the later phases' notes, none of which
contradicts this plan. `--req` was run for each task's IDs before that task. The four groups the design named:

| Group | Result at implementation |
|---|---|
| Public API surface | Clean, with one rule the plan's own text got backwards: `data-modeling/3775e9d7` says *never* `module_function`, and the plan's Task 3 aside said `module_function` "rather than `extend self`" citing that same key. The corpus and `.rubocop.yml`'s `Style/ModuleFunction: extend_self` agree; the three function modules use `extend self` (deviation 3). `api-design/e4fa3438`'s override-with-a-why-comment is used four times — `HeaderName`, `Headers`, `Query`, `Request` — one more than the design counted, for `Query`'s equality-by-encoding (`P1-12`) |
| RBS / Steep typing | Two facts phase 0 could not have seen, both about rbs's core signatures: `Data` declares no `initialize`, so a keyword `super` in any `initialize` override resolves to `BasicObject#initialize` and Steep rejects it — declared once on `Dexpace::Model` in RBS only (deviation 5); and `URI::RFC3986_Parser` is an empty class, so its `#parse` is untyped at the one call site. Strict Steep also refuses an unannotated `[]`/`{}` (`Ruby::UnannotatedEmptyCollection`), whose annotation syntax `#:` the RuboCop baseline rejected — `Layout/LeadingCommentSpace: AllowRBSInlineAnnotation: true` (deviation 7). `NFR-11`'s allowlist lacked `Data`, `ArgumentError` and `StringScanner` (deviation 6) |
| Minitest conventions | Clean. `testing/62f8f4ec`'s error-boundary pairing is applied to every builder — class, field-naming message, no partial side effect — and `testing/f36a19cd`'s bounded property tests exist for `HeaderName`'s fold, `Status`'s totality, `HeaderSyntax`'s grammar ordering, `PercentEncoding`, `MediaType` and `Query`. Three suites carry a nested test class per behaviour group (deviation 16), because `Style/OneClassPerFile` forbids a second top-level class and `Metrics/ClassLength` caps one at 100 lines |
| Encoding and binary strings | Clean and load-bearing: every validator reads `value.b.each_byte`; `PercentEncoding` accumulates into a BINARY buffer and retags UTF-8 at the end; `Query.parse` and `HeaderSyntax.trim` work on `.b`; `HeaderSyntax.validate_name!` retags a *valid* name with the caller's encoding because its bytes are proven printable ASCII, which is `io-and-byte-streams/0a4773a6`'s "retag only where the bytes are known to conform" (deviation 4) |

The four notes the design filed are unchanged by implementation, with one correction filed as a fifth entry:
`docs/knowledge/notes/data-modeling.md` gains a `## Superseded` entry recording that `Request` and `Response`
**are** `Ractor.shareable?` as built, because `URL.parse!` freezes the URI's component strings it owns and the
uri gem already freezes `URI::RFC3986_PARSER` on 3.2.11 and 4.0.6 — the phase-1 entry's mechanism (shallow
`URI#freeze`, `make_shareable` freezing the global parser) was half right, and the half that was wrong is the
one the ledger row `P1-9` rested on.

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate; three
change a gate or tool in the strict or the corrected direction, each with a fixture.

1. **`Dexpace::Model#with(changes = nil)` takes a positional `Hash`, not `**changes`.** `Dexpace/NoKeywordSplat`
   flags every public `def` in `gems/*/lib` with a `**` parameter, and an inline disable would special-case a
   gate. Ruby passes keywords to a method that declares none as one positional Hash on every Ruby in the range
   (probed on 3.2.11 and 4.0.6), so `x.with(code: 2)`, `x.with` and `x.with(**{})` all behave as the plan's
   form does, and the empty call allocates nothing.
2. **`HeaderName` is `Data.define(:original)` with `folded` a derived attribute set before `super`**, and
   `.build(original:)` has no `folded:` keyword. The plan's `initialize(original:, folded: nil)` leaves
   `folded` unused, which `Lint/UnusedMethodArgument` refuses; and a derived value that is also a member can be
   handed in stale — `#with(original: …)` carries the old fold in `to_h` — which is the argument `Status`'s
   one-member design already makes. Setting the ivar before `super` is the one moment a `Data` is mutable, and
   on 3.2.11 the inherited `Data#with` leaves it `nil`, which makes `Model#with` load-bearing for this type on
   the floor and the floor run proves it. Ledger row `P1-11`.
3. **`extend self`, never `module_function`**, in `HeaderSyntax`, `PercentEncoding` and `URL`; private helpers
   under a `private` section with a private RBS declaration. The corpus rule the plan cited says the opposite of
   what the plan's aside claimed, and `Style/ModuleFunction` enforces the corpus.
4. **`HeaderSyntax.trim` returns BINARY bytes; `validate_name!` retags a valid name with the caller's
   encoding**; `HeaderSyntax.token?` and `TCHAR` live in `HeaderSyntax`, shared by `Method` and `MediaType`,
   rather than a `TCHAR` in `Method` alone. One grammar, one home.
5. **RBS: `module Model : _ModelInstance`** — an interface asking for `to_h` and an untyped `class`, because a
   module cannot name every includer's own `.build` keyword list and Steep checks the self-type at every
   `include`; and **`Model#initialize: (**untyped) -> void` declared in RBS only**, because rbs core declares no
   `Data#initialize` and `Model` sits between every model and `Data` in the ancestor chain. Every model is
   `class X < Data` in RBS with `private def self.new` and a typed `initialize`.
6. **`tools/rbs_surface.rb`'s `STDLIB_ALLOWED` gains `Data`, `ArgumentError` and `StringScanner`.** The first
   real signatures — `class HeaderName < Data`, `class InvalidArgumentError < ::ArgumentError`, a private
   helper taking a `StringScanner` — turned `gates:rbs_surface` red on correct code: the three are core Ruby or
   `strscan`, which the require allowlist admits. Fixture `test/fixtures/gates/rbs_surface/gems/fixture/sig/core_superclasses.rbs`
   and its case in `test/gates/rbs_surface_test.rb`; verified red under the previous list, green under this one.
7. **`.rubocop.yml`: `Layout/LeadingCommentSpace: AllowRBSInlineAnnotation: true`.** Strict Steep refuses an
   empty collection literal with no `#: Type` annotation, and the cop's default rejects the annotation's
   space-less `#:`. Every ordinary comment is still held to the space rule.
8. **`rbs:validate` loads the allowlisted stdlib signature sets with `-r`**, `RequireAllowlist::ALLOWED` minus
   `set` (which rbs 4 ships under `core/`, as the Steepfile already records). With `--no-collection` and no
   `-r`, `URI::Generic` and `StringScanner` were "not found" by a gate that had never met a stdlib reference.
9. **`gates:single_instance` rescues `superclass mismatch` and reports it as a double load.** A second copy of
   core cannot finish loading once core holds `Data.define` classes — the second copy's `Data.define` is a fresh
   anonymous superclass — so the gate's tally was never reached and its test saw a stack trace. The crash is the
   violation itself; the gate now names it beside the features already loaded twice, and
   `test/gates/single_instance_test.rb` asserts both.
10. **`Surface.data_readers` honours the model's visibility.** The walker took the anonymous `Data` superclass's
    public readers, which stay public there when the model makes them private (`Headers`'s `values`/`casing`,
    `Query`'s `pairs`), so the first manifest listed three methods `respond_to?` denies. Fixture `Hidden` and a
    case in `test/gates/surface_snapshot_test.rb`.
11. **`Request`'s `Data.define(:method, …)` line carries `# rubocop:disable Lint/DataDefineOverride`** with the
    reason above it. The cop is `pending` — enabled only through `NewCops: enable` — and it warns that a member
    named `method` "may be unexpected"; `HTTP-6` fixes the member by name and the design documents the shadowing
    of `Object#method` deliberately, so the warning is answered in place. The one inline directive in the tree.
12. **`URL.parse!` re-parses a URI input from its text and freezes the component strings, rather than
    `dup.freeze`.** `URI::Generic#freeze` is shallow and `dup` shares `@host`/`@path` with the caller's object
    (probed on both interpreters), so the plan's form aliased externally-mutable state through `request.url.host`
    (`XCUT-15`). Consequence: **`Request` and `Response` are `Ractor.shareable?`** without any global touched,
    which retires the narrowing in `P1-9`; both suites assert shareability (with a `nil` body — the opaque
    body is carried as given, so an unfrozen one is the caller's). Ledger row `P1-13`.
13. **The media-type parser is a `StringScanner` over per-pattern-timeout regexps**, not the plan's character
    loops, which tripped `Metrics/ClassLength`, `AbcSize` and the complexity cops. Every regexp runs only after
    `HeaderSyntax` proved the input printable ASCII, so none meets invalid UTF-8. It is lenient about a bare
    non-token value (`q=a b` parses, and `#render` quotes it back), which `HTTP-53`'s list does not forbid.
14. **`Query#==`/`#hash` compare encodings** rather than `Data`'s generated equality over the pair list, because
    two Strings with the same non-ASCII bytes under different encoding tags are not `String#==` yet encode to
    one wire query, and `HTTP-30` is stated in terms of the encoding. Ledger row `P1-12`.
15. **Eager type checks the plan did not have**: `Method.of` accepts `String` or `Symbol` and refuses anything
    else; `HeaderName` requires a `String`; `Headers.build` requires a list of Strings per name; the builders'
    writers refuse a wrong-typed value where they are set. Each pre-empts a `NoMethodError` that would otherwise
    escape `rescue Dexpace::Error` — the Task 1 rule applied.
16. **Test layout**: every domain test file `require "dexpace"` itself (the shared helper cannot, or the smoke
    suite's namespace snapshot would be vacuous); `headers_test.rb`, `query_test.rb` and `response_test.rb` nest a
    second (and third) test class per behaviour group; the smoke suite snapshots the top level after
    `require "uri"` and `require "strscan"`, whose constants are theirs. Run counts exceed the plan's expected
    numbers throughout.
17. **Minor defaults**: `Request.build(body: nil)` and `Response.build(reason: nil, body: nil)` default their
    optional members; `MediaType.build(parameters: {})` defaults; `Protocol.parse` and `MediaType.parse` require a
    `String`.

## Findings routed

- **`rake rubocop` is vacuous in a worktree nested under the parent checkout's `.claude/`.** RuboCop takes
  `AllCops/Exclude` from the topmost `.rubocop.yml` on the path — here the parent's, whose `.claude/**/*` line
  (P0-11) swallows the whole worktree — so the gate inspected 8 files and passed on this tree. CI and a plain
  checkout are unaffected; the honest local run is `--ignore-parent-exclusion`. A repair to a phase-0 gate is
  phase 10's: routed to phase 10's inbound list in `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`.
- **`P1-9` is retired as built** (deviation 12) — recorded in the design's Deviation Ledger as `P1-13` beside an
  as-built note on `P1-9`, and as a corpus note; `docs/deviations.md` is phase 10's to flip and is untouched.
- **`Dexpace::Protocol` has no alias for `http/1.0`** — already on phase 10's inbound list from phase 8a; phase 1
  builds `HTTP-33` as stated and leaves the widening to that decision.

## Postponed work

The three items phase 1 postponed keep the owners the design's "Work Phase 1 Postponed, and Who Owns It Now"
section records — the suppressed trail (phase 4b, Task 1), wire-boundary re-validation (phase 8a Task 16, 8c
Task 9, phase 9 Task 7) and the `body` member's type with `HTTP-46`'s by-value half (phase 3b, `P3-15`) — and
were re-checked on 2026-09-15: `grep -n 'HTTP-48' docs/first-release.md` still finds the `HTTP-22`/`48`/`49`/`50`
decision line under § Blockers before first publish. The implementation postponed nothing further.
