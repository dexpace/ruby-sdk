# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  module SSE
    # One parsed server-sent event: the five tracked fields of one block (SSE-13) -- `id`,
    # `event`, `data`, `comment` and `retry` -- as an immutable value (SSE-20) with structural
    # equality, hash and string form over all five (SSE-21).
    #
    # `data` is the ordered list of raw per-line values exactly as the wire carried them, never
    # joined (SSE-8): joining with "\n" is the typed layer's (SSE-33). `event` is the raw field,
    # nil when the block sent none and NEVER defaulted to "message" (SSE-10); `id` is the block's
    # own and never a carried last-event-id (SSE-16); `retry` is a non-negative millisecond count
    # a caller may act on and the SDK never does (SSE-38). A present-but-empty field is "" or [""],
    # distinct from an absent nil (SSE-4).
    #
    # SSE-20's defensive copy is Model.own -- Ractor.make_shareable(list, copy: true), a
    # deep-frozen copy -- taken in #initialize, so neither the list the parser accumulated into
    # nor a caller's later mutation reaches inside a constructed event; and SSE-20's
    # copy-with-changes clause is Dexpace::Model#with, which routes through .build and therefore
    # through the same copy, on every supported Ruby. No bespoke #with is written here: Data#with
    # shares members and skips an #initialize override on the 3.2 floor (data-modeling/83610619).
    # The member is named `retry`, after the wire field: a Ruby keyword is an ordinary method name
    # on a receiver, and RBS accepts it (open question 1, closed on every row).
    class Event < ::Data.define(:id, :event, :data, :comment, :retry)
      include Model

      private_class_method :new, :[]

      # The validating factory every construction path goes through, absent fields defaulting
      # to absent.
      #
      # @param id [String, nil] the block's own id, verbatim (SSE-9)
      # @param event [String, nil] the raw event name; nil when none was sent (SSE-10)
      # @param data [Array<String>] the raw data lines in wire order, unjoined (SSE-8)
      # @param comment [String, nil] the block's last comment (SSE-6)
      # @param retry [Integer, nil] the accepted retry hint in milliseconds (SSE-11)
      # @return [Event] frozen, owning a deep-frozen copy of `data`
      # @raise [Dexpace::InvalidArgumentError] naming the first field of the wrong shape
      def self.build(id: nil, event: nil, data: [], comment: nil, retry: nil)
        new(id:, event:, data:, comment:, retry:)
      end

      # HTTP-4's field-named validation. Each String is copied and frozen (XCUT-15) and the list
      # is deep-copied and frozen once, here, so every accessor returns the same frozen reference
      # with no per-access wrapper. The bare `super` forwards the (re-assigned) keywords. The
      # retry hint is validated AFTER `super`, through its reader: `retry` is a Ruby keyword, so
      # `retry = ...` parses as the retry statement and `super(retry: retry)` does not parse at
      # all, while an Integer needs no transformation and the reader is the one allocation-free
      # way to read the parameter.
      def initialize(id:, event:, data:, comment:, retry:)
        id = optional_string!("id", id)
        event = optional_string!("event", event)
        data = Model.own(list!(data))
        comment = optional_string!("comment", comment)
        super
        duration!("retry", self.retry)
      end

      # SSE-22: true only when all five fields are UNSET -- a nil id, event, comment and retry and
      # an empty data list. A present-but-empty field is not unset (SSE-4), so an event whose only
      # field is `event: ""` or `data: [""]` is not empty, and a comment-only keep-alive is not
      # empty either, because a comment counts as content (SSE-6).
      def empty?
        id.nil? && event.nil? && data.empty? && comment.nil? && self.retry.nil?
      end

      private

      def optional_string!(name, value)
        return nil if value.nil?
        return Model.frozen_string(value) if value.is_a?(::String)

        raise InvalidArgumentError, "#{name} must be a String or nil, got #{value.class}"
      end

      def list!(value)
        unless value.is_a?(::Array) && value.all?(::String)
          raise InvalidArgumentError, "data must be an Array of Strings, got #{value.inspect}"
        end

        value
      end

      def duration!(name, value)
        return if value.nil? || (value.is_a?(::Integer) && !value.negative?)

        raise InvalidArgumentError,
              "#{name} must be a non-negative Integer of milliseconds or nil, got #{value.inspect}"
      end
    end
  end
end
