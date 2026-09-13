# authentication

## Rules
- An auth requirement must bind exactly one scheme to its own OAuth scopes and params, meaningful only for OAUTH2 and never inspected by resolution but preserved, must be immutable so input collections mutated after construction do not affect the stored value, and must have value-based equality over scheme, scopes, and params. (AUTH-1, AUTH-2, AUTH-3)
  <sub>spec · `docs/product-spec/11-authentication.md:7-7` · high · sha:efba58233dd1</sub>
- An auth descriptor must be a non-empty ordered list of requirements in preference order, must reject an empty list at construction, must be immutable, and must report "allows anonymous" as true if and only if any requirement's scheme is NO_AUTH. (AUTH-1, AUTH-2, AUTH-3)
  <sub>spec · `docs/product-spec/11-authentication.md:7-7` · high · sha:efba58233dd1</sub>
- Auth tier resolution must select the single most-specific descriptor present, in the strict order per-call, then operation, then client, and resolve only against that descriptor; a higher tier that is present but unsatisfiable must not fall through to a lower tier, because the caller explicitly asked for that override. (AUTH-4, AUTH-5, AUTH-6, AUTH-7)
  <sub>spec · `docs/product-spec/11-authentication.md:8-8` · high · sha:efba58233dd1</sub>
- Within the selected auth descriptor, resolution must return the first requirement in declared order whose scheme is satisfiable, where satisfiable means NO_AUTH (always satisfiable) or membership in the supplied set of available schemes, without inspecting any concrete credential. (AUTH-4, AUTH-5, AUTH-6, AUTH-7)
  <sub>spec · `docs/product-spec/11-authentication.md:8-8` · high · sha:efba58233dd1</sub>
- Auth resolution must fail with an argument error when all tiers are absent, and with a distinct auth-resolution error carrying the required schemes in preference order and the available schemes when the selected descriptor lists no satisfiable scheme. (AUTH-4, AUTH-5, AUTH-6, AUTH-7)
  <sub>spec · `docs/product-spec/11-authentication.md:8-8` · high · sha:efba58233dd1</sub>
- Every credential type must redact its secret in any string or diagnostic representation without mutating or corrupting the real fields, may leave non-secret fields visible, and must preserve its variant-specific equality: the bearer token has value-based equality over its real token and expiry, while API-key and name-key credentials use reference identity so two instances with identical fields are not equal. (AUTH-8, AUTH-9, AUTH-10, AUTH-11)
  <sub>spec · `docs/product-spec/11-authentication.md:12-12` · high · sha:efba58233dd1</sub>
- Credential construction must validate secret and identity fields as non-blank and reject blanks, for the bearer token, the API key, and the name-key's name and key. (AUTH-8, AUTH-9, AUTH-10, AUTH-11)
  <sub>spec · `docs/product-spec/11-authentication.md:12-12` · high · sha:efba58233dd1</sub>
- A token provider's fetch errors must propagate and must not be cached, so a subsequent request retries, and async callers must observe a provider error through the asynchronous channel — a failed future — never a synchronous throw. (AUTH-8, AUTH-9, AUTH-10, AUTH-11)
  <sub>spec · `docs/product-spec/11-authentication.md:12-12` · high · sha:efba58233dd1</sub>
- The challenge parser must be lenient and never throw: blank input yields an empty list, a malformed challenge recovers to the next top-level comma, an unterminated quoted string terminates at end-of-input, and parameters parsed before a malformed tail are preserved. (AUTH-12, AUTH-13)
  <sub>spec · `docs/product-spec/11-authentication.md:16-16` · high · sha:efba58233dd1</sub>
- Digest stamping must support exactly the algorithms {MD5, MD5-sess, SHA-256, SHA-256-sess} with qop "auth" or absent, declining auth-int-only challenges, unsupported algorithms, and mutual-auth verification. (AUTH-15, AUTH-22, AUTH-16, AUTH-17, AUTH-18, AUTH-20, AUTH-21, AUTH-19)
  <sub>spec · `docs/product-spec/11-authentication.md:18-18` · high · sha:efba58233dd1</sub>
