# Open Items

Running register of everything found to be unmet, unverified, misreported, or surprising in the
Ruby SDK. **This records what is known and not yet resolved — it is not a plan.** A finding lands
here whether or not anyone has yet decided what to do about it; deciding what to do is a separate
act from noticing the gap.

An open item is a discovery made **after** the work it checks against already exists: "this is not
what the design, the checklist, or the code claims it is." That is the boundary against the other
two registers at the `docs/` root:

| Register | Holds | Item is |
|---|---|---|
| `open-items.md` (this file) | Everything found unmet, unverified, misreported, or surprising | A gap discovered **after** the work |
| [`deferred-items.md`](./deferred-items.md) | Work consciously postponed while building the SDK | A decision made **before** the work: "not this phase, that one" |
| [`deviations.md`](./deviations.md) | The as-built audit of `sdk-design-ruby/10`'s deviation ledger | A place the port deliberately differs from the reference contract, and whether that has landed in code |

The same requirement ID can legitimately appear in more than one register at once.

## Item format

```
### OI-<n> — <title>

- **Opened:** <date>, <phase or source that found it>
- **Status:** open | resolved (<date>)
- **Cites:** <requirement IDs this touches, comma-separated, or "none">

<Body: what was found, why it matters, and what would resolve it.>

**Resolution:** <filled in only once Status moves to resolved — what changed, and where>
```

`Opened` names both a date and where the finding came from — a phase, a review, an audit pass — so
a later reader can tell what state of the repository produced it. `Cites` links the finding to the
normative requirement IDs it bears on, if any; `none` is a legitimate value for a purely
structural or process finding.

## The rule

Item IDs are **permanent**: never renumbered, never reused. They are cited from source comments,
tests, design documents, and phase records as well as from this file. **A resolved item is never
deleted.** It stays, with `Status: resolved (<date>)` and a filled-in `Resolution`, so that every
citation of `OI-<n>` anywhere in the repository — including one written before the item was
resolved — still resolves to something. A section that shrinks as items are "cleaned up" is a
section whose citations quietly start pointing at nothing.

A new item takes the next id below and appends; nothing here is edited except to fill in `Status`
and `Resolution` on an existing item.

---

### OI-1 — Five SEAM requirements exist only as appendix-C rows, and the gap pointer sends a reader to a chapter that does not carry them

- **Opened:** 2026-09-06, phase 2 (Seam Foundations) planning
- **Status:** open
- **Cites:** SEAM-15, SEAM-20, SEAM-22, SEAM-23, SEAM-28

`docs/product-spec/03-pluggable-seams-and-extension-model.md` carries 22 of the 30 `SEAM` IDs in
its prose, `SEAM-29` among them. Three more — `SEAM-1`, `SEAM-2` and `SEAM-13` — are stated only in
`docs/product-spec/02-architectural-principles.md`, which also restates `SEAM-29`. That accounts
for 25. The remaining five — **`SEAM-15`, `SEAM-20`, `SEAM-22`, `SEAM-23` and `SEAM-28`** — appear
nowhere in the specification's prose at all:
`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` is their only normative
statement. Verified on 2026-09-06 and re-verified on 2026-09-07 with
`grep -o 'SEAM-[0-9]*' docs/product-spec/*.md | grep -v appendix-c | sort -uV`, which lists exactly
25 IDs.

Why it matters rather than being a curiosity. Both the roadmap's gap paragraph
(`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`) and
`ruby scripts/knowledge.rb --gaps SEAM` tell a phase to read `SEAM-22` and `SEAM-28` "out of
`docs/product-spec/03-pluggable-seams-and-extension-model.md`", and neither ID is in that file. A
phase following the instruction literally either reads the wrong requirements or concludes the
specification is missing them — and the two that carry the pointer are precisely the two the corpus
cannot answer, so the phase reading them has no second source. The CLI is not wrong: it derives the
pointer from appendix C's own subsystem cell, so it names the subsystem's owning chapter rather
than asserting the ID is in it. The roadmap inherited that pointer and restated it as an
instruction.

