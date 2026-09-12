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

### OI-12 — Eighteen RECOV requirements exist only as appendix-C rows, and both the roadmap and `--gaps` send a reader to a chapter that does not carry them

- **Opened:** 2026-09-08, phase 4 segmentation design
- **Status:** open
- **Cites:** RECOV-17, RECOV-18, RECOV-19, RECOV-20, RECOV-21, RECOV-22, RECOV-23, RECOV-24,
  RECOV-25, RECOV-26, RECOV-27, RECOV-28, RECOV-29, RECOV-30, RECOV-31, RECOV-32, RECOV-33, RECOV-34

`docs/product-spec/08-execution-pipelines.md` §8.2 states `RECOV-1` through `RECOV-16` and stops.
Verified 2026-09-08 with a repository-wide grep: **`RECOV-17` through `RECOV-34` appear nowhere in
`docs/product-spec/` outside appendix C** — eighteen of the prefix's thirty-four IDs, and the largest
such cluster found so far.

Two instructions are built on the chapter carrying them, and neither is followable:

- The v1 roadmap's gap paragraph — "Phase 4: `RECOV-17`–`RECOV-31`, read out of
  `docs/product-spec/08-execution-pipelines.md` §8.2 — 15 IDs, the largest cluster in the corpus and
  the one place a phase must plan for reading the specification directly rather than querying it."
- `ruby scripts/knowledge.rb --gaps RECOV`, whose trailing line reads "read these out of
  docs/product-spec/08-execution-pipelines.md". The pointer is derived mechanically from appendix
  C's subsystem cell and is not wrong about the *subsystem*; it is unfollowable as an instruction.

**This is the third instance of one shape, which is why it is worth a third item rather than a note
on the first two.** `OI-1` recorded five `SEAM` IDs in the same position, `OI-2` recorded `IO-6`, and
this records eighteen `RECOV` IDs. At three occurrences across three prefixes the pattern is a
property of appendix C's relationship to the prose chapters — appendix C is the superset, and the
chapters are not obliged to state every row they own — rather than three separate omissions, and any
future fix should be to the derivation (`--gaps` could say "appendix C only" when the chapter does
not carry the ID) rather than to three roadmap sentences.

**Three of the eighteen are not gaps only because the *design* rescued them.** `RECOV-32`,
`RECOV-33` and `RECOV-34` have substantive corpus entries — `pipeline/785eab36`, `pipeline/2e998896`,
`pipeline/7f286969`, `retry-and-resilience/58d2faad`, `retry-and-resilience/c9228a67` — every one of
them role `design`, drawn from `docs/sdk-design-ruby/05-pipeline-architecture.md` and
`/06-retry-redirect-and-authentication.md`. So "the corpus cannot answer" and "the specification
cannot answer" are independent facts here, and `--gaps` measures only the first: its fifteen uncited
IDs understate the eighteen a reader cannot find in a chapter.

**What phase 4 did instead.** `docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md` read
all eighteen out of appendix C directly and dispositioned each: `RECOV-32` and `RECOV-33` are the two
header-stamping steps design §5.1 ships in core and stay phase 4's; the other sixteen are the
recovery-stack retry engine and are deferred to phase 6 as `DEF-35` (`RECOV-31` was already `DEF-5`).
The reading budget the roadmap asks a phase to plan for therefore largely transfers with the work,
and phase 6 inherits it alongside `docs/product-spec/09-retry-and-resilience.md`, which states the
same rules in prose under `RETRY` IDs it *can* read.

### OI-13 — `Fiber#storage=` is the only write side `ASYNC-9`/`ASYNC-11` can use, and it warns on every supported Ruby and behaves differently on the floor

- **Opened:** 2026-09-08, phase 4 segmentation design review
- **Status:** open
- **Cites:** ASYNC-9, ASYNC-10, ASYNC-11, ASYNC-12, OBS-10, OBS-23, OBS-24, CFG-15, NFR-7

Design §8.1 fixes the diagnostic-context carrier as fiber storage and fixes the adapter's shape with
it: `dexpace-async-thread` "saves the worker's prior storage, installs the captured snapshot for the
work's duration and restores it in an `ensure` (**ASYNC-9**)", with an absent context "capturing as
empty and reinstating as a clear rather than a raise (**ASYNC-11**)". `Fiber[]=` writes one key;
saving and restoring a *whole* map — which is what save/install/restore means — needs `Fiber#storage=`,
and `Fiber.new(storage:)` cannot serve, because a pooled worker's fiber already exists when the task
arrives. Two facts about that setter, verified 2026-09-08 on 3.2.11, 3.4.10 and 4.0.6 via
`mise exec ruby@<v>`:

- **It warns on every call, on all three, and at the default warning level.**
  `Fiber#storage= is experimental and may be removed in the future!` is emitted **per call**, not once
  per process (two calls, two warnings, verified), and it appears with plain `ruby` as well as
  `ruby -w` — it is not gated behind verbose mode. This repository's gate set runs the real suite
  under `ruby -w` with **warnings failing the build**
  (`docs/sdk-design-ruby/09-toolchain-and-quality-gates.md` §9.2), so a per-task save/restore emits
  one warning per task and fails that gate. The warning's category is `:experimental`, so
  `Warning[:experimental] = false` silences it — but that is a **process-global** flag, and a library
  setting one on its host is the same imposition the port already refuses for `Regexp.timeout`
  (`CLAUDE.md`, design §4/§6.3), so it is not a fix an adapter may reach for unasked. The remaining
  routes are a scoped `Warning.warn` filter around the call or an `NFR-7` waiver carrying its reason;
  which one is right is the deciding phase's call, and neither is free.
- **`Fiber.current.storage = nil` is not uniform across the range.** On 3.2.11 it leaves
  `Fiber.current.storage` as `{}`; on 3.4.10 and 4.0.6 it leaves it as `nil`. `= {}` yields `{}` on
  all three. So the obvious spelling of `ASYNC-11`'s "reinstating an empty context clears the target"
  reads back differently on the floor than on the rest of the matrix, which is exactly the shape of
  bug an unqualified version claim hides.

Neither fact is phase 4's to act on: `CTX`'s store is a `Hash` behind a `Thread::Mutex` and touches
fiber storage nowhere, which is the line
`docs/knowledge/notes/observability.md` now draws. It is recorded here because the phases that *do*
act on it — 5 for `OBS-10`/`OBS-23`/`OBS-24`, 8 for `ASYNC-8`–`ASYNC-12` — will meet the design's
sentence, reach for `Fiber#storage=`, and find a gate in the way; and because "experimental and may
be removed" is a supported-range risk that belongs in a register before an adapter is built on it,
not after. What is **not** claimed here: that fiber storage is the wrong carrier. Read-side
inheritance is uniform and copy-on-write across the whole range, re-verified in the same session and
recorded in that note. Only the write side is in question.

### OI-14 — Four independent cross-reference failures in four documents, and nothing mechanically checks the class

- **Opened:** 2026-09-08, phase 4 segmentation design review
- **Status:** open
- **Cites:** none — this is about the citations themselves, not about a requirement

**The instance that prompted it.** `DEF-32`'s *Why* cites
`docs/sdk-design-ruby/03-seam-and-adapter-mapping.md` §3.7. **That file has never existed.** The
chapter is `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md`, and its §3.7 is the right
section, so the pointer is one filename wrong and otherwise correct — which is exactly why it
survived phase 2's own review, phase 3's register sweep and phase 4's. `DEF-32` is committed phase-2
work and the register is append-only apart from `Status`/`Resolution`, so **the row is not edited**;
this item is where the finding lives.

**The pattern, which is the actual item.** This is the fourth of one shape, in four documents, by
four authors, found by four different readers:

| Item | The cross-reference | How it fails |
|---|---|---|
| `OI-1` | the gap pointer for five `SEAM` IDs | names a chapter that does not carry them |
| `OI-2` | every statement of `IO-6`'s content | cites the retired `SEAM-3`; the ID lives only in appendix C |
| `OI-12` | the roadmap's gap paragraph, and `--gaps`'s own trailing line, for eighteen `RECOV` IDs | pointer unfollowable, characterisation wrong twice |
| this row | `DEF-32`'s design-chapter citation | filename that was never right |

They are not four careless authors. They are one failure mode: **a cross-reference nobody
mechanically checks.** Every one is a claim of the form "X is stated at Y" where Y is a repository
path, a chapter number, or a requirement-ID-to-chapter mapping — all three of them derivable, none of
them derived. Prose is reviewed for whether it is *true*; a pointer is reviewed for whether it *looks*
right, and all four look right.

**What would resolve it, stated so someone can decide rather than so this row can decide.** A
link-and-citation check over `docs/` that (a) resolves every `docs/sdk-design-ruby/NN-*.md` and
`docs/product-spec/NN-*.md` filename appearing in prose against the tree, and (b) checks
requirement-ID-to-chapter claims — "`IO-6`, read out of `docs/product-spec/05-i-o-contracts.md`" —
against where the ID actually appears. `.claude/skills/housekeeping/probe.rb` is its natural home: it
already carries `links` and `citations` checks, and it already derives each repository fact **once,
from the repository** rather than checking one document against another, which is precisely the
discipline all four of these needed and did not get. The shape of the gap is narrow and worth naming:
`links` resolves only Markdown link syntax — `[text](target)` and reference links — so a path written
as prose in backticks, which is how every one of these four was written, is never resolved by
anything; and `citations` resolves only the `OI-<n>`/`DEF-<n>` register namespace. Extending those two
to backticked repository paths and to ID-to-chapter claims is a smaller step than building a new tool,
and it is the step that would have caught all four.

**Worth stating plainly: the probe passes on all four.** `ruby .claude/skills/housekeeping/probe.rb`
reports "no drift found" with `DEF-32`'s dead filename in the tree, and reported it while `OI-1`,
`OI-2` and `OI-12`'s pointers were live too. That is not a probe defect — it never claimed this
ground — but it is why four instances accumulated before anyone counted them, and it is the reason
this row argues for the check rather than for a fifth manual correction.

### OI-15 — "the monotonic counter" names two unrelated objects, and the phase-4 segmentation design's exclusions table assigns the phrase to phase 5

- **Opened:** 2026-09-08, phase 4a design
- **Status:** open
- **Cites:** CTX-4, CTX-6, CFG-15, CFG-16, RETRY-26

**The collision.** `CTX-4` requires that each call's store key append "a process-wide, monotonically
increasing counter" to a `traceId:spanId` rendering, and `CTX-6` requires that counter to be "a single
process-wide monotone counter shared by all three flavors' default-key generation". That is an
**integer sequence**: it has no unit, no relation to time, no wall clock behind it, and Ruby's
arbitrary-precision `Integer` means it cannot even wrap. It is phase 4's, and phase 4a builds it.

`CFG-16` requires that the time seam's "monotonic counter must be non-decreasing and used only for
measuring elapsed durations between its own readings (its absolute value is not meaningful)". That is
an **elapsed-time clock**. It is phase 5's, deferred by `DEF-28`, and `RETRY-26`'s cancellable wait is
its first caller.

**Why this is a finding and not a coincidence of vocabulary.**
`docs/work/mvp/phase4/2026-09-08-phase4-segmentation-design.md`'s *Exclusions* table carries the row
"`CFG-15`–`CFG-21` — the clock, **the monotonic counter**, the interruptible sleep,
`future.value(deadline:)` — 5 (`DEF-28`)". The row is correct about `CFG-16` and it is the only place a
phase-4 reader is told where "the monotonic counter" lives — so a `4a` designer reading the charter's
own scope table before reading `CTX-4` learns that the counter they need is somebody else's. The same
document's `4a` scope paragraph says the opposite two pages earlier ("the process-wide monotonic
counter `CTX-4`'s key appends"), so the document is internally consistent only to a reader who has read
both. `DEF-28`'s own text ("the clock behind them") has the same shape.

