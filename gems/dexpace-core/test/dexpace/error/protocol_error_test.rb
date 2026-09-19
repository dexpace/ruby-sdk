# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recovery_fixtures"
require "dexpace"

# XCUT-4 branch (a), XCUT-8, RECOV-15. One class carrying #status and #response with no
# per-status subclass tree (P4-20): a caller distinguishes a 404 from a 429 by reading #status.
class DexpaceProtocolErrorTest < DexpaceTestCase
  include RecoveryFixtures

  test "is a Dexpace::Error and a StandardError carrying the response and its status" do
    response = build_response(404)

    error = Dexpace::ProtocolError.new(response)

    assert_kind_of(Dexpace::Error, error)
    assert_kind_of(::StandardError, error)
    assert_same(response, error.response)
    assert_equal(Dexpace::Status.of(404), error.status)
  end

  # Open question 5: no body preview. A message is what lands in a log by default, and an error
  # body is the payload most likely to carry a token; #response is how a caller reads it.
  test "the message names the status code and its canonical name, and never the body" do
    assert_equal("HTTP 404 Not Found", Dexpace::ProtocolError.new(build_response(404)).message)
    assert_equal("HTTP 503 Service Unavailable",
                 Dexpace::ProtocolError.new(build_response(503)).message,)

    with_body = Dexpace::ProtocolError.new(build_response(500, body: response_body("secret")))

    assert_equal("HTTP 500 Internal Server Error", with_body.message)
    refute_includes(with_body.message, "secret")
  end

  test "the message is the bare code when the status has no canonical name" do
    assert_equal("HTTP 499", Dexpace::ProtocolError.new(build_response(499)).message)
  end

  test "ProtocolError.for builds the error for every status in 400..599" do
    assert_equal(400, Dexpace::ProtocolError.for(build_response(400)).status.code)
    assert_equal(599, Dexpace::ProtocolError.for(build_response(599)).status.code)
    assert_instance_of(Dexpace::ProtocolError, Dexpace::ProtocolError.for(build_response(503)))
  end

  # XCUT-8's first clause: an argument error, never a fabricated "successful exception".
  test "ProtocolError.for refuses a non-error status with an argument error" do
    [100, 200, 201, 301, 304, 399].each do |code|
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::ProtocolError.for(build_response(code))
      end

      assert_includes(error.message, code.to_s)
    end
  end

  # XCUT-8's sanctioned convenience form.
  test "ProtocolError.for_or_nil returns nil for a non-error status and the error otherwise" do
    assert_nil(Dexpace::ProtocolError.for_or_nil(build_response(200)))
    assert_nil(Dexpace::ProtocolError.for_or_nil(build_response(302)))

    error = Dexpace::ProtocolError.for_or_nil(build_response(500))

    assert_instance_of(Dexpace::ProtocolError, error)
    assert_equal(500, error.status.code)
  end

  test "refuses a response that is not a Dexpace::Response" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::ProtocolError.new(:not_a_response) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::ProtocolError.for(nil) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::ProtocolError.for_or_nil(nil) }
  end

  # Phase 6a's Task 6 added the predicate 4b postponed; the nested class below is its suite,
  # extending this file exactly as the postponement said it would.

  # XCUT-5 / RETRY-3: the baked flag, computed at construction from the SINGLE shared status
  # classifier (5a's Dexpace::Retryability), and deliberately not named #retryable? (P6-10).
  class RetryableTest < DexpaceTestCase
    include RecoveryFixtures

    test "RETRY-3 / XCUT-5: retryable_by_status? is computed at construction from Retryability" do
      error = Dexpace::ProtocolError.for(build_response(503))

      assert_predicate(error, :retryable_by_status?)
      assert_equal(Dexpace::Retryability.retryable_status?(503), error.retryable_by_status?)
      assert_same(error.retryable_by_status?, error.retryable_by_status?, "baked, not recomputed")
    end

    test "RETRY-3 / XCUT-5: the flag agrees with the classifier across the whole error range" do
      (400..599).each do |code|
        error = Dexpace::ProtocolError.for(build_response(code))
        expected = Dexpace::Retryability.retryable_status?(code)

        assert_equal(expected, error.retryable_by_status?, code.to_s)
      end
      refute_predicate(Dexpace::ProtocolError.for(build_response(501)), :retryable_by_status?)
      refute_predicate(Dexpace::ProtocolError.for(build_response(505)), :retryable_by_status?)
      refute_predicate(Dexpace::ProtocolError.for(build_response(404)), :retryable_by_status?)
      assert_predicate(Dexpace::ProtocolError.for(build_response(408)), :retryable_by_status?)
      assert_predicate(Dexpace::ProtocolError.for(build_response(429)), :retryable_by_status?)
    end

    test "RETRY-3: no per-subclass constant -- a subclass inherits the computed flag" do
      subclass = Class.new(Dexpace::ProtocolError)

      assert_predicate(subclass.new(build_response(502)), :retryable_by_status?)
      refute_predicate(subclass.new(build_response(501)), :retryable_by_status?)
    end

    test "P6-10: a ProtocolError does NOT answer XCUT-6's generic #retryable? capability" do
      error = Dexpace::ProtocolError.for(build_response(503))

      refute_respond_to(error, :retryable?)
      refute(Dexpace::Resilience::Policy.throwable_retryable?(error))
    end

    test "NFR-4: the constructor keeps 4b's single positional parameter and the two factories" do
      assert_equal(1, Dexpace::ProtocolError.instance_method(:initialize).arity)
      assert_instance_of(Dexpace::ProtocolError, Dexpace::ProtocolError.for(build_response(503)))
      assert_nil(Dexpace::ProtocolError.for_or_nil(build_response(200)))
    end
  end
end
