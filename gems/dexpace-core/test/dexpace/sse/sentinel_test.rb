# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "pp"
require_relative "../../test_helper"
require_relative "../../../lib/dexpace/sse"

# Exercises: SSE-34 -- the closed two-instance sentinel type behind Dexpace::SSE::SKIP and
# ::DONE (P7-23; renamed from the design's `Signal`, which would have shadowed Ruby's ::Signal
# inside module Dexpace::SSE -- the checklist's as-built row).
class DexpaceSSESentinelTest < DexpaceTestCase
  Sentinel = Dexpace::SSE::Sentinel

  test "SSE-34: the sentinel cannot be constructed by a caller, so the set is the two constants" do
    assert_raises(::NoMethodError) { Sentinel.new(name: :other) }
    assert_raises(::NoMethodError) { Sentinel[:other] }
    refute_respond_to(Sentinel, :build)
  end

  test "SSE-34: a sentinel has no derivation either -- #with refuses" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::SSE::SKIP.with(name: :other) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::SSE::DONE.with }
  end

  test "SSE-34: the outcome comparison is identity: a value that == a sentinel is still a value" do
    # A Data compares by value; a decoded model that happens to answer == SKIP must not be taken
    # for it, which is why every dispatch site writes equal? and why this is asserted.
    lookalike = Sentinel.send(:new, name: :skip)

    assert_equal(Dexpace::SSE::SKIP, lookalike)
    refute_same(Dexpace::SSE::SKIP, lookalike)
  end

  test "SSE-34: #to_s, #inspect and #pretty_print all print the constant's name" do
    assert_equal("Dexpace::SSE::SKIP", Dexpace::SSE::SKIP.to_s)
    assert_equal("Dexpace::SSE::SKIP", Dexpace::SSE::SKIP.inspect)
    assert_equal("Dexpace::SSE::DONE\n", Dexpace::SSE::DONE.pretty_inspect)
    assert_equal("Dexpace::SSE::DONE", Dexpace::SSE::DONE.to_s)
  end

  test "SSE-34: the sentinel type is a frozen Data with one member and no Model derivation" do
    assert_operator(Sentinel, :<, ::Data)
    assert_equal(%i[name], Sentinel.members)
    assert_predicate(Dexpace::SSE::SKIP, :frozen?)
    assert_equal({ name: :done }, Dexpace::SSE::DONE.to_h)
  end
end
