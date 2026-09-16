# The recovery layer and the error trail

**As built by phase 4b, in `dexpace-core`, written against source on 2026-09-16.** This page says
what happens to one send between "the request is ready" and "the caller has a response or an
error": a closed two-variant outcome, two folds over frozen step lists, one orchestrator that lets
no throwable past it, and the three error primitives the whole SDK uses from here on — the
suppressed-exception trail, the cycle-safe cause walk and the protocol error. What each is
*required* to do is `docs/product-spec/08-execution-pipelines.md` §8.2; how the design maps it to
Ruby is `docs/sdk-design-ruby/05-pipeline-architecture.md` §5.2; the per-requirement proof is
`docs/work/mvp/phase4/phase4b/2026-09-09-phase4b-recovery-primitives-checklist.md`. Signatures
live in `gems/dexpace-core/sig/dexpace/`, and this page does not restate them. Every example below
was run against the built code on 4.0.6 and 3.2.11 and printed the same on both. The stage
pipeline — the other of §8's two layers, the one that owns ordering and re-drive-with-fork — is
phase 4c's and is deliberately not this layer: spec §8.3 forbids collapsing the two, and nothing
under `Dexpace::Recovery` names a stage or a cursor.

## The outcome: `Dexpace::Outcome`

A send ends in exactly one of two shapes. `Dexpace::Outcome::Success` carries a `Response`;
`Dexpace::Outcome::Failure` carries an `Exception` — any `Exception`, not only a `StandardError`.
Both are frozen `Data` values built through a validating `.build` (their `new` is private), both
include the `Dexpace::Outcome` module so `outcome.is_a?(Dexpace::Outcome)` is the one type test,
and there is no third variant here: phase 7's server-sent-events adapter reuses this type with a
third variant in its own namespace, never by adding one to this one. The derivable surface is
`RECOV-1`'s list and nothing more — the two predicates, the two `-or-nil` readers, and a fold that
invokes exactly one branch at most once.

```ruby
request = Dexpace::Request.builder.tap { |b| b.url = "https://api.example.test/pets" }.build
response = Dexpace::Response.builder.tap do |b|
  b.request = request
  b.protocol = Dexpace::Protocol::HTTP_1_1
  b.status = 200
end.build

success = Dexpace::Outcome::Success.build(response: response)
failure = Dexpace::Outcome::Failure.build(error: IOError.new("connection reset"))

success.success?                                              # => true
success.response_or_nil.equal?(response)                      # => true
failure.error_or_nil.message                                  # => "connection reset"
success.fold(on_success: ->(r) { r.status.code }, on_failure: ->(e) { e.class })  # => 200
failure.fold(on_success: ->(r) { r.status.code }, on_failure: ->(e) { e.class })  # => IOError
Dexpace::Outcome::Failure.build(error: "not an exception")    # raises Dexpace::InvalidArgumentError
```

Both branches of `#fold` are required on both variants, so `on_failure: nil` is refused at the
fold that holds a Success rather than discovered on the first Failure.

## The two chains

**`Dexpace::Recovery::RequestChain`** folds `Request -> Request` steps left to right — step N's
output is step N+1's input, an empty chain returns its request by identity, and a throwing step
aborts the remainder and propagates (`RECOV-3`). It is deliberately not total; the orchestrator is
what converts its throw. **`Dexpace::Recovery::ResponseChain`** holds two lists and folds them in
one fixed order: every *response step* first, on a Success only, each handed the response and its
result rewrapped; then every *recovery step*, on every outcome, always, each handed the outcome
itself (`RECOV-4`–`RECOV-6`). A step is anything answering `#call` with one argument, so a lambda
qualifies. Both chains copy and freeze their lists at construction (`RECOV-14`), so mutating the
array you built them from changes nothing, and neither holds any other state, so one chain is safe
to apply from any number of threads.

```ruby
log = []
chain = Dexpace::Recovery::ResponseChain.build(
  response_steps: [->(resp) { log << :r1; resp }, ->(resp) { log << :r2; resp }],
  recovery_steps: [->(outcome) { log << :c1; outcome }, ->(outcome) { log << :c2; outcome }],
)
chain.apply(success).equal?(success)   # => true   -- a pass-through keeps the outcome's identity
log                                    # => [:r1, :r2, :c1, :c2]

log.clear
chain.apply(failure).equal?(failure)   # => true
log                                    # => [:c1, :c2]   -- no response step ran on a Failure
```

The three shapes matter and are typed in `sig/`: a response step is `Response -> Response` and
therefore cannot return a Failure or swap in a different outcome; only a recovery step, which is
`Outcome -> Outcome`, can. The response chain never raises for any `Outcome` input and any step
behaviour inside `StandardError` (`RECOV-8`): a throwing response step's error becomes a Failure the
recovery steps see (`RECOV-7`), and a throwing recovery step's error becomes a Failure the *next*
recovery step sees, never aborting the remainder.

