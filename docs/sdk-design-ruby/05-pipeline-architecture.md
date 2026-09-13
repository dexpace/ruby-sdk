## 5. Pipeline Architecture

Both pipeline layers survive, and the specification forbids merging them: "A port MUST NOT collapse the two layers
into one: the stage pipeline owns ordering and re-drive-with-fork; the recovery chain owns the sum-type fold and
the uniform-failure guarantee." Because this port keeps two execution models (§3.3), it also keeps the async mirror
of the stage pipeline and both bridges — the subsystems a single-execution-model host would find empty.

### 5.1 The stage-based pipeline

A step is any object responding to `#call(request, cursor)` — again `#call`, so a `lambda` is a step and Ruby's
middleware muscle memory transfers (P14). Stages are a frozen, sparsely numbered ordering
`PRE_REDIRECT → REDIRECT → RETRY → AUTH → LOGGING → SERDE → SEND` (**PIPE-2**, **PIPE-3**), with pillar stages
admitting at most one step (**PIPE-4**), a distinct second step on an occupied pillar failing fast and naming both
types (**PIPE-5**), re-installation of the *same* step distinguished by `#equal?` rather than `==` and therefore
idempotent (**PIPE-6**), and `SEND` reserved for the transport and skipped by flattening (**PIPE-8**). Reference
identity matters here specifically because core's models define value equality: `==` on two structurally identical
steps would report them the same and silently swallow a genuine collision. Non-pillar stages hold an ordered
sequence with append and prepend (**PIPE-7**), and the documented asymmetry of **PIPE-38** — append-all preserves
batch order, prepend-all reverses it because each element is prepended individually — is preserved and stated in
the API documentation as the requirement demands.

`build` flattens the staged buckets once into an immutable runtime exposing a frozen ordered view (**PIPE-25**);
every re-bucketing edit re-derives the flattened order deterministically (**PIPE-22**); a bulk reload is
all-or-nothing (**PIPE-23**); the resilience preset installs into empty slots only and rejects the whole call if
any target pillar is occupied (**PIPE-24**). The surgical insert-after/insert-before/replace edits act relative to
the first instance of an anchor type and reject a cross-stage move (**PIPE-18**, **PIPE-19**); remove deletes every
instance of a type (**PIPE-20**); a missing anchor fails identifying the type (**PIPE-21**).

**`call` versus `fork`, the one place a borrowed idiom would be wrong.** **PIPE-15** requires a step that drives the
downstream chain more than once to fork a fresh cursor per re-drive, and states that reusing the handle "MUST be
treated as a defect"; **PIPE-16** requires the fork to resume from the same position as its parent, carry the
in-flight request, share the immutable options, and advance independently. Every off-the-shelf Ruby middleware
composer treats a second downstream invocation as a bug — correct for ordinary middleware, wrong for a pillar step
whose entire job is controlled re-invocation. The cursor therefore exposes two distinct capabilities: `#call`,
single-use, raising `Dexpace::PipelineError` on a second invocation (which *is* **PIPE-15**'s defect treatment for
ordinary steps); and `#fork`, available only to a step occupying a pillar stage — checked at composition time from
the step's stage assignment, not trusted at call time — returning a fresh cursor bound to the calling step's
position. Per-call state lives on the cursor, never on the step (**PIPE-10**, **PIPE-11**), so a built runtime is
immutable and concurrent calls share nothing mutable. An empty pipeline dispatches straight to the transport
without allocating a cursor (**PIPE-9**). Options are carried by reference, unchanged, across every fork
(**PIPE-17**), which is free because they are frozen.

**Cursor-scoped state, and who may write it.** Beyond the request and the options, a cursor carries a small
keyed map of per-call state, and its two rules are what make §6.2's redirect marker sound: **state set on a cursor
is inherited by every cursor forked from it and thereafter advanced from that fork, and it is writable only by the
pillar step that created the fork.** Inheritance is what lets a value set on a per-hop fork reach the steps
downstream of that hop; the write restriction — checked at composition time from the step's stage assignment, the
same check that gates `#fork` itself — is what stops a later step, or a server-influenced value, from reaching back
and setting it. The two together give a marker that propagates exactly one hop's worth and cannot be forged, which
is the property §6.2 leans on and the reason the stage order **REDIRECT → RETRY → AUTH** matters: AUTH is
downstream of the fork REDIRECT made, so it reads the marker, and it is not the fork's creator, so it cannot set
one.

