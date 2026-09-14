# dexpace-transport-async_http

Part of the [dexpace Ruby SDK](../../README.md): an HTTP-client toolkit, not an HTTP client.
This gem is the asynchronous transport seam's reference adapter, over `async-http`.

**Status: skeleton at `0.0.0`.** Nothing is published yet, and `lib/` holds the namespace and a
`VERSION` constant and nothing else. The phase that fills it is named in the YARD block of
`lib/dexpace/transport/async_http.rb`.

## Install

```ruby
# Gemfile
gem "dexpace-transport-async_http"
```

## The smallest thing that works today

```ruby
require "dexpace/transport/async_http"

puts Dexpace::Transport::AsyncHTTP::VERSION # => "0.0.0"
```

## Depends on

`dexpace-core`, and later `async-http` -- the one third-party gem `NFR-2` budgets for this adapter,
declared by phase 8 with the code that needs it.

## Where to read next

- `docs/sdk-documentation/architecture.md` -- how the gems compose and which one to install.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` -- the gem layout and the
  zero-dependency invariant every gem here is built under.
