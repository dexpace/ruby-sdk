# styleguide-overview

## Rules
- Prioritize correctness, explicitness, and simplicity over cleverness; never let `nil` leak out of an interface, and never use metaprogramming for its own sake.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:3-3` · high · sha:fa61163448dd</sub>
- Where guidance in the authority chain conflicts, the higher-ranked authority wins, except for the deliberate deviations recorded in the guide's ledger.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:9-11` · high · sha:fa61163448dd</sub>
- `rubocop` plus `rubocop-airbnb`'s cop baseline and formatter decisions are final; formatting is treated as a non-discussion.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:14-14` · high · sha:fa61163448dd</sub>
- Simplicity means choosing the simplest approach that accomplishes the goal — no abstraction for its own sake, no metaprogramming, no cleverness — and when two correct, fast-enough designs differ, the simpler one wins.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:23-23` · high · sha:fa61163448dd</sub>
- Model state as immutable `Data.define` value objects, group behaviour into modules of functions and small duck-typed interfaces, reserve a stateful `class` for lifecycle resources that are opened and closed, and use mixins rather than inheritance for code reuse.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:60-60` · high · sha:fa61163448dd</sub>
- Make every dependency an explicit parameter visible in the method signature, with no `method_missing`, no `define_method` magic, and no monkey-patching; library options follow their documented defaults and callers pass only what differs, through keyword arguments.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:61-61` · high · sha:fa61163448dd</sub>
- Default to immutability — `frozen_string_literal: true` in every file, `freeze` on every constant, `Data.define` over mutable `Struct`, and frozen collections in public signatures — building new values by transformation rather than mutation.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:62-62` · high · sha:fa61163448dd</sub>
- Raise typed `StandardError` subclasses per domain with a class and message, chain them through `cause` on rethrow, never rescue `Exception`, and never use an empty rescue, `rescue nil`, or a modifier rescue that swallows.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:63-63` · high · sha:fa61163448dd</sub>
- Reserve `<` for narrow, Liskov-clean hierarchies and `StandardError` trees, use `T::Enum` or `case/in` for closed polymorphism, and use mixed-in modules for code reuse instead of a deep class tree.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:64-64` · high · sha:fa61163448dd</sub>
- Build pipelines from `map`/`select`/`reduce`, reaching for `each` only for effects or early exit, and avoid mutating arguments so state changes are explicit and localized.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:65-65` · high · sha:fa61163448dd</sub>
- Write comments and YARD to explain reasoning rather than mechanics, since a `sig` already states the types and prose should never restate them.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:66-66` · high · sha:fa61163448dd</sub>
- Add explicit preconditions and postconditions with `raise` on top of a runtime-checked `sig`, averaging a minimum of two assertions per method, splitting compound assertions, and asserting both positive and negative space.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:67-67` · high · sha:fa61163448dd</sub>
- Cap methods at 25 lines (cop-enforced), nesting at three levels, and parameters at four; bound every loop, queue, retry, pool, cache, and fan-out; make timeouts mandatory on external I/O; and disallow unbounded recursion in library code.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:68-68` · high · sha:fa61163448dd</sub>
- Aim for 5-15 line methods at one level of abstraction each, place guard clauses first so the happy path stays flush left, and separate logical sections with blank lines.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:69-69` · high · sha:fa61163448dd</sub>
- Work with the grain of the runtime through stable object shapes, YJIT, frozen strings, and lazy enumerators; batch over per-row work; and optimize the slowest resource first in the order network > disk > memory > CPU.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:70-70` · high · sha:fa61163448dd</sub>
- Ship only what meets the design goals, treating perfection as preferable to technical debt since debt never gets paid and doing it right the first time may be the only chance.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:71-71` · high · sha:fa61163448dd</sub>
- Apply a new or migrated style rule at the file/module level or larger, never mixing two styles within the same file, because a half-migrated file is more confusing than either end state.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:99-99` · high · sha:fa61163448dd</sub>

## Constraints

