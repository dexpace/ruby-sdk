# Contributing

Thanks for your interest in the Dexpace Ruby SDK. **Nothing has shipped yet, and everything is
`0.0.0`** — there is no `gems/` directory in this repository yet, only the design and the
scaffolding that will host it. External pull requests are welcome regardless; this page describes
the process as it will work once code lands, and the parts of it — branch discipline, commit
style, the frozen documents — that already apply today.

## Setup

The repository will be a Bundler-managed workspace of one gem per published unit under `gems/`,
one gemspec each, sharing a root `Gemfile`, `Rakefile`, `Steepfile`, `rbs_collection.yaml` and
`VERSIONS` file (`docs/sdk-design-ruby/02-gem-and-workspace-layout.md` §2.3). The supported Ruby
range is 3.2 through 4.0.

```bash
git clone https://github.com/dexpace/ruby-sdk.git
cd ruby-sdk
bundle install
```

## Quality gates

The full gate set is designed in `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md`: RuboCop
(`--fail-level=convention`), `ruby -w` with warnings fatal, RBS validated and type-checked with
Steep, an RBS sig-diff against the previous release plus a runtime surface snapshot, SimpleCov's
80% floor, the zero-runtime-dependency audit on `dexpace-core`, `bundler-audit`, and the shared
`dexpace-conformance` suite run on every transport adapter across Ruby 3.2–4.0. The default `rake`
task will run the whole set locally in one command, once the Rakefile exists.

Until then, the one gate this repository actually runs is documentation drift, not code:

```bash
ruby .claude/skills/housekeeping/probe.rb
```

Run it before claiming any of `docs/` is current.

## Conventions

The full convention set lives in [`CLAUDE.md`](CLAUDE.md). The essentials that already apply, code
or not:

- **Branch off `mvp`, not `main`.** `mvp` is the integration branch and merges into `main` when
  the MVP is complete; GitHub still offers `main` as the base, so change it.
- **`docs/product-spec/` and `docs/sdk-design-ruby/` are read-only to routine work.** They are the
  yardstick and the binding design, respectively. See `docs/README.md`'s "Frozen means frozen".
- **The zero-dependency invariant is not negotiable once there is code.** `dexpace-core`'s
  gemspec will declare zero `add_dependency` lines (**SEAM-1**); an adapter gem depends on core
  plus at most one third-party library (**NFR-2**).
- **RBS will mirror `lib/`, one file per file, in `sig/`.** A public method with no signature is a
  gap to close, not a detail to defer.
- **Minitest, not RSpec** — the bundled framework, no added test dependency, matching the "core
  plus at most one third-party library" budget applied to the toolchain itself.
- **MIT licence header** (`# SPDX-License-Identifier: MIT`) on line 1 of every source file, once
  there is source to write it on.

## Commit messages

Use the prefixes the history already follows:

| Prefix   | Use for                          |
|----------|----------------------------------|
| `feat:`  | new features                     |
| `fix:`   | bug fixes                        |
| `chore:` | refactors and cleanup            |
| `docs:`  | documentation-only changes       |
| `test:`  | tests only                       |
| `ci:`    | CI configuration                 |

## Reporting issues

Open one at [github.com/dexpace/ruby-sdk/issues](https://github.com/dexpace/ruby-sdk/issues). For
security vulnerabilities, follow [`SECURITY.md`](SECURITY.md) instead of opening a public issue.
