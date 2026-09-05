## 6. Retry, Redirect, and Authentication

### 6.1 Retry

**Single-sourcing is structurally guaranteed.** **HTTP-9**/**RETRY-6**'s idempotent set `{GET, HEAD, OPTIONS, PUT,
DELETE}`, **RETRY-1**'s retryable-status classifier (408, 429, and all of 500–599 except 501 and 505),
**XCUT-7**'s default configurable set `{408, 429, 500, 502, 503, 504}`, and **RETRY-13**'s shared backoff
calculator all live in one `Dexpace::Resilience::Policy` module as frozen constants and pure functions. Ruby
constants are process-global and `require` de-duplicates by resolved path, so — unlike a platform where two
classloaders can each hold their own copy — there is no second copy that could drift. **XCUT-5** versus **XCUT-7**
is the subtlety the specification itself flags as load-bearing: the baked flag on a protocol error is computed once
at construction from the built-in classifier and is *queryable but not consulted by the retry step*, which
consults the configurable set instead. The port keeps them as two distinctly named methods (`#retryable_by_status?`
on the error, `Policy.retry_eligible?(status, set:)` on the step) precisely so a reader cannot reach for the wrong
one, and **RETRY-37**'s authoritative-contains semantics (the configured set can both widen and narrow, and is not
intersected with the baked flag) is asserted in a dedicated test.

**The open capability, and why Ruby needs no registry for it.** **XCUT-6** requires that a transport-family or
custom error type declaring itself retryable "MUST be able to participate in retry decisions without editing the
retry classifier — for such errors the classifier queries the capability (is-Retryable and the flag), not a
concrete-type match." The Ruby mechanism is the language's own: the classifier's non-protocol branch is
`error.respond_to?(:retryable?) && error.retryable?`, walked over §5.2's cycle-safe cause enumerator so a retryable
error wrapped in a generic one is still found. No registration, no marker module to include, and no concrete-type
match anywhere in the classifier — a third-party transport adapter defines `#retryable?` on its own error class and
is in, which is the whole of what the requirement asks for. The transport-error branch of **XCUT-4** gets the flag
by default (a request that never reached the server is always retryable at the error level); the protocol branch
does not consult it, per **XCUT-5**/**XCUT-7** above.

**Retry configuration validates at construction, not at first use** (**RECOV-34**). Durations must be non-negative
and representable — the reference's nanosecond ceiling has no Ruby analogue, since `Integer` is arbitrary-precision,
so the port validates against the same ~292-year bound explicitly rather than inheriting it from a type; the delay
multiplier must be at least 1.0; maximum attempts at least 1, with 1 disabling retries; and the jitter fraction
must lie in [0.0, 1.0]. The collection-valued settings — retryable statuses, retryable methods — are **duplicated
and frozen at build time**, so a caller who keeps and later mutates the array they passed cannot change the
behaviour of a running client. That copy is the same construction-time freeze §4 applies to every model collection,
and it is stated here because a config object is exactly where a port is tempted to hold the caller's array by
reference.

**Backoff** (**RETRY-9**–**RETRY-12**) is a pure function of attempt number, settings and an **injectable random
source** defaulting to a process-wide `Random`, paired with the injectable clock of **CFG-15** so that both time and
jitter are deterministically controllable in tests — pairing the two injectables is the pattern, and neither is
useful without the other. Overflow saturation (**RETRY-11**) is trivially satisfied since Ruby integers are
arbitrary-precision; the clamp to the maximum delay is what does the work, and attempt < 1 is rejected.