```ruby
chain = Dexpace::Recovery::ResponseChain.build(
  response_steps: [->(_resp) { raise "response step blew up" }],
  recovery_steps: [
    ->(outcome) { log << outcome.error.message; outcome },
    ->(_outcome) { raise "recovery step blew up too" },
    ->(outcome) { log << outcome.error.message; outcome },
  ],
)
log.clear
result = chain.apply(success)
result.failure?                        # => true
result.error.message                   # => "recovery step blew up too"
log                                    # => ["response step blew up", "recovery step blew up too"]
```

Three things do escape `#apply`, and each is stated rather than excused: a value that is not an
`Outcome` at all is refused with `Dexpace::InvalidArgumentError` before any fold runs; a recovery
step that *returns* something that is not an `Outcome` raises `Dexpace::OutcomeError`, a defect
that is never demoted to a Failure a later step could swallow; and anything outside `StandardError`
— a `LoadError`, a `NotImplementedError`, an `Interrupt` — passes through untouched, with no trail
attached, exactly as a bare `rescue` in your own code would let it.

## Who closes the response

When a step throws while a Success is in hand, the chain closes that response **before** wrapping
the throwable, attaches any close failure to it as suppressed so it never masks the primary, and
releases it exactly once (`RECOV-12`). When a recovery step deliberately *returns* a different
outcome — a substitute Success, or a Failure built from a response it inspected — the chain closes
nothing: the step that dropped the original owns releasing it (`RECOV-13`). Both halves live in one
private helper, `Dexpace::Recovery::Ownership`, which no public code reaches; you observe its
effect and never call it.

```ruby
counting = Class.new do
  include Dexpace::Body
  include Dexpace::Closeable
  attr_reader :releases
  def initialize = (initialize_closeable; @releases = 0)
  private def release = (@releases += 1)
end
body = counting.new
held = Dexpace::Outcome::Success.build(response: response.with(body: body))

Dexpace::Recovery::ResponseChain.build(recovery_steps: [->(_) { raise "boom" }]).apply(held)
body.releases                          # => 1   -- closed by the chain on the throw

body = counting.new
held = Dexpace::Outcome::Success.build(response: response.with(body: body))
substitute = Dexpace::Outcome::Success.build(response: response)
Dexpace::Recovery::ResponseChain.build(recovery_steps: [->(_) { substitute }]).apply(held)
body.releases                          # => 0   -- the step that dropped it owns it
```

"Exactly once" is `Closeable`'s latch, not bookkeeping in the chain: the error-mapping step below
buffers the body — which closes the original — and then raises, so the chain's own close is a
second close of an already-closed body and releases nothing.

## The orchestrator

`Dexpace::Recovery::Orchestrator` is one send: the request chain, then the transport, then the
response chain, with everything before the response chain inside one rescue region, so a throw
from a request step is converted into a Failure and threaded through the recovery steps exactly
as a transport failure is, and the transport is never called after a request step has thrown
(`RECOV-2`). It is itself a transport by phase 2's duck type — `#call(request, options,
cancellation)` — so a recovery-aware stack nests wherever a transport goes. Its dispatch unwraps
the terminal outcome: a Success returns its response, a Failure re-raises its error **unchanged**,
the same object, never wrapped or substituted (`RECOV-10`).

```ruby
transport = ->(req, _options, _cancellation) { response }
orchestrator = Dexpace::Recovery::Orchestrator.build(
  transport: transport,
  request_chain: Dexpace::Recovery::RequestChain.build,
  response_chain: Dexpace::Recovery::ResponseChain.build,
)
orchestrator.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
  .status.code                                                # => 200
Dexpace::Transport.conforms?(orchestrator)                    # => true

failing = Dexpace::Recovery::Orchestrator.build(
  transport: ->(*) { raise IOError, "connection reset" },
  request_chain: Dexpace::Recovery::RequestChain.build,
  response_chain: Dexpace::Recovery::ResponseChain.build(
    recovery_steps: [->(outcome) { log << outcome.error.class; outcome }],
  ),
)
log.clear
begin
  failing.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
rescue IOError => error
  [error.message, log]
end                                                           # => ["connection reset", [IOError]]
```

One spelling in that unwrap is worth knowing about because it protects *your* code: the re-raise
is `raise error, cause: nil`. A bare `raise error` on an error whose `#cause` is `nil` silently
assigns whatever exception is in flight as its cause — and `$!` is non-`nil` inside anything called
from your own `rescue` block, which is ordinary consumer code. So an error a recovery step
constructed and returned in a Failure surfaces with the cause it had, and never with your unrelated
in-flight exception as a parent. The same spelling is used everywhere core re-raises an error it is
carrying rather than one it just rescued.

