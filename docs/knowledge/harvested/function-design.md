# function-design

## Rules
- Methods should aim for 5-15 lines; 25 lines is the hard ceiling, not the target.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:235` · high · sha:9dd0b475bc7d</sub>
- `Metrics/AbcSize` and `Metrics/CyclomaticComplexity` should be left at their default thresholds unless a specific exception is recorded.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:238` · high · sha:9dd0b475bc7d</sub>
- Review rejects an inline `rubocop:disable Metrics/` comment that is not accompanied by a ledger entry.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:258` · high · sha:9dd0b475bc7d</sub>
- `||=` must never be used to lazily initialize a boolean value because it treats an explicit `false` the same as "never set" and will re-enable a deliberately disabled flag.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:170-175` · high · sha:c2def8078f0c</sub>
- Boolean lazy initialization must test for `nil` explicitly, e.g. `@enabled = true if @enabled.nil?`, to preserve an explicitly set `false` value.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:175-184` · high · sha:c2def8078f0c</sub>
- Memoization with `@x ||= compute` must only be used when `compute` is pure and idempotent, since memoizing an effectful computation caches only the first result and silently skips future calls.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:192-195` · high · sha:c2def8078f0c</sub>
- A `return` must never appear inside a `begin` block used for memoization, because it exits the method before the memoized instance variable is assigned, defeating the cache on every call.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:196-196` · high · sha:c2def8078f0c</sub>
- The computation being memoized must be extracted to a private method so the memoizing line is a one-liner (`@total ||= compute_total`) and the private method may use early returns freely.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:197-225` · high · sha:c2def8078f0c</sub>
- An assignment used as a truth test in a condition must be wrapped in parentheses, e.g. `if (m = string.match(pattern))`, to signal deliberate assignment rather than a typo for `==`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:229-234` · high · sha:c2def8078f0c</sub>
- Outside the parenthesized-assignment idiom, an assignment used in a condition should be split into an assignment on one line and a test on the next.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:234-234` · high · sha:c2def8078f0c</sub>
- Shorthand self-assignment operators (`+=`, `<<`, `||=`, `&&=`) must be used instead of the expanded form (e.g. `count = count + 1`) to avoid noise and reduce transposition-bug risk during renames.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:256-261` · high · sha:c2def8078f0c</sub>
- A method's line count must not exceed 25 lines (hard cap, RuboCop-enforced, blank lines counted, comments excluded), with 5-15 lines as the target.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:46-50` · high · sha:3c2b6c47162f</sub>
- If the honest one-sentence summary of a method needs an "and," the method must be split into two methods along that "and."
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:51-51` · high · sha:3c2b6c47162f</sub>
- The 25-line cap applies to every callable, including public methods, private helpers, module methods, and block bodies passed to iterators such as `each`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:52-52` · high · sha:3c2b6c47162f</sub>
- Each method must operate at one level of abstraction, either orchestrating named steps or performing primitive work, but not mixing the two.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:58-63` · high · sha:3c2b6c47162f</sub>
- When an orchestrating method sprouts arithmetic, a regex, or a conditional that belongs in a helper, that fragment must be extracted into a named method.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:63-63` · high · sha:3c2b6c47162f</sub>
- If `Metrics/BlockNesting` fires due to mixed abstraction levels in a method body, the first question must be whether the nested logic deserves its own method.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:64-64` · high · sha:3c2b6c47162f</sub>
- Guard clauses must handle exceptional cases at the top of a method with an early return or raise, leaving the happy path flush left as a straight column of code.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:70-75` · high · sha:3c2b6c47162f</sub>
- Every `if` that can be inverted into a guard clause should be, since an `else` branch is usually a guard the author failed to take.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:74-74` · high · sha:3c2b6c47162f</sub>
- Method calls must use keyword arguments over positional arguments so a call site reads without opening the signature.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:94-98` · high · sha:3c2b6c47162f</sub>
- A positional parameter must never be given a default value, because the default is invisible at the call site and becomes a silent time bomb when the signature changes.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:99-99` · high · sha:3c2b6c47162f</sub>
- An options hash parameter (`def foo(options = {})`) must not be used because it loses type coverage, destroys IDE navigation, and silently allows unknown keys; keyword arguments must be used instead.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:100-100` · high · sha:3c2b6c47162f</sub>
- A method must take no more than 4 parameters; reaching a fifth parameter signals the method should extract a value object or split responsibilities.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:106-109` · high · sha:3c2b6c47162f</sub>
- A behaviour-forking boolean parameter — one whose truth value selects between two fundamentally different algorithms — must be split into two separate, honestly named methods that share a private helper for common work.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:110-112` · high · sha:3c2b6c47162f</sub>
- `next` (and `return`) must be used to invert nested conditional bodies inside loops and enumerable blocks (`map`, `select`, `reduce`) so the meaningful work stays flush left.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:143-148` · high · sha:3c2b6c47162f</sub>
- Single-line method definitions are prohibited; every `def` body must be on its own lines with `end` on its own line.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:173-176` · high · sha:3c2b6c47162f</sub>
- Ruby 3 endless method syntax (`def total = expr`) is acceptable only for a trivial pure expression with no guard clause, no local variable, and no side effect; anything with a method call carrying arguments, a conditional, or a local binding must use the traditional `def`/`end` form.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:177-178` · high · sha:3c2b6c47162f</sub>
- Explicit `return` must be omitted at the end of a method since the last expression is already its return value; redundant `return` signals an exceptional case where none exists.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:199-202` · high · sha:3c2b6c47162f</sub>
- Explicit `return` must be reserved for early exits (guards) at the top of a method, giving it a single recognizable meaning of "stop here, the rest does not apply."
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:203-204` · high · sha:3c2b6c47162f</sub>
- A `def` must use parentheses when it takes parameters and omit them when it takes none, regardless of whether the parameters have default values.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:221-226` · high · sha:3c2b6c47162f</sub>
- Methods must be pure by default — same input, same output, no observable effect — with side effects confined to a thin shell at the edges that delegates logic to a pure core.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:244-248` · high · sha:3c2b6c47162f</sub>
- A side-effecting method must carry an effect verb in its name (e.g. `write_ledger`, `emit_event`, `persist_order`, `notify_customer`) rather than a generic name like `data` or `process`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:249-249` · high · sha:3c2b6c47162f</sub>
- Time, randomness, and external state must be injected as parameters (e.g. `now:`) rather than accessed directly (e.g. `Time.now`) so the core logic remains pure and testable.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:250-250` · high · sha:3c2b6c47162f</sub>
- `public_send` must be used instead of `send` because `send` bypasses Ruby's visibility rules and can call private or protected methods as if they were public.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:272-276` · high · sha:3c2b6c47162f</sub>
- If code needs `send` to reach a private method, the underlying design should be fixed by making the method public, extracting it, or redesigning the boundary, rather than reaching for `send`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:277-277` · high · sha:3c2b6c47162f</sub>
- The only legitimate use of `send` in application code is when `public_send` is genuinely insufficient (e.g. test helpers exercising private internals, or framework-level introspection), and such sites must be annotated with a comment explaining why.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:278-278` · high · sha:3c2b6c47162f</sub>

