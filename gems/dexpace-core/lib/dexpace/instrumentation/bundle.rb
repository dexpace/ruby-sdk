# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "trace_id_flavour"
require_relative "no_span"
require_relative "no_tracer"

module Dexpace
  module Instrumentation
    # CTX-14's correlation/instrumentation bundle, the one design §8.1 names and roadmap
    # cross-phase obligation 1 fixes in phase 4: what lets logs, metrics and spans across the
    # dispatch, request and exchange stages correlate into one logical trace.
    #
    # Nine things CTX-14 says the bundle must EXPOSE; eight are stored members and the ninth,
    # validity, is derived (P4-6) -- OBS-26 makes "an all-zero trace/span id MUST be treated as
    # invalid" a MUST, so validity is a function of trace_id and span_id and not an independently
    # settable fact, and `Bundle.build(trace_id: <real>, span_id: <real>, valid: false)` is not
    # representable. The members and their names are NFR-4-locked at the first release tag, and
    # the handshake with phase 5 is the design's R3: phase 5 populates through .build or
    # NONE.with (both validate), may add METHODS here and to TraceIdFlavour, may give the two
    # no-op classes their protocols, and may not rename or remove a member, add one, store
    # validity, change the sentinels, replace the flavour with a Symbol or hand this class a
    # second NONE.
    #
    # trace_state is a list of pairs, not a Hash: OBS-26 says "a vendor trace-state list" and W3C
    # tracestate is ordered, most recent vendor first, which a Hash would lose. trace_flags stays
    # the two-hex-char wire form OBS-26 fixes; a #sampled? predicate is deliberately not shipped
    # (CTX-14 does not ask for it, and phase 5 may add it, since adding a method widens).
    class Bundle < Data.define(
      :trace_id, :span_id, :trace_flags, :trace_state, :flavour, :remote, :span, :tracer_factory,
    )
      include Dexpace::Model

      private_class_method :new

      # OBS-26's reserved span-id sentinel: 16 hex zeros. Flavour-independent -- OBS-26 states
      # the span-id rule unqualified while OBS-27's flavours scope only the trace id, whose
      # sentinel therefore lives on TraceIdFlavour (P4-7).
      INVALID_SPAN_ID = ("0" * 16).freeze

      SPAN_ID_PATTERN = Regexp.new("\\A[0-9a-f]{16}\\z", timeout: 1.0)
      private_constant :SPAN_ID_PATTERN

      TRACE_FLAGS_PATTERN = Regexp.new("\\A[0-9a-f]{2}\\z", timeout: 1.0)
      private_constant :TRACE_FLAGS_PATTERN

      # The validating factory. trace_id:, span_id: and flavour: are required deliberately --
      # defaulting them would make "I forgot to pass a trace id" produce a silently untraced
      # bundle, invisible for exactly the reason CTX-15 names: every untraced call's identifiers
      # are identical, so nothing downstream can tell an accident from a policy. A caller who
      # wants the untraced value names Bundle::NONE.
      #
      # @param trace_id [String] the trace id, in the flavour's rendering or its sentinel
      # @param span_id [String] 16 lowercase hex chars, or INVALID_SPAN_ID
      # @param flavour [TraceIdFlavour] the trace-id encoding flavour
      # @param trace_flags [String] the two-hex-char W3C flags byte; "00" is unsampled
      # @param trace_state [Array<Array(String, String)>] the vendor trace-state list, in order
      # @param remote [Boolean] whether the trace context arrived from another service
      # @param span [Object] the active span; NO_SPAN when tracing is off
      # @param tracer_factory [#tracer] the per-operation tracer factory; NO_TRACER_FACTORY when
      #   tracing is off
      # @return [Bundle]
      def self.build(trace_id:, span_id:, flavour:, trace_flags: "00", trace_state: [],
                     remote: false, span: NO_SPAN, tracer_factory: NO_TRACER_FACTORY)
        new(
          trace_id: trace_id, span_id: span_id, trace_flags: trace_flags,
          trace_state: trace_state, flavour: flavour, remote: remote,
          span: span, tracer_factory: tracer_factory,
        )
      end

      # Every clause OBS-26 makes a MUST is checked here and nowhere else: `#valid?` only
      # compares against the sentinels and would answer true for a malformed span id. Each
      # failure names its field (SEAM-29). The checks are split into the two identifiers and
      # the two wire fields so the constructor reads as one line per member.
      def initialize(trace_id:, span_id:, trace_flags:, trace_state:, flavour:, remote:, span:,
                     tracer_factory:)
        Model.required!("span", span)
        Model.required!("tracer_factory", tracer_factory)
        validate_identifiers!(flavour, trace_id, span_id)
        validate_wire_fields!(trace_flags, trace_state)

        super(
          trace_id: Model.frozen_string(trace_id), span_id: Model.frozen_string(span_id),
          trace_flags: Model.frozen_string(trace_flags), trace_state: Model.own(trace_state),
          flavour: flavour, remote: remote ? true : false, span: span,
          tracer_factory: tracer_factory,
        )
      end

      # Derived, not stored (P4-6): a function of trace_id and span_id. False for NONE and for
      # any bundle carrying either reserved sentinel (OBS-26).
      #
      # @return [Boolean]
      def valid?
        flavour.valid_trace_id?(trace_id) && span_id != INVALID_SPAN_ID
      end

      # Whether the trace context was propagated in from another service; false for NONE.
      #
      # @return [Boolean]
      def remote? = remote

      # The flavour must be a TraceIdFlavour, the trace id one that flavour renders -- the
      # sentinel or a value its pattern accepts -- and the span id OBS-26's 16 lowercase hex
      # chars or its reserved sentinel; OBS-27 does not scope the span id, so those two are the
      # accepted shapes under every flavour (P4-7).
      def validate_identifiers!(flavour, trace_id, span_id)
        Model.required!("trace_id", trace_id)
        Model.required!("span_id", span_id)
        Model.required!("flavour", flavour)
        unless flavour.is_a?(TraceIdFlavour)
          raise InvalidArgumentError, "flavour must be a TraceIdFlavour"
        end
        unless flavour.renders?(trace_id)
          raise InvalidArgumentError, "trace_id does not match flavour #{flavour.name.inspect}"
        end
        return if valid_span_id?(span_id)

        raise InvalidArgumentError, "span_id must be 16 lowercase hex chars (OBS-26)"
      end
      private :validate_identifiers!

      # OBS-26's two wire fields: the flags byte as two lowercase hex chars, and the vendor
      # trace-state list as pairs of Strings.
      def validate_wire_fields!(trace_flags, trace_state)
        Model.required!("trace_flags", trace_flags)
        unless trace_flags.is_a?(::String) && TRACE_FLAGS_PATTERN.match?(trace_flags)
          raise InvalidArgumentError, "trace_flags must be two lowercase hex chars (OBS-26)"
        end
        return if trace_state.is_a?(::Array) && trace_state.all? { |pair| string_pair?(pair) }

        raise InvalidArgumentError, "trace_state must be an array of two-element string pairs"
      end
      private :validate_wire_fields!

      def valid_span_id?(value)
        value == INVALID_SPAN_ID || (value.is_a?(::String) && SPAN_ID_PATTERN.match?(value))
      end
      private :valid_span_id?

      def string_pair?(value)
        value.is_a?(::Array) && value.size == 2 && value.all?(::String)
      end
      private :string_pair?

      # CTX-15's disabled-tracing default: the shared frozen singleton every untraced call
      # carries, with OBS-26's reserved sentinels as its values and the two no-op singletons in
      # its slots. CTX-4's call-key derivation stays call-unique across it because the counter,
      # not the bundle, supplies the uniqueness (CallKey.mint). Not defaulted into any context
      # builder: a caller names it, so an untraced chain is a decision and not an accident.
      NONE = build(
        trace_id: TraceIdFlavour::NONE.invalid_trace_id,
        span_id: INVALID_SPAN_ID,
        flavour: TraceIdFlavour::NONE,
      )
    end
  end
end
