# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# One assertion's outcome, in five statuses and never a boolean: collapsing them into pass/fail is
# exactly what makes a vacuous requirement indistinguishable from one nobody checked (design §12).
class DexpaceConformanceResultTest < DexpaceTestCase
  Result = Dexpace::Conformance::Result
  STATUSES = %i[passed failed vacuous waived error].freeze

  def assertion
    Dexpace::Conformance::Assertion.build(ids: ["X"], name: "n", body: ->(_) {})
  end

  test "status is restricted to exactly the five documented values" do
    assert_equal(STATUSES, Result::STATUSES)
    STATUSES.each do |status|
      result = Result.build(assertion: assertion, status: status)

      assert_equal(status, result.status)
      assert_nil(result.detail)
      assert_predicate(result, :frozen?)
    end
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Result.build(assertion: assertion, status: :skipped)
    end

    assert_match(/passed, failed, vacuous, waived, error/, error.message)
  end

  test "carries the assertion it is the outcome of and an optional detail" do
    a = assertion
    result = Result.build(assertion: a, status: :failed, detail: "boom")

    assert_same(a, result.assertion)
    assert_equal("boom", result.detail)
  end

  test "HTTP-4 / SEAM-29: the assertion is required, in the one message form" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Result.build(assertion: nil, status: :passed)
    end

    assert_equal("assertion is required", error.message)
    assert_raises(Dexpace::InvalidArgumentError) do
      Result.build(assertion: :not_one, status: :passed)
    end
  end

  test "HTTP-2: the constructor is private, so .build is the one entry point" do
    assert_raises(NoMethodError) { Result.new(assertion: assertion, status: :passed, detail: nil) }
  end
end
