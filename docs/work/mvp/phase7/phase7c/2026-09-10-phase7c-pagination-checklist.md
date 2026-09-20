# Phase 7c — Pagination: Checklist

**Written at execution time, 2026-09-20, from what was built** — not from the plan. A row whose task
did not do what the plan said is a row that says so, and the "Deviations from the plan" section
below is where each departure is stated with its reason. The design and the plan were written on
2026-09-10 against phases 4–6's *designs*, on a machine that then had only Ruby 3.4.10, concurrently
with 7a's and 7b's documents. Since then phases 4a–6c were built, reviewed and merged (PRs #53–#80),
every interpreter in the matrix was installed, and a cross-check agent read this plan in full against
`main` at `c53638b` on 2026-09-20. **This phase was cut from `main` at `c53638b`**, which holds the whole
of phase 6, concurrently with 7a and 7b on the same base: nothing of theirs exists on this tree, and the
one convergence point the charter names — spec-forced boundary 5's audit — went to 7b by the manager's
decision of 2026-09-20, so this lane builds no gate and carries a non-ID row for it below. Where the
plan's text and the built tree disagree the tree wins and this document records it.

**Reconciled 2026-09-20.** Phase 7b's stack merged first (#81 → #82 → #83, `main` at `34f52e8`), so
this phase's three branches were rebased onto it by `git rebase --onto` with rerere disabled, every
7c commit preserved. The sentences below that count the tree describe **this phase's own base**,
`c53638b`, and are left as written; on the combined tree the figures are: 208 `lib/dexpace/` files
beside `version.rb` (7b's nine and 7c's fifteen over the 184 of phase 6), the same nineteen
`private_constant` test-mirror exceptions, sixteen checklists, sixteen as-built pages, the core
manifest 1 180 → 1 257 (still exactly this phase's 77 rows), and **eighteen** gates — 7b's
`gates:serde_boundary` being the one this phase's base did not have. The boundary-5 row below records
the one thing the reconcile pass built. The combined tree's counts are `CLAUDE.md`'s and the roadmap's
reconciliation note's; this document's are its base's.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination.md`. Task numbers are that plan's
(seventeen). Design: `docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination-design.md`, whose
Deviation Ledger numbered P7-1–P7-6 before execution (colliding with 7a's P7-1–P7-9, numbered in
isolation; phase 10's consolidation resolves it) and whose as-built rows **P7-101–P7-117** are cited
below (7a's rows are cited as "7a's P7-n", 7b's as "7b's P7-n"; the manager fixed the numbering so the
three lanes never collide); the charter is `docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md`.
Review round 0 (2026-09-20) asked for two changes and this document records them where they land:
`Page.build` now names a non-String key (R0-1, guard 46) and `LinkHeader` reads only the first `rel`
parameter of a link-value (R0-3, P7-116, guard 47); the sentence below about which branch carried
`http/url_test.rb` was corrected (R0-2). Review round 1 (2026-09-20) asked for one test and raised one
nit, both landed: `Walk#release`'s slots-cleared-before-the-raise invariant is pinned (R1-1, guard 48),
and a fragment-only `rel=next` target — `<#>`, `<#frag>` — is end-of-stream before resolution, as the
empty one already was, RFC 3986 §4.4's two same-document forms read together (R1-2, P7-117, guard 49).
Every test file named here is under `gems/dexpace-core/test/`, mirrors its `lib/` file one for one
(two carry no `lib/` mirror and say so below; one `private_constant`, `page/closing.rb`, carries no
`test/` mirror and is asserted through the two views and the lifetime suite), and opens with the IDs
it exercises.

## Requirement rows

Thirty-six own rows — `PAGE-1`–`PAGE-36` — plus the non-ID row for spec-forced boundary 5 and the
cross-reference rows for the non-`PAGE` IDs this phase owns a share of. **Thirty-five ✅, one ✅
vacuous by construction** (`PAGE-35`, design §12's own disposition), nothing ⏳, nothing 🚫, nothing
N/A; the seven rows the design says must be stated rather than ticked (`PAGE-1`, `PAGE-15`, `PAGE-16`,
`PAGE-21`–`PAGE-24`, `PAGE-28`, `PAGE-33`, `PAGE-35`) state their clause.

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `PAGE-1` | MUST | ✅ | 11, 12, 14 | **Four sites, not two**: the blocking engine's `Items` (server order across page boundaries, `[[1, 2], [], [3, 4], [5]]` → `[1, 2, 3, 4, 5]`) and `Pages` (three page objects for three pages, each with status, headers and the executed request), and the async engine's `#walk` (items, serially) and `#walk_pages` (whole live pages, each open for the consumer's call and closed exactly once after it) over one pump with a two-branch drain — `PAGE-27` names the page-level drain in as many words, so a row citing the blocking views alone would tick a MUST the async engine did not meet (`items_test.rb` "PAGE-1"; `pages_test.rb` "PAGE-1"; `async_paginator_test.rb` "PAGE-1 (async)", "PAGE-27 (async, page-level)") |
| `PAGE-2` | MUST | ✅ | 5 | `Page#items` is a frozen SHALLOW copy (P7-101: the collection is owned, the elements stay the caller's, never `Model.own`'s deep copy, which raises on a Proc), never nil, possibly empty; `#status`, `#headers`, `#request` are read off the frozen `Response` `Data` and survive `#close`, which invalidates the body alone (`page_test.rb`, three `PAGE-2` cases) |
| `PAGE-3` | MUST | ✅ | 5, 15 | `Page` is a plain class including `Dexpace::Closeable`, not a `Data` (a `Data` cannot hold the latch; `Response#close` is a pure forward with none of its own): three `#close`es release the response once, a raising release leaves the latch flipped and is never retried; `.build` refuses anything but a real `Dexpace::Response`, and a `next_link` or `continuation_token` that is neither nil nor a String, named (P7-107; guard 46); a fetcher's page owns its response and the walk, not the fetcher, closes it (`page_test.rb`, two `PAGE-3` cases and the duck-refusal; `fetchers_test.rb` "PAGE-34 / PAGE-3"; guard 39) |
| `PAGE-4` | MUST | ✅ | 4, 7, 8, 9 | `Info` is a frozen `Data` whose `next_request == nil` is the single end-of-stream signal — no `terminal?`, no sentinel, no exception path; `.terminal(items:)` names the case; empty items with a non-nil next request is a valid non-terminal page. The three built-ins do NOT rescue the extractor: a raise is a parse failure and `PAGE-13`'s path, never an end (`info_test.rb`, four `PAGE-4` cases; the "PAGE-4: an extractor that raises" case in each of the three strategy suites; guard 44) |
| `PAGE-5` | MUST | ✅ | 7, 8, 9, 10 | The three strategies are frozen `Data`s with no instance variables at all (a `Data` holds none, measured) so "immutable and safe to share" is structural; one `CursorStrategy` serves two walks with different templates; `#parse` closes nothing (`closes` 0 on the real response) and the walk hands the strategy an open, unmutated response (`closes` 0 seen from inside `#parse`) (`cursor_strategy_test.rb`, `page_number_strategy_test.rb`, `link_strategy_test.rb`, each "PAGE-5"; `walk_test.rb` "PAGE-5") |
| `PAGE-6` | MUST | ✅ | 13, 14 | `R10`'s two assertions, separately. **Blocking**: `Paginator.build` → 0 exchanges; `#items` → 0; `#items.to_enum(:each)` → 0; `#pages` → 0; `#pages.each` (block-less) → 0; then `first(1)` is 1 exchange and `first(2)` two more. A repeated `Pages#more?` reads the staged page and costs nothing. **Non-blocking**: `AsyncPaginator.build` → 0; `#walk` → 1 exchange immediately (the requirement's own carve-out), then one per page consumed, the future settling with the page count (`paginator_test.rb`, two `PAGE-6` cases; `pages_test.rb` "PAGE-6 / PAGE-12", "PAGE-6"; `async_paginator_test.rb`, two `PAGE-6` cases; guards 4, 18, 19) |
| `PAGE-7` | MUST | ✅ | 10 | `Walk#fetch_next_page` latches `@exhausted` when the drive answers nil and answers nil with no exchange from then on; the strategy drive itself answers nil without an exchange once the last `Info` said end-of-stream; a closed walk fetches nothing (`walk_test.rb` "PAGE-7", "a closed walk fetches nothing"; guard 14) |
| `PAGE-8` | MUST | ✅ | 11, 12, 13 | `Paginator` is a frozen `Data` with no ivars and only immutable configuration; every per-walk quantity is on a private `Walk` that `Items#each` opens afresh on EVERY call (`to_a` twice = two full fetch sequences, the same URLs in the same order; two interleaved enumerators of one view do not share state; two threads over one engine each drive their own sequence) and that `Pages` opens once per view (two `#pages` calls = two walks = 4 calls) (`items_test.rb`, two `PAGE-8` cases; `pages_test.rb` "PAGE-8"; `paginator_test.rb`, two `PAGE-8` cases; `fetchers_test.rb` "PAGE-8"; guards 12, 13) |
| `PAGE-9` | MUST | ✅ | 10, 13, 14 | `cap:` counts exchanges, checked in `Walk#fetch_next_page` BEFORE the exchange (`>=`), so a server echoing one cursor forever under `cap: 3` costs exactly 3 exchanges and 3 items, on both engines; validated strictly positive in the models' `initialize` so `.build`, `#with` and a forged `send(:new, …)` all meet it — `0`, `-1`, `0.0`, `-0.5`, `NaN`, `nil`, `"3"` and `:three` refused at construction, naming `PAGE-9`; a Float cap is admitted (`walk_test.rb` "PAGE-9"; `paginator_test.rb`, three `PAGE-9` cases; `async_paginator_test.rb` "PAGE-36 / PAGE-9"; guards 15, 16) |
| `PAGE-10` | SHOULD | ✅ | 13 | The default cap is `Float::INFINITY` — strictly positive, comparable against an Integer count, a value not a sentinel — and 600 single-item pages walk under it; the documentation clause is discharged in `Paginator`'s YARD ("**set a finite cap in production**") and in `docs/sdk-documentation/pagination.md`, not as a configuration key (`paginator_test.rb` "PAGE-10") |
| `PAGE-11` | MUST | ✅ | 11 | `Items#each` closes each page BEFORE its first item is yielded (`closes` reads `[1, 1]` across a two-item page); one item from a two-item first page closes it and fetches no second page; an enumerator abandoned after one `#next` strands nothing because the close already happened; `Items#close` is a documented no-op and never raises (`items_test.rb`, two `PAGE-11` cases, "Items#close", "external iteration"; guards 1, 2) |
| `PAGE-12` | MUST | ✅ | 10, 12 | **The look-ahead lives on the `Walk`** (`@buffered`), never in the enumerator's closure. The previous page is closed as the consumer advances (`[[0,0,0],[1,0,0],[1,1,0]]`), the last at exhaustion; `Pages#more?` runs an exchange the first time and stages the page, reads it for free the second time (1 call, nothing displaced), and a probe on an exhausted-and-closed view fetches nothing; `#close` releases BOTH slots; a `break` inside `#each_page` releases the held page; `Walk#hold` writes the new page into its slot BEFORE closing the previous one so a raising close strands nothing; `Walk#buffer` refuses to displace a staged page (P7-103's error). Consumers are told to wrap the view in `#each_page` or call `#close` in `Pages`' YARD (`pages_test.rb`, seven `PAGE-12` cases; `walk_test.rb` `SlotsTest`; guards 3, 4, 5) |
| `PAGE-13` | MUST | ✅ | 10, 11, 12, 14 | `Closing.parse_or_close` closes the response INLINE on a `#parse` raise (the page is never built) and re-raises the parse error as itself (`raise error, cause: nil`); a close failure is attached to its suppressed trail, never raised over it (`[IOError]` on a `KeyError`); the fatal family closes quietly and propagates with no trail (P7-110); the same on the async path, and a parse failure on page 2 releases the held page 1 with the parse error primary (`walk_test.rb`, three `PAGE-13` cases; `items_test.rb`, `pages_test.rb`, `lifetime_test.rb`, `async_paginator_test.rb` "PAGE-28 / PAGE-13"; guards 9, 10) |
| `PAGE-14` | MUST | ✅ | 12 | `Pages` latches `@viewed`: a second `#each`, with or without a block, and a `#to_a` after one raise `Dexpace::Page::PageStateError` — a `StandardError` in the `Dexpace::Error` family, NOT `InvalidArgumentError`, per the roadmap's phase-10 inbound bullet of 2026-09-13 (P7-103; the bullet's shared-supertype half stays phase 10's). A block-less `#each` claims the latch on obtaining the enumerator (P7-113) (`pages_test.rb` `SingleUseTest`, two `PAGE-14` cases; `page_state_error_test.rb`; guards 11, 41) |
| `PAGE-15` | MUST | ✅ (P7-1) | 10, 12, 16 | **Two of three clauses**, stated: (a) a close error while releasing a held page is SURFACED — on `Pages#close` after a probe, on the advance in `Walk#hold`, on the eager close in `Items`, and through a short-circuiting terminal (`break`, `first`) — never swallowed; (c) when both held pages fail to close the first failure propagates with the second on its suppressed trail, on the one reachable two-slot state (a probe from INSIDE the loop, then `break`). (b), "re-thrown wrapped", is **vacuous by a false antecedent** — no Ruby terminal can fail to declare an error type; measured four ways on every row, `matrix_facts_test.rb` fact 1 — and `lifetime_test.rb` "P7-1" asserts the concrete class with a nil `#cause` so a wrapper introduced later fails loudly; the vacuity is `docs/first-release.md`'s `C13`, already filed. The advance close is a bare close, never `close_quietly`. `Walk#release` clears BOTH slots before anything can raise, so after a raising close the walk holds nothing, a closed `Pages` answers `more?` false and a drive over it yields nothing — the invariant review round 1 found unpinned (R1-1) is asserted in `walk_test.rb` `SlotsTest` and `pages_test.rb` `SurfacedCloseTest`, and guard 48 (the reviewer's surviving mutation 73) is red on both rows (`pages_test.rb` `SurfacedCloseTest`; `walk_test.rb` `SlotsTest`; `lifetime_test.rb`, five `PAGE-15` cases; guards 6, 7, 8, 48) |
| `PAGE-16` | MUST | ✅ (P7-6) | 7 | `CursorStrategy.build(extract:, parameter: "cursor")`: ONE extractor call, `[items, cursor]` back, `nil` OR `""` end-of-stream, otherwise the template with the parameter spliced (replacing an earlier value in place); the cursor also travels as `Info#continuation_token`. **"A single read of the response body" is the EXTRACTOR's read and core performs none**: a `RecordingBody`'s `source_count` reads 1 through an extractor that reads and 0 through one that does not, and an extractor reading through `Response#body_string` gets the single-use rule from 3b's body (`ClosedError` on a second read). The extractor's answer shape is checked, not destructured blindly (P7-107) (`cursor_strategy_test.rb`, six `PAGE-16` cases; guard 20) |
| `PAGE-17` | MUST | ✅ | 8 | `PageNumberStrategy.build(extract_items:, parameter: "page", start: 1)`: an empty items list is end-of-stream, checked FIRST; the current page is read from the EXECUTED request (`response.request`: `?page=5` on the response and `?page=1` on the template gives `page=6`); absent, empty, `abc`, `-2`, `1.5`, `1e3`, a non-ASCII numeral and a space all fall back to `start` (`page=8` under `start: 7`); a percent-encoded digit run is read decoded and counts (P7-114); `parameter:` and `start:` are configurable, `start: 0` admitted; the next request is the TEMPLATE with its page spliced, other parameters byte-identical, method and body carried (`page_number_strategy_test.rb`, six `PAGE-17` cases; guards 21, 22) |
| `PAGE-18` | MUST | ✅ | 6, 9 | `LinkHeader`, a character-level state machine with no `Regexp` (a source scan asserts it): a comma inside `<…>` and inside a quoted value does not split link-values, a semicolon inside a quoted value does not split parameters, quoted-pair escapes are honoured, `rel` may be unquoted, multi-token (space or tab) and any case (`NEXT`, `"prev  next"`, `"last\tnext"`), the token is `next` and not `nextish` or `prev-next`, the FIRST matching link-value wins, parameter names fold (`REL=next`), and only the FIRST `rel` parameter of a link-value is read — RFC 8288 §3.3's "occurrences after the first MUST be ignored", so `<u>; rel="prev"; rel="next"` is not a next link (P7-116); no header, no `rel=next` segment, an empty set and malformed input are all end-of-stream, never a raise (P7-115). `LinkStrategy.build(extract_items:, header: "Link")` reads the header under the fold and the name is configurable (`link_header_test.rb`, twelve cases; `link_strategy_test.rb` "PAGE-18", two cases; guards 23, 24, 47) |
| `PAGE-19` | MUST | ✅ (P7-3, P7-4, P7-104) | 2, 9 | `Dexpace::URL.resolve(base, reference)` wraps the pinned `URI::RFC3986_PARSER.join` (phase 1's file widened by one function, P7-3): base `/repo/issues?page=1` + `?page=2` → `/repo/issues?page=2`, the path preserved; `not a url`, `http://[bad` and whitespace answer nil. `Page.next_request_from(template, response, target)` — public, so a body-derived next URL reaches the same rules — answers nil for a nil target and for a same-document reference BEFORE resolution — the empty or whitespace-only target (`join(base, "")` is the base itself, P7-5) and, since review round 1, the fragment-only one (`<#>`, `<#top>`, `join(base, "#top")` is the base plus a fragment the wire never carries; RFC 3986 §4.4 names the two forms together, P7-117) — for an unresolvable one, and for one this client cannot dispatch: `mailto:`, `javascript:`, `ftp:`, `http:foo`, `http:///p`, every one a SUCCESSFUL join (P7-104, consistent with `REDIR-18`; no diagnostic, the engine has no logger); the base is the RESPONSE's request URL, not the template's. The same-document screen is syntactic — read off the raw target, never its resolution — so `<?>`, `<//>` (which uri resolves to the base itself) and the current URL spelled out are followed and bounded by `PAGE-9`'s cap, deliberately, and the suites pin that too (`http/url_test.rb` `ResolveTest`; `page_test.rb` `NextRequestFromTest`; `link_strategy_test.rb`, five `PAGE-19`/`P7-5`/`P7-104`/`P7-117` cases; guards 25, 26, 43, 49) |
| `PAGE-20` | SHOULD | ✅ | 6, 9 | Several `Link` instances are joined with `", "` and scanned as one (one `last` and one `next` in either order → next followed); `nil`, `[]` and `[""]` are no next link (`link_header_test.rb` "PAGE-20", "no rel=next segment and no header"; `link_strategy_test.rb` "PAGE-20") |
| `PAGE-21` | MUST | ✅ | 3 | `QueryRewriter.set` tokenises on `&` and the FIRST `=`, copies every untargeted segment as the bytes it found — `flag` stays value-less, `filter=a:b` keeps its colon, `a=b=c`, an empty segment and `%zz` survive — and re-encodes only the targeted name and value; `Dexpace::Query` is deliberately not used (`Query.parse(q).encode` rewrites `filter=a:b` to `filter=a%3Ab`, guard 27). **The half already built**: the codec is phase 1's `PercentEncoding`, shipped and tested. Asserted as byte identity of the untargeted SEGMENTS, plus a 128-sample property test (`query_rewriter_test.rb`, two `PAGE-21` cases and the property; guard 27) |
| `PAGE-22` | MUST | ✅ | 3 | `q='a b'` → `q=a%20b`; `token='a+b/c='` → `token=a%2Bb%2Fc%3D`; `get` of `q=a+b` → `a+b`, of `q=a%20b` → `a b`, of a flag → `""`, first match wins; the name is matched decoded (`pa%67e` is `page`). Ruby's `URI.decode_www_form` / `encode_www_form_component` are the exact inverse, measured on every row (`query_rewriter_test.rb`, three `PAGE-22` cases; `matrix_facts_test.rb` fact 5; guard 28) |
| `PAGE-23` | MUST | ✅ | 3, 9 | `set`: `page=1&sort=asc` → `page=2&sort=asc`; nil → `sort=asc`; duplicates dropped (`a=1&p=1&b=2&p=2` → `a=1&p=3&b=2`); absent → appended. Following a whole next URL is `template.with(url:)` through `Request.build`, so the template's `POST`, its headers and the SAME body object travel (`query_rewriter_test.rb` "PAGE-23"; `link_strategy_test.rb` "PAGE-23"; `page_test.rb` "PAGE-23") |
| `PAGE-24` | MUST | ✅ (P7-4) | 3 | `rewrite_url` `dup`s the URI and assigns the spliced query alone: `https://user:pw@api.example.com:8443/a/b?flag&page=1#frag` keeps scheme, userinfo, `8443`, `/a/b` and `frag` exactly; the caller's frozen URI is untouched; a URL with no query gains one before its fragment. `query=` is byte-transparent for every parser-produced query through the model's re-parse (fact 4, every printable ASCII byte, zero disagreements), and an empty splice is `nil` so the URL carries no dangling `?` (P7-4) (`query_rewriter_test.rb`, two `PAGE-24` cases and "P7-4"; `matrix_facts_test.rb` facts 4 and 7; guard 29) |
| `PAGE-25` | MUST | ✅ | 14 | The pump drives fetch, parse, delivery and re-arm inside `Future#on_settle` with no thread blocking on a page (the thread count is flat across a walk); cancelling the result future halts the walk at the next boundary and `Completer#on_cancel { @in_flight&.cancel(reason) }` cancels the in-flight transport future (`cancelled?` true on it; the late response then meets an already-settled completer and no second exchange is dispatched); a caller's `cancellation:` token is bridged to the same abort and its subscription detached when the walk settles (the source's hook list reads 0) (`async_paginator_test.rb` `CancellationTest` "PAGE-25", two cases; `ConstructionTest`, two token cases; guard 35) |
| `PAGE-26` | MUST | ✅ | 14 | A cancel from INSIDE the drain lets the current page finish (item 2 still delivered after a cancel at item 1) and stops at the boundary (no second exchange); a page parsed after the walk settled — the cancel lands inside `#parse`, deterministically — is dropped undrained AND closed through `Dexpace.close_quietly`, its close error swallowed, the future's outcome the cancellation and not the `IOError` (`async_paginator_test.rb` `CancellationTest`, two `PAGE-26` cases; guard 34) |
| `PAGE-27` | MUST | ✅ | 5, 14 | The `Page`'s own `Closeable` latch is the exactly-once, on whichever path consumes it: normal completion, parse failure (inline), cancellation (the staged drop) and executor rejection each close their response exactly once, asserted in one test over four un-latched `FakeResponseBody` counters; the page-level drain closes after the consumer returns, `[[0, 0], [1, 0]]` seen from inside (`async_paginator_test.rb` `TrampolineTest` "PAGE-27", "PAGE-27 (async, page-level)"; guard 38, a second close past the latch) |
| `PAGE-28` | MUST | ✅ | 14 | A consumer throw, a transport failure, a parse failure and an eagerly-throwing transport each fail the future with the ORIGINAL object (`assert_same` on the consumer's and the transport's error; phase 2's pivot wraps nothing); a transport answering a non-future fails the walk with `InvalidArgumentError` rather than a `NoMethodError`; a transport-side cancellation is forwarded as a cancellation carrying its reason (P7-109). **The null-success clause has a code site** — `Pump#null_success`, `SeamError` — although `Settlement`'s own validation makes it unreachable through any real future, so the suite drives the private pump with a duck settlement and reads the failed future; and a fatal-family consumer error fails the future AND propagates out of `#walk` unchanged, the page's response closed once (`RECOV-2`) (`async_paginator_test.rb` `FailureTest`, eight `PAGE-28` cases; guard 30) |
| `PAGE-29` | MUST | ✅ | 14 | Items are delivered one at a time in server order with a re-entrancy depth of exactly 1; with no executor the consumer runs on the settling thread (the walk completes on the caller's thread with no new thread); with an `executor:` the WHOLE driver is posted — the first dispatch too (P7-112) — so every consumer invocation runs on the executor's thread (`ProbeExecutor#drain`'s fresh thread, never the test's) and nothing is fetched until it runs (`async_paginator_test.rb`, two `PAGE-29` cases; guard 45) |
| `PAGE-30` | MUST | ✅ | 14 | `Pump#submit` wraps the one `#post` site: a rejection after two posts — the first dispatch and page 1's continuation — fails the walk with the rejection (`ProbeExecutor::Rejected`), closes the response it was carrying (page 2's `closes` 1) and delivers page 1's item only; a rejection of the FIRST post fails the walk before any exchange (`async_paginator_test.rb` `FailureTest`, two `PAGE-30` cases; guard 31) |
| `PAGE-31` | SHOULD | ✅ | 14 | The pump is 6a's re-arm-flag trampoline over `claim(:start | :continue)` under a mutex held across the flip only: 3,000 synchronously-completed pages through BOTH the inline path and an `InlineExecutor` leave `caller.size` at page 3,000 equal to page 1's. Measured through the real `Completer`: a pump that re-enters itself from `on_settle` overflows at 2,619 (3.2.11) / 2,847 (3.3.12, 3.4.10, 4.0.6) pages; guard 32 is that shape and raises `SystemStackError` (`async_paginator_test.rb` `TrampolineTest` "PAGE-31"; `matrix_facts_test.rb` fact 3; guard 32) |
| `PAGE-32` | MUST | ✅ | 14, 16 | `Pump#drain` closes the page whether the consumer returned or raised: on the success path a throwing close propagates into the fence and fails the future (`IOError` out of `Future#value`, within the deadline — never a hang); when the consumer already failed the close is `Dexpace.close_quietly`, the consumer's cause stays primary (`assert_same`) and the close error is swallowed, not attached (`Dexpace.suppressed` empty — the requirement's own word) (`async_paginator_test.rb` `FailureTest`, two `PAGE-32` cases; `lifetime_test.rb` "INVERSION, PAGE-32 (async)"; guard 33) |
| `PAGE-33` | MUST | ✅ | 14 | **Discharged by documentation, at `AsyncPaginator#walk`'s YARD** (and `docs/sdk-documentation/pagination.md`), with both halves given a code site: the first half — a response the transport delivers after the cancel settled its future never reaches the paginator — is phase 2's `Completer#fulfil` on a settled completer returning false and closing the response itself (`SEAM-30`), measured (`closes` 1, the consumer never invoked); the second — an already-dispatched request completing after the abort is closed and discarded — is `Pump#settled`'s settled check before the drain, `PAGE-26`'s drop. The race itself is not observable and is not tested (`async_paginator_test.rb` `CancellationTest` "PAGE-33", "PAGE-26: a page parsed after the walk settled") |
| `PAGE-34` | MUST | ✅ | 15 | `Fetchers.build(first:, next_page:, options:)`: the first fetcher is called exactly once per walk; the next-page fetcher is keyed off `previous.next_link`, falling back to `continuation_token` when the link is absent or blank (`["L"]` when both are present; `%w[T T2]` across two blank-link pages); a blank link with no token and a nil page from either fetcher end the stream; a nil first page is an empty stream; a fetcher's page owns its response and the walk closes it, the fetcher never does (`closes` 0 while the consumer holds it, 1 after); a non-`Page` answer is refused, and so is a page whose `next_link` or `continuation_token` is not a String — at `Page.build`, by name, before the front-end keys off it (P7-107; guard 46); the same `Items`/`Pages`/`each_item`/`each_page` surface over the same private `Walk`, uncapped (P7-111) (`fetchers_test.rb`, eight `PAGE-34` cases and "PAGE-1 / PAGE-12"; guard 36) |
| `PAGE-35` | SHOULD | ✅ vacuous by construction | 15 | **Design §12's own disposition, neither ⏳ nor 🚫**: the SHOULD is conditional on a MUTABLE paging-options object and the port offers a frozen `RequestOptions`. What the port supplies, stated: the SAME frozen instance is threaded to every fetcher that takes it, by identity (`assert_same` across both fetcher calls; arity decides — `-> { }` and `->(key) { }` are called without it), `Page#continuation_token` is the first-class per-page channel (`PAGE-34`) and a Ruby callable carries its own binding; the "mutation visibility" clause is documented as unobservable in `Fetchers`' YARD (`fetchers_test.rb` `OptionsAndViewsTest`, two `PAGE-35` cases; guard 37) |
| `PAGE-36` | MUST | ✅ | 10, 13, 14 | The paginator's frozen `options` is passed to the transport on EVERY exchange — `assert_same` on all three recorded calls, on both engines — and the default is `RequestOptions::EMPTY`, also by identity; a `Pipeline.standard` over a scripted transport receives `EMPTY` and `Cancellation.none` on each page. What 7c cannot assert — that an ADAPTER honours per-call options on pages 2..N — is phase 8a's: its plan's Task 13 carries the per-call-options conformance assertion and Task 20 wires it (`docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance.md`), and its checklist cross-references `PAGE-36`; no `docs/first-release.md` line is filed (`walk_test.rb` "PAGE-36"; `paginator_test.rb` "PAGE-36", "PIPE-26 / PIPE-27"; `async_paginator_test.rb` "PAGE-36 / PAGE-9"; guard 17) |

The non-ID row the charter and the design both require:

| Item | Status | What 7c did, and who owns the rest |
|---|---|---|
| Spec-forced boundary 5 / `R11` — the serde-isolation audit over `lib/dexpace/page/**` | owner elsewhere: **7b's Task 11** (`docs/work/mvp/phase7/phase7b/2026-09-10-phase7b-server-sent-events.md`, `tools/serde_boundary.rb` + `gates:serde_boundary`), by the manager's decision of 2026-09-20 | 7c builds no gate, no `tools/` file, no fixture and no `tasks/gates.rake` edit; 7b's tool ships a `PENDING` row for `gems/dexpace-core/lib/dexpace/page/**/*.rb` that whichever lane rebases second flips to `GUARDED`. Because 7b's constant scan does not strip comments, the tokens `Serde` and `JSON` appear NOWHERE under `lib/dexpace/page/` or in `page.rb` — YARD included; `R7`'s own sentence is spelled "a caller who wants a codec" — and `page_test.rb` "spec-forced boundary 5" scans the fifteen files for them as 7c's own guard until the row flips (P7-108). The plan's Task 1 Steps 2–4 and its resolved question 5 are recorded as a deviation below. **Reconciled 2026-09-20:** the row flipped — on the rebased code branch, one `chore:` commit moves the two `page/**` rows from `PENDING` to `GUARDED` and adds `page.rb` and `page.rbs` rows beside them (the `**` under a directory cannot match the file beside it, the reason `sse.rb` has its own row), each naming "spec-forced boundary 5" in its violation; `PENDING` is empty; the gate's test asserts it and both fixture workspaces gain clean page files; a `Dexpace::Serde` read in `page/info.rb` and a `require "json"` in `page.rb` each ran the gate red before being reverted. `page_test.rb`'s token scan stays as this phase's own guard beside it |

Cross-reference rows, the IDs this phase owns a share of:

| ID | Status | What 7c supplies, and where it is proven |
|---|---|---|
| `HTTP-46`, `HTTP-47` | ✅ widened | `Dexpace::URL.resolve(base, reference) -> URI::Generic?` beside `.parse!` and `.external_form` (P7-3): the one place the parser pin lives; the result frozen through the same private `own`; a String or URI base, a String reference (nil is the caller's mistake, named); `.parse!` untouched, so a relative `rel=next` target still cannot reach `Request` except through resolution (`http/url_test.rb` `ResolveTest`, six cases) |
| `HTTP-3`, `HTTP-4`, `SEAM-29` | ✅ | `Info`, `CursorStrategy`, `PageNumberStrategy`, `LinkStrategy`, `Paginator`, `AsyncPaginator` and `Fetchers` follow the construction pattern without exception: `.new` private, keyword `.build`, `Model.required!`'s one message form (`template is required`), validation in `initialize` so `#with` re-validates on the 3.2 floor (`paginator.with(cap: 0)` raises; `info.with(items: nil)` raises); `Page` and `Walk` are the two plain classes the plan names, because a `Data` cannot hold the latch (every suite's "HTTP-3" / "HTTP-4" case) |
| `HTTP-13` | ✅ | The one fold site is `LinkHeader#next_token?`'s `token.downcase == "next"` (plus the parameter-name fold and `Page.dispatchable?`'s scheme fold), every one the no-argument `downcase` the `Dexpace/NoLocaleCaseFold` cop enforces; `rel=NEXT` and `HTTPS://h/z` are the behavioural proofs (`link_header_test.rb`; `page_test.rb` "P7-104") |
| `PIPE-26`, `PIPE-27` | ✅ consumed | A `Pipeline.standard(scripted)` is handed to `Paginator.build` with no declaration, every page request runs through the three pillars, and the pipeline is never closed (`closed?` false after the walk) — which is also where a nil cancellation would have died (`paginator_test.rb` "PIPE-26 / PIPE-27") |
| `SEAM-11`, `SEAM-16` | ✅ consumed | The blocking engine calls `#call(request, options, cancellation)` for a `Response` and the async engine for a `Future`, against phase 6a's `ScriptedTransport` and `ScriptedAsyncTransport` (no socket, no `TCPServer`: roadmap constraint 4); an async transport that raises eagerly or answers a non-future is a failed walk (`PAGE-28`'s row) |
| `RECOV-12`, `SEAM-30` | ✅ consumed | `Dexpace.close_quietly` is the ONE swallow route, reached exactly where a requirement says swallow — `PAGE-26`'s drop, `PAGE-32`'s already-failed drain, `PAGE-30`'s rejected carry, the fatal-family parse close — and `Dexpace.attach_suppressed` the one trail writer (`Closing.close_walk`, `Walk#release`, `parse_or_close` through `close_quietly(onto:)`); the frozen-primary no-op (4b's P4-13) is stated in `Closing`'s and `Walk#release`'s YARD and asserted (`lifetime_test.rb` "the frozen-primary caveat") |
| `XCUT-9` | N/A here | 7c walks no `#cause` chain and calls `Dexpace.each_cause` nowhere; boundary 13 forbids hand-walking and does not require walking |
| `XCUT-11`, `XCUT-12`, `XCUT-15` | ✅ | `Paginator`, `AsyncPaginator`, `Fetchers` and the three strategies are frozen `Data`s with no lock and no per-call state; the per-walk state is a `Walk` (or a `Pump`) allocated per iteration; the pump's one mutex is held across the re-arm flag flip only; every collection a model holds is copied and frozen at construction (`paginator_test.rb` "PAGE-8: two threads"; `async_paginator_test.rb` "PAGE-31") |
| `SEAM-1` | ✅ | No new `require`: `uri` is named by `url.rb`, which `page.rb` requires, and was allowlisted before phase 1; nothing under `page/` requires a stdlib feature of its own (`gates:require_allowlist` green) |
| `NFR-4` | ✅ | Every addition is a widening: no existing signature moved. The manifest grew by exactly 77 rows, 1 137 → 1 214, read row by row against the object model — `Page` (`.build`, `.next_request_from`, six readers), `Info`, `QueryRewriter` (three `#` rows, `extend self`), the three strategies, `Items`, `Pages` (with `#more?`, `#closed?`), `Paginator`, `AsyncPaginator`, `Fetchers`, `PageStateError` and `URL#resolve`; no private constant, no `DIGITS`, no `DISPATCHABLE_SCHEMES`; the RBS baseline diff is vacuous until the first tag |
| `NFR-11` | ✅ | No constant outside `Dexpace::` and the stdlib allowlist in any public signature; `URI::Generic`, `Enumerable`, `Enumerator`, `Numeric` and `Thread::Mutex` are on it |
| `NFR-13` | ✅ for `.rb`; the `.rbs` half is phase 10's | The thirty-three new `.rb` files — fifteen under `lib/`, sixteen suites and two doubles under `test/` — open with the two headers the `Dexpace/SpdxHeader` cop gates; the fifteen new `.rbs` files carry no SPDX line, as no `.rbs` in the repository does (phase 10's `gates:spdx_rbs`), as 6a's and 6b's rows record |

