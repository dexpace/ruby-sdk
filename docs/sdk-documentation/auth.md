# Authentication

**As built by phase 6c, in `dexpace-core`, written against source on 2026-09-18.** This page says what
chapter 11 gives an SDK author today: the closed scheme set and the descriptor/resolver model, the four
credential types and what each shows when printed, the RFC 7235 challenge parser, the Basic and Digest
handlers and the chain that composes them, the static key stamper, the bearer stamper on each runtime,
and the AUTH pillar step at `Stages::AUTH` on both runtimes — its HTTPS guard, its cross-origin
suppression, its 401 re-challenge replay and its bearer 401 branch. What each is *required* to do is
`docs/product-spec/11-authentication.md` (`AUTH-1`–`AUTH-38`); how the design maps it to Ruby is
`docs/sdk-design-ruby/06-retry-redirect-and-authentication.md` §6.3, read with §10.15; the
per-requirement proof is `docs/work/mvp/phase6/phase6c/2026-09-09-phase6c-authentication-checklist.md`.
Signatures live in `gems/dexpace-core/sig/dexpace/auth/`, and this page does not restate them. Every
example below was run against the built code on 4.0.6 and 3.2.11 as one script and printed the same on
both. The credentials in the examples are placeholders and the RFCs' own published test vectors; the
only credential-bearing strings any example prints are the header values this layer exists to produce.

**Three things a reader should know before the first example.** The layer depends on phases 0–5 only:
it reads the cross-origin marker off phase 4c's cursor and never a header, calls phase 3b's
`Body#replayable?` directly, and takes its nonce counter from phase 4a's bounded map. Basic is
`["u:p"].pack("m0")` and Digest is `::Digest::MD5` / `::Digest::SHA256` — never `Base64`, never
`OpenSSL::Digest` (the bundled-gem rule in `CLAUDE.md`). And nothing here reads `Dexpace.configuration`:
the one tunable, the Digest nonce store's cap, is a constructor keyword, because the handler is
explicitly constructed and was never ambient.

## The scheme set and the resolver: `Scheme`, `Requirement`, `Descriptor`, `Resolver`

`Scheme` is a frozen `Data` closed at exactly five, `NO_AUTH` a sentinel meaning "this operation may run
anonymously" and never a wire scheme. `.of` is the one lookup — any case, a Symbol, or a copy
canonicalised back to its constant; `.new` and `.[]` are private and `#with` refuses, so the population
cannot grow (`AUTH-1`).

```ruby
A = Dexpace::Auth
A::Scheme::ALL.map(&:name)                       # => ["OAUTH2", "API_KEY", "BASIC", "DIGEST", "NO_AUTH"]
A::Scheme.of("basic").equal?(A::Scheme::BASIC)   # => true
A::Scheme.of("NTLM")                             # raises Dexpace::InvalidArgumentError
A::Scheme::BASIC.with(name: "NTLM")              # raises Dexpace::InvalidArgumentError
A::Scheme.respond_to?(:new)                      # => false
```

A `Requirement` binds one scheme to its own OAuth scopes and params, both taken through `Model.own` —
deep, so a caller mutating a String *inside* the array it handed over cannot reach the stored value
(`AUTH-2`). A `Descriptor` is a non-empty ordered list of them, empty refused at construction
(`AUTH-3`). `Resolver.resolve` is a pure function of its three tiers and the available set: the first
PRESENT tier is the only one consulted and does not fall through when it cannot be satisfied
(`AUTH-4`); within it the first requirement in declared order whose scheme is `NO_AUTH` or in the
available set wins (`AUTH-5`); the two failures are two types (`AUTH-6`), and the module holds no state
(`AUTH-7`).

