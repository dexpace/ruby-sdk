# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "no_span"
require_relative "scope"
require_relative "diagnostics"

module Dexpace
  module Instrumentation
    # OBS-22 and OBS-23: the current-span carrier, span activation with its restoring scope
    # handle, and log correlation over the two diagnostic-context keys. A function module over
    # `extend self` (styleguide 06, data-modeling/3775e9d7, the shape URL and PercentEncoding
    # take), because it owns no state beyond one Fiber[] slot (data-modeling/b74a2869):
    # CURRENT_SPAN_KEY names that slot and scope.rb declares it, so Scope#close writes the same
    # spelling. The carrier is Fiber[] and never Thread.current[] or Dexpace::ContextStore
    # (boundary 14): a span activated before a thread, a child fiber or an enumerator is created
    # is current inside each, and the slots hold only immutable values -- one span reference
    # and two frozen Strings -- so copy-on-write isolates a child's rebinding (verified fact 2).
    #
    # Nothing here rescues. OBS-20 and OBS-30 make a throwing tracer the caller's -- "the
    # instrumentation runtime does not defensively catch these callbacks" -- and the two block
    # forms restore through `ensure` regardless of what the block did (boundary 2). The block
    # forms are the primary API and are written in terms of the handle forms, so there is one
    # restore path whichever a caller takes (P5-45); the bare handle exists because OBS-22's
    # words are "return a scope handle" and because a scope that outlives its frame -- 5b's
    # AsyncStep, closing in a future's settlement callback -- needs one.
    #
    # The bundle is a parameter and never read from a context: taking it as an argument keeps
    # this module free of any CTX dependency, which is what lets 5c's suite load without the
    # context tree and what the load-time independence assertion (Task 11) rests on.
    module Tracing
      extend self

      # The span currently active in this fiber: NO_SPAN when nothing is, so no caller ever
      # sees nil (api-design/6ea28c9c). Allocation-free (verified fact 3).
      #
      # @return [Object] the current _Span
      def current_span
        ::Fiber[CURRENT_SPAN_KEY] || NO_SPAN
      end

      # OBS-22: makes `span` the current span and returns the handle whose #close restores the
      # one it replaced. Returns NO_SCOPE -- the cached singleton OBS-25 requires -- exactly
      # when nothing is owed on close: the span is already the current one (P5-47, an identity
      # test and not the recording flag, because a non-recording span activated over a
      # recording one still owes that restore). In an application with no tracer installed the
      # slot holds NO_SPAN and every activation is of NO_SPAN, so the untraced path allocates
      # nothing per call.
      #
      # @param span [Object] the _Span to make current
      # @return [Object] a _Scope: NO_SCOPE, or a fresh Scope restoring the previous span
      def activate(span)
        current = current_span
        return NO_SCOPE if span.equal?(current)

        ::Fiber[CURRENT_SPAN_KEY] = span
        Scope.build(current)
      end

      # OBS-22's block form: `span` is current for the block, the block's value is returned, and
      # the previous span is restored in an `ensure` -- so even when the block raises, and the
      # raise is not caught (OBS-30).
      #
      # @param span [Object] the _Span to make current
      # @yieldparam span [Object] the same span
      # @return [Object] the block's value
      def with_span(span)
        scope = activate(span)
        begin
          yield span
        ensure
          scope.close
        end
      end

      # OBS-23: activates `span` for log correlation. For a recording span with a valid bundle,
      # pushes the bundle's trace id and span id onto the diagnostic context under 5b's two
      # keys for the scope's lifetime, and returns a handle restoring the span and both keys --
      # each "to its prior value (or remove it if previously unset)". For a non-recording span
      # the push is skipped and activation delegates to plain current-span activation, in the
      # requirement's own words. And for a bundle that is not #valid? it likewise delegates: an
      # all-zero id "MUST be treated as invalid/no-trace" (OBS-26), and a recording span paired
      # with Bundle::NONE was the only state 5b's step could reach in phase 5 (R11) -- without
      # the guard every log event of a tracing-enabled client would carry trace.id=<32 zeros>,
      # a fake trace and worse than an absent key. Bundle#valid? is 4a's derived predicate and
      # is exactly this test; since phase 6a's Task 8 made a populated bundle reachable through
      # Cursor#bundle, the guard fires only for a call that seeded none. NO_SCOPE when the span
      # and both key values are already in place.
      #
      # @param span [Object] the _Span to make current
      # @param bundle [Bundle] the correlation bundle whose ids are pushed
      # @return [Object] a _Scope: NO_SCOPE, or a fresh Scope restoring all three slots
      def correlate(span, bundle)
        return activate(span) unless span.recording? && bundle.valid?

        current = current_span
        prev_trace_id = ::Fiber[Diagnostics::TRACE_ID]
        prev_span_id = ::Fiber[Diagnostics::SPAN_ID]
        trace_id = bundle.trace_id
        span_id = bundle.span_id
        if span.equal?(current) && prev_trace_id == trace_id && prev_span_id == span_id
          return NO_SCOPE
        end

        ::Fiber[CURRENT_SPAN_KEY] = span
        ::Fiber[Diagnostics::TRACE_ID] = trace_id
        ::Fiber[Diagnostics::SPAN_ID] = span_id
        Scope.build(current, prev_trace_id, prev_span_id)
      end

      # OBS-23's block form, written over .correlate plus one `ensure`, so there is one code
      # path and not two; the form a caller whose scope is purely lexical reaches for.
      #
      # @param span [Object] the _Span to make current
      # @param bundle [Bundle] the correlation bundle whose ids are pushed
      # @yieldparam span [Object] the same span
      # @return [Object] the block's value
      def with_correlated_span(span, bundle)
        scope = correlate(span, bundle)
        begin
          yield span
        ensure
          scope.close
        end
      end
    end
  end
end