**What is not claimed.** Neither document is wrong. Each sentence is true of the object it is about.
The failure is that one phrase names two objects in one phase's scope, and nothing distinguishes them
at the point of use.

**Why it is filed rather than fixed.** The phase-4 segmentation design is committed and adversarially
reviewed, and a finding against a committed phase belongs in a register rather than in an edit. Phase
4a's own design states the distinction explicitly under *Cross-cutting constraints* and in its
*Out of scope* table, which is the mitigation available to it.

**Its relation to `OI-14`.** This is the same family — a cross-reference that reads correctly and
resolves to the wrong thing, with nothing mechanically checking it — and it is the variant `OI-14`'s
proposed link-and-citation check would **not** catch. That check resolves repository paths and
requirement-ID-to-chapter claims; both are derivable. A phrase that is ambiguous between two
requirement IDs is not a broken pointer at all, and no tool this repository could reasonably build
would find it. What would: naming the object rather than its adjective. `CTX-4`'s is a **call-sequence
counter** and `CFG-16`'s is an **elapsed-time counter**, and a document that writes either full phrase
cannot be misread.

### OI-16 — `[overridden by notes/…]` prints for every key a note backticks, including rules it adopts

- **Opened:** 2026-09-08, phase 4a design review
- **Status:** open
- **Cites:** NFR-4

**The mechanism.** `Corpus#link_overrides` in `scripts/knowledge.rb` scans each note's whole text for
`` `<topic>/<8 hex>` `` — `CITED_KEY`, a bare backticked-key regexp — and, for every match, appends the
note's location to the harvested entry's `overridden_by`. There is no other signal: the CLI has one
relation, and it renders it as `[overridden by notes/…]` on the harvested entry's location line in every
query result. A note therefore cannot cite a harvested rule **in support** of what it says without
simultaneously marking that rule as overruled.

**What it costs, measured rather than asserted.** 77 of the 2 166 harvested entries currently carry the
marker. At least six of those are rules the naming note states in so many words that it is *not*
weakening:

- `notes/concurrency-and-async.md:8` marks `concurrency-and-async/c0fab747`, `/ee54cb68` and `/f261a143`,
  in the sentence "The rules in this chapter that the substitution does **not** weaken are adopted
  verbatim and are what make the shape safe".
- `notes/execution-context.md:8` marks `execution-context/d6a723dd` and, again, `c0fab747`, under "The
  rules the substitution does **not** weaken and which are adopted verbatim".
- `notes/execution-context.md:10` marks `api-design/b0e18938` and `module-organization/64e84d64`, both
  cited as rules the decision *rests on*. `b0e18938` is the minimal-public-surface rule that phase 2's
  `P2-11`, phase 3a's `P3-8` and phase 4a's `P4-2` and `P4-11` all stand on; it now reads, in every query
  that returns it, as having been overridden by a note about execution contexts.

`io-and-byte-streams/d2b47c89` shows a second symptom: a key backticked twice in one note is listed twice
in that entry's marker.

**Why this is a finding and not a style complaint.** `CLAUDE.md` and the `knowledge-lookup` skill both
describe the marker as the mechanism by which a correction is made visible — "a backticked
`<topic>/<8 hex>` key naming the harvested rule it overrides, which makes that rule print
`[overridden by notes/…]` in every query result". The phase-start query pair exists so a plan does not
assume as settled something an implementation found otherwise; a marker that fires on citation as well as
on correction inverts that for the cited rule, and it does so silently. The rules most likely to be cited
in support are the general, cross-cutting ones — minimal surface, smallest critical section, full nesting
form — which are exactly the rules a false "overridden" reading is most expensive on.

**Why it is filed rather than fixed.** The fix is a tool or convention change, not an edit to any one
document. Rewriting phase 4a's note alone to avoid backticking the two rules it adopts would remove the
citation the corpus convention asks for, and would leave `notes/concurrency-and-async.md`, which is
committed, doing the same thing — an inconsistency without a repair. Three shapes are available and the choice is not this review's:
a second relation in the note format (a `## Adopts` heading, or a `cites:` marker the regexp skips);
scoping `CITED_KEY` to the entry's first sentence, where a supersede names its target; or rendering the
two differently (`[answered by …]` versus `[cited by …]`) so a reader can tell them apart. Whichever is
taken, `ruby scripts/verify_knowledge_structure.rb` and `ruby scripts/knowledge_drift.rb` both walk the
same regexp and would need the same change.

**Its relation to `OI-14` and `OI-15`.** Both of those are cross-references that resolve to the wrong
thing with nothing checking them. This one is the opposite failure: a cross-reference that resolves
correctly and is then *reported* as something it is not, by a tool that is working exactly as written.

### OI-17 — the surgical pipeline edits are keyed by step type, and every lambda step has the same type

- **Opened:** 2026-09-08, phase 4c's design
- **Status:** open
- **Cites:** PIPE-18, PIPE-19, PIPE-20, PIPE-21

`PIPE-18`, `PIPE-19`, `PIPE-20` and `PIPE-21` are four MUSTs whose subject is an **anchor type**:
insert-after and insert-before place a step "immediately after/before the FIRST existing step that is an
instance of a given anchor type"; replace "swap[s] the FIRST existing instance of the anchor type";
remove "MUST delete EVERY step that is an instance of the given type"; and an edit whose anchor type has
no instance "MUST fail with an error identifying the missing type".

`docs/sdk-design-ruby/05-pipeline-architecture.md` §5.1 separately requires that "a step is any object
responding to `#call(request, cursor)` — again `#call`, so a `lambda` is a step and Ruby's middleware
muscle memory transfers". **Every lambda's class is `Proc`** — verified 2026-09-08 on 3.2.11, 3.4.10 and
4.0.6: `->(r, c) {}.class` is `Proc` and `#instance_of?(Proc)` is `true`, for every lambda.

The two requirements are individually satisfiable and jointly reach less far than either implies. In a
pipeline holding two lambda steps, `remove(Proc)` deletes **both** — which is exactly `PIPE-20`'s stated
semantics and is almost certainly not what the caller meant — and `insert_after(Proc, step)` anchors on
whichever lambda the flattening happens to place first, which is well-defined and arbitrary. There is no
spelling of the four edits that addresses one lambda and not the other, because the API's addressing
key is the type and the type is shared. Neither the specification nor the design notices it: `PIPE-18`
was written against a host where a step is a class.

**Why it is filed rather than only documented.** Phase 4c's mitigation is a YARD sentence on each
surgical edit saying that a step intended as an anchor should be a named class, and that is the right
mitigation for the phase — but a caller who meets the case has no recourse in the API, and phase 9's
conformance pass will exercise the four edits against class-typed steps and would never see it. Three
repairs are available and the choice is not this design's: an optional caller-supplied name or tag on
`Entry` that the edits may anchor on instead of a type; rejecting `Proc` as an anchor type outright,
which would make `PIPE-20`'s "delete EVERY instance" unreachable for lambdas rather than surprising; or
leaving it and recording the limit in `docs/sdk-documentation/`. The first is the only one that makes
the four MUSTs reach a lambda step at all.

**Its relation to `OI-1`, `OI-2` and `OI-12`.** Those three are requirements that cannot be *followed*
because a pointer does not resolve. This one is a requirement that can be followed and then does less
than it says, for a case a second requirement makes legal — so it is a conjunction failure rather than a
missing chapter, and it is the first of that shape in the register.

### OI-18 — `Transport.async_over` accepts an *async* transport silently and yields a future of a future; the mirror direction is loud

- **Opened:** 2026-09-08, phase 4c's review
- **Status:** open
- **Cites:** SEAM-18, SEAM-2, PIPE-26, PIPE-33, PIPE-34, ASYNC-2

Phase 2 gave both transport seams **one** conformance predicate. `Dexpace::Transport.conforms?` and
`Dexpace::AsyncTransport.conforms?` are each `Dexpace::Registry.callable?(object, arity: 3)`, and phase 2 recorded
the consequence honestly: the predicate reads `#parameters` and the two seams differ only in **return type**,
which `#parameters` cannot see. What phase 2 did not have, and phase 4c does, is a pair of core-owned classes with
identical `#call(request, options = …, cancellation = …)` shapes and different return types sitting in the same
namespace — `Dexpace::Pipeline` and `Dexpace::AsyncPipeline` — plus a design that tells callers to reach the
`PIPE-33`/`PIPE-34` bridges by composing exactly those two classes with exactly those two bridges (phase 4c's
R13, deviation P4-35). That makes the mistake cheap to make and it is not symmetric:

- **`AsyncTransport.sync_over(sync_pipeline)` is loud.** `Dexpace::Bridge::SyncOver#call` checks
  `future.is_a?(Dexpace::Async::Future)` and raises `Dexpace::SeamError` naming the class it got. The caller
  learns at the first send.
- **`Transport.async_over(async_pipeline, executor:)` is silent, at every layer and for ever.**
  `Bridge::AsyncOver#deliver` posts the send and hands whatever comes back to `Completer#fulfil(response)`;
  `fulfil` passes it to `Settlement.success(response)`, whose only validation is "exactly one of response or
  error" — verified by reading phase 2's plan, tasks 5, 9 and 11. So the outer `Future#value` returns the **inner
  `Future`**, no exception is raised anywhere, and the caller meets a `NoMethodError` on `#status` or `#body` at
  whatever distance from the mistake their code happens to put it. The response is also never closed, because
  nothing on that path knows there is one inside.

**Why it is filed rather than fixed here.** The predicate, both bridges, `Completer#fulfil` and `Settlement` are
all phase 2's and are committed and reviewed; phase 4c neither introduces nor widens the gap, and its own
disposition — shipping no bridge at all — is what a review would ask for. Three repairs are available and the
choice is phase 8's or a phase-2 amendment's, not phase 4c's: type-check the delivered value in
`Bridge::AsyncOver#deliver` the way `SyncOver#call` already type-checks the returned future, which makes the two
bridges symmetric and costs one `is_a?`; refuse a `Dexpace::Async::Future` return at `async_over` construction
time by test-calling nothing and instead having `AsyncPipeline` (and future async adapters) answer a marker
predicate the sync seam checks for absence of; or leave it and document the trap on both bridges. The first is the
narrowest and is the one this item recommends.

**Its relation to `OI-17`.** Both are conjunction failures rather than unresolvable pointers — a mechanism that is
correct about the thing it was designed for and silent about a case a second decision made reachable. `OI-17` is
the API's addressing key; this one is the seam's conformance key. Neither is caught by any gate in the phase-0
set, because both are type distinctions Ruby does not carry at the point they are made.

### OI-19 — the runtime surface snapshot does not hold a `Data`-generated reader for any type using this repository's `class X < Data.define(...)` convention

- **Opened:** 2026-09-08, phase 4a's plan
- **Status:** open
- **Cites:** NFR-4, NFR-3, P4-11, P1-4

