# Phase 5b — The Logging Facade and Redaction: Checklist

**Written at execution time, 2026-09-17, from what was built** — not from the plan. A row whose task
did not do what the plan said is a row that says so, and the "Deviations from the plan" section
below is where each departure is stated with its reason. The design and the plan were written on
2026-09-09 against phases 0–3's *plans* and phase 4's *designs*, on a machine that then had only Ruby
3.4.10, concurrently with 5a's and 5c's documents and before either was built. Since then phases 1, 2,
3a, 3b, 4a, 4b and 4c were built and merged to `main` (PRs #40–#62), all four interpreters were
installed, phases 5a and 5c were built in parallel off `main` and each approved, and 5c's stack was
rebased onto 5a's. **This phase was cut from the reconciled 5c docs tip, `032986b`, which holds both 5a
and 5c**, so the plan's interleaved order (5b Tasks 1–14 → 5c Tasks 1–7 → 5b Tasks 15–16) collapsed to
Tasks 1–16 straight through: 5c's `meter.rb`, `tracing.rb` and its recording doubles were already there
for Task 15, and 5c's `diagnostics.rb` — the three constants it shipped early for this phase to adopt
(P5-71) — was extended in place rather than created. Neither 5a nor 5c is on `main`: the three phase-5
stacks go up together as one nine-PR stack, 5a, then 5c on 5a, then 5b on 5c. Where the plan's text and
the built tree disagree the tree wins and this document records it.

Legend, verbatim from the roadmap's cross-cutting constraint 3: ✅ implemented and tested ·
🚫 not built (permanent simplification, named reason) · ⏳ deferred (naming the plan task — phase,
task number and path — that will do it, or the `docs/first-release.md` entry that owns it) ·
N/A not applicable in this port.

Plan: `docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction.md`. Task numbers are that
plan's. Design: `docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-design.md`, whose
Deviation Ledger rows `P5-16`–`P5-39` and as-built rows `P5-91`–`P5-102` are cited below; the charter is
`docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md`. Every test file named here is under
`gems/dexpace-core/test/`, mirrors its `lib/` file one for one (two carry no `lib/` mirror and say so
below; two `private_constant`s carry no `test/` mirror and are asserted at their call sites), and opens
with the IDs it exercises.

## Requirement rows

Twenty-eight own rows — `OBS-1`–`OBS-20`, `OBS-24` and `OBS-34`–`OBS-40` — plus fourteen cross-reference
rows for the non-`OBS` IDs this phase owns a share of, taken from the design's interface-surface table
the way 4b, 4c, 5a and 5c carried theirs: `XCUT-19`'s five clauses, `XCUT-20`, `XCUT-11`, `CFG-24`/`CFG-25`
(the warning's diagnostic), `CFG-21` (the close route), `CFG-14` (the published key names), `CFG-16` (the
monotonic duration), `SEAM-25` (the event shape), `BODY-19`/`BODY-22`/`BODY-34` (the enablement gate),
`BODY-20` (the request preview's placement), `OBS-23` (5c's push, over 5b's keys), `PIPE-28` (one stage
identity on both runtimes) and `NFR-11` (the two interfaces' home). **Twenty-six ✅** — `OBS-24` and
`OBS-10` ✅ with the 3.2 floor's behaviour stated in the row — **two ⏳** (`OBS-19` to phase 8c,
`OBS-37` post-v1), nothing 🚫, nothing N/A.

| ID | Level | Status | Task(s) | What was built, and where it is proven |
|---|---|---|---|---|
| `OBS-1` | MUST | ✅ | 4, 9, 10 | `Logger#event` makes the enabled decision ONCE — `sink.public_send(severity.sink_predicate)` — and returns the shared `Event::INERT` for a disabled severity, a frozen instance of the private `Event::Inert < Event` whose four methods return `self`/`nil` and write no ivar (P5-20). Identity is asserted with `assert_same` on the **qualified** constant `Dexpace::Instrumentation::Event::INERT`, the form `dexpace-conformance` restates from another gem (R8), and the chain `field(:k, 1).event(:x).cause(nil).emit` is measured at exactly `0.0` allocations per call through 5c's `AllocationDelta` — only a Symbol, an Integer and nil cross the loop, which is what makes the measurement file-independent; the magic comment is a repository rule and not the test's precondition. Obtaining the inert event from a logger is `0.0` per call too, and `NULL_SINK`'s predicates and discarded writes likewise. **The assertion's shape on the floor** (review round 2's R2-4): a single two-loop measurement came back negative (`-0.007`, `-0.028`) in about one whole-file run in fifteen on 3.2.11 — a one-time cost of 7 or 28 interpreter objects landing inside a measured block after the warm-up, once per process and test-order dependent, never on 4.0.6 — so 5c's `AllocationDelta#allocations_per_call` now returns the figure two consecutive measurements agree on, which a one-time cost cannot be and a real per-call cost always is; the property is still asserted at exactly `0.0`, and 60 whole-file runs on 3.2.11 after the change failed none (2 of 30 before). Guards 1 and 2, guard 2 re-run red through the changed helper on both rows (`instrumentation/logger_test.rb`, `event_test.rb`, `null_sink_test.rb`; `test/support/allocation_delta.rb`) |
| `OBS-2` | MUST | ✅ | 2, 4, 10 | `Severity` is a frozen `Data` closed set of exactly four — `ERROR`/`:error`/`:error?`, `WARNING`/`:warn`/`:warn?`, `INFO`/`:info`/`:info?`, `VERBOSE`/`:debug`/`:debug?` — with the mapping as two DATA members, `.of` by identity, `.new` and `.[]` private and `#with` refusing (the `Pipeline::Stage` shape), so the sink call is `public_send(sink_method)` and a fifth level cannot arrive by accident. Each of the four is driven through a `RecordingSink` and surfaces at its backend method. Guards 3 and 4 (`severity_test.rb`, `logger_test.rb`) |
| `OBS-3` | MUST | ✅ | 9 | `Event#field` refuses `""`, `:""`, `nil` and a non-name key through `Model.required!("field key", …)`, so the message is `SEAM-29`'s one form; a nil VALUE is kept and rendered as the literal `"null"` — and it is not routed through the header redactor, whose `""` contract would lose the null-versus-absent distinction. Guard 5 (`event_test.rb`, `AccumulatorTest`) |
| `OBS-4` | MUST | ✅ | 3, 9 | `Keys::EVENT` is `"event"`; `#event(name)` sets the tag and a nil or empty name clears it rather than emitting `event=`; at `#emit` a non-empty tag is written over any `event` key the three sources supplied — asserted from all three separately: a per-event field, the global context, and the folded diagnostic context in unfiltered mode — so the record carries the key exactly once; without a tag a per-event `event` field is an ordinary field (`event_test.rb`, `MergeTest`) |
| `OBS-5` | MUST | ✅ | 9 | One merge in one place in one order — folded diagnostic context, then the logger's frozen context, then the event's fields, later winning — into one Hash at `#emit`; the chapter's own case supplies the same key from all three with distinct values and the per-event value is the single emitted one, `keys.count` 1 (`event_test.rb`, `MergeTest`) |
| `OBS-6` | MUST | ✅ | 5, 9 | The private `Render` module: nil → `"null"`; Integer, Float, Rational, Complex, true and false pass through type-preserving; an exception → `SimpleClassName: message` with `"Class"` for an anonymous class, whose `#name` is nil (verified fact 8); an Array or Hash → its bracketed `#inspect`; a String itself, a Symbol its name, anything else `#to_s`; every path inside a `rescue StandardError` substituting `[unrenderable <ClassName>]`, reached through `Kernel#class` so a `BasicObject` — which answers neither `#class` nor `#to_s` — gets `[unrenderable BasicObject]`, and a class whose own `.name` raises gets `[unrenderable Object]`. `Hash#inspect`'s spacing changed at 3.4.0, so the collection case asserts the shape and not one interpreter's spelling. Asserted at the call site, through `Event#field`/`#emit` (P2-15, P4-3). Guards 6 and 7 (`event_test.rb`, `RenderingTest`) |
| `OBS-7` | SHOULD | ✅ | 5, 9 | `Render::MAX_VALUE_BYTES = 8 * 1024` applied on **bytes** (P5-29): `#byteslice`, then `#scrub("")` so a cut multibyte character leaves a valid String, then the marker. The marker is the ASCII `"...[truncated]"`, not the design's `"…[truncated]"` (P5-96), so it concatenates onto a BINARY or Latin-1 rendering without an `Encoding::CompatibilityError`; a String in a non-ASCII-compatible encoding (UTF-16) is transcoded to UTF-8 first. The conformance sentence's "cap+suffix" is asserted on `bytesize` — `"€" * 4000` renders as 2,730 characters, 8,190 bytes plus the marker, the 2,731st `€` having been cut in half — and the divergence from `#length` is named in the test; exactly the cap is untouched, one over is cut, and a numeric primitive of any size is exempt. Guards 8 and 9 |
| `OBS-8` | MUST | ✅ | 9 | `@emitted` flipped under the **logger's** `Thread::Mutex` and the mutex released before the sink call, in `Event#claim_emit!`: a second `#emit` is a no-op, four threads parked on one `Thread::Queue` and released onto one instance produce exactly one output, and a sink that logs through the SAME logger from inside its own write — a second event, the same mutex — completes rather than meeting the non-reentrant mutex's `ThreadError: deadlock; recursive locking`. Two events of one logger on two threads emit once each. Guards 10 and 11 (`event_test.rb`, `AccumulatorTest`; `logger_test.rb`) |
| `OBS-9` | MUST | ✅ | 9, 10 | `Logger.build(context:)` takes a String-keyed copy and deep-freezes it once through `Model.own`; `#context` returns the same object every read, every event merges it under `OBS-5`, and the caller's own Hash is neither frozen nor aliased (`logger_test.rb`, `event_test.rb`). A reserved key in the context — `url.full`, a header-prefixed key — meets the event's redaction table ONCE here, at `Logger.build`, so the frozen context already carries the redacted form and omit mode drops the key (P5-104, review round 1's R1-2; `event_test.rb`, `AmbientSourcesTest`). Guard 62 |
| `OBS-10` | MUST | ✅ | 6, 9, 10 | `Diagnostics.folded(allow_list)`: with a list, each key read through `Fiber[]` and a nil-valued key skipped; with `nil` — a MODE, the opt-in unfiltered fold, not "use the default" — the whole map read through `Fiber.current.storage`, nil values skipped and every key under `RESERVED_PREFIX` (`"dexpace."`, P5-39) skipped, so 5c's live `Span` in `:"dexpace.current_span"` never reaches `OBS-6`'s rendering. `DEFAULT_KEYS` is exactly `[:"trace.id", :"span.id"]`; the fold's key bridge is `Symbol#name`, the same frozen String on every call (asserted with `assert_same`), never `#to_s`. `Logger.build(diagnostic_keys:)` coerces a list to Symbols once, because `Fiber["k"]` raises `TypeError` on 3.2 and 3.3. **The floor**: on 3.2.11 `Fiber[:k] = nil` leaves a nil-valued key behind, so the null-skip clause is live for every key ever set and cleared there, where on 3.3+ only the warned `Fiber#storage=` can construct one — the test constructs the input through that setter inside phase 2's `WarningCapture`, the one `Fiber#storage=` call in 5b's suites, and the skip is asserted on every row. A reserved key the fold surfaces, in either mode, meets the same redaction table at `#emit` that a per-event field met at `#field` (P5-104, R1-2): `Fiber[:"url.full"]` and `Fiber[:"http.request.header.authorization"]` reach the sink as the redacted URL and the marker, or not at all in omit mode, and a per-event field still wins the merge (`event_test.rb`, `AmbientSourcesTest`). Guards 12, 13, 63 and 64 (`diagnostics_test.rb`, `FoldTest`; `logger_test.rb`; `event_test.rb`) |
| `OBS-11` | MUST | ✅ | 8, 9 | `Redactor#url` writes `***:***` in place of any present userinfo, whatever the policy says — `RedactionPolicy` has NO member that can reach userinfo (boundary 4, `XCUT-19`(a)), asserted on `Policy.members` — including a user with no password and a percent-encoded pair; the chapter's negative, neither the username nor the password substring anywhere in the output, is the assertion. Through `Event#field(Keys::URL_FULL, …)` it is structural. **On `#header_value` the same holds on every route** (P5-100, review round 0's R0-3): the relative route rebuilds a network-path reference's authority with the placeholder (`//user:secret@h/x` → `//***:***@h/x`), the surgery route substitutes an authority's userinfo before cutting (`http://user:secret@h/p x` → `http://***:***@h/p x`), and the sentinel-fallback route runs that surgery — so a hostile `Location`, which the default allow-list admits, cannot carry a credential to the sink; asserted through a real pipeline at `HEADERS` with the credential in no payload. **Two more routes closed by review round 1**: the surgery pattern tolerates a leading run of whitespace and control bytes, so a `Location` built with the leading OWS `HTTP-19` admits (`" http://user:secret@evil/x"`, a HTAB, a VT, a NUL) loses its userinfo through the redactor and through the step (P5-105, R1-3; `redactor_test.rb`, `SurgeryRouteTest`; `step_test.rb`, `HeaderRedactionTest`); and the proxy resolver's warning and its config diagnostic name the proxy URL through the redactor's total form and never raw, with `CFG-24`'s grammar rule on top for the scheme-less `user:secret@proxy.corp:3128` the redactor reads as an opaque part (P5-103, R1-1; `downstream_wirings_test.rb`). **Closed for the class by review round 2** (P5-107, R2-1): P5-105's pattern tolerated whitespace and controls and nothing else, so `<http://user:secret@evil/x>`, a quoted or parenthesised URL, `x http://…`, `%20http://…`, `+http://…`, `@http://…`, a backslash, an NBSP, a line separator and the BINARY obs-text spellings carried the userinfo through the step at `HEADERS`, and a QUOTED or bracketed `HTTPS_PROXY` — `"http://user:secret@proxy.corp:3128"` with its quotes kept — wrote the client's own credential into the warning and the sink; the surgery route now substitutes EVERY `//`-authority's userinfo wherever it sits (`gsub`, unanchored, linear), so all of those and a doubled proxy URL lose it, through the redactor, through the step and through `Proxy.resolve` (`redactor_test.rb`, `SurgeryRouteTest`; `step_test.rb`, `HostileLocationTest`; `downstream_wirings_test.rb`, `QuotedProxyTest`). What is still written back as given is what RFC 3986 gives no authority: `user:pw@h/p` (no `//` before the `@`; the resolver's grammar belt covers the proxy case), the backslash spellings, and what the parser ACCEPTS without one — `http:///u:p@h/p`, `//@u:p@h/x`, and a valid URL whose path spells a second authority, `http://u:p@h/phttp://u:p@h/p`, kept because `OBS-14` forbids altering the path — each asserted (R1-7, R2-1). A multi-valued `Location` is redacted per value before the join (P5-108, the `OBS-17` row). Guards 14, 49, 50, 51, 54, 59, 60, 61, 65, 69, 70 and 74 (`redactor_test.rb`, `event_test.rb`, `step_test.rb`, `downstream_wirings_test.rb`) |
| `OBS-12` | MUST | ✅ | 7, 8, 9 | Each `name=value` pair keeps its name and `=` and gets `***` unless the name — decoded with `URI.decode_www_form_component`, scrubbed, folded with a bare `downcase` — is in the policy's `query_allow_list`, which defaults to exactly `Set["api-version"]` and, when empty, redacts every value (an empty list is a real value, not "use the default"). Multi-value keys are atomic by construction: the decision is a function of the name alone, asserted with a name appearing three times. `?%FF=secret` — the input whose decoded name raises `ArgumentError` out of `#downcase` — redacts to `%FF=***` and raises nothing, and a name the decoder itself rejects (`%zz`, a `%` not followed by two hex digits) is unmatchable the same way, `%zz=***`, rather than sentinelling the whole URL (P5-101, R0-7). A bare token with no `=` is kept. Guards 15, 16, 17 and 52 (`redaction_policy_test.rb`, `redactor_test.rb`) |
| `OBS-13` | MUST | ✅ | 8, 9 | The fragment is tokenised by hand on `&` (`URI` does not tokenise one): a `key=value` token follows `OBS-12`'s rule, `#access_token=SECRET` → `#access_token=***`, and a fragment with no `=` anywhere — `#section`, `#a/b?c` — is kept verbatim (`redactor_test.rb`) |
| `OBS-14` | MUST | ✅ | 8, 9 | Scheme, host, port and path are written back byte for byte — including `:80`, `:443`, an IPv6 host and `file:///`, because the redacted form is reassembled from `RFC3986_PARSER.split`'s nine raw components and never through `URI#to_s`, which drops a default port (P5-91) — a present-but-empty query keeps its trailing `?` (`https://h/x?` → `https://h/x?`, `http://h?` → `http://h?`), the chapter's own case `http://h/p#a?b=c` has no `?` before the `#` (and `a?b=***` after it, `OBS-13`), and a trailing `&` — the empty final pair OBS-14 says MAY be dropped — is dropped, in a query and in a fragment, while an interior empty pair is kept. Guards 18, 19 and 20 |
| `OBS-15` | MUST | ✅ | 8 | `#url` is total: `"not a url at all"`, `"https://h/a b"`, `"http://[::1"`, a bad percent-encoding in a path, a NUL byte and `nil` all yield `"[malformed url]"` with nothing raised, asserted on the value and never with `assert_nothing_raised`. The rescue is `StandardError`, not `URI::Error` (P5-26): a policy whose allow-list read raises drives an ordinary URL into it, and narrowing it to `URI::Error` is run red. An opaque URI (`mailto:`, `urn:`, `data:`) round-trips untouched, because nothing absent is ever written back (P5-27, now by construction) — except a query-shaped tail, which the pinned parser folds INTO the opaque component (`mailto:a@b?subject=SECRET` splits with `query` nil): the part after the first `?` takes `OBS-12`'s rule and the address before it is written back as is (P5-101, R0-8). Two things `split` accepts that `#parse` rejects — a bad percent-encoding in a query VALUE, and one in a query NAME — are redacted rather than sentinelled (the fragment case still sentinels: the parser rejects a bad encoding there), and the tests say so. Guards 21, 22, 52 and 53 |
| `OBS-16` | MUST | ✅ | 8, 9 | `Redactor#header_value`: a value with a scheme is redacted like a request URL; a relative value keeps its split path and gets `?***` iff it carried a query OR a fragment, the presence test `!nil?` because `/cb?` splits with an EMPTY query (`/cb?code=SECRET` → `/cb?***`, `/cb?` → `/cb?***`, `#frag` → `?***`, `/static/path` verbatim); a value the parser rejects takes the string-surgery route on the raw value (P5-28: `bad path?secret=1` → `bad path?***`). It returns a String always — nil → `""` — and never `OBS-15`'s sentinel (P5-25): an absolute value that would sentinel falls through to the surgery form. **"A value with neither MUST be returned verbatim" yields to `OBS-11` on exactly one input**, a relative value carrying a userinfo (P5-100): the relative route writes a network-path reference's authority back with the placeholder and every other component byte for byte, so the verbatim clause holds by construction for every value `OBS-11` does not reach (`//h:8443/x`, `//[::1]:8443/x` unchanged). The surgery route substitutes every `//`-authority's userinfo wherever it sits and writes every other byte back as it came (P5-105, P5-107): `"  http://user:secret@h/p?code=S"` → `"  http://***:***@h/p?***"`, `"<http://user:secret@h/p>"` → `"<http://***:***@h/p>"`. Guards 23, 24, 49, 50, 51, 54, 65, 69, 70 and 74 |
| `OBS-17` | MUST | ✅ | 7, 8, 15 | `url_header_names` defaults to `Set["location", "content-location"]`; only those go through `#header_value`'s URL redaction and every other value passes through unchanged; `Event#field` applies it by the `http.request.header.`/`http.response.header.` prefix, so it holds for both directions. Shared so it cannot drift, twice over: the two steps write through one private `Emitter` (P5-34), and — found by guard 25 — **there is one redactor per logging path, the logger's**: `Step.build` no longer takes a `redactor:` of its own and — since review round 0 — the emitter reads no gate at all: every header goes into `Event#field` under its prefix and the event gates the name and redacts the value through the logger's one redactor (P5-95, P5-102), so the names a step logs and the values its events redact cannot come from two policies. The async path is asserted to redact a `Location` and mark an `Authorization` exactly as the sync path does. **A multi-valued URL-valued header is redacted per VALUE and joined with `", "` afterwards** (P5-108, review round 2's R2-2): the `Emitter` joined first, so two `Location`s reached the redactor as one string no parser accepts and the second value's userinfo sat behind the first value's path — `https://***:***@a/x, https://user:secret@b/y?***` through the step; now the `Emitter` hands the value list over as a list and `ReservedKeys.header_value` maps each value through the redactor for an allow-listed name, so a caller writing an `Array` by hand gets the same (`step_test.rb`, `HostileLocationTest`; `event_test.rb`, `HeaderGateTest`). Guards 25 and 71 (`redactor_test.rb`, `step_test.rb`, `async_step_test.rb`, `event_test.rb`) |
| `OBS-18` | MUST | ✅ | 7, 8, 9, 15 | `Redactor#header_name?` answers against the folded allow-list; the default list is twenty-six diagnostic, non-credential names, chosen not derived (P5-30), asserted name by name, with `authorization`, `proxy-authorization`, `cookie`, `set-cookie`, `x-api-key`, `www-authenticate` and `proxy-authenticate` asserted absent. **`Event#field` gates NAMES first, by the reserved prefix** (P5-102, review round 0's R0-4 — the round-0 tree gated only in the private `Emitter`, so a credential header written straight into `#field` logged its value): a header-prefixed key whose name is outside the list stores the fixed `REDACTED` marker (the default, P5-35) or, with `omit_disallowed_headers: true`, nothing at all, whoever the caller is; the `Emitter` writes every header and decides nothing. BOTH modes are asserted through the step and directly at `#field`, and the name gate is asserted to run before the URL-value redactor. The chapter's negative is the assertion that matters: `Content-Type`'s value present, and `Bearer`/`sk-live-abc123`/`deadbeef` nowhere in the payload. **The gate reaches `OBS-5`'s two ambient sources too** (P5-104, review round 1's R1-2): a header-prefixed key in the logger's global context is marked or dropped once at `Logger.build`, and one the diagnostic fold surfaces — in the unfiltered mode or a listed one — at `#emit`, so `Fiber[:"http.request.header.authorization"]` and a context `authorization` reach the sink as `REDACTED` or not at all, whoever set them (`event_test.rb`, `AmbientSourcesTest`). Guards 26, 55, 56, 57, 58, 62, 63 and 64 |
| `OBS-19` | SHOULD | ⏳ | — | Postponed to phase 8c, Tasks 7, 9 and 15 (`AsyncHTTP::DropPolicy`, `docs/work/mvp/phase8/phase8c/2026-09-11-phase8c-asynchronous-transport.md`), P5-32 and R10: the requirement's subject is a transport that drops a caller-set header it cannot encode; core has no transport, `Net::HTTP` raises rather than drops, and a public three-mode policy with no core caller is the `TeeSink#clear_tap` shape. What ships here is both halves the policy is built from — `Severity` and the once-per-logger latch, with `OBS-40` as the latch's exercising caller. Verified present at its owner, nothing re-recorded |
| `OBS-20` | MUST | ✅ | 11, 14, 15 | `Instrumentation.contain(logger, event:)`, the one containment primitive, a module function (P5-37): the block's value is swallowed, nil comes back, a `StandardError` becomes a WARNING `http.instrumentation.*` diagnostic carrying the error as its cause, and a failure while emitting THAT is swallowed with no second attempt — a sink that raises on every call, predicates included, still yields nil. Only `StandardError`: a `SignalException` and a `NotImplementedError` propagate. Every log-emission site in the phase is inside it — the step's request, response and failure events, and the three wirings through `Instrumentation.diagnostic` — and every tracer, scope and meter call is outside it, unwrapped (boundary 3): a raising sink cannot fail a request and produces one `INSTRUMENTATION_LOG` diagnostic per emission site, while a throwing meter propagates and fails it, and a throwing tracer propagates before the chain is driven. On the async path the meter's failure reaches the settling side (the design's stated consequence) **at every level, and the teardown runs once** (P5-109, review round 2's R2-3): the settlement work was registered on the DERIVED future at `BODY`, inside `Future#then`'s rescue, so a throwing meter vanished there; and on a future that settled inside the head the callback ran inline, raised, and the head's `ensure` finished the span and added the counter a second time. Now the work sits on the source future at both levels, the head's `ensure` tears down only when the head raised before the chain handed back its future, and a throwing meter at `NONE`, `HEADERS` and `BODY` raises into `transport.settle` with the caller still receiving the response, or — settled inline — fails the request through the driver's PIPE-30 normalisation, with `#add` and `#finish` counted at exactly one each way (`async_step_test.rb`, `ThrowingMeterTest`). Guards 27, 28, 72 and 73 (`contain_test.rb`, `step_test.rb`, `AsymmetryTest`; `async_step_test.rb`) |
| `OBS-24` | MUST | ✅ | 6 | `Diagnostics.capture` is one read and one freeze — `Fiber.current.storage` is already a fresh copy — normalised from the nil an opted-out fiber reads on 3.3+ and the `{}` the floor reads, and with every nil-valued key dropped (P5-97), so a snapshot has one shape on every row; frozen is what is claimed, Ractor-shareable is not (P5-22). `Diagnostics.with(snapshot)` installs per key, yields, and restores per key over the union of the prior and snapshot key sets in an `ensure` (P5-23), through `Fiber[]=` alone; asserted with an overwritten key put back, an introduced key gone, a raise inside the block, and a real thread boundary — capture on A, run on B, the captured keys visible inside and B's OWN prior context restored after, which is not empty, because a new Thread inherits a copy. The snapshot is any object answering `#each` and `#keys`. **The floor**: on 3.2.11 a key the snapshot introduced is left present with a nil value after the restore — the floor's whole `Fiber` API is `[]`, `[]=`, `storage` and `storage=`, and the only removal is the warned setter core never calls — which `Fiber[]` and the fold read as absent (P5-72 applied to `OBS-24`, P5-97); `FiberStorageFacts#assert_diagnostic_key_removed` asserts what each row can honour. Both settlement events of the async step ride the bridge (P5-93): the response event and — asserted since review round 1, whose mutation of the bare `log_failure` survived the suite (R1-5) — the failure event, each emitted under the caller's captured `trace.id` and `span.id` from a settling `Thread` whose own storage differs, and the settler's keys put back (`async_step_test.rb`, `ThreadBoundaryTest`). Guards 29, 30, 31 and 67 (`diagnostics_test.rb`, `BridgeTest`; `logging_matrix_facts_test.rb`; `async_step_test.rb`) |
| `OBS-34` | MUST | ✅ | 13, 15 | `HTTPLogging` is a frozen `Data` closed set of `NONE`/0, `HEADERS`/1, `BODY`/2 with `DEFAULT = NONE`, `#at_least?` its one comparison, `.of` strict, `.new`/`.[]` private and `#with` refusing. The conformance clause's first half is one test asserting four things: at `NONE` zero sink writes, one span started and finished, the counter and the histogram each recorded once under `Keys::INSTRUMENT_REQUEST_COUNT` and `::INSTRUMENT_REQUEST_DURATION`, the two instruments created once in `.build`; the second half, the preview fields present at `BODY`, is the `OBS-36` row. The structural property: the two emissions inside `contain` under the level guard, every tracer and meter call outside both, in the `ensure` — and on the async path by exactly one side, the head's `ensure` or the settlement callback, never both (P5-109). Guards 32, 33 and 73 (`http_logging_test.rb`, `step_test.rb`, `async_step_test.rb`) |
| `OBS-35` | SHOULD | ✅ | 13 | `HTTPLogging.parse(text, default:)` is whitespace-trimmed, case-insensitive (`downcase` with no argument, after `#scrub`), and falls back for nil, empty, blank or unrecognised text — the chapter's `"  Headers  "` and `"HEADERS"` both resolve to `HEADERS`; `.resolve(configuration, key:, default:)` is `.parse` over `Configuration#string(key)`, so the four tiers are 5a's. **`key:` is required with no default** (P5-36): omitting it is an `ArgumentError`, and `Configuration::Keys::LOG_LEVEL` is a published name a caller may pass — the test passes it, and passes a different key to show nothing falls back to it. Every configuration is built over `FakeConfigSource` seams. Guards 34 and 35 |
| `OBS-36` | MUST | ✅ | 14, 15 | At `HTTPLogging::BODY` the step wraps the outbound body in `RequestLoggingBody.new(body, tap_limit: preview_bytes)` and the inbound one in `ResponseLoggingBody.new(body, preview_bytes:)` — the only two construction sites in core, which phase 3b's two "nothing constructs it" pins now assert as exactly that one file — and phase 3b's over-cap regime does the rest: the conformance clause's three assertions hold, the caller receives every byte of a 100-byte response through a 16-byte cap, the preview is `"S" * 16`, and the size field is the CAPTURE's 16 and never the declared 100. `preview_bytes:` is REQUIRED at `BODY` and refused when absent, zero, negative or not an Integer; no 8 KiB lives in any signature — the caller resolves `configuration.integer(Keys::LOG_PREVIEW_BYTES, default: 8 * 1024)` and passes it (the plan's open question 5, asserted in `downstream_wirings_test.rb`). Guards 36 and 37 (`step_test.rb`, `BodyLevelTest`; `async_step_test.rb`, `BodyLevelTest`) |
| `OBS-37` | SHOULD | ⏳ | — | Post-v1 with the async adapters: `docs/first-release.md` § What v1 ships without › SHOULD- and MAY-level requirements declined for v1, the `OBS-32`/`OBS-37` entry, which names this phase. `AsyncStep` captures a preview the same way the sync step does; what is postponed is the *skip* for an unknown-length body, which needs an async adapter to be an optimisation of anything. Verified present, nothing re-recorded |
| `OBS-38` | SHOULD | ✅ | 12, 15 | `Preview.render(bytes, media_type:)`: text when the type is `text` or the subtype is in `TEXT_SUBTYPES` or carries a `+json`/`+xml` suffix (a per-pattern `Regexp.new(source, timeout:)`), decoded by phase 3b's recipe — retag with the declared charset, then `encode(UTF_8, encoding, invalid: :replace, undef: :replace)` — and never §3.1's one step, which returns `"caf��"` for the same bytes; binary otherwise, an ABSENT media type included, as `[binary N bytes captured]`. The chapter's three cases, none ASCII: an ISO-8859-1 body decodes to `café`, a PNG gets the marker, a truncated multibyte body yields U+FFFD and raises nothing; empty input yields `""`; an unknown charset falls back to UTF-8 through `MediaType#charset`'s nil; the input is never mutated. A charset Ruby KNOWS but cannot convert — `utf-7`, `iso-2022-jp-2`, dummy encodings `Encoding.find` answers and `#encode` refuses with `Encoding::ConverterNotFoundError` despite both replacement options — falls back to UTF-8 the same way, by a rescue of the `EncodingError` family, so the never-throw clause holds for the declared charset the interpreter has no converter for and the step at `BODY` still emits the response event rather than a diagnostic in its place (P5-106, review round 1's R1-4; `preview_test.rb`; `step_test.rb`, `BodyLevelTest`); UTF-16, dummy WITH a converter, keeps its own decode. Guards 38, 39 and 66 (`preview_test.rb`, `step_test.rb`) |
| `OBS-39` | MUST | ✅ | 3, 9, 15 | `Keys` (sixteen) and `Events` (eight) are frozen String constants, each a row in the surface manifest, and the suites assert the exact sets so a seventeenth or ninth cannot arrive unnoticed. The step emits `http.request` with `http.request.method`, `url.full`, the allow-listed request headers and the declared body size when known (BODY-35's `-1` is filtered), and `http.response` with `http.response.status_code`, `http.response.duration_ms` off `Clock#monotonic` (a `FakeClock` advanced 12.5 ms yields exactly 12.5), the response headers and the declared size or the two previews; a failure emits `http.response` at ERROR with `error.type` (the nearest NAMED class, so an anonymous error class reports its ancestor) and the throwable attached under `cause`, then re-raises the same object. `url.full` is ALWAYS the redacted URL, structurally: `Event#field`'s reserved-key table redacts it by name, so `not a url` becomes the sentinel and a userinfo never survives, whoever the caller is — and since review round 1 wherever it came from: a `url.full` in the logger's context or in the diagnostic fold is the redacted URL on the record too (P5-104, R1-2). `BODY-35`'s `-1` filter is asserted since the same round, whose mutation of the guard survived the suite (R1-6): a chunked request and response body at `HEADERS` put no size field on either event and `-1` appears nowhere in the payloads (`step_test.rb`, `EventsTest`). Guards 40, 41, 62, 63 and 68 (`keys_test.rb`, `event_test.rb`, `step_test.rb`, `async_step_test.rb`) |
| `OBS-40` | SHOULD | ✅ | 9, 10 | A per-event `event` field colliding with a set tag is dropped in favour of the tag and warned about ONCE per logger, as a String at the sink's `#debug`, gated on `sink.debug?` BEFORE the latch is claimed so a disabled verbose level costs nothing and does not consume the one warning; a second logger has its own latch (`CollisionLatch`, private, under the logger's mutex); ambient `event` keys from the global context or the diagnostic context defer silently and are not warned about, asserted separately. Guard 42 (`event_test.rb`, `MergeTest`) |
| `XCUT-19` | MUST | ✅ share | 7, 8, 13, 15 | Cross-reference, phase 9's ID, default-deny in five clauses: (a) `OBS-11`'s userinfo redaction is unconditional and has no allow-list to reach it; (b) `OBS-12`/`OBS-13`'s query allow-list defaults to exactly `{api-version}` and an empty one redacts everything; (c) `OBS-18`'s header allow-list is twenty-six diagnostic names with every credential and challenge header absent; (d) is `AUTH`'s, phase 6's — 5a's `Proxy#to_s`/`#inspect` mask both credentials for the one credential-bearing type that exists, and 5b relies on that for no other type; (e) `HTTPLogging::DEFAULT` is `NONE`, so body logging is off unless opted in. Phase 9 audits the five; the subjects are `RedactionPolicy::DEFAULT`'s three sets and `HTTPLogging::DEFAULT` |
| `XCUT-20` | MUST | ✅ share | 8, 11, 12 | Cross-reference, phase 9's ID: the three totality paths phase 9 audits are `Instrumentation.contain` (nothing from a log-emission site escapes), `Redactor#url`'s sentinel and `#header_value`'s marker (nothing from a parse or rebuild escapes, the rescue `StandardError` on the verified `ArgumentError`), and `Preview.render`'s never-throw decode — total by the replacement options for every byte sequence and, since review round 1, by a UTF-8 fallback for the one thing the options do not cover, a declared charset with no converter (P5-106). Each is asserted on the substituted value |
| `XCUT-11` | MUST | ✅ share | 7, 8, 10 | Cross-reference, phase 9's ID: `RedactionPolicy` is a frozen `Data` of frozen Sets, `Redactor` is frozen with a frozen policy and every intermediate a method local (asserted: one ivar, eight threads through `Redactor::DEFAULT` agree), and `Logger` is frozen after `.build` with its mutable latch and mutex held by reference — the audited shared instances |
| `CFG-24`, `CFG-25` | MUST | ✅ diagnostic beside the warning | 14 | Cross-reference, 5a's IDs, P5-8 discharged: 5a's `ProxyResolution#warn_and_nil` — the one helper every malformed-input path calls — now also emits an `http.instrumentation.config` event through `Instrumentation.diagnostic`, with the warning's text under `Keys::MESSAGE` and no throwable, through the `logger:` keyword `Proxy.resolve` gained (default `Logger::NULL`); the `Kernel#warn` stays, observed through phase 2's `WarningCapture.record`. A missing-port URL and a non-numeric property port both take the route; a valid proxy emits nothing. **The URL a warning names is the redactor's form on both channels** (P5-103, review round 1's R1-1): the round found `user:secret` in the sink for every credential-bearing malformed `HTTPS_PROXY` — the text 5a interpolates was raw and `Keys::MESSAGE` is not a reserved key — and nine such values now show `***:***@` in the warning and in the diagnostic with the credential in neither, the scheme-less spelling through `CFG-24`'s grammar rule, the not-a-URI case named once without the parser's text — and, since review round 2 (P5-107, R2-1), a value that kept its quotes (`"http://user:secret@proxy.corp:3128"`, `'http://…'`, the dotenv and ConfigMap misconfiguration), a bracketed `<http://…>` and a doubled URL likewise, which the round found writing the client's own credential into both channels because the surgery pattern tolerated no prefix but whitespace and substituted once (`QuotedProxyTest`). Guards 45, 59, 60, 61, 69 and 70 (`downstream_wirings_test.rb`, `ConfigurationWiringTest`, `QuotedProxyTest`; 5a's `proxy_test.rb` unchanged and green) |
| `CFG-21` | MUST | ✅ second route landed | 14 | Cross-reference, 5a's row: `Dexpace.close_quietly(resource, onto: nil, logger: Logger::NULL)` — the `onto:`-absent branch, which phase 2 shipped as a drop and phase 4b's table said phase 5 would complete, now emits an `http.instrumentation.close` diagnostic with the close failure as its cause through `logger:`; with `onto:` the failure goes to the trail and NOT to the logger (two routes, never both), the return contract is nil always and the null-safety and the no-`#close` tolerance are untouched, and a raising sink still yields nil. Phase 2's closeable_test.rb comment that asserted the drop is rewritten to say what is now true. Guard 43 |
| `CFG-14` | SHOULD | ✅ one key added | 14 | Cross-reference, 5a's ID: `Configuration::Keys` gains its eighth constant, `LOG_PREVIEW_BYTES = "LOG_PREVIEW_BYTES"`, in the change that reads it (the body-logging caps' pick-up), a published name a caller resolves and passes to `Step.build(preview_bytes:)`; `LOG_LEVEL` is 5a's, untouched, and 5a's `keys_test.rb` — whose count and list grew by one — still asserts that no file under `lib/` spells `LOG_LEVEL` out, this phase's `http_logging.rb` included. Guard 46 |
| `CFG-16` | MUST | ✅ first consumer | 15 | Cross-reference, 5a's ID: `http.response.duration_ms` and the histogram's measurement are `(clock.monotonic - started) * 1000.0` and never `Clock#now`; `Step.build(clock:)` defaults to `Clock::SYSTEM` and the suites inject 5a's `FakeClock` for exact durations (`step_test.rb`, `async_step_test.rb`) |
| `SEAM-25` | MUST | ✅ event SHAPE only | 3 | Cross-reference, phase 2's ID: `Events::INSTRUMENTATION_SHUTDOWN` (`"http.instrumentation.shutdown"`) and the shape `Instrumentation.diagnostic(logger, event:, cause:, message:)` emits are the half this phase supplies; the emission is phase 8b's (Tasks 6 and 10 of `docs/work/mvp/phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter.md`), where the first owned executor exists, and the harness phase 9's (Task 11). Not claimed done. It is a log-event name and not an `OBS-28` tracer callback, as the design settled |
| `BODY-19`, `BODY-22`, `BODY-34` | MUST | ✅ gate landed | 14, 15 | Cross-reference, phase 3b's IDs: the enablement gate phase 3b postponed — the two wrappers are built ONLY in `Step#wrap_request`/`#wrap_response`, ONLY at `HTTPLogging::BODY`, with the one shared cap, and below the body level neither is constructed even when a cap is supplied (the body reaches the caller as the transport produced it, `assert_same`); the two 3b pins that read "nothing in core constructs a wrapper" now read "exactly one file does, `step.rb`". `BODY-22`'s first-access drain is what `#snapshot` triggers on the response event (`step_test.rb`, `BodyLevelTest`; 3b's two body suites) |
| `BODY-20` | MUST | ✅ placement | 15 | Cross-reference, phase 3b's ID: the request preview rides on the RESPONSE and FAILURE events, never the request event — `RequestLoggingBody` mirrors on WRITE and the write happens inside `cursor.call`, after the request event, so a preview read there is `""` on every request; the failure event carries "the bytes mirrored up to the failure point" (`step_test.rb`, `BodyLevelTest`) |
| `OBS-23` | MUST | ✅ keys, 5c's push | 6 | Cross-reference, 5c's ID: `Diagnostics::TRACE_ID` and `::SPAN_ID` are the Symbols 5c's `Tracing.correlate` pushes and `Scope#close` restores; this phase extended the file 5c created without adding a require, and 5c's `independence_test.rb` — the subprocess loading the ten 5c files by name and asserting `Event`, `Logger`, `Keys`, `Events`, `HTTPLogging`, `Step` and `Configuration` undefined — is unchanged and green, which is the structural proof that the logging half did not leak in behind `Tracing` (R11) |
| `PIPE-28` | MUST | ✅ share | 15 | Cross-reference, phase 4c's ID: `Step#stage` and `AsyncStep#stage` are both `Stages::LOGGING`, `AsyncStep < Step` inherits `.build` unchanged, both are installed with `builder.append(step)` and no `stage:`, both drive the cursor exactly once through `#call` and never `#fork` (asserted with a recording cursor whose `#fork` raises), and `Pipeline::Step.conforms?` accepts both |
| `NFR-11` | MUST | ✅ share | 4, 6 | Cross-reference, phase 9's ID: the two new interfaces have a home — `_Sink` in `null_sink.rbs` (the duck type, so no bundled-gem `Logger` constant ever appears in a public signature) and `_DiagnosticSnapshot` in `diagnostics.rbs` — every name in them a `Dexpace::` constant or stdlib; the step types its slots against 4a's `_TracerFactory` and 5c's `_Meter` by bare name and declares neither; `gates:rbs_surface` reports no foreign constant over the 142 mirrors |

## What was built

Fourteen new `lib/` files under `gems/dexpace-core/lib/dexpace/instrumentation/` and one extended in
place: `severity.rb`, `keys.rb` (`Keys`, `Events`), `null_sink.rb` (`NULL_SINK` and the private
`NullSink`), `render.rb` (private), `diagnostics.rb` (5c's file, gaining `.capture`, `.with`, `.folded`,
`RESERVED_PREFIX` and the `_DiagnosticSnapshot` interface in its `sig/`), `redaction_policy.rb`,
`redactor.rb`, `event.rb` (`Event`, `Event::INERT`, the private `Event::Inert`, `CollisionLatch` and — since
review round 1 — the private `ReservedKeys` table `Logger.build` and `Event` share),
`logger.rb` (`Logger`, `Logger::NULL`), `contain.rb` (`Instrumentation.contain` and `.diagnostic`),
`preview.rb`, `http_logging.rb`, `emitter.rb` (private), `step.rb` and `async_step.rb` (with its private
`Pending`). Every file has a `sig/` mirror — the two `private_constant`s with `hooks.rbs`'s comment,
because the strict `core` Steep target types their call sites — and every public file a `test/` mirror;
`render.rb` and `emitter.rb` have none, their contracts asserted through `Event` and the two steps (P2-15,
P4-3), which makes eleven `private_constant`s without a `test/` mirror in `dexpace-core`. Six files of
earlier phases widened, each a designed widening: `closeable.rb` (`close_quietly` gains `logger:`, the
second disposal route), `hooks.rb` (`notify` gains `logger:`, the per-dropped-failure diagnostic),
`proxy.rb` (`Proxy.resolve` gains `logger:`) and `proxy/resolution.rb` (the logger threaded to the three
methods that warn and the one `warn_and_nil` helper, which now emits the config diagnostic; one line over
`Metrics/ModuleLength`, recorded inline as `.rubocop.yml` prescribes), `configuration/keys.rb`
(`LOG_PREVIEW_BYTES`), and 5c's `diagnostics.rb` (above) — their five `sig/` mirrors widened with them. The
entry file gains a fourteen-line `# Phase 5b:` block after 5c's, in dependency order, with the note that
`closeable.rb`, `hooks.rb` and `proxy/resolution.rb` pull the front of the tree in ahead of it and that this
is not a cycle. `uri` is the one plain `require` the phase adds, in `redactor.rb`, already on the
allowlist; `set` is NOT required — Ruby 3.2, the floor, autoloads `Set`, and the cop set refuses the
redundant require — so the design's "requires exactly two entries" is one.

Fourteen new suites under `test/dexpace/instrumentation/` — twelve mirrors plus two without a `lib/` file
that say so, `logging_matrix_facts_test.rb` (the floor-straddling facts as a standing test) and
`downstream_wirings_test.rb` (the four wirings) — and 5c's `diagnostics_test.rb` rewritten as this phase's
mirror (its two constant cases, its Symbol-key case and its "requires nothing" pin kept; its "no method"
pin gone). Two new files under `test/support/`, both **top level**: `recording_sink.rb` (`RecordingSink`, a
real in-memory `_Sink` with per-severity enablement and the recorded entries) and `diagnostic_context.rb`
(`DiagnosticContext.preserve`, the save-and-restore block the floor-aware `FiberStorageFacts` does not
cover). 5c's `RecordingSpan`, `RecordingTracerFactory`, `RecordingTracer`, `RecordingMeter` and the two
instruments are consumed unchanged; so are 5a's `FakeClock` and `FakeConfigSource`, phase 2's
`FakeTransport`, `FakeAsyncTransport` and `WarningCapture`, and 5c's `AllocationDelta`. Five existing
tests changed, each a code-branch repair of a pin the code invalidated: the smoke suite `dexpace_test.rb`'s
instrumentation pin (thirteen constants become twenty-six, with the five new private ones asserted
unreachable), 5a's `configuration/keys_test.rb` (the eighth key), phase 2's `closeable_test.rb` (the
comment that asserted the drop), and phase 3b's `request_logging_body_test.rb` and
`response_logging_body_test.rb` ("nothing constructs a wrapper" becomes "exactly `step.rb` does"). The
surface manifest gains **100 rows, 856 to 956**, read row by row against the object model before the one
`surface:regenerate` was accepted: every `Keys` and `Events` constant as a ` : String` row (§8.1's
snapshot-coverage requirement), `Severity` with its four and `ALL`, `Event`'s four methods and `INERT`,
`Logger` with `.build`, `#event`, `#enabled?`, `#sink`, `#context` and `#redactor` and `NULL`, `NULL_SINK`,
`Diagnostics`' three functions and `RESERVED_PREFIX`, `RedactionPolicy` with its four readers, `.build` and
`DEFAULT`, `Redactor` with its four methods, `.build`, `DEFAULT` and the five markers, `Preview` with
`.render` and its two constants, `HTTPLogging` with its four constants, `#at_least?`, `#name`, `#order`,
`#with`, `.of`, `.parse` and `.resolve`, `Step` with `.build`, `#call` and `#stage`, `AsyncStep` with
`#call`, `Instrumentation.contain` and `.diagnostic`, and `Configuration::Keys::LOG_PREVIEW_BYTES` — no row
for any private constant, the private classes present only as the value type of a constant's row. The
gemspec is untouched: zero `add_dependency` lines. `docs/knowledge/notes/` gains nothing — no harvested
rule was found wrong, and the two facts the design got wrong (below) are the design's own —
`docs/first-release.md` gains nothing (its `OBS-32`/`OBS-37` and presence-gated entries already read true),
and `docs/deviations.md` is untouched for phase 10 to flip.

The gates, all seventeen, on **4.0.6** (`bundle exec rake`, 2026-09-17, re-run after review round 0's
repair, again after review round 1's and again after review round 2's, the same day) at the tests tip
and again at the docs tip: green, exit 0 — `cops:test` 129 runs, `steep` no type error over the strict
`core` target, `test:gems` **2,050 runs / 58,448 assertions** across the six gems (201 runs more than the
base: 173 across the fifteen new or rewritten instrumentation suites and the five repaired pins, one the
smoke suite gained, round 0's eight added tests, round 1's twelve and round 2's seven), with **99.98%
line coverage (5,655 / 5,656)** against the 80% floor — the one uncovered line is the registry-claim race branch every phase since 2 has recorded —
`test:gates` 130 runs, the nine `gates:*` tasks (`gates:require_allowlist` clean, 23 bundled gems known;
`gates:surface_snapshot` six manifests matching; `gates:rbs_surface` no foreign constant;
`gates:clean_bundle` six gems in isolation), `yard` 100.00% documented (665 methods, 0 undocumented),
`bundler_audit` clean. The honest RuboCop run —
`bundle exec rubocop --fail-level=convention --ignore-parent-exclusion` — inspected 401 files with no
offenses at the tests and docs tips and **385 at the code tip**, the run round 0's R0-2 asked for; run
through `rake` from this worktree it inspects 10, the known vacuity on phase 10's inbound list. The matrix
set is green at the tests tip on **3.2.11** (2,050 runs / 58,450 assertions; three seeds after the
repair, below), **3.3.12** (2,050 / 58,448, 99.98%) and **3.4.10** (2,050 / 58,448, 99.98%), each after a
fresh `Gemfile.lock`. The code tip is green on all seventeen gates too, run one by one — `test:gems`
1,849 runs / 56,768 assertions at 94.81% (5,363 / 5,656) on 4.0.6 and 1,849 / 56,765 at 94.81% (5,287 /
5,576) on 3.2.11 with the four matrix gates — so the one exception the layering rule allows was not
needed.
**Hermeticity**: every suite under `test/dexpace/instrumentation/`
— 5b's fifteen and 5c's fifteen — was run standalone under `ruby -w` with `HTTPS_PROXY`, `HTTP_PROXY`,
`NO_PROXY`, `LOG_LEVEL`, `LOG_PREVIEW_BYTES`, `MAX_TRACKED_CONTEXTS` and `MAX_MATERIALIZED_BYTES` exported
to hostile values (`http://evil:1`, `garbage`, `*`, `body`, `3`, `2`, `4096`): all green, because every
configuration a 5b test consults is built over `FakeConfigSource` seams. The whole core suite under the
same environment is green but for four phase-3b and phase-4b tests that assert the *default*
materialisation ceiling and read the live one through 5a's per-call `IO.max_materialized_bytes` (P5-56) —
not a 5b suite and not an environment read by one; routed below. With the ceiling exported *below* the
bodies the suites use (`MAX_MATERIALIZED_BYTES=3`, 5a's own value), the four 5b tests that materialise a
body through `Response#body_string` fail inside the body layer with `StreamError: refusing to materialize
100 bytes` exactly as 3b's do, which is the product honouring its configuration and not a hermeticity gap.
The standalone runs also found the one thing a single-process gate cannot: Ruby 3.4+'s "the block passed
to … may be ignored" warning under `-w`, on `NULL_SINK`'s four writers, which declared no block — item 27
below.

## Matrix facts, re-run on every interpreter

The design ran its thirteen facts on 3.4.10 alone and flagged facts 1, 2, 3, 6 and 9 for the floor and
the ceiling; the plan's Task 1 asked for them to be run before any code rested on them. All were re-run on
2026-09-17 on **3.2.11, 3.3.12, 3.4.10 and 4.0.6**, first as one script per interpreter and then as
`logging_matrix_facts_test.rb`, a standing test, with 5c's two floor facts (point 3 of the as-built list)
added.

| Fact | 3.2.11 | 3.3.12 | 3.4.10 | 4.0.6 |
|---|---|---|---|---|
| `Fiber[:k] = v` warnings | 0 | 0 | 0 | 0 |
| `Fiber[:k] = nil` deletes the key | **no** — `storage` reads `{k: nil}` | yes | yes | yes |
| `Fiber#storage=` warnings per call | 1 | 1 | 1 | 1 |
| `Fiber#storage = {"k" => v}` | `TypeError` | `TypeError` | `TypeError` | `TypeError` |
| `Fiber["k"] = v` (String key) | `TypeError` | `TypeError` | interned | interned |
| `Fiber.current.storage` fresh and unfrozen per read | yes | yes | yes | yes |
| `Fiber.new(storage: nil) { Fiber.current.storage }` | **`{}`** | `nil` | `nil` | `nil` |
| per-key union restore `== prior` | **no** — the introduced key stays, nil-valued | yes | yes | yes |
| `{a: nil, b: 1}` prior restores as | `{a: nil, b: 1, …}` (unchanged) | `{b: 1}` | `{b: 1}` | `{b: 1}` |
| `RFC3986_PARSER` raises on `not a url`, `https://h/a b`, `?a=%zz` (`#parse`) | yes | yes | yes | yes |
| `#parse("https://h/x?")` query / `("http://h/p#a?b=c")` query | `""` / `nil` | same | same | same |
| opaque `userinfo=` / `query=` | `URI::InvalidURIError` | same | same | same |
| `URI#to_s` of `http://h:80/` | **`http://h/`** | same | same | same |
| `decode_www_form_component("%FF").downcase` | `ArgumentError: input string invalid` | same | same | same |
| `("é" * 5000).byteslice(0, 8191)` valid / scrubbed | invalid / 4,095 chars, 8,190 bytes | same | same | same |
| `Symbol#name` identity-stable and frozen; `#to_s` not | yes | yes | yes | yes |
| BINARY→UTF-8 `"café".b.encode(UTF_8, …)` | `"caf��"` | same | same | same |
| retag-then-transcode of ISO-8859-1 `caf\xE9` | `"café"` | same | same | same |
| `Thread::Mutex` recursive / owned in child fiber | `ThreadError` / false | same | same | same |
| `Hash#inspect` of `{"a" => 1}` | `{"a"=>1}` | `{"a"=>1}` | `{"a" => 1}` | `{"a" => 1}` |
| `Class.new(StandardError).name` | `nil` | `nil` | `nil` | `nil` |
| inert chain, two-loop delta (Symbol / Integer / nil args) | 0 | 0 | 0 | 0 |
| a one-time cost inside a measured block of that delta, fresh process, test-order dependent (R2-4) | **7 or 28 objects, about 1 whole-file run in 15** (2 of 30; `-0.007`, `-0.028`) | not observed | not observed | not observed (0 of 30) |

Two of the flagged facts fail on the floor, both the ones 5c had already found (P5-72), and one fact the
design did not flag failed everywhere: `URI#to_s` drops a default port, which `OBS-14` forbids and which
is why the redactor reassembles from `split` (P5-91). The `storage: nil` row is the third floor difference
and is why `Diagnostics.capture` normalises both readings to `{}`. The last row is review round 2's
(R2-4) and is why 5c's `AllocationDelta` helper returns the figure two consecutive measurements agree on
(deviation 41): in one process the figure is stable — 200 back-to-back measurements on 3.2.11 all `0.0`
— and the cost lands once, early, inside whichever measurement runs first, which is test-order.

## The floor decision, stated once

`OBS-24`'s bridge and `OBS-10`'s null clause meet the 3.2 floor as follows, and the suite asserts it
floor-aware through 5c's `FiberStorageFacts` rather than for one interpreter. **Capture** drops nil-valued
keys (`Hash#compact!` on the fresh copy, P5-97), so a snapshot is the same shape on 3.2 — where every key
ever set and cleared with `= nil` is still present with a nil — as on 3.3+, where only the warned
`Fiber#storage=` can produce one; OBS-10 says a null-valued key is skipped, so it is not a diagnostic-context
value and does not belong in a snapshot. **Restore** stays one branchless assignment per key over the union
(P5-23): on 3.3+ it is exact, and on 3.2 a key the snapshot introduced is left present with a nil value —
the floor's whole `Fiber` API is `[]`, `[]=`, `storage` and `storage=`, and the only removal is the warned
setter core never calls — which is P5-72's residual applied to `OBS-24`: unobservable at `Fiber[]`, skipped
by the fold, visible only through `Fiber.current.storage.key?`, and `assert_diagnostic_key_removed` asserts
absent where `= nil` deletes and present-and-nil on the floor, never the installed value. **The fold** skips
a nil value in both modes on every row; on 3.2 that clause is live for every cleared key, on 3.3+ only for a
host that called the setter, and the test constructs that input through the setter inside phase 2's
`WarningCapture` on every row. `Diagnostics.with` merges the snapshot over the executing fiber's context
rather than replacing it — the observability note's pooled-worker entry says why the carrier must start
empty, and that is 8b's — so a settlement on the calling fiber sees the fiber's current keys underneath the
snapshot, and a settlement on a pool thread sees the pool thread's.

## Guards run red

Every guard the brief asks to be seen red was seen red, on 4.0.6 and on 3.2.11, and the bytes restored after
each: forty-eight single-edit mutations of `lib/`, one at a time, the owning suites re-run after each. On
the first 4.0.6 pass forty-four were caught; two mutations crashed the suite on an unused-variable warning
(`FatalWarnings`) rather than an assertion and were re-spelled to keep the variable live; and four stayed
green because the suite had a gap, which was closed and is the reason the four tests named in the
"Deviations from the plan" section exist — a sink re-entering the logger from INSIDE its write (guard 11),
the async path's header redaction (guard 25, which also found the two-redactor drift, P5-95), a recording
cursor whose `#fork` raises (guard 47), and the headers level with a cap supplied (guard 48). On the second
pass **all forty-eight are caught**, forty-seven by the suite named and one — an event name mutated — by
`keys_test.rb`, which is the guard §8.1 asks for: `step_test.rb` compares against the constant and stays
green by design. The 3.2.11 pass, run whole after the four gaps were closed, caught all forty-eight as
well, guards 12, 29, 30 and 31 through the floor branches of the floor-aware assertions.

| # | Fix reverted | Guard | What it said (4.0.6 unless stated) |
|---|---|---|---|
| 1 | `OBS-1`: `Logger#event` returning a fresh `Event` for a disabled severity | `logger_test.rb`, `event_test.rb` | `Expected #<Dexpace::Instrumentation::Event …> to be the same as #<…Event::Inert>` (5 failures) |
| 2 | `OBS-1`: `Inert#field` allocating one Array per call | `event_test.rb` | `Expected \|0.0 - 1.0\| (1.0) to be <= 0.0` — **on 4.0.6 and 3.2.11** |
| 3 | `OBS-2`: a fifth `FATAL` level appended to `ALL` | `severity_test.rb` | `--- expected [:error, :warning, :info, :verbose] +++ actual […, :fatal]` (2 failures) |
| 4 | `OBS-2`: `ALL` reordered most-verbose first | `severity_test.rb` | `--- expected +++ actual` on the four-element order |
| 5 | `OBS-3`: an empty key accepted (`required!` handed the empty String) | `event_test.rb` | `Dexpace::InvalidArgumentError expected but nothing was raised` |
| 6 | `OBS-6`: `Render.render`'s rescue removed | `event_test.rb` | 2 errors: `RuntimeError: no text` and the BasicObject `NoMethodError` |
| 7 | `OBS-6`: the nil guard on `Class#name` removed | `event_test.rb` | `Expected: "Class: anon" Actual: "[unrenderable Object]"` (2 failures) |
| 8 | `OBS-7`: the cap sliced in characters (`text[0, 8192]`) | `event_test.rb` | `Expected: 8204 Actual: 12014` |
| 9 | `OBS-7`: the cap off by one (`<` for `<=`) | `event_test.rb` | `--- expected "x" * 8192 +++ actual "x" * 8192 + "...[truncated]"` |
| 10 | `OBS-8`: the latch flipped without the mutex (a `Thread.pass` between read and write) | `event_test.rb` | `Expected: 1 Actual: 4` on the four-thread race |
| 11 | `OBS-8`: the mutex held across the sink call | `event_test.rb` | `ThreadError: deadlock; recursive locking` from the sink that re-enters the logger inside its write |
| 12 | `OBS-10`: the unfiltered fold keeping a nil-valued key | `diagnostics_test.rb` | `Expected true to not be truthy` on `folded.key?("a")` — **on 4.0.6 and 3.2.11** |
| 13 | `OBS-10`: `DEFAULT_KEYS` widened with `:tenant` | `diagnostics_test.rb` | `--- expected [:"trace.id", :"span.id"] +++ actual […, :tenant]` |
| 14 | `OBS-11`: the userinfo written back as given | `redactor_test.rb` | 4 failures, `Expected "https://***:***@example.com/…" Actual "https://alice:s3cret@…"` |
| 15 | `OBS-12`: `token` added to the default query allow-list | `redaction_policy_test.rb`, `redactor_test.rb` | `Expected: Set["api-version"] Actual: Set["api-version", "token"]`, then `token=***` expected |
| 16 | `OBS-12`: the parameter name matched case-sensitively (the fold dropped) | `redactor_test.rb` | 4 failures on `API-Version=2` and `Content-Type` |
| 17 | `OBS-12`: the parameter name matched undecoded | `redactor_test.rb` | `api%2Dversion=3` expected kept, actual `***` |
| 18 | `OBS-14`: the trailing `?` dropped for an empty query | `redactor_test.rb` | `Expected "https://example.com:8443/path?" Actual "…/path"` |
| 19 | `OBS-14`: the fragment written after `?` | `redactor_test.rb` | 5 failures, `Expected "https://h/p#access_token=***" Actual "https://h/p?access_token=***"` |
| 20 | `OBS-14`: the path folded | `redactor_test.rb` | `Expected "https://Example.COM:8443/A/b%20c?" Actual "…/a/b%20c?"` |
| 21 | `OBS-15`: the rescue narrowed to `URI::Error` | `redactor_test.rb` | `RuntimeError: policy exploded` escaping, plus the `%FF` case |
| 22 | `OBS-15`: the sentinel changed | `redactor_test.rb` | `Expected: "[malformed url]" Actual: "[bad url]"` (2 failures) |
| 23 | `OBS-16`: the relative branch dropping the path | `redactor_test.rb` | `Expected: "/p?***" Actual: "?***"` (2 failures) |
| 24 | `OBS-16`: the relative branch keeping the query | `redactor_test.rb` | `Expected: "/p?***" Actual: "/p?t=1?***"` |
| 25 | `OBS-17`: the async step emitting its response through a second emitter over a second logger with an empty `url_header_names` | `async_step_test.rb` | `Expected: "/cb?***" Actual: "/cb?code=SECRET"` — the `Location` unredacted on the async path (3 failures, 1 error: the second emitter also skips the bridge and the containment) |
| 26 | `OBS-18`: `authorization` added to the header allow-list | `redaction_policy_test.rb`, `step_test.rb` | `Expected true to not be truthy` on the name, then `Bearer` found in the payload |
| 27 | `OBS-20`: the containment removed | `contain_test.rb`, `step_test.rb` | `ArgumentError: primary error` and `IOError: sink write failure` escaping (7 errors) |
| 28 | `OBS-20`: the secondary rescue removed | `contain_test.rb`, `step_test.rb` | `StandardError: sink failure` escaping from the diagnostic (3 errors) |
| 29 | `OBS-24`: the snapshot returned unfrozen | `diagnostics_test.rb` | `Expected {"trace.id": "t1"} to be frozen?` — **on 4.0.6 and 3.2.11** |
| 30 | `OBS-24`: the reinstall through `Fiber#storage=` | `diagnostics_test.rb` | `RuntimeError: warning treated as an error (NFR-6): … Fiber#storage= is experimental` (3 errors) — the warning fails the suite, as required; **on 4.0.6 and 3.2.11** |
| 31 | `OBS-24`: the restore outside the `ensure` | `diagnostics_test.rb` | `Expected: "before" Actual: "t2"` after the raise — **on 4.0.6 and 3.2.11** |
| 32 | `OBS-34`: the span skipped at level `none` | `step_test.rb` | `Expected: 1 Actual: 0` on `factory.tracers.size` |
| 33 | `OBS-34`: the counter skipped at level `none` | `step_test.rb` | 3 failures: `StandardError expected but nothing was raised` (the throwing meter) and the record counts |
| 34 | `OBS-35`: `.resolve` falling back to a baked key name | `http_logging_test.rb`, `configuration/keys_test.rb` | `ArgumentError expected but nothing was raised`, and 5a's scan: `Expected […/http_logging.rb] to be empty` |
| 35 | `OBS-35`: the chain read through `raw_property` (tiers reordered) | `http_logging_test.rb` | `Expected HEADERS to be the same as NONE` on the environment and override tiers |
| 36 | `OBS-36`: the preview cap replaced by a million | `step_test.rb` | `--- expected "S" * 16 +++ actual "S" * 100` |
| 37 | `OBS-36`: a nil cap accepted at `BODY` | `step_test.rb` | `Dexpace::InvalidArgumentError expected but nothing was raised` |
| 38 | `OBS-38`: the decode transcoding from BINARY (§3.1's form) | `preview_test.rb` | 4 failures, `Expected: "café" Actual: "caf�"` |
| 39 | `OBS-38`: the binary branch decoding instead of marking | `preview_test.rb` | `Expected: "[binary 2 bytes captured]" Actual: "ok"` |
| 40 | `OBS-39`: `url.full` stored unredacted | `event_test.rb`, `step_test.rb` | `Expected: "[malformed url]" Actual: "not a url"`, and `token=secret` in the payload |
| 41 | `OBS-39`: `Events::HTTP_RESPONSE` renamed | `keys_test.rb` | `Expected: "http.response" Actual: "http.reply"` (`step_test.rb` green by design: it compares against the constant) |
| 42 | `OBS-40`: the latch dropped (warn on every collision) | `event_test.rb` | `--- expected [:info, :info, :debug, :info, :info, :info] +++ actual […, :debug, …, :debug, …]` |
| 43 | `close_quietly`'s second route dropping the error | `downstream_wirings_test.rb` | `Expected: 1 Actual: 0` on the close diagnostic |
| 44 | `Hooks.notify`'s diagnostic replacing the trail | `downstream_wirings_test.rb` | `--- expected ["ArgumentError", "RuntimeError"] +++ actual []` on the trail |
| 45 | `Proxy.resolve`'s event without the warning | `downstream_wirings_test.rb`, 5a's `proxy_test.rb` | `Expected: 1 Actual: 0` on the warning count (9 failures) |
| 46 | `LOG_PREVIEW_BYTES` renamed to a dotted name | `downstream_wirings_test.rb`, `configuration/keys_test.rb` | `Expected: "LOG_PREVIEW_BYTES" Actual: "log.preview.bytes"` |
| 47 | the step forking before calling (`cursor.fork.call`) | `step_test.rb` | `RuntimeError: forked with nil` from the recording cursor |
| 48 | the response wrapper constructed at `HEADERS` (`if logged?`) | `step_test.rb` | `Expected #<Dexpace::ResponseLoggingBody …> to be the same as #<Dexpace::BufferBody …>` |

After review round 0's repair (2026-09-17), one per line the repair made load-bearing, each applied
by hand against the repaired suites and reverted, **on 4.0.6 and on 3.2.11** — all ten caught on both.

| # | Fix reverted | Guard | What it said (identical on both rows unless stated) |
|---|---|---|---|
| 49 | `OBS-11` (R0-3): the relative route returning the raw value when it carried neither query nor fragment | `redactor_test.rb`, `step_test.rb` | `Expected: "//***:***@h/x" Actual: "//user:secret@h/x"`; through the pipeline, `Expected "//user:secret@evil/x" to include "***:***@"` |
| 50 | `OBS-11` (R0-3): the surgery route without the userinfo substitution | `redactor_test.rb`, `step_test.rb` | 2 failures, `Expected: "http://***:***@h/p x" Actual: "http://user:secret@h/p x"`; through the pipeline, `Expected "http://user:secret@evil/p x" to include "***:***@"` |
| 51 | `OBS-11` (R0-3): the relative route writing the userinfo back as given | `redactor_test.rb` | 2 failures, `Expected: "//***:***@h/x" Actual: "//user:secret@h/x"` |
| 52 | `OBS-12` (R0-7): the decode's rescue removed, a bad name sentinelling again | `redactor_test.rb` | `--- expected "https://h/p?%zz=***&api-version=2&b=***" +++ actual "[malformed url]"` |
| 53 | `OBS-15` (R0-8): the opaque component written back verbatim | `redactor_test.rb` | `--- expected "mailto:support@example.com?subject=***" +++ actual "…?subject=SECRET"` |
| 54 | `OBS-11` (R0-3): the surgery pattern stopping at the FIRST `@` | `redactor_test.rb` | `Expected: "http://***:***@h/p x?***" Actual: "http://***:***@b@h/p x?***"` |
| 55 | `OBS-18` (R0-4): `Event#field` storing a non-allow-listed header's value | `event_test.rb`, `step_test.rb`, `async_step_test.rb` | `Expected: "REDACTED" Actual: "Bearer sk-live-1"` (3 failures), and both steps' `Authorization` cases |
| 56 | `OBS-18` (R0-4): `Event#field` ignoring omit mode (always the marker) | `event_test.rb`, `step_test.rb` | `--- expected {"…accept" => "text/html"} +++ actual {…, "…authorization" => "REDACTED"}`; through the step, `Expected true to not be truthy` |
| 57 | `OBS-18` (R0-4): `Event#field` omitting in marker mode (never storing the marker) | `event_test.rb`, `step_test.rb`, `async_step_test.rb` | `Expected: "REDACTED" Actual: nil` (2 failures), and both steps' cases |
| 58 | `OBS-18` (R0-4): the `Emitter` skipping every header (the gate mis-moved) | `step_test.rb`, `async_step_test.rb` | 5 failures, `Expected: "text/plain" Actual: nil`; `Expected: "REDACTED" Actual: nil` |

After review round 1's repair (2026-09-17), one per line the repair made load-bearing and one per
mutation the round reported surviving, each applied by hand against the repaired suites and reverted,
**on 4.0.6 and on 3.2.11** — all ten caught on both.

| # | Fix reverted | Guard | What it said (identical on both rows unless stated) |
|---|---|---|---|
| 59 | `OBS-11` (R1-1): the parseable-URL warning showing the raw URL | `downstream_wirings_test.rb` | `Expected "[dexpace] proxy URL \"http://user:secret@proxy.corp\" has no explicit port; …" to include "***:***@"` |
| 60 | `OBS-11` (R1-1): the not-a-URI warning showing the raw URL | `downstream_wirings_test.rb` | 2 failures, `Expected "[dexpace] proxy URL \"http://user:secret@proxy.corp:abc\" is not a URI" to include "***:***@"` |
| 61 | `OBS-11` (R1-1): the resolver's grammar rule removed (the redactor's form alone) | `downstream_wirings_test.rb` | `Expected "[dexpace] proxy URL \"user:secret@proxy.corp:3128\" has no explicit port; …" to include "***:***@"` |
| 62 | `OBS-39`, `OBS-18` (R1-2): the context not scrubbed at `Logger.build` | `event_test.rb` | 2 failures, `Expected: "https://***:***@h/p?sig=***&api-version=2" Actual: "https://user:secret@h/p?sig=S&api-version=2"` |
| 63 | `OBS-39`, `OBS-18` (R1-2): the fold not scrubbed at `#emit` | `event_test.rb` | 2 failures, `"url.full" => "https://user:secret@h/p?sig=S", "http.request.header.authorization" => "Bearer FIBSECRET"` in the record |
| 64 | `OBS-18` (R1-2): `ReservedKeys.scrub!` never deleting (omit mode ignored on the ambient sources) | `event_test.rb` | 2 failures, the `OMIT` sentinel itself in the record: `"http.request.header.authorization" => #<Object:…>` |
| 65 | `OBS-11` (R1-3): `SURGERY_USERINFO` re-anchored at the scheme | `redactor_test.rb`, `step_test.rb` | `Expected: " http://***:***@h/p" Actual: " http://user:secret@h/p"`; through the pipeline, `Expected " http://user:secret@evil/x?***" to include "***:***@"` |
| 66 | `OBS-38` (R1-4): `Preview.decode`'s fallback removed | `preview_test.rb`, `step_test.rb` | `Encoding::ConverterNotFoundError: code converter not found (UTF-7 to UTF-8)`; through the step, `--- expected ["http.request", "http.response"] +++ actual ["http.request", "http.instrumentation.log"]` |
| 67 | `OBS-24` (R1-5): the async FAILURE event not bridged (a bare `log_failure` in `AsyncStep#settle`) | `async_step_test.rb` | `Expected: "caller_trace" Actual: "settler_own"` — the mutation that survived round 1, now caught |
| 68 | `OBS-39`/`BODY-35` (R1-6): the `-1` declared-size guard removed | `step_test.rb` | `no request size for -1` — the mutation that survived round 1, now caught |

Two of the round's findings had no line of `lib/` behind them and have no mutation. R0-1 — fact 3 of
`logging_matrix_facts_test.rb` order-dependent on the 3.2 floor, where every teardown's
`Fiber[OTHER] = nil` is retained and "`storage == prior` iff `= nil` deletes" held only when the test
ran first — is proven by the matrix set green on 3.2.11 with seeds 9818, 1 and 42 and standalone, and by
the old spelling reproducing the failure on seed 9818 against the repaired tree; the assertion now states
the row's expected map (`prior` where `= nil` deletes, `prior.merge(OTHER => nil)` on the floor). R0-2 —
a 102-character line in the code branch's minimal-repair `diagnostics_test.rb`, visible only to the
honest RuboCop command from a nested worktree — is proven by that command clean at the code tip (385
files, no offenses).

After review round 2's repair (2026-09-17), one per line the repair made load-bearing and three of the
earlier guards re-spelled on the moved lines, each applied by hand as a single edit against the repaired
suites and restored from a byte copy, **on 4.0.6 and on 3.2.11** — all eight caught on both.

| # | Fix reverted | Guard | What it said (identical on both rows unless stated) |
|---|---|---|---|
| 69 | `OBS-11` (R2-1): the surgery substituting the FIRST `//`-authority only (`gsub` → `sub`) | `redactor_test.rb`, `downstream_wirings_test.rb` | the doubled proxy URL: `Expected: "http://***:***@proxy.corp:3128http://***:***@proxy.corp:3128" Actual: "http://***:***@proxy.corp:3128http://user:secret@proxy.corp:3128"`; `QuotedProxyTest`, 1 failure |
| 70 | `OBS-11` (R2-1): `SURGERY_USERINFO` anchored at the start of the value (`\A//`) | `redactor_test.rb`, `step_test.rb`, `downstream_wirings_test.rb` | 4, 4 and 3 failures: `Expected: "http://***:***@h/p x" Actual: "http://user:secret@h/p x"`; through the pipeline every prefixed `Location` leaking; `Expected "proxy URL \"\\"http://user:secret@proxy.corp:3128\\"\" is not a URI" to include "***:***@"` |
| 71 | `OBS-17` (R2-2): an `Array` header value joined BEFORE the redaction | `step_test.rb`, `event_test.rb` | `Expected: "https://***:***@a/x, https://***:***@b/y?code=***" Actual: "https://***:***@a/x, https://user:secret@b/y?***"`; at `#field`, the same shape |
| 72 | `OBS-20` (R2-3): the settlement work registered on the DERIVED future at `BODY` | `async_step_test.rb` | `[StandardError, :body] expected but nothing was raised` — the meter's failure swallowed by `Future#then`'s rescue |
| 73 | `OBS-20` (R2-3): the head tearing down again when the inline settlement raised (a `rescue` around `attach` re-running `finish`) | `async_step_test.rb` | `Expected: 1 Actual: 2` on the counter's adds and the span's finishes |
| 74 | `OBS-11`: the surgery route without the substitution (round 1's M37, re-spelled on the `gsub`) | `redactor_test.rb`, `step_test.rb`, `downstream_wirings_test.rb` | 5, 4 and 3 failures, every surgery-route userinfo written back |
| 75 | `OBS-11`: the userinfo written back as given on the parsed routes (guard 14 re-run) | `redactor_test.rb`, `step_test.rb`, `event_test.rb` | 13 failures, `Expected "https://***:***@…"` |
| 76 | `OBS-1`: `Inert#field` allocating one Object per call (guard 2 re-run through the changed helper) | `event_test.rb` | `Expected \|0.0 - 1.0\| (1.0) to be <= 0.0` — the agreement rule returns the real per-call cost, not a noise figure |

The round's fourth finding, R2-4, is the suite's own and has no mutation beyond guard 76: it is proven by
60 whole-file `event_test.rb` runs on 3.2.11 under random seeds failing none after the helper change,
where 2 of 30 failed before it with the negative figures the row above records, and by 5c's five
allocation suites (`meter_test.rb`, `http_tracer_test.rb`, `no_span_test.rb`, `no_tracer_test.rb`,
`tracing_test.rb`) green on 3.2.11 and 4.0.6 through the same helper.

## Audit groups run

The phase-start pair first, at implementation: `--origin note --brief` returned 53 note entries across 21
files; `--section conflicts --brief` returned 19 note entries and 6 harvested conflicts, every harvested
one `[overridden by notes/…]` and none open. `--req` was run for each task's IDs before that task; every
phase-5 `OBS` ID returned its appendix-B roll-ups beside a substantive `observability/…` or
`redaction-and-security/…` rule, as the design measured, and the three-step roll-up path was the normal
reading mode — appendix C's rows for the twenty-eight IDs were read verbatim, and chapter 15's per-ID
`*Conformance:*` clauses with them. The observability note's newest entry
(`sha:manual-phase5c-fiber-nil-and-string-key-floor`) was read before Task 6 and is what the floor decision
above rests on. The nine groups the design ran at planning are recorded there; at implementation the four
it names for the plan were re-checked against the built code:

| Group | Result at implementation |
|---|---|
| Public API surface | `module-organization/1828a984` (one public constant per file) holds for every new file — `keys.rb` carries two modules by design, `Keys` and `Events`, which the design fixes; `api-design/b0e18938` is why `NullSink`, `Inert`, `CollisionLatch`, `Render`, `Emitter`, `Pending` and the three default sets are private and every public name is in P5-16, P5-17 or P5-91–P5-99; `api-design/6ea28c9c` is overruled at exactly the two places the design names (`Redactor#header_value` returns `""` for nil; `diagnostic_keys: nil` is a mode) |
| RBS / Steep typing | Fourteen new mirrors and six widened, the strict target green; the sink typed `_Sink & Object` and the span `untyped` where the step passes what a tracer returns to what `Tracing` takes (5c's identity device); `type-system/545949a5` governs `Severity` and `HTTPLogging` as frozen `Data` closed sets over a table |
| Minitest conventions | Every suite subclasses `DexpaceTestCase`, every "never throws" claim is asserted on the substituted value and never with `assert_nothing_raised` (`testing/26b866e1`), `assert_same` wherever identity is the claim, every `Fiber[]` slot restored through `DiagnosticContext.preserve` or a shared `teardown`, five suites split into nested classes under `Metrics/ClassLength` |
| Fiber scheduler, thread safety | One `Thread::Mutex` in the phase, held across a flag flip and nothing else (`concurrency-and-async/f414b864`); no thread started in `lib/`, no wait, no `Timeout.timeout`, `Thread#raise` or `Thread#kill`; `Thread.current[]` written nowhere; `Fiber#storage=` written nowhere in `lib/` and exactly twice in `test/` (both inside `WarningCapture`, both constructing the nil-valued input) |

## Deviations from the plan

Departures from the plan's text, each with its reason. None lowers, disables or narrows a gate. Items 1–13
are where the built tree overrode the plan's assumptions, in the order the brief's as-built list gives
them; the rest are this build's and the two review rounds', and the ones that touch public behaviour are
also ledger rows P5-91–P5-106.

1. **The base is the reconciled 5c docs tip, not `main`**, and the plan's interleaved order collapsed to
   Tasks 1–16 straight through; nothing here describes 5a or 5c as landed on `main`.
2. **`diagnostics.rb` existed and was extended in place** (P5-71): `.capture`, `.with`, `.folded`,
   `RESERVED_PREFIX` and the `_DiagnosticSnapshot` interface added, no `require` added (5c's
   `independence_test.rb` loads the file by name and is unchanged and green), its line in the entry file
   left where 5c put it, and 5c's mirror rewritten as this phase's — the "no method" pin gone, the
   "requires nothing" pin kept — a code-branch repair of a pin the code invalidated, like the other five.
3. **The floor facts 5c found were re-run and decided**, as the floor decision above states (P5-97):
   capture compacts, restore stays branchless, the fold skips, and the plan's Task 1 fallback — "delete
   explicitly" — has nothing to delete with on 3.2.
4. **5c's surfaces as built were used, not the plan's fences**: `_Meter#create_counter`/`#create_histogram`
   (not `#counter`/`#histogram`), `#add(amount, attributes: nil)`, `#record(amount, attributes: nil)`,
   `Tracing.correlate(span, bundle)` returning a `_Scope`, `_Span#finish`, and 4a's `#tracer(name:)`; no
   `**` splat anywhere; `NO_TRACER_FACTORY` and `NO_METER` are the two slot defaults (P5-33).
5. **5c's doubles were consumed unchanged** by their `Dexpace::Recording*` names (P5-73), with
   `factory.tracers`, `span.finished_at`, `meter.counters`/`#histograms` and the `{amount:, attributes:}`
   record shape; `AllocationDelta` replaced the plan's inline measurement and `FiberStorageFacts` the
   plan's floor probes.
6. **5a's surfaces as built**: `Configuration#integer` resolves the cap, `Proxy.resolve` takes its
   configuration positionally and now `logger:`, `ProxyResolution#warn_and_nil` is the one helper the
   event goes through, `Clock::SYSTEM#monotonic` measures the duration, and the plan's `resolve_from_env`
   never existed.
7. **Hermeticity**: every `Configuration` in 5b's suites is built over `FakeConfigSource` seams; no test
   reads `Sources::ENVIRONMENT`. The plan's `Dexpace.configuration.derive` fixture would have read the
   process environment and is not used.
8. **The two doubles are top level** — `RecordingSink`, `DiagnosticContext` — not `Dexpace::…` as the plan
   wrote (P5-98): twenty-six of the thirty support files the base carries are, 5a went top level after the
   plan was written (P5-58), and 5c's four files — its seven doubles — are namespaced only because this plan
   consumed them by those names.
9. **The two `private_constant`s get a `sig/` mirror and no `test/` mirror** (P2-15, P4-3): the plan's
   `render_test.rb` is not written; `Render`'s contract is asserted through `Event#field`/`#emit`, and
   `Emitter`'s through the two steps.
10. **Eight custom cops exist and 5b adds none.** The plan's Task 10 amendment — a bare-`Logger` watch
    inside `Dexpace/QualifiedCoreConstant` — cannot be written in that cop's shape and, examined against
    the built tree, guards nothing: the cop's model is "`Dexpace::X` shadows `::X` for a bare `X` anywhere
    inside `module Dexpace`", and this constant is `Dexpace::Instrumentation::Logger`, not
    `Dexpace::Logger`, so a bare `Logger` from anywhere inside `module Dexpace` but outside
    `module Instrumentation` still resolves to Ruby's (verified by lexical lookup: `Dexpace::Transport::Logger`,
    `Dexpace::Logger`, then `::Logger`). The shadow is confined to the `Instrumentation` namespace, where
    core never loads the stdlib `Logger` (boundary 1) and the bare name can mean nothing else; a watch there
    would flag every correct reference. P5-38's mitigations stand: `NULL_SINK` not `NullLogger`, and every
    reference from outside the namespace written `Instrumentation::Logger`. Recorded in P5-38's as-built
    note; no cop, no SHADOWED entry.
11. **`require "logger"` appears nowhere**, in `lib/`, `test/support/` or a test: the sink duck type is
    asserted against `RecordingSink` and hand-rolled stubs; the stdlib-`Logger` proof is
    `dexpace-conformance`'s (phase 8a). `require "set"` is not written either (item 19).
12. **4c's pipeline surface as built**: both steps declare `#stage` and are installed with
    `builder.append(step)`; both drive once through `Cursor#call` and never fork, asserted with a recording
    cursor; `AsyncPipeline.map_response` is NOT what the async step rides — it closes the response after the
    block, which is a terminal operator's job and not a step's — the step uses `Future#then` directly at
    the body level (item 15).
13. **4b's primitives as built**: `raise` after the failure event re-raises the rescued error itself (no
    `cause:` reassignment arises, because the error was just rescued, not carried); `Hooks.notify` keeps
    its `raise failure, cause: nil`; `Dexpace.attach_suppressed` is the trail's writer and the diagnostic
    is emitted beside it.
14. **The redactor reassembles from `RFC3986_PARSER.split`'s nine raw components** rather than assigning
    `userinfo=`/`query=`/`fragment=` and calling `#to_s` (P5-91): `URI#to_s` drops a default port, which
    OBS-14 forbids and the plan's fence would have failed on `http://h:80/`; the raw port is readable only
    from `split` (5a's resolver found the same); and the opaque-URI raise becomes unreachable by
    construction rather than by guard, so P5-27's rule has no setter left to apply to. `split` accepts a
    bad percent-encoding in a query VALUE where `#parse` rejects it; the value is redacted rather than
    sentinelled, and the test says so.
15. **`AsyncStep` closes the scope at the end of the synchronous head and bridges the diagnostic context
    into the settlement** (P5-93), and **returns a derived future at the body level** (P5-94): the plan's
    `scope&.close` in the settlement callback would write the settling fiber's storage rather than the
    caller's, and OBS-36's "every byte to the caller" needs the wrapped response to reach the caller,
    which only `Future#then` — which 4c added after the design's verified fact 13 — can carry. The plan's
    `rescue ::Exception` with a RuboCop disable is not written: the head is a private method whose
    `begin`/`ensure` tears down only when it raised before the chain handed back its future (since review
    round 2, P5-109; an `attached` flag before that), and `AsyncDriver` normalises a step's synchronous
    `StandardError` into a failed future anyway. The plan's `FakeFuture`/`FakeAsyncCursor` are not written; the real
    `AsyncPipeline` over phase 2's `Completer` and `Future` is driven, with `FakeAsyncTransport`'s
    `settle_later` separating the head from the settlement.
16. **One redactor per logging path, the logger's** (P5-95): `Step.build` takes no `redactor:` keyword,
    `Logger` gains a public `#redactor` reader, and the emitter read its header-name gate from it. Found
    by guard 25 against the plan's shape, in which the step's redactor gated names while the logger's
    redacted values — two policies where OBS-17 asks for one. Since review round 0 the emitter reads no
    gate at all (item 30); the reader stays public as the path's one observable policy.
17. **`Instrumentation.diagnostic(logger, event:, cause:, message:)`** is a second public module function
    beside `contain` (P5-92): the three wirings and phase 8b's shutdown event share one contained
    diagnostic shape, and writing it three times pushed 5a's `ProxyResolution` past `Metrics/ModuleLength`.
    The wirings call it in one line each.
18. **`Keys::MESSAGE` is the sixteenth key** (P5-96): the configuration diagnostic carries a message and no
    throwable, and an emitted field key outside the vocabulary is what OBS-39 forbids; the design's
    fifteen were written before the config wiring's shape was.
19. **The truncation marker is ASCII**, `"...[truncated]"` (P5-96): the design's `"…[truncated]"` raises
    `Encoding::CompatibilityError` when appended to a BINARY rendering with high bytes; a non-ASCII-
    compatible String is transcoded to UTF-8 first. **`require "set"` is not written**: Ruby 3.2 autoloads
    `Set` and `Lint/RedundantRequireStatement` refuses it, so the phase requires one allowlisted entry, `uri`.
20. **`Severity` and `HTTPLogging` make `.new` and `.[]` both private and refuse `#with`** (the `Stage`
    shape, P4-32), where the plan's fences made only `.new` private and left `Data#with` reachable — on
    3.2 a `Data#with` skips the validating initialize.
21. **`Logger.build` validates**: a sink missing any of the eight methods is refused naming the first
    missing one, a non-Hash context and a non-list key list likewise; the plan's fence accepted anything.
    `Event.send(:new, …)` is 4c's `Cursor.send(:new, …)` precedent and appears only in `Logger#event`;
    every event in the suites is obtained from a `Logger`.
22. **`Event`'s collaborators are keywords**, not the plan's seven positionals (`Metrics/ParameterLists`
    caps positionals at four); the OBS-40 latch is a private `CollisionLatch` under the logger's mutex, not
    a `[false]` array; the collision message is a String at the sink's `#debug`.
23. **The step names its span and tracer by the request's method token** (P5-99), because the operation
    name — 4a's `RequestContext#operation_name` — is unreachable from a step until phase 6a's Task 8; the
    plan's `respond_to?(:context)` probes are not written, since `Request` has no `#context` and the
    branch would be dead code with no test.
24. **Multi-valued headers are one field, joined with `", "`**, and names are folded through
    `Headers#names` rather than `#each_entry`'s original casing; the plan's per-entry loop would have
    overwritten one value with the next.
25. **The four suite gaps the guards found were closed** (a sink re-entering the logger inside its write; the
    async path's `Location`/`Authorization` redaction; a recording cursor whose `#fork` raises; the headers
    level with a cap supplied), and **five existing tests changed**, all on the code branch: the smoke
    suite's instrumentation pin, 5a's `keys_test.rb` list and count, phase 2's `closeable_test.rb` comment
    (the plan's "phase 4b's test name" does not exist in the tree; only phase 2's comment did), and phase
    3b's two "nothing constructs a wrapper" pins, re-pinned to "exactly `step.rb` does".
26. **Counts**: fourteen new `lib/` files (fifteen touched with `diagnostics.rb`), 141 under `lib/dexpace/`
    with `version.rb`, 142 `sig/` mirrors, eleven `private_constant`s without a `test/` mirror, eleven
    checklists, the manifest 956 rows; 5a's `ProxyResolution` carries an inline `Metrics/ModuleLength`
    exception with its reason.
27. **`NullSink`'s four writers declare an anonymous `&` they never yield.** The design's shape — a
    message parameter and no block parameter, "the block never evaluated" — warns under `-w` on Ruby 3.4
    and later: "the block passed to 'NullSink#debug' may be ignored". The warning is suppressed
    process-wide once any same-named method that takes a block has been compiled, so `test:gems` (one
    process, `RecordingSink` loaded) can never see it and `null_sink_test.rb` run alone under `ruby -w`
    does; measured 2026-09-17 on all four interpreters, an anonymous `&` that is never referenced
    materialises no Proc (0.0 objects per call), so `OBS-1`'s zero-allocation write holds, and
    `block_given?` in the body does NOT count as use. The RBS already declared the block optional. The
    gap in the gate's reach is the forty-first inbound bullet.

Items 28 through 31 are review round 0's (2026-09-17), each fixed on the owning branch of the stack;
the first three are also the as-built rows P5-100–P5-102, and each is a place where the build read a
requirement more narrowly than its text or put a gate one object away from where the requirement's
"whoever the caller is" needs it:

28. **`OBS-11` on every route of `Redactor#header_value`** (P5-100, R0-3). The design's R9 table
    considered a relative value's path, query and fragment and never its authority, so a network-path
    reference (`//user:secret@h/x`) was "returned verbatim" by `OBS-16`'s letter, an authority the parser
    rejected survived the surgery cut, and the sentinel fallback ran that same surgery on the raw value —
    three routes on which a hostile `Location`, admitted by the default allow-list, carried a credential to
    the sink. The relative route now rebuilds the authority from the split components with the
    placeholder; the surgery route substitutes an authority's userinfo first, through an anchored, linear
    `Regexp` with a per-pattern timeout (`SURGERY_USERINFO`, a `private_constant`), up to the LAST `@`
    before the first `/`, `?` or `#`; and the collision between the two MUSTs is resolved for `OBS-11`,
    the clause with no exception in it, and stated in the source, the `OBS-16` row and the ledger. A
    scheme-shaped `user:pw@h/p` with no `//` has no authority under RFC 3986 on either entry point and is
    not a userinfo; the tests say so.
29. **A bad percent-encoding in a parameter NAME is unmatchable, and an opaque URI's query-shaped tail
    is redacted** (P5-101, R0-7 and R0-8). `URI.decode_www_form_component` raises `ArgumentError` on
    `%zz`, and the round-0 redactor let that reach `#url`'s totality rescue, sentinelling a parseable URL
    for one broken name and giving `#header_value` its third leak route; the decode is now rescued alone
    (`decode_name`, nil for a rejected name, the policy read left to `#url`'s backstop) and the name
    default-denies to `***`, the direction `%FF` already took. The pinned parser folds `?query` into the
    opaque component while splitting the fragment out, so `mailto:a@b?subject=SECRET` round-tripped
    with its query; the part after the first `?` now takes `OBS-12`'s rule and the address before it —
    not a userinfo — is written back as is. P5-27's rule is untouched: nothing absent is written.
30. **`OBS-18`'s name gate is structural at `Event#field`** (P5-102, R0-4). The design's reserved-key table
    routed a header-prefixed key through `Redactor#header_value` only, and P5-35 placed the boolean's
    effect in the `Emitter`, so a credential header written straight into `#field` — by an SDK author,
    never by the step — logged its value, and the as-built page demonstrated exactly that. The gate now
    runs at `#field` by the reserved prefix — marker or omission per the policy's boolean, the same answer
    for a caller and for the step — and the `Emitter` writes every header and gates nothing, which
    removes the second reader of the policy rather than adding a second gate. `Logger#redactor` stays
    public (P5-95's one policy per path, now observable rather than consulted by core). The redactor
    itself grew past `Metrics/ClassLength`'s default by items 28 and 29 and records the exception inline
    with its reason, as `.rubocop.yml` prescribes and as 5a's `ProxyResolution` does.
31. **Two test-side repairs with no line of `lib/` behind them** (R0-1, R0-2): fact 3 of
    `logging_matrix_facts_test.rb` asserted "`storage == prior` iff `= nil` deletes", which on the 3.2
    floor held only when the test ran first, because every earlier teardown's `Fiber[OTHER] = nil` is
    retained there — the report's 3.2.11 green was one seed in thirteen; the expected map is now stated
    per row. And the code branch's minimal-repair `diagnostics_test.rb` carried a 102-character line that
    `rake rubocop` from a nested worktree cannot see (the inbound list's vacuity) and the honest command
    can; wrapped, so the code tip is green on `NFR-7` on its own tree, as the layering rule requires. Two
    documentation slips the round filed beside them (R0-5, R0-6) are fixed in place on the docs branch:
    the as-built page's fence 8 read the `span.id` fence 5 had left in the carrier when the fences ran
    top to bottom in one process — fence 5 now clears what it set, and the sixteen fences run as one
    script with every literal result checked, 116 checks on 4.0.6 and 3.2.11 — and the roadmap's status
    note counted twenty-six departures where this list itemised twenty-seven, now thirty-one.

Items 32 through 37 are review round 1's (2026-09-17), each fixed on the owning branch of the stack;
the first four are also the as-built rows P5-103–P5-106:

32. **The proxy warning names the URL through the redactor** (P5-103, R1-1). 5a's `split_url`
    interpolated the raw proxy URL into both of its warnings, and `URI::InvalidURIError#message` repeats
    the value it rejected; this phase's config diagnostic carried that text under `Keys::MESSAGE`, which
    the table does not reserve, so `HTTPS_PROXY=http://user:secret@proxy.corp` — the no-port
    misconfiguration `CFG-25` refuses — wrote `user:secret` into the sink through core's own code, on
    every malformed-URL path. The resolver now renders the URL once, through
    `Redactor::DEFAULT#header_value`'s total form and then `CFG-24`'s own grammar rule for a value with no
    `//` (`user:secret@proxy.corp:3128`, an opaque URI with no userinfo under RFC 3986, shows as
    `***:***@proxy.corp:3128`); the parser's message is no longer quoted. The backstop's
    `error.message` was examined and left: the one decoder that names its input, `URI.decode_uri_component`,
    is reached only after `split` accepted the userinfo, and `split` rejects the bad percent-encoding
    first. `resolution.rb` was already in Task 14's edit set; 5a's `proxy_test.rb` is untouched and green.
33. **The reserved-key table is `ReservedKeys`, applied to all three of `OBS-5`'s sources** (P5-104,
    R1-2). Round 0 closed the `#field` entry point and left the context and the diagnostic fold merged
    raw at `#emit`, against `event.rb`'s own "no sink and no caller can bypass either" and the two
    requirements' wording on the emitted record. The table is now a `private_constant` beside
    `CollisionLatch`, with a `sig/` declaration and an unreachable pin in the smoke suite; the context
    meets it once at `Logger.build` (`Logger.context!` takes the redactor, validated first), the fold at
    `#emit` on the enabled path only, and a per-event field at `#field` as before. Omit mode drops the
    key from every source. `Event#header_of` and `#header_field` moved into the table; no manifest row
    changes.
34. **`SURGERY_USERINFO` tolerates a leading run of whitespace and control bytes** (P5-105, R1-3):
    `[\x00-\x20\x7F]*` before the optional scheme, ASCII so a BINARY value with high bytes still matches,
    the bytes written back as they came. `HTTP-19` admits a leading OWS in an inbound value,
    `Headers.inbound_builder` builds it, the parser rejects it, and the round found the userinfo intact
    behind it through the step at `HEADERS`. A non-whitespace prefix is not an authority and stays
    unmatched.
35. **`Preview.decode` falls back to UTF-8 for the `EncodingError` family** (P5-106, R1-4): `utf-7` and
    `iso-2022-jp-2` are dummy encodings `Encoding.find` knows and `#encode` cannot convert, so
    `MediaType#charset` is not nil for them and the replacement options do not help; the design's
    "`Encoding.find` unreachable from here" is true only of a charset Ruby lacks. `dummy?` is not the
    discriminator (UTF-16 is dummy and decodes through its BOM), so the fallback is a rescue, and the
    private `transcode` is the recipe both branches share.
36. **Two mutations that survived round 1 have a test each and no line of `lib/` behind them** (R1-5,
    R1-6): a settlement failed from a `Thread` whose own storage differs emits the failure event under
    the caller's captured `trace.id` and `span.id` and restores the settler's keys
    (`async_step_test.rb`, `ThreadBoundaryTest`); a chunked request and response body of declared length
    `-1` put no size field on either event at `HEADERS` (`step_test.rb`, `EventsTest`, over phase 3a's
    `FakeChunked`).
37. **Three documentation slips and two suite splits** (R1-7 and the round's incidentals): P5-100's closing
    sentence names the backslash, triple-slash and non-scheme spellings it already excluded by RFC 3986,
    and the tests say so; the as-built page, `CLAUDE.md`'s redaction constraint and this checklist's rows
    state the table's three sources, the leading-OWS route, the converter-less charset and the proxy
    warning's redacted URL; the redactor suite's surgery-route cases move to `SurgeryRouteTest`, the
    step suite's header cases to `HeaderRedactionTest` and its `WritingTransport` into the shared
    `Fixtures`, under `Metrics/ClassLength`; the page's sixteen fences — five results added by this
    round — run as one script again, 112 literal checks by this round's extractor (which counts a
    block-closing result once), 0 fails on 4.0.6 and on 3.2.11, the three prose results skipped.

38. **The surgery route substitutes every `//`-authority wherever it sits** (P5-107, R2-1): the
    round-1 pattern tolerated `[\x00-\x20\x7F]*` and nothing else, and round 2 found every other prefix
    HTTP-19 admits — Appendix C's `<…>`, quotes, parentheses, a word, `%20`, `+`, `@`, a backslash, an
    NBSP, obs-text — carrying a `Location`'s userinfo through the step, a quoted `HTTPS_PROXY` carrying the
    client's own credential into both channels, and a doubled URL keeping its second authority. The
    pattern is now `//[^/?#]*@`, unanchored, applied with `gsub`; deviation 34's closing sentence ("a
    non-whitespace prefix is not an authority and stays unmatched") was that reading's error and is
    superseded; the test that asserted `x http://user:secret@h/p` verbatim asserts it scrubbed. Linearity
    measured to 1 MiB on both rubies. What stays verbatim is narrowed to what RFC 3986 decides —
    no `//` before the `@`, the backslash spellings, and what the parser accepts without an authority,
    which never reaches the route — and the non-scheme prefix `é://…` left that list, because the route
    no longer needs a scheme.
39. **An `Array` under a header key is redacted per value, then joined** (P5-108, R2-2): the `Emitter`
    joined a multi-valued header before `Event#field`, so a URL-valued header with two values met the
    redactor as one unparseable string, the surgery pattern substituted once, and the second value's
    userinfo was written back. `ReservedKeys.header_value` now maps each element through
    `Redactor#header_value` for an allow-listed name and joins with `", "` afterwards; the `Emitter` hands
    the value list over unjoined and still decides nothing. Departure 24 stands with the order stated.
40. **The async step's settlement work sits on the source future, and its teardown has one owner**
    (P5-109, R2-3): registered on the derived future at `BODY`, a throwing meter's raise ran inside
    `Future#then`'s rescue and vanished; on a future that settled inside the head, the inline callback
    raised and the head's `ensure` re-ran `scope.close` and `finish`, so the span was finished and the
    counter added twice. `#attach` now registers on the source at both levels (the derivation first, so
    the callbacks run in the sync path's order) and sits outside the head's `ensure`, whose condition is
    "the future does not exist yet"; the head is a private method with an explicit `begin`/`ensure` and
    a tuple assertion, because Steep types no local across a method-level `ensure`. The class comment and
    the `OBS-20` row state the inline case: the producer is the caller, and the request fails as on the
    sync path.
41. **A change to 5c's `test/support/allocation_delta.rb`** (R2-4): `allocations_per_call` returns the
    figure two consecutive measurements agree on (at most five, then the last), because on the 3.2.11
    floor a one-time cost of 7 or 28 interpreter objects can land inside a measured block after the
    100-iteration warm-up — once per process, dependent on which test runs first — and a single
    measurement came back negative in about one whole-file run in fifteen. Not a clamp and not a wider
    delta, either of which would also hide a real fractional per-call cost; the assertion stays exact at
    every one of the eight sites (5b's three, 5c's five), 5c's suites re-run green on both rubies, and
    guard 2 re-runs red through the changed helper. Recorded here because the file is 5c's; the plan's
    "one helper per idea" is why the fix is in the helper and not at the three 5b sites.

## Findings routed

- **The design's three findings were verified at their owners, none re-recorded**: §8.1's unsourced
  `Event#tag` is on phase 10's inbound list (`#tag` is not shipped, P5-18); the bare-`Logger` cop watch was
  the plan's own Task 10 and is closed as built — not expressible, and guarding nothing (item 10 above,
  P5-38's as-built note); the charter's `OBS-19` cell and `OBS-24` arithmetic were corrected in the
  charter on 2026-09-13 and read so.
- **The unreachable context bundle** (phase 6a, Task 8) is verified at its owner and is the reason the
  step resolves to its keyword and `Bundle::NONE` and names its span by the method token (P5-99).
- **New, routed to phase 10's inbound list, two gate-reach findings from the standalone runs**: the
  forty-first bullet — Ruby 3.4+'s unused-block warning is suppressed process-wide once any same-named
  block-taking method is compiled, so the one-process `test:gems` cannot see it and only a per-file
  `ruby -w` can, which is how `NullSink`'s shape reached the code branch (item 27) — and the forty-second:
  four phase-3b and phase-4b tests assert the default materialisation ceiling and read the live one
  through 5a's per-call `IO.max_materialized_bytes`, so an exported `MAX_MATERIALIZED_BYTES` fails them;
  5a's review round 0 (R0-7) repaired the same reading in 5a's own suites and did not reach these.
- **New, routed to phase 10's inbound list** as audit work against a committed phase document: the 5b
  design's verified fact 6 ("`u.userinfo = "***:***"` renders `https://***:***@h/x`" as the rebuild
  route) and its P5-27 mechanism are stated on a `#to_s` rebuild that drops a default port, which OBS-14
  forbids — the built redactor reassembles from `split` (P5-91) and the design's fact stands only as a
  description of a route not taken; and the design's verified fact 13 ("`Async::Future` offers `#on_settle`
  and no combinator") predates 4c's `Future#then`, on which the async step's body level now rests
  (P5-94). Both are the design's own facts, not the corpus's, so no note is filed.
- **One line of `docs/first-release.md` changed**: its `CTX-16` entry, added by phase 10's design, said
  the step "probes `request.respond_to?(:context)` … so it always takes its fallback"; as built the step
  probes nothing and names its span by the method token (P5-99), the conclusion unchanged, and the line
  now says so. Its `OBS-32`/`OBS-37` entry names this phase and reads true; its presence-gated
  auto-activation entry reads true (5b adds no fourth registry). **Nothing for
  `docs/knowledge/notes/`**: no harvested rule was found wrong.
- **Review round 0's eight findings** (2026-09-17) all closed in this stack, none routed onward: the three
  `Redactor#header_value` routes that carried a userinfo to a sink (R0-3, blocking) and the name gate that
  lived in the `Emitter` alone (R0-4) on the code branch as P5-100 and P5-102, with the two redactor nits
  (R0-7, R0-8) as P5-101; the order-dependent floor assertion (R0-1, blocking) on the tests branch; the
  102-character line (R0-2, blocking) on the code branch; the page's cross-fence state (R0-5) and the
  roadmap's count (R0-6) on the docs branch — items 28–31 above and the second guard table. The `OBS-11`
  / `OBS-16` collision the review found unrecorded is now stated in the source, the two rows and P5-100.
- **Review round 1's seven findings** (2026-09-17) all closed in this stack, none routed onward: the proxy
  credential in the config diagnostic's message (R1-1, blocking) on the code branch as P5-103; the two
  ambient sources the reserved-key table did not reach (R1-2), the leading OWS the surgery pattern did not
  tolerate (R1-3) and the converter-less charset `Preview.decode` raised on (R1-4) on the code branch as
  P5-104, P5-105 and P5-106; the two surviving mutations (R1-5, R1-6) on the tests branch; P5-100's
  closing sentence (R1-7) on the docs branch — items 32–37 above and the third guard table.
- **The design's ledger** gains an "As built" addendum (P5-91–P5-106); the consolidation of P5-16–P5-39 and
  P5-91–P5-106 into design §10 and the §8.1 addendum are a human's, as for 3a, 3b, 4a, 4b, 4c, 5a and 5c,
  because `docs/sdk-design-ruby/` is frozen. §8.1's "leans on `URI` for userinfo and query" is honoured by
  the `split` parse and no frozen sentence is contradicted, so `docs/first-release.md`'s `C1`–`C14`
  paragraph gains no `C15`.

## Postponed work

**What earlier phases postponed here has landed, and the checklist rows above mark it**:
`Dexpace.close_quietly`'s second disposal route (phase 2's postponement; the `CFG-21` row; the phase-2
comment asserting the drop is what changed); `Hooks.notify`'s per-dropped-failure diagnostic (phase 2's
option, taken; the `OBS-20` row); the body-logging caps' two remaining wirings — the shared preview size
read into both phase-3b wrappers through `Step.build(preview_bytes:)` and `Configuration::Keys::LOG_PREVIEW_BYTES`,
and the gating of their construction on `HTTPLogging::BODY` — completing the item 5a half-supplied with
`MAX_MATERIALIZED_BYTES`'s source (the `BODY-19`/`BODY-22`/`BODY-34` row; 5b lands second and marks it);
and P5-8, 5a's `Kernel#warn` sites gaining their event beside the warning (the `CFG-24`/`CFG-25` row).
**What this phase half-supplies and does not claim**: `SEAM-25`'s lifecycle event SHAPE
(`Events::INSTRUMENTATION_SHUTDOWN` and `Instrumentation.diagnostic`'s form); the emission is phase 8b's
Tasks 6 and 10 and the harness phase 9's Task 11. **What this phase postpones**: `OBS-19`'s header-drop
verbosity policy, to phase 8c's Tasks 7, 9 and 15 (P5-32, R10; both halves it is built from ship here);
`OBS-37`'s async capture skip, post-v1 under `docs/first-release.md`'s `OBS-32`/`OBS-37` entry. **What it
leaves alone**: `OBS-29`'s wiring (phase 6a Task 9 and the inbound list), `OBS-32`'s units and attribute
sets (post-v1), presence-gated auto-activation (post-v1; 5b adds no registry), `Pipeline.standard` (phase
6b Task 13a — 5b installs nothing), the conformance restatement of `OBS-1`'s two assertions (phase 8a, for
which `event_test.rb`'s R8 comment is written), and the fakes' move to `dexpace-conformance` (declined by
phase 8a; two more top-level doubles strengthen the case). The implementation postponed nothing further.
