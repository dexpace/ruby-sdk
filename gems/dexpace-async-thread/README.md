# dexpace-async-thread

Part of the [dexpace Ruby SDK](../../README.md): an HTTP-client toolkit, not an HTTP client.
This gem is the async-runtime seam's adapter over plain Ruby threads.

**Status: skeleton at `0.0.0`.** Nothing is published yet, and `lib/` holds the namespace and a
`VERSION` constant and nothing else. The phase that fills it is named in the YARD block of
`lib/dexpace/async/thread.rb`.

## Install

```ruby
# Gemfile
gem "dexpace-async-thread"
```

## The smallest thing that works today

```ruby
require "dexpace/async/thread"

puts Dexpace::Async::Thread::VERSION # => "0.0.0"
```

## Depends on

`dexpace-core` only, by design: a thread is the runtime every Ruby already has, so this adapter
spends none of its `NFR-2` budget.

## Where to read next

- `docs/sdk-documentation/architecture.md` -- how the gems compose and which one to install.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` -- the gem layout and the
  zero-dependency invariant every gem here is built under.
