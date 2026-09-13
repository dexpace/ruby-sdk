# tooling-and-quality-gates

## Rules
- The Ruby version must be pinned to 4.0 or higher via a `.ruby-version` file.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:40-44` · high · sha:9dd0b475bc7d</sub>
- `Gemfile.lock` must be committed to the repository so every developer and CI node installs identical dependency versions.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:45` · high · sha:9dd0b475bc7d</sub>
- CI must run `bundle install --frozen` to reject any lockfile drift caused by an unreviewed `bundle update`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:46` · high · sha:9dd0b475bc7d</sub>
- Every project must inherit the `rubocop-airbnb` cop set as the baseline via `inherit_gem` in `.rubocop.yml`, with local overrides kept to the narrowest possible diff above it.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:53` · high · sha:9dd0b475bc7d</sub>
- Both pre-commit and CI must run `bundle exec rubocop --format progress`, and a formatter failure blocks the commit and blocks the merge.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:54` · high · sha:9dd0b475bc7d</sub>
- Any cop override in `.rubocop.yml` must carry a comment naming the chapter and rule that recorded the deviation, and an unexplained `Enabled: false` is rejected in review.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:55` · high · sha:9dd0b475bc7d</sub>
- `rubocop --autocorrect-all` is the only sanctioned way to fix style issues, run in pre-commit to prevent style drift.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:56` · high · sha:9dd0b475bc7d</sub>
- The build SHOULD enforce a minimum aggregate line-coverage floor, currently 80%, across the library units wired into the default build lifecycle, excluding sample/example code, test-only guards, and test fixtures. (NFR-5)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:17` · high · sha:5f4684bf7123</sub>
- Compiler warnings SHOULD be treated as errors across every unit, including deprecation warnings. (NFR-6)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:18` · high · sha:5f4684bf7123</sub>
- The build SHOULD run automated style/lint and static-analysis checks with findings treated as fatal, and where an analyzer cannot run on a given unit's toolchain, disabling it SHOULD be a narrowly-scoped, documented exception with explicit re-enable conditions rather than a silent global relaxation. (NFR-7)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:19` · high · sha:5f4684bf7123</sub>
- The quality gates backing the compatibility snapshot, coverage floor, warnings-as-errors, lint/static-analysis, shrink-survival, and runtime-floor checks MUST be enforced automatically and be blocking, failing the standard build/CI rather than being advisory. (NFR-17)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:20` · high · sha:5f4684bf7123</sub>
- In target ecosystems that support whole-program dead-code elimination/tree-shaking/minification, the SDK MUST ship the keep/retain configuration a downstream shrinker needs so its reflectively-reached and runtime-wired surface survives shrinking, covering the runtime-wired SPI seams, immutable models, and reflectively-bound types. (NFR-8)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:24` · high · sha:5f4684bf7123</sub>
- The shipped shrinker keep-configuration SHOULD be guarded by an automated regression check, wired into the default build, that shrinks a real consumer using only the shipped rules and runs it end-to-end against a live round-trip, failing the build if any runtime-wired or reflectively-reached surface is stripped. (NFR-9)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:25` · high · sha:5f4684bf7123</sub>
- Build artifacts SHOULD be reproducible: identical source inputs SHOULD yield byte-for-byte identical output artifacts, with embedded timestamps normalized/stripped and entry ordering deterministic. (NFR-12)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:37` · high · sha:5f4684bf7123</sub>
- Every source file SHOULD carry the project's license/SPDX header block, enforced in the reference as a review convention rather than a mechanical gate. (NFR-13)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:38` · high · sha:5f4684bf7123</sub>
- Dependency versions, plugin/tool versions, and project coordinates SHOULD live in a single source of truth rather than being restated per unit, so a bump is ideally a one-line edit applying uniformly. (NFR-14)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:39` · high · sha:5f4684bf7123</sub>
- Published artifacts SHOULD embed self-identifying version metadata the SDK can resolve at runtime, so runtime-emitted identifiers such as a User-Agent report the real version rather than an unknown placeholder. (NFR-15)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:40` · high · sha:5f4684bf7123</sub>
- Published artifacts SHOULD be cryptographically signed for provenance, with signing enforced on the release/CI path and made gracefully optional in local builds lacking signing keys. (NFR-16)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:41` · high · sha:5f4684bf7123</sub>
- The default rake task runs the entire set of quality gates locally, so no gate can be an opt-in job that nobody runs. (NFR-17)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:4-5` · high · sha:b9270d5d1ef8</sub>
- Every public entity must have an RBS signature in sig/, gated by both rbs validate and steep check. (NFR-3)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:11-11` · high · sha:b9270d5d1ef8</sub>
- An SPDX license header is required per file, checked by a custom RuboCop cop. (NFR-13)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:21-21` · high · sha:b9270d5d1ef8</sub>
- Dexpace::VERSION is sourced from the gemspec itself, and the User-Agent header reads that value directly rather than a placeholder. (NFR-15)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:22-22` · high · sha:b9270d5d1ef8</sub>
- API documentation is produced by YARD with a gate that fails on undocumented public methods.
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:25-25` · high · sha:b9270d5d1ef8</sub>

