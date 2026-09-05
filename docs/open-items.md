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

No items yet.

next id: OI-1
