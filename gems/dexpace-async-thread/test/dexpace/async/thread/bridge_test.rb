# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/pool_fake_transport"
require_relative "../../../support/counting_response"
require "dexpace/async/thread"

# ASYNC-1, ASYNC-2, ASYNC-5, ASYNC-7, ASYNC-13, ASYNC-14, ASYNC-15(b), ASYNC-17, ASYNC-19,
# ASYNC-20; PIPE-33 clauses 1-4 re-asserted through a real pool; ASYNC-6's stated thread-pool
# half; ASYNC-3's mitigation (R10) and ASYNC-4's vacuity, demonstrated rather than re-decided.
# Every mechanism under test is phase 2's, shipped and reviewed -- this is the first suite to
# drive it end to end over a real worker rather than an inline executor or a synchronous fake.
#
# Every "window" assertion gates on the double's `entered` queue before cancelling: phase 2's
# Bridge::AsyncOver checks the token BEFORE dispatch as well as after, so a cancel that lands
# before the worker reaches #call never reaches the transport at all, and a test that cancelled
# straight after posting was red three runs in twelve. Every wait is bounded.
class BridgeTest < DexpaceTestCase
  Pool = Dexpace::Async::Thread::Pool

  def teardown
    @pool&.close
    super
  end

  def build(size: 2)
    @pool = Pool.build(size: size)
  end

  def within(seconds) = Dexpace::Clock.deadline_in(seconds)

  def request
    Dexpace::Request.build(method: :get, url: "https://example.test/pets",
                           headers: Dexpace::Headers::EMPTY,)
  end

  # ASYNC-1, ASYNC-2, ASYNC-13, ASYNC-19: what the future delivers and what it fails with.
  class DeliveryTest < BridgeTest
    test "ASYNC-1: delivers the exact Response object, through a real worker" do
      pool = build
      response = Object.new
      transport = PoolFakeTransport.new(response: response)
      async = Dexpace::Transport.async_over(transport, executor: pool)

      future = async.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)

      assert_same(response, future.value(deadline: within(5)))
    end

    test "ASYNC-1: the send runs on a pool worker, never the caller's thread" do
      pool = build(size: 1)
      seen = ::Thread::Queue.new
      transport = lambda { |_request, _options, _cancellation|
        seen << ::Thread.current.name
        :ok
      }
      async = Dexpace::Transport.async_over(transport, executor: pool)

      async.call(request, nil, nil).value(deadline: within(5))

      assert_equal("#{pool.name} worker 0", seen.pop)
    end

    test "ASYNC-2/ASYNC-13: a raised failure arrives as the identical exception object" do
      pool = build
      boom = ::IOError.new("connection reset")
      transport = PoolFakeTransport.new(raises: boom)
      async = Dexpace::Transport.async_over(transport, executor: pool)

      future = async.call(request, nil, nil)

      caught = assert_raises(::IOError) { future.value(deadline: within(5)) }
      assert_same(boom, caught, "ASYNC-13: no wrapper exists, so unwrap is the identity function")
      assert_nil(caught.cause)
    end

    test "ASYNC-2: a closed pool settles the future exceptionally, never raising from #call" do
      pool = build
      pool.close
      transport = PoolFakeTransport.new(response: :ok)
      async = Dexpace::Transport.async_over(transport, executor: pool)

      future = async.call(request, nil, nil)

      assert_predicate(future, :settled?)
      error = assert_raises(Dexpace::ClosedError) { future.value }

      assert_equal("#{pool.name} is closed", error.message)
      assert_empty(transport.calls)
    end

    test "ASYNC-2: submitting through a saturated pool settles the future with RejectedError" do
      pool = build(size: 1)
      pool_limited = Pool.build(size: 1, queue_limit: 1, name: "tiny")
      gate = ::Thread::Queue.new
      entered = ::Thread::Queue.new
      pool_limited.post do
        entered << :in
        gate.pop
      end
      entered.pop
      pool_limited.post { nil } # the one slot
      async = Dexpace::Transport.async_over(PoolFakeTransport.new(response: :ok),
                                            executor: pool_limited,)

      future = async.call(request, nil, nil)

      assert_predicate(future, :settled?)
      assert_raises(Dexpace::Async::Thread::RejectedError) { future.value }
      gate << :go
      pool_limited.close
      pool.close
    end

    test "ASYNC-19: the exact RequestOptions object arrives at the wrapped transport" do
      pool = build
      options = Dexpace::RequestOptions.build(timeout: 1.5, max_retries: 2, tags: { "k" => "v" })
      req = request
      token = Dexpace::Cancellation.source.token
      transport = PoolFakeTransport.new(response: :ok)
      async = Dexpace::Transport.async_over(transport, executor: pool)

      async.call(req, options, token).value(deadline: within(5))

      recorded = transport.calls.first

      assert_same(req, recorded[0])
      assert_same(options, recorded[1])
      assert_same(token, recorded[2])
    end
  end

  # ASYNC-5, ASYNC-20, ASYNC-3's mitigation, ASYNC-7's documented outcome.
  class CancellationTest < BridgeTest
    test "ASYNC-5: a cancel between the worker producing a Response and delivery closes it once" do
      pool = build(size: 1)
      response = CountingResponse.new
      source = Dexpace::Cancellation.source
      gate = ::Thread::Queue.new
      entered = ::Thread::Queue.new
      transport = PoolFakeTransport.new(response: response, gate: gate, entered: entered)
      async = Dexpace::Transport.async_over(transport, executor: pool)

      future = async.call(request, nil, source.token)
      entered.pop # the worker is provably inside #call, past the pre-dispatch check
      source.cancel(:too_late) # cancel BEFORE the worker's #call returns
      gate << :go # now let the transport return the response

      error = assert_raises(Dexpace::CancelledError) { future.value(deadline: within(5)) }

      assert_equal(:too_late, error.reason)
      assert_equal(1, response.closes)
      assert_predicate(response, :closed?)
      assert_equal(1, transport.calls.size)
    end

    test "ASYNC-20: cancelling AFTER delivery never closes the delivered response" do
      pool = build
      response = CountingResponse.new
      transport = PoolFakeTransport.new(response: response)
      async = Dexpace::Transport.async_over(transport, executor: pool)

      future = async.call(request, nil, nil)
      delivered = future.value(deadline: within(5))
      future.cancel(:too_late)

      assert_same(response, delivered)
      assert_equal(0, response.closes)
      refute_predicate(response, :closed?)
      refute_predicate(future, :cancelled?)
    end

    # ASYNC-3's third clause and ASYNC-5 in one test, against what core DOES: phase 2's
    # AsyncOver checks the token before dispatch, so a task cancelled while still queued never
    # reaches the transport -- no round trip, no response, nothing to close. Stronger than the
    # design's "the orphan closes exactly once", which is the AFTER-dispatch window above.
    test "ASYNC-3 (unsatisfied MUST, 10.5)/ASYNC-5: a task cancelled while queued never runs" do
      pool = build(size: 1)
      occupy_gate = ::Thread::Queue.new
      occupied = ::Thread::Queue.new
      pool.post do
        occupied << :in
        occupy_gate.pop # occupy the one worker so the second unit stays queued
      end
      occupied.pop

      response = CountingResponse.new
      source = Dexpace::Cancellation.source
      transport = PoolFakeTransport.new(response: response)
      async = Dexpace::Transport.async_over(transport, executor: pool)

      future = async.call(request, nil, source.token)
      source.cancel(:gave_up_while_queued)
      occupy_gate << :go

      error = assert_raises(Dexpace::CancelledError) { future.value(deadline: within(5)) }

      assert_equal(:gave_up_while_queued, error.reason)
      pool.close # drains the queued unit, so the assertions below are about a finished walk

      assert_empty(transport.calls, "a cancelled-while-queued task performed its round trip")
      assert_equal(0, response.closes)
      # Nothing was ever interrupted: the worker that would have run it finished its own task and
      # this port never claims to have aborted a running send (ASYNC-3's mitigation, R10).
    end

    # ASYNC-7's documented outcome for this adapter, and ASYNC-6's stated half: an in-flight
    # blocking read runs to completion whatever the caller does -- the cancel reaches the worker
    # only at its next check-after-resume point, which is after the send returns -- and the SDK
    # closes the result it can no longer deliver rather than delivering it.
    test "ASYNC-7: an in-flight read that ignores cancellation completes; its result is closed" do
      pool = build(size: 1)
      gate = ::Thread::Queue.new
      entered = ::Thread::Queue.new
      response = CountingResponse.new
      transport = PoolFakeTransport.new(response: response, gate: gate, entered: entered,
                                        ignores_cancellation: true,)
      async = Dexpace::Transport.async_over(transport, executor: pool)
      source = Dexpace::Cancellation.source

      future = async.call(request, nil, source.token)
      entered.pop
      source.cancel(:abandoned)

      refute_predicate(future, :settled?,
                       "nothing interrupted the worker: the future settles when the read returns",)

      gate << :go # the worker's #call returns AFTER the cancel, as for an uncooperative read

      assert_raises(Dexpace::CancelledError) { future.value(deadline: within(5)) }
      assert_equal(1, response.closes)
      assert_predicate(transport, :ignores_cancellation?)
    end
  end

  # ASYNC-14: phase 2's SyncOver, driven over a real worker.
  class SyncBridgeTest < BridgeTest
    test "ASYNC-14: AsyncTransport.sync_over round-trips the exact response through the pool" do
      pool = build
      response = Object.new
      transport = PoolFakeTransport.new(response: response)
      sync = Dexpace::AsyncTransport.sync_over(Dexpace::Transport.async_over(transport,
                                                                             executor: pool,))

      assert_same(response, sync.call(request, nil, nil))
    end

    test "ASYNC-14: sync_over surfaces a cancellation as CancelledError with its reason" do
      pool = build
      gate = ::Thread::Queue.new
      entered = ::Thread::Queue.new
      transport = PoolFakeTransport.new(response: :never, gate: gate, entered: entered)
      async = Dexpace::Transport.async_over(transport, executor: pool)
      sync = Dexpace::AsyncTransport.sync_over(async)
      source = Dexpace::Cancellation.source

      # The canceller waits on the double's `entered` queue, not on a clock: it fires once the
      # worker is provably inside #call and blocked on the gate.
      canceller = ::Thread.new do
        entered.pop
        source.cancel(:interrupted)
      end
      error = assert_raises(Dexpace::CancelledError) { sync.call(request, nil, source.token) }
      canceller.join
      gate << :go # release the worker so it does not linger past the test

      assert_equal(:interrupted, error.reason)
      refute_kind_of(::IOError, error)
    end

    test "ASYNC-14: sync_over unwraps nothing because nothing is wrapped -- the same object" do
      pool = build
      boom = ::RuntimeError.new("sync boom")
      sync = Dexpace::AsyncTransport.sync_over(
        Dexpace::Transport.async_over(PoolFakeTransport.new(raises: boom), executor: pool),
      )

      caught = assert_raises(::RuntimeError) { sync.call(request, nil, nil) }

      assert_same(boom, caught)
    end
  end

  # ASYNC-15(b), ASYNC-16, ASYNC-17, XCUT-22 at the bridge.
  class LifecycleTest < BridgeTest
    test "ASYNC-17: a lambda-shaped async transport's #close is a safe no-op through the bridge" do
      pool = build
      lambda_transport = ->(_r, _o, _c) { :ok }
      async = Dexpace::Transport.async_over(lambda_transport, executor: pool)

      assert_nil(async.close)
      assert_predicate(async, :closed?)
      refute_predicate(async, :owned?)
      assert_equal(:ok, async.call(request, nil, nil).value(deadline: within(5)))
    end

    test "ASYNC-15(b)/XCUT-22: closing the bridge does not close the caller-supplied pool" do
      pool = build
      transport = PoolFakeTransport.new(response: :ok)
      async = Dexpace::Transport.async_over(transport, executor: pool)

      async.close

      refute_predicate(pool, :closed?,
                       "ASYNC-15(b): the pool is the caller's; the bridge never owns it",)
      assert_equal(:ok, async.call(request, nil, nil).value(deadline: within(5)))
    end

    test "ASYNC-16: closing the pool under a bridged send in flight lets it finish and deliver" do
      pool = build(size: 1)
      gate = ::Thread::Queue.new
      entered = ::Thread::Queue.new
      transport = PoolFakeTransport.new(response: :finished, gate: gate, entered: entered)
      async = Dexpace::Transport.async_over(transport, executor: pool)

      future = async.call(request, nil, nil)
      entered.pop
      closer = ::Thread.new { pool.close }
      gate << :go
      closer.join

      assert_equal(:finished, future.value(deadline: within(5)))
    end
  end

  # PIPE-33's four met clauses, re-asserted through a real pool.
  class PipelineTest < BridgeTest
    # PIPE-33 clause 2 is "runs the wrapped synchronous pipeline as a single opaque unit on that
    # executor ... its own steps stay synchronous on the worker thread and do NOT gain per-step
    # concurrency". A bare transport cannot show that: with no steps there is nothing that could
    # have been posted per step. The unit under test is a MULTI-STEP pipeline, and the count is of
    # #post calls -- not of transport calls -- because #post is where per-step concurrency would
    # appear if the clause were violated. Clause 1 (a caller-supplied executor, no default) is
    # phase 2's InvalidArgumentError, re-asserted; clause 3 is the identical options object;
    # clause 4 (cancel without interruption completes as cancelled) is the window test above.
    test "PIPE-33 clauses 1-3: a multi-step Pipeline posts once, on one worker, options intact" do
      pool = build
      counting = CountingExecutor.new(pool)
      options = Dexpace::RequestOptions.build(timeout: 2.0, max_retries: nil, tags: {})
      transport = PoolFakeTransport.new(response: :ok)
      threads = ::Thread::Queue.new
      pipeline = Dexpace::Pipeline.builder(transport: transport)
        .append(probe_step(threads), stage: Dexpace::Pipeline::Stages::PRE_REDIRECT)
        .append(probe_step(threads), stage: Dexpace::Pipeline::Stages::PRE_RETRY)
        .build
      async = Dexpace::Transport.async_over(pipeline, executor: counting)

      assert_equal(:ok,
                   async.call(request, options,
                              Dexpace::Cancellation.none,).value(deadline: within(5)),)
      assert_equal(1, counting.count,
                   "clause 2: one #post for the whole pipeline, not one per step",)
      assert_equal(1, transport.calls.size)
      assert_same(options, transport.calls.first[1],
                  "clause 3: the caller's options reach the send",)
      step_threads = Array.new(2) { threads.pop(timeout: 1) }

      assert_equal(["#{pool.name} worker"] * 2, step_threads.map { |n| n.sub(/ \d+\z/, "") })
      assert_equal(1, step_threads.uniq.size,
                   "both steps ran on the one worker the unit was posted to",)
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Transport.async_over(pipeline, executor: nil)
      end
    end

    # Delegates to the real pool and counts, so clause 2 is asserted on #post itself rather than
    # inferred from the transport's call count. #post's signature is Dexpace::Page::_Executor's
    # exactly here too -- a counting wrapper that widened it would not be testing what runs.
    class CountingExecutor
      def initialize(pool)
        @pool = pool
        @posts = ::Thread::Queue.new
      end

      def post(&)
        @posts << :posted
        @pool.post(&)
      end

      def count = @posts.size
    end

    # A request-phase transform that records the thread it ran on and passes the request through,
    # so the pipeline is genuinely multi-step without the test asserting anything about what a
    # step does. 4c's TransformStep.build takes anything answering #phase and #apply(request).
    IdentityTransform = ::Struct.new(:threads) do
      def phase = :request

      def apply(request)
        threads << ::Thread.current.name
        request
      end
    end

    def probe_step(threads)
      Dexpace::Pipeline::TransformStep.build(IdentityTransform.new(threads))
    end
  end
end
