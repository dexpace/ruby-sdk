# api-design

## Rules
- Minimize the public surface of a module by treating everything that is not part of the contract as `private` or `protected`, defining a method without visibility first and promoting it to public only when a genuine external caller needs it.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:75-113` · high · sha:7d8f43b477f9</sub>
- Every public method must carry a Sorbet `sig`, since the sig is the written, runtime-checked contract rather than mere documentation.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:115-123` · high · sha:7d8f43b477f9</sub>
- Use keyword arguments on every public method because positional arguments are order-dependent and backward-incompatible to extend, whereas a new keyword with a default is always backward-compatible.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:125-145` · high · sha:7d8f43b477f9</sub>
- A public method should accept the narrowest duck-typed interface it actually uses and return a concrete, frozen value rather than a wide type.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:147-171` · high · sha:7d8f43b477f9</sub>
- Every collection, hash, or struct returned from a public method must be frozen before it leaves, so callers cannot mutate it and corrupt the module's internal state.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:152-171` · high · sha:7d8f43b477f9</sub>
- Parse raw input (a `Hash` from JSON, a `String` from a form param, an `Integer` from a query string) once at the boundary into a typed value object, and never pass a raw `Hash` or scalar deeper into the system.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:173-208` · high · sha:7d8f43b477f9</sub>
- `T.untyped` is permitted in a method signature only in parse-constructors, which are named `parse` by convention, take raw input, validate fully, and return a typed immutable value.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:179-208` · high · sha:7d8f43b477f9</sub>
- Do not return `nil` from a public method to mean "absent" where an empty collection or a raised error is clearer; when `nil` is legitimate, type the return as `T.nilable` and document what `nil` means in a YARD comment.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:210-242` · high · sha:7d8f43b477f9</sub>
- Keep API symmetry so that paired operations (such as `parse`/`to_h`, `encode`/`decode`, `open`/`close`, `begin_transaction`/`commit`/`rollback`) share names, argument shapes, return conventions, and error contracts.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:244-278` · high · sha:7d8f43b477f9</sub>
- Asymmetry that exists for a reason, such as a one-way operation with no inverse, must be documented as a conscious design decision rather than left as an apparent oversight.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:249-249` · high · sha:7d8f43b477f9</sub>
- Deprecate a public method deliberately by marking it with a runtime `warn` and an `@deprecated` YARD tag naming the replacement and removal version, keeping it as a thin delegation for one full major cycle before deleting it on the next major bump.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:280-301` · high · sha:7d8f43b477f9</sub>
- Every optional keyword argument must have a default documented via a `@param` YARD note naming the default value, and callers should pass only the keyword arguments that differ from those defaults.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:303-331` · high · sha:7d8f43b477f9</sub>
- Changing a default value for an existing optional keyword argument in a library is a breaking change (MAJOR) because it changes behavior for callers who relied on the old default without passing it explicitly.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:308-308` · high · sha:7d8f43b477f9</sub>
- Keyword arguments with defaults must come after required keywords in a method signature.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:309-309` · high · sha:7d8f43b477f9</sub>
- Never reorder keyword arguments in an already-published method signature, even though reordering keywords is not technically breaking for callers.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:333-357` · high · sha:7d8f43b477f9</sub>
- Adding a new required keyword argument to a published signature is a breaking change even though the arguments are keyword-based, because existing callers that omit it will raise `ArgumentError`; add it only with a MAJOR bump or make it optional with a default that preserves existing behavior.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:339-339` · high · sha:7d8f43b477f9</sub>
- Define value-object protocol methods (`==`, `hash`, `to_h`, `to_s`) via `Data.define` or `T::Struct` rather than hand-rolling them, and override a generated protocol method only when the custom behavior differs meaningfully, with a why-comment explaining the deviation.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:359-398` · high · sha:7d8f43b477f9</sub>
- The public API surface SHOULD be explicit and minimal, with every exported declaration deliberately public and typed, implementation details kept non-exported, and each adapter's public surface as small as its capability allows. (NFR-3)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:12` · high · sha:5f4684bf7123</sub>
- The public API of every published unit SHOULD be captured in a checked-in, machine-comparable snapshot with the build failing on drift, and an intentional API change is landed by regenerating and committing the snapshot in the same change rather than using the regeneration tool to silence an unintentional break. (NFR-4)
  <sub>spec · `docs/product-spec/20-non-functional-requirements-and-quality-bar.md:13` · high · sha:5f4684bf7123</sub>

## Constraints
- Under `# typed: strict`, `srb tc` mechanically rejects any method that lacks a `sig`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:121-123` · high · sha:7d8f43b477f9</sub>
- Code review rejects `T::Hash[Symbol, T.untyped]` in any non-boundary method signature.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:208-208` · high · sha:7d8f43b477f9</sub>

## Conclusions

## Reference
- In Ruby, every method is public by default, so explicit `private`/`protected` declarations are the only mechanism separating implementation detail from API contract.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:80-80` · high · sha:7d8f43b477f9</sub>
- The only sanctioned positional argument on a public method is the implicit `self` receiver.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:131-131` · high · sha:7d8f43b477f9</sub>
- Semver classification is: removing/renaming a public method, narrowing a parameter type, or changing return semantics is a MAJOR bump; adding a new optional keyword argument or a new method is a MINOR bump; a bug fix that preserves the contract is a PATCH bump.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:285-285` · high · sha:7d8f43b477f9</sub>
- Choose `T::Struct` with `const` fields when Sorbet must track field types with runtime checking; choose `Data.define` when a lightweight, stdlib-only value is sufficient.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/10-api-design.md:364-364` · high · sha:7d8f43b477f9</sub>
- Chapter 10 (API Design) covers minimal public surface, keyword arguments, a `sig` on every public method, accepting duck types while returning frozen concretes, parsing at boundaries, deprecation and semver, and API symmetry.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:43-43` · high · sha:fa61163448dd</sub>

## Conflicts

## Superseded
