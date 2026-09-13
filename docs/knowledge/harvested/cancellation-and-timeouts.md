# cancellation-and-timeouts

## Rules
- Blocking transports SHOULD honor cooperative cancellation during blocking I/O; async transports SHOULD treat cancelling the returned future as a best-effort abort of the in-flight exchange (SEAM-13).
  <sub>spec · `docs/product-spec/02-architectural-principles.md:26-26` · high · sha:8014d2ec2c9d</sub>
- Cancellation is terminal and non-retryable and MUST be told apart from a retryable timeout out-of-band, never by matching an error message. (RETRY-23, RETRY-24)
  <sub>spec · `docs/product-spec/02-architectural-principles.md:27-27` · high · sha:8014d2ec2c9d</sub>
- On the sync path, a caller-initiated cancellation must surface as a terminal, non-retryable interrupt-shaped I/O exception with the runtime's cancellation signal preserved, must not be repackaged as the retryable transport-failure exception, and discrimination must be out-of-band via the runtime's cancellation state rather than by matching messages. (TRANSPORT-3)
  <sub>spec · `docs/product-spec/17-transport-adapter-conformance-contract.md:12-12` · high · sha:2d5843c58993</sub>
- A read/response timeout must be classified as a retryable transport failure (the canonical NetworkException) and must not set the caller's cancellation flag, even when the runtime represents a timeout with the same exception family as an interrupt. (TRANSPORT-4)
  <sub>spec · `docs/product-spec/17-transport-adapter-conformance-contract.md:13-13` · high · sha:2d5843c58993</sub>
- A per-call timeout override applies only to that single call, overriding the configured default for that call alone and leaving the shared native client untouched, while a null override leaves the configured default in force. (TRANSPORT-5)
  <sub>spec · `docs/product-spec/17-transport-adapter-conformance-contract.md:14-14` · high · sha:2d5843c58993</sub>
- A transport should not let a positive per-call timeout be silently reduced to zero by unit truncation; where the native timeout API is coarser than the requested duration and treats zero as no-timeout, a positive sub-resolution duration must be clamped up to the smallest finite deadline rather than truncated to zero. (TRANSPORT-6)
  <sub>spec · `docs/product-spec/17-transport-adapter-conformance-contract.md:15-15` · high · sha:2d5843c58993</sub>
- Cancelling the async response future must propagate cancellation into the in-flight native exchange so its connection/resources are released promptly. (TRANSPORT-7)
  <sub>spec · `docs/product-spec/17-transport-adapter-conformance-contract.md:16-16` · high · sha:2d5843c58993</sub>
- Where the native client can surface a cancellation originating inside it while the SDK future is still live, that cancellation must complete the future with a terminal, non-retryable cancellation-shaped exception rather than the retryable type, while a genuine timeout on the same path must still complete retryable; this is implemented by the OkHttp reference and a transport with no internal-cancel path need not support it. (TRANSPORT-8)
  <sub>spec · `docs/product-spec/17-transport-adapter-conformance-contract.md:17-17` · high · sha:2d5843c58993</sub>
- If a native response is delivered after the SDK future has already completed or cancelled, the adapted response must be closed so its connection is returned to the pool. (TRANSPORT-9)
  <sub>spec · `docs/product-spec/17-transport-adapter-conformance-contract.md:18-18` · high · sha:2d5843c58993</sub>