```ruby
scopes = [+"read"]
requirement = A::Requirement.build(scheme: :oauth2, scopes: scopes, params: { "aud" => "api" })
scopes[0] << ":write"
requirement.scopes                                        # => ["read"]

descriptor = A::Descriptor.build(requirements: [
  A::Requirement.build(scheme: :digest),
  A::Requirement.build(scheme: :basic),
  A::Requirement.build(scheme: :no_auth),
])
descriptor.allows_anonymous?                              # => true
A::Descriptor.build(requirements: [])                     # raises Dexpace::InvalidArgumentError: requirements must be non-empty (AUTH-3)

A::Resolver.resolve(per_call: nil, operation: descriptor, client: nil,
                    available_schemes: [:basic]).scheme.name            # => "BASIC"
A::Resolver.resolve(per_call: nil, operation: nil, client: descriptor,
                    available_schemes: []).scheme.name                  # => "NO_AUTH"

strict = A::Descriptor.build(requirements: [A::Requirement.build(scheme: :digest)])
begin
  A::Resolver.resolve(per_call: strict, operation: descriptor, client: nil, available_schemes: [:basic])
rescue Dexpace::AuthResolutionError => error
  error.required.map(&:name)                              # => ["DIGEST"]
  error.available.map(&:name)                             # => ["BASIC"]
end
A::Resolver.resolve(per_call: nil, operation: nil, client: nil, available_schemes: [])
                                                          # raises Dexpace::InvalidArgumentError
```

Where a per-call or operation-level descriptor is *carried* is a release decision no phase has made
(`docs/first-release.md`, § Blockers before first publish): the resolver ships as a library object, and
the step below takes an already-chosen stamper.

## The credential types: `BearerToken`, `KeyCredential`, `NamedKeyCredential`, `PasswordCredential`

Every credential redacts its secret in `#to_s`, `#inspect` **and `#pretty_print`** — the third matters:
`pp` gives a `Data` its own pretty-printer over the members and never calls `#inspect`, so a credential
that overrides only the two would print its token under `pp` (`AUTH-8`; the corpus note
`docs/knowledge/notes/authentication.md`). The real fields are untouched. Equality is variant-specific:
`BearerToken` compares by value over its real token and expiry, the two key credentials by identity —
two instances with identical fields are not equal. Blank secrets are refused (`AUTH-9`), and a bearer
token's expiry is optional and evaluated with an additive margin, strictly after (`AUTH-10`).

```ruby
token = A::BearerToken.build(token: "eyJhbGciOi...", expiry: Time.utc(2026, 9, 18, 12, 0, 0))
token.to_s               # => "BearerToken(token=[REDACTED], expiry=2026-09-18 12:00:00 UTC)"
token.inspect            # => "#<Dexpace::Auth::BearerToken token=[REDACTED] expiry=2026-09-18 12:00:00 UTC>"
pp token                 # prints the same line as #inspect, not the members
token.expired?(now: Time.utc(2026, 9, 18, 11, 59, 31), margin: 30)   # => true   (11:59:31 + 30 s > 12:00:00)
token.expired?(now: Time.utc(2026, 9, 18, 11, 59, 30), margin: 30)   # => false  (exactly 12:00:00 is not after)
A::BearerToken.build(token: "x").expired?(now: Time.utc(2100), margin: 10**9)   # => false: a nil expiry never expires
token == A::BearerToken.build(token: "eyJhbGciOi...", expiry: Time.utc(2026, 9, 18, 12, 0, 0))   # => true
A::BearerToken.build(token: "  ")   # raises Dexpace::InvalidArgumentError: token must not be blank

key = A::KeyCredential.new(api_key: "sk_live_1234", header_name: "X-Api-Key")
key.inspect              # => "#<Dexpace::Auth::KeyCredential api_key=[REDACTED] header_name=\"X-Api-Key\" prefix=nil>"
key == A::KeyCredential.new(api_key: "sk_live_1234", header_name: "X-Api-Key")   # => false: reference identity

named = A::NamedKeyCredential.new(name: "RootManageSharedAccessKey", key: "a1b2c3", prefix: "SharedAccessKey")
named.to_s               # => "NamedKeyCredential(name=\"RootManageSharedAccessKey\", key=[REDACTED], header_name=\"Authorization\", prefix=\"SharedAccessKey\")"

password = A::PasswordCredential.build(username: "alice", password: "s3cr3t")
password.inspect         # => "#<Dexpace::Auth::PasswordCredential username=[REDACTED] password=[REDACTED]>"
password.username        # => "alice"
```