- A Digest challenge is considered satisfiable if and only if the scheme is Digest (case-insensitive), it carries realm and nonce, qop contains "auth" or is absent, and the algorithm is supported or absent (defaulting to MD5), preferring the algorithm earliest in the configured preference list regardless of wire order. (AUTH-15, AUTH-22, AUTH-16, AUTH-17, AUTH-18, AUTH-20, AUTH-21, AUTH-19)
  <sub>spec · `docs/product-spec/11-authentication.md:18-18` · high · sha:efba58233dd1</sub>
- Digest stamping must track the nonce count per server nonce, starting at 00000001 and incrementing only on reuse, rendered as exactly 8 lower-case hex digits using the low 32 bits on overflow. (AUTH-15, AUTH-22, AUTH-16, AUTH-17, AUTH-18, AUTH-20, AUTH-21, AUTH-19)
  <sub>spec · `docs/product-spec/11-authentication.md:18-18` · high · sha:efba58233dd1</sub>
- Digest stamping must use UTF-8 hash-input encoding when the challenge advertises charset=UTF-8, and ISO-8859-1 otherwise. (AUTH-15, AUTH-22, AUTH-16, AUTH-17, AUTH-18, AUTH-20, AUTH-21, AUTH-19)
  <sub>spec · `docs/product-spec/11-authentication.md:18-18` · high · sha:efba58233dd1</sub>
- Digest stamping must quote/escape the appropriate fields, leave qop/nc/algorithm unquoted with the full algorithm spelling, use the request-target as the digest-uri, and emit cnonce/nc/qop only when qop is negotiated. (AUTH-15, AUTH-22, AUTH-16, AUTH-17, AUTH-18, AUTH-20, AUTH-21, AUTH-19)
  <sub>spec · `docs/product-spec/11-authentication.md:18-18` · high · sha:efba58233dd1</sub>
- The per-nonce Digest counter store should be bounded, defaulting to 1024 entries, and drained under the cap; evicting a live nonce is harmless because its nonce count restarts at 1, which is spec-legal for a fresh nonce. (AUTH-15, AUTH-22, AUTH-16, AUTH-17, AUTH-18, AUTH-20, AUTH-21, AUTH-19)
  <sub>spec · `docs/product-spec/11-authentication.md:18-18` · high · sha:efba58233dd1</sub>
- Composing auth handlers must delegate to the first handler in declaration order whose can-handle check passes, and must defensively copy the handler list, with callers expected to order stronger schemes first. (AUTH-23, AUTH-24, AUTH-25, AUTH-26)
  <sub>spec · `docs/product-spec/11-authentication.md:19-19` · high · sha:efba58233dd1</sub>
- Auth handlers must be safe for concurrent invocation, with per-handler mutable counters, such as the Digest nonce count, using thread-safe primitives so concurrent reuse of one nonce still yields correct, non-duplicated counts. (AUTH-23, AUTH-24, AUTH-25, AUTH-26)
  <sub>spec · `docs/product-spec/11-authentication.md:19-19` · high · sha:efba58233dd1</sub>
- An auth handler must emit an Authorization header for WWW-Authenticate challenges and a Proxy-Authorization header for Proxy-Authenticate challenges, selected by an explicit proxy flag, and must return no header when it cannot satisfy any offered challenge. (AUTH-23, AUTH-24, AUTH-25, AUTH-26)
  <sub>spec · `docs/product-spec/11-authentication.md:19-19` · high · sha:efba58233dd1</sub>
- Static key-credential stamping must write the key into the configured header, defaulting to Authorization, and when a prefix is configured must prepend it followed by a single space, with the stamping step stateless after construction. (AUTH-23, AUTH-24, AUTH-25, AUTH-26)
  <sub>spec · `docs/product-spec/11-authentication.md:19-19` · high · sha:efba58233dd1</sub>
