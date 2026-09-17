# Logging and redaction

**As built by phase 5b, in `dexpace-core`, written against source on 2026-09-17.** This page says what
the logging half of chapter 15 gives an SDK author today: the duck-typed sink and the closed severity
set, the logger and the accumulating event with its inert twin, the one rendering rule and the byte
cap, the redactor and its policy, the diagnostic-context fold and the snapshot bridge, the containment
primitive every emission runs inside, the body preview, the HTTP logging level and its two
configuration keys, the instrumentation step on both runtimes, and the four places earlier layers now
speak through it. What each is *required* to do is
`docs/product-spec/15-instrumentation-and-observability.md` §15.1–§15.4 and §15.9; how the design maps
it to Ruby is `docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.1; the per-requirement
proof is `docs/work/mvp/phase5/phase5b/2026-09-09-phase5b-logging-and-redaction-checklist.md`.
Signatures live in `gems/dexpace-core/sig/dexpace/instrumentation/`, and this page does not restate
them. Every example below was run against the built code on 4.0.6 and 3.2.11 and printed the same on
both, with three differences each stated where it appears: a `Hash#inspect` on the floor spells
`{"k"=>"v"}` where 4.0.6 spells `{"k" => "v"}`, a `Set#inspect` on the floor spells `#<Set: {"a"}>`
where 4.0.6 spells `Set["a"]`, and the floor retains a nil-valued diagnostic key where 3.3 and later
remove it.

**Core never requires `logger`, and nothing here is the stdlib `Logger`.** The sink is a duck type —
the four writers `#debug`/`#info`/`#warn`/`#error`, each taking an optional message and an optional
block, and their four predicates — of which the stdlib `Logger` happens to be a structural superset, so
a host passes one in and core declares no dependency on it (the bundled-gem rule in `CLAUDE.md`;
`SEAM-1`). The facade is `Dexpace::Instrumentation::Logger`, §8.1's name, and every reference to it from
outside `module Instrumentation` is written qualified, because a bare `Logger` there is Ruby's.

## The sink and the severity set: `_Sink`, `NULL_SINK`, `Severity`

`Severity` is a frozen `Data` closed at four, each carrying the sink method it writes to and the
predicate that says whether it is enabled — `OBS-2`'s mapping as data, so a fifth level cannot arrive
by accident and the sink call is one `public_send`. `.of` resolves a name to the constant by identity;
`.new` and `.[]` are private and `#with` refuses, the same shape as `Pipeline::Stage`.

```ruby
I = Dexpace::Instrumentation
I::Severity::ALL.map(&:name)                                   # => [:error, :warning, :info, :verbose]
I::Severity::VERBOSE.sink_method                               # => :debug
I::Severity::VERBOSE.sink_predicate                            # => :debug?
I::Severity.of(:warning).equal?(I::Severity::WARNING)          # => true
I::Severity::INFO.with(name: :fatal)                           # raises Dexpace::InvalidArgumentError
```

`NULL_SINK` is the default sink: a frozen instance of a private class whose predicates answer `false`
and whose writers discard, so a logger built with no sink is a logger whose every event is the inert
one below. The RBS interface `_Sink` is what a host's object must satisfy; `Logger.build` checks all
eight methods at construction and names the first one missing.

## The logger and the event: `Logger`, `Event`, `Event::INERT`

A sink is any object with those eight methods. This page's is an `Array` collector with a threshold,
and the same class is used throughout:

```ruby
class ArraySink
  attr_reader :entries
  def initialize(threshold = :debug) = (@entries = []; @threshold = threshold)
  %i[debug info warn error].each_with_index do |name, rank|
    define_method(name) { |message = nil, &block| @entries << [name, block ? block.call : message] }
    define_method(:"#{name}?") { rank >= %i[debug info warn error].index(@threshold) }
  end
end

sink = ArraySink.new(:info)
logger = I::Logger.build(sink: sink, context: { "service" => "pets", "event" => "ambient" })
logger.enabled?(:verbose)                                      # => false
logger.enabled?(:info)                                         # => true
logger.event(:verbose).equal?(I::Event::INERT)                 # => true
logger.event(:verbose).field(:k, 1).event(:x).cause(nil).emit  # => nil
logger.context.frozen?                                         # => true
logger.sink.equal?(sink)                                       # => true
```

`Logger.build(sink:, context:, redactor:, diagnostic_keys:)` takes the sink, a String-keyed global
context that is copied and deep-frozen once and merged into every event by reference (`OBS-9`), the
redactor every event of this logger redacts through, and the diagnostic-context allow-list (below).
`Logger::NULL` is the one built with every default. `#event(severity)` makes the enabled decision
**once** — `sink.public_send(severity.sink_predicate)` — and for a disabled severity returns the shared
`Event::INERT`, a frozen instance of a private subclass whose four methods return `self` or `nil` and
touch no state (`OBS-1`). The chain above is measured at exactly zero allocations per call in the
suite, so a disabled level costs a predicate and nothing else, and the `assert_same` on the qualified
constant is the form `dexpace-conformance` restates.

