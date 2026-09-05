---
name: housekeeping
description: Use before handing over a phase, whenever docs/superpowers/ has files in it, after a brainstorm or a plan lands, when CLAUDE.md or README.md counts may be stale, or when asked to tidy docs/, find broken links or dangling open-item citations, and file phase documents. Probes the repository for documentation drift, reports it, and applies the one mechanical repair.
---

# Housekeeping

## Overview

Documentation drifts because nothing checks it. A `CLAUDE.md` claiming "two published gems"
while `gems/` grew to eleven, a `README.md` that is two lines and one of them misspelled, a
shipped gem README whose opening example stopped working three releases ago — every one of
those is checkable against the repository in a few lines of script, and none of them is
checked by anything else.

This skill is that check. Two stages, and the order is not optional.

```bash
ruby .claude/skills/housekeeping/probe.rb          # read-only. Report. Always first.
ruby .claude/skills/housekeeping/apply.rb          # dry run: prints the git mv commands
ruby .claude/skills/housekeeping/apply.rb --write  # performs them
```

Zero dependencies: Ruby ≥ 3.2 and its standard library, no Gemfile, no Rakefile, no RuboCop
config. It is a hand-run tool, not a CI step. Run it before claiming the documentation is
current, after landing a phase, and whenever `docs/superpowers/` has something in it.

## Stage 1 — probe

Read-only, and tested to be: `test/probe_test.rb` snapshots `git status --porcelain` around a
run and asserts it did not move. Exit code is 1 when anything is found, so it can be promoted
to a gate as it stands; `--warn-only` exits 0 without changing what it reports.

```bash
ruby .claude/skills/housekeeping/probe.rb
ruby .claude/skills/housekeeping/probe.rb --only links,citations
ruby .claude/skills/housekeeping/probe.rb --json
ruby .claude/skills/housekeeping/probe.rb --warn-only
```

Findings are grouped by check and printed as `path:line: [severity] message`, followed by a
summary line. `act` is drift to fix; `note` is a judgement call.

Eight checks. Each is a small class with a `name` and a `run(repo)`, and each derives the
repository fact **once, from the repository**, then compares every document that states it
against that one derivation — never one document against another.

| Check | Finds |
|---|---|
| `inbox` | Files in `docs/superpowers/{specs,plans}/` that are not yet filed under `docs/work/` — staged or not, because unstaged is the inbox's normal state |
| `root` | Markdown at the repository root that belongs under `docs/`. `README.md`, `CLAUDE.md` and the community-health files are the whole allowed list |
| `claims` | A count stated in `CLAUDE.md`, `README.md` or `docs/README.md` that the repository contradicts: the number of gems under `gems/`, of `phaseN` directories under `docs/work/*/`, of topics under `docs/knowledge/harvested/` |
| `readmes` | A gem under `gems/` with no README, one under 20 lines, or one whose first heading names a different gem than its gemspec's `spec.name`. No-ops when there is no `gems/` yet |
| `links` | Broken relative links in `docs/**/*.md`, `README.md`, `CLAUDE.md` and `gems/*/README.md`. `http(s)://`, `mailto:` and anchor-only targets are skipped |
| `registers` | An aggregate `## Open Findings` / `## Deferred Items` / `## Open Items` section living inside a spec, design or plan document instead of in `docs/open-items.md` |
| `citations` | An `OI-<n>` citation with no matching entry in `docs/open-items.md`, or a `DEF-<n>` citation with no matching entry in `docs/deferred-items.md` — each prefix resolves only against its own register. No-ops per prefix when that prefix's register file does not exist |
| `guard` | The frozen list and the writable surface overlapping, a path the guard has quietly stopped refusing, or a frozen entry that has become a symlink — the three ways the apply stage could eat a normative document |

The `claims` check is a **declarative table**: file, a pattern whose first capture is the
number, a label, and a lambda that derives the real value. Adding a claim is one row. A count
written as an English word is read as well as a digit — a digits-only matcher protects about
one sentence per repository — and fenced code and double-quoted spans are excluded, so a
document that quotes the historical drift it fixed does not fail its own check.

## Stage 2 — apply

**Only after reading the probe's report.** The apply stage does exactly one thing: drains
`docs/superpowers/{specs,plans}/` into `docs/work/<delivery>/phaseN[/phaseNx]/` with `git mv`,
so `git log --follow` resolves each file across the move. It shells out to `git` through
`Open3`; it never uses `FileUtils.mv`, because a plain move is a delete plus an add and the
history stops there.

```bash
ruby .claude/skills/housekeeping/apply.rb                                   # dry run
ruby .claude/skills/housekeeping/apply.rb --delivery mvp --phase 5a --write
ruby .claude/skills/housekeeping/apply.rb --rename 2026-09-05-x.md=2026-09-05-phase5a-x.md --write
```

Dry by default; `--write` performs, `--dry-run` states the default explicitly and prints the
exact `git mv` commands it would run. `--phase 5a` files everything under
`docs/work/<delivery>/phase5/phase5a/`; without it the target is read from the filename.

It refuses the **whole batch**, leaving the tree untouched, if any source or target is under a
frozen entry, if a target already exists, if two inbox files land on one target, or if a
source is untracked and so cannot be `git mv`-ed at all. Half-applying is the one outcome that
leaves an operator with no good next move.

### What it deliberately does not do

Everything else the probe reports — a stale count, a missing gem README, a broken link, a
dangling citation — is **prose, and you edit it**. That is deliberate:

> A tool that rewrites prose to make its own check pass produces documentation that is true
> and useless at the same time.

The probe tells you what is wrong and where; the judgement about what the sentence should say
is yours. Two more things `--write` does not do, and says so when it finishes:

1. **Repoint references.** Re-run the probe's `links` and `citations` checks and fix what they
   report, in the same commit — a reference that no longer matches the tree is corrected with
   the change that staled it, never deferred.
2. **Commit.** A migration is its own commit, `git mv` only, so history follows every file.

## What it must never write

```
docs/knowledge/        docs/product-spec/     docs/product-spec.md
                       docs/sdk-design-ruby/  docs/sdk-design-ruby.md
```

Both shapes are in that list on purpose, and the matcher handles each: a **directory prefix**
and an **exact file**. The list lives in one constant, `Guard::FROZEN` in `guard.rb`, and a
test pins it, so widening it is a reviewed diff rather than a silent constant change.

This is a guard, not a promise. `guard.rb` exposes `Guard.frozen?`, `Guard.assert_writable!`
and `Guard.assert_all_writable!`; `apply.rb` calls the batch form twice — once when collecting
refusals, once immediately before the first write — so deleting either call still leaves the
stage guarded. `test/guard_test.rb` proves the four ways a naive `start_with?` fails:

- a **sibling** whose name merely starts with a frozen one (`docs/product-specs/`,
  `docs/product-spec-draft/`) is writable, because the comparison is segment-wise;
- a `..` segment that lands **inside** after normalization is refused;
- an **absolute** path is resolved rather than treated as relative, and one outside the
  repository is not frozen;
- a **symlink** whose target is inside a frozen tree is refused, because `mkdir_p` follows the
  link and a purely lexical guard would say yes while `git mv` wrote into the normative tree.

The per-tree reasons are in [`docs/README.md`](../../../docs/README.md). The one worth
repeating: `docs/knowledge/harvested/` **cannot** absorb a hand edit, because a `<sub>` sha
digests the whole source file rather than the entry — an edit inside an entry changes no sha,
and the next harvest regenerates or duplicates it with nothing to notice. A finding about a
harvested rule goes in `docs/knowledge/notes/`, by hand, by a human.

## Phase file conventions

The archive is `docs/work/<delivery>/phaseN[/phaseNx]/`; `mvp` is the first delivery and a
later effort becomes a sibling of it. A phase directory is `phaseN`, no hyphen; a sub-phase
nests one directory deeper as `phaseN/phaseNx`. Every file keeps a `YYYY-MM-DD-<slug>.md`
prefix, and a (sub)phase has three:

```
docs/work/mvp/phase5/phase5a/2026-09-05-phase5a-transport-design.md   # the design
docs/work/mvp/phase5/phase5a/2026-09-05-phase5a-transport.md          # the plan
docs/work/mvp/phase5/phase5a/2026-09-05-phase5a-transport-checklist.md
```

A document spanning a whole phase — a segmentation design, a shared checklist — sits at the
`phaseN/` level. A document belonging to no phase sits directly under the delivery.

Later, the repository becomes a multi-gem monorepo: `gems/<gem-name>/`, each with its own
README and gemspec. The `readmes` and `claims` checks already know that shape and no-op
cleanly until `gems/` exists.

## Deliberately not ported from the Node original

The Node version ships a ninth tool, `check-fences.mjs`, which extracts every ` ```typescript `
fence that imports from the workspace and typechecks the lot against `dist/`. It is **not**
ported here, because its whole mechanism is a TypeScript compiler invocation over built
declaration files and Ruby has no equivalent step to hang it on.

The Ruby analogue, when it is worth building, is not a typechecker: it is an **executor**. A
fence tagged ` ```ruby ` that `require`s a `dexpace-*` gem would be extracted to a temp file,
run under `ruby -w` with each gem's `lib/` on `$LOAD_PATH` and a stubbed transport, and
asserted to exit 0 with no warnings — the same contract (a worked example cannot silently
drift) reached through the runtime rather than the type system, since a Ruby example's
failure mode is a `NoMethodError` at call time rather than a compile error. A fence with no
`dexpace-*` require is an illustrative fragment and is skipped; a require of a gem absent from
the workspace is reported rather than failed. That needs published gems to point at, so it
waits for them.

## Its own tests

```bash
ruby .claude/skills/housekeeping/test/run.rb
ruby .claude/skills/housekeeping/test/run.rb -n /guard/     # Minitest flags pass through
```

Minitest only — the bundled gem, no Gemfile. Every check has a **pair**: a throwaway fixture
tree it must report clean over, and a mutation of that tree it must fire on. A suite that only
asserts the live repository is clean passes just as happily over a check whose body has become
`[]`, and the live repository is clean most of the time, so such a suite stays green while the
checks rot. No case count is written here on purpose; `test/run.rb` reports it.

## Structure

```
.claude/skills/housekeeping/
  SKILL.md              this file
  guard.rb              the frozen-path guard; every write site goes through it
  probe.rb              stage 1 — eight read-only checks
  apply.rb              stage 2 — git mv only, guarded, dry by default
  test/
    fixture.rb          builds the throwaway repositories the tests probe
    guard_test.rb       prefix, traversal, absolute, symlink, and the pinned list
    probe_test.rb       every check has a fixture it fires on, plus the CLI
    apply_test.rb       the target mapping, every batch refusal, and the CLI
    run.rb              the whole suite
```
