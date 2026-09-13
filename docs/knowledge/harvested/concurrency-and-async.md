# concurrency-and-async

## Rules
- Choose the concurrency model deliberately: Fibers plus `async` for high-volume I/O, threads with `Mutex`/`Queue` for moderate I/O with shared state, Ractors for CPU-parallel work, and multiple processes for isolation without Ractor restrictions. evidence: /home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:3, 60 confidence: high - type: rule topic: concurrency statement: Bound every pool and queue, replace `Timeout.timeout` with per-call deadlines, and tear down every concurrency resource on exit.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:3` · high · sha:bb7cce1169e7</sub>
- True CPU parallelism requires Ractors or multiple processes; spinning up threads to parallelize heavy computation achieves nothing and adds synchronization cost.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:59` · high · sha:bb7cce1169e7</sub>
- Code review rejects threads used for CPU-bound parallel work when Ractors or multiple processes are not used instead.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:62` · high · sha:bb7cce1169e7</sub>
- Bound the Ractor count to roughly the machine's core count using `Etc.nprocessors`, since spawning one Ractor per work item is unbounded fan-out that overwhelms the scheduler.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:69` · high · sha:bb7cce1169e7</sub>
- Reach for Ractors only when profiling shows the GVL is the bottleneck; I/O-bound work belongs to Fibers or threads, not Ractors.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:70` · high · sha:bb7cce1169e7</sub>
- Non-frozen objects crossing a Ractor boundary raise a Ractor runtime error, and review must treat this as a compile-time concern.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:94` · high · sha:bb7cce1169e7</sub>
- Use `Mutex#synchronize` to make every read-modify-write atomic when threads share mutable state, since without it two threads can interleave reads and writes producing lost updates or corrupt data.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:98-99` · high · sha:bb7cce1169e7</sub>
- Prefer eliminating shared mutable state over locking it: use immutable `Data` value objects that need no synchronization, or a `Queue`/`SizedQueue` for explicit producer-consumer coordination instead of a bare `Mutex`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:100` · high · sha:bb7cce1169e7</sub>
- Protect only the smallest possible critical section — the statements that actually touch shared state — since a coarse lock spanning an I/O call couples concurrency and latency and risks deadlock.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:101` · high · sha:bb7cce1169e7</sub>
- Bare `Mutex.new` plus manual synchronization should be replaced by `Concurrent::Map`/`Concurrent::Array` where possible, and `@mutex.synchronize` must never span an I/O call.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:126` · high · sha:bb7cce1169e7</sub>
- Reserve threads for integrations that cannot use the Fiber scheduler (C extensions with blocking calls, background work needing process-level isolation), and keep I/O-heavy hot paths on Fibers.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:134` · high · sha:bb7cce1169e7</sub>
- A new `Thread.new` for I/O-bound fan-out is rejected at review in favor of `Async`/`Semaphore`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:157` · high · sha:bb7cce1169e7</sub>
- Use `Concurrent::FixedThreadPool` (never `Concurrent::CachedThreadPool` or raw `Thread.new`) for thread-based fan-out, and `Async::Semaphore` for Fiber-based fan-out, declaring the bound as a named, documented constant.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:159-163` · high · sha:bb7cce1169e7</sub>
- Use `SizedQueue` instead of `Queue` for producer-consumer channels, since an unbounded `Queue` lets producers race arbitrarily ahead of consumers while `SizedQueue` applies backpressure when the buffer is full.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:164` · high · sha:bb7cce1169e7</sub>
- Bound concurrency at every level — the pool, the queue feeding it, and the total in-flight work — so no single layer can accumulate unbounded state.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:165` · high · sha:bb7cce1169e7</sub>
- A custom RuboCop cop bans `Thread.new` inside loops, review rejects `Queue.new` where `SizedQueue.new` belongs, and pool size and queue bound must be named constants.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:184` · high · sha:bb7cce1169e7</sub>
- Never use `Timeout.timeout`; apply per-call deadlines instead.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:186-189` · high · sha:bb7cce1169e7</sub>
- Use the `async` gem's `task.with_timeout(seconds)` to cancel by unwinding at the next Fiber yield point, a cooperative and deterministic cancellation that does not corrupt intermediate state.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:190` · high · sha:bb7cce1169e7</sub>
- For blocking I/O in threads, configure the client library's own timeout options (`:read_timeout`, `:connect_timeout`, `:open_timeout`) rather than wrapping the call in `Timeout.timeout`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:191` · high · sha:bb7cce1169e7</sub>
- Set two timeouts on every external call — a connect timeout and a read/operation timeout — since they model different failure modes (slow DNS resolution versus an accepted connection that never returns data).
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:192` · high · sha:bb7cce1169e7</sub>
- A custom RuboCop cop bans `Timeout.timeout` in application code, and I/O client constructors must include timeout options.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:212` · high · sha:bb7cce1169e7</sub>
- Cap retries with a fixed maximum retry count and exponential backoff with jitter, since unbounded retries under backpressure make a bad situation worse and jitter prevents synchronized retry storms.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:214-218` · high · sha:bb7cce1169e7</sub>
- Declare retry bounds as named constants (`MAX_RETRIES`, `BASE_DELAY_SECONDS`, `MAX_DELAY_SECONDS`) so they are visible in code review and tunable without hunting through inline literals.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:219` · high · sha:bb7cce1169e7</sub>
- After exhausting retries, raise a typed `StandardError` subclass that propagates up; do not swallow the final failure or return a sentinel `nil`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:220` · high · sha:bb7cce1169e7</sub>
- Retry loops without a max-attempts cap are rejected at review, and delay constants must be named.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:249` · high · sha:bb7cce1169e7</sub>
- Model cross-thread payloads, Ractor messages, and queue items as immutable `Data` value objects rather than `Hash` or `Struct`, since sharing a frozen object requires no synchronization.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:251-255` · high · sha:bb7cce1169e7</sub>
- Document every place a value crosses a concurrency boundary and name the invariant that holds (e.g. "frozen `LineItem` — safe for Ractor transfer") rather than leaving the reader to infer it.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:257` · high · sha:bb7cce1169e7</sub>
- A `Hash` or mutable `Struct` crossing a thread or Ractor boundary is rejected at review in favor of `Data.define`, and every such boundary must have a comment naming the invariant.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:274` · high · sha:bb7cce1169e7</sub>
- Never hold a lock across an I/O call, since the lock would be held for the entire I/O latency, turning a network hiccup into an application-wide stall.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:276-280` · high · sha:bb7cce1169e7</sub>
- Restructure code to perform all I/O outside the lock and enter the lock only for the pure in-memory update (fetch-then-lock, not lock-then-fetch).
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:282` · high · sha:bb7cce1169e7</sub>
- `@mutex.synchronize` blocks containing I/O calls are rejected at review; critical sections must touch only in-memory state.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:298` · high · sha:bb7cce1169e7</sub>
- Prefer `concurrent-ruby` primitives over hand-rolled synchronization, using `Concurrent::Map` and `Concurrent::Array` as thread-safe drop-in collections wherever multiple threads read or write the same collection.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:300-304` · high · sha:bb7cce1169e7</sub>
- When `concurrent-ruby` does not cover a pattern, reach for `Queue`/`SizedQueue` from the stdlib or `Async::Semaphore` before hand-rolling a `Mutex` solution.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:306` · high · sha:bb7cce1169e7</sub>
- A custom `Mutex` plus standard `Hash`/`Array` is replaced at review by `Concurrent::Map`/`Concurrent::Array`, and shared counters must use `Concurrent::AtomicFixnum`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:328` · high · sha:bb7cce1169e7</sub>
- Join threads, shut down pools, and close queues deterministically, since an unjoined thread or pool may be killed mid-operation by the OS at process exit, corrupting the operation.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:330-333` · high · sha:bb7cce1169e7</sub>
- Call both `shutdown` (stop accepting new work) and `wait_for_termination` (block until in-flight work drains) on every `Concurrent::FixedThreadPool`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:335` · high · sha:bb7cce1169e7</sub>
- Register pool and thread shutdown in an `at_exit` hook or inside an `ensure` block so teardown happens even if the main thread raises.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:336` · high · sha:bb7cce1169e7</sub>
- Every `Concurrent::FixedThreadPool` must have a paired `shutdown` plus `wait_for_termination` in an `ensure` block, and every `SizedQueue` must be `close`d on exit, per review.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:356` · high · sha:bb7cce1169e7</sub>
- An async-runtime adapter that owns an executor MUST implement close as an idempotent, ownership-aware release where only the first close shuts the owned executor and emits the lifecycle event; closing MUST NOT be required to cancel in-flight requests (a graceful drain is acceptable), and an adapter over a caller-supplied executor MUST NOT shut it down (SEAM-25).
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:44-44` · high · sha:0adae2d6a47f</sub>
- Async-runtime adapters that hand work to another thread SHOULD propagate the ambient logging/diagnostic context across the thread handoff and SHOULD map cancellation bidirectionally per that ecosystem's idiom (SEAM-24).
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:45-45` · high · sha:0adae2d6a47f</sub>
- The time abstraction is an injectable seam exposing three operations—current wall-clock instant, a monotonic elapsed-time counter, and a blocking interruptible sleep—with a shared platform-backed default provided, and time-dependent logic should route through this seam so tests can drive time deterministically. (CFG-15)
  <sub>spec · `docs/product-spec/16-configuration.md:32-32` · high · sha:367e27ec6481</sub>
- The monotonic counter must be non-decreasing and used only for measuring elapsed durations between its own readings (its absolute value is not meaningful), while the wall-clock reading may move backwards and must not be used for elapsed-time measurement. (CFG-16)
  <sub>spec · `docs/product-spec/16-configuration.md:33-33` · high · sha:367e27ec6481</sub>
- sleep must reject a negative duration, must allow a zero duration by returning promptly, and must honor cooperative cancellation by re-asserting the interrupt/cancellation status before propagating when interrupted mid-sleep. (CFG-17)
  <sub>spec · `docs/product-spec/16-configuration.md:34-34` · high · sha:367e27ec6481</sub>
- The async layer should provide a scheduled non-blocking delay yielding a future that completes after a non-negative duration on a scheduler without blocking a thread, completing immediately for zero, rejecting negative durations, and cancelling the future must cancel the underlying scheduled task. (CFG-18)
  <sub>spec · `docs/product-spec/16-configuration.md:35-35` · high · sha:367e27ec6481</sub>
- When surfacing the cause of a failed async operation, the subsystem should unwrap the platform's async-completion wrapper exceptions to the original throwable, terminating on the first non-wrapper cause, a null cause, or a detected cycle, and returning a non-wrapper unchanged. (CFG-19)
  <sub>spec · `docs/product-spec/16-configuration.md:36-36` · high · sha:367e27ec6481</sub>
- The subsystem should provide an interruptible-task future that runs a task on an executor such that cancel-with-interrupt interrupts the running worker while cancel-without-interrupt does not, never interrupting a queued or finished task, clearing the worker's interrupt state before it returns to its pool, and delivering rejected submission through the future rather than throwing synchronously. (CFG-20)
  <sub>spec · `docs/product-spec/16-configuration.md:37-37` · high · sha:367e27ec6481</sub>
- When an interruptible-task future has already been cancelled and the task nonetheless produced a closeable result, that result must be closed on the discard path on a best-effort basis, swallowing close failures, and the close helper must be null-safe. (CFG-21)
  <sub>spec · `docs/product-spec/16-configuration.md:38-38` · high · sha:367e27ec6481</sub>
- The async transport contract is a single-value completion future that yields exactly one Response on success or completes with exactly one failure, delivering a non-null Response on success, and an implementation with no response must complete via the failure channel rather than deliver a null or absent value. (ASYNC-1)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:7-7` · high · sha:f1bf00174456</sub>
- Every failure detectable while constructing the async operation, such as request-adaptation errors or worker-pool rejection, must be delivered through the future's failure channel and never thrown synchronously. (ASYNC-2)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:8-8` · high · sha:f1bf00174456</sub>
- Adapters that move work/callbacks onto another thread should propagate the caller's diagnostic logging context across the hop by capturing it on the boundary thread and reinstating it on the executing/callback thread, though this is an observability guarantee only—an adapter that omits it still executes exchanges correctly. (ASYNC-8)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:20-20` · high · sha:f1bf00174456</sub>
- When an adapter reinstates a captured logging context, it must first save the executing thread's prior context, install the captured context only for the work's duration, and restore the prior context afterward including when the work throws, so a reused or pooled thread's own context is never clobbered. (ASYNC-9)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:21-21` · high · sha:f1bf00174456</sub>
- When an adapter propagates logging context, capture must occur at the point that identifies the logical caller—per-subscription for cold/reusable stream or promise objects, per-task-submission for executor decorators—not at object-construction time, so a reused async object picks up the live context of each use. (ASYNC-10)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:22-22` · high · sha:f1bf00174456</sub>
- When an adapter propagates logging context, capture and restore must be safe when no logging-context backend is installed: an absent context captures as empty, and reinstating an empty context clears the target thread's context rather than raising. (ASYNC-11)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:23-23` · high · sha:f1bf00174456</sub>
- On runtimes where a newly created worker does not inherit the spawning thread's logging context (lightweight threads or plain thread-local contexts), an adapter that propagates logging context must explicitly transfer it at the thread-creation boundary, distinct from any carrier-hop guarantee the runtime provides. (ASYNC-12)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:24-24` · high · sha:f1bf00174456</sub>
- When surfacing a failure, adapters must unwrap the async framework's wrapper exceptions down to the original cause so typed handlers match the real exception, terminating unwrapping on the first non-wrapper cause, a null cause, or a detected cycle. (ASYNC-13)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:28-28` · high · sha:f1bf00174456</sub>
- An async-to-sync blocking bridge must honor thread interruption while awaiting by restoring the interrupt flag, cancelling the in-flight future, and throwing an interrupted-I/O failure; it must unwrap execution-wrapper exceptions so blocking callers see the original failure, and a future cancelled independently must surface its cancellation as-is rather than remapped to I/O. (ASYNC-14)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:29-29` · high · sha:f1bf00174456</sub>
- An adapter that owns an executor or background threads must expose a close/dispose operation that is idempotent (repeated calls safe, only the first performs shutdown), ownership-aware (releases only SDK-owned resources, never a caller-supplied executor/client), and interrupt-safe (honors thread interruption on any blocking shutdown step). (ASYNC-15)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:33-33` · high · sha:f1bf00174456</sub>
- An adapter that owns an executor should shut it down gracefully on close, stopping new work and waiting for in-flight tasks rather than interrupting them, escalating to forceful shutdown only if the closing thread is itself interrupted, with callers needing eager abort using the interrupt/structured-cancellation path instead. (ASYNC-16)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:34-34` · high · sha:f1bf00174456</sub>
- The async transport SPI should provide a no-op default close so lightweight/functional implementations need not implement lifecycle management, while any implementation that owns resources overrides it to follow the executor lifecycle contract; behavior of executeAsync after close is undefined. (ASYNC-17, ASYNC-15)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:35-35` · high · sha:f1bf00174456</sub>
- The non-blocking scheduled-delay primitive must complete after the requested delay without blocking a thread, complete immediately for a zero delay, reject a negative delay, and cancelling the returned future must cancel the underlying scheduled task so no scheduler thread is held. (ASYNC-18)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:39-39` · high · sha:f1bf00174456</sub>
- Every bridge and facade overload that accepts per-call request options must thread those options into the wrapped send so per-request overrides survive the async boundary, rather than being dropped by the SPI's options-ignoring default overload. (ASYNC-19)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:40-40` · high · sha:f1bf00174456</sub>
- Once a Response has been delivered to the caller through the future, cancelling that future must not close the Response body, since the caller owns closing it even when discarding it. (ASYNC-20, ASYNC-5)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:41-41` · high · sha:f1bf00174456</sub>
- An adapter exposing a streaming source such as SSE as a reactive stream must honor downstream backpressure by polling the source at most once per unit of demand, must complete on end-of-source, must propagate a source exception as an error signal without swallowing fatal errors, must not close the caller-owned source on any termination, and must treat the source as single-subscriber with a fresh source per subscription. (ASYNC-21)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:42-42` · high · sha:f1bf00174456</sub>
- Async transport implementations must be safe for concurrent calls from multiple threads, with all per-call mutable state confined to the returned future's completion graph. (ASYNC-22)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:43-43` · high · sha:f1bf00174456</sub>
- Components documented as shared/reusable across concurrent requests (pipeline steps, auth handlers, redactors, factories) MUST be safe for concurrent invocation, with per-call mutable state living on the call's stack/local state rather than the shared instance, and any shared mutable state synchronized. (XCUT-11)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:28` · high · sha:d6123be82c9e</sub>
- Hot-path reads of a credential/token cache SHOULD be wait-free, refresh SHOULD be single-flight so only one concurrent caller fetches an expiring token while others reuse the result, and any lock guarding refresh MUST be scoped to that cache so it never serializes unrelated in-flight requests or the global scheduler. (XCUT-12)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:29` · high · sha:d6123be82c9e</sub>
- The core SHOULD be concurrency-model agnostic, exposing plain blocking operations correct on any scheduler and leaking no async-framework types into the core public surface, with shared mutable state guarded for safe concurrent access. (NFR-11)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:33` · high · sha:5f4684bf7123</sub>
- Every async adapter MUST honour check-after-resume: after returning from any operation that may have suspended (an I/O wait, a scheduler yield, a queue pop, a task await), and before acting on the value it produced, the producer MUST re-check its cancellation state; if cancelled, it MUST close any response it holds and settle through the failure channel rather than delivering. (SEAM-30, ASYNC-5)
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:239-244` · high · sha:bf7f85fc5f18</sub>
- ASYNC-7 requires each async adapter to document in its README whether cancellation aborts the operation or lets a blocking call finish; the thread adapter lets an in-flight blocking read finish while reactor-backed adapters abort at the next scheduler checkpoint.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:254-257` · high · sha:bf7f85fc5f18</sub>
- The async runtime must reuse the identical stage identities and staging policy as the sync runtime, and the two must not each re-derive ordering independently. (PIPE-28)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:175-177` · high · sha:6b7ebc1dfd1d</sub>
- An async step returns a future and never raises for a transport failure, and the runtime converts any synchronous raise from a step's async entry point into a failed future while re-raising the fatal exception family unchanged. (PIPE-29, PIPE-30)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:179-181` · high · sha:6b7ebc1dfd1d</sub>
- The terminal response-mapping operator applies the handler and closes the response on success, tolerating an idempotent double close, and closes any response accompanying a failure. (PIPE-31)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:182-183` · high · sha:6b7ebc1dfd1d</sub>
- The async standard pipeline follows no redirects, and a port must document this asymmetry with the sync standard pipeline. (PIPE-32)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:185-186` · high · sha:6b7ebc1dfd1d</sub>
- The sync-to-async bridge requires a caller-supplied executor with no default, because a shared global pool would be starved by blocking work. (PIPE-33, SEAM-18)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:191-193` · high · sha:6b7ebc1dfd1d</sub>
- Cancelling the returned future with interruption must interrupt the worker running the in-flight send, while cancelling without interruption must complete as cancelled without interrupting the worker. (PIPE-33)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:201-203` · high · sha:6b7ebc1dfd1d</sub>

