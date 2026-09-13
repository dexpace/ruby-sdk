## 9. Toolchain and Quality Gates

Every gate the reference build enforces has a Ruby counterpart, and each is wired as a blocking CI step the way the
reference's single build command blocks on all of them together (**NFR-17**). The default `rake` task runs the whole
set locally, so a gate cannot be an opt-in job nobody runs.

| Reference gate | Ruby gate |
|---|---|
| Style/static analysis, findings fatal (**NFR-7**) | RuboCop with `rubocop-minitest` and `rubocop-performance`, `--fail-level=convention`, waivers only as scoped inline directives with a reason |
| Warnings as errors (**NFR-6**) | `ruby -w` for the test task plus `RUBYOPT=-W:deprecated`, with warnings failing the build |
| Explicit public API mode (**NFR-3**) | Every public entity has an RBS signature in `sig/`; `rbs validate` plus `steep check` gate it |
| API-surface snapshot (**NFR-4**) | `sig/**/*.rbs` diffed against the previous release tag, plus a runtime surface snapshot (§9.1) |
| Aggregate line-coverage floor (**NFR-5**) | SimpleCov `minimum_coverage 80` wired into the default Rake task, samples and test support excluded |
| Zero-dependency audit (**SEAM-1**, **NFR-1**, **NFR-2**) | Gemspec `runtime_dependencies.empty?` assertion, require-allowlist audit, clean-bundle isolation run (§9.2) |
| Concurrency-model agnosticism (**NFR-11**) | An RBS scan asserting that no constant outside `Dexpace::` and a fixed stdlib allowlist appears in any public signature under `sig/` — which is what mechanises "leaks no async-framework types into the core public surface" and is why the pivot of §3.3 had to be core-owned |
| Single-instance guarantee (§2.4) | A test asserting `$LOADED_FEATURES` holds exactly one resolved path per core file and that `Dexpace::VERSION` matches the loaded gemspec, plus the registration-time version assertion each adapter runs — the auditable form of a claim §2.4 otherwise argues structurally |
| Shrink-survival guard (**NFR-8**, **NFR-9**) | Retargeted at the require graph and stdlib drift (§9.2) |
| Runtime-floor discipline (**NFR-10**) | `required_ruby_version = ">= 3.2"` in every gemspec; CI matrix 3.2 / 3.3 / 3.4 / 4.0 running the real suite |
| Version/coordinate single source (**NFR-14**) | Root `VERSIONS` file read by every gemspec; one root `Gemfile` |
| Reproducible artifacts (**NFR-12**) | `SOURCE_DATE_EPOCH` honoured by `gem build`; `spec.files` sorted deterministically |
| License headers (**NFR-13**) | SPDX header per file, checked by a RuboCop custom cop |
| Runtime version metadata (**NFR-15**) | `Dexpace::VERSION` is the gemspec's own source; the User-Agent reads it, never a placeholder |
| Signed publications (**NFR-16**) | Signed `gem push` on the release path only, optional locally |
| Dependency CVE scanning | `bundler-audit` in CI, which is what enforces §3.4's `json >= 2.19.9` floor over time |
| API documentation | YARD, with an undocumented-public-method gate |

### 9.1 API-surface lock, and the honest limits of RBS

The closest available analogue to a machine-comparable public-API snapshot (**NFR-4**) is a diff of `sig/**/*.rbs`
against the previous release, failing when a public signature disappears or narrows without a major bump, with
regeneration a deliberate, reviewed act — the same discipline in either ecosystem, and never a way to silence an
unintentional break. Two limits must be stated rather than glossed. First, **RBS describes what someone wrote, not
what Ruby defines**: `Data.define` generates member readers that no signature tool can infer, `define_method` and
`method_missing` are invisible, and a `register` call that installs a constant at require time is not a
declaration. So the RBS diff is paired with a **runtime surface snapshot** — a test that walks `Dexpace`'s constant
tree and each class's `public_instance_methods(false)`, sorts the result, and diffs it against a committed
manifest. That catches what RBS cannot see; RBS catches the type changes the manifest cannot see. Second, Steep on
metaprogramming-heavy code produces false positives, so adoption is target-by-target rather than repository-wide
from day one: core's public surface is strict, internal modules are added incrementally, and every relaxation is a
named target in the `Steepfile` rather than a blanket ignore. `typeprof` bootstraps first-draft signatures;
`rbs collection` resolves third-party signatures for adapter gems.

### 9.2 The zero-dependency gate, and the NFR-8 analogue

**NFR-8** exempts itself here — "In ecosystems without such a build step this requirement does not apply" — and
Ruby has no whole-program shrinker. The gate is retargeted rather than deleted at the structurally equivalent risk:
in Ruby the thing that silently breaks a zero-dependency claim is not a stripped symbol but a **`require` of
something that used to be standard library and no longer is**, or an optional adapter's constant leaking into core.
Three mechanised checks: (1) **gemspec audit** — `runtime_dependencies` must be empty for core and must be
`dexpace-core` plus at most one other gem for each adapter (**SEAM-1**, **NFR-1**, **NFR-2**); (2)
**require-allowlist audit** — a test scans core's `lib/**/*.rb` for every `require`/`require_relative` and fails on
anything outside an explicit allowlist of non-gemified stdlib plus default gems that remain default on the
*highest* Ruby in the matrix, which is what turns §2.4's `base64` and `logger` traps into build failures instead of
production failures, and is the one gate here with no counterpart in the reference build; (3) **clean-bundle
isolation run** — a scratch `Gemfile` containing only `gem "dexpace-core", path: ...`, then `bundle exec ruby -e`
requiring core and exercising a smoke path, since Bundler refuses to activate a gem outside the bundle, run on
every Ruby in the matrix, which is what makes the Ruby 4.0 column load-bearing rather than aspirational.

