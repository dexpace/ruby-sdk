# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# OBS-21: "A Span MUST expose a recording flag; when non-recording, all mutators ... MUST be inert
# ... end() MUST be idempotent." Core's own NO_SPAN is non-recording by construction, so the
# recording branch and the idempotent finish need a RECORDING double to have a subject at all --
# this one, shipped here because phase 5c assigned it to the conformance gem and a third-party
# adapter author asserting OBS-21 needs it to ship. The protocol is 5c's `_Span`: `finish
# (end_timestamp: nil)`, never an `#end`.
class DexpaceConformanceRecordingSpanTest < DexpaceTestCase
  RecordingSpan = Dexpace::Conformance::RecordingSpan

  test "satisfies the _Span protocol phase 5c fixed, method for method" do
    span = RecordingSpan.new

    %i[recording? set_attribute add_event record_error status= finish context].each do |name|
      assert_respond_to(span, name)
    end

    assert_equal([%i[key end_timestamp]], span.method(:finish).parameters)
    refute_respond_to(span, :end, "the protocol is #finish, never #end")
  end

  test "recording? is true and the mutators actually record" do
    span = RecordingSpan.new(context: :the_bundle)

    assert_same(span, span.set_attribute("http.status_code", 200))
    assert_same(span, span.add_event("retry", attributes: { "attempt" => 2 }))
    assert_same(span, span.record_error(RuntimeError.new("boom")))
    span.status = :error

    assert_predicate(span, :recording?)
    assert_equal(200, span.attributes["http.status_code"])
    assert_equal([{ name: "retry", attributes: { "attempt" => 2 } }], span.events)
    assert_equal("boom", span.errors.first[:error].message)
    assert_equal(:error, span.status)
    assert_equal(:the_bundle, span.context)
  end

  test "finish is idempotent: a second call does not duplicate the exported record" do
    span = RecordingSpan.new
    at = Time.at(0)

    span.finish(end_timestamp: at)
    span.finish

    assert_equal([at], span.finished_at)
    refute_predicate(span, :recording?, "a finished span records no more")
  end

  test "mutators after finish are inert, per OBS-21's own end-then-mutate case" do
    span = RecordingSpan.new
    span.finish

    span.set_attribute("late", "value")
    span.add_event("late")
    span.record_error(RuntimeError.new("late"))
    span.status = :late

    refute_includes(span.attributes, "late")
    assert_empty(span.events)
    assert_empty(span.errors)
    assert_nil(span.status)
  end

  test "recording: false is the non-recording variant, inert from the start and never finished" do
    span = RecordingSpan.new(recording: false)

    span.set_attribute("k", "v")
    span.finish

    refute_predicate(span, :recording?)
    assert_empty(span.attributes)
    assert_empty(span.finished_at)
  end
end