- On any path where a credential will be attached, the auth step must reject a non-HTTPS request URL, case-insensitively, before any token fetch or header stamping, failing with an error naming the concrete step and the offending scheme, because credentials must not be stamped over plaintext. (AUTH-27, AUTH-28)
  <sub>spec · `docs/product-spec/11-authentication.md:23-23` · high · sha:efba58233dd1</sub>
- On a cross-origin redirect re-issue, defined by a differing scheme, host, or effective port under the RFC 6454 tuple, the auth step must not stamp the caller's credential, must strip the internal cross-origin marker so it never reaches the wire, and must skip the HTTPS guard so a deliberately-allowed downgrade hop is forwarded credential-free rather than hard-failing, whereas a same-origin re-issue must be re-stamped normally and remains subject to the HTTPS guard. (AUTH-29)
  <sub>spec · `docs/product-spec/11-authentication.md:24-24` · high · sha:efba58233dd1</sub>
- On a 401 response carrying a WWW-Authenticate header, the auth step must consult its challenge hook, and if the hook yields a non-null replacement request, the step must close the original 401 and drive the replacement through a fresh copy of the downstream chain exactly once, with no further challenge handling on the replacement; the default hook yields no replacement. (AUTH-30, AUTH-33, AUTH-32)
  <sub>spec · `docs/product-spec/11-authentication.md:25-25` · high · sha:efba58233dd1</sub>
- A 401 response without a WWW-Authenticate header must be returned unchanged without consulting the challenge hook. (AUTH-30, AUTH-33, AUTH-32)
  <sub>spec · `docs/product-spec/11-authentication.md:25-25` · high · sha:efba58233dd1</sub>
- If the challenge hook throws, or its async future completes exceptionally, or the async hook throws synchronously, the auth step must close the open 401 response body before propagating. (AUTH-30, AUTH-33, AUTH-32)
  <sub>spec · `docs/product-spec/11-authentication.md:25-25` · high · sha:efba58233dd1</sub>
- The 401 re-challenge replay must be gated on request-body replayability: if the replacement request carries a non-replayable body, the auth step must skip the replay, surface the original 401 unchanged, and must not close that original response, since the caller owns it. (AUTH-31)
  <sub>spec · `docs/product-spec/11-authentication.md:26-26` · high · sha:efba58233dd1</sub>
- The bearer auth step must stamp "Authorization: Bearer <token>" using a token cached until a configurable refresh margin before expiry, defaulting to 30 seconds, ensuring concurrent requests racing on a missing or expiring token result in at most one provider fetch via single-flight, with a non-blocking hot-path read of a valid cached token. (AUTH-34, AUTH-37, AUTH-35, AUTH-36, AUTH-38)
  <sub>spec · `docs/product-spec/11-authentication.md:27-27` · high · sha:efba58233dd1</sub>
- The bearer auth step must reject a null token and a token already expired at fetch time, evaluated with no margin, and must not cache a thrown provider error. (AUTH-34, AUTH-37, AUTH-35, AUTH-36, AUTH-38)
  <sub>spec · `docs/product-spec/11-authentication.md:27-27` · high · sha:efba58233dd1</sub>
- On a 401 advertising a Bearer challenge, the bearer auth step must evict only the exact cached token that produced the 401, matched by the stamped header value, and re-stamp a single retry with a freshly fetched token, preserving a token another request already refreshed, surfacing the 401 unchanged when the rejected request carried no Authorization header or the response advertises no Bearer challenge, and firing the eviction-driven retry regardless of HTTP method. (AUTH-34, AUTH-37, AUTH-35, AUTH-36, AUTH-38)
  <sub>spec · `docs/product-spec/11-authentication.md:27-27` · high · sha:efba58233dd1</sub>