The single-instance concern a nested-resolution package manager creates does not arise (§2.4); what replaces it is
a version-skew assertion at adapter registration. **NFR-10**'s trap has a Ruby-specific shape worth naming: the
failure is not a link error but a `NoMethodError` at call time when core uses a method present on the developer's
3.4 but absent on the declared 3.2 floor. RuboCop's `TargetRubyVersion` catches syntax, not stdlib availability, so
only actually running the suite on 3.2 catches it — which is why the matrix runs tests, not a syntax check.

### 9.3 Tests, and why a local server rather than only a stubbing library

**Minitest is the framework and Rake the runner, and RSpec is the alternative that was weighed.** RSpec is the more
widely used framework in the Ruby application world and has the richer matcher library, the better failure output
on complex expectations, and shared-example groups that would express the conformance suite's per-adapter
parametrisation more naturally than Minitest's module-inclusion idiom. Minitest wins for one reason that outranks
all of that here: **it ships with the interpreter as a default gem**, so the same argument §2.4 makes about
`base64` and `logger` applies to the test framework — a first-party suite that runs with nothing installed is a
suite an adapter author can run, and one that needs a third-party assertion DSL is a dependency this project would
be imposing on every adapter author who would rather not have it. That reason applies with real force only to
`dexpace-conformance`, which is why the gem takes it further: **its assertions are plain assertion objects** —
each one a callable that either returns cleanly or raises a `Dexpace::Conformance::Failure` carrying the expected
and actual values — with thin Minitest and RSpec drivers over them, so Minitest appears only as a development
dependency of the first-party build and never as a runtime constraint on a consumer. An adapter author on RSpec runs the same
assertions. For pipeline, model, parser and policy tests — the large majority — plain Minitest with hand-built
fakes suffices, with a stubbing library intercepting at the `Net::HTTP` level where a test needs a canned response
without a socket. **But transport conformance runs against a local
`TCPServer`-based fixture, not a stubbing library**, for two reasons. First, the transport requirements are about
socket-level behaviour a stub cannot express: connect-versus-read timeout classification
(**TRANSPORT-3**/**TRANSPORT-4**), lazily-read streaming bodies whose close cascades to connection release
(**TRANSPORT-25**), chunked framing, a half-closed peer, malformed inbound headers dropped individually
(**TRANSPORT-14**), vendor status codes surfaced faithfully (**TRANSPORT-24**). Second, a stubbing library needs a
per-client shim, so the *same* assertions could not run unchanged against `dexpace-transport-async_http` or a
future `httpx` adapter — which is the whole point of shipping `dexpace-conformance` as a gem from day one. A few
hundred lines of `TCPServer` that speaks the wire works identically for every adapter, first-party or not. The
suite also carries the lifecycle assertions of §3.7 — close is idempotent, a caller-supplied client survives it
(**SEAM-14**, **XCUT-22**), a post-close send raises (**SEAM-15**) — because those are exactly the clauses an
adapter author is most likely to satisfy by accident on the first call and not on the second.

**Appendix B.** The specification's conformance checklist covers only PAGE, SSE, SERDE, OBS, CFG, TRANSPORT, ASYNC,
XCUT and NFR — there are no sections for SEAM, HTTP, IO, BODY, CTX, PIPE, RECOV, RETRY, REDIR or AUTH, so a port
claiming Appendix B conformance claims considerably less than full conformance, and this port says so. **B.1** and
**B.2** are exercised as written; **B.3**, **B.5** and **B.8** with one item restated each — B.3's reified-helper
item (**SERDE-7**) becomes "the ergonomic decode helper routes through a witness or combinator," B.5's four-layer
precedence item names the `configure` tier as layer three, and B.8's seam-resolution item names require-time
registration as the discovery substrate. **B.4** is exercised as written except the allocation-freeness items,
restated as allocation-count assertions on the disabled path, with the shared-inert-event identity assertion
(**OBS-1**) kept exactly as written because §8.1 now has an object to assert it against. **B.6** is exercised per
adapter, with **TRANSPORT-8** and **TRANSPORT-18** vacuous for `Net::HTTP` and mandatory for any adapter whose
client has those paths. **B.7** needs the most restating: its items presume pooled-thread interrupt delivery and an
executor lifecycle, so **ASYNC-4** is vacuous by construction and **ASYNC-3**'s item is recorded as *failing*
rather than vacuous, since `dexpace-async-thread` supplies the blocking-task-on-a-worker antecedent the requirement
conditions on (§10.5); **ASYNC-1**/**2**/**5**/**6**/**13**/**14**/**18**/**19**/**20**/**22** are exercised
against the pivot, **ASYNC-8**–**ASYNC-12** against fiber storage, and **ASYNC-15**–**ASYNC-17** against §3.7.
**B.9** is exercised as §9's table, with NFR-8/NFR-9 inapplicable by their own text and replaced by §9.2. A failing
item that the port has decided not to satisfy is reported as a failure by the suite and suppressed in the port's
own build through a named waiver listing the requirement ID, so the gap stays visible rather than disappearing into
a restated item.

