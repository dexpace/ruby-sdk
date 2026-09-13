# pipeline

## Rules
- Pipeline steps must execute in a single fixed total order derived from stage assignment, independent of insertion order: a step in a lower-ordered stage runs before (wraps) a step in a higher-ordered stage on the inbound path and observes the response later on the outbound path. (PIPE-1, PIPE-7)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:9-9` · high · sha:33e9443472ce</sub>
- The stage list should interleave user-extensible "pre" and "post" slots around each pillar and should use sparse numeric order keys so new stages can be inserted without renumbering. (PIPE-3)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:11-11` · high · sha:33e9443472ce</sub>
- Installing a distinct second step onto an occupied pillar, via any add operation or a bulk reload, must fail fast naming both step types and pointing at the replace path rather than silently overwriting. (PIPE-4, PIPE-5, PIPE-6, PIPE-8)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:12-12` · high · sha:33e9443472ce</sub>
- Re-installing the same step onto its own pillar must be idempotent, with sameness distinguished by reference identity, not value equality. (PIPE-4, PIPE-5, PIPE-6, PIPE-8)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:12-12` · high · sha:33e9443472ce</sub>
- An empty pipeline must dispatch directly to the terminal transport, threading the caller's per-call options, and should do so without allocating per-call cursor state. (PIPE-9, PIPE-10, PIPE-11)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:16-16` · high · sha:33e9443472ce</sub>
- Pipeline steps must be safe for concurrent invocation, with per-request mutable state living in the per-call cursor, never on the step itself. (PIPE-9, PIPE-10, PIPE-11)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:16-16` · high · sha:33e9443472ce</sub>
- Each pipeline step must be bidirectional — receiving the inbound request, optionally invoking the rest of the chain, optionally inspecting or substituting the outbound response — and may short-circuit by returning a synthetic response without invoking the chain. (PIPE-12, PIPE-13, PIPE-14)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:17-17` · high · sha:33e9443472ce</sub>
- Invoking the next step must advance a monotonic cursor and invoke it; when the cursor is exhausted it must dispatch the current in-flight request to the terminal transport, threading the caller's per-call options, and the cursor must only move forward within a single un-forked drive. (PIPE-12, PIPE-13, PIPE-14)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:17-17` · high · sha:33e9443472ce</sub>
- A substituted request must propagate to every downstream step and to the terminal dispatch — it "sticks." (PIPE-12, PIPE-13, PIPE-14)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:17-17` · high · sha:33e9443472ce</sub>
- A pipeline step that drives the downstream chain more than once — retry re-attempting, redirect following a hop, or auth retrying after a challenge — must fork a fresh cursor for each re-drive rather than reusing the same next handle, since reusing the handle resumes past already-visited steps and must be treated as a defect; a port must provide an equivalent fork primitive and its wrapping pillar steps must use it. (PIPE-15, PIPE-16)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:18-18` · high · sha:33e9443472ce</sub>
- A forked pipeline cursor must resume from the same position as its parent, carry the current in-flight request, and share the immutable options, with forks advancing independently. (PIPE-15, PIPE-16)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:18-18` · high · sha:33e9443472ce</sub>
- The caller's per-call options must be carried unchanged for the entire call, including across every re-drive fork, readable by any step, threaded into the terminal dispatch, and must be immutable/shared rather than copied-and-diverged per fork. (PIPE-17)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:19-19` · high · sha:33e9443472ce</sub>
- A pipeline step that re-drives the chain must release each superseded intermediate response by closing its body before the next drive, and must not close the response it ultimately hands back to the caller, so close-responsibility passes outward. (PIPE-40, PIPE-15)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:20-20` · high · sha:33e9443472ce</sub>
- On paths that abandon a re-drive — a redirect cycle, a non-replayable body, or budget exhaustion — the in-flight response must be returned unclosed. (PIPE-40, PIPE-15)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:20-20` · high · sha:33e9443472ce</sub>
- Non-pillar pipeline stages must hold an ordered sequence where append adds to the tail and prepend adds to the head, preserving relative order through build and any re-bucketing edit. (PIPE-7, PIPE-18, PIPE-19, PIPE-20, PIPE-21)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:24-24` · high · sha:33e9443472ce</sub>
- The surgical insert-after, insert-before, and replace pipeline edits must act relative to the first existing instance of an anchor step type, the inserted or replacing step must declare the same stage as the anchor, and a cross-stage insert or replace must be rejected. (PIPE-7, PIPE-18, PIPE-19, PIPE-20, PIPE-21)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:24-24` · high · sha:33e9443472ce</sub>
- A pipeline remove edit must delete every instance of a given step type, preserving relative order of the remainder, and must be a no-op when the type is absent. (PIPE-7, PIPE-18, PIPE-19, PIPE-20, PIPE-21)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:24-24` · high · sha:33e9443472ce</sub>
- A pipeline insert-relative or replace edit whose anchor type is absent must fail, identifying the missing type. (PIPE-7, PIPE-18, PIPE-19, PIPE-20, PIPE-21)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:24-24` · high · sha:33e9443472ce</sub>
- Every pipeline mutation that re-buckets steps by stage must re-derive the flattened order deterministically, so the observable ordering after an edit equals building the same step set from scratch. (PIPE-22, PIPE-23, PIPE-24)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:25-25` · high · sha:33e9443472ce</sub>
- A bulk pipeline reload must be all-or-nothing — a pillar collision leaves the existing step collection completely unchanged rather than a partial rebuild. (PIPE-22, PIPE-23, PIPE-24)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:25-25` · high · sha:33e9443472ce</sub>
- The standard-resilience preset must install into empty pillar slots only, validating up front that no target pillar is occupied and rejecting the whole call — installing nothing — if any target pillar is already occupied. (PIPE-22, PIPE-23, PIPE-24)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:25-25` · high · sha:33e9443472ce</sub>
- The shipped pillar step families should lock their stage assignment so a subclass cannot relocate a step out of its own pillar. (PIPE-25, PIPE-38, PIPE-36, PIPE-37)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:26-26` · high · sha:33e9443472ce</sub>
- A pipeline step whose correctness depends on the single terminal response, such as status-to-typed-error mapping, must occupy the outermost pre-redirect slot so it runs outside both the redirect and retry loops, and on a non-error status must return the response untouched. (PIPE-25, PIPE-38, PIPE-36, PIPE-37)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:26-26` · high · sha:33e9443472ce</sub>
- The pipeline runtime must itself implement the transport SPI, delegating execute/execute-async to its own send/send-async (with and without options), so a configured pipeline can stand in wherever a transport is expected and options survive the indirection. (PIPE-26, PIPE-27)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:30-30` · high · sha:33e9443472ce</sub>
- The pipeline runtime should offer convenience constructors for a step-less pipeline forwarding directly to a transport, and for a standard pipeline installing the default resilience pillars — sync: redirect+retry+instrumentation; async: retry+instrumentation with a caller-supplied scheduler for non-blocking backoff. (PIPE-39)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:31-31` · high · sha:33e9443472ce</sub>
- The async pipeline runtime must reuse the identical stage identities and staging policy as the sync runtime; the two runtimes must not each re-derive ordering independently. (PIPE-28, PIPE-29, PIPE-30)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:35-35` · high · sha:33e9443472ce</sub>
- An async pipeline step must not throw synchronously to signal a transport or async failure — it must return a future completing exceptionally — and may throw synchronously only for caller-bug argument validation. (PIPE-28, PIPE-29, PIPE-30)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:35-35` · high · sha:33e9443472ce</sub>
- The async pipeline runtime must defensively normalize any synchronous exception from a step's async entry point, or from the empty-pipeline dispatch, into an exceptionally-completed future, while fatal/unrecoverable errors propagate synchronously and must not be swallowed. (PIPE-28, PIPE-29, PIPE-30)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:35-35` · high · sha:33e9443472ce</sub>
- The async terminal response-mapping operator must, on success, apply the handler and then close the response, tolerating an idempotent double-close; on failure it must unwrap async-wrapper exceptions to the original cause and must close any response accompanying a failure to avoid leaking the body. (PIPE-31, PIPE-32)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:36-36` · high · sha:33e9443472ce</sub>
- The sync-to-async pipeline bridge must require a caller-supplied executor with no default, run the wrapped synchronous pipeline as a single opaque unit on that executor so its steps stay synchronous on the worker without gaining per-step concurrency, and thread per-call options into the wrapped send. (PIPE-33, PIPE-34)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:40-40` · high · sha:33e9443472ce</sub>
- Cancelling the sync-to-async bridge's returned future with interruption must interrupt the worker running the in-flight send, while cancelling without interruption must complete as cancelled without interrupting the worker. (PIPE-33, PIPE-34)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:40-40` · high · sha:33e9443472ce</sub>
- The async-to-sync pipeline bridge must block on the async result per call while preserving options, and must honor thread interruption by restoring the interrupt flag, cancelling the in-flight future, and surfacing an interrupted-I/O error. (PIPE-33, PIPE-34)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:40-40` · high · sha:33e9443472ce</sub>
- The pipeline builder should provide two unambiguous ways to seed from an existing pipeline — FLATTEN, copying its steps and transport so they run in the same loops, versus NEST, treating it as an opaque transport so new steps run once outside the nested loops — and a port must make the flatten-vs-nest choice explicit rather than accidental. (PIPE-35)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:41-41` · high · sha:33e9443472ce</sub>
- The unified pipeline orchestrator must catch every throwable from any request-chain step and from the transport invocation, convert it into a Failure, and thread it through the response recovery chain, so no throwable from the pre-request phase or the transport may bypass the recovery hooks. (RECOV-2)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:46-46` · high · sha:33e9443472ce</sub>
- The request recovery chain must apply its ordered steps as a sequential left-to-right fold where the output of step N is the input of step N+1; an empty chain returns the input unchanged, and a throwing step aborts the remainder and propagates. (RECOV-3, RECOV-2)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:47-47` · high · sha:33e9443472ce</sub>
- Response-to-response recovery steps must run only when the current outcome is a Success; on a Failure the entire response-step phase is skipped. (RECOV-4, RECOV-5, RECOV-6)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:48-48` · high · sha:33e9443472ce</sub>
- Recovery steps must be applied to every outcome, both successes and failures, sequentially and always, observing the terminal outcome including a failure a response step just produced by throwing. (RECOV-4, RECOV-5, RECOV-6)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:48-48` · high · sha:33e9443472ce</sub>
- If a response step throws, its throwable must be converted into a Failure fed to the subsequent recovery steps rather than propagated out of the response chain, so error-mapping steps flow through recovery exactly like a transport error. (RECOV-7, RECOV-8, RECOV-9)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:49-49` · high · sha:33e9443472ce</sub>
- If a recovery step throws, its throwable must be wrapped into a Failure fed to the next recovery step rather than aborting the remaining recovery steps, and the recovery chain's apply operation must not throw under any input. (RECOV-7, RECOV-8, RECOV-9)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:49-49` · high · sha:33e9443472ce</sub>
- Recovery steps should surface errors by returning a Failure rather than throwing. (RECOV-7, RECOV-8, RECOV-9)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:49-49` · high · sha:33e9443472ce</sub>
- The pipeline orchestrator's dispatch must unwrap the final recovery outcome by returning the contained response on Success, or rethrowing the contained throwable unchanged — no wrapping, no substitution — on Failure, with any typed-exception surfacing done by a recovery step constructing the error and returning a Failure. (RECOV-10, RECOV-11)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:50-50` · high · sha:33e9443472ce</sub>
- When wrapping a cancellation or interruption throwable into a Failure, the wrapping helper must re-assert the cancellation signal on the current context before returning, so code later blocked on the outcome still observes the cancellation. (RECOV-10, RECOV-11)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:50-50` · high · sha:33e9443472ce</sub>
- When a response or recovery step throws while holding a Success response, the pipeline must close/release that in-hand response before wrapping the throwable, attaching any close error as suppressed so it never masks the primary error, releasing the response exactly once. (RECOV-12, RECOV-13)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:51-51` · high · sha:33e9443472ce</sub>
- When a step handed a Success deliberately returns a different outcome — a Success-to-Failure transform or a substitute Success — the pipeline must not auto-close the discarded original response; the transforming step owns releasing the response it drops. (RECOV-12, RECOV-13)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:51-51` · high · sha:33e9443472ce</sub>
- Recovery chain steps must be safe for concurrent invocation, with per-request state kept in the passed context or the value being transformed, never on the step. (RECOV-14)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:52-52` · high · sha:33e9443472ce</sub>
- The status-to-typed-exception mapping recovery step must treat only HTTP statuses 400 through 599 as errors, mapping them to the matching typed exception which becomes a Failure, and must return all other statuses unchanged. (RECOV-15, RECOV-16, RECOV-7)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:53-53` · high · sha:33e9443472ce</sub>
- Before mapping an error-status response into a Failure, whether on the initial response or a re-sent error response, the error body must be buffered into a bounded, replayable in-memory copy capped at 1 MiB so the connection is released promptly and the body remains readable on the Failure, with the same bound shared across all buffering paths and enforced as a hard truncation with no marker. (RECOV-15, RECOV-16, RECOV-7)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:53-53` · high · sha:33e9443472ce</sub>
- A port must not collapse the stage pipeline and the recovery chain into one layer, because the stage pipeline owns ordering and re-drive-with-fork while the recovery chain owns the sum-type fold and the uniform-failure guarantee.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:3-6` · high · sha:6b7ebc1dfd1d</sub>
- Pillar stages admit at most one step, and installing a distinct second step on an occupied pillar fails fast, naming both conflicting types. (PIPE-2, PIPE-3, PIPE-4, PIPE-5)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:12-14` · high · sha:6b7ebc1dfd1d</sub>
- Every re-bucketing edit to a pipeline re-derives the flattened order deterministically. (PIPE-22)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:23-23` · high · sha:6b7ebc1dfd1d</sub>
- The resilience preset installs only into empty pillar slots and rejects the entire call if any target pillar is already occupied. (PIPE-23, PIPE-24)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:24-25` · high · sha:6b7ebc1dfd1d</sub>
- Surgical insert-after, insert-before, and replace edits act relative to the first instance of an anchor type and reject a cross-stage move. (PIPE-24, PIPE-18, PIPE-19, PIPE-20, PIPE-21)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:25-27` · high · sha:6b7ebc1dfd1d</sub>
- The remove edit deletes every instance of a given step type from the pipeline. (PIPE-18, PIPE-19, PIPE-20, PIPE-21)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:26-27` · high · sha:6b7ebc1dfd1d</sub>
- A missing anchor in a surgical pipeline edit fails while identifying the anchor type that was not found. (PIPE-20, PIPE-21)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:27-27` · high · sha:6b7ebc1dfd1d</sub>
- A step that drives the downstream chain more than once must fork a fresh cursor per re-drive, and reusing the same cursor handle for a second downstream invocation must be treated as a defect. (PIPE-15, PIPE-16)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:29-31` · high · sha:6b7ebc1dfd1d</sub>
- A forked cursor must resume from the same position as its parent, carry the in-flight request, share the immutable options, and advance independently of the parent. (PIPE-16)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:31-32` · high · sha:6b7ebc1dfd1d</sub>
- An empty pipeline dispatches straight to the transport without allocating a cursor. (PIPE-9)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:39-40` · high · sha:6b7ebc1dfd1d</sub>
- In the default respect-existing mode, a request already carrying the idempotency-key header is left alone and its key strategy is not invoked at all, because a strategy typically mints a UUID or increments a counter and invoking it speculatively would burn a key per redirect hop.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:62-65` · high · sha:6b7ebc1dfd1d</sub>
- An empty token list, or one that joins to a blank or whitespace-only line, makes the client-identity step a no-op that must not emit a blank header.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:69-71` · high · sha:6b7ebc1dfd1d</sub>
- In the client-identity step's Append mode, an empty first existing header value is treated as absent so that no leading space is emitted.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:70-71` · high · sha:6b7ebc1dfd1d</sub>
- The exception factory the error-mapping step delegates to refuses to be asked for a non-error status, raising an argument error rather than fabricating a successful exception, with a convenience form returning nil instead. (BODY-31, XCUT-8)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:75-77` · high · sha:6b7ebc1dfd1d</sub>
- Error-body buffering happens inside the original body's close-guaranteeing scope so that a failure to allocate the buffer still closes the original body rather than leaking the connection. (BODY-30)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:86-88` · high · sha:6b7ebc1dfd1d</sub>
- A response with no body is returned unchanged by the error-body buffering step. (BODY-30)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:88-89` · high · sha:6b7ebc1dfd1d</sub>
- The response-lifecycle rule requiring closure of every superseded intermediate response before the next drive, never closing the response handed back, and returning the in-flight response unclosed on any abandoned re-drive, is placed on the re-driving step rather than on the runtime. (PIPE-40)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:93-97` · high · sha:6b7ebc1dfd1d</sub>
- The unified orchestrator must catch every throwable from any request-chain step and from the transport invocation and convert it into a Failure, and a before-request throw must not skip after-error handling. (RECOV-2)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:110-112` · high · sha:6b7ebc1dfd1d</sub>
- Non-recoverable runtime errors must not be retried, classified retryable, or logged, and must be surfaced unchanged with no suppressed-trail attachment. (RETRY-25)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:114-116` · high · sha:6b7ebc1dfd1d</sub>
- A cancellation error is converted to a Failure, but the wrapper re-asserts the cancellation state on the ambient token before returning so that later code blocked on the outcome still observes it. (RECOV-11)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:123-126` · high · sha:6b7ebc1dfd1d</sub>
- A throwing response step's error becomes a Failure fed to the recovery steps. (RECOV-7)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:131-132` · high · sha:6b7ebc1dfd1d</sub>
- A throwing recovery step's error is wrapped into a Failure fed to the next recovery step, so the chain's apply operation never raises under any input. (RECOV-7, RECOV-8, RECOV-10)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:132-134` · high · sha:6b7ebc1dfd1d</sub>
- Dispatch unwraps a Failure by re-raising the contained error unchanged, with no wrapping or substitution. (RECOV-8, RECOV-10)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:133-134` · high · sha:6b7ebc1dfd1d</sub>
- A step that throws while holding a Success has its response closed by the pipeline before the throwable is wrapped, with any close error attached as suppressed. (RECOV-12, RECOV-13)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:136-138` · high · sha:6b7ebc1dfd1d</sub>
- A step that deliberately returns a different outcome than the one it was given owns releasing the response it dropped.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:137-139` · high · sha:6b7ebc1dfd1d</sub>
- Both the request and response recovery chains defensively copy and freeze both step lists at construction time. (RECOV-14, BODY-8)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:144-145` · high · sha:6b7ebc1dfd1d</sub>
- One stream-ownership rule applies to all body variants across the system. (BODY-8, RETRY-34)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:145-146` · high · sha:6b7ebc1dfd1d</sub>
- Closing a pipeline never closes the transport it does not own. (PIPE-27)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:220-221` · high · sha:6b7ebc1dfd1d</sub>

## Constraints
- The pipeline runtime must preserve the pillar precedence chain REDIRECT to RETRY to AUTH to LOGGING to SERDE from outer to inner, plus an outermost pre-redirect slot outside both loops and a terminal SEND hop innermost. (PIPE-2)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:10-10` · high · sha:33e9443472ce</sub>
- A pillar stage must admit at most one step; the configurable pillars are REDIRECT, RETRY, AUTH, LOGGING, and SERDE. (PIPE-4, PIPE-5, PIPE-6, PIPE-8)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:12-12` · high · sha:33e9443472ce</sub>
- The terminal SEND stage must be reserved for the transport hop, must not hold a user step, and flattening must skip it. (PIPE-4, PIPE-5, PIPE-6, PIPE-8)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:12-12` · high · sha:33e9443472ce</sub>
- A built pipeline runtime must be immutable after construction, and each send must allocate its own per-call cursor so concurrent calls share no mutable pipeline state. (PIPE-9, PIPE-10, PIPE-11)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:16-16` · high · sha:33e9443472ce</sub>
- Closing a pipeline must be a no-op with respect to its underlying transport, because the pipeline never owns its transport and must not close it. (PIPE-26, PIPE-27)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:30-30` · high · sha:33e9443472ce</sub>
- The async standard pipeline must not follow HTTP redirects at the pipeline layer, since there is no async redirect pillar; a 3xx response surfaces verbatim unless redirect following is enabled on the transport, and a port must document this asymmetry with the sync standard pipeline. (PIPE-31, PIPE-32)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:36-36` · high · sha:33e9443472ce</sub>
- A recovery chain's step lists must behave as immutable after construction, and the response recovery chain must defensively copy both of its lists at construction. (RECOV-14)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:52-52` · high · sha:33e9443472ce</sub>
- A port must not collapse the stage-based pipeline and recovery-chain primitive layers into one: the stage pipeline owns ordering and re-drive-with-fork, while the recovery chain owns the sum-type fold and the uniform-failure guarantee. (RETRY-27, RETRY-28)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:59-59` · high · sha:33e9443472ce</sub>
- A bulk reload of a pipeline is all-or-nothing. (PIPE-22, PIPE-23)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:23-24` · high · sha:6b7ebc1dfd1d</sub>
- The idempotency-key strategy is invoked at most once per applicable request regardless of mode. (RECOV-33)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:65-66` · high · sha:6b7ebc1dfd1d</sub>
- Before an error-status response becomes an exception, the error body must be buffered into a bounded, replayable in-memory copy capped at a fixed maximum of 1 MiB (MAX_BUFFERED_ERROR_BODY_BYTES), so the live transport connection is released promptly and the error body remains readable on the resulting Failure. (RECOV-16)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:78-82` · high · sha:6b7ebc1dfd1d</sub>
- The error-body buffering cap is a hard truncation where bytes beyond it are not read and are discarded with no marker.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:81-82` · high · sha:6b7ebc1dfd1d</sub>
- The same 1 MiB error-body buffering bound is shared across every error-body-buffering path in the SDK. (RETRY-36)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:82-83` · high · sha:6b7ebc1dfd1d</sub>
- Ruby's `throw`/`catch` non-local exit is not an exception and is not used anywhere in core, so no step can escape the orchestrator through it.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:126-127` · high · sha:6b7ebc1dfd1d</sub>

