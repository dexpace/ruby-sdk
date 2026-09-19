# The stage pipeline

**As built by phase 4c, in `dexpace-core`, written against source on 2026-09-16.** This page says
how one send is composed and driven: sixteen totally ordered stages, steps installed into them by a
builder with pillar rules and surgical edits, a forward-only per-call cursor with a pillar-only
fork and stage-scoped state, a sync runtime and an async mirror that are both transports, and the
one adapter that installs a recovery-layer transform. What each is *required* to do is
`docs/product-spec/08-execution-pipelines.md` §8.1; how the design maps it to Ruby is
`docs/sdk-design-ruby/05-pipeline-architecture.md` §5.1 and §5.3; the per-requirement proof is
`docs/work/mvp/phase4/phase4c/2026-09-09-phase4c-stage-pipeline-checklist.md`. Signatures live in
`gems/dexpace-core/sig/dexpace/`, and this page does not restate them. Every example below was run
against the built code on 4.0.6 and 3.2.11 and printed the same on both (a `Hash#inspect` on the
floor spells `{:hop=>1}` where 4.0.6 spells `{hop: 1}`; nothing else differs). The recovery layer —
the other of §8's two layers, the one that owns the sum-type fold and the uniform-failure
guarantee — is phase 4b's and is deliberately not this layer: spec §8.3 forbids collapsing the two,
and the only object here that names a `Dexpace::Recovery` constant is the adapter at the end.

## The stages: `Dexpace::Pipeline::Stages`

Sixteen frozen `Dexpace::Pipeline::Stage` values in one total order — the five pillars of the
precedence chain (`REDIRECT`, `RETRY`, `AUTH`, `LOGGING`, `SERDE`), a `PRE_` slot before and a
`POST_` slot after each, and the terminal `SEND` hop — with order keys sparse by 100 so a later
revision can insert one without renumbering. `PRE_REDIRECT` is both REDIRECT's pre-slot and the
outermost slot of the whole pipeline: a step there runs outside every fork and observes only the
single terminal response, which is where a status-to-error mapping belongs. A pillar admits at most
one step; a slot holds an ordered list. `SEND` holds no user step at all.

The set is closed. `Stage` has no public constructor — both generated ones are private, there is no
`.build`, and `#with` refuses — so `Stages.of(name)` and the sixteen constants are the whole
population, and a caller cannot add a pillar or reorder the chain. Nothing sorts a `Stage`: a
`Data` answers `<=>` through `Kernel#<=>`, which is `nil` for two distinct stages, so ordering is
always `Stages::ALL`'s position and `#order` exists for a caller to read, never for the runtime.

```ruby
stages = Dexpace::Pipeline::Stages
stages::ALL.size                                    # => 16
stages::ALL.map(&:name).first(4)                    # => [:pre_redirect, :redirect, :post_redirect, :pre_retry]
stages::PILLARS.map(&:name)                         # => [:redirect, :retry, :auth, :logging, :serde]
stages::REDIRECT.pillar?                            # => true
stages::PRE_AUTH.pillar?                            # => false
stages::SEND.installable?                           # => false
stages.of(:retry).equal?(stages::RETRY)             # => true
stages::REDIRECT.with(name: :fake, order: 250)      # raises Dexpace::InvalidArgumentError
[stages::RETRY, stages::REDIRECT].sort              # raises ArgumentError
```

## Steps, and where a step's stage lives

A step is any object answering `#call(request, cursor)` — a lambda qualifies, and so does a class
with a two-argument `#call`; `Dexpace::Pipeline::Step.conforms?` is the predicate and there is no
module to include. A step receives the request, may call `cursor.call` to drive the rest of the
chain (with a substituted request, which then sticks for every downstream step and the transport),
may inspect or replace the response on the way back, or may return a synthetic response without
driving at all. A single step is shared across every call, so it holds no per-call state: whatever
a send needs to remember travels on the cursor.

The builder records each step's stage at install time and that record is the authority. A step may
declare `#stage` (a `Stage` or its name); when it does, an omitted `stage:` takes the declaration, an
agreeing one is accepted, and a disagreeing one is rejected. A step that declares nothing — every
lambda — must be given `stage:`. `#stage` is read once, at install, and never again: the runtime
consults its own frozen table, so a step that answers `Stages::REDIRECT` while sitting in a slot
gets nothing a slot step does not.

