# type-system

## Rules
- Both `sorbet-static` and `sorbet-runtime` must be wired into the project; the former performs offline static analysis and the latter enforces `sig` contracts at runtime.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:79` · high · sha:9dd0b475bc7d</sub>
- `srb tc` must run as a hard CI gate, blocking merge on a new file that fails the typechecker or an existing file that degrades its sigil to `# typed: false` without a ledger entry.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:80` · high · sha:9dd0b475bc7d</sub>
- New files must use `# typed: strict` as the minimum sigil, which requires a `sig` on every method and treats missing return types as errors.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:81` · high · sha:9dd0b475bc7d</sub>
- Lower Sorbet sigils (`# typed: true`, `# typed: false`, `# typed: ignore`) are permitted only for legacy bridges not yet migrated, and every such file must be recorded in a migration tracking list in the repo.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:81` · high · sha:9dd0b475bc7d</sub>
- Every file must set the `# typed: strict` sigil.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:87-90` · high · sha:8d551aa6e6b7</sub>
- `# typed: true` is a bridge level, not a resting state; every file at `true` is a tracked deviation recorded with a `TODO` naming the migration owner and target date.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:91` · high · sha:8d551aa6e6b7</sub>
- Every method must carry a `sig`, written immediately above the method definition with no blank line between them.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:97-104` · high · sha:8d551aa6e6b7</sub>
- Every instance variable must be declared with `T.let` in `initialize`, in a consistent declaration order.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:122-127` · high · sha:8d551aa6e6b7</sub>
- This `T.let`-in-`initialize` rule governs classes that hold their own instance variables; value objects must declare typed `const` fields on `T::Struct` instead of hand-rolled instance variables.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:130` · high · sha:8d551aa6e6b7</sub>
- `T.nilable` must be treated as a last resort; a method that cannot produce a value should raise a typed error, return an empty collection, or return a result type rather than return `nil`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:148-153` · high · sha:8d551aa6e6b7</sub>
- Legitimate uses of `T.nilable` are limited to fields genuinely absent in the domain model, optional keyword arguments, or interfaces to external systems that emit `nil`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:154` · high · sha:8d551aa6e6b7</sub>
- Safe navigation (`&.`) must be used only where `nil` is a legitimate, documented value at that point.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:173-176` · high · sha:8d551aa6e6b7</sub>
- `&.` should be reserved for receivers declared `T.nilable` or `T.untyped` at the boundary of external input; a typed domain object should not need safe navigation.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:178` · high · sha:8d551aa6e6b7</sub>
- `Hash#fetch` and `Array#fetch` must be used for keys and indices that must exist, rather than `hash[key]` which returns `nil` silently on a missing key.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:196-200` · high · sha:8d551aa6e6b7</sub>
- `T.must` and `T.unsafe` are banned outside declared bridge points, and every bridge use must carry a why-comment.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:217-223` · high · sha:8d551aa6e6b7</sub>
- Each declared bridge point (e.g. an untyped gem, a codegen boundary, a Sorbet inference limitation) must be entered in the deviations ledger with an owner and a plan to close it.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:223` · high · sha:8d551aa6e6b7</sub>
- `T.cast` is the single sanctioned cast and requires a why-comment on every use.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:241-246` · high · sha:8d551aa6e6b7</sub>
- `T.cast` must be preceded immediately by a validation of the value, with the why-comment citing what the validation proved.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:245-246` · high · sha:8d551aa6e6b7</sub>
- When reaching for `T.cast`, prefer alternatives first: `case/in` pattern matching, a discriminant field on a `T::Struct`, or a Sorbet `sealed!` hierarchy with exhaustive matching.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:247` · high · sha:8d551aa6e6b7</sub>
- Exactly one parse-constructor per type must take raw (`T.untyped`) input, validate it completely, and return a typed, immutable value object; every other method takes the typed form.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:267-273` · high · sha:8d551aa6e6b7</sub>
- The parse-constructor is the only sanctioned place for `T.cast` or a direct `T.let` on a newly constructed object, because validation sits immediately above it.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:273` · high · sha:8d551aa6e6b7</sub>
- Closed sets of domain states must be modeled with `T::Enum`; free-floating symbols or strings must never be used for domain states.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:309-312` · high · sha:8d551aa6e6b7</sub>
- At a system boundary (JSON deserialization, database column), a raw string must be parsed into a `T::Enum` using `MyEnum.deserialize(raw)`, which raises on unknown values.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:315` · high · sha:8d551aa6e6b7</sub>
- `T::Struct` or `Data.define` must be used for typed value objects at boundaries; a `Hash` crossing a boundary is treated as unparsed input.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:342-346` · high · sha:8d551aa6e6b7</sub>
- `T::Hash[Symbol, T.untyped]` must not appear in any non-boundary method signature.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:372` · high · sha:8d551aa6e6b7</sub>
- A return type must be non-nil unless `nil` genuinely models an absent domain value that could be explained to a domain expert.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:374-377` · high · sha:8d551aa6e6b7</sub>
- A method that always returns a value or otherwise raises must declare a non-nil return type; only a method that models "value or absent" should return `T.nilable`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:379` · high · sha:8d551aa6e6b7</sub>

## Constraints
- At Sorbet's `strict` level, every method must carry a `sig`, every constant must be typed, and every instance variable must be declared.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:90` · high · sha:8d551aa6e6b7</sub>
- A missing `sig` under `# typed: strict` is a compile error with no opt-out.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:102` · high · sha:8d551aa6e6b7</sub>
- `&.` on a receiver with a non-nilable Sorbet type is rejected by the type checker as a type error.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:177` · high · sha:8d551aa6e6b7</sub>

