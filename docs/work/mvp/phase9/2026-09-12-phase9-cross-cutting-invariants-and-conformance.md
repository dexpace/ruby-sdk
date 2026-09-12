# Phase 9 — Cross-Cutting Invariants and Conformance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Disposition all 41 of phase 9's requirement IDs — `XCUT-1`–`XCUT-24` and `NFR-1`–`NFR-17` — by building the instrument that answers them (four new suites in `dexpace-conformance`, four repository gates, one aggregate report and a 61-row appendix-B coverage map) and then running it against the tree phases 0–8 built.

**Architecture:** Two halves in one plan, in order. **Tasks 1–14 build the instrument** under ordinary TDD: every suite gets a deliberately non-conforming double that must make its assertion fail before a conforming one makes it pass, and every gate gets a failing fixture, exactly as phase 0 required of its seventeen gates. **Tasks 15–17 run it** and record verdicts. The two halves are kept apart deliberately: a green suite proves the *instrument* works, not that the SDK conforms, and those are different claims.

**Tech Stack:** Ruby ≥ 3.2 (matrix 3.2 / 3.3 / 3.4 / 4.0); Minitest; Rake; RBS + Steep; `RubyVM::AbstractSyntaxTree` for the repository gates; no third-party runtime dependency anywhere — `dexpace-conformance` declares `dexpace-core` and nothing else.

**Spec:** `docs/work/mvp/phase9/2026-09-12-phase9-cross-cutting-invariants-and-conformance-design.md`

## Global Constraints

Copied verbatim from the design and from `CLAUDE.md`. Every task's requirements implicitly include this section.

