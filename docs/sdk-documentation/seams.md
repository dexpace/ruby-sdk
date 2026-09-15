# The seam layer

**As built by phase 2, in `dexpace-core`, written against source on 2026-09-15.** This page says
what plugs into what: what a transport, an async transport and a codec *are*, how one is found,
what a future and a cancellation token do, what closing means, and how an operation description
becomes a `Dexpace::Request`. What each piece is *required* to do is
`docs/product-spec/03-pluggable-seams-and-extension-model.md`; how the design maps it to Ruby is
`docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md`; the per-requirement proof is
`docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations-checklist.md`. Signatures live in
`gems/dexpace-core/sig/`, and this page does not restate them. Nothing here talks to a socket:
phase 2 ships the contracts and no adapter, so every example below stands a lambda in for the
transport phase 8 ships.

## A seam is three things

Every seam is a **duck type** — a documented set of methods, nothing to include and nothing to
inherit — a **`.conforms?` predicate** on the seam's own module, and an **RBS interface** in that
seam's `sig/` file (`_Transport`, `_AsyncTransport`, `_Codec`) that a consumer's own `steep check`
sees at a parameter. An object that already has the shape conforms without an adapter: a bare
lambda is a valid transport.

| Seam | Module | Duck type | Returns |
|---|---|---|---|
| synchronous transport | `Dexpace::Transport` | `#call(request, options, cancellation)` | a `Dexpace::Response` |
| asynchronous transport | `Dexpace::AsyncTransport` | `#call(request, options, cancellation)` | a `Dexpace::Async::Future` |
| wire codec | `Dexpace::Serde` | `#media_type`, `#dump_string`, `#dump_bytes`, `#dump_to(value, sink)`, `#dump_into(value, buffer, offset:)`, `#load(source, witness)` | — |

The two transport seams have the *same* call shape and differ only in return type, which no
runtime predicate can see before the first call; so they are two registries, an adapter names which
it registers into, and the bridges below check the returned value at the first send. There is no
executor seam and no auto-activation hook: an executor is caller-supplied by requirement
(`SEAM-18`), and "whatever happens to be installed silently wins" is the failure the loud
resolution branches below exist to prevent.

## Finding a provider

Ruby has no classpath to scan, so an adapter **registers itself as a side effect of being
required**: `Dexpace::Transport.register(:net_http, Dexpace::Transport::NetHTTP, core: "~> 0.1")`
from the adapter's own entry file, where `core:` is the same `~> MAJOR.MINOR` its gemspec declares
on `dexpace-core`. The registration is refused at once if the running `Dexpace::VERSION` does not
satisfy it — a mismatched core/adapter pair fails at `require` time, not at the first send — and
only that two-segment pessimistic form is accepted; `>= 0.1` is a caller mistake, not a looser
rule. Core ships every registry empty and never requires an optional gem.

Resolution is `Dexpace::Transport.resolve` (the same five entry points exist on all three seams:
`register`, `install`, `resolve`, `registered_keys`, `swap`), and it follows one precedence:

1. An explicitly installed provider — `Dexpace::Transport.install(transport)` — always wins.
2. Otherwise, exactly one registered factory is built once, memoised process-wide, and returned.
3. Zero registered factories raise `Dexpace::SeamError` naming the seam and the install entry
   point — and **no gem**, so core never names a concrete implementation, not even in an error.
4. Two or more raise `Dexpace::SeamError` listing every registered key.

A failed resolution memoises nothing, so a later `require` or `install` takes effect on the next
call. Installing the identical instance twice is a no-op; installing a different instance over an
explicit one raises `Dexpace::InvalidArgumentError` naming both; replacing an auto-resolved
provider that had already been handed out replaces it and emits one `Kernel#warn` (silent under
`-W0`, as an advisory should be). Registering a second factory under an occupied key raises
naming both, so two gems claiming one key are loud and a double `require` is quiet.