## Constraints
- Ractors cannot access mutable objects from outside their scope; only frozen objects, `Ractor.make_shareable` values, and primitives can cross Ractor boundaries safely.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:68` · high · sha:bb7cce1169e7</sub>
- Under a registered Fiber scheduler, a blocking call built on plain IO is transparently non-blocking at the fiber level, but this transparency covers only pure-Ruby, scheduler-hookable I/O.
  <sub>design · `docs/sdk-design-ruby/01-overview.md:36-38` · high · sha:a69e6feeaeb4</sub>
- C-extension transports such as typhoeus/libcurl, and some TLS paths, bypass Ruby's Fiber scheduler hooks entirely.
  <sub>design · `docs/sdk-design-ruby/01-overview.md:38-39` · high · sha:a69e6feeaeb4</sub>
- XCUT-11, SEAM-12, TRANSPORT-29, and ASYNC-22 still require per-call state to live on the call rather than on the shared instance, since the GVL makes thread-safety cheaper to achieve but no cheaper to reason about.
  <sub>design · `docs/sdk-design-ruby/01-overview.md:61-63` · high · sha:a69e6feeaeb4</sub>
- #cancel cannot pre-empt a producer because Ruby's only pre-emption mechanisms are Thread#raise and Thread#kill, which this port forbids.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:237-239` · high · sha:bf7f85fc5f18</sub>
- A transport blocked inside an uninterruptible C-extension read, such as libcurl or some TLS paths, cannot be aborted early by any mechanism this port permits, so the worker occupies its pool slot until the read returns on its own.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:210-213` · high · sha:6b7ebc1dfd1d</sub>

## Conclusions
- The async-runtime concern is deliberately not a core interface; instead it is decoupled through a canonical, dependency-free async future type that every ecosystem adapter bridges to and from (SEAM-17).
  <sub>spec · `docs/product-spec/01-product-overview.md:9-9` · high · sha:4f786c44354d</sub>
- The async transport contract SHOULD be expressed in terms of one canonical, dependency-free async primitive (a future completing with a value or exceptionally) as an interop pivot, with ecosystem facades (coroutines, reactive streams, event-loop futures, virtual threads) implemented as separate adapter modules bridging to and from that pivot (SEAM-17).
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:18-18` · high · sha:0adae2d6a47f</sub>
- The reference implements the inter-attempt retry wait as a scheduled timer completing an awaitable future so a virtual-thread carrier can unmount without monopolizing a shared pool thread, and a port SHOULD preserve that non-pinning property where its runtime has an equivalent concern. (XCUT-3)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:11` · medium · sha:d6123be82c9e</sub>
- Because Ruby genuinely has two different I/O execution models, both the synchronous transport seam (SEAM-11) and the asynchronous transport seam with its pivot (SEAM-16, SEAM-17) survive in the Ruby port, per P4's converse that a port must not collapse a split the host genuinely has.
  <sub>design · `docs/sdk-design-ruby/01-overview.md:40-42` · high · sha:a69e6feeaeb4</sub>
- SEAM-17's design of "one canonical dependency-free pivot plus per-ecosystem adapter modules" is the only shape that keeps SEAM-1 intact given Ruby's async-ecosystem fragmentation, which is even stronger than on the reference platform.
  <sub>design · `docs/sdk-design-ruby/01-overview.md:43-47` · high · sha:a69e6feeaeb4</sub>
- Because the GVL's atomicity guarantee does not hold on all Ruby implementations, the port relies on safe publication (write under a lock, read without) rather than on the GVL itself.
  <sub>design · `docs/sdk-design-ruby/01-overview.md:60-61` · high · sha:a69e6feeaeb4</sub>
- The Thread::Mutex guarding materialize-once consumption is held only across the consumed-flag flip and never across the drain, because Ruby's Mutex is per-fiber-owned and non-reentrant, so a lock held across a suspension point inside a drain would deadlock two fibers of one thread. (BODY-6, BODY-7)
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:108-112` · high · sha:bf7f85fc5f18</sub>
- The response-logging wrapper's latch uses the same flag-flip-under-mutex shape as BODY-7's, chosen for the same non-pinning reason given in the requirement's own JVM aside.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:136-137` · high · sha:bf7f85fc5f18</sub>
- Because Ruby's async ecosystem is fragmented across Async::Task, Concurrent::Promises::Future, plain Thread plus Thread::Queue, and EventMachine descendants — none in the standard library, all with different cancellation semantics — core defines its own minimal dependency-free future rather than adopting any one as the pivot, since adopting a third-party gem would violate SEAM-1 and NFR-1.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:204-209` · high · sha:bf7f85fc5f18</sub>
- The write side (Completer) is a separate object handed only to the producer so a consumer cannot settle someone else's future, which is the Ruby answer to a language with no way to hide a completion method.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:220-222` · high · sha:bf7f85fc5f18</sub>
- #value blocks on a Thread::Queue pop rather than a spin or a Kernel#sleep poll, which makes the pivot scheduler-transparent because under a registered Fiber.scheduler a blocking queue pop routes through the scheduler's block and unblock hooks instead of parking the OS thread.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:222-228` · high · sha:bf7f85fc5f18</sub>
- The rejected alternative of running the sync contract under a Fiber.scheduler was rejected because it produces no value or handle to cancel, compose, or hand to a paginator, and it presumes every consumer runs under a scheduler while foreclosing the multiplexing and structured cancellation tree capabilities that justify an async seam. (ASYNC-1, ASYNC-6, ASYNC-20, PAGE-25, PAGE-33, RETRY-30, RETRY-33, SEAM-16)
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:269-277` · high · sha:bf7f85fc5f18</sub>
- Scheduler-transparency is retained instead as a property of the synchronous transport seam rather than as the async pivot itself.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:276-278` · high · sha:bf7f85fc5f18</sub>
- A block or callback-based async contract was rejected because it inverts error handling, gives no single place to represent "exactly one success or one failure," and makes pagination and retry trampolines harder; callbacks remain the mechanism inside #on_settle, not the contract. (PAGE-31, RETRY-30)
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:277-280` · high · sha:bf7f85fc5f18</sub>
- XCUT-2's requirement that timeout and cancellation be told apart by ambient cancellation state rather than by matching a message string is satisfied by inspecting reason.class, which matters because Net::ReadTimeout is distinguishable in Ruby but Errno::* and IOError are not reliably distinguishable.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:285-289` · high · sha:bf7f85fc5f18</sub>
- Identical stage ordering between sync and async runtimes is satisfied structurally by one `Dexpace::Pipeline::Stages` module holding the frozen ordering and pillar set, through which both runtimes flatten; only the terminal dispatch and step invocation protocol differ. (PIPE-29, PIPE-30)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:177-179` · high · sha:6b7ebc1dfd1d</sub>
- The async-standard-pipeline-follows-no-redirects asymmetry is made visible rather than silent by having the async standard-pipeline factory take an explicit `redirect: :unsupported` argument, so the asymmetry appears at the call site instead of as an absence a reader must notice.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:186-189` · high · sha:6b7ebc1dfd1d</sub>
- The async-to-sync bridge is implemented as `future.value(deadline:)`, which preserves options, honours cooperative cancellation, and surfaces the original failure unwrapped, using neither `Thread#raise` nor `Timeout.timeout`. (PIPE-33, PIPE-34, ASYNC-13, ASYNC-14, SEAM-25, XCUT-22)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:196-199` · high · sha:6b7ebc1dfd1d</sub>
- This port satisfies the non-interrupting cancellation half of the bridge contract exactly, but does not satisfy the interrupting-cancellation half, because interrupt-mode cancellation is a mechanism forbidden for the whole repository, so every cancellation on this bridge behaves as the non-interrupting mode.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:203-206` · high · sha:6b7ebc1dfd1d</sub>
- The partial mitigation for non-interruptible cancellation is that the future completes as cancelled promptly so the caller is never blocked on a worker it has given up on, and the worker aborts at its next check-after-resume point, which for a `Net::HTTP` send under a socket timeout is bounded by that timeout rather than unbounded.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:206-209` · high · sha:6b7ebc1dfd1d</sub>
- The consequence of uninterruptible reads under aggressive cancellation is bounded worker occupancy rather than a correctness failure, since whatever the read eventually produces is closed on the discard path and no result is delivered to a cancelled caller; this is recorded as an unsatisfied MUST rather than a mechanism substitution. (CFG-21)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:213-215` · high · sha:6b7ebc1dfd1d</sub>