- **Every file opens with `# frozen_string_literal: true` on line 1, `# SPDX-License-Identifier: MIT` on line 2, blank line 3** (`NFR-13`; phase 0's `Dexpace/SpdxHeader` cop). There is no `# typed:` sigil in this repository.
- **`dexpace-conformance` declares `dexpace-core` and nothing else.** No `require "minitest"`, no `require "rspec"`, no `require "socket"` anywhere in its `lib/`. `Gem::Specification` needs no require; RubyGems is loaded before user code.
- **Phase 9 creates or modifies files only under `gems/dexpace-conformance/`, `tasks/`, `tools/`, `test/`, `.github/workflows/` and **each adapter gem's `test/` tree**.** No `lib/` or `sig/` file outside `gems/dexpace-conformance/` is touched, and no file in `dexpace-core` at all. The two widenings are load-bearing rather than convenient: a suite nobody drives proves nothing, and **8a's own precedent is a driver file inside the adapter gem** — `gems/dexpace-transport-net_http/test/dexpace/transport/net_http/conformance_test.rb`, which is one `conformance(…)` call and nothing else (8a plan, Task 23). Phase 9 follows that **placement** for `dexpace-serde-json` and `dexpace-async-thread`, but each driver calls its suite's `.run` and asserts on the report, because 8a's `MinitestDriver#conformance` builds a `TransportCase` for every assertion (8a plan:2302-2306) and widening it would change an interface phase 8 owns. And phase 0's `ci_workflow_test.rb` is a **blocking** gate asserting every entry in `DEFAULT_GATES` appears in some CI job, so a phase that adds four gates and leaves `ci.yml` alone reddens a phase-0 gate. This is `R6`'s boundary as a file list: phase 9 reports, phase 10 repairs — and the list bounds *where it may write*, not *whether it may fix another gem*, which it may not.
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
| `…/conformance/executor_case.rb` + `executor_suite.rb` | Appendix `B.7`'s lifecycle half; `DEF-31`'s harness |
| `…/conformance/aggregate.rb` | One report over every suite; the preamble stating what a green run does not prove; the coverage map's generated half, read off each suite's `.assertions` |
| `gems/dexpace-conformance/APPENDIX_B.md` | The 61-row coverage map |
| `tools/ast_scan.rb` | The shared `RubyVM::AbstractSyntaxTree` walker |
| `tools/invariant_gates.rb` | `cause_walk`, `bounded_map`, `drain_loop`, `seam_names` offence lists, each with its statically undecidable gap written down |
| `tasks/gates.rake` *(modified)* | The four new gate tasks, added to `DEFAULT_GATES` |
| `.github/workflows/ci.yml` *(modified)* | The four new gates placed in the `gates` job, because phase 0's `ci_workflow_test.rb` is blocking and asserts every `DEFAULT_GATES` entry appears in some job |
| `test/fixtures/gates/` | One deliberately failing fixture per new gate, plus a positive control. **This is the one spelling** — `test/gates/` holds the gate *tests*, `test/fixtures/gates/` their *fixtures* |

---

## Task 1: Re-verify the phase's Ruby facts on three interpreters

**Files:**
- Create: `test/support/warning_capture.rb`
- Create: `test/gates/phase9_ruby_facts_test.rb`

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
Minitest version split (`OI-49`), and the `Data` reader split (`NFR-4`, Task 15).

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

- [ ] **Step 2: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The four facts phase 9's machinery rests on, re-measured on the interpreter running this suite.
# Design "The verified Ruby facts this phase is built on"; XCUT-9, XCUT-14, NFR-4, NFR-17, OI-49.
# GateCase is phase 0's gate base (phase 0 plan:263-298) and does not load FatalWarnings; the
# "still raises" test below needs it, so DexpaceTestCase's file is required for that prepend.
require_relative "../support/dexpace_test_case"
require_relative "../support/gate_case"
require_relative "../support/warning_capture"

class Phase9RubyFactsTest < GateCase
  include WarningCapture

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

  test "parsing a file emits no warning, so the warnings-fatal gate does not fire on the scanner" do
    seen = capture_warnings { ::RubyVM::AbstractSyntaxTree.parse_file(__FILE__) }

    assert_empty(seen)
  end

  test "outside a capture block a warning still raises, so the gate is not weakened" do
    error = assert_raises(::RuntimeError) { Warning.warn("escaped\n") }

    assert_includes(error.message, "NFR-6")
  end

  test "minitest is a bundled gem, never a default one, on every supported Ruby" do
    spec = ::Gem::Specification.find_by_name("minitest")

    refute(spec.default_gem?, "OI-43: design 9.3 calls minitest a default gem; it is bundled")
  end

  test "minitest ships mock below 6 and not at 6, which is what OI-49 records" do
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

Expected: PASS on all four. **Two tests assert a different outcome per interpreter by design** —
`mock_available` is true wherever Minitest is 5.x and false on 4.0.6 (Minitest 6.0.0), which is
`OI-49`; and the Symbol node type is `:LIT` on 3.2.11 and 3.3.12 and `:SYM` on 3.4.10 and 4.0.6,
which is `OI-52`.

- [ ] **Step 4: If any fact has changed, stop and file, do not adapt**

A changed fact is a finding. Append to `docs/open-items.md` at the next id, note it under
`docs/knowledge/notes/`, and say in the phase's checklist that the plan's premise moved. Do not
quietly rewrite a later task around it.

- [ ] **Step 5: Stage the change**

**No commit.** `CLAUDE.md`: "Agents do not commit, push, or touch the remote unless the user asks
for that specific action in that message."

```bash
git add -- test/support/warning_capture.rb test/gates/phase9_ruby_facts_test.rb
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

# The five result statuses of DEF-22's protocol, decided in one place. NFR-17, DEF-22.
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

# Phase 9's additions to 8a's Report: the aggregate caller DEF-22 deferred #to_h for. NFR-4.
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
- Produces: `InvariantCase.new(core:, seam: nil, mutable: [])` with `#core`, `#mutable`,
  **`#probe!(name, promised_by, method: false)`**, `#seam?`, `#seam(**settings)`,
  `#bounded_map(cap:)`, `#bounded_map_store(map)`, `#draw_cnonce(source)`,
  `#redirect_hop(from:, to:, headers:)`, `#with_bounded_map`, `#with_bounded_map_store`,
  `#with_cnonce`, `#with_redirect_hops`;
  `InvariantSuite.assertions -> Array[Assertion]`;
  `InvariantSuite.run(core: ::Dexpace, seam: nil, mutable: [], bounded_map: nil, bounded_map_store: nil, cnonce: nil, redirect_hops: nil, waive: [], around: nil) -> Report`

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

      def initialize(core:, seam: nil, mutable: [])
        @core = core
        @seam = seam
        @mutable = mutable
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

      def run(core: ::Dexpace, seam: nil, mutable: [], bounded_map: nil, bounded_map_store: nil,
              cnonce: nil, redirect_hops: nil, waive: [], around: nil)
        Runner.run(assertions, waive: waive, around: around) do
          InvariantCase.new(core: core, seam: seam, mutable: mutable)
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
- Produces: nine more assertions over eight IDs — `XCUT-14` carries **two**, `bounded_maps` (the cap
  clause) and `bounded_map_drains` (the drain-to-cap clause), both added to
  `InvariantSuite.assertions` — plus `XCUT-16`, `XCUT-17`, `XCUT-18`, `XCUT-19`, `XCUT-20`,
  `XCUT-21`, `XCUT-24`

**Five of the eight IDs are written in full below** — `XCUT-14` (as two assertions), `XCUT-17`, `XCUT-18`, `XCUT-19`,
`XCUT-21` — because each carries three, four, four, five and two clauses respectively that a single
`Check.that` demonstrably cannot express, and because the assertions written in full in the first
draft each contained a measured defect. `XCUT-16`, `XCUT-20` and `XCUT-24` stay specified by shape.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Appendix B.8's security-by-default and bounded-memory items.
# XCUT-14 (both clauses), XCUT-17, XCUT-18, XCUT-21. XCUT-16, XCUT-20 and XCUT-24 add their tests
# in the step that writes their shape-specified assertions.
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

    assert_equal([:failed], statuses(S.run(core: core))["XCUT-18"])
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

- [ ] **Step 3: Write the eight assertions**

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
      # behaviour; this shape decides it. gates:drain_loop stays as a second line over the file.
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

- [ ] **Step 4: Run on the four installed interpreters; confirm 10 runs PASS**

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
  `XCUT-12`, `XCUT-23`. **After this task `InvariantSuite` carries 27 assertions across all 24
  `XCUT` IDs** — 24 IDs, with `XCUT-11`, `XCUT-13` and `XCUT-14` each carrying two.

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

**`XCUT-23` is written in full**, because §9.3 restates this exact `B.8` item — the seam-resolution
item "names require-time registration as the discovery substrate" — and because the requirement is
three ordered rules whose ordering is the content.

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

  def statuses(report)
    report.results.each_with_object({}) { |r, h| (h[r.assertion.ids.first] ||= []) << r.status }
  end

  test "the suite covers all 24 XCUT ids, and three of them carry two assertions each" do
    ids = S.assertions.flat_map(&:ids).select { |id| id.start_with?("XCUT-") }

    assert_equal(24, ids.uniq.size)
    assert_equal(27, ids.size, "XCUT-11, XCUT-13 and XCUT-14 each carry two clauses")
    assert_equal(%w[XCUT-11 XCUT-13 XCUT-14], ids.tally.select { |_, n| n > 1 }.keys.sort)
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
                          4.times { fibers.each { |f| f.resume if f.alive? } }

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
the same clause is `DEF-46`**, deferred because it needs a reactor the conformance gem cannot open.

- [ ] **Step 4: Run on the four installed interpreters and confirm the ID coverage**

```bash
for v in 3.2.11 3.3.12 3.4.10 4.0.6; do
  mise exec ruby@$v -- ruby -w -Igems/dexpace-conformance/lib -Igems/dexpace-core/lib \
    gems/dexpace-conformance/test/dexpace/conformance/invariant_suite_concurrency_test.rb
done
```

Expected: 5 runs, PASS, with the first test proving all 24 `XCUT` IDs are covered by 27 assertions.

- [ ] **Step 5: Record the residue honestly in the phase's checklist**

**Written in full by Tasks 5–8: 15 of the 27 assertions, over 12 IDs** — `XCUT-4`, `XCUT-9`,
`XCUT-11` ×2, `XCUT-13` ×2, `XCUT-14` ×2, `XCUT-15`, `XCUT-17`, `XCUT-18`, `XCUT-19`, `XCUT-21`,
`XCUT-22`, `XCUT-23`. **Specified by shape: 12 assertions, one per ID** —
`XCUT-1`, `XCUT-2`, `XCUT-3`, `XCUT-5`, `XCUT-6`, `XCUT-7`, `XCUT-8`, `XCUT-10`, `XCUT-12`,
`XCUT-16`, `XCUT-20`, `XCUT-24`. On the `NFR` side, **4 of 9 `PackagingSuite` assertions are written
in full** and 5 by shape. **The residue is 12 `XCUT` plus 5 `NFR`** — re-derived on 2026-09-13 by
counting the twelve IDs listed; the drafts' 14 and then 11 were both wrong, and 15 + 12 = 27 is the
suite's own counting test above. A shape-specified assertion is a task the implementer writes
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
Design `R2` states the split; the nine assertions below are the portable half.

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

  test "a conforming gem set passes, and NFR-13 is vacuous carrying its reason" do
    report = run_suite(conforming)

    assert_equal(:passed, statuses(report)["NFR-1"])
    assert_equal(:passed, statuses(report)["NFR-2"])
    assert_equal(:passed, statuses(report)["NFR-15"])
    assert_equal(:vacuous, statuses(report)["NFR-13"])
    assert_includes(report.to_s, "OI-50")
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
    # dexpace-core and nothing else, and why OI-44's per-gem denylist question does not arise here.
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

      # OI-50's measurement, REPORTED rather than asserted on: the SPDX gate is a RuboCop cop and
      # cannot reach .rbs. An assertion that asserted the ABSENCE of the header would turn red the
      # day OI-50 is repaired, which is a gate that punishes its own fix.
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

      # NFR-13 is recorded as VACUOUS carrying its reason, never as a positive assertion that the
      # gap persists. OI-50: the SPDX gate is a RuboCop cop, so it covers .rb and cannot reach
      # sig/**/*.rbs, which ships inside every gem. The count is reported so a reader sees the size
      # of the gap; nothing here turns red when OI-50 is repaired.
      def spdx_header_coverage
        Assertion.build(ids: ["NFR-13"], name: "every shipped source file carries the SPDX header",
                        body: lambda do |subject|
                          missing = subject.shipped_rbs_without_header

                          raise Vacuous,
                                "the SPDX gate is a RuboCop cop and cannot reach .rbs; " \
                                "#{missing.size} shipped signature file(s) carry no header (OI-50)"
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
`OI-38`'s `dexpace-transport-async_http` at `>= 3.3`, conforming by the requirement and non-conforming
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
- Modify: `gems/dexpace-serde-json/test/support/serde_seam_assertions.rb` — the content moves; the
  file is removed with `git rm` in the staging step
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
    # Appendix B.3's seam half. SEAM-20 and SERDE-3 are genuinely portable: DEF-16's
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

# The FIRST consumer of CodecSuite; DEF-16's dexpace-serde-oj is the second the lift exists for.
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
rejects. `APPENDIX_B.md` records them `by reference`.

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
git rm -- gems/dexpace-serde-json/test/support/serde_seam_assertions.rb
```

## Task 11: `ExecutorSuite` — `DEF-31`'s harness half

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
  `THREADS = 16`, `#executor(**settings)`, `#borrowed?`, `#borrowed(pool)`, `#functional?`,
  `#functional`, `#events?`, `#events`;
  `ExecutorSuite.run(build:, borrow: nil, functional: nil, events: nil, waive: [], around: nil) -> Report`

**`DEF-31`'s harness half is reassigned to phase 9, and this is a CORRECTION to a committed register
row, not a restatement of it.** The row reads: "The *harness* half of the condition — the assertion
living in `dexpace-conformance` — is **`8a`'s**, and `8b` hands it the shape rather than writing it."
8a wrote the protocol, the `WireServer` fixture and the transport suite, and wrote **no executor
suite**; 8b supplied the shape as promised. So the harness half is unwritten after phase 8, phase 9
writes it, and the row is wrong about which phase delivers it. Phase 9's checklist records the
pick-up **against `DEF-31`** with that correction named out loud — which is the discipline phase 4b
failed when it corrected its charter while claiming to restate it.

**Five assertions, not four: `ASYNC-16` and `ASYNC-17` are added.** `B.7`'s lifecycle bullet names
`ASYNC-15`, `ASYNC-16` and `ASYNC-17` together, and a suite covering only the first leaves two of
three with no check anywhere. **Two clauses are scoped out with a reason rather than silently
dropped:** `ASYNC-15`'s clause (c), interrupt-safety, needs an interrupt pending during close, and
§8.3 bans every primitive that could arrange one — so the clause holds because the flag is never
touched (`cross-cutting-invariants/8fa2c08d`) and there is nothing observable to assert; and
`SEAM-18` is the executor *seam's* shape rather than an implementation property, which 8b's own
suite asserts. Both are recorded in `APPENDIX_B.md` as scoped out, with those reasons.

**This task's code was executed during planning** on 3.2.11, 3.4.10 and 4.0.6: **8 runs, 9
assertions, 0 failures** on each.

**One thing the planning run got wrong first, and the fence below fixes.** The event recorder was a
single array passed to `.run` and shared across the whole report, so by the time the `SEAM-25`
assertion ran, three earlier assertions had each built and closed a pool and appended a shutdown
event — and the **conforming** double failed. `events:` is therefore a **factory returning a fresh
recorder**, one per case, and `Runner` already builds a fresh case per assertion. This is
`testing/4ef070df` applied to a fixture the suite constructs rather than one a test writes.

**Only the event NAME is readable.** 8b's two field keys (`"dexpace.executor.worker_count"`,
`"dexpace.executor.drained"`) are `private_constant`s in the pool and were deliberately not added
to core's `Keys`, "because the portable assertion needs the event name only".

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Appendix B.7's lifecycle half, and DEF-31's harness.
# SEAM-12, SEAM-25, ASYNC-15, ASYNC-16, ASYNC-17, XCUT-11, XCUT-13, XCUT-22.
require_relative "../../test_helper"

class DexpaceConformanceExecutorSuiteTest < DexpaceConformanceTestCase
  S = Dexpace::Conformance::ExecutorSuite

  # A conforming double: an inline executor whose close is latched, which drains before returning,
  # refuses work after close, and records exactly one event.
  class FakePool
    attr_reader :shutdown_count

    def initialize(events: nil, owned: true)
      @events = events
      @owned = owned
      @closed = false
      @shutdown_count = 0
      @lock = Thread::Mutex.new
    end

    def post(&block)
      raise "closed" if @closed

      block.call
    end

    def close
      @lock.synchronize do
        return if @closed

        @closed = true
      end
      return unless @owned

      @shutdown_count += 1
      @events << { name: "dexpace.instrumentation.shutdown" } unless @events.nil?
    end
  end

  class UnlatchedPool < FakePool
    def close
      @closed = true
      @shutdown_count += 1
      @events << { name: "dexpace.instrumentation.shutdown" } unless @events.nil?
    end
  end

  class LeakyPool < FakePool
    def post(&block) = block.call   # accepts work after close: ASYNC-16's second half
  end

  # ASYNC-17's subject: an implementation that owns nothing.
  class FunctionalExecutor
    def shutdown_count = 0
    def post(&block) = block.call
    def close = nil
  end

  class WorkingCloseExecutor
    attr_reader :shutdown_count

    def initialize = (@shutdown_count = 0)
    def post(&block) = block.call
    def close = @shutdown_count += 1
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
    defaults = { build: ->(events: nil, **_kw) { FakePool.new(events: events) },
                 borrow: ->(pool) { BorrowHolder.new(pool) },
                 functional: -> { FunctionalExecutor.new },
                 events: -> { [] } }
    S.run(**defaults.merge(over))
  end

  test "a conforming executor passes every lifecycle assertion" do
    report = conforming

    assert_equal({ "SEAM-12" => :passed, "XCUT-13" => :passed, "XCUT-22" => :passed,
                   "ASYNC-16" => :passed, "ASYNC-17" => :passed, "SEAM-25" => :passed },
                 statuses(report))
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
    report = conforming(functional: -> { WorkingCloseExecutor.new })

    assert_equal(:failed, statuses(report)["ASYNC-17"])
  end

  test "an adapter supplying no resource-free implementation makes ASYNC-17 vacuous" do
    report = conforming(functional: nil)

    assert_equal(:vacuous, statuses(report)["ASYNC-17"])
  end

  test "an adapter with no borrowing entry point is vacuous, never failed" do
    report = conforming(borrow: nil, events: nil)

    assert_equal(:vacuous, statuses(report)["XCUT-22"])
    assert_equal(:vacuous, statuses(report)["SEAM-25"])
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
      # no-op default against a pool that owns a thread would assert the opposite requirement.
      def functional?
        !@functional.nil?
      end

      def functional
        raise Vacuous, "no resource-free implementation supplied" if @functional.nil?

        @functional.call
      end

      def events?
        !@recorder.nil?
      end

      # DEF-31's "close twice -> executor shut once, one event" needs this and nothing else. Only
      # the event NAME is readable: 8b's two field keys are adapter-private constants and a portable
      # assertion must not reach for them.
      def events
        raise Vacuous, "no event recorder supplied to ExecutorSuite.run" if @recorder.nil?

        @recorder.to_a
      end
    end
  end
end
```

- [ ] **Step 4: Write `executor_suite.rb` with its six assertions**

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
    # Appendix B.7's lifecycle half, and DEF-31's harness half -- which the register assigns to 8a
    # and which 8a did not write; phase 9 writes it and says so.
    module ExecutorSuite
      module_function

      def assertions
        @assertions ||= [concurrent_post, close_is_latched, borrowed_executor_survives,
                         graceful_shutdown, default_close_is_a_no_op,
                         one_shutdown_event].freeze
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
      def close_is_latched
        Assertion.build(ids: %w[XCUT-13 ASYNC-15], name: "an owned executor's close is idempotent",
                        body: lambda do |subject|
                          pool = subject.executor
                          pool.close
                          pool.close

                          Check.that(pool.shutdown_count == 1,
                                     "close shut the executor more than once",
                                     expected: 1, actual: pool.shutdown_count,
                                     ids: %w[XCUT-13 ASYNC-15])
                        end)
      end

      # XCUT-22 / ASYNC-15 clause (b): the SDK closes only what it created.
      def borrowed_executor_survives
        Assertion.build(ids: %w[XCUT-22 ASYNC-15],
                        name: "a caller-supplied executor survives its holder's close",
                        body: lambda do |subject|
                          raise Vacuous, "this adapter exposes no borrowing entry point" unless subject.borrowed?

                          underlying = subject.executor
                          holder = subject.borrowed(underlying)
                          holder.close

                          Check.that(underlying.shutdown_count.zero?,
                                     "the SDK shut down an executor it borrowed",
                                     expected: 0, actual: underlying.shutdown_count,
                                     ids: %w[XCUT-22 ASYNC-15])
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
      # lightweight/functional implementations need not implement lifecycle management."
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
                          Check.that(functional.shutdown_count.zero?,
                                     "a resource-free implementation's close did work",
                                     expected: 0, actual: functional.shutdown_count,
                                     ids: ["ASYNC-17"])
                        end)
      end

      # SEAM-25, via DEF-31: one lifecycle event on the FIRST close of an owned executor.
      def one_shutdown_event
        Assertion.build(ids: ["SEAM-25"],
                        name: "closing an owned executor emits exactly one shutdown event",
                        body: lambda do |subject|
                          raise Vacuous, "no event recorder supplied" unless subject.events?

                          pool = subject.executor
                          pool.close
                          pool.close
                          shutdowns = subject.events.count { |e| e[:name].to_s.include?("shutdown") }

                          Check.that(shutdowns == 1,
                                     "an owned executor's close did not emit exactly one event",
                                     expected: 1, actual: shutdowns, ids: ["SEAM-25"])
                        end)
      end
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

# DEF-31's harness, driven against the first thing in this repository that actually OWNS an executor.
#
# ExecutorSuite.run is called directly and its report asserted: 8a's MinitestDriver#conformance
# builds a TransportCase per assertion (8a plan:2302-2306) and rejects functional:/events:, and
# widening it would change an interface phase 8 owns (R6).
#
# Built from 8b's filed fence: Pool's constructor is private and .build takes size:, logger: and
# friends (8b plan:1315-1317). 8b files no borrowing entry point in this gem -- the holder of a
# caller-supplied executor is Transport.async_over (8b plan:2872) -- and no resource-free
# implementation, so borrow: and functional: are nil and XCUT-22 and ASYNC-17 report :vacuous with
# their reasons. events: is nil too: 8b emits its shutdown event through a 5b logger sink
# (8b plan:1645-1651), not into an array.
class DexpaceAsyncThreadConformanceTest < Minitest::Test
  def test_executor_suite
    report = Dexpace::Conformance::ExecutorSuite.run(
      build: ->(**settings) { Dexpace::Async::Thread::Pool.build(size: 2, **settings) },
      borrow: nil, functional: nil, events: nil, waive: []
    )

    assert(report.passed?, report.to_s)
  end
end
```

If `Dexpace::Async::Thread` exposes no `.inline` or equivalent resource-free implementation when this
runs, pass `functional: nil` and let `ASYNC-17` report `:vacuous` with its reason — **do not invent
one inside the adapter**, which `R6` forbids.

- [ ] **Step 6: Run on the four installed interpreters**

Expected: 8 runs in the gem's own suite on each of 3.2.11, 3.3.12, 3.4.10 and 4.0.6, plus **one**
test in the adapter driver. **That driver is not expected green against 8b's real `Pool`**: the
suite's `close_is_latched` and `borrowed_executor_survives` read `#shutdown_count`, which 8b's
filed `Pool` does not define — record the `:error` as a finding, do not add the method (`R6`).

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

**This task's code was executed during planning** on 3.2.11, 3.4.10 and 4.0.6: 4 runs, 11 assertions, 0 failures on each.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# One report over every suite, and the preamble docs/first-release.md's blocker requires.
# NFR-4, NFR-17, DEF-22, ASYNC-3, ASYNC-4.
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

Expected: 5 runs, PASS. (Measured during planning: **5 runs, 15 assertions, 0 failures** on 3.2.11,
3.4.10 and 4.0.6.)

- [ ] **Step 5: Stage the change**

**No commit.** `CLAUDE.md`: "Agents do not commit, push, or touch the remote unless the user asks for that specific action in that message." Every one of the twenty-one preceding plans in this repository has zero commit steps; the reviewer commits.

```bash
git add -- gems/dexpace-conformance/lib/dexpace/conformance/aggregate.rb
```

---

## Task 13: The four repository gates and the AST walker

**Files:**
- Create: `tools/ast_scan.rb`
- Create: `tools/invariant_gates.rb`
- Modify: `tasks/gates.rake` — four tasks, added to `DEFAULT_GATES`
- **Modify: `.github/workflows/ci.yml`** — the four tasks placed in the `gates` job. Phase 0's
  `ci_workflow_test.rb` is **blocking** and asserts every `DEFAULT_GATES` entry appears in some job,
  so a phase that adds four gates and leaves the workflow alone reddens a phase-0 gate.
- Create: `test/fixtures/gates/walks_cause.rb`, `reflective_cause.rb`, `delegates_cause.rb`,
  `hash_shapes.rb`, `drain_loop_map.rb`, `check_then_evict_map.rb`, `seam_shapes.rb`
- Test: `test/gates/invariant_gates_test.rb`

**Interfaces:**
- Consumes: nothing in `dexpace-conformance`; these are repository gates, not portable assertions
  (design `R4`, addenda A4–A7)
- Produces: `AstScan::SEND_TYPES`, `::SYMBOL_TYPES`, `::REFLECTIVE_SENDS`,
  `AstScan.receiver_calls(path, names)`, `.hash_ivar_assignments(path)`, `.constant_paths(path)`,
  `.string_literals(path)`, `.eviction_is_looped?(path, names)`;
  `InvariantGates.cause_walk(files, allowed:)`, `.bounded_map(files, allowed:)`,
  `.drain_loop(path, evictions:)`, `.seam_names(files, namespaces:)`; rake tasks
  `gates:cause_walk`, `gates:bounded_map`, `gates:drain_loop`, `gates:seam_names`, and the `PENDING`-empty assertion
  added to 7b's existing `gates:serde_boundary`

**This task's code was executed during planning** on 3.2.11, 3.4.10 and 4.0.6: **9 runs, 21
assertions, 0 failures** on each, against seven mutation fixtures.

**Five measured corrections, each one a gate that was wrong about a real file** — the first three
clean over a live defect, the last two red over conforming code.

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

**`XCUT-14`'s drain-loop clause gains a second line rather than moving.** Task 7's
`bounded_map_drains` asserts it behaviourally and deterministically — a store pre-filled to cap + 5,
then one `set`: a drain loop ends at 8, a check-then-evict at 13 — and `gates:drain_loop` checks the
file's shape beside it. An earlier draft said the behaviour was undecidable; that premise was false.

- [ ] **Step 1: Write the seven fixtures**

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
`drain_loop_map.rb` evicts with `@h.shift while @h.size > @cap`; `check_then_evict_map.rb` with
`@h.shift if @h.size >= @cap`.

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

  test "drain_loop accepts a looped eviction and rejects a check-then-evict" do
    assert_empty(InvariantGates.drain_loop(fixture("drain_loop_map.rb")))
    assert_equal(1, InvariantGates.drain_loop(fixture("check_then_evict_map.rb")).size)
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
end
```

- [ ] **Step 3: Run to verify it fails**

Expected: FAIL — `cannot load such file -- tools/invariant_gates`.

- [ ] **Step 4: Write `tools/ast_scan.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The shared walker behind gates:cause_walk, gates:bounded_map, gates:drain_loop and
# gates:seam_names.
#
# RubyVM::AbstractSyntaxTree rather than a regex, because `grep '\.cause'` matches a comment, a
# string, an `# XCUT-9` citation in a test header and the requirement ID itself. Verified on
# 3.2.11, 3.4.10 and 4.0.6: present on all three, and parsing emits NO WARNING under -w -- which is
# load-bearing, because phase 0's shared test case prepends FatalWarnings to Warning's singleton
# class, so a scanner that warned would fail the suite that runs it. `prism` is absent on the 3.2
# floor (LoadError), so the AST route needs no conditional require where Prism would.
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

  # Every send whose method name is in `names`, whatever the call syntax, plus every reflective
  # send naming one of them as a Symbol literal.
  #
  # @return [Array[Array(String, Integer, Symbol)]] path, line, method name
  def receiver_calls(path, names)
    hits = []
    walk(::RubyVM::AbstractSyntaxTree.parse_file(path)) do |node|
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
    walk(::RubyVM::AbstractSyntaxTree.parse_file(path)) do |node|
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

  # Whether any send named in `names` appears inside a `while`/`until` loop. This is how XCUT-14's
  # DRAIN-LOOP clause -- "a loop, not a single pre-insert check-then-evict" -- is checked as SHAPE: a
  # second line beside InvariantSuite's deterministic behavioural assertion of the same clause.
  def eviction_is_looped?(path, names)
    looped = false
    walk_with_loop_depth(::RubyVM::AbstractSyntaxTree.parse_file(path), 0) do |node, depth|
      next unless SEND_TYPES.include?(node.type)

      called = node.type == :VCALL ? node.children[0] : node.children[1]
      looped = true if names.include?(called) && depth.positive?
    end
    looped
  end

  def walk_with_loop_depth(node, depth, &block)
    return unless node.is_a?(::RubyVM::AbstractSyntaxTree::Node)

    block.call(node, depth)
    inner = %i[WHILE UNTIL].include?(node.type) ? depth + 1 : depth
    node.children.each { |child| walk_with_loop_depth(child, inner, &block) }
  end

  # Every constant path written in the file, rendered as `Dexpace::Serde::JSON`.
  #
  # @return [Array[Array(String, Integer, String)]] path, line, constant path
  def constant_paths(path)
    hits = []
    walk(::RubyVM::AbstractSyntaxTree.parse_file(path)) do |node|
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
    walk(::RubyVM::AbstractSyntaxTree.parse_file(path)) do |node|
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

  # **Stated gap, because a gate whose blind spots are unwritten is a gate nobody can audit.**
  # Undecidable statically and therefore NOT reported by any scan below: `send(name)` where `name`
  # is a variable; `@h = build_map` and any Hash arriving through a parameter or a constant `dup`;
  # and a constant reached through `const_get(dynamic)`. Each gate is a floor on its invariant
  # rather than proof of it, and the addendum for each states its measured catch rate. The
  # statically DECIDABLE shapes each gate still misses, measured, are OI-56's table.
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
  def bounded_map(files, allowed:)
    offences(files, allowed.keys) do |path|
      AstScan.hash_ivar_assignments(path).map do |(_, line, ivar)|
        "#{path}:#{line}: #{ivar} is a Hash on an instance; only Dexpace::BoundedMap may hold a " \
          "caller- or server-keyed map (XCUT-14)"
      end
    end
  end

  # XCUT-14's DRAIN-LOOP clause, checked on the ONE file that owns the bounded map, as SHAPE --
  # which is what the requirement's own wording is about: "using a loop (not a single pre-insert
  # check-then-evict)". **Stated gap:** this proves an eviction send sits inside a loop in that
  # file, not that the loop is the only eviction path; a second, unlooped eviction elsewhere in the
  # same file is not reported.
  def drain_loop(path, evictions: %i[shift delete])
    return [] if AstScan.eviction_is_looped?(path, evictions)

    ["#{path}: the bounded map evicts without a drain loop; XCUT-14 requires a loop, not a " \
     "single pre-insert check-then-evict (XCUT-14)"]
  end

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

- [ ] **Step 6: Wire four Rake tasks, add them to `DEFAULT_GATES`, and edit `ci.yml`**

`gates:cause_walk` and `gates:bounded_map` run over `Dir["gems/*/lib/**/*.rb"]`; `gates:drain_loop`
over `Dexpace::BoundedMap`'s own file; `gates:seam_names` over
`Dir["gems/dexpace-core/lib/**/*.rb"]` only. **A fifth gate is touched and is not new: `gates:serde_boundary`,
which 7b wired into the default task (7b plan:1758)** — phase 9 adds one assertion to it, that its `PENDING` list is empty, which
is the clause 7b handed forward and could not assert while phase 7 was still running — plus a fixture
with one `PENDING` entry, so the addition has been seen to fail. All five are **blocking**: a
non-blocking addition while dispositioning `NFR-17` would be self-falsifying. The **four new** ones
go in `DEFAULT_GATES` and the `gates` CI job, which is what keeps phase 0's `ci_workflow_test.rb`
(phase 0 plan:3610) green; `gates:serde_boundary` is already in both.

- [ ] **Step 7: Run the gate test on the four installed interpreters, then the whole set**

```bash
for v in 3.2.11 3.3.12 3.4.10 4.0.6; do mise exec ruby@$v -- ruby -w test/gates/invariant_gates_test.rb; done
bundle exec rake
```

Expected: **9 runs, 25 assertions, 0 failures** on each — measured 2026-09-13 on 3.2.11, 3.3.12,
3.4.10 and 4.0.6 — and
the four gates green over the real tree, or reporting offences Task 16 files.

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

**Two checks from the first draft are dropped, because neither is a budget this phase can meet.** A
**276-distinct-ID coverage check** against 22 hand-written by-reference rows is not arithmetic that
closes. And a **ten-line-header check** on each referenced file cannot pass: `B.5`'s configuration
items name around twenty `CFG` IDs each, and no ten-line header holds twenty IDs. Both are replaced
by one check that *is* decidable — **every row names at least one requirement ID and an evidence path
that exists** — and the weakening is filed as `OI-53` so the gap is visible rather than quietly
absent.

**The ID regex is restricted to the 19 known prefixes.** A bare `[A-Z]+-\d+` matches `ISO-8601`,
which appears in `B.3`'s real text, and `RFC-3986`-shaped tokens elsewhere; the prefix list is
`CLAUDE.md`'s own, in appendix-C order.

**Three things the checks establish, and the one they cannot** (design `R7`, `P9-7`):

- **Established:** the table has exactly 61 rows, and each section's count matches the count parsed
  from the specification's own appendix B. A drifting checklist is caught the day it drifts.
- **Established:** every row names at least one requirement ID from the 19 prefixes.
- **Established:** every row's evidence path exists on disk.
- **Not established:** that a referenced test actually *asserts* the described behaviour. Nothing
  mechanical can, short of re-implementing the assertion. The map's preamble says so, and so does
  `Aggregate::PREAMBLE`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The appendix-B coverage map. Design R7, P9-7, P9-8; OI-53 records what these checks do not reach.
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
    claimed and a file exists, not that the behaviour is asserted (design P9-7, OI-53).

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
`Tristate`/coercion items and `B.4`'s non-lifted items — naming the owning phase's test file. Do
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
- Modify: `docs/open-items.md`, `docs/first-release.md` as findings require

**Interfaces:**
- Consumes: every gate phase 0 built, plus Task 9's `PackagingSuite` and Task 13's four new gates
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
require (`OI-38`).

`P9-2`'s whole argument is that a source gemspec and a published one can differ, so reading the source here would falsify the phase's own deviation.

- [ ] **Step 3: Write one checklist row per `NFR`, with the evidence named**

Each row: the ID, the legend mark (✅ / 🚫 / ⏳ / N/A), the disposition artifact from the design's `R2` table, and either the observed number or the finding. Six marks are **predicted ⏳** and they divide two ways — four pending an open item (`NFR-7`/`OI-6`, `NFR-10`/`OI-38`, `NFR-13`/`OI-50`, `NFR-17`/`OI-49`) and two pending a release rather than a finding (`NFR-4`, no `v*` tag to diff against, `P0-8`'s pre-release branch; `NFR-16`, no release path, `DEF-20`). **A prediction is not an observation.** If a gate passes where the design predicted ⏳, mark it ✅ **and say the design's prediction was wrong**, naming which. If it fails where ✅ was predicted, the same in the other direction.

