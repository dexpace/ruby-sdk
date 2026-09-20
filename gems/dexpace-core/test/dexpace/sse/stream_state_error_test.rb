# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/sse_fixtures"

# Exercises: SSE-26, SSE-27 -- the loud failure a second view, or a view after close, raises:
# phase 2's error shape, namespaced under SSE (6c's ProviderError precedent), a StandardError a
# caller rescues by name or through `rescue Dexpace::Error`. The two raise sites and the latch
# behind them are asserted in stream_test.rb's ViewTest and typed_stream_test.rb's; this file is
# the one-class error's own mirror (6b's scheme_downgrade_error_test.rb).
class DexpaceSSEStreamStateErrorTest < DexpaceTestCase
  include SSEFixtures

  test "SSE-26: is a Dexpace::Error and a StandardError, caught through Module#===" do
    caught = begin
      raise Dexpace::SSE::StreamStateError, "second view"
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::SSE::StreamStateError, caught)
    assert_kind_of(::StandardError, caught)
    assert_kind_of(Dexpace::Suppressible, caught)
    assert_equal("second view", caught.message)
  end

  test "SSE-26: the second-view refusal names the requirement" do
    stream, = stream_over
    stream.events

    error = assert_raises(Dexpace::SSE::StreamStateError) { stream.events }

    assert_match(/single-pass/, error.message)
    assert_match(/SSE-26/, error.message)
  end

  test "SSE-27: the after-close refusal names the requirement" do
    stream, = stream_over
    stream.close

    error = assert_raises(Dexpace::SSE::StreamStateError) { stream.each { |_e| nil } }

    assert_match(/closed/, error.message)
    assert_match(/SSE-27/, error.message)
  end
end