- The async bearer auth step must implement a three-zone expiry policy without blocking the dispatching thread: fresh tokens are stamped with no refresh; expiring-but-valid tokens are stamped immediately while an off-thread background refresh is kicked off; and expired-or-missing tokens await a fresh single-flight fetch, coalescing concurrent expiring/missing requests onto one fetch, never caching a failed fetch, and treating a failed background refresh as non-fatal since a valid token was already stamped. (AUTH-34, AUTH-37, AUTH-35, AUTH-36, AUTH-38)
  <sub>spec · `docs/product-spec/11-authentication.md:27-27` · high · sha:efba58233dd1</sub>
- In the async auth path, HTTPS-guard failures and any challenge-hook errors should be delivered through the asynchronous channel — a failed future — rather than synchronously thrown. (AUTH-34, AUTH-37, AUTH-35, AUTH-36, AUTH-38)
  <sub>spec · `docs/product-spec/11-authentication.md:27-27` · high · sha:efba58233dd1</sub>
- `BearerToken.token`, `KeyCredential.apiKey`, and `NamedKeyCredential.name` and `key` must all be non-blank, with blanks rejected via a validation error, where non-blank means `nil`, an empty string, and a whitespace-only string are all rejected. (AUTH-9)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:144-147` · high · sha:d21cb737a231</sub>
- Every credential type overrides both `#inspect` and `#to_s` to satisfy the redact-in-string-form requirement, since Ruby interpolation calls `#to_s` and a debugger calls `#inspect`. (AUTH-8)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:151-153` · high · sha:d21cb737a231</sub>
- The challenge parser must handle multiple comma-separated challenges, quoted strings containing commas and equals signs, backslash escapes, a bare scheme with an empty parameter map, and a token68 value under a synthetic key, must never raise, must recover to the next top-level comma on a malformed challenge, and must terminate an unterminated quoted string at end of input. (AUTH-12, AUTH-13)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:157-160` · high · sha:d21cb737a231</sub>
- Auth-handler composition delegates to the first handler in declaration order whose can-handle check passes, and takes a defensive copy of the handler list at construction so a caller who later mutates the array they passed cannot reorder the preference. (AUTH-23)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:165-168` · high · sha:d21cb737a231</sub>
- Ordering of auth handlers is the caller's responsibility, documented as stronger schemes first (Digest before Basic), because a server offering both is answered by the first match and not by the strongest.
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:168-170` · high · sha:d21cb737a231</sub>
- The header name an auth handler emits is selected by an explicit proxy flag rather than by inspecting the challenge or the status: `Authorization` for a `WWW-Authenticate` challenge and `Proxy-Authorization` for a `Proxy-Authenticate` one. (AUTH-25)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:170-172` · high · sha:d21cb737a231</sub>
- A handler that cannot satisfy any offered challenge returns nil rather than an empty header, letting composition fall through cleanly and preventing a failed negotiation from putting a malformed Authorization header on the wire. (AUTH-25)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:172-174` · high · sha:d21cb737a231</sub>
- `SecureRandom.hex(16)` supplies the 128-bit Digest client nonce, a CSPRNG draw, and `Random` is never used for this purpose. (AUTH-20, XCUT-21, AUTH-18)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:189-191` · high · sha:d21cb737a231</sub>
- The per-nonce counter for Digest authentication increments under a `Thread::Mutex` so that concurrent reuse of one server nonce still yields correct, non-duplicated counts. (AUTH-20, XCUT-21, AUTH-18, AUTH-24, AUTH-19, XCUT-14)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:191-193` · high · sha:d21cb737a231</sub>
- A decoded Basic credential must be non-empty and must contain a colon, and a decoded value of any fixed-width form must be checked against its expected byte length before use, since the empty-string test alone is insufficient.
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:207-210` · high · sha:d21cb737a231</sub>
- The HTTPS guard on the AUTH pillar step fires before any token fetch or header write on every credential-attaching path. (AUTH-27, AUTH-33, AUTH-28, XCUT-16)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:212-214` · high · sha:d21cb737a231</sub>
- The 401 re-challenge drives the credential replacement through a fresh fork exactly once with no further challenge handling. (AUTH-29, AUTH-30)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:215-216` · high · sha:d21cb737a231</sub>
- A 401 response without a `WWW-Authenticate` header is returned unchanged, and an open 401 body is closed if the auth hook raises. (AUTH-30, AUTH-33, AUTH-32, AUTH-31)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:216-218` · high · sha:d21cb737a231</sub>
- On both the sync and async auth paths, the replay is skipped and the original 401 is surfaced unclosed when the replacement request body is not replayable. (AUTH-33, AUTH-32, AUTH-31)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:217-219` · high · sha:d21cb737a231</sub>

