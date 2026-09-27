<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/dexpace-wordmark-dark.svg">
    <img alt="dexpace" src="docs/assets/dexpace-wordmark-light.svg" width="320">
  </picture>
</p>

<h1 align="center">Dexpace Ruby SDK</h1>

[![CI](https://github.com/dexpace/ruby-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/dexpace/ruby-sdk/actions/workflows/ci.yml)
[![Ruby >=3.2](https://img.shields.io/badge/ruby-%3E%3D3.2-red.svg)](https://www.ruby-lang.org/)
[![Types: RBS + Steep](https://img.shields.io/badge/types-RBS%20%2B%20Steep-blue.svg)](https://github.com/soutaro/steep)
[![Lint: RuboCop](https://img.shields.io/badge/lint-RuboCop-blue.svg)](https://rubocop.org/)
![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)

A toolkit for building Ruby HTTP client libraries. It provides frozen, validated request and response
models, a sixteen-stage pipeline on a synchronous and an asynchronous runtime, pluggable transports and
codecs, and the correctness-sensitive plumbing every service client needs: idempotency-aware retry,
redirects that never leak a bearer token cross-origin, RFC 7235/7616 authentication, pagination,
server-sent events and three-state PATCH. Every public constant carries an RBS signature checked by
Steep, and it runs on Ruby 3.2 through 4.0.

The SDK is deliberately **not an HTTP client**, and it does not compete with `faraday` or `httpx` on the
easiest way to fetch a JSON endpoint. It is for authors of generated or hand-written service-client
SDKs. It defines the contracts — a transport, an async transport, a codec, a pagination strategy, a
logging sink — and supplies the models, pipeline steps and observability hooks that surround them; the
networking arrives through a transport gem of your choosing. A transport is any object answering
`#call(request, options, cancellation)`.

## Status

**Pre-release: the v1 roadmap is complete, and nothing is published.** All eleven roadmap phases
(0 through 10) are built and merged — the layers, the adapters, a conformance audit (phase 9) and a
reconciliation of every documented deviation against as-built source (phase 10). The six gems under
`gems/` are every one at `0.0.0`, and no tag has been cut. What remains before the first publish,
what v1 ships without and what would trigger work after it are tracked in
[`docs/first-release.md`](./docs/first-release.md).

## Gems

A Bundler workspace of six gems. `dexpace-core` is a **dependency** of each adapter
(`~> MAJOR.MINOR`), not a peer: Bundler activates one version per process, so the residual risk is
version skew, which each adapter checks against `Dexpace::VERSION` when it registers.

| Gem | Provides | Runtime dependencies |
|---|---|---|
| [`dexpace-core`](./gems/dexpace-core/) | Models, bodies, the pipeline and its seams, retry, redirect and authentication, SSE, pagination, serialization, configuration, logging, tracing and metrics | **none** |
| [`dexpace-transport-net_http`](./gems/dexpace-transport-net_http/) | `Dexpace::Transport::NetHTTP` — the synchronous transport over `Net::HTTP` | `net-http >= 0.4` (a default gem) |
| [`dexpace-transport-async_http`](./gems/dexpace-transport-async_http/) | `Dexpace::Transport::AsyncHTTP` — the asynchronous transport over `async-http`, HTTP/1.1 and HTTP/2 | `async-http ~> 0.104` (Ruby >= 3.3) |
| [`dexpace-serde-json`](./gems/dexpace-serde-json/) | `Dexpace::Serde::JSON` — the JSON codec over `JSON::Coder`, registered under `:json` | `json >= 2.19.9` |
| [`dexpace-async-thread`](./gems/dexpace-async-thread/) | `Dexpace::Async::Thread::Pool` — a bounded, non-blocking thread-pool executor for the async path | none |
| [`dexpace-conformance`](./gems/dexpace-conformance/) | The suites every adapter is proven against — transport, cross-cutting invariants, packaging, codec and executor | none |

Every adapter depends on `dexpace-core` plus at most one third-party gem (`NFR-2`). A consumer on
Ruby 3.2 composes every gem but `dexpace-transport-async_http`, whose dependency closure needs 3.3.

Install the core plus whichever transport and codec you need:

```ruby
# Gemfile
gem "dexpace-core"
gem "dexpace-transport-net_http"
gem "dexpace-serde-json"
```

## Quick start

### A minimal request

```ruby
require "dexpace"
require "dexpace/transport/net_http"

transport = Dexpace::Transport::NetHTTP.build

builder = Dexpace::Request.builder
builder.url = "https://api.example.test/pets?limit=2"
request = builder.header("Accept", "application/json").build   # GET, because there is no body

response = transport.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
response.status.code   # => 200
response.body_string   # => "[{\"name\":\"Rex\"}]" -- decoded once by charset, and the body closed
transport.close
```

A response body streams from the socket until it is drained or closed, and the caller owns it:
`#body_string` and `#body_bytes` do both, and `Response#close` releases it unread.

### A POST with a JSON body

```ruby
require "dexpace/serde/json"

builder = Dexpace::Request.builder
builder.method = "POST"
builder.url = "https://api.example.test/pets"
builder.body = Dexpace::Body.serialized({ "name" => "Rex" }, serde: Dexpace::Serde::JSON.default)
request = builder.build   # the body carries application/json; the transport stamps Content-Type
```

### A configured pipeline

`Pipeline.standard` installs the redirect, retry and logging pillars in their fixed stage order. Hand
it a `Pipeline::Builder` instead of a transport to add your own steps first — here the AUTH pillar with
a bearer token that is fetched once, cached, and refreshed thirty seconds before it expires, with
concurrent callers sharing one refresh.

```ruby
class TokenProvider
  def fetch = Dexpace::Auth::BearerToken.build(token: mint_token, expiry: Time.now + 3600) # mint_token: yours
end

auth = Dexpace::Auth::Step.build(stamper: Dexpace::Auth::BearerStamper.new(provider: TokenProvider.new))

client = Dexpace::Pipeline.standard(
  Dexpace::Pipeline.builder(transport: Dexpace::Transport::NetHTTP.build).append(auth),
  settings: Dexpace::Resilience::RetrySettings.build(max_retries: 4),
  redirect: Dexpace::Redirect::Step.build(max_hops: 3),
)
client.entries.map { |entry| entry.stage.name }   # => [:redirect, :retry, :auth, :logging]

response = client.call(request)   # a Pipeline is itself a transport
```

Redirect wraps retry wraps auth, so a retried attempt re-stamps its credential and a redirect hop is
judged cross-origin against the **original** request before anything is stamped on it. The builder
enforces the stage order and the one-step-per-pillar rule, and supports surgical edits —
`#insert_before`, `#insert_after`, `#replace`, `#remove` — anchored on a step's class or `name:`.

### Streaming and replayable bodies

```ruby
Dexpace::Body.bytes("\x01\x02\x03".b)                                     # replayable
Dexpace::Body.string('{"hello":"world"}', media_type: "application/json")  # replayable
Dexpace::Body.file("upload.bin", offset: 0, count: 4096)                   # replayable; a fresh handle per write
Dexpace::Body.form([["q", "a b"]])                                         # replayable
Dexpace::Body.chunked(enumerable)                                          # single-use, always
Dexpace::Body.stream(io, close: true)                                      # single-use: a retry cannot re-send it
```

A `StreamBody` over a seekable stream of known length that it does not own is replayable; one that
owns and closes its stream is not. Buffering an arbitrarily large upload to make it retryable is a
decision for the caller who knows how large it is, so the retry step re-sends only a body that already
said it could be re-sent.

### Pagination

```ruby
strategy = Dexpace::Page::CursorStrategy.build(
  extract: ->(response) { [JSON.parse(response.body_string), response.headers["x-next"]&.first] },
)
paginator = Dexpace::Page::Paginator.build(transport: client, template: request, strategy: strategy)

paginator.items.each { |item| process(item) }   # lazy, item by item; every page closed behind it
paginator.each_page { |page| page.items }        # or page by page
```

`CursorStrategy`, `PageNumberStrategy` and `LinkStrategy` (RFC 8288 `Link: rel="next"`) ship in core;
each takes an extractor, so no strategy depends on a codec. `AsyncPaginator` walks the same strategies
over an async transport, optionally on an executor such as `Dexpace::Async::Thread::Pool`.

### Server-sent events

```ruby
Dexpace::SSE::Stream.open(client.call(request)).each do |event|
  event.event   # => "tick", or nil for an unnamed event
  event.data    # => ["1"] -- one entry per data: line
end
```

The stream owns the response and closes it at the end, on `break` and on failure. Lines and events are
capped (1 MiB and 8 MiB by default) and rejected rather than truncated, and `#typed` maps each event to
your own model with `SKIP` and `DONE` as the two sentinel outcomes.

### Three-state PATCH

```ruby
T = Dexpace::Serde::Tristate

class PetPatch
  def initialize(name:, nick:) = (@name = name; @nick = nick)
  def dexpace_dump = { "name" => @name, "nick" => @nick }
end

json = Dexpace::Serde::JSON.default
json.dump_string(PetPatch.new(name: "Rex", nick: T::ABSENT))   # => "{\"name\":\"Rex\"}"
json.dump_string(PetPatch.new(name: "Rex", nick: T::NULL))     # => "{\"name\":\"Rex\",\"nick\":null}"
```

`Tristate` distinguishes absent, null and present, so "leave it alone" and "clear it" stop being the
same wire message. The omission is core's encode walk, not each model's `#dexpace_dump`.

### The asynchronous path

```ruby
require "async"
require "dexpace/transport/async_http"

Sync do
  transport = Dexpace::Transport::AsyncHTTP.build
  client = Dexpace::AsyncPipeline.standard(transport, redirect: :unsupported)

  response = client.call(request).value   # a Dexpace::Async::Future, awaited on the reactor
  response.body_string
ensure
  transport&.close
end
```

The async transport needs a running reactor on the calling thread and creates none. The async pipeline
follows no redirects at the pipeline layer, and says so with a required keyword.

## Architecture

A request flows down through ordered steps and back up through their post-processing. The terminal
stage hands it to a transport.

```
caller → Pipeline ──┬─ PRE_REDIRECT · REDIRECT · POST_REDIRECT
                    ├─ PRE_RETRY    · RETRY    · POST_RETRY
                    ├─ PRE_AUTH     · AUTH     · POST_AUTH
                    ├─ PRE_LOGGING  · LOGGING  · POST_LOGGING
                    ├─ PRE_SERDE    · SERDE    · POST_SERDE
                    └─ SEND → transport → wire
```

Sixteen stages in `Dexpace::Pipeline::Stages::ALL`, a closed set with no public constructor. Five of
them — `REDIRECT`, `RETRY`, `AUTH`, `LOGGING`, `SERDE` — are **pillars**: each admits exactly one step
and refuses a second. The `PRE_` and `POST_` stages around them stack, and are the extension slots.

A step is `#call(request, cursor)`. It drives the rest of the pipeline once through `Cursor#call`, or
forks for every drive through `Cursor#fork` — which is how retry and redirect re-send, and how the
redirect step's cross-origin marker reaches the AUTH step as cursor state that no request header and no
server-supplied `Location` can forge. `Pipeline` and `AsyncPipeline` are themselves transports, so a
pipeline is substitutable wherever a transport is.

Bottom-up, the layers are:

1. **Bytes.** `Dexpace::IO` — a FIFO `Buffer`, `BufferedSource` and `BufferedSink`, `TeeSink`. Bytes on
   the wire are always `Encoding::BINARY`, and `Response#body_string` is the one decode boundary.
2. **Bodies.** A request `Body` writes itself to a sink and says whether a retry may re-send it. A
   response body is single-use and owned by the caller.
3. **Models.** `Request`, `Response`, `Headers`, `Query`, `RequestOptions` and the value types are
   `Data`, frozen at construction and validated in their constructors, derived through `#with` or
   `#new_builder` and never mutated.
4. **Context.** `DispatchContext` promotes to `RequestContext` then `ExchangeContext`, carrying one
   instrumentation bundle; the diagnostic context travels in `Fiber[]` storage.
5. **Pipeline.** `Stage`, `Step`, `Cursor`, `Builder`, `Pipeline`, `AsyncPipeline`.
6. **Transport.** `#call(request, options, cancellation)`, and `#close`. That is the whole contract.

## Inside `dexpace-core`

| Namespace | Surface |
|---|---|
| `Dexpace::` (HTTP) | `Request`, `Response`, `Headers`, `HeaderName`, `Status`, `Method`, `Protocol`, `MediaType`, `Query`, `RequestOptions`, `URL`, `Operation` |
| `Dexpace::` (bodies) | `Body` and its factories — `bytes`, `string`, `file`, `stream`, `chunked`, `form`, `multipart`, `serialized` — `ResponseBody`, the logging body wrappers, `TypedResponse` |
| `Dexpace::IO` | `Buffer`, `BufferedSource`, `BufferedSink`, `TeeSink`, `max_materialized_bytes` |
| `Dexpace::Pipeline` | `Stages`, `Stage`, `Step`, `Entry`, `Cursor`, `Builder`, `.standard`; `Dexpace::AsyncPipeline` beside it |
| `Dexpace::Resilience` | `Policy`, `RetrySettings`, `RetryStep`, `AsyncRetryStep`, `RecoveryRetry`, `Resend` — backoff with jitter, `Retry-After` and rate-limit pacing, an injectable `Clock` |
| `Dexpace::Redirect` | `Step`, `ConditionSnapshot` — loop detection, hop cap, downgrade guard, credential stripping |
| `Dexpace::Auth` | `Step`, `AsyncStep`, `BearerStamper`, `AsyncBearerStamper`, `KeyStamper`, `BasicHandler`, `DigestHandler`, `ChallengeHandlerChain`, `Challenges`, the four credentials, `Descriptor`, `Resolver` |
| `Dexpace::Serde` | the witness protocol, `DecodeContext`, `List` / `Map` / `Nullable`, `Tristate`, `Native`, `Instant`, `DecodingHandler`, `StatusAwareHandler` |
| `Dexpace::SSE` | `Stream`, `TypedStream`, `Event`, `Reader`, `LineReader`, `SKIP` / `DONE` |
| `Dexpace::Page` | `Paginator`, `AsyncPaginator`, `CursorStrategy`, `PageNumberStrategy`, `LinkStrategy`, `Items`, `Pages`, `Fetchers` |
| `Dexpace::Recovery` | `Orchestrator`, `RequestChain`, `ResponseChain`, the `Outcome` pair, `ProtocolError`, the suppressed-exception trail |
| `Dexpace::Instrumentation` | `Logger`, `Event`, `Redactor`, `RedactionPolicy`, `HTTPLogging`, `Tracing`, `Scope`, `HTTPTracer`, `Bundle`, the no-op singletons |
| `Dexpace::` (configuration) | `Configuration`, `Dexpace.configure`, `Clock`, `Proxy`, `HTTPDate`, `UUID`, `BuildInfo` |
| `Dexpace::` (seams) | `Transport`, `AsyncTransport`, `Serde`, `Registry`, `Async::Future` / `Completer`, `Cancellation`, `Closeable` |

## Highlights

- **Zero runtime dependencies, and it is a gate.** `dexpace-core.gemspec` declares no `add_dependency`
  line, and core `require`s only stdlib that stays stdlib on every Ruby from 3.2 to 4.0 — Ruby's
  standard library shrinks between releases, so a parsed require scan checks every spelling against an
  allowlist, and a scratch-`Gemfile` run on every interpreter proves core loads alone.
- **Immutable models, validated where they are built.** Every model is a frozen `Data` whose
  constructor validates; collections are copied and frozen once, and header names and values are
  validated again inside every transport, so a forged model cannot smuggle a CRLF onto the wire.
- **Pluggable everything, by duck type.** A transport, a codec, a pagination strategy, a logging sink,
  a tracer, a meter and a clock are each a small method protocol with an RBS interface. Nothing needs
  an install step; a transport or codec gem registers itself when required.
- **Retry done right.** Exponential backoff with jitter, server pacing hints (`Retry-After`,
  `X-RateLimit-Reset`) in a fixed precedence, idempotency and body replayability checked before any
  re-send, cancellation never retried, and deterministic tests through an injectable `Clock`.
- **Redirects done right.** Loop detection, a hop cap, `Authorization` stripped before every re-issue,
  `Cookie` and `Proxy-Authorization` stripped cross-origin, HTTPS→HTTP downgrade refused by default, and
  userinfo cleared from every `Location`.
- **Real auth.** Bearer tokens with single-flight refresh, an RFC 7235 `WWW-Authenticate` parser, RFC
  7616 Digest (MD5, MD5-sess, SHA-256, SHA-256-sess), Basic and API-key credentials — refused over
  plaintext, and redacted in `#to_s`, `#inspect` and `pp`.
- **No interrupts.** `Timeout.timeout`, `Thread#raise` and `Thread#kill` are banned by a custom cop.
  Deadlines are explicit values handed to the transport's own timeouts, and cancellation is a token.
- **Sync and async from one core.** The same steps and policies run on the blocking `Pipeline` and the
  future-returning `AsyncPipeline`, over `Net::HTTP`, `async-http` or a thread pool.
- **Observability that costs nothing when off.** The no-op logger, tracer and meter are frozen
  singletons, measured at zero allocations per call. Redaction happens on the way into the log record,
  by field name, before any sink sees it.
- **Proven, not asserted.** `dexpace-conformance` runs the same 34 transport assertions against both
  transports on a real socket, plus the cross-cutting invariant, packaging, codec and executor suites.

## Development

A Bundler workspace. `.ruby-version` pins the development Ruby; supported Ruby is 3.2 through 4.0.

```bash
git clone https://github.com/dexpace/ruby-sdk.git
cd ruby-sdk
bundle install          # Gemfile.lock is not committed; each Ruby resolves its own
```

```bash
bundle exec rake                                  # all twenty-four gates, in CI's order
bundle exec rake gates:list                       # their names
bundle exec rake rubocop                          # findings fatal, custom cops included
bundle exec rake rbs:validate steep               # RBS signatures and Steep over six targets
bundle exec rake test:gems                        # every gem's suite under ruby -w, 80% coverage floor
(cd gems/dexpace-core && bundle exec rake test)   # one gem's suite
```

Twenty-four blocking gates in one `bundle exec rake` — RuboCop with custom cops, `ruby -w` with
warnings fatal, RBS and Steep, the RBS and runtime public-surface locks, an 80% coverage floor, the
zero-dependency audits on `dexpace-core`, the repository-wide invariant scans, YARD and
`bundler-audit` — each proven by a deliberately failing input
([`docs/sdk-documentation/quality-gates.md`](./docs/sdk-documentation/quality-gates.md)). CI runs the
real suite on Ruby 3.2, 3.3, 3.4 and 4.0, not a syntax check, because a target Ruby version catches
syntax and not stdlib availability ([`.github/workflows/ci.yml`](./.github/workflows/ci.yml)).

## Conventions

The full contract is in [`CLAUDE.md`](./CLAUDE.md); the documentation map is
[`docs/README.md`](./docs/README.md). The short version:

- **Spec-driven, not feature-driven.** [`docs/product-spec/`](./docs/product-spec/) is normative and
  numbered; the code exists to satisfy it. Before implementing anything, find the requirement IDs.
- **`Data.define` is the base.** Every model is frozen on construction, validated in `#initialize`,
  built through `.build` or a builder, and derived through `#with`, which routes through validation
  on every Ruby.
- **Public means documented and typed.** A public constant has a YARD block and an RBS signature in
  its gem's `sig/`, which mirrors `lib/` one file per file and ships inside the gem.
- **Typed errors only.** Every core error includes the `Dexpace::Error` module, so
  `rescue Dexpace::Error` matches and `Dexpace::TransportError` can still be an `::IOError`.
- **Every source file opens with an SPDX header** and `# frozen_string_literal: true`.
- **Every gap is routed to its owner.** Work for the release goes to
  [`docs/first-release.md`](./docs/first-release.md); a deliberate divergence from the reference
  contract goes to the deviation ledger, audited by [`docs/deviations.md`](./docs/deviations.md).
  Silent gaps are the failure mode this project is structured to prevent.

As-built documentation — one page per layer and adapter, and how the gems compose — starts at
[`docs/sdk-documentation/architecture.md`](./docs/sdk-documentation/architecture.md). Each gem's own
README says how to use it. [`CONTRIBUTING.md`](./CONTRIBUTING.md) is the contribution flow and
[`SECURITY.md`](./SECURITY.md) how to report a vulnerability.

## Releases

Every gem is at version `0.0.0`, and the first release starts from that version. `VERSIONS` at the
repository root is the single source of every gem's version, read by each gemspec.

Publishing is blocked at this time. There is no release workflow yet, and the release path is not
defined. Before the first `gem push`:

1. RubyGems ownership must be settled for every gem name, and trusted publishing configured —
   OIDC-based, with no long-lived API key committed anywhere.
2. The release path must sign what it publishes (`NFR-16`) and publish artifacts byte-identical to a
   rebuild from their tag (the release half of `NFR-12`; the build half is already a gate).

[`docs/first-release.md`](./docs/first-release.md) records both, with every other blocker before the
first publish.

## License

MIT — see [`LICENSE`](./LICENSE). Every gem ships a byte-identical copy.
