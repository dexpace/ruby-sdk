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

  def teardown
    @pool.close
    (@prior_storage.keys | Diagnostics.capture.keys | %i[trace.id tenant]).each do |key|
      ::Fiber[key] = @prior_storage[key]
    end
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
    seen.pop
  end

  test "ASYNC-10/R8: a build-time key absent from the caller's snapshot is invisible to the task" do
    observed = observed_on_worker { { "trace.id": "CALLER-A" } }

    refute(observed.key?(:tenant), "the pool's build-time context leaked into the caller's task")
    assert_equal({ "trace.id": "CALLER-A" }, observed)
  end

  test "ASYNC-9: reuse across two tasks, install-and-restore exact across a throw" do
    gate = ::Thread::Queue.new
    @pool.post do
      Diagnostics.with({ "trace.id": "A" }) { gate << visible(Diagnostics.capture) }
    end
    first = gate.pop

    @pool.post { Diagnostics.with({ "trace.id": "B" }) { raise "boom" } }

    @pool.post { gate << visible(Diagnostics.capture) }
    after_throw = gate.pop

    assert_equal({ "trace.id": "A" }, first)
    assert_empty(after_throw, "the worker's own (post-clear) context must be intact after a throw")
  end

  test "ASYNC-11: an absent context captures as empty and installs as a clear, not a raise" do
    result_queue = ::Thread::Queue.new
    @pool.post { Diagnostics.with({}) { result_queue << visible(Diagnostics.capture) } }

    assert_empty(result_queue.pop)

    # The caller has no context at all here; the job's snapshot is capture's `|| {}` branch.
    @pool.post { result_queue << visible(Diagnostics.capture) }

    assert_empty(result_queue.pop)
  end

  # The reuse floor, and the one the thread-start clear does NOT reach: Diagnostics.with restores
  # only (prior.keys | snapshot.keys), so a key the BLOCK writes is in neither set. Without #run's
  # ensure clear this observes {leaked_by_work: "A-LEAK", "trace.id": "CALLER-B"} -- caller A's tag
  # on caller B's log lines, on one reused worker. size: 1 is load-bearing: both tasks must land on
  # the same worker or the assertion is vacuous.
  test "ASYNC-9/R8: a key the work itself writes does not survive onto the next caller's task" do
    gate = ::Thread::Queue.new
    Diagnostics.with({ "trace.id": "CALLER-A" }) do
      @pool.post do
        ::Fiber[:leaked_by_work] = "A-LEAK"
        gate << :done
      end
    end
    gate.pop

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

    assert_equal(%w[B C], [seen.pop, seen.pop])
  end

  # ASYNC-12's conformance clause, written for the case that exists: a context entry set on the
  # caller thread AFTER the pool was built reaches the transport call on the worker.
  test "ASYNC-12: an entry set on the caller after the pool was built is seen on the worker" do
    ::Fiber[:set_after_build] = "late"
    seen = ::Thread::Queue.new
    @pool.post { seen << ::Fiber[:set_after_build] }

    assert_equal("late", seen.pop)
  ensure
    ::Fiber[:set_after_build] = nil
  end

  test "ASYNC-9: a worker's storage is empty before its first task, whatever the builder had" do
    seen = ::Thread::Queue.new
    @pool.post { seen << visible(Diagnostics.capture) }

    assert_empty(seen.pop)
  end
end
