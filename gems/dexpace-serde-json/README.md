# dexpace-serde-json

Part of the [dexpace Ruby SDK](../../README.md): an HTTP-client toolkit, not an HTTP client.
This gem is the wire-codec seam's reference implementation, over `json`.

**Status: skeleton at `0.0.0`.** Nothing is published yet, and `lib/` holds the namespace and a
`VERSION` constant and nothing else. The phase that fills it is named in the YARD block of
`lib/dexpace/serde/json.rb`.

## Install

```ruby
# Gemfile
gem "dexpace-serde-json"
```

## The smallest thing that works today

```ruby
require "dexpace/serde/json"

puts Dexpace::Serde::JSON::VERSION # => "0.0.0"
```

## Depends on

`dexpace-core`, and later `json >= 2.19.9` -- the one third-party gem `NFR-2` budgets for this
adapter, declared by phase 7 with the codec that needs it. That floor lives in this gemspec and
nowhere else.

## Where to read next

- `docs/sdk-documentation/architecture.md` -- how the gems compose and which one to install.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` -- the gem layout and the
  zero-dependency invariant every gem here is built under.
