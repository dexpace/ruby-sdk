# Phase 6b — Redirect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `dexpace-core`'s synchronous redirect pillar step — `Dexpace::Redirect::Step` at
`Stages::REDIRECT` — satisfying all 28 `REDIR-1`–`REDIR-28` requirements (`REDIR-27` declined for v1 —
`docs/first-release.md` § What v1 ships without — no code), plus the shared `Dexpace::Resilience::Resend` replayability predicate `REDIR-6`
consults alongside `RETRY-5` and `AUTH-31`.

**Architecture:** One iterative (`REDIR-23`) pillar step that forks a fresh `Cursor` for every hop
it drives, the first included, and never calls its own `#call` (`pipeline/86343352`,
`docs/sdk-design-ruby/05-pipeline-architecture.md` §5.1). Per hop: classify the response's status
(`REDIR-1`/`2`), fast-path return on a non-redirect status with no allocation (`REDIR-21`),
otherwise always allocate a `ConditionSnapshot` and consult either a configured predicate or the
built-in decision (`REDIR-3`–`REDIR-5`, `REDIR-16`, `REDIR-17`, `REDIR-19`, `REDIR-20`), resolve
`Location` against the current hop through `URI::RFC3986_PARSER` (`REDIR-13`/`14`), strip userinfo
(`REDIR-12`), reject an HTTPS→HTTP downgrade unless opted in (`REDIR-15`), strip `Authorization`
unconditionally and `Cookie`/`Proxy-Authorization` on a cross-origin hop only (`REDIR-7`/`9`/`10`),
write the cross-origin marker into the fork's own `Stages::REDIRECT` cursor state (`REDIR-11`,
`REDIR-24`), manage response-body lifecycle deterministically (`REDIR-22`), and emit one of four
structured, redacted observability events (`REDIR-28`).