`PasswordCredential` performs no blank check of its own — `AUTH-9` names three types and this is not
one of them, and `AUTH-14`'s laxer non-*empty* rule for Basic lives at the handler (design P6-3). Its
username is redacted beside the password: it is half of what Basic puts on the wire.

## The challenge parser: `Challenges.parse`, `Challenge`

A hand-written `StringScanner` state machine — never a regexp over the grammar, because a quoted-string
may hold the list's own delimiters and a hostile `WWW-Authenticate` must not drive a backtracking engine.
Scheme and parameter names are folded once, at `Challenge.build`, so a challenge built by hand meets a
handler in the same shape a parsed one does; values are kept verbatim; a token68 sits under
`Challenge::TOKEN68` with its padding (`AUTH-12`). It never raises: malformed input recovers to the next
top-level comma, keeping the parameters parsed before the tail, and a value whose bytes are invalid
under its own tag is scanned as bytes (`AUTH-13`). A repeated header is one list: the step joins the
values with `", "` before they reach here.

```ruby
challenges = A::Challenges.parse('Digest realm="api", qop="auth,auth-int", nonce="n1", Basic realm="api"')
challenges.map(&:scheme)                                  # => ["digest", "basic"]
challenges[0].params                                      # => {"realm" => "api", "qop" => "auth,auth-int", "nonce" => "n1"}
A::Challenges.parse("Bearer dGhlIHNlY3JldCB0b2tlbg==").first.token68      # => "dGhlIHNlY3JldCB0b2tlbg=="
A::Challenges.parse('Digest realm=@@, nonce="n", Basic realm="ok"').map(&:scheme)   # => ["digest", "basic"]
A::Challenges.parse(nil)                                  # => []
A::Challenge.build(scheme: "BASIC", params: { "REALM" => "x" }).params   # => {"realm" => "x"}
```

On the 3.2 floor a `Hash#inspect` spells `{"realm"=>"api"}` where 4.0.6 spells `{"realm" => "api"}`;
the values are the same.

## Basic: `BasicHandler`

One class, two roles, one precomputed value: `#call` stamps preemptively — the path OpenAPI's
`http`/`basic` scheme takes, sending the credential on the first request — and `#authorization_for`
answers a `basic` challenge, case-insensitively. The value is `"Basic "` plus `pack("m0")` over the
UTF-8 bytes of `username:password`, computed once; both fields must be non-empty, and a
whitespace-only password is legal (`AUTH-14`). A field UTF-8 cannot carry — a BINARY-tagged one with a
high byte, or a UTF-8-tagged one with an invalid sequence — is refused at construction as an
`InvalidArgumentError` naming the field and the two encodings, with no cause and no byte of the value
in any rendering (`AUTH-8`, design P6-85). The header is *set*, so a re-stamp replaces.

```ruby
request = Dexpace::Request.build(method: "GET", url: "https://api.example.test/v1/pets",
                                 headers: Dexpace::Headers::EMPTY)
basic = A::BasicHandler.new(password)
basic.call(request).headers["Authorization"]              # => ["Basic YWxpY2U6czNjcjN0"]
basic.authorization_for(A::Challenges.parse("BASIC realm=x"), request, proxy: false)
                                                          # => "Basic YWxpY2U6czNjcjN0"
basic.authorization_for(A::Challenges.parse('Digest realm="x", nonce="n"'), request, proxy: false)
                                                          # => nil
begin
  A::BasicHandler.new(A::PasswordCredential.build(username: "alice", password: "p\xE4".b))
rescue Dexpace::InvalidArgumentError => error
  error.message.start_with?("the password cannot be encoded as UTF-8 from ASCII-8BIT")   # => true
  error.cause                                             # => nil
end
```

