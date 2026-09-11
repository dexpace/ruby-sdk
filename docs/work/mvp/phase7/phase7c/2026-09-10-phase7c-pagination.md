# Phase 7c — Pagination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `dexpace-core`'s pagination subsystem in full — the page value and its response ownership, the
strategy contract and its three built-ins, the byte-for-byte query splice, the two consumption views over one
lazy drive routine, the async engine, and the fetcher-based front-end — satisfying all 36 requirements
`PAGE-1`–`PAGE-36`, of which 35 are implemented outright and `PAGE-35` is vacuous by construction on design
§12's own authority. No deferral is filed, no ⏳ row is added, and no unsatisfied MUST is created.

**Architecture:** One frozen `Dexpace::Page::Paginator` (`Data`, immutable configuration only, safe to share —
`PAGE-8`) producing per-iteration `Dexpace::Page::Walk` objects that **own** every live response. A `Walk`
includes `Dexpace::Closeable`, holds the current and the one-slot look-ahead page as instance variables, and
exposes `#close`; **no resource is ever acquired or released inside an `Enumerator` block or inside a `#each`
method's locals**, which is design §7.1's hard rule and phase 3's already-paid-for obligation
(`pagination/318ae05d`, `pagination/b2a85752`). Two thin views — `Items` (re-iterable, eager-closes each page
before yielding, `PAGE-11`) and `Pages` (single-use, `PAGE-14`, auto-closing with the look-ahead, `PAGE-12`) —
drive one internal routine. Strategies are frozen `Data` types taking a **caller-supplied `#call(response)`
extractor**, never a codec and never a witness, which is what makes core's pagination layer serde-agnostic and
what spec-forced boundary 5's audit enforces. The async engine is a `while` pump over a re-arm flag driven by
phase 2's `Dexpace::Async::Future#on_settle`, never recursive future composition (`PAGE-31`), with a
caller-supplied one-method `#post` executor and **no thread, no pool and no `Fiber.scheduler` requirement**.

**Tech Stack:** Ruby 3.2–4.0 (authored on 3.4.10), zero new runtime dependencies, **no new `require` in core's
allowlist** (`uri` is already on it and is the only stdlib this plan touches), Minitest, RBS + Steep, RuboCop
with phase 0's five custom cops plus phase 2's sixth, SimpleCov, YARD.

**Spec:** `docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination-design.md`, under the charter
`docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md`.
`docs/product-spec/12-pagination.md` is the normative chapter for all 36 IDs — **including its chapter intro,
which carries the transport-agnostic and serde-agnostic properties no `PAGE` ID restates**;
`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` rows 374–409 carry the canonical
text.

## Global Constraints

- **`dexpace-core` gains no dependency and the require allowlist does not grow.** `uri` is already
  allowlisted; nothing else in this plan requires a stdlib entry not already in use elsewhere in core.
- **`lib/dexpace/page/**` names no `Dexpace::Serde` constant, no bare `Serde`, no bare `JSON`, and requires
  no `dexpace/serde` file.** This is spec-forced boundary 5, mechanised by `gates:serde_isolation` in Task 1.
  Every task below is written so the gate stays green; a task that needs an exception has misread `R7`.
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`).
- **Inside `module Dexpace`, every core constant is `::`-qualified**: `::Data`, `::Array`, `::String`,
  `::Float`, `::Regexp`, `::Thread`, `::StandardError`, `::URI`, `::IndexError`.
  `Dexpace/QualifiedCoreConstant` is scoped to `lib/dexpace/async/**` and `lib/dexpace/serde/**` and does not
  reach this tree; the convention is followed anyway.
- **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are strictly forbidden**
  (`Dexpace/NoThreadInterrupt`). **This plan calls no wait of any kind** — not `Dexpace::Clock#sleep`, not
  `Dexpace::Async.delay`. No `PAGE` requirement waits, so `P5-9`'s no-scheduler raise is unreachable from
  this sub-phase.
- **`Thread::Mutex` is per-fiber-owned and non-reentrant.** Exactly one mutex is written in this plan — the
  async pump's re-arm flag in Task 14 — and it is held **across the flag flip only**, never across a
  dispatch, a parse, a consumer call or a close. `Dexpace::Closeable`'s latch is phase 2's and is already
  correct.
- **No `block_given?` guard is written anywhere in this sub-phase.** It is measurably true inside `#each`
  when reached through `to_enum(:each)` and `#next`, so it forbids nothing (`pagination/b2a85752`). Task 17
  greps for it.
- **Every `ensure` that closes reads `$!` first and branches**, per the design's `R8`: `raise` when nothing
  is in flight (`PAGE-15`), `Dexpace.attach_suppressed` when something is (`PAGE-13`), and
  `Dexpace.close_quietly` where the requirement says *swallow* (`PAGE-26`, `PAGE-32`'s already-failed
  branch). A bare `ensure` inverts the required primary and passes every test that does not look for it.
- **`URI::RFC3986_PARSER` is pinned and reached only through `Dexpace::URL`.** `Dexpace/NoUriDefaultParser`
  bans `URI.parse`/`URI.join`/`URI::DEFAULT_PARSER`; Task 2 puts the resolution call in `URL` so
  `lib/dexpace/page/` never names a parser.
- **`downcase` is called with no arguments** (`Dexpace/NoLocaleCaseFold`). `PAGE-18`'s `rel` token match is
  this plan's one fold site.
- **`Regexp.new(source, timeout: 1.0)` per pattern, never `Regexp.timeout`.** Task 8's anchored digit screen
  is this plan's only pattern; `PAGE-18`'s grammar is a state machine and writes none.
- **Domain model construction pattern:** `Data.define`, `private_class_method :new`, `.build` with
  `Model.required!`, defensive collection copies through `Model.own`, shallow `freeze`.
  **`Dexpace::Page` and `Dexpace::Page::Walk` are the two exceptions and are plain classes**, because a
  `Data` instance is frozen and cannot hold `Dexpace::Closeable`'s latch — phase 3b's finding at
  `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md:911`, applied one layer up.
- **`Dexpace::Page::Paginator` never closes its transport.** `PIPE-26`/`PIPE-27`: a built pipeline is a
  transport whose `#close` is a no-op, so a paginator wrapping one owns nothing.
- **Formatting:** double quotes, 2-space indentation, 100 columns, `consistent_comma` trailing commas.
- **Every new `lib/` file opens with the `require_relative`s for the core files it names** — phase 2's
  precedent, unchanged.

### Commands

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/page/<name>_test.rb   # one suite, red or green
(cd gems/dexpace-core && bundle exec rake test)                          # the gem's whole suite
bundle exec rake                                                         # all gates
bundle exec rake gates:serde_isolation                                   # boundary 5's audit (Task 1)
bundle exec rubocop
bundle exec steep check
bundle exec rbs validate
bundle exec rake surface:regenerate                                      # deliberate; Task 17 only
```

### What was verified during planning

**One interpreter, and this plan says so before it says anything else.** Only Ruby 3.4.10 is installed on the
authoring machine — re-checked while writing this plan: `mise ls` lists `bun`, `go`, `node` and `opencode` and
no Ruby; `~/.local/share/mise/installs` holds no ruby directory; `~/.rbenv`, `~/.rvm` and `/opt/rubies` do not
exist. **The 3.2.11 and 4.0.6 columns have not been run for anything below.** Task 1 installs both and re-runs
every fact on all three before any implementation task begins.

1. **A close error raised from an `ensure` reaches the caller unwrapped through every terminal shape** —
   `Enumerable#first`, `Enumerator::Lazy#map{}.first(2)`, an explicit `break`, and a plain block returning a
   value. `PAGE-15`'s wrapping clause has no antecedent in Ruby (`P7-1`).
2. **A raising `ensure` replaces an in-flight consumer exception as the primary**, setting `#cause` to it.
   That inverts `PAGE-13`/`PAGE-32`. Reading `$!` at the top of the `ensure` and branching restores the
   required order, on both branches including the `break`-driven one where `$!` is `nil`.
3. **Recursive future composition over synchronously-settled futures raises `SystemStackError` at ~11,000
   frames; a `while` pump completes 200,000 pages with no growth.** `PAGE-31`.
4. **`URI::Generic#query=` is byte-transparent for every query string `URI::RFC3986_PARSER.parse` can
   produce** — a differential probe over every printable ASCII byte found zero disagreements. The
   canonicalisation happens at parse time (space, `"`, `'`, `<`, `>`, `` ` ``). `PAGE-21`, `PAGE-24`.
5. **`URI.decode_www_form("q=a+b")` → `[["q", "a b"]]` and `URI.encode_www_form_component("a b")` → `"a+b"`**
   — the exact inverse of `PAGE-22` in both directions. Phase 1's
   `Dexpace::PercentEncoding.encode_component`/`.decode_component` are `PAGE-22` exactly and are already
   shipped and tested (`a b*~+/!()'` → `a%20b%2A~%2B%2F%21%28%29%27`; `decode_component("a+b")` → `"a+b"`).
6. **`URI::RFC3986_PARSER.join(base, "?page=2")` preserves the full path** (`/repo/issues?page=1` →
   `/repo/issues?page=2`), which is `PAGE-19`'s RFC 3986 requirement and not the RFC 2396 behaviour it
   forbids; it raises `URI::InvalidURIError` on `"not a url"`, `"http://[bad"` and a whitespace-only
   reference; **and it succeeds on `""` and `"//"`, returning the base unchanged** — the loop hazard `P7-5`
   closes.
7. **`uri.query = nil` removes the query; `uri.query = ""` leaves a dangling `?`** (`P7-4`).
   **`Float::INFINITY.positive?` is `true` and `3 < Float::INFINITY` is `true`** (`PAGE-9`/`PAGE-10`).
8. **`Fiber[]` is visible inside an `Enumerator`'s internal fiber and `Thread.current[]` is not**, and the
   internal fiber is created at the **first pull**, not at `Enumerator.new`.

Read as **code**, not summary, because three decisions turn on the literal shipped shape:

- `Dexpace::Closeable#initialize_closeable(owned:)`, `#close`, `#closed?`, `#owned?` and the private
  `#release` contract (`docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md:532-577`) — the latch
  `Dexpace::Page` and `Dexpace::Page::Walk` both use.
- `Dexpace::Response#close` is `body&.close` **and nothing else**, with idempotence living in
  `ResponseBody`'s own latch (3b). That is why `PAGE-27`'s exactly-once needs a latch on the `Page`.
- `Dexpace::Async::Settlement = Data.define(:response, :error, :cancelled)` validating that **exactly one of
  `response`/`error` is non-nil**, and `Future#on_settle` invoking immediately on the calling fiber when the
  future is already settled (phase 2). Those two facts are `PAGE-28`'s null-success vacuity and `PAGE-31`'s
  recursion hazard respectively.

## This plan's open questions, resolved

The design's five open questions are resolved below with a concrete decision each.

1. **`Enumerable` on the two views.** *Decision:* both `Items` and `Pages` `include ::Enumerable` and define
   `#each`. The RBS declares `include ::Enumerable[…]`; `public_instance_methods(false)` excludes inherited
   names, so Task 17's runtime surface snapshot is unaffected and the RBS line is the whole declaration.
   Design §7.1's stated reason ("giving callers `Enumerable` for free … without core inventing vocabulary")
   is the argument and this plan does not re-open it.
2. **The page view's emptiness probe.** *Decision:* `Pages#more?`, a non-consuming probe that fills the
   walk's look-ahead slot, with a YARD block stating in its first sentence that **it runs an HTTP exchange**.
   `Enumerable#any?` is inherited and consumes; a method named `any?` that costs a request is the trap
   `PAGE-12`'s own rationale warns about, so the probe gets a name that cannot be mistaken for free.
3. **`Walk`'s visibility.** *Decision:* `private_constant`, no `sig/` mirror, no manifest row — phase 4's
   precedent. `Items#close` and `Pages#close` are the public surface and delegate to it.
4. **The counting transport double.** *Decision:* one class, `test/support/counting_transport.rb`, with
   `mode:` of `:sync`, `:async_immediate` or `:async_deferred`; a script `Array` of `Response`s, `Exception`s
   or callables consumed in order; `#calls` returning frozen `[request, options, cancellation]` triples so a
   test can assert `PAGE-36`'s options reached **every** call; and `#settle_next` for the deferred async
   mode. Shape confirmed against 6a's `FakeTransport` and 4b's recovery doubles on Task 1 rather than
   invented fresh.
5. **Whether `gates:serde_isolation` scans `sig/`.** *Decision:* yes — `lib/**/*.rb` **and** `sig/**/*.rbs`
   for each guarded subtree. A `sig/dexpace/page/*.rbs` naming `Dexpace::Serde` would be a public-surface
   dependency, and the cost is one more glob. Task 1 checks phase 0's `NFR-11` scan first so the two do not
   overlap confusingly, and states in the gate's comment which one owns which failure.

## Task order and dependency chain

Seventeen tasks, in exact buildable dependency order. The one ordering rule that is not merely convenient:
**`Walk` (Task 10) lands before either view (Tasks 11, 12)**, because both views are thin over it and a view
built first would grow the state the rule forbids it from holding.

1. **Matrix fact verification, `gates:serde_isolation`, and the three test doubles** — no requirement IDs;
   the plan's own evidence-gathering step and `R11`'s branch point.
2. `Dexpace::URL.resolve` (`PAGE-19`, `P7-3`) — modifies phase 1's file; standalone.
3. `Dexpace::Page::QueryRewriter` (`PAGE-21`, `PAGE-22`, `PAGE-23`, `PAGE-24`) — standalone.
4. `Dexpace::Page::Info` (`PAGE-4`) — standalone.
5. `Dexpace::Page` (`PAGE-2`, `PAGE-3`) — needs phase 2's `Closeable`.
6. `Dexpace::Page::LinkHeader` (`PAGE-18`, `PAGE-20`) — standalone.
7. `Dexpace::Page::CursorStrategy` (`PAGE-16`, `PAGE-5`) — needs Tasks 3, 4.
8. `Dexpace::Page::PageNumberStrategy` (`PAGE-17`, `PAGE-5`) — needs Tasks 3, 4.
9. `Dexpace::Page::LinkStrategy` (`PAGE-18`, `PAGE-19`, `PAGE-20`, `PAGE-5`) — needs Tasks 2, 4, 6.
10. `Dexpace::Page::Walk` (`PAGE-5`, `PAGE-7`, `PAGE-9`, `PAGE-13`, `PAGE-15`, `PAGE-36`) — needs Tasks 4, 5.
11. `Dexpace::Page::Items` (`PAGE-1`, `PAGE-8`, `PAGE-11`) — needs Task 10.
12. `Dexpace::Page::Pages` (`PAGE-1`, `PAGE-12`, `PAGE-14`, `PAGE-15`) — needs Task 10.
13. `Dexpace::Page::Paginator` (`PAGE-6`, `PAGE-8`, `PAGE-9`, `PAGE-10`, `PAGE-36`) — needs Tasks 10–12.
14. `Dexpace::Page::AsyncPaginator` (`PAGE-25`–`PAGE-33`) — needs Tasks 5, 10, 13.
15. `Dexpace::Page::Fetchers` (`PAGE-34`, `PAGE-35`) — needs Tasks 5, 10.
16. **The lifetime inversion suite** (`PAGE-13`, `PAGE-15`, `PAGE-32`) — needs Tasks 11, 12, 14.
17. Final wiring: the requires, the shadowing audit, the surface snapshot, the RBS baseline, the `Fiber[]`
    assertion, and the four register-edit texts the design already drafted for a human to apply.

---

## Task 1: Matrix fact verification, the serde-isolation gate, and the test doubles

**Requirement IDs:** none directly. This task is the plan's evidence-gathering step and `R11`'s branch point,
per the precedent phases 3–6 all set.
**Design:** "Verified Ruby facts this document measured"; "`R11`"; "Open questions for `7c`'s own plan" 4 and 5.

**Files:**
- Create: `gems/dexpace-core/test/support/counting_transport.rb`,
  `gems/dexpace-core/test/support/probe_executor.rb`,
  `gems/dexpace-core/test/support/closing_probe.rb`
- Create or Modify: `tasks/gates.rake`

- [ ] **Step 1: Install the matrix and re-run every fact**

Install `ruby@3.2.11` and `ruby@4.0.6`. Re-run all eight facts from *What was verified during planning* on
**all three** interpreters and record the results in the task's notes. Two are load-bearing enough that a
divergence changes the design rather than the plan:

- **Fact 2** (the `ensure`/`$!` inversion). If any interpreter behaves differently, every `ensure` in Tasks
  10, 12, 14 and 16 changes shape. Expected: uniform.
- **Fact 4** (`query=` byte-transparency). If any interpreter canonicalises where 3.4.10 does not, `PAGE-21`
  needs a hand-rolled URL renderer and Task 3 grows. Expected: uniform.

Facts 1, 3, 6, 7 and 8 are expected uniform and are re-run anyway, because `pagination/318ae05d`'s own
history is a version-scoped verification that had to be widened.

- [ ] **Step 2: Determine which side of `R11` this sub-phase is on**

Run `bundle exec rake -T | grep serde_isolation`.

- **If the task does not exist**, `7c` lands first: build it in Step 3.
- **If it exists**, `7b` landed first: skip Step 3's construction and instead add one triple to its path list
  plus one negative fixture for `lib/dexpace/page/**`, then go to Step 4. **Do not build a second gate and do
  not modify `7b`'s SSE-specific prohibitions.**

Record which branch was taken in the task's notes, because the checklist's `R11` row names it.

- [ ] **Step 3: Build `gates:serde_isolation` (only on the first-lands branch)**

```ruby
# tasks/gates.rake
#
# Spec-forced boundary 5 of docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md.
#
# The `sse` entry is SSE-37, a MUST with its own conformance clause. The `page` entry is an
# EXTENSION of that mechanism, not a requirement: docs/product-spec/12-pagination.md:3 states the
# pagination engine is serde-agnostic in its chapter intro, that sentence carries no requirement ID,
# and core's require allowlist cannot see the boundary because it is INTERNAL -- pagination reaching
# for core's own Dexpace::Serde. Labelled here rather than smuggled in as a MUST.
SERDE_ISOLATION_SUBTREES = [
  {
    lib: "gems/dexpace-core/lib/dexpace/page/**/*.rb",
    sig: "gems/dexpace-core/sig/dexpace/page/**/*.rbs",
    extra: "gems/dexpace-core/lib/dexpace/page.rb",
    label: "pagination",
    cite: "docs/product-spec/12-pagination.md:3 (chapter intro; no requirement ID -- " \
          "phase 7 segmentation design, spec-forced boundary 5, an EXTENSION of SSE-37)",
  },
].freeze

