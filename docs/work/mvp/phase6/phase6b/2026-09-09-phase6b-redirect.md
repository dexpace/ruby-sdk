# Phase 6b — Redirect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `dexpace-core`'s synchronous redirect pillar step — `Dexpace::Redirect::Step` at
`Stages::REDIRECT` — satisfying all 28 `REDIR-1`–`REDIR-28` requirements (`REDIR-27` deferred,
`DEF-7`, no code), plus the shared `Dexpace::Resilience::Resend` replayability predicate `REDIR-6`
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
2. **Whether `Dexpace::Resilience::Resend` and `NotReplayableError` are built by this plan or only
   consumed.** *Decision:* Task 2 builds both, under the `Dexpace::Resilience` namespace 3b's
   forward table already names, because `6a` and `6b` are independent and `6b` cannot block on `6a`
   landing first. If `6a`'s own plan finds the file already present when it runs, `6a`'s task for it
   becomes a no-op consumption citing this one; neither sub-phase builds a second predicate under a
   different name. This is stated in the design's *Independence* section and is not re-argued here.
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
2. `Dexpace::Resilience::Resend` and `NotReplayableError` (`REDIR-6`'s dependency) — standalone.
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
14. Integration: extending 4c's `R11` negative assertion 4 to the real step, `6b`'s half of
    convergence point 1, final wiring (`lib/dexpace.rb`, `sig/` completeness, surface snapshot,
    RBS baseline) — needs Task 13.

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

## Task 2: `Dexpace::Resilience::Resend` and `NotReplayableError`

**Requirement IDs:** `REDIR-6` (this sub-phase's call site); shared with `RETRY-5` (`6a`) and
`AUTH-31` (`6c`).
**Design:** "Independence," "Object model `6b` ships."

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/resilience/resend.rb`,
  `gems/dexpace-core/sig/dexpace/resilience/resend.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/resilience/resend_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Body#replayable?` (phase 3b), `Dexpace::Error` (phase 2).
- Produces: `Dexpace::Resilience::Resend.eligible?(request) -> bool`,
  `Dexpace::Resilience::NotReplayableError`.

- [ ] **Step 1: Check whether `6a` has already shipped this file**

```bash
test -f gems/dexpace-core/lib/dexpace/resilience/resend.rb && echo EXISTS || echo MISSING
```

If `EXISTS`, this task becomes a no-op: delete it from this plan's remaining work, cite the existing
file in this sub-phase's checklist, and skip to Task 3. The remaining steps assume `MISSING`.

- [ ] **Step 2: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

class DexpaceResilienceResendTest < DexpaceTestCase
  BodyDouble = Struct.new(:replayable) do
    def replayable? = replayable
  end
  RequestDouble = Struct.new(:body)

  test "REDIR-6: a request with no body is always eligible" do
    assert(Dexpace::Resilience::Resend.eligible?(RequestDouble.new(nil)))
  end

  test "REDIR-6: a request with a replayable body is eligible" do
    assert(Dexpace::Resilience::Resend.eligible?(RequestDouble.new(BodyDouble.new(true))))
  end

  test "REDIR-6: a request with a non-replayable body is not eligible" do
    refute(Dexpace::Resilience::Resend.eligible?(RequestDouble.new(BodyDouble.new(false))))
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
    # Shared by RETRY-5 (6a), REDIR-6 (6b) and AUTH-31 (6c) -- one predicate, never re-derived.
    module Resend
      module_function

      # @param request [Dexpace::Request]
      # @return [Boolean] true if request has no body, or its body is replayable.
      def eligible?(request)
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
      def self.eligible?: (Dexpace::Request request) -> bool
    end

    class NotReplayableError < StandardError
      include Dexpace::Error

      def initialize: (String context) -> void
    end
  end
end
```

- [ ] **Step 5: Add requires to `lib/dexpace.rb`; run test to confirm it passes**

Expected: PASS, 4 runs, 0 failures, 0 errors.

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

      # @param current_url [URI::Generic] always absolute (HTTP-47).
      # @param header_value [String] the raw Location header value.
      # @return [URI::Generic] frozen; userinfo NOT yet stripped (Step's job, REDIR-12).
      # @raise [::URI::InvalidURIError]
      def resolve(current_url, header_value)
        ::URI::RFC3986_PARSER.join(::Dexpace::URL.external_form(current_url), header_value).freeze
      end
    end
  end
end
```

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
  test "REDIR-28: four frozen event-name constants" do
    assert_predicate(Dexpace::Redirect::Events::HOP_FOLLOWED, :frozen?)
    assert_predicate(Dexpace::Redirect::Events::LOOP_DETECTED, :frozen?)
    assert_predicate(Dexpace::Redirect::Events::SCHEME_DOWNGRADE_REJECTED, :frozen?)
    assert_predicate(Dexpace::Redirect::Events::LOCATION_MALFORMED, :frozen?)
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
(`Events::HOP_FOLLOWED`/`::LOOP_DETECTED`/`::SCHEME_DOWNGRADE_REJECTED`/`::LOCATION_MALFORMED`;
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

Expected: PASS, 3 runs, 0 failures, 0 errors.

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
      attr_reader :received_requests

      def initialize(responses)
        @responses = responses.dup
        @received_requests = []
        @call_count = 0
      end

      def call(request, _options, _cancellation)
        @received_requests << request
        @call_count += 1
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
require_relative "../pipeline/stages"
require_relative "../method"
require_relative "../instrumentation/logger"
require_relative "../instrumentation/redactor"
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

  def run(step, responses, seed_url: "https://a.example/x")
    transport = Dexpace::Test::ScriptedTransport.new(responses)
    pipeline = Dexpace::Pipeline.builder.append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                .build(transport: transport)
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
end
```

(`response_with` is a small local helper building a `Dexpace::Response` with the given status and,
if given, a `Location` header pointed at the argument — added to this test file's top in this
step.)

- [ ] **Step 2: Implement `#call`'s decision skeleton**

```ruby
def call(request, cursor)
  seed_triple = Origin.of(request.url)
  drive(cursor, request, request.url, seed_triple, 0, ::Set[Dexpace::URL.external_form(request.url)])
end

private

def drive(cursor, request, current_url, seed_triple, redirect_count, visited)
  fork = cursor.fork
  response = fork.call(request)

  return response unless RECOGNIZED_CODES.include?(response.status.code) # REDIR-1, REDIR-21

  snapshot = ConditionSnapshot.build(response: response, redirect_count: redirect_count,
                                      visited_uris: visited)

  return response if redirect_count >= @max_hops # REDIR-17's hard ceiling; R9's named decision

  decision = @predicate ? @predicate.call(snapshot) : default_follow?(request, response, visited)
  return response unless decision

  # Tasks 10-13 fill in resolution, hygiene, the marker fork and the next drive.
  raise NotImplementedError, "filled in by Task 10"
end

def default_follow?(request, response, visited)
  location = response.headers["Location"]&.first
  return false if location.nil? || location.empty? # REDIR-19

  begin
    target = Location.resolve(current_url_of(request), location)
  rescue ::URI::InvalidURIError
    return false # REDIR-18's other half; Task 11 adds the emit + early return-current path
  end

  return false if visited.include?(Dexpace::URL.external_form(target)) # REDIR-16

  case response.status.code
  when 301, 302, 307, 308
    @allowed_methods.include?(request.method) # REDIR-3, REDIR-4
  when 303
    @follow303 # REDIR-5; method is irrelevant
  else
    false
  end
end
```

This skeleton intentionally raises past the point Task 10 fills in — the tests above only exercise
paths that return before reaching it (fast path, missing Location, loop, cap, predicate-refuses).
`current_url_of` is a one-line accessor added here (`request.url`) kept as a named seam because
Task 10's fork loop calls it with the *current hop's* request, not always the same object.

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
  def install_with_probe(step)
    probe = Dexpace::Test::CredentialProbe.new
    pipeline = Dexpace::Pipeline.builder
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .append(probe, stage: Dexpace::Pipeline::Stages::AUTH)
    [pipeline, probe]
  end

  test "REDIR-7: Authorization is stripped before EVERY re-issue, same-origin and cross-origin" do
    step = Dexpace::Redirect::Step.new
    pipeline_builder, probe = install_with_probe(step)
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://a.example/y"),        # same-origin hop
      response_with(status: 302, location: "https://b.example/z"),        # cross-origin hop
      response_with(status: 200),
    ])
    pipeline = pipeline_builder.build(transport: transport)
    request = seeded_get_request("https://a.example/x", authorization: "Bearer caller-token")

    pipeline.call(request)

    # Every request the transport received after the first carries NO caller-supplied
    # Authorization -- REDIR-7 is unconditional, not "only on the cross-origin hop."
    transport.received_requests[1..].each do |sent|
      refute_includes(sent.headers.names, "Authorization")
    end
  end

  test "REDIR-8: cross-origin is judged against the SEED, not the previous hop" do
    step = Dexpace::Redirect::Step.new
    pipeline_builder, probe = install_with_probe(step)
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://b.example/y"),  # seed A -> hop1 on B: cross
      response_with(status: 302, location: "https://b.example/z"),  # hop1(B) -> hop2 on B: SAME as
      response_with(status: 200),                                   #   hop1, but STILL judged
    ])                                                               #   against seed A -> cross
    pipeline = pipeline_builder.build(transport: transport)
    pipeline.call(seeded_get_request("https://a.example/x"))

    assert_equal([true, true], probe.decisions.map { |d| d[:suppressed] })
  end

  test "REDIR-8: a same-origin sub-redirect on a foreign host is NOT re-marked cross-origin " \
       "merely because the seed differs from that host -- it is judged against the seed" do
    step = Dexpace::Redirect::Step.new
    pipeline_builder, probe = install_with_probe(step)
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://b.example/y"),  # seed A -> B: cross-origin
      response_with(status: 302, location: "https://b.example/z"),  # B -> B: SAME-origin as the
      response_with(status: 200),                                   #   PREVIOUS hop, but the seed
    ])                                                               #   was A, so still cross
    pipeline = pipeline_builder.build(transport: transport)
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
    pipeline = Dexpace::Pipeline.builder.append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build(transport: transport)
    pipeline.call(seeded_get_request("https://a.example/x", cookie: "session=abc"))

    assert_includes(transport.received_requests[1].headers.names, "Cookie")   # same-origin: kept
    refute_includes(transport.received_requests[2].headers.names, "Cookie")   # cross-origin: gone
  end

  test "REDIR-11/REDIR-24: the marker is written false on every same-origin hop, true on every " \
       "cross-origin hop, and never once omitted" do
    step = Dexpace::Redirect::Step.new
    _, probe = install_with_probe(step)
    pipeline = Dexpace::Pipeline.builder.append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .append(probe, stage: Dexpace::Pipeline::Stages::AUTH)
                                 .build(transport: Dexpace::Test::ScriptedTransport.new([
                                   response_with(status: 302, location: "https://a.example/y"),
                                   response_with(status: 302, location: "https://b.example/z"),
                                   response_with(status: 200),
                                 ]))
    pipeline.call(seeded_get_request("https://a.example/x"))

    assert_equal(3, probe.decisions.size)          # once per hop, including the seed's own drive
    assert_equal([false, true, true], probe.decisions.map { |d| d[:suppressed] })
  end

  test "extends 4c's R11 negative assertion 4 to the REAL step: a probe downstream of the marker " \
       "cannot see the wrong slot, with production code as the writer" do
    step = Dexpace::Redirect::Step.new
    state_probe = Dexpace::Test::StateProbe.new(tag: :retry_slot,
                                                 stage: Dexpace::Pipeline::Stages::RETRY,
                                                 state: { irrelevant: true })
    reader = Dexpace::Test::StateProbe::Reader.new
    pipeline = Dexpace::Pipeline.builder
                                 .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .append(state_probe, stage: Dexpace::Pipeline::Stages::RETRY)
                                 .append(reader, stage: Dexpace::Pipeline::Stages::AUTH)
                                 .build(transport: Dexpace::Test::ScriptedTransport.new([
                                   response_with(status: 302, location: "https://b.example/z"),
                                   response_with(status: 200),
                                 ]))
    pipeline.call(seeded_get_request("https://a.example/x"))

    assert_equal({ cross_origin: true }, reader.seen_state(Dexpace::Pipeline::Stages::REDIRECT))
    assert_equal({ irrelevant: true }, reader.seen_state(Dexpace::Pipeline::Stages::RETRY))
  end
