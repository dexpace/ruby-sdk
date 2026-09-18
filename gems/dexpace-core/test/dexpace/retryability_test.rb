# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# CFG-35's status half and XCUT-5: the single shared status classifier. The throwable half is
# phase 6a's, Task 3 (R1), and this suite asserts its absence rather than a stub.
class DexpaceRetryabilityTest < DexpaceTestCase
  StatusDouble = Struct.new(:code)
  ALWAYS = [408, 429].freeze
  NEVER_5XX = [501, 505].freeze

  test "CFG-35 / XCUT-5: 408 and 429 are retryable, as an Integer, a Status and any #code" do
    ALWAYS.each do |code|
      assert(Dexpace::Retryability.retryable_status?(code), "code #{code}")
      assert(Dexpace::Retryability.retryable_status?(Dexpace::Status.of(code)), "code #{code}")
      assert(Dexpace::Retryability.retryable_status?(StatusDouble.new(code)), "code #{code}")
    end
  end

  # The whole 5xx range, not a sample: every code from 500 to 599 is retryable except exactly 501
  # and 505, which is the "hard contract" sentence CFG-35 ends on.
  test "CFG-35 / XCUT-5: every 5xx is retryable except 501 and 505" do
    (500..599).each do |code|
      expected = !NEVER_5XX.include?(code)

      assert_equal(expected, Dexpace::Retryability.retryable_status?(code), code.to_s)
    end
  end

  test "CFG-35 / XCUT-5: every 1xx, 2xx, 3xx and 4xx but 408 and 429 is not retryable" do
    (100..499).each do |code|
      expected = ALWAYS.include?(code)

      assert_equal(expected, Dexpace::Retryability.retryable_status?(code), code.to_s)
    end
    [0, 99, 600, 999, -1].each do |code|
      refute(Dexpace::Retryability.retryable_status?(code), code.to_s)
    end
  end

  # XCUT-7's configurable default set {408, 429, 500, 502, 503, 504} is a subset of this
  # classifier and a different object; the predicate exposes no enumerable set to confuse with it.
  test "XCUT-5 / XCUT-7: the classifier is a predicate and exposes no status set" do
    [408, 429, 500, 502, 503, 504].each do |code|
      assert(Dexpace::Retryability.retryable_status?(code), "code #{code}")
    end

    assert_empty(Dexpace::Retryability.constants)
    assert_equal([:retryable_status?], Dexpace::Retryability.singleton_methods.sort)
  end

  test "CFG-37: a status that is neither an Integer nor answers #code is refused" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Retryability.retryable_status?("503")
    end

    assert_match(/status/, error.message)
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Retryability.retryable_status?(nil) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Retryability.retryable_status?(5.03) }
  end

  test "CFG-35 throwable half: no method ships in 5a, not even one returning false (R1)" do
    refute_respond_to(Dexpace::Retryability, :retryable_throwable?)
    refute_respond_to(Dexpace::Retryability, :retryable_error?)
    refute_respond_to(Dexpace::Retryability, :retryable?)
  end
end
