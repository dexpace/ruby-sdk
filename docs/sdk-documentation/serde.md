# Serialization

**As built by phase 7a, in `dexpace-core` and `dexpace-serde-json`, written against source on
2026-09-20.** This page says what chapter 14 gives an SDK author today: the witness protocol design
§10.14 substituted for the reference's reflective type token — one predicate pair, one decode context,
four combinators and three scalar witnesses — the `Tristate` three-state PATCH type, the native-form
encode walk that makes tri-state PATCH structural, `Body.serialized`, the two response handlers phase
3b's `TypedResponse` was built to take, and the JSON codec that fills `dexpace-serde-json` and declares
the `json >= 2.19.9` floor. What each is *required* to do is `docs/product-spec/14-serialization-serde.md`
(`SERDE-1`–`SERDE-30`); how the design maps it to Ruby is
`docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.4 and
`docs/sdk-design-ruby/07-pagination-sse-and-serialization.md` §7.3, read together with entries 12, 13 and
14 of `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`; the per-requirement
proof is `docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization-checklist.md`. Signatures live in
`gems/dexpace-core/sig/dexpace/serde/` and `gems/dexpace-serde-json/sig/dexpace/serde/json/`, and this
page does not restate them. Every example below was run against the built code on 4.0.6 and 3.2.11 and
printed the same on both (the one difference is Ruby 3.4's `Hash#inspect` spelling, so the examples
print strings and arrays). `S` is `Dexpace::Serde`, `T` is `Dexpace::Serde::Tristate`, `CODEC` is
`Dexpace::Serde::JSON.default`, `ctx` is `S::DecodeContext.root` and `src(text)` is
`Dexpace::IO::BufferedSource.of_bytes(text.b)` throughout; `Pet` and `PetPatch` are the two model
classes under *The witness protocol*.

**Two gems, one seam.** The codec seam — six methods, `.conforms?`, the registry — is phase 2's, in core.
Everything on this page that is codec-agnostic (the protocol, the context, the combinators, `Tristate`,
`Native`, `Instant`, the two handlers, `Body.serialized`) is core's; the codec itself is the adapter's.
`Dexpace::Serde::JSON` appears in no core file, signature or test, and a core test proves it
(`gems/dexpace-core/test/dexpace/serde/no_concrete_codec_test.rb`, `SEAM-2`).

## The witness protocol

A **witness** is any object answering `.dexpace_load(parsed, ctx)`: a model **class** implementing it
as a class method, or a combinator **instance** implementing it as an instance method — one
`respond_to?` predicate covers both, never a nominal test (`SERDE-5`, `SERDE-7`). The encode side is
`#dexpace_dump`, a zero-argument instance method returning the value's codec-native form; it takes no
context, because Ruby erases nothing about an object's class and reifies nothing about a container's
element type, which is the asymmetry §7.3 argues. The two method names are public frozen Symbols so a
code generator emits against a name this repository could rename.

```ruby
class Pet
  attr_reader :id, :name, :tags

  def self.dexpace_load(parsed, ctx)
    h = ctx.object!(parsed)
    new(id: ctx.integer!(h["id"], key: "id"),
        name: ctx.string!(h["name"], key: "name"),
        tags: S::List.of(String).dexpace_load(h["tags"], ctx.at("tags")))
  end

  def initialize(id:, name:, tags:) = (@id, @name, @tags = id, name, tags)
  def dexpace_dump = { "id" => @id, "name" => @name, "tags" => @tags }
end

class PetPatch
  def self.dexpace_load(parsed, ctx)
    h = ctx.object!(parsed)
    new(name: ctx.string!(h["name"], key: "name"),
        nick: T.of(String).dexpace_load_field(h, "nick", ctx))
  end

  attr_reader :name, :nick
  def initialize(name:, nick:) = (@name, @nick = name, nick)
  def dexpace_dump = { "name" => @name, "nick" => @nick }
end

S.witness?(Pet)                              # => true
S.witness?(S::List.of(Pet))                  # => true
S.witness?(->(parsed, ctx) { parsed })       # => false
S.witness!(nil)
# => Dexpace::InvalidArgumentError: a witness must respond to .dexpace_load(parsed, ctx); NilClass does not
[S::WITNESS_METHOD, S::DUMP_METHOD]          # => [:dexpace_load, :dexpace_dump]
```

