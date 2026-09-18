# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../../lib/dexpace/bounded_map"

# Exercises: AUTH-19, AUTH-24, XCUT-14, CTX-11 -- the private bounded map's phase-6 widening,
# #update, asserted directly for the first time (phase 4a exercised the map only through
# ContextStore; the reachability facts are here too). BoundedMap is a private_constant of
# Dexpace, so a test outside `module Dexpace` cannot name it with the scope operator --
# `Dexpace::BoundedMap` raises NameError -- and #const_get, which ignores constant privacy, is
# the access route a test has (verified on 3.2.11, 3.4.10 and 4.0.6).
class DexpaceBoundedMapTest < DexpaceTestCase
  BOUNDED_MAP = Dexpace.const_get(:BoundedMap)

  def counter(map, key) = map.update(key) { |current| (current || 0) + 1 }

  test "execution-context/b58728da: reachable by const_get, not by a qualified reference" do
    error = assert_raises(NameError) { Dexpace::BoundedMap }

    assert_includes(error.message, "private constant")
    assert_kind_of(Class, BOUNDED_MAP)
  end

  test "#update starts from nil for a new key and stores what the block returns" do
    map = BOUNDED_MAP.new(cap: 8)

    assert_equal(1, counter(map, "k"))
    assert_equal(1, map["k"])
    assert_equal("x", map.update("k") { |_current| "x" })
    assert_equal("x", map["k"])
  end

  test "#update increments on reuse of the same key" do
    map = BOUNDED_MAP.new(cap: 8)
    counter(map, "k")

    assert_equal(2, counter(map, "k"))
    assert_equal(3, counter(map, "k"))
    assert_equal(1, counter(map, "other"))
  end

  test "AUTH-19: #update drains back under the cap in the same section, oldest first" do
    map = BOUNDED_MAP.new(cap: 2)
    counter(map, "a")
    counter(map, "b")

    assert_equal(1, counter(map, "c")) # evicts "a"
    assert_equal(2, map.size)
    assert_nil(map["a"])
    assert_equal(1, counter(map, "a")) # AUTH-19: an evicted nonce restarts at 1
  end

  test "a block that raises leaves the slot as it was and releases the lock" do
    map = BOUNDED_MAP.new(cap: 8)
    counter(map, "k")

    assert_raises(RuntimeError) { map.update("k") { |_current| raise "boom" } }
    assert_equal(1, map["k"])
    assert_equal(2, counter(map, "k"))
  end

  # The block runs while the map's own non-reentrant mutex is held: a block that calls back
  # into the map meets `ThreadError: deadlock; recursive locking`, deterministically.
  test "AUTH-24: the block runs under the map's mutex -- re-entering it raises ThreadError" do
    map = BOUNDED_MAP.new(cap: 8)
    error = assert_raises(ThreadError) { map.update("k") { |_current| map["k"] } }

    assert_includes(error.message, "recursive locking")
  end

  # AUTH-24 made deterministic, not probabilistic: thread A parks INSIDE its block holding the
  # old value; thread B then calls #update on the same key. Under one critical section B blocks
  # (status "sleep") until A's write lands and then reads 1, so the count is 2. With the block
  # run outside the lock B would complete while A is parked, both would write 1, and the count
  # would be 1 -- the lost increment. The test waits for B to be blocked-or-finished before it
  # releases A, so the interleaving is forced rather than hoped for.
  test "AUTH-24: read-modify-write is one critical section, forced interleaving" do
    map = BOUNDED_MAP.new(cap: 8)
    parked = ::Thread::Queue.new
    release = ::Thread::Queue.new
    first = Thread.new do
      map.update("nonce") do |current|
        parked << true
        release.pop
        (current || 0) + 1
      end
    end
    parked.pop
    second = Thread.new { map.update("nonce") { |current| (current || 0) + 1 } }
    blocked_or_done = ["sleep", false].freeze
    Thread.pass until blocked_or_done.include?(second.status)
    finished_before_release = second.status == false
    release << true
    [first, second].each(&:join)

    refute(finished_before_release, "the second update completed while the first held the lock")
    assert_equal(2, map["nonce"])
  end

  test "AUTH-24: sixteen threads released from one barrier lose no increment" do
    map = BOUNDED_MAP.new(cap: 64)
    barrier = ::Thread::Queue.new
    threads = Array.new(16) do
      Thread.new do
        barrier.pop
        200.times { counter(map, "shared") }
      end
    end
    16.times { barrier << true }
    threads.each(&:join)

    assert_equal(3200, map["shared"])
  end

  test "phase 4a's surface is untouched: set, put, [], delete_if_identical and size" do
    map = BOUNDED_MAP.new(cap: 2)
    occupant = +"w"

    assert_equal("v", map.set("a", "v"))
    assert(map.put("b", occupant))
    refute(map.put("b", "x"))
    assert_same(occupant, map["b"])
    refute(map.delete_if_identical("b", occupant.dup))
    assert(map.delete_if_identical("b", occupant))
    assert_equal(1, map.size)
  end
end
