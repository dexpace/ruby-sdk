# data-modeling — notes

Hand-written. `../harvested/data-modeling.md` is what the documents say; this file is what the
implementation found, and it wins. Each entry names the harvested entry it answers by that
entry's stable key.

## Conflicts
- **Value-object base type: the design wins — `Data.define` is the base for every core domain type, and `T::Struct` is not available to this port at all.** Resolves `data-modeling/35fde90f`. The styleguide's rule is conditional on Sorbet (`T::Struct` is the `# typed: strict` default *because* Sorbet cannot type `Data.define` members), and this SDK has no Sorbet: `T::Struct` is defined by `sorbet-runtime`, a third-party gem that would have to appear as an `add_dependency` in `dexpace-core.gemspec`, which `SEAM-1`/`NFR-1` forbid and the gemspec audit mechanically rejects. The premise the styleguide rule rests on is therefore absent, not overruled. What the SDK does instead: every core model is `Data.define` with an `initialize` override that validates and calls `super`, collections `dup`ed and frozen exactly once at construction, `private_class_method :new` plus a validating `.build`, and `sig/**/*.rbs` carrying the per-member types RBS can express and Sorbet was wanted for. The styleguide's own reasoning for `Data.define` — frozen on construction, `==`/`hash`/`with` for free, keyword constructor enforced — is adopted in full. The styleguide-amendment alternative (scoping the `T::Struct` preference to "projects using Sorbet") was considered and not taken; this is recorded as an SDK deviation instead.
  <sub>review · `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` · high · sha:manual-roadmap-conflict-1</sub>
