# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/page_fixtures"
require_relative "../../support/probe_executor"
require_relative "../../support/inline_executor"

# Exercises: PAGE-25 through PAGE-33, PAGE-6's async half (R10), PAGE-1's async half (#walk_pages),
# PAGE-13 and PAGE-27 on the async paths; R9.
#
# R9: this engine calls no wait of any kind -- not Clock#sleep, not Async.delay -- because not one
# of PAGE-25..PAGE-33 computes or requests a delay. P5-9's no-scheduler SeamError is unreachable
# from here, and the default mode needs no scheduler, no executor and no thread: the driver is a
# callback pump on Future#on_settle, run on the settling thread, which is PAGE-29's stated default.
# Every future here is phase 2's real Completer; every response a real Dexpace::Response.
class DexpacePageAsyncPaginatorTest < DexpaceTestCase
  include PageFixtures

  # A bounded wait: "hangs" is PAGE-32's failure mode, and Future#value's deadline settles the
  # future as cancelled (:deadline_expired) instead of hanging the suite.
  def bounded_value(future, seconds: 5.0)
    future.value(deadline: Dexpace::Clock::SYSTEM.monotonic + seconds)
  end

  def consumed(async, method = :walk)
    seen = []
    future = async.public_send(method, ->(item) { seen << item })
    [future, seen]
  end

  test "PAGE-6 (non-blocking engine): construction is inert; invoking walk fetches immediately" do
    async = async_paginator_over([[1]], deferred: true)

    assert_equal(0, async.transport.calls.size)
    future = async.walk(->(_item) {})

    assert_equal(1, async.transport.calls.size)
    refute_predicate(future, :settled?)
    async.transport.settle_next!

    assert_equal(1, bounded_value(future))
  end

  test "PAGE-6: one exchange per page consumed, and the future settles with the page count" do
    async = async_paginator_over([[1, 2], [3], []])
    future, seen = consumed(async)

    assert_equal(3, bounded_value(future))
    assert_equal([1, 2, 3], seen)
    assert_equal(3, async.transport.calls.size)
  end

  test "PAGE-29: items are delivered one at a time, in server order, never concurrently" do
    seen = []
    depth = 0
    max = 0
    future = async_paginator_over([[1, 2], [3]]).walk(lambda { |item|
      depth += 1
      max = [max, depth].max
      seen << item
      depth -= 1
    })
    bounded_value(future)

    assert_equal([1, 2, 3], seen)
    assert_equal(1, max)
  end

  test "PAGE-29: with an executor, the driver and every consumer invocation run on it" do
    executor = ProbeExecutor.new(mode: :queued)
    threads = []
    async = async_paginator_over([[1], [2]], executor: executor)
    future = async.walk(->(_item) { threads << ::Thread.current })

    assert_equal(0, async.transport.calls.size) # nothing ran yet: the driver is queued
    executor.drain

    assert_equal(2, bounded_value(future))
    assert_operator(executor.posts, :>=, 3) # the first dispatch, then one continuation per page
    assert_equal(2, threads.size)
    assert(threads.all? { |thread| executor.threads.include?(thread) })
    refute_includes(threads, ::Thread.current)
  end

  test "PAGE-1 (async): #walk_pages delivers whole live pages, with status, headers and request" do
    # PAGE-1 is not qualified by engine, and PAGE-27 names the page-level drain in as many words
    # ("after the page is drained to the consumer (item- or page-level)"). Same pump, same
    # exactly-once close -- the only difference is what the consumer is handed.
    seen = []
    future = async_paginator_over([[1, 2], [3]]).walk_pages(lambda { |page|
      url = Dexpace::URL.external_form(page.request.url)
      seen << [page.items, page.status.code, page.closed?, url]
    })

    assert_equal(2, bounded_value(future))
    assert_equal([[[1, 2], 200, false, "https://x/i"], [[3], 200, false, "https://x/i?p=1"]], seen)
  end

  test "PAGE-27 (async, page-level): the page is closed after the consumer returns, exactly once" do
    probes = [fake_response_body, fake_response_body]
    observed = []
    future = async_paginator_over([[1], [2]], bodies: probes).walk_pages(lambda { |_page|
      observed << probes.map(&:closes)
    })
    bounded_value(future)

    assert_equal([[0, 0], [1, 0]], observed) # live while the consumer holds it
    assert_equal([1, 1], probes.map(&:closes))
  end

  # PAGE-25, PAGE-26 and PAGE-33: the abort, the page boundary and the documented race.
  class CancellationTest < DexpaceTestCase
    include PageFixtures

    def bounded_value(future) = future.value(deadline: Dexpace::Clock::SYSTEM.monotonic + 5.0)

    def consumed(async)
      seen = []
      future = async.walk(->(item) { seen << item })
      [future, seen]
    end

    test "PAGE-25: cancelling the result future halts the walk and cancels the in-flight call" do
      async = async_paginator_over([[1]] * 5, deferred: true)
      future = async.walk(->(_item) {})
      in_flight = async.transport.pending.first.first

      future.cancel(:test)

      assert_predicate(future, :cancelled?)
      assert_predicate(in_flight.future, :cancelled?)
      async.transport.settle_next! # the late response meets an already-settled completer

      assert_equal(1, async.transport.calls.size)
    end

    test "PAGE-25: no worker thread blocks per page -- the walk completes on the caller's thread" do
      before = ::Thread.list.size
      future, seen = consumed(async_paginator_over([[1], [2], [3]]))

      assert_equal(3, bounded_value(future))
      assert_equal([1, 2, 3], seen)
      assert_equal(before, ::Thread.list.size)
    end

    test "PAGE-33: a response delivered after the abort is closed by the TRANSPORT's completer" do
      # PAGE-33's first half, as built: Completer#fulfil on an already-cancelled completer returns
      # false and closes the response itself (SEAM-30) -- the response never reaches this engine.
      body = fake_response_body
      async = async_paginator_over([[1]], bodies: [body], deferred: true)
      future = async.walk(->(_item) { flunk("never delivered") })
      future.cancel(:test)

      async.transport.settle_next!

      assert_equal(1, body.closes)
      assert_predicate(future, :cancelled?)
    end

    test "PAGE-26: a page parsed after the walk settled is dropped undrained AND closed, quietly" do
      # PAGE-33's second half and PAGE-26's drop, on THIS engine's path: the cancel lands between
      # the parse and the drain -- here from inside the strategy -- so the built page is staged on
      # an already-settled walk, closed through close_quietly, its close error swallowed, never
      # drained.
      body = fake_response_body(close_error: IOError.new("boom"))
      holder = []
      strategy = Class.new do
        define_method(:parse) do |response, template|
          holder.first.cancel(:mid_parse)
          PageFixtures::ScriptedStrategy.new([[1]]).parse(response, template)
        end
      end.new
      async = async_paginator_over([[1]], bodies: [body], strategy: strategy, deferred: true)
      future = async.walk(->(_item) { flunk("dropped pages are never drained") })
      holder << future
      async.transport.settle_next!

      assert_equal(1, body.closes)
      assert_predicate(future, :cancelled?)
      error = assert_raises(Dexpace::CancelledError) { bounded_value(future) }

      assert_equal(:mid_parse, error.reason) # the cancellation, not the IOError, is the outcome
    end

    test "PAGE-26: a cancel from inside the drain lets the current page finish, then stops" do
      seen = []
      holder = []
      async = async_paginator_over([[1, 2], [3]], deferred: true)
      future = async.walk(lambda { |item|
        seen << item
        holder.first.cancel(:mid_drain) if item == 1
      })
      holder << future
      async.transport.settle_next!

      assert_equal([1, 2], seen) # item 2 still reached the consumer; page 2 was never fetched
      assert_equal(1, async.transport.calls.size)
      assert_predicate(future, :cancelled?)
      assert_equal(:mid_drain, assert_raises(Dexpace::CancelledError) do
        bounded_value(future)
      end.reason,)
    end
  end

  # PAGE-28's failure modes, each completing the future exceptionally with the ORIGINAL cause.
  class FailureTest < DexpaceTestCase
    include PageFixtures

    def bounded_value(future) = future.value(deadline: Dexpace::Clock::SYSTEM.monotonic + 5.0)

    test "PAGE-28: a consumer throw fails the walk with the original cause, unwrapped" do
      cause = KeyError.new("k")
      future = async_paginator_over([[1]]).walk(->(_item) { raise cause })

      error = assert_raises(KeyError) { bounded_value(future) }

      assert_same(cause, error)
    end

    test "PAGE-28: a transport failure settles the walk with the same error object" do
      cause = IOError.new("wire")
      transport = ScriptedAsyncTransport.new([cause])
      future = async_paginator_over([[1]], transport: transport).walk(->(_item) {})

      assert_same(cause, assert_raises(IOError) { bounded_value(future) })
    end

    test "PAGE-28 / PAGE-13: a parse failure fails the walk and closes the response inline" do
      body = fake_response_body
      cause = KeyError.new("parse")
      future = async_paginator_over([[1]], bodies: [body], strategy: raising_strategy(cause))
        .walk(->(_item) {})

      assert_same(cause, assert_raises(KeyError) { bounded_value(future) })
      assert_equal(1, body.closes)
    end

    test "PAGE-28: a transport that eagerly throws is handled as a failed walk" do
      transport = ->(_request, _options, _cancellation) { raise IOError, "eager" }
      future = async_paginator_over([[1]], transport: transport).walk(->(_item) {})

      assert_equal("eager", assert_raises(IOError) { bounded_value(future) }.message)
    end

    test "PAGE-28: a transport that answers a non-future is a failed walk, not a NoMethodError" do
      transport = ->(request, _options, _cancellation) { page_response(request: request) }
      future = async_paginator_over([[1]], transport: transport).walk(->(_item) {})

      assert_raises(Dexpace::InvalidArgumentError) { bounded_value(future) }
    end

    test "PAGE-28: a cancellation settled by the transport is forwarded as a cancellation" do
      transport = ScriptedAsyncTransport.new([->(_r, _o, _c) {}], settle_later: true)
      future = async_paginator_over([[1]], transport: transport).walk(->(_item) {})
      transport.pending.first.first.request_cancel(:upstream)

      assert_predicate(future, :cancelled?)
      assert_equal(:upstream, assert_raises(Dexpace::CancelledError) do
        bounded_value(future)
      end.reason,)
    end

    test "PAGE-28: a null success terminates the walk exceptionally, though Settlement bars it" do
      # Settlement's own validation makes a nil response with a nil error unconstructible, so the
      # arm is driven the only way it can be reached: the private pump handed a duck settlement.
      pump_class = Dexpace::Page::AsyncPaginator.const_get(:Pump)
      pump = pump_class.new(async_paginator_over([[1]]), ->(_item) {}, Dexpace::Cancellation.none,
                            :items,)
      pump.send(:settled, Struct.new(:response, :error).new(nil, nil))

      error = assert_raises(Dexpace::SeamError) do
        bounded_value(pump.instance_variable_get(:@completer).future)
      end

      assert_match(/settled with nothing/, error.message)
    end

    test "PAGE-28 / RECOV-2: a fatal-family consumer error fails the walk AND propagates" do
      body = fake_response_body
      async = async_paginator_over([[1]], bodies: [body])
      fatal = NoMemoryError.new("f")
      future = nil

      raised = assert_raises(NoMemoryError) { future = async.walk(->(_item) { raise fatal }) }

      assert_same(fatal, raised)
      assert_nil(future)
      assert_equal(1, body.closes)
    end

    test "PAGE-32: a throwing close on the SUCCESS path fails the future rather than hanging" do
      body = fake_response_body(close_error: IOError.new("boom"))
      future = async_paginator_over([[1]], bodies: [body]).walk(->(_item) {})

      assert_equal("boom", assert_raises(IOError) { bounded_value(future) }.message)
      assert_equal(1, body.closes)
    end

    test "PAGE-32: a failed consumer's cause stays primary; the close error is swallowed" do
      body = fake_response_body(close_error: IOError.new("close"))
      cause = KeyError.new("consumer")
      future = async_paginator_over([[1]], bodies: [body]).walk(->(_item) { raise cause })

      assert_same(cause, assert_raises(KeyError) { bounded_value(future) })
      assert_empty(Dexpace.suppressed(cause))
      assert_equal(1, body.closes)
    end

    test "PAGE-30: an executor rejecting a re-dispatch fails the walk and closes the staged page" do
      executor = ProbeExecutor.new(mode: :rejecting, after: 2) # post 1: the driver; post 2: page 1
      staged = fake_response_body
      seen = []
      async = async_paginator_over([[1], [2]], bodies: [fake_response_body, staged],
                                               executor: executor,)
      future = async.walk(->(item) { seen << item })

      assert_raises(ProbeExecutor::Rejected) { bounded_value(future) }
      assert_equal([1], seen)
      assert_equal(1, staged.closes)
      assert_equal(2, async.transport.calls.size) # page 2 fetched, then its continuation refused
    end

    test "PAGE-30: an executor that rejects the FIRST dispatch fails the walk with the rejection" do
      executor = ProbeExecutor.new(mode: :rejecting, after: 0)
      async = async_paginator_over([[1]], executor: executor)

      assert_raises(ProbeExecutor::Rejected) { bounded_value(async.walk(->(_item) {})) }
      assert_equal(0, async.transport.calls.size)
    end
  end

  # PAGE-31's trampoline and PAGE-27's exactly-once across the four paths.
  class TrampolineTest < DexpaceTestCase
    include PageFixtures

    def bounded_value(future) = future.value(deadline: Dexpace::Clock::SYSTEM.monotonic + 30.0)

    test "PAGE-31: thousands of synchronously-completed pages, no stack growth, both paths" do
      # Measured through the real Completer: a pump that re-enters itself from inside on_settle
      # overflows at ~2,600 pages on every interpreter; the re-arm loop is flat.
      pages = Array.new(3_000) { [1] }
      sampled = [1, 3_000]
      [nil, InlineExecutor.new].each do |executor|
        depths = []
        count = 0
        future = async_paginator_over(pages, executor: executor).walk(lambda { |_item|
          count += 1
          depths << caller.size if sampled.include?(count)
        })

        assert_equal(3_000, bounded_value(future))
        assert_equal(3_000, count)
        assert_equal(depths.first, depths.last, "the stack grew between page 1 and page 3,000")
      end
    end

    test "PAGE-27: each page's response closes exactly once on all four paths" do
      normal = [fake_response_body, fake_response_body]
      bounded_value(async_paginator_over([[1], [2]], bodies: normal).walk(->(_item) {}))

      parse = fake_response_body
      failing = async_paginator_over([[1]], bodies: [parse],
                                            strategy: raising_strategy(KeyError.new("p")),)
      assert_raises(KeyError) { bounded_value(failing.walk(->(_item) {})) }

      cancelled = fake_response_body
      holder = []
      mid = Class.new do
        define_method(:parse) do |response, template|
          holder.first.cancel(:c)
          PageFixtures::ScriptedStrategy.new([[1]]).parse(response, template)
        end
      end.new
      deferred = async_paginator_over([[1]], bodies: [cancelled], strategy: mid, deferred: true)
      holder << deferred.walk(->(_item) {})
      deferred.transport.settle_next!

      rejected = fake_response_body
      executor = ProbeExecutor.new(mode: :rejecting, after: 2)
      refused = async_paginator_over([[1], [2]], bodies: [fake_response_body, rejected],
                                                 executor: executor,)
      assert_raises(ProbeExecutor::Rejected) { bounded_value(refused.walk(->(_item) {})) }

      assert_equal([1, 1, 1, 1, 1],
                   [*normal.map(&:closes), parse.closes, cancelled.closes, rejected.closes],)
    end
  end

  # Construction and the token bridge.
  class ConstructionTest < DexpaceTestCase
    include PageFixtures

    def bounded_value(future) = future.value(deadline: Dexpace::Clock::SYSTEM.monotonic + 5.0)

    test "HTTP-4: the executor is nil or answers #post; the consumer must be callable" do
      assert_raises(Dexpace::InvalidArgumentError) { async_paginator_over([[1]], executor: :pool) }
      assert_raises(Dexpace::InvalidArgumentError) { async_paginator_over([[1]], cap: 0) }
      async = async_paginator_over([[1]])

      assert_raises(Dexpace::InvalidArgumentError) { async.walk(nil) }
      assert_raises(Dexpace::InvalidArgumentError) { async.walk_pages(:consumer) }
      assert_raises(Dexpace::InvalidArgumentError) { async.walk(->(_i) {}, cancellation: :token) }
      refute_respond_to(Dexpace::Page::AsyncPaginator, :new)
      assert_predicate(async, :frozen?)
      assert_nil(async.executor)
    end

    test "HTTP-4 / P7-107: the engine's own shape checks name what arrived, by class" do
      refusals = [
        [{ transport: :none }, /transport must respond to #call, got Symbol/],
        [{ template: "https://x/i" }, /template must be a Dexpace::Request, got String/],
        [{ strategy: :cursor }, /strategy must respond to #parse, got Symbol/],
        [{ options: {} }, /options must be a Dexpace::RequestOptions, got Hash/],
      ]
      refusals.each do |overrides, pattern|
        error = assert_raises(Dexpace::InvalidArgumentError) do
          async_paginator_over([[1]], **overrides)
        end

        assert_match(pattern, error.message)
      end
    end

    test "a caller's cancellation token aborts the walk and cancels the in-flight exchange" do
      source = Dexpace::Cancellation.source
      async = async_paginator_over([[1]] * 3, deferred: true)
      future = async.walk(->(_item) {}, cancellation: source.token)

      assert_same(source.token, async.transport.calls.first.last)
      source.cancel(:caller)

      assert_predicate(future, :cancelled?)
      assert_predicate(async.transport.pending.first.first.future, :cancelled?)
      assert_equal(:caller, assert_raises(Dexpace::CancelledError) { bounded_value(future) }.reason)
    end

    test "the token subscription detaches when the walk settles; a long token holds nothing" do
      source = Dexpace::Cancellation.source
      async = async_paginator_over([[1]])

      assert_equal(1, bounded_value(async.walk(->(_item) {}, cancellation: source.token)))
      assert_equal(0, source.instance_variable_get(:@hooks).size)
    end

    test "PAGE-36 / PAGE-9: the options reach every exchange; the cap bounds the async walk too" do
      options = Dexpace::RequestOptions.builder.tap { |b| b.timeout = 2.0 }.build
      transport = ScriptedAsyncTransport.new(page_script(20))
      async = async_paginator_over([], transport: transport, strategy: EndlessStrategy.new, cap: 3,
                                       options: options,)

      assert_equal(3, bounded_value(async.walk(->(_item) {})))
      assert_equal(3, transport.calls.size)
      transport.calls.each { |(_request, opts, _cancellation)| assert_same(options, opts) }
    end

    test "R9: the engine calls no wait -- no Clock#sleep, no Async.delay -- and no scheduler" do
      path = File.expand_path("../../../lib/dexpace/page/async_paginator.rb", __dir__)
      code = File.readlines(path).reject { |line| line.lstrip.start_with?("#") }.join

      refute_match(/Async\.delay|\.sleep|Fiber\.scheduler|Fiber\.set_scheduler|Thread\.new/, code)
    end
  end
end