- When an async operation is backed by a blocking task on a worker thread, cancellation must distinguish cancel-with-interrupt (interrupts the worker running the in-flight task) from cancel-without-interrupt (cancels the logical operation without interrupting), and a task still queued or already finished must not be interrupted. (ASYNC-3)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:12-12` · high · sha:f1bf00174456</sub>
- Interrupt delivery must be ordered so a stale interrupt cannot poison a pooled thread—the cancel path publishes an "interrupt in flight" marker before reading the worker, the worker's return-to-pool step blocks until that marker clears, and after the task ends the worker clears its own interrupt flag before reuse—so a worker already returned to its pool must not receive an interrupt aimed at a completed call. (ASYNC-4)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:13-13` · high · sha:f1bf00174456</sub>
- If a worker computes a closeable result but the future was already terminated so the value can never be delivered, the adapter must close that orphaned value exactly once, with whoever loses the produce/terminate race performing the close. (ASYNC-5)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:14-14` · high · sha:f1bf00174456</sub>
- Cancellation must propagate bidirectionally across each adapter—cancelling the runtime-native primitive (subscription, promise, coroutine/job) must cancel the underlying canonical future, and cancelling the canonical future must reach the runtime primitive or native transport call. (ASYNC-6)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:15-15` · high · sha:f1bf00174456</sub>
- A thread/task cancellation MUST be surfaced as a distinct, terminal, non-retryable signal kept separate from a timeout, propagating without losing the ambient cancellation flag and never letting a cancelled operation be automatically retried. (XCUT-1)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:9` · high · sha:d6123be82c9e</sub>
- A read/response/connect timeout MUST be classified as a retryable transport failure and MUST NOT set the cancellation flag, with timeout and cancellation told apart by the ambient cancellation state rather than a message string, checking the timeout branch first even when the timeout type is a subtype of the cancellation type. (XCUT-2)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:10` · high · sha:d6123be82c9e</sub>
- The time seam must expose a wall clock, a monotonic elapsed counter, and a blocking interruptible sleep. (CFG-15, RETRY-26)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:197-198` · high · sha:180a9abbb69f</sub>
- The inter-attempt retry wait must be cancellable and must not pin an execution carrier for its duration; a naive uninterruptible sleep that cannot be cancelled is non-conforming. (RETRY-26, XCUT-3)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:198-199` · high · sha:180a9abbb69f</sub>
- The retry wait must abort near-immediately on cancellation, surfacing the cancellation signal rather than a spurious timeout. (XCUT-3)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:199-201` · high · sha:180a9abbb69f</sub>
- Timeout.timeout, Thread#raise, and Thread#kill are forbidden in every gem in the repository, enforced by lint.
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:215-217` · high · sha:180a9abbb69f</sub>
- Deadlines are propagated as explicit values to open_timeout/read_timeout/write_timeout on the synchronous path, where they fail at a well-defined syscall boundary with a typed exception, and to the task's own timeout on the async path, where they interrupt only at a scheduler checkpoint. (ASYNC-3)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:219-222` · high · sha:180a9abbb69f</sub>

## Constraints
- Timeout.timeout schedules an asynchronous interrupt that can land on any bytecode instruction, including inside an ensure block that is releasing a pooled connection or between a socket read and the bookkeeping that records it, which is precisely how a connection pool can acquire a corrupt entry that later fails an unrelated request.
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:216-219` · high · sha:180a9abbb69f</sub>

## Conclusions
- Each adapter independently chooses whether its native cancellation maps to interrupt-mode or non-interrupt-mode, determining whether an in-flight blocking call is aborted, and a port should preserve and document, per adapter, whether cancelling through a runtime aborts a blocking transport or lets it run to completion. (ASYNC-7)
  <sub>spec · `docs/product-spec/18-asynchronous-runtime-adapter-contract.md:16-16` · high · sha:f1bf00174456</sub>
- Clock#sleep(duration, cancellation:) is implemented as a bounded wait on a per-call Thread::Queue that the cancellation token pushes to on cancel, rather than as Kernel#sleep, so cancellation wakes the wait immediately rather than at the end of the interval. (CFG-15, RETRY-26, XCUT-3)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:205-208` · high · sha:180a9abbb69f</sub>
- The prohibition on Timeout.timeout and Thread#raise/kill is the direct cause of three unsatisfied MUST requirements — two-mode cancellation, a pooled-thread interrupt-ordering handshake, and an interrupt clause — of which the pooled-thread handshake holds vacuously while the other two have their antecedents satisfied by dexpace-async-thread and are genuinely not met. (ASYNC-3, ASYNC-4, PIPE-33)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:222-225` · high · sha:180a9abbb69f</sub>
- The prohibition on Thread#raise is judged the right trade-off despite leaving three MUST requirements unsatisfied, because adopting Thread#raise to satisfy them would put every ensure block in the repository, including ones releasing pooled connections, at the mercy of an interrupt landing mid-instruction. (ASYNC-4)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:225-228` · high · sha:180a9abbb69f</sub>

## Reference
- The reference JVM implementation surfaces cancellation by catching the interrupt, re-asserting the interrupt state, and throwing the I/O-family cancellation type. (XCUT-1)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:9` · high · sha:d6123be82c9e</sub>
- Under a registered Fiber.scheduler, the Clock#sleep queue pop routes through the scheduler's block/unblock hooks and unmounts the fiber so no carrier is pinned; with no scheduler registered it blocks only the calling thread and never a shared pool thread. (RETRY-26, XCUT-3)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:208-211` · high · sha:180a9abbb69f</sub>
- Process.clock_gettime(Process::CLOCK_MONOTONIC) is the elapsed-time counter used only for differences, and Time.now is the wall clock, which is never used to measure elapsed time; both are behind an injectable seam so tests control them. (CFG-16, CFG-15)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:211-213` · high · sha:180a9abbb69f</sub>

## Conflicts

## Superseded
