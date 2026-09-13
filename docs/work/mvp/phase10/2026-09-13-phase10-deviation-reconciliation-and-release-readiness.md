# Phase 10 — Deviation Reconciliation and Release Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give all 124 of design §10's requirement IDs a verdict re-derived from as-built source, ship the repairs that verdict and phase 9's report demand, write the thirteen frozen-chapter amendments out so applying them is editorial, and leave `docs/first-release.md` with a per-line disposition. No gem is published; every gem stays at `0.0.0`.

**Architecture:** Four halves in one plan, in order. **Tasks 1–3 build and read the instrument** — the facts, one new gate over `docs/deviations.md`, and one pass over phase 9's report that turns it into an intake table. **Tasks 4–10 ship the repairs**, each under ordinary TDD with the audit as the failing test. **Tasks 11–15 re-derive design §10's nineteen entries plus its closing note** against the tree those repairs produced, one task per entry group, and move `docs/deviations.md`'s rows. **Tasks 16–19 close** — the two documentation repairs, the amendment set, the release-register walk, and the phase. The order is a dependency chain: a ledger audit that runs before the repairs audits a tree that will not ship.

**Tech Stack:** Ruby ≥ 3.2 (matrix 3.2 / 3.3 / 3.4 / 4.0); Minitest; Rake; RBS + Steep; `RubyVM::AbstractSyntaxTree` for `gates:sole_parse` and `RBS::Parser` for `gates:spdx_rbs`, both already available on every matrix row; no third-party runtime dependency added anywhere.

**Spec:** `docs/work/mvp/phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness-design.md`

## Global Constraints

Copied from the design and from `CLAUDE.md`. Every task's requirements implicitly include this section.

