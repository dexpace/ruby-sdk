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

  # No test pins the ABSENCE of #retryable_by_status?: XCUT-5's baked flag is postponed to phase
  # 6a, Task 6, which adds the predicate to THIS class and extends THIS suite. A postponement is
  # recorded in a checklist row, not pinned by an assertion a later phase has to delete.
end