**Tech Stack:** Ruby 3.2–4.0 (tested on 3.4.10, this plan's Task 1 re-runs on 3.2.11/4.0.6), zero
new runtime dependencies (`uri`, already allowlisted and already required by phases 1/2), Minitest,
RBS + Steep, RuboCop with phase 0's custom cops, SimpleCov, YARD.

**Spec:** `docs/work/mvp/phase6/phase6b/2026-09-09-phase6b-redirect-design.md`, under the charter
`docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md`.
`docs/product-spec/10-redirect-handling.md` is the normative chapter;
`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` carries the canonical
text for all 28 `REDIR` IDs.

## Global Constraints

- **`dexpace-core` gains no dependency and the require allowlist does not grow.** The gemspec
  contains zero `add_dependency` lines (`SEAM-1`, `NFR-1`). This sub-phase requires only `uri`,
  already allowlisted.
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`).
- **`URI::RFC3986_PARSER` is pinned explicitly for every parse and every resolution**
  (`Dexpace/NoUriDefaultParser`). `Location.resolve` writes `URI::RFC3986_PARSER.join`, never
  `URI.join`, `URI.parse` or `URI.split`.
- **`downcase` is called with no arguments repository-wide** (`Dexpace/NoLocaleCaseFold`).
  `Origin.of`'s scheme/host fold uses bare `downcase`.
- **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are strictly forbidden**
  (`Dexpace/NoThreadInterrupt`). This sub-phase schedules nothing and waits on nothing of its own;
  every blocking call happens inside `cursor.fork(...).call(...)`.
- **Inside `module Dexpace`, every core constant is `::`-qualified**: `::URI`, `::Set`,
  `::StandardError`, `::Data`. `URI::InvalidURIError` is rescued as `::URI::InvalidURIError`.
- **Domain model construction pattern** for the one public `Data` this sub-phase ships
  (`ConditionSnapshot`): `Data.define`, `private_class_method :new`, `.build` with
  `Model.required!`, defensive collection copy via `Model.own`, shallow `freeze`.
- **A driving pillar step forks for *every* drive, the first included, and never calls its own
  `#call`** (`pipeline/86343352`). `Redirect::Step#call` never calls `cursor.call`; every downstream
  invocation is `cursor.fork(state: {...}).call(follow_up_request)`, including the very first hop.
- **`#fork` and `#call` are disjoint on one cursor** (4c `R11`). `Step` never calls both on the same
  cursor object.
- **Formatting:** double quotes, 2-space indentation, 100 columns, `consistent_comma` trailing
  commas.
- **Every new `lib/` file opens with the `require_relative`s for the core files it names.**
- **`Dexpace::Method::IDEMPOTENT` (five members, `RETRY`'s idempotent set) is never reused as the
  redirect allowed-method default.** `Step::DEFAULT_ALLOWED_METHODS` is its own two-member
  `{GET, HEAD}` set (`REDIR-3`, `REDIR-4`).
- **No test anywhere in this sub-phase matches `URI::InvalidURIError#message`.** It differs by one
  space between 3.2.11 and 4.0.6 (`url-and-query-encoding/08c54234`); every assertion is on the
  exception's **class**.
- **The three upstream API fences this sub-phase writes against, quoted from the plans that file
  them.** Nothing here may call a method outside them.
  - **Phase 1** (`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model.md`, Tasks 9, 11,
    12, 14): `Dexpace::Request::Builder` files `#method=`, `#url=`, `#headers=`, `#body=`,
    `#header(name, value)` and `#build` — **writers only, no readers**, so a builder is written to
    and never read back; `Dexpace::Request` files `#method`, `#url`, `#headers`, `#body`,
    `#new_builder`. `Dexpace::Headers` is immutable and files `#[]`, `#include?`, `#names`,
    `#entries`, `#size`, `#new_builder`; **mutation lives only on `Headers::Builder`**
    (`#add`, `#set`, `#remove` — each returning `self` — and `#build`). `Headers#names` returns the
    recorded **original casing**, so a negative header assertion uses `#include?`, which folds
    through `HeaderName.of`, never `refute_includes(headers.names, …)`, which passes for the wrong
    reason on a differently-cased header. Files live under `lib/dexpace/http/`: `require_relative
    "../http/method"`, not `"../method"`.
  - **Phase 4c** (`docs/work/mvp/phase4/phase4c/2026-09-09-phase4c-stage-pipeline.md`, Tasks 3, 5,
    8, 9, 10): `Dexpace::Pipeline.builder(transport:)` takes the transport as a **required
    keyword at builder construction**, `Builder#build` and `#build_async` take **no arguments**,
    `#append(step, stage: nil)`, `Entry.build(stage:, step:)` with `Entry.new` private, and
    **there is no `AsyncPipeline.builder`** — an async pipeline is
    `Dexpace::Pipeline::Builder.new(transport:).install_preset(entries).build_async`. The test
    doubles are top-level constants in `test/support/probe_steps.rb`: `ForkingProbe.new(times:,
    state_per_drive:)` writes, `StateProbe.new(stage_to_read:)` reads into `#reads`, and neither
    declares `#stage`.
  - **Phase 5b** (`docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction.md`,
    Tasks for `Event` and `Logger`): `Logger.build(sink:, context:, redactor:, diagnostic_keys:)`
    and `Logger::NULL`; `P5-17` fixes the public methods at `.build`, `#event`, `#enabled?`,
    `#context`, `#sink` — **no `#info`/`#warn`/`#info?`/`#warn?`**. `Logger#event(severity)` makes
    the enabled decision once and returns a live `Event` or `Event::INERT`; the event is finished
    with `#event(name)`, `#field(key, value)`, `#cause(error)`, `#emit`. A caller never constructs
    an `Event`. Tests assert against `Dexpace::RecordingSink#entries`, each entry carrying
    `#payload`.

### Commands

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/<path>_test.rb   # one suite, red or green
(cd gems/dexpace-core && bundle exec rake test)                     # the gem's whole suite
bundle exec rake                                                    # all seventeen gates
bundle exec rubocop
bundle exec steep check
bundle exec rbs validate
bundle exec rake surface:regenerate                                 # deliberate; last task only
```

### What Task 1 must verify before anything else relies on it

Only 3.4.10 is confirmed installed on the authoring machine (re-checked while writing this plan:
`mise ls` lists no Ruby; `~/.rbenv`, `~/.rvm`, `/opt/rubies` do not exist). Every fact this plan's
design cites was measured on 3.4.10 only. **Task 1 installs 3.2.11 and 4.0.6 and re-runs the three
floor-straddling facts on both** before Task 2 writes any code that depends on them:

1. `URI::Generic#userinfo = ""` clears both `#user` and `#password`; `#userinfo = nil` is a no-op.
2. `URI::RFC3986_PARSER.join` resolves both a relative and an absolute reference correctly and
   raises `::URI::InvalidURIError` (never a different class) on a malformed one.
3. `URI::RFC3986_PARSER.parse(...).host` performs no case normalisation; `.port` supplies the
   scheme default when omitted.

If any differs on the floor or the ceiling, the task records it here and the affected downstream
task narrows its YARD claim to the versions actually observed — no downstream task proceeds on an
un-narrowed assumption.

## This plan's open questions, resolved

1. **Whether `Redirect::Step` needs an `AsyncStep` sibling.** *Decision:* no. `REDIR-25`/`PIPE-32`
   require the async pipeline to ship no redirect step at all; `6b` adds no `Redirect::AsyncStep`
   and no `stage:` registration on the async side. `Stages::REDIRECT` stays installable-but-unused
   there, exactly as 4c left it.
2. **Which re-sendability predicate `REDIR-6` calls.** *Decision:* **not** `6a`'s
   `Resend.eligible?`. `6a`'s `R5` settles that method as `request.body.nil? ?
   request.method.idempotent? : request.body.replayable?`, because `RETRY-7` makes a body-less
   **non-idempotent** request un-re-sendable. `REDIR-6` asks only whether a present body is
   replayable and says nothing about idempotency — redirect method eligibility is `REDIR-3`/`4`'s
   configured allowed-method set — so calling `eligible?` here would refuse a body-less `POST` 307
   under an `allowed_methods:` that `REDIR-3`/`4` explicitly permit. Task 2 therefore adds
   `Dexpace::Resilience::Resend.replayable_body?(request)` and
   `Dexpace::Resilience::NotReplayableError` to the shared `Dexpace::Resilience` namespace and
   **defines no `eligible?`**; `6a`'s Task 5 defines `eligible?` in the same module. The module is
   shared, the two methods are not, and neither sub-phase no-ops on finding the file present. Stated
   in the design's *Independence* section and not re-argued here.
3. **Whether the cross-origin marker is written as `{cross_origin: true}`/`{cross_origin: false}` on
   every hop, or omitted entirely on a same-origin hop.** *Decision:* written on **every** hop,
   explicitly `false` on a same-origin one, never omitted. `Cursor#state(Stages::REDIRECT)` already
   returns the shared frozen empty hash for a fork that wrote *nothing* — a hop that forks without
   any `state:` argument would be indistinguishable from a pipeline with no `REDIRECT` step at all
   from `6c`'s reading side, which is the correct behaviour for "no REDIRECT step installed" but the
   *wrong* behaviour for "a `REDIRECT` step ran and decided same-origin," because a future extension
   reading a second key out of the same slot could not tell the two apart. Writing `false` explicitly
   costs one keyword pair and removes the ambiguity.

## Task order and dependency chain

Fourteen tasks, in buildable dependency order:

1. **Matrix fact verification** — installs `ruby@3.2.11`/`ruby@4.0.6`, re-runs the three
   floor-straddling facts; standalone.
2. `Dexpace::Resilience::Resend.replayable_body?` and `NotReplayableError` (`REDIR-6`'s
   dependency) — standalone. `Resend.eligible?` is `6a`'s and is never called from this sub-phase.
3. `Dexpace::Redirect::Origin` (private) — `REDIR-8`; standalone.
4. `Dexpace::Redirect::Location` (private) — `REDIR-13`, `REDIR-14`, `REDIR-18`; needs Task 1's
   verified facts.
5. `Dexpace::Redirect::ConditionSnapshot` — `REDIR-20`; needs phase 1's `Model`.
6. `Dexpace::Redirect::Events`/`::Keys` and `Dexpace::Redirect::SchemeDowngradeError` — `REDIR-28`,
   `REDIR-15`; needs phase 5b's `Instrumentation` classes.
7. Test support: `ScriptedTransport`, the `AUTH`-position credential probe — needed by every task
   from 9 onward.
8. `Dexpace::Redirect::Step` construction and options (`REDIR-3`, `REDIR-4`, `REDIR-5`, `REDIR-15`,
   `REDIR-17`, `REDIR-20`, `REDIR-26`) — needs Tasks 2–7.
9. `Step#call`'s fast path, snapshot allocation, and default decision (`REDIR-1`, `REDIR-2`,
   `REDIR-16`, `REDIR-17`, `REDIR-19`, `REDIR-21`) — needs Task 8.
10. Credential hygiene and the cross-origin marker fork (`REDIR-7`, `REDIR-8`, `REDIR-9`, `REDIR-10`,
    `REDIR-11`, `REDIR-24`) — needs Task 9. **The correctness-sensitive core.**
11. Location resolution, userinfo strip, and downgrade rejection (`REDIR-12`, `REDIR-13`, `REDIR-14`,
    `REDIR-15`) — needs Task 10.
12. Body lifecycle, replayability, and the 303 GET rebuild (`REDIR-5`, `REDIR-6`, `REDIR-22`,
    `REDIR-23`) — needs Task 11.
13. `REDIR-28` emission wiring at all four event sites — needs Task 12.
    - **13a (phase-level; the constructors phase 4c postponed)** — `Pipeline.standard`/`AsyncPipeline.standard` over
      `Builder#install_preset` (`PIPE-39`, `PIPE-24`, `PIPE-32`, `REDIR-25`). Executes here only if
      `6a` has already landed; otherwise it moves verbatim into `6a`'s plan. Needs Task 8 and `6a`'s
      Tasks 9–10. Lettered so no existing "Task N" citation renumbers.
14. Integration: extending 4c's `R11` negative assertion 4 to the real step, `6b`'s half of
    convergence point 1, final wiring (`lib/dexpace.rb`, `sig/` completeness, surface snapshot,
    RBS baseline) — needs Task 13 (and Task 13a, when it runs here).

---

## Task 1: Matrix Fact Verification

**Requirement IDs:** none directly; underwrites `REDIR-8`, `REDIR-12`, `REDIR-13`, `REDIR-14`,
`REDIR-18`.
**Design:** "Verified Ruby facts this document is built on."

**Files:**
- Create: `gems/dexpace-core/test/dexpace/redirect/matrix_facts_test.rb`

- [ ] **Step 1: Install the two interpreters this plan has not run on**

```bash
mise install ruby@3.2.11 ruby@4.0.6
mise exec ruby@3.2.11 -- ruby -v
mise exec ruby@4.0.6  -- ruby -v
```

- [ ] **Step 2: Write and run the three facts on 3.4.10**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "uri"

class RedirectMatrixFactsTest < DexpaceTestCase
  test "Fact 1: userinfo = \"\" clears both user and password; userinfo = nil is a no-op" do
    u = URI::RFC3986_PARSER.parse("https://user:pass@ex.com/p?q=1")
    u.userinfo = ""
    assert_equal("https://ex.com/p?q=1", u.to_s)
    assert_nil(u.user)

    u2 = URI::RFC3986_PARSER.parse("https://user:pass@ex.com/p?q=1")
    u2.userinfo = nil
    assert_equal("https://user:pass@ex.com/p?q=1", u2.to_s) # unchanged: the no-op, on purpose
  end

  test "Fact 2: join resolves relative and absolute references, raises URI::InvalidURIError" do
    assert_equal("https://h/v2/x", URI::RFC3986_PARSER.join("https://h/v1/x", "/v2/x").to_s)
    assert_equal("https://other/y",
                 URI::RFC3986_PARSER.join("https://h/v1/x?a=1", "https://other/y").to_s)
    assert_equal("https://h:8443/v1/y", URI::RFC3986_PARSER.join("https://h:8443/v1/x", "y").to_s)

    error = assert_raises(::URI::InvalidURIError) do
      URI::RFC3986_PARSER.join("https://a.example/base/x", "ht!tp://bad")
    end
    refute_nil(error) # asserted on class only, never on #message (url-and-query-encoding/08c54234)
  end

  test "Fact 3: URI performs no host case-folding and supplies the scheme-default port" do
    assert_equal("EX.com", URI::RFC3986_PARSER.parse("https://EX.com/").host)
    assert_equal(443, URI::RFC3986_PARSER.parse("https://ex.com/").port)
    assert_equal(80, URI::RFC3986_PARSER.parse("http://ex.com/").port)
    assert_equal(443, URI::RFC3986_PARSER.parse("https://ex.com:443/").port)
  end
end
```

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/redirect/matrix_facts_test.rb`.
Expected: PASS, 3 runs, 0 failures, 0 errors.

- [ ] **Step 3: Run on 3.2.11 and 4.0.6, paste both outputs here**

```bash
mise exec ruby@3.2.11 -- bundle exec ruby -w gems/dexpace-core/test/dexpace/redirect/matrix_facts_test.rb
mise exec ruby@4.0.6  -- bundle exec ruby -w gems/dexpace-core/test/dexpace/redirect/matrix_facts_test.rb
```

A failure on either column is a finding, not a blocker: narrow the affected task's YARD claim to
"observed on 3.4.10 [and 4.0.6]" and record the narrowing in the checklist's notes column when the
checklist is written. Nothing in Tasks 2–14 may rely on a fact across the full matrix until this
step's pasted output says it holds across the full matrix.

---

## Task 2: `Dexpace::Resilience::Resend.replayable_body?` and `NotReplayableError`

**Requirement IDs:** `REDIR-6` (this sub-phase's call site).
**Design:** "Independence," "Object model `6b` ships."

**Files:**
- Create (or extend, see Step 1): `gems/dexpace-core/lib/dexpace/resilience/resend.rb`,
  `gems/dexpace-core/sig/dexpace/resilience/resend.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/resilience/resend_replayable_body_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Body#replayable?` (phase 3b), `Dexpace::Error` (phase 2).
- Produces: `Dexpace::Resilience::Resend.replayable_body?(request) -> bool`,
  `Dexpace::Resilience::NotReplayableError`.
- **Does NOT produce, consume or call `Resend.eligible?`** — that method is `6a`'s (Task 5) and
  carries `RETRY-7`'s idempotency clause, which `REDIR-6` does not have. See this plan's open
  question 2.

- [ ] **Step 1: Check whether `6a` has already created the file**

```bash
test -f gems/dexpace-core/lib/dexpace/resilience/resend.rb && echo EXISTS || echo MISSING
```

**This task runs either way** — the module is shared, the methods are not. On `EXISTS`, add
`replayable_body?` beside `6a`'s `eligible?` in the existing `module Resend` body and add
`NotReplayableError` to the same file (`6a` does not define it), leaving `eligible?` untouched; the
`sig/` mirror and `lib/dexpace.rb` require are then already present and only the mirror grows. On
`MISSING`, write the whole file as Step 3 gives it. The test file name above is distinct from `6a`'s
`resend_test.rb` and its class name is distinct from `6a`'s `DexpaceResilienceResendTest`, so the
two suites coexist whichever lands first.

- [ ] **Step 2: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

class DexpaceResilienceReplayableBodyTest < DexpaceTestCase
  BodyDouble = Struct.new(:replayable) do
    def replayable? = replayable
  end
  RequestDouble = Struct.new(:body)

  test "REDIR-6: a request with no body is always replayable-eligible" do
    assert(Dexpace::Resilience::Resend.replayable_body?(RequestDouble.new(nil)))
  end

  test "REDIR-6: a request with a replayable body is eligible" do
    assert(Dexpace::Resilience::Resend.replayable_body?(RequestDouble.new(BodyDouble.new(true))))
  end

  test "REDIR-6: a request with a non-replayable body is not eligible" do
    refute(Dexpace::Resilience::Resend.replayable_body?(RequestDouble.new(BodyDouble.new(false))))
  end

  test "REDIR-6: replayable_body? asks nothing about the method -- that is RETRY-7's clause, " \
       "carried by 6a's Resend.eligible? and never by this one" do
    # A body-less POST: not re-sendable for RETRY (RETRY-7), but perfectly re-issuable on a 307
    # whose allowed_methods the caller widened to include POST (REDIR-3/REDIR-4). A REDIR-6 gate
    # that consulted #idempotent? would refuse a redirect the specification permits.
    assert(Dexpace::Resilience::Resend.replayable_body?(RequestDouble.new(nil)))
  end

  test "REDIR-6: NotReplayableError names replayability in its message" do
    error = Dexpace::Resilience::NotReplayableError.new("redirect")
    assert_match(/replayable/, error.message)
    assert_kind_of(Dexpace::Error, error)
  end
end
```

- [ ] **Step 2b: Run test to confirm it fails**

Expected: `NameError: uninitialized constant Dexpace::Resilience`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/resilience/resend.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  module Resilience
    # The re-sendability namespace. It holds TWO predicates and they are not interchangeable:
    #
    #   .eligible?(request)        6a, RETRY-5/6/7/8 and RECOV-18 -- a body-less request is
    #                              re-sendable iff its METHOD is idempotent (RETRY-7).
    #   .replayable_body?(request) 6b, REDIR-6 -- a request is re-issuable iff it carries no body
    #                              or its body is replayable. Method eligibility for a redirect is
    #                              REDIR-3/REDIR-4's configured allowed-method set and is decided
    #                              in Redirect::Step, not here.
    #
    # Calling .eligible? for REDIR-6 would refuse a body-less POST 307 under an allowed_methods:
    # the specification permits; calling .replayable_body? for RETRY-5 would re-send a POST.
    module Resend
      module_function

      # REDIR-6. @param request [Dexpace::Request]
      # @return [Boolean] true if request has no body, or its body is replayable.
      def replayable_body?(request)
        body = request.body
        body.nil? || body.replayable?
      end
    end

    # Raised at the call site (never here) when a re-send is attempted on a non-replayable body.
    # The message names "replayable" by word, per REDIR-6's "message names replayability."
    class NotReplayableError < ::StandardError
      include Dexpace::Error

      def initialize(context)
        super("#{context} cannot be replayed: the request body is not replayable")
      end
    end
  end
end
```

- [ ] **Step 4: Write the RBS mirror**

```rbs
module Dexpace
  module Resilience
    module Resend
      def self.replayable_body?: (Dexpace::Request request) -> bool
    end

    class NotReplayableError < StandardError
      include Dexpace::Error

      def initialize: (String context) -> void
    end
  end
end
```

If `6a` landed first its `def self.eligible?` line is already in this mirror; add the one line above
beside it and leave it alone.

- [ ] **Step 5: Add requires to `lib/dexpace.rb`; run test to confirm it passes**

Expected: PASS, 5 runs, 0 failures, 0 errors.

---

## Task 3: `Dexpace::Redirect::Origin` (private)

**Requirement IDs:** `REDIR-8`.
**Design:** "Object model," verified fact 3.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/redirect/origin.rb`
- Test: none dedicated — asserted at `Step`'s call sites (Task 10), following 5a's `ConfigParsers`/
  `DeepValue` precedent for a `private_constant` with no public contract of its own.

- [ ] **Step 1: Write `gems/dexpace-core/lib/dexpace/redirect/origin.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Redirect
    # The RFC 6454 origin tuple REDIR-8 compares. Never URI#==: URI performs no host
    # normalisation and no default-port inference through #host, so the comparison is an
    # explicitly constructed [scheme, host, port] triple, per design §6.2.
    module Origin
      module_function

      # @param uri [URI::Generic] absolute; #port already resolves the scheme default.
      # @return [Array(String, String, Integer)]
      def of(uri)
        [uri.scheme.downcase, uri.host.downcase, uri.port]
      end

      # @param seed_triple [Array(String, String, Integer)] Origin.of(seed_request.url), computed
      #   once and threaded through the whole hop loop -- REDIR-8 compares against the SEED, never
      #   the previous hop.
      # @param target [URI::Generic]
      # @return [Boolean]
      def cross?(seed_triple, target)
        seed_triple != of(target)
      end
    end
  end
end
```

- [ ] **Step 2: `private_constant :Origin` inside the enclosing `Redirect` module declaration in
  `lib/dexpace/redirect.rb` (Task 8 creates that file's namespace declaration)**

No test runs yet; Task 10 exercises this module through `Step`.

---

## Task 4: `Dexpace::Redirect::Location` (private)

**Requirement IDs:** `REDIR-13`, `REDIR-14`, `REDIR-18` (this module's half; `Step` does the
conversion and the `REDIR-19` missing-header check).
**Design:** "R7 — the Location parsing route."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/redirect/location.rb`
- Test: none dedicated — see Task 3's rationale; exercised through `Step` in Tasks 10–11.

- [ ] **Step 1: Write `gems/dexpace-core/lib/dexpace/redirect/location.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "set"
require "uri"

module Dexpace
  module Redirect
    # Resolves a Location header value against the current hop's request URL (REDIR-14), via one
    # call to URI::RFC3986_PARSER.join -- which handles both a relative and an absolute reference
    # correctly and without re-rendering an already-percent-encoded component (REDIR-13, verified
    # fact 2). Raises the bare ::URI::InvalidURIError on any malformed or unresolvable reference
    # (REDIR-18); Step converts it BY CLASS, never by inspecting #message
    # (url-and-query-encoding/08c54234: the message differs by one space across the matrix).
    module Location
      module_function

      # REDIR-18's third trigger, "an unsupported/unknown scheme". RFC 3986 resolution raises on
      # neither -- measured on 3.4.10, join("https://h/x", "mailto:a@b") returns a URI::MailTo
      # whose #host is nil and join("https://h/x", "ftp://o/z") a valid URI::FTP -- so the scheme
      # is screened here rather than surfacing downstream as NoMethodError on nil.host inside
      # Origin.of, or as "cannot set user with opaque" out of #userinfo=.
      SUPPORTED_SCHEMES = ::Set["http", "https"].freeze

      # @param current_url [URI::Generic] always absolute (HTTP-47).
      # @param header_value [String] the raw Location header value.
      # @return [URI::Generic] NOT frozen and NOT yet userinfo-stripped. Step strips (REDIR-12)
      #   and freezes once afterwards -- freezing here makes that strip raise FrozenError.
      # @raise [::URI::InvalidURIError] malformed reference, or unsupported scheme (REDIR-18).
      def resolve(current_url, header_value)
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

**Do not add `.freeze` to the return value.** `Step` assigns `#userinfo = ""` to this object
(`REDIR-12`) and a frozen `URI` raises there — measured on 3.4.10:
`URI::RFC3986_PARSER.join("https://h/v1/x", "/v2/x").freeze.userinfo = ""` →
`FrozenError: can't modify frozen URI::HTTPS`. The freeze happens once, after the strip, in
`Step#resolve_target` (Task 11).

No isolated test: Task 10's Step suite exercises absolute, relative and malformed inputs together
with the credential-hygiene assertions that give them meaning (a `Location` resolution divorced
from what happens to the result next tests nothing this sub-phase's stake is about).

---

## Task 5: `Dexpace::Redirect::ConditionSnapshot`

**Requirement IDs:** `REDIR-20`.
**Design:** "R9 — REDIR-20's condition snapshot."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/redirect/condition_snapshot.rb`,
  `gems/dexpace-core/sig/dexpace/redirect/condition_snapshot.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/redirect/condition_snapshot_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`, `Dexpace::Response`.
- Produces: `Dexpace::Redirect::ConditionSnapshot` — `.build(response:, redirect_count:,
  visited_uris:)`, `#response`, `#redirect_count`, `#visited_uris`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

class DexpaceRedirectConditionSnapshotTest < DexpaceTestCase
  def build_response
    Dexpace::Response.build(request: SAMPLE_REQUEST, protocol: Dexpace::Protocol::HTTP_1_1,
                             status: Dexpace::Status.of(302), reason: "Found",
                             headers: Dexpace::Headers::EMPTY, body: nil)
  end

  test "REDIR-20: exposes response, redirect_count and visited_uris" do
    snap = Dexpace::Redirect::ConditionSnapshot.build(
      response: build_response, redirect_count: 1, visited_uris: Set["https://a.example/"],
    )
    assert_equal(1, snap.redirect_count)
    assert_equal(Set["https://a.example/"], snap.visited_uris)
  end

  test "REDIR-20: visited_uris is a frozen defensive copy, never the caller's Set" do
    caller_set = Set["https://a.example/"]
    snap = Dexpace::Redirect::ConditionSnapshot.build(
      response: build_response, redirect_count: 0, visited_uris: caller_set,
    )
    assert_predicate(snap.visited_uris, :frozen?)
    refute_same(caller_set, snap.visited_uris)
    caller_set << "https://b.example/"
    refute_includes(snap.visited_uris, "https://b.example/") # the mutation never leaks back
  end

  test "REDIR-20: required fields raise Dexpace::InvalidArgumentError naming the field" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Redirect::ConditionSnapshot.build(response: nil, redirect_count: 0,
                                                  visited_uris: Set.new)
    end
    assert_equal("response is required", error.message)
  end

  test "the generated constructor is private" do
    assert_raises(NoMethodError) { Dexpace::Redirect::ConditionSnapshot.new(response: nil,
                                                                             redirect_count: 0,
                                                                             visited_uris: Set.new) }
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Expected: `NameError: uninitialized constant Dexpace::Redirect`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/redirect/condition_snapshot.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "set"

require_relative "../model"

module Dexpace
  module Redirect
    # The READ-ONLY, defensively-copied snapshot handed to a caller-supplied redirect predicate
    # (REDIR-20). Public API: it crosses into caller code, so it gets the full phase-1 domain-model
    # treatment rather than being an internal detail.
    class ConditionSnapshot < Data.define(:response, :redirect_count, :visited_uris)
      include Model
      private_class_method :new

      def initialize(response:, redirect_count:, visited_uris:)
        Model.required!(:response, response)
        Model.required!(:redirect_count, redirect_count)
        Model.required!(:visited_uris, visited_uris)

        super(response: response, redirect_count: redirect_count,
              visited_uris: Model.own(::Set.new(visited_uris)))
      end

      def self.build(response:, redirect_count:, visited_uris:)
        new(response: response, redirect_count: redirect_count, visited_uris: visited_uris)
      end
    end
  end
end
```

- [ ] **Step 4: Write the RBS mirror**

```rbs
module Dexpace
  module Redirect
    class ConditionSnapshot
      attr_reader response: Dexpace::Response
      attr_reader redirect_count: Integer
      attr_reader visited_uris: Set[String]

      def self.build: (response: Dexpace::Response, redirect_count: Integer,
                       visited_uris: Set[String]) -> ConditionSnapshot
    end
  end
end
```

- [ ] **Step 5: Add requires to `lib/dexpace.rb`; run test to confirm it passes**

Expected: PASS, 4 runs, 0 failures, 0 errors.

---

## Task 6: `Dexpace::Redirect::Events`/`::Keys` and `SchemeDowngradeError`

**Requirement IDs:** `REDIR-28` (this task's constants), `REDIR-15` (the error class).
**Design:** "R8 — REDIR-28's emission site," object model.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/redirect/events.rb`,
  `gems/dexpace-core/lib/dexpace/redirect/errors.rb`, both `sig/` mirrors
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/redirect/events_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

class DexpaceRedirectEventsTest < DexpaceTestCase
  test "REDIR-28: five frozen event-name constants" do
    assert_predicate(Dexpace::Redirect::Events::HOP_FOLLOWED, :frozen?)
    assert_predicate(Dexpace::Redirect::Events::LOOP_DETECTED, :frozen?)
    assert_predicate(Dexpace::Redirect::Events::SCHEME_DOWNGRADE_REJECTED, :frozen?)
    assert_predicate(Dexpace::Redirect::Events::SCHEME_DOWNGRADE_PERMITTED, :frozen?)
    assert_predicate(Dexpace::Redirect::Events::LOCATION_MALFORMED, :frozen?)
  end

  test "REDIR-15: the permitted-downgrade event is a DIFFERENT name from the rejected one" do
    # An opt-in downgrade that logged \"scheme_downgrade_rejected\" would say the opposite of what
    # happened. REDIR-15's \"MUST surface it observably\" binds on the permitted branch.
    refute_equal(Dexpace::Redirect::Events::SCHEME_DOWNGRADE_REJECTED,
                 Dexpace::Redirect::Events::SCHEME_DOWNGRADE_PERMITTED)
  end

  test "REDIR-28: Keys::LOCATION_RAW is distinct from every URL-valued key" do
    refute_equal(Dexpace::Redirect::Keys::LOCATION_RAW, Dexpace::Redirect::Keys::FROM_URL)
    refute_equal(Dexpace::Redirect::Keys::LOCATION_RAW, Dexpace::Redirect::Keys::TO_URL)
  end

  test "REDIR-15: SchemeDowngradeError is a Dexpace::Error naming the downgrade" do
    error = Dexpace::Redirect::SchemeDowngradeError.new("https://a/", "http://a/")
    assert_kind_of(Dexpace::Error, error)
    assert_match(%r{https://a/}, error.message)
    assert_match(%r{http://a/}, error.message)
  end
end
```

- [ ] **Step 2: Run to confirm it fails; then write both files**

`gems/dexpace-core/lib/dexpace/redirect/events.rb` — exactly as given in the design's `R8` section
(`Events::HOP_FOLLOWED`/`::LOOP_DETECTED`/`::SCHEME_DOWNGRADE_REJECTED`/
`::SCHEME_DOWNGRADE_PERMITTED`/`::LOCATION_MALFORMED`;
`Keys::FROM_URL`/`::TO_URL`/`::REDIRECT_COUNT`/`::STATUS_CODE`/`::LOCATION_RAW`).

`gems/dexpace-core/lib/dexpace/redirect/errors.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  module Redirect
    # REDIR-15's "fail with a clear error" on an HTTPS -> HTTP downgrade rejected by default.
    class SchemeDowngradeError < ::StandardError
      include Dexpace::Error

      def initialize(from_url, to_url)
        super("redirect from #{from_url} to #{to_url} would downgrade HTTPS to HTTP; " \
              "opt in with allow_scheme_downgrade: true if this is intended")
      end
    end
  end
end
```

- [ ] **Step 3: Write both RBS mirrors, add requires to `lib/dexpace.rb`, run test to confirm it
  passes**

Expected: PASS, 4 runs, 0 failures, 0 errors.

---

## Task 7: Test support — `ScriptedTransport` and the credential probe

**Requirement IDs:** none directly; underwrites the convergence-point-1 half-test and every
credential-hygiene assertion from Task 10 onward.
**Design:** "Testing strategy."

**Files:**
- Create: `gems/dexpace-core/test/support/scripted_transport.rb`,
  `gems/dexpace-core/test/support/credential_probe.rb`

- [ ] **Step 1: Write `test/support/scripted_transport.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Test
    # A #call(request, options, cancellation) terminal transport returning one prepared Response
    # per call, in order, and recording every request it received so a test can assert on headers
    # the redirect step sent -- not only on the final response. No transport, no socket
    # (roadmap cross-cutting constraint 4).
    class ScriptedTransport
      attr_reader :received_requests, :responses

      # `log:` is a shared array the fake response bodies also append to, so a test can assert the
      # ORDER of sends against closes -- which is the only way to catch a REDIR-22a close deferred
      # past the next send, since the close-flag assertions pass either way.
      def initialize(responses, log: [])
        @responses = responses.dup
        @received_requests = []
        @call_count = 0
        @log = log
      end

      def call(request, _options, _cancellation)
        @received_requests << request
        @call_count += 1
        @log << :send
        response = @responses.fetch(@call_count - 1) do
          raise "ScriptedTransport exhausted after #{@call_count} calls"
        end
        response.is_a?(Proc) ? response.call(request) : response
      end
    end
  end
end
```

- [ ] **Step 2: Write `test/support/credential_probe.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Test
    # Installed at Stages::AUTH downstream of a real Dexpace::Redirect::Step. Stamps a fixed
    # Authorization header UNLESS the marker Redirect::Step wrote says this hop is cross-origin --
    # and records every decision so the test can assert none was wrong, rather than only asserting
    # the final wire header. This is 6b's half of convergence point 1 (design, "Convergence
    # points"): the full end-to-end test with a REAL auth step is 6c's.
    class CredentialProbe
      attr_reader :decisions

      def initialize(token: "secret-token")
        @token = token
        @decisions = []
      end

      def stage = Dexpace::Pipeline::Stages::AUTH

      def call(request, cursor)
        suppressed = cursor.state(Dexpace::Pipeline::Stages::REDIRECT)[:cross_origin] == true
        @decisions << { url: Dexpace::URL.external_form(request.url), suppressed: suppressed }

        to_send = suppressed ? request : request.new_builder.header("Authorization",
                                                                      "Bearer #{@token}").build
        cursor.call(to_send)
      end
    end
  end
end
```

---

## Task 8: `Dexpace::Redirect::Step` — construction and options

**Requirement IDs:** `REDIR-3`, `REDIR-4`, `REDIR-5`, `REDIR-15`, `REDIR-17`, `REDIR-20`,
`REDIR-26`.
**Design:** "Object model," `Step`'s constructor listing.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/redirect.rb` (namespace declaration + `private_constant`
  lines for `Origin`/`Location`), `gems/dexpace-core/lib/dexpace/redirect/step.rb`,
  `gems/dexpace-core/sig/dexpace/redirect/step.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/redirect/step_test.rb` (construction section; grows in
  Tasks 9–13)

**Interfaces:**
- Consumes: `Dexpace::Method`, `Dexpace::Pipeline::Stages`, `Dexpace::Instrumentation::Logger::NULL`,
  `Dexpace::Instrumentation::Redactor::DEFAULT`.
- Produces: `Dexpace::Redirect::Step.new(...)`, `#stage`, `#call(request, cursor)` (signature only
  in this task; behaviour in Tasks 9–13).

- [ ] **Step 1: Write the failing construction tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/scripted_transport"
require_relative "../../support/credential_probe"
require "dexpace"

class DexpaceRedirectStepConstructionTest < DexpaceTestCase
  test "REDIR-26: default allowed_methods is exactly {GET, HEAD}, frozen, decoupled from callers" do
    step = Dexpace::Redirect::Step.new
    assert_equal(Set[Dexpace::Method.of("GET"), Dexpace::Method.of("HEAD")],
                 step.allowed_methods)
    assert_predicate(step.allowed_methods, :frozen?)
  end

  test "REDIR-26: does not conflate with Dexpace::Method::IDEMPOTENT's five members" do
    refute_equal(Dexpace::Method::IDEMPOTENT.size, Dexpace::Redirect::Step.new.allowed_methods.size)
  end

  test "REDIR-26: a caller-supplied collection is duplicated and frozen, decoupled from the caller" do
    caller_methods = [Dexpace::Method.of("POST")]
    step = Dexpace::Redirect::Step.new(allowed_methods: caller_methods)
    caller_methods << Dexpace::Method.of("DELETE")
    assert_equal(1, step.allowed_methods.size) # the later mutation never reaches the step
  end

  test "REDIR-17: max_hops defaults to 3, and 0 is accepted (disables following)" do
    assert_equal(3, Dexpace::Redirect::Step.new.max_hops)
    assert_equal(0, Dexpace::Redirect::Step.new(max_hops: 0).max_hops)
  end

  test "REDIR-17: a negative max_hops is rejected" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Redirect::Step.new(max_hops: -1) }
  end

  test "installs at Stages::REDIRECT" do
    assert_equal(Dexpace::Pipeline::Stages::REDIRECT, Dexpace::Redirect::Step.new.stage)
  end

  test "logger and redactor default to the no-op and the real default, respectively" do
    step = Dexpace::Redirect::Step.new
    assert_same(Dexpace::Instrumentation::Logger::NULL, step.instance_variable_get(:@logger))
    assert_same(Dexpace::Instrumentation::Redactor::DEFAULT,
                step.instance_variable_get(:@redactor))
  end
end
```

- [ ] **Step 2: Run to confirm it fails; write `lib/dexpace/redirect.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Redirect
  end
end
```

- [ ] **Step 3: Write `lib/dexpace/redirect/step.rb`, construction section**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "set"

require_relative "../redirect"
require_relative "../error/invalid_argument_error"
require_relative "../pipeline/stages"
require_relative "../http/method"
require_relative "../http/url"
require_relative "../instrumentation/logger"
require_relative "../instrumentation/redactor"
require_relative "../instrumentation/severity"
require_relative "origin"
require_relative "location"
require_relative "condition_snapshot"
require_relative "events"
require_relative "errors"
require_relative "../resilience/resend"

module Dexpace
  module Redirect
    # The synchronous redirect pillar step at Stages::REDIRECT. Forks a fresh Cursor for EVERY
    # hop it drives, the first included, and never calls #call on its own cursor
    # (pipeline/86343352). See docs/work/mvp/phase6/phase6b/2026-09-09-phase6b-redirect-design.md.
    class Step
      # REDIR-3/REDIR-4's default -- deliberately NOT Dexpace::Method::IDEMPOTENT (5 members).
      DEFAULT_ALLOWED_METHODS = ::Set[Dexpace::Method.of("GET"), Dexpace::Method.of("HEAD")].freeze
      RECOGNIZED_CODES = ::Set[301, 302, 303, 307, 308].freeze

      attr_reader :allowed_methods, :follow303, :max_hops, :allow_scheme_downgrade, :predicate

      def initialize(allowed_methods: DEFAULT_ALLOWED_METHODS, follow303: false, max_hops: 3,
                     allow_scheme_downgrade: false, predicate: nil,
                     logger: Dexpace::Instrumentation::Logger::NULL,
                     redactor: Dexpace::Instrumentation::Redactor::DEFAULT)
        raise Dexpace::InvalidArgumentError, "max_hops is required" if max_hops.nil?
        raise Dexpace::InvalidArgumentError, "max_hops must be >= 0" if max_hops.negative?

        @allowed_methods = ::Set.new(allowed_methods.map { |m| Dexpace::Method.of(m) }).freeze
        @follow303 = follow303
        @max_hops = max_hops
        @allow_scheme_downgrade = allow_scheme_downgrade
        @predicate = predicate
        @logger = logger
        @redactor = redactor
      end

      def stage = Dexpace::Pipeline::Stages::REDIRECT

      # Tasks 9-13 fill this in; Task 8 only wires the signature so #stage and construction are
      # independently testable first.
      def call(request, cursor)
        raise NotImplementedError, "filled in by Task 9"
      end
    end
  end
end
```

Every `require_relative` above is against the path phase 1 and phase 4c actually file: `Method`,
`URL`, `Request`, `Response` and `Headers` live under `lib/dexpace/http/` (so `"../http/method"`,
never `"../method"`), while `Model`, `Error` and the pipeline tree do not.

- [ ] **Step 4: Write the RBS mirror, add requires to `lib/dexpace.rb`, run to confirm it passes**

Expected: PASS, 7 runs, 0 failures, 0 errors.

---

## Task 9: `Step#call` — fast path, snapshot, default decision

**Requirement IDs:** `REDIR-1`, `REDIR-2`, `REDIR-16`, `REDIR-17`, `REDIR-19`, `REDIR-21`.
**Design:** "R9 — REDIR-20's condition snapshot," the allocate-versus-short-circuit boundary.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/redirect/step.rb`
- Test: append to `step_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
class DexpaceRedirectStepDecisionTest < DexpaceTestCase
  def build_step(**kwargs) = Dexpace::Redirect::Step.new(**kwargs)

  # 4c files Pipeline.builder(transport:) with the transport as a REQUIRED keyword at builder
  # construction, and Builder#build with NO arguments. Every install in this suite names the stage
  # as an #append argument because no probe or step double here declares #stage.
  def run(step, responses, seed_url: "https://a.example/x")
    transport = Dexpace::Test::ScriptedTransport.new(responses)
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                .build
    request = Dexpace::Request.build(method: Dexpace::Method.of("GET"),
                                      url: Dexpace::URL.parse!(seed_url),
                                      headers: Dexpace::Headers::EMPTY, body: nil)
    [pipeline.call(request), transport]
  end

  test "REDIR-1/REDIR-2: a non-3xx and a non-recognized 3xx pass through verbatim" do
    [200, 300, 304, 305, 404, 500].each do |code|
      response, = run(build_step, [response_with(status: code)])
      assert_equal(code, response.status.code)
    end
  end

  test "REDIR-19: a 302 with no Location header is returned unfollowed" do
    response, transport = run(build_step, [response_with(status: 302, location: nil)])
    assert_equal(302, response.status.code)
    assert_equal(1, transport.received_requests.size) # no follow-up was ever sent
  end

  test "REDIR-16: a redirect loop back to the seed URI is detected and returns current, open" do
    response, transport = run(build_step, [
      response_with(status: 302, location: "https://a.example/y"),
      response_with(status: 302, location: "https://a.example/x"), # revisits the seed
    ])
    assert_equal(302, response.status.code)
    assert_equal(2, transport.received_requests.size)
    refute(response.body.nil? || response.body.closed?)
  end

  test "REDIR-17: max_hops caps the loop and returns the last response as-is" do
    responses = Array.new(5) { |i| response_with(status: 302, location: "https://a.example/#{i + 1}") }
    response, transport = run(build_step(max_hops: 2), responses)
    assert_equal(302, response.status.code) # still a redirect: the cap returned it unfollowed
    assert_equal(3, transport.received_requests.size) # seed + 2 followed hops, then stop
  end

  test "REDIR-17: max_hops 0 disables redirect following entirely" do
    response, transport = run(build_step(max_hops: 0),
                               [response_with(status: 302, location: "https://a.example/y")])
    assert_equal(302, response.status.code)
    assert_equal(1, transport.received_requests.size)
  end

  test "REDIR-20/REDIR-21: a configured predicate is consulted on a recognized 3xx and overrides " \
       "the default decision" do
    seen = []
    predicate = ->(snapshot) { seen << snapshot.redirect_count; false } # always refuses to follow
    response, transport = run(build_step(predicate: predicate),
                               [response_with(status: 302, location: "https://a.example/y")])
    assert_equal([0], seen)
    assert_equal(302, response.status.code) # predicate said no; step never followed
    assert_equal(1, transport.received_requests.size)
  end

  test "REDIR-21: the predicate is NEVER consulted for a non-recognized status" do
    predicate = ->(_snapshot) { raise "must not be called" }
    response, = run(build_step(predicate: predicate), [response_with(status: 404)])
    assert_equal(404, response.status.code)
  end

  test "REDIR-21: a recognized 3xx with no usable Location still allocates the snapshot and " \
       "consults the predicate" do
    seen = false
    predicate = ->(_snapshot) { seen = true; false }
    run(build_step(predicate: predicate), [response_with(status: 302, location: nil)])
    assert(seen)
  end

  test "REDIR-19 + REDIR-20: a predicate that says FOLLOW on a Location-less 3xx still returns " \
       "the response unfollowed, and does not raise" do
    # REDIR-20 overrides the FOLLOW decision. It does not waive REDIR-19's MUST. Reaching
    # Location.resolve with a nil header value raises ArgumentError from URI::RFC3986_PARSER.join
    # -- not even the InvalidURIError a rescue here would expect -- so the gate runs first.
    response, transport = run(build_step(predicate: ->(_s) { true }),
                               [response_with(status: 302, location: nil)])
    assert_equal(302, response.status.code)
    assert_equal(1, transport.received_requests.size)
  end

  test "REDIR-18: an unsupported scheme is returned unfollowed on BOTH decision routes" do
    %w[mailto:someone@example.test ftp://h/z].each do |location|
      [nil, ->(_s) { true }].each do |predicate|
        response, transport = run(build_step(predicate: predicate),
                                   [response_with(status: 302, location: location)])
        assert_equal(302, response.status.code)
        assert_equal(1, transport.received_requests.size)
      end
    end
  end

  test "REDIR-17: the cap vetoes a predicate that says FOLLOW, and the predicate is still " \
       "consulted at the cap (REDIR-21's NOTE)" do
    seen = []
    predicate = ->(snapshot) { seen << snapshot.redirect_count; true }
    response, transport = run(build_step(max_hops: 1, predicate: predicate), [
      response_with(status: 302, location: "https://a.example/y"),
      response_with(status: 302, location: "https://a.example/z"),
    ])
    assert_equal([0, 1], seen)   # consulted on the capped hop too, not short-circuited past
    assert_equal(302, response.status.code)
    assert_equal(2, transport.received_requests.size)
  end
end
```

(`response_with` is a small local helper building a `Dexpace::Response` with the given status and,
if given, a `Location` header pointed at the argument — added to this test file's top in this step.
Its body double tracks `#closed?` and, when the optional `log:` array is supplied, appends `:close`
to it, which is what Task 12's `REDIR-22a` ordering assertion reads. `extra_headers:` on
`seeded_post_request` seeds arbitrary headers for Task 12's `REDIR-5` prefix test.)

- [ ] **Step 2: Implement `#call`'s decision skeleton**

```ruby
def call(request, cursor)
  seed_triple = Origin.of(request.url)
  seed_method = request.method # REDIR-3/REDIR-4 say "the ORIGINAL request method", not this hop's
  drive(cursor, request, request.url, seed_triple, seed_method, 0,
        ::Set[Dexpace::URL.external_form(request.url)])
end

private

def drive(cursor, request, current_url, seed_triple, seed_method, redirect_count, visited)
  fork = cursor.fork
  response = fork.call(request)

  return response unless RECOGNIZED_CODES.include?(response.status.code) # REDIR-1, REDIR-21

  # REDIR-21's NOTE: a recognized 3xx ALWAYS allocates the snapshot, even with no usable Location.
  snapshot = ConditionSnapshot.build(response: response, redirect_count: redirect_count,
                                      visited_uris: visited)

  # REDIR-12/REDIR-18/REDIR-19, resolved ONCE, BEFORE either decision route and independently of
  # both: a predicate overrides the FOLLOW decision (REDIR-20), never the MUST-not-throw clauses.
  # The returned target is already userinfo-stripped and frozen, and is the same object the
  # REDIR-16 visited check and the follow-up builder both see -- so a server cannot defeat loop
  # detection by alternating `user:pass@` on an otherwise identical target.
  target = resolve_target(request, response)
  return response if target.nil? # unfollowed, body left open (REDIR-22c)

  decision = @predicate ? @predicate.call(snapshot) : default_follow?(seed_method, response, target,
                                                                       visited)
  return response unless decision

  # REDIR-17's cap is a hard ceiling applied OVER the answer, never in place of consulting it:
  # placing this above the predicate call would allocate a snapshot and discard it unread and
  # would make REDIR-21's "always ... consults the configured predicate" false. R9 argues it.
  return response if redirect_count >= @max_hops

  # Tasks 10-13 fill in hygiene, the marker fork and the next drive.
  raise NotImplementedError, "filled in by Task 10"
end

# REDIR-12, REDIR-18 (both triggers), REDIR-19. Returns nil for "return the current response
# unfollowed" and never raises. Task 13 wires the emit call.
def resolve_target(request, response)
  location = response.headers["Location"]&.first
  return nil if location.nil? || location.empty? # REDIR-19

  target = Location.resolve(request.url, location) # raises on malformed OR unsupported scheme
  target.userinfo = ""  # REDIR-12: "" clears user AND password; nil is a silent no-op (fact 1)
  target.freeze         # frozen HERE, once, after the strip -- never inside Location.resolve
rescue ::URI::InvalidURIError
  nil # REDIR-18: MUST NOT throw. Task 13 adds emit_location_malformed(location, error) here.
end

def default_follow?(seed_method, response, target, visited)
  return false if visited.include?(Dexpace::URL.external_form(target)) # REDIR-16

  case response.status.code
  when 301, 302, 307, 308
    @allowed_methods.include?(seed_method) # REDIR-3, REDIR-4: the ORIGINAL method
  when 303
    @follow303 # REDIR-5; method is irrelevant
  else
    false
  end
end
```

This skeleton intentionally raises past the point Task 10 fills in — the tests above only exercise
paths that return before reaching it (fast path, missing Location, loop, cap, predicate-refuses).
`seed_method` is threaded rather than re-read off the current hop's request because `REDIR-3` and
`REDIR-4` both say "the **ORIGINAL** request method": the two agree through any method-preserving
chain and diverge after a `follow303` GET rebuild, where the chain would otherwise continue under
`GET` and be admitted by the default `{GET, HEAD}` set that the seed `POST` is not in.

- [ ] **Step 3: Run the full `step_test.rb` to confirm this task's tests pass and Task 8's still do**

Expected: PASS for every test that does not reach the `NotImplementedError` branch; the tests in
this task are written to avoid it.

---

## Task 10: Credential hygiene and the cross-origin marker fork

**Requirement IDs:** `REDIR-7`, `REDIR-8`, `REDIR-9`, `REDIR-10`, `REDIR-11`, `REDIR-24`.
**Design:** "R7," full *Purpose* section, `pipeline/86343352`. **The correctness-sensitive core of
this sub-phase.**

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/redirect/step.rb`
- Test: append to `step_test.rb`

- [ ] **Step 1: Write the failing tests — every one of them a scenario named in the design's
  "tests a reader would otherwise write wrong"**

```ruby
class DexpaceRedirectStepCredentialHygieneTest < DexpaceTestCase
  # 4c: the transport is a REQUIRED keyword on Pipeline.builder, so it is supplied here rather
  # than at #build, which takes no arguments.
  def install_with_probe(step, transport)
    probe = Dexpace::Test::CredentialProbe.new
    builder = Dexpace::Pipeline.builder(transport: transport)
                               .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                               .append(probe, stage: Dexpace::Pipeline::Stages::AUTH)
    [builder, probe]
  end

  test "REDIR-7: Authorization is stripped before EVERY re-issue, same-origin and cross-origin" do
    step = Dexpace::Redirect::Step.new
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://a.example/y"),        # same-origin hop
      response_with(status: 302, location: "https://b.example/z"),        # cross-origin hop
      response_with(status: 200),
    ])
    pipeline_builder, probe = install_with_probe(step, transport)
    pipeline = pipeline_builder.build
    request = seeded_get_request("https://a.example/x", authorization: "Bearer caller-token")

    pipeline.call(request)

    # Every request the transport received after the first carries NO caller-supplied
    # Authorization -- REDIR-7 is unconditional, not "only on the cross-origin hop."
    transport.received_requests[1..].each do |sent|
      refute(sent.headers.include?("Authorization")) # #include? folds; #names is original casing
    end
  end

  test "REDIR-8: cross-origin is judged against the SEED, not the previous hop" do
    step = Dexpace::Redirect::Step.new
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://b.example/y"),  # seed A -> hop1 on B: cross
      response_with(status: 302, location: "https://b.example/z"),  # hop1(B) -> hop2 on B: SAME as
      response_with(status: 200),                                   #   hop1, but STILL judged
    ])                                                               #   against seed A -> cross
    pipeline = pipeline_builder.build
    pipeline.call(seeded_get_request("https://a.example/x"))

    assert_equal([true, true], probe.decisions.map { |d| d[:suppressed] })
  end

  test "REDIR-8: a same-origin sub-redirect on a foreign host is NOT re-marked cross-origin " \
       "merely because the seed differs from that host -- it is judged against the seed" do
    step = Dexpace::Redirect::Step.new
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://b.example/y"),  # seed A -> B: cross-origin
      response_with(status: 302, location: "https://b.example/z"),  # B -> B: SAME-origin as the
      response_with(status: 200),                                   #   PREVIOUS hop, but the seed
    ])                                                               #   was A, so still cross
    pipeline = pipeline_builder.build
    pipeline.call(seeded_get_request("https://a.example/x"))

    assert_equal([true, true], probe.decisions.map { |d| d[:suppressed] })
  end

  test "REDIR-9/REDIR-10: Cookie is stripped cross-origin and retained same-origin, in one chain" do
    step = Dexpace::Redirect::Step.new
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://a.example/y"),   # same-origin
      response_with(status: 302, location: "https://b.example/z"),   # cross-origin
      response_with(status: 200),
    ])
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build
    pipeline.call(seeded_get_request("https://a.example/x", cookie: "session=abc"))

    assert(transport.received_requests[1].headers.include?("Cookie"))  # same-origin: kept
    refute(transport.received_requests[2].headers.include?("Cookie"))  # cross-origin: gone
  end

  test "REDIR-11/REDIR-24: the marker is written false on every same-origin hop, true on every " \
       "cross-origin hop, and never once omitted" do
    step = Dexpace::Redirect::Step.new
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://a.example/y"),
      response_with(status: 302, location: "https://b.example/z"),
      response_with(status: 200),
    ])
    builder, probe = install_with_probe(step, transport)
    builder.build.call(seeded_get_request("https://a.example/x"))

    assert_equal(3, probe.decisions.size)          # once per hop, including the seed's own drive
    assert_equal([false, true, true], probe.decisions.map { |d| d[:suppressed] })
  end

  test "extends 4c's R11 negative assertion 4 to the REAL step: a probe downstream of the marker " \
       "cannot see the wrong slot, with production code as the writer" do
    step = Dexpace::Redirect::Step.new
    # 4c's doubles, under the names 4c ships: top-level constants in test/support/probe_steps.rb.
    # ForkingProbe is R11's WRITE side (it forks per drive with a named state map); StateProbe is
    # the READ side and records cursor.state(stage_to_read) into #reads. Neither declares #stage,
    # so both installs name the stage as an #append argument.
    retry_writer = ForkingProbe.new(times: 1, state_per_drive: [{ irrelevant: true }])
    redirect_reader = StateProbe.new(stage_to_read: Dexpace::Pipeline::Stages::REDIRECT)
    pipeline = Dexpace::Pipeline.builder(transport: Dexpace::Test::ScriptedTransport.new([
                                   response_with(status: 302, location: "https://b.example/z"),
                                   response_with(status: 200),
                                 ]))
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .append(retry_writer, stage: Dexpace::Pipeline::Stages::RETRY)
                                 .append(redirect_reader, stage: Dexpace::Pipeline::Stages::AUTH)
                                 .build
    pipeline.call(seeded_get_request("https://a.example/x"))

    # The AUTH-position reader sees REDIRECT's slot, written by the REAL step, and never RETRY's.
    assert_equal([{ cross_origin: false }, { cross_origin: true }], redirect_reader.reads)
  end

  test "extends 4c's R11 negative assertion 4 to the REAL step: RETRY's own slot is invisible " \
       "under Stages::REDIRECT even with a production writer at REDIRECT" do
    step = Dexpace::Redirect::Step.new
    retry_writer = ForkingProbe.new(times: 1, state_per_drive: [{ irrelevant: true }])
    retry_reader = StateProbe.new(stage_to_read: Dexpace::Pipeline::Stages::RETRY)
    pipeline = Dexpace::Pipeline.builder(transport: Dexpace::Test::ScriptedTransport.new([
                                   response_with(status: 302, location: "https://b.example/z"),
                                   response_with(status: 200),
                                 ]))
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .append(retry_writer, stage: Dexpace::Pipeline::Stages::RETRY)
                                 .append(retry_reader, stage: Dexpace::Pipeline::Stages::AUTH)
                                 .build
    pipeline.call(seeded_get_request("https://a.example/x"))

    assert_equal([{ irrelevant: true }, { irrelevant: true }], retry_reader.reads)
  end