- [ ] **Step 4: File what the pass found, and repair nothing**

Per design `R6`: `:failed` stays `:failed`; the row is ⏳ or 🚫 with the reason; an `OI-<n>` is filed; a MUST additionally gains a `docs/first-release.md` blocker. **Do not lower `--fail-level`, add an `Exclude:`, relax a metric cop or make a gate report-only** — `NFR-17`'s entire content is that no gate is advisory, and relaxing one while dispositioning it falsifies the evidence.

**An un-waived `:vacuous` on a MUST-level ID is a report blocker, not a pass.** **The mechanism does
not exist yet** — `Report#passed?` is true over vacuous results and nothing in the gem knows an ID's
level — so **`DEF-47` is picked up before this run**, not after it. `R3`'s
absent-artifact case makes a missing artifact `:vacuous` rather than `:failed`, because at execution
time "not built yet" and "built wrong" are different findings and phase 10 acts on the difference.
What stops `:vacuous` becoming a way to pass by not building: the aggregate report lists every
un-waived vacuity against a MUST **separately**, that list is a **phase-9 report blocker**, and each
entry earns a `docs/first-release.md` line. A SHOULD-level vacuity is recorded and does not block.

- [ ] **Step 5: Stage the change**

**No commit.** `CLAUDE.md`: "Agents do not commit, push, or touch the remote unless the user asks for that specific action in that message." Every one of the twenty-one preceding plans in this repository has zero commit steps; the reviewer commits.