A `#call`-shaped object is deliberately **not** a witness: `SERDE-5` requires an explicit runtime type
witness and `SERDE-8` requires construction to fail fast without one, and a `#call` fallback would make
every lambda a witness and both MUSTs unenforceable. The set of witnesses is **open**: a caller writes a
`Set` witness or a discriminated-union witness in two lines, with no registration and no core change.
`SERDE-23`'s tolerant decode falls out of the shape — a witness reads the keys it declares and never
enumerates the object, so an unknown field is ignored with nothing written.

## The decode context: `DecodeContext`

`ctx` is `Dexpace::Serde::DecodeContext`, a frozen `Data` carrying the path from the document root
(Strings for keys, Integers for indices, rendered by `#pointer` as an RFC 6901 pointer with `~0`/`~1`
escaping) and the decode's target type **name**, and holding the **one** raise site for a shape failure —
`Model.required!`'s discipline applied to the decode side, so `SERDE-13`'s "naming the target type" and
`SERDE-21`'s nine refusals are properties of one method rather than of every witness anyone writes. It is
emphatically not phase 4a's `Dexpace::Context`: a decode happens with no pipeline in sight.

```ruby
ctx = S::DecodeContext.root(target: Pet)
ctx.target                                   # => "Pet"
ctx.at("tags").at(0).pointer                 # => "/tags/0"
ctx.float!(1)                                # => 1.0   (SERDE-22: the one permitted widening)
ctx.string!("")                              # => ""    (SERDE-22: an empty string is a String)
ctx.integer!("5", key: "id")
# => Dexpace::Serde::DeserializationError: expected Integer at /id, got String
ctx.object!(nil)
# => Dexpace::Serde::DeserializationError: expected Pet (Hash) at /, got NilClass
```

The eight `!` methods — `#object!`, `#array!`, `#string!`, `#integer!`, `#float!`, `#boolean!`,
`#present!` and `#error!` — accept exactly the matching shape and refuse every cross-shape coercion
`SERDE-21` names: `"5"` never becomes `5`, `1.0` never becomes `1`, `true` never becomes `1`, `1` never
becomes `true`, `"true"` never becomes `true`, `5` never becomes `"5"`. `#float!` is the one method with
a permission — an Integer widens to a Float, which `SERDE-22` requires. `key:` appends one segment for
the message only; `#at` is what a combinator uses to descend. The **root frame names the target**
(`expected Pet (Hash) at /`), because a witness reached with a wire null calls `ctx.object!(nil)` and
knows only the shape it wanted; a nested frame's target *is* its expected shape, so it renders the plain
form (`expected String at /tags/0, got Integer`). The root's target is set by the codec's `#load` from
the witness — never by a nil check inside `#load`, because `SERDE-20`'s `Tristate.of` and `Nullable.of`
legitimately want a top-level null.

## The combinators: `List`, `Map`, `Nullable`

Each is a frozen `Data` built **by value** from a concrete element witness, and each *is* a witness, so
they nest (`SERDE-6`). Construction runs every argument through the scalar table and
`Dexpace::Serde.witness!`, so `List.of(nil)`, `List.of(Object.new)` and `List.of(::Time)` all raise at
**construction** with an actionable message — `SERDE-8`'s fail-fast, earlier than the reference's
binder-resolution failure; its "unresolved type variable" state is unreachable, because a combinator
cannot exist without a concrete element. The ergonomic spellings §7.3 uses work verbatim: `String`,
`Integer` and `Float` resolve through a private table to three scalar witnesses, and booleans are the
named witness `Dexpace::Serde::BOOLEAN`, because Ruby has no `Boolean` class to key on and
`List.of(TrueClass)` would read as a list of `true`s. `::Time` is deliberately **not** in the table — the
ISO-8601 wiring is the adapter's (design §3.4) — so a caller wanting times writes
`List.of(Dexpace::Serde::Instant)`.

