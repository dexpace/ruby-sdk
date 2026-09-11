# Phase 7a — Serialization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship serialization in full across two gems — `dexpace-core`'s witness protocol
(`Dexpace::Serde.witness!`, `DecodeContext`, four combinators), the `Tristate` three-state PATCH
type, the `Native` encode walk, `Body.serialized`, and the two `Dexpace::_ResponseHandler`s supplied
into phase 3b's `TypedResponse`; and `dexpace-serde-json`'s `Codec`, which fills that gem's `lib/`
and declares the `json >= 2.19.9` floor. All thirty `SERDE-1`–`SERDE-30` requirements, with three
carrying a deviation row and six a stated clause. No deferral is filed.

**Architecture:** One decode context (`Dexpace::Serde::DecodeContext`) carrying the path and the
**one** raise site for every shape failure — `SEAM-29`'s discipline applied to `SERDE-13`/`SERDE-21`/
`SERDE-22`, so strictness is a shared helper rather than a per-witness convention. One witness
predicate pair (`.witness!`/`.witness?`) over `respond_to?(:dexpace_load)`, never a nominal test, so
a model **class** and a combinator **instance** are witnesses under one rule and the combinator set
is open. One encode walk (`Dexpace::Serde::Native.of`) that drops an `OMIT`-dumping key from a
`Hash`, maps it to `nil` in an `Array` and at top level, and raises `SerializationError` **naming the
class** for anything non-native — because `::JSON.generate` measurably does not. Two handlers over
3b's `TypedResponse`, the status-aware one delegating to the decoding one so `SERDE-27` has exactly
one implementation, and calling phase 4b's `Recovery.buffer_error_body` and `ProtocolError.for`
rather than building a second buffering site or a second error type. One adapter class
(`Dexpace::Serde::JSON::Codec`), frozen, owning a private `::JSON::Coder` built from a frozen options
`Hash`, passing `strict: true`, reading UTF-8 through 3a's `#read_utf8` under `IO-9`'s ceiling,
validating it, and rescuing `::JSON::JSONError` and nothing wider.

**Tech Stack:** Ruby 3.2–4.0 (authored on 3.4.10), Minitest, RBS + Steep (the `serde_json` target has
**two** signature roots), RuboCop with phase 0's five custom cops plus phase 2's sixth, SimpleCov,
YARD. `dexpace-core` gains **no** dependency and no allowlist entry. `dexpace-serde-json` gains
exactly one: `json >= 2.19.9`.

**Spec:** `docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization-design.md`, under the
charter `docs/work/mvp/phase7/2026-09-10-phase7-segmentation-design.md`.
`docs/product-spec/14-serialization-serde.md` is the normative chapter for all 30 IDs and every one
of them appears in it, so appendix C is used for the modal level and not for the text.

## Global Constraints

- **`dexpace-core` gains no dependency and its require allowlist does not grow.** `time` (for
  `Dexpace::Serde::Instant`) is already on it. Core's new files `require` nothing else outside
  `dexpace/`.