## What was built

Fifteen new `lib/` files: `lib/dexpace/page.rb` (the page value, the namespace, `.next_request_from`
and the private dispatchability screen) and fourteen under `lib/dexpace/page/` — `page_state_error.rb`,
`info.rb`, `query_rewriter.rb`, `link_header.rb` (private), `cursor_strategy.rb`,
`page_number_strategy.rb`, `link_strategy.rb`, `walk.rb` (private), `closing.rb` (private),
`items.rb`, `pages.rb`, `paginator.rb` (with its private nested `Drive`), `async_paginator.rb` (with
its private nested `Pump`) and `fetchers.rb` (with its private nested `Drive`). One earlier file
widened in place, a designed widening: phase 1's `http/url.rb` gains `.resolve` beside `.parse!` and
`.external_form` (P7-3). `lib/dexpace.rb` gains a fifteen-line `# Phase 7c:` block after 6b's, in
dependency order. Every new file has a `sig/` mirror — the three private ones with `hooks.rbs`'s
comment, and the three nested private classes declared inside their owners' mirrors, because the strict
`core` Steep target types every call site — and `sig/dexpace/page.rbs` holds the three interfaces
`_Strategy`, `_Extractor` and `_Executor` nested in `class Page` (P7-106). Every public file has a
`test/` mirror; the two private ones with a mirror reach their constant through `const_get`
(`link_header_test.rb`, `walk_test.rb`, 4c's `cursor_test.rb` precedent) and `closing.rb` has none.
Two suites carry no `lib/` mirror and say so in their headers: `page/matrix_facts_test.rb` (Task 1's
facts as a standing test, 5a's through 6b's precedent, with the plan's Task 17 Step 4 `Fiber[]`
assertion) and `page/lifetime_test.rb` (Task 16, the inversion suite). Two new top-level test-support
doubles, one class per file: `PageFixtures` (the requests, real responses over `FakeResponseBody`, the
scripted strategy, the two engines and the walk every pagination suite uses) and `ProbeExecutor` (the
queued executor whose `#drain` runs the queue on a fresh joined thread, and the rejecting one, with
`Rejected` as its one error). No Response double: every response in the suite is a real
`Dexpace::Response` built through `Response.builder` (7a is creating `test/support/counting_response.rb`
concurrently and nothing of 7c's collides with or depends on it); no third scripted transport (6a's
`ScriptedTransport` and `ScriptedAsyncTransport` as they are, the latter's `settle_later:` and
`#settle_next!` being exactly `PAGE-25`/`PAGE-26`'s hold-and-release); phase 2's `InlineExecutor` is
the inline executor. Two existing tests changed: on the **code** branch, the smoke suite
(`gems/dexpace-core/test/dexpace_test.rb`, a pin the surface and layer gates read) gains
`PAGE_LAYER = %i[Page]` and a `PhaseSevenLayers` class (the eleven public constants under `Page`, the
six private names unreachable, the fourteen nested names shadowing nothing at the top level or flat
under `Dexpace` — Task 17's shadowing audit as a standing test); on the **tests** branch, phase 1's
`http/url_test.rb` gains a nested `ResolveTest` for the widened `URL.resolve` (`Style/OneClassPerFile`
being live) — a new test over a new function, not an invalidated pin, so the layering rule puts it
there. The surface manifest was regenerated once, 1 137 → 1 214, and all 77 rows read against the
object model (the `NFR-4` row).

## Matrix facts, re-run on every interpreter

The plan's eight facts and the cross-check's were run on 2026-09-20 on **3.2.11, 3.3.12, 3.4.10 and
4.0.6**, first as a scratch script per interpreter and then as `page/matrix_facts_test.rb`, a standing
test on every CI row (thirteen cases). Every fact holds identically on every row, uri 0.12.5 (the
version `gates:clean_bundle` loads on 3.2.11), 0.13.3, 1.0.4 and 1.1.1 alike; the only things that
differ are `Hash#inspect`'s spelling and `NoMethodError`'s message, neither asserted. A close error
raised from an `ensure` reaches the caller unwrapped through `Enumerable#first`, `Lazy#first(2)`, an
explicit `break` and a plain block, and a raising `ensure` REPLACES an in-flight consumer error as the
primary (its `#cause`); **`$!` is the caller's inside a method called from the caller's rescue** — the
fact the plan's `R8` prescription did not weigh (P7-105); a re-arm loop over 20,000 inline-settled
futures is flat where a pump re-entering itself from `on_settle` overflows at 2,619 (3.2.11) or 2,847
(the other three) pages through the real `Completer`; `query=` round-trips every parser-produced query
for every printable ASCII byte through `Request#with`'s re-parse (the canonicalising happens at PARSE
time, on exactly space, `"`, `#`, `'`, `<`, `>` and `` ` ``); `URI.decode_www_form("q=a+b")` is
`[["q", "a b"]]` and `encode_www_form_component("a b")` is `"a+b"`; `join` resolves `mailto:a@b`,
`javascript:alert(1)`, `http:foo` and `http:///p` successfully to a nil or empty host; `query = nil`
removes the query and `query = ""` leaves a dangling `?`; `Fiber[]` is visible inside an `Enumerator`'s
internal fiber, which is created at the FIRST pull, so a correlation value set after construction and
before the first pull IS seen by the walk and one set after the first pull is not; `Model.own` deep-copies
and freezes elements and raises on a Proc; a `Data` holds no instance variables; `Completer#fulfil` on a
cancelled completer returns false and closes the response itself; and a nil cancellation dies with
`NoMethodError` inside `Pipeline.standard`'s retry step. 6b's `redirect/matrix_facts_test.rb` already
pins the join facts this phase rests on (a query-only reference preserves the path; `join(base, "")`
answers the base; `join(base, nil)` raises `ArgumentError`; `join` raises on a space and on nothing
else) and is cited rather than re-asserted.

## Guards run red

Every guard the brief asks to be seen red was seen red, on 4.0.6 and on 3.2.11, and the bytes
restored after each: **forty-nine single-edit mutations of `lib/`** — the reviewer's thirty-nine,
six of this build's, two added in review round 1 for the two fixes it made (46, 47) and two in review
round 2 (48, the reviewer's surviving mutation 73, now caught; 49, the fragment-only half of the
same-document screen dropped) — one at a time through a harness that applies the edit in a scratch
copy of the tree, runs the owning suites under `ruby -w`, captures the first failure and restores the
file. Two mutations were re-spelled to keep a variable live, because their first spelling crashed the
suite on an unused-variable warning (`FatalWarnings`, `NFR-6`'s rule firing before any assertion)
rather than on an assertion: guard 3 (`previous.nil?` in place of the deleted close) and guard 40
(`$! || primary` in place of `$!` alone). **Forty-nine of forty-nine are caught on 4.0.6 and
forty-nine of forty-nine on 3.2.11; no equivalent mutant.** Round 2 also ran the reviewer's 5, 8, 26
(re-spelled against the round-2 source, the whole pre-resolution guard skipped) and 43, the
neighbours of the two edits, and one negative mutation — the same-document screen moved onto the
RESOLVED URL, which the "deliberately not screened" pins in `page_test.rb` and
`link_strategy_test.rb` turn red — all caught on both rows. The plan's guard 4 ("let `Walk#buffer`
overwrite a staged page") is unreachable through `Pages#more?` as built — the probe reads a staged
page before it would ever call `#buffer` — so the mutation applied is the reachable one, dropping
that early return; `Walk#buffer`'s own refusal is `walk_test.rb`'s "never displaced" case. The plan's
guard 38 ("close the page both in the drain `ensure` and after it") is absorbed by the `Page`'s own
latch — which IS `PAGE-27`'s mechanism — so the mutation applied closes the RESPONSE a second time
past the latch.

| # | Fix reverted | Guard | What it said (4.0.6; identical on 3.2.11 unless stated) |
|---|---|---|---|
| 1 | `PAGE-11`: `page.close` moved after the items are yielded | `items_test.rb` | `PAGE-11: the page is closed BEFORE any of its items is yielded` — `Expected: [1, 1] Actual: [0, 0]` (5 failures) |
| 2 | `PAGE-11`: the eager `page.close` deleted | `items_test.rb` | `Items#close releases nothing …` — `Expected: 1 Actual: 0`; "taking one item … closes it" (6 failures) |
| 3 | `PAGE-12`: `Walk#hold` does not close the previous page | `pages_test.rb` | `PAGE-15: a close error while ADVANCING is surfaced` — nothing raised; "the previous page is closed as the consumer advances" `[[0,0,0],[0,0,0],[0,0,0]]` (5 failures) |
| 4 | `PAGE-12` / `PAGE-6`: a second `Pages#more?` re-fetches instead of reading the staged page | `pages_test.rb` | `PAGE-6 / PAGE-12: a second probe costs no exchange and strands no page` — `Dexpace::Page::PageStateError: a page is already staged` (1 error) |
| 5 | `PAGE-12`: `@buffered` dropped from `Walk#release` | `pages_test.rb` | `Expected: [1, 0, 0] Actual: [0, 0, 0]`; "probing without advancing, then closing, releases the prefetched page" (3 failures) |
| 6 | `PAGE-15`: the advance close made `close_quietly` | `pages_test.rb` `SurfacedCloseTest` | `PAGE-15: a close error while ADVANCING is surfaced, not swallowed` — `IOError expected but nothing was raised` |
| 7 | `PAGE-13` / `PAGE-15`: `Closing.close_walk` ignores the primary (a bare close) | `lifetime_test.rb` | `INVERSION, PAGE-13: … the CONSUMER's error is primary` — `[KeyError] exception expected, not Class: <IOError>` (3 failures) |
| 8 | `PAGE-15`: the FIRST close failure attached to the second, the second raised | `lifetime_test.rb`, `walk_test.rb` | `Expected: "first" Actual: "second"` (2 failures) |
| 9 | `PAGE-13`: the inline close on parse failure removed | `walk_test.rb` | `Expected: 1 Actual: 0` on `closes`; "a close failure does NOT mask" `Expected: [IOError] Actual: []` (2 failures) |
| 10 | `PAGE-13`: the close error propagates over the parse failure | `walk_test.rb` | `[KeyError] exception expected, not Class: <IOError>` |
| 11 | `PAGE-14`: the `@viewed` latch removed | `pages_test.rb` `SingleUseTest` | `Dexpace::Page::PageStateError expected but nothing was raised` (2 failures) |
| 12 | `PAGE-8`: the `Walk` cached on `Items` | `items_test.rb` | `Expected: 4 Actual: 2` transport calls; the interleaved case `StopIteration` (2 failures, 1 error) |
| 13 | `PAGE-8`: one `Walk` shared across `paginator.pages` calls | `pages_test.rb` | `Expected: 4 Actual: 2`, and 12 more failures as every view shares one walk |
| 14 | `PAGE-7`: the exhaustion latch dropped and the drive restarts from the template | `walk_test.rb` | `ScriptedTransport: script exhausted after 2 calls` — the walk fetched on (1 error) |
| 15 | `PAGE-9`: the cap compared with `>` | `walk_test.rb` | `Expected: 3 Actual: 4` transport calls |
| 16 | `PAGE-9`: the positivity check removed from `initialize` | `paginator_test.rb` | `Dexpace::InvalidArgumentError expected but nothing was raised` at construction and on `#with` (2 failures) |
| 17 | `PAGE-36`: `RequestOptions::EMPTY` from page 2 onward | `walk_test.rb` | `Expected … RequestOptions timeout=1.5 … to be the same as … EMPTY` on call 2 |
| 18 | `PAGE-6`: the first fetch performed inside `Paginator#items` | `paginator_test.rb` | `PAGE-6 (blocking engine): … ZERO exchanges` — `Expected: 0 Actual: 1` (3 failures, 6 errors) |
| 19 | `PAGE-6` (async): the first dispatch never submitted from `#start` | `async_paginator_test.rb` | `Expected: 1 Actual: 0` calls after `walk`, and every walk hangs to its deadline (13 failures, 13 errors) |
| 20 | `PAGE-16`: `""` treated as a real cursor | `cursor_strategy_test.rb` | `Expected nil, not #<data Dexpace::Request …cursor=…>` |
| 21 | `PAGE-17`: the current page read from the template | `page_number_strategy_test.rb` | `Expected: "page=6" Actual: "page=2"` (3 failures) |
| 22 | `PAGE-17`: the empty-items check removed | `page_number_strategy_test.rb` | `Expected nil, not #<data Dexpace::Request …page=5>` |
| 23 | `PAGE-18`: link-values split on every `,` | `link_header_test.rb` | `Expected: "https://x/p?a=1,2" Actual: nil` |
| 24 | `PAGE-18`: `rel` compared whole and case-sensitively | `link_header_test.rb` | `Expected: "https://x/2" Actual: nil` on `rel=NEXT` (2 failures) |
| 25 | `PAGE-19`: the target parsed with `URL.parse!` instead of resolved | `link_strategy_test.rb` | `Dexpace::InvalidArgumentError: url "?page=2" is not an absolute URI (HTTP-47)` (3 errors) |
| 26 | P7-5: the blank-target guard skipped | `link_strategy_test.rb` | `Expected nil, not #<data Dexpace::Request …issues?page=1>` — the base itself |
| 27 | `PAGE-21`: the splice routed through `Query.parse(q).encode` | `query_rewriter_test.rb` | `Expected: "a=b=c&&x=%zz&page=2" Actual: "a=b%3Dc&x=%25zz&page=2"`; `filter=a%3Ab` (4 failures) |
| 28 | `PAGE-22`: values encoded with `URI.encode_www_form_component` | `query_rewriter_test.rb` | `Expected: "q=a%20b" Actual: "q=a+b"` (2 failures) |
| 29 | P7-4: an empty splice answered as `""` | `query_rewriter_test.rb` | `Expected nil, not ""`; `https://x/a?` |
| 30 | `PAGE-28`: the consumer's error wrapped in `SeamError` | `async_paginator_test.rb` `FailureTest` | `[KeyError] exception expected, not Class: <Dexpace::SeamError>` (7 failures) |
| 31 | `PAGE-30`: the carried response not closed when `#post` raises | `async_paginator_test.rb` `FailureTest` | `Expected: 1 Actual: 0` on the staged page's `closes` (2 failures) |
| 32 | `PAGE-31`: the pump launches the next page directly from the settlement | `async_paginator_test.rb` `TrampolineTest` | `SystemStackError: stack level too deep` inside the 3,000-page walk |
| 33 | `PAGE-32`: the success-path close made quiet | `async_paginator_test.rb` `FailureTest` | `IOError expected but nothing was raised` — the future fulfilled |
| 34 | `PAGE-26`: the settled check before the drain removed | `async_paginator_test.rb` `CancellationTest` | `dropped pages are never drained` — the consumer was invoked after the cancel |
| 35 | `PAGE-25`: `completer.on_cancel { in_flight&.cancel }` dropped | `async_paginator_test.rb` | `Expected #<Dexpace::Async::Future> to be cancelled?` on the in-flight future (2 failures) |
| 36 | `PAGE-34`: the continuation token keyed before the next link | `fetchers_test.rb` | `Expected: ["L"] Actual: ["T"]` |
| 37 | `PAGE-35`: the second fetcher handed `options.dup` | `fetchers_test.rb` `OptionsAndViewsTest` | `Expected … to be the same as …` on the second fetcher's options |
| 38 | `PAGE-27`: the response closed a second time past the page's latch | `async_paginator_test.rb` `TrampolineTest` | `Expected: [1, 1, 1, 1, 1] Actual: [2, 2, 1, 1, 1]` (2 failures) |
| 39 | `PAGE-3`: `Page#close` bypasses the latch | `page_test.rb` | `Expected: 1 Actual: 3` closes; the raising close retried (2 failures) |
| 40 | P7-105: the primary read off `$!` instead of the recorded local | `lifetime_test.rb` | `CALLER'S RESCUE, PAGE-15 (P7-105)` — `IOError expected but nothing was raised` inside the caller's rescue; and the source scan (2 failures) |
| 41 | `PAGE-14` / P7-103: `InvalidArgumentError` raised instead of `PageStateError` | `pages_test.rb` `SingleUseTest` | `[Dexpace::Page::PageStateError] exception expected, not Class: <Dexpace::InvalidArgumentError>` (2 failures) |
| 42 | P7-102: `nil` passed as the transport's cancellation | `walk_test.rb`, `paginator_test.rb` | `NoMethodError: undefined method 'check!' for nil` out of `Pipeline.standard`'s retry step; `Expected Cancellation.none to be the same as nil` (1 failure, 1 error) |
| 43 | P7-104: the dispatchability screen dropped | `link_strategy_test.rb`, `page_test.rb` | `Expected nil, not #<data Dexpace::Request …mailto:a@b>` (2 failures) |
| 44 | `PAGE-4`: a raising extractor rescued and read as end-of-stream | `cursor_strategy_test.rb` | `KeyError expected but nothing was raised` (2 failures) |
| 45 | `PAGE-29`: the consumer invoked inline instead of through the executor | `async_paginator_test.rb` | `Expected #<Set: {#<Thread:… main>}> to be empty` — the consumer ran on the test's thread; the rejection cases (4 failures) |
| 46 | `PAGE-34` / P7-107 (round 1, R0-1): `Page#initialize` stores `next_link` and `continuation_token` unchecked | `page_test.rb`, `fetchers_test.rb` | `Dexpace::InvalidArgumentError expected but nothing was raised`; `Expected "L" to be frozen?`; `[Dexpace::InvalidArgumentError] exception expected, not … NoMethodError` out of the fetcher walk (3 failures) |
| 47 | P7-116 (round 1, R0-3): `LinkHeader#next_target` honours ANY `rel` parameter (`params.any?`) | `link_header_test.rb` | `Expected "https://x/1" to be nil` on `rel="prev"; rel="next"` |
| 48 | `PAGE-15` (round 2, R1-1; the reviewer's mutation 73): `Walk#release` clears its two slots only AFTER a successful close, past the raise | `walk_test.rb` `SlotsTest`, `pages_test.rb` `SurfacedCloseTest` | `Expected #<Dexpace::Page …> to be nil` on `walk.current` after the raising close; `Expected #<Dexpace::Page::Pages …> to not be more?` on the closed view (2 failures) |
| 49 | P7-117 (round 2, R1-2): the fragment-only half of `same_document?` dropped, `<#>` resolved and followed | `page_test.rb` `NextRequestFromTest`, `link_strategy_test.rb` | `Expected #<data Dexpace::Request …items?page=1#> to be nil` (2 failures) |

## Audit groups run

The phase-start pair first, at implementation: `--origin note --brief` returned entries across 22
note files (`pipeline/86343352`, `pipeline/7ce4431d`, `error-handling/5322e965`,
`execution-context/b58728da` and `url-and-query-encoding/08c54234` read in full, the five the brief
binds); `--section conflicts --brief` returned six harvested conflicts, every one
`[overridden by notes/…]`, none open. The audit group's `PAGE` slice, `--prefix PAGE --section rules
--brief`, returned 36 entries across three topic files, **zero tagged `[appendix-B roll-up]`**,
covering 33 of the 36 (`PAGE-16`, `PAGE-17`, `PAGE-18` filed under Reference, read with `--req`, whose
substantive entries `pagination/3174b6ac`, `3422b2f6` and `f4b0a107` are the three strategies' rules
verbatim); chapter 12 was read in full, its `*Conformance:*` clauses included, because `PAGE-12`'s
two-shape and `PAGE-27`'s four-path clauses are each two or four tests for one row. `--req PAGE-14`
confirmed the SSE-under-`PAGE-14` pair (`sse-streaming/5f4803a0`, `b94ce49e`) and `--req BODY-11
--origin note` the `pagination/b2a85752` attribution, both now recorded in
`docs/knowledge/notes/pagination.md` (Findings routed).

| Group | Result at implementation |
|---|---|
| Public API surface | `module-organization/1828a984` (one public constant per file) holds for every new file — the three nested private classes are `private_constant`s of their owners, 6a's `Pump` precedent; `api-design/b0e18938` is why `DIGITS` and `DISPATCHABLE_SCHEMES` are private, why no engine exposes a logger or a reader beyond its `Data` members, and why `Page.next_request_from` is the ONE public function the design argues for rather than three private re-derivations; every public name is in the design's object model or in P7-103, P7-106 and P7-109 |
| RBS / Steep typing | Fifteen new mirrors and one widened (`url.rbs`), the strict target green with no relaxation; `transport`, `strategy`, `extract`, `extract_items`, `executor`, `first`, `next_page` and the views' opener are `untyped` because a lambda is a valid value (`respond_to?` validates each); the three interfaces are nested in `class Page` and validate under rbs 4.2.0; `include ::Enumerable[untyped]` and the two-overload `each` are core's first, and validate; every `URI::RFC3986_PARSER` site writes `#: untyped` as `url.rb` does; one `#: Exception` on `Settlement#error` in the forwarding arm |
| Minitest conventions | Every suite subclasses `DexpaceTestCase`; the async suite is four nested classes, the pages, walk, fetchers, lifetime and matrix-facts suites two each, under `Metrics/ClassLength` (6b's shape); `assert_same` wherever identity is the claim (the same options, the same body, the same error object); every `URI::InvalidURIError` asserted by class; no `Hash#inspect` asserted; `sample(count: 128)` is the property test's driver; every thread a test or a double starts is joined (`ProbeExecutor#drain`) |
| Fiber scheduler, thread safety | The engines are frozen and hold no per-walk state; the one mutable object per walk is the private `Walk` or `Pump`; the pump's mutex is held across the re-arm flip only; no thread started by `lib/`, no wait, no scheduler read (a source scan pins `Async.delay`, `.sleep`, `Fiber.scheduler`, `Thread.new` absent); `Fiber[]`'s first-pull snapshot asserted |
| Serialization, SSE and pagination | Every `PAGE` rule in the group restates a clause implemented above; `pagination/f57c50f6` prints `[overridden by notes/pagination.md:10]` and the build wrote no resource into an `Enumerator` block or a `#each` local; the two SSE rules the group returns under `PAGE-14` are 7b's and 7c neither consumes nor duplicates them (the error family is shared by construction, P7-103); no `SERDE` rule binds, because 7c names no serializer |

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate. Items
1–19 are where the built tree overrode the plan's assumptions, in the order the brief's as-built list
gives them; 20–30 are this build's, 31 is review round 1's and 32 is review round 2's. The ones that
touch public behaviour, the contract a later phase cites, or a statement the design makes are also the
as-built ledger rows P7-101–P7-117.

1. **Nothing was installed.** All four interpreters were present; the plan's Task 1 Step 1 and the
   design's "the only interpreter installed" were stale. The facts were re-run on every row and live in
   `page/matrix_facts_test.rb`, the per-phase convention since 5a; Task 17 Step 4's `Fiber[]`
   assertion is there rather than in `lifetime_test.rb`.
2. **Every private constant has a `sig/` mirror, and there is no `sig/dexpace/page/strategy.rbs`**
   (P7-106): `test/gates/gem_layout_test.rb` maps `lib/` to `sig/` one for one, so the design's
   "carry no `sig/`" and the plan's sig-only interface file both fail `test:gates`. The interfaces
   live in `sig/dexpace/page.rbs`, nested in `class Page`; `walk.rb` and `link_header.rb` keep test
   mirrors through `const_get`, `closing.rb` has none and joins `CLAUDE.md`'s exception list.
3. **The doubles as built were reused, and no Response double was written**: 6a's
   `ScriptedTransport` / `ScriptedAsyncTransport` (the plan's `CountingTransport`), 3b's
   `FakeResponseBody` with its un-latched `#closes` and 4b's `RecordingBody` with its `source_count`
   (the plan's `ClosingProbe`), phase 2's `InlineExecutor` (the plan's `ProbeExecutor(mode: :inline)`).
   The two new doubles are top level, one class per file: `PageFixtures` (all of the plan's fixture
   helpers, over a stateless `ScriptedStrategy` that reads the page index off the executed request's
   `p` parameter and a transport script of callables that build each response around the request the
   engine actually sent — so `response.request` is real) and `ProbeExecutor` (`:queued` with a
   thread-running `#drain`, `:rejecting` with `after:`; `Rejected` its one error).
4. **The sync engine passes `Dexpace::Cancellation.none` to the transport, never `nil`** (P7-102); it
   takes no `cancellation:` keyword in v1, per the manager's decision.
5. **`RequestOptions.build` takes all three keywords**, so the plan's `.build(timeout: 1.0)` is
   `RequestOptions.builder.tap { |b| b.timeout = 1.0 }.build`, 8a's spelling.
6. **`Model.own` is not called on the items** (P7-101); the plan's `instance_variables - %i[@extract
   @parameter]` assertion is the truthful `assert_empty(strategy.instance_variables)` plus
   `frozen?`, because a `Data` holds no ivars.
7. **RuboCop 1.91 under `NewCops: enable` shaped the fences**: no `$!` (P7-105; the 6b
   `rescue ::Exception => error` shape, the one inline disable per site); `=> error` everywhere; a plain
   `def resolve` inside `URL`'s `extend self`; `Dexpace::Page.next_request_from` is `def
   self.next_request_from`; `::Thread::Mutex`; `items.each(&)`; every method under the length, ABC and
   complexity caps by splitting (`QueryRewriter#splice`, `Info#optional_string`, the engines'
   `validate_engine!`, `LinkHeader`'s seven small scanners); `Metrics/ClassLength` recorded inline
   with its reason on `Pump` alone (6a's shape); the suites split into nested classes; the plan's
   `DexpaceURLResolveTest` is the nested `ResolveTest`; `assert_predicate` for every `more?`; no
   `Lint/UnreachableLoop` (`break if page.items == [1]`); the YARD gate at 100.00%, every
   `attr_reader` on its own line with its own `@return`.
8. **`Dexpace::URL.resolve` freezes through the private `own`, takes a String or URI base, requires
   a String reference (nil is `InvalidArgumentError`, never a silent end-of-stream), and does NOT
   screen dispatchability** — the screen is `Page.next_request_from`'s (P7-104), 6b's `dispatchable?`
   copied because `Redirect::Location` is a `private_constant`. `SEAM-27`'s composition in
   `Dexpace::Operation` is untouched and unrelated.
9. **The splice was measured through the real path** (`dup` / `query=` / `with(url:)` / `URL.parse!`)
   on every row, not `query=` alone: zero disagreements, the seven bytes canonicalised at parse time.
10. **The trampoline's hazard was measured through the real `Completer`**: ~2,600 frames, not ~11,000;
    the pump is 6a's `Pump` in shape, the `PAGE-31` test measures `caller.size` across 3,000 pages
    through both paths, and every callback body is total (a raising `on_settle` block escapes
    `Completer#fulfil` through `Hooks.notify`'s re-raise).
11. **`PAGE-33`'s two halves have two code sites**, one of them phase 2's (`Completer#fulfil` on a
    settled completer), named in `#walk`'s YARD and in the row.
12. **The async token plumbing is 6a's**: `completer.on_cancel { @in_flight&.cancel(reason) }`, a
    caller's token bridged with `on_cancel { |reason| @completer.request_cancel(reason) }` and detached
    on settle; a transport-side cancellation forwarded as a cancellation (P7-109).
13. **`Future#value(deadline:)` is the bounded wait**; no `Timeout_free_value` helper.
14. **Phase-1 and phase-2 surfaces as built**: `Request.build(method:, url:, headers:, body:)` with an
    OUTBOUND `Headers`; `Headers#[]` the frozen list under the fold; `Page.build` checks
    `response.is_a?(Dexpace::Response)` (P7-107); `Dexpace.attach_suppressed`'s frozen-primary no-op
    stated and asserted.
15. **No gate, no fixture, no `tasks/gates.rake` edit for boundary 5** (P7-108): the plan's Task 1
    Steps 2–4 and resolved question 5 are superseded by the manager's decision; 7b's Task 11 owns it,
    and 7c's own guard is `page_test.rb`'s token scan. `R7`'s sentence is spelled "a caller who wants a
    codec" in every YARD block.
16. **`lib/dexpace.rb`'s block is fifteen lines**, the design's fourteen plus `page/page_state_error`
    (P7-103), in the order given, `page` first.
17. **The smoke suite gained `PAGE_LAYER = %i[Page]` and a `PhaseSevenLayers` class** with the
    constants pin, the six private names and the fourteen-name shadowing audit; the manifest was
    regenerated once, +77 rows.
18. **The RBS validates as the plan wanted**, `include ::Enumerable[untyped]` and the nested
    interfaces included; nothing outside `STDLIB_ALLOWED` is named.
19. **The design's four findings were verified at their owners** (Findings routed): `C13`, the two
    corpus corrections and the harvest gap (now notes), 8a's `PAGE-36` conformance tasks; nothing
    re-filed in `docs/first-release.md`, `docs/deviations.md` or the roadmap's inbound list for them.
20. **`Info` and `Page` validate `next_link` and `continuation_token` as `String` or nil** and copy
    them frozen; `Info.terminal` is the named factory the design asks for. (`Page`'s half of this
    sentence was false at review round 0 — only `Info` checked — and is true since round 1's fix,
    R0-1, guard 46.)
21. **The extractor's answer shape is checked** (P7-107) — the plan's fences destructured it blindly.
22. **`Pages#more?` returns `true` on a staged page before touching the walk**, `Walk#buffer` raises
    `PageStateError` rather than the plan's `InvalidArgumentError` on a second staged page, and
    `Walk#hold` writes the new page into the slot BEFORE closing the previous one (P7-105's second
    half): the plan's `release_current` cleared `@current` first and would have stranded the page
    being advanced to when the previous close raised.
23. **`Closing` is `extend self` with two functions** — `close_walk(walk, primary)` and
    `parse_or_close(strategy, response, template)` — rather than the plan's included mixin, so the
    two engines' drives and the async pump call the same two lines; `parse_or_close` also refuses a
    non-`Info` answer and closes on the fatal family (P7-110).
24. **The `Walk` is generic over a drive** (P7-111); `Items.new` / `Pages.new` take the engine's walk
    factory (a `Method` object), validated `respond_to?(:call)`.
25. **`Paginator#each_item` / `#each_page` (and `Fetchers`') require a block** and return nil; they
    delegate to the views, whose `#each` carries the ensure.
26. **`Pages#each` without a block claims the latch on obtaining the enumerator** (P7-113) through
    `to_enum(:drive)` over a private method (works on every row, verified), and `#closed?` is exposed
    beside `#close` and `#more?`.
27. **The async engine posts the first dispatch through the executor too** (P7-112); a rejected first
    post fails the walk before any exchange; the future settles with the page count (P7-109).
28. **`PageNumberStrategy`'s screen is `[0-9]+`, private** (P7-114); `LinkHeader`'s malformed-input
    rule and its parameter-name fold (P7-115).
29. **Fetcher arity is read through `Registry.callable?`** — `arity: 1` for the first fetcher,
    `arity: 2` for the next-page one — so a `-> { }` and a `->(key) { }` are called without the
    options and their two-parameter forms with it; a non-`Page` fetcher answer is refused (P7-107).
30. **`CLAUDE.md`'s counts are re-derived from the tree on top of `main`**: 199 `lib/dexpace/` files
    beside `version.rb`, nineteen `private_constant` test-mirror exceptions (`page/closing.rb` joins),
    fifteen checklists, `phase7/phase7c/` holding a checklist; the lib-file count was counted by hand
    because the probe does not read it. *Reconciled 2026-09-20:* on top of `main` with 7b, the same
    hand count gives 208, the exceptions stay nineteen, and the checklists are sixteen.
31. **`LinkHeader` reads only the first `rel` parameter of a link-value** (P7-116; review round 0's
    R0-3): RFC 8288 §3.3 says `rel` MUST NOT appear more than once and occurrences after the first MUST
    be ignored, and the first build's `params.any?` honoured a later one. `PAGE-18`'s own words ("the
    first link-value whose `rel` parameter contains the token `next`") do not decide the case; the RFC
    does, and the strict reading is the one that cannot follow a link the server marked `prev`.
32. **A fragment-only `rel=next` target is end-of-stream before resolution, as the empty one is**
    (P7-117; review round 1's R1-2). The design's P7-5 screened the empty and whitespace-only target
    because `join(base, "")` answers the base itself; `join(base, "#frag")` answers the base plus a
    fragment the wire never carries, so `<#>; rel=next` re-fetched the current page until the cap,
    which defaults to unbounded. RFC 3986 §4.4 names the two forms together as the same-document
    references whose dereference "should not result in a new retrieval action", and the guard now
    reads both off the raw target through a private `Page.same_document?`. It stays syntactic: `<?>`,
    `<//>` (uri resolves it to the base itself, measured on every row and under uri 0.12.5) and the
    current URL spelled out are next requests like any other, bounded by `PAGE-9`'s cap — a screen on
    the resolved URL would silently end a walk against an endpoint that advances server-side state
    under one URL, with no knob to turn it off — and the suites pin that they are followed.

## Findings routed

- **The design's four findings were verified at their owners and not re-filed.** (1) `PAGE-15`'s
  wrapping-clause vacuity: `docs/first-release.md`'s fourteen-corrections blocker already lists it as
  `C13` ("§12's `PAGE` row recording one vacuity fewer … `PAGE-15`'s wrapping clause and `7c P7-1`"),
  `docs/deviations.md` carries the interim note and the roadmap's phase-10 inbound list the
  fold-into-§10 bullet — the `PAGE-15` row cites `C13` and edits none of the three. (2)/(3) The two
  corpus corrections — the SSE-under-`PAGE-14` defect is a PAIR (`sse-streaming/5f4803a0` and
  `b94ce49e`), and `pagination/b2a85752` carries `BODY-11` rather than no ID — are new `## Reference`
  entries in `docs/knowledge/notes/pagination.md` (sha markers `manual-phase7c-sse-under-page14`,
  `manual-phase7c-b2a85752-carries-body11`), beside a third for §12's unharvested serde-agnosticism
  (`manual-phase7c-serde-agnosticism-unharvested`) and a fourth adding P7-105's `$!` finding to the
  pipeline note it rests on (`manual-phase7c-r8-without-dollar-bang`); never an edit to `harvested/`,
  and `verify_knowledge_structure.rb` is OK (60 notes). (4) `PAGE-36`'s per-call-options conformance
  test is 8a's plan, Tasks 13 and 20, already carrying the assertion and its wiring — the `PAGE-36`
  row cites them and no `docs/first-release.md` line is filed. The knowledge-lookup skill's audit
  table already has the "Serialization, SSE and pagination" row; the design's "owed a thirteenth row"
  is discharged.
- **Routed to 8b's plan, Task 9** (`docs/work/mvp/phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter.md`):
  the correction that `Dexpace::Page::_Executor` lives in `sig/dexpace/page.rbs`, nested in
  `class Page`, not in `sig/dexpace/page/strategy.rbs` — one sentence added at the point that plan
  names the file; the interface's name and `def post: () { () -> void } -> void` are exactly as
  `bridge/async_over.rb:61`, `docs/deviations.md:63` and that plan already cite.
- **Already routed, cited and not re-filed**: the `PAGE-14`/`SSE-26` error-family bullet on phase 10's
  inbound list (2026-09-13) — its argument-family half is closed by P7-103 and its shared-supertype
  half stays on the list, which the roadmap's 7c status note says; the three-spellings replayability
  predicate and the two scripted transports' reconciliation (6b's and 6c's), which 7c touches not at
  all.
- **The design's ledger** gains an "As built" addendum (P7-101–P7-117); the consolidation of P7-1–P7-6
  and P7-101–P7-117 into design §10 — beside 7a's and 7b's rows, whose P7-1–P7-9 collide with this
  design's by number, knowingly — and the addition to §12's `PAGE` row are a human's, as for 3a
  through 6c, because `docs/sdk-design-ruby/` is frozen. `docs/deviations.md` is untouched, for phase
  10 to flip.
- **A finding in material this phase may write was fixed rather than filed**: the root `README.md`'s
  built-phases sentence omitted 6b although the same paragraph describes the redirect layer; 6b is
  added beside 7c (the docs PR says so).

## Postponed work

**None of this phase's own.** Every one of the 36 IDs is implemented — 35 outright and `PAGE-35` as
vacuous by construction on design §12's authority — and design §12's `PAGE` row's "*Deferred:* none"
is confirmed. **What this phase leaves to others, none of it its own to defer**: the boundary-5 gate
row for `page/**` (7b's Task 11 ships it `PENDING`; whichever lane rebases second flips it to
`GUARDED`); the shared single-use-latch supertype across `Page::PageStateError` and 7b's
`SSE::StreamStateError` (phase 10's inbound list, the bullet of 2026-09-13); a `cancellation:` keyword
on the blocking engine (a pure widening phase 8 or 10 can add, P7-102); the adapter half of `PAGE-36`
(8a's Tasks 13 and 20); and `PAGE-33`'s "the transport's responsibility" half, which phase 8's
adapters must honour and which `Completer#fulfil` already honours for a future built on the core pivot.
`docs/sdk-documentation/pagination.md` is written; the first worked cross-gem example — a paginated
JSON endpoint with `dexpace-serde-json`'s codec in the caller's extractor — waits for 7a, as the
design's interface table says.