end
```

- [ ] **Step 2: Implement the marker fork and stripping, replacing Task 9's `raise
  NotImplementedError`**

```ruby
def drive(cursor, request, current_url, seed_triple, redirect_count, visited)
  cross_origin = Origin.cross?(seed_triple, current_url) # false on the seed's own first drive
  forked = cursor.fork(state: { cross_origin: cross_origin }) # REDIR-11, REDIR-24: written on
  response = forked.call(request)                             #   EVERY drive, the first included

  return response unless RECOGNIZED_CODES.include?(response.status.code)

  snapshot = ConditionSnapshot.build(response: response, redirect_count: redirect_count,
                                      visited_uris: visited)
  return response if redirect_count >= @max_hops

  decision = @predicate ? @predicate.call(snapshot) : default_follow?(request, response, visited)
  return response unless decision

  next_request, next_url, next_cross_origin_seed = build_follow_up(request, current_url, response)
  # ... Task 11 fills in build_follow_up's body (resolution, userinfo, downgrade); Task 12 fills in
  # the body-lifecycle close-before-next-drive and the recursion-as-loop rewrite (REDIR-22, 23).

  drive(cursor, next_request, next_url, seed_triple, redirect_count + 1,
        visited << Dexpace::URL.external_form(next_url))
ensure
  emit_hop(from: current_url, to: current_url, status: nil) if false # placeholder; Task 13 wires it
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
seed's own drive). `build_follow_up` is a named seam Task 11 fills in; this task's tests exercise
only the marker and the stripping, both of which are already correct with `build_follow_up` unbuilt,
because every scenario above that reaches a second or third hop supplies `location` values this
task's *own* `build_follow_up` stub (added in this step, returning a request with only the headers
stripped and the URL swapped, no downgrade/userinfo handling yet) makes just enough to route through.

