# First Release

Release-readiness register. **Nothing has been published.** There is no `gems/` directory yet, no
tag, and no version beyond the `0.0.0` every gem will start at.

## Gems, once they exist

Per `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` §2.1, the MVP is six gems, every one of
them at `0.0.0` until the first release:

| Gem | Published? |
|---|---|
| `dexpace-core` | no — 0.0.0 |
| `dexpace-transport-net_http` | no — 0.0.0 |
| `dexpace-serde-json` | no — 0.0.0 |
| `dexpace-transport-async_http` | no — 0.0.0 |
| `dexpace-async-thread` | no — 0.0.0 |
| `dexpace-conformance` | no — 0.0.0. **Phase 8 owns this gem's gemspec, its version and its first
  release** (the roadmap's phase-8 row; phase 9 adds the remaining suites and owns neither). This is the
  row that moves first: phase 8's phase-level pull request performs the **workspace's first gem release**,
  and `DEF-22`'s assertion objects are what it has to release |

**Supported Ruby is not uniform across this table, from phase 8 onward.**
`dexpace-transport-async_http` declares `required_ruby_version >= 3.3` where every other gem keeps the
repository floor of 3.2 (phase 8c's deviation `P8-36`, `OI-38`): `async-http` 0.104.0 and its whole
dependency closure require 3.3, and the last release allowing 3.2 is eleven minor versions behind the one
phase 8c verified against. **A consumer on Ruby 3.2 composes `dexpace-core`,
`dexpace-transport-net_http`, `dexpace-serde-json`, `dexpace-async-thread` and `dexpace-conformance`, and
loses only the reactor transport** — which is `NFR-2`'s separability paying for itself, and it should be
stated in the release notes rather than discovered at `bundle install`.

**One gem's transitive closure contains a native extension.** `dexpace-transport-async_http` depends on
`io-event`, which compiles C (`ext/extconf.rb`). A platform with no toolchain and no precompiled
`io-event` cannot install that gem; the composition above is the answer for such a platform too.

## Blockers before first publish

- [ ] Repository scaffolding: `gems/`, root `Gemfile`, `Rakefile`, `Steepfile`,
      `rbs_collection.yaml`, `.rubocop.yml`, `VERSIONS` (§2.3)
- [ ] CI wired up and green on every gem
- [ ] The `dexpace-conformance` suite passing across the full supported Ruby range, 3.2 through 4.0.
      **Checkable for the first time after phase 8** (2026-09-12): phase 8a writes the suite this line
      names — `DEF-22`'s assertion protocol, the §9.3 `TCPServer` fixture and both thin drivers — and
      phase 8a and 8c each run it against a real adapter. **With one stated exception**: the 3.2 row runs
      the suite against `dexpace-transport-net_http` only, because `dexpace-transport-async_http` cannot
      be installed there (see the supported-Ruby note above, `P8-36`/`OI-38`). "Passing across 3.2
      through 4.0" therefore means: every gem on every row it can be installed on
- [ ] **Before release, `docs/sdk-documentation/` must state what a green `dexpace-conformance` run does
      and does not prove, and the run's own report preamble must name the same omissions.** Filed
      2026-09-12 by phase 8a's design (`P8-9`). The wire fixture speaks plaintext only and exercises no
      connect timeout, so `TRANSPORT-4`'s open-timeout half and every TLS property are asserted in
      `dexpace-transport-net_http`'s own suite and **not** in the portable one; phase 8c's adapter
      additionally carries a named waiver listing `TRANSPORT-14`, whose malformed-inbound-header-**name**
      clause is unreachable on `async-http` (`OI-39`, `P8-38`). A third-party adapter author whose adapter
      passes is entitled to know that TLS verification, connect-timeout classification and any waived ID
      were not among the things it passed — which is the difference between a conformance suite and a
      badge. Cites `TRANSPORT-4`, `TRANSPORT-14`, `TRANSPORT-20`, `DEF-22`, `NFR-2`
- [ ] An RBS sig-diff baseline established, so a later release can be checked against it for an
      accidental breaking change
- [ ] `SECURITY.md` contact confirmed reachable and monitored
- [ ] RubyGems ownership settled for every gem name above, and trusted publishing configured
      (OIDC-based, no long-lived API key committed anywhere)
- [ ] A decision on the four unbuilt convenience requirements in the HTTP domain model —
      `HTTP-48` (ETag), `HTTP-49` (HTTP range) and `HTTP-50` (the conditional-request aggregator),
      all SHOULD-level, plus `HTTP-22` (header-name interning, a MAY). Phase 1 built none of them.
      **`DEF-2`'s phase-6 target was corrected on 2026-09-09: it does not fire.** Phase 6 carries a
      conditional header but constructs none — `REDIR-3`/`REDIR-4` preserve, `REDIR-5` strips,
      `AUTH-30` copies — so the four are still unbuilt after phase 6 and this decision is still owed
- [ ] **Phase 8's first transport adapter must wrap every stdlib I/O and timeout error it lets
      escape** — `Errno::ETIMEDOUT`, `SocketError`, `Timeout::Error` and their kin — in something
      answering `#retryable?` (`Dexpace::TransportError` or equivalent), defaulting to `true` per
      `XCUT-4` branch (b). `RETRY-2`'s classification is a capability-only query (`XCUT-6`,
      `DEF-40`), so a bare unwrapped stdlib error classifies as **not retryable**, which is a silent
      retry-eligibility regression for exactly the class of failure `RETRY-4` calls "always
      retryable". It is invisible until an adapter exists to test it against, and reachable the
      first time a real socket times out. Recorded by phase 6a's design as deviation `P6-4`.
      **Closed in design 2026-09-12 by phase 8's planning; the box ticks when the class lands, which
      is phase 8a's Task 2.** The question this line asked — *will* phase 8 do it, with what, and who
      owns it — is now answered rather than open. `Dexpace::TransportError` is a **phase-level** task in
      `dexpace-core`, in a different gem from all three sub-phases, with one owner (8a's Task 2; 8c's
      Task 4 is a citation and a verification, and defines the class only in the out-of-order case, in
      the identical shape): `class TransportError < ::IOError; include Dexpace::Error; end`, `#retryable?`
      returning `true` unconditionally with no keyword that can override it, and a `#phase` reader
      (`:connect`/`:write`/`:read`/`:close`) **for diagnostics only, never branched on by `RETRY-2`'s
      capability query**. Phase 8 also supplies the exact list the wrap must cover, which is what makes
      the blocker real rather than theoretical: `Net::OpenTimeout`, `Net::ReadTimeout`,
      `Net::WriteTimeout` (all `< Timeout::Error < RuntimeError`), `SocketError` (`< StandardError`),
      `Errno::*` (`< SystemCallError`), `Async::TimeoutError` (`< StandardError`) and
      `Protocol::HTTP1::Error` (`< StandardError`) — **not one of which is an `::IOError` descendant**.
      It also closes phase 6a's deviation `P6-4`

## Release path

Not yet defined. `NFR-16`'s signing requirement is enforced on the release path only once that
path exists (see `docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md`, NFR row); until
then there is no path to enforce it on.