## Reference
- The Global VM Lock (GVL, formerly GIL) prevents two Ruby threads from executing bytecode simultaneously in one process, so threads give no parallelism for CPU-bound work.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:57` · high · sha:bb7cce1169e7</sub>
- I/O releases the GVL, so a thread blocked on a network call, disk read, or `sleep` yields the lock so another thread can run, giving genuine concurrency for I/O-bound work.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:58` · high · sha:bb7cce1169e7</sub>
- A Ractor is Ruby 4.0's unit of true parallelism; each Ractor has its own GVL, so N Ractors on an N-core machine can execute bytecode simultaneously.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:67` · high · sha:bb7cce1169e7</sub>
- Threads are OS-managed and carry a fixed memory overhead of roughly 1 MB of stack plus a context-switch cost, which compounds under thousands of concurrent I/O waits.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:131` · high · sha:bb7cce1169e7</sub>
- The `async` gem (socketry/async) provides a scheduler that parks a Fiber at each I/O wait and resumes it when data arrives, multiplexing thousands of Fibers over a small thread pool.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:132` · high · sha:bb7cce1169e7</sub>
- An outer `Async do` block creates a task, and inner `semaphore.async` blocks spawn child tasks; all child tasks complete before the outer block returns, giving structured concurrency without manual joining.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:133` · high · sha:bb7cce1169e7</sub>
- `Timeout.timeout` raises `Timeout::Error` from a background thread at an arbitrary point in the protected block's execution, leaving objects in partially mutated states and making it essentially un-rescueable.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:189` · high · sha:bb7cce1169e7</sub>
- A `Data` value survives Ractor transfer without `make_shareable` because the runtime already knows it is shareable, whereas a plain `Hash` or mutable `Struct` raises a `Ractor::IsolationError` at the transfer site.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:256` · high · sha:bb7cce1169e7</sub>
- I/O inside a lock risks an AB/BA deadlock when two locks protect two resources and two threads acquire them in opposite order, a condition impossible without the second lock but trivially created by adding a blocking call.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:281` · high · sha:bb7cce1169e7</sub>
- `Concurrent::AtomicFixnum` and `Concurrent::AtomicBoolean` replace `@mutex.synchronize { @count += 1 }` patterns with a single atomic operation; `Concurrent::Future` and `Concurrent::Promise` cover deferred computation; `Concurrent::FixedThreadPool` is the bounded worker pool.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:305` · high · sha:bb7cce1169e7</sub>
- A `SizedQueue` that is not closed leaves its consumer threads blocked on `deq` forever, causing a thread leak that prevents clean shutdown.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:334` · high · sha:bb7cce1169e7</sub>
- `Async` structured tasks drain automatically when the outer `Async do` block exits, making that cleanup free when using structured concurrency.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/09-concurrency.md:335` · high · sha:bb7cce1169e7</sub>
- Chapter 09 (Concurrency) covers GVL realities, `Mutex` plus immutable sharing, Ractors for parallelism, Fibers and `async`, bounded pools/queues, deadline timeouts over `Timeout.timeout`, and documented races.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:42-42` · high · sha:fa61163448dd</sub>
- The reference implementation of the canonical async interop pivot is java.util.concurrent.CompletableFuture. (SEAM-17)
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:18-18` · high · sha:0adae2d6a47f</sub>
- The async-runtime adapter contract's interchange point is a single canonical completion future carrying exactly one success value or one failure, to which every ecosystem facade (coroutines, reactive Mono/Flux, event-loop futures, virtual threads) bridges. (SEAM-17)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:3-3` · high · sha:f1bf00174456</sub>
- The canonical completion future is the single dependency-free async value type that carries exactly one success value or one failure and is the interop pivot every ecosystem adapter bridges to and from, with the JVM reference being CompletableFuture.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:13` · high · sha:f0b3d2058626</sub>
- Pooled-thread poisoning is the failure mode where an interrupt aimed at a cancelled call reaches a worker after it has returned to its pool and picked up unrelated work, prevented by an ordering handshake.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:45` · high · sha:f0b3d2058626</sub>
- The async adapter's single-value future is never null, completing either with a value or exceptionally. (ASYNC-1, ASYNC-2)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:67` · high · sha:0451cc7f3bb4</sub>
- A construction-time failure in the async adapter is delivered through the future's failure channel rather than thrown synchronously. (ASYNC-1, ASYNC-2)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:67` · high · sha:0451cc7f3bb4</sub>
- Cancellation has two modes in the async adapter, and a queued or already-finished task is never interrupted. (ASYNC-3, ASYNC-4, ASYNC-5, ASYNC-6, ASYNC-7)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:68` · high · sha:0451cc7f3bb4</sub>
- Interrupt delivery in the async adapter is ordered so that pooled-thread poisoning does not occur under stress. (ASYNC-3, ASYNC-4, ASYNC-5, ASYNC-6, ASYNC-7)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:68` · high · sha:0451cc7f3bb4</sub>
- An orphaned closeable resource on the losing side of a race in the async adapter is closed exactly once. (ASYNC-3, ASYNC-4, ASYNC-5, ASYNC-6, ASYNC-7)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:68` · high · sha:0451cc7f3bb4</sub>
- Cancellation is bidirectional per async adapter, meaning cancelling either side cancels the other. (ASYNC-3, ASYNC-4, ASYNC-5, ASYNC-6, ASYNC-7)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:68` · high · sha:0451cc7f3bb4</sub>
- Each async adapter documents whether it uses interrupt-mode cancellation or not. (ASYNC-3, ASYNC-4, ASYNC-5, ASYNC-6, ASYNC-7)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:68` · high · sha:0451cc7f3bb4</sub>
- Logging context propagates across asynchronous hops. (ASYNC-8, ASYNC-9, ASYNC-10, ASYNC-11, ASYNC-12)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:69` · high · sha:0451cc7f3bb4</sub>
- Logging context is saved, installed, and restored across an async hop, including when the operation throws. (ASYNC-8, ASYNC-9, ASYNC-10, ASYNC-11, ASYNC-12)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:69` · high · sha:0451cc7f3bb4</sub>
- Logging context is captured per-subscription or per-submission in the async adapter, not once at assembly time. (ASYNC-8, ASYNC-9, ASYNC-10, ASYNC-11, ASYNC-12)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:69` · high · sha:0451cc7f3bb4</sub>
- Async logging-context propagation is safe when no logging backend is present. (ASYNC-8, ASYNC-9, ASYNC-10, ASYNC-11, ASYNC-12)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:69` · high · sha:0451cc7f3bb4</sub>
- On lightweight-thread runtimes, logging-context transfer at the thread-creation boundary is explicit. (ASYNC-8, ASYNC-9, ASYNC-10, ASYNC-11, ASYNC-12)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:69` · high · sha:0451cc7f3bb4</sub>
- Async wrapper-exception unwrapping is cycle-safe. (ASYNC-13, ASYNC-14)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:70` · high · sha:0451cc7f3bb4</sub>
- The blocking bridge onto an async result honors interruption and unwraps the wrapper exception. (ASYNC-13, ASYNC-14)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:70` · high · sha:0451cc7f3bb4</sub>
- Closing an SDK-owned executor is idempotent, ownership-aware, and interrupt-safe. (ASYNC-15, ASYNC-16, ASYNC-17)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:71` · high · sha:0451cc7f3bb4</sub>
- Closing the async adapter gracefully shuts down its owned executor. (ASYNC-15, ASYNC-16, ASYNC-17)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:71` · high · sha:0451cc7f3bb4</sub>
- A functional-interface-based async implementation defaults its close operation to a no-op. (ASYNC-15, ASYNC-16, ASYNC-17)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:71` · high · sha:0451cc7f3bb4</sub>
- A scheduled delay in the async adapter is non-blocking, resolves immediately for a zero delay, rejects a negative delay, and cancelling it cancels the underlying task. (ASYNC-18, ASYNC-19, ASYNC-20, ASYNC-21, ASYNC-22)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:72` · high · sha:0451cc7f3bb4</sub>
- Per-call options are threaded through every async bridge. (ASYNC-18, ASYNC-19, ASYNC-20, ASYNC-21, ASYNC-22)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:72` · high · sha:0451cc7f3bb4</sub>
- A Response already delivered to the caller is not closed by a late cancellation. (ASYNC-18, ASYNC-19, ASYNC-20, ASYNC-21, ASYNC-22)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:72` · high · sha:0451cc7f3bb4</sub>
- The reactive SSE bridge honors backpressure, does not close the source itself, and supports only a single subscriber. (ASYNC-18, ASYNC-19, ASYNC-20, ASYNC-21, ASYNC-22)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:72` · high · sha:0451cc7f3bb4</sub>
- The async transport implementation is concurrency-safe. (ASYNC-18, ASYNC-19, ASYNC-20, ASYNC-21, ASYNC-22)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:72` · high · sha:0451cc7f3bb4</sub>
- Ruby has two genuinely different I/O execution models — a real blocking model exemplified by a thread parked in read(2) with Net::HTTP's socket timeouts, and a real reactor model exemplified by async/async-http driving Async::Task objects under a registered Fiber.scheduler.
  <sub>design · `docs/sdk-design-ruby/01-overview.md:34-37` · high · sha:a69e6feeaeb4</sub>
