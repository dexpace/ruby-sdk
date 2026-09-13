# Phase 9 — Cross-Cutting Invariants and Conformance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Disposition all 41 of phase 9's requirement IDs — `XCUT-1`–`XCUT-24` and `NFR-1`–`NFR-17` — by building the instrument that answers them (four new suites in `dexpace-conformance`, three repository gates, one aggregate report and a 61-row appendix-B coverage map) and then running it against the tree phases 0–8 built.

**Architecture:** Two halves in one plan, in order. **Tasks 1–14 build the instrument** under ordinary TDD: every suite gets a deliberately non-conforming double that must make its assertion fail before a conforming one makes it pass, and every gate gets a failing fixture, exactly as phase 0 required of its seventeen gates. **Tasks 15–17 run it** and record verdicts. The two halves are kept apart deliberately: a green suite proves the *instrument* works, not that the SDK conforms, and those are different claims.

**Tech Stack:** Ruby ≥ 3.2 (matrix 3.2 / 3.3 / 3.4 / 4.0); Minitest; Rake; RBS + Steep; `RubyVM::AbstractSyntaxTree` for the repository gates; no third-party runtime dependency anywhere — `dexpace-conformance` declares `dexpace-core` and nothing else.

**Spec:** `docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance-design.md`

## Global Constraints

Copied verbatim from the design and from `CLAUDE.md`. Every task's requirements implicitly include this section.

