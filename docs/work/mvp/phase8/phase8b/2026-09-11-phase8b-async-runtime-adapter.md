# Phase 8b — Async Runtime Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `dexpace-async-thread` in full: a fixed-size `::Thread` pool over a bounded
`::Thread::SizedQueue` that supplies the first real implementation of `SEAM-18`'s caller-supplied
executor duck type, settles phase 2's core-owned pivot from a real producer for the first time,
carries the `ASYNC-15`–`ASYNC-17` lifecycle over `Dexpace::Closeable`, performs the
`ASYNC-8`–`ASYNC-12` diagnostic hop over `Fiber[]`, and ships `ASYNC-18`'s scheduled delay. Nineteen
requirement IDs, all `ASYNC` (`ASYNC-1`–`ASYNC-5`, `ASYNC-7`–`ASYNC-20`), plus two cross-reference
rows with no budget line (`PIPE-33`, `ASYNC-6`). `ASYNC-3` stays ⏳ (`DEF-18`, design §10.5) and
`ASYNC-4` stays N/A (vacuous, §10.5, no register row); no deferral is filed by this plan.

**Architecture:** One class, `Dexpace::Async::Thread::Pool`, with a private `Job` (frozen `Data`)
crossing the thread boundary and one `Thread.new` call in the whole gem. The worker loop clears its
*inherited* fiber storage once at thread start (`R8`/`P8-20`) so phase 5b's `Diagnostics.with`
*replaces* rather than *merges onto* whatever the pool creator's fiber happened to hold, then loops
`while (job = @queue.pop)` over a bounded `::Thread::SizedQueue`, installing each job's captured
snapshot and rescuing `::Exception` so no bad task ever shrinks the pool (`P8-22`). `#post` never
blocks the caller — a full queue is `RejectedError`, a closed pool is `Dexpace::ClosedError`, both
routed to `Completer#fail` by phase 2's bridge (`P8-23`). `#close` closes the queue (stop, drain),
stops one lazily created `Timer` thread shared by every outstanding `#delay`, and emits
`Events::INSTRUMENTATION_SHUTDOWN` exactly once (`DEF-31`, closed here). The version-skew assertion
is made directly in the entry file rather than through a seam registry, because `SEAM-18` requires
the executor to be caller-supplied with no default and there is no executor registry to register
into (`P2-1`, `P8-21`).

**Tech Stack:** Ruby 3.2–4.0 (authored on 3.4.10), Minitest, RBS + Steep, RuboCop with phase 0's
five custom cops plus phase 2's `Dexpace/QualifiedCoreConstant` (`P2-8`, extended repository-wide by
`P3-7`) — six by phase 8, of which three reach this gem and `Dexpace/NoThreadInterrupt` has
everything to bite here — SimpleCov, YARD.
`dexpace-async-thread` declares `dexpace-core` and **nothing else** — the gem's `NFR-2` budget is
spent on nothing, by design (design §2.1's charter sentence).

**Spec:** `docs/work/mvp/phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter-design.md`, under
the charter `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`.
`docs/product-spec/18-asynchronous-runtime-adapter-contract.md` is the normative chapter for all 19
owned IDs (plus `PIPE-33`, phase 4's, and `ASYNC-6`, `8c`'s); appendix C
(`:589-608`) is used for the modal level, the chapter's own `*Conformance:*` clauses (which appendix
C drops) for the exact assertion text six decisions below turn on.

---

## Global Constraints

- **`dexpace-async-thread` gains no dependency.** The gemspec already declares `dexpace-core` and
  nothing else (`P0-9`); this plan adds no `add_dependency` line and no `rbs_collection.yaml` row.
- **The forbidden three — `Timeout.timeout`, `Thread#raise`, `Thread#kill` — appear nowhere in this
  gem.** `Dexpace/NoThreadInterrupt` also bans `Thread#terminate` and `Thread#exit`. Every deadline
  in this plan is an explicit value checked against `clock.monotonic`, never a signal.
- **`::Thread::Mutex` is held nowhere in this plan across a suspension point.** There are exactly
  two mutexes in the finished gem — `Dexpace::Closeable`'s (phase 2's, inherited, held across the
  `@closed` flip only) and `Timer`'s (held across a list mutation and the lazy thread creation,
  never across `::Thread::Queue#pop(timeout:)`). Every task that touches either states what it is
  not held across.
- **Every reference to a core primitive `Dexpace::Async` shadows is fully qualified**
  (`Dexpace/QualifiedCoreConstant`): `::Thread`, `::Thread::Queue`, `::Thread::SizedQueue`,
  `::Thread::Mutex`, `::Thread::ConditionVariable`, `::Fiber`, `::Process`, `::Exception`,
  `::StandardError`, `::ThreadError`, `::ClosedQueueError`, `::ArgumentError`, `::Data`,
  `::Array`, `::Hash`, `::Numeric`, `::Integer`, `::String`. Inside `module Dexpace; module Async;
  module Thread`, a bare `Thread` resolves to **this module**, not `::Thread` (verified fact 13 of
  the design) — every task's code samples below already write `::Thread` throughout, and the grep
  test in Task 4 makes the omission mechanical rather than a matter of care.
- **`Fiber[:key]`, never `Thread.current[:key]`.** `Thread.current[]` appears nowhere in this gem;
  Task 4's grep test asserts it by name, because it is the call a Ruby author reaches for first and
  the failure is silent.
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`), including every test
  support double.
- **No bare stdlib error escapes `lib/`.** `::ThreadError` (a full non-blocking push) and
  `::ClosedQueueError` (a closed queue) are both translated to `Dexpace::Async::Thread::RejectedError`
  or `Dexpace::ClosedError` at the one call site that can raise them (`#post`), never left to
  propagate — `P6-4`'s obligation, met by a gem that is not a transport.
- **`Diagnostics.capture`/`.with` are phase 5b's, called and never reimplemented.** This plan writes
  exactly one new line against fiber storage — the worker's one-time inherited-storage clear
  (`::Fiber.current.storage&.each_key { |k| ::Fiber[k] = nil }`) — and calls `::Fiber#storage=`
  nowhere, so `OI-13`'s warned setter is a call this gem never makes.
- **`Dexpace::Instrumentation::Logger` shadows the stdlib `Logger`.** Every reference in this plan
  is fully qualified (`Dexpace::Instrumentation::Logger`), never a bare `Logger`.
- **Domain model construction pattern, applied to a mutable class rather than a `Data`.** `Pool` is
  not a `Data` — it holds threads and is mutable by nature (`data-modeling/3e37c086`) — but it still
  gets `private_class_method :new` plus a validating `.build`, and every validation failure is
  `Dexpace::InvalidArgumentError` naming the offending keyword.
- **No test in this plan sleeps to wait.** Every wait is a condition — a `::Thread::Queue` pop, a
  bounded `Thread#join`, a `Future#value`, or a deadline-bounded `::Thread.pass` loop on a thread's
  own `#status`. The three places a real duration is unavoidable (a delay's interval, the shutdown
  budget's expiry, the timeout-versus-close disambiguation) use a small interval with a **lower**
  bound and no upper bound, and the budget's expiry additionally gets a fake-clock test that
  exercises the timed-out branch with no waiting at all. The only `Kernel#sleep` anywhere in this
  plan is inside `ProbeScheduler`'s own run loop, where it *is* the fixture's timer wheel and no
  assertion depends on its duration. A `sleep` that decides whether an assertion holds is a flake on
  a loaded machine and a false pass on a fast one.
- **This plan drives its own test doubles, never `gems/dexpace-core/test/support/`.** See
  *Discrepancies found against the design* below for the one place this plan's file list corrects a
  premise the segmentation charter (not the 8b design) states.
- **Formatting:** double quotes, 2-space indentation, 100 columns, `consistent_comma` trailing
  commas.

### Commands

Only commands phase 0's plan actually defines.

```bash
bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread_test.rb        # one suite
(cd gems/dexpace-async-thread && bundle exec rake test)                                # the gem's own
bundle exec rake test:gems                                                            # all six gems' smoke suites
bundle exec rake test:gates                                                           # the repository's gate suites
bundle exec rake                                                                      # the default task: all seventeen gates
bundle exec rake rubocop
bundle exec rake rbs:validate steep
bundle exec rake gates:gemspec_audit
bundle exec rake gates:require_allowlist
bundle exec rake gates:clean_bundle
bundle exec rake gates:rbs_surface
bundle exec rake gates:sig_diff
bundle exec rake gates:surface_snapshot
bundle exec rake surface:regenerate                                                   # deliberate; Task 11 only
bundle exec rake gates:single_instance
bundle exec rake gates:versions
bundle exec rake gates:reproducible
bundle exec rake yard bundler_audit
ruby .claude/skills/housekeeping/probe.rb                                             # Task 13, read-only
```

### What was verified during planning

**One interpreter, and this plan says so before it says anything else.** Only Ruby **3.4.10**
(`ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]`, `/usr/bin/ruby`) is installed
on the planning machine — `mise ls` lists no ruby, `~/.rbenv` does not exist. **The 3.2 and 4.0
columns have not been run for anything below; Task 1 installs both and re-runs every fact this plan
leans on before any implementation task begins.**

Every fact the design measured (its 20 numbered facts) is inherited as-is and not re-derived here;
this plan additionally verified, directly, while drafting the tasks below (all on 3.4.10, `ruby -w`,
zero warnings unless noted):

1. **A non-blocking `push` on a full `::Thread::SizedQueue` raises `ThreadError: queue full`**, and
   `push(x, timeout: 0.02)` on a full queue returns `nil` rather than raising. Confirms `#post`'s
   translation site has exactly one exception to catch for the full-queue case.
   *Command:* `ruby -w` over a five-line probe; `ThreadError: queue full` and `nil` respectively.
2. **A worker loop written as `while (job = @queue.pop) ... ensure @exits << SENTINEL end` drains
   correctly and posts its exit sentinel exactly once**, whether the queue closes with work still
   queued or empty. Confirms Task 4's worker shape and Task 6's drain-loop assumption.
   *Command:* `ruby -w` over an eleven-line probe; sentinel observed once per worker.
3. **`Proc.new` with no explicit block and no captured implicit block raises `ArgumentError: tried
   to create Proc object without a block` on 3.4.10** (removed since Ruby 3.0). `#post` must take
   its block as `&block`, never rely on an implicit `Proc.new` capture — a mistake the codebase has
   no precedent for, so this plan verified it directly rather than assuming.
   *Command:* `ruby -e` calling a method that does `Proc.new` with no block; raises as stated.
4. **The R8/R9 leak-and-fix pair reproduces exactly as design fact 7 and fact 8 describe, standalone
   (no core code, `Diagnostics.capture`/`.with` reimplemented verbatim from phase 5b's shipped
   source).** A pool built while `Fiber[:"trace.id"] = "POOL-BUILD-TIME"` and `Fiber[:tenant] =
   "assembly"` were set, driven by a worker with **no** clearing line and a caller snapshot of
   `{"trace.id" => "CALLER-A"}`, observed `{"trace.id": "CALLER-A", tenant: "assembly"}` inside
   `Diagnostics.with`. The **same** setup with the one-line clear
   (`::Fiber.current.storage&.each_key { |k| ::Fiber[k] = nil }`) at thread start observed exactly
   `{"trace.id": "CALLER-A"}`. A second run reused one worker across four tasks — context A, the
   worker's own context intact afterward, context B on the same worker, a task that **throws** with
   the worker's own (empty, post-clear) context intact after the throw, and an empty snapshot
   installing as `{}` and restoring to `{}` — all four correct, zero `Warning.warn` calls. This is
   Task 4's implementation and Task 5's test, run ahead of writing either.
   *Command:* `ruby -w` over the design's exact `Diagnostics.capture`/`.with` source plus the
   clearing line, in four scenarios.
5. **A `MiniTimer` prototype matching this plan's `Timer` (a mutex-guarded deadline-ordered
   `Array`, a `::Thread::Queue` used only as a wake signal, `pop(timeout: remaining)` against the
   nearest deadline, `stop` closing the wake queue and joining) fires two entries in deadline order
   on one thread and never fires a cancelled third**, and `Thread.list.size` returns to its
   pre-timer value after `stop`. Confirms `R11`'s implementation before Task 7 writes it.
   *Command:* `ruby -w` over a sixty-line probe; fired order `[:a, :b]`, cancelled entry never
   fired, `Thread.list.size` unchanged after `stop`.
6. **`Queue#pop(timeout: nil)` blocks indefinitely — identical to no `timeout:` argument at all —
   and still returns `nil` promptly when the queue is closed while blocked.** Confirms `Timer#run`'s
   `remaining = nil` branch (no entries scheduled) is safe and does not busy-loop.
   *Command:* `ruby -w`; a thread blocked on `pop(timeout: nil)` stays `"sleep"` for 100 ms then
   wakes on a push; a second thread blocked the same way wakes with `nil` when the queue is closed.
7. **A minimal `Fiber::Scheduler` needs `#block`, `#unblock`, `#kernel_sleep`, `#io_wait`, `#fiber`
   and `#close` to be accepted by `Fiber.set_scheduler` at all** (`io_wait`'s absence raises
   `ArgumentError: Scheduler must implement #io_wait` before anything else runs), and phase 5a's
   exact `ProbeScheduler` shape — parking a fiber in a `@waiting` hash keyed by deadline, waking it
   from `#unblock` or a `#close`-driven `run_loop` — correctly records `{block: 1, unblock: 1,
   kernel_sleep: 0}` for a fiber blocked on a `::Thread::Queue#pop` woken from another thread. This
   is the design's fact 15, re-run standalone before Task 1 copies the double into this gem's own
   `test/support/`, and it is why Task 1 copies phase 5a's exact class rather than writing a
   simpler one that turns out to be missing a required hook.
   *Command:* `ruby -w` over phase 5a's `ProbeScheduler` source, unmodified, driving one
   `Fiber.schedule` block through a queue pop and `Fiber.scheduler.close`.
8. **`::Thread::SizedQueue.new(0)` and `.new(-1)` both raise `ArgumentError: queue size must be
   positive`**, confirming `.build`'s own `size`/`queue_limit` validation runs first only so the
   message names the keyword — the primitive would reject an invalid bound anyway.
   *Command:* `ruby -w`; `ArgumentError: queue size must be positive` for both.
9. **`private_class_method :new` plus a validating `.build`, and `Data.define(:snapshot,
   :block).new(...).frozen?` is `true` with the `Hash` member frozen and the `Proc` member callable
   later**, confirming `Pool::Job`'s shape and the `.build`/`.new` split compile and behave as
   written before either is embedded in the real class.
   *Command:* `ruby -w`; `NoMethodError` on the private `.new`, `.build` succeeds, `job.frozen?` and
   `job.snapshot.frozen?` both `true`, `job.block.call` returns the expected value.

**What is conditional on the three-interpreter re-run, named rather than left to be discovered.**
Every fact above and every fact the design measured that this plan's tasks depend on is re-run on
3.2.11 and 4.0.6 in Task 1 before implementation begins; the design's own list (facts 5, 6, 7, 8, 10)
is inherited unchanged as the set this plan's `R8`/`R9` decisions are conditional on.

---

## Discrepancies found against the design

Two findings, both concrete and both resolved in this plan rather than left for the design's author
to discover at execution time; each is stated so the resolution can be reviewed and, if the design's
author prefers a different one, overridden without re-deriving the finding.

1. **The design's "requirable... with zero allowlisted names" claim for `require "dexpace"` does
   not hold against phase 0's `tools/require_allowlist.rb` as that plan documents it, and the fix is
   a one-line, out-of-band extension of an exemption that already exists for a sibling case.**
   The design states, as verified fact 1's consequence: "That is what makes
   `dexpace-async-thread`'s `lib/` requirable under phase 0's adapter require-allowlist audit with
   zero allowlisted names: the only `require` in the gem is `require "dexpace"`."
   `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates.md`'s `RequireAllowlist.reason_for`
   (Task 9) reads:
   ```ruby
   def reason_for(name, permitted)
     return nil if permitted.include?(name) || name.start_with?("dexpace/")
     return DENIED[name] if DENIED.key?(name)
     since = bundled_since[name.split("/").first]
     return "bundled since #{since}; a gem must declare it explicitly under Bundler." if since
     return nil if ALLOWED.include?(name)
     "not in the require allowlist. …"
   end
   ```
   and `third_party_for` explicitly **excludes** `"dexpace-core"` from `permitted`
   (`.reject { |dep| dep == "dexpace-core" }`), because that method exists to compute the *one
   third-party gem* an adapter's `NFR-2` budget spends, not to permit reaching into core. The only
   standing exemption for core is `name.start_with?("dexpace/")` — a **prefix with a trailing
   slash**, which does not match the bare string `"dexpace"` (`dexpace-core`'s own entry file is the
   one irregular case in the repository's gem-to-file mapping: `lib/dexpace.rb`, not
   `lib/dexpace/core.rb`). A standalone simulation of the documented algorithm confirms it:
   `reason_for("dexpace", [])` returns the "not in the require allowlist" string, not `nil`.
   **Adjudicated 2026-09-12 (verification pass): the plan is right, and the DESIGN was corrected.**
   Phase 0's source was re-read directly — the guard at
   `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates.md:2205-2206`,
   `third_party_for`'s `.reject { |dep| dep == "dexpace-core" }` at `:2220-2228`, `ALLOWED` at
   `:2131-2144` (no `"dexpace"`) and `DENIED` at `:2147-2161` (no `"dexpace"`) — so `reason_for`
   falls through to its closing string exactly as stated. The 8b design's verified fact 1 and its
   "From phase 0" bullet now carry the correction. **No `P8-<n>` row was opened**: widening a sibling
   phase's gate is a repair, not a departure from the reference contract, and the design's ledger
   preamble records that judgement rather than leaving it to be re-derived.
   *What this plan does about it:* Task 1 adds one alternative to that guard clause —
   `name == "dexpace" || name.start_with?("dexpace/")` — with a one-line comment naming
   `dexpace-core`'s irregular entry-file path as the reason the prefix-only form missed it, and a
   regression test asserting `RequireAllowlist.violations(ROOT)` stays empty on the real tree both
   before and after `dexpace-async-thread`'s entry file gains its `require "dexpace"` line. No prior
   adapter's `lib/` ever wrote that line (`dexpace-serde-json`'s entry file references
   `Dexpace::VERSION`/`Dexpace::Serde` bare, relying on load order, and never requires `"dexpace"`
   itself), which is why this is the first sub-phase to exercise the gap. *Why not the alternative of
   dropping `require "dexpace"` and matching that precedent instead:* the design's verified fact 1
   states the deliberate choice in these exact words and repeats it in the module-layout table; this
   plan honours the stated decision and repairs the one place it does not yet hold, rather than
   silently reverting to an unstated precedent. If the design's author prefers the alternative, the
   fix is to delete Task 1's one-line change and Task 2's `require "dexpace"` together — nothing
   else in this plan depends on which way it goes, because every other file in this gem loads
   `Dexpace::` constants only through the entry file's own load order regardless.
