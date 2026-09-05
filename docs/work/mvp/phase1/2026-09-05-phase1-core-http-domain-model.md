# Phase 1 — Core HTTP Domain Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the frozen, transport-agnostic HTTP wire model in `dexpace-core` — headers, status,
method, protocol, media type, query, URL, request options, request and response — satisfying
`HTTP-3`–`HTTP-35`, `HTTP-46`–`HTTP-50` and `HTTP-53`, with `HTTP-1`/`HTTP-2` and `SEAM-29`'s
construction contract satisfied by construction.

**Architecture:** Every value type is a `Data.define` subclass that includes one shared module,
`Dexpace::Model`, which supplies the required-field helper, the collection-ownership helper and a
`#with` that re-validates on every supported Ruby. `new` is private on every model; a public
validating `.build` is the only official construction path. The five models whose validation is
cross-field — `Headers`, `Query`, `RequestOptions`, `Request`, `Response` — get real mutable
`Builder` classes in their own files; the rest expose `parse`/`of` factories and `#with`.

**Tech Stack:** Ruby 3.2–4.0 (development on 4.0.6), no runtime dependencies, Minitest, RBS +
Steep, RuboCop with five custom cops, SimpleCov, YARD — all stood up by phase 0.

**Spec:** `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md`

## Global Constraints

Every task's requirements implicitly include this section. Values are copied verbatim from the
design and the governing documents.

- **`dexpace-core` gains no dependency.** The gemspec keeps zero `add_dependency` lines
  (`SEAM-1`, `NFR-1`). The only `require` this phase adds is `require "uri"`, which is on phase 0's
  twelve-name allowlist; everything else is `require_relative`.
- **Every `.rb` file** opens with `# frozen_string_literal: true` on line 1,
  `# SPDX-License-Identifier: MIT` on line 2, then a blank line (`NFR-13`;
  `docs/knowledge/notes/formatting-and-tooling.md`). No `# typed:` sigil anywhere.
- **Banned, and each is a blocking cop:** `Time.parse`/`Date.parse`/`DateTime.parse`;
  `URI::DEFAULT_PARSER` and the `URI.parse`/`URI.join`/`URI.split` family that routes through it —
  **use `URI::RFC3986_PARSER` explicitly**; any argument to `downcase`/`upcase`/`capitalize`/
  `swapcase` and `casecmp?`; `Timeout.timeout`, `Thread#raise`, `Thread#kill`.
- **Regexp timeouts are per-pattern**: `Regexp.new(source, timeout:)`, never `Regexp.timeout=`.
- **Every validation and encoding predicate reads bytes**, `value.b.each_byte`, never a character
  regexp: a `String` carrying invalid UTF-8 is exactly the input these functions exist to reject,
  and a character operation on one raises `ArgumentError`/`Encoding::CompatibilityError` from
  inside Ruby instead of returning `false`.
- **No `.build` is a bare `new` wrapper.** Every `Data` type validates in its `initialize`
  override (or in `.build` before `new`), because `.build` is public, `#with` routes every
  derivation through it, and `send(:new, …)` reaches the generated constructor whatever anyone
  writes. A rule enforced only in a `Builder` is a rule three callers walk around. The Builders
  carry exactly the rules that are about *unset* fields — `HTTP-8`'s method defaulting — and
  nothing else.
- **One error class for caller mistakes:** `Dexpace::InvalidArgumentError`, raised as
  `raise Dexpace::InvalidArgumentError, "message"` (`error-handling/f511eaba`). Never define
  `Dexpace::ArgumentError`. Never `raise` a bare string.
- **Formatting:** double quotes, 2-space indent, **100 columns**, `consistent_comma` trailing
  commas, leading-dot chains, `MethodLength: 25` with `CountAsOne`, `ParameterLists: 4`,
  `BlockNesting: 3`.
- **Tests:** Minitest only, `FooTest < DexpaceTestCase`, `test "..." do` blocks, `test/` mirroring
  `lib/` one file per file, `assert_equal(expected, actual)` in that order, every test passing
  alone and in any order, the seed never overridden. Each test file's header comment names the
  requirement IDs it exercises.
- **Every public constant gets three artifacts in the same task**: the implementation, a YARD block
  that explains *why* and never restates a type (`documentation/42d8cbf4`), and an `.rbs` mirror at
  the same path under `sig/`.
- **No commit step appears in any task.** The manager commits once per phase.
- **Never edit** `docs/product-spec/`, `docs/sdk-design-ruby/`, `docs/knowledge/harvested/`.

### Commands

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/<path>_test.rb   # one suite, red or green
(cd gems/dexpace-core && bundle exec rake test)                     # the gem's whole suite
bundle exec rake                                                    # all seventeen gates
mise exec ruby@3.2.11 -- bundle exec rake test:gems                 # the floor, locally
bundle exec rake surface:regenerate                                 # deliberate; Task 17 only
```

---

## File Structure

Grouped by responsibility. Every file below is created by exactly one task, and every `lib/` file
gets its `sig/` mirror and its `test/` mirror in that same task. All paths are relative to
`gems/dexpace-core/` unless stated otherwise.

**The construction contract (Tasks 1–2).** `lib/dexpace/error.rb`,
`lib/dexpace/error/invalid_argument_error.rb`, `lib/dexpace/model.rb`, `lib/dexpace/builder.rb`.
Responsibility: what an error is in this SDK, the four operations every value type in every later
phase inherits, and `SEAM-29`'s shared generic builder contract. These come first because every
other task raises, builds and derives through them.

**Header validation (Task 3).** `lib/dexpace/http/header_syntax.rb`. Responsibility: the byte-level
predicates for `HTTP-17`/`HTTP-18`/`HTTP-19`/`HTTP-20`, public because phase 8's transports call
them again at the wire boundary. Split from `Headers` because a transport must reach the predicate
without constructing a model.

**The header model (Tasks 4–5).** `lib/dexpace/http/header_name.rb`,
`lib/dexpace/http/headers.rb`, `lib/dexpace/http/headers/builder.rb`.

**The standalone value types (Tasks 6–9).** `lib/dexpace/http/status.rb`,
`lib/dexpace/http/method.rb`, `lib/dexpace/http/protocol.rb`, `lib/dexpace/http/media_type.rb`.
Each is independent of the others; the order is convenience, not dependency.

**Encoding and the query model (Tasks 10–11).** `lib/dexpace/http/percent_encoding.rb`,
`lib/dexpace/http/query.rb`, `lib/dexpace/http/query/builder.rb`. The encoder is its own file
because `SEAM-27`'s path-segment encoding (phase 2) calls it too.

**URLs and options (Tasks 12–13).** `lib/dexpace/http/url.rb`,
`lib/dexpace/http/request_options.rb`, `lib/dexpace/http/request_options/builder.rb`.

**The two composite models (Tasks 14–15).** `lib/dexpace/http/request.rb`,
`lib/dexpace/http/request/builder.rb`, `lib/dexpace/http/response.rb`,
`lib/dexpace/http/response/builder.rb`. Last, because each consumes most of what precedes it.

**Wiring and closing (Tasks 16–17).** `lib/dexpace.rb` and `sig/dexpace.rbs` (modified),
then the repository-root `test/fixtures/surface/dexpace-core.txt`, the checklist, the registers and
`CLAUDE.md`.

---

## Task 1: The error root and the validation error

**Requirement IDs:** `HTTP-4`, `HTTP-47`, `SEAM-29` (message form); `XCUT-4` is what forces the
module shape and is phase 9's to disposition.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/error.rb`,
  `gems/dexpace-core/lib/dexpace/error/invalid_argument_error.rb`,
  `gems/dexpace-core/sig/dexpace/error.rbs`,
  `gems/dexpace-core/sig/dexpace/error/invalid_argument_error.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb` (add the two `require_relative`s)
- Test: `gems/dexpace-core/test/dexpace/error_test.rb`,
  `gems/dexpace-core/test/dexpace/error/invalid_argument_error_test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `Dexpace::Error`, a module included by every core error class in every later phase;
  `Dexpace::InvalidArgumentError < ::ArgumentError`, which includes it. Later phases add
  `Dexpace::TransportError < ::IOError`, `Dexpace::PipelineError` and `Dexpace::ClosedError` the
  same way.

- [ ] **Step 1: Write the failing tests**

`gems/dexpace-core/test/dexpace/error/invalid_argument_error_test.rb`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# HTTP-4, HTTP-47, SEAM-29. The shape is the point: XCUT-4 requires a transport error to be in
# Ruby's IOError family, so the SDK root cannot be a base class (design §5 addendum A3).
class DexpaceInvalidArgumentErrorTest < DexpaceTestCase
  test "is an ArgumentError, so a caller's existing rescue keeps matching" do
    assert_operator(Dexpace::InvalidArgumentError, :<, ::ArgumentError)
  end

  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::InvalidArgumentError, "url is required"
    rescue Dexpace::Error => error
      error
    end

    assert_equal("url is required", caught.message)
  end

  # The string form of module_eval, not the block form: only the string form sets the cref, so
  # only it puts the rescue in Dexpace's lexical scope, which is where a Dexpace::ArgumentError
  # would shadow ::ArgumentError. The block form keeps this file's scope and proves nothing --
  # verified by defining Dexpace::ArgumentError and watching this test error.
  test "a bare rescue ArgumentError inside the Dexpace namespace still catches Ruby's own" do
    caught = Dexpace.module_eval(<<~RUBY, __FILE__, __LINE__ + 1)
      begin
        Integer("not a number")
      rescue ArgumentError => error
        error
      end
    RUBY

    assert_instance_of(::ArgumentError, caught)
  end
end
```

`gems/dexpace-core/test/dexpace/error_test.rb` asserts two things: `Dexpace::Error` is a `Module`
and not a `Class` (`assert_kind_of(Module, …)` plus `refute_kind_of(Class, …)`), and
`Dexpace.constants(false)` does not include `:ArgumentError` — the shadowing name this SDK never
defines, and the constant whose absence the `module_eval` test above depends on.

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error/invalid_argument_error_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::InvalidArgumentError`.

- [ ] **Step 3: Write `lib/dexpace/error.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # The marker every error raised by this SDK carries.
  #
  # A module rather than a base class, and the choice is forced: XCUT-4 requires a transport error
  # to belong to the runtime's I/O-error family so existing I/O rescue sites keep matching, which
  # in Ruby means `Dexpace::TransportError < ::IOError`. Ruby has single inheritance, so a class
  # root would make that requirement unsatisfiable in phase 8. `rescue` matches with Module#===,
  # which is `is_a?`, so `rescue Dexpace::Error` catches every including class exactly as a base
  # class would.
  #
  # Design §5's suppressed-exception trail -- #suppressed, the #full_message override and
  # Dexpace.attach_suppressed -- lands in phase 4 with the recovery chain that is its first
  # caller (DEF-24). It is deliberately absent rather than stubbed here.
  module Error
  end
end
```

- [ ] **Step 4: Write `lib/dexpace/error/invalid_argument_error.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # Raised when a caller supplies an argument no model can accept: a missing required field
  # (HTTP-4, in SEAM-29's "<name> is required" form), a malformed URL (HTTP-47), a header name
  # carrying a control byte (HTTP-17).
  #
  # It subclasses Ruby's own ArgumentError because that is what the failure IS -- a caller
  # mistake, which the styleguide raises from validation helpers and never rescues in ordinary
  # flow. The SDK-specific name is InvalidArgumentError, never Dexpace::ArgumentError: the latter
  # would shadow ::ArgumentError for every file inside `module Dexpace`, so a bare
  # `rescue ArgumentError` in core would silently stop catching Ruby's.
  class InvalidArgumentError < ::ArgumentError
    include Dexpace::Error
  end
end
```

- [ ] **Step 5: Write the two `sig/` mirrors**

`sig/dexpace/error.rbs`:

```rbs
module Dexpace
  module Error
  end
end
```

`sig/dexpace/error/invalid_argument_error.rbs`:

```rbs
module Dexpace
  class InvalidArgumentError < ::ArgumentError
    include Dexpace::Error
  end
end
```

- [ ] **Step 6: Add the requires to `lib/dexpace.rb`** — `require_relative "dexpace/error"` and
  `require_relative "dexpace/error/invalid_argument_error"`, after the existing version require.

- [ ] **Step 7: Run the tests to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/error_test.rb` and the sibling file.
Expected: PASS, 5 runs across the two files.

---

## Task 2: `Dexpace::Model` and `Dexpace::Builder` — the construction contract

**Requirement IDs:** `HTTP-1`, `HTTP-2`, `HTTP-3`, `HTTP-4`, `HTTP-5`, `SEAM-29`, `XCUT-15`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/model.rb`, `gems/dexpace-core/lib/dexpace/builder.rb`,
  `gems/dexpace-core/sig/dexpace/model.rbs`, `gems/dexpace-core/sig/dexpace/builder.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/model_test.rb`,
  `gems/dexpace-core/test/dexpace/builder_test.rb`

**Interfaces:**
- Consumes: `Dexpace::InvalidArgumentError` (Task 1).
- Produces: `Dexpace::Model`, with module functions `Model.required!(name, value) -> value`,
  `Model.own(collection) -> collection` (deep-frozen copy) and
  `Model.frozen_string(value) -> String`, plus the instance method `#with(**changes)`. Every value
  type in Tasks 4–15 includes it and defines `self.build(**members)`. And `Dexpace::Builder`,
  `SEAM-29`'s shared generic builder contract: the instance method `#build` (abstract) and the
  generic composition helper `Builder.build_all(builders) -> Array[Object]`. Every `Builder` class
  in Tasks 5, 11, 13, 14 and 15 includes it.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"

# HTTP-3, HTTP-4, HTTP-5, SEAM-29, XCUT-15. The #with case is the one that matters: Data#with does
# NOT call an initialize override on Ruby 3.2 (verified against 3.2.11, 3.4.10 and 4.0.6), so
# without this module derivation is unvalidated on the declared floor and validated everywhere
# else. Design §4 addendum A1.
class DexpaceModelTest < DexpaceTestCase
  # A minimal type in the shape every core model uses: private new, validating build, Model
  # included. Defined here rather than in lib/ because it exists only to test the contract.
  class Sample < Data.define(:code)
    include Dexpace::Model
    private_class_method :new

    def self.build(code:)
      new(code: code)
    end

    def initialize(code:)
      Dexpace::Model.required!("code", code)
      super
    end
  end

  test "required! raises the one error class with SEAM-29's message form" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Model.required!("url", nil) }

    assert_equal("url is required", error.message)
  end

  test "required! returns the value when it is present" do
    assert_equal(200, Dexpace::Model.required!("code", 200))
  end

  test "with re-validates on every supported Ruby" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Sample.build(code: 1).with(code: nil) }

    assert_equal("code is required", error.message)
  end

  test "with returns the receiver when nothing changes" do
    sample = Sample.build(code: 1)

    assert_same(sample, sample.with)
  end

  test "own returns a deep-frozen copy and leaves the caller's collection alone" do
    source = { "accept" => ["application/json"] }
    owned = Dexpace::Model.own(source)

    assert_predicate(owned, :frozen?)
    assert_predicate(owned.fetch("accept"), :frozen?)
    refute_predicate(source, :frozen?)
    refute_predicate(source.fetch("accept"), :frozen?)
  end

  test "own produces a Ractor-shareable value, which proves the freeze reached every level" do
    assert(Ractor.shareable?(Dexpace::Model.own({ "accept" => ["application/json"] })))
  end

  test "a model built from a live hash does not change when the caller mutates it afterwards" do
    source = { "accept" => ["application/json"] }
    owned = Dexpace::Model.own(source)
    source["accept"] << "text/plain"

    assert_equal(["application/json"], owned.fetch("accept"))
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/model_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Model`.

- [ ] **Step 3: Write `lib/dexpace/model.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "error/invalid_argument_error"

