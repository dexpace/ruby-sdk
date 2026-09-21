# dexpace-async-thread

Part of the [dexpace Ruby SDK](../../README.md): an HTTP-client toolkit, not an HTTP client.
This gem is the async-runtime seam's adapter over plain Ruby threads — the zero-third-party async
driver: a bounded worker pool over `::Thread` and `::Thread::SizedQueue` that satisfies `SEAM-18`'s
caller-supplied-executor contract and settles the core-owned pivot (`Dexpace::Async::Future`).

**Status: built by phase 8b at `0.0.0`, not yet published.** `lib/` holds one public class,
`Dexpace::Async::Thread::Pool`, its rejection error `RejectedError`, the `REQUIRED_CORE` constant
and the version-skew guard that runs at `require`. The as-built page is
`docs/sdk-documentation/async-thread.md`; the per-requirement proof is
`docs/work/mvp/phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter-checklist.md`.

## Install

```ruby
# Gemfile
gem "dexpace-async-thread"
```

## The smallest thing that works

```ruby
require "dexpace/async/thread"

pool = Dexpace::Async::Thread::Pool.build(size: 4)
begin
  async = Dexpace::Transport.async_over(transport, executor: pool) # any synchronous transport
  future = async.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
  response = future.value(deadline: Dexpace::Clock.deadline_in(30))
  # ...
ensure
  pool.close
end
```

`size:` is required and has no default, for the reason `SEAM-18` gives for the executor itself: the
right number is a function of your service, its latency and its connection budget, none of which
the SDK can see, and a wrong guess is starvation. The object that must be in an `ensure` is the one
you hold, so the `ensure` is yours: the gem never registers an `at_exit` hook and never installs a
process-wide default pool.

## What the pool is

| Call | Behaviour |
|---|---|
| `Pool.build(size:, queue_limit: nil, shutdown_timeout: 30.0, name:, logger:, clock:)` | Creates exactly `size` worker threads now, named `"<name> worker N"`; never grows or shrinks. `queue_limit` defaults to `size * QUEUE_DEPTH_PER_WORKER` (8). `shutdown_timeout` is a bound, so it must be a real, finite, non-negative number. Every bad argument is `Dexpace::InvalidArgumentError` naming the keyword. |
| `#post { … }` | `Dexpace::Page::_Executor` exactly. **Never blocks**: a full queue raises `RejectedError` (backpressure to retry or shed), a closed pool raises `Dexpace::ClosedError` (a lifecycle bug). Through `Transport.async_over` either arrives as a failed future, never a synchronous raise (`ASYNC-2`). Returns `nil`. |
| `#delay(seconds)` | `ASYNC-18`'s scheduled delay: a `Dexpace::Async::Future` settled with `true` after the interval, on one lazily created `"<name> timer"` thread shared by every outstanding delay. Zero settles before the call returns; a negative, non-finite (`NaN`, an infinity), non-real (a `Complex`) or non-`Numeric` duration raises `Dexpace::InvalidArgumentError` before anything is scheduled; cancelling the future removes the entry at once; a closed pool answers a future failed with `Dexpace::ClosedError`. |
| `#close` | Idempotent, `Dexpace::Closeable`'s latch. Stops accepting work, lets the in-flight and the already-queued tasks finish, fails every outstanding delay with `Dexpace::ClosedError`, waits for the workers and the timer within one `shutdown_timeout` budget, then emits `http.instrumentation.shutdown` once (`SEAM-25`). Returns `nil`; whether the drain completed rides on the event's `dexpace.executor.drained` field. Safe from any thread, the pool's own included: a close issued from inside a task, or from a delay's settlement handler, completes without waiting for the thread it is running on (below). |

A caller-supplied executor passed to `Transport.async_over` is never closed by the bridge: closing the
bridge leaves the pool open and usable (`ASYNC-15`, `XCUT-22`).

## Cancellation and in-flight work