- **Every Ruby file opens with `# frozen_string_literal: true` on line 1, `# SPDX-License-Identifier: MIT` on line 2, blank line 3** (`NFR-13`; phase 0's `Dexpace/SpdxHeader` cop). **Every `.rbs` file opens with `# SPDX-License-Identifier: MIT` on line 1 and nothing else** — one line, not two, because `# frozen_string_literal: true` has no meaning in RBS (design Fact 2, Task 5). There is no `# typed:` sigil in this repository.
- **Phase 10 writes only where the design's `R1` file list says it may**: `gems/dexpace-core/`, `gems/dexpace-transport-async_http/`, `gems/dexpace-transport-net_http/` (its `sig/` for Task 5 and its `test/` for Task 10 — not its `lib/`), `gems/dexpace-conformance/` (Task 3 only), every gem's `sig/`, `tools/`, `tasks/`, `test/`, the root `Rakefile`, `.github/workflows/ci.yml`, `.claude/skills/housekeeping/`, `docs/deviations.md`, `docs/first-release.md`, `CLAUDE.md`, `docs/README.md`, the roadmap, `docs/knowledge/notes/` and any `docs/work/mvp/` document. **Never** `docs/product-spec/`, `docs/product-spec.md`, `docs/sdk-design-ruby/`, `docs/sdk-design-ruby.md` or `docs/knowledge/harvested/`. Those five are frozen and the whole of Task 17 is the consequence.
- **`dexpace-core` adds no `require` outside the allowlist and no `add_dependency`.** Task 8's new error file requires nothing; Task 10 edits an existing file.
- **Every task that adds a constant to a gem also adds its `require_relative` to that gem's entry file, in the same step.** A constant with no require is a `NameError` in every consumer.
- **Every new gate name is appended to `DEFAULT_GATES` in the root `Rakefile`, not in `tasks/gates.rake`** — the `Rakefile` `load`s `tasks/*.rake` **before** defining the array and freezes it after (phase 0 plan, Task **2** Step 6 — Task 1 is the development pin and repository hygiene), so a gate
added anywhere else is not in `task default:` and therefore not blocking, which `NFR-17` forbids. And every new gate name goes in a CI job, because phase 0's `ci_workflow_test.rb` is blocking and asserts every `DEFAULT_GATES` entry appears in some job.
- **`Timeout.timeout`, `Thread#raise`, `Thread#kill`, `Thread#terminate` and `Thread#exit` are banned repository-wide** (`Dexpace/NoThreadInterrupt`, §8.3). Task 9's fiber driver uses `Dexpace::Cancellation` and `Sync { }`, never an interrupt.
- **`downcase`/`upcase`/`casecmp` take no locale argument** (`Dexpace/NoLocaleCaseFold`, `HTTP-13`); **`URI::RFC3986_PARSER` is pinned for every parse and resolution** (§3.5).
- **`assert_predicate` is not used.** It sends past `private` on the 3.2 floor; visibility is asserted with `respond_to?` (phase 1's finding, every phase plan's Global Constraints).
- **Every test runs alone, in any order** (`testing/4ef070df`): mutable fixtures fresh per test, never shared across a run. **`assert_equal(expected, actual)`, expected first** (`testing/f3a0462e`).
- **Test files name the requirement IDs they exercise in a header comment**; a non-obvious branch names the ID that forced it.
- **A repair's test must fail before the repair and pass after, and the failing test *is* the audit.** A repair whose test could not have been written before the audit found the defect is a change of opinion, not a repair (`P10-1`).
- **An audit step's product is a row with a verdict and as-built evidence — a path, a constant, a line range in a filed fence — and never a design document.** The promising phase document says where to look; it is not evidence (`P10-2`).
- **Phase 9's five result statuses, its `Report`, its waiver and `accepted_vacuous:` mechanisms, its three gates and its 61-row map are consumed and not redesigned.** Task 3's two changes are the only exceptions and both are argued there.
- **Ruby facts are verified on every installed interpreter** — `mise exec ruby@<v> -- ruby` — not on one. **Four are installed: 3.2.11, 3.3.12, 3.4.10 and 4.0.6**, which is the whole supported matrix; there is **no `.ruby-version` file in this repository**. Say which interpreters a claim was run on.
- **No `git commit`, `git push` or remote action.** Phase 10 leaves its work in the tree.

---

## File Structure

| File | Responsibility |
|---|---|
| `test/gates/phase10_ruby_facts_test.rb` | Task 1's re-verification of the design's seven facts on all four rows |
| `tools/ledger_audit.rb` | Task 2. Parses design §10's entries and `docs/deviations.md`'s rows; asserts per-row title, position and ID-set equality, and that a confirmed row's evidence resolves |
| `tasks/gates.rake` *(modified)* | `gates:ledger_audit`, `gates:spdx_rbs`, `gates:sole_parse` |
| `Rakefile` *(modified)* | the three names appended to `DEFAULT_GATES`, which is defined here |
| `.github/workflows/ci.yml` *(modified)* | the three names in the `gates` job |
| `tmp/phase10-intake.md` *(generated, not committed)* | Task 3's five-column intake over phase 9's report and gate runs |
| `gems/dexpace-conformance/lib/dexpace/conformance/appendix_b.rb` *(modified)* | Task 3: the per-item ID accessor check 2 needs |
| `gems/dexpace-conformance/test/appendix_b_map_test.rb` *(modified)* | Task 3: per-row ID-set **equality**, replacing "names at least one" |
| `gems/dexpace-conformance/lib/dexpace/conformance/transport_suite.rb` *(modified)* | Task 3: `.run` folded onto `Runner`, the five statuses unchanged |
| `gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/clients.rb` *(verify / modify)* | Task 4: `MAX_ORIGINS`, the drain loop, the close on each evicted client |
| `tools/spdx_rbs.rb` | Task 5's gate body: the SPDX line on every `sig/**/*.rbs`, and no shipped `.rbs` empty of declarations |
| every gem's `sig/**/*.rbs` *(modified)* | Task 5: the one-line header |
| `tools/sole_parse.rb` | Task 6's gate body: `parse_file` only inside `AstScan.parse`'s own method body, with its own descent because `AstScan.receiver_calls` skips an argument-carrying send |
| `.claude/skills/housekeeping/chapters.rb` | Task 7: the clause-scoped chapter-attribution check, the probe's ninth |
| `.claude/skills/housekeeping/probe.rb` *(modified)* | Task 7: registers `chapters` |
| `.claude/skills/housekeeping/test/chapters_test.rb` | Task 7: four fixtures — true positive, negation, continued clause, backticked range |
| `gems/dexpace-core/lib/dexpace/single_use_error.rb` | Task 8: `Dexpace::SingleUseError` |
| `gems/dexpace-core/sig/dexpace/single_use_error.rbs` | Task 8 |
| `gems/dexpace-core/lib/dexpace/sse/stream_state_error.rb` *(modified)* | Task 8: re-parented |
| `gems/dexpace-core/lib/dexpace/page/pages.rb` *(modified)* | Task 8: raises `SingleUseError` |
| `gems/dexpace-transport-async_http/test/dexpace/transport/async_http/xcut12_fiber_test.rb` | Task 9: `XCUT-12` under a reactor through clause 9's `around:` |
| `gems/dexpace-core/lib/dexpace/protocol.rb` *(modified)* | Task 10: `WIRE_FORMS` gains `"http/1.0"` |
| `gems/dexpace-core/lib/dexpace/instrumentation/*.rb` *(YARD only)* | Task 16: the two-factories cross-reference |
| `docs/deviations.md` *(modified)* | Tasks 11–15 move the nineteen rows; Task 17 completes the holding area to the thirteen amendments `C1`–`C13`. Its four rows whose `IDs touched` column was narrower than its §10 entry — 1, 3, 10 and 12 — were widened at planning time, 2026-09-13, with the column's convention written beside the table |
| `docs/first-release.md` *(modified)* | Task 18: one blocker added, two narrowed, three closed, two *ships-without* entries, one trigger added, one closed, one corrected |
| `docs/work/mvp/phase10/…-checklist.md` | Task 19: 188 rows |
| `CLAUDE.md`, `docs/README.md`, the roadmap *(modified)* | Task 19 |
| `docs/knowledge/notes/observability.md` *(modified)* | Task 19 Step 4: one entry |

---

## Requirement-ID → task map

**124 own rows** (108 MUST, 15 SHOULD, 1 MAY), one per ID named by design §10's nineteen entries plus
`RETRY-28` from its closing note. An ID named by more than one entry gets one row, in the earliest
task that audits it; the row names every entry. **Plus 64 cross-reference rows** whose owning phase
keeps the ID.

### The own rows, by task

| Task | §10 entries audited | Own rows | IDs |
|---|---|---|---|
| 11 | §10.1 | 51 | `SEAM-3`–`SEAM-10`; `IO-1`–`IO-42`; `XCUT-23` |
| 12 | §10.2, §10.3, §10.4, §10.5 | 22 | `SEAM-1`, `SEAM-13`, `SEAM-16`, `SEAM-17`, `SEAM-30`; `BODY-1`, `BODY-35`; `PIPE-33`; `RETRY-23`; `CFG-17`, `CFG-20`, `CFG-21`; `TRANSPORT-3`; `ASYNC-1`–`ASYNC-5`; `XCUT-1`–`XCUT-3`; `NFR-11` |
| 13 | §10.6, §10.7, §10.8, §10.9, §10.19 | 13 | `RECOV-12`; `RETRY-34`; `AUTH-14`; `PAGE-13`, `PAGE-15`; `SSE-29`, `SSE-30`, `SSE-36`; `OBS-2`; `XCUT-9`; `NFR-1`, `NFR-8`, `NFR-9` |
| 14 | §10.10, §10.11, §10.12, §10.13, §10.14 | 21 | `SEAM-20`–`SEAM-23`, `SEAM-29`; `HTTP-2`, `HTTP-4`, `HTTP-5`, `HTTP-7`, `HTTP-17`, `HTTP-18`; `BODY-8`, `BODY-37`; `SERDE-5`–`SERDE-8`, `SERDE-16`, `SERDE-17`; `XCUT-15`, `XCUT-18` |
| 15 | §10.15, §10.16, §10.17, §10.18, closing note | 17 | `BODY-32`; `PIPE-16`; `RECOV-34`; `RETRY-26`, `RETRY-28`; `REDIR-11`; `AUTH-29`; `SSE-11`; `OBS-35`; `CFG-1`, `CFG-3`, `CFG-4`, `CFG-15`, `CFG-18`, `CFG-24`, `CFG-26`; `XCUT-13` |

`SEAM-5`–`SEAM-9` and `XCUT-23` are audited in Task 11 (§10.1) and **re-read in Task 13** for §10.8's
own claim about what makes a candidate discoverable; `SEAM-3` is audited in Task 11 and cross-read in
Tasks 12 and 14 for §10.2's and §10.12's claims; `SEAM-20` is audited in Task 14 for §10.12, §10.13
*and* the four-profile claim; `IO-9` and `IO-28` are audited in Task 11 and re-read in Tasks 15 and 14
for §10.18's and §10.10's claims. Every such double appears once as a row and names both entries.

### The own rows, per ID

| ID | Level | §10 entry | Task |
|---|---|---|---|
| `SEAM-1` | MUST | §10.3, §10.7 | 12 |
| `SEAM-3` | MUST | §10.1, §10.2, §10.12 | 11 |
| `SEAM-4` | MUST | §10.1 | 11 |
| `SEAM-5` | MUST | §10.1, §10.8 | 11 |
| `SEAM-6` | MUST | §10.1, §10.8 | 11 |
| `SEAM-7` | MUST | §10.1, §10.8 | 11 |
| `SEAM-8` | SHOULD | §10.1, §10.8 | 11 |
| `SEAM-9` | MUST | §10.1, §10.8 | 11 |
| `SEAM-10` | SHOULD | §10.1, §10.9 | 11 |
| `SEAM-13` | SHOULD | §10.4 | 12 |
| `SEAM-16` | MUST | §10.3 | 12 |
| `SEAM-17` | SHOULD | §10.3 | 12 |
| `SEAM-20` | MUST | §10.12, §10.13 | 14 |
| `SEAM-21` | MUST | §10.12 | 14 |
| `SEAM-22` | MUST | §10.14 | 14 |
| `SEAM-23` | MUST | §10.14 | 14 |
| `SEAM-29` | MUST | §10.10 | 14 |
| `SEAM-30` | MUST | §10.4 | 12 |
| `HTTP-2` | MUST | §10.10 | 14 |
| `HTTP-4` | MUST | §10.10 | 14 |
| `HTTP-5` | MUST | §10.11 | 14 |
| `HTTP-7` | MUST | §10.10 | 14 |
| `HTTP-17` | MUST | §10.10 | 14 |
| `HTTP-18` | MUST | §10.10 | 14 |
| `IO-1` … `IO-8` | MUST | §10.1 | 11 |
| `IO-9` | SHOULD | §10.1, §10.18 | 11 |
| `IO-10` … `IO-15` | MUST | §10.1 | 11 |
| `IO-16` | SHOULD | §10.1 | 11 |
| `IO-17` | MUST | §10.1 | 11 |
| `IO-18` | SHOULD | §10.1 | 11 |
| `IO-19` … `IO-27` | MUST | §10.1 | 11 |
| `IO-28` | MUST | §10.1, §10.10 | 11 |
| `IO-29` … `IO-33` | MUST | §10.1 | 11 |
| `IO-34` | SHOULD | §10.1 | 11 |
| `IO-35` | SHOULD | §10.1 | 11 |
| `IO-36` | MAY | §10.1 | 11 |
| `IO-37` | MUST | §10.1 | 11 |
| `IO-38` | MUST | §10.1 | 11 |
| `IO-39` | SHOULD | §10.1 | 11 |
| `IO-40` … `IO-42` | MUST | §10.1 | 11 |
| `BODY-1` | MUST | §10.2 | 12 |
| `BODY-8` | MUST | §10.12 | 14 |
| `BODY-32` | MUST | §10.18 | 15 |
| `BODY-35` | MUST | §10.2 | 12 |
| `BODY-37` | MUST | §10.10 | 14 |
| `PIPE-16` | MUST | §10.15 | 15 |
| `PIPE-33` | MUST | §10.5 | 12 |
| `RECOV-12` | MUST | §10.6 | 13 |
| `RECOV-34` | MUST | §10.18 | 15 |
| `RETRY-23` | MUST | §10.4 | 12 |
| `RETRY-26` | MUST | §10.17 | 15 |
| `RETRY-28` | MUST | §10 closing note | 15 |
| `RETRY-34` | MUST | §10.6 | 13 |
| `REDIR-11` | MUST | §10.15 | 15 |
| `AUTH-14` | MUST | §10.7 | 13 |
| `AUTH-29` | MUST | §10.15 | 15 |
| `PAGE-13` | MUST | §10.6 | 13 |
| `PAGE-15` | MUST | §10.6 | 13 |
| `SSE-11` | MUST | §10.18 | 15 |
| `SSE-29` | MUST | §10.6 | 13 |
| `SSE-30` | MUST | §10.6 | 13 |
| `SSE-36` | MUST | §10.6 | 13 |
| `SERDE-5` … `SERDE-8` | MUST | §10.14 | 14 |
| `SERDE-16` | MUST | §10.14 | 14 |
| `SERDE-17` | MUST | §10.14 | 14 |
| `OBS-2` | MUST | §10.7 | 13 |
| `OBS-35` | SHOULD | §10.16 | 15 |
| `CFG-1` | MUST | §10.16 | 15 |
| `CFG-3` | MUST | §10.16 | 15 |
| `CFG-4` | MUST | §10.16 | 15 |
| `CFG-15` | MUST | §10.17 | 15 |
| `CFG-17` | MUST | §10.4, §10.17 | 12 |
| `CFG-18` | SHOULD | §10.17 | 15 |
| `CFG-20` | SHOULD | §10.4 | 12 |
| `CFG-21` | MUST | §10.4 | 12 |
| `CFG-24` | MUST | §10.16 | 15 |
| `CFG-26` | MUST | §10.16 | 15 |
| `TRANSPORT-3` | MUST | §10.4 | 12 |
| `ASYNC-1` | MUST | §10.3 | 12 |
| `ASYNC-2` | MUST | §10.3 | 12 |
| `ASYNC-3` | MUST | §10.5 | 12 |
| `ASYNC-4` | MUST | §10.5 | 12 |
| `ASYNC-5` | MUST | §10.4 | 12 |
| `XCUT-1` | MUST | §10.4 | 12 |
| `XCUT-2` | MUST | §10.4 | 12 |
| `XCUT-3` | MUST | §10.4, §10.17 | 12 |
| `XCUT-9` | MUST | §10.6 | 13 |
| `XCUT-13` | MUST | §10.17 | 15 |
| `XCUT-15` | MUST | §10.11 | 14 |
| `XCUT-18` | MUST | §10.10 | 14 |
| `XCUT-23` | MUST | §10.1, §10.8 | 11 |
| `NFR-1` | MUST | §10.7 | 13 |
| `NFR-8` | MUST | §10.19 | 13 |
| `NFR-9` | SHOULD | §10.19 | 13 |
| `NFR-11` | SHOULD | §10.3 | 12 |

The `IO` ranges above are written as ranges only to keep the table readable; the checklist expands
every one to a row of its own, forty-two in all, which is what "one row per requirement ID in scope"
means.

### The cross-reference rows

| IDs | Repair or audit | Task |
|---|---|---|
| `XCUT-14`, `TRANSPORT-13` | the `Clients` cap | 4 |
| `NFR-13`, `NFR-3`, `SERDE-2` | SPDX over `sig/`, and no shipped `.rbs` empty of declarations | 5 |
| `NFR-6`, `NFR-17` | the unused binding, and `parse_file`'s sole caller | 6 |
| `SEAM-15` (`SEAM-13`, `SEAM-22` and `SEAM-29` are own rows and are named here as the attribution's other subjects) | the chapter-attribution check | 7 |
| `PAGE-14`, `SSE-26`, `SSE-40` | `Dexpace::SingleUseError` | 8 |
| `XCUT-12`, `XCUT-11`, `AUTH-35`, `ASYNC-6` | the fiber-scheduler single-flight assertion | 9 |
| `HTTP-24`, `HTTP-43` | `Protocol::WIRE_FORMS` gains `"http/1.0"` | 10 |
| `CTX-14`, `CTX-16`, `CTX-20`, `OBS-21`–`OBS-25`, `OBS-28`, `OBS-29`, `OBS-34`, `SEAM-11`, `SEAM-28`, `PIPE-2`, `PIPE-11`, `PIPE-37` | the two-factories cross-reference and `CTX-16`'s documentation obligation | 16 |
| `HTTP-3`, `HTTP-42`, `HTTP-51`, `BODY-2`, `BODY-15`, `BODY-16`, `OBS-4`, `OBS-5`, `OBS-8`, `OBS-19`, `RETRY-13`, `SSE-19`, `TRANSPORT-2`, `TRANSPORT-4`, `TRANSPORT-8`, `TRANSPORT-14`, `TRANSPORT-17`, `TRANSPORT-18`, `TRANSPORT-19`, `TRANSPORT-25`, `TRANSPORT-29`, `TRANSPORT-30`, `CFG-22`, `CFG-23`, `CFG-25`, `CFG-27`, `CFG-28`, `XCUT-4`, `NFR-2` | the thirteen amendments | 17 |
| `NFR-4`, `TRANSPORT-28` | the release-register walk | 18 |

**188 rows in all** — 124 own and 64 cross-reference. Three of the 64 — `SEAM-15`, `XCUT-11` and
`AUTH-35` — are rows because a phase-10 repair touches them and not because an inbound bullet names them. The checklist is written at execution time, per the roadmap's execution step 6.

---

## Task 1: Re-verify phase 10's seven Ruby facts on all four interpreters

**Files:**
- Create: `test/gates/phase10_ruby_facts_test.rb`
- Create: `test/fixtures/gates/unused_rescue_binding.rb` — the 8a shape, reused by Task 6

**Interfaces:**
- Consumes: phase 0's `DexpaceTestCase` and its `FatalWarnings`; phase 9's `test/support/warning_capture.rb` (`WarningCapture#capture_warnings`), which is why this task writes no second recorder
- Produces: the seven facts, re-measured, and a recorded delta where one has moved

The design's facts were measured on **3.2.11, 3.3.12, 3.4.10 and 4.0.6** during planning. **Two had
already moved** between phase 9's measurement and this design's — Fact 7's Minitest versions, twice —
so this task is not ceremony. A fact that was true in planning and false at implementation time is
what the note mechanism exists to catch.

- [ ] **Step 1: Facts 1 and 5 — the two that decide a repair's shape**

Fact 1: parsing 8a's `rescue ::StandardError => e` shape with `RubyVM::AbstractSyntaxTree.parse_file`
under `-w` warns; inside a `$VERBOSE = nil` window it does not.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Phase 10 Task 1. Re-verifies the design's seven facts. NFR-6, NFR-10, NFR-13, PAGE-14, SSE-26.
require_relative "../test_helper"
require_relative "../support/warning_capture"

class Phase10RubyFactsTest < DexpaceTestCase
  # Fact 1 -- 8a's filed fence warns on every matrix row, and phase 9's window suppresses it.
  def test_unused_rescue_binding_warns_and_the_verbose_window_suppresses_it
    path = fixture_path("gates/unused_rescue_binding.rb")

    warnings = capture_warnings { RubyVM::AbstractSyntaxTree.parse_file(path) }
    assert_equal 1, warnings.size
    assert_includes warnings.first.first, "assigned but unused variable - e"

    quiet = capture_warnings do
      previous = $VERBOSE
      begin
        $VERBOSE = nil
        RubyVM::AbstractSyntaxTree.parse_file(path)
      ensure
        $VERBOSE = previous
      end
    end
    assert_empty quiet
  end

  # Fact 5 -- 7c's spelling really does put a state violation in the argument family.
  def test_rescue_argument_error_catches_an_argument_error_subclass
    subclass = Class.new(::ArgumentError)
    caught = begin
      raise subclass, "second iteration"
    rescue ::ArgumentError => e
      e
    end
    assert_kind_of subclass, caught
    assert_equal %i[ArgumentError StandardError Exception],
                 ::ArgumentError.ancestors.map(&:to_s).map(&:to_sym).select { |s| %i[ArgumentError StandardError Exception].include?(s) }
  end
end
```

- [ ] **Step 2: Confirm Step 1 fails against a tree with the binding already dropped**

Run the first test with a fixture whose `rescue` has no `=> e`. It must report zero warnings and fail
the `assert_equal 1`. That is the proof the fixture, not the interpreter, is what the test measures.
Restore the fixture; the test passes.

- [ ] **Step 3: Facts 2, 3 and 4 — the three about things outside this repository**

Fact 2: `RBS::Parser.parse_signature` accepts a `.rbs` opening with `#` comment lines, on `rbs`
2.8.2 / 3.4.0 / 3.8.0 / 3.10.0. Assert both the header form and the bare form parse; assert the
declaration count is the same either way, which is the property Task 5 needs.

Fact 3: `net/http.rb` contains `Timeout.timeout(@open_timeout, Net::OpenTimeout)` on every row.
**Assert the call, never the line number** — it was 1601 / 1601 / 1657 / 1791 across the four rows at
planning time, and amendment C8's citation is written from this test's output.

Fact 4: the `async-http` closure. This is the one fact that needs a gem install, and it is
**scratchpad-only**: `gem install async-http --install-dir <scratchpad>/gems --no-document`, never
`GEM_HOME` and never the repository. Record the resolved version set and scan every `lib/` in it for
`Timeout.timeout`, `Fiber#raise` and `Thread#kill`. Expected at planning time: 0, 7, 1, with the
`Thread#kill` in `io-event`'s `Selector.process_wait` and the `Fiber#raise` in `async/task.rb:365`
being `Async::Task#cancel`'s delivery mechanism. **Skip, with a recorded reason, on the 3.2 row**:
`async`, `async-http`, `io-event` and `protocol-http1` all declare `required_ruby_version >= 3.3`,
which is 8c's `P8-36` re-verified.

- [ ] **Step 4: Facts 6 and 7 — the two about this repository and this machine**

Fact 6: run Task 7's scanner over `docs/` and record the four numbers — lines naming both, naive line
fires, naive pair fires, clause-scoped fires. At planning time: 38 / 14 / 23 / 3. A change in any of
them means a document was added or corrected since, which is expected; what must not change is that
the clause-scoped count has **zero** false positives, and Step 4 reads each fire to confirm it.

Fact 7: `Gem::Specification.find_all_by_name("minitest")` per row, with each spec's `full_gem_path`
and `default_gem?`, and whether `require "minitest/mock"` succeeds. At planning time: 5.25.1 /
5.20.0 / 6.0.6 / 6.0.0, `default_gem?` false on all four, `minitest/mock` absent on 4.0.6 only, and
13 `already initialized constant` warnings on the 3.4 row when both copies load. **If this has moved
again, Task 18 Step 5 carries the corrected numbers into `docs/first-release.md`'s Minitest trigger.**

- [ ] **Step 5: Run the file on all four interpreters and record the outcome per row**

`for v in 3.2.11 3.3.12 3.4.10 4.0.6; do mise exec ruby@$v -- ruby -w test/gates/phase10_ruby_facts_test.rb; done`.
Every fact that differs from the design's measurement is written into this task's completion note with
both numbers and the date, and — if it changes a decision — routed per the design's *Findings* rules
before any later task reads it.

---

## Task 2: `gates:ledger_audit` — the mechanised half of the re-derivation

**Requirement IDs:** `NFR-17` (cross-reference). The instrument for all 124 own rows.

**Files:**
- Create: `tools/ledger_audit.rb`
- Create: `test/gates/ledger_audit_test.rb`
- Create: `test/fixtures/gates/deviations_wrong_ids.md`, `test/fixtures/gates/deviations_dangling_evidence.md`, `test/fixtures/gates/deviations_ok.md`
- Modify: `tasks/gates.rake`, `Rakefile`, `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `docs/sdk-design-ruby/10-…md` (read-only; frozen) and `docs/deviations.md`
- Produces: `LedgerAudit.offences -> Array[String]`, and `rake gates:ledger_audit`

A register audited once always drifts. Tasks 11–15 move nineteen rows and cite evidence in each; this
gate is what keeps the rows tied to §10 and the evidence resolvable afterwards, and it is the same
per-row equality check Task 3 adds to `APPENDIX_B.md`, applied to the register phase 10 owns.

Three assertions, all decidable:

1. **Position and title.** `docs/deviations.md`'s row *n* has §10 entry *n*'s subject. Matching is on
   the entry's bolded lead sentence with punctuation and emphasis stripped, because the register's
   titles are deliberately shorter than the chapter's sentences; the gate asserts the register title
   is a **prefix-normalised subsequence** of the chapter's, which is decidable and which a renamed
   entry breaks.
2. **ID-set equality.** Row *n*'s `IDs touched` column, expanded (`SEAM-3–SEAM-10` → eight IDs), equals
   the ID set extracted from §10 entry *n*'s text. This is the check that catches an entry gaining or
   losing an ID without the register noticing, and it is what makes the design's count of 124
   reproducible rather than a number in a document. **Equality is only checkable once the column's
   meaning is written down**, and it was not: the register listed the IDs each deviation *narrows*,
   while §10's text also names the IDs it *preserves* — §10.1's whole argument being that `IO-1`–`IO-29`
   and `IO-37`–`IO-42` are implemented in full. So the convention now sits beside the table in
   `docs/deviations.md` ("every requirement ID the §10 entry names — not only the IDs the deviation
   narrows"), and Step 0 below widened the four rows that disagreed with it.
3. **Evidence resolves, for a row with a verdict.** A row whose status is anything but
   `design only — not yet built` must cite at least one `gems/…` path that exists, and every
   `Dexpace::`-qualified constant it names must be defined after `require "dexpace"` and each adapter's
   entry file. A row citing only `docs/…` fails, by design: that is `P10-2`'s rule made mechanical.

- [ ] **Step 0: Widen the four register rows whose ID column was narrower than its chapter entry** —
      *done at planning time, 2026-09-13; this step is the record and the re-check*

Running the gate body below against the register as it stood produced **four** offences, and all four
were the same defect: the column listed the narrowed subset. Row 1 was short 34 `IO` IDs
(`IO-1`–`IO-29`, `IO-37`, `IO-38`, `IO-40`–`IO-42`), row 3 short `SEAM-1` and `NFR-11`, row 10 short
`HTTP-17`, `HTTP-18` and `XCUT-18`, row 12 short `SEAM-20`. All four were widened to their entry's full
named set on 2026-09-13, and the column's convention was written beside the table in the same change,
because a gate that asserts a rule nobody stated is a gate that will be argued with. **Re-check rather
than redo:** run the gate and confirm 0 offences; if it reports any, §10 or the register has moved since
and the row is a finding, not a chore.

- [ ] **Step 1: Write the failing test first, with all three fixtures**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Phase 10 Task 2. gates:ledger_audit keeps docs/deviations.md tied to design section 10. NFR-17.
require_relative "../test_helper"
require_relative "../../tools/ledger_audit"

class LedgerAuditTest < DexpaceTestCase
  def test_a_row_whose_id_set_differs_from_the_chapter_entry_is_an_offence
    offences = LedgerAudit.offences(register: fixture_path("gates/deviations_wrong_ids.md"))
    assert_equal 1, offences.size
    assert_includes offences.first, "row 1"
    assert_includes offences.first, "IO-30"       # present in the chapter, absent from the row
  end

  def test_a_verdict_row_citing_no_resolvable_evidence_is_an_offence
    offences = LedgerAudit.offences(register: fixture_path("gates/deviations_dangling_evidence.md"))
    assert_equal 1, offences.size
    assert_includes offences.first, "no resolvable as-built evidence"
  end

  def test_the_conforming_fixture_is_clean
    assert_empty LedgerAudit.offences(register: fixture_path("gates/deviations_ok.md"))
  end

  # The live register. Before Tasks 11-15 every row reads "design only -- not yet built", so
  # assertion 3 is vacuous for all nineteen and 1 and 2 must still hold.
  def test_the_live_register_is_clean
    assert_empty LedgerAudit.offences
  end
end
```

- [ ] **Step 2: Confirm it fails — `tools/ledger_audit.rb` does not exist**

`mise exec ruby@3.4.10 -- ruby -w test/gates/ledger_audit_test.rb` raises `LoadError`. That is the
failure; four tests, none of them reached.

- [ ] **Step 3: Implement `tools/ledger_audit.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Re-derivation gate for phase 10. Asserts docs/deviations.md's nineteen rows still describe design
# section 10's nineteen entries -- same position, same subject, same ID set -- and that a row carrying
# a verdict cites as-built evidence that resolves. P10-2: a design document is never evidence, so a
# row citing only docs/ paths fails assertion 3.
module LedgerAudit
  PREFIXES = %w[SEAM HTTP IO BODY CTX PIPE RECOV RETRY REDIR AUTH PAGE SSE SERDE OBS CFG
                TRANSPORT ASYNC XCUT NFR].freeze
  CHAPTER = "docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md"
  REGISTER = "docs/deviations.md"
  UNBUILT = "design only — not yet built"

  class << self
    def offences(chapter: CHAPTER, register: REGISTER)
      entries = chapter_entries(File.read(chapter))
      rows = register_rows(File.read(register))
      out = []
      out << "row count #{rows.size} != chapter entry count #{entries.size}" if rows.size != entries.size
      entries.each_with_index do |entry, i|
        row = rows[i] or next
        out.concat(compare(i + 1, entry, row))
      end
      out
    end

    private

    # Each entry is "N. **Subject.** ... *Touches* IDs ..." up to the next "N. **".
    def chapter_entries(text)
      text.scan(/^(\d+)\.\s+\*\*(.+?)\*\*(.*?)(?=^\d+\.\s+\*\*|\nTwo things that are deliberately)/m)
          .map { |_n, subject, body| { subject: normalise(subject), ids: ids_in(subject + body) } }
    end

    def register_rows(text)
      text.lines.grep(/^\|\s*\d+\s*\|/).map do |line|
        cells = line.split("|").map(&:strip)
        { subject: normalise(cells[2].to_s), ids: ids_in(cells[3].to_s), status: cells[4].to_s,
          evidence: cells[3].to_s + cells[4].to_s }
      end
    end

    def compare(n, entry, row)
      out = []
      out << "row #{n} subject drifted from the chapter entry" unless subsequence?(row[:subject], entry[:subject])
      missing = entry[:ids] - row[:ids]
      extra = row[:ids] - entry[:ids]
      out << "row #{n} ID set differs: chapter-only #{missing.join(', ')}" unless missing.empty?
      out << "row #{n} ID set differs: row-only #{extra.join(', ')}" unless extra.empty?
      out.concat(evidence_offences(n, row)) unless row[:status].include?(UNBUILT)
      out
    end

    def evidence_offences(n, row)
      paths = row[:evidence].scan(%r{gems/[\w./-]+}).select { |p| File.exist?(p) }
      return ["row #{n} carries a verdict and no resolvable as-built evidence"] if paths.empty?

      row[:evidence].scan(/\bDexpace(?:::[A-Z]\w*)+/).uniq.reject { |c| defined_constant?(c) }
                    .map { |c| "row #{n} names #{c}, which is not defined" }
    end

    def defined_constant?(path)
      path.split("::").drop(1).reduce(::Object.const_get(:Dexpace)) { |mod, seg| mod.const_get(seg, false) }
      true
    rescue ::NameError
      false
    end

    def ids_in(text)
      out = []
      plain = text.gsub(/[`*]/, "")
      plain.scan(/\b([A-Z]+)-(\d+)\s*[–—]\s*([A-Z]+)-(\d+)\b/) do |p, a, q, b|
        (a.to_i..b.to_i).each { |i| out << "#{p}-#{i}" } if p == q && PREFIXES.include?(p)
      end
      plain.scan(/\b([A-Z]+)-(\d+)\b/) { |p, i| out << "#{p}-#{i}" if PREFIXES.include?(p) }
      out.uniq.sort
    end

    def normalise(s) = s.gsub(/[`*]/, "").downcase.gsub(/[^a-z0-9 ]/, " ").split.join(" ")

    # A register title is deliberately shorter than the chapter's sentence, so equality is the wrong
    # test; a word subsequence is decidable and a renamed entry still breaks it.
    def subsequence?(short, long)
      words = long.split
      short.split.all? { |w| (idx = words.index(w)) && words = words.drop(idx + 1) }
    end
  end
end
```

- [ ] **Step 4: Confirm the three fixtures and the live register behave as asserted**

All four tests pass on all four interpreters. The live-register test is the load-bearing one, and the
transition it asserts is exact: **four offences against the register as it stood on 2026-09-05, zero
after Step 0's widening.** Every row still reads `design only — not yet built`, so assertion 3 is
vacuous for all nineteen and assertions 1 and 2 carry the whole check — which is a real check of the
design's ID extraction against the register, and the reason the four rows were widened at planning time
rather than left for this step to discover. Anyone re-deriving the before-state can do it from git:
the four offences are reproducible against `HEAD`'s `docs/deviations.md`.

- [ ] **Step 5: Wire it, blocking**

`tasks/gates.rake` gains `gates:ledger_audit`, which aborts with the offence list. `Rakefile` appends
`"gates:ledger_audit"` to `DEFAULT_GATES` **before** the `.freeze`. `.github/workflows/ci.yml` adds it
to the `gates` job, because phase 0's `ci_workflow_test.rb` asserts every `DEFAULT_GATES` entry appears
in some job. Run `bundle exec rake gates:ledger_audit` and `ruby -w test/gates/ci_workflow_test.rb`.

---

## Task 3: Read phase 9's report once, and close its two instrument residues

**Requirement IDs:** `NFR-17` (cross-reference); every ID the intake routes.

**Files:**
- Create: `tmp/phase10-intake.md` (generated, not committed)
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance/appendix_b.rb`
- Modify: `gems/dexpace-conformance/test/appendix_b_map_test.rb`
- Modify: `gems/dexpace-conformance/lib/dexpace/conformance/transport_suite.rb`
- Modify: `gems/dexpace-conformance/test/dexpace/conformance/transport_suite_test.rb`

**Interfaces:**
- Consumes: phase 9's `Aggregate.run` / `.render`, `Report#to_h`, `#blocking_vacuities`,
  `#accepted_vacuities`, `#waived`, `Aggregate.by_requirement_id`; `gems/dexpace-conformance/APPENDIX_B.md`;
  the offence lists of `gates:cause_walk`, `gates:bounded_map`, `gates:seam_names`, `gates:serde_boundary`
- Produces: the intake table every one of Tasks 4–18 reads instead of re-reading the report

- [ ] **Step 1: Run the aggregate and the four gates, and stop if the report is blocked**

`bundle exec rake` on 3.4.10, then per matrix row. Capture `Report#to_h`. **If `blocking_vacuities`
is non-empty, resolve those first** — each is either an absent artifact or a missing
`accepted_vacuous:` citation, and neither is a verdict phase 10 may act on. Phase 9's own expected end
state is red on `gates:bounded_map` and green elsewhere; anything else is recorded with both the
expectation and the observation.

- [ ] **Step 2: Build `tmp/phase10-intake.md`, five columns, one row per finding**

`| source | ID(s) | status | what was measured | disposition |`, where *source* is the assertion name
or gate, *status* is one of phase 9's five plus `gate offence`, and *disposition* is a phase-10 task
number, a `docs/first-release.md` section, or `no repair — <evidence>`. The design's `R3` table is the
mapping; apply it mechanically and record any row it does not cover rather than improvising one.

**Two rules the step must not break.** An `:error` is never a finding against the audited gem — it is a
`dexpace-conformance` defect, and phase 9's plan warns that treating one otherwise is "a false finding
phase 10 would act on". A gate offence is repaired, never allowlisted: "The fix is not an allowlist
entry."

- [ ] **Step 3: Re-measure the two waivers the first-party build carries**

`TRANSPORT-14`'s (8c's `P8-38`: a control/non-ASCII byte in a header **name** raises
`Protocol::HTTP1::BadHeader` out of the read) and `ASYNC-3`'s (§10.5). Both are decisions recorded
elsewhere, and `R4` says a waiver that no longer states the truth is a finding whose repair is removing
the waiver. Drive 8c's own `TCPServer` fixture emitting `X-B\xE9d: v` against the resolved
`protocol-http1`; record the class raised and where. `ASYNC-3`'s waiver rests on §8.3, not on a
library, so re-reading §8.3 and 8b's as-built worker path is the measurement.

- [ ] **Step 4: `APPENDIX_B.md`'s check 2 — write the failing test, then the accessor**

The failing test first: a fixture map row whose ID column omits one ID its appendix-B item names must
be an offence, and today it is not.

```ruby
def test_a_row_whose_id_set_differs_from_its_item_is_an_offence
  offences = AppendixBMap.offences(map: fixture_path("appendix_b_missing_id.md"))
  assert_equal 1, offences.size
  assert_includes offences.first, "B.8 item 3"
  assert_includes offences.first, "XCUT-14"     # named by the item, absent from the row
end
```

Then `AppendixB.item_ids(section:, index:) -> Array[String]`, parsing the item's own text with the
**nineteen-prefix** regex phase 9 fixed (a bare `[A-Z]+-\d+` matches `ISO-8601`, which is in `B.3`'s
real text), and the map test's assertion changes from "names at least one ID" to **set equality**.
Phase 9's design argues this is "decidable, strictly stronger, and makes the distinct-ID coverage check
hold by construction" (its design `:1243-1245`), and the filed test asserts only membership — **phase 9
plan `:5627-5631`**, inside the class at `:5611-5644`.

**State the gap at its real size, not larger.** `AppendixB` is not featureless here: it already exposes
`ids_in(text)` (`:5668`) and `spec_items(path)` (`:5732-5741`), and `generate` already computes each
item's IDs at `:5722` and writes them into the rows it generates. What is missing is an accessor **in
the form the equality check needs** — per section and index — plus the assertion itself; and because
`generate` carries hand-written rows over verbatim (`:5726`), the drift the check would catch is
confined to those. So this is one accessor and one assertion over a bounded population, which is why
`R3` permits it at all: a wider change to phase 9's instrument would make phase 10's verdicts
inseparable from its own tooling.

- [ ] **Step 5: Fold `TransportSuite.run` onto `Runner`, statuses asserted unchanged**

Write the assertion first: for a hand-built set of five subjects — one passing, one raising `Failure`,
one raising `Vacuous`, one waived by ID, one raising a bare `StandardError` — `TransportSuite.run`'s
report must carry exactly `%i[passed failed vacuous waived error]`. Confirm it passes **before** the
refactor (it is the invariant), refactor `.run` to delegate to `Runner.run(assertions, waive:, around:,
accepted_vacuous:) { subject }`, and confirm it still passes. `P9-10` is the residue this closes —
"a future change to the five statuses must be made twice" — and phase 8's ownership was its only cause.

- [ ] **Step 6: Re-run the full gate set and record the delta**

`bundle exec rake` on all four rows. The two conformance changes must move nothing but the two
assertions they add; if a suite's status distribution changes, that is a finding about the suite and it
goes in the intake.

---

## Task 4: `XCUT-14` — the per-origin client cache is bounded, and stays bounded

**Requirement IDs:** `XCUT-14` (MUST, cross-reference; phase 9 owns the row), `TRANSPORT-13`, `NFR-17`.

**Files:**
- Modify (or verify): `gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/clients.rb`
- Modify: `gems/dexpace-transport-async_http/test/dexpace/transport/async_http/clients_test.rb`

**Interfaces:**
- Consumes: `Endpoints.origin_for(url)`; `Dexpace.close_quietly`; `Clients#fetch`, `#close`
- Produces: `Clients::MAX_ORIGINS`, an insert that drains back to the cap in a **loop**, and a
  `close_quietly` on each evicted client's pool

Inbound bullets 6 and 10. The 2026-09-13 amendment expects this to be **moot**: 8c's plan Task 8 bounds
the map at planning time. The bullet stays on the list "until a green `gates:bounded_map` run says so",
which is what this task produces — and `R4`'s rule is that a sentence in a plan is not evidence that
the work was done.

- [ ] **Step 1: Measure what shipped, before writing anything**

Read the as-built `clients.rb`. Record: whether a cap constant exists and its value; whether eviction
is a **loop** or a single pre-insert check-then-evict (`XCUT-14` requires the loop in as many words);
whether each evicted client's pool is closed, since the values own pools; and whether `#close` leaves
the map populated. Then run `bundle exec rake gates:bounded_map`.

- [ ] **Step 2: If the gate is green and all four properties hold — no repair**

Record the row as **no repair needed**, with the four measurements and the green run as the evidence,
and close `docs/first-release.md`'s `gates:bounded_map` blocker in Task 18. **Do not add an allowlist
entry**, and do not "tidy" the shipped implementation: a repair with no defect is the drift `P10-1`
exists to stop. Skip to Step 5.

- [ ] **Step 3: If the gate is red — write the two failing tests**

```ruby
# XCUT-14: a bounded map, drained back to the cap in a loop after each insert, with each evicted
# value's pool closed -- the values own pools, so eviction without a close leaks a connection pool.
def test_the_origin_cache_never_exceeds_its_cap
  clients = Dexpace::Transport::AsyncHTTP::Clients.new
  (Dexpace::Transport::AsyncHTTP::Clients::MAX_ORIGINS + 5).times do |i|
    clients.fetch(URI::RFC3986_PARSER.parse("https://h#{i}.example/"))
  end
  assert_equal Dexpace::Transport::AsyncHTTP::Clients::MAX_ORIGINS, clients.size
end

def test_an_evicted_client_has_its_pool_closed
  closed = []
  clients = Dexpace::Transport::AsyncHTTP::Clients.new(factory: ->(_o) { recording_client(closed) })
  (Dexpace::Transport::AsyncHTTP::Clients::MAX_ORIGINS + 1).times do |i|
    clients.fetch(URI::RFC3986_PARSER.parse("https://h#{i}.example/"))
  end
  assert_equal 1, closed.size
end
```

The first asserts the cap; the second asserts the close on eviction, which the cap alone does not give.
Phase 9's deterministic drain-loop assertion (`InvariantSuite`'s `bounded_map_drains`, pre-fill to
cap + 5 then one `set`, ending at 8 for a loop and 13 for a check-then-evict) is the third line and is
already written — this task does not duplicate it.