BANNED_REQUIRES = %r{\brequire(?:_relative)?\s+["'][^"']*(?:dexpace/serde|\bjson\b)}
BANNED_CONSTANTS = /(?<![:\w])(?:Dexpace::Serde|Serde|JSON)(?![\w])/

task "gates:serde_isolation" do
  # ... for each subtree, for each file in lib+sig+extra: fail with label and cite on a hit ...
end
```

The `page` triple is `7c`'s. If `7b` runs second it appends its own with `label: "sse"` and
`cite: "SSE-37"`, plus its two SSE-specific checks (no done-sentinel string, no error-envelope recognition),
which are **not** generalised here.

Check phase 0's `NFR-11` RBS scan before writing the `sig:` glob, and state in a comment which gate owns
which failure: `NFR-11` asserts no non-`Dexpace::` constant appears in a public signature; this gate asserts
no `Dexpace::Serde` appears in *these* signatures. They do not overlap.

- [ ] **Step 4: Negative and positive fixtures for the gate**

A scratch file under `test/fixtures/gates/` naming `Dexpace::Serde` that the gate must **reject**, and one
naming nothing that it must **accept**. Phase 0's `two_third_party` negative-fixture precedent.

Run: `bundle exec rake gates:serde_isolation` — green on the real tree, and red when the negative fixture is
temporarily placed inside the guarded glob.

- [ ] **Step 5: Write the three test doubles**

`CountingTransport` per resolved question 4. `ProbeExecutor` with three modes: `:inline` (runs the block
immediately, recording the call), `:deferred` (queues blocks, `#drain` runs them, recording the thread), and
`:rejecting` (raises `Dexpace::Test::ExecutorRejected` after N successful posts) — `PAGE-29` and `PAGE-30`.
`ClosingProbe` — a `Dexpace::Response`-shaped double counting `#close` calls, optionally raising from
`#close`, and counting body reads so `PAGE-5` and `PAGE-16` can assert zero and one respectively.

Confirm each against 4b's, 4c's and 6a's existing doubles before writing, and reuse rather than duplicate
where one already fits.

---

## Task 2: `Dexpace::URL.resolve`

**Requirement IDs:** `PAGE-19` (the resolution half).
**Design:** "`P7-3`"; "The three built-in strategies — `PAGE-19`'s reference resolution".

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/http/url.rb`,
  `gems/dexpace-core/sig/dexpace/http/url.rbs`,
  `gems/dexpace-core/test/dexpace/http/url_test.rb` (phase 1's file, extended)

**Needs:** phase 1's `Dexpace::URL`.
**Produces:** `Dexpace::URL.resolve(base, reference) -> URI::Generic | nil`.

- [ ] **Step 1: Write the failing test, appended to phase 1's file**

```ruby
# PAGE-19: RFC 3986 reference resolution against the originating page's response URL. The RFC 2396
# behaviour -- dropping the last path segment for a query-only reference -- is the one the
# requirement explicitly forbids, so it gets its own assertion rather than riding on a general one.
class DexpaceURLResolveTest < DexpaceTestCase
  BASE = Dexpace::URL.parse!("https://api.example.com/repo/issues?page=1")

  test "PAGE-19: a query-only reference preserves the base's full path" do
    assert_equal("https://api.example.com/repo/issues?page=2",
                 Dexpace::URL.external_form(Dexpace::URL.resolve(BASE, "?page=2")))
  end

  test "PAGE-19: an absolute target is used as-is and a relative one resolves" do
    assert_equal("https://other.example/x",
                 Dexpace::URL.external_form(Dexpace::URL.resolve(BASE, "https://other.example/x")))
    assert_equal("https://api.example.com/users?page=2",
                 Dexpace::URL.external_form(Dexpace::URL.resolve(BASE, "../users?page=2")))
  end

  test "PAGE-19: a target that cannot resolve returns nil rather than raising" do
    assert_nil(Dexpace::URL.resolve(BASE, "not a url"))
    assert_nil(Dexpace::URL.resolve(BASE, "http://[bad"))
    assert_nil(Dexpace::URL.resolve(BASE, "   "))
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/url_test.rb`
Expected: fails with `NoMethodError: undefined method 'resolve' for module Dexpace::URL`.

- [ ] **Step 3: Add `.resolve` to `url.rb`**

```ruby
# PAGE-19: RFC 3986 reference resolution. Returns nil rather than raising, because PAGE-19 requires
# an unresolvable rel=next target to be treated as end-of-stream and not as an error.
#
# The parser is pinned here and nowhere else in this subsystem: Dexpace/NoUriDefaultParser bans
# URI.join outright, and putting the call in lib/dexpace/page/ would make that directory the second
# place in core that knows which parser is pinned (design §3.5; P7-3).
def resolve(base, reference)
  ::URI::RFC3986_PARSER.join(base, reference)
rescue ::URI::InvalidURIError, ::ArgumentError
  nil
end
module_function :resolve
```

- [ ] **Step 4: Widen the `sig/` mirror; run to confirm it passes**

```rbs
def self.resolve: (::URI::Generic base, ::String reference) -> ::URI::Generic?
```

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/url_test.rb`
Expected: PASS, phase 1's existing runs plus 3 new, 0 failures.

---

## Task 3: `Dexpace::Page::QueryRewriter`

**Requirement IDs:** `PAGE-21`, `PAGE-22`, `PAGE-23`, `PAGE-24`.
**Design:** "`Dexpace::Page::QueryRewriter`"; verified facts 3, 4 and 6; `P7-4`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/page/query_rewriter.rb`,
  `gems/dexpace-core/sig/dexpace/page/query_rewriter.rbs`
- Test: `gems/dexpace-core/test/dexpace/page/query_rewriter_test.rb`

**Needs:** phase 1's `Dexpace::PercentEncoding`.
**Produces:** `QueryRewriter.get`, `.set`, `.rewrite_url`.

- [ ] **Step 1: Write the failing test**

```ruby
# PAGE-21, PAGE-22, PAGE-23, PAGE-24.
#
# This module exists because Ruby's query helpers are the exact inverse of PAGE-22 in both
# directions (verified: URI.decode_www_form("q=a+b") -> [["q", "a b"]] and
# URI.encode_www_form_component("a b") -> "a+b"), and because Dexpace::Query.parse(q).encode
# re-encodes every parameter, which is the canonicalisation PAGE-21 forbids in as many words.
class DexpacePageQueryRewriterTest < DexpaceTestCase
  R = Dexpace::Page::QueryRewriter

  test "PAGE-21: untargeted parameters are copied byte-for-byte, order preserved" do
    result = R.set("flag&filter=a:b&page=1", "page", "2")

    assert_equal("flag&filter=a:b&page=2", result)
    # The requirement's own conformance clause asks for byte identity of the untargeted parts, not
    # for URL equality -- so assert the segments, not the whole string.
    assert_equal(%w[flag filter=a:b], result.split("&")[0, 2])
  end

  test "PAGE-22: encoding is RFC 3986 component encoding" do
    assert_equal("q=a%20b", R.set("", "q", "a b"))
    assert_equal("token=a%2Bb%2Fc%3D", R.set("", "token", "a+b/c="))
  end

  test "PAGE-22: reading decodes with the same semantics -- a literal + reads back as +" do
    assert_equal("a+b", R.get("q=a+b", "q"))
    assert_equal("a b", R.get("q=a%20b", "q"))
    assert_equal("", R.get("flag", "flag"))          # value-less flag -> empty string
    assert_equal("1", R.get("p=1&p=2", "p"))          # first match wins
    assert_nil(R.get("p=1", "absent"))
  end

  test "PAGE-23: replace first in place, drop duplicates, append if absent, remove when nil" do
    assert_equal("page=2&sort=asc", R.set("page=1&sort=asc", "page", "2"))
    assert_equal("sort=asc", R.set("page=1&sort=asc", "page", nil))
    assert_equal("p=1&q=2", R.set("p=1&p=9", "p", "1").then { |q| R.set(q, "q", "2") })
    assert_equal("sort=asc&page=2", R.set("sort=asc", "page", "2"))
  end

  test "P7-4: removing the only parameter yields no query at all, not a dangling ?" do
    url = Dexpace::URL.parse!("https://x/a?page=1")

    assert_equal("https://x/a", Dexpace::URL.external_form(R.rewrite_url(url, "page", nil)))
  end

  test "PAGE-24: every non-query component survives exactly" do
    url = Dexpace::URL.parse!("https://user:pw@api.example.com:8443/a/b?flag&page=1#frag")
    out = R.rewrite_url(url, "page", "2")

    assert_equal("https://user:pw@api.example.com:8443/a/b?flag&page=2#frag",
                 Dexpace::URL.external_form(out))
    assert_equal("https", out.scheme)
    assert_equal("user:pw", out.userinfo)
    assert_equal(8443, out.port)
    assert_equal("/a/b", out.path)
    assert_equal("frag", out.fragment)
  end
end
```

Add one `#sample` property test: for 128 generated raw queries mixing value-less flags, reserved characters,
repeated names and percent escapes, `set(q, name, v)` leaves every segment whose name is not `name`
byte-identical, and `get(set(q, name, v), name) == v`.

- [ ] **Step 2: Run test to confirm it fails**

Expected: `NameError: uninitialized constant Dexpace::Page::QueryRewriter`.

- [ ] **Step 3: Write the module**

Tokenise on `&`, split each segment on its **first** `=` only. `.get` decodes the matched value through
`Dexpace::PercentEncoding.decode_component` and returns `""` for a segment with no `=`. `.set` walks the
segments, replaces the first whose decoded name matches, **drops** later matches, appends when none matched
and the value is non-`nil`, and joins with `&`. `.rewrite_url` `dup`s the URI (a frozen `URI::Generic` `dup`s
to an unfrozen one — verified), assigns the spliced query, and **assigns `nil` rather than `""`** when the
splice is empty (`P7-4`).

Nothing in this file names `Dexpace::Query`, `URI.decode_www_form`, `CGI` or `URI::DEFAULT_PARSER`.

- [ ] **Step 4: `sig/` mirror, add the require, run to confirm it passes**

Expected: PASS, all assertions plus the property test.

---

## Task 4: `Dexpace::Page::Info`

**Requirement IDs:** `PAGE-4`.
**Design:** "`Dexpace::Page::Info` — `PAGE-4`'s PageInfo".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/page/info.rb`, `sig/dexpace/page/info.rbs`
- Test: `gems/dexpace-core/test/dexpace/page/info_test.rb`

**Needs:** phase 1's `Dexpace::Model`, `Dexpace::Request`.
**Produces:** `Info.build`, `Info.terminal`, `#items`, `#next_request`, `#next_link`, `#continuation_token`.

- [ ] **Step 1: Write the failing test**

```ruby
# PAGE-4: a strategy's parse output MUST always be well-formed (never nil), MUST signal termination
# ONLY by a null next-request -- never by throwing and never via a side channel -- and an empty items
# list paired with a non-null next-request is a VALID NON-TERMINAL page.
class DexpacePageInfoTest < DexpaceTestCase
  test "PAGE-4: items are never nil and are frozen and owned" do
    source = ["a"]
    info = Dexpace::Page::Info.build(items: source, next_request: nil)

    assert_equal(["a"], info.items)
    assert_predicate(info.items, :frozen?)
    source << "b"
    assert_equal(["a"], info.items)   # the model owns its copy
  end

  test "PAGE-4: a nil next_request is the single exclusive end-of-stream signal" do
    assert_nil(Dexpace::Page::Info.terminal.next_request)
    assert_empty(Dexpace::Page::Info.terminal.items)
  end

  test "PAGE-4: empty items with a non-nil next_request is a valid NON-terminal page" do
    info = Dexpace::Page::Info.build(items: [], next_request: fake_request)

    assert_empty(info.items)
    refute_nil(info.next_request)
  end

  test "PAGE-4: items must not be nil" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Page::Info.build(items: nil, next_request: nil)
    end
  end
end
```

- [ ] **Step 2: Run test to confirm it fails.** Expected: `NameError`.

- [ ] **Step 3: Write the `Data`**

`Data.define(:items, :next_request, :next_link, :continuation_token)`, `include Dexpace::Model`,
`private_class_method :new`, `.build(items:, next_request:, next_link: nil, continuation_token: nil)` with
`Model.required!` on `items`, `Model.own` freezing the list, and validation that `next_request` is `nil` or a
`Dexpace::Request`. `.terminal(items: [])` is the named factory. **There is no `terminal?` flag and no
sentinel**, which is `PAGE-4`'s prohibition made structural.

- [ ] **Step 4: `sig/` mirror, require, run to confirm it passes.**

---

## Task 5: `Dexpace::Page`

**Requirement IDs:** `PAGE-2`, `PAGE-3`.
**Design:** "`Dexpace::Page` — the page value, and why it is not a `Data`"; `P7-2`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/page.rb`, `sig/dexpace/page.rbs`
- Test: `gems/dexpace-core/test/dexpace/page_test.rb`

**Needs:** phase 2's `Dexpace::Closeable`; phase 1's `Dexpace::Response`.
**Produces:** `Dexpace::Page` (a class, and the namespace for every constant in Tasks 3, 4 and 6–15).

- [ ] **Step 1: Write the failing test**

```ruby
# PAGE-2, PAGE-3.
#
# A Page is a plain class including Dexpace::Closeable and NOT a Data, because a Data instance is
# frozen and cannot hold the latch (phase 3b's finding, applied one layer up). Response#close is a
# pure forward with no latch of its own, and Response#body may be nil or a BufferBody whose #close
# is a documented no-op -- so PAGE-27's exactly-once cannot be delegated to the response.
class DexpacePageTest < DexpaceTestCase
  test "PAGE-3: closing the page releases the response exactly once, however many times called" do
    response = ClosingProbe.new
    page = Dexpace::Page.build(response: response, items: [1, 2])

    page.close
    page.close
    page.close

    assert_equal(1, response.close_count)
    assert_predicate(page, :closed?)
  end

  test "PAGE-2: items, status, headers and request stay readable after close" do
    response = ClosingProbe.new(status: 200, headers: { "x-a" => ["1"] })
    page = Dexpace::Page.build(response: response, items: [1, 2])
    page.close

    assert_equal([1, 2], page.items)
    assert_equal(200, page.status.code)
    assert_equal(["1"], page.headers["x-a"])
    refute_nil(page.request)
  end

  test "PAGE-2: items are never nil, MAY be empty, and are frozen and owned" do
    source = [1]
    page = Dexpace::Page.build(response: ClosingProbe.new, items: source)
    source << 2

    assert_equal([1], page.items)
    assert_predicate(page.items, :frozen?)
    assert_empty(Dexpace::Page.build(response: ClosingProbe.new, items: []).items)
  end

  test "PAGE-3: a close error propagates once and the latch stays flipped" do
    response = ClosingProbe.new(raise_on_close: RuntimeError.new("boom"))
    page = Dexpace::Page.build(response: response, items: [])

    assert_raises(RuntimeError) { page.close }
    assert_predicate(page, :closed?)
    page.close                       # no second release attempted
    assert_equal(1, response.close_count)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails.** Expected: `NameError`.

- [ ] **Step 3: Write the class**

```ruby
module Dexpace
  # PAGE-2/PAGE-3: one page of a paginated walk. Owns exactly one Dexpace::Response; whoever holds
  # the page owns closing it, and the materialized items plus the derived status/headers/request
  # survive close because they are read off a frozen Data that close does not touch.
  #
  # Not a Data: Dexpace::Closeable's latch needs mutable state, and PAGE-27 requires exactly-once
  # close across four async paths that cannot rely on whatever body the transport supplied.
  #
  # This class is also the namespace for the pagination subsystem (P7-2).
  class Page
    include Dexpace::Closeable

    def self.build(response:, items:, next_link: nil, continuation_token: nil)
      Dexpace::Model.required!(:response, response)
      Dexpace::Model.required!(:items, items)
      new(response, items, next_link, continuation_token)
    end

    def initialize(response, items, next_link, continuation_token)
      @response = response
      @items = items.dup.freeze
      @next_link = next_link
      @continuation_token = continuation_token
      initialize_closeable(owned: true)
    end
    private_class_method :new

    attr_reader :response, :items, :next_link, :continuation_token

    def status = @response.status
    def headers = @response.headers
    def request = @response.request

    private

    def release
      @response.close
    end
  end
end
```

- [ ] **Step 4: `sig/` mirror, require, run to confirm it passes.**

---

## Task 6: `Dexpace::Page::LinkHeader`

**Requirement IDs:** `PAGE-18` (the grammar), `PAGE-20`.
**Design:** "`Dexpace::Page::LinkHeader`"; spec-forced boundary 22.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/page/link_header.rb` (`private_constant`; no `sig/`, no manifest row)
- Test: `gems/dexpace-core/test/dexpace/page/link_header_test.rb`

**Needs:** nothing.
**Produces:** `LinkHeader.next_target(values) -> String | nil`.

- [ ] **Step 1: Write the failing test — one fixture per named hazard**

```ruby
# PAGE-18, PAGE-20.
#
# A character-level state machine, not a regexp: RFC 8288's link-value grammar is not regular
# (commas inside <> and inside quoted parameter values must not split link-values, and quoted-pair
# escapes must be honoured), so the per-pattern-timeout constraint is discharged by not writing the
# pattern -- the same route design §6.3 takes for WWW-Authenticate.
class DexpacePageLinkHeaderTest < DexpaceTestCase
  L = Dexpace::Page.const_get(:LinkHeader)

  test "PAGE-18: a comma inside an angle-bracketed URL does not split link-values" do
    assert_equal("https://x/p?a=1,2",
                 L.next_target(['<https://x/p?a=1,2>; rel="next"']))
  end

  test "PAGE-18: a comma inside a quoted parameter value does not split link-values" do
    assert_equal("https://x/2",
                 L.next_target(['<https://x/1>; title="a,b"; rel="prev", <https://x/2>; rel="next"']))
  end

  test "PAGE-18: quoted-pair escapes are honoured" do
    assert_equal("https://x/2",
                 L.next_target(['<https://x/1>; title="a\\"b, c"; rel="last", <https://x/2>; rel=next']))
  end

  test "PAGE-18: rel may be unquoted, multi-token, and is matched case-insensitively" do
    assert_equal("https://x/2", L.next_target(['<https://x/2>; rel=NEXT']))
    assert_equal("https://x/2", L.next_target(['<https://x/2>; rel="prev  next"']))
    assert_equal("https://x/2", L.next_target(["<https://x/2>; rel=\"last\tnext\""])) 
  end

  test "PAGE-18: the FIRST link-value whose rel contains next wins" do
    assert_equal("https://x/1",
                 L.next_target(['<https://x/1>; rel=next, <https://x/2>; rel=next']))
  end

  test "PAGE-18: no rel=next segment and no header at all both mean end-of-stream" do
    assert_nil(L.next_target(['<https://x/1>; rel=prev, <https://x/9>; rel=last']))
    assert_nil(L.next_target(nil))
    assert_nil(L.next_target([]))
  end

  test "PAGE-20: multiple Link header instances are normalized by concatenation" do
    assert_equal("https://x/2", L.next_target(['<https://x/9>; rel=last', '<https://x/2>; rel=next']))
  end
end
```

- [ ] **Step 2: Run test to confirm it fails.** Expected: `NameError`.

- [ ] **Step 3: Write the state machine**

`.next_target(values)` returns `nil` for `nil` or an empty array (`PAGE-20`'s "an empty header set SHOULD map
to no next link"), otherwise `values.join(", ")` and a single pass. States: `expect_lt` → `in_uri` (accumulate
until `>`) → `after_uri` → `in_params`, with `in_quoted` and `in_escape` nested inside `in_params`. A `,` at
top level ends a link-value. Parameters are split on `;` at top level and on the first `=`; the `rel` value is
unquoted if quoted, split on space and tab, and each token compared `token.downcase == "next"` — **`downcase`
with no arguments**, per `Dexpace/NoLocaleCaseFold`. Return the first matching link-value's URI-reference.

**No `Regexp` appears in this file.**

- [ ] **Step 4: `private_constant :LinkHeader`, require, run to confirm it passes.**

---

## Task 7: `Dexpace::Page::CursorStrategy`

**Requirement IDs:** `PAGE-16`; `PAGE-5` (asserted).
**Design:** "`R7`"; "The three built-in strategies"; `P7-6`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/page/cursor_strategy.rb`, `sig/dexpace/page/cursor_strategy.rbs`
- Create: `gems/dexpace-core/sig/dexpace/page/strategy.rbs` (`interface _Strategy`, `_Extractor`)
- Test: `gems/dexpace-core/test/dexpace/page/cursor_strategy_test.rb`

**Needs:** Tasks 3, 4.
**Produces:** `CursorStrategy.build(extract:, parameter: "cursor")`, `#parse(response, template)`.

- [ ] **Step 1: Write the failing test**

```ruby
# PAGE-16 and PAGE-5.
#
# R7/P7-6: the strategy takes a caller-supplied #call(response) extractor, NEVER a Dexpace::Serde
# duck type and never a witness -- a `serde:` keyword would put the word Serde inside
# lib/dexpace/page/** and gates:serde_isolation would fail on this sub-phase's own code.
# PAGE-16's "single read of the response body" is therefore the EXTRACTOR's read; core performs
# none, and the assertion below is what makes that checkable.
class DexpacePageCursorStrategyTest < DexpaceTestCase
  test "PAGE-16: cursor 'c' derives a next request with cursor=c on the template" do
    strategy = Dexpace::Page::CursorStrategy.build(extract: ->(_r) { [[1, 2], "c"] })
    info = strategy.parse(ClosingProbe.new, fake_request(url: "https://x/i?page=1"))

    assert_equal([1, 2], info.items)
    assert_equal("page=1&cursor=c", info.next_request.url.query)
  end

  test "PAGE-16: a null OR empty next cursor is end-of-stream" do
    [nil, ""].each do |cursor|
      strategy = Dexpace::Page::CursorStrategy.build(extract: ->(_r) { [[1], cursor] })
      assert_nil(strategy.parse(ClosingProbe.new, fake_request).next_request)
    end
  end

  test "PAGE-16: the configurable parameter name defaults to cursor" do
    strategy = Dexpace::Page::CursorStrategy.build(extract: ->(_r) { [[], "c"] }, parameter: "after")
    info = strategy.parse(ClosingProbe.new, fake_request(url: "https://x/i"))

    assert_equal("after=c", info.next_request.url.query)
  end

  test "PAGE-16: core reads the body exactly zero times; the extractor reads it once" do
    probe = ClosingProbe.new
    strategy = Dexpace::Page::CursorStrategy.build(extract: ->(r) { r.read_body; [[], nil] })
    strategy.parse(probe, fake_request)

    assert_equal(1, probe.body_read_count)
  end

  test "PAGE-5: parse closes nothing, mutates nothing, and retains nothing" do
    probe = ClosingProbe.new
    strategy = Dexpace::Page::CursorStrategy.build(extract: ->(_r) { [[], nil] })
    strategy.parse(probe, fake_request)

    assert_equal(0, probe.close_count)
    assert_empty(strategy.instance_variables - %i[@extract @parameter])
    assert_predicate(strategy, :frozen?)
  end

  test "PAGE-4: an extractor that raises is a parse failure, not an end-of-stream signal" do
    strategy = Dexpace::Page::CursorStrategy.build(extract: ->(_r) { raise KeyError, "no items" })

    assert_raises(KeyError) { strategy.parse(ClosingProbe.new, fake_request) }
  end
end
```

- [ ] **Step 2: Run test to confirm it fails.** Expected: `NameError`.

- [ ] **Step 3: Write the strategy**

`Data.define(:extract, :parameter)`, `include Dexpace::Model`, `private_class_method :new`,
`.build(extract:, parameter: "cursor")` validating `extract.respond_to?(:call)` and that `parameter` is a
non-empty `String`. `#parse` calls `extract.call(response)` **once**, destructures `[items, cursor]`, and
returns `Info.terminal(items: items)` when the cursor is `nil` or `""`, otherwise
`Info.build(items:, next_request: template.with(url: QueryRewriter.rewrite_url(template.url, parameter,
cursor)))`. **The extractor is not rescued** — a raise is a parse failure and `PAGE-13` is its path.

- [ ] **Step 4: `sig/` mirrors including `interface _Strategy` and `_Extractor`, require, run to confirm it
      passes.**

---

## Task 8: `Dexpace::Page::PageNumberStrategy`

**Requirement IDs:** `PAGE-17`; `PAGE-5` (asserted).
**Design:** "The three built-in strategies".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/page/page_number_strategy.rb`, `sig/…/page_number_strategy.rbs`
- Test: `gems/dexpace-core/test/dexpace/page/page_number_strategy_test.rb`

**Needs:** Tasks 3, 4.
**Produces:** `PageNumberStrategy.build(extract_items:, parameter: "page", start: 1)`.

- [ ] **Step 1: Write the failing test**

```ruby
# PAGE-17. The empty-items check runs FIRST and is defensive against servers that return an empty
# page past the end; the current page is inferred from the ORIGINATING (executed) request, which in
# this port is response.request -- not the template.
class DexpacePagePageNumberStrategyTest < DexpaceTestCase
  def strategy(items, **kw)
    Dexpace::Page::PageNumberStrategy.build(extract_items: ->(_r) { items }, **kw)
  end

  test "PAGE-17: first page with no param and non-empty items -> next request page=start+1" do
    response = ClosingProbe.new(request: fake_request(url: "https://x/i"))
    info = strategy([1]).parse(response, fake_request(url: "https://x/i"))

    assert_equal("page=2", info.next_request.url.query)
  end

  test "PAGE-17: an empty items list is end-of-stream, checked before anything else" do
    response = ClosingProbe.new(request: fake_request(url: "https://x/i?page=4"))

    assert_nil(strategy([]).parse(response, fake_request).next_request)
  end

  test "PAGE-17: a garbage, empty or absent page value computes from start" do
    ["page=abc", "page=", ""].each do |query|
      response = ClosingProbe.new(request: fake_request(url: "https://x/i?#{query}"))
      info = strategy([1], start: 7).parse(response, fake_request(url: "https://x/i"))

      assert_equal("page=8", info.next_request.url.query)
    end
  end

  test "PAGE-17: the parameter name and the start page are both configurable, 0-based allowed" do
    response = ClosingProbe.new(request: fake_request(url: "https://x/i"))
    info = strategy([1], parameter: "pageNumber", start: 0).parse(response, fake_request(url: "https://x/i"))

    assert_equal("pageNumber=1", info.next_request.url.query)
  end

  test "PAGE-17: the current page is read from the EXECUTED request, not the template" do
    response = ClosingProbe.new(request: fake_request(url: "https://x/i?page=5"))
    info = strategy([1]).parse(response, fake_request(url: "https://x/i?page=1"))

    assert_equal("page=6", info.next_request.url.query)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails.** Expected: `NameError`.

- [ ] **Step 3: Write the strategy**

`Data.define(:extract_items, :parameter, :start)`. `#parse` calls `extract_items.call(response)`, returns
`Info.terminal` **immediately** on an empty list, then reads
`QueryRewriter.get(response.request.url.query, parameter)`, screens it with an anchored digit pattern
compiled once as `DIGITS = ::Regexp.new("\\A\\d+\\z", timeout: 1.0)` — **per-pattern timeout, never
`Regexp.timeout`** — falls back to `start` when absent, empty or non-matching, and sets the next page to
`current + 1`. Validation: `start` is a non-negative `Integer`.

- [ ] **Step 4: `sig/` mirror, require, run to confirm it passes.**

---

## Task 9: `Dexpace::Page::LinkStrategy`

**Requirement IDs:** `PAGE-18`, `PAGE-19`, `PAGE-20`; `PAGE-5` (asserted).
**Design:** "The three built-in strategies"; `P7-5`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/page/link_strategy.rb`, `sig/dexpace/page/link_strategy.rbs`
- Test: `gems/dexpace-core/test/dexpace/page/link_strategy_test.rb`

**Needs:** Tasks 2, 4, 6.
**Produces:** `LinkStrategy.build(extract_items:, header: "Link")`.

- [ ] **Step 1: Write the failing test**

```ruby
# PAGE-18, PAGE-19, PAGE-20. The grammar itself is Task 6's; this task is the resolution, the
# configurable header name, and the two end-of-stream routes.
class DexpacePageLinkStrategyTest < DexpaceTestCase
  def parse(link_values, base: "https://api.example.com/repo/issues?page=1", **kw)
    strategy = Dexpace::Page::LinkStrategy.build(extract_items: ->(_r) { [1] }, **kw)
    response = ClosingProbe.new(request: fake_request(url: base),
                                headers: link_values.nil? ? {} : { "link" => link_values })
    strategy.parse(response, fake_request(url: base))
  end

  test "PAGE-19: a query-only rel=next preserves the base path (RFC 3986, not RFC 2396)" do
    info = parse(['<?page=2>; rel=next'])

    assert_equal("https://api.example.com/repo/issues?page=2",
                 Dexpace::URL.external_form(info.next_request.url))
  end

  test "PAGE-19: an unresolvable target is end-of-stream, not an exception" do
    assert_nil(parse(['<not a url>; rel=next']).next_request)
  end

  test "P7-5: a blank rel=next target is end-of-stream, not a resolution to the base" do
    # Verified: URI::RFC3986_PARSER.join(base, "") returns the base UNCHANGED, so resolving a blank
    # target would produce a next request identical to the current one and loop until the page cap.
    assert_nil(parse(['<>; rel=next']).next_request)
    assert_nil(parse(['<   >; rel=next']).next_request)
  end

  test "PAGE-18: absence of a Link header means end-of-stream" do
    assert_nil(parse(nil).next_request)
  end

  test "PAGE-20: two separate Link headers, one next one last -> next is followed" do
    info = parse(['<https://x/9>; rel=last', '<https://x/2>; rel=next'])

    assert_equal("https://x/2", Dexpace::URL.external_form(info.next_request.url))
  end

  test "PAGE-18: the header name is configurable" do
    strategy = Dexpace::Page::LinkStrategy.build(extract_items: ->(_r) { [1] }, header: "X-Links")
    response = ClosingProbe.new(request: fake_request, headers: { "x-links" => ['<https://x/2>; rel=next'] })

    assert_equal("https://x/2", Dexpace::URL.external_form(strategy.parse(response, fake_request).next_request.url))
  end

  test "PAGE-23: following a whole next URL swaps only the URL, preserving method/headers/body" do
    template = fake_request(method: "POST", headers: { "x-a" => ["1"] }, body: fake_body)
    strategy = Dexpace::Page::LinkStrategy.build(extract_items: ->(_r) { [1] })
    response = ClosingProbe.new(request: template, headers: { "link" => ['<https://x/2>; rel=next'] })
    nxt = strategy.parse(response, template).next_request

    assert_equal(template.method, nxt.method)
    assert_equal(template.headers, nxt.headers)
    assert_same(template.body, nxt.body)
    refute_equal(template.url, nxt.url)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails.** Expected: `NameError`.

- [ ] **Step 3: Write the strategy**

`Data.define(:extract_items, :header)`. `#parse`: items from the extractor; `target =
LinkHeader.next_target(response.headers[header])`; **terminal when `target` is `nil` or
`target.strip.empty?`** (`P7-5`); otherwise `resolved = Dexpace::URL.resolve(response.request.url, target)`
and terminal when that is `nil` (`PAGE-19`); otherwise `Info.build(items:, next_request: template.with(url:
resolved), next_link: target)`. **`template.with(url:)` is what `PAGE-23`'s "swap only the request's URL,
preserving the template's method, headers, and body" is** — `Dexpace::Model#with` routes through
`Request.build`, so the other three members are carried unchanged.

- [ ] **Step 4: `sig/` mirror, require, run to confirm it passes.**

---

## Task 10: `Dexpace::Page::Walk` — the lifetime owner

**Requirement IDs:** `PAGE-5` (enforced), `PAGE-7`, `PAGE-9`, `PAGE-13`, `PAGE-15`, `PAGE-36`.
**Design:** "`Dexpace::Page::Walk` — the lifetime owner, and the whole of the `Enumerator` answer";
"The engine's lifetime and `#close` story, in one place"; "`R8`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/page/walk.rb` (`private_constant`; no `sig/`, no manifest row)
- Test: `gems/dexpace-core/test/dexpace/page/walk_test.rb`

**Needs:** Tasks 4, 5; phase 2's `Closeable`, `Dexpace.attach_suppressed`, `Dexpace.close_quietly`.
**Produces:** `Walk#fetch_next_page`, `#close`, `#current`, `#buffered`.

- [ ] **Step 1: Write the failing test**

```ruby
# PAGE-5, PAGE-7, PAGE-9, PAGE-13, PAGE-15, PAGE-36.
#
# The Walk is the object phase 3's Enumerator rule forces into existence: an Enumerator abandoned
# mid-#next never runs its ensure, and neither does an ordinary #each -- and block_given? is TRUE
# inside #each when reached through to_enum(:each), so no in-method guard helps. The only defence is
# where the resource lives, and it lives here (pagination/318ae05d, pagination/b2a85752).
class DexpacePageWalkTest < DexpaceTestCase
  test "PAGE-7: after a terminal page, repeated probes perform no further exchange" do
    transport = CountingTransport.new([response_for(1), response_for(2)])
    walk = walk_over(transport, terminal_after: 2)

    2.times { walk.fetch_next_page }
    3.times { assert_nil(walk.fetch_next_page) }

    assert_equal(2, transport.calls.size)
  end

  test "PAGE-9: with a server echoing one cursor forever and cap=N, exactly N exchanges" do
    transport = CountingTransport.new(Array.new(20) { response_for(1) })
    walk = walk_over(transport, cap: 3, terminal_after: nil)

    4.times { walk.fetch_next_page }

    assert_equal(3, transport.calls.size)
  end

  test "PAGE-36: the per-call overrides reach EVERY page request, not just the first" do
    options = Dexpace::RequestOptions.build(timeout: 1.5, max_retries: 0, tags: { "t" => "v" })
    transport = CountingTransport.new(Array.new(3) { response_for(1) })
    walk = walk_over(transport, options: options, terminal_after: 3)

    3.times { walk.fetch_next_page }

    assert_equal(3, transport.calls.size)
    transport.calls.each { |(_req, opts, _c)| assert_same(options, opts) }
  end

  test "PAGE-13: a throwing parse closes the response inline exactly once and propagates" do
    probe = ClosingProbe.new
    walk = walk_over(CountingTransport.new([probe]), strategy: raising_strategy(KeyError))

    assert_raises(KeyError) { walk.fetch_next_page }
    assert_equal(1, probe.close_count)
  end

  test "PAGE-13: a close failure does NOT mask the parse failure; it is attached as suppressed" do
    probe = ClosingProbe.new(raise_on_close: IOError.new("close boom"))
    walk = walk_over(CountingTransport.new([probe]), strategy: raising_strategy(KeyError))

    error = assert_raises(KeyError) { walk.fetch_next_page }

    assert_equal([IOError], Dexpace.suppressed(error).map(&:class))
  end

  test "PAGE-15: #close releases BOTH the held page and the buffered page" do
    a = ClosingProbe.new
    b = ClosingProbe.new
    walk = walk_over(CountingTransport.new([a, b]), terminal_after: 2)
    walk.hold(walk.fetch_next_page)
    walk.buffer(walk.fetch_next_page)

    walk.close

    assert_equal(1, a.close_count)
    assert_equal(1, b.close_count)
  end

  test "PAGE-15: when both held pages fail to close, the first propagates with the second suppressed" do
    first = ClosingProbe.new(raise_on_close: IOError.new("first"))
    second = ClosingProbe.new(raise_on_close: IOError.new("second"))
    walk = walk_over(CountingTransport.new([first, second]), terminal_after: 2)
    walk.hold(walk.fetch_next_page)
    walk.buffer(walk.fetch_next_page)

    error = assert_raises(IOError) { walk.close }

    assert_equal("first", error.message)
    assert_equal(["second"], Dexpace.suppressed(error).map(&:message))
  end

  test "PAGE-5: the strategy never sees a closed or mutated response" do
    probe = ClosingProbe.new
    walk = walk_over(CountingTransport.new([probe]), terminal_after: 1)
    walk.fetch_next_page

    assert_equal(0, probe.close_count)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails.** Expected: `NameError`.

- [ ] **Step 3: Write the class**

```ruby
module Dexpace
  class Page
    # Per-iteration state. NOT shareable, and never held inside an Enumerator block or a #each
    # method's locals -- design §7.1's hard rule, verified across 3.2/3.4/4.0 and recorded as
    # pagination/318ae05d and pagination/b2a85752.
    class Walk
      include Dexpace::Closeable

      def initialize(paginator)
        @paginator = paginator
        @next_request = paginator.template
        @current = nil
        @buffered = nil
        @exchanges = 0
        @exhausted = false
        initialize_closeable(owned: true)
      end

      attr_reader :current, :buffered

      # The ONE internal drive routine both views share (pagination/71aed9c1).
      def fetch_next_page
        return nil if @exhausted || @next_request.nil?          # PAGE-7: idempotent, no exchange
        return latch_exhausted if @exchanges >= @paginator.cap   # PAGE-9: checked BEFORE the exchange

        response = @paginator.transport.call(@next_request, @paginator.options, nil)  # PAGE-36
        @exchanges += 1
        info = parse_or_close(response)
        @next_request = info.next_request
        @exhausted = true if @next_request.nil?
        Dexpace::Page.build(response: response, items: info.items,
                            next_link: info.next_link, continuation_token: info.continuation_token)
      end

      def hold(page)
        Dexpace.close_quietly(@current) unless @current.equal?(page)
        @current = page
      end

      def buffer(page) = (@buffered = page)
      def take_buffered = (@buffered.tap { @buffered = nil })

      private

      def latch_exhausted
        @exhausted = true
        nil
      end

      # PAGE-13: the page is never constructed on this path, so nothing else would close the
      # response. The close failure must NOT mask the parse failure.
      def parse_or_close(response)
        @paginator.strategy.parse(response, @paginator.template)
      rescue ::StandardError => parse_error
        begin
          response.close
        rescue ::StandardError => close_error
          Dexpace.attach_suppressed(parse_error, close_error)
        end
        raise parse_error, cause: nil
      end

      # PAGE-15/PAGE-12: both slots, first failure primary, second attached.
      def release
        first = nil
        [@current, @buffered].compact.each do |page|
          page.close
        rescue ::StandardError => error
          first.nil? ? first = error : Dexpace.attach_suppressed(first, error)
        end
        @current = nil
        @buffered = nil
        raise first, cause: nil if first
      end
    end
    private_constant :Walk
  end
end
```

**Note for the executor.** `Dexpace.attach_suppressed` is silently a no-op on a **frozen** primary (phase 4b's
`P4-13`). That caveat is stated in `#parse_or_close`'s and `#release`'s YARD; it is not worked around, because
working around it would mean raising while attaching, which is the single failure `RECOV-12` exists to
prevent.

- [ ] **Step 4: `private_constant`, require, run to confirm it passes.**

---

## Task 11: `Dexpace::Page::Items`

**Requirement IDs:** `PAGE-1`, `PAGE-8` (item-view half), `PAGE-11`.
**Design:** "`Dexpace::Page::Items`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/page/items.rb`, `sig/dexpace/page/items.rbs`
- Test: `gems/dexpace-core/test/dexpace/page/items_test.rb`

**Needs:** Task 10.
**Produces:** `Items#each`, `#close`; `include ::Enumerable`.

- [ ] **Step 1: Write the failing test**

```ruby
# PAGE-1, PAGE-8, PAGE-11.
#
# PAGE-11's eager close is not a convenience: it is what makes the item view safe on a host where an
# abandoned Enumerator's ensure never runs. At every yield point the walk holds nothing open, so the
# residue of pagination/b2a85752 on THIS view is zero.
class DexpacePageItemsTest < DexpaceTestCase
  test "PAGE-1: items are delivered in server order across page boundaries" do
    assert_equal([1, 2, 3, 4, 5], paginator_over([[1, 2], [3, 4], [5]]).items.to_a)
  end

  test "PAGE-11: taking one item from a multi-item first page closes it and fetches no second page" do
    a = ClosingProbe.new
    transport = CountingTransport.new([a, ClosingProbe.new])
    paginator = paginator_over([[1, 2], [3]], transport: transport)

    paginator.items.each { |_i| break }

    assert_equal(1, a.close_count)
    assert_equal(1, transport.calls.size)
  end

  test "PAGE-11: the page is closed BEFORE any of its items is yielded" do
    probe = ClosingProbe.new
    observed = []
    paginator_over([[1, 2]], transport: CountingTransport.new([probe]))
      .items.each { |_i| observed << probe.close_count }

    assert_equal([1, 1], observed)
  end

  test "PAGE-8: each independent iteration restarts from the initial request with fresh state" do
    transport = CountingTransport.new(Array.new(4) { |i| response_for(i) })
    items = paginator_over([[1], [2]], transport: transport).items

    assert_equal(items.to_a, items.to_a)
    assert_equal(4, transport.calls.size)   # two full fetch sequences
  end

  test "external iteration abandoned mid-#next strands nothing, because PAGE-11 already closed it" do
    probe = ClosingProbe.new
    enumerator = paginator_over([[1, 2]], transport: CountingTransport.new([probe])).items.to_enum(:each)
    enumerator.next
    GC.start
    GC.start

    assert_equal(1, probe.close_count)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails.** Expected: `NameError`.

- [ ] **Step 3: Write the class**

```ruby
def each
  return to_enum(:each) unless block_given?   # the ONLY block_given? in this subsystem, and it is
                                              # a return-an-enumerator idiom, never a guard

  walk = Walk.new(@paginator)                 # PAGE-8: fresh state per iteration
  begin
    while (page = walk.fetch_next_page)
      items = page.items                      # PAGE-11: already a frozen copy
      page.close                              # PAGE-11: close BEFORE yielding any item
      items.each { |item| yield item }
    end
  ensure
    close_walk(walk)                          # R8's $!-branching helper
  end
end
```

`close_walk` is the shared private helper implementing `R8`'s shape and lives in a `private_constant` mixin
(`Dexpace::Page::Closing`) that both views include, so the branch is written once:

```ruby
def close_walk(walk)
  primary = $!                                  # read BEFORE anything here can raise
  begin
    walk.close
  rescue ::StandardError => close_error
    raise if primary.nil?                       # PAGE-15: surface it
    Dexpace.attach_suppressed(primary, close_error)  # PAGE-13/PAGE-32: primary stays primary
  end
end
```

`Items#close` forwards to the walk it holds for the external-iteration case; its YARD names the residue and
`#close` as the remedy. The `return to_enum(:each) unless block_given?` line is the one permitted use of
`block_given?` and carries a comment saying so, because Task 17 greps for the identifier.

- [ ] **Step 4: `sig/` mirror with `include ::Enumerable[untyped]`, require, run to confirm it passes.**

---

## Task 12: `Dexpace::Page::Pages`

**Requirement IDs:** `PAGE-1`, `PAGE-12`, `PAGE-14`, `PAGE-15`.
**Design:** "`Dexpace::Page::Pages`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/page/pages.rb`, `sig/dexpace/page/pages.rbs`
- Test: `gems/dexpace-core/test/dexpace/page/pages_test.rb`

**Needs:** Task 10.
**Produces:** `Pages#each`, `#more?`, `#close`; `include ::Enumerable`.

- [ ] **Step 1: Write the failing test**

```ruby
# PAGE-1, PAGE-12, PAGE-14, PAGE-15. Up to two live pages can exist at once, which is why the
# look-ahead slot lives on the Walk and not in the enumerator's closure (pagination/9bdf90fc).
class DexpacePagePagesTest < DexpaceTestCase
  test "PAGE-1: the page view yields exactly one page object per page, with status and headers" do
    pages = paginator_over([[1], [2], [3]]).pages.to_a

    assert_equal(3, pages.size)
    assert_equal(200, pages.first.status.code)
  end

  test "PAGE-12: the previous page is closed as the consumer advances" do
    probes = Array.new(3) { ClosingProbe.new }
    seen = []
    paginator_over([[1], [2], [3]], transport: CountingTransport.new(probes))
      .each_page { |_p| seen << probes.map(&:close_count) }

    assert_equal([[0, 0, 0], [1, 0, 0], [1, 1, 0]], seen)
  end

  test "PAGE-12: the last page is closed at exhaustion" do
    probes = Array.new(2) { ClosingProbe.new }
    paginator_over([[1], [2]], transport: CountingTransport.new(probes)).each_page { |_p| }

    assert_equal([1, 1], probes.map(&:close_count))
  end

  test "PAGE-12: probing without advancing, then closing, releases the prefetched page" do
    probes = Array.new(2) { ClosingProbe.new }
    view = paginator_over([[1], [2]], transport: CountingTransport.new(probes)).pages

    assert(view.more?)
    view.close

    assert_equal(1, probes.first.close_count)
  end

  test "PAGE-12: breaking out of a page loop inside a scoped close releases the held page" do
    probes = Array.new(2) { ClosingProbe.new }
    paginator_over([[1], [2]], transport: CountingTransport.new(probes)).each_page { |_p| break }

    assert_equal(1, probes.first.close_count)
  end

  test "PAGE-14: the iterator may be obtained at most once; re-iteration fails" do
    view = paginator_over([[1]]).pages
    view.each { |_p| }

    assert_raises(Dexpace::InvalidArgumentError) { view.each { |_p| } }
  end

  test "PAGE-8: two separate views from one paginator each drive a full fetch sequence" do
    transport = CountingTransport.new(Array.new(4) { |i| response_for(i) })
    paginator = paginator_over([[1], [2]], transport: transport)
    paginator.pages.to_a
    paginator.pages.to_a

    assert_equal(4, transport.calls.size)
  end

  test "PAGE-15: a close error while releasing a held page is SURFACED, not swallowed" do
    probe = ClosingProbe.new(raise_on_close: IOError.new("boom"))
    view = paginator_over([[1]], transport: CountingTransport.new([probe])).pages

    assert(view.more?)
    assert_raises(IOError) { view.close }
  end
end
```

- [ ] **Step 2: Run test to confirm it fails.** Expected: `NameError`.

- [ ] **Step 3: Write the class**

`Pages.new(paginator)` allocates its **one** `Walk` immediately. `#each` latches `@viewed` and raises
`Dexpace::InvalidArgumentError` on a second call (`PAGE-14`). The loop: take the buffered page if one is
staged, else `fetch_next_page`; `walk.hold(page)` — which closes the previously held page (`PAGE-12`);
`yield page`. The `ensure` is `close_walk(walk)` from Task 11's mixin. `#more?` fills the look-ahead slot via
`walk.buffer(walk.fetch_next_page)` and returns whether one is staged; its YARD's **first sentence** states
that it runs an HTTP exchange. `#close` forwards to the walk, which releases both slots.

- [ ] **Step 4: `sig/` mirror, require, run to confirm it passes.**

---

## Task 13: `Dexpace::Page::Paginator`

**Requirement IDs:** `PAGE-6`, `PAGE-8` (engine half), `PAGE-9`, `PAGE-10`, `PAGE-36`.
**Design:** "`Dexpace::Page::Paginator`"; "`R10`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/page/paginator.rb`, `sig/dexpace/page/paginator.rbs`
- Test: `gems/dexpace-core/test/dexpace/page/paginator_test.rb`

**Needs:** Tasks 10, 11, 12.
**Produces:** `Paginator.build`, `#items`, `#pages`, `#each_item`, `#each_page`.

- [ ] **Step 1: Write the failing test**

```ruby
# PAGE-6, PAGE-8, PAGE-9, PAGE-10, PAGE-36.
class DexpacePagePaginatorTest < DexpaceTestCase
  test "PAGE-6 (blocking engine): construction and obtaining a view trigger ZERO exchanges" do
    transport = CountingTransport.new([response_for(1)])
    paginator = paginator_over([[1]], transport: transport)

    assert_equal(0, transport.calls.size)
    paginator.items
    assert_equal(0, transport.calls.size)
    paginator.items.to_enum(:each)
    assert_equal(0, transport.calls.size)
    paginator.pages
    assert_equal(0, transport.calls.size)
  end

  test "PAGE-6: exactly one exchange per page actually consumed" do
    transport = CountingTransport.new(Array.new(3) { |i| response_for(i) })
    paginator_over([[1], [2], [3]], transport: transport).items.first(1)

    assert_equal(1, transport.calls.size)
  end

  test "PAGE-9: the cap is validated strictly positive AT CONSTRUCTION, not lazily" do
    [0, -1, 0.0].each do |cap|
      assert_raises(Dexpace::InvalidArgumentError) { paginator_over([[1]], cap: cap) }
    end
  end

  test "PAGE-10: the default cap is effectively unbounded" do
    assert_equal(Float::INFINITY, paginator_over([[1]]).cap)
    assert_equal(500, paginator_over([[1]] * 600, transport: repeating_transport(600)).items.count)
  end

  test "PAGE-8: the engine holds only immutable configuration and is safe to share" do
    paginator = paginator_over([[1]])

    assert_predicate(paginator, :frozen?)
    assert_empty(paginator.instance_variables - %i[@transport @template @strategy @cap @options])
  end

  test "PAGE-36: the default is no overrides" do
    assert_same(Dexpace::RequestOptions::EMPTY, paginator_over([[1]]).options)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails.** Expected: `NameError`.

- [ ] **Step 3: Write the `Data`**

`Data.define(:transport, :template, :strategy, :cap, :options)`, `include Dexpace::Model`,
`private_class_method :new`, `.build(transport:, template:, strategy:, cap: ::Float::INFINITY, options:
Dexpace::RequestOptions::EMPTY)`. Validation lives in the model's `initialize` so `.build`, `#with` and a
forged `send(:new, …)` all meet it: `transport.respond_to?(:call)`, `strategy.respond_to?(:parse)`,
`template` a `Dexpace::Request`, and **`cap.positive?`** — which `Float::INFINITY` satisfies (verified).
`#items` and `#pages` allocate views; `#each_item` and `#each_page` are the scoped block openers whose YARD
tells consumers to use them (`PAGE-12`'s documentation clause). `.build`'s YARD carries `PAGE-10`'s second
half: **direct production callers to set a finite cap.**

- [ ] **Step 4: `sig/` mirror, require, run to confirm it passes.**

---

## Task 14: `Dexpace::Page::AsyncPaginator`

**Requirement IDs:** `PAGE-25`, `PAGE-26`, `PAGE-27`, `PAGE-28`, `PAGE-29`, `PAGE-30`, `PAGE-31`, `PAGE-32`,
`PAGE-33`; `PAGE-6`'s async half.
**Design:** "`Dexpace::Page::AsyncPaginator`"; "`R9`"; "`R10`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/page/async_paginator.rb`, `sig/dexpace/page/async_paginator.rbs`
- Modify: `gems/dexpace-core/sig/dexpace/page/strategy.rbs` (add `interface _Executor`)
- Test: `gems/dexpace-core/test/dexpace/page/async_paginator_test.rb`

**Needs:** Tasks 5, 10, 13; phase 2's `Async::Future`/`Completer`/`Settlement`; Task 1's `ProbeExecutor`.
**Produces:** `AsyncPaginator.build`, `#walk(consumer, cancellation: nil) -> Dexpace::Async::Future`.

- [ ] **Step 1: Write the failing test**

```ruby
# PAGE-25 .. PAGE-33.
#
# R9: this engine calls no wait of any kind -- not Clock#sleep, not Async.delay -- because not one
# of PAGE-25..PAGE-33 computes or requests a delay. P5-9's no-scheduler SeamError is unreachable
# from here, and the default mode needs no scheduler, no executor and no thread: the driver is a
# callback pump on Future#on_settle, run on the settling thread, which is PAGE-29's stated default.
class DexpacePageAsyncPaginatorTest < DexpaceTestCase
  test "PAGE-6 (non-blocking engine): construction is inert; invoking walk fetches immediately" do
    transport = CountingTransport.new([response_for(1)], mode: :async_deferred)
    async = async_paginator_over([[1]], transport: transport)

    assert_equal(0, transport.calls.size)
    async.walk(->(_i) {})
    assert_equal(1, transport.calls.size)
  end

  test "PAGE-29: items are delivered one at a time, in server order, never concurrently" do
    seen = []
    depth = 0
    max = 0
    future = async_paginator_over([[1, 2], [3]]).walk(lambda { |i|
      depth += 1
      max = [max, depth].max
      seen << i
      depth -= 1
    })
    future.wait

    assert_equal([1, 2, 3], seen)
    assert_equal(1, max)
  end

  test "PAGE-29: with an executor, every consumer invocation runs on that executor" do
    executor = ProbeExecutor.new(mode: :deferred)
    threads = []
    async = async_paginator_over([[1], [2]], executor: executor)
    future = async.walk(->(_i) { threads << Thread.current })
    executor.drain
    future.wait

    assert_operator(executor.post_count, :>=, 1)
    assert(threads.all? { |t| executor.threads.include?(t) })
  end

  test "PAGE-31: thousands of synchronously-completed pages complete with no stack overflow" do
    # Verified: recursive future composition raises SystemStackError at ~11,000 frames; the while
    # pump completes 200,000 with no growth. The INLINE path is the one that needs the trampoline.
    [nil, ProbeExecutor.new(mode: :inline)].each do |executor|
      count = 0
      future = async_paginator_over(Array.new(20_000) { [1] }, executor: executor)
                 .walk(->(_i) { count += 1 })
      future.wait

      assert_equal(20_000, count)
      refute_predicate(future, :cancelled?)
    end
  end

  test "PAGE-25: cancelling the result future halts the walk and cancels the in-flight exchange" do
    transport = CountingTransport.new(Array.new(5) { response_for(1) }, mode: :async_deferred)
    future = async_paginator_over([[1]] * 5, transport: transport).walk(->(_i) {})
    future.cancel(:test)

    assert_predicate(transport.last_future, :cancelled?)
    transport.settle_next
    assert_equal(1, transport.calls.size)
  end

  test "PAGE-26: a fetched-but-undrained page is dropped AND closed, close errors swallowed" do
    probe = ClosingProbe.new(raise_on_close: IOError.new("boom"))
    transport = CountingTransport.new([probe], mode: :async_deferred)
    future = async_paginator_over([[1]], transport: transport).walk(->(_i) {})
    future.cancel(:test)
    transport.settle_next
    future.wait

    assert_equal(1, probe.close_count)   # closed
    # and no masking error: the walk ends on the cancellation, not on the IOError
  end

  test "PAGE-27: each page's response closes exactly once on all four paths" do
    # normal completion / parse failure / cancellation / executor rejection
    # one instrumented response per path, asserting close_count == 1
  end

  test "PAGE-28: consumer throw, transport failure, parse failure and eager throw each fail the walk" do
    cause = KeyError.new("k")
    future = async_paginator_over([[1]]).walk(->(_i) { raise cause })

    error = assert_raises(KeyError) { future.value }
    assert_same(cause, error)          # the ORIGINAL cause, unwrapped
  end

  test "PAGE-28: a transport that eagerly throws is handled as a failed walk" do
    transport = CountingTransport.new([-> (*) { raise IOError, "eager" }], mode: :async_immediate)

    assert_raises(IOError) { async_paginator_over([[1]], transport: transport).walk(->(_i) {}).value }
  end

  test "PAGE-30: an executor that rejects a re-dispatch fails the walk and closes the staged page" do
    executor = ProbeExecutor.new(mode: :rejecting, after: 1)
    probe = ClosingProbe.new
    transport = CountingTransport.new([response_for(1), probe])
    future = async_paginator_over([[1], [2]], transport: transport, executor: executor).walk(->(_i) {})

    assert_raises(ProbeExecutor::Rejected) { future.value }
    assert_equal(1, probe.close_count)
  end

  test "PAGE-32: a throwing close on the SUCCESS path completes the future exceptionally, not hangs" do
    probe = ClosingProbe.new(raise_on_close: IOError.new("boom"))
    future = async_paginator_over([[1]], transport: CountingTransport.new([probe])).walk(->(_i) {})

    assert_raises(IOError) { Timeout_free_value(future) }   # a bounded wait; "hangs" is the failure
  end

  test "PAGE-32: if the consumer already failed, that cause stays primary and the close error is swallowed" do
    probe = ClosingProbe.new(raise_on_close: IOError.new("close"))
    cause = KeyError.new("consumer")
    future = async_paginator_over([[1]], transport: CountingTransport.new([probe])).walk(->(_i) { raise cause })

    assert_same(cause, assert_raises(KeyError) { future.value })
  end
end
```

`Timeout_free_value` is a test helper waiting on the future with a bounded poll and failing the assertion on
expiry — **not** `Timeout.timeout`, which `Dexpace/NoThreadInterrupt` bans in `test/` as well as in `lib/`.

- [ ] **Step 2: Run test to confirm it fails.** Expected: `NameError`.

- [ ] **Step 3: Write the class**

`Data.define(:transport, :template, :strategy, :cap, :options, :executor)` with the same validation as Task
13 plus `executor.nil? || executor.respond_to?(:post)`. `#walk(consumer, cancellation: nil)`:

- allocate a `Completer`, a `Walk`-shaped state bundle and a `@rearm` flag guarded by a `::Thread::Mutex`
  **held across the flag flip only**;
- `completer.on_cancel { |reason| in_flight&.cancel(reason) }` — `PAGE-25`;
- the pump is `while take_rearm; dispatch_one; end`, and `dispatch_one` either runs inline or is submitted
  through `executor.post { … }` — every `#post` call site wrapped in `rescue ::StandardError` that fails the
  walk and closes any staged page (`PAGE-30`);
- `transport.call` is wrapped in `rescue ::StandardError` for `PAGE-28`'s eager-throw clause;
- `#on_settle` dispatches on the `Settlement`: `response` → parse (with `PAGE-13`'s inline close on failure) →
  build the page → **check settled before draining** (`PAGE-26`: a staged page on an already-settled walk is
  `Dexpace.close_quietly`'d and dropped) → deliver each item serially → close the page in an `ensure` that
  reads `$!` and branches per `R8` (`PAGE-32`) → re-arm; `error` → `completer.fail(error)` **unwrapped**
  (`PAGE-28`; phase 2's pivot wraps nothing, so there is nothing to unwrap); **`else` → fail the walk with a
  `Dexpace::SeamError`**, which is `PAGE-28`'s null-success clause given a code site even though
  `Settlement`'s own validation makes it unreachable.

`#walk`'s YARD carries `PAGE-33` verbatim: the inherent cancellation race, and the port's behaviour — a
request already dispatched that completes after the abort **is closed and discarded**, and a response the
transport never delivered because the cancel won the race is the transport's to release.

- [ ] **Step 4: `sig/` mirrors including `interface _Executor`, require, run to confirm it passes.**

---

## Task 15: `Dexpace::Page::Fetchers`

**Requirement IDs:** `PAGE-34`, `PAGE-35`.
**Design:** "`Dexpace::Page::Fetchers`"; "`PAGE-35`: vacuous by construction, not declined".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/page/fetchers.rb`, `sig/dexpace/page/fetchers.rbs`
- Test: `gems/dexpace-core/test/dexpace/page/fetchers_test.rb`

**Needs:** Tasks 5, 10.
**Produces:** `Fetchers.build(first:, next_page:, options:)`, `#items`, `#pages`, `#each_item`, `#each_page`.

- [ ] **Step 1: Write the failing test**

```ruby
# PAGE-34, PAGE-35.
class DexpacePageFetchersTest < DexpaceTestCase
  test "PAGE-34: the first-page fetcher is called exactly once" do
    calls = 0
    front = Dexpace::Page::Fetchers.build(
      first: -> { calls += 1; page_with(items: [1], next_link: nil) },
      next_page: ->(_key) { flunk("must not be called") },
    )
    front.items.to_a

    assert_equal(1, calls)
  end

  test "PAGE-34: subsequent pages key off the previous page's next link; next link WINS" do
    keys = []
    front = Dexpace::Page::Fetchers.build(
      first: -> { page_with(items: [1], next_link: "L", continuation_token: "T") },
      next_page: ->(key) { keys << key; page_with(items: [2], next_link: nil) },
    )
    front.items.to_a

    assert_equal(["L"], keys)
  end

  test "PAGE-34: with no next link, the continuation token is the fallback" do
    keys = []
    front = Dexpace::Page::Fetchers.build(
      first: -> { page_with(items: [1], next_link: nil, continuation_token: "T") },
      next_page: ->(key) { keys << key; page_with(items: [2], next_link: nil) },
    )
    front.items.to_a

    assert_equal(["T"], keys)
  end

  test "PAGE-34: a blank next link with no fallback token ends the stream" do
    front = Dexpace::Page::Fetchers.build(
      first: -> { page_with(items: [1], next_link: "   ", continuation_token: nil) },
      next_page: ->(_key) { flunk("must not be called") },
    )

    assert_equal([1], front.items.to_a)
  end

  test "PAGE-34: a nil page from either fetcher ends the stream; a nil FIRST page yields empty" do
    assert_empty(Dexpace::Page::Fetchers.build(first: -> { nil }, next_page: ->(_k) { nil }).items.to_a)
  end

  test "PAGE-34: a fetcher's page owns its response; the front-end closes it, the fetcher does not" do
    probe = ClosingProbe.new
    front = Dexpace::Page::Fetchers.build(
      first: -> { Dexpace::Page.build(response: probe, items: [1]) },
      next_page: ->(_k) { nil },
    )
    front.items.to_a

    assert_equal(1, probe.close_count)
  end

  test "PAGE-35: the SAME options instance is threaded through every fetcher call" do
    options = Dexpace::RequestOptions.build(timeout: 1.0)
    seen = []
    front = Dexpace::Page::Fetchers.build(
      first: ->(o) { seen << o; page_with(items: [1], next_link: "L") },
      next_page: ->(_k, o) { seen << o; page_with(items: [2], next_link: nil) },
      options: options,
    )
    front.items.to_a

    assert_equal(2, seen.size)
    seen.each { |o| assert_same(options, o) }
  end
end
```

- [ ] **Step 2: Run test to confirm it fails.** Expected: `NameError`.

- [ ] **Step 3: Write the front-end**

A `Data` holding the two fetchers and the frozen `options`, producing the same `Items`/`Pages` surface over a
`Walk`-shaped drive routine whose `fetch_next_page` calls the fetchers instead of a transport and a strategy.
The fetchers are called with `options` when they accept a second parameter, per their arity, so a caller who
does not want it writes a one-parameter lambda. `PAGE-34`'s four termination branches are four explicit
conditions; `PAGE-35`'s vacuity is stated in the YARD together with what the port supplies in its place —
`Page#continuation_token` as the first-class per-page state channel, and the caller's own closure for
anything else.

- [ ] **Step 4: `sig/` mirror, require, run to confirm it passes.**

---

## Task 16: The lifetime inversion suite

**Requirement IDs:** `PAGE-13`, `PAGE-15`, `PAGE-32` — the cross-cutting assertions no single component test
covers.
**Design:** "`R8`"; "Testing strategy", group 4.

**Files:**
- Create: `gems/dexpace-core/test/dexpace/page/lifetime_test.rb`

**Needs:** Tasks 11, 12, 14.
**Produces:** nothing in `lib/`. This is the suite that fails if a bare `ensure` was written anywhere.

- [ ] **Step 1: Write the failing test**

```ruby
# PAGE-13, PAGE-15, PAGE-32 -- the inversion suite.
#
# VERIFIED on 3.4.10: a bare `ensure` whose close raises while a consumer exception is already in
# flight REPLACES the consumer's exception as the primary (Ruby sets #cause to it). That is the
# exact inverse of PAGE-13's and PAGE-32's conformance clauses, and it is the shape a competent Ruby
# author writes by default. Every test below passes under either shape EXCEPT the two marked
# INVERSION, which are why this file exists.
class DexpacePageLifetimeTest < DexpaceTestCase
  test "INVERSION, PAGE-13: consumer raises AND close raises -> the CONSUMER's error is primary" do
    probe = ClosingProbe.new(raise_on_close: IOError.new("close"))
    cause = KeyError.new("consumer")

    error = assert_raises(KeyError) do
      paginator_over([[1]], transport: CountingTransport.new([probe])).each_page { |_p| raise cause }
    end

    assert_same(cause, error)
    assert_equal(["close"], Dexpace.suppressed(error).map(&:message))
  end

  test "INVERSION, PAGE-32 (async): consumer failure stays primary; the close error is swallowed" do
    probe = ClosingProbe.new(raise_on_close: IOError.new("close"))
    cause = KeyError.new("consumer")
    future = async_paginator_over([[1]], transport: CountingTransport.new([probe])).walk(->(_i) { raise cause })

    assert_same(cause, assert_raises(KeyError) { future.value })
  end

  test "PAGE-15: with NOTHING in flight, a close error is surfaced through a short-circuiting terminal" do
    probe = ClosingProbe.new(raise_on_close: IOError.new("close"))

    assert_raises(IOError) do
      paginator_over([[1], [2]], transport: CountingTransport.new([probe, ClosingProbe.new]))
        .each_page { |_p| break }
    end
  end

  test "P7-1: the surfaced close error is NOT wrapped -- Ruby has no terminal that cannot declare it" do
    # PAGE-15's middle clause ("re-thrown wrapped") is conditional on a terminal that cannot declare
    # the underlying I/O error type. Verified four ways on 3.4.10: Enumerable#first, Lazy#first(2),
    # an explicit break, and a plain block all deliver the close error unwrapped. Vacuous antecedent,
    # design §11.15's family. This test asserts the concrete class, so a wrapper introduced later
    # fails loudly rather than quietly changing what a caller must rescue.
    probe = ClosingProbe.new(raise_on_close: IOError.new("close"))
    error = assert_raises(IOError) do
      paginator_over([[1]], transport: CountingTransport.new([probe])).each_page { |_p| }
    end

    assert_instance_of(IOError, error)
  end

  test "PAGE-15: both held pages fail to close -> first primary, second suppressed" do
    first = ClosingProbe.new(raise_on_close: IOError.new("first"))
    second = ClosingProbe.new(raise_on_close: IOError.new("second"))
    view = paginator_over([[1], [2]], transport: CountingTransport.new([first, second])).pages
    view.each { |_p| break }
    view.more?

    error = assert_raises(IOError) { view.close }

    assert_equal("first", error.message)
    assert_equal(["second"], Dexpace.suppressed(error).map(&:message))
  end

  test "the frozen-primary caveat is stated and observable, not worked around" do
    # Phase 4b's P4-13: attach_suppressed silently no-ops on a frozen primary. Asserting the
    # behaviour rather than pretending it does not exist.
    probe = ClosingProbe.new(raise_on_close: IOError.new("close"))
    cause = KeyError.new("consumer").freeze

    error = assert_raises(KeyError) do
      paginator_over([[1]], transport: CountingTransport.new([probe])).each_page { |_p| raise cause }
    end

    assert_same(cause, error)
    assert_empty(Dexpace.suppressed(error))
  end
end
```

- [ ] **Step 2: Run and confirm which tests fail**

If Tasks 10–14 were written correctly this suite is green on first run. **If any INVERSION test fails, a bare
`ensure` was written**; fix the offending site rather than the test.

- [ ] **Step 3: Grep for the shape rather than trusting the suite**

```bash
grep -rn 'ensure' gems/dexpace-core/lib/dexpace/page/ gems/dexpace-core/lib/dexpace/page.rb
```

Every hit must be within three lines of a `primary = $!` or be an `ensure` that closes nothing. Record the
audit in the task's notes.

---

## Task 17: Final wiring, audits and the register texts

**Requirement IDs:** none new; `NFR-3`, `NFR-4`, `NFR-11`, `NFR-13` are exercised.
**Design:** "Module layout"; `P7-2`; "The findings proposed for the registers".

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace.rb` (the thirteen requires)
- Modify: the committed runtime surface manifest and the RBS baseline

- [ ] **Step 1: Add the requires to `lib/dexpace.rb`**

In dependency order: `page`, then `page/info`, `page/query_rewriter`, `page/link_header`,
`page/cursor_strategy`, `page/page_number_strategy`, `page/link_strategy`, `page/walk`, `page/items`,
`page/pages`, `page/paginator`, `page/async_paginator`, `page/fetchers`. Explicit requires, never an
autoloader — every autoloader is a gem and `SEAM-1` bars core from depending on one.

- [ ] **Step 2: The constant-shadowing audit (`P7-2`)**

`Dexpace::Page` is a class **and** the namespace, so every nested name is a shadowing candidate inside that
lexical scope. Run the audit rather than asserting the design's sentence:

```bash
ruby -e 'require "dexpace"; %w[Info QueryRewriter LinkHeader CursorStrategy PageNumberStrategy \
  LinkStrategy Walk Items Pages Paginator AsyncPaginator Fetchers Closing].each { |n| \
  puts "#{n}: core=#{Object.const_defined?(n)} dexpace=#{Dexpace.const_defined?(n, false)}" }'
```

Any `true` in either column is a shadowing hazard of the species `OI-3`/`P3-7` records and must be renamed
before the surface snapshot is regenerated.

- [ ] **Step 3: The `block_given?` and `Timeout` audits**

```bash
grep -rn 'block_given?' gems/dexpace-core/lib/dexpace/page/ gems/dexpace-core/lib/dexpace/page.rb
grep -rn 'Timeout\|Thread#raise\|Thread#kill\|Regexp\.timeout' gems/dexpace-core/lib/dexpace/page/
```

The first must return **only** the two `return to_enum(:each) unless block_given?` lines in `Items` and
`Pages`, each carrying its comment. The second must return nothing.

- [ ] **Step 4: The `Fiber[]` assertion**

One test, in `lifetime_test.rb`, asserting what verified fact 8 measured: a correlation value set in `Fiber[]`
before a view is first driven **is** visible inside the drive routine, and `Thread.current[]` is not. It is
not a `PAGE` requirement; it is the property that silently breaks and that no `PAGE` row would catch.

- [ ] **Step 5: Run every gate**

```bash
(cd gems/dexpace-core && bundle exec rake test)
bundle exec rake gates:serde_isolation
bundle exec rubocop
bundle exec steep check
bundle exec rbs validate
bundle exec rake
```

- [ ] **Step 6: Regenerate both halves of the API lock**

`bundle exec rake surface:regenerate` for the runtime surface snapshot, and the `sig/**/*.rbs` baseline diff.
**Both**, because RBS describes what someone wrote and the snapshot describes what Ruby defines; `Data.define`'s
generated readers are invisible to the first. Review the diff rather than accepting it: every new public name
should already appear in `P7-2`'s ledger row, and a name in the diff that is not in the row is a name that
arrived by accident.

- [ ] **Step 7: Hand the four register texts to a human**

The design's *findings proposed for the registers* section carries all four in full. **This plan does not
edit a register file.** They are: the `PAGE-15` vacuity addition to design §12's `PAGE` row and
`docs/deviations.md`; the amendment to the charter's corpus-attribution finding (the SSE-under-`PAGE-14`
defect is a **pair**, and `pagination/b2a85752` carries `BODY-11` rather than no ID); the new `docs/open-items.md`
row for §12's serde-agnosticism being harvested nowhere; and the `docs/first-release.md` line requiring phase
8's conformance suite to carry a per-call-options test for `PAGE-36`.

- [ ] **Step 8: The checklist**

Written at execution time, per `CLAUDE.md`, at
`docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination-checklist.md`. **One row per requirement ID, all
36**, each naming the task number above that satisfies it, with the six *state-rather-than-tick* rows the
design names carrying their clause. It is not a task this plan performs.
