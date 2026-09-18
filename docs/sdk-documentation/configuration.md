# Configuration and the clock

**As built by phase 5a, in `dexpace-core`, written against source on 2026-09-17.** This page says
what one configuration is and how a value is looked up through it: the four-tier chain and the
strict order that inverts Ruby's habit, the never-throw typed accessors, the builder and the two
seams it swaps, the process-wide slot, the seven declared keys and the two earlier layers that
now read them, the injectable clock and its cancellable wait, the deadline that phase 2's future
gained, the proxy model and its never-raising resolver, and the four small utilities filed beside
them. What each is *required* to do is `docs/product-spec/16-configuration.md`; how the design
maps it to Ruby is `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.2 and §8.3,
read together with entries 16 and 17 of
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`; the
per-requirement proof is `docs/work/mvp/phase5/phase5a/2026-09-09-phase5a-configuration-checklist.md`.
Signatures live in `gems/dexpace-core/sig/dexpace/`, and this page does not restate them. Every
example below was run against the built code on 4.0.6 and 3.2.11 and printed the same on both,
with two exceptions that are the interpreter's and not the layer's: a `Hash#inspect` on the floor
spells `{"APP_NAME"=>"demo"}` where 4.0.6 spells `{"APP_NAME" => "demo"}`, and
`BuildInfo::RUNTIME_VERSION` is the interpreter that ran it. The observability layer — the logging
sink, the redaction rules and the instrumentation events — is phase 5b's and phase 5c's and has its
own pages ([`logging-and-redaction.md`](./logging-and-redaction.md),
[`tracing-and-metrics.md`](./tracing-and-metrics.md)): the one place this layer speaks to an
operator is a `Kernel#warn` from the proxy resolver, and since phase 5b the same helper also emits an
`http.instrumentation.config` event through the `logger:` keyword `Proxy.resolve` gained.

## The chain: `Dexpace::Configuration`

A `Configuration` is a frozen `Data` over three members: an `overrides` map of `String` to
`String`, an `env_source` callable and a `property_source` callable. `#string(name, default:)` is
the one lookup, in `CFG-1`'s strict order — the override under the exact key, then the environment
seam under the exact key, then the property seam under the **normalised** key, then the default —
and every typed accessor routes through it. The order is the reference contract's, and it is the
reverse of what a Ruby library usually does: a value set in code through `Dexpace.configure` is
the *third* tier, and a process environment variable of the same name outranks it. That is
deliberate (design §10, entry 16): the property tier is the SDK's substitute for a system-property
source, a process-wide default a library sets at boot, and the environment is where an operator
overrides a library. `CFG-3`'s normalisation is one-directional and applies to the lookup key on
the property side only: `SERVICE_TIMEOUT` reads the property `service.timeout`, so a property is
stored by its own dotted name and reached by the environment-style one.

```ruby
env   = Dexpace::Configuration::Sources.from_hash("SERVICE_TIMEOUT" => "from_env", "EMPTY" => "")
props = Dexpace::Configuration::Sources.from_hash("service.timeout" => "from_prop",
                                                  "https.proxyHost" => "proxy.corp", "empty" => "")
config = Dexpace::Configuration.build(overrides: { "SERVICE_TIMEOUT" => "from_override" },
                                      env_source: env, property_source: props)
config.string("SERVICE_TIMEOUT")                                          # => "from_override"
config.derive { |b| b.remove("SERVICE_TIMEOUT") }.string("SERVICE_TIMEOUT")  # => "from_env"
no_env = config.derive { |b| b.remove("SERVICE_TIMEOUT"); b.env_source = Dexpace::Configuration::Sources::NONE }
no_env.string("SERVICE_TIMEOUT")                                          # => "from_prop"
no_env.string("HTTPS_PROXYHOST")                                          # => nil
no_env.string("MISSING", default: "none")                                 # => "none"
```

`CFG-2` makes emptiness asymmetric, and the asymmetry is the environment tier's alone: a
present-but-empty environment value is treated as absent and the lookup falls through, while an
empty override or an empty property is an answer. The example above has `EMPTY=""` in the
environment and `empty=""` as a property, so the first read falls through the environment to the
property and gets `""` from *there*; drop the environment and the same key still answers `""`.

```ruby
config.string("EMPTY", default: "fallback")                               # => ""
no_env.string("EMPTY", default: "fallback")                               # => ""
```

`#raw_property(name, default:)` is `CFG-4`'s exact-name read of the third tier and nothing else:
no override, no environment, no normalisation. It exists because the proxy property names carry
case — `https.proxyHost`, `http.nonProxyHosts` — that a fold would destroy, which is also why the
builder stores a property verbatim. A `nil` or blank key is refused everywhere with the one
`Dexpace::InvalidArgumentError` and the `<name> is required` message `SEAM-29` fixes.

```ruby
config.raw_property("https.proxyHost")                                    # => "proxy.corp"
config.raw_property("HTTPS_PROXYHOST")                                    # => nil
config.string(nil)                    # raises Dexpace::InvalidArgumentError, "name is required"
```

### The typed accessors never raise

