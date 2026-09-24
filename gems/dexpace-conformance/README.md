# dexpace-conformance

Part of the [dexpace Ruby SDK](../../README.md): an HTTP-client toolkit, not an HTTP client.
This gem is the conformance suite every adapter -- shipped or third-party -- is proven against.

**Status: `0.0.0`, unpublished; five suites are built.** `lib/` holds phase 8a's
`Dexpace::Conformance`: the assertion protocol phase 0 postponed -- `Failure`, `Vacuous`,
`Assertion`, `Result` with its five `STATUSES`, and `Report` -- the **thirty-four**-assertion
`TransportSuite` over twenty-eight `TRANSPORT` IDs, `HTTP-17`, `HTTP-18`, `XCUT-18` and `PAGE-36`
(twenty-eight over twenty-two at 8a; phase 8c's two groups are the rest),
the `TransportCase` an assertion receives and the `BorrowedPair` a borrowing construction
supplies, the plaintext `WireServer` fixture with its `RecordedRequest`s and fifteen named
`Scripts`, the two thin drivers `MinitestDriver` and `RSpecDriver`, and the two observability
doubles `RecordingSpan` and `Allocations` -- and phase 9's four further suites beside it:
`InvariantSuite` (28 assertions over all twenty-four `XCUT` IDs), `PackagingSuite` (8 over
`NFR-1`, `2`, `3`, `10`, `11`, `13`, `14` and `15`, read from published gem metadata),
`CodecSuite` (2 portable seam properties any wire codec must have) and `ExecutorSuite` (7 over an
async-runtime adapter's lifecycle), over the shared `Runner`, `Check` and `SharedInstance`, with
`Levels` -- every requirement ID's normative level, generated from the specification's own index --
making a MUST-level vacuity a report blocker, and `Aggregate` giving a whole run one verdict and one
preamble stating what it does not prove. The 61-row appendix-B coverage map is `APPENDIX_B.md`,
shipped beside this file.

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
  not, the runner and its report, the drivers, the case, the fixture and the doubles, and the four
  suites phase 9 added with a runnable example of each mechanism.
- `docs/sdk-documentation/transport-net_http.md` -- the reference adapter this suite is run
  against first.
- `docs/sdk-documentation/architecture.md` -- how the gems compose and which one to install.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` -- the gem layout and the
  zero-dependency invariant every gem here is built under.
