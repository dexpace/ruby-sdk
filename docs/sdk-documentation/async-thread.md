# The async-runtime adapter: `dexpace-async-thread`

**As built by phase 8b, in `dexpace-async-thread`, written against source on 2026-09-21.** This page
says what the zero-third-party async driver gives an SDK author today: `Dexpace::Async::Thread::Pool`,
a fixed-size `::Thread` pool over a bounded `::Thread::SizedQueue` that is the first real
implementation of `SEAM-18`'s caller-supplied executor duck type and of `Dexpace::Page::_Executor`,
the producer that settles phase 2's core-owned pivot from a worker thread, the `ASYNC-15`–`ASYNC-17`
lifecycle over `Dexpace::Closeable` with `SEAM-25`'s shutdown event, the `ASYNC-8`–`ASYNC-12`
diagnostic hop over `Fiber[]`, and `ASYNC-18`'s scheduled delay on one timer thread. What each is
*required* to do is `docs/product-spec/18-asynchronous-runtime-adapter-contract.md` (`ASYNC-1`–`ASYNC-20`,
of which this gem owns nineteen; `ASYNC-6`, `ASYNC-21` and `ASYNC-22` are the asynchronous transport's);
how the design maps it to Ruby is `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.3 and §3.7
read with entries 3, 4 and 5 of `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`;
the per-requirement proof is `docs/work/mvp/phase8/phase8b/2026-09-11-phase8b-async-runtime-adapter-checklist.md`.
Signatures live in `gems/dexpace-async-thread/sig/`, and this page does not restate them. Every example
below was run, in the order printed and as one script, against the built code on 4.0.6 and 3.2.11 and
printed the same on both, except for `Hash#inspect`'s spelling, the wording of a `NoMethodError` and the
last line's thread count (the socket block's one connection starts net-http 0.4.1's process-wide Timeout
thread on the 3.2 row, and nothing on 4.0.6; `docs/sdk-documentation/transport-net_http.md` has the fact).
Seven names are the page's shorthand and nothing else is assumed: `Pool` is `Dexpace::Async::Thread::Pool`;
`EMPTY` is `Dexpace::RequestOptions::EMPTY`; `NONE` is `Dexpace::Cancellation.none`; `req(url)` is
`Dexpace::Request.build(method: :get, url: url, headers: Dexpace::Headers::EMPTY)`; `e` is the
`RejectedError` the line before it raised, rescued; `sink` is an in-memory `_Sink` — the eight duck-typed
methods, `#debug`/`#info`/`#warn`/`#error` taking stdlib `Logger`'s block form and appending the rendered
`Hash` the block yields to `#events`, and the four predicates answering `true` (the gem's
`PoolRecordingSink` is one); `fake` is a lambda answering a plain 200 `Response` for any
request; and `strategy` is a `Dexpace::Page::_Strategy` whose `#parse(response, template)` answers two
pages — `[1, 2]` with the template as the next request, then a terminal `[3]` — the gem's
`page_executor_test.rb` has both in full. `pool` is the two-worker pool the first block builds and the
last block closes.

**The gem's whole dependency budget is `dexpace-core`** (`NFR-2`), by design: a thread is the runtime
every Ruby already has, so the gem spends none of its third-party half. Requiring it registers nothing:
`SEAM-18` requires the executor to be caller-supplied with no default, so there is no executor registry
to register into, and the entry file asserts at `require` that the loaded core satisfies
`REQUIRED_CORE` (`"~> 0.0"`) instead, raising `Dexpace::SeamError` naming both versions on skew.

## Construction: `size:` is required, and the pool never changes size

```ruby
require "dexpace/async/thread"

pool = Pool.build(size: 2, name: "docs")
pool.size          # => 2
pool.queue_limit   # => 16
pool.name          # => "docs"
pool.owned?        # => true
pool.closed?       # => false
Pool::QUEUE_DEPTH_PER_WORKER    # => 8
Pool::DEFAULT_SHUTDOWN_TIMEOUT  # => 30.0
Pool::DEFAULT_NAME              # => "dexpace-async-thread"

Pool.build(size: 0)                  # raises Dexpace::InvalidArgumentError:
                                     #   "size must be a positive Integer, got 0"
Pool.build(size: 2, queue_limit: "8") # raises Dexpace::InvalidArgumentError:
                                     #   "queue_limit must be a positive Integer, got \"8\""
Pool.new(size: 1)                    # raises NoMethodError: private method 'new' called ...
```

