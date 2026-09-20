# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "deserialization_error"

module Dexpace
  module Serde
    # The `ctx` every witness receives (design §7.3's `.dexpace_load(parsed, ctx)`), and the ONE
    # raise site for a decode shape failure -- Model.required!'s discipline applied to a second
    # family of failures, so SERDE-13's "naming the target type, across every decode overload" is a
    # property of one method rather than of every witness anyone writes.
    #
    # Emphatically not phase 4a's Dexpace::Context: a decode happens with no pipeline in sight
    # (`serde.load(source, Pet)` is a legitimate call), coupling the codec seam to the execution
    # context would push against SEAM-2 and NFR-11, and no hand-written witness has a use for an
    # execution store. What a witness needs is the three jobs SERDE-13, SERDE-21 and SERDE-22 put on
    # the decode side and a bare parsed value cannot do alone: name the target on a wire null,
    # refuse the nine cross-shape coercions, and permit the two representation-preserving ones.
    #
    # A frozen value in the phase-1 shape: `Data.define(:path, :target)`, `.new` and `.[]` private,
    # a validating `.build`, `#with` through it. `path` is the JSON-Pointer-ish segment list
    # (Strings for keys, Integers for indices), rendered by #pointer as RFC 6901 with its `~0`/`~1`
    # escaping -- a standard with an unambiguous rule for a key containing `/`, where a dotted path
    # needs a bespoke quoting rule the first time a key contains a `.`. `target` is the decode's
    # target type as a NAME (a frozen String, or nil), never the witness object: a caller's class
    # inside a Data member would join `==` and `hash`, and a name is all the message needs.
    #
    # `#target` exists because SERDE-13's conformance clause decodes "the literal null into a
    # non-null DTO" and asserts the message names the DTO. A witness reached with nil calls
    # `ctx.object!(nil)`, which knows only the shape it wanted, so without the target the message
    # reads `expected Hash at /, got NilClass` and names Hash where the requirement asks for Pet.
    # #error! therefore renders the ROOT frame as `expected Pet (Hash) at /, got NilClass` when a
    # target is set, and the plain form everywhere else, because a nested frame's target IS its
    # expected shape. `#at` carries the target unchanged so it stays available for a diagnostic at
    # any depth without displacing the expectation at a nested path.
    #
    # Encoding takes no context (§7.3: "Ruby erases nothing -- every object carries its class"), so
    # there is no DumpContext, and phase 2's CONTRACT already says the same thing mechanically: only
    # #load takes a witness.
    class DecodeContext < Data.define(:path, :target)
      include Model

      private_class_method :new, :[]

      # The one context with no path and no target, shared: the common entry point allocates
      # nothing.
      empty = [] #: Array[String | Integer]
      EMPTY_PATH = empty.freeze
      private_constant :EMPTY_PATH

      ROOT = new(path: EMPTY_PATH, target: nil)
      private_constant :ROOT

      # The validating factory every construction path goes through, `#at`'s and `#with`'s
      # included. A caller descending into a document uses #at; this exists because Model#with
      # routes through it and because a generator building a context for a nested decode is a
      # legitimate caller.
      #
      # @param path [Array<String, Integer>] the segments from the document root, copied and frozen
      # @param target [String, nil] the decode's target type name, frozen
      # @return [DecodeContext]
      # @raise [Dexpace::InvalidArgumentError] naming the member, on a path that is not an Array
      #   of Strings and Integers or a target that is not a String
      def self.build(path:, target:)
        new(path: path, target: target)
      end

      # The entry point a decode starts from: an empty path and, when a witness is given, its name.
      #
      # The name is `Module#name` for a class or module (the ergonomic `serde.load(source, Pet)`
      # route), a String as it is, and the CLASS name for anything else -- a combinator instance
      # such as `List.of(Pet)` reports `Dexpace::Serde::List`; an anonymous class has no name and
      # gets no target, so its message keeps the plain form. Set at the decode's entry point and
      # never by a nil check inside #load: SERDE-20 requires a top-level null to decode to Null
      # through `Tristate.of` and to nil through `Nullable.of`, and neither of those ever calls
      # #object! on nil, so nothing raises and nothing needs an exemption.
      #
      # @param target [Module, String, Object, nil] the witness, or its name
      # @return [DecodeContext] frozen; the shared instance when no target is given
      def self.root(target: nil)
        return ROOT if target.nil?

        name =
          case target
          when ::Module then target.name
          when ::String then target
          else target.class.name
          end
        name.nil? ? ROOT : new(path: EMPTY_PATH, target: name)
      end

      def initialize(path:, target:)
        segments = Model.required!("path", path)
        unless segments.is_a?(::Array) && segments.all? { |segment| segment?(segment) }
          raise InvalidArgumentError, "path must be an Array of String and Integer segments"
        end
        unless target.nil? || target.is_a?(::String)
          raise InvalidArgumentError, "target must be a String or nil"
        end

        super(path: Model.own(segments), target: target.nil? ? nil : Model.frozen_string(target))
      end

      # A child context one segment deeper, carrying the same target. The receiver is untouched.
      #
      # @param segment [String, Integer] an object key or an array index
      # @return [DecodeContext]
      # @raise [Dexpace::InvalidArgumentError] on a segment of any other class
      def at(segment)
        unless segment?(segment)
          raise InvalidArgumentError,
                "segment must be a String or an Integer"
        end

        self.class.build(path: path + [segment], target: target)
      end

      # The path as an RFC 6901 JSON Pointer: `""` for the document root, otherwise one `/`-prefixed
      # segment per level with `~` written `~0` and `/` written `~1`, in that order.
      #
      # @return [String]
      def pointer
        path.map { |segment| "/#{segment.to_s.gsub("~", "~0").gsub("/", "~1")}" }.join
      end

      # SERDE-21: a JSON object, or a shape failure.
      #
      # @param value [Object] the parsed value
      # @param key [String, Integer, nil] one segment appended to the path for the message only
      # @return [Hash]
      # @raise [Dexpace::Serde::DeserializationError]
      def object!(value, key: nil)
        return value if value.is_a?(::Hash)

        error!(expected: "Hash", actual: value, key: key)
      end

      # SERDE-21: a JSON array, or a shape failure.
      #
      # @param value [Object] the parsed value
      # @param key [String, Integer, nil] one segment appended to the path for the message only
      # @return [Array]
      # @raise [Dexpace::Serde::DeserializationError]
      def array!(value, key: nil)
        return value if value.is_a?(::Array)

        error!(expected: "Array", actual: value, key: key)
      end

      # SERDE-21/SERDE-22: a String, the empty String included; never a coerced scalar.
      #
      # @param value [Object] the parsed value
      # @param key [String, Integer, nil] one segment appended to the path for the message only
      # @return [String]
      # @raise [Dexpace::Serde::DeserializationError]
      def string!(value, key: nil)
        return value if value.is_a?(::String)

        error!(expected: "String", actual: value, key: key)
      end

      # SERDE-21: an Integer; a Float (1.0 included), a numeric String and a boolean are all
      # refused, because each is a lossy or cross-shape coercion the requirement names.
      #
      # @param value [Object] the parsed value
      # @param key [String, Integer, nil] one segment appended to the path for the message only
      # @return [Integer]
      # @raise [Dexpace::Serde::DeserializationError]
      def integer!(value, key: nil)
        return value if value.is_a?(::Integer)

        error!(expected: "Integer", actual: value, key: key)
      end

      # SERDE-22: a Float, or an Integer WIDENED to one -- the one method here with a permission
      # rather than a prohibition.
      #
      # @param value [Object] the parsed value
      # @param key [String, Integer, nil] one segment appended to the path for the message only
      # @return [Float]
      # @raise [Dexpace::Serde::DeserializationError]
      def float!(value, key: nil)
        return value if value.is_a?(::Float)
        # SERDE-22: numeric widening of an integer into a floating-point target is representation-
        # preserving and MUST be permitted, even though SERDE-21 forbids the reverse narrowing.
        return value.to_f if value.is_a?(::Integer)

        error!(expected: "Float", actual: value, key: key)
      end

      # SERDE-21: exactly `true` or `false`; `"true"`, `1` and `0` are refused.
      #
      # @param value [Object] the parsed value
      # @param key [String, Integer, nil] one segment appended to the path for the message only
      # @return [Boolean]
      # @raise [Dexpace::Serde::DeserializationError]
      def boolean!(value, key: nil)
        return value if value.equal?(true) || value.equal?(false)

        error!(expected: "Boolean", actual: value, key: key)
      end

      # SERDE-13 for a witness that knows its own target: any non-nil value passes through and nil
      # is refused with the caller's target named. `false` is a present value.
      #
      # @param value [Object] the parsed value
      # @param target [String] the type name the message should carry
      # @param key [String, Integer, nil] one segment appended to the path for the message only
      # @return [Object] `value`
      # @raise [Dexpace::Serde::DeserializationError]
      def present!(value, target, key: nil)
        return value unless value.nil?

        error!(expected: target, actual: value, key: key)
      end

      # The ONE raise site. The message form is fixed here -- `expected <expected> at <pointer>,
      # got <actual class>`, with the root frame naming the decode's target when one was set --
      # which is what makes SERDE-13's "naming the target type" and SERDE-21's "surface as a
      # deserialization failure" properties of this method rather than of every witness.
      #
      # @param expected [String] the shape or type the caller wanted
      # @param actual [Object] the value it got; the message names its class
      # @param key [String, Integer, nil] one segment appended to the path for the message only
      # @raise [Dexpace::Serde::DeserializationError] always
      def error!(expected:, actual:, key: nil)
        frame = key.nil? ? self : at(key)
        # SERDE-13: at the ROOT frame the expected shape is not the target -- a null decoded into
        # Pet reports `expected Hash`, which names the wrong thing -- so the root frame names both.
        # A nested frame's target IS its expected shape, so it renders the plain form.
        wanted =
          if frame.path.empty? && !frame.target.nil? && frame.target != expected
            "#{frame.target} (#{expected})"
          else
            expected
          end
        where = frame.path.empty? ? "/" : frame.pointer
        raise DeserializationError, "expected #{wanted} at #{where}, got #{actual.class}"
      end

      private

      def segment?(segment)
        segment.is_a?(::String) || segment.is_a?(::Integer)
      end
    end
  end
end