```bash
git add -- docs/work/mvp/phase9/ \
        docs/open-items.md \
        docs/first-release.md
```

---

## Task 16: The `XCUT` audit pass — probe, run, record

**Files:**
- Modify: the phase-9 checklist — the `XCUT` half
- Modify: `docs/open-items.md`, `docs/deviations.md` as findings require

**Interfaces:**
- Consumes: `InvariantSuite` (27 assertions), `TransportSuite` (8a, two drivers), `CodecSuite`, `ExecutorSuite`, the four repository gates
- Produces: twenty-four dispositioned rows and one aggregate report

- [ ] **Step 1: Run every existence probe and record the result**

Each probe is `InvariantCase#probe!`'s subject, and a miss is `:vacuous` with its reason — never
`:failed` and never `:error`. A MUST-level `:vacuous` is a report blocker (Task 15, step 4).

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

- [ ] **Step 3: Record the two dispositions a reader checks first**

Per design `R5`: **`ASYNC-3`** is asserted so it genuinely fails, waived by requirement ID in the first-party build, and printed as `waived (would fail): ASYNC-3` — never `passed`, never `vacuous`. **`ASYNC-4`** is `:vacuous` and is added to **no register row**; `DEF-18`'s `Cites:` line is `ASYNC-3, PIPE-33` and stays so. Neither ID gets a phase-9 checklist row — both are phase 8's.

