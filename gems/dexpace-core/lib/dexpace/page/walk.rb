# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../page"
require_relative "../closeable"
require_relative "../suppressible"
require_relative "page_state_error"

module Dexpace
  class Page
    # The per-iteration lifetime owner: every live page a walk holds is an instance variable on
    # this object, which the caller can reach and #close -- never a local of an Enumerator block or
    # of a #each method. That is design §7.1's hard rule applied literally: an Enumerator abandoned
    # mid-#next never runs its ensure, neither does an ordinary #each, and block_given? is
    # measurably true inside #each when reached through to_enum(:each), so no in-method guard
    # defends anything; the only defence is where the resource lives (pagination/318ae05d,
    # pagination/b2a85752). Dexpace::Closeable's latch is what phase 2 built for exactly this.
    #
    # One drive routine, shared by both views (pagination/71aed9c1) and generic over a per-walk
    # DRIVE -- an object answering `#call -> Dexpace::Page | nil` that performs one exchange and
    # holds whatever state the next one needs. The strategy engine's drive holds the next request;
    # the fetcher front-end's holds the previous page's key (P7-111). The walk owns what is common:
    # the cap counted in exchanges (PAGE-9), the exhaustion latch that makes end-of-stream probes
    # idempotent and free (PAGE-7), the current and the one-slot look-ahead page (PAGE-12), and the
    # release discipline for both (PAGE-15). Not shareable: one walk per iteration (PAGE-8).
    #
    # A private_constant, asserted through the views and reached by const_get in its own suite,
    # with a sig/ mirror because the strict `core` Steep target types every file under lib/.
    class Walk
      include Dexpace::Closeable

      # @param drive [#call] the per-walk exchange routine, `#call -> Dexpace::Page | nil`
      # @param cap [Numeric] PAGE-9's page cap, counted in exchanges, validated by the engine
      def initialize(drive, cap:)
        @drive = drive
        @cap = cap
        @current = nil
        @buffered = nil
        @exchanges = 0
        @exhausted = false
        initialize_closeable(owned: true)
      end

      # @return [Dexpace::Page, nil] the page handed to the consumer and not yet advanced past
      attr_reader :current
      # @return [Dexpace::Page, nil] PAGE-12's one-slot look-ahead, filled by a probe
      attr_reader :buffered

      # The one drive routine. nil after the walk is closed (a closed walk owns no slot to hold a
      # response in, so a late probe acquires nothing), nil with no exchange once exhausted
      # (PAGE-7), nil and latched when the cap is reached -- checked BEFORE the exchange, so a cap
      # of N produces exactly N exchanges (PAGE-9); otherwise one exchange through the drive, whose
      # nil is the strategy's end-of-stream (PAGE-4). The returned page is the caller's to hold.
      #
      # @return [Dexpace::Page, nil]
      def fetch_next_page
        return nil if closed? || @exhausted
        return latch_exhausted if @exchanges >= @cap

        page = @drive.call
        return latch_exhausted if page.nil?

        @exchanges += 1
        page
      end

      # PAGE-12's advance: `page` becomes the held page and the previous one is closed. The new
      # page is written into the slot BEFORE the previous one is closed, so a close error strands
      # nothing -- the frame that owns the walk closes it on the way out and finds the new page
      # held. The close is bare: when the consumer has returned from the previous yield nothing is
      # in flight, so a close error here is SURFACED and never swallowed (PAGE-15's first clause
      # does not carve out the advance), and never read off `$!`, which may be a caller's
      # unrelated in-flight error (P7-105).
      #
      # @param page [Dexpace::Page] the page about to be yielded
      # @return [nil]
      def hold(page)
        previous = @current
        @current = page
        previous.close unless previous.nil? || previous.equal?(page)
        nil
      end

      # PAGE-12's look-ahead. ONE slot: a staged page is never displaced, because overwriting it
      # would spend a second exchange on one yielded page (PAGE-6) and strand the displaced
      # response, which is the leak the buffering clause exists to prevent -- a probe that finds a
      # page staged reads it instead (Pages#more?), so a second call here is a state error.
      #
      # @param page [Dexpace::Page] the fetched-but-undelivered page
      # @return [nil]
      # @raise [Dexpace::Page::PageStateError] when a page is already staged
      def buffer(page)
        unless @buffered.nil?
          raise PageStateError,
                "a page is already staged in the walk's look-ahead slot"
        end

        @buffered = page
        nil
      end

      # Empties the look-ahead slot and hands its page over to be held.
      #
      # @return [Dexpace::Page, nil]
      def take_buffered
        page = @buffered
        @buffered = nil
        page
      end

      private

      def latch_exhausted
        @exhausted = true
        nil
      end

      # PAGE-15's third clause and PAGE-12's "explicit close MUST release both": both slots are
      # released, the first close failure is held, a second is attached to it as suppressed, and
      # the first is re-raised -- `raise error, cause: nil`, because it is being carried past a
      # later rescue (pipeline/7ce4431d). Both slots are cleared before anything can raise, so the
      # latch and the slots agree whatever happens; the attach is a no-op on a frozen primary
      # (phase 4b's P4-13), stated rather than worked around.
      def release
        pages = [@current, @buffered].compact
        @current = nil
        @buffered = nil
        first = nil #: StandardError?
        pages.each do |page|
          page.close
        rescue ::StandardError => error
          first.nil? ? first = error : Dexpace.attach_suppressed(first, error)
        end
        raise first, cause: nil unless first.nil?

        nil
      end
    end
    private_constant :Walk
  end
end
