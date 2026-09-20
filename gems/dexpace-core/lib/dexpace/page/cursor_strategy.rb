# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../page"
require_relative "../model"
require_relative "info"
require_relative "query_rewriter"

module Dexpace
  class Page
    # PAGE-16: the cursor strategy. Items and the next cursor come out of ONE call to a
    # caller-supplied extractor, `#call(response) -> [items, cursor]`; a nil or empty cursor is
    # end-of-stream; otherwise the next request is the template with the configurable cursor
    # parameter (default `cursor`) spliced into its query through QueryRewriter -- replacing an
    # earlier value in place, never appending a second (PAGE-23).
    #
    # An extractor, and never a codec or a witness (R7, P7-6): a keyword naming a serializer would
    # put that word inside lib/dexpace/page/** and spec-forced boundary 5's audit would fail on the
    # subsystem's own code. The consequence is stated rather than hidden: PAGE-16's "single read
    # of the response body" is the EXTRACTOR's read, core performs none, and the suite asserts it
    # against a read-counting body. An extractor that reads through Response#body_string gets the
    # single-use rule enforced by phase 3b's body -- a second read raises Dexpace::ClosedError --
    # and one that reads `response.body.source` directly owes the same discipline (PAGE-5). The
    # extractor is NOT rescued: a raise is a parse failure and PAGE-13 is its path, never an
    # end-of-stream signal (PAGE-4) -- rescuing it would turn every server-side schema change into
    # a silently truncated stream.
    #
    # A frozen Data with no instance state, so PAGE-5's "immutable and safe to share concurrently"
    # is structural: one instance serves any number of walks at once.
    class CursorStrategy < ::Data.define(:extract, :parameter)
      include Model

      private_class_method :new

      # @param extract [#call] `#call(response) -> [items, cursor_or_nil]`; a caller who wants a
      #   codec writes it into this closure, outside core
      # @param parameter [String] the cursor query parameter's name
      # @return [Dexpace::Page::CursorStrategy] frozen
      # @raise [Dexpace::InvalidArgumentError] when the extractor is not callable or the parameter
      #   is not a non-empty String
      def self.build(extract:, parameter: "cursor")
        new(extract: extract, parameter: parameter)
      end

      def initialize(extract:, parameter:)
        unless Model.required!("extract", extract).respond_to?(:call)
          raise InvalidArgumentError, "extract must respond to #call, got #{extract.class}"
        end
        unless parameter.is_a?(::String) && !parameter.empty?
          raise InvalidArgumentError,
                "parameter must be a non-empty String, got #{parameter.inspect}"
        end

        super(extract: extract, parameter: Model.frozen_string(parameter))
      end

      # One extractor call, then the derivation. The cursor also travels as the Info's
      # continuation token, so a fetcher front-end over pages this strategy produced has PAGE-34's
      # fallback key.
      #
      # @param response [Dexpace::Response] read once, through the extractor, never closed here
      # @param template [Dexpace::Request] the original request the next one is derived from
      # @return [Dexpace::Page::Info]
      # @raise [Dexpace::InvalidArgumentError] when the extractor's answer is not `[Array, String?]`
      def parse(response, template)
        items, cursor = unpack(extract.call(response))
        return Info.terminal(items: items) if cursor.nil? || cursor.empty?

        url = QueryRewriter.rewrite_url(template.url, parameter, cursor)
        Info.build(items: items, next_request: template.with(url: url), continuation_token: cursor)
      end

      private

      # The extractor's contract, checked so a wrong shape is named at the strategy and not read as
      # a silent end-of-stream by a destructuring that would put a bare Array in `items`.
      def unpack(answer)
        unless answer.is_a?(::Array) && answer.size == 2
          raise InvalidArgumentError,
                "the cursor extractor must return [items, cursor], got #{answer.class}"
        end

        items, cursor = answer
        unless items.is_a?(::Array)
          raise InvalidArgumentError, "the extractor's items must be an Array, got #{items.class}"
        end
        unless cursor.nil? || cursor.is_a?(::String)
          raise InvalidArgumentError,
                "the extractor's cursor must be a String or nil, got #{cursor.class}"
        end

        [items, cursor]
      end
    end
  end
end
