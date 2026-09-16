# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# RECOV-1: the Failure variant. Its initialize validates that the error IS an Exception -- nothing
# else in the model would catch a Failure carrying a String, and RECOV-10 would then raise it
# into a TypeError at the one point the caller is furthest from the cause (P4-21, P4-23).
class DexpaceOutcomeFailureTest < DexpaceTestCase
  test "build constructs a frozen Failure carrying the error by identity" do
    error = ::StandardError.new("failed")

    outcome = Dexpace::Outcome::Failure.build(error: error)

    assert_kind_of(Dexpace::Outcome, outcome)
    assert_predicate(outcome, :frozen?)
    assert_same(error, outcome.error)
    refute_predicate(outcome, :success?)
    assert_predicate(outcome, :failure?)
    assert_nil(outcome.response_or_nil)
    assert_same(error, outcome.error_or_nil)
  end

  test "build requires an Exception, in SEAM-29's message form for nil" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Outcome::Failure.build(error: nil)
    end

    assert_equal("error is required", error.message)
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Outcome::Failure.build(error: "not an exception")
    end
  end

  # A Failure may carry any Exception, including one outside StandardError: the orchestrator
  # never builds one for the fatal family, but a caller's recovery step may return one.
  test "build accepts an Exception outside StandardError" do
    outcome = Dexpace::Outcome::Failure.build(error: ::NotImplementedError.new("adapter"))

    assert_kind_of(::NotImplementedError, outcome.error)
  end

  test "fold applies on_failure exactly once with the error and returns its value" do
    error = ::StandardError.new("failed")
    outcome = Dexpace::Outcome::Failure.build(error: error)
    calls = []

    result = outcome.fold(
      on_success: lambda { |r|
        calls << r
        :ok
      },
      on_failure: lambda { |e|
        calls << e
        :err
      },
    )

    assert_equal(:err, result)
    assert_equal(1, calls.size)
    assert_same(error, calls.first)
  end

  test "new is private and with re-validates through build" do
    outcome = Dexpace::Outcome::Failure.build(error: ::StandardError.new("failed"))

    assert_raises(::NoMethodError) { Dexpace::Outcome::Failure.new(error: ::StandardError.new) }
    # Model#with routes through .build on every interpreter -- Data#with skips an initialize
    # override on 3.2.11 -- so a String is refused on the floor too.
    assert_raises(Dexpace::InvalidArgumentError) { outcome.with(error: "not an exception") }
    other = ::IOError.new("other")

    assert_same(other, outcome.with(error: other).error)
    assert_same(outcome, outcome.with)
  end
end
