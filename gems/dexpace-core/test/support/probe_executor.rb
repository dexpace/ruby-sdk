# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The two executor shapes PAGE-29 and PAGE-30 need beyond phase 2's InlineExecutor: a QUEUED
# executor that records every posted block and runs the queue on a fresh ::Thread it joins
# (`#drain`), so "the consumer ran on the executor's thread" is an assertion about a thread that
# is not the test's and cannot pass vacuously; and a REJECTING executor that runs the first
# `after` posts inline and raises ProbeExecutor::Rejected on the next -- the one rejection
# vocabulary Ruby offers, since there is no RejectedExecutionException to catch by type.
#
# #drain loops until the queue is empty rather than over a snapshot, because a block it runs
# may post the next page's continuation while it is still draining (the pump re-arms from
# inside the settlement it handles), and it joins the thread before returning, which is what
# keeps DexpaceTestCase's thread-count teardown green.
class ProbeExecutor
  # The rejection a `:rejecting` executor raises from #post once its budget is spent.
  class Rejected < StandardError; end

  attr_reader :posts, :threads

  def initialize(mode: :queued, after: nil)
    unless %i[queued rejecting].include?(mode)
      raise ArgumentError, "mode must be :queued or :rejecting"
    end

    @mode = mode
    @after = after
    @posts = 0
    @queue = []
    @threads = []
    @mutex = ::Thread::Mutex.new
  end

  def post(&block)
    @mutex.synchronize { @posts += 1 }
    if @mode == :queued
      @mutex.synchronize { @queue << block }
    else
      raise Rejected, "ProbeExecutor rejected post ##{@posts} (after #{@after})" if @posts > @after

      yield
    end
    nil
  end

  # Runs every queued block, in order, on one fresh thread, then joins it; nil.
  def drain
    thread = ::Thread.new do
      @mutex.synchronize { @threads << ::Thread.current }
      while (block = @mutex.synchronize { @queue.shift })
        block.call
      end
    end
    thread.join
    nil
  end

  def pending = @mutex.synchronize { @queue.size }
end
