# Phase 5a — Configuration and the Clock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `dexpace-core`'s configuration chain, clock abstraction, non-blocking delay, HTTP
date formatting/parsing, non-cryptographic UUIDs, deep value equality, built-in retryability
status classifier, static build/runtime descriptor, proxy domain model and non-throwing resolver,
and downstream store and ceiling wirings — satisfying all 38 `CFG-1`–`CFG-38` requirements,
`XCUT-5`, and picking up deferrals `DEF-28`, `DEF-36`, and `DEF-34` (part).

**Architecture:** A four-tier layered configuration chain (`Dexpace::Configuration`, `Builder`,
`Keys`, `Sources`, and `ConfigParsers`) with an atomic, process-wide safe publication slot
(`Dexpace.configure`, `.configuration`, `.reset_config!`); an injectable time seam
(`Dexpace::Clock`, `Clock::SYSTEM`) exposing wall-clock, monotonic elapsed-time, and cancellable
queue-backed sleep; a scheduler-conditional async delay (`Dexpace::Async.delay`); a proxy model
and environment-driven resolver (`Proxy`, `Type`, `HostPattern`, and `ProxyResolution`) masking
credentials and honouring precedence; and five free-standing utility modules (`HTTPDate`, `UUID`,
`DeepValue`, `Retryability`, and `BuildInfo`). No transport, no socket, no stream: the entire test
surface consists of immutable value objects, process-wide synchronisation slots, bounded queue
waits, and string/date/number parsers.

**Tech Stack:** Ruby 3.2–4.0 (tested on 3.4.10), zero runtime dependencies, allowlisted stdlib
gems (`time`, `uri`), Minitest, RBS + Steep, RuboCop with phase 0's custom cops, SimpleCov, YARD.

**Spec:** `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-design.md`, under the
charter `docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md`.
`docs/product-spec/16-configuration.md` is the normative chapter;
`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` carries the canonical
text for all 38 `CFG` IDs and related cross-cutting requirements (`XCUT-5`, `DEF-28`, `DEF-34`,
`DEF-36`).

## Global Constraints

- **`dexpace-core` gains no dependency and the require allowlist does not grow (`R5`).** The
  gemspec contains zero `add_dependency` lines (`SEAM-1`, `NFR-1`). Core may `require` only
  entries from the phase 0 allowlist: `monitor`, `uri`, `stringio`, `strscan`, `time`, `date`,
  `securerandom`, `digest`, `openssl`, `forwardable`, `set`, `singleton`. Phase 5a requires
  exactly two allowlisted entries: `time` (for `Time#httpdate`) and `uri` (for proxy parsing). It
  does not require `date`, `logger`, `timeout`, or `securerandom` (`CFG-32` uses a per-thread PRNG,
  not `SecureRandom`).
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`).
- **Inside `module Dexpace`, anywhere, every core constant is `::`-qualified**: `::Thread`,
  `::Thread::Queue`, `::Thread::Mutex`, `::Regexp`, `::Time`, `::Process`, `::Fiber`, `::Random`,
  `::Data`, `::ENV`, `::URI`, `::StandardError`, `::ArgumentError`, `::IOError`. Kernel conversion
  methods are written `::Kernel.Integer(...)` for the same reason — never `::Integer(...)`, which is
  a constant reference and a **SyntaxError** when written as a call (verified). Once
  `dexpace-async-thread` is required a bare `Thread` inside `Dexpace::Async` is
  `Dexpace::Async::Thread`, which is what `Dexpace/QualifiedCoreConstant` exists for.
  `Sources::ENVIRONMENT` is named so `::ENV` is never shadowed in the first place (`P5-3`).
- **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are strictly forbidden**
  (`Dexpace/NoThreadInterrupt`). All bounded waits in 5a route through `Thread::Queue#pop(timeout:)`.
  Deadlines are explicit values passed as monotonic instants, never ambient asynchronous
  interrupts.
- **`Thread::Mutex` is per-fiber-owned and non-reentrant.** Mutexes are held only across the
  atomic assignment of the configuration reference (`Dexpace.configure`), never across caller
  blocks, source Procs, or suspension points.
- **`downcase` is called with no arguments repository-wide** (`Dexpace/NoLocaleCaseFold`). All
  case folds (`CFG-3`, `CFG-6`, `CFG-7`, `CFG-30`) use bare `downcase`.
- **`Regexp.new(source, timeout: 1.0)` per pattern, never `Regexp.timeout`.** All regular
  expressions (date grammar, duration grammar, glob pattern translation, non-proxy hosts separator)
  compile with an explicit per-pattern timeout.
- **`URI::RFC3986_PARSER` is pinned explicitly for every URI operation**
  (`Dexpace/NoUriDefaultParser`). Unescaping uses `URI.decode_uri_component`, never obsolete
  `URI::RFC3986_PARSER.unescape` or space-mangling `URI.decode_www_form_component`.
- **Domain model construction pattern:** `Data.define`, `private_class_method :new`, `.build`
  with `Model.required!` for fail-fast validation (`SEAM-29`, `CFG-37`), defensive collection
  copies with `Model.own` (`CFG-8`), and shallow `freeze`.
- **Formatting:** double quotes, 2-space indentation, 100 columns, `consistent_comma` trailing
  commas.
- **Every new `lib/` file opens with the `require_relative`s for the core files it names**, phase
  2's precedent — `model`, `error/invalid_argument_error`, `error/seam_error`,
  `error/cancelled_error`, `cancellation`, `async/completer` as each applies. `lib/dexpace.rb`'s
  order is then a convenience rather than a load-bearing dependency, which is what makes the
  require audit a text scan. `require_relative` for core's own files only; the two library
  `require`s in the sub-phase are `time` (`http_date.rb`) and `uri` (`proxy/resolution.rb`).

### Commands

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/<path>_test.rb   # one suite, red or green
(cd gems/dexpace-core && bundle exec rake test)                     # the gem's whole suite
bundle exec rake                                                    # all seventeen gates
bundle exec rubocop                                                 # linting and style gates
bundle exec steep check                                             # Steep typing gate
bundle exec rbs validate                                            # RBS validation gate
bundle exec rake surface:regenerate                                 # deliberate; Task 16 only
```

### What was verified during planning, and how

**One interpreter, and this plan says so before it says anything else.** The design's fourteen facts
were run on Ruby 3.4.10 (`ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]`) and on
nothing else, and that is still true here: re-checked while writing this plan, `mise ls` lists `bun`,
`go`, `node` and `opencode` and no Ruby, `~/.local/share/mise/installs` holds no ruby directory, and
`~/.rbenv`, `~/.rvm` and `/opt/rubies` do not exist. **The 3.2.11 and 4.0.6 columns have not been
run.** Task 1 instructs the executing worker to install both and run them; every claim below is a
3.4.10 claim until that task's output says otherwise, and the six floor-straddling facts carry the
consequence of each not holding in open question 1.

The following were re-run here on 3.4.10 while writing this plan, because each decides a fence:
1. `Time.httpdate` accepts RFC 850 and asctime formats, proving that normalise-then-delegate would
   violate `CFG-31`'s strictness clause. 5a uses an owned, anchored grammar (`R2`).
2. `Fiber[:k]` leaks generator instances across threads (`Thread.new { Fiber[:k].equal?(o) }` is
   `true`), whereas `Thread.current[:k]` is completely isolated across child fibers and new threads
   (`R3`). `UUID.generate` memoises in `Thread.current[:dexpace_prng]`.
3. `Random#bytes(16)` returns an unfrozen `ASCII-8BIT` string. UUID v4 bit-twiddling operates via
   `setbyte` without duplicate allocations.
4. `Date._iso8601` returns `{}` for ISO-8601 durations (`"PT5S"`), and `Integer("010")` evaluates
   to 8. `ConfigParsers` uses hand-written ISO duration parsing and explicit `Integer(raw, 10)`.
5. Float equality and hashing: `Float#hash` digests the bit pattern, so two NaNs hash equal only
   when their payloads agree, and `0.0.hash == (-0.0).hash` is **true** while `CFG-34` makes the
   two unequal. `DeepValue` folds every NaN to one seed, derives the negative-zero seed from the
   positive one, and discriminates signed zeros via `1.0 / x`.
   **A correction against the design, which this plan may not edit.** The design's verified fact 7
   names the different-payload NaN pair as `0.0/0.0` and `"nan".to_f`. Re-run here: **`"nan".to_f`
   is `0.0`, not a NaN** (`"nan".to_f.nan?` is `false`; `Float("nan")` raises), so that pair
   demonstrates a Float-versus-NaN difference rather than the payload difference the fact is about,
   and a test written from it would assert `DeepValue.equal?([0.0/0.0], [0.0])` — which must be
   **false**. Everything fact 7 *concludes* survives; only the witness is wrong. This plan uses
   `0.0/0.0` and `-(0.0/0.0)` — both `nan?`, sign bit differing, `#hash` differing, reproduced
   across three interpreter processes — and the witness `[0x7FF8_0000_0000_0001].pack("Q").unpack1("D")`
   is the alternative if a reader prefers an explicit bit pattern. Filed for the design's owner;
   the plan does not edit the design.
6. `Thread::Queue#pop(timeout:)` unmounts fibers under a registered `Fiber::Scheduler` without
   calling `kernel_sleep`. Without a scheduler, `Async.delay` raises `Dexpace::SeamError` (`R6`).
7. `URI::RFC3986_PARSER.parse("http://proxy.example").port` defaults to 80, whereas
   `URI::RFC3986_PARSER.split("http://proxy.example")[3]` is `nil`. `ProxyResolution` checks the
   split array to reject missing ports (`CFG-25`).
8. `URI::RFC3986_PARSER.unescape` emits an obsolescence warning on 3.4.10; `URI.decode_uri_component`
   is used instead.

## This plan's open questions, resolved

The design closes with five open questions for the plan. All five are resolved below with a
concrete decision and rationale:

1. **Re-running the six floor-straddling facts on 3.2.11 and 4.0.6.**
   - *Decision:* Task 1 ships `matrix_facts_test.rb`, a harness asserting facts 1 (`Time.httpdate`
     laxity), 3 (`Fiber[]` cross-thread sharing), 5 (`Random#bytes` unfrozen), 8
     (`Queue#pop(timeout:)` under a scheduler and its negative-timeout return), 9 (`RUBY_*`
     constants against `RbConfig` under `--disable-gems`) and 14 (`Data#with`'s `initialize`
     override, `ENV`'s frozen return, `Ractor.make_shareable`'s copy semantics), and **Task 1's
     first two steps install `ruby@3.2.11` and `ruby@4.0.6` and run that harness on each.**
   - *What has and has not been run:* **only 3.4.10 is installed on the authoring machine**
     (verified above), so **no fact in this plan has been observed on 3.2.11 or 4.0.6**. Task 1 is
     an instruction to the executing worker, not a record of a run. Its output is pasted into the
     plan under Task 1 before any later task starts, exactly as phases 3 and 4 did — and if either
     interpreter cannot be installed, Task 1 records that instead, and every YARD claim below
     narrows to "observed on 3.4.10" rather than being written as a range claim.
   - *If a fact does not hold on the floor:*
     - Fact 1: 5a uses an owned grammar (`R2`) for parsing regardless of stdlib parser behavior;
       `Time#httpdate` formatting is byte-exact.
     - Fact 3: `Thread.current[]` is fiber-local across all supported Ruby versions; non-inheritance
       holds everywhere.
     - Fact 5: If `Random#bytes` returns a frozen buffer on any interpreter, `.dup` is added before
       calling `setbyte`.
     - Fact 8: If `Queue#pop(timeout:)` scheduler hook differs on 3.2.11, `P5-9` is unaffected because
       5a raises `SeamError` without a scheduler; YARD non-pinning docs narrow to observed versions.
       Negative duration is explicitly guarded upfront by `Clock#sleep` and `Async.delay`.
     - Fact 9: Core engine constants (`RUBY_ENGINE`, `RUBY_ENGINE_VERSION`, `RUBY_PLATFORM`) are
       standard global constants without requires.
     - Fact 14: Phase 1's `Model#with` already re-routes through `.build` to handle 3.2.11's `Data#with`
       skipping `initialize`.

