## 11. Appendix: Reference-Spec Ambiguities and How This Port Resolves Them

Tensions, gaps and internal inconsistencies in `product-spec.md` surfaced by this exercise, each resolved rather
than worked around silently, so a future reader can tell a deliberate reading from an oversight.

1. **CFG-15's blocking sleep versus RETRY-26's no-carrier-pinning.** One mandates a blocking interruptible sleep,
   the other forbids pinning a carrier. *Resolved* in §8.3: a cancellable queue wait blocks the caller while
   unmounting the fiber under a scheduler and never occupying a shared pool thread. **XCUT-3**'s own
   mechanism-versus-intent sentence is the authority.
2. **NFR-11's "plain blocking operations" versus SEAM-17's pivot in core's public surface.** *Resolved:*
   **NFR-11**'s target is *third-party framework* types; a core-owned dependency-free pivot is what **SEAM-17**
   mandates and is not one. The sync seam remains a plain blocking operation correct on any scheduler.
3. **SEAM-2 enumerates exactly five seams; is retiring one a violation?** Never settled by the text. *Resolved* by
   reading **SEAM-2** as constraining how a *retained* concern is exposed, not as requiring a concern the runtime
   standardises to stay pluggable — the rationale of **SEAM-3**–**SEAM-10** is dependency avoidance, absent here.
   Stated as an assumption because no clause grants it.
4. **CFG-1's system-property tier has no porting guidance, unlike RETRY-28** — the specification is inconsistent
   about when it anticipates ports. *Resolved* in §8.2 by substituting a distinct source and preserving the
   ordering; recorded as judged, not sanctioned (§10.16).
5. **SEAM-30's conformance step presumes externally pre-emptible futures.** *Resolved:* the invariant (an orphaned
   response closed exactly once, never surfaced) is preserved and tested by having the fake transport observe the
   token at its check-after-resume point; the step is restated in `dexpace-conformance` rather than dropped.
6. **HTTP-2/SEAM-29 presume enforceable constructor privacy**; conformance is undefined where encapsulation is
   conventional. *Resolved* in §4 and §10.10 — the official path is closed, the gap named, and the
   security-relevant invariant re-checked at the wire boundary.
7. **BODY-3's atomic compare-and-set is a property of the reference implementation, not of the requirement**, whose
   text says only "fail loudly on a second write" and "race-safe". *Resolved* with a `Thread::Mutex` held only
   across the flag flip and never across the drain — which matters because Ruby's `Mutex` is per-fiber-owned and
   non-reentrant (both verified), so holding it across a suspension point would deadlock two fibers of one thread.
   The general lesson applied reflexively: port the requirement, not the reference's mechanism.
8. **XCUT-23's resolution rule needs at least one instance after a seam retires.** *Resolved:* it has three here
   (transport, serde, executor), satisfied by §3.6, so the conformance item is accounted for.
9. **Appendix B covers only nine of nineteen prefixes.** *Resolved:* §9.3 states that Appendix B conformance is a
   strictly weaker claim than full conformance, and `dexpace-conformance` adds suites for the other ten.
10. **RETRY-38's modal tag contradicts its prose** (tagged SHOULD, body says "MAY stamp"): treated as SHOULD per
    the tag, feature deferred, discrepancy flagged. **RETRY-45 is the only requirement tagged MUST NOT**: indexed
    as a MUST, since RFC 2119 MUST and MUST NOT are the same strength.
11. **Embedded MUSTs inside SHOULD-tagged requirements** (**CTX-16**, **CTX-20**, ~20 others). *Resolved:* read as
    "the feature is optional, its behaviour is not" — where the port ships the feature it implements every embedded
    MUST; where it defers the feature (§12) they defer with it. A parent-SHOULD/child-MUST split is recommended to
    the specification author.
12. **Four reference sync/async drifts the specification pushes onto the porter** (**BODY-8**, **RECOV-14**,
    **RETRY-34**, **AUTH-31**). *Resolved* toward the stricter, uniform behaviour, each through a single shared
    implementation so the paths cannot drift again (§5.2).
13. **Citation hygiene:** "HTTP-16-body" reuses a numeral with an ad hoc suffix (cited as **BODY-16** throughout
    this document; a distinct numeral is recommended); **SEAM-29** is defined three times; and **RETRY-1**/
    **RETRY-6** are summarised in the specification's §2 before their canonical text in its §9.1 and §4.2,
    which §6.1 of this document treats as canonical.
14. **SEAM-6 and SEAM-8 describe overlapping scenarios** and are easy to conflate. *Resolved* with the explicit
    prior-state table in §3.6 rather than prose.
15. **Clauses with no Ruby manifestation:** **CFG-34**'s boxed-versus-primitive array inequality is recorded as
    inapplicable rather than emulated (the rest of **CFG-33**/**CFG-34** is implemented); **SERDE-11**'s unchecked
    exceptions and **SERDE-14**'s covariance are satisfied by the language and need no code.
16. **PIPE-32's sync/async redirect asymmetry** is preserved because it is normative, but made visible at the call
    site rather than silent (§5.3), and flagged as a candidate for closure once an async redirect story exists.
17. **The SSE preamble offers a strict-WHATWG mode as an alternative to replicating the deviations.** *Resolved:*
    the deviations are replicated — they are the specified behaviour, and interoperability with the reference
    matters more than WHATWG parity — and no strict mode ships in the MVP.
18. **SERDE-26 presumes a mutable codec engine; TRANSPORT-18 presumes a re-subscribable body producer.** Both are
    near-vacuous for the MVP adapters (`JSON` is stateless, `Net::HTTP` has no resend hook) and both are stated as
    conditional obligations on any future adapter whose library has them, per the specification's own
    per-transport scoping.
19. **The retry-unification sanction is stated twice with different scopes.** `09-retry-and-resilience.md` binds "a
    port that unifies **the stacks**"; `08-execution-pipelines.md` binds "a port unifying **retry entry points**."
    A port that unified only the entry points would escape the first and be caught by the second, which is
    presumably the intent but is nowhere said. *Resolved* in §6.1 by quoting and citing both separately and
    invoking neither, since this port unifies nothing (§10, closing note). A single normative sentence with the
    broader scope is recommended to the specification author.
20. **RECOV-31 and RETRY-38 are the same feature under two IDs at two modal levels** — a per-attempt request header
    carrying the 1-based attempt ordinal, tagged MAY in one subsystem and SHOULD in the other (and see §11.10 on
    RETRY-38's own tag/prose conflict). *Resolved:* treated as one deferred feature, listed under both IDs in §12
    so neither is silently dropped, and recommended for consolidation to the specification author.
21. **ASYNC-21 is tagged MUST but its antecedent is an optional adapter** ("An adapter exposing a streaming source
    (SSE) as a reactive stream MUST honor downstream backpressure ..."). A port shipping no reactive adapter
    satisfies it vacuously, which makes a MUST-tagged requirement invisible in a MUST-coverage count. *Resolved:*
    §12 lists it as adapter-scoped-and-vacuous rather than as either satisfied or deferred, and the backpressure
    property it protects is implemented anyway on the pull-based path (**SSE-39**, §7.2), so an adapter built later
    inherits it. Several **TRANSPORT-** requirements share this shape and are treated the same way.

