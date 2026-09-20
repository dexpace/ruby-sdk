# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../page"
require_relative "../error/invalid_argument_error"
require_relative "closing"
require_relative "walk"

module Dexpace
  class Page
    # The item-level view (PAGE-1): every page's items flattened into one sequence in server order
    # across page boundaries, over a walk the view opens afresh on EVERY #each -- PAGE-8's "each
    # independent iteration MUST restart from the initial request with its own fresh state" --
    # with each page closed BEFORE any of its items is yielded (PAGE-11), after its items were
    # copied into the page's frozen list.
    #
    # The eager close is what makes this view safe on a host where an abandoned Enumerator's
    # ensure never runs: the only suspension points an external consumer can abandon the walk at
    # are points where no response is live, so the residue of pagination/b2a85752 on this view is
    # zero. It is also why #close is a documented no-op rather than an omission -- the walk is a
    # local of #each so that overlapping iterations stay independent, so there is no walk for the
    # view to hold, and by PAGE-11 there is nothing open to release at any point a caller could
    # call it. A `@walk` stored on the view to give #close something to do would break PAGE-8 the
    # moment two iterations overlap.
    #
    # `include ::Enumerable` gives `first`, `take`, `lazy`, `count` and the rest for free
    # (design §7.1), each of them driving #each; `first` and `take` stop early and spend exactly
    # the exchanges they consume (PAGE-6). Constructed by the engine through Paginator#items or
    # Fetchers#items, never directly.
    class Items
      include ::Enumerable

      # @param opener [#call] the engine's walk factory, `#call -> Walk`, one fresh walk per call
      # @raise [Dexpace::InvalidArgumentError] when the opener is not callable
      def initialize(opener)
        unless opener.respond_to?(:call)
          raise InvalidArgumentError, "an item view is opened by the engine, got #{opener.class}"
        end

        @opener = opener
      end

      # Yields every item in server order, fetching one page per page consumed (PAGE-6) and closing
      # each page before its first item is yielded (PAGE-11). Without a block, an Enumerator over
      # the same routine -- the one permitted block_given? in this subsystem, the
      # return-an-enumerator idiom and never a guard. An Enumerator abandoned mid-#next runs no
      # ensure, and on this view that costs nothing: PAGE-11 has already closed every page it
      # pulled.
      #
      # @yieldparam item [Object]
      # @return [self, Enumerator]
      def each(&)
        return to_enum(:each) unless block_given?

        walk = @opener.call # PAGE-8: fresh state per iteration
        primary = nil #: Exception?
        begin
          while (page = walk.fetch_next_page)
            items = page.items # PAGE-11: already a frozen copy
            page.close # PAGE-11: close BEFORE any item is yielded; a failure surfaces (PAGE-15)
            items.each(&)
          end
        rescue ::Exception => error # rubocop:disable Lint/RescueException -- recorded for the ensure's Closing route, re-raised unchanged
          primary = error
          raise
        ensure
          Closing.close_walk(walk, primary)
        end
        self
      end

      # A documented no-op, kept so the two views share one lifetime vocabulary: this view holds no
      # walk (PAGE-8) and PAGE-11 leaves nothing open at any point it could be called. Pages#close
      # is the one that releases.
      #
      # @return [nil]
      def close
        nil
      end
    end
  end
end
