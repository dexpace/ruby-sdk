## 4. Domain Model Construction

**HTTP-1**, **HTTP-2**/**SEAM-29** and **XCUT-15** require every core domain type to be immutable and safe to share
after construction, constructed only through an immutable value plus a builder or factory, with no public
field-wise constructor and no unchecked copy bypassing validation. **HTTP-3** requires a pre-filled, non-aliasing
derivation; **HTTP-4** requires `build()` to validate required fields and fail with a field-named error;
**HTTP-5** requires accessors to isolate the caller from both the model's internals and a still-live builder.

**`Data.define` is the base.** Verified on 3.4.10: a `Data` instance is frozen on construction, `#with` produces a
copy with changes, and `==`/`eql?`/`hash` are generated consistently over all members — the whole value-object
contract for free, and `Data` requires all members at construction (stricter than `Struct`, which is mutable by
default). `Data` also permits an `initialize` override that validates and then calls `super`, so **HTTP-4**'s
field-named validation lives in the type rather than beside it; the shared helper raises one error type with the
one message form `"<name> is required"` that **SEAM-29** fixes, so field-named errors cannot drift between models.
Every file carries `# frozen_string_literal: true`.

**Where a real builder is kept, and where `#with` replaces one.** **HTTP-3** explicitly distinguishes builder-based
models from "value types with no builder (media type, status, typed header name, ETag, range, method, protocol)
[which] derive via re-construction through factories." The port follows that split exactly: `MediaType`, `Status`,
`Protocol`, `Method`, `HeaderName` and the conditional-request helpers are `Data` types with `parse`/`of`
factories and `#with`; `Request`, `Response`, `Headers`, `Query`, `RequestOptions` and `Configuration` get real
mutable `Builder` classes, because their validation is cross-field (**HTTP-7** rejects a body on
GET/HEAD/TRACE/CONNECT; **HTTP-8** defaults the method to GET only when there is no body) and cannot be expressed
as per-member checks. `#new_builder` returns a builder pre-filled from the instance that `dup`s every collection
rather than aliasing it (**HTTP-3**), so later builder mutation cannot reach back into the source model.

**Read-only collection exposure, computed once.** Because models are genuinely immutable after construction,
**HTTP-5** does not need a per-access wrapper: each collection is duplicated and frozen exactly once at
construction and the same frozen reference is returned from every accessor. The specification itself grants the
mechanism latitude here — "A port in a language without read-only views MUST reproduce this with unmodifiable
wrappers or per-call defensive copies" — and freezing at construction satisfies the outcome more cheaply than
either. Two Ruby caveats make this a real design decision rather than a one-liner. First, **`freeze` is shallow**:
verified that a `Data` instance is frozen while a nested `Array` member is not, so every nested collection is
frozen independently at the same construction step. Second, `Ractor.make_shareable` gives a genuine deep freeze
(verified: it walks the graph, freezing nested hashes, arrays and their string values) — **but it freezes in
place and returns the same object**, so applying it to a caller-supplied hash would silently freeze the caller's
live object. Core applies it only to a collection the model has already `dup`ed and therefore owns. The payoff is
free forward hygiene: verified that a `Data` holding an unfrozen `Hash` is not `Ractor.shareable?` while the same
`Data` holding a frozen one is, so deep-freezing at construction makes the whole wire model Ractor-shareable today
without Ractor being a load-bearing mechanism (§9's runtime floor keeps it out of the supported surface).

**The encapsulation gap, stated honestly (P8).** Ruby cannot close **HTTP-2**/**SEAM-29**'s "no public field-wise
constructor" the way a language with enforced constructor privacy can, and there are two independent holes.
*(i) Construction privacy is advisory.* `private_class_method :new` on a `Data` subclass works, and a validating
`.build` funnels all legitimate construction — but verified: `Req.send(:new, ...)` reaches the generated
constructor anyway, because `send` bypassing `private` is a deliberate, documented Ruby feature, not an oversight.
*(ii) Duck typing admits impersonation.* Any object responding to `#method`, `#url`, `#headers` and `#body`
satisfies every structural expectation a pipeline step has of a `Request`, entirely bypassing builder validation.
Neither hole can be closed. The mitigation is threefold and is deliberately not a fake proof: the official
construction path is genuinely closed (`private_class_method :new` plus a validating factory); the public API
documents and RBS declares the concrete types rather than bare interfaces, so a caller who duck-types past them is
knowingly opting out, exactly as a caller reaching for `instance_variable_set` on a frozen object is; and — this
is the part that matters for security rather than tidiness — **the two invariants whose violation is exploitable
are re-checked at the model-to-wire boundary inside every transport adapter**, not only in the builder. Header name
and outbound value validation (**HTTP-17**, **HTTP-18**, **XCUT-18**) runs again immediately before dispatch, so a
forged model cannot smuggle a CRLF into a header name even if it never met a builder. That makes the residual gap
a correctness-of-shape gap, not a request-splitting gap. Recorded in §10.