end
```

- [ ] **Step 2: Implement the marker fork and stripping, replacing Task 9's `raise
  NotImplementedError`**

```ruby
def drive(cursor, request, current_url, seed_triple, seed_method, redirect_count, visited)
  cross_origin = Origin.cross?(seed_triple, current_url) # false on the seed's own first drive
  forked = cursor.fork(state: { cross_origin: cross_origin }) # REDIR-11, REDIR-24: written on
  response = forked.call(request)                             #   EVERY drive, the first included

  return response unless RECOGNIZED_CODES.include?(response.status.code)

  snapshot = ConditionSnapshot.build(response: response, redirect_count: redirect_count,
                                      visited_uris: visited)
  target = resolve_target(request, response) # Task 9: stripped and frozen once, before deciding
  return response if target.nil?

  decision = @predicate ? @predicate.call(snapshot) : default_follow?(seed_method, response,
                                                                       target, visited)
  return response unless decision
  return response if redirect_count >= @max_hops # the ceiling, OVER the answer (Task 9, R9)

  next_request = build_follow_up(request, current_url, target, response, seed_triple)
  # ... Task 11 fills in build_follow_up's body (downgrade, header hygiene); Task 12 fills in the
  # body-lifecycle close-before-next-drive and the recursion-as-loop rewrite (REDIR-22, 23).

  drive(cursor, next_request, target, seed_triple, seed_method, redirect_count + 1,
        visited << Dexpace::URL.external_form(target))