```ruby
S::List.of(String).dexpace_load(%w[a b], ctx)                         # => ["a", "b"]
S::Map.of(String, Float).dexpace_load({ "x" => 1 }, ctx).to_a         # => [["x", 1.0]]
S::Nullable.of(Integer).dexpace_load(nil, ctx)                        # => nil
S::List.of(Pet) == S::List.of(Pet)                                    # => true
S::List.of(Object.new)
# => Dexpace::InvalidArgumentError: a witness must respond to .dexpace_load(parsed, ctx); Object does not
S::List.of(Pet).dexpace_load([{ "id" => 1, "name" => 2 }], ctx)
# => Dexpace::Serde::DeserializationError: expected String at /0/name, got Integer
```

`Map.of` decodes **keys** through the key witness too — for JSON always `String`, but the witness is
required rather than assumed, so a codec whose keys are not strings inherits the combinator unchanged.
Every combinator follows the phase-1 construction pattern (`.new` and `.[]` private, a validating
`.build` that `.of` and `#with` route through, structural equality) and answers a **fresh** collection,
never the parsed one.

## The three-state PATCH type: `Tristate`

`Dexpace::Serde::Tristate` is a module included by three values — `ABSENT` (the key is missing), `NULL`
(the key is present with an explicit null) and `Present` (the key carries a value) — so one type test
covers the three (`SERDE-14`). The illegal fourth state, Present-of-null, is unrepresentable on **both**
paths: `Present` validates in `#initialize`, so `.build`, the private `.new` and `.[]` all refuse nil, and
`Dexpace::Model#with` routes a derivation through `.build` on every supported Ruby — including 3.2, where
`Data#with` skips an `initialize` override.

```ruby
[T::ABSENT, T::NULL, T.present(1)].map(&:to_s)    # => ["Absent", "Null", "#<data Dexpace::Serde::Tristate::Present value=1>"]
T.present(1).value                                # => 1
T.from_nullable(nil).to_s                         # => "Null"   (SERDE-18: never Absent)
T.present(nil)
# => Dexpace::InvalidArgumentError: value is required
T.present(1).with(value: nil)
# => Dexpace::InvalidArgumentError: value is required
T::ABSENT.fold(on_absent: -> { :a }, on_null: -> { :n }, on_present: ->(v) { v })   # => :a
```

`SERDE-18`'s helpers are all there — `.absent`, `.null`, `.present(value)`, `.from_nullable(value)` (the
nullable mapper that can never yield Absent), the three predicates, `#value_or_nil` and the three-way
`#fold` — and the two sentinels print as `Absent` and `Null` rather than an object id (`SERDE-30`, taken).

**Decoding is the combinator's, and it has two entry points.** `Tristate.of(element)` is a witness whose
`#dexpace_load_field(hash, key, ctx)` reads the in-object case — the enclosing Hash answers `key?`
directly, so a missing key is Absent, a present null is Null and a present value is Present of the
element's decode at the key's own path (`SERDE-16`, `SERDE-17` with no field-default machinery) — and
whose protocol `#dexpace_load(parsed, ctx)` is `SERDE-20`'s top-level case. `.of` and `.from_nullable`
are two names on purpose: one is the decode-side combinator, the other a value mapper.

```ruby
w = T.of(String)
w.dexpace_load_field({}, "x", ctx).to_s                   # => "Absent"
w.dexpace_load_field({ "x" => nil }, "x", ctx).to_s       # => "Null"
w.dexpace_load_field({ "x" => "v" }, "x", ctx).value      # => "v"
w.dexpace_load(nil, ctx).to_s                             # => "Null"
```

## The encode walk: `Native` and `OMIT`

