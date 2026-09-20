# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/sse/limit_exceeded_error"

# Exercises: SSE-19 -- the error a line or an event block raises when it crosses its documented
# bound: it names which bound (`kind`) and the value (`limit`), so a caller raising a cap knows
# which one to raise; phase 2's error shape, namespaced under SSE (6c's ProviderError precedent).
class DexpaceSSELimitExceededErrorTest < DexpaceTestCase
  test "SSE-19: names which bound was crossed and its value, and is a Dexpace::Error" do
    error = Dexpace::SSE::LimitExceededError.new(kind: :line, limit: 1_048_576)

    assert_equal(:line, error.kind)
    assert_equal(1_048_576, error.limit)
    assert_kind_of(Dexpace::Error, error)
    assert_kind_of(::StandardError, error)
    assert_match(/line/, error.message)
    assert_match(/1048576/, error.message)
    assert_match(/SSE-19/, error.message)
  end

  test "SSE-19: the event kind reads as an event bound" do
    error = Dexpace::SSE::LimitExceededError.new(kind: :event, limit: 32)

    assert_equal(:event, error.kind)
    assert_match(/event/, error.message)
    assert_match(/32-byte/, error.message)
  end

  test "SSE-19: the kind is one of the two bounds and nothing else" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::SSE::LimitExceededError.new(kind: :chunk, limit: 1)
    end
  end
end
