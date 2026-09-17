# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # Phase 5b's diagnostic-context module (OBS-10, OBS-24): the two key names OBS-23 pushes and
    # OBS-10 folds by default, and the default allow-list built from them. Phase 5c ships these
    # three constants early -- and nothing else of this module -- because Tracing.correlate and
    # Scope#close read the two keys and this is a 5c-first execution (the 5c plan's Global
    # Constraints: "a 5c-first execution creates diagnostics.rb with TRACE_ID, SPAN_ID and
    # DEFAULT_KEYS itself and 5b then adopts that file rather than creating a second one"). 5b's
    # Task 6 extends this file with .capture, .with and .folded; it does not create a second one
    # (P5-71).
    #
    # Symbols, not frozen Strings: Fiber.current.storage -- OBS-10's unfiltered reader -- hands
    # every key back as a Symbol, Fiber#storage= refuses a String key with TypeError on every
    # supported Ruby, and on the 3.2 and 3.3 rows Fiber[]= and Fiber[] refuse one too (measured
    # 2026-09-17; the interning the corpus records arrives at 3.4). A Symbol is the one spelling
    # every carrier API accepts on every row, and Symbol#name is the fold's allocation-free
    # bridge to OBS-39's String field key (5b's R11, 5c's verified fact 3).
    module Diagnostics
      # OBS-23's first key, "trace.id", as the carrier spells it.
      TRACE_ID = :"trace.id"

      # OBS-23's second key, "span.id", as the carrier spells it.
      SPAN_ID = :"span.id"

      # OBS-10's default allow-list: "exactly {trace.id, span.id}", in that order.
      DEFAULT_KEYS = [TRACE_ID, SPAN_ID].freeze
    end
  end
end
