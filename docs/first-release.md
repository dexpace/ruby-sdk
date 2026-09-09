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
| `dexpace-conformance` | no — 0.0.0 |

## Blockers before first publish

- [ ] Repository scaffolding: `gems/`, root `Gemfile`, `Rakefile`, `Steepfile`,
      `rbs_collection.yaml`, `.rubocop.yml`, `VERSIONS` (§2.3)
- [ ] CI wired up and green on every gem
- [ ] The `dexpace-conformance` suite passing across the full supported Ruby range, 3.2 through 4.0
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
      first time a real socket times out. Recorded by phase 6a's design as deviation `P6-4`

## Release path

Not yet defined. `NFR-16`'s signing requirement is enforced on the release path only once that
path exists (see `docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md`, NFR row); until
then there is no path to enforce it on.