The three IDs beyond the two named gaps are the quieter half: `SEAM-15`, `SEAM-20` and `SEAM-23`
*do* have substantive corpus entries — all three are design-role, from
`docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.4 and §3.7 — so a phase querying the
corpus gets a good answer and never learns that the design entry is the only prose between it and
appendix C. Phase 2 read all five out of appendix C directly and says so in its design.

What would resolve it: either the specification gains prose for the five (which is a change to a
frozen tree and a human's deliberate act), or the roadmap's gap paragraph and
`scripts/knowledge.rb`'s `--gaps` output name **appendix C** as the source for an ID whose
subsystem chapter does not contain it. The second is the smaller change and is mechanical — the CLI
already knows every ID's location, so it could compare against the chapter text rather than
assuming it.

**Resolution:** *(open)*

### OI-2 — IO-6 is a live MUST that exists only as an appendix-C row, and every statement of its content cites the retired SEAM-3

- **Opened:** 2026-09-08, phase 3 (I/O and Body Lifecycle) segmentation design
- **Status:** open
- **Cites:** IO-6, IO-16, SEAM-3, BODY-8

`IO-6` is a MUST: "When a provider wraps a caller-supplied underlying stream (readable stream ->
buffered source, writable stream -> buffered sink), the returned wrapper MUST take ownership of that
stream: closing the wrapper closes the underlying stream. The same holds for the stream bridges
obtained from a buffered source/sink … Wrapping a plain byte array owns no external resource."

**It appears in no specification chapter and in no design chapter.** Verified 2026-09-08 with a
repository-wide grep: outside
`docs/product-spec/appendix-c-consolidated-normative-requirement-index.md`, the string `IO-6` occurs
exactly once in the whole tree — in the gap-ID paragraph of
`docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`, which instructs the phase to read it "out of
`docs/product-spec/05-i-o-contracts.md`". That chapter does not carry it: §5.1 runs `IO-1`–`IO-5` and
`IO-18`, and the *bridge* half of `IO-6`'s obligation survives there only under **`IO-16`, a SHOULD**
("closing the bridge MUST close (or invalidate) the owning source"). The *wrap* half — the MUST — is
in appendix C alone.

Why it matters rather than being a curiosity, and why it is a sharper case than `OI-1`. Both places
that state `IO-6`'s content attribute it to **`SEAM-3`**, an ID
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` item 1 retires and
phase 2 shipped as 🚫: `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.1's "Two
ownership rules, deliberately different" paragraph reads "At the I/O layer, wrapping takes
ownership: closing a `BufferedSource` built over a caller's `IO` closes that `IO` (**SEAM-3**)", and
the corpus entry `message-bodies/8a1e7a7b` repeats the attribution. A phase auditing the retirement
of `SEAM-3` and finding no surviving citation could reasonably conclude the ownership rule retires
with the seam. It does not — `IO-6` is its surviving normative home, `docs/sdk-design-ruby/10-…md`
item 12 depends on it ("ownership-on-wrap remains the I/O layer's rule and is deliberately not the
body layer's"), and `BODY-8` is the other half of that one decision. Losing it would leave every
`BufferedSource` built over a caller's stream leaking that stream on close, which no gate would
catch, because the requirement it violates is cited nowhere a reader looks.

The roadmap's gap paragraph is also wrong about this ID in the same breath as being right about the
other four: it says of `IO-6`, `IO-32`–`IO-35` that "four of the five are the byte-stream provider
apparatus §10.1 retires, which is a decided non-implementation and not unmapped spec". That is exact
for `IO-32`–`IO-35`. `IO-6` is the fifth, and it is neither retired nor a non-implementation.

What would resolve it: the same two routes `OI-1` names — either the specification gains prose for
`IO-6` in `docs/product-spec/05-i-o-contracts.md` (a change to a frozen tree and a human's deliberate
act), or the roadmap's gap paragraph and `scripts/knowledge.rb --gaps` name **appendix C** as the
source for an ID whose subsystem chapter does not contain it. A third, narrower repair belongs to
whoever next amends the design: §3.1's ownership sentence and §10.12 should cite `IO-6` rather than,
or alongside, `SEAM-3`. Phase 3's segmentation design records the finding and directs sub-phase 3a to
read `IO-6` out of appendix C directly.

**Resolution:** *(open)*

### OI-3 — Dexpace:: constant shadowing is not inert outside core, and phase 1's claim reads wider than what was verified

- **Opened:** 2026-09-08, phase 3a (I/O contracts) design
- **Status:** open
- **Cites:** none

`docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md` records, of
`Dexpace::Method` shadowing `::Method`: "**Verified inert outside core**: a consumer's top-level
`Method` still resolves to Ruby's, because `Object`'s own constants win over an included module's."
The observation is true. The conclusion drawn from it is wider than the observation supports.

Verified on 2026-09-08 against 3.2.11, 3.4.10 and 4.0.6, with the same result on all three. A
**top-level** `include Dexpace` is indeed inert: it inserts `Dexpace` into `Object`, so `Dexpace`
lands *after* `Object` in every ancestry, `Object`'s own constant table is searched first, and a bare
`IO` or `Method` still resolves to Ruby's. But a consumer writing

```ruby
class C
  include Dexpace
  def check(x) = x.is_a?(IO)
end
```

gets `Dexpace::IO`, because `include` inserts `Dexpace` **ahead of** `Object` in `C.ancestors`
(`[C, Dexpace, Object, Kernel, BasicObject]`). `C#check` then returns **`false` for a real `::IO`**,
with no error and no warning; `IO === x` is false and a `case/when IO` falls through. `extend Dexpace`
and a class with no include are unaffected; a `module M; include Dexpace` is affected the same way a
class is. The two cases disagreeing is why the original measurement, taken at the top level, gave the
wrong general answer.

