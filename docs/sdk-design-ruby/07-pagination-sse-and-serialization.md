## 7. Pagination, SSE, and Serialization

### 7.1 Pagination

**PAGE-1**'s two consumption views over one lazy walk are two `Enumerator`s sharing one internal drive routine,
giving callers `Enumerable` for free — `first`, `take`, `.lazy` chaining — without core inventing vocabulary (P14).
**PAGE-6**'s "construction triggers zero exchanges" is free: an `Enumerator` block does not run until the consumer
first pulls. **PAGE-8**'s fresh restart per iteration is free for the item view and deliberately not offered by the
page view, which **PAGE-14** requires be single-use.

**The close-on-abandon question, and the verified answer that shapes the subsystem.** **PAGE-11** requires the item
view to eager-close each page before yielding its items; **PAGE-12** requires the page view to close the previous
page on advance and to release a fetched-but-undelivered page so a probe or early break followed by close still
frees it; **SSE-25** wants the same of a partially consumed stream. On a host whose iteration protocol has an
early-termination hook this is free. **In Ruby it is free for internal iteration and not free for external
iteration**, and the difference is not documented anywhere obvious. Verified on 3.4.10: an `Enumerator` built with
`Enumerator.new { |y| ... ensure ... }` runs its `ensure` when a consumer calls `#each` with a block and `break`s
out, because the block runs in the caller's own fiber and `break` unwinds through it — but a consumer driving the
same enumerator externally with `#next` and then abandoning it leaves the generator suspended in a hidden fiber
whose `ensure` **never runs**, even after the enumerator is dropped and `GC.start` is called twice. Garbage
collection is not a cleanup hook.