```ruby
request = Dexpace::Request.builder.tap { |b| b.url = "https://api.example.test/pets" }.build
transport = lambda do |req, _options, _cancellation|
  Dexpace::Response.builder.tap do |b|
    b.request = req
    b.protocol = Dexpace::Protocol::HTTP_1_1
    b.status = 200
  end.build
end

log = []
tag = ->(name) { ->(req, cursor) { log << name; cursor.call(req) } }
pipeline = Dexpace::Pipeline.builder(transport: transport)
  .append(tag.call(:post_auth), stage: :post_auth)
  .append(tag.call(:pre_redirect), stage: Dexpace::Pipeline::Stages::PRE_REDIRECT)
  .append(tag.call(:auth), stage: :auth)
  .build

pipeline.call(request).status.code                  # => 200
log                                                 # => [:pre_redirect, :auth, :post_auth]
pipeline.entries.map { |e| e.stage.name }           # => [:pre_redirect, :auth, :post_auth]
pipeline.steps.frozen?                              # => true
pipeline.steps.equal?(pipeline.steps)               # => true
Dexpace::Transport.conforms?(pipeline)              # => true
Dexpace::Pipeline.direct(transport).steps           # => []
```

The order the steps ran in is the stage order, not the order they were appended in, and it is the
same order however they were added: flattening walks `Stages::ALL`, skipping `SEND`, and there is
no accumulated order to consult. `#steps` and `#entries` are frozen arrays built once and handed
back by the same reference every call. `Pipeline.direct(transport)` is the step-less pipeline —
useful because a pipeline is a transport, so anything that takes a transport takes one.

## The builder: `Dexpace::Pipeline::Builder`

One mutable builder serves both runtimes; `#build` produces a `Dexpace::Pipeline` and `#build_async`
a `Dexpace::AsyncPipeline` from the same bucket table, which is how the two runtimes cannot drift on
ordering. Every install returns the builder, so calls chain. The pillar rules are exact: a pillar
admits one step, re-installing the **same object** is a no-op on every install path (the surgical
inserts included), and a **distinct** second step — even one that is `==` to the occupant — fails
fast naming both types and pointing at `#replace`. Sameness is reference identity, never value
equality. A stage may be given as a `Stages` constant or its name; either way the builder holds
the constant itself, so a `dup`ed or `Marshal`ed `Stage` is the same stage to it.

```ruby
builder = Dexpace::Pipeline.builder(transport: transport)
retry_step = ->(req, cursor) { cursor.call(req) }
builder.append(retry_step, stage: :retry)
builder.append(retry_step, stage: :retry)
builder.entries.size                                # => 1
builder.append(->(req, cursor) { cursor.call(req) }, stage: :retry)
# raises Dexpace::PipelineError: pillar retry is already occupied by Proc; cannot install Proc
#   (use #replace to substitute) (PIPE-5)
builder.append(->(req, cursor) { cursor.call(req) }, stage: :send)
# raises Dexpace::PipelineError: cannot install step at terminal stage SEND (PIPE-8)
builder.append(->(req, cursor) { cursor.call(req) })
# raises Dexpace::PipelineError: step does not declare #stage and no stage: keyword was given;
#   a step with no stage cannot be installed (R10)

declaring = Class.new do
  def stage = :auth
  def call(req, cursor) = cursor.call(req)
end
builder.append(declaring.new).entries.last.stage.name   # => :auth
builder.append(declaring.new, stage: :retry)
# raises Dexpace::PipelineError: step declares stage auth but was installed with stage retry (R10)
```

**Surgical edits.** `#insert_after(anchor, step, stage:)` and `#insert_before` place the step next
to the **first** existing step that is an instance of the anchor type, in flattened order; the step
must land in the anchor's stage, and a cross-stage insert is rejected rather than relocated.
`#replace` swaps the first instance 1:1 in its own stage. `#remove(type)` deletes **every** instance
of the type and is a silent no-op when there is none. An insert or replace whose anchor is absent
fails naming what it looked for. Because every lambda's class is `Proc`, a type anchor cannot tell
two lambdas apart — `remove(Proc)` deletes both — so an install may carry `name:`, and the four
edits accept a `Symbol` or `String` in the anchor position to address exactly that one entry. An
anchor that is none of those is refused with `Dexpace::InvalidArgumentError` before anything is
compared, on an empty builder too.

