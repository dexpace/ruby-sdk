# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/allocation_delta"
require "dexpace"

# OBS-28, OBS-30: the eleven-method HTTP-tracer vocabulary with its no-op defaults, and the
# frozen NULL singleton design §8.1 names. OBS-29's ordering contract is ordering_test.rb's;
# nothing in phase 5 emits any of this (R14).
class DexpaceInstrumentationHTTPTracerTest < DexpaceTestCase
  include AllocationDelta

  HTTPTracer = Dexpace::Instrumentation::HTTPTracer
  NULL = Dexpace::Instrumentation::NULL
  ERROR = ::StandardError.new("boom").freeze
  HEADERS = { "content-type" => "application/json" }.freeze

  OPERATION = %i[operation_started operation_succeeded operation_failed].freeze
  ATTEMPT = %i[attempt_started attempt_failed retries_exhausted].freeze
  TRANSPORT = %i[
    request_url_resolved connection_acquired request_sent response_headers_received
    response_received
  ].freeze

  test "OBS-28: the vocabulary is exactly eleven methods in three groups, and NULL includes it" do
    assert_equal(
      (OPERATION + ATTEMPT + TRANSPORT).sort, HTTPTracer.public_instance_methods(false).sort,
    )
    assert_kind_of(HTTPTracer, NULL)
    assert_predicate(NULL, :frozen?)
    assert_empty(NULL.class.public_instance_methods(false), "NULL's class adds nothing")
    refute_includes(Dexpace::Instrumentation.constants(false), :NullHTTPTracer)
  end

  test "OBS-28: every event method defaults to a no-op returning nil, on NULL" do
    assert_nil(NULL.operation_started(:ctx))
    assert_nil(NULL.operation_succeeded(:ctx, :response))
    assert_nil(NULL.operation_failed(:ctx, ERROR))
    assert_nil(NULL.attempt_started(:ctx, 1))
    assert_nil(NULL.attempt_failed(:ctx, ERROR, 1.5))
    assert_nil(NULL.retries_exhausted(:ctx, ERROR))
    assert_nil(NULL.request_url_resolved(:ctx, "https://example.com"))
    assert_nil(NULL.connection_acquired(:ctx, "example.com", 443))
    assert_nil(NULL.request_sent(:ctx, 1024))
    assert_nil(NULL.response_headers_received(:ctx, 200, HEADERS))
    assert_nil(NULL.response_received(:ctx, 2048))
  end

  # The arities phases 6 and 8 emit against, pinned: host and port on connection_acquired, byte
  # counts on the two sent/received milestones, status and headers on the headers milestone,
  # the next delay on attempt_failed. No keyword and no splat anywhere (P5-42).
  test "OBS-28: the eleven arities are the contract phases 6 and 8 emit against" do
    expected = {
      operation_started: %i[context], operation_succeeded: %i[context response],
      operation_failed: %i[context error], attempt_started: %i[context attempt],
      attempt_failed: %i[context error next_delay], retries_exhausted: %i[context error],
      request_url_resolved: %i[context url], connection_acquired: %i[context host port],
      request_sent: %i[context byte_count],
      response_headers_received: %i[context status headers],
      response_received: %i[context byte_count],
    }

    expected.each do |name, params|
      assert_equal(params.map { |param| [:req, param] }, NULL.method(name).parameters, name.to_s)
    end
  end

  # OBS-28's "implementers override only what they need" as a mechanism: include the module,
  # override one method, and the other ten stay no-ops rather than NoMethodErrors -- which under
  # OBS-30's no-wrapping rule would otherwise land in the caller's request path.
  test "OBS-28: an implementer includes the module and overrides only what it needs" do
    tracer_class = Class.new do
      include Dexpace::Instrumentation::HTTPTracer

      attr_reader :started

      def operation_started(context)
        @started = context
      end
    end
    tracer = tracer_class.new

    tracer.operation_started(:my_ctx)

    assert_equal(:my_ctx, tracer.started)
    assert_nil(tracer.operation_succeeded(:my_ctx, :resp))
    assert_nil(tracer.retries_exhausted(:my_ctx, ERROR))
    assert_kind_of(HTTPTracer, tracer)
  end

  test "OBS-30: NULL is one object from sixteen threads" do
    results = Array.new(16) { ::Thread.new { NULL } }.map(&:value)

    assert_equal(1, results.uniq.size)
    assert_same(NULL, results.first)
  end

  # OBS-25's "a no-op HTTP-tracer" half: the whole vocabulary on NULL allocates nothing per
  # call. Frozen constants, Symbols and Integers only cross the loop body.
  test "OBS-25: driving all eleven callbacks on NULL allocates nothing per call" do
    per_call = allocations_per_call do
      NULL.operation_started(:ctx)
      NULL.attempt_started(:ctx, 1)
      NULL.request_url_resolved(:ctx, "https://example.com")
      NULL.connection_acquired(:ctx, "example.com", 443)
      NULL.request_sent(:ctx, 100)
      NULL.response_headers_received(:ctx, 200, HEADERS)
      NULL.response_received(:ctx, 500)
      NULL.attempt_failed(:ctx, ERROR, 1)
      NULL.retries_exhausted(:ctx, ERROR)
      NULL.operation_failed(:ctx, ERROR)
      NULL.operation_succeeded(:ctx, :response)
    end

    assert_in_delta(0.0, per_call, 0.0, "the null HTTP tracer allocates per call")
  end
end
