# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/cyclic_errors"
require "dexpace"

# XCUT-9: the one cause walk every classification in the port goes through, tracking visited
# objects by reference identity and terminating on a self-referential or cyclic chain. P4-16: it
# yields the error itself first. The three R7 cases each prove something the other two do not,
# and the fourth -- the equal?-not-== discrimination -- rests on the fixture's construction.
class DexpaceEachCauseTest < DexpaceTestCase
  test "yields the error itself first, then each cause, oldest last (P4-16)" do
    top = begin
      begin
        raise ::StandardError, "root"
      rescue ::StandardError
        raise ::StandardError, "middle"
      end
    rescue ::StandardError
      begin
        raise ::StandardError, "top"
      rescue ::StandardError => error
        error
      end
    end

    walked = Dexpace.each_cause(top).to_a

    assert_equal(%w[top middle root], walked.map(&:message))
    assert_same(top, walked[0])
    assert_same(top.cause, walked[1])
    assert_same(top.cause.cause, walked[2])
  end

  # Asserted on the COUNT and never with assert_nothing_raised, which would pass against an
  # infinite loop only by hanging the suite.
  test "terminates on a self-referential cause" do
    error = CyclicErrorFixtures::SelfCause.new("self")

    walked = Dexpace.each_cause(error).to_a

    assert_equal(1, walked.size)
    assert_same(error, walked.first)
  end

  # assert_same on each element, where verified fact 6 bites: assert_equal on the array would
  # pass against a walk that yielded [a, a] if the two carried the same message.
  test "terminates on a two-node cycle and yields each error exactly once, by identity" do
    a = CyclicErrorFixtures::CyclicPair.new("a")
    b = CyclicErrorFixtures::CyclicPair.new("b")
    a.other_cause = b
    b.other_cause = a

    walked = Dexpace.each_cause(a).to_a

    assert_equal(2, walked.size)
    assert_same(a, walked[0])
    assert_same(b, walked[1])
  end

  # The discriminator: two never-raised instances carrying one message, == by Ruby's own
  # Exception#== and eql?/hash-equal by the fixture's overrides, chained through #cause. An
  # Array-tracked walk yields 1, a Set-tracked walk yields 1, and only an identity-tracked walk
  # yields 2 (verified fact 7, measured on all three interpreters for THIS construction -- a
  # raise-built pair is not == on 3.2.11 and the test stops discriminating there).
  test "tracks visited causes by identity: two structurally equal errors are both yielded" do
    parent = CyclicErrorFixtures::StructurallyEqualError.new("same message")
    child = CyclicErrorFixtures::StructurallyEqualError.new("same message")
    parent.custom_cause = child

    assert_equal(parent, child, "the fixture must be ==, or an Array-tracked walk is not caught")
    assert(parent.eql?(child), "the fixture must be eql?, or a Set-tracked walk is not caught")
    assert_equal(parent.hash, child.hash)
    refute_same(parent, child)

    walked = Dexpace.each_cause(parent).to_a

    assert_equal(2, walked.size)
    assert_same(parent, walked[0])
    assert_same(child, walked[1])
  end

  # Open question 3: a classification must never be the thing that fails, so a #cause that
  # raises ends the chain rather than propagating.
  test "stops at a raising #cause without propagating" do
    error = CyclicErrorFixtures::RaisingCauseError.new("raising")

    walked = Dexpace.each_cause(error).to_a

    assert_equal(1, walked.size)
    assert_same(error, walked.first)
  end

  # A #cause that returns something other than an Exception ends the chain too: a classification
  # must not be handed a String as if it were a cause.
  test "stops at a #cause that is not an Exception" do
    error = CyclicErrorFixtures::LyingCauseError.new("lying")

    walked = Dexpace.each_cause(error).to_a

    assert_equal([error], walked)
  end

  test "returns an Enumerator without a block and nil with one" do
    error = ::StandardError.new("enum")
    seen = []

    enumerator = Dexpace.each_cause(error)

    assert_instance_of(::Enumerator, enumerator)
    assert_equal([error], enumerator.to_a)
    assert_nil(Dexpace.each_cause(error) { |cause| seen << cause })
    assert_equal([error], seen)
    assert(Dexpace.each_cause(error).any? { |cause| cause.equal?(error) })
  end

  test "refuses an argument that is not an Exception" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace.each_cause("boom").to_a }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace.each_cause(nil) { nil } }
  end
end