2. **Whether `strftime`'s `%a` and `%b` are locale-independent.**
   - *Decision:* keep the design's decision — format through `Time#httpdate`, requiring allowlisted
     `"time"` (`P5-12`). **The locale question is not settled and this plan does not settle it.**
     `locale -a` on the authoring machine lists only `C`, `C.utf8`, `en_US.utf8` and `POSIX`
     (re-checked here), so the design's `de_DE`/`fr_FR`/`tr_TR` runs all fell back to C and proved
     nothing, and nothing in this plan upgrades that to a fact. What is verified is narrower and
     sufficient to ship: `Time#httpdate`'s body is `getutc.strftime('%a, %d %b %Y %T GMT')`, and on
     3.4.10 under the installed locales `Time.utc(1994,11,6,8,49,37).httpdate` is byte-exact against
     `CFG-29`'s own example.
   - *What Task 5 must do about it:* install one non-English locale in the plan's environment
     (`localedef -i de_DE -f UTF-8 de_DE.UTF-8`, or the image's equivalent), re-run the `CFG-29`
     assertion under `LC_ALL=de_DE.UTF-8`, and paste the result into Task 5. **If `%a`/`%b` turn out
     to be locale-sensitive, `CFG-29` needs a hand-rolled formatter over frozen English weekday and
     month tables and `P5-12`'s formatting half changes** — the parsing half does not, because
     `R2`'s grammar already carries its own month table and never consults the locale. Until that
     run exists, the `HTTPDate.format` YARD block says the output is locale-independent **on the
     locales tested** and names which.

3. **`Completer#await`'s exact bounded-wait shape with `deadline:` and `clock:`.**
   - *Confirmed against phase 2's shipped body, not against a quotation of it.* `Completer#await`
     is `return self if settled?; subscription = arm(cancellation); begin; @gate.pop until settled?;
     ensure; subscription&.detach; end; self` — it returns **`self`**, it never raises, and
     `#arm` is the private helper that validates the token's class, short-circuits
     `Cancellation.none`, and registers `request_cancel(reason)` so a cancellation **settles the
     future** rather than merely waking the waiter. 5a preserves all four properties.
   - *Decision:* when `deadline` is given, the loop computes `remaining = deadline - clock.monotonic`
     on every iteration and passes it to `@gate.pop(timeout: remaining)`, so the **total** wait is
     bounded and a spurious wake cannot extend it. On `remaining <= 0` with the completer unsettled,
     `await` calls **`request_cancel(:deadline_expired)`** — phase 2's own settle-then-notify path —
     and returns `self`. It does **not** raise, because phase 2's `#await` never raises and
     `Future#wait` is documented "settles-or-returns; never raises the failure"; narrowing either
     would be an `NFR-4` break for a keyword that is supposed to widen.
   - *Where the raise comes from, which is the design's "cancels the future and then raises".*
     `request_cancel` settles the completer with `Settlement.cancellation(CancelledError.new(reason))`,
     so `Future#value` raises **that** object on its next line and `Future#wait` returns `self` with
     `#cancelled?` true. One expiry, one settlement, and the two existing contracts unchanged.
   - *Why the reason is the symbol `:deadline_expired` and not a sentence.* Phase 2 fixed
     `CancelledError.new(reason)` — **one positional argument, which is the reason**; there is no
     `reason:` keyword and there is no message argument. Its own comment says why the reason is an
     object: "`XCUT-2` requires a timeout and a cancellation to be told apart by ambient state,
     never by matching a string. Phase 6's `RETRY-23`/`RETRY-24` classification reads `#reason`, not
     `#message`." A `String` reason would make the design's "a caller that must distinguish them
     reads `#reason`" a string match, which is the thing that sentence exists to avoid. `#message`
     still reads `the operation was cancelled: deadline_expired`, which is the diagnostic half.

4. **Whether `Dexpace::ProxyResolution`'s seven property names want a `private_constant` module of
   their own or a frozen hash.**
   - *Decision, on the question as asked:* **no module of their own.** All seven live directly in
     `Dexpace::ProxyResolution`, which is already a `private_constant` on `Dexpace` and therefore
     already the enclosure a separate module would have provided; nesting a second module inside a
     private one buys a longer name and nothing else, and `module-organization/64e84d64`'s
     full-nesting reachability rule already reaches them there. The four the requirement pairs are
     a frozen hash and the three it does not are three frozen strings.
   - *Decision, on the shape:* the four layered names are one frozen hash keyed by layer, named
     `LAYERS` in the code below:
     `LAYERS = { https: { host: "https.proxyHost", port: "https.proxyPort" }, http: { host: "http.proxyHost", port: "http.proxyPort" } }.freeze`,
     so `CFG-24`'s "the port MUST be taken from the SAME layer as the chosen host" is a lookup on
     the layer the host was found under rather than two independent reads — the clause most likely
     to be implemented as parallel branches and most likely to pass a test that sets both layers.
     `CRED_USER` (`https.proxyUser`), `CRED_PASS` (`https.proxyPassword`) and `NON_PROXY_PROP`
     (`http.nonProxyHosts`) stay flat strings **because they are deliberately not layered**:
     `CFG-24` gives credentials no `http.*` fallback and `CFG-26` gives the non-proxy list only the
     one property name, and putting either in `LAYERS` would invite the fallback the requirement
     forbids.

5. **Where `Dexpace::IO`'s configured ceiling is read (`DEF-34`).**
   - *Decision:* a module function `Dexpace::IO.max_materialized_bytes(configuration = Dexpace.configuration)`
     reading `configuration.integer(Configuration::Keys::MAX_MATERIALIZED_BYTES, default: MAX_MATERIALIZED_BYTES)`,
     evaluated on every call so `Dexpace.configure` and `Dexpace.reset_config!` stay effective and no
     stale ceiling is memoised — which is the `DEF-36` consequence, avoided where it is avoidable.
   - *The design's conditional, discharged in Task 13 rather than assumed away:* "if there is
     exactly one call site, inline the read there and add no module function, which is one fewer
     `NFR-4`-locked name." Task 13's first step greps 3a's and 3b's call sites of
     `MAX_MATERIALIZED_BYTES`; the design's own §10.18 material names at least `#read_exactly`,
     `#slice` and `BODY-32`'s clamp, so more than one is expected and the module function is the
     working assumption — but the grep decides, and Task 13 records what it found.

## Task order and dependency chain

Sixteen tasks, in exact buildable dependency order:

1. **Matrix fact verification and the three test doubles** (`FakeClock`, `FakeSource`, `ProbeScheduler`) — installs `ruby@3.2.11` and `ruby@4.0.6`, runs the six floor-straddling facts on all three, and produces the fakes every later task uses.
2. `Dexpace::BuildInfo` (`CFG-36`) — static build/runtime descriptor; standalone.
3. `Dexpace::UUID` (`CFG-32`) — per-execution-context PRNG, v4 layout; standalone.
4. `Dexpace::Retryability` (`CFG-35`'s status half, `XCUT-5`) — the single shared status classifier; standalone.
5. `Dexpace::HTTPDate` (`CFG-29`, `CFG-30`, `CFG-31`) — owned RFC 1123 grammar and `Time#httpdate` formatting; standalone. Also settles open question 2's locale run.
6. `Dexpace::Clock` and `Clock::SYSTEM` (`CFG-15`, `CFG-16`, `CFG-17`) — the time seam; needed by Tasks 7 and 8.
7. `Dexpace::Async.delay` (`CFG-18`) — scheduler-conditional non-blocking delay; needs Task 1's `ProbeScheduler`.
8. `Async::Future` and `Async::Completer` bounded wait (`DEF-28`, `CFG-19`) — adds `deadline:` and `clock:` to `#value`, `#wait` and `#await`; needs Task 6's `Clock` and Task 1's `FakeClock`.
9. `Configuration::Keys` and `Configuration::Sources` (`CFG-11`, `CFG-14`) — the key names and the two seams. **Neither file is added to `lib/dexpace.rb`**; Task 11's `configuration.rb` owns their load order.
10. `Dexpace::ConfigParsers` (`CFG-5`, `CFG-6`, `CFG-7`) and `Dexpace::DeepValue` (`CFG-33`, `CFG-34`) — two `private_constant`s, no `sig/` mirror and no test mirror; asserted at their call sites in Task 11.
11. `Dexpace::Configuration` and `Configuration::Builder` (`CFG-1`–`CFG-10`, `CFG-12`, `CFG-33`, `CFG-34`, `CFG-37`, `CFG-38`) — the four-tier chain; needs Tasks 9 and 10.
12. `Dexpace.configure`, `.configuration`, `.reset_config!` (`CFG-13`) — the process-wide slot; needs Task 11.
13. Downstream wirings: `ContextStore.default` (`DEF-36`) and `IO.max_materialized_bytes` (`DEF-34`'s ceiling half); needs Tasks 11 and 12.
14. `Dexpace::Proxy`, `Proxy::Type` and `Proxy::HostPattern` (`CFG-22`, `CFG-23`) — **the model lands here, not in Task 15**: `type.rb` and `host_pattern.rb` reopen `class Proxy`, so `proxy.rb` must declare it first or the second file raises `superclass mismatch`.
15. `Dexpace::ProxyResolution` and `Proxy.resolve` (`CFG-24`–`CFG-28`) — the non-throwing resolver; needs Tasks 11, 12 and 14.
16. Final wiring, the `CFG-21` citation test, the surface snapshot, the RBS baseline, the checklist and the two register edits.

---
## Task 1: Matrix Fact Verification and Test Support Doubles

**Requirement IDs:** `CFG-11`, `CFG-15`, `CFG-17`, `CFG-18`, `CFG-30`, `CFG-31`, `CFG-32`, `CFG-34`, `CFG-36`.
**Design:** "The verified Ruby facts this phase is built on" (Facts 1, 3, 5, 8, 9, 14); "Testing strategy" (Three doubles, all fakes).

**Files:**
- Create: `gems/dexpace-core/test/support/fake_clock.rb`
- Create: `gems/dexpace-core/test/support/fake_source.rb`
- Create: `gems/dexpace-core/test/support/probe_scheduler.rb`
- Test: `gems/dexpace-core/test/dexpace/matrix_facts_test.rb`

**Interfaces:**
- Consumes: Ruby standard library, core `Dexpace` namespace.
- Produces: `Dexpace::FakeClock`, `Dexpace::FakeSource`, and `Dexpace::ProbeScheduler` test support doubles.

- [ ] **Step 1: Install the two interpreters this plan has not run on**

Only 3.4.10 is installed on the authoring machine, so the floor and the ceiling columns are
unobserved. Install both before writing any code that rests on a floor-straddling fact:

```bash
mise install ruby@3.2.11 ruby@4.0.6
mise exec ruby@3.2.11 -- ruby -v
mise exec ruby@4.0.6  -- ruby -v
```

If either refuses to build, **stop and record it here** rather than proceeding on the assumption
that 3.4.10 speaks for the range: every YARD claim in this sub-phase then narrows to the versions
actually observed, and open question 1's per-fact fallbacks apply.

- [ ] **Step 2: Write the matrix facts and test support doubles test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/fake_clock"
require_relative "../support/fake_source"
require_relative "../support/probe_scheduler"

class MatrixFactsTest < DexpaceTestCase
  test "Fact 1: Time.httpdate accepts RFC 850 and asctime while Date._httpdate rejects zones" do
    require "time"
    # Time.httpdate parses asctime without comma
    parsed_asctime = Time.httpdate("Sun Nov  6 08:49:37 1994")
    assert_equal(1994, parsed_asctime.year)

    # Rejects missing comma in RFC 1123 format
    assert_raises(ArgumentError) { Time.httpdate("Mon 01 Jan 2024 00:00:00 GMT") }
  end

  test "Fact 3: Fiber storage leaks across threads while Thread.current is isolated" do
    Fiber[:test_key] = "leaked"
    thread_fiber_val = Thread.new { Fiber[:test_key] }.value
    assert_equal("leaked", thread_fiber_val)

    Thread.current[:test_isolated] = "isolated"
    thread_current_val = Thread.new { Thread.current[:test_isolated] }.value
    assert_nil(thread_current_val)
  end

  test "Fact 5: Random#bytes returns unfrozen ASCII-8BIT buffer" do
    bytes = Random.new.bytes(16)
    refute(bytes.frozen?)
    assert_equal(Encoding::ASCII_8BIT, bytes.encoding)
  end

  test "Fact 8: Queue#pop negative timeout returns nil immediately and raises nothing" do
    q = Thread::Queue.new
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    val = q.pop(timeout: -1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    assert_nil(val)
    assert_operator(elapsed, :<, 0.05)
  end

  test "Fact 8: Queue#pop(timeout:) unmounts the fiber under a scheduler, never kernel_sleep" do
    scheduler = Dexpace::ProbeScheduler.new
    popped = :unset
    thread = Thread.new do
      Fiber.set_scheduler(scheduler)
      q = Thread::Queue.new
      Fiber.schedule { popped = q.pop(timeout: 0.02) }
    end
    thread.join # thread exit calls scheduler#close, which runs the event loop to completion

    assert_nil(popped)
    assert_equal(1, scheduler.block_count)
    assert_equal(0, scheduler.kernel_sleep_count)
  end

  test "Fact 9: the four RUBY_* constants need no require and RbConfig does" do
    assert_equal("constant", defined?(RUBY_ENGINE))
    assert_equal("constant", defined?(RUBY_ENGINE_VERSION))
    assert_equal("constant", defined?(RUBY_VERSION))
    assert_equal("constant", defined?(RUBY_PLATFORM))
    refute_empty(RUBY_PLATFORM.split("-", 2).last)

    # Under `ruby --disable-gems` the bare reference raises; BuildInfo therefore never names it.
    out = `ruby --disable-gems -e 'print defined?(RbConfig).inspect'`
    assert_equal("nil", out)
  end

  test "Fact 14: ENV returns a frozen String per call and make_shareable copies rather than freezes" do
    ENV["DEXPACE_FACT14"] = "v"
    begin
      first = ENV["DEXPACE_FACT14"]
      assert_predicate(first, :frozen?)
      refute_same(first, ENV["DEXPACE_FACT14"])

      ENV["DEXPACE_FACT14_EMPTY"] = ""
      assert_equal("", ENV["DEXPACE_FACT14_EMPTY"])
      assert(ENV.key?("DEXPACE_FACT14_EMPTY")) # CFG-2 reads the "" / nil distinction off this
    ensure
      ENV.delete("DEXPACE_FACT14")
      ENV.delete("DEXPACE_FACT14_EMPTY")
    end

    source = { "a" => ["b"] }
    copy = Ractor.make_shareable(source, copy: true)
    refute_predicate(source, :frozen?)
    assert_predicate(copy, :frozen?)
    refute_same(source, copy)
  end

  # Fact 14's `Data#with` half is deliberately NOT asserted here: it is the one fact whose result
  # differs by interpreter (3.2.11 skips an initialize override, 3.4.10 and 4.0.6 run it), so an
  # assertion either way fails a column. The port's mitigation is phase 1's Model#with, which routes
  # through .build on every version and is asserted by phase 1's own suite; 5a uses Model#with and
  # never Data#with, which is what Task 14 and Task 15 depend on.

  test "FakeClock conforms to _Clock interface" do
    clock = Dexpace::FakeClock.new
    assert_kind_of(Time, clock.now)
    assert_kind_of(Float, clock.monotonic)

    clock.advance(5.5)
    assert_in_delta(1005.5, clock.monotonic, 0.001)

    clock.sleep(1.0)
    assert_equal(1, clock.sleeps.size)
    assert_equal(1.0, clock.sleeps.first[:duration])
  end

  test "FakeSource provides thread-safe key-value lookup" do
    source = Dexpace::FakeSource.new("A" => "alpha")
    assert_equal("alpha", source.call("A"))
    assert_nil(source.call("B"))

    source["B"] = "beta"
    assert_equal("beta", source["B"])
  end

  # ProbeScheduler's hooks are only ever called BY the interpreter, from inside a non-blocking
  # fiber: #block and #kernel_sleep end in Fiber.yield, and calling either from the root fiber
  # raises FiberError. The scheduler is therefore exercised through Fiber.schedule (the fact-8 test
  # above) and never by invoking a hook directly.
  test "ProbeScheduler counts nothing until a scheduled fiber blocks" do
    scheduler = Dexpace::ProbeScheduler.new
    assert_equal(0, scheduler.block_count)
    assert_equal(0, scheduler.kernel_sleep_count)
    assert_equal(0, scheduler.unblock_count)
  end
end
```

- [ ] **Step 3: Run test to confirm it fails before fakes are created**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/matrix_facts_test.rb`
Expected: fails with `LoadError` loading `fake_clock`.

- [ ] **Step 4: Write test support doubles**

Write `gems/dexpace-core/test/support/fake_clock.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  class FakeClock
    attr_reader :sleeps

    def initialize(now: ::Time.utc(2026, 1, 1, 0, 0, 0), monotonic: 1000.0)
      @now = now
      @monotonic = monotonic.to_f
      @sleeps = []
      @mutex = ::Thread::Mutex.new
    end

    def now
      @mutex.synchronize { @now }
    end

    def monotonic
      @mutex.synchronize { @monotonic }
    end

    def sleep(duration, cancellation: nil)
      raise Dexpace::InvalidArgumentError, "duration must be non-negative" if duration.negative?

      @mutex.synchronize do
        @sleeps << { duration: duration, cancellation: cancellation }.freeze
        @monotonic += duration.to_f
        @now += duration.to_f
      end

      cancellation&.check!
      nil
    end

    def advance(seconds)
      @mutex.synchronize do
        @monotonic += seconds.to_f
        @now += seconds.to_f
      end
    end
  end
end
```

Write `gems/dexpace-core/test/support/fake_source.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  class FakeSource
    def initialize(entries = {})
      @entries = entries.dup
      @mutex = ::Thread::Mutex.new
    end

    def call(key)
      @mutex.synchronize { @entries[key.to_s] }
    end

    def [](key)
      call(key)
    end

    def []=(key, value)
      @mutex.synchronize do
        if value.nil?
          @entries.delete(key.to_s)
        else
          @entries[key.to_s] = value.to_s
        end
      end
    end
  end
end
```

Write `gems/dexpace-core/test/support/probe_scheduler.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # The minimal Fiber::Scheduler CFG-18's suite needs, and nothing else. It exists because
  # CFG-18's only interesting clause is conditional on a registered scheduler and there is no
  # scheduler gem in the MVP's dependency budget.
  #
  # A hook must NEVER sleep on the carrier thread: #block and #kernel_sleep are called from inside
  # a non-blocking fiber, and Kernel.sleep there re-enters #kernel_sleep, which re-enters
  # Kernel.sleep, until SystemStackError. Both hooks therefore park the current fiber with a
  # deadline and yield; the only real sleep in this file is in #run_loop, which runs on the carrier
  # thread with no fiber mounted. #close is what the interpreter calls when the scheduler's thread
  # ends, so a suite drives it by joining that thread.
  class ProbeScheduler
    attr_reader :block_count, :unblock_count, :kernel_sleep_count

    def initialize
      @block_count = 0
      @unblock_count = 0
      @kernel_sleep_count = 0
      @waiting = {}
      @ready = []
      @mutex = ::Thread::Mutex.new
    end

    def block(_blocker, timeout = nil)
      @block_count += 1
      park(timeout)
    end

    # Called from another thread when a queue is pushed to, so the bookkeeping takes the mutex.
    def unblock(_blocker, fiber)
      @mutex.synchronize do
        @unblock_count += 1
        @waiting.delete(fiber)
        @ready << fiber
      end
    end

    def kernel_sleep(duration = nil)
      @kernel_sleep_count += 1
      park(duration)
      true
    end

    def io_wait(_io, _events, _timeout)
      nil
    end

    def fiber(&block)
      f = ::Fiber.new(blocking: false, &block)
      f.resume
      f
    end

    def close
      run_loop
    end

    private

    # The mutex is held across the bookkeeping write and never across Fiber.yield: Thread::Mutex
    # ownership is per-fiber, so a lock held across a yield is a lock the resuming fiber cannot take.
    def park(timeout)
      @mutex.synchronize { @waiting[::Fiber.current] = timeout ? monotonic + timeout : nil }
      ::Fiber.yield
    end

    def monotonic
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end

    def run_loop
      until @waiting.empty? && @ready.empty?
        woken, due = @mutex.synchronize do
          taken = @ready
          @ready = []
          expired = @waiting.select { |_fiber, at| at && at <= monotonic }.keys
          expired.each { |fiber| @waiting.delete(fiber) }
          [taken, expired]
        end

        resumable = woken + due
        if resumable.empty?
          nearest = @mutex.synchronize { @waiting.values.compact.min }
          break if nearest.nil? # every remaining fiber waits forever; nothing left to drive

          ::Kernel.sleep([nearest - monotonic, 0.0].max)
          next
        end

        resumable.each { |fiber| fiber.resume if fiber.alive? }
      end
    end
  end
end
```

- [ ] **Step 5: Run matrix facts test to confirm it passes on 3.4.10**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/matrix_facts_test.rb`
Expected: PASS with 10 runs, 0 failures, 0 errors.

- [ ] **Step 6: Run the same suite on 3.2.11 and 4.0.6 and paste the output here**

```bash
mise exec ruby@3.2.11 -- bundle exec ruby -w gems/dexpace-core/test/dexpace/matrix_facts_test.rb
mise exec ruby@4.0.6  -- bundle exec ruby -w gems/dexpace-core/test/dexpace/matrix_facts_test.rb
```

Paste both runs into this task. A failure is a **finding, not a blocker**: apply the matching
fallback from open question 1, narrow the YARD claim that rested on the fact, and record the
narrowing in the checklist's notes column. Nothing later in this plan may cite a fact across the
range until this step's output says it holds across the range.

---

## Task 2: `Dexpace::BuildInfo`

**Requirement IDs:** `CFG-36` (static build/runtime descriptor).
**Design:** "R5 — `CFG-36`'s host-runtime identity, and the allowlist that does not grow"; "The object model 5a ships — `Dexpace::BuildInfo`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/build_info.rb`
- Create: `gems/dexpace-core/sig/dexpace/build_info.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/build_info_test.rb`

**Interfaces:**
- Consumes: `Dexpace::VERSION` (phase 0).
- Produces: `Dexpace::BuildInfo::SDK_VERSION`, `RUNTIME_VERSION`, `RUNTIME_VENDOR`, `OS_NAME`, `UNKNOWN`, `IDENTITY_TOKENS`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

class DexpaceBuildInfoTest < DexpaceTestCase
  test "CFG-36: exports non-blank frozen string constants" do
    assert_predicate(Dexpace::BuildInfo::SDK_VERSION, :frozen?)
    refute_empty(Dexpace::BuildInfo::SDK_VERSION)

    assert_predicate(Dexpace::BuildInfo::RUNTIME_VERSION, :frozen?)
    refute_empty(Dexpace::BuildInfo::RUNTIME_VERSION)

    assert_predicate(Dexpace::BuildInfo::RUNTIME_VENDOR, :frozen?)
    refute_empty(Dexpace::BuildInfo::RUNTIME_VENDOR)

    assert_predicate(Dexpace::BuildInfo::OS_NAME, :frozen?)
    refute_empty(Dexpace::BuildInfo::OS_NAME)

    assert_equal("unknown", Dexpace::BuildInfo::UNKNOWN)
  end

  test "CFG-36: provides ordered non-blank identity tokens list" do
    tokens = Dexpace::BuildInfo::IDENTITY_TOKENS
    assert_predicate(tokens, :frozen?)
    assert_equal(2, tokens.size)

    sdk_token, runtime_token = tokens
    assert_predicate(sdk_token, :frozen?)
    assert_predicate(runtime_token, :frozen?)

    assert_match(%r{\Adexpace-ruby/[^/ ]+\z}, sdk_token)
    assert_match(%r{\A[^/ ]+/[^/ ]+\z}, runtime_token)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/build_info_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::BuildInfo`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/build_info.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # Static build and host runtime descriptor resolved once at load time.
  # Satisfies CFG-36 and R5 without growing the require allowlist.
  module BuildInfo
    UNKNOWN = "unknown"

    sdk_ver = defined?(Dexpace::VERSION) ? Dexpace::VERSION.to_s.strip : ""
    SDK_VERSION = (sdk_ver.empty? ? UNKNOWN : sdk_ver).freeze

    run_ver = defined?(::RUBY_ENGINE_VERSION) ? ::RUBY_ENGINE_VERSION.to_s.strip : ""
    RUNTIME_VERSION = (run_ver.empty? ? UNKNOWN : run_ver).freeze

    run_ven = defined?(::RUBY_ENGINE) ? ::RUBY_ENGINE.to_s.strip : ""
    RUNTIME_VENDOR = (run_ven.empty? ? UNKNOWN : run_ven).freeze

    os = defined?(::RUBY_PLATFORM) ? ::RUBY_PLATFORM.to_s.split("-", 2).last.strip : ""
    OS_NAME = (os.empty? ? UNKNOWN : os).freeze

    IDENTITY_TOKENS = [
      "dexpace-ruby/#{SDK_VERSION}".freeze,
      "#{RUNTIME_VENDOR}-#{RUNTIME_VERSION}/#{OS_NAME}".freeze,
    ].freeze
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/build_info.rbs`**

```rbs
module Dexpace
  module BuildInfo
    UNKNOWN: String
    SDK_VERSION: String
    RUNTIME_VERSION: String
    RUNTIME_VENDOR: String
    OS_NAME: String
    IDENTITY_TOKENS: ::Array[String]
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/build_info"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/build_info_test.rb`
Expected: PASS with 2 runs, 0 failures, 0 errors.

---

## Task 3: `Dexpace::UUID`

**Requirement IDs:** `CFG-32` (non-cryptographic UUID v4 generator).
**Design:** "R3 — `CFG-32`'s per-thread PRNG on a Ruby with no `Random::DEFAULT`"; "The object model 5a ships — `Dexpace::UUID`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/uuid.rb`
- Create: `gems/dexpace-core/sig/dexpace/uuid.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/uuid_test.rb`

**Interfaces:**
- Consumes: Ruby core `Random`.
- Produces: `Dexpace::UUID.generate -> String`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require "set"

class DexpaceUUIDTest < DexpaceTestCase
  UUID_REGEX = /\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/

  test "CFG-32: generates valid v4 UUIDs matching RFC 4122 layout" do
    uuid = Dexpace::UUID.generate
    assert_predicate(uuid, :frozen?)
    assert_match(UUID_REGEX, uuid)
  end

  test "CFG-32: 10,000 draws produce no collisions" do
    seen = Set.new
    10_000.times do
      uuid = Dexpace::UUID.generate
      assert_match(UUID_REGEX, uuid)
      assert(seen.add?(uuid), "Collided on #{uuid}")
    end
  end

  # Asserted through the CARRIER, not through the output. A distinctness-of-output test alone
  # passes against a shared generator: one Random shared by 8 threads drawing 2000 each produced
  # 16 000 distinct values (design fact 4), so "no collisions" cannot show the absence of sharing.
  test "CFG-32: three execution contexts get three distinct generators, and none is shared" do
    Dexpace::UUID.generate
    main_prng = Thread.current[:dexpace_prng]
    refute_nil(main_prng)

    fiber_prng = nil
    Fiber.new do
      Dexpace::UUID.generate
      fiber_prng = Thread.current[:dexpace_prng]
    end.resume

    thread_prng = Thread.new do
      Dexpace::UUID.generate
      Thread.current[:dexpace_prng]
    end.value

    # Thread.current[] is fiber-local despite the name: a child fiber and a new thread each read
    # nil and seed their own. Fiber[] would hand THE SAME object to a new thread by identity, which
    # is precisely the shared mutable state CFG-32 forbids (R3, P5-13).
    refute_same(main_prng, fiber_prng)
    refute_same(main_prng, thread_prng)
    refute_same(fiber_prng, thread_prng)
    assert_same(main_prng, Thread.current[:dexpace_prng]) # the parent's slot was not overwritten
  end

  test "CFG-32 / P5-13: the generator is not reachable through Fiber storage" do
    Dexpace::UUID.generate
    assert_nil(Fiber[:dexpace_prng])
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/uuid_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::UUID`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/uuid.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # Type-4 (random) UUID generator for request, trace and correlation IDs (CFG-32).
  #
  # **The output is NON-cryptographic and callers must treat it as such** -- CFG-32 says so in as
  # many words, and a reader will otherwise assume the opposite of anything called a UUID.
  # XCUT-21's security-relevant values (AUTH-20's nonces among them) come from a different code
  # path entirely, and keeping the two apart is phase 5's boundary 8: this file writes no
  # `require "securerandom"` and names no SecureRandom constant, which is checkable by text.
  #
  # **The generator is memoised in `Thread.current[:dexpace_prng]`, the carrier CLAUDE.md's
  # constraint list names as the WRONG one -- and this is the deliberate exception (P5-13).** That
  # rule is about the diagnostic context, where inheritance by a child fiber, a new Thread and an
  # Enumerator's internal fiber is the property wanted; `docs/knowledge/notes/observability.md` is
  # unamended and Fiber[] remains the only correct carrier there. Here the same inheritance is the
  # defect: verified, `Fiber[:k] = o` then `Thread.new { Fiber[:k].equal?(o) }` is TRUE, so fiber
  # storage hands the same generator object to every thread the process later spawns -- exactly the
  # "shared mutable state" CFG-32 forbids. Thread.current[] is inherited by neither a child fiber
  # nor a new Thread, so no two execution contexts ever share one.
  module UUID
    module_function

    # Generates a version 4 UUID formatted as an 8-4-4-4-12 hex string.
    # @return [String] frozen UUID string, NOT suitable for secrets
    def generate
      prng = (::Thread.current[:dexpace_prng] ||= ::Random.new)
      raw = prng.bytes(16)
      b6 = (raw.getbyte(6) & 0x0f) | 0x40
      b8 = (raw.getbyte(8) & 0x3f) | 0x80
      raw.setbyte(6, b6)
      raw.setbyte(8, b8)
      hex = raw.unpack1("H*")
      "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}".freeze
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/uuid.rbs`**

```rbs
module Dexpace
  module UUID
    def self.generate: () -> String
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/uuid"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/uuid_test.rb`
Expected: PASS with 4 runs, 0 failures, 0 errors.

---
## Task 4: `Dexpace::Retryability`

**Requirement IDs:** `CFG-35`'s status half, `XCUT-5`.
**Design:** "R1 — `CFG-35`'s classifier: the status half lands here, the throwable half is deferred"; "The object model 5a ships — `Dexpace::Retryability`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/retryability.rb`
- Create: `gems/dexpace-core/sig/dexpace/retryability.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/retryability_test.rb`

**Interfaces:**
- Consumes: Ruby standard numeric types.
- Produces: `Dexpace::Retryability.retryable_status?(status) -> bool`, RBS interface `_RetryableStatus`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

class DexpaceRetryabilityTest < DexpaceTestCase
  StatusDouble = Struct.new(:code)

  test "CFG-35 / XCUT-5: classifies 408 and 429 as retryable" do
    assert(Dexpace::Retryability.retryable_status?(408))
    assert(Dexpace::Retryability.retryable_status?(429))
    assert(Dexpace::Retryability.retryable_status?(StatusDouble.new(408)))
    assert(Dexpace::Retryability.retryable_status?(StatusDouble.new(429)))
  end

  test "CFG-35 / XCUT-5: classifies 5xx as retryable except 501 and 505" do
    assert(Dexpace::Retryability.retryable_status?(500))
    assert(Dexpace::Retryability.retryable_status?(502))
    assert(Dexpace::Retryability.retryable_status?(503))
    assert(Dexpace::Retryability.retryable_status?(504))
    assert(Dexpace::Retryability.retryable_status?(599))

    refute(Dexpace::Retryability.retryable_status?(501))
    refute(Dexpace::Retryability.retryable_status?(505))
  end

  test "CFG-35 / XCUT-5: classifies 1xx, 2xx, 3xx and non-retryable 4xx as false" do
    [200, 201, 204, 301, 302, 304, 400, 401, 403, 404, 409, 422].each do |code|
      refute(Dexpace::Retryability.retryable_status?(code), "Expected #{code} not retryable")
    end
  end

  test "DEF-40: throwable classification method is intentionally not defined in 5a" do
    refute_respond_to(Dexpace::Retryability, :retryable_throwable?)
    refute_respond_to(Dexpace::Retryability, :retryable_error?)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/retryability_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::Retryability`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/retryability.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # Built-in shared HTTP status code retryability classifier.
  # Satisfies XCUT-5 and CFG-35's status half. Throwable classification is deferred (DEF-40).
  module Retryability
    module_function

    # Determines whether an HTTP status code is retryable according to the shared specification:
    # 408, 429, and all 5xx except 501 and 505 are retryable; all other statuses are not.
    # @param status [Integer, #code] numeric status code or object responding to #code
    # @return [Boolean] true if status is retryable
    def retryable_status?(status)
      code = status.respond_to?(:code) ? status.code : status.to_i
      return true if code == 408 || code == 429
      return false if code == 501 || code == 505

      code >= 500 && code <= 599
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/retryability.rbs`**

```rbs
module Dexpace
  interface _RetryableStatus
    def code: () -> Integer
  end

  module Retryability
    def self.retryable_status?: (Integer | _RetryableStatus status) -> bool
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/retryability"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/retryability_test.rb`
Expected: PASS with 4 runs, 0 failures, 0 errors.

---

## Task 5: `Dexpace::HTTPDate`

**Requirement IDs:** `CFG-29` (format), `CFG-30` (tolerant parsing), `CFG-31` (strict parsing).
**Design:** "R2 — `CFG-30`'s four zone tokens, against a banned `Time.parse` and an over-tolerant `Time.httpdate`"; "The object model 5a ships — `Dexpace::HTTPDate`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http_date.rb`
- Create: `gems/dexpace-core/sig/dexpace/http_date.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http_date_test.rb`

**Interfaces:**
- Consumes: `require "time"`, `Dexpace::InvalidArgumentError`.
- Produces: `Dexpace::HTTPDate.format(time) -> String`, `Dexpace::HTTPDate.parse(text) -> Time`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

class DexpaceHTTPDateTest < DexpaceTestCase
  test "CFG-29: formats Time instances in canonical RFC 1123 format" do
    t = Time.utc(1994, 11, 6, 8, 49, 37)
    assert_equal("Sun, 06 Nov 1994 08:49:37 GMT", Dexpace::HTTPDate.format(t))
  end

  test "CFG-30: parsing accepts all 4 zone tokens normalized to UTC" do
    expected = Time.utc(1994, 11, 6, 8, 49, 37)
    [
      "Sun, 06 Nov 1994 08:49:37 GMT",
      "Sun, 06 Nov 1994 08:49:37 UTC",
      "Sun, 06 Nov 1994 08:49:37 +0000",
      "Sun, 06 Nov 1994 08:49:37 +00:00",
    ].each do |date_str|
      assert_equal(expected, Dexpace::HTTPDate.parse(date_str))
    end
  end

  test "CFG-30: parsing is tolerant to case-insensitive months and wrong weekday" do
    expected = Time.utc(1994, 11, 6, 8, 49, 37)
    assert_equal(expected, Dexpace::HTTPDate.parse("Sun, 06 nov 1994 08:49:37 GMT"))
    assert_equal(expected, Dexpace::HTTPDate.parse("Mon, 06 Nov 1994 08:49:37 GMT")) # Mon is incorrect weekday
  end

  test "CFG-31: parsing strictly rejects empty, missing comma, RFC 850, and asctime" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HTTPDate.parse("") }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HTTPDate.parse("   ") }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HTTPDate.parse("Mon 01 Jan 2024 00:00:00 GMT") }
    # The two rows a reader would not think to add: Time.httpdate accepts both, so these are what
    # fail the day someone replaces the owned grammar with a delegation (R2, P5-12).
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HTTPDate.parse("Sunday, 06-Nov-94 08:49:37 GMT") } # RFC 850
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HTTPDate.parse("Sun Nov  6 08:49:37 1994") } # asctime
    # Leading space and embedded newline: \A..\z with single literal spaces, never \s+ and never \Z.
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HTTPDate.parse(" Sun, 06 Nov 1994 08:49:37 GMT") }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HTTPDate.parse("Sun,\n06 Nov 1994 08:49:37 GMT") }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HTTPDate.parse("Sun, 06 Nov 1994 08:49:37 GMT\n") }
    # Single-digit day, and a syntactically well-formed but impossible date.
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HTTPDate.parse("Sun, 6 Nov 1994 08:49:37 GMT") }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HTTPDate.parse("Sun, 32 Nov 1994 08:49:37 GMT") }
  end

  test "CFG-29: format requires its argument (SEAM-29's one message form)" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HTTPDate.format(nil) }
    assert_equal("time is required", error.message)
  end

  test "Property test: parse(format(t)) == t.floor" do
    100.times do |i|
      t = Time.at(1_700_000_000 + (i * 3600)).utc
      assert_equal(t.floor, Dexpace::HTTPDate.parse(Dexpace::HTTPDate.format(t)))
    end
  end
