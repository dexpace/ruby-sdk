# ruby-idioms

## Rules
- Build pipelines with map/select/reject/reduce/find, and reach for each only for pure effects or break/next early exit.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:34-40` · high · sha:56396824907b</sub>
- Name each pipeline stage with a local variable when a method chain exceeds roughly three steps.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:39` · high · sha:56396824907b</sub>
- RuboCop's Style/MapIntoArray and Style/EachWithObject cops surface common each-replaces-map patterns.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:55` · high · sha:56396824907b</sub>
- Use the `&:symbol` shorthand exactly when the block takes one argument and calls one no-argument method on it, with no branching and no further computation.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:57-62` · high · sha:56396824907b</sub>
- RuboCop's Style/SymbolProc cop is enabled to enforce the &:symbol shorthand where applicable.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:74` · high · sha:56396824907b</sub>
- Use tap for side-effecting inspection inside a chain (logging, metrics, breakpoints) without breaking the chain, since tap returns the receiver unchanged.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:76-79` · high · sha:56396824907b</sub>
- Use then (aliased yield_self) to pipe a receiver through an expression that does not fit the receiver's own API, keeping the pipeline linear.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:80` · high · sha:56396824907b</sub>
- Never use tap to mutate the receiver and carry the mutation forward invisibly; mutation belongs in an explicit assignment.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:81` · high · sha:56396824907b</sub>
- tap mutation is rejected at code review as a hidden side effect.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:96` · high · sha:56396824907b</sub>
- Use case/in for structural decomposition of hashes, arrays, and Data objects instead of a tree of dig/[]/fetch calls and if guards.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:98-101` · high · sha:56396824907b</sub>
- Use one-line rightward-assignment `=>` patterns to bind a value from a deconstruction without branching, typically at the top of a method to assert input shape.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:103` · high · sha:56396824907b</sub>
- Never use `for`; use block iterators instead.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:126` · high · sha:56396824907b</sub>
- RuboCop's Style/For cop is enabled with EnforcedStyle: each.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:147` · high · sha:56396824907b</sub>
- Use `{ ... }` for single-line blocks and `do ... end` for multi-line blocks; never chain multiple `do...end` blocks and never write a multi-line `{ }` block.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:149-153` · high · sha:56396824907b</sub>
- RuboCop's Style/BlockDelimiters cop is configured with EnforcedStyle: line_count_based.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:176` · high · sha:56396824907b</sub>
- Never monkey-patch core classes globally; use a scoped refinement (refine + using) with a why-comment if patching is unavoidable.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:178-182` · high · sha:56396824907b</sub>
- Before reaching for a refinement, consider whether an adapter method, a plain module function, or a decorator class can express the same behaviour without patching.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:183` · high · sha:56396824907b</sub>
- RuboCop's Style/MonkeyPatchingProtection cop is enabled, and global reopens of core classes are rejected at review.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:203` · high · sha:56396824907b</sub>
- Avoid needless metaprogramming (define_method, method_missing/respond_to_missing?, dynamic send tricks) and write ruby -w clean code, since explicit beats clever.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:205-208` · high · sha:56396824907b</sub>
- Use public_send as the sanctioned form of dynamic dispatch because it respects private/protected visibility and raises NoMethodError on an unknown name rather than silently dispatching to an unintended private method.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:209` · high · sha:56396824907b</sub>
- Code should produce zero ruby -w warnings, since every suppressed warning is a potential nil or dead branch hiding in production.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:210` · high · sha:56396824907b</sub>
- When metaprogramming genuinely earns its keep, contain it in one module, document the contract with a sig, and gate the file with a why-comment.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:211` · high · sha:56396824907b</sub>
- define_method and method_missing require a why-comment and architecture approval at code review.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:232` · high · sha:56396824907b</sub>
- Use squiggly heredocs `<<~` for multi-line strings so common leading indentation is stripped from the string content.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:234-238` · high · sha:56396824907b</sub>
- The closing heredoc delimiter must go on its own line at the base indentation level.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:239` · high · sha:56396824907b</sub>
- RuboCop's Style/HeredocDelimiterNaming and Layout/HeredocIndentation cops are enabled; a heredoc without squiggly indentation is a cop violation.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:256` · high · sha:56396824907b</sub>
- Use shorthand symbol hash keys and prefer symbols over strings as hash keys.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:258-262` · high · sha:56396824907b</sub>
- Use Hash#fetch instead of Hash#[] on external or parsed input so a missing key raises KeyError immediately at the source instead of silently returning nil.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:263` · high · sha:56396824907b</sub>
- Supply a default value or block to Hash#fetch for keys that legitimately may be absent, e.g. hash.fetch(:discount, 0).
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:263` · high · sha:56396824907b</sub>
- RuboCop's Style/HashSyntax cop is configured with EnforcedStyle: ruby19, and Hash#fetch over [] on external/parsed input is enforced at review.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:280` · high · sha:56396824907b</sub>
- Use string interpolation over string concatenation.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:282-285` · high · sha:56396824907b</sub>
- Wrap @ivars and $globals in braces inside string interpolation (e.g. "#{@total}") instead of using the unbraced form (e.g. "#@total"), because the unbraced form is ambiguous about where the interpolation ends.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:286` · high · sha:56396824907b</sub>
- Never call .to_s inside string interpolation, because interpolation already calls to_s automatically, making an inner call redundant noise.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:287` · high · sha:56396824907b</sub>
- RuboCop's Style/StringConcatenation and Style/RedundantInterpolation cops are both enabled, and Style/InterpolationCheck enforces braces around ivars and globals.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:304` · high · sha:56396824907b</sub>
- Use Time over DateTime everywhere and keep timestamps in UTC.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:306-309` · high · sha:56396824907b</sub>
- Parse known formats with Time.iso8601 rather than Time.parse, because Time.parse accepts dozens of ambiguous formats and falls back to locale-dependent parsing.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:310` · high · sha:56396824907b</sub>
- Prefer Time.now.utc over Time.now; store and compare timestamps in UTC and convert to a local zone only at presentation boundaries.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:311` · high · sha:56396824907b</sub>
- RuboCop's Style/DateTime cop prefers Time, and review rejects Time.parse for known ISO 8601 inputs.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:327` · high · sha:56396824907b</sub>
- Prefer plain literal arrays (e.g. ["draft", "confirmed"]) over %w/%i literal syntax.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:329-332` · high · sha:56396824907b</sub>
- Use first/last over [0]/[-1] index literals for array element access, because first(n)/last(n) generalize to a slice while indexing does not.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:333` · high · sha:56396824907b</sub>
- Use &&/||/! over and/or/not in all boolean expressions; reserve and/or for flow control only, and even then prefer if/unless.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:334` · high · sha:56396824907b</sub>
- RuboCop's Style/WordArray and Style/SymbolArray cops are configured with EnforcedStyle: brackets, and Style/AndOr is configured with EnforcedStyle: always; first/last over index literals is enforced at review.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:354` · high · sha:56396824907b</sub>

