# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../page"
require_relative "../error/invalid_argument_error"
require_relative "closing"
require_relative "page_state_error"
require_relative "walk"

module Dexpace
  class Page
    # The page-level view (PAGE-1): whole Dexpace::Pages in order, each live -- status, headers,
    # originating request and the open response -- for the length of the consumer's turn. One walk,
    # allocated when the view is, and single-use: the iterator may be obtained at most once, and a
    # second #each raises PageStateError rather than silently restarting (PAGE-14); two views from
    # one engine are two walks and two full fetch sequences (PAGE-8).
    #
    # PAGE-12's auto-closing discipline, verbatim: the previous page is closed as the consumer
    # advances, the last page at exhaustion, and a page fetched by a probe but not yet delivered is
    # staged in storage the WALK owns -- its one-slot look-ahead, never the enumerator's closure
    # (pagination/9bdf90fc) -- so an emptiness probe or an early break followed by #close still
    # releases it; #close releases both the held page and the staged one. Up to two live pages can
    # exist at once. **Wrap the view in Paginator#each_page or Fetchers#each_page, or call #close
    # yourself**: an Enumerator abandoned mid-#next runs no ensure, so a page pulled through
    # external iteration and then dropped stays open until #close, which is the residue design
    # §7.1 states rather than hides.
    #
    # `include ::Enumerable` gives `first`, `take`, `lazy` and the rest, each of them one drive of
    # #each -- so `view.first` is the whole single use. Constructed by the engine through
    # Paginator#pages or Fetchers#pages, never directly.
    class Pages
      include ::Enumerable

      # @param opener [#call] the engine's walk factory, `#call -> Walk`
      # @raise [Dexpace::InvalidArgumentError] when the opener is not callable
      def initialize(opener)
        unless opener.respond_to?(:call)
          raise InvalidArgumentError, "a page view is opened by the engine, got #{opener.class}"
        end

        @walk = opener.call
        @viewed = false
      end

      # Yields each live page in order, closing the previous one as it advances and the last at
      # exhaustion, and both held pages on every exit -- a return, a `break`, a raise (PAGE-12).
      # Without a block, the Enumerator over the same routine; obtaining it IS the one use, so a
      # later block call raises. A second call in either form raises PageStateError (PAGE-14).
      #
      # @yieldparam page [Dexpace::Page] live for the length of the block, closed after it
      # @return [self, Enumerator]
      # @raise [Dexpace::Page::PageStateError] on a second call
      def each(&)
        claim!
        return to_enum(:drive) unless block_given?

        drive(&)
        self
      end

      # PAGE-12's emptiness probe. **The first call runs an HTTP exchange**: probing for the next
      # page eagerly fetches it, and the page is staged in the walk's look-ahead slot until the
      # consumer advances to it or the view is closed. A repeated probe reads the staged page and
      # costs nothing (PAGE-6); a closed or exhausted walk fetches nothing and answers false.
      #
      # @return [Boolean] whether another page is available
      def more?
        return true unless @walk.buffered.nil?

        page = @walk.fetch_next_page
        return false if page.nil?

        @walk.buffer(page)
        true
      end

      # Releases both the held page and any staged one, surfacing a close failure rather than
      # swallowing it (PAGE-15); idempotent through the walk's latch.
      #
      # @return [nil]
      def close
        @walk.close
      end

      # Whether #close has run (or #each's own ensure did).
      #
      # @return [Boolean]
      def closed?
        @walk.closed?
      end

      private

      def claim!
        if @viewed
          raise PageStateError,
                "a page view is single-use: its iterator was already obtained (PAGE-14)"
        end

        @viewed = true
      end

      # The one drive: a staged page first, else the next fetched one; hold it (closing the previous
      # -- a failure there is surfaced, PAGE-15), yield it; close the walk on every exit through
      # Closing, with the consumer's error recorded so a close failure joins its trail instead of
      # replacing it (PAGE-13's order, R8).
      def drive
        primary = nil #: Exception?
        begin
          while (page = @walk.take_buffered || @walk.fetch_next_page)
            @walk.hold(page)
            yield page
          end
        rescue ::Exception => error # rubocop:disable Lint/RescueException -- recorded for the ensure's Closing route, re-raised unchanged
          primary = error
          raise
        ensure
          Closing.close_walk(@walk, primary)
        end
      end
    end
  end
end
