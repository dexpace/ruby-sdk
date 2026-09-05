## 8. Instrumentation and Configuration

### 8.1 The instrumentation seam

**The event model is a listener with one method per event, not a generic bus.** The obvious Ruby shape is a
`#call(event_name, payload)` pub/sub bus, rejected because **OBS-1** requires a disabled level to allocate nothing
and a `(name, payload)` bus forces a `Hash` allocation at every call site whether or not anyone is listening. A
listener duck-typed on named methods — `#request_started(ctx)`, `#attempt_failed(ctx, error, next_delay)`,
`#connection_acquired(ctx)`, the rest of **OBS-28**'s HTTP-shaped vocabulary — passes arguments on the stack and
allocates nothing when the installed listener is the frozen `Dexpace::Instrumentation::NULL`. **OBS-29**'s
lifecycle ordering (one `operation_started`; mutually exclusive single `operation_succeeded`/`operation_failed`;
attempt events repeating; `retries_exhausted` immediately followed by `operation_failed` carrying the same error;
one listener per logical operation) is asserted by an ordering test. A `CallableAdapter` wrapping a
`#call(name, payload)` object is offered so the bus shape is available without being the default. **OBS-30**'s
"callbacks MUST NOT throw, and the runtime does NOT defensively catch them" is preserved as written — tracer and
meter calls are not wrapped — while every *log-emission* site is wrapped and degrades to an
`http.instrumentation.*` diagnostic (**OBS-20**, **XCUT-20**).

**The structured log event is a builder object, not a logger call, and that is what eight MUSTs require.** A plain
`Logger`-shaped sink is the wrong *shape* for the OBS-1 family, and the mistake is worth naming because the sink is
so obviously the idiomatic Ruby answer that it is easy to stop there. **OBS-1** does not merely say the disabled
path is cheap; it says "The facade MUST decide enabled/disabled once, at event-creation time, and return a shared
inert event for the disabled case." That is an object with an identity a conformance test can assert, and its
conformance note says so outright: "assert the returned event is the shared singleton (reference-identical across
calls)." Seven further MUSTs — empty-key rejection, the reserved tag, source precedence, rendering totality,
emit-once, the global context and the stable vocabulary — are stated *about that object* and have nowhere to live
on a `sink.info { }` call, and two SHOULDs hang off the same object. So core defines one:

```
Dexpace::Instrumentation::Event                # obtained from Logger#event(severity), never constructed directly
  #field(key, value)   #tag(key, value)   #event(name)   #cause(error)   #emit
Dexpace::Instrumentation::Event::INERT         # the frozen shared singleton returned when the severity is disabled
```

Every builder method returns `self` so chains compose, and `INERT` is a frozen instance whose builder methods
return `self` and whose `#emit` does nothing. `Logger#event` performs the enabled check **once**, at that call, and
returns either a fresh live event or `INERT` — so a disabled `logger.event(:verbose).field(:k, v).cause(e).emit`
allocates nothing beyond the arguments the caller had already computed, and the singleton is reference-identical
across calls (**OBS-1**). The honest limit is unchanged and worth restating: Ruby cannot make an *enabled*
structured event allocation-free, and **OBS-1** does not ask it to; the disabled path is what must allocate nothing,
and it is tested by allocation count. The eight clauses the object then carries:

- **Keys and null values** (**OBS-3**). An empty key raises an `ArgumentError` at `#field` — the caller's bug,
  surfaced at the call site rather than as a malformed line in a log aggregator. A `nil` **value** is not dropped:
  it is emitted as the literal `null`, because a dropped key and a null key mean different things to whoever is
  reading the output, and Ruby's habit of treating `nil` as "not there" is exactly the reflex this forbids.
- **The reserved `event` tag** (**OBS-4**). `#event(name)` sets the authoritative categorisation tag under the
  reserved key `event`; an empty name clears the tag rather than emitting `event=`. When a non-empty tag is set,
  any `event` key arriving from the global context, the folded diagnostic context, or a per-event field is
  suppressed, so the emitted record carries `event` exactly once. The rationale is the requirement's own and is
  concrete: a JSON appender handed two `event` keys produces invalid output.