module Dexpace
  # The construction contract every core value type includes.
  #
  # Four operations, kept in one place because each of them is a rule that is otherwise remembered
  # per type: the field-named failure SEAM-29 fixes, the derivation that re-validates, and the two
  # ways a model takes ownership of something a caller handed it.
  module Model
    # HTTP-4 and SEAM-29: one helper, one error class, one message form, so a required-field
    # failure cannot be phrased differently by two models.
    def self.required!(name, value)
      raise InvalidArgumentError, "#{name} is required" if value.nil?

      value
    end

    # HTTP-5 and XCUT-15: the model owns its collections outright.
    #
    # `copy: true` is load-bearing. Ractor.make_shareable deep-freezes IN PLACE, and `dup` is
    # shallow, so make_shareable(hash.dup) would freeze the caller's live value arrays. With
    # copy: true the caller's object graph is untouched and the returned copy is deep-frozen,
    # which is what lets every accessor return the same frozen reference with no per-access
    # wrapper (design §4, §10.11).
    def self.own(collection)
      Ractor.make_shareable(collection, copy: true)
    end

    # A String a caller still holds a reference to is externally-mutable state XCUT-15 forbids a
    # model from aliasing.
    def self.frozen_string(value)
      value.frozen? ? value : value.dup.freeze
    end

    # HTTP-3's derivation for a type with no builder.
    #
    # This overrides Data#with deliberately. Verified on three interpreters: Data#with does not
    # call an `initialize` override on Ruby 3.2.11, and does on 3.4.10 and 4.0.6 -- so the
    # inherited method skips every HTTP-4/SEAM-29 check on the declared floor while passing on the
    # developer's Ruby. Routing through the type's own .build makes derivation uniform, and every
    # type gets it by including this module rather than by remembering.
    def with(**changes)
      return self if changes.empty?

      self.class.build(**to_h, **changes)
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/model.rbs`**

```rbs
module Dexpace
  module Model
    def self.required!: (String name, untyped value) -> untyped
    def self.own: [T] (T collection) -> T
    def self.frozen_string: (String value) -> String

    def with: (**untyped changes) -> untyped
  end
end
```

- [ ] **Step 5: Add the require to `lib/dexpace.rb`** and run the test

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/model_test.rb`
Expected: PASS, 7 runs.

- [ ] **Step 6: Run the same suite on the floor interpreter**

Run: `mise exec ruby@3.2.11 -- bundle exec ruby -w gems/dexpace-core/test/dexpace/model_test.rb`
Expected: PASS, 7 runs. **This is the run that proves the `#with` override earns its place** —
delete the override and this command fails while the 4.0 run passes.

- [ ] **Step 7: Write the failing test for the shared builder contract**

`SEAM-29` carries two MUSTs and the second one is easy to read past: as well as the uniform
`<name> is required` message, "a shared generic Builder contract (`build()` producing the target
type) MUST exist so generic composition helpers can accept any builder", with the conformance step
"a builder is assignable where the generic Builder contract is expected"
(`docs/product-spec/03-pluggable-seams-and-extension-model.md` §3.8).

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"

# SEAM-29's second MUST.
class DexpaceBuilderTest < DexpaceTestCase
  class Incomplete
    include Dexpace::Builder
  end

  test "a generic helper accepts every builder in the phase" do
    builders = [Dexpace::Headers.builder]

    assert_equal([Dexpace::Headers], Dexpace::Builder.build_all(builders).map(&:class))
  end

  test "a builder that does not implement build fails loudly rather than silently" do
    assert_raises(NotImplementedError) { Incomplete.new.build }
  end

  test "the generic helper rejects an object that is not a builder" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Builder.build_all([Object.new]) }
  end
end
```

The first test grows one entry per builder as Tasks 11, 13, 14 and 15 land — by the end it reads
`[Headers.builder, Query.builder, RequestOptions.builder, Request.builder, Response.builder]` and
asserts all five classes come back. That list is the conformance step, and it is the reason this
contract is a real module rather than a comment.

- [ ] **Step 8: Write `lib/dexpace/builder.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "error/invalid_argument_error"

module Dexpace
  # SEAM-29's shared generic builder contract: `#build` produces the target type, and a generic
  # composition helper can therefore accept any builder without knowing which model it makes.
  #
  # In Ruby the assignability half of that requirement is carried by the RBS interface
  # `Dexpace::_Builder[T]`, which is what a consumer's own `steep check` sees; this module is its
  # runtime half, so a helper can also refuse an object that never opted in.
  module Builder
    # The generic composition helper the requirement exists for.
    def self.build_all(builders)
      builders.map do |builder|
        unless builder.is_a?(Builder)
          raise InvalidArgumentError, "#{builder.class} does not implement the builder contract"
        end

        builder.build
      end
    end

    # Deliberately NotImplementedError, which is a ScriptError and not a StandardError: a builder
    # class that forgot #build is a programmer error and must not be swallowed by an ordinary
    # `rescue`.
    def build
      raise NotImplementedError, "#{self.class} must implement #build (SEAM-29)"
    end
  end
end
```

- [ ] **Step 9: Write `sig/dexpace/builder.rbs`**

```rbs
module Dexpace
  interface _Builder[T]
    def build: () -> T
  end

  module Builder
    def self.build_all: (Array[Builder] builders) -> Array[untyped]

    def build: () -> untyped
  end
end
```

- [ ] **Step 10: Add the require to `lib/dexpace.rb` and run the suite**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/builder_test.rb`
Expected: FAIL until Task 5 lands `Headers.builder`, then PASS, 3 runs. Run it again at the end of
Task 5; it is listed here because the contract belongs with `Model`, not with the first builder
that happens to need it.

---

## Task 3: `Dexpace::HeaderSyntax` — the byte-level validators

**Requirement IDs:** `HTTP-17`, `HTTP-18`, `HTTP-19`, `HTTP-20`; implements `XCUT-18` for phase 9.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/header_syntax.rb`,
  `gems/dexpace-core/sig/dexpace/http/header_syntax.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/header_syntax_test.rb`

**Interfaces:**
- Consumes: `Dexpace::InvalidArgumentError` (Task 1).
- Produces: `Dexpace::HeaderSyntax` with `.trim(name) -> String`, `.valid_name?(name) -> bool`,
  `.validate_name!(name) -> String` (returns the trimmed name),
  `.valid_outbound_value?(value) -> bool`, `.validate_outbound_value!(value, name:) -> String`,
  `.valid_inbound_value?(value) -> bool`, `.validate_inbound_value!(value, name:) -> String`, and
  `.escape(name) -> String`. Tasks 4, 5 and 9 call it; phase 8's transports call it again at the
  wire boundary (`DEF-25`).

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# HTTP-17, HTTP-18, HTTP-19, HTTP-20, XCUT-18. Every predicate here reads bytes, and these are the
# cases that prove why: "a\0" survives String#strip, and a character regexp raises on invalid
# UTF-8 instead of returning false.
class DexpaceHeaderSyntaxTest < DexpaceTestCase
  Syntax = Dexpace::HeaderSyntax

  test "trims surrounding SP and HTAB and stores the bare name" do
    assert_equal("X-Trace", Syntax.validate_name!("  X-Trace  "))
  end

  test "rejects a name whose only content is a NUL that String#strip would remove" do
    assert_raises(Dexpace::InvalidArgumentError) { Syntax.validate_name!("a\0") }
  end

  test "rejects a name with a trailing CR rather than trimming it away" do
    assert_raises(Dexpace::InvalidArgumentError) { Syntax.validate_name!("a\r") }
  end

  test "rejects a blank name" do
    assert_raises(Dexpace::InvalidArgumentError) { Syntax.validate_name!("   ") }
  end

  test "rejects a name carrying invalid UTF-8 with the SDK's error, not the regexp engine's" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Syntax.validate_name!("h\xE9der") }

    refute_match(/invalid byte sequence/, error.message)
  end

  test "rejects CRLF in a name, which is the request-splitting vector" do
    assert_raises(Dexpace::InvalidArgumentError) { Syntax.validate_name!("a\r\nb") }
  end

  test "accepts HTAB inside an outbound value" do
    assert_equal("a\tb", Syntax.validate_outbound_value!("a\tb", name: "X-Trace"))
  end

  test "rejects a non-ASCII byte in an outbound value" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Syntax.validate_outbound_value!("v\xC3\xA5lue", name: "X-Trace")
    end
  end

  test "accepts obs-text in an inbound value, which HTTP-19 relaxes" do
    value = "v\xC3\xA5lue"

    assert_equal(value, Syntax.validate_inbound_value!(value, name: "Content-Disposition"))
  end

  test "rejects CRLF in an inbound value, which HTTP-19 does not relax" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Syntax.validate_inbound_value!("a\r\nb", name: "Content-Disposition")
    end
  end

  test "rejects DEL in an inbound value" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Syntax.validate_inbound_value!("a\x7Fb", name: "Content-Disposition")
    end
  end

  test "never echoes the offending value in the message" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Syntax.validate_outbound_value!("secret\r\ntoken", name: "Authorization")
    end

    refute_includes(error.message, "secret")
    assert_includes(error.message, "Authorization")
  end

  test "escapes control bytes in an echoed name" do
    assert_equal('a\\x0D\\x0Ab', Syntax.escape("a\r\nb"))
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/header_syntax_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::HeaderSyntax`.

- [ ] **Step 3: Write `lib/dexpace/http/header_syntax.rb`**

The trim and the byte predicates are the whole file; everything else is a message.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error/invalid_argument_error"

module Dexpace
  # The header grammar, as bytes.
  #
  # Public API on purpose: HTTP-17/HTTP-18/XCUT-18 are re-checked at the model-to-wire boundary
  # inside every transport adapter (phase 8, DEF-25), and an adapter lives in a different gem, so
  # it must be able to reach the predicate without building a model. That re-check is what makes
  # the encapsulation gap of design §10.10 a correctness-of-shape gap rather than a
  # request-splitting one.
  module HeaderSyntax
    HTAB = 0x09
    SPACE = 0x20
    DEL = 0x7F

    module_function

    # HTTP-17's "surrounding whitespace is trimmed before validation" -- SP and HTAB only.
    #
    # Not String#strip, twice over. It also strips NUL, so "a\0" would trim to "a" and pass the
    # check that exists to reject NUL; and it raises Encoding::CompatibilityError on a name
    # carrying invalid UTF-8, which is an input this function must REJECT rather than crash on.
    # Trimming CR or LF would be worse still: "a\r\n" would become a valid name.
    def trim(name)
      bytes = name.b
      start = 0
      finish = bytes.bytesize
      start += 1 while start < finish && trimmable?(bytes.getbyte(start))
      finish -= 1 while finish > start && trimmable?(bytes.getbyte(finish - 1))
      bytes.byteslice(start, finish - start)
    end

    def trimmable?(byte)
      byte == SPACE || byte == HTAB
    end
    private_class_method :trimmable?

    # HTTP-17: no C0 control, no DEL, no byte >= 0x80, not blank. Every byte below 0x21 is
    # rejected, which covers the controls, SP and HTAB -- a header name has no interior space.
    def valid_name?(name)
      trimmed = trim(name)
      return false if trimmed.empty?

      trimmed.each_byte.none? { |byte| byte < 0x21 || byte == DEL || byte >= 0x80 }
    end

    # HTTP-18: HTAB plus printable ASCII 0x20-0x7E, and nothing else.
    def valid_outbound_value?(value)
      value.b.each_byte.all? { |byte| byte == HTAB || (byte >= SPACE && byte < DEL) }
    end

    # HTTP-19: the same rule with the non-ASCII clause relaxed, because RFC 7230 permits obs-text
    # in a field value and applying the outbound grammar to a response would silently drop a
    # legitimate Latin-1 Content-Disposition.
    def valid_inbound_value?(value)
      value.b.each_byte.all? { |byte| byte == HTAB || (byte >= SPACE && byte != DEL) }
    end

    def validate_name!(name)
      return trim(name) if valid_name?(name)

      raise InvalidArgumentError,
            "header name #{escape(name)} is not a valid field name (HTTP-17)"
    end

    def validate_outbound_value!(value, name:)
      return value if valid_outbound_value?(value)

      raise InvalidArgumentError,
            "value for header #{escape(name)} contains a byte no outbound header value may " \
            "carry (HTTP-18)"
    end

    def validate_inbound_value!(value, name:)
      return value if valid_inbound_value?(value)

      raise InvalidArgumentError,
            "value for header #{escape(name)} contains a control byte (HTTP-19)"
    end

    # HTTP-20: a rejected VALUE never appears in a message in any form, and a name is echoed with
    # its control bytes escaped, so a rejected header cannot inject a line into a log.
    def escape(name)
      escaped = name.to_s.b.each_byte.map do |byte|
        byte < SPACE || byte == DEL || byte >= 0x80 ? format("\\x%02X", byte) : byte.chr
      end
      escaped.join
    end
  end
end
```

Three shapes here are deliberate and a reviewer should not "clean them up": `module_function`
rather than `extend self` (`data-modeling/3775e9d7`); `.b` before every byte walk, including inside
`escape`, because that is the one path that runs *on* an input already known to be malformed; and
`private_class_method :trimmable?`, because a module function that appears in no `sig/` file is not
public API and `NFR-3`/`NFR-4` are only meaningful if the two agree. Everything else in this file
is declared in the signature below.

- [ ] **Step 4: Write `sig/dexpace/http/header_syntax.rbs`**

```rbs
module Dexpace
  module HeaderSyntax
    HTAB: Integer
    SPACE: Integer
    DEL: Integer

    def self.trim: (String name) -> String
    def self.valid_name?: (String name) -> bool
    def self.valid_outbound_value?: (String value) -> bool
    def self.valid_inbound_value?: (String value) -> bool
    def self.validate_name!: (String name) -> String
    def self.validate_outbound_value!: (String value, name: String) -> String
    def self.validate_inbound_value!: (String value, name: String) -> String
    def self.escape: (String name) -> String
  end
end
```

- [ ] **Step 5: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/header_syntax_test.rb`
Expected: PASS, 13 runs.

- [ ] **Step 6: Add a bounded property test and the surface assertion, then re-run**

```ruby
  test "the outbound grammar is strictly narrower than the inbound one" do
    sample(count: 128) do |rng|
      value = Array.new(rng.rand(0..8)) { rng.rand(0..255).chr }.join

      assert(Syntax.valid_inbound_value?(value)) if Syntax.valid_outbound_value?(value)
    end
  end

  test "the trim helper is internal, not public surface" do
    refute_respond_to(Syntax, :trimmable?)
  end
```

The property is what a single example cannot give: a refactor that inverts one comparison breaks
the implication before it breaks any of the thirteen cases above.

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/header_syntax_test.rb`
Expected: PASS, 15 runs.

---

## Task 4: `Dexpace::HeaderName`

**Requirement IDs:** `HTTP-21`, `HTTP-13`. **Deferred:** `HTTP-22` (`DEF-2`, no interning).

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/header_name.rb`,
  `gems/dexpace-core/sig/dexpace/http/header_name.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/header_name_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model` (Task 2), `Dexpace::HeaderSyntax` (Task 3).
- Produces: `Dexpace::HeaderName` — `.of(name)` accepting a `String` **or** a `HeaderName`,
  `.build(original:, folded: nil)`, `#original`, `#folded`, `#to_s`, and `#==`/`#eql?`/`#hash`
  folded. Task 5 uses `HeaderName.of(name).folded` for every string-keyed lookup.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# HTTP-21, HTTP-13.
class DexpaceHeaderNameTest < DexpaceTestCase
  test "compares by the folded form while keeping the original casing for the wire" do
    name = Dexpace::HeaderName.of("Content-Type")

    assert_equal(Dexpace::HeaderName.of("CONTENT-TYPE"), name)
    assert_equal("Content-Type", name.to_s)
  end

  test "hashes by the folded form, so two casings share a Hash slot" do
    table = { Dexpace::HeaderName.of("Content-Type") => 1 }

    assert_equal(1, table[Dexpace::HeaderName.of("content-type")])
  end

  test "folds with no locale argument, so a dotted I never becomes a dotless one" do
    assert_equal("if-none-match", Dexpace::HeaderName.of("If-None-Match").folded)
  end

  test "enforces HTTP-17's name validation" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::HeaderName.of("a\r\nb") }
  end

  test "accepts a HeaderName, so the string-keyed API interoperates" do
    name = Dexpace::HeaderName.of("Accept")

    assert_same(name, Dexpace::HeaderName.of(name))
  end

  test "trims before folding" do
    assert_equal("accept", Dexpace::HeaderName.of("  Accept  ").folded)
  end

  # .build validates; it is not a wrapper around `new`. Without an initialize override, `#with`
  # reaches the generated constructor, `HeaderName.of("Accept").with(original: "a\r\nb")`
  # succeeds, and the CRLF reaches the wire through a name that never met a validator.
  test "with re-validates and re-folds, so a derived name cannot carry CRLF" do
    name = Dexpace::HeaderName.of("Accept")

    assert_raises(Dexpace::InvalidArgumentError) { name.with(original: "a\r\nb") }
    assert_equal("content-type", name.with(original: "Content-Type").folded)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/header_name_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::HeaderName`.

- [ ] **Step 3: Write `lib/dexpace/http/header_name.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "header_syntax"

