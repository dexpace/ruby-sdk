# concurrency-and-async — notes

Hand-written. `../harvested/concurrency-and-async.md` is what the documents say; this file is what
the implementation found, and it wins. Each entry names the harvested entry it answers by that
entry's stable key.

## Superseded
- **`Async::Task#cancel` is the current cancellation primitive; `#stop` is a deprecated backward-compatibility
  alias, and `#cancel`'s `cause:` keyword is the out-of-band channel `#stop` never had.** Supersedes
  `concurrency-and-async/f75816b6` ("dexpace-async-async later maps Async::Task#stop and #with_timeout onto the
  pivot's cancellation in both directions per ASYNC-6, and dexpace-async-concurrent_ruby maps
  Concurrent::Promises::Future") on the method name only — the *mapping* it describes is right, and so is its
  `ASYNC-6` citation. Verified on `async` 2.45.1 under Ruby 3.4.10: `lib/async/node.rb` carries
  `# Backward compatibility alias for {#cancel}. # @deprecated Use {#cancel} instead.` immediately above
  `def stop(...) = cancel(...)`, and `Async::Task.instance_method(:stop).owner` is `Async::Node`. The current
  primitive is **`Async::Task#cancel(later = false, cause: $!)`**, and its `cause:` keyword is materially
  better for this port than `#stop` was: a `Dexpace::Cancellation#reason` passed as `cause:` is readable back
  off the raised `Async::Cancel` as `#cause`, which is the out-of-band discrimination `XCUT-2` and
  `TRANSPORT-3` require and which `#stop` gives no channel for. The sentence the harvested entry quotes lives
  in `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:252-254`, a **frozen** chapter, so it is not
  corrected in place: §3.3 is right about the mapping and stale about the name until §3 is next deliberately
  amended by a human. What this repository does meanwhile: **phase 8c calls `#cancel` everywhere** and passes
  the cancellation reason as `cause:`; `dexpace-async-async`, which is post-v1
  (`docs/first-release.md` § What v1 ships without › Post-v1 gems, with `SEAM-24`'s cancellation bridge), is
  written against `#cancel` when it is built. Because `#stop` still forwards, nothing breaks today — what is
  lost by writing `#stop` is the `cause:` channel, silently. This entry re-keys on the next harvest of §3, at
  which point its citation of `concurrency-and-async/f75816b6` needs revisiting. Cites `ASYNC-6`, `SEAM-24`,
  `TRANSPORT-7`.
  <sub>review · `docs/work/mvp/phase8/phase8c/2026-09-11-phase8c-asynchronous-transport-design.md` · high · sha:manual-phase8c-async-task-cancel</sub>

## Conflicts
- **Core's shared mutable state is one frozen `Data` snapshot swapped under a `Thread::Mutex`, not a `concurrent-ruby` collection.** Resolves `concurrency-and-async/b44d400b`, `concurrency-and-async/abfb9ed9`, `concurrency-and-async/960d89ec` and `concurrency-and-async/0e11c51d`. All four say the same thing — prefer `Concurrent::Map`/`Concurrent::Array`/`Concurrent::AtomicFixnum` over a hand-rolled `Mutex` plus a plain `Hash`, and replace bare `Mutex.new` at review — and all four are unavailable here for the same mechanical reason the Sorbet rules are: `concurrent-ruby` is a third-party gem, `dexpace-core.gemspec` is asserted to contain zero `add_dependency` lines (`SEAM-1`, `NFR-1`), and `rake gates:gemspec_audit` rejects one. Library-versus-application again: an application pays that dependency once, a zero-dependency core would impose it on every consumer. What the SDK does instead, per `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md` §3.6 and §3.7: every piece of shared mutable state in `dexpace-core` — the seam registry's factory table and resolved slot, `Dexpace::Async::Future`'s settled outcome, `Dexpace::Cancellation`'s reason, `Dexpace::Closeable`'s closed latch — is held as **one frozen `Data` value in one instance variable**, replaced wholesale under a `Thread::Mutex` on the write path and read without any lock on the read path. A reader therefore takes a single reference read and sees a consistent, fully-constructed, deep-frozen picture or the previous one, never a torn mixture, which is `SEAM-9`'s three clauses ("reads observe the latest install without blocking, writes are serialized, a concurrent first-access cannot run the discovery scan twice") implemented rather than argued, and is also `IO-39`'s lock-free-read property surviving the seam that used to state it. Verified on 3.2.11 and 4.0.6: a prototype of this shape resolved exactly one instance from 32 concurrent threads with one factory invocation and one scan, and an unresolved registry re-scanned on the next access and picked up a later registration. The rules in this chapter that the substitution does **not** weaken are adopted verbatim and are what make the shape safe: `concurrency-and-async/c0fab747` (protect only the smallest critical section), `concurrency-and-async/ee54cb68` and `concurrency-and-async/f261a143` (never hold a lock across I/O — so the `SEAM-8` warning is emitted outside the mutex, and a callback, a `#release` and a drain always are), and `concurrency-and-async/54d8bb89` with `concurrency-and-async/2c743901` (prefer eliminating shared mutable state, and model anything crossing a concurrency boundary as an immutable `Data` value), which is precisely why the snapshot is a `Data` and not a `Hash`. Two Ruby facts make the "smallest critical section" rule non-negotiable here rather than stylistic, both re-verified on 3.2.11, 3.4.10 and 4.0.6: `Thread::Mutex` is non-reentrant (`ThreadError: deadlock; recursive locking`) and its ownership is **per-fiber**, not per-thread (`ThreadError: deadlock; lock already owned by another fiber belonging to the same thread`), so a lock held across any suspension point deadlocks two fibers of one thread. What is lost and is not replaced: `Concurrent::AtomicFixnum`-style lock-free counters, and `concurrent-ruby`'s tested primitives in place of code this repository has to test itself — which is why every one of those objects ships with an explicit contention test rather than an argument. The bounded-pool and deterministic-teardown rules in the same chapter (`concurrency-and-async/6764e0b5`, `concurrency-and-async/dc345cae`, `concurrency-and-async/df658d73`, `concurrency-and-async/3692970f`, `concurrency-and-async/047644ea`, `concurrency-and-async/dd8e6d2d`) are **not** resolved here and are not weakened: they bind `dexpace-async-thread`, an adapter gem whose `NFR-2` budget permits one third-party library, and they are that gem's to answer in phase 8. The styleguide-amendment alternative (scoping chapter 9's `concurrent-ruby` preference to projects that may take the dependency) was considered and not taken; this is recorded as an SDK deviation instead (phase 2).
  <sub>review · `docs/work/mvp/phase2/2026-09-06-phase2-seam-foundations-design.md` · high · sha:manual-phase2-no-concurrent-ruby</sub>

## Reference
- **A cancelled `Async` task raises an `Exception` that is not a `StandardError`, so every `rescue` written the
  obvious way is blind to it — the close belongs in an `ensure`.** No harvested rule is false here, so no key is
  backticked; what is added is a fact two of them are read against. `error-handling/0871259d` ("Never rescue
  `Exception` in application code; rescue `StandardError` or a named subclass instead") stays true — the repair
  below is an `ensure`, not a widened rescue — and `cross-cutting-invariants/68aad33a` (the two required-to-be-loud
  exceptions to `close_quietly`'s quiet closing) is unaffected. Design §3.3's check-after-resume rule says a
  producer that discovers cancellation while holding a response "MUST close any response it holds and settle
  through the failure channel", and §3.7 makes `Dexpace.close_quietly` the single sanctioned exit for such a
  close — it "rescues `StandardError` from `#close`". Verified on `async` 2.45.1 under Ruby 3.4.10:
  `Async::Stop` **is** `Async::Cancel` — `lib/async/stop.rb` is `module Async; Stop = Cancel; end` — and
  `lib/async/cancel.rb:8` declares `class Cancel < Exception`, so `Async::Stop.equal?(Async::Cancel)` is `true`
  and `Async::Cancel.ancestors.take(3)` is `[Async::Cancel, Exception, Object]` — **not a `StandardError`**.
  `Async::Task#cancel` raises it inside the task (`#stop` is the deprecated alias; see this file's
  `## Superseded` entry), so a `rescue => e` or a `rescue StandardError` in an adapter's send path does **not**
  run, while `task.with_timeout`'s `Async::TimeoutError` **is** a `StandardError` and does. An orphan-close
  written as a `rescue` therefore runs on a timeout and not on a cancellation — the exact inverse of what
  `SEAM-30` and `ASYNC-5` are for, and it is silent. **What every adapter must do:** put the close in an
  `ensure`, where it is reached on both paths, and let `close_quietly` do the rescuing inside it;
  `close_quietly`'s own rescue of `StandardError` from `#close` is correct as written and needs no widening,
  because what the cancellation escapes is the *reaching* of the close, not the close itself. Because the two
  names are one class, `rescue Async::Cancel` and `rescue Async::Stop` catch the same thing; an adapter that
  writes both has written one. A second sanctioned quiet-close exit is **not** the answer — that would give the
  SDK two answers to one question, and `close_quietly`'s contract is phase 2's. Cites `SEAM-30`, `ASYNC-5`,
  `ASYNC-6`, `TRANSPORT-7`, `TRANSPORT-9`, `TRANSPORT-22`, `CFG-21`, `XCUT-13`.
  <sub>review · `docs/work/mvp/phase8/2026-09-11-phase8-segmentation-design.md` · high · sha:manual-phase8-async-cancel-not-standarderror</sub>
