# data-modeling

## Rules
- Every mutable constant must be frozen with `.freeze` at the point of assignment, since a constant name bound to a mutable object can be corrupted by any caller with access to it.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:149-150` · high · sha:c2def8078f0c</sub>
- Typed constants must be wrapped in `T.let` so Sorbet checks the constant's type at load time.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:150-150` · high · sha:c2def8078f0c</sub>
- `attr_reader` must be used for any trivial instance-variable accessor that is part of a public interface.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:281-284` · high · sha:c2def8078f0c</sub>
- `attr_writer` and `attr_accessor` must never be added to value objects because mutation is forbidden for objects whose identity is defined by their values at construction time.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:281-285` · high · sha:c2def8078f0c</sub>
- When an attribute genuinely needs to change over an object's lifetime, it must be exposed via an explicit `def x=(value)` writer with a `sig` and a why-comment explaining the lifecycle, rather than via `attr_writer`/`attr_accessor`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:286-286` · high · sha:c2def8078f0c</sub>
- Model domain records as typed value objects (T::Struct, Data.define) and group their transformations into modules of functions rather than wrapping them in classes.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:100-106` · high · sha:d92dcab09c01</sub>
- Reserve a class for the narrow case where an instance owns a lifecycle, tested by whether open/close or start/stop operations are meaningful for it.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:104` · high · sha:d92dcab09c01</sub>
- Code review rejects a class that has no instance state and no lifecycle, since a zero-instance-method class holding only def self.* methods is a module in disguise.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:130` · high · sha:d92dcab09c01</sub>
- Prefer a module of functions over a class whose public interface is entirely class methods.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:132-135` · high · sha:d92dcab09c01</sub>
- Use `module Foo; extend self; end` only for simple utility modules; for modules that need `sig` on class methods, use a single `class << self; extend T::Sig; end` block instead.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:136` · high · sha:d92dcab09c01</sub>
- Never use module_function; prefer extend self or class << self as a single idiom.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:137` · high · sha:d92dcab09c01</sub>
- RuboCop's Style/ModuleFunction cop governs module_function usage, with the project default being extend self or class << self.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:164` · high · sha:d92dcab09c01</sub>
- Use Data.define for immutable value objects and use T::Struct when Sorbet must track each field's type.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:166-170` · high · sha:d92dcab09c01</sub>
- At `# typed: strict`, T::Struct is the default value-object type; Data.define is acceptable only in `# typed: true` files that have not yet been migrated.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:170` · high · sha:d92dcab09c01</sub>
- Struct with keyword_init: true is permitted only when Struct-specific behaviour (members, positional construction, subclassing for test doubles) is required, and must always be used with keyword_init: true.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:171` · high · sha:d92dcab09c01</sub>
- Never use a plain Struct where Data.define or T::Struct suffices, because plain Struct fields are mutable by default.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:171` · high · sha:d92dcab09c01</sub>
- A hand-rolled class with attr_reader and a freeze call in initialize is acceptable only when the class adds methods beyond data access; pure data should use T::Struct or Data.define.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:172` · high · sha:d92dcab09c01</sub>
- RuboCop's Style/MutableConstant cop and code review reject mutable Struct fields, and Sorbet's srb tc rejects T.untyped field access in `# typed: strict` files.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:192` · high · sha:d92dcab09c01</sub>
- Write parse-don't-validate constructors that interrogate raw input exactly once at the boundary and return frozen, valid instances.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:194-197` · high · sha:d92dcab09c01</sub>
- Make `new` private (or rely on T::Struct's tracked constructor) so the parse-constructor is the single entry point and no caller can bypass validation to construct an invalid instance.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:198` · high · sha:d92dcab09c01</sub>
- Raise ArgumentError with a message that names the offending value and the violated constraint.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:199` · high · sha:d92dcab09c01</sub>
- Pair assertions in a parse-constructor by checking a constraint positively and then negatively where the derivations are independent, and confirm validity with a postcondition check inside the constructor.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:200` · high · sha:d92dcab09c01</sub>
- Code review rejects domain methods whose parameter types are raw Integer, String, or T.untyped where a value object already exists.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:234` · high · sha:d92dcab09c01</sub>
- Compose behaviour via include/prepend/extend and delegate via Forwardable's def_delegators; subclass only for StandardError trees.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:236-241` · high · sha:d92dcab09c01</sub>
- Code review rejects the `<` inheritance operator unless the parent is a StandardError subclass, a Sorbet structural base type (T::Struct, T::Enum), or a Sorbet abstract/sealed module.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:286` · high · sha:d92dcab09c01</sub>
- RuboCop's Style/Delegation cop encourages def_delegators over hand-rolled forwarding.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:286` · high · sha:d92dcab09c01</sub>
- Never use `@@` class variables; use a class instance variable for class-level state instead.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:288` · high · sha:d92dcab09c01</sub>
- If the real intent of shared state is a process-global registry, use an explicit singleton module (Module.new { extend self; ... }) with documented mutability rather than a class variable.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:294` · high · sha:d92dcab09c01</sub>
- RuboCop's Style/ClassVars cop bans `@@` class variables, and srb tc flags untyped class variables under `# typed: strict`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:329` · high · sha:d92dcab09c01</sub>
- Group all class methods in a single `class << self` block rather than scattered `def self.*` declarations.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:331-336` · high · sha:d92dcab09c01</sub>
- Add `extend T::Sig` as the first line inside a class << self block so Sorbet can attach sig blocks to class methods; omitting it causes srb tc to flag every sig inside the block as unresolved.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:337` · high · sha:d92dcab09c01</sub>
- RuboCop's Style/ClassMethodsDefinitions cop is configured to enforce class << self; code review rejects def self.* outside such a block.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:373` · high · sha:d92dcab09c01</sub>
- Make illegal states unrepresentable by using T::Enum for closed sets instead of free symbols or strings.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:375-378` · high · sha:d92dcab09c01</sub>
- Close a case statement on a T::Enum or sealed hierarchy with `else T.absurd(value)` so Sorbet can prove exhaustiveness.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:379` · high · sha:d92dcab09c01</sub>
- For a closed hierarchy of classes with shared behaviour, combine abstract! and sealed! on the parent module.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:380` · high · sha:d92dcab09c01</sub>
- Never model a state transition as an optional field (e.g. T.nilable); instead give the relevant enum member a mandatory field so it is absent on all other states without a nil guard.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:381` · high · sha:d92dcab09c01</sub>
- srb tc rejects passing a raw Symbol or String where a T::Enum is required, and every case on a T::Enum or sealed module must close with T.absurd at code review.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:425` · high · sha:d92dcab09c01</sub>
- Define small, duck-typed interfaces as Sorbet abstract modules with sig { abstract... } stubs, and have concrete implementations include them.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:427-431` · high · sha:d92dcab09c01</sub>
- Name interface modules by role (e.g. Priceable, Fulfillable, Auditable), not by implementation family (e.g. AbstractOrder, BaseRepository).
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:432` · high · sha:d92dcab09c01</sub>
- Keep interfaces small, at one to three methods, so callers that need only one method depend on the one-method module.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:433` · high · sha:d92dcab09c01</sub>
- srb tc enforces the `override` keyword on every implementation of an abstract method.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:471` · high · sha:d92dcab09c01</sub>
- Expose attr_reader only on value objects; never expose a setter (attr_writer, attr_accessor, or a hand-written field= method) that lets an invariant break after construction.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:473-476` · high · sha:d92dcab09c01</sub>
- Model a "modified" value as a method that returns a new instance (e.g. `with` on Data.define or T::Struct, or an explicit factory method) rather than mutating in place.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:478` · high · sha:d92dcab09c01</sub>
- For lifecycle classes that hold mutable state, setters may be warranted only when the class owns the mutation as part of its defined lifecycle contract, exposed through a narrow named method rather than a raw attr_accessor.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:479` · high · sha:d92dcab09c01</sub>
- Code review rejects attr_writer and attr_accessor on any T::Struct or Data.define value object.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:511` · high · sha:d92dcab09c01</sub>
- Respect the Liskov Substitution Principle whenever inheritance is used: every subclass must be usable wherever its parent is accepted, with no surprises.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:513-516` · high · sha:d92dcab09c01</sub>
- Never override a method to change shared logic; override only to extend, calling super first or last and then adding, never replacing the body entirely.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:518` · high · sha:d92dcab09c01</sub>
- Code review treats any `override` implementation that does not call `super` as an LSP smell requiring justification.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:554` · high · sha:d92dcab09c01</sub>
- Keep classes small and single-responsibility; if a class cannot be named in one domain noun without an "and," split it.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:556-559` · high · sha:d92dcab09c01</sub>
- Extract a class into multiple types when it has more than one reason to change, such as needing changes for pricing, serialization format, and status reporting separately.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:561` · high · sha:d92dcab09c01</sub>
- All core domain-model types MUST present an immutable value/metadata surface after construction, safe to share across threads without external synchronization, with any change producing a new instance, with the single carve-out of a body wrapping live single-use stream state (HTTP-1).
  <sub>spec · `docs/product-spec/02-architectural-principles.md:12-12` · high · sha:8014d2ec2c9d</sub>
- Model construction MUST go through an immutable-value plus Builder (or dedicated factory) pattern; there MUST be no public field-wise constructor or unchecked copy that bypasses validation (SEAM-29/HTTP-2).
  <sub>spec · `docs/product-spec/02-architectural-principles.md:13-13` · high · sha:8014d2ec2c9d</sub>
- A shared generic Builder contract (build() producing the target type) MUST exist so generic composition helpers can accept any builder, and required-field validation MUST be uniform: a missing required field fails at build() with a message of the form "<name> is required" (SEAM-29, restated).
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:49-49` · high · sha:0adae2d6a47f</sub>
- Each builder-based model (request, response, headers, query params, request options, request conditions, multipart body) MUST expose a newBuilder()-style derivation returning a builder pre-populated from the instance, and that pre-filled builder MUST NOT alias the original's internal collections — each value list is copied (HTTP-3).
  <sub>spec · `docs/product-spec/04-core-http-domain-model.md:7-7` · high · sha:22d100d5bc94</sub>
- build() MUST validate required fields and fail with a field-named error when one is missing — a request requires its URL, a response requires request, protocol, and status — never silently substituting defaults except where explicitly specified (HTTP-4).
  <sub>spec · `docs/product-spec/04-core-http-domain-model.md:8-8` · high · sha:22d100d5bc94</sub>
- Accessors returning collections of header/query names, values, or entries MUST NOT let a caller mutate the model through the returned value, and MUST NOT surface later mutations of a live builder, guaranteed by a build-time deep copy of every value list plus read-only-typed collection returns (HTTP-5).
  <sub>spec · `docs/product-spec/04-core-http-domain-model.md:9-9` · high · sha:22d100d5bc94</sub>
- Every file carries the "# frozen_string_literal: true" magic comment.
  <sub>design · `docs/sdk-design-ruby/04-domain-model-construction.md:15-15` · high · sha:c6fab8d5db91</sub>
- #new_builder returns a builder pre-filled from the instance that dups every collection rather than aliasing it, per HTTP-3, so later builder mutation cannot reach back into the source model.
  <sub>design · `docs/sdk-design-ruby/04-domain-model-construction.md:24-25` · high · sha:c6fab8d5db91</sub>
- Core applies Ractor.make_shareable only to a collection the model has already dup'ed and therefore owns.
  <sub>design · `docs/sdk-design-ruby/04-domain-model-construction.md:36-38` · high · sha:c6fab8d5db91</sub>

## Constraints
- `frozen_string_literal: true` freezes bare string literals but does not freeze array or hash literals, which remain mutable and can be modified by any caller holding a reference.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:148-148` · high · sha:c2def8078f0c</sub>
- RuboCop `Style/MutableConstant` is configured as an error, and `frozen_string_literal: true` is required in every file per rule 01.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:168-168` · high · sha:c2def8078f0c</sub>
- Inheritance is sanctioned only for StandardError subclasses because rescue and is_a? dispatch are built on the class hierarchy and there is no practical substitute.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:242` · high · sha:d92dcab09c01</sub>
- Under `# typed: strict`, `@@var` class variables cannot be typed precisely and srb tc infers them as T.untyped or requires a workaround.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:293` · high · sha:d92dcab09c01</sub>
- Sorbet rejects any attempt to assign to a T::Struct const field after construction.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:477` · high · sha:d92dcab09c01</sub>
- Data.define objects are frozen immediately after construction, so a mutation attempt raises FrozenError.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:477` · high · sha:d92dcab09c01</sub>
- Ruby's freeze is shallow — verified that a Data instance is frozen while a nested Array member is not — so every nested collection must be frozen independently at the same construction step.
  <sub>design · `docs/sdk-design-ruby/04-domain-model-construction.md:32-34` · high · sha:c6fab8d5db91</sub>
- Ruby cannot close HTTP-2/SEAM-29's "no public field-wise constructor" the way a language with enforced constructor privacy can — verified that Req.send(:new, ...) reaches the generated constructor anyway, because send bypassing private is a deliberate, documented Ruby feature, not an oversight.
  <sub>design · `docs/sdk-design-ruby/04-domain-model-construction.md:42-46` · high · sha:c6fab8d5db91</sub>
- Duck typing admits impersonation of a domain model — any object responding to #method, #url, #headers, and #body satisfies every structural expectation a pipeline step has of a Request, entirely bypassing builder validation — and neither this hole nor the private_class_method bypass can be closed in Ruby.
  <sub>design · `docs/sdk-design-ruby/04-domain-model-construction.md:44-49` · high · sha:c6fab8d5db91</sub>

## Conclusions
- Grouping class methods in a class << self block is a recorded deviation from Airbnb's guide (which uses def self.method), chosen to align with Shopify's preference, and is documented in the README deviations ledger.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:336` · high · sha:d92dcab09c01</sub>
- Data.define is used as the base for domain value types because a Data instance is frozen on construction, #with produces a copy with changes, and ==, eql?, and hash are generated consistently over all members, giving the whole value-object contract for free; Data requires all members at construction, which is stricter than the mutable-by-default Struct (verified on 3.4.10).
  <sub>design · `docs/sdk-design-ruby/04-domain-model-construction.md:9-11` · high · sha:c6fab8d5db91</sub>
- Data's ability to override initialize to validate and then call super lets HTTP-4's field-named validation live in the type itself, and a shared helper raises one error type with the fixed message form "<name> is required" so that field-named errors cannot drift between models.
  <sub>design · `docs/sdk-design-ruby/04-domain-model-construction.md:11-14` · high · sha:c6fab8d5db91</sub>
- The port splits domain types exactly along HTTP-3's guidance: MediaType, Status, Protocol, Method, HeaderName, and the conditional-request helpers are Data types with parse/of factories and #with, while Request, Response, Headers, Query, RequestOptions, and Configuration get real mutable Builder classes because their validation is cross-field (HTTP-7 rejects a body on GET/HEAD/TRACE/CONNECT; HTTP-8 defaults the method to GET only when there is no body).
  <sub>design · `docs/sdk-design-ruby/04-domain-model-construction.md:17-24` · high · sha:c6fab8d5db91</sub>
- Because models are genuinely immutable after construction, HTTP-5 does not need a per-access wrapper for collections: each collection is duplicated and frozen exactly once at construction and the same frozen reference is returned from every accessor, satisfying the requirement's own outcome more cheaply than unmodifiable wrappers or per-call defensive copies.
  <sub>design · `docs/sdk-design-ruby/04-domain-model-construction.md:27-32` · high · sha:c6fab8d5db91</sub>
- The mitigation for the encapsulation gap is threefold: the official construction path is genuinely closed via private_class_method :new plus a validating factory; the public API documents and RBS-declares concrete types rather than bare interfaces so a duck-typing caller is knowingly opting out; and the two exploitable invariants — header name and outbound value validation, per HTTP-17, HTTP-18, and XCUT-18 — are re-checked at the model-to-wire boundary inside every transport adapter, not only in the builder, making the residual gap a correctness-of-shape gap rather than a request-splitting gap.
  <sub>design · `docs/sdk-design-ruby/04-domain-model-construction.md:49-57` · high · sha:c6fab8d5db91</sub>

## Reference
- module_function creates a private instance method and a public module-level copy, which is confusing under Sorbet because Sorbet cannot resolve the module-function arity unambiguously.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:137` · high · sha:d92dcab09c01</sub>
- Under `# typed: strict`, Data.define field accessors return T.untyped because Sorbet does not individually type Data.define fields.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:170` · high · sha:d92dcab09c01</sub>
- A `@@var` class variable is shared across the entire inheritance hierarchy, including subclasses added later, so a write in any subclass mutates the ancestor's slot.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:291` · high · sha:d92dcab09c01</sub>
- A class instance variable declared on the class object itself is scoped to exactly one class; writes do not propagate to subclasses even if a reader is inherited.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:292` · high · sha:d92dcab09c01</sub>
- `class << self` opens the singleton class, which gives `private` its expected scoping so that `private :method_name` inside the block makes a class method private, unlike `def self.method` which requires a separate `private_class_method` call.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:334` · high · sha:d92dcab09c01</sub>
- Adding a new enum or sealed-hierarchy member without adding a corresponding case branch causes T.absurd to raise at runtime on the first unhandled call.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:379` · high · sha:d92dcab09c01</sub>
- sealed! restricts subclassing of a module to the same file, and abstract! requires every concrete subclass to implement the abstract interface; Sorbet checks both at typecheck time.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:380` · high · sha:d92dcab09c01</sub>
- The practical Liskov test is to substitute the subclass in the parent's test suite and confirm all tests still pass.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:517` · high · sha:d92dcab09c01</sub>
- RuboCop's Metrics/ClassLength cap is treated as a floor, not a target; the aim is a class whose entire body fits on a screen.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:560` · high · sha:d92dcab09c01</sub>
- A long private-method section or a long initialize parameter list signals that too many concerns or dependencies were merged into one class.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:562` · high · sha:d92dcab09c01</sub>
- Chapter 06 (Classes & Data Modeling) covers data-plus-functions design, modules of functions over class-method bags, `Data.define` value objects, composition via mixins, `T::Enum`/sealed types, and making illegal states unrepresentable.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:39-39` · high · sha:fa61163448dd</sub>
- Value-based types with no builder (media type, status, the typed header name, ETag, HTTP range, method, protocol) are derived by re-constructing through their factories. (HTTP-3)
  <sub>spec · `docs/product-spec/04-core-http-domain-model.md:7-7` · high · sha:22d100d5bc94</sub>
- HTTP-1, HTTP-2/SEAM-29, and XCUT-15 require every core domain type to be immutable and safe to share after construction, constructed only through an immutable value plus a builder or factory, with no public field-wise constructor and no unchecked copy bypassing validation.
  <sub>design · `docs/sdk-design-ruby/04-domain-model-construction.md:3-5` · high · sha:c6fab8d5db91</sub>
- HTTP-3 requires a pre-filled, non-aliasing derivation; HTTP-4 requires build() to validate required fields and fail with a field-named error; HTTP-5 requires accessors to isolate the caller from both the model's internals and a still-live builder.
  <sub>design · `docs/sdk-design-ruby/04-domain-model-construction.md:5-7` · high · sha:c6fab8d5db91</sub>
- Ractor.make_shareable gives a genuine deep freeze, verified to walk the graph freezing nested hashes, arrays, and their string values, but it freezes in place and returns the same object, so applying it to a caller-supplied hash would silently freeze the caller's live object.
  <sub>design · `docs/sdk-design-ruby/04-domain-model-construction.md:34-37` · high · sha:c6fab8d5db91</sub>
- Verified that a Data holding an unfrozen Hash is not Ractor.shareable? while the same Data holding a frozen Hash is, so deep-freezing at construction makes the whole wire model Ractor-shareable today without Ractor being a load-bearing mechanism.
  <sub>design · `docs/sdk-design-ruby/04-domain-model-construction.md:37-40` · high · sha:c6fab8d5db91</sub>

## Conflicts
- **styleguide vs design: value object base type** — the styleguide makes T::Struct the default value-object type at # typed: strict and permits Data.define only in not-yet-migrated # typed: true files; the design bases every domain value type on Data.define with a validating initialize and frozen-once collections
  <sub>styleguide `/home/mohammad/Projects/dexpace/styleguide/ruby/06-classes-and-data-modeling.md:166-172` · styleguide `/home/mohammad/Projects/dexpace/styleguide/ruby/03-type-safety-and-nil-discipline.md:342-348` · design `docs/sdk-design-ruby/04-domain-model-construction.md:9-14` · unresolved 2026-09-05</sub>

## Superseded