## Constraints
- A port of the authentication model must preserve the security invariants of never leaking credentials over plaintext or cross-origin, an unpredictable Digest cnonce, and secret redaction, along with the deterministic resolution semantics and the exact challenge/retry lifecycle.
  <sub>spec · `docs/product-spec/11-authentication.md:3-3` · high · sha:efba58233dd1</sub>
- The auth resolver must be stateless, concurrency-safe, and a deterministic pure function of its inputs. (AUTH-4, AUTH-5, AUTH-6, AUTH-7)
  <sub>spec · `docs/product-spec/11-authentication.md:8-8` · high · sha:efba58233dd1</sub>
- Digest stamping must draw the client nonce (cnonce) from a cryptographically strong source with at least 128 bits of entropy. (AUTH-15, AUTH-22, AUTH-16, AUTH-17, AUTH-18, AUTH-20, AUTH-21, AUTH-19)
  <sub>spec · `docs/product-spec/11-authentication.md:18-18` · high · sha:efba58233dd1</sub>
- There must be exactly one auth step occupying the single AUTH pillar stage, running nested inside both the redirect loop and the retry loop, so auth executes per redirect hop and per retry attempt with redirect wrapping retry wrapping auth. (AUTH-27, AUTH-28)
  <sub>spec · `docs/product-spec/11-authentication.md:23-23` · high · sha:efba58233dd1</sub>
- The auth suppression mechanism for cross-origin redirects must only be able to suppress credential stamping, never force a credential to be sent. (AUTH-29)
  <sub>spec · `docs/product-spec/11-authentication.md:24-24` · high · sha:efba58233dd1</sub>
