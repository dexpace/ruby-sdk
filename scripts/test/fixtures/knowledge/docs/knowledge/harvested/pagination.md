# pagination

## Rules
- A Page MUST be a closeable resource owning exactly one underlying response, and whoever pulls a page owns closing it (PAGE-1).
  <sub>spec · `docs/product-spec/12-pagination.md:20` · high · sha:5555eeee6666</sub>
- The item-level view MUST eager-close each page before yielding any of that page's items (PAGE-2).
  <sub>spec · `docs/product-spec/12-pagination.md:38` · high · sha:5555eeee6666</sub>

## Reference
- The design chapter's item-view snippet yields inside a begin block with close in the ensure, which orders the close after the first item (PAGE-2).
  <sub>design · `docs/sdk-design-ruby/07-pagination.md:12-18` · medium · sha:7777aaaa8888</sub>

## Conflicts
- **design vs styleguide: frozen page objects** — the design describes a Page as a mutable object closed in place, while the styleguide requires value objects to be frozen at construction. Which wins for a closeable page needs settling (PAGE-3).
  <sub>design `docs/sdk-design-ruby/07-pagination.md:22` · styleguide `/opt/dexpace-fixture/styleguide/ruby/06-classes-and-data-modeling.md:168-183` · unresolved 2026-01-01</sub>