## Constraints
- The `for x in collection` construct leaks the loop variable into the enclosing scope after the loop finishes, unlike block iterators which scope the block parameter to the block.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:129` · high · sha:56396824907b</sub>
- The `for` loop provides no break value, no block-level rescue, and no way to pass the block further, making it strictly less capable than its iterator equivalent.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:131` · high · sha:56396824907b</sub>
- Opening a core class like String, Integer, or Array globally changes behaviour for every gem and caller in the process, giving the patch a process-wide impact radius.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:181` · high · sha:56396824907b</sub>
- and/or/not have lower precedence than assignment in Ruby, which can produce non-obvious parse trees such as `x = true and false` assigning true to x.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:334` · high · sha:56396824907b</sub>

## Conclusions
- Preferring plain literal arrays over %w/%i is a recorded deviation from Airbnb's style guide, documented in the README deviations ledger.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:332` · high · sha:56396824907b</sub>

## Reference
- The pin operator `^` matches a pattern against an existing variable's value to guard against a specific runtime value in structural pattern matching.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:104` · high · sha:56396824907b</sub>
- `{ ... }` has higher precedence than `do ... end`, so in a method chain a do...end block binds to the last receiver in the chain rather than to the intended method, silently re-parsing intent.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:152` · high · sha:56396824907b</sub>
- Refinements scope a patch to only the files that explicitly opt in with `using`, limiting the impact radius to one file.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:182` · high · sha:56396824907b</sub>
- Plain `<<HEREDOC` preserves all leading whitespace, including surrounding-code indentation, which leaks invisible spaces into error messages, SQL, and rendered templates.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:237` · high · sha:56396824907b</sub>
- Symbol hash keys are frozen and interned, producing stable object_id values and zero GC pressure on repeated use, while string keys allocate a new object per literal.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:262` · high · sha:56396824907b</sub>
- DateTime is a legacy class that models civil time in a combined date-and-time object without timezone awareness, while Time in Ruby 4.0 is UTC-aware, supports nanosecond precision, and underlies ActiveSupport::TimeWithZone.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:309` · high · sha:56396824907b</sub>
- Time.iso8601(s) raises ArgumentError immediately on input that does not conform to ISO 8601.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/07-ruby-idioms.md:310` · high · sha:56396824907b</sub>
- Chapter 07 (Ruby Idioms) covers Enumerable pipelines, `&:sym`, `tap`/`then`, pattern matching with `case/in`, banning `for`, `{}` vs `do..end` usage, banning monkey-patching, squiggly heredocs, and preferring `Time` over `DateTime`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:40-40` · high · sha:fa61163448dd</sub>

## Conflicts

## Superseded