`#integer`, `#boolean` and `#duration` read through `#string` and parse; a missing or unparseable
value yields the caller's default and never an exception (`CFG-5`). Integers parse in base 10
explicitly — `"010"` is ten, never eight — and negative values are returned as they are. Booleans
are exactly `"true"` and `"false"`, case-insensitively, and nothing else: `"1"`, `"yes"` and `"on"`
all fall to the default (`CFG-6`). Durations come back as `Float` **seconds**, the unit
`Kernel#sleep`, `Thread::Queue#pop(timeout:)` and `RequestOptions#timeout` all speak, from three
grammars in `CFG-7`'s order: ISO-8601 when the text starts with `P` or `p`, then `<number><unit>`
with `ms`, `s`, `m`, `h` or `d`, then a bare number read as **milliseconds** — the clause a reader
gets wrong. A negative duration in any grammar is the default.

```ruby
typed = Dexpace::Configuration.build(
  overrides: { "N" => "010", "B" => "TRUE", "D1" => "PT1.5S", "D2" => "1500ms", "D3" => "1500",
               "D4" => "2m", "NEG" => "-5", "BAD" => "yes", "UNDER" => "1_000", "NEGD" => "-1s" },
  env_source: Dexpace::Configuration::Sources::NONE,
)
typed.integer("N")                                                        # => 10
typed.integer("NEG")                                                      # => -5
typed.integer("UNDER")                                                    # => 1000
typed.integer("BAD", default: 3)                                          # => 3
typed.boolean("B")                                                        # => true
typed.boolean("BAD", default: false)                                      # => false
typed.duration("D1")                                                      # => 1.5
typed.duration("D2")                                                      # => 1.5
typed.duration("D3")                                                      # => 1.5
typed.duration("D4")                                                      # => 120.0
typed.duration("NEGD", default: 0.0)                                      # => 0.0
```

`"1_000"` resolving to `1000` is Ruby's `Kernel#Integer` tolerance, documented rather than removed.

## The builder, the sources and derivation

`Configuration.builder` starts an empty `Configuration::Builder`; `#new_builder` seeds one from an
existing configuration with the override map `dup`ed and both seams passed by reference; `#derive
{ |b| … }` is the copy-on-write shorthand around `#new_builder` and `#build` (`CFG-9`). The
builder's five mutators are `#override(key, value)` and `#remove(key)` for the first tier,
`#property(key, value)` for the third, and the two seam setters `#env_source=` and
`#property_source=` (`CFG-11`). Each refuses a `nil` or blank key, a `nil` value, or a seam that
does not answer `#call`, with `Dexpace::InvalidArgumentError` and before anything is stored
(`CFG-37`). `#remove` drops only the override, so the lookup falls through to the other tiers as
if the key had never been overridden; it never installs a `nil` (`CFG-10`). The built model is
frozen, its override map is a frozen copy, and later mutation of the builder or of the caller's
seed hash does not reach it (`CFG-8`).

```ruby
base = Dexpace::Configuration.builder
  .override("APP_NAME", "demo")
  .property("service.timeout", "5000")
  .build
base.frozen?                                                              # => true
base.overrides                                                            # => {"APP_NAME" => "demo"}
base.string("SERVICE_TIMEOUT")                                            # => "5000"
derived = base.derive { |b| b.override("APP_NAME", "other").property("service.retries", "3") }
derived.string("APP_NAME")                                                # => "other"
base.string("APP_NAME")                                                   # => "demo"
derived.raw_property("service.timeout")                                   # => "5000"
derived.raw_property("service.retries")                                   # => "3"
seed = { "K" => "v" }
cfg = Dexpace::Configuration.build(overrides: seed)
seed["K"] = "changed"
cfg.string("K")                                                           # => "v"
Dexpace::Configuration.builder.override("K", nil)     # raises "value is required"
Dexpace::Configuration.builder.override(" ", "v")     # raises "key cannot be blank"
Dexpace::Configuration.builder.tap { |b| b.env_source = :nope }
                                                      # raises "env_source must answer #call, got Symbol"
```

The seams are the two callables `Configuration::Sources` names and builds. `Sources::ENVIRONMENT`
reads `::ENV` and is the default environment seam; `Sources::NONE` answers `nil` to everything and
is the default property seam, so `Configuration::EMPTY` has "no overrides, platform-backed seams"
exactly as `CFG-13` says; `Sources.from_hash(map)` copies the map with keys and values
stringified, freezes the copy and returns a frozen lambda over it — the hermetic seam a test uses
in place of the process environment.

```ruby
Dexpace::Configuration::Sources::NONE.call("PATH")                        # => nil
Dexpace::Configuration::Sources.from_hash({ a: 1 }).call(:a)              # => "1"
Dexpace::Configuration::Sources.from_hash({ a: nil })   # raises "value for :a is required"
Dexpace::Configuration.builder.build.property_source.equal?(Dexpace::Configuration::Sources::NONE)  # => true
```

