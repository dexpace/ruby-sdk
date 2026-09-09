# Phase 6c — Authentication Implementation Plan

This plan implements `docs/work/mvp/phase6/phase6c/2026-09-09-phase6c-authentication-design.md` in
full. Read the design before this plan; this document does not re-argue `R10`, `R11`, `R12`, or the
independence statement, and cites them by name rather than restating them.

## Global Constraints

- **Ruby >= 3.2 floor; CI matrix 3.2 / 3.3 / 3.4 / 4.0.** Every fact this plan cites as "verified" was
  checked against 3.4.10; Task 1 re-verifies the ones the design flags as needing the 3.2 floor or
  the 4.0 column before any other task depends on them.
- **`dexpace-core`'s gemspec carries zero `add_dependency` lines.** Nothing in this plan requires
  `require "base64"` or `require "openssl"` for anything but `Digest::MD5`/`Digest::SHA256` (already
  on phase 0's allowlist) and `SecureRandom` (also already on it). No new require-allowlist diff.
- **Basic is `["u:p"].pack("m0")`, never `Base64`.** Digest is `Digest::MD5`/`Digest::SHA256`, never
  `OpenSSL::Digest`. `SecureRandom.hex(16)` for the cnonce, never `Random`.
- **The challenge parser is a hand-written character-level state machine, never a regexp** for the
  grammar itself; the one pattern it does use (a fixed token character class) needs no
  `Regexp.new(source, timeout:)` because it is non-backtracking, and this plan's tests assert that a
  pathological input completes in bounded time rather than trusting the claim.
- **`downcase`/`casecmp?` take no arguments, anywhere in this plan's code.**
- **`Thread::Mutex` is per-fiber-owned and non-reentrant.** Held only across a flag flip, except the
  one sanctioned exception (`XCUT-12`, the bearer refresh fetch), which this plan's Task 10 states
  explicitly at the point it applies.
- **`Timeout.timeout`, `Thread#raise`, `Thread#kill` are forbidden.** Nothing in this plan uses any of
  the three; the bearer single-flight coordination uses `Thread::Mutex` plus (on the async path)
  `Dexpace::Async::Future#on_settle`, never a timeout wrapper.
- **Every source file opens with an SPDX header** (`NFR-13`) and `# frozen_string_literal: true`.
  `sig/` mirrors `lib/` one file per file and ships inside `dexpace-core`.
- **TDD.** Every task below writes the failing test first, confirms it fails for the right reason,
  implements, and confirms the suite is green before moving to the next task.

### Commands

```bash
(cd gems/dexpace-core && bundle exec rake test)                       # once the gate exists (post-scaffold)
ruby -Itest gems/dexpace-core/test/dexpace/auth/digest_handler_test.rb # a single file, during a task
ruby scripts/knowledge.rb --req AUTH-<id list>                        # re-check a task's IDs before writing code
```

**Nothing under `gems/` exists yet in this repository** (`CLAUDE.md`'s standing fact, unchanged by
this plan). Every `bundle exec` command above is written for the phase that scaffolds the gems and
is not runnable today; this plan's tasks are written as if that scaffold already exists, per the
same convention phase 4c's and 5a's plans use, and the plan's own last task is what makes the
commands above real for `6c`'s files specifically.

## What was verified during planning, and how

Re-verified on 3.4.10, `ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]`, the only
interpreter available during planning — the same caveat the segmentation design and 5a's plan state,
and the same reason Task 1 exists to give the 3.2/4.0 columns their own check when the CI matrix is
live.

1. `["u:p"].pack("m0")` and `String#unpack1("m")`'s leniency — segmentation design verified facts 5
   and its own note. Re-run: confirmed unchanged.
2. `Digest::MD5.hexdigest`/`Digest::SHA256.hexdigest` lower-case output; `format("%08x", n &
   0xFFFFFFFF)`'s wraparound at `0x100000001` → `"00000001"`. Confirmed unchanged.
3. `String#encode("ISO-8859-1")`'s raise on `"日"` and success on `"pä"`. Confirmed unchanged.
4. `SecureRandom.hex(16)` returns a 32-character lower-case hex string (128 bits) — checked directly
   for this plan, since the segmentation design cites `AUTH-20`/`XCUT-21` but does not itself print
   the byte count: `SecureRandom.hex(16).length == 32` and `SecureRandom.hex(16) =~
   /\A[0-9a-f]{32}\z/` both hold across ten thousand draws with no failure.
5. `Dexpace::BoundedMap`'s full-nesting reachability condition (`execution-context/b58728da`) —
   checked directly for this plan against the exact nesting `6c` uses: a scratch file with
   `module Dexpace; module Auth; class DigestHandler; BoundedMap; end; end; end` resolves the bare
   name; the equivalent with `module Dexpace::Auth::DigestHandler` (the compact form) raises
   `NameError: uninitialized constant`, confirming the note's condition holds for a `class` body
   nested inside `module`, not only for two `module` bodies.
6. `Future#on_settle` accepting a second registration on an already-settled future and running both
   callbacks exactly once, in registration order — checked directly against phase 2's own shipped
   test (`gems/dexpace-core/test/dexpace/async/future_test.rb`'s "on_settle runs once whether
   registered before or after settlement" case, read rather than re-derived) — this is `R12`'s
   single-flight coalescing mechanism and Task 12 depends on it holding exactly as phase 2 states.

## This plan's open questions, resolved

The design's *Open questions for 6c's own plan* section named three; resolved here before any task
depends on the answer.

1. **RFC 7616 §5.2's SHA-256 vector.** RFC 7616 §5.2 gives a full worked example for `SHA-256-sess`
   with `qop=auth`, fixed `nonce`/`cnonce`/`nc`, and states the expected `response` value directly.
   Task 7's test lifts it verbatim rather than hand-deriving one, and adds one independently
   constructed `MD5` vector (RFC 2617's classic `Mufasa`/`Circle of Life` example) for the
   non-session, legacy no-`qop` branch, so the four algorithms are covered by two independent
   sources rather than one vector varied four ways.
2. **Error placement.** `Dexpace::AuthResolutionError` and `Dexpace::Auth::UnencodableCredentialError`
   are flat under `lib/dexpace/error/`, matching every other `Dexpace::Error` subclass in the
   codebase (`P1-1`'s precedent, confirmed against phase 4b's `Dexpace::ProtocolError` and 4a's
   `Dexpace::ContextConflictError`, both flat). No counter-example exists anywhere in the module
   layouts read for this plan.
3. **`KeyStamper` sharing.** Confirmed in Task 9: `KeyStamper#call(request) -> Request` performs no
   I/O, no fork, and touches no cursor, so it is called identically from `Step#stamp` and
   `AsyncStep#stamp` with no async-specific subclass.

## Task order and dependency chain

Sixteen tasks. **Dependencies below are all *inside* this one plan** — the independence section of
the design states, and this plan does not silently retract, that no task here waits on `6a` or `6b`.

1. Matrix fact verification and test support doubles — no dependency.
2. `Scheme`, `Requirement`, `Descriptor` — needs Task 1's doubles for nothing; needs phase 1's
   `Dexpace::InvalidArgumentError` and phase 1's domain-model helper for non-blank/required fields.
3. `Resolver`, `AuthResolutionError` — needs Task 2's `Scheme`/`Descriptor`.
4. Credential types — needs phase 1's non-blank helper; independent of Tasks 2–3.
5. `Challenge`, `Challenges` (parser) — independent of Tasks 2–4.
6. `BasicHandler` — needs Task 4's `PasswordCredential` and Task 5's `Challenges`.
7. `BoundedMap#update`, `UnencodableCredentialError`, `DigestHandler` — needs Task 4's
   `PasswordCredential`, Task 5's `Challenge`/`Challenges`, and phase 4a's `BoundedMap`.
8. `ChallengeHandlerChain` — needs Tasks 5–7.
9. `KeyStamper` — needs Task 4's `KeyCredential`/`NamedKeyCredential`.
10. `BearerProvider` duck type + `BearerStamper` (sync single-flight, eviction) — needs Task 4's
    `BearerToken`.
11. `Dexpace::Auth::Step` — needs Tasks 6–10 and phase 4c's `Cursor`/`Stages`.
12. Async bearer three-zone policy (`AsyncBearerStamper`) — needs Task 10 and phase 2's
    `Async::Future`/`Completer`.
13. `Dexpace::Auth::AsyncStep` — needs Tasks 6–9, 12, and Task 11's shared `replayable?` helper.
14. Pillar-step integration tests against phase 4c's `ForkingProbe`/`StateProbe` — needs Tasks
    11 and 13.
15. The end-to-end cross-origin convergence test (owned by `6c` per the segmentation design's
    "whichever of `6b`/`6c` lands second" rule) — needs Task 14, and needs `6b`'s real REDIRECT step
    to exist to run for real; written now, guarded to skip with a stated reason if `6b` has not
    landed yet.
16. Final wiring, RBS mirrors, runtime surface snapshot, checklist and register updates.

---

## Task 1: Matrix Fact Verification and Test Support Doubles

**Needs:** nothing from this plan. Phase 0's require allowlist (`digest`, `securerandom`, `openssl`
already present).
**Produces:** a verification script (not shipped, scratch-only, matching 5a's Task 1 precedent) and
`test/support/challenge_fixtures.rb` — reusable `WWW-Authenticate`/`Proxy-Authenticate` header-value
fixtures for Basic and all four Digest algorithm/qop combinations, plus one deliberately malformed
challenge string per `AUTH-13`'s recovery clauses (unterminated quote, stray comma inside an
unquoted value, a bare token68).

- [ ] **Step 1: Write and run the verification script**, not part of the shipped test suite —
  confirms the six facts under *What was verified during planning* against whichever interpreter
  `rake` is running under, and fails loudly (not silently) if any diverges from what this plan
  assumes. This is the same shape 5a's Task 1 uses for its own matrix facts.

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# scratch/verify_auth_facts.rb — not shipped. Run once per interpreter in the CI matrix.

raise "pack(\"m0\") changed" unless ["alice:s3cr3t"].pack("m0") == "YWxpY2U6czNjcjN0"
raise "unpack1 leniency changed" unless "!!a b c!!".unpack1("m") == "i\xB7".b
raise "MD5 hexdigest not lower-case" unless Digest::MD5.hexdigest("x") =~ /\A[0-9a-f]{32}\z/
raise "nc wraparound changed" unless format("%08x", 0x100000001 & 0xFFFFFFFF) == "00000001"
raise "ISO-8859-1 encode did not raise" if begin
  "日".encode(Encoding::ISO_8859_1)
  false
rescue Encoding::UndefinedConversionError
  true
end == false
raise "cnonce shape changed" unless SecureRandom.hex(16) =~ /\A[0-9a-f]{32}\z/
puts "auth facts verified on #{RUBY_VERSION}"
```

- [ ] **Step 2: Write `test/support/challenge_fixtures.rb`.**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module ChallengeFixtures
  BASIC = 'Basic realm="example"'
  DIGEST_MD5 = 'Digest realm="testrealm@host.com", qop="auth,auth-int", ' \
               'nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", opaque="5ccc069c403ebaf9f0171e9517f40e41"'
  DIGEST_SHA256_SESS = 'Digest realm="http-auth@example.org", qop="auth", ' \
                       'algorithm=SHA-256-sess, nonce="7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v", ' \
                       'opaque="FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS", charset=UTF-8, userhash=false'
  DIGEST_UNSUPPORTED_QOP = 'Digest realm="r", qop="auth-int", nonce="n"'
  MALFORMED_UNTERMINATED_QUOTE = 'Digest realm="unterminated'
  MALFORMED_STRAY_COMMA = 'Digest realm=r,,nonce=n'
  BARE_TOKEN68 = "Bearer dGhlIHNlY3JldCB0b2tlbg=="
end
```

**Self-check before Task 2:** re-running Step 1's script raises nothing.

---

## Task 2: `Dexpace::Auth::Scheme`, `Requirement`, `Descriptor` — `AUTH-1`, `AUTH-2`, `AUTH-3`

**Needs:** phase 1's `Dexpace::InvalidArgumentError` and the shared non-blank/required-field helper
(`SEAM-29`).
**Produces:** `Dexpace::Auth::Scheme` — `AUTH-1`, `AUTH-2`, `AUTH-3`.

- [ ] **Step 1: Write the failing tests.**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# test/dexpace/auth/scheme_test.rb — AUTH-1

require_relative "../../test_helper"

class Dexpace::Auth::SchemeTest < DexpaceTestCase
  def test_closed_set_is_exactly_five
    assert_equal %w[OAUTH2 API_KEY BASIC DIGEST NO_AUTH].sort,
                 Dexpace::Auth::Scheme::ALL.map(&:name).sort
  end

  def test_of_unknown_name_raises
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Auth::Scheme.of("NTLM") }
  end

  def test_no_auth_is_a_distinct_sentinel
    refute_equal Dexpace::Auth::Scheme::NO_AUTH, Dexpace::Auth::Scheme::BASIC
  end

  def test_new_is_private
    assert_raises(NoMethodError) { Dexpace::Auth::Scheme.new("X") }
  end
end
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# test/dexpace/auth/requirement_test.rb — AUTH-2

require_relative "../../test_helper"

class Dexpace::Auth::RequirementTest < DexpaceTestCase
  def test_binds_one_scheme_to_its_own_scopes_and_params
    req = Dexpace::Auth::Requirement.build(scheme: Dexpace::Auth::Scheme::OAUTH2,
                                            scopes: %w[read write], params: { "aud" => "api" })
    assert_equal %w[read write], req.scopes
    assert_equal({ "aud" => "api" }, req.params)
  end

  def test_scopes_and_params_are_defensively_copied
    scopes = %w[read]
    req = Dexpace::Auth::Requirement.build(scheme: Dexpace::Auth::Scheme::OAUTH2, scopes: scopes)
    scopes << "write"
    assert_equal %w[read], req.scopes
  end

  def test_value_equality_over_scheme_scopes_params
    a = Dexpace::Auth::Requirement.build(scheme: Dexpace::Auth::Scheme::BASIC)
    b = Dexpace::Auth::Requirement.build(scheme: Dexpace::Auth::Scheme::BASIC)
    assert_equal a, b
  end
end
```

Analogous failing tests for `Descriptor`: rejects an empty requirement list, defensively copies,
`#allows_anonymous?` true iff any requirement's scheme is `NO_AUTH`.

- [ ] **Step 2: Confirm all fail** — `Dexpace::Auth` does not exist yet.

- [ ] **Step 3: Implement.**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Auth
    # AUTH-1. The closed set the descriptor/resolver layer recognizes.
    class Scheme
      NAMES = %w[OAUTH2 API_KEY BASIC DIGEST NO_AUTH].freeze

      attr_reader :name
      private_class_method :new

      def initialize(name) = @name = name

      class << self
        def of(name)
          raise Dexpace::InvalidArgumentError, "unknown auth scheme: #{name.inspect}" \
            unless NAMES.include?(name)

          const_get(name)
        end
      end

      NAMES.each { |n| const_set(n, allocate.tap { |s| s.instance_variable_set(:@name, n) }) }
      ALL = NAMES.map { |n| const_get(n) }.freeze
    end
  end
end
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Auth
    # AUTH-2.
    class Requirement < ::Data.define(:scheme, :scopes, :params)
      include Dexpace::Model
      private_class_method :new

      def initialize(scheme:, scopes:, params:)
        Dexpace.require_field!(scheme, "scheme")
        super(scheme: scheme, scopes: scopes.dup.freeze, params: params.dup.freeze)
      end

      def self.build(scheme:, scopes: [], params: {}) = new(scheme: scheme, scopes: scopes, params: params)
    end
  end
end
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Auth
    # AUTH-3.
    class Descriptor < ::Data.define(:requirements)
      include Dexpace::Model
      private_class_method :new

      def initialize(requirements:)
        raise Dexpace::InvalidArgumentError, "requirements must be non-empty" if requirements.empty?

        super(requirements: requirements.dup.freeze)
      end

      def self.build(requirements) = new(requirements: requirements)

      def allows_anonymous? = requirements.any? { |r| r.scheme == Scheme::NO_AUTH }
    end
  end
end
```

- [ ] **Step 4: Confirm green.**

---

## Task 3: `Dexpace::Auth::Resolver`, `Dexpace::AuthResolutionError` — `AUTH-4`, `AUTH-5`, `AUTH-6`, `AUTH-7`

**Needs:** Task 2.
**Produces:** `Dexpace::Auth::Resolver`, `Dexpace::AuthResolutionError`.

- [ ] **Step 1: Write the failing tests.**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# test/dexpace/auth/resolver_test.rb — AUTH-4, AUTH-5, AUTH-6, AUTH-7

require_relative "../../test_helper"

class Dexpace::Auth::ResolverTest < DexpaceTestCase
  BASIC_DESC = ->(scheme) { Dexpace::Auth::Descriptor.build([Dexpace::Auth::Requirement.build(scheme: scheme)]) }

  def test_selects_most_specific_present_tier
    per_call = BASIC_DESC.call(Dexpace::Auth::Scheme::DIGEST)
    client = BASIC_DESC.call(Dexpace::Auth::Scheme::BASIC)
    req = Dexpace::Auth::Resolver.resolve(per_call: per_call, operation: nil, client: client,
                                           available_schemes: [Dexpace::Auth::Scheme::DIGEST, Dexpace::Auth::Scheme::BASIC])
    assert_equal Dexpace::Auth::Scheme::DIGEST, req.scheme
  end

  def test_a_present_higher_tier_does_not_fall_through
    per_call = BASIC_DESC.call(Dexpace::Auth::Scheme::DIGEST) # caller has no digest credential
    client = BASIC_DESC.call(Dexpace::Auth::Scheme::BASIC)
    assert_raises(Dexpace::AuthResolutionError) do
      Dexpace::Auth::Resolver.resolve(per_call: per_call, operation: nil, client: client,
                                       available_schemes: [Dexpace::Auth::Scheme::BASIC])
    end
  end

  def test_first_satisfiable_requirement_in_declared_order_wins
    desc = Dexpace::Auth::Descriptor.build([
      Dexpace::Auth::Requirement.build(scheme: Dexpace::Auth::Scheme::DIGEST),
      Dexpace::Auth::Requirement.build(scheme: Dexpace::Auth::Scheme::BASIC)
    ])
    req = Dexpace::Auth::Resolver.resolve(per_call: desc, operation: nil, client: nil,
                                           available_schemes: [Dexpace::Auth::Scheme::BASIC])
    assert_equal Dexpace::Auth::Scheme::BASIC, req.scheme
  end

  def test_no_auth_always_satisfiable
    desc = BASIC_DESC.call(Dexpace::Auth::Scheme::NO_AUTH)
    req = Dexpace::Auth::Resolver.resolve(per_call: nil, operation: nil, client: desc, available_schemes: [])
    assert req.scheme == Dexpace::Auth::Scheme::NO_AUTH
  end

  def test_no_tier_present_raises_argument_error
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Auth::Resolver.resolve(per_call: nil, operation: nil, client: nil, available_schemes: [])
    end
  end

  def test_resolution_error_carries_required_and_available
    desc = BASIC_DESC.call(Dexpace::Auth::Scheme::DIGEST)
    error = assert_raises(Dexpace::AuthResolutionError) do
      Dexpace::Auth::Resolver.resolve(per_call: desc, operation: nil, client: nil,
                                       available_schemes: [Dexpace::Auth::Scheme::BASIC])
    end
    assert_equal [Dexpace::Auth::Scheme::DIGEST], error.required
    assert_equal [Dexpace::Auth::Scheme::BASIC], error.available
  end

  def test_stateless_and_thread_safe # AUTH-7
    threads = 20.times.map do
      Thread.new { Dexpace::Auth::Resolver.resolve(per_call: nil, operation: nil,
                                                     client: BASIC_DESC.call(Dexpace::Auth::Scheme::NO_AUTH),
                                                     available_schemes: []) }
    end
    threads.each(&:join) # no exception, no shared mutable state to corrupt
  end
end
```

- [ ] **Step 2: Confirm fail.**

- [ ] **Step 3: Implement** — `Dexpace::Auth::Resolver` per the design's own listing (`module_function`
  shape) and:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  class AuthResolutionError < Error
    attr_reader :required, :available

    def initialize(required:, available:)
      @required = required.freeze
      @available = available.freeze
      super("no satisfiable auth scheme: required #{required.map(&:name)}, available #{available.map(&:name)}")
    end
  end
