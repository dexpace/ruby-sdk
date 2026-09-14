# dexpace-conformance

Part of the [dexpace Ruby SDK](../../README.md): an HTTP-client toolkit, not an HTTP client.
This gem is the conformance suite every adapter -- shipped or third-party -- is proven against.

**Status: skeleton at `0.0.0`.** Nothing is published yet, and `lib/` holds the namespace and a
`VERSION` constant and nothing else. The phase that fills it is named in the YARD block of
`lib/dexpace/conformance.rb`.

## Install

```ruby
# Gemfile
gem "dexpace-conformance"
```

## The smallest thing that works today

```ruby
require "dexpace/conformance"

puts Dexpace::Conformance::VERSION # => "0.0.0"
```

## Depends on

`dexpace-core` only, by design: the suite's Minitest and RSpec drivers reference `::Minitest` and
`::RSpec` at call time and `require` neither, so no test framework becomes a runtime constraint on a
consumer.

## Where to read next

- `docs/sdk-documentation/architecture.md` -- how the gems compose and which one to install.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` -- the gem layout and the
  zero-dependency invariant every gem here is built under.