What `#build` does with the property tier is the one rule worth knowing before writing against the
builder. An **inherited** seam that the builder never touched is passed through by reference —
`CFG-9` requires `derived.property_source.equal?(receiver.property_source)` — and so is the
environment seam. When `#property` was called over an inherited seam, the two compose: the added
entries shadow the inherited source and fall through to it, which is `CFG-13`'s last-write-wins at
the key level. The two seam operations are mutually exclusive on one builder, in either order:
`#property` after an explicit `#property_source=` would silently shadow the seam just installed,
and `#property_source=` after `#property` would silently discard the entries, so both raise.

```ruby
base.derive { |b| b.override("X", "1") }.property_source.equal?(base.property_source)  # => true
base.derive { |b| b.property("k", "v") }.property_source.equal?(base.property_source)  # => false
b = Dexpace::Configuration.builder.property("k", "v")
b.property_source = Dexpace::Configuration::Sources::NONE
                        # raises "property_source= cannot follow property; the entries would be lost"
b2 = Dexpace::Configuration.builder.tap { |x| x.property_source = Dexpace::Configuration::Sources::NONE }
b2.property("k", "v")   # raises "property cannot be added after an explicit property_source="
```

## The slot: `Dexpace.configure`, `.configuration`, `.reset_config!`

The process-wide configuration is one frozen reference. `Dexpace.configuration` reads it with no
lock, because a frozen snapshot swapped whole is safe to publish through a plain reference under
the GVL and the mutex is for the writers. `Dexpace.configure { |builder| … }` seeds a builder from
the **live** slot, yields it, builds *outside* the mutex — so a block that reads the slot cannot
deadlock a non-reentrant, per-fiber-owned mutex — and swaps the result in under it; it returns the
configuration it published. `Dexpace.reset_config!` swaps `Configuration::EMPTY` back in and
returns it. Replacement is last-write-wins (`CFG-13`), which is why the builder treats the
inherited seam as inherited: a library setting a property at boot and an application adding one
later is the ordinary case, and the second `configure` must not raise. There is no observer,
listener or change notification; a reader that wants the latest value reads the slot again.

```ruby
Dexpace.configuration.equal?(Dexpace::Configuration::EMPTY)              # => true
returned = Dexpace.configure { |c| c.property("service.timeout", "5000") }
returned.equal?(Dexpace.configuration)                                    # => true
Dexpace.configure { |c| c.property("https.proxyHost", "proxy.corp") }
Dexpace.configuration.raw_property("service.timeout")                     # => "5000"
Dexpace.configuration.string("SERVICE_TIMEOUT")                           # => "5000"
snapshot = Dexpace.configuration
Dexpace.configure { |c| c.property("service.timeout", "9000") }
snapshot.raw_property("service.timeout")                                  # => "5000"
Dexpace.configuration.raw_property("service.timeout")                     # => "9000"
Dexpace.reset_config!.equal?(Dexpace::Configuration::EMPTY)              # => true
Dexpace.configure                                     # raises "configure block is required"
before = Dexpace.configuration
Dexpace.configure { |c| c.override("K", nil) }        # raises Dexpace::InvalidArgumentError
Dexpace.configuration.equal?(before)                                      # => true
```

A block that raises publishes nothing. Every test that calls `Dexpace.configure` restores the
slot in its teardown; `config_test.rb` is the shape to copy.

## The keys: `Configuration::Keys`, and the two layers that read them

`Configuration::Keys` declares the seven names `CFG-14` fixes as `String` constants —
`MAX_RETRY_ATTEMPTS`, `LOG_LEVEL`, `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`,
`MAX_MATERIALIZED_BYTES` and `MAX_TRACKED_CONTEXTS` — and, since phase 5b, an eighth,
`LOG_PREVIEW_BYTES`. Declaring a key is not reading it: `MAX_RETRY_ATTEMPTS` is read by the retry
layer when it lands; `LOG_LEVEL` and `LOG_PREVIEW_BYTES` are the names a caller hands the logging
layer (`HTTPLogging.resolve(config, key:)` and `Step.build(preview_bytes:)`), which reads neither on
its own; the three proxy names are read by `Proxy.resolve` below, and the last two by the two earlier
layers this phase wired to the chain.
The seven `https.proxy*` / `http.proxy*` / `http.nonProxyHosts` property names are the resolver's
private business and are not on `Keys`.

**The materialisation ceiling is live.** `Dexpace::IO.max_materialized_bytes(configuration =
Dexpace.configuration)` reads `Keys::MAX_MATERIALIZED_BYTES` through the chain as an integer and
falls back to `IO::MAX_MATERIALIZED_BYTES` when the key is absent, unparseable or not positive.
The five places that consult the ceiling — `TypedReads#guard_materialization!` (and through it
`Buffer#snapshot`), `Body.clamp_cap`, `StreamBody#replayable?` and `BufferBody#==` — call the
function on every check, so `Dexpace.configure` governs every materialisation from the next call
on, `reset_config!` restores the constant, and the refusal names the limit that applied. The
constant is the default and the fallback; there is no `ceiling:` keyword anywhere.