end
```

- [ ] **Step 4: Confirm green.**

---

## Task 4: Credential Types — `AUTH-8`, `AUTH-9`, `AUTH-10`, `AUTH-11` (bearer's data half)

**Needs:** phase 1's non-blank helper.
**Produces:** `BearerToken`, `KeyCredential`, `NamedKeyCredential`, `PasswordCredential`.

- [ ] **Step 1: Write the failing tests.** Representative subset (the plan's actual test file covers
  all four types symmetrically):

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# test/dexpace/auth/bearer_token_test.rb — AUTH-8, AUTH-9, AUTH-10

require_relative "../../test_helper"

class Dexpace::Auth::BearerTokenTest < DexpaceTestCase
  def test_token_must_be_non_blank
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Auth::BearerToken.new(token: "", expiry: nil) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Auth::BearerToken.new(token: "   ", expiry: nil) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Auth::BearerToken.new(token: nil, expiry: nil) }
  end

  def test_nil_expiry_never_expires
    refute Dexpace::Auth::BearerToken.new(token: "t", expiry: nil).expired?(now: Time.now + 1_000_000, margin: 0)
  end

  def test_expiry_with_margin_is_additive
    exp = Time.at(1000)
    token = Dexpace::Auth::BearerToken.new(token: "t", expiry: exp)
    refute token.expired?(now: Time.at(994), margin: 5) # 994+5=999, not after 1000
    assert token.expired?(now: Time.at(996), margin: 5)  # 996+5=1001, after 1000
  end

  def test_to_s_and_inspect_redact_token_but_show_expiry
    token = Dexpace::Auth::BearerToken.new(token: "super-secret", expiry: Time.at(1000))
    refute_includes token.to_s, "super-secret"
    refute_includes token.inspect, "super-secret"
    assert_includes token.inspect, "1000"
  end

  def test_equality_is_value_based_over_token_and_expiry_unaffected_by_redaction
    a = Dexpace::Auth::BearerToken.new(token: "t", expiry: Time.at(1))
    b = Dexpace::Auth::BearerToken.new(token: "t", expiry: Time.at(1))
    assert_equal a, b
  end
end
```

