## 2. Gem and Workspace Layout

The port is a single repository with one directory and one gemspec per published gem under `gems/`, the shape
`aws-sdk-ruby` uses for the same problem (one lean core plus many independently versioned satellites in one repo
with shared CI). The dependency topology is the one `rubocop` uses — a core gem plus extension gems that depend on
core and exactly one third-party library each — which is precisely what **NFR-2** asks for: "each optional
capability ... SHOULD be a separately installable unit depending on core plus at most one third-party library."
The alternative considered and rejected is the `dry-rb` one-repo-per-gem model: it gives cleaner independent
release cadences, but adapters here must track core's seam interfaces closely enough that cross-repo CI would cost
more than it saves during the pre-1.0 period when those interfaces are still moving.

The top-level Ruby namespace is `Dexpace`; gem names are hyphenated and map segment-for-segment onto the constant
path (`dexpace-transport-net_http` → `lib/dexpace/transport/net_http.rb` → `Dexpace::Transport::NetHTTP`), the
convention Ruby's own autoloading tools assume, so a reader can derive either from the other.

### 2.1 MVP gems

| Gem | Namespace | Runtime dependencies | Purpose |
|---|---|---|---|
| `dexpace-core` | `Dexpace` | **none** | Domain model (§4), I/O contracts implemented directly on stdlib (§3.1), execution context, both pipeline layers (§5), retry/redirect/auth (§6), pagination and SSE (§7), the serde seam and `Tristate` (§7.3), the instrumentation seam (§8.1), configuration (§8.2), the async pivot and cancellation token (§3.3). |
| `dexpace-transport-net_http` | `Dexpace::Transport::NetHTTP` | `dexpace-core`; `net-http` (a default gem) | The reference synchronous transport. Always available, scheduler-transparent, real socket timeout knobs, streaming in both directions. |
| `dexpace-serde-json` | `Dexpace::Serde::JSON` | `dexpace-core`; `json >= 2.19.9` | The reference wire codec. Ships separately per P3 even though `json` costs nothing to embed — see §3.4. |
| `dexpace-transport-async_http` | `Dexpace::Transport::AsyncHTTP` | `dexpace-core`; `async-http` | The reference *asynchronous* transport. In the MVP, not later: the async seam of §3.3 is unproven without a reactor-native transport behind it, because a thread-pool driver exercises the pivot's shape but none of the properties — multiplexing, a structured cancellation tree, scheduler-native suspension — that justify keeping a second transport seam at all. |
| `dexpace-async-thread` | `Dexpace::Async::Thread` | `dexpace-core` | The zero-third-party async driver: a bounded worker pool over `Thread`/`Thread::SizedQueue` that satisfies **SEAM-18**'s caller-supplied-executor contract and settles the core pivot, so the async seam is usable before anyone adopts a reactor. |
| `dexpace-conformance` | `Dexpace::Conformance` | `dexpace-core` | The shared adapter conformance suite (§9.3), published from day one because a third-party adapter author has no other way to prove an adapter against the same assertions the first-party adapters run. Its assertions are plain assertion objects with no framework dependency (§9.3), so the gem imposes no test framework on its consumers. |

### 2.2 Later gems

Deliberately deferred, in rough priority order: `dexpace-async-async` (`async`) bridging the pivot to
`Async::Task`; `dexpace-async-concurrent_ruby` (`concurrent-ruby`) bridging it to
`Concurrent::Promises::Future`; `dexpace-transport-httpx` (`httpx`) for HTTP/2 without a reactor;
`dexpace-transport-excon` and `-typhoeus`; `dexpace-serde-oj` (`oj`);
`dexpace-instrumentation-otel` (`opentelemetry-api`).

The line between the two lists is not "how useful" but "what would be unproven without it." A seam ships in the
MVP together with at least one adapter that exercises the property the seam exists for; a second adapter over the
same property is a later gem.

### 2.3 Layout and versioning

```
ruby-sdk/
  gems/
    dexpace-core/
      dexpace-core.gemspec
      lib/dexpace.rb                    # explicit requires; defines Dexpace and Dexpace::VERSION
      lib/dexpace/{http,io,body,context,pipeline,recovery,resilience,redirect,auth,page,sse,serde,
                   instrumentation,config,async,transport,error}/**.rb
      sig/dexpace/**.rbs                # mirrors lib/ one file per file
      test/dexpace/**_test.rb           # mirrors lib/ one file per file
    dexpace-transport-net_http/{dexpace-transport-net_http.gemspec,lib,sig,test}
    dexpace-transport-async_http/{...}
    dexpace-serde-json/{...}
    dexpace-async-thread/{...}
    dexpace-conformance/{...}
  Gemfile  Rakefile  Steepfile  rbs_collection.yaml  .rubocop.yml  VERSIONS  .github/workflows/
```

