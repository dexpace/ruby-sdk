# `docs/`

One owner per entry, one job per entry, and nothing written by two things. This file is the
index and the contract; the rule is that nothing in `docs/` is unowned.

Entries marked **(planned)** do not exist yet. They are listed anyway, because an ownership
table that only describes what already exists is a table that gets edited after the fact —
and the entries below are frozen the moment they appear, not the moment someone remembers.

| Entry | Owns | Written by | Housekeeping may write? |
|---|---|---|---|
| [`product-spec/`](./product-spec/) + [`product-spec.md`](./product-spec.md) | **Normative.** The numbered requirements — `HTTP-7`, `SEAM-1`, `RETRY-13`, `NFR-5`, … — that the code exists to satisfy. The `.md` is its table of contents | A human, deliberately | **No — frozen** |
| [`sdk-design-ruby/`](./sdk-design-ruby/) + [`sdk-design-ruby.md`](./sdk-design-ruby.md) | How each spec area maps to idiomatic Ruby. Non-normative but binding by convention. §10 is the **normative deviation ledger** | A human, deliberately | **No — frozen** |
| `knowledge/harvested/` **(planned)** | Harvested styleguide and spec knowledge, topic-indexed. Generated; **never hand-edited** | The `knowledge-harvest` skill | **No — frozen** |
| `knowledge/notes/` **(planned)** | What the implementation found, overriding a harvested entry. Hand-written, role `review` | A human | **No — frozen** |
| [`sdk-documentation/`](./sdk-documentation/) | **As-built.** How the gems compose, which one to install, worked cross-gem examples | A human, or a skill on request | Yes |
| [`work/`](./work/) | Process records: per-(sub)phase design, plan and checklist, one directory per phase under a unit of delivery | The phase that produced them; **collected** here by the `housekeeping` skill | Yes — `git mv` only |
| [`superpowers/`](./superpowers/README.md) | Nothing, for long. The **inbox** the Superpowers skills write into | `brainstorming`, `writing-plans` | Yes — it drains it |
| [`open-items.md`](./open-items.md) | Running register of findings: gaps discovered **after** the work, permanent item IDs `OI-<n>`, cited from anywhere in the repository | Whoever finds the item | Yes — appends |
| [`deferred-items.md`](./deferred-items.md) | Running register of deferrals: work postponed **before** the work, permanent item IDs `DEF-<n>` | The phase (or design pass) that defers the item | Yes — appends |
| [`deviations.md`](./deviations.md) | As-built audit of `sdk-design-ruby/10`'s deviation ledger, plus deviations found outside a phase | A human, following a phase or review | No — judgment, not a mechanical append |
| [`first-release.md`](./first-release.md) | Release-readiness register: gem versions, blockers before first publish, the release path | A human, updated as blockers close | No |
| [`assets/`](./assets/) | Vendored wordmark SVGs the root [`README.md`](../README.md) renders | Copied from `dexpace/morphic` | Yes |
| [`README.md`](./README.md) | This index | A human | Yes |

## Frozen means frozen

`knowledge/`, `product-spec/`, `sdk-design-ruby/` and the two sibling tables of contents are
**read-only to routine maintenance**. The `housekeeping` skill refuses to write to them, and
that refusal is a tested guard rather than a paragraph of good intent
([`guard.rb`](../.claude/skills/housekeeping/guard.rb),
[`test/guard_test.rb`](../.claude/skills/housekeeping/test/guard_test.rb)).

Each has its own reason:

- **`product-spec/`** is what the code is measured against. A tool editing the yardstick is a
  category error.
- **`sdk-design-ruby/`** carries §10, the normative deviation ledger. Amending it is a
  deliberate act, not a maintenance pass.
- **`knowledge/harvested/`** *cannot* absorb a hand edit. Its `<sub>` shas digest the whole
  source file rather than the entry, so an edit inside an entry changes no sha and the next
  harvest regenerates or duplicates it with nothing to notice. Record the finding in
  `knowledge/notes/` instead.
- **`knowledge/notes/`** is hand-written and could in principle be edited; it is grouped with
  `harvested/` because the corpus is read as one tree and a note's key citation couples them.

The list lives in exactly one place —
[`Guard::FROZEN`](../.claude/skills/housekeeping/guard.rb) — so widening it is a reviewed
diff rather than a silent constant change, and a test pins it.

## `work/` and the inbox

`docs/work/<delivery>/phaseN[/phaseNx]/` is the archive. `mvp/` is the first delivery; a later
effort becomes a sibling of it.

```
work/mvp/
  2026-09-05-ruby-sdk-v1-roadmap-design.md        # belongs to no phase
  phase1/ … phaseN/
    phase6/2026-09-05-phase6-segmentation-design.md   # spans the whole phase
    phase6/phase6a/                                   # one directory per sub-phase
      2026-09-05-phase6a-transport-design.md
      2026-09-05-phase6a-transport.md
      2026-09-05-phase6a-transport-checklist.md
```

A phase directory is `phaseN`, no hyphen. A sub-phase nests one directory deeper as
`phaseN/phaseNx`. Every file keeps its `YYYY-MM-DD-` prefix, which carries ordering the
directory name does not, and a (sub)phase has three files: `…-design.md`, the plain plan
`….md`, and `…-checklist.md`.

New documents do **not** land there directly. The `brainstorming` and `writing-plans` skills
hard-code `docs/superpowers/{specs,plans}/`, they are installed globally, and this repository
cannot change them — so that directory is an inbox and the `housekeeping` skill collects from
it. See [`superpowers/README.md`](./superpowers/README.md).

## The registers

There are three, at the `docs/` root: [`open-items.md`](./open-items.md),
[`deferred-items.md`](./deferred-items.md) and [`deviations.md`](./deviations.md). The boundary
between the first two is *when* an item was created — a deferral is a decision made **before** the
work ("not this phase, that one"); an open item is a discovery made **after** ("this is not what
the checklist says it is") — and `deviations.md` is a third kind of thing entirely: the as-built
audit of the normative deviation ledger in `sdk-design-ruby/10`, not a register anyone appends
findings to routinely. An aggregate `## Open Findings` / `## Deferred Items` / `## Open Items`
section inside a spec, design or plan document is drift, and the probe reports it — a concern only
a specification remembers is a concern nothing acts on.

Item IDs are **permanent**: never renumbered, never reused, cited from source comments and tests
as well as from `docs/`. `OI-<n>` resolves only against `open-items.md`; `DEF-<n>` resolves only
against `deferred-items.md`. Requirement IDs (`HTTP-7`, `SEAM-1`) are a different namespace and the
probe does not confuse them.

## Keeping this file true

```bash
ruby .claude/skills/housekeeping/probe.rb
```

The [`housekeeping`](../.claude/skills/housekeeping/SKILL.md) skill probes every claim here
against the repository — the gem count, the phase-directory count, the harvested-topic count,
a README on every gem, broken relative links, register text in the wrong document, and a
citation that resolves to nothing. It is a hand-run tool, not a CI step. Run it before
claiming the documentation is current.
