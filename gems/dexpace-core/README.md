# dexpace-core

Part of the [dexpace Ruby SDK](../../README.md): an HTTP-client toolkit, not an HTTP client.
This gem is the core: the domain model, the pipeline and every seam's contract.

**Status: skeleton at `0.0.0`.** Nothing is published yet, and `lib/` holds the namespace and a
`VERSION` constant and nothing else. The phase that fills it is named in the YARD block of
`lib/dexpace.rb`.

## Install

```ruby
# Gemfile
gem "dexpace-core"
```

## The smallest thing that works today

```ruby
require "dexpace"

puts Dexpace::VERSION # => "0.0.0"
```

## Depends on

Nothing. `dexpace-core.gemspec` has no `add_dependency` line, and `rake gates:gemspec_audit` asserts
it stays that way (`SEAM-1`, `NFR-1`).

## Where to read next

- `docs/sdk-documentation/architecture.md` -- how the gems compose and which one to install.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` -- the gem layout and the
  zero-dependency invariant every gem here is built under.
