# dexpace-transport-net_http

Part of the [dexpace Ruby SDK](../../README.md): an HTTP-client toolkit, not an HTTP client.
This gem is the synchronous transport seam's reference adapter, over `net/http`.

**Status: `0.0.0`, unpublished; the adapter is built.** `lib/` holds phase 8a's
`Dexpace::Transport::NetHTTP`: the two constructions `.build(timeout:, logger:, tls:)` over a
fresh-per-call `Net::HTTP` and `.using(client, logger:)` over a caller's own, the `Adapter` behind
both with its owning-or-borrowing lifecycle, the header policy the wire carries (`MANAGED_HEADERS`,
`DEFAULT_CONTENT_TYPE`, and the three auto-stamps `Net::HTTP` adds that the adapter deletes), the
per-response producer thread behind every streamed body with its bounded release, one total
per-call budget across the three native timeout knobs, the classifier that asks the cancellation
token first and wraps every other failure as a retryable `Dexpace::TransportError`, the lenient
inbound mapping, `TLS_SETTINGS`, the proxy route over phase 5a's resolver with
`PROXY_LIMITATION_EVENT`, and the registration under `REGISTRY_KEY` (`:net_http`) that requiring
the gem performs. Proven on `net-http` 0.4.1, 0.6.0 and 0.9.1 and against the shared conformance
suite in `dexpace-conformance`.

## Install

```ruby
# Gemfile
gem "dexpace-transport-net_http"
```

## The smallest thing that works today

```ruby
require "dexpace/transport/net_http"

adapter = Dexpace::Transport::NetHTTP.build
request = Dexpace::Request.build(method: "GET", url: "http://127.0.0.1:8080/pets?limit=2",
                                 headers: Dexpace::Headers::EMPTY)
response = adapter.call(request, Dexpace::RequestOptions::EMPTY, nil)   # against a server on 8080
response.status.code  # => 200
response.body_string  # => "[]" -- decoded through the one decode boundary, then closed
adapter.close         # => nil
```

A response body streams from the socket until it is drained or closed; `Response#body_string`
does both. `Pipeline.standard(adapter)` puts retry, redirect and authentication around it.

## Depends on

`dexpace-core`, and `net-http >= 0.4` -- a default gem on every supported Ruby, with no upper
bound, and the one gem `NFR-2` budgets for this adapter.

## Where to read next

- `docs/sdk-documentation/transport-net_http.md` -- the as-built page: what the wire carries,
  what streams, what a budget bounds, what a failure means, and what is deliberately not here.
- `docs/sdk-documentation/conformance.md` -- the suite this adapter is proven against, and the
  two things a green run does not prove.
- `docs/sdk-documentation/architecture.md` -- how the gems compose and which one to install.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` -- the gem layout and the
  zero-dependency invariant every gem here is built under.
