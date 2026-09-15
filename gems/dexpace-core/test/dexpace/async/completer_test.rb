# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SEAM-16, SEAM-17, SEAM-30. The state lives on the Completer and the Future is a facade over it,
# because Ruby has no package-private visibility and the alternative is a cross-object `send`.
# Two classes because Metrics/ClassLength caps one at 100 lines: settlement and SEAM-30 here,
# cancellation and the callback lists in Hooks.
class DexpaceAsyncCompleterTest < DexpaceTestCase
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

  def completer = Dexpace::Async::Completer.new

  test "a fulfilled future delivers the response and never closes it" do
    subject = completer
    response = FakeResponse.new

    assert(subject.fulfil(response))

    assert_same(response, subject.future.value)
    assert_equal(0, response.closes, "SEAM-16: a delivered response is the caller's to close")
  end

  test "a failed future re-raises the identical exception object" do
    subject = completer
    boom = ::IOError.new("connection reset")

    assert(subject.fail(boom))

    caught = assert_raises(::IOError) { subject.future.value }
    assert_same(boom, caught, "SEAM-18: there is no wrapper to unwrap")
  end

  test "fulfil that loses the race closes the orphan exactly once" do
    subject = completer

    assert(subject.fail(::IOError.new("already gone")))
    orphan = FakeResponse.new

    refute(subject.fulfil(orphan))

    assert_equal(1, orphan.closes, "SEAM-30: the caller-closes rule cannot apply to a value no " \
                                   "caller receives",)
  end

  test "cancelling after settlement does not close the delivered response" do
    subject = completer
    response = FakeResponse.new
    subject.fulfil(response)

    subject.future.cancel(:too_late)

    assert_equal(0, response.closes, "SEAM-16's last clause, and ASYNC-20")
    refute_predicate(subject.future, :cancelled?)
    assert_same(response, subject.future.value)
  end

  test "cancelling before settlement settles as cancelled and raises with the reason" do
    subject = completer

    subject.future.cancel(:stop)

    assert_predicate(subject.future, :settled?)
    assert_predicate(subject.future, :cancelled?)
    error = assert_raises(Dexpace::CancelledError) { subject.future.value }
    assert_equal(:stop, error.reason)
  end

  test "concurrent settles elect exactly one winner" do
    subject = completer
    wins = ::Queue.new

    Array.new(16) { |i| ::Thread.new { wins << i if subject.fail(::IOError.new(i.to_s)) } }
      .each(&:join)

    assert_equal(1, wins.size)
  end

  test "fail refuses anything that is not an exception" do
    assert_raises(Dexpace::InvalidArgumentError) { completer.fail(:not_an_exception) }
  end

  test "outcome is nil until settled, then the settlement" do
    subject = completer

    assert_nil(subject.outcome)
    refute_predicate(subject, :settled?)
    subject.fulfil(:value)

    assert_equal(Dexpace::Async::Settlement.success(:value), subject.outcome)
  end

  test "future is memoised and on_settle and on_cancel require a block" do
    subject = completer

    assert_same(subject.future, subject.future)
    assert_raises(Dexpace::InvalidArgumentError) { subject.on_settle }
    assert_raises(Dexpace::InvalidArgumentError) { subject.on_cancel }
  end

  test "request_cancel after settlement is a no-op that reports false" do
    subject = completer
    subject.fulfil(:value)

    refute(subject.request_cancel(:late))
  end

  # Cancellation, the abort hooks and the settle callbacks.
  class Hooks < DexpaceTestCase
    def completer = Dexpace::Async::Completer.new

    test "on_cancel gives the producer a hook to abort promptly" do
      subject = completer
      seen = []
      subject.on_cancel { |reason| seen << reason }

      subject.future.cancel(:abort)

      assert_equal([:abort], seen)
    end

    test "on_cancel registered after a cancellation fires at once, and after a settle never" do
      cancelled = completer
      cancelled.future.cancel(:gone)
      seen = []

      cancelled.on_cancel { |reason| seen << reason }

      assert_equal([:gone], seen)

      settled = completer
      settled.fulfil(FakeResponse.new)

      settled.on_cancel { flunk("a settled future has no cancellation to report") }
    end

    # The outcome is published BEFORE the cancel hooks run. Notify-then-settle leaves the future
    # permanently unsettled when one hook raises, so every #value on it blocks forever -- the same
    # failure Bridge::AsyncOver#deliver's rescue closes, reached through the public API alone. The
    # join timeout is the assertion: without it the suite hangs instead of failing.
    test "a raising cancel hook still leaves the future settled and every waiter unblocked" do
      subject = completer
      subject.on_cancel { raise ::IOError, "the producer's abort hook blew up" }

      assert_raises(::IOError) { subject.future.cancel(:stop) }

      assert_predicate(subject, :settled?, "cancellation must always publish an outcome")
      assert_predicate(subject.future, :cancelled?)
      waiter = ::Thread.new do
        subject.future.value
      rescue Dexpace::CancelledError => error
        error
      end

      assert(waiter.join(5), "the future never settled and #value would block forever")
      assert_equal(:stop, waiter.value.reason)
    end

    test "one raising settle callback does not drop the callbacks registered after it" do
      subject = completer
      seen = []
      subject.on_settle { seen << :first }
      subject.on_settle { raise ::IOError, "a settle callback blew up" }
      subject.on_settle { seen << :third }

      assert_raises(::IOError) { subject.fulfil(FakeResponse.new) }

      assert_equal(%i[first third], seen)
      assert_predicate(subject, :settled?)
    end

    test "on_settle runs once whether registered before or after settlement" do
      subject = completer
      seen = []
      subject.future.on_settle { |settlement| seen << [:before, settlement.success?] }

      subject.fulfil(FakeResponse.new)
      subject.future.on_settle { |settlement| seen << [:after, settlement.success?] }

      assert_equal([[:before, true], [:after, true]], seen)
    end
  end
end