2. **Not a discrepancy after re-checking the evidence — a rationale the design left implicit, kept
   here because the next reader will ask the same question.** *Adjudicated 2026-09-12: neither
   document is wrong, and neither was corrected on this point.* The 8b design already prescribes the
   direct form in as many words — "the entry file compares `Dexpace::VERSION` against
   `CORE_REQUIREMENT` with `Gem::Requirement` at require time" — and `P8-21`'s own `Why` already
   names 7a's `P7-7` as the precedent for a require-time assertion in an adapter's entry file. What
   was missing is the reason the *other* available precedent does not govern, and one supporting
   fact: **`Gem::Version`/`Gem::Requirement` are constants, not a `require`**, so phase 0's
   require-allowlist audit — a text scan of `require`/`require_relative` lines
   (`…phase0…-scaffold-and-quality-gates.md:2163-2196`) — never sees them, and the fact that
   `rubygems` is not on `ALLOWED` is beside the point for a gem that writes no `require "rubygems"`.
   7a verified the same thing from the other side: "`Gem::Version` needs no `require` (verified)"
   (`docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization-design.md:1380`). The argument
   below stands as written. Phase 2's
   `Registry#assert_core_version!` hand-rolls its `~> M.N` comparison specifically because "`Gem` is
   undefined under `ruby --disable-gems`… and a library may not assume RubyGems is loaded" — a
   constraint that binds `dexpace-core` (which must work with no `Gemfile` and no Bundler at all)
   but does not bind an *adapter* gem, which is only ever loaded as an installed/bundled gem and is
   therefore always running under `bundle exec` (or an equivalent RubyGems-aware invocation), where
   `Gem::Version`/`Gem::Requirement` are already loaded transitively by `bundler/setup` before any
   gem's own code runs. Phase 7a's entry-file floor assertion for `dexpace-serde-json`
   (`docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization.md`, Task 13) uses
   `Gem::Version` directly, with no `require "rubygems"` line and no hand-rolled comparison. This
   plan's `P8-21` skew assertion follows phase 7a's precedent, not phase 2's: `Gem::Version`/
   `Gem::Requirement` used directly in `thread.rb`, unexplained by any `require`, because it is
   ambient under the `bundle exec` every gate and test in this repository already runs under. This
   is written out rather than left implicit because `P8-21` cites phase 2's `Registry` as spec-forced
   boundary 8's usual vehicle in the same paragraph that drops its comparison mechanism, and a
   phase-9 audit reading the two rows side by side will otherwise ask why one gem hand-rolls what
   another calls directly. The answer is the `--disable-gems` constraint, and it is core's alone.

---

## This plan's open questions, resolved

The design's six open questions, resolved with a concrete decision each.

1. **`QUEUE_DEPTH_PER_WORKER`'s exact value.** *Decision:* **8**, exactly as the design recommends,
   as a named, documented `Integer` constant. Not tuned against a benchmark: the number that matters
   is the caller's `size`, and a depth chosen against this machine's timing would read as measured
   when it is a burst-tolerance policy. The YARD block states the reasoning and the fact that it is
   a depth-per-worker, not an absolute capacity. Task 4.
2. **`DEFAULT_SHUTDOWN_TIMEOUT`'s exact value, and whether it should be required.** *Decision:*
   **`30.0` seconds, and a default rather than a required keyword.** The asymmetry with `size:` is
   deliberate and stated in the YARD: a wrong `size` is a starvation bug that persists for the
   pool's whole life, while a wrong `shutdown_timeout` costs at most one slow shutdown, and a
   required keyword on a close-time budget would make the common construction call three keywords
   long for a value most callers have no opinion about. The YARD names the transport's own read
   timeout as the value this should exceed. Task 4.
3. **The two `DEF-31` event field keys.** *Decision:* `"dexpace.executor.worker_count"` and
   `"dexpace.executor.drained"`, as `private_constant` frozen `String`s on `Pool`, exactly as the
   design recommends — private because `dexpace-conformance`'s eventual assertion is "close twice →
   one event" and needs only the event name, and a public field key would be an `NFR-4` lock with
   one reader inside the gem that owns it. Task 6.
4. **README versus YARD for `ASYNC-7`.** *Decision:* the README is the requirement's home (one
   `## Cancellation and in-flight work` section quoting the exact contrast sentence,
   `concurrency-and-async/74aee9a8`, plus the `ensure`-form example and a close-semantics table);
   `#post` and `#close`'s YARD blocks each carry a one-line cross-reference to it rather than
   restating it, because a caller reading `#post`'s signature in an editor is exactly the reader who
   needs to be told an in-flight blocking read runs to completion, and a YARD block that restates the
   whole section would be two sources for one rule. Task 13.
5. **The stub clock's shape.** *Decision:* a five-line `Dexpace::StubClock` in this gem's own
   `test/support/stub_clock.rb`, implementing exactly `#monotonic` (returning a settable, advanceable
   `Float`) and raising `NotImplementedError` from `#now` and `#sleep`, so a later edit that reaches
   for either fails loudly rather than silently using a stub never designed for it. Not shared with
   phase 5a's own clock double, which lives in `gems/dexpace-core/test/support/` and is unreachable
   from this gem's `test_helper.rb` (`DEF-29`'s disposition, see *Discrepancies* above for the
   sibling finding about `test/support/`). Task 1.
6. **The three-interpreter re-run.** *Decision:* Task 1 installs `ruby@3.2.11` and `ruby@4.0.6` and
   re-runs every fact this plan's `R8`/`R9` decisions are conditional on — specifically, that
   `Fiber[:k] = nil` deletes the key and that a pooled worker created before a key was set sees
   nothing set afterward — on both, before any implementation task begins. A failure on either is a
   **finding, not a silent blocker**: it is recorded in Task 1's own step rather than causing the
   plan to improvise a different mechanism, because `observability/65191069`'s single-interpreter
   caveat is a phase-8 obligation this plan is the one place that can close it, and closing it means
   running the re-check and writing down what happened, not assuming success.

---

## Task order and dependency chain

Thirteen tasks. One hard external ordering rule and one internal one.

**Hard rule, external:** the entry file's `require "dexpace"` (Task 2) requires Task 1's
require-allowlist fix to have already landed, or `gates:require_allowlist` goes red the moment
Task 2's step runs it. Task 1 is first for this reason alone, even before its evidence-gathering
role is considered.

**Hard rule, internal:** `RejectedError` (Task 3) lands before `Pool` (Task 4), because `#post`'s
rejection path raises it by name.

1. **Matrix and floor fact verification, the require-allowlist fix, and this plan's test doubles** —
   installs `ruby@3.2.11` and `ruby@4.0.6`, re-runs every fact Tasks 4–7 depend on, lands the
   one-line `tools/require_allowlist.rb` fix, and builds the five doubles later tasks need.
2. **The gemspec assertion and the entry file** (`P8-21`) — needs Task 1's require-allowlist fix.
3. `Dexpace::Async::Thread::RejectedError` — needs Task 2 (the entry file's `require_relative`
   chain starts there).
4. `Pool.build`/`.new`, `Pool::Job`, the worker loop, `#post` (`ASYNC-2`; `R8`'s clearing line;
   `R9`; `R12`; `P8-20`, `P8-22`, `P8-23`) — needs Task 3.
5. Diagnostics conformance, the break-it proof for `R8`/`R9` (`ASYNC-8`–`ASYNC-12`) — needs Task 4.
6. `#close`, `#release`, the bounded drain, `DEF-31`'s event (`ASYNC-15`, `ASYNC-16`, `ASYNC-17`,
   `SEAM-25`, `XCUT-13`, `XCUT-22`; `P8-24`) — needs Task 4.