- [ ] **Step 4: Record the vacuities and deferrals other phases handed forward**

Four, from 4c and 7c, recorded in the aggregate report's preamble and **not** as phase-9 checklist rows: `PIPE-33` (`DEF-18`), `PIPE-36` (`DEF-4`), `PIPE-39` (`DEF-39`), `PIPE-32`'s vacuity until `DEF-39` lands, `PAGE-35`'s vacuity, and **`PAGE-15`'s wrapping clause (`P7-1`), which §12's `PAGE` row does not record** — that last one goes to `docs/deviations.md`'s "Deviations found outside a phase" holding area for phase 10 to fold in.

- [ ] **Step 5: Write one checklist row per `XCUT` ID, with the audit subject named**

24 rows, each naming the artifact audited, the assertion that audited it, and the mark.

- [ ] **Step 6: Stage the change**

**No commit.** `CLAUDE.md`: "Agents do not commit, push, or touch the remote unless the user asks for that specific action in that message." Every one of the twenty-one preceding plans in this repository has zero commit steps; the reviewer commits.

```bash
git add -- docs/work/mvp/phase9/ \
        docs/open-items.md \
        docs/deviations.md
```

---

## Task 17: Regenerate the API surface, run the full gate set, close the phase

**Files:**
- Modify: `gems/dexpace-conformance/sig/**/*.rbs` — regenerated baseline
- Modify: the runtime surface manifest
- Modify: `docs/deferred-items.md` — the two pick-ups and the four new rows
- Modify: `docs/knowledge/notes/` — the three notes
- Modify: `CLAUDE.md`, `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`

