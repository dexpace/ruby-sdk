# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# PIPE-1, PIPE-2, PIPE-3, PIPE-4, PIPE-8, PIPE-25, PIPE-28: the one frozen stage table both
# runtimes flatten through (P4-31).
class DexpacePipelineStagesTest < DexpaceTestCase
  STAGES = Dexpace::Pipeline::Stages

  test "holds exactly sixteen stages, and ALL lists each constant once" do
    tables = %i[ALL PILLARS]
    constants = STAGES.constants(false).reject { |name| tables.include?(name) }

    assert_equal(16, STAGES::ALL.size)
    assert_equal(16, constants.size)
    assert_equal(STAGES::ALL.map(&:name).sort, constants.map { |c| STAGES.const_get(c).name }.sort)
    assert_equal(16, STAGES::ALL.uniq.size, "no stage appears in ALL twice")
  end

  test "ALL and PILLARS are frozen, and so is every stage in them" do
    assert_predicate(STAGES::ALL, :frozen?)
    assert_predicate(STAGES::PILLARS, :frozen?)
    assert(STAGES::ALL.all?(&:frozen?))
  end

  # PIPE-2's precedence chain, verbatim, as a list of names in ALL's own order (P4-31).
  test "ALL is PIPE-2's chain with PIPE-3's pre and post slots interleaved, SEND last" do
    expected = %i[
      pre_redirect redirect post_redirect
      pre_retry retry post_retry
      pre_auth auth post_auth
      pre_logging logging post_logging
      pre_serde serde post_serde
      send
    ]

    assert_equal(expected, STAGES::ALL.map(&:name))
  end

  # ALL is a hand-written frozen Array and #order is a separate public member that NOTHING at run
  # time reads (verified fact 10: flattening walks ALL's positions), so the two can disagree with
  # no symptom while #order is NFR-4-locked surface a caller may reasonably order by. This is the
  # assertion that catches a stage inserted at the wrong index, or given a duplicate or
  # out-of-sequence key -- the one edit PIPE-3's sparse numbering exists to make safe.
  test "ALL is in strictly ascending order by Stage#order, with sparse keys by 100" do
    orders = STAGES::ALL.map(&:order)

    assert_equal(orders, orders.uniq.sort)
    assert_equal(STAGES::ALL, STAGES::ALL.sort_by(&:order))
    assert_equal((1..16).map { |i| i * 100 }, orders, "sparse by 100 (PIPE-3)")
  end

  test "PILLARS holds the five configurable pillars in precedence order, SEND excluded" do
    expected = [STAGES::REDIRECT, STAGES::RETRY, STAGES::AUTH, STAGES::LOGGING, STAGES::SERDE]

    assert_equal(expected, STAGES::PILLARS)
    refute_includes(STAGES::PILLARS, STAGES::SEND)
    assert_equal(STAGES::PILLARS, STAGES::ALL.select { |s| s.pillar? && !s.terminal? })
  end

  test "exactly six stages are pillars and exactly one is terminal" do
    assert_equal(6, STAGES::ALL.count(&:pillar?))
    assert_equal([STAGES::SEND], STAGES::ALL.select(&:terminal?))
    assert_equal(15, STAGES::ALL.count(&:installable?))
  end

  test ".of resolves a stage by Symbol or String name, by identity" do
    assert_same(STAGES::RETRY, STAGES.of(:retry))
    assert_same(STAGES::RETRY, STAGES.of("retry"))
    assert_same(STAGES::PRE_REDIRECT, STAGES.of(:pre_redirect))
    STAGES::ALL.each { |stage| assert_same(stage, STAGES.of(stage.name)) }
  end

  test ".of raises Dexpace::InvalidArgumentError naming an unknown stage" do
    error = assert_raises(Dexpace::InvalidArgumentError) { STAGES.of(:nonexistent) }

    assert_includes(error.message, "unknown stage: :nonexistent (PIPE-1)")
    assert_raises(Dexpace::InvalidArgumentError) { STAGES.of(nil) }
    assert_raises(Dexpace::InvalidArgumentError) { STAGES.of("RETRY") }
  end
end
