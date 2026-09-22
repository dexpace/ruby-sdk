# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/async_http_recording_sink"
require "dexpace/transport/async_http"

# TRANSPORT-13 (SHOULD): a configurable policy for how header drops are logged, with the
# per-name dedup mode case-insensitive and bounded, and the OBS-19 policy phase 5b postponed
# here. §17's own conformance clause: "under once-per-header assert the same name warns once
# then goes quiet, a different name warns once." Every emission is under the shared transport
# event, with String field keys, so one assertion reads a drop record from either adapter.
class DexpaceTransportAsyncHTTPDropPolicyTest < DexpaceTestCase
  DropPolicy = Dexpace::Transport::AsyncHTTP::DropPolicy
  EVENT = Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED

  def logger_and_sink
    sink = AsyncHTTPRecordingSink.new
    [Dexpace::Instrumentation::Logger.build(sink: sink), sink]
  end

  test "EVERY mode warns on every drop, same name or not" do
    logger, sink = logger_and_sink
    policy = DropPolicy.build(mode: DropPolicy::EVERY)

    policy.report(logger, "X-Bad:Name", "not a token")
    policy.report(logger, "X-Bad:Name", "not a token")

    assert_equal(%i[warn warn], sink.severities(EVENT))
    assert_equal(DropPolicy::EVERY, policy.mode)
  end

  test "QUIET never warns" do
    logger, sink = logger_and_sink
    policy = DropPolicy.build(mode: DropPolicy::QUIET)

    policy.report(logger, "X-Bad:Name", "not a token")
    policy.report(logger, "Y-Bad:Name", "not a token")

    assert_equal(%i[debug debug], sink.severities(EVENT))
  end

  test "ONCE_PER_NAME (the default) warns once per distinct folded name, then goes quiet" do
    logger, sink = logger_and_sink
    policy = DropPolicy.build

    policy.report(logger, "X-Bad:Name", "not a token")
    policy.report(logger, "X-Bad:Name", "not a token")
    policy.report(logger, "Y-Bad:Name", "not a token")

    assert_equal(%i[warn debug warn], sink.severities(EVENT))
    assert_equal(DropPolicy::ONCE_PER_NAME, policy.mode)
  end

  test "the per-name latch is case-insensitive on the folded name (HTTP-13)" do
    logger, sink = logger_and_sink
    policy = DropPolicy.build

    policy.report(logger, "X-Bad:Name", "not a token")
    policy.report(logger, "x-bad:name", "not a token")
    policy.report(logger, "X-BAD:NAME", "not a token")

    assert_equal(%i[warn debug debug], sink.severities(EVENT))
  end

  test "bounded at MAX_TRACKED_NAMES distinct names; the next degrades to quiet and is not " \
       "tracked, so a repeat of it is quiet too" do
    logger, sink = logger_and_sink
    policy = DropPolicy.build
    bound = DropPolicy::MAX_TRACKED_NAMES

    bound.times { |i| policy.report(logger, "X-Bad:#{i}", "not a token") }
    policy.report(logger, "X-Bad:#{bound}", "not a token")
    policy.report(logger, "X-Bad:#{bound}", "not a token")

    assert_equal(64, bound)
    assert_equal(bound, sink.severities(EVENT).count(:warn))
    assert_equal(%i[debug debug], sink.severities(EVENT).last(2))
  end

  test "a drop's record carries the header name and the reason under the shared event, with " \
       "String keys" do
    logger, sink = logger_and_sink
    DropPolicy.build.report(logger, "X-Bad:Name", "not an RFC 7230 token (TRANSPORT-12)")

    record = sink.entries.first.payload

    assert_equal(EVENT, record["event"])
    assert_equal("X-Bad:Name", record["header"])
    assert_equal("not an RFC 7230 token (TRANSPORT-12)", record["reason"])
  end

  test "a rejected mode raises Dexpace::InvalidArgumentError rather than degrading silently" do
    error = assert_raises(Dexpace::InvalidArgumentError) { DropPolicy.build(mode: :bogus) }

    assert_match(/mode must be one of/, error.message)
    assert_raises(NoMethodError) { DropPolicy.new(mode: DropPolicy::QUIET) }
  end

  # OBS-20: every emission is contained -- a sink that raises never reaches the adapter.
  test "a raising sink is contained, and the drop still returns nil" do
    sink = Object.new
    def sink.warn(*) = raise("sink exploded")
    def sink.debug(*) = raise("sink exploded")
    def sink.info(*) = nil
    def sink.error(*) = nil
    %i[debug? info? warn? error?].each { |query| sink.define_singleton_method(query) { true } }
    logger = Dexpace::Instrumentation::Logger.build(sink: sink)

    assert_nil(DropPolicy.build.report(logger, "X-Bad:Name", "not a token"))
  end

  test "MODES is the closed set of three, frozen" do
    assert_equal(%i[every once_per_name quiet], DropPolicy::MODES)
    assert_predicate(DropPolicy::MODES, :frozen?)
  end
end
