## 10. Deliberate Deviations from the Reference Contract

Every place where the Ruby-idiomatic answer changes the *mechanism* by which a requirement is satisfied, rather
than merely relocating it. **With two named exceptions — ASYNC-3 and PIPE-33's interrupt clause, both consequences
of the one prohibition in §8.3 — none narrows a MUST-level correctness guarantee. A third, ASYNC-4, holds
vacuously for the same reason and is collected with them in §10.5.** Each entry states the IDs it touches, whether
the specification sanctions it or this port judged it, and where the full argument lives. Nothing new appears here.

1. **The byte-stream provider seam is retired; its behavioural contract is not.** *Touches* **SEAM-3**–**SEAM-10**,
   **IO-30**–**IO-36**, **IO-39**, **XCUT-23** as applied to this seam. *Judged.* Ruby's byte primitives ship with
   the interpreter, so nothing needs keeping out of core and there is nothing to make pluggable (P2).
   **IO-1**–**IO-29** and **IO-37**–**IO-42** are implemented in full; only the pluggability apparatus is removed.
   §3.1.
2. **The canonical body is a duck type, not a nominal interface.** *Touches* **SEAM-3**, **BODY-1**, **BODY-35**.
   *Judged.* `#each` yielding BINARY `String` chunks is Rack's de facto standard, so every existing Ruby streaming
   body inter-operates with no adapter (P14). The inverse adapter `BufferedSource.over` is the single entry point
   the other direction, and takes no ownership. §3.1.
3. **The async pivot is a core-owned future rather than an ecosystem primitive.** *Touches* **SEAM-16**,
   **SEAM-17**, **ASYNC-1**, **ASYNC-2**. **Spec-sanctioned**: **SEAM-17** is a SHOULD that names the pattern, not
   the type, and explicitly wants "one canonical dependency-free future pivot ... ecosystem facades ... separate
   adapters." Adopting any Ruby async gem as the pivot would put a third-party type in core's public surface,
   violating **SEAM-1** and **NFR-11**. §3.3.