`CLAUDE.md`'s Public API Surface section, and design deviation `P4-11` restating it for this
phase, both say the same thing: "`Data.define`'s generated readers … are all invisible to
[RBS]. So the RBS diff is paired with a **runtime surface snapshot** … Each catches what the other
cannot see." **Verified directly against phase 0's own walker
(`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates.md`'s `Surface.walk`, which
calls `mod.public_instance_methods(false)`), on 3.2.11, 3.4.10 and 4.0.6: it does not.**
`public_instance_methods(false)` returns only methods defined directly on the class named, and for
every value type in this repository — `class Status < Data.define(:code)` in phase 1 and every one
after it, this phase's `DispatchContext`, `RequestContext`, `ExchangeContext`, `Bundle` and
`TraceIdFlavour` included — the `Data`-generated readers are defined on the **anonymous class
`Data.define` returns**, which is that type's `superclass`, not on the type itself:

```
Dexpace::DispatchContext.instance_methods(false)             # => [:promote_to_request]
Dexpace::DispatchContext.superclass.instance_methods(false)  # => [:bundle, :call_key, :store]
```

on all three interpreters. This is specific to the **subclassing** idiom this SDK uses throughout
(`P1-4`'s construction pattern): `Foo = Data.define(:a, :b) do; def extra; end; end` — assigning
the `Data.define` return directly to a constant, with a block, instead of subclassing it — gives
`Foo.instance_methods(false) == [:a, :b, :extra]` and `Foo.superclass == Data`, on all three, so
the gap is a consequence of the chosen convention and not of `Data.define` or of any interpreter.

**Consequence for `NFR-4`.** A `Data`-generated reader can be renamed or removed without the
runtime snapshot noticing at all — the RBS diff still catches it, because phase 1 already writes
every reader out explicitly in `sig/` for exactly the reason `P1-4`/`CLAUDE.md` state — so "each
catches what the other cannot see" holds for what `sig_diff` alone would miss, but the runtime
snapshot's contribution for a `Data`-generated reader specifically is nothing, not a second gate.
`#==`/`#eql?`/`#hash`/`#to_h`/`#with` — the methods `Data` itself defines, one level further up —
are absent from every `Data`-based type's row in every gem's snapshot for the identical reason, and
always have been since phase 1's first regeneration; this item is the first place the absence was
checked and confirmed rather than assumed benign.

**Why filed rather than fixed here.** `tools/surface.rb` (phase 0, Task 14) is committed and
reviewed, and every `Data`-based type in every gem is affected identically — this is a phase-0-owned
tool and a repository-wide convention question, not something a sub-phase changes as a side effect
of its own plan. Two repairs are available and the choice belongs to phase 0's owner or a review:
walk `mod.superclass.instance_methods(false)` too when `mod.superclass` is itself a `Data.define`
return value (narrow, but couples the walker to a naming heuristic for an anonymous class); or
accept the split as-is and amend `CLAUDE.md`'s and `P1-4`'s stated rationale to say the runtime
snapshot's role is method definitions only, never member accessors — which is what the RBS diff
already alone provides. Neither is taken here.

### OI-20 — the drain's second discriminating measurement is not reachable from `ContextStore`'s public surface, and `Metrics/ParameterLists` cannot be satisfied by a keywords-everywhere API

- **Opened:** 2026-09-08, phase 4a's plan review
- **Status:** open
- **Cites:** CTX-11, CTX-12, XCUT-14, NFR-7, OI-6

Two findings, filed together because each is a place where a rule this repository already holds
cannot be enforced by the mechanism the documents assume, and neither is a sub-phase's to settle.

**The drain measurement.** `docs/knowledge/notes/execution-context.md` and phase 4a's design both
record that the aggregate drain-iteration count (`8000 − 64 = 7936`) is vacuous — it reproduces
under a split-lock drain and under a single `if` with no loop — and both name the two measurements
that do discriminate: "the maximum iterations in any one call" and "the maximum size ever
observed". Phase 4a's plan ships the first, in its observable form (from a store at `cap`, every
further insert evicts exactly one occupant and the size is never observed above `cap`); it does
**not** ship the second, because it cannot. `Dexpace::ContextStore#size` delegates to
`BoundedMap#size`, which takes the same `Thread::Mutex` as the insert — so a reader can never
observe the transient `cap + 1`. Measured: a split-lock `BoundedMap`, acquiring the mutex
separately for the insert and for the drain, sampled by four concurrent `#size` readers across
64 000 inserts from 32 threads at `cap` 8, reported a maximum of exactly 8 on six consecutive
runs, identical to six runs of the shipped one-`synchronize` form. The note's own `9`-at-`cap`-8
observation was taken from **inside** the prototype's hash, which no test written against the
public surface can reach.

What that leaves: the one-`synchronize` insert-and-drain — on which `CTX-7`'s "registered,
overwritten, and removed concurrently without external locking" and `CTX-8`'s "deterministically
admit exactly one winner" both rest — is held by the source, by `BoundedMap`'s own comment and by
the corpus note, and by **no test**. Narrowing the lock's scope would be invisible to the suite on
CRuby, which is the same shape `DEF-33` records for the non-CRuby matrix row. What would resolve
it: either an internal probe seam on `BoundedMap` that a test can read without the mutex (a
`private_constant`'s test surface, which phase 2 declined for `Dexpace::Hooks` and which would
need the same argument made deliberately), or a non-CRuby matrix row on which an unsynchronised
read-modify-write is observable. Neither belongs to 4a.

**`Metrics/ParameterLists`.** RuboCop counts keyword arguments by default
(`CountKeywordArgs: true`) and `api-design/1d9e6e0b` makes every public parameter a keyword, so the
cop's `Max: 4` — which phase 0 set and every phase plan's Global Constraints restate — is
unsatisfiable for any model with more than four members. Phase 4a is the first phase where that
bites at scale: seven methods trip it (`Bundle.build` and `#initialize` at 8,
`ExchangeContext`'s pair at 6, `RequestContext`'s pair at 5, `NO_TRACER_FACTORY#tracer` at 5), all
carrying exactly the member set the design fixes. 4a pays it with named inline disables, which is
phase 0's own convention for a directive; the alternative — one reviewed `CountKeywordArgs: false`
line — is a `.rubocop.yml` diff and belongs with `OI-6`, whose resolution paragraph already says a
config change is not a sub-phase's to make. Recorded here so that whoever closes `OI-6` has the
measured count rather than an impression.

**Resolution:** *(open)*

### OI-21 — `CFG-35` and `XCUT-5` define the same status classifier, and `DEF-38` assigns it to phase 6 without accounting for `CFG-35` being a phase-5 ID

- **Opened:** 2026-09-09, phase 5 segmentation design
- **Status:** open
- **Cites:** CFG-35, XCUT-5, XCUT-6, XCUT-7, RETRY-1, DEF-38, OI-15

`XCUT-5` (MUST): the baked retryability flag "MUST be computed ONCE at construction from a **SINGLE
shared status classifier** … That classifier MUST treat 408, 429, and all 5xx EXCEPT 501 and 505 as
retryable." `CFG-35` (SHOULD): "A shared retryability classifier SHOULD exist and treat these HTTP
status codes as retryable: 408, 429, and all 5xx EXCEPT 501 and 505 … Where the classifier is
implemented, this exact status-code set is a hard contract so exception construction and the retry
policy agree." Same set, same object, two IDs in two phases.

`DEF-38`, filed by phase 4b and committed, says that classifier is "`RETRY-1`'s, the same object
`XCUT-6`'s open-capability path and `XCUT-7`'s configurable retryable-status set are defined
against, **all three of them phase 6's**" — correct about `XCUT-6` and `XCUT-7`, and silent about
`CFG-35`, whose home is phase 5 and whose text is where the built-in set is stated at requirement
level. Nothing is wrong in either document; the failure is that one object is named by two
requirements in two phases with no cross-reference at either end. It is the `OI-15` shape — a
sentence that reads correctly and resolves to the wrong phase — and, like `OI-15`, it is filed
rather than fixed because the register row is committed and adversarially reviewed.

`XCUT-5`'s own closing NOTE is what a reader must not lose: the baked flag is **not** what the retry
step consults, so the built-in classifier (`CFG-35`/`XCUT-5`) and the configurable set (`XCUT-7`)
are legitimately two objects and only the first is in question here.

What would resolve it: phase 5a's `R1` decides whether the classifier lands in phase 5, defers to
phase 6 beside `DEF-38`, or splits status half from throwable half — and whichever it picks, both
ends gain the cross-reference this row records as missing.

**Resolution:** *(open)*

### OI-22 — `CFG-20`'s cancel-with-interrupt clause is `ASYNC-3`'s under a second ID, is unsatisfiable under §8.3, and no register row cites `CFG-20`

- **Opened:** 2026-09-09, phase 5 segmentation design
- **Status:** open
- **Cites:** CFG-20, ASYNC-3, ASYNC-4, PIPE-33, DEF-18, DEF-31, SEAM-25

Design §10.5 names `ASYNC-3`, `ASYNC-4` and `PIPE-33` and stops. `DEF-18` cites `ASYNC-3` and
`PIPE-33`. §12's `CFG` row says `CFG-20` is "reshaped as the pivot", which does not say a clause is
unmet. §10 item 4 lists `CFG-20` among the IDs it touches but argues the mechanism substitution
rather than the gap. `docs/first-release.md` carries no line. So a phase-5 checklist row for
`CFG-20` has three citations available and none of them states what is missing.

The disposition is not in doubt — `CFG-20` is a SHOULD, three of its four clauses are met, and the
fourth is the same prohibition §10.5 already settles, so **the port gains no fourth unsatisfied
MUST**. But the roadmap's one-row-per-ID convention exists to stop a ✅ or a ⏳ with an unstated
missing clause, which is exactly what phase 2 recorded for `SEAM-25` when it filed `DEF-31`. Filed
so the row phase 5a writes has something true to cite. The parallel worth reading beside it is
§11.20's `RECOV-31`/`RETRY-38` — "the same feature under two IDs" — and the phase-4 treatment of it.

What would resolve it: a citation that names the unmet clause. Phase 5a's `R7` decides the form —
⏳ against `DEF-18` with a note that the row does not cite `CFG-20`, ✅-with-clauses naming the three
that are met, or a partial marker of its own.

**Resolution:** *(open)*

### OI-23 — the housekeeping probe's `citations` check cannot see a backticked register ID, which is the form this repository writes 92% of them in

- **Opened:** 2026-09-09, phase 5 segmentation design
- **Status:** open
- **Cites:** none

`Citations#check_file` in `.claude/skills/housekeeping/probe.rb` scans `Prose.unfenced(...)`, and
`unfenced` blanks inline code spans as well as fenced and indented blocks, "so a link or a citation
ID that appears only as an EXAMPLE, inside code, is not read as an actual link or citation." That
reasoning is sound for a link and wrong for a register ID here, because `CLAUDE.md`'s own
requirement-ID convention backticks every ID and every document follows it.

Measured across the tracked `docs/`, `scripts/` and `.claude/` trees on 2026-09-09, excluding the
two register files and the skill's own test fixtures: **996 backticked `OI-`/`DEF-` mentions against
83 bare ones**, so the check inspects about one citation in thirteen. Reproduced directly: a scratch
file under `docs/work/` naming two undefined open-item IDs, one wrapped in backticks and one bare,
produces exactly one finding — the bare one.

The immediate consequence was the phase 5 segmentation design itself, which cited `OI-21`, `OI-22`
and this row before any of them existed, in the repository's normal backticked form, while the check
that exists to catch precisely that returned "no drift found". A human filing those rows had no
mechanical reminder that they were still unfiled, which is the failure mode the check was built for.

