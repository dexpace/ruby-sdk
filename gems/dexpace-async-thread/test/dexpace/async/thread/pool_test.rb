# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/pool_recording_sink"
require_relative "../../../support/pool_stub_clock"
require "dexpace/async/thread"

# ASYNC-2 (#post never blocks; a saturated or closed pool is a raise the bridge routes to the
# failure channel), ASYNC-15, ASYNC-16, ASYNC-17 and SEAM-25's lifecycle event (#close), R8/R9's
# clearing line and R12's bound. Every mutable fixture is built fresh per test (testing/4ef070df)
# and closed in teardown BEFORE the base's thread count runs; every "slow" or "stuck" task is a
# Thread::Queue gate the test controls, never a sleep.
class PoolTest < DexpaceTestCase
  Pool = Dexpace::Async::Thread::Pool
  LIB = File.expand_path("../../../../lib", __dir__)

  def teardown
    @pool&.close
    super
  end

  def build(size: 2, **)
    @pool = Pool.build(size: size, **)
  end

  # .build's validation, the defaults and the worker threads it creates (R12).
  class ConstructionTest < PoolTest
    test "size is a required keyword with no default" do
      error = assert_raises(::ArgumentError) { Pool.build }

      assert_match(/size/, error.message)
    end

    test "size rejects zero, a negative, a non-Integer and nil, naming the keyword" do
      [0, -1, "4", 1.5, nil].each do |bad|
        error = assert_raises(Dexpace::InvalidArgumentError) { Pool.build(size: bad) }

        assert_match(/\Asize must be a positive Integer/, error.message, bad.inspect)
      end
    end

    test "queue_limit defaults to size * QUEUE_DEPTH_PER_WORKER and rejects the same shapes" do
      pool = build(size: 3)

      assert_equal(3 * Pool::QUEUE_DEPTH_PER_WORKER, pool.queue_limit)
      assert_equal(8, Pool::QUEUE_DEPTH_PER_WORKER)

      [0, -1, "4"].each do |bad|
        error = assert_raises(Dexpace::InvalidArgumentError) do
          Pool.build(size: 2, queue_limit: bad)
        end

        assert_match(/\Aqueue_limit must be a positive Integer/, error.message, bad.inspect)
      end
    end

    test "shutdown_timeout, name, logger and clock validate, each naming its keyword" do
      { shutdown_timeout: -1, name: "", logger: Object.new,
        clock: Object.new, }.each do |keyword, bad|
        error = assert_raises(Dexpace::InvalidArgumentError) { Pool.build(size: 1, keyword => bad) }

        assert_match(/\A#{keyword} must/, error.message, keyword)
      end
      error = assert_raises(Dexpace::InvalidArgumentError) { Pool.build(size: 1, name: :sym) }

      assert_match(/\Aname must be a non-empty String/, error.message)
    end

    test "name, shutdown_timeout, logger and clock default; size and queue_limit read back" do
      pool = build(size: 1, queue_limit: 3)

      assert_equal(Pool::DEFAULT_NAME, pool.name)
      assert_equal("dexpace-async-thread", Pool::DEFAULT_NAME)
      assert_in_delta(30.0, Pool::DEFAULT_SHUTDOWN_TIMEOUT)
      assert_equal(1, pool.size)
      assert_equal(3, pool.queue_limit)
      assert_predicate(pool, :owned?)
      refute_predicate(pool, :closed?)
    end

    test "Pool.new is private; .build is the one entry point" do
      assert_raises(::NoMethodError) do
        Pool.new(size: 1, queue_limit: 1, shutdown_timeout: 1.0, name: "x",
                 logger: Dexpace::Instrumentation::Logger::NULL, clock: Dexpace::Clock::SYSTEM,)
      end
    end

    # A worker names itself INSIDE its own body (the plan's `.tap { |t| t.name = ... }` named it
    # from outside, after it had started), so the names are read from the workers themselves: three
    # gated tasks, one per worker, each reporting the thread it runs on.
    test "exactly size worker threads are created at construction, each named for the pool" do
      before = ::Thread.list.size
      pool = build(size: 3, name: "named-pool")
      gate = ::Thread::Queue.new
      names = ::Thread::Queue.new
      3.times do
        pool.post do
          names << ::Thread.current.name
          gate.pop
        end
      end
      seen = Array.new(3) { names.pop }
      3.times { gate << :go }

      assert_equal(before + 3, ::Thread.list.size)
      assert_equal(["named-pool worker 0", "named-pool worker 1", "named-pool worker 2"], seen.sort)
      pool.close

      assert_equal(before, ::Thread.list.size)
    end
  end

  # The three source scans over lib/: the spawn sites, the forbidden calls, the ::-qualification.
  class SourceScanTest < PoolTest
    # Comments are stripped before matching, on the CHOMPED line: `line.sub(/#.*\z/, "")` never
    # matched a line File.readlines hands back with its newline (`.` does not match "\n"), so an
    # explanatory comment naming the call counted as a hit. The gem has TWO bounded spawn sites,
    # Pool#spawn_worker and Timer#spawn_thread, both bounded construction in a private method
    # (R12's df658d73 row); the expected set is a literal so adding a site is a deliberate edit
    # here, never a silent count bump.
    SPAWN_SITES = %w[pool.rb timer.rb].freeze

    def lib_files = Dir.glob(File.join(LIB, "**/*.rb"))

    test "every Thread.new in lib/ is in a bounded spawn helper, and there are no others" do
      hits = lib_files.flat_map do |path|
        File.readlines(path).filter_map do |line|
          code = line.chomp.sub(/#.*/, "")
          File.basename(path) if code.include?("::Thread.new") || code.match?(/(?<!:)\bThread\.new/)
        end
      end

      assert_equal(SPAWN_SITES, hits.sort)
    end

    test "the forbidden three, Thread.current[] and Fiber#storage= appear nowhere in lib/" do
      banned = Regexp.union(/Timeout\.timeout/, /Thread#raise/, /\.raise\(/, /Thread#kill/,
                            /\.kill\b/, /Thread\.current\[/, /\.storage\s*=[^=]/,)
      hits = lib_files.flat_map do |path|
        File.readlines(path).map { |line| line.chomp.sub(/#.*/, "") }.grep(banned)
      end

      assert_empty(hits)
    end

    test "every reference to Ruby's Thread and Fiber in lib/ is ::-qualified" do
      bare = /(?<![:\w])(Thread|Fiber|Queue|SizedQueue|Mutex)\b(?!:)/
      hits = lib_files.flat_map do |path|
        File.readlines(path).each_with_index.filter_map do |line, index|
          code = line.chomp.sub(/#.*/, "")
          next if /\A\s*module Thread\b/.match?(code) # the namespace's own definition site

          "#{File.basename(path)}:#{index + 1}: #{code.strip}" if code.match?(bare)
        end
      end

      assert_empty(hits)
    end
  end

  # #post: the worker hop, the non-blocking push (P8-23) and the worker net (P8-22).
  class PostTest < PoolTest
    test "a unit runs on a worker thread, not the caller's, and #post returns nil" do
      pool = build(size: 1)
      seen = ::Thread::Queue.new

      assert_nil(pool.post { seen << ::Thread.current })
      worker = seen.pop(timeout: 5)

      refute_same(::Thread.current, worker)
      assert_equal("#{pool.name} worker 0", worker.name)
    end

    test "post requires a block, refused before anything reaches the queue" do
      pool = build(size: 1)
      error = assert_raises(::ArgumentError) { pool.post }

      assert_match(/block/, error.message)
    end

    test "post returns in bounded time with a full queue, from any thread (P8-23)" do
      pool = build(size: 1, queue_limit: 1)
      gate = ::Thread::Queue.new
      entered = ::Thread::Queue.new
      pool.post do
        entered << :in
        gate.pop
      end
      entered.pop # the one worker is provably occupied
      pool.post { nil } # fills the one-slot queue

      submitter = ::Thread.new do
        pool.post { nil }
      rescue Dexpace::Async::Thread::RejectedError
        :rejected
      end
      result = submitter.join(1)
      gate << :go

      refute_nil(result, "post did not return in bounded time")
      assert_equal(:rejected, submitter.value)
    end

    test "a full queue raises RejectedError naming the pool, the limit and the worker count" do
      pool = build(size: 1, queue_limit: 1, name: "bounded")
      gate = ::Thread::Queue.new
      entered = ::Thread::Queue.new
      pool.post do
        entered << :in
        gate.pop
      end
      entered.pop
      pool.post { nil }

      error = assert_raises(Dexpace::Async::Thread::RejectedError) { pool.post { nil } }

      assert_equal("bounded: queue full (limit 1, 1 workers)", error.message)
      refute_kind_of(::ThreadError, error)
      gate << :go
    end

    test "P8-22: a task that raises a ScriptError does not shrink the pool; the next task runs" do
      sink = PoolRecordingSink.new
      pool = build(size: 1, logger: Dexpace::Instrumentation::Logger.build(sink: sink))
      ran = ::Thread::Queue.new

      pool.post { raise ::NotImplementedError, "a defect in the block" }
      pool.post { ran << ::Thread.current.name }

      assert_equal("#{pool.name} worker 0", ran.pop(timeout: 5), "the worker died")
      pool.close
      hook = sink.events_named(Dexpace::Instrumentation::Events::INSTRUMENTATION_HOOK)

      assert_equal(1, hook.size)
      assert_equal(:error, hook.first.severity)
      assert_includes(hook.first.payload.to_s, "a defect in the block")
    end

    test "P8-22: the worker survives exit, Interrupt and NoMemoryError from a block, silently" do
      pool = build(size: 1)
      ran = ::Thread::Queue.new

      pool.post { exit(3) }
      pool.post { raise ::Interrupt }
      pool.post { raise ::NoMemoryError }
      pool.post { ran << :still_here }

      assert_equal(:still_here, ran.pop(timeout: 5), "the worker died")
    end

    test "P8-22: a sink that raises while reporting a defect cannot kill the worker (OBS-20)" do
      raising = Object.new
      %i[debug info warn error].each do |m|
        raising.define_singleton_method(m) do |*|
          raise "sink boom"
        end
      end
      %i[debug? info? warn? error?].each { |m| raising.define_singleton_method(m) { true } }
      pool = build(size: 1, logger: Dexpace::Instrumentation::Logger.build(sink: raising))
      ran = ::Thread::Queue.new

      pool.post { raise "a defect" }
      pool.post { ran << :still_here }

      assert_equal(:still_here, ran.pop(timeout: 5), "the worker died")
    end
  end

  # #close: ASYNC-15's idempotent latch, ASYNC-16's drain and SEAM-25's one event.
  class CloseTest < PoolTest
    def shutdown_events(sink)
      sink.events_named(Dexpace::Instrumentation::Events::INSTRUMENTATION_SHUTDOWN)
    end

    # Phase 2 fixes Closeable#close's return value at nil for every closeable, and this pins it.
    test "close is idempotent: both calls return nil, only the first releases, the latch flips" do
      pool = build(size: 2)

      assert_nil(pool.close)
      assert_predicate(pool, :closed?)
      assert_nil(pool.close)
      assert_predicate(pool, :closed?)
    end

    test "close from 16 threads at once emits one shutdown event, drained, with the worker count" do
      sink = PoolRecordingSink.new
      pool = build(size: 2, shutdown_timeout: 2.0,
                   logger: Dexpace::Instrumentation::Logger.build(sink: sink),)

      Array.new(16) { ::Thread.new { pool.close } }.each(&:join)
      events = shutdown_events(sink)

      assert_equal(1, events.size)
      assert_equal(:info, events.first.severity)
      assert_equal(2, events.first.payload["dexpace.executor.worker_count"])
      assert_equal(true, events.first.payload["dexpace.executor.drained"]) # rubocop:disable Minitest/AssertTruthy -- the field's VALUE is the boolean true, not a truthy object
    end

    test "ASYNC-16: an in-flight task finishes rather than being interrupted; queued work drains" do
      pool = build(size: 1, queue_limit: 4)
      gate = ::Thread::Queue.new
      entered = ::Thread::Queue.new
      ran = ::Thread::Queue.new
      pool.post do
        entered << :in
        gate.pop
        ran << :first
      end
      pool.post { ran << :second }
      entered.pop

      closer = ::Thread.new { pool.close }
      gate << :go
      closer.join

      assert_equal(%i[first second], [ran.pop, ran.pop])
      assert_predicate(pool, :closed?)
    end

    test "SEAM-15: post after close raises ClosedError naming the pool, never ::ClosedQueueError" do
      pool = build(size: 1, name: "done")
      pool.close

      error = assert_raises(Dexpace::ClosedError) { pool.post { nil } }

      assert_equal("done is closed", error.message)
      refute_kind_of(::ClosedQueueError, error)
    end

    # The translation arm itself, deterministically: #post reads the latch first, so under a
    # real #close the ClosedQueueError branch is reached only in the window between that read and
    # the push -- a window the racing test in pool_concurrency_test.rb opens rarely. Closing the
    # queue UNDERNEATH an open latch is the one way to walk into it every time.
    test "SEAM-15: a queue closed under an open latch surfaces as ClosedError, not the raw one" do
      pool = build(size: 1, name: "underneath")
      pool.instance_variable_get(:@queue).close

      error = assert_raises(Dexpace::ClosedError) { pool.post { nil } }

      assert_equal("underneath is closed", error.message)
      refute_kind_of(::ClosedQueueError, error)
    end

    test "close reports not-drained when the budget is spent, off a stub clock, with no waiting" do
      stub_clock = PoolStubClock.new
      sink = PoolRecordingSink.new
      # shutdown_timeout: 0.0 is the one budget a fake clock can drive end to end: the drain
      # computes `deadline - clock.monotonic` FIRST and returns before touching the exit queue when
      # that is <= 0, so the timed-out branch runs with no queue wait at all -- the branch the
      # design says a fake clock can exercise and a real one cannot. A stuck worker is present, so
      # the branch is reached for the right reason.
      pool = build(size: 1, shutdown_timeout: 0.0, clock: stub_clock,
                   logger: Dexpace::Instrumentation::Logger.build(sink: sink),)
      gate = ::Thread::Queue.new
      entered = ::Thread::Queue.new
      pool.post do
        entered << :in
        gate.pop
      end
      entered.pop

      closer = ::Thread.new { pool.close }

      assert(closer.join(2), "close blocked on a spent budget instead of returning")
      events = shutdown_events(sink)

      assert_equal(1, events.size)
      assert_equal(false, events.first.payload["dexpace.executor.drained"], # rubocop:disable Minitest/RefuteFalse -- the field's VALUE is the boolean false, not a falsy object
                   "the drain must report the budget as spent, not as a clean shutdown",)

      gate << :go # release the stuck task so the worker exits and the suite leaks no thread
      pool.instance_variable_get(:@workers).each { |w| w.join(2) }
    end

    test "ASYNC-15/OBS-20: a sink that raises on the shutdown event does not fail #close" do
      raising = Object.new
      %i[debug info warn error].each do |m|
        raising.define_singleton_method(m) do |*|
          raise "sink boom"
        end
      end
      %i[debug? info? warn? error?].each { |m| raising.define_singleton_method(m) { true } }
      pool = build(size: 1, logger: Dexpace::Instrumentation::Logger.build(sink: raising))

      assert_nil(pool.close)
      assert_predicate(pool, :closed?)
    end

    test "Dexpace.close_quietly closes a pool through the same latch" do
      pool = build(size: 1)

      assert_nil(Dexpace.close_quietly(pool))
      assert_predicate(pool, :closed?)
    end
  end
end
