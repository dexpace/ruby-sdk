# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recovery_fixtures"
require_relative "../../support/recording_body"
require "dexpace"

# RECOV-15, RECOV-16, XCUT-8, PIPE-37. The status test is phase 1's Status#error? and the bound
# is phase 3b's: this suite exercises the step that reads both, and the one clause a placement
# test alone would miss -- a non-error response passes with its body not read, consumed or
# closed.
class DexpaceRecoveryErrorMappingStepTest < DexpaceTestCase
  include RecoveryFixtures

  test "is a :response transform defaulting to core's own factory" do
    step = Dexpace::Recovery::ErrorMappingStep.build

    assert_kind_of(Dexpace::Recovery::Transform, step)
    assert_equal(:response, step.phase)
    assert_respond_to(step.factory, :call)
    assert_predicate(step.factory, :frozen?)
    assert_same(step.factory, Dexpace::Recovery::ErrorMappingStep.build.factory,
                "one frozen default, no Method object per build",)
  end

  # PIPE-37's parenthesised clause, made honourable here and honoured by phase 4c's placement:
  # identity, and the body's #source never called and its latch never flipped.
  test "a non-error response is returned by identity with its body not read or closed" do
    step = Dexpace::Recovery::ErrorMappingStep.build

    [100, 200, 204, 301, 304, 399].each do |code|
      body = RecordingBody.new("payload")
      response = build_response(code, body: body)

      assert_same(response, step.apply(response))
      assert_equal(0, body.source_count, "body#source must not be called on a #{code}")
      assert_equal(0, body.release_count)
      refute_predicate(body, :closed?)
    end
  end

  test "an error response is buffered first, then mapped, then raised as a ProtocolError" do
    step = Dexpace::Recovery::ErrorMappingStep.build
    body = response_body("error payload")
    response = build_response(404, body: body)

    raised = assert_raises(Dexpace::ProtocolError) { step.apply(response) }

    assert_equal(404, raised.status.code)
    assert_predicate(body, :closed?, "RECOV-16: buffering closes the original (RECOV-13)")
    assert_instance_of(Dexpace::BufferBody, raised.response.body)
    assert_equal("error payload", raised.response.body_string)
    assert_equal("error payload".b, raised.response.body_bytes, "readable repeatably")
    refute_same(response, raised.response)
  end

  test "an error response with no body is mapped and raised without buffering" do
    raised = assert_raises(Dexpace::ProtocolError) do
      Dexpace::Recovery::ErrorMappingStep.build.apply(build_response(503))
    end

    assert_equal(503, raised.status.code)
    assert_nil(raised.response.body)
  end

  # Verified fact 5, at the site RECOV-10's own test cannot reach: the factory CONSTRUCTS the
  # error, so a bare `raise` here would hand it the caller's in-flight $! as a #cause -- and
  # RECOV-10's `cause: nil` unwrap cannot clear a cause that is already there. A 4xx raised from
  # inside a caller's rescue is the ordinary case in a generated client, not an exotic one.
  test "the raise attaches no cause while an unrelated exception is in flight" do
    step = Dexpace::Recovery::ErrorMappingStep.build
    response = build_response(404, body: response_body("error payload"))

    raised = begin
      raise "unrelated caller in-flight exception"
    rescue ::StandardError
      begin
        step.apply(response)
      rescue Dexpace::ProtocolError => error
        error
      end
    end

    assert_nil(raised.cause, "the mapping step must not add a cause to the error it constructs")
  end

  # §5.1's "delegates to": a generated SDK substitutes its own typed errors without a second
  # step, and the factory sees the BUFFERED response.
  test "a custom factory receives the buffered response and its result is what is raised" do
    custom = Class.new(::StandardError)
    seen = nil
    step = Dexpace::Recovery::ErrorMappingStep.build(factory: lambda { |response|
      seen = response
      custom.new("status: #{response.status.code}")
    })
    body = response_body("server error")

    raised = assert_raises(custom) { step.apply(build_response(500, body: body)) }

    assert_equal("status: 500", raised.message)
    assert_instance_of(Dexpace::BufferBody, seen.body)
    assert_predicate(body, :closed?)
  end

  # XCUT-8's factory rule holds for a caller's factory too: the step only ever calls it for an
  # error status, so a factory that returns nil has broken its half of the contract.
  test "a factory that returns something that is not an Exception is a caller mistake" do
    step = Dexpace::Recovery::ErrorMappingStep.build(factory: ->(_) { "not an exception" })

    assert_raises(Dexpace::InvalidArgumentError) { step.apply(build_response(500)) }
  end

  test "build validates the factory and new is private" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Recovery::ErrorMappingStep.build(factory: nil)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Recovery::ErrorMappingStep.build(factory: :not_callable)
    end
    assert_raises(::NoMethodError) { Dexpace::Recovery::ErrorMappingStep.new(factory: ->(_) {}) }
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Recovery::ErrorMappingStep.build.apply(:not_a_response)
    end
  end
end
