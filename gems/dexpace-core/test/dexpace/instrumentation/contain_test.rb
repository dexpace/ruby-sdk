# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_sink"
require_relative "../../../lib/dexpace/instrumentation/contain"

# Exercises: OBS-20, XCUT-20
#
# The one failure-containment primitive: a module function (P5-37), so a containment cannot
# migrate to the sink the way a `logger.contain { }` would invite. Nothing here is asserted with
# assert_nothing_raised (testing/26b866e1): every totality claim is asserted on the diagnostic
# that was emitted, or on the nil that came back.
class DexpaceInstrumentationContainTest < DexpaceTestCase
  Instrumentation = Dexpace::Instrumentation
  Logger = Dexpace::Instrumentation::Logger
  Events = Dexpace::Instrumentation::Events
  Keys = Dexpace::Instrumentation::Keys

  test "OBS-20: the block runs, its value is swallowed, and nil comes back" do
    sink = RecordingSink.new
    ran = false

    logger = Logger.build(sink: sink)
    result = Instrumentation.contain(logger, event: Events::INSTRUMENTATION_LOG) do
      ran = true
      :value_a_caller_must_not_branch_on
    end

    assert(ran)
    assert_nil(result)
    assert_empty(sink.entries)
  end

  test "OBS-20: a StandardError from the block becomes a WARNING diagnostic carrying the cause" do
    sink = RecordingSink.new

    logger = Logger.build(sink: sink)
    result = Instrumentation.contain(logger, event: Events::INSTRUMENTATION_LOG) do
      raise ::IOError, "network stream severed"
    end

    assert_nil(result)
    assert_equal(1, sink.entries.size)
    assert_equal(:warn, sink.entries.first.severity)
    payload = sink.payloads.first

    assert_equal(Events::INSTRUMENTATION_LOG, payload[Keys::EVENT])
    assert_equal("IOError: network stream severed", payload[Keys::CAUSE])
  end

  test "OBS-20: the diagnostic carries the event name it was given, whichever of the five" do
    sink = RecordingSink.new
    logger = Logger.build(sink: sink)
    [Events::INSTRUMENTATION_CLOSE, Events::INSTRUMENTATION_HOOK, Events::INSTRUMENTATION_CONFIG,
     Events::INSTRUMENTATION_SHUTDOWN,].each do |name|
      Instrumentation.contain(logger, event: name) { raise "x" }
    end

    assert_equal([Events::INSTRUMENTATION_CLOSE, Events::INSTRUMENTATION_HOOK,
                  Events::INSTRUMENTATION_CONFIG, Events::INSTRUMENTATION_SHUTDOWN,],
                 sink.payloads.map { |payload| payload[Keys::EVENT] },)
    sink.payloads.each do |payload|
      assert_operator(payload[Keys::EVENT], :start_with?, Events::INSTRUMENTATION_PREFIX)
    end
  end

  # "a secondary failure while emitting that diagnostic MUST be swallowed": a sink that raises on
  # every call, the diagnostic included. The assertion is the nil and the absence of a raise
  # reaching here -- and it is the case that fails if the inner rescue is written as a bare
  # `rescue nil` in a place Ruby parses differently than intended.
  test "OBS-20: a secondary failure while emitting the diagnostic is swallowed" do
    exploding = ::Object.new
    %i[debug? info? warn? error?].each { |name| exploding.define_singleton_method(name) { true } }
    %i[debug info warn error].each do |name|
      exploding.define_singleton_method(name) { |*| raise ::StandardError, "sink failure" }
    end
    logger = Logger.build(sink: exploding)

    result = Instrumentation.contain(logger, event: Events::INSTRUMENTATION_LOG) do
      raise ::ArgumentError, "primary error"
    end

    assert_nil(result)
  end

  test "OBS-20: a sink whose predicate itself raises is contained too" do
    hostile = ::Object.new
    %i[debug info warn error debug? info? warn? error?].each do |name|
      hostile.define_singleton_method(name) { |*| raise "hostile #{name}" }
    end
    logger = Logger.build(sink: hostile)

    assert_nil(Instrumentation.contain(logger, event: Events::INSTRUMENTATION_LOG) { raise "x" })
  end

  test "OBS-20: with Logger::NULL the failure is contained and nothing is produced" do
    result = Instrumentation.contain(Logger::NULL, event: Events::INSTRUMENTATION_LOG) { raise "x" }

    assert_nil(result)
  end

  # The rescue is StandardError and never Exception: a SignalException, a NoMemoryError or a
  # ScriptError inside a log line is not a logging failure to swallow.
  test "OBS-20, XCUT-20: only StandardError is contained; a non-StandardError propagates" do
    sink = RecordingSink.new
    logger = Logger.build(sink: sink)

    assert_raises(::SignalException) do
      Instrumentation.contain(logger, event: Events::INSTRUMENTATION_LOG) { raise ::SignalException, "TERM" }
    end
    assert_raises(::NotImplementedError) do
      Instrumentation.contain(logger, event: Events::INSTRUMENTATION_LOG) { raise ::NotImplementedError }
    end
    assert_empty(sink.entries)
  end

  test "P5-37: contain is a module function on Instrumentation, not a method on Logger or Event" do
    assert_respond_to(Instrumentation, :contain)
    refute_respond_to(Logger::NULL, :contain)
    refute_respond_to(Dexpace::Instrumentation::Event::INERT, :contain)
    assert_raises(Dexpace::InvalidArgumentError) { Instrumentation.contain(Logger::NULL, event: "x") }
  end
end