An enabled event accumulates and emits once:

```ruby
logger.event(:info)
      .event("pet.fetched")
      .field(I::Keys::URL_FULL, "https://alice:s3cret@api.example.test/pets?api-version=2&token=abc#x=1")
      .field("http.request.header.authorization", "Bearer sk-live-1")
      .field("http.response.header.location", "//user:secret@cdn.example.test/next?cursor=SECRET")
      .field("http.response.header.content-type", "application/json")
      .field("count", 3).field("ratio", 0.5).field("nothing", nil)
      .field("tags", %w[a b]).field("error", RuntimeError.new("boom"))
      .emit
severity, record = sink.entries.last
severity                                              # => :info
record["service"]                                     # => "pets"
record["event"]                                       # => "pet.fetched"
record["url.full"]                                    # => "https://***:***@api.example.test/pets?api-version=2&token=***#x=***"
record["http.request.header.authorization"]           # => "REDACTED"
record["http.response.header.location"]               # => "//***:***@cdn.example.test/next?***"
record["http.response.header.content-type"]           # => "application/json"
record["count"]                                       # => 3
record["ratio"]                                       # => 0.5
record["nothing"]                                     # => "null"
record["tags"]                                        # => "[\"a\", \"b\"]"
record["error"]                                       # => "RuntimeError: boom"
```

Four things in that record are the layer's rules and not the sink's. **Redaction happened at
`#field`, by the field's name** (`OBS-39`, §8.1): `url.full` went through `Redactor#url`, and every
header-prefixed key through `OBS-18`'s name gate first — `Authorization` is not on the allow-list, so
its value is the fixed `REDACTED` marker (or, with `omit_disallowed_headers: true`, the key is not
stored at all), whoever wrote the field — and then, for an allow-listed name, through
`Redactor#header_value`, which redacts a URL-valued header (`Location`, `Content-Location`), userinfo
included, and passes every other value through (P5-102). A caller who writes a credential header
straight into `#field` therefore gets exactly what the step gets; the gate is keyed by the field name,
not by who called. **Rendering is one rule** (`OBS-6`): `nil` is the literal `"null"`, numerics and
booleans pass through type-preserving, an exception renders as `SimpleClassName: message`, an `Array`
or `Hash` as its bracketed `#inspect`, and anything else through `#to_s`; every path is inside a rescue
that substitutes `[unrenderable ClassName]`, reached through `Kernel#class` so even a `BasicObject` gets
a name. **The key is validated**: an empty or non-name key raises `Dexpace::InvalidArgumentError` with the
`<name> is required` message form (`OBS-3`), and a nil *value* is kept.

The cap is bytes, not characters, and the marker is ASCII (`OBS-7`):

```ruby
sink3 = ArraySink.new
l3 = I::Logger.build(sink: sink3)
l3.event(:info).field("big", "x" * 9000).emit
big = sink3.entries.last[1]["big"]
big.bytesize                                          # => 8206   (8192 + "...[truncated]")
l3.event(:info).field("euro", "€" * 4000).emit
euro = sink3.entries.last[1]["euro"]
euro.bytesize                                         # => 8204   (8190 + the marker: the 2,731st € was cut)
euro.valid_encoding?                                  # => true   (scrubbed after the byte slice)
euro.count("€")                                       # => 2730
l3.event(:info).field("hostile", BasicObject.new).emit
sink3.entries.last[1]["hostile"]                      # => "[unrenderable BasicObject]"
l3.event(:info).field("anon", Class.new(StandardError).new("anon")).emit
sink3.entries.last[1]["anon"]                         # => "Class: anon"   (an anonymous class has no name)
```

### Merge order, the tag, and the once-per-logger warning

`#emit` builds one record in one order — the folded diagnostic context, then the logger's context, then
the event's fields, later winning (`OBS-5`) — writes the tag over any `event` key those supplied
(`OBS-4`), attaches the cause, renders every value, and hands the record to the sink through the
**block** form of the severity's method, so a sink that is disabled after the predicate said yes still
never renders it. A per-event field named `event` that collides with a set tag is dropped and warned
about once per logger at the sink's `#debug`, gated on `sink.debug?` before the latch is claimed, so a
disabled verbose level neither pays for nor consumes the one warning; a colliding `event` key from the
global or diagnostic context defers silently (`OBS-40`).