module Dexpace
  # A header name that compares by its case-folded form and emits its original casing (HTTP-21).
  class HeaderName < Data.define(:original, :folded)
    include Model
    private_class_method :new

    # `folded` is accepted and ignored: it is derived, and #with passes every member back through
    # here. Deriving rather than trusting is what keeps `.with(original: "CONTENT-TYPE")` from
    # producing a name whose fold no longer matches its casing.
    def self.build(original:, folded: nil)
      new(original: original, folded: folded)
    end

    def self.of(name)
      return name if name.is_a?(HeaderName)

      build(original: name)
    end

    # The validating constructor. HTTP-13's fold is `downcase` with NO argument, ever: Ruby's fold
    # is opt-in-locale -- "I".downcase(:turkic) is "ı" -- and the repository-wide cop rejects the
    # argument form, so the ASCII/invariant guarantee is enforced rather than assumed. The fold
    # never meets a non-ASCII byte anyway, because validate_name! rejected one first; relaxing
    # HTTP-17 would therefore break HTTP-13, which is why that dependency is stated here.
    def initialize(original:, folded: nil)
      trimmed = HeaderSyntax.validate_name!(Model.required!("header name", original))
      super(original: Model.frozen_string(trimmed), folded: trimmed.downcase.freeze)
    end

    def to_s
      original
    end

    # Data generates equality over BOTH members, which would make "Accept" and "accept" unequal
    # and violate HTTP-21. Folded-only comparison is the observable contract; the original casing
    # is carried for emission and takes no part in it (api-design/e4fa3438 permits the override
    # with this comment).
    def ==(other)
      other.is_a?(HeaderName) && folded == other.folded
    end
    alias eql? ==

    def hash
      folded.hash
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/http/header_name.rbs`**

```rbs
module Dexpace
  class HeaderName
    include Model

    attr_reader original: String
    attr_reader folded: String

    def self.build: (original: String, ?folded: String?) -> HeaderName
    def self.of: (String | HeaderName name) -> HeaderName
    def to_s: () -> String
    def ==: (untyped other) -> bool
    def eql?: (untyped other) -> bool
    def hash: () -> Integer
  end
end
```

RBS cannot see `Data.define`'s generated readers, which is why they are written out here — the
same reason `NFR-4` pairs the signature diff with a runtime surface snapshot (design §9.1).

- [ ] **Step 5: Add the require to `lib/dexpace.rb`** and run the test

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/header_name_test.rb`
Expected: PASS, 7 runs.

---

## Task 5: `Dexpace::Headers` and `Headers::Builder`

**Requirement IDs:** `HTTP-13`–`HTTP-21`, plus `HTTP-3`, `HTTP-4`, `HTTP-5` for this model, and
`SEAM-29`'s builder contract.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/headers.rb`,
  `gems/dexpace-core/lib/dexpace/http/headers/builder.rb`, and the two `sig/` mirrors
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/headers_test.rb`,
  `gems/dexpace-core/test/dexpace/http/headers/builder_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`, `Dexpace::Builder`, `Dexpace::HeaderSyntax`, `Dexpace::HeaderName`.
- Produces: `Dexpace::Headers` — `.build(values:, casing:, direction: :outbound)`, `.builder`,
  `.inbound_builder`, `Headers::EMPTY`, `Headers::DIRECTIONS`, `#[](name) -> Array[String]?`,
  `#include?(name)`, `#names -> Array[String]`, `#entries -> Array[[String, String]]`,
  `#each_entry`, `#size`, `#empty?`, `#direction`, `#new_builder`, `#==`/`#eql?`/`#hash`; and
  `Dexpace::Headers::Builder` — `.new(direction:)`, `#direction`, `#add(name, value)`,
  `#set(name, value)`, `#remove(name)`, `#build -> Headers`. Tasks 14 and 15 consume both.

- [ ] **Step 1: Write the failing tests**

`headers_test.rb` — the model's contract, including the two accessor tiers `HTTP-5` names and the
validation `.build` owes a caller who never met a builder:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# HTTP-3, HTTP-5, HTTP-13, HTTP-14, HTTP-15, HTTP-16, HTTP-17, HTTP-18, HTTP-19, HTTP-21.
class DexpaceHeadersTest < DexpaceTestCase
  def build_headers
    Dexpace::Headers.builder.add("Content-Type", "application/json").add("Accept", "*/*").build
  end

  test "resolves a name added under one casing through any other" do
    assert_equal(["application/json"], build_headers["CONTENT-TYPE"])
  end

  test "iterates distinct names in insertion order with their original casing" do
    assert_equal(%w[Content-Type Accept], build_headers.names)
  end

  # HTTP-5, in its two tiers: "name-set and entry-set accessors return a fresh per-call snapshot;
  # per-name value-list accessors return the instance's own list."
  test "the name set and the entry set are a fresh frozen snapshot on every call" do
    headers = build_headers

    assert_predicate(headers.names, :frozen?)
    refute_same(headers.names, headers.names)
    assert_predicate(headers.entries, :frozen?)
    refute_same(headers.entries, headers.entries)
  end

  test "a per-name value list is the model's own frozen list, not a copy" do
    headers = build_headers

    assert_predicate(headers["Accept"], :frozen?)
    assert_same(headers["Accept"], headers["Accept"])
    assert_raises(FrozenError) { headers["Accept"] << "text/plain" }
  end

  test "a value list obtained before a builder mutation is unchanged after it" do
    headers = build_headers
    snapshot = headers["Accept"]
    builder = headers.new_builder
    builder.add("Accept", "text/plain")

    assert_equal(["*/*"], snapshot)
    assert_equal(["*/*"], headers["Accept"])
  end

  test "new_builder does not alias the model's value lists" do
    headers = build_headers
    derived = headers.new_builder.add("Accept", "text/plain").build

    assert_equal(["*/*"], headers["Accept"])
    assert_equal(["*/*", "text/plain"], derived["Accept"])
  end

  test "new_builder carries the direction, so an inbound model derives an inbound builder" do
    inbound = Dexpace::Headers.inbound_builder.add("Content-Disposition", "v\xC3\xA5lue").build

    assert_equal(:inbound, inbound.direction)
    assert_equal(:inbound, inbound.new_builder.direction)
    derived = inbound.new_builder.add("X-Other", "v\xC3\xA5lue").build

    assert_equal(["v\xC3\xA5lue"], derived["X-Other"])
  end

  test "an outbound model derives an outbound builder, which still refuses obs-text" do
    derived = build_headers.new_builder

    assert_equal(:outbound, derived.direction)
    assert_raises(Dexpace::InvalidArgumentError) { derived.add("X-Other", "v\xC3\xA5lue") }
  end

  # HTTP-2's gap is real, so .build validates rather than trusting its caller: it is public API and
  # a transport, a fixture or a later phase can reach it without ever meeting a Builder.
  test "build rejects a name no builder would have accepted" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Headers.build(values: { "a\r\nb" => ["x"] }, casing: { "a\r\nb" => "a\r\nb" })
    end
  end

  test "build rejects a value no builder would have accepted" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Headers.build(values: { "x-trace" => ["a\r\nb"] },
                             casing: { "x-trace" => "X-Trace" })
    end
  end

  test "build rejects a stored name with no matching original casing" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Headers.build(values: { "accept" => ["*/*"] }, casing: { "other" => "Other" })
    end
  end

  # The two hashes are one collection seen twice, so the check is a set equality: a casing entry
  # with no value list would make #names report a header that #size and #[] do not have.
  test "build rejects a casing entry that carries no values" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Headers.build(values: {}, casing: { "x-a" => "X-A" })
    end
  end

  test "equality is by folded name and value, so casing and direction take no part" do
    assert_equal(Dexpace::Headers.builder.add("Accept", "*/*").build,
                 Dexpace::Headers.builder.add("ACCEPT", "*/*").build)
    assert_equal(Dexpace::Headers.builder.add("Accept", "*/*").build.hash,
                 Dexpace::Headers.inbound_builder.add("accept", "*/*").build.hash)
  end

  test "is Ractor-shareable, which proves the deep freeze reached every value list" do
    assert(Ractor.shareable?(build_headers))
  end

  test "an absent name reads as nil and is not contained" do
    headers = build_headers

    assert_nil(headers["X-Absent"])
    refute(headers.include?("X-Absent"))
  end

  test "does not expose its internal hashes" do
    refute_respond_to(build_headers, :values)
    refute_respond_to(build_headers, :casing)
  end
end
```

`headers/builder_test.rb` — the mutation contract, and the partial-state rule:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# HTTP-14, HTTP-15, HTTP-18, HTTP-19, HTTP-20, SEAM-29.
class DexpaceHeadersBuilderTest < DexpaceTestCase
  test "add appends and set replaces the whole list" do
    builder = Dexpace::Headers.builder.add("Accept", "a").add("Accept", "b")

    assert_equal(%w[a b], builder.build["Accept"])
    assert_equal(["c"], builder.set("Accept", "c").build["Accept"])
  end

  test "setting a value to nil removes the header entirely" do
    headers = Dexpace::Headers.builder.add("Accept", "a").set("Accept", nil).build

    refute(headers.include?("Accept"))
    assert_empty(headers.names)
  end

  test "an outbound builder refuses obs-text and an inbound builder accepts it" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Headers.builder.add("Content-Disposition", "v\xC3\xA5lue")
    end
    assert_equal(["v\xC3\xA5lue"],
                 Dexpace::Headers.inbound_builder
                   .add("Content-Disposition", "v\xC3\xA5lue").build["Content-Disposition"])
  end

  test "both directions refuse CRLF in a value" do
    [Dexpace::Headers.builder, Dexpace::Headers.inbound_builder].each do |builder|
      assert_raises(Dexpace::InvalidArgumentError) { builder.add("X-Trace", "a\r\nb") }
    end
  end

  # testing/62f8f4ec: a rejected entry leaves no partial state behind. The casing table is the
  # half that is easy to get wrong -- recording the name before validating the value leaves an
  # orphan entry that #names would report for a header the model does not carry.
  test "a rejected value leaves the builder usable and records no orphan name" do
    builder = Dexpace::Headers.builder.add("Accept", "*/*")

    assert_raises(Dexpace::InvalidArgumentError) { builder.add("X-Trace", "a\r\nb") }

    built = builder.build

    assert_equal(["Accept"], built.names)
    refute(built.include?("X-Trace"))
    assert_equal(["*/*"], builder.add("Accept", "text/plain").build["Accept"].first(1))
  end

  test "a rejected name leaves no partial state either" do
    builder = Dexpace::Headers.builder.add("Accept", "*/*")

    assert_raises(Dexpace::InvalidArgumentError) { builder.add("a\r\nb", "x") }
    assert_equal(["Accept"], builder.build.names)
  end

  test "the error message names the header and never echoes the value" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Headers.builder.add("Authorization", "Bearer secret\r\ntoken")
    end

    assert_includes(error.message, "Authorization")
    refute_includes(error.message, "secret")
  end

  test "building twice yields two independent models" do
    builder = Dexpace::Headers.builder.add("Accept", "a")
    first = builder.build
    builder.add("Accept", "b")

    assert_equal(["a"], first["Accept"])
    assert_equal(%w[a b], builder.build["Accept"])
  end

  test "implements the shared builder contract" do
    assert_kind_of(Dexpace::Builder, Dexpace::Headers.builder)
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/headers_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Headers`.

- [ ] **Step 3: Write `lib/dexpace/http/headers.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "header_name"
require_relative "header_syntax"

module Dexpace
  # A case-insensitive, multi-value, insertion-ordered header collection (HTTP-13 - HTTP-21).
  #
  # Two parallel frozen hashes rather than one: `values` is keyed by the folded name for lookup,
  # containment, equality and hashing, and `casing` carries the original casing HTTP-21 requires
  # for wire emission. Both are deep-frozen once at construction, and both readers are private --
  # the model's public surface is the accessors below, not its internals.
  #
  # `direction` is a member because HTTP-19's lenient inbound grammar is a property of the model,
  # not of the builder that happened to make it: without it, #new_builder on a response's headers
  # would hand back a strict builder that rejects the obs-text the model already holds.
  class Headers < Data.define(:values, :casing, :direction)
    include Model
    private_class_method :new
    private :values, :casing

    DIRECTIONS = %i[outbound inbound].freeze

    def self.build(values:, casing:, direction: :outbound)
      new(values: Model.own(values), casing: Model.own(casing), direction: direction)
    end

    def self.builder
      Builder.new(direction: :outbound)
    end

    def self.inbound_builder
      Builder.new(direction: :inbound)
    end

    # HTTP-2's gap makes this necessary rather than paranoid: `.build` is public, `new` is
    # reachable through `send`, and #with routes every derivation back through `.build`. A model
    # whose only validation lived in Builder#add would accept a CRLF name from any of the three.
    def initialize(values:, casing:, direction:)
      validate_direction!(direction)
      validate_names!(values, casing)
      validate_values!(values, casing, direction)
      super
    end

    # HTTP-5, second tier: "per-name value-list accessors return the instance's own list". The
    # list is already frozen, so returning it is both cheaper and stricter than copying.
    def [](name)
      values[HeaderName.of(name).folded]
    end

    def include?(name)
      values.key?(HeaderName.of(name).folded)
    end

    # HTTP-5, first tier: "name-set and entry-set accessors return a fresh per-call snapshot".
    # Hash#values allocates, and the freeze makes the snapshot read-only rather than merely new.
    def names
      casing.values.freeze
    end

    def entries
      values.flat_map { |folded, list| list.map { |value| [casing.fetch(folded), value].freeze } }
            .freeze
    end

    def each_entry(&block)
      return enum_for(:each_entry) unless block

      entries.each(&block)
      self
    end

    def size
      values.size
    end

    def empty?
      values.empty?
    end

    def new_builder
      Builder.new(direction: direction, values: values, casing: casing)
    end

    # HTTP-13 folds names for "storage, lookup, containment, mutation, removal, equality, and
    # hashing", so equality is over the folded values alone: two collections differing only in the
    # casing they will emit, or in the direction that validated them, are the same headers. Data
    # would generate equality over all three members and get that wrong (api-design/e4fa3438
    # permits the override with this comment).
    def ==(other)
      other.is_a?(Headers) && values == other.send(:values)
    end
    alias eql? ==

    def hash
      values.hash
    end

    private

    def validate_direction!(direction)
      return if DIRECTIONS.include?(direction)

      raise InvalidArgumentError, "direction must be one of: #{DIRECTIONS.join(", ")}"
    end

    # Set equality, not a one-way walk: a casing entry with no value list is not merely untidy,
    # it makes #names report a header #size and #[] do not have.
    def validate_names!(values, casing)
      orphans = casing.keys - values.keys
      unless orphans.empty?
        raise InvalidArgumentError,
              "casing carries #{HeaderSyntax.escape(orphans.first)}, which holds no values"
      end

      values.each_key do |folded|
        HeaderSyntax.validate_name!(folded)
        original = casing[folded]
        next if !original.nil? && HeaderName.of(original).folded == folded

        raise InvalidArgumentError,
              "header #{HeaderSyntax.escape(folded)} has no matching original casing"
      end
    end

    def validate_values!(values, casing, direction)
      values.each do |folded, list|
        name = casing.fetch(folded)
        list.each do |value|
          if direction == :inbound
            HeaderSyntax.validate_inbound_value!(value, name: name)
          else
            HeaderSyntax.validate_outbound_value!(value, name: name)
          end
        end
      end
    end

    EMPTY = build(values: {}, casing: {})
  end
end
```

