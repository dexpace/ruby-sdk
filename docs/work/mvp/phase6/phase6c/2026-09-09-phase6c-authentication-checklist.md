# Phase 6c — Authentication: Checklist

**Written at execution time, 2026-09-18, from what was built** — not from the plan. A row whose task
did not do what the plan said is a row that says so, and the "Deviations from the plan" section
below is where each departure is stated with its reason. The design and the plan were written on
2026-09-09 (reviewed 2026-09-13) against phases 0–3's *plans* and phases 4 and 5's *designs*, on a
machine that then had only Ruby 3.4.10, concurrently with 6a's and 6b's documents. Since then phases
4a, 4b, 4c, 5a, 5b and 5c were built, reviewed and merged to `main` (PRs #53–#62, #63–#71) and every
interpreter in the matrix was installed. **This phase was cut from `main` at `f1fe848`**, which holds
all of phase 5; phase 6a is being built at the same time in another worktree, also off `main`, and
phase 6b starts after both have returned. Nothing of 6a's exists on this base — no
`Dexpace::Resilience`, no `Cursor#bundle`, no `RetryStep` — so the `Cursor` context-bundle widening the
charter assigns to 6a was **consumed not at all**, and the step ships its own `logger:` keyword (the
design's R8-of-6b reasoning). Where the plan's text and the built tree disagree the tree wins and this
document records it.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase6/phase6c/2026-09-09-phase6c-authentication.md`. Task numbers are that
plan's. Design: `docs/work/mvp/phase6/phase6c/2026-09-09-phase6c-authentication-design.md`, whose
Deviation Ledger rows P6-1–P6-7 (6c's numbering, which knowingly collides with 6a's P6-1–P6-12 — the
roadmap's 2026-09-10 catch-up entry records the collision and phase 10's consolidation resolves it;
outside the design every citation reads "6c's P6-n") and as-built rows P6-71–P6-85 are cited below;
the charter is `docs/work/mvp/phase6/2026-09-09-phase6-segmentation-design.md`. Every test file named
here is under `gems/dexpace-core/test/`, mirrors its `lib/` file one for one (five carry no `lib/`
mirror and say so below; one `private_constant` carries no `test/` mirror and is asserted at its call
sites), and opens with the IDs it exercises.

## Requirement rows

Thirty-eight own rows — `AUTH-1`–`AUTH-38` — plus one row for the Task 15 convergence test and
twelve cross-reference rows for the non-`AUTH` IDs this phase owns a share of, taken from the design's
interface-surface table and the charter's spec-forced boundaries the way 4b, 4c, 5a, 5b and 5c carried
theirs. **Thirty-eight ✅** — `AUTH-29` ✅ with its three clauses stated in the row — nothing ⏳,
nothing 🚫, nothing N/A; the Task 15 row is *written, guarded; owned by 6b* and is not ticked.

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `AUTH-1` | MUST | ✅ | 2 | `Dexpace::Auth::Scheme`, a frozen `Data` closed at exactly `OAUTH2`, `API_KEY`, `BASIC`, `DIGEST`, `NO_AUTH` in `Pipeline::Stage`'s shape (P4-32, P4-56): `.new` **and `.[]`** private, no `.build`, `#with` refusing, `.of` the one lookup (any case, a Symbol, or a copy canonicalised back to its constant), `ALL` public because the requirement is stated as a set. `NO_AUTH` is a distinct sentinel; its stamper is `Step::NO_STAMP` (`scheme_test.rb`, 8 tests) |
| `AUTH-2` | MUST | ✅ | 2 | `Requirement`, `Data.define(:scheme, :scopes, :params)` with `.build(scheme:, scopes: [], params: {})`, the scheme resolved through `Scheme.of` as `Request` resolves its method; both collections taken through `Model.own` — deep, so a caller mutating a String INSIDE the retained array cannot reach the stored value (the fixture is `+"read"`; a frozen literal raises at the caller's `<<` first) — the same frozen reference from every accessor, value equality over the three members (`requirement_test.rb`) |
| `AUTH-3` | MUST | ✅ | 2 | `Descriptor`, `.build(requirements:)` **keyword-shaped** so `Model#with` routes through it (the plan's positional `.build(requirements)` breaks `#with`), an empty list and a non-`Requirement` element refused, `Model.own` on the list (identity of the frozen elements kept), `#allows_anonymous?` iff any scheme `== NO_AUTH` (`descriptor_test.rb`) |
| `AUTH-4` | MUST | ✅ | 3 | `Resolver.resolve(per_call:, operation:, client:, available_schemes:)`: the first PRESENT tier is the only one consulted — `per_call \|\| operation \|\| client` — and a present, unsatisfiable higher tier raises rather than falling through, asserted with a client tier that would have satisfied it (`resolver_test.rb`) |
| `AUTH-5` | MUST | ✅ | 3 | Declared order; `NO_AUTH` always satisfiable with an empty available set; membership of the available set, each element resolved through `Scheme.of` so a String, a Symbol or a copied constant all count; no credential is ever received, so none is inspected (`resolver_test.rb`) |
| `AUTH-6` | MUST | ✅ | 3 | Two distinct types: `Dexpace::InvalidArgumentError` when all three tiers are absent, `Dexpace::AuthResolutionError` (flat, phase 2's error shape, `#required` in preference order and `#available` as frozen copies, a message naming both lists and `(none)` for an empty one) when the selected descriptor lists nothing satisfiable (`resolver_test.rb`, `error/auth_resolution_error_test.rb`) |
| `AUTH-7` | MUST | ✅ | 3 | A module with `extend self` and no instance state — the single shared entry point trivially; twenty threads resolve the same inputs to the same answer; `Resolver.instance_variables` is empty (`resolver_test.rb`) |
| `AUTH-8` | MUST | ✅ | 4 | Every credential type redacts its secret in `#to_s` **and** `#inspect` **and** — the third rendering the requirement's "any string/diagnostic representation" reaches and the design did not name — `#pretty_print`, because `pp` walks a `Data`'s members and never calls `#inspect` (P6-72, verified on 3.2.11, 3.4.10 and 4.0.6); the real fields are untouched and `#to_h` still carries them. `BearerToken`: value equality and hashing over the real token and expiry, two tokens with unequal secrets rendering identically; `KeyCredential` and `NamedKeyCredential`: no `==`/`eql?`/`hash` defined, so two instances with identical fields are NOT equal and hash apart; the key NAME visible (the requirement's own list); `PasswordCredential`: the username redacted as well as the password (P6-73). One marker, `Dexpace::Auth::REDACTED`. **The cause chain is a diagnostic representation too**: the two encoding failures (`AUTH-14`'s and `AUTH-21`'s) are raised `cause: nil`, because Ruby's conversion error names a character or byte of the secret and `#full_message` renders a cause on every supported Ruby — review round 1's R1-3, P6-85 — and `digest_handler_test.rb` asserts that `message`, `detailed_message`, `inspect`, `full_message` and every `each_cause` message carry neither the character nor the password (`bearer_token_test.rb`, `key_credential_test.rb`, `named_key_credential_test.rb`, `password_credential_test.rb`, `digest_handler_test.rb`, `basic_handler_test.rb`; guards 3–13, 74–79) |
| `AUTH-9` | MUST | ✅ | 4 | `Validation.non_blank!(name, value)` — the `private_constant` helper, `(name, value)` in `Model.required!`'s order — refuses `nil` through `Model.required!` (`"<name> is required"`, SEAM-29's form untouched), a non-String, and `""`, `"   "`, `"\t\n"` with `"<name> must not be blank"` (6c's P6-6), applied to `BearerToken.token`, `KeyCredential.api_key`, `NamedKeyCredential.name` and `.key`, and to a supplied prefix; never to `PasswordCredential` (`bearer_token_test.rb`, `key_credential_test.rb`, `named_key_credential_test.rb`; guard 2) |
| `AUTH-10` | MUST | ✅ | 4 | `BearerToken#expired?(now:, margin: 0)`: a nil expiry is never expired whatever the margin; otherwise `(now + margin) > expiry`, STRICTLY — 994+5 against 1000 is not expired, 995+5 is not, 996+5 is; `expiry` must be a `Time` or nil (`bearer_token_test.rb`; guard 52) |
| `AUTH-11` | MUST | ✅ | 10, 12 | `BearerProvider.fetch_async(provider)`, the one function the requirement fixes and the plan never wrote: a `#fetch`-only provider's result is mirrored into an already-settled future and its raise into an already-FAILED one (a nil token becomes a failed `ProviderError` future, never `Completer#fulfil(nil)`); a `#fetch_async` override's synchronous raise, and a non-`Future` return, are normalised into a failed future; the function never raises. `BearerProvider.conforms?` is `respond_to?(:fetch)`. The sync stamper propagates a provider's raise unchanged and caches nothing (`bearer_provider_test.rb`, `bearer_stamper_test.rb`, `async_bearer_stamper_test.rb`; guard 61) |
| `AUTH-12` | MUST | ✅ | 5 | `Challenges.parse` over a `StringScanner` with eight fixed, timeout-compiled character-class patterns and no regexp over the grammar: multiple top-level challenges in wire order, a quoted-string holding commas and `=`, backslash escapes unescaped and quotes stripped, values verbatim, a bare scheme as a challenge with an empty map, a token68 under `Challenge::TOKEN68` (`"token68"`) and recorded WHOLE with its `=` padding. The fold of scheme and parameter names lives in ONE place, `Challenge.build`, so a hand-built challenge meets a handler in a parsed one's shape (`challenges_test.rb`, `challenge_test.rb`; guards 14–16) |
| `AUTH-13` | MUST | ✅ | 5 | Never raises: nil, empty, blank and separator-only input yield `[]`; a malformed value, a parameter before any scheme, a bare token where a parameter was expected and a character no token starts with each recover to the next TOP-LEVEL comma, walking a quoted string on the way so a comma inside one is not the boundary; parameters parsed before the tail stay on the emitted challenge; an unterminated quoted-string runs to end of input; `,,` is an empty list element and the parameter after it continues the challenge (RFC 7230 §7). **A value whose bytes are invalid under its own tag is scanned as bytes** — `StringScanner#scan` and `String#downcase` both raise `ArgumentError` on one, which the plan's fence would have surfaced (P6-74). Ten adversarial inputs, and 100 000 bytes in four shapes in under a second; and every one of the eight scanner patterns pinned as a private, frozen `Regexp` with a per-pattern `#timeout`, the property the measurement discharges but could not pin on its own — `Regexp.new` returns an unfrozen object, so the eight now `.freeze` as 5a's `HTTPDate::GRAMMAR` does (review round 0's R0-2) (`challenges_test.rb` `GrammarTest`, `LeniencyTest`; guards 17–20, 63, 64) |
| `AUTH-14` | MUST | ✅ | 6 | `BasicHandler`: `"Basic " + ["u:p"].pack("m0")` over the UTF-8 bytes — the pair transcoded to UTF-8 first, so a Latin-1-tagged credential encodes the same bytes — computed once at construction, the same frozen String from both roles: `#call` (preemptive, the `http`/`basic` scheme's path, the header SET so a re-stamp replaces) and `#authorization_for` (answered only when a `basic` challenge was offered, the parser's fold making that an equality test). Non-EMPTY, not non-blank: three spaces is a legal password, `""` is refused; a colon in the username is refused per RFC 7617 §2 (P6-75); a username or password UTF-8 cannot carry — BINARY-tagged with a high byte, or UTF-8-tagged with an invalid sequence, which `encode` to the same encoding passes through unvalidated — is refused at construction as an `InvalidArgumentError` naming the field and the two encodings, `cause: nil`, never the bare `Encoding::UndefinedConversionError` round 1's tree let escape naming a byte of the password (review round 1's R1-3, P6-85). Never `Base64`: the source is scanned (`basic_handler_test.rb`; guards 21, 22, 77–79) |
| `AUTH-15` | MUST | ✅ | 7 | `DigestHandler::ALGORITHMS` is exactly `MD5`, `MD5-sess`, `SHA-256`, `SHA-256-sess`; `qop` is split on commas and compared TOKEN-EXACT after a bare fold — `"auth-int".include?("auth")` is true, so a substring test accepts exactly the challenge this requirement declines — an auth-int-only challenge, `SHA-512-256` and any other algorithm decline, and nothing handles `rspauth` (`digest_handler_test.rb` `SelectionTest`; guard 23) |
| `AUTH-16` | MUST | ✅ | 7 | Satisfiable iff `digest` (the fold makes it case-insensitive), `realm` and `nonce` present, `qop` absent or containing the `auth` token, the algorithm absent (MD5) or supported (matched with a bare ASCII fold, `sha-256` accepted); then the PREFERENCE list is walked, not the challenge list, so the same two challenges in either order select the preferred one. Plus the echo condition the port adds: a realm, nonce or opaque the outbound header grammar cannot carry makes the challenge unsatisfiable (P6-76) (`digest_handler_test.rb` `SelectionTest`, `WireTest`) |
| `AUTH-17` | MUST | ✅ | 7 | HA1 = H(username:realm:password), keyed as H(HA1:nonce:cnonce) for `-sess`; HA2 = H(method:uri), the method entering so POST and GET differ; the response H(HA1:nonce:nc:cnonce:qop:HA2) with qop and the legacy H(HA1:nonce:HA2) without; lower-case hex from `::Digest::MD5`/`::Digest::SHA256`. RFC 2617 §3.5's genuine `qop=auth` vector reproduces exactly (`6629fae49393a05397450978507c4ef1` with `nc=00000001`, `cnonce="0a4f113b"`), and three DERIVED expectations — the legacy no-qop form of the same inputs `670fd8c2df070c60b045671b8b24ff02`, RFC 7616 §3.9.1's inputs under SHA-256 `9fbf3e2223549127935ba79d47a0299af1f57eae1240ead830c0b47ad60346e1` and SHA-256-sess `a0316f893cdcbd706441a5392ef9e690688b447acf4015a2b9ce520e6b551a5c` — derived on all four interpreters by `matrix_facts_test.rb` and committed only because they were produced; the RFC's printed SHA-256 response is 63 hex characters and no digest is (`digest_handler_test.rb` `VectorsTest`; guard 24) |
| `AUTH-18` | MUST | ✅ | 7 | `next_count` is one `BoundedMap#update(nonce) { \|n\| (n \|\| 0) + 1 }` per server nonce — `00000001` first, `00000002` on reuse, a second nonce its own `00000001` — rendered `format("%08x", count & 0xFFFFFFFF)`: 8 lower-case hex digits, `0xFFFFFFFF + 1` → `00000000`, `0x1000000FE` → `000000ff`. **A refused attempt consumes no count**: `compute` materialises the credential — the one step that can raise (`AUTH-21`) — before the count is taken, the design's own `authorization_for` order, so after a raise the nonce's slot is unset and the next response on it sends `00000001`, not one higher than the server has seen (review round 0's R0-4, which found the built order reversed) (`digest_handler_test.rb` `CounterTest`; guards 25, 26, 68) |
| `AUTH-19` | SHOULD | ✅ | 7 | The store is the handler's OWN `BoundedMap.new(cap:)`, `cap:` a constructor keyword defaulting to `DEFAULT_CAP = 1024` and read from no configuration chain (R11, 6c's P6-4): constructed in `#initialize`, never shared between two handlers, drained under the cap in `#update`'s own critical section, an evicted nonce restarting at `00000001`. Reached by a BARE name from the full-nesting `module Dexpace; module Auth; class DigestHandler` body: the qualified spelling raises `NameError: private constant Dexpace::BoundedMap referenced` (`digest_handler_test.rb` `CounterTest`, `bounded_map_test.rb`; guards 27, 28) |
| `AUTH-20` | MUST | ✅ | 7 | `cnonce_source: ::SecureRandom` by default, `#hex(16)` — 128 bits, 32 lower-case hex characters, fresh per response — with the source a constructor keyword answering `#hex` so a vector can pin it; the source file is scanned for `::SecureRandom` and against `Random` (`digest_handler_test.rb` `EncodingTest`, `matrix_facts_test.rb`; guard 29) |
| `AUTH-21` | MUST | ✅ | 7 | `materialize(text, field, utf8)`: UTF-8 when the challenge advertises `charset=UTF-8` in any case, ISO-8859-1 otherwise, each of username, realm and password materialised under its own field name; the Latin-1 branch on a representable credential (`café`) hashes Latin-1 bytes (asserted against the UTF-8 hash, which differs), and on an unrepresentable one RAISES `Dexpace::Auth::UnencodableCredentialError` with `#field` (`:password`, `:username`), `#encoding` naming the branch that raised — `"ISO-8859-1"` here — `#source_encoding` naming the value's own tag, **no `#cause`** and no credential in the message — for every one of the four algorithms, since the encoding step is shared (R10, 6c's P6-1). **The UTF-8 branch raises the same failure naming `"UTF-8"`** for a credential that is not text under its own tag: a BINARY-tagged one, whose high bytes have no UTF-8 meaning (`#source_encoding` `"ASCII-8BIT"`), or a UTF-8-tagged one with an invalid sequence, which `encode` to the same encoding passes through unvalidated and would otherwise have been hashed as it was; a Latin-1-tagged credential is transcoded and accepted. **`#cause` is nil on every path** (review round 1's R1-3, P6-85): the rescued conversion error's message is `U+65E5 from UTF-8 to ISO-8859-1` — a character of the password — and `#full_message` renders a cause on every supported Ruby, so round 1's tree, which kept the rescued error as the cause per `R10`, leaked one character through that rendering; the value's own encoding, the part of that message that was not the secret, is carried as `#source_encoding` and in the message ("cannot be encoded as ISO-8859-1 from UTF-8") instead, and both raises spell `cause: nil` so a caller's in-flight `$!` is not assigned either. The message's reason is the target's own — "advertised charset=UTF-8 and the value cannot be transcoded to it" against "did not advertise charset=UTF-8, so RFC 7616's default applies" — so the UTF-8 branch never blames the challenge for a byte the caller supplied; round 0's tree named ISO-8859-1 on both branches (review round 0's R0-3, P6-84) (`digest_handler_test.rb` `EncodingTest`, `unencodable_credential_error_test.rb`; guards 30, 31, 65–67, 74–76) |
| `AUTH-22` | MUST | ✅ | 7 | username, realm, nonce, uri, response, cnonce and opaque quoted with `"` and `\` backslash-escaped (round-tripping through the parser); `qop`, `nc` and `algorithm` bare, the algorithm in its full spelling (`SHA-256-sess`); `cnonce`, `nc` and `qop` only when qop was negotiated, `opaque` only when the challenge sent it; the digest-uri the request-target — the raw path, `/` for an empty one, `?` and the raw query, never the fragment. A non-ASCII username goes on the wire as RFC 7616 §3.4's `username*=UTF-8''…`, because HTTP-18's grammar refuses the quoted form (P6-76) (`digest_handler_test.rb` `WireTest`) |
| `AUTH-23` | MUST | ✅ | 8 | `ChallengeHandlerChain.new(handlers)`: the list copied and frozen at construction (a later `clear` on the caller's array changes nothing), each handler asked in declaration order through the one-method protocol `#authorization_for(challenges, request, proxy:)` (6c's P6-2), the first non-nil value returned — `[digest, basic]` answers Digest and `[basic, digest]` answers Basic to the same header (`challenge_handler_chain_test.rb`) |
| `AUTH-24` | MUST | ✅ | 7 | The handler is frozen after construction and its one mutable thing is the store, whose increment is `BoundedMap#update` — read, yield and write under the map's own `::Thread::Mutex`. Proven **deterministically**, not probabilistically: a block that re-enters the map meets `ThreadError: deadlock; recursive locking`, and a forced interleaving — thread A parked inside its block holding the old value, thread B observed blocked on the mutex before A is released — yields 2, where a block run outside the lock yields the lost increment 1; then sixteen threads from one barrier lose none of 3 200, and sixteen threads reusing one nonce through the handler produce 1 600 distinct counts (`bounded_map_test.rb`, `digest_handler_test.rb` `CounterTest`; guard 32) |
| `AUTH-25` | MUST | ✅ | 8 | `#header_name(proxy:)` is `Authorization` or `Proxy-Authorization` from the explicit flag alone; `#authorization_for` and `#as_challenge_hook` answer nil — no header, never an empty one — when no handler satisfies; the hook is the ONE place a handler's VALUE becomes a header on a request, SET rather than added, and with `proxy: true` writes `Proxy-Authorization` and not `Authorization` (`challenge_handler_chain_test.rb`) |
| `AUTH-26` | MUST | ✅ | 9 | `KeyStamper.new(credential)` over anything answering `#header_name`, `#prefix`, `#key_value` — both key types do — writes the key into the configured header, `Authorization` by default, with a configured prefix followed by exactly one space; the value computed once, checked against the outbound grammar at construction, and SET on every call (a re-stamp replaces, the original request untouched); the stamper is frozen and writes no ivar after construction (`key_stamper_test.rb`; guards 33, 34) |
| `AUTH-27` | MUST | ✅ | 11, 13, 14 | `Step#stage` and `AsyncStep#stage` answer `Pipeline::Stages::AUTH` (order 800), read once at install; a second AUTH step is refused by the builder (`PIPE-5`); the nesting is `PIPE-2`'s stage order, which 4c fixed — the pillar-integration set installs a REDIRECT-stage probe in front and a PRE_AUTH recorder and shows PRE_AUTH ran before the AUTH replay on both runtimes (`step_test.rb` `ConstructionTest`, `pillar_integration_test.rb`) |
| `AUTH-28` | MUST | ✅ | 11, 13 | `enforce_https!` runs before the stamper is called, on every path where a credential would be attached — `NO_STAMP` included, since the step cannot know a stamper attaches nothing — comparing the scheme with a bare `downcase` (`HTTPS://…` passes) and raising `Dexpace::Auth::HTTPSRequiredError` with `#scheme` and `#step` (`"Dexpace::Auth::Step"` / `"Dexpace::Auth::AsyncStep"`) in the message; a stamper that would have run flunks the test; on the root cursor too (`step_test.rb` `GuardTest`, `https_required_error_test.rb`, `pillar_integration_test.rb`; guards 35, 36) |
| `AUTH-29` | MUST | ✅ | 11, 13, 14 | Three clauses. **Suppression (implemented):** `cross_origin?` reads `cursor.state(Stages::REDIRECT)[:cross_origin]`, truthy meaning suppress, FIRST in `#call`; on a cross-origin re-issue nothing is stamped (a stamper that runs flunks), a StateProbe downstream reads `{cross_origin: true}`, and the step still forks (P4-39). **HTTPS-guard skip (implemented):** on that path a plaintext URL is forwarded credential-free rather than failing; on a same-origin re-issue (`cross_origin: false`) and with NO redirect step at all (the shared frozen empty slot) the request is re-stamped and re-guarded. **Stripping (satisfied by construction, no code):** the marker is cursor state and never a header, so nothing was added and nothing is stripped — `REDIR-11`'s clause (c) *a fortiori*, clause (a) structurally since a `Location` cannot reach cursor state (design §10.15). The mechanism can only suppress, never cause: a forged `X-Dexpace-Cross-Origin` request header changes nothing, a RETRY-stage fork writing `cross_origin: true` into its OWN slot changes nothing (4c's assertion 4), and an AUTH-stage fork cannot write REDIRECT's slot (`step_test.rb` `CrossOriginTest`, `async_step_test.rb`, `pillar_integration_test.rb`; guards 37–39) |
| `AUTH-30` | MUST | ✅ | 11, 13, 14 | On a 401 with `WWW-Authenticate` the hook is called with the joined header value (RFC 7235 §4.1: a repeated header is one list), the stamped request and the response; a replacement closes the original 401 (through `Dexpace.close_quietly`, with the step's `logger:` as the disposal route) and drives ONE fresh fork, with no further challenge handling — a second 401 surfaces; **the close comes BEFORE the drive**, asserted as the replay reaches the transport — the scripted second reply is a callable that reads the 401's close count when it is called, on the sync replay, the sync bearer retry and both async branches — and not by count after the fact, which a close-after-drive mutation survived (review round 1's R1-2; guards 69–72); `Step::NO_REPLACEMENT` is the default and yields nil; non-401 responses pass through untouched, sent once (`step_test.rb` `DriveTest`, `step_bearer_challenge_test.rb`, `async_step_test.rb` `ChallengeTest` and `BearerTest`, `pillar_integration_test.rb`; guards 40, 41, 44, 69–72) |
| `AUTH-31` | MUST | ✅ | 11, 11a, 13, 14 | One private `replayable?(request)` — `body.nil? \|\| body.replayable?`, phase 3b's own predicate called directly, never a 6a object — inherited by `AsyncStep` from `Step`, so the gate is one implementation on both runtimes (spec-forced boundary 13): a non-replayable replacement surfaces the original 401 UNCLOSED (`FakeResponseBody#closes` is 0) after one drive; a replayable body and no body replay; and the gate is applied to `AUTH-36`'s bearer retry as well (6c's P6-7) (`step_test.rb` `ReplayGateTest`, `step_bearer_challenge_test.rb`, `async_step_test.rb`, `pillar_integration_test.rb`; guards 42, 59) |
| `AUTH-32` | MUST | ✅ | 11, 13 | A hook that raises leaves the open 401 closed — `close_quietly(response, onto: error)`, so a close failure rides the hook error's suppressed trail — and the error propagates as the same object; a hook returning something that is not a request is refused the same way. On the async path all three clauses are real: a synchronous raise, a returned future that fails, and a non-request — **returned synchronously or through a future**, a future of a future included — each closing the 401 and failing the step's future. The future-fulfilled non-request shape left the 401 OPEN in round 1's tree, because the settled value was checked outside the frame that closes it: `Step#consult`'s rescue is now one private `closing_on_error(response)` frame both runtimes use, `AsyncStep` overrides `consult` to pass a future through, and the settled value is checked inside that frame (review round 1's R1-1; guard 73) (`step_test.rb` `ReplayGateTest`, `async_step_test.rb` `ChallengeTest`, `pillar_integration_test.rb`; guards 43, 60, 73) |
| `AUTH-33` | MUST | ✅ | 11, 13, 14 | A 401 with no `WWW-Authenticate` is returned as the same object, unclosed, after one drive, and the hook is never consulted; `challenge_header` answers nil for an absent or empty list (`step_test.rb`, `async_step_test.rb`, `pillar_integration_test.rb`; guard 44) |
| `AUTH-34` | MUST | ✅ | 10 | `BearerStamper.new(provider:, clock: Clock::SYSTEM, refresh_margin: DEFAULT_REFRESH_MARGIN = 30)`: `Authorization: Bearer <token>` SET; the token cached until `expired?(now:, margin: @refresh_margin)` — 69 s into a 100 s token is cached, 71 s refreshes; the hot path reads `@token` with NO lock (a mutex that raises on `synchronize` is installed after the first fetch and the next call succeeds — XCUT-12); the slow path takes the per-credential `::Thread::Mutex`, double-checks, and holds it across `@provider.fetch` — XCUT-12's one sanctioned lock-across-fetch — so sixteen threads racing on a missing token cause exactly ONE fetch, deterministically: the fetch parks until all sixteen have entered `#call` (`bearer_stamper_test.rb`; guards 45–47) |
| `AUTH-35` | MUST | ✅ | 10, 12 | `validate(fetched)` inside the lock: nil → `ProviderError`; not a `BearerToken` → `ProviderError`; `expired?(now:, margin: 0)` → `ProviderError`, with `expiry == now` accepted (strictly after); a raising provider propagates its own error; on every one of those `@token` is untouched and the next call fetches again. The async stamper's `invalid(token)` is the same three checks as a value, failing the waiters and caching nothing — the "nothing" asserted for the rejected already-expired token through `#evict_if_matches` and the cache slot, since a token cached although rejected was behaviourally near-invisible and a mutation caching it survived round 1 (R1-5; guard 80) (`bearer_stamper_test.rb`, `async_bearer_stamper_test.rb` `FailureTest`; guards 48, 80) |
| `AUTH-36` | MUST | ✅ | 10, 11a, 13 | Cache half: `#evict_if_matches(rejected_header)` compares `"Bearer #{token}"` with the rejected VALUE under the lock — exact, `"Bearer  current"` does not match — clears only on a match and reports which happened. Step half, `bearer_retry` before the hook: on a 401 whose challenges include `bearer`, with the rejected request carrying `Authorization`, and a replayable body, evict, close the 401, and re-stamp ONE retry — a fresh fetch when the eviction fired (`["Bearer old", "Bearer new"]` on the wire), the preserved token when another request already refreshed it (`["Bearer old", "Bearer refreshed-elsewhere"]`, one fetch in all); regardless of method (a POST retries); surfacing the 401 unchanged and unclosed with no eviction and no fetch when the request carried no `Authorization` (cross-origin suppression) or the response advertises no `Bearer`; a second 401 surfaces after the one retry, two forks and no `#call`; the hook is never consulted for a Bearer challenge and IS consulted for a Digest one. Mirrored on the async step through `#stamp_fresh` after an eviction and `#stamp` after a preserved token — the routing itself asserted through `SpyBearerStamper`, whose two stamps differ on the wire (`Bearer cached` / `Bearer fresh`) and which records the call order, because the real stamper fetches through either method once its cache is empty and the first suite could not tell them apart (review round 0's R0-1) (`bearer_stamper_test.rb`, `step_bearer_challenge_test.rb`, `async_step_test.rb` `BearerTest`; guards 49–51, 62) |
| `AUTH-37` | MUST | ✅ | 12, 13 | `AsyncBearerStamper#stamp` reads one lock-free token and decides the zone from one clock reading: **fresh** (not expired with the margin) stamps in an already-settled future with no provider call, and takes no lock; **expiring-but-valid** stamps the still-valid token in a settled future at once and starts a refresh it never awaits (the future is settled before the refresh is; the boundary is exactly the margin — 1030 against 1000+30 is fresh, 1029 is expiring); **expired or missing** derives the stamped request from the coalesced fetch through `Future#then`. ONE single-flight slot: eight missing-zone and four expiring-zone callers cost one fetch. A failed BACKGROUND refresh is reported through `logger:` as one `http.auth.refresh` WARNING (`Events::AUTH_REFRESH`, P6-77) carrying the cause, the in-flight request already stamped, and caches nothing; a failed awaited fetch fails its waiters with the same object, caches nothing, and the next call retries. The fetch is started OUTSIDE the lock — a `#fetch`-only provider mirrors into an already-settled future whose `#on_settle` runs inline, and starting it under the lock is `ThreadError: deadlock; recursive locking` (R12, guard 55). `#stamp_fresh` bypasses the cache and awaits a fetch, the post-eviction clause, and `AsyncStep` routes a successful eviction through it and a failed one through `#stamp` — proven through `SpyBearerStamper` since review round 0 (R0-1), the mutation that survived the first suite now caught (guard 62). No `#value`, `#wait` or `Async.delay` in the file, asserted by scan (`async_bearer_stamper_test.rb`, `async_step_test.rb` `BearerTest`; guards 52–57, 62) |
| `AUTH-38` | SHOULD | ✅ | 13 | `AsyncStep#call` runs its whole body inside one `Completer` frame: the HTTPS guard, a raising stamper, a failing provider, the hook's three failure clauses and every settlement callback (`guarded`, on the calling fiber and on whatever thread settles a future) fail the ONE returned future rather than raising. Proven with the step called DIRECTLY on a root cursor, because through a pipeline the driver's own PIPE-30 normalisation would hide the frame; and with no `Fiber.scheduler` registered, since nothing in the class waits or delays (`async_step_test.rb` `FrameTest`; guard 58) |
| Task 15 | — | **written, guarded; owned by 6b** | 15 | `cross_origin_convergence_test.rb`: a seed origin, a 302 whose `Location` is a foreign host, a real `KeyStamper` credential on the real `Auth::Step`, and the assertion that no `Authorization` reaches the second hop while the first was stamped. Its body is real — every helper is defined, and against a scratch stub `Dexpace::Redirect::Step` it passed when the stub forked the second hop with `{ cross_origin: true }` and failed with `Expected ["authorization"] to not include "authorization"` when the stub forked without the marker — and it skips on this base with the stated reason because `Dexpace::Redirect::Step` does not exist here. Phase 6b, which lands last, un-guards it against its real step and owns it under the charter's "whichever of 6b/6c lands second" rule. Not ticked |

Cross-reference rows, the IDs this phase owns a share of:

| ID | Status | What 6c supplies, and where it is proven |
|---|---|---|
| `REDIR-11` (clause b) | ✅ reader half | "only SUPPRESS stamping, never CAUSE a credential to be sent" is the only clause with executable content on the AUTH side: the read is truthy-means-suppress from a slot only the REDIRECT pillar's own fork can write, a request header and a RETRY slot both change nothing, and the empty slot is the same-origin answer (`step_test.rb` `CrossOriginTest`). Clauses (a) and (c) are satisfied structurally and by construction (the `AUTH-29` row). The writer half is 6b's |
| `XCUT-12` | ✅ | The bearer hot path is lock-free by publication of one frozen `BearerToken` reference, on both stampers (a refusing mutex proves it); the one sanctioned lock across a suspension point is `BearerStamper#refresh!`'s fetch under the per-credential mutex, scoped so it serialises nothing else; the async stamper holds its lock across a flag flip only and starts the fetch outside it (`bearer_stamper_test.rb`, `async_bearer_stamper_test.rb`) |
| `XCUT-14`, `CTX-11` | ✅ second consumer | `DigestHandler`'s nonce store is phase 4a's `BoundedMap`, "one implementation" holding under the full-nesting condition, with `#update` added in place — the insert and the drain loop in one critical section as `#set` has them — and `bounded_map.rb` gaining a true `test/` mirror for it, which takes it off the private-constant exception list (`bounded_map_test.rb`) |
| `XCUT-16` | ✅ | The HTTPS guard on every credential-attaching path, before any fetch or write, on both runtimes (the `AUTH-28` row) |
| `XCUT-19`, `OBS-13` | ✅ objects' half | The credential OBJECTS' three renderings are 6c's (the `AUTH-8` row); the header VALUES on the way into a log record are 5b's redactor, whose default allow-list already omits `authorization`, `proxy-authorization`, `www-authenticate` and `proxy-authenticate`, and 6c adds no policy member |
| `XCUT-21` | ✅ | The cnonce is `::SecureRandom.hex(16)`, never `Random` and never 5a's non-cryptographic `Dexpace::UUID` (the `AUTH-20` row) |
| `BODY-1` (`#replayable?`) | ✅ call site | `request.body&.replayable?` — spelled `body.nil? \|\| body.replayable?` — called directly from the one inherited predicate on both runtimes, with `FakeBody.new(…, replayable: false)` as the non-replayable fixture (the `AUTH-31` row) |
| `PIPE-15`, P4-39 | ✅ | Both steps fork for EVERY drive, the first included, and never call the handed cursor: a `SpyCursor` wrapper around the driver-made cursor counts one fork and zero calls on a plain drive, two forks and zero calls on a replay, and the cross-origin path forks too; the call-then-fork shape raises `PipelineError: cursor is spent and cannot be forked` (guard 40) (`step_test.rb`, `step_bearer_challenge_test.rb`, `async_step_test.rb`) |
| `PIPE-30` | ✅ consumed | The async driver normalises a synchronously raising async step into a failed future; 6c relies on it for nothing — its own frame is what `AUTH-38` rests on — and the direct-call test is what tells the two apart |
| `HTTP-18` | ✅ consumed | The outbound header grammar decides two things the requirements leave open: a non-ASCII Digest username takes the `username*` form, and a challenge whose realm, nonce or opaque cannot be echoed is unsatisfiable (P6-76); `KeyStamper` refuses a key the grammar cannot carry at construction |
| `SEAM-1` | ✅ | `digest` is the one plain `require` the phase adds to core, in `digest_handler.rb`; `securerandom` and `strscan` were already required; all three were on the allowlist before this phase; `base64` is refused by the gate as "bundled since 3.4.0" (guard 21). `seam_surface_test.rb`'s pin grows from four features to five |
| `OBS-39` | ✅ widened | `Instrumentation::Events` gains its ninth name, `AUTH_REFRESH = "http.auth.refresh"`, outside the `http.instrumentation.` prefix, 5b's `keys_test.rb` pin repaired on the code branch (P6-77) |

## What was built

Twenty-five new `lib/` files: `lib/dexpace/auth.rb` (the namespace and `REDACTED`),
`lib/dexpace/error/auth_resolution_error.rb` (flat, as `AUTH-6`'s general failure), and twenty-three
under `lib/dexpace/auth/` — `validation.rb` (`private_constant`), `scheme.rb`, `requirement.rb`,
`descriptor.rb`, `resolver.rb`, `bearer_token.rb`, `key_credential.rb`, `named_key_credential.rb`,
`password_credential.rb`, `challenge.rb`, `challenges.rb` (with its private `Parser`),
`basic_handler.rb`, `digest_handler.rb` (with its private `Computed`), `challenge_handler_chain.rb`,
`key_stamper.rb`, `bearer_provider.rb`, `bearer_stamper.rb`, `async_bearer_stamper.rb`, `step.rb`,
`async_step.rb` (with its private `Exchange`), and the three namespaced errors
`unencodable_credential_error.rb`, `https_required_error.rb` and `provider_error.rb`, filed under
`auth/` because their constants are under `Auth`, the way phase 2's `Serde` errors sit under
`serde/` (the plan filed them flat under `error/`; deviation 4 below). Three earlier files widened in
place, each a designed widening: `bounded_map.rb` gains `#update(key) { |old| new }`, phase 4a's own
forward-table addition; `instrumentation/keys.rb` gains `Events::AUTH_REFRESH` — a second earlier-phase
`lib/` file widened beside `bounded_map.rb`, a pure widening of a module 6a may widen too, so the
manager's 6a/6c merge treats `instrumentation/keys.rb` and 5b's `keys_test.rb` as a shared pair
(review round 0's R0-5); and `lib/dexpace.rb`
gains a twenty-five-line `# Phase 6c:` block after 5b's, in dependency order. Every file has a `sig/`
mirror — `validation.rbs` with `hooks.rbs`'s comment, the private `Parser`, `Computed`, `Exchange`,
`HASHES`, `ECHOED`, `NAMES` and the parser's eight patterns declared because the strict `core` Steep
target types their uses, and the six RBS interfaces `_Hasher`, `_CnonceSource`, `_ChallengeHandler`,
`_KeyCredential`, `_BearerProvider` and `_AsyncBearerProvider` because NFR-11's scan admits no
`Digest`, `SecureRandom` or `Random` in a public signature — and every public file a `test/` mirror,
twenty-five of them, plus `bounded_map_test.rb`, the first true mirror of a private constant, so
`bounded_map.rb` leaves the exception list as `auth/validation.rb` joins it, and the count stays at
eleven. Five suites carry no `lib/` mirror and say so in their headers: `step_bearer_challenge_test.rb`
(11a, a second suite over `step.rb`), `pillar_integration_test.rb` (14, one example set over both
runtimes plus a broken-step sanity check), `cross_origin_convergence_test.rb` (15, guarded),
`matrix_facts_test.rb` (Task 1's facts as a standing test, 5a's, 5b's and 5c's precedent) and
`error/auth_resolution_error_test.rb`'s sibling-less shape is the template's. Nine new top-level
test-support doubles, one class per file: `ChallengeFixtures`, `FixedCnonce`, `SequencedTransport`
(named so as not to collide with the `ScriptedTransport` phase 6a is writing at the same time; the
manager reconciles the pair after both lanes land), `SequencedAsyncTransport`,
`ScriptedBearerProvider`, `ScriptedAsyncBearerProvider`, `SpyCursor` (the recording wrapper over a
driver-made cursor, 5b's item-12 shape), `SpyBearerStamper` (review round 0's R0-1: a stamper whose
`#stamp` and `#stamp_fresh` differ on the wire, the only way `AsyncStep`'s post-eviction routing can be
told apart) and the `AuthFixtures` module over 4b's `RecoveryFixtures`.
Four existing tests changed, all on the code branch as pins the code invalidated: the smoke suite's
layer table (`Auth`, `AuthResolutionError`) and its preloaded stdlib features (`digest`, or the
top-level `Digest` reads as the entry file's), `seam_surface_test.rb`'s require pin (four features
become five), and 5b's `keys_test.rb` (eight events become nine). The surface manifest was regenerated
once, from 956 to 1 059 lines, and all 103 rows read against the object model: every public constant
and method of the layout above, `Challenges#parse`, `Resolver#resolve` and `BearerProvider#fetch_async`
as `#` rows because `extend self` is what the cop set prescribes, `Scheme#with` as the refusing
override, and nothing private; review round 1's repair regenerated it once more, to 1 060 lines, for
the one reader it added, `UnencodableCredentialError#source_encoding`.

## Matrix facts, re-run on every interpreter

The plan's eight facts and the two the design flagged as needing the floor were run on 2026-09-18 on
**3.2.11, 3.3.12, 3.4.10 and 4.0.6**, first as one scratch script per interpreter and then as
`matrix_facts_test.rb`, a standing test on every CI row. Every fact holds identically on every row:
`["alice:s3cr3t"].pack("m0")` is `YWxpY2U6czNjcjN0` and US-ASCII, `["ü:pä"]` packs to `w7w6cMOk`;
`"!!a b c!!".unpack1("m")` is `"i\xB7"`; MD5 and SHA-256 hexdigests are lower-case 32 and 64;
`format("%08x", 0x100000001 & 0xFFFFFFFF)` is `00000001`; `"日".encode("ISO-8859-1")` raises
`Encoding::UndefinedConversionError` and `"pä"` encodes to `[112, 228]`; `SecureRandom.hex(16)` is 32
lower-case hex characters; `"auth-int".include?("auth")` is true; a `Data`'s members are not ivars;
`dup.freeze` is shallow and `Model.own` deep; `Thread::Mutex` re-entry is `ThreadError: deadlock;
recursive locking`; `Gem::BUNDLED_GEMS::SINCE` is undefined on 3.2.11 and defined on 3.3.12, 3.4.10
and 4.0.6. **The four Digest expectations were DERIVED on all four interpreters and are identical on
every row**: RFC 2617 §3.5's `qop=auth` vector `6629fae49393a05397450978507c4ef1`, the legacy no-qop form
of the same inputs `670fd8c2df070c60b045671b8b24ff02`, RFC 7616 §3.9.1's inputs under SHA-256
`9fbf3e2223549127935ba79d47a0299af1f57eae1240ead830c0b47ad60346e1` and under SHA-256-sess
`a0316f893cdcbd706441a5392ef9e690688b447acf4015a2b9ce520e6b551a5c`. Two facts neither the plan nor
the design stated were found by the build and hold on every row: **`pp` walks a `Data`'s members and
never calls an `#inspect` override** (P6-72; the corpus note filed under `docs/knowledge/notes/`), and
**a UTF-8-tagged String with an invalid byte makes `StringScanner#scan` and `String#downcase` raise
`ArgumentError`** (P6-74), which the plan's parser fence would have surfaced from `AUTH-13`'s
never-raising parser. A third, the reachability facts for the private map — `const_get` bypasses
`private_constant`, `Dexpace::BoundedMap` raises `private constant … referenced`, the compact
`module Dexpace::Auth::…` form raises `uninitialized constant`, the full-nesting form resolves — hold on
every row as `execution-context/b58728da` states.

## Guards run red

Every guard the brief asks to be seen red was seen red, on 4.0.6 and on 3.2.11, and the bytes restored
after each: sixty-one single-edit mutations of `lib/`, one at a time through a harness that applies
the edit, runs the owning suites under `ruby -w`, captures the first failure and restores the file;
plus the cop and the require gate run against a mutated file by hand. On the first 4.0.6 pass
fifty-seven were caught; two mutations crashed the suite on an unused-variable warning
(`FatalWarnings`) rather than an assertion and were re-spelled to keep the variable live (49, 56); and
**two stayed green because the suite had a gap, which was closed** — the parameter-name fold
mutation survived because the parser folded a second time on top of the model (the parser's duplicate
fold was removed and the model is now the one fold point, guards 14 and 15), and removing the async
step's `guarded` rescue survived every pipeline test because the driver's own PIPE-30 normalisation
catches a synchronous raise, which is why `async_step_test.rb` now calls the step directly on a root
cursor (guard 58). One mutation (53) hangs the suite rather than failing it — a background refresh
that waits on the unsettled fetch never returns — which is the guard firing as the brief's "a hang
there is a finding"; the `R12 as code` source-scan test, run by name, reports it as an assertion. On
the second pass **all sixty-one are caught**, and the 3.2.11 pass, run whole after the gaps were
closed, catches all sixty-one as well.

| # | Fix reverted | Guard | What it said (4.0.6; identical on 3.2.11 unless stated) |
|---|---|---|---|
| 1 | `AUTH-2`: `Model.own` replaced by `dup.freeze` | `requirement_test.rb` | `Expected: {"aud" => ["api"]} Actual: {"aud" => ["api:other"]}` (2 failures; the String inside the retained array reached) |
| 2 | `AUTH-9`: the blank check dropped from `Validation.non_blank!` | `bearer_token_test.rb`, `key_credential_test.rb`, `named_key_credential_test.rb` | `Dexpace::InvalidArgumentError expected but nothing was raised` (5 failures across the three) |
| 3 | `AUTH-8`: `BearerToken#inspect` printing the token | `bearer_token_test.rb` | `Expected … token=super-secret-token …` (3 failures, the "equal renderings, unequal tokens" pair among them) |
| 4 | `AUTH-8`: `BearerToken#to_s` printing the token | `bearer_token_test.rb` | `Expected "BearerToken(token=super-secret-token, …" to not include "super-secret"` |
| 5 | `AUTH-8`: `BearerToken#pretty_print` dropped | `bearer_token_test.rb` | `Expected "#<data Dexpace::Auth::BearerToken token=\"super-secret-token\", …" to not include "super-secret"` — the `pp` leak |
| 6 | `AUTH-8`: `KeyCredential#inspect` printing the key | `key_credential_test.rb` | `Expected "#<Dexpace::Auth::KeyCredential api_key=super-secret-key …" to not include "super-secret"` |
| 7 | `AUTH-8`: `KeyCredential#to_s` printing the key | `key_credential_test.rb` | `Expected "KeyCredential(api_key=super-secret-key, …" to not include "super-secret"` |
| 8 | `AUTH-8`: `NamedKeyCredential#inspect` printing the key | `named_key_credential_test.rb` | `Expected "#<Dexpace::Auth::NamedKeyCredential name=\"key-name\" key=super-secret-key …" to not include "super-secret"` |
| 9 | `AUTH-8`: `NamedKeyCredential#to_s` printing the key | `named_key_credential_test.rb` | `Expected "NamedKeyCredential(name=\"key-name\", key=super-secret-key, …" to not include "super-secret"` |
| 10 | `AUTH-8`: `PasswordCredential#inspect` printing the password | `password_credential_test.rb` | `Expected "#<Dexpace::Auth::PasswordCredential username=[REDACTED] password=super-secret>" to not include "super-secret"` (2 failures: pp too) |
| 11 | `AUTH-8`: `PasswordCredential#to_s` printing the username | `password_credential_test.rb` | `Expected "PasswordCredential(username=alice-user, …" to not include "alice-user"` |
| 12 | `AUTH-8`: `PasswordCredential#pretty_print` dropped | `password_credential_test.rb` | `Expected "#<data Dexpace::Auth::PasswordCredential username=\"alice-user\", password=\"super-secret\">" to not include "super-secret"` |
| 13 | `AUTH-8`/`AUTH-10`: `KeyCredential` given `==`/`eql?`/`hash` over its fields | `key_credential_test.rb` | `Expected #<…KeyCredential api_key=[REDACTED] …> to not be equal to #<…KeyCredential api_key=[REDACTED] …>` |
| 14 | `AUTH-12`: the parameter-name fold in `Challenge.build` made case-sensitive | `challenges_test.rb`, `challenge_test.rb` | `--- expected {"realm" => "MiXeD"} +++ actual {"REALM" => "MiXeD"}` (2 failures) |
| 15 | `AUTH-12`: the scheme fold made case-sensitive | `challenges_test.rb`, `challenge_test.rb`, `basic_handler_test.rb` | 10 failures in the parser suite, `Expected: "basic" Actual: "BASIC"`, and the Basic handler's case-insensitive acceptance |
| 16 | `AUTH-13`: token68 padding dropped (`=*` removed from the pattern) | `challenges_test.rb` | `Expected: "dGhlIHNlY3JldCB0b2tlbg==" Actual: nil` |
| 17 | `AUTH-13`: the top-level comma consumed twice | `challenges_test.rb` | `Expected: ["basic", "digest"] Actual: ["basic"]` (4 failures) |
| 18 | `AUTH-13`: an unterminated quoted-string raising at EOF | `challenges_test.rb` | `ArgumentError: unterminated quoted-string` (2 errors) |
| 19 | `AUTH-13`: recovery not walking a quoted string | `challenges_test.rb` | `Expected: ["digest", "basic"] Actual: ["digest", "b", "basic"]` |
| 20 | `AUTH-13`: a malformed tail raising instead of recovering | `challenges_test.rb` | `ArgumentError: malformed parameter` (2 errors) |
| 21 | `AUTH-14`: `require "base64"` added to the Basic handler | `gates:require_allowlist` | `lib/dexpace/auth/basic_handler.rb:4: require "base64" -- bundled since 3.4.0; a gem must declare it explicitly under Bundler.` — on 3.2.11, where `Gem::BUNDLED_GEMS::SINCE` is undefined, the same line reads `-- not in the require allowlist`, the refusal holding on every row and the reason on the 4.0 row, as `CLAUDE.md` states |
| 22 | `AUTH-14`: the credential pair packed without transcoding to UTF-8 | `basic_handler_test.rb` | `Expected: "Basic w7w6cMOk" Actual: "Basic /Dpw5A=="` (the Latin-1-tagged credential's bytes) |
| 23 | `AUTH-15`: the auth-int-only decline as a substring test | `digest_handler_test.rb` | `Expected "Digest username=…" to be nil` |
| 24 | `AUTH-17`: hexdigests upper-cased | `digest_handler_test.rb` | `--- expected 9fbf3e22… +++ actual 9FBF3E22…` (8 failures) |
| 25 | `AUTH-18`: nc not wrapping at 32 bits | `digest_handler_test.rb` | `Expected: "00000000" Actual: "100000000"` |
| 26 | `AUTH-18`: one counter for every nonce | `digest_handler_test.rb` | `Expected: "00000000" Actual: "00000004"` (3 failures, the restart-per-nonce among them) |
| 27 | `AUTH-19`: the cap ignored | `digest_handler_test.rb` | `Expected: 2 Actual: 3` (the store held every nonce) |
| 28 | `AUTH-19`: the store reached as `Dexpace::BoundedMap` | `digest_handler_test.rb` | `NameError: private constant Dexpace::BoundedMap referenced` (28 errors; the compact `module Dexpace::Auth::…` body raises `uninitialized constant`, scratch-verified) |
| 29 | `AUTH-20`: the cnonce from `::Random.new` | `digest_handler_test.rb` | the source-scan assertion: `Expected "…" to include "::SecureRandom"` |
| 30 | `AUTH-21`: the Latin-1 branch with `undef: :replace` | `digest_handler_test.rb` | `Dexpace::Auth::UnencodableCredentialError expected but nothing was raised` (2 failures) |
| 31 | `AUTH-21`: the rescue removed, the bare conversion error escaping | `digest_handler_test.rb` | `[Dexpace::Auth::UnencodableCredentialError] exception expected, not #<Encoding::UndefinedConversionError: U+65E5 from UTF-8 to ISO-8859-1>` |
| 32 | `AUTH-24`: `BoundedMap#update`'s block run outside the mutex (read, yield, write) | `bounded_map_test.rb` | `ThreadError expected but nothing was raised`, and the forced interleaving `Expected: 2 Actual: 1` — the lost increment |
| 33 | `AUTH-26`: the key always written to `Authorization` | `key_stamper_test.rb` | `Expected: ["abc"] Actual: nil` (the `X-Api-Key` header absent) |
| 34 | `AUTH-26`: the outbound-grammar check dropped | `key_stamper_test.rb` | `Dexpace::InvalidArgumentError expected but nothing was raised` |
| 35 | `AUTH-28`: the guard removed | `step_test.rb`, `pillar_integration_test.rb` | `[Dexpace::Auth::HTTPSRequiredError] exception expected but nothing was raised` (4 + 2 failures, both runtimes) |
| 36 | `AUTH-28`: a bare `RuntimeError` instead of `HTTPSRequiredError` | `step_test.rb` | `[Dexpace::Auth::HTTPSRequiredError] exception expected, not #<RuntimeError: https required>` (4 failures) |
| 37 | `AUTH-29`: the guard skipped cross-origin but the stamper still run | `step_test.rb` | the stamper's own `flunk`: `must not stamp cross-origin` |
| 38 | `AUTH-29`: the marker read from a request header | `step_test.rb`, `pillar_integration_test.rb` | `Dexpace::Auth::HTTPSRequiredError: Dexpace::Auth::Step refuses to attach a credential to a "http" request` on the cross-origin case (both runtimes) |
| 39 | `AUTH-29`: the empty slot treated as cross-origin | `step_test.rb` | 14 failures: every same-origin and no-redirect-step case unstamped |
| 40 | `AUTH-30` / P4-39: the first drive through `cursor.call`, the replay through `#fork` | `step_test.rb` | `Dexpace::PipelineError: cursor is spent and cannot be forked; #call and #fork are disjoint (PIPE-15)` (4 errors) and the spy's `Expected: 0 Actual: 1` calls |
| 41 | `AUTH-30`: the replacement driven twice | `step_test.rb` | `RuntimeError: SequencedTransport: no scripted reply for drive 3` (3 errors) |
| 42 | `AUTH-31`: a non-replayable replacement replayed | `step_test.rb`, `pillar_integration_test.rb` | `Expected #<…Response status=401…> to be the same as #<…Response status=200…>` (both runtimes' sync half) |
| 43 | `AUTH-32`: the 401 not closed when the hook raises | `step_test.rb`, `pillar_integration_test.rb` | `Expected: ["close failed"] Actual: []` and `Expected: 1 Actual: 0` closes (3 + 2 failures) |
| 44 | `AUTH-33`: a 401 without `WWW-Authenticate` consulting the hook | `step_test.rb` | `Expected true to not be truthy` (`consulted`) |
| 45 | `AUTH-34`: the hot path taking the lock | `bearer_stamper_test.rb` | `RuntimeError: the hot path took the lock (XCUT-12)` |
| 46 | `AUTH-34`: the fetch moved outside the lock (single-flight broken) | `bearer_stamper_test.rb` | `Expected: 1 Actual: 16` fetches under sixteen threads |
| 47 | `AUTH-35`: a cached token used past expiry | `bearer_stamper_test.rb` | `Expected: ["Bearer t2"] Actual: ["Bearer t1"]` |
| 48 | `AUTH-35`: an already-expired fetched token cached | `bearer_stamper_test.rb` | `Dexpace::Auth::ProviderError expected but nothing was raised` |
| 49 | `AUTH-36`: a no-op eviction | `bearer_stamper_test.rb`, `step_bearer_challenge_test.rb` | `Expected: ["Bearer new"] Actual: ["Bearer old"]` and `["Bearer old", "Bearer old"]` on the wire (1 + 3 failures) |
| 50 | `AUTH-36`: evicting whatever is cached, not the exact token | `bearer_stamper_test.rb`, `step_bearer_challenge_test.rb` | `Expected true to not be truthy` and the preserved token re-fetched (1 + 1 failures) |
| 51 | `AUTH-36`: the retry gated on idempotency | `step_bearer_challenge_test.rb` | `Expected: 200 Actual: 401` (the POST not retried) |
| 52 | `AUTH-37`/`AUTH-10`: the zone boundary `>=` instead of `>` | `bearer_token_test.rb`, `async_bearer_stamper_test.rb` | `Expected true to not be truthy` at exactly the margin, and the fresh-zone stamper's `no fetch expected` flunk |
| 53 | `AUTH-37`: the background refresh waiting on its fetch | `async_bearer_stamper_test.rb` | the suite HANGS (killed after 90 s: the test holds the completer unsettled until `stamp` returns, which it never does); run by name, `R12 as code`: `Expected /\.value\b\|\.wait\b\|Async\.delay/ to not match …` |
| 54 | `AUTH-37`: a failed background refresh raised | `async_bearer_stamper_test.rb` | `RuntimeError: refresh failed` out of the settle callback |
| 55 | `AUTH-37` (R12): the fetch started under the lock | `async_bearer_stamper_test.rb` | `ThreadError: deadlock; recursive locking` (5 errors) |
| 56 | `AUTH-37`: the single-flight slot never reused | `async_bearer_stamper_test.rb` | `Expected: 1 Actual: 12` fetches for twelve coalescing callers |
| 57 | `AUTH-37`: `#stamp_fresh` reusing the cache | `async_bearer_stamper_test.rb` | `Expected: ["Bearer fetched"] Actual: ["Bearer cached"]` |
| 58 | `AUTH-38`: the frame's rescue removed | `async_step_test.rb` | `Dexpace::Auth::HTTPSRequiredError: Dexpace::Auth::AsyncStep refuses to attach …` raised synchronously from the direct call; every pipeline test stays green because the driver normalises it (PIPE-30) |
| 59 | `AUTH-31` (async): the gate dropped | `async_step_test.rb`, `pillar_integration_test.rb` | `Expected #<…Response status=401…> to be the same as #<…status=200…>` (both) |
| 60 | `AUTH-32` (async): a failed hook future not closing the 401 | `async_step_test.rb` | `Expected: 1 Actual: 0` closes |
| 61 | `AUTH-11`: `BearerProvider.fetch_async`'s rescue removed | `bearer_provider_test.rb`, `async_bearer_stamper_test.rb` | `RuntimeError: boom` raised synchronously, and `fatal: No live threads left. Deadlock?` — a future nobody settles — in the stamper suite |
| cop | `AUTH-12`: `name.downcase(:turkic)` in `Challenge.build` | `rubocop` | `Dexpace/NoLocaleCaseFold: Call downcase with no argument: Ruby's fold is opt-in-locale and HTTP-13 needs ASCII folding.` |

4c's negative assertion 4 from the AUTH side, asked for as a guard, has no mutation to run: an AUTH
step cannot write REDIRECT's slot because `Cursor#fork(state:)` merges into the FORKING pillar's own
slot, chosen from the entry table, and the cursor has no setter — the test installs a forger at
`Stages::AUTH` that forks with `{ cross_origin: false }` and a reader at `POST_AUTH` that still sees
`{ cross_origin: true }` under `Stages::REDIRECT`, and asserts the cursor's public methods include
nothing matching `state=` or `write`.

After review round 0's repair (2026-09-18), one per line the repair made load-bearing and one per
mutation the round reported surviving, each applied by hand against the repaired suites and reverted,
**on 4.0.6 and on 3.2.11** — all seven caught on both.

| # | Fix reverted | Guard | What it said (identical on both rows unless stated) |
|---|---|---|---|
| 62 | `AUTH-37` (R0-1): the post-eviction retry stamped through `#stamp` instead of `#stamp_fresh` — the round's M45 | `async_step_test.rb` `BearerTest` | `--- expected ["Bearer cached", "Bearer fresh"] +++ actual ["Bearer cached", "Bearer cached"]` — the mutation that survived round 0, now caught |
| 63 | `AUTH-13` (R0-2): `TOKEN` compiled without `timeout:` — the round's M37x | `challenges_test.rb` `LeniencyTest` | `Expected nil to not be nil.` (`TOKEN`) — the plan-equivalent survivor, now caught |
| 64 | `AUTH-13` (R0-2): `QUOTE` not frozen | `challenges_test.rb` `LeniencyTest` | `Expected /"/ to be frozen?.` |
| 65 | `AUTH-21` (R0-3): the error always naming ISO-8859-1 — round 0's tree | `digest_handler_test.rb` `EncodingTest` | `--- expected [:password, "UTF-8"] +++ actual [:password, "ISO-8859-1"]` |
| 66 | `AUTH-21` (R0-3): the UTF-8 branch's validity check dropped (an invalid UTF-8-tagged credential hashed as it is) | `digest_handler_test.rb` `EncodingTest` | `Dexpace::Auth::UnencodableCredentialError expected but nothing was raised.` |
| 67 | `AUTH-21` (R0-3): the UTF-8 reason worded as the Latin-1 one | `unencodable_credential_error_test.rb`, `digest_handler_test.rb` | `Expected "the password cannot be encoded as UTF-8: the Digest challenge did not advertise charset=UTF-8, …" to include "advertised charset=UTF-8".` (1 + 1 failures) |
| 68 | `AUTH-18` (R0-4): the nonce count taken before the credential is materialised — round 0's tree | `digest_handler_test.rb` `CounterTest` | `Expected 1 to be nil.` (the refused attempt's count left in the store) |

The round's fifth finding, R0-5, has no line of `lib/` behind it and no mutation: it records that
`instrumentation/keys.rb` is a second earlier-phase file widened beside `bounded_map.rb`, for the
manager's 6a/6c merge to treat as shared, which "What was built" above now says.

After review round 1's repair (2026-09-18), one per line the repair made load-bearing and one per
mutation the round reported surviving, each applied by hand through the same harness against the
repaired suites and reverted, **on 4.0.6 and on 3.2.11** — all twelve caught on both.

| # | Fix reverted | Guard | What it said (identical on both rows unless stated) |
|---|---|---|---|
| 69 | `AUTH-30` (R1-2): the sync replay closes the 401 AFTER the drive — the round's MX1, which survived the count-only form | `step_test.rb` `DriveTest` | `Expected: 1 Actual: 0` — the close count read as the replay reached the transport |
| 70 | `AUTH-36` (R1-2): the sync bearer retry closes the 401 after the drive | `step_bearer_challenge_test.rb` `RetryTest` | `Expected: 1 Actual: 0` (the retry-time read; on 4.0.6 the first failure reported is the `AUTH-35 on the retry` case, whose raising provider leaves the 401 open under the mutated order) |
| 71 | `AUTH-30` (R1-2): the async replay chains the drive before closing | `async_step_test.rb` `ChallengeTest` | `Expected: 1 Actual: 0` |
| 72 | `AUTH-36` (R1-2): the async bearer retry started before the close | `async_step_test.rb` `BearerTest` | `Expected: 1 Actual: 0` |
| 73 | `AUTH-32` (R1-1): the settled hook value checked outside the closing frame — round 1's tree | `async_step_test.rb` `ChallengeTest` | `Expected: 1 Actual: 0` closes, for the String and the future-of-a-future shapes |
| 74 | `AUTH-21` (R1-3): the Digest failure raised with the rescued conversion error as `cause:` — round 1's tree | `digest_handler_test.rb` `EncodingTest` | `Expected #<Encoding::UndefinedConversionError: "\xE4" from ASCII-8BIT to UTF-8> to be nil.` (4.0.6); on 3.2.11 the first failure is the rendering test, `U+65E5` found in `full_message` |
| 75 | `AUTH-21` (R1-3): the Digest failure raised bare (whatever `$!` is in flight becomes the cause) | `digest_handler_test.rb` `EncodingTest` | the same nil-cause assertion |
| 76 | `AUTH-21` (R1-3): `#source_encoding` hard-coded to `"UTF-8"` | `digest_handler_test.rb` `EncodingTest` | `--- expected [:password, "UTF-8", "ASCII-8BIT"] +++ actual [:password, "UTF-8", "UTF-8"]` |
| 77 | `AUTH-14` (R1-3): `BasicHandler` lets the bare conversion error escape — round 1's tree | `basic_handler_test.rb` | `[Dexpace::InvalidArgumentError] exception expected, not Class: <Encoding::UndefinedConversionError>` |
| 78 | `AUTH-14` (R1-3): `BasicHandler`'s typed refusal carries the conversion error as `cause:` | `basic_handler_test.rb` | `Expected #<Encoding::UndefinedConversionError: "\xE4" from ASCII-8BIT to UTF-8> to be nil.` |
| 79 | `AUTH-14` (R1-3): `BasicHandler`'s validity check dropped (an invalid UTF-8-tagged field packed as it is) | `basic_handler_test.rb` | `Dexpace::InvalidArgumentError expected but nothing was raised.` |
| 80 | `AUTH-35` (R1-5): a token `invalid` rejected as already expired cached anyway — the round's M51 | `async_bearer_stamper_test.rb` `FailureTest` | `Expected true to not be truthy.` (`#evict_if_matches("Bearer expired")` answered true) |

The round's fourth finding, R1-4, is the roadmap note's pre-repair run and coverage figures, and has
no mutation; the note now carries the figures of every tip since.

## Audit groups run

The phase-start pair first, at implementation: `--origin note --brief` returned 53 note entries across
21 files; `--section conflicts --brief` returned 25 entries with all six harvested conflicts
`[overridden by notes/…]` and none open. The eleventh audit group, `--prefix RETRY,REDIR,AUTH
--section rules --brief`, returned 371 lines, **zero tagged `[appendix-B roll-up]`**, covering 37 of
`AUTH`'s 38 (`AUTH-14` filed under Reference, read with `--req`); appendix C's rows for all
thirty-eight were read verbatim. `--req` was run per task. The three note entries the charter binds
were read in full and are what three decisions rest on: `pipeline/86343352` (both steps fork for every
drive; guard 40 is the rejected shape), `execution-context/b58728da` (the bare-name reachability;
guard 28 is the qualified spelling) and `pipeline/7ce4431d` (no carried re-raise exists in 6c — every
`raise` is of an error just rescued or freshly built, so `cause: nil` applies nowhere, and the one
re-raise in `Step#consult` is a bare `raise` of the rescued object).

| Group | Result at implementation |
|---|---|
| Public API surface | `module-organization/1828a984` (one public constant per file) holds for every new file — `bearer_provider.rb` carries the module and two RBS interfaces by design; `api-design/b0e18938` is why `Validation`, `Parser`, `Computed`, `Exchange`, the two tables and the eight patterns are private and every public name is in the design's object model or in P6-71–P6-85; the one-method handler protocol (P6-2) and the `BearerProvider.fetch_async` function are the two surfaces the design named and the plan did not write |
| RBS / Steep typing | Twenty-five new mirrors and two widened (`bounded_map.rbs`, `instrumentation/keys.rbs`), the strict target green with no relaxation; the two interfaces the scan needs typed `_CnonceSource & Object` and `_KeyCredential & Object` where the constructor calls `respond_to?` (5c's `& Object` device); the stamper and the hook `untyped` because a lambda is a valid value for either and `Registry.callable?` validates the arity |
| Minitest conventions | Every suite subclasses `DexpaceTestCase`, every "never raises" claim is asserted on the value (`assert_kind_of(Array, parse(input))`), `assert_same` wherever identity is the claim (the unclosed 401 IS the original), a test helper named `dispatch` rather than `run` (which shadows `Minitest::Test#run`), eight suites split into nested classes under `Metrics/ClassLength`, no `#inspect` containing a Hash asserted |
| Fiber scheduler, thread safety | Three `Thread::Mutex`es in the phase: the map's (held across read-yield-write, the one caller-block-under-lock in the tree, its contract on the method), the sync stamper's (held across the fetch, XCUT-12's sanctioned exception, stated at the call site), the async stamper's (held across a flag flip and never across the fetch, R12); the hot paths lock-free; no thread started in `lib/`, no wait, no `#value`, no `Async.delay`; every test thread joined |
| Resilience: retry, redirect and authentication | Every `AUTH` rule in the group restates a clause implemented above; the three `RETRY`/`REDIR` rules that mention `AUTH-31` and `AUTH-29` (`attach_suppressed` shared by both retry stacks; the marker's writer) are 6a's and 6b's, and 6c neither consumes nor duplicates them |

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate. Items
1–18 are where the built tree overrode the plan's assumptions, in the order the brief's as-built list
gives them; 19–28 are this build's; 29 and 30 are review round 0's and 31 and 32 review round 1's
(both 2026-09-18). The ones that touch public behaviour, the contract a later phase cites, or a
statement the design makes are also the as-built ledger rows P6-71–P6-85.

1. **The base is `main` at `f1fe848`**, and phase 6a's tree was neither read nor consumed: no
   `Resilience::Resend`, no `Cursor#bundle`. `AUTH-31` calls `request.body&.replayable?` directly, as the
   design's Independence section said, and the steps ship their own `logger:` keyword.
2. **`ForkingProbe`'s API is the built one** — `ForkingProbe.new(times:, state_per_drive:)` installed at
   `Stages::REDIRECT`, never the plan's `cursor_for`/`cross_origin_cursor_for`/`fork_count` — and every
   drive-path test runs through a real pipeline because only the driver makes a forkable cursor; the
   root `Cursor.build` is used for the HTTPS guard and the direct-call `AUTH-38` test alone. "The step
   forked N times and never called its cursor" is `SpyCursor`, a recording wrapper installed as a lambda
   at the step's stage (5b's item 12).
3. **The doubles are top level, one class per file, and the existing ones were reused**: `FakeBody` is
   the plan's `NonReplayableBody`, `FakeTransport`, `FakeAsyncTransport`, `FakeClock`, `FakeResponseBody`
   (whose `#closes` is how "closed" is asserted; `Response` has no `#closed?`) and `RecoveryFixtures`'
   builders. The plan's per-suite `async_provider`/`sync_only_provider`/`scripted_provider`/
   `CountingProvider`/`FixedCnonce` helpers became `ScriptedBearerProvider`, `ScriptedAsyncBearerProvider`
   and `FixedCnonce`; the scripted transport is `SequencedTransport` to avoid 6a's `ScriptedTransport`
   file. Task 1's scratch script SHIPS as `matrix_facts_test.rb`, on 5a's, 5b's and 5c's precedent.
4. **The three `Auth::` errors are filed under `lib/dexpace/auth/`**, one file each, because the constant
   path decides the file path (phase 2's `serde/` errors), and `AuthResolutionError` stays flat under
   `error/`; every error is `< ::StandardError; include Dexpace::Error`, since `Dexpace::Error` is a
   module and the plan's `< Error` fences are a `TypeError`; every message names the field and the
   encoding and never the value.
5. **Phase 1's API as built**: `Headers#[]` returns a list, so single-valued headers are read with
   `.first` and a repeated `WWW-Authenticate` is joined with `", "` before it reaches the hook;
   `Request::Builder#header` appends, so every stamper and the hook adapter SET the header through
   `request.with(headers: request.headers.new_builder.set(name, value).build)` and a re-stamp replaces;
   `Request.build` needs `headers:`; `with(body:)` on a POST for the body tests; HTTP-18's grammar refuses
   RFC 7616 §3.9.1's quoted `Jäsøn Doe`, which is P6-76.
6. **The async pivot as built**: `Future#then` exists and is used (never `then_map`); `Settlement#success?`,
   `#response`, `#error`, `#cancelled`; `Completer#fulfil(nil)` raises, so the wrapper fails a nil token
   instead; `#on_settle` runs inline on a settled future, so the fetch is started outside the lock
   (guard 55) and `AsyncBearerStamper#stamp_fresh`/`#evict_if_matches` are public. The plan's two gaps
   are closed: a synchronously raising `#fetch_async` clears nothing because `BearerProvider.fetch_async`
   never raises, and `AUTH-11`'s default wrapper and `AsyncStep`'s `stamp_async` adapter are written.
   `Registry.callable?(object, arity:)` validates the stamper (1) and the hook (3).
7. **The construction pattern as 5a's review enforced it**: every public `Data` includes `Model`, has
   `.new` private, validates in `initialize`, ships a KEYWORD `.build` and derives through `Model#with` —
   `Descriptor.build(requirements:)`, `BearerToken.build(token:, expiry: nil)`,
   `PasswordCredential.build(username:, password:)`, `Challenge.build(scheme:, params: {})`; `Scheme` hides
   `.[]` too and its `#with` refuses; `Validation.non_blank!(name, value)` takes `Model.required!`'s
   order; the `AUTH-2` fixture uses `+"read"`; `BearerToken#expired?` returns a Boolean for a nil expiry.
8. **`BoundedMap#update` calls the existing private `drain`**, reopens nothing (it is added to the class
   body in the full-nesting form), and its contract is on the method: read, yield and write under the
   mutex, the block confined to in-memory state, a raising block leaving the slot as it was.
   `bounded_map.rb` gains a TRUE `test/` mirror, `bounded_map_test.rb`, and leaves the exception list;
   `DigestHandler.new(credential, preference:, cap:, cnonce_source:)` with `#hex(16)` is the constructor
   phase 9's plan pins, kept exactly.
9. **The steps are built through `.build` with `.new` private** (5b's shape), consistently across the
   two; the keyword set is `Step.build(stamper:, challenge_hook: NO_REPLACEMENT, logger: Logger::NULL)`.
   **`redactor:` is not a keyword**: the step emits no log event, so there is nothing to redact, and one
   redactor per path is the logger's (P5-95); `logger:` exists for §3.7's second disposal route on a
   superseded 401 whose close fails. `AsyncBearerStamper` takes `logger:` for `AUTH-37`'s
   log-and-continue, through `Instrumentation.diagnostic`. The credential objects' renderings are what
   `AUTH-8`'s rows are about; 5b's allow-list already omits the four credential headers.
10. **There is no `Dexpace::Auth::Replayability`** — not public, not private: the predicate is one
    private method on `Step` that `AsyncStep` inherits, which is "one implementation, two drivers" with
    no third public spelling beside 6a's `Resend.eligible?` and 6b's `replayable_body?`. The
    three-spellings duplication that remains between 6a and 6b is routed to phase 10's inbound list
    (Findings routed, below).
11. **No `Digest`, `SecureRandom` or `Random` in any `sig/` file**: `_Hasher` and `_CnonceSource` are
    interfaces (5c's `trace_id_flavour.rbs` precedent), the Steepfile is untouched (the strict target
    already checks all of `lib/` and declares `digest`, `securerandom` and `openssl`), `require "digest"`
    lives in `digest_handler.rb`, and `seam_surface_test.rb`'s pin becomes
    `%w[digest securerandom strscan time uri]` on the code branch beside the smoke suite's layer table.
12. **RuboCop's answers**: `extend self` everywhere (`Challenges`, `Resolver`, `BearerProvider`,
    `Validation`), `=> error`, every method under 25 lines and four positionals (`Computed` carries the
    Digest render's seven values, `Exchange` the async 401's four), `Naming/PredicateMethod` needed no
    disable in the end, every pattern `Regexp.new(source, timeout: 1.0).freeze` — the `.freeze` and the
    test that pins both properties on all eight are review round 0's R0-2 — and `Metrics/ClassLength`
    recorded inline with its reason on `DigestHandler` (one RFC, one class) and `AsyncStep` (one `#call`
    as continuations) — the two recorded exceptions `.rubocop.yml` prescribes; eight suites split into
    nested classes; the test helper `dispatch` because `run` is `Minitest::Test#run`.
13. **All four interpreters were installed** and the facts run on each (above); nothing was installed.
14. **Ledger numbering**: P6-1–P6-7 stand as the design numbered them; the as-built rows start at
    **P6-71**; every citation outside the design reads "6c's P6-n".
15. **`docs/first-release.md`'s two entries were verified present and cited, not re-filed**; one line of
    the first is corrected to what was built (Findings routed, below).
16. **`CLAUDE.md`'s counts are re-derived from the tree on top of `main`**, for 6c only; the lib-file
    count was counted by hand because the probe does not read it.
17. **The entry file's `# Phase 6c:` block sits after 5b's**, twenty-five lines, in dependency order, with
    the plain requires in the files that use them.
18. **Task 15's guard is `defined?(Dexpace::Redirect::Step)`** and its body was proven against a scratch
    stub both ways (the Task 15 row); the skip reason names 6b as the owner.
19. **`Scheme::ALL` is public** where `Proxy::Type`'s table is private: `AUTH-1` states the scheme set as
    a set and a caller assembling `available_schemes` needs to name "every scheme" without five
    constants; the population is still closed (`.new`, `.[]` private, `#with` refusing).
20. **`Requirement.build(scheme:)` resolves a String or Symbol through `Scheme.of`**, as `Request` resolves
    its method through `Method.of`, rather than refusing a non-`Scheme` as the plan's fence did; an
    unknown name is still refused.
21. **`PasswordCredential` requires both fields present and Strings** (HTTP-4's missing-field rule through
    `Model.required!`) and applies no blank or empty check, which is P6-3 as designed; a nil password
    would otherwise be a `NoMethodError` at the handler.
22. **`Challenge.build` is the one fold point** for the scheme and the parameter names (deviation of
    the parser's duplicate fold, removed after guard 14 survived it): a hand-built challenge and a
    parsed one meet a handler in the same shape.
23. **The parser scans an invalidly encoded value as bytes** (P6-74), keeps a valid value's tag, and
    treats `,,` as an empty list element whose following `name=value` continues the challenge — the
    RFC 7230 §7 reading of the plan's `MALFORMED_STRAY_COMMA` fixture, whose assertions hold either way.
24. **`BasicHandler` refuses a colon in the username** (P6-75) and transcodes the pair to UTF-8 before
    packing, so a Latin-1-tagged credential encodes the bytes `AUTH-14` names.
25. **`DigestHandler` matches the algorithm token case-insensitively**, declines a challenge whose realm,
    nonce or opaque the outbound grammar cannot carry, and sends a non-ASCII username as `username*`
    (P6-76); the `Computed` value and `#with(response:)` carry the seven render fields.
26. **`AsyncStep` subclasses `Step`** (5b's P5-34 shape) and adapts a `#call`-shaped stamper into a
    settled future, so `KeyStamper`, `BasicHandler` and even the sync `BearerStamper` work on the async
    runtime; the hook may return a future (P6-78); every inner future is watched through one `observe`
    that forwards a cancellation as a cancellation and cancels the inner future when the outer is
    cancelled (P6-79).
27. **`Events::AUTH_REFRESH`** is the ninth event, outside the instrumentation prefix (P6-77); 5b's
    `keys_test.rb` pin repaired on the code branch.
28. **Three uncovered lines found by the first full run** — the async step's two failure-forwarding
    branches and the Digest handler's non-credential refusal — each given a test, so the auth files are
    at 100% line coverage and the whole tree at 99.98% (the registry race branch every phase records).
29. **`DigestHandler#materialize` takes the branch's target `Encoding` and the typed failure names it**
    (review round 0's R0-3, P6-84). The plan's fence returned `string.b` on the UTF-8 branch with no
    transcoding and rescued only the Latin-1 branch; the built handler transcodes on both — a
    Latin-1-tagged `pä` under `charset=UTF-8` hashes `C3 A4`, which the fence would have hashed as `E4` —
    and round 0's tree rescued both branches into one error that always said ISO-8859-1. Now the error
    carries the encoding that failed, its reason is keyed by that name (a private `REASONS` table), and
    the UTF-8 branch also refuses a UTF-8-tagged credential with an invalid sequence, which `encode` to
    the same encoding passes through unvalidated: hashing it as it was is the silently wrong response
    R10 rejects.
30. **The nonce count is taken after the credential is materialised** (review round 0's R0-4). Round 0's
    `compute` took `next_count` while building `Computed` and hashed afterwards, so `AUTH-21`'s raise
    consumed an `nc`; the design's own `authorization_for` fence materialises first, and the built method
    now does too. Not a departure from the plan but a return to it, recorded because the round found the
    built order reversed.
31. **The two encoding failures carry no `#cause`, and `BasicHandler`'s is typed** (review round 1's
    R1-3, P6-85). The design's `R10` set `#cause` to the rescued `Encoding::UndefinedConversionError`
    "because it is free and consistent", the plan's fence did the same, and round 1 found that error's
    message naming the offending character of the password (`U+65E5`) — rendered by `#full_message` on
    every supported Ruby, which round 0's clean-`message`/`detailed_message`/`inspect` checks did not
    reach. Both raises in `DigestHandler#materialize` now spell `cause: nil` and
    `UnencodableCredentialError` takes a third keyword, `source_encoding:`, carrying the value's own tag
    and naming it in the message; `BasicHandler`, which the plan had transcode the joined pair in one
    `encode` and let the bare conversion error escape at construction, transcodes each field under its
    own name and refuses one UTF-8 cannot carry as an `InvalidArgumentError` naming the field and the
    two encodings, `cause: nil` — the class comment's "the original left as the `cause`" rule yielding to
    `AUTH-8` for a credential. `docs/knowledge/notes/error-handling.md` narrows the styleguide's rule.
32. **The async step checks a hook future's settled value inside the frame that closes the 401**
    (review round 1's R1-1). The plan's fence, and round 1's tree, validated the settled value in the
    settlement callback itself, so a future fulfilling with a non-request failed the step's future with
    the 401 open — the one `AUTH-32` shape neither the class comment nor the AUTH-32 row excluded.
    `Step#consult`'s rescue became one private `closing_on_error(response)` frame, `AsyncStep` overrides
    `consult` (the future pass-through) instead of `replacement!` (now strict everywhere, a future of a
    future included), and the settled value goes through the same frame. A refactor of a private
    method on both runtimes, no surface change, no ledger row: P6-78's statement holds as written.

## Findings routed

- **The design's two findings were verified at their owner, `docs/first-release.md`, and not
  re-filed**: the `AuthDescriptor` carrier under § Blockers before first publish ("Release-gated since
  2026-09-13; this line owns the decision") and the query-/cookie-carried `apiKey` under § What v1
  ships without ("Added 2026-09-13 by phase 6c's final review"). **One phrase of the first is corrected
  to what was built**: it said the step accepts "an already-resolved credential (or a caller-supplied
  `Scheme => credential` table)"; as built `Step.build` takes one `stamper:` and no table, the
  resolver's output is threaded by whoever assembles the pipeline, and the line now says so. Nothing
  else in the file changes.
- **New, routed to phase 10's inbound list** as audit work against already-planned phases: the
  replayability predicate now has three spellings after phase 6 — 6a's `Resilience::Resend.eligible?`,
  6b's `Resend.replayable_body?` and 6c's private `Step#replayable?` — two of them public and
  NFR-4-locked; phase 10's consolidation decides whether one public predicate serves all three call
  sites (`RETRY-5`, `REDIR-6`, `AUTH-31`). Referred to by date and content, never by ordinal.
- **New, filed under `docs/knowledge/notes/error-handling.md`** after review round 1 as a narrowing
  of the styleguide's "the `cause:` passed on rethrow must be the original exception object"
  (`error-handling/866b8ebe`): a wrap whose original is a Ruby conversion error over a secret carries
  no cause, because the original's message names a character or byte of the input and `#full_message`
  renders the chain; the field and the encodings are named instead (P6-85). A later serde decoder or
  transport re-validation over credential material meets the same rule.
- **New, filed under `docs/knowledge/notes/authentication.md`** as a correction the corpus cannot
  state: the harvested `AUTH-8` conclusion says a credential "overrides both `#inspect` and `#to_s`"
  because interpolation calls one and a debugger the other, and that is one rendering short — `pp`
  gives a `Data` its own `#pretty_print`, which walks the members and never calls `#inspect`, on every
  supported Ruby (P6-72). A phase-7 or downstream value type carrying a secret meets the same gap.
- **6b's un-guarding of Task 15** is 6b's brief's, stated here so the skip is not read as a gap.
- **The design's ledger** gains an "As built" addendum (P6-71–P6-85); the consolidation of P6-1–P6-7 and
  P6-71–P6-85 into design §10 and the §6.3 addendum are a human's, as for 3a, 3b, 4a, 4b, 4c, 5a, 5b
  and 5c, because `docs/sdk-design-ruby/` is frozen. §6.3's `Step.new(…)` spelling and its
  "raise a bare error" reading of `AUTH-21`'s branch are honoured in substance by `.build` and the typed
  failure, and no frozen sentence is contradicted, so `docs/first-release.md`'s `C1`–`C14` paragraph
  gains no `C15`.

## Postponed work

**None.** Every one of the thirty-eight `AUTH` IDs is implemented in full — `AUTH-29`'s stripping clause
satisfied by construction and not deferred, since nothing was added to strip — and 6c carries no ⏳
row, as the charter said it would. **What earlier phases postponed here has landed**: phase 4a's
forward-table addition, `BoundedMap#update` (the `AUTH-19` and `XCUT-14` rows). **What this phase
leaves to others, none of it its own to defer**: the end-to-end cross-origin test's un-guarding (6b,
the Task 15 row); the `Cursor` context-bundle widening (6a's Task 8, consumed if present and not
present on this base, so the steps read no `Cursor#bundle`); the `AuthDescriptor` carrier and the
non-header `apiKey` (release decisions, `docs/first-release.md`); the wire-boundary re-validation of
the stamped `Authorization` and `Proxy-Authorization` values (phase 8a Task 16, phase 8c Task 9, phase
9 Task 7); the three-spellings predicate (phase 10). The context store's configured cap does not extend
to `AUTH-19`'s cap (R11), and no deferral is filed in its place.
