# assertions

## Rules
- Methods must assert aggressively, averaging 2 or more assertions per method across a module, checking arguments at entry and results before return.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:297-301` · high · sha:3c2b6c47162f</sub>
- Explicit value-level assertions must supplement `sig` type checks for properties Sorbet cannot express, such as an array being non-empty or a monetary total being non-negative.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:301-301` · high · sha:3c2b6c47162f</sub>
- Assertions must cover both positive and negative space — verifying that the expected holds and that the impossible is absent — using independent assertions for separate failure modes.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:302-302` · high · sha:3c2b6c47162f</sub>
- A property should be pair-asserted by verifying it two independent ways so that disagreement between the two derivations surfaces at the assertion rather than downstream.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:303-303` · high · sha:3c2b6c47162f</sub>
- `Assert.that` is the sole sanctioned assertion primitive in the codebase.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:329-329` · high · sha:3c2b6c47162f</sub>

## Constraints

## Conclusions
- The project defines a single project-wide `Assert` module with a dedicated `InvariantViolation` error class so callers can distinguish a broken invariant (programmer error) from an operational failure they might recover from.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:304-325` · high · sha:3c2b6c47162f</sub>

## Reference
- `Assert.that(condition, message)` raises `Assert::InvariantViolation` unless the condition holds, and `Assert.fail(message)` unconditionally raises `Assert::InvariantViolation` for exhaustive case analysis and unreachable branches.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:312-327` · high · sha:3c2b6c47162f</sub>
- Assertion density is enforced through review as a target rather than through a lint rule.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:329-329` · high · sha:3c2b6c47162f</sub>

## Conflicts

## Superseded
