# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # OBS-6 and OBS-7: total field-value rendering with a byte-bounded truncation. Every value
    # an event carries passes through .render on the way to the sink, inside a `rescue
    # StandardError` that substitutes `[unrenderable <ClassName>]` -- around BOTH halves of
    # OBS-6's `SimpleClassName: message` form, because an exception class whose #message raises
    # propagates from the message read, not the class-name read; around #inspect, because a
    # collection's rendering calls #to_s on everything it holds; and with a nil guard on
    # Class#name, because `Class.new(StandardError).name` is nil and anonymous error classes are
    # what a test suite and a metaprogrammed adapter both produce (verified fact 8).
    #
    # The cap is a BYTE figure (P5-29): "bounded maximum length (reference: 8 KiB)" is a memory
    # bound only under the byte reading -- `("é" * 5000)` is 5,000 characters and 10,000 bytes --
    # and a byte slice of a multibyte String is not a valid String, so the slice is scrubbed
    # before the marker goes on. The marker is ASCII so it concatenates onto any ASCII-compatible
    # encoding, BINARY included. Primitives are exempt, as OBS-7 says.
    #
    # A private_constant (P2-15, P4-3): its contract is Event's, asserted through Event#field and
    # #emit, and it is no service core offers.
    module Render
      # OBS-7's reference bound, in bytes.
      MAX_VALUE_BYTES = 8 * 1024
      # OBS-7's suffix. ASCII only, so it concatenates onto a BINARY or a Latin-1 rendering.
      TRUNCATION_MARKER = "...[truncated]"
      # OBS-3's spelling of a null value: the literal String, never a dropped key.
      NULL = "null"

      # Renders one field value totally: nil to "null", numerics and booleans through
      # type-preserving, an exception to `SimpleClassName: message`, a collection to its
      # bracketed #inspect form, a String and anything else to text, and every textual result
      # truncated on bytes. Never raises.
      #
      # @param value [Object] anything a caller handed Event#field, #cause or a context
      # @return [Object] the rendered value: a String, or the primitive itself
      def self.render(value)
        return NULL if value.nil?
        return value if primitive?(value)

        truncate(text_of(value))
      rescue ::StandardError
        unrenderable(value)
      end

      # OBS-6's type-preserving primitives: numerics and booleans. `case` rather than a class
      # list so a BasicObject, which answers no #is_a?, is never asked.
      #
      # @param value [Object]
      # @return [Boolean]
      def self.primitive?(value)
        case value
        when ::Integer, ::Float, ::Rational, ::Complex, true, false then true
        else false
        end
      end
      private_class_method :primitive?

      # The textual form, before truncation. A String is itself; an exception is its simple
      # class name and message; an Array or a Hash is its #inspect (the bracketed form); a
      # Symbol is its name; everything else is #to_s.
      def self.text_of(value)
        case value
        when ::String then value
        when ::Exception then "#{simple_class_name(value.class)}: #{value.message}"
        when ::Array, ::Hash then value.inspect
        when ::Symbol then value.name
        else value.to_s
        end
      end
      private_class_method :text_of

      # OBS-7 on bytes: #byteslice, then #scrub so a cut multibyte character does not leave an
      # invalid String, then the marker. A String that is not ASCII-compatible is transcoded
      # first so the ASCII marker can follow it.
      def self.truncate(text)
        unless text.encoding.ascii_compatible?
          text = text.encode(::Encoding::UTF_8, invalid: :replace, undef: :replace)
        end
        return text if text.bytesize <= MAX_VALUE_BYTES

        # Steep types #byteslice as nilable (it is, for an offset past the end); the offset is 0.
        head = text.byteslice(0, MAX_VALUE_BYTES) || +""
        head.scrub("") + TRUNCATION_MARKER
      end
      private_class_method :truncate

      # `SimpleClassName`: the last segment of the class name, or "Class" for an anonymous class,
      # whose #name is nil (verified fact 8).
      def self.simple_class_name(klass)
        name = klass.name
        name.nil? ? "Class" : name.split("::").last
      end
      private_class_method :simple_class_name

      # OBS-6's diagnostic placeholder. Reached through Kernel#class rather than #class, because a
      # BasicObject answers neither #class nor #to_s, and the placeholder must be reachable for it.
      def self.unrenderable(value)
        klass = ::Kernel.instance_method(:class).bind_call(value)
        "[unrenderable #{simple_class_name(klass)}]"
      rescue ::StandardError
        "[unrenderable Object]"
      end
      private_class_method :unrenderable
    end
    private_constant :Render
  end
end