**Note for the implementing worker:** this task's `drive` is written recursively for exposition; the
iterative rewrite (`REDIR-23`) happens in Task 12, which turns this into a `while` loop with no
change to the marker/stripping logic — do not let the iterative rewrite reach into this task's
already-passing tests, which assert behaviour, not control-flow shape.

- [ ] **Step 3: Run the full suite to confirm this task's tests pass**

Expected: PASS. `NoMethodError: undefined method 'build_follow_up'` is the acceptable interim state
between Step 2's two code blocks; add the stub named above before running.

---

## Task 11: Location resolution, userinfo strip, downgrade rejection

**Requirement IDs:** `REDIR-12`, `REDIR-13`, `REDIR-14`, `REDIR-15`.
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
    pipeline = Dexpace::Pipeline.builder.append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build(transport: transport)
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
    pipeline = Dexpace::Pipeline.builder.append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build(transport: transport)
    pipeline.call(seeded_get_request("https://seed.example/x"))

    sent_url = Dexpace::URL.external_form(transport.received_requests[1].url)
    assert_equal("https://h/a%2Fb?x=%26y", sent_url) # no "user:pass@"; %2F and %26 intact
  end

  test "REDIR-15: an HTTPS -> HTTP downgrade is rejected by default, closing the current response" do
    step = Dexpace::Redirect::Step.new
    current = response_with(status: 302, location: "http://h/y")
    transport = Dexpace::Test::ScriptedTransport.new([current])
    pipeline = Dexpace::Pipeline.builder.append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build(transport: transport)

    assert_raises(Dexpace::Redirect::SchemeDowngradeError) do
      pipeline.call(seeded_get_request("https://h/x"))
    end
    assert_predicate(current.body, :closed?) # REDIR-22b: closed before the error propagates
  end

  test "REDIR-15: the downgrade opt-in permits it and observably warns" do
    step = Dexpace::Redirect::Step.new(allow_scheme_downgrade: true)
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "http://h/y"),
      response_with(status: 200),
    ])
    pipeline = Dexpace::Pipeline.builder.append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build(transport: transport)

    pipeline.call(seeded_get_request("https://h/x")) # does not raise
    assert_equal("http://h/y", Dexpace::URL.external_form(transport.received_requests[1].url))
  end

  test "REDIR-18: a malformed Location is not thrown, and returns the current response unfollowed" do
    step = Dexpace::Redirect::Step.new
    transport = Dexpace::Test::ScriptedTransport.new([response_with(status: 302, location: "ht!tp://bad")])
    pipeline = Dexpace::Pipeline.builder.append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build(transport: transport)

    response = pipeline.call(seeded_get_request("https://h/x"))
    assert_equal(302, response.status.code)
    assert_equal(1, transport.received_requests.size)
  end