```ruby
Fiber[:"trace.id"] = "4bf92f3577b34da6a3ce929d0e0e4736"
Fiber[:"span.id"] = "00f067aa0ba902b7"
Fiber[:tenant] = "acme"
sink2 = ArraySink.new(:debug)
logger2 = I::Logger.build(sink: sink2, context: { "service" => "pets", "who" => "context" })
logger2.event(:info).field("who", "field").emit
sink2.entries.last[1]
# => {"trace.id" => "4bf92f3577b34da6a3ce929d0e0e4736", "span.id" => "00f067aa0ba902b7", "service" => "pets", "who" => "field"}
logger2.event(:info).event("tag").field("event", "field").emit
sink2.entries[-2]
# => [:debug, "dexpace: a per-event field named 'event' collided with the event tag and was dropped; the tag wins (OBS-40)"]
sink2.entries[-1][1]["event"]                         # => "tag"
logger2.event(:info).event("tag").field("event", "again").emit
sink2.entries.map(&:first)                            # => [:info, :debug, :info, :info]   (warned once)
```

The diagnostic context is folded per `OBS-10`: with the default allow-list, exactly `trace.id` and
`span.id`; with a list, those keys; with `diagnostic_keys: nil` — a mode, the opt-in unfiltered fold —
every key present, skipping nil values and every key under `Diagnostics::RESERVED_PREFIX`
(`"dexpace."`), which is where phase 5c keeps the live current-span object.

```ruby
I::Logger.build(sink: sink2, diagnostic_keys: nil).event(:info).emit
sink2.entries.last[1]
# => {"trace.id" => "4bf92f3577b34da6a3ce929d0e0e4736", "span.id" => "00f067aa0ba902b7", "tenant" => "acme"}
I::Logger.build(sink: sink2, diagnostic_keys: [:tenant]).event(:info).emit
sink2.entries.last[1]                                 # => {"tenant" => "acme"}
Fiber[:"trace.id"] = nil; Fiber[:"span.id"] = nil; Fiber[:tenant] = nil   # the carrier is empty again

event = logger2.event(:info).field("n", 1)
event.emit                                            # => nil
event.emit                                            # => nil   (a no-op: OBS-8)
sink2.entries.count { |_s, r| r.is_a?(Hash) && r["n"] == 1 }   # => 1
```

`OBS-8`'s once-only latch is flipped under the logger's `Thread::Mutex` and **the mutex is released
before the sink is called**. That ordering is load-bearing: the mutex is non-reentrant, and a sink that
logs through the same logger from inside its own write is a second event on the same mutex — the suite
drives exactly that sink, and holding the lock across the call is `ThreadError: deadlock; recursive
locking`.

## Redaction: `RedactionPolicy`, `Redactor`

`RedactionPolicy` is a frozen `Data` of three frozen `Set`s and a boolean, folded to lower case at
construction; `Redactor` is frozen over one policy and keeps no other state, so `Redactor::DEFAULT` is
shared across threads without a lock (`XCUT-11`). The defaults are default-deny in every clause
`XCUT-19` names: the query allow-list is exactly `{api-version}` and an empty list redacts every value
(`OBS-12`); the header allow-list is twenty-six diagnostic, non-credential names (`OBS-18`); the
URL-valued header names are `location` and `content-location` (`OBS-17`); and userinfo is redacted with
**no policy member able to reach it** (`OBS-11`) — `RedactionPolicy.members` has four entries and none
is about userinfo.

```ruby
r = I::Redactor::DEFAULT
r.url("https://alice:s3cret@h:8443/p?api-version=2&token=t&x#access_token=s")
# => "https://***:***@h:8443/p?api-version=2&token=***&x#access_token=***"
r.url("http://h:80/p?")                               # => "http://h:80/p?"     (port and empty query kept)
r.url("http://h/p#a?b=c")                             # => "http://h/p#a?b=***" (no query; a fragment pair)
r.url("http://h/p?a=1&")                              # => "http://h/p?a=***"   (the trailing empty pair dropped)
r.url("mailto:a@b.c")                                 # => "mailto:a@b.c"       (opaque: nothing to redact)
r.url("mailto:a@b.c?subject=SECRET")                  # => "mailto:a@b.c?subject=***" (its query-shaped tail)
r.url("not a url at all")                             # => "[malformed url]"
r.url(nil)                                            # => "[malformed url]"
r.url("https://h/x?%FF=secret")                       # => "https://h/x?%FF=***" (an undecodable name)
r.url("https://h/x?%zz=secret&api-version=1")         # => "https://h/x?%zz=***&api-version=1"

r.header_value("Location", "/cb?code=SECRET")         # => "/cb?***"
r.header_value("Location", "/cb?")                    # => "/cb?***"            (it carried a query)
r.header_value("Location", "/static/path")            # => "/static/path"
r.header_value("Location", "https://h/x?t=1")         # => "https://h/x?t=***"
r.header_value("Location", "//user:secret@h/x")       # => "//***:***@h/x"      (relative, with an authority)
r.header_value("Location", "bad path?secret=1")       # => "bad path?***"       (unparseable: surgery)
r.header_value("Location", "http://user:pw@h/p x")    # => "http://***:***@h/p x"
r.header_value("Content-Type", "text/html?x=1")       # => "text/html?x=1"      (not a URL header)
r.header_value("Location", nil)                       # => ""
r.header_name?("Content-Type")                        # => true
r.header_name?("Authorization")                       # => false

I::RedactionPolicy::DEFAULT.query_allow_list          # => Set["api-version"]    (#<Set: {"api-version"}> on 3.2)
I::RedactionPolicy::DEFAULT.url_header_names          # => Set["location", "content-location"]
I::RedactionPolicy::DEFAULT.header_allow_list.size    # => 26
I::RedactionPolicy::DEFAULT.omit_disallowed_headers   # => false
strict = I::Redactor.build(policy: I::RedactionPolicy.build(query_allow_list: [], header_allow_list: [:Date]))
strict.url("https://h/p?api-version=2")               # => "https://h/p?api-version=***"
strict.header_name?("date")                           # => true
strict.header_name?("content-type")                   # => false
```