## Conclusions
- The stage-based pipeline and the recovery-chain primitives share one backoff calculator and one pacing-header parser so their retry behavior cannot drift between the two layers.
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:3-3` · high · sha:33e9443472ce</sub>
- The stage-based pipeline is the intended composition surface for assembling a client — ordering redirect, retry, auth, logging/instrumentation, and serialization concerns as pillar steps, driving re-attempts via per-call cursors and forks, and letting a configured pipeline become a transport others can nest — and it has a real async mirror, whereas the recovery-chain primitives serve as the resilience layer used when a concern must observe every outcome uniformly through one code path without letting a pre-transport throw bypass it.
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:57-57` · high · sha:33e9443472ce</sub>
- The stage-based pipeline and the recovery-chain layer intentionally differ in one place — the recovery-aware retry stack enforces a total-timeout budget that the stage-based retry step omits — and a port unifying the retry entry points must make that budget explicitly opt-in. (RETRY-27, RETRY-28)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:59-59` · high · sha:33e9443472ce</sub>
- Re-installation of the same step is distinguished using `#equal?` rather than `==` so that it is idempotent, because core's models define value equality and `==` on two structurally identical steps would silently swallow a genuine collision. (PIPE-5, PIPE-6, PIPE-8)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:14-17` · high · sha:6b7ebc1dfd1d</sub>
- Whether a step may call `#fork` is checked at pipeline composition time from the step's stage assignment, not trusted at call time. (PIPE-10, PIPE-11)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:36-38` · high · sha:6b7ebc1dfd1d</sub>
- Per-call state lives on the cursor rather than on the step, so that a built runtime is immutable and concurrent calls share nothing mutable. (PIPE-10, PIPE-11)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:38-39` · high · sha:6b7ebc1dfd1d</sub>
- Cursor-scoped state set on a cursor is inherited by every cursor forked from it and thereafter advanced from that fork, and it is writable only by the pillar step that created the fork.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:43-49` · high · sha:6b7ebc1dfd1d</sub>
- The stage order REDIRECT → RETRY → AUTH matters because AUTH is downstream of the fork REDIRECT made, so AUTH can read a marker set on that fork but, since AUTH did not create the fork, cannot set one itself.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:49-52` · high · sha:6b7ebc1dfd1d</sub>
- Three non-pillar steps that ship in core (idempotency-key, client-identity, error-mapping) are each written once against the step protocol shared by both the stage pipeline and the recovery chain, so the same object installs into either without a second implementation.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:54-58` · high · sha:6b7ebc1dfd1d</sub>
- The markerless truncation of buffered error bodies is a documented consequence rather than an oversight, so any consumer deserializing a buffered error body must tolerate a structurally incomplete payload and any witness decoding it must fail into a typed error rather than assume well-formedness.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:89-91` · high · sha:6b7ebc1dfd1d</sub>
- Outcome exhaustiveness is enforced twice: at runtime a non-matching outcome raises via a raising `else` arm converting Ruby's `NoMatchingPatternError` into a named internal error, and statically Steep checks the union type at every fold site, with neither check alone claimed to be a full guarantee. (RECOV-1)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:101-107` · high · sha:6b7ebc1dfd1d</sub>
- The orchestrator rescues `Exception`, immediately re-raises anything outside `StandardError`, and converts the rest to a Failure, satisfying the catch-everything requirement for what the recovery layer can meaningfully handle while surfacing fatal errors unchanged. (RECOV-2, RETRY-25)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:116-119` · high · sha:6b7ebc1dfd1d</sub>
- Using Ruby's own fatal/non-fatal exception split rather than a bespoke error classification is this port's own choice rather than a sanctioned one, justified because `StandardError` is the boundary every Ruby library and application already codes against, letting a consumer's bare `rescue` and core's fatal-family passthrough agree on recoverability without either needing to know about the other. (RETRY-25)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:119-123` · high · sha:6b7ebc1dfd1d</sub>
- The response-ownership rules for a throwing step versus a deliberately-returning step are implemented as one shared helper so the asymmetry between them lives in a single place.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:138-139` · high · sha:6b7ebc1dfd1d</sub>
- This port resolves all four specification-flagged inconsistencies in the same direction, toward the stricter and more uniform behaviour, each with one shared implementation so the two paths cannot drift again. (RECOV-14, BODY-8, RETRY-34, AUTH-31, BODY-4, BODY-5, REDIR-6, RETRY-5)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:143-149` · high · sha:6b7ebc1dfd1d</sub>
- The flatten-versus-nest pipeline-seeding choice is offered as two explicitly named constructors rather than one overloaded constructor, because a port must make that choice explicit rather than accidental and Ruby's keyword arguments make the distinction easy to leave implicit. (PIPE-35, PIPE-26)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:217-219` · high · sha:6b7ebc1dfd1d</sub>