7. `Timer` and `Pool#delay` (`ASYNC-18`; `R11`; `P8-25`); the two-fibers-one-thread no-deadlock
   proof — needs Task 6 (shares `#release`'s shutdown sequence).
8. The bridge end to end (`ASYNC-1`, `ASYNC-5`, `ASYNC-13`, `ASYNC-14`, `ASYNC-19`, `ASYNC-20`;
   `PIPE-33`'s cross-reference; `ASYNC-6`'s cross-reference; `R10`; `ASYNC-7`'s demonstration) —
   needs Tasks 4 and 6.
9. `Dexpace::Page::_Executor` conformance via `AsyncPaginator` — needs Task 4.
10. The concurrency proof suite (`XCUT-11`, `SEAM-12` evidence) — needs Tasks 4 and 6.
11. `sig/` completion, the RBS baseline diff, the runtime surface snapshot — needs Tasks 2–9.
12. The clean-bundle isolation run, extended; the full gate set on all three interpreters — needs
    Task 11.
13. The `ASYNC-7` README, YARD, the knowledge note, the register-edit instructions, housekeeping —
    needs Task 12.

---

## Task 1: Matrix and floor fact verification, the require-allowlist fix, and this plan's test doubles

**Requirement IDs:** none directly; the plan's evidence-gathering step, per the precedent phases
3–7 all set, plus the mechanical fix *Discrepancies* item 1 requires before Task 2 can run.
**Design:** "Verified Ruby facts"; "`R8`"; the open questions' items 5 and 6.

**Files:**
- Modify: `tools/require_allowlist.rb`
- Test: `test/gates/require_allowlist_test.rb` (phase 0's, extended),
  `gems/dexpace-async-thread/test/dexpace/async/thread/matrix_facts_test.rb`
- Create: `gems/dexpace-async-thread/test/support/fake_transport.rb`,
  `gems/dexpace-async-thread/test/support/counting_response.rb`,
  `gems/dexpace-async-thread/test/support/recording_sink.rb`,
  `gems/dexpace-async-thread/test/support/probe_scheduler.rb`,
  `gems/dexpace-async-thread/test/support/stub_clock.rb`

- [ ] **Step 1: Install the floor and the ceiling**

```bash
mise install ruby@3.2.11 ruby@4.0.6
```

Confirm both resolve: `mise exec ruby@3.2.11 -- ruby -v` and `mise exec ruby@4.0.6 -- ruby -v`.

- [ ] **Step 2: Write the failing require-allowlist regression test**

Extend `test/gates/require_allowlist_test.rb`:

```ruby
  # `reason_for` is private: RequireAllowlist is `extend self` and declares `private` above it
  # (phase 0's source, :2198-2205), so `RequireAllowlist.reason_for(...)` is a NoMethodError and
  # the probe has to go through #send. Phase 0's own suite reaches the same internals through the
  # public `scan_file`, which needs a fixture file; #send is the smaller of the two here because
  # this case is about one name rather than one file.
  test "P8b-1: bare 'dexpace' is exempt alongside any 'dexpace/...' subpath" do
    permitted = []

    assert_nil(RequireAllowlist.send(:reason_for, "dexpace", permitted))
    assert_nil(RequireAllowlist.send(:reason_for, "dexpace/closeable", permitted))
    refute_nil(RequireAllowlist.send(:reason_for, "dexpace-core", permitted),
               "the hyphenated gem name is not a require target and must not be exempted")
  end
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `ruby -Itest test/gates/require_allowlist_test.rb -n "/P8b-1/"`
Expected: FAIL on the **first** assertion — `reason_for("dexpace", [])` returns the "not in the
require allowlist" string, not `nil`. (The second and third assertions already hold today, so a
failure on either of those is a different defect and must not be papered over by Step 4's fix.)
This is *Discrepancies* item 1, reproduced as a test rather than only argued.

- [ ] **Step 4: Fix `tools/require_allowlist.rb`**

One line, inside `reason_for`:

```ruby
    # P8b-1: dexpace-core's own entry file is lib/dexpace.rb, not lib/dexpace/core.rb -- the one
    # irregular case in the gem-to-file mapping (CLAUDE.md, design §2.3) -- so the bare name needs
    # its own exemption alongside the "dexpace/..." subpath form. Every other gem's entry file
    # already matches the prefix form and is unaffected.
    return nil if permitted.include?(name) || name == "dexpace" || name.start_with?("dexpace/")
```

replacing the existing `return nil if permitted.include?(name) || name.start_with?("dexpace/")`
line.

- [ ] **Step 5: Run it to confirm it passes, then run the real gate**

Run: `ruby -Itest test/gates/require_allowlist_test.rb`
Expected: PASS, including the pre-existing "the real repository is clean" test — this fix widens an
exemption and narrows nothing, so every previously-passing case still passes.
Run: `bundle exec rake gates:require_allowlist`
Expected: clean, unchanged message shape.

- [ ] **Step 6: Write the matrix-facts regression test**

`gems/dexpace-async-thread/test/dexpace/async/thread/matrix_facts_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# Design's verified facts 5, 6, 7, 8, 10 and this plan's own facts 1-9, re-run on every Ruby in
# the matrix rather than trusted from one interpreter. ASYNC-9 and ASYNC-11 rest on facts 5-8
# entirely (observability/65191069's own caveat, which this phase is the one place that closes it).
class MatrixFactsTest < DexpaceTestCase
  test "fact 1: a non-blocking push on a full SizedQueue raises ThreadError, a timed push returns nil" do
    q = ::Thread::SizedQueue.new(1)
    q.push(:a)

    assert_raises(::ThreadError) { q.push(:b, true) }
    assert_nil(q.push(:b, timeout: 0.02))
  end

  test "fact 2: a worker loop over queue.pop drains and exits exactly once" do
    queue = ::Thread::Queue.new
    exits = ::Thread::Queue.new
    ran = []
    worker = ::Thread.new do
      begin
        while (job = queue.pop)
          ran << job
        end
      ensure
        exits << :worker_exited
      end
    end
    queue << :job_a
    queue.close
    worker.join

    assert_equal([:job_a], ran)
    assert_equal(:worker_exited, exits.pop)
  end

  test "fact 3: Proc.new with no block raises ArgumentError on this floor" do
    poster = Object.new
    def poster.post = ::Proc.new

    assert_raises(::ArgumentError) { poster.post }
  end

  test "fact 5: MiniTimer fires two entries in deadline order and never fires a cancelled third" do
    fired = ::Thread::Queue.new
    entries = []
    mutex = ::Thread::Mutex.new
    wake = ::Thread::Queue.new
    thread = ::Thread.new do
      loop do
        deadline = mutex.synchronize { entries.first&.first }
        remaining = deadline ? [deadline - ::Process.clock_gettime(::Process::CLOCK_MONOTONIC), 0].max : nil
        wake.pop(timeout: remaining)
        break if wake.closed?

        due = mutex.synchronize do
          now = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          ready, keep = entries.partition { |(at, _)| at <= now }
          entries.replace(keep)
          ready
        end
        due.each { |(_, block)| block.call }
      end
    end
    now = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    mutex.synchronize do
      entries << [now + 0.05, -> { fired << :a }]
      entries << [now + 0.10, -> { fired << :b }]
      cancel_me = [now + 0.02, -> { fired << :should_not_fire }]
      entries << cancel_me
      entries.sort_by!(&:first)
      entries.delete(cancel_me)
    end
    wake.push(:recompute)

    order = [fired.pop, fired.pop]
    wake.close
    thread.join

    assert_equal(%i[a b], order)
  end

  test "fact 6: Queue#pop(timeout: nil) blocks indefinitely and wakes cleanly on close" do
    queue = ::Thread::Queue.new
    result = nil
    entered = ::Thread::Queue.new
    worker = ::Thread.new do
      entered << :about_to_block
      result = queue.pop(timeout: nil)
    end
    entered.pop
    # Wait for the BLOCKED state on a condition with a deadline, never on a sleep: the thread is
    # running the moment it pushes, and reaching "sleep" is what this fact is about.
    deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + 2.0
    ::Thread.pass until worker.status == "sleep" ||
                        ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) > deadline
    assert_equal("sleep", worker.status)

    queue.close
    worker.join
    assert_nil(result)
  end

  test "fact 8: SizedQueue.new(0) and .new(-1) both refuse to construct" do
    assert_raises(::ArgumentError) { ::Thread::SizedQueue.new(0) }
    assert_raises(::ArgumentError) { ::Thread::SizedQueue.new(-1) }
  end

  test "fact 9: a frozen Data value crosses a thread boundary with a callable member intact" do
    job_class = ::Data.define(:snapshot, :block)
    job = job_class.new(snapshot: { a: 1 }.freeze, block: -> { :ran })

    assert(job.frozen?)
    assert(job.snapshot.frozen?)
    assert_equal(:ran, ::Thread.new { job.block.call }.value)
  end
end
```

- [ ] **Step 7: Run it on 3.4.10, then on the floor and the ceiling**

```bash
bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread/matrix_facts_test.rb
mise exec ruby@3.2.11 -- bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread/matrix_facts_test.rb
mise exec ruby@4.0.6  -- bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread/matrix_facts_test.rb
```

Expected: PASS on all three, 7 runs, 0 failures, 0 errors, 0 warnings. A failure on either
non-floor interpreter is a **finding**: record it in this step (which fact, which interpreter, what
differed) before continuing — do not silently adjust `R8`/`R9`'s mechanism to compensate without
recording why.

- [ ] **Step 8: Write the test doubles**

`gems/dexpace-async-thread/test/support/fake_transport.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # 8b's own #call(request, options, cancellation)-shaped double (SEAM-11/SEAM-16). Independent of
  # gems/dexpace-core/test/support/FakeTransport: this gem's test_helper.rb puts only its own lib
  # on the load path, and a require_relative into another gem's test/ tree is the cross-gem reach
  # styleguide 12.6 forbids -- see this plan's Discrepancies section for the corrected premise.
  #
  # Modes: `gate:` a ::Thread::Queue the test controls, so #call blocks until the test pushes
  # rather than sleeping; `entered:` a ::Thread::Queue this double pushes to as its FIRST act, so
  # a test that must act only once the worker is inside #call waits on a condition instead of a
  # sleep (Task 8's ASYNC-14 cancellation is the case); `response:`/`raises:` what #call produces
  # once the gate opens.
  #
  # `ignores_cancellation:` is documentary only and changes no behaviour: #call never inspects
  # its own `cancellation` argument in ANY mode, exactly like `Net::HTTP` itself (a real transport
  # has to be told to close its socket under a blocked read; it does not poll a token). The
  # keyword exists so ASYNC-7's test can name its own intent at the call site -- "this double does
  # not cooperate with an abort" -- rather than because a second, cooperative mode exists to
  # contrast it with. `#call`'s third argument is still recorded in `@calls` either way, so a test
  # can assert what was threaded through even though nothing here reads it.
  class FakeTransport
    attr_reader :calls

    def initialize(response: nil, raises: nil, gate: nil, entered: nil,
                   ignores_cancellation: false)
      @response = response
      @raises = raises
      @gate = gate
      @entered = entered
      @ignores_cancellation = ignores_cancellation
      @calls = []
      @mutex = ::Thread::Mutex.new
    end

    def call(request, options, cancellation)
      @mutex.synchronize { @calls << [request, options, cancellation] }
      @entered&.push(:in_call)
      @gate&.pop
      raise @raises if @raises

      @response
    end

    def ignores_cancellation? = @ignores_cancellation
  end
end
```

`gems/dexpace-async-thread/test/support/counting_response.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # A #close-counting Response double, for ASYNC-5's exactly-once orphan close and ASYNC-20's
  # negative twin (a delivered response is never closed by a later cancel).
  class CountingResponse
    include Dexpace::Closeable

    def initialize
      @closes = 0
      @mutex = ::Thread::Mutex.new
      initialize_closeable(owned: true)
    end

    def closes
      @mutex.synchronize { @closes }
    end

    private

    def release
      @mutex.synchronize { @closes += 1 }
    end
  end
end
```

`gems/dexpace-async-thread/test/support/recording_sink.rb` (shaped identically to phase 5b's
`Dexpace::RecordingSink`, declared fresh here for the same `test/support/` reason as `FakeTransport`
above):

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  class RecordingSink
    Entry = ::Data.define(:severity, :message, :payload)

    def initialize
      @entries = []
      @mutex = ::Thread::Mutex.new
    end

    def entries
      @mutex.synchronize { @entries.dup }
    end

    def debug(msg = nil, &block) = record(:debug, msg, &block)
    def info(msg = nil, &block) = record(:info, msg, &block)
    def warn(msg = nil, &block) = record(:warn, msg, &block)
    def error(msg = nil, &block) = record(:error, msg, &block)

    def debug? = true
    def info? = true
    def warn? = true
    def error? = true

    private

    def record(severity, msg)
      payload = block_given? ? yield : msg
      @mutex.synchronize { @entries << Entry.new(severity: severity, message: msg, payload: payload).freeze }
      nil
    end
  end
end
```

`gems/dexpace-async-thread/test/support/probe_scheduler.rb` (phase 5a's exact, verified shape,
re-declared here for the same reason):

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # A minimal Fiber::Scheduler, copied from phase 5a's Dexpace::ProbeScheduler (this gem's own
  # test/support/, per DEF-29's disposition; see this plan's Discrepancies section). Verified fact
  # 7 above is this exact class, unmodified, driving a fiber blocked on a Thread::Queue#pop.
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
    # ownership is per-fiber, so a lock held across a yield is a lock the resuming fiber cannot
    # take.
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
          break if nearest.nil?

          ::Kernel.sleep([nearest - monotonic, 0.0].max)
          next
        end

        resumable.each { |fiber| fiber.resume if fiber.alive? }
      end
    end
  end
end
```

`gems/dexpace-async-thread/test/support/stub_clock.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # Drives Task 6's shutdown-timed-out branch and Task 7's delay-interval assertions with no real
  # waiting. Answers only #monotonic, the one method the pool's own arithmetic uses (Clock#now and
  # #sleep have no consumer here); a later edit that reaches for either fails loudly rather than
  # silently using a stub never designed for it (design open question 5).
  class StubClock
    def initialize(start: 0.0)
      @monotonic = start
      @mutex = ::Thread::Mutex.new
    end

    def monotonic
      @mutex.synchronize { @monotonic }
    end

    def advance(seconds)
      @mutex.synchronize { @monotonic += seconds }
      nil
    end

    def now
      raise ::NotImplementedError, "StubClock answers only #monotonic"
    end

    def sleep(*)
      raise ::NotImplementedError, "StubClock answers only #monotonic"
    end
  end
end
```

- [ ] **Step 9: Run `gates:require_allowlist` and the smoke suite once more**

Run: `bundle exec rake gates:require_allowlist test:gems`
Expected: both clean/green — the fix and the new doubles change nothing else in the tree.

---

## Task 2: The gemspec assertion and the entry file

**Requirement IDs:** none new (`NFR-14`; `SEAM-10`'s replacement via `P2-1`/`P8-21`).
**Design:** "`Dexpace::Async::Thread` — the entry file"; `P8-21`; *Discrepancies* item 2 above.

**Files:**
- Modify: `gems/dexpace-async-thread/lib/dexpace/async/thread.rb`,
  `gems/dexpace-async-thread/sig/dexpace/async/thread.rbs`
- Test: `gems/dexpace-async-thread/test/dexpace/async/thread_test.rb` (phase 0's smoke suite,
  extended)

- [ ] **Step 1: Write the failing tests**

Extend `gems/dexpace-async-thread/test/dexpace/async/thread_test.rb`:

```ruby
  test "NFR-2: the gemspec declares dexpace-core and nothing else" do
    spec = Gem::Specification.load(
      File.expand_path("../../../dexpace-async-thread.gemspec", __dir__)
    )

    assert_equal(%w[dexpace-core], spec.runtime_dependencies.map(&:name))
  end

  test "P8-21: CORE_REQUIREMENT is the two-segment pessimistic form the gemspec declares" do
    spec = Gem::Specification.load(
      File.expand_path("../../../dexpace-async-thread.gemspec", __dir__)
    )
    core_dep = spec.dependencies.find { |d| d.name == "dexpace-core" }

    assert_equal(core_dep.requirement.to_s, Dexpace::Async::Thread::CORE_REQUIREMENT)
    assert_match(/\A~> \d+\.\d+\z/, Dexpace::Async::Thread::CORE_REQUIREMENT)
  end

  # The skewed version is passed as a plain String, not as a stand-in Dexpace module: a
  # `VERSION = "9.9.9"` inside a `Class.new do … end` block is a dynamic constant assignment and
  # will not parse, and #assert_core_version! takes the version string precisely so the skew case
  # is testable without redefining Dexpace::VERSION under the running suite.
  test "P8-21: a skewed core raises Dexpace::SeamError naming both versions, at require time" do
    error = assert_raises(Dexpace::SeamError) do
      Dexpace::Async::Thread.send(:assert_core_version!, "9.9.9")
    end

    assert_match(/dexpace-async-thread/, error.message)
    assert_match(/9\.9\.9/, error.message)
    assert_match(/#{Regexp.escape(Dexpace::Async::Thread::CORE_REQUIREMENT)}/, error.message)
  end

  test "the running core satisfies CORE_REQUIREMENT (the assertion already ran once, at require)" do
    major, minor, = Dexpace::VERSION.split(".", 3)
    wanted = Gem::Requirement.new(Dexpace::Async::Thread::CORE_REQUIREMENT)

    assert(wanted.satisfied_by?(Gem::Version.new("#{major}.#{minor}.0")))
  end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread_test.rb`
Expected: FAIL — `NameError: uninitialized constant Dexpace::Async::Thread::CORE_REQUIREMENT`, and
`NoMethodError` on the private `assert_core_version!`.

- [ ] **Step 3: Write the entry file**

`gems/dexpace-async-thread/lib/dexpace/async/thread.rb` (phase 0's `require_relative
"thread/version"` line stays; everything else is new, in this order):

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require_relative "thread/version"

module Dexpace
  module Async
    # The zero-third-party async driver: a bounded worker pool over `::Thread`/`::Thread::SizedQueue`
    # that satisfies SEAM-18's caller-supplied-executor contract and settles the core-owned pivot
    # (design §2.1's charter sentence). See `Dexpace::Async::Thread::Pool` for the whole surface;
    # this module exists only to carry `VERSION`, `CORE_REQUIREMENT` and the version-skew guard.
    #
    # There is no module-level default pool and no `.post` here (concurrency-and-async/a1ec6ce4;
    # SEAM-18): construct `Pool.build(size:)` explicitly, in the caller's own code, where the size
    # decision belongs.
    module Thread
      # This gem's own version. NFR-15's runtime-emitted identifier.
      # (Defined in thread/version.rb; declared here for reference only -- see that file.)

      # The `~> MAJOR.MINOR` requirement this gem was built against, identical to the string the
      # gemspec's `add_dependency "dexpace-core", ...` line declares. `gates:gemspec_audit` checks
      # the agreement from the gemspec side; the "current core version satisfies it" test above
      # checks it from this side.
      CORE_REQUIREMENT = "~> 0.0"

      # SEAM-18 requires the executor to be caller-supplied with no default, so there is no
      # executor registry to register into (P2-1) -- the version-skew assertion is the boundary's
      # substance and `Dexpace::Registry#register`'s `core:` keyword is only its usual vehicle.
      # Kept and made directly. Runs before the require_relative chain below, so a skewed pair
      # fails at `require` time rather than at the first #post (design §2.4).
      #
      # Gem::Version/Gem::Requirement, used directly and with no explicit `require`: this gem is
      # only ever loaded as an installed/bundled gem, under `bundle exec` or an equivalent
      # RubyGems-aware invocation, where both are already loaded transitively by `bundler/setup`
      # before any gem's own code runs -- unlike dexpace-core, which must also work with no
      # Bundler at all and therefore hand-rolls its own comparison (see this plan's Discrepancies
      # section, item 2).
      def self.assert_core_version!(core_version)
        wanted = ::Gem::Requirement.new(CORE_REQUIREMENT)
        return if wanted.satisfied_by?(::Gem::Version.new(core_version))

        raise Dexpace::SeamError,
              "dexpace-async-thread #{VERSION} was built against dexpace-core " \
              "#{CORE_REQUIREMENT}, but dexpace-core #{core_version} is loaded"
      end
      private_class_method :assert_core_version!

      assert_core_version!(Dexpace::VERSION)
    end
  end
end
```

- [ ] **Step 4: Write the `sig/` addition**

`gems/dexpace-async-thread/sig/dexpace/async/thread.rbs` gains:

```rbs
module Dexpace
  module Async
    module Thread
      CORE_REQUIREMENT: String
    end
  end
end
```

(`VERSION: String` already exists, declared in `sig/dexpace/async/thread/version.rbs` from phase 0
and untouched here.)

- [ ] **Step 5: Run the tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread_test.rb`
Expected: PASS. Then `bundle exec rake rubocop rbs:validate steep gates:gemspec_audit
gates:require_allowlist`.

---

## Task 3: `Dexpace::Async::Thread::RejectedError`

**Requirement IDs:** none new (`ASYNC-2`'s companion class; referenced by Tasks 4, 6, 8).
**Design:** "`Dexpace::Async::Thread::RejectedError`"; "Two errors, two conditions, one new name."

**Files:**
- Create: `gems/dexpace-async-thread/lib/dexpace/async/thread/rejected_error.rb`,
  `gems/dexpace-async-thread/sig/dexpace/async/thread/rejected_error.rbs`
- Modify: `gems/dexpace-async-thread/lib/dexpace/async/thread.rb`
- Test: `gems/dexpace-async-thread/test/dexpace/async/thread/rejected_error_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# ASYNC-2's companion: a full queue is backpressure to retry or shed, a closed pool (Dexpace::
# ClosedError, phase 2's) is a lifecycle bug -- two classes because a caller's two sensible
# responses differ.
class RejectedErrorTest < DexpaceTestCase
  test "is a StandardError that Dexpace::Error catches, and is not a transport failure" do
    error = Dexpace::Async::Thread::RejectedError.new("dexpace-async-thread: queue full")

    assert_kind_of(::StandardError, error)
    assert_kind_of(Dexpace::Error, error)
    refute_kind_of(::IOError, error)
  end

  test "answers no #retryable? predicate" do
    error = Dexpace::Async::Thread::RejectedError.new("full")

    refute_respond_to(error, :retryable?)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread/rejected_error_test.rb`
Expected: FAIL — `NameError: uninitialized constant Dexpace::Async::Thread::RejectedError`.

- [ ] **Step 3: Write the implementation**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Async
    module Thread
      # Raised by Pool#post when the bounded submission queue is full -- ASYNC-2's "saturated"
      # half of "worker-pool rejection (a saturated/shut-down executor)". A closed pool raises
      # Dexpace::ClosedError instead (SEAM-15, phase 2's class): two classes because a caller's two
      # sensible responses differ, a closed pool is a lifecycle bug and a full queue is
      # backpressure to retry or shed.
      #
      # Answers no #retryable? predicate, deliberately: that protocol belongs to
      # Dexpace::TransportError (the phase-level task) and a pool rejection never crosses a retry
      # boundary -- it happens at the bridge, above the pipeline, where no RETRY step can see it.
      class RejectedError < ::StandardError
        include Dexpace::Error
      end
    end
  end
end
```

- [ ] **Step 4: Write the `sig/` file**

```rbs
module Dexpace
  module Async
    module Thread
      class RejectedError < ::StandardError
        include Dexpace::Error
      end
    end
  end
end
```

- [ ] **Step 5: Add the `require_relative` and run the test**

Add `require_relative "thread/rejected_error"` to `lib/dexpace/async/thread.rb`, immediately after
the `assert_core_version!` call.
Run: `bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread/rejected_error_test.rb`
Expected: PASS. Then `bundle exec rake rubocop rbs:validate steep`.

---

## Task 4: `Pool.build`/`.new`, `Pool::Job`, the worker loop, and `#post`

**Requirement IDs:** `ASYNC-2`. **Design:** "`Dexpace::Async::Thread::Pool`"; "`Pool::Job` —
`private_constant`"; "The worker loop, stated as code because four requirements are in its shape";
"`R8`"; "`R9`" (the antecedent-check row itself is Task 5's, but the clearing line that discharges
it is written here); "`R12`"; deviations `P8-20`, `P8-22`, `P8-23`.

**Files:**
- Create: `gems/dexpace-async-thread/lib/dexpace/async/thread/pool.rb`,
  `gems/dexpace-async-thread/sig/dexpace/async/thread/pool.rbs`
- Modify: `gems/dexpace-async-thread/lib/dexpace/async/thread.rb`
- Test: `gems/dexpace-async-thread/test/dexpace/async/thread/pool_test.rb`

This task does **not** implement `#close`/`#delay` yet: `Dexpace::Closeable`'s default `#release`
raises `NotImplementedError`, which is deliberately left as-is until Task 6, so the ordering is
visible in the diff (7a's `P7-7` precedent, Task 13, Step 4).

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/fake_transport"

# ASYNC-2, R8, R9's clearing line, R12. Every mutable fixture is built fresh per test
# (testing/4ef070df); every test closes its own pool via `pool = Pool.build(...); ... ensure
# pool.close_workers_only_for_this_test_helper` is NOT used here -- Task 4 has no #close yet, so
# teardown joins workers directly through the queue instead.
class PoolTest < DexpaceTestCase
  Pool = Dexpace::Async::Thread::Pool

  def teardown
    @pool_queue&.close
    @pool_workers&.each(&:join)
  end

  # Reaches into the pool's own ivars via instance_variable_get, because Task 4 ships no #close --
  # the alternative, skipping teardown, would leak six workers per test into Thread.list and make
  # every later test's thread-accounting assertion (Task 10) order-dependent.
  def build(size: 2, **kwargs)
    pool = Pool.build(size: size, **kwargs)
    @pool_queue = pool.instance_variable_get(:@queue)
    @pool_workers = pool.instance_variable_get(:@workers)
    pool
  end

  test "size is a required keyword with no default" do
    assert_raises(::ArgumentError) { Pool.build }
  end

  test "size rejects zero, a negative and a non-Integer, naming the keyword" do
    [0, -1, "4", 1.5].each do |bad|
      error = assert_raises(Dexpace::InvalidArgumentError) { Pool.build(size: bad) }
      assert_match(/size/, error.message, bad.inspect)
    end
  end

  test "queue_limit defaults to size * QUEUE_DEPTH_PER_WORKER and rejects the same shapes" do
    pool = build(size: 3)
    assert_equal(3 * Pool::QUEUE_DEPTH_PER_WORKER, pool.queue_limit)

    [0, -1, "4"].each do |bad|
      error = assert_raises(Dexpace::InvalidArgumentError) { Pool.build(size: 2, queue_limit: bad) }
      assert_match(/queue_limit/, error.message, bad.inspect)
    end
  end

  test "shutdown_timeout, name, logger and clock validate and default" do
    assert_raises(Dexpace::InvalidArgumentError) { Pool.build(size: 1, shutdown_timeout: -1) }
    assert_raises(Dexpace::InvalidArgumentError) { Pool.build(size: 1, name: "") }
    assert_raises(Dexpace::InvalidArgumentError) { Pool.build(size: 1, logger: Object.new) }
    assert_raises(Dexpace::InvalidArgumentError) { Pool.build(size: 1, clock: Object.new) }

    pool = build(size: 1)
    assert_equal(Pool::DEFAULT_NAME, pool.name)
  end

  test "Pool.new is private" do
    assert_raises(::NoMethodError) { Pool.new(1, 1, 1, "x", nil, nil) }
  end

  test "there is exactly one Thread.new in the gem's lib, and it is in the spawn helper" do
    hits = Dir.glob(File.join(ROOT, "gems/dexpace-async-thread/lib/**/*.rb")).flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        "#{path}:#{index + 1}" if line.include?("::Thread.new") || line.match?(/(?<!:)\bThread\.new/)
      end
    end

    assert_equal(1, hits.size, hits.inspect)
    assert_match(%r{lib/dexpace/async/thread/pool\.rb}, hits.first)
  end

  test "the forbidden three and Thread.current[] appear nowhere in lib/" do
    banned = /Timeout\.timeout|Thread#raise|\.raise\(|Thread#kill|Thread\.current\[/
    hits = Dir.glob(File.join(ROOT, "gems/dexpace-async-thread/lib/**/*.rb")).flat_map do |path|
      File.readlines(path).grep(banned)
    end

    assert_empty(hits)
  end

  test "a unit runs on a worker thread, not the caller's" do
    caller_id = ::Thread.current.object_id
    pool = build(size: 1)
    seen = ::Thread::Queue.new

    pool.post { seen << ::Thread.current.object_id }

    refute_equal(caller_id, seen.pop)
  end

  test "post returns in bounded time with a full queue, from any thread" do
    pool = build(size: 1, queue_limit: 1)
    gate = ::Thread::Queue.new
    pool.post { gate.pop } # occupies the one worker
    pool.post { nil } rescue nil # fills the one-slot queue, or is itself rejected -- either is fine here

    submitter = ::Thread.new do
      pool.post { nil }
    rescue Dexpace::Async::Thread::RejectedError
      :rejected
    end
    result = submitter.join(1)
    gate << :go

    refute_nil(result, "post did not return in bounded time")
  end

  test "a full queue raises RejectedError naming the pool, the limit and the worker count" do
    pool = build(size: 1, queue_limit: 1)
    gate = ::Thread::Queue.new
    pool.post { gate.pop }

    error = assert_raises(Dexpace::Async::Thread::RejectedError) { pool.post { nil } }
    assert_match(/#{Regexp.escape(pool.name)}/, error.message)
    assert_match(/1/, error.message)

    gate << :go
  end

  test "post requires a block" do
    pool = build(size: 1)
    assert_raises(::ArgumentError) { pool.post }
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread/pool_test.rb`
Expected: FAIL — `NameError: uninitialized constant Dexpace::Async::Thread::Pool`.

- [ ] **Step 3: Write `lib/dexpace/async/thread/pool.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "rejected_error"
# `require_relative "timer"` is added in Task 7, with the file it names: Timer does not exist yet
# and a require of a file that is not there is a LoadError, not a red test.

module Dexpace
  module Async
    module Thread
      # A fixed-size ::Thread pool over a bounded ::Thread::SizedQueue, satisfying SEAM-18's
      # caller-supplied-executor duck type (#post { }) and Dexpace::Page::_Executor exactly (7c).
      # `size:` threads are created at construction and never grow or shrink -- a worker cannot
      # die (see #run below), so there is nothing to replace.
      #
      # NFR-11: no constant outside Dexpace:: appears anywhere in this class's public surface --
      # the threads and queues are private ivars with no readers, and #size/#queue_limit return
      # the Integers the caller passed, never @queue.max or @workers.length.
      class Pool
        include Dexpace::Closeable

        # A depth per worker, not an absolute capacity: "a worker may have eight units of work
        # waiting behind it before the pool rejects", scaling with whatever size: the caller
        # chose. Not tuned against a benchmark (design open question 1) -- the number that
        # matters is size:, which the caller states explicitly.
        QUEUE_DEPTH_PER_WORKER = 8

        # Long enough to outlive one in-flight HTTP send. A default rather than a required
        # keyword (design open question 2): a wrong size: is a starvation bug that persists for
        # the pool's life; a wrong shutdown_timeout: costs at most one slow shutdown. Should
        # exceed the wrapped transport's own read timeout.
        DEFAULT_SHUTDOWN_TIMEOUT = 30.0

        DEFAULT_NAME = "dexpace-async-thread"

        # DEF-31's event field keys. private_constant: dexpace-conformance's assertion is "close
        # twice -> one event" and needs only the event name; a public field key would be an
        # NFR-4 lock with one reader inside the gem that owns it (design open question 3).
        WORKER_COUNT_FIELD = "dexpace.executor.worker_count"
        private_constant :WORKER_COUNT_FIELD
        DRAINED_FIELD = "dexpace.executor.drained"
        private_constant :DRAINED_FIELD

        # Crosses a thread boundary: frozen Data, both members immutable by construction
        # (concurrency-and-async/2c743901, /16ceb098). The snapshot is Diagnostics.capture's
        # frozen Hash and the block is a Proc; the snapshot's *values* are the caller's own
        # objects and are neither copied nor frozen -- a caller who puts a mutable object into
        # fiber storage shares that object across this hop (observability/65191069), which is the
        # caller's obligation and is stated in the README and in #post's YARD block.
        Job = ::Data.define(:snapshot, :block)
        private_constant :Job

        WORKER_EXITED = :worker_exited
        private_constant :WORKER_EXITED

        private_class_method :new

        def self.build(size:, queue_limit: nil, shutdown_timeout: DEFAULT_SHUTDOWN_TIMEOUT,
                        name: DEFAULT_NAME, logger: Dexpace::Instrumentation::Logger::NULL,
                        clock: Dexpace::Clock::SYSTEM)
          size = positive_integer!(:size, size)
          queue_limit = positive_integer!(:queue_limit, queue_limit || size * QUEUE_DEPTH_PER_WORKER)
          unless shutdown_timeout.is_a?(::Numeric) && !shutdown_timeout.negative?
            raise Dexpace::InvalidArgumentError,
                  "shutdown_timeout must be a non-negative Numeric, got #{shutdown_timeout.inspect}"
          end
          unless name.is_a?(::String) && !name.empty?
            raise Dexpace::InvalidArgumentError, "name must be a non-empty String, got #{name.inspect}"
          end
          unless logger.respond_to?(:event)
            raise Dexpace::InvalidArgumentError, "logger must respond to #event, got #{logger.class}"
          end
          unless clock.respond_to?(:monotonic)
            raise Dexpace::InvalidArgumentError, "clock must respond to #monotonic, got #{clock.class}"
          end

          new(size, queue_limit, shutdown_timeout, name, logger, clock)
        end

        def self.positive_integer!(keyword, value)
          unless value.is_a?(::Integer) && value.positive?
            raise Dexpace::InvalidArgumentError,
                  "#{keyword} must be a positive Integer, got #{value.inspect}"
          end
          value
        end
        private_class_method :positive_integer!

        attr_reader :size, :queue_limit, :name

        def initialize(size, queue_limit, shutdown_timeout, name, logger, clock)
          @size = size
          @queue_limit = queue_limit
          @shutdown_timeout = shutdown_timeout
          @name = name
          @logger = logger
          @clock = clock
          @queue = ::Thread::SizedQueue.new(queue_limit)
          @exits = ::Thread::Queue.new
          # `@timer = Timer.new(name)` is added in Task 7 (cheap: no thread is spawned until the
          # first positive #delay -- R11). It is not here because Timer does not exist yet.
          @workers = ::Array.new(size) { |index| spawn_worker(index) }
          initialize_closeable(owned: true)
        end

        # SEAM-18's duck type; Dexpace::Page::_Executor exactly (`() { () -> void } -> void`).
        # Never blocks the calling thread, including a pool worker re-posting to its own pool
        # (P8-23): the submission queue's non-blocking push turns a full queue into
        # RejectedError rather than a parked producer.
        #
        # @yield [] the unit of work; runs on a pool worker, with the caller's diagnostic context
        #   installed for its duration (ASYNC-8..ASYNC-12)
        # @raise [Dexpace::ClosedError] if the pool is closed
        # @raise [Dexpace::Async::Thread::RejectedError] if the bounded queue is full
        def post(&block)
          raise ::ArgumentError, "post requires a block" unless block
          raise Dexpace::ClosedError, "#{@name} is closed" if closed?

          job = Job.new(snapshot: Dexpace::Instrumentation::Diagnostics.capture, block: block)
          begin
            @queue.push(job, true)
          rescue ::ThreadError
            raise RejectedError,
                  "#{@name}: queue full (limit #{@queue_limit}, #{@size} workers)"
          rescue ::ClosedQueueError
            raise Dexpace::ClosedError, "#{@name} is closed"
          end
          nil
        end

        private

        # The ONE ::Thread.new in this gem: bounded by a validated size, in one private method.
        def spawn_worker(index)
          ::Thread.new do
            ::Thread.current.name = "#{@name} worker #{index}"
            ::Thread.current.report_on_exception = false # set INSIDE the thread; verified fact 10
            # R8/R9: clear whatever this worker inherited from the fiber that called Pool.build,
            # exactly once, before the first task. Fiber.current.storage returns a fresh Hash
            # (verified fact 5), so this iterates a copy and writes to the live storage.
            ::Fiber.current.storage&.each_key { |key| ::Fiber[key] = nil }
            begin
              while (job = @queue.pop) # a suspension point; check-after-resume's earliest chance
                run(job)
              end
            ensure
              @exits << WORKER_EXITED # non-nil sentinel; verified fact 4/this plan's fact 1
            end
          end
        end

        # P8-22: rescues ::Exception and the worker never dies. RECOV-2's "rescue Exception,
        # re-raise anything outside StandardError" is departed from deliberately here: on a
        # worker thread "re-raise" means the thread dies silently (verified facts 10, 11), and
        # the caller's failure channel was already settled by the block itself before this net
        # could see anything -- what reaches here is a defect IN the block, emitted as a
        # diagnostic rather than demoted into any caller's result. Interrupt is the one case
        # worth naming: Ctrl-C is delivered to the main thread, so swallowing it here discards
        # nothing.
        def run(job)
          Dexpace::Instrumentation::Diagnostics.with(job.snapshot) { job.block.call }
        rescue ::Exception => e
          Dexpace::Instrumentation.contain(@logger, event: Dexpace::Instrumentation::Events::INSTRUMENTATION_LOG) do
            @logger.event(Dexpace::Instrumentation::Severity::ERROR)
                   .event(Dexpace::Instrumentation::Events::INSTRUMENTATION_HOOK)
                   .cause(e).emit
          end
          nil
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/async/thread/pool.rbs`**

```rbs
module Dexpace
  module Async
    module Thread
      class Pool
        include Dexpace::Closeable

        QUEUE_DEPTH_PER_WORKER: Integer
        DEFAULT_SHUTDOWN_TIMEOUT: Float
        DEFAULT_NAME: String

        # ?queue_limit is Integer? and not Integer because the derived default is a nil sentinel:
        # `queue_limit: size * QUEUE_DEPTH_PER_WORKER` in the parameter list would evaluate against
        # an UNVALIDATED size, so `Pool.build(size: nil)` would raise NoMethodError from the default
        # instead of Dexpace::InvalidArgumentError naming the keyword -- and `steep check` reads a
        # nil default under an Integer declaration as an error. The design's sig/ block carries the
        # same `Integer?`.
        def self.build: (size: Integer,
                         ?queue_limit: Integer?,
                         ?shutdown_timeout: Numeric,
                         ?name: String,
                         ?logger: Dexpace::Instrumentation::Logger,
                         ?clock: Dexpace::Clock) -> Pool
        def post: () { () -> void } -> void
        def size: () -> Integer
        def queue_limit: () -> Integer
        def name: () -> String
      end
    end
  end
end
```

(`#delay` is added to this file in Task 7, once it exists.)

- [ ] **Step 5: Add the `require_relative` and run the tests**

Add `require_relative "thread/pool"` to `lib/dexpace/async/thread.rb`, after
`require_relative "thread/rejected_error"`.
Run: `bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread/pool_test.rb`
Expected: PASS, 11 runs. Then `bundle exec rake rubocop rbs:validate steep`.

- [ ] **Step 6: Prove the grep tests are not vacuous**

Temporarily add a second `::Thread.new` anywhere in `lib/` (e.g. inside `#post`) and confirm the
"exactly one Thread.new" test goes red; restore. Temporarily add a bare `Thread.current[:x]` read
and confirm the forbidden-three test goes red; restore. A test that has only ever been seen to
pass has not been tested against failure.

---

## Task 5: Diagnostics conformance, and the break-it proof for `R8`/`R9`

**Requirement IDs:** `ASYNC-8`, `ASYNC-9`, `ASYNC-10`, `ASYNC-11`, `ASYNC-12`.
**Design:** "`R8` — `ASYNC-9`'s save/install/restore against `OI-13`'s warned setter"; "`R9` —
which clause of `ASYNC-12` is live"; testing strategy group 4.

**Files:**
- Test: `gems/dexpace-async-thread/test/dexpace/async/thread/pool_diagnostics_test.rb`

No new `lib/` code: Task 4's `spawn_worker` already carries the one clearing line and calls
`Diagnostics.with`. **This task has no ordinary red phase for that mechanism** — `Diagnostics.
capture`/`.with` already exist in `dexpace-core`, shipped by phase 5b. What this task delivers is
the proof: the two negative assertions the design's verified facts 6/7 demand, and the break-it run
that shows they are not vacuous.

- [ ] **Step 1: Write the tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# ASYNC-8..ASYNC-12. Every test restores the slot it touches in teardown (testing/4ef070df); every
# pool is built fresh in `setup`, in a DIFFERENT fiber-storage context than the one it is driven
# from, per verified fact 7's own shape -- a suite that builds the pool in the test body, in the
# caller's own context, passes under the bug this suite exists to catch.
class PoolDiagnosticsTest < DexpaceTestCase
  Pool = Dexpace::Async::Thread::Pool

  def setup
    @prior_storage = (::Fiber.current.storage || {}).dup
    ::Fiber[:"trace.id"] = "POOL-BUILD-TIME"
    ::Fiber[:tenant] = "assembly"
    @pool = Pool.build(size: 1) # the one worker inherits {trace.id: POOL-BUILD-TIME, tenant:
                                 # assembly} HERE, at ::Thread.new's moment of creation
    @queue = @pool.instance_variable_get(:@queue)
    @workers = @pool.instance_variable_get(:@workers)
    # The caller's OWN context, from this point on, must not carry the build-time keys -- a real
    # caller submitting a request was never on the thread that built the pool. Clearing here,
    # rather than in each test body, is what makes every #post below capture exactly what the
    # test installs and nothing left over from setup: Diagnostics.capture runs on THIS (the
    # calling) thread inside #post, so an uncleared :tenant here would appear in every job's
    # snapshot regardless of whether the worker leaked anything -- indistinguishable from the bug
    # this suite exists to catch. This is the fix over a first draft that skipped this step and
    # asserted a false positive every time (confirmed by running that draft against the real
    # class: every test failed, including the ones with the R8 clearing line correctly applied).
    ::Fiber[:"trace.id"] = nil
    ::Fiber[:tenant] = nil
  end

  def teardown
    @queue.close
    @workers.each(&:join)
    (@prior_storage.keys | (::Fiber.current.storage || {}).keys).each { |k| ::Fiber[k] = @prior_storage[k] }
  end

  test "ASYNC-10/R8: a key set at pool-build time and absent from the caller's snapshot is not visible to the task" do
    result_queue = ::Thread::Queue.new
    Dexpace::Instrumentation::Diagnostics.with({ :"trace.id" => "CALLER-A" }) do
      @pool.post { result_queue << ::Fiber.current.storage.dup }
    end
    observed = result_queue.pop

    refute(observed.key?(:tenant), "the pool's build-time context leaked into the caller's task")
    assert_equal({ :"trace.id" => "CALLER-A" }, observed)
  end

  test "ASYNC-9: reuse across two tasks, install-and-restore exact across a throw" do
    gate = ::Thread::Queue.new
    @pool.post do
      Dexpace::Instrumentation::Diagnostics.with({ :"trace.id" => "A" }) { gate << ::Fiber.current.storage.dup }
    end
    first = gate.pop

    begin
      @pool.post { Dexpace::Instrumentation::Diagnostics.with({ :"trace.id" => "B" }) { raise "boom" } }
    rescue
      nil
    end

    @pool.post { gate << ::Fiber.current.storage.dup }
    after_throw = gate.pop

    assert_equal({ :"trace.id" => "A" }, first)
    assert_equal({}, after_throw, "the worker's own (post-clear) context must be intact after a throw")
  end

  test "ASYNC-11: an absent context captures as empty and installs as a clear, not a raise" do
    @pool.post { Dexpace::Instrumentation::Diagnostics.with({}) { nil } }
    # no exception: reaching the next assertion is the proof
    result_queue = ::Thread::Queue.new
    @pool.post { result_queue << ::Fiber.current.storage.dup }
    assert_equal({}, result_queue.pop)
  end

  test "ASYNC-8/ASYNC-12: the three-context conformance sequence -- assemble A, execute B, re-execute C" do
    ::Fiber[:"trace.id"] = "A"
    # pool already built under A/tenant in setup; simulate "assembled under A" by using @pool as-is

    seen = ::Thread::Queue.new
    Dexpace::Instrumentation::Diagnostics.with({ :"trace.id" => "B" }) { @pool.post { seen << ::Fiber[:"trace.id"] } }
    Dexpace::Instrumentation::Diagnostics.with({ :"trace.id" => "C" }) { @pool.post { seen << ::Fiber[:"trace.id"] } }

    assert_equal(%w[B C], [seen.pop, seen.pop])
  end
end
```

- [ ] **Step 2: Run them to confirm they pass against Task 4's code**

Run: `bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread/pool_diagnostics_test.rb`
Expected: PASS, 4 runs.

- [ ] **Step 3: The break-it proof — remove the clearing line and confirm red**

In `spawn_worker`, comment out `::Fiber.current.storage&.each_key { |key| ::Fiber[key] = nil }`.
Run the suite again.
Expected: the "a key set at pool-build time…" test FAILS — `observed.key?(:tenant)` is `true`,
`{"trace.id": "CALLER-A", tenant: "assembly"}` observed instead of `{"trace.id": "CALLER-A"}`. This
is design fact 7, reproduced against the real class rather than a standalone probe. Restore the
line; confirm green again.

---

## Task 6: `#close`, `#release`, the bounded drain, and `DEF-31`'s lifecycle event

**Requirement IDs:** `ASYNC-15`, `ASYNC-16`, `ASYNC-17`. **Design:** "Teardown, stated as the
sequence it is"; "`R12`" (the `dd8e6d2d`/`047644ea` rows); deviation `P8-24`; `DEF-31`.

**Files:**
- Modify: `gems/dexpace-async-thread/lib/dexpace/async/thread/pool.rb`,
  `gems/dexpace-async-thread/sig/dexpace/async/thread/pool.rbs`
- Test: `gems/dexpace-async-thread/test/dexpace/async/thread/pool_test.rb` (extended)

- [ ] **Step 1: Write the failing tests**

Add to `pool_test.rb` (replacing the `build`/`teardown` helper now that `#close` exists):

```ruby
  def teardown
    @pool&.close
  end

  def build(size: 2, **kwargs)
    @pool = Pool.build(size: size, **kwargs)
  end

  test "close is idempotent: twice returns nil twice and releases once" do
    pool = build(size: 2)

    assert_nil(pool.close)
    assert(pool.closed?)
    assert_nil(pool.close)
  end

  test "close from 16 threads at once emits exactly one shutdown event" do
    sink = Dexpace::RecordingSink.new
    pool = build(size: 2, logger: Dexpace::Instrumentation::Logger.build(sink: sink))

    16.times.map { ::Thread.new { pool.close } }.each(&:join)

    events = sink.entries.select { |e| e.payload.is_a?(Hash) && e.payload[Dexpace::Instrumentation::Keys::EVENT] == Dexpace::Instrumentation::Events::INSTRUMENTATION_SHUTDOWN }
    assert_equal(1, events.size)
  end

  test "an in-flight task finishes rather than being interrupted, and queued work still drains" do
    pool = build(size: 1, queue_limit: 4)
    gate = ::Thread::Queue.new
    ran = ::Thread::Queue.new
    pool.post { gate.pop; ran << :first }
    pool.post { ran << :second }

    closer = ::Thread.new { pool.close }
    gate << :go
    closer.join

    assert_equal(%i[first second], [ran.pop, ran.pop])
  end

  test "post after close raises Dexpace::ClosedError, never ::ClosedQueueError" do
    pool = build(size: 1)
    pool.close

    error = assert_raises(Dexpace::ClosedError) { pool.post { nil } }
    refute_kind_of(::ClosedQueueError, error)
  end

  test "close reports not-drained when the budget is spent, off the injected clock and with no real waiting" do
    stub_clock = Dexpace::StubClock.new
    sink = Dexpace::RecordingSink.new
    # shutdown_timeout: 0.0 is the one budget a fake clock can drive end to end. The drain computes
    # `deadline - clock.monotonic` FIRST and returns before touching @exits when that is <= 0, so
    # the timed-out branch runs with no queue wait at all -- which is exactly what the design says a
    # fake clock can exercise and a real one cannot ("no fake clock makes a real queue wake early").
    # A stuck worker is still present, so the branch is reached for the right reason.
    pool = build(size: 1, shutdown_timeout: 0.0, clock: stub_clock,
                 logger: Dexpace::Instrumentation::Logger.build(sink: sink))
    gate = ::Thread::Queue.new
    pool.post { gate.pop } # never released -- simulates an uninterruptible send

    closer = ::Thread.new { pool.close }

    assert(closer.join(2), "close blocked on a spent budget instead of returning")
    shutdown = sink.entries.find do |e|
      e.payload.is_a?(Hash) &&
        e.payload[Dexpace::Instrumentation::Keys::EVENT] ==
          Dexpace::Instrumentation::Events::INSTRUMENTATION_SHUTDOWN
    end
    refute_nil(shutdown)
    assert_equal(false, shutdown.payload["dexpace.executor.drained"],
                 "the drain must report the budget as spent, not as a clean shutdown")

    gate << :go # release the stuck task so the worker exits and the suite leaks no thread
  end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread/pool_test.rb`
Expected: FAIL on every new test — `NotImplementedError: Pool includes Dexpace::Closeable and must
define a private #release` (`Dexpace::Closeable`'s default).

- [ ] **Step 3: Write `#release` and the drain**

Add to `Pool`, in the `private` section, after `#run`:

```ruby
        # Dexpace::Closeable's latch calls this on the winning #close only, and only after the
        # @closed flip -- the mutex is never held here (design's Thread-safety table).
        def release
          deadline = @clock.monotonic + @shutdown_timeout
          @queue.close # stop accepting; queued work still drains (verified fact 3 / this plan's fact 2)
          # Task 7 inserts `stop_timer(deadline)` here, once Timer exists: it fails every
          # outstanding #delay with Dexpace::ClosedError and joins the timer thread inside this
          # same budget. One deadline serves both waits, so the whole close is bounded by
          # shutdown_timeout rather than by shutdown_timeout per resource.
          drained = drain_workers(deadline)
          Dexpace::Instrumentation.contain(@logger, event: Dexpace::Instrumentation::Events::INSTRUMENTATION_LOG) do
            @logger.event(Dexpace::Instrumentation::Severity::INFO)
                   .event(Dexpace::Instrumentation::Events::INSTRUMENTATION_SHUTDOWN)
                   .field(WORKER_COUNT_FIELD, @size)
                   .field(DRAINED_FIELD, drained)
                   .emit
          end
          nil
        end

        # Bounded, sentinel-carrying: @exits.pop's return alone cannot distinguish "the budget
        # elapsed" from "the queue closed" from "a worker actually exited" (verified fact 4 /
        # this plan's fact -- Thread::Queue#pop returns nil for all three), so the clock is
        # re-read on every iteration rather than trusted to the pop's return value.
        def drain_workers(deadline)
          remaining = @size
          while remaining.positive?
            budget = deadline - @clock.monotonic
            return false if budget <= 0

            exited = @exits.pop(timeout: budget)
            return false if exited.nil? && @clock.monotonic >= deadline

            remaining -= 1 if exited
          end
          true
        end
```

- [ ] **Step 4: Update the `sig/` file**

`sig/dexpace/async/thread/pool.rbs` already declares `include Dexpace::Closeable`, which is where
`#close`/`#closed?`/`#owned?` come from — phase 2's `sig/` carries those signatures and restating
them here would put two declarations of one method into the tree `gates:sig_diff` compares. No
change needed beyond what Task 4 already wrote.

- [ ] **Step 5: Run the tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread/pool_test.rb`
Expected: PASS. `Timer` does not exist at this point and nothing here references it — Task 7 adds
the file, the ivar and the `stop_timer(deadline)` line into `#release` together, so no task in this
plan ships a call to a class that is not there and no step needs a temporary stub. Then
`bundle exec rake rubocop rbs:validate steep`.

- [ ] **Step 6: The `SEAM-25`/`ASYNC-15`(b) assertion, at the bridge rather than the pool**

Add one test proving the pool has *no* second entry point and the bridge's `owned: false` is what
discharges the ownership-aware clause (needs Task 8's bridge fixtures; note it here and move it
into Task 8's file rather than duplicating the pool construction):

```ruby
  # Moved to bridge_test.rb (Task 8): "Transport.async_over(fake, executor: pool).close leaves the
  # pool open and usable" is ASYNC-15(b) and XCUT-22, and it needs the bridge to exist.
```

---

## Task 7: `Dexpace::Async::Thread::Timer` and `Pool#delay`

**Requirement IDs:** `ASYNC-18`. **Design:** "`R11` — `ASYNC-18`'s non-blocking scheduled delay,
with no `Fiber.scheduler`"; deviation `P8-25`; "Thread-safety proof obligations."

**Files:**
- Create: `gems/dexpace-async-thread/lib/dexpace/async/thread/timer.rb`
- Modify: `gems/dexpace-async-thread/lib/dexpace/async/thread/pool.rb`
  (the `require_relative`, the `@timer` ivar and `#release`'s `stop_timer` line — the three Tasks 4
  and 6 deliberately left out), `gems/dexpace-async-thread/sig/dexpace/async/thread/pool.rbs`.
  **`lib/dexpace/async/thread.rb` is not touched**: `Timer` is a `private_constant` reached through
  `pool.rb`'s own `require_relative`.
- Test: `gems/dexpace-async-thread/test/dexpace/async/thread/pool_delay_test.rb`

`Timer` is `private_constant`: no `sig/` file, no runtime-surface-manifest row (7c's
`Page::LinkHeader` is the precedent for a file with no public constant at all).

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# ASYNC-18's four clauses, and the timer's own lifecycle (R11, P8-25).
class PoolDelayTest < DexpaceTestCase
  Pool = Dexpace::Async::Thread::Pool

  def teardown
    @pool&.close
  end

  def build(**kwargs)
    @pool = Pool.build(size: 1, **kwargs)
  end

  def timer_threads
    ::Thread.list.select { |t| t.name&.end_with?(" timer") }
  end

  test "a negative delay raises before any timer thread exists" do
    pool = build
    before = ::Thread.list.size

    assert_raises(Dexpace::InvalidArgumentError) { pool.delay(-1) }
    assert_equal(before, ::Thread.list.size)
  end

  test "a zero delay settles immediately and spawns no timer thread" do
    pool = build

    future = pool.delay(0)

    assert(future.settled?)
    assert_nil(future.value)
    assert_empty(timer_threads)
  end

  test "a positive delay settles after at least the interval, and spawns exactly one named timer thread" do
    pool = build
    started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)

    future = pool.delay(0.05)
    future.value
    elapsed = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started

    assert_operator(elapsed, :>=, 0.04)
    assert_equal(1, timer_threads.size)
  end

  test "three concurrent delays fire in deadline order on one shared timer thread" do
    pool = build
    order = ::Thread::Queue.new

    pool.delay(0.10).on_settle { order << :b }
    pool.delay(0.05).on_settle { order << :a }
    pool.delay(0.15).on_settle { order << :c }

    # Three blocking pops, no sleep: the queue IS the wait, and the order they arrive in is the
    # assertion. A sleep here would only decide how long the test takes to fail.
    assert_equal(%i[a b c], [order.pop, order.pop, order.pop])
    assert_equal(1, timer_threads.size)
  end

  test "cancelling a future removes the entry so it never fires via on_fire, and the future stays cancelled" do
    pool = build
    future = pool.delay(0.05)

    # #delay takes no block (ASYNC-18 settles with nil, never a value) and on_settle fires on ANY
    # settlement including a cancellation, so neither is the right probe for "never fires". The
    # real assertion: after the interval elapses, the future is still cancelled -- not
    # overwritten by a late #fulfil from a timer entry that should have been removed -- and
    # #value raises CancelledError rather than returning nil.
    future.cancel(:no_longer_needed)

    # Waiting past the cancelled entry's own deadline WITHOUT a sleep: schedule a later delay on
    # the same timer and block on it. When the sentinel settles, the cancelled entry's deadline is
    # provably in the past and the same single timer thread has run through it -- which a sleep
    # only approximates, and approximates worse on a loaded machine.
    pool.delay(0.10).value

    assert(future.cancelled?)
    error = assert_raises(Dexpace::CancelledError) { future.value }
    assert_equal(:no_longer_needed, error.reason)
  end

  test "close fails every outstanding delay with Dexpace::ClosedError" do
    pool = build
    future = pool.delay(10.0)

    pool.close

    assert(future.settled?)
    assert_raises(Dexpace::ClosedError) { future.value }
  end

  test "a pool that never scheduled a positive delay has no timer thread to stop" do
    pool = build
    pool.close

    assert_empty(timer_threads)
  end

  test "two fibers of one thread both call #delay and #cancel under a probe scheduler; neither deadlocks" do
    pool = build
    scheduler = Dexpace::ProbeScheduler.new
    outcomes = []

    ::Thread.new do
      ::Fiber.set_scheduler(scheduler)
      first = ::Fiber.schedule do
        future = pool.delay(0.05)
        future.value
        outcomes << :first_settled
      end
      second = ::Fiber.schedule do
        future = pool.delay(0.20)
        future.cancel
        outcomes << :second_cancelled
      end
      ::Fiber.scheduler.close
    end.join

    assert_equal(%i[first_settled second_cancelled].sort, outcomes.sort)
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread/pool_delay_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'delay'`.

- [ ] **Step 3: Write `lib/dexpace/async/thread/timer.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Async
    module Thread
      # R11's implementation. One lazily created ::Thread per instance, named "<name> timer",
      # parked on a bounded wake queue against the nearest deadline; never as a value channel
      # (design's own reason for the pivot's wake-up queue, and this repository's third
      # load-bearing appearance of Thread::Queue#pop's nil ambiguity). Knows nothing about
      # Completer or ClosedError: #schedule takes two opaque callbacks so the caller (Pool)
      # decides what "fired" and "shut down" mean.
      #
      # private_constant of Dexpace::Async::Thread: no public constant, no sig/ file, no
      # runtime-surface-manifest row.
      class Timer
        Entry = ::Data.define(:deadline, :on_fire, :on_shutdown)
        private_constant :Entry

        def initialize(name)
          @name = name
          @mutex = ::Thread::Mutex.new
          @entries = []
          @wake = ::Thread::Queue.new
          @thread = nil
        end

        # @return [Object] an opaque handle for #cancel
        def schedule(delay, on_fire:, on_shutdown:)
          entry = Entry.new(deadline: monotonic + delay, on_fire: on_fire, on_shutdown: on_shutdown)
          @mutex.synchronize do
            @entries << entry
            @entries.sort_by!(&:deadline)
            @thread ||= spawn_thread
          end
          wake
          entry
        end

        def cancel(entry)
          @mutex.synchronize { @entries.delete(entry) }
          wake
          nil
        end

        # Stops the timer thread, if one was ever spawned (a pool that only ever scheduled zero
        # delays never spawns one), and fails every entry that never fired through its own
        # on_shutdown callback rather than firing it -- ASYNC-18's "no scheduler thread is held"
        # applied to shutdown, and design's "not completed early".
        #
        # The join is BOUNDED by the caller's remaining budget and never a bare #join: XCUT-13 and
        # design §3.7 forbid an unbounded wait in a close path for this gem by name ("close signals
        # its queue and returns, it does not join workers under a Kernel#sleep or an unbounded
        # Thread#join"), and the timer is one of the pool's owned resources, not an exception to it.
        # The entries are failed whether or not the join completed: a caller blocked in #value on a
        # delay that will never fire is the one outcome worse than a slow close.
        def stop(timeout)
          @wake.close
          @thread&.join(timeout)
          leftover = @mutex.synchronize { @entries.dup }
          leftover.each { |entry| entry.on_shutdown.call }
          nil
        end

        private

        def monotonic = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)

        def spawn_thread
          ::Thread.new { run }.tap { |t| t.name = "#{@name} timer" }
        end

        def wake
          @wake.push(:recompute)
        rescue ::ClosedQueueError
          nil
        end

        # The mutex is held across a list insert, a list delete and a `first` read only -- never
        # across #pop(timeout:), the entry's on_fire/on_shutdown callback, or a Completer settle
        # (design's Thread-safety proof obligations table).
        def run
          loop do
            next_deadline = @mutex.synchronize { @entries.first&.deadline }
            remaining = next_deadline ? [next_deadline - monotonic, 0].max : nil
            @wake.pop(timeout: remaining)
            break if @wake.closed?

            due = @mutex.synchronize do
              now = monotonic
              ready, keep = @entries.partition { |entry| entry.deadline <= now }
              @entries = keep
              ready
            end
            due.each { |entry| entry.on_fire.call }
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Add `#delay` to `Pool`**

```ruby
        # ASYNC-18's non-blocking scheduled delay. Backed by the pool's one lazily created Timer
        # thread, shared across every outstanding delay. Settles with nil, not a duration or a
        # timestamp -- the primitive's whole content is "later", matching CFG-18's
        # Dexpace::Async.delay so the two are interchangeable at the call site.
        #
        # "Without blocking a thread" holds for the caller's thread and every pool worker, and not
        # absolutely: one named timer thread is parked for the interval (P8-25). A caller running
        # under a Fiber.scheduler and wanting the zero-thread reading uses
        # Dexpace::Async.delay instead -- unavailable to a pool worker regardless, since
        # Fiber.scheduler is per-thread (design verified fact 15).
        #
        # @raise [Dexpace::InvalidArgumentError] for a negative duration, before any timer thread
        #   is created
        # @raise [Dexpace::ClosedError] if the pool is closed
        def delay(duration)
          unless duration.is_a?(::Numeric)
            raise Dexpace::InvalidArgumentError, "duration must be Numeric, got #{duration.class}"
          end
          raise Dexpace::InvalidArgumentError, "duration must not be negative" if duration.negative?
          raise Dexpace::ClosedError, "#{@name} is closed" if closed?

          completer = Dexpace::Async::Completer.new
          if duration.zero?
            completer.fulfil(nil)
            return completer.future
          end

          entry = @timer.schedule(
            duration,
            on_fire: -> { completer.fulfil(nil) },
            on_shutdown: -> { completer.fail(Dexpace::ClosedError.new("#{@name} is closed")) },
          )
          completer.on_cancel { @timer.cancel(entry) }
          completer.future
        end
```

Place it in the public section, after `#post`.

- [ ] **Step 4b: Wire `Timer` into `Pool`'s construction and its close**

Three one-line edits to `lib/dexpace/async/thread/pool.rb`, all of them the lines Tasks 4 and 6
deliberately left out because `Timer` did not exist yet:

```ruby
require_relative "timer"                                     # beside require_relative "rejected_error"

          @timer = Timer.new(name)                           # in #initialize, before @workers

          stop_timer(deadline)                               # in #release, after @queue.close
```

and the private helper it names, beside `#drain_workers`:

```ruby
        # The timer shares the workers' single close budget rather than getting one of its own, so
        # `#close` is bounded by shutdown_timeout in total (design: "within the same
        # DEFAULT_SHUTDOWN_TIMEOUT budget as the workers").
        def stop_timer(deadline)
          @timer.stop([deadline - @clock.monotonic, 0.0].max)
        end
```

- [ ] **Step 5: Update the two `sig/` files**

`sig/dexpace/async/thread/pool.rbs` gains:

```rbs
        def delay: (Numeric duration) -> Dexpace::Async::Future
```

`Timer` gets no `sig/` file (`private_constant`).

- [ ] **Step 6: Confirm the require chain**

`Timer` is reached through `pool.rb`'s own `require_relative "timer"` (Step 4b), not through the
entry file: it is a `private_constant` of `Dexpace::Async::Thread` and the entry file requires only
the gem's public constants. Confirm `lib/dexpace/async/thread.rb` is **unchanged** by this task and
that `gates:require_allowlist` stays clean — a `require_relative` inside `lib/` is checked for
escaping the gem's `lib/`, which this one does not.

- [ ] **Step 7: Run the tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread/pool_delay_test.rb`
Expected: PASS, 8 runs. The two-fiber test is the load-bearing one: it is the only shape that
proves `Timer`'s mutex is not held across a suspension point — a single-threaded test and a
two-**thread** test both pass under a bug this test would catch, because thread-level mutex
ownership would be correct in both. Then `bundle exec rake rubocop rbs:validate steep`.

- [ ] **Step 8: The break-it proof for the timer's mutex scope**

Temporarily widen `run`'s critical section to wrap `@wake.pop(timeout: remaining)` inside the
`@mutex.synchronize` block. Run the two-fiber test again.
Expected: `ThreadError: deadlock; lock already owned by another fiber belonging to the same thread`
(verified fact 9), or the test hangs — either way, red. Restore the narrow critical section;
confirm green.

---

## Task 8: The bridge end to end, `ASYNC-6`/`PIPE-33`'s cross-reference rows, and `ASYNC-7`

**Requirement IDs:** `ASYNC-1`, `ASYNC-5`, `ASYNC-7`, `ASYNC-13`, `ASYNC-14`, `ASYNC-19`,
`ASYNC-20`; cross-reference rows `PIPE-33` and `ASYNC-6`; `ASYNC-3` (⏳, `DEF-18`) and `ASYNC-4`
(N/A) demonstrated rather than newly decided. **Design:** "How a unit of work reaches the pivot,
how a caller awaits it, and where the deadlines are"; "`R10`"; "The two cross-reference rows, with
no budget line"; testing strategy groups 6 and 7 (the concurrency half moves to Task 10).

**Files:**
- Test: `gems/dexpace-async-thread/test/dexpace/async/thread/bridge_test.rb`

No new `lib/` code: every mechanism this task exercises (`Completer`, `Future`,
`Transport.async_over`, `AsyncTransport.sync_over`) is phase 2's, already shipped. This is the
first sub-phase that can drive it end to end over a real worker rather than `InlineExecutor` or a
synchronous fake.

**This task has no ordinary red phase, for the same reason Task 5 does not, and the substitute is
the same.** There is no new implementation for a test to be red against; what makes these
assertions real rather than decorative is Step 3's break-it proof, which shows the composition test
distinguishing a correct implementation from a plausible wrong one. A test that has only ever been
seen to pass has not been tested against failure — that rule is what replaces red-first here, and it
is not an exemption from it.

- [ ] **Step 1: Write the tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/fake_transport"
require_relative "../../../support/counting_response"

# ASYNC-1, ASYNC-5, ASYNC-13, ASYNC-14, ASYNC-19, ASYNC-20; PIPE-33 clauses 2-4; ASYNC-6's stated
# cross-reference; ASYNC-3's mitigation (R10) and ASYNC-4's vacuity, demonstrated rather than
# re-decided. Every "slow"/"stuck" task in this suite is a Thread::Queue gate the test controls;
# no sleep decides an assertion.
class BridgeTest < DexpaceTestCase
  Pool = Dexpace::Async::Thread::Pool

  def teardown
    @pool&.close
  end

  def build(size: 2)
    @pool = Pool.build(size: size)
  end

  test "ASYNC-1: delivers the exact Response object, through a real worker" do
    pool = build
    response = Object.new
    transport = Dexpace::FakeTransport.new(response: response)
    async = Dexpace::Transport.async_over(transport, executor: pool)

    future = async.call(:request, nil, nil)

    assert_same(response, future.value)
  end

  test "ASYNC-2/ASYNC-13: a raised failure arrives as the identical exception object" do
    pool = build
    boom = ::IOError.new("connection reset")
    transport = Dexpace::FakeTransport.new(raises: boom)
    async = Dexpace::Transport.async_over(transport, executor: pool)

    future = async.call(:request, nil, nil)

    caught = assert_raises(::IOError) { future.value }
    assert_same(boom, caught, "ASYNC-13: no wrapper exists, so unwrap is the identity function")
  end

  test "ASYNC-2: submitting through a closed pool settles the future exceptionally, never raising synchronously from #call" do
    pool = build
    pool.close
    transport = Dexpace::FakeTransport.new(response: :ok)
    async = Dexpace::Transport.async_over(transport, executor: pool)

    future = async.call(:request, nil, nil)

    assert_raises(Dexpace::ClosedError) { future.value }
  end

  test "ASYNC-19: the exact RequestOptions object arrives at the wrapped transport, across the hop" do
    pool = build
    options = Dexpace::RequestOptions::EMPTY
    transport = Dexpace::FakeTransport.new(response: :ok)
    async = Dexpace::Transport.async_over(transport, executor: pool)

    async.call(:request, options, nil).value

    assert_same(options, transport.calls.first[1])
  end

  test "ASYNC-5: cancel in the window after the worker produces a Response but before delivery closes it exactly once" do
    pool = build(size: 1)
    response = Dexpace::CountingResponse.new
    source = Dexpace::Cancellation.source
    gate = ::Thread::Queue.new
    transport = Dexpace::FakeTransport.new(response: response, gate: gate)
    async = Dexpace::Transport.async_over(transport, executor: pool)

    future = async.call(:request, nil, source.token)
    source.cancel(:too_late) # cancel BEFORE the worker's #call returns
    gate << :go # now let the transport return the response

    assert_raises(Dexpace::CancelledError) { future.value }
    assert_equal(1, response.closes)
  end

  test "ASYNC-20: cancelling AFTER delivery never closes the delivered response" do
    pool = build
    response = Dexpace::CountingResponse.new
    transport = Dexpace::FakeTransport.new(response: response)
    async = Dexpace::Transport.async_over(transport, executor: pool)

    future = async.call(:request, nil, nil)
    delivered = future.value
    future.cancel(:too_late)

    assert_same(response, delivered)
    assert_equal(0, response.closes)
  end

  test "ASYNC-3 (DEF-18)/ASYNC-5: cancelling while queued still lets the task run, and the orphan closes exactly once" do
    pool = build(size: 1)
    occupy_gate = ::Thread::Queue.new
    pool.post { occupy_gate.pop } # occupy the one worker so the second unit stays queued

    response = Dexpace::CountingResponse.new
    source = Dexpace::Cancellation.source
    transport = Dexpace::FakeTransport.new(response: response)
    async = Dexpace::Transport.async_over(transport, executor: pool)

    future = async.call(:request, nil, source.token)
    source.cancel(:gave_up_while_queued)
    occupy_gate << :go

    assert_raises(Dexpace::CancelledError) { future.value }
    assert_equal(1, response.closes, "SEAM-30/ASYNC-5: no response reaches a cancelled caller")
    # ASYNC-3's third clause: nothing is ever interrupted, and this port never claims it aborted
    # the queued task before it ran -- it ran, and the orphan close is what closes the gap.
  end

  test "ASYNC-14: AsyncTransport.sync_over round-trips and surfaces CancelledError, not ::IOError" do
    pool = build
    gate = ::Thread::Queue.new
    entered = ::Thread::Queue.new
    transport = Dexpace::FakeTransport.new(response: :never, gate: gate, entered: entered)
    async = Dexpace::Transport.async_over(transport, executor: pool)
    sync = Dexpace::AsyncTransport.sync_over(async)
    source = Dexpace::Cancellation.source

    # The canceller waits on the double's `entered` queue, not on a clock: it fires once the worker
    # is provably inside #call and blocked on the gate. A sleep here would be a guess that the
    # worker had started, and a slow machine would turn the guess into a flake.
    canceller = ::Thread.new { entered.pop; source.cancel(:interrupted) }
    error = assert_raises(Dexpace::CancelledError) { sync.call(:request, nil, source.token) }
    canceller.join
    gate << :go # release the worker so it does not linger past the test

    assert_equal(:interrupted, error.reason)
  end

  test "ASYNC-17: a lambda-shaped async transport's #close is a safe no-op" do
    lambda_transport = ->(_r, _o, _c) { :ok }
    async = Dexpace::Transport.async_over(lambda_transport, executor: InlineExecutorForBridgeTest.new)

    assert_nil(async.close)
  end

  test "ASYNC-15(b)/XCUT-22: closing the bridge does not close the pool" do
    pool = build
    transport = Dexpace::FakeTransport.new(response: :ok)
    async = Dexpace::Transport.async_over(transport, executor: pool)

    async.close

    refute(pool.closed?, "ASYNC-15(b): the pool is the caller's; the bridge never owns it")
    assert_equal(:ok, async.call(:request, nil, nil).value)
  end

  # PIPE-33 clause 2 is "runs the wrapped synchronous pipeline as a single opaque unit on that
  # executor ... its own steps stay synchronous on the worker thread and do NOT gain per-step
  # concurrency" (appendix C:221). A bare transport cannot show that: with no steps there is
  # nothing that could have been posted per-step, so the count of 1 proves nothing. The unit under
  # test is a MULTI-STEP pipeline, and the count is of #post calls -- not of transport calls --
  # because #post is where per-step concurrency would appear if the clause were violated.
  #
  # Implementer's note, the same one Task 9 carries: 4c ships `Pipeline.builder(transport:)` with
  # `#append`/`#build` and `Pipeline.direct(transport)` (4c design :767, :1078), and the exact Entry
  # construction for a probe step must be matched against 4c's landed signatures at execution time.
  # The SHAPE is what this plan pins: two steps, one #post, the identical options object.
  test "PIPE-33 clauses 2-3: a whole multi-step Dexpace::Pipeline posts exactly once, and options thread through" do
    pool = build
    posts = ::Thread::Queue.new
    counting = CountingExecutorForBridgeTest.new(pool, posts)
    options = Dexpace::RequestOptions::EMPTY
    transport = Dexpace::FakeTransport.new(response: :ok)
    pipeline = Dexpace::Pipeline.builder(transport: transport)
                                .append(probe_step(:first))
                                .append(probe_step(:second))
                                .build
    async = Dexpace::Transport.async_over(pipeline, executor: counting)

    async.call(:request, options, nil).value

    assert_equal(1, counting.count, "clause 2: one #post for the whole pipeline, not one per step")
    assert_equal(1, transport.calls.size)
    assert_same(options, transport.calls.first[1], "clause 3: the caller's options reach the send")
  end

  test "ASYNC-7: an in-flight blocking read that ignores cancellation runs to completion" do
    pool = build(size: 1)
    gate = ::Thread::Queue.new
    response = Dexpace::CountingResponse.new
    transport = Dexpace::FakeTransport.new(response: response, gate: gate, ignores_cancellation: true)
    async = Dexpace::Transport.async_over(transport, executor: pool)
    source = Dexpace::Cancellation.source

    future = async.call(:request, nil, source.token)
    source.cancel(:abandoned)
    gate << :go # the worker's #call returns AFTER the cancel, as it would for an uncooperative read

    # The read ran to completion (the gate had to open); the response is closed as an orphan
    # rather than delivered, which is ASYNC-3's mitigation and not a contradiction of "runs to
    # completion" -- the transport's OWN work finished, the SDK's delivery did not.
    assert_raises(Dexpace::CancelledError) { future.value }
    assert_equal(1, response.closes)
  end

  class InlineExecutorForBridgeTest
    def post(&block) = block.call
  end

  # Delegates to the real pool and counts, so PIPE-33 clause 2 is asserted on #post itself rather
  # than inferred from the transport's call count. #post's signature is Dexpace::Page::_Executor's
  # exactly here too -- a counting wrapper that widened it would not be testing what runs.
  class CountingExecutorForBridgeTest
    def initialize(pool, posts)
      @pool = pool
      @posts = posts
    end

    def post(&block)
      @posts << :posted
      @pool.post(&block)
    end

    def count = @posts.size
  end

  # A no-op step, so the pipeline is genuinely multi-step without the test asserting anything about
  # what a step does. 4c's adapter is `Dexpace::Pipeline::TransformStep.build(transform)`, where
  # `transform` answers `#phase` (`:request` or `:response`) and `#apply` (4c design :808-832) --
  # `#append`'s own Entry construction is the part to match against 4c's landed signatures at
  # execution time.
  IdentityTransform = ::Struct.new(:phase) do
    def apply(request, _cursor) = request
  end

  def probe_step(_name)
    Dexpace::Pipeline::TransformStep.build(IdentityTransform.new(:request))
  end
end
```

- [ ] **Step 2: Run them to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread/bridge_test.rb`
Expected: PASS, 12 runs. Every mechanism under test is phase 2's, already shipped and reviewed —
this task's proof is that the composition works over a real pool, not that the mechanism is new.

- [ ] **Step 3: The break-it proof for `ASYNC-19`**

In a scratch copy, if `Dexpace::Bridge::AsyncOver#deliver` dropped `options` from its wrapped call
(it does not; this is a read-only proof that the assertion is real), the "exact RequestOptions
object" test would fail on `assert_same`. Confirm by temporarily stubbing `FakeTransport#call` to
ignore its second argument and assert against a freshly-built `RequestOptions` instead of
`assert_same` — the substitute assertion passes even with options dropped, which is exactly why
`assert_same` and not `assert_equal` is what the real test uses. Revert the scratch copy; this step
does not modify the committed test.

---

## Task 9: `Dexpace::Page::_Executor` conformance, driven by `AsyncPaginator`

**Requirement IDs:** none new (`NFR-3`/`NFR-11` surface `8b` inherits from `7c`).
**Design:** "`Dexpace::Page::_Executor`: the interface is core's and `#post` is exactly it, not a
superset."

**Files:**
- Test: `gems/dexpace-async-thread/test/dexpace/async/thread/page_executor_test.rb`

- [ ] **Step 1: Write the test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/fake_transport"

# Proves Pool#post satisfies Dexpace::Page::_Executor AS 7c's code uses it, not as respond_to?
# reports it -- the interface is core-declared (gems/dexpace-core/sig/dexpace/page/strategy.rbs)
# and 8b did not write it (NFR-3/NFR-11's surface this gem inherits).
class PageExecutorTest < DexpaceTestCase
  Pool = Dexpace::Async::Thread::Pool

  def teardown
    @pool&.close
  end

  test "AsyncPaginator drives a two-page walk with the pool as its executor" do
    @pool = Pool.build(size: 2)
    responses = [Dexpace::Response.new(status: Dexpace::Status::OK, headers: Dexpace::Headers::EMPTY, body: nil)] * 2
    call_count = 0
    transport = ->(_request, _options, _cancellation) do
      response = responses[call_count]
      call_count += 1
      response
    end
    strategy = ->(_response, _template) { Dexpace::Page::Info.build(items: [], next_link: nil) }

    paginator = Dexpace::Page::AsyncPaginator.build(
      transport: transport,
      template: Dexpace::Request.build(method: :get, url: "https://example.test/items"),
      strategy: strategy,
      executor: @pool,
    )

    items = ::Thread::Queue.new
    future = paginator.walk(->(item) { items << item })
    future.value

    assert(future.settled?)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails, then passes**

Run: `bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread/page_executor_test.rb`
Expected: FAILs first if `Dexpace::Page::AsyncPaginator`/`Dexpace::Page::Info` are not yet
present in this checkout (phase 7 landed before phase 8 per the roadmap's recommended order; if
this checkout is genuinely phase-7-complete, adjust the test's fixture construction to match 7c's
actual shipped `Info`/`Request` builder signatures exactly, which this plan cannot pin further
without reading the landed source). Once the fixture matches the shipped API: PASS, 1 run,
confirming `#post`'s signature is `_Executor` exactly — no keyword, zero-arity block, no second
`post`-shaped method.

**Note for the implementer:** this task's exact fixture calls (`Dexpace::Response.build`,
`Dexpace::Page::Info.build`, `Dexpace::Request.build`) must be checked against phase 7c's actually
landed signatures at execution time; this plan pins the *shape* of the conformance proof (drive a
real `AsyncPaginator` with the pool as `executor:`) rather than the exact keyword list of a gem this
sub-phase does not own.

---

## Task 10: The concurrency proof suite

**Requirement IDs:** none new (`XCUT-11`, `SEAM-12` — phase 9's evidence, named by the design's
"The interface surface later phases may cite").
**Design:** "Thread-safety proof obligations"; "The other concurrency assertions, each naming what
it would catch."

**Files:**
- Test: `gems/dexpace-async-thread/test/dexpace/async/thread/pool_concurrency_test.rb`

- [ ] **Step 1: Write the tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# XCUT-11, SEAM-12: concurrency safety asserted, not argued. Five properties, each naming what it
# would catch.
class PoolConcurrencyTest < DexpaceTestCase
  Pool = Dexpace::Async::Thread::Pool

  test "post from many threads at once: accepted + rejected == submitted, every accepted job runs exactly once" do
    size = 2
    queue_limit = size * Pool::QUEUE_DEPTH_PER_WORKER
    pool = Pool.build(size: size, queue_limit: queue_limit)
    submitted = size * queue_limit * 2
    ran = ::Thread::Queue.new
    accepted = 0
    rejected = 0
    mutex = ::Thread::Mutex.new

    threads = ::Array.new(16) do
      ::Thread.new do
        (submitted / 16).times do
          begin
            pool.post { ran << :one }
            mutex.synchronize { accepted += 1 }
          rescue Dexpace::Async::Thread::RejectedError
            mutex.synchronize { rejected += 1 }
          end
        end
      end
    end
    threads.each(&:join)

    # Close FIRST: #close drains what is queued (ASYNC-16), so after it returns every accepted job
    # has run and the count below is a drain rather than a race against the workers. Counting first
    # and closing after would make `accepted == total_ran` a statement about how fast the machine
    # is. The bounded pop is a drain of an already-quiet queue, not a wait for work.
    pool.close
    total_ran = 0
    total_ran += 1 while ran.pop(timeout: 0.5)

    assert_equal(accepted, total_ran, "a lost job or a double-run")
    assert_equal(submitted, accepted + rejected)
  end

  test "close from 16 threads at once: exactly one event, every call returns" do
    sink = Dexpace::RecordingSink.new
    pool = Pool.build(size: 2, logger: Dexpace::Instrumentation::Logger.build(sink: sink))

    results = ::Array.new(16) { ::Thread.new { pool.close } }.map { |t| t.join(5) }

    refute_includes(results, nil, "a close call never returned -- the latch is not a real latch")
    shutdown_events = sink.entries.count { |e| e.payload.is_a?(Hash) && e.payload[Dexpace::Instrumentation::Keys::EVENT] == Dexpace::Instrumentation::Events::INSTRUMENTATION_SHUTDOWN }
    assert_equal(1, shutdown_events)
  end

  test "post racing close: every call succeeds or raises Dexpace::ClosedError, never ::ClosedQueueError" do
    pool = Pool.build(size: 2, queue_limit: 32)
    errors = ::Thread::Queue.new
    posting = ::Thread::Queue.new
    poster = ::Thread.new do
      loop do
        pool.post { nil }
        posting << :posted
      rescue Dexpace::ClosedError
        break
      rescue Dexpace::Async::Thread::RejectedError
        posting << :rejected
        next
      rescue => e
        errors << e
        break
      end
    end
    # Close only once the poster is provably in its loop -- a condition, not a sleep. Without this
    # the close can win before the first #post and the race the test exists for never happens.
    posting.pop
    pool.close
    poster.join(5)

    assert(errors.empty?, "a bare stdlib error escaped: #{errors.pop&.class}")
  end

  test "post from inside a task returns rather than deadlocking, and raises RejectedError when full" do
    pool = Pool.build(size: 1, queue_limit: 1)
    result = ::Thread::Queue.new

    pool.post do
      begin
        pool.post { nil } # the queue has room for exactly this one
        result << :accepted
      rescue Dexpace::Async::Thread::RejectedError
        result << :rejected
      end
    end

    assert_includes(%i[accepted rejected], result.pop(timeout: 2))
    pool.close
  end

  test "20 build-and-close cycles of a three-worker pool leave Thread.list.size unchanged" do
    before = ::Thread.list.size

    20.times do
      pool = Pool.build(size: 3)
      pool.post { nil }
      pool.close
    end

    assert_equal(before, ::Thread.list.size)
  end
end
```

- [ ] **Step 2: Run them to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-async-thread/test/dexpace/async/thread/pool_concurrency_test.rb`
Expected: PASS, 5 runs. Then run the whole gem's suite once more: `(cd gems/dexpace-async-thread &&
bundle exec rake test)`.

- [ ] **Step 3: The break-it proofs — this task ships no new `lib/` code, so these are its red phase**

Three, each restored immediately, and each aimed at the assertion the design says a plausible wrong
implementation would pass:

1. Delete the `rescue ::ClosedQueueError` arm in `#post`. Expected: the post-racing-close test goes
   red with a bare `::ClosedQueueError` in `errors` — which is the assertion proving the stdlib
   error is translated on *every* path and not only the one the happy test takes.
2. Replace `@queue.push(job, true)` with the blocking `@queue << job`. Expected: the
   post-from-inside-a-task test stops returning (a worker parks waiting for a worker) and its
   `result.pop(timeout: 2)` returns `nil` — `P8-23`'s fourth reason, demonstrated rather than argued.
3. In a scratch copy, replace `Dexpace::Closeable`'s latch with a plain `return if @closed; @closed
   = true` (no mutex). Expected: the sixteen-way close test goes red with **more than one**
   shutdown event — "a latch that is a flag check rather than a latch", which is `ASYNC-15`(a) and
   `SEAM-25`'s "close twice → executor shut once, one event". Do not break it by removing the
   worker's exit sentinel instead: that variant costs a full `shutdown_timeout` per cycle and would
   run for ten minutes before going red, which is a proof nobody re-runs.

---

## Task 11: `sig/` completion, the RBS baseline diff, and the runtime surface snapshot

**Requirement IDs:** none new (`NFR-3`, `NFR-4`, `NFR-11`).
**Design:** "The `sig/` shape."

**Files:**
- Modify: `gems/dexpace-async-thread/sig/dexpace/async/thread.rbs`,
  `gems/dexpace-async-thread/sig/dexpace/async/thread/pool.rbs`

- [ ] **Step 1: Confirm the whole `sig/` tree matches `lib/`**

Every public constant (`VERSION`, `CORE_REQUIREMENT`, `RejectedError`, `Pool`) has a `sig/` mirror;
`Job` and `Timer` are `private_constant` and have neither, which `gates:rbs_surface` and
`gates:surface_snapshot` both confirm rather than assume — `Data.define`'s generated readers on
`Job` are invisible to `rbs validate`, and `Job` being `private_constant` means it should appear in
**neither** artifact.

- [ ] **Step 2: Run `rbs validate` and `steep check`**

Run: `bundle exec rake rbs:validate steep`
Expected: clean. `include Dexpace::Closeable` in `Pool`'s `sig/` means `#close`/`#closed?`/
`#owned?` are visible to a consumer's own `steep check` without a second declaration.

- [ ] **Step 3: Confirm `NFR-11`'s scan**

Run: `bundle exec rake gates:rbs_surface`
Expected: clean. No constant outside `Dexpace::` appears anywhere in `sig/dexpace/async/thread*`
— not `::Thread`, not `::Thread::SizedQueue`, not `::Fiber`. `#size`/`#queue_limit`/`#name` return
the `Integer`/`String`s the caller passed, never a foreign-typed accessor.

- [ ] **Step 4: Regenerate BOTH the RBS baseline and the runtime surface snapshot**

Run: `bundle exec rake surface:regenerate`, then diff.
Expected: the diff shows only **additions** — `VERSION`, `CORE_REQUIREMENT`, `RejectedError`,
`Pool` and its public methods. `NFR-4`'s lock fails on a signature that disappears or narrows; this
plan narrows nothing.

- [ ] **Step 5: Run `gates:sig_diff` and `gates:surface_snapshot`**

Run: `bundle exec rake gates:sig_diff gates:surface_snapshot`
Expected: clean against the regenerated baselines.

---

## Task 12: The clean-bundle isolation run, extended; the full gate set on all three interpreters

**Requirement IDs:** none new (`NFR-2`; boundary 7).
**Design:** "A second scratch bundle for `gates:clean_bundle`."

**Files:**
- Modify: `tasks/gates.rake`
- Test: `test/gates/clean_bundle_test.rb` (phase 0's, extended)

- [ ] **Step 1: Write the failing test**

Extend `test/gates/clean_bundle_test.rb`:

```ruby
  test "dexpace-core and dexpace-async-thread together load, build a pool, post and close, in isolation" do
    _out, err, status = rake("gates:clean_bundle")

    assert_predicate(status, :success?, err)
  end
```

(This rides on the existing `gates:clean_bundle` task's own success/failure, extended in Step 3
below, rather than adding a new task name — "an extension of an existing gate, not a sixteenth
gate," per the design.)

- [ ] **Step 2: Run it to confirm today's task does not yet cover the composed case**

Run: `bundle exec rake gates:clean_bundle`
Expected: passes today (it does not yet attempt the composed check), which is why Step 3's addition
needs its OWN explicit assertion inside the task body rather than relying on this test alone —
add a second, narrower test that greps `tasks/gates.rake` for the composed Gemfile's two `gem` lines:

```ruby
  test "the clean_bundle task's source declares both gems together, not only alone" do
    body = File.read(File.join(ROOT, "tasks/gates.rake"))

    assert_includes(body, %q(gem "dexpace-core"))
    assert_includes(body, %q(gem "dexpace-async-thread"))
  end
```

Run it: FAIL — the composed Gemfile does not exist yet.

- [ ] **Step 3: Extend the `gates:clean_bundle` task**

In `tasks/gates.rake`, after the existing per-gem loop inside `task :clean_bundle do … end`:

```ruby
    clean_bundle_composed_check(root) unless override

    puts "gates:clean_bundle: #{targets.size} gem(s) load in isolation on Ruby #{RUBY_VERSION}."
```

and, beside `clean_bundle_check`:

```ruby
  # Extends gates:clean_bundle for the first gem whose NFR-2 budget is zero by design: proves an
  # adapter activates with nothing but core in the bundle, on every Ruby in the matrix. Unlike the
  # per-gem-alone check above, BOTH gems are declared here via path:, so Bundler's dependency graph
  # resolves against the local sources and never needs dexpace-core reachable from
  # "https://rubygems.org" (where it is never published).
  def clean_bundle_composed_check(root)
    Dir.mktmpdir("dexpace-clean-bundle-composed") do |dir|
      core_path = File.join(root, "gems", "dexpace-core")
      thread_path = File.join(root, "gems", "dexpace-async-thread")
      File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
        # frozen_string_literal: true
        source "https://rubygems.org"
        gem "dexpace-core", path: #{core_path.inspect}
        gem "dexpace-async-thread", path: #{thread_path.inspect}
      GEMFILE
      smoke = <<~RUBY
        require "dexpace/async/thread"
        pool = Dexpace::Async::Thread::Pool.build(size: 1)
        done = Thread::Queue.new
        pool.post { done << :ran }
        abort("job never ran") unless done.pop
        pool.close
      RUBY
      env = { "BUNDLE_GEMFILE" => File.join(dir, "Gemfile") }

      Bundler.with_unbundled_env do
        out, err, status = Open3.capture3(env, "bundle", "install", "--quiet", chdir: dir)
        unless status.success?
          abort("gates:clean_bundle (composed): would not install:\n#{out}\n#{err}")
        end

        out, err, status = Open3.capture3(env, "bundle", "exec", "ruby", "-e", smoke, chdir: dir)
        unless status.success?
          abort("gates:clean_bundle (composed): failed in isolation:\n#{out}\n#{err}")
        end
      end
    end
  end
```

- [ ] **Step 4: Run both new tests, then the real gate**

Run: `ruby -Itest test/gates/clean_bundle_test.rb`
Expected: PASS.
Run: `bundle exec rake gates:clean_bundle`
Expected: `gates:clean_bundle: 6 gem(s) load in isolation on Ruby 3.4.10.` — the composed check adds
no line to that summary count (it is a second, unnamed check inside the same task), and the task
still exits 0.

- [ ] **Step 5: Run it on Ruby 4.0.6**

```bash
mise exec ruby@4.0.6 -- bundle exec rake gates:clean_bundle
```

Expected: clean. This is the run that proves the zero-third-party claim rather than asserting it —
a `require` of a gem that became bundled would fail here and nowhere else, and the 4.0 row is
load-bearing for the same reason it is for core.

- [ ] **Step 6: Run the whole gate set on all three interpreters**

```bash
bundle exec rake
mise exec ruby@3.2.11 -- bundle exec rake
mise exec ruby@4.0.6  -- bundle exec rake
```

Expected: all seventeen gates clean on all three rows.

---

## Task 13: The `ASYNC-7` README, YARD, the knowledge note, register-edit instructions, housekeeping

**Requirement IDs:** `ASYNC-7`. **Design:** "What `8b` additionally ships, without owning a new
ID"; "The knowledge note `8b` files"; "The findings proposed for the registers"; "Deferral-register
sweep"; open question 4.

**Files:**
- Modify: `gems/dexpace-async-thread/README.md`,
  `gems/dexpace-async-thread/lib/dexpace/async/thread/pool.rb` (YARD cross-reference lines only)

- [ ] **Step 1: Write the README's `ASYNC-7` section**

Add, after the existing install/usage content:

```markdown
## Cancellation and in-flight work

`dexpace-async-thread` lets an in-flight blocking read finish; reactor-backed adapters
(`dexpace-transport-async_http`) abort at the next scheduler checkpoint instead. Cancelling a
future whose send is already running on a worker does not interrupt that worker — `Thread#raise`
and `Thread#kill` are forbidden throughout this SDK (design §8.3), because an asynchronous interrupt
can land inside an `ensure` block releasing a pooled connection. The worker's blocking call runs to
completion; the SDK discards the result if the caller has moved on, closing it exactly once
(`ASYNC-5`) rather than delivering it.

The practical consequence: cancelling a request routed through this pool bounds *your* wait, not
the worker's occupancy. A transport blocked inside an uninterruptible read occupies its pool slot
until the read returns on its own.

## Lifecycle

```ruby
pool = Dexpace::Async::Thread::Pool.build(size: 4)
begin
  # ...
ensure
  pool.close
end
```

| Call | Behaviour |
|---|---|
| `#post` | Never blocks. A full queue raises `RejectedError`; a closed pool raises `Dexpace::ClosedError`. |
| `#delay` | Never blocks the caller or a worker; one named `<name> timer` thread is parked per pool that has ever scheduled a positive delay. |
| `#close` | Idempotent. Stops accepting work, lets in-flight and already-queued work finish within `shutdown_timeout` (default 30s), then returns. A caller-supplied executor passed to `Transport.async_over` is never closed by the bridge. |

**A caller who submits a mutable object through fiber storage shares that object with the worker.**
The per-submission diagnostic-context snapshot is captured, not deep-copied: its keys are frozen
but a mutable value (an `Array`, a `Hash`) in that snapshot is the same object on both sides of the
hop. Keep values you push into `Fiber[]` immutable, or synchronize your own access to them.
```

- [ ] **Step 2: Add the YARD cross-references**

In `Pool#post` and `Pool#close`'s YARD blocks (the latter inherited from `Dexpace::Closeable`, so
add the note to `#post`'s block only, plus one line in the class comment):

```ruby
        # See the gem README's "Cancellation and in-flight work" section for what happens to a
        # blocking send already running when its future is cancelled (ASYNC-7).
```

- [ ] **Step 3: Run the YARD gate**

Run: `bundle exec rake yard`
Expected: clean — every public method documented, no undocumented-public-method finding.

- [ ] **Step 4: Verify the note filed on 2026-09-12 still matches; update it if the implementation
      found otherwise**

`docs/knowledge/notes/observability.md`'s `## Reference` entry **already exists**: the phase-8
follow-through wrote it on 2026-09-12 from the design's *The knowledge note `8b` files* block —
role `review`, a manual `sha:manual-phase8b-pooled-worker-context-floor` marker. **One thing was
corrected when it was filed, and the reason is a gate:** the draft backticked
`observability/65191069`, which is this file's own second `## Superseded` entry and not a harvested
key, and `ruby scripts/verify_knowledge_structure.rb` rejects a note citing a note. The filed entry
backticks `observability/e0f1e864` — the harvested rule both `## Superseded` entries narrow — and
names the sibling note entry by its `sha:` marker in prose. Check the entry against what this
sub-phase measured and amend it if execution contradicts it; do not duplicate it. Then perform the
design's stated obligation, which is the half this step still has work in: **re-run
`observability/65191069`'s own measurements (the copy-on-write-protects-the-slot fact and the
`Fiber#storage=` key-coercion fact) on 3.2.11 and 4.0.6**, using Task 1's already-installed
interpreters, and amend that note's own single-interpreter caveat to say the re-run happened and
what it found. Then run `ruby scripts/verify_knowledge_structure.rb` (the gate) and
`ruby scripts/knowledge_drift.rb` (the hand-run report). **`harvested/` is not edited.**

- [ ] **Step 5: Perform `DEF-31`'s register edit**

`docs/deferred-items.md`'s `DEF-31` row: change `- **Status:** deferred` to
`- **Status:** picked-up (<execution date>, phase 8b). \`dexpace-async-thread\`'s \`#close\`
emits \`Events::INSTRUMENTATION_SHUTDOWN\` at \`Severity::INFO\`, inside
\`Instrumentation.contain\`, exactly once, asserted under 16-way concurrent close
(Task 6/Task 10).` Leave `DEF-18`, `DEF-1`, `DEF-28`, `DEF-21`, `DEF-27`, `DEF-11`, `DEF-12`,
`DEF-32`, `DEF-33` and `DEF-29` untouched, per the design's own sweep — `DEF-29`'s mark is `8a`'s,
not this plan's, and this plan's `test/support/` doubles are exactly the evidence the design cites
for why.

- [ ] **Step 6: Hand the four open-item/deviation findings to a human**

The design drafts all four verbatim under *The findings proposed for the registers* and this plan
does **not** file them (numbers collide across `8a`/`8b`/`8c` until a human assigns all three sets
at once): the pooled-worker-context-floor generalisation, `AsyncOver`'s check-after-resume-not-
before-dispatch finding, `Thread#report_on_exception`'s blind spot in the warnings-fatal gate, and
the `Completer#on_cancel` attribution correction to `docs/deviations.md`. Hand over the six `P8-20`
through `P8-25` ledger rows for consolidation into design §10.

- [ ] **Step 7: Run housekeeping's probe**

Run: `ruby .claude/skills/housekeeping/probe.rb`
Fix what it reports — without rewriting prose to satisfy a check — and note that `CLAUDE.md`'s
phase-directory claims sentence, the roadmap's phase-8 row link, and the `knowledge-lookup`
audit-group row are the charter's obligations, not this plan's. **Do not run `apply.rb --write`**
and do not commit; both are the user's to ask for.

---

## Coverage: every ID against the tasks that satisfy it

| ID | Level | Disposition | Task(s) |
|---|---|---|---|
| `ASYNC-1` | MUST | ✅ | 8 |
| `ASYNC-2` | MUST | ✅ | 4, 8 |
| `ASYNC-3` | MUST | **⏳ not satisfied, citing `DEF-18`** — see Task 8's cancel-while-queued test and `R10` | 8 (mitigation demonstrated) |
| `ASYNC-4` | MUST | **N/A — vacuous, citing design §10.5, no register row** | none (vacuous by construction; no code) |
| `ASYNC-5` | MUST | ✅ | 4 (`Completer#fulfil`, core), 8 (window test) |
| `ASYNC-6` | MUST | **cross-reference row, `8c`'s ID** — stated half only | 8 |
| `ASYNC-7` | SHOULD | ✅ | 8 (demonstration test), 13 (README) |
| `ASYNC-8` | SHOULD | ✅ | 4, 5 |
| `ASYNC-9` | MUST | ✅ | 4, 5 |
| `ASYNC-10` | MUST | ✅ | 4, 5 |
| `ASYNC-11` | MUST | ✅ | 4, 5 |
| `ASYNC-12` | MUST | ✅ (antecedent-check row) | 5 |
| `ASYNC-13` | MUST | ✅ | 8 |
| `ASYNC-14` | MUST | ✅ | 8 |
| `ASYNC-15` | MUST | ✅ | 6, 8 (clause b at the bridge), 10 |
| `ASYNC-16` | SHOULD | ✅ | 6 |
| `ASYNC-17` | SHOULD | ✅ | 6 (overriding implementation), 8 (SPI default asserted) |
| `ASYNC-18` | MUST | ✅ | 7 |
| `ASYNC-19` | MUST | ✅ | 8 |
| `ASYNC-20` | MUST | ✅ | 8 |
| `PIPE-33` | MUST | **cross-reference row, phase 4's ID** — clauses 2–4 re-asserted; clause 5 (interrupt) stays phase 4's ⏳ citing `DEF-18` | 8 |

**Every one of the 19 owned IDs plus the two cross-reference rows appears above.** `ASYNC-3`'s row
text and `ASYNC-4`'s row text are copied from the design's own drafted checklist language at
execution time (see the design document's "Twelve rows carry a clause the checklist must state
rather than tick" section) — this plan does not redraft them, only cites where the code that
grounds each is.

---

## Verification log (2026-09-12)

A verification pass read this plan against
`docs/work/mvp/phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter-design.md` and the charter
`docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`, task by task and ID by ID. Every
change it made is below with its reason. Two changes landed in the **design** instead, and are
marked as such.

**Correctness of the sketched code**

- **Task 4 no longer requires or constructs `Timer`.** `pool.rb` carried `require_relative "timer"`
  and `@timer = Timer.new(name)` while `timer.rb` is not written until Task 7 — a `LoadError`, not a
  red test, on every Task 4 and Task 5 step. Task 7 gains a Step 4b that adds the require, the ivar
  and `#release`'s timer line together, and Task 6's "stub `Timer#stop` if you implement out of
  order" caveat is gone with the thing that caused it.
- **`Timer#stop` takes a bounded timeout.** It was a bare `@thread&.join`, which is the unbounded
  close-path wait `XCUT-13` and design §3.7 forbid **for this gem by name**, and which contradicts
  the design's own "within the same `DEFAULT_SHUTDOWN_TIMEOUT` budget as the workers". `#release`
  now computes one `deadline` and both `stop_timer(deadline)` and `drain_workers(deadline)` spend
  it, so a close is bounded by `shutdown_timeout` in total rather than per resource.
- **Task 6's fake-clock close test was rewritten because it could not pass.** It built the pool with
  `shutdown_timeout: 5.0`, blocked `#close` in `@exits.pop(timeout: 5.0)` — a **real** five-second
  queue wait — and then advanced a stub clock, which no queue observes; `closer.join(2)` would have
  been `nil` every time. The replacement uses `shutdown_timeout: 0.0`, so the drain's
  `deadline - clock.monotonic` comparison returns before any queue wait, and asserts the emitted
  event's `drained` field is `false`. That is the branch the design says a fake clock *can* drive,
  and the only one.
- **Task 2's skew test no longer writes `VERSION = "9.9.9"` inside a `Class.new do … end` block.**
  That is a dynamic constant assignment and does not parse. `#assert_core_version!` already takes
  the version string, so the test passes `"9.9.9"` directly.
- **Task 1's allowlist regression test goes through `#send`.** `RequireAllowlist` is `extend self`
  and declares `private` above `reason_for` (phase 0's source, `:2198-2205`), so
  `RequireAllowlist.reason_for(...)` is a `NoMethodError` and the test would have failed for the
  wrong reason — which is indistinguishable from the finding it exists to reproduce.
- **`?queue_limit:` is `Integer?` in both `sig/` blocks, here and in the design.** `.build` defaults
  it to `nil` and derives after validating `size`; a `nil` default under an `Integer` declaration is
  a `steep check` error, and the alternative — `queue_limit: size * QUEUE_DEPTH_PER_WORKER` in the
  parameter list — evaluates against an unvalidated `size`, so `Pool.build(size: nil)` would raise
  `NoMethodError` from the default rather than `Dexpace::InvalidArgumentError` naming the keyword.

**Tests that waited on a clock rather than on a condition**

The design's testing strategy says "no sleep decides an assertion" and the plan restated it; five
tests did not honour it. Each now waits on a condition, and a new Global Constraint states the rule
once so a later edit has something to violate rather than a habit to forget.

- **Task 1, fact 6** — `sleep(0.05)` before asserting a thread had reached `"sleep"`. Now an
  `entered` queue plus a deadline-bounded `::Thread.pass` loop on `#status`.
- **Task 6 and Task 8** — the two sleeps above and below the ASYNC-14 cancellation. `FakeTransport`
  gains an `entered:` queue it pushes to as its first act, so the canceller fires once the worker is
  provably inside `#call`.
- **Task 7** — `sleep(0.25)` before three blocking pops that already are the wait (removed), and
  `sleep(0.10)` to let a cancelled entry's deadline pass (now a later `#delay` on the same timer,
  awaited through `#value`, which proves the timer ran *through* that deadline rather than guessing
  that it did).
- **Task 10** — `sleep(0.01)` before `#close` in the post-racing-close test, now a `posting` queue;
  and the accepted-versus-ran count, which raced the workers, now runs after `#close` has drained.

**Coverage against the design and the charter**

- Every one of the 19 owned IDs, both cross-reference rows and all four modal levels were checked
  against appendix C (`:589-608`): 15 MUST + 4 SHOULD (`ASYNC-7`, `ASYNC-8`, `ASYNC-16`,
  `ASYNC-17`), which matches the coverage table row for row and the charter's split. `ASYNC-3` ⏳
  citing `DEF-18`, `ASYNC-4` N/A citing §10.5 and **no** register row, `ASYNC-6` and `PIPE-33` as
  cross-references with no budget line — all four as the charter fixes them. No ID is missing a
  task, none is ticked that the design says must carry a clause instead.
- **Task 8's `PIPE-33` test was rebuilt around a real multi-step pipeline.** It wrapped a bare
  `FakeTransport` and counted *transport* calls, which cannot show clause 2 — with no steps there is
  nothing that could have been posted per-step, so a count of one proves nothing. It now builds a
  two-step `Dexpace::Pipeline` and counts `#post` itself through a delegating executor, which is
  what the design's boundary 12 and testing group 6 both describe.
- **Tasks 8 and 10 state why they have no red phase, and what replaces it.** Both ship no new `lib/`
  code, so no test can be red against an implementation that already exists; Task 8 already carried
  a break-it proof and now says that is the substitute, and Task 10 gains three (the
  `ClosedQueueError` translation, the non-blocking push, the close latch). Task 5 already had this
  shape and is unchanged.
- Test counts in two "Expected: PASS, N runs" lines were wrong against the tests actually listed
  (Task 4: 12 → 11; Task 7: 9 → 8).
- Commands under `### Commands` were checked one by one against phase 0's plan: every name is a real
  task there (`…phase0…-scaffold-and-quality-gates.md:355-366` lists the default task's seventeen,
  `surface:regenerate` is at `:3020-3022`, `yard` at `:3356`, `bundler_audit` at `:3543`). Nothing
  was added or removed.
- Task 12's `clean_bundle_composed_check` insertion point was checked against phase 0's real task
  body (`:2353-2374`): the `targets.each` loop followed by the summary `puts` is exactly where the
  plan puts it, and the helper's shape matches `clean_bundle_check`'s.
- `Timeout.timeout`, `Thread#raise` and `Thread#kill` appear nowhere; `Fiber[]` is the carrier and
  `Thread.current[]` appears nowhere; both are additionally asserted by Task 4's grep tests, which
  Step 6 proves non-vacuous. Every mutex in the sketched code is held across a flip, a list
  mutation or the lazy thread creation and never across a queue wait or a callback. Every `.rb`
  sketch, test support file included, opens with `# frozen_string_literal: true`,
  `# SPDX-License-Identifier: MIT`, a blank line, and a header comment naming the IDs it serves.
- The `Dexpace/QualifiedCoreConstant` cop is phase 2's (`P2-8`), not phase 0's; the Tech Stack line
  and the design's "From phase 0" bullet both said five cops while counting it among them. Both now
  say six, three of which reach this gem.

**The two filed discrepancies, re-run and adjudicated**

1. **`require "dexpace"` under phase 0's allowlist — the plan is right; the DESIGN was corrected.**
   Phase 0's `reason_for` exempts `permitted.include?(name) || name.start_with?("dexpace/")`;
   `third_party_for` rejects `"dexpace-core"` from `permitted` by name, and `"dexpace"` is on
   neither `ALLOWED` nor `DENIED` — so the bare name falls through to "not in the require
   allowlist". The design's verified fact 1 and its "From phase 0" bullet now carry the correction
   and name the plan's Task 1 as where the one-line widening lands. **No `P8-<n>` row was opened**:
   repairing a sibling phase's gate is not a departure from the reference contract, and the design's
   ledger preamble now records that judgement rather than leaving the absence to look like an
   oversight.
2. **`Gem::Version` versus phase 2's hand-rolled comparison — neither document was wrong, and item 2
   is reclassified as a rationale rather than a discrepancy.** The design already prescribes
   `Gem::Requirement` in the entry file, and `P8-21` already names 7a's `P7-7` as the precedent for
   a require-time assertion in an adapter. What was genuinely missing is why phase 2's precedent
   does not govern, and the fact that settles it: `Gem::Version`/`Gem::Requirement` are **constants,
   not a `require`**, so phase 0's require-allowlist — a text scan of `require`/`require_relative`
   lines — never sees them, and `rubygems`' absence from `ALLOWED` is beside the point for a gem
   that writes no `require "rubygems"`. 7a verified the same from the other side
   (`…phase7a…-serialization-design.md:1380`). Phase 2's hand-roll answers `ruby --disable-gems`,
   which binds `dexpace-core` and no adapter.

**Design edits made by this pass** — verified fact 1's correction and the matching "From phase 0"
bullet; "five custom cops" → six; `?queue_limit:` → `Integer?` in the `sig/` shape with its reason;
the `Pool.build` pseudo-signature's `nil` sentinel; a row in *The interface surface later phases may
cite* stating `8b`'s side of the deadline-and-cancel contract for `8c`; and the ledger's reserved
band narrowed from `P8-20`–`P8-39` to **`P8-20`–`P8-35`**, since `8b` uses six rows and `8c` takes
`P8-36`–`P8-50` (the top end widened by the cross-sub-phase reconciliation pass later the same day;
`8c` uses `P8-36`–`P8-40` and `P8-41`–`P8-50` stay unallocated).

**Not changed, and why.** The six `P8-20`–`P8-25` ledger rows, `R8`–`R12`'s decisions, the object
model, the module layout and the `sig/` shape are all consistent between plan and design and are
left alone. The four register findings stay unfiled; three of them were **numbered `OI-46`–`OI-48` by
the cross-sub-phase reconciliation pass later on 2026-09-12** (this pass deliberately left them blank
because `8a` and `8c` were still concurrent, which they no longer are), and the fourth — the
`docs/deviations.md` attribution note — stays unnumbered because that register does not use `OI-<n>`.
Task 9's and Task 8's fixture calls into
phase 7c's and 4c's landed signatures stay flagged as execution-time checks rather than pinned
here — this sub-phase does not own those gems, and pinning a keyword list it cannot verify would be
a worse failure than naming the check.

## Handoff to follow-through

Four things this sub-phase cannot write itself, recorded here so they are not rediscovered. None is
a register edit performed by this plan.

1. **The deviation bands are settled, and the charter is where they are stated.** The 8b design's
   reserved band was narrowed from `P8-20`–`P8-39` to `P8-20`–`P8-35` on 2026-09-12, because `8b` uses
   six rows and a twenty-row reservation crowds a sibling that cannot coordinate with it. The
   cross-sub-phase reconciliation pass later the same day adopted that allocation phase-wide and
   widened `8c`'s top end so it has headroom of its own: **`8a` `P8-1`–`P8-19` (using `P8-1`–`P8-14`),
   `8b` `P8-20`–`P8-35` (using `P8-20`–`P8-25`), `8c` `P8-36`–`P8-50` (using `P8-36`–`P8-40`)**, with
   `P8-41`–`P8-50` unallocated and `P8-41` retired unfiled by `8c`'s own verifier. The table is in
   `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md`'s *Deviation Ledger*, and the three
   sub-phase designs cite it rather than each restating it. **Nothing was renumbered**, so no citation
   moved and `docs/deviations.md` receives `8b`'s six rows unchanged.
2. **Phase 0's `tools/require_allowlist.rb` gains one alternative in this plan's Task 1**
   (`name == "dexpace" || name.start_with?("dexpace/")`). It is a repository-wide file: `8a` and
   `8c` must not land the same widening a second time, and whichever sub-phase runs first owns it.
   The *Discrepancies* section carries the evidence and the decision not to open a `P8-<n>` for it.
3. **The four register findings drafted in the 8b design are unfiled; three now carry numbers.**
   `OI-46`, `OI-47` and `OI-48` for `docs/open-items.md`, assigned by the cross-sub-phase
   reconciliation pass on 2026-09-12 after `8a`'s `OI-42`–`OI-45` and in sub-phase order, and each
   rewritten there in the register's own row format so filing is a paste. **The fourth carries no
   number and must not be given one**: it targets `docs/deviations.md`, which is a judgement register
   rather than a mechanical append, and it is an attribution correction — design §10.5's mitigation
   sentence names `Completer#on_cancel` as something "an adapter" does, and on the thread path no
   adapter can, because the hook belongs to the transport that owns the socket. A filer runs
   `ruby .claude/skills/housekeeping/probe.rb --only citations` first: fifteen numbers (`OI-34`–`OI-48`)
   are cited across phase 8 with no row in the register yet, and if any is filed under a different
   number every one after it shifts mechanically.
4. **`observability/65191069`'s single-interpreter caveat is cleared by this plan's Task 13, Step 4**
   and by nothing else in phase 8. If `8b` is re-scoped or dropped, the caveat outlives the phase
   that the charter says owns it.

### Added by the cross-sub-phase reconciliation pass, 2026-09-12

Four things settled elsewhere in the phase that a follow-through agent should know bear on `8b`, none
of which changes a line of this plan's nineteen IDs or twelve tasks.

5. **`8b` is on no side of any of the four shared-artifact decisions, and that stays true.** The
   charter's phase-level task 1 (`Dexpace::TransportError`) is now `8a`'s Task 2 rather than "whoever
   lands first"; the suite contract is one twelve-clause list owned by `8a`'s design; the header-drop
   contract is stated once in the charter's new *Shared transport contracts* subsection; and the CI
   matrix after `8c`'s per-gem Ruby floor is stated once in the charter. **`8b` writes none of them**,
   which its design already says, and this plan's Task 12 is unaffected.
6. **This plan's gate runs stay on three interpreters — 3.2.11, 3.4.10 and 4.0.6 — and must tolerate
   `8c`'s edited `VERSIONS` if `8c` executes first.** They do, without change: `dexpace-async-thread`
   has no `floor:<gem-name>` row, `DexpaceVersions.ruby_floor(name)` falls back to the global `3.2`,
   the new row is colon-joined into `VERSIONS`' existing three-token `name` column so `.records` and
   every existing `.value` call site parse it unchanged, and `gates:versions` continues to assert
   `>= 3.2` for this gem. **This plan touches none of `VERSIONS`, the root `Gemfile`,
   `tools/versions.rb`, `tools/versions_gate.rb`, `tasks/quality.rake` or `tasks/gates.rake`'s
   `clean_bundle` target selection**, and Task 12 must not land a second copy of that edit. The one
   phase-0 file this plan does edit is `tools/require_allowlist.rb` (item 2 above), which is a
   different file and a different repair.
7. **`Events::TRANSPORT_HEADER_DROPPED` is a `dexpace-core` widening `8a` or `8c` lands, not `8b`.**
   `8b` drops no header and emits no drop record; `DEF-31`'s `Events::INSTRUMENTATION_SHUTDOWN` is
   phase 5b's and already exists. Named so a reviewer of the phase-level PR does not read the new
   constant as something every phase-8 gem touches.
8. **`8b`'s two cross-reference rows are unchanged by the reconciliation.** `PIPE-33` keeps its phase-4
   ⏳ and `ASYNC-6` stays `8c`'s ID with `8b` stating the thread-pool half — and `8c`'s own design was
   corrected on 2026-09-12 to settle `ASYNC-6`'s inward direction through `Completer#request_cancel`
   rather than `#fail`, which is the same distinction `8b`'s coverage table already relies on for
   `ASYNC-5` and `ASYNC-20`. No row in the coverage table moves.