`Dexpace::Serde::Native.of(value, encoders: {})` walks any value into codec-native Ruby — `Hash`,
`Array`, `String`, `Integer`, `Float`, `true`, `false`, `nil` — in the one place where `SERDE-15`'s key
omission, `SERDE-20`'s three degradations and `SERDE-9`'s loud failure on an unencodable value all live.
Design §7.3 put the Absent-key omission in each model's own `#dexpace_dump`; the port puts it in the
walk instead (`7a P7-9`), because `SERDE-19`'s named failure — "absent this wiring, Absent and Null
become indistinguishable on the wire" — is exactly what a per-model convention produces when one model
forgets, silently, in a PATCH. A model that omits its own Absent keys still works; the walk has nothing
to drop. The rules, in order: native scalars pass through (a mutable String copied and frozen, nothing
retagged); anything answering `#dexpace_dump` is replaced and **re-walked**; a Hash has each value walked
and an entry whose value is `OMIT` dropped, with String and Symbol keys coerced to Strings and anything
else refused; an Array has each element walked and an `OMIT` written as `nil`; at the top level `OMIT`
is `nil`; a class in `encoders:` — exact class first, then the first `is_a?` match — is replaced and
re-walked; and anything else raises `SerializationError` **naming the class**, the loud failure
`::JSON.generate` measurably does not give (it returns the object's `#inspect` as a JSON string).

```ruby
S::Native.of(PetPatch.new(name: "x", nick: T::ABSENT)).to_a      # => [["name", "x"]]
S::Native.of(PetPatch.new(name: "x", nick: T::NULL)).to_a        # => [["name", "x"], ["nick", nil]]
S::Native.of([T::ABSENT, T.present("v")])                        # => [nil, "v"]
S::Native.of(T::ABSENT)                                          # => nil
S::OMIT.to_s                                                     # => "Omit"
S::Native.of(Object.new)
# => Dexpace::Serde::SerializationError: Object is not a codec-native value: it answers no #dexpace_dump and no encoder is configured for it
S::Native.of(Time.utc(2026, 9, 10), encoders: { Time => ->(t) { t.iso8601 } })   # => "2026-09-10T00:00:00Z"
```

`Native` and `OMIT` are public because a second codec adapter (`dexpace-serde-oj`, post-v1) calls `.of`
and inherits tri-state encoding, which is design §3.4's "no second code path in core". Core ships the
`encoders:` table **empty**; the adapter fills it. A Symbol value is not native and raises; a BINARY
String is handed to the generator as it is, which refuses invalid UTF-8 (a `SerializationError`) and
warns on valid UTF-8 tagged BINARY — encode text as UTF-8 before it reaches a codec. The walk returns
fresh collections and never aliases a caller's. A cyclic graph recurses without bound and is the
caller's mistake.

## The ISO-8601 witness: `Instant`

`Dexpace::Serde::Instant` is core's, because a witness is codec-agnostic and a second codec would
otherwise write a second one; its *default wiring* as the encoder for `::Time` is the adapter's.
`.dexpace_load` parses through `Time.iso8601` (from `time`, which the `Dexpace/NoTimeParse` cop does not
ban; phase 5a's `HTTPDate` is RFC 1123, a different grammar) and refuses the lax forms `"2026-09-10"`,
`"2026-09-10 12:00:00"`, `""` and a non-String, each naming `Time (ISO-8601)` at the field's path.
`.dexpace_dump` renders `#iso8601(6)`.

**The precision domain (`7a P7-8`).** `Time#iso8601(n)` truncates rather than rounds, so `SERDE-24`'s
round trip holds exactly for any `Time` whose `subsec` is an exact multiple of one microsecond — every
`Time` this SDK constructs (`Time.utc(...)`, `Time.at(sec, usec, :usec)`) and every `Time` `Instant`
decodes — and is lossy outside it, including the ordinary-looking `Time.new(2026, 9, 10, 12, 0,
0.123456, "+02:00")`, whose Float second is stored as the exact rational `0.12345599999…` and renders one
microsecond low. The port does not round instead: that would be a second date formatter beside
`HTTPDate`.

```ruby
S::Instant.dexpace_dump(Time.utc(2026, 9, 10, 12))                          # => "2026-09-10T12:00:00.000000Z"
S::Instant.dexpace_load("2026-09-10T12:00:00Z", ctx).utc?                   # => true
S::Instant.dexpace_dump(Time.new(2026, 9, 10, 12, 0, 0.123456, "+02:00"))   # => "2026-09-10T12:00:00.123455+02:00"
t = Time.at(1_757_505_600, 123_456, :usec).utc
S::Instant.dexpace_load(S::Instant.dexpace_dump(t), ctx) == t              # => true
```

## The JSON codec: `Dexpace::Serde::JSON`

`gems/dexpace-serde-json` is the workspace's second real gem: `Dexpace::Serde::JSON::Codec` implements
phase 2's six seam methods over one private `::JSON::Coder`, the gemspec declares `json >= 2.19.9` —
**the only place in the repository that floor may be stated** — and the entry file re-asserts the floor at
require time as `Dexpace::SeamError` (`7a P7-7`), because `bundler-audit` runs in this repository's CI and
never in a consumer's process, and an unbundled `require "dexpace/serde/json"` on a stock Ruby 3.3 or
3.4 activates the interpreter's default json (2.7.2 / 2.9.1), which has no `JSON::Coder` at all — and a
stock Ruby 4.0 activates 2.18.0, which has one and is still below the floor; `json/floor_test.rb` drives
the assertion against each interpreter's default json in a bundler-stripped child process. Requiring
the entry file registers the codec under `:json` with `core: "~> 0.0"`, design §2.4's version-skew guard.

`Dexpace::Serde::JSON.default` is a factory — a **fresh** codec on every call (`SERDE-25`) — and
`.build(options)` takes one positional Hash validated against an allowlist of five: `max_nesting:`,
`allow_nan:`, `allow_duplicate_key:`, `script_safe:` and `encoders:`. An unknown key is the SDK's own
`InvalidArgumentError`, because json 2.19.9 swallowed an unknown `Coder` option silently and json 3.0
refuses it with a keyword error. Two options are the codec's and not the caller's: `strict: true` always
(belt and braces beside `Native`, which refuses every non-native value before the generator sees it) and
`allow_duplicate_key: false` unless the caller opts in, because a duplicate key is accepted-last-wins on
json 2.9, a warning on 2.19.9 and a `ParserError` on 3.0, and the explicit option makes it one
`DeserializationError` across the range. `encoders:` never reaches the `Coder`; it replaces the default
table, which renders `::Time`, `::DateTime` and `::Date` as ISO-8601 through `Instant` (`SERDE-24`).

```ruby
Dexpace::Serde.conforms?(CODEC)                                            # => true
CODEC.media_type.render                                                    # => "application/json"
CODEC.dump_string(Pet.new(id: 7, name: "Ré", tags: %w[a]))                 # => "{\"id\":7,\"name\":\"Ré\",\"tags\":[\"a\"]}"
CODEC.dump_bytes({ "a" => "é" }).encoding.name                             # => "ASCII-8BIT"
pet = CODEC.load(src("{\"id\":7,\"name\":\"Ré\",\"tags\":[\"a\"],\"extra\":true}"), Pet)
[pet.class, pet.id, pet.name, pet.tags]                                    # => [Pet, 7, "Ré", ["a"]]
CODEC.dump_string(PetPatch.new(name: "x", nick: T::ABSENT))                # => "{\"name\":\"x\"}"
CODEC.dump_string(PetPatch.new(name: "x", nick: T::NULL))                  # => "{\"name\":\"x\",\"nick\":null}"
CODEC.load(src("{\"name\":\"x\"}"), PetPatch).nick.to_s                    # => "Absent"
CODEC.dump_string({ "at" => Time.utc(2026, 9, 10, 12) })                   # => "{\"at\":\"2026-09-10T12:00:00.000000Z\"}"
S::JSON.default.equal?(S::JSON.default)                                    # => false
S::JSON::MINIMUM_JSON_VERSION                                              # => "2.19.9"
Dexpace::Serde.registered_keys                                             # => [:json]
S::JSON.build(max_nestng: 4)
# => Dexpace::InvalidArgumentError: unknown codec option(s) :max_nestng; the accepted options are :max_nesting, :allow_nan, :allow_duplicate_key, :script_safe, :encoders
```

**The failure model** (`SERDE-9`, `SERDE-10`, `SERDE-12`, `SERDE-13`, `7a P7-6`). An unencodable value
raises `SerializationError`; malformed input raises `DeserializationError` with the parser's error as
`#cause`; a wire null into a non-null target names the target; invalid UTF-8 in the payload is refused
before parsing, because 3a's `#read_utf8` retags without validating and `::JSON.parse` accepts invalid
UTF-8 and returns a String that claims an encoding it does not have (`P7-6`); and a genuine stream I/O
error propagates **unwrapped**, structurally — the codec rescues `::JSON::JSONError` around the parse
alone, whose ancestry is `[ParserError, JSONError, StandardError]` with `IOError` nowhere in it, so a
`Dexpace::StreamError` cannot be caught by it.

```ruby
CODEC.dump_string(Object.new)
# => Dexpace::Serde::SerializationError: Object is not a codec-native value: it answers no #dexpace_dump and no encoder is configured for it
begin; CODEC.load(src("{not json"), Pet); rescue S::DeserializationError => e; [e.class, e.cause.class]; end
# => [Dexpace::Serde::DeserializationError, JSON::ParserError]
CODEC.load(src("null"), Pet)
# => Dexpace::Serde::DeserializationError: expected Pet (Hash) at /, got NilClass
CODEC.load(src("{\"name\":\"\xff\"}".b), Pet)
# => Dexpace::Serde::DeserializationError: the payload is not valid UTF-8 (RFC 8259 §8.1); refusing to parse it
failing = Object.new
def failing.read_utf8(*) = raise Dexpace::StreamError, "connection reset"
begin; CODEC.load(failing, Pet); rescue Dexpace::StreamError => e; [e.class, e.is_a?(S::Error)]; end
# => [Dexpace::StreamError, false]
```

**The four encode profiles and the stream rule** (`SEAM-20`, `SEAM-21`, `SERDE-3`, `SERDE-4`, `7a
P7-5`). `#dump_string` answers a fresh UTF-8 String and `#dump_bytes` the same bytes BINARY-tagged;
`#dump_to(value, sink)` writes into a caller-owned `#write` sink and answers the count; `#dump_into(value,
buffer, offset:)` writes at an offset into a **mutable BINARY String** and answers the count, with an
explicit fit check — `String#[]=` silently *grows* a String on an over-long payload — raising
`::IndexError` (distinct from the serde type, `#cause` nil even inside a caller's rescue) on an overflow
or an out-of-range offset and leaving the buffer untouched. Ruby's `IO::Buffer` is refused with
`InvalidArgumentError`: it warns through `Warning.warn` on construction at every level, which the suite's
fatal-warnings base turns into an error, and its `#set_string` raises `ArgumentError` where `String#[]=`
raises `IndexError` (`P7-5`). **The codec closes nothing** — not the sink, not the source it reads to
EOF, not the buffer — which is the third ownership rule beside `IO-6`'s and `BODY-8`'s, phase 3 left to
this layer, and the adapter's suite asserts it against close-counting trackers under every option.

```ruby
buffer = ("\0" * 12).b
CODEC.dump_into({ "a" => 1 }, buffer, offset: 2)      # => 7
buffer                                                 # => "\x00\x00{\"a\":1}\x00\x00\x00"
CODEC.dump_into({ "a" => 1 }, ("\0" * 4).b, offset: 0)
# => IndexError: 7 bytes at offset 0 do not fit a 4-byte buffer
require "stringio"                                    # StringIO is not loaded by the codec
sink = StringIO.new(+"".b)
CODEC.dump_to([1, 2], sink)                            # => 5
sink.closed?                                           # => false
```

**`#load` materialises the whole text (`7a P7-1`).** `SERDE-27` asks a decoding handler to stream the
body "without first materializing the whole body", and no version of the `json` gem at or above the
floor can be handed a stream: `JSON.parse` raises `TypeError` on a `StringIO`, and the one IO-accepting
entry point, `JSON.load`, is banned by design §3.4 for its `create_additions` hazard. So `#load` drains
the source to EOF with 3a's `#read_utf8` under `Dexpace::IO.max_materialized_bytes` (64 MiB by default,
checked incrementally), and **a response body above that ceiling raises `Dexpace::StreamError`**, an
`::IOError`, unwrapped past the codec and past the handler's close — the documented limit a caller
streaming a large JSON response meets. A caller wanting a larger body streams it through
`Response#body.source` rather than through a typed handler. The seam already takes the source, so an
adapter whose library has a pull parser (`dexpace-serde-oj`, post-v1) satisfies the clause with no change
to core, to the handlers or to the seam.

## `Body.serialized`

`SERDE-2`'s factory, the ninth beside phase 3b's eight: a value plus a serde, with the serde's declared
media type as the body's — a `MediaType` passed through, a String parsed through phase 1's
`MediaType.parse`, and a nil or empty one refused naming the codec's class, because "MUST NOT be
defaulted to a format-agnostic constant" means there is no fallback to fall back to. It returns a
replayable `BytesBody` that knows its exact length. The default `Content-Type` travels as the body's
media type; the header itself is the transport's to stamp on the wire when the caller set none
(`TRANSPORT-10`, phase 8).

```ruby
body = Dexpace::Body.serialized(PetPatch.new(name: "Ré", nick: T::ABSENT), serde: CODEC)
[body.class, body.media_type.render, body.content_length, body.replayable?]
# => [Dexpace::BytesBody, "application/json", 14, true]
```

## The two response handlers

Both are `Dexpace::_ResponseHandler`s — `#call(response) -> value` — supplied **into** phase 3b's
`TypedResponse` and never replacing it: 3b's memo and its flip-only mutex are its, and a handler runs
outside that lock by construction. Both are frozen `Data`s built through `.build`, with
`Dexpace::Serde.witness!` at construction so a bad witness fails there rather than at first body access,
which matters because `TypedResponse` is lazy.

**`DecodingHandler.build(serde:, witness:)`** is `SERDE-27`: it hands `#load` the body's own `#source`
and copies nothing; closes the response in an unguarded `ensure` on **every** path (the handler's subject
is the response; the codec's, under `SERDE-3`, is the stream — two rules, two subjects); surfaces a
missing **or empty** body as a `DeserializationError` naming the target (`an anonymous witness` for a
`Class.new` one, which has no name to carry), screened before `#load` with
`BufferedSource#eof?`, a non-consuming probe (never `#content_length`, which is `-1` for every
unknown-length body, and never a parser message, which differs across json versions); and rescues
nothing, so the codec's chained failures and an unwrapped I/O error both pass through. Which bodies it
can read, stated because `Body#source`'s default raises: `ResponseBody`, `ResponseLoggingBody` and
`BufferBody` — a `BytesBody` (`Body.bytes`, `Body.string`) raises `StreamError` naming the class, and
`Body.buffer` is the readable in-memory spelling.

**`StatusAwareHandler.build(serde:, witness:, factory:)`** is `SERDE-28`: a 2xx delegates to a
`DecodingHandler` (one implementation of `SERDE-27`); a 4xx/5xx buffers the body through phase 4b's
`Recovery.buffer_error_body` — the one buffering call site, which closes the live response itself, so
this branch adds no second close — and raises `factory.call(buffered)`, `ProtocolError.for` by default,
`cause: nil`; and anything else (a 1xx, an unfollowed 3xx such as a 304) closes the response and raises
a `DeserializationError` whose message leads with the status code and carries the **raw** `ETag` and
`Location` values, parsed by nothing. `factory:` is the same keyword `Recovery::ErrorMappingStep` takes,
so a generated SDK substitutes its typed errors — and decodes the buffered error body with its own
witness — with the hook it already knows.

The five responses the example reads are built over `Body.buffer` — the readable in-memory body — by one
helper, from the codec's own media type; a real transport's `ResponseBody` reads the same way.

```ruby
def response_over(status, text, headers: Dexpace::Headers::EMPTY_INBOUND)
  buffer = Dexpace::IO::Buffer.new
  buffer.write(text.b)
  request = Dexpace::Request.build(method: "GET", url: "https://host/v1/pets/7", headers: Dexpace::Headers::EMPTY)
  Dexpace::Response.build(request: request, protocol: Dexpace::Protocol::HTTP_1_1, status: status, headers: headers,
                          body: Dexpace::Body.buffer(buffer, media_type: CODEC.media_type))
end
ok_200 = response_over(200, '{"id":7,"name":"Ré","tags":["a"]}')
not_found_404 = response_over(404, '{"error":"gone"}')
not_modified_304 = response_over(304, "", headers: Dexpace::Headers.inbound_builder.add("etag", '"v1"').build)
empty_200 = response_over(200, "")
empty_list_200 = response_over(200, "[]")

handler = S::StatusAwareHandler.build(serde: CODEC, witness: Pet)
typed = Dexpace::TypedResponse.new(response: ok_200, handler: handler)
typed.status.code                                        # => 200
typed.value.name                                         # => "Ré"
typed.value.equal?(typed.value)                          # => true   (HTTP-44: decoded once, memoised)
begin; Dexpace::TypedResponse.new(response: not_found_404, handler: handler).value; rescue Dexpace::ProtocolError => e; [e.status.code, e.response.body_string, e.response.body_string]; end
# => [404, "{\"error\":\"gone\"}", "{\"error\":\"gone\"}"]   (twice, after the live response closed)
Dexpace::TypedResponse.new(response: not_modified_304, handler: handler).value
# => Dexpace::Serde::DeserializationError: 304 Not Modified: not decoded into Pet, only a 2xx body is (SERDE-28); etag: "v1"
Dexpace::TypedResponse.new(response: empty_200, handler: handler).value
# => Dexpace::Serde::DeserializationError: no body to decode into Pet: the response carried none (SERDE-27)
S::DecodingHandler.build(serde: CODEC, witness: S::List.of(Pet)).call(empty_list_200)   # => []
```

The composed path a generated SDK walks — `Dexpace::Operation` → `Pipeline.standard` → `TypedResponse`
over `StatusAwareHandler` over the real codec — is asserted end to end in
`gems/dexpace-serde-json/test/dexpace/serde/json/composition_test.rb`, over an in-memory transport; its
socket twin is phase 8a's.

## What is deliberately not here

- **A codec that streams.** `7a P7-1`: `#load` materialises the text under the 64 MiB ceiling and a body
  above it is a `StreamError`; an adapter with a pull parser satisfies `SERDE-27`'s clause with no core
  change, and `dexpace-serde-oj` is the named candidate (`docs/first-release.md`).
- **A `::Time` entry in core's scalar table.** The ISO-8601 wiring is the adapter's per design §3.4; a
  core mapping would make it every codec's default. `List.of(Dexpace::Serde::Instant)` is the spelling.
- **A `#call`-shaped witness.** `SERDE-5` and `SERDE-8`, above. Phase 2's `FakeCodec` drives its witness
  through `#call` because it predates the protocol, which is why core's handler tests use a named class
  answering both.
- **A `DumpContext`.** Encoding takes no context; the asymmetry is §7.3's own argument.
- **A per-type cache.** `SERDE-29`'s cache clause has no subject: the witness is supplied per call and
  nothing is memoised by type, which is what makes one frozen codec safe to share.
- **Ruby's `IO::Buffer` as a `#dump_into` target.** `7a P7-5`: a mutable BINARY String *is* Ruby's byte
  array, and `IO::Buffer` warns on construction and raises a different class on overflow.
- **A `Content-Type` header stamped by `Body.serialized`.** The media type is the body's; the header is
  the transport's to write when the caller set none (`TRANSPORT-10`).
- **Parsing `ETag` or `Location` in the 304 message.** `HTTP-48` is unbuilt and a release decision; the
  handler copies the raw values, so a malformed server `ETag` stays a diagnostic rather than becoming a
  second failure.