## Reference
- The SDK has two cooperating pipeline layers — the stage-based pipeline, the user-facing dispatch runtime that turns cross-cutting concerns into discrete bidirectional steps assigned to a fixed, totally-ordered stage list, and the recovery-chain primitives, the resilience layer beneath resilience steps built on a closed two-variant outcome threaded through a fold.
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:3-3` · high · sha:33e9443472ce</sub>
- Within a single non-pillar pipeline stage, step order follows insertion order rather than the cross-stage deterministic order. (PIPE-1, PIPE-7)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:9-9` · high · sha:33e9443472ce</sub>
- The SERDE pillar stage is a reserved slot with no shipped behavior. (PIPE-2)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:10-10` · high · sha:33e9443472ce</sub>
- build() must produce the pipeline's ordered step sequence by flattening stages in declaration order, skipping the SEND stage, into an immutable runtime that exposes a read-only, ordered view of its steps. (PIPE-25, PIPE-38, PIPE-36, PIPE-37)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:26-26` · high · sha:33e9443472ce</sub>
- Append-all preserves a batch's iteration order within a stage, while prepend-all, applying each element prepended individually, results in the reversed batch order, and a port must document this asymmetry. (PIPE-25, PIPE-38, PIPE-36, PIPE-37)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:26-26` · high · sha:33e9443472ce</sub>
- The response-side recovery outcome must be a closed sum type with exactly two variants — a success carrying a response and a failure carrying a throwable — mutually exclusive and jointly exhaustive, with derivable accessors and a fold that applies exactly one of two branches at most once per call. (RECOV-1)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:45-45` · high · sha:33e9443472ce</sub>
- The recovery chain's fold order is all response steps first on the success path, then all recovery steps, in declared order within each group. (RECOV-4, RECOV-5, RECOV-6)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:48-48` · high · sha:33e9443472ce</sub>
- In the reference implementation, the request recovery chain does not copy its step list at construction, retaining the caller's read-only list reference directly instead; a port should copy there too. (RECOV-14)
  <sub>spec · `docs/product-spec/08-execution-pipelines.md:52-52` · high · sha:33e9443472ce</sub>