`.build` creates exactly `size` threads, each named `"<name> worker N"`, and the pool never grows or
shrinks: a worker cannot die (below), so there is nothing to replace, and a pool whose thread count
changes has a capacity a caller cannot reason about. `size:` has no default for the reason `SEAM-18`
refuses a default executor: the right number is a function of the caller's service and its connection
budget, and a wrong guess is starvation. `queue_limit:` is a depth per worker, derived after `size` is
validated so `Pool.build(size: nil)` names the keyword rather than raising from the default;
`shutdown_timeout:` (a finite, non-negative `Numeric` — a budget is a bound), `name:` (a non-empty `String`), `logger:` (anything
answering `#event`; `Dexpace::Instrumentation::Logger::NULL` by default) and `clock:` (anything answering
`#monotonic`; `Dexpace::Clock::SYSTEM`) validate the same way, each naming its keyword.

## `#post`: the executor duck type, and it never blocks

```ruby
done = Thread::Queue.new
pool.post { done << Thread.current.name }  # => nil
done.pop                                    # => "docs worker 0"
```

`#post` is `Dexpace::Page::_Executor`'s signature exactly — one zero-arity block, `void` — and returns
`nil`: a handle returned through an interface that says the value is not to be used would be a surface
in one `NFR-4` artifact and not the other. It never parks the caller, a pool worker re-posting to its
own pool included: the queue's non-blocking push turns a full queue into a raise rather than a blocked
producer, which is what makes `ASYNC-2`'s "saturated executor" a case this adapter has at all.

```ruby
tiny = Pool.build(size: 1, queue_limit: 1, name: "tiny")
gate = Thread::Queue.new
entered = Thread::Queue.new
tiny.post { entered << :in; gate.pop }  # occupies the one worker
entered.pop
tiny.post { nil }                        # fills the one queue slot
tiny.post { nil }                        # raises Dexpace::Async::Thread::RejectedError:
                                         #   "tiny: queue full (limit 1, 1 workers)"
# rescued into `e`:
e.is_a?(Dexpace::Error)        # => true
e.is_a?(IOError)               # => false
e.respond_to?(:retryable?)     # => false
gate << :go
tiny.close
tiny.post { nil }                        # raises Dexpace::ClosedError: "tiny is closed"
```

Two errors for two conditions, because a caller's two sensible responses differ: a full queue is
backpressure to retry or shed, a closed pool is a lifecycle bug. `RejectedError` is a `StandardError`
under `Dexpace::Error` and not an `IOError` — a rejection is not a transport failure — and it answers
no `#retryable?`, because a pool rejection happens at the bridge, above the pipeline, where no retry
step can see it. Neither the `ThreadError` a full push raises nor the `ClosedQueueError` a closed queue
raises ever escapes `lib/`.

## The bridge: a blocking transport made asynchronous on a worker

```ruby
transport = ->(request, _options, _cancellation) { "#{Thread.current.name} sent #{request.url}" }
async = Dexpace::Transport.async_over(transport, executor: pool)
future = async.call(req("https://example.test/pets"), EMPTY, NONE)
future.class                                          # => Dexpace::Async::Future
future.value(deadline: Dexpace::Clock.deadline_in(5))  # => "docs worker 0 sent https://example.test/pets"

closed = Pool.build(size: 1, name: "shut")
closed.close
failed = Dexpace::Transport.async_over(transport, executor: closed).call(req("https://example.test/"), EMPTY, NONE)
failed.settled?  # => true
failed.value     # raises Dexpace::ClosedError: "shut is closed"
```

`Transport.async_over(transport, executor: pool)` is phase 2's bridge, and the pool is the first
executor it has ever had. `#call` mints a `Completer`, returns the future before anything fallible, and
posts one block; a raise from `#post` itself — a closed pool, a full queue — is routed to the failure
channel, so a caller of an async seam never rescues around `#call` (`ASYNC-2`). The block runs the
send on the worker, re-checks the token on return, and settles the completer; a failure the transport
raised arrives as the identical exception object, because there is no wrapper to unwrap (`ASYNC-13`).
The bridge is `owned: false`: closing it leaves the pool open and usable (`ASYNC-15`, `XCUT-22`).

## Cancellation: nothing is interrupted, and the orphan is closed once

```ruby
source = Dexpace::Cancellation.source
gate, entered, closes = Thread::Queue.new, Thread::Queue.new, Thread::Queue.new
result = Object.new
result.define_singleton_method(:close) { closes << :closed; nil }
slow = ->(_request, _options, _cancellation) { entered << :in; gate.pop; result }

future = Dexpace::Transport.async_over(slow, executor: pool).call(req("https://example.test/slow"), EMPTY, source.token)
entered.pop                       # the worker is inside the send
source.cancel(:changed_my_mind)   # => true
future.settled?                   # => false: nothing interrupted the worker
gate << :go                       # the send returns, after the cancel
future.value(deadline: Dexpace::Clock.deadline_in(5))  # raises Dexpace::CancelledError, reason :changed_my_mind
closes.pop(timeout: 2)            # => :closed -- exactly once
closes.pop(timeout: 0.1)          # => nil
```