- [ ] **Step 4: Confirm both fail, implement, confirm both pass**

The cap follows 8c's own precedent for its other caller-keyed map, `DropPolicy::MAX_TRACKED_NAMES` at
64 distinct names for `TRANSPORT-13`, which is why bullet 6 calls the omission "an omission rather than
a decision". Drain in a `while` loop after each insert; `Dexpace.close_quietly` each evicted client's
pool; have `#close` clear the map as well as close the values.

- [ ] **Step 5: Any *other* `gates:bounded_map` offence is a new adjudication, not a chore**

Phase 9 recorded **six offences in five files** over 222 filed fences at 184 distinct `lib/` paths;
five of the six are false positives carrying their reason, filed under **four** keys in
`InvariantGates::BOUNDED_MAP_ALLOWED` — the list is keyed by path and `configuration.rb` supplies two of
the five — and the sixth is `Clients#@by_origin`, this task's subject. A seventh offence is decided
against that file's own code: either the
map's lifetime makes a cap impossible-to-be-the-backstop (`XCUT-14`'s own last clause — the owner is
dropped after one operation), in which case an allowlist entry with that argument written out, or it is
a defect, in which case a cap. Phase 9 priced the wrong answer: "past a dozen entries the gate is
reporting that the invariant is not held."

---

