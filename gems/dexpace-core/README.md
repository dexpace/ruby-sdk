# dexpace-core

Part of the [dexpace Ruby SDK](../../README.md): an HTTP-client toolkit, not an HTTP client.
This gem is the core: the domain model, the pipeline and every seam's contract.

**Status: `0.0.0`, unpublished; the HTTP domain model and the seam layer are built.** `lib/`
holds phase 1's wire model -- `Dexpace::Request`, `Response`, `Headers`, `HeaderName`, `Status`,
`Method`, `Protocol`, `MediaType`, `Query`, `RequestOptions`, the `HeaderSyntax`,
`PercentEncoding` and `URL` function modules, and the construction contract `Dexpace::Model` /
`Dexpace::Builder` under the error root `Dexpace::Error` -- and phase 2's seam layer: the provider
registry `Dexpace::Registry`, the `Dexpace::Transport`, `Dexpace::AsyncTransport` and
`Dexpace::Serde` seams, the `Dexpace::Bridge` pair, the async pivot `Dexpace::Async::Future` /
`Completer`, `Dexpace::Cancellation`, `Dexpace::Closeable` and `Dexpace::Operation`. Nothing else
yet: the pipeline, the body model and every adapter are later phases', and no transport ships
here, so nothing talks to a socket. The as-built pages are `docs/sdk-documentation/http.md` and
`docs/sdk-documentation/seams.md`.

## Install

```ruby
# Gemfile
gem "dexpace-core"
```

## The smallest thing that works today

```ruby
require "dexpace"

builder = Dexpace::Request.builder
builder.url = "https://api.example.test/widgets"
request = builder.header("Accept", "application/json").build

request.method                  # => Dexpace::Method::GET, defaulted because there is no body
request.headers["accept"]       # => ["application/json"], looked up case-insensitively
request.with(body: "x")         # raises Dexpace::InvalidArgumentError: a GET carries no body
```

Every type is frozen at construction, validated in its constructor, and derived through
`#with` or `#new_builder` rather than mutated; a caller mistake raises
`Dexpace::InvalidArgumentError`, which is also an `ArgumentError`.

A transport is any object responding to `#call(request, options, cancellation)`, so the seam
layer works end to end with a lambda standing in for the adapter phase 8 ships:

```ruby
operation = Dexpace::Operation.build(
  method: "GET", template: "/pets/{id}", projections: { id: [:path, "id"], limit: [:query, "limit"] },
)
request = operation.build_request(base_url: "https://api.example.test/v1", inputs: { id: "a/b", limit: 1 })
request.url.to_s               # => "https://api.example.test/v1/pets/a%2Fb?limit=1"

Dexpace::Transport.swap(->(req, _options, _cancellation) { req.url.to_s }) do
  Dexpace::Transport.resolve.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
end
Dexpace::Transport.resolve     # raises Dexpace::SeamError: no transport provider is registered
```

## Depends on

Nothing. `dexpace-core.gemspec` has no `add_dependency` line, and `rake gates:gemspec_audit` asserts
it stays that way (`SEAM-1`, `NFR-1`).

## Where to read next

- `docs/sdk-documentation/http.md` -- the domain model as built: what each type guarantees.
- `docs/sdk-documentation/seams.md` -- the seam layer as built: what a transport, a codec and a
  future are, and how a provider is resolved.
- `docs/sdk-documentation/architecture.md` -- how the gems compose and which one to install.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` -- the gem layout and the
  zero-dependency invariant every gem here is built under.