```ruby
class LoggingHook
  def call(request, cursor) = cursor.call(request)
end

builder = Dexpace::Pipeline.builder(transport: transport)
builder.append(LoggingHook.new, stage: :pre_auth)
builder.insert_after(LoggingHook, ->(r, c) { c.call(r) }, stage: :pre_auth, name: :after_hook)
builder.insert_before(:after_hook, ->(r, c) { c.call(r) }, stage: :pre_auth, name: :before_after)
builder.entries.map(&:name)                         # => [nil, :before_after, :after_hook]
builder.insert_after(LoggingHook, ->(r, c) { c.call(r) }, stage: :post_auth)
# raises Dexpace::PipelineError: cannot insert Proc declaring stage post_auth relative to anchor
#   at stage pre_auth (PIPE-18)
builder.replace(:missing, ->(r, c) { c.call(r) }, stage: :pre_auth)
# raises Dexpace::PipelineError: anchor step named :missing was not found in pipeline (PIPE-21)
builder.remove(Proc)
builder.entries.map { |e| e.step.class }            # => [LoggingHook]
builder.remove(String).entries.size                 # => 1
```

**Batches** keep one asymmetry that is documented because it is easy to get backwards: `#append_all`
preserves the batch's order within the stage, while `#prepend_all` prepends each element
individually, so `[a, b]` ends up `b, a`. **Bulk paths** are all-or-nothing: `#reload(entries)`
replaces the whole collection and `#install_preset(entries)` fills empty pillars, and both validate
the whole set — every element a `Dexpace::Pipeline::Entry`, and no two distinct steps on one pillar
within the set — before touching a bucket, so a rejected call leaves the collection exactly as it
was. `#install_preset` additionally refuses if any target pillar is already occupied, naming every
occupant. It is the mechanism the two standard-resilience presets are written over, and nothing
else is: since phase 6b's Task 13a, `Pipeline.standard(over, ...)` installs the redirect, retry and
instrumentation steps into a transport or a builder handed in — a builder whose target pillar is
already occupied rejects the whole call, which is what makes `PIPE-24` reachable through the
constructor — and `AsyncPipeline.standard(over, redirect: :unsupported, ...)` the async retry and
instrumentation steps; both are described, with the keywords they thread through, in
[`redirect.md`](./redirect.md).

```ruby
builder = Dexpace::Pipeline.builder(transport: transport)
builder.append(->(r, c) { c.call(r) }, stage: :retry)
entry = ->(stage, step) { Dexpace::Pipeline::Entry.build(stage: Dexpace::Pipeline::Stages.of(stage), step: step) }
builder.install_preset([entry.call(:redirect, ->(r, c) { c.call(r) }), entry.call(:retry, ->(r, c) { c.call(r) })])
# raises Dexpace::PipelineError: cannot install preset: pillar retry is already occupied by Proc (PIPE-24)
builder.entries.map { |e| e.stage.name }            # => [:retry]
builder.reload([entry.call(:post_auth, ->(r, c) { c.call(r) })])
builder.entries.map { |e| e.stage.name }            # => [:post_auth]
```

**Seeding from an existing pipeline** is two explicit constructors, never an accident.
`Builder.flattening(pipeline)` copies the pipeline's entries (names included) and its transport,
so the seeded steps run inside the new builder's loops; `Builder.nesting(pipeline)` makes the
pipeline the new builder's transport, so the new steps run once, outside the nested pipeline's
loops. With a twice-forking `REDIRECT` inside, a new `PRE_RETRY` step runs twice under FLATTEN and
once under NEST — the only observable difference, and the whole point.

## The cursor: `Dexpace::Pipeline::Cursor`

Each send allocates its own cursor and hands each step a cursor bound to that step's entry; an
empty pipeline allocates none and dispatches straight to the transport. `cursor.call(request)`
advances to the next step, or past the last one dispatches to the transport with the caller's
options and cancellation token; it is **single-use**, and a second sequential call raises. The
caller's `RequestOptions` are the same frozen object at every step and across every fork, readable
as `cursor.options`.

A step that drives the chain more than once — a redirect following a hop, a retry re-attempting —
does not call `cursor.call` at all: it calls `cursor.fork` once **per drive**, the first included,
and drives each fork. A fork resumes from the same position with the same request, options and
token, and advances independently; only a step occupying one of the five configurable pillars may
fork, decided from the runtime's own entry table and never from anything the step says, and a fork
taken after the cursor's own `#call` is refused because `#call` and `#fork` are disjoint on one
cursor. `cursor.may_fork?` answers the question without rescuing. The re-driving step also owns the
response lifecycle across its drives: it closes each superseded intermediate response before the
next drive and hands the last one back unclosed.

