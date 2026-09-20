# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace/transport/net_http"

# TRANSPORT-5, TRANSPORT-6 (8a's R3): RequestOptions#timeout is a TOTAL per-call budget, carried
# as a monotonic instant over an injectable clock. TRANSPORT-5's own conformance clause is a
# statement about the CALL's budget, not one syscall, and the total reading is what makes it
# implementable at all. Deadline is a private_constant, reached through const_get.
class DexpaceTransportNetHttpDeadlineTest < DexpaceTestCase
  NetHTTP = Dexpace::Transport::NetHTTP
  Deadline = NetHTTP.const_get(:Deadline)

  # A clock that advances only when told to: no real time enters these tests.
  class FakeClock
    def initialize(start)
      @now = start
    end

    def monotonic
      @now
    end

    def advance(seconds)
      @now += seconds
    end
  end

  test "is a private_constant of NetHTTP, and .new is private" do
    assert_raises(NameError) { NetHTTP::Deadline }
    assert_raises(NoMethodError) { Deadline.new(FakeClock.new(0.0), 1.0) }
  end

  test "#remaining counts down as the clock advances" do
    clock = FakeClock.new(0.0)
    deadline = Deadline.build(clock: clock, budget: 5.0)

    clock.advance(2.0)

    assert_in_delta(3.0, deadline.remaining)
  end

  test "#expired? is true once remaining reaches zero or below" do
    clock = FakeClock.new(0.0)
    deadline = Deadline.build(clock: clock, budget: 1.0)

    refute_predicate(deadline, :expired?)
    clock.advance(1.0)

    assert_predicate(deadline, :expired?)
    clock.advance(0.5)

    assert_predicate(deadline, :expired?)
  end

  # TRANSPORT-6: the antecedent is inverted on this adapter (zero means poll-once, not
  # unbounded), and the clamp ships anyway, for adapters over coarser APIs.
  test "#clamped raises a tiny positive remaining up to MIN_TIMEOUT_SECONDS" do
    clock = FakeClock.new(0.0)
    deadline = Deadline.build(clock: clock, budget: NetHTTP::MIN_TIMEOUT_SECONDS / 2)

    assert_in_delta(NetHTTP::MIN_TIMEOUT_SECONDS, deadline.clamped)
  end

  test "#clamped does not raise an already-expired remaining" do
    clock = FakeClock.new(0.0)
    deadline = Deadline.build(clock: clock, budget: -1.0)

    assert_operator(deadline.clamped, :<=, 0)
    assert_predicate(deadline, :expired?)
  end

  test "#clamped leaves a comfortably positive remaining untouched" do
    clock = FakeClock.new(0.0)
    deadline = Deadline.build(clock: clock, budget: 10.0)

    assert_in_delta(10.0, deadline.clamped)
  end

  test "the budget is measured against the clock's monotonic reading, never Time.now" do
    clock = FakeClock.new(1_000.0)
    deadline = Deadline.build(clock: clock, budget: 0.5)

    assert_in_delta(0.5, deadline.remaining)
    clock.advance(0.25)

    assert_in_delta(0.25, deadline.remaining)
  end
end