end
```

- [ ] **Step 1b: Settle open question 2's locale half, and paste the result here**

Install one non-English locale and re-run `CFG-29`'s assertion under it:

```bash
localedef -i de_DE -f UTF-8 de_DE.UTF-8      # or the image's equivalent
LC_ALL=de_DE.UTF-8 ruby -rtime -e 'print Time.utc(1994,11,6,8,49,37).httpdate'
```

Expected `Sun, 06 Nov 1994 08:49:37 GMT`. **If it differs, stop:** `CFG-29` then needs a hand-rolled
formatter over frozen English weekday and month tables, `P5-12`'s formatting half changes, and
`HTTPDate.format` stops delegating. `HTTPDate.parse` is unaffected either way — its month table is
its own and it consults no locale.

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http_date_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::HTTPDate`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/http_date.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "time"

require_relative "model"
require_relative "error/invalid_argument_error"

module Dexpace
  # RFC 1123 HTTP-date formatting and parsing.
  # Formatting delegates to Time#httpdate (CFG-29). Parsing implements an owned anchored
  # grammar honoring the 4 zone tokens (GMT, UTC, +0000, +00:00) and case-insensitive
  # months (CFG-30), while strictly failing on malformed or non-RFC 1123 dates (CFG-31).
  module HTTPDate
    MONTHS = {
      "jan" => 1, "feb" => 2, "mar" => 3, "apr" => 4,
      "may" => 5, "jun" => 6, "jul" => 7, "aug" => 8,
      "sep" => 9, "oct" => 10, "nov" => 11, "dec" => 12,
    }.freeze

    # Single literal spaces, not \s+: CFG-31's clause is about the well-formed "Xxx, " prefix, and
    # \s also matches a newline, so `"Sun,\n06 Nov 1994 08:49:37 GMT"` would parse under \s+ --
    # the same class of hole \Z would open at the other end. No normalisation runs before this
    # match, which is how CFG-31's blank-input failure is a property of the pattern rather than of
    # whatever a normaliser did to the input.
    GRAMMAR = ::Regexp.new(
      '\\A[A-Za-z]{3}, (\\d{2}) ([A-Za-z]{3}) (\\d{4}) (\\d{2}):(\\d{2}):(\\d{2}) (GMT|UTC|\\+0000|\\+00:00)\\z',
      ::Regexp::IGNORECASE,
      timeout: 1.0,
    ).freeze

    module_function

    # Formats a Time instant as an RFC 1123 date string (CFG-29).
    #
    # Delegates to Time#httpdate, whose body is `getutc.strftime('%a, %d %b %Y %T GMT')`. Whether
    # %a and %b are locale-independent is NOT verified: only C, C.utf8, en_US.utf8 and POSIX were
    # installed where this was written, so every non-English locale tested fell back to C. Task 5
    # installs one and re-asserts; if it turns out to be locale-sensitive this becomes a
    # hand-rolled formatter over frozen English tables and P5-12's formatting half changes.
    #
    # @param time [Time] time instant to format
    # @return [String] formatted date string
    def format(time)
      Model.required!("time", time).getutc.httpdate
    end

    # Parses an RFC 1123 date string with tolerant zone and month grammar (CFG-30, CFG-31).
    # @param text [String] date string to parse
    # @return [Time] parsed UTC Time instant
    # @raise [Dexpace::InvalidArgumentError] if text is empty, blank, or malformed
    def parse(text)
      if text.nil? || text.to_s.empty?
        raise Dexpace::InvalidArgumentError, "HTTP date cannot be empty"
      end

      m = GRAMMAR.match(text)
      unless m
        raise Dexpace::InvalidArgumentError, "Malformed or unsupported RFC 1123 date: #{text.inspect}"
      end

      month = MONTHS[m[2].downcase]
      unless month
        raise Dexpace::InvalidArgumentError, "Unknown month name in date: #{m[2].inspect}"
      end

      # The rescue wraps ONLY Time.utc. A method-level `rescue ::ArgumentError` would also catch the
      # two raises above, because Dexpace::InvalidArgumentError < ::ArgumentError -- re-raising them
      # with a second, wrong message. Verified: the outer rescue does fire on the inner raise.
      begin
        ::Time.utc(
          ::Kernel.Integer(m[3], 10), month, ::Kernel.Integer(m[1], 10),
          ::Kernel.Integer(m[4], 10), ::Kernel.Integer(m[5], 10), ::Kernel.Integer(m[6], 10)
        )
      rescue ::ArgumentError => e
        raise Dexpace::InvalidArgumentError,
              "Invalid date components in #{text.inspect}: #{e.message}"
      end
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/http_date.rbs`**

```rbs
module Dexpace
  module HTTPDate
    MONTHS: ::Hash[String, Integer]
    GRAMMAR: ::Regexp

    def self.format: (::Time time) -> String
    def self.parse: (String text) -> ::Time
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/http_date"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http_date_test.rb`
Expected: PASS with 6 runs, 0 failures, 0 errors.

---

## Task 6: `Dexpace::Clock` and `Clock::SYSTEM`

**Requirement IDs:** `CFG-15` (time seam), `CFG-16` (monotonic counter), `CFG-17` (cancellable sleep).
**Design:** "The object model 5a ships — `Dexpace::Clock` and `Clock::SYSTEM`"; "Cross-cutting constraints that bite 5a specifically".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/clock.rb`
- Create: `gems/dexpace-core/sig/dexpace/clock.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/clock_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Cancellation`, `Dexpace::InvalidArgumentError`, `Dexpace::CancelledError`.
- Produces: `Dexpace::Clock`, `Dexpace::Clock::SYSTEM`, `Dexpace::Clock.deadline_in`, RBS interface `_Clock`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

class DexpaceClockTest < DexpaceTestCase
  test "CFG-15 / CFG-16: Clock::SYSTEM exposes now and monotonic counter" do
    clock = Dexpace::Clock::SYSTEM
    assert_kind_of(Time, clock.now)
    assert_kind_of(Float, clock.monotonic)

    t1 = clock.monotonic
    t2 = clock.monotonic
    assert_operator(t2, :>=, t1)
  end

  test "CFG-17: sleep rejects negative duration with InvalidArgumentError" do
    clock = Dexpace::Clock::SYSTEM
    assert_raises(Dexpace::InvalidArgumentError) { clock.sleep(-0.5) }
  end

  test "CFG-17: sleep allows zero duration promptly" do
    clock = Dexpace::Clock::SYSTEM
    start = clock.monotonic
    clock.sleep(0)
    assert_operator(clock.monotonic - start, :<, 0.05)
  end

  test "CFG-17: sleep honors cancellation and re-asserts token status" do
    source = Dexpace::Cancellation::Source.new
    source.cancel("aborted")

    clock = Dexpace::Clock::SYSTEM
    err = assert_raises(Dexpace::CancelledError) do
      clock.sleep(5.0, cancellation: source.token)
    end
    assert_equal("aborted", err.reason)
    assert_predicate(source.token, :cancelled?)
  end

  test "Clock.deadline_in helper computes monotonic instant" do
    clock = Dexpace::Clock::SYSTEM
    dl = Dexpace::Clock.deadline_in(2.5, clock: clock)
    assert_in_delta(clock.monotonic + 2.5, dl, 0.1)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/clock_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::Clock`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/clock.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "cancellation"
require_relative "error/invalid_argument_error"
require_relative "error/cancelled_error"

module Dexpace
  # Time abstraction exposing wall-clock, monotonic elapsed-time, and cancellable sleep (CFG-15).
  #
  # EXACTLY three instance methods, because CFG-15 says "exposing three operations" and a fake owes
  # the seam what the seam declares. CFG-18's delay is a module function on Dexpace::Async and not a
  # fourth method here (P5-10); Clock.deadline_in is a CLASS method for the same reason.
  class Clock
    # Returns the current wall-clock instant.
    # @return [Time] current wall clock
    def now
      ::Time.now
    end

    # Returns the monotonic elapsed-time counter in seconds (CFG-16).
    # @return [Float] elapsed time counter
    def monotonic
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end

    # Bounded, cooperative, interruptible sleep (CFG-17).
    # Uses a per-call Thread::Queue to wait without holding mutexes or using unsafe Thread#raise.
    # @param duration [Numeric] duration in seconds
    # @param cancellation [Dexpace::Cancellation, nil] optional cancellation token
    # @return [nil]
    # @raise [Dexpace::InvalidArgumentError] if duration is negative
    # @raise [Dexpace::CancelledError] if cancelled before or during sleep
    def sleep(duration, cancellation: nil)
      # The guard is 5a's and not inherited: Thread::Queue#pop(timeout: -1) returns nil immediately
      # and raises nothing (verified fact 8), so a test asserting "returns promptly" would pass
      # against a missing guard.
      raise Dexpace::InvalidArgumentError, "sleep duration must be non-negative" if duration.negative?
      # CFG-17's "possibly yielding" is a MAY and is not taken: a Thread.pass would make a zero
      # sleep a scheduling event, which is more than the requirement asks for.
      return nil if duration.zero?

      cancellation&.check!

      queue = ::Thread::Queue.new
      subscription = cancellation&.on_cancel { queue.push(:cancel) }
      begin
        # nil means the duration elapsed and :cancel means the token fired. Sound ONLY because this
        # queue is per-call, private and never closed -- a closed queue pops nil too (fact 8).
        #
        # CFG-17's re-assertion clause is met structurally: the token's #cancelled? was set before
        # the push that woke this wait, so #check! raises at the caller's own next instruction and a
        # downstream handler inspecting the token observes the cancelled state. No Thread#raise,
        # no Thread#kill and no Timeout.timeout is involved (§8.3).
        cancellation&.check! if queue.pop(timeout: duration.to_f) == :cancel
      ensure
        # P2-14 made Subscription#detach public for exactly this: the hook lives on the caller's
        # token, which may outlive the wait by the life of a client.
        subscription&.detach
      end
      nil
    end

    # Convenience helper to compute a monotonic deadline instant.
    # @param duration [Numeric] seconds in the future
    # @param clock [_Clock] clock providing monotonic scale
    # @return [Float] monotonic deadline instant
    def self.deadline_in(duration, clock: SYSTEM)
      clock.monotonic + duration.to_f
    end

    # Shared default clock backed by the platform clock (CFG-15).
    SYSTEM = new.freeze
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/clock.rbs`**

```rbs
module Dexpace
  interface _Clock
    def now: () -> ::Time
    def monotonic: () -> Float
    def sleep: (Numeric duration, ?cancellation: Dexpace::Cancellation?) -> nil
  end

  class Clock
    def now: () -> ::Time
    def monotonic: () -> Float
    def sleep: (Numeric duration, ?cancellation: Dexpace::Cancellation?) -> nil

    def self.deadline_in: (Numeric duration, ?clock: _Clock) -> Float

    SYSTEM: Clock
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/clock"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/clock_test.rb`
Expected: PASS with 5 runs, 0 failures, 0 errors.

---
## Task 7: `Dexpace::Async.delay`

**Requirement IDs:** `CFG-18` (scheduled non-blocking delay).
**Design:** "R6 — `CFG-18`'s 'WITHOUT blocking a thread', and what happens with no scheduler"; "The object model 5a ships — `Dexpace::Async.delay`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/async/delay.rb`
- Create: `gems/dexpace-core/sig/dexpace/async/delay.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/async/delay_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Async::Completer`, `Dexpace::Async::Future`, `Dexpace::InvalidArgumentError`, `Dexpace::SeamError`.
- Produces: `Dexpace::Async.delay(duration) -> Dexpace::Async::Future`.

**The value the future settles with, which the design and phase 2 disagree about.** The design says
"a `Future` already settled with a **`nil`** value" and `CFG-18` says "completing (with an
empty/void value)". Phase 2 makes that unconstructible: `Async::Settlement#initialize` raises
`Dexpace::InvalidArgumentError` when `response.nil? == error.nil?`, and its own comment names why —
"`SEAM-16`'s *MUST NOT complete successfully with a null/absent value* made structural: there is no
settled-with-nothing state to construct". `Completer#fulfil(nil)` therefore **raises**, and a fence
that called it would fail on its first line. 5a settles the delay future with **`true`** — the
smallest non-`nil` value, carrying no new `NFR-4`-locked name — and `Future#value` on a delay future
returns `true`, not `nil`. Every assertion in this task is written against `true` for that reason.
**This is a conflict between the 5a design's wording and a phase-2 MUST, resolved here in favour of
`SEAM-16` because a MUST outranks a design sentence; whoever owns the 5a design should confirm the
wording rather than have it silently diverge.**

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/probe_scheduler"