This is the `OI-14` and `OI-16` family — a mechanism that reports clean over a set it never looked
at. Filed rather than fixed because the fix is a judgement about the check (blank inline code for
links but not for register IDs? scan `asserted` rather than `unfenced`? both, with the example case
handled by an explicit ignore marker?) and belongs with whoever owns the skill.

**Resolution:** *(open)*

### OI-24 — the audit group for `CFG` returns 36 of 38 IDs while `--prefix-info` reports 38 of 38

- **Opened:** 2026-09-09, phase 5a (Configuration and the Clock) design
- **Status:** open
- **Cites:** CFG-14, CFG-29

The `knowledge-lookup` skill's tenth audit-group row — *Observability, configuration and
redaction*, added by the phase-5 segmentation design for exactly this material — is
`--topic observability,configuration,redaction-and-security --section rules --brief` **and**
`--prefix CFG,OBS --section rules --brief`. Running the second half returns 37 entries covering
**36 distinct `CFG` IDs**. `CFG-14` and `CFG-29` are absent, because the corpus files both under the
`Reference` section rather than `Rules`: `configuration/8b79358e` (`CFG-14`, the well-known key
constants) and `configuration/60b0e938` (`CFG-29`, RFC 1123 formatting), both sourced from
`docs/product-spec/16-configuration.md`.

Meanwhile `--prefix-info CFG` reports "38 of 38 IDs have a substantive entry, 0 are roll-up only, 0
are uncited" and `--gaps CFG` reports nothing. So a designer who runs the skill's own audit-group
row and counts what comes back reads 36 rules, is told separately that there are 38, and has no
signal that the two numbers are about different things. Both missing IDs are load-bearing in phase
5a and were read from chapter 16 and appendix C instead.

Checked mechanically on 2026-09-09. The `OBS` half of the same audit group loses none of its 40, so
this is not a general property of `--section rules` but a per-ID filing decision that happens to
fall on two `CFG` IDs — which is worse than a systematic gap, because comparing the two halves of
one group gives no hint of it.

This is the `OI-14` and `OI-16` family — a mechanism that reports clean over a set it never looked
at. Filed rather than fixed because the fix is a judgement about the tool or the harvest (should
`--section rules` fall back to `Reference` for an ID with no `Rules` entry? should `--prefix-info`
report the per-section split? should the two entries be re-harvested as rules?) and belongs with
whoever owns the corpus.

What would resolve it: either of those tool changes, or a documented reading step in the skill. The
mitigation available today is one line and phase 5a's design states it for the next phase to copy —
run `--prefix <P> --section rules` and diff the IDs it returns against the prefix's canonical range,
rather than trusting the entry count.

**Resolution:** *(open)*

### OI-25 — design §8.1 names `Event#tag(key, value)` and no requirement in chapter 15 does

- **Opened:** 2026-09-09, phase 5b (logging facade and redaction) design
- **Status:** open
- **Cites:** OBS-4, OBS-5, OBS-8, NFR-4

`docs/sdk-design-ruby/08-instrumentation-and-configuration.md` §8.1 fixes the event object's surface in
a code block: `#field(key, value)   #tag(key, value)   #event(name)   #cause(error)   #emit`. Four of
the five are traceable to a requirement — `#field` to `OBS-3`, `#event` to `OBS-4`, `#cause` to
`OBS-39`, `#emit` to `OBS-8`. **`#tag` is not.** No `OBS` requirement names a tag other than `OBS-4`'s
reserved `event` tag, which the same block gives to `#event(name)`; §8.1's own prose mentions `#tag`
nowhere after the code block; and `OBS-5`'s precedence rule enumerates exactly three contributing
sources — per-event field, global context, folded diagnostic context — so a fourth channel would have
no precedence over any of them and no rule about what happens when it collides.

The one place a reader will think this item missed something is `OBS-8`, which says "Field/tag/cause
accumulation is not required to be thread-safe (single-thread build)". That names a *tag accumulator*
and is the closest chapter 15 comes to `#tag` — but the tag it names is `OBS-4`'s, the single reserved
categorisation tag that `#event(name)` sets and an empty name clears. Nothing in the chapter gives a
tag a **key**, which is what the two-argument `#tag(key, value)` signature is for, and that is the gap.

Why it matters. `NFR-4` locks a public signature at the first release tag, and §8.1 is the document a
phase-5 implementer copies the surface from. Shipping `#tag` gives the SDK a public, YARD-documented,
RBS-signed method with no requirement, no default, no precedence rule and no caller — which is `OI-8`'s
exact shape, filed while phase 3a's `TeeSink#clear_tap` was in the same position. Not shipping it and
being wrong costs nothing before the first release, because adding a method widens.

What phase 5b does. Ships `#field`, `#event`, `#cause` and `#emit`, and not `#tag`, recorded as
deviation `P5-18`.

What would resolve it. Either a reading of `#tag` that names the requirement it serves and its
precedence relative to `OBS-5`'s three sources — in which case phase 5b's plan adds it — or one
corrected line in §8.1 the next time §8 is deliberately amended by a human. It is filed rather than
fixed because §8.1 is frozen and because the alternative reading may exist and the phase-5b design
could not find it.

**Resolution:** *(open)*

### OI-26 — `Dexpace::Instrumentation::Logger` shadows the stdlib `Logger`, and the cop that exists for exactly this cannot carry the name

- **Opened:** 2026-09-09, phase 5b (logging facade and redaction) design
- **Status:** open
- **Cites:** OBS-1, OBS-2, SEAM-1, NFR-1

Design §8.1 calls the facade `Logger` (`Logger#event` performs the enabled check) and phase 5b ships
`Dexpace::Instrumentation::Logger`. Inside `module Dexpace; module Instrumentation; … end; end` — which
is the full nesting form every file in this repository uses — a bare `Logger` resolves to that constant,
and inside an **adapter gem** that has `require "logger"` in its own gemspec and reopens the same
namespace, it still resolves to that constant rather than to `::Logger`. That is the shadowing hazard
`Dexpace/QualifiedCoreConstant` (P2-8, extended by phase 3a as P3-7) exists to catch, and phase 5a met
the same hazard for `ENV` and avoided it by choosing a different name (`Sources::ENVIRONMENT`, `P5-3`).

The name cannot be avoided here the way `ENV` was, and the cop cannot cover it. §8.1 names the facade
`Logger` and the sink duck type is deliberately *the stdlib `Logger` surface as a structural subset*, so
the word is doing real work rather than being a coincidence. And adding `Logger` to the cop's
`SHADOWED` list would flag every legitimate bare `Logger` reference in every adapter gem that declares
the dependency — which is the budget `NFR-2` exists to permit. So the cop is silent on the one name in
the repository where the shadow is deliberate and the consequence is a bundled gem.

Why it matters, concretely. `logger` becomes a bundled gem in Ruby 4.0
(`Gem::BUNDLED_GEMS::SINCE["logger"] == "4.0.0"`, re-verified 2026-09-09), so an author who writes a
bare `Logger` inside the namespace intending the stdlib one gets phase 5b's facade instead — and the
failure is a `NoMethodError` about `#event` or `#enabled?`, which points nowhere near the cause. The
inverse mistake is worse and is what the require-allowlist gate does catch: a `require "logger"` in
core fails the build by name.

What phase 5b does. Keeps the name, records deviation `P5-38`, and mitigates in the two places it can:
the default sink is `NULL_SINK` and not `NullLogger`, so there is only one `Logger`-shaped name in the
namespace; and every reference to either constant in phase 5b's own code is fully qualified.

What would resolve it. A cop that flags a bare `Logger` reference *only inside `module Dexpace`*, which
is a scope `Dexpace/QualifiedCoreConstant` does not currently express; or a decision to rename the
facade, which is a §8.1 amendment. Both are judgements for whoever owns the cop set.

**Resolution:** *(open)*

### OI-27 — the phase-5 segmentation design's 5b scope table states an outcome its own R10 leaves open

- **Opened:** 2026-09-09, phase 5b (logging facade and redaction) design
- **Status:** open
- **Cites:** OBS-19, NFR-4

`docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md`'s 5b scope table dispositions `OBS-19`
as "Partially satisfied — **the verbosity policy and its once-per-name throttle ship**; the emission
site is vacuous for `Net::HTTP`". Its `R10`, two hundred lines later, says the opposite is equally
available: "`5b` decides between shipping the three-mode verbosity policy … **and recording the
requirement vacuous with a cross-reference row for phase 8**. It must not ship a policy with no caller
and no test that exercises it."

Both sentences are defensible and they are not the same sentence. A sub-phase designer who reads the
scope table as binding — which is what a scope table is for, and what the charter's other twenty-six
rows are — implements a policy the charter's own risk section then tells them not to ship. A designer
who reads `R10` first finds an open decision the scope table has already made.

