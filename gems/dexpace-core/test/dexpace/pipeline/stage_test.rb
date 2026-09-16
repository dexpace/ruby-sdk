# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# PIPE-1, PIPE-4, PIPE-8: one immutable stage in the total ordering, and the closed set it is a
# member of (P4-32).
class DexpacePipelineStageTest < DexpaceTestCase
  # P4-32: the stage set is closed at sixteen STRUCTURALLY, not by policy. Data.define generates
  # BOTH .new and .[] -- privatising only .new leaves Stage[...] as a public field-wise constructor
  # and makes "a caller cannot mint a sixteenth-and-a-half stage" false. Both are private. The
  # send hole phase 1's P8 names is untouched and is not closable.
  test "Stage has no public constructor: neither .new nor .[] nor .build" do
    assert_raises(NoMethodError) do
      Dexpace::Pipeline::Stage.new(name: :test, order: 100, pillar: false, terminal: false)
    end
    assert_raises(NoMethodError) do
      Dexpace::Pipeline::Stage[name: :test, order: 100, pillar: false, terminal: false]
    end
    refute_respond_to(Dexpace::Pipeline::Stage, :build)
  end

  # The hole the design does not name: Data#with is public on every Data, and on 3.4.10 and 4.0.6
  # it would mint a seventeenth stage that Stages.of cannot find; through Model#with it would
  # route to a Stage.build that does not exist. Stage overrides #with to refuse instead, so the
  # closed set is closed on every interpreter in the range and the refusal is the SDK's own error
  # rather than a NoMethodError from inside Model.
  test "Stage#with refuses, because the set is closed and there is nothing to derive" do
    stage = Dexpace::Pipeline::Stages::REDIRECT

    error = assert_raises(Dexpace::InvalidArgumentError) { stage.with(name: :fake, order: 250) }
    assert_includes(error.message, "closed")
    assert_raises(Dexpace::InvalidArgumentError) { stage.with }
    assert_equal(16, Dexpace::Pipeline::Stages::ALL.size, "no seventeenth stage was minted")
  end

  # The validating initialize behind the private constructor, reached through the send hole P8
  # names -- the one route to it -- so the five checks are proven rather than assumed: a Symbol
  # name, an Integer order, two booleans, and PIPE-4's rule that a terminal stage is a pillar.
  test "the private constructor validates every member, terminal implying pillar (PIPE-4)" do
    mint = ->(**members) { Dexpace::Pipeline::Stage.send(:new, **members) }
    valid = { name: :probe, order: 50, pillar: false, terminal: false }

    assert_equal(:probe, mint.call(**valid).name)
    assert_raises(Dexpace::InvalidArgumentError) { mint.call(**valid, name: "probe") }
    assert_raises(Dexpace::InvalidArgumentError) { mint.call(**valid, order: 50.0) }
    assert_raises(Dexpace::InvalidArgumentError) { mint.call(**valid, pillar: nil) }
    assert_raises(Dexpace::InvalidArgumentError) { mint.call(**valid, terminal: 1) }
    assert_raises(Dexpace::InvalidArgumentError) { mint.call(**valid, terminal: true) }
    assert_predicate(mint.call(**valid, pillar: true, terminal: true), :terminal?)
  end

  test "a stage's predicates reflect the members it was built with" do
    stage = Dexpace::Pipeline::Stages::REDIRECT

    assert_equal(:redirect, stage.name)
    assert_equal(200, stage.order)
    assert_predicate(stage, :pillar?)
    refute_predicate(stage, :terminal?)
    assert_predicate(stage, :installable?)
    assert_predicate(stage, :frozen?)
  end

  test "a slot stage is neither a pillar nor terminal, and is installable" do
    stage = Dexpace::Pipeline::Stages::PRE_AUTH

    refute_predicate(stage, :pillar?)
    refute_predicate(stage, :terminal?)
    assert_predicate(stage, :installable?)
  end

  # PIPE-4's parenthesis and PIPE-8: SEND is flagged as a singleton, is the transport hop itself,
  # and admits no user step.
  test "the terminal SEND stage is a pillar, is terminal, and is not installable" do
    send_stage = Dexpace::Pipeline::Stages::SEND

    assert_equal(:send, send_stage.name)
    assert_equal(1600, send_stage.order)
    assert_predicate(send_stage, :pillar?)
    assert_predicate(send_stage, :terminal?)
    refute_predicate(send_stage, :installable?)
  end

  # Verified fact 10: a Data responds to <=> through Kernel#<=>, which returns nil for two
  # distinct stages, so sorting stages raises. Nothing in the runtime sorts a Stage; ordering is
  # Stages::ALL's position, always, and this test is the trap's name.
  test "sorting Stage instances directly raises ArgumentError, so nothing may sort them" do
    a = Dexpace::Pipeline::Stages::REDIRECT
    b = Dexpace::Pipeline::Stages::RETRY

    assert_raises(ArgumentError) { [b, a].sort }
    assert_equal([a, b], [b, a].sort_by(&:order))
  end

  test "two distinct stages are never equal, so a table keyed by stage cannot collide" do
    all = Dexpace::Pipeline::Stages::ALL

    all.each do |stage|
      refute_equal(stage, all.find { |other| !other.equal?(stage) })
    end
    assert_equal(16, all.map(&:hash).uniq.size)
  end
end