end

# REDIR-7 (unconditional), REDIR-9/REDIR-10 (cross-origin only).
def strip_headers(headers, cross_origin:)
  builder = headers.new_builder.remove("Authorization") # REDIR-7: every re-issue, no exception
  builder = builder.remove("Cookie").remove("Proxy-Authorization") if cross_origin # REDIR-9
  builder.build
end
```

`Origin.cross?(seed_triple, current_url)` on the **first** drive compares the seed's own URL against
itself, which is always `false` — the seed is same-origin with itself by definition, so hop 0's
marker is `false`, matching this task's third test's `[false, true, true]` sequence (index 0 is the
seed's own drive). `build_follow_up` is a named seam Task 11 fills in; it takes the **already
resolved, stripped and frozen** `target` rather than re-resolving, so there is exactly one
resolution per hop and the URL the loop records in `visited` is byte-identical to the one it sends.
This task's tests exercise only the marker and the stripping, both of which are already correct with
`build_follow_up` unbuilt, because every scenario above that reaches a second or third hop supplies
`location` values this task's *own* `build_follow_up` stub (added in this step, returning a request
with only the headers stripped and the URL swapped, no downgrade handling yet) makes just enough to
route through.

**Note for the implementing worker:** this task's `drive` is written recursively for exposition; the
iterative rewrite (`REDIR-23`) happens in Task 12, which turns this into a `while` loop with no
change to the marker/stripping logic — do not let the iterative rewrite reach into this task's
already-passing tests, which assert behaviour, not control-flow shape.

- [ ] **Step 3: Run the full suite to confirm this task's tests pass**

Expected: PASS. `NoMethodError: undefined method 'build_follow_up'` is the acceptable interim state
between Step 2's two code blocks; add the stub named above before running.

---

## Task 11: Location resolution, userinfo strip, downgrade rejection

**Requirement IDs:** `REDIR-12`, `REDIR-13`, `REDIR-14`, `REDIR-15`, `REDIR-18` (both triggers —
the malformed reference *and* the unsupported/unknown scheme).
**Design:** "R7," verified facts 1–2.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/redirect/step.rb`
- Test: append to `step_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
class DexpaceRedirectStepLocationTest < DexpaceTestCase
  test "REDIR-14: a relative Location resolves against the CURRENT hop, not the seed" do
    step = Dexpace::Redirect::Step.new
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "/v2/x"), # relative to https://h/v1/x -> https://h/v2/x
      response_with(status: 200),
    ])
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build
    pipeline.call(seeded_get_request("https://h/v1/x"))

    assert_equal("https://h/v2/x", Dexpace::URL.external_form(transport.received_requests[1].url))
  end

  test "REDIR-12/REDIR-13: userinfo is stripped, and the already-encoded path/query survive " \
       "byte-for-byte" do
    step = Dexpace::Redirect::Step.new
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://user:pass@h/a%2Fb?x=%26y"),
      response_with(status: 200),
    ])
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build
    pipeline.call(seeded_get_request("https://seed.example/x"))

    sent_url = Dexpace::URL.external_form(transport.received_requests[1].url)
    assert_equal("https://h/a%2Fb?x=%26y", sent_url) # no "user:pass@"; %2F and %26 intact
  end

  test "REDIR-15: an HTTPS -> HTTP downgrade is rejected by default, closing the current response" do
    step = Dexpace::Redirect::Step.new
    current = response_with(status: 302, location: "http://h/y")
    transport = Dexpace::Test::ScriptedTransport.new([current])
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build

    assert_raises(Dexpace::Redirect::SchemeDowngradeError) do
      pipeline.call(seeded_get_request("https://h/x"))
    end
    assert_predicate(current.body, :closed?) # REDIR-22b: closed before the error propagates
  end

  test "REDIR-15: the downgrade opt-in permits it and observably warns" do
    sink = Dexpace::RecordingSink.new
    step = Dexpace::Redirect::Step.new(
      allow_scheme_downgrade: true,
      logger: Dexpace::Instrumentation::Logger.build(sink: sink),
    )
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "http://h/y"),
      response_with(status: 200),
    ])
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build

    pipeline.call(seeded_get_request("https://h/x")) # does not raise
    assert_equal("http://h/y", Dexpace::URL.external_form(transport.received_requests[1].url))

    # REDIR-15: "permitted only via an opt-in that surfaces the downgrade observably." Permitting
    # it silently satisfies the first half of the clause and fails the second, and the URL
    # assertion above cannot tell the two apart -- which is why this assertion lives in this test
    # and is not deferred to Task 13.
    names = sink.entries.map { |e| e.payload[Dexpace::Instrumentation::Keys::EVENT] }
    assert_includes(names, Dexpace::Redirect::Events::SCHEME_DOWNGRADE_PERMITTED)
    refute_includes(names, Dexpace::Redirect::Events::SCHEME_DOWNGRADE_REJECTED)
  end

  test "REDIR-18: an unsupported scheme returns the current response unfollowed, body open" do
    step = Dexpace::Redirect::Step.new
    current = response_with(status: 302, location: "mailto:someone@example.test")
    transport = Dexpace::Test::ScriptedTransport.new([current])
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build

    response = pipeline.call(seeded_get_request("https://h/x"))

    assert_equal(302, response.status.code)
    assert_equal(1, transport.received_requests.size)
    refute_predicate(current.body, :closed?) # REDIR-22c: a "return current" outcome stays open
  end

  test "REDIR-18: a malformed Location is not thrown, and returns the current response unfollowed" do
    step = Dexpace::Redirect::Step.new
    transport = Dexpace::Test::ScriptedTransport.new([response_with(status: 302, location: "ht!tp://bad")])
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build

    response = pipeline.call(seeded_get_request("https://h/x"))
    assert_equal(302, response.status.code)
    assert_equal(1, transport.received_requests.size)
  end
end
```