- The per-nonce counter store is bounded at 1024 entries with drain-to-cap eviction. (AUTH-19, XCUT-14)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:193-193` · high · sha:d21cb737a231</sub>
- `Base64.strict_encode64` is forbidden in core because `base64` became a bundled gem in Ruby 3.4, so `require "base64"` from a gem that has not declared the dependency fails under Bundler on a supported Ruby.
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:196-198` · high · sha:d21cb737a231</sub>
- On mixed input, `String#unpack1("m")` silently decodes whatever valid base64 subset it finds and discards the rest, so a caller that tests only for an empty result would accept non-empty garbage, and there is no error channel to check instead.
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:204-207` · high · sha:d21cb737a231</sub>

## Conclusions
- Credential blank-value validation runs inside the `Data` subclass's `initialize` override alongside the required-field guard, so there is no construction path that skips it.
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:148-149` · high · sha:d21cb737a231</sub>
- The variant-specific equality split, value equality for the bearer token and reference identity for the key credentials, is expressed by making the bearer token a `Data` class and the key credentials plain classes that do not define `==`, so Ruby's default identity equality applies to them without any code being written.
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:153-156` · high · sha:d21cb737a231</sub>
- The challenge parser is written as a character-level state machine rather than a regexp, because the challenge grammar is not regular and a hostile `WWW-Authenticate` header should not be able to drive a backtracking regex engine.
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:160-162` · high · sha:d21cb737a231</sub>
- The port uses `Digest::MD5` and `Digest::SHA256` for all four Digest authentication algorithms, so Digest authentication keeps working in a FIPS deployment and no MD5 implementation needs vendoring, which is also the zero-dependency choice.
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:187-189` · high · sha:d21cb737a231</sub>
- Core uses `[credentials].pack("m0")` instead of `Base64.strict_encode64`, verified to produce identical output, since it is a core `String`/`Array` method with no library dependency behind it.
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:198-200` · high · sha:d21cb737a231</sub>
- The HTTPS guard is deliberately skipped on a cross-origin re-issue where no credential will be attached, so a permitted downgrade hop is forwarded credential-free rather than hard-failing. (XCUT-16, AUTH-29)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:213-215` · high · sha:d21cb737a231</sub>
- The bearer-token step's hot path reads one frozen token object from an instance variable without taking a lock, with refresh serialised under a per-credential `Thread::Mutex`, and the read is safe by publication (written only under the lock) rather than by relying on the GVL, so it holds correctly on JRuby and TruffleRuby too. (AUTH-34, XCUT-12, AUTH-37)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:219-222` · high · sha:d21cb737a231</sub>
- A credential provider returning nil is surfaced to the caller as an error rather than producing a silently unauthenticated request, because the alternative failure mode is an unexplained 401 from the server with no indication that the SDK is what dropped the credential. (AUTH-35)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:227-230` · high · sha:d21cb737a231</sub>
- A credential provider returning a token already expired at fetch time is an error, evaluated with no refresh margin, because applying the refresh margin here would reject a token merely close to expiry, which is a legitimate thing for a provider to return.
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:230-233` · high · sha:d21cb737a231</sub>
- A credential provider that raises has its exception propagate and its result is not cached, so the next request retries the fetch rather than inheriting a poisoned slot, meaning the memoisation write happens only after the provider returns successfully and never inside an ensure block.
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:233-236` · high · sha:d21cb737a231</sub>

## Reference
- Authentication in the SDK has two largely independent halves — a scheme-agnostic descriptor/resolver model that decides which auth alternative an operation requires, and a stamping/challenge half that puts credentials on the wire and reacts to server challenges.
  <sub>spec · `docs/product-spec/11-authentication.md:3-3` · high · sha:efba58233dd1</sub>
- The recognized authentication scheme set is exactly {OAUTH2, API_KEY, BASIC, DIGEST, NO_AUTH}, where NO_AUTH is a distinct sentinel meaning "may run anonymously / skip credential stamping" rather than a wire scheme. (AUTH-1, AUTH-2, AUTH-3)
  <sub>spec · `docs/product-spec/11-authentication.md:7-7` · high · sha:efba58233dd1</sub>
- 401 eviction/refresh matching for credentials is done on the stamped header string rather than credential equality, so value equality is not required for API-key and name-key credentials. (AUTH-8, AUTH-9, AUTH-10, AUTH-11)
  <sub>spec · `docs/product-spec/11-authentication.md:12-12` · high · sha:efba58233dd1</sub>
- Bearer-token expiry is optional, with null meaning never locally expires, and is evaluated additively with a grace margin: a token is expired at reference time "now" with margin M if and only if its expiry is non-null and "now + M" is strictly after the expiry. (AUTH-8, AUTH-9, AUTH-10, AUTH-11)
  <sub>spec · `docs/product-spec/11-authentication.md:12-12` · high · sha:efba58233dd1</sub>
- The challenge parser parses RFC 7235 WWW-Authenticate/Proxy-Authenticate header values into an ordered list of challenges, honoring multiple comma-separated challenges, quoted-string values containing commas and equals signs, backslash escapes, scheme/param names normalized to lower case, values stored verbatim after unquoting, a bare scheme emitted with an empty parameter map, and a token68 value recorded under a synthetic key. (AUTH-12, AUTH-13)
  <sub>spec · `docs/product-spec/11-authentication.md:16-16` · high · sha:efba58233dd1</sub>
- Basic auth stamping produces "Basic " followed by base64 of the UTF-8 encoding of "username:password", computed once, accepts a Basic challenge case-insensitively, emits an Authorization header (or Proxy-Authorization for a proxy challenge), and validates credentials as non-empty, permitting whitespace-only per RFC 7617, which is laxer than the non-blank rule elsewhere. (AUTH-14)
  <sub>spec · `docs/product-spec/11-authentication.md:17-17` · high · sha:efba58233dd1</sub>
- Digest stamping computes HA1/HA2/response per RFC 7616/2069 using lower-case hex of the selected algorithm. (AUTH-15, AUTH-22, AUTH-16, AUTH-17, AUTH-18, AUTH-20, AUTH-21, AUTH-19)
  <sub>spec · `docs/product-spec/11-authentication.md:18-18` · high · sha:efba58233dd1</sub>
- In the reference implementation, the replayability gate on 401 re-challenge replay is enforced on the synchronous auth step only; the async auth step does not currently apply a replayability gate and closes the original 401 before re-driving unconditionally, and a faithful port should apply the same gate on both paths. (AUTH-31)
  <sub>spec · `docs/product-spec/11-authentication.md:26-26` · high · sha:efba58233dd1</sub>
- An auth challenge is a parsed RFC 7235 WWW-Authenticate / Proxy-Authenticate directive consisting of a scheme plus a parameter map that a server returns on a 401/407 to indicate how a client may authenticate.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:7` · high · sha:f0b3d2058626</sub>
- The 401 replayability gate applies on both the sync and async auth paths through one `Dexpace::Resilience::Resend.eligible?(request)` predicate located under `resilience/` per the project layout. (AUTH-31, BODY-4, BODY-5, REDIR-6, RETRY-5)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:147-149` · high · sha:6b7ebc1dfd1d</sub>
- The same `Dexpace::Resilience::Resend.eligible?(request)` predicate is also consulted for BODY-4, BODY-5, REDIR-6, and RETRY-5.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:148-149` · high · sha:6b7ebc1dfd1d</sub>
- MD5 and MD5-sess must be supported alongside SHA-256 and SHA-256-sess for Digest authentication because RFC 7616 still mandates MD5 for interoperability with servers that have not adopted SHA-256. (AUTH-15, AUTH-22)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:176-178` · high · sha:d21cb737a231</sub>
- `Digest::MD5`, from Ruby's `digest` default gem, bundles its own implementation and does not route through OpenSSL's EVP layer, while `OpenSSL::Digest::MD5` does and therefore fails on a FIPS-enabled OpenSSL build where MD5 is not an approved algorithm.
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:178-182` · high · sha:d21cb737a231</sub>
- The FIPS-related MD5 divergence claim could not be reproduced on the authoring machine, since no FIPS-enabled OpenSSL build was available and both routes succeed on a normal Ruby 3.4.10, so the claim rests on published behaviour (GitLab's omnibus packaging FIPS work replacing `OpenSSL::Digest` MD5 calls with stdlib `Digest::MD5`) rather than direct verification.
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:181-187` · low · sha:d21cb737a231</sub>
- Basic authentication requires the header value `Basic ` followed by the base64 encoding of the UTF-8 bytes of `username:password`. (AUTH-14)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:195-196` · high · sha:d21cb737a231</sub>
- `String#unpack1("m")`, used for Basic-credential decoding, never raises on any input on Ruby 3.4.10, and returns an empty string only when the input contains no valid base64 characters at all.
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:202-205` · high · sha:d21cb737a231</sub>
- The async bearer-token policy has three zones: stamp when fresh, stamp and kick off a background refresh when expiring-but-valid, and await a coalesced single-flight fetch when expired, implemented using the pivot's `#on_settle`. (AUTH-37)
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:222-224` · high · sha:d21cb737a231</sub>
- A failed background token refresh is non-fatal because a valid token was already stamped on the request.
  <sub>design · `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md:224-225` · high · sha:d21cb737a231</sub>

## Conflicts

## Superseded
