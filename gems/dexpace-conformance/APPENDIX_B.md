# Appendix B coverage map

One row per item of `docs/product-spec/appendix-b-conformance-test-checklist.md` — sixty-one, in
the specification's own order — naming the requirement IDs that item exercises, the evidence that
covers it, and a status.

Regenerate the ID column and the row set with `ruby tools/appendix_b.rb`. The generator reads this
file first and carries every hand-written **Evidence** and **Status** cell over, so a row's
judgement survives a regeneration and a dropped or added checklist item does not.

## The statuses

| Status | What it means |
|---|---|
| `suite` | An assertion in `dexpace-conformance`: this gem's own, portable across implementations of one seam |
| `by reference` | A test file in the gem that owns the subsystem. **See the limit below.** |
| `restated per §9.3` | Design §9.3 restates the item for this port, and the restatement is what is checked |
| `scoped out` | This port declines the item or a clause of it, with the reason in the row |

## What the checks over this map establish, and what they do not

Three checks run in `test/gates/appendix_b_test.rb`:

1. the table has **exactly** as many rows as appendix B has items, and each section's count matches
   the count parsed from the specification's own text;
2. every row's **ID column equals** the ID set parsed from that item's own text — 276 distinct IDs
   over the 61 items, no ID in two items, at most 12 in one — so no row can be wrong about which
   requirements its item covers, and every ID appendix B names is in some row by construction;
3. every row's **evidence path exists** on disk.

**What they do not establish: that a referenced test asserts the behaviour the item describes.** A
`by reference` row's evidence is a test file in a gem this phase does not own, and nothing makes a
test file announce which appendix-B item it covers. Such a row proves an ID is *claimed* and a file
*exists* — never more (design `P9-7`). `Aggregate::PREAMBLE` says the same thing about a green
suite run, so a reader who meets only one of the two documents is still told.

**The closing condition, priced and deferred rather than overlooked.** The gap shrinks as the
`by reference` rows do, and the event that makes shrinking them worth its cost is the one
`docs/first-release.md` § Post-release triggers already records for lifting `B.1`, `B.2` and `B.5`:
**a second implementation** of the pagination engine, the SSE reader or the configuration chain.
Until that fires, the only other route is a per-section ID reconciliation done by hand once and then
checked — a piece of work rather than a line, which phase 9 does not take.

## Why `B.1`, `B.2` and `B.5` are `by reference`

§9.3's argument for shipping `dexpace-conformance` as a gem is portability across *implementations
of one seam*: "the *same* assertions could not run unchanged against `dexpace-transport-async_http`
or a future `httpx` adapter — which is the whole point." Pagination, SSE and the configuration chain
have exactly one implementation each, and `PAGE-8` makes the pagination engine stateless and
shareable rather than pluggable. A lifted assertion over a single subject is not more true for
having moved gems; it is a test with one subject living in a package whose purpose is many, and it
costs a second file to keep in step (`P9-1`).

