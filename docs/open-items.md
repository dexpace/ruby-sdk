# Open Items

Running register of everything found to be unmet, unverified, misreported, or surprising in the
Ruby SDK. **This records what is known and not yet resolved — it is not a plan.** A finding lands
here whether or not anyone has yet decided what to do about it; deciding what to do is a separate
act from noticing the gap.

An open item is a discovery made **after** the work it checks against already exists: "this is not
what the design, the checklist, or the code claims it is." That is the boundary against the other
two registers at the `docs/` root:

| Register | Holds | Item is |
|---|---|---|
| `open-items.md` (this file) | Everything found unmet, unverified, misreported, or surprising | A gap discovered **after** the work |
| [`deferred-items.md`](./deferred-items.md) | Work consciously postponed while building the SDK | A decision made **before** the work: "not this phase, that one" |
| [`deviations.md`](./deviations.md) | The as-built audit of `sdk-design-ruby/10`'s deviation ledger | A place the port deliberately differs from the reference contract, and whether that has landed in code |

The same requirement ID can legitimately appear in more than one register at once.

## Item format

```
### OI-<n> — <title>

- **Opened:** <date>, <phase or source that found it>
- **Status:** open | resolved (<date>)
- **Cites:** <requirement IDs this touches, comma-separated, or "none">

<Body: what was found, why it matters, and what would resolve it.>

**Resolution:** <filled in only once Status moves to resolved — what changed, and where>
```

`Opened` names both a date and where the finding came from — a phase, a review, an audit pass — so
a later reader can tell what state of the repository produced it. `Cites` links the finding to the
normative requirement IDs it bears on, if any; `none` is a legitimate value for a purely
structural or process finding.

## The rule

Item IDs are **permanent**: never renumbered, never reused. They are cited from source comments,
tests, design documents, and phase records as well as from this file. **A resolved item is never
deleted.** It stays, with `Status: resolved (<date>)` and a filled-in `Resolution`, so that every
citation of `OI-<n>` anywhere in the repository — including one written before the item was
resolved — still resolves to something. A section that shrinks as items are "cleaned up" is a
section whose citations quietly start pointing at nothing.

A new item takes the next id below and appends; nothing here is edited except to fill in `Status`
and `Resolution` on an existing item.

---

### OI-1 — Five SEAM requirements exist only as appendix-C rows, and the gap pointer sends a reader to a chapter that does not carry them

- **Opened:** 2026-09-06, phase 2 (Seam Foundations) planning
- **Status:** open
- **Cites:** SEAM-15, SEAM-20, SEAM-22, SEAM-23, SEAM-28

`docs/product-spec/03-pluggable-seams-and-extension-model.md` carries 22 of the 30 `SEAM` IDs in
its prose, `SEAM-29` among them. Three more — `SEAM-1`, `SEAM-2` and `SEAM-13` — are stated only in
`docs/product-spec/02-architectural-principles.md`, which also restates `SEAM-29`. That accounts
for 25. The remaining five — **`SEAM-15`, `SEAM-20`, `SEAM-22`, `SEAM-23` and `SEAM-28`** — appear
nowhere in the specification's prose at all:
`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` is their only normative
statement. Verified on 2026-09-06 and re-verified on 2026-09-07 with
`grep -o 'SEAM-[0-9]*' docs/product-spec/*.md | grep -v appendix-c | sort -uV`, which lists exactly
25 IDs.

Why it matters rather than being a curiosity. Both the roadmap's gap paragraph
(`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`) and
`ruby scripts/knowledge.rb --gaps SEAM` tell a phase to read `SEAM-22` and `SEAM-28` "out of
`docs/product-spec/03-pluggable-seams-and-extension-model.md`", and neither ID is in that file. A
phase following the instruction literally either reads the wrong requirements or concludes the
specification is missing them — and the two that carry the pointer are precisely the two the corpus
cannot answer, so the phase reading them has no second source. The CLI is not wrong: it derives the
pointer from appendix C's own subsystem cell, so it names the subsystem's owning chapter rather
than asserting the ID is in it. The roadmap inherited that pointer and restated it as an
instruction.

The three IDs beyond the two named gaps are the quieter half: `SEAM-15`, `SEAM-20` and `SEAM-23`
*do* have substantive corpus entries — all three are design-role, from
`docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.4 and §3.7 — so a phase querying the
corpus gets a good answer and never learns that the design entry is the only prose between it and
appendix C. Phase 2 read all five out of appendix C directly and says so in its design.

What would resolve it: either the specification gains prose for the five (which is a change to a
frozen tree and a human's deliberate act), or the roadmap's gap paragraph and
`scripts/knowledge.rb`'s `--gaps` output name **appendix C** as the source for an ID whose
subsystem chapter does not contain it. The second is the smaller change and is mechanical — the CLI
already knows every ID's location, so it could compare against the chapter text rather than
assuming it.

**Resolution:** *(open)*

next id: OI-2