This is the `OI-14` family — a cross-reference failure inside a document rather than between two — and
it is filed rather than fixed because the charter is committed and adversarially reviewed. It is the
second time a phase-5 sub-phase design has had to correct its charter on a point the charter states
twice (phase 5a corrected verified fact 2's inference about `Time.httpdate`), which is what makes it a
register entry rather than a note in one document. The precedent for the sub-phase's reading winning is
phase 4c's correction of the charter's `PIPE-39` row.

What phase 5b does. Follows `R10`, defers `OBS-19` as `DEF-41`, and records the divergence from the
scope table as deviation `P5-32`.

What would resolve it. One corrected cell in the charter's 5b scope table, by a human, the next time
the charter is deliberately amended.

**Resolution:** *(open)*

### OI-28 — a `**` keyword splat allocates a Hash per call even when nothing is passed, and nothing mechanised distinguishes it from the named keyword the styleguide's rule is about

- **Opened:** 2026-09-09, phase 5c (tracing and metrics) design
- **Status:** open
- **Cites:** OBS-1, OBS-25, NFR-7, OI-6

`api-design/1d9e6e0b` requires keyword arguments on every public method and gives its reason as
backward compatibility: "a new keyword with a default is always backward-compatible". That reason is
a property of **named** keywords. Measured on `ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM
[x86_64-linux]`, the only interpreter installed on this machine, 1000 iterations each, `GC` disabled,
in a file carrying `# frozen_string_literal: true`: `def m(x, **attributes)` called as `m(e)` — with
no keyword argument at all — allocates **1002–1005** objects, one `Hash` per call; called as
`m(e, **FROZEN)` it allocates 1003–1004; a wrapper forwarding `**kw` to another `**kw` allocates
2003–2004. The named form `def m(x, attributes: nil)` allocates 2–4 whether or not the keyword is
passed, and a four-keyword signature called with one positional argument allocates 1–2 — the
measurement floor. (Reproduced independently on 2026-09-09 by the pass that reconciled the phase-5b
and phase-5c designs; the run-to-run spread is warm-up, and the per-call cost is 1 or 0 in every run.)

Two requirements make this a correctness question rather than a performance one. `OBS-25` (MUST):
"Selecting a no-op path MUST NOT allocate per call." `OBS-1` (MUST): a disabled log event "MUST
allocate nothing". Both are asserted by allocation count, and both are unsatisfiable for any method
written with a splat — including a method whose callers never pass a keyword.

Nothing catches it. RuboCop has no cop for it, the styleguide rule reads as licensing it, `**opts` is
the spelling `opentelemetry-api` and every Ruby metrics library uses, and the failure is silent: an
implementation with a splat passes every behavioural test and fails only the two allocation
assertions, in two different phases, one of them in a different gem (`DEF-22`). Phase 5c pays it with
`P5-42` — a stated deviation forbidding the splat across its own SPI — which binds one segment and
nothing else.

What would resolve it: a custom cop in the `Dexpace/` family forbidding `**` in a public signature
under `lib/`, in the shape of `Dexpace/NoTimeParse` and `Dexpace/NoThreadInterrupt` — both of which
exist for the same reason, that the idiomatic spelling is the wrong one and a reviewer will not catch
it every time. That is a `.rubocop.yml` and cop-source change and belongs with `OI-6`, whose
resolution paragraph already records that a config change is not a sub-phase's to make.

**Resolution:** *(open)*

### OI-29 — "per-operation tracer factory" names two different objects, and phase 4a bound the bundle's member to the one that is per-library

- **Opened:** 2026-09-09, phase 5c (tracing and metrics) design
- **Status:** open
- **Cites:** CTX-14, CTX-20, OBS-25, OBS-28, OBS-29, DEF-37

`CTX-14` (MUST) requires the correlation bundle to expose "a per-operation tracer factory" and
`CTX-20` (SHOULD) calls it "The per-operation tracer factory carried on the instrumentation bundle …
Its factory method MUST be safe to invoke concurrently from multiple threads, **because operation
starts are not serialized**". `OBS-29` (MUST) says of the *HTTP-tracer* vocabulary in §15.7: "One
tracer instance corresponds 1:1 to a single logical operation lifecycle (**created by the factory per
operation**)." Read together they describe one object created once per operation.

That reading is not available, and the proof needs nothing outside this repository's own normative
text: `OBS-25` (MUST) requires "a no-op Tracer returning a shared no-op Span" and "a no-op HTTP-tracer
/ tracer-factory", and requires that "Selecting a no-op path MUST NOT allocate per call" — so the
no-op factory MUST return the same object every time, which is the opposite of one instance per
operation. Phase 4a's `P4-8` then bound `Bundle#tracer_factory` to `opentelemetry-api`'s
`TracerProvider` shape — `#tracer(name = nil, version = nil)`, positional — for a good and stated
reason: "an application already running OpenTelemetry gets spans with no adapter code" is only true if
`OpenTelemetry.tracer_provider` can be passed straight into `Bundle.build(tracer_factory:)`. A
`TracerProvider` is keyed by instrumentation-library name and version rather than by operation, which
is what makes that pass-through work at all. **That last sentence is an unverified claim about a gem
neither phase 4a nor phase 5c could install** — `opentelemetry-api` is not present on this machine,
re-checked 2026-09-09 — and it is recorded as the motivation for `P4-8`, not as a measured fact; the
argument above does not depend on it.

So the specification's "tracer factory" and this port's `Bundle#tracer_factory` are not the same kind
of object: the bundle's produces **span** tracers (`OBS-21`–`OBS-25`, `Tracer`/`Span`) and is
legitimately shared or cached, while `OBS-29`'s produces **HTTP-tracers** (`OBS-28`'s eleven-method
event vocabulary) and is legitimately per-operation. Nothing is broken today, because phase 5c ships
the HTTP-tracer vocabulary without a factory and without an emitter (`DEF-42`). What is missing is the
cross-reference: `CTX-14`'s member and `OBS-29`'s factory read as one object in four documents —
appendix C, design §8.1, `DEF-37` and phase 4a's `R3` — and phase 6, which wires the vocabulary, is
the first phase that needs them to be two. It is the `OI-15` and `OI-21` shape: a sentence that reads
correctly and resolves to the wrong object.

Phase 5c records the reconciliation it adopted as `P5-43` — `OBS-29`'s 1:1 clause binds stateful
tracers only, so a shared stateless `NO_TRACER` satisfies both MUSTs — which is sound for the no-op
and says nothing about a recording one. Filed rather than fixed because `DEF-37` and phase 4a's
handshake are committed and adversarially reviewed, and because the fix is either a second bundle
member (which roadmap obligation 1 forbids phase 5 from adding) or a separate HTTP-tracer factory
slot, which is phase 6's to shape when it has an emitter.

**Resolution:** *(open)*

### OI-30 — the phase-5 segmentation design assigns `OBS-24` to `5b` in prose and to `5c` in its arithmetic, and both scope tables sum correctly either way

- **Opened:** 2026-09-09, phase 5b/5c reconciliation pass
- **Status:** open
- **Cites:** OBS-24, OBS-10, OBS-23, OI-14, OI-27

`docs/work/mvp/phase5/2026-09-09-phase5-segmentation-design.md` says twice, in prose, that `OBS-24`
is `5b`'s. Line 233: "`OBS-24` goes to `5b`: it is the context snapshot itself, with no span in it."
Risk `R12` repeats it: "`5b` owns `OBS-24` and `5c` owns `OBS-23`, so the decision is stated once and
cited by the other."

Its arithmetic says the opposite. The `5b` ID-set sentence (line 424) reads "exactly `OBS-1`–`OBS-20`
together with `OBS-34`–`OBS-40`: 20 + 7 = **27**", which excludes `OBS-24`; the `5c` Implemented row
(line 445) reads "`OBS-21`–`OBS-31`, `OBS-33`", which includes it.

**Nothing mechanical catches this, and that is the point.** The phase total is 78 under either
reading — 27 + 13 or 28 + 12 — so a checklist built from the charter's own tables reconciles against
the roadmap's count and reports clean while one requirement sits in the wrong segment. Both
sub-phase designs inherited the arithmetic: `5b` listed `OBS-21`–`OBS-27` as out of scope while
owning `OBS-24` in its own `R12` section, and neither document gave `OBS-24` a scope-table row at
all until the reconciliation pass added one.

The prose is right and the arithmetic is wrong: `OBS-24` is the whole-map diagnostic-context
snapshot, it has no span in it, and `OBS-10`'s default fold — which is `5b`'s — is what reads the
keys it captures. The reconciliation pass corrected the sub-phase tables to `5b` = 28 and `5c` = 12,
left the cut and the phase total untouched, and did not edit the charter.

This is the `OI-14` and `OI-27` family: a sentence that reads correctly and resolves to the wrong
place, with no check that would notice. It differs from `OI-27` in being an arithmetic
inconsistency rather than a prose one, which is why it survived a document that was reviewed for
exactly this class of error.

What would resolve it: a correction in place to the charter's two scope tables, stated as a
correction, by whoever owns that document — the sub-phase designs already carry the corrected
disposition and cite this row.

**Resolution:** *(open)*

### OI-31 — the instrumentation step's slot precedence names a context bundle a pipeline step cannot reach

- **Opened:** 2026-09-09, phase 5b/5c plan reconciliation pass
- **Status:** open
- **Cites:** OBS-34, CTX-14, CTX-15, PIPE-11, OBS-25, NFR-4

The reconciled contract between `5b` and `5c` fixes how the instrumentation step resolves its tracer
factory and its meter, in three clauses: **the request context's instrumentation bundle when it is not
`Bundle::NONE`, else the step's constructor keyword, else the constant.** `5c`'s design argues for it from
`CTX-14` ("Each context MUST carry a correlation/instrumentation metadata bundle exposing at minimum … an
active span, and a per-operation tracer factory"), and `5b`'s `P5-33` adopts it.

**The first clause has no implementation path.** Nothing in the shipped surface lets a pipeline step reach a
`RequestContext` or an `Instrumentation::Bundle`:

- Phase 4c's design states outright that "4c does not consume 4a at all", and gives `Dexpace::Pipeline::Cursor`
  the surface `#call`, `#fork`, `#may_fork?`, `#request`, `#options`, `#cancellation`, `#state(stage)` and
  `#spent?` — no context reader among them.
- `Dexpace::Request`'s members are `(:method, :url, :headers, :body)`; `Dexpace::RequestOptions`'s, the other
  thing `Cursor` hands out, are `(:timeout, :max_retries, :tags)`. Neither carries a bundle.
- `PIPE-11` forbids the remaining route: "Per-request mutable state MUST live in the per-call cursor (carried
  and forked by next), never on the step", which rules out reading a context from ambient storage.
- `CTX-11`'s `ContextStore` is not a back door. It is keyed by a per-call key the step does not hold, and
  `CTX-13` explicitly permits the store to evict any entry, "the most-recently inserted included".

**Why it is an open item and not a blocker.** With no bundle reachable the step degrades to its own
`tracer_factory:` / `meter:` keywords and to `Bundle::NONE` — which is exactly `OBS-34`'s and `XCUT-19`(e)'s
*default* configuration: no tracer, no meter, log level `none`. `OBS-34`'s conformance clause ("at none assert
no request/response events but the span still starts/ends and the counter/histogram still record") is
discharged against the step's keyword and does not depend on a context being reachable, so **no phase-5
assertion is weakened and no signature moves.** Adding the clause later is a widening, which
`api-design/1d9e6e0b` makes non-breaking under `NFR-4`.

**What would resolve it: phase 6.** It owns the pillar steps and is the first thing that would either widen
`Cursor` with a context reader or have `Pipeline.standard` (`DEF-39`) thread a bundle in at construction.
Whichever it picks, `bundle_for` in `5b`'s step is the one method that changes. Until then both plans state
the two-clause resolution at the call site rather than describing a three-clause rule they do not implement.

This is not a `DEF-` row: nobody consciously postponed the clause — both designs argued for it in parallel
worktrees and neither checked that a step could reach a context. That is the discovered-after-the-fact shape
`open-items.md` holds, and it is the same family as `OI-14`, `OI-27` and `OI-30`: a sentence that reads
correctly and resolves to something that is not there.

**Decided 2026-09-09, phase 6 segmentation design and `6a`'s design; not yet landed.** Of the two
candidates this row names, **(b) is rejected on the merits**: a bundle threaded at `Pipeline.standard`
construction is *per-pipeline*, while `CTX-14`/`CTX-20`/`OBS-23`'s bundle is *per-operation*, so (b) cannot
carry a per-request span — it merely re-spells clause 2 and leaves clause 1 dead **including for the
preset**. **(a) is adopted, and completed**: this row states only the consumer side, so the resolution is a
read-only per-call accessor on `Dexpace::Pipeline::Cursor` **plus one optional seeding keyword on the
pipeline's call path**, both widenings under `NFR-4` per `api-design/1d9e6e0b`, with `PIPE-11` naming the
cursor as the home and `PIPE-17` giving the fork semantics. `bundle_for` in `5b`'s step gains its first
clause in the same task. **Phase `6a` builds it** (phase 6 segmentation `R13`); if `6b` or `6c` executes
first the task travels with it, and the other two designs consume the reader without re-implementing it.
`6a`'s `DEF-42` emission task does **not** depend on the widening, because `OI-29` establishes that
`OBS-29`'s HTTP-tracer is not `Bundle#tracer_factory` — `6a`'s retry step reads its per-operation tracer
from a factory called with `cursor` itself.

**Resolution:** *(open — the mechanism is decided; the row closes when `6a` lands it)*

### OI-32 — `OBS-29`'s operation-lifecycle triple cannot be emitted from `Stages::LOGGING`, so `DEF-42`'s stated wiring route is unavailable in the phase its pick-up condition names

- **Opened:** 2026-09-09, phase 6 segmentation design and `6a`'s design
- **Status:** open
- **Cites:** OBS-28, OBS-29, PIPE-2, PIPE-37, DEF-42, OI-29

`DEF-42` explains phase 5's decision not to wire `OBS-29`'s operation-lifecycle triple as "it needs a
third slot on `5b`'s instrumentation step, which the phase-5 charter's boundary 15 does not grant" — a
statement about a *slot*, which leaves the *stage* implicit.

