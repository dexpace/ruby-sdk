# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# PIPE-8, PIPE-22, PIPE-23, PIPE-25, PIPE-35: the caller-visible "this step, at this stage" pair,
# with the optional anchor name PIPE-18-PIPE-21 address a lambda step by (the plan's 2026-09-13
# amendment).
class DexpacePipelineEntryTest < DexpaceTestCase
  STAGES = Dexpace::Pipeline::Stages
  ENTRY = Dexpace::Pipeline::Entry

  def setup
    super
    @stage = STAGES::RETRY
    @step = ->(req, cur) { cur.call(req) }
  end

  # Both generated constructors are private, so .build is the only path and its checks cannot be
  # walked around by a caller who reaches for Data's .[] instead of .new.
  test "Entry.new and Entry.[] are both private" do
    assert_raises(NoMethodError) { ENTRY.new(stage: @stage, step: @step, name: nil) }
    assert_raises(NoMethodError) { ENTRY[stage: @stage, step: @step, name: nil] }
  end

  test "Entry.build succeeds with a stage and a conforming step, and name: defaults to nil" do
    entry = ENTRY.build(stage: @stage, step: @step)

    assert_same(@stage, entry.stage)
    assert_same(@step, entry.step)
    assert_nil(entry.name, "name: is optional and defaults to nil")
    assert_predicate(entry, :frozen?)
  end

  # The amendment. A name is what lets PIPE-18-PIPE-21 address ONE lambda step, whose class is
  # Proc like every other lambda's (verified fact 13).
  test "Entry.build carries an optional Symbol or String name, a String frozen" do
    assert_equal(:auth_probe, ENTRY.build(stage: @stage, step: @step, name: :auth_probe).name)

    mutable = +"auth_probe"
    named = ENTRY.build(stage: @stage, step: @step, name: mutable)

    assert_equal("auth_probe", named.name)
    assert_predicate(named.name, :frozen?)
    refute_same(mutable, named.name, "a caller's mutable String is copied, not aliased (XCUT-15)")
  end

  test "Entry.build rejects a name that is neither Symbol nor String" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      ENTRY.build(stage: @stage, step: @step, name: 42)
    end

    assert_includes(error.message, "name must be a Symbol or String (PIPE-18)")
  end

  # PIPE-8, in the one place every install funnels through.
  test "Entry.build rejects the terminal SEND stage with PipelineError" do
    error = assert_raises(Dexpace::PipelineError) { ENTRY.build(stage: STAGES::SEND, step: @step) }

    assert_includes(error.message, "cannot install step at terminal stage SEND (PIPE-8)")
  end

  test "Entry.build rejects a stage that is not a Stage, a name included" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      ENTRY.build(stage: :retry, step: @step)
    end

    assert_includes(error.message, "stage must be a Dexpace::Pipeline::Stage (PIPE-1)")
    assert_raises(Dexpace::InvalidArgumentError) { ENTRY.build(stage: nil, step: @step) }
  end

  test "Entry.build rejects a non-conforming step with InvalidArgumentError" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      ENTRY.build(stage: @stage, step: Object.new)
    end

    assert_includes(error.message, "step must conform to Dexpace::Pipeline::Step (PIPE-12)")
    assert_raises(Dexpace::InvalidArgumentError) { ENTRY.build(stage: @stage, step: ->(x) { x }) }
  end

  # Model#with routes through .build, so a derivation re-validates on every interpreter --
  # including 3.2.11, where Data#with would skip an initialize override. A derivation to SEND is
  # the PIPE-8 rejection, not a silently minted entry.
  test "Entry#with re-validates through .build, on the floor as above it" do
    entry = ENTRY.build(stage: @stage, step: @step, name: :a)
    renamed = entry.with(name: :b)

    assert_equal(:b, renamed.name)
    assert_same(@step, renamed.step)
    assert_same(entry, entry.with)
    assert_raises(Dexpace::PipelineError) { entry.with(stage: STAGES::SEND) }
    assert_raises(Dexpace::InvalidArgumentError) { entry.with(step: Object.new) }
  end

  test "two entries over the same stage, step and name are ==, and a name difference is not" do
    a = ENTRY.build(stage: @stage, step: @step, name: :x)
    b = ENTRY.build(stage: @stage, step: @step, name: :x)

    assert_equal(a, b)
    refute_same(a, b)
    refute_equal(a, ENTRY.build(stage: @stage, step: @step, name: :y))
  end
end
