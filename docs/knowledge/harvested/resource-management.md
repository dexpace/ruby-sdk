# resource-management

## Rules
- Use block form (e.g., `File.open(path) { |f| ... }`, `Tempfile.create`, `pool.with_connection`) for every closable resource so the underlying close runs on any exit path — normal return, uncaught exception, or explicit raise.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:50-56` · high · sha:9abc7f90733b</sub>
- Nest block-form resource acquisitions rather than acquiring multiple resources at the same level, so that teardown order is established by construction with the innermost block exiting first.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:56-56` · high · sha:9abc7f90733b</sub>
- When no block form exists for a resource, place the acquisition before a `begin` block and the release in the corresponding `ensure` clause, nil-guarding the `ensure` so it is safe even if acquisition failed.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:78-79` · high · sha:9abc7f90733b</sub>
- Make close calls idempotent by checking for nil or a closed flag before calling close, since a double-close on many clients such as sockets or DB adapters raises an error.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:80-80` · high · sha:9abc7f90733b</sub>
- Release resources in `ensure`, never in `rescue`, because `rescue` handles errors while `ensure` handles cleanup, and mixing them skips cleanup on a normal return or a re-raise that bypasses the rescue.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:81-81` · high · sha:9abc7f90733b</sub>
- Never open one connection per request; size connection or HTTP pools with a bounded, named constant instead, since an unbounded per-request connection count can exceed the upstream's hard connection ceiling and cause request failures.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:105-111` · high · sha:9abc7f90733b</sub>
- Name a connection pool's size constant at module scope with a `T.let` type annotation rather than embedding a literal number in the pool constructor, so the capacity decision is greppable and reviewable.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:110-110` · high · sha:9abc7f90733b</sub>
- Pair every connection pool with a checkout timeout so that a saturated pool fails fast rather than queuing indefinitely and exhausting caller threads.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:111-111` · high · sha:9abc7f90733b</sub>
- Replace unbounded per-instance memoization with a bounded LRU cache when the key space is large or unbounded, setting `max_size` from the expected working set and available memory rather than from items seen so far.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:142-143` · high · sha:9abc7f90733b</sub>
- Pair a cache's size bound with a TTL where the cached data has a meaningful freshness window, so size prevents memory exhaustion and TTL prevents stale data.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:144-144` · high · sha:9abc7f90733b</sub>
- A module-level or class-level cache shared across threads (e.g., `@@cache` or a class-side `Hash`) requires a `Mutex` or a thread-safe cache implementation, since an unsynchronized shared hash corrupts under concurrent writes.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:145-145` · high · sha:9abc7f90733b</sub>
- Set a per-call timeout at the client level for every external I/O call — for example `Net::HTTP#read_timeout`, `redis.timeout`, `pg`'s `:connect_timeout`, or `Async::Task#with_timeout` in an async context.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:180-184` · high · sha:9abc7f90733b</sub>
- Set I/O timeouts at the granularity of a single network call rather than relying on a single global timeout, since a global timeout does not bound the total blocking time of a batch of sequential calls.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:185-185` · high · sha:9abc7f90733b</sub>
- Expose every I/O timeout as a named constant (e.g., `FETCH_TIMEOUT = T.let(5.0, Float)`) rather than a magic number embedded in a client constructor.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:186-186` · high · sha:9abc7f90733b</sub>
- Never rely on finalizers or the garbage collector for deterministic resource cleanup; use block form or `ensure` instead.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:224-229` · high · sha:9abc7f90733b</sub>
- `ObjectSpace.define_finalizer` may only be used as a leak detector that logs a warning when an object is collected without having been explicitly closed, and any such use must carry a comment naming its diagnostic purpose.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:230-230` · high · sha:9abc7f90733b</sub>
- Release resources in reverse acquisition order — the resource acquired last (e.g., a cursor depending on a transaction depending on a connection) is released first — so nothing is released while something layered on it is still alive.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:271-275` · high · sha:9abc7f90733b</sub>
- When writing composite teardown by hand in a single `ensure` clause, list the close calls bottom-up and annotate the dependency reason (e.g., why the cursor closes before the transaction).
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:276-276` · high · sha:9abc7f90733b</sub>
- Track every spawned thread or Ractor in a collection and join it in a teardown path that is guaranteed to run, since a thread with no reference to join can never be recovered.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:310-314` · high · sha:9abc7f90733b</sub>
- Fiber teardown is the caller's responsibility: call `.resume` until the fiber finishes, or in `async` contexts call `.stop` on the task.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:315-315` · high · sha:9abc7f90733b</sub>
- Supervisors and worker pools must expose a `shutdown` method that signals workers to drain their queue and joins each worker thread before the method returns, invoked by callers in an `ensure` clause or `at_exit` hook rather than relying on GC.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:316-316` · high · sha:9abc7f90733b</sub>
- Make every `at_exit` hook body idempotent and nil-guarded so it does not raise if another hook or an `ensure` clause already closed the resource.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:367-367` · high · sha:9abc7f90733b</sub>
- Prefer explicit lifecycle ownership — a class that opens a resource in its constructor exposes a `close` method the caller invokes in an `ensure` clause — over relying on `at_exit`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:368-368` · high · sha:9abc7f90733b</sub>
- Reserve `at_exit` for process-level resources with no owning object, such as a PID file, lock file, or metrics flush, and document why explicit lifecycle ownership was not feasible.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:369-369` · high · sha:9abc7f90733b</sub>
- Wrap a raw resource handle (socket, file descriptor, lock) in a small object that owns its lifecycle and exposes a `with_` block method, so callers use block form without knowing the internals.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:399-403` · high · sha:9abc7f90733b</sub>
- Keep a resource wrapper limited to acquire, yield, and release, with no business logic inside the wrapper itself.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:404-404` · high · sha:9abc7f90733b</sub>
- Annotate a wrapper's `with_` method with a `sig` that reflects the block's parameter type, since the block parameter type is the resource's public interface rather than the raw handle.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:405-405` · high · sha:9abc7f90733b</sub>