- A pipeline step is any object responding to `#call(request, cursor)`, so a lambda qualifies as a step.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:10-11` · high · sha:6b7ebc1dfd1d</sub>
- The stage pipeline's frozen, sparsely numbered stage ordering is PRE_REDIRECT → REDIRECT → RETRY → AUTH → LOGGING → SERDE → SEND. (PIPE-2, PIPE-3)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:11-12` · high · sha:6b7ebc1dfd1d</sub>
- The SEND stage is reserved for the transport and is skipped by flattening. (PIPE-6, PIPE-8)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:15-15` · high · sha:6b7ebc1dfd1d</sub>
- Non-pillar stages hold an ordered sequence of steps supporting append and prepend operations. (PIPE-7, PIPE-38)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:17-18` · high · sha:6b7ebc1dfd1d</sub>
- Append-all preserves batch order while prepend-all reverses it, because each element in prepend-all is prepended individually. (PIPE-7, PIPE-38)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:18-20` · high · sha:6b7ebc1dfd1d</sub>
- The `build` operation flattens the staged buckets once into an immutable runtime exposing a frozen ordered view. (PIPE-25, PIPE-22)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:22-23` · high · sha:6b7ebc1dfd1d</sub>
- The cursor exposes `#call`, which is single-use and raises `Dexpace::PipelineError` on a second invocation, and `#fork`, which is available only to a step occupying a pillar stage. (PIPE-15, PIPE-10, PIPE-11)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:34-38` · high · sha:6b7ebc1dfd1d</sub>
- Options are carried by reference, unchanged, across every fork, which is free because the options are frozen. (PIPE-9, PIPE-17)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:40-41` · high · sha:6b7ebc1dfd1d</sub>
- The idempotency-key step adds its configured header only for methods in a configured set, defaulting to POST, PUT, and PATCH, and passes every other method through untouched. (RECOV-32)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:60-62` · high · sha:6b7ebc1dfd1d</sub>
- In overwrite mode, the idempotency-key strategy's result replaces any existing header value.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:64-65` · high · sha:6b7ebc1dfd1d</sub>
- The client-identity step joins its configured tokens into one space-separated line, and reconciles with an existing header by mode: Append (default) appends after the first existing value while preserving every other value, or sets the sole value if the header is absent, while Replace overwrites all existing values. (RECOV-33)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:66-69` · high · sha:6b7ebc1dfd1d</sub>
- The error-mapping step treats only statuses in the 400..599 range as errors, mapping such a status to the matching typed exception, and returns 1xx, 2xx, and 3xx responses unchanged so the success chain continues. (RECOV-15)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:72-74` · high · sha:6b7ebc1dfd1d</sub>
- A 304 or an unfollowed 3xx response keeps its body because the error-mapping step is the one that turns an error response into an error. (BODY-31)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:73-75` · high · sha:6b7ebc1dfd1d</sub>
- Core ships one `Dexpace::Recovery.buffer_error_body(response)` function holding the single MAX_BUFFERED_ERROR_BODY_BYTES constant. (BODY-30)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:85-87` · high · sha:6b7ebc1dfd1d</sub>
- The recovery chain's two-variant outcome type is defined as `Dexpace::Outcome::Success = Data.define(:response)` and `Dexpace::Outcome::Failure = Data.define(:error)`. (RECOV-1)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:101-102` · high · sha:6b7ebc1dfd1d</sub>
- The same Outcome type is reused, not re-invented, for the SSE typed adapter's Value/Skip/Done results, with a third variant added in that namespace. (SSE-33, SSE-36)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:107-108` · high · sha:6b7ebc1dfd1d</sub>
- Ruby's bare `rescue` with no class catches only `StandardError`, while `rescue Exception` catches everything including `NoMemoryError`, `SystemStackError`, `SignalException`, `SystemExit`, `Interrupt`, and `ScriptError`. (RETRY-25)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:112-114` · high · sha:6b7ebc1dfd1d</sub>
- Request steps in the recovery chain fold left-to-right with a throw aborting the remainder, response steps run only on a Success, and recovery steps run on every outcome, always, in declared order. (RECOV-3, RECOV-10)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:129-131` · high · sha:6b7ebc1dfd1d</sub>
- The specification flags its own reference implementation as internally inconsistent in four places and leaves the resolution to the porter, one of which concerns whether the request recovery chain copies its step list. (RECOV-14)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:141-143` · high · sha:6b7ebc1dfd1d</sub>
- A built pipeline runtime responds to `#call(request, options, cancellation)`, so a configured pipeline is itself a transport. (PIPE-26)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:219-220` · high · sha:6b7ebc1dfd1d</sub>

## Conflicts

## Superseded