end
```

- [ ] **Step 2: Implement `build_follow_up`**

```ruby
def build_follow_up(request, current_url, response)
  location = response.headers["Location"]&.first
  target = Location.resolve(current_url, location) # REDIR-14; raises ::URI::InvalidURIError,
                                                     # already rescued by default_follow?/caller
  target.userinfo = "" # REDIR-12: "" clears both user and password; nil is a no-op (verified fact 1)

  if downgrade?(current_url, target) && !@allow_scheme_downgrade # REDIR-15
    Dexpace.close_quietly(response.body) if response.body
    raise SchemeDowngradeError.new(Dexpace::URL.external_form(current_url),
                                    Dexpace::URL.external_form(target))
  elsif downgrade?(current_url, target)
    emit_scheme_downgrade_rejected_but_permitted(current_url, target) # Task 13 wires the emitter
  end

  [target, response.status.code]
end

def downgrade?(from_url, to_url)
  from_url.scheme.downcase == "https" && to_url.scheme.downcase == "http"
end
```

`response.body.closed?` in this task's third test is asserted against phase 3b's own `Response#close`
contract; `Dexpace.close_quietly` is phase 2's discard-path close (`CFG-21`), used here rather than a
bare `response.body.close` because closing on the *raise* path must never itself raise and mask the
`SchemeDowngradeError` — exactly `REDIR-22b`'s "the current response MUST be closed before the error
propagates."

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
    pipeline = Dexpace::Pipeline.builder.append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build(transport: transport)
    original = seeded_post_request("https://h/x", content_type: "application/json",
                                    content_length: "13", body: json_body_double)
    pipeline.call(original)

    rebuilt = transport.received_requests[1]
    assert_equal("GET", rebuilt.method.token)
    assert_nil(rebuilt.body)
    refute_includes(rebuilt.headers.names, "Content-Type")
    refute_includes(rebuilt.headers.names, "Content-Length")
  end

  test "REDIR-6: a non-replayable body on a followed 307 fails with a clear error, closing current" do
    step = Dexpace::Redirect::Step.new
    current = response_with(status: 307, location: "https://h/y")
    transport = Dexpace::Test::ScriptedTransport.new([current])
    pipeline = Dexpace::Pipeline.builder.append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build(transport: transport)
    non_replayable = seeded_post_request("https://h/x", body: non_replayable_body_double)

    error = assert_raises(Dexpace::Resilience::NotReplayableError) { pipeline.call(non_replayable) }
    assert_match(/replayable/, error.message)
    assert_predicate(current.body, :closed?) # REDIR-22b
  end

  test "REDIR-22a/22c: each superseded intermediate is closed; the final, returned response stays open" do
    step = Dexpace::Redirect::Step.new
    hop1 = response_with(status: 302, location: "https://h/y")
    hop2 = response_with(status: 302, location: "https://h/z")
    final = response_with(status: 200)
    transport = Dexpace::Test::ScriptedTransport.new([hop1, hop2, final])
    pipeline = Dexpace::Pipeline.builder.append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build(transport: transport)

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
    pipeline = Dexpace::Pipeline.builder.append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build(transport: transport)

    assert_equal(200, pipeline.call(seeded_get_request("https://h/0")).status.code)
  end
