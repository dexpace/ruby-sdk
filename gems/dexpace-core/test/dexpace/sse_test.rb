# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# Exercises: SSE-19 (the two documented caps, their values and their layering under phase 3a's
# ceiling), SSE-11 (the retry magnitude cap, a SEPARATE cap from SSE-19's), SSE-34 (the two
# mapper-outcome sentinels as module constants) -- lib/dexpace/sse.rb, the namespace file.
class DexpaceSSETest < DexpaceTestCase
  test "SSE-19: MAX_LINE_BYTES is 1 MiB and MAX_EVENT_BYTES is 8 MiB, both chosen and documented" do
    assert_equal(1 * 1024 * 1024, Dexpace::SSE::MAX_LINE_BYTES)
    assert_equal(8 * 1024 * 1024, Dexpace::SSE::MAX_EVENT_BYTES)
  end

  test "SSE-19: both caps sit strictly below phase 3a's materialisation ceiling" do
    # A different bound at a different layer, never a second ceiling on the same operation. The
    # relationship is asserted rather than described so a later change to either constant that
    # inverted it would fail here.
    assert_operator(Dexpace::SSE::MAX_LINE_BYTES, :<, Dexpace::IO::MAX_MATERIALIZED_BYTES)
    assert_operator(Dexpace::SSE::MAX_EVENT_BYTES, :<, Dexpace::IO::MAX_MATERIALIZED_BYTES)
    assert_operator(Dexpace::SSE::MAX_LINE_BYTES, :<, Dexpace::SSE::MAX_EVENT_BYTES)
  end

  test "SSE-11: MAX_RETRY_MS is 2**31 - 1, design section 10.18's substituted constant" do
    assert_equal((2**31) - 1, Dexpace::SSE::MAX_RETRY_MS)
  end

  test "SSE-34: SKIP and DONE are two distinct frozen singletons of the sentinel type" do
    refute_equal(Dexpace::SSE::SKIP, Dexpace::SSE::DONE)
    refute_same(Dexpace::SSE::SKIP, Dexpace::SSE::DONE)
    assert_predicate(Dexpace::SSE::SKIP, :frozen?)
    assert_predicate(Dexpace::SSE::DONE, :frozen?)
    assert_instance_of(Dexpace::SSE::Sentinel, Dexpace::SSE::SKIP)
    assert_instance_of(Dexpace::SSE::Sentinel, Dexpace::SSE::DONE)
    assert_equal(:skip, Dexpace::SSE::SKIP.name)
    assert_equal(:done, Dexpace::SSE::DONE.name)
  end

  test "SSE-34: a sentinel reaching a log identifies itself by the constant's name" do
    assert_equal("Dexpace::SSE::SKIP", Dexpace::SSE::SKIP.to_s)
    assert_equal("Dexpace::SSE::DONE", Dexpace::SSE::DONE.inspect)
  end

  test "the namespace holds exactly its public constants and the three limits are Integers" do
    assert_equal(
      %i[DONE Event LimitExceededError LineReader MAX_EVENT_BYTES MAX_LINE_BYTES MAX_RETRY_MS
         Reader SKIP Sentinel Stream StreamStateError TypedStream],
      Dexpace::SSE.constants(false).sort,
    )
    assert_kind_of(::Integer, Dexpace::SSE::MAX_LINE_BYTES)
    assert_kind_of(::Integer, Dexpace::SSE::MAX_EVENT_BYTES)
    assert_kind_of(::Integer, Dexpace::SSE::MAX_RETRY_MS)
  end
end