4. **Cancellation is cooperative; the orphaned-response close moves to the producer.** *Touches* **SEAM-13**,
   **SEAM-30**, **XCUT-1**–**XCUT-3**, **CFG-17**, **CFG-20**, **CFG-21**, **RETRY-23**, **TRANSPORT-3**,
   **ASYNC-5**. *Judged, with partial sanction* (**XCUT-3** separates the non-pinning mechanism from the normative
   prompt-cancellation requirement). Ruby's only pre-emption primitives land an interrupt on arbitrary bytecode and
   are forbidden (§8.3). **SEAM-30**/**ASYNC-5**'s orphaned-response close is performed by the producer under the
   check-after-resume rule, and **CFG-21**'s discard-path close through the same helper — *how*, not *whether*
   (P6). Cancellation remains prompt at the future, which is what **XCUT-3** makes normative. §3.3, §3.7, §8.3.
5. **Two MUSTs are not satisfied, and a third holds vacuously: ASYNC-3, PIPE-33's interrupt clause, and ASYNC-4.**
   *Touches* **ASYNC-3**, **ASYNC-4**, **PIPE-33**. *Judged, and admitted rather than argued away* (P8). These are
   the only entries in this catalogue that are not mechanism substitutions, and they are not equivalent to one
   another, which is why they are separated here.
   - **ASYNC-4 holds vacuously, and that is a real argument.** It requires an interrupt-ordering handshake so "a
     stale interrupt cannot poison a pooled thread." It is a negative guarantee about a hazard interrupts create;
     a port that never delivers an interrupt cannot produce the hazard, so the guarantee holds — and holds more
     strongly than an implementation of the handshake would provide, since a handshake narrows a window it does not
     close. The conformance item is recorded as vacuous.
   - **ASYNC-3 is not satisfied.** It requires that "when an async operation is backed by a blocking task on a
     worker thread, cancellation MUST distinguish two modes: cancel-with-interrupt interrupts the worker currently
     executing the in-flight task, while cancel-without-interrupt cancels the logical operation without
     interrupting the worker." Its antecedent is satisfied here — `dexpace-async-thread` is precisely a blocking
     task on a worker thread — so the requirement applies and the port meets only one of the two modes. It is not
     vacuous and is not claimed to be.
   - **PIPE-33's interrupt clause is not satisfied**, for the same reason and on the same bridge: "Cancelling the
     returned future with interruption MUST interrupt the worker running the in-flight send." The
     non-interrupting half is met exactly.

   *Why:* §8.3's prohibition on `Timeout.timeout`, `Thread#raise` and `Thread#kill`, which exists because an
   asynchronous interrupt in Ruby can land on any bytecode instruction, including inside an `ensure` releasing a
   pooled connection. *Mitigation:* the check-after-resume rule (§3.3) aborts the worker at its next resume point,
   and `Completer#on_cancel` lets an adapter shorten that by closing the socket under the read; the future itself
   completes as cancelled promptly either way, so no caller waits on work it has abandoned. *Residual gap, stated
   precisely:* **a transport blocked inside an uninterruptible C-extension read cannot be aborted early**, so its
   worker occupies a pool slot until that read returns on its own. The consequence is bounded worker occupancy
   under aggressive cancellation; no response is leaked and no result is delivered to a cancelled caller. §3.3,
   §5.3, §8.3, §12.
6. **Suppressed exceptions are a core-owned trail, not a host facility.** *Touches* **RECOV-12**, **PAGE-13**,
   **PAGE-15**, **SSE-29**, **SSE-30**, **SSE-36**, **RETRY-34**, **XCUT-9**. *Judged.* Ruby has `Exception#cause`
   (single causal parent) and nothing else; `Dexpace::Error#suppressed` supplies the list, `#cause` is never
   overloaded to mean "failed while cleaning up," and every cause walk goes through one `equal?`-tracking
   enumerator so **XCUT-9**'s cycle-safety is a property of the helper rather than of each call site. §5.2.
7. **"Standard library" is narrowed to what is stable across the supported Ruby range.** *Touches* **SEAM-1**,
   **NFR-1**, **AUTH-14**, **OBS-2**. *Judged.* Ruby's stdlib shrinks between releases (`base64` bundled from 3.4,
   `logger` from 4.0, verified), so core may require only non-gemified stdlib and permanently-default gems. The
   visible consequences are Basic auth via `pack("m0")` and a duck-typed logging sink beneath the event facade.
   §2.4, §6.3, §8.1, §9.2.
8. **Discovery's substrate is require-time self-registration, not classpath scanning.** *Touches* **SEAM-5**–
   **SEAM-9**, **XCUT-23**. *Judged.* All five precedence branches are preserved verbatim; only what makes a
   candidate "discoverable" changes. The registry holds factories, the resolved slot holds one instance, and
   **SEAM-6**/**SEAM-8**'s prior-state table compares `equal?` on that instance. Presence-gated auto-activation is
   permitted for instrumentation only, and the asymmetry is argued rather than assumed. §3.6.
9. **SEAM-10's multi-loader de-duplication is vacuous and is replaced by a version-skew guard.** *Touches*
   **SEAM-10**. *Judged.* Ruby has one process-global constant namespace and no classloader; two copies of core
   cannot yield two distinct classes. The real Ruby risk is an adapter built against a different core version, which
   the `~>` constraint plus a registration-time assertion covers, audited by §9's single-instance gate. §2.4, §3.6.
10. **Runtime encapsulation of models is partially unachievable.** *Touches* **HTTP-2**/**SEAM-29**, **HTTP-4**,
    **HTTP-7**, **IO-28**/**BODY-37**. *Judged, and admitted rather than closed* (P8). `private_class_method :new` is
    bypassable by `send` by design, and duck typing admits impersonation. The official path is genuinely closed, the
    gap is documented, and — the part that matters — header validation (**HTTP-17**/**HTTP-18**/**XCUT-18**) is
    re-run at the model-to-wire boundary so a forged model cannot smuggle a request-splitting header. §4.