end
```

- [ ] **Step 2: Rewrite `#call`/`drive` as an iterative loop**

```ruby
def call(request, cursor)
  seed_triple = Origin.of(request.url)
  visited = ::Set[Dexpace::URL.external_form(request.url)]
  redirect_count = 0
  current_request = request
  current_url = request.url
  prior_response = nil

  loop do
    cross_origin = Origin.cross?(seed_triple, current_url)
    forked = cursor.fork(state: { cross_origin: cross_origin }) # REDIR-11, REDIR-24; every drive
    response = forked.call(current_request)
    Dexpace.close_quietly(prior_response.body) if prior_response&.body # REDIR-22a
    prior_response = nil

    unless RECOGNIZED_CODES.include?(response.status.code)
      return response # REDIR-1, REDIR-21: no snapshot, response left open (REDIR-22c)
    end

    snapshot = ConditionSnapshot.build(response: response, redirect_count: redirect_count,
                                        visited_uris: visited)
    return response if redirect_count >= @max_hops # REDIR-17's hard ceiling, R9

    decision = @predicate ? @predicate.call(snapshot) : default_follow?(current_request, response,
                                                                         visited)
    return response unless decision

    begin
      current_request = build_follow_up(current_request, current_url, response) # REDIR-6, REDIR-12-15
    rescue StandardError
      Dexpace.close_quietly(response.body) if response.body # REDIR-22b: close before propagating
      raise
    end
    current_url = current_request.url
    visited << Dexpace::URL.external_form(current_url)
    redirect_count += 1
    prior_response = response # closed at the TOP of the next iteration, after that iteration's
                               # own fork succeeds -- never eagerly, so a raise inside build_follow_up
                               # above still finds `response` open for its own rescue to close.
  end
end
```

