# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # A recording _Span: the one core does not ship (P5-48). Every OBS-21 recording-branch
  # assertion and every OBS-22 nesting assertion runs against this, because NO_SPAN records
  # nothing and a nesting test written over one span passes under an implementation that never
  # restores anything. A real in-memory implementation and not a recorder of calls -- a fake by
  # testing/7ecef8e8's definition -- with `recording: false` giving the non-recording variant
  # OBS-23's delegation test needs, since NO_SPAN in that role is already the slot's occupant.
  #
  # `finished_at` is an Array, not a value: OBS-21's "call end() twice and assert no duplicate
  # export" is assertable only against something that could have exported twice, and a
  # one-element array after two #finish calls is that assertion. Phase 5b's step tests consume
  # this class by this name and read `span.finished_at`; a rename here is a rename there.
  #
  # Namespaced under Dexpace, against the tree's top-level convention for doubles (FakeTransport,
  # ProbeStep, RecordingBody), because 5b's plan names all six of the recording doubles as
  # Dexpace::Recording* and a plan may not be edited from here (checklist, deviations).
  # It lives in dexpace-core's test tree and is not public API.
  class RecordingSpan
    attr_reader :attributes, :events, :errors, :status, :finished_at, :context

    def initialize(recording: true, context: nil)
      @recording = recording
      @context = context
      @attributes = {}
      @events = []
      @errors = []
      @status = nil
      @finished_at = []
    end

    def recording?
      @recording
    end

    def set_attribute(key, value)
      @attributes[key] = value if @recording
      self
    end

    def add_event(name, attributes: nil)
      @events << { name: name, attributes: attributes }.freeze if @recording
      self
    end

    def record_error(error, attributes: nil)
      @errors << { error: error, attributes: attributes }.freeze if @recording
      self
    end

    def status=(status)
      @status = status if @recording
      status
    end

    def finish(end_timestamp: nil)
      return nil unless @recording
      return nil unless @finished_at.empty?

      @finished_at << (end_timestamp || ::Time.now).freeze
      nil
    end
  end
end
