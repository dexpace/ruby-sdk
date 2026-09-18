# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_sink"
require_relative "../../support/diagnostic_context"
require_relative "../../support/allocation_delta"
require_relative "../../../lib/dexpace/instrumentation/logger"

# Exercises: OBS-1, OBS-2, OBS-9, OBS-10, OBS-40
#
# The facade. The enabled decision is made once, at #event, and the disabled answer is the
# shared singleton asserted by a QUALIFIED constant reference (R8): that is the form
# dexpace-conformance restates from another gem, and it is what forces Event::INERT public.
#
# Split into nested classes under Metrics/ClassLength: the decision, the collaborators.
class DexpaceInstrumentationLoggerTest < DexpaceTestCase
  include AllocationDelta

  Logger = Dexpace::Instrumentation::Logger
  Severity = Dexpace::Instrumentation::Severity
  Event = Dexpace::Instrumentation::Event
  Diagnostics = Dexpace::Instrumentation::Diagnostics

  test "OBS-1: a disabled severity yields Event::INERT, reference-identical across calls" do
    sink = RecordingSink.new(info_enabled: false, debug_enabled: true)
    logger = Logger.build(sink: sink)

    assert_same(Dexpace::Instrumentation::Event::INERT, logger.event(Severity::INFO))
    assert_same(logger.event(Severity::INFO), logger.event(:info))
    refute(logger.enabled?(Severity::INFO))

    live = logger.event(Severity::VERBOSE)

    refute_same(Event::INERT, live)
    assert_kind_of(Event, live)
    refute_same(live, logger.event(:verbose), "a live event is fresh per call")
    assert(logger.enabled?(:verbose))
  end

  # OBS-1's allocation clause at the facade: obtaining the inert event costs nothing per call.
  # Only the frozen Severity constant crosses the loop.
  test "OBS-1: obtaining the inert event allocates nothing per call" do
    logger = Logger.build(sink: RecordingSink.new(info_enabled: false))

    assert_in_delta(0.0, allocations_per_call { logger.event(Severity::INFO) }, 0.0)
  end

  test "OBS-2: each of the four severities emits at its own backend level" do
    sink = RecordingSink.new
    logger = Logger.build(sink: sink)
    Severity::ALL.each { |severity| logger.event(severity).field("k", severity.name).emit }

    assert_equal(%i[error warn info debug], sink.entries.map(&:severity))
    assert_equal(%w[error warning info verbose], sink.payloads.map { |payload| payload["k"] })
  end

  test "OBS-2: the enabled decision is per severity and reads the sink's predicate" do
    sink = RecordingSink.new(debug_enabled: false, error_enabled: false)
    logger = Logger.build(sink: sink)

    assert_same(Event::INERT, logger.event(Severity::VERBOSE))
    assert_same(Event::INERT, logger.event(Severity::ERROR))
    refute_same(Event::INERT, logger.event(Severity::INFO))
    assert_raises(Dexpace::InvalidArgumentError) { logger.event(:fatal) }
  end

  test "Logger::NULL is a frozen logger over NULL_SINK whose every event is inert" do
    assert_predicate(Logger::NULL, :frozen?)
    assert_same(Dexpace::Instrumentation::NULL_SINK, Logger::NULL.sink)
    Severity::ALL.each do |severity|
      assert_same(Event::INERT, Logger::NULL.event(severity), severity.name.to_s)
      refute(Logger::NULL.enabled?(severity))
    end
    assert_equal({}, Logger::NULL.context)
  end

  # OBS-9, OBS-10 and construction.
  class CollaboratorsTest < DexpaceTestCase
    Logger = Dexpace::Instrumentation::Logger
    Severity = Dexpace::Instrumentation::Severity
    Diagnostics = Dexpace::Instrumentation::Diagnostics

    test "OBS-9: the context is String-keyed, deep-frozen once, and the same object every read" do
      sink = RecordingSink.new
      source = { env: "staging", tags: %w[a b] }
      logger = Logger.build(sink: sink, context: source)

      assert_equal({ "env" => "staging", "tags" => %w[a b] }, logger.context)
      assert_predicate(logger.context, :frozen?)
      assert_predicate(logger.context["tags"], :frozen?)
      assert_same(logger.context, logger.context)
      refute_predicate(source, :frozen?, "the caller's Hash is copied, never frozen in place")

      logger.event(Severity::INFO).emit

      assert_equal("staging", sink.payloads.first["env"])
    end

    test "OBS-10: the default allow-list folds trace.id and span.id only" do
      sink = RecordingSink.new
      logger = Logger.build(sink: sink)
      DiagnosticContext.preserve do
        ::Fiber[Diagnostics::TRACE_ID] = "t"
        ::Fiber[Diagnostics::SPAN_ID] = "s"
        ::Fiber[:tenant] = "acme"
        logger.event(Severity::INFO).emit
      end

      assert_equal({ "trace.id" => "t", "span.id" => "s" }, sink.payloads.first)
    end

    # nil is a MODE (the opt-in unfiltered fold), not "use the default", so it is asserted through
    # behaviour: P5-17 puts no #diagnostic_keys reader on the surface.
    test "OBS-10: diagnostic_keys nil is the unfiltered mode and a custom list folds those keys" do
      sink = RecordingSink.new
      unfiltered = Logger.build(sink: sink, diagnostic_keys: nil)
      custom = Logger.build(sink: sink, diagnostic_keys: ["tenant", :"trace.id"])
      DiagnosticContext.preserve do
        ::Fiber[Diagnostics::TRACE_ID] = "t"
        ::Fiber[:tenant] = "acme"
        ::Fiber[:other] = "o"
        unfiltered.event(Severity::INFO).emit
        custom.event(Severity::INFO).emit
      end

      assert_equal({ "trace.id" => "t", "tenant" => "acme", "other" => "o" }, sink.payloads[0])
      assert_equal({ "tenant" => "acme", "trace.id" => "t" }, sink.payloads[1])
    end

    test "a sink missing one of the eight methods is refused at construction, naming it" do
      partial = ::Object.new
      %i[debug info warn error debug? info? warn?].each do |name|
        partial.define_singleton_method(name) { |*| nil }
      end
      error = assert_raises(Dexpace::InvalidArgumentError) { Logger.build(sink: partial) }

      assert_match(/lacks #error\?/, error.message)
      assert_raises(Dexpace::InvalidArgumentError) { Logger.build(context: "not a hash") }
      assert_raises(Dexpace::InvalidArgumentError) { Logger.build(diagnostic_keys: "trace.id") }
      assert_raises(Dexpace::InvalidArgumentError) { Logger.build(diagnostic_keys: [1]) }
      assert_raises(Dexpace::InvalidArgumentError) { Logger.build(redactor: nil) }
      refute_respond_to(Logger, :new)
    end

    # OBS-8's latch mutex is shared by every event of one logger and released before any sink
    # call, so two events emitting on two threads through one logger are independent.
    test "OBS-8: two events from one logger emit concurrently, once each" do
      sink = RecordingSink.new
      logger = Logger.build(sink: sink)
      gate = ::Thread::Queue.new
      threads = Array.new(2) do |index|
        ::Thread.new do
          event = logger.event(Severity::INFO).field("n", index)
          gate.pop
          event.emit
          event.emit
        end
      end
      2.times { gate << true }
      threads.each(&:join)

      assert_equal([0, 1], sink.payloads.map { |payload| payload["n"] }.sort)
    end
  end
end