```ruby
Dexpace::IO::MAX_MATERIALIZED_BYTES                                       # => 67108864
Dexpace::IO.max_materialized_bytes                                        # => 67108864
Dexpace.configure { |c| c.override("MAX_MATERIALIZED_BYTES", "8") }
Dexpace::IO.max_materialized_bytes                                        # => 8
src = Dexpace::IO::BufferedSource.of_bytes("0123456789".b)
src.read_exactly(10)                    # raises Dexpace::StreamError, "refusing to materialize 10 bytes
                                        #   as one String: the limit is 8 bytes (Dexpace::IO.max_materialized_bytes; …"
src.read_exactly(8).bytesize                                              # => 8
Dexpace.configure { |c| c.override("MAX_MATERIALIZED_BYTES", "-1") }
Dexpace::IO.max_materialized_bytes                                        # => 67108864
Dexpace.reset_config!
Dexpace::IO.max_materialized_bytes(:nope)   # raises "configuration must be a Dexpace::Configuration, got Symbol"
```

**The context-store cap is read once, at first use.** `Dexpace::ContextStore.default` is built on
its first call, under one `::Thread::Mutex`, with `cap:` read from
`Keys::MAX_TRACKED_CONTEXTS` through the live chain then, and `ContextStore::MAX_TRACKED_CONTEXTS`
(1024) when the key is absent or not a positive integer. Phase 4a assigned the store at file load,
which no `Dexpace.configure` could ever reach; now a `configure` at boot, before the first context
is promoted, sizes it, and a `configure` after the first promotion does not resize it — nor does
`reset_config!`. The mutex is what makes a first-call construction as sound as a load-time one:
sixteen threads reaching `.default` together get one store (`context_store_config_test.rb`), where
an unsynchronised `@default ||= new` would give sixteen. The chain is read *outside* the mutex and
only the `||=` runs under it — no caller-supplied seam ever runs under the lock, the rule
`Dexpace.configure` follows — and once published the reference is read without the lock, so a
promotion after the first runs no seam and takes no lock. Constructing the store registers no
context (`CTX-17`).

```ruby
Dexpace::ContextStore::MAX_TRACKED_CONTEXTS                               # => 1024
Dexpace::ContextStore.default.equal?(Dexpace::ContextStore.default)      # => true
```

## The clock: `Dexpace::Clock`

