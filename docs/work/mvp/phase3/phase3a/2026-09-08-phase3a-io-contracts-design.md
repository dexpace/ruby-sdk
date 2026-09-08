# Phase 3a — I/O Contracts

**Status:** Draft, for review. Written 2026-09-08, against
`docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md`, which is this sub-phase's charter.

## Purpose

Sub-phase 3a builds the byte-streaming layer every body, every logging snapshot, every codec and the
whole of SSE and pagination later stand on: one FIFO buffer, one buffered source/sink pair with typed
reads and non-consuming views, and one tee sink that mirrors a bounded tap without ever altering the
wire body. It is the layer design §10.1 kept when it retired the seam that used to make it pluggable,
so **the behavioural contract is the whole deliverable and there is no factory, no registry and no
installation call to build.**

Three decisions in this document reshape what the rest of phase 3 consumes, and each was forced by a
fact run on a real interpreter rather than by taste.

- **`IO-1`'s read primitive and Ruby's `#read` cannot be the same method.** `IO-1` requires a
  tail-append into a caller's buffer; `IO.copy_stream` — the exact call `Net::HTTP#body_stream=`
  makes — hands `#readpartial` **one buffer that it reuses across every call** and expects it to be
  overwritten. A `BufferedSource` that satisfied `IO-1` under the name `#read` would corrupt every
  streamed upload and grow that buffer without bound. The primitive is `#read_into`; `#read`,
  `#readpartial`, `#getbyte` and `#each` keep Ruby's semantics and are what makes design §3.1's
  "`IO-16` is satisfied by construction" true rather than merely asserted (R2, R4).
- **`Dexpace::EndOfStreamError` must inherit `::EOFError`, and that is load-bearing rather than
  tidy.** `IO.copy_stream` terminates on an `EOFError` **subclass** raised by a duck-typed
  `#readpartial`, verified on all three interpreters. An end-of-stream error outside that family
  would propagate out of every streaming upload phase 8 performs.
- **Defining `Dexpace::IO` reaches further than core.** Inside `module Dexpace`, `x.is_a?(IO)` and
  `IO === x` are silently `false` for a real `::IO` — and, contrary to phase 1's "verified inert
  outside core", the same is true inside a **consumer's own class that does `include Dexpace`**.
  Phase 1's claim holds only for a top-level include. Filed as `OI-3` (R1).

3a ships no body, no transport and no pipeline. Its whole test surface is bytes: construction,
reading, writing, views, close, encoding and the two threads that `IO-38` puts on one flag.

## Governing documents

- `docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md` — the charter. It fixes 3a's 42
  IDs, the ten spec-forced boundaries, the gap IDs and risks R1–R4. R5–R10 are 3b's and are not
  touched here.
- `docs/product-spec/05-i-o-contracts.md`, read in full, with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` for the canonical text
  of every ID — and for `IO-6`, which appendix C is the **only** normative statement of (`OI-2`).
- `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.1 in full and §3.7 for the close
  latch; `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md` §7.1 for the `Enumerator`
  rule; `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md` items 1, 2,
  10, 11, 12 and 18; §12's `IO` row.
- `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md` — the phase-3 row, the eight cross-cutting
  constraints and the ✅ / 🚫 / ⏳ / N/A legend used verbatim by this sub-phase's checklist.
- `docs/work/mvp/phase1/2026-09-05-phase1-core-http-domain-model-design.md` and
  `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` with
  `docs/work/mvp/phase2/2026-09-07-phase2-seam-foundations.md` — what 3a stands on.
- `CLAUDE.md` and `docs/README.md`.

## Scope

### The 42 IDs, with dispositions

**Implemented — 34.** `IO-1`–`IO-29`, `IO-37`, `IO-38`, `IO-40`, `IO-41`, `IO-42`. Three of them are
SHOULDs — `IO-9`, `IO-16` and `IO-18` — and all three are implemented; `IO-16`'s "satisfied by
construction" claim is **verified rather than restated**, which is R4 and is answered below.

**🚫 permanent simplification — 8.** `IO-30`, `IO-31`, `IO-32`, `IO-33`, `IO-34`, `IO-35`, `IO-36`,
`IO-39`. Every row cites `docs/sdk-design-ruby/10-…md` item 1, which retires the byte-stream provider
seam together with its registry, and §12's `IO` row, which confirms it. Phase 2 already shipped
`SEAM-3`/`SEAM-4` as 🚫 with the reason attached. **3a creates no fourth registry, no factory and no
installation call**, and it does not re-argue the retirement (boundary 9).

`IO-32`–`IO-35` are four of the roadmap's five gap IDs; the segmentation design confirmed the
roadmap is right about them and budgeted no reading. `IO-6` is the fifth and is a live MUST that
3a implements — see R3.

**Also fixed by 3a without owning a new ID**, per the charter:

- the **canonical body representation** — design §10.2's duck type, any object responding to `#each`
  and yielding `String` chunks tagged `Encoding::BINARY`. The body **production contract**
  (`HTTP-36`/`BODY-1`) is 3b's and does not appear here.
- **`BufferedSource.over`** and its stated no-ownership exception (§3.1, `message-bodies/f060d944`).
- **`MAX_MATERIALIZED_BYTES`** — §10.18's substituted constant, §3.1's 64 MiB default, "chosen, not
  derived" (boundary 8).

### The canonical text the design turns on

Quoted from appendix C rather than paraphrased, because each of these fixes a decision below.

> **IO-1** (MUST) — `Source.read(dest, byteCount)` MUST append the bytes it reads to the TAIL of the
> caller-provided destination buffer (never overwrite existing content), and MUST return the number
> of bytes transferred: at least 1 when byteCount>0 and the source is not exhausted, exactly 0 when
> byteCount==0, -1 when the source is exhausted before any byte is read, and never more than
> byteCount.

> **IO-6** (MUST) — When a provider wraps a caller-supplied underlying stream (readable stream ->
> buffered source, writable stream -> buffered sink), the returned wrapper MUST take ownership of
> that stream: closing the wrapper closes the underlying stream. The same holds for the stream
> bridges obtained from a buffered source/sink (closing the bridge closes the owning source/sink).
> Wrapping a plain byte array owns no external resource.

> **IO-16** (SHOULD) — A BufferedSource SHOULD provide a read-only **host-native** byte-stream bridge
> whose single-byte read returns the next byte as an unsigned value 0..255 or -1 at end, and whose
> bulk read returns the count read or -1 at end; closing the bridge MUST close (or invalidate) the
> owning source. Symmetrically a BufferedSink SHOULD provide a writable-stream bridge whose close
> closes the sink.

> **IO-37** (MUST) — All streaming instances … are single-threaded contracts: they are NOT required
> to be safe for concurrent use, and callers MUST serialize external access when sharing one across
> threads. Independent views (slices, peeks) MAY be used from different threads, but each individual
> view remains single-threaded.

> **IO-40** (MUST) — These streaming contracts MUST NOT impose their own read/write timeout or
> deadline; the adapter wraps foreign streams with a no-op timeout, delegating all deadline
> enforcement to the transport. A mirroring/wrapping sink MUST NOT swallow OR duplicate the wrapped
> stream's cancellation/interrupt handling …

> **IO-42** (MUST) — A buffered source/sink that wraps an external stream MUST reject
> read/write/flush/emit attempts made after close() with an I/O error … A purely in-memory buffer is
> exempt on its OWN read/write surface … but its close() MUST still invalidate every slice derived
> from it.

### Out of scope, explicitly

| Excluded | Owning phase |
|---|---|
| Every `BODY` ID and the twelve `HTTP` IDs jointly numbered into spec ch.06 | 3b |
| The body **production contract** — `HTTP-36`/`BODY-1`'s single write-to-sink operation, media type, content length, `#replayable?` | 3b. 3a fixes only the representation |
| `DEF-26`'s narrowing of `Request#body`/`Response#body` in `sig/` | 3b — it needs a body type, and 3a's duck type is not one |
| `HTTP-42`'s decode **policy** — the single decode boundary is `Response#body_string` | 3b. 3a ships `IO-13`'s charset reads as a primitive and adds no second decode site (boundary 7) |
| `IO-9`/`BODY-32`'s ceiling as a **configurable** limit rather than a constant with a default | 5. 3a owns the constant; R5 (3b's) decides the parameter shape by which a value reaches it |
| Any clock, deadline or timeout | 8 for the transport that owns the socket; 5 for `CFG-15`–`CFG-21`. `IO-40` forbids one here outright (boundary 1) |
| `SSE-12`'s BOM rule and the SSE line machine over `IO-14`; `PAGE`'s and `SERDE`'s use of `BufferedSource.over` | 7 |
| `SERDE-3`/`SEAM-20`/`SEAM-21`'s third ownership rule — a codec closes nothing | 7. Phase 3 neither implements nor weakens it (boundary 5) |
| `XCUT-15`, `XCUT-18` — restated cross-cutting invariants 3a leaves satisfiable without claiming | 9 |

**No segmentation design of its own.** 3a is one spec chapter, one gem, 42 IDs, under a segmentation
design that already exists at the `phase3/` level.

## Prerequisites

### From phase 0 — seventeen blocking gates, unchanged and unlowered

`gates:require_allowlist` is the one that constrains the code: core's `lib/**/*.rb` may `require`
only `monitor`, `uri`, `stringio`, `strscan`, `time`, `date`, `securerandom`, `digest`, `openssl`,
`forwardable`, `set`, `singleton`. **3a adds nothing to it and requires nothing at all** — `::IO`,
`::String`, `::Encoding`, `::Thread::Mutex` and `::Enumerator` are core Ruby and need no `require`.
`stringio` is already allowlisted and 3a uses it in `test/` only. Re-verified on 3.2.11, 3.4.10 and
4.0.6 that neither `stringio` nor `tempfile` appears in any `Gem::BUNDLED_GEMS::SINCE` table
(undefined on 3.2.11; 28 entries on 3.4.10; 23 on 4.0.6), so neither is at risk of the bundled-gem
trap inside the supported range.

`gates:surface_snapshot` and `gates:sig_diff` are regenerated once, deliberately, in the phase's last
task — every public constant below is `NFR-4`-locked at the first release tag, which is why each is
named on purpose and carries a Deviation Ledger row where design §3 did not name it.

### From phase 1

`Dexpace::Model` and `Dexpace::Builder` are **not** used by 3a: nothing here is a `Data` value type.
What 3a does inherit and obey:

- **`Dexpace::InvalidArgumentError < ::ArgumentError`** — every argument-validation failure in 3a
  raises it (`IO-3`, `IO-10`, `IO-21`). No new argument-error class is defined.
- **`Dexpace::Error` is a module**, included by every core error class (P1-2). 3a's two new error
  classes include it.
- **`Dexpace::ArgumentError` is never defined**, in this or any later phase — and the same rule
  applies, for the same reason, to **`Dexpace::IOError` and `Dexpace::EOFError`**, which would shadow
  Ruby's for every file inside `module Dexpace` and silently narrow every bare `rescue IOError` in
  core. The classes below are `Dexpace::StreamError` and `Dexpace::EndOfStreamError`.
- **Public constants are flat unless the design namespaced the subsystem** (P1-1). Design §3.1 and
  §10.2 name `Dexpace::IO::Buffer` and `Dexpace::IO::BufferedSource`, so the whole streaming
  subsystem is namespaced and the two error classes are flat.
- **`downcase` takes no argument** (`Dexpace/NoLocaleCaseFold`) — 3a folds one thing, a charset name.

### From phase 2

- **`Dexpace::Closeable`** with its latch: `initialize_closeable(owned:)`, `#owned?`, `#closed?`,
  `#close` and a private `#release`, the mutex held **only across the flip**. `IO-41`'s idempotent
  close is that latch and 3a writes no second one (charter prerequisite).
- **`Dexpace::ClosedError`** — phase 2 shipped the class, the rule and **no raise site**. 3a is its
  first caller.
- **`Dexpace::Hooks`**, `Dexpace.close_quietly`, `Dexpace::Cancellation`, `Dexpace::Registry` and the
  async pivot are not used by 3a. `close_quietly` gains **no** new call site here: every close 3a
  performs is either an explicit caller close or a `#release`, and §3.7 makes both loud.
- **The six custom cops**, of which `Dexpace/QualifiedCoreConstant` is extended by R1.

### The one change 3a makes to a phase-2 constant