**Three shipped steps that are not pillars.** Three small steps ship in core alongside the pillar families. Each is
written once against the step protocol both layers share, so the same object installs into a non-pillar stage of
this pipeline and into the recovery chain's request or response list (§5.2) without a second implementation —
which is the same single-sourcing discipline §6.1 applies to the two retry stacks. Each carries a clause worth
stating rather than leaving to the implementer.

- **The idempotency-key step** (**RECOV-32**) adds its configured header only for methods in the configured set —
  default POST, PUT, PATCH, the non-idempotent writes — and passes every other method through untouched. In the
  default respect-existing mode a request already carrying the header is left alone **and the key strategy is not
  invoked at all**, which matters because a strategy is typically a UUID mint or a counter and invoking it
  speculatively burns a key per redirect hop; in overwrite mode the strategy's result replaces any existing value.
  The strategy is invoked at most once per applicable request either way.
- **The client-identity step** (**RECOV-33**) joins its configured tokens into one space-separated line and
  reconciles with what is already there by mode: Append (default) appends its line after the **first** existing
  value while preserving every other value, or sets it as the sole value when the header is absent; Replace
  overwrites all existing values. An empty token list, or one that joins to a blank or whitespace-only line, makes
  the step a no-op — it must not emit a blank header — and in Append mode an empty first existing value is treated
  as absent so no leading space is emitted.
- **The error-mapping step** (**RECOV-15**) treats **only** statuses in 400..599 as errors, maps such a status to
  the matching typed exception, and returns 1xx, 2xx and 3xx unchanged so the success chain continues. It is the
  step that turns an error *response* into an error, which is why a 304 or an unfollowed 3xx keeps its body
  (**BODY-31**). The factory it delegates to refuses to be asked for a non-error status, raising an argument error
  rather than fabricating a successful exception, with the convenience form returning `nil` instead (**XCUT-8**).

**The bounded error-body copy, specified once because every error path shares it.** Before an error-status response
becomes an exception, **RECOV-16** requires that "the error body MUST be buffered into a bounded, replayable
in-memory copy capped at a fixed maximum (1 MiB / MAX_BUFFERED_ERROR_BODY_BYTES) so that (a) the live transport
connection is released promptly and (b) the error body remains readable on the resulting Failure," with the cap a
hard truncation — bytes beyond it are not read and are discarded with no marker — and the same bound shared across
every error-body-buffering path. This is load-bearing twice over: **RETRY-36** needs it so a re-sent 503's
connection is released before the next attempt and a 503, 503, 200 sequence actually reaches the 200, and
**BODY-30** needs the copy to be independently and repeatably readable after the transport connection is gone. Core
ships one `Dexpace::Recovery.buffer_error_body(response)` holding the one constant, and the buffering happens
**inside** the original body's close-guaranteeing scope so that a failure to allocate the buffer still closes the
original body rather than leaking the connection (**BODY-30**), through §3.7's helper. A response with no body is
returned unchanged. The truncation being markerless is a documented consequence, not an oversight: a consumer
deserializing a buffered error body must tolerate a structurally incomplete payload, so the witness that decodes an
error body is written to fail into a typed error rather than to assume well-formedness.

**PIPE-40**'s response-lifecycle rule — close every superseded intermediate response before the next drive, never
close the one handed back, return the in-flight response unclosed on any abandoned re-drive — is placed on the
re-driving step, not on the runtime, mirroring the reference. In Ruby the `ensure` block is the natural home for
the close, but it must be written to close only the *superseded* response, which is why the rule lives with the
step that knows which that is.

### 5.2 The recovery-chain primitives