**Interfaces:**
- Consumes: everything above
- Produces: a green `bundle exec rake` on every matrix row, or a recorded reason it is not

**Both baselines are regenerated, not one.** `Data.define`'s generated readers on `Assertion` and `Result` are public API `rbs validate` cannot see, and `OI-19` measured that the runtime snapshot does not see them either for this repository's `class X < Data.define(...)` convention — so the two catch different things and neither alone covers `Report#to_h`, `Aggregate::PREAMBLE` and eleven new constants.

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

Expected: green, **with the 3.2 row excluding `dexpace-transport-async_http`** (`OI-38`, `P8-36`:
`async-http` 0.104.0 declares `>= 3.3`) and with whatever `OI-49`'s `minitest` pin decision produced
on the 4.0 row. Both exclusions are recorded, not silent. The same four rows run locally: 3.2.11,
3.3.12, 3.4.10 and 4.0.6.

- [ ] **Step 3: Append the register rows**

`docs/deferred-items.md`: move **`DEF-22`**, **`DEF-25`** and **`DEF-31`** to
`picked-up (<date>, phase 9)`. `DEF-22`'s and `DEF-25`'s conditions name this phase in as many
words. **`DEF-31` is a correction, not a match**: its row assigns the harness half to `8a`, 8a wrote
no executor suite, and phase 9 writes it — so the pick-up line says that out loud rather than
presenting itself as meeting the condition as written. Append `DEF-43` through `DEF-46` from the
design's table, each with a target phase or an explicit condition. Mark **nothing** UNSCHEDULED: the
one row that invites it, `DEF-23`, has an unmet condition because phase 9's suites go in `lib/`, and
that reasoning is inherited from 8a rather than re-derived.

