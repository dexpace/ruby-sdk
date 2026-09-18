# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "securerandom"
require_relative "../model"

module Dexpace
  # The instrumentation subsystem: the correlation bundle every execution context carries and the
  # values it is built from. Namespaced because design §8.1 names Dexpace::Instrumentation::Bundle
  # itself, and a subsystem the design names with a namespace keeps it (P1-1).
  module Instrumentation
    # OBS-27's trace-id encoding flavours, and the value CTX-14's "a trace-id encoding flavor"
    # slot holds: a frozen Data over a frozen table with an .of factory (type-system/545949a5),
    # never a case statement or a bare Symbol -- the per-flavour behaviour, a pattern, a sentinel
    # and a range, is data, not code. Phase 5c's #generate_trace_id is the ONE exception to that
    # sentence and P5-50 records why: generation is behaviour a member cannot hold, a fourth
    # member holding a callable would be redefinition (boundary 10 forbids adding a Data
    # member, since it changes the generated ==, hash and to_h under every Bundle::NONE
    # comparison), and a table keyed on the name outside the Data is the case statement wearing
    # a hash.
    #
    # The flavour governs the TRACE id only. CTX-14's words are "a trace-id encoding flavor",
    # OBS-27's scope is "trace-id generation", and OBS-26 states the span-id rule unqualified, so
    # a Datadog-flavoured bundle carries a decimal trace id and a hex span id. That reads oddly
    # and it is what the two requirements say together (Bundle::INVALID_SPAN_ID is the one
    # span-id sentinel; P4-7). No span-id generator ships (P5-44): OBS-26 states the span-id rule
    # as a validity rule Bundle.build already enforces, and core creates no spans.
    class TraceIdFlavour < Data.define(:name, :trace_id_pattern, :invalid_trace_id, :max_value)
      # OBS-27's coerced W3C draw: the lowest non-zero 128-bit value, 31 hex zeros and a one.
      COERCED_W3C_TRACE_ID = "#{"0" * 31}1".freeze
      private_constant :COERCED_W3C_TRACE_ID

      # The exclusive bound of a Datadog draw: 2**64, as a shift for the reason DATADOG gives.
      DATADOG_DRAW_BOUND = 1 << 64
      private_constant :DATADOG_DRAW_BOUND
      include Dexpace::Model

      private_class_method :new

      # The validating factory. `max_value` is nil where the pattern is the whole rule.
      #
      # @param name [Symbol] the flavour's name, what .of resolves
      # @param trace_id_pattern [Regexp] the shape a renderable trace id has, anchored
      # @param invalid_trace_id [String] this flavour's reserved invalid sentinel
      # @param max_value [Integer, nil] the largest integer a rendering may denote
      # @return [TraceIdFlavour]
      def self.build(name:, trace_id_pattern:, invalid_trace_id:, max_value: nil)
        new(
          name: name, trace_id_pattern: trace_id_pattern, invalid_trace_id: invalid_trace_id,
          max_value: max_value,
        )
      end

      # Every member but the range is required (SEAM-29's one message form).
      def initialize(name:, trace_id_pattern:, invalid_trace_id:, max_value:)
        Model.required!("name", name)
        Model.required!("trace_id_pattern", trace_id_pattern)
        Model.required!("invalid_trace_id", invalid_trace_id)

        super(
          name: name, trace_id_pattern: trace_id_pattern,
          invalid_trace_id: Model.frozen_string(invalid_trace_id), max_value: max_value,
        )
      end

      # A trace id that identifies a real trace under this flavour: renderable and not the
      # sentinel (OBS-26's "an all-zero trace/span id MUST be treated as invalid/no-trace").
      #
      # @param trace_id [String]
      # @return [Boolean]
      def valid_trace_id?(trace_id)
        trace_id != invalid_trace_id && renderable?(trace_id)
      end

      # A trace id a bundle of this flavour may carry at all: the sentinel, or a renderable
      # value. This is what Bundle's own validation asks; the two predicates disagree at exactly
      # one input, the sentinel, which is why both exist.
      #
      # @param trace_id [String]
      # @return [Boolean]
      def renders?(trace_id)
        trace_id == invalid_trace_id || renderable?(trace_id)
      end

      # The pattern fixes the SHAPE and max_value fixes the RANGE, because a digit count cannot
      # express one: OBS-27's Datadog flavour is "a 64-bit unsigned integer rendered as a decimal
      # string", and \A[0-9]{1,20}\z also accepts 99999999999999999999, which is larger than
      # 2**64 - 1. The bound is a member rather than a branch so the table stays the whole of the
      # per-flavour behaviour; nil means the pattern is the whole rule (both hex flavours).
      def renderable?(trace_id)
        return false unless trace_id.is_a?(::String) && trace_id_pattern.match?(trace_id)

        bound = max_value
        bound.nil? || trace_id.to_i <= bound
      end
      private :renderable?

      # OBS-27's generation, per flavour: W3C draws 128 bits and renders them as 32 lowercase hex
      # chars (SecureRandom#hex emits lowercase by construction, so nothing is case-folded);
      # DATADOG draws a 64-bit unsigned integer and renders it decimal; NONE "always yields the
      # invalid sentinel", which is not an error. A zero draw is coerced to the lowest non-zero
      # value of the flavour -- a substitution and not a redraw, because "a zero draw MUST be
      # coerced to a non-zero value" is the requirement's own word and a redraw loop against an
      # injected always-zero generator never terminates; a real CSPRNG reaches the branch with
      # probability 2**-128 and 2**-64, so the substitution's determinism costs nothing.
      #
      # The randomness source is the CSPRNG path (XCUT-21's), which keeps it a separate code path
      # from CFG-32's non-cryptographic UUID (boundary 8). `generator` is a test seam and not
      # requirement surface: the coercion is unreachable by sampling, so a test injects an object
      # answering `#hex(bytes)` and `#random_number(max)` -- SecureRandom's own two methods,
      # which a seeded `Random` also has -- rather than swapping a module process-wide. Positional
      # and defaulted, so the production call allocates nothing beyond the id itself.
      #
      # @param generator [#hex, #random_number] the randomness source; SecureRandom by default
      # @return [String] a frozen trace id valid under this flavour, or NONE's sentinel
      # @raise [InvalidArgumentError] for a flavour outside OBS-27's three (P5-50)
      def generate_trace_id(generator = ::SecureRandom)
        case name
        when :w3c
          drawn = generator.hex(16)
          drawn == invalid_trace_id ? COERCED_W3C_TRACE_ID : drawn.freeze
        when :datadog
          drawn = generator.random_number(DATADOG_DRAW_BOUND)
          (drawn.zero? ? 1 : drawn).to_s.freeze
        when :none
          invalid_trace_id
        else
          raise InvalidArgumentError, "no trace-id generator for flavour #{name.inspect}"
        end
      end

      # OBS-27's no-op flavour: "always yields the invalid sentinel". The pattern matches nothing,
      # so only OBS-26's 32 hex zeros renders -- a disabled-tracing bundle carries no trace id of
      # its own. The sentinel is OBS-26's exact value and not a flavour-specific zero draw, so
      # Bundle::NONE carries the pair CTX-15 names verbatim (P4-7).
      NONE = build(
        name: :none,
        trace_id_pattern: Regexp.new("\\A(?!)\\z", timeout: 1.0),
        invalid_trace_id: "0" * 32,
      )

      # OBS-27's W3C flavour: a 128-bit value rendered as 32 lowercase hex chars. Lowercase-only,
      # and an uppercase input is rejected rather than folded (OBS-26).
      W3C = build(
        name: :w3c,
        trace_id_pattern: Regexp.new("\\A[0-9a-f]{32}\\z", timeout: 1.0),
        invalid_trace_id: "0" * 32,
      )

      # OBS-27's Datadog flavour: a 64-bit unsigned integer rendered as a decimal string. Its own
      # zero draw is "0" -- the one OBS-27 says "MUST be coerced to a non-zero value" -- and is
      # distinct from OBS-26's 32-hex-zero sentinel (P4-7). The bound is 2**64 - 1, spelled as a
      # shift because rbs types Integer#** as Numeric and strict Steep refuses it for an Integer?.
      DATADOG = build(
        name: :datadog,
        trace_id_pattern: Regexp.new("\\A[0-9]{1,20}\\z", timeout: 1.0),
        invalid_trace_id: "0",
        max_value: (1 << 64) - 1,
      )

      # The closed set, in OBS-27's order. Phase 5 may add a method to the flavour; it may not
      # replace the type with a Symbol (roadmap obligation 1).
      ALL = [NONE, W3C, DATADOG].freeze

      # Resolves a name against the closed set. Raises on an unrecognised one -- the
      # Protocol.parse behaviour, not the deliberately total Status.of one, because a flavour is
      # a closed set and a status code is not.
      #
      # @param name [Symbol] `:none`, `:w3c` or `:datadog`
      # @return [TraceIdFlavour] the shared frozen instance
      # @raise [InvalidArgumentError] on any other name
      def self.of(name)
        ALL.find { |flavour| flavour.name == name } ||
          raise(InvalidArgumentError, "unrecognised trace-id flavour: #{name.inspect}")
      end
    end
  end
end