**Headers** (**HTTP-13**–**HTTP-22**) are two parallel frozen hashes: normalised (downcased) name → frozen array of
values for lookup, containment, mutation, removal, equality and hashing; and normalised name → original casing for
wire emission (**HTTP-21**). **HTTP-13**'s "never a locale-sensitive fold" needs one correction to the obvious
reading and then holds. `String#downcase` **does** have a locale mode — verified on 3.4.10, `"I".downcase(:turkic)`
returns `"ı"`, the dotless i that breaks a case-insensitive header comparison — but it is opt-in per call and
selected by an explicit symbol argument. What Ruby lacks is an *ambient* locale that could change the meaning of a
bare `downcase`, which is the mechanism that makes this a live hazard on hosts where the default fold reads a
process or thread locale. So the guarantee is not "the language cannot do this" but "the language cannot do this by
accident, and core never asks it to": **`downcase` is called with no arguments everywhere in core**, and the lint
rule that forbids `Time.parse` also forbids passing a locale symbol to `downcase`/`upcase`/`casecmp` anywhere in
the repository, so the guarantee is enforced rather than assumed. Bare `downcase` *is* still Unicode-aware, which
would fold non-ASCII bytes; that is harmless only because **HTTP-17** rejects non-ASCII in names before storage, so
the fold never sees a non-ASCII byte. That dependency is stated because relaxing **HTTP-17** would silently break
**HTTP-13**. Setting a value to `nil` removes the header entirely (**HTTP-15**); insertion order of distinct names
is preserved by Ruby's insertion-ordered `Hash` at no cost (**HTTP-16**). **HTTP-22**'s optional interning is not
implemented: it is a **MAY**, the observable contract is value equality by folded name, and Ruby's frozen string
literals already deduplicate the common case.

**Status** (**HTTP-10**–**HTTP-12**) is `Data.define(:code)` with the canonical name looked up from a frozen table
rather than stored as a member. This is not a stylistic choice: **HTTP-12** requires two `Status` values to be
equal iff their codes are equal, with the name not participating, and a `Data.define(:code, :name)` would generate
equality over both members and quietly violate it. Construction is total over any integer (**HTTP-10**) — an
unrecognised code yields an instance with no canonical name, never a raise — and a separate lookup lets callers
distinguish recognised from unrecognised. Range classification (**HTTP-11**) is derived, not stored.

**Media type** (**HTTP-23**–**HTTP-27**, **HTTP-53**) needs a hand-written parser: it must split parameters
respecting quoted strings, split each parameter on the *first* `=` only, strip quotes and unescape quoted pairs,
and render so that `parse(render(x)) == x`. Ruby ships nothing that does this. The parser uses
`Regexp.new(source, timeout: ...)` (per-pattern, 3.2+) rather than the process-global `Regexp.timeout`, because a
library must never impose a process-wide regexp budget on its host; this is cheap hardening against a
pathological `Content-Type` from a hostile server, and the same treatment is given to the challenge parser in §6.3.

**Query** (**HTTP-28**–**HTTP-32**) is an insertion-ordered list of name/value pairs, not a `Hash`, because
**HTTP-28** requires multi-value support with order preserved and a value-less parameter modelled as a single
empty-string value distinct from an absent name — a shape a `Hash` cannot express. Encoding uses §3.5's strict
component encoder. Parsing (**HTTP-31**) is lenient and total: a malformed percent-escape falls back to the raw
text rather than raising, which is the opposite of `URI.decode_www_form_component`'s behaviour and therefore
another hand-rolled function.

**Request options** (**HTTP-34**, **HTTP-35**) are a `Data` with `nil`-defaulted timeout and max-retries and a
frozen tag hash, plus a canonical frozen `EMPTY` instance so "override nothing" allocates nothing per call.
Timeout is a `Float` of seconds, matching every Ruby socket API so no unit conversion sits between the model and
the wire.

---

