# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/allocation_delta"
require_relative "../../support/recording_meter"
require "dexpace"

# OBS-31, OBS-33, OBS-30: the no-op meter and its two shared instrument singletons, the
# discarding counter and histogram, and the structural concurrency safety of frozen stateless
# objects. OBS-31's per-measurement recording is asserted against RecordingMeter, because core
# ships no recording meter (P5-48). OBS-32 is post-v1 and no instrument name appears here.
class DexpaceInstrumentationMeterTest < DexpaceTestCase
  include AllocationDelta

  NO_METER = Dexpace::Instrumentation::NO_METER
  FROZEN_ATTRS = { "http.request.method" => "GET" }.freeze

  # "returns shared instrument singletons" is a reference-identity claim, and it is asserted
  # meter-to-meter under DIFFERENT names -- the same name proves memoisation, not sharing.
  test "OBS-31: NO_METER returns one shared counter and one shared histogram, whatever the name" do
    counter = NO_METER.create_counter("requests_total")
    histogram = NO_METER.create_histogram("duration_ms", unit: "ms", description: "latency")

    assert_same(counter, NO_METER.create_counter("bytes_total", unit: "By"))
    assert_same(histogram, NO_METER.create_histogram("size_bytes"))
    refute_same(counter, histogram)
    assert_predicate(NO_METER, :frozen?)
    assert_predicate(counter, :frozen?)
    assert_predicate(histogram, :frozen?)
  end

  test "OBS-31: the meter and its instruments are private classes behind public singletons" do
    %i[NoMeter NoCounter NoHistogram NO_COUNTER NO_HISTOGRAM].each do |name|
      refute_includes(Dexpace::Instrumentation.constants(false), name, "#{name} leaked")
    end
    assert_raises(::NameError) { Dexpace::Instrumentation::NO_COUNTER }
    assert_equal(
      %i[create_counter create_histogram], NO_METER.class.public_instance_methods(false).sort,
    )
    assert_equal([:add], NO_METER.create_counter("c").class.public_instance_methods(false))
    assert_equal([:record], NO_METER.create_histogram("h").class.public_instance_methods(false))
  end

  # OBS-33: no hot-path validation. A negative delta is the caller's undefined behaviour and is
  # discarded like any other; assert_nil on the return value, never assert_nothing_raised
  # (testing/26b866e1) -- the stronger claim a discarding instrument actually makes.
  test "OBS-33: the no-op counter discards every increment, negative ones included, unchecked" do
    counter = NO_METER.create_counter("test")

    assert_nil(counter.add(1))
    assert_nil(counter.add(10, attributes: FROZEN_ATTRS))
    assert_nil(counter.add(0))
    assert_nil(counter.add(-1))
    assert_nil(counter.add(2.5))
  end

  test "OBS-33: the no-op histogram tolerates NaN, +/-Infinity, zero and a negative" do
    histogram = NO_METER.create_histogram("test")

    assert_nil(histogram.record(::Float::NAN))
    assert_nil(histogram.record(::Float::INFINITY))
    assert_nil(histogram.record(-::Float::INFINITY))
    assert_nil(histogram.record(0))
    assert_nil(histogram.record(-1))
    assert_nil(histogram.record(42.5, attributes: FROZEN_ATTRS))
  end

  test "P5-42: every attributes and descriptor parameter is a named keyword, never a ** splat" do
    assert_equal(
      [%i[req name], %i[key unit], %i[key description]],
      NO_METER.method(:create_counter).parameters,
    )
    assert_equal(
      [%i[req name], %i[key unit], %i[key description]],
      NO_METER.method(:create_histogram).parameters,
    )
    assert_equal(
      [%i[req amount], %i[key attributes]],
      NO_METER.create_counter("c").method(:add).parameters,
    )
    assert_equal(
      [%i[req amount], %i[key attributes]],
      NO_METER.create_histogram("h").method(:record).parameters,
    )
  end

  # OBS-30: an identity test across threads, not a stress test -- the property, not the absence
  # of a race, which no test can show.
  test "OBS-30: sixteen threads get the same meter, counter and histogram" do
    counters = Array.new(16)
    histograms = Array.new(16)
    threads = Array.new(16) do |i|
      ::Thread.new do
        counters[i] = NO_METER.create_counter("c_#{i}")
        histograms[i] = NO_METER.create_histogram("h_#{i}")
      end
    end
    threads.each(&:join)

    assert_equal(1, counters.uniq.size)
    assert_equal(1, histograms.uniq.size)
    assert_same(NO_METER.create_counter("x"), counters.first)
  end

  # OBS-25 reaches the metrics half through OBS-31's "shared instrument singletons": creating and
  # driving the instruments allocates nothing per call. Frozen constants only cross the loop.
  test "OBS-31: creating and driving the no-op instruments allocates nothing per call" do
    per_call = allocations_per_call do
      NO_METER.create_counter("c", unit: "{request}").add(1, attributes: FROZEN_ATTRS)
      NO_METER.create_histogram("h", unit: "ms").record(12, attributes: FROZEN_ATTRS)
    end

    assert_in_delta(0.0, per_call, 0.0, "the no-op metrics path allocates per call")
  end

  # OBS-31's recording half, on the fake that deliberately lacks the sharing property (P5-48).
  test "OBS-31: a recording meter records each measurement with its attributes" do
    meter = Dexpace::RecordingMeter.new
    counter = meter.create_counter("count", unit: "{request}")
    histogram = meter.create_histogram("duration", unit: "ms")

    assert_nil(counter.add(1, attributes: FROZEN_ATTRS))
    assert_nil(histogram.record(12.3, attributes: FROZEN_ATTRS))
    assert_equal([{ amount: 1, attributes: FROZEN_ATTRS }], counter.records)
    assert_in_delta(12.3, histogram.records.first[:amount])
    assert_equal("{request}", counter.unit)
    assert_equal("ms", histogram.unit)
    refute_same(counter, meter.create_counter("count", unit: "{request}"))
  end
end
