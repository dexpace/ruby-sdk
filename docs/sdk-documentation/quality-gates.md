# Quality gates

Every blocking gate this SDK runs, what each protects, and how to run it locally. As built by
phase 0 (`docs/work/mvp/phase0/`), extended by phase 7b (`gates:serde_boundary`) and by phase 9
(`gates:cause_walk`, `gates:bounded_map`, `gates:seam_names`); the design it implements is
`docs/sdk-design-ruby/09-toolchain-and-quality-gates.md`, and this page describes the build as it
is rather than as it was planned.

`bundle exec rake` runs all twenty-one, in the order below, and stops at the first failure. Each is
a separately invocable task, because a gate you cannot run alone is a gate you debug by running
everything. `bundle exec rake gates:list` prints the names; `bundle exec rake -T` describes them.

| # | Task | Protects | Turned red by |
|---|---|---|---|
| 1 | `rubocop` | `NFR-7`, `NFR-13`: style and lint findings are fatal; the eight custom cops mechanise `CLAUDE.md`'s ban list — phase 2's `Dexpace/QualifiedCoreConstant` is the seventh, refusing a bare `Thread`/`Queue`/`Mutex`/`SizedQueue`/`ConditionVariable`/`JSON`/`IO` anywhere inside `module Dexpace` in every gem's `lib/` (phase 3a widened it from two namespaces and one gem, and taught it that `module Dexpace; module IO` declares the shadow rather than referring to Ruby's), and phase 4a's `Dexpace/NoWeakReferences` is the eighth, refusing `ObjectSpace::WeakMap`, `ObjectSpace::WeakKeyMap`, `WeakRef` and `require "weakref"` in every gem's `lib/`, because `CTX-19` makes the bounded cap and not the collector the leak backstop | any finding at `--fail-level=convention` |
| 2 | `cops:test` | the custom cops themselves — a cop that silently stops matching stays silent otherwise; the four ban cops see a safe-navigation call (`@thread&.kill`, `name&.downcase(:turkic)`) and the interrupt cop a block-pass (`threads.each(&:kill)`, `(&:exit)`) as well as the plain spelling | `.rubocop/test/cops_test.rb`: 77 rejected and 52 accepted sources, the seventh cop's in two nested classes of their own — phase 2's ten and seven, phase 3a's eight and ten — and the eighth's fourteen and fifteen in a third, every row a source string so the two `WeakKeyMap` spellings parse on the 3.2 floor where the constant does not exist |
| 3 | `rbs:validate` | `NFR-3`: every `sig/**/*.rbs` parses and resolves, per gem, with `--no-collection` and the signature sets of the stdlib features the require allowlist admits loaded with `-r` (`set` excepted: rbs 4 ships it under `core/`) | an `.rbs` naming an undeclared type |
| 4 | `steep` | `NFR-3`: `steep check` over six named targets, `core` strict | a type error in any target |
| 5 | `test:gems` | `NFR-5`, `NFR-6`, `NFR-10`: every gem's suite in one `ruby -w -W:deprecated` process, stderr scanned for `warning:`, SimpleCov `minimum_coverage 80` over `gems/*/lib/**/*.rb` | a failing test, a warning at load or run time, a leaked thread, coverage below 80 |
| 6 | `test:gates` | `NFR-17`: the gate suites under `test/gates/`, which drive every other gate against its failing fixtures | any fixture a gate stops rejecting |
| 7 | `gates:gemspec_audit` | `SEAM-1`, `NFR-1`, `NFR-2`: core declares nothing; an adapter declares `dexpace-core` at `~> MAJOR.MINOR` plus at most one gem; every floor is `>= 3.2` | a core dependency, a second third-party gem, a stale core constraint, a wrong floor, a gemspec that runs a subprocess (`git ls-files`) or `require_relative`s a helper that does, a gemspec that does not load (named, not a `NoMethodError` on nil) |
| 8 | `gates:require_allowlist` | `SEAM-1`, `SEAM-2`, `NFR-1`: every `require` and `autoload` in every gem — parsed, so `require("x")`, `Kernel.require "x"` and a require after a `;` are all seen — is allowlisted, `dexpace` or under `dexpace/`, or the gem's one declared dependency; every `require_relative` stays inside the gem's `lib/`; a denylist names `json`, the transport names and `timeout` with the requirement that forbids each — `socket` scoped to core and the transport adapters, so the conformance gem's wire server may have it, the rest denied to every gem; a feature that is not a string literal is refused as unreadable | `base64`, `logger`, `tsort`, `json`, `timeout`, `net/http` in any gem, `socket` in a bound gem, an escaping `require_relative`, `require("json")`, `Kernel.require`, `autoload :JSON, "json"`, `require name` |
| 9 | `gates:serde_boundary` | `SSE-37`, and the phase-7 segmentation design's spec-forced boundary 5: core's SSE layer and its pagination layer -- `lib/dexpace/sse.rb`, `lib/dexpace/sse/**`, `lib/dexpace/page.rb`, `lib/dexpace/page/**` and their `sig/` mirrors -- hold no serialization dependency, checked by a PARSED scan (prism for every `require`/`require_relative`/`autoload` spelling and every constant read or path, the RBS lexer for every type name), so the YARD may say the words the requirement asks for; every guarded glob must match at least one file, and a path whose files are not on the base yet sits on a printed `PENDING` list until they land, when its rows move to `GUARDED` -- the pagination layer's did on 2026-09-20, when 7c was reconciled onto the tree that holds the gate, and the list has been empty since (added by phase 7b) | `require "json"`, `require_relative "../serde/json"`, `Dexpace::Serde`, a bare `Serde` or `JSON`, `::JSON`, `self::JSON`, a serde type in a guarded `.rbs`, a guarded file that does not parse, a feature that is not a string literal, a `GUARDED` glob matching nothing |
| 10 | `gates:cause_walk` | `XCUT-9`: `Dexpace.each_cause` is the ONLY walk of an error's cause chain, checked by a parsed scan over every gem's `lib/`. A send is three node types — `a.cause` is `:CALL`, `a&.cause` is `:QCALL`, a bare `cause` is `:VCALL` — and a reflective `send`/`__send__`/`public_send`/`method` naming `:cause` is seen too, by Symbol AND by String; a Symbol literal is `:LIT` on 3.2 and 3.3 and `:SYM` on 3.4 and 4.0, so both are named. A send carrying an ARGUMENT is not a walk, which is what keeps 5b's `Event#cause(error)` builder out. Allowlist: `each_cause.rb` itself (added by phase 9) | `error.cause` anywhere else, `e&.cause`, `errors.map(&:cause)`, `e.send(:cause)`, `e.public_send("cause")` |
| 11 | `gates:bounded_map` | `XCUT-14`: only `Dexpace::BoundedMap` holds a map whose key space a caller or a server chooses, checked as a parsed scan for a `Hash` assigned to an instance variable — a literal, `Hash.new`, `::Hash.new`, a chained call on a literal and an `||=` are all seen. The allowlist is a path ⇒ REASON Hash and each of its six entries carries the adjudication that put it there, because an allowlist whose entries carry no argument is a list of things somebody once silenced; a test asserts every entry names a live file the scan still reports, so a stale entry cannot silently re-open a hole (added by phase 9) | `@by_origin = {}` in a new file, `@cache = Hash.new`, `@seen ||= {}` |
| 12 | `gates:seam_names` | `SEAM-2`: core never names a concrete seam implementation, matched by the LEAF namespace each adapter gem owns — `Serde::JSON`, `Transport::NetHTTP`, `Transport::AsyncHTTP`, `Async::Thread` — anywhere in a constant path or a String or Symbol literal, so `const_get("Dexpace::Serde::JSON")` is caught beside the bare constant. A fixed list of fully qualified names caught 0 of 4 realistic shapes and matching any path under a seam namespace flagged 31 conforming references, so the rule is the leaf pair; a later adapter gem adds its leaf here or is invisible, which is the gate's stated gap (added by phase 9) | `Dexpace::Serde::JSON` in core, `Transport::NetHTTP`, `const_get(:"Dexpace::Async::Thread")` |
| 13 | `gates:clean_bundle` | `SEAM-1`, `NFR-1`, `NFR-10`: each gem loads inside a scratch bundle holding only itself (and core, for an adapter); Bundler refuses every undeclared gem | a `require` of a bundled gem nobody declared — `logger` on Ruby 4.0 |
| 14 | `gates:rbs_surface` | `NFR-11`: no constant outside `Dexpace::` and a stdlib allowlist in any public signature. The signatures are loaded as one set and every name resolved against it, the way `rbs validate` does, so a relative `Headers` inside `module Dexpace` and a type variable `T` are not leaks; every type tree is then walked, so a leak inside an optional, a union, a tuple, a record, a proc or a type argument is seen | `Async::Task` as a return type, superclass, mixin (name or type argument), type alias, class or module alias, class- or method-level generic bound, or anywhere inside a type; `DexpaceX::Thing`; a set that does not resolve |
| 15 | `gates:sig_diff` | `NFR-4`: every public declaration in `sig/`, parsed and flattened to one line per overload with `private` honoured, against the last `v*` tag, per gem; a removed **or narrowed** declaration fails | a declaration or file gone since the tag, a dropped overload, a method moved under `private` (vacuous, by stated design, until the first tag) |
| 16 | `gates:surface_snapshot` | `NFR-4`: the runtime constant and method tree each gem adds to `Dexpace`, walked from the root and not from the gem's own constant — so an export placed *beside* a namespace (`Dexpace::Transport::Shared`, a method on `Dexpace::Transport`) is in the manifest — `Data.define` readers (those still public on the model) and singleton methods included, a `private_constant` excluded, one line per method, against `test/fixtures/surface/<gem>.txt`; an adapter's manifest is what its entry file adds with core already loaded, so core's lines are in core's manifest only | any export not in the manifest, inside or beside the gem's namespace; `rake surface:regenerate` is the deliberate act |
| 17 | `gates:single_instance` | design §2.4: one resolved path per core file; `Dexpace::VERSION` equals the gemspec. A second copy of core cannot finish loading once core holds `Data.define` models — Ruby refuses the re-opened class with `superclass mismatch` — and the gate reports that in the same terms, beside the features loaded twice before it | one core feature resolved from two directories; a version literal that disagrees |
| 18 | `gates:versions` | `NFR-14`, `NFR-10`: `.ruby-version`, the CI matrix, six gemspec versions and floors and six `VERSION` literals all agree with `VERSIONS` | any consumer that drifted; a gemspec that does not load |
| 19 | `gates:reproducible` | `NFR-12`: each gem built twice under a fixed `SOURCE_DATE_EPOCH` is byte-identical | a gemspec whose build depends on anything but its inputs |
| 20 | `yard` | styleguide 14.1: every public object documented | `yard stats --list-undoc` below 100% |
| 21 | `bundler_audit` | a known CVE in the resolved bundle | `bundler-audit check --update` |

