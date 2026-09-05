# naming-conventions

## Rules
- Methods, variables, symbols, file names, and directories must use `snake_case`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:58-63` · high · sha:99aca13c9944</sub>
- File and directory names must mirror the constant they contain in `snake_case` form, e.g. `Commerce::Order` lives in `commerce/order.rb`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:62` · high · sha:99aca13c9944</sub>
- Classes and modules must use `CamelCase` (PascalCase).
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:67-70` · high · sha:99aca13c9944</sub>
- Established acronyms in class/module names stay uppercase when the broader ecosystem treats them that way, e.g. `HTTPClient`, `XMLParser`, `SKUCatalog`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:71` · high · sha:99aca13c9944</sub>
- Constants must use `SCREAMING_SNAKE_CASE`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:76-79` · high · sha:99aca13c9944</sub>
- A constant encoding a quantity must carry its unit or scale in the name, e.g. `CONNECT_TIMEOUT_MS`, `MAX_RETRIES`, `TAX_RATE_PCT`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:80` · high · sha:99aca13c9944</sub>
- Magic numbers are banned; every bare numeric literal that has a conceptual identity must be extracted into a named constant.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:81` · high · sha:99aca13c9944</sub>
- Predicate methods must end in `?` and must return a real boolean (`true` or `false`), never `nil`, an empty array, or a string.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:119-123` · high · sha:99aca13c9944</sub>
- A method that does not return a boolean must not end in `?`; a method like `customer.address?` returning an `Address` or `nil` must be renamed, e.g. `address` or `find_address`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:124` · high · sha:99aca13c9944</sub>
- A bang method (`!`) must be used only when a non-bang counterpart of the same method exists.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:136-139` · high · sha:99aca13c9944</sub>
- A method must never be given a bang purely for emphasis without a non-bang twin.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:141` · high · sha:99aca13c9944</sub>
- Method names must never use `is_`, `has_`, or `get_` prefixes.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:160-164` · high · sha:99aca13c9944</sub>
- Use an effect verb (`fetch_`, `load_`, `find_`) instead of `get_` when the operation performs I/O or may fail.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:165` · high · sha:99aca13c9944</sub>
- Side-effecting methods must be named with an effect verb, while pure transforms must be named as nouns or adjectives, never a verb implying action.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:169-174` · high · sha:99aca13c9944</sub>
- The parameter of a binary operator method (`==`, `<=>`, `+`, `-`, etc.) must be named `other`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:193-196` · high · sha:99aca13c9944</sub>
- `<<` and `[]` are exceptions to the `other` parameter naming convention and should use a domain-appropriate name such as `item`, `key`, or `index`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:197` · high · sha:99aca13c9944</sub>
- `reduce` block arguments must be named mnemonically to tell the story of the accumulation, rather than generically as `a, b`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:198` · high · sha:99aca13c9944</sub>
- Throwaway and unused variables must be named `_` or with an `_`-prefix.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:215-218` · high · sha:99aca13c9944</sub>
- When multiple distinct discards appear in the same scope, each must be prefixed with `_` followed by a descriptive suffix, e.g. `_index`, `_meta`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:219` · high · sha:99aca13c9944</sub>
- A real variable must never be assigned and left unused; it must either be used or named as a deliberate `_`-prefixed discard.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:220` · high · sha:99aca13c9944</sub>
- Terminology with discriminatory origins must be avoided; use `allowlist`/`denylist` instead of whitelist/blacklist, and `primary`/`replica` instead of master/slave.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:233-236` · high · sha:99aca13c9944</sub>
- True arithmetic constants such as `0`, `1`, `-1`, or `2` in an index expression do not need named constants when their meaning is structurally obvious.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:238` · high · sha:99aca13c9944</sub>

## Constraints

## Conclusions

## Reference
- "Dangerous," in the context of bang-method naming, means the method mutates the receiver in-place where the non-bang variant does not, or raises on failure where the non-bang variant returns `false`/`nil`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:140` · high · sha:99aca13c9944</sub>
- The endorsed effect verbs for side-effecting method names are `write_`, `charge_`, `fetch_`, `load_`, `send_`, `emit_`, `publish_`, `persist_`, and `record_`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:173` · high · sha:99aca13c9944</sub>
- Chapter 02 (Naming Conventions) covers `snake_case`/`CamelCase`/`SCREAMING_SNAKE_CASE` usage, predicate `?` and paired bang `!` methods, banning `is_`/`get_` prefixes, one class per file, effect-verb naming, and no magic numbers.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:35-35` · high · sha:fa61163448dd</sub>

## Conflicts

## Superseded
