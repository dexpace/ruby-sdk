# Pagination

**As built by phase 7c, in `dexpace-core`, written against source on 2026-09-20.** This page says what
chapter 12 gives an SDK author today: the page value that owns one live response, the strategy contract
with its three built-in strategies, the byte-for-byte query splice, the two consumption views over one
lazy walk, the blocking engine, the non-blocking engine driven through phase 2's `Future#on_settle`, and
the fetcher-based front-end. What each is *required* to do is `docs/product-spec/12-pagination.md`
(`PAGE-1`–`PAGE-36`); how the design maps it to Ruby is
`docs/sdk-design-ruby/07-pagination-sse-and-serialization.md` §7.1, read together with entry 6 of
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`; the per-requirement proof
is `docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination-checklist.md`, and the phase's own
decisions are the ledger of `docs/work/mvp/phase7/phase7c/2026-09-10-phase7c-pagination-design.md`.
Signatures live in `gems/dexpace-core/sig/dexpace/page.rbs` and `sig/dexpace/page/`, and this page does
not restate them. Every example below was run against the built code on 4.0.6 and 3.2.11 and printed
the same on both. The examples use two test doubles from `gems/dexpace-core/test/support/` —
`ScriptedTransport`, whose script is one reply per call, and its async twin `ScriptedAsyncTransport` —
because a paginator sends through a transport and nothing on this page should talk to a socket; `P` is
`Dexpace::Page` throughout, `req(url)` builds a request, `response(request, headers:)` a response over
a closable body whose `#closes` counts, and `cursor_server` a scripted transport that answers each
request with a response built around it.

**Transport-agnostic and serde-agnostic, and the second is a rule with a gate.** A paginator takes any
object answering `#call(request, options, cancellation)` — a `Pipeline`, a bare adapter, a lambda — and
never closes it (`PIPE-26`, `PIPE-27`: a built pipeline is a transport whose `#close` is a no-op). It
names no serializer: the built-in strategies take a caller-supplied **extractor**, `#call(response)`,
and a caller who wants a codec writes it into that closure, outside core. Nothing under
`lib/dexpace/page/` spells a serializer's name, in code or in comment, and the suite scans for it;
phase 7b's `gates:serde_boundary` is the gate that will hold the row.

## The page value: `Page`

`Dexpace::Page` is one page of a walk and the namespace of the whole subsystem. It is built through
`.build(response:, items:, next_link:, continuation_token:)` over a real `Dexpace::Response` — the two
optional keys nil or a String copied frozen, anything else refused by name — with `.new` private, and it
owns that response: whoever holds the page owns closing it, the close is latched
(`Dexpace::Closeable`, so a second `#close` touches nothing), and it forwards to the response exactly once
(`PAGE-3`, `PAGE-27`). The materialized `#items` (a frozen shallow copy — the collection is the page's,
the elements stay the caller's), `#status`, `#headers` and `#request` are read off frozen values and
stay readable after the close; only the body is invalidated (`PAGE-2`). It is a plain class rather than
a `Data` because a `Data` instance is frozen and cannot hold the latch, and the latch cannot be borrowed
from the response, whose body may be `nil` or a `BufferBody` whose close is a documented no-op.

```ruby
page = P.build(response: response(req("https://api.example/v1/items?page=1")), items: [1, 2])
page.items                                                   # => [1, 2]
page.status.code                                             # => 200
page.close
page.close
page.response.body.closes                                    # => 1
page.items                                                   # => [1, 2]
Dexpace::URL.external_form(page.request.url)                 # => "https://api.example/v1/items?page=1"
```

## The strategy contract: `Info` and the three built-ins

A strategy is any object answering `#parse(response, template) -> Dexpace::Page::Info`, validated with
`respond_to?` and never by a nominal test (the RBS interface is `Dexpace::Page::_Strategy`). It reads
everything it needs synchronously inside `#parse`, retains nothing, closes nothing, and is immutable
(`PAGE-5`); the three built-ins are frozen `Data`s with no instance state at all, so one instance serves
any number of concurrent walks. `Info` carries the page's items and the next request, and **a `nil` next
request is the single end-of-stream signal** — no flag, no sentinel, no exception path (`PAGE-4`);
`Info.terminal(items:)` names that case so an empty items list is never mistaken for it.

```ruby
info = P::Info.build(items: [1], next_request: req("https://api.example/v1/items?page=2"))
info.next_request.url.query                                  # => "page=2"
P::Info.terminal(items: [9]).next_request                    # => nil
P::Info.build(items: [], next_request: req("https://h/")).items # => []
```

**`CursorStrategy.build(extract:, parameter: "cursor")`** (`PAGE-16`) calls the extractor once,
expects `[items, cursor]` back, treats a `nil` or empty cursor as end-of-stream, and otherwise splices
the cursor into the template's query under the parameter name — replacing an earlier value in place,
never appending a second. Core reads the body zero times; an extractor that reads through
`Response#body_string` gets the single-use rule from phase 3b's body (a second read raises
`Dexpace::ClosedError`). An extractor that raises is a parse failure, never an end-of-stream.

