# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../page"
require_relative "../model"
require_relative "../http/request"

module Dexpace
  class Page
    # PAGE-4's PageInfo: what a strategy's #parse returns -- the page's items plus the fully-formed
    # request for the next page, or nil for end-of-stream.
    #
    # `next_request == nil` is the single, exclusive end-of-stream signal, and there is no second
    # one: no `terminal?` flag, no sentinel and no exception path, which is PAGE-4's prohibition
    # made structural. .terminal is the named factory for that case so a strategy author never
    # writes `next_request: nil` by hand and never mistakes an empty items list for termination:
    # an empty list paired with a non-nil next request is a valid NON-terminal page, and the
    # factory names the other one.
    #
    # The items Array is copied shallowly and frozen -- the collection is the model's, its
    # elements stay the caller's domain objects (P7-101); Model.own's deep copy would replace
    # them, freeze them and raise on a Proc. The two optional keys are PAGE-34's: a strategy that
    # found a next link or a continuation token records it here so the Page it becomes carries
    # them for the fetcher front-end.
    class Info < ::Data.define(:items, :next_request, :next_link, :continuation_token)
      include Model

      private_class_method :new

      # The validating factory every construction path goes through.
      #
      # @param items [Array] the page's items, possibly empty, never nil
      # @param next_request [Dexpace::Request, nil] nil is the end-of-stream signal (PAGE-4)
      # @param next_link [String, nil] PAGE-34's next link, when the source carried one
      # @param continuation_token [String, nil] PAGE-34's fallback key
      # @return [Dexpace::Page::Info]
      # @raise [Dexpace::InvalidArgumentError] on a nil or non-Array items, a next_request that is
      #   not a Dexpace::Request, or a non-String link or token
      def self.build(items:, next_request:, next_link: nil, continuation_token: nil)
        new(items: items, next_request: next_request, next_link: next_link,
            continuation_token: continuation_token,)
      end

      # The end-of-stream page: these items and no next request.
      #
      # @param items [Array] the last page's items, empty by default
      # @return [Dexpace::Page::Info]
      def self.terminal(items: [])
        build(items: items, next_request: nil)
      end

      def initialize(items:, next_request:, next_link:, continuation_token:)
        unless Model.required!("items", items).is_a?(::Array)
          raise InvalidArgumentError, "items must be an Array, got #{items.class}"
        end
        unless next_request.nil? || next_request.is_a?(Dexpace::Request)
          raise InvalidArgumentError,
                "next_request must be a Dexpace::Request or nil, got #{next_request.class}"
        end

        super(items: items.dup.freeze, next_request: next_request,
              next_link: optional_string("next_link", next_link),
              continuation_token: optional_string("continuation_token", continuation_token),)
      end

      private

      # nil, or a frozen copy of the String (XCUT-15); anything else is named and refused.
      def optional_string(name, value)
        return nil if value.nil?
        return Model.frozen_string(value) if value.is_a?(::String)

        raise InvalidArgumentError, "#{name} must be a String or nil, got #{value.class}"
      end
    end
  end
end
