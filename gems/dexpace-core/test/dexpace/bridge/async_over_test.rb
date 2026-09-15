# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_transport"
require_relative "../../support/inline_executor"
require "dexpace"

# SEAM-18's sync-to-async half, and the one place in phase 2 where core itself can produce a
# response no caller will take delivery of -- which is where SEAM-30 is exercised rather than
# merely stated.
class DexpaceBridgeAsyncOverTest < DexpaceTestCase
  # A closeable response that counts its closes, so SEAM-30's orphan close is observable.
  class FakeResponse
    include Dexpace::Closeable

    attr_reader :closes

    def initialize
      @closes = 0
      initialize_closeable(owned: true)
    end

    private

    def release
      @closes += 1
    end
  end

  test "delivers the response and threads the exact options and token through" do
    response = FakeResponse.new
    sync = FakeTransport.new(response: response)
    async = Dexpace::Transport.async_over(sync, executor: InlineExecutor.new)
    options = Dexpace::RequestOptions::EMPTY
    token = Dexpace::Cancellation.none

    future = async.call(:request, options, token)

    assert_same(response, future.value)
    assert_same(options, sync.calls.first[1], "SEAM-18: per-call options are threaded, not dropped")
    assert_same(token, sync.calls.first[2])
    assert_equal(0, response.closes, "a delivered response is the caller's to close")
  end

  test "routes a synchronous raise from the wrapped transport to the failure channel" do
    boom = ::IOError.new("connection reset")
    async = Dexpace::Transport.async_over(
      FakeTransport.new(raises: boom), executor: InlineExecutor.new,
    )

    future = async.call(:request, nil, nil)

    caught = assert_raises(::IOError) { future.value }
    assert_same(boom, caught, "ASYNC-2 / PIPE-30: normalised to the failure channel, not wrapped")
  end

  test "closes the orphaned response when cancellation wins the completion race" do
    response = FakeResponse.new
    source = Dexpace::Cancellation.source
    sync = FakeTransport.new(response: response, before_return: -> { source.cancel(:gave_up) })
    async = Dexpace::Transport.async_over(sync, executor: InlineExecutor.new)

    future = async.call(:request, nil, source.token)

    assert_raises(Dexpace::CancelledError) { future.value }
    assert_equal(1, response.closes,
                 "SEAM-30: check-after-resume closes a response no caller receives",)
  end

  # Both transport seams share one .conforms? -- Dexpace::Registry.callable?(object, arity: 3) --
  # and #parameters cannot see a return type, so an async transport is accepted at construction.
  # Without #deliver's guard the outer future delivers the INNER future, nothing raises anywhere,
  # and the real response is never closed. Phase 4c's Pipeline/AsyncPipeline pair is what makes it
  # cheap to hit; the finding is 4c's plan's, routed to this task.
  test "an async transport handed to async_over raises at the first send" do
    inner = Dexpace::Async::Completer.new
    async = Dexpace::Transport.async_over(
      ->(_request, _options, _cancellation) { inner.future }, executor: InlineExecutor.new,
    )

    future = async.call(:request, nil, nil)

    error = assert_raises(Dexpace::SeamError) { future.value }
    assert_match(/SYNCHRONOUS transport/, error.message)
    assert_match(/Dexpace::Async::Future/, error.message, "the message names the class it got")
  end

  # Check-before-dispatch. ASYNC-3's third clause holds without it -- nothing here is ever
  # interrupted -- and SEAM-30 closes the orphan either way. What it saves is one round trip and,
  # on a non-idempotent method, one server-side side effect a caller believed they had cancelled.
  # It belongs to core because the pool posts an opaque block and cannot see the token.
  test "a token cancelled before the block runs never reaches the transport at all" do
    source = Dexpace::Cancellation.source
    source.cancel(:gave_up)
    sync = FakeTransport.new(response: :ok)
    async = Dexpace::Transport.async_over(sync, executor: InlineExecutor.new)

    future = async.call(:request, nil, source.token)

    error = assert_raises(Dexpace::CancelledError) { future.value }
    assert_equal(:gave_up, error.reason)
    assert_empty(sync.calls, "check-before-dispatch: the send was never made")
  end

  test "the bridge's product conforms to the async seam" do
    async = Dexpace::Transport.async_over(FakeTransport.new, executor: InlineExecutor.new)

    assert(Dexpace::AsyncTransport.conforms?(async))
  end

  # ASYNC-2 and PIPE-30 want one normalisation: a caller of an async seam never has to rescue
  # around #call. A shut-down pool raising from #post is the same class of failure as the wrapped
  # transport raising, and goes to the same channel.
  test "a raise from the executor itself settles the future rather than escaping" do
    exploding = Class.new do
      def post = raise(::IOError, "the pool is shut down")
    end.new
    async = Dexpace::Transport.async_over(FakeTransport.new(response: :ok), executor: exploding)

    future = async.call(:request, nil, nil)

    error = assert_raises(::IOError) { future.value }
    assert_equal("the pool is shut down", error.message)
  end

  # deliver's delivery branch must sit INSIDE its rescue. Written as a method-level `else` it does
  # not, so anything raised between the send returning and the future settling escapes the posted
  # block -- and under a real threaded executor that kills the worker and leaves the future
  # permanently unsettled. InlineExecutor masks it, because #call's own rescue catches what
  # escapes; this test supplies a threaded executor so it cannot. The raise is a real one: a
  # transport returning nil trips Settlement's "exactly one of response or error" rule inside
  # Completer#fulfil, which is SEAM-16's "MUST NOT complete successfully with a null value" --
  # so a nil response is a failure delivered through the failure channel, never a future that
  # nobody can wait on.
  test "a raise after the send but before the settle still settles the future" do
    threaded = Class.new do
      attr_reader :workers

      def initialize = @workers = []

      def post(&block) = @workers << ::Thread.new(&block)
    end.new
    async = Dexpace::Transport.async_over(FakeTransport.new(response: nil), executor: threaded)

    future = async.call(:request, nil, nil)

    settled = ::Thread.new { future.wait }

    assert(settled.join(5), "ASYNC-2/PIPE-30: the future never settled and #value would block")
    assert_raises(Dexpace::InvalidArgumentError) { future.value }
    threaded.workers.each(&:join)
  end

  test "the bridge is closeable, owns nothing, and leaves the wrapped transport usable" do
    transport = FakeTransport.new(response: :ok)
    async = Dexpace::Transport.async_over(transport, executor: InlineExecutor.new)

    refute_predicate(async, :owned?, "SEAM-14 / XCUT-22: transport and executor are the caller's")
    assert_nil(async.close)
    assert_predicate(async, :closed?)
    assert_nil(async.close, "SEAM-14: close is idempotent")
    assert_equal(:ok, async.call(:request, nil, nil).value,
                 "close released nothing, because the bridge created nothing",)
  end
end
