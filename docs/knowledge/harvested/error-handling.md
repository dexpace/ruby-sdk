# error-handling

## Rules
- Every failure in application code must be a typed `StandardError` subclass raised with a class and a message.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:3` · high · sha:ca24f5238acf</sub>
- Errors must be chained through `cause` on rethrow and rescued precisely by callers.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:3` · high · sha:ca24f5238acf</sub>
- Programmer errors — broken invariants, unreachable states, bugs — must raise `Assert::InvariantViolation` and crash fast rather than being handled.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:3` · high · sha:ca24f5238acf</sub>
- Operational errors must be caught by callers who can recover, distinguishing them from programmer errors.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:3` · high · sha:ca24f5238acf</sub>
- Define one project-level base exception class (e.g. `Commerce::Error < StandardError`) with domain-specific error trees hanging off it, so callers can rescue the root broadly or a leaf precisely.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:80-84` · high · sha:ca24f5238acf</sub>
- Carry identifying inputs on custom error classes as Sorbet-typed `attr_reader` fields (ids, offending values, correlation ids) so they survive serialization and appear in structured logs.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:85` · high · sha:ca24f5238acf</sub>
- Keep a custom exception hierarchy to two levels deep, since a five-level hierarchy navigates no better than a two-level one.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:86` · high · sha:ca24f5238acf</sub>
- Introduce a new exception subclass only when callers must distinguish it for different handling; otherwise reuse an existing class with a richer message.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:87` · high · sha:ca24f5238acf</sub>
- Never write `raise StandardError` or `raise RuntimeError` bare in application code; all domain failures must extend the project's error base class.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:126` · high · sha:ca24f5238acf</sub>
- Never rescue `Exception` in application code; rescue `StandardError` or a named subclass instead.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:128-133` · high · sha:ca24f5238acf</sub>
- A bare `rescue` without a named class is equivalent to `rescue StandardError` and is acceptable only in a narrow `rescue => error` that immediately re-raises.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:132` · high · sha:ca24f5238acf</sub>
- `rescue Exception => error` belongs only in a top-level crash reporter that re-raises after logging, and that reporter must live in a framework or process supervisor, not in business-logic methods.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:133` · high · sha:ca24f5238acf</sub>
- `Lint/RescueException` is the RuboCop cop that enforces the prohibition on rescuing `Exception` outside the designated crash-reporter module.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:155` · high · sha:ca24f5238acf</sub>
- Do not use exceptions for flow control; check the condition before operating instead of raising and rescuing to handle an ordinary case.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:157-161` · high · sha:ca24f5238acf</sub>
- A lookup that may miss must return `T.nilable(Order)` (or similar), with the caller using `&.` or an explicit nil check, rather than raising and rescuing to represent absence.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:162` · high · sha:ca24f5238acf</sub>
- A yes/no question must return a boolean rather than raising an exception that the caller catches to read the answer.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:163` · high · sha:ca24f5238acf</sub>
- Callers that rescue an exception class merely to read a "not found" branch are rejected at review; the canonical pattern is `T.nilable` return plus a nil check.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:188` · high · sha:ca24f5238acf</sub>
- Use implicit `begin` — method-level `rescue`/`ensure` without an explicit `begin` block — since `def`/`end` is already an implicit `begin`/`end`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:190-194` · high · sha:ca24f5238acf</sub>
- An explicit `begin`/`end` inside a method body is legitimate only when the rescue scope is smaller than the whole method; otherwise extract a private method and rescue at that method's level.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:195` · high · sha:ca24f5238acf</sub>
- `Style/RedundantBegin` is the RuboCop cop enforcing implicit `begin`, and reviewers reject an explicit `begin` at the outermost scope of a method body.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:219` · high · sha:ca24f5238acf</sub>
- Never use an empty `rescue` block, since it discards the exception and ships whatever corrupt state follows.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:221-224` · high · sha:ca24f5238acf</sub>
- Never use `rescue nil` (e.g. `result = do_thing rescue nil`), because it rescues every `StandardError` including bugs, swallows the exception silently, and returns `nil` so callers assume success.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:225` · high · sha:ca24f5238acf</sub>
- Never use a modifier rescue (`expr rescue fallback`); use a full `rescue` clause with a named class instead, since the modifier form cannot log, cannot chain cause, and cannot distinguish an expected failure from a programmer mistake.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:226` · high · sha:ca24f5238acf</sub>
- A deliberate exception swallow is acceptable only if it catches the single expected error class, immediately re-raises anything else, and is accompanied by a comment documenting why the failure is tolerable.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:227` · high · sha:ca24f5238acf</sub>
- `Lint/SuppressedException` and `Style/RescueModifier` are the RuboCop cops enforcing prohibitions on empty rescue and modifier rescue respectively, and `rescue nil` requires a named class plus a why-comment at review.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:251` · high · sha:ca24f5238acf</sub>
- Prefer `raise SomeError, "message"` over `raise SomeError.new("message")`, because the two-argument form delegates instantiation to `raise`, which sets the backtrace at the correct call depth.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:253-256` · high · sha:ca24f5238acf</sub>
- Never use a bare `raise "message"` in application code, since it raises `RuntimeError`, which no caller can rescue precisely because messages are not a stable API.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:257` · high · sha:ca24f5238acf</sub>
- Omit the explicit `RuntimeError` class name when raising `RuntimeError` (write `raise "message"`), but never use that bare form for anything other than `RuntimeError` in application code.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:258` · high · sha:ca24f5238acf</sub>
- When re-raising the current exception inside a rescue block, use a bare `raise` with no arguments so it re-raises `$!` with the original backtrace intact.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:259` · high · sha:ca24f5238acf</sub>
- `Style/RaiseArgs` is the RuboCop cop enforcing the two-argument raise form, and review rejects bare string raises in application code.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:280` · high · sha:ca24f5238acf</sub>
- Never `return` from an `ensure` block, because `ensure` runs regardless of an in-flight exception and a `return` inside it silently discards that exception.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:282-287` · high · sha:ca24f5238acf</sub>
- `ensure` blocks must contain only unconditional cleanup (closing resources, releasing locks, decrementing counters) and must not compute a return value.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:287` · high · sha:ca24f5238acf</sub>
- `Lint/EnsureReturn` is the RuboCop cop rejecting any `return` expression inside an `ensure` block.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:313` · high · sha:ca24f5238acf</sub>
- Never `return` from inside a `rescue` clause nested within a `begin`/`end` used on the right-hand side of an assignment (e.g. memoization), because it skips the assignment entirely and exits the method instead.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:315-320` · high · sha:ca24f5238acf</sub>
- Inside a rescue clause nested in an assignment `begin`/`end`, assign the fallback value as the clause's last expression instead of returning it.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:320` · high · sha:ca24f5238acf</sub>
- Name rescue-bound exception variables `error`, not `e`, so the binding is self-describing and signals the exception will be used rather than discarded.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:348-353` · high · sha:ca24f5238acf</sub>
- In a method that rescues multiple exception classes, name each rescue variable meaningfully (e.g. `declined_error`) so each clause reads correctly in isolation.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:352` · high · sha:ca24f5238acf</sub>
- `e` as a rescue variable name is rejected at code review.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:367` · high · sha:ca24f5238acf</sub>
- When catching one error and raising another, pass the original exception explicitly as the `cause:` keyword argument rather than relying on Ruby's implicit cause assignment.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:369-373` · high · sha:ca24f5238acf</sub>
- The `cause:` passed on rethrow must be the original exception object, not a string, and raw third-party exceptions must be wrapped in a typed domain class before propagating.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:374` · high · sha:ca24f5238acf</sub>
- Attach context fields — the inputs that triggered the failure and a correlation id tying the chain to the request — on the new error class when chaining causes.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:375` · high · sha:ca24f5238acf</sub>
- Every wrap-and-rethrow must pass `cause:`; a rethrow without `cause:` is a review rejection.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:401` · high · sha:ca24f5238acf</sub>
- Prefer a standard-library exception (`ArgumentError`, `KeyError`, `TypeError`, `RangeError`, `StopIteration`, etc.) where one exactly fits the failure, and introduce a new class only when callers must distinguish it for different handling.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:403-407` · high · sha:ca24f5238acf</sub>
- Wrap standard-library exceptions at layer boundaries so, e.g., a `KeyError` raised inside a repository surfaces as a typed domain error to the layer above rather than escaping the repository.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:408` · high · sha:ca24f5238acf</sub>
- `ArgumentError` and `TypeError` signal caller mistakes and are programmer errors; raise them from validation helpers but do not rescue them in business logic.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:409` · high · sha:ca24f5238acf</sub>
- A new exception class requires a stated reason at review why existing classes cannot be rescued precisely enough.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:427` · high · sha:ca24f5238acf</sub>
- Use `Assert.that` and `Assert.fail` for programmer errors — violated preconditions, unreachable branches, impossible computed results — which must crash loudly and close to the fault.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:429-432` · high · sha:ca24f5238acf</sub>
- An operational error — an expected failure of a correct program such as a card decline, gateway timeout, or out-of-stock item — must be raised as a typed domain error or returned as a nilable value, then handled by callers.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:433` · high · sha:ca24f5238acf</sub>
- Never demote a programmer error to a handled operational error, and never promote an operational error to a crash.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:434` · high · sha:ca24f5238acf</sub>
- `Assert::InvariantViolation` must never be caught in business logic; catching it belongs only in a top-level crash reporter. evidence: /home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:434, 465 confidence: high - type: reference topic: error-handling statement: `Assert::InvariantViolation` is not a subclass of `Commerce::Error`, so a caller rescuing `Commerce::Error` cannot accidentally catch a programming bug.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:436` · high · sha:ca24f5238acf</sub>
- A caller rescuing `StandardError` at a boundary should re-raise `Assert::InvariantViolation` explicitly rather than letting it be silently absorbed.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:436` · high · sha:ca24f5238acf</sub>
- An `ensure` block that can itself raise must rescue narrowly inside the `ensure` body, since an exception escaping an `ensure` replaces the in-flight exception, silently discarding it.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:435` · high · sha:ca24f5238acf</sub>
- The buffered copy of an error body MUST be readable independently and repeatably after the transport connection is released, and buffering MUST occur inside the original body's close-guaranteeing scope so a provider/buffer-allocation failure still releases the connection; a response with no body MUST be returned unchanged (HTTP-52/BODY-30).
  <sub>spec · `docs/product-spec/06-request-and-response-body-lifecycle.md:46-46` · high · sha:c2bf15dc8a06</sub>
- Error-to-exception mapping MUST apply only to 4xx/5xx responses; a non-error non-success response (e.g. 304, an unfollowed 3xx) MUST be returned with its body intact (BODY-31).
  <sub>spec · `docs/product-spec/06-request-and-response-body-lifecycle.md:46-46` · high · sha:c2bf15dc8a06</sub>
- Byte-capped snapshot/preview operations MUST reject a negative cap, silently clamp the cap to the platform's maximum single-array size, and return whatever bytes are available up to the clamped cap; a capless snapshot MUST fail loudly when the captured size exceeds the platform maximum rather than attempt an impossible allocation (BODY-32).
  <sub>spec · `docs/product-spec/06-request-and-response-body-lifecycle.md:47-47` · high · sha:c2bf15dc8a06</sub>
- An exception-side error-body preview SHOULD be non-consuming, reading from a fresh peek view and returning null when there is no body and empty when exhausted (BODY-33).
  <sub>spec · `docs/product-spec/06-request-and-response-body-lifecycle.md:47-47` · high · sha:c2bf15dc8a06</sub>
- Body logging on both request and response sides MUST engage only when body-level logging is enabled, and the in-memory capture on both sides MUST be bounded by one shared preview-size configuration; the consumer MUST still receive every byte of an over-preview body since only the logged preview and size fields are bounded (BODY-34).
  <sub>spec · `docs/product-spec/06-request-and-response-body-lifecycle.md:48-48` · high · sha:c2bf15dc8a06</sub>
- The error taxonomy MUST have exactly two top-level branches — protocol errors carrying a fully-received response raised as an unchecked/runtime error, and transport errors carrying no response that belong to the runtime's I/O-error family — with a transport error always reporting itself retryable at the error level. (XCUT-4)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:15` · high · sha:d6123be82c9e</sub>
- The baked retryability flag of a protocol error MUST be computed once at construction from a single shared status classifier rather than hardcoded per subclass. (XCUT-5, XCUT-7)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:16` · high · sha:d6123be82c9e</sub>
- A transport-family or custom error type that declares itself retryable via the retryability capability MUST participate in retry decisions without any edit to the classifier, since the classifier queries the capability rather than matching a concrete type. (XCUT-6, XCUT-7)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:17` · high · sha:d6123be82c9e</sub>
- The status-to-exception mapping factory MUST reject being asked to map a non-error status (1xx/2xx/3xx) by raising an argument error rather than fabricating a successful exception, though a convenience form MAY return an absent/null value for non-error statuses instead. (XCUT-8)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:19` · high · sha:d6123be82c9e</sub>
- Any classification that walks an error's cause chain MUST be cycle-safe, tracking visited causes by reference identity and terminating on a self-referential or cyclic chain. (XCUT-9)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:20` · high · sha:d6123be82c9e</sub>
- Any code that classifies an error by walking its cause chain must track visited causes by reference identity and terminate on a self-referential or cyclic chain instead of looping forever. (XCUT-2, XCUT-9)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:162-164` · high · sha:6b7ebc1dfd1d</sub>
- Every error classification in the port walks the cause chain through `Dexpace.each_cause`, and none walks `#cause` by hand, including the suppressed-error trail since a suppressed error may itself carry a cause. (CTX-9)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:169-171` · high · sha:6b7ebc1dfd1d</sub>

