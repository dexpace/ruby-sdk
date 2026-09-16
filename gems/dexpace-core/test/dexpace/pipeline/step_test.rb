# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# PIPE-11, PIPE-12, NFR-11: the step protocol -- #call(request, cursor) -- and the predicate that
# is phase 2's transport predicate one arity lower (verified fact 1).
class DexpacePipelineStepTest < DexpaceTestCase
  STEP = Dexpace::Pipeline::Step

  test "conforms? accepts a two-argument lambda" do
    assert(STEP.conforms?(->(request, cursor) { cursor.call(request) }))
  end

  # The :opt handling, without which a non-lambda proc would be rejected and design §5.1's "a
  # lambda qualifies as a step" would be false of half of Ruby's callables.
  test "conforms? accepts a two-argument proc, whose parameters report :opt" do
    step = proc { |request, cursor| cursor.call(request) }

    assert_equal(%i[opt opt], step.parameters.map(&:first))
    assert(STEP.conforms?(step))
  end

  test "conforms? accepts an object with a two-argument #call, and a bound Method" do
    klass = Class.new do
      def call(request, cursor) = cursor.call(request)
    end

    assert(STEP.conforms?(klass.new))
    assert(STEP.conforms?(klass.new.method(:call)))
  end

  test "conforms? accepts a rest-parameter callable and one with a trailing optional" do
    assert(STEP.conforms?(->(*args) { args }))
    assert(STEP.conforms?(->(request, cursor, extra = nil) { [request, cursor, extra] }))
  end

  test "conforms? rejects zero-, one- and three-argument callables" do
    refute(STEP.conforms?(-> { 42 }))
    refute(STEP.conforms?(->(x) { x }))
    refute(STEP.conforms?(->(a, b, c) { [a, b, c] }))
  end

  test "conforms? rejects a callable with a required keyword" do
    refute(STEP.conforms?(->(request, cursor, mode:) { [request, cursor, mode] }))
  end

  test "conforms? rejects non-callable objects" do
    refute(STEP.conforms?(Object.new))
    refute(STEP.conforms?(nil))
    refute(STEP.conforms?("not callable"))
  end

  # A step is a duck type: `include Dexpace::Pipeline::Step` is neither required nor meaningful,
  # because a lambda cannot include a module. The module has no instance side to include.
  test "Step is a module with no instance methods and no registry" do
    assert_empty(STEP.instance_methods)
    refute_respond_to(STEP, :register)
    refute_respond_to(STEP, :install)
  end
end
