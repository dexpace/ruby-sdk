# Contributing

Thanks for your interest in the Dexpace Ruby SDK. The v1 roadmap is complete — all eleven phases
are built and merged — but **nothing is published yet**: every gem under `gems/` is at `0.0.0`, and
the remaining work before the first release is tracked in
[`docs/first-release.md`](docs/first-release.md). Pull requests are welcome; this page is the flow
they go through.

## Setup

The repository is a Bundler-managed workspace of six gems under `gems/`, one gemspec each, sharing a
root `Gemfile`, `Rakefile`, `Steepfile`, `rbs_collection.yaml` and `VERSIONS` file. Supported Ruby
is **3.2 through 4.0**; `dexpace-transport-async_http` alone requires **3.3 or later**, because
`async-http` does, and on 3.2 the other five gems install and test without it.

```bash
git clone https://github.com/dexpace/ruby-sdk.git
cd ruby-sdk
bundle install
```

`Gemfile.lock` is not committed: each interpreter resolves its own. Delete it before switching Ruby.

## Quality gates

One command runs all twenty-four blocking gates, in the order CI runs them:

```bash
bundle exec rake              # every gate; stops at the first failure
bundle exec rake gates:list   # the twenty-four names
bundle exec rake -T           # each gate is separately invocable
```

They cover RuboCop (findings fatal, with the repository's custom cops), `ruby -w` with warnings
fatal, `rbs validate` and `steep check`, the RBS and runtime public-surface locks, SimpleCov's 80%
floor, the three zero-dependency checks on `dexpace-core`, the repository-wide invariant scans,
YARD's undocumented-public-method gate and `bundler-audit`. Each is described in
[`docs/sdk-documentation/quality-gates.md`](docs/sdk-documentation/quality-gates.md). CI runs the
gem suites and the packaging gates on Ruby 3.2, 3.3, 3.4 and 4.0, and everything else once.

If your change touches documentation, also run the drift probe and make it exit 0:

```bash
ruby .claude/skills/housekeeping/probe.rb
```

## How a change is made

The work here is **spec-driven**. `docs/product-spec/` holds the numbered requirements — `HTTP-7`,
`SEAM-1`, `RETRY-13`, … — and `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md`
is the index. Before changing behaviour, find the requirement IDs the change must satisfy, and cite
them: in the test file's header comment, beside a non-obvious branch, and in the pull request.

- **Bug fixes** go with a test that fails before the fix and passes after it (TDD), naming the
  requirement the bug violated.
- **Work that belongs to the release** — a blocker, something v1 ships without, a post-release
  trigger — is recorded in `docs/first-release.md` in the same change.
- **A deliberate difference from the reference contract** is a deviation, not a quiet choice: it is
  recorded where the design ledger and [`docs/deviations.md`](docs/deviations.md) can see it.
- **Larger work** — a new adapter gem from the design's post-v1 list, say — starts with a design,
  a plan and a checklist mapping every requirement ID in scope to a task, under
  `docs/work/<delivery>/`, the way every roadmap phase did.

[`CLAUDE.md`](CLAUDE.md) is the working summary of the conventions, including the constraints that
most often bite. The ones every change meets:

- **Branch off `main`, and target `main`.** There is no integration branch.
- **`docs/product-spec/` and `docs/sdk-design-ruby/` are frozen to routine work.** They are the
  yardstick and the binding design; see `docs/README.md`.
- **The zero-dependency invariant is not negotiable.** `dexpace-core`'s gemspec declares no
  `add_dependency` line (**SEAM-1**), and core `require`s only stdlib that stays stdlib on every
  supported Ruby; an adapter gem depends on core plus at most one third-party library (**NFR-2**).
- **RBS mirrors `lib/`, one file per file, in `sig/`.** Public means a `Dexpace::` constant with a
  YARD block and an RBS signature; changing the public surface means updating `sig/` and
  regenerating the runtime surface snapshot deliberately (`bundle exec rake surface:regenerate`).
- **Minitest, not RSpec**, for the repository's own suites.
- **An `# SPDX-License-Identifier: MIT` header** in every Ruby file (after
  `# frozen_string_literal: true`) and on line 1 of every RBS file.

## Commit messages

Use the prefixes the history already follows, with a subject of at most 74 characters and a body
wrapped at 72:

| Prefix   | Use for                          |
|----------|----------------------------------|
| `feat:`  | new features                     |
| `fix:`   | bug fixes                        |
| `chore:` | refactors and cleanup            |
| `docs:`  | documentation-only changes       |
| `test:`  | tests only                       |
| `ci:`    | CI configuration                 |

## Pull requests

The pull request template asks for the requirement IDs the change touches, the gates you ran and
the records you updated. Keep a pull request to one concern; CI must be green on every Ruby before
it is merged.

## Reporting issues

Open one at [github.com/dexpace/ruby-sdk/issues](https://github.com/dexpace/ruby-sdk/issues) using
the bug-report or feature-request template. For security vulnerabilities, follow
[`SECURITY.md`](SECURITY.md) instead of opening a public issue. Everyone taking part is expected to
follow the [Code of Conduct](CODE_OF_CONDUCT.md).