Verified 2026-09-09: `5b`'s `Dexpace::Instrumentation::Step` declares `#stage` returning
`Dexpace::Pipeline::Stages::LOGGING` and is installed with no `stage:` argument, and phase 4c rejects with
`Dexpace::PipelineError` any install supplying a different `stage:` for a step that declares one — **so the
step cannot be moved.** `Stages::LOGGING` is order 1100 while `REDIRECT`, `RETRY` and `AUTH` are 200, 500
and 800, so once phase 6's pillars exist a step at `LOGGING` runs once per redirect hop, per retry attempt
and per auth replay. An operation-scoped triple emitted from there fires many times per operation, which
contradicts `OBS-29`'s "One tracer instance corresponds 1:1 to a single logical operation lifecycle".

The site that satisfies the clause is `Stages::PRE_REDIRECT`, order 100, which phase 4c states is "outside
every pillar's fork, so a step there is invoked once" and which `PIPE-37` already reserves for
terminal-response-only steps — and that is a **new step**, not a slot on an existing one. Phase 6a decided
under its `R15` not to ship it: no phase-6 ID justifies the `NFR-4` surface, and `OBS-28`'s "Every event
method SHOULD default to a no-op so adding a new event is a non-breaking change" is what makes wiring the
per-attempt group alone safe.

Nothing is broken today, because nothing emits the triple. This is the `OI-14`/`OI-27`/`OI-30`/`OI-31`
family: a sentence that reads correctly and resolves to something that is not there. `DEF-42`'s row carries
the corresponding correction to its pick-up route.

**Resolution:** *(open)*

### OI-33 — `AUTH-4`–`AUTH-7`'s tier resolution presupposes an `AuthDescriptor` producer that no phase names

- **Opened:** 2026-09-09, phase 6c design
- **Status:** open
- **Cites:** AUTH-1, AUTH-4, AUTH-5, AUTH-6, AUTH-7

The resolver takes a per-call, an operation and a client `AuthDescriptor`, in that preference order, and
`6c` ships it as a correct, tested, stateless pure function. What no phase specifies — not 1 through 5, and
not `AUTH`'s own 38 IDs — is **where a per-call or operation-level `AuthDescriptor` is carried**:
`docs/sdk-design-ruby/` names no field on `Request`, on `RequestOptions`, or on any `Operation` construct for
it, and no `AUTH` requirement asks for one. `AUTH-1`–`AUTH-7` describe the descriptor and the resolver as
data and a function, never a carrier.

`6c` ships the AUTH pillar step accepting an already-resolved credential (or a caller-supplied
`Scheme => credential` table) at construction time, treating the resolver as a standalone library object
whose caller — presumably Operation-building code, outside `AUTH`'s scope entirely — invokes it and threads
the result into the step. If that Operation-level wiring is never built in a later phase, `AUTH-4`–`AUTH-7`'s
resolver ships correct and exercised only by its own unit tests, never by an end-to-end call path.

Same shape as `OI-14`, `OI-27`, `OI-30` and `OI-31`: a sentence that reads correctly and resolves to
something not yet built. Filed as a candidate rather than assumed settled by shipping the resolver alone.

**Resolution:** *(open)*

### OI-34 — `Net::HTTP` has a built-in automatic retry that is on by default, and design §3.2, §11.18 and §12 all record that it has none

- **Opened:** 2026-09-11, phase 8 segmentation design
- **Status:** open
- **Cites:** TRANSPORT-2, TRANSPORT-17, TRANSPORT-18, TRANSPORT-3, RETRY-13, PIPE-2, XCUT-4

Design §3.2 says "The reference transport disables nothing for **TRANSPORT-1**/**TRANSPORT-2** because
`Net::HTTP` follows no redirects and retries nothing on its own — those two requirements are vacuous for
this adapter". §11.18 says "`Net::HTTP` has no resend hook". §12's `TRANSPORT` row lists `TRANSPORT-1`,
`TRANSPORT-2`, `TRANSPORT-8` and `TRANSPORT-18` as "adapter-scoped and vacuous for `Net::HTTP`", and the
MUST-level summary counts `TRANSPORT-2` and `TRANSPORT-18` among the eight MUSTs that hold vacuously.
The redirect half is right; the retry half is false. Verified on `net-http` 0.6.0 under Ruby 3.4.10:
`Net::HTTP#max_retries` **defaults to 1**, and `#transport_request` retries when
`count < max_retries && IDEMPOTENT_METHODS_.include?(req.method)` on `Net::ReadTimeout`, `IOError`,
`EOFError`, `Errno::ECONNRESET`, `Errno::ECONNABORTED`, `Errno::EPIPE`, `Errno::ETIMEDOUT`,
`OpenSSL::SSL::SSLError` and `Timeout::Error`, where `IDEMPOTENT_METHODS_` is
`["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE"]`. The retry re-runs `req.exec`, so it re-writes
the request body; PUT and DELETE are both in the set. Three consequences, none of them cosmetic: a
pipeline that believes it is the single retry authority (`TRANSPORT-2`, `PIPE-2`) is not; a single-use
body could be written twice (`TRANSPORT-17`); and a cancellation delivered by closing the socket under
a blocked read surfaces as `IOError`, which is **on the rescue list**, so the library would swallow and
retry a caller's cancellation (`TRANSPORT-3`). **Amended 2026-09-12, from phase 8a's design (verified
fact 3), which measured the third consequence end to end rather than reading it out of a rescue list:**
against a server whose first connection hangs, with a second thread calling `conn.finish` 250 ms in, the
call **returned `200`** at the default `max_retries` and raised `IOError: stream closed in another
thread` at `0` — so the swallow is observed, not inferred. Two clauses of the same method bound the
hazard without removing it: `rescue Net::OpenTimeout; raise` means a connect timeout is never retried,
and `count = max_retries` inside the `reading_body` block means the window closes once the response head
is read; neither helps the connect-and-head phase, which is where a cancel lands. All three are fixed by one line, `http.max_retries = 0`,
which phase 8a will write — but the three requirements' dispositions in §12 are wrong until it does, and
§12 is frozen. Nothing is broken today because nothing is implemented. What would resolve it: phase 8a
implements the disable and its checklist states the corrected reason; §12's `TRANSPORT` row and the
MUST-level count are corrected the next time §12 is deliberately amended by a human, and
`docs/deviations.md` carries the interim note.

**Resolution:** *(open)*

### OI-35 — design §3.2 prescribes a block-scoped `read_body` construction for `dexpace-transport-net_http` that cannot satisfy the two requirements it says it satisfies "literally"

- **Opened:** 2026-09-11, phase 8 segmentation design
- **Status:** open
- **Cites:** SEAM-11, TRANSPORT-25, TRANSPORT-19, IO-41, BODY-15, HTTP-43

`docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:167-171` reads: "Streaming is preserved end
to end: `dexpace-transport-net_http` issues the request inside `Net::HTTP#request(req) { |res| ... }`
and exposes the response body as a `BufferedSource` over the block-scoped
`Net::HTTPResponse#read_body` stream, so **SEAM-11**'s no-pre-buffering clause and **TRANSPORT-25**'s
'lazily-read stream, not pre-buffered ... closing the SDK response cascades to close the native body and
release the connection' are satisfied **literally**." Measured against a `TCPServer` that writes five
body bytes, sleeps 400 ms and writes five more, on `net-http` 0.6.0 under Ruby 3.4.10: `#request`
without a block returned after **401 ms** with `res.body == "aaaaabbbbb"`; the block form with a block
that does not read returned with the body already buffered, because `Net::HTTPResponse#reading_body`
ends with `self.body` and nils `@socket` in its `ensure`; and `res.read_body` after the block raised
`IOError: Net::HTTPOK#read_body called twice`. So the prescribed construction yields a **fully buffered
body and a dead socket** — `SEAM-11`'s "MUST NOT pre-buffer the body (caller owns read/close)" and
`TRANSPORT-25`'s lazily-read stream both violated by the design's own recipe. The construction that does
work keeps the block open across the return of `#call` (a `Fiber` or a producer thread), which §3.2
does not describe and which brings its own abandonment problem — an abandoned `Fiber` never runs its
`ensure`, so the connection leaks. This is `OI-34`'s species in the same paragraph of the same frozen
section: a design sentence that is false about `Net::HTTP`. This row records that the chapter it is
departing from is wrong rather than merely silent. Nothing is broken today because nothing is
implemented.

**Amended 2026-09-12: phase 8a's `R1` has decided the construction, and the reason is not the one this
row leads with.** The fiber is disqualified by `FiberError: fiber called across threads` — `Fiber#resume`
from a second thread raises, so a fiber pump created on a `dexpace-async-thread` worker inside
`Transport.async_over` could not have its body read on the caller's thread, and `TRANSPORT-29`'s
"confined to the returned response graph" would narrow to "confined to one thread". The abandoned
`ensure` is real and is not what decides it. `8a` ships a per-response producer `Thread` over a
`Thread::SizedQueue(1)` drained through a `#readpartial`-shaped reader, recorded as deviation `P8-1`.
The row's diagnosis of the chapter is unchanged and still correct.