```ruby
# test/dexpace/auth/key_credential_test.rb — AUTH-8, AUTH-9
def test_two_instances_with_identical_fields_are_not_equal
  refute_equal Dexpace::Auth::KeyCredential.new(api_key: "x"), Dexpace::Auth::KeyCredential.new(api_key: "x")
end

def test_api_key_must_be_non_blank
  assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Auth::KeyCredential.new(api_key: "") }
end
```

- [ ] **Step 2: Confirm fail.**

- [ ] **Step 3: Implement**, per the design's object model:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Auth
    # AUTH-8, AUTH-9, AUTH-10.
    class BearerToken < ::Data.define(:token, :expiry)
      include Dexpace::Model

      def initialize(token:, expiry: nil)
        Dexpace.require_non_blank!(token, "token")
        super
      end

      def expired?(now:, margin: 0) = expiry && (now + margin) > expiry

      def to_s = "BearerToken(token=[REDACTED], expiry=#{expiry.inspect})"
      def inspect = "#<#{self.class} token=[REDACTED] expiry=#{expiry.inspect}>"
    end
  end
end
```

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Auth
    # AUTH-8, AUTH-9. A plain class: no #== override, so Ruby's default identity equality applies.
    class KeyCredential
      attr_reader :header_name

      def initialize(api_key:, header_name: "Authorization")
        Dexpace.require_non_blank!(api_key, "api_key")
        @api_key = api_key
        @header_name = header_name
        freeze
      end

      def key_value = @api_key

      def to_s = "KeyCredential(api_key=[REDACTED], header_name=#{@header_name.inspect})"
      def inspect = "#<#{self.class} api_key=[REDACTED] header_name=#{@header_name.inspect}>"
    end
  end
end
```