## Where they run

`.github/workflows/ci.yml` has two jobs. **`test`** runs `test:gems` and gates 7, 8, 13 and 17 on
every Ruby in the matrix — 3.2, 3.3, 3.4 and 4.0 — because those are the gates whose answer
depends on the interpreter: a method absent on the 3.2 floor, or a name that becomes a bundled gem
at 4.0. **`gates`** runs everything else once, on the development Ruby named in `.ruby-version`.
`test/gates/ci_workflow_test.rb` asserts every gate appears in a job and no job may fail, so a
gate added to the default task and forgotten in CI is caught.

## Running one gate against its failing input

Every gate body that is more than a subprocess and a message is a module under `tools/`
(`gates:clean_bundle` and `gates:single_instance` are inline in `tasks/gates.rake`), so
`test/gates/<gate>_test.rb` can call it directly against a fixture under
`test/fixtures/gates/<gate>/`. The task itself can be pointed at a fixture too:

```bash
DEXPACE_GATE_ROOT=test/fixtures/gates/gemspec_audit/two_third_party bundle exec rake gates:gemspec_audit
DEXPACE_GATE_ROOT=test/fixtures/gates/invariants/workspace bundle exec rake gates:cause_walk
DEXPACE_GATE_ROOT=test/fixtures/gates/invariants/workspace bundle exec rake gates:bounded_map
DEXPACE_GATE_ROOT=test/fixtures/gates/invariants/workspace bundle exec rake gates:seam_names
RUBYOPT=-r./test/fixtures/gates/serde_boundary/pending_probe.rb bundle exec rake gates:serde_boundary
DEXPACE_SURFACE_EXTRA=Injected bundle exec rake gates:surface_snapshot
DEXPACE_SURFACE_EXTRA=Dexpace::Transport::Shared bundle exec rake gates:surface_snapshot   # beside a namespace
DEXPACE_FORCE_DUPLICATE=1 bundle exec rake gates:single_instance
```

