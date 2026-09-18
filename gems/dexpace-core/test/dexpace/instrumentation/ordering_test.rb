# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_http_tracer"
require "dexpace"

# OBS-29's lifecycle ordering contract, as its own conformance clause prescribes: "drive a
# succeeding and a failing (retry-exhausted) operation through a conformant emitter and assert
# the ordering and the exhausted->failed pairing". The emitter is RecordingHTTPTracer, driven
# BY HAND -- nothing in phase 5 emits any of this (R14; the per-attempt group is phase 6a's
# retry step, Task 9, the transport milestones phase 8's, the operation triple phase 10's), which
# OBS-29's own last sentence anticipates: "pipeline/transport wiring to emit it is a follow-up,
# so it is not yet runtime-enforced". This is the regression the wiring must keep green. The
# 1:1 clause is asserted in no_tracer_test.rb against RecordingTracerFactory (P5-43).
class DexpaceInstrumentationOrderingTest < DexpaceTestCase
  CTX = :request_context

  test "OBS-29: a succeeding operation emits started once, first, and succeeded once, last" do
    tracer = Dexpace::RecordingHTTPTracer.new

    tracer.operation_started(CTX)
    tracer.attempt_started(CTX, 1)
    tracer.request_url_resolved(CTX, "https://example.com")
    tracer.connection_acquired(CTX, "example.com", 443)
    tracer.request_sent(CTX, 100)
    tracer.response_headers_received(CTX, 200, {})
    tracer.response_received(CTX, 500)
    tracer.operation_succeeded(CTX, :response)
    names = tracer.events.map(&:first)

    assert_equal(:operation_started, names.first)
    assert_equal(:operation_succeeded, names.last)
    assert_equal(1, names.count(:operation_started))
    assert_equal(1, names.count(:operation_succeeded))
    refute_includes(names, :operation_failed, "succeeded and failed are mutually exclusive")
    refute_includes(names, :retries_exhausted)
    assert_equal(
      %i[attempt_started request_url_resolved connection_acquired request_sent
         response_headers_received response_received],
      names[1..-2],
      "the attempt and its transport milestones sit between the two lifecycle events",
    )
  end

  # The clause a naive test omits: retries_exhausted is IMMEDIATELY followed by operation_failed
  # carrying the SAME error object -- adjacency by index, identity by assert_same.
  test "OBS-29: a retry-exhausted operation pairs retries_exhausted with operation_failed" do
    tracer = Dexpace::RecordingHTTPTracer.new
    error = ::StandardError.new("connection timeout")

    tracer.operation_started(CTX)
    tracer.attempt_started(CTX, 1)
    tracer.attempt_failed(CTX, error, 0.5)
    tracer.attempt_started(CTX, 2)
    tracer.attempt_failed(CTX, error, 1.0)
    tracer.retries_exhausted(CTX, error)
    tracer.operation_failed(CTX, error)
    events = tracer.events
    names = events.map(&:first)

    assert_equal(:operation_started, names.first)
    assert_equal(:operation_failed, names.last)
    assert_equal(1, names.count(:operation_started))
    assert_equal(1, names.count(:operation_failed))
    refute_includes(names, :operation_succeeded, "succeeded and failed are mutually exclusive")
    assert_equal(2, names.count(:attempt_started), "attempt events may fire many times")

    exhausted_at = names.index(:retries_exhausted)

    refute_nil(exhausted_at)
    assert_equal(1, names.count(:retries_exhausted), "retries_exhausted fires at most once")
    assert_equal(:operation_failed, names[exhausted_at + 1], "immediately followed")
    assert_same(events[exhausted_at][2], events[exhausted_at + 1][2], "the same throwable")
    assert_same(error, events[exhausted_at + 1][2])
  end

  # A failure without exhaustion -- a non-retryable error on the first attempt -- still ends in
  # exactly one operation_failed and never a retries_exhausted.
  test "OBS-29: a non-retried failure ends in operation_failed alone" do
    tracer = Dexpace::RecordingHTTPTracer.new
    error = ::ArgumentError.new("400 Bad Request")

    tracer.operation_started(CTX)
    tracer.attempt_started(CTX, 1)
    tracer.operation_failed(CTX, error)
    names = tracer.events.map(&:first)

    assert_equal(%i[operation_started attempt_started operation_failed], names)
    assert_same(error, tracer.events.last[2])
  end
end
