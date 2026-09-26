## What and why

<!-- One concern per pull request. What changes, and why. Link the issue: "Closes #…". -->

## Requirements

<!-- The docs/product-spec/ requirement IDs this satisfies, changes or touches (e.g. HTTP-7, RETRY-13),
     and where each is cited: the test file's header comment, the branch it forced. "None" for a
     change no requirement governs (tooling, docs). -->

## Verification

<!-- What you ran and on which Ruby. Tick what applies. -->

- [ ] `bundle exec rake` — all twenty-four gates — green on Ruby ____
- [ ] A test that failed before this change and passes after it (for a fix or a behaviour change)
- [ ] `sig/` updated beside `lib/`, and the runtime surface snapshot regenerated deliberately if the public surface changed
- [ ] `ruby .claude/skills/housekeeping/probe.rb` exits 0 (for a change under `docs/`, `CLAUDE.md` or a README)

## Records

- [ ] A deviation from the reference contract is recorded in the owning Deviation Ledger and `docs/deviations.md`, or there is none
- [ ] Release work this uncovers or closes is recorded in `docs/first-release.md`, or there is none
- [ ] The checklist, the as-built page under `docs/sdk-documentation/` and the gem README still describe the code
- [ ] Nothing under `docs/product-spec/` or `docs/sdk-design-ruby/` was edited (frozen to routine work)