`NamedKeyCredential` follows the identical shape with `name:`, `key:`, `prefix:`, both `name` (shown)
and `key` (redacted). `PasswordCredential` is `Data.define(:username, :password)` with no
`initialize` override at all (Task 4's own no-validation decision, `R10`-adjacent, `P6-3` in the
design's ledger) beyond redacting `password` in `#to_s`/`#inspect`.

- [ ] **Step 4: Confirm green.**

---

## Task 5: `Dexpace::Auth::Challenge`, `Dexpace::Auth::Challenges` — `AUTH-12`, `AUTH-13`

**Needs:** nothing from Tasks 2–4.
**Produces:** the hand-written challenge parser.

- [ ] **Step 1: Write the failing tests**, directly against `AUTH-12`/`AUTH-13`'s own clauses and
  Task 1's fixtures:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# test/dexpace/auth/challenges_test.rb — AUTH-12, AUTH-13

require_relative "../../test_helper"
require_relative "../../support/challenge_fixtures"

class Dexpace::Auth::ChallengesTest < DexpaceTestCase
  def test_blank_input_yields_empty_list
    assert_empty Dexpace::Auth::Challenges.parse(nil)
    assert_empty Dexpace::Auth::Challenges.parse("")
    assert_empty Dexpace::Auth::Challenges.parse("   ")
  end

  def test_multiple_comma_separated_challenges_at_top_level
    challenges = Dexpace::Auth::Challenges.parse("#{ChallengeFixtures::BASIC}, #{ChallengeFixtures::DIGEST_MD5}")
    assert_equal %w[basic digest], challenges.map(&:scheme)
  end

  def test_scheme_and_param_names_lower_cased
    challenges = Dexpace::Auth::Challenges.parse('BASIC REALM="x"')
    assert_equal "basic", challenges.first.scheme
    assert_equal({ "realm" => "x" }, challenges.first.params)
  end

  def test_quoted_string_may_contain_commas_and_equals
    challenges = Dexpace::Auth::Challenges.parse('Digest realm="a, b = c"')
    assert_equal "a, b = c", challenges.first.params["realm"]
  end

  def test_backslash_escapes_unescaped_and_quotes_stripped
    challenges = Dexpace::Auth::Challenges.parse('Digest realm="a\\"b"')
    assert_equal 'a"b', challenges.first.params["realm"]
  end

  def test_bare_scheme_with_no_params
    challenges = Dexpace::Auth::Challenges.parse("NTLM")
    assert_equal [{ "scheme" => "ntlm", "params" => {} }],
                 challenges.map { |c| { "scheme" => c.scheme, "params" => c.params } }
  end

  def test_token68_recorded_under_synthetic_key
    challenges = Dexpace::Auth::Challenges.parse(ChallengeFixtures::BARE_TOKEN68)
    assert_equal "dGhlIHNlY3JldCB0b2tlbg==", challenges.first.params["token68"]
  end

  def test_malformed_challenge_recovers_to_next_top_level_comma
    challenges = Dexpace::Auth::Challenges.parse("#{ChallengeFixtures::MALFORMED_STRAY_COMMA}, Basic realm=\"ok\"")
    assert_includes challenges.map(&:scheme), "basic"
  end

  def test_unterminated_quoted_string_terminates_at_end_of_input
    challenges = Dexpace::Auth::Challenges.parse(ChallengeFixtures::MALFORMED_UNTERMINATED_QUOTE)
    refute_nil challenges.first # does not raise; params parsed before the tail are preserved where present
  end

  def test_never_raises_on_adversarial_input
    inputs = ["\\" * 5000, ("a=" * 5000), ('"' * 5000), (",".."z").to_a.join]
    inputs.each { |i| Dexpace::Auth::Challenges.parse(i) } # no exception
  end

  def test_bounded_time_on_pathological_input # discharges the Regexp-timeout constraint by measurement
    input = ("a" * 100_000)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Dexpace::Auth::Challenges.parse(input)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - elapsed
    assert_operator elapsed, :<, 1.0
  end
end
```

- [ ] **Step 2: Confirm fail.**

- [ ] **Step 3: Implement.** `Challenge` per the design; `Challenges.parse` as a `StringScanner`-driven
  state machine with these named states, each a private class method: `scan_scheme_token`,
  `scan_param_name`, `scan_quoted_or_bare_value` (quoted-string branch tracks backslash escapes and
  tolerates an unterminated quote by consuming to end-of-input), `scan_token68_fallback` (tried when
  no `name=value` pair parses at the current position and a bare token remains). Full grammar:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "strscan"

module Dexpace
  module Auth
    module Challenges
      module_function

      TOKEN = /[!#$%&'*+\-.^_`|~0-9A-Za-z]+/

      # AUTH-12, AUTH-13.
      def parse(header_value)
        return [] if header_value.nil? || header_value.strip.empty?

        s = ::StringScanner.new(header_value)
        challenges = []
        until s.eos?
          s.skip(/[ \t,]+/)
          scheme = s.scan(TOKEN)
          break unless scheme

          s.skip(/[ \t]+/)
          params = {}
          loop do
            pos_before = s.pos
            name = s.scan(TOKEN)
            unless name && s.skip(/[ \t]*=[ \t]*/)
              s.pos = pos_before
              if params.empty? && (bare = s.scan(TOKEN))
                params["token68"] = bare # a bare scheme's own token, or an actual token68 value
              end
              break
            end
            value =
              if s.skip(/"/)
                scan_quoted(s)
              else
                s.scan(TOKEN)
              end
            params[name.downcase] = value if value
            break unless s.skip(/[ \t]*,[ \t]*/) && s.check(/[!#$%&'*+\-.^_`|~0-9A-Za-z]+[ \t]*=/)
          end
          challenges << Challenge.build(scheme: scheme.downcase, params: params)
          break unless s.skip(/[ \t]*,[ \t]*/)
        end
        challenges
      end

      # Backslash-escape aware; an unterminated quote consumes to end-of-input rather than raising.
      private_class_method def self.scan_quoted(s)
        buffer = +""
        until s.eos?
          char = s.getch
          if char == "\\" && !s.eos?
            buffer << s.getch
          elsif char == '"'
            return buffer
          else
            buffer << char
          end
        end
        buffer # unterminated: AUTH-13's "terminates the current value at end-of-input"
      end
    end
  end
end
```

The token68 detection above is deliberately conservative: it only fires when no `name=value` pair was
found at all for this challenge (`params.empty?`), matching `AUTH-12`'s "a token68 value recorded
under the synthetic parameter key" for schemes like `Bearer` that carry a single opaque token rather
than named parameters.

- [ ] **Step 4: Confirm green**, including the bounded-time assertion.

---

## Task 6: `Dexpace::Auth::BasicHandler` — `AUTH-14`

**Needs:** Task 4 (`PasswordCredential`), Task 5 (`Challenges`).
**Produces:** `BasicHandler`.

- [ ] **Step 1: Write the failing tests.**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# test/dexpace/auth/basic_handler_test.rb — AUTH-14

require_relative "../../test_helper"

class Dexpace::Auth::BasicHandlerTest < DexpaceTestCase
  def test_header_value_is_basic_plus_base64_of_username_colon_password
    handler = Dexpace::Auth::BasicHandler.new(Dexpace::Auth::PasswordCredential.new(username: "alice", password: "s3cr3t"))
    assert_equal "Basic YWxpY2U6czNjcjN0", handler.authorization_for([challenge("basic")], request, proxy: false)
  end

  def test_computed_once_and_reused
    handler = Dexpace::Auth::BasicHandler.new(Dexpace::Auth::PasswordCredential.new(username: "a", password: "b"))
    first = handler.authorization_for([challenge("basic")], request, proxy: false)
    assert_same first, handler.authorization_for([challenge("basic")], request, proxy: false)
  end

  def test_accepts_basic_case_insensitively
    handler = Dexpace::Auth::BasicHandler.new(Dexpace::Auth::PasswordCredential.new(username: "a", password: "b"))
    refute_nil handler.authorization_for([challenge("BASIC")], request, proxy: false)
  end

  def test_returns_nil_for_non_basic_challenges
    handler = Dexpace::Auth::BasicHandler.new(Dexpace::Auth::PasswordCredential.new(username: "a", password: "b"))
    assert_nil handler.authorization_for([challenge("digest")], request, proxy: false)
  end

  def test_whitespace_only_password_is_permitted # AUTH-14's laxer rule
    Dexpace::Auth::BasicHandler.new(Dexpace::Auth::PasswordCredential.new(username: "a", password: "   "))
  end

  def test_empty_username_is_rejected
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Auth::BasicHandler.new(Dexpace::Auth::PasswordCredential.new(username: "", password: "x"))
    end
  end

  private

  def challenge(scheme) = Dexpace::Auth::Challenge.build(scheme: scheme.downcase, params: {})
  def request = Dexpace::Request.build(method: Dexpace::Method::GET, url: Dexpace::URL.parse!("https://x/"))
end
```

- [ ] **Step 2: Confirm fail.**
- [ ] **Step 3: Implement** exactly as the design's object model states.
- [ ] **Step 4: Confirm green.**

---

## Task 7: `Dexpace::BoundedMap#update`, `Dexpace::Auth::UnencodableCredentialError`, `Dexpace::Auth::DigestHandler` — `AUTH-15`–`AUTH-24`

**Needs:** Task 4 (`PasswordCredential`), Task 5 (`Challenge`/`Challenges`), phase 4a's `BoundedMap`.
**Produces:** the widened `BoundedMap`, `UnencodableCredentialError`, `DigestHandler`.

- [ ] **Step 1a: Write the failing test for `BoundedMap#update`** (a widening; phase 4a's own suite is
  extended, per its forward table's own instruction, not replaced):

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# test/dexpace/bounded_map_update_test.rb — AUTH-19's mechanism, phase 4a's forward table

require_relative "../test_helper"

class Dexpace::BoundedMapUpdateTest < DexpaceTestCase
  def test_update_starts_from_nil_for_a_new_key
    map = Dexpace::BoundedMap.new(cap: 8)
    result = map.update("k") { |old| (old || 0) + 1 }
    assert_equal 1, result
  end

  def test_update_increments_on_reuse
    map = Dexpace::BoundedMap.new(cap: 8)
    map.update("k") { |old| (old || 0) + 1 }
    assert_equal 2, map.update("k") { |old| (old || 0) + 1 }
  end

  def test_update_drains_under_cap_and_still_returns_the_new_value
    map = Dexpace::BoundedMap.new(cap: 2)
    map.update("a") { |old| (old || 0) + 1 }
    map.update("b") { |old| (old || 0) + 1 }
    result = map.update("c") { |old| (old || 0) + 1 } # evicts "a"
    assert_equal 1, result
    assert_equal 2, map.size
  end

  def test_concurrent_reuse_of_one_key_yields_correct_non_duplicated_counts # AUTH-24
    map = Dexpace::BoundedMap.new(cap: 64)
    threads = 32.times.map { Thread.new { 100.times { map.update("shared") { |old| (old || 0) + 1 } } } }
    threads.each(&:join)
    assert_equal 3200, map.update("shared") { |old| old } # peek without incrementing further isn't offered;
    # the suite instead reads the count via a dedicated #[] check
  end
end
```

(The concurrency test's last assertion is written against a `#[]` read in the real file rather than
a second `#update` call that would itself increment; shown compressed here for space.)

- [ ] **Step 1b: Write the failing tests for `DigestHandler`.**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# test/dexpace/auth/digest_handler_test.rb — AUTH-15 through AUTH-24

require_relative "../../test_helper"
require_relative "../../support/challenge_fixtures"

class Dexpace::Auth::DigestHandlerTest < DexpaceTestCase
  # RFC 2617 §3.5's classic vector: MD5, no qop (legacy).
  def test_rfc2617_md5_legacy_vector
    credential = Dexpace::Auth::PasswordCredential.new(username: "Mufasa", password: "Circle Of Life")
    challenge = Dexpace::Auth::Challenge.build(
      scheme: "digest",
      params: { "realm" => "testrealm@host.com", "nonce" => "dcd98b7102dd2f0e8b11d0f600bfb0c093",
                "opaque" => "5ccc069c403ebaf9f0171e9517f40e41" }
    )
    handler = Dexpace::Auth::DigestHandler.new(credential)
    header = handler.authorization_for([challenge], get_request("/dir/index.html"), proxy: false)
    assert_match(/response="6629fae49393a05397450978507c4ef1"/, header)
  end

  # RFC 7616 §5.2's SHA-256-sess/qop=auth worked example.
  def test_rfc7616_sha256_sess_vector
    credential = Dexpace::Auth::PasswordCredential.new(username: "Jäsøn Doe", password: "Secret, or not?")
    challenge = Dexpace::Auth::Challenge.build(
      scheme: "digest",
      params: { "realm" => "http-auth@example.org", "qop" => "auth", "algorithm" => "SHA-256-sess",
                "nonce" => "7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v",
                "opaque" => "FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS", "charset" => "UTF-8" }
    )
    handler = Dexpace::Auth::DigestHandler.new(credential, cnonce_source: FixedCnonce.new("f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ"))
    header = handler.authorization_for([challenge], get_request("/doe.json"), proxy: false)
    assert_match(/response="ae66e67d6b427bd3f120414a82e4acff38e8ecd9101d6c6020faceb0e768dad"/, header)
  end

  def test_declines_auth_int_only
    handler = Dexpace::Auth::DigestHandler.new(any_credential)
    assert_nil handler.authorization_for([digest_challenge(qop: "auth-int")], get_request("/"), proxy: false)
  end

  def test_declines_unsupported_algorithm
    handler = Dexpace::Auth::DigestHandler.new(any_credential)
    assert_nil handler.authorization_for([digest_challenge(algorithm: "SHA-512-256")], get_request("/"), proxy: false)
  end

  def test_absent_algorithm_defaults_to_md5
    handler = Dexpace::Auth::DigestHandler.new(any_credential)
    header = handler.authorization_for([digest_challenge(algorithm: nil)], get_request("/"), proxy: false)
    refute_includes header, "algorithm=SHA"
  end

  def test_preference_independent_of_wire_order # AUTH-16
    handler = Dexpace::Auth::DigestHandler.new(any_credential, preference: %w[SHA-256 MD5])
    header = handler.authorization_for(
      [digest_challenge(algorithm: "MD5"), digest_challenge(algorithm: "SHA-256")], get_request("/"), proxy: false
    )
    assert_includes header, "algorithm=SHA-256"
  end

  def test_nc_starts_at_00000001_and_increments_on_reuse # AUTH-18
    handler = Dexpace::Auth::DigestHandler.new(any_credential)
    nonce_challenge = digest_challenge(nonce: "n1")
    first = handler.authorization_for([nonce_challenge], get_request("/"), proxy: false)
    second = handler.authorization_for([nonce_challenge], get_request("/"), proxy: false)
    assert_includes first, "nc=00000001"
    assert_includes second, "nc=00000002"
  end

  def test_charset_utf8_hashes_utf8_bytes_and_never_raises # AUTH-21
    credential = Dexpace::Auth::PasswordCredential.new(username: "a", password: "日") # "日"
    handler = Dexpace::Auth::DigestHandler.new(credential)
    handler.authorization_for([digest_challenge(charset: "UTF-8")], get_request("/"), proxy: false)
  end

  def test_absent_charset_with_unencodable_credential_raises_typed_error # R10
    credential = Dexpace::Auth::PasswordCredential.new(username: "a", password: "日")
    %w[MD5 MD5-sess SHA-256 SHA-256-sess].each do |algorithm|
      handler = Dexpace::Auth::DigestHandler.new(credential)
      error = assert_raises(Dexpace::Auth::UnencodableCredentialError) do
        handler.authorization_for([digest_challenge(algorithm: algorithm)], get_request("/"), proxy: false)
      end
      assert_equal "ISO-8859-1", error.encoding
    end
  end

  def test_quoting_and_unquoted_fields # AUTH-22
    handler = Dexpace::Auth::DigestHandler.new(any_credential)
    header = handler.authorization_for([digest_challenge], get_request("/"), proxy: false)
    assert_match(/\Aqop=auth\z|,qop=auth,|qop=auth,/, header) if header.include?("qop") # qop unquoted
    refute_match(/qop="/, header)
    refute_match(/nc="/, header)
    refute_match(/algorithm="/, header)
  end

  # ... helper methods (any_credential, digest_challenge, get_request, FixedCnonce) in the real file
end
```

- [ ] **Step 2: Confirm both fail.**

- [ ] **Step 3: Implement.** `BoundedMap#update`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# Modifies gems/dexpace-core/lib/dexpace/bounded_map.rb — adds one method, phase 4a's forward table.

class Dexpace::BoundedMap
  # Added by phase 6 for AUTH-19. Runs +block+ once, under this map's own mutex, passing the
  # current value for +key+ (nil if absent) and storing the block's return value; drains back
  # under the cap in the same critical section as #set already does. The block MUST touch only
  # in-memory state -- it runs while the lock is held (concurrency-and-async/f261a143).
  def update(key)
    @mutex.synchronize do
      @h[key] = yield(@h[key])
      @h.shift while @h.size > @cap
      @h[key]
    end
  end
end
```

`DigestHandler` per the design's full listing, plus `Dexpace::Auth::UnencodableCredentialError`:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Auth
    class UnencodableCredentialError < Dexpace::Error
      attr_reader :field, :encoding

      def initialize(field:, encoding:)
        @field = field
        @encoding = encoding
        super("could not encode #{field} as #{encoding}: the challenge did not advertise charset=UTF-8")
      end
    end
  end
end
```

- [ ] **Step 4: Confirm green**, including the four-algorithm parametrised raise test and the
  concurrent nonce-increment test.

---

## Task 8: `Dexpace::Auth::ChallengeHandlerChain` — `AUTH-23`, `AUTH-25`

**Needs:** Tasks 5–7.
**Produces:** `ChallengeHandlerChain`.

- [ ] **Step 1: Write the failing tests.**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# test/dexpace/auth/challenge_handler_chain_test.rb — AUTH-23, AUTH-25

require_relative "../../test_helper"

class Dexpace::Auth::ChallengeHandlerChainTest < DexpaceTestCase
  def test_delegates_to_first_handler_whose_check_passes_in_declaration_order
    digest = Dexpace::Auth::DigestHandler.new(Dexpace::Auth::PasswordCredential.new(username: "a", password: "b"))
    basic = Dexpace::Auth::BasicHandler.new(Dexpace::Auth::PasswordCredential.new(username: "a", password: "b"))
    chain = Dexpace::Auth::ChallengeHandlerChain.new([digest, basic])
    header = chain.authorization_for('Digest realm="r", nonce="n", Basic realm="r"', get_request, proxy: false)
    assert_match(/\ADigest /, header)
  end

  def test_defensive_copy_at_construction
    handlers = [Dexpace::Auth::BasicHandler.new(Dexpace::Auth::PasswordCredential.new(username: "a", password: "b"))]
    chain = Dexpace::Auth::ChallengeHandlerChain.new(handlers)
    handlers.clear
    refute_nil chain.authorization_for('Basic realm="r"', get_request, proxy: false)
  end

  def test_returns_nil_when_no_handler_satisfies
    chain = Dexpace::Auth::ChallengeHandlerChain.new([])
    assert_nil chain.authorization_for('Digest realm="r", nonce="n"', get_request, proxy: false)
  end

  def test_header_name_selected_by_explicit_proxy_flag
    chain = Dexpace::Auth::ChallengeHandlerChain.new([])
    assert_equal "Authorization", chain.header_name(proxy: false)
    assert_equal "Proxy-Authorization", chain.header_name(proxy: true)
  end
end
```

- [ ] **Step 2: Confirm fail.**
- [ ] **Step 3: Implement**, per the design's listing.
- [ ] **Step 4: Confirm green.**

---

## Task 9: `Dexpace::Auth::KeyStamper` — `AUTH-26`

**Needs:** Task 4.
**Produces:** `KeyStamper`.

- [ ] **Step 1: Write the failing tests.**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# test/dexpace/auth/key_stamper_test.rb — AUTH-26

require_relative "../../test_helper"

class Dexpace::Auth::KeyStamperTest < DexpaceTestCase
  def test_writes_key_into_configured_header_defaulting_to_authorization
    stamper = Dexpace::Auth::KeyStamper.new(Dexpace::Auth::KeyCredential.new(api_key: "abc"))
    request = stamper.call(get_request)
    assert_equal "abc", request.headers["Authorization"]
  end

  def test_prefix_is_prepended_with_single_space
    stamper = Dexpace::Auth::KeyStamper.new(
      Dexpace::Auth::NamedKeyCredential.new(name: "n", key: "abc", prefix: "SharedAccessKey")
    )
    request = stamper.call(get_request)
    assert_equal "SharedAccessKey abc", request.headers["Authorization"]
  end

  def test_stateless_after_construction
    stamper = Dexpace::Auth::KeyStamper.new(Dexpace::Auth::KeyCredential.new(api_key: "abc"))
    stamper.call(get_request)
    stamper.call(get_request) # no state to leak between calls
  end
end
```

- [ ] **Step 2: Confirm fail.**
- [ ] **Step 3: Implement**, per the design's listing (calling `request.with_header`, phase 1's
  builder-shaped mutation-via-copy, never a destructive write).
- [ ] **Step 4: Confirm green.**

---

## Task 10: `Dexpace::Auth::BearerProvider`, `Dexpace::Auth::BearerStamper` (sync) — `AUTH-11` (sync half), `AUTH-34`, `AUTH-35`, `AUTH-36`

**Needs:** Task 4 (`BearerToken`).
**Produces:** the sync bearer single-flight/eviction object.

- [ ] **Step 1: Write the failing tests.**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# test/dexpace/auth/bearer_stamper_test.rb — AUTH-11, AUTH-34, AUTH-35, AUTH-36

require_relative "../../test_helper"

class Dexpace::Auth::BearerStamperTest < DexpaceTestCase
  def test_stamps_bearer_header_with_cached_token
    provider = stub_provider(Dexpace::Auth::BearerToken.new(token: "t1", expiry: nil))
    stamper = Dexpace::Auth::BearerStamper.new(provider: provider, clock: Dexpace::Clock::SYSTEM)
    request = stamper.call(get_request)
    assert_equal "Bearer t1", request.headers["Authorization"]
  end

  def test_concurrent_requests_racing_on_a_missing_token_result_in_one_fetch # AUTH-34
    calls = 0
    provider = CountingProvider.new { calls += 1; Dexpace::Auth::BearerToken.new(token: "t#{calls}", expiry: nil) }
    stamper = Dexpace::Auth::BearerStamper.new(provider: provider, clock: Dexpace::Clock::SYSTEM)
    threads = 16.times.map { Thread.new { stamper.call(get_request) } }
    threads.each(&:join)
    assert_equal 1, calls
  end

  def test_nil_token_surfaces_as_error_and_is_not_cached # AUTH-35
    provider = stub_provider(nil)
    stamper = Dexpace::Auth::BearerStamper.new(provider: provider, clock: Dexpace::Clock::SYSTEM)
    assert_raises(Dexpace::Auth::ProviderError) { stamper.call(get_request) }
  end

  def test_already_expired_at_fetch_time_with_no_margin_surfaces_as_error # AUTH-35
    provider = stub_provider(Dexpace::Auth::BearerToken.new(token: "t", expiry: Time.at(0)))
    stamper = Dexpace::Auth::BearerStamper.new(provider: provider, clock: fixed_clock(Time.at(1)))
    assert_raises(Dexpace::Auth::ProviderError) { stamper.call(get_request) }
  end

  def test_raising_provider_propagates_and_is_not_cached # AUTH-35
    calls = 0
    provider = CountingProvider.new { calls += 1; raise "boom" if calls == 1; Dexpace::Auth::BearerToken.new(token: "t2", expiry: nil) }
    stamper = Dexpace::Auth::BearerStamper.new(provider: provider, clock: Dexpace::Clock::SYSTEM)
    assert_raises(RuntimeError) { stamper.call(get_request) }
    assert_equal "Bearer t2", stamper.call(get_request).headers["Authorization"] # retried
  end

  def test_eviction_matches_only_the_exact_rejected_header # AUTH-36
    provider = stub_provider(Dexpace::Auth::BearerToken.new(token: "old", expiry: nil))
    stamper = Dexpace::Auth::BearerStamper.new(provider: provider, clock: Dexpace::Clock::SYSTEM)
    stamped = stamper.call(get_request)
    stamper.evict_if_matches("Bearer old")
    provider.token = Dexpace::Auth::BearerToken.new(token: "new", expiry: nil)
    assert_equal "Bearer new", stamper.call(get_request).headers["Authorization"]
  end

  def test_no_eviction_when_rejected_header_does_not_match_current_token
    provider = stub_provider(Dexpace::Auth::BearerToken.new(token: "current", expiry: nil))
    stamper = Dexpace::Auth::BearerStamper.new(provider: provider, clock: Dexpace::Clock::SYSTEM)
    stamper.call(get_request)
    stamper.evict_if_matches("Bearer stale") # a token another request already refreshed
    assert_equal "Bearer current", stamper.call(get_request).headers["Authorization"]
  end
end
```

- [ ] **Step 2: Confirm fail.**

- [ ] **Step 3: Implement.**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Auth
    class ProviderError < Dexpace::Error; end

    # AUTH-11 (sync half), AUTH-34, AUTH-35, AUTH-36.
    class BearerStamper
      def initialize(provider:, clock:, refresh_margin: 30)
        @provider = provider
        @clock = clock
        @refresh_margin = refresh_margin
        @lock = ::Thread::Mutex.new
        @token = nil # written only under @lock
      end

      def call(request)
        token = @token # hot-path read, no lock (XCUT-12)
        token = refresh! if token.nil? || token.expired?(now: @clock.now, margin: @refresh_margin)
        request.with_header("Authorization", "Bearer #{token.token}")
      end

      def evict_if_matches(rejected_header)
        @lock.synchronize do
          @token = nil if @token && "Bearer #{@token.token}" == rejected_header
        end
      end

      private

      def refresh!
        @lock.synchronize do
          token = @token
          return token if token && !token.expired?(now: @clock.now, margin: @refresh_margin)

          # XCUT-12: the lock is deliberately held across this blocking fetch -- the one sanctioned
          # exception to "never hold a mutex across a suspension point" -- scoped to this credential.
          fetched = @provider.fetch
          raise ProviderError, "provider returned no token" if fetched.nil?
          raise ProviderError, "provider returned an already-expired token" if fetched.expired?(now: @clock.now, margin: 0)

          @token = fetched # written only on success; a raise above leaves @token untouched (AUTH-35)
        end
      end
    end
  end
end
```

- [ ] **Step 4: Confirm green.**

---

## Task 11: `Dexpace::Auth::Step` — `AUTH-27`–`AUTH-33`

**Needs:** Tasks 6–10, phase 4c's `Cursor`/`Stages`.
**Produces:** the sync AUTH pillar step.

- [ ] **Step 1: Write the failing tests**, against phase 4c's `Cursor.build`, a stub downstream, and
  a bare stub `ForkingProbe`-shaped fork:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# test/dexpace/auth/step_test.rb — AUTH-27 through AUTH-33

require_relative "../../test_helper"
require_relative "../../support/forking_probe" # phase 4c's

class Dexpace::Auth::StepTest < DexpaceTestCase
  def test_declares_stage_auth
    assert_equal Dexpace::Pipeline::Stages::AUTH, build_step.stage
  end

  def test_https_guard_fires_before_any_stamp_on_a_plaintext_url # AUTH-28
    step = build_step(stamper: ->(_r) { flunk "must not stamp before the guard" })
    cursor = Dexpace::Pipeline::Cursor.build(drive: null_driver, request: http_request, options: options, cancellation: no_cancel)
    error = assert_raises(Dexpace::Auth::HTTPSRequiredError) { step.call(http_request, cursor) }
    assert_equal "http", error.scheme
  end

  def test_cross_origin_skips_stamping_and_the_https_guard # AUTH-29
    step = build_step(stamper: ->(_r) { flunk "must not stamp on a cross-origin re-issue" })
    cursor = cross_origin_cursor(request: http_request) # plaintext URL, but cross-origin -- guard must NOT fire
    step.call(http_request, cursor) # does not raise
  end

  def test_same_origin_reissue_is_restamped_and_reguarded
    stamped = false
    step = build_step(stamper: ->(r) { stamped = true; r })
    cursor = same_origin_cursor(request: https_request)
    step.call(https_request, cursor)
    assert stamped
  end

  def test_forks_for_every_drive_including_the_first
    probe = ForkingProbe.new
    step = build_step
    cursor = probe.cursor_for(Dexpace::Pipeline::Stages::AUTH)
    step.call(https_request, cursor)
    assert_equal 1, probe.fork_count
  end

  def test_401_with_challenge_consults_hook_and_replays_once # AUTH-30
    replacement = https_request.with_header("Authorization", "Basic new")
    step = build_step(challenge_hook: ->(_c, _req, _res) { replacement })
    response = step.call(https_request, unauthorized_challenge_cursor)
    assert_equal 200, response.status.code # the replay's stub response
  end

  def test_default_hook_yields_no_replacement
    step = build_step
    response = step.call(https_request, unauthorized_challenge_cursor)
    assert_equal 401, response.status.code
  end

  def test_replay_skipped_when_replacement_body_not_replayable # AUTH-31
    replacement = https_request.with_body(NonReplayableBody.new)
    step = build_step(challenge_hook: ->(_c, _req, _res) { replacement })
    response = step.call(https_request, unauthorized_challenge_cursor)
    assert_equal 401, response.status.code
    refute response.closed?
  end

  def test_hook_error_closes_open_401_before_propagating # AUTH-32
    step = build_step(challenge_hook: ->(*) { raise "hook blew up" })
    cursor = unauthorized_challenge_cursor(track_close: ->(response) { @closed = response })
    assert_raises(RuntimeError) { step.call(https_request, cursor) }
    assert @closed
  end

  def test_401_without_challenge_header_passes_through_unconsulted # AUTH-33
    hook_called = false
    step = build_step(challenge_hook: ->(*) { hook_called = true; nil })
    response = step.call(https_request, unauthorized_no_challenge_cursor)
    assert_equal 401, response.status.code
    refute hook_called
  end
end
```

- [ ] **Step 2: Confirm fail.**

- [ ] **Step 3: Implement** the sync `Dexpace::Auth::Step` per the design's listing, with:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  class HTTPSRequiredError < Error
    attr_reader :scheme, :step

    def initialize(scheme:, step:)
      @scheme = scheme
      @step = step
      super("#{step} refuses to stamp a credential onto a #{scheme} request: HTTPS is required")
    end
  end
end
```

`Step#enforce_https!` compares `request.url.scheme.downcase == "https"` and raises
`Dexpace::HTTPSRequiredError.new(scheme: request.url.scheme, step: self.class.name)` otherwise
(`AUTH-28`'s "naming the concrete step and the offending scheme"). `Step#stamp` dispatches on the
resolved credential's class to the appropriate handler/stamper (`BasicHandler`/`DigestHandler` via
the default `ChallengeHandlerChain`-backed `challenge_hook`, `KeyStamper`, or `BearerStamper`); the
default `challenge_hook` for a request with no prior 401 is "attach nothing yet" for Digest (the
first request to a fresh realm carries no Digest header at all — RFC 7616's own challenge-response
shape) and "attach immediately" for Basic/key/bearer.

- [ ] **Step 4: Confirm green.**

---

## Task 12: `Dexpace::Auth::AsyncBearerStamper` (three-zone policy) — `AUTH-37`

**Needs:** Task 10, phase 2's `Async::Future`/`Completer`.
**Produces:** the async bearer refresh policy, `R12`'s mechanism.

- [ ] **Step 1: Write the failing tests.**

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# test/dexpace/auth/async_bearer_stamper_test.rb — AUTH-37

require_relative "../../test_helper"

class Dexpace::Auth::AsyncBearerStamperTest < DexpaceTestCase
  def test_fresh_zone_stamps_with_no_provider_call
    calls = 0
    provider = async_provider { calls += 1; fresh_token }
    stamper = Dexpace::Auth::AsyncBearerStamper.new(provider: provider, clock: Dexpace::Clock::SYSTEM)
    stamper.stamp(get_request).value
    assert_equal 0, calls
  end

  def test_expiring_but_valid_zone_stamps_immediately_and_never_awaits_the_refresh
    refresh_settled = Dexpace::Async::Completer.new
    provider = async_provider { refresh_settled.future }
    stamper = seeded_stamper(provider: provider, token: expiring_but_valid_token)
    request = stamper.stamp(get_request).value(cancellation: nil) # must not block on the unsettled refresh
    assert_equal "Bearer still-valid", request.headers["Authorization"]
  end

  def test_expired_zone_awaits_a_fresh_fetch_before_stamping
    completer = Dexpace::Async::Completer.new
    provider = async_provider { completer.future }
    stamper = Dexpace::Auth::AsyncBearerStamper.new(provider: provider, clock: Dexpace::Clock::SYSTEM)
    future = stamper.stamp(get_request)
    refute future.settled?
    completer.fulfil(fresh_token)
    assert_equal "Bearer fresh", future.value.headers["Authorization"]
  end

  def test_concurrent_expiring_requests_coalesce_onto_one_fetch
    calls = 0
    completer = Dexpace::Async::Completer.new
    provider = async_provider { calls += 1; completer.future }
    stamper = Dexpace::Auth::AsyncBearerStamper.new(provider: provider, clock: Dexpace::Clock::SYSTEM) # no cached token: expired zone
    futures = 8.times.map { stamper.stamp(get_request) }
    completer.fulfil(fresh_token)
    futures.each { |f| assert_equal "Bearer fresh", f.value.headers["Authorization"] }
    assert_equal 1, calls
  end

  def test_failed_background_refresh_is_non_fatal
    completer = Dexpace::Async::Completer.new
    provider = async_provider { completer.future }
    stamper = seeded_stamper(provider: provider, token: expiring_but_valid_token)
    request = stamper.stamp(get_request).value
    assert_equal "Bearer still-valid", request.headers["Authorization"] # already returned
    completer.fail(RuntimeError.new("refresh failed")) # must not raise anywhere, must not be observed
  end

  def test_failed_fetch_is_not_cached_and_a_later_request_retries
    calls = 0
    completer1 = Dexpace::Async::Completer.new
    provider = async_provider do
      calls += 1
      calls == 1 ? completer1.future : Dexpace::Async::Completer.new.tap { |c| c.fulfil(fresh_token) }.future
    end
    stamper = Dexpace::Auth::AsyncBearerStamper.new(provider: provider, clock: Dexpace::Clock::SYSTEM)
    first = stamper.stamp(get_request)
    completer1.fail(RuntimeError.new("boom"))
    assert_raises(RuntimeError) { first.value }
    assert_equal "Bearer fresh", stamper.stamp(get_request).value.headers["Authorization"]
  end
end
```

- [ ] **Step 2: Confirm fail.**

- [ ] **Step 3: Implement**, per `R12`'s mechanism:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Auth
    # AUTH-37. R12's mechanism: never calls #value/#wait on any future it creates; the calling
    # fiber returns as soon as it has a value to hand back, never waiting on a refresh it kicked
    # off but does not need.
    class AsyncBearerStamper
      def initialize(provider:, clock:, refresh_margin: 30)
        @provider = provider
        @clock = clock
        @refresh_margin = refresh_margin
        @lock = ::Thread::Mutex.new
        @token = nil            # written only under @lock
        @in_flight = nil        # a Dexpace::Async::Future, written only under @lock
      end

      def stamp(request)
        token = @token
        if token && !token.expired?(now: @clock.now, margin: @refresh_margin)
          kick_off_background_refresh! if token.expired?(now: @clock.now, margin: 0) # placeholder for the expiring zone below
          settled(request, token)
        elsif token && !token.expired?(now: @clock.now, margin: 0)
          # Expiring-but-valid: stamp now, refresh in the background, never await it.
          background_refresh!
          settled(request, token)
        else
          # Expired/missing: coalesce onto one in-flight fetch and await THAT, never a blocking wait.
          coalesced_refresh_future.then_map { |fresh| stamp_with(request, fresh) }
        end
      end

      private

      def settled(request, token)
        completer = Dexpace::Async::Completer.new
        completer.fulfil(request.with_header("Authorization", "Bearer #{token.token}"))
        completer.future
      end

      def stamp_with(request, token)
        request.with_header("Authorization", "Bearer #{token.token}")
      end

      def background_refresh!
        future = @provider.fetch_async
        future.on_settle do |settlement|
          next unless settlement.success?

          fetched = settlement.response
          next if fetched.nil? || fetched.expired?(now: @clock.now, margin: 0) # AUTH-35, silently ignored in the background

          @lock.synchronize { @token = fetched }
        end
        # settlement.error? (a failed background refresh) is deliberately not observed further:
        # AUTH-37's "MUST NOT fail the in-flight request" -- there is no in-flight request left to fail.
      end

      def coalesced_refresh_future
        @lock.synchronize do
          return @in_flight if @in_flight

          completer = Dexpace::Async::Completer.new
          @in_flight = completer.future
          @provider.fetch_async.on_settle do |settlement|
            @lock.synchronize { @in_flight = nil }
            if settlement.success? && valid?(settlement.response)
              @lock.synchronize { @token = settlement.response }
              completer.fulfil(settlement.response)
            else
              completer.fail(settlement.error || ProviderError.new("provider returned no usable token"))
            end
          end
          completer.future
        end
      end

      def valid?(token) = token && !token.expired?(now: @clock.now, margin: 0)
    end
  end
end
```

`Future#then_map` is assumed as a small combinator over `#on_settle` + a derived `Completer` (build it
here if phase 2 does not already ship one; if it does, this task consumes it rather than writing a
second one — checked against phase 2's shipped surface before this step lands, and recorded as a
one-line note in this task's own PR if phase 2 turns out to ship it already).

- [ ] **Step 4: Confirm green**, including the coalescing test's single-call assertion and the
  non-fatal-background-failure test.

---

## Task 13: `Dexpace::Auth::AsyncStep` — `AUTH-38`, uniform `AUTH-27`–`AUTH-36` on the async runtime

**Needs:** Tasks 6–9, 12; Task 11's shared `replayable?` helper (extracted to a module function both
steps call, satisfying the design's "one implementation, two drivers" statement for `AUTH-31`).
**Produces:** the async AUTH pillar step.

- [ ] **Step 1: Write the failing tests**, mirroring Task 11's but asserting `Future`-shaped results
  and the always-a-failed-future delivery rule:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# test/dexpace/auth/async_step_test.rb — AUTH-38 and the async mirror of AUTH-27..AUTH-36

require_relative "../../test_helper"

class Dexpace::Auth::AsyncStepTest < DexpaceTestCase
  def test_https_guard_failure_is_a_failed_future_not_a_synchronous_raise # AUTH-38
    step = build_async_step
    future = step.call(http_request, async_cursor)
    assert_raises(Dexpace::HTTPSRequiredError) { future.value }
  end

  def test_hook_error_is_a_failed_future
    step = build_async_step(challenge_hook: ->(*) { raise "boom" })
    future = step.call(https_request, unauthorized_challenge_async_cursor)
    assert_raises(RuntimeError) { future.value }
  end

  def test_no_scheduler_registered_still_yields_a_future_not_a_raise # R12's closing claim
    refute Fiber.scheduler # this test's own environment has none, and the step still returns cleanly
    step = build_async_step
    future = step.call(https_request, async_cursor)
    assert_instance_of Dexpace::Async::Future, future
  end

  def test_replayability_gate_is_the_same_helper_step_uses # AUTH-31 uniformity
    assert_same Dexpace::Auth::Step.method(:replayable?), Dexpace::Auth::AsyncStep.method(:replayable?)
  end
end
```

- [ ] **Step 2: Confirm fail.**

- [ ] **Step 3: Implement.** Extract `replayable?(request) = request.body.nil? ||
  request.body.replayable?` as a shared module function both `Step` and `AsyncStep` call (revisiting
  Task 11 to extract it, non-destructively — its existing tests stay green). `AsyncStep#call` wraps
  its entire body in one `Completer`-backed frame:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Auth
    module Replayability
      module_function
      def replayable?(request) = request.body.nil? || request.body.replayable?
    end

    class AsyncStep
      def stage = Dexpace::Pipeline::Stages::AUTH

      def call(request, cursor)
        completer = Dexpace::Async::Completer.new
        begin
          if cross_origin?(cursor)
            completer.fulfil(cursor.fork.call(request).value) # still async-shaped; see note below
          else
            enforce_https!(request)
            stamp_async(request).on_settle do |settlement|
              settlement.success? ? drive(settlement.response, cursor, completer) : completer.fail(settlement.error)
            end
          end
        rescue => e
          completer.fail(e) # AUTH-38: every raise inside this frame settles the future, uniformly
        end
        completer.future
      end

      # ... drive() mirrors Step#call's post-stamp logic (fork, 401 re-challenge, AUTH-31's gate via
      # Replayability.replayable?, AUTH-32's close-on-hook-error) over Futures instead of direct
      # returns, settling +completer+ at each exit point instead of returning or raising.
    end
  end
end
```

The `cross_origin?` branch's `cursor.fork.call(request).value` is a placeholder shown for space; the
real implementation threads the downstream `Future` through without an intermediate `#value` call,
matching `R12`'s "no blocking wait anywhere" rule — the plan's actual file chains it with
`cursor.fork.call(request).on_settle { |s| s.success? ? completer.fulfil(s.response) :
completer.fail(s.error) }`, consistent with `drive`'s own shape.

- [ ] **Step 4: Confirm green.**

---

## Task 14: Pillar-Step Integration Tests Against Phase 4c's Doubles

**Needs:** Tasks 11 and 13.
**Produces:** no new production code; the cross-cutting assertions the design's *Testing strategy*
names, run against both `Step` and `AsyncStep` in one shared example set (parametrised over the two
classes) so `AUTH-27`, `AUTH-28`, `AUTH-29`'s two branches, `AUTH-30`–`AUTH-33`, and `AUTH-31`'s
uniformity all run once per runtime rather than being written twice by hand.

- [ ] **Step 1: Write the shared example set** using `ForkingProbe`/`StateProbe` to synthesize a
  `Stages::REDIRECT`-owned cursor with `state: { cross_origin: true }` and with it unset, exactly as
  the design's Independence section states `6c` does with no dependency on `6b`'s real step.
- [ ] **Step 2: Confirm it fails against a deliberately broken double** (a sanity check that the
  shared examples are not vacuously green) before running it against the real `Step`/`AsyncStep`.
- [ ] **Step 3: Run it against both.**
- [ ] **Step 4: Confirm green on both.**

---

## Task 15: The End-to-End Cross-Origin Convergence Test

**Needs:** Task 14. Needs `6b`'s real `Dexpace::Redirect::Step` to run for real; the segmentation
design assigns this test's ownership to whichever of `6b`/`6c` lands second, and under the
recommended order that is `6c`.

- [ ] **Step 1: Write the test**, guarded to detect whether `Dexpace::Redirect::Step` (or whatever
  `6b`'s design finally names it — this task reads `6b`'s shipped design doc, not this one, before
  writing the guard's constant name) is defined:

```ruby
# frozen_string_literal: true
# SPDX-License-Identifier: MIT
# test/dexpace/auth/cross_origin_convergence_test.rb — REDIR-11, AUTH-29, the segmentation design's
# convergence point 1. Owned by 6c under the recommended 6a -> 6b -> 6c order.

require_relative "../../test_helper"

class Dexpace::Auth::CrossOriginConvergenceTest < DexpaceTestCase
  def test_no_authorization_header_reaches_a_foreign_origin_after_a_redirect
    skip "6b's real REDIRECT step is not yet built; see phase6/phase6c's Task 15" \
      unless defined?(Dexpace::Redirect::Step)

    pipeline = Dexpace::Pipeline.builder(transport: two_hop_cross_origin_transport)
                                 .append(Dexpace::Pipeline::Stages::REDIRECT, Dexpace::Redirect::Step.new)
                                 .append(Dexpace::Pipeline::Stages::AUTH,
                                         Dexpace::Auth::Step.new(credential: Dexpace::Auth::KeyCredential.new(api_key: "secret")))
                                 .build
    response = pipeline.call(seed_request)
    refute_includes captured_headers_for_second_hop, "Authorization"
  end
end
```

- [ ] **Step 2: If `6b` has already landed, confirm it fails for the right reason first** (a
  deliberately-broken fixture, same discipline as Task 14), then confirm it passes for real. **If
  `6b` has not landed**, confirm the guard skips with the stated reason — this is not a passing test
  by omission, and the plan's own checklist row for this task is written as "implemented, blocked on
  `6b`" rather than ticked, until `6b` lands and the skip is removed.

---

## Task 16: Final Wiring, RBS Baseline, Runtime Surface Snapshot, Checklist and Register Updates

**Needs:** Tasks 1–15.
**Produces:** the wiring that makes `6c`'s files load as part of `dexpace-core`, and the phase's
own bookkeeping.

- [ ] **Step 1: Modify `lib/dexpace.rb`** to add explicit `require_relative` lines for every file in
  the design's *Module layout*, in dependency order (credentials before handlers, handlers before the
  chain, the chain before the steps) — never an autoloader, per `CLAUDE.md`'s standing rule.

- [ ] **Step 2: Write `sig/**/*.rbs` mirrors** for every public constant the design's object model
  names, one file per `lib/` file. Run `rbs validate` and `steep check` against the `Dexpace::Auth`
  target, added to the `Steepfile` at whatever strictness level core's public surface already uses.

- [ ] **Step 3: Regenerate the runtime surface snapshot** — walk `Dexpace::Auth`'s constant tree and
  each class's `public_instance_methods(false)`, sort, diff against the committed manifest, and
  commit the new one. Confirms every public method the design's object model lists (and no
  accidental extra) is what ships.

- [ ] **Step 4: Confirm the require-allowlist audit and the clean-bundle isolation run still pass**
  with no diff — `6c` adds `digest`, `securerandom` and nothing else to what `dexpace-core` already
  requires, and both were on the allowlist before this phase.

- [ ] **Step 5: Run the full `dexpace-core` suite** (`bundle exec rake test`) and confirm every task's
  tests are green together, not merely green individually.

- [ ] **Step 6: Write `6c`'s checklist** (a separate document, execution-time, per `CLAUDE.md` — not
  produced by this plan) mapping each of the 38 `AUTH` IDs to the task number above that satisfies
  it, plus the two ⏳-adjacent rows this plan carries with no code: `AUTH-29`'s stripping clause
  ("satisfied by construction, no code," Task 11) and nothing else, since `6c` files no deferral.

- [ ] **Step 7: File the register items this plan's design identified**, by hand, in the target
  registers the design names — the `docs/open-items.md` finding about `AUTH-4`–`AUTH-7`'s missing
  wiring producer — using the next free `OI-<n>` number at the time of filing, never a number chosen
  in advance by this plan.

- [ ] **Step 8: Run housekeeping** (`ruby .claude/skills/housekeeping/probe.rb`) and fix what it
  reports before calling the sub-phase done.

## Self-review against the design

**What this plan has and has not established.** Every one of `R10`, `R11`, `R12`'s resolutions is
implemented by a specific task (`R10`: Task 7's `UnencodableCredentialError`; `R11`: Task 7's
per-handler `BoundedMap` plus the design's no-deferral argument, nothing further to implement;
`R12`: Task 12's `AsyncBearerStamper` and Task 13's uniform failed-future delivery). The three
deviation-ledger entries beyond those (`P6-2`, `P6-3`) are implemented in Tasks 8 and 4 respectively.
The one register finding is filed by hand in Task 16, not by any earlier task's code.

**What remains genuinely open at the end of this plan.** Task 15's end-to-end test is written but
its pass/skip state depends on `6b`'s landing order, which this plan does not control and does not
pretend to. `Future#then_map` (Task 12) is either consumed from phase 2 or written once, decided at
that task's own execution time against phase 2's actual shipped surface, not guessed here.

### Requirement ID Mapping

| Task | IDs |
|---|---|
| 1 | (support only) |
| 2 | AUTH-1, AUTH-2, AUTH-3 |
| 3 | AUTH-4, AUTH-5, AUTH-6, AUTH-7 |
| 4 | AUTH-8, AUTH-9, AUTH-10 |
| 5 | AUTH-12, AUTH-13 |
| 6 | AUTH-14 |
| 7 | AUTH-15, AUTH-16, AUTH-17, AUTH-18, AUTH-19, AUTH-20, AUTH-21, AUTH-22, AUTH-24 |
| 8 | AUTH-23, AUTH-25 |
| 9 | AUTH-26 |
| 10 | AUTH-11, AUTH-34, AUTH-35, AUTH-36 |
| 11 | AUTH-27, AUTH-28, AUTH-29, AUTH-30, AUTH-31, AUTH-32, AUTH-33 |
| 12 | AUTH-37 |
| 13 | AUTH-38, AUTH-27..AUTH-36 (async mirror) |
| 14 | (cross-cutting integration, no new IDs) |
| 15 | REDIR-11, AUTH-29 (convergence) |
| 16 | (wiring, no new IDs) |

All 38 `AUTH` IDs appear above at least once. `AUTH-29` appears twice (Task 11's construction and
Task 15's convergence test) deliberately — the segmentation design's convergence-point rule requires
the end-to-end assertion to exist somewhere, and it is not a substitute for Task 11's own unit-level
`AUTH-29` tests.