State a pillar step wants downstream steps to see is written **only** as `cursor.fork(state: {...})`
and lands only in the forking stage's own slot, read as `cursor.state(stage)` — a frozen hash, one
shared empty hash for a slot nothing wrote. There is no state-setting method on the cursor. That
keying by `(stage, key)` is what phase 6's cross-origin marker rests on: the redirect step writes
under `Stages::REDIRECT`, the auth step downstream reads that slot, and nothing between them — a
retry step included, which forks under its own slot — can write the value AUTH reads. Each hop is a
fresh fork of the redirect step's own cursor, so hop 2 never inherits hop 1's write.

```ruby
drives = []
redirect = lambda do |req, cursor|
  first = cursor.fork(state: { hop: 1 }).call(req)
  drives << first.status.code
  first.close                                        # the superseded hop, released before the next
  cursor.fork(state: { hop: 2, cross_origin: true }).call(req)
end
seen = []
auth = lambda do |req, cursor|
  seen << cursor.state(Dexpace::Pipeline::Stages::REDIRECT)
  cursor.call(req)
end
pipeline = Dexpace::Pipeline.builder(transport: transport)
  .append(redirect, stage: :redirect)
  .append(auth, stage: :auth)
  .build

pipeline.call(request).status.code                  # => 200
seen                                                # => [{hop: 1}, {hop: 2, cross_origin: true}]
seen[0].frozen?                                     # => true
drives                                              # => [200]

Dexpace::Pipeline.builder(transport: transport).append(->(_r, c) { c.fork }, stage: :pre_auth).build.call(request)
# raises Dexpace::PipelineError: stage pre_auth is not a configurable pillar and cannot fork (PIPE-15)
Dexpace::Pipeline.builder(transport: transport).append(->(r, c) { c.call(r); c.call(r) }, stage: :pre_auth).build.call(request)
# raises Dexpace::PipelineError: cursor has already been invoked and cannot be reused (PIPE-15)
Dexpace::Pipeline.builder(transport: transport).append(->(r, c) { c.call(r); c.fork }, stage: :retry).build.call(request)
# raises Dexpace::PipelineError: cursor is spent and cannot be forked; #call and #fork are disjoint (PIPE-15)
```

One limit is stated because it is invisible otherwise: the reuse guard is an unsynchronised flag,
so a second **sequential** call always raises and a second **concurrent** call on one cursor
sometimes does not. Handing one cursor to two threads is already the defect the guard names; do not
read the raise as a concurrency guard.

## The adapter: `Dexpace::Pipeline::TransformStep`

The recovery layer's `Dexpace::Recovery::Transform` — a pure `#apply(value)` tagged `:request` or
`:response` — installs into a non-pillar stage through this one wrapper. It reads `#phase` once, at
build, refuses anything but the two values, and calls `#apply` and never `#call`. It declares no
stage of its own, because the three shipped transforms belong in different places: the
error-mapping transform goes at `PRE_REDIRECT`, outside every fork, so it sees only the terminal
response and hands a 2xx back untouched; an idempotency-key transform belongs at or before
`PRE_RETRY` so a re-attempt reuses the key.

```ruby
mapping = Dexpace::Pipeline::TransformStep.build(Dexpace::Recovery::ErrorMappingStep.build)
mapping.transform.class                             # => Dexpace::Recovery::ErrorMappingStep
mapping.respond_to?(:stage)                         # => false
Dexpace::Pipeline.builder(transport: transport).append(mapping, stage: :pre_redirect).build.call(request).status.code   # => 200

failing = ->(req, _o, _c) { Dexpace::Response.builder.tap { |b| b.request = req; b.protocol = Dexpace::Protocol::HTTP_1_1; b.status = 503 }.build }
Dexpace::Pipeline.builder(transport: failing).append(mapping, stage: :pre_redirect).build.call(request)
# raises Dexpace::ProtocolError (503)
```

## The async mirror: `Dexpace::AsyncPipeline`

`#build_async` produces an `AsyncPipeline` over an async transport — one whose `#call` returns a
`Dexpace::Async::Future`. It has no stages, builder or cursor of its own: the same builder builds it
and the same cursor drives it, so a concern occupies the same slot in both runtimes. Its `#call`
returns the step's or the transport's own future, never re-wrapped; a step's synchronous
`StandardError` becomes a failed future carrying that identical error, so one step's mistake cannot
break the async contract, while the fatal family (`NoMemoryError`, and `ScriptError`s such as a
`LoadError` from a step that lazily requires something absent) propagates synchronously out of
`#call`. A step or transport that returns something other than a future fails the drive with
`Dexpace::SeamError`, because nothing at build time can see a return type.

