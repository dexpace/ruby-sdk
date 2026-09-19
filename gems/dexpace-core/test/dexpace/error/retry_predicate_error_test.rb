# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# RETRY-40, RETRY-25, P6-11, P6-56: the well-typed abort the two stage-based retry drivers raise
# when a caller's should_retry predicate itself raises. The raise sites and the wrapping are
# asserted where they happen (retry_step_test.rb, async_retry_step_test.rb); this mirror pins the
# class's own shape.
class DexpaceRetryPredicateErrorTest < DexpaceTestCase
  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::RetryPredicateError, "the should_retry predicate raised RuntimeError"
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::RetryPredicateError, caught)
    assert_kind_of(Dexpace::Suppressible, caught)
  end

  test "subclasses StandardError and includes Dexpace::Error" do
    assert_operator(Dexpace::RetryPredicateError, :<, ::StandardError)
    assert_includes(Dexpace::RetryPredicateError.ancestors, Dexpace::Error)
  end

  # P6-56: flat under Dexpace::, on the tree's one-error-per-file convention, and not under
  # Dexpace::Resilience, where the plan named it half the time.
  test "P6-56: lives flat under Dexpace::, not under Dexpace::Resilience" do
    assert_equal("Dexpace::RetryPredicateError", Dexpace::RetryPredicateError.name)
    refute(Dexpace::Resilience.const_defined?(:RetryPredicateError, false))
  end

  # RETRY-40: the predicate's own failure travels as #cause, which a `cause:` at the raise site
  # sets -- a genuine wrap of a fresh failure, so pipeline/7ce4431d's `cause: nil` rule for a
  # CARRIED error does not apply here.
  test "RETRY-40: carries the predicate's raise as #cause when raised with cause:" do
    inner = ::RuntimeError.new("boom")
    wrapped = begin
      raise Dexpace::RetryPredicateError.new("the should_retry predicate raised RuntimeError"),
            cause: inner
    rescue Dexpace::RetryPredicateError => error
      error
    end

    assert_same(inner, wrapped.cause)
    assert_equal("the should_retry predicate raised RuntimeError", wrapped.message)
  end

  test "carries no fields of its own" do
    assert_empty(Dexpace::RetryPredicateError.instance_methods(false))
  end

  test "is not Dexpace::InvalidArgumentError -- a misbehaving hook is not a bad argument" do
    refute_operator(Dexpace::RetryPredicateError, :<, Dexpace::InvalidArgumentError)
  end
end