**`#url` rebuilds from `URI::RFC3986_PARSER.split`, never through `URI#to_s`.** `URI#to_s` drops a
default port — `http://h:80/` renders as `http://h/` on every supported Ruby — and `OBS-14` requires
scheme, host, port and path written back unchanged, so the redactor reassembles the nine raw components
and writes back only what was present: a present-but-empty query keeps its `?`, an absent one writes
nothing, and an opaque URI round-trips untouched because no component is ever assigned (P5-91, P5-27)
— except a query-shaped tail, which the parser folds into the opaque component and which takes the
query rule (P5-101). Each `name=value` pair keeps its name — decoded, scrubbed and folded with a bare
`downcase` — and gets `***` unless the name is allow-listed; a name that cannot be decoded (`%FF`, or a
`%zz` the decoder rejects outright) is redacted rather than raised on or sentinelled, and a bare token
with no `=` is kept. The fragment is tokenised by hand on `&`, because `URI` does not tokenise one
(`OBS-13`). `#url` is total: any `StandardError` — not only `URI::Error`, because a policy read can
raise too — yields the `"[malformed url]"` sentinel (`OBS-15`). `#header_value` never returns that
sentinel and never returns nil: an absolute value is redacted like a request URL, a relative one keeps
its path — and its authority, if it has one — and gets `?***` iff it carried a query *or* a fragment
(`OBS-16`), and an unparseable one takes string surgery on the raw value; on every one of those routes
a userinfo is `***:***@`, which is where `OBS-11`'s "unconditionally" overrules `OBS-16`'s "returned
verbatim" for the one input both reach (P5-100).

## The diagnostic-context bridge: `Diagnostics.capture`, `.with`, `.folded`

`Diagnostics` is the file phase 5c created for its two key names; this phase gives it the fold the event
uses, the snapshot for an async settlement (`OBS-24`), and the reserved prefix.

```ruby
D = I::Diagnostics
D::DEFAULT_KEYS                                       # => [:"trace.id", :"span.id"]
D::RESERVED_PREFIX                                    # => "dexpace."
Fiber[:"trace.id"] = "t1"
Fiber[:tenant] = "acme"
Fiber[:"dexpace.current_span"] = :private
Fiber[:cleared] = nil
snap = D.capture
snap                                                  # => {"trace.id": "t1", tenant: "acme", "dexpace.current_span": :private}
snap.frozen?                                          # => true
D.folded(D::DEFAULT_KEYS)                             # => {"trace.id" => "t1"}
D.folded(nil)                                         # => {"trace.id" => "t1", "tenant" => "acme"}
D.folded([:tenant, :missing])                         # => {"tenant" => "acme"}
Fiber[:"trace.id"] = nil; Fiber[:tenant] = nil; Fiber[:"dexpace.current_span"] = nil

Thread.new do
  Fiber[:tenant] = "other"
  inside = D.with(snap) { [Fiber[:"trace.id"], Fiber[:tenant]] }
  [inside, Fiber[:"trace.id"], Fiber[:tenant]]
end.value                                             # => [["t1", "acme"], nil, "other"]
Fiber.current.storage.key?(:cleared)                  # => false on 3.3 and later; true on 3.2
```

