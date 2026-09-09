# Phase 5c — Tracing and Metrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `dexpace-core`'s tracing and metrics subsystem: the span and scope protocols behind
phase 4a's three published singletons, the current-span carrier and log-correlation scope pushing
and restoring diagnostic-context keys (`trace.id`, `span.id`), W3C/Datadog trace-id generation on
`TraceIdFlavour` with zero-draw coercion, `Bundle#sampled?`, the HTTP-shaped tracer event vocabulary
and its lifecycle ordering contract, and the metrics SPI with its allocation-free no-op meter.
**Twelve IDs, of which eleven are implemented and `OBS-32` is ⏳ `DEF-9`.** `OBS-24` is in the
`OBS-21`–`OBS-33` range and is **`5b`'s**, not 5c's — the charter's arithmetic says otherwise and
its own prose says twice that it is `5b`'s, which is the reading both sub-phase designs act on
(`OI-30`). Bounded by `OBS-20`, `OBS-30`, `CTX-20`, `XCUT-11` and `XCUT-20`; consuming `SEAM-28`'s
stable operation identifier; closing `DEF-37` and `DEF-1`'s second half.

**Architecture:** A lightweight, allocation-free tracing and metrics SPI inside `dexpace-core`
comprising stateless frozen singletons (`NO_SPAN`, `NO_TRACER`, `NO_TRACER_FACTORY`, `NO_SCOPE`,
`NULL`, `NO_METER`), a module of module functions (`Dexpace::Instrumentation::Tracing`) managing one
per-fiber current-span slot (`:"dexpace.current_span"`) and delegating log correlation to fiber
storage keys (`Diagnostics::TRACE_ID`, `Diagnostics::SPAN_ID`), an immutable 3-ivar scope handle
(`Scope`) restoring previous values through the Ruby call stack, a CSPRNG trace-id generator
anchored on `SecureRandom`, an 11-method HTTP tracer module (`HTTPTracer`) and bus adapter
(`CallableAdapter`), and a no-op meter returning shared instrument singletons. Concurrency safety is
structural: no locks, no threads, no interrupts, no mutexes, and zero defensive catching of foreign
tracer/meter exceptions (`OBS-20`, `OBS-30`).

**Tech Stack:** Ruby 3.2–4.0 (tested on 3.4.10), zero runtime dependencies, allowlisted stdlib gem
(`securerandom`), Minitest, RBS + Steep, RuboCop with phase 0's custom cops, SimpleCov, YARD.

**Spec:** `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-design.md`, under the
charter `docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md`.
`docs/product-spec/15-instrumentation-and-observability.md` §15.5–§15.8 are the normative sections;
`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` carries the canonical
text for `OBS-21`–`OBS-33` and related cross-cutting requirements (`CTX-20`, `SEAM-28`, `OBS-20`,
`OBS-34`, `DEF-37`).

---

## Global Constraints

- **`dexpace-core` gains no dependency and the require allowlist does not grow.** The gemspec
  contains zero `add_dependency` lines (`SEAM-1`, `NFR-1`). Core may `require` only entries from the
  phase 0 allowlist: `monitor`, `uri`, `stringio`, `strscan`, `time`, `date`, `securerandom`,
  `digest`, `openssl`, `forwardable`, `set`, `singleton`. Phase 5c requires exactly one allowlisted
  entry: `securerandom` (for `OBS-27`'s trace-id generation). Core **never `require`s `logger`**
  (`CLAUDE.md`, boundary 1).
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`).
- **Inside `module Dexpace`, anywhere, every core constant is `::`-qualified**: `::Thread`,
  `::Fiber`, `::Time`, `::Data`, `::Object`, `::StandardError`, `::ArgumentError`, `::TypeError`,
  `::Exception`, `::SecureRandom`, `::Kernel`. Conversion methods are written `::Kernel.Integer(...)`
  or `::Kernel.Float(...)` — never bare `Integer(...)`.
- **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are strictly forbidden**
  (`Dexpace/NoThreadInterrupt`). Phase 5c starts no thread, takes no lock and performs no wait.
  Concurrency safety is structural, resting on frozen stateless singletons and `Fiber[]` slot
  isolation (`OBS-30`, `CTX-20`, `XCUT-11`).
- **`downcase` is called with no arguments repository-wide** (`Dexpace/NoLocaleCaseFold`).
  `TraceIdFlavour#generate_trace_id` produces lowercase hex by construction (`String#unpack1("H*")`
  or `SecureRandom.hex`) without relying on case-folding.
- **No method takes a `**` keyword splat (`P5-42`, `OI-28`).** A `**attributes` keyword splat
  allocates one `Hash` per call even when empty (verified fact 1: 1002 / 1000 calls). `OBS-25` makes
  it a MUST that selecting a no-op path MUST NOT allocate per call. Every attributes parameter in this
  segment is one named optional keyword (`attributes: nil`).
- **`Fiber[:key]` is the diagnostic-context carrier, not `Thread.current[:key]`** (`CLAUDE.md`,
  boundary 14). `Fiber[]` is inherited by child fibers and new threads. The previously active span
  is held in the `Scope` handle's own ivar on the Ruby call stack, never in a stack in fiber storage,
  because fiber storage copy-on-write protects the *slot*, not the object in it (`R13`, verified
  fact 2).
- **Domain model construction pattern:** `Data.define`, `private_class_method :new`, `.build`
  with `Model.required!` for fail-fast validation (`SEAM-29`), defensive collection copies, and
  shallow `freeze`. Note exception: `Scope` is a per-call resource handle with 3 ivars, not a `Data`
  (`P5-46`, verified fact 5).
- **`OBS-20`'s asymmetry honoured:** Core wraps no foreign tracer or meter calls (`OBS-20`,
  `OBS-30`). Implementations must not throw, but if a foreign callback throws, it propagates directly
  to the caller. `ensure` blocks in `Tracing.with_span` and `with_correlated_span` guarantee scope
  restoration even when exceptions propagate.
- **Independence from the logging half:** 5c ships no logger, no event, no sink, no redactor, no
  configuration accessor and no pipeline step, and reads no log level. `Tracing`, `Scope`,
  `NO_METER` and `HTTPTracer` have no constructor parameter, no ivar and no method argument through
  which a level could reach them. That is what makes `5b`'s `OBS-34` test at `HTTPLogging::NONE`
  writable; **it does not discharge `OBS-34`, which is `5b`'s ID** (`R11`, Task 11).
- **The one crossing dependency, stated rather than discovered:** `scope.rb` and `tracing.rb`
  `require_relative "diagnostics"` for `5b`'s `Diagnostics::TRACE_ID` and `::SPAN_ID`, which are
  **`Symbol`s** and are `5b`'s to declare (`R11`, reversing 5c's draft). **5c declares no
  diagnostic-context key-name constant, ships no `instrumentation/keys.rb`, and fixes no OTel
  instrument name, unit or attribute set** — `Keys::INSTRUMENT_REQUEST_COUNT` and
  `::INSTRUMENT_REQUEST_DURATION` are `5b`'s. `diagnostics.rb` requires nothing else in `5b` and
  defines no `Event`, so the require drags nothing. Nothing else in 5c waits on `5a` or `5b`.
- **Formatting:** double quotes, 2-space indentation, 100 columns, `consistent_comma` trailing
  commas.

### Commands

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/<path>_test.rb # one suite
(cd gems/dexpace-core && bundle exec rake test)                                   # core suite
bundle exec rake                                                                  # all 17 gates
bundle exec rubocop                                                               # linting gates
bundle exec steep check                                                           # Steep typing
bundle exec rbs validate                                                          # RBS validation
bundle exec rake surface:regenerate                                               # deliberate; Task 12
```

### What was verified during planning, and how

**One interpreter, and this plan states it explicitly.** All facts in the design were verified on
Ruby 3.4.10 (`ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]`). **Only 3.4.10
is installed on this machine**; `mise ls` lists `bun`, `go`, `node` and `opencode` and no Ruby;
`~/.rbenv`, `~/.rvm` and `/opt/rubies` do not exist. **The 3.2.11 and 4.0.6 columns have not been
run.** Task 1 instructs the worker to install both and run the matrix facts.

The following were re-run on 3.4.10 while writing this plan, and **on nothing else**. Facts 2, 3,
4 and 6 are the floor-straddling ones and carry a standing test (Task 1); facts 1, 5, 7 and 8 are
VM-behaviour measurements with no standing test of their own — 1 and 7 are re-measured inside
`OBS-25`'s and `OBS-30`'s own assertions, and 5 and 8 are design inputs rather than claims the
suite makes.
1. `def m(x, **kw)` allocates 1002 objects per 1000 calls when called as `m(1)` with no keyword
   arguments; `def m(x, attributes: nil)` allocates 4 objects per 1000 calls (`P5-42`).
2. `Fiber[:arr] = []` followed by `<<` inside `Thread.new` mutates the parent's Array; rebinding
   `Fiber[:span] = :child` in a child thread leaves the parent's slot untouched.
3. `Fiber["trace.id"] = "val"` sets `Fiber.current.storage.keys` to `[:"trace.id"]`; `Symbol#name`
   returns the identical frozen `String` on every call (`assert_same`).
4. `Fiber[:k] = nil` deletes the key (`Fiber.current.storage.key?(:k)` is `false`), whereas
   `Fiber.current.storage = { k: nil }` retains the key with a nil value.
5. A 3-ivar class allocates 1003 objects per 1000 allocations; `Data.define` allocates 2003.
6. `require "securerandom"` adds 2 entries to `$LOADED_FEATURES` and does not load `openssl` or
   `logger`; `Gem::BUNDLED_GEMS::SINCE["securerandom"]` is `nil`. **Read on 3.4.10 only** — the
   sentence previously said "across all supported Rubies", which no run supports and which the
   paragraph above contradicts. What the 3.4.10 table *does* license is stronger than one column:
   it is forward-looking and already carries `"4.0.0"` for `logger`, `ostruct`, `benchmark`,
   `fiddle` and `pstore` and `"3.4.0"` for `base64`, so 3.4.10's own table enumerates the
   gemification through 4.0.0 and does not name `securerandom`. That is evidence, not the 4.0.6
   run; Task 1 is still where the column is closed.
7. Frozen singletons are visible as identical objects (`assert_same`) across 16 concurrent threads.
8. `NoHistogram#record` accepts `Float::NAN`, `Float::INFINITY`, `-Float::INFINITY`, `0`, and `-1`
   without throwing, returning `nil`.

---

## This plan's open questions, resolved

The design closes with six open questions. All six are resolved below with concrete decisions and
rationales:

1. **Re-running the four floor-straddling facts on 3.2.11 and 4.0.6.**
   *Decision:* Task 1 installs `ruby@3.2.11` and `ruby@4.0.6` via `mise` and runs the matrix facts
   suite on all three. **This has not happened**: only 3.4.10 is installed on the machine this plan
   was written on, verified at review time, and Task 1's commands are instructions rather than a
   record. If an interpreter cannot be installed, the execution report records the limitation and
   claims narrow to the versions that ran. The per-fact consequence of a *failing* fact is fixed in
   Task 1, Step 5's table rather than improvised — facts 2 and 6 included, which the draft left
   unstated.
2. **`opentelemetry-api`'s exact method names and arities for `Tracer`, `Span`, and metrics SPI.**
   *Decision:* **The gem is not installed on this machine and no claim below is verified against
   it** — re-checked at review time; `gem list` shows no `opentelemetry-*`. This is the same limit
   phase 4a hit for `#tracer`'s arity (`P4-8`, whose comment cites the gem source 4a fetched from
   rubygems.org on 2026-09-08) and the reason `OI-29` marks its `TracerProvider`-caches claim as
   motivation rather than measurement. Core adopts the signatures the design specifies, and **Task 3
   confirms each against the gem's source before the method names are locked**, recording any
   divergence as a ledger row rather than silently adopting it — a name that is nearly right is
   worse than one that is deliberately different. `NO_TRACER_FACTORY#tracer`'s five-argument shape
   is *not* in scope for that check: it is 4a's, verified against the gem there, and boundary 10
   forbids changing it. The signatures under review:
   - `_Tracer`: `#start_span(name, attributes: nil, kind: nil, with_parent: nil)`, `#in_span(name, attributes: nil, kind: nil) { |span| }`
   - `_Span`: `#recording?`, `#set_attribute(key, value)`, `#add_event(name, attributes: nil)`, `#record_error(error, attributes: nil)`, `#status=(status)`, `#finish(end_timestamp: nil)`, `#context`
   - `_Meter`: `#create_counter(name, unit: nil, description: nil)`, `#create_histogram(name, unit: nil, description: nil)`
   - `_Counter`: `#add(amount, attributes: nil)`
   - `_Histogram`: `#record(amount, attributes: nil)`
   `P5-42` is non-negotiable and this check cannot reopen it: if the gem spells a parameter
   `**attributes`, core's own signature stays named and the adapter pays the one-line bridge,
   because `OBS-25` is a MUST and call-compatibility is a design preference. Every signature above
   uses named optional keywords (`attributes: nil`), never a splat. **Whatever the check returns,
   `5b` has already written these names into its step and its `OBS-34` conformance test**, so a name
   that moves here moves there in the same change; state the divergence rather than letting the two
   documents drift.
3. **Whether `record_error` or `record_exception` is the right name.**
   *Decision:* Core uses `record_error(error, attributes: nil)` (`P5-41`), and this is a **choice
   against** `opentelemetry-api`'s `record_exception` rather than an alignment with it: `OBS-21`
   says "all mutators (attribute/error)", the SDK's own vocabulary is `Dexpace::Error` and
   `#each_cause`, and `error.type` is `OBS-39`'s field key. `P5-41` already carries the name; if
   question 2's check shows the gem's spelling is load-bearing for the structural subset, the
   reversal is a ledger row, not a silent rename. The OpenTelemetry adapter gem may alias
   `record_exception` post-v1.
4. **Whether `Tracing`'s current-span slot should also be readable by 5b's fold.**
   *Decision:* No. `CURRENT_SPAN_KEY = :"dexpace.current_span"` is a `private_constant`, declared
   once in `scope.rb` because `Scope#close` and `Tracing` both write that slot and one key must not
   have two spellings. `Tracing.current_span` is the only reader exposed. `OBS-10`'s default
   allow-list is exactly `{trace.id, span.id}`; the current span is not diagnostic context and must
   never be folded. If `5b` needs the span itself for an event field that is a `.current_span` call,
   not a third key name (boundary 15).