## Digest: `DigestHandler`

Challenge-driven by construction — there is no preemptive `#call`, because a response needs the
server's nonce — and reached from the step through the chain's hook below. It supports exactly `MD5`,
`MD5-sess`, `SHA-256` and `SHA-256-sess` with `qop=auth` or the legacy no-qop form, declines an
auth-int-only challenge (token-exact: `"auth-int".include?("auth")` is true, which is the trap) and any
other algorithm, and never verifies `rspauth` (`AUTH-15`, `AUTH-16`, `AUTH-17`). The nonce count is per
server nonce, one read-modify-write under the handler's own bounded map, wrapping to 32 bits
(`AUTH-18`, `AUTH-19`, `AUTH-24`); the cnonce is sixteen `SecureRandom` bytes (`AUTH-20`); hash inputs
are UTF-8 under `charset=UTF-8` and ISO-8859-1 otherwise, and either branch **raises** a typed
failure naming its own encoding on a credential it cannot represent — Latin-1 for a character it has
no code for, UTF-8 for a BINARY-tagged or invalidly tagged value — never a silently wrong response
(`AUTH-21`, design P6-1, P6-84). The failure names the field, the target encoding and the value's own
encoding, and carries **no `#cause`**: Ruby's conversion error names the offending character of the
secret, and `#full_message` renders a cause, so the character would have been the one thing a
diagnostic could leak (`AUTH-8`, design P6-85). A refused attempt consumes no nonce count. The example
is RFC 2617 §3.5's own vector, with a fixed cnonce so it reproduces.

```ruby
class FixedCnonce
  def initialize(value) = @value = value
  def hex(_bytes) = @value
end
mufasa = A::PasswordCredential.build(username: "Mufasa", password: "Circle Of Life")
digest = A::DigestHandler.new(mufasa, cnonce_source: FixedCnonce.new("0a4f113b"))
rfc = A::Challenges.parse('Digest realm="testrealm@host.com", qop="auth,auth-int", ' \
                          'nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", opaque="5ccc069c403ebaf9f0171e9517f40e41"')
index = Dexpace::Request.build(method: "GET", url: "https://host/dir/index.html", headers: Dexpace::Headers::EMPTY)
digest.authorization_for(rfc, index, proxy: false)
# => "Digest username=\"Mufasa\", realm=\"testrealm@host.com\", uri=\"/dir/index.html\", algorithm=MD5,
#     nonce=\"dcd98b7102dd2f0e8b11d0f600bfb0c093\", nc=00000001, cnonce=\"0a4f113b\", qop=auth,
#     response=\"6629fae49393a05397450978507c4ef1\", opaque=\"5ccc069c403ebaf9f0171e9517f40e41\""
A::Challenges.parse(digest.authorization_for(rfc, index, proxy: false)).first.params["nc"]   # => "00000002"
digest.authorization_for(A::Challenges.parse('Digest realm="r", qop="auth-int", nonce="n"'), index, proxy: false)
                                                          # => nil: auth-int only
digest.authorization_for(A::Challenges.parse('Digest realm="r", nonce="n", algorithm=SHA-512-256'), index, proxy: false)
                                                          # => nil: unsupported algorithm

japanese = A::DigestHandler.new(A::PasswordCredential.build(username: "u", password: "日本語"))
begin
  japanese.authorization_for(A::Challenges.parse('Digest realm="r", nonce="n"'), index, proxy: false)
rescue A::UnencodableCredentialError => error
  [error.field, error.encoding, error.source_encoding]    # => [:password, "ISO-8859-1", "UTF-8"]
  error.message.include?("日本語")                          # => false: the message names the field, never the value
  error.cause                                             # => nil: the conversion error named U+65E5, a character of it
  error.full_message(highlight: false).include?("U+65E5") # => false
end
japanese.authorization_for(A::Challenges.parse('Digest realm="r", nonce="n", charset=UTF-8'), index, proxy: false).nil?
                                                          # => false: UTF-8 advertised, hashed as UTF-8
binary = A::DigestHandler.new(A::PasswordCredential.build(username: "u", password: "p\xE4".b))
begin
  binary.authorization_for(A::Challenges.parse('Digest realm="r", nonce="n", charset=UTF-8'), index, proxy: false)
rescue A::UnencodableCredentialError => error
  [error.field, error.encoding, error.source_encoding]    # => [:password, "UTF-8", "ASCII-8BIT"]: the branch that raised
end

sha = A::DigestHandler.new(mufasa, preference: %w[SHA-256 MD5])
two = A::Challenges.parse('Digest realm="r", nonce="n", algorithm=MD5, Digest realm="r", nonce="n", algorithm=SHA-256')
A::Challenges.parse(sha.authorization_for(two, index, proxy: false)).first.params["algorithm"]   # => "SHA-256"
```

