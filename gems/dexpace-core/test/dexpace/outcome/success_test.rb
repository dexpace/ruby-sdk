# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recovery_fixtures"
require "dexpace"

# RECOV-1: the Success variant. Phase 1's construction rule taken whole -- private new, a
# validating initialize, .build as the wrapper, Model#with routing through .build (P4-21, P4-23).
class DexpaceOutcomeSuccessTest < DexpaceTestCase
  include RecoveryFixtures

  test "build constructs a frozen Success carrying the response by identity" do
    response = build_response

    outcome = Dexpace::Outcome::Success.build(response: response)

    assert_kind_of(Dexpace::Outcome, outcome)
    assert_predicate(outcome, :frozen?)
    assert_same(response, outcome.response)
    assert_predicate(outcome, :success?)
    refute_predicate(outcome, :failure?)
    assert_same(response, outcome.response_or_nil)
    assert_nil(outcome.error_or_nil)
  end

  test "build requires a Dexpace::Response, in SEAM-29's message form for nil" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Outcome::Success.build(response: nil)
    end

    assert_equal("response is required", error.message)
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Outcome::Success.build(response: "not a response")
    end
  end

  test "fold applies on_success exactly once with the response and returns its value" do
    response = build_response
    outcome = Dexpace::Outcome::Success.build(response: response)
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

    assert_equal(:ok, result)
    assert_equal(1, calls.size)
    assert_same(response, calls.first)
  end

  test "new is private and with re-validates through build" do
    outcome = Dexpace::Outcome::Success.build(response: build_response)

    assert_raises(::NoMethodError) { Dexpace::Outcome::Success.new(response: build_response) }
    # Model#with routes through .build on every interpreter -- Data#with skips an initialize
    # override on 3.2.11 -- so the nil is refused on the floor too.
    assert_raises(Dexpace::InvalidArgumentError) { outcome.with(response: nil) }
    other = build_response(201)

    assert_same(other, outcome.with(response: other).response)
    assert_same(outcome, outcome.with)
  end

  test "two Successes over one response are equal, and hash alike" do
    response = build_response

    first = Dexpace::Outcome::Success.build(response: response)
    second = Dexpace::Outcome::Success.build(response: response)

    assert_equal(first, second)
    assert_equal(first.hash, second.hash)
    refute_equal(first, Dexpace::Outcome::Success.build(response: build_response(201)))
  end
end