- [ ] **Step 2: Implement `build_follow_up`**

```ruby
# `target` arrives already resolved, userinfo-stripped and frozen from Step#resolve_target (Task 9)
# -- this method never re-resolves, so there is exactly one resolution per hop and REDIR-16's
# visited check saw the same bytes this re-issue will send.
def build_follow_up(request, current_url, target, response, seed_triple)
  if downgrade?(current_url, target) # REDIR-15, evaluated per hop transition
    unless @allow_scheme_downgrade
      # The close lives in the caller's rescue (Task 12), which covers every raise out of this
      # method under one REDIR-22b path rather than one per failure shape.
      raise SchemeDowngradeError.new(Dexpace::URL.external_form(current_url),
                                      Dexpace::URL.external_form(target))
    end

    # REDIR-15's second half: the opt-in "MUST surface it observably". Task 13 wires the emitter;
    # this branch must exist for it to wire into, and Task 12's rewrite must not drop it.
    emit_scheme_downgrade_permitted(current_url, target)
  end

  # Task 12 adds the 303 rebuild and the REDIR-6 replayability gate here.
  request.new_builder.tap do |b|
    b.url = target
    b.headers = strip_headers(request.headers, cross_origin: Origin.cross?(seed_triple, target))
  end.build
end

def downgrade?(from_url, to_url)
  from_url.scheme.downcase == "https" && to_url.scheme.downcase == "http"
end
```