Why it matters rather than being a curiosity. The finding is about **every flat `Dexpace::` constant
that shares a name with a core class** — `Dexpace::Method`, `Dexpace::Request`, `Dexpace::Response`,
`Dexpace::Query`, `Dexpace::Status`, and now `Dexpace::IO`, which phase 3a adds and which is the one
callers most often type-test. `include Dexpace` is an ordinary Ruby convenience and phase 1
deliberately measured it, so it is a use this port expects. No gate this repository owns can reach a
consumer's file: phase 3a's extension of `Dexpace/QualifiedCoreConstant` covers `gems/*/lib/**/*.rb`
and stops at the gem boundary by construction.

What would resolve it: nothing mechanical, and renaming is not on the table — design §3.1 and §10.2
name `Dexpace::IO::Buffer` and phase 1's P1-1 keeps a namespace the design gave a subsystem. What can
be done, and what phase 3a does, is state it where a reader meets it: the hazard is recorded in
`Dexpace::IO`'s own YARD block. What is *not* yet done, and is why this row is open: the same warning
belongs in `docs/sdk-documentation/` once that is written, and a release decision should see it —
neither has a home yet.

**Resolution:** *(open)*

### OI-4 — A source retains every view derived from it until it is closed, and the deregistration is O(n)

- **Opened:** 2026-09-08, phase 3a (I/O contracts) plan
- **Status:** open
- **Cites:** IO-19, IO-20, IO-22, IO-38, IO-42, BODY-22, BODY-29

`Dexpace::IO::TypedReads` keeps `@dexpace_views`, an `Array` of every view built from the object,
because `IO-22` requires that "closing the parent source MUST invalidate every outstanding slice
derived from it so that subsequent reads on those slices fail loudly … never returning stale or
arbitrary bytes", and `IO-38` requires that invalidation to be visible across threads. A view removes
itself from that array on its own `#close`, through `#dexpace_forget_view`. A caller that takes many
views and closes none — which nothing in the contract forbids, and `IO-22`'s "closing a slice MUST
NOT close its parent" positively invites — grows the array for the parent's whole lifetime, and each
later `#dexpace_forget_view` is an `Array#delete`, a linear scan.

Why it is recorded rather than fixed. It is bounded by construction everywhere phase 3a can see:
every `#peek` in this SDK is a bounded preview, and the parent is a response body whose lifetime is
one request. The first place that bound stops being obvious is phase 3b, whose `BODY-22`–`BODY-29`
response-logging drain takes a view **per attempt on a retried request**, and phase 6's retry loop is
what decides how many attempts there are.