`dexpace-async-thread` lets an in-flight blocking read finish; a reactor-backed adapter is designed to
abort at the next scheduler checkpoint instead (`ASYNC-7`; design §3.3's contrast, the behaviour
`dexpace-transport-async_http` is specified to carry).
Cancelling a future whose send is already running on a worker does not interrupt that worker —
`Thread#raise` and `Thread#kill` are forbidden throughout this SDK (design §8.3), because an
asynchronous interrupt can land inside an `ensure` releasing a pooled connection. The worker's
blocking call runs to completion; the SDK closes the result exactly once rather than delivering it
(`ASYNC-5`), and the future settles as cancelled with the caller's reason. A task cancelled while it
is still queued never reaches the transport at all: phase 2's bridge checks the token before it
dispatches as well as after.

The practical consequence: cancelling a request routed through this pool bounds *your* wait, not the
worker's occupancy. A transport blocked inside an uninterruptible read occupies its pool slot until
the read returns on its own. Give the wrapped transport its own timeout, and size the pool for the
concurrency you actually want blocked at once.

## The diagnostic context crosses the hop

`Fiber[]`'s diagnostic context (`trace.id`, `span.id`, whatever else you put there) is captured at
each `#post`, on the caller's fiber, and installed on the worker for the block's duration through
`Dexpace::Instrumentation::Diagnostics.with` (`ASYNC-8`–`ASYNC-12`). A worker starts with empty
storage whatever the fiber that built the pool held, and is returned to empty after every task,
including one that raised, so nothing leaks from the pool's builder or from one caller's task into
the next caller's log lines.

The same discipline holds on the pool's second thread, the timer behind `#delay`: each `#delay`
captures its caller's context, and a `#on_settle` or `#then` on that delay's future runs under it —
the context of the caller who asked for *that* delay, never the first caller's, whose context the
timer thread inherited when it was spawned, and never a key an earlier handler wrote. An entry
`#close` fails settles on the closing thread under the delay caller's context too, and the closing
thread's own context is put back afterwards.

**A mutable object you put into fiber storage is shared with the worker.** The snapshot is captured,
not deep-copied: its keys are frozen, but an `Array` or a `Hash` value is the same object on both
sides of the hop. Keep the values you push into `Fiber[]` immutable, or synchronise your own access
to them.

## Where callbacks run

`Future#on_settle` runs on the settling thread. For a future from `Transport.async_over` over this
pool that is a **pool worker**; for a future from `#delay` it is the **timer thread**, or the closing
thread when `#close` fails it — in every case under the diagnostic context of the caller who posted
the task or asked for the delay. A handler that blocks is blocking that thread: every later delay
behind a stuck timer handler, or one worker's slot behind a stuck settlement handler. A handler that
raises is reported as an `http.instrumentation.hook` diagnostic through the pool's `logger:` and the
thread lives; a block posted to the pool that raises anything at all — a `NotImplementedError`, an
`exit`, an `Interrupt` — is reported the same way, and the pool is never one worker smaller for it.

A handler or a task that **closes the pool** completes the close where it runs. From a delay's
settlement handler — the grace-period idiom, `pool.delay(5).on_settle { pool.close }` — the timer
thread is not joined by itself: the other outstanding delays are failed, the workers are drained and
the shutdown event is emitted, and the timer thread exits as soon as the handler returns. From inside
a posted task, the worker running it counts as drained and is not waited for: `#close` returns as soon
as the other workers have exited, that worker finishes its task, runs whatever the closed queue still
held, and exits. Neither path waits out the shutdown budget or raises.

## Depends on

`dexpace-core` only, by design: a thread is the runtime every Ruby already has, so this adapter
spends none of its `NFR-2` budget. The entry file asserts at `require` that the loaded
`dexpace-core` satisfies `REQUIRED_CORE` and raises `Dexpace::SeamError` naming both versions if it
does not.

## Where to read next

- `docs/sdk-documentation/async-thread.md` — the as-built page, every example run on 4.0.6 and 3.2.11.
- `docs/sdk-documentation/seams.md` — the executor duck type, the two bridges and the pivot this pool settles.
- `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.3 and §3.7 — the pivot, the check-after-resume rule and the close contract.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` — the gem layout and the zero-dependency invariant.