`lib/dexpace.rb` issues explicit `require`s for the whole tree rather than using an autoloader. This is not
stylistic: every Ruby autoloader worth using is a gem, and **SEAM-1** bars core from depending on one. Explicit
requires also make §9's require-graph audit a text scan rather than a runtime trace. Adapter gems follow the same
rule for consistency.

Each gem is versioned independently under SemVer (`Gem::Version` already implements the comparison and constraint
semantics Bundler resolves against; no versioning library is needed). Adapters declare
`add_dependency "dexpace-core", "~> MAJOR.MINOR"`, and register themselves through a call that asserts core's
`Dexpace::VERSION` is compatible, so a mismatched pair fails loudly at `require` time rather than at the first
seam call. **NFR-14**'s single source of truth is a repo-root `VERSIONS` file read by every gemspec, so a
tool-version or coordinate bump happens in one place.

### 2.4 Enforcing the zero-dependency invariant, and what "standard library" means in Ruby

**SEAM-1** limits core's runtime dependencies to "the language stdlib, the runtime, and a compile-time-only
logging facade." Ruby has no compile/runtime dependency scope distinction — `add_dependency` is the only kind —
so the first half of the enforcement is mechanical and absolute: **`dexpace-core.gemspec` contains zero
`add_dependency` lines**, asserted by a test in the default Rake task that loads the gemspec and requires
`runtime_dependencies` to be empty. That test *is* the **SEAM-1** dependency audit; there is no scope declaration
to lean on instead.

The second half is subtler and is the single most Ruby-specific hazard in this design. **Ruby's "standard library"
is not a fixed set — it shrinks between releases.** Some libraries are *non-gemified stdlib* (plain files in the
interpreter's `lib/`, always present, e.g. `monitor`); some are *default gems* (shipped with the interpreter,
always activatable, e.g. `json`, `digest`, `openssl`, `uri`, `net-http`, `securerandom`, `stringio`, `time`,
`set`, `timeout`); and some are *bundled gems* (shipped with the interpreter but requiring an explicit
`Gemfile`/gemspec entry under Bundler). Requirements migrate from the second category to the third. Verified from
`Gem::BUNDLED_GEMS::SINCE` on Ruby 3.4.10: **`base64` became a bundled gem in Ruby 3.4, and `logger`, `ostruct`,
`benchmark`, `fiddle` and `pstore` become bundled gems in Ruby 4.0.** A core gem that innocently writes
`require "base64"` to Base64-encode Basic credentials, or `require "logger"` to type-check a sink, acquires an
undeclared dependency that fails under Bundler on a supported Ruby.

The rule this port adopts, stated precisely: **`dexpace-core` may `require` only (a) non-gemified stdlib and (b)
default gems that remain default gems on every Ruby in the supported range, currently 3.2 through 4.0.** The
concrete consequences appear in §6.3 (Basic auth uses `["u:p"].pack("m0")`, never `Base64`) and §8.1 (the logging
sink is a duck type, and core never `require`s `logger`). Adapter gems are exempt: an adapter that wants `logger`
declares it, which is exactly what **NFR-2**'s "core plus at most one third-party library" budget is for. §9 wires
this into CI as a require-allowlist audit plus a clean-bundle isolation run on the highest Ruby in the matrix.

**Single-instance guarantee.** The reference and any package manager with nested resolution must ask how two
copies of core could be loaded at once, because type-identity checks (the exception hierarchy of **XCUT-4**, the
`Outcome` variants of **RECOV-1**, the `Tristate` variants of **SERDE-14**) break silently under duplication. In
Ruby the answer is structural: Bundler activates exactly one version of a gem per process, `require` de-duplicates
by resolved feature path, and constants live in one process-global namespace — two copies of `dexpace-core` cannot
produce two distinct `Dexpace::TransportError` classes; they would reopen the same constant. The residual risk is
therefore not identity split but *version skew* (an adapter compiled against an older core's seam), which the
`~>` constraint plus the registration-time version assertion above covers.

---

