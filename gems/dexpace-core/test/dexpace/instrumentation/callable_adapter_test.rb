# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# Design §8.1, OBS-28: the bus-shape adapter, forwarding each of the eleven callbacks to one
# `#call(name, payload)` object with the event name and a Hash of the arguments under their
# parameter names. The bus shape is available without being the default listener interface.
class DexpaceInstrumentationCallableAdapterTest < DexpaceTestCase
  Adapter = Dexpace::Instrumentation::CallableAdapter
  HEADERS = { "content-type" => "application/json" }.freeze

  def drive_all_eleven(tracer)
    tracer.operation_started(:ctx)
    tracer.operation_succeeded(:ctx, :resp)
    tracer.operation_failed(:ctx, :err)
    tracer.attempt_started(:ctx, 1)
    tracer.attempt_failed(:ctx, :err, 0.5)
    tracer.retries_exhausted(:ctx, :err)
    tracer.request_url_resolved(:ctx, "https://api.example.com")
    tracer.connection_acquired(:ctx, "api.example.com", 443)
    tracer.request_sent(:ctx, 128)
    tracer.response_headers_received(:ctx, 200, HEADERS)
    tracer.response_received(:ctx, 512)
  end

  test "OBS-28: every callback is forwarded as its name and a payload keyed by parameter name" do
    received = []
    adapter = Adapter.new(->(name, payload) { received << [name, payload] })

    drive_all_eleven(adapter)

    assert_equal(
      [
        [:operation_started, { context: :ctx }],
        [:operation_succeeded, { context: :ctx, response: :resp }],
        [:operation_failed, { context: :ctx, error: :err }],
        [:attempt_started, { context: :ctx, attempt: 1 }],
        [:attempt_failed, { context: :ctx, error: :err, next_delay: 0.5 }],
        [:retries_exhausted, { context: :ctx, error: :err }],
        [:request_url_resolved, { context: :ctx, url: "https://api.example.com" }],
        [:connection_acquired, { context: :ctx, host: "api.example.com", port: 443 }],
        [:request_sent, { context: :ctx, byte_count: 128 }],
        [:response_headers_received, { context: :ctx, status: 200, headers: HEADERS }],
        [:response_received, { context: :ctx, byte_count: 512 }],
      ],
      received,
    )
  end

  test "OBS-28: the adapter is an HTTPTracer, overrides all eleven, and returns nil from each" do
    adapter = Adapter.new(->(_name, _payload) { :ignored })

    assert_kind_of(Dexpace::Instrumentation::HTTPTracer, adapter)
    assert_equal(
      Dexpace::Instrumentation::HTTPTracer.public_instance_methods(false).sort,
      Adapter.public_instance_methods(false).sort,
    )
    assert_nil(adapter.operation_started(:ctx))
    assert_nil(adapter.response_received(:ctx, 1))
  end

  test "any #call(name, payload) object serves as the bus, not only a lambda" do
    bus = Class.new do
      attr_reader :seen

      def call(name, payload)
        (@seen ||= []) << name
        payload
      end
    end.new
    adapter = Adapter.new(bus)

    adapter.operation_started(:ctx)
    adapter.operation_succeeded(:ctx, :resp)

    assert_equal(%i[operation_started operation_succeeded], bus.seen)
  end

  # OBS-30 from the other side: the adapter wraps nothing, so a raising bus fails the caller.
  test "OBS-30: a raising bus propagates through the adapter uncaught" do
    adapter = Adapter.new(->(_name, _payload) { raise "bus down" })
    error = assert_raises(::RuntimeError) { adapter.operation_started(:ctx) }

    assert_equal("bus down", error.message)
  end

  test "a callable that does not respond to #call is refused at construction" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Adapter.new(:not_callable) }

    assert_includes(error.message, "callable")
    assert_raises(Dexpace::InvalidArgumentError) { Adapter.new(nil) }
  end
end