**Retry-After parsing needs three hand-written pieces, each because the obvious tool is wrong (P13).** Verified on
3.4.10: `Time.httpdate` is more tolerant than its reputation in one respect and strict in the two that matter. It
**is** case-insensitive on day and month names — `time.rb` compiles its RFC 2616 pattern with the `/ix` flags, and
`Time.httpdate("sun, 06 nov 1994 08:49:37 gmt")` parses to the same instant as the canonical casing — so the
lowercase-month tolerance **CFG-30** and **RETRY-15** ask for is already there. What it rejects, with
`ArgumentError: not RFC 2616 compliant date`, are the two forms those requirements also name: the **single-digit
day** (`"Sun, 6 Nov 1994 08:49:37 GMT"`) and the non-`GMT` zone spellings, both `"... 08:49:37 UTC"` and
`"... 08:49:37 +0000"`. All three verified. Those rejections are what make a hand-written parser necessary; the
casing is not, and saying so keeps the port from carrying a fold it does not need. `Time.parse` is catastrophically
permissive — it parses `"120"` and `"0x10"` into plausible-looking dates rather than failing, which is the exact
inverse of **RETRY-16**'s totality requirement that malformed input map to "no hint," never to a wrong or zero
delay. `Float("0x10", exception: false)` returns `16.0` and `Float("1_0", exception: false)` returns `10.0`, so
Ruby's numeric coercion accepts hex-float and underscore forms — precisely what **RETRY-19** demands be screened
out by a strict decimal grammar *before* any float parse. And `Integer("08", exception: false)` returns `nil`
because a leading zero selects octal, so every integer parse in the port passes base 10 explicitly. The port
therefore ships one bounded-lenient RFC 1123 parser (shared with **CFG-29**–**CFG-31**), one strict decimal screen,
and one base-10 integer helper, and forbids `Time.parse` by lint rule.

The rest of the pacing contract translates directly: a valid date or epoch already in the past yields a zero delay,
distinct from unparseable yielding no hint (**RETRY-17**); every computed delta is clamped to 365 days before
conversion (**RETRY-18**); a present hint replaces rather than augments the exponential schedule and receives no
additional symmetric jitter (**RETRY-20**); precedence differs between the two stacks exactly as **RETRY-21**
specifies; and a parse failure never masks the real upstream failure (**RETRY-22**).

**Two stacks, and why the unification sanction is not invoked.** The specification ships two cooperating retry
stacks — the recovery-chain retry with a total-timeout budget (**RETRY-27**) and the stage-based step forbidden to
impose one (**RETRY-28**) — and grants an escape to a port that unifies them, in two places whose wording differs
slightly and which are worth quoting separately rather than blending. **RETRY-28** itself
(`09-retry-and-resilience.md`) says "a port that unifies the stacks MUST make the total-timeout an explicitly
opt-in feature rather than always-on"; the pipelines chapter (`08-execution-pipelines.md`), introducing the same
tension from the layer side, says "a port unifying retry entry points MUST make that budget explicitly opt-in."
Same obligation, two scopes — the stacks, and the entry points onto them — and a port that unified only the entry
points would still be caught by the second.

This port invokes neither, and the reason is structural rather than a preference: **the port keeps both stacks
because it keeps both layers each stack belongs to.** The stage-based step is a stage-pipeline step and the
recovery retry is a recovery-chain step; §5 keeps both layers because `08-execution-pipelines.md` forbids merging
them — "A port MUST NOT collapse the two layers into one" — so there is no unification here for the sanction to
apply to. What the sanction guards against is drift between two stacks that a port kept, and that is handled
directly instead: **RETRY-13** requires both stacks to "compute their backoff via the one shared calculator using
the one shared set of constants ... the stacks MUST NOT carry independent backoff formulas or duplicated
constants," and **RETRY-14** requires their budgets to denote the same number of wire sends. Both stacks therefore
share one calculator, one classifier and one pacing parser, with **RETRY-14**'s equivalence (max-attempts 3 equals
max-retries 2 plus the initial send) asserted by test.