`AsyncPipeline.map_response(future) { |response| ... }` is the terminal response-mapping operator:
the handler sees the response open, the response is closed once the handler returns or raises, a
raising handler fails the mapped future with the identical error, and cancelling the mapped future
cancels the send with the same reason. It is a class method over any future, so it composes with a
pipeline's send and is testable without one.

```ruby
async_transport = lambda do |req, _o, _c|
  completer = Dexpace::Async::Completer.new
  completer.fulfil(transport.call(req, nil, nil))
  completer.future
end
ap = Dexpace::Pipeline.builder(transport: async_transport).append(->(r, c) { c.call(r) }, stage: :pre_auth).build_async
Dexpace::AsyncTransport.conforms?(ap)               # => true
ap.call(request).class                              # => Dexpace::Async::Future
ap.call(request).value.status.code                  # => 200

failed = Dexpace::Pipeline.builder(transport: async_transport).append(->(_r, _c) { raise "step bug" }, stage: :pre_auth).build_async.call(request)
failed.settled?                                     # => true
failed.value                                        # raises RuntimeError: step bug

Dexpace::AsyncPipeline.map_response(ap.call(request)) { |response| response.status.code }.value   # => 200
```

The asymmetry the specification asks a port to document: the sync standard pipeline,
`Pipeline.standard`, installs the redirect step, and the async standard pipeline,
`AsyncPipeline.standard`, does not follow redirects at the pipeline layer and takes an explicit
`redirect: :unsupported` — a required keyword, refusing every other value — so the absence is
visible at the call site. Both constructors exist since phase 6b's Task 13a (`PIPE-39`; the worked
examples are in [`redirect.md`](./redirect.md)). What is deliberate on the runtime's side:
`REDIRECT` is installable on the async path by hand, because the two runtimes share one staging
policy and that constraint is the preset's, not the runtime's.

```ruby
Dexpace::AsyncPipeline.standard(async_transport, redirect: :unsupported).entries.map { |e| e.stage.name }
# => [:retry, :logging]
Dexpace::Pipeline.standard(transport).entries.map { |e| e.stage.name }
# => [:redirect, :retry, :logging]
```

## The bridges, which this layer does not ship

A pipeline is a transport, so phase 2's two bridges are the sync-to-async and async-to-sync
bridges: `Dexpace::Transport.async_over(pipeline, executor:)` posts the **whole** sync pipeline as
one unit on a caller-supplied executor — the steps never see it, and there is no default — and
`Dexpace::AsyncTransport.sync_over(async_pipeline)` blocks on the future under the caller's
cancellation token and raises `Dexpace::CancelledError` when the token is cancelled. This layer
adds no wait, no executor and no second normalisation. The one clause it cannot meet, interrupting a
worker mid-send, is `docs/first-release.md`'s unsatisfied MUST for the same reason nothing in this
port interrupts a thread.

```ruby
executor = Class.new { def post = yield }.new
Dexpace::Transport.async_over(pipeline, executor: executor)
  .call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none).value.status.code   # => 200
Dexpace::AsyncTransport.sync_over(ap)
  .call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none).status.code         # => 200
```

## Closing, threads and locks

A pipeline never owns its transport: `#close` latches (`closed?` is true, `owned?` is false) and
releases nothing, the transport's own `closed?` is untouched, and a closed pipeline still sends,
because wrapping a pipeline in a resource-management scope must not suggest transport resources
were released. Nothing in this layer holds a mutex. A built runtime is a frozen entry table, a
frozen step view and a write-once transport reference, so concurrent sends read frozen data; the
per-call state is the cursor, allocated per send and handed to exactly one step; the builder is
single-threaded by construction. No wait, no timer and no `Timeout.timeout` exist here; the only
blocking call in reach is phase 2's `Future#value`, and this layer does not call it.

```ruby
closable = Class.new do
  def initialize(inner) = (@inner = inner; @closed = false)
  def call(r, o, c) = @inner.call(r, o, c)
  def close = @closed = true
  def closed? = @closed
end.new(transport)
pipeline = Dexpace::Pipeline.direct(closable)
pipeline.close
pipeline.closed?                                    # => true
closable.closed?                                    # => false
pipeline.call(request).status.code                  # => 200
```
