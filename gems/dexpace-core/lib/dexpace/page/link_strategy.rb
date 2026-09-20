# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../page"
require_relative "../model"
require_relative "info"
require_relative "link_header"

module Dexpace
  class Page
    # PAGE-18, PAGE-19, PAGE-20: the Link-header strategy. The items come out of a caller-supplied
    # `#call(response) -> items` extractor; the next request comes from the response's Link
    # header(s), read under the fold through Headers#[] -- every instance the server sent, which
    # LinkHeader joins and scans by RFC 8288's grammar for the first link-value whose `rel` carries
    # the token `next` -- and resolved through Dexpace::Page.next_request_from against the
    # originating page's response URL, which is where PAGE-19's three end-of-stream routes live: a
    # blank target (P7-5), an unresolvable one, and one this client cannot dispatch (P7-104). No
    # header, no rel=next segment, or any of the three, is end-of-stream and never an error. The
    # header name is configurable and defaults to `Link`.
    #
    # The raw target travels as the Info's `next_link`, so the fetcher front-end's PAGE-34 key is
    # available on pages this strategy produced. The extractor is not rescued (PAGE-4). A frozen
    # Data with no instance state (PAGE-5).
    class LinkStrategy < ::Data.define(:extract_items, :header)
      include Model

      private_class_method :new

      # @param extract_items [#call] `#call(response) -> items`
      # @param header [String] the header to read the link-values from
      # @return [Dexpace::Page::LinkStrategy] frozen
      # @raise [Dexpace::InvalidArgumentError] when the extractor is not callable or the header
      #   name is not a non-empty String
      def self.build(extract_items:, header: "Link")
        new(extract_items: extract_items, header: header)
      end

      def initialize(extract_items:, header:)
        unless Model.required!("extract_items", extract_items).respond_to?(:call)
          raise InvalidArgumentError,
                "extract_items must respond to #call, got #{extract_items.class}"
        end
        unless header.is_a?(::String) && !header.empty?
          raise InvalidArgumentError, "header must be a non-empty String, got #{header.inspect}"
        end

        super(extract_items: extract_items, header: Model.frozen_string(header))
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

        target = LinkHeader.next_target(response.headers[header])
        next_request = Dexpace::Page.next_request_from(template, response, target)
        return Info.terminal(items: items) if next_request.nil?

        Info.build(items: items, next_request: next_request, next_link: target)
      end
    end
  end
end