`.capture` is one read of `Fiber.current.storage` — already a fresh copy — with nil-valued keys
dropped and the result frozen. The compaction is the floor's doing: on 3.2, `Fiber[:k] = nil` leaves
the key behind with a nil value (the last line), so an uncompacted snapshot would carry every key ever
set and cleared, and `OBS-10` says a nil-valued key is not diagnostic context anyway (P5-97). The
snapshot carries the reserved slot too, because the bridge moves the whole context and the fold is what
filters. `.with(snapshot)` installs per key, yields, and restores per key over the union of the prior and
snapshot key sets in an `ensure`, through `Fiber[]=` alone — never `Fiber#storage=`, which warns on every
call. On 3.3 and later the restore is exact; on the floor a key the snapshot introduced stays present with
a nil value, which `Fiber[]` reads as `nil` and the fold skips (P5-72 applied to `OBS-24`). The snapshot
is anything answering `#each` and `#keys` (`_DiagnosticSnapshot`). The bridge merges over the executing
fiber's context rather than replacing it — the thread above still sees its own `tenant` afterwards —
which is why phase 8b's pooled worker must start with an empty carrier.

## Containment: `Instrumentation.contain`, `.diagnostic`

Every log emission in core runs inside `contain`, and no tracer, scope or meter call does (`OBS-20`).
`contain` swallows the block's value, reports a `StandardError` as one WARNING event under the
`http.instrumentation.*` name it was given with the error as its cause, and swallows a failure of *that*
report with no second attempt — a sink that raises on every call, predicates included, still yields
`nil`. Anything that is not a `StandardError` propagates. `diagnostic` is the contained WARNING event the
three wirings below and phase 8b's shutdown event share: an event name, an optional cause and an optional
`Keys::MESSAGE`.

```ruby
sink4 = ArraySink.new(:debug)
l4 = I::Logger.build(sink: sink4)
I.contain(l4, event: I::Events::INSTRUMENTATION_LOG) { raise "boom" }             # => nil
sink4.entries.last   # => [:warn, {"event" => "http.instrumentation.log", "cause" => "RuntimeError: boom"}]
I.contain(l4, event: I::Events::INSTRUMENTATION_LOG) { 42 }                       # => nil
I.diagnostic(l4, event: I::Events::INSTRUMENTATION_CONFIG, message: "bad port")   # => nil
sink4.entries.last   # => [:warn, {"message" => "bad port", "event" => "http.instrumentation.config"}]
I.contain(l4, event: I::Events::INSTRUMENTATION_LOG) { raise NotImplementedError } # propagates
I::Events.constants.sort
# => [:HTTP_REQUEST, :HTTP_RESPONSE, :INSTRUMENTATION_CLOSE, :INSTRUMENTATION_CONFIG,
#     :INSTRUMENTATION_HOOK, :INSTRUMENTATION_LOG, :INSTRUMENTATION_PREFIX, :INSTRUMENTATION_SHUTDOWN]
I::Keys.constants.size                                                            # => 16
```

`Keys` and `Events` are the whole field and event vocabulary (`OBS-39`): sixteen frozen `String`
constants and eight, every one a row in the surface manifest, so a seventeenth cannot arrive unnoticed.
`INSTRUMENTATION_SHUTDOWN` is the name phase 8b's executor will emit under; nothing emits it yet.

## Body previews: `Preview.render`

`OBS-38`: a captured body renders as text when its media type is `text/*`, a known text subtype (`json`,
`xml`, `x-www-form-urlencoded`, …) or carries a `+json`/`+xml` suffix, decoded by phase 3b's recipe —
retag with the declared charset, then transcode to UTF-8 with replacement — and as a fixed marker
otherwise, an absent media type included. It never raises and never mutates its input.

```ruby
MT = Dexpace::MediaType
I::Preview.render("caf\xE9".b, media_type: MT.parse("text/plain; charset=iso-8859-1"))  # => "café"
I::Preview.render("\x89PNG".b, media_type: MT.parse("image/png"))                        # => "[binary 4 bytes captured]"
I::Preview.render("{}".b, media_type: MT.parse("application/problem+json"))              # => "{}"
I::Preview.render("\xE2\x82".b, media_type: MT.parse("text/plain"))                      # => "�"  (a cut multibyte char)
I::Preview.render("x".b, media_type: nil)                                                # => "[binary 1 bytes captured]"
```

The two-step decode is deliberate: §3.1's one-step form, `bytes.encode("UTF-8", …)` from BINARY,
renders the first case as `"caf�"`, and the suite runs that substitution red.

## The level and its keys: `HTTPLogging`, `LOG_LEVEL`, `LOG_PREVIEW_BYTES`

`HTTPLogging` is a frozen `Data` closed at three — `NONE`, `HEADERS`, `BODY` — with `DEFAULT = NONE`
(`OBS-34`, `XCUT-19`(e)) and one comparison, `#at_least?`. `.parse` is whitespace-trimmed and
case-insensitive and falls back to its default for anything unrecognised (`OBS-35`); `.resolve` is
`.parse` over `Configuration#string(key)`, so the four tiers are phase 5a's. **The key is a required
keyword with no default**: `Configuration::Keys::LOG_LEVEL` is the published name a caller passes, and
core reads it nowhere on its own. The preview cap is the same shape — the caller resolves
`Keys::LOG_PREVIEW_BYTES` and passes it — and no 8 KiB default lives in any signature.