This is `ASYNC-7`'s documented outcome for the thread adapter, and the contrast the reactor-backed
adapter draws the other way: an in-flight blocking read runs to completion, the result the caller can
no longer take delivery of is closed exactly once (`ASYNC-5`, whoever loses the produce-versus-cancel
race), and the future settles as cancelled with the caller's reason. A task cancelled while still queued
never reaches the transport at all — the bridge checks the token before it dispatches as well as after —
and a response already delivered is never closed by a later cancel (`ASYNC-20`): the caller owns closing
what they were handed. `Thread#raise` and `Thread#kill` are forbidden throughout the SDK (design §8.3),
so `ASYNC-3`'s interrupt mode is an unsatisfied MUST this gem carries and does not re-open; a transport
blocked in an uninterruptible read occupies its pool slot until the read returns on its own.

## The diagnostic context crosses the hop, and only the caller's

```ruby
Fiber[:"trace.id"] = "abc123"
seen = Thread::Queue.new
pool.post { seen << Dexpace::Instrumentation::Diagnostics.capture }
seen.pop   # => {"trace.id": "abc123"}
Fiber[:"trace.id"] = nil
pool.post { seen << Dexpace::Instrumentation::Diagnostics.capture }
seen.pop   # => {}
```

The context is captured at each `#post`, on the caller's fiber — per submission, never at construction
(`ASYNC-10`) — and installed on the worker for the block's duration through phase 5b's
`Diagnostics.with`, restored in an `ensure` whether the block returned or raised (`ASYNC-9`). Two clears
the design measured to be necessary make that install a *replacement* rather than a merge: a worker
clears the storage it inherited from the fiber that called `Pool.build` once at thread start, and clears
its storage again after every task, so a key the pool's builder held or a key one caller's task wrote
never sits underneath the next caller's snapshot (`P8-20`). An absent context captures as `{}` and
installs as a clear (`ASYNC-11`). The snapshot's values are the caller's own objects, shared and not
copied: keep what you put into `Fiber[]` immutable, or synchronise your own access to it.

## `#delay`: a scheduled delay on one timer thread

```ruby
pool.delay(0).settled?   # => true
pool.delay(0).value      # => true
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
pool.delay(0.05).value(deadline: Dexpace::Clock.deadline_in(5))       # => true
Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0 >= 0.05          # => true
Thread.list.map(&:name).grep(/docs/).sort  # => ["docs timer", "docs worker 0", "docs worker 1"]
pool.delay(-1)           # raises Dexpace::InvalidArgumentError: "duration must not be negative, got -1"
pool.delay(Float::NAN)   # raises Dexpace::InvalidArgumentError: "duration must be finite, got NaN"
pool.delay(Complex(1, 1)) # raises Dexpace::InvalidArgumentError: "duration must be a real number, got (1+1i)"
late = pool.delay(60)
late.cancel(:no_longer_needed)
late.cancelled?          # => true
```

`ASYNC-18`'s four clauses, each with its mechanism: a negative, non-finite (`NaN`, an infinity), non-real (a
`Complex`) or non-`Numeric` duration raises before any thread exists — a `NaN` answers false to both
`negative?` and `zero?`, and one that reached the timer's deadline-ordered list killed its thread and made
every later `#delay` raise a bare `ArgumentError` (`P8-77`); zero settles the future inline and spawns
nothing; a positive delay is one entry on a deadline-ordered list served by one lazily created
`"<name> timer"` thread, parked against the nearest deadline and re-parked after every wake; cancelling
the future removes its entry at once and wakes the timer, so no scheduler thread is held for a delay
nobody wants. The future settles with `true`, as phase 5a's `Dexpace::Async.delay` does, so the two are
interchangeable — and that one is the zero-thread alternative for a caller under a `Fiber.scheduler`; it
is unavailable to a pool worker, whose `Fiber.scheduler` is always `nil`. "Without blocking a thread"
therefore holds for the caller's thread and every worker and not absolutely: one named timer thread per
pool is parked for the interval (`P8-25`). A `#on_settle` on a delay future runs on that timer thread,
not on a worker.

## `#close`: idempotent, bounded, one event