**`.build` validates; it is not a wrapper around `new`.** That is the rule for every `Data` type in
this phase (design's construction-contract section), and `Headers` is where it earns its keep:
`.build` is public API, `#with` routes derivation through it, and `send(:new, …)` reaches the
generated constructor whatever anyone writes — so validation that lived only in `Builder#add`
would be validation three callers can walk around.

**`HTTP-5` has two tiers and this file implements both**, quoting appendix C: "Name-set and
entry-set accessors return a fresh per-call snapshot; per-name value-list accessors return the
instance's own list." So `#names` and `#entries` allocate and freeze per call, and `#[]` returns
the model's own frozen list. Design §4's summary sentence — "the same frozen reference is returned
from every accessor" — is the *outcome* for the second tier only; the normative text is narrower
and it wins (Deviation Ledger P1-7).

- [ ] **Step 4: Write `lib/dexpace/http/headers/builder.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../builder"
require_relative "../header_syntax"

module Dexpace
  class Headers
    class Builder
      include Dexpace::Builder

      attr_reader :direction

      def initialize(direction: :outbound, values: {}, casing: {})
        @direction = direction
        @values = values.transform_values(&:dup)
        @casing = casing.dup
      end

      # Validate BEFORE recording. Recording the casing first leaves an orphan entry behind when
      # the value is rejected, and #names would then report a header the model does not carry --
      # a partial side effect testing/62f8f4ec exists to catch.
      def add(name, value)
        header = HeaderName.of(name)
        validated = validate_value(value, header)
        record(header)
        @values[header.folded] = (@values[header.folded] || []) << validated
        self
      end

      def set(name, value)
        return remove(name) if value.nil?

        header = HeaderName.of(name)
        validated = validate_value(value, header)
        record(header)
        @values[header.folded] = [validated]
        self
      end

      def remove(name)
        folded = HeaderName.of(name).folded
        @values.delete(folded)
        @casing.delete(folded)
        self
      end

      def build
        Headers.build(values: @values, casing: @casing, direction: @direction)
      end

      private

      def record(header)
        @casing[header.folded] ||= header.original
      end

      # HTTP-20: the message names the header (trimmed, and escaped by HeaderSyntax) and never
      # echoes the value.
      def validate_value(value, header)
        Model.required!("header value", value)
        if @direction == :inbound
          HeaderSyntax.validate_inbound_value!(value, name: header.original)
        else
          HeaderSyntax.validate_outbound_value!(value, name: header.original)
        end
      end
    end
  end
end
```

- [ ] **Step 5: Write the two `sig/` mirrors**, `sig/dexpace/http/headers.rbs` and
  `sig/dexpace/http/headers/builder.rbs`, declaring every public method named in the Interfaces
  block. The two members that are `private` in Ruby — `values` and `casing` — go under RBS's own
  `private` modifier, so `steep check` still types the internals while the surface manifest records
  only the public accessors. Verified against `rbs` 3.8.0:

```rbs
module Dexpace
  class Headers
    include Model

    DIRECTIONS: Array[Symbol]
    EMPTY: Headers

    attr_reader direction: Symbol

    def self.build: (values: Hash[String, Array[String]], casing: Hash[String, String],
                     ?direction: Symbol) -> Headers
    def self.builder: () -> Headers::Builder
    def self.inbound_builder: () -> Headers::Builder

    def []: (String | HeaderName name) -> Array[String]?
    def include?: (String | HeaderName name) -> bool
    def names: () -> Array[String]
    def entries: () -> Array[[String, String]]
    def each_entry: () { ([String, String]) -> void } -> Headers
                  | () -> Enumerator[[String, String], Headers]
    def size: () -> Integer
    def empty?: () -> bool
    def new_builder: () -> Headers::Builder
    def ==: (untyped other) -> bool
    def eql?: (untyped other) -> bool
    def hash: () -> Integer

    private

    attr_reader values: Hash[String, Array[String]]
    attr_reader casing: Hash[String, String]
  end
end
```

- [ ] **Step 6: Add both requires to `lib/dexpace.rb`, in dependency order** — `headers/builder`
  after `headers`, because `Headers::EMPTY` is evaluated at require time and the builder reopens
  the class.

- [ ] **Step 7: Run every suite that now has its dependencies**

Run, in order:

```bash
bundle exec ruby -w gems/dexpace-core/test/dexpace/http/headers_test.rb
bundle exec ruby -w gems/dexpace-core/test/dexpace/http/headers/builder_test.rb
bundle exec ruby -w gems/dexpace-core/test/dexpace/builder_test.rb
```

Expected: PASS, 16 runs, 9 runs and 3 runs. The third is Task 2's builder-contract suite, which
could not pass until a real builder existed.

---

## Task 6: `Dexpace::Status`

**Requirement IDs:** `HTTP-10`, `HTTP-11`, `HTTP-12`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/status.rb`,
  `gems/dexpace-core/sig/dexpace/http/status.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/status_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`.
- Produces: `Dexpace::Status` — `.of(code)`, `.build(code:)`, `.canonical_name(code) -> String?`,
  `#code`, `#canonical_name`, `#informational?`, `#success?`, `#redirect?`, `#client_error?`,
  `#server_error?`, `#error?`, and the named constants `Status::OK`, `Status::CREATED`,
  `Status::NO_CONTENT`, `Status::NOT_MODIFIED`, `Status::BAD_REQUEST`, `Status::UNAUTHORIZED`,
  `Status::FORBIDDEN`, `Status::NOT_FOUND`, `Status::REQUEST_TIMEOUT`,
  `Status::TOO_MANY_REQUESTS`, `Status::INTERNAL_SERVER_ERROR`, `Status::NOT_IMPLEMENTED`,
  `Status::BAD_GATEWAY`, `Status::SERVICE_UNAVAILABLE`, `Status::GATEWAY_TIMEOUT`. Task 15 uses it.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# HTTP-10, HTTP-11, HTTP-12.
class DexpaceStatusTest < DexpaceTestCase
  test "maps a recognised code to a status carrying its canonical name" do
    assert_equal("OK", Dexpace::Status.of(200).canonical_name)
  end

  test "maps a vendor code without raising and without a name" do
    [499, 520, 526, 530, 599].each do |code|
      status = Dexpace::Status.of(code)

      assert_equal(code, status.code)
      assert_nil(status.canonical_name)
    end
  end

  test "is equal to the canonical constant for the same code and hashes identically" do
    status = Dexpace::Status.of(200)

    assert_equal(Dexpace::Status::OK, status)
    assert_equal(Dexpace::Status::OK.hash, status.hash)
  end

  test "classifies by range" do
    assert_predicate(Dexpace::Status.of(100), :informational?)
    assert_predicate(Dexpace::Status.of(204), :success?)
    assert_predicate(Dexpace::Status.of(301), :redirect?)
    assert_predicate(Dexpace::Status.of(404), :client_error?)
    assert_predicate(Dexpace::Status.of(503), :server_error?)
  end

  test "treats 400 through 599 as errors and nothing else" do
    assert_predicate(Dexpace::Status.of(400), :error?)
    assert_predicate(Dexpace::Status.of(599), :error?)
    refute_predicate(Dexpace::Status.of(399), :error?)
  end

  test "rejects a code outside the protocol's range as a caller mistake" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Status.of(99) }
  end
end
```

Add one `#sample` property test: for 256 codes drawn from `100..599`, `Status.of(code).code` equals
the input and no call raises — `HTTP-10`'s totality stated as a property rather than five examples.

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/status_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Status`.

- [ ] **Step 3: Write `lib/dexpace/http/status.rb`**

The member list is the design decision; everything else follows from it.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"

module Dexpace
  # An HTTP status code, total over the protocol's range (HTTP-10 - HTTP-12).
  #
  # ONE member, and that is HTTP-12 rather than minimalism: two Status values must be equal iff
  # their codes are equal, with the name taking no part. A Data.define(:code, :name) would generate
  # equality over both members and violate that silently -- a vendor 520 with no name would not
  # equal a 520 someone had named. The canonical name is a lookup, which is also what HTTP-10's
  # "a separate lookup MUST let callers distinguish recognized codes" asks for.
  class Status < Data.define(:code)
    include Model
    private_class_method :new

    CANONICAL_NAMES = {
      100 => "Continue", 101 => "Switching Protocols",
      200 => "OK", 201 => "Created", 202 => "Accepted", 204 => "No Content",
      206 => "Partial Content",
      301 => "Moved Permanently", 302 => "Found", 303 => "See Other", 304 => "Not Modified",
      307 => "Temporary Redirect", 308 => "Permanent Redirect",
      400 => "Bad Request", 401 => "Unauthorized", 403 => "Forbidden", 404 => "Not Found",
      405 => "Method Not Allowed", 406 => "Not Acceptable", 408 => "Request Timeout",
      409 => "Conflict", 410 => "Gone", 412 => "Precondition Failed",
      413 => "Content Too Large", 415 => "Unsupported Media Type",
      422 => "Unprocessable Content", 425 => "Too Early", 428 => "Precondition Required",
      429 => "Too Many Requests", 431 => "Request Header Fields Too Large",
      500 => "Internal Server Error", 501 => "Not Implemented", 502 => "Bad Gateway",
      503 => "Service Unavailable", 504 => "Gateway Timeout",
      505 => "HTTP Version Not Supported", 507 => "Insufficient Storage",
      511 => "Network Authentication Required",
    }.freeze

    def self.build(code:)
      new(code: code)
    end

    # Idempotent on a Status, like Method.of and HeaderName.of: #with and Response#initialize both
    # pass whatever they were given straight back in, and a factory that only accepts raw input
    # makes every caller write the type check instead.
    def self.of(code)
      return code if code.is_a?(Status)

      build(code: code)
    end

    def self.canonical_name(code)
      CANONICAL_NAMES[code]
    end

    def initialize(code:)
      Model.required!("code", code)
      unless code.is_a?(Integer) && code.between?(100, 599)
        raise InvalidArgumentError, "code must be an integer status code between 100 and 599"
      end

      super
    end

    def canonical_name
      CANONICAL_NAMES[code]
    end

    def informational? = code.between?(100, 199)
    def success? = code.between?(200, 299)
    def redirect? = code.between?(300, 399)
    def client_error? = code.between?(400, 499)
    def server_error? = code.between?(500, 599)
    def error? = code.between?(400, 599)

    OK = of(200)
    CREATED = of(201)
    NO_CONTENT = of(204)
    NOT_MODIFIED = of(304)
    BAD_REQUEST = of(400)
    UNAUTHORIZED = of(401)
    FORBIDDEN = of(403)
    NOT_FOUND = of(404)
    REQUEST_TIMEOUT = of(408)
    TOO_MANY_REQUESTS = of(429)
    INTERNAL_SERVER_ERROR = of(500)
    NOT_IMPLEMENTED = of(501)
    BAD_GATEWAY = of(502)
    SERVICE_UNAVAILABLE = of(503)
    GATEWAY_TIMEOUT = of(504)
  end
end
```

`.build` validates through the `initialize` override — `Status::OK.with(code: nil)` raises — which
is the phase-wide rule stated in Global Constraints: no `.build` is a bare `new` wrapper.

`HTTP-10` says construction is total over "any code"; the 100–599 guard is the port's reading and
is not a narrowing of it — a vendor code like nginx's 499 or Cloudflare's 520–526 and 530 is inside
the range and constructs cleanly with no name, which is exactly the requirement's stated rationale.
An `Integer` outside the protocol's own range is a caller mistake, not a vendor code.

- [ ] **Step 4: Write `sig/dexpace/http/status.rbs`** — the member, the frozen table as
  `Hash[Integer, String]`, the two factories, the lookup in both forms, the six predicates and the
  fifteen constants.

- [ ] **Step 5: Add the require and run the test**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/status_test.rb`
Expected: PASS, 7 runs.

---

## Task 7: `Dexpace::Method`

**Requirement IDs:** `HTTP-9`, and the classification `HTTP-7` consumes.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/method.rb`,
  `gems/dexpace-core/sig/dexpace/http/method.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/method_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`.
- Produces: `Dexpace::Method` — `.of(token)`, `.build(token:)`, `#token`, `#to_s`, `#idempotent?`,
  `#body_forbidden?`, the frozen sets `Method::IDEMPOTENT` and `Method::BODY_FORBIDDEN`, and the
  constants `Method::GET`, `HEAD`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`, `TRACE`, `CONNECT`.
  Task 14 asks `#body_forbidden?`; phase 6 derives its retry allow-list from `IDEMPOTENT`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# HTTP-9. The idempotent set is single-sourced here; phase 6's retry allow-list and replay-safety
# gate both derive from it and neither restates it.
class DexpaceMethodTest < DexpaceTestCase
  test "the canonical wire token is the uppercase name" do
    %w[GET HEAD POST PUT PATCH DELETE OPTIONS TRACE CONNECT].each do |token|
      assert_equal(token, Dexpace::Method.of(token.downcase).token)
    end
  end

  test "classifies exactly GET HEAD OPTIONS PUT DELETE as idempotent" do
    idempotent = %w[GET HEAD OPTIONS PUT DELETE]

    idempotent.each { |token| assert_predicate(Dexpace::Method.of(token), :idempotent?) }
    %w[POST PATCH CONNECT TRACE].each do |token|
      refute_predicate(Dexpace::Method.of(token), :idempotent?)
    end
  end

  test "classifies exactly GET HEAD TRACE CONNECT as forbidding a body" do
    %w[GET HEAD TRACE CONNECT].each do |token|
      assert_predicate(Dexpace::Method.of(token), :body_forbidden?)
    end
    %w[POST PUT PATCH DELETE OPTIONS].each do |token|
      refute_predicate(Dexpace::Method.of(token), :body_forbidden?)
    end
  end

  test "accepts an extension method that is a valid token" do
    assert_equal("PROPFIND", Dexpace::Method.of("propfind").token)
  end

  test "rejects a token carrying a separator or a control byte" do
    ["GET POST", "GET\r\n", "GE T", ""].each do |token|
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Method.of(token) }
    end
  end

  # The byte check runs before `upcase`, which would otherwise raise a raw ArgumentError from
  # inside Ruby and escape `rescue Dexpace::Error`.
  test "rejects a token carrying invalid UTF-8 with the SDK's own error" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Method.of("GE\xE9T") }

    refute_match(/invalid byte sequence/, error.message)
  end

  test "with re-validates, so a derived method cannot carry a separator" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Method::GET.with(token: "GE T") }
  end

  # Visibility is asserted with respond_to?, never with assert_predicate. Minitest's
  # assert_predicate calls __send__, which sends straight past `private`: verified that a private
  # predicate passes assert_predicate on Minitest 5.25.1 (Ruby 3.2.11) and 6.0.0 (Ruby 4.0.6)
  # alike, and that refute_predicate catches it on 6.0.0 only. Task 14 calls
  # `method.body_forbidden?` with an explicit receiver, so a misplaced `private` here breaks a
  # later task, and on the declared floor no other assertion in this file would notice.
  test "the classification predicates are public, because a Request asks them by receiver" do
    %i[to_s idempotent? body_forbidden?].each do |name|
      assert_respond_to(Dexpace::Method::GET, name)
    end
    refute_respond_to(Dexpace::Method::GET, :token?)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/method_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Method`.

- [ ] **Step 3: Write `lib/dexpace/http/method.rb`**

The token grammar and the two sets are the content:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"

module Dexpace
  # An HTTP method token (HTTP-9).
  #
  # `upcase` with no argument: the same locale rule as HTTP-13's fold, enforced by the same cop.
  # Because the token is upcased at construction and validated against the RFC 7230 token grammar,
  # "each method's canonical wire token equals its uppercase name" holds structurally rather than
  # through a lookup table -- an extension method gets the guarantee too.
  class Method < Data.define(:token)
    include Model
    private_class_method :new

    # RFC 7230 tchar, as BYTES. Not a regexp: `String#upcase` and `Regexp#match?` both raise
    # ArgumentError on a String carrying invalid UTF-8, and an ArgumentError raised from inside
    # Ruby escapes `rescue Dexpace::Error` -- a validator that crashes has not rejected its input.
    # tchar is ASCII-only, so a byte test is exact as well as total.
    TCHAR = ("0".."9").to_a.concat(("A".."Z").to_a, ("a".."z").to_a,
                                   %w[! # $ % & ' * + - . ^ _ ` | ~])
                      .map { |char| char.ord }.freeze

    # HTTP-9's single source. Phase 6's configurable retry allow-list and its inherent
    # replay-safety gate both derive from this set; neither writes the five names again.
    IDEMPOTENT = %w[GET HEAD OPTIONS PUT DELETE].freeze

    # The classification HTTP-7 consumes: a body on one of these is rejected at construction
    # rather than deferred to a transport, because reference transports diverge (one throws, one
    # silently drops the body) and rejecting once yields one portable behaviour.
    BODY_FORBIDDEN = %w[GET HEAD TRACE CONNECT].freeze

    def self.build(token:)
      new(token: token)
    end

    def self.of(token)
      return token if token.is_a?(Method)

      build(token: token)
    end

    # Byte check first, then `upcase` -- never the other way round. On "GET\xE9" the upcase would
    # raise ArgumentError before any rule of this SDK had a chance to reject the token.
    def initialize(token:)
      text = Model.required!("token", token).to_s
      unless token?(text)
        raise InvalidArgumentError, "method must be a valid HTTP token (RFC 7230 tchar)"
      end

      super(token: Model.frozen_string(text.upcase))
    end

    def to_s
      token
    end

    def idempotent?
      IDEMPOTENT.include?(token)
    end

    # HTTP-7's gate, asked of the method rather than re-listed in Request::Builder.
    def body_forbidden?
      BODY_FORBIDDEN.include?(token)
    end

    # `private` guards this one method and nothing above it. Placement is load-bearing: a
    # `private` sitting above #to_s, #idempotent? and #body_forbidden? makes all three private,
    # and Request#initialize calls `method.body_forbidden?` with an explicit receiver, so the
    # phase fails at Task 14 with a NoMethodError. Measured, with the mistake in place: on 4.0.6
    # (Minitest 6.0.0) two `refute_predicate` cases catch it; on the 3.2.11 floor (Minitest
    # 5.25.1) nothing in this suite does, because assert_predicate and refute_predicate both go
    # through __send__ there. That is why the visibility test below uses respond_to?.
    private

    def token?(text)
      bytes = text.b
      !bytes.empty? && bytes.each_byte.all? { |byte| TCHAR.include?(byte) }
    end

    GET = of("GET")
    HEAD = of("HEAD")
    POST = of("POST")
    PUT = of("PUT")
    PATCH = of("PATCH")
    DELETE = of("DELETE")
    OPTIONS = of("OPTIONS")
    TRACE = of("TRACE")
    CONNECT = of("CONNECT")
  end
end
```

`.build` validates through the `initialize` override, so `Method::GET.with(token: "GE T")` raises
rather than producing a model no builder would have made — the same rule every `Data` type in this
phase follows.

**`Dexpace::Method` shadows `::Method` inside `module Dexpace`**, the same hazard phase 0 recorded
for `Dexpace::Serde::JSON` and `Dexpace::Async::Thread`. Inside core, a bare `Method` means this
class; write `::Method` when you mean Ruby's. Outside core it is inert — a consumer's top-level
`Method` still resolves to Ruby's, even after `include Dexpace`, because `Object`'s own constants
win over an included module's. The entry-file YARD block says both halves.

- [ ] **Step 4: Write `sig/dexpace/http/method.rbs`** and add the require to `lib/dexpace.rb`.

- [ ] **Step 5: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/method_test.rb`
Expected: PASS, 8 runs.

---

## Task 8: `Dexpace::Protocol`

**Requirement IDs:** `HTTP-33`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/protocol.rb`,
  `gems/dexpace-core/sig/dexpace/http/protocol.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/protocol_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`.
- Produces: `Dexpace::Protocol` — `.parse(text)`, `.build(wire:)`, `#wire`, `#to_s`, and the
  constants `Protocol::HTTP_1_1` and `Protocol::HTTP_2`. Task 15 requires one on every response.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# HTTP-33.
class DexpaceProtocolTest < DexpaceTestCase
  test "exposes a canonical lower-case wire form" do
    assert_equal("http/1.1", Dexpace::Protocol::HTTP_1_1.wire)
    assert_equal("http/2", Dexpace::Protocol::HTTP_2.wire)
  end

  test "parses the canonical forms and the two aliases, case-insensitively" do
    ["HTTP/2", "http/2", "HTTP/2.0", "http/2.0"].each do |text|
      assert_equal(Dexpace::Protocol::HTTP_2, Dexpace::Protocol.parse(text))
    end
    assert_equal(Dexpace::Protocol::HTTP_1_1, Dexpace::Protocol.parse("HTTP/1.1"))
  end

  test "raises on an unrecognised identifier, naming it" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Protocol.parse("spdy/3") }

    assert_includes(error.message, "spdy/3")
  end

  # The byte check runs before `downcase`, which would otherwise raise a raw ArgumentError from
  # inside Ruby and escape `rescue Dexpace::Error`.
  test "rejects an identifier carrying invalid UTF-8 with the SDK's own error" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Protocol.parse("h\xE9") }

    refute_match(/invalid byte sequence/, error.message)
  end

  test "with re-validates, so a derived protocol cannot carry an unknown wire form" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Protocol::HTTP_2.with(wire: "http/9") }
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/protocol_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Protocol`.

- [ ] **Step 3: Write `lib/dexpace/http/protocol.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"

