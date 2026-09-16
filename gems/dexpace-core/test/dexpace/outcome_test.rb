# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/recovery_fixtures"
require "dexpace"

# RECOV-1: the closed sum type with exactly two variants, the module both include, and the
# property that the fold and the two predicates never disagree (P4-24).
class DexpaceOutcomeTest < DexpaceTestCase
  include RecoveryFixtures

  test "Outcome is a module that both variants include, and it declares no factory" do
    assert_kind_of(::Module, Dexpace::Outcome)
    refute_kind_of(::Class, Dexpace::Outcome)
    assert_operator(Dexpace::Outcome::Success, :<, Dexpace::Outcome)
    assert_operator(Dexpace::Outcome::Failure, :<, Dexpace::Outcome)
    assert_empty(Dexpace::Outcome.singleton_class.public_instance_methods(false))
    assert_empty(Dexpace::Outcome.public_instance_methods(false))
  end

  # Verified fact 14: Data's generated #deconstruct_keys makes case/in work over the two variants
  # even with private_class_method :new, and an unmatched value with no `else` raises
  # NoMatchingPatternError -- which is inside StandardError, the fact R6 turns on.
  test "case/in pattern matching reaches both variants and refuses anything else" do
    response = build_response
    error = ::IOError.new("io")
    success = Dexpace::Outcome::Success.build(response: response)
    failure = Dexpace::Outcome::Failure.build(error: error)
    match = lambda do |outcome|
      case outcome
      in Dexpace::Outcome::Success[response:] then [:success, response]
      in Dexpace::Outcome::Failure[error:] then [:failure, error]
      end
    end

    assert_equal([:success, response], match.call(success))
    assert_equal([:failure, error], match.call(failure))
    refused = assert_raises(::NoMatchingPatternError) { match.call(:neither) }

    assert_kind_of(::StandardError, refused)
  end

  # Both branches are required on both variants, so a nil branch is refused at the fold and not
  # on the first outcome of the other kind.
  test "fold refuses a nil branch on either variant, whichever branch would have run" do
    success = Dexpace::Outcome::Success.build(response: build_response)
    failure = Dexpace::Outcome::Failure.build(error: ::StandardError.new("failed"))
    branch = ->(_) { :ran }

    error = assert_raises(Dexpace::InvalidArgumentError) do
      success.fold(on_success: branch, on_failure: nil)
    end

    assert_equal("on_failure is required", error.message)
    assert_raises(Dexpace::InvalidArgumentError) { failure.fold(on_success: nil, on_failure: branch) }
    assert_raises(Dexpace::InvalidArgumentError) { success.fold(on_success: nil, on_failure: branch) }
    assert_raises(Dexpace::InvalidArgumentError) { failure.fold(on_success: branch, on_failure: nil) }
  end

  # Not the mandatory round-trip property: neither variant has a parse constructor. Written
  # anyway because it is the exhaustiveness claim in executable form -- over a seeded sequence,
  # #fold selects on_success exactly when #success? and on_failure exactly when #failure?, and the
  # predicates are never both true or both false. The seed is DexpaceTestCase#sample's and is
  # printed on failure.
  test "fold agrees with the predicates over a seeded sequence of both variants" do
    response = build_response

    sample do |rng|
      outcome = if rng.rand(2).zero?
                  Dexpace::Outcome::Success.build(response: response)
                else
                  Dexpace::Outcome::Failure.build(error: ::StandardError.new("sampled"))
                end
      branch = outcome.fold(on_success: ->(_) { :s }, on_failure: ->(_) { :f })

      refute_equal(outcome.success?, outcome.failure?)
      assert_equal(outcome.success? ? :s : :f, branch)
      assert_equal(outcome.success?, !outcome.response_or_nil.nil?)
      assert_equal(outcome.failure?, !outcome.error_or_nil.nil?)
    end
  end
end
