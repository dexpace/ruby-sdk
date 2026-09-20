# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "serialization_error"
require_relative "witness"

module Dexpace
  module Serde
    # The value a `#dexpace_dump` returns for a field that must be OMITTED from the enclosing
    # object: Tristate::ABSENT's dump, and what a hand-written model returns for the same effect.
    # Native's walk drops a Hash entry whose walked value is this sentinel (SERDE-15), writes a wire
    # null for it inside an Array and at the top level (SERDE-20), and nothing else ever sees it.
    # A frozen singleton of a class a caller cannot name, with a stable textual form for the reason
    # SERDE-30 gives ABSENT and NULL theirs.
    class Omit
      # @return [String] "Omit"
      def to_s = "Omit"
      alias inspect to_s
    end
    private_constant :Omit

    # The frozen omission sentinel (see Omit).
    OMIT = Omit.new.freeze

    # The encode walk (P7-9): turns any value into codec-native Ruby -- Hash, Array, String,
    # Integer, Float, true, false, nil -- in the one place where SERDE-15's key omission, SERDE-20's
    # three degradations and SERDE-9's loud failure on an unencodable value all live, so a codec
    # adapter inherits them by calling `.of` and no model has to remember them.
    #
    # Design §7.3 puts the Absent-key omission in each model's own `#dexpace_dump`. It lives here
    # instead because SERDE-19 is a MUST whose named failure -- "absent this wiring, Absent and Null
    # become indistinguishable on the wire" -- is exactly what a per-model convention produces when
    # one model forgets, silently, in a PATCH. In the walk it is structural, which is the word §7.3
    # itself uses for what SERDE-19 needs; a model that omits its own Absent keys still works, the
    # walk simply has nothing to drop. It is also why `Native` and `OMIT` are public: a second codec
    # adapter (dexpace-serde-oj, post-v1) calls `.of` and inherits tri-state encoding, which is
    # design §3.4's "no second code path in core" made concrete.
    #
    # The seven rules, in order:
    #
    # 1. nil, true, false, an Integer and a Float pass through; a String passes through with no
    #    retag (a mutable one is copied and frozen, XCUT-15). A BINARY-tagged String is handed to
    #    the generator as it is: json refuses one holding invalid UTF-8 (a SerializationError here)
    #    and warns on one holding valid UTF-8, so text is encoded as UTF-8 before it reaches a
    # codec.
    # 2. Anything answering `#dexpace_dump` (DUMP_METHOD) is replaced by its dump and RE-WALKED --
    #    the model case, the Tristate case and the hand-written case are one branch, and it wins
    #    over an `encoders:` entry for the same class.
    # 3. A Hash: every value walked, an entry whose walked value is OMIT dropped (SERDE-15), keys
    #    coerced from String or Symbol to String and anything else refused -- a key is a name, and
    #    an Integer or an object silently stringified is the kind of quiet mistake this walk exists
    #    to refuse.
    # 4. An Array: every element walked, an element that walks to OMIT written as nil (SERDE-20).
    # 5. At the top level, a value that walks to OMIT is nil (SERDE-20: "emit a wire null for both
    #    Absent and Null rather than throwing").
    # 6. A class present in `encoders:` -- by exact class first, then the first entry the value
    #    `is_a?`, in the table's order -- is replaced by `encoders[klass].call(value)` and
    # re-walked. This is the only hook, and it is what carries the adapter's ISO-8601 default
    # (design §3.4) without core naming ::Time as a policy: core ships the table EMPTY.
    # 7. Anything else -- a Symbol, a Time with no encoder, an arbitrary object -- raises
    #    SerializationError NAMING THE CLASS, the loud failure verified fact 3 shows ::JSON.generate
    #    will not give (it returns the object's `#inspect` as a JSON string).
    #
    # The walk returns fresh collections and never aliases a caller's (XCUT-15). A cyclic object
    # graph and an encoder that returns a value of its own class both recurse without bound; both
    # are caller mistakes, and neither is one a codec's own nesting cap can see because the walk
    # runs before the generator does.
    module Native
      extend self

      # Core's default: no encoder at all.
      none = {} #: Hash[Module, untyped]
      NO_ENCODERS = none.freeze
      private_constant :NO_ENCODERS

      # Walks `value` into codec-native Ruby.
      #
      # @param value [Object] anything: a model, a Tristate, a Hash, an Array, a scalar
      # @param encoders [Hash{Class => #call}] the one hook, empty by default
      # @return [Hash, Array, String, Integer, Float, true, false, nil]
      # @raise [Dexpace::Serde::SerializationError] on a value no rule accepts, naming its class
      # @raise [Dexpace::InvalidArgumentError] on an `encoders:` that is not a Hash of Class to
      #   callable
      def of(value, encoders: NO_ENCODERS)
        table = encoders!(encoders)
        walked = walk(value, table)
        walked.equal?(OMIT) ? nil : walked
      end

      private

      def encoders!(encoders)
        unless encoders.is_a?(::Hash) && encoders.all? do |k, v|
          k.is_a?(::Module) && v.respond_to?(:call)
        end
          raise InvalidArgumentError,
                "encoders must be a Hash of Class to #call, got #{encoders.class}"
        end

        encoders
      end

      def walk(value, encoders)
        return value if native_scalar?(value) || value.equal?(OMIT)
        return Model.frozen_string(value) if value.is_a?(::String)
        return walk(value.public_send(DUMP_METHOD), encoders) if value.respond_to?(DUMP_METHOD)
        return walk_hash(value, encoders) if value.is_a?(::Hash)
        return walk_array(value, encoders) if value.is_a?(::Array)

        walk_encoded(value, encoders)
      end

      def native_scalar?(value)
        value.nil? || value.equal?(true) || value.equal?(false) ||
          value.is_a?(::Integer) || value.is_a?(::Float)
      end

      def walk_hash(hash, encoders)
        out = {} #: Hash[String, untyped]
        hash.each_with_object(out) do |(key, raw), acc|
          walked = walk(raw, encoders)
          acc[key!(key)] = walked unless walked.equal?(OMIT)
        end
      end

      def walk_array(array, encoders)
        array.map do |raw|
          walked = walk(raw, encoders)
          walked.equal?(OMIT) ? nil : walked
        end
      end

      def walk_encoded(value, encoders)
        encoder = encoders[value.class] || encoders.find { |klass, _| value.is_a?(klass) }&.last
        if encoder.nil?
          raise SerializationError,
                "#{value.class} is not a codec-native value: it answers no ##{DUMP_METHOD} and " \
                "no encoder is configured for it"
        end

        walk(encoder.call(value), encoders)
      end

      def key!(key)
        case key
        when ::String then Model.frozen_string(key)
        when ::Symbol then key.name
        else raise SerializationError, "a Hash key must be a String or a Symbol, got #{key.class}"
        end
      end
    end
  end
end