## Constraints
- Turning an error response into an exception MUST buffer at most a fixed cap of 1 MiB of the error body into memory and re-serve it as a replayable body, dropping bytes beyond the cap (HTTP-52/BODY-30).
  <sub>spec · `docs/product-spec/06-request-and-response-body-lifecycle.md:46-46` · high · sha:c2bf15dc8a06</sub>
- Ruby's `Exception#cause` provides a single-parent causal chain set automatically when re-raising inside a rescue, but Ruby has nothing resembling a built-in suppressed-exception list. (RECOV-12, PAGE-13, PAGE-15, SSE-29, SSE-36, RETRY-34)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:151-153` · high · sha:6b7ebc1dfd1d</sub>
- Ruby does not prevent cause-chain cycles because `#cause` is settable through `Exception#exception`, and application re-raise chains can close on themselves, turning an infinite cause walk inside a rescue handler into an unkillable hang rather than a stack overflow.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:164-166` · high · sha:6b7ebc1dfd1d</sub>

## Conclusions
- `#cause` is left entirely to Ruby's automatic mechanism and is never used for the suppressed trail, because the two express different relationships: "caused by" versus "happened while cleaning up after," and conflating them would make a close failure look like a root cause.
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:156-158` · high · sha:6b7ebc1dfd1d</sub>
- Core provides one `Dexpace.each_cause(error)` enumerator that tracks visited objects by `equal?` rather than `==`, because core's `Data`-based errors define structural equality that would otherwise truncate a legitimate chain of two distinct errors carrying identical fields. (CTX-9)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:166-169` · high · sha:6b7ebc1dfd1d</sub>

