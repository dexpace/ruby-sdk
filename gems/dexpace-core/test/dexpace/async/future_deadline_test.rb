# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/fake_clock"

# The pivot's deadline: keyword phase 2 postponed to phase 5 (P2-5), landed as a timed gate pop
# inside Completer#await ending in request_cancel(:deadline_expired); CFG-19's
# satisfied-by-construction unwrap (P5-11); and CFG-20's three met clauses.
module FutureDeadlineTest
  # The expired branch is the only one a fake clock can drive: no fake makes a real Thread::Queue
  # wake early, which is the same limit CFG-15's suite records.
  class ExpiryTest < DexpaceTestCase
    test "deadline: an expired deadline cancels the future, and #value raises that cancellation" do
      clock = FakeClock.new(monotonic: 100.0)
      completer = Dexpace::Async::Completer.new
      future = completer.future

      error = assert_raises(Dexpace::CancelledError) { future.value(deadline: 90.0, clock: clock) }

      # A Symbol, not a sentence: XCUT-2 forbids telling a deadline from a cancel by string match.
      assert_equal(:deadline_expired, error.reason)
      assert_predicate(future, :cancelled?)
      assert_predicate(completer, :settled?)
    end

    test "deadline: #wait still settles-or-returns, and never raises, on an expired deadline" do
      clock = FakeClock.new(monotonic: 100.0)
      future = Dexpace::Async::Completer.new.future

      assert_same(future, future.wait(deadline: 90.0, clock: clock))
      assert_predicate(future, :cancelled?)
    end

    test "deadline: #await keeps its positional token and keeps returning self (NFR-4)" do
      clock = FakeClock.new(monotonic: 100.0)
      completer = Dexpace::Async::Completer.new

      assert_same(completer, completer.await(nil, deadline: 90.0, clock: clock))
      assert_predicate(completer.future, :cancelled?)
    end

    # The expiry cancels through phase 2's own request_cancel, so the producer's abort hook fires
    # and SEAM-30's lost-race close applies to whatever it later delivers.
    test "deadline: expiry runs the producer's on_cancel hook and closes a late response" do
      clock = FakeClock.new(monotonic: 100.0)
      completer = Dexpace::Async::Completer.new
      reasons = []
      completer.on_cancel { |reason| reasons << reason }
      resource = Struct.new(:closes) do
        def close = self.closes += 1
      end.new(0)

      completer.future.wait(deadline: 99.0, clock: clock)

      assert_equal([:deadline_expired], reasons)
      refute(completer.fulfil(resource))
      assert_equal(1, resource.closes)
    end

    test "deadline: a deadline exactly now is already expired (remaining <= 0)" do
      clock = FakeClock.new(monotonic: 100.0)
      future = Dexpace::Async::Completer.new.future

      future.wait(deadline: 100.0, clock: clock)

      assert_predicate(future, :cancelled?)
    end

    # The guard that runs red if the expiry raises a bare timeout instead of cancelling the
    # future: a settled future is what makes the producer stop, and #cancelled? is how a caller
    # and RETRY's classification see it.
    test "deadline: an expired deadline settles the completer; it does not merely raise" do
      clock = FakeClock.new(monotonic: 100.0)
      completer = Dexpace::Async::Completer.new

      completer.await(nil, deadline: 50.0, clock: clock)

      assert_predicate(completer, :settled?)
      assert(completer.outcome.cancelled)
      assert_kind_of(Dexpace::CancelledError, completer.outcome.error)
      refute(completer.fulfil(:late)) # the settlement is published; a later fulfil loses
    end
  end

  # The branches where the deadline does not fire.
  class NonExpiryTest < DexpaceTestCase
    test "deadline: a future settled before the deadline delivers its value untouched" do
      clock = FakeClock.new(monotonic: 100.0)
      completer = Dexpace::Async::Completer.new
      completer.fulfil(:done)

      future = completer.future

      assert_same(future, future.wait(deadline: 150.0, clock: clock))
      assert_equal(:done, future.value(deadline: 150.0, clock: clock))
      refute_predicate(future, :cancelled?)
    end

    test "deadline: an already-settled future ignores an expired deadline" do
      clock = FakeClock.new(monotonic: 100.0)
      completer = Dexpace::Async::Completer.new
      completer.fulfil(:done)

      assert_equal(:done, completer.future.value(deadline: 1.0, clock: clock))
      refute_predicate(completer.future, :cancelled?)
    end

    # The deadline bounds the TOTAL wait: `remaining` is recomputed from the clock on every
    # iteration, so a spurious wake cannot extend it. Driven with the real clock and a real
    # producer thread, which is the only way a not-yet-expired deadline can be exercised.
    test "deadline: a producer that settles before a real deadline wins, and the wait ends then" do
      completer = Dexpace::Async::Completer.new
      producer = Thread.new do
        sleep(0.02)
        completer.fulfil(:in_time)
      end
      deadline = Dexpace::Clock.deadline_in(5.0)
      start = Dexpace::Clock::SYSTEM.monotonic

      assert_equal(:in_time, completer.future.value(deadline: deadline))
      assert_operator(Dexpace::Clock::SYSTEM.monotonic - start, :<, 4.0)

      producer.join
    end

    test "deadline: a real deadline that passes while waiting cancels with :deadline_expired" do
      completer = Dexpace::Async::Completer.new
      deadline = Dexpace::Clock.deadline_in(0.03)
      start = Dexpace::Clock::SYSTEM.monotonic

      error = assert_raises(Dexpace::CancelledError) { completer.future.value(deadline: deadline) }
      elapsed = Dexpace::Clock::SYSTEM.monotonic - start

      assert_equal(:deadline_expired, error.reason)
      assert_operator(elapsed, :>=, 0.03)
      assert_operator(elapsed, :<, 5.0)
    end

    test "deadline: a cancellation token during a deadline wait wins with its own reason" do
      completer = Dexpace::Async::Completer.new
      source = Dexpace::Cancellation.source
      source.cancel(:caller)

      error = assert_raises(Dexpace::CancelledError) do
        completer.future.value(cancellation: source.token, deadline: Dexpace::Clock.deadline_in(5.0))
      end

      assert_equal(:caller, error.reason)
    end

    test "deadline: no deadline is phase 2's wait, unchanged" do
      completer = Dexpace::Async::Completer.new
      completer.fulfil(:v)

      assert_equal(:v, completer.future.value)
      assert_equal(:v, completer.future.value(deadline: nil))
      assert_equal(:v, completer.future.value(deadline: nil, clock: FakeClock.new))
    end

    test "deadline: the keyword refuses a non-numeric deadline and a clock without #monotonic" do
      completer = Dexpace::Async::Completer.new

      assert_raises(Dexpace::InvalidArgumentError) { completer.future.wait(deadline: "soon") }
      assert_raises(Dexpace::InvalidArgumentError) { completer.future.wait(deadline: 1.0, clock: :c) }
      assert_raises(Dexpace::InvalidArgumentError) { completer.await(nil, deadline: :now) }
    end
  end

  # CFG-19 and CFG-20's met clauses.
  class UnwrapTest < DexpaceTestCase
    # assert_same, not assert_kind_of: the whole observable content of "a non-wrapper throwable
    # MUST be returned unchanged" in a port with no wrapper, and a kind check would pass against
    # an implementation that rewrapped (P5-11).
    test "CFG-19: a failure surfaces as the identical object, with no completion wrapper" do
      completer = Dexpace::Async::Completer.new
      original = RuntimeError.new("underlying root error")
      completer.fail(original)

      error = assert_raises(RuntimeError) { completer.future.value }

      assert_same(original, error)
      assert_nil(error.cause)
    end

    test "CFG-19: the failure is the identical object through #then and through a deadline wait" do
      completer = Dexpace::Async::Completer.new
      original = IOError.new("root")
      derived = completer.future.then { |value| value }
      completer.fail(original)

      assert_same(original, assert_raises(IOError) { derived.value })
      assert_same(original, assert_raises(IOError) { completer.future.value(deadline: 1e12) })
    end

    test "CFG-19 / P5-11: no unwrap method ships, and Dexpace.each_cause is the one cause walk" do
      refute_respond_to(Dexpace::Async, :unwrap)
      refute_respond_to(Dexpace::Async::Future, :unwrap)
      refute_respond_to(Dexpace::Async::Completer.new.future, :unwrap)
      assert_respond_to(Dexpace, :each_cause)
    end

    # CFG-20's three met clauses; the fourth (cancel-with-interrupt) is ASYNC-3's mechanism under
    # a second ID and is cited from the checklist row, not asserted here.
    test "CFG-20: a non-interrupting cancel settles promptly and a finished task is untouched" do
      completer = Dexpace::Async::Completer.new
      completer.fulfil(:finished)

      assert_same(completer.future, completer.future.cancel(:late))
      refute_predicate(completer.future, :cancelled?)
      assert_equal(:finished, completer.future.value)

      pending = Dexpace::Async::Completer.new
      pending.future.cancel(:early)

      assert_predicate(pending.future, :cancelled?)
    end

    test "CFG-20: a rejected submission is delivered through the future, never thrown" do
      completer = Dexpace::Async::Completer.new
      rejection = Dexpace::SeamError.new("executor saturated")

      assert(completer.fail(rejection))
      assert_same(rejection, assert_raises(Dexpace::SeamError) { completer.future.value })
    end
  end
end
