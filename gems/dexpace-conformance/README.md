# dexpace-conformance

Part of the [dexpace Ruby SDK](../../README.md): an HTTP-client toolkit, not an HTTP client.
This gem is the conformance suite every adapter -- shipped or third-party -- is proven against.

**Status: `0.0.0`, unpublished; the transport suite is built.** `lib/` holds phase 8a's
`Dexpace::Conformance`: the assertion protocol phase 0 postponed -- `Failure`, `Vacuous`,
`Assertion`, `Result` with its five `STATUSES`, and `Report` -- the twenty-eight-assertion
`TransportSuite` over twenty-two `TRANSPORT` IDs, `HTTP-17`, `HTTP-18`, `XCUT-18` and `PAGE-36`,
the `TransportCase` an assertion receives and the `BorrowedPair` a borrowing construction
supplies, the plaintext `WireServer` fixture with its `RecordedRequest`s and fifteen named
`Scripts`, the two thin drivers `MinitestDriver` and `RSpecDriver`, and the two observability
doubles `RecordingSpan` and `Allocations`. Phase 9 adds the remaining suites beside the
transport one.

## Install

```ruby
# Gemfile, test group
gem "dexpace-conformance"
```

## The smallest thing that works today

```ruby
require "dexpace/conformance"

class MyAdapterConformanceTest < Minitest::Test
  extend Dexpace::Conformance::MinitestDriver

  conformance(
    Dexpace::Conformance::TransportSuite,
    build: ->(**settings) { MyAdapter.build(**settings) },
    borrow: nil,   # or ->(port) { Dexpace::Conformance::BorrowedPair.build(transport:, probe:) }
    waive: [],
  )
end
# => one test method per assertion; a Vacuous is a skip naming why, a Failure a flunk naming the IDs
```

Every report opens with `TransportSuite::PREAMBLE`: the fixture speaks plaintext only and
exercises no connect timeout, so TLS verification and `TRANSPORT-4`'s open-timeout half are not
among the things a green run proves. An RSpec consumer requires
`dexpace/conformance/rspec_driver` itself.

## Depends on

`dexpace-core` only, by design: the suite's Minitest and RSpec drivers reference `::Minitest` and
`::RSpec` at call time and `require` neither, so no test framework becomes a runtime constraint on a
consumer. `socket` and `tempfile` are stdlib that stays stdlib on every supported Ruby.

## Where to read next

- `docs/sdk-documentation/conformance.md` -- the as-built page: what a green run proves and does
  not, the runner and its report, the drivers, the case, the fixture and the doubles.
- `docs/sdk-documentation/transport-net_http.md` -- the reference adapter this suite is run
  against first.
- `docs/sdk-documentation/architecture.md` -- how the gems compose and which one to install.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` -- the gem layout and the
  zero-dependency invariant every gem here is built under.
