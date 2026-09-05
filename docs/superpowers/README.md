# `docs/superpowers/` — the inbox, not the archive

New phase documents land here. They do not stay here.

The Superpowers `brainstorming` and `writing-plans` skills write to hard-coded paths —
`docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` and
`docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`. Those skills are installed globally,
shared across projects, and this repository cannot change them. So the path stays, and this
directory is the drop point it writes into.

The archive is [`docs/work/`](../work/). Every finished (sub)phase's design, plan and
checklist lives under `docs/work/<delivery>/phaseN[/phaseNx]/`, each file keeping its
`YYYY-MM-DD-` prefix. The layout and the naming rules are in [`docs/README.md`](../README.md).

## What to do with a file that appears here

Run the [`housekeeping`](../../.claude/skills/housekeeping/SKILL.md) skill. Its probe stage
lists every file sitting in `specs/` or `plans/` — staged or not — and its apply stage works
out which `docs/work/<delivery>/phaseN[/phaseNx]/` directory each belongs in and moves it with
`git mv`, so `git log --follow` resolves the file across the move.

```bash
ruby .claude/skills/housekeeping/probe.rb --only inbox
ruby .claude/skills/housekeeping/apply.rb --phase 5a            # dry run
ruby .claude/skills/housekeeping/apply.rb --phase 5a --write
```

**It does not repoint the references.** That is deliberate, and the tool says so when it
finishes: a maintenance tool that rewrites prose to make its own check pass produces
documentation that is true and useless at the same time. After `--write`, run the probe's
`links` and `citations` checks and fix what they report, in the same commit. Doing the whole
thing by hand is fine too.

A file left here is not lost — it is just not filed. The probe reports it every run until it
is.

## What must not happen here

Do not point a citation at `docs/superpowers/`. It is a staging path, and anything written
here is scheduled to move. Cite `docs/work/<delivery>/phaseN/<file>` — the path the document
will have for the rest of its life. The one deliberate exception is a document describing the
*skills'* write behaviour, such as this file.
