# performance

## Rules
- Profile before optimizing and never optimize based on a guess, since intuition about Ruby performance is wrong at least half the time due to non-local interactions between YJIT, GC, object shapes, and the C-extension boundary.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:42-48` · high · sha:57a0098e7a32</sub>
- Capture a profile before changing code and again after the fix, treating the delta as the only proof; store a benchmark in a committed `bench/` file beside the code it guards as a regression guard for future refactors.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:47-47` · high · sha:57a0098e7a32</sub>
- Never optimize a cold path, since the GC's generational minor collection makes short-lived allocation cheap in code the profiler never flags.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:48-48` · high · sha:57a0098e7a32</sub>
- Optimize resources in the fixed order network > disk > memory > CPU, choosing the layer to work on from the profile rather than from reading the code.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:52-57` · high · sha:57a0098e7a32</sub>
- Avoid heavy `method_missing`, `send` with dynamic names, and `define_method` in hot paths, since each defeats the JIT's inline cache and forces a generic dispatch.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:65-65` · high · sha:57a0098e7a32</sub>
- Benchmark with the JIT enabled that will be used in production, since a micro-benchmark run with `--disable-yjit` measures a different runtime and its numbers do not transfer.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:66-66` · high · sha:57a0098e7a32</sub>
- Assign every instance variable a class will ever use inside `initialize`, in one deterministic order, and never conditionally define an ivar outside `initialize`, since that forks the object shape into a transition chain.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:74-74` · high · sha:57a0098e7a32</sub>
- Hoist allocations out of loops and build output into a pre-allocated buffer rather than reallocating, since the GC cost that matters is the allocation rate inside a hot inner loop, not any single allocation.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:100-100` · high · sha:57a0098e7a32</sub>
- Use mutable working strings created with `+""` or `String.new` as reusable buffers, and freeze the final result before returning it across a boundary.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:101-101` · high · sha:57a0098e7a32</sub>
- Build strings with `String#<<` (in-place mutation) rather than `String#+` inside a loop.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:105-110` · high · sha:57a0098e7a32</sub>
- When a string must be immutable at the boundary, build it with `<<` into a mutable buffer and freeze the result after assembly, rather than using `String#+` to avoid mutability.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:110-110` · high · sha:57a0098e7a32</sub>
- Prepend `.lazy` to a chained Enumerable pipeline over large, streamed, or infinite sequences, calling `.first(n)` or `.take(n).to_a` at the end so no intermediate array is materialized before it is needed.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:130-135` · high · sha:57a0098e7a32</sub>
- Do not use `.lazy` on small, finite collections where eager evaluation is clearer and the GC pressure is negligible.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:135-135` · high · sha:57a0098e7a32</sub>
- Prefer `size` as the default length check, reserving `count { |e| predicate }` for the counted-predicate form.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:159-159` · high · sha:57a0098e7a32</sub>
- Use the most specific string method available — following the hierarchy `start_with?`/`end_with?` for prefix/suffix checks, `delete` for character-set removal, `tr` for single-character translation, `sub` for a single exact-string replacement — and reserve `gsub` for genuine regex-pattern global replacement.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:164-169` · high · sha:57a0098e7a32</sub>
- Use `hash.fetch(key) { default }` so the default block evaluates only on a miss, and use `Hash.new { |h, k| h[k] = expensive_default(k) }` to compute and cache a default on first access rather than `hash[key] ||= expensive_default(key)`, which recomputes on every falsy value without caching.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:191-193` · high · sha:57a0098e7a32</sub>
- Collect all ids or keys upfront and issue one bulk query (`WHERE id IN (...)`), indexing the results in memory for O(1) lookup, instead of issuing one query or HTTP request per loop element.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:215-220` · high · sha:57a0098e7a32</sub>
- Use eager loading (`includes`, `preload`, `eager_load`) at the query site to prevent ORM-induced N+1 queries, and confirm the query plan with `bullet` or SQL logs.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:220-220` · high · sha:57a0098e7a32</sub>
- Use symbols rather than strings for all internal hash keys and option labels.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:246-251` · high · sha:57a0098e7a32</sub>
- Convert external string data (JSON, query parameters, environment variables) to symbols once at the entry-point boundary, rather than scattering `to_sym` calls across the codebase.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:251-251` · high · sha:57a0098e7a32</sub>

## Constraints
- Ruby 3.2+ tracks object shapes — the combination of an object's ivar names and their assignment order — and YJIT caches ivar accesses by shape, so two objects of the same class assigning ivars in different orders or subsets get different shapes and YJIT's cache degrades their access to a hash lookup.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:72-73` · high · sha:57a0098e7a32</sub>
- `hash[key] || default` recomputes the default on every miss and mishandles falsy stored values, since a stored `false` or `0` incorrectly triggers the default.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:191-191` · high · sha:57a0098e7a32</sub>

## Conclusions
- Ruby performance is treated as won at design time rather than through micro-optimization, prioritizing knowledge of the resource hierarchy, code that YJIT compiles well, and profiler-identified hot paths over intuition.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:3-3` · high · sha:57a0098e7a32</sub>
- YJIT is kept as the default JIT until ZJIT matches its performance, though ZJIT should be evaluated.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:63-63` · high · sha:57a0098e7a32</sub>

## Reference
- Use `stackprof` for CPU profiling (wall-clock or CPU mode), `memory_profiler` for allocation counts and sources, and `benchmark-ips` for iterations-per-second comparisons of an isolated function on a warm runtime — each answers a different performance question.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:46-46` · high · sha:57a0098e7a32</sub>
- A pull request claiming a performance win must attach before/after numbers (a `stackprof` flamegraph, `benchmark-ips` output, or `memory_profiler` totals) in the description; optimization without a committed profile or benchmark does not merge.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:50-50` · high · sha:57a0098e7a32</sub>
- A network round-trip costs roughly 5-50 milliseconds, which dwarfs a CPU operation costing nanoseconds, so one eliminated query beats a thousand micro-optimizations.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:55-55` · high · sha:57a0098e7a32</sub>
- A CPU micro-fix proposed before a profile has named CPU as the bottleneck is sent back in design review; the slowest resource named by the profile is fixed first.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:59-59` · high · sha:57a0098e7a32</sub>
- YJIT is Ruby's stable production compiler, enabled with `--yjit` or `RUBY_YJIT_ENABLE=1`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:63-63` · high · sha:57a0098e7a32</sub>
- Ruby 4.0 ships ZJIT, YJIT's successor, compiled into the binary but not enabled at runtime by default.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:63-63` · high · sha:57a0098e7a32</sub>
- Benchmarks must capture the `ruby --yjit` baseline; reviewers flag `send`/`method_missing` on measured hot paths and redirect to a direct call or a dispatch table.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:68-68` · high · sha:57a0098e7a32</sub>
- RuboCop and Sorbet `# typed: strict` flag uninitialized ivars; reviewers reject ivar assignments outside `initialize` on objects in hot paths.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:94-94` · high · sha:57a0098e7a32</sub>
- `# frozen_string_literal: true` interns string literals so the same literal produces the same object reference instead of a fresh allocation each time.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:99-99` · high · sha:57a0098e7a32</sub>
- `frozen_string_literal: true` is enforced by RuboCop's `Style/FrozenStringLiteralComment` cop; reviewers flag allocation-per-iteration patterns on measured hot paths.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:103-103` · high · sha:57a0098e7a32</sub>
- `String#+` allocates a new String object on every call, so over N loop iterations the cost is O(N) allocations and up to O(N²) bytes copied, while `String#<<` mutates the receiver in place at O(1) per append.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:108-109` · high · sha:57a0098e7a32</sub>
- RuboCop's `Performance/StringConcatenationInLoop` cop flags `String#+` inside a block or loop body.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:128-128` · high · sha:57a0098e7a32</sub>
- On Ruby `Array`, `Hash`, and `String`, `size` and `length` are aliases performing O(1) cached-length reads; `count` without a block is O(1) on `Array`/`Hash` but on `ActiveRecord::Relation` and many `Enumerable` sources it executes a `SELECT COUNT(*)` or iterates the entire collection.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:157-158` · high · sha:57a0098e7a32</sub>
- On ActiveRecord, `size` checks whether the association is already loaded and returns the cached length if so, falling back to a `COUNT` query only when unloaded, while `count` always issues a query.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:160-160` · high · sha:57a0098e7a32</sub>
- RuboCop's `Performance/Size` cop prefers `size` over `count` for arrays and strings without a block; reviewers replace `count` on already-loaded associations with `size`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:162-162` · high · sha:57a0098e7a32</sub>
- RuboCop's `Performance/StringReplacement`, `Performance/StartWith`, and `Performance/EndWith` cops flag `gsub` used with a string-literal pattern and redirect to the specialized method.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:186-186` · high · sha:57a0098e7a32</sub>
- A loop issuing one query per element transforms O(1) I/O cost into O(N) I/O cost; at N=100 rows and 5ms per round-trip, 500ms of latency is manufactured from nothing.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:218-218` · high · sha:57a0098e7a32</sub>
- The `bullet` gem raises on N+1 queries in development and test; SQL logs in tests catch unintentional N+1 patterns introduced by refactors.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:244-244` · high · sha:57a0098e7a32</sub>
- A symbol is interned as one object for the process lifetime, while a string literal is allocated fresh at every evaluation unless mitigated by `frozen_string_literal: true` — and dynamic strings, JSON string keys, and string construction still allocate regardless.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:249-249` · high · sha:57a0098e7a32</sub>
- RuboCop's `Performance/InefficientHashSearch` and `Style/HashSyntax` cops enforce shorthand symbol hash keys; reviewers flag string keys on internal hashes and option sets.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/15-performance.md:253-253` · high · sha:57a0098e7a32</sub>

## Conflicts

## Superseded
