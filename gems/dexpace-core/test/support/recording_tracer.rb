# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "recording_span"

module Dexpace
  # A recording _TracerFactory whose #tracer returns a FRESH RecordingTracer per call: OBS-29's
  # "one tracer instance corresponds 1:1 to a single logical operation lifecycle" made testable
  # (P5-43), against a NO_TRACER_FACTORY that returns one shared object by design. The parameter
  # list is 4a's five-argument mirror of opentelemetry-api's TracerProvider#tracer (P4-8), so a
  # caller written against either shape reaches this fake the same way; SEAM-28's stable
  # operation identifier arrives as `name` (or the legacy positional) and is kept on the tracer.
  # Phase 5b's step tests read `factory.tracers`. Not public API; see recording_span.rb for why
  # the doubles are namespaced.
  class RecordingTracerFactory
    attr_reader :tracers

    def initialize
      @tracers = []
    end

    def tracer(deprecated_name = nil, deprecated_version = nil, name: nil, version: nil,
               attributes: nil)
      tracer = RecordingTracer.new(
        name: name || deprecated_name, version: version || deprecated_version,
        attributes: attributes,
      )
      @tracers << tracer
      tracer
    end
  end

  # A recording _Tracer: #start_span returns a fresh RecordingSpan carrying the span name and
  # the attributes it was started with, and #in_span yields one. Records every span it started
  # so a test can assert what an operation did with it.
  class RecordingTracer
    attr_reader :name, :version, :attributes, :spans

    def initialize(name: nil, version: nil, attributes: nil)
      @name = name
      @version = version
      @attributes = attributes
      @spans = []
    end

    def start_span(name, attributes: nil, kind: nil, with_parent: nil)
      span = RecordingSpan.new
      span.set_attribute("span.name", name)
      span.set_attribute("span.kind", kind) unless kind.nil?
      span.set_attribute("span.parent", with_parent) unless with_parent.nil?
      attributes&.each { |key, value| span.set_attribute(key, value) }
      @spans << span
      span
    end

    def in_span(name, attributes: nil, kind: nil)
      span = start_span(name, attributes: attributes, kind: kind)
      return span unless block_given?

      begin
        yield span
      ensure
        span.finish
      end
    end
  end
end