## Task 5: `NFR-13` — the SPDX header reaches `sig/`, and no shipped signature is empty

**Requirement IDs:** `NFR-13` (SHOULD, cross-reference; phase 9 owns the row), `NFR-3`, `SERDE-2`, `NFR-17`.

**Files:**
- Create: `tools/spdx_rbs.rb`
- Create: `test/gates/spdx_rbs_test.rb`
- Create: `test/fixtures/gates/sig_missing_header.rbs`, `test/fixtures/gates/sig_empty.rbs`, `test/fixtures/gates/sig_ok.rbs`
- Modify: every `gems/*/sig/**/*.rbs`
- Modify: `tasks/gates.rake`, `Rakefile`, `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `RBS::Parser.parse_signature` (Fact 2), `RBS::Buffer`
- Produces: `SpdxRbs.offences -> Array[String]`, `rake gates:spdx_rbs`

Inbound bullets 8 and 26. `NFR-13`'s conformance clause is "scan **all source files** for the required
header"; phase 0 mechanised it as a RuboCop cop, and `.rbs` is not Ruby, so `sig/` — which mirrors
`lib/` one file per file and **ships inside each gem** — is shipped source with no header and no gate.
Phase 9's `PackagingSuite` asserts the header's **presence** deliberately, so it reports `:failed`
today and passes the day this task lands.

Bullet 26 rides along because this is the only task that opens every `.rbs`: 7a settled
`sig/dexpace/serde.rbs`'s `#media_type` clause and handed forward the question of whether phase 2's
**four other** declared signature files are empty too, which no gate can see.

- [ ] **Step 1: Write the failing test, three fixtures**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Phase 10 Task 5. NFR-13's header on shipped signatures; NFR-3/SERDE-2's declared-but-empty residue.
require_relative "../test_helper"
require_relative "../../tools/spdx_rbs"

class SpdxRbsTest < DexpaceTestCase
  def test_a_signature_without_the_header_is_an_offence
    offences = SpdxRbs.offences(paths: [fixture_path("gates/sig_missing_header.rbs")])
    assert_equal 1, offences.size
    assert_includes offences.first, "SPDX-License-Identifier"
  end

  def test_a_signature_with_no_declarations_is_an_offence
    offences = SpdxRbs.offences(paths: [fixture_path("gates/sig_empty.rbs")])
    assert_equal 1, offences.size
    assert_includes offences.first, "declares nothing"
  end

  def test_the_conforming_fixture_is_clean
    assert_empty SpdxRbs.offences(paths: [fixture_path("gates/sig_ok.rbs")])
  end

  def test_every_shipped_signature_is_clean
    assert_empty SpdxRbs.offences
  end
end
```

- [ ] **Step 2: Confirm the last test fails against the tree as phase 9 left it**

It must report one offence per shipped `.rbs`, which by phase 8 is roughly as many files as `lib/`
has. That count is the finding, recorded in this task's note.

- [ ] **Step 3: Implement the gate**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# NFR-13's conformance clause says "all source files" and sig/ ships inside every gem, so the
# signatures are shipped source. A RuboCop cop cannot reach them: .rbs is not Ruby. Verified on
# rbs 2.8.2 / 3.4.0 / 3.8.0 / 3.10.0 -- a leading "#" comment parses and changes no declaration, so
# the header is one line. frozen_string_literal has no meaning in RBS, which is why it is not two.
require "rbs"

module SpdxRbs
  HEADER = "# SPDX-License-Identifier: MIT"

  def self.offences(paths: Dir["gems/*/sig/**/*.rbs"].sort)
    paths.flat_map do |path|
      out = []
      source = File.read(path)
      out << "#{path}: line 1 is not #{HEADER}" unless source.lines.first&.chomp == HEADER
      buffer = RBS::Buffer.new(name: Pathname(path), content: source)
      out << "#{path}: declares nothing" if RBS::Parser.parse_signature(buffer).flatten.compact.empty?
      out
    rescue RBS::ParsingError => e
      ["#{path}: does not parse -- #{e.message}"]
    end
  end
end
```

`RBS::Parser.parse_signature` returns a three-element array on modern `rbs` and an array of
declarations on 2.8.2; `.flatten.compact.empty?` is true for a file with no declarations on both, which
Task 1 Step 3 asserts rather than assumes.

- [ ] **Step 4: Add the header to every shipped signature, and fix every empty one**

Mechanical for the header — prepend one line and one blank line. **Not** mechanical for an empty
signature: each is a declared-and-unwritten file, and writing it means writing the types the promising
phase document described. Record each one, its promising document and line, and the types written.
Phase 2's `sig/dexpace/serde.rbs` is the known case ("carries `interface _Codec` with the six methods
and the module's class methods", and gives no types); 7a settled `#media_type`'s.

- [ ] **Step 5: Confirm all four tests pass, then wire it blocking**

`rbs validate` and `steep check` must still pass — Fact 2 says the header changes no declaration, and
this is where that is confirmed against the real tree rather than a fixture. Append `"gates:spdx_rbs"`
to `DEFAULT_GATES` in the `Rakefile`, add it to the `gates` CI job, run `ci_workflow_test.rb`.

- [ ] **Step 6: Re-run phase 9's `PackagingSuite`**

Its `spdx_header_coverage` assertion was `:failed` and must now be `:passed` — "which is the direction
a gate should move under its own repair". Record the transition; Task 19 marks `NFR-13`'s
cross-reference row and cites phase 9's row.

---

## Task 6: `gates:sole_parse` — `AstScan.parse` is the only caller of `parse_file`

**Requirement IDs:** `NFR-6` (SHOULD, cross-reference), `NFR-17`.

**Files:**
- Create: `tools/sole_parse.rb`, `test/gates/sole_parse_test.rb`
- Create: `test/fixtures/gates/rogue_parse_file.rb` (a direct `parse_file(path)` — argument-carrying),
  `test/fixtures/gates/rogue_parse_file_send.rb` (`send(:parse_file, path)`)