**The inter-attempt wait** is where **CFG-15** and **RETRY-26** pull against each other, and §8.3 resolves it. Every
other retry-loop clause translates without incident: a retryable response's body and connection are released
*before* the wait so a socket is not pinned across the delay, and the response is still closed if the retry
decision or delay computation raises (**RETRY-35**); the failed-attempt trail is attached as suppressed on terminal
failure and discarded on eventual success (**RETRY-34**, using §5.2's helper on both stacks); each attempt
re-executes the downstream chain through a fresh fork rather than reusing the prior attempt's cursor
(**RETRY-44**); and the engine never shuts down a caller-supplied scheduler (**RETRY-45**). The async loop is an
iterative pump driven by a re-arm flag rather than recursive future composition (**RETRY-30**, **RETRY-31**), which
also disposes of **PAGE-31**'s trampoline concern for the same reason; if the caller has already settled or
cancelled the returned future, no further attempt is launched and any response arriving from an in-flight attempt
is closed rather than leaked (**RETRY-32**), which is §3.3's check-after-resume rule applied at the retry layer.

### 6.2 Redirect

**REDIR-1**–**REDIR-6**'s code and method rules translate literally. **REDIR-8**'s cross-origin test — scheme,
case-insensitive host, and effective port compared against the **seed** origin, not the previous hop — is a
comparison of an explicitly constructed `[scheme.downcase, host.downcase, effective_port]` triple rather than
`URI#==`, so default-port normalisation is visible rather than delegated. **HTTP-46**'s prohibition on blocking
work or DNS resolution in URL equality is free here: Ruby's `URI` performs no resolution in comparison or hashing,
so there is no workaround to design around in the first place — the requirement is satisfied by not reimplementing
a resolving comparator. **REDIR-13**'s wire-exact preservation of an already-percent-encoded path, query and
fragment is satisfied by resolving through `URI.join`/`URI#merge` and never round-tripping through a re-rendered
string (§3.5).

**The cross-origin marker is not a header, and that is strictly stronger.** **REDIR-11** requires an out-of-band
signal telling the auth layer to skip credential stamping on a cross-origin re-issue, and imposes three conditions:
it must be impossible for a server-supplied `Location` to forge, it must only suppress stamping and never cause a
credential to be sent, and it must be removed before dispatch. The reference implements it as an internal header
cleared on every re-issue, and the requirement itself flags the resulting porter trap: "only the auth step strips
the marker, so a pipeline with no auth step ... forwards the internal marker to the transport." This port puts the
marker on the **forked per-hop cursor** instead of on the request, under §5.1's cursor-scoped state rules. A
`Location` value cannot reach cursor state, so forgery is not merely defended against but structurally impossible;
there is nothing on the request to strip, so the trap the requirement warns about cannot occur, and the "removed
before dispatch" clause is satisfied a fortiori because nothing was ever added. The two rules §5.1 states are what
carry the argument, and both depend on the stage order **REDIRECT → RETRY → AUTH**: inheritance is why a marker set
on the per-hop fork is visible to the AUTH step downstream of it, and the write restriction — only the pillar step
that created a fork may write its state — is why AUTH, which did not create it, can read the marker but cannot set
one, and why no step downstream of AUTH can either. The marker also expires correctly for free, since the next hop
is a new fork from REDIRECT and starts from REDIRECT's own state rather than the previous hop's. This changes the
mechanism, not the guarantee, and in the direction the requirement's own rationale wants (§10). The auth step reads
it through the cursor (**AUTH-29**).

The remaining lifecycle rules are mechanical: **REDIR-16**'s visited-URI set is seeded with the original request
URI and a revisit returns the current response unclosed and without raising; **REDIR-17**'s max-hops default of 3
returns the last response as-is at the cap and disables following entirely at 0; **REDIR-18** and **REDIR-19**
return the current response unfollowed on a malformed, unresolvable, missing or empty `Location`; **REDIR-22**
closes the prior response before issuing a follow-up and closes the current one if building the follow-up raises,
while every "return current" outcome leaves the response open for the caller; and **REDIR-23**'s stack-safety is
free because the follower is a `while` loop.

### 6.3 Authentication

**AUTH-1**–**AUTH-7**'s descriptor/resolver model is pure data and pure functions and translates without comment;
the resolver is a deterministic function of its inputs with no state (**AUTH-7**). Credential construction is where
the validation lives: **AUTH-9** requires that `BearerToken.token`, `KeyCredential.apiKey`, and
`NamedKeyCredential.name` and `key` all be non-blank and that blanks be rejected with a validation error, and
"non-blank" here means Ruby's sense of the word — `nil`, `""` and a whitespace-only string are all rejected, since
a credential of spaces produces a syntactically valid header that fails at the server with no useful diagnostic.
The check runs in the `Data` subclass's `initialize` override alongside §4's required-field guard, so there is no
construction path that skips it.

**AUTH-8**'s redact-in-string-form requirement means every credential type overrides `#inspect` **and** `#to_s`,
since Ruby interpolation calls `#to_s` and a debugger calls `#inspect`; and its variant-specific equality split —
value equality for the bearer token, reference identity for the key credentials — is expressed by making the bearer
token a `Data` and the key credentials plain classes that do not define `==`, so Ruby's default identity equality
is what they get — the language's default is the requirement, and writing nothing is the correct implementation.

**Challenge parsing** (**AUTH-12**, **AUTH-13**) is hand-written: it must handle multiple comma-separated
challenges, quoted strings containing commas and equals signs, backslash escapes, a bare scheme with an empty
parameter map, and a token68 value under a synthetic key, and must never raise — recovering to the next top-level
comma on a malformed challenge and terminating an unterminated quoted string at end of input. No Ruby library does
this; the parser is a character-level state machine, not a regexp, both because the grammar is not regular and
because a hostile `WWW-Authenticate` should not be able to drive a backtracking engine.

**Which handler answers, and which header name it writes.** Two clauses around the parser are easy to leave
implicit and are stated here instead. Composition (**AUTH-23**) delegates to the first handler in declaration order
whose can-handle check passes, and **takes a defensive copy of the handler list at construction** so a caller who
later mutates the array they passed cannot reorder the preference — the same construction-time copy §6.1 applies to
the retry sets and §4 to every model collection. Ordering is the caller's responsibility and the documentation says
so: stronger schemes first, Digest before Basic, because a server offering both is answered by the first match and
not by the strongest. And the header name a handler emits is selected by an **explicit proxy flag**, not by
inspecting the challenge or the status: `Authorization` for a `WWW-Authenticate` challenge, `Proxy-Authorization`
for a `Proxy-Authenticate` one (**AUTH-25**). A handler that cannot satisfy any offered challenge returns `nil` —
no header, not an empty one — which is what lets composition fall through cleanly and what keeps a failed
negotiation from putting a malformed `Authorization:` on the wire.

**Digest is where Ruby is better off than a portable-crypto host, and the reason is FIPS.** **AUTH-15**–**AUTH-22**
require MD5 and MD5-sess alongside SHA-256 and SHA-256-sess: RFC 7616 still mandates MD5 for interoperability with
servers that have not adopted SHA-256. Ruby offers two routes to MD5, and they are not equivalent. `Digest::MD5`
comes from the `digest` default gem, which bundles its own implementation and does not route through OpenSSL's EVP
layer; `OpenSSL::Digest::MD5` does, and therefore fails on a FIPS-enabled OpenSSL where MD5 is not an approved
algorithm, because the restriction is enforced inside the EVP layer itself. This is the one claim in this document
that could **not** be reproduced on the authoring machine — no FIPS-enabled OpenSSL build was available, and both
routes succeed on a normal 3.4.10 — so it is stated as resting on published behaviour rather than on verification:
the divergence is documented in GitLab's omnibus packaging, whose FIPS work replaced `OpenSSL::Digest` MD5 calls
with stdlib `Digest::MD5` for exactly this reason (`gitlab-org/omnibus-gitlab!6357`, cited in the Ruby-ecosystem
research this design draws on). Marked because P13 asks for verification against a real interpreter and this
paragraph does not have it; the design consequence is unchanged either way, since `Digest::MD5` is also the
zero-dependency choice. The port uses `Digest::MD5` and `Digest::SHA256` for all four algorithms, so Digest
authentication keeps working in a FIPS deployment — and no MD5 implementation needs vendoring, unlike a host whose
portable crypto API excludes it on security grounds. `SecureRandom.hex(16)` supplies the 128-bit client nonce
(**AUTH-20**, **XCUT-21**), which is a CSPRNG draw, never `Random`. The per-nonce counter (**AUTH-18**) increments under a
`Thread::Mutex` so concurrent reuse of one server nonce still yields correct non-duplicated counts (**AUTH-24**),
and its store is bounded at 1024 with drain-to-cap (**AUTH-19**, **XCUT-14**).

**Basic authentication is the zero-dependency rule's sharpest edge.** **AUTH-14** requires
`Basic ` + base64(UTF-8 of `username:password`). The obvious Ruby line is `Base64.strict_encode64`, and it is
forbidden in core: `base64` became a *bundled* gem in Ruby 3.4 (verified from `Gem::BUNDLED_GEMS::SINCE`), so
`require "base64"` from a gem that has not declared it fails under Bundler on a supported Ruby. Core uses
`[credentials].pack("m0")` instead (verified to produce identical output), which is a core `String`/`Array` method
with no library behind it.

The inverse, `String#unpack1("m")`, is used for decoding, and its leniency is worse than "returns an empty string
for garbage" — that is only the easy case. Verified on 3.4.10: **it never raises, on any input.** It returns `""`
only when the input contains no valid base64 characters at all (`"&*(^%$#@".unpack1("m")` → `""`), and on *mixed*
input it silently decodes whatever valid subset it finds and discards the rest — `"!!a b c!!".unpack1("m")` returns
the two-byte string `"i\xB7"`, decoded from the surviving `abc`. So a caller that tests only for an empty result
accepts non-empty garbage, and there is no error channel to check instead. **The subsequent length check is what
catches it**: a decoded Basic credential must be non-empty and must contain a `:`, and a decoded value of any
fixed-width form is checked against its expected byte length before use. Stated explicitly because the empty-string
test is the natural thing to write and it is not sufficient.

**The AUTH pillar step** (**AUTH-27**–**AUTH-33**) runs inside both loops. **AUTH-28**'s HTTPS guard fires before
any token fetch or header write on every credential-attaching path (**XCUT-16**), and is skipped — deliberately —
on a cross-origin re-issue where no credential will be attached, so a permitted downgrade hop is forwarded
credential-free rather than hard-failing (**AUTH-29**). The 401 re-challenge drives the replacement through a fresh
fork exactly once with no further challenge handling (**AUTH-30**), returns a 401 without `WWW-Authenticate`
unchanged (**AUTH-33**), closes the open 401 body if the hook raises (**AUTH-32**), and — on both sync and async
paths, per §5.2's uniform resolution of **AUTH-31** — skips the replay and surfaces the original 401 *unclosed*
when the replacement body is not replayable. The bearer step's hot path reads one frozen token object from an
instance variable without taking a lock, with refresh serialised under a per-credential `Thread::Mutex`
(**AUTH-34**, **XCUT-12**); the read is safe by publication (written only under the lock) rather than by relying on
the GVL, so it holds on JRuby and TruffleRuby too. **AUTH-37**'s three-zone async policy — stamp when fresh, stamp
and kick off a background refresh when expiring-but-valid, await a coalesced single-flight fetch when expired —
uses the pivot's `#on_settle`, and a failed background refresh is non-fatal because a valid token was already
stamped.

**The provider is not trusted, and the three ways it can misbehave are handled separately** (**AUTH-35**). A
provider returning `nil` is an error surfaced to the caller, not a silently unauthenticated request — the failure
mode a permissive port produces is a 401 from the server with no indication that the SDK is what dropped the
credential. A provider returning a token **already expired at fetch time** is likewise an error, and the expiry is
evaluated with **no refresh margin**: the margin exists to trigger a refresh early, and applying it here would
reject a token that is merely close to expiry, which is a legitimate thing for a provider to return. And a provider
that *raises* propagates and **its result is not cached**, so the next request retries the fetch rather than
inheriting a poisoned slot — which in Ruby means the memoisation write happens after the provider returns
successfully and never inside an `ensure`, since an `ensure` around a raising call is exactly how a `nil` gets
cached by accident.

---