module Dexpace
  # The negotiated protocol (HTTP-33).
  #
  # The byte check runs before `downcase`, and that order is the whole reason this is code rather
  # than one line: `String#downcase` raises ArgumentError on a String carrying invalid UTF-8, and
  # an ArgumentError from inside Ruby escapes `rescue Dexpace::Error`. A validator that crashes
  # has not rejected its input.
  class Protocol < Data.define(:wire)
    include Model
    private_class_method :new

    WIRE_FORMS = %w[http/1.1 http/2].freeze
    ALIASES = { "http/1.1" => "http/1.1", "http/2" => "http/2", "http/2.0" => "http/2" }.freeze

    def self.build(wire:)
      new(wire: wire)
    end

    def self.parse(text)
      return text if text.is_a?(Protocol)

      identifier = Model.required!("protocol", text).to_s
      unless identifier.b.each_byte.all? { |byte| byte > 0x20 && byte < 0x7F }
        raise InvalidArgumentError, "protocol identifier is not printable ASCII"
      end

      # `downcase` with no argument: "locale-invariant" is enforced by the repository-wide cop
      # rather than asserted here, exactly as in HTTP-13's fold.
      canonical = ALIASES[identifier.downcase]
      raise InvalidArgumentError, "unrecognised protocol #{identifier.inspect}" if canonical.nil?

      build(wire: canonical)
    end

    def initialize(wire:)
      unless WIRE_FORMS.include?(Model.required!("wire", wire))
        raise InvalidArgumentError, "wire must be one of: #{WIRE_FORMS.join(", ")}"
      end

      super(wire: Model.frozen_string(wire))
    end

    def to_s
      wire
    end

    HTTP_1_1 = build(wire: "http/1.1")
    HTTP_2 = build(wire: "http/2")
  end
end
```

`.build` validates through the `initialize` override, so `Protocol::HTTP_2.with(wire: "http/9")`
raises — no `.build` in this phase is a bare `new` wrapper. An unrecognised identifier carries the
offending text in its message: it is caller-supplied protocol text, not a header value, so
`HTTP-20`'s no-echo rule does not reach it.

- [ ] **Step 4: Write `sig/dexpace/http/protocol.rbs`** and add the require.

- [ ] **Step 5: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/protocol_test.rb`
Expected: PASS, 5 runs.

---

## Task 9: `Dexpace::MediaType`

**Requirement IDs:** `HTTP-23`, `HTTP-24`, `HTTP-25`, `HTTP-26`, `HTTP-27`, `HTTP-53`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/media_type.rb`,
  `gems/dexpace-core/sig/dexpace/http/media_type.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/media_type_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`, `Dexpace::HeaderSyntax`.
- Produces: `Dexpace::MediaType` — `.parse(text)`, `.build(type:, subtype:, parameters:)`,
  `#type`, `#subtype`, `#parameters`, `#charset -> String?`, `#render -> String`, `#to_s`,
  `#matches?(other) -> bool`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# HTTP-23, HTTP-24, HTTP-25, HTTP-26, HTTP-27, HTTP-53.
class DexpaceMediaTypeTest < DexpaceTestCase
  test "lower-cases type, subtype and parameter keys while preserving a value's case" do
    media = Dexpace::MediaType.parse("Application/JSON;Charset=UTF-8")

    assert_equal("application", media.type)
    assert_equal("json", media.subtype)
    assert_equal({ "charset" => "UTF-8" }, media.parameters)
  end

  test "splits parameters respecting quoted strings and only on the first equals" do
    media = Dexpace::MediaType.parse(%(text/plain; q="a;b=c"; x=1))

    assert_equal({ "q" => "a;b=c", "x" => "1" }, media.parameters)
  end

  test "round-trips through render, quoting and escaping a value that is not a token" do
    original = Dexpace::MediaType.parse(%(text/plain; q="a\\"b"))

    assert_equal(original, Dexpace::MediaType.parse(original.render))
  end

  test "resolves charset case-insensitively and returns nil when absent or unknown" do
    assert_equal("utf-8", Dexpace::MediaType.parse("text/plain; CharSet=utf-8").charset)
    assert_nil(Dexpace::MediaType.parse("text/plain").charset)
    assert_nil(Dexpace::MediaType.parse("text/plain; charset=bogus").charset)
  end

  test "rejects the malformed forms HTTP-53 names" do
    ["", "   ", "bare", "/plain", "text/", "text/plain/x", "text/plain; q", "text/plain; =1",
     "text/plain; q="].each do |bad|
      assert_raises(Dexpace::InvalidArgumentError, bad) { Dexpace::MediaType.parse(bad) }
    end
  end

  test "rejects a control or non-ASCII byte anywhere, using the outbound header-value predicate" do
    ["text/pl\rain", "text/pl\xC3\xA5in"].each do |bad|
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::MediaType.parse(bad) }
    end
  end

  test "with re-validates, so a derived media type cannot carry an unfolded type" do
    json = Dexpace::MediaType.parse("application/json")

    assert_raises(Dexpace::InvalidArgumentError) { json.with(type: "TEXT") }
  end

  test "matches a wildcard only in the sanctioned positions, ignoring parameters" do
    json = Dexpace::MediaType.parse("application/json; charset=utf-8")

    assert(Dexpace::MediaType.parse("*/*").matches?(json))
    assert(Dexpace::MediaType.parse("application/*").matches?(json))
    refute(Dexpace::MediaType.parse("text/*").matches?(json))
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::MediaType.parse("*/json") }
  end
end
```

Add one `#sample` property test — `testing/f36a19cd` makes a round-trip property mandatory for a
parser: for 64 generated `type/subtype; key="value"` inputs drawn from a bounded alphabet that
includes `;`, `=`, `"` and `\` inside the value, `parse(render(parse(text))) == parse(text)`.

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/media_type_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::MediaType`.

- [ ] **Step 3: Write the parser**

Ruby ships nothing that splits parameters respecting quoted strings, so this is hand-written. The
three functions below are the part a reader could not otherwise get right; the rest of the class is
the usual `Data`/`Model`/private-`new` shape. **Validate the raw input's bytes first** — a
character-oriented scan of an invalid-UTF-8 string raises before it can reject it.

```ruby
# HTTP-26: the same predicate as an outbound header value, so a media type is always header-safe.
# It runs on the RAW input, before any character-oriented work, because `each_char` on invalid
# UTF-8 raises rather than returning something this parser could reject.
def self.parse(text)
  Model.required!("media type", text)
  unless HeaderSyntax.valid_outbound_value?(text)
    raise InvalidArgumentError, "media type contains a byte no header value may carry (HTTP-26)"
  end

  segments = split_parameters(text)
  essence = segments.shift.to_s.strip
  type, slash, subtype = essence.partition("/")
  if slash.empty? || type.empty? || subtype.empty? || subtype.include?("/")
    raise InvalidArgumentError, "media type #{text.inspect} is not a well-formed type/subtype"
  end

  build(type: type.downcase, subtype: subtype.downcase, parameters: parse_parameters(segments))
end

# HTTP-25: a `;` inside a quoted string is not a separator, and a `\` escapes the next byte.
def self.split_parameters(text)
  parts = []
  current = +""
  quoted = false
  escaped = false
  text.each_char do |char|
    if escaped
      escaped = false
    elsif quoted && char == "\\"
      escaped = true
    elsif char == '"'
      quoted = !quoted
    elsif char == ";" && !quoted
      parts << current
      current = +""
      next
    end
    current << char
  end
  parts << current
end

# HTTP-25 and HTTP-53: split on the FIRST "=" only; the key and the raw value are both required.
def self.parse_parameters(segments)
  segments.each_with_object({}) do |segment, parameters|
    key, equals, raw = segment.strip.partition("=")
    if equals.empty? || key.empty? || raw.empty?
      raise InvalidArgumentError, "media-type parameter #{segment.strip.inspect} is malformed"
    end

    parameters[key.downcase] = unquote(raw)
  end
end
```

**`.build` validates too, and does not trust `.parse` to have done it.** The `initialize` override
re-checks what the type guarantees: `type` and `subtype` present, non-empty, token-shaped and
already folded, every parameter key already folded and token-shaped, and the whole rendered form
header-safe by `HeaderSyntax.valid_outbound_value?`. `.parse` normalises (it lower-cases and
unquotes) and `initialize` validates the normalised invariants, so `#with(type: "TEXT")` — which
routes through `.build` — fails loudly rather than producing a `MediaType` whose equality no longer
behaves case-insensitively. No `.build` in this phase is a bare `new` wrapper.

`unquote(raw)` strips a surrounding pair of quotes and removes one level of `\` escaping, raising
on an unterminated quoted string. `#render` is its inverse: `"#{type}/#{subtype}"` followed by
`"; #{key}=#{quoted}"` per parameter, where a value matching the RFC 7230 token grammar is emitted
bare and anything else is emitted quoted with `\` and `"` escaped — which is what makes
`parse(render(x)) == x` hold. Both regexps in this file are built with
`Regexp.new(source, timeout: 1.0)`.

`#charset` looks up `"charset"` (the keys are already folded), downcases the value with no
argument, and returns it only if `Encoding.name_list` recognises it — otherwise `nil`, never a
raise (`HTTP-24`). `#matches?(other)` returns true when this type is `*` and this subtype is `*`,
or this type equals the other's and this subtype is `*` or equals the other's; parameters take no
part (`HTTP-27`), and `.parse` rejects a wildcard type paired with a concrete subtype.

- [ ] **Step 4: Write `sig/dexpace/http/media_type.rbs`** and add the require.

- [ ] **Step 5: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/media_type_test.rb`
Expected: PASS, 9 runs.

---

## Task 10: `Dexpace::PercentEncoding`

**Requirement IDs:** `HTTP-29`, `HTTP-31`, `HTTP-32`; design §3.5's component encoder.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/percent_encoding.rb`,
  `gems/dexpace-core/sig/dexpace/http/percent_encoding.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/percent_encoding_test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `Dexpace::PercentEncoding` with `.encode_component(text) -> String` and
  `.decode_component(text) -> String`. Task 11 uses both; phase 2's `SEAM-27` path-segment
  encoding calls `.encode_component` for the same reason.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# HTTP-29, HTTP-31, HTTP-32, design §3.5. None of Ruby's three built-in escapers implements RFC
# 3986 component encoding: URI.encode_www_form_component and CGI.escape emit "+" for a space and
# URI::RFC3986_PARSER.escape leaves "/", "+" and "*" bare. This is the hand-written one.
class DexpacePercentEncodingTest < DexpaceTestCase
  Encoding_ = Dexpace::PercentEncoding

  test "encodes everything outside the unreserved set, and nothing inside it" do
    assert_equal("a%20b%2A~%2B%2F%21%28%29%27", Encoding_.encode_component("a b*~+/!()'"))
  end

  test "leaves the unreserved set untouched" do
    unreserved = "AZaz09-._~"

    assert_equal(unreserved, Encoding_.encode_component(unreserved))
  end

  test "encodes a multi-byte character as its UTF-8 bytes, uppercase" do
    assert_equal("caf%C3%A9", Encoding_.encode_component("café"))
  end

  test "decoding leaves a plus as a plus" do
    assert_equal("a+b", Encoding_.decode_component("a+b"))
  end

  test "decoding a malformed escape falls back to the raw text rather than raising" do
    assert_equal("a%zzb", Encoding_.decode_component("a%zzb"))
    assert_equal("a%", Encoding_.decode_component("a%"))
  end

  test "round-trips bytes that are not valid UTF-8" do
    assert_equal("%FF", Encoding_.encode_component(Encoding_.decode_component("%FF")))
  end
end
```