- **Precedence and at-most-once** (**OBS-5**). Per-event field beats global context beats folded diagnostic
  context, and a key appears at most once in the emitted record. Implemented as one merge in that order into a
  single `Hash` at emit time rather than as three sources consulted by the renderer, because a renderer that
  consults three sources is a renderer that can emit a key twice.
- **Rendering is total** (**OBS-6**). An exception renders as `SimpleClassName: message` (Ruby: `e.class.name` with
  namespaces stripped, then the message); arrays, hashes and other collections render in a bracketed textual form;
  numerics, booleans and characters pass through type-preserving so a JSON appender emits a number rather than a
  quoted string. And the clause that matters most in Ruby: **if a value's own `#to_s` raises, the facade
  substitutes a diagnostic placeholder rather than propagating.** Ruby makes this reachable in a way a language
  with a guaranteed `toString` does not — `BasicObject` has no `#to_s` at all, a lazily-loaded proxy can raise from
  it, and `#inspect` on a partially initialised object raises routinely — so the rendering path rescues
  `StandardError` per value and substitutes `[unrenderable <ClassName>]`. **OBS-7**'s bounded truncation with a
  marker (reference 8 KiB, primitives exempt) is a **SHOULD** and is implemented on the same path.
- **Emit at most once, correctly under concurrency** (**OBS-8**). A second terminal `#emit` on the same instance is
  a no-op, and the guard must be correct under concurrent invocation even though field accumulation need not be
  thread-safe. This is the same latched flag as §3.7's close: a `@emitted` boolean flipped under a `Thread::Mutex`
  with the mutex released before the sink call, so an emit that blocks on I/O does not hold a lock across a
  suspension point. Not the GVL: a lone flag read and write is atomic on CRuby but not on JRuby or TruffleRuby, and
  §1 fixes safe publication as the port's rule for exactly this reason.
- **Global context on every event** (**OBS-9**). A global key/value context configured on the logger attaches to
  every event that logger produces, subject to **OBS-5** precedence. The context is **referenced, not deep-copied
  per event**, which is the requirement's own hot-path preference, and the consequence is stated rather than
  assumed: the context is expected to be effectively immutable, so the logger freezes what it is given at
  configuration time instead of trusting the caller to leave it alone.
- **Stable names and keys** (**OBS-39**). The emitted vocabulary is fixed, not incidental: events named
  `http.request` and `http.response`, carrying `http.request.method`, `url.full`, `http.response.status_code`,
  `http.response.duration_ms`, and the content-length and header fields; a failure emits an `http.response` event
  carrying `error.type` with the exception attached as the cause. `url.full` is **always** the redacted URL — the
  single most consequential line in this subsection, since an unredacted `url.full` is how query-string credentials
  reach a log aggregator. Redaction (**OBS-11**–**OBS-19**) runs on the way into `#field`, not at the sink, so no
  sink implementation can bypass it. The names are frozen constants and covered by §9.1's surface snapshot, because
  a "stable" vocabulary that nothing asserts drifts on the first refactor.
- **The collision diagnostic** (**OBS-40**, a **SHOULD**, implemented). A caller setting a per-event field named
  `event` while a tag is set has that field dropped in favour of the tag; the logger warns once, at verbose level,
  gated on verbose being enabled so it costs nothing when disabled, and throttled to one emission per logger by a
  latched flag. Ambient `event` keys from the global or diagnostic context defer silently and are **not** warned
  about, since the caller did not write them.

