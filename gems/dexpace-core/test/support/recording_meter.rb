# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # A recording _Meter: returns a FRESH instrument per #create_counter / #create_histogram call,
  # deliberately without the shared-singleton property OBS-31 gives the no-op meter, so the
  # no-op's property is asserted against a fake that does not have it. Records the instruments it
  # made; each instrument records `{ amount:, attributes: }` per measurement. Core ships no
  # recording meter (P5-48). Phase 5b's step tests read `meter.counters` and `meter.histograms`.
  # Not public API; see recording_span.rb for why the doubles are namespaced.
  class RecordingMeter
    attr_reader :counters, :histograms

    def initialize
      @counters = []
      @histograms = []
    end

    def create_counter(name, unit: nil, description: nil)
      counter = RecordingCounter.new(name: name, unit: unit, description: description)
      @counters << counter
      counter
    end

    def create_histogram(name, unit: nil, description: nil)
      histogram = RecordingHistogram.new(name: name, unit: unit, description: description)
      @histograms << histogram
      histogram
    end
  end

  # A recording _Counter. Records every increment as given: OBS-33 makes a negative delta the
  # caller's undefined behaviour and forbids hot-path validation, so this fake validates nothing
  # either and a test can observe what a careless caller sent.
  class RecordingCounter
    attr_reader :name, :unit, :description, :records

    def initialize(name:, unit: nil, description: nil)
      @name = name
      @unit = unit
      @description = description
      @records = []
    end

    def add(amount, attributes: nil)
      @records << { amount: amount, attributes: attributes }.freeze
      nil
    end
  end

  # A recording _Histogram. Tolerates any input the way OBS-33 demands, recording it verbatim.
  class RecordingHistogram
    attr_reader :name, :unit, :description, :records

    def initialize(name:, unit: nil, description: nil)
      @name = name
      @unit = unit
      @description = description
      @records = []
    end

    def record(amount, attributes: nil)
      @records << { amount: amount, attributes: attributes }.freeze
      nil
    end
  end
end