Add one `#sample` property test: for 128 generated strings over a byte alphabet including `%`,
`+`, space and bytes ≥ 0x80, `encode_component(decode_component(encode_component(s)))` equals
`encode_component(s)`.

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/percent_encoding_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::PercentEncoding`.

- [ ] **Step 3: Write `lib/dexpace/http/percent_encoding.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # RFC 3986 percent-encoding for a single component (HTTP-29, HTTP-32; design §3.5).
  #
  # This is NOT application/x-www-form-urlencoded, and the form encoder BODY-35 needs is a
  # different function with a different name in a later phase. They are never interchanged: the
  # difference is a space, which is %20 here and "+" there, and a URL that mixes them is wrong in
  # a way no test of either function alone would catch.
  module PercentEncoding
    UNRESERVED = ("A".."Z").to_a.concat(("a".."z").to_a, ("0".."9").to_a, %w[- . _ ~]).freeze
    ENCODED = (0..255).to_h { |byte| [byte, format("%%%02X", byte)] }.freeze
    # Per-pattern timeout, like every other regexp in this gem (Global Constraints above): the
    # process-global Regexp.timeout is a budget a library must never impose on its host.
    HEX = Regexp.new("\\A[0-9A-Fa-f]{2}\\z", timeout: 1.0)

    module_function

    # Reads bytes, so a value carrying invalid UTF-8 encodes byte-exactly instead of raising.
    def encode_component(text)
      text.b.each_byte.map { |byte| passthrough(byte) || ENCODED.fetch(byte) }.join
    end

    def passthrough(byte)
      character = byte.chr
      UNRESERVED.include?(character) ? character : nil
    end
    private_class_method :passthrough

    # HTTP-31: lenient and total. A malformed escape is left exactly as it was found rather than
    # raising, which is the opposite of URI.decode_www_form_component's behaviour and the reason
    # this is hand-rolled. HTTP-32: "+" decodes to "+", never to a space.
    def decode_component(text)
      bytes = text.b
      out = (+"").b
      index = 0
      while index < bytes.bytesize
        pair = bytes.byteslice(index + 1, 2)
        if bytes.getbyte(index) == 0x25 && pair&.bytesize == 2 && HEX.match?(pair)
          out << pair.to_i(16).chr
          index += 3
        else
          out << bytes.getbyte(index).chr
          index += 1
        end
      end
      out.force_encoding(Encoding::UTF_8)
    end
  end
end
```

`passthrough` is private for the same reason `HeaderSyntax.trimmable?` is: it appears in no `sig/`
file, and a module function that is public in Ruby and absent from the signature is public API
nobody declared.

The BINARY accumulator matters: appending a high byte to a UTF-8 buffer raises
`Encoding::CompatibilityError`. The closing `force_encoding` is a retag, not a conversion — the
bytes are whatever the sender sent, every comparison downstream is byte-wise, and
`io-and-byte-streams/0a4773a6` is what sanctions the retag.

- [ ] **Step 4: Write `sig/dexpace/http/percent_encoding.rbs`** and add the require.

- [ ] **Step 5: Run the test to confirm it passes**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/percent_encoding_test.rb`
Expected: PASS, 7 runs.

---

## Task 11: `Dexpace::Query` and `Query::Builder`

**Requirement IDs:** `HTTP-28`, `HTTP-29`, `HTTP-30`, `HTTP-31`, `HTTP-32`, plus `HTTP-3`/`HTTP-5`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/query.rb`,
  `gems/dexpace-core/lib/dexpace/http/query/builder.rb`, and the two `sig/` mirrors
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/query_test.rb`,
  `gems/dexpace-core/test/dexpace/http/query/builder_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`, `Dexpace::PercentEncoding`.
- Produces: `Dexpace::Query` — `.build(pairs:)`, `.parse(text)`, `.builder`, `Query::EMPTY`,
  `#entries -> Array[[String, String]]`, `#[](name) -> Array[String]?`, `#include?(name)`,
  `#names -> Array[String]`, `#encode -> String`, `#empty?`, `#new_builder`; and
  `Dexpace::Query::Builder`, which includes `Dexpace::Builder` — `#add(name, value)`,
  `#set(name, values)`, `#remove(name)`, `#build`. The `pairs` member's generated reader is
  **private**: `#entries` is the public entry-set accessor.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# HTTP-28, HTTP-29, HTTP-30, HTTP-31, HTTP-32, HTTP-3, HTTP-5.
class DexpaceQueryTest < DexpaceTestCase
  test "names are case-sensitive, unlike header names" do
    query = Dexpace::Query.builder.add("page", "1").add("Page", "2").build

    assert_equal(["1"], query["page"])
    assert_equal(["2"], query["Page"])
  end

  test "encodes with RFC 3986 rules, one occurrence per value, in insertion order" do
    query = Dexpace::Query.builder.add("q", "a b").add("plus", "c+d").add("q", "z").build

    assert_equal("q=a%20b&plus=c%2Bd&q=z", query.encode)
  end

  test "models a value-less parameter as one empty-string value, distinct from an absent name" do
    query = Dexpace::Query.builder.add("flag", nil).build

    assert_equal([""], query["flag"])
    assert(query.include?("flag"))
    assert_nil(query["absent"])
  end

  test "returns empty for an empty query and omits the leading question mark" do
    assert_equal("", Dexpace::Query::EMPTY.encode)
  end

  test "parses leniently: a leading ?, a bare segment, a stray &, a bad escape" do
    query = Dexpace::Query.parse("?a=1&&b&c=&d=%zz")

    assert_equal(["1"], query["a"])
    assert_equal([""], query["b"])
    assert_equal([""], query["c"])
    assert_equal(["%zz"], query["d"])
  end

  test "a blank or nil query parses to empty" do
    assert_predicate(Dexpace::Query.parse(nil), :empty?)
    assert_predicate(Dexpace::Query.parse("  "), :empty?)
  end

  test "equality is order-sensitive: two instances are equal iff they encode identically" do
    first = Dexpace::Query.builder.add("a", "1").add("b", "2").build
    second = Dexpace::Query.builder.add("b", "2").add("a", "1").build

    refute_equal(first, second)
    assert_equal(first, Dexpace::Query.parse(first.encode))
  end

  test "a name whose value list is empty is dropped at build time" do
    query = Dexpace::Query.builder.add("a", "1").set("a", []).build

    refute(query.include?("a"))
    assert_equal("", query.encode)
  end

  test "new_builder does not alias the model's pairs" do
    query = Dexpace::Query.builder.add("a", "1").build
    derived = query.new_builder.add("a", "2").build

    assert_equal(["1"], query["a"])
    assert_equal(%w[1 2], derived["a"])
  end

  # HTTP-5: "name-set and entry-set accessors return a fresh per-call snapshot".
  test "the name set and the entry set are a fresh frozen snapshot on every call" do
    query = Dexpace::Query.builder.add("a", "1").build

    assert_predicate(query.names, :frozen?)
    refute_same(query.names, query.names)
    assert_predicate(query.entries, :frozen?)
    refute_same(query.entries, query.entries)
  end

  test "build rejects a pair shape no builder would have produced" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Query.build(pairs: [["a"]]) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Query.build(pairs: [%w[a b], nil]) }
  end

  test "does not expose its internal pair list" do
    refute_respond_to(Dexpace::Query::EMPTY, :pairs)
  end
end
```

Add one `#sample` round-trip property test: for 64 generated queries, `Query.parse(q.encode) == q`.

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/query_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Query`.

- [ ] **Step 3: Write `lib/dexpace/http/query.rb`**

`Data.define(:pairs)` including `Model`, `private_class_method :new`, `private :pairs`, and a
`.build(pairs:)` that validates before it owns:

```ruby
def self.build(pairs:)
  new(pairs: Model.own(pairs))
end

# .build is public and #with routes through it, so the shape is checked here rather than trusted
# from Builder#build. No .build in this phase is a bare `new` wrapper.
def initialize(pairs:)
  Model.required!("pairs", pairs)
  pairs.each do |pair|
    unless pair.is_a?(Array) && pair.length == 2 && pair.all?(String)
      raise InvalidArgumentError, "every query pair must be a [name, value] pair of strings"
    end
  end

  super
end

# HTTP-5, first tier: a fresh per-call snapshot for the name set and the entry set.
def names
  pairs.map(&:first).uniq.freeze
end

def entries
  pairs.map(&:dup).each(&:freeze).freeze
end

# There is no stored per-name list to hand back -- the model is a pair list -- so this allocates
# one and freezes it, which satisfies HTTP-5's MUST by the stricter route.
def [](name)
  found = pairs.select { |pair| pair.first == name }.map(&:last)
  found.empty? ? nil : found.freeze
end
```

The encode/parse pair is the rest of the content:

```ruby
# HTTP-29: one occurrence per value, insertion order preserved, no leading "?", "" when empty.
def encode
  pairs.map do |name, value|
    "#{PercentEncoding.encode_component(name)}=#{PercentEncoding.encode_component(value)}"
  end.join("&")
end

# HTTP-31: lenient and total, and the exact inverse of #encode for well-formed input.
def self.parse(text)
  return EMPTY if text.nil? || text.b.strip.empty?

  pairs = text.b.sub(/\A\?/, "").split("&").reject(&:empty?).map do |segment|
    name, _equals, value = segment.partition("=")
    [PercentEncoding.decode_component(name), PercentEncoding.decode_component(value)]
  end
  build(pairs: pairs.map(&:freeze))
end
```

`text.b` before `strip` and `sub` is the same rule as `HeaderSyntax.trim`: a query string arrives
from the wire and may not be valid UTF-8, and `String#strip` raises on one.

A `Hash` cannot back this model: `HTTP-28` requires multiple values per name **with order
preserved across names** and a value-less parameter distinct from an absent one, so the pairs list
is the model and `#[]` is a scan.

- [ ] **Step 4: Write `lib/dexpace/http/query/builder.rb`**

`#add(name, value)` maps a `nil` value to `""` (`HTTP-28`'s `?flag`); `#set(name, values)` replaces
every occurrence of a name with the given list, in place at the name's first position;
`#remove(name)` drops them all; `#build` **rejects any name whose value list came out empty**
before constructing, which is `HTTP-30`'s phantom-entry rule — an empty list would otherwise leave
`include?` true and `encode` blind to it. The class includes `Dexpace::Builder` (Task 2), so it is
accepted by the generic helper `SEAM-29` requires; add `Query.builder` to that suite's list.

- [ ] **Step 5: Write both `sig/` mirrors** and add both requires in dependency order.

- [ ] **Step 6: Run both suites to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/query_test.rb` and the builder suite.
Expected: PASS, 13 runs and 5 runs.

---

## Task 12: `Dexpace::URL`

**Requirement IDs:** `HTTP-46`, `HTTP-47`; design §3.5's parser pin.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/url.rb`,
  `gems/dexpace-core/sig/dexpace/http/url.rbs`
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/url_test.rb`

**Interfaces:**
- Consumes: `Dexpace::InvalidArgumentError`.
- Produces: `Dexpace::URL` with `.parse!(input) -> URI::Generic` (frozen) and
  `.external_form(uri) -> String`. Task 14 calls both; phase 2's base-URL composition calls
  `.parse!` so the parser pin has exactly one home.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# HTTP-46, HTTP-47, design §3.5.
class DexpaceUrlTest < DexpaceTestCase
  test "parses with the RFC 3986 parser, which is pinned on every supported Ruby" do
    url = Dexpace::URL.parse!("https://example.test/a%2Fb?x=%26")

    assert_equal("https://example.test/a%2Fb?x=%26", Dexpace::URL.external_form(url))
  end

  test "preserves already-encoded octets rather than normalising them away" do
    url = Dexpace::URL.parse!("https://example.test/a%2Fb")

    assert_includes(Dexpace::URL.external_form(url), "%2F")
  end

  test "rejects a malformed URL with an argument error carrying the offending input" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::URL.parse!("::bad") }

    assert_includes(error.message, "::bad")
  end

  test "rejects a relative URI, naming it" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::URL.parse!("/relative") }

    assert_includes(error.message, "/relative")
  end

  test "rejects a nil URL through the shared required-field helper" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::URL.parse!(nil) }

    assert_equal("url is required", error.message)
  end

  test "accepts a URI object, returns it frozen, and does not freeze the caller's" do
    caller_uri = ::URI::RFC3986_PARSER.parse("https://example.test/")

    assert_predicate(Dexpace::URL.parse!(caller_uri), :frozen?)
    refute_predicate(caller_uri, :frozen?)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/url_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::URL`.

- [ ] **Step 3: Write `lib/dexpace/http/url.rb`**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "uri"

require_relative "../model"

module Dexpace
  # URL parsing, pinned to one parser (design §3.5).
  #
  # ::URI::RFC3986_PARSER explicitly, never URI.parse and never URI::DEFAULT_PARSER: which parser
  # DEFAULT_PARSER names changed at exactly Ruby 3.4.0, which straddles this port's supported
  # range, so code written against it silently changes escaping and parsing behaviour across the
  # CI matrix without changing a line. A custom cop fails the build on either. RFC3986_PARSER has
  # been present since Ruby 3.0, so the pin costs nothing on the floor.
  module URL
    module_function

    def parse!(input)
      Model.required!("url", input)
      # `dup` before `freeze`: a URI this method did not parse belongs to the caller, and
      # freezing it in place would freeze THEIR object -- the same mistake Model.own avoids with
      # `copy: true`. A URI we parsed here is ours already, and the dup is one allocation.
      uri = input.is_a?(::URI::Generic) ? input.dup : ::URI::RFC3986_PARSER.parse(input.to_s)
      unless uri.absolute?
        raise InvalidArgumentError, "url #{input.to_s.inspect} is not an absolute URI (HTTP-47)"
      end

      uri.freeze
    rescue ::URI::InvalidURIError => error
      raise InvalidArgumentError, "url #{input.to_s.inspect} is malformed: #{error.message}"
    end

    # HTTP-46's comparison key. Ruby's URI performs no name resolution, so this is textual and
    # non-blocking by construction -- which the request equality test asserts rather than assumes.
    def external_form(uri)
      uri.to_s
    end
  end
end
```

- [ ] **Step 4: Write `sig/dexpace/http/url.rbs`**

`URI::Generic` is the only constant outside `Dexpace::` this phase's signatures name;
`gates:rbs_surface` matches its allowlist on the first path segment, `URI`, which phase 0 already
permits, so the gate needs no change.

- [ ] **Step 5: Add the require and run the test**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/url_test.rb`
Expected: PASS, 6 runs.

---

## Task 13: `Dexpace::RequestOptions` and its builder

**Requirement IDs:** `HTTP-34`, `HTTP-35`, plus `HTTP-3`/`HTTP-5`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/request_options.rb`,
  `gems/dexpace-core/lib/dexpace/http/request_options/builder.rb`, and the two `sig/` mirrors
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/request_options_test.rb`,
  `gems/dexpace-core/test/dexpace/http/request_options/builder_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`.
- Produces: `Dexpace::RequestOptions` — `.build(timeout:, max_retries:, tags:)`, `.builder`,
  `RequestOptions::EMPTY`, `#timeout -> Float?`, `#max_retries -> Integer?`,
  `#tags -> Hash[String, String]`, `#new_builder`; and `Dexpace::RequestOptions::Builder` —
  `#timeout=`, `#max_retries=`, `#tag(key, value)`, `#build`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# HTTP-34, HTTP-35. These are operational overrides and are deliberately NOT part of the wire
# model (HTTP-6), which is why they are a separate type rather than members of Request.
class DexpaceRequestOptionsTest < DexpaceTestCase
  test "EMPTY overrides nothing" do
    empty = Dexpace::RequestOptions::EMPTY

    assert_nil(empty.timeout)
    assert_nil(empty.max_retries)
    assert_empty(empty.tags)
  end

  test "EMPTY is one shared frozen instance, so overriding nothing allocates nothing" do
    assert_same(Dexpace::RequestOptions::EMPTY, Dexpace::RequestOptions::EMPTY)
  end

  test "tags are copied at build, so later mutation of the source map cannot reach the model" do
    source = { "tenant" => "acme" }
    options = Dexpace::RequestOptions.build(timeout: nil, max_retries: nil, tags: source)
    source["tenant"] = "other"

    assert_equal({ "tenant" => "acme" }, options.tags)
  end

  test "rejects a zero or negative timeout, because zero means no timeout in one transport" do
    [0, 0.0, -1.5].each do |timeout|
      builder = Dexpace::RequestOptions.builder
      builder.timeout = timeout

      assert_raises(Dexpace::InvalidArgumentError) { builder.build }
    end
  end

  test "accepts a nil timeout, which is the use-the-default sentinel" do
    assert_nil(Dexpace::RequestOptions.builder.build.timeout)
  end

  test "with re-validates, so a derived options cannot carry a zero timeout" do
    options = Dexpace::RequestOptions.build(timeout: 2.5, max_retries: nil, tags: {})

    assert_raises(Dexpace::InvalidArgumentError) { options.with(timeout: 0) }
  end

  test "rejects a negative max-retries and accepts zero, which disables retries for this call" do
    negative = Dexpace::RequestOptions.builder
    negative.max_retries = -1

    assert_raises(Dexpace::InvalidArgumentError) { negative.build }

    zero = Dexpace::RequestOptions.builder
    zero.max_retries = 0

    assert_equal(0, zero.build.max_retries)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/request_options_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::RequestOptions`.

- [ ] **Step 3: Write the model** — `Data.define(:timeout, :max_retries, :tags)` including `Model`,
  private `new`, `.build` coercing a non-`nil` timeout with `Float(timeout)` and passing `tags`
  through `Model.own`, `EMPTY = build(timeout: nil, max_retries: nil, tags: {})`, and
  `#new_builder` pre-filling from the instance. The timeout is a `Float` of **seconds**, matching
  every Ruby socket API so no unit conversion sits between the model and the wire (design §4).

  **`HTTP-35`'s two rejections live in the `initialize` override, not in the builder**, because
  `.build` is public and `#with` routes through it: a rule enforced only in `Builder#build` would
  let `options.with(timeout: -1)` produce a model the builder would have refused.

```ruby
def initialize(timeout:, max_retries:, tags:)
  if !timeout.nil? && timeout.to_f <= 0
    raise InvalidArgumentError, "timeout must be a positive number of seconds, or nil to use " \
                                "the default (HTTP-35)"
  end
  # 0 is legal and means "disable retries for this call"; only a negative count is a mistake.
  if !max_retries.nil? && max_retries.to_i.negative?
    raise InvalidArgumentError, "max_retries must not be negative (HTTP-35)"
  end

  super
end
```

- [ ] **Step 4: Write the builder** — `include Dexpace::Builder`, the `#timeout=`, `#max_retries=`
  and `#tag(key, value)` writers, and a `#build` that is a plain delegation now that the rules live
  in the model:

```ruby
def build
  RequestOptions.build(timeout: @timeout, max_retries: @max_retries, tags: @tags)
end
```

Add `RequestOptions.builder` to Task 2's builder-contract suite.

- [ ] **Step 5: Write both `sig/` mirrors** and add both requires.

- [ ] **Step 6: Run both suites to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/request_options_test.rb` and the
builder suite.
Expected: PASS, 8 runs and 4 runs.

---

## Task 14: `Dexpace::Request` and `Request::Builder`

**Requirement IDs:** `HTTP-3`, `HTTP-4`, `HTTP-5`, `HTTP-6`, `HTTP-7`, `HTTP-8`, `HTTP-9`,
`HTTP-46`, `HTTP-47`; `HTTP-1`/`HTTP-2` by construction.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/request.rb`,
  `gems/dexpace-core/lib/dexpace/http/request/builder.rb`, and the two `sig/` mirrors
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/request_test.rb`,
  `gems/dexpace-core/test/dexpace/http/request/builder_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`, `Dexpace::Method`, `Dexpace::Headers`, `Dexpace::URL`.
- Produces: `Dexpace::Request` — `.build(method:, url:, headers:, body:)`, `.builder`, `#method`,
  `#url`, `#headers`, `#body`, `#new_builder`, `#==`, `#eql?`, `#hash`; and
  `Dexpace::Request::Builder` — `#method=`, `#url=`, `#headers=`, `#body=`, `#header(name, value)`,
  `#build`. Task 15 requires a `Request` on every `Response`.

- [ ] **Step 1: Write the failing tests**

`request/builder_test.rb` carries the cross-field rules, which are the reason this model has a real
builder at all:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"

# HTTP-4, HTTP-7, HTTP-8, HTTP-47.
class DexpaceRequestBuilderTest < DexpaceTestCase
  def builder(url: "https://example.test/")
    Dexpace::Request.builder.tap { |b| b.url = url }
  end

  test "requires a URL and names the missing field" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Request.builder.build }

    assert_equal("url is required", error.message)
  end

  test "defaults the method to GET when there is neither a method nor a body" do
    assert_equal(Dexpace::Method::GET, builder.build.method)
  end

  test "a body with no method reports the missing method, not the no-body-on-GET rule" do
    with_body = builder
    with_body.body = "payload"
    error = assert_raises(Dexpace::InvalidArgumentError) { with_body.build }

    assert_equal("method is required", error.message)
  end

  test "rejects a body on every method whose classification forbids one" do
    %w[GET HEAD TRACE CONNECT].each do |token|
      forbidden = builder
      forbidden.method = token
      forbidden.body = "payload"

      assert_raises(Dexpace::InvalidArgumentError, token) { forbidden.build }
    end
  end

  test "clearing the body makes a GET buildable again" do
    cleared = builder
    cleared.method = "GET"
    cleared.body = "payload"
    cleared.body = nil

    assert_equal(Dexpace::Method::GET, cleared.build.method)
  end

  test "accepts a body on POST" do
    posted = builder
    posted.method = "POST"
    posted.body = "payload"

    assert_equal("payload", posted.build.body)
  end

  test "rejects a malformed URL with the offending input in the message" do
    error = assert_raises(Dexpace::InvalidArgumentError) { builder(url: "::bad").build }

    assert_includes(error.message, "::bad")
  end