**Beneath the event object, the output sink is a duck type, and core never `require`s `logger`** — §2.4's reason:
`logger` becomes a bundled gem in Ruby 4.0 (verified), so requiring it from a zero-dependency core creates an
undeclared dependency on a supported interpreter. The sink is where a rendered event goes once `#emit` has done the
work above; it is an *output adapter*, not the facade. Core defines it as anything responding to
`#debug`/`#info`/`#warn`/`#error` plus the `#debug?`-style predicates, which is exactly the stdlib `Logger`
surface, so a stdlib `Logger`, a Rails logger or `SemanticLogger` drops in with zero adapter code (P14); a frozen
`NullLogger` whose predicates return `false` is the default, and it is the predicate `Logger#event` consults to
decide between a live event and `INERT`. Emission uses the block form (`sink.debug { ... }`) so no rendering runs
if the sink's own level check disagrees — a redundant guard for a sink whose level moved after event creation, not
the enabled decision, which **OBS-1** fixes at `#event`. **OBS-2**'s four severities — ERROR, WARNING, INFO,
VERBOSE — map onto `Logger`'s `ERROR`/`WARN`/`INFO`/`DEBUG`, which is the mapping the requirement names.

**Which bridges ship, and the rule that picks them.** The reference chose its two logging bridges to **span the two
poles of its ecosystem** — the dominant high-throughput structured logger, and the zero-configuration option a
library can assume — and that selection criterion is worth copying rather than the specific choices. In Ruby the
poles are `SemanticLogger` (structured, JSON-first, what an operations-heavy shop already runs) and the stdlib
`Logger` (present everywhere, configured by nobody, what a small consumer gets by default). Both are reached
through the same duck type with no adapter gem at all, which is the payoff of defining the sink as a structural
subset of the `Logger` surface rather than as a nominal interface. Applying the same rule to tracing gives the
opposite count — **one** shape rather than two — for the reason the next paragraph gives, and the asymmetry is the
rule working rather than an inconsistency in it: two poles where the ecosystem has two, one where it has one.

**Tracing** (**OBS-21**–**OBS-27**) is a structural subset of the `Tracer`/`Span` shape of `opentelemetry-api`
(P14) — Ruby's tracing ecosystem has converged there, and that gem is explicitly designed to be safe for libraries
to depend on. Core still depends on nothing: an application already running OpenTelemetry gets spans with no
adapter code, one running nothing gets **OBS-25**'s frozen no-op tracer, no-op span with cached scope and
all-invalid sentinels. `dexpace-instrumentation-otel` wires richer semantics and is the one adapter permitted
presence-gated activation (§3.6). **OBS-31**'s meter has the same shape: a no-op default returning shared
instrument singletons, with no metrics runtime pulled into core.

**The correlation bundle ships in core, minimal but complete.** **CTX-14** requires that "each context MUST carry a
correlation/instrumentation metadata bundle exposing at minimum: a trace id, a span id, trace flags, trace state, a
trace-id encoding flavor, validity and remoteness flags, an active span, and a per-operation tracer factory," and
it is tempting to defer the whole thing until an OpenTelemetry adapter exists, since that is what would populate
it. That would be the wrong call, and it is the P11 failure in reverse: deferring the *shape* means every context
type, the promotion chain of §5.4, and **CTX-4**'s call key all change when the adapter lands. Core therefore ships
`Dexpace::Instrumentation::Bundle` as a frozen `Data` with all nine members, and the untraced case is not a gap but
a well-specified value — **OBS-25**'s no-op path and **OBS-26**'s reserved sentinels between them define every
field: trace id of 32 hex zeros, span id of 16 hex zeros, trace flags `00`, empty trace state, the no-op trace-id
flavour, `valid? == false`, `remote? == false`, **OBS-25**'s shared no-op span, and **CTX-20**'s no-op per-operation
tracer factory. One frozen `Bundle::NONE` singleton is shared across every untraced call, which is what makes
**CTX-15**'s "no-op bundle shares constant sentinels across every untraced call" true and what makes **CTX-4**'s
uniqueness requirement non-trivial — the call key cannot be derived from the bundle, because every untraced call's
bundle is the same object, which is precisely why §5.4's key carries a monotonic counter. The OTel adapter later
supplies a populated `Bundle` through the same constructor; nothing in core changes when it does.