The consequence is a hard rule, and it is exactly the hidden-precondition case (P7): **resource acquisition and
release never live inside an `Enumerator` block.** The page engine owns the in-flight page and the underlying
response in its own scope with its own `ensure`, and exposes `#close` on the view; the enumerator block only reads
through a thin view. Internal iteration then gets **PAGE-11**/**PAGE-12** automatically, external iteration gets
them from an explicit `#close` that the block form (`Dexpace::Page.each { }`) makes the default. **PAGE-12**'s
one-slot look-ahead lives on the engine, not in the enumerator's closure, released by the same `#close`.
**PAGE-15**'s close-error propagation uses §5.2's suppressed helper: the first failure propagates, the second is
attached.

**PAGE-21**'s verbatim query splice is this subsystem's obvious-tool-is-wrong case. Ruby's query helpers
(`URI.decode_www_form`, `CGI.parse`, any re-render through `URI::Generic#query=`) round-trip the whole query
through their own canonical encoding, re-encoding everything and using `+` for space — contrary to **PAGE-21**'s
byte-for-byte preservation of untargeted parameters and **PAGE-22**'s RFC 3986 semantics with a literal `+` as
data. The rewriter tokenises the raw query substring by hand and splices only the targeted value; **PAGE-23**'s
replace-first/append/remove and **PAGE-24**'s preservation of every non-query component follow from operating on
the substring rather than a parsed model.

The async engine (**PAGE-25**–**PAGE-33**) drives fetch/parse/deliver/re-arm through the pivot's `#on_settle`
without blocking a thread, with page-granular cancellation (**PAGE-26**), exactly-once response close across the
drain, drop and parse-failure paths (**PAGE-27**), and the original cause surfaced unwrapped (**PAGE-28**,
**ASYNC-13**). **PAGE-31**'s trampoline is the same iterative pump as **RETRY-30**, and the specification's own
latitude applies — "A port on a runtime without deep-recursion risk MAY satisfy the intent with its native loop
model but MUST NOT recurse per page" — so the loop is a `while`. **PAGE-29**'s single-walk, in-order delivery
defaults to inline on the settling thread with an executor mode for blocking consumers.

### 7.2 Server-Sent Events

Ruby ships no SSE client, so there is no native implementation to argue against; the WHATWG line and field grammar
(**SSE-1**–**SSE-15**) is a small synchronous state machine over §3.1's line-reading primitive — which is exactly
why that primitive was hand-written rather than delegated to `IO#gets`, since **SSE-2** requires LF, CR and CRLF
all recognised with a lone CR terminating alone and **SSE-14** requires an unterminated final line returned as
content. **SSE-12**'s single leading BOM is consumed through a non-consuming lookahead (§3.1's peek), so a
mid-stream BOM survives as data. **SSE-11**'s "The representable maximum is runtime-specific (signed 64-bit ms in
the reference); a port MUST pick a documented cap and reject beyond it rather than wrap" is spec-sanctioned
latitude, and it needs exercising because Ruby integers are arbitrary-precision and cannot overflow: the port
documents a cap of 2^31−1 milliseconds and ignores any larger value, which preserves the requirement's observable
behaviour (an absurd `retry` is ignored rather than honoured) on a host where the stated failure mode is
unreachable. **SSE-19**'s optional line-length cap is implemented with a documented default, because an unbounded
line from a hostile server is an unbounded allocation.

**The parsed event is a value, and delivery is pull-based.** `Dexpace::SSE::Event` is a `Data` over the five fields
— id, event, data, comment, retry — which gives **SSE-21**'s structural equality, hash over all five, and stable
string form for free (§4). **SSE-20**'s defensive copy is not free and is the one clause to get right: the event
holds a **duplicated and frozen** data list, so neither the list the parser was accumulating into nor a caller's
later mutation can reach inside a constructed event, and `#with` copies the list again rather than sharing it —
`Data#with` copies the struct, not its members, so sharing is the default and copying is the deliberate act.
**SSE-22**'s empty predicate is true only when all five fields are unset, which makes a comment-only keep-alive
report *non-empty*, since a comment counts as content. And **SSE-39** requires delivery to be "pull-based
(demand-driven) with no eager read-ahead: the parser advances the byte source only when the consumer requests the
next event, so a blocking source read is the backpressure mechanism and no unbounded internal event buffer
accumulates." That falls out of the design rather than being added to it: the parser is a synchronous state machine
reading through §3.1's `BufferedSource.over`, which pulls a chunk only when asked, so backpressure is the source
read blocking and there is no queue between parser and consumer to grow. It is asserted by a test that drives one
event and then checks the underlying source's read count, because "no read-ahead" is the kind of property an
optimisation quietly breaks.

**The convenience view is lazy, single-pass, and single-use** (**SSE-40**). The `Enumerable` view over a raw source
that the streaming facade below exposes *is* what **SSE-40** describes, not something extra: it is lazy and
single-pass, it propagates a read exception to the
consumer at the offending pull rather than buffering it, and it **reuses one reader instance** so per-stream state
— the consumed BOM of **SSE-12**, the current retry value, the last event id — is preserved across pulls instead of
being re-derived per view. Its second clause is the one needing an explicit guard: a view MUST NOT be taken twice
over the same source, because a second view would resume mid-stream and silently deliver a partial event. The
facade latches a `@viewed` flag on first call and raises on a second, which is the same single-use treatment
**PAGE-14** gets on the page view. This is a **SHOULD** the port implements, not a deferral.

The streaming facade (**SSE-23**–**SSE-32**) reuses §7.1's lifetime mechanism verbatim, deliberately, so one
cleanup story covers both subsystems: the response is owned by the facade in its own scope, closed exactly once
across all four termination paths (clean end of stream, explicit close, early abandon, mid-stream failure), with
the closed-state guard a `Thread::Mutex`-protected flag so **SSE-31**'s cross-thread close is well defined. The
sync/async asymmetry in **SSE-30** — a release failure on the automatic terminal path is swallowed and reported out
of band, while a failure on an *explicit* close propagates — is two call sites into one close-once helper, not two
closes. **SSE-38**'s prohibitions (no auto-reconnect, no persisted last-event-id, no reconnect header) are
satisfied by omission and asserted by test, since the temptation to add them is real. **SSE-37**'s hard boundary —
core's SSE layer has zero serde dependency — is checked mechanically by §9.2's require audit, not by review.

### 7.3 Serialization: class-object-as-witness

**SERDE-5**–**SERDE-8** defend against generic erasure: a decoder given an erased parametric type cannot recover
the element type, so the reference forces callers through a reflectively reconstructed runtime type token and
**SERDE-8** rejects a token with no type argument or an unresolved variable. The porter's first job is to
**classify the host's erasure precisely rather than assume it matches the reference's.** Ruby erases nothing —
every object carries its class — so the reflective trick is unnecessary. But Ruby also *reifies* nothing about a
container: an `Array` is never an `Array` of anything, and `JSON.parse` returns `Hash`es and `Array`s carrying no
target-type information. The requirement is therefore not vacuous, and its failure mode is *worse* than on the
reference platform: instead of a cast error at the first field access, the caller silently receives a `Hash` where
a model was expected and finds out several frames later as a `NoMethodError` with no useful context.

The answer is not to recover a type but to require the caller to supply a runtime value that already carries it.
**A witness is any object responding to `.dexpace_load(parsed, ctx)`**, which a model class implements as a class
method returning an instance; the inverse `#dexpace_dump` returns a structure of codec-native values. Parametric
targets (**SERDE-6**) are covered by **combinators that are themselves witnesses**, supplied by core —
`Dexpace::Serde::List.of(Pet)`, `Map.of(String, Pet)`, `Nullable.of(Pet)`, `Tristate.of(String)` — each built by
value from a concrete element witness, so a parametric target is stated once, as data, with no reflective
reconstruction anywhere.

Is that at least as strong as a reflective type token (P9)? Stronger on two counts, weaker on one, and the third
must be said. Stronger: a reflective token can be built for a type with no decoding behaviour at all, so the
reference must resolve it against the codec's binder at decode time and can fail deep inside a parse, whereas
`Dexpace::Serde.witness!(w)` fails at witness construction if `w` does not respond to `.dexpace_load`. Stronger:
**SERDE-8**'s "unresolved type variable" state is unreachable, because a combinator cannot be constructed without a
concrete element witness — there is no partially-resolved token to reject. Weaker: a host with a compiler refuses
the call site outright, whereas Ruby can only fail fast at run time, with RBS and Steep as a gate rather than a
guarantee (§9). The port declares the witness's static shape in RBS so Steep checks call sites, and claims no more.

**Where the witness is cashed in: the lazy typed-response wrapper.** **HTTP-44** requires a lazy typed-response
wrapper to "expose raw status/headers/protocol/reason/request WITHOUT consuming the body", and to "parse the typed
value at most once on first access, memoizing the outcome so every later access returns the same value or re-throws
the same failure without re-running the handler or re-reading the single-use body. Both a null success and a thrown
failure MUST be memoized." `Dexpace::TypedResponse` therefore forwards those five raw accessors straight to the
`Response` it wraps and touches the body only when the typed value is first asked for, with the witness above as
the handler. The null-success clause is where the obvious Ruby idiom is wrong (P13): `@value ||= load` re-runs the
handler on every access for a witness that legitimately decodes to `nil`, and the second run reads a single-use
body that is already consumed. The memo is therefore an explicit `@state` — `:unstarted`, `:running`, `:done` —
with the outcome held in `@value` or `@error` and never inferred from `@value` being nil; a memoized failure is
re-raised as the same exception object rather than re-derived, so its `#cause` and its suppressed trail (§5.2)
survive every later access.

**HTTP-45** adds that concurrent first accesses "MUST be serialized so the handler runs exactly once, using a lock
that cooperates with lightweight/virtual-thread schedulers rather than an intrinsic monitor that pins the carrier
across the parse." That is §3.1's **BODY-22** shape reused unchanged, for the reason given there: the
`Thread::Mutex` is held only across the `@state` flip and never across the parse, because Ruby's `Mutex` is
per-fiber-owned and non-reentrant, so a lock held across the suspension point inside a parse deadlocks two fibers
of one thread. Whoever flips `:unstarted` to `:running` runs the handler outside the lock; a caller arriving
mid-parse waits on a `Thread::ConditionVariable` over the same mutex, which the fiber scheduler hooks, so it
unmounts its fiber rather than pinning the thread — the non-pinning clause satisfied by the primitive's own
scheduler awareness rather than by a bespoke lock.

**Tristate** (**SERDE-14**–**SERDE-20**) is three frozen singletons and one wrapper — `Tristate::ABSENT`,
`Tristate::NULL`, `Tristate::Present = Data.define(:value)` — with `Present.new(nil)` rejected at construction so
the illegal fourth state cannot be built through the public API. The two sentinels override `#to_s` and `#inspect`
to return `"Absent"` and `"Null"` (**SERDE-30**), which costs two lines and is worth them: Ruby's default `#inspect`
for a singleton object renders its object id, so a log line or a test failure comparing tristates would otherwise
differ between runs and be unreadable in both. Ruby's decode side is *easier* than a key-oriented
codec's, and the asymmetry **SERDE-17** documents does not bite: `JSON.parse` yields an ordinary `Hash` and
`hash.key?("x")` distinguishes an absent key from a present null directly, so the witness decides per key with full
knowledge of the enclosing model's shape (**SERDE-16**). Encoding is equally direct — `#dexpace_dump` builds the
`Hash` and simply omits Absent keys before `JSON.generate` — so **SERDE-15** needs no per-key serializer hook at
all, **SERDE-19**'s default wiring is structural rather than registered, and **SERDE-20**'s top-level and
array-element degradation is a three-line branch in the combinator.

Three closing notes. **SERDE-21**/**SERDE-22**'s strict coercion policy is satisfied *by the codec doing nothing*:
`JSON.parse` performs no coercion, so `"5"` never silently becomes `5`; the strictness burden moves into the
witness, where each field asserts its expected class and raises a `DeserializationError` naming the target type on
mismatch — which is also how **SERDE-13** is enforced. **SERDE-26**'s "private copy of the codec engine" is close
to vacuous for a stateless `JSON` module and is satisfied by holding configuration in a frozen options hash owned
by the `Serde` instance; the requirement's own fallback clause covers this and the behaviour is documented rather
than silent. **SERDE-9**–**SERDE-12**'s failure model is a `Dexpace::Serde::Error` root with `SerializationError`
and `DeserializationError` subtypes, adapters catching the backing library's exceptions and re-raising inside the
`rescue` so Ruby sets `#cause` automatically, and a genuine stream `IOError` propagating unwrapped (**SERDE-12**)
rather than being reclassified — which is also the failure half of **SEAM-20** and **SEAM-21** (§3.4), satisfied
here once rather than at each of the four encode profiles.

---