```ruby
template = req("https://api.example/v1/items")
cursor = P::CursorStrategy.build(extract: ->(r) { [[r.status.code], r.headers["x-next"]&.first] })
cursor.parse(response(template, headers: { "X-Next" => "c2" }), template).next_request.url.query
# => "cursor=c2"
cursor.parse(response(template), template).next_request      # => nil
cursor.parse(response(template), template).items             # => [200]
```

**`PageNumberStrategy.build(extract_items:, parameter: "page", start: 1)`** (`PAGE-17`) treats an
empty items list as end-of-stream before anything else is computed, reads the current page from the
**executed** request — `response.request`, the final hop after any redirect chain — and falls back to
`start` when the parameter is absent, empty or not a run of ASCII digits (a percent-encoded digit run is
read decoded and counts); `start: 0` serves a 0-based server.

```ruby
numbered = P::PageNumberStrategy.build(extract_items: ->(_r) { [1] })
numbered.parse(response(req("https://api.example/v1/items?page=4")), template).next_request.url.query
# => "page=5"
numbered.parse(response(template), template).next_request.url.query # => "page=2"
P::PageNumberStrategy.build(extract_items: ->(_r) { [] }).parse(response(template), template).next_request
# => nil
```

**`LinkStrategy.build(extract_items:, header: "Link")`** (`PAGE-18`–`PAGE-20`) reads every instance
of the header, joins them, scans them by RFC 8288's grammar — a character-level state machine, not a
regexp, because a comma inside `<…>` or inside a quoted value must not split link-values and a quoted
pair must be honoured — and takes the first link-value whose `rel` carries the token `next`, quoted or
not, in any case; only a link-value's first `rel` parameter is read, as RFC 8288 §3.3 requires, so
`<u>; rel="prev"; rel="next"` is a prev link. The target is resolved against the originating page's
response URL as an RFC 3986 reference (a query-only `<?page=2>` keeps the whole path), and it is
end-of-stream, never an error, when the header or the segment is absent, when the target is a
same-document reference — blank, or fragment-only like `<#top>`, RFC 3986 §4.4's two forms, which would
otherwise re-fetch the current page until the cap — when it cannot resolve, or when it resolves to
something this client cannot dispatch — `mailto:`, `javascript:`, a host-less `http:foo`. That
same-document check reads the raw target, never the resolved URL: `<?>`, `<//>` or the current URL
spelled out are followed like any other next link, and a server that loops through one is bounded by
the cap.

```ruby
link = P::LinkStrategy.build(extract_items: ->(_r) { [1] })
linked = response(req("https://api.example.com/repo/issues?page=1"),
                  headers: { "Link" => '<https://x/9>; rel="last", <?page=2>; rel="next"' })
Dexpace::URL.external_form(link.parse(linked, template).next_request.url)
# => "https://api.example.com/repo/issues?page=2"
link.parse(linked, template).next_link                       # => "?page=2"
link.parse(response(template, headers: { "Link" => "<mailto:a@b>; rel=next" }), template).next_request
# => nil
```