**Diagnostic context** (**OBS-10**, **OBS-23**, **OBS-24**, **ASYNC-8**–**ASYNC-12**) uses **fiber storage**
(`Fiber[:key]`, 3.2+), and the verified behaviour corrects a common assumption: `Fiber[:key]` **is** inherited by a
child fiber, by a newly created `Thread`, and by an `Enumerator`'s internal fiber, while `Thread.current[:key]` —
despite the name — is fiber-local and visible in none of them. Fiber storage is therefore the correct carrier, and
it makes **ASYNC-12**'s explicit transfer largely unnecessary at *creation* boundaries. It stays necessary at
*reuse* boundaries: a pooled worker created before the request inherits nothing relevant, so `dexpace-async-thread`
saves the worker's prior storage, installs the captured snapshot for the work's duration and restores it in an
`ensure` (**ASYNC-9**), with capture taken per task submission rather than at pool construction (**ASYNC-10**), and
an absent context capturing as empty and reinstating as a clear rather than a raise (**ASYNC-11**). **OBS-10**'s
allow-list defaults to `{trace.id, span.id}`. **Redaction** (**OBS-11**–**OBS-19**, **XCUT-19**) leans on `URI` for
userinfo and query and is hand-rolled for the fragment, because `URI` does not tokenise `key=value` pairs out of a
fragment — the same split the reference makes for the same reason (**OBS-13**); **OBS-15**'s totality is a `rescue`
returning the fixed `[malformed url]` sentinel, never a raise.

### 8.2 Configuration

**CFG-1** fixes four tiers: explicit override, environment by exact key, a system-property source by normalised
key, then the caller default. Ruby has no ambient key/value store equivalent to a `-D` flag. The port neither
fabricates one from a second `ENV` lookup under another key (P11) nor drops to three tiers: it substitutes a
**genuinely different source** for the third tier — the process-wide defaults installed by
`Dexpace.configure { |c| ... }`, the dominant Ruby idiom for exactly this concern, and in-process programmatic
state set by the application at boot rather than an environment read wearing a different name.

The ordering is preserved from **CFG-1** rather than from Ruby convention, and that is a deliberate, uncomfortable
choice. The common Ruby precedence is *call-site > `configure` > `ENV` > default*; this port uses *call-site
override > `ENV` > `configure` defaults > caller default*, because **CFG-1** is normative and a conformance test
written against it would observe the difference. It also happens to be the better ordering on the merits, which is
worth saying so the choice does not read as pure obedience: **letting a deployment's environment variable override
a default written in application code is the 12-factor property adopters actually want** — it is what makes a
timeout or a proxy adjustable in staging without a redeploy, and a `configure` block that silently beat `ENV` would
turn every such knob into a code change. The escape hatch is that tier 1 exists: an application that needs
its programmatic value to beat a deployment's environment variable passes it as an explicit per-client or per-call
override, which is the tier that *does* win. **CFG-3**'s normalised-key accessor and **CFG-4**'s raw exact-name
accessor both survive and stay distinct — the raw accessor is what lets an application set a `https.proxyHost`-style
key with its casing intact (**CFG-24**), which the normalising accessor would mangle. Consequently the proxy model
(**CFG-22**–**CFG-28**) keeps its preferred first layer too: it reads the `configure` tier first and falls back to
`HTTPS_PROXY`/`HTTP_PROXY`, preserving **CFG-24**'s precedence shape with a Ruby-native source. That is one
deviation applied twice, not two deviations.

`Dexpace.configure` yields a mutable staging object and atomically replaces a single frozen `Configuration`
reference under a `Thread::Mutex`; readers take no lock and read one reference that can never change under them
because it is frozen (**CFG-8**, **CFG-13**). Derivation is copy-on-write with the override map copied before the
mutator runs and the source seams inherited by reference (**CFG-9**). **CFG-11**'s substitutable seams are the test
story — env and property sources are injectable `->(key) { ... }` callables, so a hermetic test never mutates real
`ENV` — alongside a documented `Dexpace.reset_config!` for the process-wide slot. **CFG-5**–**CFG-7**'s never-throw
typed accessors are hand-written for the same totality reason as §6.1's date parser: the boolean accessor
recognises only case-insensitive `true`/`false` and falls back for `1`, `yes` or `on`; the duration accessor takes
ISO-8601, `<number><unit>` shorthand and a bare number as milliseconds, rejecting negatives; and every integer
parse passes base 10 explicitly for the octal reason verified in §6.1. **CFG-38** routes typed accessors through the
full layered lookup, not the override map alone, and **CFG-37**'s explicit null validation — the case the
specification flags for languages without null safety — is fail-fast argument guards.