Cancellation needs nothing special here. A `Dexpace::CancelledError` from the transport is
converted like any other `StandardError`; the token you passed still answers `#cancelled?`
afterwards because phase 2's source is a latch, and no code path clears it (`RECOV-11`).

## The three shipped steps, and the one contract they share

Three steps ship, written once against `Dexpace::Recovery::Transform` — a pure `#apply(value)`
over a request or a response, tagged by `#phase` (`:request` or `:response`), with the module's one
default, `#call(value)`, forwarding to `#apply` so a transform installs into a chain as itself.
Phase 4c's stage pipeline installs the same objects through one generic wrapper that reads
`#phase`; neither layer holds a second implementation.

**`IdempotencyKeyStep`** (`RECOV-32`) stamps a configured header on a request whose method is in
its set — POST, PUT and PATCH by default — through a strategy you supply (`#call(request) ->
String`; core mints no key format for you). In `:respect_existing`, the default, a request already
carrying the header is returned by identity and the strategy is **not** called, so a redirect hop
never burns a fresh key; in `:overwrite` the strategy's value replaces every existing one.

```ruby
minted = []
step = Dexpace::Recovery::IdempotencyKeyStep.build(
  header: "Idempotency-Key",
  strategy: ->(_req) { minted << "k#{minted.size + 1}"; minted.last },
)
post = Dexpace::Request.build(method: Dexpace::Method::POST, url: "https://api.example.test/pets",
                              headers: Dexpace::Headers::EMPTY, body: nil)
stamped = step.apply(post)
stamped.headers["Idempotency-Key"]      # => ["k1"]   -- Headers#[] is the value list
step.apply(stamped).equal?(stamped)     # => true     -- already carried: identity, strategy uncalled
minted                                  # => ["k1"]
step.apply(request).equal?(request)     # => true     -- a GET passes through untouched
```

**`ClientIdentityStep`** (`RECOV-33`) composes its tokens into one space-separated line. In
`:append`, the default, the line goes after the *first* existing value and every other value
survives; when the header is absent the line is its sole value; an empty first value is treated as
absent so no leading space is emitted. In `:replace` every existing value is overwritten. An empty
token list, or one whose tokens are all blank, is a no-op that returns the request by identity.

```ruby
ua = Dexpace::Recovery::ClientIdentityStep.build(header: "User-Agent", tokens: ["dexpace/0.0.0"])
ua.apply(request).headers["User-Agent"]                       # => ["dexpace/0.0.0"]
with_ua = request.with(headers: Dexpace::Headers.builder.add("User-Agent", "acme/2").build)
ua.apply(with_ua).headers["User-Agent"]                       # => ["acme/2 dexpace/0.0.0"]
Dexpace::Recovery::ClientIdentityStep.build(header: "User-Agent", tokens: [" ", ""])
  .apply(request).equal?(request)                             # => true
```

**`ErrorMappingStep`** (`RECOV-15`, `RECOV-16`) is a response step that treats only 400..599 as
errors. A 1xx, 2xx or 3xx comes back by identity with its body not read, consumed or closed — which
is what lets phase 4c put this step in the outermost slot without it draining every 2xx on the way
past. An error status has its body buffered first, into a bounded replayable copy at
`Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES` so the connection is released and the body stays
readable, then mapped through a factory — `Dexpace::ProtocolError.for` unless you pass your own —
and raised; the chain turns the raise into a Failure.

```ruby
error_response = response.with(
  status: 404,
  body: Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes("{\"code\":\"nope\"}")),
)
begin
  Dexpace::Recovery::ErrorMappingStep.build.apply(error_response)
rescue Dexpace::ProtocolError => error
  [error.message, error.status.code, error.response.body_string]
end                         # => ["HTTP 404 Not Found", 404, "{\"code\":\"nope\"}"]
Dexpace::Recovery::ErrorMappingStep.build.apply(response).equal?(response)   # => true
```

`Dexpace::ProtocolError` is one class carrying `#response` and `#status`, and there is no
per-status subclass tree: a caller distinguishes a 404 from a 429 by reading `#status`, and a
generated SDK that wants its own typed errors passes a `factory:` rather than subclassing. Its
message names the status and never the body, because a message is what lands in a log by default.
`ProtocolError.for` refuses a non-error status with an argument error rather than fabricating a
"successful exception"; `.for_or_nil` returns `nil` instead (`XCUT-8`). Its retryability flag is
phase 6a's and is not here yet. `Dexpace::Recovery.buffer_error_body(response)` is the one
buffering function, reading phase 3b's one bound and declaring no second.

## The error trail

