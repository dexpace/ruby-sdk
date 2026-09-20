# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../page"
require_relative "../model"
require_relative "info"
require_relative "query_rewriter"

module Dexpace
  class Page
    # PAGE-17: the page-number strategy. An empty items list is end-of-stream, checked FIRST and
    # before anything else is computed -- defensive against a server that returns an empty page
    # past the end. Otherwise the current page is read from the ORIGINATING (executed) request's
    # page parameter, which in this port is `response.request` and not the template: after a
    # redirect chain the executed request is the final hop's, and it is the one the server
    # answered. An absent, empty or non-numeric value falls back to the configurable start page
    # (default 1; 0 is permitted for 0-based servers), and the next request is the template with
    # `current + 1` spliced into its page parameter (default `page`).
    #
    # The numeric screen is one anchored ASCII-digit pattern compiled once with its own
    # `Regexp.new(source, timeout:)` -- per-pattern, never the process-global `Regexp.timeout` a
    # library must not impose on its host (design §4). `[0-9]` rather than `\d`, so a non-ASCII
    # digit is "non-numeric" and falls back, as the requirement's garbage case asks. The extractor
    # is `#call(response) -> items` and is not rescued (PAGE-4; see CursorStrategy). A frozen Data
    # with no instance state (PAGE-5).
    class PageNumberStrategy < ::Data.define(:extract_items, :parameter, :start)
      include Model

      private_class_method :new

      DIGITS = ::Regexp.new("\\A[0-9]+\\z", timeout: 1.0)
      private_constant :DIGITS

      # @param extract_items [#call] `#call(response) -> items`
      # @param parameter [String] the page-number query parameter's name
      # @param start [Integer] the first page's number; 0 for a 0-based server
      # @return [Dexpace::Page::PageNumberStrategy] frozen
      # @raise [Dexpace::InvalidArgumentError] when the extractor is not callable, the parameter is
      #   not a non-empty String, or the start is not a non-negative Integer
      def self.build(extract_items:, parameter: "page", start: 1)
        new(extract_items: extract_items, parameter: parameter, start: start)
      end

      def initialize(extract_items:, parameter:, start:)
        unless Model.required!("extract_items", extract_items).respond_to?(:call)
          raise InvalidArgumentError,
                "extract_items must respond to #call, got #{extract_items.class}"
        end
        unless parameter.is_a?(::String) && !parameter.empty?
          raise InvalidArgumentError,
                "parameter must be a non-empty String, got #{parameter.inspect}"
        end
        unless start.is_a?(::Integer) && !start.negative?
          raise InvalidArgumentError, "start must be a non-negative Integer, got #{start.inspect}"
        end

        super(extract_items: extract_items, parameter: Model.frozen_string(parameter), start: start)
      end

      # @param response [Dexpace::Response] read once, through the extractor, never closed here
      # @param template [Dexpace::Request] the original request the next one is derived from
      # @return [Dexpace::Page::Info]
      # @raise [Dexpace::InvalidArgumentError] when the extractor's answer is not an Array
      def parse(response, template)
        items = extract_items.call(response)
        unless items.is_a?(::Array)
          raise InvalidArgumentError, "the extractor's items must be an Array, got #{items.class}"
        end
        return Info.terminal(items: items) if items.empty?

        url = QueryRewriter.rewrite_url(template.url, parameter, (current_page(response) + 1).to_s)
        Info.build(items: items, next_request: template.with(url: url))
      end

      private

      # The executed request's page number, or `start` when the parameter is absent, empty or
      # not a run of ASCII digits.
      def current_page(response)
        value = QueryRewriter.get(response.request.url.query, parameter)
        value.nil? || !DIGITS.match?(value) ? start : value.to_i
      end
    end
  end
end