**CFG-33**/**CFG-34**'s deep value equality is recursive structural comparison with NaN equal to NaN and `+0.0`
distinct from `-0.0` for float arrays; **CFG-34**'s further boxed-versus-primitive clause has no Ruby manifestation
and is recorded as inapplicable (§11.15) rather than emulated. **CFG-32**'s explicitly *non*-cryptographic UUID
generator and **XCUT-21**'s CSPRNG requirement stay two separate code paths, as the specification insists, even
though Ruby's `SecureRandom` lacks the blocking-entropy problem that motivated the split: keeping them separate
costs nothing and preserves the ability to substitute either independently.

### 8.3 The clock, the wait, and the prohibition

**CFG-15** requires the time seam to expose a wall clock, a monotonic elapsed counter, and a **blocking
interruptible sleep**; **RETRY-26** requires the inter-attempt wait to be cancellable and to "NOT pin an execution
carrier for its duration — a naive uninterruptible sleep that cannot be cancelled is non-conforming"; **XCUT-3**
requires the wait to abort near-immediately on cancellation, surfacing the cancellation signal rather than a
spurious timeout. These pull apart on a host with cooperative scheduling, and the specification itself separates
mechanism from intent here: "a port SHOULD preserve that non-pinning property where its runtime has an equivalent
concern, but the normative requirement is prompt cancellation, not the specific mechanism."

The resolution: `Clock#sleep(duration, cancellation:)` is **not** `Kernel#sleep`. It is a bounded wait on a
per-call `Thread::Queue` that the cancellation token pushes to on cancel, so cancellation wakes it immediately
rather than at the end of the interval. That satisfies **CFG-15** literally (it blocks the caller until the
duration elapses or the wait is interrupted) and **RETRY-26**/**XCUT-3** simultaneously: under a registered
`Fiber.scheduler` the queue pop routes through the scheduler's `block`/`unblock` hooks and unmounts the fiber, so no
carrier is pinned; with no scheduler it blocks only the calling thread, never a shared pool thread, which is the
hazard the requirement targets. `Process.clock_gettime(Process::CLOCK_MONOTONIC)` is the elapsed counter
(**CFG-16**), used only for differences; `Time.now` is the wall clock and is never used to measure elapsed time.
Both are behind the injectable seam so tests control them (**CFG-15**).

**The prohibition, stated once and enforced by lint.** `Timeout.timeout`, `Thread#raise` and `Thread#kill` are
forbidden in every gem in this repository. `Timeout.timeout` schedules an asynchronous interrupt that can land on
*any* bytecode instruction — including inside an `ensure` block that is releasing a pooled connection, or between a
socket read and the bookkeeping that records it — which is precisely how a connection pool acquires a corrupt
entry that fails a later, unrelated request. Deadlines are instead propagated as explicit values to
`open_timeout`/`read_timeout`/`write_timeout` on the sync path, where they fail at a well-defined syscall boundary
with a typed exception, and to the task's own timeout on the async path, where they interrupt only at a scheduler
checkpoint. This prohibition is the direct cause of the port's three unsatisfied MUSTs — **ASYNC-3**'s two-mode
cancellation, **ASYNC-4**'s pooled-thread interrupt-ordering handshake, and **PIPE-33**'s interrupt clause — and
they are not equivalent cases: **ASYNC-4**'s guarantee holds vacuously here, while **ASYNC-3** and **PIPE-33** have
their antecedents satisfied by `dexpace-async-thread` and are genuinely not met. §10.5 splits them and §12 lists
them. The prohibition is nonetheless the right trade: a port that adopted `Thread#raise` to satisfy three clauses
would put every `ensure` block in the repository, including the ones releasing pooled connections, at the mercy of
an interrupt landing mid-instruction — which is the failure **ASYNC-4** itself exists to prevent.

---