Ruby's `#cause` is a single parent set at re-raise; it cannot carry the *secondary* failures an
error accumulated while it was being handled — the close that failed while unwinding, the later
hook that raised, the earlier attempts behind a terminal retry failure. `Dexpace::Suppressible`
carries them. Every SDK error has the trail by inclusion (`Dexpace::Error` includes the module);
any other error gets it on its first attach, because `Dexpace.attach_suppressed(primary,
secondary)` `extend`s a primary that lacks it. That is why the trail is its own module and not
`Dexpace::Error`: `rescue Dexpace::Error` keeps meaning "the SDK raised this", and an extended
third-party `IOError` does not start matching it.

```ruby
primary = IOError.new("write failed")
Dexpace.attach_suppressed(primary, Errno::EPIPE.new("broken pipe on close"))
Dexpace.attach_suppressed(primary, RuntimeError.new("hook raised"))

Dexpace.suppressed(primary).map(&:message)   # => ["Broken pipe - broken pipe on close", "hook raised"]
primary.is_a?(Dexpace::Suppressible)         # => true
primary.is_a?(Dexpace::Error)                # => false
Dexpace.suppressed(primary).frozen?          # => true
puts primary.detailed_message(highlight: false)
# write failed (IOError)
# Suppressed exceptions (2):
#   (1) Errno::EPIPE: Broken pipe - broken pipe on close
#   (2) RuntimeError: hook raised
```

The trail is a frozen array replaced on every attach, so a handle you took earlier is a stable
snapshot. It renders through `#detailed_message`, which is what Ruby's default uncaught-exception
printer and `Exception#full_message` both call, so an uncaught error prints its trail with no
logger involved; a logger that formats an exception itself sees neither, which is what
`Dexpace.suppressed(error)` — `[]` for anything without a trail — is for. Attaching an error to
itself is a no-op, by identity and never by `==`; attaching to a frozen error is a documented no-op
too, because a helper that raised while attaching a *close* error would mask the primary. Two
places in core already write to it: `Dexpace.close_quietly(resource, onto: error)` attaches a
rescued close failure to `error` (the first of the two disposal routes `close_quietly` was
promised; the second, a diagnostic for the no-`onto:` case, is phase 5's), and phase 2's hook
runner surfaces the first handler failure with every later one on its trail instead of dropping
them.

## The cause walk

`Dexpace.each_cause(error)` yields the error itself first, then each `#cause` transitively, and it
is the one walk every classification in the port uses — "is this retryable", "is there a protocol
error under this wrapper". It is cycle-safe by *reference identity* (`XCUT-9`): the visited set is
a `Hash` built with `#compare_by_identity`, never an `Array` and never a `Set`, because
`Exception#==` is structural — two distinct errors of one class with one message and no backtrace
are `==` — and an `Array` would truncate a legitimate chain of two such errors to one, while a
caller's error class overriding `hash`/`eql?` would defeat a `Set`. A `#cause` that raises, or that
returns something that is not an exception, ends the chain rather than failing the classification.

```ruby
chained = begin
  begin
    raise IOError, "socket closed"
  rescue IOError
    raise Dexpace::StreamError, "read failed"
  end
rescue Dexpace::StreamError => error
  error
end
Dexpace.each_cause(chained).map(&:class)                    # => [Dexpace::StreamError, IOError]
Dexpace.each_cause(chained).any? { |e| e.is_a?(IOError) }   # => true

loopy = Class.new(StandardError) { def cause = self }.new("me again")
Dexpace.each_cause(loopy).count                             # => 1
```

## Errors, and what is deliberately not one

`Dexpace::ProtocolError` is `XCUT-4`'s branch (a), a `StandardError` carrying a fully received
response; branch (b), `Dexpace::TransportError < ::IOError` carrying no response, lands with the
first transport in phase 8. `Dexpace::OutcomeError` is the one defect this layer names — a value
that is not an `Outcome` reaching a fold — and it is a `StandardError` that the orchestrator and
the chains re-raise by name instead of converting, because `NoMatchingPatternError` is inside
`StandardError` and the conforming-looking route would turn a core bug into a 200 a recovery step
could not tell from a real one. Every other `StandardError` a step or a transport raises is an
outcome, and the fatal family is nobody's outcome.

## Threads, fibers and clocks

Nothing here holds a mutex, because nothing here has mutable shared state: a built chain is frozen
lists, an orchestrator is three frozen references, a transform is frozen configuration, and every
per-send value travels in the request, the response or the outcome. The one exception a reader
might expect — the suppressed trail — is covered by a single-writer discipline at every core call
site rather than a lock: core makes no thread-safety claim for concurrent `attach_suppressed`
calls on one error object, and a lock on a caller's exception is not available in any case. No
wait, no timer and no `Timeout.timeout` exist in this layer; `RECOV-27`'s cancellable
inter-attempt wait, and the whole recovery-stack retry engine (`RECOV-17`–`RECOV-30`), are phase
6a's, behind the time seam phase 5 defines.
