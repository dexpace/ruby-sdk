# Phase 3b — Body Lifecycle

**Status:** Draft, for review. Written 2026-09-08, against
`docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md`, which is this sub-phase's charter, and on
top of `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md` and its plan, both
committed.

## Purpose

Sub-phase 3b builds everything a payload is between a caller and a socket: the eight request-body
variants and the one response body, the production contract they all satisfy, the materialize-once
guard, the two logging wrappers that capture bytes without ever altering the wire, the one decode
boundary, the bounded error-body copy, and the lazy typed-response wrapper. It is the layer 3a's bytes
exist for, and it is the last piece of the wire model phase 1 carried as an opaque member.

Three decisions in this document change what a reader of the design chapters would have written, and
each was forced by a fact run on a real interpreter.

- **The one decode boundary needs two steps, not one.** Design §3.1 says `Response#body_string`
  "applies the media type's charset via `String#encode(invalid: :replace, undef: :replace)`". Applied
  to the BINARY bytes 3a delivers, that call **mangles every non-ASCII byte** — `"café".b.encode(...)`
  is `"caf��"` on 3.2.11, 3.4.10 and 4.0.6 alike. The retag has to come first, and the
  target encoding has to be named explicitly because a target-less `#encode` follows the process-global
  `Encoding.default_internal`. Filed as `OI-7` with a corpus note (verified fact 1).
- **`BODY-9`'s "mark/reset" has a Ruby antecedent and it is not `respond_to?`.** A pipe, a socket, a
  `StringIO` and a `File` all answer `true` to `respond_to?(:rewind)`; the pipe and the socket then
  raise `Errno::ESPIPE`. The probe that works is `pos` + `seek(pos)` — non-destructive on a seekable
  stream even at a non-zero offset, and raising on a pipe with nothing consumed. `BODY-9` is
  implemented, not vacuous (R9, verified fact 2).
- **§7.1's `Enumerator` rule reaches an ordinary `#each` method, not only an `Enumerator.new` block.**
  A plain `def each; open; yield; ensure; close; end` driven through `to_enum(:each)` with `#next` and
  then abandoned leaves its `ensure` unrun, on all three interpreters. That is the corpus rule
  `pagination/f57c50f6` stated one class of object too narrowly, and it decides how every body variant
  produces bytes (verified fact 3).

3b ships no transport, no pipeline, no retry loop and no configuration chain. Its whole test surface is
bodies: production, replayability, ownership, capture, close and decode.

## Governing documents

- `docs/work/mvp/phase3/2026-09-08-phase3-segmentation-design.md` — the charter. It fixes 3b's 49 IDs,
  the ten spec-forced boundaries, the `DEF-26` pick-up and risks R5–R10. R1–R4 were 3a's and are
  resolved; they are not re-opened here.
- `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts-design.md` and
  `docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts.md` — what 3b stands on. The design's
  "The interface surface 3b consumes" table is reconciled row by row below; the plan is where the
  actual method bodies are, and it was read rather than inferred from.
- `docs/product-spec/06-request-and-response-body-lifecycle.md`, read in full, with
  `docs/product-spec/appendix-c-consolidated-normative-requirement-index.md` for the canonical text of
  every ID.
- `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.1 in full and §3.7 for close;
  `docs/sdk-design-ruby/05-pipeline-architecture.md` §5.1 for the bounded error copy;
  `docs/sdk-design-ruby/07-pagination-sse-and-serialization.md` §7.1 for the `Enumerator` rule and §7.3
  for `TypedResponse`; `docs/sdk-design-ruby/10-deliberate-deviations-from-the-reference-contract.md`
  items 2, 10, 11, 12 and 18; §12's `BODY` and `HTTP` rows.
- `docs/work/mvp/2026-09-05-ruby-sdk-v1-roadmap-design.md`, and phase 1's and phase 2's designs.
- `CLAUDE.md` and `docs/README.md`.

## Scope

### The 49 IDs, with dispositions

**Implemented — 47.** `BODY-1`–`BODY-11`, `BODY-13`–`BODY-35`, `BODY-37`; `HTTP-36`–`HTTP-45`,
`HTTP-51`, `HTTP-52`. Five are SHOULDs — `BODY-9`, `BODY-20`, `BODY-29`, `BODY-33`, `HTTP-51` — and all
five are implemented; `BODY-9` is R9 and is answered below rather than assumed.

**⏳ `DEF-3` — 2, and one of them changes.**

| ID | Level | Disposition |
|---|---|---|
| `BODY-12` | SHOULD | **Split, and the split is this document's to make.** Clause 1 — "stream its bytes using the platform's most efficient file-to-sink transfer (avoiding an unnecessary user-space copy)" — is **implemented** here, through `::IO.copy_stream`. Clause 2 — "the transport layer SHOULD be able to recognize a file-backed body by type to dispatch a true zero-copy kernel transfer" — stays ⏳, target **phase 8** with `DEF-10`; 3b discharges the half of it that is a body-layer obligation by making the file body a named public class exposing `#path`, `#offset` and `#count`, which is what a transport dispatches on |
| `BODY-36` | MAY | ⏳, unchanged in substance and given the explicit pick-up condition the segmentation design named: Ruby's standard library has no `mmap`, and the only routes are a C extension or the `mmap` gem, both barred from core by `SEAM-1`/`NFR-1`, so the condition is **core's dependency budget changes**, which no phase in v1 can meet |

Before this change the register row for `DEF-3` read "BODY-12 lands with an `IO.copy_stream` path
post-MVP; BODY-36 has no named trigger". The segmentation design stated both sharpenings and did not
perform them; this change performs them on the register, because 3b is the phase that owns both IDs.

**Also carried, without owning the ID:**

- **`DEF-26`, picked up.** Its pick-up condition names phase 3 explicitly: narrow `Request#body` and
  `Response#body` in `sig/` from `untyped`, and add the by-value equality test against a real body
  type. Both need a body type to exist, which is why the row is 3b's and not 3a's — 3a's `_Chunked`
  duck type is deliberately not one. Resolved under R6 below.
- **`HTTP-46` — a cross-reference row, not a re-satisfaction.** The ID stays phase 1's, whose design
  overrides `#==`/`#hash` on `Request` to compare "`URL.external_form(url)` plus method, headers and
  body by value". The body half of that was untestable in phase 1 because no body type existed. 3b
  supplies the type and the test; dropping the row would leave a requirement whose obligation this
  phase discharges with no row in the phase that discharges it. Same treatment phase 2 gave `SEAM-29`.
- **The form encoder phase 1 handed here.** Phase 1's design says of `HTTP-38`/`BODY-35`: "The form
  encoder … is not here and is not this. It is `+`-for-space and never claimed RFC 3986 compliant; it
  lands in phase 3 as a different function with a different name and different tests." That is a real
  deliverable inside `HTTP-38`/`BODY-35`, and the segmentation design's edge table does not name it.
  3b ships it.

### The canonical text the design turns on

Quoted from appendix C, because each fixes a decision below.

> **HTTP-36** (MUST) — A request body MUST produce its bytes on demand via a single write-to-sink
> operation, MUST report its media type (nullable) and content length (with a negative sentinel, -1,
> meaning 'unknown'), and MUST expose whether it is replayable …

> **BODY-8** (MUST) — A single-use request body that owns a closeable source MUST release (close) that
> source as part of its single write … A port MUST decide its stream-ownership/close rule deliberately
> rather than assume every single-use body closes its input.

> **BODY-9** (SHOULD) — A stream-backed request body of known length SHOULD be treated as replayable
> when (and only when) the stream supports mark/reset and the length fits the platform's maximum
> single-array bound; otherwise it MUST be single-use. When replayable via mark/reset, each write after
> the first MUST rewind (reset) before reading, and the rewind MUST be race-safe (at most one reset
> between any two writes).

> **BODY-24** (MUST) — When the response body exceeds the cap … the wrapper MUST buffer only the
> prefix, MUST leave the delegate open, and MUST serve the next read as a single-use stream that first
> replays the captured prefix and then continues from the still-live tail … A second read in this
> regime MUST fail (the tail is single-consumer).

> **BODY-28** (MUST) — On the fits-cap path, closing the delegate as part of a successful capture is
> best-effort … The captured in-memory buffer MUST survive the wrapper's close (it holds only memory,
> no transport resource) so post-mortem snapshot logging still works after close.

> **HTTP-42** (MUST) — Reading a response body as text MUST default its charset to the charset declared
> in the body's media type, falling back to UTF-8 when none is declared or the declared charset is
> unknown.

> **HTTP-43** (MUST) — Response MUST be closeable and its close MUST be idempotent and forward to the
> body … (Idempotency is delegated to the body's idempotent close per HTTP-41; a bodyless response
> close is a no-op.)

> **HTTP-44** (MUST) — A lazy typed-response wrapper MUST expose raw
> status/headers/protocol/reason/request WITHOUT consuming the body, and MUST parse the typed value at
> most once on first access, memoizing the outcome … Both a null success and a thrown failure MUST be
> memoized.

> **HTTP-52** (MUST) — An error-mapping path that must retain a response body after the transport
> connection is released MUST buffer the body into memory up to a fixed cap (1 MiB), dropping bytes
> beyond the cap, and MUST expose the buffered copy as a replayable body readable multiple times.
> Buffering MUST occur inside the original body's close scope so a provider-resolution failure still
> releases the connection.

### Two spec-reading traps, recorded so neither is walked into

- **`HTTP-16-body` is not a requirement ID.** Spec §6.3 labels the convenience-reader rule
  "**HTTP-16-body / BODY-16**". Canonical `HTTP-16` is phase 1's header insertion-order SHOULD,
  unrelated, and **not in 3b's scope**. The obligation is carried by `BODY-16` and by `HTTP-41`'s own
  appendix-C text, which folds the finally-close clause in.
- **`BODY-6` and `BODY-7` are two rows, not one.** Neither appears in ch.06's prose as its own bullet —
  §6.1 states their content inside `BODY-3`/`HTTP-37`'s entry. Both have appendix-C rows and
  substantive corpus coverage, and design §3.1 names them separately: `BODY-6` is "a second write
  raises rather than emitting zero bytes", `BODY-7` is "under concurrent writes at most one passes".
  They get separate checklist rows and separate tests, because the second is a concurrency proof the
  first does not make.

### Out of scope, explicitly

| Excluded | Owning phase |
|---|---|
| Every `IO` ID. 3a owns the representation, the buffer, the sources and sinks, and the tee | 3a |
| `BODY-4`/`BODY-5`'s three **call sites** — the retry stop, the auth challenge return, the redirect raise — and `Dexpace::Resilience::Resend.eligible?(request)`, the one predicate the corpus places under `resilience/` (`authentication/cdd2b5fc`) | 6. 3b ships the `#replayable?` property the three consult and the documented decline behaviours; it builds no gate and no predicate |
| `BODY-5`'s method-idempotency gate. Phase 1 shipped `Method#idempotent?`; the gate that reads it is retry-specific | 1 built, 6 gates |
| `BODY-30`/`HTTP-52`'s **recovery-chain step** and `BODY-31`'s **error-to-exception mapping step** — design §12 places both in §5.1 alongside `RECOV-16` | 4. R8 below draws the line |
| `BODY-19`/`BODY-34`'s **configuration source** and the body-level-logging **enablement predicate**; `IO-9`/`BODY-32`'s ceiling as a configurable value | 5 — `DEF-34`, filed here. R5 below |
| `HTTP-44`/`HTTP-45`'s **witness** — `SEAM-22`'s `.dexpace_load(parsed, ctx)` protocol and the status-aware handler that closes over it (`serde/4b78c08d`) | 7. 3b ships `TypedResponse` over a handler duck type. R7 below |
| `SEAM-20`/`SEAM-21`/`SERDE-3`'s third ownership rule — a codec reads or writes a caller's stream fully and closes nothing | 7. Phase 3 neither implements nor weakens it (boundary 5) |
| `BODY-12`'s transport zero-copy dispatch; `TRANSPORT-25`'s streaming response body | 8 — `DEF-10` |
| `XCUT-15`, `XCUT-18` — restated cross-cutting invariants 3b leaves satisfiable without claiming | 9 |

**No segmentation design of its own.** 3b is one spec chapter, one gem, 49 IDs, under a segmentation
design that already exists at the `phase3/` level.

## Prerequisites

### From phase 0 — seventeen blocking gates, unchanged and unlowered

`gates:require_allowlist` is the one that constrains the code: core's `lib/**/*.rb` may `require` only
`monitor`, `uri`, `stringio`, `strscan`, `time`, `date`, `securerandom`, `digest`, `openssl`,
`forwardable`, `set`, `singleton`. **3b adds nothing to it.** `::File`, `::IO`, `::IO.copy_stream`,
`::String`, `::Encoding`, `::Thread::Mutex` and `::Thread::ConditionVariable` are core Ruby and need no
`require`; `securerandom` is already allowlisted and is what `HTTP-51`'s spec-valid random boundary uses;
`stringio` and `tempfile` are used in `test/` only, and the segmentation design already verified both are
default gems on 3.2.11, 3.4.10 and 4.0.6 and appear in no `Gem::BUNDLED_GEMS::SINCE` table.

`gates:surface_snapshot` and `gates:sig_diff` are regenerated once, deliberately, in the phase's last
task. 3b adds more public constants than any phase so far, which is why R6 names every one on purpose
and gives them a ledger row.

`OI-6` records that RuboCop is clean for no phase under `.rubocop.yml` as phase 0 wrote it. 3b inherits
that and adds to it rather than resolving it: the resolution belongs to whoever lands phase 0. The
plan's "expected: clean" steps are unfalsifiable until then, and 3b states that rather than repeating
the claim.

### From phase 1

- **`Dexpace::Model` and `Dexpace::Builder`** — not used by 3b. No body is a `Data` value type: every
  one carries at least a media type and a length, several carry an open stream, and `Data`'s frozen
  construction is wrong for an object with a consume-once latch. The construction rule 3b does obey is
  phase 1's real one: **no `.build` is a bare `new` wrapper, and validation lives where a forged
  construction still meets it** — here that means each body class's own `initialize`.
- **`Dexpace::InvalidArgumentError < ::ArgumentError`** — every argument-validation failure in 3b
  raises it. `Dexpace::ArgumentError` is never defined.
- **`Dexpace::Error` is a module** (P1-2), included by every core error class. 3b defines **no new
  error class**: 3a's `Dexpace::StreamError` and `Dexpace::EndOfStreamError`, phase 2's
  `Dexpace::ClosedError` and phase 1's `Dexpace::InvalidArgumentError` cover every failure below. That
  is stated rather than left implicit, because "the body layer needs its own error" is the obvious
  first instinct and it is wrong: `BODY-6`'s second write, `BODY-10`'s short transfer, `BODY-13`'s
  short write, `BODY-24`'s second read and `BODY-25`'s zero read are all stream-contract violations,
  which is exactly what `Dexpace::StreamError` is.