11. **Read-only collection exposure is computed once, not wrapped per access.** *Touches* **HTTP-5**, **XCUT-15**.
    **Spec-sanctioned**: **HTTP-5** grants the mechanism explicitly ("A port in a language without read-only
    collection views MUST reproduce this guarantee with unmodifiable wrappers or per-call defensive copies").
    Caveats stated: `freeze` is shallow, and `Ractor.make_shareable` deep-freezes *in place*, so it is applied only
    to collections the model already owns. §4.
12. **One stream-ownership rule for bodies, resolving a reference inconsistency.** *Touches* **BODY-8**, **SEAM-3**,
    **SEAM-21**. **Spec-sanctioned**: **BODY-8** requires the port to decide ("A port MUST decide its
    stream-ownership/close rule deliberately rather than assume every single-use body closes its input"). A body
    closes exactly the sources it opened; ownership-on-wrap remains the I/O layer's rule and is deliberately not the
    body layer's, and the serde seam's streaming variants close nothing (**SEAM-20**/**SEAM-21**). §3.1, §3.4, §3.7.
13. **The serde seam ships four encode profiles, two of which are one Ruby type.** *Touches* **SEAM-20**.
    *Judged.* `#dump_string`, `#dump_bytes`, `#dump_to(sink)` and `#dump_into(buffer, offset:)` all ship; a BINARY
    `String` *is* Ruby's byte array, so the fresh-string and fresh-byte-array profiles differ only in the encoding
    tag the result carries. Both are kept because the tag is load-bearing at §3.1's encoding boundary. Argued
    clause-by-clause rather than reduced (P5). §3.4.
14. **The serde witness is a class-object-and-combinator protocol, not a reflective type token.** *Touches*
    **SEAM-22**, **SEAM-23**, **SERDE-5**–**SERDE-8**, **SERDE-16**, **SERDE-17**. *Judged.* Ruby erases nothing
    but reifies no element types, so the requirement is live and its mechanism is unavailable. Argued at least as
    strong on two counts (earlier failure, unreachable unresolved-variable state) and honestly weaker on one (no
    compile-time refusal). **SEAM-23**'s failure hierarchy is unaffected by the substitution and ships as written.
    §3.4, §7.3.
15. **The cross-origin redirect marker lives on the per-hop cursor, not on the request.** *Touches* **REDIR-11**,
    **AUTH-29**, **PIPE-16**. *Judged, and stronger.* Forgery becomes structurally impossible rather than defended
    against, and the porter trap **REDIR-11** itself documents — a pipeline with no auth step forwarding the marker
    to the transport — cannot occur. Rests on §5.1's two cursor-state rules and the stage order
    REDIRECT → RETRY → AUTH. §5.1, §6.2.
16. **The configuration chain keeps four tiers with a substituted third source.** *Touches* **CFG-1**, **CFG-3**,
    **CFG-4**, **CFG-24**, **CFG-26**, **OBS-35**. *Judged.* Ruby has no system properties; the `Dexpace.configure`
    defaults tier is a genuinely distinct in-process source, not a second `ENV` read under another name (P11).
    **CFG-1**'s ordering is preserved even where it inverts common Ruby convention — and is defended on the merits,
    not only on obedience — and the proxy model's resolution is the same deviation applied again, not a new one.
    §8.2.
17. **The interruptible sleep is a cancellable queue wait, not `Kernel#sleep`.** *Touches* **CFG-15**, **CFG-17**,
    **CFG-18**, **RETRY-26**, **XCUT-3**, **XCUT-13**. **Spec-sanctioned** in part: **XCUT-3** states "the normative
    requirement is prompt cancellation, not the specific mechanism." Satisfies **CFG-15**'s blocking-and-interruptible
    clause and **RETRY-26**'s no-pinning clause simultaneously, and is what lets §3.7's graceful close wait without
    parking a cancelled caller. §3.7, §8.3.
18. **Platform-constant substitutions where Ruby has no constant.** *Touches* **IO-9**, **BODY-32**, **SSE-11**,
    **RECOV-34**. **Partly spec-sanctioned**: **SSE-11** requires the port to pick a documented cap. Ruby has no
    maximum single allocation and no integer overflow, so the port names explicit constants (64 MiB
    materialisation ceiling, 2^31−1 ms retry hint, an explicit ~292-year duration bound in retry config) and fails
    or ignores loudly above them, preserving the observable behaviour on a host where the stated failure mode is
    unreachable. §3.1, §6.1, §7.2.
19. **The dead-code-survival gate is retargeted, not deleted.** *Touches* **NFR-8**, **NFR-9**. **Spec-sanctioned**:
    **NFR-8** says "In ecosystems without such a build step this requirement does not apply." Retargeted at the
    require-allowlist audit and clean-bundle isolation run, which guard the Ruby-specific way a zero-dependency
    claim silently stops being true. §9.2.

Two things that are deliberately **not** deviations, recorded because a reader may expect them: the two retry
stacks are **not** unified, so neither **RETRY-28**'s nor `08-execution-pipelines.md`'s unification sanction is
invoked (§6.1); and both transport seams and both pipeline bridges survive, so no analogue of a single-execution-model
collapse appears above (§1, §3.3, §5.3).

---