## Reference
- Below `StandardError` in Ruby's exception tree sit `SignalException` (including `Interrupt`), `NoMemoryError`, `SystemExit`, and `ScriptError`, all of which `rescue Exception` would incorrectly catch.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/08-error-handling.md:131` · high · sha:ca24f5238acf</sub>
- Chapter 08 (Error Handling) covers `StandardError` subclasses, never rescuing `Exception`, banning flow-control by exception, implicit `begin`, banning empty/`nil`/modifier rescue, raising with a class and message, and `cause` chaining.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:41-41` · high · sha:fa61163448dd</sub>
- A protocol error's baked retryability flag and the retry step's configurable retryable-status set are distinct notions with distinct default membership, and the configured set is what the retry step actually consults. (XCUT-5, XCUT-7)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:5` · high · sha:d6123be82c9e</sub>
- The shared status classifier treats HTTP status 408, 429, and all 5xx statuses except 501 and 505 as retryable, and everything else as not retryable. (XCUT-5, XCUT-7)
  <sub>spec · `docs/product-spec/19-cross-cutting-invariants-and-policies.md:16` · high · sha:d6123be82c9e</sub>
- A protocol error is an error meaning a complete response was received but its status is 4xx/5xx, expressed as an unchecked/runtime error carrying the response.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:47` · high · sha:f0b3d2058626</sub>
- A transport error is a failure that produced no response, such as connect refused, DNS/TLS failure, read timeout, or peer reset, belonging to the runtime's I/O-error family and always-retryable at the error level.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:65` · high · sha:f0b3d2058626</sub>
- Core's error root `Dexpace::Error` carries a `#suppressed` array, frozen once populated, with `#full_message` overridden to render the suppression trail. (PAGE-15, SSE-29, SSE-36, RETRY-34)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:153-154` · high · sha:6b7ebc1dfd1d</sub>
- One `Dexpace.attach_suppressed(primary, secondary)` helper skips attaching an exception to itself, implementing the self-suppression guard. (RETRY-34)
  <sub>design · `docs/sdk-design-ruby/05-pipeline-architecture.md:154-156` · high · sha:6b7ebc1dfd1d</sub>

## Conflicts

## Superseded