**Phase 1's `Request::Builder` files writers and no readers** (`#method=`, `#url=`, `#headers=`,
`#body=`, `#header(name, value)`, `#build`), so the stripped headers are derived from
`request.headers` — the immutable model, through its own `#new_builder` — and assigned back with
`#headers=`. There is no `builder.headers` to read, and `Headers` itself has no `#remove`; mutation
lives only on `Headers::Builder`.

`response.body.closed?` in this task's third test is asserted against phase 3b's own `Response#close`
contract; `Dexpace.close_quietly` is phase 2's discard-path close (`CFG-21`), used in Task 12's
rescue rather than a bare `response.body.close` because closing on the *raise* path must never itself
raise and mask the `SchemeDowngradeError` — exactly `REDIR-22b`'s "the current response MUST be
closed before the error propagates."

- [ ] **Step 3: Wire `build_follow_up`'s return into `drive` (replacing Task 10's stub) and run the
  full suite**

Expected: PASS, every test from Tasks 8–11.

---

## Task 12: Body lifecycle, replayability, and the 303 rebuild

**Requirement IDs:** `REDIR-5`, `REDIR-6`, `REDIR-22`, `REDIR-23`.
**Design:** "Testing strategy," the `REDIR-22a`/`22b`/`22c` scenarios.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/redirect/step.rb` — this task rewrites `drive` from
  recursion into the `while` loop `REDIR-23` requires, folding in body-close ordering and the 303
  rebuild
- Test: append to `step_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
class DexpaceRedirectStepLifecycleTest < DexpaceTestCase
  test "REDIR-5: a 303 is rebuilt as a GET with the body dropped and every Content-* header removed" do
    step = Dexpace::Redirect::Step.new(follow303: true)
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 303, location: "https://h/y"),
      response_with(status: 200),
    ])
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build
    original = seeded_post_request("https://h/x", content_type: "application/json",
                                    content_length: "13", body: json_body_double,
                                    extra_headers: { "Content-Language" => "en",
                                                     "Content-MD5" => "deadbeef",
                                                     "Accept" => "application/json" })
    pipeline.call(original)

    rebuilt = transport.received_requests[1]
    assert_equal("GET", rebuilt.method.token)
    assert_nil(rebuilt.body)
    refute(rebuilt.headers.include?("Content-Type"))
    refute(rebuilt.headers.include?("Content-Length"))
    # REDIR-5 says "every Content-* header", and its three examples are examples. A header the
    # implementation's list cannot have been written against is what makes this a prefix test.
    refute(rebuilt.headers.include?("Content-Language"))
    refute(rebuilt.headers.include?("Content-MD5"))
    assert(rebuilt.headers.include?("Accept")) # a non-Content-* header is untouched
  end

  test "REDIR-6: a non-replayable body on a followed 307 fails with a clear error, closing current" do
    step = Dexpace::Redirect::Step.new
    current = response_with(status: 307, location: "https://h/y")
    transport = Dexpace::Test::ScriptedTransport.new([current])
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build
    non_replayable = seeded_post_request("https://h/x", body: non_replayable_body_double)

    error = assert_raises(Dexpace::Resilience::NotReplayableError) { pipeline.call(non_replayable) }
    assert_match(/replayable/, error.message)
    assert_predicate(current.body, :closed?) # REDIR-22b
  end

  test "REDIR-6: a body-LESS non-idempotent method is re-issued, not refused -- REDIR-6 asks " \
       "about the body and RETRY-7's idempotency clause is not in scope here" do
    step = Dexpace::Redirect::Step.new(allowed_methods: [Dexpace::Method.of("POST")])
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 307, location: "https://h/y"),
      response_with(status: 200),
    ])
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build

    assert_equal(200, pipeline.call(seeded_post_request("https://h/x", body: nil)).status.code)
    assert_equal("POST", transport.received_requests[1].method.token) # REDIR-4: method preserved
  end

  test "REDIR-22a: the prior response is closed BEFORE the follow-up is issued, not after it " \
       "returns" do
    # The close-flag assertions in the next test pass for EITHER ordering. Only the order catches
    # a close deferred past the next send, which holds hop N's connection for the whole of hop
    # N+1 and deadlocks a one-connection pool. Design 6.2 -- "closes the prior response before
    # issuing a follow-up" -- and 4c's own ForkingProbe (the PIPE-40 fixture) both close first.
    log = []
    step = Dexpace::Redirect::Step.new
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://h/y", log: log),
      response_with(status: 200, log: log),
    ], log: log)
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build

    pipeline.call(seeded_get_request("https://h/x"))

    # :send (seed) -> :close (hop 1, superseded) -> :send (follow-up). A trailing :close would be
    # the deferred ordering; a [:send, :send, :close] log is the bug.
    assert_equal(%i[send close send], log)
  end

  test "REDIR-22a/22c: each superseded intermediate is closed; the final, returned response stays open" do
    step = Dexpace::Redirect::Step.new
    hop1 = response_with(status: 302, location: "https://h/y")
    hop2 = response_with(status: 302, location: "https://h/z")
    final = response_with(status: 200)
    transport = Dexpace::Test::ScriptedTransport.new([hop1, hop2, final])
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build

    result = pipeline.call(seeded_get_request("https://h/x"))

    assert_same(final, result)
    assert_predicate(hop1.body, :closed?)
    assert_predicate(hop2.body, :closed?)
    refute_predicate(final.body, :closed?) if final.body
  end

  test "REDIR-23: a chain of 200 hops does not overflow the stack" do
    step = Dexpace::Redirect::Step.new(max_hops: 5_000)
    responses = Array.new(5_000) { |i| response_with(status: 302, location: "https://h/#{i + 1}") }
    responses << response_with(status: 200)
    transport = Dexpace::Test::ScriptedTransport.new(responses)
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build

    assert_equal(200, pipeline.call(seeded_get_request("https://h/0")).status.code)
  end
end
```

- [ ] **Step 2: Rewrite `#call`/`drive` as an iterative loop**

```ruby
def call(request, cursor)
  seed_triple = Origin.of(request.url)
  seed_method = request.method # REDIR-3/REDIR-4: the ORIGINAL method, not the current hop's
  visited = ::Set[Dexpace::URL.external_form(request.url)]
  redirect_count = 0
  current_request = request
  current_url = request.url

  loop do
    cross_origin = Origin.cross?(seed_triple, current_url)
    forked = cursor.fork(state: { cross_origin: cross_origin }) # REDIR-11, REDIR-24; every drive
    response = forked.call(current_request)

    unless RECOGNIZED_CODES.include?(response.status.code)
      return response # REDIR-1, REDIR-21: no snapshot, response left open (REDIR-22c)
    end

    snapshot = ConditionSnapshot.build(response: response, redirect_count: redirect_count,
                                        visited_uris: visited)
    target = resolve_target(current_request, response) # REDIR-12, REDIR-18, REDIR-19; never raises
    return response if target.nil?

    decision = @predicate ? @predicate.call(snapshot) : default_follow?(seed_method, response,
                                                                         target, visited)
    return response unless decision
    return response if redirect_count >= @max_hops # REDIR-17's ceiling, OVER the answer (R9)

    begin
      next_request = build_follow_up(current_request, current_url, target, response, seed_triple)
    rescue StandardError
      Dexpace.close_quietly(response.body) if response.body # REDIR-22b: close before propagating
      raise
    end

    # REDIR-22a, and it is an ORDERING clause: "BEFORE issuing a follow-up request, the prior
    # redirect response's body MUST be closed." The close therefore happens here -- after the
    # follow-up is built (so a raise above still finds `response` open for its own rescue) and
    # BEFORE the next iteration's fork goes out. Deferring it to the top of the next iteration
    # passes every close-flag assertion and still holds hop N's connection for the whole of hop
    # N+1, which deadlocks a one-connection pool; 4c's ForkingProbe (the PIPE-40 fixture this
    # step extends) and design 6.2 both close first.
    Dexpace.close_quietly(response.body) if response.body

    emit_hop(from: current_url, to: target, status: response.status,
             redirect_count: redirect_count) # Task 13 defines the emitter
    current_request = next_request
    current_url = target
    visited << Dexpace::URL.external_form(target)
    redirect_count += 1
  end
end
```