- [ ] **Step 4: File the three knowledge notes**

`notes/testing.md` (`## Superseded`, `testing/e27df4c7` and `testing/70473c9d` — Minitest 6 on 4.0.6 ships no `minitest/mock`); `notes/tooling-and-quality-gates.md` (`## Superseded`, `tooling-and-quality-gates/3085561e` — the SPDX cop cannot reach `.rbs`); `notes/cross-cutting-invariants.md`, a new file (`## Reference`, `cross-cutting-invariants/89eb6533` — the `XCUT-11` predicate and the AST-based gates). Each: role `review`, a manual `sha:manual-phase9-<slug>` marker, the backticked key on one line at column 0, the `<sub>` indented.

```bash
ruby scripts/verify_knowledge_structure.rb
ruby scripts/knowledge_drift.rb
```

- [ ] **Step 5: Update `CLAUDE.md`'s command block and count sentences**

Phase 9 adds four gate tasks to the seventeen phase 0 built; the "After scaffold" block and the phase-directory sentence both name what now exists.

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
`NFR-13` and `NFR-14` in **both**. `R3` → Task 5's `probe!` and Tasks 15–16's vacuity handling.
`R4` → Task 13. `R5` → Task 16, step 3. `R6` → the Global Constraints file-list line, Task 15's
step 4 and Task 11's `functional: nil` fallback. `R7` → Task 14. `R8` → Task 4 and Task 8's pair of
`XCUT-11` assertions. The 41 IDs: `XCUT-1`–`24` are covered by **27 assertions** across Tasks 5–8
(`XCUT-11`, `XCUT-13` and `XCUT-14` carry two each), asserted by Task 8's own counting test and dispositioned in
Task 16; `NFR-1`–`17` split into Task 9's eight portable assertions and Task 15's twelve recorded
gate results, with three IDs in both and `NFR-8`/`NFR-9` in neither.

**Hand-forward coverage, restated from this plan's own numbers rather than the design's.** The
design's table is rebuilt against these task numbers, and the mapping is: rows naming `XCUT-11` →
Tasks 4 and 8; `XCUT-14` → Tasks 7 and 13; `XCUT-8`, `XCUT-9` → Tasks 6 and 13; `XCUT-5`/`-6`/`-7` →
Task 6; `XCUT-12` → Task 8; `XCUT-15` → Task 5; `XCUT-13`/`XCUT-22` → Tasks 5 and 11; `XCUT-19`,
`XCUT-20`, `XCUT-21` → Task 7; `XCUT-18` → Task 7; `SEAM-2`, `SSE-37` → Task 13; `SEAM-20`/`-21`/
`SERDE-3` → Task 10; `SEAM-12`, `SEAM-18` → Task 11; `OBS-21`/`OBS-25` → Task 14's map (8a already
shipped `RecordingSpan` and `Allocations`; phase 9 adds no assertion and records them by reference);
`NFR-11` → Task 9; `DEF-22` → Tasks 2–12; `DEF-31` → Task 11; the conformance-pass rows (4c's and
7c's) → Task 16, step 4. **The build/run split is Tasks 1–14 and 15–17**, not the design's 1–9 /
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