## Constraints
- required_ruby_version is set to ">= 3.2" in every gemspec, and CI runs the real test suite on a matrix of Ruby 3.2, 3.3, 3.4, and 4.0. (NFR-10)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:18-18` · high · sha:b9270d5d1ef8</sub>
- RBS describes what someone wrote, not what Ruby actually defines: Data.define generates member readers that no signature tool can infer, define_method and method_missing are invisible to it, and a register call that installs a constant at require time is not a declaration RBS can see.
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:32-35` · high · sha:b9270d5d1ef8</sub>
- The shrink-survival guard requirement exempts itself in ecosystems without a build-time shrinking step, and Ruby has no whole-program shrinker, so the gate is retargeted rather than deleted. (NFR-8)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:45-46` · high · sha:b9270d5d1ef8</sub>

## Conclusions
- Ruby 4.0 was chosen as the hard version floor because it ships frozen string literals as a default, tightens the object model, and is the baseline Sorbet supports for the target strictness.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:44` · high · sha:9dd0b475bc7d</sub>
- Specific numbers and tool names in the non-functional requirements, such as 80% coverage, the shrinker, and the exact static analyzers, are the JVM reference's particular instantiation; a faithful port need only ensure the equivalent gate exists and blocks.
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:3` · high · sha:5f4684bf7123</sub>
- The reference's "whole-program shrinker with a reflection blind spot" constraint does not hold for Ruby because NFR-8 itself states the requirement does not apply in ecosystems without such a build step, so the corresponding gate is retargeted rather than deleted, at the structurally equivalent Ruby risk.
  <sub>design · `docs/sdk-design-ruby/01-overview.md:55-57` · high · sha:a69e6feeaeb4</sub>
- Steep adoption is target-by-target rather than repository-wide from day one because Steep on metaprogramming-heavy code produces false positives; core's public surface is checked strictly, internal modules are added incrementally, and every relaxation is a named target in the Steepfile rather than a blanket ignore.
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:38-40` · high · sha:b9270d5d1ef8</sub>
- The zero-dependency risk in Ruby is retargeted to two structurally equivalent risks: a require of something that used to be standard library and no longer is, or an optional adapter's constant leaking into core.
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:46-48` · high · sha:b9270d5d1ef8</sub>
- RuboCop's TargetRubyVersion catches syntax incompatibility but not stdlib method availability, so only actually running the test suite on Ruby 3.2 catches such gaps, which is why the CI matrix runs tests rather than only a syntax check.
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:62-63` · high · sha:b9270d5d1ef8</sub>