The response line is quoted per `AUTH-22`: username, realm, nonce, uri, response, cnonce and opaque
quoted with backslash escaping; `qop`, `nc` and `algorithm` bare; the three qop fields only when qop was
negotiated. Two wire forms are the port's own decisions, recorded as design row P6-76: a non-ASCII
username goes out as RFC 7616 §3.4's `username*=UTF-8''…`, because the outbound header grammar refuses
the quoted form, and a challenge whose realm, nonce or opaque cannot be echoed under that grammar is
declined rather than raised from the header write.

## Composing handlers and the hook: `ChallengeHandlerChain`

The chain parses the header value once and asks each handler in declaration order through the
one-method protocol `#authorization_for(challenges, request, proxy:) -> String | nil`, returning the
first non-nil value — so order stronger schemes first (`AUTH-23`). The header *name* comes from the
explicit `proxy:` flag alone (`AUTH-25`). `#as_challenge_hook` is the adapter that turns a handler's
value into the replacement request the step's hook contract wants, and it is never installed by
default.

```ruby
chain = A::ChallengeHandlerChain.new([digest, basic])
chain.authorization_for('Basic realm="api"', index, proxy: false)   # => "Basic YWxpY2U6czNjcjN0"
chain.header_name(proxy: true)                                       # => "Proxy-Authorization"
hook = chain.as_challenge_hook
hook.call('Basic realm="api"', index, nil).headers["Authorization"]   # => ["Basic YWxpY2U6czNjcjN0"]
hook.call("NTLM", index, nil)                                        # => nil: no handler can satisfy it
```

## Static keys: `KeyStamper`

Constructed against either key credential, it computes the header value once — the prefix, one space,
the key — checks it against the outbound grammar, and sets it on every call with no state of its own
(`AUTH-26`).

```ruby
A::KeyStamper.new(named).call(request).headers["Authorization"]   # => ["SharedAccessKey a1b2c3"]
A::KeyStamper.new(key).call(request).headers["X-Api-Key"]         # => ["sk_live_1234"]
```

An `apiKey` carried in a query parameter or a cookie has no path through this layer — `AUTH-26` is
header-only, and what a consumer loses by placing one there is in `docs/first-release.md`, § What v1
ships without.

## Bearer tokens: `BearerStamper`, `AsyncBearerStamper`, `BearerProvider`