What would resolve it, and what would not. A weak-reference table would trade a real, measurable cost
— an allocation and an indirection on every view — for a hypothetical one, and the `ObjectSpace`
finalizer alternative is barred twice over: by `resource-management/1676974d` ("never rely on
finalizers or the garbage collector for deterministic resource cleanup") and by
`docs/sdk-design-ruby/07-pagination-sse-and-serialization.md` §7.1's independent derivation of the
same rule from the `Enumerator`/`ensure` asymmetry. Replacing the `Array` with a `Hash` keyed by
`object_id` would make the deregistration O(1) at the cost of a second structure to keep in step. The
right first move is a measurement, on phase 3b's actual drain, not a redesign here.

**Resolution:** *(open)*

### OI-5 — `#read_line_utf8` is the one drain-style read the 64 MiB ceiling does not guard

- **Opened:** 2026-09-08, phase 3a (I/O contracts) design review
- **Status:** open
- **Cites:** IO-9, IO-14, SSE-11, SSE-12, BODY-32

Phase 3a's deviation **P3-4** widens `IO-9`'s SHOULD so that `MAX_MATERIALIZED_BYTES` guards every
operation producing one contiguous `String` — `#snapshot`, `#read` with no count, `#read_exactly`,
`#read_utf8`, `#read_string` and a length-bounded slice read. The three drain-style members of that
list are guarded **incrementally**, as the result grows, precisely because their size is not known
before they start. `#read_line_utf8` is not among them, and cannot be: `IO-14` fixes no maximum line
length, so there is neither a count to check up front nor an end to stop at but a terminator that
may never arrive. A source that never yields `\n` therefore materialises the whole stream into one
`String`, which on a stream-backed source is exactly the OOM `IO-9` exists to convert into an
actionable error.

**It is the one *drain-style* read outside the guard, not the one read outside it.** `#read(length)`
and `#readpartial(maxlen)` are outside it too, and correctly so: `IO-9` itself leaves them there —
"plain (non-slice) exact-count buffered reads instead inherit whatever bounds check the underlying
stream library performs". P3-4 widens the SHOULD over `#read_exactly` and not over those two on the
**provenance of the count**, not its size: `#read_exactly` is what `HTTP-39`/`BODY-10`'s
exact-length copy drives, and `BODY-10`'s count is a *declared* length — a number a peer chose —
while `#read(length)` and `#readpartial(maxlen)` take a number the calling code chose. This item is
about the read that has no count at all.

Why it is recorded rather than fixed in phase 3a. `IO-9`'s own scope names `snapshot()` and
length-bounded slice reads; a line read is neither, so guarding it would widen the SHOULD a second
time against a requirement (`IO-14`) that positively describes an unbounded read. The consumer that
reads lines from a stream a server controls is **phase 7's SSE machine**, and `SSE-11` already
obliges that machine to carry its own documented cap —
`docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` item 18 catalogues
`SSE-11`'s cap in the same breath as `IO-9`'s. Putting a second, lower, silent cap underneath it in
phase 3a would give one stream two ceilings, which is the failure phase 3's segmentation boundary 8
pins for the materialisation constant.

What would resolve it, and what would not. Phase 7 supplying `SSE-11`'s cap **at the line-machine
level**, so the bound is one documented number in the layer that knows what a line means, resolves
it for the only consumer in the MVP. Adding a `max_line_bytes:` keyword to `#read_line_utf8` would
not: phase 5 owns the configuration chain, `IO-40`-adjacent limits reaching this layer is what
`docs/knowledge/notes/resource-management.md` already declines for timeouts, and a keyword with no
configuration source behind it is `DEF-28`'s shape without `DEF-28`'s pick-up condition. Until phase
7 lands, the honest statement is the one phase 3a's design now carries at the method: the bound is
the caller's.

**Resolution:** *(open)*

### OI-6 — RuboCop's own report is not clean for any phase under `.rubocop.yml` as phase 0 wrote it

- **Opened:** 2026-09-08, phase 3a (I/O contracts) plan review
- **Status:** open
- **Cites:** NFR-7, NFR-10

Every phase plan ends by running `bundle exec rubocop --fail-level=convention` and expecting it
clean. Measured for the first time here, by extracting each plan's `lib/` fences and running
**RuboCop 1.90.0** against `docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates.md`'s
`.rubocop.yml` exactly as that plan writes it: **it is clean for none of them.**

What phase 1's and phase 2's `lib/` fences already report, before phase 3 exists — 32 files
inspected, and the counts are of offenses:

| Cop | Count | Why it fires |
|---|---|---|
| `Layout/EmptyLineAfterMagicComment` | 32 | The two-line header **phase 0 itself mandates** — `# frozen_string_literal: true` then `# SPDX-License-Identifier: MIT` — puts a non-magic comment where the cop wants a blank line. It fires on every file in the repository, present and future |
| `Metrics/AbcSize` | 8 | Never configured; RuboCop's default of 17 applies |
| `Naming/RescuedExceptionsVariableName` | 4 | This repository has written `rescue … => error` since phase 1; the cop's default `PreferredName` is `e` |
| `Style/ArgumentsForwarding`, `Naming/BlockForwarding`, `Style/DataInheritance`, `Layout/MultilineMethodCallIndentation`, `Layout/EmptyLinesAfterModuleInclusion`, `Metrics/CyclomaticComplexity`, `Metrics/PerceivedComplexity`, `Style/ModuleFunction`, `Metrics/ClassLength`, `Naming/PredicateMethod`, `Style/SymbolProc`, `Style/MultipleComparison`, `Style/TrailingCommaInArguments`, `Style/TrailingCommaInArrayLiteral` (four of them in **phase 0's own** `.rubocop/test/cops_test.rb` fence) | 1–8 each | Mostly cops added or tightened after the config was written |

`test/` is worse and is not excluded: phase 1's and phase 2's 37 suite fences report
`Minitest/MultipleAssertions` ×33 (the cop's default cap is 3), `Minitest/AssertPredicate` ×22,
`Minitest/EmptyLineBeforeAssertionMethods` ×15 and `Minitest/RefutePredicate` ×10. Two of those are
**not** configuration gaps either: `Minitest/AssertPredicate` and `Minitest/RefutePredicate` propose
exactly the form phase 1 documented as unusable here — `assert_predicate` sends past `private` on
the 3.2 floor, which is why every plan's Global Constraints say "visibility is asserted with
`respond_to?`, never `assert_predicate`".

Phase 3a adds `Metrics/ModuleLength` on `TypedReads` (399 lines) and `TypedWrites` (145) and
`Metrics/AbcSize` on two chunk-store helpers to the same list, and nothing else: its plan review
fixed every `Layout/LineLength`, `Metrics/ParameterLists`, `Style/SafeNavigation`,
`Style/MinMaxComparison`, `Style/ComparableClamp`, `Style/TrailingCommaInArguments`,
`Style/TrailingCommaInArrayLiteral`, `Layout/EmptyLineBetweenDefs` and
`Layout/EmptyLinesAroundAccessModifier` finding in its own `lib/` and `test/` fences.

Why it matters. `NFR-7` makes RuboCop findings fatal, so a gate that cannot pass is a gate that
gets `--fail-level` lowered or `Exclude:`d in a hurry by whoever first runs `bundle exec rake` — at
which point the cops that *are* load-bearing stop being read. It also makes every plan's "Expected:
clean" step unfalsifiable, which is the specific failure this register exists to catch: three phase
plans state a verification result none of them could have observed.

One finding inside it is **not** a configuration gap and must not be autocorrected.
`Style/SymbolProc` on phase 3a's `@dexpace_views.each { |view| view.dexpace_invalidate }` proposes
`&:dexpace_invalidate`; `#dexpace_invalidate` is `protected`, and the symbol form sends it publicly
— verified `NoMethodError: protected method 'dexpace_invalidate' called for an instance of …`. The
block form is load-bearing. Any resolution that runs `rubocop --autocorrect` over the tree has to
exclude it.

What would resolve it: one reviewed `.rubocop.yml` diff that, per cop, either sets the value this
repository actually wants or disables the cop with the reason named — the shape phase 0 already
fixed for the require allowlist ("a reviewed one-line diff with the requirement that motivated
it"), and the shape `tooling-and-quality-gates/d39dd7c6` requires of every override ("an
unexplained `Enabled: false` is rejected in review"). It is deliberately **not** phase 3a's to make:
3a widened one cop's `Include:`, and the phase that widens a watch must not also be the phase that
relaxes four metric cops for every gem. It belongs to whoever lands phase 0, against the RuboCop
version `VERSIONS` actually pins — which is not 1.90.0 by construction, so the list above is a floor
on the work, not a specification of it.

**Resolution:** *(open)*

### OI-7 — design §3.1's decode recipe destroys every non-ASCII byte, and its target-less `#encode` follows a process global

- **Opened:** 2026-09-08, phase 3b (body lifecycle) design
- **Status:** open
- **Cites:** HTTP-42, HTTP-24, IO-13, BODY-16

`docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.1 fixes exactly one decode boundary and
names the mechanism: `Response#body_string`, "which applies the media type's charset via
`String#encode(invalid: :replace, undef: :replace)` and falls back to UTF-8 when absent or unknown". The
**rule** is right and phase 3b implements it unchanged. The **mechanism** is wrong in two independent
ways, each verified on 2026-09-08 against 3.2.11, 3.4.10 and 4.0.6.

**It mangles the payload.** The same paragraph requires the port to retag every response body to
`Encoding::BINARY` on ingress and never trust a transport's tagging, so the bytes reaching that call are
BINARY. From BINARY, every byte at or above `0x80` is an *undefined character in the source encoding*,
which `undef: :replace` replaces: `"café".b.encode(::Encoding::UTF_8, invalid: :replace, undef: :replace)`
returns `"caf"` followed by two U+FFFD replacement characters — one per byte of the two-byte UTF-8 `é` —
and is not `==` to the correct answer on any of the three interpreters. The bytes have to be **retagged**
to the declared charset first, which is what phase 3a's `Dexpace::IO::TypedReads#read_string(encoding)`
already does, and only then transcoded.

**And its result depends on a process global the host controls.** The cited call passes no target
encoding, and `String#encode(invalid: :replace, undef: :replace)` with none converts to
`Encoding.default_internal`. With `Encoding.default_internal = ::Encoding::ISO_8859_1` — a single line
any host application may have run — the same call on the same string returns an ISO-8859-1 result with
the accented character destroyed, while the explicit-target form is unaffected; verified both ways on all
three. That is the same passes-where-you-look shape §3.5 pins `URI::RFC3986_PARSER` against and that
`IO-14` avoids `IO#gets` and `$/` for, and it is the reason this is a finding rather than a nit: a
library must not let a host global decide what its decode returns.

Why it matters beyond phase 3. §3.1 is frozen and is the sentence a later reader copies. Nothing
mechanical catches it: the result is a well-formed `String`, `rbs`/`steep` see a `String` either way, and
**an ASCII-only test fixture passes under the bug** — the same trap phase 3a recorded for its ingress
retag, which is why every encoding test in phase 3 uses non-ASCII content.

What phase 3b does, and what would resolve the item. `Response#body_string` resolves the charset from
`Dexpace::MediaType#charset` (phase 1 already returns `nil` for an absent **or** unknown-to-this-Ruby
charset, so `HTTP-42`'s fallback needs no second validation and `Encoding.find` cannot raise), retags
through `#read_string`, then transcodes with **both** encodings named:
`#encode(enc, invalid: :replace, undef: :replace)`. Verified `valid_encoding?` for UTF-8 bytes declared
UTF-8, ISO-8859-1 bytes declared ISO-8859-1, and ISO-8859-1 bytes mis-declared as UTF-8. What would
resolve the item is one corrected sentence in §3.1 the next time §3 is deliberately amended by a human;
until then the corpus note against `io-and-byte-streams/fbcb4d19` in
`docs/knowledge/notes/io-and-byte-streams.md` is what stops the next reader repeating the recipe. It is
**not** a deviation from the reference contract — `HTTP-42` is satisfied exactly — which is why it lands
here and not in `docs/deviations.md`, the same judgement phase 3a made for `OI-2`.

**Resolution:** *(open)*

### OI-8 — `TeeSink#clear_tap` is `NFR-4`-locked public API with no core caller

- **Opened:** 2026-09-08, phase 3b (body lifecycle) design
- **Status:** open
- **Cites:** BODY-18, BODY-17, IO-26, IO-29, NFR-4

Phase 3a shipped `Dexpace::IO::TeeSink#clear_tap` for one stated reason — its design says the method
"exists because `BODY-18` requires the tap cleared at the start of every write of the wrapped body" —
and its `3a→3b` contract table hands it to phase 3b as "`#clear_tap` for `BODY-18`'s per-attempt
reset". Phase 3b satisfies `BODY-18` a different way, and the difference is forced rather than chosen:
`TeeSink.new(primary:, tap_limit:)` binds its primary **at construction**, and a retry writes to a
different sink on a different connection, so one tee cannot span two attempts. `Dexpace::RequestLoggingBody`
therefore builds a **fresh** `TeeSink` per `#write_to` call. That satisfies `BODY-18` by construction —
a fresh tap cannot accumulate an earlier attempt's bytes — and is strictly stronger than clearing one,
because it also drops the previous attempt's memory rather than retaining a cleared buffer for the
wrapper's lifetime. The consequence is that `#clear_tap` has **no caller anywhere in core**, while
being a public method with a YARD block and an RBS signature, which is this repository's own definition
of public surface and is therefore locked by `NFR-4` at the first release tag.

Why it is recorded rather than fixed. Rewriting a committed, adversarially reviewed 3a plan on the
strength of an unreviewed 3b design decision is the wrong order: the fresh-tee approach is this
document's, it has not been reviewed, and a plan that removes a method from a reviewed document to suit
an unreviewed one inverts the dependency the sub-phase split exists to keep clean. Phase 3a stays as
committed.

What would resolve it, and why the window is now. Phase 3b's plan and its review confirming the
fresh-tee-per-write mechanism, after which **phase 3a's plan may drop `#clear_tap` before execution** —
neither plan has been executed, no gem exists, every gem is at `0.0.0` and nothing is published
(`docs/first-release.md`), so removing the method costs one edit to an unexecuted plan and one line of
its `sig/` mirror. After the first release tag the same removal is a public signature disappearing,
which `NFR-4`'s API lock treats as a breaking change requiring a major bump. That asymmetry is the whole
reason this is filed now rather than noticed later. The alternative resolution is equally admissible and
costs nothing: keep `#clear_tap` as a deliberate convenience for an SDK author reusing a tee directly,
with its YARD saying that core does not call it and why — but that has to be a decision someone made,
not a method nobody removed.

**Resolution:** *(open)*

### OI-9 — `BufferedSource.wrapping` delivers one byte per read, so every wrapping-backed transfer is one syscall per byte

- **Opened:** 2026-09-08, phase 3b (body lifecycle) plan
- **Status:** open
- **Cites:** IO-1, IO-2, IO-16, BODY-10, BODY-17, BODY-22, HTTP-39, HTTP-42

`Dexpace::IO::BufferedSource.wrapping(io)` — the factory a transport uses to build a response body,
and the one phase 3b's `Dexpace::StreamBody` uses to read a caller's upload stream — returns **one
byte** from `#read_into(dest, count: N)` for any positive `N` whenever its buffer is empty, and
yields **one-byte chunks** from `#each`. Measured on 3.2.11, 3.4.10 and 4.0.6 on 2026-09-08: 200 000
bytes come back as 200 000 chunks through 200 001 `readpartial(1)` calls, taking ~0.21 s where the
same 200 000 bytes through a `Dexpace::IO::Buffer` or a `BufferedSource.over` source take 0.000 s.
The three interpreters agree to within a few milliseconds.

The cause is one line, in two places with the same shape. `#read_into` fills through
`#fill_once_if_empty`, which is hard-coded to `ensure_buffered(1)` — that is, `fill(1)` — and
`#fill_from_upstream(min_bytes)` then calls `readpartial([min_bytes, 1].max)`, so the count the
caller asked for never reaches the upstream. `#store_take_chunk`'s empty refill inside `#each` and
`#drain_all` is the same. Passing the requested count instead — `fill(count)`, which still fills
**once** and still returns whatever came back — is non-blocking and satisfies `IO-1`'s "at least 1
when byteCount is positive and the source is not exhausted" exactly as `fill(1)` does. `#read(n)` is
already the efficient path and is not affected, because `#read_up_to` calls `ensure_buffered(length)`;
but `#read(n)` blocks until it has `n` bytes or end of stream, so it is not a substitute for the
primitive on a socket.

This is a **throughput** defect and not a correctness one. Every read returns the right bytes in the
right order, every `IO` requirement is met, and phase 3a's suite is green and stays green — which is
why no gate would have caught it and why it is filed rather than fixed by a bug report. It reaches
phase 3b's `Dexpace::StreamBody` upload pump, `Dexpace::ResponseBody`'s readers,
`Dexpace::Response#body_string` and `Dexpace::ResponseLoggingBody`'s drain, and it will reach every
transport phase 8 writes, since `BufferedSource.wrapping` is how a response body is built.

Why it is recorded rather than fixed. It is phase 3a's code, phase 3a's plan is committed and
adversarially reviewed, and rewriting it from an unreviewed phase-3b plan inverts the dependency the
sub-phase split exists to keep clean — the same order-of-work argument `OI-8` makes.

What would resolve it, and why the window is now. `OI-8`'s window, exactly: **neither plan has been
executed**, no gem exists under `gems/`, every gem is at `0.0.0` and nothing is published
(`docs/first-release.md`), so the fix is one line inside an unexecuted plan's Task 5 fragment and
changes no signature, no constant and no test. Phase 3b is deliberately built so the fix costs it
nothing: **no test in phase 3b asserts a chunk granularity in either direction**, and its plan's
decision 4 states that the body layer invents no block size and asks the source for the whole
remaining count, so 3b's throughput improves with 3a's fix and none of its 266 tests change. After
the first release tag the same edit is still not an `NFR-4` break — no signature moves — but it is
then a behaviour change against a shipped gem rather than a correction to an unexecuted plan.

**Resolution:** *(open)*

### OI-10 — the response-body surface `Response#close`, `#body_string` and `#body_bytes` are written against is `#source` + `#close`, and two of the three bodies that can occupy `Response#body` do not have it

- **Opened:** 2026-09-08, phase 3b (body lifecycle) design review
- **Status:** resolved (2026-09-08)
- **Cites:** HTTP-41, HTTP-42, HTTP-43, BODY-14, BODY-16, BODY-23, BODY-24, BODY-30, BODY-34, HTTP-52

Phase 3b adds three methods to phase 1's `Dexpace::Response`. Its design states `#close` as "`body&.close`
and nothing else", and `#body_string`/`#body_bytes` as convenience readers that close the body in an
`ensure` (`BODY-16`); its plan writes them against **two** members of the body — `body.source` for the
bytes and `body.close` for the release. Neither member is on the contract they are called through:
`Dexpace::Body`, the module every body includes and the type `DEF-26` narrows `Response#body` to,
declares `#write_to`, `#media_type`, `#content_length`, `#replayable?`, `#to_replayable`, `#each` and the
equality trio, and **neither `#source` nor `#close`**.

Three body types can legitimately sit in `Response#body`, and only one of them satisfies what those
three methods call:

| Body | `#source` | `#close` | Put there by |
|---|---|---|---|
| `Dexpace::ResponseBody` | yes | yes (`Closeable`) | the transport (`HTTP-41`/`BODY-14`) |
| `Dexpace::ResponseLoggingBody` | **no** — the same accessor is named `#read` | yes (`Closeable`) | phase 5's body logging (`BODY-22`–`BODY-29`, `BODY-34`) |
| `Dexpace::BufferBody` | **no** | **no** | phase 4's `Recovery.buffer_error_body` (`BODY-30`/`HTTP-52`) |

So `response.close` raises `NoMethodError` on a response whose error body has been buffered, and
`response.body_string` raises on that one **and** on any response whose body has been wrapped for
logging. Neither is reachable from phase 3b's own suite, because every `Response` it builds carries a
bare `ResponseBody` — which is exactly why it is filed rather than caught: the first failure is in
phase 4, against code phase 3 shipped and phase 3's tests pass over.

`BODY-30` is the sharp end. Its canonical text requires the buffered copy to be "readable independently
and repeatably (**decode it, then snapshot it**) after the original transport connection is released" —
that is `Response#body_string` followed by a snapshot, over a `BufferBody`, twice. Under the current
design the decode cannot run at all, and if `#close` were added naively as "close the buffer" the second
read would return nothing. Both halves of the requirement therefore constrain the answer rather than
merely inviting one.

What would resolve it. One name for the response-body read handle — `#source`, which is the word
`HTTP-41`/`BODY-14` uses ("its read handle (source)") and the name `ResponseBody` already has — declared
on `Dexpace::Body` beside a default `#close`, and implemented by all three: `ResponseBody` unchanged;
`ResponseLoggingBody#source` in place of (or aliased from) `#read`, returning the same
`Dexpace::IO::BufferedSource` in both regimes; and `BufferBody#source` returning a **fresh** `#peek` view
per call, which is `BODY-30`'s "repeatably" and does not collide with `BODY-14`'s "the same underlying
handle every time", a rule about the single-use response body and not about a replayable buffer-backed
copy. `Dexpace::Body#close` defaults to a **no-op** — a body that owns no transport resource has nothing
to release, and `BODY-30` positively requires that `#body_string`'s `ensure`-close leave the buffered
copy readable — with `Closeable#close` overriding it in the two classes that do own something (the
include order is `include Dexpace::Body` then `include Dexpace::Closeable`, so `Closeable` wins). That
also removes the `body.close if body.respond_to?(:close)` guard `Body.buffer_bounded` currently needs,
which is the same hole seen from inside the body layer.

It was filed rather than fixed on discovery because it is a coordinated change across a design and a
plan that are reviewed separately and must agree: it adds two members to `Dexpace::Body`, two to
`BufferBody`, and renames one on `ResponseLoggingBody`, each with an RBS mirror, a surface-snapshot line
and a test.

**Resolution:** resolved 2026-09-08 by the phase-3b design and plan together, to the shape above and
with no residue. `docs/work/mvp/phase3/phase3b/2026-09-08-phase3b-body-lifecycle-design.md` declares
`#source` and a **default no-op `#close`** on `Dexpace::Body` (contract table under "`Dexpace::Body` —
the contract, the factories, the constants"), states the three-body table that says which body answers
`#source` how and why two of those three cells are forced by `BODY-30` rather than chosen, renames
`ResponseLoggingBody`'s drain accessor from `#read` to `#source`, gives `BufferBody` a fresh `#peek`
view per `#source` call and the module's no-op `#close`, fixes the include order as
`include Dexpace::Body` then `include Dexpace::Closeable` so `Closeable#close` wins where a body owns
something, and drops the `respond_to?(:close)` guard from `Body.buffer_bounded`. The decision carries
Deviation Ledger row **P3-23** — a contract widening rather than a naming row, which is why it is not
absorbed into P3-14 — and the testing strategy now drives `#close`, `#body_string` and `#body_bytes`
over a `Response` built on each of the three bodies in turn, with `BODY-30`'s own "decode it, then
snapshot it" as one test, because the shape of this defect was a green suite that only ever used the
one body which happened to have the members. The plan's half lands in the same change under the
manager's coordination.

### OI-11 — a caller mistake in an argument can still leave core as a stdlib exception class

- **Opened:** 2026-09-08, phase 3b (body lifecycle) plan review
- **Status:** open
- **Cites:** HTTP-4, SEAM-29, HTTP-38, HTTP-51, BODY-35

Phase 3b's Global Constraints fix two error vocabularies and no third: `Dexpace::InvalidArgumentError`
for "a caller mistake in an argument", `Dexpace::StreamError` for a stream-contract violation. Two
call sites in phase 3b do not hold to it, and both were found by probing rather than by a test,
because no test passes the input that reaches them.

- `Dexpace::Body.string(text, encoding: ::Encoding::UTF_8)` calls `text.encode(encoding)`, which
  raises `Encoding::UndefinedConversionError` for a `String` whose bytes cannot be represented in the
  target. Verified on 3.4.10: `Dexpace::Body.string("caf\xE9".b)` raises
  `Encoding::UndefinedConversionError: "\xE9" from ASCII-8BIT to UTF-8`. It is exactly a caller
  mistake in an argument, and `HTTP-4`/`SEAM-29`'s whole point is that such a failure names the field
  in one error class.
- `Dexpace::Body.multipart(parts, subtype:)` interpolates `subtype` into `MediaType.parse`, so a
  malformed subtype raises out of phase 1's parser rather than naming `subtype`.

Not fixed in phase 3b, deliberately. The fix at each site is a `rescue` that re-raises as
`Dexpace::InvalidArgumentError` naming the argument, which is three lines — but the two sites are not
the only ones with this shape (phase 1's coercions through `Method.of`, `Status.of`, `Protocol.parse`
and `URL.parse!` each decide the same question, and `URL.parse!` already re-wraps while the others do
not), and a rule about which stdlib exception classes core re-wraps at an argument boundary is a
cross-phase decision one sub-phase should not settle alone. Recording it keeps the question visible
for the phase that owns the answer rather than letting each new factory decide it again.

The narrow reading — that these are not "caller mistakes" because the caller could have encoded the
`String` itself — is available and is why this is an item and not a defect. It is recorded because the
Global Constraints assert the stronger reading, and a constraint that is true of most call sites and
silently false at two is worse than one stated with its exceptions.

next id: OI-12