5. **How `#generate_trace_id` takes its randomness source.**
   *Decision:* An optional positional parameter defaulting to `::SecureRandom`:
   `def generate_trace_id(generator = ::SecureRandom)`. Positional avoids keyword-argument
   allocation, avoids the process-wide module swap `testing/4ef070df` forbids, and is what lets the
   test inject a generator that draws zero — `OBS-27`'s coercion clause is unreachable by sampling.
   It is a test seam and not part of the requirement's surface, which is why it is not a keyword.
   **Confirm on Task 2 that a positional parameter here does not trip `api-design/1d9e6e0b`'s
   keywords-everywhere rule**; if it does, take the named keyword and pay one allocation on a
   per-operation path where `OBS-25` does not bind.
6. **Whether the load-time independence assertion is expressible as written.**
   *Decision:* Yes, and it is verified rather than assumed: Task 11 drives a subprocess that
   `require`s 5c's files plus `5b`'s `diagnostics.rb` — which requires nothing else in `5b` and
   defines no `Event` — and asserts `defined?(Dexpace::Instrumentation::Event)` is `nil` while
   exercising tracing and metrics. `require`, not `require_relative`: the latter has no stable
   basepath from `ruby -e` across the supported range. If `lib/dexpace.rb` ever becomes the only
   entry point, the assertion weakens to a require-scan and **the weakening is recorded**.

---

## Task order and dependency chain

Twelve tasks, in exact buildable dependency order:

1. **Matrix fact verification and test support doubles** (`RecordingSpan`, `RecordingTracer`, `RecordingMeter`) — installs interpreters if possible, verifies facts on all three, and builds the three doubles later tasks need. The fourth double, `RecordingHTTPTracer`, is Task 8's: the design makes it a fake that **includes `HTTPTracer`** and overrides all eleven, and the module does not exist until Task 8.
2. `TraceIdFlavour#generate_trace_id` and `Bundle#sampled?` (`OBS-26`, `OBS-27`, `DEF-37`) — W3C/Datadog generation, zero coercion, and flag bit inspection; standalone modification of existing 4a models.
3. `NO_SPAN` widening and `_Span` RBS interface (`OBS-21`, `OBS-25`, `DEF-37`) — implements no-op span protocol, mutators, and idempotent `#finish`; needs Task 1's `RecordingSpan`.
4. `NO_TRACER`, `NO_TRACER_FACTORY` and `_Tracer` RBS interfaces (`OBS-25`, `OBS-29`, `OBS-30`, `CTX-20`, `DEF-37`) — implements no-op tracer protocol and concurrent factory; needs Task 3's `NO_SPAN` and Task 1's `RecordingTracer`.
5. `Dexpace::Instrumentation::Scope` and `NO_SCOPE` (`OBS-22`, `OBS-25`, `DEF-37`) — 3-ivar scope handle and cached singleton; needs Task 3's `NO_SPAN`.
6. `Dexpace::Instrumentation::Tracing` (`OBS-22`, `OBS-23`, `OBS-25`, `OBS-30`) — `.current_span`, `.activate`, `.with_span`, `.correlate`, `.with_correlated_span`; needs Tasks 3, 4, 5, and Task 1's `RecordingSpan`.
7. `Dexpace::Instrumentation::NO_METER` and the Metrics SPI (`OBS-31`, `OBS-33`, `OBS-30`) — no-op meter, counter, histogram singletons, and `_Meter` interfaces; needs Task 1's `RecordingMeter`.
8. `Dexpace::Instrumentation::HTTPTracer` and `NULL` (`OBS-28`, `OBS-29`, `OBS-30`) — 11-method default no-op event vocabulary module, `NULL` singleton, and the `RecordingHTTPTracer` double that includes the module; standalone.
9. `Dexpace::Instrumentation::CallableAdapter` (`OBS-28`, §8.1) — bus-shape adapter wrapping `#call(name, payload)`; needs Task 8's `HTTPTracer`.
10. Lifecycle ordering contract verification (`OBS-29`, `DEF-42`) — verifies emission contract and exhausted→failed pairing against Task 8's `RecordingHTTPTracer`.
11. Structural independence from the logging half (`R11`; **no 5c ID** — `OBS-34` is `5b`'s) — proves 5c operates with no log level, no sink and `Event` undefined; needs Tasks 2–9 and `5b`'s `diagnostics.rb`.
12. Final wiring, surface snapshot, RBS baseline, checklist, and register updates (`DEF-37`, `DEF-1`, `DEF-30`, `DEF-42`, `OI-28`, `OI-29`) — updates `lib/dexpace.rb`, regenerates snapshot, validates RBS/Steep, and records register dispositions.

---

## Task 1: Matrix Fact Verification and Test Support Doubles

**Requirement IDs:** `OBS-21`, `OBS-25`, `OBS-27`, `OBS-29`, `OBS-30`, `OBS-31`, `OBS-33`.
**Design:** "The verified Ruby facts this phase is built on" (Facts 1, 2, 3, 4, 6, 7, 8); "Testing strategy" (Four doubles, all fakes).

**Files:**
- Create: `gems/dexpace-core/test/support/recording_span.rb`
- Create: `gems/dexpace-core/test/support/recording_tracer.rb`
- Create: `gems/dexpace-core/test/support/recording_meter.rb`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/tracing_matrix_facts_test.rb`

**Interfaces:**
- Consumes: Ruby stdlib (`securerandom`; `Fiber` is core, not a require).
- Produces: `Dexpace::RecordingSpan`, `Dexpace::RecordingTracer`, `Dexpace::RecordingTracerFactory`, `Dexpace::RecordingMeter`, `Dexpace::RecordingCounter`, `Dexpace::RecordingHistogram`. (`Dexpace::RecordingHTTPTracer` is Task 8's.)

**The file is `tracing_matrix_facts_test.rb` and not `matrix_facts_test.rb`, and that is a
reconciliation fix.** Both this plan and `5b`'s claimed
`test/dexpace/instrumentation/matrix_facts_test.rb` — two different suites at one path, written in
isolated worktrees, and whichever landed second would have overwritten the first with no conflict to
notice, because the class names differ. `5b`'s is `logging_matrix_facts_test.rb`. `5a`'s
`test/dexpace/matrix_facts_test.rb` sits a directory up and is untouched by either.

**`5b` consumes `recording_tracer.rb`, `recording_span.rb` and `recording_meter.rb` and declares none
of their six constants** — `RecordingCounter` and `RecordingHistogram` included. Its step test aliases
`Dexpace::RecordingTracerFactory`, `Dexpace::RecordingTracer` and `Dexpace::RecordingMeter` and reads
`factory.tracers`, `span.finished_at`, `meter.counters` and `meter.histograms`, which are the readers
below. A rename here is a rename in `5b`'s Task 15.

- [ ] **Step 1: Install interpreters and record status**

```bash
mise install ruby@3.2.11 ruby@4.0.6 || true
mise exec ruby@3.2.11 -- ruby -v || echo "3.2.11 unavailable"
mise exec ruby@4.0.6  -- ruby -v || echo "4.0.6 unavailable"
```

**Only 3.4.10 exists on the machine this plan was written on** — re-verified at review time: `mise
ls` lists `bun`, `go`, `node` and `opencode` and no Ruby, and `~/.rbenv`, `~/.rvm` and
`/opt/rubies` do not exist. Nothing below has been run on 3.2.11 or 4.0.6; the commands are
instructions, not a record. Paste each interpreter's real output into the execution report.

- [ ] **Step 2: Write the failing matrix facts test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_span"
require_relative "../../support/recording_tracer"
require_relative "../../support/recording_meter"

# OBS-21, OBS-25, OBS-27, OBS-29, OBS-30, OBS-31, OBS-33: the floor-straddling facts the segment
# rests on (design facts 2, 3, 4 and 6), re-run on every interpreter in the matrix, plus the
# shape of the three recording fakes P5-48 makes every recording-branch assertion run against.
class TracingMatrixFactsTest < DexpaceTestCase
  def teardown
    ::Fiber[:dexpace_test_slot] = nil
    ::Fiber[:"trace.id"] = nil
    ::Fiber[:"span.id"] = nil
    super
  end

  test "Fact 1: named optional keyword allocates nothing; splat allocates Hash per call" do
    def sample_splat(x, **attributes); end
    def sample_named(x, attributes: nil); end

    ::GC.disable
    begin
      start_splat = ::GC.stat(:total_allocated_objects)
      1000.times { sample_splat(1) }
      delta_splat = ::GC.stat(:total_allocated_objects) - start_splat

      start_named = ::GC.stat(:total_allocated_objects)
      1000.times { sample_named(1) }
      delta_named = ::GC.stat(:total_allocated_objects) - start_named

      assert_operator delta_splat, :>=, 1000
      assert_operator delta_named, :<, 10
    ensure
      ::GC.enable
    end
  end

  test "Fact 2: fiber storage copy-on-write protects slot, not mutable object in it" do
    ::Fiber[:dexpace_test_arr] = []
    child_id = nil
    t = ::Thread.new do
      ::Fiber[:dexpace_test_arr] << :mutated
      child_id = ::Fiber[:dexpace_test_arr].object_id
    end
    t.join

    assert_equal([:mutated], ::Fiber[:dexpace_test_arr])
    assert_equal(::Fiber[:dexpace_test_arr].object_id, child_id)

    ::Fiber[:dexpace_test_slot] = :parent
    t2 = ::Thread.new do
      ::Fiber[:dexpace_test_slot] = :child
    end
    t2.join
    assert_equal(:parent, ::Fiber[:dexpace_test_slot])
  ensure
    ::Fiber[:dexpace_test_arr] = nil
  end

  test "Fact 3: Fiber accepts String key and interns; Symbol#name preserves identity" do
    ::Fiber["trace.id"] = "trace-fact-3"
    assert(::Fiber.current.storage.key?(:"trace.id"))
    assert_equal("trace-fact-3", ::Fiber["trace.id"])

    sym = :"trace.id"
    assert_same(sym.name, sym.name)
    assert_predicate(sym.name, :frozen?)
  end

  test "Fact 4: Fiber[:k] = nil deletes key from storage" do
    ::Fiber[:dexpace_test_slot] = "exists"
    assert(::Fiber.current.storage.key?(:dexpace_test_slot))

    ::Fiber[:dexpace_test_slot] = nil
    refute(::Fiber.current.storage.key?(:dexpace_test_slot))
  end

  test "Fact 6: securerandom is permanently default and does not load openssl" do
    require "securerandom"
    hex = ::SecureRandom.hex(16)
    assert_match(/\A[0-9a-f]{32}\z/, hex)

    if defined?(::Gem::BUNDLED_GEMS::SINCE)
      assert_nil(::Gem::BUNDLED_GEMS::SINCE["securerandom"])
    end
  end

  test "Fact 7: frozen singleton reference is identical across 16 threads" do
    singleton = ::Object.new.freeze
    results = Array.new(16)
    threads = Array.new(16) do |i|
      ::Thread.new { results[i] = singleton }
    end
    threads.each(&:join)
    results.each { |res| assert_same(singleton, res) }
  end

  test "Test support doubles instantiate with expected interface contracts" do
    span = Dexpace::RecordingSpan.new
    assert_predicate(span, :recording?)
    span.set_attribute("k", "v")
    assert_equal("v", span.attributes["k"])

    tracer_factory = Dexpace::RecordingTracerFactory.new
    tracer = tracer_factory.tracer("op")
    assert_instance_of(Dexpace::RecordingTracer, tracer)

    meter = Dexpace::RecordingMeter.new
    counter = meter.create_counter("c")
    histogram = meter.create_histogram("h")
    assert_instance_of(Dexpace::RecordingCounter, counter)
    assert_instance_of(Dexpace::RecordingHistogram, histogram)
  end
end
```

- [ ] **Step 3: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/tracing_matrix_facts_test.rb`
Expected: fails with `LoadError` loading `recording_span`.

- [ ] **Step 4: Write the three test support doubles**

All three are **fakes**, not mocks or stubs (`testing/7ecef8e8`, `/630ba094`): `P5-48` says core
ships no recording span, tracer or meter, so every recording-branch clause of `OBS-21`, `OBS-29`,
`OBS-30` and `OBS-31` is asserted against these. `5b`'s step tests consume `RecordingSpan`,
`RecordingTracer` and `RecordingMeter` and add no second set (`DEF-29`); the method names in them
are 5c's, and a rename here is a rename there.

Write `gems/dexpace-core/test/support/recording_span.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  class RecordingSpan
    attr_reader :attributes, :events, :errors, :status, :finished_at

    def initialize(recording: true, context: nil)
      @recording = recording
      @context = context
      @attributes = {}
      @events = []
      @errors = []
      @status = nil
      @finished_at = []
    end

    def recording?
      @recording
    end

    def set_attribute(key, value)
      @attributes[key] = value if @recording
      self
    end

    def add_event(name, attributes: nil)
      @events << { name: name, attributes: attributes }.freeze if @recording
      self
    end

    def record_error(error, attributes: nil)
      @errors << { error: error, attributes: attributes }.freeze if @recording
      self
    end

    def status=(status)
      @status = status if @recording
      status
    end

    def finish(end_timestamp: nil)
      return nil unless @recording
      return nil unless @finished_at.empty?

      @finished_at << (end_timestamp || ::Time.now).freeze
      nil
    end

    def context
      @context
    end
  end
end
```

Write `gems/dexpace-core/test/support/recording_tracer.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "recording_span"

module Dexpace
  class RecordingTracerFactory
    attr_reader :tracers

    def initialize
      @tracers = []
    end

    def tracer(deprecated_name = nil, deprecated_version = nil, name: nil, version: nil,
               attributes: nil)
      tracer_name = name || deprecated_name
      tracer_ver = version || deprecated_version
      t = RecordingTracer.new(name: tracer_name, version: tracer_ver)
      @tracers << t
      t
    end
  end

  class RecordingTracer
    attr_reader :name, :version, :spans

    def initialize(name: nil, version: nil)
      @name = name
      @version = version
      @spans = []
    end

    def start_span(name, attributes: nil, kind: nil, with_parent: nil)
      span = RecordingSpan.new
      span.set_attribute("span.name", name)
      attributes&.each { |k, v| span.set_attribute(k, v) }
      @spans << span
      span
    end

    def in_span(name, attributes: nil, kind: nil)
      span = start_span(name, attributes: attributes, kind: kind)
      if block_given?
        yield span
      else
        span
      end
    end
  end
end
```

Write `gems/dexpace-core/test/support/recording_meter.rb`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  class RecordingMeter
    attr_reader :counters, :histograms

    def initialize
      @counters = []
      @histograms = []
    end

    def create_counter(name, unit: nil, description: nil)
      c = RecordingCounter.new(name: name, unit: unit, description: description)
      @counters << c
      c
    end

    def create_histogram(name, unit: nil, description: nil)
      h = RecordingHistogram.new(name: name, unit: unit, description: description)
      @histograms << h
      h
    end
  end

  class RecordingCounter
    attr_reader :name, :unit, :description, :records

    def initialize(name:, unit: nil, description: nil)
      @name = name
      @unit = unit
      @description = description
      @records = []
    end

    def add(amount, attributes: nil)
      @records << { amount: amount, attributes: attributes }.freeze
      nil
    end
  end

  class RecordingHistogram
    attr_reader :name, :unit, :description, :records

    def initialize(name:, unit: nil, description: nil)
      @name = name
      @unit = unit
      @description = description
      @records = []
    end

    def record(amount, attributes: nil)
      @records << { amount: amount, attributes: attributes }.freeze
      nil
    end
  end
end
```

- [ ] **Step 5: Run the suite on 3.4.10, then on every interpreter that installed**

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/tracing_matrix_facts_test.rb
mise exec ruby@3.2.11 -- ruby -w gems/dexpace-core/test/dexpace/instrumentation/tracing_matrix_facts_test.rb
mise exec ruby@4.0.6  -- ruby -w gems/dexpace-core/test/dexpace/instrumentation/tracing_matrix_facts_test.rb
```

Expected: PASS with **7 runs**, 0 failures, 0 errors, on each interpreter that installed. Running
it on 3.4.10 alone is not the check — facts 2, 3, 4 and 6 are the floor-straddling kind this
repository has been bitten by three times (`URI::DEFAULT_PARSER` at 3.4.0, `StringIO#read(n, buf)`
at 3.4, `Data#with`'s `initialize` on 3.2), and `OI-13` already records a 3.2-versus-3.4 divergence
inside fact 4's own neighbourhood.

**If an interpreter will not install, say so in the execution report and narrow the claim to the
versions that ran.** If a fact *fails* on a version, the per-fact consequence is fixed here so it
is not improvised:

| Fact | If it does not hold on the floor |
|---|---|
| 2 — `Fiber[]`'s copy-on-write protects the slot, not the object | Nothing changes: `R13` already refuses a stack in fiber storage, and a *stronger* isolation on some version cannot break a design that stores nothing mutable there. Record the divergence and stop. |
| 3 — `Fiber.current.storage` returns `Symbol` keys; `Symbol#name` is identity-stable | 5c is unaffected — it reads no storage map — but the crossing contract to `5b` narrows to the versions observed, and `5b`'s fold takes a memoised key lookup instead of `Symbol#name`. State the narrowing in the execution report; do not edit `5b`'s plan. |
| 4 — `Fiber[:k] = nil` deletes the key | `Scope#close`'s branchless restore is wrong on that version. Fall back to a per-key `key?`-guarded restore that deletes explicitly, and re-state `P5-49` against the version that needs it — `OBS-23`'s "remove it if previously unset" is a MUST and cannot be dropped. |
| 6 — `securerandom` is a permanently-default gem not loading `openssl` | The require allowlist and the bundled-gem rule are at stake, not `OBS-27`. If `Gem::BUNDLED_GEMS::SINCE["securerandom"]` is non-`nil` on any supported Ruby, stop: the draw moves to core's own `Random` — `Random.bytes(16).unpack1("H*")`, which is not a gem at all and which `#generate_trace_id`'s `respond_to?(:hex)` branch already accommodates — and the finding goes to `docs/open-items.md` before any code is written. |

---

## Task 2: Trace-ID Generation on `TraceIdFlavour` and `Bundle#sampled?`

**Requirement IDs:** `OBS-26` (identifiers and validity sentinels), `OBS-27` (W3C and Datadog trace-id generation with zero coercion), `DEF-37` (part).
**Design:** "The object model 5c ships — `TraceIdFlavour`, widened"; "The object model 5c ships — `Bundle#sampled?`"; `P5-44` (no span-id generator).

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/instrumentation/trace_id_flavour.rb`
- Modify: `gems/dexpace-core/lib/dexpace/instrumentation/bundle.rb`
- Modify: `gems/dexpace-core/sig/dexpace/instrumentation/trace_id_flavour.rbs`
- Modify: `gems/dexpace-core/sig/dexpace/instrumentation/bundle.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/trace_id_flavour_test.rb`

**Interfaces:**
- Consumes: `SecureRandom`, `Dexpace::Model`.
- Produces: `TraceIdFlavour#generate_trace_id`, `Bundle#sampled?`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# OBS-26, OBS-27: trace-id generation format and zero-draw coercion.
class DexpaceInstrumentationTraceIdFlavourTest < DexpaceTestCase
  test "OBS-27: W3C flavour generates 32 lowercase hex characters and never sentinel" do
    flavour = Dexpace::Instrumentation::TraceIdFlavour::W3C
    sentinel = flavour.invalid_trace_id

    1000.times do
      id = flavour.generate_trace_id
      assert_match(/\A[0-9a-f]{32}\z/, id)
      refute_equal(sentinel, id)
      assert_predicate(id, :frozen?)
    end
  end

  test "OBS-27: Datadog flavour generates decimal string 64-bit integer and never sentinel" do
    flavour = Dexpace::Instrumentation::TraceIdFlavour::DATADOG
    sentinel = flavour.invalid_trace_id

    1000.times do
      id = flavour.generate_trace_id
      assert_match(/\A[0-9]{1,20}\z/, id)
      refute_equal(sentinel, id)
      assert_operator(::Kernel.Integer(id, 10), :>, 0)
      assert_predicate(id, :frozen?)
    end
  end

  test "OBS-27: NONE flavour always returns invalid sentinel" do
    flavour = Dexpace::Instrumentation::TraceIdFlavour::NONE
    id = flavour.generate_trace_id
    assert_equal(flavour.invalid_trace_id, id)
    assert_predicate(id, :frozen?)
  end

  test "OBS-27: zero draw is coerced to non-zero value for W3C and Datadog" do
    fake_zero_w3c = Object.new
    def fake_zero_w3c.hex(_n); "0" * 32; end

    w3c = Dexpace::Instrumentation::TraceIdFlavour::W3C
    w3c_id = w3c.generate_trace_id(fake_zero_w3c)
    refute_equal(w3c.invalid_trace_id, w3c_id)
    assert(w3c.valid_trace_id?(w3c_id))

    fake_zero_dd = Object.new
    def fake_zero_dd.random_number(_max); 0; end

    dd = Dexpace::Instrumentation::TraceIdFlavour::DATADOG
    dd_id = dd.generate_trace_id(fake_zero_dd)
    refute_equal(dd.invalid_trace_id, dd_id)
    assert(dd.valid_trace_id?(dd_id))
  end

  test "OBS-26: Bundle#sampled? inspects low bit of trace_flags" do
    make_bundle = lambda do |flags|
      Dexpace::Instrumentation::Bundle.build(
        trace_id: "0" * 32,
        span_id: "0" * 16,
        trace_flags: flags,
        # 4a's Bundle#initialize validates trace_state as an Array of two-element String pairs;
        # a String here raises InvalidArgumentError before #sampled? is ever reached.
        trace_state: [],
        flavour: Dexpace::Instrumentation::TraceIdFlavour::W3C,
        remote: false,
      )
    end

    refute_predicate(make_bundle.call("00"), :sampled?)
    assert_predicate(make_bundle.call("01"), :sampled?)
    refute_predicate(make_bundle.call("02"), :sampled?)
    assert_predicate(make_bundle.call("03"), :sampled?)
    assert_predicate(make_bundle.call("ff"), :sampled?)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/trace_id_flavour_test.rb`
Expected: fails with `NoMethodError: undefined method 'generate_trace_id'`.

- [ ] **Step 3: Modify `gems/dexpace-core/lib/dexpace/instrumentation/trace_id_flavour.rb`**

Add `#generate_trace_id(generator = ::SecureRandom)`:
```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "securerandom"
require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Instrumentation
    # OBS-27: trace-id encoding flavours: a frozen Data over a frozen table with an .of factory.
    class TraceIdFlavour < ::Data.define(:name, :trace_id_pattern, :invalid_trace_id)
      include Dexpace::Model
      private_class_method :new

      def self.build(name:, trace_id_pattern:, invalid_trace_id:)
        new(name: name, trace_id_pattern: trace_id_pattern, invalid_trace_id: invalid_trace_id)
      end

      def initialize(name:, trace_id_pattern:, invalid_trace_id:)
        Model.required!("name", name)
        Model.required!("trace_id_pattern", trace_id_pattern)
        Model.required!("invalid_trace_id", invalid_trace_id)

        super
      end

      def valid_trace_id?(trace_id)
        trace_id != invalid_trace_id && trace_id_pattern.match?(trace_id)
      end

      def renders?(trace_id)
        trace_id == invalid_trace_id || trace_id_pattern.match?(trace_id)
      end

      # OBS-27: W3C, Datadog and NONE generation with mandatory zero-draw coercion. `generator`
      # is a test seam, not requirement surface: the coercion clause is unreachable by sampling,
      # so the test injects a generator that draws zero (design open question 5).
      #
      # The coercion is a substitution, not a redraw. The design's word is "redrawn", but a
      # redraw loop against an injected always-zero generator does not terminate, and OBS-27's
      # own words are "a zero draw MUST be coerced to a non-zero value" -- which a fixed non-zero
      # substitution satisfies. Deterministic across two zero draws, which is harmless because a
      # real CSPRNG reaches this branch with probability 2^-128.
      def generate_trace_id(generator = ::SecureRandom)
        case name
        when :w3c
          raw = if generator.respond_to?(:hex)
                  generator.hex(16)
                else
                  generator.bytes(16).unpack1("H*")
                end
          # OBS-27: zero draw coerced to non-zero value
          raw = "00000000000000000000000000000001" if raw == invalid_trace_id
          raw.freeze
        when :datadog
          val = if generator.respond_to?(:random_number)
                  generator.random_number(18_446_744_073_709_551_616)
                else
                  generator.bytes(8).unpack1("Q>")
                end
          # OBS-27: zero draw coerced to non-zero value
          val = 1 if val == 0
          val.to_s.freeze
        when :none
          invalid_trace_id
        else
          raise InvalidArgumentError, "unsupported generator flavour: #{name.inspect}"
        end
      end

      NONE = build(
        name: :none,
        trace_id_pattern: ::Regexp.new("\\A(?!)\\z", timeout: 1.0),
        invalid_trace_id: ("0" * 32).freeze,
      )

      W3C = build(
        name: :w3c,
        trace_id_pattern: ::Regexp.new("\\A[0-9a-f]{32}\\z", timeout: 1.0),
        invalid_trace_id: ("0" * 32).freeze,
      )

      DATADOG = build(
        name: :datadog,
        trace_id_pattern: ::Regexp.new("\\A[0-9]{1,20}\\z", timeout: 1.0),
        invalid_trace_id: "0".freeze,
      )

      ALL = [NONE, W3C, DATADOG].freeze

      def self.of(name)
        ALL.find { |flavour| flavour.name == name } ||
          raise(InvalidArgumentError, "unrecognised trace-id flavour: #{name.inspect}")
      end
    end
  end
end
```

- [ ] **Step 4: Modify `gems/dexpace-core/lib/dexpace/instrumentation/bundle.rb`**

Add `#sampled?` method to `Bundle`:
```ruby
      def sampled?
        (::Kernel.Integer(trace_flags, 16) & 1) == 1
      end
```

- [ ] **Step 5: Modify `sig/` mirrors**

In `sig/dexpace/instrumentation/trace_id_flavour.rbs`:
```rbs
      def generate_trace_id: (?untyped generator) -> String
```

In `sig/dexpace/instrumentation/bundle.rbs`:
```rbs
      def sampled?: () -> bool
```

- [ ] **Step 6: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/trace_id_flavour_test.rb`
Expected: PASS with 5 runs, 0 failures, 0 errors.

---

## Task 3: `NO_SPAN` Widening and `_Span` RBS Interface

**Requirement IDs:** `OBS-21` (recording flag, inert mutators, idempotent finish), `OBS-25` (no-op span default), `DEF-37` (part).
**Design:** "The object model 5c ships — `NO_SPAN`'s class, widened"; `P5-42` (named optional keywords, no splat); `P5-48` (recording assertions run on test fake).

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/instrumentation/no_span.rb`
- Modify: `gems/dexpace-core/sig/dexpace/instrumentation/no_span.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/no_span_test.rb`

**Interfaces:**
- Consumes: `Bundle::NONE` (phase 4a).
- Produces: widened `NO_SPAN` surface and filled `_Span` interface.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_span"
require "dexpace"

# OBS-21, OBS-25: NoSpan surface, inert mutators, and idempotent finish.
class DexpaceInstrumentationNoSpanTest < DexpaceTestCase
  test "OBS-21: NO_SPAN is non-recording, mutators drop data and return self" do
    span = Dexpace::Instrumentation::NO_SPAN

    refute_predicate(span, :recording?)
    assert_same(span, span.set_attribute("http.status_code", 200))
    assert_same(span, span.add_event("cache_hit", attributes: { "tier" => "l1" }))
    assert_same(span, span.record_error(StandardError.new("boom")))
    # `span.status = :ok` as an expression always evaluates to its right-hand side, whatever the
    # method returns, so the assignment form asserts nothing about #status=. public_send is what
    # reaches the method's own return value (OBS-21: the mutator returns the argument and drops
    # it), and #status is not readable back, which is the inertness.
    assert_equal(:ok, span.public_send(:status=, :ok))
    assert_nil(span.finish)
    assert_nil(span.finish(end_timestamp: Time.now))
    assert_same(Dexpace::Instrumentation::Bundle::NONE, span.context)
  end

  test "OBS-21: RecordingSpan mutators record data and finish is idempotent with no duplicate export" do
    span = Dexpace::RecordingSpan.new
    assert_predicate(span, :recording?)

    span.set_attribute("key", "val")
    assert_equal({ "key" => "val" }, span.attributes)

    err = StandardError.new("fail")
    span.record_error(err)
    assert_equal(1, span.errors.size)
    assert_same(err, span.errors.first[:error])

    # Idempotent finish
    t1 = Time.utc(2026, 9, 9, 12, 0, 0)
    t2 = Time.utc(2026, 9, 9, 12, 0, 5)
    span.finish(end_timestamp: t1)
    span.finish(end_timestamp: t2)

    assert_equal(1, span.finished_at.size)
    assert_equal(t1, span.finished_at.first)
  end

  test "P5-42: mutators use named optional keywords and not keyword splats" do
    span = Dexpace::Instrumentation::NO_SPAN
    method_params = span.method(:add_event).parameters
    refute_includes(method_params.map(&:first), :keyrest)
    assert_includes(method_params, %i[key attributes])

    err_params = span.method(:record_error).parameters
    refute_includes(err_params.map(&:first), :keyrest)
    assert_includes(err_params, %i[key attributes])
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/no_span_test.rb`
Expected: fails with `NoMethodError: undefined method 'recording?'`.

- [ ] **Step 3: Modify `gems/dexpace-core/lib/dexpace/instrumentation/no_span.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # CTX-15: no-op span singleton. Widened for OBS-21 and OBS-25 (DEF-37).
    #
    # No `require_relative "bundle"` here, deliberately: bundle.rb requires this file (its
    # Bundle.build defaults `span:` to NO_SPAN) and closes NONE = build(...) at load, so the
    # reverse require makes the cycle fail with
    # `uninitialized constant Dexpace::Instrumentation::Bundle::NO_SPAN` whenever no_span.rb is
    # entered first -- reproduced, not inferred. #context resolves Bundle::NONE at call time and
    # lib/dexpace.rb requires bundle.rb after this file, so nothing is needed here.
    class NoSpan
      # rubocop:disable Lint/UnusedMethodArgument -- OBS-21: every mutator is inert and drops its
      # data; the parameter names are the documented protocol and are kept verbatim (P5-41).
      def recording?
        false
      end

      def set_attribute(key, value)
        self
      end

      def add_event(name, attributes: nil)
        self
      end

      def record_error(error, attributes: nil)
        self
      end

      def status=(status)
        status
      end

      def finish(end_timestamp: nil)
        nil
      end
      # rubocop:enable Lint/UnusedMethodArgument

      def context
        Bundle::NONE
      end
    end
    private_constant :NoSpan

    NO_SPAN = NoSpan.new.freeze
  end
end
```

- [ ] **Step 4: Modify `sig/dexpace/instrumentation/no_span.rbs`**

```rbs
module Dexpace
  module Instrumentation
    interface _Span
      def recording?: () -> bool
      def set_attribute: (String key, untyped value) -> self
      def add_event: (String name, ?attributes: ::Hash[String, untyped]?) -> self
      def record_error: (::Exception error, ?attributes: ::Hash[String, untyped]?) -> self
      def status=: (untyped status) -> untyped
      def finish: (?end_timestamp: ::Time?) -> void
      def context: () -> Bundle
    end

    NO_SPAN: _Span
  end
end
```

The design's `interface _Span` block listed five methods where its own `NO_SPAN` table lists seven;
the reconciliation pass corrected the design, and `#status=` and `#context` are declared here
because its own `NO_SPAN` table ships both with an ID against each (`OBS-21` and
`OBS-25`/`CTX-15`), and an interface a shipped object exceeds is one Steep cannot check the object
against. Both are covered by `P5-41`, which already enumerates "the seven methods on `NO_SPAN`'s
class". `NFR-11` holds: `Bundle` is a `Dexpace::` constant.

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/no_span_test.rb`
Expected: PASS with 3 runs, 0 failures, 0 errors.

---

## Task 4: Widening `NO_TRACER`, `NO_TRACER_FACTORY` and `_Tracer` RBS Interfaces

**Requirement IDs:** `OBS-25` (shared no-op tracer and factory, zero allocations), `OBS-29` (1:1 operation lifecycle), `OBS-30` (concurrency safety, non-throwing), `CTX-20` (concurrent factory), `SEAM-28` (stable operation name), `DEF-37` (part).
**Design:** "The object model 5c ships — `NO_TRACER`'s class, widened"; `P5-43` (1:1 stateful vs shared stateless); `P5-42` (named keywords).

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/instrumentation/no_tracer.rb`
- Modify: `gems/dexpace-core/sig/dexpace/instrumentation/no_tracer.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/no_tracer_test.rb`

**Interfaces:**
- Consumes: `NO_SPAN` (Task 3).
- Produces: widened `NO_TRACER` and `NO_TRACER_FACTORY`, filled `_Tracer` and `_TracerFactory` RBS interfaces.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_tracer"
require "dexpace"

# OBS-25, OBS-29, OBS-30, CTX-20: NO_TRACER surface, identity, and concurrency.
class DexpaceInstrumentationNoTracerTest < DexpaceTestCase
  FROZEN_ATTRS = { "k" => "v" }.freeze

  test "OBS-25: NO_TRACER#start_span returns NO_SPAN by identity" do
    tracer = Dexpace::Instrumentation::NO_TRACER
    span = tracer.start_span("operation", attributes: FROZEN_ATTRS, kind: :client)
    assert_same(Dexpace::Instrumentation::NO_SPAN, span)
  end

  test "OBS-25: NO_TRACER#in_span yields NO_SPAN and returns block result" do
    tracer = Dexpace::Instrumentation::NO_TRACER
    yielded = nil
    result = tracer.in_span("operation", attributes: FROZEN_ATTRS) do |span|
      yielded = span
      :done
    end

    assert_same(Dexpace::Instrumentation::NO_SPAN, yielded)
    assert_equal(:done, result)
  end

  test "OBS-25: no-op tracer path does not allocate per call when given non-allocating arguments" do
    tracer = Dexpace::Instrumentation::NO_TRACER

    # Two-loop delta canceling interpreter loop overhead
    ::GC.disable
    begin
      100.times { tracer.start_span("warmup", attributes: FROZEN_ATTRS) }

      start_1 = ::GC.stat(:total_allocated_objects)
      1000.times { tracer.start_span("op", attributes: FROZEN_ATTRS) }
      delta_1 = ::GC.stat(:total_allocated_objects) - start_1

      start_2 = ::GC.stat(:total_allocated_objects)
      2000.times { tracer.start_span("op", attributes: FROZEN_ATTRS) }
      delta_2 = ::GC.stat(:total_allocated_objects) - start_2

      # Per-iteration allocation rate is (delta_2 - delta_1) / 1000
      per_call_allocations = (delta_2 - delta_1) / 1000.0
      assert_equal(0.0, per_call_allocations)
    ensure
      ::GC.enable
    end
  end

  test "OBS-30, CTX-20: NO_TRACER_FACTORY is concurrently safe across 16 threads" do
    factory = Dexpace::Instrumentation::NO_TRACER_FACTORY
    results = Array.new(16)
    threads = Array.new(16) do |i|
      Thread.new { results[i] = factory.tracer("op_name") }
    end
    threads.each(&:join)

    assert_equal(1, results.uniq.size)
    assert_same(Dexpace::Instrumentation::NO_TRACER, results.first)
  end

  test "OBS-29, P5-43: RecordingTracerFactory returns a fresh tracer per operation" do
    factory = Dexpace::RecordingTracerFactory.new
    t1 = factory.tracer("op1")
    t2 = factory.tracer("op2")

    refute_same(t1, t2)
    assert_equal(2, factory.tracers.size)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/no_tracer_test.rb`
Expected: fails with `NoMethodError: undefined method 'start_span'`.

- [ ] **Step 3: Modify `gems/dexpace-core/lib/dexpace/instrumentation/no_tracer.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "no_span"

module Dexpace
  module Instrumentation
    # CTX-20, OBS-25: no-op tracer returning shared NO_SPAN singleton. Every attributes
    # parameter is a named optional keyword and never a ** splat (P5-42, OI-28).
    class NoTracer
      # rubocop:disable Lint/UnusedMethodArgument -- the arguments are the documented protocol
      # and are ignored by construction; OBS-25 requires the shared singleton back regardless.
      # Metrics/ParameterLists counts keywords (OI-20): #start_span's four is at Max: 4 and
      # needs no directive today, so none is written.
      def start_span(name, attributes: nil, kind: nil, with_parent: nil)
        NO_SPAN
      end

      def in_span(name, attributes: nil, kind: nil)
        if block_given?
          yield NO_SPAN
        else
          NO_SPAN
        end
      end
      # rubocop:enable Lint/UnusedMethodArgument
    end
    private_constant :NoTracer

    NO_TRACER = NoTracer.new.freeze

    # CTX-20, OBS-25: no-op tracer factory returning shared NO_TRACER singleton.
    #
    # #tracer's five-argument shape is 4a's and is NOT re-opened here (P4-8, boundary 10): it
    # mirrors OpenTelemetry::Trace::TracerProvider#tracer so an application can pass
    # OpenTelemetry.tracer_provider straight into Bundle.build(tracer_factory:). SEAM-28's stable
    # operation identifier is what a caller passes as `name`, which is DEF-1's second half.
    class NoTracerFactory
      # rubocop:disable Lint/UnusedMethodArgument, Metrics/ParameterLists -- 4a's directive,
      # carried forward verbatim: every argument is part of the mirrored signature and is
      # deliberately unused, and the count is the gem's, not this repository's.
      def tracer(deprecated_name = nil, deprecated_version = nil, name: nil, version: nil,
                 attributes: nil)
        NO_TRACER
      end
      # rubocop:enable Lint/UnusedMethodArgument, Metrics/ParameterLists
    end
    private_constant :NoTracerFactory

    NO_TRACER_FACTORY = NoTracerFactory.new.freeze
  end
end
```

- [ ] **Step 4: Modify `sig/dexpace/instrumentation/no_tracer.rbs`**

```rbs
module Dexpace
  module Instrumentation
    interface _Tracer
      def start_span: (String name, ?attributes: ::Hash[String, untyped]?, ?kind: ::Symbol?, ?with_parent: untyped?) -> _Span
      def in_span: [T] (String name, ?attributes: ::Hash[String, untyped]?, ?kind: ::Symbol?) { (_Span) -> T } -> T
    end

    interface _TracerFactory
      def tracer: (?String? deprecated_name, ?String? deprecated_version, ?name: String?,
                   ?version: String?, ?attributes: ::Hash[String, untyped]?) -> _Tracer
    end

    NO_TRACER: _Tracer
    NO_TRACER_FACTORY: _TracerFactory
  end
end
```

**`_TracerFactory` is reproduced from 4a unchanged, five parameters and all.** The design printed
it as `def tracer: (?String? name, ?String? version) -> _Tracer` while calling it "unchanged from
4a"; 4a's shipped declaration is the five-argument mirror of
`OpenTelemetry::Trace::TracerProvider#tracer` (`P4-8`). 4a's is the one on disk and boundary 10
forbids redefining it, and narrowing a released interface is an `NFR-4` break — so 4a's is what
ships. **The reconciliation pass corrected the design's printing to match**, so the two documents
now agree and this paragraph records a closed divergence rather than an open one. `_Tracer`'s
`?with_parent:` and `?kind:` on `#in_span` were the same kind of stale printing and were corrected
in the same pass.

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/no_tracer_test.rb`
Expected: PASS with 5 runs, 0 failures, 0 errors.

---

## Task 5: `Dexpace::Instrumentation::Scope` and `NO_SCOPE`

**Requirement IDs:** `OBS-22` (scope handle restoring previously-active span), `OBS-25` (cached singleton scope), `DEF-37` (part).
**Design:** "The object model 5c ships — `Scope` and `NO_SCOPE`"; `P5-46` (3-ivar class, not Data); `P5-47` (identity split).

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/scope.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/scope.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/scope_test.rb`

**Interfaces:**
- Consumes: `Diagnostics::TRACE_ID`, `Diagnostics::SPAN_ID` (5b).
- Produces: `Dexpace::Instrumentation::Scope`, `Dexpace::Instrumentation::NO_SCOPE`, `_Scope` RBS interface.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_span"
require "dexpace"

# OBS-22, OBS-25, P5-46, P5-49: Scope handle, NO_SCOPE cached singleton, and the branchless
# per-key diagnostic restore. The key names are 5b's constants and are never spelled twice.
class DexpaceInstrumentationScopeTest < DexpaceTestCase
  TRACE_ID = Dexpace::Instrumentation::Diagnostics::TRACE_ID
  SPAN_ID = Dexpace::Instrumentation::Diagnostics::SPAN_ID
  CURRENT_SPAN = :"dexpace.current_span"

  # testing/4ef070df: every test runs alone, in any order. A test that leaves a current span or a
  # trace.id set poisons every later test in the same fiber -- order-dependent, and therefore a
  # failure that does not reproduce.
  def teardown
    ::Fiber[CURRENT_SPAN] = nil
    ::Fiber[TRACE_ID] = nil
    ::Fiber[SPAN_ID] = nil
    super
  end

  test "OBS-25: NO_SCOPE is a frozen singleton whose #close is nil" do
    scope = Dexpace::Instrumentation::NO_SCOPE
    assert_predicate(scope, :frozen?)
    assert_nil(scope.close)
  end

  test "OBS-22, P5-46: Scope is a plain 3-ivar class restoring state on #close" do
    span1 = Dexpace::RecordingSpan.new
    span2 = Dexpace::RecordingSpan.new

    ::Fiber[CURRENT_SPAN] = span2
    ::Fiber[TRACE_ID] = "t2"
    ::Fiber[SPAN_ID] = "s2"

    scope = Dexpace::Instrumentation::Scope.build(span1, "t1", "s1")
    assert_equal(3, scope.instance_variables.size)

    scope.close
    assert_same(span1, ::Fiber[CURRENT_SPAN])
    assert_equal("t1", ::Fiber[TRACE_ID])
    assert_equal("s1", ::Fiber[SPAN_ID])

    # OBS-21's neighbouring idempotence clause is what a reader expects here: a second close
    # restores the same three values to the same three slots. Scope is deliberately NOT a
    # Dexpace::Closeable -- XCUT-13's latch is about owned resources and a scope owns nothing.
    scope.close
    assert_same(span1, ::Fiber[CURRENT_SPAN])
    assert_equal("t1", ::Fiber[TRACE_ID])
    assert_equal("s1", ::Fiber[SPAN_ID])
  end

  test "OBS-22, P5-49: a nil prior value deletes the key rather than storing nil" do
    span1 = Dexpace::RecordingSpan.new
    ::Fiber[TRACE_ID] = "t-present"
    ::Fiber[SPAN_ID] = "s-present"

    scope = Dexpace::Instrumentation::Scope.build(span1, nil, nil)
    scope.close

    # Fiber[k] returns nil for both "absent" and "present with a nil value", so the assertion has
    # to be #key? -- assert_nil would pass under an implementation that stored nil (fact 4).
    refute(::Fiber.current.storage.key?(TRACE_ID))
    refute(::Fiber.current.storage.key?(SPAN_ID))
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/scope_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::Instrumentation::NO_SCOPE`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/instrumentation/scope.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "diagnostics"

module Dexpace
  module Instrumentation
    # The current-span slot key, declared once and shared by Scope and Tracing. It is NOT a
    # diagnostic-context key and must never be folded (OBS-10's default allow-list is exactly
    # {trace.id, span.id}), so it is a private_constant and is namespaced so it cannot collide
    # with an application's own. Bare references resolve from both lexical scopes below;
    # a qualified reference to a private_constant raises (execution-context/b58728da).
    CURRENT_SPAN_KEY = :"dexpace.current_span"
    private_constant :CURRENT_SPAN_KEY

    # OBS-25: Cached singleton scope returned when no restoration is required.
    class NoScope
      def close
        nil
      end
    end
    private_constant :NoScope

    NO_SCOPE = NoScope.new.freeze

    # OBS-22: Plain 3-ivar class holding previous slot values on the Ruby stack.
    # Deliberately not a Data.define (P5-46): a per-call resource handle, not a value.
    #
    # No stack lives in fiber storage (R13, verified fact 2): Fiber[]'s copy-on-write protects
    # the slot, not the object in it, so a span stack there would be one shared mutable Array
    # across every descendant thread and fiber -- XCUT-11 with no synchronisation.
    class Scope
      UNSET = ::Object.new.freeze
      private_constant :UNSET

      private_class_method :new

      # @api private -- the internal constructor. Tracing.activate and .correlate are the only
      # callers; it is not part of P5-41's public reading of Scope, whose public surface is
      # #close alone. It cannot be private_class_method because Tracing is a sibling module.
      def self.build(prev_span, prev_trace_id = UNSET, prev_span_id = UNSET)
        new(prev_span, prev_trace_id, prev_span_id)
      end

      def initialize(prev_span, prev_trace_id, prev_span_id)
        @prev_span = prev_span
        @prev_trace_id = prev_trace_id
        @prev_span_id = prev_span_id
      end

      # OBS-22 and OBS-23's restores, in one place. Idempotent by construction: a second call
      # writes the same three values into the same three slots. Fiber[:k] = nil deletes the key
      # (verified fact 4), so "restore to its prior value (or remove it if previously unset)" is
      # one assignment with no branch on presence -- at the cost P5-49 records.
      def close
        ::Fiber[CURRENT_SPAN_KEY] = @prev_span
        ::Fiber[Diagnostics::TRACE_ID] = @prev_trace_id unless @prev_trace_id.equal?(UNSET)
        ::Fiber[Diagnostics::SPAN_ID] = @prev_span_id unless @prev_span_id.equal?(UNSET)
        nil
      end
    end
  end
end
```

`scope.rb` is the second and last file 5c requires from `5b` — `diagnostics.rb`, which requires
nothing else in `5b` and defines no `Event`, so it drags nothing and does not break Task 11's
load-time assertion. The design names `tracing.rb` as the requirer; `Scope#close` owns the two
diagnostic restores, so it needs the pair too and states the require rather than inheriting it.

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/instrumentation/scope.rbs`**

```rbs
module Dexpace
  module Instrumentation
    interface _Scope
      def close: () -> void
    end

    class Scope
      @prev_span: _Span
      @prev_trace_id: untyped
      @prev_span_id: untyped

      def self.build: (_Span prev_span, ?untyped prev_trace_id, ?untyped prev_span_id) -> Scope
      def close: () -> void
    end

    NO_SCOPE: _Scope
  end
end
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/scope_test.rb`
Expected: PASS with 3 runs, 0 failures, 0 errors.

---

## Task 6: `Dexpace::Instrumentation::Tracing`

**Requirement IDs:** `OBS-22` (nesting, restoration, exception safety), `OBS-23` (log correlation, delegation, removal of unset keys), `OBS-25` (zero-allocation default), `OBS-30` (non-wrapping exception propagation).
**Design:** "The object model 5c ships — `Tracing`"; `R12` (per-key fiber storage); `R13` (identity test); `P5-45` (block-form first); `P5-49` (null value deletion).

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/tracing.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/tracing.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/tracing_test.rb`

**Interfaces:**
- Consumes: `NO_SPAN`, `NO_SCOPE`, `Scope`, `Bundle`, `Diagnostics::TRACE_ID`, `Diagnostics::SPAN_ID`.
- Produces: `Dexpace::Instrumentation::Tracing` (`.current_span`, `.activate`, `.with_span`, `.correlate`, `.with_correlated_span`).

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_span"
require "dexpace"

# OBS-22, OBS-23, OBS-25, OBS-30: Tracing current span, activation, and correlation.
class DexpaceInstrumentationTracingTest < DexpaceTestCase
  TRACE_ID = Dexpace::Instrumentation::Diagnostics::TRACE_ID
  SPAN_ID = Dexpace::Instrumentation::Diagnostics::SPAN_ID

  # testing/4ef070df: restore both diagnostic slots and the current-span slot unconditionally,
  # including on failure, or a later test in the same fiber inherits them.
  def teardown
    ::Fiber[:"dexpace.current_span"] = nil
    ::Fiber[TRACE_ID] = nil
    ::Fiber[SPAN_ID] = nil
    super
  end

  test "OBS-22: Tracing.current_span defaults to NO_SPAN" do
    assert_same(Dexpace::Instrumentation::NO_SPAN, Dexpace::Instrumentation::Tracing.current_span)
  end

  test "OBS-22: nested activations with distinct spans restore outer and then initial" do
    outer = Dexpace::RecordingSpan.new
    inner = Dexpace::RecordingSpan.new

    assert_same(Dexpace::Instrumentation::NO_SPAN, Dexpace::Instrumentation::Tracing.current_span)

    Dexpace::Instrumentation::Tracing.with_span(outer) do |s_outer|
      assert_same(outer, s_outer)
      assert_same(outer, Dexpace::Instrumentation::Tracing.current_span)

      Dexpace::Instrumentation::Tracing.with_span(inner) do |s_inner|
        assert_same(inner, s_inner)
        assert_same(inner, Dexpace::Instrumentation::Tracing.current_span)
      end

      assert_same(outer, Dexpace::Instrumentation::Tracing.current_span)
    end

    assert_same(Dexpace::Instrumentation::NO_SPAN, Dexpace::Instrumentation::Tracing.current_span)
  end

  test "OBS-22, OBS-30: exception inside with_span propagates and restores prior span" do
    outer = Dexpace::RecordingSpan.new
    inner = Dexpace::RecordingSpan.new

    Dexpace::Instrumentation::Tracing.with_span(outer) do
      assert_raises(RuntimeError) do
        Dexpace::Instrumentation::Tracing.with_span(inner) do
          raise "boom"
        end
      end
      assert_same(outer, Dexpace::Instrumentation::Tracing.current_span)
    end
  end

  test "OBS-23: correlate pushes trace.id and span.id and deletes previously unset keys on close" do
    span = Dexpace::RecordingSpan.new
    bundle = Dexpace::Instrumentation::Bundle.build(
      trace_id: "4bf92f3577b34da6a3ce929d0e0e4736",
      span_id: "00f067aa0ba902b7",
      trace_flags: "01",
      trace_state: [],
      flavour: Dexpace::Instrumentation::TraceIdFlavour::W3C,
      remote: false,
    )

    refute(::Fiber.current.storage.key?(TRACE_ID))
    refute(::Fiber.current.storage.key?(SPAN_ID))

    Dexpace::Instrumentation::Tracing.with_correlated_span(span, bundle) do
      assert_equal("4bf92f3577b34da6a3ce929d0e0e4736",
                   ::Fiber[TRACE_ID])
      assert_equal("00f067aa0ba902b7",
                   ::Fiber[SPAN_ID])
    end

    # OBS-23: must distinguish unset from nil and remove key
    refute(::Fiber.current.storage.key?(TRACE_ID))
    refute(::Fiber.current.storage.key?(SPAN_ID))
  end

  test "OBS-23: non-recording span delegates to plain activation and skips correlation push" do
    # A non-recording RecordingSpan, NOT NO_SPAN: with NO_SPAN the slot already holds it, the
    # identity test returns NO_SCOPE, and the test passes against an implementation that does
    # nothing at all. The "delegates to plain current-span activation" half is the assertion.
    quiet = Dexpace::RecordingSpan.new(recording: false)
    bundle = Dexpace::Instrumentation::Bundle.build(
      trace_id: "4bf92f3577b34da6a3ce929d0e0e4736",
      span_id: "00f067aa0ba902b7",
      flavour: Dexpace::Instrumentation::TraceIdFlavour::W3C,
    )

    Dexpace::Instrumentation::Tracing.with_correlated_span(quiet, bundle) do
      assert_same(quiet, Dexpace::Instrumentation::Tracing.current_span)
      refute(::Fiber.current.storage.key?(TRACE_ID))
      refute(::Fiber.current.storage.key?(SPAN_ID))
    end

    assert_same(Dexpace::Instrumentation::NO_SPAN,
                Dexpace::Instrumentation::Tracing.current_span)
  end

  test "OBS-25, P5-47: activating currently active span returns NO_SCOPE by identity" do
    span = Dexpace::RecordingSpan.new
    Dexpace::Instrumentation::Tracing.with_span(span) do
      scope = Dexpace::Instrumentation::Tracing.activate(span)
      assert_same(Dexpace::Instrumentation::NO_SCOPE, scope)
    end
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/tracing_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::Instrumentation::Tracing`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/instrumentation/tracing.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "no_span"
require_relative "scope"
require_relative "diagnostics"

module Dexpace
  module Instrumentation
    # OBS-22, OBS-23: Span activation, log correlation, and diagnostic context push/restore.
    #
    # One Fiber[] slot holds the current span, CURRENT_SPAN_KEY names it, and scope.rb declares
    # it -- one spelling of one key, because Scope#close writes the same slot. Nothing here
    # rescues: OBS-20 and OBS-30 make a throwing tracer the caller's, and the ensure below
    # restores regardless (boundary 2).
    module Tracing
      module_function

      def current_span
        ::Fiber[CURRENT_SPAN_KEY] || NO_SPAN
      end

      def activate(span)
        current = current_span
        return NO_SCOPE if span.equal?(current)

        ::Fiber[CURRENT_SPAN_KEY] = span
        Scope.build(current)
      end

      def with_span(span)
        scope = activate(span)
        begin
          yield span
        ensure
          scope.close
        end
      end

      def correlate(span, bundle)
        return activate(span) unless span.recording?

        current = current_span
        prev_trace = ::Fiber[Diagnostics::TRACE_ID]
        prev_span = ::Fiber[Diagnostics::SPAN_ID]
        trace_id = bundle.trace_id
        span_id = bundle.span_id

        if span.equal?(current) && prev_trace == trace_id && prev_span == span_id
          return NO_SCOPE
        end

        ::Fiber[CURRENT_SPAN_KEY] = span
        ::Fiber[Diagnostics::TRACE_ID] = trace_id
        ::Fiber[Diagnostics::SPAN_ID] = span_id
        Scope.build(current, prev_trace, prev_span)
      end

      def with_correlated_span(span, bundle)
        scope = correlate(span, bundle)
        begin
          yield span
        ensure
          scope.close
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/instrumentation/tracing.rbs`**

```rbs
module Dexpace
  module Instrumentation
    module Tracing
      def self.current_span: () -> _Span
      def self.activate: (_Span span) -> _Scope
      def self.with_span: [T] (_Span span) { (_Span) -> T } -> T
      def self.correlate: (_Span span, Bundle bundle) -> _Scope
      def self.with_correlated_span: [T] (_Span span, Bundle bundle) { (_Span) -> T } -> T
    end
  end
end
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/tracing_test.rb`
Expected: PASS with 6 runs, 0 failures, 0 errors.

---

## Task 7: `Dexpace::Instrumentation::NO_METER` and the Metrics SPI

**Requirement IDs:** `OBS-31` (Meter manufacturing counter and histogram singletons, zero dependencies), `OBS-33` (non-negative counter documentation, non-finite histogram inputs tolerated), `OBS-30` (concurrency safety), `OBS-32` (deferred, post-v1 `DEF-9`).
**Design:** "The object model 5c ships — `Dexpace::Instrumentation::NO_METER`"; `P5-40` (constants); `P5-42` (named keywords); `P5-48` (fakes for recording).

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/meter.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/meter.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/meter_test.rb`

**Interfaces:**
- Consumes: Ruby numeric types.
- Produces: `Dexpace::Instrumentation::NO_METER`, `_Meter`, `_Counter`, `_Histogram` RBS interfaces.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_meter"
require "dexpace"

# OBS-31, OBS-33, OBS-30: NO_METER singletons, non-finite toleration, and concurrency.
class DexpaceInstrumentationMeterTest < DexpaceTestCase
  FROZEN_ATTRS = { "http.request.method" => "GET" }.freeze

  test "OBS-31: NO_METER returns shared counter and histogram singletons under different names" do
    meter = Dexpace::Instrumentation::NO_METER
    c1 = meter.create_counter("requests_total")
    c2 = meter.create_counter("bytes_total")
    assert_same(c1, c2)

    h1 = meter.create_histogram("duration_ms")
    h2 = meter.create_histogram("size_bytes")
    assert_same(h1, h2)
  end

  test "OBS-33: Counter#add returns nil for non-negative values" do
    counter = Dexpace::Instrumentation::NO_METER.create_counter("test")
    assert_nil(counter.add(1))
    assert_nil(counter.add(10, attributes: FROZEN_ATTRS))
  end

  test "OBS-33: Histogram#record tolerates NaN, Infinity, -Infinity, 0, and negative numbers" do
    histogram = Dexpace::Instrumentation::NO_METER.create_histogram("test")

    # OBS-33 and testing/26b866e1: assert_nil on return value, not assert_nothing_raised
    assert_nil(histogram.record(Float::NAN))
    assert_nil(histogram.record(Float::INFINITY))
    assert_nil(histogram.record(-Float::INFINITY))
    assert_nil(histogram.record(0))
    assert_nil(histogram.record(-1))
    assert_nil(histogram.record(42.5, attributes: FROZEN_ATTRS))
  end

  test "OBS-30: NO_METER methods are safe to call concurrently across 16 threads" do
    meter = Dexpace::Instrumentation::NO_METER
    counter_results = Array.new(16)
    histogram_results = Array.new(16)

    threads = Array.new(16) do |i|
      Thread.new do
        counter_results[i] = meter.create_counter("c_#{i}")
        histogram_results[i] = meter.create_histogram("h_#{i}")
      end
    end
    threads.each(&:join)

    assert_equal(1, counter_results.uniq.size)
    assert_equal(1, histogram_results.uniq.size)
  end

  test "RecordingMeter fake records measurements" do
    meter = Dexpace::RecordingMeter.new
    c = meter.create_counter("count", unit: "{request}")
    h = meter.create_histogram("duration", unit: "ms")

    c.add(1, attributes: FROZEN_ATTRS)
    h.record(12.3, attributes: FROZEN_ATTRS)

    assert_equal(1, c.records.size)
    assert_equal(1, c.records.first[:amount])
    assert_equal(1, h.records.size)
    assert_in_delta(12.3, h.records.first[:amount])
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/meter_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::Instrumentation::NO_METER`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/instrumentation/meter.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # OBS-31, OBS-33: Shared no-op counter singleton.
    class NoCounter
      # OBS-33's MUST-document half, stated where a duck-typed SPI can bind it: only
      # non-negative increments are valid. A negative delta is undefined behaviour and is the
      # caller's responsibility, and the core instrument MUST NOT validate it on the hot path --
      # so there is no check here, deliberately. The same sentence is the YARD block on
      # _Counter#add.
      # rubocop:disable Lint/UnusedMethodArgument -- the measurement is discarded by design.
      def add(amount, attributes: nil)
        nil
      end
      # rubocop:enable Lint/UnusedMethodArgument
    end
    private_constant :NoCounter

    NO_COUNTER = NoCounter.new.freeze
    private_constant :NO_COUNTER

    # OBS-31, OBS-33: Shared no-op histogram singleton.
    class NoHistogram
      # Tolerates any numeric input including NaN and Infinity without throwing (OBS-33):
      # there is nothing to throw from, because the measurement is discarded.
      # rubocop:disable Lint/UnusedMethodArgument -- the measurement is discarded by design.
      def record(amount, attributes: nil)
        nil
      end
      # rubocop:enable Lint/UnusedMethodArgument
    end
    private_constant :NoHistogram

    NO_HISTOGRAM = NoHistogram.new.freeze
    private_constant :NO_HISTOGRAM

    # OBS-31: No-op Meter manufacturing shared counter and histogram singletons. "Shared" is a
    # reference-identity claim and is asserted meter-to-meter under two different names, which is
    # why the two instruments stay private_constant (api-design/b0e18938).
    class NoMeter
      # rubocop:disable Lint/UnusedMethodArgument -- name, unit and description are the
      # documented protocol; a discarding meter has nothing to do with them.
      def create_counter(name, unit: nil, description: nil)
        NO_COUNTER
      end

      def create_histogram(name, unit: nil, description: nil)
        NO_HISTOGRAM
      end
      # rubocop:enable Lint/UnusedMethodArgument
    end
    private_constant :NoMeter

    NO_METER = NoMeter.new.freeze
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/instrumentation/meter.rbs`**

```rbs
module Dexpace
  module Instrumentation
    interface _Counter
      # OBS-33: only non-negative increments are valid. A negative delta is undefined behaviour
      # and is the caller's responsibility; the core instrument MUST NOT validate it on the hot
      # path, and does not. This sentence is where OBS-33's MUST-document clause binds -- a
      # duck-typed SPI has no other place for it.
      def add: (Integer amount, ?attributes: ::Hash[String, untyped]?) -> void
    end

    interface _Histogram
      # OBS-33: tolerates any input without throwing; the no-op discards it. Handling of
      # non-finite values (NaN, +/-Infinity) is delegated to concrete adapters.
      def record: (Numeric amount, ?attributes: ::Hash[String, untyped]?) -> void
    end

    interface _Meter
      def create_counter: (String name, ?unit: String?, ?description: String?) -> _Counter
      def create_histogram: (String name, ?unit: String?, ?description: String?) -> _Histogram
    end

    NO_METER: _Meter
  end
end
```

`interface _Meter`, `_Counter` and `_Histogram` are declared **here and only here**. `5b`'s draft
carried an empty `_Meter`, borrowing 4a's device of stating a deferral in the type system; that
device is right when the populating phase is a different one held open by a register row, and
wrong here, where the populating segment is in the same phase. **Two declarations of one interface
name is an `rbs validate` failure, not a merge conflict** — 5b's empty declaration is deleted and
its `meter:` types against `Dexpace::Instrumentation::_Meter` — written as a bare `_Meter` in
`step.rbs`, which sits inside `module Instrumentation` too. `untyped` appears once, as an attribute *value*:
`OBS-31` says "key/value attributes" and fixes nothing about the value type.

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/meter_test.rb`
Expected: PASS with 5 runs, 0 failures, 0 errors.

---

## Task 8: `Dexpace::Instrumentation::HTTPTracer` and `NULL`

**Requirement IDs:** `OBS-28` (11-method HTTP tracer vocabulary with no-op defaults), `OBS-29` (lifecycle contract), `OBS-30` (concurrent safety).
**Design:** "The object model 5c ships — `HTTPTracer` and `NULL`"; `P5-40` (constants); `R14` (contract ships, wiring deferred).

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/http_tracer.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/http_tracer.rbs`
- Create: `gems/dexpace-core/test/support/recording_http_tracer.rb`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/http_tracer_test.rb`

**Interfaces:**
- Consumes: nothing. Every argument is `untyped` in `sig/` and the module touches no context, no
  request and no response — the vocabulary is fixed by `OBS-28`, and its emitters are phases 6
  and 8's (`DEF-42`).
- Produces: `Dexpace::Instrumentation::HTTPTracer`, `Dexpace::Instrumentation::NULL`,
  `Dexpace::RecordingHTTPTracer`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# OBS-28, OBS-30: HTTPTracer vocabulary and NULL singleton.
class DexpaceInstrumentationHTTPTracerTest < DexpaceTestCase
  test "OBS-28: NULL singleton includes HTTPTracer and defaults all 11 methods to nil" do
    tracer = Dexpace::Instrumentation::NULL

    assert_predicate(tracer, :frozen?)
    assert_kind_of(Dexpace::Instrumentation::HTTPTracer, tracer)

    # Operation lifecycle group
    assert_nil(tracer.operation_started(:ctx))
    assert_nil(tracer.operation_succeeded(:ctx, :response))
    assert_nil(tracer.operation_failed(:ctx, StandardError.new))

    # Per-attempt group
    assert_nil(tracer.attempt_started(:ctx, 1))
    assert_nil(tracer.attempt_failed(:ctx, StandardError.new, 1.5))
    assert_nil(tracer.retries_exhausted(:ctx, StandardError.new))

    # Transport milestones group
    assert_nil(tracer.request_url_resolved(:ctx, "https://example.com"))
    assert_nil(tracer.connection_acquired(:ctx, "example.com", 443))
    assert_nil(tracer.request_sent(:ctx, 1024))
    assert_nil(tracer.response_headers_received(:ctx, 200, {}))
    assert_nil(tracer.response_received(:ctx, 2048))
  end

  test "OBS-28: implementer includes HTTPTracer and overrides only required callbacks" do
    custom_tracer_class = Class.new do
      include Dexpace::Instrumentation::HTTPTracer
      attr_reader :started

      def operation_started(context)
        @started = context
      end
    end

    tracer = custom_tracer_class.new
    tracer.operation_started(:my_ctx)
    assert_equal(:my_ctx, tracer.started)
    assert_nil(tracer.operation_succeeded(:my_ctx, :resp))
  end

  test "OBS-30: NULL is thread-safe and shared across 16 threads" do
    results = Array.new(16)
    threads = Array.new(16) do |i|
      Thread.new { results[i] = Dexpace::Instrumentation::NULL }
    end
    threads.each(&:join)

    assert_equal(1, results.uniq.size)
    assert_same(Dexpace::Instrumentation::NULL, results.first)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/http_tracer_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::Instrumentation::HTTPTracer`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/instrumentation/http_tracer.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # OBS-28: HTTP-shaped tracer event vocabulary with no-op defaults. A module, not a base
    # class: Ruby has single inheritance and an implementer may already have a superclass, and a
    # bare duck type gives no defaults -- which under OBS-30's no-wrapping rule would make a
    # missing method a NoMethodError in the caller's request path.
    #
    # OBS-29's ordering contract binds an implementer, not this module: operation_started fires
    # once, operation_succeeded and operation_failed are mutually exclusive and each fires once,
    # attempt events may repeat, and retries_exhausted is immediately followed by
    # operation_failed with the same throwable. Nothing in phase 5 emits any of it (DEF-42).
    module HTTPTracer
      # rubocop:disable Lint/UnusedMethodArgument -- OBS-28: "Every event method SHOULD default
      # to a no-op so adding a new event is a non-breaking change and implementers override only
      # what they need." The parameter names are the contract phases 6 and 8 emit against.
      # --- Operation Lifecycle Group ---
      def operation_started(context)
        nil
      end

      def operation_succeeded(context, response)
        nil
      end

      def operation_failed(context, error)
        nil
      end

      # --- Per-Attempt Group ---
      def attempt_started(context, attempt)
        nil
      end

      def attempt_failed(context, error, next_delay)
        nil
      end

      def retries_exhausted(context, error)
        nil
      end

      # --- Transport Milestones Group ---
      def request_url_resolved(context, url)
        nil
      end

      def connection_acquired(context, host, port)
        nil
      end

      def request_sent(context, byte_count)
        nil
      end

      def response_headers_received(context, status, headers)
        nil
      end

      def response_received(context, byte_count)
        nil
      end
      # rubocop:enable Lint/UnusedMethodArgument
    end

    # §8.1: Frozen no-op HTTP tracer singleton.
    class NullHTTPTracer
      include HTTPTracer
    end
    private_constant :NullHTTPTracer

    NULL = NullHTTPTracer.new.freeze
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/instrumentation/http_tracer.rbs`**

```rbs
module Dexpace
  module Instrumentation
    module HTTPTracer
      def operation_started: (untyped context) -> void
      def operation_succeeded: (untyped context, untyped response) -> void
      def operation_failed: (untyped context, untyped error) -> void

      def attempt_started: (untyped context, Integer attempt) -> void
      def attempt_failed: (untyped context, untyped error, Numeric next_delay) -> void
      def retries_exhausted: (untyped context, untyped error) -> void

      def request_url_resolved: (untyped context, untyped url) -> void
      def connection_acquired: (untyped context, String host, Integer port) -> void
      def request_sent: (untyped context, Integer byte_count) -> void
      def response_headers_received: (untyped context, Integer status, untyped headers) -> void
      def response_received: (untyped context, Integer byte_count) -> void
    end

    NULL: HTTPTracer
  end
end
```

No `interface _HTTPTracer` is declared, deliberately: eleven signatures with no core caller would
be eleven `NFR-4`-locked shapes nothing checks, and `HTTPTracer` is a **module an implementer
includes**, so its own declaration above is the contract `rbs validate` reads. If phase 6 wires
the vocabulary, the interface arrives with the wiring (design, *The RBS interfaces*).

- [ ] **Step 5: Write `gems/dexpace-core/test/support/recording_http_tracer.rb`**

`OBS-29`'s conformance clause asks for the ordering to be driven "through a **conformant
emitter**", and the design fixes the shape: a fake that **includes `HTTPTracer`** and overrides
all eleven. Including the module rather than re-declaring the methods is what gives the module a
caller in the suite (`R14`) and what makes a missing override a silent no-op rather than a
`NoMethodError` — which is the property `OBS-28`'s "implementers override only what they need"
is about. This is why the double lives here and not in Task 1: `HTTPTracer` does not exist until
Step 3 above.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../lib/dexpace/instrumentation/http_tracer"

module Dexpace
  # OBS-29's conformant emitter. Includes the vocabulary and overrides all eleven, appending one
  # tuple per callback so the ordering test can assert sequence, adjacency and identity (P5-48).
  class RecordingHTTPTracer
    include Instrumentation::HTTPTracer

    attr_reader :events

    def initialize
      @events = []
    end

    def operation_started(context)
      @events << [:operation_started, context].freeze
      nil
    end

    def operation_succeeded(context, response)
      @events << [:operation_succeeded, context, response].freeze
      nil
    end

    def operation_failed(context, error)
      @events << [:operation_failed, context, error].freeze
      nil
    end

    def attempt_started(context, attempt)
      @events << [:attempt_started, context, attempt].freeze
      nil
    end

    def attempt_failed(context, error, next_delay)
      @events << [:attempt_failed, context, error, next_delay].freeze
      nil
    end

    def retries_exhausted(context, error)
      @events << [:retries_exhausted, context, error].freeze
      nil
    end

    def request_url_resolved(context, url)
      @events << [:request_url_resolved, context, url].freeze
      nil
    end

    def connection_acquired(context, host, port)
      @events << [:connection_acquired, context, host, port].freeze
      nil
    end

    def request_sent(context, byte_count)
      @events << [:request_sent, context, byte_count].freeze
      nil
    end

    def response_headers_received(context, status, headers)
      @events << [:response_headers_received, context, status, headers].freeze
      nil
    end

    def response_received(context, byte_count)
      @events << [:response_received, context, byte_count].freeze
      nil
    end
  end
end
```

- [ ] **Step 6: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/http_tracer_test.rb`
Expected: PASS with 3 runs, 0 failures, 0 errors.

---

## Task 9: `Dexpace::Instrumentation::CallableAdapter`

**Requirement IDs:** `OBS-28`, §8.1.
**Design:** "The object model 5c ships — `CallableAdapter`"; `P5-40` (constants).

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/instrumentation/callable_adapter.rb`
- Create: `gems/dexpace-core/sig/dexpace/instrumentation/callable_adapter.rbs`
- Test: `gems/dexpace-core/test/dexpace/instrumentation/callable_adapter_test.rb`

**Interfaces:**
- Consumes: `HTTPTracer` (Task 8).
- Produces: `Dexpace::Instrumentation::CallableAdapter`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# §8.1, OBS-28: CallableAdapter forwarding HTTPTracer events to #call(name, payload).
class DexpaceInstrumentationCallableAdapterTest < DexpaceTestCase
  test "CallableAdapter forwards all 11 event callbacks to callable with expected payload" do
    received = []
    bus = ->(name, payload) { received << [name, payload] }
    adapter = Dexpace::Instrumentation::CallableAdapter.new(bus)

    adapter.operation_started(:ctx)
    adapter.operation_succeeded(:ctx, :resp)
    adapter.operation_failed(:ctx, :err)

    adapter.attempt_started(:ctx, 1)
    adapter.attempt_failed(:ctx, :err, 0.5)
    adapter.retries_exhausted(:ctx, :err)

    adapter.request_url_resolved(:ctx, "https://api.example.com")
    adapter.connection_acquired(:ctx, "api.example.com", 443)
    adapter.request_sent(:ctx, 128)
    adapter.response_headers_received(:ctx, 200, { "content-type" => "application/json" })
    adapter.response_received(:ctx, 512)

    assert_equal(11, received.size)
    assert_equal([:operation_started, { context: :ctx }], received[0])
    assert_equal([:operation_succeeded, { context: :ctx, response: :resp }], received[1])
    assert_equal([:operation_failed, { context: :ctx, error: :err }], received[2])
    assert_equal([:attempt_started, { context: :ctx, attempt: 1 }], received[3])
    assert_equal([:attempt_failed, { context: :ctx, error: :err, next_delay: 0.5 }], received[4])
    assert_equal([:retries_exhausted, { context: :ctx, error: :err }], received[5])
    assert_equal([:request_url_resolved, { context: :ctx, url: "https://api.example.com" }],
                 received[6])
    assert_equal([:connection_acquired, { context: :ctx, host: "api.example.com", port: 443 }],
                 received[7])
    assert_equal([:request_sent, { context: :ctx, byte_count: 128 }], received[8])
    assert_equal(
      [:response_headers_received,
       { context: :ctx, status: 200, headers: { "content-type" => "application/json" } },],
      received[9],
    )
    assert_equal([:response_received, { context: :ctx, byte_count: 512 }], received[10])
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/callable_adapter_test.rb`
Expected: fails with `NameError: uninitialized constant Dexpace::Instrumentation::CallableAdapter`.

- [ ] **Step 3: Write `gems/dexpace-core/lib/dexpace/instrumentation/callable_adapter.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "http_tracer"

module Dexpace
  module Instrumentation
    # §8.1: Bus adapter forwarding HTTPTracer methods to an object responding to #call(name, payload).
    class CallableAdapter
      include HTTPTracer

      def initialize(callable)
        @callable = callable
      end

      def operation_started(context)
        @callable.call(:operation_started, { context: context })
      end

      def operation_succeeded(context, response)
        @callable.call(:operation_succeeded, { context: context, response: response })
      end

      def operation_failed(context, error)
        @callable.call(:operation_failed, { context: context, error: error })
      end

      def attempt_started(context, attempt)
        @callable.call(:attempt_started, { context: context, attempt: attempt })
      end

      def attempt_failed(context, error, next_delay)
        @callable.call(:attempt_failed, { context: context, error: error, next_delay: next_delay })
      end

      def retries_exhausted(context, error)
        @callable.call(:retries_exhausted, { context: context, error: error })
      end

      def request_url_resolved(context, url)
        @callable.call(:request_url_resolved, { context: context, url: url })
      end

      def connection_acquired(context, host, port)
        @callable.call(:connection_acquired, { context: context, host: host, port: port })
      end

      def request_sent(context, byte_count)
        @callable.call(:request_sent, { context: context, byte_count: byte_count })
      end

      def response_headers_received(context, status, headers)
        @callable.call(:response_headers_received,
                       { context: context, status: status, headers: headers })
      end

      def response_received(context, byte_count)
        @callable.call(:response_received, { context: context, byte_count: byte_count })
      end
    end
  end
end
```

- [ ] **Step 4: Write `gems/dexpace-core/sig/dexpace/instrumentation/callable_adapter.rbs`**

```rbs
module Dexpace
  module Instrumentation
    class CallableAdapter
      include HTTPTracer

      @callable: untyped

      def initialize: (untyped callable) -> void
    end
  end
end
```

- [ ] **Step 5: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/callable_adapter_test.rb`
Expected: PASS with 1 run, 0 failures, 0 errors.

---

## Task 10: Lifecycle Ordering Contract Verification

**Requirement IDs:** `OBS-29` (lifecycle ordering, exhausted→failed adjacency, same throwable), `DEF-42`.
**Design:** "R14 — whether `OBS-29`'s lifecycle wiring ships here"; "Testing strategy — `RecordingHTTPTracer`".

**Files:**
- Test: `gems/dexpace-core/test/dexpace/instrumentation/ordering_test.rb`

**Interfaces:**
- Consumes: `RecordingHTTPTracer` and `HTTPTracer` (both Task 8).
- Produces: automated conformance verification for `OBS-29`'s emission contract.

**Nothing in phase 5 emits any of this** (`R14`, `DEF-42`). The two tests below drive a conformant
emitter by hand, which is what `OBS-29`'s own conformance clause asks for and what its own last
sentence licenses: "pipeline/transport wiring to emit it is a follow-up, so it is not yet
runtime-enforced." The per-attempt group has no emitter until phase 6's retry step and the
transport milestones none until phase 8; wiring only the operation triple was considered and
rejected on both sides of the 5b/5c boundary.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_http_tracer"
require "dexpace"

# OBS-29: HTTP-tracer lifecycle ordering and exhausted->failed pairing.
class DexpaceInstrumentationOrderingTest < DexpaceTestCase
  test "OBS-29: succeeding operation emits started once and succeeded once" do
    tracer = Dexpace::RecordingHTTPTracer.new
    ctx = :req_context
    resp = :response_payload

    # Simulate conformant runner emission
    tracer.operation_started(ctx)
    tracer.attempt_started(ctx, 1)
    tracer.request_url_resolved(ctx, "https://example.com")
    tracer.connection_acquired(ctx, "example.com", 443)
    tracer.request_sent(ctx, 100)
    tracer.response_headers_received(ctx, 200, {})
    tracer.response_received(ctx, 500)
    tracer.operation_succeeded(ctx, resp)

    events = tracer.events.map(&:first)
    assert_equal(:operation_started, events.first)
    assert_equal(:operation_succeeded, events.last)
    assert_equal(1, events.count(:operation_started))
    assert_equal(1, events.count(:operation_succeeded))
    refute_includes(events, :operation_failed)
  end

  test "OBS-29: retry-exhausted operation pairs retries_exhausted immediately with operation_failed" do
    tracer = Dexpace::RecordingHTTPTracer.new
    ctx = :req_context
    err = StandardError.new("connection timeout")

    # Simulate conformant runner failure emission
    tracer.operation_started(ctx)
    tracer.attempt_started(ctx, 1)
    tracer.attempt_failed(ctx, err, 0.5)
    tracer.attempt_started(ctx, 2)
    tracer.attempt_failed(ctx, err, 1.0)
    tracer.retries_exhausted(ctx, err)
    tracer.operation_failed(ctx, err)

    events = tracer.events
    assert_equal(:operation_started, events.first.first)
    assert_equal(:operation_failed, events.last.first)

    # Adjacency assertion: retries_exhausted is immediately followed by operation_failed
    exhausted_idx = events.index { |e| e.first == :retries_exhausted }
    refute_nil(exhausted_idx)
    assert_equal(:operation_failed, events[exhausted_idx + 1].first)

    # Exact same throwable assertion
    assert_same(events[exhausted_idx][2], events[exhausted_idx + 1][2])
    assert_same(err, events[exhausted_idx + 1][2])

    # Mutual exclusivity of succeeded and failed
    refute_includes(events.map(&:first), :operation_succeeded)
  end
end
```

- [ ] **Step 2: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/ordering_test.rb`
Expected: PASS with 2 runs, 0 failures, 0 errors.

---

## Task 11: Structural Independence from the Logging Half

**Requirement IDs:** none of 5c's. **`OBS-34` is `5b`'s ID and this test does not discharge it** —
its conformance clause ("at none assert no request/response events but the span still starts/ends
and the counter/histogram still record") is discharged by `5b`'s step test at `HTTPLogging::NONE`.
What ships here is 5c's own regression against *acquiring* a dependency on the logging half, which
is what makes `5b`'s test writable (`R11`). Naming the two as two is deliberate: two documents each
describing a different mechanism as *the* mechanism is how a requirement ends up with no test.
**Design:** "OBS-34's independence of the log level, and the half 5c owes"; `R11`.

**Files:**
- Test: `gems/dexpace-core/test/dexpace/instrumentation/independence_test.rb`

**Interfaces:**
- Consumes: 5c source files and 5b's `diagnostics.rb`.
- Produces: load-time proof that 5c requires no logging classes and defines no `Event`.

- [ ] **Step 1: Write the test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# R11, OBS-20: 5c holds no sink, reads no log level and references no Event. OBS-34 is 5b's ID
# and is NOT discharged here.
class DexpaceInstrumentationIndependenceTest < DexpaceTestCase
  GEM_ROOT = File.expand_path("../../..", __dir__)

  test "R11: 5c files load and exercise tracing and metrics with Event undefined" do
    # A subprocess, because the in-process suite has already loaded the whole tree through
    # `require "dexpace"` and cannot un-define a constant. require, not require_relative:
    # require_relative from `ruby -e` has no stable basepath across the supported range.
    cmd = [
      "bundle", "exec", "ruby", "-w", "-e", <<~RUBY
        require "./lib/dexpace/instrumentation/diagnostics"
        require "./lib/dexpace/instrumentation/trace_id_flavour"
        require "./lib/dexpace/instrumentation/no_span"
        require "./lib/dexpace/instrumentation/no_tracer"
        require "./lib/dexpace/instrumentation/bundle"
        require "./lib/dexpace/instrumentation/scope"
        require "./lib/dexpace/instrumentation/tracing"
        require "./lib/dexpace/instrumentation/meter"
        require "./lib/dexpace/instrumentation/http_tracer"
        require "./lib/dexpace/instrumentation/callable_adapter"

        if defined?(Dexpace::Instrumentation::Event)
          raise "Regression: Dexpace::Instrumentation::Event must not be loaded by 5c files"
        end

        # Exercise tracing and metrics without any logger or event
        span = Dexpace::Instrumentation::NO_SPAN
        Dexpace::Instrumentation::Tracing.with_span(span) do
          meter = Dexpace::Instrumentation::NO_METER
          counter = meter.create_counter("test")
          counter.add(1)
        end
        puts "OK"
      RUBY
    ]

    out = IO.popen(cmd, err: %i[child out], chdir: GEM_ROOT, &:read)
    assert_equal("OK\n", out)
  end
end
```

`no_span` and `no_tracer` are required **before** `bundle`, and `bundle` requires them back:
`Bundle.build` defaults `span:` to `NO_SPAN` and `NONE = build(...)` runs at load, so entering
`bundle.rb` first would raise `uninitialized constant
Dexpace::Instrumentation::Bundle::NO_SPAN`. The order above is the one `lib/dexpace.rb` uses and
is the order this list must keep.

If `lib/dexpace.rb` ever becomes the gem's only entry point and requires the whole tree, this
assertion weakens to a require-scan over 5c's own `lib/` files — and **the weakening is recorded
in the execution report**, not quietly substituted (design open question 6).

- [ ] **Step 2: Run test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/instrumentation/independence_test.rb`
Expected: PASS with 1 run, 0 failures, 0 errors. `err: %i[child out]` is load-bearing: without it
a subprocess failure arrives as an empty `out` and an assertion that says nothing about why.

---

## Task 12: Final Wiring, Surface Snapshot, RBS Baseline, Checklist, and Register Updates

**Requirement IDs:** `NFR-3` (RBS + Steep), `NFR-4` (surface snapshot), `DEF-37` (closed), `DEF-1` (picked up, part), `DEF-30` (condition unmet note), `DEF-42` (cited), `OI-28` / `OI-29` (cited).
**Design:** "Module layout"; "The interface surface later phases may cite"; "Deferral-register sweep"; "Open questions for 5c's own plan".

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Regenerate: `test/fixtures/surface/dexpace-core.txt` (**repository root**, not under the gem —
  phase 0 put the six manifests at `test/fixtures/surface/*.txt`)
- Create: `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-checklist.md`
- Register edits: `docs/deferred-items.md` (`DEF-37` CLOSED, `DEF-1` second half picked up,
  `DEF-30` a dated `Status` line and nothing more); `docs/open-items.md` — **nothing to write**
- Update: `CLAUDE.md`'s claims sentences

**No register row is filed by this task.** `DEF-42`, `OI-28`, `OI-29` and `OI-30` were filed by the
pass that reconciled the 5b and 5c designs, and **`OI-31`** by the pass that reconciled the two
**plans**; all five are **already in the registers** — verify they are there and cite them; re-filing
them under new ids is the mistake both phase-4 plans made. `OBS-32` files no new row: it is `DEF-9`'s,
pre-existing.

**`OI-31` is 5c's too, not only `5b`'s.** It records that the slot precedence this segment argued for
in `R11` — "the context's bundle wins when it is not `Bundle::NONE`; otherwise the step's keyword;
otherwise `NO_TRACER_FACTORY`" — has no implementation path in its first clause, because no mechanism
lets a pipeline step reach a `RequestContext` or an `Instrumentation::Bundle`. Nothing 5c ships
changes: the two slot defaults, `NO_METER`, `NO_TRACER_FACTORY` and `Tracing.correlate`'s `bundle`
parameter are all unaffected — `correlate` takes the bundle as an **argument** precisely so `Tracing`
carries no `CTX` dependency. The clause is `5b`'s call site and phase 6's to close.

**Interfaces:**
- Consumes: all 5c components.
- Produces: fully wired `dexpace-core` runtime, verified type signatures, updated registers.

- [ ] **Step 1: Wire requires into `lib/dexpace.rb`**

Add **five** lines to `gems/dexpace-core/lib/dexpace.rb`, in this order — `scope` before `tracing`
because `tracing.rb` requires it and because `CURRENT_SPAN_KEY` is declared there, and all five
after 4a's `instrumentation/bundle` line:
```ruby
require_relative "dexpace/instrumentation/scope"
require_relative "dexpace/instrumentation/tracing"
require_relative "dexpace/instrumentation/meter"
require_relative "dexpace/instrumentation/http_tracer"
require_relative "dexpace/instrumentation/callable_adapter"
```

`5b`'s `dexpace/instrumentation/diagnostics` line is **`5b`'s to add**; `scope.rb` and `tracing.rb`
pull it in by `require_relative` regardless of which segment lands first, which is what keeps the
two orderable in either order. No line is added for a `keys.rb`: 5c ships none.

- [ ] **Step 2: Regenerate runtime surface snapshot**

Run: `bundle exec rake surface:regenerate`
Expected: the snapshot gains `Dexpace::Instrumentation::Tracing`, `::Scope`, `::NO_SCOPE`,
`::HTTPTracer`, `::NULL`, `::CallableAdapter` and `::NO_METER`, together with the widened method
rows on `NO_SPAN`'s and `NO_TRACER`'s classes, `TraceIdFlavour#generate_trace_id` and
`Bundle#sampled?`. `NoScope`, `NoMeter`, `NoCounter`, `NoHistogram` and `NullHTTPTracer` are
`private_constant` and must **not** appear (verified fact 7: `Module#constants` excludes them);
neither do `NO_COUNTER` and `NO_HISTOGRAM`.

`OI-19` is live here and not background: the snapshot "does not hold a `Data`-generated reader for
any type using this repository's `class X < Data.define(...)` convention". `TraceIdFlavour` is such
a type — `#generate_trace_id` is an ordinary method and *is* held, but a stable diff is **not**
proof the `Data` readers are covered.

- [ ] **Step 3: Validate RBS and Steep typecheck**

Run:
```bash
bundle exec rbs validate
bundle exec steep check
```
Expected: PASS with 0 errors.

- [ ] **Step 4: Generate the Phase 5c checklist file**

Create `docs/work/mvp/phase5/phase5c/2026-09-09-phase5c-tracing-and-metrics-checklist.md`, **one
row per ID**, for the 12 in scope — `OBS-21`–`OBS-33` less `OBS-24`, which is `5b`'s — each naming
the numbered task that satisfies it, using the roadmap's ✅ / 🚫 / ⏳ / N/A legend verbatim. Copy the
`OBS-29` row from the design's *R14* section rather than inventing one, and copy the `OBS-32` row's
⏳ `DEF-9` disposition rather than giving it a task home. Four rows carry no ID and must still be
present: the span, scope and tracer protocols behind phase 4a's three singletons (`DEF-37`
closing), `SEAM-28`'s consumer (`DEF-1`'s second half), the widened `_Span`/`_Tracer` RBS
interfaces, and the filled `_Meter`/`_Counter`/`_Histogram` declarations 5b types against. Add a
line stating that `OBS-24` and `OBS-34` are `5b`'s and are listed only so a reader following the
charter's arithmetic finds the answer here.

- [ ] **Step 5: Edit the registers — three rows, and no more**

In `docs/deferred-items.md`:
1. `DEF-37`: `Status` to `picked-up (2026-09-09, phase 5c) — CLOSED`. The five prohibitions in its
   "What phase 5 may not do" were honoured item by item; say so.
2. `DEF-1`: second half (`SEAM-28`) to `picked-up (2026-09-09, phase 5c)`. The `SEAM-24` half is
   untouched and stays with `DEF-11`. Note in the row that `SEAM-28` was read out of appendix C
   because it exists **only** as an appendix-C row (`OI-1`, unresolved) — `docs/product-spec/03-…`
   does not carry the ID.
3. `DEF-30`: append a dated line to `Status`: `2026-09-09 (phase 5c): condition read and found NOT
   met — SEAM-2 enumerates five core interface seams and instrumentation is not among them; 5c
   registers nothing, discovers nothing and adds no fourth registry`. It does **not** become
   UNSCHEDULED: that is for a row whose condition a phase met and declined.

Then verify — do not re-file — that `DEF-42`, `OI-28`, `OI-29`, `OI-30` and `OI-31` are present and
that `DEF-9` still carries `OBS-32`. `docs/open-items.md` gets nothing. `docs/deviations.md` gets
nothing from this task: `P5-40`–`P5-49` are consolidated into design §10 by a human, which is
judgement and not a mechanical append.

- [ ] **Step 6: Update `CLAUDE.md`'s claims sentences**

The `claims` check reads the phase-directory sentence out of `CLAUDE.md` and compares it against
the live tree. Narrow the "plan still to be written" wording to the sub-phases that still have
none, and do not write a count that the probe can derive.

- [ ] **Step 7: Run the full gate set and the housekeeping probe**

```bash
bundle exec rake                          # all 17 blocking gates, none lowered
ruby .claude/skills/housekeeping/probe.rb # read-only; fix what it reports, never rewrite prose to satisfy it
```

The three zero-dependency checks are the ones this segment can plausibly break: the gemspec audit
(core's `runtime_dependencies` still empty), the require-allowlist audit (5c adds `securerandom`,
already on the list, and no `logger` anywhere in `lib/` **or** `test/` — the scan reads text), and
the clean-bundle isolation run on every Ruby in the matrix.

---

## Self-review against the design

### Requirement IDs Accounted For

| Requirement ID | Scope Status | Task Home | Disposition Summary |
|---|---|---|---|
| `OBS-21` | Implemented — core's only span is non-recording | Task 3 | Every clause holds on shipped code; the **recording** branch is an SPI obligation stated in `_Span`'s YARD and asserted against `RecordingSpan`, a test fake, because core ships no recording span (`P5-48`) |
| `OBS-22` | Implemented | Task 5, Task 6 | Scope handle restoring previously active span, nesting, exception safety |
| `OBS-23` | Implemented | Task 6 | Push `trace.id` / `span.id`, restore/delete on close, non-recording delegation |
| `OBS-24` | **Not 5c's** | — | `5b`'s (`R12`, `P5-23`), and it carries a row in `5b`'s scope table. Listed here for the reader the charter's arithmetic will send here (`OI-30`). 5c owns `OBS-23`'s per-key push and contributes the measurement `5b` need not re-derive: `Fiber.current.storage` already returns a fresh unfrozen `Hash`, so the snapshot's immutability is one `freeze`. `P5-49`'s gap is inherited by `5b`'s union restore |
| `OBS-25` | Implemented | Tasks 3, 4, 5, 6, 7 | The no-op tracer returns the shared `NO_SPAN`, `NO_SCOPE` is the cached-singleton scope, `Bundle::NONE` is the no-op context whose identifiers are all invalid sentinels, and `NO_TRACER_FACTORY`/`NULL` are the no-op factory and HTTP tracer. "MUST NOT allocate per call" is met by **no method in the segment taking a `**` splat** (`P5-42`, `OI-28`) and asserted by reference identity from a qualified constant plus a two-loop delta with non-allocating arguments. `NO_SCOPE` is returned on an **identity** test — not the recording flag, which would leave a recording span un-restored under a non-recording one (`P5-47`) |
| `OBS-26` | Satisfied by **phase 4a**, which 5c populates and may not redefine | Task 2 | The reserved sentinels, the 16-lowercase-hex span-id rule and the derived validity flag are `Bundle`, `Bundle::INVALID_SPAN_ID` and `TraceIdFlavour`, all shipped by 4a and untouched here. 5c adds only `#sampled?` over the existing `trace_flags` member, which 4a explicitly reserved for phase 5 (boundaries 10 and 11) |
| `OBS-27` | Implemented | Task 2 | Trace-id generation for W3C, Datadog, NONE; mandatory zero-draw coercion |
| `OBS-28` | Implemented | Task 8, Task 9 | 11-method HTTP tracer event vocabulary and `CallableAdapter` bus shape |
| `OBS-29` | ✅ **contract and ordering test only** | Tasks 4, 8, 10 | The eleven-method vocabulary, its no-op defaults and an ordering assertion over a conformant emitter fake ship in 5c. **Nothing in phase 5 emits any of it**: the per-attempt group has no emitter until phase 6's retry step and the transport-milestone group none until phase 8's adapters, which the requirement's own last sentence anticipates. Wiring is `DEF-42`, picked up with `DEF-39`'s `Pipeline.standard`. The 1:1 clause is read as binding stateful tracers only (`P5-43`) and is asserted against `RecordingTracer`. *Cites:* `OBS-28`, `OBS-29`, `DEF-39`, `DEF-42`, §8.1 |
| `OBS-30` | Implemented **by construction** | Tasks 4, 6, 7, 8 | Core wraps no tracer or meter call anywhere, which is the whole of the runtime's obligation; concurrency safety is identity across threads on frozen stateless singletons. The must-not-throw half is a contract on implementers, documented and asserted by a throwing block that is required to **propagate** out of `Tracing.with_span` with the slot still restored (`OBS-20`'s conformance clause says so in as many words) |
| `OBS-31` | Implemented | Task 7 | Metrics SPI: `NO_METER` manufacturing shared counter and histogram singletons, asserted meter-to-meter under two different names. Core pulls in no metrics runtime |
| `OBS-32` | ⏳ **Deferred, `DEF-9`** (pre-existing) | — | No task home, deliberately. `http.client.request.count` and `http.client.request.duration` appear nowhere in 5c's `lib/`; the names are `5b`'s, and the units, descriptions, semantic-convention conformance and attribute sets stay deferred because the conformance clause needs a recording meter core does not ship (`P5-48`, `DEF-17`). Task 12 files no new row |
| `OBS-33` | Implemented | Task 7 | The MUST-document half is discharged on `_Counter#add`'s signature in `sig/` and on `NoCounter#add` in `lib/` — the only two places a duck-typed SPI's contract can bind — with **no hot-path validation**; histogram tolerates NaN, ±Infinity, 0 and negatives, asserted by `assert_nil` on the return value rather than `assert_nothing_raised` (`testing/26b866e1`) |
| `OBS-34` | **Not 5c's** | Task 11 | `5b`'s ID. 5c ships a structural regression proving it acquires no dependency on the logging half; the conformance clause is discharged by `5b`'s step test at `HTTPLogging::NONE`. Named as two mechanisms, not one (`R11`) |
| `CTX-20` | Satisfied by **phase 4a**, re-asserted here | Task 4 | The no-op factory's existence is 4a's; 5c asserts the embedded MUST — "safe to invoke concurrently from multiple threads" — as an identity test across 16 threads |
| `SEAM-28`| Consumed, closing `DEF-1`'s second half | Task 4 | `_TracerFactory#tracer(name, …)` takes the operation identifier `RequestContext#operation_name` carries, which is the consumer `DEF-1` was waiting for. `SEAM-28`'s own constraint holds structurally: nothing in `Dexpace::Instrumentation` can reach a `Request` at all. `SEAM-28` is one of the five IDs `OI-1` records as existing only as an appendix-C row; the register note must say so. The `SEAM-24` half stays with `DEF-11` |
| `DEF-37` | Picked up / **CLOSED** | Tasks 3, 4, 5, 12 | The three `private_constant` classes get their methods and `_Span`/`_Tracer` are widened, with all three published objects keeping the identity phase 4 gave them — which is what makes `OBS-25`'s allocation clause assertable by reference identity. The five prohibitions are honoured item by item: no second no-op span or tracer, neither published singleton replaced, no `Bundle` member renamed, removed **or added**, `#valid?` left derived, `TraceIdFlavour` left a `Data`, `Bundle` given no second `NONE` |
| `DEF-30` | Condition read, **found NOT met** | Task 12 | `SEAM-2` enumerates five core interface seams and instrumentation is not among them. 5c registers nothing, discovers nothing and adds no fourth registry; phase 2's test asserting the auto-activation hook is absent stays green, untouched. The row gains a dated `Status` line and does **not** become UNSCHEDULED (`R15`) |

### Deviation Ledger Accounting

- `P5-40` (Public constants not named in §8.1: `Tracing`, `Scope`, `NO_SCOPE`, `HTTPTracer`, `NO_METER`): Tasks 5, 6, 7, 8.
- `P5-41` (Public methods not named in §8.1): Tasks 2, 3, 4, 5, 6, 7, 8.
- `P5-42` (No `**` keyword splats; named optional keywords for zero allocation): Tasks 1, 3, 4, 7.
- `P5-43` (`OBS-29` 1:1 clause applies to stateful tracers; `NO_TRACER_FACTORY` returns shared object): Task 4.
- `P5-44` (No span-id generator shipped; `OBS-27` applies to trace IDs): Task 2.
- `P5-45` (`OBS-22` scope handle exposed block-form-first, bare handle secondary): Tasks 5, 6.
- `P5-46` (`Scope` is plain 3-ivar class, not Data): Task 5.
- `P5-47` (`NO_SCOPE` returned on identity test, not recording flag): Task 6.
- `P5-48` (Core ships no recording span/tracer/meter; assertions use fakes under `test/support/`): Tasks 1, 3, 4, 7, 8, 10.
- `P5-49` (Per-key restore turns null-valued key into absent key): Tasks 5, 6.

**Ten rows, `P5-40`–`P5-49`, and this plan adds none.** The design fixed the block; a plan that
files a new `P5-` number has re-opened a decision the design closed. `5b` holds `P5-16`–`P5-38` with
`P5-39` a deliberate unused gap, and nothing here reaches into that block. `DEF-42`, `OI-28`, `OI-29`,
`OI-30` and `OI-31` are already in the registers and are cited, not re-filed.

### Tests Written as Code Fences (Addressing Tests Readers Write Wrong)

1. `OBS-25` allocation test: uses frozen non-allocating arguments and two-loop delta cancellation (Task 4, Step 1).
2. `OBS-25` identity test: asserts `assert_same NO_SPAN` on qualified constant (Task 4, Step 1).
3. `OBS-22` nesting test: uses two distinct `RecordingSpan` instances and asserts `assert_same` at each level (Task 6, Step 1).
4. `OBS-22` throw test: asserts slot restoration *after* `assert_raises` (Task 6, Step 1).
5. `OBS-23` restore test: asserts `refute Fiber.current.storage.key?(...)` to distinguish absent from nil (Task 6, Step 1).
6. `OBS-23` non-recording test: asserts diagnostic push skipped while current span still activated (Task 6, Step 1).
7. `OBS-21` idempotence test: asserts no duplicate export on `RecordingSpan#finish` called twice (Task 3, Step 1).
8. `OBS-27` generation test: asserts format over 1000 draws and tests zero-draw coercion via injected fake (Task 2, Step 1).
9. `OBS-30` concurrency test: asserts identity across 16 threads (Task 4, Task 7, Step 1).
10. `OBS-30` non-wrapping test: verifies throwing block propagates out of `with_span` while ensure restores (Task 6, Step 1).
11. `OBS-33` histogram toleration: tests `assert_nil` for NaN, Infinity, -Infinity, 0, and negative numbers (Task 7, Step 1).
12. `OBS-31` shared instrument test: compares instruments created under different names (Task 7, Step 1).
13. `OBS-29` ordering test: verifies succeeding and failing sequences with exhausted→failed adjacency and same throwable (Task 10, Step 1).

**Two of the design's list are answered differently and it is worth saying which.** `OBS-30`'s
must-not-throw assertion is driven by a `raise` inside the guarded block rather than by a throwing
fake tracer; the mechanism under test — nothing rescues, the `ensure` restores anyway — is the
same, and a throwing `RecordingTracer` variant is the stronger form if a later pass wants it.
`OBS-21`'s `#status=` assertion goes through `public_send`, because `span.status = :ok` as an
expression always evaluates to its right-hand side and therefore asserts nothing about the method.

### What this plan does not verify

Stated so a reader does not take silence for confirmation.

- **The 3.2.11 and 4.0.6 columns have not been run.** Only 3.4.10 is installed; every fact and
  every fence below was exercised on it alone. Task 1 is the instruction, not the record.
- **`opentelemetry-api` is not installed**, so every claim about its method names and arities is
  unverified. Task 3 is where the check happens; `P5-42` is not negotiable by it.
- **Four MUSTs are verified against fakes, not shipped code** — `OBS-21`'s recording branch,
  `OBS-29`'s ordering, `OBS-30`'s must-not-throw and `OBS-31`'s per-measurement recording. That is
  `P5-48`'s accepted cost, and phase 8's `dexpace-conformance` (`DEF-22`) is where the same
  assertions meet a real adapter.
- **Eleven `HTTPTracer` method names are `NFR-4`-locked before any emitter exists to prove they
  are the right eleven.** `R14` states the risk and accepts it; this plan does not reduce it.
- **`Scope.build` is a public class method that `P5-41` does not enumerate.** It is the internal
  constructor — `private_class_method :new` cannot keep construction "inside `Tracing`" when
  `Tracing` is a sibling module — and it is marked `@api private` with no YARD block, which is this
  repository's own definition of internal. Whether `P5-41` should be widened to name it is a
  judgement for the human consolidating the ledger into design §10.