Under contention the registry is safe by shape rather than by discipline: its state is one frozen
snapshot swapped under a mutex held across the swap and nothing else, so reads never block; a
concurrent first access runs the factory exactly once, later arrivals park on the winner's gate
(a `Thread::Queue`, so a fiber scheduler sees the wait); and no factory or `.conforms?` call ever
runs under the lock — a factory may install, swap or resolve *another* registry freely, and one
that resolves *its own* registry gets a `Dexpace::SeamError` at that call rather than a hang.

For a test, `Dexpace::Transport.swap(fake) { … }` overrides the resolved provider for the block
and restores the prior state afterwards, with no conflict check. Two things survive the block on
purpose: a registration made inside it (a `require` cannot be re-run) and a resolution that
completed inside it.

## The future and the completer

`Dexpace::Async::Future` is the core-owned, dependency-free pivot every async adapter settles
through; adapters bridge to it and never replace it, which is what keeps third-party async types
out of every public signature. It is a facade over a `Dexpace::Async::Completer`, the write side,
which is handed only to the producer:

```ruby
completer = Dexpace::Async::Completer.new
future = completer.future

Thread.new { completer.fulfil(response) }       # or completer.fail(error)

future.value                                    # blocks on a queue, never spins; raises the failure
future.wait                                     # settles-or-returns, never raises
future.on_settle { |settlement| … }             # exactly once; at once if already settled
future.then { |value| value.status }            # a derived future; failure and cancellation forward
future.cancel(:caller_gave_up)                  # cooperative, see below
```

Three rules do most of the work. **Settling means writing exactly one of a response or an error**
(`Dexpace::Async::Settlement`), so a future can never succeed with nothing. **A fulfil that loses
the race closes what it was handed** — `completer.fulfil(response)` returns `false` and
`Dexpace.close_quietly(response)` has run — so an orphaned response is released whether or not
the adapter remembered (`SEAM-30`). **Failures are delivered as the identical object**: there is
no wrapper, and `future.value` re-raises what `completer.fail` was given.

The blocking wait is scheduler-transparent: `#value` pops a `Thread::Queue`, which a registered
`Fiber.scheduler` routes through its `block`/`unblock` hooks instead of parking the OS thread — a
caller inside a reactor awaits without blocking it, and a caller with no scheduler blocks one
thread, as asked. `#value(cancellation: token)` waits under a token; there is no `deadline:` yet
(phase 5 adds it, widening the signature).

## Cancellation

`Dexpace::Cancellation` is the third argument of both transport seams and the state a blocking
transport honours. It is cooperative: Ruby's pre-emption primitives are forbidden repository-wide,
so nothing is ever interrupted, and the producer's obligation is **check-after-resume** — after any
operation that may have suspended, and before acting on its result, re-check the token; if
cancelled, close what you hold and settle through the failure channel.

```ruby
source = Dexpace::Cancellation.source           # the write side, kept by whoever may cancel
token = source.token                            # the read side, handed to a transport

token.cancelled?                                # => false
token.check!                                    # raises Dexpace::CancelledError once cancelled
handle = token.on_cancel { |reason| … }         # exactly once; at once if already cancelled
handle.detach                                   # withdraws that registration; idempotent
source.cancel(:deadline)                        # => true the first time, false afterwards

both = Dexpace::Cancellation.any(client_token, per_call_token)
Dexpace::Cancellation.none                      # the shared token that can never be cancelled
```

The reason is a typed object, never a message: a timeout and a cancellation are told apart by
`reason.class`, out of band. A composed token subscribes to nothing at construction — `#cancelled?`
and `#reason` are computed from the sources, and the winner is the source that cancelled first in
time — so composing a client-lifetime token with a per-call token on every request leaks nothing;
a registration made for a bounded wait (`future.value(cancellation:)` arms one) is detached when
the wait ends. `Completer#on_cancel { |reason| … }` is the producer's hook to abort promptly rather
than only at its next resume point; the future is settled as cancelled *before* the hook runs, so
a raising hook can never leave a waiter blocked.

## Closing