A provider is a duck type: `#fetch -> BearerToken`, and optionally `#fetch_async -> Future`. The sync
stamper caches one token per credential until a refresh margin before its expiry (30 s by default),
reads it on the hot path with no lock, and refreshes under the per-credential mutex — held across the
provider's fetch, the one sanctioned lock across a suspension point in this SDK (`XCUT-12`) — so
concurrent requests racing on a missing token cost one fetch (`AUTH-34`). A nil token, a token already
expired at fetch time, or a raising provider surfaces and caches nothing (`AUTH-35`). Eviction is a
compare-and-clear on the stamped header value (`AUTH-36`'s cache half).

```ruby
class StaticProvider
  def initialize(*tokens) = (@tokens = tokens; @fetches = 0)
  attr_reader :fetches
  def fetch
    @fetches += 1
    @tokens.size > 1 ? @tokens.shift : @tokens.first
  end
end
clock = Struct.new(:now) do
  def monotonic = 0.0
  def sleep(*) = nil
end
at = clock.new(Time.utc(2026, 9, 18, 12, 0, 0))
provider = StaticProvider.new(A::BearerToken.build(token: "t1", expiry: Time.utc(2026, 9, 18, 12, 1, 0)),
                              A::BearerToken.build(token: "t2", expiry: Time.utc(2026, 9, 18, 13, 0, 0)))
bearer = A::BearerStamper.new(provider: provider, clock: at, refresh_margin: 30)
bearer.call(request).headers["Authorization"]      # => ["Bearer t1"]
at.now = Time.utc(2026, 9, 18, 12, 0, 29)
bearer.call(request).headers["Authorization"]      # => ["Bearer t1"]   (12:00:29 + 30 s is not after 12:01:00)
at.now = Time.utc(2026, 9, 18, 12, 0, 31)
bearer.call(request).headers["Authorization"]      # => ["Bearer t2"]   (refreshed at the margin)
provider.fetches                                   # => 2
bearer.evict_if_matches("Bearer stale")            # => false: not the cached token
bearer.evict_if_matches("Bearer t2")               # => true

nil_provider = Object.new.tap { |o| def o.fetch = nil }
A::BearerStamper.new(provider: nil_provider).call(request)   # raises Dexpace::Auth::ProviderError
```

The async stamper implements `AUTH-37`'s three zones without blocking: a fresh token is stamped in an
already-settled future with no provider call; an expiring-but-valid one is stamped at once while a
refresh it never awaits runs; an expired or missing one settles a future of its own from one
coalesced fetch — a second `Completer` fed by the fetch's `#on_settle`, never a `Future#then`
derivation of it, because `#then` would wire each waiter's cancellation back to the fetch every
waiter shares. `BearerProvider.fetch_async` is `AUTH-11`'s default: a
`#fetch`-only provider is mirrored into an already-settled (or already-failed) future, and a
`#fetch_async` override that raises synchronously becomes a failed future — the function never raises.
A failed background refresh is reported through the stamper's `logger:` as one `http.auth.refresh`
warning and fails nothing.

```ruby
async = A::AsyncBearerStamper.new(provider: StaticProvider.new(A::BearerToken.build(token: "t3")), clock: at)
future = async.stamp(request)
future.settled?                                    # => true: a #fetch-only provider settles inline
future.value.headers["Authorization"]              # => ["Bearer t3"]

completer = Dexpace::Async::Completer.new
pending_provider = Object.new
pending_provider.define_singleton_method(:fetch) { raise "not used" }
pending_provider.define_singleton_method(:fetch_async) { completer.future }
waiting = A::AsyncBearerStamper.new(provider: pending_provider, clock: at)
first = waiting.stamp(request)
second = waiting.stamp(request)                    # coalesces onto the same in-flight fetch
first.settled?                                     # => false
completer.fulfil(A::BearerToken.build(token: "t4"))
[first.value.headers["Authorization"], second.value.headers["Authorization"]]   # => [["Bearer t4"], ["Bearer t4"]]

A::BearerProvider.fetch_async(nil_provider).settled?   # => true
A::BearerProvider.fetch_async(nil_provider).value      # raises Dexpace::Auth::ProviderError
```

The fetch is shared; a cancellation is not. Cancelling one coalesced request's future detaches
that request alone: the fetch runs on, the other waiters and every later arrival stamp the token
when it lands, and the cancelled future carries its own reason (`SEAM-18`). Only the provider's
own settlement settles the shared fetch, and a provider that cancels its fetch cancels every
waiter as a cancellation, never as a plain failure.

```ruby
completer = Dexpace::Async::Completer.new
pending_provider.define_singleton_method(:fetch_async) { completer.future }
shared = A::AsyncBearerStamper.new(provider: pending_provider, clock: at)
first = shared.stamp(request)
second = shared.stamp(request)
first.cancel(:caller_gave_up)
[first.cancelled?, second.settled?, completer.future.settled?]   # => [true, false, false]
third = shared.stamp(request)                      # still coalesces onto the live fetch
completer.fulfil(A::BearerToken.build(token: "t5"))
[second.value.headers["Authorization"], third.value.headers["Authorization"]]   # => [["Bearer t5"], ["Bearer t5"]]
first.value                                        # raises Dexpace::CancelledError
```

## The AUTH pillar step: `Step`, `AsyncStep`

Built through `.build(stamper:, challenge_hook: NO_REPLACEMENT, logger: Logger::NULL)`, frozen, and
installed with `builder.append(step)` and no `stage:` because it declares `Stages::AUTH` (`AUTH-27`). The
stamper is anything answering `#call(request) -> Request` — a `KeyStamper`, a `BasicHandler`, a
`BearerStamper`, or `Step::NO_STAMP` for the `NO_AUTH` sentinel; the async step also takes an
`AsyncBearerStamper`. `#call`'s order is the contract: the cross-origin check first (`AUTH-29`: on a
cross-origin redirect re-issue, read from the redirect step's own cursor slot and never a header, the
step stamps nothing and skips the guard), then the HTTPS guard before any fetch or write (`AUTH-28`),
then the stamper, then one fresh fork for the drive, then the 401 handling: the bearer branch
(`AUTH-36`) before the challenge hook (`AUTH-30`), each gated on the replacement body's replayability
(`AUTH-31`), the 401 closed before a replay and closed when the hook fails (`AUTH-32`), and returned
unchanged without consulting the hook when it carries no `WWW-Authenticate` (`AUTH-33`). The step forks
for every drive, the first included, and never calls the cursor it was handed (P4-39).

