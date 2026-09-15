# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SEAM-16: there is no "settled with nothing" state to reach, because settling means writing
# exactly one of a response or an error. That is enforced in initialize, not in a builder, per
# phase 1's construction rule.
class DexpaceAsyncSettlementTest < DexpaceTestCase
  test "exactly one of response or error, and cancelled implies error" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Async::Settlement.build }
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Async::Settlement.build(response: :r, error: ::IOError.new)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Async::Settlement.build(response: :r, cancelled: true)
    end
  end

  test "the three factories build the three shapes" do
    assert_predicate(Dexpace::Async::Settlement.success(:response), :success?)
    refute_predicate(Dexpace::Async::Settlement.failure(::IOError.new), :success?)
    cancelled = Dexpace::Async::Settlement.cancellation(Dexpace::CancelledError.new(:why))

    assert(cancelled.cancelled)
    refute_predicate(cancelled, :success?)
    assert_equal(:why, cancelled.error.reason)
  end

  test "the members are exactly response, error and cancelled, and cancelled is a boolean" do
    settled = Dexpace::Async::Settlement.build(error: ::IOError.new("x"), cancelled: nil)

    assert_equal(%i[response error cancelled], settled.to_h.keys)
    assert_same(false, settled.cancelled, "coerced to a literal false, never left nil")
    assert_nil(settled.response)
  end

  # Data#with does not call an initialize override on Ruby 3.2 (verified 3.2.11 / 3.4.10 / 4.0.6),
  # so this passes on 3.4 and 4.0 without phase 1's shared #with and fails on the declared floor.
  test "with re-validates on every supported Ruby" do
    settled = Dexpace::Async::Settlement.success(:response)

    assert_raises(Dexpace::InvalidArgumentError) { settled.with(response: nil) }
  end

  test "a settlement is frozen and equal by value" do
    settled = Dexpace::Async::Settlement.success(:response)

    assert_predicate(settled, :frozen?)
    assert_equal(Dexpace::Async::Settlement.success(:response), settled)
  end

  test "new is private" do
    refute_respond_to(Dexpace::Async::Settlement, :new)
  end
end
