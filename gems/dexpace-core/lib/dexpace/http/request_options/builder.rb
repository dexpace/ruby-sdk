# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../builder"
require_relative "../../error/invalid_argument_error"

module Dexpace
  class RequestOptions
    # The mutable assembler for a RequestOptions (HTTP-34, HTTP-35).
    #
    # The writers refuse a value of the wrong type at once; the range rules -- a positive
    # timeout, a non-negative max-retries -- live in the model, where `.build` and #with also
    # meet them, so #build is a plain delegation.
    class Builder
      include Dexpace::Builder

      # HTTP-3: a builder pre-filled from a model copies the tags rather than aliasing them.
      def initialize(timeout: nil, max_retries: nil, tags: {})
        @timeout = timeout
        @max_retries = max_retries
        @tags = tags.dup
      end

      # A number of seconds, or nil to use the default.
      def timeout=(seconds)
        unless seconds.nil? || seconds.is_a?(Numeric)
          raise InvalidArgumentError, "timeout must be a number of seconds or nil"
        end

        @timeout = seconds
      end

      # A retry count, or nil to use the default; 0 disables retries for the call (HTTP-35).
      def max_retries=(count)
        unless count.nil? || count.is_a?(Integer)
          raise InvalidArgumentError, "max_retries must be an Integer or nil"
        end

        @max_retries = count
      end

      # Sets one opaque tag; a later value under the same key replaces the earlier one.
      def tag(key, value)
        unless key.is_a?(String) && value.is_a?(String)
          raise InvalidArgumentError, "a tag is a String key and a String value (HTTP-34)"
        end

        @tags[key] = value
        self
      end

      # The frozen model; the builder stays usable and later mutation does not reach it.
      def build
        RequestOptions.build(timeout: @timeout, max_retries: @max_retries, tags: @tags)
      end
    end
  end
end