`REDIR-22a`'s "before issuing a follow-up request, the prior redirect response's body MUST be
closed" is implemented at the **top** of the next loop iteration rather than immediately after
building the follow-up, so the ordering is: close the *previous* hop's response only once the
*current* hop's fork is confirmed about to run — which is observably identical (nothing reads the
prior response in between) and keeps the "close on raise" path (inside `build_follow_up`'s `rescue`)
and the "close before next send" path as the same `close_quietly` call site conceptually, never two
independent ones that could drift.

- [ ] **Step 3: Update `build_follow_up` to consult `Resilience::Resend` and rebuild 303s**

```ruby
def build_follow_up(request, current_url, response)
  location = response.headers["Location"]&.first
  target = Location.resolve(current_url, location)
  target.userinfo = ""

  if downgrade?(current_url, target) && !@allow_scheme_downgrade
    raise SchemeDowngradeError.new(Dexpace::URL.external_form(current_url),
                                    Dexpace::URL.external_form(target))
  end

  builder =
    if response.status.code == 303
      strip_content_headers(request.new_builder).method("GET").tap { |b| b.body = nil } # REDIR-5
    else
      unless Dexpace::Resilience::Resend.eligible?(request) # REDIR-6
        raise Dexpace::Resilience::NotReplayableError, "redirect re-issue"
      end

      request.new_builder # method AND body preserved, per REDIR-3/REDIR-4
    end

  builder.url = target
  builder.headers = strip_headers(builder.headers, cross_origin: Origin.cross?(seed_triple_of(request),
                                                                                target))
  builder.build
end

def strip_content_headers(builder)
  %w[Content-Type Content-Length Content-Encoding].each { |name| builder.headers.remove(name) }
  builder
end
```

(`seed_triple_of` is a small memoised accessor added in this step so `build_follow_up` does not need
the seed threaded as an extra parameter; it is computed once from the *original* request `#call`
received and cached on the step's per-call state — which in this codebase means a local captured in
`#call`'s closure rather than an instance variable, since `Step` instances are shared across
concurrent calls and per-call captured locals are what phase 4's `ForkingProbe`/`StateProbe` pattern
already relies on for exactly this reason. The implementing worker restructures `build_follow_up`
as a closure or passes `seed_triple` explicitly rather than adding instance state — either is
acceptable; the checklist item this task closes is the behaviour, not this sketch's exact plumbing.)

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
  def logging_step(sink)
    logger = Dexpace::Instrumentation::Logger.new(sink: sink, level: Dexpace::Instrumentation::Severity::ALL)
    Dexpace::Redirect::Step.new(logger: logger)
  end

  test "REDIR-28: a followed hop emits HOP_FOLLOWED with both URLs passed through the redactor" do
    events = []
    step = logging_step(->(event) { events << event })
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://user:pass@h/y"),
      response_with(status: 200),
    ])
    pipeline = Dexpace::Pipeline.builder.append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build(transport: transport)
    pipeline.call(seeded_get_request("https://seed.example/x"))

    hop_event = events.find { |e| e.tag(Dexpace::Instrumentation::Keys::EVENT) == Dexpace::Redirect::Events::HOP_FOLLOWED }
    refute_nil(hop_event)
    refute_match(/user:pass/, hop_event.fields[Dexpace::Redirect::Keys::TO_URL])
  end

  test "REDIR-28: loop detection and scheme-downgrade-rejected each emit their own named event" do
    events = []
    step = logging_step(->(event) { events << event })
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://seed.example/x"), # revisits the seed
    ])
    pipeline = Dexpace::Pipeline.builder.append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build(transport: transport)
    pipeline.call(seeded_get_request("https://seed.example/x"))

    assert(events.any? { |e| e.tag(Dexpace::Instrumentation::Keys::EVENT) == Dexpace::Redirect::Events::LOOP_DETECTED })
  end

  test "REDIR-28: the malformed-Location event logs the RAW string, never through the redactor" do
    events = []
    step = logging_step(->(event) { events << event })
    transport = Dexpace::Test::ScriptedTransport.new([
      response_with(status: 302, location: "https://user:pass@ht!tp://bad"),
    ])
    pipeline = Dexpace::Pipeline.builder.append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                                 .build(transport: transport)
    pipeline.call(seeded_get_request("https://seed.example/x"))

    malformed = events.find { |e| e.tag(Dexpace::Instrumentation::Keys::EVENT) == Dexpace::Redirect::Events::LOCATION_MALFORMED }
    refute_nil(malformed)
    assert_equal("https://user:pass@ht!tp://bad", malformed.fields[Dexpace::Redirect::Keys::LOCATION_RAW])
  end

  test "REDIR-28: a redaction failure degrades to a placeholder rather than crashing logging" do
    events = []
    raising_redactor = Object.new.tap { |r| r.define_singleton_method(:url) { |_| raise "boom" } }
    step = Dexpace::Redirect::Step.new(logger: logging_step_logger_for(events), redactor: raising_redactor)
    # ... construct as needed; the assertion is that #call does not raise even though @redactor#url
    # would, because Task 13's emit_hop wraps the call the same way 5b's own Redactor::DEFAULT does
    # internally -- belt-and-suspenders for a caller-supplied redactor that is not itself total.
  end