- A reactor-native HTTP client exposes HTTP/2 stream multiplexing and a structured cancellation tree that no blocking call can express even when perfectly scheduled.
  <sub>design · `docs/sdk-design-ruby/01-overview.md:39-40` · high · sha:a69e6feeaeb4</sub>
- async's Async::Task, concurrent-ruby's Concurrent::Promises::Future, plain Thread plus Thread::Queue, and EventMachine-descended deferrables are mutually incompatible async primitives with different cancellation semantics, and none of them is in the Ruby standard library. (SEAM-17)
  <sub>design · `docs/sdk-design-ruby/01-overview.md:43-46` · high · sha:a69e6feeaeb4</sub>
- On CRuby, the Global VM Lock (GVL) makes a lone instance-variable reference read or write atomic, satisfying XCUT-12's wait-free credential read in the way the JVM needs a volatile field for, but this guarantee does not hold on JRuby or TruffleRuby.
  <sub>design · `docs/sdk-design-ruby/01-overview.md:58-61` · high · sha:a69e6feeaeb4</sub>
- Fiber.scheduler, available from Ruby 3.0, makes the blocking I/O contract scheduler-transparent and makes RETRY-26's requirement that retry MUST NOT pin an execution carrier a live concern in Ruby rather than a JVM-only one.
  <sub>design · `docs/sdk-design-ruby/01-overview.md:64-66` · high · sha:a69e6feeaeb4</sub>
