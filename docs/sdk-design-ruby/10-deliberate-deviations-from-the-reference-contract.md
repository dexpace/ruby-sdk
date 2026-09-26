## 10. Deliberate Deviations from the Reference Contract

Every place where the Ruby-idiomatic answer changes the *mechanism* by which a requirement is satisfied, rather
than merely relocating it. **With two named exceptions — ASYNC-3 and PIPE-33's interrupt clause, both consequences
of the one prohibition in §8.3 — none narrows a MUST-level correctness guarantee. A third, ASYNC-4, holds
vacuously for the same reason and is collected with them in §10.5.** Each entry states the IDs it touches, whether
the specification sanctions it or this port judged it, and where the full argument lives. Nothing new appears here.

[Corrected 2026-09-25, when this chapter was reconciled against the as-built tree rather than against the phase
documents that produced it. The bold sentence held for the nineteen entries the design wrote and is no longer the
whole count: three further MUST clauses are not met, each on a stated domain and each admitted rather than argued
away — the no-materialisation clause of SERDE-27 in the shipped JSON codec (entry 20), the header-name clause of
TRANSPORT-14 on the asynchronous transport (entry 21), and the no-pinning clause of HTTP-45 for a second fiber of one
thread with no fiber scheduler installed (entry 22). Four further entries narrow a MUST clause on an edge they state
and argue rather than admit — a frozen primary (6), a borrowed `Net::HTTP` (26), an explicit scheme-default port
(33) and a bearer provider with no `#fetch_async` (34). "Nothing new appears here" holds for entries 1–19 only. Entries
20–38 consolidate every genuine deviation from the reference contract that the phases' as-built ledgers recorded and
this chapter did not; each cites its ledger row — a phase-7 row with its sub-phase letter, because 7a, 7b and 7c
each number from `P7-1` — and the as-built code, and its full argument lives in that phase's design. Corrections to
entries 1–19 are dated in place, quoting what they replace. Ledger rows that record a departure from the design or
the plan while the specification is met exactly are not deviations and are not carried here.]

