# documentation

## Rules
- A comment that cannot be maintained must be deleted, because a stale comment functions as an active lie.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:3-3` · high · sha:947e62fc7d68</sub>
- YARD-document every public class and every public method, exempting only methods that are not externally visible or whose name already carries the full meaning (e.g., `valid?`, `to_s`, a two-line predicate).
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:39-43` · high · sha:947e62fc7d68</sub>
- Give every public class a class-level YARD comment stating what it models, when to reach for it, and what invariants it guarantees.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:44-44` · high · sha:947e62fc7d68</sub>
- Never restate a `sig`'s type information in YARD prose, such as writing `@param order_id [Integer] the order id` when the sig already declares `order_id: Integer`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:48-53` · high · sha:947e62fc7d68</sub>
- Write comments to explain why (reasoning, constraints, decisions) rather than restating what the code already shows mechanically, since the "what" is verifiable by reading the code but the "why" is not.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:57-62` · high · sha:947e62fc7d68</sub>
- Add a top-of-file comment when a file contains zero classes or more than one class, following Airbnb's guide exactly; a single-class file whose class header already says everything is exempt.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:72-77` · high · sha:947e62fc7d68</sub>
- Give every class a header comment stating what the class represents, its invariants, and the pattern a caller uses.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:76-76` · high · sha:947e62fc7d68</sub>
- Put an `@example` on every non-obvious public API, since a signature shows the shape of a call but not the shape of usage.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:93-98` · high · sha:947e62fc7d68</sub>
- Obvious one-liners such as a pure `Money.zero` or a predicate `order.paid?` do not need an `@example`, because the signature already serves as the example.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:98-98` · high · sha:947e62fc7d68</sub>
- Format every TODO comment as `# TODO(Full Name): explanation`, using the person's full name rather than an anonymous marker.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:112-117` · high · sha:947e62fc7d68</sub>
- Use a full name in a TODO comment so it is greppable by person (e.g., `grep -r "TODO(Lena" .`), since a first name alone or a username alias breaks across team members.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:116-116` · high · sha:947e62fc7d68</sub>
- A TODO's explanation must state both why the debt exists and what removes it; a TODO without an explanation is insufficient to act on or evaluate later.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:117-117` · high · sha:947e62fc7d68</sub>
- Never leave commented-out code in the codebase; delete it, since version control (e.g., `git log -S 'removed_method'`) recovers it without misleading readers.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:126-131` · high · sha:947e62fc7d68</sub>
- Use `#` line comments only; never use `=begin`/`=end` block comments.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:135-140` · high · sha:947e62fc7d68</sub>
- Update or delete a comment in the same commit as the code change it describes; a diff that changes behaviour and leaves surrounding YARD or inline comments stale does not merge.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:144-151` · high · sha:947e62fc7d68</sub>
- Write YARD blocks and standalone inline comments as complete sentences with proper capitalisation and ending punctuation, rather than headline-style fragments.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:153-158` · high · sha:947e62fc7d68</sub>

## Constraints
- `=begin`/`=end` block comments must start in column 0 and cannot be indented, so inside a method or class body they can look like a syntax error.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:138-138` · high · sha:947e62fc7d68</sub>

## Conclusions
- YARD is treated as the documentation layer for public Ruby API while a Sorbet `sig` is treated as the type layer, kept deliberately separate so the signature states types and the comment states the contract, the why, and the edge cases.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:3-3` · high · sha:947e62fc7d68</sub>

## Reference
- Every public method and class exported from the module surface must carry a YARD block, verified during code review of new API additions.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:46-46` · high · sha:947e62fc7d68</sub>
- `@param` and `@return` lines that only echo the type are rejected in review; lines that add a constraint, unit, or sentinel meaning are kept.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:55-55` · high · sha:947e62fc7d68</sub>
- Mechanics-narrating comments are deleted on sight in review; only comments a reviewer could not have inferred from the diff are kept.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:70-70` · high · sha:947e62fc7d68</sub>
- `rubocop-airbnb` enforces the top-of-file comment rule, and review confirms the comment addresses what the file is and how to use it, not just what it contains.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:91-91` · high · sha:947e62fc7d68</sub>
- Non-obvious public methods must carry a realistic `@example` that reflects the current API, verified in review.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:110-110` · high · sha:947e62fc7d68</sub>
- A RuboCop custom cop or grep check in CI rejects any `# TODO` not matching the pattern `# TODO\([^)]+\): .+`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:124-124` · high · sha:947e62fc7d68</sub>
- RuboCop's `Style/CommentedKeyword` cop and review reject commented-out code regardless of apparent intent.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:133-133` · high · sha:947e62fc7d68</sub>
- RuboCop's `Style/BlockComments` cop causes CI to reject any `=begin` outside an intentional literal-string test fixture.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:142-142` · high · sha:947e62fc7d68</sub>
- A short trailing note on the same line as code (e.g., `total = subtotal + tax # cents`) is exempt from the full-sentence and terminal-punctuation requirement when a full sentence would overflow the 100-column limit.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/14-documentation.md:158-158` · high · sha:947e62fc7d68</sub>

## Conflicts

## Superseded
