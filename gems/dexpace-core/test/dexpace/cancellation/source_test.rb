# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# The write side of SEAM-13's token: one frozen Data snapshot swapped under a Thread::Mutex, so
# concurrent cancels elect exactly one winner -- SEAM-9's serialisation rule applied to the same
# snapshot shape the registry uses -- and hooks run outside the lock.
class DexpaceCancellationSourceTest < DexpaceTestCase
  test "concurrent cancels elect exactly one winner and one reason" do
    source = Dexpace::Cancellation.source
    wins = ::Queue.new

    Array.new(16) { |i| ::Thread.new { wins << i if source.cancel(i) } }.each(&:join)

    assert_equal(1, wins.size)
    assert_equal(wins.pop, source.reason, "the reason is the winner's")
  end

  test "the source and its token agree on cancelled? and reason" do
    source = Dexpace::Cancellation.source

    refute_predicate(source, :cancelled?)
    assert_nil(source.reason)
    assert_nil(source.cancelled_at)

    source.cancel(:why)

    assert_predicate(source, :cancelled?)
    assert_predicate(source.token, :cancelled?)
    assert_equal(:why, source.reason)
    assert_equal(:why, source.token.reason)
    assert_kind_of(::Integer, source.cancelled_at)
  end

  test "a hook registered after cancellation fires immediately with the reason" do
    source = Dexpace::Cancellation.source
    source.cancel(:already)
    seen = []

    returned = source.on_cancel { |reason| seen << reason }

    assert_same(source, returned)
    assert_equal([:already], seen)
  end

  test "hooks run exactly once each, after the state is published" do
    source = Dexpace::Cancellation.source
    observed = []
    source.on_cancel { |reason| observed << [reason, source.cancelled?] }
    source.on_cancel { |reason| observed << [reason, source.reason] }

    source.cancel(:go)
    source.cancel(:again)

    assert_equal([[:go, true], %i[go go]], observed)
  end

  test "off_cancel withdraws one registration by identity and is idempotent" do
    source = Dexpace::Cancellation.source
    seen = []
    kept = proc { seen << :kept }
    dropped = proc { seen << :dropped }
    source.on_cancel(&kept)
    source.on_cancel(&dropped)

    assert_same(source, source.off_cancel(dropped))
    source.off_cancel(dropped)
    source.cancel(:go)

    assert_equal([:kept], seen)
    assert_same(source, source.off_cancel(kept), "a no-op once the list is taken")
  end

  test "the token is a token, is frozen, and is the same object on every read" do
    source = Dexpace::Cancellation.source

    assert_instance_of(Dexpace::Cancellation, source.token)
    assert_predicate(source.token, :frozen?)
    assert_same(source.token, source.token)
  end

  # The stamp is monotonic and taken at cancel time, which is what a composed token orders by.
  test "cancelled_at orders two sources by the time they cancelled" do
    earlier = Dexpace::Cancellation.source
    later = Dexpace::Cancellation.source

    earlier.cancel(:first)
    later.cancel(:second)

    assert_operator(earlier.cancelled_at, :<=, later.cancelled_at)
  end
end
