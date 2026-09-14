# dexpace-transport-net_http

Part of the [dexpace Ruby SDK](../../README.md): an HTTP-client toolkit, not an HTTP client.
This gem is the synchronous transport seam's reference adapter, over `net/http`.

**Status: skeleton at `0.0.0`.** Nothing is published yet, and `lib/` holds the namespace and a
`VERSION` constant and nothing else. The phase that fills it is named in the YARD block of
`lib/dexpace/transport/net_http.rb`.

## Install

```ruby
# Gemfile
gem "dexpace-transport-net_http"
```

## The smallest thing that works today

```ruby
require "dexpace/transport/net_http"

puts Dexpace::Transport::NetHTTP::VERSION # => "0.0.0"
```

## Depends on

`dexpace-core`, and later `net-http` -- the one third-party gem `NFR-2` budgets for this adapter,
declared by phase 8 with the code that needs it.

## Where to read next

- `docs/sdk-documentation/architecture.md` -- how the gems compose and which one to install.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` -- the gem layout and the
  zero-dependency invariant every gem here is built under.