- Keep: `test/fixtures/gates/unused_rescue_binding.rb` (Task 1's fixture, reused here)
- Modify: `tools/ast_scan.rb` (its header comment's stale citation only — Step 5)
- Modify: `tasks/gates.rake`, `Rakefile`, `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: phase 9's `AstScan.parse`, `AstScan::SEND_TYPES`, `::SYMBOL_TYPES`, `::REFLECTIVE_SENDS`
  and its `walk`/`method_name` helpers. **Not `AstScan.receiver_calls`** — the reason is decided below
- Produces: `SoleParse.offences`, `rake gates:sole_parse`

Inbound bullet 7, **second half only. The first half is already closed and this task does not re-do
it.** 8a's `Adapter#dispatch` no longer carries `rescue ::StandardError => e`: its fence reads
`rescue ::StandardError` at that plan's `:5177`, and the plan records the repair itself at `:6337-6339`
("the binding is gone"), made by commit **152ec6a** before phase 10 began. The bullet's citation,
`:4858`, now points at `body = res.body_string`. So there is no lint finding left to repair, and a
repair with no defect is the drift `P10-1` exists to stop.

**What outlives it is the generalisation**, which nothing has ever asserted: any repository tool that
parses a filed source under the warnings-fatal test case has the same exposure, and "nothing else in
this file may call `parse_file` directly" is a **comment** in `tools/ast_scan.rb`, not an assertion.
`AstScan.parse` is the one place that opens a `$VERBOSE = nil` window restored in `ensure`, and Task 1's
`unused_rescue_binding.rb` fixture is kept precisely to prove that window still works — it is the
artifact that makes the gate's reason legible after the defect that motivated it is gone.

- [ ] **Step 1: Write the failing test, one rogue fixture and the repository as the positive control**

```ruby
def test_a_parse_file_send_with_an_argument_outside_the_owner_method_is_an_offence
  offences = SoleParse.offences(paths: [fixture_path("gates/rogue_parse_file.rb")])
  assert_equal 1, offences.size
  assert_includes offences.first, "parse_file"
end

def test_a_reflective_parse_file_send_is_also_an_offence
  offences = SoleParse.offences(paths: [fixture_path("gates/rogue_parse_file_send.rb")])
  assert_equal 1, offences.size
end

def test_the_repository_has_exactly_one_caller
  assert_empty SoleParse.offences
end
```

The first test is the one that decides the gate's shape: **the rogue fixture's call carries an
argument**, because every real `parse_file` call does — `RubyVM::AbstractSyntaxTree.parse_file(path)`.
A gate that only saw argument-free sends would pass over its own subject.

- [ ] **Step 2: Confirm all three fail — `tools/sole_parse.rb` does not exist**

- [ ] **Step 3: Implement the gate with its own walk, and not on `receiver_calls`**

**Decision, because it looks like duplication and is not.** `AstScan.receiver_calls(path, names)` is
phase 9's and records a direct-name hit **only when the call carries no arguments** — `hits << [path,
node.first_lineno, called] if arguments(node).nil?` (phase 9 plan `:5219`), a narrowing added
deliberately so 5b's filed `Event#cause(error)` builder would not redden `gates:cause_walk`. Every
`parse_file` call carries a path, so `receiver_calls` reports none of them; it also returns
`[path, line, name]` **triples** rather than nodes, which is the second reason a body written against it
would not run. Widening it would change an interface phase 9 owns, which `R3` forbids. So this gate
walks `AstScan.parse`'s tree itself, reusing phase 9's node vocabulary and adding nothing to it.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# AstScan.parse opens a $VERBOSE = nil window around parse_file, because a SCANNED file's own
# diagnostics route through Warning.warn and fire phase 0's FatalWarnings. The rule that keeps that
# the single entry point was a comment in tools/ast_scan.rb; this is the assertion. Deliberately NOT
# built on AstScan.receiver_calls: that helper skips a send carrying arguments (phase 9 plan:5219, a
# narrowing for #cause), and every parse_file call carries a path -- so it reports none of them.
# A Symbol literal is :LIT on 3.2 and :SYM on 3.4/4.0 -- both are named through AstScan::SYMBOL_TYPES,
# per docs/knowledge/notes/cross-cutting-invariants.md -- so the reflective forms are caught on every row.
require_relative "ast_scan"

module SoleParse
  TREES = ["tools/**/*.rb", "tasks/**/*.rake", "test/gates/**/*.rb", ".claude/skills/**/*.rb"].freeze
  TARGET = :parse_file
  OWNER_FILE = "tools/ast_scan.rb"
  OWNER_METHOD = :parse

  def self.offences(paths: TREES.flat_map { |glob| Dir[glob] }.sort)
    paths.flat_map { |path| offences_in(path) }
  end

  # The exemption is the OWNER METHOD, not the owner file: "nothing else in this file may call
  # parse_file directly" is exactly the rule, and a file-wide exemption cannot enforce it.
  def self.offences_in(path)
    owner = path == OWNER_FILE
    sends(AstScan.parse(path), owner: owner)
      .map { |line| "#{path}:#{line}: parse_file outside AstScan.#{OWNER_METHOD} (NFR-6)" }
  end

  # Depth-first, carrying the owner flag down, so a block nested inside AstScan#parse is still
  # inside it. `Node#children` is Ruby's own API; nothing here needs a new AstScan helper.
  def self.sends(node, owner:, inside_owner: false, out: [])
    inside = inside_owner || (owner && defines_owner?(node))
    out << node.first_lineno if !inside && targets?(node)
    node.children.grep(::RubyVM::AbstractSyntaxTree::Node)
        .each { |child| sends(child, owner: owner, inside_owner: inside, out: out) }
    out
  end

  # :DEFN carries the method name first; :DEFS (`def self.parse`) carries the receiver first.
  def self.defines_owner?(node)
    case node.type
    when :DEFN then node.children[0] == OWNER_METHOD
    when :DEFS then node.children[1] == OWNER_METHOD
    else false
    end
  end

  def self.targets?(node)
    return false unless AstScan::SEND_TYPES.include?(node.type)
    return true if AstScan.method_name(node) == TARGET

    AstScan::REFLECTIVE_SENDS.include?(AstScan.method_name(node)) &&
      AstScan.symbol_argument(node) == TARGET
  end
end
```

Three notes on the shape. **Everything it borrows from `AstScan` already exists and is already public**
— `parse`, `method_name`, `symbol_argument`, `SEND_TYPES`, `SYMBOL_TYPES` and `REFLECTIVE_SENDS`, all
public singleton methods or constants under that module's `module_function` — and it adds nothing to
that module, which is what keeps `R3` true. It deliberately does **not** use `AstScan.walk`, whose flat
traversal cannot tell the scanner whether it is inside a method body; the descent is this task's own and
uses `Node#children`, Ruby's own API. The **`DEFN`/`DEFS` branch is what makes the exemption
method-scoped**, matching the design's addendum `A9` ("failing on any `parse_file` send outside
`AstScan.parse`'s own method body") rather than exempting the whole file — which matters, because the
rule the comment states is about the *file's other methods* and a file-wide exemption cannot enforce
it.

**Stated gap, written into the gate's own output**: `send(variable)` is statically undecidable, which
is the same residue phase 9 wrote down for `gates:cause_walk`. Both `:LIT` and `:SYM` are named via
`AstScan::SYMBOL_TYPES`, because a `:LIT`-only scan catches 6 of 7 reflective shapes on the floor and 2
of 7 on the newer rows.

- [ ] **Step 4: Confirm all three pass on all four rows, then wire it blocking**

`AstScan.parse`'s own `#parse` method body is the one exemption and it is a method, not a list. Append
`"gates:sole_parse"` to `DEFAULT_GATES` in the `Rakefile`, add it to the `gates` CI job, and run
`ruby -w test/gates/ci_workflow_test.rb`.

- [ ] **Step 5: Prove the `$VERBOSE` window the gate exists to protect still works**

Parse `test/fixtures/gates/unused_rescue_binding.rb` through `AstScan.parse` under `-w` and assert **no
warning escapes**, and through a bare `RubyVM::AbstractSyntaxTree.parse_file` and assert one
`assigned but unused variable - e` does. That contrast is what the fixture is for now that 8a's fence no
longer carries the binding: it keeps the gate's reason checkable instead of leaving a gate whose
motivating defect has vanished from the tree.

**And correct the one citation this task inherits.** `tools/ast_scan.rb`'s own header comment, as phase 9
filed it (phase 9 plan `:5185`), cites "8a plan:4858" for the unused `e` — the same citation bullet 7
carried and the same one that no longer resolves. This task is the only one that opens that file, so it
repoints the comment at 8a plan `:5177` and at commit 152ec6a's correction, and keeps the *mechanism*
sentence exactly as phase 9 wrote it: the window exists because a scanned file's own `-w` diagnostics
reach `Warning.warn`, and that is true whether or not any filed fence currently emits one.


## Task 7: the probe's ninth check — chapter attribution, clause-scoped

**Requirement IDs:** none of its own; it mechanises `CLAUDE.md`'s requirement-ID conventions. `SEAM-15` and `NFR-17` are its cross-reference rows; `SEAM-13`, `SEAM-22` and `SEAM-29` are named here as the attribution's other subjects and are **own** rows (Tasks 12 and 14).

**Files:**
- Create: `.claude/skills/housekeeping/chapters.rb`
- Create: `.claude/skills/housekeeping/test/chapters_test.rb`
- Modify: `.claude/skills/housekeeping/probe.rb`, `.claude/skills/housekeeping/test/run.rb`
- Create: `test/fixtures/chapters/` — four fixtures, of which two carry the pre-correction text of
  `phase8a-…-design.md:67` and `phase8c-…-design.md:69` verbatim, as regression fixtures. **Both
  documents were corrected on 2026-09-13 by phase 10's planning**, so the check's evidence is the
  fixtures and not a live defect
- Modify: `.claude/skills/housekeeping/SKILL.md` and `CLAUDE.md`'s "Eight checks" sentences — **nine**

**Interfaces:**
- Consumes: the probe's `Repo` reader and its `Finding` shape; `docs/product-spec/*.md`
- Produces: `Chapters#findings`, registered as the probe's ninth check, and three corrected attributions

Inbound bullet 3, built from Fact 6's measurement rather than from the bullet's stated job description
— which asks for a claim-verb grammar and **matches 0 of the 38 live candidates**, because the shape
these claims take is a bare governing-documents list.

- [ ] **Step 1: Write the four fixtures and their assertions first**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Phase 10 Task 7. The clause-scoped chapter-attribution check. Measured over docs/ on 2026-09-13:
# 38 lines name both a chapter and an ID; a naive same-line rule fires on 14 lines / 23 pairs with 4
# true positives; this form fires 3 times with 0 false positives. Two blind spots are asserted here so
# the check never claims to have seen what it did not.
class ChaptersTest < HousekeepingTestCase
  def test_a_governing_documents_list_naming_an_appendix_c_only_id_is_a_finding
    findings = run_chapters("`docs/product-spec/03-pluggable-seams-and-extension-model.md` for `SEAM-11`, `SEAM-15`.")
    assert_equal 1, findings.size
    assert_includes findings.first.message, "SEAM-15"
  end

  def test_prose_whose_subject_is_the_absence_is_not_a_finding
    assert_empty run_chapters(
      "`docs/product-spec/03-pluggable-seams-and-extension-model.md` carries 22 of the 30 `SEAM` IDs; " \
      "`SEAM-15` and `SEAM-22` appear nowhere in the specification's prose."
    )
  end

  def test_a_backticked_range_is_expanded          # 8a:67 hides SEAM-13 inside `SEAM-11`-`SEAM-15`
    findings = run_chapters("`docs/product-spec/03-pluggable-seams-and-extension-model.md` for `SEAM-11`–`SEAM-15`.")
    assert_equal %w[SEAM-13 SEAM-15], findings.map { |f| f.message[/SEAM-\d+/] }.sort
  end

  def test_a_clause_continued_onto_the_next_line_is_a_stated_blind_spot
    findings = run_chapters("- `docs/product-spec/03-pluggable-seams-and-extension-model.md` —\n  `SEAM-15`.")
    assert_empty findings
    assert_includes Housekeeping::Chapters::GAPS, :continued_clause
  end
end
```

The fourth is the important one: it asserts the check **does not** fire and that the gap is declared.
A check that silently misses is worse than one that says what it misses.

- [ ] **Step 2: Confirm all four fail — `chapters.rb` does not exist**

- [ ] **Step 3: Implement the check**

The four tunable vocabularies, each in its own constant so a test can name it:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Housekeeping
  # A document asserting that a requirement ID is stated in a named spec chapter, where the chapter
  # does not carry it. The unit is a CLAUSE, not a line: "A.md for X, Y; B.md for Z" pairs every ID
  # with every chapter under a same-line rule, which is why a naive rule fires 23 times for 4 real
  # defects. Appendix C carries every ID and can never be wrong about one, so it is exempt.
  class Chapters
    PREFIXES = %w[SEAM HTTP IO BODY CTX PIPE RECOV RETRY REDIR AUTH PAGE SSE SERDE OBS CFG
                  TRANSPORT ASYNC XCUT NFR].freeze
    # A clause boundary. ';' only: an em-dash separates a chapter from its ID list as often as it
    # separates two clauses, and treating it as a boundary loses 8c:69's real defect.
    BOUNDARY = ";"
    # Prose whose own subject is that the ID is NOT in the chapter. Evaluated over the line PLUS the
    # following one, because such a sentence routinely crosses a line break.
    NEGATION = /appear(?:s)? nowhere|appendix C is (?:their|its) only|does not carry|no prose chapter|
                appendix-C rows?|unfollowable|from appendix C|read out of \*\*appendix C\*\*|
                neither ID appears|appears in/xi
    EXEMPT = /appendix-c/
    # Two stated gaps, both measured rather than guessed. `continued_clause`: a clause whose chapter
    # reference sits on the preceding line is invisible to a line-oriented scanner (8c:70's SEAM-15 is
    # the live instance, caught by hand). `dynamic_chapter_path`: a chapter named by interpolation or
    # by a variable rather than as a literal path -- undecidable here for the same reason
    # `send(variable)` is undecidable for phase 9's AST gates. Both are printed with the check's
    # output, so a reader is never told it saw something it did not.
    GAPS = %i[continued_clause dynamic_chapter_path].freeze

    def findings(repo) = repo.markdown_files.reject { EXEMPT.match?(_1) }.flat_map { scan(repo, _1) }

    # ... scan: for each line, skip when NEGATION matches the two-line window; split at BOUNDARY;
    # within a clause track the nearest preceding chapter reference and test every ID after it,
    # expanding a range whether or not its endpoints are backticked.
  end
end
```

**Range vocabulary, and why it is the one thing Fact 6 says to add:** `` `SEAM-11`–`SEAM-15` `` does
not match a range pattern written for unbackticked text, and that is what hides 8a's `SEAM-13`. With
backticks tolerated the check catches **5 of the 5 known true positives**; without, 3.

- [ ] **Step 4: Confirm the four pass, then run it over the live tree**

**Expect zero findings, and that is the designed outcome, not a weak check.** The three true positives
the measurement found were **corrected during phase 10's planning on 2026-09-13** — 8a's design `:67`
named `docs/product-spec/03-pluggable-seams-and-extension-model.md` for `SEAM-11`–`SEAM-15` and
`SEAM-22` when that chapter carries none of `SEAM-13`, `SEAM-15`, `SEAM-22`, and 8c's design `:69-70`
named it for nine IDs, two of them wrong the same way. Both are phase documents, and CLAUDE.md's rule
is that a finding in material you may write is not a finding: fix it. So the check's proof lives in
**committed fixtures**, which is where it belongs — a gate whose only evidence is a live defect loses
its evidence the moment the defect is fixed, and the next reader cannot tell a working check from a
blind one.

**Two** corrected lines carry those three attributions — 8a's design `:67` (three wrong IDs on one line,
`SEAM-13`, `SEAM-15`, `SEAM-22`) and 8c's design `:69-70` (two, `SEAM-13` and `SEAM-15`) — and both are
therefore copied into `test/fixtures/chapters/` as regression fixtures verbatim, with their
pre-correction text, so the check is asserted against the exact shape it was designed for. **Step 1's
four assertions read their input from those fixture files**, not from the inline strings a first draft
used: a fixture that is a copy of the real defect is evidence, and a hand-typed approximation of it is
not.
If the live run reports anything, read it: a false positive means the vocabulary is wrong and the
vocabulary changes, never the prose. `CLAUDE.md` is explicit — "Never rewrite prose to satisfy a check."

- [ ] **Step 5: Re-verify the attribution facts the corrections rest on**

`SEAM-13`'s only prose home is `docs/product-spec/02-architectural-principles.md`, and `SEAM-15`,
`SEAM-20`, `SEAM-22`, `SEAM-23` and `SEAM-28` appear in no prose chapter at all — appendix C is their
only normative statement. Phase 2 established that on 2026-09-06, re-verified it on 2026-09-07, and
phase 10's planning re-verified it on 2026-09-13; this step re-runs it at implementation time, because
a spec revision that moved an ID into a chapter would make both corrections wrong in the other
direction. `grep -o 'SEAM-[0-9]*' docs/product-spec/*.md | grep -v appendix-c | sort -uV` is the form
the roadmap records.

- [ ] **Step 6: Register it, and correct the two "Eight checks" sentences**

`probe.rb` gains `chapters` in its check list; `CLAUDE.md` and `SKILL.md` say **nine** checks and name
it. `ruby -w .claude/skills/housekeeping/test/run.rb` and `ruby .claude/skills/housekeeping/probe.rb`.
The probe is read-only and tested to be — the new check reads `docs/product-spec/` and writes nothing,
which the guard test already enforces for every frozen tree.

---

## Task 8: `PAGE-14` / `SSE-26` — one core error family for the single-use latch

**Requirement IDs:** `PAGE-14` (MUST), `SSE-26` (MUST), `SSE-40` (SHOULD), `NFR-4` — cross-reference; phases 7b and 7c own the rows. `SEAM-29` is named here for its one-type-one-message-form discipline and is an **own** row, audited in Task 14 under §10.10.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/single_use_error.rb`, `gems/dexpace-core/sig/dexpace/single_use_error.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Modify: `gems/dexpace-core/lib/dexpace/sse/stream_state_error.rb`, its `sig/`
- Modify: `gems/dexpace-core/lib/dexpace/page/pages.rb`, its `sig/`
- Modify: `gems/dexpace-core/test/dexpace/page/pages_test.rb`, `…/sse/stream_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Error` (the module phase 1 ships)
- Produces: `Dexpace::SingleUseError < ::StandardError`; `Dexpace::SSE::StreamStateError < Dexpace::SingleUseError`

Inbound bullet 24. Fact 5 measures the cost: `Dexpace::InvalidArgumentError < ::ArgumentError`, so a
caller's `rescue ArgumentError` around a page loop swallows `PAGE-14`'s **state** violation, and no
single `rescue` covers both subsystems. Neither requirement names a type; `SSE-26`'s own example is
"an illegal-state error".

- [ ] **Step 1: Write the two failing tests**

```ruby
# PAGE-14 / SSE-26: one error family for the single-use latch. A caller must be able to write one
# rescue for both subsystems, and a state violation must not be catchable as an ArgumentError.
def test_a_second_page_iteration_is_not_an_argument_error
  pages = build_pages
  pages.each { break }
  refute_kind_of ::ArgumentError, assert_raises(Dexpace::SingleUseError) { pages.each { break } }
end

def test_one_rescue_covers_both_subsystems
  [-> { second_page_iteration }, -> { second_sse_view }].each do |thunk|
    assert_raises(Dexpace::SingleUseError) { thunk.call }
  end
end
```

- [ ] **Step 2: Confirm both fail** — the first because `Pages#each` raises
`Dexpace::InvalidArgumentError` today, the second because `SingleUseError` does not exist.

- [ ] **Step 3: Implement**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # Raised when a single-use view's iterator is taken a second time. PAGE-14 ("re-iteration MUST fail
  # rather than silently restart") and SSE-26 ("a second attempt MUST fail loudly (e.g. an
  # illegal-state error)") describe one situation, and before phase 10 they had two error families:
  # 7c raised InvalidArgumentError, which is < ::ArgumentError, so a caller's `rescue ArgumentError`
  # around a page loop swallowed a state violation -- measured on 3.2.11, 3.3.12, 3.4.10 and 4.0.6.
  # Named for the situation rather than for the category: "state error" would invite every future
  # misuse, and SEAM-29's one-type-one-message-form discipline argues for the narrower name.
  class SingleUseError < ::StandardError
    include Dexpace::Error
  end
end
```

The `require_relative` goes in `lib/dexpace.rb` **after** the one for `error.rb`: `include Dexpace::Error`
is evaluated when the class body runs, so a require order that loads this file first is a `NameError` at
load time rather than a test failure.

`Dexpace::SSE::StreamStateError < Dexpace::SingleUseError` — 7b's constant, its `sig/`, its YARD and
every one of its tests survive, and inserting a class between it and `StandardError` narrows nothing:
every existing `rescue StreamStateError` and `rescue StandardError` still catches. `Pages#each` raises
`SingleUseError`. The `require_relative` goes in `lib/dexpace.rb` in this step.

- [ ] **Step 4: Confirm both pass, and that 7b's and 7c's own suites are untouched**

Run `dexpace-core`'s whole suite. 7b's three `assert_raises(Dexpace::SSE::StreamStateError)` assertions
must still pass unchanged — that is the proof re-parenting is additive. 7c's assertions change from
`InvalidArgumentError` to `SingleUseError`, which is the repair.

- [ ] **Step 5: Regenerate both surface baselines**

`sig/` gains one file and one changed superclass; the runtime surface manifest gains one constant.
`NFR-4` needs **both** regenerated, because `rbs` cannot see what `Data.define` generates and the
manifest cannot see a signature — "changing exports means regenerating both".

---

## Task 9: `XCUT-12` — the single-flight assertion under a fiber scheduler