1. **The byte-stream provider seam is retired; its behavioural contract is not.** *Touches* **SEAM-3**–**SEAM-10**,
   **IO-30**–**IO-36**, **IO-39**, **XCUT-23** as applied to this seam. *Judged.* Ruby's byte primitives ship with
   the interpreter, so nothing needs keeping out of core and there is nothing to make pluggable (P2).
   **IO-1**–**IO-29** and **IO-37**–**IO-42** are implemented in full; only the pluggability apparatus is removed.
   §3.1. [Narrowed 2026-09-25 from phase 3a's as-built ledger, `P3-1`–`P3-3`: "in full" means under Ruby's
   spellings. The tail-appending read of IO-1 is `#read_into(dest, count:)`, because `#read` and `#readpartial`
   keep Ruby's overwrite semantics, which `IO.copy_stream` relies on; the host-native bridge of IO-16 ends with
   `nil` or `Dexpace::EndOfStreamError < ::EOFError` rather than -1; and the use-after-close failure of IO-42 is
   `Dexpace::ClosedError`, a `StandardError` rather than an `IOError`, because a `Dexpace::IOError` would shadow
   Ruby's inside `module Dexpace`. As built in `gems/dexpace-core/lib/dexpace/io/typed_reads.rb`.]
2. **The canonical body is a duck type, not a nominal interface.** *Touches* **SEAM-3**, **BODY-1**, **BODY-35**.
   *Judged.* `#each` yielding BINARY `String` chunks is Rack's de facto standard, so every existing Ruby streaming
   body inter-operates with no adapter (P14). The inverse adapter `BufferedSource.over` is the single entry point
   the other direction, and takes no ownership. §3.1. [Narrowed 2026-09-25 from phase 3b's `P3-15`: the duck type is
   what a body *yields*; the slot a `Request` or `Response` body occupies is typed `Dexpace::Body?` in `sig/`, which
   is **HTTP-36**'s contract (a write-to-sink operation, a media type, a length and replayability), and nothing
   coerces a bare Rack body into it at runtime.]
3. **The async pivot is a core-owned future rather than an ecosystem primitive.** *Touches* **SEAM-16**,
   **SEAM-17**, **ASYNC-1**, **ASYNC-2**. **Spec-sanctioned**: **SEAM-17** is a SHOULD that names the pattern, not
   the type, and explicitly wants "one canonical dependency-free future pivot ... ecosystem facades ... separate
   adapters." Adopting any Ruby async gem as the pivot would put a third-party type in core's public surface,
   violating **SEAM-1** and **NFR-11**. §3.3.
4. **Cancellation is cooperative; the orphaned-response close moves to the producer.** *Touches* **SEAM-13**,
   **SEAM-30**, **XCUT-1**–**XCUT-3**, **CFG-17**, **CFG-20**, **CFG-21**, **RETRY-23**, **TRANSPORT-3**,
   **ASYNC-5**. *Judged, with partial sanction* (**XCUT-3** separates the non-pinning mechanism from the normative
   prompt-cancellation requirement). Ruby's only pre-emption primitives land an interrupt on arbitrary bytecode and
   are forbidden (§8.3). **SEAM-30**/**ASYNC-5**'s orphaned-response close is performed by the producer under the
   check-after-resume rule, and **CFG-21**'s discard-path close through the same helper — *how*, not *whether*
   (P6). Cancellation remains prompt at the future, which is what **XCUT-3** makes normative. §3.3, §3.7, §8.3.
   [Extended 2026-09-25 from phase 2's `P2-4` and phase 4b's `P4-17`: the same substitution reaches two more IDs.
   **SEAM-18**'s blocking bridge, told to "restore the interrupt flag … surface an interrupted-I/O error", has no
   interrupt to restore — the flag clause is vacuous as ASYNC-4 is — and raises the typed `Dexpace::CancelledError`
   (a `StandardError`, not an `IOError`) from `Dexpace::Bridge::SyncOver`; and **RECOV-11**'s re-assert-on-wrap has
   no action to perform, because the token is a latch computed from its sources, so converting a `CancelledError`
   into a Failure cannot clear it.]
5. **Two MUSTs are not satisfied, and a third holds vacuously: ASYNC-3, PIPE-33's interrupt clause, and ASYNC-4.**
   *Touches* **ASYNC-3**, **ASYNC-4**, **PIPE-33**. *Judged, and admitted rather than argued away* (P8). These are
   the only entries in this catalogue that are not mechanism substitutions, and they are not equivalent to one
   another, which is why they are separated here. [Corrected 2026-09-25: "the only entries" held for the nineteen;
   entries 20–22 admit three more unmet MUST clauses, 29 records two vacuities, and several of 23–38 are readings of
   two colliding MUSTs rather than substitutions. These three remain the only ones caused by §8.3's prohibition.]
   - **ASYNC-4 holds vacuously, and that is a real argument.** It requires an interrupt-ordering handshake so "a
     stale interrupt cannot poison a pooled thread." It is a negative guarantee about a hazard interrupts create;
     a port that never delivers an interrupt cannot produce the hazard, so the guarantee holds — and holds more
     strongly than an implementation of the handshake would provide, since a handshake narrows a window it does not
     close. The conformance item is recorded as vacuous.
   - **ASYNC-3 is not satisfied.** It requires that "when an async operation is backed by a blocking task on a
     worker thread, cancellation MUST distinguish two modes: cancel-with-interrupt interrupts the worker currently
     executing the in-flight task, while cancel-without-interrupt cancels the logical operation without
     interrupting the worker." Its antecedent is satisfied here — `dexpace-async-thread` is precisely a blocking
     task on a worker thread — so the requirement applies and the port meets only one of the two modes. It is not
     vacuous and is not claimed to be.
   - **PIPE-33's interrupt clause is not satisfied**, for the same reason and on the same bridge: "Cancelling the
     returned future with interruption MUST interrupt the worker running the in-flight send." The
     non-interrupting half is met exactly.

   *Why:* §8.3's prohibition on `Timeout.timeout`, `Thread#raise` and `Thread#kill`, which exists because an
   asynchronous interrupt in Ruby can land on any bytecode instruction, including inside an `ensure` releasing a
   pooled connection. *Mitigation:* the check-after-resume rule (§3.3) aborts the worker at its next resume point,
   and `Completer#on_cancel` lets a **transport** shorten that by closing its socket under the read — the thread-pool
   adapter owns no socket [Amended 2026-09-25, `C12` of `docs/deviations.md`: this read "lets an adapter shorten
   that"; `dexpace-async-thread` posts an opaque block and can register no such hook, and the hooks that exist are
   the two transports' — `ResponsePump` in `gems/dexpace-transport-net_http/lib/dexpace/transport/net_http/` and
   `Exchange` in `gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/`]; the future itself
   completes as cancelled promptly either way, so no caller waits on work it has abandoned. *Residual gap, stated
   precisely:* **a transport blocked inside an uninterruptible C-extension read cannot be aborted early**, so its
   worker occupies a pool slot until that read returns on its own. The consequence is bounded worker occupancy
   under aggressive cancellation; no response is leaked and no result is delivered to a cancelled caller. §3.3,
   §5.3, §8.3, §12.
6. **Suppressed exceptions are a core-owned trail, not a host facility.** *Touches* **RECOV-12**, **PAGE-13**,
   **PAGE-15**, **SSE-29**, **SSE-30**, **SSE-36**, **RETRY-34**, **XCUT-9**. *Judged.* Ruby has `Exception#cause`
   (single causal parent) and nothing else; `Dexpace::Suppressible` supplies the list — `Dexpace::Error` includes it
   and `Dexpace.attach_suppressed` extends it onto any other exception [Amended 2026-09-25, `C14` of
   `docs/deviations.md`: this read "`Dexpace::Error#suppressed` supplies the list". Every primary RECOV-12,
   `close_quietly` and `Hooks.notify` hand the helper can be a caller's own exception, so the trail cannot live on
   the SDK's root alone; as built it is `gems/dexpace-core/lib/dexpace/suppressible.rb` (phase 4b's `P4-12`). One
   narrowing rides with it (`P4-13`): attaching extends a caller's exception visibly, and on a **frozen** primary the
   attach is a documented no-op, so the secondary error is lost rather than raised over the primary — the one case
   where RECOV-12's attachment is not met], `#cause` is never
   overloaded to mean "failed while cleaning up," and every cause walk goes through one `equal?`-tracking
   enumerator so **XCUT-9**'s cycle-safety is a property of the helper rather than of each call site. §5.2.
7. **"Standard library" is narrowed to what is stable across the supported Ruby range.** *Touches* **SEAM-1**,
   **NFR-1**, **AUTH-14**, **OBS-2**. *Judged.* Ruby's stdlib shrinks between releases (`base64` bundled from 3.4,
   `logger` from 4.0, verified), so core may require only non-gemified stdlib and permanently-default gems. The
   visible consequences are Basic auth via `pack("m0")` and a duck-typed logging sink beneath the event facade.
   §2.4, §6.3, §8.1, §9.2.
8. **Discovery's substrate is require-time self-registration, not classpath scanning.** *Touches* **SEAM-5**–
   **SEAM-9**, **XCUT-23**. *Judged.* All five precedence branches are preserved verbatim; only what makes a
   candidate "discoverable" changes. The registry holds factories, the resolved slot holds one instance, and
   **SEAM-6**/**SEAM-8**'s prior-state table compares `equal?` on that instance. Presence-gated auto-activation is
   permitted for instrumentation only, and the asymmetry is argued rather than assumed. §3.6.
9. **SEAM-10's multi-loader de-duplication is vacuous and is replaced by a version-skew guard.** *Touches*
   **SEAM-10**. *Judged.* Ruby has one process-global constant namespace and no classloader; two copies of core
   cannot yield two distinct classes. The real Ruby risk is an adapter built against a different core version, which
   the `~>` constraint plus a registration-time assertion covers, audited by §9's single-instance gate. §2.4, §3.6.
   [Extended 2026-09-25 from phase 8b's `P8-21`: the thread-pool adapter has no registry to register into — there is
   no executor seam, and **SEAM-18** forbids a default executor — so `dexpace-async-thread` makes the same
   `Gem::Requirement` check directly at require time against `Dexpace::Async::Thread::REQUIRED_CORE`.]
10. **Runtime encapsulation of models is partially unachievable.** *Touches* **HTTP-2**/**SEAM-29**, **HTTP-4**,
    **HTTP-7**, **IO-28**/**BODY-37**. *Judged, and admitted rather than closed* (P8). `private_class_method :new` is
    bypassable by `send` by design — which bypasses `.build` but not validation, since every HTTP domain model's
    `#initialize` validates before `super`; what stays open is `.allocate`, which yields an instance whose members
    are all `nil` — and duck typing admits impersonation. [Amended 2026-09-25, `C19` of `docs/deviations.md`: the
    sentence read only "`private_class_method :new` is bypassable by `send` by design", which §4 had glossed as
    reaching "the generated constructor". As built, `Dexpace::Request.send(:new, …)` with a GET and a body raises the
    HTTP-7 refusal from `gems/dexpace-core/lib/dexpace/http/request.rb`, and `Request.allocate` answers `nil` for all
    four members.] The official path is genuinely closed, the
    gap is documented, and — the part that matters — header validation (**HTTP-17**/**HTTP-18**/**XCUT-18**) is
    re-run at the model-to-wire boundary so a forged model cannot smuggle a request-splitting header. §4.
11. **Read-only collection exposure is computed once, not wrapped per access.** *Touches* **HTTP-5**, **XCUT-15**.
    **Spec-sanctioned**: **HTTP-5** grants the mechanism explicitly ("A port in a language without read-only
    collection views MUST reproduce this guarantee with unmodifiable wrappers or per-call defensive copies").
    Caveats stated: `freeze` is shallow, and `Ractor.make_shareable` deep-freezes *in place*, so it is applied only
    to collections the model already owns. §4.
12. **One stream-ownership rule for bodies, resolving a reference inconsistency.** *Touches* **BODY-8**, **SEAM-3**,
    **SEAM-21**. **Spec-sanctioned**: **BODY-8** requires the port to decide ("A port MUST decide its
    stream-ownership/close rule deliberately rather than assume every single-use body closes its input"). A body
    closes exactly the sources it opened; ownership-on-wrap remains the I/O layer's rule (**IO-6**) and is deliberately
    not the body layer's [Amended 2026-09-25, `C3` of `docs/deviations.md`: §3.1 attributed the I/O rule to SEAM-3,
    the ID entry 1 retires; the live ID is IO-6, and `Dexpace::IO::BufferedSource.wrapping` is its as-built
    home], and the serde seam's streaming variants close nothing (**SEAM-20**/**SEAM-21**). §3.1, §3.4, §3.7.
13. **The serde seam ships four encode profiles, two of which are one Ruby type.** *Touches* **SEAM-20**.
    *Judged.* `#dump_string(value)`, `#dump_bytes(value)`, `#dump_to(value, sink)` and
    `#dump_into(value, buffer, offset: 0)` all ship [Amended 2026-09-25, `C18` of `docs/deviations.md`: the four
    were spelled without the value they encode, as `#dump_to(sink)` and `#dump_into(buffer, offset:)`; as built in
    `gems/dexpace-serde-json/lib/dexpace/serde/json/codec.rb`. Narrowed the same day from phase 7a's `P7-5`: the
    buffer profile's target is a mutable BINARY `String` only — Ruby's `IO::Buffer` is refused, because it warns as
    experimental and raises `ArgumentError` where `String#[]=` raises `IndexError`, the single range error
    **SERDE-4** asks for]; a BINARY
    `String` *is* Ruby's byte array, so the fresh-string and fresh-byte-array profiles differ only in the encoding
    tag the result carries. Both are kept because the tag is load-bearing at §3.1's encoding boundary. Argued
    clause-by-clause rather than reduced (P5). §3.4.
14. **The serde witness is a class-object-and-combinator protocol, not a reflective type token.** *Touches*
    **SEAM-22**, **SEAM-23**, **SERDE-5**–**SERDE-8**, **SERDE-16**, **SERDE-17**. *Judged.* Ruby erases nothing
    but reifies no element types, so the requirement is live and its mechanism is unavailable. Argued at least as
    strong on two counts (earlier failure, unreachable unresolved-variable state) and honestly weaker on one (no
    compile-time refusal). **SEAM-23**'s failure hierarchy is unaffected by the substitution and ships as written.
    §3.4, §7.3.
15. **The cross-origin redirect marker lives on the per-hop cursor, not on the request.** *Touches* **REDIR-11**,
    **AUTH-29**, **PIPE-16**. *Judged, and stronger.* Forgery becomes structurally impossible rather than defended
    against, and the porter trap **REDIR-11** itself documents — a pipeline with no auth step forwarding the marker
    to the transport — cannot occur. Rests on §5.1's two cursor-state rules and the stage order
    REDIRECT → RETRY → AUTH. §5.1, §6.2. [Stated as built 2026-09-25 from phase 4c's `P4-28` and `P4-29`: cursor
    state is keyed by `(stage, key)`, written only as `Cursor#fork(state:)` into the forking pillar's own slot and
    read through `#state(stage)`; `Dexpace::Pipeline::Cursor` has no setter, so even the RETRY pillar that sits
    between REDIRECT and AUTH cannot write the slot AUTH reads.]
16. **The configuration chain keeps four tiers with a substituted third source.** *Touches* **CFG-1**, **CFG-3**,
    **CFG-4**, **CFG-24**, **CFG-26**, **OBS-35**. *Judged.* Ruby has no system properties; the `Dexpace.configure`
    defaults tier is a genuinely distinct in-process source, not a second `ENV` read under another name (P11).
    **CFG-1**'s ordering is preserved even where it inverts common Ruby convention — and is defended on the merits,
    not only on obedience — and the proxy model's resolution is the same deviation applied again, not a new one.
    §8.2.
17. **The interruptible sleep is a cancellable queue wait, not `Kernel#sleep`.** *Touches* **CFG-15**, **CFG-17**,
    **CFG-18**, **RETRY-26**, **XCUT-3**, **XCUT-13**. **Spec-sanctioned** in part: **XCUT-3** states "the normative
    requirement is prompt cancellation, not the specific mechanism." Satisfies **CFG-15**'s blocking-and-interruptible
    clause and **RETRY-26**'s no-pinning clause simultaneously. §3.7, §8.3. [Corrected 2026-09-25: the entry
    ended "and is what lets §3.7's graceful close wait without parking a cancelled caller". No close path calls
    `Clock#sleep`: its only callers are the two retry drivers. As built, §3.7's graceful close is bounded rather
    than cancellable — `Dexpace.close_quietly` calls `#close` with no arguments, so `Dexpace::Async::Thread::Pool`'s
    drain waits at most its construction-time `shutdown_timeout` and takes no token (phase 8b's `P8-24`,
    `gems/dexpace-async-thread/lib/dexpace/async/thread/pool.rb`), and the interrupt-safety clause of **ASYNC-15**
    is met by that bound and by the flag never being touched.]
18. **Platform-constant substitutions where Ruby has no constant.** *Touches* **IO-9**, **BODY-32**, **SSE-11**,
    **RECOV-34**. **Partly spec-sanctioned**: **SSE-11** requires the port to pick a documented cap. Ruby has no
    maximum single allocation and no integer overflow, so the port names explicit constants (64 MiB
    materialisation ceiling, 2^31−1 ms retry hint, an explicit ~292-year duration bound in retry config) and fails
    or ignores loudly above them, preserving the observable behaviour on a host where the stated failure mode is
    unreachable. §3.1, §6.1, §7.2. [Amended 2026-09-25, `C15` of `docs/deviations.md`: the list omitted
    `SSE::MAX_LINE_BYTES` (1 MiB) and `SSE::MAX_EVENT_BYTES` (8 MiB), **SSE-19**'s two rejecting caps, distinct from
    SSE-11's `MAX_RETRY_MS` (phase 7b's `P7-21`). The line cap is sanctioned by chapter 13's own SSE-19 port clause;
    the event cap is judged, since appendix C's "no maximum line or event size" is what it departs from. Three more
    narrowings from the as-built ledgers: the materialisation ceiling is read per call through
    `Dexpace::IO.max_materialized_bytes` from its configuration key, so `IO::MAX_MATERIALIZED_BYTES` is the default and
    the fallback rather than a fixed bound, and it governs every contiguous materialisation including
    `#read_exactly` (phase 5a's `P5-56`, phase 3a's `P3-4`); and the pacing-header parser bounds each digit run at
    fifteen digits and a value at 64 bytes, the largest a `Float` carries exactly, below which **RETRY-18** clamps
    and above which **RETRY-16** answers no hint (phase 6a's `P6-61`).]
19. **The dead-code-survival gate is retargeted, not deleted.** *Touches* **NFR-8**, **NFR-9**. **Spec-sanctioned**:
    **NFR-8** says "In ecosystems without such a build step this requirement does not apply." Retargeted at the
    require-allowlist audit and clean-bundle isolation run, which guard the Ruby-specific way a zero-dependency
    claim silently stops being true. §9.2.

20. **SERDE-27's no-materialisation clause is not satisfied by the shipped JSON codec.** *Touches* **SERDE-27**,
    **SERDE-12**, **IO-9**. *Judged, and admitted rather than argued away.* Added 2026-09-25 from phase 7a's `P7-1`.
    No `json` entry point at or above the 2.19.9 floor parses from an IO except `JSON.load`, which §3.4 bans for
    `create_additions`, so `Dexpace::Serde::JSON::Codec#load` drains the source into one `String` under
    `Dexpace::IO.max_materialized_bytes` and a larger body raises `Dexpace::StreamError` unwrapped (**SERDE-12**).
    The deviation is adapter-local: `Dexpace::Serde::DecodingHandler` materialises nothing and hands `#load` the
    unread `BufferedSource`, so a codec over a pull parser satisfies the clause with no change to core, the handler
    or the seam. The requirement's other three MUST clauses — consume and close on every path, a missing body surfaced
    naming the target, a parse failure chained as the cause while a mid-stream I/O error propagates unwrapped — are
    met. As built:
    `gems/dexpace-serde-json/lib/dexpace/serde/json/codec.rb`; the gap is also `docs/first-release.md` § What v1
    ships without › Unsatisfied MUSTs.
21. **TRANSPORT-14's header-name clause is unreachable on the asynchronous transport.** *Touches* **TRANSPORT-14**,
    **TRANSPORT-27**. *Judged, and admitted rather than argued away.* Added 2026-09-25 from phase 8c's `P8-38`,
    with the TRANSPORT-27 half that ledger row did not carry. `protocol-http1` raises out of the read on a control or
    non-ASCII byte in an inbound header **name**, and on an unparseable `Content-Length`, so no response object
    exists to drop the one header from or to downgrade to the unknown-length sentinel: the whole response fails as a
    retryable `Dexpace::TransportError`. The value-side clauses hold on both adapters, and both clauses hold on
    `dexpace-transport-net_http`. The gap is bounded to the one malformed response and is carried as a named
    conformance waiver listing both IDs,
    `gems/dexpace-transport-async_http/test/dexpace/transport/async_http/conformance_test.rb`'s `WAIVED`.
22. **HTTP-45's no-pinning clause holds for threads, not for a second fiber of one thread with no scheduler.**
    *Touches* **HTTP-45**, **BODY-22**. *Judged, and admitted rather than argued away.* Added 2026-09-25 from phase
    3b's `P3-27` and `P3-28`, which recorded it in that phase's documents alone. The once-only parse of
    `Dexpace::TypedResponse#value` and the once-only drain of `Dexpace::ResponseLoggingBody` serialise through a
    `Thread::Mutex` and a `Thread::ConditionVariable` held across the state flip only; both defer to an installed
    `Fiber.scheduler`, which is the non-pinning HTTP-45 asks for. With no scheduler — Ruby's default — a second
    fiber of the same thread arriving mid-parse parks the carrier thread, and deadlocks the process if the first
    fiber is never resumed. Two threads, and a fiber arriving after the parse settled, are unaffected. Ruby has no
    scheduler-independent primitive that serialises without parking. As built:
    `gems/dexpace-core/lib/dexpace/http/typed_response.rb`,
    `gems/dexpace-core/lib/dexpace/http/body/response_logging_body.rb`.
23. **The orchestrator's "every throwable" is every `StandardError`.** *Touches* **RECOV-2**, **RECOV-8**,
    **PIPE-30**. *Judged.* Added 2026-09-25 from phase 4b's `P4-19` and phase 4c's `P4-52`. The recovery
    orchestrator, the response chain and the async driver convert every `StandardError` into a Failure; the fatal
    family outside it (`NoMemoryError`, `SystemExit`, `Interrupt`, `ScriptError`) propagates unconverted, which is
    the reading of PIPE-30's "fatal/unrecoverable errors MUST propagate" this port applies to all three; and
    `Dexpace::OutcomeError` — a fold handed something that is not an `Outcome` — is re-raised by name rather than
    demoted into a Failure a recovery step could swallow, because it is the caller's programming defect. As built:
    `Dexpace::Recovery::Orchestrator#call` in `gems/dexpace-core/lib/dexpace/recovery/orchestrator.rb`.
24. **Retryable throwables are classified by capability, not by I/O type.** *Touches* **RETRY-2**, **RECOV-17**,
    **XCUT-4**, **XCUT-6**. *Judged, with partial sanction* — RECOV-17 itself asks for a capability. Added
    2026-09-25 from phase 6a's `P6-4`. RETRY-2 defines the retryable set as any throwable that is, or has in its cause
    chain, an I/O or timeout error; `Dexpace::Resilience::Policy.throwable_retryable?` asks only `#retryable?` over
    `Dexpace.each_cause`, on both stacks, because a type match is wrong both ways — a wrapped `ProtocolError`, or an
    I/O error a caller deliberately marks terminal. The stated blind spot — a bare stdlib I/O error escaping an
    adapter unwrapped classifies not retryable — is closed by obligation: both shipped transports wrap every
    no-response failure in `Dexpace::TransportError`, whose `#retryable?` is true. As built:
    `gems/dexpace-core/lib/dexpace/resilience/policy.rb`.
25. **The asynchronous transport runs only inside a reactor, and its response does not outlive that reactor.**
    *Touches* **TRANSPORT-21**, **TRANSPORT-25**. *Judged.* Added 2026-09-25 from phase 8c's `P8-39`
    and `P8-94`. `Dexpace::Transport::AsyncHTTP` creates no reactor: called with no `Async::Task` current it returns
    an already-failed future carrying `Dexpace::SeamError` — TRANSPORT-21's channel, never a synchronous raise — and
    a caller must read the body before the `Sync` block that produced the response ends, because the reactor's
    teardown drains the connection pool and waits on the connection behind an unread body, so TRANSPORT-25's lazily
    read body is lazy within the reactor's lifetime only. The specification states no such precondition;
    `async-http` imposes it. As built:
    `gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/adapter.rb` (`REACTOR_MESSAGE`).
26. **A borrowed `Net::HTTP` is used verbatim: one origin, serialised calls, no per-call timeout.** *Touches*
    **TRANSPORT-5**, **TRANSPORT-15**, **TRANSPORT-19**, **XCUT-22**. *Judged.* Added 2026-09-25 from phase 8a's
    `P8-6`, `P8-15` and `P8-53`. TRANSPORT-5's per-call override and XCUT-22's leave-the-caller's-client-untouched
    rule contradict each other on a `Net::HTTP`, whose timeouts are instance state, so
    `Dexpace::Transport::NetHTTP.using` refuses a per-call timeout with `InvalidArgumentError` rather than
    silently ignoring it; it also refuses a request naming any origin but the client's own, and serialises calls
    through one permit held for the life of each response, so TRANSPORT-19's prompt unblock waits on the caller's
    own `read_timeout`. The owning construction, `.build`, has none of these limits, and the asynchronous adapter's
    `.using` applies a per-call timeout as a task deadline. As built:
    `gems/dexpace-transport-net_http/lib/dexpace/transport/net_http/adapter.rb`.
27. **ASYNC-18's delay blocks no caller and no worker, but one timer thread per pool.** *Touches* **ASYNC-18**.
    *Judged.* Added 2026-09-25 from phase 8b's `P8-25`. `Dexpace::Async::Thread::Pool#delay` parks neither the
    caller nor any pool worker; one lazily created timer thread per pool waits out every interval, and cancelling a
    delay removes its entry, so no thread is held for it. `Fiber.scheduler` is per thread, so core's `Async.delay`
    is unavailable on a worker, and a thread per delay or a worker used as the timer would be unbounded or would
    starve the pool. As built: `gems/dexpace-async-thread/lib/dexpace/async/thread/timer.rb`.
28. **CFG-18's delay settles with `true` and refuses to block.** *Touches* **CFG-18**, **SEAM-16**. *Judged,
    forced by a MUST.* Added 2026-09-25 from phase 5a's `P5-9` and `P5-52`. SEAM-16 makes a nil-valued success
    unconstructible, so `Dexpace::Async.delay` settles with `true`, the smallest non-nil value, rather than the
    "empty/void value" CFG-18 describes; and with no `Fiber.scheduler` a positive delay raises `Dexpace::SeamError`
    rather than degrading to a thread-backed wait that would meet the MUST clauses while falsifying the SHOULD's
    headline, "without blocking a thread". A zero delay completes inline and a negative one is refused. As built:
    `gems/dexpace-core/lib/dexpace/async/delay.rb`.
29. **Two clauses are vacuous by a false antecedent: CFG-19's unwrap and PAGE-15's wrapping.** *Touches*
    **CFG-19**, **PAGE-15**. *Judged; the same shape as §11.15.* Added 2026-09-25 from phase 5a's `P5-11` and phase
    7c's `P7-1`. Ruby has no completion or execution wrapper exception — `Completer#fail` and `Future#value`
    deliver the caller's own object — so CFG-19's "a non-wrapper throwable MUST be returned unchanged" holds for
    every input, and shipping an unwrap would `NFR-4`-lock an identity function; the observable half is asserted
    with `assert_same`. And no Ruby iteration terminal "cannot declare the underlying I/O error type", so PAGE-15's
    wrap-to-declare clause has nothing to wrap: a page close failure is raised as itself. Both IDs are implemented
    for every clause that has a subject. As built: `gems/dexpace-core/lib/dexpace/async/completer.rb`,
    `gems/dexpace-core/lib/dexpace/page/closing.rb`; §12 lists both among the vacuous entries.
30. **Where OBS-11's userinfo redaction meets OBS-16's "returned verbatim", OBS-11 wins.** *Touches* **OBS-11**,
    **OBS-16**, **OBS-14**, **HTTP-19**. *Judged; resolves two MUSTs that collide.* Added 2026-09-25 from phase 5b's
    `P5-100` and `P5-107`. A relative header value's network-path authority, and every `//`-authority in a value the
    URI parser rejected wherever it sits, has its userinfo replaced by `***:***`, whatever **HTTP-19**-admitted bytes
    precede it; every other byte is written back as it came, and what RFC 3986 gives no authority (a path spelling
    a second one) stays verbatim. A rejected value has no grammar left to honour, and a tolerated-prefix list is
    always one prefix short, so OBS-11's "unconditionally" is read literally. As built:
    `Dexpace::Instrumentation::Redactor` in `gems/dexpace-core/lib/dexpace/instrumentation/redactor.rb`.
31. **The diagnostic context restores, snapshots and folds with three stated narrowings.** *Touches* **OBS-10**,
    **OBS-23**, **OBS-24**, **XCUT-20**. *Judged.* Added 2026-09-25 from phase 5c's `P5-49` and `P5-72` and phase
    5b's `P5-22`, `P5-39` and `P5-97`. OBS-23's "remove it if previously unset" and "restore its prior value" share
    one assignment, `Fiber[k] = prior`: on 3.3 and later a present-but-nil key restores as absent, and on the 3.2
    floor, whose `Fiber` API has no removal, a previously unset key restores as present-and-nil — both unobservable
    at `Fiber[]`, and OBS-10 skips a nil value, while `Diagnostics.capture` compacts nil-valued keys so the floor's
    retained nils never travel. OBS-24's snapshot is immutable (a shallow-frozen `Hash`) and makes no shareability
    claim, because `Ractor.make_shareable` over a host's unshareable value raises from a logging path, which XCUT-20
    forbids. And OBS-10's unfiltered mode folds every present key except those under
    `Diagnostics::RESERVED_PREFIX` (`dexpace.`), where core keeps its current-span slot. As built:
    `Dexpace::Instrumentation::Diagnostics` in `gems/dexpace-core/lib/dexpace/instrumentation/diagnostics.rb`.
32. **Trace identity follows the flavour, and the no-op tracer is shared across operations.** *Touches*
    **OBS-26**, **OBS-27**, **OBS-29**, **OBS-25**, **CTX-15**. *Judged; each resolves two MUSTs in literal
    conflict.* Added 2026-09-25 from phase 4a's `P4-7` and phase 5c's `P5-43`. OBS-26's invalid trace id of 32 hex
    zeros is exact for the W3C and no-op flavours and for `Bundle::NONE`; OBS-27's Datadog flavour renders decimal,
    where that sentinel is not expressible, so its invalid id is `"0"`, while the span-id sentinel stays one
    constant. And OBS-29's "one tracer instance corresponds 1:1 to one logical operation" binds a stateful tracer:
    OBS-25 requires the no-op factory to hand out one shared tracer with no per-call allocation, so
    `NO_TRACER_FACTORY#tracer` answers `NO_TRACER` every time, and the 1:1 obligation is stated on `_Tracer` as an
    implementer contract and asserted against a factory that returns a fresh instance per call. As built:
    `Dexpace::Instrumentation::TraceIdFlavour`, `Dexpace::Instrumentation::NO_TRACER_FACTORY`.
33. **A redirect predicate overrides the follow decision but not the hop cap, and an explicit default port is not
    kept.** *Touches* **REDIR-13**, **REDIR-17**, **REDIR-18**, **REDIR-19**, **REDIR-20**, **REDIR-21**,
    **REDIR-23**. *Judged.* Added 2026-09-25 from phase 6b's `P6-91` and `P6-96`. REDIR-20 says a configured
    predicate "fully overrides the built-in follow decision"; the step consults it on every recognised 3xx
    (REDIR-21) and then lets REDIR-17's cap veto a `true`, and a missing or unresolvable target returns the response
    unfollowed whatever it answered, because REDIR-17, REDIR-18 and REDIR-19 are MUSTs with no carve-out and an
    uncapped predicate would make REDIR-23's stack safety unbounded. Separately, REDIR-13's "preserve explicit
    ports" holds for every non-default port but not for an explicit scheme default: `URI#to_s` elides `:443` and
    `:80` and `URL.parse!` re-parses from the text, so `Location: https://h:443/y` reaches the wire as
    `https://h/y`. The origin triple REDIR-8 and AUTH-29 compare is unchanged. As built:
    `Dexpace::Redirect::Step` in `gems/dexpace-core/lib/dexpace/redirect/step.rb`.
34. **Four authentication clauses yield to the port's other rules.** *Touches* **AUTH-16**, **AUTH-22**,
    **AUTH-23**, **AUTH-31**, **AUTH-36**, **AUTH-37**, **AUTH-11**, **HTTP-18**. *Judged.* Added 2026-09-25 from phase
    6c's `P6-2`, `P6-5`, `P6-7` and `P6-76` (cited with the sub-phase letter, since 6a's rows share those numbers).
    AUTH-37's off-thread background refresh is off-thread only if the provider is: the SDK owns no thread, so
    `Dexpace::Auth::AsyncBearerStamper` calls the provider's `#fetch_async` and never awaits it, and a provider with
    `#fetch` alone is mirrored into a settled future per AUTH-11, so its blocking fetch runs inline on the
    dispatching fiber. AUTH-23's first-handler-whose-can-handle-passes is one answer-or-`nil` call, so a handler that
    recognises a challenge but cannot answer it defers to the next rather than ending the chain. AUTH-36's
    eviction-driven retry is still skipped for a non-replayable body, surfacing the 401 unchanged, in the direction
    of AUTH-31's own note. And Digest yields to the outbound header grammar of HTTP-18: a non-ASCII username goes out
    as RFC 7616's `username*=UTF-8''…` rather than AUTH-22's quoted form, and a challenge whose `realm`, `nonce` or
    `opaque` the grammar cannot echo is declined, narrowing AUTH-16's satisfiable set by exactly the challenges no
    conforming request could answer. As built: `gems/dexpace-core/lib/dexpace/auth/`.
35. **Two pagination clauses are met by stated readings.** *Touches* **PAGE-16**, **PAGE-19**, **PAGE-10**.
    *Judged.* Added 2026-09-25 from phase 7c's `P7-5`, `P7-117` and `P7-6`. RFC 3986's same-document references —
    `<>` and `<#…>` — resolve successfully to the current URL, and followed literally they re-fetch the current page
    until a cap PAGE-10 defaults to unbounded, so `Dexpace::Page.next_request_from` reads both forms off the raw
    target and answers end-of-stream, while `<?>`, `<//>` and the current URL spelled out are still followed. And
    PAGE-16's single read of the body is the extractor's contract rather than core's: the strategies take a
    caller-supplied `#call(response)` extractor and never a codec — the serde independence the specification's
    pagination chapter demands — so core calls the extractor exactly once per page and cannot enforce how often it reads.
    As built: `gems/dexpace-core/lib/dexpace/page.rb`, `gems/dexpace-core/lib/dexpace/page/cursor_strategy.rb`.
36. **SERDE-24's round-trip holds on a stated precision domain.** *Touches* **SERDE-24**. *Judged.* Added
    2026-09-25 from phase 7a's `P7-8`. `Dexpace::Serde::Instant` emits ISO-8601 at microsecond width through
    `Time#iso8601(6)`, which truncates: every `Time` whose sub-second part is an exact multiple of a microsecond —
    every one the SDK constructs or decodes — round-trips exactly, and a float-derived one need not
    (`0.123456` → `.123455`). Rounding would mean a second date formatter beside `HTTPDate`. As built:
    `gems/dexpace-core/lib/dexpace/serde/instant.rb`.
37. **Three model clauses take a Ruby shape.** *Touches* **HTTP-9**, **HTTP-34**, **HTTP-1**, **BODY-9**,
    **HTTP-38**. *Judged.* Added 2026-09-25 from phase 1's `P1-10` and `P1-14` and phase 3b's `P3-16`. HTTP-9's
    idempotent set is a public constant, `Dexpace::Method::IDEMPOTENT`, with `#idempotent?`, rather than "an internal
    constant": the single-source clause is met exactly, and the two consumers read it by receiver from sibling files,
    which a private predicate cannot serve without a second copy of the set. `RequestOptions` tag values are narrowed
    to `String`, where HTTP-34 fixes string keys and HTTP-1 leaves values opaque, so the map can be deep-copied and
    deep-frozen at construction; narrowing is the direction a later release can widen. And BODY-9's "supports
    mark/reset" is seekability, probed at construction with `pos` and `seek(pos)` — `respond_to?(:rewind)` answers
    true for a pipe — with each replay seeking back to the construction position rather than byte 0. As built:
    `gems/dexpace-core/lib/dexpace/http/method.rb`, `gems/dexpace-core/lib/dexpace/http/request_options.rb`,
    `gems/dexpace-core/lib/dexpace/http/body/stream_body.rb`.
38. **Two defects are detected as far as Ruby lets them be.** *Touches* **PIPE-15**, **PIPE-5**, **BODY-11**,
    **BODY-17**. *Judged, and admitted rather than closed* (P8). Added 2026-09-25 from phase 4c's `P4-33` and
    `P4-37` and phase 3b's `P3-21` and `P3-28`. PIPE-15's reuse of a spent cursor is detected sequentially: the
    single-use latch is an unsynchronised flag, because a cursor is per step invocation and never published, and a
    mutex would put a non-reentrant lock on every step of every call to catch a caller defect, so a concurrent double
    use is not guaranteed to raise (measured at roughly 1.5 % on 3.2.11). PIPE-5's "distinct cross-stage error" is a
    distinct message on the one `Dexpace::PipelineError`. And a body driven through a caller's own abandoned
    external `#each` keeps what it held — an `ensure` never runs in an `Enumerator` abandoned mid-`#next` — so a
    `FileBody` leaks the fresh handle BODY-11 opens for that write and a replayable `StreamBody` keeps its rewind
    guard and refuses every later write, the safer failure; internal drives always complete. As built:
    `gems/dexpace-core/lib/dexpace/pipeline/cursor.rb`, `gems/dexpace-core/lib/dexpace/http/body/file_body.rb`.

Two things that are deliberately **not** deviations, recorded because a reader may expect them: the two retry
stacks are **not** unified, so neither **RETRY-28**'s nor `08-execution-pipelines.md`'s unification sanction is
invoked (§6.1); and both transport seams and both pipeline bridges survive, so no analogue of a single-execution-model
collapse appears above (§1, §3.3, §5.3).

---

