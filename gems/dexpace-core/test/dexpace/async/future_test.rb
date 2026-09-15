# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SEAM-16, SEAM-18's interruption clause. #value blocks on a Thread::Queue pop rather than a spin
# or a Kernel#sleep poll, which is what makes the pivot scheduler-transparent (Task 6 proves it).
class DexpaceAsyncFutureTest < DexpaceTestCase
  test "value blocks until another thread settles, rather than spinning" do
    completer = Dexpace::Async::Completer.new
    response = Object.new
    producer = ::Thread.new do
      sleep(0.05)
      completer.fulfil(response)
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    assert_same(response, completer.future.value)

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator(elapsed, :>=, 0.04, "the waiter really blocked")
    producer.join
  end

  test "value honours a cancellation token and settles the future as cancelled" do
    completer = Dexpace::Async::Completer.new
    source = Dexpace::Cancellation.source
    canceller = ::Thread.new do
      sleep(0.02)
      source.cancel(:caller_gave_up)
    end

    error = assert_raises(Dexpace::CancelledError) do
      completer.future.value(cancellation: source.token)
    end

    assert_equal(:caller_gave_up, error.reason)
    assert_predicate(completer.future, :cancelled?)
    canceller.join
  end

  test "value on an already-cancelled token settles at once without waiting" do
    completer = Dexpace::Async::Completer.new
    source = Dexpace::Cancellation.source
    source.cancel(:already)

    error = assert_raises(Dexpace::CancelledError) do
      completer.future.value(cancellation: source.token)
    end

    assert_equal(:already, error.reason)
  end

  test "wait returns self and never raises the failure" do
    completer = Dexpace::Async::Completer.new
    completer.fail(::IOError.new("boom"))

    future = completer.future

    assert_same(future, future.wait)
    assert_predicate(future, :settled?)
  end

  test "the none token is accepted and arms nothing" do
    completer = Dexpace::Async::Completer.new
    completer.fulfil(:ok)

    assert_equal(:ok, completer.future.value(cancellation: Dexpace::Cancellation.none))
  end

  test "a non-token cancellation is a caller mistake, not a NoMethodError from inside the pivot" do
    completer = Dexpace::Async::Completer.new

    error = assert_raises(Dexpace::InvalidArgumentError) do
      completer.future.value(cancellation: :not_a_token)
    end

    assert_match(/Dexpace::Cancellation/, error.message)
  end

  test "a future refuses to be built over anything but a completer" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Async::Future.new(Object.new) }

    assert_match(/Completer/, error.message)
  end

  test "settled? and cancelled? are public; the completer is not exposed" do
    future = Dexpace::Async::Completer.new.future

    assert_respond_to(future, :settled?)
    assert_respond_to(future, :cancelled?)
    refute_respond_to(future, :completer)
  end

  # #then: the one combinator on the read side (design P2-11).
  class Then < DexpaceTestCase
    # A closeable value, so SEAM-30's orphan close is observable on a mapped value.
    class Mapped
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

    test "then derives a future settled with the block's result" do
      completer = Dexpace::Async::Completer.new
      derived = completer.future.then { |response| "mapped #{response}" }

      completer.fulfil("ok")

      assert_equal("mapped ok", derived.value)
    end

    test "then maps a future that had already settled" do
      completer = Dexpace::Async::Completer.new
      completer.fulfil(2)

      assert_equal(4, completer.future.then { |value| value * 2 }.value)
    end

    test "then forwards the failure unchanged, as the same object" do
      boom = ::IOError.new("reset")
      completer = Dexpace::Async::Completer.new
      derived = completer.future.then { |_value| flunk("the block must not run on a failure") }

      completer.fail(boom)

      assert_same(boom, assert_raises(::IOError) { derived.value })
    end

    test "then forwards cancellation as cancellation, not as a plain failure" do
      completer = Dexpace::Async::Completer.new
      derived = completer.future.then { |_value| flunk("the block must not run on a cancellation") }

      completer.future.cancel(:caller_gave_up)

      error = assert_raises(Dexpace::CancelledError) { derived.value }
      assert_equal(:caller_gave_up, error.reason)
      assert_predicate(derived, :cancelled?, "a derived future that lost its source is cancelled")
    end

    test "cancelling the derived future cancels the one it was derived from" do
      completer = Dexpace::Async::Completer.new
      derived = completer.future.then { |value| value }

      derived.cancel(:downstream_gave_up)

      assert_predicate(completer.future, :cancelled?, "SEAM-18's bidirectional cancellation")
      assert_equal(:downstream_gave_up, completer.outcome.error.reason)
      assert_predicate(derived, :cancelled?)
    end

    test "a raising block fails the derived future rather than escaping the settling thread" do
      completer = Dexpace::Async::Completer.new
      derived = completer.future.then { |_value| raise(::ArgumentError, "bad map") }

      completer.fulfil(:source)

      assert_equal("bad map", assert_raises(::ArgumentError) { derived.value }.message)
      assert_predicate(completer.future, :settled?, "the source future still settled successfully")
    end

    # SEAM-30 reaches a mapped value because #then settles through Completer#fulfil. The race is
    # made deterministic by cancelling the derived future from inside the mapping block: the block
    # still returns its value, and #fulfil then loses to the cancellation and closes it.
    test "a mapped value that loses the completion race is closed, not leaked" do
      completer = Dexpace::Async::Completer.new
      mapped = Mapped.new
      derived = completer.future.then do |_value|
        derived.cancel(:changed_my_mind)
        mapped
      end

      completer.fulfil(:source)

      assert_predicate(derived, :cancelled?)
      assert_equal(1, mapped.closes)
    end

    test "then requires a block" do
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Async::Completer.new.future.then }
    end
  end
end