**Requirement IDs:** `XCUT-12` (SHOULD), `XCUT-11`, `ASYNC-6`, `AUTH-35` — cross-reference.

**Files:**
- Create: `gems/dexpace-transport-async_http/test/dexpace/transport/async_http/xcut12_fiber_test.rb`

**Interfaces:**
- Consumes: phase 9's `InvariantSuite`'s `XCUT-12` assertions and the suite contract's clause 9
  `around:` wrapper; 6c's bearer credential cache; `Async`'s `Sync`
- Produces: the fiber-scheduler run of an assertion phase 9 could only run on threads

Phase 9 postponed this naming phase 10 in as many words — "**Phase 10**, if its audit of `XCUT-12`
finds the thread-only form insufficient — a judgement phase 10 is entitled to make and phase 9 is not".
The design's `R9` finds it insufficient: `Thread::Mutex` ownership is **per-fiber and non-reentrant**,
a single-flight guard is a lock held across a fetch, a fetch under a reactor is a suspension point, and
a thread-only race cannot see the deadlock that combination creates.

- [ ] **Step 1: Assert the shape fails before it passes — deliberately, with a bad guard**

Build a double whose single-flight guard holds a `Thread::Mutex` **across** the fetch, and run it
under `Sync { }` with two fibers on one thread. It must deadlock or fail; a thread-only run of the same
double passes. **That contrast is the whole justification for this task**, and it is asserted rather
than argued — with the deadlock detected by an explicit deadline check on a `Queue`, never by
`Timeout.timeout`, which §8.3 bans.

- [ ] **Step 2: Write the driver**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# XCUT-12 under a fiber scheduler. Phase 9 ships the thread form and could not ship this one:
# dexpace-conformance declares dexpace-core and nothing else, so it cannot open a reactor. This gem
# already declares async-http, so the driver costs no dependency -- 8a's precedent is a driver file
# inside the adapter gem. Thread::Mutex ownership is per-fiber and non-reentrant, so a guard held
# across a fetch deadlocks two fibers of one thread, which a thread-only race cannot observe.
#
# The keywords are phase 9's, verbatim: InvariantSuite.run's filed signature is
# (core:, seam:, transport:, mutable:, bounded_map:, bounded_map_store:, cnonce:, redirect_hops:,
# waive:, around:) -- there is no `only:` and no `only`-shaped filter, so this driver runs the WHOLE
# suite under the wrapper and reads XCUT-12's results back out of the report.
require "async"
require "dexpace/conformance"

class XCUT12FiberTest < Minitest::Test
  def test_single_flight_holds_under_a_fiber_scheduler
    report = Dexpace::Conformance::InvariantSuite.run(
      core: ::Dexpace,
      # ... every subject keyword phase 9's signature names, including whichever one carries
      # XCUT-12's credential cache; 6c's expiring-token provider is what it is given.
      around: ->(&blk) { Sync { blk.call } }
    )
    xcut12 = report.results.select { |r| r.assertion.ids.include?("XCUT-12") }
    refute_empty xcut12, "the suite ran no XCUT-12 assertion"
    assert_empty xcut12.select { |r| %i[failed error].include?(r.status) }, report.to_s
  end
end
```

**Two things this fence is careful about, and both were wrong in a first draft.** There is **no `only:`
keyword** on `InvariantSuite.run` and no ID filter of any shape (phase 9 plan `:1193-1194`), so the
driver runs the full suite and selects `XCUT-12`'s results from `Report#results` afterwards — which is
also the honest thing, since a reactor is the environment being tested and running everything under it
is strictly more informative. And **the credential subject arrives under whichever keyword phase 9's
implementer names for it**: phase 9's `XCUT-12` assertion is *specified by shape only* — "races N threads
on an expiring token and asserts exactly one fetch" (phase 9 plan `:2465-2470`) — so which of its
subject keywords carries the cache is genuinely unresolved in phase 9 and this driver may not invent one.
Step 2 reads the as-built signature and fills it in. That is what makes "**it adds no keyword to a
phase-9 or phase-8 interface**" — `R3`'s rule — true as written rather than aspirational.

- [ ] **Step 3: Confirm it passes, and that the thread driver still passes**

Both forms run; neither replaces the other. Record the measured fiber count, the observed number of
fetches (exactly one) and the interpreter rows — **3.3.12, 3.4.10 and 4.0.6 only**, because `async`
declares `required_ruby_version >= 3.3` and the 3.2 row cannot install it (8c's `P8-36`, re-verified in
Task 1).

- [ ] **Step 4: Close the post-release trigger**

`docs/first-release.md` § Post-release triggers' `XCUT-12` entry says in its own text "This trigger is
what fires if phase 10 leaves that judgement open". Phase 10 does not, so Task 18 removes the entry and
the phase's status note records why — an armed trigger whose event no longer means anything is worse
than no trigger.

---

## Task 10: `Protocol.parse` — the missing `"http/1.0"` wire form