end
```

- [ ] **Step 2: Implement the four emission methods, exactly as given in the design's `R8` section
  (`emit_hop`, `emit_loop_detected`, `emit_scheme_downgrade_rejected_but_permitted`,
  `emit_location_malformed`), and wire each call site**

- Loop detection (in `default_follow?`'s `REDIR-16` branch and in the loop's own revisit check):
  call `emit_loop_detected(target)` before returning `false`.
- Downgrade-rejected-but-permitted (in `build_follow_up`'s `elsif` branch, Task 11): call
  `emit_scheme_downgrade_rejected_but_permitted(current_url, target)`.
- Malformed Location (wherever `::URI::InvalidURIError` is rescued, in `default_follow?` and in the
  loop's own top-level rescue if `build_follow_up` is reached with a predicate-forced follow):
  call `emit_location_malformed(location, error)`.
- Hop followed (once per successful loop iteration, after `build_follow_up` returns without raising):
  call `emit_hop(from: current_url_before, to: current_request.url, status: response.status)`.

Wrap `@redactor.url` calls inside `emit_hop` in a local `rescue StandardError` **in addition to**
relying on `Redactor::DEFAULT`'s own totality, because `@redactor` is a constructor keyword and a
caller-supplied one is not guaranteed total — `REDIR-28`'s "redaction failures MUST NOT crash
logging" binds on *any* configured redactor, not only the default.

- [ ] **Step 3: Run the full suite to confirm every test from Tasks 8–13 passes**

---

## Task 14: Integration, 4c's negative assertion, and final wiring

**Requirement IDs:** none new; closes out `REDIR-1`–`REDIR-26`, `REDIR-28`'s test coverage.
**Design:** "Testing strategy," "Convergence points," "Prerequisites."

**Files:**
- Test: `gems/dexpace-core/test/dexpace/redirect/integration_test.rb`
- Modify: `gems/dexpace-core/lib/dexpace.rb` (final require ordering check), every `sig/dexpace/
  redirect/**.rbs` (completeness pass)

- [ ] **Step 1: Write the integration test extending 4c's R11 negative assertion 4 to the real step**

Already exercised in Task 10's own suite (the "extends 4c's R11 negative assertion 4" test). This
step adds the **inverse** check 4c's assertion 5 names — a write does not reach back — run against
the real step rather than `StateProbe`:

```ruby
test "R11 assertion 5, against the real step: a second, independent redirect chain does not see " \
     "the first chain's marker" do
  step = Dexpace::Redirect::Step.new
  reader = Dexpace::Test::StateProbe::Reader.new
  pipeline = Dexpace::Pipeline.builder
                               .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                               .append(reader, stage: Dexpace::Pipeline::Stages::AUTH)
                               .build(transport: Dexpace::Test::ScriptedTransport.new([
                                 response_with(status: 302, location: "https://b.example/z"),
                                 response_with(status: 200),
                                 response_with(status: 200), # second, independent call
                               ]))
  pipeline.call(seeded_get_request("https://a.example/x")) # first call: cross-origin hop
  first_seen = reader.seen_state(Dexpace::Pipeline::Stages::REDIRECT)

  pipeline.call(seeded_get_request("https://c.example/x")) # second call: same-origin throughout
  second_seen = reader.seen_state(Dexpace::Pipeline::Stages::REDIRECT)

  assert_equal({ cross_origin: true }, first_seen)
  assert_equal({ cross_origin: false }, second_seen) # NOT the first call's leftover true
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
  pipeline = Dexpace::Pipeline.builder
                               .append(step, stage: Dexpace::Pipeline::Stages::REDIRECT)
                               .append(probe, stage: Dexpace::Pipeline::Stages::AUTH)
                               .build(transport: Dexpace::Test::ScriptedTransport.new([
                                 response_with(status: 302, location: "https://b.example/z"),
                                 response_with(status: 200),
                               ]))
  pipeline.call(seeded_get_request("https://a.example/x"))

  refute(probe.decisions.last[:suppressed] == false) # the foreign-host hop MUST be suppressed
  final_request = transport_of(pipeline).received_requests.last
  refute_includes(final_request.headers.names, "Authorization") # never leaked to the wire
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

- [ ] **Step 5: Restate, do not file, the findings and register items this sub-phase's design names**

This plan does not edit `docs/open-items.md`, `docs/knowledge/notes/`, or
`.claude/skills/knowledge-lookup/SKILL.md` — the design document's *Findings for the registers*
section already describes each in full, ready for a human to file. This step is a checklist
reminder, not an action: confirm the design document still states all three before calling this
sub-phase done.

- [ ] **Step 6: Do not write `phase6b-redirect-checklist.md` in this task.** Per `CLAUDE.md`, the
  checklist is written at execution time, mapping each of the 28 IDs to the numbered task above
  that satisfies it (or, for `REDIR-27`, to its `DEF-7` ⏳ row). This plan's own task headers already
  carry that mapping in their "Requirement IDs" lines; the checklist transcribes it into the
  one-row-per-ID form `CLAUDE.md` requires.
