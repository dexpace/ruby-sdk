<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/dexpace-wordmark-dark.svg">
    <img alt="dexpace" src="docs/assets/dexpace-wordmark-light.svg" width="320">
  </picture>
</p>

<h1 align="center">Dexpace Ruby SDK</h1>

The Ruby SDK for dexpace: **an HTTP-client toolkit, not an HTTP client.** It is for authors of
generated or hand-written service-client SDKs who need the correctness-sensitive plumbing —
idempotency-aware retry, redirects that never leak a bearer token cross-origin, RFC 7235/7616
authentication, pagination, SSE, three-state PATCH — solved exactly once, and it deliberately does
not compete with `faraday` or `httpx` on the easiest way to fetch a JSON endpoint.

## Status

**Pre-release: the v1 roadmap is complete, and nothing is published.** All eleven roadmap phases
(0 through 10) are built and merged — the layers, the adapters, a conformance audit (phase 9) and a
reconciliation of every documented deviation against as-built source (phase 10). The six gems under
`gems/` are every one at `0.0.0`, and no tag has been cut. What remains before the first publish,
what v1 ships without and what would trigger work after it are tracked in
[`docs/first-release.md`](./docs/first-release.md).

| Gem | What it carries | Runtime dependencies |
|---|---|---|
| [`dexpace-core`](./gems/dexpace-core/) | The frozen, validated HTTP domain model; the transport, async-transport and codec seams with the core-owned async pivot and cancellation; byte streams and bodies; the execution context; the recovery layer; a sixteen-stage pipeline on a sync and an async runtime; the four-tier configuration chain and the clock; logging with redaction, tracing and metrics; retry, redirect and authentication; server-sent events; pagination; and the serialization witness protocol with three-state PATCH | none |
| [`dexpace-transport-net_http`](./gems/dexpace-transport-net_http/) | The synchronous transport over `Net::HTTP` | `dexpace-core`; `net-http >= 0.4` |
| [`dexpace-transport-async_http`](./gems/dexpace-transport-async_http/) | The asynchronous transport over `async-http`, HTTP/1.1 and HTTP/2 | `dexpace-core`; `async-http ~> 0.104` (Ruby >= 3.3) |
| [`dexpace-serde-json`](./gems/dexpace-serde-json/) | The JSON codec over `JSON::Coder` | `dexpace-core`; `json >= 2.19.9` |
| [`dexpace-async-thread`](./gems/dexpace-async-thread/) | A bounded, non-blocking thread-pool executor for the async path | `dexpace-core` |
| [`dexpace-conformance`](./gems/dexpace-conformance/) | The suites every adapter is proven against — transport, cross-cutting invariants, packaging, codec and executor | `dexpace-core` |

Each gem's README says how to use it; the as-built documentation, one page per layer and adapter,
starts at [`docs/sdk-documentation/architecture.md`](./docs/sdk-documentation/architecture.md).

Supported Ruby is 3.2 through 4.0, except `dexpace-transport-async_http`, which needs 3.3 or later
because its dependency does. Every change is held to twenty-four blocking gates in one
`bundle exec rake` — RuboCop with custom cops, `ruby -w` with warnings fatal, RBS and Steep, the
public-surface locks, an 80% coverage floor, the zero-dependency audits on `dexpace-core`, the
repository-wide invariant scans, YARD and `bundler-audit` — each proven by a deliberately failing
input, and CI runs the real suite on Ruby 3.2, 3.3, 3.4 and 4.0
([`docs/sdk-documentation/quality-gates.md`](./docs/sdk-documentation/quality-gates.md)).

## Working in the repository

```bash
bundle install          # Gemfile.lock is not committed; each Ruby resolves its own
bundle exec rake        # all twenty-four gates, in order
bundle exec rake -T     # each gate is separately invocable
```

`CLAUDE.md` is the working summary — the hard rule on what `dexpace-core` may `require`, the
requirement-ID conventions, the constraints that will bite — and `docs/README.md` is the index
of everything under `docs/`: the normative specification, the port design, the harvested
knowledge corpus, the as-built documentation and the per-phase process records.
[`CONTRIBUTING.md`](./CONTRIBUTING.md) is the contribution flow and
[`SECURITY.md`](./SECURITY.md) how to report a vulnerability.

## License

MIT — see [`LICENSE`](./LICENSE). Every gem ships a byte-identical copy.
