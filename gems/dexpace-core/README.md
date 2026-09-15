# dexpace-core

Part of the [dexpace Ruby SDK](../../README.md): an HTTP-client toolkit, not an HTTP client.
This gem is the core: the domain model, the pipeline and every seam's contract.

**Status: `0.0.0`, unpublished; the HTTP domain model is built.** `lib/` holds phase 1's wire
model -- `Dexpace::Request`, `Response`, `Headers`, `HeaderName`, `Status`, `Method`, `Protocol`,
`MediaType`, `Query`, `RequestOptions`, the `HeaderSyntax`, `PercentEncoding` and `URL` function
modules, and the construction contract `Dexpace::Model` / `Dexpace::Builder` under the error root
`Dexpace::Error` -- and nothing else yet: the pipeline, the seams and the body model are later
phases'. The as-built page is `docs/sdk-documentation/http.md`.

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

## Depends on

Nothing. `dexpace-core.gemspec` has no `add_dependency` line, and `rake gates:gemspec_audit` asserts
it stays that way (`SEAM-1`, `NFR-1`).

## Where to read next

- `docs/sdk-documentation/http.md` -- the domain model as built: what each type guarantees.
- `docs/sdk-documentation/architecture.md` -- how the gems compose and which one to install.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` -- the gem layout and the
  zero-dependency invariant every gem here is built under.
