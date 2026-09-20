# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# The conformance assertion protocol phase 0 postponed to this phase (design §9.3, 8a's R7): an
# assertion "either returns cleanly or raises a Dexpace::Conformance::Failure carrying the expected
# and actual values". P8-8 records why the class is a ::StandardError that does NOT include
# Dexpace::Error: a conformance failure is a test result, not an SDK error, and an adapter author's
# broad `rescue Dexpace::Error` around a send must not swallow the assertion that the send was
# wrong.
class DexpaceConformanceFailureTest < DexpaceTestCase
  Failure = Dexpace::Conformance::Failure

  test "P8-8: is a StandardError and does not include Dexpace::Error" do
    assert_operator(Failure, :<, ::StandardError)
    refute_operator(Failure, :<, Dexpace::Error)
    refute_kind_of(Dexpace::Error, Failure.new("x", expected: 1, actual: 2, requirement_ids: ["A"]))
  end

  test "carries the expected and actual values and the requirement ids it was raised for" do
    failure = Failure.new("expected X", expected: "X", actual: "Y",
                                        requirement_ids: ["TRANSPORT-24"],)

    assert_equal("expected X", failure.message)
    assert_equal("X", failure.expected)
    assert_equal("Y", failure.actual)
    assert_equal(["TRANSPORT-24"], failure.requirement_ids)
    assert_predicate(failure.requirement_ids, :frozen?)
  end

  test "a broad rescue of the SDK's error root lets it through" do
    raised = begin
      begin
        raise Failure.new("x", expected: 1, actual: 2, requirement_ids: ["A"])
      rescue Dexpace::Error
        :swallowed
      end
    rescue Failure
      :propagated
    end

    assert_equal(:propagated, raised)
  end
end
