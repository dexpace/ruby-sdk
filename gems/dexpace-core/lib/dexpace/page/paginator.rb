# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../page"
require_relative "../model"
require_relative "../cancellation"
require_relative "../http/request"
require_relative "../http/request_options"
require_relative "closing"
require_relative "walk"
require_relative "items"
require_relative "pages"

module Dexpace
  class Page
    # The blocking pagination engine (PAGE-6 through PAGE-10, PAGE-36): a frozen Data holding only
    # immutable configuration -- the transport, the request template, the strategy, the page cap
    # and the per-call options -- and no per-walk state at all, so one instance is safe to share
    # across any number of concurrent iterations (PAGE-8). Every per-walk quantity lives on a
    # private Walk that #items and #pages allocate per view; nothing here is fetched until a
    # consumer probes (PAGE-6).
    #
    # The transport is anything answering `#call(request, options, cancellation)` with a
    # Dexpace::Response -- a Pipeline, a bare adapter, a lambda. A built pipeline is a transport
    # whose #close is a no-op (PIPE-26, PIPE-27), so the paginator wraps one without declaring it
    # and NEVER closes it: PAGE-3's ownership transfer is about the response, not the transport it
    # came from, and a paginator that closed its transport would break a caller who built one
    # pipeline for a whole client. The per-call options are passed on EVERY exchange, which is
    # what makes PAGE-36 structural rather than remembered; the default is RequestOptions::EMPTY,
    # "no overrides". The cancellation the transport receives is always Cancellation.none: the
    # blocking engine takes no per-walk token in v1, and a nil there would die inside the standard
    # pipeline's retry step (P7-102).
    #
    # PAGE-10: the default cap is Float::INFINITY, strictly positive and comparable against an
    # Integer exchange count, so the cap check is one expression with no nil branch. **Production
    # callers should set a finite cap**: an unbounded walk over a server that never advances its
    # cursor runs until the process is stopped, and the cap is the only bound this engine has.
    class Paginator < ::Data.define(:transport, :template, :strategy, :cap, :options)
      include Model

      private_class_method :new

      # @param transport [#call] `#call(request, options, cancellation) -> Dexpace::Response`
      # @param template [Dexpace::Request] the first page's request and the shape every later one
      #   is derived from
      # @param strategy [_Strategy] a stateless parser answering `#parse(response, template)`
      # @param cap [Numeric] PAGE-9's maximum number of exchanges, strictly positive; set a finite
      #   one in production (PAGE-10)
      # @param options [Dexpace::RequestOptions] PAGE-36's per-call overrides, applied to every page
      # @return [Dexpace::Page::Paginator] frozen
      # @raise [Dexpace::InvalidArgumentError] when a member is missing or of the wrong shape, or
      #   the cap is not strictly positive
      def self.build(transport:, template:, strategy:, cap: ::Float::INFINITY,
                     options: Dexpace::RequestOptions::EMPTY)
        new(transport: transport, template: template, strategy: strategy, cap: cap,
            options: options,)
      end

      # Validation lives here so .build, #with and a forged send(:new, ...) all meet it (PAGE-9's
      # "validated as strictly positive at construction, not lazily").
      def initialize(transport:, template:, strategy:, cap:, options:)
        validate_engine!(transport, template, strategy)
        unless cap.is_a?(::Numeric) && cap.positive?
          raise InvalidArgumentError,
                "cap must be a strictly positive number, got #{cap.inspect} (PAGE-9)"
        end
        unless Model.required!("options", options).is_a?(Dexpace::RequestOptions)
          raise InvalidArgumentError,
                "options must be a Dexpace::RequestOptions, got #{options.class}"
        end

        super
      end

      # The item-level view: a fresh walk per iteration, every page closed before its items are
      # yielded (PAGE-11), re-iterable (PAGE-8). Nothing is fetched until it is driven (PAGE-6).
      #
      # @return [Dexpace::Page::Items]
      def items
        Items.new(method(:open_walk))
      end

      # The page-level view: one walk, single-use (PAGE-14), auto-closing with a one-slot look-ahead
      # (PAGE-12). Nothing is fetched until it is driven or probed (PAGE-6). Wrap it in #each_page,
      # or call Pages#close yourself, so an early exit releases what it holds.
      #
      # @return [Dexpace::Page::Pages]
      def pages
        Pages.new(method(:open_walk))
      end

      # The scoped opener for items: yields each item in server order and closes the walk on every
      # exit -- a return, a `break`, a raise. The recommended form (PAGE-12's "consumers MUST be
      # told to wrap the view in a scoped/auto-close construct").
      #
      # @yieldparam item [Object]
      # @return [nil]
      # @raise [Dexpace::InvalidArgumentError] without a block
      def each_item(&block)
        raise InvalidArgumentError, "each_item requires a block" if block.nil?

        items.each(&block)
        nil
      end

      # The scoped opener for pages: yields each live Dexpace::Page in order, closes the previous
      # page as the consumer advances, the last at exhaustion, and both held pages on every exit --
      # a return, a `break`, a raise. The recommended form for the page view (PAGE-12).
      #
      # @yieldparam page [Dexpace::Page]
      # @return [nil]
      # @raise [Dexpace::InvalidArgumentError] without a block
      def each_page(&block)
        raise InvalidArgumentError, "each_page requires a block" if block.nil?

        pages.each(&block)
        nil
      end

      # The strategy engine's per-walk exchange routine (P7-111): the next request is its one piece
      # of state, seeded from the template and replaced by each Info's next request; nil once the
      # strategy said end-of-stream, with no exchange (PAGE-7). One exchange passes the paginator's
      # options every time (PAGE-36) and Cancellation.none (P7-102), then PAGE-13's parse-or-close,
      # then the Page that owns the response from here on (PAGE-3).
      class Drive
        # @param paginator [Dexpace::Page::Paginator]
        def initialize(paginator)
          @paginator = paginator
          @next_request = paginator.template #: Dexpace::Request?
        end

        # @return [Dexpace::Page, nil]
        def call
          request = @next_request
          return nil if request.nil?

          response = @paginator.transport.call(request, @paginator.options, Dexpace::Cancellation.none)
          info = Closing.parse_or_close(@paginator.strategy, response, @paginator.template)
          @next_request = info.next_request
          Dexpace::Page.build(response: response, items: info.items, next_link: info.next_link,
                              continuation_token: info.continuation_token,)
        end
      end
      private_constant :Drive

      private

      # The three members named the way HTTP-4 / SEAM-29 name them; the async engine validates the
      # same three the same way.
      def validate_engine!(transport, template, strategy)
        unless Model.required!("transport", transport).respond_to?(:call)
          raise InvalidArgumentError, "transport must respond to #call, got #{transport.class}"
        end
        unless Model.required!("template", template).is_a?(Dexpace::Request)
          raise InvalidArgumentError, "template must be a Dexpace::Request, got #{template.class}"
        end
        return if Model.required!("strategy", strategy).respond_to?(:parse)

        raise InvalidArgumentError, "strategy must respond to #parse, got #{strategy.class}"
      end

      # A fresh Walk over a fresh Drive: PAGE-8's "each independent iteration restarts from the
      # initial request with its own fresh state".
      def open_walk
        Walk.new(Drive.new(self), cap: cap)
      end
    end
  end
end