- **`Dexpace::MediaType`** with `#charset -> String?`, which resolves the parameter case-insensitively
  and returns `nil` when absent **or unknown to this Ruby** (it consults `Encoding.name_list`). That is
  `HTTP-42`'s fallback condition already satisfied at the model: 3b needs no second validation and
  `Encoding.find` on the value it returns cannot raise.
- **`Dexpace::Status`** with `#error?` (400–599), `#client_error?` and `#server_error?` (`HTTP-11`).
  That **is** `BODY-31`'s 4xx/5xx predicate; 3b writes no second one.
- **`Dexpace::Method#idempotent?` and `#body_forbidden?`** — `HTTP-7`'s rejection of a body on
  GET/HEAD/TRACE/CONNECT already runs in `Request`'s `initialize` and keeps working unchanged once the
  body is a real type.
- **`Dexpace::PercentEncoding`** — the strict RFC 3986 component encoder. 3b adds the form encoder
  beside it (R6).
- **`Dexpace::Request` and `Dexpace::Response`**, each carrying an opaque `body`. 3b narrows both in
  `sig/` and adds three methods to `Response`.
- **`downcase` takes no argument** (`Dexpace/NoLocaleCaseFold`); every source file opens with
  `# frozen_string_literal: true` then the SPDX line.

### From phase 2

- **`Dexpace::Closeable`** — `initialize_closeable(owned:)`, `#owned?`, `#closed?`, `#close`, private
  `#release`, the mutex held only across the flip, and `#closed?` reading under it since 3a's P3-6.
  `BODY-15`'s idempotent close, `BODY-27`'s close-once guard and `HTTP-41`'s response-body close are
  all that latch. 3b writes no second one.
- **`Dexpace::ClosedError`** — 3a is its first caller; 3b is its second, at every **use-after-close** on
  a stream-backed surface: a read on the over-cap tail after the wrapper's close (R10), and a read on a
  closed `ResponseBody`'s source. `BODY-24`'s *second* read is a different failure and a different
  class — nothing is closed, the tail has simply already been taken — so it raises
  `Dexpace::StreamError`, with the other stream-contract violations listed under phase 1 above.
- **`Dexpace.close_quietly`** — **`BODY-28` is its first call site in the SDK.** `DEF-27`'s condition
  (a suppressed trail or a diagnostic sink to route the dropped error to) is still unmet, so the
  rescued error is still dropped; the row is strengthened, not met.
- **`Dexpace::Hooks`, `Dexpace::Registry`, `Dexpace::Cancellation` and the async pivot** — not used by
  3b. No body notifies a hook list, and `IO-40`'s no-deadline rule reaches the body layer through the
  same argument it reaches 3a by.
- **The six custom cops** — phase 0's five plus phase 2's `Dexpace/QualifiedCoreConstant`, which 3a
  widened rather than replaced. 3a added none and neither does 3b.

### From phase 3a — the contract table, row by row

3a's design closes with "The interface surface 3b consumes": **eight rows plus two further items**.
Each is checked below against what 3b actually needs, and two rows do not deliver what a naive reading
suggests. The count reconciles with the charter, whose own dependency-edge table is the same eight
edges; the two further surfaces are named in 3a's following paragraph rather than in its table.

| 3a row | What 3b needs | Verdict |
|---|---|---|
| 1 — `TeeSink.new(primary:, tap_limit:)`, `#write`, `#write_from`, `#write_all`, `#emit`, `#flush`, `#close`, `#tap_snapshot`, `#tap_bytesize`, `#clear_tap`, `#buffer` raising | The tee, per write, with the tap readable afterwards | **Delivers, with one consequence and one unused method.** `IO-29` makes `#close`, `#flush` and `#emit` forward to the **primary**, which is the transport's sink — so `RequestLoggingBody` calls none of the three. And because `TeeSink` binds its primary at construction, 3b creates a **fresh tee per write** rather than reusing one, which satisfies `BODY-18` by construction and leaves **`#clear_tap` with no core caller** — filed as `OI-8`, which names the window in which 3a's plan may drop it without an `NFR-4` break. Reported as a cross-phase finding rather than worked around |
| 2 — `Buffer.new`, the `TypedWrites` surface, `#snapshot`, `#bytesize`, the `TypedReads` surface | Materialize-once's drain target and the replayable body over it | Delivers |
| 3 — `#read_exactly(count)`, `#write_all(source)`, `StreamError.short_transfer` / `.zero_read` | `HTTP-39`/`BODY-10`'s exact copy, `BODY-13`'s short write, `BODY-25`'s zero read, one message form | **Delivers two of three, and `#write_all` is deliberately not used.** `#write_all(source)` is `TypedWrites`', so it requires the *sink* to be a `Dexpace::IO` sink; a body writes to whatever `#write`-shaped object the transport hands it, and wrapping that in `BufferedSink.wrapping` would take ownership of the transport's socket, which `IO-6` then obliges the wrapper to close. 3b drives its own copy loop instead (P3-20). The two message helpers are used exactly as `BODY-13` intends |
| 4 — `#peek`, `#slice(offset:, count:)`, `Closeable`'s latch, `Buffer`'s post-close readability | `BODY-22`–`BODY-29` | **Delivers, and 3b needs one surface more than the row names.** `Buffer`'s post-close readability is `IO-42`'s in-memory exemption, expressed in 3a as the private `#reads_survive_close?`/`#writes_survive_close?` hooks, and it is exactly what `BODY-28` needs. `Closeable`'s latch alone is not all of `BODY-27`: the requirement names **two** close paths, and the tail's reaches the latch only through `BufferedSource.wrapping`'s ownership (`IO-6`) — R10, where `.over` is rejected for exactly this |
| 5 — `Dexpace::IO::MAX_MATERIALIZED_BYTES` | `BODY-32`'s clamp target and `BODY-9`'s "fits the platform's maximum single-array bound" | Delivers. Cited, never re-derived; one ceiling (boundary 8) |
| 6 — `BufferedSource.wrapping(io)` with its ownership, `#close`, `#closed?`, `IO-42`'s rejection | `HTTP-41`/`BODY-14`/`BODY-15`'s response body | Delivers |
| 7 — `#read_string(encoding, count: nil)`, `#read_utf8(count: nil)` | `HTTP-42`'s decode | **Delivers the retag; the transcode is 3b's and the design's recipe for it is wrong.** 3a's `#read_string` retags the drained BINARY bytes and applies no policy, which is exactly right. The second step is `#encode(enc, invalid: :replace, undef: :replace)` with the **target named explicitly**, and it must not be applied to untagged bytes. `OI-7` |
| 8 — `IO-6`'s I/O-layer half, the factory-name convention, `.over`'s exception | `BODY-8`'s inverted body-layer rule | Delivers. §10.12 is one decision with two halves; 3b fixes the second and re-decides neither |
| + `Dexpace::IO::_Chunked` | The RBS type a body's own interface can include | Delivers |
| + `BufferedSource#each` | What makes a source itself a canonical body representation | Delivers, and it is what `ResponseBody` is built on |

**One thing the contract does not give 3b, and 3b does not need:** a body-layer name for `_Chunked`.
3a named it `_Chunked` rather than `_Body` precisely so 3b's richer type could take the other name;
3b's is `Dexpace::Body`, a module rather than an interface, for the reason under R6.

## Corpus reading, and what it settled

The `knowledge-lookup` skill's phase-start pair was run before anything here was written, and every
count below is what it returned **before this phase filed its own two notes**. A reader re-running them
afterwards should expect `--origin note --brief` at 27 entries across the same 15 files rather than 25,
and the twelve-`HTTP`-ID `--req` call at 29 entries across 8 topic files rather than 28 across 7 — the
extra entry and the extra file are this phase's own `notes/io-and-byte-streams.md` entry, which cites
`HTTP-42`. Nothing else moves.

`--origin note --brief` returns **25 entries across 15 note files**; `--section conflicts --brief`
returns 24 entries across 17 topic files, **18 of them notes, and all six harvested conflicts print
`[overridden by notes/…]`** — none is open, so 3b inherits no unresolved conflict and owns no conflict
decision of its own.

`--prefix-info BODY` reports 37 IDs, 31 MUST / 5 SHOULD / 1 MAY, owning chapter
`docs/product-spec/06-request-and-response-body-lifecycle.md`, and **37 of 37 substantive with zero
roll-up-only entries**. `--gaps BODY` and `--gaps HTTP` both return nothing. `--req` over the twelve
jointly numbered `HTTP` IDs returns 28 entries across 7 topic files, **none tagged
`[appendix-B roll-up]`** — the roll-up hazard does not fire for this sub-phase at all, and no ID here
needed the three-step roll-up path.

`--phase 1 --brief` and `--phase 2 --brief` were run. Phase 1 cites `BODY-35`, `HTTP-36`, `HTTP-38`,
`HTTP-41` and `HTTP-43` from its own out-of-scope table, pointing here; phase 2 cites `BODY-27` for the
same reason. Nothing either phase settled is re-opened.

### The audit groups this phase ran

