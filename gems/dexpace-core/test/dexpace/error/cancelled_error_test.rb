# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SEAM-18's interruption clause read as cooperative cancellation (design P2-4). The reason is a
# typed object rather than a message, because XCUT-2 requires timeout and cancellation to be told
# apart out-of-band; RETRY-23/RETRY-24 read the same field in phase 6.
class DexpaceCancelledErrorTest < DexpaceTestCase
  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::CancelledError
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::CancelledError, caught)
  end

  test "carries the cancellation reason as the object it was given" do
    reason = Object.new

    assert_same(reason, Dexpace::CancelledError.new(reason).reason)
  end

  test "reads without a reason" do
    assert_nil(Dexpace::CancelledError.new.reason)
    assert_equal("the operation was cancelled", Dexpace::CancelledError.new.message)
  end

  test "names the reason in the message when there is one" do
    error = Dexpace::CancelledError.new(:deadline)

    assert_equal("the operation was cancelled: deadline", error.message)
  end

  # XCUT-4 puts transport errors in Ruby's IOError family. A cancellation is not a transport
  # failure, so it deliberately stays outside it (design P2-4).
  test "is not in Ruby's IOError family" do
    refute_operator(Dexpace::CancelledError, :<, ::IOError)
    assert_operator(Dexpace::CancelledError, :<, ::StandardError)
  end
end