| Section | Item | IDs | Evidence | Status |
|---|---|---|---|---|
| B.1 | 1 | PAGE-1, PAGE-2, PAGE-3 | gems/dexpace-core/test/dexpace/page/paginator_test.rb | by reference |
| B.1 | 2 | PAGE-6, PAGE-7, PAGE-8 | gems/dexpace-core/test/dexpace/page/walk_test.rb | by reference |
| B.1 | 3 | PAGE-9, PAGE-10 | gems/dexpace-core/test/dexpace/page/walk_test.rb | by reference |
| B.1 | 4 | PAGE-11, PAGE-12, PAGE-14, PAGE-15 | gems/dexpace-core/test/dexpace/page/lifetime_test.rb | by reference |
| B.1 | 5 | PAGE-13 | gems/dexpace-core/test/dexpace/page/lifetime_test.rb | by reference |
| B.1 | 6 | PAGE-16, PAGE-17, PAGE-18, PAGE-20, PAGE-19 | gems/dexpace-core/test/dexpace/page/link_strategy_test.rb | by reference |
| B.1 | 7 | PAGE-21, PAGE-22, PAGE-23, PAGE-24 | gems/dexpace-core/test/dexpace/page/query_rewriter_test.rb | by reference |
| B.1 | 8 | PAGE-25, PAGE-26, PAGE-27, PAGE-28, PAGE-29, PAGE-30, PAGE-31, PAGE-32, PAGE-33 | gems/dexpace-core/test/dexpace/page/async_paginator_test.rb | by reference |
| B.1 | 9 | PAGE-34, PAGE-35 | gems/dexpace-core/test/dexpace/page/fetchers_test.rb | by reference |
| B.1 | 10 | PAGE-36 | gems/dexpace-core/test/dexpace/page/paginator_test.rb | by reference |
| B.2 | 1 | SSE-1, SSE-2, SSE-3, SSE-4, SSE-5, SSE-6, SSE-7, SSE-8, SSE-9, SSE-10, SSE-11, SSE-12 | gems/dexpace-core/test/dexpace/sse/reader_test.rb | by reference |
| B.2 | 2 | SSE-13, SSE-14, SSE-15, SSE-16, SSE-17, SSE-18, SSE-19 | gems/dexpace-core/test/dexpace/sse/boundaries_test.rb | by reference |
| B.2 | 3 | SSE-20, SSE-21, SSE-22 | gems/dexpace-core/test/dexpace/sse/event_test.rb | by reference |
| B.2 | 4 | SSE-23, SSE-24, SSE-25, SSE-26, SSE-27, SSE-28, SSE-29, SSE-30, SSE-31, SSE-32 | gems/dexpace-core/test/dexpace/sse/stream_test.rb | by reference |
| B.2 | 5 | SSE-33, SSE-34, SSE-35, SSE-36 | gems/dexpace-core/test/dexpace/sse/typed_stream_test.rb | by reference |
| B.2 | 6 | SSE-37, SSE-38, SSE-39, SSE-40, SSE-41 | tools/serde_boundary.rb | suite |
| B.3 | 1 | SERDE-1, SERDE-2 | gems/dexpace-serde-json/test/dexpace/serde/json/codec_test.rb | by reference |
| B.3 | 2 | SERDE-3, SERDE-4 | gems/dexpace-conformance/lib/dexpace/conformance/codec_suite.rb | suite |
| B.3 | 3 | SERDE-5, SERDE-6, SERDE-7, SERDE-8 | gems/dexpace-core/test/dexpace/serde/witness_test.rb | restated per §9.3 |
| B.3 | 4 | SERDE-9, SERDE-10, SERDE-11, SERDE-12, SERDE-13 | gems/dexpace-conformance/lib/dexpace/conformance/codec_suite.rb | suite |
| B.3 | 5 | SERDE-14, SERDE-15, SERDE-16, SERDE-17, SERDE-18, SERDE-19, SERDE-20, SERDE-30 | gems/dexpace-core/test/dexpace/serde/tristate_test.rb | by reference |
| B.3 | 6 | SERDE-21, SERDE-22, SERDE-23, SERDE-24, SERDE-25, SERDE-26, SERDE-29 | gems/dexpace-core/test/dexpace/serde/scalars_test.rb | by reference |
| B.3 | 7 | SERDE-27, SERDE-28 | gems/dexpace-serde-json/test/dexpace/serde/json/codec_load_test.rb | by reference |
| B.4 | 1 | OBS-1, OBS-2, OBS-3, OBS-4, OBS-5, OBS-6, OBS-7, OBS-8, OBS-9, OBS-40 | gems/dexpace-core/test/dexpace/instrumentation/event_test.rb | by reference |
| B.4 | 2 | OBS-10 | gems/dexpace-core/test/dexpace/instrumentation/diagnostics_test.rb | by reference |
| B.4 | 3 | OBS-11, OBS-12, OBS-13, OBS-14, OBS-15, OBS-16, OBS-17, OBS-18, OBS-19 | gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite/security.rb | suite |
| B.4 | 4 | OBS-20 | gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite/security.rb | suite |
| B.4 | 5 | OBS-21, OBS-22, OBS-23, OBS-24, OBS-25 | gems/dexpace-conformance/lib/dexpace/conformance/recording_span.rb | restated per §9.3 |
| B.4 | 6 | OBS-26, OBS-27, OBS-28, OBS-29, OBS-30 | gems/dexpace-core/test/dexpace/instrumentation/http_tracer_test.rb | by reference |
| B.4 | 7 | OBS-31, OBS-32, OBS-33 | gems/dexpace-core/test/dexpace/instrumentation/meter_test.rb | by reference |
| B.4 | 8 | OBS-34, OBS-35, OBS-36, OBS-37, OBS-38, OBS-39 | gems/dexpace-core/test/dexpace/instrumentation/step_test.rb | by reference |
| B.5 | 1 | CFG-1, CFG-2, CFG-3, CFG-4, CFG-38 | gems/dexpace-core/test/dexpace/configuration_test.rb | restated per §9.3 |
| B.5 | 2 | CFG-5, CFG-6, CFG-7 | gems/dexpace-core/test/dexpace/configuration_test.rb | by reference |
| B.5 | 3 | CFG-8, CFG-9, CFG-10, CFG-11, CFG-12, CFG-13, CFG-14, CFG-37 | gems/dexpace-core/test/dexpace/config_test.rb | by reference |
| B.5 | 4 | CFG-15, CFG-16, CFG-17, CFG-18, CFG-19, CFG-20, CFG-21 | gems/dexpace-core/test/dexpace/clock_test.rb | by reference |
| B.5 | 5 | CFG-22, CFG-23, CFG-24, CFG-25, CFG-26, CFG-27, CFG-28 | gems/dexpace-core/test/dexpace/proxy_test.rb | by reference |
| B.5 | 6 | CFG-29, CFG-30, CFG-31, CFG-32, CFG-33, CFG-34, CFG-35, CFG-36 | gems/dexpace-core/test/dexpace/http_date_test.rb | by reference |
| B.6 | 1 | TRANSPORT-1, TRANSPORT-2 | gems/dexpace-conformance/lib/dexpace/conformance/transport_suite/outbound.rb | suite |
| B.6 | 2 | TRANSPORT-3, TRANSPORT-4, TRANSPORT-5, TRANSPORT-6, TRANSPORT-7, TRANSPORT-8, TRANSPORT-9 | gems/dexpace-conformance/lib/dexpace/conformance/transport_suite/resilience.rb | suite |
| B.6 | 3 | TRANSPORT-10, TRANSPORT-11, TRANSPORT-12, TRANSPORT-13, TRANSPORT-14 | gems/dexpace-conformance/lib/dexpace/conformance/transport_suite/header_drops.rb | suite |
| B.6 | 4 | TRANSPORT-15, TRANSPORT-16, TRANSPORT-17, TRANSPORT-18, TRANSPORT-19 | gems/dexpace-conformance/lib/dexpace/conformance/transport_suite/lifecycle.rb | suite |
| B.6 | 5 | TRANSPORT-20, TRANSPORT-21, TRANSPORT-22, TRANSPORT-23, TRANSPORT-24, TRANSPORT-25, TRANSPORT-26, TRANSPORT-27, TRANSPORT-28, TRANSPORT-29, TRANSPORT-30 | gems/dexpace-conformance/lib/dexpace/conformance/transport_suite/streaming.rb | suite |
| B.7 | 1 | ASYNC-1, ASYNC-2 | gems/dexpace-async-thread/test/dexpace/async/thread/pool_test.rb | by reference |
| B.7 | 2 | ASYNC-3, ASYNC-4, ASYNC-5, ASYNC-6, ASYNC-7 | gems/dexpace-conformance/lib/dexpace/conformance/executor_suite/shutdown.rb | suite |
| B.7 | 3 | ASYNC-8, ASYNC-9, ASYNC-10, ASYNC-11, ASYNC-12 | gems/dexpace-async-thread/test/dexpace/async/thread/pool_diagnostics_test.rb | by reference |
| B.7 | 4 | ASYNC-13, ASYNC-14 | gems/dexpace-async-thread/test/dexpace/async/thread/bridge_test.rb | scoped out |
| B.7 | 5 | ASYNC-15, ASYNC-16, ASYNC-17 | gems/dexpace-conformance/lib/dexpace/conformance/executor_suite/lifecycle.rb | suite |
| B.7 | 6 | ASYNC-18, ASYNC-19, ASYNC-20, ASYNC-21, ASYNC-22 | gems/dexpace-transport-async_http/test/dexpace/transport/async_http/adapter_test.rb | by reference |
| B.8 | 1 | XCUT-1, XCUT-2, XCUT-3 | gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite/concurrency.rb | suite |
| B.8 | 2 | XCUT-4, XCUT-5, XCUT-6, XCUT-7, XCUT-8, XCUT-9 | gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite/taxonomy.rb | suite |
| B.8 | 3 | XCUT-10 | gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite/classification.rb | suite |
| B.8 | 4 | XCUT-11, XCUT-12, XCUT-13, XCUT-22, XCUT-23 | gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite/sharing.rb | suite |
| B.8 | 5 | XCUT-14, XCUT-15 | gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite/memory.rb | suite |
| B.8 | 6 | XCUT-16, XCUT-17, XCUT-18, XCUT-19, XCUT-20, XCUT-21, XCUT-24 | gems/dexpace-conformance/lib/dexpace/conformance/invariant_suite/credentials.rb | suite |
| B.9 | 1 | NFR-1, NFR-2 | gems/dexpace-conformance/lib/dexpace/conformance/packaging_suite/dependencies.rb | suite |
| B.9 | 2 | NFR-3, NFR-4 | gems/dexpace-conformance/lib/dexpace/conformance/packaging_suite/surface.rb | suite |
| B.9 | 3 | NFR-5, NFR-6, NFR-7, NFR-17 | Rakefile | restated per §9.3 |
| B.9 | 4 | NFR-8, NFR-9 | docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md | scoped out |
| B.9 | 5 | NFR-10 | gems/dexpace-conformance/lib/dexpace/conformance/packaging_suite/dependencies.rb | suite |
| B.9 | 6 | NFR-11 | gems/dexpace-conformance/lib/dexpace/conformance/packaging_suite/surface.rb | suite |
| B.9 | 7 | NFR-12, NFR-13, NFR-14, NFR-15, NFR-16 | gems/dexpace-conformance/lib/dexpace/conformance/packaging_suite/dependencies.rb | suite |