| Group | Query | Result |
|---|---|---|
| **Message bodies** | `--prefix BODY --section rules,conclusions,constraints,reference` | 45 + 15 + 30 entries. `message-bodies/627eaeab` ("a body over a caller-supplied `IO` or `Enumerator` never closes it, and transfer of close ownership is opted into explicitly at the factory") is the body-layer ownership rule, adopted verbatim and load-bearing for `BODY-8` |
| **Streaming and encoding** | `--prefix IO --section rules --brief` and `--topic io-and-byte-streams,serde --section rules --grep 'encoding\|binary\|ASCII-8BIT\|force_encoding'` | `io-and-byte-streams/d2b47c89` (never trust a transport's charset tagging) adopted. **`io-and-byte-streams/fbcb4d19` is superseded** — the decode recipe. See the note below |
| **Error handling** | `--prefix BODY --section rules` narrowed to `error-handling.md`, plus `--topic error-handling --section rules` | `error-handling/aaa8a235`, `/b732301f`, `/82145ceb`, `/ea20e887`, `/6153058c` — `BODY-30`–`BODY-34` restated from the spec side; nothing conflicts. `error-handling/d2eadac4` (the note) already fixes the error-root shape |
| **Resource lifecycle and stream ownership** | `--topic resource-management --section rules` and `--chapter 13` | The group 3a added to the skill's table. `resource-management/d1f16cad` (the note) already resolves the timeout rules against `IO-40`; `resource-management/bf5560dc` (block form for every closable resource) reaches `ResponseBody` and is adopted; `resource-management/1676974d` (never rely on finalizers) is what forbids papering over the `#each` residue |
| **Public API surface** | `--topic api-design,http-domain-model,documentation,module-organization,error-handling --section rules --brief` | `api-design/1d9e6e0b` (keyword arguments) shapes every signature; `api-design/88e6bf12` (narrowest duck-typed parameter) is why `#write_to` takes `#write` and `TypedResponse` takes `#call` |
| **Fiber scheduler, thread safety** | `--topic concurrency-and-async --section rules --brief` and `--prefix BODY --grep 'mutex\|latch\|concurren'` | `concurrency-and-async/e94924e3` (`BODY-6`/`BODY-7`'s mutex across the flag flip and never across the drain) and `/6569f2a4` (`BODY-22`'s latch is the same shape) govern; `serde/97665a9a` extends both to `HTTP-45` |
| **Minitest conventions** | `--chapter 11 --section rules` and `--topic testing,assertions --section rules` | Clean. `testing/f36a19cd` makes the property test over `HTTP-51`'s framing mandatory rather than optional |
| **Styleguide-vs-design conflicts** | `--section conflicts --brief` | All six resolved |

### The two notes filed against the corpus by this phase

Written before this document was finished, because a resolution recorded only in a phase document is
re-litigated by whoever reads the corpus next.

- **`docs/knowledge/notes/io-and-byte-streams.md`**, `## Superseded`, third entry — **the decode
  boundary is retag-then-transcode, and the transcode must name its target.** Supersedes
  `io-and-byte-streams/fbcb4d19` ("there is exactly one decode boundary, `Response#body_string`, which
  applies the media type's charset via `String#encode(invalid: :replace, undef: :replace)`"), whose
  *rule* is right and whose *recipe* mangles every non-ASCII byte when applied to the BINARY bytes the
  I/O layer delivers. Verified fact 1. This is the corpus half of `OI-7`.
- **`docs/knowledge/notes/pagination.md`**, `## Superseded`, second entry — **§7.1's rule reaches an
  ordinary `#each` method, not only an `Enumerator.new` block.** Supersedes `pagination/f57c50f6`
  ("Resource acquisition and release must never live inside an Enumerator block in the Ruby SDK,
  because Ruby's cleanup guarantee on break only holds for internal iteration and not for external
  iteration via `#next`"), which is true and one class of object too narrow. Verified fact 3. It is
  what decides how every body variant produces bytes, and it is the reason `FileBody`'s residue is
  documented rather than closed.

Two audit results earn no note. `resource-management/bf5560dc`'s block form is **adopted** for
`ResponseBody`, which is 3b's only closable factory, and an adopted rule needs no note. And
`type-system/b5166811` ("`nil` as a last resort") does not reach `#content_length`'s `-1`: `BODY-35`
fixes the sentinel in normative text, an ID-bearing rule beats a styleguide default under the roadmap's
precedence rule, and 3a already took the same `-1` for `IO-1` without one. Recorded here so the absence
is deliberate.

## The verified Ruby facts this phase is built on

Every claim was run on 3.2.11, 3.4.10 and 4.0.6 through `mise exec ruby@<v>` on 2026-09-08. The first
five changed a decision; the rest are recorded because the plan would otherwise assume them.

1. **`String#encode` on BINARY bytes mangles them, and a target-less `#encode` follows a process
   global.** `"café".b.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)` is
   `"caf��"` on all three — every byte ≥ 0x80 is undefined *in the source encoding* and is
   replaced. The correct sequence is `force_encoding(charset)` then `encode(charset, invalid: :replace,
   undef: :replace)`, which yields `"café"` for UTF-8 bytes, `"café"` for ISO-8859-1 bytes declared as
   ISO-8859-1, and a scrubbed `"caf�"` for ISO-8859-1 bytes declared as UTF-8 — a `valid_encoding?`
   result in every case. Separately, `#encode(invalid: :replace)` **with no target** converts to
   `Encoding.default_internal`: with it set to ISO-8859-1, §3.1's call **applied to the BINARY bytes**
   — `"café".b.encode(invalid: :replace, undef: :replace)` — returns the ISO-8859-1 string `"caf??"`,
   the accented character replaced twice over, while the explicit-target form returns the same result
   with or without the global. The two halves compound and are independently disqualifying, which is
   why both are named: retagging first without naming the target still hands the host's
   `default_internal` the choice of output encoding (verified: after the retag the same target-less
   call returns ISO-8859-1 under that global, and `"caf?"` in US-ASCII under another).
   `default_internal` is a process global a host sets, which is the same class of hazard as
   `URI::DEFAULT_PARSER` (§3.5) and `$/` (`IO-14`). **The decode boundary names both encodings
   explicitly and retags first.**
2. **`respond_to?(:rewind)` is `true` for a pipe, a socket, a `StringIO` and a `File` alike**, and the
   first two then raise `Errno::ESPIPE` — including at position 0 with nothing consumed, after which
   the stream is still fully readable. `#pos`, `#pos=` and `#seek` raise the same way. The probe that
   discriminates is therefore `origin = io.pos; io.seek(origin, ::IO::SEEK_SET)`: it raises on a
   non-seekable stream and is a genuine no-op on a seekable one, **preserving a non-zero starting
   position** rather than silently rewinding a caller's mid-file handle to byte 0. `Errno::ESPIPE` is a
   `SystemCallError` and a `StandardError`, and **not** an `IOError`. This is R9's whole answer.
3. **An ordinary `#each` method leaks exactly like an `Enumerator.new` block.** A plain
   `def each; @log << :open; begin; yield …; ensure; @log << :close; end; end` driven with
   `to_enum(:each)` and two `#next` calls and then dropped leaves the `ensure` **unrun** after two
   `GC.start` calls; `#rewind` does not run it either; `#each` with a block and a `break` **does** run
   it; and a full external drive to `StopIteration` **does** run it. `block_given?` is `true` under
   `to_enum(:each)`, so "require a block" is not a defence. Uniform on all three.
4. **`::IO.copy_stream` accepts a duck-typed `#write` destination, honours `(length, src_offset)`, and
   does not move the source `File`'s own cursor when an offset is given.** `copy_stream(path_or_io,
   duck_sink, 4, 3)` delivers `"3456"` as BINARY strings and returns `4`; with an offset the source
   `File#pos` is unchanged, without one it advances. That is `BODY-12`'s first clause and `BODY-11`'s
   offset window in one stdlib call, with `BODY-13`'s short-write detection falling out of the return
   value.
5. **A source responding to `#to_path` still honours `copy_stream`'s length and offset — but a
   `copy_stream(body, sink)` with neither copies the whole file.** So defining `#to_path` on a
   windowed file body would let a transport silently upload the entire file instead of the body's
   `offset+count` range. `#to_path` is deliberately not defined; `#path`, `#offset` and `#count` are.
6. **`raise cached_error` re-raises the same object with its `#cause` and its original backtrace
   intact**, on all three, even from a different frame and repeatedly. `HTTP-44`'s "re-throws the same
   failure" and `BODY-26`'s cached error are therefore a bare `raise`, with no `#exception` dance and
   no backtrace loss.
7. **A frozen `String` is safe through the whole chain when `#b` is the retag.** `fz.b.frozen?` is
   `false` and `fz.b.equal?(fz)` is `false`; `(+"").b << fz` works; `+fz` is unfrozen. Re-verified
   because every body that yields literal chunks yields frozen ones under
   `# frozen_string_literal: true`.
8. **`Thread::Mutex` is non-reentrant and per-fiber-owned**, re-verified: a nested `#synchronize`
   raises `ThreadError: deadlock; recursive locking`, and a second fiber of the same thread locking one
   held across a `Fiber.yield` raises `ThreadError: deadlock; lock already owned by another fiber
   belonging to the same thread`. That is what makes 3b's "two fibers interleaving a drain" test a real
   proof rather than a restatement.
9. **`Tempfile#close` leaves the path on disk and `#unlink` removes it**; `#close!` exists. Relevant
   only to `test/`, where `FileBody`'s fixtures live.
10. **`byteslice` past the end returns `nil`, `byteslice(0, n)` past the end returns what exists**, and
    `[Float::INFINITY, n].min` is an `Integer`. `BODY-32`'s "return whatever bytes are available up to
    the clamped cap without requiring that exactly that many bytes exist" is that behaviour, and
    `BODY-19`'s unbounded default composes with an integer cap without a type test.

## R5 — where the caps get their values before phase 5

**Three different numbers, and collapsing any two is the failure.**

| Number | What it bounds | Where its value comes from in 3b |
|---|---|---|
| `Dexpace::IO::MAX_MATERIALIZED_BYTES` (64 MiB) | One contiguous `String` (`IO-9`), and `BODY-32`'s clamp target | 3a's constant, read directly. **3b adds no keyword** |
| `Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES` (1 MiB) | `BODY-30`/`HTTP-52`'s error-body copy | A 3b constant. The requirement fixes the number, so there is nothing to configure |
| The body-logging preview size | `BODY-19`'s tap cap and `BODY-22`'s drain cap, which `BODY-34` requires be **one shared** value | A keyword on each wrapper. **The source is deferred — `DEF-34`** |

**The ceiling gets no keyword, and that is a decision rather than an omission.** 3a shipped
`MAX_MATERIALIZED_BYTES` with no keyword specifically to leave this to 3b, and 3b declines it for
boundary 8's reason: a `ceiling:` keyword on a preview operation would let one stream carry two
ceilings, which is exactly what §10.18's single substituted constant exists to prevent. What `BODY-32`
*does* parameterise is the **cap**, which is a different thing — a caller's request for at most N bytes,
clamped down to the ceiling and never up. So `#preview(cap:)` takes a cap and reads the ceiling from
the constant. Phase 5 changes where the constant's *value* comes from; it changes no signature.

**The two wrappers take a cap keyword, and their defaults are deliberately asymmetric.**

- `RequestLoggingBody.new(delegate, tap_limit: ::Float::INFINITY)` — the default is unbounded because
  `BODY-19`'s own text says so: "The unbounded default cap exists for direct wrapper use; the
  instrumentation layer always supplies a finite cap." 3a's `TeeSink.new(primary:, tap_limit:
  ::Float::INFINITY)` already implements exactly that, and the wrapper passes the value through.
- `ResponseLoggingBody.new(delegate, preview_bytes:)` — **required, no default.** `BODY-22` says
  "buffering up to a configurable byte cap" and names no default, and an unbounded default here would
  mean `BODY-24`'s over-cap regime never fires and a multi-gigabyte response is fully buffered by a
  wrapper whose whole purpose is to bound. Requiring the keyword ships the narrower signature and lets
  phase 5 widen it, which is `DEF-28`'s precedent applied verbatim: adding a default widens and cannot
  break `NFR-4`.

A reader who tidied these into one default would break one requirement or the other; the asymmetry is
recorded as **P3-18**.

**`BODY-34` is therefore partially satisfied in 3b, and the row says so.** Its parameter shape lands
here — both wrappers take a cap, so one value can drive both — and its two remaining clauses do not:
the *shared source* needs phase 5's layered chain, and the *enablement predicate* ("body logging MUST
engage only when body-level logging is enabled") has no subject in 3b, because nothing in core
constructs a logging wrapper. That second half is satisfied **structurally** rather than by a flag: the
wrappers are off the path unless something builds one, and the only thing that will is phase 5's
instrumentation layer. `DEF-34` carries both.

## R6 — the body constants' names and namespace

**Flat public constants, files under `lib/dexpace/http/body/`, and `Dexpace::Body` is a module.**

Phase 1's P1-1 makes flat the default and keeps a namespace only where the design already gave a
subsystem one. Design §3 names `Dexpace::IO::Buffer`, `Dexpace::IO::BufferedSource` and — flat —
`Dexpace::TypedResponse`. It names **no** body-variant constant, so the default applies. Two things
make the default the right answer here rather than merely the rule:

- **A `Dexpace::Body::` namespace would manufacture the exact hazard `OI-3` and P3-7 are about.** The
  natural names inside it are `File`, `Buffer`, `Response` and `Stream` — three of which shadow
  something the body code uses constantly (`::File`, `Dexpace::IO::Buffer`, `Dexpace::Response`), and
  the shadowing is silent for `is_a?` and `case/when`. Flattening to `Dexpace::FileBody`,
  `Dexpace::BufferBody` and `Dexpace::ResponseBody` collides with nothing and adds no `SHADOWED` entry.
- **A flat constant in a subdirectory already has a precedent in this repository.**
  `Dexpace::InvalidArgumentError` is at `lib/dexpace/error/…` and 3a's `Dexpace::StreamError` at
  `lib/dexpace/error/stream_error.rb`. The constant is flat; the file is filed where it belongs.

**`Dexpace::Body` is a module, and it is three things at once**, each of which needs it to be exactly
this and not an interface or a base class:

1. **The shared contract**, included by every body class — `#replayable?` defaulting to `false`
   (`BODY-1`), `#content_length` defaulting to `-1` (`BODY-35`), `#media_type` defaulting to `nil`
   (`HTTP-36`), `#to_replayable` (`BODY-3`/`HTTP-37`), `#each` derived from `#write_to` (§10.2), and
   the one private exact-length copy routine `HTTP-39`/`BODY-10` and `BODY-13` share. Same shape as
   3a's `TypedReads` over one `#fill` hook: here the hook is `#write_to(sink)`.
2. **The factory home `HTTP-38`/`BODY-35` asks for** — "Body factories MUST classify replayability by
   source" is one sentence and wants one place: `Body.bytes`, `.string`, `.file`, `.stream`,
   `.chunked`, `.form`, `.multipart`, `.buffer`.
3. **The type `DEF-26` narrows `sig/` to.** RBS understands a module used as a type as "an instance of
   a class that includes it", so `Request#body: Dexpace::Body?` type-checks, and Steep then sees every
   variant. An RBS interface would work too and is rejected: an interface cannot carry the default
   implementations of point 1, so every variant would restate `#replayable? = false`, which is the
   drift the module exists to prevent.

Not a base class, because Ruby has single inheritance and `MultipartBody` and `ResponseLoggingBody`
both want to compose with something else later; a module costs nothing and forecloses nothing.

**Every name below is `NFR-4`-locked at the first release tag**, which is why each is chosen on purpose
and all of them carry one Deviation Ledger row, **P3-14**, in the shape phase 2 used for its six
unnamed constants and 3a used for P3-8.

### The twelve public constants and where each comes from

| Constant | IDs | Why it exists as its own class |
|---|---|---|
| `Dexpace::Body` | `HTTP-36`, `BODY-1`, `BODY-35`, `HTTP-38` | The contract, the factories and `DEF-26`'s type |
| `Dexpace::BytesBody` | `HTTP-38`/`BODY-35` | Byte-array and string bodies; replayable with an exact length |
| `Dexpace::BufferBody` | `BODY-3`/`HTTP-37`, `HTTP-52`/`BODY-30` | The product of materialize-once and of the bounded error copy — a body over a `Dexpace::IO::Buffer` core owns |
| `Dexpace::FileBody` | `HTTP-40`/`BODY-11`, `BODY-12`, `BODY-13` | `BODY-11`'s fail-fast construction and fresh-handle-per-write are a class's invariants, and `BODY-12` clause 2 needs a **type** a transport can recognise |
| `Dexpace::StreamBody` | `HTTP-38`/`BODY-35`, `BODY-6`–`BODY-9` | The rewindable/one-shot split of R9 lives here, and so do the consume-once latch and `BODY-8`'s opt-in close |
| `Dexpace::ChunkedBody` | §10.2, `BODY-6`, `BODY-7` | A body over an `#each`-shaped object — the canonical representation as a body |
| `Dexpace::FormBody` | `HTTP-38`/`BODY-35` | Always replayable, `x-www-form-urlencoded`, the encoder phase 1 handed here |
| `Dexpace::MultipartBody` (+ nested `::Part`) | `BODY-2`, `HTTP-51` | One shared framing routine so declared length cannot drift from bytes written |
| `Dexpace::ResponseBody` | `HTTP-41`/`BODY-14`, `BODY-15`, `HTTP-43` | Single-use handle over a `BufferedSource`, closeable, owning the transport resource |
| `Dexpace::RequestLoggingBody` | `BODY-17`–`BODY-21`, `BODY-37` | The tee-on-write wrapper |
| `Dexpace::ResponseLoggingBody` | `BODY-22`–`BODY-29` | The drain-once wrapper, two regimes |
| `Dexpace::TypedResponse` | `HTTP-44`, `HTTP-45` | Design §7.3 names it, flat |

Plus, and each named on purpose:

- `Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES = 1024 * 1024` — `BODY-30`/`HTTP-52`'s fixed cap. Design
  §5.1 puts "the one constant" inside phase 4's `Dexpace::Recovery.buffer_error_body`; it moves one
  layer down because the operation that reads it is a body operation and 3b ships that first. Phase 4's
  step reads this constant rather than declaring a second one — one number, and the addendum below
  records the move.
- `Dexpace::Body.buffer_bounded(body, cap:)` — the bounded replayable copy (R8).
- `Dexpace::PercentEncoding.encode_form(pairs)` and `.encode_form_component(text)` — the form encoder
  phase 1 handed here. It goes **beside** the RFC 3986 encoder rather than in a module of its own,
  because `url-and-query-encoding/9ff11c34` requires "two distinct functions with distinct tests that
  are never interchanged" and the strongest guard against the mix-up is the two of them in one file
  with the comment that says so. Two functions, not two modules.
- The RBS interface `Dexpace::_ResponseHandler` (R7). No runtime constant, so `gates:sig_diff` is its
  only gate — which is why it is named deliberately.

## R7 — `HTTP-44`/`HTTP-45` without a witness

**The handler is any object responding to `#call(response)`.**

`Dexpace::TypedResponse.new(response:, handler:)`, with `handler` validated by `respond_to?(:call)` at
construction and never by a nominal test. The RBS interface is

- `Dexpace::_ResponseHandler` — `def call: (Dexpace::Response) -> untyped`

and it names no constant outside `Dexpace::`, so `NFR-11`'s scan is clean and no phase-7 type appears in
a phase-3 signature.

**Why `#call(response)` and not something narrower.** Design §7.3 says the witness is "the handler",
which reads as though `TypedResponse` should take a `SEAM-22` witness directly. It cannot, and the
reason is in the witness's own shape: a witness is "any object responding to `.dexpace_load(parsed,
ctx)`" — it takes an **already-parsed** value and a context, not a response and not bytes. Something
has to read the body, choose a codec, parse, and only then call the witness; and `serde/4b78c08d`
requires that something to be **status-aware** — "decode the body only on a 2xx status, throw the mapped
HTTP-error exception carrying a bounded buffered copy of the error body on 4xx/5xx, and on any other
non-2xx status close the response and raise". So the thing `TypedResponse` invokes needs the whole
response, and the witness sits *inside* it. `#call(body)` or `#call(bytes)` would be narrower and would
force phase 7 to **replace** `TypedResponse` rather than supply a handler into it.