## Constraints
- RuboCop `Lint/AssignmentInCondition` is configured with `AllowSafeAssignment: true`, permitting parenthesized assignment in conditions while flagging bare assignment, and this is the default in `rubocop-airbnb`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:254-254` · high · sha:c2def8078f0c</sub>
- RuboCop `Style/SelfAssignment` is configured as an error.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/04-variables-and-declarations.md:279-279` · high · sha:c2def8078f0c</sub>
- RuboCop `Metrics/MethodLength` is configured with `Max: 25`, with `CountAsOne` applied for heredocs and blank lines counted toward the total.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:56-56` · high · sha:3c2b6c47162f</sub>
- RuboCop `Metrics/BlockNesting` is configured with `Max: 3`, with a target of 2 or fewer.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:92-92` · high · sha:3c2b6c47162f</sub>
- RuboCop `Style/OptionHash` bans options hashes and `Style/KeywordParameters` enforces keyword-argument usage.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:104-104` · high · sha:3c2b6c47162f</sub>
- RuboCop `Metrics/ParameterLists` is configured with `Max: 4`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:141-141` · high · sha:3c2b6c47162f</sub>
- RuboCop `Style/Next` enforces `next` over wrapped conditionals in block bodies.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:171-171` · high · sha:3c2b6c47162f</sub>
- RuboCop `Style/SingleLineMethods` enforces the ban on single-line method definitions.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:197-197` · high · sha:3c2b6c47162f</sub>
- RuboCop `Style/RedundantReturn` enforces omission of unnecessary `return` statements.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:219-219` · high · sha:3c2b6c47162f</sub>
- RuboCop `Style/DefWithParentheses` and `Style/MethodDefParentheses` enforce the parentheses convention on method definitions.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:242-242` · high · sha:3c2b6c47162f</sub>
- A RuboCop custom cop or `Lint/SendWithMixinArgument` flags bare `send` usage in non-test application code.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:295-295` · high · sha:3c2b6c47162f</sub>

## Conclusions
- The 25-line method cap was set deliberately tighter than comparable caps in other languages, described as the "Ruby-scaled sibling" of Go's 70-line and Kotlin's 60-line limits.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:50-50` · high · sha:3c2b6c47162f</sub>

## Reference
- `Metrics/MethodLength` is capped at 25 lines with `CountAsOne` exemptions for `array`, `hash`, and `heredoc` literals.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:231-235` · high · sha:9dd0b475bc7d</sub>
- `Metrics/ParameterLists` is capped at a maximum of 4 parameters.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:236` · high · sha:9dd0b475bc7d</sub>
- `Metrics/BlockNesting` is capped at a maximum depth of 3.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:237` · high · sha:9dd0b475bc7d</sub>
- A `sig { params(...).returns(...) }` block always accompanies a `def` with parentheses, while a `sig { returns(...) }` block always accompanies a `def` without parentheses.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/05-methods.md:225-225` · high · sha:3c2b6c47162f</sub>
- Chapter 05 (Methods) covers a 25-line cap, keyword arguments over positional arguments or options hashes, guard clauses, one level of abstraction, `next` over nested blocks, `public_send`, purity by default, and 2+ assertions.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:38-38` · high · sha:fa61163448dd</sub>

## Conflicts

## Superseded