`Clock` is the injectable time source `CFG-15` and `CFG-16` ask for, with exactly the three
instance methods the RBS interface `Dexpace::_Clock` declares — `#now` (a wall-clock `Time`),
`#monotonic` (a `Float` of seconds on `Process::CLOCK_MONOTONIC`'s scale, never wall time), and
`#sleep(duration, cancellation: nil)` — and one shared instance, `Clock::SYSTEM`, backed by the
platform. A fake owes the seam those three and nothing else; `test/support/fake_clock.rb` is the
one the suite uses. Time-arithmetic never reads `#now`: a deadline is an instant on the monotonic
scale, and `Clock.deadline_in(duration, clock: SYSTEM)` — a class method, deliberately, so the
interface stays at three — computes one, because computing a deadline off `Time.now` is exactly
the mistake `CFG-16` forbids.

`#sleep` blocks the calling thread and is interruptible (`CFG-15`, `CFG-17`), and how it does
that is the design decision worth knowing (design §10, entry 17): the wait is a per-call
`::Thread::Queue#pop(timeout:)`, the cancellation token's `#on_cancel` hook pushes into that
queue, and the token is re-checked after the wake. `Kernel#sleep` cannot be woken without
`Thread#raise`, which every gem here bans, and the queue wait interrupts at a safe point rather
than on an arbitrary bytecode instruction. A zero duration returns at once, an already-cancelled
token raises before any wait, a cancel *during* the wait wakes it promptly and raises
`Dexpace::CancelledError`, and a wait that elapsed returns `nil`. The hook is detached in an
`ensure`, so a token that outlives the wait carries no leak.

```ruby
clock = Dexpace::Clock::SYSTEM
clock.frozen?                                                             # => true
clock.now.class                                                           # => Time
clock.monotonic.class                                                     # => Float
clock.sleep(0.05)                                                         # => nil
clock.sleep(0)                                                            # => nil
clock.sleep(-1)                         # raises "duration must be non-negative, got -1"
clock.sleep("1")                        # raises "duration must be a number of seconds, got String"
source = Dexpace::Cancellation::Source.new
clock.sleep(0.05, cancellation: source.token)                             # => nil
Thread.new { sleep 0.05; source.cancel(:demo) }
clock.sleep(30, cancellation: source.token)   # raises Dexpace::CancelledError well inside a second,
                                              #   "the operation was cancelled: demo"
clock.sleep(1, cancellation: :nope)     # raises "cancellation: takes a Dexpace::Cancellation, got Symbol"
Dexpace::Clock.deadline_in(5) > clock.monotonic                           # => true
Dexpace::Clock.instance_methods(false).sort                               # => [:monotonic, :now, :sleep]
```

### Deadlines on the future, and the scheduler-conditional delay

Phase 2's `Async::Future#wait`, `#value` and `Async::Completer#await` now take `deadline:` — an
instant on `#monotonic`'s scale, the value `Clock.deadline_in` returns — and `clock:`, the seam
the instant is measured against, defaulting to `Clock::SYSTEM`. The positional cancellation stays
where it was. The deadline is the same timed gate pop the clock uses, and an expiry does not raise
past the wait: it calls the completer's `request_cancel(:deadline_expired)`, so the future
**settles**, `#wait` returns the settled future as it always did, and `#value` raises
`Dexpace::CancelledError` naming `deadline_expired`. A future already settled returns at once
whatever the deadline; a deadline already in the past settles it at once; a `nil` deadline is
phase 2's unbounded wait. The one settlement wins as before — a `fulfil` after expiry returns
`false` and changes nothing.

```ruby
completer = Dexpace::Async::Completer.new
future = completer.future
future.wait(deadline: Dexpace::Clock.deadline_in(0.05)).settled?          # => true
future.value                            # raises Dexpace::CancelledError,
                                        #   "the operation was cancelled: deadline_expired"
completer.fulfil(:late)                                                   # => false
c2 = Dexpace::Async::Completer.new
c2.fulfil(:ok)
c2.future.value(deadline: Dexpace::Clock.deadline_in(0.05))               # => :ok
c3 = Dexpace::Async::Completer.new
c3.future.wait(deadline: -1).settled?                                     # => true
c4 = Dexpace::Async::Completer.new
Thread.new { sleep 0.05; c4.fulfil(:slow) }
c4.future.value(deadline: Dexpace::Clock.deadline_in(30))                 # => :slow
c5 = Dexpace::Async::Completer.new
c5.future.wait(deadline: "5")           # raises "deadline: takes a monotonic instant (Numeric), got String"
c5.future.wait(deadline: 1, clock: :nope)
                                        # raises "clock: takes a Dexpace::_Clock answering #monotonic, got Symbol"
```

`Dexpace::Async.delay(duration)` is `CFG-18`'s non-blocking counterpart: a `Future` that settles
with `true` once the duration has elapsed, **without** occupying a thread. It is
scheduler-conditional. A zero duration settles at once anywhere; otherwise it needs a
`Fiber.scheduler` on the calling thread — under one, the timed queue pop routes through the
scheduler's `block`/`unblock` hooks and unmounts the fiber, so the carrier thread is free — and
raises `Dexpace::SeamError` without one, because a thread-backed fallback would honour the letter
of the MUST clauses while violating the headline, and the error says what to do instead. The
future settles with `true`, not `nil`, because phase 2's `SEAM-16` makes a `nil`-valued settlement
unconstructible (P5-52). `Future#cancel` on the returned future stops the timer.

```ruby
Dexpace::Async.delay(0).value                                             # => true
Dexpace::Async.delay(0.01)              # raises Dexpace::SeamError on a thread with no Fiber.scheduler:
                                        #   "Async.delay needs a registered Fiber.scheduler to complete
                                        #   without blocking a thread (CFG-18). Register one with
                                        #   Fiber.set_scheduler, or use Dexpace::Clock#sleep, which blocks
                                        #   the calling thread by design."
Dexpace::Async.delay(-1)                # raises "duration must be non-negative, got -1"
```

## The proxy: `Dexpace::Proxy`, `Proxy::Type`, `Proxy::HostPattern`

`Proxy` is a frozen `Data` over eight members — `type`, `host`, `port`, `non_proxy_hosts`,
`username`, `password`, `challenge_handler`, `bypass_all` — built through `Proxy.build` with the
last five optional (`CFG-22`). The port is validated into `0..65535`, the type is resolved through
`Proxy::Type.of`, and every non-proxy entry must already be a `HostPattern`. Both renderings mask
both credentials — `CFG-22`'s words are "never emit username/password in cleartext": `#to_s` is
`type://****:****@host:port`, each credential present rendered as `****` in its userinfo position
and an absent one as nothing, so the shape says which is set and never what it is; `#inspect`
prints every member, the username and the password each as `"****"` when present and `nil` when
absent, and the challenge handler by its class only. The accessors `#username` and `#password`
return the values — the model holds them, it is the renderings that never show them.
`#bypass?(host)` is `true` when `bypass_all` is set, otherwise when any pattern matches
(`CFG-23`).

```ruby
proxy = Dexpace::Proxy.build(type: :http, host: "proxy.corp", port: 3128, username: "u", password: "s3cret",
                             non_proxy_hosts: [Dexpace::Proxy::HostPattern.of("*.internal"),
                                               Dexpace::Proxy::HostPattern.of("localhost")])
proxy.to_s                                                                # => "http://****:****@proxy.corp:3128"
proxy.inspect
# => "#<Dexpace::Proxy type=\"HTTP\" host=\"proxy.corp\" port=3128 non_proxy_hosts=[\"*.internal\", \"localhost\"] username=\"****\" password=\"****\" challenge_handler=nil bypass_all=false>"
proxy.username                                                            # => "u"
proxy.password                                                            # => "s3cret"
proxy.bypass?("DB.INTERNAL")                                              # => true
proxy.bypass?("api.example.com")                                          # => false
proxy.with(port: 8080).to_s                                               # => "http://****:****@proxy.corp:8080"
proxy.with(port: 65536)                 # raises "port must be within 0..65535, got 65536"
proxy.with(password: nil).to_s                                            # => "http://****@proxy.corp:3128"
Dexpace::Proxy.build(type: "socks5", host: "h", port: 1080).to_s          # => "socks5://h:1080"
Dexpace::Proxy.build(type: "ftp", host: "h", port: 1)
                                        # raises "unknown proxy type \"ftp\"; one of HTTP, SOCKS4, SOCKS5"
```

`Proxy::Type` is a closed set of three — `HTTP`, `SOCKS4`, `SOCKS5` — in the shape the pipeline's
`Stage` set has, not the shape phase 1's `Status` has: `.of(token)` is the only lookup, accepting a
`Type` or a `String`/`Symbol` folded and stripped, and canonicalising a `dup`ed copy back to its
constant; `.new` and `.[]` are private, there is no `.build`, and `#with` refuses, so the three
constants are the whole population and identity comparison over them holds.

```ruby
proxy.type.equal?(Dexpace::Proxy::Type::HTTP)                             # => true
Dexpace::Proxy::Type.of(" socks4 ").equal?(Dexpace::Proxy::Type::SOCKS4)  # => true
Dexpace::Proxy::Type.of(Dexpace::Proxy::Type::HTTP.dup).equal?(Dexpace::Proxy::Type::HTTP)  # => true
Dexpace::Proxy::Type::HTTP.with(name: "X")                                # raises Dexpace::InvalidArgumentError
Dexpace::Proxy::Type.new(name: "X")                                       # raises NoMethodError
```

`Proxy::HostPattern` is a one-member `Data` over `glob`, with the compiled `Regexp` a private
instance variable set once at construction (`CFG-23`; P5-53): `*` matches any run, `?` exactly
one character, every other character is literal, the match is anchored `\A…\z` — so a trailing
newline never matches — case-insensitive, and compiled with a per-pattern `timeout:`, never the
process-global `Regexp.timeout`. Equality is over the glob, which is the value; the pattern is the
mechanism, and `#with` recompiles it through `.build` on every Ruby.

```ruby
pat = Dexpace::Proxy::HostPattern.of("*.example.?om")
pat.matches?("API.EXAMPLE.COM")                                           # => true
pat.matches?("example.com")                                               # => false
pat.matches?("a.example.com\n")                                           # => false
pat.matches?(nil)                                                         # => false
Dexpace::Proxy::HostPattern.of("a.b").matches?("axb")                     # => false
pat.inspect                                                               # => "#<data Dexpace::Proxy::HostPattern glob=\"*.example.?om\">"
pat == Dexpace::Proxy::HostPattern.of("*.example.?om")                    # => true
```

### Resolution: `Proxy.resolve`

`Proxy.resolve(configuration = Dexpace.configuration, logger: Instrumentation::Logger::NULL)` reads
a proxy out of the chain and **never raises** on its content: an invalid configuration yields `nil`
after one `Kernel#warn` prefixed `[dexpace]` (`CFG-24`; P5-8 keeps it `Kernel#warn` — phase 5b added
an `http.instrumentation.config` event beside it through `logger:` and removed nothing). The one
thing that does raise is being handed something that is
not a `Configuration`, which is the caller's argument and not the configuration's content.
`CFG-28`'s prohibition on implicit reads is met structurally: nothing in core calls `.resolve`, so
no environment read happens until a caller asks.

The order is `CFG-24`'s. The property tier is consulted first, by `#raw_property` under the exact
names: `https.proxyHost` / `https.proxyPort` win over `http.proxyHost` / `http.proxyPort`, and the
port is taken from the **same layer** as the chosen host — one lookup on the layer the host was
found under, never two independent reads. Credentials come from `https.proxyUser` /
`https.proxyPassword` only, with no `http.*` fallback. A property host with a port that is
missing, non-numeric or outside `0..65535` yields `nil` with a warning and does *not* fall through
to the environment (`CFG-25`): a set-but-unusable proxy is a configuration error, not an absence.
Only when no property host is set is the environment read, `HTTPS_PROXY` then `HTTP_PROXY` — the
first non-blank of the two, so a blank `HTTPS_PROXY` from any tier does not mask `HTTP_PROXY` — as
a URL whose scheme selects the type, whose port must be explicit — `CFG-25` forbids defaulting to
80 or 443 — and whose userinfo is percent-decoded into the credentials.

```ruby
def resolve_with(env: {}, props: {})
  cfg = Dexpace::Configuration.build(env_source: Dexpace::Configuration::Sources.from_hash(env),
                                     property_source: Dexpace::Configuration::Sources.from_hash(props))
  Dexpace::Proxy.resolve(cfg)
end
resolve_with(props: { "https.proxyHost" => "p1", "https.proxyPort" => "3128",
                      "http.proxyHost" => "p2", "http.proxyPort" => "8080" }).to_s      # => "http://p1:3128"
resolve_with(props: { "http.proxyHost" => "p2", "http.proxyPort" => "8080",
                      "https.proxyUser" => "u", "https.proxyPassword" => "pw" }).to_s  # => "http://****:****@p2:8080"
resolve_with(props: { "https.proxyHost" => "p1", "http.proxyPort" => "8080" })        # => nil
# stderr: [dexpace] proxy port for p1 (https.proxyPort) is missing, non-numeric or outside 0..65535
r = resolve_with(env: { "HTTPS_PROXY" => "http://u%40x:p%3Aw@proxy.corp:3128",
                        "NO_PROXY" => "*.internal, localhost" })
r.to_s                                                                    # => "http://****:****@proxy.corp:3128"
r.username                                                                # => "u@x"
r.password                                                                # => "p:w"
r.non_proxy_hosts.map(&:glob)                                             # => ["*.internal", "localhost"]
resolve_with(env: { "HTTP_PROXY" => "socks5://proxy.corp:1080" }).type.name             # => "SOCKS5"
resolve_with(env: { "HTTPS_PROXY" => "  ", "HTTP_PROXY" => "http://plain:3128" }).host      # => "plain"
resolve_with(env: { "HTTPS_PROXY" => "https://proxy.corp" })                            # => nil
# stderr: [dexpace] proxy URL "https://proxy.corp" has no explicit port; CFG-25 forbids defaulting to 80 or 443
Dexpace::Proxy.resolve(:nope)           # raises "configuration must be a Dexpace::Configuration, got Symbol"
```

The non-proxy list follows `CFG-26` and `CFG-27`: the property `http.nonProxyHosts`, split on
`|`, wins outright over the environment's `NO_PROXY`, split on `,`; in both, a separator escaped
with a backslash is literal, entries are trimmed and empties dropped, and a list that is exactly
`*` means bypass everything — which `.resolve` reports as `nil`, because a proxy no request will
use is not a proxy.

```ruby
resolve_with(env: { "HTTPS_PROXY" => "http://proxy.corp:3128", "NO_PROXY" => "*" })    # => nil
resolve_with(env: { "HTTPS_PROXY" => "http://proxy.corp:3128", "NO_PROXY" => "a\\,b,c" })
  .non_proxy_hosts.map(&:glob)                                            # => ["a,b", "c"]
resolve_with(env: { "HTTPS_PROXY" => "http://proxy.corp:3128", "NO_PROXY" => "env.only" },
             props: { "http.nonProxyHosts" => "a|b" }).non_proxy_hosts.map(&:glob)     # => ["a", "b"]
```

## The utilities: `HTTPDate`, `UUID`, `Retryability`, `BuildInfo`

**`Dexpace::HTTPDate`** is the RFC 1123 pair. `.format(time)` is `Time#httpdate` — `getutc` then
the fixed English format, byte-exact against the specification's own example, so a local-zone
`Time` renders as GMT (`CFG-30`); the month and weekday names are CRuby's own tables and never the
locale, which was verified under a `de_DE.UTF-8` `LOCPATH` on 3.2.11, 3.4.10 and 4.0.6. `.parse`
is an **owned** anchored grammar, not `Time.httpdate`: the stdlib parser accepts the obsolete RFC
850 and asctime forms `CFG-31` refuses, and `Time.parse` is banned repository-wide. The grammar is
lenient on the weekday token and the case, strict from the day of month on, and accepts the four
zone spellings `GMT`, `UTC`, `+0000` and `+00:00` as the same instant — then checks every
component against what `Time.utc` built, because `Time.utc(1994, 11, 31)` is silently 1 December
(P5-54). Both a grammar miss and an impossible date are `Dexpace::InvalidArgumentError` naming the
input.

```ruby
t = Time.utc(1994, 11, 6, 8, 49, 37)
Dexpace::HTTPDate.format(t)                                               # => "Sun, 06 Nov 1994 08:49:37 GMT"
Dexpace::HTTPDate.format(t.getlocal("+05:00"))                            # => "Sun, 06 Nov 1994 08:49:37 GMT"
Dexpace::HTTPDate.parse("Sun, 06 Nov 1994 08:49:37 GMT") == t             # => true
Dexpace::HTTPDate.parse("sun, 06 nov 1994 08:49:37 utc") == t             # => true
Dexpace::HTTPDate.parse("Xyz, 06 Nov 1994 08:49:37 GMT") == t             # => true
Dexpace::HTTPDate.parse("Sun, 06 Nov 1994 08:49:37 +00:00").utc?          # => true
Dexpace::HTTPDate.parse("Sunday, 06-Nov-94 08:49:37 GMT")
                                  # raises "not an RFC 1123 date: \"Sunday, 06-Nov-94 08:49:37 GMT\""
Dexpace::HTTPDate.parse("Thu, 31 Nov 1994 08:49:37 GMT")
                                  # raises "impossible date components in RFC 1123 date: \"Thu, 31 Nov 1994 08:49:37 GMT\""
Time.utc(1994, 11, 31).day                                                # => 1
Dexpace::HTTPDate.format("now")   # raises "time must be a Time, got String"
```

**`Dexpace::UUID.generate`** is a version-4 UUID in the canonical lower-case hyphenated form,
frozen, drawn from a `::Random` kept in `Thread.current[:dexpace_prng]` — a fiber-local slot, so
one generator per execution context and none shared (`CFG-32`) — and never from `SecureRandom`.
`securerandom` is on the require allowlist, so the require gate would not notice that
substitution; the suite's text scan of `uuid.rb` is what does.

```ruby
u = Dexpace::UUID.generate
u =~ /\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/                          # => 0
u.frozen?                                                                 # => true
Dexpace::UUID.generate == Dexpace::UUID.generate                          # => false
Thread.current[:dexpace_prng].class                                       # => Random
Thread.new { Thread.current[:dexpace_prng] }.value                        # => nil
```

**`Dexpace::Retryability.retryable_status?(status)`** is `CFG-35`'s status half, over an `Integer`
or anything answering `#code` with one — phase 1's `Status` included: 408, 429 and every 5xx but
501 and 505 are retryable, nothing else is. The throwable half is phase 6a's, where the transport
error classes it needs land.

```ruby
Dexpace::Retryability.retryable_status?(408)                              # => true
Dexpace::Retryability.retryable_status?(503)                              # => true
Dexpace::Retryability.retryable_status?(501)                              # => false
Dexpace::Retryability.retryable_status?(404)                              # => false
Dexpace::Retryability.retryable_status?(Dexpace::Status.of(502))          # => true
Dexpace::Retryability.retryable_status?("503")
                            # raises "status must be an Integer or answer #code with one, got String"
```

**`Dexpace::BuildInfo`** resolves the SDK version and the runtime's version, vendor and OS name
once at load into frozen constants, each falling back to the non-blank `UNKNOWN` (`"unknown"`), and
composes `IDENTITY_TOKENS`, the ordered pair a User-Agent-style string is made from — SDK token
first, runtime token second (`CFG-36`). Every component is read off a constant that needs no
`require`, so the allowlist did not grow; composing the User-Agent itself is not this module's job.

```ruby
Dexpace::BuildInfo::SDK_VERSION                                           # => "0.0.0"
Dexpace::BuildInfo::RUNTIME_VENDOR                                        # => "ruby"
Dexpace::BuildInfo::OS_NAME                                               # => "linux"
Dexpace::BuildInfo::IDENTITY_TOKENS                                       # => ["dexpace-ruby/0.0.0", "ruby-4.0.6/linux"]
Dexpace::BuildInfo::IDENTITY_TOKENS.all?(&:frozen?)                       # => true
```

## Structural equality, which nothing calls yet

`Dexpace::DeepValue` is `CFG-33`'s and `CFG-34`'s content-based equality and the hash that
matches it — recursive over `Array` and `Hash`, `nil`-safe with `nil` hashing to zero, and with the
floating-point rules Ruby's own `==` and `#hash` get wrong for this purpose: NaN equals NaN and
every NaN hashes alike whatever its payload, `+0.0` and `-0.0` are unequal and hash apart, and an
`Integer` array is not a `Float` array of the same values. It is cycle-safe where a naive
recursion is not. It is a `private_constant` on `Dexpace`: no caller exists anywhere in v1, it
exists to satisfy the conformance clause, and promoting it later is a widening `NFR-4` permits
where the reverse would be a break. It is reachable by bare name from any file that reopens
`module Dexpace`, which is how `configuration_test.rb` drives it; the examples below alias it that
way and are the only ones on this page not written against a public name.

```ruby
module Dexpace; DeepValueDemo = DeepValue; end
nan = 0.0 / 0.0
Dexpace::DeepValueDemo.equal?([nan], [-nan])                              # => true
[nan] == [-nan]                                                           # => false
Dexpace::DeepValueDemo.equal?([0.0], [-0.0])                              # => false
[0.0] == [-0.0]                                                           # => true
Dexpace::DeepValueDemo.equal?([1], [1.0])                                 # => false
[1] == [1.0]                                                              # => true
Dexpace::DeepValueDemo.hash([nan]) == Dexpace::DeepValueDemo.hash([-nan]) # => true
Dexpace::DeepValueDemo.hash(nil)                                          # => 0
Dexpace::DeepValue                                                        # raises NameError
```

## What to know before writing against it

- **Read the chain, do not cache it.** `Dexpace.configuration` is cheap — one reference read — and
  a snapshot held across a `configure` is a stale snapshot by design. The context store is the one
  deliberate exception, and this page says so above.
- **A property is the third tier.** If a value you set through `Dexpace.configure { |c|
  c.property(…) }` is not what you read back, look for an environment variable of the normalised
  name first; that is the order working, not failing.
- **Durations are seconds and bare numbers are milliseconds.** `#duration` returns what
  `Clock#sleep` takes; a configuration value of `"1500"` is one and a half seconds.
- **Deadlines are instants, not durations.** Pass `Clock.deadline_in(seconds)` to `deadline:`,
  never a number of seconds; a small positive number is an instant in the past on a monotonic
  clock that has been running since boot, and the wait settles at once.
- **Nothing here spawns a thread, and only two things block.** `Clock#sleep` and a `deadline:` wait
  block the calling thread on a timed queue pop and nothing else; `Async.delay` refuses rather
  than blocks; `Proxy.resolve` warns rather than raises. No `Timeout.timeout`, no `Thread#raise`,
  no `Kernel#sleep` exists in this layer.
- **The proxy resolver's warning is `Kernel#warn` and stays so.** Phase 5b's logging layer added an
  event beside it, reachable through `Proxy.resolve(config, logger:)`; a consumer that wants the
  warning's text somewhere else passes a logger or redirects `$stderr`, and does not expect the
  warning itself to change.
