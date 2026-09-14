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

**Phase 0 is built; no domain code is.** Nothing is published. The repository holds six gems under
`gems/`, every one at `0.0.0` and every one a skeleton — a namespace, a `VERSION`, a gemspec, a
signature mirror and a smoke suite:

| Gem | Namespace | Runtime dependencies today |
|---|---|---|
| `dexpace-core` | `Dexpace` | none |
| `dexpace-transport-net_http` | `Dexpace::Transport::NetHTTP` | `dexpace-core` |
| `dexpace-transport-async_http` | `Dexpace::Transport::AsyncHTTP` | `dexpace-core` |
| `dexpace-serde-json` | `Dexpace::Serde::JSON` | `dexpace-core` |
| `dexpace-async-thread` | `Dexpace::Async::Thread` | `dexpace-core` |
| `dexpace-conformance` | `Dexpace::Conformance` | `dexpace-core` |

What phase 0 does ship is the gate set every later phase is written under: seventeen blocking
checks in one `bundle exec rake`, each proven by a deliberately failing input, and a CI matrix
that runs the real suite on Ruby 3.2, 3.3, 3.4 and 4.0
(`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-checklist.md`).

## Working in the repository

```bash
bundle install          # Gemfile.lock is not committed; each Ruby resolves its own
bundle exec rake        # every gate, in order
bundle exec rake -T     # each gate is separately invocable
```

`CLAUDE.md` is the working summary — the hard rule on what `dexpace-core` may `require`, the
requirement-ID conventions, the constraints that will bite — and `docs/README.md` is the index
of everything under `docs/`: the normative specification, the port design, the harvested
knowledge corpus, the as-built documentation and the per-phase process records.

## License

MIT — see [`LICENSE`](./LICENSE). Every gem ships a byte-identical copy.