Nothing in the build sets any of these; they exist so a gate is watched to go red, not assumed
to.

## Three facts worth knowing before you fight a gate

- **`Gemfile.lock` and `rbs_collection.lock.yaml` are not committed.** Each Ruby resolves its
  own; remove the lock before switching interpreters, because a lock written by Bundler 4 makes
  an older Bundler try to install Bundler 4.
- **Every subprocess the build starts runs on the interpreter running `rake`.** `ruby`, `gem`
  and `bundle` are taken from `RbConfig` (`tools/interpreter.rb`), never from `PATH`, so a
  version-manager shim that ignores `.ruby-version` cannot make `gates:clean_bundle` report one
  Ruby and run on another; the clean-bundle smoke script asserts the `RUBY_VERSION` it landed on.
  Only the outermost `bundle exec rake` is yours to point at the right Ruby.
- **`gem build` writes every tar entry's mtime as `Gem.source_date_epoch`**, so under the fixed
  epoch `gates:reproducible` always sets, a touched file never changes the artifact. What the
  epoch falls back to when the variable is *unset* depends on RubyGems, not on this repository:
  from RubyGems 3.6 (the Ruby 3.4 and 4.0 rows) it is a fixed 1980-01-02; on the 3.2 and 3.3 rows
  it is `Time.now`, so two builds a second apart differ. The gate never relies on the fallback,
  and its negative input is a build that depends on something other than its inputs — a gemspec
  that reads the clock — not a touched mtime, which cannot show under the epoch.