## Reference
- The `.ruby-version` file is read uniformly by `rbenv`, `chruby`, and `asdf`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:43` · high · sha:9dd0b475bc7d</sub>
- The aggregate coverage floor is a minimum line-coverage percentage computed across all library units combined, not per-unit, excluding samples and test-support code, enforced by the default build.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:5` · high · sha:f0b3d2058626</sub>
- A quality gate is an automated, build-blocking check that fails the standard build when its condition is not met, such as coverage floor, API-snapshot drift, warnings, lint/static-analysis, shrink-survival, or runtime-floor.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:51` · high · sha:f0b3d2058626</sub>
- Shrink-survival keep-configuration is the retain/keep rules the SDK ships so a downstream whole-program shrinker does not eliminate reflectively-reached or runtime-wired surface.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:63` · high · sha:f0b3d2058626</sub>
- Static analysis is enforced by RuboCop with rubocop-minitest and rubocop-performance, run with --fail-level=convention, with waivers permitted only as scoped inline directives carrying a reason. (NFR-7)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:9-9` · high · sha:b9270d5d1ef8</sub>
- Warnings-as-errors is implemented as ruby -w for the test task plus RUBYOPT=-W:deprecated, with warnings failing the build. (NFR-6)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:10-10` · high · sha:b9270d5d1ef8</sub>
- The API-surface snapshot gate diffs sig/**/*.rbs against the previous release tag and also maintains a runtime surface snapshot. (NFR-4)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:12-12` · high · sha:b9270d5d1ef8</sub>
- SimpleCov enforces a minimum_coverage of 80 wired into the default Rake task, with samples and test support excluded from the measurement. (NFR-5)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:13-13` · high · sha:b9270d5d1ef8</sub>
- The zero-dependency audit checks the gemspec's runtime_dependencies.empty? assertion, a require-allowlist audit, and a clean-bundle isolation run. (SEAM-1, NFR-1, NFR-2)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:14-14` · high · sha:b9270d5d1ef8</sub>
- Concurrency-model agnosticism is mechanised as an RBS scan asserting that no constant outside Dexpace:: and a fixed stdlib allowlist appears in any public signature under sig/, which is why the core-owned pivot mechanism was required. (NFR-11)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:15-15` · high · sha:b9270d5d1ef8</sub>
- The single-instance guarantee is verified by a test asserting that $LOADED_FEATURES holds exactly one resolved path per core file and that Dexpace::VERSION matches the loaded gemspec, plus a registration-time version assertion each adapter runs.
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:16-16` · high · sha:b9270d5d1ef8</sub>
- A single root VERSIONS file is read by every gemspec, and there is one root Gemfile for version/coordinate consistency. (NFR-14)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:19-19` · high · sha:b9270d5d1ef8</sub>
- Reproducible artifacts are achieved by honouring SOURCE_DATE_EPOCH in gem build and sorting spec.files deterministically. (NFR-12)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:20-20` · high · sha:b9270d5d1ef8</sub>
- Signed gem push is used on the release path only and is optional locally. (NFR-16)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:23-23` · high · sha:b9270d5d1ef8</sub>
- bundler-audit runs in CI for dependency CVE scanning, which is what enforces the json >= 2.19.9 floor over time.
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:24-24` · high · sha:b9270d5d1ef8</sub>
- The runtime surface snapshot is a test that walks Dexpace's constant tree and each class's public_instance_methods(false), sorts the result, and diffs it against a committed manifest, catching what RBS cannot see, while RBS catches the type changes the manifest cannot see.
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:35-38` · high · sha:b9270d5d1ef8</sub>
- typeprof bootstraps first-draft RBS signatures, and rbs collection resolves third-party signatures for adapter gems.
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:40-41` · high · sha:b9270d5d1ef8</sub>
- The gemspec audit requires runtime_dependencies to be empty for core and to be dexpace-core plus at most one other gem for each adapter. (SEAM-1, NFR-1, NFR-2)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:49-50` · high · sha:b9270d5d1ef8</sub>
- The require-allowlist audit scans core's lib/**/*.rb for every require/require_relative and fails on anything outside an explicit allowlist of non-gemified stdlib plus default gems that remain default on the highest Ruby in the CI matrix; it has no counterpart in the reference build.
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:51-54` · high · sha:b9270d5d1ef8</sub>
- The clean-bundle isolation run uses a scratch Gemfile containing only gem "dexpace-core", path: ..., then runs bundle exec ruby -e requiring core and exercising a smoke path, since Bundler refuses to activate a gem outside the bundle; it runs on every Ruby in the CI matrix, which is what makes the Ruby 4.0 column load-bearing rather than aspirational.
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:54-57` · high · sha:b9270d5d1ef8</sub>
- The Ruby-specific shape of the runtime-floor discipline trap is that the failure is a NoMethodError at call time, not a link error, when core uses a method present on the developer's Ruby 3.4 but absent on the declared 3.2 floor. (NFR-10)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:60-62` · high · sha:b9270d5d1ef8</sub>

## Conflicts
- **styleguide vs design: RuboCop baseline** — the styleguide requires every project to inherit the rubocop-airbnb cop set via inherit_gem and to run rubocop --autocorrect-all in pre-commit; the design names RuboCop with rubocop-minitest and rubocop-performance at --fail-level=convention and does not mention rubocop-airbnb
  <sub>styleguide `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:53-56` · design `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:9` · unresolved 2026-09-05</sub>

## Superseded
