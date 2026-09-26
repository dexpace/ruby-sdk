## 12. Appendix: Requirement Coverage Index

All 19 prefixes and 645 requirements, with the sections addressing each family and, by ID, everything the port
does not implement as written. Three kinds of entry appear, and they are not interchangeable:

- **Not satisfied** — a MUST whose antecedent this port meets and whose obligation it does not. There are **two**
  in full: **ASYNC-3** and **PIPE-33**'s interrupt clause, both consequences of §8.3's prohibition, both argued in
  §10.5. **Three more MUST clauses are not met on a stated domain**: **SERDE-27**'s no-materialisation clause in the
  shipped JSON codec (§10.20), **TRANSPORT-14**'s header-name clause on the asynchronous transport (§10.21), and
  **HTTP-45**'s no-pinning clause for a second fiber of one thread with no fiber scheduler (§10.22). Four §10
  entries narrow a MUST clause on an edge they state and argue — a frozen primary (§10.6), a borrowed `Net::HTTP`
  (§10.26), an explicit scheme-default port (§10.33) and a bearer provider without `#fetch_async` (§10.34). Nothing
  else in this document should be read as claiming less than full MUST-level conformance. [Corrected 2026-09-25: this entry
  counted two and said nothing else fell short; the three stated-domain clauses were recorded in phase ledgers
  (7a's `P7-1`, 8c's `P8-38`, 3b's `P3-27`) and in `docs/first-release.md` for the first, and reached this index
  only when §10 was reconciled against the as-built tree.]
- **Vacuous** — a requirement whose antecedent this port never reaches, so the guarantee holds without an
  implementation. **ASYNC-4** (no interrupts are ever delivered, §10.5); **ASYNC-21**, **TRANSPORT-1** and
  **TRANSPORT-18** (adapter-scoped, and no MVP adapter has the path — §3.2, §11.18, §11.21); **NFR-8** by its own
  text; **CFG-34**'s boxed-versus-primitive clause (§11.15); **PAGE-15**'s wrapping clause (§10.29); and, at SHOULD
  level, **SEAM-10** (§10.9) and **CFG-19**'s unwrap (§10.29). A vacuous item is recorded as vacuous in
  `dexpace-conformance`, never as passing. [Amended 2026-09-25, `C6`, `C7` and `C13` of `docs/deviations.md`:
  **TRANSPORT-2** left this list — `Net::HTTP#max_retries` defaults to 1 and `Async::HTTP::Client`'s `retries:` to
  3, and both adapters set 0, so it is satisfied by construction; **TRANSPORT-8** left it — `dexpace-transport-net_http`
  has no internal cancellation, but `async-http` delivers `Async::Cancel` into an in-flight exchange and
  `dexpace-transport-async_http` completes the future with a terminal cancellation, asserted in its own suite; and
  **PAGE-15**'s wrapping clause joined it (phase 7c's `P7-1`), with **CFG-19** (phase 5a's `P5-11`).]
- **Deferred** — a **SHOULD** or **MAY** the port declines for the first release, listed by ID. Deferred means not
  implemented, never reinterpreted.

What this index does **not** claim: that every one of the 99 SHOULD- and 14 MAY-level requirements is individually
argued above. Those the port declines are named here; the remainder are implemented as written, and it is
`dexpace-conformance` per item — not this table — that establishes it. §9.3's warning applies with equal force in
the other direction: Appendix B covers nine of nineteen prefixes, so neither Appendix B nor this index is by itself
a conformance claim.

| Prefix | Count | Addressed in | Deferred / notes |
|---|---|---|---|
| SEAM | 30 | §2.4, §3.1–§3.7, §5.3 | *Deferred:* SEAM-24 (SHOULD, cross-thread diagnostic-context propagation) beyond fiber storage, ships with `dexpace-async-async`; SEAM-28 (MAY, stable operation identifier on the projection). *Notes:* SEAM-3 and SEAM-4's byte-stream factory retired with the seam (§10.1) while SEAM-5–SEAM-9 are kept intact for the three surviving seams (§3.6); SEAM-10 vacuous (§10.9); SEAM-14/SEAM-25's close contract in §3.7; SEAM-15 (MAY) taken explicitly — a post-close send raises; SEAM-20/SEAM-21's four profiles and never-close rule in §3.4; SEAM-22's generic-type capture replaced by the witness protocol (§10.14, §7.3) and SEAM-23's SDK-owned serde failure hierarchy in §3.4 |
| HTTP | 53 | §3.1, §3.5, §3.7, §4, §6.2 | **Not satisfied on a stated domain:** HTTP-45's no-pinning clause for a second fiber of one thread with no fiber scheduler (§10.22). *Deferred:* HTTP-22 (MAY, name interning); HTTP-48, HTTP-49, HTTP-50 (SHOULD; ETag, Range and conditional-request helpers). *Notes:* HTTP-2/SEAM-29's constructor privacy partially unachievable and re-checked at the wire boundary (§10.10); HTTP-9's idempotent set public and HTTP-34's tag values `String` (§10.37); HTTP-37/HTTP-38/HTTP-39 in §3.1; HTTP-41/HTTP-43 in §3.7; HTTP-44/HTTP-45's memoizing wrapper in §7.3 |
| IO | 42 | §3.1, §3.7 | *Deferred:* none. *Notes:* IO-30–IO-36 and IO-39 retired with the provider seam and its registry (§10.1) — IO-39 is entirely about the registry's lock-free reads and has no subject once the registry is gone; IO-1–IO-29 and IO-37–IO-42 implemented in full, with IO-41's idempotent close under §3.7's latch |
| BODY | 37 | §3.1, §4, §5.1, §6.1, §7.1 | *Deferred:* BODY-36 (MAY, memory-mapped view) — no stdlib mmap; BODY-12 (SHOULD, platform zero-copy file transfer) lands with an `IO.copy_stream` path post-MVP. *Notes:* the five variants and both logging wrappers (BODY-2–BODY-7, BODY-10–BODY-29, BODY-31, BODY-34) in §3.1; BODY-8's ownership rule in §10.12; BODY-30's bounded error copy in §5.1, from which BODY-33's non-consuming preview falls out |
| CTX | 20 | §5.4, §8.1 | *Deferred:* none. *Notes:* CTX-13's arbitrary-victim latitude (MAY) taken as-is; CTX-14's correlation bundle ships in core with OBS-25/OBS-26's sentinels and CTX-20's no-op tracer factory (§8.1), populated rather than replaced when the OTel adapter lands |
| PIPE | 40 | §5.1–§5.3 | **Not satisfied:** PIPE-33's interrupt clause (§10.5). *Deferred:* PIPE-36 (SHOULD, pillar-step stage locking) post-MVP. *Notes:* PIPE-15's reuse defect detected sequentially and PIPE-5's distinct error a distinct message (§10.38); PIPE-30's fatal family read as everything outside `StandardError` (§10.23); PIPE-39's convenience constructors are §5.1's preset and §5.3's two named seeding constructors; PIPE-32's asymmetry preserved and made visible (§11.16) |
| RECOV | 34 | §5.1, §5.2 | *Deferred:* RECOV-31 (MAY, per-attempt ordinal header — the same feature as RETRY-38, §11.20). *Notes:* RECOV-15's status mapping, RECOV-16's bounded replayable error copy, RECOV-32's idempotency-key step and RECOV-33's client-identity step are named steps in §5.1; RECOV-34's construction-time validation and defensive copies in §6.1 |
| RETRY | 45 | §6.1, §8.3 | *Deferred:* RETRY-29 (MAY, server-driven retry override); RETRY-38 (attempt-ordinal header; tag/prose conflict recorded at §11.10); RETRY-43 (MAY, fixed-delay mode). *Notes:* both stacks ship and neither unification sanction is invoked (§6.1, §10 closing note); RETRY-36's re-mapped re-sent error body shares §5.1's bounded copy |
| REDIR | 28 | §6.2 | *Deferred:* REDIR-27 (MAY, configurable target header). *Notes:* REDIR-11's marker moved to the per-hop cursor (§10.15) |
| AUTH | 38 | §6.3 | *Deferred:* none. *Notes:* AUTH-9's non-blank validation, AUTH-23's ordered composition with a defensive copy, AUTH-25's proxy-flag header selection and AUTH-35's provider-result rejection are all in §6.3; AUTH-38's async delivery is §3.3's failure channel |
| PAGE | 36 | §7.1 | *Deferred:* none. *Notes:* PAGE-35 (SHOULD) is conditional on offering a mutable paging-options object; the port offers an immutable value instead, so the clause is vacuous rather than declined; PAGE-15's wrapping clause is vacuous by a false antecedent (`7c P7-1`, §10.29) [amended 2026-09-25, `C13` of `docs/deviations.md`: the row recorded one vacuity fewer than `dexpace-conformance` does]; PAGE-19's same-document targets and PAGE-16's extractor obligation (§10.35) |
| SSE | 41 | §7.2 | *Deferred:* SSE-41 (MAY, reactive-adapter error and lifecycle latitude) — scoped to a reactive adapter and none ships; no strict-WHATWG mode (§11.17). *Notes:* SSE-40's lazy single-pass view ships (§7.2), as do SSE-20's defensive copy, SSE-21/SSE-22's value semantics and SSE-39's pull-based delivery |
| SERDE | 30 | §3.4, §7.3 | **Not satisfied:** SERDE-27's no-materialisation clause in the shipped JSON codec, adapter-local (§10.20). *Deferred:* none. *Notes:* SERDE-24 (ISO-8601 date form, round-trip on the microsecond domain, §10.36) and SERDE-25 (fresh-config factory) implemented in §3.4, SERDE-23's tolerant decode and SERDE-30's sentinel string forms likewise; SERDE-26 satisfied by a private `::JSON::Coder` per codec instance [amended 2026-09-25, `C23` of `docs/deviations.md`: this read "near-vacuous for a stateless `JSON` (§11.18)", written against json 2.9.1] |
| OBS | 40 | §8.1 | *Deferred:* OBS-32 (SHOULD, OpenTelemetry metric conventions) and OBS-37 (SHOULD, async body-capture skip) land with the OTel and async adapters. *Notes:* OBS-1's shared inert event, OBS-3–OBS-9, OBS-39 and OBS-40's throttled diagnostic are the event object of §8.1; OBS-19 (SHOULD) is vacuous for `Net::HTTP`, which raises on an unencodable header rather than dropping it, and binds any adapter that drops |
| CFG | 38 | §8.2, §8.3 | *Deferred:* none. *Notes:* CFG-20 (SHOULD, interruptible-task future) reshaped as the pivot (§3.3) with CFG-21's discard-path close honoured (§3.3, §3.7); CFG-34's boxed-versus-primitive array clause inapplicable (§11.15); CFG-18's delay settles with `true` and refuses without a scheduler (§10.28); CFG-19 vacuous (§10.29) |
| TRANSPORT | 30 | §3.2, §3.7, §6.2, §9.3 | **Not satisfied on a stated domain:** TRANSPORT-14's header-name clause on `dexpace-transport-async_http`, with TRANSPORT-27's (SHOULD) `Content-Length` half, both waived by ID in that gem's conformance run (§10.21). *Deferred:* TRANSPORT-28 (SHOULD, zero-copy file body) is per-adapter and post-MVP. *Notes:* TRANSPORT-1 and TRANSPORT-18 are adapter-scoped and vacuous for both MVP adapters, binding on any adapter whose client has those paths (§11.18, §11.21); TRANSPORT-2 is satisfied by construction — both adapters set their client's native retry count to 0; TRANSPORT-8 is vacuous for `Net::HTTP` and satisfied on `dexpace-transport-async_http`; TRANSPORT-30 ships on `dexpace-transport-net_http` (its proxy-limitation event); TRANSPORT-5's per-call override is refused on a borrowed `Net::HTTP` (§10.26); TRANSPORT-22's adaptation-failure close is one of §3.7's `close_quietly` paths. [Amended 2026-09-25, `C6` and `C7` of `docs/deviations.md`: the row listed TRANSPORT-2 and TRANSPORT-8 as vacuous and TRANSPORT-14 as satisfied without qualification; corrected the same day: it listed TRANSPORT-30 as deferred, which phase 8a built] |
| ASYNC | 22 | §3.3, §3.7, §5.3, §8.1 | **Not satisfied:** ASYNC-3 (§10.5). *Vacuous:* ASYNC-4 (§10.5); ASYNC-21, adapter-scoped with no reactive adapter shipping, though its backpressure property is implemented on the pull-based path anyway (SSE-39, §7.2). *Deferred:* none. *Notes:* ASYNC-15–ASYNC-17's lifecycle in §3.7, the close bounded rather than cancellable (§10.17); ASYNC-18's delay holds one timer thread per pool (§10.27) |
| XCUT | 24 | §3.3, §3.7, §4, §5.2, §6, §8.1, §8.3 | *Deferred:* none. *Notes:* XCUT-6's open retryability capability and XCUT-8's non-error refusal in §6.1 and §5.1; XCUT-9's cycle-safe cause walk in §5.2; XCUT-13 and XCUT-22 in §3.7 |
| NFR | 17 | §2, §9 | *Deferred:* none. *Notes:* NFR-8 vacuous by its own text and NFR-9 with it, both retargeted (§10.19); NFR-11 mechanised as §9's RBS surface scan; NFR-16 (SHOULD, signing) enforced on the release path only |

**Total: 645.** SEAM 30, HTTP 53, IO 42, BODY 37, CTX 20, PIPE 40, RECOV 34, RETRY 45, REDIR 28, AUTH 38 (367);
PAGE 36, SSE 41, SERDE 30, OBS 40, CFG 38, TRANSPORT 30, ASYNC 22, XCUT 24, NFR 17 (278).

**MUST-level summary.** Of the 531 MUST and 1 MUST NOT requirements, **two are not satisfied** — ASYNC-3 and
PIPE-33's interrupt clause — **three more are not met on a stated domain** — SERDE-27's no-materialisation clause,
TRANSPORT-14 on the asynchronous transport and HTTP-45's no-pinning clause for a same-thread fiber without a
scheduler — and **seven hold vacuously** for the reasons stated above: ASYNC-4, ASYNC-21, TRANSPORT-1,
TRANSPORT-18, NFR-8, CFG-34's boxed-array clause and PAGE-15's wrapping clause. [Corrected 2026-09-25: the summary
read "eight hold vacuously … TRANSPORT-2, TRANSPORT-8" and counted no stated-domain gap; see the two list entries
at the head of this appendix.] Six more —
SEAM-3, SEAM-4 and IO-30–IO-33 — are the pluggability apparatus of the one seam this port retires, argued
clause-by-clause in §10.1 rather than implemented; SEAM-5–SEAM-9 survive intact because three other seams still
need them (§3.6). Every remaining MUST is implemented as written or covered by a deviation catalogued in §10, and
no deviation there narrows a MUST-level correctness guarantee except the five named at the head of this appendix
and the four stated edges named beside them.
