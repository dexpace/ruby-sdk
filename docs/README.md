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
| [`deviations.md`](./deviations.md) | As-built audit of `sdk-design-ruby/10`'s deviation ledger, plus deviations found outside a phase | A human, following a phase or review | No — judgment, not a mechanical append |
| [`first-release.md`](./first-release.md) | Release-readiness register: gem versions, blockers before first publish, the release path, plus what v1 ships without and the post-release triggers | A human, updated as blockers close | No |
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

## The register

There is one, at the `docs/` root: [`deviations.md`](./deviations.md) — the as-built audit of the
normative deviation ledger in `sdk-design-ruby/10`, plus deviations found outside a phase. It is
not a find-list, and nothing else here is one either.

A finding is **not registered; it is routed to its owner when it is found**. Work that falls
inside a phase's scope becomes a numbered task in that phase's plan, cited by path and task
number. Audit-or-repair work against a phase that is already planned goes to phase 10's inbound
list in [the roadmap](./work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md). Anything belonging to
the release — a blocker, something v1 ships without, a step on the release path, a post-release
trigger — goes to [`first-release.md`](./first-release.md). And when the thing reported is in
material you may write, it is not routed anywhere: it is fixed. Work consciously postponed
**before** it is done ("not this phase, that one") takes the first or the third of those, and the
document that postpones it says which, with the reason and the pick-up condition. An aggregate
`## Open Findings` / `## Deferred Items` / `## Open Items` section inside a spec, design or plan
document is drift, and the probe reports it — a concern only a specification remembers is a
concern nothing acts on.

Both item-ID namespaces are **retired**: `OI-<n>`, the find-list that was `open-items.md`, and
`DEF-<n>`, the deferrals that were `deferred-items.md`, both on 2026-09-13. Neither resolves to
anything, neither prefix is reused, and the probe reports every surviving citation of either —
from a source comment, a test, or anywhere under `docs/`. Requirement IDs (`HTTP-7`, `SEAM-1`) are
a different namespace and the probe does not confuse them.

## What the tree beside `docs/` holds

Six gems exist under `gems/`, all at `0.0.0` and none published — each a gemspec reading the
root `VERSIONS` file, a `sig/` mirror and a smoke suite. `dexpace-core` holds phase 1's HTTP
domain model, phase 2's seam layer, phase 3a's byte-streaming layer, phase 3b's body layer, phase
4a's execution context, phase 4b's recovery layer, phase 4c's stage pipeline, phase 5a's
configuration layer, phase 5b's logging facade and redaction, phase 5c's tracing and metrics
layer, phase 6a's retry layer, phase 6c's authentication layer, phase 6b's redirect layer, phase
7b's server-sent-events layer, phase 7c's pagination layer, phase 7a's serialization layer and
phase 8a's transport error; `dexpace-serde-json` holds phase 7a's JSON codec and declares
`json >= 2.19.9`; `dexpace-transport-net_http` holds phase 8a's synchronous transport and declares
`net-http >= 0.4`, and `dexpace-conformance` phase 8a's assertion protocol, transport suite, wire
fixture, two drivers and two doubles; `dexpace-async-thread` holds phase 8b's thread pool, its
rejection error and the version-skew guard, and declares `dexpace-core` alone; the other one is
phase 0's skeleton, a namespace and a
`VERSION`. The as-built documentation lands in
[`sdk-documentation/`](./sdk-documentation/) as each gem gains code; the twenty pages written so far are [`sdk-documentation/quality-gates.md`](./sdk-documentation/quality-gates.md), because the
gate set is the thing phase 0 built, [`sdk-documentation/http.md`](./sdk-documentation/http.md),
because the domain model is the thing phase 1 built,
[`sdk-documentation/seams.md`](./sdk-documentation/seams.md), because the seam layer is the thing
phase 2 built, [`sdk-documentation/io.md`](./sdk-documentation/io.md), because the byte-streaming
layer is the thing phase 3a built, [`sdk-documentation/body.md`](./sdk-documentation/body.md),
because the body layer is the thing phase 3b built,
[`sdk-documentation/execution-context.md`](./sdk-documentation/execution-context.md), because the
execution context is the thing phase 4a built,
[`sdk-documentation/recovery.md`](./sdk-documentation/recovery.md), because the recovery layer and
the error trail are the things phase 4b built,
[`sdk-documentation/pipelines.md`](./sdk-documentation/pipelines.md), because the stage pipeline is
the thing phase 4c built, and
[`sdk-documentation/configuration.md`](./sdk-documentation/configuration.md), because the
configuration layer and the clock are the things phase 5a built,
[`sdk-documentation/tracing-and-metrics.md`](./sdk-documentation/tracing-and-metrics.md), because
the tracing and metrics layer is the thing phase 5c built,
[`sdk-documentation/logging-and-redaction.md`](./sdk-documentation/logging-and-redaction.md),
because the logging facade and redaction are the things phase 5b built,
[`sdk-documentation/retry.md`](./sdk-documentation/retry.md), because the retry layer — one policy
core and its two stacks — is the thing phase 6a built,
[`sdk-documentation/auth.md`](./sdk-documentation/auth.md), because the authentication layer is
the thing phase 6c built,
[`sdk-documentation/redirect.md`](./sdk-documentation/redirect.md), because the redirect layer and
the two `standard` constructors are the things phase 6b built,
[`sdk-documentation/sse.md`](./sdk-documentation/sse.md), because the server-sent-events layer and
the serde-boundary gate are the things phase 7b built,
[`sdk-documentation/pagination.md`](./sdk-documentation/pagination.md), because the pagination
layer — the page value, the strategies, the two views, the two engines and the fetcher front-end —
is the thing phase 7c built,
[`sdk-documentation/serde.md`](./sdk-documentation/serde.md), because the serialization layer and the
JSON codec are the things phase 7a built, and
[`sdk-documentation/transport-net_http.md`](./sdk-documentation/transport-net_http.md) and
[`sdk-documentation/conformance.md`](./sdk-documentation/conformance.md), because the synchronous
transport and the conformance suite are what phase 8a built — the first code outside
`dexpace-core` after 7a's codec — and
[`sdk-documentation/async-thread.md`](./sdk-documentation/async-thread.md), because the thread pool
that is the async path's first executor is what phase 8b built.

## Keeping this file true

```bash
ruby .claude/skills/housekeeping/probe.rb
```

The [`housekeeping`](../.claude/skills/housekeeping/SKILL.md) skill probes every claim here
against the repository — the gem count, the phase-directory count, the harvested-topic count,
a README on every gem, broken relative links, register text in the wrong document, and a
citation that resolves to nothing. It is a hand-run tool, not a CI step. Run it before
claiming the documentation is current.