## Conclusions
- `T::Struct` is required at `# typed: strict`; `Data.define` is acceptable only for small, internal value objects in files at `# typed: true` that have not yet been migrated.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:348` · high · sha:8d551aa6e6b7</sub>

## Reference
- A `sig` is a runtime-executed assertion, not documentation, and a method whose runtime argument violates its `sig` raises `TypeError` immediately.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:82` · high · sha:9dd0b475bc7d</sub>
- A Sorbet `sig` is enforced at runtime, checking every argument type and the return type on every call, so an incorrect argument is rejected at the caller rather than several stack frames later.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:100-101` · high · sha:8d551aa6e6b7</sub>
- Without `T.let`, Sorbet infers instance-variable types from assignment sites, and conditional assignment (in a branch, guard, or callback) causes Sorbet to widen the inferred type to include `NilClass`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:125` · high · sha:8d551aa6e6b7</sub>
- `fetch` with a block is the sanctioned form for providing computed defaults, and `fetch` with a second argument is the form for static defaults.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:201` · high · sha:8d551aa6e6b7</sub>
- Under Sorbet, `hash[key]` on a `T::Hash[K, V]` returns `T.nilable(V)`, while `hash.fetch(key)` returns the non-nilable `V`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:202` · high · sha:8d551aa6e6b7</sub>
- `T.must(x)` asserts non-nilness to Sorbet without proof, and if the assertion is wrong, the runtime raises `TypeError` at the `T.must` call site rather than where the `nil` originated.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:220` · high · sha:8d551aa6e6b7</sub>
- `T.unsafe(x)` disables all Sorbet checking on the value and everything derived from it, functioning as Ruby's equivalent of TypeScript's `any` cast.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:221` · high · sha:8d551aa6e6b7</sub>
- A `case` statement on a `T::Enum` value can be checked for exhaustiveness by adding a final `else T.absurd(status)` branch, which fails at runtime if a new member is added without updating the switch.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:313` · high · sha:8d551aa6e6b7</sub>
- Chapter 03 (Type Safety & Nil Discipline) covers `# typed: strict`, requiring a `sig` on every method, requiring a stated reason for `T.let`/`T.cast`, banning `T.must` outside bridges, `&.`, preferring `fetch` over `[]`, disallowing nil across boundaries, and parse-don't-validate.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:36-36` · high · sha:fa61163448dd</sub>

## Conflicts
- **styleguide vs design: static typing stack** — the styleguide mandates Sorbet with # typed: strict on every file, a runtime-checked sig on every method, and srb tc as the first CI gate; the design ships RBS signatures under sig/ gated by rbs validate and steep check, with no Sorbet dependency
  <sub>styleguide `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:87-104` · styleguide `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:79-82` · design `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:11-12` · unresolved 2026-09-05</sub>

## Superseded
