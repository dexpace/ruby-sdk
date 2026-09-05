# package-and-dependency-layout

## Rules
- The core module MUST depend only on the language standard library, the runtime, and a compile-time-only logging facade, and MUST NOT carry a runtime dependency on any concrete HTTP transport, serialization library, I/O implementation, or async framework. (NFR-1)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:7` · high · sha:5f4684bf7123</sub>
- Each optional capability (transport, serialization format, I/O backend, async bridge) SHOULD be a separately installable unit depending on the core plus at most one third-party library, so a consumer composes only the units it uses. (NFR-2)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:8` · high · sha:5f4684bf7123</sub>
- The SDK MUST declare a lowest-supported-runtime floor and target it for all general-purpose units; a capability requiring a newer runtime MUST be isolated into its own unit declaring the higher floor explicitly and MUST NOT be a hard dependency of the general-purpose core, and no produced artifact may reference runtime/stdlib APIs absent on the floor it declares. (NFR-10)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:29` · high · sha:5f4684bf7123</sub>
- Gem names are hyphenated and map segment-for-segment onto the constant path, for example dexpace-transport-net_http maps to lib/dexpace/transport/net_http.rb and to Dexpace::Transport::NetHTTP, following the convention Ruby's own autoloading tools assume.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:12-14` · high · sha:668b1cc67c24</sub>
- Adapter gems follow the same explicit-require convention as dexpace-core for consistency.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:61-62` · high · sha:668b1cc67c24</sub>
- Adapter gems declare add_dependency "dexpace-core", "~> MAJOR.MINOR" and register themselves through a call that asserts core's Dexpace::VERSION is compatible, so a mismatched pair fails loudly at require time rather than at the first seam call. (NFR-14)
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:65-68` · high · sha:668b1cc67c24</sub>
- dexpace-core.gemspec must contain zero add_dependency lines, asserted by a test in the default Rake task that loads the gemspec and requires runtime_dependencies to be empty, because Ruby has no compile/runtime dependency scope distinction to lean on instead. (SEAM-1)
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:74-78` · high · sha:668b1cc67c24</sub>
- dexpace-core may require only non-gemified stdlib and default gems that remain default gems on every Ruby version in the supported range, currently 3.2 through 4.0.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:91-92` · high · sha:668b1cc67c24</sub>
- Basic auth credential encoding in this port uses ["u:p"].pack("m0") rather than requiring "base64", to avoid an undeclared dependency on a library that becomes a bundled gem in Ruby 3.4.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:87-93` · high · sha:668b1cc67c24</sub>
- The logging sink in dexpace-core is a duck type, and core never requires "logger", to avoid an undeclared dependency on a library that becomes a bundled gem in Ruby 4.0.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:87-94` · high · sha:668b1cc67c24</sub>
- Adapter gems are exempt from dexpace-core's require restriction — an adapter that wants "logger" declares it as a dependency, fitting within NFR-2's "core plus at most one third-party library" budget.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:94-96` · high · sha:668b1cc67c24</sub>

## Constraints
- SEAM-1 limits dexpace-core's runtime dependencies to "the language stdlib, the runtime, and a compile-time-only logging facade."
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:73-74` · high · sha:668b1cc67c24</sub>
- Ruby's "standard library" is not a fixed set — it shrinks between releases.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:80-81` · high · sha:668b1cc67c24</sub>
- In Ruby, Bundler activates exactly one version of a gem per process, require de-duplicates by resolved feature path, and constants live in one process-global namespace, so two copies of dexpace-core cannot produce two distinct Dexpace::TransportError classes because they would reopen the same constant. (XCUT-4, RECOV-1, SERDE-14)
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:98-103` · high · sha:668b1cc67c24</sub>

## Conclusions
- The port uses a single repository with one directory and one gemspec per published gem under gems/, the same shape aws-sdk-ruby uses (one lean core plus many independently versioned satellites in one repo with shared CI).
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:3-5` · high · sha:668b1cc67c24</sub>
- The dependency topology follows the rubocop model of a core gem plus extension gems that each depend on core and exactly one third-party library, matching NFR-2's requirement that "each optional capability ... SHOULD be a separately installable unit depending on core plus at most one third-party library."
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:5-7` · high · sha:668b1cc67c24</sub>
- The dry-rb one-repo-per-gem model was considered and rejected because although it gives cleaner independent release cadences, adapters must track core's seam interfaces closely enough that cross-repo CI would cost more than it saves during the pre-1.0 period when those interfaces are still moving.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:8-10` · high · sha:668b1cc67c24</sub>
- The dexpace-serde-json gem (namespace Dexpace::Serde::JSON, depending on dexpace-core and json >= 2.19.9) ships separately from core per working principle P3 even though the json library costs nothing to embed.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:18-22` · high · sha:668b1cc67c24</sub>
- The dexpace-transport-async_http gem (namespace Dexpace::Transport::AsyncHTTP, depending on dexpace-core and async-http) is included in the MVP rather than deferred because the async seam is unproven without a reactor-native transport behind it, since a thread-pool driver exercises the pivot's shape but none of the properties — multiplexing, a structured cancellation tree, scheduler-native suspension — that justify keeping a second transport seam at all.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:18-23` · high · sha:668b1cc67c24</sub>
- The dexpace-conformance gem (namespace Dexpace::Conformance, depending only on dexpace-core) is published from day one because a third-party adapter author has no other way to prove an adapter against the same assertions the first-party adapters run, and its assertions are plain assertion objects with no framework dependency so the gem imposes no test framework on its consumers. (SEAM-18)
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:18-25` · high · sha:668b1cc67c24</sub>
- The line between MVP gems and later gems is drawn not by usefulness but by what would be unproven without it: a seam ships in the MVP together with at least one adapter that exercises the property the seam exists for, and a second adapter over the same property becomes a later gem.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:35-37` · high · sha:668b1cc67c24</sub>
- lib/dexpace.rb issues explicit requires for the whole tree rather than using an autoloader, because every Ruby autoloader worth using is itself a gem and SEAM-1 bars core from depending on one.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:59-62` · high · sha:668b1cc67c24</sub>
- Using explicit requires instead of an autoloader also makes the require-graph audit a text scan rather than a runtime trace. (SEAM-1)
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:60-62` · high · sha:668b1cc67c24</sub>
- NFR-14's single source of truth for versions and tool coordinates is a repo-root VERSIONS file read by every gemspec, so a tool-version or coordinate bump happens in one place.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:68-69` · high · sha:668b1cc67c24</sub>
- Because Ruby structurally prevents two distinct copies of a gem's constants from coexisting in one process, the residual risk for dexpace-core is not identity split but version skew (an adapter compiled against an older core's seam), which is covered by the ~> version constraint plus the registration-time version assertion.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:103-105` · high · sha:668b1cc67c24</sub>

## Reference
- An adapter unit is a separately installable module supplying one concrete capability by depending on the core plus at most one third-party library, keeping its public surface minimal, so consumers compose only the units they need.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:3` · high · sha:f0b3d2058626</sub>
- The top-level Ruby namespace for the port is Dexpace.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:12-12` · high · sha:668b1cc67c24</sub>
- The dexpace-core gem has namespace Dexpace, has no runtime dependencies, and contains the domain model, I/O contracts implemented directly on stdlib, execution context, both pipeline layers, retry/redirect/auth, pagination and SSE, the serde seam and Tristate, the instrumentation seam, configuration, and the async pivot and cancellation token.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:18-20` · high · sha:668b1cc67c24</sub>
- The dexpace-transport-net_http gem has namespace Dexpace::Transport::NetHTTP, depends on dexpace-core and net-http (a default gem), and is the reference synchronous transport, always available, scheduler-transparent, with real socket timeout knobs and streaming in both directions.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:18-21` · high · sha:668b1cc67c24</sub>
- The dexpace-async-thread gem (namespace Dexpace::Async::Thread, depending only on dexpace-core) is a zero-third-party async driver — a bounded worker pool over Thread/Thread::SizedQueue — that satisfies SEAM-18's caller-supplied-executor contract and settles the core pivot so the async seam is usable before anyone adopts a reactor.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:18-24` · high · sha:668b1cc67c24</sub>
- Gems deliberately deferred past the MVP, in rough priority order, are dexpace-async-async (bridging the pivot to Async::Task via the async gem), dexpace-async-concurrent_ruby (bridging to Concurrent::Promises::Future via concurrent-ruby), dexpace-transport-httpx (HTTP/2 without a reactor via httpx), dexpace-transport-excon and dexpace-transport-typhoeus, dexpace-serde-oj (via oj), and dexpace-instrumentation-otel (via opentelemetry-api).
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:29-33` · high · sha:668b1cc67c24</sub>
- Each gem in the port is versioned independently under SemVer using Gem::Version, which already implements the comparison and constraint semantics Bundler resolves against, so no additional versioning library is needed.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:64-65` · high · sha:668b1cc67c24</sub>
- Ruby libraries fall into three categories — non-gemified stdlib (plain files always present in the interpreter's lib/, e.g. monitor), default gems (shipped with the interpreter and always activatable, e.g. json, digest, openssl, uri, net-http, securerandom, stringio, time, set, timeout), and bundled gems (shipped with the interpreter but requiring an explicit Gemfile/gemspec entry under Bundler) — and requirements migrate from the default-gem category to the bundled-gem category over time.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:81-85` · high · sha:668b1cc67c24</sub>
- Verified from Gem::BUNDLED_GEMS::SINCE on Ruby 3.4.10, base64 became a bundled gem in Ruby 3.4, and logger, ostruct, benchmark, fiddle, and pstore become bundled gems in Ruby 4.0.
  <sub>design · `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:85-89` · high · sha:668b1cc67c24</sub>

## Conflicts
- **styleguide vs design: Ruby version floor** — the styleguide pins Ruby to 4.0 or higher via .ruby-version and chooses 4.0 as the hard floor; the design fixes required_ruby_version >= 3.2 with a CI matrix of 3.2, 3.3, 3.4 and 4.0 and restricts core to stdlib that stays default across that range
  <sub>styleguide `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:40-44` · design `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:18` · design `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:91-92` · unresolved 2026-09-05</sub>
- **styleguide vs design: gems per repository** — the styleguide prescribes one gemspec at the repository root and treats multiple gemspecs in one repository as a signal the gem should be split; the design is a single-repository gems/ monorepo with one gemspec per published gem (aws-sdk-ruby shape)
  <sub>styleguide `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:170-178` · design `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:3-10` · unresolved 2026-09-05</sub>

## Superseded
