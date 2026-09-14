# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"

module Dexpace
  # Per-call operational overrides that are not part of the wire form (HTTP-34, HTTP-35).
  #
  # Every field defaults to the `nil` "use the default" sentinel and EMPTY is the canonical
  # "override nothing", so a call that overrides nothing allocates nothing. `timeout` is a Float
  # of SECONDS, matching every Ruby socket API so no unit conversion sits between the model and
  # the wire (design §4). These are operational knobs, deliberately outside the wire model
  # (HTTP-6), which is why they are a separate type rather than members of Request.
  class RequestOptions < Data.define(:timeout, :max_retries, :tags)
    include Model

    private_class_method :new

    # The validating factory; `tags` is copied and deep-frozen, never aliased (HTTP-34).
    def self.build(timeout:, max_retries:, tags:)
      Model.required!("tags", tags)
      new(timeout: timeout, max_retries: max_retries, tags: Model.own(tags))
    end

    # A builder overriding nothing.
    def self.builder
      Builder.new
    end

    # HTTP-35's two rejections live here, not in the builder, because `.build` is public and
    # #with routes through it: a rule enforced only in Builder#build would let
    # `options.with(timeout: -1)` produce a model the builder would have refused.
    def initialize(timeout:, max_retries:, tags:)
      validate_timeout!(timeout)
      validate_max_retries!(max_retries)
      validate_tags!(tags)
      super(timeout: timeout.nil? ? nil : Float(timeout), max_retries: max_retries, tags: tags)
    end

    # HTTP-3: a builder pre-filled from this instance, with a copy of the tags.
    def new_builder
      Builder.new(timeout: timeout, max_retries: max_retries, tags: tags)
    end

    # The validators are made private by name, below them, so EMPTY can follow them: it calls
    # `.build`, which runs them, and a constant after a bare `private` reads as scoped when it is
    # not.
    #
    # Zero is refused as well as a negative: zero means "no timeout" in one transport and
    # "fail at once" in another, so it cannot be a portable override.
    def validate_timeout!(timeout)
      return if timeout.nil? || (timeout.is_a?(Numeric) && timeout.positive?)

      raise InvalidArgumentError,
            "timeout must be a positive number of seconds, or nil to use the default (HTTP-35)"
    end

    # 0 is legal and means "disable retries for this call"; only a negative count is a mistake.
    def validate_max_retries!(max_retries)
      return if max_retries.nil? || (max_retries.is_a?(Integer) && !max_retries.negative?)

      raise InvalidArgumentError, "max_retries must be a non-negative integer (HTTP-35)"
    end

    def validate_tags!(tags)
      return if tags.is_a?(Hash) && tags.all? { |pair| pair.all?(String) }

      raise InvalidArgumentError, "tags must be a Hash of String keys to String values (HTTP-34)"
    end

    private :validate_timeout!, :validate_max_retries!, :validate_tags!

    # The canonical "override nothing" (HTTP-34).
    EMPTY = build(timeout: nil, max_retries: nil, tags: {})
  end
end