```ruby
I::HTTPLogging::DEFAULT.equal?(I::HTTPLogging::NONE)                      # => true
I::HTTPLogging.parse("  Headers  ").equal?(I::HTTPLogging::HEADERS)       # => true
I::HTTPLogging.parse("verbose").name                                      # => :none
I::HTTPLogging.parse(nil, default: I::HTTPLogging::BODY).name             # => :body
I::HTTPLogging::BODY.at_least?(I::HTTPLogging::HEADERS)                   # => true

K = Dexpace::Configuration::Keys
env = Dexpace::Configuration::Sources.from_hash("LOG_LEVEL" => "body", "LOG_PREVIEW_BYTES" => "64")
config = Dexpace::Configuration.build(env_source: env)
I::HTTPLogging.resolve(config, key: K::LOG_LEVEL).name                    # => :body
config.integer(K::LOG_PREVIEW_BYTES, default: 8 * 1024)                   # => 64
K::LOG_PREVIEW_BYTES                                                      # => "LOG_PREVIEW_BYTES"
```

## The instrumentation step: `Step`, `AsyncStep`

`Step.build(logger:, level:, tracer_factory:, meter:, preview_bytes:, clock:)` is a pipeline step at
`Stages::LOGGING` — installed with `append(step)` and no `stage:`, driving the cursor exactly once and
never forking — that starts one span and records the two instruments on every request, and emits the
`http.request` and `http.response` events at `HEADERS` and above. The two instruments are created once in
`.build` under `Keys::INSTRUMENT_REQUEST_COUNT` and `::INSTRUMENT_REQUEST_DURATION`; the tracer and the
span are named by the request's method token, because the operation name lives on the context bundle
phase 6a wires in (P5-99). There is **one redaction policy per logging path, the logger's**: the step
takes no redactor of its own, and every header it logs is gated by name and redacted by value at
`Event#field` through the logger's redactor (P5-95, P5-102), so the step and a hand-written field get
the same answer.

```ruby
transport = lambda do |req, _options, _cancellation|
  req.body&.write_to(Dexpace::IO::Buffer.new)   # a real transport writes the request body to the wire
  headers = Dexpace::Headers.inbound_builder
  headers.add("Content-Type", "application/json")
  headers.add("Location", "/next?cursor=SECRET")
  headers.add("Set-Cookie", "session=abc")
  buffer = Dexpace::IO::Buffer.new
  buffer.write("{\"pets\":[1,2,3],\"padding\":\"" + ("S" * 80) + "\"}")
  Dexpace::Response.build(request: req, protocol: Dexpace::Protocol::HTTP_1_1, status: 200,
                          headers: headers.build,
                          body: Dexpace::Body.buffer(buffer, media_type: MT.parse("application/json")))
end

sink5 = ArraySink.new(:debug)
step = I::Step.build(logger: I::Logger.build(sink: sink5),
                     level: I::HTTPLogging.resolve(config, key: K::LOG_LEVEL),           # BODY, from above
                     preview_bytes: config.integer(K::LOG_PREVIEW_BYTES, default: 8 * 1024))  # 64
step.stage.name                                                           # => :logging
pipeline = Dexpace::Pipeline.builder(transport: transport).append(step).build

request_headers = Dexpace::Headers.builder
request_headers.add("Authorization", "Bearer sk-live-1")
request_headers.add("Accept", "application/json")
request = Dexpace::Request.build(method: "POST", url: "https://bob:pw@api.example.test/pets?api-version=2&token=t",
                                 headers: request_headers.build,
                                 body: Dexpace::Body.string("{\"name\":\"rex\"}", media_type: MT.parse("application/json")))
response = pipeline.call(request)
response.status.code                                                      # => 200
response.body.class                                                       # => Dexpace::ResponseLoggingBody
response.body_string.bytesize                                             # => 109   (every byte, through a 64-byte cap)
sink5.entries.map(&:first)                                                # => [:info, :info]
sink5.entries[0][1]
# => {"http.request.method" => "POST",
#     "url.full" => "https://***:***@api.example.test/pets?api-version=2&token=***",
#     "http.request.header.authorization" => "REDACTED",
#     "http.request.header.accept" => "application/json",
#     "http.request.body.size" => 14,
#     "event" => "http.request"}
sink5.entries[1][1]
# => {"http.response.status_code" => 200,
#     "http.response.duration_ms" => 0.40170500142266974,        (Clock#monotonic; varies)
#     "http.response.header.content-type" => "application/json",
#     "http.response.header.location" => "/next?***",
#     "http.response.header.set-cookie" => "REDACTED",
#     "http.request.body.size" => 14,
#     "http.request.body.preview" => "{\"name\":\"rex\"}",
#     "http.response.body.size" => 64,
#     "http.response.body.preview" => "{\"pets\":[1,2,3],\"padding\":\"SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS",
#     "event" => "http.response"}
```