Anything the SDK can release responds to `#close`. `Dexpace::Closeable` supplies the whole contract
to a class that includes it, calls `initialize_closeable(owned:)` from its constructor and defines
a private `#release`: `#close` is idempotent (a latch, flipped under a mutex held across the flip
only), `#release` runs exactly once and only when `owned?`, and a `#release` that raises still
leaves the latch flipped and propagates once. **Ownership is a construction-time fact**: a
component that *built* a resource releases it; one that *borrowed* it latches and releases
nothing, so the caller may keep using what it supplied. `Dexpace.close_quietly(resource)` is the
one exit for a close on a cleanup path — null-safe, tolerant of an object with no `#close`, and
never raising over a primary failure (the rescued error is dropped until phase 4 supplies the
suppressed trail). `Dexpace::ClosedError` is the documented post-close failure: a transport that
*owns* the resource it closed raises it from a later send; phase 2 ships the class and the rule,
phase 8's adapters the first raise site.

## Bridging sync and async

```ruby
async = Dexpace::Transport.async_over(blocking_transport, executor: pool)   # executor required
sync = Dexpace::AsyncTransport.sync_over(async_transport)
```

Both live in `Dexpace::Bridge` and both are `Closeable` with `owned: false`: they hold what the
caller supplied and create nothing, so their close releases nothing. `async_over` posts the
blocking send to the caller's executor (a duck type: `#post { … }`; there is intentionally no
default, because a shared global pool would be starved by blocking work), returns the future before
anything fallible runs, routes a raise from the transport *or from `#post` itself* to the failure
channel, checks the token before the send and again after it — closing a response no caller will
receive — and refuses, at the first send, an async transport handed to it by mistake. `sync_over`
calls the async transport, checks that a `Dexpace::Async::Future` came back, and waits on it under
the caller's token; per-call options pass through both bridges as the exact object.

## From an operation to a request

`Dexpace::Operation` is a frozen descriptor — an HTTP method, a path template with `{name}`
placeholders, and a projection table mapping each input key to
`[:path | :query | :header | :body, wire_name]` — plus one builder method:

```ruby
pets = Dexpace::Operation.build(
  method: "GET",
  template: "/owners/{owner}/pets",
  projections: { owner: [:path, "owner"], limit: [:query, "limit"], trace: [:header, "X-Trace"] },
)
request = pets.build_request(
  base_url: "https://host/c?sig=abc",
  inputs: { owner: "a/b", limit: 1, trace: "t-1" },
)
request.url.to_s   # => "https://host/c/owners/a%2Fb/pets?sig=abc&limit=1"
```

Two checks at two times make "every placeholder has a value" structural: at construction, the set
of `:path` wire names must equal the set of template placeholders (a placeholder with no projection
can never be filled; a `:path` projection naming no placeholder can never be used); at
`#build_request`, every projected path input must have a non-`nil` value, and the error names the
input key and the placeholder. A path value is percent-encoded as a single segment — `"a/b"` is
`a%2Fb` and never two segments — the query is the wire model's own RFC 3986 rendering with one
parameter per value of a repeated projection, headers go through the outbound builder so a CRLF is
refused at assembly, and the body is carried untouched for a codec to encode later.

The base-URL composition is a concatenation, **not** RFC 3986 reference resolution: a trailing
slash normalises to one separator, an empty operation path leaves the base untouched, an existing
base query is kept with the operation's appended (a dangling `&` dropped), already-encoded octets
survive verbatim, and a base carrying a fragment is refused naming it. `URI#merge` would have
dropped both the `/c` and the `sig=abc` that a signed base URL needs to keep.

## What is deliberately absent

No transport, codec, executor or pipeline ships here; the in-memory fakes the suites use live in
`gems/dexpace-core/test/support/` and are not public API. No deadline on the future's wait, no
error-disposal route inside `close_quietly`, no lifecycle event from `#close`, no operation
identifier on `Operation`, and no presence-gated activation of any kind — each is owned by a later
phase or by `docs/first-release.md`, and the phase-2 design's "Work Phase 2 Postponed" section says
which. The byte-stream provider seam is retired outright: `IO`, `StringIO` and BINARY `String`s are
the platform, not a dependency.
