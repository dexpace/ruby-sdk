# variables-and-declarations

## Rules
- Local variables must be declared on the line where they first receive a value rather than at the top of a method, to keep scope minimal and live range short.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:61-65` · high · sha:c2def8078f0c</sub>
- An intermediate local variable that is too generic to have an honest single-word label (such as `tmp`, `result`, or `data`) must be extracted into a method that earns a real name.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:66-67` · high · sha:c2def8078f0c</sub>
- `$global` variables are prohibited because they are process-wide mutable state with no owner that any file, test, or thread can write or race on.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:92-97` · high · sha:c2def8078f0c</sub>
- Perl special variables such as `$1`, `$2`, `$~`, `$;`, `$,`, and `$\` are prohibited because they are global state silently overwritten by any subsequent regex or method call in the same thread.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:96-96` · high · sha:c2def8078f0c</sub>
- State must be passed explicitly via return values, keyword arguments, or instance variables on a well-scoped object rather than through global or Perl special variables.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:97-97` · high · sha:c2def8078f0c</sub>
- `@@class` variables must not be used because they are shared across the entire inheritance hierarchy, allowing a subclass write to be seen by the superclass's reader with no scoping protection.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:115-118` · high · sha:c2def8078f0c</sub>
- Shared class-level state must be implemented as a class instance variable (declared inside `class << self`) or, if fixed at load time, as a frozen constant, instead of a `@@class` variable.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:119-120` · high · sha:c2def8078f0c</sub>
- Redundant `self.` must be dropped inside instance methods except where the language requires it.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:322-325` · high · sha:c2def8078f0c</sub>
- Inside a `class << self` block, method definitions must omit the `self.` prefix because every method in the block is already a class method.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:327-327` · high · sha:c2def8078f0c</sub>
- Constants must be declared at the top of the class or module, frozen, and typed with `T.let`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:353-359` · high · sha:c2def8078f0c</sub>
- Magic numbers and magic strings embedded in method bodies must be replaced with named constants declared at the top of the class.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:356-357` · high · sha:c2def8078f0c</sub>

## Constraints
- RuboCop `Style/GlobalVars` and `Style/PerlBackrefs` are both configured as errors.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:113-113` · high · sha:c2def8078f0c</sub>
- RuboCop `Style/ClassVars` is configured as an error.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:143-143` · high · sha:c2def8078f0c</sub>
- RuboCop `Style/RedundantSelf` is configured as an error.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:351-351` · high · sha:c2def8078f0c</sub>
- A constant assigned without `T.let` is inferred by Sorbet as `T.untyped`, making it a type-checking blind spot.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:358-358` · high · sha:c2def8078f0c</sub>
- RuboCop `Style/MagicNumber` (via the `rubocop-magic_numbers` gem) enforces named constants for magic literals, and `Style/MutableConstant` catches constants on mutable values without `.freeze`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:385-385` · high · sha:c2def8078f0c</sub>

## Conclusions

## Reference
- Ruby requires `self.` in exactly three places — assignment to an instance accessor (to disambiguate from a local variable), defining a class method (`def self.parse`), and referencing the class itself (`self.class`).
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:326-326` · high · sha:c2def8078f0c</sub>
- Constants of already-immutable types (integers, symbols, `Data.define` objects) do not need `.freeze`, but string, array, and hash constants do.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:359-359` · high · sha:c2def8078f0c</sub>
- Chapter 04 (Variables & Declarations) covers local scope, banning `$globals` and `@@class` variables, freezing constants, `||=` initialization (not for booleans), memoization caveats, `attr_reader`, and avoiding redundant `self.`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:37-37` · high · sha:fa61163448dd</sub>

## Conflicts

## Superseded