- **`dexpace-serde-json` gains exactly one third-party dependency**, and the gemspec line lands
  **before** the first `require "json"` in that gem's `lib/` — phase 0's adapter-extended
  require-allowlist audit permits only "the single third-party gem that adapter's gemspec declares",
  so the reverse order is a red build. Task 13 is where the line lands and Task 14 is the first task
  that requires `json`.
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`).
- **Inside `module Dexpace::Serde`, `JSON` is the adapter and Ruby's is `::JSON`.** Phase 2's
  `Dexpace/QualifiedCoreConstant` rejects a bare `JSON` under `lib/dexpace/serde/**` in **both** gems.
  Core's `lib/dexpace/serde/**` writes the token `JSON` in no form at all; the adapter writes `::JSON`
  everywhere. Every other core constant is `::`-qualified too: `::Time`, `::String`, `::Hash`,
  `::Array`, `::Integer`, `::Float`, `::IndexError`, `::ArgumentError`, `::Encoding`, `::Gem`.
- **`::JSON::Coder#load` is `::JSON.parse`'s configured form and is NOT `::JSON.load`.** They share
  four letters and nothing else; design §3.4 bans `JSON.load` and `JSON.dump` by lint rule
  (`serde/5e420c20`). Every call site carries the one-line comment saying so, so a later reader does
  not "fix" it.
- **`Timeout.timeout`, `Thread#raise` and `Thread#kill` are forbidden** (`Dexpace/NoThreadInterrupt`).
  Nothing in this plan waits, sleeps or interrupts.
- **`Thread::Mutex` is held nowhere in this plan.** `HTTP-45`'s flip-only lock is 3b's, shipped, and
  a handler supplied into `TypedResponse` runs **outside** it by construction.
- **`downcase` takes no arguments** (`Dexpace/NoLocaleCaseFold`). Media-type folding is phase 1's
  `MediaType`, at construction; this plan writes no fold.
- **`Time.parse`/`Date.parse`/`DateTime.parse` are banned** (`Dexpace/NoTimeParse`).
  `Time.iso8601`/`Time#iso8601` from `time` are what `SERDE-24` uses and are not what the cop bans.
- **No regexp is compiled in this plan**, so `Regexp.new(source, timeout:)` has no site here. If one
  appears during implementation it carries its own timeout and never `Regexp.timeout`.
- **Domain model construction pattern:** `Data.define`, `include Dexpace::Model`,
  `private_class_method :new`, `.build` with `Model.required!`, `Model.own` for a collection member,
  shallow `freeze`.
- **Every encoding assertion uses non-ASCII content.** `io-and-byte-streams/a44b4de6`: appending an
  ASCII-only `String` to a BINARY one leaves it BINARY, so an ASCII-only fixture passes under exactly
  the bug.
- **`raise Klass, "msg", cause: nil`** wherever an error must not chain the caller's in-flight one —
  `pipeline/f02559b9`'s spelling, and `SERDE-4`'s "not chaining one" made structural.
- **Formatting:** double quotes, 2-space indentation, 100 columns, `consistent_comma` trailing
  commas.

### Commands

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/<path>_test.rb        # one core suite
bundle exec ruby -w gems/dexpace-serde-json/test/dexpace/<path>_test.rb  # one adapter suite
(cd gems/dexpace-core && bundle exec rake test)
(cd gems/dexpace-serde-json && bundle exec rake test)
bundle exec rake                                                        # all seventeen gates
bundle exec rubocop
bundle exec steep check
bundle exec rbs validate
bundle exec rake surface:regenerate                                     # deliberate; Task 18 only
```

### What was verified during planning

**One interpreter, and this plan says so before it says anything else.** Only Ruby **3.4.10** is
installed on the authoring machine — re-checked while writing this plan. **The 3.2 and 4.0 columns
have not been run for anything below.** Task 1 installs both and re-runs every fact on all three.

**A second axis this phase is the first to have: the `json` version.** Two were exercised — the
interpreter's default gem **2.9.1** and **2.19.9**, the exact gemspec floor, installed into a scratch
`GEM_HOME`. The design's *Verified Ruby facts* section carries all fifteen; the eight this plan's
tasks are written directly against are:

1. **`JSON.parse(StringIO.new(…))` raises `TypeError` on 2.9.1 AND on 2.19.9.**
   `JSON::Parser.instance_methods(false)` is `[:parse, :source]` on both; no singleton method is
   pull-shaped. `JSON.parse(obj)` *does* succeed for an object answering `#to_str`, and that buys
   nothing because `#to_str` returns the whole `String`. `P7-1`, Task 15.
2. **`::JSON.generate(Object.new)` returns `"\"#<Object:0x…>\""` — it does not raise — on both
   versions. `strict: true` makes it raise `JSON::GeneratorError`.** Tasks 7 and 14.
3. **`JSON::ParserError < JSON::JSONError < StandardError`, and `IOError` is nowhere in it.** So
   `rescue ::JSON::JSONError` structurally cannot catch a `Dexpace::StreamError`. Task 15.
4. **`IO::Buffer.new` warns through `Warning.warn` at every warning level, category
   `:experimental`**, and phase 0's shared test case overrides `Warning.warn` **to raise**.
   `IO::Buffer#set_string` raises `ArgumentError` where `String#[]=` raises `IndexError`. `P7-5`,
   Task 14.
5. **`String#[]=` with an in-range offset and an over-long payload silently GROWS the string**
   (`("\0"*4).b[2,3] = "abcd".b` → six bytes). An out-of-range offset raises `IndexError`; a frozen
   target raises `FrozenError`. `SERDE-4` needs an explicit fit check. Task 14.
6. **`JSON.parse(%Q({"a":"\xff"}).b)["a"]` is UTF-8-tagged with `#valid_encoding?` `false`**, and
   phase 3a's `#read_utf8` retags without validating. `"\xc3\xa9".b.encode(UTF_8, BINARY)` raises on a
   valid `é`, so a transcode is the wrong repair. `P7-6`, Task 15.
7. **`JSON::Coder` exists on 2.19.9 and NOT on 2.9.1.** `initialize` takes `[[:opt, :options],
   [:block, :as_json]]`; instance methods `[:dump, :generate, :load, :load_file, :parse]`; freezable;
   thread-safe across 8 threads × 500 dumps. `P7-4` and `P7-7`, Tasks 13, 14 and 16.
8. **`Time#iso8601(n)` truncates.** `Time.new(2026,9,10,12,0,0.123456,"+02:00").iso8601(6)` is
   `"…00.123455+02:00"` and the round trip is **false**; `Time.at(0, 123456, :usec)` round-trips
   exactly at `iso8601(6)`; whole seconds round-trip at `iso8601`. `Time.iso8601` rejects
   `"2026-09-10"` and `"2026-09-10 12:00:00"`. `P7-8`, Task 8.

Two further facts are relied on with no task of their own: `raise Klass, "msg", cause: nil` gives
`#cause` `nil` even inside a `rescue` (Task 14), and `respond_to?` sees a class method so one
predicate covers a model class and a combinator instance (Task 3).

The following were confirmed by **reading the shipped source through its phase's plan**, not by
re-deriving them from design prose:

- **`Dexpace::Serde::CONTRACT`** is `%i[media_type dump_string dump_bytes dump_to dump_into load]`,
  `private_constant`, and `.conforms?` is `CONTRACT.all? { |n| object.respond_to?(n) }`
  (`docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md:4576-4610`). `#dump` is **not** in it.
- **`interface _Codec`'s body was never written.** Phase 2's Step 6 says the file "carries
  `interface _Codec` with the six methods and the module's class methods" and gives no types
  (`…:4613-4614`). Task 12 writes it.
- **`Dexpace::Body#source` default raises `Dexpace::StreamError` naming the class and `#close`
  default is a no-op**; `Dexpace::BufferBody#source` returns a **fresh `#peek` view per call** and its
  `#close` is the no-op (`…phase3b…-design.md:706-764`). `SERDE-28`'s buffered error body is readable
  twice because of that, and Task 11's test asserts it.
- **`Dexpace::TypedResponse.new(response:, handler:)`** validates `handler` with
  `respond_to?(:call)`, memoizes through a four-state `@state`, and re-raises a memoized failure as
  the **same object** (`…phase3b…-design.md:514-558`). Task 10 asserts both against a call-counting
  handler.
- **`Dexpace::Recovery.buffer_error_body(response)`** returns the response unchanged when
  `status.error?` is false **or the body is `nil`**, otherwise calls `Body.buffer_bounded` and
  releases the original in an `ensure` (`…phase4b…-design.md:1136-1150`). So Task 11's 4xx/5xx branch
  needs **no** `nil` check and **no** second close.
- **`Dexpace::Recovery::ErrorMappingStep.build(factory: Dexpace::ProtocolError.method(:for))`** is
  the default spelling `StatusAwareHandler` copies (`…phase4b…-design.md:1186`).
- **`Dexpace::IO::BufferedSource#read_utf8(count: nil)`** drains with no count and is guarded
  **incrementally** by `MAX_MATERIALIZED_BYTES` under `P3-4`, raising `Dexpace::StreamError`
  (`…phase3a…-design.md:657`, `:1048`, `:1109`).
- **`Dexpace::Model.required!(name, value)`** raises `Dexpace::InvalidArgumentError` with exactly
  `"<name> is required"`, and **`Model#with` routes through `.build`** on every supported Ruby
  (`…phase1…-design.md:338-346`, `data-modeling/83610619`).
- **`gems/dexpace-serde-json`'s skeleton** exists at `0.0.0` with a gemspec declaring `dexpace-core`
  and nothing else, `lib/dexpace/serde/json.rb` carrying the shadowing caution,
  `lib/dexpace/serde/json/version.rb` defining `Dexpace::Serde::JSON::VERSION`, a shadowing-regression
  test, and a Steep target with two signature roots
  (`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates.md:1374-1398`, `:1650-1657`,
  `:2628-2630`).

## This plan's open questions, resolved

The design's five open questions are resolved below with a concrete decision each.

1. **The scalar-witness table's membership.** *Decision:* `::String`, `::Integer` and `::Float` map to
   scalar witnesses; **booleans get a named constant, `Dexpace::Serde::BOOLEAN`**, rather than two
   class keys, because Ruby has no `Boolean` class to key on and `List.of(TrueClass)` would read as a
   list of `true`s. **`::Time` is NOT in the table** — the ISO-8601 wiring is the adapter's per
   design §3.4, and a core mapping would make it every codec's default. A caller wanting times writes
   `List.of(Dexpace::Serde::Instant)`. Task 5 builds the table; Task 8 builds `Instant`.
2. **`DecodeContext#path`'s rendering.** *Decision:* **JSON Pointer, RFC 6901** — `/pets/3/name` —
   with `~0`/`~1` escaping for a key containing `~` or `/`. A dotted path needs a bespoke quoting rule
   the first time a key contains a `.`, and there is no standard for it. Task 2.
3. **The `SERDE-27` empty-body boundary.** *Decision:* **the handler checks, not the codec.**
   `SERDE-27` requires the exception to *name the target type* and only the handler holds the
   witness; `::JSON.parse("")`'s own `ParserError` names nothing useful. `DecodingHandler` raises for
   a `nil` body **and** for a body whose `#content_length` is `0`, and additionally converts a
   codec-side "unexpected end of input" `ParserError` into the same target-naming message. Task 10.
4. **`Codec.build`'s options validation.** *Decision:* **validated against a frozen allowlist**,
   raising `Dexpace::InvalidArgumentError` for an unknown key, because `::JSON::Coder.new` accepts
   unknown options silently and a forwarded typo produces a codec configured differently from what
   the caller wrote with no signal. The allowlist starts as `%i[max_nesting allow_nan
   allow_duplicate_key script_safe encoders]` and Task 14 fixes its exact membership against the
   **floored** gem, never against 2.9.1.
5. **The three-interpreter re-run, and specifically `JSON::Coder`.** *Decision:* Task 1 runs it, and
   this plan states in advance what changes if it fails. `JSON::Coder`'s presence is a property of
   the **gem**, and the gemspec floors at 2.19.9, so it should be uniform — but Ruby 4.0's own default
   `json` is unknown to this document and the bundle resolution has not been run. **If fact 7 does not
   hold on all three, `P7-4` is withdrawn** and Task 14 falls back to design §7.3's predicted route: a
   frozen options `Hash` passed to `::JSON.generate`/`::JSON.parse` per call, with §11.18's
   documented-fallback clause invoked in the YARD. Nothing else in the plan changes; `#dump_string`
   and `#load` are the only two methods that touch the coder.

## Task order and dependency chain

Eighteen tasks. The chain has one hard external ordering rule and one internal one, and both are
stated so a reader can see they are not habit.

**Hard rule, external:** the gemspec line (Task 13) lands **before** the first `require "json"` (Task
14), because phase 0's adapter-extended require-allowlist audit fails the build otherwise. This is
what the charter means by "what `7a` owes in exchange for spanning two gems".

**Hard rule, internal:** `DecodeContext` (Task 2) and the witness predicates (Task 3) land before
every witness, because every witness raises through the first and is validated by the second.

1. **Matrix and floor fact verification, test doubles, and the `SEAM-2` negative test** — installs
   `ruby@3.2.11` and `ruby@4.0.6`, re-runs the fifteen facts on all three, and builds the four doubles
   this plan needs.
2. `Dexpace::Serde::DecodeContext` (`SERDE-13`, `SERDE-21`, `SERDE-22`) — standalone.
3. `Dexpace::Serde.witness!`/`.witness?`, `WITNESS_METHOD`, `DUMP_METHOD` (`SERDE-5`, `SERDE-7`,
   `SERDE-8`) — standalone.
4. `Dexpace::Serde::Tristate`, the value type (`SERDE-14`, `SERDE-18`, `SERDE-30`) — needs Task 2.
5. The scalar witnesses and `List`/`Map`/`Nullable` (`SERDE-6`, `SERDE-8`, `SERDE-23`) — needs Tasks
   2 and 3.
6. `Tristate.of` and `#dexpace_load_field` (`SERDE-16`, `SERDE-17`) — needs Tasks 2, 3, 4.
7. `Dexpace::Serde::Native` and `OMIT` (`SERDE-15`, `SERDE-19`, `SERDE-20`) — needs Task 4.
8. `Dexpace::Serde::Instant` (`SERDE-24`) — needs Task 2.
9. `Dexpace::Body.serialized` (`SERDE-2`) — needs phase 3b's `BytesBody` and phase 1's `MediaType`.
10. `Dexpace::Serde::DecodingHandler` (`SERDE-27`) — needs Task 3 and phase 3b's `TypedResponse`.
11. `Dexpace::Serde::StatusAwareHandler` (`SERDE-28`) — needs Task 10 and phase 4b's `Recovery`.
12. `interface _Codec`'s body and core's `sig/`+`require` wiring (`NFR-3`, `NFR-11`) — needs Tasks
    2–11.
13. The gemspec line, the floor assertion and the entry file (`NFR-2`, `P7-7`) — **the ordering
    gate**.
14. `Dexpace::Serde::JSON::Codec` — construction and the four encode profiles (`SERDE-1`, `SERDE-3`
    encode half, `SERDE-4`, `SERDE-9`, `SERDE-10`, `SERDE-25`, `SERDE-26`, `SERDE-29`) — needs Tasks
    7 and 13.
15. `Codec#load` (`SERDE-3` decode half, `SERDE-5`, `SERDE-11`, `SERDE-12`, `SERDE-13`, `SERDE-21`,
    `SERDE-22`, `SERDE-23`) — needs Tasks 2, 3, 5, 14.
16. The two adapter defaults and the tri-state round trip (`SERDE-1`, `SERDE-19`, `SERDE-24`) — needs
    Tasks 6, 7, 8, 14, 15.
17. `SerdeSeamAssertions` and the adapter conformance suite (`SERDE-3`, `SERDE-4`, `SERDE-9`,
    `SERDE-10`, `SERDE-12`, `SERDE-29`) — needs Tasks 14–16.
18. Final wiring: the requires, the RBS baseline diff, the runtime surface snapshot, the knowledge
    note, and the four register-edit texts the design already drafted for a human to apply. The
    checklist is written at execution time, per `CLAUDE.md`, and is not a task this plan performs.

**Tasks 2–11 are core and Tasks 13–17 are the adapter**, and the boundary between them is where a
reviewer should check that no core file, `sig/` file or test names `Dexpace::Serde::JSON` — Task 1
builds the test that makes that mechanical.

---

## Task 1: Matrix and floor fact verification, test doubles, the `SEAM-2` negative test

**Requirement IDs:** none directly; the plan's evidence-gathering step, per the precedent phases 3–6
all set. It also builds `SEAM-2`'s mechanised guard, which has no ID of its own here.
**Design:** "The verified Ruby facts this sub-phase is built on"; `R12`.

**Files:**
- Create: `gems/dexpace-core/test/dexpace/serde/no_concrete_codec_test.rb`
- Create: `gems/dexpace-core/test/support/counting_response.rb`
- Create: `gems/dexpace-serde-json/test/support/close_counting_source.rb`
- Create: `gems/dexpace-serde-json/test/support/close_counting_sink.rb`

**Needs:** phase 2's `FakeCodec` (reused, not rebuilt); phase 3a's `BufferedSource`; phase 3b's
`Response`/`ResponseBody`.
**Produces:** three doubles plus the `SEAM-2` guard.

- [ ] **Step 1: Install the matrix and re-run every fact**

Install `ruby@3.2.11` and `ruby@4.0.6`. For each of the three, run the design's fifteen facts and
record the result in the task's notes. **Fact 7 is the one with a plan consequence**: resolve
`dexpace-serde-json`'s bundle on each interpreter and assert `::JSON::VERSION` is `>= 2.19.9` and
`::JSON.constants.include?(:Coder)` is `true`. If it is false on any row, apply open question 5's
stated fallback before Task 14 and record the withdrawal of `P7-4`.

- [ ] **Step 2: Write the `SEAM-2` negative test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# SEAM-2, and the charter's cross-cutting constraint: "Dexpace::Serde::JSON appears in no core file,
# in no core sig/ file (NFR-11) and in no core test." No other gate sees this inside one gem -- the
# require allowlist denies `json` by name but says nothing about a *constant* reference, and Steep
# type-checks core against core's own sig/ where the constant does not exist either.
class DexpaceSerdeNoConcreteCodecTest < DexpaceTestCase
  ROOT = File.expand_path("../../..", __dir__)
  TREES = %w[lib sig test].freeze

  test "no core file, signature or test names the concrete codec" do
    offenders = TREES.flat_map do |tree|
      Dir.glob(File.join(ROOT, tree, "**", "*")).select do |path|
        File.file?(path) && path != __FILE__ && File.read(path).include?("Serde::JSON")
      end
    end

    assert_empty(offenders, "SEAM-2: core must name no concrete codec")
  end

  test "the seam itself supplies no media type to fall back to" do
    refute_respond_to(Dexpace::Serde, :media_type, "SEAM-19, restated at phase 7's first consumer")
  end
end
```

- [ ] **Step 3: Write `test/support/counting_response.rb` in core**

A `Response`-shaped double whose `#close` increments a counter and whose `#body` returns a
body-shaped double with a scriptable `#source` and its own close counter. `SERDE-27`'s conformance
clause asks for "one close" in five different scenarios, and a counter is the only way to assert
"one" rather than "at least one".

- [ ] **Step 4: Write the two close-counting trackers in `gems/dexpace-serde-json/test/support/`**

`CloseCountingSource` wraps a `Dexpace::IO::BufferedSource` built with `.of_bytes`, forwards every
read method, and counts `#close` calls. `CloseCountingSink` wraps a `StringIO`, forwards `#write`
returning the byte count, and counts `#close`. `SERDE-3`'s conformance clause names a "close-counting
tracker" in as many words and requires the count to be **0**, so the doubles must be able to report
zero rather than merely not raise.

- [ ] **Step 5: Confirm the `SEAM-2` test passes on an empty tree**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/serde/no_concrete_codec_test.rb`
Expected: PASS, 2 runs. It stays green through every core task and is the gate Task 12's `sig/` work
must not break.

---

## Task 2: `Dexpace::Serde::DecodeContext`

**Requirement IDs:** `SERDE-13`, `SERDE-21`, `SERDE-22`.
**Design:** "`R2` — what `ctx` is"; "The object model `7a` ships — `Dexpace::Serde::DecodeContext`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/serde/decode_context.rb`,
  `gems/dexpace-core/sig/dexpace/serde/decode_context.rbs`
- Test: `gems/dexpace-core/test/dexpace/serde/decode_context_test.rb`

**Needs:** phase 1's `Dexpace::Model`; phase 2's `Dexpace::Serde::DeserializationError`.
**Produces:** `DecodeContext.root`, `#path`, `#at`, and the eight `!` methods.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# SERDE-13, SERDE-21, SERDE-22. The strictness burden moves into the witness (serde/b5e5efc8) --
# which makes it a per-field discipline unless something makes it a shared helper. This is that
# helper, and it is Model.required!'s discipline applied to a second family of failures: ONE raise
# site, ONE message form, so "naming the target type" is a property of one method rather than of
# every witness anyone writes.
class DexpaceSerdeDecodeContextTest < DexpaceTestCase
  def ctx = Dexpace::Serde::DecodeContext.root

  test "the root context has an empty frozen path and is itself frozen" do
    assert_empty(ctx.path)
    assert_predicate(ctx.path, :frozen?)
    assert_predicate(ctx, :frozen?)
  end

  test "#at appends one segment and returns a new context, leaving the receiver untouched" do
    child = ctx.at("pets").at(3).at("name")

    assert_equal(["pets", 3, "name"], child.path)
    assert_empty(ctx.path)
  end

  # SERDE-21: the nine named cross-shape coercions, one fixture each. A loop would hide a dropped
  # case, and the requirement enumerates them individually.
  test "SERDE-21: string to integer is rejected" do
    assert_raises(Dexpace::Serde::DeserializationError) { ctx.integer!("5") }
  end

  test "SERDE-21: string to float is rejected" do
    assert_raises(Dexpace::Serde::DeserializationError) { ctx.float!("1.5") }
  end

  test "SERDE-21: string to boolean is rejected" do
    assert_raises(Dexpace::Serde::DeserializationError) { ctx.boolean!("true") }
  end

  test "SERDE-21: empty string to integer, float and boolean are all rejected" do
    assert_raises(Dexpace::Serde::DeserializationError) { ctx.integer!("") }
    assert_raises(Dexpace::Serde::DeserializationError) { ctx.float!("") }
    assert_raises(Dexpace::Serde::DeserializationError) { ctx.boolean!("") }
  end

  test "SERDE-21: float to integer is rejected (lossy narrowing)" do
    assert_raises(Dexpace::Serde::DeserializationError) { ctx.integer!(1.5) }
  end

  test "SERDE-21: boolean to integer and integer to boolean are both rejected" do
    assert_raises(Dexpace::Serde::DeserializationError) { ctx.integer!(true) }
    assert_raises(Dexpace::Serde::DeserializationError) { ctx.boolean!(1) }
  end

  test "SERDE-21: boolean to float is rejected" do
    assert_raises(Dexpace::Serde::DeserializationError) { ctx.float!(true) }
  end

  test "SERDE-21: a non-string scalar to string is rejected" do
    assert_raises(Dexpace::Serde::DeserializationError) { ctx.string!(5) }
    assert_raises(Dexpace::Serde::DeserializationError) { ctx.string!(true) }
  end

  # SERDE-22: the two permissions. An implementation that rejects these has broken a MUST while
  # looking stricter and therefore more correct.
  test "SERDE-22: an integer widens into a float target" do
    widened = ctx.float!(1)

    assert_in_delta(1.0, widened)
    assert_instance_of(::Float, widened)
  end

  test "SERDE-22: an empty string binds to a textual target" do
    assert_equal("", ctx.string!(""))
  end

  # SERDE-13: naming the target type, across every decode overload -- which is one method here.
  test "SERDE-13: a wire null into a non-null target names the target type and the path" do
    error = assert_raises(Dexpace::Serde::DeserializationError) do
      ctx.at("pets").at(0).string!(nil, key: "name")
    end

    assert_match(/String/, error.message)
    assert_match(%r{/pets/0/name}, error.message)
    assert_match(/NilClass/, error.message)
  end

  test "the path renders as an RFC 6901 pointer with ~0 and ~1 escaping" do
    error = assert_raises(Dexpace::Serde::DeserializationError) { ctx.at("a/b").at("c~d").string!(1) }

    assert_match(%r{/a~1b/c~0d}, error.message)
  end

  test "#object! and #array! reject the wrong container and accept the right one" do
    assert_equal({ "a" => 1 }, ctx.object!({ "a" => 1 }))
    assert_equal([1], ctx.array!([1]))
    assert_raises(Dexpace::Serde::DeserializationError) { ctx.object!([]) }
    assert_raises(Dexpace::Serde::DeserializationError) { ctx.array!({}) }
  end

  test "#present! rejects nil and names the caller's target" do
    assert_equal(5, ctx.present!(5, "Pet"))

    error = assert_raises(Dexpace::Serde::DeserializationError) { ctx.present!(nil, "Pet") }

    assert_match(/Pet/, error.message)
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/serde/decode_context_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Serde::DecodeContext`.

- [ ] **Step 3: Write `lib/dexpace/serde/decode_context.rb`**

`Data.define(:path)`, `include Dexpace::Model`, `private_class_method :new`. `.root` memoizes one
frozen instance with an empty frozen path. `#at(segment)` returns
`self.class.__build(path: (path + [segment]).freeze)` — an internal builder, not public, because a
caller constructing an arbitrary path has no use for one. Every `!` method has the same two-line
shape:

```ruby
def string!(value, key: nil)
  return value if value.is_a?(::String)

  error!(expected: "String", actual: value, key: key)
end
```

`#float!` is the one exception and carries the `SERDE-22` comment at the widening branch:

```ruby
def float!(value, key: nil)
  # SERDE-22: numeric widening of an integer into a floating-point target is representation-
  # preserving and MUST be permitted, even though SERDE-21 forbids the reverse narrowing.
  return value.to_f if value.is_a?(::Integer) && !value.is_a?(::TrueClass)
  return value if value.is_a?(::Float)

  error!(expected: "Float", actual: value, key: key)
end
```

`#error!` is the one raise site:

```ruby
def error!(expected:, actual:, key: nil)
  at = key.nil? ? self : self.at(key)
  raise Dexpace::Serde::DeserializationError,
        "expected #{expected} at #{at.pointer}, got #{actual.class}"
end
```

`#pointer` renders RFC 6901: `""` for the root, otherwise `path.map { |s| "/" + s.to_s.gsub("~",
"~0").gsub("/", "~1") }.join`.

- [ ] **Step 4: Write the `sig/` mirror and run to confirm it passes**

```rbs
module Dexpace
  module Serde
    class DecodeContext
      include Dexpace::Model

      attr_reader path: Array[String | Integer]

      def self.root: () -> DecodeContext
      def at: (String | Integer segment) -> DecodeContext
      def pointer: () -> String
      def object!: (untyped value, ?key: (String | Integer)?) -> Hash[String, untyped]
      def array!: (untyped value, ?key: (String | Integer)?) -> Array[untyped]
      def string!: (untyped value, ?key: (String | Integer)?) -> String
      def integer!: (untyped value, ?key: (String | Integer)?) -> Integer
      def float!: (untyped value, ?key: (String | Integer)?) -> Float
      def boolean!: (untyped value, ?key: (String | Integer)?) -> bool
      def present!: (untyped value, String target, ?key: (String | Integer)?) -> untyped
      def error!: (expected: String, actual: untyped, ?key: (String | Integer)?) -> bot
    end
  end
end
```

Run the suite. Expected: PASS, 16 runs.

---

## Task 3: `Dexpace::Serde.witness!`, `.witness?`, `WITNESS_METHOD`, `DUMP_METHOD`

**Requirement IDs:** `SERDE-5`, `SERDE-7`, `SERDE-8`.
**Design:** "`R2` — the witness protocol's public surface".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/serde/witness.rb`,
  `gems/dexpace-core/sig/dexpace/serde/witness.rbs`
- Modify: `gems/dexpace-core/lib/dexpace/serde.rb` (the two module functions), `sig/dexpace/serde.rbs`
- Test: `gems/dexpace-core/test/dexpace/serde/witness_test.rb`

**Needs:** phase 1's `Dexpace::InvalidArgumentError`.
**Produces:** `Dexpace::Serde.witness!`, `.witness?`, `WITNESS_METHOD`, `DUMP_METHOD`, and the RBS
`interface _Witness`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# SERDE-5, SERDE-7, SERDE-8. Ruby erases nothing but reifies no element types, so the requirement is
# live and its mechanism (a reflective type token) is unavailable -- design §10.14 substitutes a
# class-object-and-combinator protocol. A witness is any object responding to .dexpace_load, which
# covers a model CLASS and a combinator INSTANCE with one predicate.
class DexpaceSerdeWitnessTest < DexpaceTestCase
  class Pet
    def self.dexpace_load(parsed, ctx) = new(ctx.object!(parsed))
    def initialize(hash) = @hash = hash
  end

  test "a class answering .dexpace_load is a witness" do
    assert(Dexpace::Serde.witness?(Pet))
    assert_same(Pet, Dexpace::Serde.witness!(Pet))
  end

  test "an ordinary object answering #dexpace_load is a witness too" do
    combinator = Object.new
    def combinator.dexpace_load(parsed, _ctx) = parsed

    assert(Dexpace::Serde.witness?(combinator))
  end

  # SERDE-8: reject construction with no type argument, failing fast with an actionable message.
  test "anything else is not a witness and witness! says what is missing" do
    refute(Dexpace::Serde.witness?(Object.new))
    refute(Dexpace::Serde.witness?(nil))
    refute(Dexpace::Serde.witness?("not a witness"))

    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Serde.witness!(nil) }

    assert_match(/dexpace_load/, error.message)
  end

  # SERDE-7: the ergonomic route IS the generic carrier. There is no raw-class path beside it to
  # forget to route through, because the class object is itself the witness.
  test "the ergonomic spelling and the carrier spelling are the same object" do
    assert_same(Pet, Dexpace::Serde.witness!(Pet))
  end

  test "the two protocol method names are public frozen symbols" do
    assert_equal(:dexpace_load, Dexpace::Serde::WITNESS_METHOD)
    assert_equal(:dexpace_dump, Dexpace::Serde::DUMP_METHOD)
    assert_predicate(Dexpace::Serde::WITNESS_METHOD, :frozen?)
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

Expected: FAIL — `NoMethodError: undefined method 'witness?' for module Dexpace::Serde`.

- [ ] **Step 3: Write the implementation**

```ruby
module Dexpace
  module Serde
    WITNESS_METHOD = :dexpace_load
    DUMP_METHOD    = :dexpace_dump

    class << self
      # A witness is any object responding to .dexpace_load(parsed, ctx). respond_to? and never a
      # nominal test, for the reason every seam here gives: a model class implements it as a class
      # method and a combinator instance as an instance method, and one predicate must cover both.
      def witness?(object) = object.respond_to?(WITNESS_METHOD)

      def witness!(object)
        return object if witness?(object)

        raise Dexpace::InvalidArgumentError,
              "witness must respond to ##{WITNESS_METHOD}, got #{object.class}"
      end
    end
  end
end
```

- [ ] **Step 4: Write the `sig/` mirror and run to confirm it passes**

`interface _Witness` with `def dexpace_load: (untyped parsed, Dexpace::Serde::DecodeContext ctx) ->
untyped`, plus the two module functions and the two constants on `module Dexpace::Serde`. Both
`parsed` and the return are `untyped`, because a witness's target type is the caller's and RBS is a
gate rather than a guarantee here (`serde/2f431a07`).

Run the suite. Expected: PASS, 5 runs.

---

## Task 4: `Dexpace::Serde::Tristate` — the value type

**Requirement IDs:** `SERDE-14`, `SERDE-18`, `SERDE-30`.
**Design:** "`Dexpace::Serde::Tristate` — `SERDE-14`–`SERDE-20`, `SERDE-30`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/serde/tristate.rb`,
  `gems/dexpace-core/sig/dexpace/serde/tristate.rbs`
- Test: `gems/dexpace-core/test/dexpace/serde/tristate_test.rb`

**Needs:** phase 1's `Dexpace::Model`, `Model.required!`, `Dexpace::InvalidArgumentError`.
**Produces:** `Tristate` the module, `ABSENT`, `NULL`, `Present`, the five module functions and the
six instance methods. `Tristate.of` is Task 6's.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# SERDE-14, SERDE-18, SERDE-30. Three states and no fourth: Present is bounded to non-null so
# Present-of-null is unrepresentable through the public API. The module is included by all three
# values, exactly Outcome's shape (4b) and Context's (4a), so v.is_a?(Tristate) is one type test.
class DexpaceSerdeTristateTest < DexpaceTestCase
  T = Dexpace::Serde::Tristate

  test "all three values share the module, so one type test covers them" do
    assert_kind_of(T, T::ABSENT)
    assert_kind_of(T, T::NULL)
    assert_kind_of(T, T.present(1))
  end

  # SERDE-14: the illegal fourth state, closed on the CONSTRUCTION path.
  test "SERDE-14: Present rejects nil at construction" do
    error = assert_raises(Dexpace::InvalidArgumentError) { T.present(nil) }

    assert_equal("value is required", error.message)
  end

  # SERDE-14: and closed on the DERIVATION path, which is the half a reader will not think to test.
  # Model#with routes through .build on every supported Ruby (data-modeling/83610619) -- Data#with
  # does NOT call an initialize override on 3.2, so without Model this would silently succeed there.
  test "SERDE-14: #with cannot derive a Present holding nil, on any supported Ruby" do
    assert_raises(Dexpace::InvalidArgumentError) { T.present(1).with(value: nil) }
  end

  test "SERDE-18: the three factories" do
    assert_same(T::ABSENT, T.absent)
    assert_same(T::NULL, T.null)
    assert_equal(1, T.present(1).value)
  end

  # SERDE-18's own conformance clause, quoted: "assert the nullable mapper yields Present for
  # non-null and Null for null". It can NEVER yield Absent, which is why it is a separate name from
  # Tristate.of -- the combinator.
  test "SERDE-18: from_nullable yields Present or Null and never Absent" do
    assert_predicate(T.from_nullable(1), :present?)
    assert_predicate(T.from_nullable(nil), :null?)
    refute_predicate(T.from_nullable(nil), :absent?)
  end

  test "SERDE-18: the three predicates are exhaustive and mutually exclusive" do
    [T::ABSENT, T::NULL, T.present(1)].each do |v|
      assert_equal(1, [v.absent?, v.null?, v.present?].count(true))
    end
  end

  test "SERDE-18: the three-way fold" do
    fold = ->(v) { v.fold(on_absent: -> { :a }, on_null: -> { :n }, on_present: ->(x) { x }) }

    assert_equal(:a, fold.call(T::ABSENT))
    assert_equal(:n, fold.call(T::NULL))
    assert_equal(7, fold.call(T.present(7)))
  end

  test "SERDE-18: the value-or-null accessor" do
    assert_nil(T::ABSENT.value_or_nil)
    assert_nil(T::NULL.value_or_nil)
    assert_equal(7, T.present(7).value_or_nil)
  end

  # SERDE-30 (MAY, taken). Ruby's default #inspect for a singleton renders its object id, so a log
  # line or a test failure comparing tristates would otherwise differ between runs. Asserted as
  # string equality, not as refute_match(/0x/), because the requirement names the forms.
  test "SERDE-30: the sentinels have stable identity-free textual forms" do
    assert_equal("Absent", T::ABSENT.to_s)
    assert_equal("Absent", T::ABSENT.inspect)
    assert_equal("Null", T::NULL.to_s)
    assert_equal("Null", T::NULL.inspect)
  end

  test "the sentinels are frozen singletons" do
    assert_predicate(T::ABSENT, :frozen?)
    assert_same(T::ABSENT, T.absent)
    refute_equal(T::ABSENT, T::NULL)
  end

  test "Present compares by value and is frozen" do
    assert_equal(T.present(1), T.present(1))
    assert_predicate(T.present(1), :frozen?)
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

Expected: FAIL — `uninitialized constant Dexpace::Serde::Tristate`.

- [ ] **Step 3: Write `lib/dexpace/serde/tristate.rb`**

The module carries the six instance methods and the five module functions. `Present =
Data.define(:value)` includes `Dexpace::Model` **and** `Tristate`, with `private_class_method :new`
and a `.build(value:)` calling `Model.required!(:value, value)`; `T.present(v)` forwards to it, which
is what gives `SERDE-14`'s exact `"value is required"` message. `ABSENT` and `NULL` are frozen
instances of two `private_constant` singleton classes that include `Tristate` and define `#to_s` and
`#inspect`. `#dexpace_dump` returns `Dexpace::Serde::OMIT` for Absent, `nil` for Null, and the
Present value's own dump — Task 7 defines `OMIT`, so this method is written in Task 7 and the file
carries a forward comment here.

- [ ] **Step 4: Write the `sig/` mirror and run to confirm it passes**

Declare `module Tristate` with the six instance methods, `class Present` including both modules, and
`ABSENT: Tristate` / `NULL: Tristate` as constants. The `Data`-generated `#value` reader is public
API invisible to `rbs validate`, so it is declared explicitly here and Task 18 regenerates the
runtime surface snapshot that also holds it.

Run the suite. Expected: PASS, 11 runs.

---

## Task 5: The scalar witnesses and `List`, `Map`, `Nullable`

**Requirement IDs:** `SERDE-6`, `SERDE-8`, `SERDE-23`.
**Design:** "`Dexpace::Serde::List`, `Map`, `Nullable` — `SERDE-6`"; open question 1.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/serde/scalars.rb` (`private_constant` table plus
  `Dexpace::Serde::BOOLEAN`), `lib/dexpace/serde/list.rb`, `map.rb`, `nullable.rb`, and their four
  `sig/` mirrors
- Test: `gems/dexpace-core/test/dexpace/serde/combinators_test.rb`

**Needs:** Tasks 2 and 3.
**Produces:** `List.of`, `Map.of`, `Nullable.of`, `BOOLEAN`, and the scalar resolution that makes
`List.of(String)` work.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# SERDE-6, SERDE-8, SERDE-23. Parametric targets are covered by combinators that are themselves
# witnesses, each built BY VALUE from a concrete element witness -- so a parametric target is stated
# once, as data, with no reflective reconstruction anywhere.
class DexpaceSerdeCombinatorsTest < DexpaceTestCase
  S = Dexpace::Serde

  class Pet
    attr_reader :name

    def self.dexpace_load(parsed, ctx)
      h = ctx.object!(parsed)
      new(ctx.string!(h["name"], key: "name"))
    end

    def initialize(name) = @name = name
  end

  def ctx = S::DecodeContext.root

  # SERDE-5's own conformance clause: "decode a JSON object into a concrete DTO via the type-witness
  # path; assert the result is the real DTO type and field access returns typed values".
  test "SERDE-6: a list of a DTO decodes to real DTOs with typed field access" do
    pets = S::List.of(Pet).dexpace_load([{ "name" => "Ré" }, { "name" => "b" }], ctx)

    assert_equal([Pet, Pet], pets.map(&:class))
    assert_equal("Ré", pets.first.name)
  end

  test "SERDE-6: a map keyed by String and valued by a DTO" do
    map = S::Map.of(String, Pet).dexpace_load({ "a" => { "name" => "x" } }, ctx)

    assert_instance_of(Pet, map["a"])
  end

  test "SERDE-6: Nullable accepts nil where the element witness would not" do
    assert_nil(S::Nullable.of(Pet).dexpace_load(nil, ctx))
    assert_instance_of(Pet, S::Nullable.of(Pet).dexpace_load({ "name" => "x" }, ctx))
    assert_raises(Dexpace::Serde::DeserializationError) { Pet.dexpace_load(nil, ctx) }
  end

  test "the ergonomic scalar spellings design §7.3 uses work verbatim" do
    assert_equal(%w[a b], S::List.of(String).dexpace_load(%w[a b], ctx))
    assert_equal([1, 2], S::List.of(Integer).dexpace_load([1, 2], ctx))
    assert_equal([1.0], S::List.of(Float).dexpace_load([1], ctx))          # SERDE-22 widening
    assert_equal([true], S::List.of(S::BOOLEAN).dexpace_load([true], ctx))
  end

  # SERDE-8: reject construction with no type argument or an unresolved one, failing FAST -- at
  # witness construction, not deep inside a parse. The "unresolved type variable" state is
  # unreachable by construction (serde/ffc92673) and is stated in the YARD, not emulated.
  test "SERDE-8: a combinator cannot be built from a non-witness" do
    assert_raises(Dexpace::InvalidArgumentError) { S::List.of(nil) }
    assert_raises(Dexpace::InvalidArgumentError) { S::List.of(Object.new) }
    assert_raises(Dexpace::InvalidArgumentError) { S::Map.of(String, nil) }
    assert_raises(Dexpace::InvalidArgumentError) { S::Nullable.of(Object.new) }
  end

  test "a combinator is itself a witness, so combinators nest" do
    nested = S::List.of(S::List.of(String))

    assert(S.witness?(nested))
    assert_equal([%w[a]], nested.dexpace_load([%w[a]], ctx))
  end

  test "a combinator is a frozen value with structural equality" do
    assert_equal(S::List.of(Pet), S::List.of(Pet))
    assert_predicate(S::List.of(Pet), :frozen?)
  end

  # SERDE-23 (SHOULD, implemented as the witness's default): a witness reads the keys it declares
  # and ignores the rest, so a backward-compatible server addition does not break a deployed client.
  test "SERDE-23: an unknown field is ignored rather than failing" do
    pet = Pet.dexpace_load({ "name" => "x", "added_next_year" => 1 }, ctx)

    assert_equal("x", pet.name)
  end

  test "the element error names the element's own path, not the container's" do
    error = assert_raises(Dexpace::Serde::DeserializationError) do
      S::List.of(Pet).dexpace_load([{ "name" => 1 }], ctx)
    end

    assert_match(%r{/0/name}, error.message)
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

Expected: FAIL — `uninitialized constant Dexpace::Serde::List`.

- [ ] **Step 3: Write the four files**

`Scalars::TABLE` is a frozen `private_constant` `Hash` mapping `::String`, `::Integer` and `::Float`
to three frozen singleton witnesses, plus `BOOLEAN` as a **named public constant** rather than two
class keys (open question 1). `Scalars.resolve(w)` returns `TABLE.fetch(w) { Dexpace::Serde.witness!(w) }`,
which is the one place the ergonomic spelling and the protocol meet.

Each combinator is `Data.define(:element)` (or `:key, :value`), `include Dexpace::Model`,
`private_class_method :new`, with `.of` running `Scalars.resolve` on every argument so the failure is
at **construction**. `#dexpace_load` walks with `ctx.at(index_or_key)` for each element, which is what
makes the element error name the element's path.

- [ ] **Step 4: Write the four `sig/` mirrors and run to confirm it passes**

Run the suite. Expected: PASS, 9 runs.

---

## Task 6: `Tristate.of` and `#dexpace_load_field`

**Requirement IDs:** `SERDE-16`, `SERDE-17`.
**Design:** "`Dexpace::Serde::Tristate`"; `P7-3`'s second named method.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/serde/tristate.rb`, `sig/dexpace/serde/tristate.rbs`
- Test: `gems/dexpace-core/test/dexpace/serde/tristate_decode_test.rb`

**Needs:** Tasks 2, 3, 4.
**Produces:** `Tristate.of(element)`, its `#dexpace_load(parsed, ctx)` and its
`#dexpace_load_field(hash, key, ctx)`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# SERDE-16 and SERDE-17. The asymmetry SERDE-17 documents does not bite in Ruby: JSON.parse yields
# an ordinary Hash and hash.key?("x") distinguishes an absent key from a present null directly
# (serde/5fe8e3ed, verified), so the witness decides per key with full knowledge of the enclosing
# model's shape. There is no field-default machinery and none is emulated.
#
# TWO entry points, and the reason is measurable: #dexpace_load_field needs the ENCLOSING Hash to
# ask key?, while the protocol's #dexpace_load sees only the value and cannot. The second is
# SERDE-20's top-level case.
class DexpaceSerdeTristateDecodeTest < DexpaceTestCase
  S = Dexpace::Serde
  T = S::Tristate

  def ctx = S::DecodeContext.root

  # SERDE-16's own conformance clause: decode {}, {"x":null}, {"x":value}.
  test "SERDE-16/SERDE-17: a missing key is Absent, an explicit null is Null, a value is Present" do
    w = T.of(String)

    assert_predicate(w.dexpace_load_field({}, "x", ctx), :absent?)
    assert_predicate(w.dexpace_load_field({ "x" => nil }, "x", ctx), :null?)
    assert_equal("v", w.dexpace_load_field({ "x" => "v" }, "x", ctx).value)
  end

  # SERDE-17's conformance clause names the trap by name: "assert Absent, NOT Null".
  test "SERDE-17: an omitted field is Absent and never Null" do
    result = T.of(String).dexpace_load_field({}, "x", ctx)

    assert_predicate(result, :absent?)
    refute_predicate(result, :null?)
  end

  test "SERDE-16: the inner value's declared element type is preserved" do
    assert_instance_of(::Float, T.of(Float).dexpace_load_field({ "x" => 1 }, "x", ctx).value)
    assert_raises(Dexpace::Serde::DeserializationError) do
      T.of(Integer).dexpace_load_field({ "x" => "5" }, "x", ctx)
    end
  end

  # SERDE-20's decode half: "deserialize a top-level null -> Null".
  test "SERDE-20: a top-level null decodes to Null through the protocol entry point" do
    assert_predicate(T.of(String).dexpace_load(nil, ctx), :null?)
    assert_equal("v", T.of(String).dexpace_load("v", ctx).value)
  end

  test "SERDE-8: Tristate.of rejects a non-witness like every other combinator" do
    assert_raises(Dexpace::InvalidArgumentError) { T.of(Object.new) }
  end

  test "Tristate.of and Tristate.from_nullable are different things with different names" do
    assert(S.witness?(T.of(String)))
    refute(S.witness?(T.from_nullable("v")))
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

Expected: FAIL — `NoMethodError: undefined method 'of' for module Dexpace::Serde::Tristate`.

- [ ] **Step 3: Implement**

`Tristate.of(element)` returns a frozen `Tristate::Combinator` (a `private_constant`
`Data.define(:element)`), whose `#dexpace_load_field(hash, key, ctx)` is three lines because of
`Hash#key?`, and whose `#dexpace_load(parsed, ctx)` is `SERDE-20`'s top-level branch. The
`private_constant` combinator carries no `sig/` of its own; `Tristate.of`'s **return type** is
declared as the `_Witness` interface, which is what a caller can use and all a caller needs.

- [ ] **Step 4: Run to confirm it passes**

Expected: PASS, 6 runs. Re-run Task 4's suite to confirm it is unaffected.

---

## Task 7: `Dexpace::Serde::Native` and `Dexpace::Serde::OMIT`

**Requirement IDs:** `SERDE-15`, `SERDE-19`, `SERDE-20`.
**Design:** "`Dexpace::Serde::Native` and `Dexpace::Serde::OMIT`"; `P7-9`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/serde/native.rb`, `sig/dexpace/serde/native.rbs`
- Modify: `gems/dexpace-core/lib/dexpace/serde/tristate.rb` (its `#dexpace_dump`)
- Test: `gems/dexpace-core/test/dexpace/serde/native_test.rb`

**Needs:** Task 4.
**Produces:** `Native.of(value, encoders:)` and `OMIT`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# SERDE-15, SERDE-19, SERDE-20 (P7-9). Design §7.3 puts the Absent-key omission in each model's own
# #dexpace_dump; the port puts it in this walk instead, because SERDE-19 is a MUST whose named
# failure -- "absent this wiring, Absent and Null become indistinguishable on the wire" -- is exactly
# what a per-model convention produces when one model forgets. In the walk it is structural, which
# is the word §7.3 itself uses for what SERDE-19 needs.
class DexpaceSerdeNativeTest < DexpaceTestCase
  S = Dexpace::Serde
  T = S::Tristate

  class Patch
    def initialize(**h) = @h = h
    def dexpace_dump = { "name" => @h[:name], "nick" => @h[:nick] }
  end

  test "native scalars pass through" do
    assert_nil(S::Native.of(nil))
    assert_equal([true, false, 1, 1.5, "é"], S::Native.of([true, false, 1, 1.5, "é"]))
  end

  test "anything answering #dexpace_dump is replaced and re-walked" do
    assert_equal({ "name" => "x", "nick" => nil },
                 S::Native.of(Patch.new(name: "x", nick: T::NULL)))
  end

  # SERDE-15: Absent MUST omit the key entirely; Null MUST emit the key with a wire null; Present
  # MUST emit the key with the encoded inner value.
  test "SERDE-15: Absent omits the key, Null emits a null, Present emits the value" do
    assert_equal({ "name" => "x" }, S::Native.of(Patch.new(name: "x", nick: T::ABSENT)))
    assert_equal({ "name" => "x", "nick" => nil }, S::Native.of(Patch.new(name: "x", nick: T::NULL)))
    assert_equal({ "name" => "x", "nick" => "n" },
                 S::Native.of(Patch.new(name: "x", nick: T.present("n"))))
  end

  # SERDE-20: degrade gracefully where no enclosing object can omit a key.
  test "SERDE-20: a top-level Absent and Null both render null rather than throwing" do
    assert_nil(S::Native.of(T::ABSENT))
    assert_nil(S::Native.of(T::NULL))
  end

  test "SERDE-20: an array element Absent becomes null rather than being dropped" do
    assert_equal([nil, nil, "v"], S::Native.of([T::ABSENT, T::NULL, T.present("v")]))
  end

  # Verified fact 2 is why this test exists: ::JSON.generate(Object.new) returns
  # "\"#<Object:0x…>\"" rather than raising, so SERDE-9/SERDE-10's "an unserializable value throws
  # the serialization subtype" is a requirement the generator alone silently fails.
  test "an unserializable value raises SerializationError NAMING THE CLASS" do
    error = assert_raises(Dexpace::Serde::SerializationError) { S::Native.of(Object.new) }

    assert_match(/Object/, error.message)
  end

  test "a non-stringable Hash key raises rather than being coerced silently" do
    assert_raises(Dexpace::Serde::SerializationError) { S::Native.of({ Object.new => 1 }) }
  end

  test "the encoders table is the ONE hook, and core ships it empty" do
    walked = S::Native.of(::Time.utc(2026, 9, 10), encoders: { ::Time => ->(t) { t.iso8601 } })

    assert_equal("2026-09-10T00:00:00Z", walked)
    assert_raises(Dexpace::Serde::SerializationError) { S::Native.of(::Time.utc(2026, 9, 10)) }
  end

  test "the walk returns fresh collections and never aliases the caller's" do
    source = { "a" => [1] }

    refute_same(source, S::Native.of(source))
    refute_same(source["a"], S::Native.of(source)["a"])
  end

  test "OMIT is a frozen sentinel with a stable textual form" do
    assert_predicate(S::OMIT, :frozen?)
    assert_equal("Omit", S::OMIT.to_s)
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

Expected: FAIL — `uninitialized constant Dexpace::Serde::Native`.

- [ ] **Step 3: Write `lib/dexpace/serde/native.rb`**

`OMIT` is a frozen singleton with `#to_s`/`#inspect` overridden, for the same reason `SERDE-30` gives
for `ABSENT` and `NULL`. `Native.of(value, encoders: {})` dispatches through the design's seven rules
**in order**, with the `top_level:` distinction carried as a private recursion argument so
`SERDE-20`'s three degradations (`Hash` drop, `Array` `nil`, top-level `nil`) are three branches in
one method rather than three call sites.

- [ ] **Step 4: Give `Tristate` its `#dexpace_dump` and run both suites**

`ABSENT#dexpace_dump` returns `OMIT`, `NULL#dexpace_dump` returns `nil`, and `Present#dexpace_dump`
returns `value` (the walk re-walks it, so a nested model or a nested `Tristate` is handled by the
same recursion).

Run: the new suite and Task 4's. Expected: both PASS.

---

## Task 8: `Dexpace::Serde::Instant`

**Requirement IDs:** `SERDE-24`.
**Design:** "`Dexpace::Serde::Instant` — `SERDE-24`'s decode half (`P7-8`)"; verified fact 8.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/serde/instant.rb`, `sig/dexpace/serde/instant.rbs`
- Test: `gems/dexpace-core/test/dexpace/serde/instant_test.rb`

**Needs:** Task 2. `require "time"` — already on core's allowlist.
**Produces:** `Instant.dexpace_load` and `Instant.dexpace_dump`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# SERDE-24. "Whichever form is chosen, the encoding MUST round-trip to the same instant" -- and
# Time#iso8601(n) TRUNCATES rather than rounding, verified, so the guarantee holds over a stated
# precision domain and the port says which. P7-8.
#
# Dexpace/NoTimeParse bans Time.parse, Date.parse and DateTime.parse. Time.iso8601 and Time#iso8601
# are `time`'s and are not what the cop bans (verified).
class DexpaceSerdeInstantTest < DexpaceTestCase
  S = Dexpace::Serde

  def ctx = S::DecodeContext.root

  test "SERDE-24: an ISO-8601 string, not an epoch number" do
    assert_equal("2026-09-10T12:00:00.000000Z", S::Instant.dexpace_dump(::Time.utc(2026, 9, 10, 12)))
  end

  # SERDE-24's own conformance clause: serialize an instant -> ISO-8601 string, deserialize ->
  # equality with the original.
  test "SERDE-24: whole seconds round-trip exactly" do
    t = ::Time.utc(2026, 9, 10, 12, 0, 0)

    assert_equal(t, S::Instant.dexpace_load(S::Instant.dexpace_dump(t), ctx))
  end

  test "SERDE-24: exact microseconds round-trip exactly -- the stated domain" do
    t = ::Time.at(1_757_505_600, 123_456, :usec).utc

    assert_equal(t, S::Instant.dexpace_load(S::Instant.dexpace_dump(t), ctx))
  end

  test "SERDE-24: a UTC offset survives the round trip" do
    t = ::Time.new(2026, 9, 10, 12, 0, 0, "+02:00")
    back = S::Instant.dexpace_load(S::Instant.dexpace_dump(t), ctx)

    assert_equal(t, back)
    assert_equal(7200, back.utc_offset)
  end

  # P7-8, executable rather than prose: OUTSIDE the domain the encoding truncates and the round trip
  # is lossy. Asserting it is what keeps the YARD caveat honest.
  test "P7-8: a Float-second Time truncates and does NOT round-trip" do
    t = ::Time.new(2026, 9, 10, 12, 0, 0.123456, "+02:00")

    assert_equal("2026-09-10T12:00:00.123455+02:00", S::Instant.dexpace_dump(t))
    refute_equal(t, S::Instant.dexpace_load(S::Instant.dexpace_dump(t), ctx))
  end

  test "a non-string, a malformed string and a lax form each raise naming Time" do
    [5, "not a time", "", "2026-09-10", "2026-09-10 12:00:00"].each do |bad|
      error = assert_raises(Dexpace::Serde::DeserializationError) { S::Instant.dexpace_load(bad, ctx) }

      assert_match(/Time/, error.message)
    end
  end

  test "Instant is a witness and nests in a combinator" do
    assert(S.witness?(S::Instant))
    assert_equal([::Time.utc(2026, 9, 10)],
                 S::List.of(S::Instant).dexpace_load(["2026-09-10T00:00:00.000000Z"], ctx))
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

Expected: FAIL — `uninitialized constant Dexpace::Serde::Instant`.

- [ ] **Step 3: Write `lib/dexpace/serde/instant.rb`**

A module with two module functions. `.dexpace_dump(time)` is `time.iso8601(6)`.
`.dexpace_load(parsed, ctx)` calls `ctx.string!(parsed)` then `::Time.iso8601`, rescuing
`::ArgumentError` and calling `ctx.error!(expected: "Time", actual: parsed)`. The YARD block carries
`P7-8`'s domain statement with the measured example, and it is the only place in this plan a
requirement's guarantee is qualified.

- [ ] **Step 4: Write the `sig/` mirror and run to confirm it passes**

`::Time` is the one foreign constant in core's serde `sig/` and it is on `NFR-11`'s stdlib allowlist.

Run the suite. Expected: PASS, 7 runs.

---

## Task 9: `Dexpace::Body.serialized`

**Requirement IDs:** `SERDE-2`.
**Design:** "`Dexpace::Body.serialized(value, serde:)` — `SERDE-2`"; `R3`'s coercion paragraph.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace/http/body.rb`, `sig/dexpace/http/body.rbs`
- Test: `gems/dexpace-core/test/dexpace/http/body_serialized_test.rb`

**Needs:** phase 3b's `BytesBody`, phase 1's `MediaType`, phase 2's `FakeCodec`.
**Produces:** the ninth factory.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_codec"

# SERDE-2, whose own conformance clause is: "build a body via create(value, serde) with no explicit
# media type; assert the Content-Type equals the serde's declared media type." A ninth factory beside
# phase 3b's eight; adding one WIDENS, which NFR-4's "disappears or narrows" lock permits.
class DexpaceBodySerializedTest < DexpaceTestCase
  test "SERDE-2: the body's media type is the serde's declared one" do
    body = Dexpace::Body.serialized(:payload, serde: FakeCodec.new)

    assert_equal(Dexpace::MediaType.parse("application/vnd.dexpace.fake"), body.media_type)
  end

  test "SERDE-2: there is no format-agnostic default to fall back to" do
    forgetful = Class.new(FakeCodec) { def media_type = nil }.new

    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Body.serialized(:payload, serde: forgetful)
    end

    assert_match(/media type/, error.message)
    refute_match(%r{application/octet-stream}, error.message)
  end

  test "a MediaType-returning codec passes through and a String is coerced" do
    stringy = FakeCodec.new
    typed = Class.new(FakeCodec) do
      def media_type = Dexpace::MediaType.parse("application/json")
    end.new

    assert_instance_of(Dexpace::MediaType, Dexpace::Body.serialized(:v, serde: stringy).media_type)
    assert_equal(Dexpace::MediaType.parse("application/json"),
                 Dexpace::Body.serialized(:v, serde: typed).media_type)
  end

  test "the bytes are the serde's dump_bytes and the body is replayable with an exact length" do
    codec = FakeCodec.new
    body = Dexpace::Body.serialized(:payload, serde: codec)
    sink = StringIO.new(+"".b)

    assert_predicate(body, :replayable?)
    assert_equal(codec.dump_bytes(:payload).bytesize, body.content_length)
    body.write_to(sink)
    body.write_to(sink)                       # replayable means byte-for-byte identical, twice
    assert_equal(codec.dump_bytes(:payload) * 2, sink.string)
  end

  test "a missing value or serde fails with SEAM-29's message form" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.serialized(:v, serde: nil) }

    assert_equal("serde is required", error.message)
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

Expected: FAIL — `NoMethodError: undefined method 'serialized' for module Dexpace::Body`.

- [ ] **Step 3: Implement**

```ruby
def self.serialized(value, serde:)
  Dexpace::Model.required!(:serde, serde)
  declared = serde.media_type
  # SERDE-2: "MUST NOT be defaulted to a format-agnostic constant at the SPI level" -- so there is
  # no fallback to fall back to. Phase 2 enforces the presence at .conforms?; this is the same rule
  # at the one call site that consumes the value.
  raise Dexpace::InvalidArgumentError, "#{serde.class} declared no media type" if blank?(declared)

  bytes(serde.dump_bytes(value),
        media_type: declared.is_a?(Dexpace::MediaType) ? declared : Dexpace::MediaType.parse(declared))
end
```

- [ ] **Step 4: Update the `sig/` and run both the new suite and phase 3b's body suite**

Expected: PASS, and 3b's suite unaffected — the eight existing factories are untouched.

---

## Task 10: `Dexpace::Serde::DecodingHandler`

**Requirement IDs:** `SERDE-27`.
**Design:** "`R3` — `DecodingHandler`"; `R1`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/serde/decoding_handler.rb`,
  `sig/dexpace/serde/decoding_handler.rbs`
- Test: `gems/dexpace-core/test/dexpace/serde/decoding_handler_test.rb`

**Needs:** Task 3; phase 3b's `TypedResponse`, `Response`, `ResponseBody`; Task 1's
`CountingResponse`; phase 2's `FakeCodec`.
**Produces:** `DecodingHandler.build(serde:, witness:)`, `#call(response)`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_codec"
require_relative "../../support/counting_response"

# SERDE-27, whose conformance clause is a five-case matrix and gets five tests: "handle a valid body
# -> typed value plus one close; a bodyless response -> serde exception naming the target; malformed
# content -> serde exception with a non-null cause; a mid-stream I/O error -> propagates unwrapped;
# the response closes in every case."
#
# FakeCodec, never Dexpace::Serde::JSON -- SEAM-2, and Task 1's negative test enforces it.
class DexpaceSerdeDecodingHandlerTest < DexpaceTestCase
  S = Dexpace::Serde

  def handler(serde: FakeCodec.new, witness: ->(text) { text.upcase })
    S::DecodingHandler.build(serde: serde, witness: witness)
  end

  test "SERDE-27: a valid body decodes to the typed value and closes the response exactly once" do
    response = CountingResponse.with_body("héllo")

    assert_equal("HÉLLO", handler.call(response))
    assert_equal(1, response.close_count)
  end

  # SERDE-27: "MUST surface a missing body (e.g. 204) as a serde exception NAMING THE TARGET TYPE".
  # A zero-length body is treated the same way, because a caller cannot distinguish them and
  # ::JSON.parse("")'s own ParserError names nothing useful (this plan's open question 3).
  test "SERDE-27: a bodyless response raises naming the target, and still closes" do
    response = CountingResponse.bodyless

    error = assert_raises(Dexpace::Serde::DeserializationError) { handler(witness: PetWitness).call(response) }

    assert_match(/PetWitness/, error.message)
    assert_equal(1, response.close_count)
  end

  test "SERDE-27: an empty body raises the same target-naming error" do
    response = CountingResponse.with_body("")

    assert_raises(Dexpace::Serde::DeserializationError) { handler(witness: PetWitness).call(response) }
    assert_equal(1, response.close_count)
  end

  test "SERDE-27: a codec failure surfaces as a serde exception with a NON-NIL cause" do
    exploding = Class.new(FakeCodec) do
      def load(_source, _witness)
        raise ::RuntimeError, "the backing library said no"
      rescue ::RuntimeError
        raise Dexpace::Serde::DeserializationError, "decode failed"
      end
    end.new
    response = CountingResponse.with_body("x")

    error = assert_raises(Dexpace::Serde::DeserializationError) { handler(serde: exploding).call(response) }

    refute_nil(error.cause)
    assert_equal(1, response.close_count)
  end

  # SERDE-27's last clause and SERDE-12's, from the handler's side: a genuine mid-stream I/O error
  # propagates UNWRAPPED. Dexpace::StreamError is an ::IOError and no rescue in this path catches it.
  test "SERDE-27: a mid-stream I/O error propagates unwrapped, and the response still closes" do
    failing = Class.new(FakeCodec) do
      def load(_source, _witness) = raise Dexpace::StreamError, "connection reset"
    end.new
    response = CountingResponse.with_body("x")

    assert_raises(Dexpace::StreamError) { handler(serde: failing).call(response) }
    assert_equal(1, response.close_count)
  end

  # The clause that reads like a contradiction and is not: SERDE-3 binds the CODEC and its subject is
  # the caller's STREAM; SERDE-27 binds the HANDLER and its subject is the RESPONSE. Two rules, two
  # subjects. This test asserts both hold at once.
  test "the handler closes the response and the codec closes nothing" do
    response = CountingResponse.with_body("x")

    handler.call(response)

    assert_equal(1, response.close_count)
    assert_equal(0, response.body_close_count_from_codec)
  end

  test "the handler is a _ResponseHandler, so TypedResponse takes it and runs it exactly once" do
    calls = 0
    counting = ->(_response) { calls += 1; :value }
    typed = Dexpace::TypedResponse.new(response: CountingResponse.with_body("x"), handler: counting)

    3.times { assert_equal(:value, typed.value) }

    assert_equal(1, calls)
  end

  test "a memoized failure is re-raised as the SAME object, so its cause survives" do
    typed = Dexpace::TypedResponse.new(response: CountingResponse.with_body(""),
                                       handler: handler(witness: PetWitness))
    first = assert_raises(Dexpace::Serde::DeserializationError) { typed.value }
    second = assert_raises(Dexpace::Serde::DeserializationError) { typed.value }

    assert_same(first, second)
  end

  test "a non-witness fails at handler construction, not at first body access" do
    assert_raises(Dexpace::InvalidArgumentError) { S::DecodingHandler.build(serde: FakeCodec.new, witness: 5) }
  end
end
```

`PetWitness` is a two-line named witness class in the test file, so `SERDE-27`'s "naming the target
type" is asserted against a name a reader can see.

- [ ] **Step 2: Run to confirm it fails**

Expected: FAIL — `uninitialized constant Dexpace::Serde::DecodingHandler`.

- [ ] **Step 3: Implement**

`Data.define(:serde, :witness)`, `include Dexpace::Model`, `private_class_method :new`, `.build`
running `Model.required!` on both and `Dexpace::Serde.witness!` on the witness. `#call(response)` is
the design's eight lines, with the `ensure` unguarded and the `SERDE-3`-versus-`SERDE-27` comment at
the `ensure`.

The "empty body" check is the handler's (open question 3): `body.nil? || body.content_length.zero?`,
and additionally a `rescue` converting a codec-side end-of-input `DeserializationError` whose
`#cause` is a parse error over empty input into the same target-naming message — because
`content_length` is `-1` when unknown and a chunked empty body reaches the codec.

- [ ] **Step 4: Write the `sig/` mirror and run to confirm it passes**

`def call: (Dexpace::Response response) -> untyped`, which is `Dexpace::_ResponseHandler`'s shape
exactly. Expected: PASS, 9 runs.

---

## Task 11: `Dexpace::Serde::StatusAwareHandler`

**Requirement IDs:** `SERDE-28`.
**Design:** "`R3` — `StatusAwareHandler`".

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/serde/status_aware_handler.rb`,
  `sig/dexpace/serde/status_aware_handler.rbs`
- Test: `gems/dexpace-core/test/dexpace/serde/status_aware_handler_test.rb`

**Needs:** Task 10; phase 4b's `Recovery.buffer_error_body` and `ProtocolError`.
**Produces:** `StatusAwareHandler.build(serde:, witness:, factory:)`, `#call(response)`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_codec"
require_relative "../../support/counting_response"

# SERDE-28. Its conformance clause names four cases and one of them is a trap: "2xx -> decode; 500
# (AND A NON-CANONICAL 599) -> the mapped exception with the status code and a readable buffered
# error body; 304 -> serde exception naming the status plus one close." 599 is a 5xx and therefore
# the SECOND branch; a reader skimming "non-canonical" will file it under the third.
class DexpaceSerdeStatusAwareHandlerTest < DexpaceTestCase
  S = Dexpace::Serde

  def handler(factory: nil)
    kwargs = { serde: FakeCodec.new, witness: ->(text) { text.upcase } }
    kwargs[:factory] = factory unless factory.nil?
    S::StatusAwareHandler.build(**kwargs)
  end

  test "SERDE-28: a 2xx decodes through the SAME implementation as the plain handler" do
    assert_equal("HÉLLO", handler.call(CountingResponse.with_body("héllo", status: 200)))
  end

  test "SERDE-28: a 4xx/5xx raises the mapped exception and never decodes the error payload" do
    [400, 404, 500, 599].each do |code|
      response = CountingResponse.with_body("boom", status: code)

      error = assert_raises(Dexpace::ProtocolError) { handler.call(response) }

      assert_equal(code, error.status.code)
    end
  end

  # "carrying a bounded, buffered in-memory copy of the error body (so the error body is readable
  # AFTER the live response closes)" -- and BODY-30's own words are "decode it, then snapshot it",
  # which is why BufferBody#source hands out a fresh peek view per call (P3-23).
  test "SERDE-28: the error body is readable twice after the live response is gone" do
    error = assert_raises(Dexpace::ProtocolError) { handler.call(CountingResponse.with_body("boom", status: 500)) }

    assert_equal("boom", error.response.body_string)
    assert_equal("boom", error.response.body_string)
  end

  test "SERDE-28: the factory keyword substitutes a generated SDK's typed error" do
    typed = Class.new(::StandardError)
    called = 0
    factory = ->(response) { called += 1; typed.new("status #{response.status.code}") }

    assert_raises(typed) { handler(factory: factory).call(CountingResponse.with_body("b", status: 503)) }
    assert_equal(1, called)
  end

  # The third branch. Its message MUST lead with the status code and preserve conditional/redirect
  # context -- by COPYING the raw header values, never by parsing them: running a malformed server
  # ETag through HTTP-48's validating helper inside an error path turns a diagnostic into a second
  # failure (the charter's DEF-2 argument, honoured).
  test "SERDE-28: a 304 closes and raises a serde exception leading with the code" do
    response = CountingResponse.with_body("", status: 304,
                                          headers: { "etag" => '"abc"', "location" => "/x" })

    error = assert_raises(Dexpace::Serde::DeserializationError) { handler.call(response) }

    assert_match(/\A304\b/, error.message)
    assert_match(/"abc"/, error.message)
    assert_match(%r{/x}, error.message)
    assert_equal(1, response.close_count)
  end

  test "SERDE-28: a malformed ETag reaches the message verbatim rather than raising a second time" do
    response = CountingResponse.with_body("", status: 304, headers: { "etag" => 'W/"unterminated' })

    error = assert_raises(Dexpace::Serde::DeserializationError) { handler.call(response) }

    assert_match(/unterminated/, error.message)
  end

  test "SERDE-28: a 1xx takes the third branch too" do
    assert_raises(Dexpace::Serde::DeserializationError) { handler.call(CountingResponse.with_body("", status: 100)) }
  end

  # RECOV-16's buffering already released the original in an ensure, so this branch must NOT close
  # again -- a second close would be a double close of an object Body.buffer_bounded released.
  test "the 4xx/5xx branch adds no second close of its own" do
    response = CountingResponse.with_body("boom", status: 500)

    assert_raises(Dexpace::ProtocolError) { handler.call(response) }
    assert_equal(1, response.close_count)
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

Expected: FAIL — `uninitialized constant Dexpace::Serde::StatusAwareHandler`.

- [ ] **Step 3: Implement**

`Data.define(:decoding, :factory)`, with `.build(serde:, witness:, factory:
Dexpace::ProtocolError.method(:for))` constructing a `DecodingHandler` internally — so `SERDE-27`'s
five clauses have exactly one implementation. `#call` is the three-branch dispatch, with the
`ProtocolError.for`-not-`.for_or_nil` comment at the second branch and the copy-don't-parse comment
at the third. The third branch reads `response.headers["etag"]` and `["location"]` through phase 1's
case-folded `Headers#[]` and interpolates the raw values.

- [ ] **Step 4: Write the `sig/` mirror and run to confirm it passes**

Expected: PASS, 8 runs. Re-run Task 10's suite.

---

## Task 12: `interface _Codec`'s body, and core's `sig/` and `require` wiring

**Requirement IDs:** none new (`NFR-3`, `NFR-11`; the finding under `docs/open-items.md`).
**Design:** "The `sig/` shape"; `R3`'s coercion paragraph.

**Files:**
- Modify: `gems/dexpace-core/sig/dexpace/serde.rbs`, `gems/dexpace-core/lib/dexpace.rb`,
  `gems/dexpace-core/sig/dexpace.rbs`
- Test: the existing `gems/dexpace-core/test/dexpace_test.rb` constant-tree assertion

- [ ] **Step 1: Write `interface _Codec`'s body**

```rbs
module Dexpace
  module Serde
    interface _Codec
      def media_type: () -> (Dexpace::MediaType | String)
      def dump_string: (untyped value) -> String
      def dump_bytes: (untyped value) -> String
      def dump_to: (untyped value, untyped sink) -> Integer
      def dump_into: (untyped value, String buffer, offset: Integer) -> Integer
      def load: (untyped source, _Witness witness) -> untyped
    end
  end
end
```

`#media_type`'s union is the finding the design proposes for `docs/open-items.md`: phase 2 declared
this interface and never wrote it, its `FakeCodec` returns a `String`, and `Dexpace::Body#media_type`
returns `Dexpace::MediaType?`. `#load`'s `source` is `untyped` rather than
`Dexpace::IO::BufferedSource`, because `SERDE-3`'s subject is "a caller-supplied stream" and phase
2's own test passes a `StringIO`.

- [ ] **Step 2: Add the ten `require_relative`s to `lib/dexpace.rb`, in dependency order**

`serde/decode_context`, `serde/witness`, `serde/native`, `serde/scalars`, `serde/tristate`,
`serde/list`, `serde/map`, `serde/nullable`, `serde/instant`, `serde/decoding_handler`,
`serde/status_aware_handler` — after `serde` and its three error files, which phase 2 already
requires.

- [ ] **Step 3: Run `rbs validate`, `steep check` and the whole core suite**

Run: `bundle exec rbs validate && bundle exec steep check && (cd gems/dexpace-core && bundle exec rake test)`
Expected: clean. `NFR-11`'s scan should report `::Time` as the only foreign constant in core's serde
signatures, and Task 1's `SEAM-2` test must still pass.

---

## Task 13: The gemspec line, the floor assertion, and the entry file

**Requirement IDs:** none new (`NFR-2`; `P7-7`).
**Design:** "What `7a` additionally ships, without owning a new ID"; `P7-7`.

**Files:**
- Modify: `gems/dexpace-serde-json/dexpace-serde-json.gemspec`,
  `gems/dexpace-serde-json/lib/dexpace/serde/json.rb`, `sig/dexpace/serde/json.rbs`
- Test: `gems/dexpace-serde-json/test/dexpace/serde/json_test.rb` (phase 0's, extended)

**This task is the ordering gate.** It lands before Task 14, which is the first task to write
`require "json"`.

- [ ] **Step 1: Write the failing tests**

```ruby
  test "NFR-2: the gemspec declares dexpace-core plus exactly one third-party gem" do
    spec = Gem::Specification.load(File.expand_path("../../../dexpace-serde-json.gemspec", __dir__))
    names = spec.runtime_dependencies.map(&:name).sort

    assert_equal(%w[dexpace-core json], names)
    assert_equal([">= 2.19.9"], spec.runtime_dependencies.find { |d| d.name == "json" }.requirements_list)
  end

  # P7-7. bundler-audit enforces the floor for a BUNDLED consumer in this repository's CI; it never
  # runs in a consumer's process. An unbundled `require "dexpace/serde/json"` on Ruby 3.4.10
  # activates the interpreter's default json 2.9.1, which has no JSON::Coder at all -- so without
  # this the failure is a NameError deep inside a codec, and the 2026 advisories the floor exists
  # for are silently unpatched.
  test "P7-7: the floor is asserted at require time and names itself" do
    assert_equal("2.19.9", Dexpace::Serde::JSON::MINIMUM_JSON_VERSION)
    assert_operator(Gem::Version.new(::JSON::VERSION), :>=,
                    Gem::Version.new(Dexpace::Serde::JSON::MINIMUM_JSON_VERSION))
  end

  test "the adapter registers itself against the seam with a core version assertion" do
    assert_includes(Dexpace::Serde.registered_keys, :json)
  end
```

- [ ] **Step 2: Run to confirm they fail**

Expected: FAIL on all three — no `json` dependency, no `MINIMUM_JSON_VERSION`, no registration.

- [ ] **Step 3: Add the gemspec line**

`spec.add_dependency "json", ">= 2.19.9"` beside the existing `dexpace-core` line. **This is the only
place in the repository that floor may be stated** (`CLAUDE.md`'s hard rule, design §3.4,
`serde/d15ade64`).

- [ ] **Step 4: Extend the entry file**

Keep phase 0's shadowing caution verbatim. Add, in order: `require "json"` (the first in this gem, and
legal only because Step 3 landed), the `MINIMUM_JSON_VERSION` constant, the `Gem::Version` floor
assertion raising `Dexpace::SeamError`, `require_relative "json/codec"`, and the registration
`Dexpace::Serde.register(:json, -> { default }, core: Dexpace::VERSION)` — design §2.4's
version-skew assertion, spent here for the first time by an adapter with a third-party dependency.
`.default` and `.build` delegate to `Codec`, which Task 14 writes; this step leaves them raising
`NotImplementedError` so the ordering is visible in the diff.

- [ ] **Step 5: Run the gate that this task exists for**

Run: `bundle exec rake gates:gemspec_audit gates:require_allowlist gates:clean_bundle`
Expected: clean. `gates:gemspec_audit` sees a gem with a third-party dependency for the first time in
the roadmap; `gates:require_allowlist`'s adapter extension permits `json` **because** Step 3 declared
it, and would fail if Steps 3 and 4 were reversed.

---

## Task 14: `Dexpace::Serde::JSON::Codec` — construction and the four encode profiles

**Requirement IDs:** `SERDE-1`, `SERDE-3` (encode half), `SERDE-4`, `SERDE-9`, `SERDE-10`,
`SERDE-25`, `SERDE-26`, `SERDE-29`.
**Design:** "`Dexpace::Serde::JSON::Codec` — the six seam methods"; `P7-4`, `P7-5`.

**Files:**
- Create: `gems/dexpace-serde-json/lib/dexpace/serde/json/codec.rb`,
  `sig/dexpace/serde/json/codec.rbs`
- Test: `gems/dexpace-serde-json/test/dexpace/serde/json/codec_test.rb`

**Needs:** Tasks 7 and 13.
**Produces:** `Codec.build`, `.default`, `#media_type`, `#dump_string`, `#dump_bytes`, `#dump_to`,
`#dump_into`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/close_counting_sink"

# SEAM-20's four allocation profiles, SERDE-4's buffer contract, SERDE-9/SERDE-10's failure model,
# SERDE-25's factory and SERDE-26's private engine. Every reference to Ruby's JSON is ::JSON --
# phase 2's Dexpace/QualifiedCoreConstant, and this is the first code it bites.
class DexpaceSerdeJSONCodecTest < DexpaceTestCase
  C = Dexpace::Serde::JSON::Codec

  test "SERDE-1: the seam's six methods are all present, so .conforms? accepts it" do
    assert(Dexpace::Serde.conforms?(C.default))
    assert_empty(Dexpace::Serde.missing_methods(C.default))
  end

  test "SEAM-19/SERDE-2: it declares its own media type as a MediaType" do
    assert_equal(Dexpace::MediaType.parse("application/json"), C.default.media_type)
  end

  # §10.13: a String tagged Encoding::BINARY *is* Ruby's byte array, so these two differ exactly in
  # the encoding tag -- and both ship because the tag is load-bearing at §3.1's boundary.
  test "SEAM-20: dump_string and dump_bytes differ exactly in the encoding tag" do
    codec = C.default

    assert_equal(::Encoding::UTF_8, codec.dump_string({ "a" => "é" }).encoding)
    assert_equal(::Encoding::BINARY, codec.dump_bytes({ "a" => "é" }).encoding)
    assert_equal(codec.dump_string({ "a" => "é" }).b, codec.dump_bytes({ "a" => "é" }))
  end

  test "SERDE-3: dump_to writes the bytes and never closes the caller's sink" do
    sink = CloseCountingSink.new
    written = C.default.dump_to({ "a" => "é" }, sink)

    assert_equal(sink.string.bytesize, written)
    assert_equal(0, sink.close_count)
  end

  # SERDE-4's conformance clause, all four parts.
  test "SERDE-4: encode into an oversized buffer at an offset" do
    payload = C.default.dump_bytes({ "a" => "é" })
    buffer = ("\0" * (payload.bytesize + 8)).b
    written = C.default.dump_into({ "a" => "é" }, buffer, offset: 4)

    assert_equal(payload.bytesize, written)
    assert_equal(payload, buffer.byteslice(4, payload.bytesize))
    assert_equal("\0\0\0\0".b, buffer.byteslice(0, 4))
  end

  # Verified fact 5 is why the explicit fit check exists: String#[]= with an in-range offset and an
  # over-long payload silently GROWS the string rather than raising, which is the one behaviour
  # SERDE-4 exists to forbid.
  test "SERDE-4: a one-byte-short buffer raises a range error, NOT the serde type, chaining nothing" do
    payload = C.default.dump_bytes({ "a" => 1 })
    buffer = ("\0" * (payload.bytesize - 1)).b

    error = assert_raises(::IndexError) { C.default.dump_into({ "a" => 1 }, buffer, offset: 0) }

    refute_kind_of(Dexpace::Serde::Error, error)
    assert_nil(error.cause)
    assert_equal(payload.bytesize - 1, buffer.bytesize, "the buffer must not have grown")
  end

  test "SERDE-4: an out-of-range offset raises IndexError and leaves the buffer untouched" do
    buffer = ("\0" * 4).b

    assert_raises(::IndexError) { C.default.dump_into(1, buffer, offset: 9) }
    assert_raises(::IndexError) { C.default.dump_into(1, buffer, offset: -1) }
    assert_equal("\0\0\0\0".b, buffer)
  end

  # P7-5. Ruby's IO::Buffer is excluded by measurement, not by taste: it warns through Warning.warn
  # at every level and phase 0's shared test case overrides Warning.warn TO RAISE, so a test
  # constructing one fails the build -- and a requirement whose conformance clause cannot be tested
  # is not satisfied. Also, its set_string raises ArgumentError where String#[]= raises IndexError.
  test "P7-5: a frozen or non-BINARY buffer is refused as an argument error, not a range error" do
    assert_raises(Dexpace::InvalidArgumentError) { C.default.dump_into(1, (+"    ").b.freeze, offset: 0) }
    assert_raises(Dexpace::InvalidArgumentError) { C.default.dump_into(1, +"    ", offset: 0) }
    assert_raises(Dexpace::InvalidArgumentError) { C.default.dump_into(1, [], offset: 0) }
  end

  # SERDE-9/SERDE-10, and verified fact 2 is why this is a real test rather than a formality:
  # ::JSON.generate(Object.new) RETURNS "\"#<Object:0x…>\"" instead of raising. Two layers stop it --
  # core's Native walk rejects a non-native value, and strict: true makes the generator itself raise.
  test "SERDE-9/SERDE-10: an unserializable value raises the SERIALIZATION subtype, not the library's" do
    error = assert_raises(Dexpace::Serde::SerializationError) { C.default.dump_string(Object.new) }

    refute_kind_of(::JSON::JSONError, error)
    assert_match(/Object/, error.message)
  end

  test "the generator is strict, so a bare Object never round-trips as its inspect string" do
    refute_match(/#<Object/, (C.default.dump_string({ "a" => 1 }) rescue ""))
    assert_raises(Dexpace::Serde::SerializationError) { C.default.dump_string([Object.new]) }
  end

  test "SERDE-9: a library failure is caught and chained rather than escaping the SPI" do
    error = assert_raises(Dexpace::Serde::SerializationError) { C.default.dump_string(::Float::NAN) }

    assert_kind_of(::JSON::JSONError, error.cause)
  end

  # SERDE-25's conformance clause: "invoke the factory twice and assert distinct instances".
  test "SERDE-25: .default returns a fresh, independent instance on every call" do
    refute_same(C.default, Dexpace::Serde::JSON.default)
    refute_same(C.default.__id__, C.default.__id__)
  end

  # SERDE-26 (P7-4). The antecedent is false by construction -- .build takes OPTIONS, never a
  # ::JSON::Coder -- and each instance owns a private engine built from its own frozen options hash,
  # so no engine is shared and no reconfiguration of one reaches another.
  test "SERDE-26: two codecs share no engine and neither exposes one" do
    a = C.build(max_nesting: 4)
    b = C.default

    refute_respond_to(a, :coder)
    assert_predicate(a, :frozen?)
    assert_raises(Dexpace::Serde::DeserializationError) { a.load(source("[[[[[1]]]]]"), ->(x, _c) { x }) }
    assert_equal([[[[[1]]]]], b.load(source("[[[[[1]]]]]"), ->(x, _c) { x }))
  end

  test "an unknown option is refused rather than forwarded silently" do
    assert_raises(Dexpace::InvalidArgumentError) { C.build(max_nestng: 4) }
  end

  # SERDE-29's conformance clause: "exercise one serde from many concurrent workers encoding and
  # decoding distinct values and assert no corruption."
  test "SERDE-29: one frozen codec is safe from many concurrent workers" do
    codec = C.default
    results = 8.times.map do |i|
      ::Thread.new { 200.times.map { codec.dump_string({ "k" => i, "v" => "é#{i}" }) }.uniq }
    end.map(&:value)

    assert_equal(8, results.flatten.uniq.size)
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

Expected: FAIL — `uninitialized constant Dexpace::Serde::JSON::Codec`.

- [ ] **Step 3: Fix the option allowlist against the FLOORED gem**

Before writing the class, enumerate `::JSON::Coder.new`'s accepted options on **2.19.9** — not on
2.9.1 — and fix `ALLOWED_OPTIONS` to the intersection of that set and what this adapter means to
support. Open question 4's starting set is `%i[max_nesting allow_nan allow_duplicate_key script_safe
encoders]`; record the final set in the task's notes with the measurement.

- [ ] **Step 4: Write `lib/dexpace/serde/json/codec.rb`**

A plain class (not a `Data`, because it holds a `::JSON::Coder` that is an implementation detail with
no value semantics), frozen at the end of `initialize`, `private_class_method :new`, `.build(**options)`
validating against `ALLOWED_OPTIONS` and `.default` calling `.build`. `@coder =
::JSON::Coder.new(**@json_options.merge(strict: true))`; `@encoders` is the frozen ISO-8601 table
Task 16 fills; `@media_type` is a memoized frozen `Dexpace::MediaType`.

`#dump_string` is `@coder.dump(Dexpace::Serde::Native.of(value, encoders: @encoders))` wrapped in
`rescue ::JSON::JSONError => e; raise Dexpace::Serde::SerializationError, "…"` — **inside** the
rescue, so Ruby sets `#cause` (`serde/5821286d`). `#dump_bytes` is `#dump_string(value).b`.
`#dump_to(value, sink)` is `sink.write(dump_bytes(value))` and closes nothing. `#dump_into` is the
design's nine lines, verbatim, including `cause: nil`.

- [ ] **Step 5: Write the `sig/` mirror and run to confirm it passes**

**No `::JSON` constant appears in the adapter's public signature** — `NFR-11`, and the reason
`@coder` has no reader. Run the suite. Expected: PASS, 14 runs, and `bundle exec rubocop` clean on
`Dexpace/QualifiedCoreConstant`.

---

## Task 15: `Codec#load`

**Requirement IDs:** `SERDE-3` (decode half), `SERDE-5`, `SERDE-11`, `SERDE-12`, `SERDE-13`,
`SERDE-21`, `SERDE-22`, `SERDE-23`.
**Design:** "`#load`, stated in full"; `R1`; `P7-1`; `P7-6`.

**Files:**
- Modify: `gems/dexpace-serde-json/lib/dexpace/serde/json/codec.rb`, its `sig/`
- Test: `gems/dexpace-serde-json/test/dexpace/serde/json/codec_load_test.rb`

**Needs:** Tasks 2, 3, 5, 14.
**Produces:** `#load(source, witness)`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/close_counting_source"

# SERDE-3's decode half, SERDE-5, SERDE-11, SERDE-12, SERDE-13, SERDE-21, SERDE-22, SERDE-23.
class DexpaceSerdeJSONCodecLoadTest < DexpaceTestCase
  C = Dexpace::Serde::JSON::Codec
  S = Dexpace::Serde

  class Pet
    attr_reader :name

    def self.dexpace_load(parsed, ctx)
      h = ctx.object!(parsed)
      new(ctx.string!(h["name"], key: "name"))
    end

    def initialize(name) = @name = name
  end

  def source(text) = Dexpace::IO::BufferedSource.of_bytes(text.b)

  # SERDE-5's conformance clause: decode a JSON object into a concrete DTO via the type-witness path
  # and assert the result is the REAL DTO type with typed field access.
  test "SERDE-5: decode through an explicit witness yields the real type" do
    pet = C.default.load(source(%q({"name":"Ré"})), Pet)

    assert_instance_of(Pet, pet)
    assert_equal("Ré", pet.name)
    assert_equal(::Encoding::UTF_8, pet.name.encoding)
  end

  # SERDE-3, and message-bodies/a7afc6ee names this rule as 7a's: "a codec closes nothing".
  # SERDE-3's own tail -- "even when the codec's own auto-close feature is enabled" -- holds under
  # every option this adapter accepts, which is what the loop covers.
  test "SERDE-3: load reads to EOF and closes the caller's source exactly zero times" do
    [C.default, C.build(max_nesting: 4)].each do |codec|
      tracked = CloseCountingSource.new(%q({"name":"x"}))

      codec.load(tracked, Pet)

      assert_equal(0, tracked.close_count)
      assert_predicate(tracked, :at_eof?)
    end
  end

  test "SERDE-5: there is no witness-less overload to fall into" do
    assert_raises(::ArgumentError) { C.default.load(source("{}")) }
    assert_raises(Dexpace::InvalidArgumentError) { C.default.load(source("{}"), 5) }
  end

  # SERDE-9 from the decode side, and SERDE-11 (SHOULD, satisfied by the language: every one of
  # these is a StandardError descendant and appears in no declared signature).
  test "SERDE-13/SERDE-9: malformed input is wrapped as the DESERIALIZATION subtype with a cause" do
    error = assert_raises(Dexpace::Serde::DeserializationError) { C.default.load(source("{not json"), Pet) }

    assert_kind_of(::JSON::JSONError, error.cause)
    assert_kind_of(::StandardError, error)
  end

  # SERDE-12, satisfied STRUCTURALLY by verified fact 3: JSON::JSONError's ancestry is
  # [JSON::ParserError, JSON::JSONError, StandardError, Exception] and IOError is nowhere in it, so
  # `rescue ::JSON::JSONError` CANNOT catch a Dexpace::StreamError. The codec writes no
  # `rescue StandardError` and this test is what proves the narrow rescue is load-bearing.
  test "SERDE-12: a genuine stream I/O error propagates UNWRAPPED" do
    failing = Object.new
    def failing.read_utf8(count: nil) = raise Dexpace::StreamError, "connection reset"

    error = assert_raises(Dexpace::StreamError) { C.default.load(failing, Pet) }

    refute_kind_of(Dexpace::Serde::Error, error)
  end

  # R1 clause 3, and the observable behaviour a caller will meet: a body above IO-9's ceiling raises
  # a StreamError (an ::IOError), which propagates past the codec's rescue for the same reason.
  test "R1/P7-1: an over-ceiling body surfaces as a StreamError, not as a serde error" do
    over_ceiling = Object.new
    def over_ceiling.read_utf8(count: nil)
      raise Dexpace::StreamError, "materialisation would exceed MAX_MATERIALIZED_BYTES"
    end

    assert_raises(Dexpace::StreamError) { C.default.load(over_ceiling, Pet) }
  end

  # SERDE-13 across "every decode overload" -- which is one method here, so one test.
  test "SERDE-13: a wire null into a non-null target names the target type" do
    error = assert_raises(Dexpace::Serde::DeserializationError) { C.default.load(source("null"), Pet) }

    assert_match(/Hash/, error.message)
  end

  # SERDE-21/SERDE-22, through the REAL codec rather than through DecodeContext alone: JSON.parse
  # performs no coercion (verified), so the strictness burden is entirely the witness's.
  test "SERDE-21: the codec never coerces, so the witness sees the wire shape" do
    assert_raises(Dexpace::Serde::DeserializationError) { C.default.load(source(%q({"name":5})), Pet) }
  end

  test "SERDE-22: an integer widens into a float target through the real decode path" do
    witness = ->(parsed, ctx) { ctx.float!(parsed) }
    def witness.dexpace_load(parsed, ctx) = call(parsed, ctx)

    assert_in_delta(1.0, C.default.load(source("1"), witness))
  end

  test "SERDE-23: an unknown field is ignored" do
    assert_equal("x", C.default.load(source(%q({"name":"x","new_field":1})), Pet).name)
  end

  # P7-6. Verified fact 6: #read_utf8 retags without validating (3a's stated contract) and
  # ::JSON.parse accepts invalid UTF-8 and returns a UTF-8-tagged String whose #valid_encoding? is
  # false. Without this guard a caller receives a String that claims an encoding it does not have.
  test "P7-6: invalid UTF-8 in the payload is a deserialization failure, not a corrupt String" do
    invalid = source(%Q({"name":"\xff"}))

    error = assert_raises(Dexpace::Serde::DeserializationError) { C.default.load(invalid, Pet) }

    assert_match(/UTF-8/, error.message)
  end

  test "P7-6: well-formed non-ASCII survives the same path untouched" do
    assert_equal("héllo wörld", C.default.load(source(%q({"name":"héllo wörld"})), Pet).name)
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

Expected: FAIL — `NoMethodError: undefined method 'load'`.

- [ ] **Step 3: Implement `#load`**

The design's ten lines, verbatim, with three comments that must survive review: the
`::JSON::Coder#load`-is-not-`::JSON.load` note, the `P7-6` validation note, and the
`rescue ::JSON::JSONError`-and-never-`StandardError` note naming verified fact 3 as the reason.

- [ ] **Step 4: Run to confirm it passes**

Expected: PASS, 12 runs. Re-run Task 14's suite.

---

## Task 16: The two adapter defaults and the tri-state round trip

**Requirement IDs:** `SERDE-1`, `SERDE-19`, `SERDE-24`.
**Design:** "`Dexpace::Serde::JSON::Codec`"; `P7-9`.

**Files:**
- Modify: `gems/dexpace-serde-json/lib/dexpace/serde/json/codec.rb`
- Test: `gems/dexpace-serde-json/test/dexpace/serde/json/defaults_test.rb`

**Needs:** Tasks 6, 7, 8, 14, 15.
**Produces:** the `encoders:` table wiring `::Time`/`::Date`/`::DateTime` to `Instant`, and the
end-to-end tri-state round trip.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# SERDE-1's round trip, SERDE-19's default wiring, SERDE-24's encoder default. Design §3.4 fixes the
# last two "here rather than left to the JSON gem's own", so they are the adapter's and are tested
# through the real codec end to end.
class DexpaceSerdeJSONDefaultsTest < DexpaceTestCase
  C = Dexpace::Serde::JSON::Codec
  T = Dexpace::Serde::Tristate

  class Patch
    def self.dexpace_load(parsed, ctx)
      h = ctx.object!(parsed)
      new(name: ctx.string!(h["name"], key: "name"),
          nick: T.of(String).dexpace_load_field(h, "nick", ctx))
    end

    attr_reader :name, :nick

    def initialize(name:, nick:) = (@name = name; @nick = nick)
    def dexpace_dump = { "name" => @name, "nick" => @nick }
  end

  def source(text) = Dexpace::IO::BufferedSource.of_bytes(text.b)

  # SERDE-1's conformance clause: "assert the serializer and deserializer round-trip a value with
  # each other" -- one bundle, one reference.
  test "SERDE-1: the encoder and decoder round-trip through one bundle" do
    codec = C.default
    original = Patch.new(name: "Ré", nick: T.present("n"))
    back = codec.load(source(codec.dump_string(original)), Patch)

    assert_equal("Ré", back.name)
    assert_equal("n", back.nick.value)
  end

  # SERDE-19's conformance clause, quoted: "build from a bare codec with default settings; assert
  # Absent omits the key and Null emits null." P7-9 is what makes this structural rather than a
  # convention every model must remember.
  test "SERDE-19: the DEFAULT configuration wires tri-state, with nothing registered" do
    codec = C.default

    assert_equal(%q({"name":"x"}), codec.dump_string(Patch.new(name: "x", nick: T::ABSENT)))
    assert_equal(%q({"name":"x","nick":null}), codec.dump_string(Patch.new(name: "x", nick: T::NULL)))
    assert_equal(%q({"name":"x","nick":"n"}), codec.dump_string(Patch.new(name: "x", nick: T.present("n"))))
  end

  test "SERDE-16/SERDE-17: the same three shapes decode back to the three states" do
    codec = C.default

    assert_predicate(codec.load(source(%q({"name":"x"})), Patch).nick, :absent?)
    assert_predicate(codec.load(source(%q({"name":"x","nick":null})), Patch).nick, :null?)
    assert_equal("n", codec.load(source(%q({"name":"x","nick":"n"})), Patch).nick.value)
  end

  # SERDE-24's conformance clause through the real codec: "serialize an instant -> ISO-8601 string,
  # deserialize -> equality with the original." Design §3.4: "never epoch numbers".
  test "SERDE-24: the default encoder renders a Time as an ISO-8601 string, not an epoch number" do
    encoded = C.default.dump_string({ "at" => ::Time.utc(2026, 9, 10, 12) })

    assert_equal(%q({"at":"2026-09-10T12:00:00.000000Z"}), encoded)
    refute_match(/\d{10}/, encoded.sub("2026", ""))
  end

  test "SERDE-24: the round trip holds within the stated precision domain" do
    codec = C.default
    t = ::Time.at(1_757_505_600, 123_456, :usec).utc
    witness = Dexpace::Serde::Instant

    assert_equal(t, codec.load(source(codec.dump_string(t)), witness))
  end

  # P7-8, executable. Outside the domain the encoding truncates, and the YARD says so.
  test "P7-8: a Float-second Time truncates through the real codec too" do
    codec = C.default
    t = ::Time.new(2026, 9, 10, 12, 0, 0.123456, "+02:00")

    refute_equal(t, codec.load(source(codec.dump_string(t)), Dexpace::Serde::Instant))
  end

  test "a Date and a DateTime take the same default" do
    assert_match(/2026-09-10/, C.default.dump_string(::Date.new(2026, 9, 10)))
  end
end
```

- [ ] **Step 2: Run to confirm it fails**

Expected: FAIL — a `Time` raises `SerializationError` from `Native.of`, because Task 7 ships the
`encoders:` hook empty.

- [ ] **Step 3: Fill the encoders table**

```ruby
DEFAULT_ENCODERS = {
  ::Time     => ->(t) { Dexpace::Serde::Instant.dexpace_dump(t) },
  ::DateTime => ->(d) { Dexpace::Serde::Instant.dexpace_dump(d.to_time) },
  ::Date     => ->(d) { d.iso8601 },
}.freeze
```

The table is the adapter's per design §3.4 and core ships it **empty**, which is what keeps the
ISO-8601 default from becoming every codec's. A caller may replace it through `Codec.build(encoders:
…)`, which is what the option allowlist's `:encoders` entry is for.

- [ ] **Step 4: Run to confirm it passes**

Expected: PASS, 8 runs. Re-run Tasks 14 and 15.

---

## Task 17: `SerdeSeamAssertions` and the adapter conformance suite

**Requirement IDs:** `SERDE-3`, `SERDE-4`, `SERDE-9`, `SERDE-10`, `SERDE-12`, `SERDE-29` — asserted
here **through the lift target**, in addition to Tasks 14–16's direct tests.
**Design:** `R12`.

**Files:**
- Create: `gems/dexpace-serde-json/test/support/serde_seam_assertions.rb`
- Create: `gems/dexpace-serde-json/test/dexpace/serde/json/seam_conformance_test.rb`

**Needs:** Tasks 14, 15, 16.
**Produces:** the file phase 9 lifts.

- [ ] **Step 1: Write `SerdeSeamAssertions`**

A plain module of assertion **methods** over a `codec` the includer supplies, written **against the
seam** and naming `Dexpace::Serde::JSON` nowhere:

```ruby
module SerdeSeamAssertions
  # SEAM-20/SEAM-21/SERDE-3: a codec closes nothing. Phase 9 lifts this file into
  # dexpace-conformance and re-points the raises at Dexpace::Conformance::Failure; the ASSERTIONS
  # are written once, here, and against the seam rather than against any adapter (DEF-22 fixes the
  # callable shape and is phase 8's, so this stays plain Minitest).
  def assert_closes_nothing(codec) = …
  def assert_buffer_profile(codec) = …          # SERDE-4's four parts
  def assert_failure_model(codec) = …           # SERDE-9, SERDE-10, and the non-null cause
  def assert_io_error_passthrough(codec) = …    # SERDE-12
  def assert_shareable(codec) = …               # SERDE-29
end
```

- [ ] **Step 2: Write the suite that drives it**

```ruby
class DexpaceSerdeJSONSeamConformanceTest < DexpaceTestCase
  include SerdeSeamAssertions

  test "the JSON codec satisfies the seam's adapter obligations" do
    codec = Dexpace::Serde::JSON.default

    assert_closes_nothing(codec)
    assert_buffer_profile(codec)
    assert_failure_model(codec)
    assert_io_error_passthrough(codec)
    assert_shareable(codec)
  end
end
```

- [ ] **Step 3: Run to confirm it passes**

Expected: PASS. It should pass on the first run, because Tasks 14–16 already established every
behaviour — that is the point: this task packages, it does not discover. **If it fails, the failure
is in the packaging and the assertion is wrong, not the codec.**

- [ ] **Step 4: Record the phase-9 target**

The file path goes into `7a`'s checklist, so phase 9 inherits a named target rather than
reconstructing assertions from prose. `DEF-29`'s condition is still **not** met — these doubles are
new and consume none of core's three fakes — and `DEF-22`'s callable shape is **not** pre-empted.

---

## Task 18: Final wiring

**Requirement IDs:** none new (`NFR-3`, `NFR-4`, `NFR-11`, `NFR-13`).
**Design:** "The `sig/` shape"; "The knowledge note `7a` files"; "The findings proposed for the
registers".

- [ ] **Step 1: Run the whole gate set on all three interpreters**

Run: `bundle exec rake` on 3.2.11, 3.4.10 and 4.0.6. Every one of the seventeen gates, with
`gates:gemspec_audit`, `gates:require_allowlist` and `gates:clean_bundle` now seeing a gem with a
third-party dependency for the first time in the roadmap.

- [ ] **Step 2: Regenerate BOTH the RBS baseline and the runtime surface snapshot**

Run: `bundle exec rake surface:regenerate`, then diff. Changing exports means regenerating **both**:
`Data.define`'s generated readers on `Tristate::Present`, `DecodeContext` and the three combinators
are public API invisible to `rbs validate`, and the adapter's require-time `Dexpace::Serde.register`
call is invisible to it too. Confirm the diff shows only additions — `NFR-4`'s lock fails on a
signature that disappears or narrows, and `7a` narrows nothing.

- [ ] **Step 3: Confirm `NFR-11`'s scan and the `SEAM-2` test**

Core's serde signatures name `::Time` and nothing else foreign; the adapter's name no `::JSON`
constant. Task 1's `SEAM-2` test must still pass over the finished tree.

- [ ] **Step 4: Write the knowledge note**

`docs/knowledge/notes/serde.md`, a `## Reference` entry, exactly as the design drafts it — role
`review`, a manual `sha:manual-phase7a-utf8-validation` marker, and a backticked `serde/b5e5efc8`
reference. Then run `ruby scripts/verify_knowledge_structure.rb` (the gate) and
`ruby scripts/knowledge_drift.rb` (the hand-run report). **`harvested/` is not edited.**

- [ ] **Step 5: Hand the four register findings to a human**

The design drafts all four verbatim and **this plan does not file them**: the unwritten `_Codec`
interface and the `SERDE`-audit-group narrowness (`docs/open-items.md`), the `SERDE-27` release
blocker (`docs/first-release.md`), and `DEF-16`'s second motive (`docs/deferred-items.md`). Also hand
over the nine `P7-<n>` ledger rows for consolidation into design §10 and audit by
`docs/deviations.md`.

- [ ] **Step 6: Run housekeeping's probe**

Run: `ruby .claude/skills/housekeeping/probe.rb`
Fix what it reports — **without rewriting prose to satisfy a check** — and note that `CLAUDE.md`'s
phase-directory claims sentence and the `knowledge-lookup` audit-group row are the charter's
obligations, not this plan's. **Do not run `apply.rb --write`** and do not commit; both are the
user's to ask for.