- **Every file opens with `# frozen_string_literal: true` on line 1, `# SPDX-License-Identifier: MIT` on line 2, blank line 3** (`NFR-13`; phase 0's `Dexpace/SpdxHeader` cop). There is no `# typed:` sigil in this repository.
- **`dexpace-conformance` declares `dexpace-core` and nothing else.** No `require "minitest"`, no `require "rspec"`, no `require "socket"` anywhere in its `lib/`. `Gem::Specification` needs no require; RubyGems is loaded before user code.
- **Phase 9 creates or modifies files only under `gems/dexpace-conformance/`, `tasks/`, `tools/`, `test/`, `.github/workflows/`, **each adapter gem's `test/` tree** and the root `Rakefile`.** No `lib/` or `sig/` file outside `gems/dexpace-conformance/` is touched, and no file in `dexpace-core` at all. **The root `Rakefile` is on that list for one reason: `DEFAULT_GATES` is defined there, not in `tasks/gates.rake`** — the `Rakefile` `load`s `tasks/*.rake` **before** defining the array and then `.freeze`s it (phase 0 plan, Task 1 Step 6), so a `.rake` file can neither see it nor append to it, and a gate outside it is not in `task default:` and therefore not blocking, which `NFR-17` forbids and this phase's own `NFR-17` disposition would be falsified by. The two widenings are load-bearing rather than convenient: a suite nobody drives proves nothing, and **8a's own precedent is a driver file inside the adapter gem** — `gems/dexpace-transport-net_http/test/dexpace/transport/net_http/conformance_test.rb`, which is one `conformance(…)` call and nothing else (8a plan, Task 23). Phase 9 follows that **placement** for `dexpace-serde-json` and `dexpace-async-thread`, but each driver calls its suite's `.run` and asserts on the report, because 8a's `MinitestDriver#conformance` builds a `TransportCase` for every assertion (8a plan:2302-2306) and widening it would change an interface phase 8 owns. (One keyword with a default, `accepted_vacuous: {}`, is added to it, to `RSpecDriver` and to `TransportSuite.run` by Task 12a, forwarded to the `Report.new` each already performs and nothing else — a widening `NFR-4` permits, argued in that task's decision 3; added 2026-09-13.) And phase 0's `ci_workflow_test.rb` is a **blocking** gate asserting every entry in `DEFAULT_GATES` appears in some CI job, so a phase that adds three gates and leaves `ci.yml` alone reddens a phase-0 gate. This is `R6`'s boundary as a file list: phase 9 reports, phase 10 repairs — and the list bounds *where it may write*, not *whether it may fix another gem*, which it may not.
- **Every task that adds a constant to `dexpace-conformance` also adds its `require_relative` to `lib/dexpace/conformance.rb`, in the same step.** A constant with no require is a `NameError` in every consumer, including this gem's own suite; the entry file is named in each such task's Files list for that reason. `rspec_driver.rb` stays the one deliberate exception (8a), because requiring it would name `::RSpec` in a Minitest-only process.
- **`Timeout.timeout`, `Thread#raise`, `Thread#kill`, `Thread#terminate` and `Thread#exit` are banned repository-wide** (`Dexpace/NoThreadInterrupt`, §8.3). Cancellation in an assertion uses `Dexpace::Cancellation`, never a thread interrupt.
- **`downcase`/`upcase`/`casecmp` take no locale argument** (`Dexpace/NoLocaleCaseFold`, `HTTP-13`).
- **`URI::RFC3986_PARSER` is pinned for every parse and every resolution**; `URI.parse`/`URI.join`/`URI.split` and `URI::DEFAULT_PARSER` are cop-banned (§3.5).
- **`assert_predicate` is not used.** It sends past `private` on the 3.2 floor; visibility is asserted with `respond_to?` (phase 1's finding, every phase plan's Global Constraints).
- **Every test runs alone, in any order** (`testing/4ef070df`): mutable fixtures are built fresh per test, never shared across a suite run. This bit during planning — see Task 11's note.
- **`assert_equal(expected, actual)`, expected first** (`testing/f3a0462e`); descriptive assertions over bare `assert x == y` (`testing/6e277a34`).
- **Test files name the requirement IDs they exercise in a header comment** (`CLAUDE.md`'s conventions); a non-obvious branch names the ID that forced it.
- **`Assertion`, `Result`, `Failure`, `Vacuous` and the five statuses are phase 8a's and are not changed.** `Assertion.build` and `Result.build` are the only construction entry points — `private_class_method :new` makes *every* explicit-receiver `new` raise, including from inside this gem.
- **A waiver is keyed by requirement ID, never by assertion name**, and every waived ID is named on every run (§9.3: "the gap stays visible").
- **An assertion raises `Vacuous` from inside, after establishing its antecedent is absent** — never skipped from a list. §12 counts eight MUSTs that hold vacuously and a suite reporting them as passing is how that count stops being true.
- **Ruby facts are verified on every installed interpreter** — `mise exec ruby@<v> -- ruby …` — not on one. **Four are installed: 3.2.11, 3.3.12, 3.4.10 and 4.0.6**, which is the whole supported matrix (3.2 / 3.3 / 3.4 / 4.0 per `CLAUDE.md`); there is **no `.ruby-version` file in this repository**. The planning measurements quoted below were taken on 3.2.11, 3.4.10 and 4.0.6 before 3.3.12 was installed and say so where they appear; the 2026-09-13 fix round re-ran the fences on all four. Say which interpreters a claim was run on.

---

## File Structure

| File | Responsibility |
|---|---|
| `gems/dexpace-conformance/lib/dexpace/conformance.rb` *(modified, every task)* | The entry file. Each new constant's `require_relative` lands here in the task that creates it |
| `gems/dexpace-conformance/lib/dexpace/conformance/runner.rb` | The one loop every new suite's `.run` delegates to; decides the five statuses in one place |
| `…/conformance/check.rb` | `Check.that` — the assertion primitive every suite body uses. Its own file, because one public constant per file is the rule and phase 9's own code must pass the `NFR-3` assertion phase 9 ships |
| `…/conformance/report.rb` *(modified)* | Adds `#results`, `#to_h`, `.merge` and the waived/vacuous rendering sections |
| `…/conformance/shared_instance.rb` | `XCUT-11`'s structural predicate (`R8`) |
| `…/conformance/invariant_case.rb` + `invariant_suite.rb` | Appendix `B.8`; `XCUT-1`–`XCUT-24` |
| `…/conformance/packaging_case.rb` + `packaging_suite.rb` | Appendix `B.9`; the **eight** portable `NFR`s — `NFR-1`, `NFR-2`, `NFR-3`, `NFR-10`, `NFR-11`, `NFR-13`, `NFR-14`, `NFR-15` |
| `…/conformance/codec_case.rb` + `codec_suite.rb` | Appendix `B.3`'s seam half, lifted from 7a's named target |
| `…/conformance/executor_case.rb` + `executor_suite.rb` | Appendix `B.7`'s lifecycle half; the harness for `SEAM-25`'s lifecycle event |
| `…/conformance/aggregate.rb` | One report over every suite; the preamble stating what a green run does not prove; the coverage map's generated half, read off each suite's `.assertions` |
| `…/conformance/levels.rb` *(generated, committed)* | `Levels::OF` — every requirement ID's normative level, generated from appendix C by `tools/requirement_levels.rb`; what lets a `Report` tell a MUST-level vacuity from a SHOULD-level one (the MUST-level vacuity blocker, Task 12a) |
| `gems/dexpace-conformance/APPENDIX_B.md` | The 61-row coverage map |
| `tools/ast_scan.rb` | The shared `RubyVM::AbstractSyntaxTree` walker |
| `tools/invariant_gates.rb` | `cause_walk`, `bounded_map`, `seam_names` offence lists, each with its statically undecidable gap written down. `drain_loop` is out of v1 (Task 13) — Task 7's `bounded_map_drains` decides its clause deterministically |
| `tools/requirement_levels.rb` | Generates `levels.rb` from appendix C — **reads** the frozen spec, writes one file under `gems/`; `--check` exits 1 when the committed map is stale (Task 12a) |
| `test/gates/requirement_levels_test.rb` | Regenerates the level map in memory and diffs it against the committed file; asserts every ID any suite declares is one appendix C knows (Task 12a) |
| `tasks/gates.rake` *(modified)* | The three new gate tasks |
| `Rakefile` *(modified)* | The three names appended to `DEFAULT_GATES`, which is defined here and not in `tasks/gates.rake` — the `Rakefile` `load`s `tasks/*.rake` before defining the array and then freezes it, so a gate added anywhere else is not in `task default:` and not blocking (`NFR-17`) |
| `.github/workflows/ci.yml` *(modified)* | The three new gates placed in the `gates` job, because phase 0's `ci_workflow_test.rb` is blocking and asserts every `DEFAULT_GATES` entry appears in some job |
| `test/fixtures/gates/` | One deliberately failing fixture per new gate, plus a positive control. **This is the one spelling** — `test/gates/` holds the gate *tests*, `test/fixtures/gates/` their *fixtures* |

---

## Task 1: Re-verify the phase's Ruby facts on three interpreters

**Files:**
- Create: `test/support/warning_capture.rb`
- Create: `test/gates/phase9_ruby_facts_test.rb`
- Create: `test/fixtures/gates/warns_unused.rb` — Task 13 reuses it and writes no eighth fixture

**Interfaces:**
- Consumes: phase 0's `DexpaceTestCase`, whose `FatalWarnings` module is **prepended to
  `Warning.singleton_class`**
- Produces: `WarningCapture#capture_warnings { } -> Array[[String, Symbol?]]`, and the four facts
  every later task rests on, re-measured at implementation time

The design's facts were measured during planning on **3.2.11, 3.4.10 and 4.0.6** — the three
interpreters installed at the time. **There is no `.ruby-version` file in this repository**; the
supported matrix is 3.2 / 3.3 / 3.4 / 4.0 per `CLAUDE.md`, and **3.3.12 is now installed as well**
(2026-09-13), so this task re-verifies every fact on all four rows. A fact that was true in planning and false at
implementation time is what the note mechanism exists to catch, and four are load-bearing: the AST
node types (Task 13), the **`:LIT` versus `:SYM`** divergence (Task 13's reflective scan), the
Minitest version split (phase 0 plan, Task 2's `minitest` `~> 5.25` pin), and the `Data` reader split (`NFR-4`, Task 15).

- [ ] **Step 1: Write `test/support/warning_capture.rb` first, because the obvious shape does not work**

Phase 0 installs its warnings-fatal gate as `Warning.singleton_class.prepend(FatalWarnings)`
(`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates.md:1579-1585`). A prepended
module sits **above** the singleton class's own methods — `Warning.singleton_class.ancestors` begins
`[FatalWarnings, #<Class:Warning>, Warning]` — so a `Warning.define_singleton_method(:warn)` lands
**below** `FatalWarnings` and never receives the call. Measured on 3.2.11, 3.3.12, 3.4.10 and 4.0.6:
defining the singleton method **raises nothing**, and the next `Warning.warn` still raises `NFR-6`'s
error with nothing captured. (An earlier draft said the definition itself emitted a `method
redefined` warning that raised; it does not.) **Prepend order is the whole reason for the shape:**
the recorder is a **second module prepended above `FatalWarnings`**, with a thread-local sink so the
capture is scoped and nothing global is mutated per test.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# NFR-6's gate is FatalWarnings, PREPENDED to Warning's singleton class by phase 0. A prepended
# module sits above the singleton class's own methods, so define_singleton_method(:warn) lands BELOW
# FatalWarnings and never receives the call: it raises nothing and captures nothing (measured on
# 3.2.11, 3.3.12, 3.4.10 and 4.0.6). Prepend order is the reason for this shape -- a SECOND module
# prepended ABOVE FatalWarnings -- and a thread-local sink keeps the capture scoped: outside a
# capture block, FatalWarnings still raises.
module RecordingWarnings
  SINK = :dexpace_warning_sink

  def warn(message, category: nil)
    sink = ::Thread.current[SINK]
    return super if sink.nil?

    sink << [message, category]
    nil
  end
end
Warning.singleton_class.prepend(RecordingWarnings)

module WarningCapture
  def capture_warnings
    sink = []
    previous = ::Thread.current[RecordingWarnings::SINK]
    ::Thread.current[RecordingWarnings::SINK] = sink
    yield
    sink
  ensure
    ::Thread.current[RecordingWarnings::SINK] = previous
  end
end
```

**And the fixture the two warning facts need.** The claim an earlier draft made — that parsing emits
no warning — is true of the **parser** and false of the **file**: a scanned file's own `-w`
diagnostics are emitted at parse time and routed through `Warning.warn` exactly as at require time.
Testing that against `__FILE__`, which carries no diagnostic, proves nothing, so the fact needs a
file that does. The shape is 8a's, filed and unchanged — `rescue ::StandardError => e` inside
`Adapter#dispatch`, where `e` is never read
(`docs/work/mvp/phase8/phase8a/2026-09-11-phase8a-synchronous-transport-and-conformance.md:4858`)
— and it emits `assigned but unused variable - e` on 3.2.11, 3.3.12, 3.4.10 and 4.0.6.

```ruby
# test/fixtures/gates/warns_unused.rb
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Parsed, never required: this file's own -w diagnostic IS the input. `e` is bound and unused --
# the shape 8a filed at 8a plan:4858, `rescue ::StandardError => e` inside Adapter#dispatch, which
# emits "assigned but unused variable - e" on 3.2.11, 3.3.12, 3.4.10 and 4.0.6. Nothing here names
# #cause or assigns a Hash ivar, so every gate in Task 13 must report it CLEAN; what it proves is
# that the scan does not RAISE under the warnings-fatal test case.
module WarnsUnused
  def self.call(pump)
    pump.head
  rescue ::StandardError => e
    pump.close
    raise
  end
end
```

- [ ] **Step 2: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The four facts phase 9's machinery rests on, re-measured on the interpreter running this suite.
# Design "The verified Ruby facts this phase is built on"; XCUT-9, XCUT-14, NFR-4, NFR-17, and
# phase 0 Task 2's minitest pin.
# GateCase is phase 0's gate base (phase 0 plan:263-298) and does not load FatalWarnings; the
# "still raises" test below needs it, so DexpaceTestCase's file is required for that prepend.
require_relative "../support/dexpace_test_case"
require_relative "../support/gate_case"
require_relative "../support/warning_capture"

class Phase9RubyFactsTest < GateCase
  include WarningCapture

  WARNS_UNUSED = File.expand_path("../fixtures/gates/warns_unused.rb", __dir__)

  test "a send is one of three AST node types and a :CALL-only scan misses safe navigation" do
    types = []
    walk(::RubyVM::AbstractSyntaxTree.parse("a.cause; b&.cause; cause")) do |node|
      name = node.type == :VCALL ? node.children[0] : node.children[1]
      types << node.type if name == :cause
    end

    assert_equal(%i[CALL QCALL VCALL], types)
  end

  test "a Symbol literal is :LIT below Ruby 3.4 and :SYM at and above it" do
    found = []
    walk(::RubyVM::AbstractSyntaxTree.parse("e.send(:cause)")) do |node|
      found << node.type if %i[LIT SYM].include?(node.type)
    end
    expected = ::Gem::Version.new(::RUBY_VERSION) < ::Gem::Version.new("3.4.0") ? [:LIT] : [:SYM]

    assert_equal(expected, found,
                 "a reflective-send scan naming only one of the two is strictest on the row it " \
                 "was written on and blind on the others")
  end

  # The PARSER is silent for well-formed input; the SCANNED FILE's own -w diagnostics are not, and
  # they arrive through Warning.warn exactly as at require time. An earlier draft of this test
  # parsed __FILE__, which carries no diagnostic, and concluded that parsing never warns.
  test "a scanned file's own -w diagnostics reach Warning.warn, which is what the scanner must silence" do
    seen = capture_warnings { ::RubyVM::AbstractSyntaxTree.parse_file(WARNS_UNUSED) }

    assert_equal(1, seen.size)
    assert_includes(seen.first.first, "assigned but unused variable - e")
    assert_nil(seen.first.last, "no category, so Warning[:deprecated] = false cannot reach it")
  end

  # $VERBOSE = false silences only the -w class: a duplicated hash key warns whatever $VERBOSE is
  # and would still raise under FatalWarnings, so the window AstScan.parse opens is nil, not false.
  test "$VERBOSE = nil silences the parse warning, and the window closes behind it" do
    armed = $VERBOSE
    seen = capture_warnings { quietly { ::RubyVM::AbstractSyntaxTree.parse_file(WARNS_UNUSED) } }

    assert_empty(seen)
    assert_equal(armed, $VERBOSE, "the gate stays armed outside the window")
  end

  test "outside a capture block a warning still raises, so the gate is not weakened" do
    error = assert_raises(::RuntimeError) { Warning.warn("escaped\n") }

    assert_includes(error.message, "NFR-6")
  end

  test "minitest is a bundled gem, never a default one, on every supported Ruby" do
    spec = ::Gem::Specification.find_by_name("minitest")

    refute(spec.default_gem?, "design 9.3 calls minitest a default gem; it is bundled, which is why " \
                              "phase 0 Task 2's Gemfile names it")
  end

  test "minitest ships mock below 6 and not at 6, which is why phase 0 Task 2 pins it" do
    major = ::Gem::Version.new(::Minitest::VERSION).segments.first
    mock_available = begin
      require "minitest/mock"
      true
    rescue ::LoadError
      false
    end

    assert_equal(major < 6, mock_available)
  end

  test "a Data subclass's generated readers live on the superclass, not on the subclass" do
    type = Class.new(::Data.define(:code)) { def ok? = code == 200 }

    assert_equal([:ok?], type.instance_methods(false))
    assert_equal([:code], type.superclass.instance_methods(false))
  end

  private

  # AstScan.parse's window (Task 13), spelled here so the fact is measured where it is recorded.
  def quietly
    previous = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = previous
  end

  def walk(node, &block)
    return unless node.is_a?(::RubyVM::AbstractSyntaxTree::Node)

    block.call(node)
    node.children.each { |child| walk(child, &block) }
  end
end
```

- [ ] **Step 3: Run on the four installed interpreters**

```bash
for v in 3.2.11 3.3.12 3.4.10 4.0.6; do mise exec ruby@$v -- ruby -w test/gates/phase9_ruby_facts_test.rb; done
```

Expected: **8 runs, 16 assertions, 0 failures** on each — measured 2026-09-13 on 3.2.11, 3.3.12,
3.4.10 and 4.0.6. **Two tests assert a different outcome per interpreter by design** —
`mock_available` is true wherever Minitest is 5.x and false on 4.0.6 (Minitest 6.0.0), which is
what phase 0 plan, Task 2's `minitest` `~> 5.25` pin answers; and the Symbol node type is `:LIT` on
3.2.11 and 3.3.12 and `:SYM` on 3.4.10 and 4.0.6, which `docs/knowledge/notes/cross-cutting-invariants.md`
records.

- [ ] **Step 4: If any fact has changed, stop and file, do not adapt**

A changed fact is a finding, and a finding is **routed to its owner when it is found**, never parked in
a register. Route it: to a numbered task in the plan of the phase whose scope it falls in — this plan's
own, where the fact is phase 9's; to phase 10's inbound list in the roadmap when it is audit or repair
work on an already-planned phase; or to `docs/first-release.md` when it belongs to the release. Note it
under `docs/knowledge/notes/` as well whenever it is a fact about Ruby or a library the corpus states
otherwise, and say in the phase's checklist that the plan's premise moved. Do not quietly rewrite a
later task around it.

- [ ] **Step 5: Stage the change**

**No commit.** `CLAUDE.md`: "Agents do not commit, push, or touch the remote unless the user asks
for that specific action in that message."

```bash
git add -- test/support/warning_capture.rb test/gates/phase9_ruby_facts_test.rb \
        test/fixtures/gates/warns_unused.rb
```

## Task 2: `Runner` — the one place the five statuses are decided

**Files:**
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/runner.rb`
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/check.rb`
- Create: `gems/dexpace-conformance/sig/dexpace/conformance/runner.rbs`, `…/check.rbs`
- **Modify: `gems/dexpace-conformance/lib/dexpace/conformance.rb`** — the `require_relative`s,
  without which every fence below is a `NameError`
- Test: `gems/dexpace-conformance/test/dexpace/conformance/runner_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Conformance::Assertion` (8a: `Data.define(:ids, :name, :body)`, `.build(ids:, name:, body:)`, `#call(subject)`), `Result` (`.build(assertion:, status:, detail: nil)`, statuses `%i[passed failed vacuous waived error]`), `Failure` (`#expected`, `#actual`, `#requirement_ids`), `Vacuous` (`#reason`), `Report` (`.new(results)`)
- Produces: `Dexpace::Conformance::Runner.run(assertions, waive: [], around: nil) { subject } -> Report`

Four suites would otherwise each carry their own status loop, and §11.12's "four reference sync/async drifts" is what four copies of one loop become. `TransportSuite` predates this and is deliberately **not** refactored onto it — phase 8 owns that file and `R6` keeps phase 9 out of it.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The five result statuses of 8a's assertion protocol, decided in one place. NFR-17.
require_relative "../../test_helper"

class DexpaceConformanceRunnerTest < DexpaceConformanceTestCase
  R = Dexpace::Conformance::Runner

  def assertion(ids, name, &body)
    Dexpace::Conformance::Assertion.build(ids: ids, name: name, body: body)
  end

  test "an assertion that returns cleanly is passed" do
    report = R.run([assertion(["X-1"], "clean") { |_s| nil }]) { :subject }

    assert_equal(:passed, report.results.first.status)
  end

  test "a Failure is failed and its expected and actual reach the detail" do
    body = ->(_s) { raise Dexpace::Conformance::Failure.new("no", expected: 1, actual: 2, requirement_ids: ["X-1"]) }
    report = R.run([assertion(["X-1"], "fails", &body)]) { :subject }

    assert_equal(:failed, report.results.first.status)
    assert_includes(report.results.first.detail, "expected 1, got 2")
  end

  test "a Vacuous is vacuous and carries its reason, never passed" do
    body = ->(_s) { raise Dexpace::Conformance::Vacuous, "no adapter has this path" }
    report = R.run([assertion(["X-1"], "vacuous", &body)]) { :subject }

    assert_equal(:vacuous, report.results.first.status)
    assert_equal("no adapter has this path", report.results.first.detail)
  end

  test "any other StandardError is errored, never silently a failure" do
    report = R.run([assertion(["X-1"], "boom") { |_s| raise TypeError, "nope" }]) { :subject }

    assert_equal(:error, report.results.first.status)
    assert_includes(report.results.first.detail, "TypeError")
  end

  test "a waiver matches by requirement id and never by assertion name" do
    report = R.run([assertion(%w[X-1 X-2], "waived") { |_s| raise "never reached" }],
                   waive: ["X-2"]) { :subject }

    assert_equal(:waived, report.results.first.status)
  end

  test "the subject block is called once per assertion, never shared" do
    built = 0
    R.run([assertion(["X-1"], "a") { |_s| nil }, assertion(["X-2"], "b") { |_s| nil }]) do
      built += 1
      :subject
    end

    assert_equal(2, built)
  end

  test "an around wrapper wraps every invocation" do
    wrapped = 0
    around = lambda do |&blk|
      wrapped += 1
      blk.call
    end
    R.run([assertion(["X-1"], "a") { |_s| nil }], around: around) { :subject }

    assert_equal(1, wrapped)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `(cd gems/dexpace-conformance && bundle exec rake test TEST=test/dexpace/conformance/runner_test.rb)`
Expected: FAIL — `uninitialized constant Dexpace::Conformance::Runner`.

- [ ] **Step 3: Write the implementation**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "failure"
require_relative "vacuous"
require_relative "result"
require_relative "report"

module Dexpace
  module Conformance
    # The one loop every suite's `.run` delegates to, so the five statuses are decided in one
    # place. TransportSuite (phase 8a) predates this and is deliberately left untouched -- phase 8
    # owns that file and phase 9 reports rather than refactors (design R6).
    module Runner
      module_function

      # @param assertions [Array[Assertion]] ordered, frozen
      # @param waive [Array[String]] requirement IDs, never assertion names (section 9.3)
      # @param around [Proc, nil] wraps each invocation; an async driver passes
      #   ->(&blk) { Sync { blk.call } }, which is the suite contract's clause 9
      # @yield a subject built fresh per assertion (testing/4ef070df)
      def run(assertions, waive: [], around: nil, &subject)
        Report.new(assertions.map { |assertion| one(assertion, waive, around, subject) })
      end

      # @api private -- `module_function` makes every method below a public singleton method, and
      # the NFR-3 assertion this phase itself ships enumerates those. `private_class_method` keeps
      # `.run` the module's only public entry point.
      def one(assertion, waive, around, subject)
        return Result.build(assertion: assertion, status: :waived) if (assertion.ids & waive).any?

        invoke(assertion, around, subject)
        Result.build(assertion: assertion, status: :passed)
      rescue Vacuous => e
        Result.build(assertion: assertion, status: :vacuous, detail: e.reason)
      rescue Failure => e
        Result.build(assertion: assertion, status: :failed,
                     detail: "#{e.message} (expected #{e.expected.inspect}, got #{e.actual.inspect})")
      rescue ::StandardError => e
        Result.build(assertion: assertion, status: :error, detail: "#{e.class}: #{e.message}")
      end

      def invoke(assertion, around, subject)
        body = -> { assertion.call(subject.call) }
        around.nil? ? body.call : around.call(&body)
      end

      private_class_method :one, :invoke
    end
  end
end
```

**`Check` ships in the same task, in its own file**, because every suite body from Task 5 onward
calls it and because a second public constant inside `invariant_suite.rb` would break this
repository's one-public-constant-per-file rule (`module-organization/1828a984`) *and* fail the
`NFR-3` assertion Task 9 ships — phase 9's own code is inside the surface that assertion walks.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "failure"

module Dexpace
  module Conformance
    # The one assertion primitive every suite's bodies use.
    module Check
      module_function

      def that(condition, message, expected:, actual:, ids:)
        return if condition

        raise Failure.new(message, expected: expected, actual: actual, requirement_ids: ids)
      end
    end
  end
end
```

**Rescue order is load-bearing and is not alphabetical.** `Vacuous` and `Failure` are both `::StandardError` descendants (8a), so the bare `rescue ::StandardError` must come last or it swallows both and every vacuity becomes an error.

- [ ] **Step 4: Write the two `sig/` mirrors**

```rbs
module Dexpace
  module Conformance
    module Runner
      def self.run: (Array[Assertion] assertions, ?waive: Array[String], ?around: Proc?) { () -> untyped } -> Report
    end

    module Check
      def self.that: (untyped condition, String message, expected: untyped, actual: untyped,
                      ids: Array[String]) -> void
    end
  end
end
```

`Runner.one` and `.invoke` get **no** signature: they are `private_class_method` and `sig/` mirrors
the public surface only.

- [ ] **Step 5: Wire the entry file — without this, nothing in the gem loads**

Append to `gems/dexpace-conformance/lib/dexpace/conformance.rb`, after 8a's five requires:

```ruby
require_relative "conformance/check"
require_relative "conformance/runner"
```

**This is the single most load-bearing step in the plan's first half.** 8a's entry file requires
`failure`, `vacuous`, `assertion`, `result` and `report`; a consumer — including this gem's own
suite, which does `require_relative "../../test_helper"` and nothing else — reaches
`Dexpace::Conformance::Runner` only if the entry file names it. Every later task repeats this step
for the constants it adds.

- [ ] **Step 6: Run the test and the type gates**

```bash
(cd gems/dexpace-conformance && bundle exec rake test TEST=test/dexpace/conformance/runner_test.rb)
bundle exec rbs validate && bundle exec steep check
```

Expected: 7 runs, PASS; `rbs validate` and `steep check` clean.

- [ ] **Step 7: Stage the change**

**No commit.** `CLAUDE.md`: "Agents do not commit, push, or touch the remote unless the user asks for that specific action in that message." Every one of the twenty-one preceding plans in this repository has zero commit steps; the reviewer commits.

```bash
git add -- gems/dexpace-conformance/lib/dexpace/conformance/runner.rb
```

---

## Task 3: `Report` gains `#results`, `#to_h` and `.merge`

**Files:**
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance/report.rb`
- Modify: `gems/dexpace-conformance/sig/dexpace/conformance/report.rbs`
- Test: `gems/dexpace-conformance/test/dexpace/conformance/report_test.rb` *(extend 8a's)*
- **No entry-file change**: 8a already requires `report`. This is the one task in the plan's first
  half that adds no new constant.

**Interfaces:**
- Consumes: `Result`
- Produces: `Report#results -> Array[Result]`, `Report#passed -> Array[Result]`, `Report#to_h -> Hash`, `Report.merge(Array[Report]) -> Report`

8a deferred a structured `#to_h` explicitly — "`NFR-4`-locked surface with no caller until phase 9 aggregates three suites". **Phase 9 is the phase with the caller**, so it ships, with a `sig/` mirror, and Task 17 regenerates the API baseline for it.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Phase 9's additions to 8a's Report: the aggregate caller 8a deferred #to_h for. NFR-4.
require_relative "../../test_helper"

class DexpaceConformanceReportPhase9Test < DexpaceConformanceTestCase
  def result(ids, status)
    assertion = Dexpace::Conformance::Assertion.build(ids: ids, name: ids.join("+"), body: ->(_s) { nil })
    Dexpace::Conformance::Result.build(assertion: assertion, status: status)
  end

  test "merge flattens many reports into one passed? over the whole run" do
    merged = Dexpace::Conformance::Report.merge(
      [Dexpace::Conformance::Report.new([result(["XCUT-15"], :passed)]),
       Dexpace::Conformance::Report.new([result(["NFR-1"], :failed)])]
    )

    assert_equal(2, merged.results.size)
    refute(merged.passed?)
  end

  test "a vacuous result does not fail the run" do
    report = Dexpace::Conformance::Report.new([result(["ASYNC-4"], :vacuous)])

    assert(report.passed?)
  end

  test "to_h carries one row per result with its ids, status and detail" do
    report = Dexpace::Conformance::Report.new([result(%w[XCUT-13 XCUT-22], :passed)])

    assert_equal(1, report.to_h[:passed])
    assert_equal(%w[XCUT-13 XCUT-22], report.to_h[:results].first[:ids])
  end

  test "to_s names every waived id on every run, not only when something failed" do
    report = Dexpace::Conformance::Report.new([result(["ASYNC-3"], :waived)])

    assert_includes(report.to_s, "waived (would fail): ASYNC-3")
  end

  test "to_s distinguishes vacuous from waived in separate lines" do
    report = Dexpace::Conformance::Report.new([result(["ASYNC-4"], :vacuous), result(["ASYNC-3"], :waived)])

    assert_includes(report.to_s, "vacuous: ASYNC-4")
    assert_includes(report.to_s, "waived (would fail): ASYNC-3")
  end
end
```

*(`"a vacuous result does not fail the run"` is written as filed and is **replaced by Task 12a**,
which splits it by level — a SHOULD-level vacuity still does not fail the run; an un-waived,
un-accepted MUST-level one does. Until Task 12a lands it is the truthful statement of a `Report`
that knows no levels; added 2026-09-13.)*

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `NoMethodError: undefined method 'merge' for class Dexpace::Conformance::Report`.

- [ ] **Step 3: Write the implementation**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    # A frozen list of Results. Phase 8a shipped #to_s; phase 9 adds the structured form it
    # deferred ("NFR-4-locked surface with no caller until phase 9 aggregates three suites") and
    # the merge the aggregate needs.
    class Report
      # Merging Results rather than Reports keeps a single #passed? over the whole run, which is
      # what a CI step needs.
      def self.merge(reports)
        new(reports.flat_map(&:results))
      end

      attr_reader :results

      def initialize(results)
        @results = results.freeze
      end

      def passed?
        failures.empty? && errors.empty?
      end

      def passed = by_status(:passed)
      def failures = by_status(:failed)
      def vacuous = by_status(:vacuous)
      def waived = by_status(:waived)
      def errors = by_status(:error)

      # Section 9.3: "the gap stays visible rather than disappearing into a restated item" -- every
      # waived id is named on every run. Waived and vacuous are rendered in separate sections
      # because section 12 counts them as different things: a waived assertion WOULD have failed,
      # a vacuous one could not have run.
      def to_s
        lines = ["#{passed.size} passed, #{failures.size} failed, #{vacuous.size} vacuous, " \
                 "#{waived.size} waived, #{errors.size} errored"]
        waived.each { |r| lines << "  waived (would fail): #{r.assertion.ids.join(", ")} (#{r.assertion.name})" }
        vacuous.each { |r| lines << "  vacuous: #{r.assertion.ids.join(", ")}: #{r.detail}" }
        failures.each { |r| lines << "  FAILED: #{r.assertion.ids.join(", ")}: #{r.detail}" }
        errors.each { |r| lines << "  ERROR: #{r.assertion.ids.join(", ")}: #{r.detail}" }
        lines.join("\n")
      end

      def to_h
        {
          passed: passed.size, failed: failures.size, vacuous: vacuous.size,
          waived: waived.size, errored: errors.size,
          results: @results.map do |r|
            { ids: r.assertion.ids, name: r.assertion.name, status: r.status, detail: r.detail }
          end
        }
      end

      private

      def by_status(status)
        @results.select { |r| r.status == status }
      end
    end
  end
end
```

- [ ] **Step 4: Extend the `sig/` mirror**

Add `attr_reader results: Array[Result]`, `def passed: () -> Array[Result]`, `def to_h: () -> Hash[Symbol, untyped]` and `def self.merge: (Array[Report]) -> Report`.

- [ ] **Step 5: Run 8a's report test and this one together**

Expected: 8a's existing report assertions still pass — `#to_s`'s first line keeps its shape and only gains sections — plus 5 new runs.

- [ ] **Step 6: Stage the change**

**No commit.** `CLAUDE.md`: "Agents do not commit, push, or touch the remote unless the user asks for that specific action in that message." Every one of the twenty-one preceding plans in this repository has zero commit steps; the reviewer commits.

```bash
git add -- gems/dexpace-conformance/lib/dexpace/conformance/report.rb
```

---

## Task 4: `SharedInstance` — `XCUT-11`'s structural predicate

**Files:**
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/shared_instance.rb`
- Create: `gems/dexpace-conformance/sig/dexpace/conformance/shared_instance.rbs`
- Test: `gems/dexpace-conformance/test/dexpace/conformance/shared_instance_test.rb`

**Files (addendum):**
- **Modify: `gems/dexpace-conformance/lib/dexpace/conformance.rb`** — `require_relative "conformance/shared_instance"`

**Interfaces:**
- Consumes: `Failure`
- Produces: `Dexpace::Conformance::SharedInstance.audit(object, mutable: [], ids: ["XCUT-11"]) -> void`

**`mutable:` is the DRIVER's declaration, never read off the audited object.** An earlier draft had
the assertion ask the subject (`step.respond_to?(:conformance_mutable_state)`), and measured, that
inverts the requirement in both directions: a conforming latch-plus-mutex `Closeable` **fails**,
because no phase committed to such a method and `R6` forbids phase 9 adding one to another gem — the
exact false condemnation `P9-9` exists to prevent — while the identical per-call-state bug **passes**
by declaring `[:@attempt]`. The driver is `dexpace-core`'s own suite and knows which ivar is which;
the audited object must not get a vote on its own exemption.

`XCUT-11` is the heaviest hand-forward target — nine rows across five phase documents — and no phase defined what "audited" means. A *frozen and no ivars* rule would condemn every `Closeable` in the SDK, because `cross-cutting-invariants/89eb6533` makes close idempotence "a `@closed` boolean flipped under a `Thread::Mutex`". So two kinds of mutable state are permitted and both must be **declared by the subject** (design `R8`, `P9-9`).

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# XCUT-11's structural half: per-call mutable state must not live on a shared instance, and the
# two kinds that legitimately do must be declared. Design R8, P9-9.
require_relative "../../test_helper"

class DexpaceConformanceSharedInstanceTest < DexpaceConformanceTestCase
  S = Dexpace::Conformance::SharedInstance

  class Frozen
    def initialize = freeze
  end

  class Latched
    def initialize
      @closed = false
      @lock = Thread::Mutex.new
    end
  end

  class PerCallState
    def initialize = (@attempt = 0)
  end

  test "a frozen instance with no state conforms" do
    S.audit(Frozen.new)
  end

  test "a latch and its mutex conform when the subject declares them" do
    S.audit(Latched.new, mutable: %i[@closed @lock])
  end

  test "an undeclared mutable ivar on a shared instance raises a Failure naming it" do
    error = assert_raises(Dexpace::Conformance::Failure) { S.audit(PerCallState.new) }

    assert_equal([:@attempt], error.actual)
    assert_equal(["XCUT-11"], error.requirement_ids)
  end

  test "declaring only some of the state still fails on the rest" do
    assert_raises(Dexpace::Conformance::Failure) { S.audit(Latched.new, mutable: [:@lock]) }
  end

  test "the requirement ids are overridable so a seam suite can cite its own pair" do
    error = assert_raises(Dexpace::Conformance::Failure) do
      S.audit(PerCallState.new, ids: %w[XCUT-11 SEAM-12])
    end

    assert_equal(%w[XCUT-11 SEAM-12], error.requirement_ids)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `uninitialized constant Dexpace::Conformance::SharedInstance`.

- [ ] **Step 3: Write the implementation**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "failure"

module Dexpace
  module Conformance
    # XCUT-11's structural half, as one predicate (design R8, P9-9).
    #
    # A frozen-and-no-ivars rule would condemn every Closeable in the SDK, because
    # cross-cutting-invariants/89eb6533 makes close idempotence a @closed latch flipped under a
    # Thread::Mutex. So two kinds of mutable state are permitted -- a mutex with the state it
    # guards, and Closeable's latch -- and both must be DECLARED by the caller: only the object
    # knows which ivar is its mutex and which is the state under it.
    module SharedInstance
      module_function

      # @param object [Object] the shared instance under audit
      # @param mutable [Array[Symbol]] ivars the DRIVER declares as guarded state or a close
      #   latch. Never read off the audited object: no phase committed to such a method, adding one
      #   is forbidden by R6, and an object that supplied its own exemption list could exempt the
      #   per-call state XCUT-11 exists to forbid.
      # @param ids [Array[String]] requirement IDs the raised Failure carries
      def audit(object, mutable: [], ids: ["XCUT-11"])
        return if object.frozen? && object.instance_variables.empty?

        undeclared = object.instance_variables - mutable
        return if undeclared.empty?

        raise Failure.new(
          "#{object.class} is shared across concurrent requests and holds undeclared mutable state",
          expected: mutable.sort, actual: object.instance_variables.sort, requirement_ids: ids
        )
      end
    end
  end
end
```

- [ ] **Step 4: Wire the entry file, write the `sig/` mirror, run the test, run the type gates**

Append to `gems/dexpace-conformance/lib/dexpace/conformance.rb`. Without it `SharedInstance` is
reachable only through `invariant_suite.rb`'s own `require_relative`, and a consumer that requires
the entry file and names the constant directly gets a `NameError`:

```ruby
require_relative "conformance/shared_instance"
```

Expected: 5 runs, PASS.

- [ ] **Step 5: Stage the change**

**No commit.** `CLAUDE.md`: "Agents do not commit, push, or touch the remote unless the user asks for that specific action in that message." Every one of the twenty-one preceding plans in this repository has zero commit steps; the reviewer commits.

```bash
git add -- gems/dexpace-conformance/lib/dexpace/conformance.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/shared_instance.rb
```

---

## Task 5: `InvariantCase`, the probe, and the model/lifecycle assertions

**Files:**
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/invariant_case.rb`
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite.rb`
- Create: two `sig/` mirrors
- **Modify: `gems/dexpace-conformance/lib/dexpace/conformance.rb`** — both `require_relative`s
- Test: `gems/dexpace-conformance/test/dexpace/conformance/invariant_suite_test.rb`

**Interfaces:**
- Consumes: `Assertion`, `Check`, `Failure`, `Vacuous`, `Runner`, `SharedInstance`
- Produces: `InvariantCase.new(core:, seam: nil, mutable: [], transport: nil)` with `#core`, `#mutable`,
  **`#probe!(name, promised_by, method: false)`**, `#seam?`, `#seam(**settings)`, `#transport?`,
  `#transport` *(added 2026-09-13: the transport factory Task 7's forged-request assertion drives —
  a separate keyword because `seam:` is already the pipeline-step factory `XCUT-11`'s tests
  supply, and one keyword cannot hand two assertions two different objects)*,
  `#bounded_map(cap:)`, `#bounded_map_store(map)`, `#draw_cnonce(source)`,
  `#redirect_hop(from:, to:, headers:)`, `#with_bounded_map`, `#with_bounded_map_store`,
  `#with_cnonce`, `#with_redirect_hops`;
  `InvariantSuite.assertions -> Array[Assertion]`;
  `InvariantSuite.run(core: ::Dexpace, seam: nil, transport: nil, mutable: [], bounded_map: nil, bounded_map_store: nil, cnonce: nil, redirect_hops: nil, waive: [], around: nil) -> Report`

**`probe!` lands here, in the first audit task, not in Task 6.** It was measured: with the probe
introduced a task later, `XCUT-15`, `XCUT-13` and `XCUT-22` report `:error` rather than `:vacuous`
against a core that has not built `Headers` yet — a `NoMethodError` wrapped as `:error` says
"something went wrong in the suite", and `:vacuous` with a reason says "phase 1 committed to
`Headers` and it is not there". Phase 10 acts on that distinction.

**Every double below is built from the predecessor's filed fence, not from its prose.** Phase 1
filed `Headers.build(values:, casing:, direction: :outbound)` (plan line 1257) — **not** a
positional hash. Phase 4a filed `BoundedMap` with `#set`/`#put`/`#[]`/`#size` and `.new(cap:)` as a
`private_constant` (plan line 842). Phase 6c filed `Auth::DigestHandler.new(credential,
preference:, cap:, cnonce_source: ::SecureRandom)` calling `@cnonce_source.hex(16)` (design line
630) — **not** an `Auth::Digest.cnonce` module function.

**This task's code was executed during planning** against conforming and non-conforming doubles
built from those fences: **13 runs, 18 assertions, 0 failures on 3.2.11, 3.4.10 and 4.0.6**, under
`ruby -w`. The fences below are that code.

- [ ] **Step 1: Write `invariant_case.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "vacuous"

module Dexpace
  module Conformance
    # What an InvariantSuite assertion receives.
    #
    # `core` is the loaded Dexpace module -- XCUT's subjects are core constants, not an instance.
    # `seam` is an optional factory for the IDs that are per-implementation. `mutable` is the
    # DRIVER's declaration of which instance variables on a shared instance are a mutex with the
    # state it guards or Closeable's latch (design P9-9): never read off the audited object, which
    # could then exempt the per-call state XCUT-11 forbids.
    class InvariantCase
      attr_reader :core, :mutable

      def initialize(core:, seam: nil, mutable: [], transport: nil)
        @core = core
        @seam = seam
        @mutable = mutable
        @transport = transport
      end

      # Design R3: every audit opens with an existence probe against the name the owning phase
      # committed to, and an ABSENT artifact is :vacuous naming who promised it -- not :failed.
      # Phase 9 is planned before any code exists, so at execution time an artifact may legitimately
      # not be built yet; reporting :failed would conflate "not built" with "built wrong", which is
      # the distinction phase 10 acts on. Nothing passes by not being built: an un-waived :vacuous
      # on a MUST-level ID is a phase-9 report blocker and earns a docs/first-release.md line.
      def probe!(name, promised_by, method: false)
        present = method ? @core.respond_to?(name) : @core.const_defined?(name)
        return if present

        raise Vacuous, "#{name} is absent; #{promised_by} committed to it"
      end

      def seam?
        !@seam.nil?
      end

      def seam(**settings)
        raise Vacuous, "no seam implementation supplied to InvariantSuite.run" if @seam.nil?

        @seam.call(**settings)
      end

      # A transport factory, for the one assertion whose subject is an adapter's dispatch path
      # (XCUT-18's second assertion, the wire-boundary re-validation's phase-9 clause). Kept apart from `seam` because the
      # driver may supply both and they are different objects.
      def transport?
        !@transport.nil?
      end

      def transport
        raise Vacuous, "no transport factory supplied to InvariantSuite.run" if @transport.nil?

        @transport.call
      end

      # Dexpace::BoundedMap is a private_constant on Dexpace (4a's P4-3), bare-name reachable from
      # every full-nesting descendant and from nothing else -- so the suite cannot const_get it, and
      # the driver, which is dexpace-core's own suite, hands in a factory instead.
      def bounded_map(cap:)
        raise Vacuous, "no bounded-map factory supplied to InvariantSuite.run" if @bounded_map.nil?

        @bounded_map.call(cap: cap)
      end

      def with_bounded_map(factory)
        @bounded_map = factory
        self
      end

      # XCUT-14's drain clause needs the map's backing Hash, which 4a's BoundedMap keeps private
      # (@h, 4a plan:842-892). The driver knows that name and hands in a reader, exactly as it hands
      # in the factory; the suite itself never reaches into the object.
      def bounded_map_store(map)
        if @bounded_map_store.nil?
          raise Vacuous, "no bounded-map store reader supplied to InvariantSuite.run"
        end

        @bounded_map_store.call(map)
      end

      def with_bounded_map_store(reader)
        @bounded_map_store = reader
        self
      end

      # XCUT-17 needs one redirect re-issue driven through 6b's step. Building the step, its cursor
      # and the scripted 3xx is the driver's job; the assertion needs only the re-issued request
      # back -- anything answering #headers (with #[]) and #url -- or the error a refusal raises.
      def redirect_hop(from:, to:, headers:)
        raise Vacuous, "no redirect driver supplied to InvariantSuite.run" if @redirect_hops.nil?

        @redirect_hops.call(from: from, to: to, headers: headers)
      end

      def with_redirect_hops(driver)
        @redirect_hops = driver
        self
      end

      # 6c's DigestHandler takes cnonce_source: and calls #hex(16) on it; the driver knows how to
      # build one with a credential, and the assertion only needs the draw to happen.
      def draw_cnonce(source)
        raise Vacuous, "no cnonce driver supplied to InvariantSuite.run" if @cnonce.nil?

        @cnonce.call(source)
      end

      def with_cnonce(driver)
        @cnonce = driver
        self
      end
    end
  end
end
```

- [ ] **Step 2: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Appendix B.8's model and lifecycle items. XCUT-15, XCUT-13 (both clauses), XCUT-22.
require_relative "../../test_helper"

class DexpaceConformanceInvariantSuiteTest < DexpaceConformanceTestCase
  S = Dexpace::Conformance::InvariantSuite

  # Doubles built from phase 1's FILED fence: Headers.build(values:, casing:, direction:).
  module ConformingCore
    class Headers
      def self.build(values:, casing:, direction: :outbound)
        new(Dexpace::Model.own(values), Dexpace::Model.own(casing), direction)
      end

      def initialize(values, casing, direction)
        @values = values
        @casing = casing
        @direction = direction
      end

      def [](name) = @values[name]
    end
  end

  # The non-conforming double: it keeps the caller's own hash instead of owning it.
  module AliasingCore
    class Headers
      def self.build(values:, casing:, direction: :outbound) = new(values)
      def initialize(values) = (@values = values)
      def [](name) = @values[name]
    end
  end

  class LatchedSeam
    attr_reader :release_count

    def initialize(client: nil)
      @client = client
      @owned = client.nil?
      @closed = false
      @release_count = 0
      @lock = Thread::Mutex.new
    end

    def call(request) = [request, 1]

    def close
      @lock.synchronize do
        return if @closed

        @closed = true
      end
      @release_count += 1
      @client.close if @owned && !@client.nil?
    end
  end

  class UnlatchedSeam < LatchedSeam
    def close
      @release_count += 1
      @client&.close
    end
  end

  DECLARED = %i[@client @owned @closed @release_count @lock].freeze

  def statuses(report)
    report.results.each_with_object({}) { |r, h| (h[r.assertion.ids.first] ||= []) << r.status }
  end

  def conforming(core: ConformingCore, seam: ->(**kw) { LatchedSeam.new(**kw) })
    S.run(core: core, seam: seam, mutable: DECLARED)
  end

  test "a conforming core and seam pass every model and lifecycle assertion" do
    report = conforming

    assert_equal([:passed], statuses(report)["XCUT-15"])
    assert_equal(%i[passed passed], statuses(report)["XCUT-13"])
    assert_equal([:passed], statuses(report)["XCUT-22"])
  end

  test "a model aliasing a caller's collection fails XCUT-15" do
    report = conforming(core: AliasingCore)

    assert_equal([:failed], statuses(report)["XCUT-15"])
    refute(report.passed?)
  end

  test "an unlatched close fails the first of XCUT-13's two assertions and passes the second" do
    report = conforming(seam: ->(**kw) { UnlatchedSeam.new(**kw) })

    assert_equal(%i[failed passed], statuses(report)["XCUT-13"])
  end

  test "XCUT-13 carries two assertions because the requirement has two clauses" do
    assert_equal(2, S.assertions.count { |a| a.ids.include?("XCUT-13") })
  end

  test "a holder that closes a borrowed resource fails XCUT-22" do
    closing = Class.new(LatchedSeam) do
      def close
        super
        @client&.close
      end
    end

    report = conforming(seam: ->(**kw) { closing.new(**kw) })

    assert_equal([:failed], statuses(report)["XCUT-22"])
  end

  test "an absent artifact is vacuous with a reason, never failed and never errored" do
    report = S.run(core: Module.new, seam: ->(**kw) { LatchedSeam.new(**kw) }, mutable: DECLARED)

    assert_equal([:vacuous], statuses(report)["XCUT-15"])
    assert_includes(report.to_s, "Headers is absent; phase 1's domain model committed to it")
  end

  test "with no seam supplied the per-implementation ids are vacuous, never passed" do
    report = S.run(core: ConformingCore)

    assert_equal(%i[vacuous vacuous], statuses(report)["XCUT-13"])
    assert_equal([:vacuous], statuses(report)["XCUT-22"])
    assert(report.passed?, "a vacuous result must not fail the run")
  end

  test "a waiver is keyed by requirement id and is named on every run" do
    report = S.run(core: AliasingCore, waive: ["XCUT-15"])

    assert_equal([:waived], statuses(report)["XCUT-15"])
    assert_includes(report.to_s, "waived (would fail): XCUT-15")
  end
end
```

- [ ] **Step 3: Run to verify it fails**

Run: `(cd gems/dexpace-conformance && bundle exec rake test TEST=test/dexpace/conformance/invariant_suite_test.rb)`
Expected: FAIL — `uninitialized constant Dexpace::Conformance::InvariantSuite`.

- [ ] **Step 4: Write `invariant_suite.rb` with the four assertions**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "assertion"
require_relative "check"
require_relative "failure"
require_relative "invariant_case"
require_relative "runner"
require_relative "shared_instance"
require_relative "vacuous"

module Dexpace
  module Conformance
    # Appendix B.8. One Result per assertion, assertions keyed by requirement ID, and an
    # appendix-B item is a view over the assertions for its IDs (design P9-8) -- which is what lets
    # XCUT-13 carry two assertions for its two clauses without a second ID.
    module InvariantSuite
      module_function

      def assertions
        @assertions ||= [immutable_models, idempotent_close, non_blocking_close,
                         only_closes_what_it_created].freeze
      end

      def run(core: ::Dexpace, seam: nil, transport: nil, mutable: [], bounded_map: nil,
              bounded_map_store: nil, cnonce: nil, redirect_hops: nil, waive: [], around: nil)
        Runner.run(assertions, waive: waive, around: around) do
          InvariantCase.new(core: core, seam: seam, mutable: mutable, transport: transport)
                       .with_bounded_map(bounded_map).with_bounded_map_store(bounded_map_store)
                       .with_cnonce(cnonce).with_redirect_hops(redirect_hops)
        end
      end

      # XCUT-15: "mutate a collection passed into a builder AFTER build; assert the built model is
      # unchanged". Phase 1 filed Headers.build(values:, casing:, direction:) -- keywords, and a
      # Hash of String => Array[String], so the mutation is on the inner array.
      def immutable_models
        Assertion.build(ids: ["XCUT-15"], name: "public wire models retain no external-mutable alias",
                        body: lambda do |subject|
                          subject.probe!(:Headers, "phase 1's domain model")
                          live = { "accept" => ["text/plain"] }
                          model = subject.core::Headers.build(values: live,
                                                              casing: { "accept" => "Accept" })
                          live["accept"] << "application/json"

                          Check.that(model["accept"] == ["text/plain"],
                                     "a model changed when a collection passed into its builder " \
                                     "was mutated",
                                     expected: ["text/plain"], actual: model["accept"],
                                     ids: ["XCUT-15"])
                        end)
      end

      # XCUT-13, clause 1: "close()/shutdown() MUST be idempotent (latched so repeats are no-ops)".
      # Counted at the resource, never inferred from close's return value.
      def idempotent_close
        Assertion.build(ids: ["XCUT-13"], name: "close is latched so repeats are no-ops",
                        body: lambda do |subject|
                          seam = subject.seam
                          seam.close
                          seam.close

                          Check.that(seam.release_count == 1,
                                     "close ran its release more than once",
                                     expected: 1, actual: seam.release_count, ids: ["XCUT-13"])
                        end)
      end

      # XCUT-13, clause 2: "and MUST NOT block on interrupt-sensitive waits". The design names this
      # as one of TWO assertions and not three; without it the requirement's second clause has no
      # check at all. Bounded by elapsed monotonic time, never by an interrupt -- section 8.3 bans
      # Timeout.timeout, Thread#raise and Thread#kill outright.
      def non_blocking_close
        Assertion.build(ids: ["XCUT-13"], name: "close does not block on an interrupt-sensitive wait",
                        body: lambda do |subject|
                          seam = subject.seam
                          started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
                          seam.close
                          elapsed = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started

                          Check.that(elapsed < 0.5,
                                     "close blocked rather than signalling and returning",
                                     expected: "< 0.5s", actual: elapsed.round(3), ids: ["XCUT-13"])
                        end)
      end

      # XCUT-22: "build a transport around a caller-supplied client, close the transport, then reuse
      # the client -> it still works."
      def only_closes_what_it_created
        Assertion.build(ids: ["XCUT-22"], name: "a caller-supplied resource survives the SDK's close",
                        body: lambda do |subject|
                          borrowed = Object.new
                          def borrowed.closed? = @closed == true
                          def borrowed.close = @closed = true

                          seam = subject.seam(client: borrowed)
                          seam.close

                          Check.that(!borrowed.closed?,
                                     "the SDK closed a resource it did not create",
                                     expected: false, actual: borrowed.closed?, ids: ["XCUT-22"])
                        end)
      end
    end
  end
end
```

- [ ] **Step 5: Wire the entry file**

```ruby
require_relative "conformance/invariant_case"
require_relative "conformance/invariant_suite"
```

- [ ] **Step 6: Run on the four installed interpreters**

```bash
for v in 3.2.11 3.3.12 3.4.10 4.0.6; do
  mise exec ruby@$v -- ruby -w -Igems/dexpace-conformance/lib -Igems/dexpace-core/lib \
    gems/dexpace-conformance/test/dexpace/conformance/invariant_suite_test.rb
done
```

Expected: 8 runs, PASS on each. (The planning prototype of these assertions plus Tasks 6–8's, driven
together, measured **13 runs, 18 assertions, 0 failures** on all three.)

- [ ] **Step 7: Stage the change**

**No commit.**

```bash
git add -- gems/dexpace-conformance/lib/dexpace/conformance.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/invariant_case.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite.rb \
        gems/dexpace-conformance/sig/dexpace/conformance/invariant_case.rbs \
        gems/dexpace-conformance/sig/dexpace/conformance/invariant_suite.rbs \
        gems/dexpace-conformance/test/dexpace/conformance/invariant_suite_test.rb
```

## Task 6: `InvariantSuite` — the error taxonomy and retry classification

**Files:**
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite.rb`
- Test: `gems/dexpace-conformance/test/dexpace/conformance/invariant_suite_taxonomy_test.rb`

**Interfaces:**
- Consumes: Task 5's `InvariantCase#probe!` and `Check`; from core — `Dexpace::Error` (a **module**,
  `P1-1`), `Dexpace::ProtocolError` with `.for` / `.for_or_nil` (4b), `Dexpace::TransportError <
  ::IOError` with `#retryable?` always true (8a's phase-level task),
  `Dexpace::Retryability.retryable_status?` (5a), `Dexpace.each_cause` (4b)
- Produces: seven more assertions, one per ID: `XCUT-4`, `XCUT-5`, `XCUT-6`, `XCUT-7`, `XCUT-8`,
  `XCUT-9`, `XCUT-10`

**Amendment, 2026-09-13 — `XCUT-9`'s two measured blind spots, and what the suite does about them.**
Two shapes of `Dexpace.each_cause` defeat the assertion Step 3 writes, and **this task decides how each
is reported** rather than leaving the residue to be discovered at execution. **(1) A collect-then-yield
walk hangs the suite.** An implementation that gathers the whole chain into an array before yielding
never returns its first element on a cyclic chain, so the step-bounded `Enumerator#next` drive never
gets a step to count — measured, the review's `collect` mutation was still running when a 20-second
`timeout` killed it on 3.4.10. Bounding it would need an interrupt, which §8.3 bans outright, and
`Thread#join(limit)` would return while leaving an unkillable thread spinning for the rest of the
process. The suite therefore **cannot** report `:failed` on that shape: decide here how it reports a
walk it cannot bound — a documented hang with the harness's own outer timeout as the only bound, or a
`:vacuous` carrying that reason — and write the decision into the assertion's YARD comment beside the
step bound, so the next reader does not re-derive it. **(2) A depth cap exactly equal to the cycle
length passes.** A walk that stops after three steps reports `:passed` against the three-node cycle on
3.2.11, 3.3.12, 3.4.10 and 4.0.6, because a black-box test over one finite input cannot tell a counter
from a visited set. Decide whether driving **several** cycle lengths is worth its narrowing of the cap
case — a cap of N survives only the N-node cycle — and either drive them or say in the comment why one
length is enough. Task 13's `gates:cause_walk` keeps the walk in one file, which bounds where either
defect could live and proves neither absent. **Whatever is decided, the residue is stated on the
`XCUT-9` checklist row** in Task 16, not left implied by a green result.

**Amendment, 2026-09-13 — factory visibility, and it binds Tasks 6 through 11.** `module_function`
makes every assertion factory a **public** singleton method, and none of them has a `sig/` mirror —
which `CLAUDE.md`'s public-surface rule ("public means a `Dexpace::` constant that has a YARD block and
an RBS signature in its gem's `sig/`") and the `NFR-3` assertion this phase itself ships both refuse.
Measured by walking each module's `singleton_methods(false)` over this plan's own fences on 3.2.11 and
4.0.6: `InvariantSuite` exposes **15** factories besides `.assertions` and `.run` (14 before the
2026-09-13 fix added `bounded_map_drains`; its new `XCUT-21` helpers are already `private_class_method`
and do not appear), `ExecutorSuite` **6**, `PackagingSuite` **4**, `CodecSuite` **2**. **So every
factory written in Tasks 6–11 gets `private_class_method` after its definition**, exactly as `Runner`
already hides its helpers (Task 2), leaving `.assertions` and `.run` as each suite's only public
singleton methods. `InvariantSuite`'s 15 is a whole-module count, so it includes the four factories
Task 5 opened that file with: they take the same fix, applied here rather than in a task of their own,
because the rule is one line per factory and not a task's worth of work. The same rule in the other
direction is **one public class per file**: a case file's helper class is outside
`module-organization/1828a984`'s only sanctioned exception, *a class-level **private** struct or
`Data.define` used nowhere but that file*, unless it is marked
`private_constant` — Task 10's `CodecCase::CountingSink` and Task 11's `ExecutorCase::EventRecorder`
are the two instances, and each carries the fix in its own task. None of this is cosmetic: `rbs
validate`, `steep check` and the runtime surface snapshot all run in Task 17, so a suite written the
loose way reddens the phase's last task rather than shipping.

- [ ] **Step 1: Write the failing test, one non-conforming double per assertion**

The tests for the **two assertions Step 3 writes in full** are given — `XCUT-4`, and `XCUT-9`'s two
cases. The five shape-specified IDs (`XCUT-5`, `XCUT-6`, `XCUT-7`, `XCUT-8`, `XCUT-10`) get their
non-conforming doubles in the step that writes each assertion, in the identical shape (a
`Module.new` carrying the one constant the assertion probes, defective in exactly the clause the
assertion names). A test naming an ID whose assertion is not yet written fails for that reason alone,
which is why none is printed here.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Appendix B.8's error-taxonomy and retry-classification items.
# XCUT-4 and XCUT-9 here; XCUT-5, XCUT-6, XCUT-7, XCUT-8 and XCUT-10 add theirs with their assertions.
require_relative "../../test_helper"

class DexpaceConformanceInvariantTaxonomyTest < DexpaceConformanceTestCase
  S = Dexpace::Conformance::InvariantSuite

  def statuses(report) = report.results.to_h { |r| [r.assertion.ids.first, r.status] }

  test "a transport error outside the IOError family fails XCUT-4" do
    core = Module.new do
      const_set(:TransportError, Class.new(::StandardError) { def retryable? = true })
    end

    assert_equal(:failed, statuses(S.run(core: core))["XCUT-4"])
  end

  test "a DEPTH-CAPPED cause walk fails XCUT-9, which a two-node cycle could not detect" do
    core = Module.new do
      def self.each_cause(error)
        return enum_for(:each_cause, error) unless block_given?

        current = error
        2.times do
          break if current.nil?

          yield current
          current = current.cause
        end
      end
    end

    assert_equal(:failed, statuses(S.run(core: core))["XCUT-9"])
  end

  test "a NON-TERMINATING cause walk reports failed rather than hanging the suite" do
    core = Module.new do
      def self.each_cause(error)
        return enum_for(:each_cause, error) unless block_given?

        current = error
        loop do
          yield current
          current = current.cause
        end
      end
    end

    assert_equal(:failed, statuses(S.run(core: core))["XCUT-9"])
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — neither assertion exists, so `statuses(...)` returns `nil` for both keys.

- [ ] **Step 3: Write the seven assertions**

Two in full. `XCUT-9` is given in full because its first draft was **wrong in two ways that a green
run would have hidden**: a two-node cycle cannot distinguish an identity-tracking walk from one that
merely stops after two steps, and `.to_a` over a non-terminating walk **hangs** — measured, killed
at 15 s with unbounded array growth — rather than reporting `:failed`. Three or more nodes fixes the
first; bounding the drive by **step count** through `Enumerator#next` fixes the second, and needs
none of §8.3's banned interrupt primitives, which is why the first draft's reasoning that a bound
was unavailable was simply false.

```ruby
      # XCUT-4: "a connection failure maps to the I/O-family error with no response and
      # isRetryable true, catchable as a generic I/O error." The IOError ancestry is the half a port
      # gets wrong -- phase 1 made Dexpace::Error a MODULE (P1-1) precisely so a transport error
      # could sit in Ruby's IOError family and still be caught by a broad rescue.
      def two_branch_taxonomy
        Assertion.build(ids: ["XCUT-4"], name: "transport errors are I/O-family and always retryable",
                        body: lambda do |subject|
                          subject.probe!(:TransportError, "8a's phase-level task")
                          klass = subject.core.const_get(:TransportError)

                          Check.that(klass < ::IOError,
                                     "a transport error is outside the runtime's I/O-error family",
                                     expected: "< ::IOError", actual: klass.ancestors.take(4),
                                     ids: ["XCUT-4"])
                          error = klass.new("refused")
                          Check.that(error.retryable? == true,
                                     "a transport error does not report itself always-retryable",
                                     expected: true, actual: error.retryable?, ids: ["XCUT-4"])
                        end)
      end

      # XCUT-9: "track visited causes by reference identity and terminate on a self-referential or
      # cyclic chain." Conformance: "build an error whose cause points back to itself and run the
      # classifier; assert it returns WITHOUT HANGING."
      #
      # THREE nodes, not two: a two-node cycle is indistinguishable from a walk that simply stops
      # after two steps, so a depth-capped implementation would pass. And the walk is driven through
      # Enumerator#next under a STEP BOUND rather than #to_a, so a non-terminating walk reports
      # :failed instead of hanging the whole suite -- a bound on iterations needs no interrupt and is
      # therefore not touched by section 8.3's prohibition.
      def cycle_safe_cause_walk
        Assertion.build(ids: ["XCUT-9"], name: "the cause walk terminates on a self-referential chain",
                        body: lambda do |subject|
                          subject.probe!(:each_cause, "4b's Dexpace.each_cause", method: true)
                          nodes = Array.new(3) { |i| ::StandardError.new("node-#{i}") }
                          nodes.each_with_index do |node, i|
                            node.instance_variable_set(:@loop, nodes[(i + 1) % nodes.size])
                            # Exception#cause is not assignable, so the cycle is built through a
                            # singleton reader -- the only portable way to produce the shape XCUT-9
                            # names on CRuby. Verified on 3.2.11, 3.4.10 and 4.0.6.
                            def node.cause = @loop
                          end

                          walked = []
                          enumerator = subject.core.each_cause(nodes.first)
                          begin
                            8.times { walked << enumerator.next }
                          rescue ::StopIteration
                            nil
                          end

                          Check.that(walked.size == 3,
                                     "the cause walk did not terminate after visiting the cycle once",
                                     expected: 3, actual: walked.size, ids: ["XCUT-9"])
                        end)
      end
```

The remaining five — `XCUT-5`, `XCUT-6`, `XCUT-7`, `XCUT-8`, `XCUT-10` — each open with
`subject.probe!`, quote their conformance clause in the YARD comment, and route every comparison
through `Check.that`. `XCUT-5` walks the classifier over `[408, 429, 500, 501, 505, 507, 404]` and
asserts the exact membership the requirement fixes; `XCUT-7` widens and narrows a configurable set
and asserts the retry step consults *it* and not the baked flag; `XCUT-10` drives the five-case
matrix the requirement enumerates (body-less GET, body-less POST on a protocol error, body-less POST
on a **transport** error, POST with a replayable body, POST with a streaming body).

- [ ] **Step 4: Run on the four installed interpreters**

Expected: **3 runs, PASS** from the fences above — one per test Step 1 prints; each shape-specified
assertion adds its own test when it is written. The `#cause` singleton construction is the riskiest
line in the task — verify it on **3.2.11** specifically, where `Exception#cause` semantics are
likeliest to differ. Re-measured 2026-09-13 on 3.2.11, 3.3.12, 3.4.10 and 4.0.6, including the
non-terminating case, which returns in milliseconds rather than hanging.

- [ ] **Step 5: Stage the change**

**No commit.**

```bash
git add -- gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite.rb \
        gems/dexpace-conformance/test/dexpace/conformance/invariant_suite_taxonomy_test.rb
```

---

## Task 7: `InvariantSuite` — the security and bounded-memory assertions

**Files:**
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite.rb`
- Test: `gems/dexpace-conformance/test/dexpace/conformance/invariant_suite_security_test.rb`

**Interfaces:**
- Consumes: Task 5's `probe!`, `#bounded_map`, `#bounded_map_store`, `#draw_cnonce`,
  `#redirect_hop`; from core —
  `Dexpace::HeaderSyntax.validate_name!(name)` and `.validate_outbound_value!(value, name:)`
  (phase 1's filed signature: `name:` is **required**), `Dexpace::BoundedMap` (4a, a
  `private_constant`, reached through the driver's factory),
  `Dexpace::Instrumentation::Redactor` with `#url`, `#header_value`, `#header_name?`, `#policy` and
  `DEFAULT` (5b's filed name — **not** `Dexpace::Redactor`, which does not exist),
  `Dexpace::Auth::DigestHandler.new(credential, cnonce_source:)` (6c), `Dexpace::Redirect::Step`
  with `#call(request, cursor)` (6b)
- Produces: ten more assertions over eight IDs — `XCUT-14` carries **two**, `bounded_maps` (the cap
  clause) and `bounded_map_drains` (the drain-to-cap clause); `XCUT-18` carries **two**,
  `header_syntax_validation` (the validator's own contract) and `forged_request_is_refused_at_dispatch`
  (the **call site**: the wire-boundary re-validation's phase-9 clause, added 2026-09-13); all four added to
  `InvariantSuite.assertions` — plus `XCUT-16`, `XCUT-17`, `XCUT-19`, `XCUT-20`, `XCUT-21`, `XCUT-24`

**Five of the eight IDs are written in full below** — `XCUT-14` (as two assertions), `XCUT-17`, `XCUT-18` (as two assertions), `XCUT-19`,
`XCUT-21` — because each carries three, four, four, five and two clauses respectively that a single
`Check.that` demonstrably cannot express, and because the assertions written in full in the first
draft each contained a measured defect. `XCUT-16`, `XCUT-20` and `XCUT-24` stay specified by shape.

**Why `XCUT-18` carries two, stated because the first draft carried one and it was the wrong one.**
`header_syntax_validation` proves that `Dexpace::HeaderSyntax` rejects the splitting bytes — a
property phase 1 already tests in core. Phase 1's postponement hands phase 9 a different clause: "phase 9's
conformance suite is where the assertion that it happened belongs", where *it* is the adapter
**re-running** that validation immediately before dispatch, over a `Request` that never met a
builder. Phase 8's two per-adapter tests prove the call site in the first-party adapters; a property
asserted only there is one a third-party adapter omits silently, and on `protocol-http2`'s path it is
the sole barrier between a forged model and an injected header (8c design, fact 4). So
`forged_request_is_refused_at_dispatch` takes the driver's `transport:` factory — a separate keyword
from `seam:`, which is already `XCUT-11`'s pipeline-step factory, for this
assertion — builds a `Request` through `send(:new, …)` (the documented Ruby feature that bypasses
`private_class_method :new`, design §10.10) carrying a CRLF in a header name, and asserts that
`#call` raises **before any wire activity**: the seam is handed a listener that records connections,
and one accepted connection is the failure. With no `transport:` it is `:vacuous` with that reason, never
`:passed`.

**Amendment, 2026-09-13 — factory visibility.** Every assertion factory this task writes gets
`private_class_method` after its definition: `module_function` makes them public singleton methods with
no `sig/` mirror, which `CLAUDE.md`'s public-surface rule and this phase's own `NFR-3` assertion both
refuse. Task 6's amendment carries the rule, the per-suite counts and the reasoning for Tasks 6–11.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Appendix B.8's security-by-default and bounded-memory items.
# XCUT-14 (both clauses), XCUT-17, XCUT-18 (both assertions; the second is the wire-boundary
# re-validation's phase-9 clause), XCUT-21. XCUT-16, XCUT-20 and XCUT-24 add their tests in the step that writes their
# shape-specified assertions.
require "securerandom"
require_relative "../../test_helper"

class DexpaceConformanceInvariantSecurityTest < DexpaceConformanceTestCase
  S = Dexpace::Conformance::InvariantSuite

  # 4a's filed BoundedMap surface (4a plan:842-892): .new(cap:), #set, #size, a drain loop over @h.
  class ConformingMap
    def initialize(cap:)
      @cap = cap
      @h = {}
      @mutex = Thread::Mutex.new
    end

    def set(key, value)
      @mutex.synchronize do
        @h[key] = value
        @h.shift while @h.size > @cap
      end
      value
    end

    def size = @mutex.synchronize { @h.size }
  end

  class UncappedMap < ConformingMap
    def set(key, value)
      @mutex.synchronize { @h[key] = value }
      value
    end
  end

  # Caps correctly from empty, and is exactly XCUT-14's "single pre-insert check-then-evict".
  class CheckThenEvictMap < ConformingMap
    def set(key, value)
      @mutex.synchronize do
        @h.shift if @h.size >= @cap
        @h[key] = value
      end
      value
    end
  end

  STORE = ->(map) { map.instance_variable_get(:@h) }
  REDIRECTING_CORE = Module.new { const_set(:Redirect, Module.new) }
  Hop = Struct.new(:headers, :url)
  ORIGIN = %r{\Ahttps?://[^/]+}
  USERINFO = %r{//[^@/]*@}

  # A conforming re-issue: userinfo dropped, Authorization always stripped, Cookie and
  # Proxy-Authorization also stripped cross-origin, and an HTTPS-to-HTTP downgrade refused.
  def conforming_hop(from:, to:, headers:)
    raise ArgumentError, "downgrade refused" if from.start_with?("https:") && to.start_with?("http:")

    target = to.sub(USERINFO, "//")
    dropped = from[ORIGIN] == target[ORIGIN] ? %w[authorization] : %w[authorization cookie proxy-authorization]
    Hop.new(headers.reject { |name, _| dropped.include?(name) }, target)
  end

  def statuses(report)
    report.results.each_with_object({}) { |r, h| (h[r.assertion.ids.first] ||= []) << r.status }
  end

  def digest_core(&body)
    handler = Class.new(&body)
    Module.new { const_set(:Auth, Module.new { const_set(:DigestHandler, handler) }) }
  end

  # The driver constructs with the source the suite hands it and returns the rendered cnonce. 6c's
  # real draw is inside #authorization_for (6c design:630-653); these doubles expose it as #cnonce.
  def x21(core) = S.run(core: core, cnonce: ->(src) { core::Auth::DigestHandler.new(:cred, cnonce_source: src).cnonce })

  test "a map with no cap fails XCUT-14's cap clause deterministically, with no thread race" do
    report = S.run(core: Module.new, bounded_map: ->(cap:) { UncappedMap.new(cap: cap) })

    assert_equal(:failed, statuses(report)["XCUT-14"].first)
  end

  test "a drain-loop map passes both of XCUT-14's clauses" do
    report = S.run(core: Module.new, bounded_map: ->(cap:) { ConformingMap.new(cap: cap) },
                   bounded_map_store: STORE)

    assert_equal(%i[passed passed], statuses(report)["XCUT-14"])
  end

  test "a check-then-evict map passes the cap clause and fails the drain clause, deterministically" do
    report = S.run(core: Module.new, bounded_map: ->(cap:) { CheckThenEvictMap.new(cap: cap) },
                   bounded_map_store: STORE)

    assert_equal(%i[passed failed], statuses(report)["XCUT-14"])
  end

  test "a redirect driver that keeps Authorization on a same-origin re-issue fails XCUT-17" do
    report = S.run(core: REDIRECTING_CORE, redirect_hops: ->(from:, to:, headers:) { Hop.new(headers, to) })

    assert_equal([:failed], statuses(report)["XCUT-17"])
  end

  test "a conforming redirect driver passes all four of XCUT-17's clauses" do
    report = S.run(core: REDIRECTING_CORE, redirect_hops: method(:conforming_hop))

    assert_equal([:passed], statuses(report)["XCUT-17"])
  end

  test "a header validator accepting HTAB in a NAME fails XCUT-18" do
    core = Module.new do
      const_set(:HeaderSyntax, Module.new do
        def self.validate_name!(name) = name
        def self.validate_outbound_value!(value, name:) = value
      end)
    end

    assert_equal([:failed, :vacuous], statuses(S.run(core: core))["XCUT-18"],
                 "the validator assertion fails; the call-site assertion is vacuous with no transport:")
  end

  # the wire-boundary re-validation's phase-9 clause. The transport doubles answer the seam's #call(request, options,
  # cancellation) (phase 2's shape). A forged request is one that never met a builder: the
  # assertion builds it, the double only receives it.
  class RefusingTransport
    def call(request, _options, _cancellation)
      request.headers.each_entry { |name, value| ::Dexpace::HeaderSyntax.validate_name!(name); ::Dexpace::HeaderSyntax.validate_outbound_value!(value, name: name) }
      raise "unreachable: the forged name must have been refused"
    end
  end

  class DispatchingTransport
    def call(request, _options, _cancellation)
      ::TCPSocket.new(request.url.host, request.url.port).close # wire activity before any check
      raise ::Dexpace::InvalidArgumentError, "too late: already on the wire"
    end
  end

  test "a transport that re-validates before dispatch passes XCUT-18's call-site assertion" do
    report = S.run(core: ::Dexpace, transport: -> { RefusingTransport.new })

    assert_equal(%i[passed passed], statuses(report)["XCUT-18"])
  end

  test "a transport that touches the wire before re-validating fails XCUT-18's call-site assertion" do
    report = S.run(core: ::Dexpace, transport: -> { DispatchingTransport.new })

    assert_equal(%i[passed failed], statuses(report)["XCUT-18"])
    assert_match(/accepted a connection/, report.failures.first.detail)
  end

  test "a handler with no injectable cnonce source fails XCUT-21" do
    core = digest_core do
      def initialize(credential) = (@credential = credential)
      def cnonce = format("%032x", rand(2**128))
    end

    report = S.run(core: core, cnonce: ->(_src) { core::Auth::DigestHandler.new(:cred).cnonce })

    assert_equal([:failed], statuses(report)["XCUT-21"])
  end

  test "a handler whose DEFAULT source is Random.new fails XCUT-21, though an injected one is used" do
    core = digest_core do
      def initialize(credential, cnonce_source: Random.new) = (@credential = credential; @source = cnonce_source)
      def cnonce = @source.hex(16)
    end

    assert_equal([:failed], statuses(x21(core))["XCUT-21"])
  end

  test "a 128-bit draw truncated to 8 characters fails XCUT-21" do
    core = digest_core do
      def initialize(credential, cnonce_source: ::SecureRandom) = (@credential = credential; @source = cnonce_source)
      def cnonce = @source.hex(16)[0, 8]
    end

    assert_equal([:failed], statuses(x21(core))["XCUT-21"])
  end

  test "a conforming handler passes XCUT-21 whatever encoding renders its 128 bits" do
    core = digest_core do
      def initialize(credential, cnonce_source: ::SecureRandom) = (@credential = credential; @source = cnonce_source)
      def cnonce = @source.urlsafe_base64(16)
    end

    assert_equal([:passed], statuses(x21(core))["XCUT-21"])
  end
end
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Write the ten assertions**

```ruby
      # XCUT-14's CAP clause. Conformance: "insert far more than the cap of distinct keys; assert
      # map size never exceeds the cap." Single-threaded and DETERMINISTIC, reading the size after
      # every insert. The drain-to-cap clause is the next assertion, not this one.
      def bounded_maps
        Assertion.build(ids: ["XCUT-14"], name: "a caller-keyed map never exceeds its cap",
                        body: lambda do |subject|
                          cap = 8
                          map = subject.bounded_map(cap: cap)
                          sizes = (cap * 40).times.map do |i|
                            map.set("key-#{i}", i)
                            map.size
                          end

                          Check.that(sizes.max <= cap,
                                     "an insert burst pushed the map past its cap",
                                     expected: "<= #{cap}", actual: sizes.max, ids: ["XCUT-14"])
                        end)
      end

      # XCUT-14's DRAIN-TO-CAP clause: evict "using a loop (not a single pre-insert check-then-evict)".
      # Decided behaviourally and deterministically: fill the backing Hash to cap + 5 -- the state a
      # concurrent overshoot leaves, arranged without a thread -- then perform ONE #set. 4a's filed
      # drain loop (4a plan:842-892) ends at the cap, 8; a check-then-evict ends at 13; identically
      # on 3.2.11, 3.3.12, 3.4.10 and 4.0.6. An earlier draft called this clause undecidable as
      # behaviour; this shape decides it. This assertion is the ONLY line on the drain-to-cap clause:
      # gates:drain_loop is out of v1 (Task 13), because it caught 1 of 3 non-conforming shapes and
      # carried a false positive while this test decides the same clause deterministically.
      def bounded_map_drains
        Assertion.build(ids: ["XCUT-14"], name: "one insert drains an over-cap map back to its cap",
                        body: lambda do |subject|
                          cap = 8
                          map = subject.bounded_map(cap: cap)
                          store = subject.bounded_map_store(map)
                          (cap + 5).times { |i| store["overshoot-#{i}"] = i }
                          map.set("after-overshoot", 0)

                          Check.that(map.size <= cap,
                                     "one insert into an over-cap map evicted once instead of " \
                                     "draining back to the cap",
                                     expected: "<= #{cap}", actual: map.size, ids: ["XCUT-14"])
                        end)
      end

      # XCUT-17, all four clauses, because the requirement is four rules and a port can satisfy any
      # three: (a) strip Authorization before EVERY re-issue, even same-origin; (b) on a cross-origin
      # redirect -- judged against the ORIGINAL SEED origin, not the previous hop -- additionally
      # strip Cookie and Proxy-Authorization; (c) drop userinfo in the Location; (d) reject an
      # HTTPS-to-HTTP downgrade by default.
      def redirect_credential_hygiene
        Assertion.build(ids: ["XCUT-17"], name: "redirect handling enforces credential hygiene",
                        body: lambda do |subject|
                          subject.probe!(:Redirect, "6b's redirect step")

                          same = subject.redirect_hop(from: "https://a.example/one",
                                                      to: "https://a.example/two",
                                                      headers: { "authorization" => ["Bearer t"],
                                                                 "cookie" => ["s=1"] })
                          Check.that(same.headers["authorization"].nil?,
                                     "Authorization survived a SAME-ORIGIN re-issue (clause a)",
                                     expected: nil, actual: same.headers["authorization"],
                                     ids: ["XCUT-17"])

                          cross = subject.redirect_hop(from: "https://a.example/one",
                                                       to: "https://b.example/two",
                                                       headers: { "authorization" => ["Bearer t"],
                                                                  "cookie" => ["s=1"],
                                                                  "proxy-authorization" => ["Basic x"] })
                          %w[authorization cookie proxy-authorization].each do |name|
                            Check.that(cross.headers[name].nil?,
                                       "#{name} survived a CROSS-ORIGIN re-issue (clause b)",
                                       expected: nil, actual: cross.headers[name], ids: ["XCUT-17"])
                          end

                          userinfo = subject.redirect_hop(from: "https://a.example/one",
                                                          to: "https://user:pw@a.example/two",
                                                          headers: {})
                          Check.that(!userinfo.url.to_s.include?("user:pw"),
                                     "userinfo in the Location survived the re-issue (clause c)",
                                     expected: "no userinfo", actual: userinfo.url.to_s,
                                     ids: ["XCUT-17"])

                          downgrade = begin
                            subject.redirect_hop(from: "https://a.example/one",
                                                 to: "http://a.example/two", headers: {})
                            :allowed
                          rescue ::StandardError
                            :rejected
                          end
                          Check.that(downgrade == :rejected,
                                     "an HTTPS-to-HTTP downgrade was followed without opt-in " \
                                     "(clause d)",
                                     expected: :rejected, actual: downgrade, ids: ["XCUT-17"])
                        end)
      end

      # XCUT-18, all four byte classes, because the requirement's whole content is that names and
      # values have DIFFERENT permitted sets and a port that applies one rule to both passes a
      # single-case check. Phase 1 filed .validate_outbound_value!(value, name:) with name: REQUIRED.
      def header_syntax_validation
        Assertion.build(ids: ["XCUT-18"], name: "header names and outbound values reject splitting bytes",
                        body: lambda do |subject|
                          subject.probe!(:HeaderSyntax, "phase 1's HeaderSyntax")
                          syntax = subject.core.const_get(:HeaderSyntax)

                          rejects_name = lambda do |bytes, label|
                            refused = begin
                              syntax.validate_name!("X-A#{bytes}B")
                              false
                            rescue ::StandardError
                              true
                            end
                            Check.that(refused, "a header NAME containing #{label} was accepted",
                                       expected: "rejected", actual: "accepted", ids: ["XCUT-18"])
                          end
                          # HTAB is the one byte a NAME must reject and a VALUE must accept -- the
                          # asymmetry is the requirement.
                          ["\r", "\n", "\x00", "\x7F", "\t", "\xC3\xA5"].each_with_index do |b, i|
                            rejects_name.call(b, %w[CR LF NUL DEL HTAB non-ASCII][i])
                          end

                          accepted = begin
                            syntax.validate_outbound_value!("a\tb", name: "X-Trace")
                            true
                          rescue ::StandardError
                            false
                          end
                          Check.that(accepted,
                                     "an outbound VALUE containing HTAB was rejected; only a NAME " \
                                     "must reject it",
                                     expected: "accepted", actual: "rejected", ids: ["XCUT-18"])

                          ["\r", "\n", "\x00", "\x7F", "\xC3\xA5"].each do |byte|
                            refused = begin
                              syntax.validate_outbound_value!("a#{byte}b", name: "X-Trace")
                              false
                            rescue ::StandardError
                              true
                            end
                            Check.that(refused,
                                       "an outbound VALUE containing a control or non-ASCII byte " \
                                       "was accepted",
                                       expected: "rejected", actual: "accepted", ids: ["XCUT-18"])
                          end
                        end)
      end

      # XCUT-18's second assertion -- the wire-boundary re-validation's phase-9 clause: "phase 9's conformance suite is where
      # the assertion that it happened belongs", where IT is the adapter re-running HTTP-17/HTTP-18
      # immediately before dispatch over a Request that never met a builder. Phase 8's per-adapter
      # tests prove the call site in two first-party adapters; this proves the PROPERTY for any
      # adapter a third party writes, and on protocol-http2's path it is the sole barrier (8c
      # design, fact 4). The forged request is built through the documented hole design 10.10
      # admits -- Request.send(:new, ...) reaches the generated constructor past
      # private_class_method :new -- and, if that constructor rejects a foreign headers object, by
      # the duck type 8a's own forged test uses (8a plan:3739-3751); the detail says which.
      # Wire activity is observed, not inferred: the URL points at a listener this assertion owns,
      # and one accepted connection is the failure. Resource acquisition and release live in this
      # block's own scope with an ensure, never in an Enumerator (design 7.1).
      def forged_request_is_refused_at_dispatch
        Assertion.build(ids: ["XCUT-18"],
                        name: "an adapter refuses a forged request at dispatch, before any wire activity",
                        body: lambda do |subject|
                          raise Vacuous, "no transport factory supplied to InvariantSuite.run" unless subject.transport?

                          subject.probe!(:Request, "phase 1's domain model")
                          subject.probe!(:HeaderSyntax, "phase 1's HeaderSyntax")
                          listener = ::TCPServer.new("127.0.0.1", 0)
                          begin
                            url = ::URI::RFC3986_PARSER.parse("http://127.0.0.1:#{listener.addr[1]}/")
                            forged, route = forge_request(subject.core, url)
                            transport = subject.transport

                            refused = begin
                              transport.call(forged, nil, ::Dexpace::Cancellation.none)
                              false
                            rescue ::StandardError
                              true
                            end
                            connected = listener.accept_nonblock(exception: false) != :wait_readable

                            Check.that(!connected,
                                       "the adapter accepted a connection for a request forged via #{route} " \
                                       "whose header name carries CRLF",
                                       expected: "no wire activity", actual: "accepted a connection", ids: ["XCUT-18"])
                            Check.that(refused,
                                       "the adapter did not raise on a forged request (via #{route}) " \
                                       "whose header name carries CRLF",
                                       expected: "raised before dispatch", actual: "returned", ids: ["XCUT-18"])
                          ensure
                            listener.close
                          end
                        end)
      end

      # Two forged shapes, tried in order. Neither goes through Headers.build, because HTTP-17 would
      # reject the name there -- which is exactly why a forged model is the one that must be
      # re-validated at the wire boundary.
      def forge_request(core, url)
        headers = Object.new
        headers.define_singleton_method(:each_entry) { |&blk| blk.call("X-Evil\r\nInjected", "v") }
        method = core.const_defined?(:Method) ? core.const_get(:Method)::GET : :get
        begin
          [core.const_get(:Request).send(:new, method: method, url: url, headers: headers, body: nil),
           "Request.send(:new, ...)"]
        rescue ::StandardError
          forged = Object.new
          forged.define_singleton_method(:method) { method }
          forged.define_singleton_method(:url) { url }
          forged.define_singleton_method(:headers) { headers }
          forged.define_singleton_method(:body) { nil }
          [forged, "a duck-typed object answering #method/#url/#headers/#body"]
        end
      end

      # XCUT-19, clauses (a), (b), (c) and (e) -- clause (d), a credential not revealing its secret
      # in string form, is asserted against 5a's Proxy in the same task. 5b filed
      # Dexpace::Instrumentation::Redactor, NOT Dexpace::Redactor.
      def redaction_is_default_deny
        Assertion.build(ids: ["XCUT-19"], name: "logging redacts secrets by default",
                        body: lambda do |subject|
                          subject.probe!(:Instrumentation, "5b's instrumentation")
                          redactor = subject.core::Instrumentation::Redactor::DEFAULT

                          rendered = redactor.url("https://u:pw@h.example/p?token=s&page=2#k=v")
                          Check.that(!rendered.include?("pw"),
                                     "URL userinfo was not redacted (clause a)",
                                     expected: "no userinfo", actual: rendered, ids: ["XCUT-19"])
                          Check.that(!rendered.include?("token=s"),
                                     "a non-allow-listed query value was emitted (clause b)",
                                     expected: "redacted", actual: rendered, ids: ["XCUT-19"])
                          Check.that(!rendered.include?("k=v"),
                                     "a key=value fragment token was emitted (clause b)",
                                     expected: "redacted", actual: rendered, ids: ["XCUT-19"])
                          Check.that(rendered.include?("h.example") && rendered.include?("/p"),
                                     "host and path were redacted, which the clause does not ask",
                                     expected: "preserved", actual: rendered, ids: ["XCUT-19"])

                          Check.that(!redactor.header_name?("authorization"),
                                     "the header allow-list is not default-deny (clause c)",
                                     expected: false, actual: true, ids: ["XCUT-19"])
                        end)
      end

      # XCUT-21: "MUST be drawn from a cryptographically-strong PRNG with sufficient entropy (the
      # reference uses >= 128 bits for the Digest cnonce), NEVER a non-cryptographic RNG."
      #
      # Three observations and no character count. (1) The handler takes an injectable
      # cnonce_source: (6c design:630). (2) Entropy is judged by BYTES DRAWN from an injected recorder
      # and CARRIED into the rendered cnonce: each drawn byte is flipped in turn and the rendered value
      # must change, so a 128-bit draw truncated to 8 characters fails and a 22-character
      # urlsafe_base64(16) passes -- a character count got both wrong. (3) The DEFAULT source is
      # OBSERVED: the driver's construction is replayed with cnonce_source: stripped, and ::SecureRandom
      # must perform the draw. A default of Random.new passed every earlier form of this assertion,
      # because a check that only ever injected a source never exercised the default.
      def csprng_for_security_values
        Assertion.build(ids: ["XCUT-21"], name: "security-relevant randomness comes from a CSPRNG",
                        body: lambda do |subject|
                          subject.probe!(:Auth, "6c's Dexpace::Auth")
                          handler = subject.core::Auth.const_get(:DigestHandler)
                          injectable = handler.instance_method(:initialize).parameters.any? do |(kind, name)|
                            %i[key keyreq].include?(kind) && name == :cnonce_source
                          end
                          Check.that(injectable,
                                     "the digest handler takes no injectable cnonce source, so its " \
                                     "randomness source cannot be audited at all",
                                     expected: "a cnonce_source: keyword", actual: "absent",
                                     ids: ["XCUT-21"])

                          base = cnonce_recorder
                          rendered = subject.draw_cnonce(base).to_s
                          Check.that(base.drawn.positive?,
                                     "the handler drew no bytes from the injected source, so it " \
                                     "uses some other randomness",
                                     expected: "at least one draw", actual: 0, ids: ["XCUT-21"])
                          carried = (0...[base.drawn, 64].min).count do |index|
                            subject.draw_cnonce(cnonce_recorder(index)).to_s != rendered
                          end
                          Check.that(carried >= 16,
                                     "the rendered cnonce carries fewer than 128 bits of the bytes " \
                                     "drawn for it",
                                     expected: ">= 16 drawn bytes reach the cnonce",
                                     actual: "#{carried} of #{base.drawn}", ids: ["XCUT-21"])

                          Check.that(defined?(::SecureRandom) ? true : false,
                                     "::SecureRandom is not loaded, so no default can be it",
                                     expected: "::SecureRandom", actual: "undefined", ids: ["XCUT-21"])
                          draws = default_source_draws(subject, handler)
                          Check.that(draws.positive?,
                                     "with no cnonce_source: supplied, ::SecureRandom performed no " \
                                     "draw, so the handler's default source is something else",
                                     expected: "a draw from ::SecureRandom", actual: "none",
                                     ids: ["XCUT-21"])
                        end)
      end

      # @api private. A Random::Formatter whose every draw is recorded. Formatter routes #hex,
      # #urlsafe_base64, #base64, #random_bytes, #uuid, #alphanumeric and #random_number through
      # #bytes -- measured on 3.2.11, 3.3.12, 3.4.10 and 4.0.6 -- so defining #bytes records them all.
      # Byte i of a call is (0xA5 ^ i) & 0xFF, complemented when i == flip.
      def cnonce_recorder(flip = nil)
        ::Class.new do
          include ::Random::Formatter

          attr_reader :drawn

          define_method(:initialize) { @drawn = 0 }
          define_method(:bytes) do |count|
            chunk = ::Array.new(count) do |offset|
              byte = (0xA5 ^ (@drawn + offset)) & 0xFF
              @drawn + offset == flip ? byte ^ 0xFF : byte
            end
            @drawn += count
            chunk.pack("C*")
          end
        end.new
      end

      # @api private. Replays the driver with cnonce_source: stripped at #new and counts draws that
      # reach ::SecureRandom. A prepend cannot be undone, so both taps are installed once per target
      # and do nothing unless THIS thread has set the probe -- the Warning recorder's shape (Task 1).
      # A driver that never passes cnonce_source: to #new is a misuse of the hook, and raises.
      def default_source_draws(subject, handler)
        ::SecureRandom.singleton_class.prepend(secure_random_tap)
        handler.singleton_class.prepend(strip_cnonce_source)
        state = { draws: 0, stripped: false }
        ::Thread.current[:dexpace_conformance_default_source] = state
        subject.draw_cnonce(cnonce_recorder)
        unless state[:stripped]
          raise ::ArgumentError, "the cnonce driver did not call #new with cnonce_source:, so the " \
                                 "handler's default source could not be exercised"
        end

        state[:draws]
      ensure
        ::Thread.current[:dexpace_conformance_default_source] = nil
      end

      # @api private. #random_bytes carries #hex, #urlsafe_base64, #base64 and #uuid; #bytes carries
      # #alphanumeric and #random_number (measured on all four interpreters).
      def secure_random_tap
        @secure_random_tap ||= ::Module.new do
          %i[bytes random_bytes].each do |name|
            define_method(name) do |*args|
              state = ::Thread.current[:dexpace_conformance_default_source]
              state[:draws] += 1 unless state.nil?
              super(*args)
            end
          end
        end
      end

      # @api private.
      def strip_cnonce_source
        @strip_cnonce_source ||= ::Module.new do
          define_method(:new) do |*args, **kwargs, &block|
            state = ::Thread.current[:dexpace_conformance_default_source]
            next super(*args, **kwargs, &block) if state.nil? || !kwargs.key?(:cnonce_source)

            state[:stripped] = true
            super(*args, **kwargs.except(:cnonce_source), &block)
          end
        end
      end

      private_class_method :cnonce_recorder, :default_source_draws, :secure_random_tap,
                           :strip_cnonce_source
```

`XCUT-16` (no credential over non-HTTPS, plus the marker-suppressed exception the clause permits),
`XCUT-20` (three totality paths — `Instrumentation.contain`, `Redactor#url`'s malformed-URL
sentinel, `Preview.render`'s never-throw decode — **scoped** exactly as 5c handed forward: satisfied
for what the SDK owns, and **not** extended to a foreign callback, which `OBS-20` forbids) and
`XCUT-24` (a byte-capped, non-consuming preview over a 10 MB body, asserting both the cap and that a
later consumer read still sees the whole body) stay specified by shape, each opening with `probe!`
and quoting its clause.

- [ ] **Step 4: Run on the four installed interpreters; confirm 12 runs PASS**

The two `XCUT-18` call-site tests open a real `TCPServer` on `127.0.0.1:0` for the length of one
assertion; a sandbox that refuses loopback listeners makes them `:error`, which is a fixture fact
about the machine and not a finding — record it, do not waive it.

- [ ] **Step 5: Stage the change**

**No commit.**

```bash
git add -- gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/invariant_case.rb \
        gems/dexpace-conformance/test/dexpace/conformance/invariant_suite_security_test.rb
```

---

## Task 8: `InvariantSuite` — cancellation, concurrency and seam resolution

**Files:**
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite.rb`
- Test: `gems/dexpace-conformance/test/dexpace/conformance/invariant_suite_concurrency_test.rb`

**Interfaces:**
- Consumes: `SharedInstance` (Task 4), `probe!` (Task 5); from core — `Dexpace::Cancellation`,
  `Dexpace::CancelledError` (phase 2), `Dexpace::Registry` with `#register(key, factory, core:)`,
  `#install(provider)`, `#resolve` and `Dexpace::SeamError` (phase 2's filed surface),
  `Dexpace::Clock` (5a)
- Produces: the last six assertions: `XCUT-1`, `XCUT-2`, `XCUT-3`, `XCUT-11` (**two** assertions),
  `XCUT-12`, `XCUT-23`. **After this task `InvariantSuite` carries 28 assertions across all 24
  `XCUT` IDs** — 24 IDs, with `XCUT-11`, `XCUT-13`, `XCUT-14` and `XCUT-18` each carrying two
  (`XCUT-18`'s second, the forged-request call-site assertion, was added 2026-09-13 for the
  wire-boundary re-validation's phase-9 clause).

Three shape decisions, each forced rather than chosen.

**Cancellation uses `Dexpace::Cancellation`, never a thread interrupt.** `Dexpace/NoThreadInterrupt`
bans the alternative repository-wide, and 8c's clause 7 already records this as a property of the
*assertions* rather than of either adapter.

**`XCUT-11` is TWO assertions, not one.** Sixteen threads is the conformance clause's own shape;
**two fibers on one thread** is 8b's hand-forward and "the only shape that proves a per-fiber mutex
is not held across a suspension point" — `Thread::Mutex` ownership being per-fiber is one of
`CLAUDE.md`'s constraints-that-will-bite, and a thread-only race cannot see it. An earlier draft had
a counting test asserting **one** assertion per ID, which structurally forbade the second and is
why the design named a shape the plan then could not build.

**The second clause has to CATCH the deadlock, not merely outlive it.** A per-fiber mutex held
across `Fiber.yield` does not hang — the second fiber's `resume` raises
`ThreadError: deadlock; lock already owned by another fiber belonging to the same thread`, verified
with that exact message on 3.2.11, 3.3.12, 3.4.10 and 4.0.6. A `ThreadError` escaping the body
reaches `Runner`'s bare `rescue ::StandardError` and is reported `:error`, which is the status for
"this assertion is broken", not for "the subject is non-conformant". So the resume loop converts it
into a `Failure` carrying the message, and the suite's own non-conforming double proves the status
is `:failed`. Measured before and after: `[:passed, :error]` then `[:passed, :failed]`, on all four.

**`XCUT-23` is written in full**, because §9.3 restates this exact `B.8` item — the seam-resolution
item "names require-time registration as the discovery substrate" — and because the requirement is
three ordered rules whose ordering is the content.

**Amendment, 2026-09-13 — factory visibility.** Every assertion factory this task writes gets
`private_class_method` after its definition: `module_function` makes them public singleton methods with
no `sig/` mirror, which `CLAUDE.md`'s public-surface rule and this phase's own `NFR-3` assertion both
refuse. Task 6's amendment carries the rule, the per-suite counts and the reasoning for Tasks 6–11.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Appendix B.8's cancellation, concurrency and seam-resolution items.
# XCUT-1, XCUT-2, XCUT-3, XCUT-11, XCUT-12, XCUT-23.
require_relative "../../test_helper"

class DexpaceConformanceInvariantConcurrencyTest < DexpaceConformanceTestCase
  S = Dexpace::Conformance::InvariantSuite

  class StatelessStep
    def initialize = freeze
    def call(request) = [request, 1]
  end

  class LatchedStep
    def initialize
      @closed = false
      @lock = Thread::Mutex.new
    end

    def call(request) = [request, 1]
  end

  class CrossTalkingStep
    def initialize = (@attempt = 0)
    def call(request) = [request, @attempt += 1]
  end

  # Clause 2's non-conforming double: it holds its per-fiber mutex across a suspension point, which
  # is exactly what the clause forbids. Thread::Mutex ownership is per-FIBER, so the SECOND fiber's
  # lock attempt RAISES ThreadError rather than blocking. Clause 1 drives the same object from a
  # thread's ROOT fiber, where Fiber.yield raises FiberError ("attempt to yield on a not resumed
  # fiber", identical on all four interpreters) -- the rescue is what lets one double answer both
  # clauses, and it is the double's, never the assertion's.
  class SuspendingLockStep
    def initialize = (@lock = Thread::Mutex.new)

    def call(request)
      @lock.synchronize do
        begin
          Fiber.yield
        rescue FiberError
          nil
        end
        [request, 1]
      end
    end
  end

  def statuses(report)
    report.results.each_with_object({}) { |r, h| (h[r.assertion.ids.first] ||= []) << r.status }
  end

  test "the suite covers all 24 XCUT ids, and four of them carry two assertions each" do
    ids = S.assertions.flat_map(&:ids).select { |id| id.start_with?("XCUT-") }

    assert_equal(24, ids.uniq.size)
    assert_equal(28, ids.size, "XCUT-11, XCUT-13, XCUT-14 and XCUT-18 each carry two assertions")
    assert_equal(%w[XCUT-11 XCUT-13 XCUT-14 XCUT-18], ids.tally.select { |_, n| n > 1 }.keys.sort)
  end

  test "a frozen stateless step passes XCUT-11" do
    report = S.run(core: Module.new, seam: ->(**_kw) { StatelessStep.new })

    assert_equal(%i[passed passed], statuses(report)["XCUT-11"])
  end

  test "a latch-and-mutex step passes XCUT-11 when the DRIVER declares its state" do
    report = S.run(core: Module.new, seam: ->(**_kw) { LatchedStep.new },
                   mutable: %i[@closed @lock])

    assert_equal(%i[passed passed], statuses(report)["XCUT-11"],
                 "P9-9: a frozen-and-no-ivars rule would condemn every Closeable in the SDK")
  end

  test "a step holding per-call state on the shared instance fails XCUT-11" do
    report = S.run(core: Module.new, seam: ->(**_kw) { CrossTalkingStep.new })

    assert_includes(statuses(report)["XCUT-11"], :failed)
  end

  test "a step declaring its own per-call state as exempt still fails, because mutable: is the driver's" do
    report = S.run(core: Module.new, seam: ->(**_kw) { CrossTalkingStep.new }, mutable: [])

    assert_includes(statuses(report)["XCUT-11"], :failed)
  end

  # Clause 2's own non-conforming case, and the reason it is asserted as the exact PAIR rather than
  # with assert_includes: the misbehaviour surfaces as a raised ThreadError, and an assertion that
  # let it escape would report :error -- indistinguishable from a broken harness, which
  # assert_includes(:failed) would not catch either. Sorted, because the two clauses' order inside
  # `assertions` is not something this test should pin. Measured on 3.2.11, 3.3.12, 3.4.10 and
  # 4.0.6: [:passed, :error] before the assertion's rescue, [:passed, :failed] after.
  test "a step holding its lock across a suspension point fails XCUT-11's second clause" do
    report = S.run(core: Module.new, seam: ->(**_kw) { SuspendingLockStep.new }, mutable: %i[@lock])

    assert_equal(%i[failed passed], statuses(report)["XCUT-11"].sort,
                 "a deadlock must be reported :failed; :error reads as a broken harness")
  end
end
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Write the six assertions, `XCUT-11`'s pair and `XCUT-23` in full**

```ruby
      # XCUT-11, clause 1: "invoke one shared step instance from many threads with distinct requests
      # and assert no cross-talk", plus the structural predicate of design R8. `mutable:` comes from
      # the DRIVER (P9-9): an object that supplied its own exemption list could exempt the per-call
      # state this rule forbids -- measured, a latch-plus-mutex Closeable was falsely condemned and
      # the identical per-call-state bug falsely passed.
      def shared_instances_are_concurrent_safe
        Assertion.build(ids: ["XCUT-11"], name: "a shared component holds no per-call state",
                        body: lambda do |subject|
                          step = subject.seam
                          SharedInstance.audit(step, mutable: subject.mutable)

                          results = ::Thread::Queue.new
                          Array.new(16) { |i| ::Thread.new { results << step.call("request-#{i}") } }
                            .each(&:join)
                          collected = []
                          collected << results.pop until results.empty?
                          requests = collected.map(&:first).sort

                          Check.that(requests == (0...16).map { |i| "request-#{i}" }.sort,
                                     "a shared step crossed one call's request into another's",
                                     expected: 16, actual: requests.uniq.size, ids: ["XCUT-11"])
                        end)
      end

      # XCUT-11, clause 2: TWO FIBERS ON ONE THREAD, which 8b handed forward as "the only shape that
      # proves a per-fiber mutex is not held across a suspension point". Thread::Mutex ownership in
      # Ruby is per-FIBER and non-reentrant, so a lock held across a yield deadlocks two fibers of
      # one thread and sixteen threads cannot see it. Bounded by a resume count, never by an
      # interrupt.
      def shared_instances_are_fiber_safe
        Assertion.build(ids: ["XCUT-11"], name: "a shared component's lock is not held across a suspension",
                        body: lambda do |subject|
                          step = subject.seam
                          seen = []
                          fibers = Array.new(2) do |i|
                            ::Fiber.new do
                              seen << step.call("fiber-#{i}")
                              ::Fiber.yield
                              seen << step.call("fiber-#{i}-again")
                            end
                          end
                          4.times do
                            fibers.each do |f|
                              next unless f.alive?

                              begin
                                f.resume
                              rescue ::ThreadError => e
                                # Ruby's own report of the misbehaviour this clause hunts. Mutex
                                # ownership is per-FIBER, so a lock held across Fiber.yield makes
                                # the SECOND fiber's resume raise "deadlock; lock already owned by
                                # another fiber belonging to the same thread" -- verified on
                                # 3.2.11, 3.3.12, 3.4.10 and 4.0.6, identical message on all four.
                                # Without this rescue it propagates past Check and Runner's bare
                                # `rescue ::StandardError` reports :error, which reads as a broken
                                # harness rather than as the non-conformance it is (measured).
                                raise Failure.new(
                                  "two fibers on one thread deadlocked; a lock is held across a " \
                                  "suspension point: #{e.message}",
                                  expected: 4, actual: "#{e.class}: #{e.message}",
                                  requirement_ids: ["XCUT-11"]
                                )
                              end
                            end
                          end

                          Check.that(seen.size == 4,
                                     "two fibers on one thread did not both complete; a lock is " \
                                     "held across a suspension point",
                                     expected: 4, actual: seen.size, ids: ["XCUT-11"])
                        end)
      end

      # XCUT-23: "an explicit install ALWAYS WINS; otherwise the implementation is auto-discovered;
      # and zero or multiple candidates with no explicit selection MUST FAIL LOUDLY with an
      # actionable error rather than silently pick one or no-op." Three ordered rules, and the
      # ORDERING is the content -- a port that fails loudly on ambiguity but lets discovery beat an
      # explicit install satisfies two of three. Section 9.3 restates this item to name require-time
      # registration as the discovery substrate, which phase 2's Registry#register is.
      def seam_resolution_is_deterministic
        Assertion.build(ids: ["XCUT-23"], name: "a single-implementation seam resolves deterministically",
                        body: lambda do |subject|
                          subject.probe!(:Registry, "phase 2's Dexpace::Registry")
                          registry = subject.core.const_get(:Registry)
                          # Phase 2 filed Registry#initialize(seam:, installer:, conforms:) (phase 2
                          # plan:2864) and #register(key, factory, core:), whose core: must be the
                          # two-segment "~> M.N" form (plan:3089-3100). Every construction and
                          # registration sits OUTSIDE the rescues below, so a call-shape mistake is
                          # :error -- it can never masquerade as a loud failure. And "loud" is
                          # checked for its own reason: the error must be ACTIONABLE, naming the
                          # explicit-install entry point, which phase 2's installer: exists to supply.
                          installer = "Dexpace::Conformance probe #install"
                          fresh = lambda do
                            registry.new(seam: "conformance-probe", installer: installer,
                                         conforms: ->(_provider) { true })
                          end
                          major, minor = subject.core.const_get(:VERSION).to_s.split(".")
                          core = "~> #{major}.#{minor}"
                          failure_of = lambda do |target|
                            target.resolve
                            nil
                          rescue ::StandardError => e
                            e
                          end

                          empty = failure_of.call(fresh.call)
                          Check.that(!empty.nil? && empty.message.include?(installer),
                                     "resolving with no candidate did not fail loudly with an " \
                                     "actionable error naming the explicit-install entry point",
                                     expected: "an error naming #{installer}",
                                     actual: empty&.message, ids: ["XCUT-23"])

                          ambiguous = fresh.call
                          ambiguous.register(:a, -> { :a }, core: core)
                          ambiguous.register(:b, -> { :b }, core: core)
                          outcome = failure_of.call(ambiguous)
                          Check.that(!outcome.nil? && outcome.message.include?(installer),
                                     "two registered candidates with no explicit install did not " \
                                     "fail loudly with an actionable error",
                                     expected: "an error naming #{installer}",
                                     actual: outcome&.message, ids: ["XCUT-23"])

                          explicit = fresh.call
                          explicit.register(:discovered, -> { :discovered }, core: core)
                          explicit.install(:installed)
                          resolved = explicit.resolve
                          Check.that(resolved == :installed,
                                     "an auto-discovered implementation beat an explicit install",
                                     expected: :installed, actual: resolved, ids: ["XCUT-23"])
                        end)
      end
```

`XCUT-1`, `XCUT-2`, `XCUT-3` and `XCUT-12` stay specified by shape. Each opens with `probe!` and
quotes its clause; `XCUT-2`'s asserts the subtype-first ordering the requirement calls out
explicitly ("even when the timeout type is a *subtype* of the cancellation type"), and `XCUT-12`'s
races N threads on an expiring token and asserts exactly one fetch — **the fiber-scheduler form of
the same clause is postponed to phase 10's `XCUT-12` judgement** (the design's *Work phase 9 postponed,
and who owns it now*), because it needs a reactor the conformance gem cannot open.

- [ ] **Step 4: Run on the four installed interpreters and confirm the ID coverage**

```bash
for v in 3.2.11 3.3.12 3.4.10 4.0.6; do
  mise exec ruby@$v -- ruby -w -Igems/dexpace-conformance/lib -Igems/dexpace-core/lib \
    gems/dexpace-conformance/test/dexpace/conformance/invariant_suite_concurrency_test.rb
done
```

Expected: 6 runs, PASS, with the first test proving all 24 `XCUT` IDs are covered by 28 assertions.

- [ ] **Step 5: Record the residue honestly in the phase's checklist**

**Written in full by Tasks 5–8: 16 of the 28 assertions, over 12 IDs** — `XCUT-4`, `XCUT-9`,
`XCUT-11` ×2, `XCUT-13` ×2, `XCUT-14` ×2, `XCUT-15`, `XCUT-17`, `XCUT-18` ×2, `XCUT-19`, `XCUT-21`,
`XCUT-22`, `XCUT-23`. **Specified by shape: 12 assertions, one per ID** —
`XCUT-1`, `XCUT-2`, `XCUT-3`, `XCUT-5`, `XCUT-6`, `XCUT-7`, `XCUT-8`, `XCUT-10`, `XCUT-12`,
`XCUT-16`, `XCUT-20`, `XCUT-24`. On the `NFR` side, **4 of 8 `PackagingSuite` assertions are written
in full** and 4 by shape. **The residue is 12 `XCUT` plus 4 `NFR`** — re-derived on 2026-09-13 by
counting the twelve IDs listed; the drafts' 14 and then 11 were both wrong, and 16 + 12 = 28 is the
suite's own counting test above (15 + 12 = 27 before `XCUT-18`'s second assertion, 2026-09-13). A shape-specified assertion is a task the implementer writes
under TDD with a non-conforming double, exactly as the fully-written ones were; what the residue
records is that no measurement has yet been taken against it, and five of five first-draft
fully-written assertions contained a defect, so the shaped ones inherit no presumption of
correctness.

- [ ] **Step 6: Stage the change**

**No commit.**

```bash
git add -- gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite.rb \
        gems/dexpace-conformance/test/dexpace/conformance/invariant_suite_concurrency_test.rb
```

## Task 9: `PackagingCase` and `PackagingSuite` — appendix `B.9`

**Files:**
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/packaging_case.rb`
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/packaging_suite.rb`
- Create: two `sig/` mirrors
- **Modify: `gems/dexpace-conformance/lib/dexpace/conformance.rb`** — both `require_relative`s
- Test: `gems/dexpace-conformance/test/dexpace/conformance/packaging_suite_test.rb`

**Interfaces:**
- Consumes: `Assertion`, `Check`, `Failure`, `Vacuous`, `Runner`
- Produces: `PackagingCase.new(core_name:, adapter_names:, resolve: DEFAULT_RESOLVE, constants: {})`
  with `#spec(name)`, `#every_name`, `#runtime_version(name)`, `#shipped_rbs_without_header`;
  `PackagingSuite.run(core: "dexpace-core", adapters: [], resolve:, constants: {}, waive: [], around: nil) -> Report`

**This task's code was executed during planning** on 3.2.11, 3.4.10 and 4.0.6 against fixture
`Gem::Specification`s and one real installed gem: **9 runs, 13 assertions, 0 failures** on each.

**`resolve:` reads published metadata, not a source gemspec** (design `P9-2`): `NFR-1`'s conformance
clause names "the core artifact's **published dependency metadata**", and phase 0's
`gates:gemspec_audit` is the pre-publication check over the source.

**`NFR-10`, `NFR-13` and `NFR-14` legitimately have BOTH a recorded gate result and an assertion
here, and that is not a double disposition** — it is two audiences. The gate answers "is *this*
repository's CI enforcing it"; the assertion answers "can a downstream porter check it against
*their own* reimplementation", which is the whole reason `dexpace-conformance` is a published gem.
Design `R2` states the split; the eight assertions below — one per portable ID — are the portable half.

**Amendment, 2026-09-13 — factory visibility.** Every assertion factory this task writes gets
`private_class_method` after its definition: `module_function` makes them public singleton methods with
no `sig/` mirror, which `CLAUDE.md`'s public-surface rule and this phase's own `NFR-3` assertion both
refuse. Task 6's amendment carries the rule, the per-suite counts and the reasoning for Tasks 6–11.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Appendix B.9's portable half. NFR-1, NFR-2, NFR-3, NFR-10, NFR-11, NFR-13, NFR-14, NFR-15.
require_relative "../../test_helper"

class DexpaceConformancePackagingSuiteTest < DexpaceConformanceTestCase
  S = Dexpace::Conformance::PackagingSuite

  module FakeGem
    VERSION = "0.1.0"
    module Adapter
      VERSION = "0.1.0"
    end
    module Stale
      VERSION = "0.0.9"
    end
    module NoVersion
    end
  end

  CONSTANTS = { "dexpace-core" => "DexpaceConformancePackagingSuiteTest::FakeGem",
                "dexpace-serde-json" => "DexpaceConformancePackagingSuiteTest::FakeGem::Adapter" }
              .freeze

  def spec(name, version, deps)
    ::Gem::Specification.new do |s|
      s.name = name
      s.version = version
      deps.each { |d| s.add_dependency(d, ">= 0") }
    end
  end

  def resolver(specs) = ->(name) { specs[name] }

  def statuses(report) = report.results.to_h { |r| [r.assertion.ids.first, r.status] }

  def conforming
    { "dexpace-core" => spec("dexpace-core", "0.1.0", []),
      "dexpace-serde-json" => spec("dexpace-serde-json", "0.1.0", %w[dexpace-core json]) }
  end

  def run_suite(specs, constants: CONSTANTS)
    S.run(adapters: ["dexpace-serde-json"], resolve: resolver(specs), constants: constants)
  end

  test "a conforming gem set passes, and NFR-13 passes when every shipped .rbs carries the header" do
    report = run_suite(conforming)

    assert_equal(:passed, statuses(report)["NFR-1"])
    assert_equal(:passed, statuses(report)["NFR-2"])
    assert_equal(:passed, statuses(report)["NFR-15"])
    assert_equal(:passed, statuses(report)["NFR-13"])
  end

  test "a shipped signature file with no SPDX header fails NFR-13 rather than vacuating it" do
    report = run_suite(conforming, constants: CONSTANTS)
    # …with one gem's sig/ tree seeded from a fixture whose .rbs carries no header.
    assert_equal(:failed, statuses(report)["NFR-13"])
    assert_includes(report.to_s, "cannot reach .rbs")
  end

  test "a core with one runtime dependency fails NFR-1" do
    specs = conforming
    specs["dexpace-core"] = spec("dexpace-core", "0.1.0", ["json"])

    assert_equal(:failed, statuses(run_suite(specs))["NFR-1"])
  end

  test "an adapter with two third-party dependencies fails NFR-2" do
    specs = conforming
    specs["dexpace-serde-json"] = spec("dexpace-serde-json", "0.1.0", %w[dexpace-core json oj])

    assert_equal(:failed, statuses(run_suite(specs))["NFR-2"])
  end

  test "a runtime version disagreeing with the gemspec fails NFR-15" do
    constants = CONSTANTS.merge("dexpace-serde-json" =>
      "DexpaceConformancePackagingSuiteTest::FakeGem::Stale")

    assert_equal(:failed, statuses(run_suite(conforming, constants: constants))["NFR-15"])
  end

  test "a LOADED gem that defines no VERSION fails NFR-15 rather than vacuating it" do
    constants = CONSTANTS.merge("dexpace-serde-json" =>
      "DexpaceConformancePackagingSuiteTest::FakeGem::NoVersion")

    assert_equal(:failed, statuses(run_suite(conforming, constants: constants))["NFR-15"])
  end

  test "NFR-15 compares against the gemspec, so a 0.0.0 gemspec is not a free pass" do
    specs = { "dexpace-core" => spec("dexpace-core", "0.0.0", []) }
    report = S.run(adapters: [], resolve: resolver(specs),
                   constants: { "dexpace-core" => "DexpaceConformancePackagingSuiteTest::FakeGem" })

    assert_equal(:failed, statuses(report)["NFR-15"],
                 "0.1.0 reported against a 0.0.0 gemspec must fail; a placeholder-only check " \
                 "passes at 0.0.0, which is the version every gem in this repository carries")
  end

  test "an uninstalled gem is vacuous, never failed" do
    report = S.run(adapters: ["dexpace-serde-json"], resolve: ->(_n) { nil }, constants: CONSTANTS)

    assert_equal([:vacuous], report.results.map(&:status).uniq)
  end

  test "an unloaded constant is vacuous, never failed" do
    report = run_suite(conforming, constants: { "dexpace-core" => "NotLoaded::Anywhere" })

    assert_equal(:vacuous, statuses(report)["NFR-15"])
  end

  test "the default resolver reads a real installed gem's published metadata" do
    subject = Dexpace::Conformance::PackagingCase.new(core_name: "minitest", adapter_names: [])

    assert_equal("minitest", subject.spec("minitest").name)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Write `packaging_case.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "failure"
require_relative "vacuous"

module Dexpace
  module Conformance
    # What a PackagingSuite assertion receives. The subject is a set of gem NAMES resolved through
    # RubyGems, not paths: NFR-1's conformance clause names "the core artifact's PUBLISHED
    # dependency metadata", and only a resolved Gem::Specification is that (design P9-2).
    #
    # No `require` is needed: RubyGems is loaded before user code, so Gem::Specification is
    # available without one -- which is what keeps this gem's declared dependency set at
    # dexpace-core and nothing else, and why phase 0 plan Task 9's per-gem denylist scope does not
    # arise here.
    class PackagingCase
      DEFAULT_RESOLVE = lambda do |name|
        ::Gem::Specification.find_by_name(name)
      rescue ::Gem::MissingSpecError
        nil
      end

      attr_reader :core_name, :adapter_names

      def initialize(core_name:, adapter_names:, resolve: DEFAULT_RESOLVE, constants: {})
        @core_name = core_name
        @adapter_names = adapter_names
        @resolve = resolve
        @constants = constants
      end

      def spec(name)
        found = @resolve.call(name)
        raise Vacuous, "#{name} is not installed, so its published metadata cannot be read" if found.nil?

        found
      end

      def every_name
        [@core_name, *@adapter_names]
      end

      # NFR-15. `constants:` maps each gem name to its constant path and is what a real run passes.
      # The derived default below is a convenience for a porter and is WRONG for this repository's
      # own gems -- dexpace-core is `Dexpace`, not `Dexpace::Core`, and NetHTTP, AsyncHTTP and JSON
      # are not mechanical casings -- so Task 15 passes CLAUDE.md's gem table explicitly.
      #
      # An unloaded path is :vacuous (nothing to read). A LOADED module with no VERSION is :failed:
      # the gem is present and reports no version at runtime, which is the defect NFR-15 names, not
      # an absent antecedent.
      def runtime_version(name)
        path = @constants.fetch(name) { default_constant_path(name) }
        scope = path.split("::").reduce(::Object) do |mod, segment|
          unless mod.const_defined?(segment, false)
            raise Vacuous, "#{path} is not loaded, so no runtime version can be read"
          end

          mod.const_get(segment, false)
        end
        unless scope.const_defined?(:VERSION, false)
          raise Failure.new("#{path} is loaded but defines no VERSION", expected: "#{path}::VERSION",
                            actual: "undefined", requirement_ids: ["NFR-15"])
        end

        scope.const_get(:VERSION, false).to_s
      end

      # The shipped .rbs files with no SPDX header. NFR-13's conformance clause is "scan ALL source
      # files", and sig/ ships inside every gem, so this is the half no RuboCop cop can reach. The
      # assertion over it asserts PRESENCE, so it goes green the day phase 10's inbound-list repair
      # lands rather than red.
      def shipped_rbs_without_header
        every_name.flat_map do |name|
          root = @resolve.call(name)&.full_gem_path
          next [] if root.nil?

          ::Dir.glob(::File.join(root, "sig", "**", "*.rbs")).reject do |file|
            ::File.foreach(file).first(2).any? { |line| line.include?("SPDX-License-Identifier") }
          end
        end
      end

      private

      def default_constant_path(name)
        name.split("-").map { |segment| segment.split("_").map(&:capitalize).join }.join("::")
      end
    end
  end
end
```

- [ ] **Step 4: Write `packaging_suite.rb`**

Four assertions in full; five by shape.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "assertion"
require_relative "check"
require_relative "failure"
require_relative "packaging_case"
require_relative "runner"
require_relative "vacuous"

module Dexpace
  module Conformance
    # Appendix B.9's PORTABLE half -- the properties of a UNIT, which a downstream porter can check
    # against their own reimplementation. The properties of THIS build (NFR-4, NFR-5, NFR-6, NFR-7,
    # NFR-12, NFR-16, NFR-17) stay recorded gate results and are not here; NFR-10, NFR-13 and NFR-14
    # are in BOTH, for the two audiences design R2 names. NFR-8 and NFR-9 are in neither form: both
    # are vacuous by NFR-8's own text (section 10.19), and the retargeted checks are dispositioned
    # under NFR-1 rather than counted twice (P9-5).
    module PackagingSuite
      module_function

      def assertions
        @assertions ||= [core_has_no_runtime_dependencies, adapter_budget,
                         version_matches_the_gemspec, spdx_header_coverage,
                         explicit_public_surface, declared_runtime_floor,
                         no_foreign_constant_in_a_signature, single_version_source].freeze
      end

      def run(core: "dexpace-core", adapters: [], resolve: PackagingCase::DEFAULT_RESOLVE,
              constants: {}, waive: [], around: nil)
        Runner.run(assertions, waive: waive, around: around) do
          PackagingCase.new(core_name: core, adapter_names: adapters, resolve: resolve,
                            constants: constants)
        end
      end

      # NFR-1: "the core artifact's published dependency metadata lists zero runtime dependencies
      # beyond the stdlib". Empty, not "contains no transport" -- Ruby has no compile-versus-runtime
      # scope, so any non-empty set is a claim someone has to adjudicate (section 2.4).
      def core_has_no_runtime_dependencies
        Assertion.build(ids: ["NFR-1"], name: "core declares zero runtime dependencies",
                        body: lambda do |subject|
                          names = subject.spec(subject.core_name).runtime_dependencies.map(&:name)
                          next if names.empty?

                          raise Failure.new("#{subject.core_name} declares runtime dependencies",
                                            expected: [], actual: names, requirement_ids: ["NFR-1"])
                        end)
      end

      # NFR-2: "assert its dependency metadata lists the core plus at most one external library".
      def adapter_budget
        Assertion.build(ids: ["NFR-2"], name: "each adapter declares core plus at most one library",
                        body: lambda do |subject|
                          subject.adapter_names.each do |name|
                            deps = subject.spec(name).runtime_dependencies.map(&:name)
                            third_party = deps - [subject.core_name]
                            next if deps.include?(subject.core_name) && third_party.size <= 1

                            raise Failure.new("#{name} is outside NFR-2's dependency budget",
                                              expected: "#{subject.core_name} plus at most one",
                                              actual: deps, requirement_ids: ["NFR-2"])
                          end
                        end)
      end

      # NFR-15: "query the SDK's self-reported version AT RUNTIME from a packaged artifact; it must
      # EQUAL THE BUILD VERSION and never the placeholder." So the assertion COMPARES the loaded
      # constant against the resolved gemspec's version. A not-a-placeholder check alone passes at
      # 0.0.0 -- the version every gem in this repository currently carries -- which would make this
      # assertion green on a tree where NFR-15 has never been satisfied.
      def version_matches_the_gemspec
        Assertion.build(ids: ["NFR-15"], name: "each gem reports its build version at runtime",
                        body: lambda do |subject|
                          subject.every_name.each do |name|
                            built = subject.spec(name).version.to_s
                            reported = subject.runtime_version(name)
                            next if reported == built

                            raise Failure.new(
                              "#{name}'s runtime version does not equal its build version",
                              expected: built, actual: reported, requirement_ids: ["NFR-15"]
                            )
                          end
                        end)
      end

      # NFR-13 asserts PRESENCE: its conformance clause is "scan ALL source files for the required
      # header", and sig/**/*.rbs is shipped source no RuboCop cop can reach, since .rbs is not Ruby.
      # A body that raised Vacuous on every path would check nothing for anyone -- and R2 puts NFR-13
      # in the PORTABLE kind precisely because a porter must be able to run it against their own gem.
      # So it fails, with the first-party repair already routed: SPDX coverage for sig/**/*.rbs is on
      # phase 10's inbound list, and this assertion turns green the day that lands rather than red.
      # NFR-13 is a SHOULD, so a failure here records the gap and blocks no report (Task 12a).
      def spdx_header_coverage
        Assertion.build(ids: ["NFR-13"], name: "every shipped source file carries the SPDX header",
                        body: lambda do |subject|
                          missing = subject.shipped_rbs_without_header

                          Check.that(missing.empty?,
                                     "shipped signature files carry no SPDX header; the gate is a " \
                                     "RuboCop cop and cannot reach .rbs, and SPDX coverage for " \
                                     "sig/**/*.rbs is on phase 10's inbound list",
                                     expected: [], actual: missing.first(10),
                                     ids: ["NFR-13"])
                        end)
      end
    end
  end
end
```

The remaining four are specified by shape, each reading the resolved spec's `full_gem_path`:
**`NFR-3`** enumerates every `Dexpace::` constant a gem's `lib/` defines and asserts each has a
`sig/` mirror and that no `private_constant` appears — and it is the assertion phase 9's **own** code
must pass, which is why `Check` is its own file and `Runner`'s helpers are `private_class_method`.
**`NFR-10`** asserts `required_ruby_version` is declared and permits a **higher** floor for an
isolated capability, which `NFR-10` explicitly allows ("a capability that genuinely requires a newer
runtime MUST be isolated into its own unit that declares the higher floor explicitly") — this is
8c plan, Task 3's per-gem Ruby floor gate edit: `dexpace-transport-async_http` at `>= 3.3`, conforming by the requirement and non-conforming
by phase 0's `gates:versions`, which is the finding and not a defect in the assertion.
**`NFR-11`** scans every shipped `sig/` for a constant outside `Dexpace::` and a fixed stdlib
allowlist; its named subject is 6c's hand-forward, **`Dexpace::Auth::BearerProvider`** — "the one
documented duck-type interface 6c names without enforcing via `include`" — which must appear as an
RBS `interface` and never as a foreign constant. **`NFR-14`** asserts each gem's version equals the
root `VERSIONS` entry.

- [ ] **Step 5: Wire the entry file and run on the four installed interpreters**

```ruby
require_relative "conformance/packaging_case"
require_relative "conformance/packaging_suite"
```

```bash
for v in 3.2.11 3.3.12 3.4.10 4.0.6; do
  mise exec ruby@$v -- ruby -w -Igems/dexpace-conformance/lib -Igems/dexpace-core/lib \
    gems/dexpace-conformance/test/dexpace/conformance/packaging_suite_test.rb
done
```

Expected: 9 runs, PASS on each. (The planning prototype of the four fully-written assertions
measured **9 runs, 13 assertions, 0 failures** on all three.)

- [ ] **Step 6: Stage the change**

**No commit.**

```bash
git add -- gems/dexpace-conformance/lib/dexpace/conformance.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/packaging_case.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/packaging_suite.rb \
        gems/dexpace-conformance/sig/dexpace/conformance/packaging_case.rbs \
        gems/dexpace-conformance/sig/dexpace/conformance/packaging_suite.rbs \
        gems/dexpace-conformance/test/dexpace/conformance/packaging_suite_test.rb
```

## Task 10: `CodecSuite` — the lift 7a named

**Files:**
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/codec_case.rb`
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/codec_suite.rb`
- Create: two `sig/` mirrors
- **Modify: `gems/dexpace-conformance/lib/dexpace/conformance.rb`** — both `require_relative`s
- Create: `gems/dexpace-serde-json/test/dexpace/serde/json/conformance_test.rb` — the driver,
  **following 8a's placement**: a driver file inside the adapter gem's `test/` tree, which calls
  `CodecSuite.run` directly for the reason Step 5 gives (8a's
  `gems/dexpace-transport-net_http/test/dexpace/transport/net_http/conformance_test.rb`)
- Modify: `gems/dexpace-serde-json/test/support/serde_seam_assertions.rb` — **only the lifted halves
  leave.** `assert_closes_nothing`'s `SEAM-20`/`SERDE-3` clause and `assert_failure_model`
  (`SERDE-9`) become `CodecSuite` assertions and are deleted here; `assert_closes_nothing`'s
  **`SEAM-21`** type-token clause, `assert_buffer_profile` (`SERDE-4`), `assert_io_error_passthrough`
  (`SERDE-12`) and `assert_shareable` (`SERDE-29`) **stay in this file**, which is therefore **not**
  removed. `SEAM-21` is not lifted (§10.14, design `R1`), `SERDE-4` and `SERDE-12` are written
  against a `#encode_into` shape `CodecCase` does not carry, and `SERDE-29` is the evidence
  `XCUT-12`'s vacuity rests on (Task 8) — a `git rm` would delete four assertions three documents say
  stay with 7a, and `APPENDIX_B.md`'s `B.3` `by reference` rows point at this path
- Modify: `gems/dexpace-serde-json/test/dexpace/serde/json/seam_conformance_test.rb` — 7a's driver
  (7a plan, Task 17 Step 2) `include`s `SerdeSeamAssertions` and calls all five methods; drop the two
  calls whose methods left, keep the other three. Named here because a file that loses a method its
  caller names is a `NoMethodError` nobody planned for
- Test: `gems/dexpace-conformance/test/dexpace/conformance/codec_suite_test.rb`

**Interfaces:**
- Consumes: `Assertion`, `Check`, `Failure`, `Vacuous`, `Runner`; phase 2's filed seam contract —
  `#dump_to(value, sink)` and `#load(source, witness)`, with `#dump` deliberately **outside**
  `CONTRACT` (phase 2 plan:4552-4564); 7a's `Codec#load`, which reads `source.read_utf8` and calls
  `witness.dexpace_load(parsed, ctx)` (7a design:1322-1330)
- Produces: `CodecCase.new(build:, witness:, source:)` with `#codec`, `#sink`, `#witness`,
  `#source(text)`; `CodecSuite.run(build:, witness:, source:, waive: [], around: nil) -> Report`.
  The witness and the source factory are the **driver's**: the contract has no witness-less
  overload, and the source type is the adapter's (7a's is `Dexpace::IO::BufferedSource`)

7a wrote `gems/dexpace-serde-json/test/support/serde_seam_assertions.rb` as "the named lift target
for the conformance suite, written against the seam and never against `Dexpace::Serde::JSON` by
name", and recorded the path in its checklist "so phase 9 inherits a target rather than a search".
**This is the lift.** The `Tristate` and coercion items stay with 7a.

**Amendment, 2026-09-13 — `CodecCase::CountingSink`'s placement.** `CountingSink` is a **second public class** in `codec_case.rb`, which is outside `module-organization/1828a984`'s one-class-per-file rule and outside its only sanctioned exception, *a class-level **private** struct or `Data.define` used nowhere but that file*. The class earns its place in this file — one constructor, one reader, and no meaning outside the case that hands it out — so the fix is to make it match the exception rather than to move it: **`private_constant :CountingSink`** immediately after the class body, which hides the name without hiding the object `#sink` returns. Task 11's `ExecutorCase::EventRecorder` is the same shape and takes the same fix; Task 6's factory-visibility amendment carries the rule for both, and `rbs validate`, `steep check` and the runtime surface snapshot (Task 17) catch either one mechanically once the gem exists.

**Two requirement-level corrections to the first draft, both measured.**

**The error type is `Dexpace::Serde::Error`, not `Dexpace::SerdeError`.** Phase 2 filed the hierarchy
as `Dexpace::Serde::SerializationError < Dexpace::Serde::Error` and
`Dexpace::Serde::DeserializationError < Dexpace::Serde::Error` (design line 984). `Dexpace::SerdeError`
does not exist anywhere in the repository — the first draft's harness **invented** it, which is why
that draft reported 4 runs / 6 assertions / 0 failures while two of its four tests fail against the
real hierarchy on all three interpreters. Measured, and it is the exact failure mode the brief warned
about: a double built from prose.

**The close-the-target clause is `SEAM-20` plus `SERDE-3`, not `SEAM-21`.** `SEAM-21` is the
explicit-runtime-type-token rule. `SEAM-21`'s own assertion is **not lifted** — it is a property of
the witness protocol (§10.14) and stays in 7a's suite — and the coverage map records it as such
rather than leaving a reader to infer it.

**This task's code was executed during planning** on 3.2.11, 3.4.10 and 4.0.6 against the real
hierarchy: **8 runs, 10 assertions, 0 failures** on each.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Appendix B.3's seam half, lifted from 7a's named target. SEAM-20, SERDE-3, SERDE-9.
require "json"
require "stringio"
require_relative "../../test_helper"

class DexpaceConformanceCodecSuiteTest < DexpaceConformanceTestCase
  S = Dexpace::Conformance::CodecSuite

  # Doubles built from phase 2's FILED contract (phase 2 plan:4552-4564): #dump_to(value, sink) and
  # #load(source, witness). #dump is deliberately NOT in CONTRACT, so no double defines it. The error
  # hierarchy is phase 2's too: SerializationError and DeserializationError descend from
  # Dexpace::Serde::Error, and there is no Dexpace::SerdeError.
  class ConformingCodec
    def dump_to(value, sink) = sink.write(value.inspect)

    def load(source, _witness)
      ::JSON.parse(source.read)
    rescue ::JSON::ParserError
      raise Dexpace::Serde::DeserializationError, "malformed JSON"
    end
  end

  class ClosingCodec < ConformingCodec
    def dump_to(value, sink)
      super
      sink.close
    end
  end

  # SERDE-9's "no library type escapes". A plain def, not `def … if cond`, which would define the
  # method conditionally and inherit the conforming parent's -- the first draft's mistake.
  class LeakyCodec < ConformingCodec
    def load(source, _witness) = ::JSON.parse(source.read)
  end

  # SERDE-9 requires the STABLE SERDE type: a Dexpace error outside that hierarchy is not it.
  class WrongFamilyCodec < ConformingCodec
    def load(_source, _witness) = raise(::ArgumentError, "not a serde error")
  end

  # SERDE-9's second clause: "chaining the original cause".
  class UnchainedCodec < ConformingCodec
    def load(_source, _witness) = raise(Dexpace::Serde::DeserializationError, "malformed JSON")
  end

  class SilentCodec < ConformingCodec
    def load(_source, _witness) = nil
  end

  # 7a's witness protocol is any object answering #dexpace_load(parsed, ctx) (7a plan:617-630); the
  # source factory stands in for the driver's, which for 7a builds a Dexpace::IO::BufferedSource.
  WITNESS = Object.new
  def WITNESS.dexpace_load(parsed, _ctx) = parsed
  SOURCE = ->(text) { StringIO.new(text) }

  def run_suite(codec, waive: []) = S.run(build: -> { codec.new }, witness: WITNESS, source: SOURCE, waive: waive)

  def statuses(report) = report.results.to_h { |r| [r.assertion.ids.first, r.status] }

  test "a conforming codec passes both seam assertions" do
    assert_equal({ "SEAM-20" => :passed, "SERDE-9" => :passed }, statuses(run_suite(ConformingCodec)))
  end

  test "a codec that closes a caller-supplied sink fails SEAM-20 and SERDE-3 together" do
    report = run_suite(ClosingCodec)

    assert_equal(:failed, statuses(report)["SEAM-20"])
    assert_includes(report.to_s, "FAILED: SEAM-20, SERDE-3")
  end

  test "a library exception type escaping the seam fails SERDE-9" do
    assert_equal(:failed, statuses(run_suite(LeakyCodec))["SERDE-9"])
  end

  test "a Dexpace error outside the serde hierarchy fails SERDE-9" do
    assert_equal(:failed, statuses(run_suite(WrongFamilyCodec))["SERDE-9"])
  end

  test "a serde error with no chained cause fails SERDE-9" do
    assert_equal(:failed, statuses(run_suite(UnchainedCodec))["SERDE-9"])
  end

  test "a codec that does not raise at all fails SERDE-9" do
    assert_equal(:failed, statuses(run_suite(SilentCodec))["SERDE-9"])
  end

  test "a Vacuous raised inside the body is not swallowed into passed" do
    vacuous = Class.new(ConformingCodec) do
      def load(_source, _witness) = raise(Dexpace::Conformance::Vacuous, "this codec decodes nothing")
    end

    assert_equal(:vacuous, statuses(run_suite(vacuous))["SERDE-9"])
  end

  test "a waiver by id suppresses exactly one result and leaves the other running" do
    report = run_suite(ClosingCodec, waive: ["SERDE-3"])

    assert_equal({ "SEAM-20" => :waived, "SERDE-9" => :passed }, statuses(report))
  end
end
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Write `codec_case.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    # What a CodecSuite assertion receives. Lifted from 7a's
    # gems/dexpace-serde-json/test/support/serde_seam_assertions.rb, which 7a wrote against the seam
    # and never against Dexpace::Serde::JSON by name.
    class CodecCase
      # A sink that counts its own closes, so SERDE-3's "streaming/buffer targets not closed" is a
      # count and not an inference.
      class CountingSink
        attr_reader :bytes, :close_count

        def initialize
          @bytes = +""
          @close_count = 0
        end

        def write(chunk) = (@bytes << chunk).bytesize
        def close = @close_count += 1
      end

      attr_reader :witness

      # witness: and source: come from the driver. Phase 2's contract is load(source, witness) with
      # no witness-less overload (phase 2 plan:4554-4573), and 7a's codec reads its source with
      # #read_utf8 (7a design:1324), so neither is the suite's to invent.
      def initialize(build:, witness:, source:)
        @build = build
        @witness = witness
        @source = source
      end

      def codec = @build.call
      def sink = CountingSink.new
      def source(text) = @source.call(text)
    end
  end
end
```

- [ ] **Step 4: Write `codec_suite.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "assertion"
require_relative "check"
require_relative "codec_case"
require_relative "failure"
require_relative "runner"
require_relative "vacuous"

module Dexpace
  module Conformance
    # Appendix B.3's seam half. SEAM-20 and SERDE-3 are genuinely portable: the post-v1
    # dexpace-serde-oj is the second subject the lift exists for. SEAM-21 -- the explicit
    # runtime-type-token rule -- is NOT lifted: it is a property of the witness protocol
    # (section 10.14) and stays in 7a's suite, recorded as such in APPENDIX_B.md.
    module CodecSuite
      module_function

      def assertions
        @assertions ||= [never_closes_its_target, no_library_type_escapes].freeze
      end

      def run(build:, witness:, source:, waive: [], around: nil)
        Runner.run(assertions, waive: waive, around: around) do
          CodecCase.new(build: build, witness: witness, source: source)
        end
      end

      # SEAM-20 and SERDE-3, not SEAM-21: the "MUST NOT close the caller's target" clause on the
      # encode path is SEAM-20's plus SERDE-3's. #dump_to and never #dump: phase 2's CONTRACT names
      # #dump_to and keeps the #dump shorthand out of it deliberately (phase 2 plan:4561-4564), so a
      # conforming codec need not define #dump at all.
      def never_closes_its_target
        Assertion.build(ids: %w[SEAM-20 SERDE-3], name: "a codec never closes a target it was handed",
                        body: lambda do |subject|
                          sink = subject.sink
                          subject.codec.dump_to({ "a" => 1 }, sink)

                          Check.that(sink.close_count.zero?,
                                     "the codec closed a caller-supplied sink",
                                     expected: 0, actual: sink.close_count,
                                     ids: %w[SEAM-20 SERDE-3])
                        end)
      end

      # SERDE-9: "failures surface the stable serde type CHAINING THE ORIGINAL CAUSE, no library
      # type escapes." Three clauses and all three are asserted -- a Dexpace error outside the serde
      # hierarchy, or a serde error with no cause chained, satisfies neither the "stable serde type"
      # nor the "chaining the original cause" half, and both passed the first draft.
      def no_library_type_escapes
        Assertion.build(ids: ["SERDE-9"], name: "a decode failure surfaces the SDK's serde type",
                        body: lambda do |subject|
                          raised = capture_failure(subject)

                          Check.that(!raised.nil?, "malformed input decoded without raising",
                                     expected: "a Dexpace::Serde::Error", actual: "no error",
                                     ids: ["SERDE-9"])
                          Check.that(serde_error?(raised),
                                     "a failure outside the SDK's serde hierarchy escaped the seam",
                                     expected: "Dexpace::Serde::Error", actual: raised.class.name,
                                     ids: ["SERDE-9"])
                          Check.that(!raised.cause.nil?,
                                     "the serde failure chained no original cause",
                                     expected: "a chained #cause", actual: nil, ids: ["SERDE-9"])
                        end)
      end

      # Vacuous and Failure are re-RAISED rather than captured: both are StandardError descendants
      # (8a), so a bare `rescue ::StandardError` turns the suite's own vacuity into a PASS -- and it
      # did, measured, in the first draft, where the note beside the rescue named Failure and missed
      # Vacuous entirely.
      # @api private
      def capture_failure(subject)
        subject.codec.load(subject.source("{not json"), subject.witness)
        nil
      rescue Vacuous, Failure
        raise
      rescue ::StandardError => e
        e
      end

      # @api private
      def serde_error?(error)
        defined?(::Dexpace::Serde::Error) && error.is_a?(::Dexpace::Serde::Error)
      end

      private_class_method :capture_failure, :serde_error?
    end
  end
end
```

- [ ] **Step 5: Wire the entry file, write the adapter-gem driver, remove the old support file**

Append both requires to `gems/dexpace-conformance/lib/dexpace/conformance.rb` — without them
`codec_suite_test.rb`, which reaches the suite through the test helper's entry-file require, is a
`NameError`:

```ruby
require_relative "conformance/codec_case"
require_relative "conformance/codec_suite"
```

The driver sits where 8a's does, in the adapter's own `test/` tree, but **calls `CodecSuite.run`
directly and asserts on the report**. 8a's `MinitestDriver#conformance` cannot drive this suite: it
builds a `TransportCase` for every assertion (8a plan:2302-2306), which has no `#codec`, `#sink`,
`#witness` or `#source`, and giving it a case-factory hook would change an interface phase 8 owns.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# The FIRST consumer of CodecSuite; the post-v1 dexpace-serde-oj is the second the lift exists for.
# CodecSuite.run is called directly: 8a's MinitestDriver#conformance builds a TransportCase per
# assertion (8a plan:2302-2306), and widening it would change an interface phase 8 owns (R6).
class DexpaceSerdeJsonConformanceTest < Minitest::Test
  # 7a's witness protocol: any object answering #dexpace_load(parsed, ctx) (7a plan:617-630).
  PASS_THROUGH = Object.new
  def PASS_THROUGH.dexpace_load(parsed, _ctx) = parsed

  def test_codec_suite
    report = Dexpace::Conformance::CodecSuite.run(
      build: -> { Dexpace::Serde::JSON::Codec.default },                  # 7a plan:1896-1897
      witness: PASS_THROUGH,
      source: ->(text) { Dexpace::IO::BufferedSource.of_bytes(text.b) },  # 7a plan:1953
      waive: []
    )

    assert(report.passed?, report.to_s)
  end
end
```

7a's `SERDE-4` offset matrix and `SERDE-12` I/O-error pass-through **stay in the adapter's own
suite**: they are seam-portable in principle, but 7a wrote them against a `#encode_into` shape
`CodecCase` does not carry, and widening `CodecCase` for one adapter is what `R1`'s criterion
rejects. `APPENDIX_B.md` records them `by reference`, **and the path those rows name is
`gems/dexpace-serde-json/test/support/serde_seam_assertions.rb`, which survives this task** —
holding `SEAM-21`, `SERDE-4`, `SERDE-12` and `SERDE-29` — so Task 14's evidence-path check has a file
to find.

- [ ] **Step 6: Run both suites on the four installed interpreters**

Expected: 8 runs in the gem's own suite on each of 3.2.11, 3.3.12, 3.4.10 and 4.0.6, plus **one**
test in the adapter driver, which asserts the whole report.

- [ ] **Step 7: Stage the change**

**No commit.**

```bash
git add -- gems/dexpace-conformance/lib/dexpace/conformance.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/codec_case.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/codec_suite.rb \
        gems/dexpace-conformance/sig/dexpace/conformance/codec_case.rbs \
        gems/dexpace-conformance/sig/dexpace/conformance/codec_suite.rbs \
        gems/dexpace-conformance/test/dexpace/conformance/codec_suite_test.rb \
        gems/dexpace-serde-json/test/
```

**No `git rm`.** `serde_seam_assertions.rb` is edited, not removed: the two lifted methods go and
four assertions — `SEAM-21`, `SERDE-4`, `SERDE-12`, `SERDE-29` — stay, with 7a's
`seam_conformance_test.rb` updated in the same change to call the three that remain.

## Task 11: `ExecutorSuite` — the harness half of `SEAM-25`'s lifecycle event

**Files:**
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/executor_case.rb`
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/executor_suite.rb`
- Create: two `sig/` mirrors
- **Modify: `gems/dexpace-conformance/lib/dexpace/conformance.rb`** — both `require_relative`s
- Create: `gems/dexpace-async-thread/test/dexpace/async/thread/conformance_test.rb` — the driver, in
  the adapter gem's own `test/` tree, following 8a's precedent
- Test: `gems/dexpace-conformance/test/dexpace/conformance/executor_suite_test.rb`

**Interfaces:**
- Consumes: `Assertion`, `Check`, `Failure`, `Vacuous`, `Runner`
- Produces: `ExecutorCase.new(build:, borrow: nil, functional: nil, recorder: nil)` with
  `THREADS = 16`, `ExecutorCase::EventRecorder`, `#executor(**settings)`, `#borrowed?`,
  `#borrowed(pool)`, `#functional?`, `#functional`, `#events?`, `#shutdowns`;
  `ExecutorSuite.run(build:, borrow: nil, functional: nil, events: nil, waive: [], around: nil) -> Report`

**The harness half of `SEAM-25`'s lifecycle event — which phase 2 postponed and 8b emits — is
reassigned to phase 9, and this is a CORRECTION to a committed record, not a restatement of it.** 8b's
design read: "The *harness* half of the condition — the assertion living in `dexpace-conformance` — is
**`8a`'s**, and `8b` hands it the shape rather than writing it." 8a wrote the protocol, the `WireServer`
fixture and the transport suite, and wrote **no executor suite**; 8b supplied the shape as promised. So
the harness half is unwritten after phase 8, phase 9 writes it, and the earlier record is wrong about
which phase delivers it. Phase 9's checklist records the work **against `SEAM-25`** with that
correction named out loud — which is the discipline phase 4b failed when it corrected its charter
while claiming to restate it.

**Five assertions, not four: `ASYNC-16` and `ASYNC-17` are added.** `B.7`'s lifecycle bullet names
`ASYNC-15`, `ASYNC-16` and `ASYNC-17` together, and a suite covering only the first leaves two of
three with no check anywhere. **Two clauses are scoped out with a reason rather than silently
dropped:** `ASYNC-15`'s clause (c), interrupt-safety, needs an interrupt pending during close, and
§8.3 bans every primitive that could arrange one — so the clause holds because the flag is never
touched (`cross-cutting-invariants/8fa2c08d`) and there is nothing observable to assert; and
`SEAM-18` is the executor *seam's* shape rather than an implementation property, which 8b's own
suite asserts. Both are recorded in `APPENDIX_B.md` as scoped out, with those reasons.

**A seventh assertion, `ASYNC-3`, written so that it genuinely fails — added 2026-09-13.** Design
`R5` and Task 16 step 4 say `ASYNC-3` "is asserted so it genuinely fails, waived by requirement ID in
the first-party build, and printed as `waived (would fail): ASYNC-3`"; until this revision no task
wrote the assertion, and the only `ASYNC-3` in the plan was a hand-built `:waived` result in two
rendering tests — a claim with no assertion behind it, which is the green-over-defect shape the fix
round removed. `blocked_worker_is_released_on_cancel` posts, through core's own pivot
(`Dexpace::Transport.async_over`, phase 2), a transport call that blocks on a `Queue#pop` with **no
timeout**; once the worker is provably inside the call it cancels the token and asks whether the
worker was released within a bound. On `dexpace-async-thread` it is not — §8.3 forbids every
primitive that could interrupt it, which is the whole content of the unsatisfied `ASYNC-3` MUST
(design §10.5; `docs/first-release.md` § What v1 ships without › Unsatisfied MUSTs) — and on the
inline double it
is not either, so the assertion fails everywhere this repository can point it and the thread
driver waives it **by ID**. That is appendix `B.7`'s "recorded as *failing* rather than vacuous"
item given a runnable subject. The timed wait is the requirement's own shape ("within a bound"),
not a sleep used as synchronisation: the worker's entry is observed through a queue, and the
assertion frees the gate itself in an `ensure` so a failed run leaks no thread.

**This task's code was executed during planning** on 3.2.11, 3.3.12, 3.4.10 and 4.0.6: **9 runs, 10
assertions, 0 failures** on each — before the `ASYNC-3` assertion and its test, which were not
executed during planning and are the first thing to run red-then-green at execution. The suite was also driven end to end against a stand-in
transcribed from 8b's filed `Pool` (8b plan:1278-1428 and 1714-1750) on the same four: green, with
`XCUT-22` and `ASYNC-17` `:vacuous`; and red — `XCUT-13` and `SEAM-25` `:failed`, `expected 1, got
2` — against the same class with `#close` unlatched so `#release` double-fires.

**One thing the planning run got wrong first, and the fence below fixes.** The event recorder was a
single array passed to `.run` and shared across the whole report, so by the time the `SEAM-25`
assertion ran, three earlier assertions had each built and closed a pool and appended a shutdown
event — and the **conforming** double failed. `events:` is therefore a **factory returning a fresh
recorder**, one per case, and `Runner` already builds a fresh case per assertion. This is
`testing/4ef070df` applied to a fixture the suite constructs rather than one a test writes.

**The shutdown is observed through the logger sink, because that is the only place a filed executor
exposes it — and an earlier draft of this task got that wrong.** That draft had every lifecycle
assertion read `pool.shutdown_count` and count `{ name: ... }` hashes. **No executor in this
repository has a `#shutdown_count`, and none emits a `{ name: }` hash.** 8b's `Pool` reports its
shutdown exactly once, from `#release`, through the injected logger —
`@logger.event(Severity::INFO).event(Events::INSTRUMENTATION_SHUTDOWN).field(WORKER_COUNT_FIELD,
@size).field(DRAINED_FIELD, drained).emit` (8b plan:1725-1732) — and 5b's `Event#emit` ends in
`@sink.public_send(@severity.sink_method) { rendered_record }` with `record[Keys::EVENT] =
@event_tag` (5b plan:2134-2175). 8b's own test counts it exactly that way: build the pool with
`logger: Dexpace::Instrumentation::Logger.build(sink: sink)` and select the sink entries whose
`payload[Keys::EVENT] == Events::INSTRUMENTATION_SHUTDOWN` (8b plan:1644-1651, and again at
2563-2570). So **the recorder `events:` returns is a sink**: `ExecutorCase::EventRecorder`
implements core's `_Sink` duck type (5b plan:886-896; `NULL_SINK` at 5b plan:861-872) and the
adapter's `build:` lambda is what wires it into its own logger. `dexpace-conformance` declares
`dexpace-core` and nothing else, so `Keys::EVENT` and `Events::INSTRUMENTATION_SHUTDOWN` are names
it may use and `Dexpace::Async::Thread` is not — which is exactly why the event name, and not a
counter method, is the portable observation.

**Only the event NAME is readable.** 8b's two field keys (`"dexpace.executor.worker_count"`,
`"dexpace.executor.drained"`) are `private_constant`s in the pool (8b plan:1295-1300) and were
deliberately not added to core's `Keys`, "because the portable assertion needs the event name only".
`ExecutorCase#shutdowns` reads `Keys::EVENT` and nothing else.

**What the recorder-free path can and cannot prove, stated rather than implied.** `XCUT-13`,
`XCUT-22` and `ASYNC-17` each split into a half that needs no recorder and a half that does, and the
second half is **skipped, never failed**, when the adapter supplied no `events:` factory — so an
adapter without one still gets a real result rather than a vacuity. The half that is lost is worth
naming: without a recorder, an **unlatched** executor passes `XCUT-13`, because `Closeable#close`
returns `nil` on the losing call either way (phase 2 plan:558-568) and "the shutdown work ran twice"
is visible only in the event. Measured: with a recorder the unlatched double is `:failed` on
`XCUT-13` and `SEAM-25`; without one it is `:passed` on `XCUT-13` and `:vacuous` on `SEAM-25`.

**Amendment, 2026-09-13 — `ExecutorCase::EventRecorder`'s placement.** `EventRecorder` is a **second
public class** in `executor_case.rb`, which is outside `module-organization/1828a984`'s
one-class-per-file rule and outside its only sanctioned exception, *a class-level **private** struct or
`Data.define` used nowhere but that file*. It is the same shape as Task 10's
`CodecCase::CountingSink`, it lands here for the same reason — one constructor, one reader and no
meaning outside the case that hands it out — and it takes the same fix: **`private_constant
:EventRecorder`** immediately after the class body, which hides the name without hiding the object the
case returns. Task 6's factory-visibility amendment carries the rule and the reasoning for both
instances; `rbs validate`, `steep check` and the runtime surface snapshot (Task 17) catch either one
mechanically once the gem exists.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Appendix B.7's lifecycle half, and the harness for SEAM-25's lifecycle event.
# SEAM-12, SEAM-25, ASYNC-15, ASYNC-16, ASYNC-17, XCUT-11, XCUT-13, XCUT-22.
require_relative "../../test_helper"

class DexpaceConformanceExecutorSuiteTest < DexpaceConformanceTestCase
  S = Dexpace::Conformance::ExecutorSuite

  # The one payload every double below emits, shaped exactly as Event#emit shapes it: a Hash whose
  # Keys::EVENT entry carries the event name (5b plan:2156-2168). 8b's two field keys are the pool's
  # private constants and no portable assertion reads them, so nothing else is here.
  SHUTDOWN = { Dexpace::Instrumentation::Keys::EVENT =>
                 Dexpace::Instrumentation::Events::INSTRUMENTATION_SHUTDOWN }.freeze

  # A conforming double: an inline executor whose close is latched, which drains before returning,
  # refuses work after close, and reports its shutdown the ONLY way a filed executor does -- one
  # Events::INSTRUMENTATION_SHUTDOWN payload into the sink the suite supplied (8b plan:1725-1732).
  # It deliberately defines no #shutdown_count: 8b's Pool has none, and a double that invents one is
  # what made an earlier draft of this suite red against the real adapter.
  class FakePool
    def initialize(events: nil, owned: true)
      @events = events
      @owned = owned
      @closed = false
      @lock = Thread::Mutex.new
    end

    def post(&block)
      raise "closed" if @closed

      block.call
    end

    def close
      @lock.synchronize do
        return nil if @closed

        @closed = true
      end
      return nil unless @owned

      emit_shutdown
      nil
    end

    private

    def emit_shutdown
      @events&.info { SHUTDOWN }
      nil
    end
  end

  # XCUT-13's non-conforming twin: no latch, so every close runs the shutdown again and the second
  # one emits a second event.
  class UnlatchedPool < FakePool
    def close
      @closed = true
      emit_shutdown
      nil
    end
  end

  class LeakyPool < FakePool
    def post(&block) = block.call   # accepts work after close: ASYNC-16's second half
  end

  # ASYNC-17's subject: an implementation that owns nothing, so its close shuts nothing down and
  # emits nothing.
  class FunctionalExecutor
    def post(&block) = block.call
    def close = nil
  end

  # ASYNC-17's non-conforming twin: a "functional" implementation whose close shuts something down,
  # which it reports the same way every other subject here does.
  class WorkingCloseExecutor
    def initialize(events) = (@events = events)

    def post(&block) = block.call

    def close
      @events&.info { SHUTDOWN }
      nil
    end
  end

  class BorrowHolder
    def initialize(pool) = (@pool = pool)
    def close = nil
  end

  class ClosingBorrowHolder
    def initialize(pool) = (@pool = pool)
    def close = @pool.close
  end

  def statuses(report) = report.results.to_h { |r| [r.assertion.ids.first, r.status] }

  def conforming(**over)
    # ASYNC-3 is waived by ID here for the same reason the thread driver waives it: no executor
    # this repository can build releases a worker blocked in an uninterruptible call (section 10.5),
    # and the suite's job is to print that as `waived (would fail)`, never as passed.
    defaults = { build: ->(events: nil, **_kw) { FakePool.new(events: events) },
                 borrow: ->(pool) { BorrowHolder.new(pool) },
                 functional: ->(**_kw) { FunctionalExecutor.new },
                 events: -> { Dexpace::Conformance::ExecutorCase::EventRecorder.new },
                 waive: ["ASYNC-3"] }
    S.run(**defaults.merge(over))
  end

  test "a conforming executor passes every lifecycle assertion, with ASYNC-3 waived by id" do
    report = conforming

    assert_equal({ "SEAM-12" => :passed, "XCUT-13" => :passed, "XCUT-22" => :passed,
                   "ASYNC-16" => :passed, "ASYNC-17" => :passed, "SEAM-25" => :passed,
                   "ASYNC-3" => :waived },
                 statuses(report))
    assert_includes(report.to_s, "waived (would fail): ASYNC-3")
  end

  # ASYNC-3 (unsatisfied MUST, design section 10.5) / design R5: the assertion is real and it fails. An inline executor runs the blocked
  # call on the posting thread, a pool runs it on a worker; neither can release it on cancel.
  test "ASYNC-3 genuinely fails against an executor that cannot release a blocked worker" do
    report = conforming(waive: [])

    assert_equal(:failed, statuses(report)["ASYNC-3"])
    assert_match(/still blocked/, report.failures.first.detail)
  end

  # The recorder is wired the way 8b wires its own: Logger.build(sink:) (8b plan:1645-1646), and
  # what reaches it is whatever Event#emit hands a sink. This is the one test that proves the suite
  # reads a REAL emission rather than a shape the doubles agreed on among themselves.
  test "the recorder is a sink: it counts what Event#emit hands a sink, and nothing else" do
    recorder = Dexpace::Conformance::ExecutorCase::EventRecorder.new
    logger = Dexpace::Instrumentation::Logger.build(sink: recorder)
    logger.event(Dexpace::Instrumentation::Severity::INFO)
          .event(Dexpace::Instrumentation::Events::INSTRUMENTATION_SHUTDOWN)
          .field("dexpace.executor.worker_count", 2).emit
    logger.event(Dexpace::Instrumentation::Severity::INFO)
          .event(Dexpace::Instrumentation::Events::INSTRUMENTATION_LOG).emit
    subject = Dexpace::Conformance::ExecutorCase.new(build: ->(**_kw) { FakePool.new },
                                                    recorder: recorder)

    assert_equal(2, recorder.entries.size)
    assert_equal(1, subject.shutdowns)
  end

  test "an unlatched close fails XCUT-13" do
    report = conforming(build: ->(events: nil, **_kw) { UnlatchedPool.new(events: events) })

    assert_equal(:failed, statuses(report)["XCUT-13"])
  end

  test "a holder that closes a borrowed executor fails XCUT-22" do
    report = conforming(borrow: ->(pool) { ClosingBorrowHolder.new(pool) })

    assert_equal(:failed, statuses(report)["XCUT-22"])
  end

  test "an executor accepting work after close fails ASYNC-16" do
    report = conforming(build: ->(events: nil, **_kw) { LeakyPool.new(events: events) })

    assert_equal(:failed, statuses(report)["ASYNC-16"])
  end

  test "a functional implementation whose close does work fails ASYNC-17" do
    report = conforming(functional: ->(events: nil, **_kw) { WorkingCloseExecutor.new(events) })

    assert_equal(:failed, statuses(report)["ASYNC-17"])
  end

  test "an adapter supplying no resource-free implementation makes ASYNC-17 vacuous" do
    report = conforming(functional: nil)

    assert_equal(:vacuous, statuses(report)["ASYNC-17"])
  end

  # The recorder-free path, stated as a whole report rather than two spot checks: XCUT-13 and
  # ASYNC-17 keep running on the half that needs no recorder, and only SEAM-25 -- whose whole
  # subject IS the event -- goes vacuous with XCUT-22.
  test "an adapter with no borrowing entry point and no recorder is vacuous, never failed" do
    report = conforming(borrow: nil, events: nil)

    assert_equal({ "SEAM-12" => :passed, "XCUT-13" => :passed, "XCUT-22" => :vacuous,
                   "ASYNC-16" => :passed, "ASYNC-17" => :passed, "SEAM-25" => :vacuous,
                   "ASYNC-3" => :waived },
                 statuses(report))
  end

  test "a second close emitting a second event fails SEAM-25" do
    report = conforming(build: ->(events: nil, **_kw) { UnlatchedPool.new(events: events) })

    assert_equal(:failed, statuses(report)["SEAM-25"])
  end
end
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Write `executor_case.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace/instrumentation/keys"
require_relative "vacuous"

module Dexpace
  module Conformance
    # What an ExecutorSuite assertion receives. The executor is a factory, never a constant --
    # dexpace-conformance declares dexpace-core and nothing else, so it can name no adapter.
    #
    # The event recorder is built ONCE PER CASE and passed into the factory as an `events:`
    # setting, never shared across a run. Runner builds a fresh case per assertion, so an earlier
    # assertion's shutdown event cannot be counted by a later one -- testing/4ef070df applied to a
    # subject the suite constructs. Measured: sharing one recorded array across the run made the
    # CONFORMING double fail.
    class ExecutorCase
      THREADS = 16

      # The recorder is a SINK, because a sink is where a shutdown is observable. No filed executor
      # in this repository exposes a shutdown counter: 8b's Pool reports its shutdown exactly once,
      # from #release, through the injected logger --
      # `@logger.event(Severity::INFO).event(Events::INSTRUMENTATION_SHUTDOWN).field(...).emit`
      # (8b plan:1725-1732) -- and Event#emit ends in
      # `@sink.public_send(@severity.sink_method) { rendered_record }` with
      # `record[Keys::EVENT] = @event_tag` (5b plan:2156-2175). So the portable observation is the
      # payload this sink receives, and the adapter's `build:` lambda is what wires it in: 8b's own
      # test does exactly that, `Logger.build(sink: sink)` (8b plan:1645-1651).
      #
      # Shaped on core's _Sink duck type (5b plan:886-896; NULL_SINK at 5b plan:861-872) and on 8b's
      # test-support RecordingSink (8b plan:686-715), whose mutex-guarded array this copies. Every
      # predicate answers true, so an INFO-severity shutdown is never filtered by Logger#enabled?
      # before it reaches here.
      class EventRecorder
        def initialize
          @payloads = []
          @mutex = ::Thread::Mutex.new
        end

        # The payloads this sink received, oldest first, as a dup -- a caller iterating cannot race
        # a close still running on another thread.
        def entries = @mutex.synchronize { @payloads.dup }

        def debug(msg = nil, &block) = record(msg, &block)
        def info(msg = nil, &block) = record(msg, &block)
        def warn(msg = nil, &block) = record(msg, &block)
        def error(msg = nil, &block) = record(msg, &block)

        def debug? = true
        def info? = true
        def warn? = true
        def error? = true

        private

        def record(msg)
          payload = block_given? ? yield : msg
          @mutex.synchronize { @payloads << payload }
          nil
        end
      end

      def initialize(build:, borrow: nil, functional: nil, recorder: nil)
        @build = build
        @borrow = borrow
        @functional = functional
        @recorder = recorder
      end

      def executor(**settings)
        return @build.call(**settings) if @recorder.nil?

        @build.call(events: @recorder, **settings)
      end

      def borrowed?
        !@borrow.nil?
      end

      def borrowed(pool)
        raise Vacuous, "this adapter exposes no borrowing entry point" if @borrow.nil?

        @borrow.call(pool)
      end

      # ASYNC-17's subject is a RESOURCE-FREE implementation, supplied separately: asserting the
      # no-op default against a pool that owns a thread would assert the opposite requirement. It
      # takes the recorder the same way `build:` does, so "its close shut nothing down" is a count
      # of events rather than an inference.
      def functional?
        !@functional.nil?
      end

      def functional
        raise Vacuous, "no resource-free implementation supplied" if @functional.nil?
        return @functional.call if @recorder.nil?

        @functional.call(events: @recorder)
      end

      def events?
        !@recorder.nil?
      end

      # SEAM-25's "close twice -> executor shut once, one event" needs this and nothing else: how
      # many Events::INSTRUMENTATION_SHUTDOWN payloads the recorder saw. Only the event NAME is
      # read -- 8b's two field keys ("dexpace.executor.worker_count", "dexpace.executor.drained")
      # are private_constants in the pool (8b plan:1295-1300) and deliberately absent from core's
      # Keys, "because the portable assertion needs the event name only".
      def shutdowns
        raise Vacuous, "no event recorder supplied to ExecutorSuite.run" if @recorder.nil?

        @recorder.entries.count do |payload|
          payload.is_a?(::Hash) &&
            payload[Dexpace::Instrumentation::Keys::EVENT] ==
              Dexpace::Instrumentation::Events::INSTRUMENTATION_SHUTDOWN
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write `executor_suite.rb` with its seven assertions**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "assertion"
require_relative "check"
require_relative "executor_case"
require_relative "failure"
require_relative "runner"
require_relative "vacuous"

module Dexpace
  module Conformance
    # Appendix B.7's lifecycle half, and the harness half of SEAM-25's lifecycle event -- which 8b's
    # design assigned to 8a and which 8a did not write; phase 9 writes it and says so.
    #
    # Every lifecycle observation in this file goes through ExecutorCase#shutdowns, the count of
    # Events::INSTRUMENTATION_SHUTDOWN payloads the recorder saw. That is the ONLY channel a filed
    # executor exposes a shutdown on (8b plan:1725-1732); an assertion reading a `#shutdown_count`
    # would be reading a method no adapter in this repository defines.
    module ExecutorSuite
      module_function

      def assertions
        @assertions ||= [concurrent_post, close_is_latched, borrowed_executor_survives,
                         graceful_shutdown, default_close_is_a_no_op,
                         one_shutdown_event, blocked_worker_is_released_on_cancel].freeze
      end

      # `events:` is a FACTORY returning a fresh recorder, not a recorder -- one per assertion.
      def run(build:, borrow: nil, functional: nil, events: nil, waive: [], around: nil)
        Runner.run(assertions, waive: waive, around: around) do
          ExecutorCase.new(build: build, borrow: borrow, functional: functional,
                           recorder: events&.call)
        end
      end

      # SEAM-12 / XCUT-11: "invoke one shared instance from many threads and assert no cross-talk."
      # Sixteen threads each post a distinct value; the assertion is on the collected set, never on
      # timing, so the test runs alone in any order (testing/4ef070df).
      def concurrent_post
        Assertion.build(ids: %w[SEAM-12 XCUT-11], name: "a shared executor takes work from many threads",
                        body: lambda do |subject|
                          pool = subject.executor
                          seen = ::Thread::Queue.new
                          Array.new(ExecutorCase::THREADS) { |i| ::Thread.new { pool.post { seen << i } } }
                            .each(&:join)
                          pool.close

                          collected = []
                          collected << seen.pop until seen.empty?

                          Check.that(collected.sort == (0...ExecutorCase::THREADS).to_a,
                                     "work posted from many threads was lost or duplicated",
                                     expected: (0...ExecutorCase::THREADS).to_a,
                                     actual: collected.sort, ids: %w[SEAM-12 XCUT-11])
                        end)
      end

      # XCUT-13 / ASYNC-15 clauses (a) and (b): close is latched and ownership-aware. Clause (c),
      # interrupt-safety, is scoped out -- section 8.3 bans every primitive that could arrange a
      # pending interrupt, so the clause holds by the flag never being touched
      # (cross-cutting-invariants/8fa2c08d) and there is nothing observable to assert.
      #
      # Two halves, because only one needs a recorder. Closeable#close returns nil on the winning
      # AND the losing call (phase 2 plan:558-568), which is assertable against any adapter; that
      # the shutdown WORK ran once is visible only in the lifecycle event, so the count runs when
      # the adapter supplied a recorder and is skipped -- not failed -- when it did not.
      def close_is_latched
        Assertion.build(ids: %w[XCUT-13 ASYNC-15], name: "an owned executor's close is idempotent",
                        body: lambda do |subject|
                          pool = subject.executor
                          pool.close
                          second = begin
                            pool.close
                          rescue ::StandardError => e
                            e
                          end
                          Check.that(second.nil?,
                                     "a second close raised or returned a value instead of latching",
                                     expected: nil, actual: second, ids: %w[XCUT-13 ASYNC-15])

                          return unless subject.events?

                          shutdowns = subject.shutdowns
                          Check.that(shutdowns == 1,
                                     "close shut the executor more than once",
                                     expected: 1, actual: shutdowns, ids: %w[XCUT-13 ASYNC-15])
                        end)
      end

      # XCUT-22 / ASYNC-15 clause (b): the SDK closes only what it created. 8b discharges this at the
      # bridge, whose `owned: false` keeps Closeable#close from ever reaching #release (phase 2
      # plan:564-566), so the borrowed executor must still be USABLE afterwards -- observable with
      # no recorder at all -- and must have emitted no shutdown event.
      def borrowed_executor_survives
        Assertion.build(ids: %w[XCUT-22 ASYNC-15],
                        name: "a caller-supplied executor survives its holder's close",
                        body: lambda do |subject|
                          raise Vacuous, "this adapter exposes no borrowing entry point" unless subject.borrowed?

                          underlying = subject.executor
                          holder = subject.borrowed(underlying)
                          holder.close

                          alive = ::Thread::Queue.new
                          still_open = begin
                            underlying.post { alive << :ok }
                            true
                          rescue ::StandardError
                            false
                          end
                          Check.that(still_open,
                                     "the SDK shut down an executor it borrowed",
                                     expected: "still accepting work", actual: "refused work",
                                     ids: %w[XCUT-22 ASYNC-15])

                          if subject.events?
                            shutdowns = subject.shutdowns
                            Check.that(shutdowns.zero?,
                                       "the SDK emitted a shutdown event for an executor it borrowed",
                                       expected: 0, actual: shutdowns, ids: %w[XCUT-22 ASYNC-15])
                          end

                          underlying.close
                          nil
                        end)
      end

      # ASYNC-16 (SHOULD): "shut it down gracefully on close -- stop accepting new work and WAIT for
      # in-flight tasks to finish rather than interrupting them." Both halves are observable without
      # an interrupt.
      def graceful_shutdown
        Assertion.build(ids: ["ASYNC-16"], name: "close drains in-flight work and refuses new work",
                        body: lambda do |subject|
                          pool = subject.executor
                          done = ::Thread::Queue.new
                          8.times { |i| pool.post { done << i } }
                          pool.close

                          drained = []
                          drained << done.pop until done.empty?
                          Check.that(drained.sort == (0...8).to_a,
                                     "close did not wait for in-flight work to finish",
                                     expected: 8, actual: drained.size, ids: ["ASYNC-16"])

                          refused = begin
                            pool.post { done << :after }
                            false
                          rescue ::StandardError
                            true
                          end
                          Check.that(refused || done.empty?,
                                     "the executor accepted new work after close",
                                     expected: "refused", actual: "accepted", ids: ["ASYNC-16"])
                        end)
      end

      # ASYNC-17 (SHOULD): "the async transport SPI SHOULD provide a NO-OP DEFAULT close so
      # lightweight/functional implementations need not implement lifecycle management." A no-op
      # close shuts nothing down, so it emits no lifecycle event -- the same recorder, read for zero
      # rather than for one. "behavior of executeAsync after close is undefined" is why the second
      # half is an event count and not a post-after-close probe.
      def default_close_is_a_no_op
        Assertion.build(ids: ["ASYNC-17"], name: "a resource-free implementation inherits a no-op close",
                        body: lambda do |subject|
                          raise Vacuous, "no resource-free implementation supplied" unless subject.functional?

                          functional = subject.functional
                          Check.that(functional.respond_to?(:close),
                                     "a functional implementation has no close at all",
                                     expected: "#close", actual: "absent", ids: ["ASYNC-17"])
                          functional.close
                          functional.close

                          return unless subject.events?

                          shutdowns = subject.shutdowns
                          Check.that(shutdowns.zero?,
                                     "a resource-free implementation's close shut something down",
                                     expected: 0, actual: shutdowns, ids: ["ASYNC-17"])
                        end)
      end

      # SEAM-25 (the event half phase 2 postponed, emitted by 8b): one lifecycle event on the FIRST
      # close of an owned executor, and none on
      # the second. The event name is core's (Events::INSTRUMENTATION_SHUTDOWN, 5b plan:741); the
      # two field keys around it are the adapter's private constants and are never read.
      def one_shutdown_event
        Assertion.build(ids: ["SEAM-25"],
                        name: "closing an owned executor emits exactly one shutdown event",
                        body: lambda do |subject|
                          raise Vacuous, "no event recorder supplied" unless subject.events?

                          pool = subject.executor
                          pool.close
                          pool.close
                          shutdowns = subject.shutdowns

                          Check.that(shutdowns == 1,
                                     "an owned executor's close did not emit exactly one event",
                                     expected: 1, actual: shutdowns, ids: ["SEAM-25"])
                        end)
      end

      # ASYNC-3 (unsatisfied MUST, design R5, section 10.5): "cancel-with-interrupt against a blocking
      # worker". Written so it genuinely FAILS on every executor this repository can build -- the
      # thread pool cannot interrupt a worker (section 8.3 bans Thread#raise, Thread#kill and
      # Timeout.timeout) and an inline executor blocks the posting thread -- and the first-party
      # drivers waive it BY ID so the report prints `waived (would fail): ASYNC-3`, never passed
      # and never vacuous. The pivot is core's Transport.async_over (phase 2), which is how a
      # cancellation token reaches a posted unit at all; the SPI's #post takes no token.
      #
      # The wait is the requirement's own shape, "within a bound", observed through queues: the
      # worker's ENTRY is a queue push (no sleep guesses that it started), the RELEASE is a queue
      # pop with a timeout (Ruby >= 3.2), and the ensure frees the gate so a failed run leaks no
      # worker and no thread.
      BLOCKED_WORKER_BOUND = 1.0

      def blocked_worker_is_released_on_cancel
        Assertion.build(ids: ["ASYNC-3"],
                        name: "cancelling a task blocked on a worker releases the worker within a bound",
                        body: lambda do |subject|
                          unless defined?(::Dexpace::Transport) && ::Dexpace::Transport.respond_to?(:async_over)
                            raise Vacuous, "Dexpace::Transport.async_over is absent; phase 2 committed to it"
                          end

                          gate = ::Thread::Queue.new
                          entered = ::Thread::Queue.new
                          released = ::Thread::Queue.new
                          transport = BlockingTransport.new(gate: gate, entered: entered, released: released)
                          pool = subject.executor
                          source = ::Dexpace::Cancellation.source
                          bridge = ::Dexpace::Transport.async_over(transport, executor: pool)
                          poster = ::Thread.new do
                            bridge.call(:request, nil, source.token).value
                          rescue ::StandardError
                            nil
                          end
                          begin
                            entered.pop # the worker is provably inside #call and blocked
                            source.cancel(:interrupt_requested)
                            freed = released.pop(timeout: BLOCKED_WORKER_BOUND)

                            Check.that(!freed.nil?,
                                       "a worker blocked in an uninterruptible call was not released after cancel",
                                       expected: "released within #{BLOCKED_WORKER_BOUND}s of cancel",
                                       actual: "still blocked", ids: ["ASYNC-3"])
                          ensure
                            gate << :free
                            poster.join(BLOCKED_WORKER_BOUND)
                            pool.close
                          end
                        end)
      end

      # The blocking subject: answers the transport seam's #call, parks on a gate with NO timeout,
      # and reports its own entry and release. Returns a closeable so the pivot's orphan-close
      # path (SEAM-30) has something to close when the cancelled caller is refused the result.
      class BlockingTransport
        def initialize(gate:, entered:, released:)
          @gate = gate
          @entered = entered
          @released = released
        end

        def call(_request, _options, _cancellation)
          @entered << :in
          @gate.pop
          Closeable.new
        ensure
          @released << :out
        end

        class Closeable
          def close = nil
        end
      end
      private_constant :BlockingTransport
    end
  end
end
```

- [ ] **Step 5: Wire the entry file and write the adapter-gem driver**

```ruby
require_relative "conformance/executor_case"
require_relative "conformance/executor_suite"
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# SEAM-25's lifecycle-event harness, driven against the first thing in this repository that actually
# OWNS an executor.
#
# ExecutorSuite.run is called directly and its report asserted: 8a's MinitestDriver#conformance
# builds a TransportCase per assertion (8a plan:2302-2306) and rejects functional:/events:, and
# widening it would change an interface phase 8 owns (R6).
#
# Built from 8b's filed fence. Pool's constructor is private and .build takes size:, queue_limit:,
# shutdown_timeout:, name:, logger: and clock: -- there is NO events: keyword and NO #shutdown_count
# (8b plan:1317-1336, 1349-1364). The shutdown is observable in exactly one place: #release emits
# Events::INSTRUMENTATION_SHUTDOWN at Severity::INFO through the injected logger (8b plan:1725-1732).
# So this lambda TRANSLATES the suite's `events:` recorder into `logger:`, which is what 8b's own
# test does -- `Logger.build(sink: sink)`, then count the entries whose payload names the event
# (8b plan:1644-1651). The recorder IS the sink: ExecutorCase::EventRecorder implements core's _Sink
# duck type (5b plan:886-896), so nothing in this file adapts between two shapes.
#
# borrow: and functional: stay nil. 8b files no borrowing entry point in THIS gem -- the holder of a
# caller-supplied executor is Transport.async_over (8b plan:2872) -- and no resource-free
# implementation, so XCUT-22 and ASYNC-17 report :vacuous with their reasons.
class DexpaceAsyncThreadConformanceTest < Minitest::Test
  def test_executor_suite
    report = Dexpace::Conformance::ExecutorSuite.run(
      build: lambda do |events: nil, **settings|
        logger = if events.nil?
                   Dexpace::Instrumentation::Logger::NULL
                 else
                   Dexpace::Instrumentation::Logger.build(sink: events)
                 end
        Dexpace::Async::Thread::Pool.build(size: 2, logger: logger, **settings)
      end,
      borrow: nil, functional: nil,
      events: -> { Dexpace::Conformance::ExecutorCase::EventRecorder.new },
      # ASYNC-3 is waived BY ID, never removed: this pool cannot release a worker blocked in an
      # uninterruptible call (design section 10.5, an unsatisfied MUST), the assertion genuinely fails
      # against it,
      # and the report prints `waived (would fail): ASYNC-3` on every run (design R5).
      waive: ["ASYNC-3"]
    )

    assert(report.passed?, report.to_s)
    assert_includes(report.to_s, "waived (would fail): ASYNC-3")
  end
end
```

If `Dexpace::Async::Thread` exposes no `.inline` or equivalent resource-free implementation when this
runs, pass `functional: nil` and let `ASYNC-17` report `:vacuous` with its reason — **do not invent
one inside the adapter**, which `R6` forbids.

- [ ] **Step 6: Run on the four installed interpreters**

Expected: 10 runs in the gem's own suite on each of 3.2.11, 3.3.12, 3.4.10 and 4.0.6, plus **one**
test in the adapter driver, and **the driver is expected GREEN against 8b's real `Pool`** — four
results, `SEAM-12`, `XCUT-13`, `ASYNC-16` and `SEAM-25` passing, `ASYNC-3` printed as
`waived (would fail): ASYNC-3`, with `XCUT-22` and `ASYNC-17` `:vacuous` for the reasons the
driver's own comment gives. (Once Task 12a lands, `XCUT-22`'s vacuity is on a **MUST** and the
driver must name it in `accepted_vacuous:` with its citation — 8b files no borrowing entry point;
the holder of a caller-supplied executor is `Transport.async_over`, 8b plan:2872 — or the report
blocks, which is that task's rule doing its job.) Measured during planning against a
stand-in transcribed from 8b's filed fence, on all four.

**If it is not green, read the report before touching either gem.** A `:failed` here is a finding
about `dexpace-async-thread` and belongs in the phase-9 report; an `:error` is almost always this
suite reaching for something 8b does not expose, which is a defect in *this* file — that is exactly
how an earlier draft came to read a `#shutdown_count` no filed executor has. `R6` forbids widening
8b's surface to suit the suite, and its **one named exception** — "a defect inside
`dexpace-conformance` itself that prevents the suite from running is phase 9's to fix, because
otherwise the phase has no instrument and the audit does not happen" — is what covers a repair here.
`R6` never licenses filing a suite defect as a finding against conforming code; that is a false
finding phase 10 would act on.

- [ ] **Step 7: Stage the change**

**No commit.**

```bash
git add -- gems/dexpace-conformance/lib/dexpace/conformance.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/executor_case.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/executor_suite.rb \
        gems/dexpace-conformance/sig/dexpace/conformance/executor_case.rbs \
        gems/dexpace-conformance/sig/dexpace/conformance/executor_suite.rbs \
        gems/dexpace-conformance/test/dexpace/conformance/executor_suite_test.rb \
        gems/dexpace-async-thread/test/
```

## Task 12: `Aggregate` — one report, and a preamble that states what green does not prove

**Files:**
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/aggregate.rb`
- Create: `gems/dexpace-conformance/sig/dexpace/conformance/aggregate.rbs`
- Test: `gems/dexpace-conformance/test/dexpace/conformance/aggregate_test.rb`

**Interfaces:**
- Consumes: `Report` (Task 3)
- Produces: `Aggregate.run(Array[Report]) -> Report`, `Aggregate.render(Report) -> String`,
  **`Aggregate.by_requirement_id(Array[suite], statuses: Report?) -> Hash[String, Array[Hash]]`**,
  `Aggregate::PREAMBLE`

**Files (addendum):**
- **Modify: `gems/dexpace-conformance/lib/dexpace/conformance.rb`** — `require_relative "conformance/aggregate"`

**`by_requirement_id` takes the SUITES, not a Report**, and that is a correction: `R7` says the
generated half of the coverage map is built by walking "every suite's `.assertions`", and a Report
holds only the assertions that actually **ran**. Reading a Report would let a suite skipped in one
invocation silently shorten the map — and Task 14's own row-count check would then fail for a reason
that has nothing to do with a dropped row. An assertion with no result is marked `:not_run` rather
than omitted, and each row names both the suite and the assertion, which the first draft conflated
into one `suite:` key holding the assertion name.

`docs/first-release.md` carries a standing blocker filed by 8a: "**Before release, `docs/sdk-documentation/` must state what a green `dexpace-conformance` run does and does not prove, and the run's own report preamble must name the same omissions.**" `PREAMBLE` is that, made mechanical — printed on every run rather than written once in a document nobody re-reads.

**This task's code was executed during planning** and re-measured 2026-09-13 on 3.2.11, 3.3.12, 3.4.10 and 4.0.6: **6 runs, 15 assertions, 0 failures** on each — one run per `test` block in Step 1's fence.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# One report over every suite, and the preamble docs/first-release.md's blocker requires.
# NFR-4, NFR-17, ASYNC-3, ASYNC-4; 8a's assertion protocol.
require_relative "../../test_helper"
require "dexpace/conformance/invariant_suite"

class DexpaceConformanceAggregateTest < DexpaceConformanceTestCase
  A = Dexpace::Conformance::Aggregate

  def report(*rows)
    results = rows.map do |(ids, name, status)|
      assertion = Dexpace::Conformance::Assertion.build(ids: ids, name: name, body: ->(_s) { nil })
      Dexpace::Conformance::Result.build(assertion: assertion, status: status)
    end
    Dexpace::Conformance::Report.new(results)
  end

  test "merging two suites keeps one passed? over the whole run" do
    merged = A.run([report([["XCUT-15"], "immutable", :passed]),
                    report([["NFR-1"], "zero deps", :failed])])

    assert_equal(2, merged.results.size)
    refute(merged.passed?)
  end

  test "vacuous and waived are counted apart and neither fails the run" do
    merged = A.run([report([["ASYNC-4"], "ordered interrupt", :vacuous],
                           [["ASYNC-3"], "two-mode cancellation", :waived])])

    assert(merged.passed?)
    assert_equal(1, merged.vacuous.size)
    assert_equal(1, merged.waived.size)
  end

  test "the rendered report states what a green run does not prove" do
    rendered = A.render(A.run([report([["XCUT-15"], "immutable", :passed])]))

    assert_includes(rendered, "It does not prove")
    assert_includes(rendered, "by reference")
  end

  test "by_requirement_id reads each suite's DECLARED assertions, not a report's results" do
    map = A.by_requirement_id([Dexpace::Conformance::InvariantSuite])

    assert_equal(2, map["XCUT-13"].size, "XCUT-13 carries two assertions, one per clause")
    assert_equal(%i[not_run not_run], map["XCUT-13"].map { |row| row[:status] })
  end

  test "by_requirement_id marks an assertion with no result :not_run rather than omitting it" do
    ran = Dexpace::Conformance::InvariantSuite.run(core: Module.new)
    map = A.by_requirement_id([Dexpace::Conformance::InvariantSuite], statuses: ran)

    refute_includes(map.values.flatten.map { |row| row[:status] }, :not_run)
  end

  test "each row names both the suite and the assertion, which are different things" do
    map = A.by_requirement_id([Dexpace::Conformance::InvariantSuite])
    row = map["XCUT-15"].first

    assert_equal("Dexpace::Conformance::InvariantSuite", row[:suite])
    refute_equal(row[:suite], row[:assertion])
  end
end
```

*(`"vacuous and waived are counted apart and neither fails the run"` is written as filed and is
**replaced by Task 12a**, which makes an un-waived, un-accepted MUST-level vacuity fail the
aggregate; added 2026-09-13.)*

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Write the implementation**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "report"

module Dexpace
  module Conformance
    # One report over every suite in a run. This is the caller phase 8a deferred Report#to_h for.
    module Aggregate
      # Section 12 distinguishes "not satisfied" from "holds vacuously", and section 9.3 requires a
      # waived gap to stay visible. So the preamble states, on every run, what a green result does
      # NOT prove -- which is docs/first-release.md's standing blocker made mechanical rather than
      # written once in a document nobody re-reads.
      PREAMBLE = [
        "A pass here proves the assertions below ran green. It does not prove:",
        "  - TLS verification or connect-timeout classification: the wire fixture speaks plaintext",
        "    only and there is no portable way to make a local listener accept slowly, so both are",
        "    asserted in dexpace-transport-net_http's own suite and not in this one (8a's P8-9)",
        "  - anything covered 'by reference' in APPENDIX_B.md, where the evidence is another gem's",
        "    test file: the row proves the ID is claimed and the file exists, not that the",
        "    behaviour is asserted (phase 9's P9-7)",
        "  - any requirement whose assertion is listed below as waived or vacuous"
      ].freeze

      module_function

      def run(reports)
        Report.merge(reports)
      end

      def render(report)
        [*PREAMBLE, "", report.to_s].join("\n")
      end

      # The generated half of the appendix-B coverage map: every assertion **declared** by every
      # suite, keyed by requirement ID -- read off each suite's `.assertions`, never off a Report.
      # A Report holds only the assertions that actually RAN, so reading one would let a suite
      # skipped in a given invocation silently shorten the map and fail its own row-count check
      # (design R7).
      #
      # `statuses` is an optional Report: when given, each row carries the status that run produced,
      # and an assertion with no result is marked :not_run rather than omitted.
      def by_requirement_id(suites, statuses: nil)
        observed = (statuses.nil? ? [] : statuses.results)
                   .to_h { |result| [result.assertion.name, result.status] }
        suites.each_with_object({}) do |suite, map|
          suite.assertions.each do |assertion|
            assertion.ids.each do |id|
              (map[id] ||= []) << { suite: suite.name, assertion: assertion.name,
                                    status: observed.fetch(assertion.name, :not_run) }
            end
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write the `sig/` mirror, wire the entry file, run on the four installed interpreters**

```ruby
require_relative "conformance/aggregate"
```

Expected: 6 runs, PASS. (Measured **6 runs, 15 assertions, 0 failures** on 3.2.11, 3.3.12, 3.4.10
and 4.0.6 — six `test` blocks above, and `assert_includes`/`refute_includes` count two each.)

- [ ] **Step 5: Stage the change**

**No commit.** `CLAUDE.md`: "Agents do not commit, push, or touch the remote unless the user asks for that specific action in that message." Every one of the twenty-one preceding plans in this repository has zero commit steps; the reviewer commits.

```bash
git add -- gems/dexpace-conformance/lib/dexpace/conformance/aggregate.rb
```

---

## Task 12a: `Levels` and the MUST-level vacuity blocker

*(Added 2026-09-13, plan re-verification. Lettered so no existing "Task N" citation moves; it sits
between Task 12, whose `Aggregate` it extends, and Task 13, and it MUST land before Task 15's
disposition run — the condition the blocker was postponed under on 2026-09-13. This task is the
blocker's owner.)*

**Requirement IDs:** `NFR-17` (no gate is advisory — a run that reports green over an unbuilt MUST
is an advisory gate wearing a green badge); the MUST-level vacuity blocker's mechanism; 8a's assertion
protocol, extended and not changed; the unsatisfied `ASYNC-3` MUST and `ASYNC-4` as the canonical
*sanctioned* MUST-level vacuity the mechanism must not block on; `NFR-8` as the canonical *gate-side*
vacuity it never sees.
**Design:** `R3` ("the aggregate report lists every un-waived `:vacuous` on a MUST-level ID
separately, and that list is a phase-9 report blocker"); `R6` step 1; `P9-3`; `P9-6`; the MUST-level
vacuity blocker entry under *Work phase 9 postponed, and who owns it now*.

**Files:**
- Create: `tools/requirement_levels.rb` — the generator; **reads** appendix C, never writes it
- Create: `gems/dexpace-conformance/lib/dexpace/conformance/levels.rb` — **generated**, committed
- Create: `gems/dexpace-conformance/sig/dexpace/conformance/levels.rbs`
- Create: `test/gates/requirement_levels_test.rb` — regenerate-and-diff, the way the surface
  snapshot is kept honest
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance/report.rb` and its `sig/` mirror (Task 3)
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance/runner.rb` (Task 2) and the `.run` of
  each phase-9 suite (Tasks 5, 9, 10, 11) — one pass-through keyword each
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance/transport_suite.rb`,
  `minitest_driver.rb`, `rspec_driver.rb` (8a's) — the **same** one keyword, see below
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance/aggregate.rb` and its `sig/` (Task 12)
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance.rb` — `require_relative "conformance/levels"`
- Modify: `gems/dexpace-conformance/test/dexpace/conformance/report_test.rb` (Task 3's two vacuity
  tests), `aggregate_test.rb` (Task 12's), `executor_suite_test.rb` (Task 11's full-hash tests)
- Modify: `gems/dexpace-async-thread/test/dexpace/async/thread/conformance_test.rb` (Task 11's
  driver) and `gems/dexpace-transport-net_http/test/dexpace/transport/net_http/conformance_test.rb`
  (8a's driver, Task 23 of its plan) — each names its sanctioned MUST-level vacuities with a citation

**Interfaces:**
- Consumes: `Report`, `Runner`, `Aggregate`, `Result`, appendix C
- Produces: `Dexpace::Conformance::Levels::OF -> Hash[String, Symbol]` (frozen; `:must`, `:should`,
  `:may`), `Levels.of(id) -> Symbol` (`:unknown` for an ID appendix C does not hold),
  `Levels.must?(id)`, `Levels.known?(id)`; `Report.new(results, accepted_vacuous: {})`,
  `Report.merge(reports, accepted_vacuous: {})`, `Report#blocking_vacuities -> Array[Result]`,
  `Report#accepted_vacuities -> Array[Result]`, `Report#accepted_vacuous -> Hash[String, String]`,
  `Report#unknown_ids -> Array[String]`; `Runner.run(assertions, waive:, around:, accepted_vacuous: {})`;
  `accepted_vacuous: {}` on every suite's `.run` and on both drivers; `Aggregate.run(reports,
  accepted_vacuous: {})`; two new `PREAMBLE` lines

**What this task is for, in one sentence.** `R3` makes an *absent* artifact `:vacuous` rather than
`:failed` so phase 10 can tell "not built" from "built wrong" — and that is safe only if nothing
passes by not being built. As filed, `Report#passed?` was true over vacuous results (8a's own report
test asserts exactly that, and Task 3's and Task 12's tests repeated it) and nothing in the gem knew
whether an ID is a MUST or a SHOULD, so a MUST that never got built read as a green run. The design's
postponed-work entry records that as a manager decision not to be lost; this task is the mechanism and
the owner.

**Three decisions, each forced.**

1. **The level map is generated from appendix C and committed, not read at runtime.** A gem
   cannot read `docs/` from a consumer's machine, and appendix C is normative and **frozen** —
   `Guard::FROZEN` in `.claude/skills/housekeeping/guard.rb` makes every maintenance tool refuse to
   write there, and this tool is held to the same rule by construction: it opens the file for
   reading, renders `levels.rb`, and has no code path that writes anywhere else. Drift is caught the
   way the runtime surface snapshot is caught: `test/gates/requirement_levels_test.rb` regenerates
   in memory and diffs against the committed file, so an edit to appendix C that is not followed by
   `ruby tools/requirement_levels.rb` is a red test naming the stale IDs. `MUST NOT` is `:must` — it
   is a MUST with a negated predicate, and appendix C holds exactly one.
2. **Sanctioned vacuities are accepted by ID with a mandatory citation, through a keyword distinct
   from `waive:`.** `ASYNC-4` is a MUST and is `:vacuous` by design §10.5's own argument ("a port
   that never interrupts has no interrupt ordering to get wrong"); `XCUT-22` is a MUST and is
   `:vacuous` in the thread driver because 8b files no borrowing entry point; 8a's driver records
   `TRANSPORT-18` and `TRANSPORT-12` as `:vacuous` on `Net::HTTP` (8a plan:4905-4907). None of
   these may block a first-party run, and none may be hidden by `waive:` either — a waived assertion
   *would have failed* and a vacuous one *could not have run*, and the report has kept those apart
   since 8a. So a driver passes `accepted_vacuous: { "ASYNC-4" => "design §10.5: …" }`, every value
   is a non-empty citation string or `Report.new` raises `ArgumentError`, and the report renders
   them under their own heading, **"accepted MUST-level vacuities (design-sanctioned)"**, on every
   run. Everything else that is un-waived, `:vacuous` and MUST-level goes under **"MUST-level
   vacuities (report blockers)"**, and `#passed?` is false while that list is non-empty. A
   SHOULD-level or MAY-level vacuity is recorded and does not block.
3. **`Report#passed?` changes meaning once, for every report the gem produces — which reaches
   8a's `TransportSuite`, and that is the one 8a surface this task widens.** The alternative — a
   second predicate, `#blocking?`, that a CI step must remember to call alongside `#passed?` — is the
   green-over-defect shape again, one forgotten call away. `Report` is one class; two meanings for
   one predicate depending on which suite built it would be a hidden mode. So `TransportSuite.run`,
   `MinitestDriver#conformance` and `RSpecDriver` each gain the same `accepted_vacuous: {}` keyword,
   passed through to `Report.new` and nothing else — a widening `NFR-4` permits, not the refactor
   onto `Runner` this plan declines. The Global Constraints' "widening it would change an interface
   phase 8 owns" is about building a `TransportCase` per assertion and stands; this is one keyword
   with a default, added so 8a's own net_http driver can keep asserting `report.passed?` truthfully.

- [ ] **Step 1: Write the failing tests**

`test/gates/requirement_levels_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# MUST-level vacuity blocker (Task 12a): the level map is generated from appendix C and must never
# drift from it. Appendix C is
# frozen; the tool under test reads it and writes only levels.rb. NFR-17.
require "minitest/autorun"
require_relative "../../tools/requirement_levels"
require_relative "../../gems/dexpace-conformance/lib/dexpace/conformance/levels"
require_relative "../../gems/dexpace-conformance/lib/dexpace/conformance"

class RequirementLevelsTest < Minitest::Test
  PREFIXES = %w[SEAM HTTP IO BODY CTX PIPE RECOV RETRY REDIR AUTH PAGE SSE SERDE OBS CFG TRANSPORT ASYNC XCUT NFR].freeze

  def test_the_committed_map_equals_a_fresh_parse_of_appendix_c
    assert_equal(RequirementLevels.parse, Dexpace::Conformance::Levels::OF,
                 "levels.rb is stale: run `ruby tools/requirement_levels.rb`")
  end

  def test_appendix_c_yields_645_ids_over_the_19_prefixes_and_every_id_has_a_level
    map = RequirementLevels.parse

    assert_equal(645, map.size, "CLAUDE.md: 645 numbered requirements; the spec is frozen, so a change here is a human decision")
    assert_equal(PREFIXES.sort, map.keys.map { |id| id.sub(/-\d+\z/, "") }.uniq.sort)
    assert_equal(%i[may must should], map.values.uniq.sort)
  end

  def test_must_not_is_a_must
    assert_equal(:must, RequirementLevels::LEVEL.fetch("MUST NOT"))
  end

  def test_the_tool_never_writes_appendix_c
    before = RequirementLevels::SOURCE.read
    RequirementLevels.render(RequirementLevels.parse)

    assert_equal(before, RequirementLevels::SOURCE.read)
  end

  # The failing fixture: one flipped level is a diff, not a pass.
  def test_a_map_with_one_level_flipped_does_not_equal_the_committed_file
    stale = RequirementLevels.render(RequirementLevels.parse.merge("ASYNC-4" => :should))

    refute_equal(RequirementLevels::TARGET.read, stale)
  end

  def test_every_id_any_suite_declares_is_one_appendix_c_knows
    suites = [Dexpace::Conformance::InvariantSuite, Dexpace::Conformance::PackagingSuite,
              Dexpace::Conformance::CodecSuite, Dexpace::Conformance::ExecutorSuite,
              Dexpace::Conformance::TransportSuite]
    declared = Dexpace::Conformance::Aggregate.by_requirement_id(suites).keys

    assert_empty(declared.reject { |id| Dexpace::Conformance::Levels.known?(id) })
  end
end
```

Amend Task 3's `report_test.rb` — replace `"a vacuous result does not fail the run"` with two tests
and add two more:

```ruby
  test "a SHOULD-level vacuity is recorded and does not fail the run" do
    report = Dexpace::Conformance::Report.new([result(["XCUT-12"], :vacuous)])

    assert(report.passed?)
    assert_empty(report.blocking_vacuities)
  end

  # The failing fixture the MUST-level vacuity blocker exists for: an unbuilt MUST is not a green run.
  test "an un-waived, un-accepted MUST-level vacuity is a report blocker and fails the run" do
    report = Dexpace::Conformance::Report.new([result(["ASYNC-4"], :vacuous)])

    refute(report.passed?)
    assert_equal(["ASYNC-4"], report.blocking_vacuities.flat_map { |r| r.assertion.ids })
    assert_includes(report.to_s, "MUST-level vacuity (report blocker): ASYNC-4")
    assert_includes(report.to_s, "REPORT BLOCKED: 1 un-waived MUST-level vacuit")
  end

  test "an accepted MUST-level vacuity carries its citation, renders apart, and does not block" do
    report = Dexpace::Conformance::Report.new(
      [result(["ASYNC-4"], :vacuous)],
      accepted_vacuous: { "ASYNC-4" => "design §10.5: a port that never interrupts has no interrupt ordering to get wrong" }
    )

    assert(report.passed?)
    assert_equal(1, report.accepted_vacuities.size)
    assert_includes(report.to_s, "accepted MUST-level vacuity (design-sanctioned): ASYNC-4: design §10.5")
    assert_equal(["ASYNC-4"], report.to_h[:accepted_vacuities].map { |row| row[:ids].first })
  end

  test "an acceptance with no citation is refused at construction, not rendered as a blank" do
    assert_raises(::ArgumentError) do
      Dexpace::Conformance::Report.new([result(["ASYNC-4"], :vacuous)], accepted_vacuous: { "ASYNC-4" => "" })
    end
  end

  test "a waived result is never counted as a vacuity, accepted or blocking" do
    report = Dexpace::Conformance::Report.new([result(["ASYNC-3"], :waived)])

    assert(report.passed?)
    assert_empty(report.blocking_vacuities)
    assert_includes(report.to_s, "waived (would fail): ASYNC-3")
  end
```

Amend Task 12's `aggregate_test.rb` — replace `"vacuous and waived are counted apart and neither
fails the run"` with:

```ruby
  test "vacuous and waived are counted apart; a SHOULD-level vacuity does not fail the run" do
    merged = A.run([report([["XCUT-12"], "wait-free reads", :vacuous],
                           [["ASYNC-3"], "two-mode cancellation", :waived])])

    assert(merged.passed?)
    assert_equal(1, merged.vacuous.size)
    assert_equal(1, merged.waived.size)
  end

  test "an un-accepted MUST-level vacuity blocks the aggregate, and an accepted one does not" do
    reports = [report([["ASYNC-4"], "ordered interrupt", :vacuous])]

    refute(A.run(reports).passed?)
    assert(A.run(reports, accepted_vacuous: { "ASYNC-4" => "design §10.5" }).passed?)
  end

  test "the rendered report names the blocker section and the preamble says why" do
    rendered = A.render(A.run([report([["ASYNC-4"], "ordered interrupt", :vacuous])]))

    assert_includes(rendered, "MUST-level vacuity (report blocker): ASYNC-4")
    assert_includes(rendered, "design R3")
  end
```

Amend Task 11's `executor_suite_test.rb`: the recorder-free full-hash test now runs
`conforming(borrow: nil, events: nil, accepted_vacuous: { "XCUT-22" => "no borrowing entry point supplied to this run", "SEAM-25" => "no event recorder supplied to this run" })`
and asserts `report.passed?`; add one test that the same run **without** `accepted_vacuous:` has
`refute(report.passed?)` and lists `XCUT-22` and `SEAM-25` as blockers — both are MUSTs.

- [ ] **Step 2: Run to verify it fails**

Expected: `LoadError` on `tools/requirement_levels`; then, once the tool exists,
`NameError: uninitialized constant Dexpace::Conformance::Levels`; then `ArgumentError: unknown
keyword: :accepted_vacuous` from `Report.new`.

- [ ] **Step 3: Write the generator and generate `levels.rb`**

`tools/requirement_levels.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Generates gems/dexpace-conformance/lib/dexpace/conformance/levels.rb from appendix C (the
# MUST-level vacuity blocker, Task 12a).
#
# Appendix C is normative and FROZEN (CLAUDE.md; Guard::FROZEN). This tool READS it and writes
# exactly one file, TARGET, which is not under docs/. There is no code path that writes SOURCE.
#
#   ruby tools/requirement_levels.rb          # regenerate levels.rb
#   ruby tools/requirement_levels.rb --check  # exit 1 if levels.rb is stale
require "pathname"

module RequirementLevels
  ROOT = Pathname(__dir__).join("..").expand_path
  SOURCE = ROOT.join("docs/product-spec/appendix-c-consolidated-normative-requirement-index.md")
  TARGET = ROOT.join("gems/dexpace-conformance/lib/dexpace/conformance/levels.rb")
  # CLAUDE.md's 19 prefixes, in appendix-C order. Restricting the regex is what keeps ISO-8601 and
  # RFC-shaped tokens out of the map (Task 14 learned the same lesson).
  PREFIXES = %w[SEAM HTTP IO BODY CTX PIPE RECOV RETRY REDIR AUTH PAGE SSE SERDE OBS CFG
                TRANSPORT ASYNC XCUT NFR].freeze
  ROW = /\A\| ((?:#{PREFIXES.join("|")})-\d+) \| (MUST NOT|MUST|SHOULD|MAY) \|/
  LEVEL = { "MUST" => :must, "MUST NOT" => :must, "SHOULD" => :should, "MAY" => :may }.freeze

  module_function

  def parse(source = SOURCE)
    source.each_line.filter_map { |line| (m = ROW.match(line)) && [m[1], LEVEL.fetch(m[2])] }.to_h
  end

  def render(map)
    rows = map.map { |id, level| "        #{id.inspect} => #{level.inspect}," }.join("\n")
    <<~RUBY
      # frozen_string_literal: true
      # SPDX-License-Identifier: MIT

      # GENERATED by tools/requirement_levels.rb from appendix C -- do not edit; re-run the tool.
      # NFR-17; the MUST-level vacuity blocker (Task 12a).
      module Dexpace
        module Conformance
          # The normative level of every requirement ID, so a Report can tell a MUST-level vacuity
          # from a SHOULD-level one (design R3, Task 12a). A gem cannot read docs/ at runtime, so the
          # map is committed here and test/gates/requirement_levels_test.rb diffs it against
          # appendix C on every run.
          module Levels
            OF = {
      #{rows}
            }.freeze

            def self.known?(id) = OF.key?(id)
            def self.of(id) = OF.fetch(id, :unknown)
            def self.must?(id) = of(id) == :must
          end
        end
      end
    RUBY
  end
end

if $PROGRAM_NAME == __FILE__
  rendered = RequirementLevels.render(RequirementLevels.parse)
  if ARGV.include?("--check")
    exit(RequirementLevels::TARGET.exist? && RequirementLevels::TARGET.read == rendered ? 0 : 1)
  else
    RequirementLevels::TARGET.write(rendered)
    puts "wrote #{RequirementLevels::TARGET} (#{RequirementLevels.parse.size} ids)"
  end
end
```

Run `ruby tools/requirement_levels.rb`, commit the generated file with the change, and write the
`sig/` mirror: `OF: Hash[String, Symbol]`, `def self.known?: (String) -> bool`,
`def self.of: (String) -> Symbol`, `def self.must?: (String) -> bool`. `Levels.of` answers
`:unknown` rather than raising because a `Result` built in a test may carry an ID appendix C does not
hold; an unknown ID never blocks, and `Report#unknown_ids` plus the gate test above are what make a
typo visible instead of silent.

- [ ] **Step 4: Extend `Report`**

Replace Task 3's constructor, `.merge`, `#passed?`, `#to_s` and `#to_h` with:

```ruby
      # Merging Results rather than Reports keeps a single #passed? over the whole run. The
      # acceptances merge too: a suite-level acceptance survives aggregation, and an aggregate-level
      # one applies to every suite (Task 12a).
      def self.merge(reports, accepted_vacuous: {})
        inherited = reports.map(&:accepted_vacuous).reduce({}, :merge)
        new(reports.flat_map(&:results), accepted_vacuous: inherited.merge(accepted_vacuous))
      end

      attr_reader :results, :accepted_vacuous

      # `accepted_vacuous` is { "ID" => citation }. Every citation is mandatory and non-empty: an
      # acceptance is a claim that design section 12 or 10.5 sanctions the vacuity, and a blank claim
      # is the silent pass this mechanism exists to remove.
      def initialize(results, accepted_vacuous: {})
        @results = results.freeze
        @accepted_vacuous = accepted_vacuous.transform_keys(&:to_s).freeze
        @accepted_vacuous.each do |id, citation|
          next if citation.is_a?(::String) && !citation.strip.empty?

          raise ::ArgumentError, "accepted_vacuous[#{id.inspect}] needs a citation (design section 12 or 10.5)"
        end
      end

      # Design R3 / Task 12a: nothing passes by not being built. An un-waived :vacuous whose IDs
      # include a MUST that no acceptance names is a report blocker.
      def passed?
        failures.empty? && errors.empty? && blocking_vacuities.empty?
      end

      def blocking_vacuities
        vacuous.reject { |r| accepted?(r) }.select { |r| r.assertion.ids.any? { |id| Levels.must?(id) } }
      end

      def accepted_vacuities
        vacuous.select { |r| r.assertion.ids.any? { |id| Levels.must?(id) } && accepted?(r) }
      end

      def unknown_ids
        @results.flat_map { |r| r.assertion.ids }.uniq.reject { |id| Levels.known?(id) }
      end

      def to_s
        lines = ["#{passed.size} passed, #{failures.size} failed, #{vacuous.size} vacuous, " \
                 "#{waived.size} waived, #{errors.size} errored"]
        waived.each { |r| lines << "  waived (would fail): #{ids(r)} (#{r.assertion.name})" }
        accepted_vacuities.each { |r| lines << "  accepted MUST-level vacuity (design-sanctioned): #{ids(r)}: #{citation_for(r)}" }
        (vacuous - accepted_vacuities - blocking_vacuities).each { |r| lines << "  vacuous: #{ids(r)}: #{r.detail}" }
        blocking_vacuities.each { |r| lines << "  MUST-level vacuity (report blocker): #{ids(r)}: #{r.detail}" }
        failures.each { |r| lines << "  FAILED: #{ids(r)}: #{r.detail}" }
        errors.each { |r| lines << "  ERROR: #{ids(r)}: #{r.detail}" }
        unless blocking_vacuities.empty?
          lines << "REPORT BLOCKED: #{blocking_vacuities.size} un-waived MUST-level vacuit#{blocking_vacuities.size == 1 ? 'y' : 'ies'} (design R3)"
        end
        lines.join("\n")
      end

      def to_h
        {
          passed: passed.size, failed: failures.size, vacuous: vacuous.size,
          waived: waived.size, errored: errors.size,
          blocking_vacuities: blocking_vacuities.map { |r| { ids: r.assertion.ids, detail: r.detail } },
          accepted_vacuities: accepted_vacuities.map { |r| { ids: r.assertion.ids, citation: citation_for(r) } },
          unknown_ids: unknown_ids,
          results: @results.map do |r|
            { ids: r.assertion.ids, name: r.assertion.name, status: r.status, detail: r.detail }
          end
        }
      end

      private

      def accepted?(result)
        result.assertion.ids.all? { |id| !Levels.must?(id) || @accepted_vacuous.key?(id) }
      end

      def citation_for(result)
        result.assertion.ids.filter_map { |id| @accepted_vacuous[id] }.uniq.join("; ")
      end

      def ids(result) = result.assertion.ids.join(", ")
```

The first line of `#to_s` keeps 8a's shape — 8a's report test asserts it — and the blocker verdict
is a **last** line, so a reader who sees only the tail sees the verdict. `require_relative "levels"`
at the top of `report.rb`. Extend the `sig/` mirror with the new readers and the keyword.

- [ ] **Step 5: Pass `accepted_vacuous:` through every place a `Report` is built**

`Runner.run(assertions, waive: [], around: nil, accepted_vacuous: {}) { subject }` hands it to
`Report.new`. Each phase-9 suite's `.run` (`InvariantSuite`, `PackagingSuite`, `CodecSuite`,
`ExecutorSuite`) gains `accepted_vacuous: {}` and forwards it — a keyword with a default, so every
existing call in Tasks 5–11 is unchanged. 8a's `TransportSuite.run`, `MinitestDriver#conformance` and
`RSpecDriver` gain the identical keyword, forwarded to the `Report.new` each already performs, and
**nothing else in those three files changes** (decision 3 above). Then the two first-party drivers
name what planning already knows is sanctioned, each with its citation:

- `gems/dexpace-async-thread/test/dexpace/async/thread/conformance_test.rb` (Task 11 Step 5):
  `accepted_vacuous: { "XCUT-22" => "8b plan:2872 — the holder of a caller-supplied executor is Transport.async_over; this gem files no borrowing entry point" }`.
- `gems/dexpace-transport-net_http/test/dexpace/transport/net_http/conformance_test.rb` (8a's
  driver): `"TRANSPORT-18" => "8a plan:4905-4907 — vacuous once max_retries = 0; Net::HTTP drives no re-subscribable producer"` and
  `"TRANSPORT-12" => "design §12 TRANSPORT row — Net::HTTP has no wire grammar stricter than the model's; it drops nothing"`.
  `TRANSPORT-13` is a SHOULD and needs no entry.

**Any further MUST-level vacuity a first-party run produces is derived from the run's own output at
execution, never typed here in advance**: if the blocker section is non-empty and the entry is
sanctioned by §12 or §10.5, add the acceptance **with the citation**; if it is not sanctioned, it is
a finding — `R6`'s ladder, a `docs/first-release.md` line, and no acceptance. `ASYNC-4` is not a
suite result in any first-party run (no assertion carries it, Task 16 step 4) and needs no entry
unless one appears; if it does, its citation is design §10.5.

- [ ] **Step 6: Extend `Aggregate`**

`Aggregate.run(reports, accepted_vacuous: {})` calls `Report.merge(reports, accepted_vacuous:)`.
Add two lines to `PREAMBLE`, after the "waived or vacuous" bullet:

```ruby
        "  - a MUST-level requirement whose assertion is vacuous and that no accepted_vacuous:",
        "    citation names: such a result is listed below as a report blocker, fails this run,",
        "    and earns a docs/first-release.md line (design R3, Task 12a)"
```

`render` is unchanged — the sections travel in `report.to_s`. Regenerate the `sig/` mirror.

- [ ] **Step 7: Run on the four installed interpreters**

```bash
ruby tools/requirement_levels.rb --check && echo levels current
for v in 3.2.11 3.3.12 3.4.10 4.0.6; do
  mise exec ruby@$v -- ruby -w test/gates/requirement_levels_test.rb
  mise exec ruby@$v -- bundle exec rake test:gems
done
```

Expected: 6 runs in `requirement_levels_test.rb`, PASS; Task 3's report tests 9 runs (5 + 4 net of
the replaced one), Task 12's 8 runs, Task 11's 11 runs, all PASS; 8a's `report_test.rb` unchanged
and green; both first-party drivers green **with their acceptances printed** under "accepted
MUST-level vacuities (design-sanctioned)". If a driver is red with a non-empty blocker section, the
mechanism has found its first real vacuity: follow Step 5's last paragraph, do not add an
acceptance without a citation, and do not touch `Levels`.

- [ ] **Step 8: Stage the change**

**No commit.**

```bash
git add -- tools/requirement_levels.rb \
        test/gates/requirement_levels_test.rb \
        gems/dexpace-conformance/lib/dexpace/conformance.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/levels.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/report.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/runner.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/aggregate.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/transport_suite.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/minitest_driver.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/rspec_driver.rb \
        gems/dexpace-conformance/lib/dexpace/conformance/*_suite.rb \
        gems/dexpace-conformance/sig/ \
        gems/dexpace-conformance/test/ \
        gems/dexpace-async-thread/test/ \
        gems/dexpace-transport-net_http/test/
```

---

## Task 13: The three repository gates and the AST walker

**`gates:drain_loop` is out of v1** *(decided 2026-09-13)*. It is the one gate whose subject is
already decided elsewhere and decided better: Task 7's `bounded_map_drains` asserts `XCUT-14`'s
drain-to-cap clause **behaviourally and deterministically** — a store pre-filled to cap + 5, then one
`set`; a drain loop ends at 8 and a check-then-evict at 13, identically on 3.2.11, 3.3.12, 3.4.10 and
4.0.6 — while the gate measured **1 of 3 non-conforming shapes caught with one false positive** (a
`loop do … break … end` drain). A second line weaker than the first line is a maintenance cost, not
evidence. The trigger that would bring it back is in `docs/first-release.md` § Post-release triggers.
`.eviction_is_looped?` and the two drain fixtures are not written here.

**Files:**
- Create: `tools/ast_scan.rb`
- Create: `tools/invariant_gates.rb`
- Modify: `tasks/gates.rake` — three tasks
- **Modify: the root `Rakefile`** — the three names appended to `DEFAULT_GATES`. The array is defined
  in the `Rakefile`, which `load`s `tasks/*.rake` **before** defining it and then `.freeze`s it
  (phase 0 plan, Task 1 Step 6), so `tasks/gates.rake` can neither see it nor append to it — and a
  gate outside `DEFAULT_GATES` is not in `task default:`, which is exactly the advisory gate
  `NFR-17` forbids and this phase dispositions.
- **Modify: `.github/workflows/ci.yml`** — the three tasks placed in the `gates` job. Phase 0's
  `ci_workflow_test.rb` is **blocking** and asserts every `DEFAULT_GATES` entry appears in some job,
  so a phase that adds three gates and leaves the workflow alone reddens a phase-0 gate.
- Create: `test/fixtures/gates/walks_cause.rb`, `reflective_cause.rb`, `delegates_cause.rb`,
  `hash_shapes.rb`, `seam_shapes.rb`
- **Consumes, does not create**: `test/fixtures/gates/warns_unused.rb`, written by Task 1
- Test: `test/gates/invariant_gates_test.rb`

**Interfaces:**
- Consumes: nothing in `dexpace-conformance`; these are repository gates, not portable assertions
  (design `R4`, addenda A4–A7)
- Produces: `AstScan::SEND_TYPES`, `::SYMBOL_TYPES`, `::REFLECTIVE_SENDS`,
  **`AstScan.parse(path)`** — the one parse entry point, see correction 6 —
  `AstScan.receiver_calls(path, names)`, `.hash_ivar_assignments(path)`, `.constant_paths(path)`,
  `.string_literals(path)`;
  `InvariantGates::CAUSE_WALK_ALLOWED`, `::BOUNDED_MAP_ALLOWED`, `::ADAPTER_NAMESPACES`;
  `InvariantGates.cause_walk(files, allowed:)`, `.bounded_map(files, allowed:)`,
  `.seam_names(files, namespaces:)`; rake tasks
  `gates:cause_walk`, `gates:bounded_map`, `gates:seam_names`, and the `PENDING`-empty assertion
  added to 7b's existing `gates:serde_boundary`

**This task's code was executed during planning** on 3.2.11, 3.3.12, 3.4.10 and 4.0.6: **11 runs, 42
assertions, 0 failures** on each, against the mutation fixtures plus Task 1's `warns_unused.rb`; the
two drain fixtures and the `drain_loop` test in that count are dropped with the gate, so the run
counts fall by one test and its assertions.
(Re-measured 2026-09-13 straight out of this document with nothing adapted. The same fences without
correction 6's test and fixture measured **10 runs, 39 assertions** on all four, and before this
task's tenth test was added, **9 runs, 25 assertions**.)

**Six measured corrections, each one a gate that was wrong about a real file** — the first three
reported clean over a live defect, the next two red over conforming code, and the sixth raised over
a file it merely reads.

1. **A send is three node types, not one.** `a.cause` is `:CALL`, `a&.cause` is `:QCALL`, bare
   `cause` is `:VCALL`. A `:CALL`-only scan found 2 of 3 sends in one fixture and missed every
   safe-navigated one.
2. **A reflective send bypasses call-syntax scanning entirely.** `send(:cause)`, `__send__`,
   `public_send` and `method(:cause)` all reached the invariant untouched: the gate caught **3 of 7**
   realistic shapes before `REFLECTIVE_SENDS`, and **6 of 7** after — the seventh, `send(variable)`,
   is statically undecidable and is written into the gate's stated gap rather than left implied.
3. **A Symbol literal is `:LIT` on Ruby 3.2 and `:SYM` on 3.4 and 4.0.** Measured on all three, and
   it is the reverse of the usual direction — the *newer* interpreters diverge. A scan naming only
   `:LIT` caught 6 of 7 on the floor and **2 of 7** on both newer rows: a gate strictest exactly
   where it runs least.
4. **`seam_names` matches an ADAPTER-OWNED LEAF NAMESPACE — not a literal spelling, and not a seam
   namespace.** A fixed list of four fully qualified names caught **0 of 4** realistic shapes. The
   next draft matched the last two segments against `Serde`/`Transport`/`Async`/`Instrumentation`
   and flagged **31 references in 15 of core's own filed files** — `Async::Completer`,
   `Async::Future`, `Instrumentation::*` — which made Task 17's green gate set unreachable. The rule
   now names the four leaves the MVP adapter gems own (`CLAUDE.md`'s gem table) — `Serde::JSON`,
   `Transport::NetHTTP`, `Transport::AsyncHTTP`, `Async::Thread` — anywhere in the path. It therefore
   **does** need that list, and a later adapter gem must add its leaf or stay invisible to the gate.
5. **`cause_walk` skips a send that carries arguments, and covers `:FCALL` and `:BLOCK_PASS`.**
   `Exception#cause` takes no argument, so `logger.event(:warn).cause(e)` — 5b's filed `Event#cause`
   builder (5b plan:2128-2131) — is some other `#cause`, and reporting it made the gate red over
   conforming code. `cause()` is `:FCALL` and `errors.map(&:cause)` is a `:BLOCK_PASS`, and both walk
   the chain. Node shapes measured identical on 3.2.11, 3.3.12, 3.4.10 and 4.0.6 apart from `:LIT`/`:SYM`.
6. **A scanned file's own `-w` diagnostics fire phase 0's warnings-fatal gate, and this plan said
   they did not.** `parse_file` emits no warning *of its own* for well-formed input — which is what
   was measured, against a file carrying no diagnostic — but the **scanned file's** diagnostics are
   emitted at parse time and routed through `Warning.warn` exactly as at require time, and
   `test/gates/invariant_gates_test.rb` requires `dexpace_test_case`, whose `FatalWarnings` raises
   on the first one. 8a's filed `adapter.rb` is a live instance: `rescue ::StandardError => e`
   inside `Adapter#dispatch` never reads `e` (8a plan:4858) and emits `assigned but unused
   variable - e` on 3.2.11, 3.3.12, 3.4.10 and 4.0.6. Measured with `warns_unused.rb` added and the
   scanner unchanged: `RuntimeError: warning treated as an error (NFR-6)` raised out of
   `AstScan.receiver_calls` on all four. The fix is `AstScan.parse`, and **which** suppression was
   measured rather than assumed: `Warning[:deprecated] = false` does not reach it (the warning
   carries no category), `$VERBOSE = false` silences the `-w` class but leaves the always-on parse
   warnings firing (`key :a is duplicated` still raised on all four), and only `$VERBOSE = nil`
   silences both — restored in `ensure`, so outside the window `NFR-6`'s gate is armed as before.

**`gates:bounded_map`'s six hits over the filed fences are adjudicated, and five of the six are
false positives with their reason filed in `BOUNDED_MAP_ALLOWED`.** Measured 2026-09-13 by running
the two fences above, unmodified, over every Ruby fence in phases 0–8 that names a `lib/` path —
222 fences at 184 distinct `gems/*/lib/**/*.rb` paths, 2 of which do not parse and neither of which
contains a `Hash` ivar. Six offences in five files, identically on 3.2.11, 3.3.12, 3.4.10 and 4.0.6:

| Filed fence | ivar | Adjudication |
|---|---|---|
| `lib/dexpace/bounded_map.rb` (4a plan:824-894) | `@h` | `Dexpace::BoundedMap` itself. The design row already said "outside `BoundedMap`'s own file"; the filed gate had **no default allowlist at all**, unlike `cause_walk`'s, so it reported its own subject |
| `gems/dexpace-core/lib/dexpace/configuration.rb` (5a plan:2645-2825) | `@overrides` | `Configuration::Builder` accumulator; keys are the embedder's `CFG` keys, and `#build` hands it to a frozen `Data` |
| same file | `@properties` | same |
| `gems/dexpace-core/lib/dexpace/instrumentation/event.rb` (5b plan:2050-2181) | `@fields` | one log event's field bag, dropped at `#emit`. The closest call of the five: `http.response.header.*` keys **are** server-influenced, so it fails the key-space clause and passes only on lifetime |
| `lib/dexpace/conformance/recording_span.rb` (8a plan:2102-2157) | `@attributes` | a per-span test double, inert after `#end` |
| `lib/dexpace/transport/async_http/clients.rb` (8c plan:1683-1756) | `@by_origin` | **TRUE POSITIVE.** An instance-lived per-origin client cache, keyed by `Endpoints.origin_for(url)`, uncapped, and nothing evicts — `#close` (8c plan:1740-1744) reads `@by_origin.values`, closes each client's pool and never clears the map. Task 16 routes it to **phase 10's inbound list** as `Clients#@by_origin`'s missing cap, and **phase 10 repairs it** — `R6`'s "a bug found in `Dexpace::BoundedMap` is filed here and fixed by phase 10" applies verbatim to another gem's map |

**The obvious generalising narrowing was written and measured and is rejected.** Filtering the
report to ivars the file also reads *by key* — `@h[k]`, `@h.fetch(k)`, `@h.key?(k)`, `@h[k] ||= v`,
each a `:CALL`/`:QCALL` on an `:IVAR` or an `:OP_ASGN1`, and all distinct from the `:ATTRASGN` of
`@h[k] = v`, with node shapes identical on 3.2.11, 3.4.10 and 4.0.6 — takes 6 offences to 3. It
drops `configuration.rb` and `recording_span.rb` and it does **not** drop `event.rb`, because
`@fields.key?(Keys::EVENT)` is a keyed read with a constant key. So it buys two allowlist entries
and costs a new statically decidable blind spot — a cache written in one file and looked up in
another through an `attr_reader` — in a gate whose whole value is being a floor. Two proxies deep
(keyed read ⇒ cache ⇒ long-lived) is worse than one honest allowlist line per file, and this phase
has already had `seam_names` wrong twice and the retired `drain_loop` carrying a false positive from exactly
this kind of cleverness. **The rule is unchanged; only the allowlist and its default are new.**

**`XCUT-14`'s drain-loop clause gains a second line rather than moving.** Task 7's
`bounded_map_drains` asserts it behaviourally and deterministically — a store pre-filled to cap + 5,
then one `set`: a drain loop ends at 8, a check-then-evict at 13. An earlier draft said the behaviour
was undecidable; that premise was false, and once it is false a shape gate that catches 1 of 3
non-conforming shapes with a false positive adds nothing — which is why `gates:drain_loop` is out of
v1 and its trigger is in `docs/first-release.md` § Post-release triggers.

**Amendment, 2026-09-13 — the three gates' remaining statically decidable misses, and the disposition
each one needs.** Every gate below already states an *undecidable* gap; what follows is the shapes it
**could** decide and does not. Measured with the review's mutation battery against this task's
`tools/ast_scan.rb` and `tools/invariant_gates.rb` **after** the 2026-09-13 corrections
(argument-carrying sends skipped, `:FCALL` and `:BLOCK_PASS` added to `cause_walk`; adapter leaf
namespaces in `seam_names`), **identically on 3.2.11, 3.3.12, 3.4.10 and 4.0.6**:

| Gate | Caught / clean as required | Decidable misses |
|---|---|---|
| `cause_walk` | 10 of 12 decidable shapes — the 7 claimed plus `cause()`, receiverless `send(:cause)`, `errors.map(&:cause)`; clean on both argument-carrying builder shapes (5b's `Event#cause(e)`) | `e.send("cause")` (String argument); `Exception.instance_method(:cause).bind_call(e)` |
| `bounded_map` | 5 of 9 decidable shapes — the 4 claimed plus `@h \|\|= {}` | `@h = Hash.new { \|h, k\| h[k] = [] }` (block form); `@@h = {}`; `NONCES = {}`; `instance_variable_set(:@h, {})` |
| `seam_names` | 5 of 7 decidable shapes — the 4 claimed plus `Dexpace::Serde::JSON::Codec`; clean on core's own `Instrumentation::Severity`, `Async::Future`, `Serde::DeserializationError` | `Object.const_get(:"Dexpace::Serde::JSON")` (dynamic Symbol); `Serde.const_get(:JSON)` (chained) |

**This task disposes of every cell in the right-hand column**, one of two ways: widen the gate for it,
or record it as accepted **inside that gate's own stated gap** — the gap sentence in the gate's source
is the artifact, not a passing comment — and then state the result on the `XCUT-9`, `XCUT-14` and
`SEAM-2` rows in Task 16. A miss that is neither widened nor written into the gap is the failure this
amendment exists to prevent: a gate whose stated gap is narrower than its real one reads as stronger
evidence than it is, which is the same defect as a gate reporting clean over a live violation. Two
measurements bound the work. Over every parseable filed `lib/` fence of phases 1–8 (**199 of 202**; 165
in core), `cause_walk` and `seam_names` report **zero** offences, so widening either costs nothing
against the tree as filed. `bounded_map` with no allowlist reports **6 hits in 5 files**, which is what
its allowlist-with-reasons exists for and is adjudicated in Step 5. And the clause `drain_loop` would
have covered already has a stronger line — Task 7's `bounded_map_drains` decides that `XCUT-14` clause
deterministically (8 against 13) — which is why the gate itself is out of v1 rather than shipped with
a gap sentence.

- [ ] **Step 1: Write the five fixtures**

```ruby
# test/fixtures/gates/reflective_cause.rb
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Bad
  def self.a(e) = e.cause
  def self.b(e) = e&.cause
  def self.c(e) = e.send(:cause)
  def self.d(e) = e.__send__(:cause)
  def self.e(e) = e.public_send(:cause)
  def self.f(e) = e.method(:cause).call
  def self.g(e, name) = e.send(name)   # undecidable: the stated gap
end
```

```ruby
# test/fixtures/gates/hash_shapes.rb
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Bad
  class Store
    def initialize(seed)
      @a = {}
      @b = Hash.new(0)
      @c = ::Hash.new
      @d = {}.compare_by_identity
      @e = build_map   # undecidable: the stated gap
      @f = seed        # undecidable: the stated gap
      @cap = 1024      # not a Hash; must NOT be reported
    end

    def build_map = {}
  end
end
```

```ruby
# test/fixtures/gates/seam_shapes.rb
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Bad
    A = Dexpace::Serde::JSON
    B = ::Dexpace::Serde::JSON
    C = Serde::JSON
    D = Object.const_get("Dexpace::Transport::NetHTTP")
    OK1 = Dexpace::Registry       # a core constant; must NOT be reported
    OK2 = Dexpace::Serde::Error   # the seam's own error type; must NOT be reported
    OK3 = Async::Future           # core's own async surface; must NOT be reported
    OK4 = Instrumentation::Severity # core's own instrumentation; must NOT be reported
  end
end
```

```ruby
# test/fixtures/gates/walks_cause.rb
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A .cause in a comment, which a grep reports and the AST does not.
module Walks
  def self.a(e) = e.cause                    # :CALL
  def self.b(e) = e&.cause                   # :QCALL
  def self.c(errors) = errors.map(&:cause)   # :BLOCK_PASS
  def self.d(logger, e) = logger.event(:warn).cause(e).emit   # carries an argument: NOT reported
  def self.s = "e.cause in a string"

  class Chained < ::StandardError
    def bare = cause                         # :VCALL
    def parens = cause()                     # :FCALL
  end
end
```

Five of its six `cause` sends must be reported; the sixth is 5b's argument-carrying builder shape.
`delegates_cause.rb` calls `Dexpace.each_cause` and names `.cause` only in prose;
The two drain fixtures are not written: `gates:drain_loop` is out of v1. The sixth fixture this task's test reads, `warns_unused.rb`, is
**Task 1's** and is not rewritten here — it names no `#cause` send and assigns no `Hash` ivar, so
every gate must report it clean, and what it proves is that the scan does not raise.

- [ ] **Step 2: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The repository-wide invariant scans. XCUT-9, XCUT-14, SEAM-2. Design R4, addenda A4-A6.
require_relative "../support/dexpace_test_case"   # FatalWarnings: a scanner that warned would fail here
require_relative "../support/gate_case"
require_relative "../../tools/invariant_gates"

class InvariantGatesTest < GateCase
  FIXTURES = File.expand_path("../fixtures/gates", __dir__)

  def fixture(name) = File.join(FIXTURES, name)

  test "cause_walk reports CALL, QCALL, VCALL, FCALL and &:cause, and not an argument-carrying send" do
    offences = InvariantGates.cause_walk([fixture("walks_cause.rb")])

    assert_equal(5, offences.size, "6 sends named cause; 5b's builder shape .cause(e) is not a walk")
    assert_includes(offences.first, "XCUT-9")
  end

  test "cause_walk reports every reflective send shape" do
    offences = InvariantGates.cause_walk([fixture("reflective_cause.rb")])

    assert_equal(6, offences.size,
                 "send/__send__/public_send/method plus . and &. -- 6 of 7 shapes; " \
                 "send(variable) is undecidable and is the gate's stated gap")
  end

  test "cause_walk is clean for a file that delegates and names cause only in prose" do
    assert_empty(InvariantGates.cause_walk([fixture("delegates_cause.rb")]))
  end

  test "cause_walk honours its allowlist so the single walk's own file passes" do
    assert_empty(InvariantGates.cause_walk([fixture("walks_cause.rb")],
                                           allowed: [fixture("walks_cause.rb")]))
  end

  test "bounded_map reports every statically decidable Hash shape" do
    offences = InvariantGates.bounded_map([fixture("hash_shapes.rb")], allowed: {})

    assert_equal(4, offences.size,
                 "literal, Hash.new, ::Hash.new and a chained call on a literal -- 4 of 6; " \
                 "a method return and a parameter are the stated gap")
    assert_includes(offences.first, "XCUT-14")
  end

  test "bounded_map is clean when the file is allowlisted with a reason" do
    allowed = { fixture("hash_shapes.rb") => "keys are frozen constants, not caller input" }

    assert_empty(InvariantGates.bounded_map([fixture("hash_shapes.rb")], allowed: allowed))
  end

  # The allowlist IS the adjudication, so a stale entry silently re-opens a hole. XCUT-14.
  test "every bounded_map allowlist entry names a live file and carries its reason" do
    refute_empty(InvariantGates::BOUNDED_MAP_ALLOWED)

    InvariantGates::BOUNDED_MAP_ALLOWED.each do |path, reason|
      assert_path_exists(path, "allowlisted path no longer exists; the entry is stale")
      refute_empty(reason.to_s.strip, "#{path} is allowlisted with no reason")
    end
  end

  test "seam_names matches an adapter's leaf namespace, not a literal spelling" do
    offences = InvariantGates.seam_names([fixture("seam_shapes.rb")])

    assert_equal(4, offences.size, "qualified, root-qualified, bare, and a const_get string")
  end

  test "seam_names permits core's own constants in the seam namespaces" do
    offences = InvariantGates.seam_names([fixture("seam_shapes.rb")]).join("\n")

    refute_includes(offences, "Dexpace::Registry")
    refute_includes(offences, "Serde::Error")
    refute_includes(offences, "Async::Future")
    refute_includes(offences, "Instrumentation::Severity")
  end

  # A scanned file's own -w diagnostics reach Warning.warn like any other parse, and THIS suite
  # loads FatalWarnings (the require at the top), so a bare parse_file reddens the gate over a file
  # it merely reads -- 8a's filed adapter.rb is a live instance (8a plan:4858). The first assertion
  # proves the fixture is not inert; the second proves AstScan.parse's $VERBOSE window holds.
  test "a file whose own -w diagnostics would fire the warnings gate is scanned without firing it" do
    assert_raises(::RuntimeError) { ::RubyVM::AbstractSyntaxTree.parse_file(fixture("warns_unused.rb")) }

    assert_empty(InvariantGates.cause_walk([fixture("warns_unused.rb")]))
  end
end
```

- [ ] **Step 3: Run to verify it fails**

Expected: FAIL — `cannot load such file -- tools/invariant_gates`.

- [ ] **Step 4: Write `tools/ast_scan.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The shared walker behind gates:cause_walk, gates:bounded_map and
# gates:seam_names.
#
# RubyVM::AbstractSyntaxTree rather than a regex, because `grep '\.cause'` matches a comment, a
# string, an `# XCUT-9` citation in a test header and the requirement ID itself. Verified on
# 3.2.11, 3.3.12, 3.4.10 and 4.0.6: present on all four. The PARSER emits no warning of its own for
# well-formed input -- but the SCANNED FILE's -w diagnostics are a different thing and do reach
# Warning.warn, which is load-bearing here; every parse below therefore goes through #parse, and
# nothing else in this file may call parse_file directly. `prism` is absent on the 3.2 floor
# (LoadError), so the AST route needs no conditional require where Prism would.
module AstScan
  # Node types a send can take. :CALL is `a.cause`, :QCALL is `a&.cause`, :VCALL is a bare `cause`
  # and :FCALL is `cause()` or a receiverless `send(:cause)`. Measured identical on 3.2.11, 3.3.12,
  # 3.4.10 and 4.0.6; a scan checking only :CALL misses every safe-navigated send.
  SEND_TYPES = %i[CALL QCALL VCALL FCALL].freeze

  # A Symbol literal is a :LIT node on Ruby 3.2 and a :SYM node on 3.4 and 4.0. **Measured on
  # 3.2.11, 3.4.10 and 4.0.6**, and it is the reverse of the usual direction -- the newer
  # interpreters diverge. A scan naming only :LIT caught 6 of 7 reflective shapes on the floor and
  # 2 of 7 on both newer rows: strictest exactly where it runs least.
  SYMBOL_TYPES = %i[LIT SYM].freeze

  # Sends that reach a method by NAME rather than by call syntax. All four bypass a scan that looks
  # only at call syntax -- measured: the cause-walk gate caught 3 of 7 realistic shapes before these
  # were added and 6 of 7 after.
  REFLECTIVE_SENDS = %i[send __send__ public_send method].freeze

  module_function

  # parse_file with the scanned file's own -w diagnostics suppressed, which is the whole reason
  # this method exists rather than five direct parse_file calls.
  #
  # A file's -w diagnostics are emitted AT PARSE TIME and routed through Warning.warn exactly as
  # they are at require time. Phase 0's shared test case prepends FatalWarnings to Warning's
  # singleton class, and test/gates/invariant_gates_test.rb requires it, so a bare parse_file
  # raises on the first such file -- which is not hypothetical: 8a's filed adapter.rb leaves `e`
  # unused in its `rescue ::StandardError => e` inside #dispatch (8a plan:4858) and emits
  # "assigned but unused variable - e" on 3.2.11, 3.3.12, 3.4.10 and 4.0.6.
  #
  # Which mechanism, measured on all four: `Warning[:deprecated] = false` does NOT reach it (the
  # warning carries no category); `$VERBOSE = false` silences the -w class but not the always-on
  # parse warnings, and `key :a is duplicated` still raised under it; `$VERBOSE = nil` silences
  # both. It is process-global, so the window is this one call and `ensure` closes it -- outside
  # it, NFR-6's gate is armed exactly as before.
  def parse(path)
    previous = $VERBOSE
    $VERBOSE = nil
    ::RubyVM::AbstractSyntaxTree.parse_file(path)
  ensure
    $VERBOSE = previous
  end

  # Every send whose method name is in `names`, whatever the call syntax, plus every reflective
  # send naming one of them as a Symbol literal.
  #
  # @return [Array[Array(String, Integer, Symbol)]] path, line, method name
  def receiver_calls(path, names)
    hits = []
    walk(parse(path)) do |node|
      if node.type == :BLOCK_PASS # `errors.map(&:cause)`: BLOCK_PASS(nil, SYM/LIT)
        passed = symbol_value(node.children[1])
        hits << [path, node.first_lineno, passed] if names.include?(passed)
        next
      end
      next unless SEND_TYPES.include?(node.type)

      called = method_name(node)
      if names.include?(called)
        # A walk sends #cause with no argument; a send carrying one is some other #cause -- 5b's
        # filed Event#cause(error) builder is the case that made this gate red over conforming code.
        hits << [path, node.first_lineno, called] if arguments(node).nil?
        next
      end
      next unless REFLECTIVE_SENDS.include?(called)

      reflected = symbol_argument(node)
      hits << [path, node.first_lineno, reflected] if names.include?(reflected)
    end
    hits
  end

  # :VCALL and :FCALL carry the name first; :CALL and :QCALL carry the receiver first.
  def method_name(node) = %i[VCALL FCALL].include?(node.type) ? node.children[0] : node.children[1]

  # The argument node, or nil when there is none (a :VCALL has no slot at all).
  def arguments(node)
    index = { CALL: 2, QCALL: 2, FCALL: 1 }[node.type]
    index.nil? ? nil : node.children[index]
  end

  # The SOLE argument of a send, when it is a Symbol literal. `nil` for anything dynamic -- a
  # deliberate false negative: `send(name)` where `name` is a variable is undecidable statically and
  # is one of the shapes the gate's stated gap covers.
  def symbol_argument(node)
    args = arguments(node)
    return nil unless args.is_a?(::RubyVM::AbstractSyntaxTree::Node) && args.type == :LIST

    values = args.children.compact
    values.size == 1 ? symbol_value(values.first) : nil
  end

  def symbol_value(node)
    return nil unless node.is_a?(::RubyVM::AbstractSyntaxTree::Node) && SYMBOL_TYPES.include?(node.type)

    value = node.children.first
    value.is_a?(::Symbol) ? value : nil
  end

  # Every instance-variable assignment whose value is a Hash by a statically decidable route: a
  # literal `{}`, a `Hash.new`/`::Hash.new` call, or a chained call on either
  # (`{}.compare_by_identity`). **Stated gap:** `@h = build_map`, `@h = OTHER.dup` and any Hash
  # arriving through a parameter are undecidable and are not reported -- the gate caught 1 of 6
  # realistic shapes before this widening and 4 of 6 after, which is a floor on the invariant rather
  # than proof of it (addendum A5 states this).
  #
  # @return [Array[Array(String, Integer, Symbol)]] path, line, ivar name
  def hash_ivar_assignments(path)
    hits = []
    walk(parse(path)) do |node|
      next unless node.type == :IASGN
      next unless hash_valued?(node.children[1])

      hits << [path, node.first_lineno, node.children[0]]
    end
    hits
  end

  def hash_valued?(node)
    return false unless node.is_a?(::RubyVM::AbstractSyntaxTree::Node)

    case node.type
    when :HASH then true
    when :CALL, :QCALL
      return true if node.children[1] == :new && const_name(node.children[0]) == :Hash

      hash_valued?(node.children[0])
    else false
    end
  end

  # XCUT-14's DRAIN-LOOP clause has no scanner here: `eviction_is_looped?` and `walk_with_loop_depth`
  # are NOT written, because gates:drain_loop is out of v1 and Task 7's `bounded_map_drains` decides
  # the same clause deterministically (8 against 13). The trigger that would bring the shape check
  # back is in docs/first-release.md, section Post-release triggers.

  # Every constant path written in the file, rendered as `Dexpace::Serde::JSON`.
  #
  # @return [Array[Array(String, Integer, String)]] path, line, constant path
  def constant_paths(path)
    hits = []
    walk(parse(path)) do |node|
      next unless %i[CONST COLON2 COLON3].include?(node.type)

      rendered = render_const(node)
      hits << [path, node.first_lineno, rendered] unless rendered.nil?
    end
    hits
  end

  # Every String literal, so a `const_get("Dexpace::Serde::JSON")` is reachable by the same suffix
  # match the constant scan uses.
  #
  # @return [Array[Array(String, Integer, String)]] path, line, literal
  def string_literals(path)
    hits = []
    walk(parse(path)) do |node|
      next unless node.type == :STR

      hits << [path, node.first_lineno, node.children.first]
    end
    hits
  end

  def walk(node, &block)
    return unless node.is_a?(::RubyVM::AbstractSyntaxTree::Node)

    block.call(node)
    node.children.each { |child| walk(child, &block) }
  end

  # `Hash` is a :CONST and `::Hash` is a :COLON3; a check naming only the first missed
  # `@h = ::Hash.new` on every interpreter (measured).
  def const_name(node)
    return nil unless node.is_a?(::RubyVM::AbstractSyntaxTree::Node)

    %i[CONST COLON3].include?(node.type) ? node.children[0] : nil
  end

  def render_const(node)
    case node.type
    when :CONST then node.children[0].to_s
    when :COLON3 then "::#{node.children[0]}"
    when :COLON2
      left = node.children[0]
      return node.children[1].to_s if left.nil?

      inner = render_const(left)
      inner.nil? ? nil : "#{inner}::#{node.children[1]}"
    end
  end
end
```

- [ ] **Step 5: Write `tools/invariant_gates.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "ast_scan"

# The repository-wide invariant scans (design R4, addenda A4-A7). Each returns a list of offence
# strings; the Rake task prints them and exits non-zero when the list is non-empty.
#
# These are Rake gates and not conformance assertions because their subject is THIS repository's
# source tree, which does not exist in a consumer's process.
module InvariantGates
  # XCUT-9: Dexpace.each_cause is the single cause walk (4b's hand-forward).
  CAUSE_WALK_ALLOWED = [
    "gems/dexpace-core/lib/dexpace/each_cause.rb" # the single walk itself
  ].freeze

  # SEAM-2 matched by the ADAPTER-OWNED LEAF NAMESPACE, anywhere in the path. Measured twice: a fixed
  # list of fully qualified names caught 0 of 4 realistic shapes, and matching any path under a seam
  # namespace (Serde, Transport, Async, Instrumentation) flagged 31 references in 15 of core's own
  # filed files -- Async::Completer, Async::Future, Instrumentation::* -- because core legitimately
  # owns constants there. So the rule names the leaf each MVP adapter gem owns (CLAUDE.md's gem
  # table). Stated gap: a later adapter gem adds its leaf here or is invisible to this gate.
  ADAPTER_NAMESPACES = [%w[Serde JSON], %w[Transport NetHTTP], %w[Transport AsyncHTTP],
                        %w[Async Thread]].freeze

  # XCUT-14: Dexpace::BoundedMap is the one bounded-keyed-map implementation (4a's hand-forward),
  # so its own file is the first exclusion and every other entry is an ADJUDICATED false positive.
  # A path => reason Hash, exactly as phase 0's require allowlist is, because an allowlist whose
  # entries carry no argument is a list of things somebody once silenced.
  #
  # Adjudicated 2026-09-13 against each predecessor's FILED FENCE, never its prose. With an empty
  # allowlist the gate reports **6 Hash ivars in 5 filed files**, identically on 3.2.11, 3.3.12,
  # 3.4.10 and 4.0.6. Four files are here; the fifth is NOT, and is this phase's finding -- see the
  # stated gap below. XCUT-14 scopes itself to a "process/instance-lived map whose key space is
  # influenced by callers or remote servers (context registries, per-nonce counters, and any
  # similar cache)" and adds that "the cap is a memory backstop and MUST NOT be relied on as the
  # primary cleanup mechanism". What every entry here has in common is that clause: the map's
  # primary cleanup mechanism is its owner being dropped after ONE operation, so a cap would never
  # be the backstop. That property is a lifetime, and a lifetime is not decidable from one file --
  # which is why the allowlist is the mechanism and not a cleverer scan.
  BOUNDED_MAP_ALLOWED = {
    "gems/dexpace-core/lib/dexpace/bounded_map.rb" =>
      "@h IS Dexpace::BoundedMap's own store -- the single implementation this gate exists to " \
      "keep single (4a plan:824-894, the ivar at 845)",
    "gems/dexpace-core/lib/dexpace/configuration.rb" =>
      "@overrides and @properties are Configuration::Builder accumulators discarded at #build, " \
      "and the built Configuration is a frozen Data; the keys are the embedder's own CFG keys, " \
      "not caller or server input (5a plan:2645-2825, the ivars at 2668 and 2672)",
    "gems/dexpace-core/lib/dexpace/instrumentation/event.rb" =>
      "@fields is ONE log event's field bag, allocated per call and dropped at #emit; its " \
      "lifetime is a single operation, so a cap could never be the memory backstop XCUT-14 " \
      "describes (5b plan:2050-2181, the ivar at 2090)",
    "gems/dexpace-conformance/lib/dexpace/conformance/recording_span.rb" =>
      "@attributes is one RecordingSpan double's record, inert after #end and dropped with the " \
      "span (8a plan:2102-2157, the ivar at 2115)"
  }.freeze

  # **Stated gap, because a gate whose blind spots are unwritten is a gate nobody can audit.**
  # Undecidable statically and therefore NOT reported by any scan below: `send(name)` where `name`
  # is a variable; `@h = build_map` and any Hash arriving through a parameter or a constant `dup`;
  # and a constant reached through `const_get(dynamic)`. Each gate is a floor on its invariant
  # rather than proof of it, and the addendum for each states its measured catch rate. The
  # statically DECIDABLE shapes each gate still misses are measured in this task's gate-miss
  # dispositions amendment, and each is widened for or accepted in the gap above.
  #
  # **bounded_map's sixth hit is NOT allowlisted and is the audit's one finding -- Task 16 routes it
  # to phase 10's inbound list as Clients#@by_origin's missing cap.**
  # gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/clients.rb:32's @by_origin is
  # an instance-lived per-origin Async::HTTP::Client cache with no cap and no eviction: the key is
  # Endpoints.origin_for(url), so a caller's URLs and a server's redirect Location headers both add
  # keys, and nothing removes one -- #close (8c plan:1740-1744) clears no key. That is XCUT-14's
  # "any similar cache" exactly, and the same sub-phase bounded its OTHER caller-keyed map at 64
  # for TRANSPORT-13 (8c plan:1385, 1438-1445), so the omission is a miss and not a decision.
  #
  # **One further measured blind spot, from the same adjudication: a Hash held inside a value
  # object rather than directly on an ivar.** 8c's DropPolicy keeps its bounded per-name set as
  # `@snapshot = Snapshot.new(seen: {}.freeze)` (8c plan:1715-1745); the Hash literal is an
  # argument, not the assigned value, so hash_ivar_assignments does not see it. That file is
  # conforming, so it costs nothing here -- but an UNBOUNDED map written the same way would be
  # invisible, and that is a gap in the floor rather than in this file.
  module_function

  def cause_walk(files, allowed: CAUSE_WALK_ALLOWED)
    offences(files, allowed) do |path|
      AstScan.receiver_calls(path, [:cause]).map do |(_, line, _)|
        "#{path}:#{line}: walks #cause outside Dexpace.each_cause (XCUT-9)"
      end
    end
  end

  # A Hash assigned to an instance variable is the shape a caller- or server-keyed map takes. The
  # allowlist is a Hash of path => reason, so every permitted one carries the argument for why it is
  # not caller-keyed -- exactly as phase 0's require allowlist does.
  def bounded_map(files, allowed: BOUNDED_MAP_ALLOWED)
    offences(files, allowed.keys) do |path|
      AstScan.hash_ivar_assignments(path).map do |(_, line, ivar)|
        "#{path}:#{line}: #{ivar} is a Hash on an instance; only Dexpace::BoundedMap may hold a " \
          "caller- or server-keyed map (XCUT-14)"
      end
    end
  end

  # No `drain_loop` here: the gate is out of v1 (see this task's opening note), and XCUT-14's
  # drain-to-cap clause is asserted behaviourally by Task 7's `bounded_map_drains`.

  def seam_names(files, namespaces: ADAPTER_NAMESPACES)
    offences(files, []) do |path|
      candidates = AstScan.constant_paths(path) + AstScan.string_literals(path)
      candidates.filter_map do |(_, line, rendered)|
        next unless concrete_seam?(rendered.to_s, namespaces)

        "#{path}:#{line}: core names the concrete seam implementation #{rendered} (SEAM-2)"
      end
    end
  end

  # `Dexpace::Serde::JSON`, `::Dexpace::Serde::JSON`, bare `Serde::JSON` and
  # `Dexpace::Serde::JSON::Codec` all contain an adapter's leaf pair as consecutive segments;
  # `Dexpace::Serde::Error`, `Dexpace::Async::Future` and `Instrumentation::Severity` contain none.
  def concrete_seam?(rendered, namespaces)
    rendered.delete_prefix("::").split("::").each_cons(2).any? { |pair| namespaces.include?(pair) }
  end

  def offences(files, allowed)
    (files - allowed).flat_map { |path| yield(path) }
  end
end
```

- [ ] **Step 6: Wire three Rake tasks, append them to `DEFAULT_GATES` in the root `Rakefile`, and edit `ci.yml`**

`gates:cause_walk` and `gates:bounded_map` run over `Dir["gems/*/lib/**/*.rb"]`; `gates:seam_names` over
`Dir["gems/dexpace-core/lib/**/*.rb"]` only. **The three names are appended to `DEFAULT_GATES` in the
root `Rakefile`**, which is where that array lives — `tasks/gates.rake` is `load`ed before it exists
and it is frozen after, so a task defined there and nowhere else would be off the default build and
therefore advisory, which is the one thing `NFR-17` forbids. **A fourth gate is touched and is not new: `gates:serde_boundary`,
which 7b wired into the default task (7b plan:1758)** — phase 9 adds one assertion to it, that its `PENDING` list is empty, which
is the clause 7b handed forward and could not assert while phase 7 was still running — plus a fixture
with one `PENDING` entry, so the addition has been seen to fail. All four are **blocking**: a
non-blocking addition while dispositioning `NFR-17` would be self-falsifying. The **three new** ones
go in `DEFAULT_GATES` and the `gates` CI job, which is what keeps phase 0's `ci_workflow_test.rb`
(phase 0 plan:3610) green; `gates:serde_boundary` is already in both.

- [ ] **Step 7: Run the gate test on the four installed interpreters, then the whole set**

```bash
for v in 3.2.11 3.3.12 3.4.10 4.0.6; do mise exec ruby@$v -- ruby -w test/gates/invariant_gates_test.rb; done
bundle exec rake
```

Expected: **11 runs, 42 assertions, 0 failures** on each — measured 2026-09-13 on 3.2.11, 3.3.12,
3.4.10 and 4.0.6, the fences run straight out of this document with nothing adapted — and
`gates:cause_walk` and `gates:seam_names` green over the real tree, with
`gates:bounded_map` reporting **exactly one** offence, `async_http/clients.rb`'s `@by_origin`, which
Task 16 routes to phase 10's inbound list as `Clients#@by_origin`'s missing cap. Anything else from
`bounded_map` is either a new file the adjudication
never saw — adjudicate it and add an entry with its reason — or the sixth hit having been repaired,
in which case the gate set is green and phase 10's inbound entry for that cache closes. **A fifth
allowlist entry is a decision, not
a chore**: design open question 2 says that past a dozen entries the gate is telling us the
invariant is not held.

- [ ] **Step 8: Stage the change**

**No commit.**

```bash
git add -- tools/ast_scan.rb tools/invariant_gates.rb tasks/gates.rake \
        .github/workflows/ci.yml test/fixtures/gates/ test/gates/invariant_gates_test.rb
```

---

## Task 14: `APPENDIX_B.md` — the 61-row coverage map

**Files:**
- Create: `gems/dexpace-conformance/APPENDIX_B.md`
- Create: `tools/appendix_b.rb` — the generator for the suite-backed rows
- Test: `test/gates/appendix_b_test.rb`

**Interfaces:**
- Consumes: `Aggregate.by_requirement_id(suites)` (Task 12),
  `docs/product-spec/appendix-b-conformance-test-checklist.md`
- Produces: a committed 61-row table, and three checks over it

The map's columns: section, item number, the requirement IDs the item names, the covering suite or
test file, and the status (`suite`, `by reference`, `restated per §9.3`, `scoped out`, `waived`,
`vacuous`). Sections and counts, parsed from the specification rather than typed: `B.1` 10, `B.2` 6,
`B.3` 7, `B.4` 8, `B.5` 6, `B.6` 5, `B.7` 6, `B.8` 6, `B.9` 7 — **61**.

**Correction, 2026-09-13 — the numbers the first draft dropped two checks on were wrong, and the
stronger check is decidable.** Measured against the real appendix B with the 19-prefix regex below:
the 61 items name **276 distinct requirement IDs, no ID repeated across items**; the **maximum in any
one item is 12** (`B.2`'s item 11), 59 of 61 name ten or fewer, and **`B.5`'s six items name 5, 3, 8,
7, 7 and 8** — not "around twenty each", which was the stated reason for dropping the header check
and is false. So the retained check is not "every row names at least one ID": it is **per-row ID-set
equality** — each row's ID column must equal the set parsed from that item's own text, which is what
the column already claims to be. That is decidable, it is strictly stronger, and it makes the dropped
distinct-ID coverage check hold **by construction** (the union of 61 equal sets is the 276). What
stays dropped is the ten-line-header check on the *referenced* file, now on the honest ground that a
by-reference row's evidence lives in another phase's test file whose header this phase does not own —
and `P9-7`'s caveat is untouched: a by-reference row still proves an ID is claimed and a file exists,
never that the behaviour is tested.

**The ID regex is restricted to the 19 known prefixes.** A bare `[A-Z]+-\d+` matches `ISO-8601`,
which appears in `B.3`'s real text, and `RFC-3986`-shaped tokens elsewhere; the prefix list is
`CLAUDE.md`'s own, in appendix-C order.

**Three things the checks establish, and the one they cannot** (design `R7`, `P9-7`):

- **Established:** the table has exactly 61 rows, and each section's count matches the count parsed
  from the specification's own appendix B. A drifting checklist is caught the day it drifts.
- **Established:** every row's ID column **equals** the ID set parsed from that item's own text
  (276 distinct IDs over the 61 items, max 12 in one item), so no row can be wrong about which
  requirements its item covers, and every ID appendix B names is in some row by construction.
- **Established:** every row's evidence path exists on disk.
- **Not established:** that a referenced test actually *asserts* the described behaviour. Nothing
  mechanical can, short of re-implementing the assertion. The map's preamble says so, and so does
  `Aggregate::PREAMBLE`.

**Amendment, 2026-09-13 — the preamble states what the map leaves unproven, and names the condition
that would close it.** Dropping the two undecidable checks is right, and it leaves a real gap; a gap
that is merely *absent* from a document reads as a gap nobody found. So `APPENDIX_B.md` opens with a
preamble saying both halves in its own voice, and **that wording is this task's deliverable**, not a
reviewer's later addition:

- **What the three checks establish.** The table has exactly 61 rows; each section's count matches the
  count parsed from the specification's own appendix B; every row's ID column equals the set parsed
  from that item's own text — **276 distinct IDs, no ID in two items, at most 12 in one** — and every
  row names an evidence path that exists on disk.
- **What they do not: a referenced test's header is not checked to declare the IDs its row claims.**
  A `by reference` row's evidence is a test file in a gem this phase does not own, and nothing makes
  a test file announce which appendix-B item it covers. So such a row establishes that an ID is
  claimed and that a file exists, **never** that the referenced test asserts the described behaviour
  (design `P9-7`).
- **The closing condition, named rather than left open.** The gap shrinks when the by-reference rows
  do, and the event that makes shrinking them worth its cost is the one `docs/first-release.md` §
  Post-release triggers already records for lifting `B.1`, `B.2` and `B.5`: **a second implementation**.
  Until that trigger fires, the only other route is a per-section ID reconciliation done by hand once
  and then checked — a piece of work rather than a line, and phase 9 does not take it. The preamble
  says so, so that a later reader knows the gap was priced and deferred, not overlooked.

`Aggregate::PREAMBLE` (Task 12) makes the same statement about a green suite run; a reader who meets
only one of the two documents must still be told.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The appendix-B coverage map. Design R7, P9-7, P9-8; the map's preamble states what these checks
# do not reach.
require_relative "../support/gate_case"
require_relative "../../tools/appendix_b"

class AppendixBTest < GateCase
  SPEC = "docs/product-spec/appendix-b-conformance-test-checklist.md"
  MAP = "gems/dexpace-conformance/APPENDIX_B.md"

  test "the map carries exactly one row per checklist item" do
    assert_equal(61, AppendixB.spec_item_count(SPEC))
    assert_equal(AppendixB.spec_item_count(SPEC), AppendixB.rows(MAP).size)
  end

  test "the per-section counts match the specification's own" do
    assert_equal({ "B.1" => 10, "B.2" => 6, "B.3" => 7, "B.4" => 8, "B.5" => 6,
                   "B.6" => 5, "B.7" => 6, "B.8" => 6, "B.9" => 7 },
                 AppendixB.spec_counts_by_section(SPEC))
    assert_equal(AppendixB.spec_counts_by_section(SPEC), AppendixB.counts_by_section(MAP))
  end

  test "every row names at least one requirement id from the nineteen known prefixes" do
    unlabelled = AppendixB.rows(MAP).reject { |row| row[:ids].any? }

    assert_empty(unlabelled)
  end

  test "the id scanner does not mistake ISO-8601 for a requirement id" do
    assert_empty(AppendixB.ids_in("ISO-8601 dates round-trip and RFC-3986 encoding applies"))
    assert_equal(%w[SERDE-24], AppendixB.ids_in("ISO-8601 dates round-trip (SERDE-24)"))
  end

  test "every row's evidence path exists on disk" do
    missing = AppendixB.rows(MAP).map { |row| row[:evidence] }
                       .reject { |path| path.nil? || File.exist?(path) }

    assert_empty(missing)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `AppendixB` does not exist and `APPENDIX_B.md` has not been written.

- [ ] **Step 3: Write `tools/appendix_b.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Two Markdown files compared: the specification's appendix B, and the coverage map beside the
# conformance gem. Plain text operations -- no AST, no gem.
module AppendixB
  # CLAUDE.md's nineteen prefixes, in appendix-C order. A bare /[A-Z]+-\d+/ matches ISO-8601, which
  # appears in B.3's real text, and RFC-3986-shaped tokens elsewhere.
  PREFIXES = %w[SEAM HTTP IO BODY CTX PIPE RECOV RETRY REDIR AUTH PAGE SSE SERDE OBS CFG
                TRANSPORT ASYNC XCUT NFR].freeze
  ID = /\b(?:#{PREFIXES.join("|")})-\d+\b/

  module_function

  def ids_in(text) = text.scan(ID).uniq

  def spec_item_count(path) = ::File.readlines(path).count { |line| line.start_with?("- [ ]") }

  def spec_counts_by_section(path)
    section = nil
    ::File.readlines(path).each_with_object({}) do |line, counts|
      if (match = /^### (B\.\d)/.match(line))
        section = match[1]
        counts[section] = 0
      elsif line.start_with?("- [ ]") && section
        counts[section] += 1
      end
    end
  end

  # The map's own table: | section | item | ids | evidence | status |
  def rows(path)
    ::File.readlines(path).filter_map do |line|
      next unless line.start_with?("| B.")

      cells = line.split("|").map(&:strip).reject(&:empty?)
      next if cells.size < 5

      { section: cells[0], item: cells[1], ids: ids_in(cells[2]),
        evidence: cells[3].delete("`").then { |e| e == "--" ? nil : e }, status: cells[4] }
    end
  end

  def counts_by_section(path)
    rows(path).each_with_object({}) { |row, counts| counts[row[:section]] = counts.fetch(row[:section], 0) + 1 }
  end

  HEADER = <<~MARKDOWN
    # Appendix B coverage map

    Generated by `tools/appendix_b.rb --generate`. `suite` rows are regenerated from each suite's declared
    assertions; every other row is hand-written and carried over. A `by reference` row proves an ID is
    claimed and a file exists, not that the behaviour is asserted (design P9-7; see the preamble's
    "what these checks do not establish").

    | Section | Item | IDs | Evidence | Status |
    |---|---|---|---|---|
  MARKDOWN

  # One row per specification item, in the specification's order. An item naming an ID some suite
  # declares an assertion for is GENERATED from Aggregate.by_requirement_id (Task 12): status `suite`,
  # evidence that suite's file. Any other item keeps its hand-written row from the existing map, and
  # an item with neither is emitted `unmapped` with evidence `unmapped` -- not a path, so the evidence
  # check fails and names it until someone writes the row.
  def generate(spec_path, map_path, suites)
    covered = ::Dexpace::Conformance::Aggregate.by_requirement_id(suites)
    hand = hand_written_lines(map_path)
    body = spec_items(spec_path).map do |(section, item, text)|
      ids = ids_in(text)
      suite = ids.flat_map { |id| covered.fetch(id, []) }.map { |row| row[:suite] }.first
      next "| #{section} | #{item} | #{ids.join(", ")} | `#{suite_file(suite)}` | suite |" if suite

      hand.fetch([section, item.to_s]) { "| #{section} | #{item} | #{ids.join(", ")} | unmapped | unmapped |" }
    end
    "#{HEADER}#{body.join("\n")}\n"
  end

  # [[section, 1-based item number, item line]] in the specification's order.
  def spec_items(path)
    section = nil
    ::File.readlines(path).each_with_object([]) do |line, items|
      if (match = /^### (B\.\d)/.match(line))
        section = match[1]
      elsif line.start_with?("- [ ]") && section
        items << [section, items.count { |(s, _, _)| s == section } + 1, line]
      end
    end
  end

  # The map's hand-written rows, verbatim, keyed by [section, item]. Reads the file BEFORE the caller
  # writes it, which is why the CLI takes the map's path rather than redirecting stdout into it.
  def hand_written_lines(path)
    return {} unless ::File.exist?(path)

    ::File.readlines(path, chomp: true).each_with_object({}) do |line, kept|
      cells = line.split("|").map(&:strip).reject(&:empty?)
      next unless line.start_with?("| B.") && cells.size >= 5
      next if %w[suite unmapped].include?(cells[4])

      kept[[cells[0], cells[1]]] = line
    end
  end

  # Dexpace::Conformance::InvariantSuite -> gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite.rb
  def suite_file(name)
    leaf = name.split("::").last.gsub(/(?<!^)([A-Z])/, '_\1').downcase
    "gems/dexpace-conformance/lib/dexpace/conformance/#{leaf}.rb"
  end
end

if $PROGRAM_NAME == __FILE__ && ARGV.first == "--generate"
  require "dexpace/conformance"
  suites = %i[InvariantSuite PackagingSuite CodecSuite ExecutorSuite TransportSuite].filter_map do |name|
    Dexpace::Conformance.const_get(name) if Dexpace::Conformance.const_defined?(name)
  end
  map = ARGV.fetch(1)
  File.write(map, AppendixB.generate("docs/product-spec/appendix-b-conformance-test-checklist.md", map, suites))
end
```

- [ ] **Step 4: Write `APPENDIX_B.md`, generating the suite-backed rows and hand-writing the rest**

```bash
ruby -Igems/dexpace-conformance/lib -Igems/dexpace-core/lib \
  tools/appendix_b.rb --generate gems/dexpace-conformance/APPENDIX_B.md
```

The generator takes the map's **path** rather than writing to stdout: a shell redirect truncates the
file before the generator reads the hand-written rows it carries over. Every item no suite covers
comes out `unmapped` until its row is written by hand.

Then hand-write the `by reference` rows, replacing each `unmapped` one — one per `B.1`, `B.2` and `B.5` item, plus `B.3`'s
`Tristate`/coercion items and `B.4`'s non-lifted items — naming the owning phase's test file. The
`B.1`/`B.2`/`B.5` rows are the disposition deviation **`P9-1`** records (design ledger, consolidated
into design §10 and audited by `docs/deviations.md`): dispositioned **by reference** to the owning
phase's suite rather than lifted, because each has one implementation and §9.3's case for the gem is
portability across many; the `B.1`/`B.2`/`B.5` entry in `docs/first-release.md` § Post-release triggers
names the event — a second implementation — that would lift them. Do
**not** hand-edit a generated row: re-run the generator. `B.3`'s reified-helper item carries
`restated per §9.3` (§9.3 restates `SERDE-7` as "the ergonomic decode helper routes through a
witness or combinator"); `SEAM-21`, `SEAM-18` and `ASYNC-15`'s clause (c) carry `scoped out` with
their reasons.

**The by-reference residue is ~29 of 61, not 22** — `B.1`'s 10, `B.2`'s 6, `B.5`'s 6, plus `B.3`'s
`Tristate`/coercion items and `B.4`'s items beyond the two §9.3 names by hand. The map is what makes
the number checkable rather than estimated, and it is counted section by section there.

- [ ] **Step 5: Run the test, then the whole gate set**

Expected: 5 runs, PASS, with the map at exactly 61 rows and the section counts 10/6/7/8/6/5/6/6/7.
Before the hand-written rows exist, the evidence test fails and names every `unmapped` row — that is
the generator's placeholder doing its job, not a defect.

- [ ] **Step 6: Stage the change**

**No commit.**

```bash
git add -- gems/dexpace-conformance/APPENDIX_B.md tools/appendix_b.rb test/gates/appendix_b_test.rb
```

## Task 15: The `NFR` disposition pass — run every gate, record every answer

**Files:**
- Create: `docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance-checklist.md` — the `NFR` half
- Modify: `docs/first-release.md` as findings require, plus the plan of the phase that owns each
  finding or the roadmap's phase-10 inbound list — **a finding is routed to its owner, not registered**

**Interfaces:**
- Consumes: every gate phase 0 built, plus Task 9's `PackagingSuite` and Task 13's three new gates
- Produces: seventeen dispositioned rows

**This is where phase 9 stops building and starts measuring.** No code is written in this task except a finding's citation.

- [ ] **Step 1: Run the whole gate set and capture each result**

```bash
bundle exec rake 2>&1 | tee tmp/phase9-gates.log
```

Then the matrix: **four rows, 3.2 / 3.3 / 3.4 / 4.0**, which is what `NFR-10` and `NFR-17` are
about. All four are installed locally — 3.2.11, 3.3.12, 3.4.10 and 4.0.6; there is no
`.ruby-version` file here — so a local run covers the rows CI does. Record which was run.

```bash
for v in 3.2.11 3.3.12 3.4.10 4.0.6; do echo "== $v =="; mise exec ruby@$v -- bundle exec rake test:gems; done
```

Record, per gate: exit status, the number it produced where it produces one (SimpleCov's aggregate for `NFR-5`), and the finding where it produces one.

- [ ] **Step 2: Run `PackagingSuite` against genuinely built `.gem` files, not source gemspecs**

```bash
for g in gems/*; do (cd "$g" && gem build ./*.gemspec -o "$OLDPWD/tmp/$(basename "$g").gem"); done
gem install --local --no-document tmp/*.gem
ruby -e 'require "dexpace"; require "dexpace/transport/net_http"; require "dexpace/transport/async_http"
         require "dexpace/serde/json"; require "dexpace/async/thread"; require "dexpace/conformance"
         puts Dexpace::Conformance::PackagingSuite.run(
           adapters: %w[dexpace-transport-net_http dexpace-transport-async_http
                        dexpace-serde-json dexpace-async-thread dexpace-conformance],
           constants: { "dexpace-core" => "Dexpace",
                        "dexpace-transport-net_http" => "Dexpace::Transport::NetHTTP",
                        "dexpace-transport-async_http" => "Dexpace::Transport::AsyncHTTP",
                        "dexpace-serde-json" => "Dexpace::Serde::JSON",
                        "dexpace-async-thread" => "Dexpace::Async::Thread",
                        "dexpace-conformance" => "Dexpace::Conformance" })'
```

**`constants:` is `CLAUDE.md`'s gem table, passed explicitly and never derived from the gem name.**
`PackagingCase`'s derived default maps `dexpace-core` to `Dexpace::Core`, which does not exist, and
`net_http` → `NetHTTP` is not a mechanical casing; with no map every gem's `NFR-15` would report
`:vacuous`. A `:vacuous` `NFR-15` in this output therefore means a require above is missing, not
that a version is right. On the 3.2 row, drop `dexpace-transport-async_http` from both lists and its
require — the per-gem Ruby floor 8c plan, Task 3 gates.

`P9-2`'s whole argument is that a source gemspec and a published one can differ, so reading the source here would falsify the phase's own deviation.

- [ ] **Step 3: Write one checklist row per `NFR`, with the evidence named**

Each row: the ID, the legend mark (✅ / 🚫 / ⏳ / N/A), the disposition artifact from the design's `R2` table, and either the observed number or the finding. Six marks are **predicted ⏳** and they divide two ways — four pending a finding another task or phase owns (`NFR-7` / phase 0 plan, Task 3's reviewed `.rubocop.yml` baseline; `NFR-10` / 8c plan, Task 3's per-gem Ruby floor gate edit; `NFR-13` / phase 10's inbound list, SPDX coverage for `sig/**/*.rbs`; `NFR-17` / phase 0 plan, Task 2's `minitest` `~> 5.25` pin) and two pending a release rather than a finding (`NFR-4`, no `v*` tag to diff against, `P0-8`'s pre-release branch; `NFR-16`, no release path — `docs/first-release.md` § Release path). **A prediction is not an observation.** If a gate passes where the design predicted ⏳, mark it ✅ **and say the design's prediction was wrong**, naming which. If it fails where ✅ was predicted, the same in the other direction.

- [ ] **Step 4: File what the pass found, and repair nothing**

Per design `R6`: `:failed` stays `:failed`; the row is ⏳ or 🚫 with the reason; the finding is **routed to its owner** — a numbered task in the owning phase's plan, or phase 10's inbound list in the roadmap when the repair belongs to a phase already planned; a MUST additionally gains a `docs/first-release.md` blocker. **Do not lower `--fail-level`, add an `Exclude:`, relax a metric cop or make a gate report-only** — `NFR-17`'s entire content is that no gate is advisory, and relaxing one while dispositioning it falsifies the evidence.

**An un-waived `:vacuous` on a MUST-level ID is a report blocker, not a pass.** The mechanism is
**Task 12a** — `Levels::OF` generated from appendix C, `Report#blocking_vacuities`, `#passed?` false
while that list is non-empty, and the "MUST-level vacuities (report blockers)" section on every
render — and **the MUST-level vacuity blocker lands there, before this run**, not after it: **do not
start this step until Task 12a is green**, because this run's verdicts are not trustworthy without it
(the condition the blocker was postponed under). `R3`'s absent-artifact case makes a missing artifact `:vacuous` rather
than `:failed`, because at execution time "not built yet" and "built wrong" are different findings
and phase 10 acts on the difference. What stops `:vacuous` becoming a way to pass by not building:
the aggregate report lists every un-waived vacuity against a MUST **separately** under its own
heading, that list is a **phase-9 report blocker**, and each entry earns a `docs/first-release.md`
line. A vacuity a driver names in `accepted_vacuous:` with a design §12/§10.5 citation is rendered
apart as design-sanctioned and does not block; a SHOULD-level vacuity is recorded and does not block.

- [ ] **Step 5: Stage the change**

**No commit.** `CLAUDE.md`: "Agents do not commit, push, or touch the remote unless the user asks for that specific action in that message." Every one of the twenty-one preceding plans in this repository has zero commit steps; the reviewer commits.

```bash
git add -- docs/work/mvp/phase9/ \
        docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md \
        docs/first-release.md
```

---

## Task 16: The `XCUT` audit pass — probe, run, record

**Files:**
- Modify: the phase-9 checklist — the `XCUT` half
- Modify: `docs/deviations.md` and `docs/first-release.md` as findings require, plus the plan of the
  phase that owns each finding or the roadmap's phase-10 inbound list — **a finding is routed to its
  owner, not registered**

**Interfaces:**
- Consumes: `InvariantSuite` (28 assertions), `TransportSuite` (8a, two drivers), `CodecSuite`, `ExecutorSuite` (seven assertions, `ASYNC-3` among them), `Levels` and the MUST-level vacuity section (Task 12a), the three repository gates
- Produces: twenty-four dispositioned rows, one aggregate report, and the three gates' offence lists

- [ ] **Step 1: Run every existence probe and record the result**

Each probe is `InvariantCase#probe!`'s subject, and a miss is `:vacuous` with its reason — never
`:failed` and never `:error`. A MUST-level `:vacuous` is a report blocker — Task 12a's
`Report#blocking_vacuities` and its "MUST-level vacuities (report blockers)" section; Task 15, step 4.

```bash
ruby -Igems/dexpace-core/lib -e 'require "dexpace"
  %i[Cancellation CancelledError Closeable Registry ProtocolError TransportError Retryability
     HeaderSyntax BoundedMap Redactor UUID].each do |name|
    puts format("%-20s %s", name, Dexpace.const_defined?(name))
  end
  puts format("%-20s %s", "each_cause", Dexpace.respond_to?(:each_cause))'
```

A `false` is a finding, not a blocker: record the divergence, name the phase document that promised the constant, and follow `R3`'s three cases — renamed (correct the row and say so), reshaped (assert the property against what arrived and file against the design document), absent (⏳/🚫, file, hand to phase 10).

- [ ] **Step 2: Run the aggregate over every suite**

```bash
ruby -e 'require "dexpace/conformance/aggregate"
  # …run each suite with its real subject, then:
  puts Dexpace::Conformance::Aggregate.render(Dexpace::Conformance::Aggregate.run(reports))'
```

Two arguments of the first-party run are load-bearing and are stated here so the run is not
assembled from memory *(added 2026-09-13)*. **`InvariantSuite.run(core: ::Dexpace, transport: ->
{ Dexpace::Transport::NetHTTP.build }, …)`** — the `transport:` factory is 8a's adapter, so `XCUT-18`'s
call-site assertion (Task 7, the wire-boundary re-validation's phase-9 clause) runs against a real dispatch path; left out,
that assertion is `:vacuous` on a **MUST** and Task 12a's rule blocks the report, which is the rule
doing its job and not a reason to omit the section. **`Aggregate.run(reports, accepted_vacuous: …)`**
carries only the acceptances the drivers already name (Task 12a, Step 5) plus any the run itself
justifies under §12/§10.5 with a citation; the "accepted MUST-level vacuities (design-sanctioned)"
section is then the run's own list of what it did not prove, printed beside the blockers it found.

- [ ] **Step 3: Run the three repository gates and file what they report**

```bash
bundle exec rake gates:cause_walk gates:bounded_map gates:seam_names
```

`cause_walk` and `seam_names` were clean over every filed `lib/` fence of phases 0–8
and are expected clean here. **`gates:bounded_map` is expected to report exactly one offence** —
`gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/clients.rb:32`'s `@by_origin`,
adjudicated in Task 13 as the one true positive of the six. It is `XCUT-14`'s `:failed`, not the
gate's: an uncapped instance-lived cache keyed by an origin caller URLs and server redirect
`Location`s both choose, never evicted — `#close` (8c plan:1740-1744) clears no key. Record it as
an entry on **phase 10's inbound list** — `Clients#@by_origin`'s missing cap — mark `XCUT-14`'s row ⏳
with the reason, and — because `XCUT-14` is a **MUST** — add the
`docs/first-release.md` blocker line design `R6` requires, then hand the repair to **phase 10**.
**Do not add a cap here.** `R6`'s exception covers a defect inside `dexpace-conformance` and nothing
else, and this is `dexpace-transport-async_http`'s; `8c` is the sub-phase whose fence introduced it
and has already run by the time this task does.

An offence from any *other* file is a new adjudication, not a new allowlist line written to get
green: decide it against that file's filed fence exactly as Task 13 decided the six, and write the
reason if it is a false positive.

- [ ] **Step 4: Record the two dispositions a reader checks first**

Per design `R5`: **`ASYNC-3`** is asserted so it genuinely fails, waived by requirement ID in the first-party build, and printed as `waived (would fail): ASYNC-3` — never `passed`, never `vacuous`. **`ASYNC-4`** is `:vacuous` and is added to **no unsatisfied-MUST entry**; that entry (`docs/first-release.md` § What v1 ships without › Unsatisfied MUSTs) covers `ASYNC-3` and `PIPE-33`'s interrupt clause and stays so. Neither ID gets a phase-9 checklist row — both are phase 8's.

- [ ] **Step 5: Record the vacuities and postponed items other phases handed forward**

Four, from 4c and 7c, recorded in the aggregate report's preamble and **not** as phase-9 checklist rows: `PIPE-33` (an unsatisfied MUST, §10.5), `PIPE-36` (declined for v1, `docs/first-release.md` § What v1 ships without), `PIPE-39` (`Pipeline.standard`, phase 6b's Task 13a), `PIPE-32`'s vacuity until `Pipeline.standard` lands, `PAGE-35`'s vacuity, and **`PAGE-15`'s wrapping clause (`P7-1`), which §12's `PAGE` row does not record** — that last one goes to `docs/deviations.md`'s "Deviations found outside a phase" holding area for phase 10 to fold in.

- [ ] **Step 6: Write one checklist row per `XCUT` ID, with the audit subject named**

24 rows, each naming the artifact audited, the assertion that audited it, and the mark.

- [ ] **Step 7: Stage the change**

**No commit.** `CLAUDE.md`: "Agents do not commit, push, or touch the remote unless the user asks for that specific action in that message." Every one of the twenty-one preceding plans in this repository has zero commit steps; the reviewer commits.

```bash
git add -- docs/work/mvp/phase9/ \
        docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md \
        docs/deviations.md \
        docs/first-release.md
```

---

## Task 17: Regenerate the API surface, run the full gate set, close the phase

**Files:**
- Modify: `gems/dexpace-conformance/sig/**/*.rbs` — regenerated baseline
- Modify: the runtime surface manifest
- Modify: this phase's checklist and the roadmap's phase status note — the marks Step 3 performs for
  the work earlier phases postponed here and for the MUST-level vacuity blocker
- Modify: `docs/knowledge/notes/` — the three notes, four entries (the new file carries two)
- Modify: `CLAUDE.md`, `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`

**Interfaces:**
- Consumes: everything above
- Produces: a green `bundle exec rake` on every matrix row, or a recorded reason it is not

**Both baselines are regenerated, not one.** `Data.define`'s generated readers on `Assertion` and `Result` are public API `rbs validate` cannot see, and phase 0 plan, Task 14's `Data`-reader snapshot decision rests on the measurement that the runtime snapshot does not see them either for this repository's `class X < Data.define(...)` convention — so the two catch different things and neither alone covers `Report#to_h`, `Aggregate::PREAMBLE` and thirteen new constants.

- [ ] **Step 1: Regenerate both**

```bash
bundle exec rake gates:surface_snapshot -- --regenerate
bundle exec rbs validate && bundle exec steep check
```

- [ ] **Step 2: Run the full gate set on every Ruby in the matrix**

```bash
bundle exec rake
for v in 3.2.11 3.3.12 3.4.10 4.0.6; do echo "== $v =="; mise exec ruby@$v -- bundle exec rake test:gems; done
```

Expected: green, **with the 3.2 row excluding `dexpace-transport-async_http`** (8c plan, Task 3's per-gem Ruby floor gate edit; `P8-36`:
`async-http` 0.104.0 declares `>= 3.3`) and with what phase 0 plan, Task 2's `minitest` `~> 5.25` pin produces
on the 4.0 row. Both exclusions are recorded, not silent. The same four rows run locally: 3.2.11,
3.3.12, 3.4.10 and 4.0.6.

**One expected exception, and it is the whole point of the gate.** Unless `Clients#@by_origin` has
acquired a cap since `8c` filed it, `gates:bounded_map` is red, `bundle exec rake` is red, and
**that is the correct end state for phase 9** — `R6` makes the repair phase 10's, and `NFR-17`'s
content is that no gate is advisory. **The fix is not an allowlist entry.** Adding one would leave a
gate reporting clean over a live `XCUT-14` violation, which is the failure mode phase 0's
failing-fixture discipline and `notes/cross-cutting-invariants.md` both exist to prevent. Record the
red run, its one offence, its entry on phase 10's inbound list and the `docs/first-release.md` blocker, and say in the phase's
closing note that the gate set is green **except** that row. If the map has been bounded in the
meantime, the run is green and phase 10's inbound entry for that cache closes, naming the change that bounded it.

- [ ] **Step 3: Mark the work earlier phases postponed here as landed**

*(Rewritten 2026-09-13.)* Four marks, each a ✅ on this phase's checklist row plus one dated sentence
in the roadmap's phase status note, and one confirmation:

- **The conformance assertion protocol** — phase 8a's Task 25 Step 3a has already said the protocol
  half phase 0 postponed has landed. Say the second half — "phase 9 adds the remaining suites" — has
  landed too: `Check`, `Runner`, `SharedInstance`, `InvariantSuite`, `PackagingSuite`, `CodecSuite`,
  `ExecutorSuite`, `Aggregate`, `Levels` and `Report#to_h` (Tasks 2–12a). Do not restate 8a's half.
- **The wire-boundary re-validation** — phase 8's second-landing sub-phase (8c's Task 19 Step 5a, or
  8a's Task 25 Step 3a) has said both adapters' call sites have landed. Say the portable assertion
  phase 1 named for this phase has landed: `InvariantSuite`'s second `XCUT-18` assertion drives a
  forged `Request` through a transport factory and asserts refusal before any wire activity (Task 7).
  If phase 8's sentence has not been written when this runs, do not write it here; record phase 9's
  clause and leave phase 8's to phase 8's plan.
- **`SEAM-25`'s lifecycle event** — 8b's Task 13 Step 5 has said the **emission** half phase 2
  postponed has landed. Say the harness half has landed, **as a CORRECTION**: 8b's design assigned
  that half to 8a, 8a wrote no executor suite, and phase 9 wrote `ExecutorSuite` (Task 11): close
  twice, executor shut once, one event, matched on the event name. Two dated sentences, each naming
  its half, is the truthful record; one that overwrote 8b's would present a correction as a
  restatement.
- **The MUST-level vacuity blocker** — mark Task 12a's row ✅ and say the blocker phase 9 postponed on
  2026-09-13 has landed before Task 15's disposition run, per its own condition: `Levels::OF`
  generated from appendix C, `Report#blocking_vacuities`, `#passed?` false over an un-waived,
  un-accepted MUST-level vacuity, and the two report sections.
- **Confirm, do not re-file**: the four other things phase 9 postponed still say what the design's
  *Work phase 9 postponed, and who owns it now* says and live where it says — the require-allowlist
  regeneration guard and the `B.1`/`B.2`/`B.5` lift under `docs/first-release.md` § Post-release
  triggers, the `NFR-12`/`NFR-16` assertions under its § Release path, and the `XCUT-12` fiber form on
  phase 10's inbound list in the roadmap's 2026-09-13 status note. A missing entry is a defect to
  report, not one to re-file elsewhere.
- **Route, do not register.** Anything this phase turns up that it is not acting on now goes to its
  owner the moment it is found: a numbered task in the owning phase's plan, phase 10's inbound list in
  the roadmap when it is audit or repair work on an already-planned phase, or `docs/first-release.md`
  when it belongs to the release — with the reason and the pick-up condition written beside the
  pointer. There is no register to append to, and a finding with no owner named is a finding nothing
  will act on.
- Decline **nothing**: the one item that invites it, the Steep target over a `test/` tree, has an
  unmet condition because phase 9's suites go in `lib/`, and that reasoning is inherited from 8a
  rather than re-derived; it stays under `docs/first-release.md` § Post-release triggers.

- [ ] **Step 4: File the three knowledge notes**

`notes/testing.md` (`## Superseded`, `testing/e27df4c7` and `testing/70473c9d` — Minitest 6 on 4.0.6 ships no `minitest/mock`); `notes/tooling-and-quality-gates.md` (`## Superseded`, `tooling-and-quality-gates/3085561e` — the SPDX cop cannot reach `.rbs`); `notes/cross-cutting-invariants.md`, a new file carrying **two** `## Reference` entries — the `XCUT-11` predicate (`cross-cutting-invariants/89eb6533`) and, separately, the AST-based gates. Each: role `review`, a manual `sha:manual-phase9-<slug>` marker, the backticked key on one line at column 0, the `<sub>` indented.

```bash
ruby scripts/verify_knowledge_structure.rb
ruby scripts/knowledge_drift.rb
```

- [ ] **Step 5: Update `CLAUDE.md`'s command block and count sentences**

Phase 9 adds three gate tasks to the seventeen phase 0 built; the "After scaffold" block and the phase-directory sentence both name what now exists.

- [ ] **Step 6: Append the roadmap status note and run housekeeping**

```bash
ruby .claude/skills/housekeeping/probe.rb
```

Expected: `no drift found`.

- [ ] **Step 7: Stage the change**

**No commit.** `CLAUDE.md`: "Agents do not commit, push, or touch the remote unless the user asks for that specific action in that message." Every one of the twenty-one preceding plans in this repository has zero commit steps; the reviewer commits.

```bash
git add -- <the files this task created or modified>
```

---

## Self-Review

**Spec coverage.** `R1` → Tasks 5–14, with `APPENDIX_B.md` (Task 14) carrying a row for each of the
61 items. `R2` → Task 9 builds the portable half and Task 15 records the gate half, with `NFR-10`,
`NFR-13` and `NFR-14` in **both**. `R3` → Task 5's `probe!`, Task 12a's MUST-level vacuity blocker
(`Levels`, `Report#blocking_vacuities`, the two report sections), and Tasks 15–16's
vacuity handling.
`R4` → Task 13. `R5` → Task 16, step 4. `R6` → the Global Constraints file-list line, Task 15's
step 4 and Task 11's `functional: nil` fallback. `R7` → Task 14. `R8` → Task 4 and Task 8's pair of
`XCUT-11` assertions. The 41 IDs: `XCUT-1`–`24` are covered by **28 assertions** across Tasks 5–8
(`XCUT-11`, `XCUT-13`, `XCUT-14` and `XCUT-18` carry two each), asserted by Task 8's own counting test and dispositioned in
Task 16; `NFR-1`–`17` split into Task 9's eight portable assertions and Task 15's ten recorded
gate results, with three IDs in both and `NFR-8`/`NFR-9` in neither — 8 + 10 − 3 = 15, which is the
seventeen less those two.

**Hand-forward coverage, restated from this plan's own numbers rather than the design's.** The
design's table is rebuilt against these task numbers, and the mapping is: rows naming `XCUT-11` →
Tasks 4 and 8; `XCUT-14` → Tasks 7 and 13; `XCUT-8`, `XCUT-9` → Tasks 6 and 13; `XCUT-5`/`-6`/`-7` →
Task 6; `XCUT-12` → Task 8; `XCUT-15` → Task 5; `XCUT-13`/`XCUT-22` → Tasks 5 and 11; `XCUT-19`,
`XCUT-20`, `XCUT-21` → Task 7; `XCUT-18` → Task 7; `SEAM-2`, `SSE-37` → Task 13; `SEAM-20`/`-21`/
`SERDE-3` → Task 10; `SEAM-12`, `SEAM-18` → Task 11; `OBS-21`/`OBS-25` → Task 14's map (8a already
shipped `RecordingSpan` and `Allocations`; phase 9 adds no assertion and records them by reference);
`NFR-11` → Task 9; the conformance assertion protocol's second half → Tasks 2–12a; the wire-boundary
re-validation's phase-9 clause → Task 7's second `XCUT-18` assertion; `SEAM-25`'s harness half → Task
11; the unsatisfied `ASYNC-3` MUST → Task 11's `ASYNC-3` assertion (written to fail, waived by ID) and
Task 16 step 4; the `B.1`/`B.2`/`B.5` lift → Task 14 (`P9-1`, declined; the trigger is in
`docs/first-release.md` § Post-release triggers); the MUST-level vacuity blocker → Task 12a; the
conformance-pass rows
(4c's and 7c's) → Task 16, step 5. **The build/run split is Tasks 1–14 and 15–17**, not the design's 1–9 /
10–17, which is corrected in the design.

**Placeholder scan.** No "TBD", no "add appropriate error handling", no "similar to Task N". Six
tasks reference code executed during planning and give the measured run counts; the shape-specified
assertions are named by ID with their conformance clause and the residue is counted in Task 8's step
5 — **12 `XCUT` and 5 `NFR`**, re-derived from the IDs listed there (the drafts' 14 and 11 were both
wrong).

**Type consistency.** `Assertion.build(ids:, name:, body:)`, `Result.build(assertion:, status:,
detail:)`, `Failure.new(message, expected:, actual:, requirement_ids:)`, `Vacuous.new(reason)`,
`Report.new(results)` / `.merge` / `#results` / `#to_h`, and `Check.that(condition, message,
expected:, actual:, ids:)` — used identically in Tasks 2–12. `Runner.run(assertions, waive:,
around:) { subject }` is called the same way by all four suites.
`Aggregate.by_requirement_id(suites, statuses:)` takes suites in both its definition (Task 12) and
its caller (Task 14). `ExecutorCase`'s constructor keyword is `recorder:` and `ExecutorSuite.run`'s
is `events:` — deliberately different, because one takes a recorder and the other a factory, which
is the distinction the planning run got wrong once.

**Commit steps.** Zero. Every task ends in `git add`, per `CLAUDE.md` and the twenty-one preceding
plans.
