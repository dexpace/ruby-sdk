# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace/async/thread"

# Proves Pool#post satisfies Dexpace::Page::_Executor AS 7c's code uses it, not as respond_to?
# reports it -- the interface is core-declared, nested in `class Page` in
# gems/dexpace-core/sig/dexpace/page.rbs (7c's correction, P7-106), and 8b did not write it
# (NFR-3/NFR-11's surface this gem inherits). The real executor mode posts the FIRST dispatch
# through the executor too (7c's P7-112), so the pool is where the whole walk runs, consumer
# included -- which is what the thread assertion below pins, because `future.settled?` alone
# passes with the executor ignored.
class PageExecutorTest < DexpaceTestCase
  Pool = Dexpace::Async::Thread::Pool

  def teardown
    @pool&.close
    super
  end

  # A stateless _Strategy over a page counter: two pages, then the terminal Info.
  class TwoPageStrategy
    def initialize
      @seen = 0
      @mutex = ::Thread::Mutex.new
    end

    def parse(_response, template)
      page = @mutex.synchronize { @seen += 1 }
      case page
      when 1 then Dexpace::Page::Info.build(items: [1, 2], next_request: template)
      else Dexpace::Page::Info.terminal(items: [3])
      end
    end
  end

  def template
    Dexpace::Request.build(method: :get, url: "https://example.test/items",
                           headers: Dexpace::Headers::EMPTY,)
  end

  def response_for(request)
    Dexpace::Response.build(request: request, protocol: "HTTP/1.1", status: 200,
                            headers: Dexpace::Headers::EMPTY_INBOUND,)
  end

  test "AsyncPaginator walks two pages with the pool as executor; the consumer runs on a worker" do
    @pool = Pool.build(size: 2, name: "paging")
    calls = ::Thread::Queue.new
    fake = lambda do |request, _options, _cancellation|
      calls << ::Thread.current.name
      response_for(request)
    end
    items = ::Thread::Queue.new
    consumer_threads = ::Thread::Queue.new

    paginator = Dexpace::Page::AsyncPaginator.build(
      # The paginator's transport must answer a Dexpace::Async::Future, so the sync double is
      # bridged -- over an INLINE executor, not the pool, so the only thread that can carry the
      # consumer onto a pool worker is the paginator's own executor:. Bridged over the pool as
      # well, `executor: nil` would still show the consumer on a worker (the settlement's), and
      # the assertion would prove nothing about the executor mode.
      transport: Dexpace::Transport.async_over(fake, executor: InlineExecutor.new),
      template: template,
      strategy: TwoPageStrategy.new,
      executor: @pool,
    )
    future = paginator.walk(lambda do |item|
      consumer_threads << ::Thread.current.name
      items << item
    end)
    pages = future.value(deadline: Dexpace::Clock.deadline_in(5))

    assert_equal(2, pages, "the walk settles with the page count, never nil (P7-109)")
    assert_equal([1, 2, 3], Array.new(3) { items.pop(timeout: 1) })
    assert_equal(2, calls.size)
    workers = Array.new(3) { consumer_threads.pop(timeout: 1) }

    assert(workers.all? { |name| name.to_s.start_with?("paging worker ") },
           "the consumer ran off the pool: #{workers.inspect}",)
    assert(Array.new(2) { calls.pop }.all? { |name| name.to_s.start_with?("paging worker ") },
           "the bridged transport ran on the executor's worker, which posted the dispatch",)
  end

  # Runs the block on the calling thread: the bridge's executor here, so nothing but the
  # paginator's executor: can move work onto a pool worker.
  class InlineExecutor
    def post = yield
  end

  test "#post is _Executor's signature exactly: one zero-arity block, nothing else" do
    @pool = Pool.build(size: 1)
    post = @pool.method(:post)

    assert_equal([%i[block block]], post.parameters)
    assert_equal(0, post.arity)
    assert_nil(@pool.post { nil })
    assert_equal(1, Dexpace::Async::Thread::Pool.public_instance_methods(false).count do |m|
      m == :post
    end,)
    assert_raises(::ArgumentError) { @pool.post(:extra) { nil } }
  end
end