- [ ] **Step 3: Update `build_follow_up` to consult `Resilience::Resend` and rebuild 303s**

```ruby
def build_follow_up(request, current_url, target, response, seed_triple)
  if downgrade?(current_url, target)
    unless @allow_scheme_downgrade
      raise SchemeDowngradeError.new(Dexpace::URL.external_form(current_url),
                                      Dexpace::URL.external_form(target))
    end

    emit_scheme_downgrade_permitted(current_url, target) # REDIR-15's opt-in MUST stay observable
  end

  headers = strip_headers(request.headers, cross_origin: Origin.cross?(seed_triple, target))
  builder = request.new_builder

  if response.status.code == 303
    # REDIR-5: re-issued as a GET, body dropped, every Content-* header removed. `b.method = ...`
    # -- phase 1 files a WRITER; `builder.method("GET")` would reach Object#method and raise.
    builder.method = Dexpace::Method::GET
    builder.body = nil
    headers = strip_content_headers(headers)
  else
    unless Dexpace::Resilience::Resend.replayable_body?(request) # REDIR-6, NOT 6a's eligible?
      raise Dexpace::Resilience::NotReplayableError, "redirect re-issue"
    end
    # method AND body preserved, per REDIR-3/REDIR-4: nothing is written to the builder.
  end

  builder.url = target
  builder.headers = headers
  builder.build
end

# REDIR-5 says "every Content-* request header (case-insensitively)" and its three examples are
# examples -- `e.g.` in both appendix C and chapter 10. A fixed list leaves Content-MD5,
# Content-Language, Content-Range and Content-Disposition on a request that no longer has a body.
# Headers is immutable and has no #remove; mutation lives on Headers::Builder, and #names returns
# the recorded original casing, so the prefix test folds (the repo-wide no-argument downcase).
def strip_content_headers(headers)
  headers.names
         .select { |name| name.downcase.start_with?("content-") }
         .each_with_object(headers.new_builder) { |name, b| b.remove(name) }
         .build
end
```

`seed_triple` is threaded as a parameter from `#call`'s own local rather than memoised on the step:
`Step` instances are shared across concurrent calls, so any per-call value cached in an instance
variable is a cross-call leak. `#call` computes it once at the top and passes it down.

- [ ] **Step 4: Run the full suite to confirm every test from Tasks 8–12 passes**

---

## Task 13: `REDIR-28` emission wiring

**Requirement IDs:** `REDIR-28`.
**Design:** "R8 — REDIR-28's emission site."

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/redirect/step.rb`
- Test: append to `step_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
class DexpaceRedirectStepEmissionTest < DexpaceTestCase
  # 5b's ONLY public Logger constructor is .build; P5-17 fixes the public methods at .build,
  # #event, #enabled?, #context and #sink -- there is no #info/#warn and no `level:` keyword.
  # Enablement is the SINK's, through its four predicates, which is what RecordingSink models.
  def logging_step(sink, **kwargs)
    Dexpace::Redirect::Step.new(logger: Dexpace::Instrumentation::Logger.build(sink: sink), **kwargs)
  end

  def event_names(sink)
    sink.entries.map { |e| e.payload[Dexpace::Instrumentation::Keys::EVENT] }
  end

  def payload_for(sink, name)
    sink.entries.map(&:payload)
        .find { |p| p[Dexpace::Instrumentation::Keys::EVENT] == name }
  end

  test "REDIR-28: a followed hop emits HOP_FOLLOWED with both URLs passed through the redactor" do
    sink = Dexpace::RecordingSink.new
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://user:pass@h/y"),
      response_with(status: 200),
    ])
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(logging_step(sink), stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build
    pipeline.call(seeded_get_request("https://seed.example/x"))

    hop = payload_for(sink, Dexpace::Redirect::Events::HOP_FOLLOWED)
    refute_nil(hop)
    refute_match(/user:pass/, hop[Dexpace::Redirect::Keys::TO_URL])
    assert_equal(302, hop[Dexpace::Redirect::Keys::STATUS_CODE])
  end

  test "REDIR-28: loop detection emits its own named event" do
    sink = Dexpace::RecordingSink.new
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://seed.example/x"), # revisits the seed
    ])
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(logging_step(sink), stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build
    pipeline.call(seeded_get_request("https://seed.example/x"))

    assert_includes(event_names(sink), Dexpace::Redirect::Events::LOOP_DETECTED)
  end

  test "REDIR-28: the malformed-Location event logs the RAW string, never through the redactor" do
    sink = Dexpace::RecordingSink.new
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://user:pass@ht!tp://bad"),
    ])
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(logging_step(sink), stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build
    pipeline.call(seeded_get_request("https://seed.example/x"))

    malformed = payload_for(sink, Dexpace::Redirect::Events::LOCATION_MALFORMED)
    refute_nil(malformed)
    assert_equal("https://user:pass@ht!tp://bad",
                 malformed[Dexpace::Redirect::Keys::LOCATION_RAW])
  end

  test "REDIR-18: an unsupported scheme emits the same malformed event, raw" do
    sink = Dexpace::RecordingSink.new
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "ftp://h/z"),
    ])
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(logging_step(sink), stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build
    pipeline.call(seeded_get_request("https://seed.example/x"))

    assert_equal("ftp://h/z",
                 payload_for(sink, Dexpace::Redirect::Events::LOCATION_MALFORMED)[
                   Dexpace::Redirect::Keys::LOCATION_RAW])
  end

  test "REDIR-28: a redaction failure degrades to a placeholder rather than crashing logging" do
    sink = Dexpace::RecordingSink.new
    raising = Object.new.tap { |r| r.define_singleton_method(:url) { |_| raise "boom" } }
    step = logging_step(sink, redactor: raising)
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://h/y"),
      response_with(status: 200),
    ])
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build

    # REDIR-28's "redaction failures MUST NOT crash logging" binds on ANY configured redactor, and
    # `redactor:` is a constructor keyword, so a caller-supplied one is not total the way
    # Redactor::DEFAULT is. #redacted_url's own rescue is what makes this pass.
    assert_equal(200, pipeline.call(seeded_get_request("https://seed.example/x")).status.code)
    assert_equal(Dexpace::Instrumentation::Redactor::MALFORMED_URL,
                 payload_for(sink, Dexpace::Redirect::Events::HOP_FOLLOWED)[
                   Dexpace::Redirect::Keys::TO_URL])
  end
end
```

- [ ] **Step 2: Implement the four emission methods, exactly as given in the design's `R8` section
  (`emit_hop`, `emit_loop_detected`, `emit_scheme_downgrade_permitted`, `emit_location_malformed`,
  plus the shared `redacted_url` helper), and wire each call site**

Each is one chain against 5b's real surface — `@logger.event(Severity::…)` makes the enabled
decision once and returns `Event::INERT` when the sink is not listening, so there is no `#info?`
predicate to call and no `Event` to construct:

- **Loop detected** — in `default_follow?`'s `REDIR-16` branch: `emit_loop_detected(target)` before
  returning `false`. There is exactly one revisit check, in `default_follow?`; the loop has no
  second one.
- **Scheme downgrade permitted** — in `build_follow_up`'s `@allow_scheme_downgrade` branch (Task 11,
  preserved through Task 12's rewrite): `emit_scheme_downgrade_permitted(current_url, target)`. It
  is `Events::SCHEME_DOWNGRADE_PERMITTED`, **not** `…_REJECTED`: the rejection path raises
  `SchemeDowngradeError` and is observable as the error, and logging "rejected" for a downgrade that
  went through would say the opposite of what happened.
- **Malformed Location** — the single `rescue ::URI::InvalidURIError` inside `resolve_target`
  (Task 9), which covers `REDIR-18`'s malformed reference and its unsupported/unknown scheme alike
  and is reached on both decision routes: `emit_location_malformed(location, error)`. There is no
  second rescue site, because `resolve_target` runs before the predicate is consulted.
- **Hop followed** — once per successful loop iteration, after `build_follow_up` returns without
  raising and after the prior-response close: `emit_hop(from: current_url, to: target, status:
  response.status, redirect_count: redirect_count)`.

`redacted_url` wraps `@redactor.url` in a local `rescue StandardError` returning
`Redactor::MALFORMED_URL`, **in addition to** relying on `Redactor::DEFAULT`'s own totality, because
`@redactor` is a constructor keyword and a caller-supplied one is not guaranteed total —
`REDIR-28`'s "redaction failures MUST NOT crash logging" binds on *any* configured redactor, not
only the default.

- [ ] **Step 3: Run the full suite to confirm every test from Tasks 8–13 passes**

---

## Task 13a — phase-level: `Pipeline.standard` and `AsyncPipeline.standard` over `Builder#install_preset`, the constructors phase 4c postponed

**Requirement IDs:** `PIPE-39` (its second constructor, closing phase 4c's ⏳ row), `PIPE-24` (consumed,
never re-implemented), `PIPE-32` (the substantive clause stops being vacuous), `REDIR-25` (same).
**Design:** the charter, `docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md`, "Phase-level
tasks owned by no sub-phase — `Pipeline.standard` and `AsyncPipeline.standard`" and `R14`; `docs/sdk-design-ruby/05-pipeline-architecture.md`
§5.3 (`PIPE-32`'s `redirect: :unsupported` argument); this sub-phase's design, "Convergence points" §2.
Inserted 2026-09-13 by the reconciliation of the outstanding deferrals: phase 4c postponed the two constructors on
2026-09-08 because the step families they install did not exist yet, the charter assigned this task to "whichever of
`6a`/`6b` lands second", and neither sub-phase plan carried it.

**Guard — read before starting.** This task executes in **whichever of `6a` and `6b` lands second**;
under the recommended order that is `6b`, which is why it lives here. If `6a` lands second, this task
moves **verbatim** into `6a`'s plan as its own lettered task and is skipped here — it is never run
twice and never run before both `Dexpace::Redirect::Step` (Task 8) and
`Dexpace::Resilience::RetryStep`/`AsyncRetryStep` (`6a` Tasks 9 and 10) exist. `6a`'s plan cites this
task by name in its Task 13 list of postponed work; that citation is the mirror the charter requires so the
task is neither built twice nor dropped.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/pipeline.rb` (`Pipeline.standard`)
- Modify: `gems/dexpace-core/lib/dexpace/async_pipeline.rb` (`AsyncPipeline.standard`)
- Modify: `gems/dexpace-core/sig/dexpace/pipeline.rbs`, `sig/dexpace/async_pipeline.rbs`
- Test: `gems/dexpace-core/test/dexpace/pipeline/standard_test.rb`

**Needs:** 4c's `Builder#install_preset(entries)` and `Pipeline::Entry`; 5b's
`Dexpace::Instrumentation::Step`; `6a`'s `RetryStep`/`AsyncRetryStep` (both declaring `#stage`); this
sub-phase's `Redirect::Step`; Task 7's `ScriptedTransport`.
**Produces:** `Pipeline.standard(transport, ...)`, `AsyncPipeline.standard(transport, ..., redirect:
:unsupported)`; **no** second installation path.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# PIPE-39 (second constructor), PIPE-24, PIPE-32, REDIR-25. Picks up the constructors phase 4c postponed.
require_relative "../../test_helper"

class DexpacePipelineStandardTest < DexpaceTestCase
  test "PIPE-39: the sync standard pipeline installs redirect, retry and instrumentation, nothing else" do
    pipeline = Dexpace::Pipeline.standard(Dexpace::Test::ScriptedTransport.new([response_with(status: 200)]))
    stages = pipeline.entries.map(&:stage)

    assert_includes(stages, Dexpace::Pipeline::Stages::REDIRECT)
    assert_includes(stages, Dexpace::Pipeline::Stages::RETRY)
    assert_includes(stages, Dexpace::Pipeline::Stages::LOGGING)
    assert_equal(3, stages.size)
  end

  test "PIPE-32/REDIR-25: the async standard pipeline installs NO step at Stages::REDIRECT" do
    pipeline = Dexpace::AsyncPipeline.standard(Dexpace::Test::FakeAsyncTransport.new,
                                               redirect: :unsupported)
    stages = pipeline.entries.map(&:stage)

    refute_includes(stages, Dexpace::Pipeline::Stages::REDIRECT)
    assert_includes(stages, Dexpace::Pipeline::Stages::RETRY)
    assert_includes(stages, Dexpace::Pipeline::Stages::LOGGING)
  end

  test "PIPE-32: the async constructor rejects any redirect: value other than :unsupported, and requires it" do
    transport = Dexpace::Test::FakeAsyncTransport.new
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::AsyncPipeline.standard(transport, redirect: :follow) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::AsyncPipeline.standard(transport, redirect: nil) }
    assert_raises(ArgumentError) { Dexpace::AsyncPipeline.standard(transport) } # keyword is required, not defaulted
  end

  test "PIPE-24: both constructors go through Builder#install_preset -- a caller-occupied pillar rejects the whole preset" do
    # 4c files Pipeline.builder(transport:) with the transport at BUILDER construction, so a
    # pre-seeded builder already carries it and `transport` is not re-supplied to .standard.
    transport = Dexpace::Test::ScriptedTransport.new([])
    builder = Dexpace::Pipeline.builder(transport: transport)
                               .append(Dexpace::Resilience::RetryStep.build,
                                       stage: Dexpace::Pipeline::Stages::RETRY)
    error = assert_raises(Dexpace::PipelineError) do
      Dexpace::Pipeline.standard(transport, builder: builder)
    end
    assert_match(/PIPE-24/, error.message)
    assert_equal(1, builder.entries.size) # nothing was overlaid or partially installed
  end

  test "the sync standard pipeline actually follows a redirect and retries a 503 in one call" do
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 503, headers: { "retry-after" => "0" }),
      response_with(status: 302, location: "https://a.example/y"),
      response_with(status: 200),
    ])
    pipeline = Dexpace::Pipeline.standard(transport, retry: Dexpace::Resilience::RetrySettings.build(initial_delay: 0.0))

    assert_equal(200, pipeline.call(seeded_get_request("https://a.example/x")).status.code)
    assert_equal(3, transport.received_requests.size)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline/standard_test.rb`
Expected: fails with `NoMethodError: undefined method 'standard' for Dexpace::Pipeline`.

- [ ] **Step 3: Write the two constructors — over `#install_preset`, and nothing else**

