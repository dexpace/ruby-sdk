# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../page"
require_relative "../model"
require_relative "../registry"
require_relative "../http/request_options"
require_relative "walk"
require_relative "items"
require_relative "pages"

module Dexpace
  class Page
    # The fetcher-based front-end (PAGE-34, PAGE-35): the caller supplies a first-page fetcher and a
    # next-page fetcher instead of a transport and a strategy, and gets the same two views over the
    # same private Walk -- the item view, the page view with its look-ahead, and the two scoped
    # openers. A frozen Data holding the two callables and the options; every per-walk quantity
    # lives on the walk (PAGE-8).
    #
    # PAGE-34's rules, each a branch of the private Drive: the first-page fetcher is called exactly
    # once per walk; every later page keys the next-page fetcher off the previous page's next link,
    # falling back to its continuation token when the link is absent or blank -- next link wins; a
    # blank link with no fallback token, or a nil page from either fetcher, ends the stream, and a
    # nil FIRST page is an empty stream rather than an error. **Each fetcher builds a Dexpace::Page
    # that owns its response and MUST NOT close it** -- ownership transfers to the page and the
    # walk releases it (PAGE-3) -- **and a fetcher that raises before building the page remains
    # responsible for that response**: core cannot reach a response a fetcher never handed it.
    #
    # PAGE-35, vacuous by construction on design §12's own authority: the SHOULD is conditional on
    # a MUTABLE paging-options object, and this port offers a frozen Dexpace::RequestOptions
    # instead, so the clause is vacuous rather than declined. What the port does supply: the SAME
    # frozen instance is threaded to every fetcher that takes it, by identity; a fetcher that wants
    # per-page state has the previous page's `continuation_token` as a first-class channel
    # (PAGE-34), and a Ruby callable carries its own binding for anything else. A fetcher's arity
    # decides whether it is called with the options: `-> { }` and `->(key) { }` are called without
    # them, `->(options) { }` and `->(key, options) { }` with them.
    class Fetchers < ::Data.define(:first, :next_page, :options)
      include Model

      private_class_method :new

      # @param first [#call] `#call -> Dexpace::Page | nil`, or `#call(options)`
      # @param next_page [#call] `#call(key) -> Dexpace::Page | nil`, or `#call(key, options)`;
      #   `key` is the previous page's next link, or its continuation token when the link is blank
      # @param options [Dexpace::RequestOptions] handed, by identity, to a fetcher that takes it
      # @return [Dexpace::Page::Fetchers] frozen
      # @raise [Dexpace::InvalidArgumentError] when a fetcher is not callable or the options are not
      #   a Dexpace::RequestOptions
      def self.build(first:, next_page:, options: Dexpace::RequestOptions::EMPTY)
        new(first: first, next_page: next_page, options: options)
      end

      def initialize(first:, next_page:, options:)
        unless Model.required!("first", first).respond_to?(:call)
          raise InvalidArgumentError, "first must respond to #call, got #{first.class}"
        end
        unless Model.required!("next_page", next_page).respond_to?(:call)
          raise InvalidArgumentError, "next_page must respond to #call, got #{next_page.class}"
        end
        unless Model.required!("options", options).is_a?(Dexpace::RequestOptions)
          raise InvalidArgumentError,
                "options must be a Dexpace::RequestOptions, got #{options.class}"
        end

        super
      end

      # The item-level view over a fetcher-driven walk (PAGE-11's eager close, PAGE-8's fresh walk
      # per iteration).
      #
      # @return [Dexpace::Page::Items]
      def items
        Items.new(method(:open_walk))
      end

      # The page-level view over a fetcher-driven walk (PAGE-12, PAGE-14).
      #
      # @return [Dexpace::Page::Pages]
      def pages
        Pages.new(method(:open_walk))
      end

      # The scoped opener for items; closes the walk on every exit.
      #
      # @yieldparam item [Object]
      # @return [nil]
      # @raise [Dexpace::InvalidArgumentError] without a block
      def each_item(&block)
        raise InvalidArgumentError, "each_item requires a block" if block.nil?

        items.each(&block)
        nil
      end

      # The scoped opener for pages; closes both held pages on every exit.
      #
      # @yieldparam page [Dexpace::Page]
      # @return [nil]
      # @raise [Dexpace::InvalidArgumentError] without a block
      def each_page(&block)
        raise InvalidArgumentError, "each_page requires a block" if block.nil?

        pages.each(&block)
        nil
      end

      # The fetcher front-end's per-walk exchange routine (P7-111): whether the first fetcher has
      # run, and the previous page's key. Each call answers a Dexpace::Page or nil, exactly as the
      # strategy engine's drive does, so the Walk is shared unchanged.
      class Drive
        # @param fetchers [Dexpace::Page::Fetchers]
        def initialize(fetchers)
          @fetchers = fetchers
          @started = false
          @key = nil #: String?
        end

        # @return [Dexpace::Page, nil]
        def call
          page = @started ? fetch_next : fetch_first
          @started = true
          return nil if page.nil?
          unless page.is_a?(Dexpace::Page)
            raise InvalidArgumentError,
                  "a fetcher must return a Dexpace::Page or nil, got #{page.class}"
          end

          @key = key_of(page)
          page
        end

        private

        def fetch_first
          fetcher = @fetchers.first
          takes_options = Dexpace::Registry.callable?(fetcher, arity: 1)
          takes_options ? fetcher.call(@fetchers.options) : fetcher.call
        end

        # nil when the previous page carried neither a link nor a token: end-of-stream (PAGE-34).
        def fetch_next
          key = @key
          return nil if key.nil?

          fetcher = @fetchers.next_page
          if Dexpace::Registry.callable?(fetcher, arity: 2)
            fetcher.call(key, @fetchers.options)
          else
            fetcher.call(key)
          end
        end

        # PAGE-34: the next link wins; a blank one falls back to the continuation token; both blank
        # is nil.
        def key_of(page)
          link = page.next_link
          return link unless link.nil? || link.strip.empty?

          token = page.continuation_token
          token.nil? || token.strip.empty? ? nil : token
        end
      end
      private_constant :Drive

      private

      # A fresh Walk over a fresh Drive, uncapped: the fetchers are the caller's own code, and
      # PAGE-9's cap bounds a server, not a callable the caller wrote.
      def open_walk
        Walk.new(Drive.new(self), cap: ::Float::INFINITY)
      end
    end
  end
end
