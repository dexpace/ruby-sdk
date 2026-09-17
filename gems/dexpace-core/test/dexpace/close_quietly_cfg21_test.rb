# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# CFG-21: a cancelled interruptible task whose result is a closeable resource must have that
# result closed on the discard path, best-effort, swallowing close failures, and the close helper
# must be null-safe. Phase 2 shipped both halves -- Dexpace.close_quietly and Completer#fulfil's
# lost-race close (SEAM-30) -- so this suite asserts them rather than adding code, and exists so
# the checklist row has a test to name.
class DexpaceCloseQuietlyCFG21Test < DexpaceTestCase
  # A closeable that counts its closes and can be told to fail them.
  class CountingResource
    attr_reader :closes

    def initialize(raising: false)
      @closes = 0
      @raising = raising
    end

    def close
      @closes += 1
      raise ::IOError, "close failed" if @raising

      nil
    end
  end

  test "CFG-21: the best-effort close helper is null-safe" do
    assert_nil(Dexpace.close_quietly(nil))
  end

  test "CFG-21: a close failure on the discard path is swallowed, and the close was attempted" do
    resource = CountingResource.new(raising: true)

    assert_nil(Dexpace.close_quietly(resource))
    assert_equal(1, resource.closes)
  end

  test "CFG-21: a fulfil that loses the race to a cancel closes the response exactly once" do
    completer = Dexpace::Async::Completer.new
    resource = CountingResource.new
    completer.future.cancel(:too_late)

    refute(completer.fulfil(resource))
    assert_equal(1, resource.closes)
    assert_predicate(completer.future, :cancelled?)
  end

  # The same discard path when the cancellation came from an expired deadline (Task 8): one
  # settlement, one close.
  test "CFG-21: a fulfil after a deadline expiry closes the late result exactly once" do
    completer = Dexpace::Async::Completer.new
    resource = CountingResource.new
    completer.await(nil, deadline: 0.0, clock: Dexpace::Clock::SYSTEM)

    refute(completer.fulfil(resource))
    assert_equal(1, resource.closes)
  end
end
