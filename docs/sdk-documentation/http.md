# The HTTP domain model

**As built by phase 1, in `dexpace-core`, written against source on 2026-09-15.** This page says
how the wire model composes and what to expect from it. What each type is *required* to do is
`docs/product-spec/04-core-http-domain-model.md`; how the design maps it to Ruby is
`docs/sdk-design-ruby/04-domain-model-construction.md`; the per-requirement proof is
`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-checklist.md`. Signatures live in
`gems/dexpace-core/sig/`, and this page does not restate them.

## One shape, every type

Every value type here is `class X < Data.define(...)` including `Dexpace::Model`, with `new`
private and a public, validating `.build`. That buys four properties at once, and they are the
same for `Status` as for `Request`:

- **Frozen on construction.** A model never changes; a collection member is copied and
  deep-frozen once, at build (`Model.own`), so an accessor hands back the model's own frozen
  object with no per-call copy, and a `Hash` or `Array` the caller keeps a reference to cannot
  reach the model afterwards. Every model — `Request` and `Response` included, when the opaque
  body they carry is `nil` or frozen — is `Ractor.shareable?`, which is the one-line proof the
  freeze reached every level and is not otherwise relied on.
- **Validated wherever it was built.** Validation lives in each type's `initialize`, so
  `.build`, `#with` and a builder's `#build` all meet it, and a missing required member fails with
  the one message form `<name> is required` (`Dexpace::Model.required!`).
- **Derived, never mutated.** A type with no builder derives through `#with(member: value)`, which
  routes through `.build` — `Dexpace::Model#with` overrides `Data#with` because the inherited one
  skips an `initialize` override on Ruby 3.2. A type with a builder derives through
  `#new_builder`, a builder pre-filled from the instance that copies every collection.
- **Coerced at the boundary.** A factory that has a typed form accepts the raw form too and
  is idempotent on its own type: `Request.build(method: "post", url: "https://…")` holds a
  `Dexpace::Method` and a frozen `URI::Generic`; `Response.build(protocol: "HTTP/2.0",
  status: 404, …)` holds a `Protocol` and a `Status`.

One error class covers every caller mistake: `Dexpace::InvalidArgumentError`, a subclass of
Ruby's `ArgumentError` that includes the SDK's root, `Dexpace::Error`. The root is a **module**
so that a later transport error can subclass `IOError` and still be caught by
`rescue Dexpace::Error`. `Dexpace::ArgumentError` is never defined.

## Building a request and reading a response

```ruby
require "dexpace"

builder = Dexpace::Request.builder
builder.url = "https://api.example.test/widgets?page=2"
builder.method = :post                      # a String, a Symbol or a Dexpace::Method
builder.body = "{}"                         # opaque until phase 3's body model; carried, not frozen
request = builder.header("Accept", "application/json").build

request.method                              # => Dexpace::Method::POST
request.method.idempotent?                  # => false
request.headers["ACCEPT"]                   # => ["application/json"]  (frozen; the model's own list)
request.headers.names                       # => ["Accept"]            (a fresh frozen snapshot)
Dexpace::URL.external_form(request.url)     # => "https://api.example.test/widgets?page=2"

retried = request.new_builder.header("X-Attempt", "2").build
request.headers.include?("X-Attempt")       # => false: the derivation copied, never aliased

response = Dexpace::Response.builder
response.request = request
response.protocol = "HTTP/1.1"
response.status = 429
built = response.build
built.status                                # => Dexpace::Status::TOO_MANY_REQUESTS
built.error?                                # => true, derived from the status
built.headers.direction                     # => :inbound, so obs-text is admitted (HTTP-19)
```

The builders carry exactly the rules that are about a field nobody set: a request with neither
method nor body is a `GET`; a body with no method reports `method is required` rather than
defaulting to `GET` and then rejecting the body; a `GET`, `HEAD`, `TRACE` or `CONNECT` with a body
is refused at build, and so is `get_request.with(body: "…")`, because the model checks too.

## Headers, names and bytes

`Dexpace::Headers` folds names for lookup, containment, equality and hashing and keeps the first
casing it saw for emission; two collections differing only in casing, or in the direction that
validated them, are equal. Every name and every value is validated **as bytes** by
`Dexpace::HeaderSyntax`, the module every transport re-runs immediately before dispatch:

| Input | Outbound (a request) | Inbound (a response) |
|---|---|---|
| a name with CR, LF, NUL, DEL, a space or any byte ≥ 0x80 | rejected | rejected |
| `"  X-Trace  "` | accepted as `X-Trace` — SP and HTAB are trimmed, nothing else | same |
| a value with HTAB | accepted | accepted |
| a value with a byte ≥ 0x80 (obs-text) | rejected | accepted |
| a value with CR, LF or DEL | rejected | rejected |
| a `String` whose bytes are not valid UTF-8 | rejected with `InvalidArgumentError` | as the rows above |

A rejected value never appears in the error message; a rejected name is echoed with its control
bytes escaped. `Headers.builder` validates by the outbound grammar and `Headers.inbound_builder`
by the inbound one; the direction is a member of the built collection, so a builder derived from
a response's headers stays lenient.

`Dexpace::HeaderName` is the typed name: equal and hashed by its fold, emitted with its original
casing, accepted everywhere a `String` name is.

## The value types

- **`Status`** — total over 100–599: `Status.of(520)` is a status with no canonical name, never an
  error; `Status.canonical_name(code)` is the separate lookup. Equality is by code alone. Range
  predicates (`success?`, `error?`, …) are derived, and `Response` delegates the same six.
- **`Method`** — an upper-cased RFC 7230 token, so extension methods are representable.
  `Method::IDEMPOTENT` and `#idempotent?` are the single source the retry layer derives from;
  `#body_forbidden?` is the classification the request builder asks. Inside `module Dexpace`,
  `Method` is this class; write `::Method` for Ruby's.
- **`Protocol`** — `http/1.1` or `http/2`; `Protocol.parse` accepts those and the aliases
  `HTTP/2` and `HTTP/2.0`, case-insensitively, and raises on anything else.
- **`MediaType`** — type, subtype and parameter keys folded, parameter values as given;
  `parse` splits parameters respecting quoted-strings and `render` re-quotes, so
  `parse(render(x)) == x`; `#charset` is `nil` for an absent or unknown charset, never a raise;
  `#matches?` handles `*/*` and `type/*`.
- **`Query`** — an insertion-ordered list of `[name, value]` pairs, case-sensitive, multiple
  values per name, `?flag` as a single empty-string value. `#encode` uses the strict RFC 3986
  component encoder (`Dexpace::PercentEncoding`: space is `%20`, `+` is `%2B`, `~` is bare) and
  `Query.parse` is its lenient inverse. Two queries are equal exactly when they encode
  identically.
- **`RequestOptions`** — per-call `timeout` (a `Float` of seconds), `max_retries` and string
  `tags`, every field `nil`/empty by default and `RequestOptions::EMPTY` the shared "override
  nothing". These are operational knobs and deliberately not part of `Request`.
- **`URL`** — a module, not a type: `URL.parse!` pins `URI::RFC3986_PARSER`, refuses a relative
  URI, and returns a `URI::Generic` frozen through its components; `URL.external_form` is the
  textual key `Request` compares by, with no name resolution.

## What is not here yet

The body model, `Response#close` and the body lifecycle are phase 3's; the pipeline, seams and
transports that carry these values are later phases'. `ETag`, the HTTP range helper and the
conditional-request aggregator (`HTTP-48`–`HTTP-50`) and header-name interning (`HTTP-22`) are not
built in v1 — see `docs/first-release.md`.
