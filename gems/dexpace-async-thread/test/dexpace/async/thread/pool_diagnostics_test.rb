# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace/async/thread"

# ASYNC-8..ASYNC-12 (R8, R9, P8-20). Every test restores the slot it touches in teardown
# (testing/4ef070df); every pool is built fresh in `setup`, in a DIFFERENT fiber-storage context
# than the one it is driven from, per the design's verified fact 7 -- a suite that builds the
# pool in the test body, in the caller's own context, passes under the bug this suite exists to
# catch.
#
# Every read of the worker's context goes through Dexpace::Instrumentation::Diagnostics.capture,
# never `Fiber.current.storage` raw: on the 3.2 floor `Fiber[:k] = nil` RETAINS the key with a nil
# value (P5-72), so the raw map on a cleared worker is `{tenant: nil, ...}` there and `{}` on
# 3.3+, while `.capture` compacts nil-valued keys (P5-97) and reads the same on every row. The
# "key the work itself writes" proof writes a key the worker has NEVER held (:leaked_by_work),
# because a key set at pool-build time and cleared sits in the floor's prior map as a retained nil,
# where the union restore resets it and hides the missing ensure-clear on 3.2 alone.
#
# Core's own `dexpace.`-prefixed slots (5c's current-span carrier) travel in the snapshot by design
# -- carrying the caller's active span to the worker is ASYNC-8's whole purpose -- and are read
# through `visible`, which drops them: under `rake test:gems` another gem's suite can leave a
# no-op span on the main fiber, and these tests are about the diagnostic keys the pool installs.
class PoolDiagnosticsTest < DexpaceTestCase
  Pool = Dexpace::Async::Thread::Pool
  Diagnostics = Dexpace::Instrumentation::Diagnostics

  def setup
    super
    @prior_storage = Diagnostics.capture
    ::Fiber[:"trace.id"] = "POOL-BUILD-TIME"
    ::Fiber[:tenant] = "assembly"
    # The one worker inherits {trace.id: POOL-BUILD-TIME, tenant: assembly} HERE, at ::Thread.new's
    # moment of creation (verified facts 5 and 7).
    @pool = Pool.build(size: 1)
    # The caller's OWN context, from this point on, must not carry the build-time keys: a real
    # caller submitting a request was never on the thread that built the pool. Diagnostics.capture
    # runs on THIS thread inside #post, so an uncleared :tenant here would appear in every job's
    # snapshot regardless of whether the worker leaked anything -- indistinguishable from the bug.
    ::Fiber[:"trace.id"] = nil
    ::Fiber[:tenant] = nil
  end

  # The restore is asserted, not assumed (the design's testing strategy, group 4: "a teardown-order
  # assertion proves the restoration itself"): after the per-key restore the main fiber's
  # compacted storage must read exactly as it did before setup wrote the build-time keys, core's
  # reserved slots included. It lives in teardown because the restore does -- the base's own
  # thread count is the precedent for an assertion there.
  def teardown
    @pool.close
    (@prior_storage.keys | Diagnostics.capture.keys | %i[trace.id tenant]).each do |key|
      ::Fiber[key] = @prior_storage[key]
    end

    assert_equal(@prior_storage, Diagnostics.capture, # rubocop:disable Minitest/AssertionInLifecycleHook -- the teardown-order assertion the design's testing strategy names; the restore it proves runs here
                 "teardown did not restore the main fiber's storage",)
    super
  end

  # A snapshot without core's reserved slots (Diagnostics::RESERVED_PREFIX).
  def visible(snapshot)
    snapshot.reject { |key, _| key.name.start_with?(Diagnostics::RESERVED_PREFIX) }
  end

  # What the worker sees, read on the worker through the one reader that is uniform across rows.
  def observed_on_worker(&)
    seen = ::Thread::Queue.new
    Diagnostics.with(yield) { @pool.post { seen << visible(Diagnostics.capture) } }
    seen.pop(timeout: 5)
  end

  # The first carrier, the workers (P8-20 as designed).
  class WorkerContextTest < PoolDiagnosticsTest
    test "ASYNC-10/R8: a build-time key not in the caller's snapshot is invisible to the task" do
      observed = observed_on_worker { { "trace.id": "CALLER-A" } }

      refute(observed.key?(:tenant), "the pool's build-time context leaked into the caller's task")
      assert_equal({ "trace.id": "CALLER-A" }, observed)
    end

    test "ASYNC-9: reuse across two tasks, install-and-restore exact across a throw" do
      gate = ::Thread::Queue.new
      @pool.post do
        Diagnostics.with({ "trace.id": "A" }) { gate << visible(Diagnostics.capture) }
      end
      first = gate.pop(timeout: 5)

      @pool.post { Diagnostics.with({ "trace.id": "B" }) { raise "boom" } }

      @pool.post { gate << visible(Diagnostics.capture) }
      after_throw = gate.pop(timeout: 5)

      assert_equal({ "trace.id": "A" }, first)
      assert_empty(after_throw, "the worker's own (post-clear) context must survive a throw")
    end

    test "ASYNC-11: an absent context captures as empty and installs as a clear, not a raise" do
      result_queue = ::Thread::Queue.new
      @pool.post { Diagnostics.with({}) { result_queue << visible(Diagnostics.capture) } }

      assert_empty(result_queue.pop(timeout: 5))

      # The caller has no context at all here; the job's snapshot is capture's `|| {}` branch.
      @pool.post { result_queue << visible(Diagnostics.capture) }

      assert_empty(result_queue.pop(timeout: 5))
    end

    # The reuse floor, and the one the thread-start clear does NOT reach: Diagnostics.with
    # restores only (prior.keys | snapshot.keys), so a key the BLOCK writes is in neither set.
    # Without #run's ensure clear this observes {leaked_by_work: "A-LEAK", "trace.id": "CALLER-B"}
    # -- caller A's tag on caller B's log lines, on one reused worker. size: 1 is load-bearing:
    # both tasks must land on the same worker or the assertion is vacuous.
    test "ASYNC-9/R8: a key the work itself writes does not survive onto the next caller's task" do
      gate = ::Thread::Queue.new
      Diagnostics.with({ "trace.id": "CALLER-A" }) do
        @pool.post do
          ::Fiber[:leaked_by_work] = "A-LEAK"
          gate << :done
        end
      end

      refute_nil(gate.pop(timeout: 5), "the first task never ran")

      seen = observed_on_worker { { "trace.id": "CALLER-B" } }

      refute(seen.key?(:leaked_by_work),
             "the previous task's fiber-storage write leaked onto the next caller",)
      assert_equal({ "trace.id": "CALLER-B" }, seen)
    end

    test "ASYNC-8/10/12: the three-context sequence -- assemble A, execute B, re-execute C" do
      # The pool was assembled under A (setup); each use captures its OWN live context, here.
      seen = ::Thread::Queue.new
      Diagnostics.with({ "trace.id": "B" }) { @pool.post { seen << ::Fiber[:"trace.id"] } }
      Diagnostics.with({ "trace.id": "C" }) { @pool.post { seen << ::Fiber[:"trace.id"] } }

      assert_equal(%w[B C], Array.new(2) { seen.pop(timeout: 5) })
    end

    # ASYNC-12's conformance clause, written for the case that exists: a context entry set on the
    # caller thread AFTER the pool was built reaches the transport call on the worker.
    test "ASYNC-12: an entry set on the caller after the pool was built is seen on the worker" do
      ::Fiber[:set_after_build] = "late"
      seen = ::Thread::Queue.new
      @pool.post { seen << ::Fiber[:set_after_build] }

      assert_equal("late", seen.pop(timeout: 5))
    ensure
      ::Fiber[:set_after_build] = nil
    end

    test "ASYNC-9: a worker's storage is empty before its first task, whatever the builder had" do
      seen = ::Thread::Queue.new
      @pool.post { seen << visible(Diagnostics.capture) }

      assert_empty(seen.pop(timeout: 5))
    end
  end

  # The gem's SECOND ::Thread.new carrier, the timer thread: spawned by the first positive #delay
  # from THAT caller's fiber, so it inherits that caller's storage at creation exactly as a worker
  # inherits the builder's (verified fact 7). Review round 2's R2-1: with neither of P8-20's clears
  # on this thread and no per-delay snapshot, every later delay's #on_settle and #then ran under
  # the first caller's context -- caller B's handler tagged with caller A's trace id, a contextless
  # caller C's too, and a key one handler wrote visible to every later one. ASYNC-8 names callbacks
  # explicitly; P8-78 extends P8-20 to this thread. Every read is on the timer thread through
  # `visible(Diagnostics.capture)`, as the worker cases read, and bounded.
  class TimerContextTest < PoolDiagnosticsTest
    TIMER = "#{Pool::DEFAULT_NAME} timer".freeze

    # What a delay's #on_settle handler sees, read on the thread it runs on.
    def observed_on_timer(snapshot, duration = 0.01)
      seen = ::Thread::Queue.new
      Diagnostics.with(snapshot) do
        @pool.delay(duration).on_settle do
          seen << [::Thread.current.name, visible(Diagnostics.capture)]
        end
      end
      seen.pop(timeout: 5)
    end

    test "ASYNC-8/10 on the timer: A spawns it; B's and C's handlers read B's and an empty one" do
      a = observed_on_timer({ "trace.id": "CALLER-A", tenant: "a-corp" })
      b = observed_on_timer({ "trace.id": "CALLER-B" })
      c = observed_on_timer({})

      assert_equal([TIMER, { "trace.id": "CALLER-A", tenant: "a-corp" }], a)
      assert_equal([TIMER, { "trace.id": "CALLER-B" }], b)
      assert_equal([TIMER, {}], c)
    end

    # The construction floor on the timer thread, isolated from the reuse floor: the FIRST handler
    # to fire belongs to a caller whose snapshot lacks a key the spawning caller had. Without the
    # thread-start clear it reads {trace.id: CALLER-B, tenant: spawner-corp} -- the spawner's key
    # underneath B's install, which B's snapshot has no key to overwrite.
    test "ASYNC-10: the first handler to fire does not see the spawning caller's keys" do
      spawner = Diagnostics.with({ "trace.id": "SPAWNER", tenant: "spawner-corp" }) do
        @pool.delay(10.0)
      end
      seen = observed_on_timer({ "trace.id": "CALLER-B" })
      spawner.cancel(:done)

      refute_nil(seen, "the delay never fired")
      refute(seen.last.key?(:tenant), "the spawning caller's context leaked into a later handler")
      assert_equal([TIMER, { "trace.id": "CALLER-B" }], seen)
    end

    # The reuse floor: a key the HANDLER writes is in neither (prior.keys | snapshot.keys) set, so
    # without the clear after each callback it is visible to every later handler on the thread.
    test "ASYNC-9: a key a handler writes on the timer thread is invisible to the next handler" do
      gate = ::Thread::Queue.new
      Diagnostics.with({ "trace.id": "CALLER-A" }) do
        @pool.delay(0.01).on_settle do
          ::Fiber[:leaked_by_handler] = "A-LEAK"
          gate << :done
        end
      end

      refute_nil(gate.pop(timeout: 5), "the first delay never fired")

      seen = observed_on_timer({ "trace.id": "CALLER-B" })

      refute_nil(seen, "the second delay never fired")
      refute(seen.last.key?(:leaked_by_handler),
             "the previous handler's fiber-storage write leaked onto the next caller's handler",)
      assert_equal([TIMER, { "trace.id": "CALLER-B" }], seen)
    end

    # ASYNC-18's stated purpose is "to insert async delays into a future chain": the continuation
    # a caller chains onto a delay future runs on the timer thread under that caller's context --
    # a timer another request spawned, so the context is reinstated and never merely inherited.
    test "ASYNC-8: a #then continuation on a delay future runs under the delay caller's context" do
      spawner = Diagnostics.with({ "trace.id": "REQUEST-1" }) { @pool.delay(10.0) }
      seen = ::Thread::Queue.new
      Diagnostics.with({ "trace.id": "REQUEST-2" }) do
        @pool.delay(0.01).then do |_|
          seen << [::Thread.current.name, visible(Diagnostics.capture)]
          :ok
        end
      end

      assert_equal([TIMER, { "trace.id": "REQUEST-2" }], seen.pop(timeout: 5))
      spawner.cancel(:done)
    end

    # The shutdown callback runs on the CLOSING thread, under the delay caller's context for its
    # duration, and the closer's own context is put back after it (ASYNC-9's save and restore on
    # the callback thread); the closer's thread is not the timer's to clear.
    test "ASYNC-8/9: a delay #close fails settles under its caller's context, then the closer's" do
      future = Diagnostics.with({ "trace.id": "REQUEST-3" }) { @pool.delay(10.0) }
      seen = ::Thread::Queue.new
      future.on_settle { seen << [::Thread.current, visible(Diagnostics.capture)] }

      closer_after = Diagnostics.with({ "trace.id": "CLOSER" }) do
        @pool.close
        visible(Diagnostics.capture)
      end

      assert_equal([::Thread.current, { "trace.id": "REQUEST-3" }], seen.pop(timeout: 5))
      assert_equal({ "trace.id": "CLOSER" }, closer_after)
    end
  end
end
