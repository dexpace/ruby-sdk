# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/recovery_fixtures"
require "dexpace"

# RECOV-16, BODY-30. Status#error? is phase 1's and the bound is phase 3b's; this suite exercises
# only the step that reads both, and the negative guarantee that no second bound exists (R9,
# spec-forced boundary 10).
class DexpaceRecoveryTest < DexpaceTestCase
  include RecoveryFixtures

  test "Recovery is a module holding the buffering function and declaring no second bound" do
    assert_kind_of(::Module, Dexpace::Recovery)
    refute(Dexpace::Recovery.constants(false).any? { |name| name.to_s.include?("BYTES") },
           "the one bound is Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES and lives there",)
    refute_match(/1024 \* 1024|1_048_576|1048576/,
                 File.read(File.expand_path("../../lib/dexpace/recovery.rb", __dir__)),)
  end

  test "buffer_error_body returns a non-error response by identity, body untouched" do
    body = response_body("ok")
    response = build_response(200, body: body)

    assert_same(response, Dexpace::Recovery.buffer_error_body(response))
    refute_predicate(body, :closed?)
    redirect = build_response(304, body: body)

    assert_same(redirect, Dexpace::Recovery.buffer_error_body(redirect))
    refute_predicate(body, :closed?)
  end

  test "buffer_error_body returns an error response with no body by identity" do
    response = build_response(500)

    assert_same(response, Dexpace::Recovery.buffer_error_body(response))
  end

  test "buffer_error_body buffers the error body, closes the original, and keeps the rest" do
    body = response_body("error payload")
    response = build_response(503, body: body)

    result = Dexpace::Recovery.buffer_error_body(response)

    refute_same(response, result)
    assert_predicate(body, :closed?, "buffer_bounded's ensure closes the original")
    assert_instance_of(Dexpace::BufferBody, result.body)
    assert_equal(503, result.status.code)
    assert_same(response.request, result.request)
    assert_same(response.headers, result.headers)
    assert_equal("error payload", result.body_string)
    assert_equal("error payload".b, result.body_bytes, "readable repeatably (BODY-30)")
  end

  # Spec-forced boundary 10: the assertion names the constant rather than 1024 * 1024, so a
  # second constant would break this test rather than pass it. One 1 MiB allocation per run.
  test "buffer_error_body truncates at MAX_BUFFERED_ERROR_BODY_BYTES with no marker" do
    cap = Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES
    response = build_response(500, body: response_body("x" * (cap + 1)))

    bytes = Dexpace::Recovery.buffer_error_body(response).body_bytes

    assert_equal(cap, bytes.bytesize)
    assert_equal(("x" * cap).b, bytes)
  end

  test "buffer_error_body refuses anything that is not a Dexpace::Response" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Recovery.buffer_error_body(nil) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Recovery.buffer_error_body("x") }
  end
end