## Conclusions
- The Ruby style guide's value ordering is correctness > performance > developer experience, following the root README's ordering, with developer experience further refined into simplicity > expressiveness.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:19-19` · high · sha:fa61163448dd</sub>
- Correctness is placed first because in a dynamic language like Ruby it must be actively bought — Sorbet's runtime-checked signatures serve as the first test suite, and nil or a wrong type must not cross a boundary unchecked.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:21-21` · high · sha:fa61163448dd</sub>
- Performance is placed before simplicity because the right architecture is chosen once at design time and is expensive to retrofit, so code should work with the grain of the runtime (YJIT, object shapes, frozen strings, lazy enumerators) and optimize the slowest resource first: network > disk > memory > CPU.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:22-22` · high · sha:fa61163448dd</sub>
- Expressiveness is ranked last in the value order because Ruby's expressive power is treated as a temptation as much as a gift, and clarity is worth nothing if the code is wrong, slow, or needlessly clever.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:24-24` · high · sha:fa61163448dd</sub>
- The Ruby style guide uses shorthand symbol hash keys (`{ one: 1 }`) instead of Airbnb's hash-rocket symbol keys (`{ :one => 1 }`), using hash-rockets only when a key is not a symbol, because Airbnb predates ubiquitous 1.9 syntax and shorthand is the modern community and Shopify default.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:79-79` · high · sha:fa61163448dd</sub>
- The Ruby style guide mandates double quotes everywhere, rather than Airbnb's unspecified/mixed quote style, to remove per-literal decisions and match Shopify.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:80-80` · high · sha:fa61163448dd</sub>
- The Ruby style guide prefers plain literal arrays of double-quoted strings over Airbnb's recommendation to use `%w` freely, because `%w` is a second string syntax to learn while plain arrays are explicit and greppable.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:81-81` · high · sha:fa61163448dd</sub>
- The Ruby style guide uses `find`, `select`, `reduce`, and `map` instead of Airbnb's preferred `detect` and `inject`, because `detect` was an ActiveRecord-disambiguation that no longer earns its keep.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:82-82` · high · sha:fa61163448dd</sub>
- Class methods are grouped in a single `class << self` block rather than defined individually with `def self.method` as Airbnb recommends, because it keeps `private` working for class methods and collects them in one place, matching Shopify.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:83-83` · high · sha:fa61163448dd</sub>
- The Ruby style guide mandates Sorbet `# typed: strict` with runtime `sig` checking as an owner decision, since Airbnb does not address static typing, for maximum safety in a dynamic language through both static and runtime enforcement.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:84-84` · high · sha:fa61163448dd</sub>
- The Ruby style guide imposes a 25-line hard method-size cap (aiming for 5-15 lines), cop-enforced, as an owner decision following Tiger Style discipline and scaled as the Ruby sibling of Go's 70-line and Kotlin's 60-line caps, since Airbnb sets no upstream cap.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:85-85` · high · sha:fa61163448dd</sub>
- The Ruby style guide standardizes on Minitest as the test framework, since Airbnb leaves it unspecified, because Minitest is the Shopify and core-Ruby default.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:86-86` · high · sha:fa61163448dd</sub>

## Reference
- The dexpace Ruby style guide targets Ruby 4.0+, frozen string literals everywhere, Sorbet `# typed: strict` with runtime-checked signatures, and `rubocop` plus `rubocop-airbnb` for tooling.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:3-3` · high · sha:fa61163448dd</sub>
- The Ruby style guide is platform-agnostic, covering the Ruby language, its object model, and runtime-neutral idioms; framework concerns (Rails, Sidekiq, gem packaging beyond the basics) layer on top and never weaken it.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:5-5` · high · sha:fa61163448dd</sub>
- The Airbnb Ruby Style Guide is the canonical, primary source of truth for whitespace, method/call shape, conditionals, and naming.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:11-11` · high · sha:fa61163448dd</sub>
- The Shopify Ruby Style Guide fills the gaps Airbnb leaves open, supplying modern taste such as shorthand hash keys, double quotes, `Hash#fetch`, Minitest, and squiggly heredocs; it is deferred to where Airbnb is silent.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:12-12` · high · sha:fa61163448dd</sub>
- The Ruby Style Guide (rubystyle.guide), Bozhidar Batsov's community guide, is the shared base layer both the Airbnb and Shopify guides descend from, and is deferred to when both are silent.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:13-13` · high · sha:fa61163448dd</sub>
- The dexpace overlay layer adds Tiger Style discipline (assertion density, bounded everything, no unbounded recursion, zero debt), a method size cap, mandatory Sorbet `# typed: strict` with runtime `sig` enforcement, frozen-by-default values, and `Data.define` value objects with parse-don't-validate constructors.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:15-15` · high · sha:fa61163448dd</sub>
- Security, performance, and git practices are covered in the root-level code style guide, which is language-agnostic and adapted to Ruby by this guide.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:54-54` · high · sha:fa61163448dd</sub>
- Sorbet is credited as the type system underlying the guide, with runtime-checked signatures serving as the first test suite.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:93-93` · high · sha:fa61163448dd</sub>
- RuboCop is credited as the single lint and format baseline for the guide.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:94-94` · high · sha:fa61163448dd</sub>
- TigerBeetle's Tiger Style is credited as the source of assertion density, the method size cap, limits-on-everything discipline, the ban on unbounded recursion, and the zero-technical-debt principle.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:95-95` · high · sha:fa61163448dd</sub>

## Conflicts

## Superseded
