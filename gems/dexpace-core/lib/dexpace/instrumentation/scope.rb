# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "diagnostics"

module Dexpace
  module Instrumentation
    # The current-span slot key, declared once and shared by Scope and Tracing, because
    # Scope#close and Tracing both write the slot and one key must not have two spellings. It is
    # NOT a diagnostic-context key and must never be folded -- OBS-10's default allow-list is
    # exactly {trace.id, span.id} -- so it is a private_constant, and it is namespaced under
    # `dexpace.` so it cannot collide with an application's own key and so 5b's unfiltered fold
    # can skip the reserved prefix (the design's open question 4). A bare reference resolves from
    # both lexical scopes below; a qualified one raises (execution-context/b58728da), which is
    # why every file here uses the full `module Dexpace; module Instrumentation` nesting.
    CURRENT_SPAN_KEY = :"dexpace.current_span"
    private_constant :CURRENT_SPAN_KEY

    # OBS-25's "a no-op Span whose current-scope is a cached singleton": the class behind
    # NO_SCOPE, whose #close has nothing to restore. Frozen, stateless, shared from every thread
    # (OBS-30 structurally).
    class NoScope
      # Nothing to restore.
      #
      # @return [nil]
      def close
        nil
      end
    end
    private_constant :NoScope

    # The one shared, frozen scope handle Tracing.activate and .correlate return whenever no
    # restore is owed -- the span being activated is already the current one and no diagnostic
    # key would change (P5-47, an identity test and not the recording flag). Public for the
    # reason NO_SPAN is: OBS-25's conformance clause asserts "the same singletons" by a
    # qualified reference, and a qualified reference to a private_constant raises.
    NO_SCOPE = NoScope.new.freeze

    # OBS-22's scope handle: "when closed, restores the previously-active span", and with it
    # OBS-23's two diagnostic keys, in one place. A plain class with three ivars and one method,
    # deliberately not a Data (P5-46): a per-call resource handle, not a value -- it has no
    # meaningful ==, its generated #hash would be nonsense, frozen-on-construction buys it
    # nothing, and a Data costs two allocations to a plain object's one (verified fact 5) on
    # the one path OBS-25 does not make free. The previously-active span lives HERE, on the
    # Ruby call stack, and never in a stack in fiber storage: Fiber[]'s copy-on-write protects
    # the slot and not the object in it, so a span stack there would be one shared mutable Array
    # across every descendant thread and fiber -- XCUT-11 with no synchronisation (R13,
    # verified fact 2). Nesting is the call stack; correctness under a raise is the block form's
    # `ensure` in Tracing.
    #
    # Not a Dexpace::Closeable (P5-45): XCUT-13's idempotent non-blocking close is about owned
    # resources with a lifecycle, and a scope owns nothing -- its #close restores rather than
    # releases. It is idempotent anyway, by construction.
    class Scope
      # The "not handed" marker for the two diagnostic restores: a plain activation
      # (Tracing.activate) owes the span restore only and must leave the two keys exactly as
      # they were, which nil cannot express because nil is itself a value the restore writes.
      UNSET = ::Object.new.freeze
      private_constant :UNSET

      private_class_method :new

      # The internal constructor. Tracing.activate and .correlate are its only callers, and it is
      # not part of the scope's contract (P5-41 enumerates #close alone): it cannot be a
      # private_class_method because Tracing is a sibling module, so it is public and says so.
      #
      # @api private
      # @param prev_span [Object] the span the slot held before activation
      # @param prev_trace_id [String, nil, UNSET] the prior trace.id value, nil for absent
      # @param prev_span_id [String, nil, UNSET] the prior span.id value, nil for absent
      # @return [Scope]
      def self.build(prev_span, prev_trace_id = UNSET, prev_span_id = UNSET)
        new(prev_span, prev_trace_id, prev_span_id)
      end

      def initialize(prev_span, prev_trace_id, prev_span_id)
        @prev_span = prev_span
        @prev_trace_id = prev_trace_id
        @prev_span_id = prev_span_id
      end

      # OBS-22's and OBS-23's restores, in one place and idempotent by construction: a second
      # call writes the same three values into the same three slots. "Restore each key to its
      # prior value (or remove it if previously unset)" is one assignment with no branch on
      # presence, because `Fiber[:k] = nil` deletes the key on Ruby 3.3 and later -- and on the
      # 3.2 floor leaves it present with a nil value, which `Fiber[]` reads identically and
      # OBS-10's "Keys with null values MUST be skipped" folds identically, the floor offering
      # no other removal than the warned whole-map setter core never calls (P5-49, P5-72).
      #
      # @return [nil]
      def close
        ::Fiber[CURRENT_SPAN_KEY] = @prev_span
        ::Fiber[Diagnostics::TRACE_ID] = @prev_trace_id unless @prev_trace_id.equal?(UNSET)
        ::Fiber[Diagnostics::SPAN_ID] = @prev_span_id unless @prev_span_id.equal?(UNSET)
        nil
      end
    end
  end
end