**Requirement IDs:** `HTTP-24`, `HTTP-43` — cross-reference; phase 1 owns `Protocol`. `NFR-4`.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/protocol.rb`, its `sig/`
- Modify: `gems/dexpace-core/test/dexpace/protocol_test.rb`
- Modify: `gems/dexpace-transport-net_http/test/.../response_mapper_test.rb`

**Interfaces:**
- Consumes: `Protocol::WIRE_FORMS`, `Protocol.parse`
- Produces: `"http/1.0"` folding to a recognised wire form

Inbound bullet 27, handed forward by 8a: only `http/1.1`, `http/2` and `http/2.0` fold, so a real
`HTTP/1.0` response makes `native.http_version` produce `"1.0"` and `ResponseMapper` **raise**. No
`TRANSPORT` ID requires 1.0 support and every `WireServer` script in 8a's plan answers `HTTP/1.1`, so
the gap is never exercised by the suite — and is reachable by any real server. 8a declined it because
widening `WIRE_FORMS` is a phase-1 surface decision no sub-phase should take alone; phase 10 is the
phase that may.

- [ ] **Step 1: Two failing tests, one per layer**

`Protocol.parse("http/1.0")` must return a `Protocol` and not raise; `ResponseMapper` given a native
response whose `http_version` is `"1.0"` must map it and not raise.

- [ ] **Step 2: Confirm both fail, add the wire form, confirm both pass**

Additive only: a value is recognised that was not. No existing mapping changes, so `NFR-4` permits it
(`api-design/1d9e6e0b`), and both surface baselines are regenerated because `WIRE_FORMS` is a public
constant whose contents the manifest records.

- [ ] **Step 3: Assert the negative case still holds**

An unrecognised version — `"http/0.9"`, `"spdy/3"` — must still fail the way phase 1 specified. A
widening that turns a loud failure into a silent one is the direction this repair must not go.

---

## Task 11: Re-derive §10.1 — the retired byte-stream provider seam

**Requirement IDs (51, own rows):** `SEAM-3`–`SEAM-10`; `IO-1`–`IO-42`; `XCUT-23`.

**Files:**
- Modify: `docs/deviations.md` (row 1)
- Read only: `gems/dexpace-core/lib/dexpace/io/**`, `gems/dexpace-core/lib/dexpace/registry.rb`,
  `gems/dexpace-core/sig/dexpace/io/**`

**Interfaces:**
- Promising documents (where to look, never evidence):
  `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md` and its plan;
  `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` for the registry and for
  `SEAM-3`'s 🚫 row
- Produces: 51 checklist rows and `docs/deviations.md` row 1's verdict

§10.1 makes **three** separable claims, and the entry's own sentence separates them: the pluggability
apparatus "is removed"; `IO-1`–`IO-29` and `IO-37`–`IO-42` "are implemented in full"; and `XCUT-23`'s
resolution rule "as applied to this seam" retires with it. Each is audited differently.

- [ ] **Step 1: The removal claim — a negative scan, with its blind spots stated**

`SEAM-3`–`SEAM-10` and `IO-30`–`IO-36`, `IO-39` are the apparatus. The claim is an **absence**, and
`R2` says an absence needs a scan over the tree rather than a read of one file. Assert: no
`Dexpace::IO` constant exposes a factory-registration entry point; `Dexpace::Registry` holds no
byte-stream slot; no `sig/` file declares one. **Where the scan cannot decide, say so** — a
`const_get` on a computed name is undecidable, exactly as `gates:cause_walk` records for
`send(variable)`.

The four appendix-C-only IDs are read verbatim here, because the corpus has no entry for them
(`--gaps IO` lists `IO-32`–`IO-35`): `IO-32`'s install idempotence, `IO-33`'s explicit-install-wins,
`IO-34`'s resolution cache and `IO-35`'s replaced-provider warning. Each is the subject the retirement
removes, and the row says so rather than saying "not implemented".

- [ ] **Step 2: The full-implementation claim — 36 IDs, each against its own clause**

`IO-1`–`IO-29` and `IO-37`–`IO-42`, against the appendix-C clause rather than against §3.1's
description of it (`R2`'s substitution rule). **`IO-6` is the load-bearing one**: appendix C is its
only normative statement, §3.1 and §10.12 attribute its rule to the retired `SEAM-3`, and the cost of
the misattribution is that "a phase auditing `SEAM-3`'s retirement finds no surviving citation and
could reasonably conclude the ownership rule retires with the seam". So this step asserts
ownership-on-wrap **from `IO-6`'s text**: closing a `BufferedSource` built over a caller's `IO` closes
that `IO`. Amendment C3 is the documentation half.

`IO-38`'s cross-thread close is confirmed as **tested on CRuby only** — the GVL hides a missing lock —
which is the standing post-release trigger and not a phase-10 finding.

- [ ] **Step 3: `XCUT-23` — three surviving instances, not zero**

§11.8 records the resolution: `XCUT-23`'s rule "needs at least one instance after a seam retires" and
"has three here (transport, serde, executor)". Assert all three against `Dexpace::Registry`'s as-built
precedence — explicit install > require-time discovery > loud failure — and record the row against
§10.1 **and** §10.8, which Task 13 re-reads for its own claim.

- [ ] **Step 4: Move `docs/deviations.md` row 1, with evidence**

One of `R1`'s four verdicts, citing paths and constants. `bundle exec rake gates:ledger_audit` must
pass afterwards — which now means something, because row 1 carries a verdict and assertion 3 is live
for it.

---

## Task 12: Re-derive §10.2–§10.5 — the body duck type, the pivot, cancellation, the unsatisfied MUSTs

**Requirement IDs (22, own rows):** `SEAM-1`, `SEAM-13`, `SEAM-16`, `SEAM-17`, `SEAM-30`; `BODY-1`, `BODY-35`; `PIPE-33`; `RETRY-23`; `CFG-17`, `CFG-20`, `CFG-21`; `TRANSPORT-3`; `ASYNC-1`–`ASYNC-5`; `XCUT-1`–`XCUT-3`; `NFR-11`.

**Files:**
- Modify: `docs/deviations.md` (rows 2, 3, 4, 5)
- Read only: `gems/dexpace-core/lib/dexpace/body/**`, `…/completer.rb`, `…/cancellation.rb`;
  `gems/dexpace-async-thread/lib/**`; both transports' cancellation paths

- [ ] **Step 1: §10.2 — the duck type, and what `BufferedSource.over` owns**

`#each` yielding BINARY `String` chunks; `BufferedSource.over` as "the single entry point the other
direction" taking **no** ownership. The second half is the one an audit misses: assert that
`BufferedSource.over` does *not* close what it wraps, which is the deliberate difference from `IO-6`'s
ownership-on-wrap that §10.12 exists to state. Both under one row each for `BODY-1` and `BODY-35`.

- [ ] **Step 2: §10.3 — the pivot, and `NFR-11`'s scan as evidence**

`SEAM-17` is a SHOULD naming the pattern, not the type; the claim is that no third-party framework type
appears in core's public surface. The evidence is phase 9's `PackagingSuite` `NFR-11` scan over each
**shipped** `sig/` tree plus the `gates:rbs_surface` result — read out of phase 9's report via Task 3's
intake, not re-run. §11.2's resolution ("`NFR-11`'s target is *third-party framework* types; a
core-owned dependency-free pivot is not one") is the claim being checked, and the check is that
`Dexpace::Completer` and the pivot's type are core-owned.

- [ ] **Step 3: §10.4 — cancellation, nine IDs and the one sentence that is unattributed**

`SEAM-30`/`ASYNC-5`'s orphaned-response close performed by the **producer** under the check-after-resume
rule; `CFG-21`'s discard-path close through the same helper; `XCUT-3`'s prompt cancellation at the
future. Then the attribution: §10.5's mitigation sentence says "`Completer#on_cancel` lets **an
adapter** shorten that by closing the socket under the read", and **only the transport can** —
`dexpace-async-thread` owns no socket and its pool posts an opaque block. Confirm that from as-built
source in both adapters; the correction travels with amendment C5.

- [ ] **Step 4: §10.5 — audit, do not re-open**

Cross-cutting constraint 8. `ASYNC-3` **not satisfied** (its antecedent is met — a blocking task on a
worker thread — and the port meets one of the two modes); `PIPE-33`'s interrupt clause **not
satisfied**, its non-interrupting half met exactly; `ASYNC-4` **vacuous**, and on **no** unsatisfied-MUST
entry, which the roadmap corrected in place on 2026-09-11 and which stays. `CFG-20`'s
cancel-with-interrupt clause is the same unmet clause under a second ID, and the port gains no fourth
unsatisfied MUST.

The evidence is phase 9's report: `waived (would fail): ASYNC-3`, never `passed` and never `vacuous`;
`ASYNC-4` `:vacuous`. Assert the report says exactly that, and assert the residual gap §10.5 states —
"a transport blocked inside an uninterruptible C-extension read cannot be aborted early" — against 8a's
as-built producer thread. **No step of this task adopts an interruptible path or proposes one.**

Task 1's Fact 4 belongs here as context and not as a verdict: the `async-http` closure's seven
`Fiber#raise` sites are interrupts at scheduler checkpoints, which is what §3.3 already relies on, and
they neither satisfy `ASYNC-3` (whose antecedent is a worker **thread**) nor violate §8.3's rationale.

- [ ] **Step 5: Move rows 2–5 with evidence; `gates:ledger_audit` green**

---

## Task 13: Re-derive §10.6–§10.9 and §10.19

**Requirement IDs (13, own rows):** `RECOV-12`; `RETRY-34`; `AUTH-14`; `PAGE-13`, `PAGE-15`; `SSE-29`, `SSE-30`, `SSE-36`; `OBS-2`; `XCUT-9`; `NFR-1`, `NFR-8`, `NFR-9`. Re-reads `SEAM-5`–`SEAM-10` and `XCUT-23` for §10.8's and §10.9's own claims.

**Files:**
- Modify: `docs/deviations.md` (rows 6, 7, 8, 9, 19)
- Read only: `gems/dexpace-core/lib/dexpace/each_cause.rb`, `…/error.rb`, `…/registry.rb`;
  every gemspec; `tools/invariant_gates.rb`'s `cause_walk` offence list

- [ ] **Step 1: §10.6 — the suppressed trail, and `XCUT-9`'s two halves**

`Dexpace::Error#suppressed` supplies the list; `#cause` is never overloaded to mean "failed while
cleaning up"; every cause walk goes through one `equal?`-tracking enumerator. The first two are read
from source; the third is `gates:cause_walk`'s offence list out of Task 3's intake, **with its stated
gap carried into the row** — 10 of 12 decidable shapes, `send(variable)` undecidable. Phase 9's
`XCUT-9` residue travels too: a depth cap exactly equal to the cycle length passes a black-box test, so
the row states what the assertion proves and what it cannot.

- [ ] **Step 2: §10.7 — the narrowing, and the one assertion that *is* the audit**

`dexpace-core.gemspec` contains **zero `add_dependency` lines**, which CLAUDE.md says "*is* the
`SEAM-1` dependency audit". Evidence: phase 9's `PackagingSuite` over each **published**
`Gem::Specification` (`P9-2`'s whole point — a source gemspec and a published one can differ), plus the
require-allowlist audit and the clean-bundle isolation run. Then the two visible consequences:
`AUTH-14`'s Basic auth as `["u:p"].pack("m0")` and never `Base64`, and `OBS-2`'s duck-typed logging sink
with no `require "logger"` anywhere in core. `package-and-dependency-layout/70fbcaee` is the note the
allowlist's basis rests on and is cited, not re-derived.

- [ ] **Step 3: §10.8 and §10.9 — self-registration, and a vacuity that is really a substitution**

All five precedence branches preserved verbatim; the registry holds factories, the resolved slot holds
one instance, `SEAM-6`/`SEAM-8`'s prior-state table compares `equal?` on that instance. Then the
asymmetry §10.8 says is "argued rather than assumed": presence-gated auto-activation permitted for
instrumentation only — and phase 10 asserts the restriction is **enforced**, not merely stated, because
`docs/first-release.md` carries it as a declined item ("no transport or codec adapter may ever use
presence-gated activation").

§10.9: `SEAM-10` is vacuous (one process-global constant namespace, no classloader) and is **replaced**
by the version-skew guard, which phase 2 built as `Dexpace::Registry#register(key, factory, core:)`
(phase 2 plan `:2438-2439`; `P2-7` is that guard's own deviation row, and it is narrower than the guard
— it records that the version comparison is hand-rolled and accepts only `~> MAJOR.MINOR`). A vacuity with a replacement is not the same row as a vacuity without one, and the row says
which.

- [ ] **Step 4: §10.19 — the retarget, and where its two halves are dispositioned**

`NFR-8` vacuous by its own text; `NFR-9` follows its antecedent; both retargeted at the
require-allowlist audit and the clean-bundle isolation run, **dispositioned under `NFR-1`** rather than
counted twice (phase 9's `P9-5`). Confirm phase 9 marked both **N/A** and not ✅. The regeneration guard
`NFR-9`'s content is not covered by is the standing post-release trigger and is confirmed still
unowned by a phase, not re-filed.

- [ ] **Step 5: Move rows 6–9 and 19; `gates:ledger_audit` green**

---

## Task 14: Re-derive §10.10–§10.14

**Requirement IDs (21, own rows):** `SEAM-20`–`SEAM-23`, `SEAM-29`; `HTTP-2`, `HTTP-4`, `HTTP-5`, `HTTP-7`, `HTTP-17`, `HTTP-18`; `BODY-8`, `BODY-37`; `SERDE-5`–`SERDE-8`, `SERDE-16`, `SERDE-17`; `XCUT-15`, `XCUT-18`.

**Files:**
- Modify: `docs/deviations.md` (rows 10, 11, 12, 13, 14)
- Read only: `gems/dexpace-core/lib/dexpace/{request,response,headers,query}.rb`,
  `…/header_syntax.rb`, `…/serde/**`; `gems/dexpace-serde-json/lib/**`; both adapters' dispatch paths

- [ ] **Step 1: §10.10 — the gap stated honestly, and the mitigation asserted**

The two holes are real and neither can be closed: `Req.send(:new, …)` reaches the generated
constructor, and any object answering `#method`/`#url`/`#headers`/`#body` duck-types past the builder.
**Assert both, so the row is honest** — CLAUDE.md says "Do not build a fake proof that they are"
closed. Then assert the mitigation that matters: header name and outbound value validation
(`HTTP-17`, `HTTP-18`, `XCUT-18`) runs **again** immediately before dispatch, inside **every** transport
adapter. Evidence is phase 9's `InvariantSuite` `XCUT-18` assertion driven through a forged
`Dexpace::Request` plus 8a's Task 16 and 8c's Task 9 call sites — read from source, both adapters, not
one.

- [ ] **Step 2: §10.11 — spec-sanctioned, and the two caveats that are easy to lose**

`HTTP-5` grants the mechanism explicitly. The caveats: `freeze` is **shallow**, so every nested
collection is frozen independently at construction; `Ractor.make_shareable` deep-freezes **in place**
and returns the same object, so it is applied only to a collection the model already `dup`ed. Assert
the second from source: a `make_shareable` on a caller's live hash is the bug the caveat exists to
prevent, and it is invisible unless someone looks.

- [ ] **Step 3: §10.12 and §10.13 — one ownership rule, four profiles**

`BODY-8` requires the port to decide, so the audit is that the decision is **uniform**: a body closes
exactly the sources it opened; ownership-on-wrap is the I/O layer's and deliberately not the body
layer's; the serde seam's streaming variants close nothing (`SEAM-20`/`SEAM-21`). The `SEAM-3`
attribution in §10.12's own text is amendment C3's second half.

§10.13: all four encode profiles ship — `#dump_string`, `#dump_bytes`, `#dump_to(sink)`,
`#dump_into(buffer, offset:)` — and the two that are "one Ruby type" differ **only in the encoding tag
the result carries**. Assert the tag, since that is the whole reason both are kept.

- [ ] **Step 4: §10.14 — the witness, and the one clause it is honestly weaker on**

`SEAM-22` is read verbatim from appendix C (no corpus entry; `--gaps SEAM` lists it). The entry claims
the substitution is "at least as strong on two counts (earlier failure, unreachable
unresolved-variable state) and honestly weaker on one (no compile-time refusal)". Assert all three,
including the weakness — a row that records only the strengths is the shape of audit this phase exists
to replace. `SEAM-23`'s failure hierarchy ships as written, and phase 9's own fix round found the trap
here: `Dexpace::SerdeError` **exists nowhere**; phase 2 filed `Dexpace::Serde::Error` with
`SerializationError` and `DeserializationError` under it. Assert the real hierarchy.

- [ ] **Step 5: Move rows 10–14; `gates:ledger_audit` green**

---

## Task 15: Re-derive §10.15–§10.18 and the closing note

**Requirement IDs (17, own rows):** `BODY-32`; `PIPE-16`; `RECOV-34`; `RETRY-26`, `RETRY-28`; `REDIR-11`; `AUTH-29`; `SSE-11`; `OBS-35`; `CFG-1`, `CFG-3`, `CFG-4`, `CFG-15`, `CFG-18`, `CFG-24`, `CFG-26`; `XCUT-13`.

**Files:**
- Modify: `docs/deviations.md` (rows 15, 16, 17, 18) and its closing-note verdict
- Read only: `gems/dexpace-core/lib/dexpace/pipeline/**`, `…/configuration.rb`, `…/clock.rb`,
  `…/retry/**`, `…/sse/**`, `…/io/buffer.rb`

- [ ] **Step 1: §10.15 — "judged, and stronger", which is a claim with a testable consequence**

The cross-origin marker on the per-hop cursor rather than on the request makes forgery
**structurally impossible** and makes the porter trap `REDIR-11` documents — a pipeline with no auth
step forwarding the marker to the transport — **unable to occur**. Assert the second: construct a
pipeline with no AUTH step and show the marker cannot reach the transport. A "stronger" claim that is
not asserted is a claim.

- [ ] **Step 2: §10.16 — four tiers, and the ordering defended rather than obeyed**

`CFG-1`'s ordering preserved even where it inverts common Ruby convention; the `Dexpace.configure`
defaults tier is "a genuinely distinct in-process source, not a second `ENV` read under another name"
(`P11`). Assert the distinctness: a value set through `configure` and absent from `ENV` must resolve,
and the two tiers must be independently observable. The proxy model's resolution is "the same deviation
applied again, not a new one" — assert it uses the same chain rather than its own.

- [ ] **Step 3: §10.17 — the cancellable queue wait, satisfying two clauses at once**

`CFG-15`'s blocking-and-interruptible clause and `RETRY-26`'s no-carrier-pinning clause, simultaneously
— which §11.1 records as the resolution of a genuine tension, with `XCUT-3`'s mechanism-versus-intent
sentence as the authority. Assert both clauses of one object, and assert §3.7's graceful close waits
without parking a cancelled caller (`XCUT-13`).

- [ ] **Step 4: §10.18 — four named constants, and "fails or ignores loudly above them"**

`IO-9`'s 64 MiB materialisation ceiling, `SSE-11`'s documented cap, `RECOV-34`'s ~292-year duration
bound, `BODY-32`. `SSE-11` requires the port to pick a documented cap, so the audit is that the
constant is **documented and public**, not merely present. Then the loudness: assert a value above each
bound raises or is ignored **observably**, because "preserving the observable behaviour on a host where
the stated failure mode is unreachable" is the entry's whole claim.

- [ ] **Step 5: The closing note — the two things that are deliberately not deviations**

The two retry stacks are **not** unified, so neither `RETRY-28`'s nor `08-execution-pipelines.md`'s
unification sanction is invoked; and both transport seams and both pipeline bridges survive. Assert
both from source: two retry stacks present and distinct, two transport seams, two pipeline bridges.
§11.19 records that the unification sanction is stated twice with different scopes and that this port
"unifies nothing" — a claim that is false the moment someone merges the stacks, and nothing else checks
it. `RETRY-28` gets its own row for that reason.

- [ ] **Step 6: Move rows 15–18 and record the closing note's verdict; `gates:ledger_audit` green**

---

## Task 16: the two documentation repairs — two tracer factories, one undriven chain

**Requirement IDs:** `CTX-14`, `CTX-16`, `CTX-20`, `OBS-21`–`OBS-25`, `OBS-28`, `OBS-29`, `OBS-34`, `SEAM-11`, `SEAM-28`, `PIPE-2`, `PIPE-11`, `PIPE-37`, `NFR-4` — all cross-reference.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/instrumentation/bundle.rb` (YARD only)
- Modify: `gems/dexpace-core/lib/dexpace/instrumentation/http_tracer.rb` (YARD only)
- Modify: `gems/dexpace-core/test/dexpace/instrumentation/http_tracer_test.rb`

**Interfaces:**
- Consumes: `Bundle#tracer_factory` (4a's `P4-8`, bound to `opentelemetry-api`'s `TracerProvider`
  shape; the **filed arity is the five-parameter one**, `def tracer(deprecated_name = nil,
  deprecated_version = nil, name: nil, version: nil, attributes: nil)` — 4a's plan `:188`, `:1418`,
  `sig/` at `:1455`, superseding its design's two-parameter rendering, which matters because Step 2
  writes YARD on that method); `Instrumentation::HTTPTracer`'s eleven methods and `NULL`
- Produces: no signature change — YARD, one test, and one knowledge note (Task 19 Step 4)

Inbound bullets 2 and 23. The design's `R6` and `R7` close both as decisions rather than surface, on
canonical text: `OBS-29` ends "**This is a documented emission contract; pipeline/transport wiring to
emit it is a follow-up, so it is not yet runtime-enforced**", and `CTX-16`'s three modal clauses are met
by phase 4a without a carrier. **No step of this task adds a pipeline step, a keyword or a
`RequestOptions` member.**

- [ ] **Step 1: Write the test that pins the distinction, and confirm it fails**

```ruby
# CTX-14's tracer factory and OBS-29's are two objects, not one. OBS-25 (MUST) requires a no-op
# tracer-factory and that "Selecting a no-op path MUST NOT allocate per call", so the no-op factory
# returns the SAME object every time -- the opposite of one instance per operation. 4a's P4-8 bound
# Bundle#tracer_factory to a TracerProvider shape keyed by library name and version. So the bundle's
# factory makes SPAN tracers (OBS-21-OBS-25) and is legitimately shared; OBS-29's makes HTTP-tracers
# (OBS-28's eleven-method vocabulary) and is legitimately per operation.
def test_the_bundles_factory_is_keyed_by_library_and_not_by_operation
  bundle = Dexpace::Instrumentation::Bundle.build(...)
  # 4a filed the five-parameter TracerProvider shape; name:/version: are the keyword half.
  assert_equal bundle.tracer_factory.tracer(name: "x", version: "1"),
               bundle.tracer_factory.tracer(name: "x", version: "1")
end

def test_the_no_op_http_tracer_allocates_nothing_per_call
  assert_same Dexpace::Instrumentation::HTTPTracer::NULL, Dexpace::Instrumentation::HTTPTracer::NULL
end
```

Phase 5c's `P5-43` reconciles the no-op case only; the first assertion is the half nobody wrote.

- [ ] **Step 2: Write the two YARD blocks, and say why in each**

On `Bundle#tracer_factory`: it produces **span** tracers, is keyed by instrumentation-library name and
version, and is **not** `OBS-29`'s per-operation HTTP-tracer factory. On
`Instrumentation::HTTPTracer`: one instance corresponds 1:1 to one logical operation lifecycle
(`OBS-29`), **and `OBS-29`'s own last sentence makes the emission wiring a follow-up**, so v1 emits the
per-attempt group (6a's Task 9) and not the operation-lifecycle triple or the transport milestones. A
YARD block explains *why*; it never restates a signature.

- [ ] **Step 3: State `CTX-16`'s documentation obligation where the artifact is**

`docs/first-release.md`'s worked-example blocker enumerates what the example must show. Task 18 adds
the correlation chain to that enumeration: constructing a `DispatchContext`, promoting it, and where
the operation name goes. This step writes the sentence; Task 18 files it.

- [ ] **Step 4: Confirm no signature moved**

`rbs validate`, `steep check`, both surface baselines unchanged. A documentation repair that changes a
baseline is not a documentation repair.

---

## Task 17: the amendment set — eleven corrections, written so applying them is editorial

**Requirement IDs.** **Cross-reference rows, exactly the set the map's Task 17 row carries:** `HTTP-3`, `HTTP-42`, `HTTP-51`, `BODY-2`, `BODY-15`, `BODY-16`, `OBS-4`, `OBS-5`, `OBS-8`, `OBS-19`, `RETRY-13`, `SSE-19`, `TRANSPORT-2`, `TRANSPORT-4`, `TRANSPORT-8`, `TRANSPORT-14`, `TRANSPORT-17`, `TRANSPORT-18`, `TRANSPORT-19`, `TRANSPORT-25`, `TRANSPORT-29`, `TRANSPORT-30`, `CFG-22`, `CFG-23`, `CFG-25`, `CFG-27`, `CFG-28`, `XCUT-4`, `NFR-2`. **Also named by the amendments, but as *own* rows audited in Tasks 11–15 — not cross-reference rows:** `IO-6`, `IO-13`, `IO-16` (Task 11), `ASYNC-3`, `ASYNC-4`, `PIPE-33` (Task 12), `NFR-8` (Task 13), `XCUT-18` (Task 14), `PAGE-15` (Task 13), `XCUT-13` (Task 15). **And named by an amendment but owned elsewhere in this plan:** `HTTP-24` (Task 10's row), `SEAM-11` (Task 16's), `NFR-4` (Task 18's), `NFR-17` (Tasks 2, 5 and 6's). Every ID here has exactly one row somewhere in the checklist; this heading says where, because a first draft labelled all thirty-five "cross-reference" and ten of them are not.

**Files:**
- Modify: `docs/deviations.md` — § *Deviations found outside a phase*, completed to the thirteen amendments `C1`–`C13`
- Modify: `docs/first-release.md` — one blocker (filed in Task 18)

**Interfaces:**
- Reads only: the frozen chapters, to quote them
- Produces: thirteen numbered amendments `C1`–`C13`, each with the file, the sentence, the replacement,
  the measurement and the verified code half

**Phase 10 does not edit §3, §4, §8, §9, §10, §11, §12 or appendix C.** `docs/README.md`'s "Frozen
means frozen" reserves them to a human acting deliberately. What this task does is make the amendment a
**transcription**: **eleven of the thirteen already have interim notes** — the retirement batch's seven
(`C1`, `C3`–`C7`, `C10`), the two dated 2026-09-12 that this plan numbers `C12` and `C13`, and the two
phase 10's design added (`C8`, `C11`) — and every one of the thirteen gains its replacement text and a
verified code half, so applying the set two years from now is editorial and not a fresh investigation.

- [ ] **Step 1: Verify every code half in as-built source, before writing a replacement**

Eleven checks, one per amendment, each a read of shipped code rather than of a plan: C1's
retag-then-transcode in `Response#body_string`; C2's `MultipartBody#new_builder` and its non-aliasing
assertion; C3's ownership-on-wrap in 3a; C4's four event methods and the **absence** of `#tag`; C5's
producer `Thread` over a `Thread::SizedQueue(1)`; C6's `http.max_retries = 0`; C7's `TRANSPORT-14`
waiver and `TRANSPORT-8` class discrimination; C8 — none owed; C9's root `Gemfile` `minitest` line and
pin; C10's one-`Result`-per-assertion; C11's two halves — 7b's configurable SSE line cap, and 5c's plus
6a's documented `OBS-29` emission contract with the per-attempt group emitted.

**An amendment whose code half is absent is not written as an amendment** — it becomes a finding and a
repair, because the whole premise of the set is that the port already behaves correctly and only the
sentence is wrong.

- [ ] **Step 2: Write C1–C11, each in the existing holding area's voice**

**Seven existing notes are rewritten in place** only to **add** the replacement text and the
verification date — `C1`, `C3`, `C4`, `C5`, `C6`, `C7` and `C10`, the retirement batch — and their
measurements, dates and attributions stand. **Two more already exist and needed only a number:** the
2026-09-12 attribution note against §10.5's "an adapter" becomes **`C12`** and the 2026-09-12
completeness note against §12's `PAGE` row becomes **`C13`**. They had been left out of the set
entirely, which is why `docs/deviations.md` now states the `C1`–`C13` mapping beside the notes rather
than leaving it in a plan. **Four are new writes:** **C8**, carrying
Fact 3's per-row `net-http` measurement and Fact 4's first measurement of the `async-http` closure
(no `Timeout.timeout`; seven `Fiber#raise` sites at scheduler checkpoints, one of them
`Async::Task#cancel`'s delivery mechanism; one `Thread#raise` that is a `Thread.current.raise` on the
calling thread and therefore not §8.3's hazard; one `Thread#kill` on an unreachable helper thread);
**C11**, appendix C's `SSE-19` row dropping the port sanction `docs/product-spec/13-…md:33` carries;
and **`C2`** and **`C9`**, the two the holding area has never carried — §4's builder list dropping the
multipart body `HTTP-3` names, and §9.3 calling a bundled Minitest a default gem. `C8` and `C11` were
filed with the design on 2026-09-13; `C2` and `C9` are written here.

C8's replacement is wider than bullet 19 asked for, and the reason is stated in the amendment: bullet
19 asks for "one clause scoping the prohibition to code this repository writes", and the measurement
says the useful clause is that plus **what the closures actually do** — which is what a reader auditing
the ban will want and what no document holds.

**C11 is against the frozen *normative* specification**, so it is also written as a recommendation to
the specification author, in §11's own idiom ("recommended to the specification author"). It is written
as **one amendment about a pattern, not two errata about two rows**, because phase 10's planning measured
the divergence running in **both** directions:

- `docs/product-spec/13-server-sent-events-and-streaming.md:33` ends `SSE-19` with "a port MAY add a
  configurable cap and reject/truncate oversized lines, **documenting the divergence**"; appendix C's row
  for the same ID ends at the growable byte accumulator and carries no sanction. `P7-21` rests on the
  appendix-C half of the same pair, where appendix C says "no maximum line **or event** size" and the
  chapter says only "lines/values".
- `docs/product-spec/appendix-c-…md`'s `OBS-29` row ends "(created by the factory per operation). **This
  is a documented emission contract; pipeline/transport wiring to emit it is a follow-up, so it is not
  yet runtime-enforced.**"; `docs/product-spec/15-instrumentation-and-observability.md:54` carries neither
  the parenthetical nor the clause, and carries a `*Conformance:*` clause appendix C drops.

**For each pair the two rows together are the only complete statement of the requirement, and neither row
says so** — which is the general defect the amendment states, because `CLAUDE.md` calls appendix C "the
fastest way to locate a requirement ID" and a checklist author who stops there gets something that reads
complete. The `OBS-29` half is not hypothetical damage: five documents across four phases reasoned from
the chapter's short form and carried an "open surface decision" the requirement had closed, which
`R6` settles and which cost the roadmap's inbound list its largest bullet.

- [ ] **Step 3: State the set's closing condition once, in the section's own preamble**

The holding area calls itself "a holding area, not a permanent second ledger". After this task it is
**complete** — thirteen amendments, none owed a measurement — and the preamble says so, names Task 18's
blocker as the closing condition, and says what happens if the blocker is answered the other way: the
release notes name which design sentences a reader should not trust.

- [ ] **Step 4: Confirm the frozen trees are untouched**

`git diff --name-only` must name no file under `docs/product-spec/` or `docs/sdk-design-ruby/`, and
`ruby .claude/skills/housekeeping/probe.rb --only guard` must pass. That is the tested guard, and this
is the task it exists for.

---

## Task 18: the release-register walk

**Requirement IDs:** `NFR-4`, `TRANSPORT-28`, `XCUT-12`, `XCUT-14`, `NFR-13` — cross-reference. `NFR-12` and `NFR-16` are **named and get no row**: this task only walks the `docs/first-release.md` lines that mention them, which is register work and not a requirement verdict, and phase 9 owns both rows. The design's *64 cross-reference rows* section states that exclusion, with `NFR-10`.

**Files:**
- Modify: `docs/first-release.md`
- Create/regenerate: `sig/` baseline and the runtime surface manifest, per gem

**Interfaces:**
- Consumes: Task 3's intake; Tasks 4–17's outcomes; phase 9's `NFR` dispositions
- Produces: a per-line disposition for thirteen blockers, four *ships-without* subsections, the release
  path and seven post-release triggers

- [ ] **Step 1: Walk every line and record one of four dispositions**

*closed by this phase*, *narrowed by this phase*, *still open with the reason*, *outside the
repository*. The walk is the deliverable; a line with no disposition is the failure this task exists to
prevent.

- [ ] **Step 2: Close three**

The **RBS sig-diff baseline** — phase 10 is the last phase to touch `sig/` in every gem (Task 5), so it
is the phase that can establish a baseline over a tree nothing else will change. Regenerate **both**:
the `sig/**/*.rbs` tree and the runtime surface manifest, because "`rbs` describes what someone wrote,
not what Ruby defines" and `Data.define`'s generated readers are invisible to the first.
**`gates:bounded_map` green** (Task 4). **The `XCUT-12` post-release trigger** (Task 9), removed with
the reason recorded.

- [ ] **Step 3: Narrow two**

The conformance-run caveat blocker gains the waivers Task 3 Step 3 re-measured and
`APPENDIX_B.md`'s `by reference` residue — **the majority of the map's 61 rows**, and the largest single
thing a green run does not prove. The worked-example blocker gains the correlation chain (Task 16 Step
3).

- [ ] **Step 4: Add one blocker, two *ships-without* entries, one trigger**

The blocker: Task 17's amendment set applied, **or** the release notes naming which design sentences a
reader should not trust. The two entries, both under *Behavioural asymmetries a consumer must know*:
the HTTP-tracer vocabulary's operation-lifecycle triple and transport-milestone group have **no wired
emitter** in v1, with `OBS-29`'s own follow-up clause as why that is conforming; and the correlation
chain is **driven by the SDK author**, with `ContextStore`'s cap and `CTX-19`'s reachability exercised
only by phase 4a's tests. The trigger: a **second** continued-clause true positive for Task 7's check →
write the sentence-spanning form; one instance is an anecdote.

- [ ] **Step 5: Correct the Minitest trigger's measurement**

Its per-interpreter versions are phase 9's and two are stale. Task 1 Step 4's numbers replace them,
dated, with the duplicate-load mechanism added: on the 3.4 row a newer minitest in the **user** gem
directory wins a bare `require`, and loading it alongside the interpreter's copy emits
`already initialized constant` warnings that `NFR-6`'s gate turns into a failure. The pin stays phase
0's Task 2; the reason it is load-bearing widens.

- [ ] **Step 6: Refuse to mark `NFR-4` ✅, and say so in the row**

`api-design/46c8b5fc` is `NFR-4` verbatim and its subject is a diff against the previous release tag;
there is no tag. Phase 10 establishes the baseline and leaves the disposition ⏳, citing phase 9's row
and `P0-8`'s pre-release branch. **Establishing a baseline is not satisfying a requirement about
comparing against one** — and marking it ✅ would be exactly the claim this phase exists to catch.

- [ ] **Step 7: Confirm nothing was published**

No tag, no `gem push`, every gem at `0.0.0`, `docs/first-release.md`'s § Release path still "not yet
defined". Phase 10 defines no release process; where one is genuinely missing it is a line in this
file, not an invention.

---

## Task 19: close the phase

**Files:**
- Create: `docs/work/mvp/phase10/2026-09-13-phase10-deviation-reconciliation-and-release-readiness-checklist.md`
- Modify: `CLAUDE.md`, `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`
- Read only: `docs/knowledge/notes/observability.md` — Step 4 **confirms** the entry that was filed with
  the design and does not re-file it; a missing entry is a defect to report
- Read only: `docs/README.md` — checked, not changed. Its ownership table already covers
  `docs/work/<delivery>/phaseN/`, and it states neither a phase count nor a probe-check count, so phase
  10 gives it nothing to update. Step 6 confirms that by running the probe's `readmes` check

- [ ] **Step 1: Write the checklist — 188 rows**

124 own rows, one per ID named by design §10's nineteen entries plus the closing note, each with its
mark (✅ / 🚫 / ⏳ / N/A), its `R1` verdict, the as-built evidence and the task. 64 cross-reference rows,
each naming the repair and the owning phase's row it cross-references. **A requirement in scope with no
row is the failure this project is structured to prevent**; the map above is what the rows are checked
against, and `gates:ledger_audit` is what checks the register they feed.

- [ ] **Step 2: `CLAUDE.md`**

The `claims` count goes from **ten phase directories to eleven**, and the phase-9 paragraph gains a
phase-10 paragraph in the same voice: no segmentation design and no sub-phase, the decision argued
rather than assumed, 124 own rows plus 64 cross-reference rows, the thirteen amendments, and that its
checklist is still to be written at execution time. The "Eight checks" sentences become **nine** (Task
7). The gate count in the "After scaffold" block gains `gates:ledger_audit`, `gates:spdx_rbs` and
`gates:sole_parse`. The "Zero gems exist under `gems/`" sentence is unaffected by planning and will be
false once phase 0 runs; phase 0 owns it.

- [ ] **Step 3: The roadmap**

A dated status note in the style of phases 8 and 9: what was filed, the segmentation decision and its
argument, the scope, the thirteen amendments, the repairs, what was postponed and to which
`docs/first-release.md` section, the findings and their owners, and the one knowledge note. The
inbound list gains **eight dated bullets** under its own growth rule, and a dated head note pointing at
the design's disposition table as the one place every bullet's owner lives. **It does not restate the
per-bullet owners**, which is what the head note filed on 2026-09-13 already says and the reason it says
it: the table and a copy of it beside the bullets are two things that would diverge, and the roadmap is
an index. What stops the list being an inbox is that the head note asserts all thirty-two are
dispositioned and names where to check.

- [ ] **Step 4: Confirm the one knowledge note, do not re-file it**

`docs/knowledge/notes/observability.md`'s `OBS-29` entry was **filed with the design on 2026-09-13**, on
phase 9's precedent, because a resolution recorded only in a design document is re-litigated by whoever
reads the corpus next. This step confirms it is still there and still linked: `ruby scripts/knowledge.rb
--key observability/2da9e2f3` must print `[overridden by notes/observability.md]`;
`ruby scripts/verify_knowledge_structure.rb` must report **52 note entries, every cited key live**; and
`ruby scripts/knowledge_drift.rb` must report **0 DRIFT** and **0** unresolved note citations. A missing
entry is a defect to report, not one to re-file.

**Two things this step must not do.** It must not add a second note for any of phase 10's other findings:
a note earns its place by overriding a harvested rule an implementation found false, and the other six
are corrections to writable documents, measurements of third-party source or machine state, or a defect
in a phase plan — none of which a harvested rule asserts. And it must not cite a note's own key: the
structure gate rejects a backticked key no **harvested** entry carries, which is why the existing entry
names this file's other two by `sha:` marker instead.

- [ ] **Step 5: The full gate set, on every matrix row**

`bundle exec rake` on 3.2.11, 3.3.12, 3.4.10 and 4.0.6. **The expected end state is green**, which is
the difference from phase 9's expected end state and is the point of this phase: `gates:bounded_map` is
green because Task 4 closed it, `PackagingSuite`'s SPDX assertion is green because Task 5 did, and the
three new gates are green because Tasks 2, 5 and 6 built them against failing fixtures first. Any row
that is not green is recorded with the reason and a `docs/first-release.md` line.

- [ ] **Step 6: `ruby .claude/skills/housekeeping/probe.rb` — `no drift found`**

Then `ruby -w .claude/skills/housekeeping/test/run.rb` and `ruby -w scripts/test/knowledge_test.rb`,
because Task 7 changed the probe and Step 4 changed the corpus. **Never rewrite prose to satisfy a
check**: the probe says what is wrong and where, and the judgement about what the sentence should say
is the writer's.

- [ ] **Step 7: Confirm, do not re-file, what phase 10 postponed**

Three items, each already owning a `docs/first-release.md` line: the amendment set's application, Task
7's continued-clause blind spot, and an `NFR-4` diff as opposed to a baseline. A missing entry is a
defect to report, not one to re-file elsewhere. And **no register is created**: both item-ID namespaces
were retired on 2026-09-13 and neither is reused.
