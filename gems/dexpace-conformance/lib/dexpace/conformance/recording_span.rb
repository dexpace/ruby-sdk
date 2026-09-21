# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    # OBS-21's RECORDING branch, which core's own NO_SPAN cannot demonstrate because it is always
    # non-recording: a real in-memory span over phase 5c's `_Span` protocol -- `recording?`, the
    # three mutators, `status=`, `finish(end_timestamp:)` and `context` -- that records every
    # mutation while live and goes inert after #finish, which is OBS-21's idempotence clause and
    # its post-finish-mutation clause in one object. Shipped here rather than in core's test tree
    # because phase 5c assigned it to the conformance gem and a third-party adapter author
    # asserting OBS-21 needs it to ship; `recording: false` is the non-recording variant OBS-23's
    # delegation assertions need.
    #
    # `finished_at` is an Array, not a value: "call end() twice and assert no duplicate export" is
    # assertable only against something that could have exported twice, and a one-element array
    # after two #finish calls is that assertion.
    class RecordingSpan
      # @return [Hash{String => Object}] every attribute set while recording
      attr_reader :attributes
      # @return [Array<Hash>] every event added while recording, as `{name:, attributes:}`
      attr_reader :events
      # @return [Array<Hash>] every error recorded while recording, as `{error:, attributes:}`
      attr_reader :errors
      # @return [Object, nil] the last status set while recording
      attr_reader :status
      # @return [Array<Time>] the finish timestamps: at most one, however often #finish was called
      attr_reader :finished_at
      # @return [Object, nil] whatever the constructor was given as the span's context
      attr_reader :context

      # @param recording [Boolean] false for the inert, non-recording variant
      # @param context [Object, nil] what #context answers (a Bundle, for a real span)
      def initialize(recording: true, context: nil)
        @recording = recording ? true : false
        @context = context
        @attributes = {}
        @events = []
        @errors = []
        @status = nil
        @finished_at = []
      end

      # OBS-21's flag: true until #finish, and never for the non-recording variant.
      #
      # @return [Boolean]
      def recording?
        @recording && @finished_at.empty?
      end

      # @param key [String]
      # @param value [Object]
      # @return [self]
      def set_attribute(key, value)
        @attributes[key] = value if recording?
        self
      end

      # @param name [String]
      # @param attributes [Hash, nil]
      # @return [self]
      def add_event(name, attributes: nil)
        @events << { name: name, attributes: attributes }.freeze if recording?
        self
      end

      # @param error [Exception]
      # @param attributes [Hash, nil]
      # @return [self]
      def record_error(error, attributes: nil)
        @errors << { error: error, attributes: attributes }.freeze if recording?
        self
      end

      # @param status [Object]
      # @return [Object] the status given
      def status=(status)
        @status = status if recording?
        status
      end

      # Idempotent: the first call records one timestamp and every later call records nothing.
      #
      # @param end_timestamp [Time, nil] defaults to now
      # @return [nil]
      def finish(end_timestamp: nil)
        return nil unless recording?

        @finished_at << (end_timestamp || ::Time.now).freeze
        nil
      end
    end
  end
end
