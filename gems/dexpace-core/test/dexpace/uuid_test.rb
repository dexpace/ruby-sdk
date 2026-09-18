# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# CFG-32: the non-cryptographic type-4 UUID generator over a per-execution-context PRNG (R3,
# P5-13).
class DexpaceUUIDTest < DexpaceTestCase
  UUID_LAYOUT = /\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/

  test "CFG-32: generates a frozen, lower-case v4 UUID with the RFC 4122 version and variant" do
    uuid = Dexpace::UUID.generate

    assert_predicate(uuid, :frozen?)
    assert_match(UUID_LAYOUT, uuid)
    assert_equal(36, uuid.bytesize)
    assert_predicate(uuid, :ascii_only?)
  end

  test "CFG-32: 10 000 draws produce no collision" do
    seen = Set.new
    10_000.times do
      uuid = Dexpace::UUID.generate

      assert_match(UUID_LAYOUT, uuid)
      assert(seen.add?(uuid), "collided on #{uuid}")
    end
  end

  # Asserted through the CARRIER, not through the output. A distinctness-of-output test alone
  # passes against a shared generator: one Random shared by 8 threads drawing 2000 each produced
  # 16 000 distinct values (design fact 4), so "no collisions" cannot show the absence of sharing.
  test "CFG-32: three execution contexts get three distinct generators, and none is shared" do
    Dexpace::UUID.generate
    main_prng = Thread.current[:dexpace_prng]

    refute_nil(main_prng)
    assert_kind_of(Random, main_prng)

    fiber_prng = nil
    Fiber.new do
      Dexpace::UUID.generate
      fiber_prng = Thread.current[:dexpace_prng]
    end.resume

    thread_prng = Thread.new do
      Dexpace::UUID.generate
      Thread.current[:dexpace_prng]
    end.value

    # Thread.current[] is fiber-local despite the name: a child fiber and a new thread each read
    # nil and seed their own. Fiber[] would hand THE SAME object to a new thread by identity,
    # which is precisely the shared mutable state CFG-32 forbids (R3, P5-13).
    refute_same(main_prng, fiber_prng)
    refute_same(main_prng, thread_prng)
    refute_same(fiber_prng, thread_prng)
    assert_same(main_prng, Thread.current[:dexpace_prng]) # the parent's slot was not overwritten
  end

  test "CFG-32 / P5-13: the generator is not reachable through Fiber storage" do
    Dexpace::UUID.generate

    assert_nil(Fiber[:dexpace_prng])
  end

  # Boundary 8: the non-cryptographic path and XCUT-21's CSPRNG stay two code paths, checkable by
  # text -- this file writes no require "securerandom" and names no SecureRandom constant.
  test "CFG-32 / XCUT-21: the generator names no SecureRandom and requires no securerandom" do
    path = File.expand_path("../../lib/dexpace/uuid.rb", __dir__)
    code = File.readlines(path).grep_v(/\A\s*#/).join

    refute_match(/SecureRandom|securerandom/, code)
  end

  # The version nibble is 4 and the variant nibble is in 8..b on every draw, not merely on the
  # first: the masks are applied to the two bytes and nothing else.
  test "CFG-32: the version and variant nibbles hold across 1000 draws, and the rest is random" do
    versions = Set.new
    variants = Set.new
    firsts = Set.new
    1000.times do
      uuid = Dexpace::UUID.generate
      versions << uuid[14]
      variants << uuid[19]
      firsts << uuid[0]
    end

    assert_equal(Set["4"], versions)
    assert_equal(Set["8", "9", "a", "b"], variants)
    assert_operator(firsts.size, :>, 8)
  end
end