**Why `#call` and not a `dexpace_`-prefixed name.** A `Proc` and a lambda respond to `#call`, so a test
double is one line and needs no support class; `api-design/88e6bf12` asks for the narrowest duck-typed
interface a public method actually uses, and `#call(response)` is exactly it. The `dexpace_` prefix
exists on the witness protocol to avoid colliding with a model class's own methods, which is not a risk
for a callable.

**What 3b implements, and what it must not.** `HTTP-44` opens with a clause that is easy to read past
because it costs one line: the wrapper "MUST expose raw status/headers/protocol/reason/request WITHOUT
consuming the body". `TypedResponse` therefore carries `#status`, `#headers`, `#protocol`, `#reason` and
`#request` as plain forwards to the wrapped `Response` — none of them touches `#value`, `@state` or the
body, and that is asserted rather than assumed, because a memo that reads `#status` through `#value`
would consume the body to answer a header question. `#response` is exposed for the same reason. Then the
memo: `HTTP-44`'s is an explicit `@state` machine —
`:unstarted`, `:running`, `:done`, `:failed` — with the outcome in `@value` or `@error` and **never**
inferred from `@value` being `nil`, because `@value ||= handler.call(response)` re-runs the handler for a
witness that legitimately decodes to `nil` and the second run reads a single-use body that is already
gone (§7.3's P13 case). A memoized failure is re-raised as the same object, which verified fact 6 shows
keeps its `#cause` and its original backtrace. `HTTP-45`'s serialization is §3.1's `BODY-22` shape
reused unchanged: a `Thread::Mutex` held **only** across the `@state` flip and never across the parse,
with a caller arriving mid-parse waiting on a `Thread::ConditionVariable` over the same mutex
(`serde/97665a9a`). 3b builds no witness, no codec and no status-aware handler.

## R8 — the boundary against phase 4

**The line is the argument type. A body operation takes a body; a step takes a response.**

| Mechanism | Side | What it is |
|---|---|---|
| `Dexpace::Body.buffer_bounded(body, cap:) -> Dexpace::BufferBody` | **3b** | Drains at most `cap` bytes of `body` into a `Dexpace::IO::Buffer`, **stops reading** rather than reading and discarding, returns a replayable buffer-backed body, and calls the original's `#close` in an `ensure` — unguarded, because `#close` is on the contract (P3-23) — so a failure to allocate still releases the connection. Independently and repeatably readable afterwards, because a `BufferBody` writes through a fresh `#peek` view and hands out a fresh one from `#source`, never consuming its buffer |
| `Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES` | **3b** | The one number. `RETRY-36` and `BODY-30` share it (§5.1) |
| `Dexpace::Status#error?` | **phase 1** | `BODY-31`'s 4xx/5xx classification, already shipped as `HTTP-11`. 3b writes no second predicate |
| `Dexpace::Recovery.buffer_error_body(response)` | **phase 4** | The recovery-chain step: returns the response unchanged when `status.error?` is false **or the body is nil**, otherwise calls `Body.buffer_bounded` with the constant and returns a response carrying the buffered body |
| The error-mapping step, `RECOV-15`/`XCUT-8`'s exception factory | **phase 4** | Turns an error response into an exception |

**`Body.buffer_bounded` is deliberately status-blind.** It never looks at a status, which is what makes
"error-to-exception mapping MUST apply only to 4xx/5xx" (`BODY-31`) impossible to get wrong from inside
the body layer: the only thing that can classify is the step, and the only thing that can classify is
phase 1's `Status#error?`. 3b's `BODY-31` row is therefore a **cross-reference**: the predicate is phase
1's, the step is phase 4's, and 3b's contribution is the negative guarantee plus its test — no body
operation consumes, closes or re-serves a body on the basis of a status.

**`BODY-30`'s clauses split the same way.** "Buffer at most a fixed cap", "dropping bytes beyond the
cap", "readable independently and repeatably after the connection is released" and "buffering MUST occur
inside the original body's close-guaranteeing scope" are all 3b. "A response with no body MUST be
returned unchanged" is a statement about a *response* and is phase 4's, in the same step that asks
`status.error?`. `HTTP-52` is the same MUST from the HTTP side and splits identically; 3b's row cites
the body half and names phase 4 for the rest.

**`BODY-33`'s preview is 3b's, entirely.** "An exception-side error-body preview SHOULD be
non-consuming: it reads from a fresh peek view of the body's source and MUST NOT advance the primary
read path, returning null when there is no body and an empty result when the source is exhausted." The
peek view and the non-advancing read are `Dexpace::ResponseBody#preview(cap:)`, built on 3a's `#peek`;
the "null when there is no body" half is the caller's `nil` check on `response.body`, which is phase
4's call site. One method, one row, the `nil` clause named as the caller's.

## R9 — `BODY-9`'s mark/reset clause, given a Ruby subject

**The antecedent is seekability, probed at construction with `pos` + `seek(pos)`, and the SHOULD is
implemented.**

`BODY-9` conditions replayability on "the stream supports mark/reset AND the length fits the platform's
maximum single-array bound". Ruby has no mark/reset. Three candidate antecedents were tested on all
three interpreters (verified fact 2):

| Candidate | Result |
|---|---|
| `respond_to?(:rewind)` | **Useless.** `true` for a pipe, a socket, a `StringIO` and a `File` alike |
| A trial `#rewind` | **Discriminates, and is destructive.** It raises `Errno::ESPIPE` on a pipe or socket even at position 0 with nothing consumed, and the stream stays readable — but on a `File` handed over at a non-zero offset it silently moves the caller's cursor to byte 0 |
| `origin = io.pos; io.seek(origin, ::IO::SEEK_SET)` | **Discriminates and is non-destructive.** Raises `Errno::ESPIPE` on a pipe or socket; a genuine no-op on a `File` or `StringIO` at any position, verified by reading the same bytes before and after |

So `Dexpace::StreamBody` probes once at construction — guarded by `respond_to?(:pos)` **and**
`respond_to?(:seek)`, since the factory accepts any `#read`- or `#readpartial`-shaped object and neither
method is implied by either, and a bare probe would raise `NoMethodError`, which no `SystemCallError`
rescue catches — inside a `rescue ::SystemCallError` (verified: `Errno::ESPIPE` is a `SystemCallError`
and a `StandardError`, and **not** an `IOError`, so a bare `rescue IOError` would not catch it), and
stores two frozen construction-time facts: `@rewindable` and `@origin`. It is `#replayable?` when
**all four** of the conditions below hold — `BODY-9`'s three, and one `BODY-8` forces —

1. `@rewindable` is true;
2. the length is **known** (`content_length` is not `-1`), which `BODY-9` requires literally ("a
   stream-backed request body **of known length**");
3. the length is at most `Dexpace::IO::MAX_MATERIALIZED_BYTES`, which is §10.18's substitution for "the
   platform's maximum single-array bound" and the same ceiling `IO-9` and `BODY-32` share (boundary 8);
   and
4. **ownership was not transferred** — `close: false`. This one is not `BODY-9`'s and is not optional:
   `BODY-8` obliges an owning single-use body to close its source as part of its single write, so a
   body that both owns its stream and claims replayability would close the stream on the first write
   and then `seek` a closed handle on the second. The two clauses are only compatible by making
   ownership transfer imply single-use, and `Body.stream(io, …, close: true)` therefore never returns a
   replayable body however seekable the stream is. `#rewindable?` is public precisely so a test can
   tell "the probe said no" from "`BODY-8` forbids replay".

— and single-use otherwise, which is `BODY-9`'s own "otherwise it MUST be single-use" and `HTTP-38`'s
matching clause.

**Replay rewinds to `@origin`, not to byte 0**, and that is the finding that makes the probe worth
having: a caller who hands the body a `File` already positioned at byte 4096 means the body starts
there, and rewinding to 0 would silently send 4096 bytes the caller never asked for. The probe captures
the position it must return to at the same moment it proves it can.

**Race-safety.** `BODY-9`'s "the rewind MUST be race-safe (at most one reset between any two writes)"
uses the same shape as `BODY-7`'s consume-once guard: a `Thread::Mutex` held **only** across a
`@writing` flag flip and never across the read, per `concurrency-and-async/e94924e3` and verified fact
8. A second concurrent write on a replayable stream body observes the flag and raises
`Dexpace::StreamError` rather than issuing a second `seek` under the first write's read — which is what
"at most one reset between any two writes" means when the writes overlap.

Recorded as **P3-16**.

## R10 — `BODY-24`'s over-cap tail and `IO-42`'s in-memory exemption

**`IO-42` governs surfaces, not objects, and the over-cap regime is two objects behind one close-once
guard — not one object that is both.**

`ResponseLoggingBody` holds three things after a drain: a `Dexpace::IO::Buffer` holding the captured
prefix (or the whole body), the delegate, and — in the over-cap regime — the single-use composite
stream it hands out. Each has its own `IO-42` answer, and both wrong answers are the two directions
`IO-42`'s own rationale names.

| Surface | `IO-42` answer | The requirement that forces it |
|---|---|---|
| The captured `Dexpace::IO::Buffer` | **Exempt.** Its reads keep working after anything closes, because it wraps no external stream and its close frees nothing | `BODY-28`: "the captured in-memory buffer MUST survive the wrapper's close … so post-mortem snapshot logging still works after close." 3a already expresses this as `Buffer#reads_survive_close?` returning `true` |
| The over-cap composite stream (`BODY-24`) | **Not exempt.** It holds the live delegate, so every read after close raises `Dexpace::ClosedError`, and a second read raises whether or not anything is closed | `BODY-24`: "A second read in this regime MUST fail (the tail is single-consumer)", and `IO-42`'s "use-after-close of a real resource fails loudly" |
| Views derived from the captured buffer (`BODY-23`) | **Invalidated by the buffer's close, never by the wrapper's** | `IO-42`'s second half: "its close() MUST still invalidate every slice derived from it" |

**The rule that keeps the three consistent: the wrapper's `#close` closes the delegate and does not
close the captured buffer.** The buffer holds only memory; closing it would invalidate every outstanding
`BODY-23` view for no gain and would put `BODY-28`'s post-mortem snapshot one refactor away from
breaking. It is released when the wrapper is collected, which is the one place in this SDK where
relying on the collector is correct precisely because there is no resource to release
(`resource-management/1676974d` is about *deterministic resource cleanup*, and memory is not one).

**The composite is `BufferedSource.wrapping` over a private tail object whose `#close` calls the
wrapper's** — the tail serves the captured prefix from a fresh `#peek` view of the buffer and then
continues from the delegate, and it is `#read`-shaped rather than `#each`-shaped because that is what
`.wrapping` accepts (3a: "anything responding to `#readpartial` or `#read`").

**`BufferedSource.over` was the obvious choice and it is rejected**, because `BODY-27` does not bear the
reading that makes it work. `.over` owns nothing (3a's R3), so the tail's `#close` — a real, public,
callable method, since every `BufferedSource` carries `Closeable`'s — would do nothing to the delegate.
That is not "one close path, so a single guard holds trivially": it is a **second close path that routes
nowhere**, which is precisely the object the requirement's own sentence forbids — "the wrapper's own
close **and the one-shot tail stream's close** MUST route through a single shared close-once guard", and
ch.06 §6.6 words it the same way. A clause that names two paths is not satisfied by making one of them
inert; if it were, the requirement would be unfalsifiable. The harm is concrete rather than formal:
`BODY-24` hands the tail to a consumer *as the rest of the body*, the consumer's idiomatic release is to
close what it was handed (`resource-management/bf5560dc`, and `IO-6`'s whole ownership discipline), and
under `.over` that close releases no transport resource at all — `BODY-15`'s "closing releases the
underlying transport resource" lost one layer up, with a YARD sentence standing in for the mechanism a
MUST names.

`.wrapping` takes ownership (`IO-6`), so closing the returned source closes the tail object, whose
`#close` calls the wrapper's `#close` — `Closeable`'s latch, one guard, both paths, at most one delegate
close in either order, and a delegate whose close raises still marked closed (`BODY-27`'s second
sentence). The wrapper's own `#close` closes the **delegate** and not the tail, so there is no cycle;
and `Closeable`'s mutex is held only across the flip, so even a cycle would not deadlock.

**The cost is stated rather than hidden.** `.wrapping`'s read path is `OI-9`'s one-byte-per-read defect
until `OI-9` is resolved, and the tail sits on top of a delegate whose own source is already
`wrapping`-backed, so an over-cap body pays it twice — and this is the consumer's real byte path, not a
preview, because `BODY-24` routes the whole remaining body through it. It is still the right trade:
`OI-9` is a measured throughput defect with a named one-line fix that removes it from both layers at
once, and what it is traded against is a transport connection that is never released at all.

§7.1's residue applies and is bounded: the tail holds the wrapper's own state, not an unowned resource,
and the delegate stays reachable from the wrapper.

## The object model 3b ships

### `Dexpace::Body` — the contract, the factories, the constants

A public module included by every body class, over exactly one hook every includer implements:
`#write_to(sink) -> Integer`. Every other member has a default, including the two the response side
needs — `#source`, whose default raises, and `#close`, whose default is a no-op — so a request body
implements one method and the three bodies that can occupy `Response#body` override two more (below).
Public and not `private_constant` for the reason 3a gave `TypedReads`: the runtime surface snapshot walks `public_instance_methods(false)` and cannot see a
method reaching a class through a module, so a private module would hide most of 3b from the gate that
exists to see it.

| Member | ID | Note |
|---|---|---|
| `#write_to(sink) -> Integer` | `HTTP-36` | The **single write-to-sink operation**. `sink` is anything responding to `#write` (`Dexpace::IO::_Sink`) — a `TeeSink`, a `BufferedSink`, a `Buffer`, a raw `::IO`. Returns the byte count. Every includer implements this and nothing else is required of it |
| `#media_type -> Dexpace::MediaType?` | `HTTP-36` | Nullable, default `nil` |
| `#content_length -> Integer` | `HTTP-36`, `BODY-35` | Exact when known, **`-1`** when not. Not `nil`: `BODY-35` fixes the sentinel and an ID-bearing rule wins |
| `#replayable? -> bool` | `BODY-1` | **Default `false`.** True only where writing more than once yields byte-for-byte identical output |
| `#to_replayable -> Dexpace::Body` | `BODY-3`, `HTTP-37` | `self` when already replayable; otherwise drains `#write_to` once into a `Dexpace::IO::Buffer` and returns a `BufferBody`, leaving the original consumed |
| `#each { \|String\| } -> nil` | §10.2 | Derived once, here, as a `#write_to` against a block-shaped sink — so every body has exactly **one** byte-producing implementation and `BODY-17`'s "the exact bytes the wrapped body's single write produces" cannot differ between the two paths |
| `#source -> Dexpace::IO::BufferedSource` | `HTTP-41`/`BODY-14`, `HTTP-42`, `BODY-16`, `BODY-30` | **The read handle**, and the second half of the contract `Response`'s three methods are written against. `HTTP-41`'s own text names it — "its read handle (source)" — so there is one name for it, on the module, and not one name per class. The module's **default raises `Dexpace::StreamError`** with a message naming the class, because the seven request-body variants have no read handle and never occupy `Response#body`; a raising default rather than an absent method is what makes the `sig/` declaration true of every `Dexpace::Body`, which is what lets `Response#body_string` type-check against `Dexpace::Body?`. The three bodies that *can* occupy the slot override it |
| `#close -> nil` | `HTTP-43`, `HTTP-41`/`BODY-15`, `BODY-16`, `BODY-30` | **Default: a no-op.** `HTTP-43` forwards a response's close to its body unconditionally and `Request::Builder` coerces nothing, so *every* body must answer `#close`; a body owning no transport resource has nothing to release. The default is not laziness — `BODY-30` **requires** it: the buffered error copy must survive `#body_string`'s `ensure`-close and stay "readable independently and repeatably". `Dexpace::Closeable`'s `#close` overrides it in the two classes that own something, because the include order is `include Dexpace::Body` **then** `include Dexpace::Closeable` and the later include sits nearer the class in the ancestor chain |
| `#==` / `#eql?` / `#hash` | `HTTP-46` | Over each variant's own construction-time facts. `DEF-26` |
| `.bytes`, `.string`, `.file`, `.stream`, `.chunked`, `.form`, `.multipart`, `.buffer` | `HTTP-38`, `BODY-35` | The factories, in one place, each naming the replayability it confers. Eight factories over seven classes: `.string` and `.bytes` both return a `BytesBody`, because `HTTP-38` classifies a string and a byte array identically and two classes for one behaviour is one more than the requirement asks for |
| `.buffer_bounded(body, cap:)` | `BODY-30`, `HTTP-52` | R8 |
| `MAX_BUFFERED_ERROR_BODY_BYTES` | `BODY-30`, `HTTP-52` | 1 MiB, fixed by the requirement |
| private `copy_exactly(source, sink, count)` | `HTTP-39`/`BODY-10`, `BODY-13`, `BODY-25` | **One** exact-length copy routine for the whole body layer, raising `Dexpace::StreamError.short_transfer` on a premature end and `.zero_read` on a zero-length read for a positive request, and treating a declared length of `0` as a legitimate empty write |

**`#source` and `#close` are one decision, and it is the module's rather than three classes'.**
`Dexpace::Response#close`, `#body_string` and `#body_bytes` are written against exactly two members of
whatever `Response#body` holds — `#source` for the bytes and `#close` for the release — and `HTTP-36`
enumerates neither, so without this row they are called through a contract that does not declare them.
Three body types can legitimately hold that slot, and each arrives from a different phase:

| Body | Put there by | `#source` | `#close` |
|---|---|---|---|
| `Dexpace::ResponseBody` | the transport (`HTTP-41`/`BODY-14`) | the **same underlying handle** every call | `Closeable`'s latch, releasing the transport resource (`BODY-15`) |
| `Dexpace::ResponseLoggingBody` | phase 5's body logging (`BODY-22`–`BODY-29`, `BODY-34`) | the regime's accessor: a fresh `#peek` view fits-cap, R10's composite over-cap | `Closeable`'s latch, `BODY-27`'s shared close-once guard |
| `Dexpace::BufferBody` | phase 4's `Recovery.buffer_error_body` (`BODY-30`/`HTTP-52`) | a **fresh `#peek` view per call** | the module's **no-op** |

Two of those three cells are forced rather than chosen. `BufferBody#source` is a *fresh* view each call
because `BODY-30` says the buffered copy must be readable "independently and **repeatably** (decode it,
then snapshot it) after the original transport connection is released" — `BODY-14`'s same-handle rule is
about the single-use response body and does not reach a replayable in-memory copy, and applying it here
would make the second of `BODY-30`'s two named reads return nothing. And `BufferBody#close` must be a
no-op because `BODY-16` closes the body in an `ensure` on the way out of `#body_string`, so a close that
invalidated the buffer would destroy the copy between `BODY-30`'s "decode it" and its "snapshot it".
Declaring both on the module rather than per class is what makes `HTTP-43`'s "forward to the body"
total: `Request::Builder` coerces nothing (below), so there is no type-level guarantee about what sits
in `Response#body`, and a `respond_to?`-guarded forward would be the same gap with a quieter failure.
Recorded as **P3-23**.

**`HTTP-46`'s by-value equality, made concrete.** Each variant defines `#==`, `#eql?` and `#hash`
together over the facts that determine its bytes — `BytesBody` over its frozen bytes and media type,
`FileBody` over path, offset, count and media type, `BufferBody` over its buffer's snapshot,
`FormBody`/`MultipartBody` over their parts, and `StreamBody`/`ChunkedBody`/`ResponseBody` over the
stream object itself, which makes their equality identity — correctly, because two different open
streams are two different values. All three are defined together, never `#==` alone: phase 1's
`Request#hash` folds the body in, and a body with a value `#==` but an identity `#hash` would break the
`hash`/`eql?` contract for every `Request` used as a `Hash` key.

### The seven request-body variants

| Class | Replayable? | Owns / closes | IDs |
|---|---|---|---|
| `BytesBody` | **yes** | nothing | `HTTP-38`/`BODY-35`, `BODY-1` |
| `BufferBody` | **yes** — `#write_to` writes through a fresh `#peek` view and closes it in an `ensure`, so it never consumes its buffer; `#source` hands out a fresh view per call for the same reason | its own `Buffer` (memory), which its **no-op `#close`** deliberately does not release (`BODY-30`) | `BODY-3`/`HTTP-37`, `BODY-30`, `HTTP-52` |
| `FileBody` | **yes** — a fresh `::File` handle per write | the handle it opened, per write, in an `ensure` | `HTTP-40`/`BODY-11`, `BODY-12`, `BODY-13` |
| `StreamBody` | **conditional** — R9 | the caller's stream **only when `close: true` was passed at the factory** | `HTTP-38`/`BODY-35`, `BODY-6`–`BODY-9` |
| `ChunkedBody` | **no**, unconditionally | nothing | §10.2, `BODY-6`, `BODY-7` |
| `FormBody` | **yes** | nothing | `HTTP-38`/`BODY-35` |
| `MultipartBody` | **conjunction over its parts** | nothing of its own; each part owns what it owns | `BODY-2`, `HTTP-51` |

**`FileBody` is the one that carries the most requirement per line.** `HTTP-40`/`BODY-11`'s fail-fast
construction validates, in this order and before any I/O beyond one `::File.stat`: the path exists; it is
a **regular** file; `offset` is a non-negative `Integer`; `count` is a non-negative `Integer` or the
rest-of-file sentinel; and `offset + count` is within the size captured at construction. Every failure
is `Dexpace::InvalidArgumentError` naming the argument. `#write_to(sink)` opens a fresh handle, calls
`::IO.copy_stream(handle, sink, count, offset)` — verified fact 4: it accepts a duck-typed `#write`
destination, honours the window, and does not disturb the handle's own cursor — closes the handle in an
`ensure`, and raises `StreamError.short_transfer(transferred:, expected:)` when the return is short,
which is `BODY-13` through 3a's shared helper. **`#to_path` is deliberately not defined** (verified fact
5): it would let `::IO.copy_stream(body, socket)` copy the whole file and silently ignore the body's
window. `#path`, `#offset` and `#count` are public instead, which is what `BODY-12`'s "recognizable by
type so transports can dispatch a true zero-copy kernel path" needs from this side. **P3-17.**

**`ChunkedBody` is single-use and takes no `replayable:` keyword.** An `#each`-shaped object may or may
not re-yield identical bytes, and `BODY-1` permits `true` **only** when it provably does. A keyword
would let a caller assert a property `BODY-1` says must be earned, and the assertion would be believed
by the retry, redirect and 401 paths. A caller with a genuinely repeatable source uses `Body.bytes` or
calls `#to_replayable`. Recorded as **P3-19**.

**`MultipartBody` derives its length and its bytes from one routine** (`HTTP-51`): one private
`emit(sink)` that writes the boundary, the part headers and the part bodies, and one `#content_length`
that runs the same routine against a counting sink, so the declared length cannot drift from the bytes
written. The boundary is generated with `SecureRandom` from the RFC 2046 `bcharsnospace` set, 1–70
characters; a caller-supplied boundary violating that grammar is rejected with
`Dexpace::InvalidArgumentError`. `HTTP-51`'s one MUST inside a SHOULD — "quote/escape part header
parameter values so CR/LF or a quote cannot break the framing" — is **two mechanisms and not one**, and
conflating them is how it gets implemented wrongly: a parameter value is emitted as a quoted-string with
`\` and `"` **escaped**, while a CR or an LF is **rejected**, because a quoted-string has no
representation for either and an "escaped" CRLF is still a CRLF on the wire — escaping it would be the
framing break the MUST exists to prevent. Phase 1's `HeaderSyntax.valid_outbound_value?` is then run
over each assembled header line as a second, whole-line sweep, so a caller-supplied part header rather
than a parameter value is caught by the same predicate and not by a second copy of it. `BODY-2`'s
conjunction is `parts.all?(&:replayable?)`, and the declared length collapses to `-1` if any part's is
`-1`.

**The consume-once guard, once, for the two single-use variants.** `StreamBody` (when not replayable)
and `ChunkedBody` share one latch: a `@consumed` flag flipped under a `Thread::Mutex` held **only**
across the flip and never across the write (`concurrency-and-async/e94924e3`, verified fact 8). A second
write raises `Dexpace::StreamError` (`BODY-6`), and under concurrent writes exactly one passes and every
loser sees the same error (`BODY-7`). Two IDs, one mechanism, two tests — the second of which is a real
concurrency proof and not a restatement of the first.

**`BODY-8`, recorded rather than re-opened.** §10.12 already decided it, and the decision is: **a body
closes exactly the sources it opened.** `FileBody` opens and closes a handle per write. `StreamBody` and
`ChunkedBody` over a caller-supplied stream or `#each` object close **nothing**, unless ownership was
transferred explicitly at the factory (`Body.stream(io, …, close: true)`) — at which point `BODY-8`'s
MUST applies and the single write drains-and-closes, so skipping materialization does not leak it.
`ResponseBody` owns its source, transferred explicitly at construction by the transport that built it.
`message-bodies/627eaeab` states exactly this and is adopted verbatim. 3b does not generalise the rule
over the codec's, which is phase 7's and opts out of both (boundary 5).

### `Dexpace::ResponseBody` — the single-use handle

Includes `Dexpace::Body` **then** `Dexpace::Closeable` — that order everywhere a body is closable, so
`Closeable#close` sits nearer the class than the module's no-op default and wins. Wraps a
`Dexpace::IO::BufferedSource` the transport built with `.wrapping`, so closing it closes the transport
stream.

- `.new(source:, media_type: nil, content_length: -1)` and a block form that closes on any exit
  (`resource-management/bf5560dc` — this is 3b's only closable factory).
- `#source -> Dexpace::IO::BufferedSource` — the module's member, implemented here as `HTTP-41`/`BODY-14`
  requires: **the same underlying handle every time**, never a fresh replay. Repeatable access requires
  `ResponseLoggingBody` or `Body.buffer_bounded`, and those two answer `#source` differently on purpose
  (P3-23).
- `#close` — `BODY-15`: releases the transport resource, idempotent through `Closeable`'s latch, and
  **does not assume the body was read**.
- `#preview(cap:) -> String` — `BODY-33`: a fresh `#peek` view, a capped read, the view closed in an
  `ensure`, and the primary read path unmoved. Empty when exhausted.
- `#replayable?` is `false` and `#write_to` raises after the source is consumed — a response body is a
  reader, and offering it as a request body without materializing it is `BODY-14`'s failure.

### The two logging wrappers

**`Dexpace::RequestLoggingBody`** — `.new(delegate, tap_limit: ::Float::INFINITY)`, including
`Dexpace::Body`.

- `#write_to(sink)` builds a **fresh** `Dexpace::IO::TeeSink.new(primary: sink, tap_limit: @tap_limit)`,
  keeps it as `@tee`, and calls `@delegate.write_to(@tee)`. `BODY-17`'s "mirror the exact bytes … while
  forwarding those same bytes … consuming the upstream exactly once" is the tee's own `IO-25`, and the
  full untruncated payload reaching the primary is `IO-25`/`IO-26`.
- **`BODY-18` is satisfied by construction.** A fresh tee per write cannot accumulate an earlier
  attempt's bytes, which is strictly stronger than clearing one — it also drops the previous attempt's
  memory. This is why 3a's `TeeSink#clear_tap` has no core caller (`OI-8`).
- **The wrapper never calls `#close`, `#flush` or `#emit` on the tee.** `IO-29` forwards all three to
  the primary, and the primary is the transport's sink, which the body does not own (`BODY-8`, §10.12).
  Nothing leaks: the tee holds a tap `Buffer` and a reference.
- `#snapshot -> String` reads `@tee&.tap_snapshot`, so a write that failed partway still returns the
  bytes mirrored up to the failure (`BODY-20`) — the tee mirrors **before** forwarding (`IO-27`), which
  is the ordering `IO-27` exists for.
- `#replayable?` is `@delegate.replayable?` **verbatim**, and `#to_replayable` returns
  `RequestLoggingBody.new(@delegate.to_replayable, tap_limit: @tap_limit)` — a wrapper around the
  delegate's replayable form, cap preserved (`BODY-21`), so a retry loop keeps capturing.
- `BODY-37` is `IO-28` restated at the body layer and is **one mechanism, not two**: the wrapper exposes
  no buffer handle and `TeeSink#buffer` already raises with the actionable message. Design §10.10
  records the honest position — the prohibition cannot be language-enforced, `instance_variable_get`
  reaches anything — and 3b neither re-derives it nor claims more (boundary 4).

**`Dexpace::ResponseLoggingBody`** — `.new(delegate, preview_bytes:)`, including `Dexpace::Body` **then**
`Dexpace::Closeable`.

- `#source`, `#snapshot` and `#error` each trigger the drain on first access; the drain runs **at most
  once, lazily**, with concurrent first accesses serialized through a `@state` flip under a
  `Thread::Mutex` and a `Thread::ConditionVariable` for the losers (`BODY-22`, the same shape as
  `BODY-7`'s and `HTTP-45`'s, held across the flip and never across the drain). The accessor is
  `#source` and **not** `#read`: it returns a `Dexpace::IO::BufferedSource` in both regimes, it is the
  member `Response#body_string` calls, and a method named `#read` returning a source rather than bytes
  would read against `::IO#read`'s own meaning besides (P3-23).
- **Fits-cap regime** (`BODY-23`): EOF reached before the cap. The wrapper captures everything into its
  `Dexpace::IO::Buffer`, closes the delegate through the close-once guard, and thereafter serves every
  read as a **fresh non-consuming `#peek` view** — fully repeatable, each read independent.
- **Over-cap regime** (`BODY-24`): the wrapper buffers only the prefix, **leaves the delegate open**,
  and serves the next read as the composite of R10 — prefix then live tail. A second read raises.
- `BODY-25`: a delegate read returning zero bytes for a positive count raises
  `Dexpace::StreamError.zero_read(requested:)`, never end of stream. 3a's helper, so the message form
  cannot diverge from `BODY-10`'s.
- `BODY-26`: a mid-drain failure retains the bytes already read and caches the error. Reads re-raise the
  **same object** every call (verified fact 6), `#snapshot` returns the partial bytes without raising,
  and `#error` surfaces the cached error without triggering a drain — three different behaviours over
  one cached value, and three tests.
- `BODY-27`: **one** close-once guard. `Closeable`'s latch, shared by the wrapper's own `#close` and by
  the over-cap tail's close, because some transport streams throw on double-close; a delegate whose
  close raises is still marked closed and the failure propagates once (§3.7's second loud exception).
  The tail's close *reaches* the latch because the composite is `BufferedSource.wrapping`-owned and its
  tail object's `#close` calls the wrapper's — R10, which is where `.over` is rejected and why.
- `BODY-28`: on the fits-cap path the delegate close is best effort — `Dexpace.close_quietly`, its
  **first call site in this SDK** — so a close failure is not reported as a drain error and does not
  prevent serving the captured body. The captured buffer survives the wrapper's close (R10).
- `BODY-29`: `#content_length` is the captured size **only** when the capture was complete, otherwise
  the delegate's declared length.

### The three additions to phase-1 types

| Change | ID | Why it is safe and why it is here |
|---|---|---|
| `Dexpace::Response#close` | `HTTP-43` | `body&.close` and nothing else. A `Data` instance is frozen and **cannot hold a latch**, which would be a problem if `HTTP-43` needed one — it does not: its own appendix-C text says "(Idempotency is delegated to the body's idempotent close per HTTP-41; a bodyless response close is a no-op.)" So a pure forward is the requirement stated literally, and `ResponseBody`'s `Closeable` latch is where idempotence lives |
| `Dexpace::Response#body_string` and `#body_bytes` | `HTTP-42`, `BODY-16`, `HTTP-41` | The **one** decode boundary and its byte-array sibling, both closing the body in an `ensure` whether or not the read succeeded (`BODY-16`) |
| `sig/` narrows `Request#body` and `Response#body` to `Dexpace::Body?` | `DEF-26`, `HTTP-46`, `NFR-4` | The lock diffs against the previous release tag and **there is none** — every gem is at `0.0.0` and nothing is published. Free now, not later, which is exactly why `DEF-26` targeted phase 3 |

**All three are written against `#source` and `#close`, which is why both are on `Dexpace::Body` and
not on one class.** The version of this design that reviewers first saw put `#source` only on
`ResponseBody`, called it `#read` on `ResponseLoggingBody`, and gave `BufferBody` neither — under which
`response.close` and `response.body_string` would have raised `NoMethodError` on exactly the body
`BODY-30`/`HTTP-52` puts into a response, the one whose canonical text says "decode it, then snapshot
it". Nothing in 3b's own suite would have caught it, because every `Response` 3b builds carries a bare
`ResponseBody`; the first failure would have been phase 4's, against code phase 3 shipped and phase 3's
tests pass over. The contract row and the three-body table above are the fix, and `OI-10` records the
finding and its resolution. It is worth stating in this section as well as that one, because this is the
section a later phase reads before adding a fourth thing that can sit in `Response#body`: whatever it
is, it answers `#source` and `#close` or it does not go there.

**No coercion is added at the builder, and that is a decision.** `Request::Builder#body=` continues to
accept and store whatever it is given; it does not turn a `String` into a `BytesBody`. Coercion would
put a second replayability-classification site next to `HTTP-38`'s one, and `HTTP-36` is explicit that a
request body is a thing with a write operation, a media type and a length — a `String` is not one. The
narrowing is a `sig/` change checked by Steep against `lib/`, and `DEF-23` records that no Steep target
covers a test tree, so phase 1's suites are unaffected.

## The spec-forced boundaries, honoured

1. **`IO-40` — no clock, no deadline.** No method in 3b takes a timeout, a deadline or a
   `Cancellation`. The only blocking calls are the delegate's own reads and the sink's own writes, and
   they block for exactly as long as the transport that owns the socket allows. `DEF-28`'s `deadline:`
   stays off the pivot until phase 5.
2. **`IO-37` with `IO-38`.** No body is thread-safe as a general contract. The **only** synchronised
   state in 3b is four flag flips — `BODY-7`'s consume-once, `BODY-9`'s replay claim (R9's `@writing`,
   a second flag under the same body-level mutex, not the same flag as `@consumed`), `BODY-22`'s drain
   latch and `HTTP-45`'s parse latch — plus `Closeable`'s. Each mutex is held across its flip and
   across nothing else.
3. **`IO-42`'s asymmetry, in both directions** — R10.
4. **`IO-28` ↔ `BODY-37`: one mechanism, two rows.** §10.10 records the honest position and 3b restates
   it without re-deriving it and without claiming more. `TeeSink#buffer` raises; the wrapper adds no
   second accessor.
5. **`IO-6` with `BODY-8`, per §10.12** — two rules, deliberately different, one decision. 3a fixed the
   I/O half and `.over`'s exception; 3b records the body half above and re-decides neither. The third
   rule — `SEAM-20`/`SEAM-21`/`SERDE-3`, a codec closes nothing — is phase 7's, and 3b neither
   implements nor weakens it, and does not generalise its two rules over it.
6. **`BODY-4`'s three declines are not unified.** 3b ships **one** `#replayable?` property. The three
   decline behaviours are documented at that property and in `Dexpace::Body`'s YARD — retry stops and
   surfaces the last outcome, auth returns the original challenge response unchanged **and does not
   close it**, redirect fails loudly — and are **implemented by phase 6, separately, in three places**.
   3b builds no gate, no shared predicate and no unified decline, because `BODY-4` says explicitly that
   a port need not unify them and design §3.1 preserves the difference.
7. **`HTTP-42`'s single decode boundary.** `Response#body_string` is the only place in the SDK that
   turns bytes into text. `#body_bytes` returns BINARY and decodes nothing; 3a's `#read_string` and
   `#read_utf8` retag and apply no policy; `ResponseLoggingBody#snapshot` and `ResponseBody#preview`
   return BINARY. **One decode site, and the addendum below is why it is two steps rather than one.**
8. **`IO-9`/`BODY-32`'s `MAX_MATERIALIZED_BYTES`** — one constant, one ceiling, cited and never
   re-derived. `BODY-32`'s capped preview rejects a negative cap with
   `Dexpace::InvalidArgumentError`, **silently clamps** the cap down to the ceiling, and returns
   whatever bytes exist up to the clamped cap without requiring that exactly that many exist (verified
   fact 10). The capless half — "a snapshot with no explicit cap MUST fail loudly when the captured
   size exceeds the platform maximum" — is 3a's `Buffer#snapshot`, already shipped.
9. **The retirement of the byte-stream provider seam.** 3b creates no registry, no factory seam and no
   installation call.
10. **`Dexpace::IO::` is fixed, and 3b is the first phase to consume the hazard gate at scale.** Every
    file 3b writes sits inside `module Dexpace`, where a bare `IO` is `Dexpace::IO` and `x.is_a?(IO)` is
    silently `false` for a real `::IO`. 3a's widened `Dexpace/QualifiedCoreConstant` now watches the
    one-segment `Dexpace` namespace across every gem's `lib/`, so `::IO.copy_stream`, `::IO::SEEK_SET`
    and `::File` are written qualified and the cop enforces it. **3b creates no constant that shadows a
    core class, so `SHADOWED` is unchanged** — 3a's standing rule is that a constant joins it in the
    same change that creates its shadow, and `Dexpace::FileBody` and `Dexpace::BufferBody` shadow
    nothing.

## Encoding, stated once for 3b

- **Bytes are always `Encoding::BINARY`** everywhere except the single decode boundary. Every chunk a
  body yields, every `String` `#snapshot` and `#preview` return, and every byte written to a sink is
  BINARY.
- **`String#b` is the ingress retag, never `force_encoding`** — `io-and-byte-streams/a44b4de6`, and the
  reason is that `force_encoding` raises `FrozenError` on a frozen `String` even when the target
  encoding is already the string's own, and the chunks a Rack-shaped body yields are frozen.
- **The one decode boundary is `Response#body_string`, and it is two steps:**

  > resolve the charset — `media_type&.charset`, a `String?` phase 1 already validated against
  > `Encoding.name_list`, falling back to `Encoding::UTF_8` when it is `nil`; then **retag** the drained
  > BINARY bytes to that encoding (3a's `#read_string` does this); then **transcode with the target
  > named explicitly**, `#encode(enc, invalid: :replace, undef: :replace)`.

  Verified fact 1 is why all three steps are load-bearing: skipping the retag mangles every non-ASCII
  byte, and omitting the explicit target hands the result to the host's `Encoding.default_internal`.
  `#body_string` always returns a `valid_encoding?` `String` tagged with the resolved charset.
- **`#body_bytes` decodes nothing** and returns BINARY. Both readers close the body in an `ensure`
  (`BODY-16`).
- **Every encoding test in 3b uses non-ASCII content**, because an ASCII-only fixture passes under
  exactly the bug these rules prevent — 3a's finding, unchanged and re-applied.

## §7.1 applied — where the `Enumerator` rule bites in 3b

§7.1's rule: **resource acquisition and release never live inside an `Enumerator` block; the engine owns
the resource in its own scope and exposes `#close`.** Verified fact 3 widens it: **an ordinary `#each`
method is not a way around it.** Four consequences, and the third is honest rather than closed.

1. **`#each` is derived from `#write_to`, once, in `Dexpace::Body`.** There is one byte-producing
   implementation per body and `#each` is a `#write_to` against a block-shaped sink. That is what makes
   `BODY-17`'s "the exact bytes the wrapped body's single write produces" mean the same thing whichever
   path a transport takes, and it means the resource question is asked once instead of eleven times.
   **P3-21.**
2. **Bodies that hold a resource hold it on the object and expose `#close`.** `ResponseBody` owns its
   `BufferedSource`; a `StreamBody` with `close: true` owns its stream. Abandoning
   `body.to_enum(:each)` mid-`#next` on either leaks nothing that `#close` would not still release,
   which is exactly 3a's position for `BufferedSource#each`.
3. **`FileBody` is the one variant that *originates* a real residue, and it is documented, not closed
   — and it travels.** `BODY-11` requires a fresh handle per write, so the handle cannot live on the
   object. A consumer that drives `file_body.to_enum(:each)` with `#next` and abandons it before
   exhaustion leaks that
   handle: the `ensure` does not run, `#rewind` does not run it, and `GC.start` is not a cleanup hook —
   all verified. Nothing in Ruby closes this and 3b does not pretend otherwise. What 3b does: states it
   in `FileBody`'s YARD, notes that a **full** external drive to `StopIteration` **does** run the
   `ensure` (verified) so `BufferedSource.over(file_body)` driven to exhaustion is safe, and files the
   corpus note that widens `pagination/f57c50f6` so the next reader does not believe the rule stops at
   `Enumerator.new`. **The residue is inherited by anything whose bytes come from a `FileBody`** — a
   `MultipartBody` with a file part, a `RequestLoggingBody` over one — because `#each` is derived from
   `#write_to`, and the abandonment suspends inside the enclosing body's write just as it does inside
   the file's. It is one residue with one cause and one note, not four, which is why it is stated here
   rather than repeated per class; each affected class's YARD points at `FileBody`'s. This is the same
   shape as `.over`'s documented residue and as §10.10's admitted hole: an honest gap beats a fake
   proof.
4. **Every view core takes, core closes.** `BufferBody#write_to` and `ResponseBody#preview` each take a
   `#peek` view and close it in an `ensure`, which deregisters it from the parent. The one place a view
   outlives the call is `BODY-23`'s per-read view, which is handed to the caller — an instance of the
   growth `OI-4` describes ("a caller that takes many views and closes none"), reached on a **second**
   axis to the per-attempt one `OI-4` names for "phase 3b's per-attempt response-logging drain": one
   view per *read* of a captured body, not one per retry attempt. Both are the same registry and the
   same `Array#delete`. `OI-4` asks for a measurement on this drain rather than a redesign; the plan
   owns that measurement, and this document does not pre-empt its result.

## Module layout

Every file 3b creates or modifies. `sig/` mirrors `lib/` one file per file and ships inside the gem;
`test/` mirrors `lib/` one file per file and does not ship. Paths under `gems/dexpace-core/`.

```
lib/dexpace/http/body.rb                          Dexpace::Body, MAX_BUFFERED_ERROR_BODY_BYTES
lib/dexpace/http/body/bytes_body.rb               Dexpace::BytesBody
lib/dexpace/http/body/buffer_body.rb              Dexpace::BufferBody
lib/dexpace/http/body/file_body.rb                Dexpace::FileBody
lib/dexpace/http/body/stream_body.rb              Dexpace::StreamBody
lib/dexpace/http/body/chunked_body.rb             Dexpace::ChunkedBody
lib/dexpace/http/body/form_body.rb                Dexpace::FormBody
lib/dexpace/http/body/multipart_body.rb           Dexpace::MultipartBody (+ ::Part)
lib/dexpace/http/body/response_body.rb            Dexpace::ResponseBody
lib/dexpace/http/body/request_logging_body.rb     Dexpace::RequestLoggingBody
lib/dexpace/http/body/response_logging_body.rb    Dexpace::ResponseLoggingBody
lib/dexpace/http/typed_response.rb                Dexpace::TypedResponse

lib/dexpace/http/percent_encoding.rb              MODIFIED: .encode_form, .encode_form_component
lib/dexpace/http/response.rb                      MODIFIED: #close, #body_string, #body_bytes
lib/dexpace.rb                                    MODIFIED: requires for the tree above

sig/dexpace/http/request.rbs                      MODIFIED: body -> Dexpace::Body?   (DEF-26)
sig/dexpace/http/response.rbs                     MODIFIED: body -> Dexpace::Body?, + three methods
test/fixtures/surface/dexpace-core.txt            regenerated once, in the last task

test/support/fake_body.rb                         scriptable Dexpace::Body includer
test/support/fake_response_body.rb                a delegate whose #close raises, and whose read stalls
```

Twelve new `lib/` files with twelve `sig/` mirrors and twelve `test/` mirrors, three modified `lib/`
files, two modified `sig/` files, two new test-support doubles. `Dexpace::Body::Part` does not exist;
`MultipartBody::Part` is nested under its own class, which is phase 1's `Request::Builder` shape and not
a new namespace.

**`MAX_BUFFERED_ERROR_BODY_BYTES` lives in `body.rb`**, beside the module whose operation reads it —
phase 2's reading of `module-organization/1828a984` applied again, the same way 3a put
`MAX_MATERIALIZED_BYTES` in `io.rb`.

## Testing strategy

`test/` mirrors `lib/` one file per file; each file's header comment names the requirement IDs it
exercises, and a non-obvious branch names the ID that forced it. Every suite subclasses
`DexpaceTestCase`, so a warning raised by code under test fails the test that triggered it.

**No transport, and the constraint is satisfied trivially.** The roadmap puts phases 1 through 7 on an
in-memory fake transport implementing only the `SEAM-11`/`SEAM-16` seams. 3b touches no transport at
all: every `Dexpace::Response` under test is built directly through phase 1's `Response::Builder`, and
every sink is a `Dexpace::IO::Buffer`, a `StringIO`, an `IO.pipe` end or 3a's `FakeSink`. Phase 2's
transport fakes are not required here. No real socket appears until phase 8.

**What 3b reuses from 3a**, unchanged and required explicitly by the suites that use them, never from
`test_helper.rb`:

- **`FakeSink`** — `#write`, scriptable to return a short count and to raise partway. It is what
  `BODY-13`'s short write, `BODY-20`'s partial mirror and `IO-27`'s staging-clear need.
- **`FakeSource`** — `#read_into`, scriptable to return `0` for a positive count. That is `BODY-25`'s
  stream-contract violation, and no real Ruby stream produces it.
- **`FakeChunked`** — `#each`, scriptable to yield frozen literals, non-BINARY strings, an empty chunk
  between two non-empty ones, and a body whose `#each` carries an `ensure`. It is `ChunkedBody`'s input
  and §7.1's residue test in one double.

**What 3b must add**, and why each exists because no real object produces the behaviour:

- **`FakeBody`** — a `Dexpace::Body` includer with scriptable `#replayable?`, `#content_length`,
  `#media_type`, and a `#write_to` that can emit a scripted number of bytes and then raise. It is the
  delegate for both logging wrappers, and it is the only way to test `BODY-20`'s "the snapshot returns
  the bytes mirrored up to the failure" and `BODY-26`'s mid-drain failure deterministically.
- **`FakeResponseBody`** — a delegate whose `#close` **raises**, which `BODY-27` ("if the delegate's
  close throws it MUST still be marked closed") and `BODY-28` ("a close failure after a successful full
  capture MUST NOT be reported as a drain error") both require and which no `StringIO` will do.

**What stands in for a real stream.** `StringIO` and `File`/`Tempfile` for the seekable cases,
`IO.pipe` for the non-seekable one — `BODY-9`'s negative case is a **real** pipe raising a **real**
`Errno::ESPIPE`, not a simulation, which is what makes R9's probe test meaningful.

**The concurrency tests, which are the ones a reader would otherwise write wrong.**

| Case | Asserted |
|---|---|
| N threads calling `#write_to` on one single-use body, sequenced through a `Thread::Queue` | Exactly one succeeds; every loser raises `Dexpace::StreamError` with the consumed message (`BODY-7`) |
| Two fibers of one thread interleaving a drain on one `ResponseLoggingBody` | No `ThreadError`. Verified fact 8 makes this a real proof: a mutex held across a fiber suspension raises for the second fiber, so the test fails loudly under the bug it exists to catch (`BODY-22`) |
| Two fibers of one thread both triggering `TypedResponse`'s first access | No `ThreadError`, handler runs once (`HTTP-45`) |
| N threads on `TypedResponse#value` where the handler sleeps | The handler runs exactly once; every caller gets the same object (`HTTP-44`, `HTTP-45`) |
| A handler that returns `nil` | The handler runs **once**, not once per access — the `@value \|\|=` bug, asserted by counting invocations (`HTTP-44`) |
| A handler that raises | The **same exception object** every time, with `#cause` and backtrace intact (`HTTP-44`, verified fact 6) |
| `#close` on a `ResponseLoggingBody` from two threads with a delegate whose close raises | The delegate is closed once, the failure propagates once, the latch is still flipped (`BODY-27`) |
| Two concurrent writes on a **replayable** `StreamBody` | At most one `seek` happens between them (`BODY-9`'s race-safe rewind) |

**The `IO-42`/`BODY-28` pair gets two tests that fail in opposite ways**, because one "it still works
after close" test would pass over either error: the captured buffer's `#snapshot` **succeeds** after the
wrapper's close, and the over-cap tail's read **raises `Dexpace::ClosedError`** after it.

**P3-23's response-body surface is asserted over all three bodies, not over `ResponseBody` alone** — the
shape of the defect `OI-10` recorded was that the passing test used the one body that happened to have
the members. So: a `Response` is built over each of `ResponseBody`, `ResponseLoggingBody` and
`BufferBody` in turn, and `#close`, `#body_string` and `#body_bytes` are driven against each. The
`BufferBody` row carries `BODY-30`'s own two-step sentence as one test — **decode it, then snapshot it**,
in that order, after the close `BODY-16` performs — which fails if `#close` ever stops being a no-op and
fails if `#source` ever stops handing out a fresh view. `BODY-27`'s tail close gets the matching pair:
closing the tail alone closes the delegate exactly once, and closing the wrapper first then the tail
closes it exactly once as well.

**Property tests, bounded** (`testing/f36a19cd`, phase 0's `#sample(count:, seed:)`):

- **`HTTP-51`'s framing** — over N random part lists, `multipart.content_length` equals the byte count
  `#write_to` actually produces. That is the requirement's own reason for one shared routine, and it is
  the single most valuable property test in this sub-phase.
- **`HTTP-42`'s decode** — over random byte strings and each of a small charset set, `#body_string`
  returns a `valid_encoding?` `String` tagged with the resolved charset, with `Encoding.default_internal`
  set to something hostile for half the runs.
- **`BODY-32`'s clamp** — over random caps including negative, zero, huge and `MAX_MATERIALIZED_BYTES +
  1`, `#preview(cap:)` either raises `Dexpace::InvalidArgumentError` (negative) or returns at most
  `min(cap, ceiling, available)` bytes.
- **`Dexpace::PercentEncoding.encode_form` versus `.encode_component`** — the two are asserted to differ
  on a space and on `+`, and never to be interchanged, which is `url-and-query-encoding/9ff11c34`'s
  "distinct tests" clause made mechanical.

**Negative tests at every error boundary** (`testing/62f8f4ec`): each raises the expected class, carries
a message naming the offending value, and leaves no partial side effect — a body is still usable after
a rejected construction argument, a wrapper after a rejected cap.

**`FileBody`'s construction validation gets one test per clause** — missing path, a directory, a
character device, a negative offset, an offset past the size, a count past the size — because `BODY-11`
lists them and a single "it validates" test would pass with five of six checks missing.

**Visibility is asserted with `respond_to?`, never `assert_predicate`** — phase 1's finding, which bites
here because `#replayable?`, `#closed?` and `#rewindable?` are all public predicates on objects with
private hooks. (`ResponseLoggingBody#error` is `BODY-26`'s accessor and not a predicate; it is spelled
without the `?` on purpose, because it returns the cached error or `nil` rather than a boolean.)

**One test allocates.** `Body.buffer_bounded` over a body larger than
`MAX_BUFFERED_ERROR_BODY_BYTES` costs one 1 MiB allocation, once per run per matrix row, to assert the
truncation is markerless and that the bytes beyond the cap are **not read** rather than read and
discarded. It is stated so the plan does not quietly drop it.

## Design addendum — what this phase adds to §3.1 and §5.1

Design §3 and §5 are frozen and are not edited here. Two additions, recorded in different places on
purpose, following 3a's own test: a row goes in the Deviation Ledger when the port departs from the
**reference contract**; a documentation erratum goes to `docs/open-items.md` and to the corpus.

| Addendum | What the design says | What phase 3b builds |
|---|---|---|
| **B1 — the decode boundary is two steps, and the second names its target** | §3.1: `Response#body_string` "applies the media type's charset via `String#encode(invalid: :replace, undef: :replace)`" | The rule is implemented exactly as stated — one boundary, the declared charset, UTF-8 as the fallback. The **recipe** is not: applied to BINARY bytes, that call replaces every byte ≥ 0x80, and with no target argument it follows the process-global `Encoding.default_internal`. The port retags first and names both encodings. **No ledger row** — nothing about the port's behaviour departs from `HTTP-42`; only the design's mechanism sentence is wrong. `OI-7`, plus the corpus note against `io-and-byte-streams/fbcb4d19` |
| **B2 — the error-body cap constant moves one layer down** | §5.1: "Core ships one `Dexpace::Recovery.buffer_error_body(response)` holding the one constant" | The constant is `Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES` and the operation reading it is `Dexpace::Body.buffer_bounded(body, cap:)`, both shipped by phase 3b. Phase 4's `Recovery.buffer_error_body(response)` is still the one step and still the one call site, and it reads this constant rather than declaring a second. **No ledger row**: §5.1's guarantee — one constant, one shared bound across every error-body-buffering path — holds exactly, and only the file it lives in changes, because phase 3 ships bodies before phase 4 ships the chain |

## Deviation Ledger

Each row is consolidated into design §10 and audited by `docs/deviations.md`. Numbering continues from
phase 3a, whose last row was P3-13; P3-14 through P3-21 were reserved for 3a's reviewers and went
unused, so this phase starts at P3-14. **P3-22 is the plan's** — the per-variant accessors this list's
constants do not enumerate — and **P3-23 is this document's review's**, added when the review found the
response-body surface below (`OI-10`). A gap in the numbers would be fine; a collision would not, which
is why each row names where it came from.

| # | Deviation | Requirement / document | Why |
|---|---|---|---|
| P3-14 | The public constants and methods design §3 does not name: `Dexpace::Body` with its eight factories, `.buffer_bounded` and `MAX_BUFFERED_ERROR_BODY_BYTES`; `Dexpace::BytesBody`, `BufferBody`, `FileBody`, `StreamBody`, `ChunkedBody`, `FormBody`, `MultipartBody` (and `MultipartBody::Part`), `ResponseBody`, `RequestLoggingBody`, `ResponseLoggingBody`; `Response#close`, `#body_string`, `#body_bytes`; `PercentEncoding.encode_form` and `.encode_form_component`; the RBS interface `Dexpace::_ResponseHandler` | `NFR-4`; `api-design/b0e18938`; phase 2's P2-11 and 3a's P3-8 precedent | Each is locked at the first release tag, so a name arriving by accident is locked by accident. The constants are **flat under `lib/dexpace/http/body/`** per P1-1, and a `Dexpace::Body::` namespace is rejected rather than merely not chosen: its natural member names are `File`, `Buffer` and `Response`, three constants the body code uses constantly, and `OI-3`/P3-7 show that shadowing is silent for `is_a?` and `case/when`. `Dexpace::Body` is a **module**, not an interface and not a base class, because it must carry the default `#replayable?`, `#content_length` and `#each` implementations *and* be the type `sig/` narrows to for `DEF-26`; an RBS interface can do the second but not the first. The form encoder goes beside the RFC 3986 encoder in one file because `url-and-query-encoding/9ff11c34` asks for two distinct functions, not two modules, and adjacency is the strongest guard against interchanging them |
| P3-15 | `sig/` narrows `Request#body` and `Response#body` from `untyped` to `Dexpace::Body?` — the **production contract**, not §10.2's `#each` duck type — and no coercion is added at the builder | `DEF-26`, `HTTP-6`, `HTTP-36`, `HTTP-46`, `NFR-4`; design §10.2 | §10.2's duck type is what a body *yields*; `HTTP-36` says what a request body *is* — a thing with a single write-to-sink operation, a media type, a length and a replayability property — and a Rack array is not one. 3a named its interface `_Chunked` and not `_Body` for exactly this reason. Coercion at the builder is rejected because it would create a second replayability-classification site next to `HTTP-38`'s one. The narrowing is free against `NFR-4` because the lock diffs against the previous release tag and there is none |
| P3-16 | `BODY-9`'s "supports mark/reset" is **seekability, probed at construction with `pos` + `seek(pos)`**, and a replayable stream body rewinds to its **construction position**, not to byte 0 | `BODY-9`, `HTTP-38`; design §3.1 | Ruby has no mark/reset and `respond_to?(:rewind)` answers `true` for a pipe, a socket, a `StringIO` and a `File` alike (verified on 3.2.11, 3.4.10, 4.0.6). A trial `#rewind` discriminates but silently moves a caller's mid-file cursor to 0; `origin = io.pos; io.seek(origin, ::IO::SEEK_SET)` discriminates and is a genuine no-op, raising `Errno::ESPIPE` — a `SystemCallError`, **not** an `IOError` — on a pipe or socket with nothing consumed and the stream still readable. Rewinding to `@origin` rather than 0 is what stops a body over a pre-positioned handle sending bytes the caller never offered. The SHOULD is implemented rather than declared vacuous |
| P3-17 | `BODY-12`'s first clause is **implemented** via `::IO.copy_stream(handle, sink, count, offset)`, and the file body is made recognisable by exposing `#path`, `#offset` and `#count` while deliberately **not** defining `#to_path` | `BODY-12`, `BODY-11`, `BODY-13`; `DEF-3`, `DEF-10` | The segmentation design delegated this clause to 3b. `::IO.copy_stream` is core Ruby, needs no `require`, accepts a duck-typed `#write` destination, honours the `(length, offset)` window, leaves the source handle's own cursor untouched when an offset is given, and returns the byte count — which is `BODY-13`'s short-write detection for free (verified on all three). It is also the call that becomes a real kernel `sendfile`/`copy_file_range` the moment both ends are real `::IO`s, which is what clause 2 is waiting for. `#to_path` is not defined because a `copy_stream(body, sink)` with no length would then copy the **whole file**, silently ignoring the body's window (verified). Clause 2's dispatch stays `DEF-10`'s, phase 8 |
| P3-18 | The two logging wrappers' cap defaults are **deliberately asymmetric**: `RequestLoggingBody` defaults `tap_limit:` to `::Float::INFINITY`, `ResponseLoggingBody` **requires** `preview_bytes:` | `BODY-19`, `BODY-22`, `BODY-34`; `DEF-28`'s precedent, `DEF-34` | `BODY-19` states its own default in its own text ("The unbounded default cap exists for direct wrapper use; the instrumentation layer always supplies a finite cap"), and 3a's `TeeSink` already implements it. `BODY-22` names no default, and an unbounded one would mean `BODY-24`'s over-cap regime never fires and a multi-gigabyte response is fully buffered by the wrapper whose purpose is to bound it. Requiring the keyword ships the narrower signature and lets phase 5 widen it, which cannot break `NFR-4`. A reader who unified the two defaults would break one requirement or the other, which is why the asymmetry is a row rather than a comment |
| P3-19 | `ChunkedBody` is **unconditionally single-use**; there is no `replayable:` keyword on it or on `Body.chunked` | `BODY-1`, `HTTP-38`, `BODY-4` | `BODY-1` permits `#replayable?` to be `true` **only** when writing more than once provably yields byte-for-byte identical output. An `#each`-shaped object may or may not, and a keyword would let a caller *assert* the property — an assertion the retry, redirect and 401 paths then believe (`BODY-4`). A caller with a genuinely repeatable source uses `Body.bytes`, or calls `#to_replayable` and pays one materialisation. Recorded rather than left silent because "add a keyword" is the obvious first request |
| P3-20 | The body layer drives its own exact-length copy through one private routine in `Dexpace::Body`, rather than calling 3a's `TypedWrites#write_all(source)` | `HTTP-39`/`BODY-10`, `BODY-13`, `BODY-25`, `IO-6`, `IO-17` | `#write_all` is a method **on a sink**, so using it would require the transport's `#write`-shaped destination to be wrapped in a `Dexpace::IO::BufferedSink` — and `IO-6` makes that wrapper own and close the socket, which is precisely what a body must never do (`BODY-8`, §10.12), with no borrowing variant available by design (3a's P3-12). One body-layer routine instead, using 3a's `StreamError.short_transfer` and `.zero_read` so `BODY-13`'s "one helper so the message form cannot diverge" holds across both layers. `IO-17`'s zero-read *rule* is therefore implemented in two places; its *message* in one, which is what the requirement actually fixes |
| P3-21 | `Dexpace::Body#each` is **derived from `#write_to`** through a block-shaped sink, defined once in the module; and `FileBody`'s external-iteration residue is documented rather than closed | §10.2, §7.1; `BODY-11`, `BODY-17` | One byte-producing implementation per body means `BODY-17`'s "the exact bytes the wrapped body's single write produces" cannot differ between the `#write_to` path and the `#each` path. §7.1's rule is wider than the corpus states it: verified on all three interpreters that an **ordinary** `#each` method's `ensure` also fails to run when the method is driven through `to_enum(:each)` and abandoned, that `#rewind` does not run it, and that `block_given?` is `true` under that drive so a "require a block" guard is not a defence. Bodies that hold a resource hold it on the object with `#close`; `FileBody`, which `BODY-11` obliges to open a fresh handle per write, cannot, so its YARD states the leak and the corpus note widens `pagination/f57c50f6`. §10.10's precedent: an admitted hole beats a fake proof |
| P3-23 | `Dexpace::Body` declares two members `HTTP-36` does not enumerate — `#source -> Dexpace::IO::BufferedSource`, whose module default **raises `Dexpace::StreamError`**, and `#close`, whose module default is a **no-op** — and the read handle carries one name across all three bodies that can occupy `Response#body`, so `ResponseLoggingBody`'s accessor is `#source` rather than `#read` and `BufferBody` implements both | `HTTP-36`, `HTTP-41`/`BODY-14`, `HTTP-43`, `BODY-15`, `BODY-16`, `BODY-30`/`HTTP-52`; `NFR-4`; P3-14 and P3-22's precedent | `HTTP-36` enumerates what a **request** body is; `HTTP-43`'s "forward to the body", `BODY-16`'s finally-close and `HTTP-42`'s decode are all written against a **response** body's read handle and close, and nothing declared them. Found by review, filed as `OI-10`: `BufferBody` — the body `BODY-30`/`HTTP-52` puts into a response — had neither, so `response.close` and `response.body_string` raised `NoMethodError` on the one object whose canonical text says "decode it, then snapshot it", and no phase-3 test reached it because every `Response` 3b builds carries a bare `ResponseBody`. Three sub-decisions are forced rather than chosen. **The default `#close` is a no-op**, not a raise and not a `respond_to?` guard at the caller: `Request::Builder` coerces nothing, so nothing constrains what sits in `Response#body`, and a guard is the same gap with a quieter failure; a body owning no transport resource has nothing to release, and `BODY-30` positively requires `#body_string`'s `ensure`-close to leave the buffered copy readable. **`BufferBody#source` returns a fresh `#peek` view per call**, because `BODY-30` says "readable independently and **repeatably** (decode it, then snapshot it)" and `BODY-14`'s same-handle rule governs the single-use response body, not a replayable in-memory copy. **`Closeable` wins over the default** wherever a body owns something, because the include order is `Dexpace::Body` then `Dexpace::Closeable` and the later include sits nearer the class. Consequence for the plan: `Body.buffer_bounded` closes the original unguarded, and the `respond_to?(:close)` test disappears with the guard |

## Deferrals Filed by Phase 3b

Filed against `docs/deferred-items.md`; the row names an explicit pick-up condition, per the roadmap's
execution step 7.

| ID | Deferral | Target / condition |
|---|---|---|
| `DEF-34` | The **configuration source** for the body-logging preview size, the body-level-logging **enablement predicate**, and `IO-9`/`BODY-32`'s ceiling as a configurable value rather than a constant. `BODY-34` requires the in-memory capture on both sides to be bounded by **one shared** preview-size configuration and body logging to engage only when body-level logging is enabled; `BODY-19` requires the tap cap to be configurable. Phase 3b ships the parameter shape on both wrappers, one number that can drive both, and the structural half of the enablement clause — nothing in core constructs a logging wrapper, so the wrappers are off the path unless something builds one. What it cannot ship is the thing that decides the value and the thing that decides "enabled" | **Phase 5** (`CFG-1`–`CFG-4`, `OBS-35`), which owns the layered configuration chain and the instrumentation facade. The condition is that chain existing. Adding a default to `ResponseLoggingBody`'s required `preview_bytes:` and reading both caps from configuration are both widenings, so `NFR-4` is not prejudiced by shipping the narrower surface now — `DEF-28`'s precedent, applied verbatim |

### Deferral-register sweep

The roadmap's execution step 1 requires the phase to read the **whole** register and disposition every
row. All thirty-three were read.

**Phase 3b picks up one row, amends a second, and adds a caller to a third.**

- **`DEF-26` — picked up.** Its pick-up condition named phase 3, and 3b is where a body type exists to
  narrow to. `sig/` narrows `Request#body` and `Response#body` to `Dexpace::Body?` (P3-15) and the
  by-value equality test runs against real body types, which is `HTTP-46`'s cross-reference row. Status
  moves to `picked-up (2026-09-08, phase 3b)`.
- **`DEF-3` — amended, and it stays deferred.** Both halves are 3b's IDs, and this is the phase the
  segmentation design's sweep pointed at. `BODY-12`'s **first clause is now implemented** (P3-17), so
  the row's remaining scope is the transport dispatch of clause 2, target **phase 8** alongside
  `DEF-10`. `BODY-36`'s "no named trigger" is replaced by the explicit condition the segmentation
  design named — **core's dependency budget changes**, since Ruby has no stdlib `mmap` and both routes
  to one are barred by `SEAM-1`/`NFR-1`. The sharpenings were stated in the segmentation design and not
  performed on the register; this change performs them, and `DEF-33`'s text already cross-references
  them as though they had been.
- **`DEF-27` — untouched, condition unmet, and 3b is its first caller.** `BODY-28`'s best-effort close
  after a successful full capture is `Dexpace.close_quietly`'s first call site in the SDK. Neither
  disposal route exists yet — phase 4 supplies the suppressed trail, phase 5 the diagnostic — so the
  rescued error is still dropped and the row stands as written, strengthened rather than met.
- **`DEF-28` — untouched, and named as a constraint.** The pivot has no `deadline:` until phase 5, and
  `IO-40` independently forbids the body layer from owning one. `DEF-34` above follows the same
  precedent it set.
- **`DEF-29` — untouched, condition still unmet, row strengthened.** 3b adds `FakeBody` and
  `FakeResponseBody` to `gems/dexpace-core/test/support/`, which is two more doubles that would move
  into `dexpace-conformance` when the first consumer outside `dexpace-core` appears. That consumer is
  phase 8 at the earliest.
- **`DEF-10` — touched only as `BODY-12`'s transport half**, above. `TRANSPORT-28`'s zero-copy dispatch
  is unchanged and post-MVP.
- **`DEF-33` — untouched.** 3a's row; the CI matrix is still CRuby-only and 3b adds no non-CRuby row.
- **`DEF-23` — untouched, and the condition was checked rather than assumed.** 3b's two fakes are a
  handful of scriptable methods with no invariants a type checker would catch, so "a gem's test support
  becomes production-quality code worth checking" is not met. Not marked UNSCHEDULED.
- **`DEF-24`, `DEF-25` — untouched.** Targets phase 4 and phase 8. `DEF-25`'s wire-boundary
  re-validation is a transport obligation and 3b writes no header.
- **`DEF-30`, `DEF-31`, `DEF-32` — untouched.** Targets phase 5, phase 5 and phase 4; no body notifies
  a hook list and nothing here emits a lifecycle event.
- **`DEF-1`, `DEF-2` — untouched.** `SEAM-24`/`SEAM-28` target phase 5; `HTTP-22`/`HTTP-48`–`HTTP-50`
  target phase 6.
- **`DEF-4`–`DEF-9` — untouched.** `PIPE`, `RECOV`, `RETRY`, `REDIR`, `SSE` and `OBS`; other prefixes,
  later phases. `DEF-9`'s "async body-capture skip" is an `OBS` clause over these wrappers and is phase
  5's, not 3b's.
- **`DEF-11`–`DEF-17` — untouched.** Post-v1 gems, out of the MVP by construction.
- **`DEF-18` — untouched.** `ASYNC-3`/`ASYNC-4`/`PIPE-33`; do not re-open.
- **`DEF-19`, `DEF-20` — untouched.** Release-gated; nothing is published.
- **`DEF-21` — already picked up** by phase 2. **`DEF-22` — untouched**, phase 8's conformance
  assertion objects.

### The finding filed against `docs/open-items.md`

**`OI-7` — design §3.1's decode recipe destroys every non-ASCII byte, and its target-less `#encode`
follows a process global.** §3.1 fixes one decode boundary, `Response#body_string`, "which applies the
media type's charset via `String#encode(invalid: :replace, undef: :replace)`". The rule is right and the
mechanism is not. Verified on 3.2.11, 3.4.10 and 4.0.6: applied to the BINARY bytes the I/O layer
delivers, that call replaces every byte ≥ 0x80 — `"café".b.encode(Encoding::UTF_8, invalid: :replace,
undef: :replace)` is `"caf��"` — because from BINARY every high byte is undefined in the
target. The bytes must be **retagged** to the declared charset first. Separately, the sentence's call
takes no target argument, and `#encode(invalid: :replace)` with none converts to
`Encoding.default_internal`, a process-wide setting the host controls: with it set to ISO-8859-1 the same
call returns an ISO-8859-1 string with the accent destroyed, while an explicit-target call is
unaffected. That is the same floor-straddling, passes-where-you-look shape design §3.5 pins
`URI::RFC3986_PARSER` against and `IO-14` avoids `$/` for. What phase 3b does: `#body_string` resolves
the charset from `MediaType#charset` (already `nil` for absent or unknown, so `Encoding.find` cannot
raise), retags through 3a's `#read_string`, then transcodes with **both** encodings named. What would
resolve the item: one sentence in §3.1 the next time §3 is deliberately amended. Filed with the corpus
note against `io-and-byte-streams/fbcb4d19` so the next reader of the corpus does not repeat the recipe.
`OI-1` through `OI-6` remain open and unchanged, and `OI-8` is this document's second filing (3a's
`TeeSink#clear_tap`, above); `OI-4` names this sub-phase's drain as where its bound stops being obvious,
and the plan owns the measurement it asks for. Two further items were opened against this sub-phase
after this document was first written. **`OI-9`**, from the plan, is open: `BufferedSource.wrapping`
delivers one byte per read, which reaches every path here that reads through a wrapped stream, including
R10's tail. **`OI-10`**, from this document's review, is **resolved by this document**: `Response#close`,
`#body_string` and `#body_bytes` were written against a `#source`-plus-`#close` surface that
`Dexpace::Body` did not declare and that two of the three bodies which can occupy `Response#body` did
not implement; both members are now on the module, `ResponseLoggingBody`'s accessor is `#source`, and
`BufferBody` implements both — **P3-23**.

## Open questions for 3b's own plan

Five, each bounded, none re-opening a decision above.

1. **Task order inside the sub-phase.** The segmentation design constrains it and the plan must state
   it: `BODY-1`–`BODY-16`, `BODY-35`, `HTTP-36`–`HTTP-43` and `HTTP-51` land **before**
   `BODY-17`–`BODY-34`, `BODY-37`, `HTTP-44`, `HTTP-45` and `HTTP-52`, because every wrapper wraps a
   body. Within the first group the plan picks the order; the recommendation is `Dexpace::Body` and
   `BytesBody` first, since every later test needs a body it can trust.
2. **`OI-4`'s measurement.** `BODY-23` hands out one `#peek` view per read, and `OI-4` asks for a
   measurement on this drain rather than a redesign. The plan owns a task that measures the retention
   and the `Array#delete` cost under a realistic read count, and records the number in `OI-4`'s
   resolution field. It does **not** own changing 3a's view registry.
3. **Whether `MultipartBody#content_length` runs the framing routine eagerly or memoizes it.** `HTTP-51`
   fixes that the length and the bytes come from one routine; it does not fix when. The recommendation
   is to compute lazily and memoize, because a multipart body over eight file parts should not stat
   eight files to answer a header question that may never be asked — but the plan states the choice and
   tests that the memoized value still equals the bytes written.
4. **Whether `Body.string(text, media_type:)` encodes eagerly.** `HTTP-38` classifies a string body as
   replayable; it says nothing about when the `String` becomes bytes. The recommendation is eagerly, at
   construction, so `#content_length` is exact and a caller's later mutation of the source `String`
   cannot change the body — the same "independent copy" property 3a kept for `.of_bytes`.
5. **The exact chunk size `#write_to` uses when copying from a source.** 3a left the mirror question
   open for `#each`; here the recommendation is to write whatever the source's own read returned rather
   than a fixed size, for `BODY-17`'s byte-exact mirroring, with `FileBody` delegating the question to
   `::IO.copy_stream` entirely. The plan states the choice.