That resolution is public as **`Page.next_request_from(template, response, target)`**, because a next-page
URL carried in the response *body* is the one common shape none of the three built-ins covers, and a
strategy written by hand that re-derives the branch gets the end-of-stream rules quietly wrong. It
answers the template with only its URL swapped — method, headers and body travel unchanged (`PAGE-23`).

```ruby
P.next_request_from(template, response(template), "?page=2").url.query # => "page=2"
P.next_request_from(template, response(template), "   ")     # => nil
P.next_request_from(template, response(template), "#top")    # => nil
```

## The query splice: `QueryRewriter`

`PAGE-21`–`PAGE-24`, as three pure functions over the raw query substring. `.set(query, name, value)`
replaces the first occurrence in place, drops later duplicates, appends when absent and removes when the
value is `nil`; every other segment is copied byte-for-byte — a value-less flag stays value-less,
`filter=a:b` keeps its bare colon — and only the targeted name and value are encoded, with RFC 3986
component encoding (space to `%20`, a literal `+` to `%2B`). `.get(query, name)` decodes with the same
semantics, first match wins, a flag reads as `""`. `.rewrite_url(uri, name, value)` changes the query
and nothing else. Phase 1's `Dexpace::Query` is deliberately not used here: it re-encodes every
parameter, which is the canonicalisation `PAGE-21` forbids; and Ruby's `URI.decode_www_form` /
`encode_www_form_component` are the exact inverse of `PAGE-22`. Removing the only parameter yields a URL
with no `?` at all, not a dangling one (the phase's `P7-4`).

```ruby
QR = P::QueryRewriter
QR.set("flag&filter=a:b&page=1", "page", "2")                # => "flag&filter=a:b&page=2"
QR.set("", "q", "a b")                                       # => "q=a%20b"
QR.set("", "token", "a+b/c=")                                # => "token=a%2Bb%2Fc%3D"
QR.get("q=a+b", "q")                                         # => "a+b"
QR.get("flag", "flag")                                       # => ""
QR.set("page=1&sort=asc", "page", nil)                       # => "sort=asc"
QR.set("page=1", "page", nil)                                # => nil
url = Dexpace::URL.parse!("https://user:pw@h:8443/a/b?flag&page=1#frag")
Dexpace::URL.external_form(QR.rewrite_url(url, "page", "2")) # => "https://user:pw@h:8443/a/b?flag&page=2#frag"
```

The RFC 3986 resolution the Link strategy uses is phase 1's `Dexpace::URL`, widened by one function:
`URL.resolve(base, reference)` wraps the pinned `URI::RFC3986_PARSER.join` and answers `nil` for a
reference that cannot resolve. It is reference resolution and never `SEAM-27`'s base-URL composition,
which `Dexpace::Operation` does by hand because the two disagree on a query-bearing base.

```ruby
base = Dexpace::URL.parse!("https://api.example.com/repo/issues?page=1")
Dexpace::URL.external_form(Dexpace::URL.resolve(base, "?page=2"))
# => "https://api.example.com/repo/issues?page=2"
Dexpace::URL.resolve(base, "not a url")                      # => nil
```

## The blocking engine: `Paginator`, `Items`, `Pages`

`Paginator.build(transport:, template:, strategy:, cap: Float::INFINITY, options: RequestOptions::EMPTY)`
is a frozen `Data` of immutable configuration and nothing else, so one instance is shared freely
(`PAGE-8`). Nothing is fetched until a consumer probes: constructing it, obtaining a view and obtaining
an enumerator all cost zero exchanges, and then exactly one exchange per page consumed (`PAGE-6`). The
per-call `options:` are passed to the transport on **every** page, not only the first (`PAGE-36`); the
cancellation the transport receives is always `Cancellation.none` — the blocking engine takes no
per-walk token in v1. `cap:` counts exchanges, is validated strictly positive at construction
(`PAGE-9`), and defaults to `Float::INFINITY`; **set a finite cap in production**, because it is the
only bound the engine has over a server that never advances its cursor (`PAGE-10`). The `strategy`
every engine example below shares is one cursor strategy that reads the page it is on off the
**executed** request and answers a three-page walk:

```ruby
strategy = P::CursorStrategy.build(extract: lambda { |r|
  case P::QueryRewriter.get(r.request.url.query, "cursor")
  when nil  then [[1, 2], "c2"]
  when "c2" then [[3], "c3"]
  else           [[4], nil]
  end
})
transport = cursor_server
paginator = P::Paginator.build(transport: transport, template: template, strategy: strategy)
paginator.frozen?                                            # => true
paginator.cap                                                # => Infinity
paginator.items; transport.calls.size                        # => 0
paginator.items.to_a                                         # => [1, 2, 3, 4]
transport.calls.size                                         # => 3
transport.calls.map { |(r, _o, _c)| r.url.query }            # => [nil, "cursor=c2", "cursor=c3"]
P::Paginator.build(transport: transport, template: template, strategy: strategy, cap: 0)
# => Dexpace::InvalidArgumentError: cap must be a strictly positive number, got 0 (PAGE-9)
capped = P::Paginator.build(transport: cursor_server(10), template: template, cap: 3,
                            strategy: P::CursorStrategy.build(extract: ->(_r) { [[1], "again"] }))
capped.items.to_a                                            # => [1, 1, 1]
capped.transport.calls.size                                  # => 3
```

**`#items`** is the item-level view: every page's items in server order across page boundaries, over a
fresh walk on every `#each` (so `to_a` twice is two full fetch sequences), with **each page closed
before its first item is yielded** (`PAGE-11`) — which is what makes this view safe under external
iteration, since an `Enumerator` abandoned mid-`#next` never runs its `ensure`: at every point a
consumer can stop, nothing is open. `Items#close` is a documented no-op for the same reason. Both views
`include Enumerable`, so `first`, `take`, `lazy` and `count` work, each spending exactly the exchanges
it consumes.

```ruby
transport2 = cursor_server
paginator2 = paginator.with(transport: transport2)
paginator2.items.first(1)                                    # => [1]
transport2.calls.size                                        # => 1
transport2.calls.first[1].equal?(Dexpace::RequestOptions::EMPTY) # => true
```

**`#pages`** is the page-level view: whole live pages, each open for the length of the consumer's turn,
the previous one closed as the consumer advances and the last at exhaustion (`PAGE-12`). It is
**single-use** — obtaining its iterator a second time raises `Page::PageStateError`, a state error and
never an `ArgumentError` (`PAGE-14`) — and it has a one-slot look-ahead: `#more?` runs an exchange the
first time and stages the page in storage the walk owns, a second probe reads the staged page for free,
and `#close` releases both the held page and the staged one. **Wrap the view in `#each_page`**, or call
`#close` yourself: a page pulled through external iteration and dropped stays open until then, which is
the residue design §7.1 states rather than hides. A close failure while releasing a held page is
surfaced, never swallowed, and when both held pages fail to close the first failure propagates with the
second on its suppressed trail (`PAGE-15`, `Dexpace.suppressed`).

```ruby
transport3 = cursor_server
pages = paginator.with(transport: transport3).pages
pages.more?                                                  # => true
transport3.calls.size                                        # => 1
pages.more?                                                  # => true
transport3.calls.size                                        # => 1
seen = []
pages.each { |pg| seen << [pg.items, pg.closed?] }
seen                                                         # => [[[1, 2], false], [[3], false], [[4], false]]
pages.closed?                                                # => true
pages.each { |_pg| nil }
# => Dexpace::Page::PageStateError: a page view is single-use: its iterator was already obtained (PAGE-14)
opened = []
paginator.with(transport: cursor_server).each_page { |pg| opened << pg; break if pg.items == [1, 2] }
opened.map(&:closed?)                                        # => [true]
```

**`#each_item { }` and `#each_page { }`** are the scoped openers: the same views, driven with a block
that is required, the walk closed on every exit — a return, a `break`, a raise.

A parse failure closes the response inline (the page is never built, so nothing else would) and
propagates as itself; a close failure on that path is attached to the parse error's suppressed trail,
never raised over it (`PAGE-13`). The same order holds for a consumer that raises inside a page loop:
the consumer's error stays primary and the walk's close failure joins its trail. That order is the
opposite of what a bare `ensure` gives in Ruby — a close that raises from an `ensure` *replaces* the
in-flight error — and the frame that owns the walk records the primary explicitly rather than reading
`$!`, which inside a caller's own `rescue` is the caller's unrelated error.

```ruby
raising = P::CursorStrategy.build(extract: ->(_r) { raise KeyError, "no items key" })
P::Paginator.build(transport: cursor_server, template: template, strategy: raising).items.to_a
# => KeyError: no items key                                   (the response closed inline)
```

## The non-blocking engine: `AsyncPaginator`

`AsyncPaginator.build(transport:, template:, strategy:, cap:, options:, executor: nil)` takes an async
transport — `#call(request, options, cancellation) -> Dexpace::Async::Future` — and offers two walk
methods over one pump: **`#walk(consumer, cancellation: nil)`** delivers every item, one at a time and
in server order, to `consumer.call(item)`, never concurrently (`PAGE-29`); **`#walk_pages(consumer,
cancellation: nil)`** delivers each live `Page` once, before it is closed. Both return a
`Dexpace::Async::Future` that settles with the number of pages delivered, or fails with the **original**
cause of a consumer throw, a transport failure, a parse failure or an eager transport raise, unwrapped
(`PAGE-28`). Invoking a walk method is itself the consumption trigger and begins fetching immediately;
there is no lazy obtain step on this engine (`PAGE-6`'s own carve-out).

The engine calls no wait — not `Clock#sleep`, not `Async.delay` — and needs no scheduler, no executor
and no thread: by default whoever settles the transport's future drives the next page, on that thread
or fiber (`PAGE-29`'s stated default). The driver is a re-arm-flag trampoline, never a callback that
calls the next page: `Future#on_settle` runs its block inline on an already-settled future, so a
recursive pump overflows at a few thousand synchronously-answered pages, and this one is flat at any
count (`PAGE-31`). With an `executor:` — any object answering `#post { }`; phase 8's
`dexpace-async-thread` is the first real one — the first dispatch and every continuation are posted to
it, so every consumer invocation runs on the executor and a blocking consumer never ties up a transport
callback thread; a rejecting `#post` fails the walk with the rejection and closes the response it was
carrying (`PAGE-30`).

```ruby
async_transport = ScriptedAsyncTransport.new(Array.new(3) { ->(r, _o, _c) { response(r) } })
async = P::AsyncPaginator.build(transport: async_transport, template: template, strategy: strategy)
seen = []
future = async.walk(->(item) { seen << item })
future.settled?                                              # => true
future.value                                                 # => 3
seen                                                         # => [1, 2, 3, 4]
async_transport = ScriptedAsyncTransport.new(Array.new(3) { ->(r, _o, _c) { response(r) } })
pages_seen = []
async.with(transport: async_transport).walk_pages(->(pg) { pages_seen << [pg.items, pg.closed?] }).value
pages_seen                                                   # => [[[1, 2], false], [[3], false], [[4], false]]
executor = InlineExecutor.new
on_executor = P::AsyncPaginator.build(transport: ScriptedAsyncTransport.new(Array.new(3) { ->(r, _o, _c) { response(r) } }),
                                      template: template, strategy: strategy, executor: executor)
on_executor.walk(->(_i) { nil }).value                       # => 3
executor.posts                                               # => 4
```

Cancelling the returned future halts the walk at the next page boundary and cancels the in-flight
transport future (`PAGE-25`): items already being delivered from the settling page still reach the
consumer, and a page that was fetched and parsed but not yet drained is closed quietly and dropped
(`PAGE-26`). A caller's `cancellation:` token is bridged to the same abort and released when the walk
settles. Each page's response is closed exactly once on whichever path consumes it — after the drain,
when a staged page is dropped, when a re-dispatch is rejected, or inline on a parse failure (`PAGE-27`);
on the drain path a throwing close is reported through the future on the success path and swallowed
when the consumer already failed, so that cause stays primary (`PAGE-32`).

```ruby
deferred = ScriptedAsyncTransport.new(Array.new(3) { ->(r, _o, _c) { response(r) } }, settle_later: true)
future = async.with(transport: deferred).walk(->(_item) { nil })
deferred.calls.size                                          # => 1
future.cancel(:shutting_down)
future.cancelled?                                            # => true
deferred.pending.first.first.future.cancelled?               # => true
one_page = ScriptedAsyncTransport.new([->(r, _o, _c) { response(r) }])
async.with(transport: one_page).walk(->(_i) { raise ArgumentError, "consumer" }).value
# => ArgumentError: consumer                                  (the same object, and the page closed)
```

**The inherent cancellation race, documented as `PAGE-33` requires.** If a cancel settles the
transport's future *before* the transport delivers its response, that response never reaches this
engine's close path: releasing it is the transport's responsibility, and for a future built on phase 2's
`Completer` the completer does it (`Completer#fulfil` on a settled completer closes what it was handed,
`SEAM-30`). Conversely, a page request already dispatched may still complete after the abort, and when
it completes successfully this engine closes and discards the response at the page boundary rather than
delivering it. The first half is not this engine's code; the second is `#walk`'s settled check.

## The fetcher front-end: `Fetchers`

`Fetchers.build(first:, next_page:, options: RequestOptions::EMPTY)` replaces the transport and the
strategy with two caller callables and offers the same `#items`, `#pages`, `#each_item` and
`#each_page` over the same walk (`PAGE-34`). The first-page fetcher is called exactly once per walk;
every later page keys the next-page fetcher off the previous page's `next_link`, falling back to its
`continuation_token` when the link is absent or blank — next link wins; a blank link with no token, or
a `nil` page from either fetcher, ends the stream, and a `nil` first page is an empty stream. Each
fetcher builds a `Page` that owns its response and must not close it — the walk releases it — and a
fetcher that raises before building the page remains responsible for that response. A fetcher that takes
a second parameter is handed the same frozen `options` instance every time, by identity; that is all
`PAGE-35`'s mutable-options clause can mean here, since the port offers no mutable options object (design
§12 calls the clause vacuous rather than declined), and a fetcher that wants per-page state has the
previous page's `continuation_token` and its own closure.

```ruby
front = P::Fetchers.build(
  first: -> { P.build(response: response(template), items: [1, 2], next_link: "/v1/items?after=2") },
  next_page: lambda { |key|
    key == "/v1/items?after=2" ? P.build(response: response(template), items: [3], continuation_token: "t3") : nil
  },
)
front.items.to_a                                             # => [1, 2, 3]
```

## What is deliberately not here

- **No codec, no serializer, no default JSON-flavoured strategy.** The built-ins take an extractor; the
  codec is `dexpace-serde-json`'s (phase 7a) and it belongs in the caller's closure. Nothing under
  `lib/dexpace/page/` names a serializer, and the suite scans for the tokens; phase 7b's
  `gates:serde_boundary` carries the row for this directory.
- **No per-walk cancellation on the blocking engine.** `Paginator` and `Fetchers` take no
  `cancellation:`; the transport receives `Cancellation.none`. A keyword is a widening a later phase can
  add without moving any signature.
- **No wrapper type for `PAGE-15`'s "re-thrown wrapped" clause.** Its antecedent — a stream terminal
  that cannot declare the underlying error type — does not exist in Ruby: a close error from an `ensure`
  reaches the caller unwrapped through `first`, `lazy.first(2)`, an explicit `break` and a plain block
  on every supported interpreter. The other two clauses of the ID are implemented; the vacuity is the
  phase's `P7-1` and `docs/first-release.md`'s `C13`.
- **No wait and no scheduler in the async engine.** No `PAGE` requirement computes or requests a delay,
  so phase 5a's `Async.delay` and its no-scheduler `SeamError` are unreachable from here.
- **No fourth built-in strategy, no logger and no instrumentation event.** Chapter 12 names three
  strategies and no `OBS` vocabulary; a non-dispatchable `rel=next` target is dropped silently as
  end-of-stream, with nothing to emit it through.
- **No redirect following, retry or authentication of its own.** Those are the transport's — hand the
  paginator a `Pipeline.standard(...)` and every page request goes through all three pillars.