**RECOV-1**'s closed two-variant outcome is `Dexpace::Outcome::Success = Data.define(:response)` and
`Dexpace::Outcome::Failure = Data.define(:error)`, folded through a single `case/in` pattern match with a raising
`else` arm. Ruby has no sealed types and no compile-time exhaustiveness, so exhaustiveness is enforced twice and
neither check alone is claimed to be a guarantee: at runtime a non-matching outcome raises rather than falling
through (Ruby's pattern matching raises `NoMatchingPatternError` on an unmatched `case/in` with no `else`, and the
fold's explicit `else` converts that into a named internal error), and statically Steep checks the union type at
every fold site (§9). The same `Outcome` is reused, not re-invented, for the SSE typed adapter's Value/Skip/Done
results (**SSE-33**–**SSE-36**) with a third variant in that namespace.

**RECOV-2** is the defining invariant — "the unified orchestrator MUST catch EVERY throwable from any request-chain
step and from the transport invocation, convert it into a Failure ... a before-request throw MUST NOT skip
after-error handling" — and it collides with Ruby's exception taxonomy in a way that needs an explicit rule.
`rescue` with no class catches `StandardError` only; `rescue Exception` catches everything including
`NoMemoryError`, `SystemStackError`, `SignalException`, `SystemExit`, `Interrupt` and `ScriptError`. **RETRY-25**
independently requires that non-recoverable runtime errors "MUST NOT be retried, classified retryable, or logged;
they MUST be surfaced unchanged with no suppressed-trail attachment." The port's rule: **the orchestrator rescues
`Exception`, immediately re-raises anything outside `StandardError`, and converts the rest to a `Failure`.** That
single line satisfies **RECOV-2** for everything the recovery layer can meaningfully handle and, for everything it
cannot, **RETRY-25**'s "they MUST be surfaced unchanged with no suppressed-trail attachment." Using Ruby's own
fatal/non-fatal split rather than a bespoke classification is this port's choice and not a sanctioned one, and the
argument for it is that `StandardError` is the boundary every Ruby library and every application already codes
against: a consumer's own bare `rescue` and core's fatal-family passthrough agree on which errors are recoverable
without either having to know about the other, which no bespoke list could achieve. Two riders: a cancellation
error is converted to a `Failure` but
the wrapper re-asserts the cancellation state on the ambient token before returning (**RECOV-11**), so later code
blocked on the outcome still observes it; and Ruby's `throw`/`catch` non-local exit is not an exception and is not
used anywhere in core, so no step can escape the orchestrator through it.

**RECOV-3** through **RECOV-10** are plain folds over frozen arrays of steps: request steps fold left-to-right with
a throw aborting the remainder; response steps run only on a `Success`; recovery steps run on every outcome, always,
in declared order, with a throwing response step's error becoming a `Failure` fed to the recovery steps
(**RECOV-7**) and a throwing recovery step's error wrapped into a `Failure` fed to the *next* recovery step so the
chain's apply operation never raises under any input (**RECOV-8**). Dispatch unwraps by re-raising the contained
error unchanged, with no wrapping or substitution (**RECOV-10**).

**RECOV-12** and **RECOV-13** are the response-ownership pair and are easy to get backwards: a step that *throws*
while holding a `Success` has its response closed by the pipeline before the throwable is wrapped, with any close
error attached as suppressed; a step that *deliberately returns* a different outcome owns releasing the response it
dropped. Both are implemented as one shared helper so the asymmetry lives in one place.

**RECOV-14** is one of four places the specification flags its own reference implementation as internally
inconsistent and pushes the decision to the porter ("the request recovery chain does NOT copy ... so a port SHOULD
copy there too"). This port resolves all four in the same direction — toward the stricter, uniform behaviour — and
does so with one shared implementation each so the two paths cannot drift again: **RECOV-14**, both chains
defensively copy and freeze both step lists at construction; **BODY-8**, one stream-ownership rule for all body
variants (§3.1); **RETRY-34**, the skip-self-suppression guard applies to both retry stacks through one
`attach_suppressed` helper; **AUTH-31**, the 401 replayability gate applies on both the sync and async auth paths
through one `Dexpace::Resilience::Resend.eligible?(request)` predicate (under `resilience/`, per §2.3's layout),
which is the same predicate **BODY-4**, **BODY-5**, **REDIR-6** and **RETRY-5** consult.

**Suppressed exceptions.** Ruby has `Exception#cause` — a single-parent causal chain, set automatically when
re-raising inside a `rescue` — but nothing resembling a suppressed-exception list, which **RECOV-12**, **PAGE-13**,
**PAGE-15**, **SSE-29**, **SSE-36** and **RETRY-34** all need. Core's error root `Dexpace::Error` therefore carries
a `#suppressed` array, frozen once populated, with `#full_message` overridden to render the trail, and one
`Dexpace.attach_suppressed(primary, secondary)` helper that skips attaching an exception to itself (**RETRY-34**'s
self-suppression guard). `#cause` is left entirely to Ruby's automatic mechanism and is never used for the
suppressed trail: they mean different things (this error was *caused by* that one, versus this error happened
*while cleaning up after* that one) and conflating them makes a close failure look like a root cause.

**Walking the cause chain is cycle-safe, and Ruby makes the cycle reachable.** Anything that classifies an error by
inspecting what caused it — the retryability walk of §6.1, the cancellation-versus-timeout classification of
**XCUT-2**, the redaction of a nested message — walks `#cause` transitively, and **XCUT-9** requires that any such
walk "MUST track visited causes by reference identity and terminate on a self-referential or cyclic chain instead
of looping forever." Ruby does not prevent the cycle: `#cause` is settable through `Exception#exception` and
re-raise chains built by application code can and do close on themselves, and an infinite walk inside a rescue
handler is an unkillable hang rather than a stack overflow. Core therefore has one `Dexpace.each_cause(error)`
enumerator, and it tracks the objects it has seen by **`equal?`** — not `==`, which core's `Data`-based errors
define structurally and which would truncate a legitimate chain of two distinct errors carrying identical fields,
the same trap **CTX-9** sets in §5.4. Every classification in the port goes through it; none walks `#cause` by
hand. The suppressed trail above is walked by the same helper for the same reason, since a suppressed error may
itself carry a cause.

### 5.3 The async mirror and the two bridges

Because both execution models are real here, **PIPE-28**'s "the async runtime MUST reuse the identical stage
identities and staging policy as the sync runtime; the two MUST NOT each re-derive ordering independently" has
teeth and is satisfied structurally: there is one `Dexpace::Pipeline::Stages` module holding the frozen ordering and
the pillar set, and both runtimes flatten through the same code. Only the terminal dispatch and the step invocation
protocol differ. **PIPE-29** and **PIPE-30** are honoured by the same normalisation described in §3.3: an async
step returns a future, never raises for a transport failure, and the runtime converts any synchronous raise from a
step's async entry point into a failed future — re-raising the fatal family unchanged, per §5.2's rule.
**PIPE-31**'s terminal response-mapping operator applies the handler and closes the response on success (tolerating
an idempotent double close) and closes any response accompanying a failure.

**PIPE-32** — the async standard pipeline follows no redirects, and "a port MUST document this asymmetry with the
sync standard pipeline" — is preserved rather than papered over, and made visible rather than silent: the async
standard-pipeline factory takes an explicit `redirect: :unsupported` argument, so the asymmetry appears at the call
site instead of as an absence a reader has to notice. It is also listed in §11 as a specification tension, because
a port with a genuine async redirect story could reasonably close it.

**PIPE-33**'s sync-to-async bridge requires a caller-supplied executor with no default, and **SEAM-18** gives the
reason: a shared global pool would be starved by blocking work. Core defines the executor as a duck type
(`#post { ... }`) and ships no implementation, so there is no default to fall into; `dexpace-async-thread` supplies
a bounded `Thread::SizedQueue` pool and `dexpace-async-async` supplies an `Async::Task`-backed one. The bridge runs
the whole synchronous pipeline as one opaque unit on that executor, so its steps stay synchronous on the worker and
do not gain per-step concurrency, exactly as **PIPE-33** specifies. **PIPE-34**'s async-to-sync bridge is
`future.value(deadline:)`, which preserves options, honours cooperative cancellation and surfaces the original
failure unwrapped (**ASYNC-13**, **ASYNC-14**) — never `Thread#raise`, never `Timeout.timeout`. The bridge owns no
executor, so its close touches nothing (§3.7, **SEAM-25**, **XCUT-22**).

**The one clause of PIPE-33 this port does not satisfy, stated as a gap rather than a difference.** **PIPE-33**
requires that "Cancelling the returned future with interruption MUST interrupt the worker running the in-flight
send; cancelling without interruption MUST complete as cancelled without interrupting the worker." The second half
is satisfied exactly. **The first half is not satisfied, and the port does not claim otherwise**: interrupt-mode
cancellation is the mechanism §8.3 forbids for the whole repository, so every cancellation on this bridge behaves
as the non-interrupting mode. The mitigation is real but partial: the future completes as cancelled *promptly*, so
the caller is never blocked on a worker it has given up on, and the worker aborts at its next check-after-resume
point (§3.3), which for a `Net::HTTP` send under a socket timeout is bounded by that timeout rather than
unbounded. `Completer#on_cancel` lets an adapter shorten that further by closing the socket out from under the
read. What remains is the residual gap, named precisely (P8): **a transport blocked inside an uninterruptible
C-extension read — libcurl, some TLS paths — cannot be aborted early by any mechanism this port permits**, so the
worker occupies its pool slot until the read returns on its own. The consequence is bounded worker occupancy under
aggressive cancellation, not a correctness failure: no response is leaked, because whatever the read eventually
produces is closed on the discard path (§3.3, **CFG-21**), and no result is delivered to a cancelled caller. This
is recorded as an unsatisfied MUST in §10 and §12, not as a mechanism substitution.

**PIPE-35**'s flatten-versus-nest seeding is offered as two explicitly named constructors rather than one
overloaded one, because "a port MUST make the flatten-vs-nest choice explicit rather than accidental" and Ruby's
keyword arguments make the distinction easy to leave implicit. **PIPE-26** falls out for free: the built runtime
responds to `#call(request, options, cancellation)`, so a configured pipeline *is* a transport (§3.2), and
**PIPE-27** is satisfied because closing a pipeline never closes the transport it does not own.

### 5.4 The execution context model

The dispatch → request → exchange promotion chain (**CTX-1**–**CTX-3**) is three distinct `Data` classes sharing a
module, not one class with a stage field: **CTX-1**'s "exchange is terminal — no method promoting back" is then
enforced by the absence of a method rather than by a guard clause that could be forgotten. Each promotion is
additive and non-mutating, carrying forward the same instrumentation bundle reference and the same call key and
adding exactly one artifact (**CTX-2**), which `Data`'s frozen-by-construction semantics give for free.

**CTX-4**'s call key must be unique per call even when tracing is disabled and every bundle field is identical
(**CTX-15**'s no-op bundle shares constant sentinels across every untraced call), so the key is a rendered
`trace-id:span-id` prefix plus a process-wide monotonic counter incremented under a `Thread::Mutex` — not a
trace-derived value, and not a bare UUID, which would lose the debuggability the prefix buys. Off-chain
construction mints a fresh key by the same mechanism, with the documented consequence (**CTX-5**/**CTX-6**) that
two default-constructed contexts with otherwise identical fields are *not* equal, and an explicit key is how a
caller who needs value equality pins one. **CTX-17**'s registration-at-promotion rule means constructing a
dispatch context registers nothing, so a context never promoted leaves no store entry and its close is a no-op.

The store is a plain `Hash` behind a `Thread::Mutex`, not a concurrency-library map: **CTX-7**'s requirement is
that distinct keys be registrable concurrently without external locking, which a mutex-guarded hash satisfies, and
core cannot depend on `concurrent-ruby` (**SEAM-1**). **CTX-9**'s eviction is **identity-based** — the slot is
cleared only when its current occupant `equal?` the closing context — and this is the one place a Ruby port is
actively likely to go wrong, because core's value objects define `==` and a naive `delete_if { |_, v| v == ctx }`
would evict a *different* context with identical fields. The port uses `equal?` explicitly and asserts the
distinction in a test. **CTX-10** follows: only the furthest-reached link occupies the slot, so closing a promoted
intermediate is a no-op, as is removing an unknown key (**CTX-18**).

**CTX-11**'s bounded backstop is a post-insert drain *loop* (**CTX-12**) with arbitrary victim selection
(**CTX-13**), sharing one implementation with **XCUT-14**'s general bounded-map rule and with **AUTH-19**'s
per-nonce counter store. **CTX-19**'s prohibition on weak references is a live temptation in Ruby —
`ObjectSpace::WeakMap` and `ObjectSpace::WeakKeyMap` exist and look like the obvious way to "help" the collector —
and it is forbidden by lint: a weakly held context could be collected mid-call, taking the reachable
request/response graph (including an unread body pinning a connection) with it. The bounded cap is the only
sanctioned backstop. **CTX-16**'s operation name is carried forward unchanged and stays strictly advisory: it
reaches the tracing seam and nothing else, never the request, the dispatch decision, or the store key.

---