```ruby
logged = Pool.build(size: 2, name: "logged", logger: Dexpace::Instrumentation::Logger.build(sink: sink))
pending = logged.delay(60)
logged.close       # => nil
logged.close       # => nil
pending.settled?   # => true
pending.value      # raises Dexpace::ClosedError: "logged is closed"
sink.events.size   # => 1
sink.events.first.slice("event", "dexpace.executor.worker_count", "dexpace.executor.drained")
# => {"event" => "http.instrumentation.shutdown", "dexpace.executor.worker_count" => 2, "dexpace.executor.drained" => true}

grace = Pool.build(size: 1, name: "grace")
done = Thread::Queue.new
grace.delay(0.01).on_settle { grace.close; done << :closed }   # a close issued ON the timer thread
done.pop(timeout: 5)   # => :closed
grace.closed?          # => true
```

`#close` is `Dexpace::Closeable`'s latch — a boolean flipped under a mutex held across the flip only —
and the winner runs the release in this order: close the submission queue (new posts raise
`Dexpace::ClosedError`; queued work still drains, and a task in flight finishes rather than being
interrupted, `ASYNC-16`), stop the timer and fail every outstanding delay with `Dexpace::ClosedError`,
wait for every worker's exit sentinel and the timer within ONE `shutdown_timeout` budget, then emit
`Events::INSTRUMENTATION_SHUTDOWN` at INFO exactly once inside `Instrumentation.contain` — the lifecycle
event phase 2 postponed until something owned an executor (`SEAM-25`). `#close` returns `nil` for every
closeable in this SDK, so whether the drain completed rides on the event's `dexpace.executor.drained`
field; a spent budget reports `false` and leaves the stuck worker to finish on its own. There is no
`cancellation:` keyword on `#close` (`P8-24`): `Dexpace.close_quietly` calls `#close` with no arguments,
and the bounded budget is what keeps a caller closing inside a cancelled scope from being parked. A
close issued from the pool's own threads completes too (`P8-76`): from a delay's settlement handler, as
above, the timer thread is not joined by itself and exits once the handler returns; from inside a posted
task, the worker running it counts as drained and finishes its task — and whatever the closed queue
still held — after `#close` has returned. Neither waits out the budget or raises.

## Over a real socket

```ruby
require "dexpace/transport/net_http"
require "dexpace/conformance"

server = Dexpace::Conformance::WireServer.start(Dexpace::Conformance::Scripts.fixed("hello from the wire"))
adapter = Dexpace::Transport::NetHTTP.build(timeout: 5)
wire = Dexpace::Transport.async_over(adapter, executor: pool)
response = wire.call(req("http://127.0.0.1:#{server.port}/"), EMPTY, NONE).value(deadline: Dexpace::Clock.deadline_in(10))
response.status.code                   # => 200
response.body_string                   # => "hello from the wire"
server.requests.first.request_line     # => "GET / HTTP/1.1"
response.close
server.close
```

The charter's convergence point 2, and the first place the async path touches a socket: phase 8a's
synchronous adapter on a worker of this pool, its pump-backed response delivered through the pivot,
the options object and the token threaded through unchanged. The composed proof is this gem's
`test/dexpace/async/thread/composed_transport_test.rb`, and nothing under its `lib/` names either sibling.

## As a paginator's executor

```ruby
paginator = Dexpace::Page::AsyncPaginator.build(
  transport: Dexpace::Transport.async_over(fake, executor: pool),  # a transport answering a Future
  template: req("https://example.test/items"), strategy: strategy, executor: pool,
)
items = Thread::Queue.new
paginator.walk(->(item) { items << item }).value(deadline: Dexpace::Clock.deadline_in(5))  # => 2 (pages)
Array.new(3) { items.pop }   # => [1, 2, 3]

pool.close
```

Phase 7c's `executor:` mode posts every dispatch, the first included, through `#post`, so the walk —
consumer included — runs on the pool's workers and the pool is what `Dexpace::Page::_Executor` was
declared for.

## What is deliberately not here

- **No default pool, no `.instance`, no module-level `.post`**: `SEAM-18` forbids a shared global pool
  because blocking work would starve it, and a convenience constructor would be one by another name.
- **No cancellation hook of the pool's own** (`R10`): the pool posts an opaque block and cannot see the
  token; shortening a blocked read by closing the socket under it is the transport's, which is 8a's.
- **No interrupt** (`ASYNC-3`, `ASYNC-4`, `PIPE-33`'s last clause): design §10.5's trade, carried and
  not re-opened; `docs/first-release.md` names the reopening condition.
- **No `cancellation:` on `#close`** (`P8-24`), **no `on_saturation:` policy** and **no growth**: each
  would be an `NFR-4`-locked surface with no requirement behind it.
- **No second future, completer, token or bridge**: every one is phase 2's, and `#delay` returns
  `Dexpace::Async::Future`.
- **No accessor over the threads or the queue**: `#size`, `#queue_limit` and `#name` return the values
  the caller passed, so no constant outside `Dexpace::` appears in any public signature (`NFR-11`).