- Dexpace::Async::Future exposes #settled?, #cancelled?, #value(deadline: nil) which blocks and raises the failure, #wait(deadline: nil) which settles-or-times-out and never raises, #on_settle which is invoked exactly once, and #cancel(reason) which is cooperative; Dexpace::Async::Completer is the write side with #fulfil(response), #fail(error), and #on_cancel.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:211-219` · high · sha:bf7f85fc5f18</sub>
- Thread::Mutex ownership is per-fiber, not per-thread; locking a held mutex from a second fiber of the same thread raises ThreadError rather than succeeding (verified).
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:224-226` · high · sha:bf7f85fc5f18</sub>
- Completer#on_cancel gives the producer a hook to abort promptly, such as closing a socket or stopping a task, rather than only at the next resume.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:245-246` · high · sha:bf7f85fc5f18</sub>
- dexpace-async-thread drives the future pivot from a bounded Thread::SizedQueue pool as a zero-third-party implementation; dexpace-transport-async_http drives it from an Async::Task under a reactor, exercising multiplexing, structured cancellation, and scheduler-native suspension.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:248-252` · high · sha:bf7f85fc5f18</sub>
- dexpace-async-async later maps Async::Task#stop and #with_timeout onto the pivot's cancellation in both directions per ASYNC-6, and dexpace-async-concurrent_ruby maps Concurrent::Promises::Future.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:252-254` · high · sha:bf7f85fc5f18</sub>
- CFG-21 requires that when an interruptible-task future has already been cancelled and the task nonetheless produced a closeable resource result, that result MUST be closed on the discard path (best-effort, swallowing close failures) rather than leaked.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:262-264` · high · sha:bf7f85fc5f18</sub>
- Core defines Dexpace::Cancellation, a token carrying a typed #reason, composable via Cancellation.any(caller_token, deadline_token) and derivable per call, threaded through the sync seam as an ordinary argument and through the async seam as the future's own state. (XCUT-2)
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:282-286` · high · sha:bf7f85fc5f18</sub>
- Core defines the sync-to-async bridge executor as a duck type exposing `#post { ... }` and ships no implementation; the `dexpace-async-thread` gem supplies a bounded `Thread::SizedQueue` pool and `dexpace-async-async` supplies an `Async::Task`-backed one.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:192-194` · high · sha:6b7ebc1dfd1d</sub>
- The sync-to-async bridge runs the whole synchronous pipeline as one opaque unit on the executor, so its steps stay synchronous on the worker and do not gain per-step concurrency. (PIPE-33, PIPE-34)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:194-196` · high · sha:6b7ebc1dfd1d</sub>
- The async-to-sync bridge owns no executor, so closing it touches nothing. (ASYNC-13, ASYNC-14, SEAM-25, XCUT-22)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:198-199` · high · sha:6b7ebc1dfd1d</sub>
- `Completer#on_cancel` lets a transport adapter shorten worker abandonment further by closing the socket out from under an in-progress read.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:209-210` · high · sha:6b7ebc1dfd1d</sub>

## Conflicts

## Superseded
