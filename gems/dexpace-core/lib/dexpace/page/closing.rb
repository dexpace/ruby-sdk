# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../page"
require_relative "../suppressible"
require_relative "info"

module Dexpace
  class Page
    # The two close disciplines every view, engine and walk in this subsystem shares, written once
    # so PAGE-13's and PAGE-15's primary-error rules cannot drift between the four sites that need
    # them.
    #
    # The trap both exist for was measured on every CI row (R8): a bare `ensure` whose close raises
    # while a consumer exception is already in flight REPLACES the consumer's exception as the
    # primary -- Ruby sets #cause to it, so nothing is lost, but PAGE-13's and PAGE-32's conformance
    # clauses assert the exact opposite order. And the obvious repair, reading `$!` at the top of
    # the `ensure`, is wrong in the other direction: `$!` is dynamically scoped to the thread and is
    # non-nil inside anything called from a CALLER's `rescue` (pipeline/7ce4431d's measurement), so
    # a walk driven from inside a consumer's rescue block would quietly attach its close error to an
    # unrelated in-flight error instead of surfacing it. Neither `$!` nor a bare `ensure` appears in
    # this subsystem (P7-105). The shape is 6b's: the frame that owns the walk records the primary
    # in a `rescue ::Exception` arm that re-raises unchanged, and its `ensure` hands that local to
    # .close_walk, which branches on it -- nil under a `break`, a normal return or a plain
    # exhaustion, the consumer's error otherwise.
    #
    # Dexpace.close_quietly is deliberately NOT a third branch here: it is reached only where a
    # requirement says SWALLOW -- PAGE-26's already-settled drop and PAGE-32's already-failed
    # consumer, both in the async engine -- and using it anywhere else silently breaks PAGE-15's
    # "surfaced, not swallowed". A private_constant with a sig/ mirror because the strict `core`
    # Steep target types every file under lib/; asserted through the views and the lifetime suite.
    module Closing
      extend self

      # PAGE-15 and PAGE-13/PAGE-32's primary rule, at the walk's end: with nothing in flight a
      # close failure is SURFACED; with `primary` in flight it is attached to the primary's
      # suppressed trail through Dexpace.attach_suppressed, and the primary stays primary. The
      # attach is a documented no-op on a frozen primary (phase 4b's P4-13), never worked around --
      # raising while attaching would mask the primary, which is the one thing this method exists
      # to prevent.
      #
      # @param walk [Dexpace::Page::Walk] the walk to close; its #release closes both slots
      # @param primary [Exception, nil] what the owning frame is already unwinding with, or nil
      # @return [nil]
      def close_walk(walk, primary)
        walk.close
        nil
      rescue ::StandardError => error
        raise if primary.nil?

        Dexpace.attach_suppressed(primary, error)
        nil
      end

      # PAGE-13: the strategy's parse, with the response closed INLINE on the exceptional path --
      # the page is never constructed, so nothing else would close it -- and the parse error kept
      # primary: a close failure is attached to its trail, never raised over it. A fatal-family
      # error (not a StandardError) closes the response quietly and propagates unchanged with no
      # trail, RECOV-2's split (P7-110). The re-raise is spelled `raise error, cause: nil`, because
      # the error was carried across a nested rescue and a bare `raise` would hand it whatever is in
      # flight as a #cause (pipeline/7ce4431d).
      #
      # @param strategy [_Strategy] the paginator's strategy
      # @param response [Dexpace::Response] the fetched response, owned by the caller until the
      #   Info comes back and by the Page it becomes afterwards
      # @param template [Dexpace::Request] the original request template
      # @return [Dexpace::Page::Info]
      def parse_or_close(strategy, response, template)
        info = strategy.parse(response, template)
        unless info.is_a?(Info)
          raise InvalidArgumentError,
                "a strategy's parse must return a Dexpace::Page::Info, got #{info.class}"
        end

        info
      rescue ::StandardError => error
        Dexpace.close_quietly(response, onto: error)
        raise error, cause: nil
      rescue ::Exception # rubocop:disable Lint/RescueException -- RECOV-2: the fatal family finds the response closed too, then propagates unchanged
        Dexpace.close_quietly(response)
        raise
      end
    end
    private_constant :Closing
  end
end
