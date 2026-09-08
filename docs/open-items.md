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

next id: OI-21