```ruby
class ScriptedTransport
  attr_reader :requests
  def initialize(*responses) = (@responses = responses; @requests = [])
  def call(request, _options, _cancellation)
    @requests << request
    @responses.shift
  end
end
def response_for(request, status, challenge = nil)
  builder = Dexpace::Response.builder
  builder.request = request
  builder.protocol = Dexpace::Protocol::HTTP_1_1
  builder.status = status
  builder.headers = challenge ? Dexpace::Headers.inbound_builder.add("WWW-Authenticate", challenge).build
                              : Dexpace::Headers::EMPTY_INBOUND
  builder.build
end

transport = ScriptedTransport.new(response_for(request, 200))
step = A::Step.build(stamper: A::KeyStamper.new(key))
step.stage.equal?(Dexpace::Pipeline::Stages::AUTH)         # => true
pipeline = Dexpace::Pipeline.builder(transport: transport).append(step).build
pipeline.call(request).status.code                         # => 200
transport.requests.first.headers["X-Api-Key"]              # => ["sk_live_1234"]

plaintext = Dexpace::Request.build(method: "GET", url: "http://api.example.test/v1/pets", headers: Dexpace::Headers::EMPTY)
begin
  pipeline.call(plaintext)
rescue A::HTTPSRequiredError => error
  [error.scheme, error.step]   # => ["http", "Dexpace::Auth::Step"]
  error.message                # => "Dexpace::Auth::Step refuses to attach a credential to a \"http\" request: credentials are stamped over HTTPS only (AUTH-28)"
end

# A 401 re-challenge answered by Digest: the chain's hook is how Digest reaches the step.
challenge = 'Digest realm="testrealm@host.com", qop="auth", nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093"'
transport = ScriptedTransport.new(response_for(index, 401, challenge), response_for(index, 200))
digest_step = A::Step.build(stamper: A::Step::NO_STAMP, challenge_hook: chain.as_challenge_hook)
Dexpace::Pipeline.builder(transport: transport).append(digest_step).build.call(index).status.code   # => 200
transport.requests.map { |r| r.headers["Authorization"]&.first&.slice(0, 15) }   # => [nil, "Digest username"]

# The default hook yields no replacement: the 401 surfaces after one drive, unclosed.
transport = ScriptedTransport.new(response_for(index, 401, challenge))
Dexpace::Pipeline.builder(transport: transport).append(A::Step.build(stamper: A::Step::NO_STAMP)).build
                 .call(index).status.code                  # => 401
```