end
```

`request_test.rb` carries equality, derivation and the honest encapsulation tests:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# HTTP-1, HTTP-2, HTTP-3, HTTP-5, HTTP-6, HTTP-46.
class DexpaceRequestTest < DexpaceTestCase
  def request(url: "https://example.test/a")
    builder = Dexpace::Request.builder
    builder.url = url
    builder.header("Accept", "*/*")
    builder.build
  end

  test "two requests to the same textual URL are equal, with no name resolution" do
    assert_equal(request, request)
  end

  test "two textually different URLs are not equal even when they name the same host" do
    refute_equal(request(url: "https://example.test/a"), request(url: "https://example.test/a/"))
  end

  test "equality compares method, headers and body by value" do
    other = request.new_builder
    other.header("Accept", "text/plain")

    refute_equal(request, other.build)
  end

  test "hash agrees with equality" do
    assert_equal(request.hash, request.hash)
  end

  # A Request is frozen and holds only frozen state, and it is still NOT Ractor.shareable? --
  # URI::Generic's freeze is shallow (@host and @path stay unfrozen), and the only thing that
  # would change that, Ractor.make_shareable(uri), deep-freezes URI::RFC3986_PARSER, a
  # process-global object, in place. Verified on 3.2.11 and 4.0.6. Ractor is load-bearing nowhere
  # in this port, so the boundary is stated rather than bought at that price (Deviation P1-9).
  test "is frozen, and the URI member is what keeps it out of Ractor-shareable" do
    assert_predicate(request, :frozen?)
    assert(Ractor.shareable?(request.headers))
    refute(Ractor.shareable?(request))
  end

  test "new_builder is pre-filled and does not alias the original's headers" do
    original = request
    derived = original.new_builder
    derived.header("X-Trace", "1")

    refute(original.headers.include?("X-Trace"))
    assert(derived.build.headers.include?("X-Trace"))
  end

  test "with re-validates HTTP-7, so a GET cannot acquire a body by derivation" do
    assert_raises(Dexpace::InvalidArgumentError) { request.with(body: "payload") }
  end

  test "build coerces a method token and a URL string into their types" do
    built = Dexpace::Request.build(method: "post", url: "https://example.test/a",
                                   headers: Dexpace::Headers::EMPTY, body: nil)

    assert_equal(Dexpace::Method::POST, built.method)
    assert_equal("https://example.test/a", Dexpace::URL.external_form(built.url))
  end

  test "build rejects a method token, a URL and a headers value it cannot coerce" do
    empty = Dexpace::Headers::EMPTY

    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Request.build(method: "GE T", url: "https://example.test/", headers: empty,
                             body: nil)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Request.build(method: "GET", url: "::bad", headers: empty, body: nil)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Request.build(method: "GET", url: "https://example.test/", headers: {}, body: nil)
    end
  end

  # HTTP-2's residual gap, asserted rather than papered over (design §10.10, §11.6). `send`
  # bypassing `private` is a documented Ruby feature and cannot be closed; the mitigation is that
  # HTTP-17/HTTP-18 are re-validated at the model-to-wire boundary inside every transport (phase
  # 8, DEF-25), which makes this a correctness-of-shape gap and not a request-splitting one. A
  # test asserting this path is blocked would be a lie that passes.
  test "send reaches the private constructor, and that hole is documented not closed" do
    forged = Dexpace::Request.send(:new, method: Dexpace::Method::GET,
                                         url: Dexpace::URL.parse!("https://example.test/"),
                                         headers: Dexpace::Headers::EMPTY, body: nil)

    assert_instance_of(Dexpace::Request, forged)
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/request/builder_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Request`.

- [ ] **Step 3: Write `lib/dexpace/http/request.rb`**

`Data.define(:method, :url, :headers, :body)` — exactly `HTTP-6`'s four members — including
`Model`, with private `new` and a `.build` that validates. Three things a reader would otherwise
get wrong.

**The model, not only the builder, enforces `HTTP-7`.** `#with` routes through `.build`, so a rule
that lived only in `Request::Builder#build` would let `get_request.with(body: "payload")` produce a
GET carrying a body — the exact state `HTTP-7` exists to make unrepresentable:

```ruby
def initialize(method:, url:, headers:, body:)
  # Coerce, do not merely check. `.build` is public and #with routes through it, so
  # `Request.build(method: "GET", url: "https://h/")` has to yield a Method and a URI rather than
  # a String that behaves like one until the first `#body_forbidden?` call. Both factories are
  # idempotent on their own type, so the coercion is free when the caller already did it.
  http_method = Method.of(Model.required!("method", method))
  target = URL.parse!(url)
  unless Model.required!("headers", headers).is_a?(Headers)
    raise InvalidArgumentError, "headers must be a Dexpace::Headers"
  end
  if http_method.body_forbidden? && !body.nil?
    raise InvalidArgumentError, "a #{http_method} request must not carry a body (HTTP-7)"
  end

  super(method: http_method, url: target, headers: headers, body: body)
end
```

`HTTP-8`'s defaulting stays in the builder, and only there: it is a rule about a field nobody set,
which a model that already has one cannot express.

The other two:

```ruby
# HTTP-46: URLs compare by textual external form and nothing else. Data's generated equality would
# compare URI::Generic objects, which is URI's own normalising relation and a different one --
# and the requirement is stated in terms of the external form. Ruby's URI performs no DNS, so
# "MUST NOT perform blocking work or name resolution" holds structurally; the test asserts it.
def ==(other)
  other.is_a?(Request) &&
    URL.external_form(url) == URL.external_form(other.url) &&
    method == other.method && headers == other.headers && body == other.body
end
alias eql? ==

def hash
  [Request, URL.external_form(url), method, headers, body].hash
end
```

`#method` deliberately shadows `Object#method`, exactly as `Net::HTTPGenericRequest#method` does;
the YARD block says so, and `Object#instance_method` remains available to anyone who needs the
callable.

- [ ] **Step 4: Write `lib/dexpace/http/request/builder.rb`**

`include Dexpace::Builder`, writers for the four members, `#header(name, value)` as a convenience
over the headers builder, and a `#build` that applies `HTTP-4`, then `HTTP-8`, then `HTTP-7` — in
that order, because the missing-method error must be reported before the no-body rule can name the
wrong mistake. Add `Request.builder` to Task 2's builder-contract suite.

```ruby
def build
  url = URL.parse!(@url) # HTTP-4 (required) and HTTP-47 (malformed), in one call
  # HTTP-8: GET only when there is nothing to send. A body with no method reports the MISSING
  # METHOD rather than defaulting to GET and then tripping HTTP-7's no-body rule, which would
  # name the wrong mistake.
  Model.required!("method", @method) if @method.nil? && !@body.nil?
  method = @method.nil? ? Method::GET : Method.of(@method)
  if method.body_forbidden? && !@body.nil?
    raise InvalidArgumentError, "a #{method} request must not carry a body (HTTP-7)"
  end

  Request.build(method: method, url: url, headers: @headers || Headers::EMPTY, body: @body)
end
```

`Request.build` re-checks `HTTP-7` itself (Step 3), so the builder's own check is the one that
produces the better message — the model's is the one that cannot be bypassed.

**`body` is opaque in phase 1.** The `BODY` model is phase 3's; here the member is carried, its
presence is the only thing asked of it, and its RBS type is `untyped` (`DEF-26`).

- [ ] **Step 5: Write both `sig/` mirrors** and add both requires.

- [ ] **Step 6: Run both suites to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/request_test.rb` and the builder
suite.
Expected: PASS, 10 runs and 7 runs. The duck-typing case is deliberately **not** a test: an
assertion that a `Struct` with four readers responds to four readers restates Ruby, and design
§10.10's second hole is stated in prose there and in the design's Testing section instead.

---

## Task 15: `Dexpace::Response` and `Response::Builder`

**Requirement IDs:** `HTTP-3`, `HTTP-4`, `HTTP-5`, `HTTP-6`, `HTTP-11`.

**Files:**
- Create: `gems/dexpace-core/lib/dexpace/http/response.rb`,
  `gems/dexpace-core/lib/dexpace/http/response/builder.rb`, and the two `sig/` mirrors
- Modify: `gems/dexpace-core/lib/dexpace.rb`
- Test: `gems/dexpace-core/test/dexpace/http/response_test.rb`,
  `gems/dexpace-core/test/dexpace/http/response/builder_test.rb`

**Interfaces:**
- Consumes: `Dexpace::Model`, `Dexpace::Request`, `Dexpace::Protocol`, `Dexpace::Status`,
  `Dexpace::Headers`.
- Produces: `Dexpace::Response` — `.build(request:, protocol:, status:, reason:, headers:, body:)`,
  `.builder`, `#request`, `#protocol`, `#status`, `#reason`, `#headers`, `#body`, `#new_builder`,
  and the six classification predicates delegating to `#status`; and
  `Dexpace::Response::Builder` — a writer per member and `#build`.

- [ ] **Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# HTTP-3, HTTP-4, HTTP-5, HTTP-6, HTTP-11.
class DexpaceResponseTest < DexpaceTestCase
  def response(status: Dexpace::Status::OK)
    builder = Dexpace::Response.builder
    builder.request = request
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = status
    builder.build
  end

  def request
    builder = Dexpace::Request.builder
    builder.url = "https://example.test/"
    builder.build
  end

  test "requires the request, the protocol and the status, naming the missing field" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Response.builder.build }

    assert_equal("request is required", error.message)
  end

  test "names the missing status when only that is absent" do
    builder = Dexpace::Response.builder
    builder.request = request
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    error = assert_raises(Dexpace::InvalidArgumentError) { builder.build }

    assert_equal("status is required", error.message)
  end

  test "carries an optional reason phrase and an optional body, and empty headers by default" do
    built = response

    assert_nil(built.reason)
    assert_nil(built.body)
    assert_predicate(built.headers, :empty?)
  end

  test "derives its classification from its status rather than restating the ranges" do
    assert_predicate(response, :success?)
    assert_predicate(response(status: Dexpace::Status.of(503)), :server_error?)
    assert_predicate(response(status: Dexpace::Status.of(404)), :error?)
  end

  test "build coerces a protocol identifier and a status code into their types" do
    builder = Dexpace::Response.builder
    builder.request = request
    builder.protocol = "HTTP/2.0"
    builder.status = 404
    built = builder.build

    assert_equal(Dexpace::Protocol::HTTP_2, built.protocol)
    assert_equal(Dexpace::Status::NOT_FOUND, built.status)
    assert_predicate(built, :client_error?)
  end

  test "build rejects a protocol and a status it cannot coerce" do
    assert_raises(Dexpace::InvalidArgumentError) { response(status: 99) }
    builder = Dexpace::Response.builder
    builder.request = request
    builder.protocol = "spdy/3"
    builder.status = Dexpace::Status::OK

    assert_raises(Dexpace::InvalidArgumentError) { builder.build }
  end

  test "is frozen and derives without aliasing" do
    built = response
    derived = built.new_builder
    derived.status = Dexpace::Status::NOT_FOUND

    assert_predicate(built, :frozen?)
    assert_equal(Dexpace::Status::OK, built.status)
    assert_equal(Dexpace::Status::NOT_FOUND, derived.build.status)
  end
end
```

- [ ] **Step 2: Run them to confirm they fail**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/response_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Response`.

