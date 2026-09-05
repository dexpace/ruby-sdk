# module-organization — notes

Hand-written. `../harvested/module-organization.md` is what the documents say; this file is what
the implementation found, and it wins. Each entry names the harvested entry it answers by that
entry's stable key.

## Conflicts
- **Autoloading: the design wins — `lib/dexpace.rb` issues explicit `require`s and no gem in this repository loads Zeitwerk.** Resolves `module-organization/bf6411ad`. This is a library-versus-application distinction rather than a preference: Zeitwerk is itself a gem, so `require "zeitwerk"` in `dexpace-core` is an `add_dependency` line, and `dexpace-core.gemspec` is asserted to have zero runtime dependencies (`SEAM-1`, `NFR-1`). An application can afford the autoloader; a zero-dependency core cannot. What the SDK does instead: `lib/dexpace.rb` requires the whole tree explicitly, which also turns the require-graph audit into a text scan rather than a runtime trace; adapter gems follow the same rule for consistency even though `NFR-2`'s one-third-party-library budget would technically permit them an autoloader. Everything else the styleguide chapter asks for is kept unchanged — the file-path-to-constant mapping, one constant per file, nested `module`/`class` form, no load-time side effects, no top-level constants outside `Dexpace::` — so the convention Zeitwerk would have enforced is enforced by review and by the runtime surface snapshot instead. The styleguide-amendment alternative (carving out gems whose dependency budget forbids an autoloader) was considered and not taken; this is recorded as an SDK deviation instead.
  <sub>review · `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` · high · sha:manual-roadmap-conflict-2</sub>