The async step runs the same body inside one `Completer` frame, so the guard's failure, a raising
stamper, a failing provider and every hook failure settle the one returned future rather than raising
(`AUTH-38`), with no `Fiber.scheduler` required because nothing in it waits. Its hook may also answer a
`Dexpace::Async::Future` of the replacement (design P6-78), and whatever that future settles with meets
the same check and the same close as a direct answer: a failed future, or one fulfilling with anything
but a request or nil, closes the open 401 before the step's future fails (`AUTH-32`).

```ruby
class ScriptedAsyncTransport < ScriptedTransport
  def call(request, options, cancellation)
    completer = Dexpace::Async::Completer.new
    completer.fulfil(super)
    completer.future
  end
end
transport = ScriptedAsyncTransport.new(response_for(request, 200))
async_step = A::AsyncStep.build(stamper: async)
future = Dexpace::Pipeline::Builder.new(transport: transport).append(async_step).build_async.call(request)
future.value.status.code                                   # => 200
transport.requests.first.headers["Authorization"]          # => ["Bearer t3"]

guard = Dexpace::Pipeline::Builder.new(transport: ScriptedAsyncTransport.new).append(async_step).build_async.call(plaintext)
guard.settled?                                             # => true
guard.value                                                # raises Dexpace::Auth::HTTPSRequiredError
```

And the cross-origin suppression, with a probe standing in for the redirect step that phase 6b builds:
a step at `Stages::REDIRECT` forks its drive with `state: { cross_origin: true }`, the AUTH step reads
that slot, and a plaintext foreign hop goes out credential-free instead of failing (`AUTH-29`,
`REDIR-11`'s reader half). Nothing on the request carried the marker, so nothing had to be stripped.

```ruby
class CrossOriginProbe
  def call(request, cursor) = cursor.fork(state: { cross_origin: true }).call(request)
end
transport = ScriptedTransport.new(response_for(plaintext, 200))
Dexpace::Pipeline.builder(transport: transport)
                 .append(CrossOriginProbe.new, stage: Dexpace::Pipeline::Stages::REDIRECT)
                 .append(A::Step.build(stamper: A::KeyStamper.new(key)))
                 .build.call(plaintext)
transport.requests.first.headers["X-Api-Key"]              # => nil
transport.requests.first.url.scheme                        # => "http"
```

## What is deliberately not here

- **The real redirect step, and the end-to-end cross-origin test.** Phase 6b builds `Dexpace::Redirect::Step`;
  the convergence test that puts it in front of this step is written and guarded in
  `gems/dexpace-core/test/dexpace/auth/cross_origin_convergence_test.rb`, and 6b un-guards it.
- **A carrier for per-call and operation-level descriptors**, and **query- or cookie-carried API keys.**
  Both are release decisions recorded in `docs/first-release.md`; the resolver and the header-only
  stamper are complete as specified.
- **Wire-boundary re-validation of the stamped header values.** Phase 8's transport adapters re-check
  `HTTP-17`/`HTTP-18` immediately before dispatch; this layer checks a key at construction and a Digest
  challenge's echoed values at selection, and builds no second pass.
- **A `Cursor` context bundle.** The widening phase 6a owns did not exist on this phase's base; the
  steps take their own `logger:` and read no bundle.
- **Mutual authentication (`rspauth`)**, `auth-int`, `SHA-512-256`, and any scheme beyond the five —
  each declined by requirement, not omitted.