```ruby
# in lib/dexpace/pipeline.rb
#
# Against 4c's fences, not a recalled shape: Pipeline.builder(transport:) takes the transport as a
# REQUIRED keyword at builder construction, Builder#build and #build_async take NO arguments,
# Entry.new is private (Entry.build is the factory), and there is no AsyncPipeline.builder at all.
def self.standard(transport, redirect: Dexpace::Redirect::Step.new,
                  retry: Dexpace::Resilience::RetrySettings.build,
                  instrumentation: Dexpace::Instrumentation::Step.build,
                  builder: nil)
  entries = [
    Entry.build(stage: Stages::REDIRECT, step: redirect),
    Entry.build(stage: Stages::RETRY,    step: Dexpace::Resilience::RetryStep.build(settings: retry)),
    Entry.build(stage: Stages::LOGGING,  step: instrumentation),
  ]
  # PIPE-24: validate-then-commit, one installation path and no second one.
  (builder || Pipeline.builder(transport:)).install_preset(entries).build
end

# in lib/dexpace/async_pipeline.rb
# PIPE-32 / design §5.3: the asymmetry is a REQUIRED keyword at the call site, not an absence.
# There is no AsyncPipeline.builder (4c ships Pipeline.direct/AsyncPipeline.direct and one
# Builder); an async pipeline is Pipeline::Builder#build_async on a builder holding an async
# transport, which is the same builder class and the same install_preset.
def self.standard(transport, redirect:, retry: Dexpace::Resilience::RetrySettings.build,
                  instrumentation: Dexpace::Instrumentation::Step.build,
                  builder: nil)
  unless redirect == :unsupported
    raise Dexpace::InvalidArgumentError,
          "AsyncPipeline.standard follows no redirects at the pipeline layer (PIPE-32); pass redirect: :unsupported"
  end
  entries = [
    Entry.build(stage: Stages::RETRY,   step: Dexpace::Resilience::AsyncRetryStep.build(settings: retry)),
    Entry.build(stage: Stages::LOGGING, step: instrumentation),
  ]
  (builder || Dexpace::Pipeline::Builder.new(transport:)).install_preset(entries).build_async
end
```

No method other than `#install_preset` adds a step here; if a reviewer finds a second `@buckets`
write or a bare `#append` in either constructor, that is phase 4c's "writes no second installation
path" condition being violated. `Stages::REDIRECT` stays installable-but-unused on the async path (`PIPE-28`,
this sub-phase's `REDIR-25` row); this constructor simply never installs anything there.

- [ ] **Step 4: Write the `sig/` mirrors, run to confirm it passes**

```rbs
def self.standard: (untyped transport, ?redirect: untyped, ?retry: Dexpace::Resilience::RetrySettings,
                    ?instrumentation: untyped, ?builder: Dexpace::Pipeline::Builder?) -> Pipeline
# async_pipeline.rbs -- Builder is Dexpace::Pipeline::Builder on BOTH sides; 4c ships one builder
# class and discriminates the runtime by which of #build / #build_async the caller invoked.
def self.standard: (untyped transport, redirect: :unsupported, ?retry: Dexpace::Resilience::RetrySettings,
                    ?instrumentation: untyped, ?builder: Dexpace::Pipeline::Builder?) -> AsyncPipeline
```

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/pipeline/standard_test.rb`
Expected: PASS, 5 runs, 0 failures, 0 errors. Both names are `NFR-4` **widenings** and appear in the
surface snapshot Task 14 regenerates; add them to this sub-phase's Deviation Ledger row for new
public names.

- [ ] **Step 5: Update the YARD on `Dexpace::AsyncPipeline`** so the `PIPE-32` asymmetry sentence phase
  4c already wrote now points at the `redirect: :unsupported` keyword rather than at an absence.

---

## Task 14: Integration, 4c's negative assertion, and final wiring

**Requirement IDs:** none new; closes out `REDIR-1`–`REDIR-26`, `REDIR-28`'s test coverage.
**Design:** "Testing strategy," "Convergence points," "Prerequisites."

**Files:**
- Test: `gems/dexpace-core/test/dexpace/redirect/integration_test.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb` (final require ordering check), every `sig/dexpace/
  redirect/**.rbs` (completeness pass)

- [ ] **Step 1: Write the integration test extending 4c's R11 negative assertion 4 to the real step**

Already exercised in Task 10's own suite (the two "extends 4c's R11 negative assertion 4" tests,
which pair the real step at `REDIRECT` with 4c's `ForkingProbe` at `RETRY` and its `StateProbe` at
`AUTH`). This step adds the **inverse** check 4c's assertion 5 names — a write does not reach back —
run with the real step as the writer rather than a `ForkingProbe`:

```ruby
test "R11 assertion 5, against the real step: a second, independent redirect chain does not see " \
     "the first chain's marker" do
  step = Dexpace::Redirect::Step.new
  # 4c's read-side double, under 4c's own name and constructor: a top-level StateProbe in
  # test/support/probe_steps.rb, taking stage_to_read: and recording into #reads. It declares no
  # #stage, so the install names one.
  reader = StateProbe.new(stage_to_read: Dexpace::Pipeline::Stages::REDIRECT)
  pipeline = Dexpace::Pipeline.builder(transport: Dexpace::Test::ScriptedTransport.new([
                                 response_with(status: 302, location: "https://b.example/z"),
                                 response_with(status: 200),
                                 response_with(status: 200), # second, independent call
                               ]))
                               .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                               .append(reader, stage: Dexpace::Pipeline::Stages::AUTH)
                               .build
  pipeline.call(seeded_get_request("https://a.example/x")) # first call: seed A, hop to B
  pipeline.call(seeded_get_request("https://c.example/x")) # second call: same-origin throughout

  # Reads, in order: call 1 hop 0 (same-origin with its own seed), call 1 hop 1 (cross), then
  # call 2's single drive -- false, NOT the first call's leftover true.
  assert_equal([{ cross_origin: false }, { cross_origin: true }, { cross_origin: false }],
               reader.reads)
end
```

- [ ] **Step 2: Write `6b`'s half of convergence point 1, explicitly named as a half**

```ruby
# This is 6b's half of the phase-6 convergence point named in the charter and in this sub-phase's
# design ("Convergence points"). The full end-to-end test -- a real credential, a real AUTH step,
# an assertion that no Authorization reaches a second real transport call -- is owned by whichever
# of 6b/6c lands second (6c, under the recommended order) and is NOT duplicated here.
test "6b's half of convergence point 1: the marker this step writes is exactly what a real " \
     "credential-attaching step would need to suppress stamping correctly" do
  step = Dexpace::Redirect::Step.new
  probe = Dexpace::Test::CredentialProbe.new(token: "leaked-if-wrong")
  transport = Dexpace::Test::ScriptedTransport.new([
    response_with(status: 302, location: "https://b.example/z"),
    response_with(status: 200),
  ])
  pipeline = Dexpace::Pipeline.builder(transport: transport)
                               .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                               .append(probe, stage: Dexpace::Pipeline::Stages::AUTH)
                               .build
  pipeline.call(seeded_get_request("https://a.example/x"))

  assert(probe.decisions.last[:suppressed]) # the foreign-host hop MUST be suppressed
  refute(transport.received_requests.last.headers.include?("Authorization")) # never on the wire
end
```

- [ ] **Step 3: Run the whole `dexpace-core` suite; run `rubocop`, `steep check`, `rbs validate`**

```bash
(cd gems/dexpace-core && bundle exec rake test)
bundle exec rubocop
bundle exec steep check
bundle exec rbs validate
```

- [ ] **Step 4: Regenerate the runtime surface snapshot and diff `sig/**/*.rbs` against the previous
  release tag**

```bash
bundle exec rake surface:regenerate
```

Confirm the new public surface is exactly: `Dexpace::Redirect::Step`, `::ConditionSnapshot`,
`::Events`, `::Keys`, `::SchemeDowngradeError`; `Dexpace::Resilience::Resend`,
`::NotReplayableError` (or neither, if Task 2 found `6a` had already shipped them — in which case
this step confirms no *second* copy was added). `Origin` and `Location` must **not** appear in the
snapshot (`private_constant`).

- [ ] **Step 5: Restate, do not file, the findings this sub-phase's design names**

This plan does not edit `docs/knowledge/notes/` or
`.claude/skills/knowledge-lookup/SKILL.md` — the design document's *Findings, and who owns them now*
section already describes each in full, with the owner that carries it, ready for a human to file. This step is a checklist
reminder, not an action: confirm the design document still states all three before calling this
sub-phase done.

**The two records Task 13a owes, when it ran here (added 2026-09-13).** Unlike the three
findings above, these are edits this sub-phase *performs*, by hand, in the same change as the
checklist — the 2026-09-13 reconciliation of the outstanding deferrals found that no phase-6 plan carried them:

- This phase's status note in the roadmap says that the `standard` constructors phase 4c postponed have landed: that
  `Pipeline.standard` and `AsyncPipeline.standard` were written over `Builder#install_preset` by
  `6b`'s Task 13a and that `redirect: :unsupported` is a required keyword on the async one
  (`PIPE-32`). If Task 13a moved to `6a`, that plan writes the sentence and names `6a` instead.
- Phase 4c's `PIPE-39` ⏳ row: closes as ✅ in **this sub-phase's** checklist, citing Task 13a
  (phase 4c's own checklist row is left as written, per the two-rows-one-obligation precedent).

- [ ] **Step 6: Do not write `phase6b-redirect-checklist.md` in this task.** Per `CLAUDE.md`, the
  checklist is written at execution time, mapping each of the 28 IDs to the numbered task above
  that satisfies it (or, for `REDIR-27`, to its ⏳ row pointing at the v1 decline in `docs/first-release.md`), plus the `PIPE-39` ✅ row Task 13a
  adds when it runs here. This plan's own task headers already carry that mapping in their
  "Requirement IDs" lines; the checklist transcribes it into the one-row-per-ID form `CLAUDE.md`
  requires.
