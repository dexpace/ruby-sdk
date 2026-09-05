# formatting-and-tooling

## Rules
- `# frozen_string_literal: true` must appear as the very first line of every `.rb` file, even though Ruby 4.0 enables freezing by default.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:89` · high · sha:9dd0b475bc7d</sub>
- The `# typed:` Sorbet sigil must appear immediately on the second line of the file, directly after the frozen-string-literal comment.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:90` · high · sha:9dd0b475bc7d</sub>
- A blank line must separate the magic-comment block from the rest of the file (requires, module/class headers, or YARD doc).
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:91` · high · sha:9dd0b475bc7d</sub>
- No magic comments other than the frozen-string-literal comment and the typed sigil belong at the top of a file; `# encoding: utf-8` and `# warn_indent: true` must not be committed.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:92` · high · sha:9dd0b475bc7d</sub>
- Files must use 2-space soft-tab indentation; hard tabs are banned.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:112` · high · sha:9dd0b475bc7d</sub>
- Files must use Unix LF line endings, enforced at the repo boundary via `.gitattributes` setting `*.rb text eol=lf`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:113` · high · sha:9dd0b475bc7d</sub>
- UTF-8 is the only permitted source encoding and must not be declared via an `# encoding: utf-8` comment.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:114` · high · sha:9dd0b475bc7d</sub>
- Every file must end with a final newline, and trailing whitespace on any line must be removed.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:115` · high · sha:9dd0b475bc7d</sub>
- Line length must not exceed 100 columns, including comments and YARD strings.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:119-124` · high · sha:9dd0b475bc7d</sub>
- Wrapping a long URL onto its own line is the one accepted exception to the line-length cap; URLs must not be wrapped mid-token.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:124` · high · sha:9dd0b475bc7d</sub>
- Review rejects `# rubocop:disable Layout/LineLength` except for lone URLs.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:137` · high · sha:9dd0b475bc7d</sub>
- Strings must always be double-quoted.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:139-142` · high · sha:9dd0b475bc7d</sub>
- `%q()`, `%Q()`, and `%{}` are banned for ordinary strings.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:145` · high · sha:9dd0b475bc7d</sub>
- Each expression must occupy its own line; semicolons are banned except for a single-line class body such as an empty class shell.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:149-154` · high · sha:9dd0b475bc7d</sub>
- Single-line compound forms such as `def foo; bar; end` or `if cond; x; end` are banned; the full multi-line form must be used instead.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:154` · high · sha:9dd0b475bc7d</sub>
- Spaces must surround binary operators (e.g. `+`, `-`, `*`, `/`, `=`, `==`, `<`, `>`, `&&`, `||`, `=>`).
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:175` · high · sha:9dd0b475bc7d</sub>
- A space must follow every comma, colon (in argument lists and hash literals), and semicolon, and no space precedes any of them.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:176` · high · sha:9dd0b475bc7d</sub>
- A space must appear inside `{ }` in hash literals and blocks, but no space may appear immediately inside `[]` or `()`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:177` · high · sha:9dd0b475bc7d</sub>
- No space follows unary `!`, `~`, or `+`; no space appears in range literals (`1..10`); and no space appears in lambda literals (`->(x, y) { x + y }`).
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:178` · high · sha:9dd0b475bc7d</sub>
- Multiline arrays, hashes, and argument lists must place one element per line.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:198-201` · high · sha:9dd0b475bc7d</sub>
- A trailing comma after the last element is mandatory in multiline array, hash, and argument list literals.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:202` · high · sha:9dd0b475bc7d</sub>
- The closing delimiter (`]`, `}`, `)`, or `end`) must be placed on its own line, dedented to the level of the opening line.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:203` · high · sha:9dd0b475bc7d</sub>
- Method chains longer than one receiver-plus-call must break at each dot, with the dot leading on the continuation line indented one level, rather than trailing on the prior line.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:204` · high · sha:9dd0b475bc7d</sub>

## Constraints

## Conclusions
- The 100-column line-length cap was chosen deliberately as the tighter Airbnb bound over Shopify's 120-column bound because narrower lines survive side-by-side diffs, two-pane editors, and laptop code review without horizontal scrolling.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:122` · high · sha:9dd0b475bc7d</sub>
- Double-quoted strings were adopted as the Shopify default and recorded as a deliberate deviation from Airbnb's silence on the matter, captured in the deviations ledger in README.md.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/01-formatting-and-tooling.md:143` · high · sha:9dd0b475bc7d</sub>

## Reference
- Chapter 01 (Formatting & Tooling) covers the `rubocop-airbnb` baseline, Ruby ≥ 4.0 pinned, mandatory `frozen_string_literal`, 2-space indentation, 100-column limit, double quotes, trailing commas, the `srb tc` typecheck gate, and metric caps.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:34-34` · high · sha:fa61163448dd</sub>

## Conflicts

## Superseded