**`Dexpace::Closeable#closed?` is changed to read the latch under the close mutex.** Phase 2's reader
is unsynchronised — it returns `@dexpace_closed` directly — which is correct for everything phase 2
ships, because nothing there reads the flag from a second thread. `IO-38` is the first requirement
that does: "the CLOSE state of a source/buffer MUST be observable across threads to the slices
derived from it, so that a close on one thread reliably invalidates a slice being read on another
(no torn or stale reads)", and design §3.1 fixes the mechanism — "written and read through a
`Thread::Mutex` rather than relying on the GVL, so the guarantee survives JRuby and TruffleRuby". An
unsynchronised read relies on exactly the GVL that sentence declines to rely on.

Measured on 3.2.11 / 3.4.10 / 4.0.6: 10⁶ `Thread::Mutex#synchronize` round trips cost 0.050 s /
0.071 s / 0.060 s against 0.013 s / 0.020 s / 0.017 s for the same loop with no lock — about 40 ns
per call. That is affordable **once per public call** and not once per byte, which is why the rule
below is stated as a call-boundary rule. Recorded as **P3-6**; the change is one line inside
`lib/dexpace/closeable.rb` and it lands in 3a because 3a is where the requirement bites.

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run before anything here was written, and the
counts below are what it returned **before this phase filed its own three notes**.
`--origin note --brief` returns 21 entries across 12 note files; `--section conflicts --brief`
returns 16 note entries and 6 harvested ones, and **all six harvested conflicts print
`[overridden by notes/…]`** — none is open, so 3a inherits no unresolved conflict.

`--prefix-info IO` reports 42 IDs, 35 MUST / 6 SHOULD / 1 MAY, owning chapter
`docs/product-spec/05-i-o-contracts.md`, and **37 of 42 substantive with zero roll-up-only entries**
— the appendix-B roll-up hazard does not fire for this prefix at all. `--gaps IO` returns the five
the charter already dispositioned. **Both of those two numbers move when this phase's own notes
land**, and a reader re-running the query afterwards should expect 38 of 42 and four gaps, not 37 and
five: the `message-bodies` note below cites `IO-6`, which is what makes `IO-6` substantive. The other
four gaps — `IO-32`–`IO-35` — stay gaps, because 3a reads nothing for them.
`--phase 1 --brief` and `--phase 2 --brief` were run: phase 1
cites no `IO` ID; phase 2 cites `IO-1`, `IO-29`, `IO-37`, `IO-39` and `IO-42` from its own
out-of-scope table, pointing here.

### The audit groups this phase ran

| Group | Query | Result |
|---|---|---|
| **Encoding and binary strings** | `--prefix IO --section rules` then `--topic io-and-byte-streams,serde --section rules --grep 'encoding\|binary\|ASCII-8BIT\|force_encoding'` | 33 + 5 entries. `io-and-byte-streams/ff0de47e` and `/d2b47c89` adopted verbatim and load-bearing. **`io-and-byte-streams/0a4773a6` is superseded** — see the note below |
| **Resource lifecycle and stream ownership** | `--topic resource-management --section rules` and `--chapter 13` | 27 entries. **This group was not in the skill's audit table; it was added there before the audit ran**, per the roadmap's first retrospective rule. Two rules changed the design (block forms, and the timeout conflict below) |
| **Public API surface** | `--topic api-design,documentation,module-organization --section rules` | `api-design/1d9e6e0b` (keyword arguments) shapes every signature; `api-design/79b5d745` (documented asymmetry) is what `IO-42` needs; `api-design/88e6bf12` (narrowest duck-typed parameter) is R1's real mitigation |
| **Fiber scheduler, thread safety** | `--topic concurrency-and-async --section rules --grep 'mutex\|thread\|fiber\|GVL\|single-thread\|concurrent'` | Clean. `concurrency-and-async/f414b864` (the note) governs: one frozen snapshot under a `Thread::Mutex`, the lock held across a flag flip and nothing else |
| **Minitest conventions** | `--chapter 11 --section rules` and `--topic testing,assertions --section rules` | Clean. `testing/f36a19cd` makes property tests mandatory for the codec-shaped parts; `testing/62f8f4ec` and `/4ef070df` shape the negative tests |
| **Styleguide-vs-design conflicts** | `--section conflicts --brief` | All six resolved |

Two audit results earn **no note of their own**, and for two different reasons — neither of which is
the precedence rule, because neither is a conflict:

- **`api-design/c15b29ce`** ("every collection, hash, or struct returned from a public method must be
  frozen") is out of **scope** rather than overruled: `#snapshot` returns a `String`, which is none of
  the three the rule names, and `IO-8`'s own "and vice versa" clause positively presumes the caller
  may mutate it. A note records what an implementation found a rule to get *wrong*; a rule that
  simply does not reach the case is a Deviation Ledger row, and it is **P3-10**, so the reasoning is
  not rediscovered as a bug.
- **`resource-management/bf5560dc`** ("use block form … for every closable resource") is **adopted**,
  in full, for the two factories that take ownership of an external stream; it has nothing to say
  about the factories that own nothing. An adopted rule needs no note either. It is nonetheless
  mentioned inside the `resource-management` note below — that note has to say which rules in the
  chapter it does *not* resolve, or a reader takes the timeout finding as a verdict on the chapter —
  and it carries **P3-12**. See "Ownership" below.

### The three notes filed against the corpus by this phase

Written before the plan, because a resolution recorded only in a design document is re-litigated by
whoever reads the corpus next.

- **`docs/knowledge/notes/message-bodies.md`** (new file), `## Conflicts` — the I/O-layer
  ownership rule's surviving normative home is **`IO-6`**, not the retired `SEAM-3`. Resolves
  `message-bodies/8a1e7a7b`, whose text ("at the I/O layer, wrapping takes ownership … (SEAM-3,
  BODY-11, BODY-8)") attributes a live MUST to an ID design §10.1 retires and phase 2 shipped as 🚫.
  This is R3, and it is the corpus half of `OI-2`.
- **`docs/knowledge/notes/io-and-byte-streams.md`** (new file), `## Superseded` — two entries.
  (a) `io-and-byte-streams/ba53c43b` (`IO-1`) and `/f009344c` (`IO-16`) read together imply one
  `#read`; **they cannot be one method in Ruby**, with the `IO.copy_stream` evidence. (b)
  `io-and-byte-streams/0a4773a6`'s "`force_encoding` is a retag used only where the bytes are known
  to conform" is true and incomplete: `force_encoding` also requires a `String` you own. A Rack body
  under `# frozen_string_literal: true` yields **frozen** chunks, and `force_encoding` on a frozen
  `String` raises `FrozenError` **even when the encoding is already the one being set**, verified on
  all three interpreters. `String#b` is the ingress idiom.
- **`docs/knowledge/notes/resource-management.md`** (new file), `## Conflicts` — the styleguide's
  per-call I/O timeout rules (`resource-management/c86d4e58`, `/ed29d0f5`, `/2b9040ef`) do **not**
  reach this layer. `IO-40` is a MUST that these contracts impose no timeout of their own, and the
  precedence rule gives an ID-bearing rule the win. The timeouts land where the socket is, in phase
  8's transports.

## The verified Ruby facts this phase is built on

Every claim was run on 3.2.11, 3.4.10 and 4.0.6 through `mise exec ruby@<v>` on 2026-09-08. The first
five changed a decision; the rest are recorded because the plan would otherwise assume them.

1. **`IO.copy_stream` reuses one destination buffer across every `readpartial`/`read` call, and
   expects it overwritten.** Against a duck-typed source, `copy_stream` checks `respond_to?(:to_path)`,
   then `respond_to?(:readpartial)`, then calls `readpartial(16384, buf)` with the **same `buf`
   object every time** (`p.ids.uniq.size == 1` on all three); with no `#readpartial` it falls back to
   `read(16384, buf)` with the same expectation. `Net::HTTP#send_request_with_body_stream` is
   `IO.copy_stream(f, sock)`, so this is the call every streamed upload makes. **`IO-1`'s
   tail-append is the exact opposite**, so the two cannot share a name. This is R2 and R4's evidence
   and it is the single most consequential fact in this document.
2. **`IO.copy_stream` terminates cleanly on an `EOFError` *subclass*** raised by a duck-typed
   `#readpartial` — `n=3`, payload intact, on all three. `Dexpace::EndOfStreamError < ::EOFError` is
   therefore not a stylistic choice: outside that family, `copy_stream` propagates and phase 8's
   uploads fail.
3. **`force_encoding` on a frozen `String` raises `FrozenError`, even when the target encoding is
   already the string's own.** And under `# frozen_string_literal: true` — which every file in this
   repository carries and which a Rack-style body's `["chunk"].each` inherits — those chunks are
   frozen. `String#b` always returns a **new, unfrozen** object (`fz.b.equal?(fz)` is false;
   `fz.b.frozen?` is false), so `#b` is the ingress retag and `force_encoding` is not.
4. **Appending a non-ASCII UTF-8 `String` to a BINARY one silently retags the result to UTF-8; an
   ASCII-only one does not.** `(+"").b << "é"` is UTF-8; `(+"").b << "abc"` stays ASCII-8BIT; `#concat`
   behaves identically. That asymmetry is the trap: **an ASCII-only test fixture passes under the
   bug**, so every encoding test in 3a uses non-ASCII bytes.
5. **`Dexpace::IO` shadows `::IO` inside a consumer's own class, not only inside core.** Inside
   `module Dexpace`, `x.is_a?(IO)` and `IO === x` are `false` for a real `::IO` with no error and a
   `case/when IO` falls through, while a bare `IO.pipe` raises `NoMethodError` (loud, harmless). New
   here: in `class C; include Dexpace; …; x.is_a?(IO)`, the answer is also **`false`**, because
   `Dexpace` sits ahead of `Object` in `C.ancestors`. Phase 1's "verified inert outside core" holds
   only for a **top-level** `include Dexpace`, where `Object`'s own constants win and `Dexpace` lands
   *after* `Object` in the chain — verified both ways. `File`, `StringIO` and `Tempfile` are **not**
   shadowed, because no `Dexpace::` constant of those names exists. Filed as `OI-3`.
6. **`Thread::Mutex#synchronize` costs about 40 ns more than an unsynchronised read** (10⁶ round
   trips: 0.050 / 0.071 / 0.060 s against 0.013 / 0.020 / 0.017 s). Affordable once per public call.
7. **A `Thread::Mutex` held across a fiber suspension raises `ThreadError` for the second fiber of
   the same thread**, and nesting `synchronize` in one fiber raises `ThreadError: deadlock; recursive
   locking`. Both re-verified. This is what makes the "two fibers of one thread interleaving reads"
   test below a real proof that no lock is held across a read.
8. **`readpartial` raises `EOFError` where `read(n)` returns `nil`; `read()` with no count returns
   `""` at EOF; `read(0)` returns `""` on both `IO` and `StringIO`, exhausted or not.** Two sentinels
   for one condition, and `IO-2`'s stated hazard does not fire for Ruby's own readers — but `IO-2` is
   about 3a's surface, not about `IO`'s, so it still needs its row and its test.
9. **Reading or `readpartial`-ing a closed `IO` or `StringIO` raises `IOError`** on all three. That is
   the behaviour `IO-42` asks 3a to reproduce on its own surface.
10. **`IO#write` returns the full count for a 1 MB blocking write**; a duck-typed destination needs
    only `#write` returning the byte count for `IO.copy_stream` to drive it.
11. **`StringIO#read(n, buf)`'s destination encoding changed at exactly Ruby 3.4** — ASCII-8BIT on
    3.2.11, UTF-8 on 3.4.10 and 4.0.6 — while `IO#read` preserves the destination's tag on all three.
    The same floor-straddling shape design §3.5 pins `URI::RFC3986_PARSER` against. 3a never infers a
    tag from a destination or a source.
12. **The `Enumerator` `ensure` asymmetry holds on 3.2.11, 3.4.10 and 4.0.6**: `#each` with a block
    and a `break` runs the `ensure`; `#next` then abandonment does not, after two `GC.start` calls.
    Re-verified here because §7.1's rule binds 3a before it binds phase 7.
13. **`Encoding.find` raises `ArgumentError` for an unknown name** and resolves `iso-8859-1`;
    `byteslice` preserves the receiver's encoding and can produce an invalid UTF-8 `String` from a
    valid one.

## R1 — the `Dexpace::IO` shadowing gate

**The hazard, precisely.** Verified fact 5. The loud case is harmless: a bare `IO.pipe` inside
`module Dexpace` raises `NoMethodError`. The dangerous case is silent and it is exactly the shape
design §3.1 reaches for — "core adapts `#read`-shaped `IO`-likes at the edge because
`Net::HTTP#body_stream=` wants one" is an `is_a?`-shaped test, and `Response#body_string`, which 3b
adds to `lib/dexpace/http/response.rb`, sits inside `module Dexpace` too. That is why the gate cannot
be scoped to `lib/dexpace/io/**`.

**The mitigation that actually matters is not the cop.** It is that **core never writes
`is_a?(IO)`.** Every place 3a inspects a caller-supplied stream it asks `respond_to?`, which is what
`api-design/88e6bf12` asks for anyway ("a public method should accept the narrowest duck-typed
interface it actually uses") and what makes `BufferedSource.wrapping` accept a `StringIO`, an
`IO.pipe` end, a `Tempfile` and a caller's own `#readpartial`-shaped object without a type test. A
cop cannot make a nominal type test correct; it can only stop one from being written.

**The cop extension, decided.**

- **`SHADOWED` gains exactly one constant, `IO`.** `File`, `StringIO` and `Tempfile` are *not* added:
  no `Dexpace::File`, `Dexpace::StringIO` or `Dexpace::Tempfile` constant exists or is created by 3a,
  a bare `File` inside `module Dexpace` resolves to `::File` (verified), and a rule guarding nothing
  only flags correct code. **The reusable rule, stated for every later phase: a constant joins
  `SHADOWED` in the same change that creates the `Dexpace::` constant which shadows it** — never
  earlier, never later.
- **`WATCHED` gains a third entry, the one-segment path `%w[Dexpace]`**, which subsumes phase 2's
  two and makes the rule "inside `module Dexpace`, anywhere, a bare `Thread`, `Queue`, `Mutex`,
  `SizedQueue`, `ConditionVariable`, `JSON` or `IO` must be `::`-qualified". Phase 2 deliberately
  kept **one** `SHADOWED` list for both namespaces rather than one list each, and widening the watch
  rather than adding a per-constant scope keeps that decision intact. The cost is one `::` on every
  `::Thread::Mutex` core already writes in that form.
- **`.rubocop.yml`'s `Include:` widens to `gems/*/lib/**/*.rb`** — every gem, because an adapter gem
  also writes inside `module Dexpace`. `test/**` is deliberately left out: a test file's classes are
  top level, not inside `module Dexpace`, so the cop's own lexical check would find nothing there.
- **The cop must not fire on the constant's own definition site**, and this is the one way to ship it
  broken. `module Dexpace; module IO` is *itself* a bare `IO` inside `module Dexpace`, so a rule that
  looks only at the constant name and the lexical namespace rejects `lib/dexpace/io.rb` — the very
  file that creates the hazard — and every `module IO`/`class Buffer` nesting under it. The cop
  therefore skips a constant node in **definition** position (the name a `module`/`class` node
  declares) and flags only a **reference**. Phase 2 never met this because no file it wrote defined a
  constant named in `SHADOWED`.
- The cop's cases go into phase 0's data-driven suite as phase 2's did. Rejected: a bare `IO`
  *referenced* inside `module Dexpace`, inside `module Dexpace; module IO`, inside
  `module Dexpace; module Http`, and in the compact `module Dexpace::Async` form; plus phase 2's own
  constants under the widened one-segment watch, so the widening itself is asserted rather than
  assumed. Accepted, each producing **no** offense: `::IO` in each of those four `IO` contexts, a
  bare `IO` at the top level with no enclosing module, one inside an unrelated `module Elsewhere`,
  a bare `File`, `StringIO` and `Tempfile` inside `module Dexpace`, the fully written-out
  `Dexpace::IO::Buffer`, and — the two that pin the bullet above — `module Dexpace; module IO` and
  `module Dexpace; module IO; class Buffer` as definition sites.

**Phase 2's accompanying behavioural test is *not* reproducible here, and the reason is that the
hazard is worse, not that it is absent.** Phase 2's test had to *define* a stand-in
`Dexpace::Async::Thread` because core's suite never requires the adapter gem; here `Dexpace::IO` is
defined by core itself, so the hazard is live from the first `require` and there is nothing to
simulate. Reproducing phase 2's shape would mean asserting that Ruby shadows constants, which is
phase 1's "an assertion that a four-reader `Struct` responds to four readers restates the language"
failure. **What 3a asserts instead is the mitigation**: `BufferedSource.wrapping` and
`BufferedSink.wrapping` each accept a real `::IO` (from `IO.pipe`), a `StringIO` and a bare
`#readpartial`/`#write`-shaped object. Stated exactly, because the weaker claim is the true one: it
fails outright if core wrote an unqualified `is_a?(IO)` gate — inside `module Dexpace` that rejects
all three, the real `::IO` included — and it passes for a duck-typed accept and also for a correctly
`::`-qualified `is_a?(::IO)` fast path with a duck fallback. It is a test that the **hazard** is
absent, not a proof of which of the two safe shapes was written; the cop is what forbids the
unqualified form, and `respond_to?` everywhere is what the code review looks for.

**What the cop cannot reach, and where it is recorded.** Verified fact 5's consumer half — a
consumer's own `class C; include Dexpace` silently loses `is_a?(IO)` — is outside every gate this
repository owns. It is filed as **`OI-3`**, it is stated in `Dexpace::IO`'s own YARD block, and the
finding is about `Dexpace::Method`, `Dexpace::Request` and every other flat constant as much as about
`Dexpace::IO`. 3a does not flatten the namespace to avoid it: boundary 10 fixes `Dexpace::IO::`, and
flattening would trade one shadowed constant for four.

## R2 — the `Source#read(dest, count)` primitive

**The name.** `IO-1`'s primitive is **`#read_into(dest, count:)`**, not `#read`. Verified fact 1 is
the whole argument: `#read` and `#readpartial` on a `BufferedSource` are the `IO-16` bridge that
design §3.1 says is satisfied by construction, `IO.copy_stream` drives that bridge with one reused
buffer it expects overwritten, and a tail-appending `#read` would both corrupt the payload and grow
that buffer without bound. Recorded as **P3-1**. `IO-3`'s "a port MAY use whichever argument-error
type is idiomatic" is the specification's own signal that these operation names are the reference's
spelling and not the contract.

**The shape and the four return values.**

`#read_into(dest, count:) -> Integer`, in this order and with the ordering load-bearing:

1. **`IO-3` first, before any I/O.** `count` not an `Integer`, or negative → `Dexpace::InvalidArgumentError`
   naming the argument. `dest` not a `String`, frozen, or not tagged `Encoding::BINARY` → the same
   error, also before any I/O. Rejecting a non-BINARY `dest` is not pedantry: verified fact 4 makes
   the destination's tag depend on the *content* of the payload, so a UTF-8 `dest` produces a buffer
   that is BINARY for an ASCII response and UTF-8 for a non-ASCII one. Rejecting a frozen `dest`
   eagerly is phase 1's finding-3 shape — a `FrozenError` from deep inside is a crash, not a
   rejection.
2. **`IO-42` second, and it has to be above `IO-2` rather than below it.** A closed stream-backed
   source raises `Dexpace::ClosedError` from every read attempt, **count `0` included**. `IO-2`'s
   clause is about an *open* source that is exhausted — "even when the source is already exhausted" —
   so it says nothing about a closed one, and putting the zero-count shortcut first would let
   `read_into(dest, count: 0)` return `0` from a source whose underlying stream is gone, which is
   exactly the use-after-close `IO-42` requires to fail loudly. A `Buffer` takes the in-memory
   exemption here and keeps answering.
3. **`IO-2` third.** `return 0 if count.zero?` — before consulting the buffer and before touching
   the upstream, so a zero-count read on an exhausted source returns `0` and never `-1`. Ruby's own
   readers do not collapse this (verified fact 8), but `IO-2` is a statement about 3a's surface.
4. **Serve from the buffer if anything is buffered**, appending with `dest << chunk` where `chunk` is
   BINARY. Return the count, never more than `count`.
5. **Otherwise fill, then serve.** Return `-1` only when the fill has yielded nothing **and the
   upstream has said it is done**. "Yielded nothing" and "is exhausted" are two different facts and
   collapsing them is how `IO-1`'s "at least 1 when byteCount>0 and the source is not exhausted" gets
   violated — see the empty-chunk rule below.

The sentinel is `-1` and not Ruby's `nil`. `IO-1` fixes it, `IO-17` reads it ("MUST terminate only on
a -1 (EOF) read"), and a foreign source implementing `IO-1` literally would return `-1` — which a
`nil`-testing pump would misread as "one byte transferred". One convention, applied to the portable
vocabulary only; the host-native bridge uses Ruby's, which is P3-2.

**Normalising two EOF sentinels without a rescue on the hot path.** The hot path is *"the bytes are
already buffered"*, and it never touches the upstream at all. `readpartial`'s `EOFError` and
`read`'s `nil` are normalised in **one private hook, `#fill(min_bytes)`**, which:

- is entered only when the buffer is short of what the caller asked for;
- returns `0` immediately, without touching the upstream, once a latched `@upstream_exhausted` flag
  is set — it is set once and never cleared, so the rescue executes **at most once per stream**, not
  once per read;
- calls `upstream.readpartial(n)` when the upstream responds to it (it blocks for at least one byte
  and never over-reads) and `upstream.read(n)` otherwise, rescuing `::EOFError` in the first case and
  testing for `nil` in the second, and setting the flag either way;
- for a `.over`-wrapped body, calls `enumerator.next` and normalises `StopIteration` the same way —
  and **only** `StopIteration`, per the empty-chunk rule below.

So the answer to "without a rescue on the hot path" is structural rather than clever: the rescue is
on the fill path, the fill path is entered only when bytes are genuinely needed, and it is
short-circuited by a flag the moment the upstream has said it is done.

**An empty chunk is not end of stream, and only the `.over` path can produce one.** `#each` yielding
`""` is ordinary — Rack permits it, and `["ab", "", "cd"].each` is the shortest example — so
`enumerator.next` returning a zero-length `String` means "no bytes this time", never "no bytes ever".
`StopIteration` is the **only** end-of-stream signal on that path, and a fill that adds zero bytes
without it must be retried rather than latched. Collapsing the two truncates a body at its first
empty chunk, silently and with a well-formed short read. On the `wrapping` path a zero-length return
**is** treated as exhaustion, and that is a decision rather than an oversight: verified on 3.2.11,
3.4.10 and 4.0.6 that `IO#read(n)`, `StringIO#read(n)`, `IO#readpartial(n)` and
`StringIO#readpartial(n)` never return `""` for a positive `n` — they return `nil` or raise
`EOFError` — so for every reader `Net::HTTP` or a test will hand it, `""` is unreachable; a
caller's own `#readpartial`-shaped object that returns `""` forever is the one shape this reading
would treat as EOF, and treating it as "retry" instead would spin, which is the failure `IO-17`'s
zero-read clause names on the other side of the same contract. `FakeChunked` scripts the empty-chunk
case, and `FakeSource` the zero-read one, for exactly these two reasons.

**Ingress retag, stated once and applied everywhere.** Verified facts 3 and 4 together fix the idiom:
a chunk arriving from an upstream or from a wrapped body is stored as

> the chunk itself when it is **both frozen and already `Encoding::BINARY`**, and `chunk.b` otherwise.

`.b` always returns a fresh unfrozen copy, so it is safe on a frozen chunk where `force_encoding`
raises; keeping an already-frozen BINARY chunk avoids a copy per chunk on the common path and cannot
alias caller-mutable state, because a frozen `String` is not mutable. `force_encoding` appears
nowhere on the ingress path.

## R3 — `IO-6`, stated once, without `SEAM-3`

`IO-6` is a MUST with no chapter prose: outside appendix C the string `IO-6` occurs once in the whole
tree, in the roadmap's gap paragraph, which sends a reader to a chapter that does not carry it
(`OI-2`). Its *bridge* half survives in `docs/product-spec/05-i-o-contracts.md` §5.3 under `IO-16`, a
SHOULD. Both places that state its *wrap* half — design §3.1's "Two ownership rules, deliberately
different" paragraph and the corpus entry `message-bodies/8a1e7a7b` — attribute it to **`SEAM-3`**,
which design §10.1 retires and phase 2 shipped as 🚫. **3a reads `IO-6` out of appendix C and cites
`IO-6` and design §10.12; it does not cite `SEAM-3`, and it files the corpus note that stops the next
reader repeating the attribution.**

**The I/O-layer ownership rule, stated once for this port.**

> **Wrapping takes ownership.** A `BufferedSource` or `BufferedSink` built over a caller-supplied
> stream closes that stream when it is closed. There is **no borrowing variant**, because `IO-6`
> forbids one: a wrapper that did not close its underlying stream would be the exact object the MUST
> prohibits. §3.7's build-versus-borrow split governs components that *hold* a resource — transports,
> executors, pools — and is not a licence to offer a borrowing wrap here.

> **Wrapping bytes owns nothing.** `Buffer.new` and `BufferedSource.of_bytes(string)` own no external
> resource — `IO-6`'s own last sentence — so their close releases only memory.

> **`.over` is the one stated exception**, and it is design §3.1's, not this document's:
> `BufferedSource.over(chunked)` **does not take ownership of the wrapped object**. Closing the
> returned source drains and discards its own buffer and never calls `#close` on what it wrapped,
> because its callers are always downstream of something that already owns the response
> (`message-bodies/f060d944`). This is what removes the one 3a→3b edge that would have run backwards.

> **The bridge inherits the wrap.** `IO-6`'s second sentence — "closing the bridge closes the owning
> source/sink" — is satisfied because in this port **the bridge is the source** (R4). It is asserted,
> not inferred.

> **There is a third rule and it is phase 7's.** `SEAM-20`/`SEAM-21`/`SERDE-3` (`serde/cfbe4e9a`)
> require a codec to read or write a caller-supplied stream fully and close nothing. Phase 3 neither
> implements nor weakens it (boundary 5).

**The factory names carry the rule**, so ownership is a construction-time fact and never a close-time
judgement: `.wrapping` owns, `.of_bytes` and `.over` and `Buffer.new` do not. 3b inverts the rule at
the body layer (`BODY-8`, §10.12) and does not re-decide this half.

**Block forms.** `resource-management/bf5560dc` asks for a block form for every closable resource so
the close runs on any exit path. 3a adopts it exactly where a leak is possible:
`BufferedSource.wrapping(io) { |source| … }` and `BufferedSink.wrapping(io) { |sink| … }` close on any
exit and return the block's value; without a block they return the wrapper and the caller owns the
close. The factories that own nothing get no block form, because there is nothing to leak, and
`resource-management/43a55896`'s "prefer explicit lifecycle ownership — a class that opens a resource
in its constructor exposes a `close` method the caller invokes in an `ensure`" is what the no-block
form already is. Recorded as **P3-12**.

## R4 — whether `IO-16`'s "satisfied by construction" survives `IO-6`

**The claim as design §3.1 writes it is false, and it becomes true after the R2 rename.** §3.1 says
"`IO-16`'s native-stream bridge is satisfied by construction, since a `BufferedSource` already
responds to `#read`, `#readpartial` and `#each`." That holds only if those three carry **Ruby's**
semantics. Under the naive reading — `#read` is `IO-1`'s tail-appending primitive — a `BufferedSource`
responds to `#read` and is *not* a bridge: verified fact 1 shows `IO.copy_stream` handing it one
reused buffer, and a tail-append would concatenate the whole stream into that buffer while writing
ever-growing garbage to the socket. The claim survives because the primitive is renamed, and only
because of that.

**With the rename, three things are true and each is asserted rather than assumed.**

1. **The bridge is the source.** `#read(length = nil, outbuf = nil)`, `#readpartial(maxlen, outbuf = nil)`,
   `#getbyte`, `#readbyte` and `#each` carry Ruby's own conventions. `IO-16`'s "**host-native**" is
   the requirement's own word, so the bridge signals end of stream the host-native way — `nil` from
   `#read` and `#getbyte`, `Dexpace::EndOfStreamError` from `#readpartial` and `#readbyte` — rather
   than with the reference host's `-1`. Recorded as **P3-2**.
2. **`Dexpace::EndOfStreamError < ::EOFError` is what makes it work**, and verified fact 2 is the
   assertion: `IO.copy_stream` terminates cleanly on an `EOFError` subclass from a duck-typed
   `#readpartial`. The test that pins it is an end-to-end `IO.copy_stream(source, sink)` over a
   `BufferedSource`, which is the exact mechanism `Net::HTTP#body_stream=` uses — not a mock of it.
3. **`IO-6`'s second sentence is trivially true and still gets a test.** "Closing the bridge closes
   the owning source/sink" is trivial when the bridge *is* the source — which is precisely why it is
   worth an assertion rather than an inference, because "trivially true" is what a later refactor
   that splits the bridge into its own object would silently break. The test drives the source
   through `IO.copy_stream`, calls `#close` on it, and asserts the wrapped `::IO` reports `closed?`.

**The one place `IO-16` is not satisfied by construction**, stated rather than glossed: its
single-byte clause names an unsigned 0..255 or −1. Ruby's `#getbyte` returns `0..255` or `nil` and
`#readbyte` raises; both are the host-native spelling of the same contract and both ship. The
symmetric writable-stream bridge is `BufferedSink#write(*strings)` returning the byte count, which is
what `IO.copy_stream` requires of a destination (verified fact 10) and whose close is the sink's own.

## Module layout

Every file 3a creates or modifies. `sig/` mirrors `lib/` one file per file and ships inside the gem;
`test/` mirrors `lib/` one file per file and does not ship. Paths under `gems/dexpace-core/` unless
stated.

```
lib/dexpace.rb                              MODIFIED: requires for the tree below
lib/dexpace/closeable.rb                    MODIFIED: #closed? reads under the mutex (IO-38, P3-6)
lib/dexpace/error/stream_error.rb           Dexpace::StreamError
lib/dexpace/error/end_of_stream_error.rb    Dexpace::EndOfStreamError
lib/dexpace/io.rb                           Dexpace::IO, Dexpace::IO::MAX_MATERIALIZED_BYTES
lib/dexpace/io/typed_reads.rb               Dexpace::IO::TypedReads
lib/dexpace/io/typed_writes.rb              Dexpace::IO::TypedWrites
lib/dexpace/io/buffered_source.rb           Dexpace::IO::BufferedSource
lib/dexpace/io/buffer.rb                    Dexpace::IO::Buffer
lib/dexpace/io/buffered_sink.rb             Dexpace::IO::BufferedSink
lib/dexpace/io/tee_sink.rb                  Dexpace::IO::TeeSink

test/support/fake_source.rb                 #read_into only, scriptable
test/support/fake_sink.rb                   #write only, scriptable
test/support/fake_chunked.rb                #each only, scriptable
```

Three files at the repository root, plus one regenerated artifact under `gems/dexpace-core/`:

```
.rubocop/cops/dexpace/qualified_core_constant.rb   MODIFIED: SHADOWED + IO, WATCHED + ["Dexpace"],
                                                             plus the definition-site guard (R1)
.rubocop/test/cops_test.rb                          MODIFIED: the new rejected and accepted cases
.rubocop.yml                                        MODIFIED: Include widened to gems/*/lib/**/*.rb
test/fixtures/surface/dexpace-core.txt              regenerated once, in the last task
```

Nine new `lib/` files — two error classes and seven under `Dexpace::IO` — with nine `sig/` mirrors,
nine `test/` mirrors and three test-support files. Two existing files are modified, `lib/dexpace.rb`
and `lib/dexpace/closeable.rb`, and each has a mirror already.

**`MAX_MATERIALIZED_BYTES` lives in `lib/dexpace/io.rb`**, beside the module whose limit it is. That
file therefore defines a module and one constant nested inside it, which is phase 2's reading of
`module-organization/1828a984` applied again (`Dexpace.close_quietly` beside `Dexpace::Closeable`):
splitting a single frozen `Integer` into its own file to satisfy a rule about constants would be the
letter over the purpose.

## The object model 3a ships

Every public constant, its surface, and the IDs that force the shape. Each name the design's §3 does
not already carry has a Deviation Ledger row, because `NFR-4` locks it at the first release tag.

### `Dexpace::IO` — the namespace and the ceiling

A module holding nothing but `MAX_MATERIALIZED_BYTES` and the four classes and two modules below.
Design §3.1 and §10.2 name `Dexpace::IO::Buffer` and `Dexpace::IO::BufferedSource`, and phase 1's
P1-1 keeps a namespace the design already gave a subsystem, so the namespace is fixed (boundary 10)
and 3a gates the shadowing rather than flattening it (R1).

`MAX_MATERIALIZED_BYTES = 64 * 1024 * 1024` — §10.18's substitution for a host maximum single-array
allocation Ruby does not have, at §3.1's default, "chosen, not derived". **3a ships the constant and
the default and nothing reads it from a keyword**; the operations below read the constant directly.
That is deliberate, and it is deliberately narrower than §3.1's own sentence, which asks for the value
to be "configurable through the same layered chain as every other limit (§8.2) **rather than a frozen
constant**". 3a ships exactly the frozen constant that sentence declines, because there is no layered
chain to read from until phase 5 and the exclusion table gives phase 5 the *configuration source*;
`R5` — which parameter shape carries a value to it — is 3b's. Nothing is foreclosed: adding an
optional keyword later widens a signature rather than narrowing one, so `NFR-4` is not prejudiced
(phase 2's `DEF-28` precedent, applied verbatim), and the constant remains the one ceiling `IO-9` and
`BODY-32` share whatever ends up feeding it.

### `Dexpace::IO::TypedReads` — the read vocabulary (`IO-11`–`IO-16`, `IO-19`–`IO-24`)

A **public** module supplying every typed read over one private hook, `#fill(min_bytes) -> Integer`,
which the includer implements. It is public and not `private_constant` for two reasons that are each
sufficient: the runtime surface snapshot walks each class's `public_instance_methods(false)`, which
does **not** see a method reaching a class through an included module, so a private module would hide
almost the whole of 3a's surface from the gate that exists to see it; and a third-party source
implementation that supplies `#fill` gets the whole vocabulary by including it, which is the Ruby
shape of the reference's `BufferedSource` interface. `Dexpace::Closeable` set the
`initialize_*`-plus-one-hook precedent in phase 2 and this follows it exactly.

| Method | ID | Note |
|---|---|---|
| `#read_into(dest, count:) -> Integer` | `IO-1`, `IO-2`, `IO-3` | R2. Tail-append, `-1` at EOF, `0` for a zero count |
| `#read(length = nil, outbuf = nil) -> String?` | `IO-11`, `IO-16` | Ruby's semantics: overwrites `outbuf`, `nil` at EOF for a positive length, `""` at EOF with no length. With no length it is `IO-11`'s count-less byte-array read exactly |
| `#readpartial(maxlen, outbuf = nil) -> String` | `IO-16` | Ruby's semantics: overwrites, raises `Dexpace::EndOfStreamError` at EOF |
| `#read_exactly(count) -> String` | `IO-12` | Exactly `count` bytes or `Dexpace::EndOfStreamError`; never short |
| `#readbyte -> Integer` / `#getbyte -> Integer?` | `IO-11`, `IO-16` | Raises at EOF / `nil` at EOF |
| `#read_utf8(count: nil) -> String` | `IO-12`, `IO-13` | `count` is a **byte** count; with none, drains |
| `#read_string(encoding, count: nil) -> String` | `IO-13` | Retags the drained BINARY bytes. No replacement policy — that is `HTTP-42`'s, at 3b's single decode boundary |
| `#read_line_utf8 -> String?` | `IO-14` | Hand-implemented, never `#gets`: `$/` is global and universal-newline handling depends on how the `IO` was opened. `\n` and `\r\n` terminate, a lone `\r` is content, a final unterminated line comes back as-is, `nil` when exhausted before any byte. **Unbounded on purpose** — the one **drain-style** read `MAX_MATERIALIZED_BYTES` does not guard, its size being unknown until the terminator is found (P3-4, `OI-5`) |
| `#skip(count) -> void` | `IO-15` | Exactly `count`, `Dexpace::EndOfStreamError` if fewer remain; `skip(0)` a no-op at or after EOF |
| `#eof? -> bool` | `IO-11` | May block while the upstream decides. Ruby's own name for `exhausted()` |
| `#peek -> BufferedSource` | `IO-19` | A non-consuming view over the whole remaining source |
| `#slice(offset:, count:) -> BufferedSource` | `IO-20`, `IO-21`, `IO-23` | Lazy offset overflow, eager negative rejection, offsets composing additively and the window capped at the parent view's own remaining window |
| `#each { |String| } -> void` | §10.2 | Yields BINARY chunks until exhausted, so a source **is** a canonical body representation. Without a block, `to_enum(:each)` |

**`#peek` and `#slice` return a `BufferedSource`**, not a new public type. A view is a `BufferedSource`
constructed in view mode, which makes `IO-23`'s slice-of-a-slice free, keeps the bridge claim true of
views, and adds no `NFR-4`-locked constant. **Both reach that constructor through one internal
entry point; `#peek` is not expressible as a call to `#slice`.** `#slice`'s window is a required
`Integer` `count:` — `IO-21` rejects a negative one eagerly and the RBS types it `Integer` — while
`IO-19`'s peek is "over the **whole remaining** source", a length no stream-backed source knows: the
bytes it covers include ones the upstream has not yet been asked for. Passing the currently buffered
byte count as `count:` would silently truncate a peek over a live response at whatever happened to be
buffered, which is the failure `IO-19` exists to prevent. So `#peek` supplies offset `0` and an
**unbounded** window and `#slice` supplies the caller's two integers, and only `#slice` validates
them.

**The view retention rule, which the specification does not state and 3a therefore does.** A view
pins the parent's cursor position at construction and reads a window relative to that pin, driving
the parent's `#fill` without advancing the parent's cursor (`IO-19`, `IO-20`). **The parent holds
nothing back for a view.** Its retention floor is its own cursor: it drops what it has itself
consumed and keeps what it has not, and no pin raises that floor. Two consequences, and they are two
halves of one rule rather than a rule and an exception:

- Bytes a view reads *ahead* of the parent's cursor are retained, because the parent has not consumed
  them — so a view over a multi-gigabyte source that a caller drives to the end does retain
  proportionally. That is inherent to `IO-19`'s "over the whole remaining source" and is bounded in
  practice because every caller of `#peek` in this SDK is a bounded preview.
- **If the parent's own cursor passes the next byte a live view still needs — its pin plus what it
  has already pulled — that view's later reads fail loudly with `Dexpace::ClosedError` rather than
  returning bytes from somewhere else**; `IO-22`'s "never returning stale or arbitrary bytes" is the
  anchor. Bytes the view has already read are behind it and the parent may pass them freely.

Retention therefore needs no pin bookkeeping at all — the parent's cursor is the floor, and the view
registry exists only for `IO-22`/`IO-38`'s invalidation on close (`OI-4`). Recorded as **P3-5**.
Closing a view releases its registration (`IO-22`).

### `Dexpace::IO::TypedWrites` — the write vocabulary (`IO-4`, `IO-5`, `IO-13`, `IO-17`, `IO-18`)

The symmetric public module, over one private hook `#deliver(string)` which pushes bytes one level
toward the includer's destination.

| Method | ID | Note |
|---|---|---|
| `#write_from(buffer, count:) -> void` | `IO-4` | Removes exactly `count` bytes from the **head** of a `Dexpace::IO::Buffer`; if it holds fewer, `Dexpace::StreamError` rather than a partial write |
| `#write(*strings) -> Integer` | `IO-16` | The host-native writable bridge: returns the byte count, which is what `IO.copy_stream` needs of a destination |
| `#write_all(source) -> Integer` | `IO-17` | Pumps to exhaustion through `#read_into`, terminating only on `-1`, returning the total. **A read of `0` for a positive requested count raises `Dexpace::StreamError`** — never tolerated as EOF, never spun on |
| `#write_utf8(string, range: nil) -> void` | `IO-13` | `range` is a character range over the `String`, the reference's substring form |
| `#write_string(string, encoding:) -> void` | `IO-13` | The symmetric explicit-charset write |
| `#emit -> self` / `#flush -> self` | `IO-5`, `IO-18` | `#emit` is the cheap one-level hand-off; `#flush` forces all the way out |

**`IO-17`'s zero-read check is applied unconditionally**, not only to a "foreign" source. The
requirement scopes it to a non-adapter-native source; §10.1 retired the adapter, so "adapter-native"
has no subject in this port, and a correct source never returns `0` for a positive count anyway — so
the check never fires for a native one and needs no native/foreign predicate, no marker module and no
`.conforms?`. The symmetric rule applies on the write side: an underlying `#write` that returns fewer
bytes than it was handed is a sink-contract violation and raises `Dexpace::StreamError`.

### `Dexpace::IO::Buffer` — the FIFO (`IO-7`–`IO-10`, `IO-41`, `IO-42`)

Includes `TypedReads`, `TypedWrites` and `Dexpace::Closeable`. An `Array` of BINARY `String` chunks
with a head byte offset, so draining is O(1) amortised (§3.1). Its `#fill` returns `0` — a buffer has
no upstream — and its `#deliver` appends to its own chunk list, which is what makes it "simultaneously
a source and a sink" (`IO-7`).

- `.new` — public, no arguments, a fresh independent empty buffer.
- `#bytesize` — `IO-7`'s "size". Named for bytes because everything here is bytes and `String#bytesize`
  is the precedent.
- `#snapshot -> String` — `IO-8`. A fresh, **unfrozen**, independent BINARY copy that neither consumes
  nor mutates the buffer. Unfrozen because `IO-8`'s "and vice versa" presumes the caller may mutate
  it (**P3-10**). Guarded by `MAX_MATERIALIZED_BYTES` (`IO-9`).
- `#clear -> void` — `IO-10`.
- `#copy_to(other, offset: 0, count: nil) -> void` — `IO-10`. Copies a window into another `Buffer`
  without consuming or mutating this one, defaulting to "from `offset` through end", rejecting a
  negative `offset` or `count` and a window past the end with `Dexpace::InvalidArgumentError`
  (`IO-3`'s eager rejection, and appendix C's own "a port MAY use whichever argument-error type is
  idiomatic").
- `#emit` / `#flush` — return `self`, `IO-18`'s explicit MAY for a pure in-memory buffer.
- `#close` — the latch flips and **the read/write surface stays usable**, which is `IO-42`'s in-memory
  exemption, so snapshot-after-close body logging still works. Its close **still invalidates every
  view derived from it** (`IO-42`, `IO-22`, `IO-38`).

### `Dexpace::IO::BufferedSource` — the reader (`IO-6`, `IO-11`–`IO-24`, `IO-41`, `IO-42`)

Includes `TypedReads` and `Dexpace::Closeable`. Holds the same chunk-store shape plus an optional
upstream, a frozen `@owns_upstream`, a frozen view mode, and a registry of derived views.

- `.wrapping(io)` and `.wrapping(io) { |source| … }` — **takes ownership** (`IO-6`). Accepts anything
  responding to `#readpartial` or `#read`; validated by `respond_to?`, never `is_a?` (R1).
- `.of_bytes(string)` — an **independent copy** of the input, so a later mutation of the caller's
  `String` does not change the source and vice versa (`IO-30`'s surviving behavioural clause). Owns
  no external resource.
- `.over(chunked)` — §3.1's single inverse adapter over the §10.2 duck type, pulling from `#each` on
  demand so no read-ahead accumulates. **Owns nothing** (R3).
- `.new` is `private_class_method`. Ownership must not be settable through an unnamed argument, which
  is the whole point of making it a construction-time fact (**P3-11**). The view constructor the two
  view methods reach is internal — no RBS signature, no YARD block, an underscore-prefixed name — so
  it is not public surface by this repository's own definition of the word.
- `#owns_upstream? -> bool` and `#view? -> bool` — the two frozen construction-time facts, readable.
  They are the only public instance methods this class defines that do not arrive through a module,
  and they carry a Deviation Ledger row for that reason (**P3-8**): `#owns_upstream?` is what makes
  `IO-6`'s ownership assertable from a test without `instance_variable_get`, and `#view?` is what
  `IO-22`'s slice-versus-parent close rule is asserted against.
- `#close` — the latch, then `#release`: drop the buffer, deregister this source from its parent if
  it is a view, invalidate every view derived from it, and close the upstream **only if
  `@owns_upstream`**. `@owned` on `Closeable` is always `true` here, because a source always owns its
  own buffer; whether it also owns the upstream is the separate frozen fact the factory names set.

**`owned:` is `true` on every `Closeable` 3a constructs**, and that is stated rather than left to a
reader who copies phase 2's nearest shape. Phase 2's `Bridge::AsyncOver`/`SyncOver` pass
`owned: false` because they hold a caller-supplied transport they must never close — and
`Closeable#close` skips `#release` entirely when `owned?` is false. Under `owned: false` a `Buffer`'s
close would never invalidate its views (`IO-42`, `IO-22`) and a `TeeSink`'s close would never reach
its primary (`IO-29`), in both cases silently. Every 3a instance owns something it must release, so
every one of them is `owned: true`, and the caller-supplied thing a `BufferedSource` may or may not
own is carried by the separate `@owns_upstream` fact above rather than by `Closeable`'s flag.

### `Dexpace::IO::BufferedSink` — the writer (`IO-4`, `IO-5`, `IO-6`, `IO-16`–`IO-18`, `IO-41`, `IO-42`)

Includes `TypedWrites` and `Dexpace::Closeable`. `#deliver` stages bytes and writes them through to
the underlying stream.

- `.wrapping(io)` and `.wrapping(io) { |sink| … }` — **takes ownership** (`IO-6`). Accepts anything
  responding to `#write`.
- `.new` is `private_class_method`, for the reason above.
- `#close` — the latch, then flush what is staged and close the underlying stream.

### `Dexpace::IO::TeeSink` — the mirror (`IO-25`–`IO-29`, `IO-40`)

Its own class including `TypedWrites` and `Dexpace::Closeable`, **not** a `BufferedSink` subclass:
`IO-29` makes its flush, close and emit forward to the primary only, so inheriting a sink's lifecycle
and overriding three quarters of it would be inheritance used as a shortcut. §3.1 already says the
tee is hand-built rather than assembled from `IO.pipe` or `IO.copy_stream`.

- `.new(primary:, tap_limit: Float::INFINITY)` — public. `IO-26`'s "default limit MUST be effectively
  unbounded" is `Float::INFINITY`; a limit of `0` mirrors nothing while forwarding everything.
- `#deliver(string)` mirrors into the tap **before** forwarding to the primary (`IO-27`), stops
  copying into the tap once `tap_limit` is reached while the full untruncated payload continues to
  the primary (`IO-25`, `IO-26`), and **clears its staging buffer in an `ensure`** so a failed primary
  write leaves no stale bytes to prepend (`IO-27`). An `ensure` and not a `rescue`, so nothing is
  swallowed — which is also `IO-40`'s "MUST NOT swallow OR duplicate the wrapped stream's
  cancellation/interrupt handling" honoured structurally, and `resource-management/346deaec`.
- `#flush`, `#emit`, `#close` — forward to the **primary only**, leaving the tap intact for later
  snapshotting (`IO-29`).
- `#tap_snapshot -> String`, `#tap_bytesize -> Integer`, `#clear_tap -> void` — the tap is readable
  only through a fresh copy. `#clear_tap` exists because `BODY-18` requires the tap cleared at the
  start of every write of the wrapped body; it is not a lifecycle method and `IO-29` does not reach
  it.
- **`#buffer` is defined and raises** `Dexpace::StreamError` with a message directing the caller at
  the typed write methods (`IO-28`). It is defined rather than absent so the failure is that message
  and not a `NoMethodError`. Design §10.10 already records the honest position: the prohibition
  cannot be language-enforced, `instance_variable_get` reaches anything, and 3a does not build a fake
  proof that it cannot.

### The error classes

| Condition | Class | IDs |
|---|---|---|
| Negative or non-integer count, out-of-range window, frozen or non-BINARY destination, unknown charset name | `Dexpace::InvalidArgumentError` — **phase 1's, unchanged** | `IO-3`, `IO-10`, `IO-21` |
| End of stream on an exact-count, single-byte or skip read | `Dexpace::EndOfStreamError < ::EOFError`, includes `Dexpace::Error` | `IO-11`, `IO-12`, `IO-15`, `IO-16` |
| Source holds fewer bytes than a write demands; a foreign source's zero read; a short underlying write; materialisation over the ceiling; `IO-28`'s buffer handle | `Dexpace::StreamError < ::IOError`, includes `Dexpace::Error` | `IO-4`, `IO-9`, `IO-17`, `IO-28` |
| Read, write, flush or emit after close on a stream-backed instance; a read from a closed or invalidated view | `Dexpace::ClosedError` — **phase 2's, first raise site here** | `IO-22`, `IO-24`, `IO-42` |

`Dexpace::EndOfStreamError` inherits `::EOFError` because verified fact 2 makes that load-bearing, and
because Ruby's own readers raise `EOFError` for exactly this condition (verified fact 8).
`Dexpace::StreamError` inherits `::IOError` because `IO-4`, `IO-17` and `IO-42` each literally say "an
I/O error" and `::IOError` is Ruby's root for that family — **not** because of `XCUT-4`, which is
about the error *taxonomy's* two top-level branches and requires a transport error to "report itself
as always-retryable at the error level". A stream-contract violation is not a transport error and
must not make that claim, so `Dexpace::StreamError` is a sibling of phase 8's
`Dexpace::TransportError` inside Ruby's I/O family and never a subclass of it. `IO-42`'s "I/O error"
for use-after-close is served by phase 2's `Dexpace::ClosedError`, which is a `::StandardError` and
not an `::IOError` — read as "a loud, distinct, non-EOF failure", which is what the requirement's own
rationale asks for and what `IO-24`'s "distinct from normal EOF" makes structural. Recorded as
**P3-3**. `Dexpace::IOError` and `Dexpace::EOFError` are never defined, for phase 1's
`Dexpace::ArgumentError` reason.

**Two message helpers ship on `Dexpace::StreamError` as class methods** —
`.short_transfer(transferred:, expected:)` and `.zero_read(requested:)` — because `BODY-13` requires
the short-write message form of `BODY-10`/`HTTP-39` and the zero-read message form of `BODY-25` to
come from **one** helper "so the message form cannot diverge", and 3a is the phase that owns the I/O
half. 3b calls them.

### The RBS interfaces

Three, in `sig/dexpace/io.rbs`. They carry no runtime constant, so the surface snapshot cannot see
them and the `sig` diff is their only gate — which is why each is named deliberately.

- **`Dexpace::IO::_Source`** — `def read_into: (String, count: Integer) -> Integer`. The primitive
  `#write_all` accepts (`IO-17`).
- **`Dexpace::IO::_Sink`** — `def write: (*String) -> Integer`. The primitive a destination satisfies.
- **`Dexpace::IO::_Chunked`** — `def each: () { (String) -> void } -> void`. **This is design §10.2's
  canonical body representation as a type.** It is named `_Chunked` and not `_Body` deliberately: 3b's
  body type is richer — media type, content length, `#replayable?`, a single write-to-sink operation —
  and naming both `_Body` would put two meanings on one name across the sub-phase boundary the cut
  exists to keep clean. 3b's interface can include this one.

`NFR-11`'s scan sees no constant outside `Dexpace::` in any of them, and 3a's whole public surface
names no stdlib type but `String`, `Integer` and `Encoding`.

## The ten spec-forced boundaries, honoured

1. **`IO-40` — 3a owns no clock and no deadline.** No method in 3a takes a timeout, a deadline or a
   `Cancellation`; the only blocking call in the whole sub-phase is the upstream's own
   `#readpartial`/`#read` inside `#fill`, and it blocks for exactly as long as the transport that
   owns the socket allows. `DEF-28`'s `deadline:` keyword stays off the pivot until phase 5, and 3a
   does not reach for it. The corpus's per-call-timeout rules are answered by the note above.
2. **`IO-37` with `IO-38` — single-threaded, close being the one exception.** No instance carries a
   lock over its read or write path; the **only** synchronised state in 3a is the close latch, read
   once per public call through `Dexpace::Closeable`'s mutex (P3-6) and never held across a read, a
   fill, a drain or a `#release`. 3a does not make instances thread-safe: that would over-satisfy a
   MUST that says the opposite and would hide a caller's own error. The flag is not fiber-local.
   §3.1's mechanism is honoured exactly — a `Thread::Mutex`, not the GVL, "so the guarantee survives
   JRuby and TruffleRuby" — and `DEF-33` records that no such interpreter is in the matrix.
3. **`IO-42`'s asymmetry, in both directions.** A stream-backed `BufferedSource`/`BufferedSink`/
   `TeeSink` raises `Dexpace::ClosedError` from every read, write, flush and emit after close. A
   `Buffer` does **not**: its own read/write surface stays live after close, because an in-memory
   close frees nothing and snapshot-after-close logging depends on it. **And a `Buffer`'s close still
   invalidates every view derived from it.** Both directions have their own test and neither may be
   simplified into the other; `api-design/79b5d745` is why the asymmetry is documented at the method
   rather than left looking like an oversight.
4. **`IO-28` — no reader is exposed and any method that would hand one out raises.** `#buffer` on
   `TeeSink` is defined solely to raise with the actionable message; neither `BufferedSink` nor
   `TeeSink` exposes any other route to the backing store, and the tap is reachable only through
   `#tap_snapshot`'s fresh copy. §10.10's admitted hole is restated, not closed and not faked. 3b
   restates the same mechanism at `BODY-37` and builds nothing new.
5. **`IO-6` with `BODY-8`, per §10.12** — R3 above states the I/O half once, cites `IO-6` and §10.12
   rather than `SEAM-3`, and names `.over`'s exception in the same place. 3a does not touch the body
   half, and it does not generalise its rule over the codec's, which is phase 7's and opts out of
   both.
6. **`BODY-4`'s three declines** are 3b's and are not touched.
7. **`HTTP-42`'s single decode boundary.** `#read_string` and `#read_utf8` retag; they apply no
   replacement policy and no charset default. The one decode boundary stays `Response#body_string` in
   3b.
8. **`IO-9`/`BODY-32`'s `MAX_MATERIALIZED_BYTES`** — one constant, one ceiling, owned here and cited
   by 3b. §10.18's substitution and §3.1's 64 MiB default are adopted as written, "chosen, not
   derived".
9. **The retirement of the byte-stream provider seam is settled.** 3a creates no fourth registry, no
   factory and no installation call, and its eight 🚫 rows cite §10.1 rather than re-arguing it. The
   one place the retirement leaves a behavioural residue — `IO-30`'s "the byte-array-wrapping source
   MUST be an independent copy of the input" — is kept as a property of `.of_bytes` even though the
   ID is 🚫, because it is a behaviour and not apparatus.
10. **`Dexpace::IO::` is fixed.** 3a gates the shadowing hazard (R1) and does not flatten the
    namespace; flattening would trade one shadowed constant for four and contradict P1-1.

## §7.1 applied — where the `Enumerator` rule bites in 3a

§7.1's rule, verified again here on all three interpreters (fact 12): **resource acquisition and
release never live inside an `Enumerator` block; the engine owns the resource in its own scope and
exposes `#close`.** It reaches 3a before it reaches phase 7, and it bites in exactly two places.

**`BufferedSource.over(chunked)` drives the wrapped object's `#each` externally.** Pulling on demand
means `chunked.to_enum(:each)` and `#next`, and a source closed before exhaustion abandons that
enumerator with its `ensure` unrun. **Nothing core owns leaks, and that is a consequence of `.over`
owning nothing** (R3): the enumerator holds the caller's body, and the caller's body is owned by
whoever created it. What 3a does about the residue is document it rather than paper over it —
`.over`'s YARD block states that a `#each`-shaped object holding a resource must expose `#close` and
be closed by its owner, because `.over` will not, and that the abandonment case leaves that object's
own `ensure` unrun. `#rewind` does not run it either (verified in the segmentation design). No
mechanism in Ruby closes this, and 3a does not pretend one does.

**Core's own `#each`-shaped producers hold their resource on the object, never in the block.**
`BufferedSource#each` and `Buffer#each` are ordinary `yield` loops over state that lives on the
instance, with `#close` on the instance. So `source.to_enum(:each)` abandoned mid-`#next` leaks
nothing that `#close` would not still release — which is precisely what makes it safe to return an
`Enumerator` from `#each` without a block at all. Stated here rather than rediscovered when phase 7
hands a source to a pagination engine.

## Encoding, stated once for 3a

- **Bytes on the wire are always `Encoding::BINARY`**, verified the same object as `ASCII_8BIT`.
  Every chunk stored, every `String` returned by `#read`, `#readpartial`, `#read_exactly`, `#snapshot`
  and `#each` is BINARY.
- **Core retags on ingress rather than trusting a declared charset** (`io-and-byte-streams/d2b47c89`).
  The idiom is R2's: keep the chunk when it is frozen and already BINARY, `#b` it otherwise. Never
  `force_encoding` on the ingress path — verified fact 3.
- **`#read_into` requires a BINARY destination** and rejects anything else eagerly, because verified
  fact 4 makes the result's tag depend on the payload's content.
- **The only decode in 3a is a retag.** `#read_utf8` and `#read_string(encoding)` set the tag the
  caller named and validate nothing; `#valid_encoding?` is the caller's question and `HTTP-42`'s
  replacement policy is 3b's, at the one decode boundary §3.1 permits.
- **`IO-14`'s line reads return UTF-8-tagged strings** with the terminator consumed and not returned,
  hand-implemented over the byte buffer so the rule survives a slice-window boundary.

## The interface surface 3b consumes

The load-bearing half of the cut. The segmentation design names eight 3a→3b edges; each is pinned
here to a concrete surface, and **3b may rely on exactly this and must state it in its own
Prerequisite section rather than inherit it by habit.**

| 3b requirement | What it gets from 3a |
|---|---|
| `BODY-17`–`BODY-21`, `BODY-37` — the request-logging tee | `Dexpace::IO::TeeSink.new(primary:, tap_limit:)`, `#write`, `#write_from`, `#write_all`, `#emit`, `#flush`, `#close` (primary only), `#tap_snapshot`, `#tap_bytesize`, `#clear_tap` for `BODY-18`'s per-attempt reset, and `#buffer` raising for `BODY-37` |
| `BODY-3`/`HTTP-37` — materialize-once | `Dexpace::IO::Buffer.new`, the whole `TypedWrites` surface for the drain, `#snapshot`, `#bytesize`, and the whole `TypedReads` surface for the replay |
| `HTTP-39`/`BODY-10`, `BODY-13`, `BODY-25` — exact-length copy and the shared message form | `#read_exactly(count)`, `#write_all(source)` with `IO-17`'s zero-read rule, and **`Dexpace::StreamError.short_transfer(transferred:, expected:)` / `.zero_read(requested:)`** — the one helper `BODY-13` requires so the message form cannot diverge |
| `BODY-22`–`BODY-29` — the response-logging drain | `#peek`, `#slice(offset:, count:)`, `Dexpace::Closeable`'s latch for `BODY-27`'s close-once guard, and `Buffer`'s post-close readability for `BODY-28`'s "the captured buffer outlives the wrapper's close" |
| `BODY-32`, `BODY-33` — the capped preview | `Dexpace::IO::MAX_MATERIALIZED_BYTES`, cited and not re-derived. One ceiling |
| `HTTP-41`/`BODY-14`, `BODY-15` — the response body | `BufferedSource.wrapping(io)` with its ownership, `#close`, `#closed?`, and `IO-42`'s stream-backed rejection |
| `HTTP-42` — the charset decode | `#read_string(encoding, count: nil)` and `#read_utf8(count: nil)` as primitives. 3b adds the policy and the default, not a second decode site |
| `BODY-8` — the body-layer ownership rule | `IO-6`'s I/O-layer half stated once (R3), the factory-name convention that carries it, and `.over`'s exception. 3b inverts it deliberately and re-decides nothing |

Two further things 3b consumes without an edge in that table: **`Dexpace::IO::_Chunked`**, the §10.2
representation as a type its own body interface can include, and **`BufferedSource#each`**, which is
what makes a source itself a canonical body representation.

## Testing strategy

`test/` mirrors `lib/` one file per file; each file's header comment names the requirement IDs it
exercises and a non-obvious branch names the ID that forced it. Every suite subclasses
`DexpaceTestCase`, so a warning raised by code under test fails the test that triggered it.

**No transport is needed at all.** Roadmap cross-cutting constraint 4 puts phases 1 through 7 on an
in-memory fake transport; 3a touches no transport, so the constraint is satisfied trivially and the
`SEAM-11`/`SEAM-16` fakes phase 2 built are not required here.

**What stands in for a real stream, and why it is not a stub.** `StringIO` (allowlisted, `test/` only)
and `IO.pipe` (core Ruby, no `require`) give genuine EOF, genuine blocking and genuine close
semantics — including the `IOError` a closed handle raises (verified fact 9) — without a socket.
`IO.pipe` in particular is what makes the `IO-38` cross-thread test real rather than simulated: a
reader really does block.

**The three fakes, in `gems/dexpace-core/test/support/`**, following phase 2's precedent and its four
reasons, required explicitly by the suites that use them and never from `test_helper.rb`. Each exists
because no real stream can produce the behaviour the requirement is about:

- **`FakeSource`** — implements `#read_into` and nothing else, scriptable to return `0` for a positive
  count. That is `IO-17`'s source-contract violation, and no real Ruby stream will produce it.
- **`FakeSink`** — implements `#write`, scriptable to return a short count and to raise partway
  through, which is what `IO-27`'s "clears its staging buffer even on a failed primary write" and the
  short-underlying-write rule need.
- **`FakeChunked`** — implements `#each`, scriptable to yield frozen literals, non-BINARY strings, an
  **empty chunk between two non-empty ones**, and a body whose `#each` carries an `ensure`: the
  encoding rule, the empty-chunk rule above and §7.1's residue, in one double. The empty-chunk case
  is the one a real `StringIO` or `IO.pipe` cannot produce, which is why it needs a fake at all.

`DEF-29`'s condition — a consumer outside `dexpace-core` — is still unmet; these three strengthen the
row without meeting it.

**The concurrency tests, which are the ones a reader would otherwise write wrong.**

| Case | Asserted |
|---|---|
| Two fibers of one thread interleaving reads on one `BufferedSource` | No `ThreadError`. This is the proof that no lock is held across a read: verified fact 7 shows a mutex held across a fiber suspension raises for the second fiber, so the test fails loudly under the bug it exists to catch |
| A view being read on thread B while thread A closes the parent, sequenced through a `Thread::Queue` | B's next read raises `Dexpace::ClosedError` — never stale bytes, never a torn read (`IO-38`, `IO-22`) |
| **P3-6's mechanism**: one fiber holds the instance's close mutex across a `Fiber.yield`, a second fiber then calls `#closed?` | `ThreadError`. This is the **only** assertion in 3a that distinguishes the synchronised reader from phase 2's, and it fails against phase 2's — verified fact 7 is what makes it possible. Everything else about `IO-38` passes with or without the lock on every CRuby row, which is what `DEF-33` records. A one-line body change with no signature change is invisible to `gates:sig_diff`, so this assertion is the only thing standing between P3-6 and a silent revert |
| A `#release` that reads `#closed?` | Returns `true` and does not deadlock — the proof that the mutex is held across the flip and **not** across `#release`, which a non-reentrant `Thread::Mutex` would turn into `ThreadError` (verified fact 7's second half) |
| `#close` called from two threads on one source | `#release` runs exactly once, both callers return, the upstream is closed at most once (`IO-41`) |
| A `#release` that raises | The latch is still flipped, the failure propagates once, a second `#close` is a no-op |

**The bridge tests, which prove R4 rather than restating it.**

| Case | Asserted |
|---|---|
| `IO.copy_stream(source, sink)` over a `BufferedSource.wrapping(pipe_read_end)` | The bytes arrive intact. This is the exact call `Net::HTTP#send_request_with_body_stream` makes |
| `Dexpace::EndOfStreamError` ancestry | `< ::EOFError`, with a comment naming verified fact 2 — without it `copy_stream` propagates instead of terminating |
| `#read(2, buf)` and `#read_into(buf, count: 2)` on the same source with the same non-empty `buf` | The first **overwrites**, the second **appends**. One test, two assertions, so a later "simplification" that merges them turns red |
| `IO.copy_stream` through the source, then `#close` | The wrapped `::IO` reports `closed?` — `IO-6`'s bridge clause asserted, not inferred |
| `#getbyte` at EOF / `#readbyte` at EOF | `nil` / raises. `IO-16`'s host-native spelling |

**The encoding tests.** Every one uses **non-ASCII** content, because verified fact 4 makes an
ASCII-only fixture pass under the bug.

| Case | Asserted |
|---|---|
| A `FakeChunked` yielding frozen `# frozen_string_literal: true` literals | No `FrozenError` escapes; every buffered chunk is BINARY |
| A `FakeChunked` yielding a UTF-8 `"é"` chunk | The buffer and every read result are BINARY, not UTF-8 |
| `#read_into` with a UTF-8 destination / a frozen destination | Rejected with `Dexpace::InvalidArgumentError` before any I/O |
| `#read_string(Encoding::ISO_8859_1)` and `#read_utf8` round trips | `IO-13`'s own conformance step, non-ASCII both ways |
| A `StringIO`-backed source read on 3.2 and on 3.4+ | Identical BINARY results, which is verified fact 11 pinned rather than assumed |

**The ceiling tests (`IO-9`).** The guard is checked against the **requested or known** byte count
before anything is allocated, so `#read_exactly(MAX_MATERIALIZED_BYTES + 1)` and a **read** from
`#slice(offset: 0, count: MAX_MATERIALIZED_BYTES + 1)` both refuse while allocating nothing.
Constructing that slice must still **succeed** — `IO-21` makes over-range slice construction lazy and
rejects only a negative offset or count eagerly — so the ceiling fires on the read and never on the
construction, and a separate test asserts exactly that ordering. `#copy_to` is not a ceiling case at
all: it materialises nothing, and an out-of-range window there is `IO-10`'s
`Dexpace::InvalidArgumentError`. **Three reads sit outside the guard, deliberately, and for two
different reasons — stated rather than left silent, because a reader who found them would otherwise
read the omission as an oversight.** `#read(length)` and `#readpartial(maxlen)` are left where `IO-9`
itself leaves them: "plain (non-slice) exact-count buffered reads instead inherit whatever bounds
check the underlying stream library performs". P3-4 widens the SHOULD over `#read_exactly` and not
over those two, and the distinction is the **provenance of the count**, not its size — `#read_exactly`
is the read `HTTP-39`/`BODY-10`'s exact-length copy drives, so its count arrives from the wire as a
declared length, while `#read(length)` and `#readpartial(maxlen)` take a number the calling code
chose. A guard earns its place where a hostile peer picks the number. **`#read_line_utf8` is outside
for the other reason**: it is the one **drain-style** read the guard does not cover — `#read` with no
count, `#read_utf8` and `#read_string` all drain and all are guarded, incrementally, as the result
grows. A line read has no count at all and no end but a terminator that may never arrive. `IO-14`
fixes no maximum line length, `IO-9`'s SHOULD names `snapshot()` and length-bounded slice reads and
nothing else, and the only consumer in this SDK that reads lines from a stream an attacker controls
is phase 7's SSE machine, whose own cap `SSE-11` requires and design §10.18 catalogues alongside this
one. So the line read materialises whatever the next terminator is away, a caller that hands it a
terminator-free multi-gigabyte stream gets a multi-gigabyte `String`, and the bound belongs to the
caller. Recorded as `OI-5` so the choice is visible to phase 7 and to a release decision rather than
being rediscovered as a `#read_utf8` inconsistency. **One test does allocate**:
a `Buffer` built just over the ceiling,
asserting `#snapshot` refuses with a message naming the streaming alternative. It costs one 64 MiB
allocation, once per run per matrix row, and it is the only test in 3a that allocates anything
large — stated so the plan does not quietly drop it.

**Property tests, bounded** (`testing/f36a19cd`, phase 0's `#sample(count:, seed:)`): N random BINARY
chunks written through the sink surface and read back through the source surface, asserting FIFO
order and byte equality (`IO-7`); `#read_line_utf8` over generated inputs mixing `\n`, `\r\n`, a lone
`\r` and an unterminated tail (`IO-14`); `#slice` composition over random offsets and budgets, with
slice-of-a-slice asserted additive and capped (`IO-23`).

**Negative tests at every error boundary** (`testing/62f8f4ec`): each raises the expected class,
carries a message naming the offending value, and leaves no partial side effect — a buffer is still
usable after a rejected `#copy_to`, a sink after a rejected `#write_from`, a source after a rejected
`#read_into`.

**Visibility is asserted with `respond_to?`, never `assert_predicate`** — phase 1's finding, which
bites here because `#eof?` and `#closed?` are public predicates on objects with private hooks.

**`IO-42`'s two directions get two tests that fail in opposite ways**, because a single "it is frozen
after close" test would pass over either error.

**The cop's cases** go into phase 0's data-driven `.rubocop/test/cops_test.rb` as phase 2's did, with
the accepted half proving the cop does not reject every occurrence of the name.

## Design §3 Addendum — what this phase adds to §3.1

Design §3 is frozen and is not edited here. Two additions, and they are recorded in different
places on purpose. **A1 is a deviation** — the port's method names depart from what §3.1's sentence
assumes — and carries **P3-1**. **A2 is not a deviation and gets no ledger row**: nothing about this
port's behaviour departs from the reference contract there, the rule §3.1 states is implemented
exactly as stated, and only its *citation* is wrong. That is a finding about the design document,
and it is recorded where findings go — `OI-2`, plus the corpus note against
`message-bodies/8a1e7a7b` so the next reader of the corpus does not repeat the attribution. Filing a
`P3-<n>` row for it would put a documentation erratum in the register that audits behavioural
departures.

| Addendum | What §3.1 says | What phase 3a builds |
|---|---|---|
| **A1 — the bridge and the primitive are different methods** | "`IO-16`'s native-stream bridge is satisfied by construction, since a `BufferedSource` already responds to `#read`, `#readpartial` and `#each`" | True only once `IO-1`'s primitive is renamed `#read_into`. Verified: `IO.copy_stream` — what `Net::HTTP#send_request_with_body_stream` calls — hands `#readpartial` one buffer it reuses across every call and expects overwritten, on 3.2.11, 3.4.10 and 4.0.6. `#read`/`#readpartial`/`#getbyte`/`#each` carry Ruby's semantics; `#read_into` carries `IO-1`'s |
| **A2 — the ownership rule's citation** | "At the I/O layer, wrapping takes ownership … (**SEAM-3**)" | The surviving normative home is **`IO-6`**, a MUST. `SEAM-3` is retired by §10.1 and was shipped 🚫 by phase 2; §10.12 depends on `IO-6` without naming it. Every 3a citation of the rule names `IO-6` and §10.12. `OI-2`, and a corpus note against `message-bodies/8a1e7a7b` |

## Deviation Ledger

Each row is consolidated into design §10 and audited by `docs/deviations.md`. Numbering continues
from the phase-3 segmentation design, which left the ledger empty.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P3-1 | `IO-1`'s primitive is **`#read_into(dest, count:)`**, not `#read` | `IO-1`, `IO-16`; design §3.1 | `IO.copy_stream` — the exact call `Net::HTTP#send_request_with_body_stream` makes — drives a duck-typed source through `#readpartial(len, buf)`, or `#read(len, buf)` when there is no `#readpartial`, with **one buffer object reused across every call** and expected overwritten (verified on 3.2.11, 3.4.10, 4.0.6). A tail-appending `#read` would corrupt every streamed upload and grow that buffer without bound. Appendix C's operation names are the reference's spelling; `IO-3`'s own "a port MAY use whichever argument-error type is idiomatic" is the specification signalling as much. Addendum §3-A1 |
| P3-2 | `IO-16`'s bridge signals end of stream the **host-native** way — `nil` from `#read`/`#getbyte`, `Dexpace::EndOfStreamError` from `#readpartial`/`#readbyte` — not with `-1` | `IO-16` | The requirement's own word is "host-native", and `-1` is the reference host's `InputStream` convention. `Dexpace::EndOfStreamError < ::EOFError` is load-bearing: verified that `IO.copy_stream` terminates cleanly on an `EOFError` **subclass** from a duck-typed `#readpartial` on all three interpreters. The portable vocabulary keeps `IO-1`'s `-1` |
| P3-3 | `IO-42`'s "I/O error" for use-after-close is **`Dexpace::ClosedError`** — phase 2's `::StandardError` — rather than a new `::IOError` subclass | `IO-42`, `IO-22`, `IO-24`; `SEAM-15` | Phase 2 shipped the class, the rule and no raise site; 3a is its first caller. Read as "a loud, distinct, non-EOF failure", which is what `IO-42`'s rationale asks for and what `IO-24`'s "distinct from normal EOF" makes structural. Introducing `Dexpace::IOError` is barred for phase 1's `Dexpace::ArgumentError` reason: it would shadow `::IOError` for every file inside `module Dexpace` |
| P3-4 | The materialisation ceiling guards **every** operation that produces one contiguous `String` — `#snapshot`, `#read` with no count, `#read_exactly`, `#read_utf8`, `#read_string` and a length-bounded slice read — and never a slice's *construction* | `IO-9`, `IO-21`; design §10.18 | `IO-9` lets plain exact-count reads "inherit whatever bounds check the underlying stream library performs". In Ruby that check does not exist — a `String` is bounded only by memory — so inheriting it means inheriting the OOM killer. §10.18's "fails or ignores loudly above them, preserving the observable behaviour on a host where the stated failure mode is unreachable" is the sanction. It widens a SHOULD's scope; it narrows nothing. It is widened over `#read_exactly` and **not** over `#read(length)` or `#readpartial(maxlen)`, and the line is the **provenance of the count** rather than its size: `#read_exactly` is what `HTTP-39`/`BODY-10`'s exact-length copy drives, and `BODY-10`'s is a *declared* length — a number a peer chose — while the other two take a number the calling code chose. Those two stay where `IO-9` puts them, inheriting "whatever bounds check the underlying stream library performs". The one **drain-style** read left outside the guard is `#read_line_utf8`: the guarded drains — `#read` with no count, `#read_utf8`, `#read_string` — are checked incrementally as the result grows, and a line read has no count to check and no end but a terminator that may never arrive. `IO-14` fixes no line length, and the caller that reads lines from a hostile stream is phase 7's SSE machine, which `SSE-11` obliges to carry its own documented cap (`OI-5`) |
| P3-5 | A view pins the parent's cursor at construction, the parent holds nothing back for it, and a parent whose own cursor passes the next byte a live view still needs makes that view's later reads fail with `Dexpace::ClosedError` | `IO-19`, `IO-20`, `IO-22` | The specification does not say what happens when the parent advances under a live view. `IO-22`'s "never returning stale or arbitrary bytes" is the only normative anchor and it points one way. The alternative — the parent retaining from the lowest live pin — was rejected because it makes this rule unreachable and turns any un-closed view into an unbounded retention hold on the parent; the parent's own cursor is the retention floor instead, and the view registry serves invalidation only (`OI-4`). Stated so a plan does not decide it silently, differently, per view kind |
| P3-6 | `Dexpace::Closeable#closed?` is changed to read the latch **under the close mutex** | `IO-38`; design §3.1; phase 2's `closeable.rb` | `IO-38` is the first requirement that reads the flag from a second thread, and §3.1 fixes the mechanism as "written and read through a `Thread::Mutex` rather than relying on the GVL, so the guarantee survives JRuby and TruffleRuby". Phase 2's reader is unsynchronised, which is correct for everything phase 2 ships and not for this. Measured cost ~40 ns per call on all three interpreters, paid once per public call and never per byte |
| P3-7 | `Dexpace/QualifiedCoreConstant` gains the constant `IO`, a third watched namespace — the one-segment `Dexpace`, making it repository-wide over every gem's `lib/` — and a definition-site guard | phase 2's P2-8; design §9's gate table | Verified: inside `module Dexpace`, `x.is_a?(IO)` and `IO === x` are silently `false` for a real `::IO` and a `case/when IO` falls through, while `IO.pipe` is a loud `NoMethodError`. `Response#body_string`, which 3b adds under `lib/dexpace/http/`, is the counter-example that forbids scoping the rule to `lib/dexpace/io/**`. `File`, `StringIO` and `Tempfile` are deliberately **not** added: no `Dexpace::` constant of those names exists, and the standing rule is that a constant joins the list in the same change that creates its shadow. The definition-site guard is new and is not optional: this is the first phase whose own `lib/` **defines** a constant that is in `SHADOWED`, so without it the cop rejects `lib/dexpace/io.rb`, the file that creates the hazard the cop exists for |
| P3-8 | Public constants and public methods the design's §3 does not name: `Dexpace::IO` itself, `Dexpace::IO::TypedReads`, `Dexpace::IO::TypedWrites`, `Dexpace::StreamError`, `Dexpace::EndOfStreamError`, `StreamError.short_transfer`/`.zero_read`, `TeeSink#tap_snapshot`/`#tap_bytesize`/`#clear_tap`, `BufferedSource#owns_upstream?`/`#view?`, and the RBS interfaces `_Source`, `_Sink`, `_Chunked` | `NFR-4`; `api-design/b0e18938`; phase 2's P2-11 precedent | Each is locked at the first release tag, so a name arriving by accident is locked by accident. `TypedReads`/`TypedWrites` are public and not `private_constant` because the surface snapshot's `public_instance_methods(false)` cannot see a method reaching a class through a module, so a private module would hide most of 3a from the gate that exists to see it. The two `StreamError` class methods exist because `BODY-13` requires one helper "so the message form cannot diverge". `_Chunked` is not called `_Body` because 3b's body type is richer and one name for two meanings across the cut is the failure the cut exists to prevent. `#owns_upstream?` and `#view?` are the two construction-time facts read back: without them `IO-6`'s ownership and `IO-22`'s slice-versus-parent rule are assertable only through `instance_variable_get`, which is the shape §10.10 already records as reaching anything |
| P3-9 | Every count and offset beyond the first positional subject is a **keyword** — `#read_into(dest, count:)`, `#slice(offset:, count:)`, `#write_from(buffer, count:)`, `#copy_to(other, offset:, count:)` — where the reference's operations are positional. The **host-native bridge methods are the stated exception**: `#read(length = nil, outbuf = nil)`, `#readpartial(maxlen, outbuf = nil)`, `#getbyte` and `#write(*strings)` keep Ruby's positional signatures exactly | `IO-1`, `IO-4`, `IO-10`, `IO-16`, `IO-20`; `api-design/1d9e6e0b` | The styleguide asks for keywords on every public method, and here it also removes a real hazard: the reference's `read(dest, byteCount)` and Ruby's `read(length, outbuf)` put the same two arguments in opposite orders, so two positionals of different types are one transposition away from a silent corruption. The bridge is exempt because being call-compatible with `::IO` is its entire purpose — a keyword there would make `IO.copy_stream` fail |
| P3-10 | `#snapshot` returns an **unfrozen** copy, against the freeze-every-returned-collection rule | `IO-8`; `api-design/c15b29ce` | `IO-8` requires that later mutations of the buffer do not affect a returned snapshot "**and vice versa**", which presumes the caller may mutate it. The styleguide rule names collections, hashes and structs, and a `String` is none of the three, so it does not reach here — recorded rather than noted so the reasoning is not rediscovered as a bug |
| P3-11 | `BufferedSource.new` and `BufferedSink.new` are `private_class_method`; `Buffer.new` and `TeeSink.new` are public | `IO-6`; design §3.7 | Ownership is a construction-time fact, and a public `.new` taking an ownership argument would let a caller build the wrapper `IO-6` forbids — one that wraps a caller's stream and does not close it. `Buffer` and `TeeSink` each have exactly one construction meaning and need no factory to name it. Phase 1's `private_class_method :new` plus a validating `.build` is a rule about `Data` value types and does not reach these, which are mutable and stateful |
| P3-12 | `.wrapping` takes a block form; there is **no borrowing variant** of either wrapping factory | `IO-6`; `resource-management/bf5560dc`, `/43a55896` | The styleguide's strongest resource rule asks for a block form for every closable resource, and 3a adopts it exactly where a leak is possible. A borrowing wrap is not offered because `IO-6` is a MUST that a wrapper closes what it wraps; §3.7's build-versus-borrow split governs components that hold a resource, not the I/O wrap, and reading it as licence here would contradict the requirement §10.12 depends on |

## Deferrals Filed by Phase 3a

Filed against `docs/deferred-items.md`; the row names an explicit pick-up condition, per the
roadmap's execution step 7. (The heading avoids the literal words the housekeeping probe's
`registers` check reserves for the aggregate register, which is where the row lives.)

| ID | Deferral | Target / condition |
|---|---|---|
| `DEF-33` | Running the `IO` suite on a Ruby without a GVL — JRuby or TruffleRuby — so that `IO-38`'s cross-thread close guarantee is **exercised** rather than argued. Design §3.1 puts the close flag under a `Thread::Mutex` "so the guarantee survives JRuby and TruffleRuby", and the CI matrix is CRuby 3.2 / 3.3 / 3.4 / 4.0, on which the GVL would hide a missing lock. 3a ships the mutex, the test and the reasoning; what it cannot ship is the interpreter that would fail without them | Condition: a non-CRuby row is added to the CI matrix. No phase in v1 plans one, so the condition names the event and not a phase — the same shape as `DEF-3`'s `BODY-36` half, and recorded so a later reader does not mistake an unscheduled condition for a forgotten one |

### Deferral-register sweep

The roadmap's execution step 1 requires the phase to read the **whole** register and disposition every
row. All thirty-two were read.

**Phase 3a picks up none, marks none UNSCHEDULED, and adds a caller to one.**

- **`DEF-26` — untouched, and it is 3b's.** The segmentation design already picked it up for 3b,
  because narrowing `Request#body`/`Response#body` in `sig/` needs a body type and 3a's `_Chunked`
  duck type is not one. 3a does not touch either signature.
- **`DEF-3` — untouched.** `BODY-12` and `BODY-36` are `BODY` IDs; the segmentation design gave
  `BODY-12`'s transport half phase 8 and `BODY-36` an explicit pick-up condition. Nothing in 3a moves
  either.
- **`DEF-27` — untouched, and 3a adds no caller.** `close_quietly`'s two disposal routes are still
  missing, and 3a performs no best-effort close: every close here is either a caller's explicit
  `#close`, which propagates (§3.7's first loud exception), or a `#release`, which propagates once
  (§3.7's second). `BODY-28`'s new call site is 3b's, not 3a's.
- **`DEF-28` — untouched, and named as a constraint rather than a deferral.** The pivot has no
  `deadline:` until phase 5 and `IO-40` independently forbids 3a from owning one. The two agree, and
  3a's parameterisation of `MAX_MATERIALIZED_BYTES` follows the same precedent: ship the narrower
  surface, let phase 5 widen it.
- **`DEF-29` — untouched, condition still unmet, row strengthened.** 3a adds `FakeSource`, `FakeSink`
  and `FakeChunked` to `gems/dexpace-core/test/support/`, which is three more doubles that would move
  into `dexpace-conformance` when the first consumer outside `dexpace-core` appears. That consumer is
  phase 8 at the earliest.
- **`DEF-32` — untouched.** `Hooks.notify` has no caller in 3a; nothing here notifies a hook list.
- **`DEF-21` — already picked up** by phase 2. **`DEF-1`, `DEF-2`, `DEF-24`, `DEF-25`, `DEF-30`,
  `DEF-31` — untouched**: targets phase 5, 6, 4, 8, post-v1 and 5, none reachable from a phase that
  ships byte streams.
- **`DEF-4`–`DEF-10` — untouched.** `PIPE`, `RECOV`, `RETRY`, `REDIR`, `SSE`, `OBS` and `TRANSPORT`;
  other prefixes, later phases.
- **`DEF-11`–`DEF-17` — untouched.** Post-v1 gems, out of the MVP by construction.
- **`DEF-18` — untouched.** `ASYNC-3`/`ASYNC-4`/`PIPE-33`; do not re-open.
- **`DEF-19`, `DEF-20` — untouched.** Release-gated; nothing is published.
- **`DEF-22` — untouched.** Phase 8's conformance assertion objects.
- **`DEF-23` — untouched, and the condition was checked rather than assumed.** A Steep target over a
  test tree is picked up "when a gem's test support becomes production-quality code worth checking".
  3a's three fakes are each a handful of scriptable methods with no invariants a type checker would
  catch, and `DEF-29` already says the moment they become production-quality is the moment they move.
  Not met, so not marked UNSCHEDULED.

### The finding filed against `docs/open-items.md`

**`OI-3` — the `Dexpace::` constant shadowing is not inert outside core, and phase 1's claim is
narrower than it reads.** Phase 1's design records "Verified inert outside core: a consumer's
top-level `Method` still resolves to Ruby's, because `Object`'s own constants win over an included
module's." That sentence is true and its conclusion is not: verified on 3.2.11, 3.4.10 and 4.0.6, a
consumer writing `class C; include Dexpace; …` gets `Dexpace::IO` for a bare `IO` and
`Dexpace::Method` for a bare `Method`, because `include` inserts `Dexpace` **ahead of** `Object` in
`C.ancestors`; the top-level case is inert only because a top-level `include` inserts `Dexpace`
**after** `Object`, whose own constant table is searched first. `x.is_a?(IO)` is then silently
`false` for a real `::IO`. The finding is about every flat `Dexpace::` constant that shares a name
with a core class — `Method`, `Request`, `Response`, and now `IO` — and no gate this repository owns
can reach a consumer's file. What would resolve it: nothing mechanical; what 3a does is state it in
`Dexpace::IO`'s YARD block and record it here so a release decision and the as-built documentation
both see it. `OI-2` remains open and unchanged.

## Open questions for 3a's own plan

Three, each bounded and each named rather than hand-waved. None reopens a decision above.

1. **The chunk-store compaction policy.** The design fixes the shape — an `Array` of BINARY `String`
   chunks with a head byte offset, so draining is O(1) amortised (§3.1) — and two invariants: no byte
   is copied more than once on the fill path, and the store's retention floor is the object's **own**
   cursor, never a view's pin (P3-5 above). The second one is what makes this question small: the
   store needs no pin bookkeeping, only a decision about compaction. When a fully consumed chunk is
   dropped, and whether a partially consumed head chunk is `byteslice`d or left with a moving offset,
   is the plan's to pick and to test against those two invariants.
2. **`#each`'s chunk granularity.** Recommendation: yield whatever the upstream returned rather than a
   fixed size, because `.over` must preserve the wrapped body's own chunking for `BODY-17`'s
   byte-exact mirroring to mean what it says. The plan states the choice either way, because a fixed
   size is defensible for a `wrapping` source where there is no caller chunking to preserve.
3. **Whether the one allocating `IO-9` test runs on every matrix row.** Recommendation: yes, once per
   run per row — one 64 MiB allocation is affordable and skipping it on some rows would leave the
   ceiling's only size-based assertion untested where it might first break. The plan states the cost.
