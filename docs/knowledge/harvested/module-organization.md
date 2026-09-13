# module-organization

## Rules
- Each file must define exactly one class or module, and the filename must be the `snake_case` of the constant path.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:95-98` · high · sha:99aca13c9944</sub>
- Module nesting should stay shallow — three path segments is a smell, and more than three is treated as a design problem.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:100` · high · sha:99aca13c9944</sub>
- Use Zeitwerk as the autoloader and let file paths dictate the constant namespace, calling `Zeitwerk::Loader.for_gem` and `loader.setup` once in the entry point without calling `loader.eager_load` at runtime.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:79-97` · high · sha:a7709c006923</sub>
- Define exactly one class or module per file, named after the constant it defines, with the only sanctioned exception being a class-level private struct or `Data.define` used nowhere but that file.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:99-107` · high · sha:a7709c006923</sub>
- Define nested constants using the full `module`/`class` nesting form rather than compact path syntax, because the compact form causes Ruby to resolve un-prefixed names against only the file's top-level lexical scope, not the intermediate modules.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:109-137` · high · sha:a7709c006923</sub>
- Requiring a file must have no load-time side effects — no network call, database query, global registry mutation, or `puts` at file scope — only definitions; expose an explicit `Commerce.configure { }` block or a `Commerce::Loader.setup!` method for initialization instead.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:139-168` · high · sha:a7709c006923</sub>
- Follow the standard gem layout: a single `lib/<gem>.rb` entry point that consumers require, a `sig/` (or `rbi/`) directory for Sorbet signatures, a `test/` directory mirroring `lib/`, and one gemspec at the root.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:170-178` · high · sha:a7709c006923</sub>
- Use `require_relative` for in-project files outside the autoload path and `require` for external gems, grouping requires into stdlib, external gems, and in-project (with a blank line between groups) and sorting alphabetically within each group.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:180-203` · high · sha:a7709c006923</sub>
- Never `require_relative` into another gem's internals; if a constant from an external gem is needed, `require` only that gem's public entry point.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:186-186` · high · sha:a7709c006923</sub>
- Avoid top-level constant pollution by placing everything under the gem's namespace module; the only sanctioned top-level definition is the gem's namespace module itself in the entry point.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:205-213` · high · sha:a7709c006923</sub>
- Never reopen `Object` or `Kernel` to add helper methods; use a module of functions inside the namespace and mix it in where needed instead.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:210-210` · high · sha:a7709c006923</sub>
- Keep the dependency graph acyclic; when two modules require each other, extract the shared abstraction into its own module to break the cycle rather than lazy-requiring inside a method body to hide it.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:215-233` · high · sha:a7709c006923</sub>
- Re-export the public contract from the gem's top-level namespace (for example `Commerce::Order` rather than `Commerce::Checkout::Order`) so directory reorganizations require updating one alias rather than every caller.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:235-256` · high · sha:a7709c006923</sub>
- Hide internals that are not part of the public promise under a `Commerce::Internal` namespace, optionally guarded at runtime with `private_constant :Internal`; callers who reach into `Internal` own every breakage.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:240-256` · high · sha:a7709c006923</sub>
- Group files by feature domain (such as `commerce/checkout/`, `commerce/inventory/`) rather than by technical layer (such as `models/`, `services/`, `repositories/`), so a change to one feature touches one directory.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:260-281` · high · sha:a7709c006923</sub>
- Keep a `shared/` directory thin, reserved for cross-domain primitives with no single owner (such as a `Money` type or a base error class), since a fat `shared/` becomes layer-folders under a different name.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:266-266` · high · sha:a7709c006923</sub>

## Constraints
- Zeitwerk depends on the one-constant-per-file mapping for autoloading; a file that defines two top-level constants loads the first and silently misses the second.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/02-naming-conventions.md:99` · high · sha:99aca13c9944</sub>

## Conclusions
- Multiple gemspecs in one repository signal that the gem should be split.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:176-176` · high · sha:a7709c006923</sub>

## Reference
- With Zeitwerk, a filename that does not match its defined constant raises a `NameError` at first use rather than silently shadowing it.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:83-97` · high · sha:a7709c006923</sub>
- Chapter 12 (Module Organization) covers Zeitwerk autoloading, one class/module per file, nested-module namespacing, banning load-time side effects, gem layout, and a `madge`-style circular-dependency ban.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:45-45` · high · sha:fa61163448dd</sub>

## Conflicts
- **styleguide vs design: autoloading** — the styleguide requires Zeitwerk as the autoloader with Zeitwerk::Loader.for_gem in the entry point; the design issues explicit requires from lib/dexpace.rb and forbids an autoloader in core because every usable autoloader is itself a gem and SEAM-1 bars core from depending on one
  <sub>styleguide `/home/mohammad/Projects/dexpace/styleguide/ruby/12-module-organization.md:79-97` · design `docs/sdk-design-ruby/02-gem-and-workspace-layout.md:59-62` · unresolved 2026-09-05</sub>

## Superseded