- [ ] **Step 3: Write `lib/dexpace/http/response.rb`** — `Data.define(:request, :protocol, :status,
  :reason, :headers, :body)`, `HTTP-6`'s six members, including `Model`, private `new`, `.build`,
  and the six one-line delegations `HTTP-11` asks for:

```ruby
def informational? = status.informational?
def success? = status.success?
def redirect? = status.redirect?
def client_error? = status.client_error?
def server_error? = status.server_error?
def error? = status.error?
```

`#close` and the body lifecycle (`HTTP-41`, `HTTP-43`) are phase 3's and are absent here rather
than stubbed — a stub would be a method whose contract nothing implements.

- [ ] **Step 4: Write `lib/dexpace/http/response/builder.rb`** — `include Dexpace::Builder`, a
  writer per member, and a `#build` that defaults `headers` to `Headers::EMPTY` and delegates.
  The required-field checks live in the model's `initialize` override, in the order the
  requirement lists them, so `.build` and `#with` enforce them too:

```ruby
def initialize(request:, protocol:, status:, reason:, headers:, body:)
  unless Model.required!("request", request).is_a?(Request)
    raise InvalidArgumentError, "request must be a Dexpace::Request"
  end
  # Same rule as Request: coerce through the type's own factory rather than trusting the caller,
  # and both factories are idempotent on their own type so a builder pays nothing for it.
  negotiated = Protocol.parse(Model.required!("protocol", protocol))
  code = Status.of(Model.required!("status", status))
  unless Model.required!("headers", headers).is_a?(Headers)
    raise InvalidArgumentError, "headers must be a Dexpace::Headers"
  end

  super(request: request, protocol: negotiated, status: code, reason: reason, headers: headers,
        body: body)
end
```

  Add `Response.builder` to Task 2's builder-contract suite, which then holds all five.

- [ ] **Step 5: Write both `sig/` mirrors** and add both requires.

- [ ] **Step 6: Run both suites to confirm they pass**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace/http/response_test.rb` and the builder
suite.
Expected: PASS, 7 runs and 4 runs.

---

## Task 16: Entry-point wiring, YARD and the signature tree

**Requirement IDs:** `NFR-3`, `NFR-11` as machinery; `SEAM-1`'s explicit-require rule.

**Files:**
- Modify: `gems/dexpace-core/lib/dexpace.rb`, `gems/dexpace-core/sig/dexpace.rbs`
- Test: `gems/dexpace-core/test/dexpace_test.rb` (extend phase 0's smoke suite)

**Interfaces:**
- Consumes: every constant from Tasks 1–15.
- Produces: a `require "dexpace"` that loads the whole domain model, and a signature tree
  `rbs validate` and `steep check` both accept.

- [ ] **Step 1: Extend the smoke suite**

Add three tests to `test/dexpace_test.rb`: requiring `"dexpace"` alone makes `Dexpace::Request`,
`Dexpace::Headers` and `Dexpace::Status` resolve (no per-file require needed by a consumer);
`Dexpace.constants(false)` does not include `:ArgumentError`; and every constant the manifest will
record is reachable from `Dexpace` — the check that catches a file added to `lib/` and forgotten in
the entry point.

- [ ] **Step 2: Run it to confirm it fails**

Run: `bundle exec ruby -w gems/dexpace-core/test/dexpace_test.rb`
Expected: FAIL — `uninitialized constant Dexpace::Request`, if any require was missed.

- [ ] **Step 3: Order the requires in `lib/dexpace.rb`**

Dependency order, and it is not alphabetical: `error`, `error/invalid_argument_error`, `model`,
`builder`, `http/header_syntax`, `http/header_name`, `http/headers`, `http/headers/builder`,
`http/status`,
`http/method`, `http/protocol`, `http/media_type`, `http/percent_encoding`, `http/query`,
`http/query/builder`, `http/url`, `http/request_options`, `http/request_options/builder`,
`http/request`, `http/request/builder`, `http/response`, `http/response/builder`. A builder file
follows its model because the model's `EMPTY`-style constants are evaluated at require time.

- [ ] **Step 4: Check the whole gem loads in isolation**

```bash
bundle exec ruby -w -Igems/dexpace-core/lib -e 'require "dexpace"; puts Dexpace::Status::OK.code'
```

Expected: `200`, and no warning on stderr.

- [ ] **Step 5: Run the typing gates**

Run: `bundle exec rake rbs:validate steep`
Expected: both green. If `steep check` reports a diagnostic in a `core`-target file, fix the
signature or the code — **never relax the target**; `core` is the one Steep target that never
relaxes (phase 0's `Steepfile`).

- [ ] **Step 6: Run the documentation gate**

Run: `bundle exec rake yard`
Expected: zero undocumented public objects. Every public class and every public method carries a
YARD block that explains why the rule exists and never restates a type
(`documentation/80beb95e`, `/42d8cbf4`).

- [ ] **Step 7: Run the whole gem suite**

Run: `(cd gems/dexpace-core && bundle exec rake test)`
Expected: PASS, every suite from Tasks 1–15.

---

## Task 17: Gates, unchanged API surface, and the checklist

**Files:**
- Create: `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-checklist.md`
- Modify: `test/fixtures/surface/dexpace-core.txt`, `CLAUDE.md`,
  `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`, `docs/deferred-items.md`
- Test: the full gate set, plus the housekeeping probe

**Interfaces:**
- Consumes: everything Tasks 1–16 built.
- Produces: the phase record. Nothing consumes it in code.

- [ ] **Step 1: Run every gate, in one command**

Run: `bundle exec rake`
Expected: all seventeen green. `gates:require_allowlist` is the one to read closely — it must
report `uri` as the single new `require` in core, and nothing else.

- [ ] **Step 2: Run the suite on the floor and the ceiling**

```bash
mise exec ruby@3.2.11 -- bundle exec rake test:gems
mise exec ruby@4.0.6 -- bundle exec rake
```

Expected: green on both. The 3.2 run is the one that would fail if `Dexpace::Model#with` were
dropped, and the phase's checklist records that it was run.

- [ ] **Step 3: Regenerate the runtime surface manifest, deliberately**

```bash
bundle exec rake surface:regenerate
git diff --stat test/fixtures/surface/dexpace-core.txt
bundle exec rake gates:surface_snapshot gates:rbs_surface gates:sig_diff
```

Expected: the manifest grows from two lines to the phase's whole public surface; the three gates
then pass, with `gates:sig_diff` still printing `no release tag yet — the first v* tag becomes the
baseline`. **Read the diff before accepting it**: a constant in it that no task above created is a
leak, and regeneration is a reviewed act, never a way to silence a failure (`api-design/46c8b5fc`).

- [ ] **Step 4: Write the checklist**

Create `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-checklist.md` from what was
actually built, not from this plan. **Forty-two rows**: `HTTP-1`–`HTTP-35`, `HTTP-46`–`HTTP-50`,
`HTTP-53`, and `SEAM-29` — whose construction contract this phase honours ahead of phase 2, both
halves of it: the uniform `<name> is required` message (Task 2's `Model.required!`) and the shared
generic builder contract (Task 2's `Dexpace::Builder`). Legend, verbatim from the roadmap: ✅
implemented and tested · 🚫 not built (permanent simplification, named reason) · ⏳ deferred
(`DEF-<n>` with its pick-up condition) · N/A not applicable in this port. Each row names the
**numbered task above** that satisfies it. `HTTP-1` and `HTTP-2` are ✅ against Task 2 with "by
construction" stated and `HTTP-2`'s residual gap named. `HTTP-22`, `HTTP-48`, `HTTP-49` and
`HTTP-50` are ⏳ `DEF-2`, whose target is phase 6. Add the audit-group section the roadmap
requires: the four groups this phase ran (*Public API surface*; *RBS / Steep typing*; *Minitest
conventions*; *Encoding and binary strings*) and the result of each, including the four notes
filed.

- [ ] **Step 5: Verify the register rows and add any the implementation found**

Run: `grep -n '^### DEF-2[4-9]' docs/deferred-items.md`
Expected: `DEF-24`, `DEF-25` and `DEF-26`, appended during planning, and `DEF-2` naming **phase 6**
as its target with the four unmet SHOULDs also listed in `docs/first-release.md`'s readiness list.
Anything the implementation defers beyond those is appended as
`DEF-27` onward with the deferring phase, the reason, the pick-up condition and the IDs it cites,
and the `next id:` line at the foot of the register is updated.

- [ ] **Step 6: Append the roadmap status note**

Append one dated entry to `## Phase Status Notes` in
`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`. Never rewrite an earlier one. It states
what landed, the two verified interpreter findings and where each is recorded, the four notes
filed, the deferrals, and the one count that changed — the phase-directory count is unchanged at
two, and `gems/` is still six.

- [ ] **Step 7: Update `CLAUDE.md`**

Three edits, and no others:

1. The **"Nothing is implemented yet"** paragraph — `dexpace-core` now carries the HTTP domain
   model; the other five gems are still namespace-and-`VERSION` skeletons.
2. The **domain-model construction pattern** section — add the two rules this phase fixed for every
   later phase: `#with` routes through the validating factory because `Data#with` does not call an
   `initialize` override on Ruby 3.2, and `Dexpace::Error` is a module so that `XCUT-4`'s
   `IOError` family stays reachable. Both are one line each, pointing at the phase-1 design.
3. The **counts the `claims` check reads** — the gem count and the harvested-topic count are
   unchanged; the phase-directory sentence already says two and stays true.

- [ ] **Step 8: Run the probe and fix what it reports**

Run: `ruby .claude/skills/housekeeping/probe.rb`
Expected: exit 0, `no drift found.` A `claims` finding means a numeral in a sentence is wrong — fix
the sentence, never the check.

- [ ] **Step 9: Run the four repository gate commands**

```bash
ruby .claude/skills/housekeeping/probe.rb
ruby -w .claude/skills/housekeeping/test/run.rb
ruby -w scripts/test/knowledge_test.rb
ruby scripts/verify_knowledge_structure.rb
```

Expected: all four exit 0. The last confirms the four notes this phase filed are structurally sound
and that every harvested key they cite is still live.

- [ ] **Step 10: Hand over**

Do not commit. Report to the manager: the twenty-two new `lib/` files with their `sig/` and `test/`
mirrors, the seventeen gates green on 3.2 and 4.0, the surface-manifest diff, the `DEF-` rows, the
checklist's forty-two rows with any ⏳ or 🚫 named, and the `CLAUDE.md` diff.

---

## Self-Review

**Spec coverage.** Every `## <Component>` section of the design maps to at least one task:

| Design section | Task |
|---|---|
| Error root and the validation type | 1 |
| The shared construction helper and the builder contract | 2 |
| Header syntax | 3 |
| HeaderName | 4 |
| Headers and `Headers::Builder` | 5 |
| Status | 6 |
| Method | 7 |
| Protocol | 8 |
| MediaType | 9 |
| PercentEncoding | 10 |
| Query and `Query::Builder` | 11 |
| URL | 12 |
| RequestOptions and its builder | 13 |
| Request and `Request::Builder` | 14 |
| Response and `Response::Builder` | 15 |
| Entry point and the public surface | 16 |
| Testing (the encoding table, the aliasing tests, the `HTTP-2` negative proof, the property tests) | distributed: Task 3 (encoding), Tasks 5, 11, 13, 14, 15 (aliasing), Task 14 (`HTTP-2`), Tasks 3, 6, 9, 10, 11 (property) |
| Design §4 and §5 addenda | 1 (A3), 2 (A1), 3 (A2) |
| Deviation Ledger, deferrals, register sweep | 17 |

**Requirement coverage.** All 39 in-scope IDs plus `HTTP-1`/`HTTP-2` and `SEAM-29`: `SEAM-29`'s
two MUSTs (2 — `Model.required!` for the message form, `Dexpace::Builder` for the generic
contract), `HTTP-1`/`HTTP-2` (2),
`HTTP-3`/`HTTP-4`/`HTTP-5` (2, 5, 11, 13, 14, 15), `HTTP-6` (14, 15), `HTTP-7`/`HTTP-8` (14),
`HTTP-9` (7), `HTTP-10`–`HTTP-12` (6), `HTTP-13` (3, 4, 5), `HTTP-14`–`HTTP-16` (5),
`HTTP-17`–`HTTP-20` (3), `HTTP-21` (4), `HTTP-22` (⏳ `DEF-2`), `HTTP-23`–`HTTP-27` (9),
`HTTP-28`–`HTTP-32` (10, 11), `HTTP-33` (8), `HTTP-34`/`HTTP-35` (13), `HTTP-46`/`HTTP-47` (12,
14), `HTTP-48`–`HTTP-50` (⏳ `DEF-2`), `HTTP-53` (9).

**Placeholder scan.** No "TBD", no "implement later", no "add appropriate error handling", no
"similar to Task N". Three tasks describe a file's shape in prose rather than in full code — Task 8
(`Protocol`), Task 13's model and Task 15's model — and each names the exact members, the exact
validation calls and the exact error messages, because the shape is the one already shown in full
in Tasks 6 and 7 and repeating forty lines of `Data.define`/`private_class_method`/`build` would
bury the two lines that differ.

**Type consistency.**

- `Model.required!(name, value)`, `Model.own(collection)` and `Model.frozen_string(value)` are
  defined in Task 2 and called by name in Tasks 4, 5, 6, 7, 8, 9, 11, 12, 13, 14 and 15.
- `Dexpace::Builder` is defined in Task 2 and included by the five `Builder` classes in Tasks 5,
  11, 13, 14 and 15; `Builder.build_all` is called only by Task 2's own suite, which grows one
  entry per builder as they land.
- `Model#with` requires every including type to define `self.build(**members)` whose keywords are
  exactly the `Data` members — asserted for `Status` in Task 6, and true by construction for every
  type because `.build`'s keyword list is copied from the `Data.define` list in each task.
- `HeaderSyntax.validate_name!`, `.validate_outbound_value!(value, name:)` and
  `.validate_inbound_value!(value, name:)` are defined in Task 3 with those exact keywords and
  called with them in Tasks 4, 5 and 9.
- `HeaderName.of` accepts `String | HeaderName` (Task 4) and is called with both in Task 5.
- `PercentEncoding.encode_component` / `.decode_component` (Task 10) are called in Task 11 only.
- `URL.parse!` / `.external_form` (Task 12) are called in Task 14's builder and equality.
- `Headers::EMPTY`, `Query::EMPTY` and `RequestOptions::EMPTY` are the three canonical empties, each
  defined in its own model file after `.build` exists.
- Every `Data` type's `.build` validates through an `initialize` override: `HeaderName` (4),
  `Headers` (5), `Status` (6), `Method` (7), `Protocol` (8), `MediaType` (9), `Query` (11),
  `RequestOptions` (13), `Request` (14), `Response` (15). `URL` (12) is a module of functions and
  has no constructor to protect; `PercentEncoding` (10) and `HeaderSyntax` (3) likewise.
- `Method::GET` and `Method#body_forbidden?` (Task 7) are consumed in Task 14's `#build`.
- `Status`'s six predicates (Task 6) are delegated to by `Response`'s six (Task 15), with identical
  names.

**Rough edges, stated rather than hidden.**

- `Query#[]` scans the pairs list and allocates a fresh frozen array, so a query with hundreds of
  parameters is O(n) per lookup with one allocation. That is the shape `HTTP-28` forces — a pair
  list has no stored per-name list to hand back — and the sizes involved make it irrelevant; a
  memoised index would be a mutable member on a frozen model.
- `Headers#names` and `#entries` allocate per call, because `HTTP-5` says name-set and entry-set
  accessors return a fresh per-call snapshot. `#[]` does not, because the same requirement says a
  per-name value-list accessor returns the instance's own list. The asymmetry is the requirement's,
  not this port's, and the tests assert both halves so a later "optimisation" cannot quietly
  collapse them.
- `Model.own` deep-copies through `Ractor.make_shareable(collection, copy: true)`, which is more
  work than a shallow `dup` on every build. It is the only form that leaves the caller's nested
  collections unfrozen, which is the correctness requirement; if it ever shows up in a profile, the
  fix is a narrower copy, not a shallower freeze.
- `Request#method` shadows `Object#method`. Deliberate, matching `Net::HTTPGenericRequest#method`,
  and documented at the accessor.
- `MediaType#charset` consults `Encoding.name_list`, so "unknown" means "unknown to this Ruby".
  `HTTP-24` asks for `nil` on an unknown charset and does not define the vocabulary; this is the
  narrowest available answer and is stated at the accessor.