class DexpaceAsyncDelayTest < DexpaceTestCase
  test "CFG-18: negative delay raises InvalidArgumentError immediately" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Async.delay(-1.0) }
  end

  test "CFG-18: zero delay completes future immediately without scheduler" do
    future = Dexpace::Async.delay(0)
    assert_predicate(future, :settled?)
    # true, not nil: SEAM-16 makes a nil-response Settlement unconstructible (see this task's note)
    assert_equal(true, future.value)
    assert_nil(Fiber.scheduler) # no scheduler was consulted
  end

  test "CFG-18: positive delay without registered scheduler raises SeamError" do
    # Ensure Fiber.scheduler is nil
    assert_nil(Fiber.scheduler)
    err = assert_raises(Dexpace::SeamError) do
      Dexpace::Async.delay(0.05)
    end
    assert_match(/Fiber\.set_scheduler/, err.message)
    assert_match(/CFG-18/, err.message)
    assert_match(/Dexpace::Clock#sleep/, err.message)
  end

  # The scheduler's event loop runs in ProbeScheduler#close, which the interpreter calls when the
  # scheduler's thread ends -- so the suite drives it by joining that thread, never by sleeping in
  # the main fiber. A `sleep` in the root fiber does not run the loop and does not reach the hooks.
  test "CFG-18: with ProbeScheduler the delay unmounts the fiber rather than blocking a thread" do
    scheduler = Dexpace::ProbeScheduler.new
    future = nil

    thread = Thread.new do
      Fiber.set_scheduler(scheduler)
      future = Dexpace::Async.delay(0.01)
    end
    thread.join

    assert_predicate(future, :settled?)
    assert_equal(true, future.value)
    # The only assertion that tests "WITHOUT blocking a thread" rather than that a delay delays.
    assert_equal(1, scheduler.block_count)
    assert_equal(0, scheduler.kernel_sleep_count)
  end

  test "CFG-18: cancelling the returned future cancels the scheduled wait" do
    scheduler = Dexpace::ProbeScheduler.new
    future = nil

    thread = Thread.new do
      Fiber.set_scheduler(scheduler)
      future = Dexpace::Async.delay(5.0)
      future.cancel(:test_cancel)
    end
    thread.join # returns promptly: the cancel hook pushed, so the parked fiber woke

    assert_predicate(future, :cancelled?)
    assert_equal(0, scheduler.kernel_sleep_count)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/async/delay_test.rb`
Expected: fails with `NoMethodError: undefined method 'delay' for module Dexpace::Async`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/async/delay.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "completer"
require_relative "../error/invalid_argument_error"
require_relative "../error/seam_error"

module Dexpace
  module Async
    module_function

    # The void value CFG-18's future settles with. Not nil: SEAM-16 makes Async::Settlement refuse
    # a nil response, so "completing with an empty/void value" is spelled `true` here.
    ELAPSED = true
    private_constant :ELAPSED

    # Scheduled non-blocking delay yielding a future completing after duration (CFG-18).
    # If no Fiber.scheduler is installed, raises Dexpace::SeamError rather than degrading
    # to a thread-blocking wait (P5-9). It lives on Async rather than being a fourth method on the
    # three-operation time seam (P5-10), and it takes no clock: keyword because nothing in its four
    # branches reads a clock -- the wait is Thread::Queue#pop's own timeout:, which takes a duration
    # and not an instant, and no fake clock can make a real queue wake early (R6).
    # @param duration [Numeric] duration in seconds
    # @return [Dexpace::Async::Future] future completing with the void value
    # @raise [Dexpace::InvalidArgumentError] if duration is negative
    # @raise [Dexpace::SeamError] if duration is positive but no scheduler is registered
    def delay(duration)
      dur = duration.to_f
      raise Dexpace::InvalidArgumentError, "delay duration must be non-negative" if dur.negative?

      completer = Completer.new
      if dur.zero?
        completer.fulfil(ELAPSED)
        return completer.future
      end

      if ::Fiber.scheduler.nil?
        raise Dexpace::SeamError,
              "Async.delay requires a registered Fiber.scheduler to run without blocking a thread " \
              "(CFG-18). Register one with Fiber.set_scheduler, or use Dexpace::Clock#sleep, which " \
              "blocks the calling thread by design."
      end

      queue = ::Thread::Queue.new

      # CFG-18's fourth clause: cancelling the future must cancel the scheduled task so the
      # scheduler thread is not held. Completer#on_cancel is the hook that fires on
      # Future#cancel -> Completer#request_cancel, and it returns the completer rather than a
      # subscription, so there is nothing to detach: the completer drops its hook list on settle.
      completer.on_cancel { queue.push(:cancel) }

      ::Fiber.schedule do
        # nil means the duration elapsed and :cancel means the future was cancelled. Sound only
        # because this queue is per-call, private, and never closed -- a closed queue pops nil too.
        completer.fulfil(ELAPSED) unless queue.pop(timeout: dur) == :cancel
      end

      completer.future
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/async/delay.rbs`**

```rbs
module Dexpace
  module Async
    def self.delay: (Numeric duration) -> Dexpace::Async::Future
  end
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/async/delay"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/async/delay_test.rb`
Expected: PASS with 5 runs, 0 failures, 0 errors.

---

## Task 8: Bounded Wait on Futures: `Future#value`, `#wait`, and `Completer#await`

**Requirement IDs:** `DEF-28` (`deadline:` and `clock:` keywords), `CFG-19` (unwrapping satisfied by construction).
**Design:** "The object model 5a ships — `Dexpace::Async::Future#value` and `#wait` (DEF-28)"; "Deferral-register sweep (`DEF-28`)".

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/async/future.rb`
- Modify: `gems/dexpace-core/lib/dexpace/async/completer.rb`
- Modify: `gems/dexpace-core/sig/dexpace/async/future.rbs`
- Modify: `gems/dexpace-core/sig/dexpace/async/completer.rbs`
- Test: `gems/dexpace-core/test/dexpace/async/future_deadline_test.rb`

**Interfaces:**
- Consumes: Task 6's `Dexpace::Clock::SYSTEM` and `_Clock`.
- Produces: `Future#value(cancellation: nil, deadline: nil, clock: Clock::SYSTEM)`,
  `Future#wait(cancellation: nil, deadline: nil, clock: Clock::SYSTEM)`,
  `Completer#await(cancellation = nil, deadline: nil, clock: Clock::SYSTEM)`.

**Read phase 2's shipped bodies before editing them; this task adds two keywords and changes nothing
else.** The three methods are, verbatim from phase 2: `Completer#await(cancellation = nil)` →
`return self if settled?; subscription = arm(cancellation); begin; @gate.pop until settled?; ensure;
subscription&.detach; end; self`; `Future#wait(cancellation: nil)` → `@completer.await(cancellation);
self`; `Future#value(cancellation: nil)` → `wait(cancellation: cancellation); settlement =
@completer.outcome; raise settlement.error if settlement.error; settlement.response`. There is no
`#failed?`, no `#reason` and no `#result` on `Completer` — the state is one `Settlement` behind
`#outcome`. `#arm` is private and is the only correct way to register the token: it type-checks the
argument, short-circuits `Cancellation.none`, and registers `request_cancel(reason)` so a
cancellation **settles the future**. Replacing it with a bare `@gate.push` would wake the waiter and
leave the future permanently unsettled, which is the failure phase 2's own `#request_cancel` comment
documents at length. All three keep returning what they returned; `#await` still returns `self` and
still never raises, because narrowing either would be the `NFR-4` break this widening exists to avoid.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/fake_clock"

class DexpaceFutureDeadlineTest < DexpaceTestCase
  # The expired branch is the only one a fake clock can drive: no fake makes a real Thread::Queue
  # wake early, which is the same limit CFG-15's suite records.
  test "DEF-28: an expired deadline cancels the future, and #value raises that cancellation" do
    clock = Dexpace::FakeClock.new(monotonic: 100.0)
    completer = Dexpace::Async::Completer.new
    future = completer.future

    err = assert_raises(Dexpace::CancelledError) do
      future.value(deadline: 90.0, clock: clock)
    end
    # A Symbol, not a sentence: XCUT-2 forbids telling a deadline from a cancel by string match.
    assert_equal(:deadline_expired, err.reason)
    assert_predicate(future, :cancelled?)
  end

  test "DEF-28: #wait still settles-or-returns, and never raises, on an expired deadline" do
    clock = Dexpace::FakeClock.new(monotonic: 100.0)
    completer = Dexpace::Async::Completer.new
    future = completer.future

    assert_same(future, future.wait(deadline: 90.0, clock: clock))
    assert_predicate(future, :cancelled?)
  end

  test "DEF-28: #await keeps returning self, which NFR-4 forbids narrowing" do
    clock = Dexpace::FakeClock.new(monotonic: 100.0)
    completer = Dexpace::Async::Completer.new

    assert_same(completer, completer.await(nil, deadline: 90.0, clock: clock))
  end

  test "DEF-28: wait returns self when completed before deadline" do
    clock = Dexpace::FakeClock.new(monotonic: 100.0)
    completer = Dexpace::Async::Completer.new
    future = completer.future

    completer.fulfil(:done)
    res = future.wait(deadline: 150.0, clock: clock)
    assert_same(future, res)
    assert_equal(:done, future.value)
    refute_predicate(future, :cancelled?)
  end

  test "CFG-19: failure surfaces original throwable without completion wrapper" do
    completer = Dexpace::Async::Completer.new
    original_error = RuntimeError.new("underlying root error")

    completer.fail(original_error)
    err = assert_raises(RuntimeError) { completer.future.value }
    assert_same(original_error, err)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/async/future_deadline_test.rb`
Expected: fails with `ArgumentError: unknown keyword: :deadline`.

- [ ] **Step 3: Modify `gems/dexpace-core/lib/dexpace/async/future.rb` and `completer.rb`**

In `gems/dexpace-core/lib/dexpace/async/future.rb`, replace only the bodies of `#wait` and `#value`
and leave `#initialize`, `#settled?`, `#cancelled?`, `#on_settle` and `#cancel` exactly as phase 2
wrote them:

```ruby
      # Settles-or-returns; never raises the failure, and an expired deadline is not an exception
      # to that: it settles the future as cancelled and this still returns self.
      # @param cancellation [Dexpace::Cancellation, nil] optional cancellation token
      # @param deadline [Float, nil] monotonic instant, on Clock#monotonic's scale (DEF-28)
      # @param clock [_Clock] the seam the deadline is measured against
      # @return [self]
      def wait(cancellation: nil, deadline: nil, clock: Dexpace::Clock::SYSTEM)
        @completer.await(cancellation, deadline: deadline, clock: clock)
        self
      end

      # Blocks, then delivers the response or raises the failure. On an expired deadline the
      # failure IS the cancellation #await settled with, so there is one raise here and no second
      # error class: the caller reads CancelledError#reason to tell a deadline from a cancel.
      # @return [Object] the settled response
      def value(cancellation: nil, deadline: nil, clock: Dexpace::Clock::SYSTEM)
        wait(cancellation: cancellation, deadline: deadline, clock: clock)
        settlement = @completer.outcome
        raise settlement.error if settlement.error

        settlement.response
      end
```

In `gems/dexpace-core/lib/dexpace/async/completer.rb`, replace only `#await`. `#arm`, `#settle`,
`#request_cancel`, `#fulfil`, `#fail`, `#on_cancel` and `#on_settle` are untouched:

```ruby
      # Waits until settled, observing cancellation and an optional monotonic deadline (DEF-28).
      #
      # `deadline:` is an instant on Clock#monotonic's scale and not a duration, so a wait that is
      # resumed spuriously cannot extend it: `remaining` is recomputed from the clock on every
      # iteration and the total wait is what is bounded. `Clock.deadline_in` is how a caller names
      # the scale; computing one off Time.now is the mistake CFG-16 forbids.
      #
      # On expiry this cancels the future through phase 2's own #request_cancel -- one settlement,
      # published before the hooks run -- and returns. It does not raise: #await never raised and
      # Future#wait is documented never to raise the failure, so raising here would narrow two
      # signatures NFR-4 locks. Future#value raises on its next line, because the settlement it
      # finds is a cancellation carrying :deadline_expired.
      #
      # @param cancellation [Dexpace::Cancellation, nil]
      # @param deadline [Float, nil] monotonic instant
      # @param clock [_Clock]
      # @return [self]
      def await(cancellation = nil, deadline: nil, clock: Dexpace::Clock::SYSTEM)
        return self if settled?

        subscription = arm(cancellation)
        begin
          if deadline.nil?
            @gate.pop until settled?
          else
            until settled?
              remaining = deadline.to_f - clock.monotonic
              if remaining <= 0
                request_cancel(:deadline_expired)
                break
              end

              @gate.pop(timeout: remaining)
            end
          end
        ensure
          subscription&.detach
        end
        self
      end
```

- [ ] **Step 4: Update `gems/dexpace-core/sig/dexpace/async/future.rbs` and `completer.rbs`**

In `sig/dexpace/async/future.rbs`:
```rbs
module Dexpace
  module Async
    class Future
      def value: (?cancellation: Dexpace::Cancellation?, ?deadline: Float?, ?clock: _Clock) -> untyped
      def wait: (?cancellation: Dexpace::Cancellation?, ?deadline: Float?, ?clock: _Clock) -> self
    end
  end
end
```

In `sig/dexpace/async/completer.rbs`:
```rbs
module Dexpace
  module Async
    class Completer
      # -> self, unchanged from phase 2. Narrowing it to `nil` would be the NFR-4 break this
      # widening exists to avoid.
      def await: (?Dexpace::Cancellation? cancellation, ?deadline: Float?, ?clock: _Clock) -> self
    end
  end
end
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/async/future_deadline_test.rb`
Expected: PASS with 5 runs, 0 failures, 0 errors.

---
## Task 9: `Dexpace::Configuration::Keys` and `Dexpace::Configuration::Sources`

**Requirement IDs:** `CFG-11` (substitutable seams), `CFG-14` (well-known key constants).
**Design:** "The object model 5a ships — `Dexpace::Configuration::Keys` and `Sources`"; "Deviation Ledger (P5-3)".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/configuration/keys.rb`
- Create: `gems/dexpace-core/sig/dexpace/configuration/keys.rbs`
- Create: `gems/dexpace-core/lib/dexpace/configuration/sources.rb`
- Create: `gems/dexpace-core/sig/dexpace/configuration/sources.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/configuration/keys_test.rb`
- Test: `gems/dexpace-core/test/dexpace/configuration/sources_test.rb`

**Interfaces:**
- Consumes: Ruby standard library.
- Produces: `Dexpace::Configuration::Keys`, `Dexpace::Configuration::Sources`, RBS interface `_ConfigSource`.

- [ ] **Step 1: Write the failing tests**

Write `gems/dexpace-core/test/dexpace/configuration/keys_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

class DexpaceConfigurationKeysTest < DexpaceTestCase
  test "CFG-14: exports well-known key constants as frozen strings" do
    keys = [
      Dexpace::Configuration::Keys::MAX_RETRY_ATTEMPTS,
      Dexpace::Configuration::Keys::LOG_LEVEL,
      Dexpace::Configuration::Keys::HTTP_PROXY,
      Dexpace::Configuration::Keys::HTTPS_PROXY,
      Dexpace::Configuration::Keys::NO_PROXY,
      Dexpace::Configuration::Keys::MAX_MATERIALIZED_BYTES,
      Dexpace::Configuration::Keys::MAX_TRACKED_CONTEXTS,
    ]

    keys.each do |k|
      assert_predicate(k, :frozen?)
      refute_empty(k)
    end

    assert_equal("MAX_RETRY_ATTEMPTS", Dexpace::Configuration::Keys::MAX_RETRY_ATTEMPTS)
    assert_equal("LOG_LEVEL", Dexpace::Configuration::Keys::LOG_LEVEL)
  end
end
```

Write `gems/dexpace-core/test/dexpace/configuration/sources_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

class DexpaceConfigurationSourcesTest < DexpaceTestCase
  test "CFG-11: ENVIRONMENT seam reads from process ENV" do
    ENV["TEST_CFG_KEY"] = "hello"
    begin
      assert_equal("hello", Dexpace::Configuration::Sources::ENVIRONMENT.call("TEST_CFG_KEY"))
      assert_nil(Dexpace::Configuration::Sources::ENVIRONMENT.call("NON_EXISTENT_CFG_KEY"))
    ensure
      ENV.delete("TEST_CFG_KEY")
    end
  end

  test "CFG-11: NONE seam always returns nil" do
    assert_nil(Dexpace::Configuration::Sources::NONE.call("ANY_KEY"))
  end

  test "CFG-11: from_hash builds an immutable, hermetic lookup seam" do
    source = Dexpace::Configuration::Sources.from_hash("A" => "val-a", 123 => "val-num")
    assert_equal("val-a", source.call("A"))
    assert_equal("val-num", source.call("123"))
    assert_nil(source.call("MISSING"))
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/configuration/keys_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::Configuration`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/configuration/keys.rb` and `sources.rb`**

Write `gems/dexpace-core/lib/dexpace/configuration/keys.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  class Configuration
    # Well-known configuration keys published by dexpace (CFG-14).
    module Keys
      MAX_RETRY_ATTEMPTS = "MAX_RETRY_ATTEMPTS"
      LOG_LEVEL = "LOG_LEVEL"
      HTTP_PROXY = "HTTP_PROXY"
      HTTPS_PROXY = "HTTPS_PROXY"
      NO_PROXY = "NO_PROXY"
      MAX_MATERIALIZED_BYTES = "MAX_MATERIALIZED_BYTES"
      MAX_TRACKED_CONTEXTS = "MAX_TRACKED_CONTEXTS"
    end
  end
end
```

Write `gems/dexpace-core/lib/dexpace/configuration/sources.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  class Configuration
    # Pre-built injectable configuration lookup seams (CFG-11).
    module Sources
      # Seam reading from the host process environment.
      # Named ENVIRONMENT to avoid shadowing Ruby's ::ENV (P5-3).
      ENVIRONMENT = ->(key) { ::ENV[key.to_s] }.freeze

      # Seam resolving all keys to nil (empty source).
      NONE = ->(_key) { nil }.freeze

      # Constructs a hermetic lookup seam from a Hash of string key-value pairs.
      # @param hash [Hash] key-value map
      # @return [Proc] callable from key to String?
      def self.from_hash(hash)
        map = {}
        hash.each { |k, v| map[k.to_s] = v ? v.to_s : nil }
        frozen_map = map.freeze
        ->(key) { frozen_map[key.to_s] }.freeze
      end
    end
  end
end
```

- [ ] **Step 4: Write `sig` files**

Write `gems/dexpace-core/sig/dexpace/configuration/keys.rbs`:
```rbs
module Dexpace
  class Configuration
    module Keys
      MAX_RETRY_ATTEMPTS: String
      LOG_LEVEL: String
      HTTP_PROXY: String
      HTTPS_PROXY: String
      NO_PROXY: String
      MAX_MATERIALIZED_BYTES: String
      MAX_TRACKED_CONTEXTS: String
    end
  end
end
```

Write `gems/dexpace-core/sig/dexpace/configuration/sources.rbs`:
```rbs
module Dexpace
  interface _ConfigSource
    def call: (String key) -> String?
  end

  class Configuration
    module Sources
      ENVIRONMENT: ^(String) -> String?
      NONE: ^(String) -> String?

      def self.from_hash: (::Hash[untyped, untyped] hash) -> (^(String) -> String?)
    end
  end
end
```

- [ ] **Step 5: Do NOT add these two to `lib/dexpace.rb`**

**`keys.rb` and `sources.rb` reopen `class Configuration`, and `configuration.rb` declares it as
`class Configuration < ::Data.define(...)`. Whichever runs first wins the superclass, and the other
raises `TypeError: superclass mismatch for class Configuration`** — reproduced on 3.4.10 while
writing this plan, and a `LoadError`-shaped failure that looks like a typo. So `configuration.rb`
(Task 11) is the only entry point: it declares the class, then requires these two at file scope, then
reopens the class for `EMPTY`, which needs `Sources::ENVIRONMENT` at load time. `lib/dexpace.rb`
gains one line, `require_relative "dexpace/configuration"`, and never these two. Both files
therefore carry no `require_relative` of their own and are never required directly, including from a
test — the suites below reach them through `require "dexpace"`.

- [ ] **Step 6: Run tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/configuration/keys_test.rb`
Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/configuration/sources_test.rb`
Expected: PASS with 1 and 3 runs respectively, 0 failures, 0 errors.

---

## Task 10: `Dexpace::ConfigParsers` and `Dexpace::DeepValue`

**Requirement IDs:** `CFG-5` (integer parsing), `CFG-6` (boolean parsing), `CFG-7` (duration parsing), `CFG-33` (deep equality & hash), `CFG-34` (float & array semantics).
**Design:** "R4 — where `CFG-33`/`CFG-34`'s deep equality lives"; "The object model 5a ships — `Dexpace::ConfigParsers` and `Dexpace::DeepValue`"; "Deviations (P5-4, P5-14, P5-15)".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/configuration/parsers.rb` (`Dexpace::ConfigParsers`, private_constant)
- Create: `gems/dexpace-core/lib/dexpace/deep_value.rb` (`Dexpace::DeepValue`, private_constant)
- Modify: `gems/dexpace-core/lib/dexpace.rb`

**Interfaces:**
- Consumes: Ruby standard library, `Model`.
- Produces: `Dexpace::ConfigParsers` and `Dexpace::DeepValue` private constants.

- [ ] **Step 1: Write `gems/dexpace-core/lib/dexpace/configuration/parsers.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # Internal value parsers for configuration accessors (CFG-5, CFG-6, CFG-7).
  # private_constant on Dexpace.
  module ConfigParsers
    # IGNORECASE for the same reason R2 folds the whole date grammar: accepting more than CFG-7
    # demands cannot reject a conforming input, and CFG-7's own "leading 'P'/'p'" already sets the
    # direction. A negative designator never matches -- \d+ has no sign -- so CFG-7's "A negative
    # duration MUST be rejected" is a property of the pattern rather than of a later check.
    DURATION_ISO = ::Regexp.new(
      '\\A[Pp](?:(?<d>\\d+)D)?(?:T(?:(?<h>\\d+)H)?(?:(?<m>\\d+)M)?(?:(?<s>\\d+(?:\\.\\d+)?)S)?)?\\z',
      ::Regexp::IGNORECASE,
      timeout: 1.0,
    ).freeze

    DURATION_UNIT = ::Regexp.new(
      '\\A(?<val>\\d+(?:\\.\\d+)?)\\s*(?<unit>ms|s|m|h|d)\\z',
      ::Regexp::IGNORECASE,
      timeout: 1.0,
    ).freeze

    DURATION_BARE = ::Regexp.new(
      '\\A(?<val>\\d+(?:\\.\\d+)?)\\z',
      timeout: 1.0,
    ).freeze

    module_function

    # Parses raw string into integer with explicit base 10 (CFG-5).
    # Returns default if raw is absent, non-numeric, or malformed. Negative values are valid and
    # are returned as-is. Base 10 is explicit because Integer("010") is 8 and Integer("010", 10) is
    # 10, and a deployment setting MAX_RETRY_ATTEMPTS=010 would otherwise silently get 8.
    #
    # `Kernel.Integer(...)` and never `::Integer(...)`: the latter is a constant reference and a
    # SyntaxError when written as a call, which `ruby -c` catches and a reader does not.
    def parse_integer(raw, default: nil)
      return default if raw.nil?

      value = ::Kernel.Integer(raw, 10, exception: false)
      value.nil? ? default : value
    end

    # Parses raw string into boolean strictly checking 'true' and 'false' case-insensitively (CFG-6).
    def parse_boolean(raw, default: nil)
      return default if raw.nil?

      case raw.downcase
      when "true" then true
      when "false" then false
      else default
      end
    end

    # Parses raw duration string into Float seconds in CFG-7 order (P5-4):
    # 1. ISO-8601 when starting with 'P' or 'p'
    # 2. Number with unit (ms, s, m, h, d)
    # 3. Bare number as milliseconds
    def parse_duration(raw, default: nil)
      return default if raw.nil? || raw.strip.empty?

      str = raw.strip
      if str.start_with?("P", "p")
        m = DURATION_ISO.match(str)
        return default unless m && m[0] != "P" && m[0] != "p"

        days = m[:d] ? m[:d].to_f : 0.0
        hours = m[:h] ? m[:h].to_f : 0.0
        mins = m[:m] ? m[:m].to_f : 0.0
        secs = m[:s] ? m[:s].to_f : 0.0
        total = (days * 86_400.0) + (hours * 3600.0) + (mins * 60.0) + secs
        return total.negative? ? default : total
      end

      m = DURATION_UNIT.match(str)
      if m
        val = m[:val].to_f
        return default if val.negative?

        case m[:unit].downcase
        when "ms" then return val / 1000.0
        when "s"  then return val
        when "m"  then return val * 60.0
        when "h"  then return val * 3600.0
        when "d"  then return val * 86_400.0
        end
      end

      m = DURATION_BARE.match(str)
      if m
        val = m[:val].to_f
        return default if val.negative?

        return val / 1000.0 # Bare numbers are milliseconds (CFG-7)
      end

      default
    end
  end

  private_constant :ConfigParsers
end
```

- [ ] **Step 2: Write `gems/dexpace-core/lib/dexpace/deep_value.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # Internal deep value comparator and hasher conforming to CFG-33 and CFG-34.
  # private_constant on Dexpace with no sig/ mirror.
  module DeepValue
    # Every NaN folds to ONE seed. Float#hash digests the bit pattern, so (0.0/0.0).hash and
    # "nan".to_f.hash differ (verified fact 7) while DeepValue.equal? calls the two NaNs equal --
    # delegating to Float#hash would break CFG-33's "equals and hashCode MUST be mutually
    # consistent" on the first NaN pair a caller did not build from the same bits.
    NAN_HASH = 0x7ff8_0000_0000_0000.hash
    # Ruby's own `0.0.hash == (-0.0).hash` is TRUE (verified fact 7, re-checked). CFG-34 makes the
    # two UNEQUAL and requires hashing to match, so the negative-zero seed cannot be (-0.0).hash --
    # it is derived from the positive one so the pair can never coincide.
    POSITIVE_ZERO_HASH = 0.0.hash
    NEGATIVE_ZERO_HASH = ~POSITIVE_ZERO_HASH
    CYCLE_HASH = 0xdead_beef.hash

    module_function

    # Evaluates deep equality with CFG-34 float and array semantics.
    def equal?(a, b)
      equal_rec?(a, b, {}.compare_by_identity)
    end

    def equal_rec?(a, b, visited)
      return true if a.equal?(b)
      return false if a.nil? || b.nil?

      if a.is_a?(::Float) && b.is_a?(::Float)
        return true if a.nan? && b.nan?
        # +0.0 and -0.0 are UNEQUAL (CFG-34), discriminated by 1.0/x -> Infinity vs -Infinity.
        return (1.0 / a) == (1.0 / b) if a.zero? && b.zero?

        return a == b
      end

      # Element-kind distinctness: [1] != [1.0] (P5-14). eql? and never ==, which is true for them.
      return a.eql?(b) if a.is_a?(::Numeric) && b.is_a?(::Numeric)

      if a.is_a?(::Array) && b.is_a?(::Array)
        return false if a.size != b.size
        return true if comparing?(visited, a, b)

        return a.each_with_index.all? { |element, index| equal_rec?(element, b[index], visited) }
      end

      if a.is_a?(::Hash) && b.is_a?(::Hash)
        return false if a.size != b.size
        return true if comparing?(visited, a, b)

        return a.all? { |key, value| b.key?(key) && equal_rec?(value, b[key], visited) }
      end

      a == b
    end

    # The guard is keyed by the PAIR, never by each side independently (P5-15). Two separate sets
    # say "a was seen, and separately b was seen", which answers true for an (a, b) pair that was
    # never compared: [u, v, u] against [m, n, n] with u and n unequal is a false positive on the
    # third element. One identity-keyed map of identity-keyed maps says "a is already being
    # compared against b" -- the co-inductive answer for a cycle, and a sound memoisation
    # otherwise, because a false result leaves #all? immediately and never reaches a second read.
    def comparing?(visited, a, b)
      partners = (visited[a] ||= {}.compare_by_identity)
      return true if partners[b]

      partners[b] = true
      false
    end

    # Computes a hash consistent with equal? (CFG-33, CFG-34).
    def hash(value)
      hash_rec(value, {}.compare_by_identity)
    end

    # `stack` is a recursion STACK and not a visited set: the entry is removed on the way out. A
    # set that never unwinds hashes [u, u] differently from an equal [m, n], because the second u
    # would fold to CYCLE_HASH -- which is CFG-33's mutual consistency broken by the guard meant to
    # protect it. Array#hash unwinds the same way, which is the behaviour P5-15 refuses to regress
    # against.
    def hash_rec(value, stack)
      return 0 if value.nil? # CFG-33: "two nulls are equal; null hashes to zero"

      if value.is_a?(::Float)
        return NAN_HASH if value.nan?
        return (1.0 / value).positive? ? POSITIVE_ZERO_HASH : NEGATIVE_ZERO_HASH if value.zero?

        return value.hash
      end

      return CYCLE_HASH if stack[value]

      if value.is_a?(::Array)
        stack[value] = true
        begin
          return value.inject(17) { |acc, element| (acc * 31) + hash_rec(element, stack) }
        ensure
          stack.delete(value)
        end
      end

      if value.is_a?(::Hash)
        stack[value] = true
        begin
          return value.inject(19) { |acc, (key, entry)| acc + (key.hash ^ hash_rec(entry, stack)) }
        ensure
          stack.delete(value)
        end
      end

      value.hash
    end
  end

  private_constant :DeepValue
end
```

- [ ] **Step 3: Add requires to `lib/dexpace.rb`**

Add `require_relative "dexpace/configuration/parsers"` and `require_relative "dexpace/deep_value"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 4: The privateness is asserted, not eyeballed**

Neither file gets a `sig/` mirror, a YARD gate entry, a surface-manifest row or a test mirror
(P2-15, P4-3). What replaces the test mirror is Task 11's suite, which reaches both by **bare name**
from inside `module Dexpace` and asserts that a qualified `::Dexpace::DeepValue` raises `NameError`.
Do not add a `_test.rb` for either file, and do not promote either to public "so it can be tested":
promoting a private constant later is a widening `NFR-4` permits, and the reverse is a break.

---
## Task 11: `Dexpace::Configuration` and `Configuration::Builder`

**Requirement IDs:** `CFG-1`–`CFG-10`, `CFG-12`, `CFG-33`, `CFG-34`, `CFG-37`, `CFG-38`.
**Design:** "The object model 5a ships — `Dexpace::Configuration` and `Builder`"; "Testing strategy — the tests a reader would otherwise write wrong"; "Deviations (P5-4, P5-6, P5-14, P5-15)".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/configuration.rb`
- Create: `gems/dexpace-core/sig/dexpace/configuration.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/configuration_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`, `Dexpace::Configuration::Keys`, `Sources`, `ConfigParsers`, `DeepValue`.
- Produces: `Dexpace::Configuration`, `Dexpace::Configuration::Builder`, `Configuration::EMPTY`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "../support/fake_source"

module Dexpace
  class ConfigurationTest < DexpaceTestCase
    test "CFG-1: resolves in strict precedence order" do
      cfg = Configuration.build(
        overrides: { "KEY" => "from_override" },
        env_source: FakeSource.new("KEY" => "from_env"),
        property_source: FakeSource.new("key" => "from_prop"),
      )
      assert_equal("from_override", cfg.string("KEY", default: "default"))

      cfg2 = Configuration.build(
        overrides: {},
        env_source: FakeSource.new("KEY" => "from_env"),
        property_source: FakeSource.new("key" => "from_prop"),
      )
      assert_equal("from_env", cfg2.string("KEY", default: "default"))

      cfg3 = Configuration.build(
        overrides: {},
        env_source: FakeSource.new,
        property_source: FakeSource.new("key" => "from_prop"),
      )
      assert_equal("from_prop", cfg3.string("KEY", default: "default"))

      cfg4 = Configuration.build(
        overrides: {},
        env_source: FakeSource.new,
        property_source: FakeSource.new,
      )
      assert_equal("default", cfg4.string("KEY", default: "default"))
    end

    test "CFG-2 asymmetry: empty env string falls through while empty override string resolves" do
      cfg_env_empty = Configuration.build(
        overrides: {},
        env_source: FakeSource.new("KEY" => ""),
        property_source: FakeSource.new("key" => "from_prop"),
      )
      assert_equal("from_prop", cfg_env_empty.string("KEY"))

      # The second half is what stops a later refactor making emptiness a chain-wide rule: CFG-2
      # names the environment layer and only the environment layer.
      cfg_override_empty = Configuration.build(
        overrides: { "KEY" => "" },
        env_source: FakeSource.new("KEY" => "from_env"),
        property_source: FakeSource.new,
      )
      assert_equal("", cfg_override_empty.string("KEY"))

      cfg_property_empty = Configuration.build(
        overrides: {},
        env_source: FakeSource.new,
        property_source: FakeSource.new("key" => ""),
      )
      assert_equal("", cfg_property_empty.string("KEY", default: "fallback"))
    end

    test "CFG-3: property lookup uses normalized key (lowercase with dots)" do
      cfg = Configuration.build(
        overrides: {},
        env_source: FakeSource.new,
        property_source: FakeSource.new("max.retry.attempts" => "5"),
      )
      assert_equal("5", cfg.string("MAX_RETRY_ATTEMPTS"))
    end

    # Every Configuration in this suite passes BOTH seams explicitly. Configuration.build defaults
    # env_source: to Sources::ENVIRONMENT, and a test that omits it reads the developer's real
    # environment -- which CFG-11 exists to make unnecessary and which makes a suite depend on the
    # machine it runs on.
    test "CFG-4: raw_property reads exact property name without normalization" do
      cfg = Configuration.build(
        env_source: FakeSource.new,
        property_source: FakeSource.new("https.proxyHost" => "proxy.corp"),
      )
      assert_equal("proxy.corp", cfg.raw_property("https.proxyHost"))
      assert_nil(cfg.raw_property("HTTPS.PROXYHOST"))
    end

    test "CFG-8: builder mutation after build does not mutate built configuration" do
      b = Configuration.builder
      b.override("KEY", "v1")
      c1 = b.build

      b.override("KEY", "v2")
      c2 = b.build

      assert_equal("v1", c1.string("KEY"))
      assert_equal("v2", c2.string("KEY"))
      assert_predicate(c1.overrides, :frozen?)
      assert_raises(FrozenError) { c1.overrides["KEY"] = "mutated" }
    end

    test "CFG-9: derive provides copy-on-write with shared source seams" do
      env = FakeSource.new("A" => "alpha")
      prop = FakeSource.new("b" => "bravo")
      orig = Configuration.build(overrides: { "O" => "orig" }, env_source: env, property_source: prop)

      derived = orig.derive do |builder|
        builder.override("O", "new_orig")
        builder.override("EXTRA", "extra")
      end

      assert_equal("orig", orig.string("O"))
      assert_nil(orig.string("EXTRA"))

      assert_equal("new_orig", derived.string("O"))
      assert_equal("extra", derived.string("EXTRA"))
      assert_same(orig.env_source, derived.env_source)
      assert_same(orig.property_source, derived.property_source)
    end

    test "CFG-10: builder remove drops override without leaving tombstone" do
      b = Configuration.builder
      b.override("K", "v")
      b.remove("K")
      cfg = b.build
      refute_includes(cfg.overrides.keys, "K")
    end

    test "CFG-37: fail-fast validations reject null/empty keys, null values and null seams" do
      b = Configuration.builder
      assert_raises(Dexpace::InvalidArgumentError) { b.override("", "val") }
      assert_raises(Dexpace::InvalidArgumentError) { b.override(nil, "val") }
      assert_raises(Dexpace::InvalidArgumentError) { b.override("K", nil) }
      assert_raises(Dexpace::InvalidArgumentError) { b.property(nil, "val") }
      assert_raises(Dexpace::InvalidArgumentError) { b.property("k", nil) }
      assert_raises(Dexpace::InvalidArgumentError) { b.remove(nil) }
      assert_raises(Dexpace::InvalidArgumentError) { b.env_source = nil }
      assert_raises(Dexpace::InvalidArgumentError) { b.property_source = nil }
      assert_raises(Dexpace::InvalidArgumentError) { Configuration.build(env_source: nil) }

      # The mutator itself is a required argument (CFG-37 names "derive mutator" in as many words).
      error = assert_raises(Dexpace::InvalidArgumentError) { Configuration::EMPTY.derive }
      assert_equal("derive block is required", error.message)

      # A nil default is CFG-37's documented-nullable "lookup default" and is accepted.
      assert_nil(Configuration::EMPTY.string("ANY", default: nil))
    end

    test "CFG-9: an inherited property seam survives derive by reference, not by rebuild" do
      prop = FakeSource.new("a.b" => "v")
      base = Configuration.build(env_source: FakeSource.new, property_source: prop)

      derived = base.derive { |builder| builder.override("X", "1") }
      assert_same(prop, derived.property_source)
      assert_equal("v", derived.string("A_B"))

      # #property on top of an installed seam is refused rather than silently discarding one of
      # them; last-write-wins is right for CFG-13's process slot and wrong inside one builder.
      assert_raises(Dexpace::InvalidArgumentError) do
        base.derive { |builder| builder.property("c.d", "w") }
      end
    end

    # Supplied through the ENV seam and not as an override, deliberately: a test that supplies the
    # value as an override passes against an implementation that reads only the override map, which
    # is the implementation CFG-38 exists to forbid.
    test "CFG-38 against CFG-5: typed accessors resolve values from env and property layers" do
      cfg = Configuration.build(
        env_source: FakeSource.new("INT_KEY" => "42", "BOOL_KEY" => "true", "DUR_KEY" => "500ms"),
        property_source: FakeSource.new("prop.int" => "7"),
      )
      assert_equal(42, cfg.integer("INT_KEY"))
      assert_equal(true, cfg.boolean("BOOL_KEY"))
      assert_in_delta(0.5, cfg.duration("DUR_KEY"), 0.001)
      assert_equal(7, cfg.integer("PROP_INT")) # normalised through the property layer too
    end

    # CFG-5, CFG-6 and CFG-7 live in ConfigParsers, which is a private_constant with no test mirror
    # (P2-15, P4-3), so its behaviour is asserted here at its call sites.
    test "CFG-5: integer parsing is base 10, total, and returns negatives as-is" do
      cfg = Configuration.build(
        env_source: FakeSource.new(
          "OCTAL_LOOKING" => "010", "NEGATIVE" => "-5", "UNDERSCORED" => "1_000",
          "PADDED" => " 5 ", "HEXY" => "0x10", "SCIENTIFIC" => "1e3", "JUNK" => "5x",
          "BLANK" => "",
        ),
        property_source: FakeSource.new,
      )
      # The live defect, not a theoretical one: Integer("010") is 8 and Integer("010", 10) is 10.
      assert_equal(10, cfg.integer("OCTAL_LOOKING"))
      assert_equal(-5, cfg.integer("NEGATIVE"))
      # Ruby's two tolerances, documented rather than removed.
      assert_equal(1000, cfg.integer("UNDERSCORED"))
      assert_equal(5, cfg.integer("PADDED"))
      # Unparseable never throws; it returns the caller's default (CFG-5).
      assert_equal(99, cfg.integer("HEXY", default: 99))
      assert_equal(99, cfg.integer("SCIENTIFIC", default: 99))
      assert_equal(99, cfg.integer("JUNK", default: 99))
      assert_equal(99, cfg.integer("MISSING", default: 99))
      assert_nil(cfg.integer("MISSING"))
      assert_equal(99, cfg.integer("BLANK", default: 99)) # CFG-2: "" in env is absent
    end

    test "CFG-6: the boolean accessor recognises exactly true and false, case-insensitively" do
      entries = { "T" => "true", "F" => "false", "UPPER" => "TRUE", "MIXED" => "FaLsE",
                  "PADDED" => " true" }
      %w[1 0 yes no on off].each_with_index { |token, i| entries["TOKEN#{i}"] = token }
      cfg = Configuration.build(env_source: FakeSource.new(entries), property_source: FakeSource.new)

      assert_equal(true, cfg.boolean("T"))
      assert_equal(false, cfg.boolean("F"))
      assert_equal(true, cfg.boolean("UPPER"))
      assert_equal(false, cfg.boolean("MIXED"))
      # No trimming: CFG-6 grants case-insensitivity and nothing else.
      assert_nil(cfg.boolean("PADDED"))
      6.times { |i| assert_nil(cfg.boolean("TOKEN#{i}"), "TOKEN#{i} must not be recognised") }
      assert_equal(:fallback, cfg.boolean("MISSING", default: :fallback))
    end

    test "CFG-7: durations parse ISO-8601, shorthand and bare milliseconds, into Float seconds" do
      cfg = Configuration.build(
        env_source: FakeSource.new(
          "ISO_S" => "PT5S", "ISO_D" => "P1D", "ISO_MIX" => "P1DT2H3M4S", "ISO_ZERO" => "PT0S",
          "ISO_LOWER" => "pt5s", "ISO_NEG" => "PT-5S",
          "MS" => "250ms", "SEC" => "3s", "MIN" => "2m", "HOUR" => "1h", "DAY" => "1d",
          "CAPS" => "250MS", "BARE" => "1500", "NEG_SHORT" => "-3s", "UNKNOWN_UNIT" => "5w",
        ),
        property_source: FakeSource.new,
      )
      # P5-4: the return is Float SECONDS, which is what Kernel#sleep, Queue#pop(timeout:) and
      # phase 1's RequestOptions#timeout already speak.
      assert_in_delta(5.0, cfg.duration("ISO_S"), 1e-9)
      assert_in_delta(86_400.0, cfg.duration("ISO_D"), 1e-9)
      assert_in_delta(93_784.0, cfg.duration("ISO_MIX"), 1e-9)
      assert_in_delta(0.0, cfg.duration("ISO_ZERO"), 1e-9)
      assert_in_delta(5.0, cfg.duration("ISO_LOWER"), 1e-9)

      assert_in_delta(0.25, cfg.duration("MS"), 1e-9)
      assert_in_delta(3.0, cfg.duration("SEC"), 1e-9)
      assert_in_delta(120.0, cfg.duration("MIN"), 1e-9)
      assert_in_delta(3600.0, cfg.duration("HOUR"), 1e-9)
      assert_in_delta(86_400.0, cfg.duration("DAY"), 1e-9)
      assert_in_delta(0.25, cfg.duration("CAPS"), 1e-9)

      # A bare number is MILLISECONDS (CFG-7), which is the clause a reader gets wrong.
      assert_in_delta(1.5, cfg.duration("BARE"), 1e-9)

      # Negative in either form, and an unknown unit, return the default and never throw.
      assert_equal(:d, cfg.duration("ISO_NEG", default: :d))
      assert_equal(:d, cfg.duration("NEG_SHORT", default: :d))
      assert_equal(:d, cfg.duration("UNKNOWN_UNIT", default: :d))
      assert_equal(:d, cfg.duration("MISSING", default: :d))
    end

    # Two traps, and the pair is chosen to spring both.
    #
    # First: `[n] == [n]` with the SAME object is true, because Array#== short-circuits on identity,
    # so a test written with one NaN literal passes against a broken implementation. refute_same
    # makes the precondition visible.
    #
    # Second, and the one verified fact 7 exists to expose: the payloads must DIFFER. `0.0/0.0` and
    # `-(0.0/0.0)` are both NaN with opposite sign bits, so Float#hash disagrees about them
    # (reproduced across three processes) and an implementation that never folds NaN fails here.
    # A same-bits pair -- two objects built from `[0x7FF8000000000000].pack("Q").unpack1("D")` --
    # hashes equal through Float#hash alone and would pass against exactly that implementation,
    # which is the trap. NOTE: `"nan".to_f` is NOT a NaN in Ruby; it is 0.0. See the correction in
    # "What was verified during planning".
    #
    # No assertion here names a literal hash value: Float#hash is seeded per process.
    test "CFG-33 / CFG-34: DeepValue NaN equality and payload-independent hashing" do
      a = 0.0 / 0.0
      b = -(0.0 / 0.0)
      refute_same(a, b)
      assert_predicate(a, :nan?)
      assert_predicate(b, :nan?)
      refute_equal(a.hash, b.hash) # the precondition: Ruby's own hash disagrees about this pair

      assert(DeepValue.equal?([a], [b]))
      assert_equal(DeepValue.hash([a]), DeepValue.hash([b]))
    end

    test "CFG-34: DeepValue signed zero distinction and hash consistency" do
      # Ruby's own 0.0.hash == (-0.0).hash, so the equality half alone passes against an
      # implementation whose hash is Array#hash. Both halves, in one test.
      assert_equal(0.0.hash, (-0.0).hash)
      refute(DeepValue.equal?([0.0], [-0.0]))
      refute_equal(DeepValue.hash([0.0]), DeepValue.hash([-0.0]))
    end

    test "CFG-34: DeepValue element kind distinctness" do
      assert_equal([1], [1.0]) # Ruby says they are equal; CFG-34 says they are not
      refute(DeepValue.equal?([1], [1.0]))
      refute_equal(DeepValue.hash([1]), DeepValue.hash([1.0]))
    end

    test "CFG-33: DeepValue null-safety, and null hashes to zero" do
      assert(DeepValue.equal?(nil, nil))
      refute(DeepValue.equal?(nil, 1))
      refute(DeepValue.equal?(1, nil))
      assert_equal(0, DeepValue.hash(nil))
    end

    test "CFG-33: byte arrays fall back to ordinary equality on the BINARY String" do
      # Ruby's primitive byte array is a String, so CFG-33's byte-array case is its
      # "non-arrays fall back to ordinary equality" clause and not an array-path branch.
      assert(DeepValue.equal?("\xff\x00".b, "\xff\x00".b))
      refute(DeepValue.equal?("\xff\x00".b, [255, 0]))
    end

    # P2-15 / P4-3's reachability condition, asserted rather than assumed: a private_constant on
    # Dexpace is reachable by bare name from any file that reopens `module Dexpace; ...` in the full
    # nesting form -- which this suite does -- and unreachable through a qualified reference. That
    # asymmetry is what lets these two ship with no sig/ mirror, no YARD gate entry and no surface
    # manifest row, and it is why the assertions above can exist at all.
    test "P2-15: ConfigParsers and DeepValue are private constants, reachable only unqualified" do
      assert_kind_of(::Module, DeepValue)
      assert_kind_of(::Module, ConfigParsers)

      assert_raises(::NameError) { ::Dexpace::DeepValue }
      assert_raises(::NameError) { ::Dexpace::ConfigParsers }
      refute_includes(Dexpace.constants, :DeepValue)
      refute_includes(Dexpace.constants, :ConfigParsers)
    end

    test "CFG-33: DeepValue cycle-safe comparison and hashing" do
      x = []
      x << x
      y = []
      y << y
      assert(DeepValue.equal?(x, y))
      assert_equal(DeepValue.hash(x), DeepValue.hash(y))
    end

    # The pair guard, and the stack that unwinds: two independent visited sets pass the cycle test
    # above and still get both of these wrong (P5-15).
    test "CFG-33: the visited guard is keyed by the pair, and the hash stack unwinds" do
      one = [1]
      two = [2]
      refute(DeepValue.equal?([one, two, one], [[1], [2], [2]]))

      shared = [1]
      assert(DeepValue.equal?([shared, shared], [[1], [1]]))
      assert_equal(DeepValue.hash([shared, shared]), DeepValue.hash([[1], [1]]))
    end
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/configuration_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::Configuration::Builder` or `Configuration.build`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/configuration.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "model"
require_relative "error/invalid_argument_error"

module Dexpace
  # Immutable, 4-tier layered configuration model (CFG-1 through CFG-10, CFG-37, CFG-38).
  #
  # This file declares the class and is the ONLY entry point to it: keys.rb and sources.rb reopen
  # `class Configuration` with no superclass clause, so loading either before this line raises
  # `TypeError: superclass mismatch`. They are required at the foot of this file, and EMPTY is
  # assigned after them because it needs Sources::ENVIRONMENT at load time.
  class Configuration < ::Data.define(:overrides, :env_source, :property_source)
    include Model
    private_class_method :new

    # CFG-12: no mutex, by requirement. "Configuration builders SHOULD be usable single-threaded
    # only; the immutability guarantee applies to the built configuration, not to an in-progress
    # builder." Nobody should add one for symmetry with Dexpace.configure's.
    class Builder
      def initialize(overrides: {}, env_source: Sources::ENVIRONMENT, property_source: nil)
        @overrides = {}
        overrides.each { |k, v| @overrides[k.to_s] = v.to_s }
        @env_source = env_source
        @property_source = property_source
        @properties = {}
        # A seam inherited through #new_builder counts as installed: #derive must hand the SAME
        # object back (CFG-9's "shared, not copied"), so #property on top of one is the same
        # silent-discard failure as #property after an explicit #property_source=.
        @property_source_explicit =
          !(property_source.nil? || property_source.equal?(Sources::NONE))
      end

      def override(key, value)
        Model.required!("key", key)
        Model.required!("value", value)
        k = key.to_s.strip
        raise Dexpace::InvalidArgumentError, "key cannot be empty" if k.empty?

        @overrides[k] = value.to_s
        self
      end

      def remove(key)
        Model.required!("key", key)
        @overrides.delete(key.to_s.strip)
        self
      end

      def property(key, value)
        Model.required!("key", key)
        Model.required!("value", value)
        if @property_source_explicit
          raise Dexpace::InvalidArgumentError, "Cannot call #property after explicit #property_source="
        end

        k = key.to_s.strip.downcase.tr("_", ".")
        raise Dexpace::InvalidArgumentError, "property key cannot be empty" if k.empty?

        @properties[k] = value.to_s
        self
      end

      def property_source=(source)
        Model.required!("property_source", source)
        if @properties.any?
          raise Dexpace::InvalidArgumentError, "Cannot set #property_source= after calling #property"
        end

        @property_source = source
        @property_source_explicit = true
      end

      def env_source=(source)
        Model.required!("env_source", source)
        @env_source = source
      end

      # An installed seam is passed through BY REFERENCE, never rebuilt: CFG-9 requires
      # `derived.property_source.equal?(receiver.property_source)`, and a value-equal copy passes a
      # test written with assert_equal while failing the requirement.
      def build
        prop_source = if @property_source_explicit
                        @property_source
                      elsif @properties.any?
                        Sources.from_hash(@properties)
                      else
                        @property_source || Sources::NONE
                      end

        Configuration.build(
          overrides: @overrides,
          env_source: @env_source,
          property_source: prop_source,
        )
      end
    end

    def self.builder
      Builder.new
    end

    def self.build(overrides: {}, env_source: Sources::ENVIRONMENT, property_source: Sources::NONE)
      Model.required!("overrides", overrides)
      Model.required!("env_source", env_source)
      Model.required!("property_source", property_source)

      frozen_overrides = Model.own(overrides.transform_keys(&:to_s).transform_values(&:to_s))
      new(
        overrides: frozen_overrides,
        env_source: env_source,
        property_source: property_source,
      )
    end

    def new_builder
      Builder.new(
        overrides: overrides.dup,
        env_source: env_source,
        property_source: property_source,
      )
    end

    # Resolves a key in strict 4-tier precedence (CFG-1).
    def string(name, default: nil)
      n = name.to_s
      return overrides[n] if overrides.key?(n)

      env_val = env_source.call(n)
      return env_val if !env_val.nil? && !env_val.empty? # CFG-2: empty env string falls through

      prop_key = n.downcase.tr("_", ".")
      prop_val = property_source.call(prop_key)
      return prop_val unless prop_val.nil? # empty property string resolves

      default
    end

    # Raw property read without normalisation (CFG-4).
    def raw_property(name, default: nil)
      val = property_source.call(name.to_s)
      val.nil? ? default : val
    end

    def integer(name, default: nil)
      ConfigParsers.parse_integer(string(name), default: default)
    end

    def boolean(name, default: nil)
      ConfigParsers.parse_boolean(string(name), default: default)
    end

    def duration(name, default: nil)
      ConfigParsers.parse_duration(string(name), default: default)
    end

    # Derives a new Configuration using copy-on-write (CFG-9, CFG-10). The receiver is untouched:
    # #new_builder dups the override map and passes both seams by reference.
    # @raise [Dexpace::InvalidArgumentError] if no mutator block is given (CFG-37)
    def derive(&mutator)
      Model.required!("derive block", mutator)
      builder = new_builder
      mutator.call(builder)
      builder.build
    end
  end
end

require_relative "configuration/keys"
require_relative "configuration/sources"

module Dexpace
  class Configuration
    # CFG-13's "MUST default to an empty configuration (no overrides, platform-backed seams)".
    # Assigned after sources.rb has loaded, which is why it is not in the body above.
    EMPTY = build(overrides: {}, env_source: Sources::ENVIRONMENT, property_source: Sources::NONE)
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/configuration.rbs`**

```rbs
module Dexpace
  class Configuration
    attr_reader overrides: ::Hash[String, String]
    attr_reader env_source: _ConfigSource
    attr_reader property_source: _ConfigSource

    class Builder
      def override: (String key, String value) -> self
      def remove: (String key) -> self
      def property: (String key, String value) -> self
      def property_source=: (_ConfigSource source) -> _ConfigSource
      def env_source=: (_ConfigSource source) -> _ConfigSource
      def build: () -> Configuration
    end

    def self.builder: () -> Builder
    def self.build: (?overrides: ::Hash[String, String], ?env_source: _ConfigSource, ?property_source: _ConfigSource) -> Configuration
    def new_builder: () -> Builder

    def string: (String name, ?default: String?) -> String?
    def raw_property: (String name, ?default: String?) -> String?
    def integer: (String name, ?default: Integer?) -> Integer?
    def boolean: (String name, ?default: bool?) -> bool?
    def duration: (String name, ?default: Float?) -> Float?
    def derive: () { (Builder) -> void } -> Configuration

    EMPTY: Configuration
  end
end
```

- [ ] **Step 5: Add one require to `lib/dexpace.rb`**

Add `require_relative "dexpace/configuration"`, which pulls in `configuration/keys` and
`configuration/sources` behind it. Task 9's two files stay out of `lib/dexpace.rb` for the
superclass reason stated there.

- [ ] **Step 6: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/configuration_test.rb`
Expected: PASS with 21 runs, 0 failures, 0 errors.

---

## Task 12: Process Configuration: `Dexpace.configure`, `.configuration`, `.reset_config!`

**Requirement IDs:** `CFG-13` (process-wide slot and safe publication).
**Design:** "The object model 5a ships — `Dexpace.configure`, `.configuration`, `.reset_config!`"; "Deviation Ledger (P5-1, P5-2)".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/config.rb`
- Create: `gems/dexpace-core/sig/dexpace/config.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/config_test.rb`

**Interfaces:**
- Consumes: Task 11's `Dexpace::Configuration`.
- Produces: `Dexpace.configure`, `Dexpace.configuration`, `Dexpace.reset_config!`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

class DexpaceConfigTest < DexpaceTestCase
  def teardown
    Dexpace.reset_config!
    super
  end

  test "CFG-13: defaults to Configuration::EMPTY" do
    assert_same(Dexpace::Configuration::EMPTY, Dexpace.configuration)
  end

  test "CFG-13: configure atomically replaces configuration snapshot" do
    Dexpace.configure do |c|
      c.override("APP_NAME", "DexpaceApp")
      c.property("service.timeout", "5000")
    end

    cfg = Dexpace.configuration
    assert_equal("DexpaceApp", cfg.string("APP_NAME"))
    assert_equal("5000", cfg.string("SERVICE_TIMEOUT"))
  end

  test "CFG-13: reset_config! restores Configuration::EMPTY" do
    Dexpace.configure { |c| c.override("K", "V") }
    refute_same(Dexpace::Configuration::EMPTY, Dexpace.configuration)

    Dexpace.reset_config!
    assert_same(Dexpace::Configuration::EMPTY, Dexpace.configuration)
  end

  test "CFG-13: configure block running Dexpace.configuration does not deadlock" do
    Dexpace.configure do |c|
      current = Dexpace.configuration
      assert_kind_of(Dexpace::Configuration, current)
      c.override("REENTRANT", "safe")
    end
    assert_equal("safe", Dexpace.configuration.string("REENTRANT"))
  end

  test "CFG-13 / CFG-37: configure without a block fails fast rather than storing nothing" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace.configure }
    assert_equal("configure block is required", error.message)
    assert_same(Dexpace::Configuration::EMPTY, Dexpace.configuration)
  end

  test "CFG-8 / CFG-13: the published snapshot is frozen, so a reader observes it whole" do
    Dexpace.configure { |c| c.override("K", "V") }
    snapshot = Dexpace.configuration

    assert_predicate(snapshot, :frozen?)
    assert_predicate(snapshot.overrides, :frozen?)
    # Last-write-wins: a second configure replaces the reference and leaves the first untouched.
    Dexpace.configure { |c| c.override("K", "W") }
    assert_equal("V", snapshot.string("K"))
    assert_equal("W", Dexpace.configuration.string("K"))
    refute_same(snapshot, Dexpace.configuration)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/config_test.rb`
Expected: fails with `NoMethodError: undefined method 'configuration' for module Dexpace`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/config.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "model"
require_relative "configuration"

module Dexpace
  @config_mutex = ::Thread::Mutex.new
  @configuration = Configuration::EMPTY

  # Lock-free safe read of the process-wide frozen configuration snapshot (CFG-13).
  # @return [Dexpace::Configuration]
  def self.configuration
    @configuration
  end

  # Configures the process-wide configuration snapshot (CFG-13: last-write-wins, safe publication).
  #
  # The mutex is held across the assignment and across nothing else: the caller's block runs BEFORE
  # it is taken, so a configure block that itself calls Dexpace.configuration cannot deadlock on a
  # non-reentrant, per-fiber-owned Thread::Mutex.
  #
  # CFG-13 is last-write-wins and safe publication and NOTHING else: there is no listener, no
  # observer and no fan-out here, and a change notification would be a new seam nothing asked for.
  #
  # @yieldparam builder [Dexpace::Configuration::Builder]
  # @return [Dexpace::Configuration] the new configuration
  # @raise [Dexpace::InvalidArgumentError] if no block is given (CFG-37 names "the global-config
  #   setter" among the mutating operations that must fail fast rather than store a null)
  def self.configure(&mutator)
    Model.required!("configure block", mutator)
    builder = @configuration.new_builder
    mutator.call(builder)
    new_config = builder.build

    @config_mutex.synchronize { @configuration = new_config }
  end

  # Restores the process-wide configuration to Configuration::EMPTY (CFG-13).
  # Mandatory in test teardowns to prevent cross-suite contamination.
  # @return [Dexpace::Configuration]
  def self.reset_config!
    @config_mutex.synchronize do
      @configuration = Configuration::EMPTY
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/config.rbs`**

```rbs
module Dexpace
  def self.configuration: () -> Configuration
  def self.configure: () { (Configuration::Builder) -> void } -> Configuration
  def self.reset_config!: () -> Configuration
end
```

- [ ] **Step 5: Add require to `lib/dexpace.rb`**

Add `require_relative "dexpace/config"` to `gems/dexpace-core/lib/dexpace.rb`.

- [ ] **Step 6: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/config_test.rb`
Expected: PASS with 6 runs, 0 failures, 0 errors.

---
## Task 13: Downstream Store and IO Wirings

**Requirement IDs:** `DEF-36` (`ContextStore.default` cap), `DEF-34` (`IO.max_materialized_bytes` configured ceiling).
**Design:** "The two picked-up wirings"; "Deferral-register sweep (DEF-34, DEF-36)".

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/context_store.rb`
- Modify: `gems/dexpace-core/lib/dexpace/io.rb`
- Modify: `gems/dexpace-core/sig/dexpace/context_store.rbs`
- Modify: `gems/dexpace-core/sig/dexpace/io.rbs`
- Test: `gems/dexpace-core/test/dexpace/context_store_config_test.rb`
- Test: `gems/dexpace-core/test/dexpace/io_ceiling_test.rb`

**Interfaces:**
- Consumes: Task 11's `Configuration`, `Configuration::Keys`, Task 12's `Dexpace.configuration`.
- Produces: configured `ContextStore.default`, `Dexpace::IO.max_materialized_bytes(configuration)`.

- [ ] **Step 0: Discharge open question 5 — count `MAX_MATERIALIZED_BYTES`'s call sites**

```bash
grep -rn "MAX_MATERIALIZED_BYTES" gems/dexpace-core/lib
```

Record the result here. The design's conditional: **if there is exactly one call site, inline the
read there and add no module function**, which is one fewer `NFR-4`-locked name. Phase 3a guards at
least `#read_exactly` and `#slice`, and 3b's `BODY-32` clamp reads it too, so more than one is
expected and the module function below is the working assumption — but the grep decides, not this
sentence.

- [ ] **Step 1: Write the failing tests**

Write `gems/dexpace-core/test/dexpace/context_store_config_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

class ContextStoreConfigTest < DexpaceTestCase
  def teardown
    Dexpace.reset_config!
    super
  end

  test "DEF-36: ContextStore.default falls back to MAX_TRACKED_CONTEXTS with no configuration" do
    store = Dexpace::ContextStore.default
    assert_kind_of(Dexpace::ContextStore, store)
    assert_same(store, Dexpace::ContextStore.default) # one process-wide instance, memoised
  end

  # The store is memoised, so a Dexpace.configure AFTER the first promotion does not resize it and
  # neither does Dexpace.reset_config!. A cap is a process-lifetime property here. This test asserts
  # the READ rather than the resize, on a fresh store built the way .default builds one, because a
  # test that asserted the resize would be asserting something DEF-36 deliberately does not promise
  # -- and a test that reset .default's memo would be reaching into another phase's ivar.
  test "DEF-36: the configured cap is what a freshly built default store would use" do
    Dexpace.configure { |c| c.override(Dexpace::Configuration::Keys::MAX_TRACKED_CONTEXTS, "3") }

    cap = Dexpace.configuration.integer(
      Dexpace::Configuration::Keys::MAX_TRACKED_CONTEXTS,
      default: Dexpace::ContextStore::MAX_TRACKED_CONTEXTS,
    )
    assert_equal(3, cap)

    store = Dexpace::ContextStore.new(cap: cap)
    assert_kind_of(Dexpace::ContextStore, store)
  end

  test "DEF-36: an unparseable cap falls back to 1024 rather than raising" do
    Dexpace.configure { |c| c.override(Dexpace::Configuration::Keys::MAX_TRACKED_CONTEXTS, "many") }

    assert_equal(
      Dexpace::ContextStore::MAX_TRACKED_CONTEXTS,
      Dexpace.configuration.integer(
        Dexpace::Configuration::Keys::MAX_TRACKED_CONTEXTS,
        default: Dexpace::ContextStore::MAX_TRACKED_CONTEXTS,
      ),
    )
  end
end
```

Write `gems/dexpace-core/test/dexpace/io_ceiling_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

class IOCeilingTest < DexpaceTestCase
  def teardown
    Dexpace.reset_config!
    super
  end

  test "DEF-34: IO.max_materialized_bytes reads the configured ceiling on every call" do
    assert_equal(Dexpace::IO::MAX_MATERIALIZED_BYTES, Dexpace::IO.max_materialized_bytes)

    custom = Dexpace::Configuration.builder
                                   .override(Dexpace::Configuration::Keys::MAX_MATERIALIZED_BYTES,
                                             "1048576")
                                   .build
    assert_equal(1_048_576, Dexpace::IO.max_materialized_bytes(custom))

    # Not memoised: a Dexpace.configure after the first read is effective, which is the DEF-36
    # consequence avoided where it is avoidable (open question 5).
    Dexpace.configure do |c|
      c.override(Dexpace::Configuration::Keys::MAX_MATERIALIZED_BYTES, "2097152")
    end
    assert_equal(2_097_152, Dexpace::IO.max_materialized_bytes)

    Dexpace.reset_config!
    assert_equal(Dexpace::IO::MAX_MATERIALIZED_BYTES, Dexpace::IO.max_materialized_bytes)
  end

  test "DEF-34: an unparseable ceiling falls back to the constant rather than raising" do
    Dexpace.configure do |c|
      c.override(Dexpace::Configuration::Keys::MAX_MATERIALIZED_BYTES, "sixty-four megs")
    end

    assert_equal(Dexpace::IO::MAX_MATERIALIZED_BYTES, Dexpace::IO.max_materialized_bytes)
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io_ceiling_test.rb`
Expected: fails with `NoMethodError: undefined method 'max_materialized_bytes' for module Dexpace::IO`.

- [ ] **Step 3: Modify `gems/dexpace-core/lib/dexpace/context_store.rb` and `io.rb`**

Both files already exist. Change **only** the passages below; every existing constant, class and
method stays exactly as phase 3a and phase 4a wrote it, and neither file gains a `require_relative`
of `configuration` — `lib/dexpace.rb` loads it, and adding one here would make a phase-3 file
depend on a phase-5 one at load time.

In `gems/dexpace-core/lib/dexpace/context_store.rb`, replace the body of the existing
`class << self ... def default ... end ... end` block:

```ruby
      # The one process-wide instance. Not a constant: a live store cannot be frozen at assignment,
      # which a mutable constant must be.
      #
      # DEF-36: the cap comes from the layered chain at FIRST construction, falling back to
      # MAX_TRACKED_CONTEXTS. No signature changes, which is DEF-36's own claim. The consequence,
      # stated because it is not obvious: the store is memoised, so a Dexpace.configure after the
      # first promotion does not resize it and neither does Dexpace.reset_config!. A cap is a
      # process-lifetime property here, and a test that needs a different one builds its own
      # ContextStore.new(cap:) -- which is what phase 4a made the keyword for.
      def default
        @default ||= new(
          cap: Dexpace.configuration.integer(
            Configuration::Keys::MAX_TRACKED_CONTEXTS,
            default: MAX_TRACKED_CONTEXTS,
          ),
        )
      end
```

In `gems/dexpace-core/lib/dexpace/io.rb`, **add** this module function beside the existing
`MAX_MATERIALIZED_BYTES` — do not restate the constant, which would emit an
`already initialized constant` warning and fail the build under `-w`:

```ruby
    # DEF-34's ceiling half: §3.1's "configurable through the same layered chain as every other
    # limit". Read on every call rather than memoised, so Dexpace.configure and
    # Dexpace.reset_config! stay effective -- the DEF-36 consequence above, avoided where it is
    # avoidable. NO `ceiling:` keyword is added anywhere, so phase 3's boundary 8 ("a ceiling:
    # keyword on a preview operation would give one stream two ceilings") is untouched.
    #
    # @param configuration [Dexpace::Configuration]
    # @return [Integer] the effective ceiling in bytes
    def self.max_materialized_bytes(configuration = Dexpace.configuration)
      configuration.integer(
        Configuration::Keys::MAX_MATERIALIZED_BYTES,
        default: MAX_MATERIALIZED_BYTES,
      )
    end
```

- [ ] **Step 4: Update `sig` files**

In `gems/dexpace-core/sig/dexpace/context_store.rbs`:
```rbs
module Dexpace
  class ContextStore
    def self.default: () -> ContextStore
  end
end
```

In `gems/dexpace-core/sig/dexpace/io.rbs`:
```rbs
module Dexpace
  module IO
    MAX_MATERIALIZED_BYTES: Integer
    def self.max_materialized_bytes: (?Configuration configuration) -> Integer
  end
end
```

- [ ] **Step 5: Run tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/context_store_config_test.rb`
Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/io_ceiling_test.rb`
Expected: PASS with 3 and 2 runs respectively, 0 failures, 0 errors.

---

## Task 14: `Dexpace::Proxy`, `Proxy::Type` and `Proxy::HostPattern`

**Requirement IDs:** `CFG-22` (the immutable proxy model, its type and its masked rendering),
`CFG-23` (host-pattern glob matching and the bypass decision), `CFG-25`'s range check on the model,
`CFG-27`'s explicit bypass-all flag.
**Design:** "The object model 5a ships — `Dexpace::Proxy`, `Dexpace::Proxy::Type` and
`Dexpace::Proxy::HostPattern`"; "Deviations (P5-5, P5-7)".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/proxy.rb`
- Create: `gems/dexpace-core/sig/dexpace/proxy.rbs`
- Create: `gems/dexpace-core/lib/dexpace/proxy/type.rb`
- Create: `gems/dexpace-core/sig/dexpace/proxy/type.rbs`
- Create: `gems/dexpace-core/lib/dexpace/proxy/host_pattern.rb`
- Create: `gems/dexpace-core/sig/dexpace/proxy/host_pattern.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/proxy/type_test.rb`
- Test: `gems/dexpace-core/test/dexpace/proxy/host_pattern_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`, `Dexpace::InvalidArgumentError`.
- Produces: `Dexpace::Proxy` (without `.resolve`, which is Task 15's), `Dexpace::Proxy::Type`,
  `Dexpace::Proxy::HostPattern`.

**`proxy.rb` lands here and not in Task 15, because nothing else can load without it.** `type.rb`
and `host_pattern.rb` reopen `class Proxy`; if either is loaded before `proxy.rb` declares
`class Proxy < ::Data.define(...)`, the later one raises `TypeError: superclass mismatch` — so
`proxy.rb` must exist, and be the requiring file, from the moment its two nested types do. Task 15
adds `Proxy.resolve` and the third trailing `require_relative` to this same file.

- [ ] **Step 1: Write the failing tests**

Write `gems/dexpace-core/test/dexpace/proxy/type_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

class DexpaceProxyTypeTest < DexpaceTestCase
  test "CFG-22: exposes HTTP, SOCKS4, and SOCKS5 singletons" do
    assert_equal("HTTP", Dexpace::Proxy::Type::HTTP.name)
    assert_equal("SOCKS4", Dexpace::Proxy::Type::SOCKS4.name)
    assert_equal("SOCKS5", Dexpace::Proxy::Type::SOCKS5.name)
  end

  test "CFG-22: of factory resolves string case-insensitively or raises" do
    assert_same(Dexpace::Proxy::Type::HTTP, Dexpace::Proxy::Type.of("http"))
    assert_same(Dexpace::Proxy::Type::SOCKS5, Dexpace::Proxy::Type.of("SOCKS5"))
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Proxy::Type.of("UNKNOWN") }
  end
end
```

Write `gems/dexpace-core/test/dexpace/proxy/host_pattern_test.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

class DexpaceProxyHostPatternTest < DexpaceTestCase
  test "CFG-23: glob matching handles wildcards and case-insensitivity" do
    p = Dexpace::Proxy::HostPattern.of("*.example.com")
    assert(p.matches?("api.example.com"))
    assert(p.matches?("API.Example.COM"))
    refute(p.matches?("example.com")) # apex domain not matched

    q = Dexpace::Proxy::HostPattern.of("test?.example.com")
    assert(q.matches?("test1.example.com"))
    refute(q.matches?("test12.example.com"))
  end

  test "CFG-23: newline in host does not match pattern" do
    p = Dexpace::Proxy::HostPattern.of("evil.com")
    refute(p.matches?("evil.com\n"))
    refute(p.matches?("sub.evil.com\n.example.com"))
  end

  test "Property test: round-trips glob attribute, and #with recompiles the matcher" do
    ["*.com", "host?.org", "exact.net"].each do |g|
      p = Dexpace::Proxy::HostPattern.of(g)
      assert_equal(g, p.glob)
      assert(p.matches?(g)) if g !~ /[*?]/
    end

    # Model#with routes through .build, which re-enters initialize -- so the matcher is recompiled
    # from the new glob rather than carried over from the old one.
    derived = Dexpace::Proxy::HostPattern.of("*.old").with(glob: "*.new")
    assert_equal("*.new", derived.glob)
    assert(derived.matches?("api.new"))
    refute(derived.matches?("api.old"))
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/proxy/type_test.rb`
Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/proxy/host_pattern_test.rb`
Expected: both fail with `NameError: uninitialized constant Dexpace::Proxy`.

- [ ] **Step 3: Write `proxy.rb` first, then `proxy/type.rb` and `proxy/host_pattern.rb`**

Write `gems/dexpace-core/lib/dexpace/proxy.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "model"
require_relative "error/invalid_argument_error"

module Dexpace
  # Immutable proxy configuration model (CFG-22).
  #
  # This file declares the class and is the only entry point to it: proxy/type.rb,
  # proxy/host_pattern.rb and proxy/resolution.rb are required at its foot, because the first two
  # reopen `class Proxy` and loading either first raises `TypeError: superclass mismatch`.
  #
  # String representations mask credentials (P5-7).
  class Proxy < ::Data.define(
    :type,
    :host,
    :port,
    :non_proxy_hosts,
    :username,
    :password,
    :challenge_handler,
    :bypass_all,
  )
    include Model
    private_class_method :new

    def self.build(
      type:,
      host:,
      port:,
      non_proxy_hosts: [],
      username: nil,
      password: nil,
      challenge_handler: nil,
      bypass_all: false
    )
      Model.required!("type", type)
      Model.required!("host", host)
      Model.required!("port", port)

      p = port.to_i
      if p.negative? || p > 65_535
        raise Dexpace::InvalidArgumentError, "Proxy port must be between 0 and 65535: #{port.inspect}"
      end

      patterns = Model.own(non_proxy_hosts.to_a)

      new(
        type: type,
        host: host.to_s.freeze,
        port: p,
        non_proxy_hosts: patterns,
        username: username ? username.to_s.freeze : nil,
        password: password ? password.to_s.freeze : nil,
        challenge_handler: challenge_handler,
        bypass_all: !!bypass_all,
      )
    end

    # Determines whether a given host should bypass the proxy (CFG-23).
    # @param target_host [String] host to evaluate
    # @return [Boolean] true if bypassed
    def bypass?(target_host)
      return true if bypass_all

      non_proxy_hosts.any? { |pattern| pattern.matches?(target_host) }
    end

    # CFG-22: "Its string rendering MUST mask credentials (never emit username/password in
    # cleartext)." Both renderings are overridden, not just #to_s (P5-7): Data's generated #inspect
    # prints every member including password, and #inspect -- not #to_s -- is what `p`, a log
    # interpolation and an assert_equal failure message print.
    def to_s
      auth = username ? "#{username}:****@" : ""
      "#{type.name.downcase}://#{auth}#{host}:#{port}"
    end

    def inspect
      masked = password.nil? ? "nil" : "\"****\""
      "#<#{self.class.name} type=#{type.name} host=#{host.inspect} port=#{port} " \
        "username=#{username.inspect} password=#{masked} " \
        "non_proxy_hosts=#{non_proxy_hosts.size} bypass_all=#{bypass_all}>"
    end
  end
end

require_relative "proxy/type"
require_relative "proxy/host_pattern"
```

Write `gems/dexpace-core/lib/dexpace/proxy/type.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Proxy
    # Protocol type for a proxy (CFG-22): a frozen Data over a frozen table with an .of factory,
    # never a Symbol and never an enum library (type-system/545949a5). The set is closed BY the
    # requirement, so .of raises on an unrecognised token -- phase 1's Protocol treatment, not its
    # Status treatment.
    class Type < ::Data.define(:name)
      include Model
      private_class_method :new

      NAMES = %w[HTTP SOCKS4 SOCKS5].freeze
      private_constant :NAMES

      # Validation lives here and not in .build, so #with -- which routes through .build -- cannot
      # derive a fourth type (phase 1's construction rule; phase 2's Settlement is the precedent).
      def initialize(name:)
        text = Model.required!("proxy type", name).to_s
        unless NAMES.include?(text)
          raise Dexpace::InvalidArgumentError, "unknown proxy type: #{name.inspect}"
        end

        super(name: Model.frozen_string(text))
      end

      def self.build(name:)
        new(name: name)
      end

      HTTP = build(name: "HTTP")
      SOCKS4 = build(name: "SOCKS4")
      SOCKS5 = build(name: "SOCKS5")

      # Not public: P5-1 fixes Type's public surface at three constants, and an exposed table is a
      # fourth NFR-4-locked name with one caller.
      ALL = [HTTP, SOCKS4, SOCKS5].freeze
      private_constant :ALL

      # Resolves a proxy protocol token to one of the three shared instances.
      # @param token [String, Symbol] protocol token
      # @return [Type] the shared instance
      # @raise [Dexpace::InvalidArgumentError] if token is unrecognised
      def self.of(token)
        text = Model.required!("proxy type", token).to_s.strip.upcase
        ALL.find { |type| type.name == text } ||
          raise(Dexpace::InvalidArgumentError, "unknown proxy type: #{token.inspect}")
      end
    end
  end
end
```

Write `gems/dexpace-core/lib/dexpace/proxy/host_pattern.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Proxy
    # Compiled host glob pattern for non-proxy host matching (CFG-23).
    #
    # The Regexp is compiled in #initialize when it is absent, which is CFG-23's "Patterns SHOULD be
    # compiled once at construction, not per lookup" and is also what lets Model#with round-trip
    # through .build(**to_h, **changes) without a member that cannot be reconstructed.
    class HostPattern < ::Data.define(:glob, :matcher)
      include Model
      private_class_method :new

      # `matcher:` exists because Data#to_h carries it and Model#with replays every member through
      # .build. It is deliberately IGNORED: a matcher replayed from the old glob beside a new one is
      # a pattern that no longer matches what it claims to, and `#with(glob:)` is the only
      # derivation this two-member type has. The Regexp is compiled from the glob, once, here --
      # which is still CFG-23's "compiled once at construction, not per lookup".
      def initialize(glob:, matcher: nil) # rubocop:disable Lint/UnusedMethodArgument
        text = Model.required!("glob", glob).to_s
        raise Dexpace::InvalidArgumentError, "glob is required" if text.empty?

        super(glob: Model.frozen_string(text), matcher: translate(text))
      end

      def self.build(glob:, matcher: nil)
        new(glob: glob, matcher: matcher)
      end

      # The parse-constructor.
      # @param glob [String] wildcard pattern, e.g. *.example.com
      # @return [HostPattern] compiled pattern
      def self.of(glob)
        build(glob: glob)
      end

      # Tests whether a candidate host matches this pattern.
      #
      # The host is matched EXACTLY as given. Stripping it first would defeat the \z anchor:
      # "evil.com\n".strip is "evil.com", so a stripping matcher answers true for a host that is not
      # the host -- verified, and the same hole \Z would open from the other end.
      #
      # @param host [String] host to evaluate
      # @return [Boolean] true if matched
      def matches?(host)
        return false if host.nil?

        matcher.match?(host.to_s)
      end

      private

      # CFG-23's four rules, verified: `*` -> `.*`, `?` -> `.`, everything else Regexp.escape'd, a
      # FULL-string match anchored \A..\z, matched case-insensitively. \z and never \Z, because
      # \Aabc\Z matches "abc\n" and a full-string match that accepts a trailing newline is not one.
      # No /m: `.*` stopping at \n is what keeps *.example.com from matching
      # "evil.com\n.example.com" -- turning a tolerance into a bypass of the check itself. The
      # timeout is per-pattern and never the process-global Regexp.timeout.
      def translate(glob)
        source = +"\\A"
        glob.each_char do |char|
          source << case char
                    when "*" then ".*"
                    when "?" then "."
                    else ::Regexp.escape(char)
                    end
        end
        ::Regexp.new(source << "\\z", ::Regexp::IGNORECASE, timeout: 1.0)
      end
    end
  end
end
```

- [ ] **Step 4: Write `sig` files**

Write `gems/dexpace-core/sig/dexpace/proxy.rbs` (Task 15 adds `self.resolve` to it), then:

```rbs
module Dexpace
  class Proxy
    attr_reader type: Proxy::Type
    attr_reader host: String
    attr_reader port: Integer
    attr_reader non_proxy_hosts: ::Array[Proxy::HostPattern]
    attr_reader username: String?
    attr_reader password: String?
    attr_reader challenge_handler: untyped
    attr_reader bypass_all: bool

    def self.build: (
      type: Proxy::Type,
      host: String,
      port: Integer,
      ?non_proxy_hosts: ::Array[Proxy::HostPattern],
      ?username: String?,
      ?password: String?,
      ?challenge_handler: untyped,
      ?bypass_all: bool
    ) -> Proxy

    def bypass?: (String target_host) -> bool
    def to_s: () -> String
    def inspect: () -> String
  end
end
```

Write `gems/dexpace-core/sig/dexpace/proxy/type.rbs`:
```rbs
module Dexpace
  class Proxy
    class Type
      attr_reader name: String
      def self.of: (String | Symbol token) -> Type

      HTTP: Type
      SOCKS4: Type
      SOCKS5: Type
    end
  end
end
```

Write `gems/dexpace-core/sig/dexpace/proxy/host_pattern.rbs`:
```rbs
module Dexpace
  class Proxy
    class HostPattern
      attr_reader glob: String
      attr_reader matcher: ::Regexp

      def self.of: (String glob) -> HostPattern
      def matches?: (String host) -> bool
    end
  end
end
```

- [ ] **Step 5: Add one require to `lib/dexpace.rb`**

`require_relative "dexpace/proxy"`, and **only** that: `proxy.rb` requires `proxy/type` and
`proxy/host_pattern` at its foot, and Task 15 adds `proxy/resolution` beside them. Neither nested
file ever appears in `lib/dexpace.rb`, for the same superclass reason Task 9 states — these two
reopen `class Proxy` and only `proxy.rb` may declare it.

- [ ] **Step 6: Run tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/proxy/type_test.rb`
Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/proxy/host_pattern_test.rb`
Expected: PASS with 2 and 3 runs respectively, 0 failures, 0 errors.

---
## Task 15: `Dexpace::ProxyResolution` and `Proxy.resolve`

**Requirement IDs:** `CFG-24` (source precedence and the never-throw clause), `CFG-25` (explicit
port, 0..65535, absent means invalid), `CFG-26` (non-proxy host escape, split order and the
property-over-environment precedence), `CFG-27` (bypass-all), `CFG-28` (explicit resolution only).
Task 14 carries `CFG-22` and `CFG-23`.
**Design:** "The object model 5a ships — `Dexpace::ProxyResolution`"; "Testing strategy — the tests
a reader would otherwise write wrong"; "Deviations (P5-8)".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/proxy/resolution.rb` (`Dexpace::ProxyResolution`, `private_constant`, no `sig/` mirror and no test mirror)
- Modify: `gems/dexpace-core/lib/dexpace/proxy.rb` (add `Proxy.resolve` and the third trailing require)
- Modify: `gems/dexpace-core/sig/dexpace/proxy.rbs` (add `self.resolve`)
- Test: `gems/dexpace-core/test/dexpace/proxy_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Configuration` (`#raw_property`, `#string`), `Configuration::Keys`,
  `Proxy::Type`, `Proxy::HostPattern`, `URI::RFC3986_PARSER`.
- Produces: `Dexpace::Proxy.resolve(configuration = Dexpace.configuration) -> Proxy?`.

**Step 3 adds two things to `proxy.rb`** — the method and the require — and changes nothing else in
it:

```ruby
    # Resolves proxy options from configuration (CFG-24). Never raises: invalid configuration
    # yields nil and a warning.
    #
    # CFG-28's MAY is taken and its prohibition is met structurally: the argument defaults to
    # Dexpace.configuration, and NOTHING in core calls this. No environment read happens unless a
    # caller invokes the resolver, which is "nothing may read proxy configuration implicitly at
    # construction/startup" enforced by the absence of a call site rather than by a comment.
    #
    # @param configuration [Dexpace::Configuration]
    # @return [Proxy, nil]
    def self.resolve(configuration = Dexpace.configuration)
      ProxyResolution.resolve(configuration)
    end
```

and, at the foot of the file, after the two requires Task 14 put there:

```ruby
require_relative "proxy/resolution"
```

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "../support/fake_source"

# DexpaceTestCase prepends FatalWarnings to Warning.singleton_class, so every Warning.warn raises
# "warning treated as an error (NFR-6)" -- including the one CFG-24 and CFG-25 REQUIRE the resolver
# to emit. Minitest's `Warning.stub(:warn, ...)` cannot intercept it: `stub` defines a method on the
# singleton class, and a prepended module sits ahead of that in the ancestry, so FatalWarnings#warn
# still runs and still raises. Verified on 3.4.10.
#
# The sink below is prepended AFTER FatalWarnings, so it sits ahead of it, and it delegates with
# `super` whenever no capture is active -- warnings outside a capture block still fail their test.
# It is defined here rather than in test/support/ because the design fixes exactly three
# test-support doubles and this is not a fourth double, it is one test file's harness.
module ProxyWarningSink
  def warn(message, category: nil)
    sink = ::Thread.current[:dexpace_captured_warnings]
    return sink << message if sink

    super
  end
end
Warning.singleton_class.prepend(ProxyWarningSink)

class DexpaceProxyTest < DexpaceTestCase
  # testing/26b866e1 forbids assert_nothing_raised, so CFG-24's never-throw clause is asserted as
  # assert_nil on the result AND an assertion on the captured warning. The second half is not
  # optional: a warning that escapes fails the test under DexpaceTestCase.
  def capture_warnings
    Thread.current[:dexpace_captured_warnings] = []
    yield
    Thread.current[:dexpace_captured_warnings]
  ensure
    Thread.current[:dexpace_captured_warnings] = nil
  end

  # Both seams are always supplied: Configuration.build defaults env_source: to the real process
  # environment, and a proxy suite that inherits it fails on a developer machine with HTTPS_PROXY set.
  def config(properties: {}, environment: {})
    Dexpace::Configuration.build(
      env_source: Dexpace::FakeSource.new(environment),
      property_source: Dexpace::FakeSource.new(properties),
    )
  end

  test "CFG-22 / P5-7: string rendering and inspect mask credentials" do
    proxy = Dexpace::Proxy.build(
      type: Dexpace::Proxy::Type::HTTP,
      host: "proxy.internal",
      port: 8080,
      username: "admin",
      password: "SuperSecretPassword",
    )

    refute_includes(proxy.to_s, "SuperSecretPassword")
    assert_includes(proxy.to_s, "****")

    refute_includes(proxy.inspect, "SuperSecretPassword")
    assert_includes(proxy.inspect, "****")
  end

  test "CFG-23 / CFG-27: bypass? evaluates bypass_all and host pattern globs" do
    proxy = Dexpace::Proxy.build(
      type: Dexpace::Proxy::Type::HTTP,
      host: "proxy.internal",
      port: 8080,
      non_proxy_hosts: [Dexpace::Proxy::HostPattern.of("*.local"), Dexpace::Proxy::HostPattern.of("127.0.0.1")],
    )

    assert(proxy.bypass?("service.local"))
    assert(proxy.bypass?("127.0.0.1"))
    refute(proxy.bypass?("external.com"))

    bypass_all_proxy = Dexpace::Proxy.build(
      type: Dexpace::Proxy::Type::HTTP,
      host: "proxy.internal",
      port: 8080,
      bypass_all: true,
    )
    assert(bypass_all_proxy.bypass?("anything.com"))
  end

  # The chapter's own conformance case, and a negative: set ONLY the http.* host and port plus the
  # https.* credentials, and assert the resolved proxy carries those credentials. A test that also
  # sets https.proxyHost proves nothing, because the cross-layer read is what CFG-24 is about.
  test "CFG-24: the port comes from the host's layer, and credentials from https.* only" do
    proxy = Dexpace::Proxy.resolve(config(properties: {
      "http.proxyHost" => "http-proxy.corp",
      "http.proxyPort" => "3128",
      "https.proxyUser" => "alice",
      "https.proxyPassword" => "secret",
    }))

    assert_equal("http-proxy.corp", proxy.host)
    assert_equal(3128, proxy.port)
    assert_equal("alice", proxy.username)
    assert_equal("secret", proxy.password)
  end

  test "CFG-24: https.proxyHost wins over http.proxyHost, and takes https.proxyPort with it" do
    proxy = Dexpace::Proxy.resolve(config(properties: {
      "https.proxyHost" => "secure.corp", "https.proxyPort" => "8443",
      "http.proxyHost" => "plain.corp",  "http.proxyPort" => "3128",
    }))

    assert_equal("secure.corp", proxy.host)
    assert_equal(8443, proxy.port)
  end

  # A guard, not a coincidence: the day someone "simplifies" the resolver onto #port, this says why
  # it is wrong rather than merely failing somewhere else.
  test "CFG-25: RFC3986_PARSER#port defaults to 80 and #split[3] does not" do
    assert_equal(80, URI::RFC3986_PARSER.parse("http://proxy.example").port)
    assert_nil(URI::RFC3986_PARSER.split("http://proxy.example")[3])
    assert_equal("8080", URI::RFC3986_PARSER.split("http://proxy.example:8080")[3])
  end

  test "CFG-25: absent port in proxy URL is invalid and resolves to nil with a warning" do
    proxy = nil
    warnings = capture_warnings do
      proxy = Dexpace::Proxy.resolve(config(environment: { "HTTPS_PROXY" => "http://proxy.example" }))
    end

    assert_nil(proxy)
    assert(warnings.any? { |w| w.include?("no explicit port") }, warnings.inspect)
  end

  test "CFG-25: a port outside 0..65535 yields nil with a warning" do
    proxy = nil
    warnings = capture_warnings do
      proxy = Dexpace::Proxy.resolve(config(properties: {
        "https.proxyHost" => "proxy.corp", "https.proxyPort" => "70000",
      }))
    end

    assert_nil(proxy)
    assert(warnings.any? { |w| w.include?("70000") }, warnings.inspect)
  end

  # CFG-24's clause (2) is "IF NO system-property host is set". A property host whose port is
  # unusable therefore yields nil; falling through to HTTPS_PROXY here would turn CFG-25's
  # "MUST yield null rather than guessing a default port" into guessing a different proxy.
  test "CFG-24 / CFG-25: an unusable property port does not fall through to the environment" do
    proxy = nil
    warnings = capture_warnings do
      proxy = Dexpace::Proxy.resolve(config(
        properties: { "https.proxyHost" => "proxy.corp", "https.proxyPort" => "abc" },
        environment: { "HTTPS_PROXY" => "http://other.example:8080" },
      ))
    end

    assert_nil(proxy)
    assert(warnings.any? { |w| w.include?("proxy.corp") }, warnings.inspect)
  end

  test "CFG-24: a malformed proxy URL yields nil with a warning and never raises" do
    ["http://h:abc", "not a url", "http://:8080"].each do |bad|
      proxy = :unset
      warnings = capture_warnings do
        proxy = Dexpace::Proxy.resolve(config(environment: { "HTTPS_PROXY" => bad }))
      end

      assert_nil(proxy, "#{bad.inspect} must resolve to nil")
      refute_empty(warnings, "#{bad.inspect} must warn")
    end
  end

  test "CFG-24: percent-encoded credentials in a proxy URL are decoded, and + is not a space" do
    proxy = Dexpace::Proxy.resolve(
      config(environment: { "HTTPS_PROXY" => "http://u%40x:p%3As+t@proxy.example:8080" }),
    )

    assert_equal("u@x", proxy.username)
    assert_equal("p:s+t", proxy.password)
  end

  test "CFG-26: non-proxy hosts escape and observable split-drop-unescape-trim order" do
    proxy = Dexpace::Proxy.resolve(config(environment: {
      "HTTP_PROXY" => "http://proxy.example:8080",
      "NO_PROXY" => "a\\,b, c, , d",
    }))

    # The whitespace-only fragment survives CFG-26's order as an empty token and is then dropped,
    # because HostPattern.of("") is not a host pattern. See split_non_proxy's comment.
    assert_equal(3, proxy.non_proxy_hosts.size)
    assert_equal("a,b", proxy.non_proxy_hosts[0].glob)
    assert_equal("c", proxy.non_proxy_hosts[1].glob)
    assert_equal("d", proxy.non_proxy_hosts[2].glob)
  end

  test "CFG-26: the pipe-separated system property wins over NO_PROXY, whichever source gave the host" do
    proxy = Dexpace::Proxy.resolve(config(
      properties: { "http.nonProxyHosts" => "a\\|b|*.internal" },
      environment: { "HTTPS_PROXY" => "http://proxy.example:8080", "NO_PROXY" => "ignored.example" },
    ))

    assert_equal(["a|b", "*.internal"], proxy.non_proxy_hosts.map(&:glob))
    assert(proxy.bypass?("svc.internal"))
    refute(proxy.bypass?("ignored.example"))
  end

  test "CFG-27: NO_PROXY='*' resolves to nil, while '*' in a list stays an ordinary glob" do
    assert_nil(Dexpace::Proxy.resolve(config(environment: {
      "HTTP_PROXY" => "http://proxy.example:8080", "NO_PROXY" => "*",
    })))

    proxy = Dexpace::Proxy.resolve(config(environment: {
      "HTTP_PROXY" => "http://proxy.example:8080", "NO_PROXY" => "*,x.example",
    }))
    refute_nil(proxy)
    refute_predicate(proxy, :bypass_all)
    assert_equal(2, proxy.non_proxy_hosts.size)
  end

  # CFG-28's prohibition, met structurally: resolution happens only when a caller invokes the
  # resolver, and nothing in core invokes it. The absence of a call site is the enforcement.
  test "CFG-28: nothing in core resolves proxy configuration implicitly" do
    root = File.expand_path("../../lib", __dir__) # gems/dexpace-core/lib
    call_sites = Dir.glob("#{root}/**/*.rb").grep_v(%r{/proxy\.rb\z}).select do |path|
      File.read(path).include?("Proxy.resolve")
    end

    assert_empty(call_sites)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/proxy_test.rb`
Expected: fails with `NoMethodError: undefined method 'resolve' for class Dexpace::Proxy` — the
model itself already exists, because Task 14 built it.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/proxy/resolution.rb`, then add `Proxy.resolve` and the third require to `proxy.rb`**

Write `gems/dexpace-core/lib/dexpace/proxy/resolution.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "uri"

module Dexpace
  # Internal proxy resolution logic conforming to CFG-24 through CFG-28.
  # private_constant on Dexpace.
  module ProxyResolution
    LAYERS = {
      https: { host: "https.proxyHost", port: "https.proxyPort" },
      http:  { host: "http.proxyHost",  port: "http.proxyPort" },
    }.freeze

    CRED_USER = "https.proxyUser"
    CRED_PASS = "https.proxyPassword"
    NON_PROXY_PROP = "http.nonProxyHosts"

    module_function

    # CFG-24's two sources, in its order and with its boundary: the environment is consulted only
    # "if no system-property host is set". A system-property host with an unusable port therefore
    # yields nil, never a silent fall-through to HTTPS_PROXY -- which would be CFG-25's
    # "MUST cause resolution to yield null rather than guessing" inverted into guessing elsewhere.
    def resolve(configuration)
      layer, host = property_host(configuration)
      return from_properties(configuration, layer, host) if host

      from_environment(configuration)
    rescue ::StandardError => error
      # CFG-24: "MUST NOT throw on any malformed input". Every input this resolver expects to be
      # malformed is answered by an explicit nil-with-warning above; this is the backstop, and it
      # is deliberately last rather than wrapped around the parse alone, because CFG-24's clause is
      # about the operation and not about one call inside it.
      emit("proxy resolution failed: #{error.class}: #{error.message}")
      nil
    end

    # @return [Array(Symbol, String), Array(nil, nil)] the layer the host came from, and the host
    def property_host(configuration)
      LAYERS.each do |layer, keys|
        value = configuration.raw_property(keys[:host])
        next if value.nil? || value.strip.empty?

        return [layer, value.strip]
      end
      [nil, nil]
    end

    def from_properties(configuration, layer, host)
      # The port comes from the SAME layer as the chosen host -- one lookup on `layer`, never two
      # independent reads, which is the clause a test that sets both layers cannot catch.
      raw_port = configuration.raw_property(LAYERS[layer][:port])
      port = parse_port(raw_port)
      unless port
        emit("proxy port for #{host} is missing, non-numeric or outside 0..65535: #{raw_port.inspect}")
        return nil
      end

      patterns, bypass_all = non_proxy_hosts(configuration)
      return nil if bypass_all

      # Credentials come from https.proxyUser / https.proxyPassword ONLY, with no http.* fallback,
      # even when the host came from the http.* pair (CFG-24; the chapter's own conformance case).
      Proxy.build(
        type: Proxy::Type::HTTP,
        host: host,
        port: port,
        username: configuration.raw_property(CRED_USER),
        password: configuration.raw_property(CRED_PASS),
        non_proxy_hosts: patterns,
      )
    end

    def from_environment(configuration)
      url = configuration.string(Configuration::Keys::HTTPS_PROXY) ||
            configuration.string(Configuration::Keys::HTTP_PROXY)
      return nil if url.nil? || url.strip.empty?

      url = url.strip
      # URL.parse! is deliberately not used: its contract is to raise, and CFG-24 forbids throwing.
      parts =
        begin
          ::URI::RFC3986_PARSER.split(url)
        rescue ::URI::InvalidURIError => error
          emit("proxy URL #{url.inspect} is not a URI: #{error.message}")
          return nil
        end

      scheme, userinfo, host, raw_port = parts

      # CFG-25's absent port is read off split[3] and NEVER off #port: parse("http://h").port is
      # already 80 by the time it is read, so a resolver built on #port passes for "http://h:8080"
      # AND for "http://h" -- resolving the second to 80, the exact behaviour CFG-25 forbids.
      if raw_port.nil?
        emit("proxy URL #{url.inspect} has no explicit port; CFG-25 forbids defaulting to 80/443")
        return nil
      end

      port = parse_port(raw_port)
      unless port
        emit("proxy port in #{url.inspect} is outside 0..65535: #{raw_port.inspect}")
        return nil
      end
      if host.nil? || host.empty?
        emit("proxy URL #{url.inspect} has no host")
        return nil
      end

      patterns, bypass_all = non_proxy_hosts(configuration)
      return nil if bypass_all

      username, password = credentials(userinfo)

      Proxy.build(
        type: scheme_type(scheme),
        host: host,
        port: port,
        username: username,
        password: password,
        non_proxy_hosts: patterns,
      )
    end

    # Resolved at call time, not into a frozen table at load time: this file must not name
    # Proxy::Type at require time, because type.rb reopens `class Proxy` and only proxy.rb may
    # declare it. `downcase` with no argument, everywhere (Dexpace/NoLocaleCaseFold).
    def scheme_type(scheme)
      case scheme.to_s.downcase
      when "socks5" then Proxy::Type::SOCKS5
      when "socks4" then Proxy::Type::SOCKS4
      else Proxy::Type::HTTP
      end
    end

    # Userinfo arrives percent-encoded and split() does not decode it. decode_uri_component and
    # never RFC3986_PARSER.unescape, which prints an obsolescence warning on 3.4.10 against a gate
    # set that fails on warnings; and never decode_www_form_component, which turns a "+" in a
    # password into a space.
    def credentials(userinfo)
      return [nil, nil] if userinfo.nil? || userinfo.empty?

      user, password = userinfo.split(":", 2)
      [
        user.nil? || user.empty? ? nil : ::URI.decode_uri_component(user),
        password.nil? ? nil : ::URI.decode_uri_component(password),
      ]
    end

    # CFG-26: the system property (pipe-separated) wins over the environment variable
    # (comma-separated), and the winner does not depend on which source supplied the host -- a
    # proxy resolved from HTTPS_PROXY still honours http.nonProxyHosts.
    def non_proxy_hosts(configuration)
      raw = configuration.raw_property(NON_PROXY_PROP)
      return split_non_proxy(raw, "|") unless raw.nil? || raw.empty?

      split_non_proxy(configuration.string(Configuration::Keys::NO_PROXY), ",")
    end

    def parse_port(raw)
      return nil if raw.nil? || raw.to_s.strip.empty?

      # Kernel.Integer and never ::Integer(...), which is a constant reference and a SyntaxError.
      # Base 10 explicit, and the 0..65535 range check is 5a's: parse("http://h:70000").port is
      # 70000 with no complaint from the parser.
      value = ::Kernel.Integer(raw.to_s.strip, 10, exception: false)
      return nil if value.nil? || value.negative? || value > 65_535

      value
    end

    # CFG-26's observable order, in this order: split on an unescaped separator -> drop empty
    # fragments (BEFORE unescape and trim) -> unescape -> trim. Verified against the chapter's own
    # conformance outputs: "a\|b|c" -> ["a|b", "c"], "a\,b,c" -> ["a,b", "c"], "a||c" -> ["a", "c"],
    # "a| |c" -> ["a", "", "c"].
    #
    # The -1 limit is NOT load-bearing -- the very next step drops empty fields anyway -- and stays
    # because it makes this the literal `split` half of CFG-26's stated order rather than a
    # pre-filtered one.
    def split_non_proxy(raw, separator)
      return [[], false] if raw.nil? || raw.to_s.empty?

      pattern = ::Regexp.new("(?<!\\\\)#{::Regexp.escape(separator)}", timeout: 1.0)
      tokens = raw.to_s.split(pattern, -1)
                  .reject(&:empty?)
                  .map { |token| token.gsub("\\#{separator}", separator).strip }

      # CFG-27: exactly one bare "*" is bypass-all and resolution returns nil, carried by the flag
      # and never by a literal "*" entry. A "*" inside a multi-entry list stays a normal any-host
      # glob, which is why this compares the whole token list and not `tokens.include?("*")`.
      return [[], true] if tokens == ["*"]

      # A whitespace-only fragment survives CFG-26's order as an EMPTY token, and an empty glob is
      # not a host pattern -- HostPattern.of("") raises. It is dropped here, after the order the
      # requirement fixes has been observed, rather than by removing it from the split.
      [tokens.reject(&:empty?).map { |token| Proxy::HostPattern.of(token) }, false]
    end

    # P5-8: Kernel#warn today, following phase 2's P2-6 verbatim. 5b adds an http.instrumentation.*
    # event BESIDE this and removes neither.
    def emit(message)
      ::Kernel.warn("[dexpace] #{message}")
    end
  end

  private_constant :ProxyResolution
end
```


- [ ] **Step 4: Add one line to `gems/dexpace-core/sig/dexpace/proxy.rbs`**

Task 14 wrote the rest of this file; Task 15 adds only:

```rbs
    def self.resolve: (?Configuration configuration) -> Proxy?
```

- [ ] **Step 5: `lib/dexpace.rb` is unchanged by this task**

Task 14 already added `require_relative "dexpace/proxy"`, and Step 3's third trailing require pulls
`proxy/resolution` in behind it. `proxy/resolution.rb` never appears in `lib/dexpace.rb` itself: it
is a `private_constant` with no `sig/` mirror and no test mirror, and its behaviour is asserted at
its call site, `Proxy.resolve`.

- [ ] **Step 6: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/proxy_test.rb`
Expected: PASS with 14 runs, 0 failures, 0 errors.

---

## Task 16: Final Wiring, Surface Snapshot, RBS Baseline, Checklist, and Register Updates

**Requirement IDs:** `NFR-3`, `NFR-4`, `NFR-11`, `NFR-13`, `NFR-14`, and all 38 `CFG` IDs.
**Design:** "Module layout"; "Deviation Ledger (P5-1 through P5-15)"; "Deferral-register sweep"; "The findings filed against docs/open-items.md".

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Regenerate: `test/fixtures/surface/dexpace-core.txt` (**repository root**, not under the gem — phase 0 put the six manifests at `test/fixtures/surface/*.txt`)
- Create: `gems/dexpace-core/test/dexpace/close_quietly_cfg21_test.rb`
- Create: `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-checklist.md`
- Register edits: `docs/deferred-items.md` (`DEF-28` and `DEF-36` to `picked-up`; **`DEF-34` untouched**), `docs/open-items.md` (nothing to write)
- Update: `CLAUDE.md`'s two claims sentences

- [ ] **Step 1: Verify the final require list in `gems/dexpace-core/lib/dexpace.rb`**

5a adds **eleven** lines, not sixteen: `configuration/keys`, `configuration/sources`,
`configuration/parsers`, `proxy/type`, `proxy/host_pattern` and `proxy/resolution` are pulled in by
`configuration.rb` and `proxy.rb`, which own their load order for the superclass reason Tasks 9 and
14 state.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# ... (phases 0 through 4c requires, unchanged) ...

# Configuration, the clock, the proxy model and the free-standing utilities (phase 5a).
# `time` is required by http_date.rb and `uri` by proxy/resolution.rb, each in the file that uses
# it; the allowlist does not grow (R5).
require_relative "dexpace/build_info"
require_relative "dexpace/uuid"
require_relative "dexpace/retryability"
require_relative "dexpace/deep_value"
require_relative "dexpace/http_date"
require_relative "dexpace/clock"
require_relative "dexpace/async/delay"
require_relative "dexpace/configuration"   # pulls in configuration/keys and configuration/sources
require_relative "dexpace/configuration/parsers"
require_relative "dexpace/config"
require_relative "dexpace/proxy"           # pulls in proxy/type, host_pattern and resolution
```

Then assert the require audit still passes on the two library requires and nothing else:

```bash
grep -rn '^\s*require "' gems/dexpace-core/lib   # expect only allowlisted entries; 5a adds time, uri
grep -rn 'SecureRandom\|require "securerandom"\|require "logger"\|require "base64"' gems/dexpace-core/lib
```

The second grep must come back empty: `CFG-32`'s non-cryptographic path and `XCUT-21`'s CSPRNG stay
two code paths (boundary 8), and that is checkable by text.

- [ ] **Step 2: Write the one test `CFG-21` needs, which phase 2 already satisfies**

5a adds no code for `CFG-21`; it adds the citation, so the checklist row has a test to name.

Write `gems/dexpace-core/test/dexpace/close_quietly_cfg21_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# CFG-21: a cancelled interruptible task whose result is a closeable resource must have that result
# closed on the discard path, best-effort, and the close helper must be null-safe. Phase 2 shipped
# both halves -- Dexpace.close_quietly and Completer#fulfil's lost-race close (SEAM-30) -- so this
# suite asserts them rather than adding code.
class DexpaceCloseQuietlyCFG21Test < DexpaceTestCase
  class CountingResource
    attr_reader :closes

    def initialize(raising: false)
      @closes = 0
      @raising = raising
    end

    def close
      @closes += 1
      raise ::IOError, "close failed" if @raising

      nil
    end
  end

  test "CFG-21: the best-effort close helper is null-safe" do
    assert_nil(Dexpace.close_quietly(nil))
  end

  test "CFG-21: close failures on the discard path are swallowed" do
    resource = CountingResource.new(raising: true)
    Dexpace.close_quietly(resource)
    assert_equal(1, resource.closes)
  end

  test "CFG-21: a fulfil that loses the race to a cancel closes the response exactly once" do
    completer = Dexpace::Async::Completer.new
    resource = CountingResource.new

    completer.future.cancel(:too_late)
    refute(completer.fulfil(resource))

    assert_equal(1, resource.closes)
    assert_predicate(completer.future, :cancelled?)
  end
end
```

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/close_quietly_cfg21_test.rb`
Expected: PASS with 3 runs, 0 failures, 0 errors.

- [ ] **Step 3: Regenerate the runtime surface snapshot and the RBS baseline**

```bash
bundle exec rbs validate
bundle exec steep check
bundle exec rake surface:regenerate
```

The manifest is `test/fixtures/surface/dexpace-core.txt` at the **repository root**. Regeneration is
a deliberate, reviewed act and happens once, here — never as a way to silence an unintended break.
Read the diff and confirm that every added line is a name `P5-1` or `P5-2` already accounts for, and
that nothing else appeared: the private constants `ConfigParsers`, `ProxyResolution` and `DeepValue`,
`Proxy::Type::ALL`, `Configuration::Sources`' internals and `Async::ELAPSED` must all be absent.

- [ ] **Step 4: Create the checklist**

`docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-checklist.md`, one row per ID, using
the roadmap's ✅ / 🚫 / ⏳ / N/A legend verbatim. The dispositions, which must match the design's
scope table exactly — **35 implemented, `CFG-20` and `CFG-34` partially satisfied, `CFG-35` split**:

- `CFG-1`–`CFG-18`: ✅ (Tasks 6, 7, 9, 10, 11, 12)
- `CFG-19`: ✅ — satisfied **by construction**, no `unwrap` method ships (`P5-11`; Task 8)
- `CFG-20`: ⏳, and the row is the one the design fixes, copied verbatim rather than paraphrased:
  > `| CFG-20 | SHOULD | ⏳ | DEF-18, OI-22 | Three of four clauses met: the non-interrupting cancel is Future#cancel (phase 2); the queued-or-finished clause holds because no interrupt is ever delivered; the rejected-submission clause is Completer#fail's routing. The fourth — cancel-with-interrupt — is ASYNC-3's mechanism under a second ID and is forbidden by §8.3; DEF-18 carries the mechanism and does not cite CFG-20, which is what OI-22 records. |`
- `CFG-21`: ✅ (phase 2's code, this task's test)
- `CFG-22`–`CFG-33`: ✅ (Tasks 3, 5, 10, 11, 14, 15)
- `CFG-34`: ⏳ — NaN, signed-zero and element-kind distinctness implemented; the **container-kind**
  clause recorded inapplicable per §11.15, and the inapplicability **not** extended (`P5-14`; Task 10)
- `CFG-35`: ⏳ — the status classifier ships as `XCUT-5`'s single shared object; the **throwable**
  half is `DEF-40` (`R1`; Task 4)
- `CFG-36`–`CFG-38`: ✅ (Tasks 2, 11)
- `XCUT-5`: ✅ (Task 4) · `DEF-28`: picked up (Task 8) · `DEF-36`: picked up (Task 13) ·
  `DEF-34`: ceiling half supplied (Task 13), row not edited — see Step 5

A `CFG` ID in scope with no row is the single failure this repository's process exists to prevent.

- [ ] **Step 5: Edit the registers — two rows, and no more**

- `DEF-28` → `Status: picked-up (<date>, phase 5a)`.
- `DEF-36` → `Status: picked-up (<date>, phase 5a)`.
- **`DEF-34` is NOT edited.** 5a supplies the ceiling half only; the two logging-body wirings need
  `5b`'s enablement setting, and the charter puts the row's edit on whichever of `5a`/`5b` lands
  **second**. 5a leads, so `5b` edits it.
- **`DEF-40` and `OI-24` already exist** — filed by the 5a design, verified present at
  `docs/deferred-items.md` and `docs/open-items.md`. **Do not re-file, re-number or duplicate
  either**; both 4b's and 4c's plans made exactly that mistake. Confirm with:
  `grep -n '^### DEF-40 \|^### OI-24 ' docs/deferred-items.md docs/open-items.md`
- No `P5-<n>`, `DEF-<n>` or `OI-<n>` is invented by this plan. The ledger is `P5-1`–`P5-15` and it
  is the 5a **design**'s; a sixteenth deviation found at execution time is appended there as `P5-16`
  and consolidated into design §10, never renumbered and never duplicated into a second list.

- [ ] **Step 6: Update `CLAUDE.md`'s claims sentences**

The `claims` check compares each stated count against the live tree, so **both** sentences move:

- the phase-directory count goes from **five to six**, and the sentence gains a `phase5/` clause:
  "There are six phase directories under `docs/work/*/`; … `phase5/` carries its segmentation
  design, `docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md`, and one sub-phase
  directory, `phase5/phase5a/`, holding a design, a plan and a checklist."
- the trailing "Every checklist is still to be written at execution time" is no longer true once
  Step 4 lands, and must be narrowed to the phases that still have none.
- the gems sentence changes only if this sub-phase is the first to create `gems/` — it is not.

**Never rewrite the prose to satisfy the check.** Derive the counts, then say what is true.

- [ ] **Step 7: Run the full gate set and the housekeeping probe**

```bash
bundle exec rake
ruby .claude/skills/housekeeping/probe.rb
```

Expected: all gates green, and the probe reporting nothing. Fix what the probe reports before
handing over; `--only links,citations` after any document move.

---

## Self-review against the design

### What this plan has and has not established

Stated first, because the table below is a mapping and not a proof.

- **One interpreter.** Every fence and every fact here was exercised on **3.4.10 only**; 3.2.11 and
  4.0.6 are not installed on the authoring machine and Task 1 is an instruction to install and run
  them, not a record of having done so. Nothing below claims a range.
- **The substantial fences were extracted and run, and this says which.** `probe_scheduler.rb` (both
  the timeout and the cancel-wake paths, under a real `Fiber.schedule`), `deep_value.rb` (NaN pair,
  signed zeros, element kinds, null-safety, the cycle case, the pair-guard false positive and the
  hash-stack unwind), `proxy/type.rb`, `proxy/host_pattern.rb` (including the trailing-newline row
  and `#with`), and `proxy/resolution.rb` + `proxy.rb` driven end-to-end against a stub
  `Configuration` — every `CFG-24`–`CFG-27` assertion in Task 15 passing. Every Ruby fence in this
  document was checked with `ruby -c`. **Not run:** `configuration.rb`, `config.rb`, `clock.rb`,
  `async/delay.rb` and the `Future`/`Completer` edits, which need phase 1's `Model` and phase 2's
  async pivot rather than a stub; their APIs were read off phase 1's and phase 2's shipped bodies
  and are quoted where they are used.
- **Four conflicts and corrections this plan is carrying**, none of which it may resolve alone:
  1. `CFG-18`'s future settles with `true`, not `nil` — `SEAM-16` makes a nil-response `Settlement`
     unconstructible, so the design's "settled with a `nil` value" is not buildable (Task 7).
  2. The design's verified fact 7 names `"nan".to_f` as a NaN; it is `0.0`. The conclusion survives,
     the witness does not, and this plan uses `0.0/0.0` and `-(0.0/0.0)`.
  3. Whether `strftime`'s `%a`/`%b` are locale-independent is **unverified** and Task 5 must settle
     it before `P5-12`'s formatting half can be called sound.
  4. `CFG-26`'s "a whitespace-only fragment is retained as an empty token" is observed through
     `split_non_proxy`'s token order and then dropped before compilation, because
     `HostPattern.of("")` is not a host pattern. The requirement fixes the order, not what a
     consumer does with an empty token; this is the reading, stated rather than assumed.
- **No `P5-`, `DEF-` or `OI-` number is invented here.** The ledger is the design's `P5-1`–`P5-15`;
  `DEF-40` and `OI-24` exist already and Task 16 verifies rather than re-files them; `DEF-34`'s row
  is not edited.

### Requirement ID Mapping

Thirty-eight `CFG` IDs, every one with a row: **35 ✅, three ⏳** (`CFG-20`, `CFG-34`, `CFG-35`),
matching the design's scope table exactly. Nothing in `CFG` is deferred outright.

| Requirement ID | Level | Disposition / Task | Summary |
|---|---|---|---|
| `CFG-1` | MUST | Task 11 | 4-tier precedence: override > exact env > normalized property > default |
| `CFG-2` | MUST | Task 11 | Empty env var falls through; empty override resolves |
| `CFG-3` | MUST | Task 11 | Normalised property key: downcased with dots replacing underscores |
| `CFG-4` | MUST | Task 11 | `raw_property` lookup by exact name without normalisation |
| `CFG-5` | MUST | Tasks 10, 11 | Base 10 integer parsing via `ConfigParsers` |
| `CFG-6` | MUST | Tasks 10, 11 | Boolean parsing matching "true"/"false" case-insensitively |
| `CFG-7` | MUST | Tasks 10, 11 | Duration parsing (ISO-8601, unit, bare ms) returning Float seconds (`P5-4`) |
| `CFG-8` | MUST | Task 11 | Immutability and defensive copying via `Model.own` |
| `CFG-9` | MUST | Task 11 | Copy-on-write `derive` with shared source seams |
| `CFG-10` | MUST | Task 11 | Builder `remove` drops override only, no tombstone |
| `CFG-11` | MUST | ✅ Tasks 1, 9 | Substitutable seams `Sources::ENVIRONMENT`, `NONE`, `from_hash`; `FakeSource` is what makes every `CFG-1`–`CFG-10` case hermetic |
| `CFG-12` | SHOULD | Task 11 | Builder single-threaded by design (no mutex) |
| `CFG-13` | SHOULD | Task 12 | `Dexpace.configure`, `.configuration`, `.reset_config!` slot |
| `CFG-14` | SHOULD | Task 9 | Well-known key constants in `Configuration::Keys` |
| `CFG-15` | MUST | Tasks 1, 6 | `Clock` seam: now, monotonic, sleep; `Clock::SYSTEM` default |
| `CFG-16` | MUST | Task 6 | Monotonic elapsed-time counter in seconds |
| `CFG-17` | MUST | Task 6 | Sleep negative rejection, zero duration, cancellation re-assertion |
| `CFG-18` | SHOULD | Tasks 1, 7 | `Async.delay` non-blocking under scheduler; `SeamError` without (`P5-9`) |
| `CFG-19` | SHOULD | ✅ Task 8 | Cause unwrapping satisfied **by construction**: no `unwrap` method ships (`P5-11`); asserted with `assert_same` on the error object |
| `CFG-20` | SHOULD | **⏳** Tasks 8, 16 | Three of four clauses met; cancel-with-interrupt is `ASYNC-3`'s mechanism under a second ID and is forbidden by §8.3. Row cites `DEF-18` **and** `OI-22`, verbatim from the design (`R7`). 5a files no fourth deferral |
| `CFG-21` | MUST | ✅ Task 16 | Discard-path close and its null-safety are phase 2's `Dexpace.close_quietly` and `Completer#fulfil`'s lost-race close. 5a adds no code and adds the test the row names |
| `CFG-22` | MUST | Tasks 14, 15 | `Proxy` and `Proxy::Type`; credential masking in `to_s` and `inspect` (`P5-7`) |
| `CFG-23` | MUST | Task 14 | `HostPattern` glob matching with `\A...\z`, per-pattern timeout |
| `CFG-24` | MUST | Task 15 | Proxy precedence: sysprop > env URL; non-throwing resolution |
| `CFG-25` | MUST | Task 15 | Proxy port explicit 0..65535; absent port invalid |
| `CFG-26` | MUST | Task 15 | Non-proxy hosts split with negative lookbehind, unescape, trim |
| `CFG-27` | MUST | Tasks 14, 15 | `NO_PROXY="*"` bypass all resolves to nil; multi-entry globs |
| `CFG-28` | MAY | Task 15 | Explicit proxy resolution only (`Proxy.resolve`), no implicit read |
| `CFG-29` | MUST | Task 5 | RFC 1123 date formatting via `Time#httpdate` |
| `CFG-30` | MUST | Task 5 | RFC 1123 date parsing tolerant to 4 zone tokens and lowercase month |
| `CFG-31` | MUST | Task 5 | RFC 1123 date parsing strict day-of-month, comma check, reject RFC 850 |
| `CFG-32` | MUST | Task 3 | Non-crypto UUID v4 via per-thread PRNG in `Thread.current[]` (`P5-13`) |
| `CFG-33` | MUST | ✅ Tasks 10, 11 | `DeepValue` null handling (null hashes to zero), byte-array fallback, pair-keyed cycle guard and unwinding hash stack (`P5-15`), hash/equality consistency |
| `CFG-34` | MUST | **⏳** Tasks 10, 11 | NaN equality with a folded hash seed, signed-zero inequality with distinct seeds, element-kind distinctness (`P5-14`). The **container-kind** clause is recorded inapplicable per §11.15 and the inapplicability is not extended |
| `CFG-35` | SHOULD | **⏳** Task 4 | The **status** half ships as `XCUT-5`'s single shared object. The **throwable** half is `DEF-40` — no stub and no predicate returning `false`, because a wrong answer under an `NFR-4` lock can only be changed by breaking (`R1`) |
| `CFG-36` | SHOULD | Task 2 | `BuildInfo` SDK version and host runtime identity without allowlist growth (`R5`) |
| `CFG-37` | MUST | Tasks 11, 15 | Fail-fast argument validations via `Model.required!` |
| `CFG-38` | MUST | Task 11 | Typed accessors read whole chain (overrides, env, properties) |

### The non-`CFG` obligations 5a carries without owning a new ID

| Obligation | Where | Note |
|---|---|---|
| `XCUT-5` — the single shared status classifier the baked flag is computed from | Task 4 | `Retryability.retryable_status?`, a predicate and **not** an exposed set: `XCUT-7`'s configurable set is a different object and publishing this one as a second enumerable constant beside it is how the two get confused |
| `DEF-28` — the `deadline:` keyword and the monotonic clock behind it | Tasks 6, 8 | `Future#value` / `#wait` / `Completer#await` gain `deadline:` and `clock:`; `Clock#monotonic` is the scale and `Clock.deadline_in` names it. Both additions widen, which `NFR-4`'s "disappears or narrows" lock permits. Row moves to `picked-up` |
| `DEF-36` — a configuration source for `ContextStore`'s cap | Task 13 | One wiring, no signature change. Row moves to `picked-up` |
| `DEF-34` — the **ceiling** half only | Task 13 | `IO.max_materialized_bytes` reads `Keys::MAX_MATERIALIZED_BYTES`; no `ceiling:` keyword anywhere, so phase 3's boundary 8 is untouched. **The row is not edited** — the other two wirings need `5b`'s enablement setting and `5b` lands second |
| `CFG-14`'s well-known key constants, which `RETRY-12` and `OBS-35` reference without owning | Task 9 | `Keys::MAX_RETRY_ATTEMPTS` is the **name** only; the 200 ms / ×2 / 8 s / 0.2 / 3-sends values are phase 6's. `Keys::LOG_LEVEL` is **a published name a caller may pass, never a default any resolver falls back to** — `OBS-35`'s embedded MUST, which `5b` meets by taking its key as a required argument |
| `DEF-40`, `OI-24` | Task 16 | Filed by the **design**. Verified present; not re-filed, not re-numbered |
| `DEF-18`, `OI-22`, `DEF-38`, `DEF-35`, `DEF-27`, `DEF-30`, `DEF-3` | — | Untouched. 5a cites `DEF-18`/`OI-22` from `CFG-20`'s row, changes `DEF-38`'s *source* without editing its text, unblocks `DEF-35` by building `Clock#sleep`, adds no `close_quietly` call site, adds no fourth registry, and does not grow the require allowlist |

### Deviation Ledger Mapping

| Deviation | Description | Task |
|---|---|---|
| `P5-1` | Public constants not named by §8.2 | Task 16 |
| `P5-2` | Public methods not named by §8.2 | Task 16 |
| `P5-3` | `Sources::ENVIRONMENT` instead of `Sources::ENV` | Task 9 |
| `P5-4` | `Configuration#duration` returns `Float` seconds | Tasks 10, 11 |
| `P5-5` | `Proxy` host and port instead of socket address | Task 15 |
| `P5-6` | No Ractor shareability claim for `Configuration` | Task 11 |
| `P5-7` | `Proxy` overrides both `#to_s` and `#inspect` | Task 15 |
| `P5-8` | Proxy warning uses `Kernel#warn` | Task 15 |
| `P5-9` | `Async.delay` raises `SeamError` without scheduler | Task 7 |
| `P5-10` | `Async.delay` on `Async` module, not `Clock` | Task 7 |
| `P5-11` | `CFG-19` satisfied by construction (no `unwrap`) | Task 8 |
| `P5-12` | `HTTPDate` owned parse grammar, `Time#httpdate` format | Task 5 |
| `P5-13` | `UUID` memoised in `Thread.current[]` | Task 3 |
| `P5-14` | `CFG-34` distinct array kinds as element-kind distinctness | Task 10 |
| `P5-15` | `DeepValue` cycle safety via identity visited set | Task 10 |
