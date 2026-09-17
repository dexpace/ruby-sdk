# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # CTX-15's no-op span, the object behind NO_SPAN, with OBS-21's protocol as phase 5c gave it
    # (the protocol phase 4a postponed): phase 4 fixed the slot and the identity of the object
    # filling it, and phase 5c gives THIS class its methods rather than introducing a second
    # no-op span -- the class is a private_constant and so not NFR-4-locked, while the object
    # keeps the identity phase 4 published (boundary 10).
    #
    # Every method here works on a FROZEN receiver -- NO_SPAN is frozen at its definition -- so
    # none writes an ivar, which is also what OBS-25's "selecting a no-op path MUST NOT allocate
    # per call" wants: each answers a constant or `self` from arguments already on the stack.
    # Every attributes parameter is a named optional keyword and never a `**` splat, because a
    # splat allocates a Hash on every call including one passing nothing (P5-42;
    # Dexpace/NoKeywordSplat is the cop). The parameter names are the documented protocol and
    # are kept verbatim though unused (P5-41).
    #
    # No `require_relative "bundle"` here, deliberately: bundle.rb requires this file (its
    # Bundle.build defaults `span:` to NO_SPAN) and closes NONE = build(...) at load, so the
    # reverse require would make the cycle fail whenever no_span.rb is entered first. #context
    # resolves Bundle::NONE at call time, and lib/dexpace.rb requires bundle.rb after this file.
    #
    # The implementer contract, stated where a duck-typed SPI can bind it: a recording span
    # keeps what its mutators are handed, exports once on #finish and never on a second call
    # (OBS-21's "end() MUST be idempotent"), and every method is safe to invoke concurrently and
    # never raises (OBS-30 -- the runtime does not catch, so a raise reaches the caller's
    # request). `record_error`, not opentelemetry-api's `record_exception`: OBS-21's word is
    # "error", the SDK's own vocabulary is Dexpace::Error and #each_cause, and `error.type` is
    # OBS-39's field key (the plan's resolved question 3; P5-41).
    class NoSpan
      # rubocop:disable Lint/UnusedMethodArgument -- OBS-21: every mutator is inert and drops
      # its data; the parameter names are the protocol.

      # OBS-21's recording flag: false, always, and the reason every mutator below is inert.
      #
      # @return [false]
      def recording?
        false
      end

      # Drops the attribute (OBS-21).
      #
      # @param key [String] the attribute key
      # @param value [Object] the attribute value
      # @return [self]
      def set_attribute(key, value)
        self
      end

      # Drops the event (OBS-21, OBS-28).
      #
      # @param name [String] the event name
      # @param attributes [Hash{String => Object}, nil] per-event attributes, frozen by the caller
      # @return [self]
      def add_event(name, attributes: nil)
        self
      end

      # Drops the error (OBS-21).
      #
      # @param error [Exception] the error to record
      # @param attributes [Hash{String => Object}, nil] per-error attributes, frozen by the caller
      # @return [self]
      def record_error(error, attributes: nil)
        self
      end

      # Drops the status; there is no reader (OBS-21). Returns the argument, as any assignment
      # method does when reached through public_send.
      #
      # @param status [Object] the status to set
      # @return [Object] the argument
      def status=(status)
        status
      end

      # OBS-21's "end() MUST be a no-op ... and idempotent": nil on every call, first or second.
      # `finish`, not `end`, on P4-8's call-compatibility argument alone -- `def end` is legal
      # Ruby and the choice rests on the opentelemetry-api shape, not on syntax.
      #
      # @param end_timestamp [Time, nil] ignored
      # @return [nil]
      def finish(end_timestamp: nil)
        nil
      end
      # rubocop:enable Lint/UnusedMethodArgument

      # OBS-25's "a no-op instrumentation context whose identifiers are all invalid sentinels":
      # Bundle::NONE, by identity, whose span is this object.
      #
      # @return [Bundle] Bundle::NONE
      def context
        Bundle::NONE
      end
    end
    private_constant :NoSpan

    # The one shared, frozen no-op span every untraced bundle carries (CTX-14's "an active span",
    # CTX-15). One instance, so OBS-25's "MUST NOT allocate per call" is assertable by reference
    # identity: `assert_same Dexpace::Instrumentation::NO_SPAN, bundle.span`. Public, where
    # BoundedMap is not, because that assertion is a QUALIFIED reference and a qualified reference
    # to a private constant raises even from inside Dexpace (design, verified fact 6).
    NO_SPAN = NoSpan.new.freeze
  end
end