## Constraints
- Ruby's `Timeout.timeout` raises `Timeout::Error` from a background thread, which can interrupt arbitrary C-extension code mid-write and corrupt client state, so it must not be used as a per-call I/O deadline.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:184-184` · high · sha:9abc7f90733b</sub>
- `ObjectSpace.define_finalizer` procs are non-deterministic, run on a separate thread, may coalesce, and are not guaranteed to run at process exit at all.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:228-228` · high · sha:9abc7f90733b</sub>
- An exception raised from a close call inside an `ensure` clause replaces the original in-flight exception and hides the real failure, so each close call must be safe to call twice.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:277-277` · high · sha:9abc7f90733b</sub>
- `at_exit` hooks execute in reverse registration order after all threads have terminated, an ordering that is fragile because a dependency's hook may run before or after the caller's own hook, and the hook receives no signal about which exit path fired.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:363-367` · high · sha:9abc7f90733b</sub>

## Conclusions
- Ruby's block form and `ensure` are treated as the language's mechanism for guaranteed resource cleanup, because closable resources such as file handles, connections, sockets, locks, and thread stacks outlive the call that opens them unless something explicitly closes them on every path, including the exceptional one.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:3-3` · high · sha:9abc7f90733b</sub>

## Reference
- RuboCop's `Style/AutoResourceCleanup` cop enforces block-form usage for closable resources, and review checks any `.open` or `.new` on a closable type not paired with a block or an `ensure` clause.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:73-73` · high · sha:9abc7f90733b</sub>
- Any method that opens a resource without a block form must have an `ensure` clause on the containing `begin`, with the close call nil-guarded or idempotent, verified in review.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:103-103` · high · sha:9abc7f90733b</sub>
- `ConnectionPool.new`, `redis-client`, or any DB adapter must reference a named `MAX_*` constant for the pool size argument; bare numeric literals in pool constructors are rejected in review and by grep.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:137-137` · high · sha:9abc7f90733b</sub>
- Any `Hash` used as a cache must declare a `MAX_*` constant and a TTL where applicable; unbounded `Hash` caches are rejected in review.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:178-178` · high · sha:9abc7f90733b</sub>
- Every HTTP, DB, Redis, gRPC, or socket client must set `open_timeout`/`read_timeout` (or the equivalent) to a named constant; bare `Timeout.timeout` wrappers are rejected in review.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:222-222` · high · sha:9abc7f90733b</sub>
- Any occurrence of `ObjectSpace.define_finalizer` must carry a comment marking it as a diagnostic-only leak detector, verified by review and grep.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:269-269` · high · sha:9abc7f90733b</sub>
- Composite teardown must release in reverse order, any `ensure` closing multiple resources must be annotated with the dependency order, and block nesting is the default approach for two or more resources.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:308-308` · high · sha:9abc7f90733b</sub>
- Any `Thread.new` or `Ractor.new` whose handle is not stored for a later `join` or `wait` is rejected in review, and worker pools must expose a `shutdown` that joins all workers.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:361-361` · high · sha:9abc7f90733b</sub>
- Each `at_exit` occurrence must carry a comment explaining why explicit lifecycle ownership was not used, and its body must be idempotent and nil-guarded, verified by review and grep.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:397-397` · high · sha:9abc7f90733b</sub>
- Raw resource handles must not be passed across method boundaries without a wrapping object that owns the lifecycle; the wrapper must expose a `with_` block method and must not expose the raw handle as a public attribute.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/13-resource-management.md:464-464` · high · sha:9abc7f90733b</sub>

## Conflicts

## Superseded