**Resolution:** *(open — the construction is decided (`P8-1`); the row closes when the frozen §3.2
sentence is corrected, which is a human's deliberate amendment)*

### OI-36 — no route exists by which a transport adapter reaches an `HTTPTracer`, so `DEF-42`'s transport-milestone group has a vocabulary and no reachable emitter

- **Opened:** 2026-09-11, phase 8 segmentation design
- **Status:** open
- **Cites:** OBS-28, OBS-29, DEF-42, OI-31, OI-32, SEAM-11, SEAM-16, PIPE-11, NFR-4

Phase 5c shipped `Dexpace::Instrumentation::HTTPTracer` with five transport methods whose argument lists
it fixed — `#request_url_resolved(context, url)`, `#connection_acquired(context, host, port)`,
`#request_sent(context, byte_count)`, `#response_headers_received(context, status, headers)`,
`#response_received(context, byte_count)` — and `DEF-42` records that "the transport-milestone group
follows in phase 8 with the first adapter". `OBS-29` additionally requires "One tracer instance
corresponds 1:1 to a single logical **operation** lifecycle (created by the factory per operation)". The
transport seam is `#call(request, options, cancellation)`; `Request`'s members are
`(:method, :url, :headers, :body)` and `RequestOptions`'s are `(:timeout, :max_retries, :tags)`
(phase 5b's `P5-33` states both), the adapter is in a different gem, `PIPE-11` forbids ambient carriage,
and `NFR-4` locks the seam's three-argument shape. So an adapter can reach a tracer only through its own
constructor — which gives one tracer for the adapter's whole lifetime, not one per operation — or
through a widening of `RequestOptions`, which is a core type and a phase-1 surface. This is `OI-31`'s
shape one layer further out: `OI-31` records that a pipeline **step** cannot reach a context bundle;
this records that a **transport in another gem** cannot reach a per-operation tracer at all. Phase 8a
decides and the decision may be "not wired, and `DEF-42` stays open on this half too", which is what
`OI-32` already records for the operation-lifecycle triple.

**Resolution:** *(open)*

### OI-37 — a cancelled `Async` task raises an `Exception` that is not a `StandardError`, so `Dexpace.close_quietly` and every `rescue` written the obvious way are blind to it

- **Opened:** 2026-09-11, phase 8 segmentation design
- **Status:** open
- **Cites:** SEAM-30, ASYNC-5, ASYNC-6, TRANSPORT-7, TRANSPORT-9, TRANSPORT-22, CFG-21, XCUT-13

Design §3.3's check-after-resume rule says a producer that discovers cancellation while holding a
response "MUST close any response it holds and settle through the failure channel", and §3.7 makes
`Dexpace.close_quietly` the single sanctioned exit for such a close — it "rescues `StandardError` from
`#close`". Verified on `async` 2.45.1 under Ruby 3.4.10: `Async::Stop` **is** `Async::Cancel` —
`lib/async/stop.rb` is `module Async; Stop = Cancel; end` — and `lib/async/cancel.rb:8` declares
`class Cancel < Exception`, so `Async::Stop.equal?(Async::Cancel)` is `true` and
`Async::Cancel.ancestors.take(3)` is `[Async::Cancel, Exception, Object]` — **not a `StandardError`**.
`Async::Task#cancel` raises it inside the task and `#stop` is the backward-compatible alias, so a
`rescue => e` or a `rescue StandardError` in an adapter's send path does not
run, while `task.with_timeout`'s `Async::TimeoutError` **is** a `StandardError` and does. An orphan-close
written as a `rescue` therefore runs on a timeout and not on a cancellation, which is the exact inverse
of what `SEAM-30` and `ASYNC-5` are for, and it is silent. The mechanism is phase 2's and phase 8
neither introduces nor widens the gap; the repair is local — the close belongs in an `ensure`, not a
`rescue` — and `close_quietly`'s own rescue of `StandardError` from `#close` is unaffected and correct.
Because the two names are one class, `rescue Async::Cancel` and `rescue Async::Stop` catch the same
thing; an adapter that writes both has written one. Recorded rather than fixed here because
`close_quietly`'s contract is phase 2's and a second exit would
give the SDK two answers to one question. It is `OI-18`'s species: a core mechanism that is correct about
what it was designed for and silent about a case a later gem made reachable.

**Resolution:** *(open)*
### OI-38 — `dexpace-transport-async_http` cannot declare the repository-wide Ruby 3.2 floor, and a phase-0 gate asserts that it must

- **Opened:** 2026-09-11, phase 8c design
- **Status:** open
- **Cites:** NFR-2, NFR-10, NFR-14, DEF-11, P0-9, P8-36

Phase 0 fixed `VERSIONS` with a single `ruby floor` line of `3.2` and a `ruby matrix` of
`3.2 3.3 3.4 4.0`, and `rake gates:versions` asserts "that every gemspec's `required_ruby_version` equals
`>= ` plus the `ruby floor` line"
(`docs/work/mvp/phase0/2026-09-05-phase0-scaffold-and-quality-gates-design.md:291-303`). Verified on
2026-09-11 against the installed stack: **`async-http` 0.104.0 declares `required_ruby_version >= 3.3`**,
and so do `async` 2.45.1, `async-pool` 0.12.0, `console` 1.37.0, `io-endpoint` 0.18.0, `io-event` 1.22.0,
`io-stream` 0.14.0, `protocol-http` 0.71.0, `protocol-http1` 0.41.0, `protocol-http2` 0.28.0 and
`protocol-url` 0.19.0. From rubygems.org's version index: `async-http 0.94.2` is the last release
allowing `>= 3.2` and `0.95.0` raised it; for `async` the boundary is `2.37.0` / `2.38.0`, both released
2026-03-08. So the two mechanised constraints contradict each other: the gate requires `>= 3.2` and the
only dependency that satisfies `>= 3.2` is eleven minor releases behind the one the phase-8c design
verified every one of its facts against. Phase 8c takes the narrowing as deviation `P8-36` and
`dexpace-core`'s floor does not move. What this row records is the **machinery that has to change and
that no sub-phase owns**: (a) `VERSIONS` gains a per-gem floor key
(`ruby floor dexpace-transport-async_http  3.3`) beside the global one; (b) `gates:versions` reads a
per-gem floor when one exists and the global floor otherwise — a change to a phase-0 gate; (c) the root
`Gemfile`'s `gems/*` glob skips a gem this interpreter's version cannot satisfy, without which
`bundle install` on the 3.2 row fails for the whole workspace; (d) the 3.2 row excludes this one gem
from `test:gems` and `gates:clean_bundle` — the two tasks that install or load it; `gates:gemspec_audit`
and `gates:require_allowlist` only read text and need no exclusion. The exclusion is per-gem and not
per-gate, and it lives in the Ruby-side tasks rather than in the workflow YAML, so
`ci_workflow_test.rb`'s "every listed gate appears in some job" still holds and `ci.yml` is unedited. It also earns a line in
`docs/first-release.md`: the gem a consumer on Ruby 3.2 cannot install, and the composition that still
works for them. Nothing is broken today because nothing is implemented.

**Resolution:** *(open)*

### OI-39 — `TRANSPORT-14`'s malformed-inbound-header-**name** clause is unreachable on `dexpace-transport-async_http`, and §12 records `TRANSPORT-14` as satisfied without qualification

- **Opened:** 2026-09-11, phase 8c design
- **Status:** open
- **Cites:** TRANSPORT-14, XCUT-18, HTTP-17, NFR-8, P8-38

`TRANSPORT-14` (MUST): "Inbound response headers MUST be copied leniently enough that a single malformed
header does not fail the whole response: a control byte in a value, **or a control/non-ASCII byte in a
name**, MUST drop only that header (logged at verbose) while the body and remaining headers are still
delivered." Verified on 2026-09-11 against `protocol-http1` 0.41.0 under Ruby 3.4.10, driving a raw
`TCPServer` that emits `X-B\xE9d: v`: the client raises
`Protocol::HTTP1::BadHeader: Could not parse header: "X-B\xE9d: v"` out of the **read**, so no response
object exists and the adapter has nothing to drop from. The other two clauses hold: an obs-text byte in a
value came back as `["X-Obs", "caf\xE9"]` (both `ASCII-8BIT`) and a control byte in a value came back
intact for the adapter to drop. The charter's fact 6 measured `Net::HTTP` doing the opposite — it
*preserves* a non-ASCII name as a key — so the requirement is satisfiable on one MVP adapter and not on
the other, which is the per-transport scoping §17's own preamble anticipates and which neither §12 nor
§9.3 records for this ID (§9.3 scopes only `TRANSPORT-8` and `TRANSPORT-18` that way). Phase 8c records
it as deviation `P8-38` and the conformance run carries a **named waiver listing `TRANSPORT-14`**, per
§9.3's mechanism, so the gap is reported rather than restated. The only route to satisfying it would be
to parse the response head off the socket before `protocol-http1` does, i.e. to reimplement the HTTP/1.1
response parser inside an adapter whose whole design is to be thin over one library. What would resolve
it: §12's `TRANSPORT` row gains `TRANSPORT-14` to its adapter-scoped list the next time §12 is
deliberately amended by a human, and `docs/deviations.md` carries the interim note. Nothing is broken
today because nothing is implemented.

**Resolution:** *(open)*

### OI-40 — design §3.3 and the corpus name `Async::Task#stop`, which `async` 2.45.1 deprecates in favour of `#cancel`

- **Opened:** 2026-09-11, phase 8c design
- **Status:** open
- **Cites:** ASYNC-6, SEAM-24, DEF-1, DEF-11, TRANSPORT-7

`docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:252-254` reads: "`dexpace-async-async` maps
`Async::Task#stop`/`#with_timeout` onto the pivot's cancellation in both directions for callers whose own
code is already reactor-based (**ASYNC-6**)", and the corpus carries it verbatim as
`concurrency-and-async/f75816b6`. The phase-8 segmentation design cites `Async::Task#stop` as "the
primitive" in its fact 8 and in `R13`. Verified on `async` 2.45.1 under Ruby 3.4.10:
`lib/async/node.rb` carries `# Backward compatibility alias for {#cancel}. # @deprecated Use {#cancel}
instead.` immediately above `def stop(...) = cancel(...)`, and `Async::Task.instance_method(:stop).owner`
is `Async::Node`. The current primitive is **`Async::Task#cancel(later = false, cause: $!)`**, and its
`cause:` keyword is materially better for this port than `#stop` was: a `Dexpace::Cancellation#reason`
passed as `cause:` is readable back off the raised `Async::Cancel` as `#cause`, which is the out-of-band
discrimination `XCUT-2` and `TRANSPORT-3` require and which `#stop` gives no channel for. This is the
same species as the charter's `OI-34` and `OI-35` — a frozen design chapter that is wrong about a
library — and it is smaller than either: the *mapping* §3.3 describes is right, only the method name has
moved. Phase 8c calls `#cancel` everywhere. What would resolve it: `dexpace-async-async` (`DEF-11`,
post-v1) is written against `#cancel`; §3.3's sentence is corrected the next time §3 is deliberately
amended by a human; the corpus entry re-keys on the next harvest, at which point any note citing
`concurrency-and-async/f75816b6` needs revisiting. Nothing is broken today because nothing is
implemented.

**Resolution:** *(open)*

### OI-41 — `TRANSPORT-8` is satisfiable on `dexpace-transport-async_http`, and §12 counts it among the eight MUSTs that hold vacuously

- **Opened:** 2026-09-11, phase 8c design
- **Status:** open
- **Cites:** TRANSPORT-8, TRANSPORT-3, TRANSPORT-4, XCUT-2, ASYNC-6, NFR-8

`docs/sdk-design-ruby/12-appendix-requirement-coverage-index.md:41` lists "TRANSPORT-1, TRANSPORT-2,
TRANSPORT-8 and TRANSPORT-18 … adapter-scoped and vacuous for `Net::HTTP`", and the MUST-level summary
at `:49-55` counts `TRANSPORT-8` among "eight [that] hold vacuously". §9.3 is more careful —
"**TRANSPORT-8** and **TRANSPORT-18** vacuous for `Net::HTTP` and **mandatory for any adapter whose
client has those paths**" — and the corpus carries that as `testing/9a56af9d`. Verified on 2026-09-11
against `async` 2.45.1 and `async-http` 0.104.0 under Ruby 3.4.10: cancelling a **parent** `Async::Task`
delivers `Async::Cancel` into an in-flight child exchange while the SDK future is still live — measured
event sequence `["outer-saw:Async::Cancel", "inner:Async::Cancel", "inner-ensure"]` — which is exactly
`TRANSPORT-8`'s antecedent, "a cancellation that originates inside it (e.g. an internal cancel-all)". It
is not a contrived case: it is the ordinary shape of a consumer whose supervisor cancels its children on
shutdown. The requirement's second clause is free here, because `async` puts the two exceptions in
different halves of the tree: `Async::Cancel < Exception` and `Async::TimeoutError < StandardError`, so
the terminal-versus-retryable discrimination is by class and never by message (`XCUT-2`). Two candidates
were tested and **rejected** as the antecedent: a graceful HTTP/2 GOAWAY mid-stream did not abort the
open stream (the client read it to completion), and `Protocol::HTTP::RefusedError` is a retryable
transport failure rather than a cancellation. So the port gains a **satisfied** MUST where §12 records a
vacuous one — the inverse direction from `OI-34`, and equally a defect in a frozen chapter. What would
resolve it: phase 8c implements and asserts the discrimination and its checklist row states it;
§12's `TRANSPORT` row and the MUST-level count are corrected the next time §12 is deliberately amended
by a human, and `docs/deviations.md` carries the interim note. Nothing is broken today because nothing is
implemented.

**Resolution:** *(open)*
### OI-42 — `net-http`'s connect phase uses `Timeout.timeout`, the primitive design §8.3 bans, and the cop that enforces the ban cannot see it

- **Opened:** 2026-09-11, phase 8a design
- **Status:** open
- **Cites:** ASYNC-3, PIPE-33, XCUT-13, TRANSPORT-4, NFR-2, DEF-18

**`net-http`'s connect phase uses `Timeout.timeout`, the primitive design §8.3 bans, and the cop that
enforces the ban cannot see it.** `/usr/lib/ruby/3.4.0/net/http.rb:1657` is
`s = Timeout.timeout(@open_timeout, Net::OpenTimeout) { TCPSocket.open(conn_addr, conn_port, @local_host, @local_port) }`.
§8.3's prohibition is stated as binding "every gem in this repository" and phase 0 mechanises it as
`Dexpace/NoThreadInterrupt` over this repository's own `lib/`, so a library dependency using it is
outside both the words and the scan. The hazard §8.3 names — an asynchronous interrupt landing "inside an
`ensure` block that is releasing a pooled connection" — is **not** reachable through this particular use:
the interrupt can only land during `TCPSocket.open`, before any SDK object holds a socket, and the
library converts it into a typed `Net::OpenTimeout` rather than letting a bare `Timeout::Error` escape.
So the port's guarantee is narrower than §8.3's sentence and is still true of everything it claims. Worth
a row because the sentence is absolute, because a reader auditing the ban will grep `lib/` and find
nothing, and because the same question will be asked of `async-http`'s dependency closure in `8c`. What
would resolve it: §8.3 gaining one clause scoping the prohibition to code this repository writes, the
next time §8 is deliberately amended by a human. Nothing is broken today because nothing is implemented.

**Resolution:** *(open)*

### OI-43 — design §9.3 calls Minitest a default gem; it is a bundled gem, and §2.4 is built on exactly that distinction

- **Opened:** 2026-09-11, phase 8a design
- **Status:** open
- **Cites:** NFR-2, NFR-17, SEAM-1, DEF-22

**Design §9.3 calls Minitest a default gem; it is a bundled gem, and §2.4 is built on exactly that
distinction.** §9.3's argument for choosing Minitest over RSpec is that "**it ships with the interpreter
as a default gem**, so the same argument §2.4 makes about `base64` and `logger` applies to the test
framework". Verified on 3.4.10: `Gem::Specification.find_by_name("minitest").default_gem?` is `false`,
its gem directory is not the interpreter's, and `Gem::BUNDLED_GEMS::SINCE` does not name it either
(the table lists only gems that *became* bundled at a known version). Minitest is **bundled** — available
with the interpreter, and requiring an explicit `Gemfile`/gemspec entry under Bundler, which is the very
property §2.4 spends a page warning about. The **conclusion** survives unchanged and is the reason this
is a row rather than a correction to a decision: an adapter author can still run the suite with nothing
extra installed, and `dexpace-conformance` still declares nothing, because `8a`'s two drivers reference
`::Minitest` and `::RSpec` at call time and `require` neither. What it changes is one sentence in a frozen
chapter and one line in the root `Gemfile`, which must list `minitest` explicitly. Nothing is broken
today because nothing is implemented.

**Resolution:** *(open)*

### OI-44 — the require-allowlist's denylist has no per-gem scope, so a denial written for core's reason reaches a gem the reason does not describe

- **Opened:** 2026-09-11, phase 8a design
- **Status:** open
- **Cites:** SEAM-1, SEAM-2, NFR-1, NFR-2, DEF-22

**The require-allowlist's denylist has no per-gem scope, so a denial written for core's reason reaches a
gem the reason does not describe.** Phase 0's denylist denies `socket` with the reason "`SEAM-1`/`SEAM-2`:
core embeds no concrete transport", and phase 0's adapter extension permits only "allowlisted, or under
`dexpace/`, or the single third-party gem that adapter's gemspec declares" — so `dexpace-conformance`,
which declares no third-party gem, cannot `require "socket"` even though it embeds no transport and
`socket` is non-gemified stdlib that can never become a bundled gem. The immediate case is `8a`'s
(`P8-14` amends the gate with a named per-gem exception), and the shape is general: every denylist entry
carries a *reason*, the reasons are gem-scoped, and the mechanism is not. The same question will arise
for `dexpace-transport-async_http` and `openssl`, and for any future adapter that legitimately needs a
denied name. What would resolve it: the denylist growing a scope column, so an entry reads "denied to
core and to transport adapters" rather than "denied". Nothing is broken today because nothing is
implemented.

**Resolution:** *(open)*

### OI-45 — `dexpace-transport-net_http` opens a TCP (and over HTTPS a TLS) connection per request, and the corpus rule that forbids that has no note

- **Opened:** 2026-09-11, phase 8a design
- **Status:** open
- **Cites:** TRANSPORT-5, TRANSPORT-29, SEAM-12, NFR-2, XCUT-11

**`dexpace-transport-net_http` opens a TCP — and, over HTTPS, a TLS — connection per request, and the
corpus rule that forbids that has no note.** `resource-management/4aca52f9` says "Never open one
connection per request; size connection or HTTP pools with a bounded, named constant instead", and design
§3.2 with `transport-adapter/52b448e8` requires the opposite for measured reasons this document records
(verified fact 9: a shared `Net::HTTP` under eight threads produced 128 errors and **26 responses matched
to the wrong request**). The design is right and the cost is real: every request pays a handshake, which
on an HTTPS endpoint is one round trip plus a TLS negotiation. A keep-alive pool is not reachable inside
`NFR-2`'s budget — `connection_pool` would be a second third-party declaration and `gates:gemspec_audit`
rejects it — and a hand-rolled pool in the adapter would have to answer every bounded-pool and
deterministic-teardown rule the corpus routes to `dexpace-async-thread`, in a gem that is not that one.
What would resolve it: either a note recording the resolution this document argues, or a later phase
taking a hand-rolled bounded pool with a checkout timeout as a deliberate, separately-designed piece of
work. Recorded now because the first user to benchmark the SDK against `faraday` will find this and
should find it already written down. Nothing is broken today because nothing is implemented.

**Resolution:** *(open)*
### OI-46 — a pooled worker inherits the pool creator's fiber storage, so the repository's context-restore mechanism leaks assembly-time context into a caller's task

- **Opened:** 2026-09-11, phase 8b design
- **Status:** open
- **Cites:** ASYNC-9, ASYNC-10, ASYNC-12, OBS-23, OBS-24, XCUT-11

**A pooled worker inherits the pool creator's fiber storage, so the repository's context-restore mechanism
leaks assembly-time context into a caller's task — and nothing in `docs/knowledge/` or design §8.1 says
so.** Design §8.1 fixes the adapter's shape as "saves the worker's prior storage, installs the captured
snapshot for the work's duration and restores it in an `ensure`", and phase 5b's `Diagnostics.with`
implements exactly that with a **merge** on install (`snapshot.each { |k, v| Fiber[k] = v }`), which is
correct for 5b's own consumer and for `OBS-24`. Measured on Ruby 3.4.10: a pool built while
`Fiber[:tenant] = "assembly"` was set, driven by a caller whose captured context is
`{"trace.id" => "CALLER-A"}`, runs the task with `{"trace.id" => "CALLER-A", :tenant => "assembly"}`
visible — because `::Thread.new` inherited `:tenant` at pool construction and the snapshot has no key to
overwrite it with. That is `ASYNC-10`'s "a stale snapshot from when it was assembled", and it is invisible
in every test that builds the pool in the same context it submits from. **Phase 8b fixes it for its own
gem** with a one-time clear of inherited storage at worker start (`P8-20`), and the *finding* is that the
hazard is a property of **any** long-lived carrier this repository creates with `::Thread.new` — a future
`dexpace-instrumentation-otel` background exporter, a `dexpace-async-concurrent_ruby` pool, or a caller's
own worker wrapped in `Diagnostics.with` — and neither the design sentence nor the harvested rule warns
about it. What would resolve it: either a sentence in §8.1 (a frozen chapter, so not now) or the knowledge
note `8b` files below, which is the route taken. Nothing is broken today because nothing is implemented.

**Resolution:** *(open)*

### OI-47 — `Dexpace::Bridge::AsyncOver`'s posted block re-checks cancellation on return and not before dispatch, so a task cancelled while queued still performs its network round-trip

- **Opened:** 2026-09-11, phase 8b design
- **Status:** open
- **Cites:** SEAM-18, SEAM-30, ASYNC-3, ASYNC-5, PIPE-33, XCUT-3

**`Dexpace::Bridge::AsyncOver`'s posted block re-checks cancellation on return and not before dispatch, so
a task cancelled while queued still performs its network round-trip.** Phase 2's design describes the block
as "perform[ing] the blocking send, re-check[ing] cancellation on return". The worker's
`::Thread::Queue#pop` is one of the four suspension points `concurrency-and-async/611b9392` enumerates, so
the block begins executing immediately after a resume — the earliest check-after-resume point a queued task
has — and a single `cancellation.cancelled?` test there would turn a wasted round-trip into no round-trip.
**Nothing is broken**: `ASYNC-3`'s third clause requires only that a queued task not be *interrupted*,
which holds because nothing is ever interrupted; `SEAM-30`/`ASYNC-5` close the orphan through
`Completer#fulfil`'s losing-race branch; and no response reaches a cancelled caller. What is lost is one
network call, one connection from the pool, and — on a non-idempotent method — one **server-side side
effect a caller believed they had cancelled**, which is the half that makes this worth a row rather than a
micro-optimisation. **It is filed rather than fixed because it is `dexpace-core`'s code**: `AsyncOver` is
phase 2's, committed and reviewed, and `dexpace-async-thread` cannot see the token — the pool posts an
opaque block by design (`concurrency-and-async/08a0e08d`), which is also what lets the same object serve
`Dexpace::Page::_Executor`. The repair is one `if` at the top of the posted block and belongs to whoever
next amends phase 2. `OI-18` is the same species from the same object: a core mechanism correct about what
it was designed for and silent about a case a later gem made reachable. Nothing is broken today because
nothing is implemented.

**Resolution:** *(open)*

### OI-48 — `Thread#report_on_exception` writes to `$stderr` directly, so a dying thread is invisible to the warnings-fatal gate that exists for exactly this

- **Opened:** 2026-09-11, phase 8b design
- **Status:** open
- **Cites:** NFR-7, NFR-17, XCUT-11, ASYNC-15

**`Thread#report_on_exception` writes to `$stderr` directly, so a dying thread is invisible to the one gate
that exists for exactly this.** Phase 0's gate set runs the real suite under `ruby -w` with warnings
failing the build, and its shared test case **overrides `Warning.warn` to raise** — which is what catches
`IO::Buffer`'s experimental warning (7a's `P7-5`) and `Fiber#storage=`'s (`OI-13`). Measured on 3.4.10: a
thread that dies with an exception prints `#<Thread:…> terminated with exception (report_on_exception is
true)` to `$stderr` and the `Warning.warn` override captures **nothing**. So a suite that leaks a dying
thread — a test double's worker, a helper's background thread, a future adapter's exporter — produces
stderr noise no gate reads and no assertion fails. **Phase 8b's own workers cannot die** (`P8-22`) and set
`report_on_exception = false` inside the thread body anyway, so this gem is not the subject; the finding is
that **the repository's warnings-fatal gate does not cover thread death**, and phase 8 is the first phase
to create threads at all. What would resolve it: a shared test-case addition asserting `::Thread.list.size`
is unchanged at `teardown`, which is a phase-0 artifact and a one-line change — cheaper than the class of
bug it catches, and `8b`'s own suite already asserts it per-test. Nothing is broken today because nothing
is implemented.

**Resolution:** *(open)*

next id: OI-49