Read the two records against the requirements. `url.full` is always the redacted URL, structurally:
the step hands the raw URL to `#field` and the field's name does the rest (`OBS-39`). The
`Authorization` and `Set-Cookie` names are outside the allow-list, so their values are the fixed
`REDACTED` marker — or omitted entirely with `RedactionPolicy.build(omit_disallowed_headers: true)`
(`OBS-18`); `Location`'s value went through the URL-value redactor (`OBS-17`). The request event carries
the *declared* size when the body knows it (`BODY-35`'s `-1` is filtered out) and no preview, because
the request body is written inside the dispatch, after the request event; the previews and the capture
sizes ride on the response event (`BODY-20`). At `BODY` the step wraps the outbound body in
`RequestLoggingBody` and the inbound one in `ResponseLoggingBody` with the one shared cap — the only two
construction sites of those phase-3b wrappers in core — and phase 3b's over-cap regime does the rest: the
caller receives every one of the 109 bytes, the preview is the first 64, and the size field is the
**capture's** 64, never the declared length (`OBS-36`, `BODY-19`, `BODY-22`, `BODY-34`). Below `BODY`
neither wrapper is constructed even when a cap is supplied — the level is the gate, the cap only its
size — and `preview_bytes:` is required at `BODY` and refused when absent, zero, negative or not an
`Integer`. A multi-valued header is one field, joined with `", "`.

At `NONE` there is no log event at all, and the span and the instruments happen regardless:

```ruby
class CountingMeter
  attr_reader :counts, :records
  def initialize = (@counts = []; @records = [])
  def create_counter(name, unit: nil, description: nil)
    counts = @counts
    Class.new { define_method(:add) { |amount, attributes: nil| counts << [name, amount] } }.new
  end
  def create_histogram(name, unit: nil, description: nil)
    records = @records
    Class.new { define_method(:record) { |amount, attributes: nil| records << [name, amount.class] } }.new
  end
end
meter = CountingMeter.new
sink6 = ArraySink.new(:debug)
quiet = I::Step.build(logger: I::Logger.build(sink: sink6), level: I::HTTPLogging::NONE, meter: meter)
Dexpace::Pipeline.builder(transport: transport).append(quiet).build.call(request)
sink6.entries                                         # => []
meter.counts                                          # => [["http.client.request.count", 1]]
meter.records                                         # => [["http.client.request.duration", Float]]
```

The asymmetry `OBS-20` prescribes is visible from outside: a raising sink cannot fail the request, a
raising meter can.

```ruby
class RaisingSink < ArraySink
  def info(_message = nil, &_block) = raise(IOError, "disk full")
end
noisy = I::Step.build(logger: I::Logger.build(sink: RaisingSink.new(:debug)), level: I::HTTPLogging::HEADERS)
Dexpace::Pipeline.builder(transport: transport).append(noisy).build.call(request).status.code   # => 200

class RaisingMeter < CountingMeter
  def create_counter(*) = Class.new { def add(*, **) = raise("metrics down") }.new
end
broken = I::Step.build(logger: I::Logger.build(sink: ArraySink.new), level: I::HTTPLogging::NONE, meter: RaisingMeter.new)
Dexpace::Pipeline.builder(transport: transport).append(broken).build.call(request)   # raises RuntimeError: metrics down
```

A failure below the step emits the response event at `ERROR` with `error.type` — the nearest *named*
class, so an anonymous error class reports its ancestor — and the throwable attached under `cause`, then
re-raises the same object:

```ruby
failing = ->(_req, _o, _c) { raise Dexpace::StreamError, "connection reset" }
sink7 = ArraySink.new(:debug)
fstep = I::Step.build(logger: I::Logger.build(sink: sink7), level: I::HTTPLogging::HEADERS)
Dexpace::Pipeline.builder(transport: failing).append(fstep).build.call(request)   # raises Dexpace::StreamError
sink7.entries.map(&:first)                            # => [:info, :error]
sink7.entries.last[1].slice("event", "error.type", "cause")
# => {"event" => "http.response", "error.type" => "Dexpace::StreamError", "cause" => "StreamError: connection reset"}
```

**`AsyncStep`** is the same step over `AsyncPipeline` (`build_async`), inheriting `.build` unchanged.
Its synchronous head opens the span, correlates it, emits the request event and drives the cursor;
the response or failure event, the span's finish and the two instruments happen in the settlement,
which may run on another thread or fiber. Two things follow from that (P5-93, P5-94). The correlation
scope is closed on the *caller's* fiber at the end of the head — `Scope#close` writes the closing
fiber's storage, and closing from the settlement would write the settler's — and the caller's diagnostic
context reaches the settlement through `Diagnostics.capture` in the head and `Diagnostics.with` around
the emission (`OBS-24`). And at `BODY` the step returns a future derived with `Future#then`, carrying the
response wrapped in `ResponseLoggingBody`, because the wrapper mirrors on the caller's read and only a
derived future can settle with a different value; below `BODY` it registers `#on_settle` and returns the
cursor's own future, so nothing in the chain is re-wrapped. A raising meter fails the settlement rather
than the head, which is `OBS-20`'s asymmetry on the async path.

## Four wirings into earlier layers

Three places that dropped or warned now also speak through a `logger:` keyword, defaulting to
`Logger::NULL`, and one phase-3b postponement lands.

```ruby
sink8 = ArraySink.new(:debug)
l8 = I::Logger.build(sink: sink8)
resource = Object.new
def resource.close = raise(IOError, "already gone")
Dexpace.close_quietly(resource, logger: l8)           # => nil
sink8.entries.last   # => [:warn, {"event" => "http.instrumentation.close", "cause" => "IOError: already gone"}]
primary = RuntimeError.new("primary")
Dexpace.close_quietly(resource, onto: primary, logger: l8)   # => nil
Dexpace.suppressed(primary).map(&:message)            # => ["already gone"]   (the trail, not the logger)
sink8.entries.size                                    # => 1

cfg9 = Dexpace::Configuration.build(env_source: Dexpace::Configuration::Sources.from_hash("HTTPS_PROXY" => "https://proxy.corp"))
Dexpace::Proxy.resolve(cfg9, logger: l8)              # => nil, after "[dexpace] proxy URL \"https://proxy.corp\" has no explicit port; …" on $stderr
sink8.entries.last
# => [:warn, {"message" => "proxy URL \"https://proxy.corp\" has no explicit port; CFG-25 forbids defaulting to 80 or 443",
#             "event" => "http.instrumentation.config"}]
```

- **`Dexpace.close_quietly(resource, onto: nil, logger: Logger::NULL)`** — the second disposal route
  phase 2 shipped as a drop: with no `onto:` the close failure becomes an `http.instrumentation.close`
  diagnostic; with `onto:` it goes to the suppressed trail and **not** to the logger. Two routes, never
  both; nil always; a resource without `#close` and a nil resource still tolerated (`CFG-21`).
- **`Hooks.notify(hooks, argument, logger: Logger::NULL)`** — a hook failure after the first is attached
  to the first as before and now also reported as an `http.instrumentation.hook` diagnostic; the first
  failure still propagates with `cause: nil`.
- **`Proxy.resolve(configuration, logger: Logger::NULL)`** — every malformed-input path still
  `Kernel#warn`s with the `[dexpace]` prefix (`CFG-24`) and now also emits an `http.instrumentation.config`
  event with the warning's text under `message` and no cause, through the one helper all of them call
  (`CFG-25`; phase 5a's P5-8 discharged).
- **The body-logging caps** — `Configuration::Keys::LOG_PREVIEW_BYTES` is the published name, the caller
  resolves it and passes it to `Step.build`, and the two wrappers are built only there and only at `BODY`
  (`BODY-34`); the `body.md` page's "nothing in core constructs either" now reads "the step does".

## What is deliberately not here

- **A header-drop verbosity policy** (`OBS-19`, SHOULD). Its subject is a transport that drops a
  caller-set header it cannot encode, and core has no transport; both halves it is built from —
  `Severity` and the once-per-logger latch — ship here, and phase 8c's async adapter is where the
  policy has a caller.
- **An async skip of the preview for an unknown-length body** (`OBS-37`, SHOULD). `AsyncStep` captures
  a preview the way the sync step does; the skip is an optimisation of nothing until an async adapter
  exists, and it is post-v1 under `docs/first-release.md`'s `OBS-32`/`OBS-37` entry.
- **The stdlib `Logger`, or any adapter for it.** The sink is a duck type it already satisfies; the
  proof that it does is `dexpace-conformance`'s (phase 8a).
- **The span named after the operation.** The step names it by the method token until phase 6a wires
  the context bundle into the pipeline; nothing here reads `RequestContext#operation_name`.
- **Any emitter of the HTTP-tracer vocabulary, and `Pipeline.standard`.** The step installs nothing
  by itself; a caller appends it. The per-attempt emitter is phase 6a's, the standard assembly phase 6b's.
- **A cop for the bare `Logger` name.** Examined and closed: the shadow is confined to
  `module Instrumentation`, where core never loads the stdlib class and the bare name can mean nothing
  else, so a watch would flag every correct reference (P5-38).
